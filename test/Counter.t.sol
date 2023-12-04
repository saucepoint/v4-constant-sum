// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Constants} from "@uniswap/v4-core/contracts/../test/utils/Constants.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {HookTest} from "./utils/HookTest.sol";
import {Counter} from "../src/Counter.sol";
import {HookMiner} from "./utils/HookMiner.sol";

contract CounterTest is HookTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Counter hook;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_MODIFY_POSITION_FLAG | Hooks.NO_OP_FLAG | Hooks.ACCESS_LOCK_FLAG
        );
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(Counter).creationCode, abi.encode(address(manager)));
        hook = new Counter{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "CounterTest: hook address mismatch");

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        initializeRouter.initialize(poolKey, Constants.SQRT_RATIO_1_1, ZERO_BYTES);

        PoolKey memory hooklessKey =
            PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), 3000, 60, IHooks(address(0x0)));
        initializeRouter.initialize(hooklessKey, Constants.SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pair, so there are tokens that we can take
        modifyPositionRouter.modifyPosition(
            hooklessKey, IPoolManager.ModifyPositionParams(-60, 60, 10000 ether), ZERO_BYTES
        );

        // Provide liquidity to the hook, so there are tokens on the constant sum curve
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        hook.addLiquidity(poolKey, 100e18);
    }

    function test_zeroForOne_positive() public {
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        // Perform a test swap //
        int256 amount = 10e18;
        bool zeroForOne = true;
        swap(poolKey, amount, zeroForOne, ZERO_BYTES);
        // ------------------- //

        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));

        // paid token0
        assertEq(token0Before - token0After, uint256(amount));

        // received token1
        assertEq(token1After - token1Before, uint256(amount));
    }

    function test_zeroForOne_negative() public {
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        // Perform a test swap: want 10 token1 //
        int256 amount = -10e18;
        bool zeroForOne = true;
        swap(poolKey, amount, zeroForOne, ZERO_BYTES);
        // ------------------- //

        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));

        // paid token0
        assertEq(token0Before - token0After, uint256(-amount));

        // received token1
        assertEq(token1After - token1Before, uint256(-amount));
    }

    function test_oneForZero_positive() public {
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        // Perform a test swap //
        int256 amount = 10e18;
        bool zeroForOne = false;
        swap(poolKey, amount, zeroForOne, ZERO_BYTES);
        // ------------------- //

        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));

        // paid token1
        assertEq(token1Before - token1After, uint256(amount));

        // received token0
        assertEq(token0After - token0Before, uint256(amount));
    }

    function test_oneForZero_negative() public {
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        // Perform a test swap: want 10 token0 //
        int256 amount = -10e18;
        bool zeroForOne = false;
        swap(poolKey, amount, zeroForOne, ZERO_BYTES);
        // ------------------- //

        uint256 token0After = token0.balanceOf(address(this));
        uint256 token1After = token1.balanceOf(address(this));

        // paid token1
        assertEq(token1Before - token1After, uint256(-amount));

        // received token0
        assertEq(token0After - token0Before, uint256(-amount));
    }
}
