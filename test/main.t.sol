// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PoolManager} from "v4-core/PoolManager.sol";

import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";

import {Main} from "src/main.sol";
import { ILOLaunchpad } from "src/abstract/ILOLaunchpad.sol";



contract MainTest is Test {

    uint BASE_BPS = 10000;

    PoolManager UNI_V4;
    Main main;

    address admin = makeAddr("admin");
    address launcher = makeAddr("launcher");

    ERC20Mock launchToken;
    ERC20Mock usdc;

    function setUp() public {

        //UNI POOL manager
        UNI_V4 = new PoolManager(address(0));

        //deloy contract
        vm.prank(admin);
        main = new Main(address(UNI_V4), address(UNI_V4));

        vm.startPrank(launcher);
        launchToken = new ERC20Mock();
        launchToken.mint(launcher,  1e34);
        usdc = new ERC20Mock();

    }



    function testTokenLaunch (
        address team, uint128 saleTarget, uint16 rewardFactorBps, uint24 poolFee, int24 tickSpacing, bool isNative) public returns (uint launchIndex) {

        vm.assume(tickSpacing > 1 && tickSpacing < 1000);

        uint balanceBefore = launchToken.balanceOf(address(main));
        uint unclaimedFeesBefore = main.protocolFee(address(launchToken));
        uint protocolFee = saleTarget * main.PROTOCOL_FEE() / BASE_BPS;

        address baseCurrency = isNative ? address(usdc) : address(usdc);

        PoolKey memory pool = PoolKey(
            Currency.wrap(address(launchToken)),
            Currency.wrap(baseCurrency),
            poolFee,
            tickSpacing,
            IHooks(address(main))
        );

        assertEq(main.poolId(keccak256(abi.encode(pool))), 0);

        ILOLaunchpad.LaunchData memory launchData = ILOLaunchpad.LaunchData({
            token: address(launchToken),
            baseCurrency: baseCurrency,
            saleTarget: saleTarget,
            totalSales: 10,
            rewardFactorBps: rewardFactorBps,
            poolFee: poolFee,
            tickSpacing: tickSpacing,
            presaleDuration: 60 days,
            vestingDuration: 30 days,
            launchedAt: 0,
            updatedAt: 0,
            sqrtPriceX96: 100000000000000,
            launchStatus: ILOLaunchpad.LaunchStatus.PRESALE
        });

        vm.startPrank(team);
        //mint and approve enough for the team
        launchToken.mint(team,  uint(saleTarget) * 2);
        launchToken.approve(address(main),  uint(saleTarget) * 2);
        launchIndex = main.launchToken(launchData);
        vm.stopPrank();

        {

            ILOLaunchpad.LaunchData memory currentLaunch = main.getLaunchWithIndex(launchIndex);

            assertEq(currentLaunch.token, launchData.token);
            assertEq(currentLaunch.baseCurrency, launchData.baseCurrency);
            assertEq(currentLaunch.saleTarget, launchData.saleTarget);
            assertEq(currentLaunch.totalSales, 0);
            assertEq(currentLaunch.rewardFactorBps, launchData.rewardFactorBps);
            assertEq(currentLaunch.presaleDuration, launchData.presaleDuration);
            assertEq(currentLaunch.vestingDuration, launchData.vestingDuration);
            assertEq(currentLaunch.launchedAt, uint40(block.timestamp));
            assertEq(currentLaunch.updatedAt, uint40(block.timestamp));
            //assertEq(currentLaunch.launchStatus, ILOLaunchpad.LaunchStatus.PRESALE);
            assertEq(launchToken.balanceOf(address(main)) - balanceBefore, saleTarget + protocolFee);
            assertEq(main.protocolFee(address(launchToken)) - unclaimedFeesBefore, protocolFee); //protocolFee
            assertEq(main.poolId(keccak256(abi.encode(pool))), launchIndex);


            //Uinswap Asset
            assertEq(currentLaunch.baseCurrency, launchData.baseCurrency);

        }


    }


}