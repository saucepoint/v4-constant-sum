// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract CounterTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Counter hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    // function test_zeroForOne_positive() public {
    //     uint256 token0Before = token0.balanceOf(address(this));
    //     uint256 token1Before = token1.balanceOf(address(this));
    //     uint256 reserves0Before = token0.balanceOf(address(hook));

    //     // Perform a test swap //
    //     int256 amount = 10e18;
    //     bool zeroForOne = true;
    //     swap(key, zeroForOne, amount, ZERO_BYTES);
    //     // ------------------- //

    //     uint256 token0After = token0.balanceOf(address(this));
    //     uint256 token1After = token1.balanceOf(address(this));
    //     uint256 reserves0After = token0.balanceOf(address(hook));

    //     // paid token0
    //     assertEq(token0Before - token0After, uint256(amount));
    //     assertEq(reserves0After - reserves0Before, uint256(amount));

    //     // received token1
    //     assertEq(token1After - token1Before, uint256(amount));
    // }

    // function test_zeroForOne_negative() public {
    //     uint256 token0Before = token0.balanceOf(address(this));
    //     uint256 token1Before = token1.balanceOf(address(this));
    //     uint256 reserves0Before = token0.balanceOf(address(hook));

    //     // Perform a test swap: want 10 token1 //
    //     int256 amount = -10e18;
    //     bool zeroForOne = true;
    //     swap(key, zeroForOne, amount, ZERO_BYTES);
    //     // ------------------- //

    //     uint256 token0After = token0.balanceOf(address(this));
    //     uint256 token1After = token1.balanceOf(address(this));
    //     uint256 reserves0After = token0.balanceOf(address(hook));

    //     // paid token0
    //     assertEq(token0Before - token0After, uint256(-amount));
    //     assertEq(reserves0After - reserves0Before, uint256(-amount));

    //     // received token1
    //     assertEq(token1After - token1Before, uint256(-amount));
    // }

    // function test_oneForZero_positive() public {
    //     uint256 token0Before = token0.balanceOf(address(this));
    //     uint256 token1Before = token1.balanceOf(address(this));
    //     uint256 reserves1Before = token1.balanceOf(address(hook));

    //     // Perform a test swap //
    //     int256 amount = 10e18;
    //     bool zeroForOne = false;
    //     swap(key, zeroForOne, amount, ZERO_BYTES);
    //     // ------------------- //

    //     uint256 token0After = token0.balanceOf(address(this));
    //     uint256 token1After = token1.balanceOf(address(this));
    //     uint256 reserves1After = token1.balanceOf(address(hook));

    //     // paid token1
    //     assertEq(token1Before - token1After, uint256(amount));
    //     assertEq(reserves1After - reserves1Before, uint256(amount));

    //     // received token0
    //     assertEq(token0After - token0Before, uint256(amount));
    // }

    // function test_oneForZero_negative() public {
    //     uint256 token0Before = token0.balanceOf(address(this));
    //     uint256 token1Before = token1.balanceOf(address(this));
    //     uint256 reserves1Before = token1.balanceOf(address(hook));

    //     // Perform a test swap: want 10 token0 //
    //     int256 amount = -10e18;
    //     bool zeroForOne = false;
    //     swap(key, zeroForOne, amount, ZERO_BYTES);
    //     // ------------------- //

    //     uint256 token0After = token0.balanceOf(address(this));
    //     uint256 token1After = token1.balanceOf(address(this));
    //     uint256 reserves1After = token1.balanceOf(address(hook));

    //     // paid token1
    //     assertEq(token1Before - token1After, uint256(-amount));
    //     assertEq(reserves1After - reserves1Before, uint256(-amount));

    //     // received token0
    //     assertEq(token0After - token0Before, uint256(-amount));
    // }

    function test_no_v4_liquidity() public {
        vm.expectRevert("No v4 Liquidity allowed");
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }
}
