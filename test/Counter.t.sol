// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Counter} from "../src/Counter.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract CounterTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    Counter hook;
    PoolKey poolKey;
    PoolId poolId;
    PoolKey hooklessKey;

    function setUp() public {
        Deployers.deployFreshManagerAndRouters();
        Deployers.deployMintAndApprove2Currencies();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQ_FLAG);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(Counter).creationCode, abi.encode(address(manager)));
        hook = new Counter{salt: salt}(IPoolManager(address(manager)));
        require(address(hook) == hookAddress, "CounterTest: hook address mismatch");

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(address(hook)));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        hooklessKey = PoolKey(
            currency0, currency1, 3000, 60, IHooks(address(0x0))
        );
        manager.initialize(hooklessKey, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pair, so there are tokens that we can take
        modifyLiquidityRouter.modifyLiquidity(
            hooklessKey, IPoolManager.ModifyLiquidityParams(-60, 60, 100000 ether), ZERO_BYTES
        );

        // Provide liquidity to the hook, so there are tokens on the constant sum curve
        IERC20(Currency.unwrap(currency0)).approve(address(hook), type(uint256).max);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), type(uint256).max);
        hook.addLiquidity(poolKey, 100e18);
    }

    function test_zeroForOne_positive() public {
        uint256 currency0Before = currency0.balanceOf(address(this));
        uint256 currency1Before = currency1.balanceOf(address(this));
        uint256 reserves0Before = currency0.balanceOf(address(hook));

        // Perform a test swap //
        int256 amount = 10e18;
        bool zeroForOne = true;
        swap(poolKey, zeroForOne, amount, ZERO_BYTES);
        // ------------------- //

        uint256 currency0After = currency0.balanceOf(address(this));
        uint256 currency1After = currency1.balanceOf(address(this));
        uint256 reserves0After = currency0.balanceOf(address(hook));

        // paid currency0
        assertEq(currency0Before - currency0After, uint256(amount));
        assertEq(reserves0After - reserves0Before, uint256(amount));

        // received currency1
        assertEq(currency1After - currency1Before, uint256(amount));
    }

    function test_zeroForOne_negative() public {
        uint256 currency0Before = currency0.balanceOf(address(this));
        uint256 currency1Before = currency1.balanceOf(address(this));
        uint256 reserves0Before = currency0.balanceOf(address(hook));

        // Perform a test swap: want 10 currency1 //
        int256 amount = -10e18;
        bool zeroForOne = true;
        swap(poolKey, zeroForOne, amount, ZERO_BYTES);
        // ------------------- //

        uint256 currency0After = currency0.balanceOf(address(this));
        uint256 currency1After = currency1.balanceOf(address(this));
        uint256 reserves0After = currency0.balanceOf(address(hook));

        // paid currency0
        assertEq(currency0Before - currency0After, uint256(-amount));
        assertEq(reserves0After - reserves0Before, uint256(-amount));

        // received currency1
        assertEq(currency1After - currency1Before, uint256(-amount));
    }

    function test_oneForZero_positive() public {
        uint256 currency0Before = currency0.balanceOf(address(this));
        uint256 currency1Before = currency1.balanceOf(address(this));
        uint256 reserves1Before = currency1.balanceOf(address(hook));

        // Perform a test swap //
        int256 amount = 10e18;
        bool zeroForOne = false;
        swap(poolKey, zeroForOne, amount, ZERO_BYTES);
        // ------------------- //

        uint256 currency0After = currency0.balanceOf(address(this));
        uint256 currency1After = currency1.balanceOf(address(this));
        uint256 reserves1After = currency1.balanceOf(address(hook));

        // paid currency1
        assertEq(currency1Before - currency1After, uint256(amount));
        assertEq(reserves1After - reserves1Before, uint256(amount));

        // received currency0
        assertEq(currency0After - currency0Before, uint256(amount));
    }

    function test_oneForZero_negative() public {
        uint256 currency0Before = currency0.balanceOf(address(this));
        uint256 currency1Before = currency1.balanceOf(address(this));
        uint256 reserves1Before = currency1.balanceOf(address(hook));

        // Perform a test swap: want 10 currency0 //
        int256 amount = -10e18;
        bool zeroForOne = false;
        swap(poolKey, zeroForOne, amount, ZERO_BYTES);
        // ------------------- //

        uint256 currency0After = currency0.balanceOf(address(this));
        uint256 currency1After = currency1.balanceOf(address(this));
        uint256 reserves1After = currency1.balanceOf(address(hook));

        // paid currency1
        assertEq(currency1Before - currency1After, uint256(-amount));
        assertEq(reserves1After - reserves1Before, uint256(-amount));

        // received currency0
        assertEq(currency0After - currency0Before, uint256(-amount));
    }

    function test_no_v4_liquidity() public {
        vm.expectRevert("No v4 Liquidity allowed");
        modifyLiquidityRouter.modifyLiquidity(
            poolKey, IPoolManager.ModifyLiquidityParams(-60, 60, 10000 ether), ZERO_BYTES
        );
    }

    function test_hookless_gas() public {
        int256 amount = 1e18;
        bool zeroForOne = true;
        uint256 gasBefore = gasleft();
        swap(hooklessKey, zeroForOne, amount, ZERO_BYTES);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console2.log("hookless gas used: ", gasUsed);
    }

    function test_csmm_gas() public {
        int256 amount = 1e18;
        bool zeroForOne = true;
        uint256 gasBefore = gasleft();
        swap(poolKey, zeroForOne, amount, ZERO_BYTES);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console2.log("csmm gas used: ", gasUsed);
    }
}
