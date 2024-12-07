// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {PositionManager} from "v4-periphery/PositionManager.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {LiquidityAmounts} from "./oos/LiquidityAmounts.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {ILOLaunchpad} from "./abstract/ILOLaunchpad.sol";

//import {ILOHook} from "./abstract/ILOHook.sol";

import "forge-std/console.sol";


contract Main is ILOLaunchpad {

    using SafeERC20 for IERC20;


    PositionManager public V4_POSITION_MANAGER;


    constructor (address uni_v4, address payable positionManager) ILOLaunchpad(uni_v4) {
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

        emit Investment(launchIndex, mintedTokenId, liquidity, reward);

    }


    function claimVestedTokens(uint tokenId, address to) external {

        Vested memory vesting = vestedToken[tokenId];

        LaunchData memory launch = launchData[vesting.launchIndex];

        if (msg.sender != V4_POSITION_MANAGER.ownerOf(tokenId)) {
            //Todo approved should be able to claim
            revert NotTokenOwner();
        }

        IERC20(launch.token).safeTransfer(to, vesting.reward);

        delete vestedToken[tokenId];

    }



    /**
     * PRIVATE FUNCTONS
     */
    function _onlyUniV4() internal view {
        if (msg.sender != address(UNI_V4)) revert NotUniswap();
    }

}