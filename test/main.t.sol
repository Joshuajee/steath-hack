// SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import "forge-std/Test.sol";
import {PositionManager} from "v4-periphery/PositionManager.sol";

import {PoolManager} from "v4-core/PoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IWETH9} from "v4-periphery/interfaces/external/IWETH9.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {PositionDescriptor} from "v4-periphery/PositionDescriptor.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

import {Main} from "src/main.sol";
import { ILOLaunchpad } from "src/abstract/ILOLaunchpad.sol";



contract MainTest is Test, DeployPermit2 {

    uint BASE_BPS = 10000;

    IAllowanceTransfer permit2;
    PositionDescriptor public positionDescriptor;
    IWETH9 public _WETH9 = IWETH9(address(new WETH()));

    IPoolManager UNI_V4;
    PositionManager posm;

    Main main;

    address admin = makeAddr("admin");
    address launcher = makeAddr("launcher");

    ERC20Mock launchToken;
    ERC20Mock usdc;

    function setUp() public {

        //UNI POOL manager
        UNI_V4 =  IPoolManager(address(new PoolManager(address(0))));

        permit2 = IAllowanceTransfer(deployPermit2());
        positionDescriptor = new PositionDescriptor(UNI_V4, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, "ETH");
        posm = new PositionManager(UNI_V4, permit2, 100_000, positionDescriptor, _WETH9);

        //deloy contract
        vm.prank(admin);

        address flags = address(
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );

        bytes memory constructorArgs = abi.encode(address(UNI_V4), payable(address(posm))); //Add all the necessary constructor arguments from the hook
        deployCodeTo("main.sol:Main", constructorArgs, flags);
        main = Main(flags);

        launchToken = new ERC20Mock();
        usdc = new ERC20Mock();

    }

    function mintAndApprove(address user, bool isNative) internal {
        launchToken.mint(user, type(uint128).max);
        launchToken.approve(address(main), type(uint).max);
        if (isNative) {

        } else {
            usdc.mint(user, type(uint128).max);
            usdc.approve(address(main), type(uint).max);
        }
    }

    function orderCurrency(address tokenA, address tokenB) internal returns (address token0, address token1) {
       (token0, token1) = tokenA < tokenB ? (tokenB, tokenA) : (tokenA, tokenB);
    }


    function testTokenLaunch (
        address team, uint128 saleTarget, uint16 rewardFactorBps, uint24 poolFee, int24 tickSpacing, bool isNative) public returns (uint launchIndex) {

        vm.assume(tickSpacing > 1 && tickSpacing < 1000 && poolFee <= 1e6);

        uint balanceBefore = launchToken.balanceOf(address(main));
        uint unclaimedFeesBefore = main.protocolFee(address(launchToken));
        uint protocolFee = saleTarget * main.PROTOCOL_FEE() / BASE_BPS;

        address baseCurrency = isNative ? address(usdc) : address(usdc);

        (address token0, address token1) = orderCurrency(baseCurrency, address(launchToken));

        PoolKey memory pool = PoolKey(
            Currency.wrap(token0),
            Currency.wrap(token1),
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
            sqrtPriceX96: uint160((2 ** 96)) / 1,
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
            //assertEq(main.poolId(keccak256(abi.encode(pool))), launchIndex);


            //Uinswap Asset
            assertEq(currentLaunch.baseCurrency, launchData.baseCurrency);

        }

    }

    function testAddLiquidity (address lp, uint128 saleTarget, uint16 rewardFactorBps, uint24 poolFee, int24 tickSpacing, bool isNative) public returns (uint launchIndex) {

        launchIndex = testTokenLaunch(launcher, saleTarget, rewardFactorBps, poolFee, tickSpacing, isNative);

        address baseCurrency = isNative ? address(usdc) : address(usdc);

        (address token0, address token1) = orderCurrency(baseCurrency, address(launchToken));

        PoolKey memory pool = PoolKey(
            Currency.wrap(token0),
            Currency.wrap(token1),
            poolFee,
            tickSpacing,
            IHooks(address(0))
        );

        vm.startPrank(lp);
        mintAndApprove(lp, false);
        main.addLiquidity(pool, lp, 1 ether);
        vm.stopPrank();


    }


}