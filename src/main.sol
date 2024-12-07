// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {PositionManager} from "v4-periphery/PositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";

import {BaseHook} from "v4-periphery/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {LiquidityAmounts} from "./oos/LiquidityAmounts.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ILOLaunchpad} from "./abstract/ILOLaunchpad.sol";


import "forge-std/console.sol";


contract Main is ILOLaunchpad, BaseHook {

    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;

    event Swap(uint indexed launchIndex, uint indexed tokenId, uint indexed liquidity);


    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    mapping(PoolId => uint256 count) public beforeSwapCount;
    mapping(PoolId => uint256 count) public afterSwapCount;

    mapping(PoolId => uint256 count) public beforeAddLiquidityCount;
    mapping(PoolId => uint256 count) public beforeRemoveLiquidityCount;


    PositionManager public V4_POSITION_MANAGER;


    constructor (address uni_v4, address payable positionManager) ILOLaunchpad(uni_v4) BaseHook(IPoolManager(address(V4_POSITION_MANAGER))) {
        V4_POSITION_MANAGER = PositionManager(positionManager);
    }


    
    function addLiquidity(PoolKey calldata pool, address recipient, uint value) external payable {
        LaunchData memory launch = getLaunchPoolKey(pool);
        bool baseIsNative = launch.baseCurrency == address(0);
        if (baseIsNative) {
            value = msg.value;
        } 
        (uint reward, uint investmentToken, uint investmentBase) = getLaunchInvestmentInfo(launch, value);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            launch.sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-MAX_TICK),
            TickMath.getSqrtPriceAtTick(MAX_TICK),
            investmentToken,
            investmentBase
        );
        console.log("---", reward, investmentToken, investmentBase);
        console.log("LQ: ", liquidity);
        IERC20(launch.token).forceApprove(address(V4_POSITION_MANAGER), investmentToken);
        if (!baseIsNative) {
            IERC20(launch.baseCurrency).forceApprove(address(V4_POSITION_MANAGER), investmentBase);
        }
        bytes[] memory params = new bytes[](2);
        bytes memory actions = abi.encodePacked(Actions.MINT_POSITION, Actions.SETTLE_PAIR);
        params[0] = abi.encode(pool, -MAX_TICK, MAX_TICK, liquidity, type(uint128).max, type(uint128).max, recipient, bytes("0"));
        params[1] = abi.encode(pool.currency0, pool.currency1);
        uint mintedTokenId = V4_POSITION_MANAGER.nextTokenId();
        V4_POSITION_MANAGER.modifyLiquidities{value: baseIsNative ? investmentBase : 0}(
            abi.encode(actions, params),
            block.timestamp + 60
        );
        uint launchIndex = poolId[keccak256(abi.encode(pool))];
        vestedToken[mintedTokenId] = Vested({reward: reward, launchIndex: launchIndex });
        //Update Pool status
        updatePoolStatus(launchIndex);
        emit Investment(launchIndex, mintedTokenId, liquidity, reward);
    }


    function claimVestedTokens(uint tokenId, address to) external {
        Vested memory vesting = vestedToken[tokenId];
        LaunchData memory launch = launchData[vesting.launchIndex];
        if (launch.launchStatus != LaunchStatus.LIVE) revert ("Cannot Remove Liquidity");
        if (msg.sender != V4_POSITION_MANAGER.ownerOf(tokenId)) {
            //Todo approved should be able to claim
            revert NotTokenOwner();
        }
        if (vesting.reward > 0) IERC20(launch.token).safeTransfer(to, vesting.reward);
        delete vestedToken[tokenId];
    }


    /**
     * HOOK FUNCTIONS
     */

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: true,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function beforeSwap(
        address, 
        PoolKey calldata key, 
        IPoolManager.SwapParams calldata, 
        bytes calldata
    ) external override returns (bytes4, BeforeSwapDelta, uint24) {
        _onlyUniV4();
        LaunchData memory launch = getLaunchPoolKey(key);
        if (launch.launchStatus == LaunchStatus.PRESALE) revert ("SWAP NOT ALLOWED IN PRESALE");
        if (launch.launchStatus == LaunchStatus.FAILED) revert ("SWAP NOT ALLOWED FOR FAILED POOLS");
        emit Swap(poolId[getPoolKeyHash(key)], 0, 0);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }


    function beforeRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        _onlyUniV4();
        LaunchData memory launch = getLaunchPoolKey(key);
        if (launch.launchStatus != LaunchStatus.LIVE || launch.launchStatus != LaunchStatus.FAILED) revert ("Cannot Remove Liquidity");
        emit Swap(poolId[getPoolKeyHash(key)], 0, 0);
        return BaseHook.beforeRemoveLiquidity.selector;
    }



    /**
     * PRIVATE FUNCTONS
     */
    function _onlyUniV4() internal view {
        if (msg.sender != address(UNI_V4)) revert NotUniswap();
    }

}