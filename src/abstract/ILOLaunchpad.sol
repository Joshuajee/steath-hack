// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";

import {ILOAdmin} from "./ILOAdmin.sol";

abstract contract ILOLaunchpad is ILOAdmin { 

    error NotUniswap();

    using SafeERC20 for IERC20;

    event Launch(uint indexed launchIndex);
    event Investment(uint indexed launchIndex, uint indexed tokenId, uint indexed liquidity, uint reward);

    enum LaunchStatus {
        PRESALE,
        VESTING,
        LIVE,
        FAILED
    }

    struct Vested {
        uint launchIndex;
        uint reward;
    }

    struct LaunchData {
        address token;
        address baseCurrency;
        uint128 saleTarget; 
        uint128 totalSales;
        uint16 rewardFactorBps; //10000 BPS means 1:1, so for every unit of base currency invested the LP get one unit of the prelaunch token
        uint24 poolFee;
        int24 tickSpacing;
        uint40 presaleDuration;
        uint40 vestingDuration;
        uint40 launchedAt;
        uint40 updatedAt;
        uint160   sqrtPriceX96;
        LaunchStatus launchStatus;
    }

    IPoolManager immutable public UNI_V4;

    mapping(bytes32 => uint) public poolId;
    mapping(uint => Vested) public vestedToken;

    //using array to store launches
    LaunchData [] internal launchData;

    constructor(address _uni_v4) //ILOHook(_uni_v4)
    {
        UNI_V4 = IPoolManager(_uni_v4);
        //Push an empty lauch to occupy index 0
        launchData.push();
    }

    //Todo sanity checks on sales target
    function launchToken (LaunchData memory _launchData)  external returns (uint256) {
        uint launchIndex = launchData.length;
        //The launch time to the current timestamp
        _launchData.launchedAt = uint40(block.timestamp);
        _launchData.updatedAt = uint40(block.timestamp);
        _launchData.totalSales = 0;
        _launchData.launchStatus = LaunchStatus.PRESALE;

        uint _protocolFee = _launchData.saleTarget * PROTOCOL_FEE / BASE_BPS;

        //send sales target plus protocol fees to the contract.
        IERC20(_launchData.token).safeTransferFrom(msg.sender, address(this), _launchData.saleTarget + _protocolFee);

        //save fee
        protocolFee[_launchData.token] += _protocolFee;

        launchData.push(_launchData);

        (address token0, address token1) = sortCurrency(_launchData.token, _launchData.baseCurrency);

        PoolKey memory pool = PoolKey(
            Currency.wrap(token0), 
            Currency.wrap(token1), 
            _launchData.poolFee, 
            _launchData.tickSpacing, 
            IHooks(address(this))
        );

        UNI_V4.initialize(pool, _launchData.sqrtPriceX96);

        poolId[keccak256(abi.encode(pool))] = launchIndex;

        emit Launch(launchIndex);

        return launchIndex;
    }

    function updatePoolStatus(uint launchIndex) public {
        
        LaunchData storage launch = launchData[launchIndex]; 

        if (launch.launchStatus == LaunchStatus.PRESALE) {

            if (launch.launchedAt + launch.presaleDuration > block.timestamp) {
                launch.launchStatus = LaunchStatus.FAILED;
                launch.updatedAt = uint40(block.timestamp);
            }

            if (launch.saleTarget == launch.totalSales) {
                launch.launchStatus = LaunchStatus.VESTING;
                launch.updatedAt = uint40(block.timestamp);
            }

        } else  if (launch.launchStatus == LaunchStatus.VESTING)  {

            if (launch.updatedAt + launch.vestingDuration > block.timestamp) {
                launch.launchStatus = LaunchStatus.LIVE;
                launch.updatedAt = uint40(block.timestamp);
            }

        }

    }

    /**
     * 
     * @param launchIndex the index of the launch to get
     * @return return the launch details
     */
    function getLaunchWithIndex(uint launchIndex) external view returns (LaunchData memory) {
        return launchData[launchIndex];
    }

    /**
     * 
     * @param poolKey the uniswap pool key of the launch to get
     * @return return the launch details
     */
    function getLaunchPoolKey(PoolKey calldata poolKey) public view returns (LaunchData memory) {
        return launchData[poolId[keccak256(abi.encode(poolKey))]];
    }

    /**
     * To display all the launches, for testing in production we will use subgraphs
     */
    function getAllLaunches () external view returns (LaunchData[] memory) {
        return launchData;
    }

     /**
     * Get investment and rewards
     * @param launchIndex Launch Index
     * @param value the amount of tokens passed
     * @return rewards the amount of token to reward LPs with i.e vested tokens
     * @return investmentToken the amount of tokens to invest for LP
     * @return investmentBase the amount of Base Token (ETH, USDC etc.) to invest for LP
     */
    function getLaunchInvestmentInfo(uint launchIndex, uint value) public view returns (uint rewards, uint investmentToken, uint investmentBase) {
        LaunchData memory launch = launchData[launchIndex]; 
        return getLaunchInvestmentInfo(launch, value);
    }

    /**
     * Get investment and rewards
     * @param launch Launch Struct  data
     * @param value the amount of tokens passed
     * @return rewards the amount of token to reward LPs with i.e vested tokens
     * @return investmentToken the amount of tokens to invest for LP
     * @return investmentBase the amount of Base Token (ETH, USDC etc.) to invest for LP
     */
    function getLaunchInvestmentInfo(LaunchData memory launch, uint value) public pure returns (uint rewards, uint investmentToken, uint investmentBase) {

        uint price;
        
        if (launch.token > launch.baseCurrency) {
            price = PRECISION / ((launch.sqrtPriceX96 / (2 ** 96)) ** 2);
        } else {
            price = PRECISION * ((launch.sqrtPriceX96 / (2 ** 96)) ** 2);
        }


        investmentBase = value;
        investmentToken = price * investmentBase / PRECISION;
        rewards = investmentToken * launch.rewardFactorBps / BASE_BPS;

        uint total = investmentToken + rewards;
        uint remainingTokens = launch.saleTarget - launch.totalSales;

        if (total > remainingTokens) {
            investmentToken = remainingTokens;
            investmentBase = investmentToken * PRECISION / price * investmentBase;
            rewards = investmentToken * launch.rewardFactorBps / BASE_BPS;
        }
    }

    function sortCurrency(address tokenA, address tokenB) public pure returns (address token0, address token1) {
       (token0, token1) = tokenA > tokenB ? (tokenB, tokenA) : (tokenA, tokenB);
    }


    function getPoolKeyHash(PoolKey calldata pool) public pure returns (bytes32) {
        return keccak256(abi.encode(pool));
    }



}

