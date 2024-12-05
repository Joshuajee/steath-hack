// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPositionManager} from "v4-periphery/interfaces/IPositionManager.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {ILOLaunchpad} from "./abstract/ILOLaunchpad.sol";
//import {ILOHook} from "./abstract/ILOHook.sol";

contract Main is ILOLaunchpad {

    IPositionManager public V4_POSITION_MANAGER;

    constructor (address uni_v4, address positionManager) ILOLaunchpad(uni_v4) {
        V4_POSITION_MANAGER = IPositionManager(positionManager);
    }



    function addLiquidity(PoolKey calldata pool, int24 tickLower, int24 tickUpper, uint128 liquidity, uint128 amount0Max, uint128 amount1Max) external {


        // V4_POSITION_MANAGER.mint(
        //     pool, tickLower, tickUpper, liquidity, amount0Max, amount1Max, msg.sender, block.timestamp + 60
        // );

    }


    function claimVestedTokens(uint launchId, address to) external {

    }

}