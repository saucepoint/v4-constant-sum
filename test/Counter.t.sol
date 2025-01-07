// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {Counter} from "../src/Counter.sol";

import {Fixtures} from "./utils/Fixtures.sol";

contract CounterTest is Test, Fixtures {
    Counter hook;

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
            uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG)
                ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        manager.initialize(key, SQRT_PRICE_1_1);

        // Seed liquidity
        IERC20(Currency.unwrap(currency0)).approve(address(hook), 1000e18);
        IERC20(Currency.unwrap(currency1)).approve(address(hook), 1000e18);
        hook.addLiquidity(key, 1000e18);
    }

    function test_exactInput(bool zeroForOne, uint256 amount) public {
        amount = bound(amount, 1 wei, 1000e18);
        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        swap(key, zeroForOne, -int256(amount), ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        if (zeroForOne) {
            // paid token0
            assertEq(balance0Before - balance0After, amount);

            // received token1
            assertEq(balance1After - balance1Before, amount);
        } else {
            // paid token1
            assertEq(balance1Before - balance1After, amount);

            // received token0
            assertEq(balance0After - balance0Before, amount);
        }
    }

    function test_exactOutput(bool zeroForOne, uint256 amount) public {
        amount = bound(amount, 1 wei, 1000e18);
        uint256 balance0Before = currency0.balanceOfSelf();
        uint256 balance1Before = currency1.balanceOfSelf();

        swap(key, zeroForOne, int256(amount), ZERO_BYTES);

        uint256 balance0After = currency0.balanceOfSelf();
        uint256 balance1After = currency1.balanceOfSelf();

        if (zeroForOne) {
            // paid token0
            assertEq(balance0Before - balance0After, amount);

            // received token1
            assertEq(balance1After - balance1Before, amount);
        } else {
            // paid token1
            assertEq(balance1Before - balance1After, amount);

            // received token0
            assertEq(balance0After - balance0Before, amount);
        }
    }

    function test_no_v4_liquidity() public {
        vm.expectRevert();
        modifyLiquidityRouter.modifyLiquidity(key, LIQUIDITY_PARAMS, ZERO_BYTES);
    }
}
