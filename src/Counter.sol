// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// TODO: update to v4-periphery/BaseHook.sol when its compatible
import {BaseHook} from "./forks/BaseHook.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {Lockers} from "@uniswap/v4-core/contracts/libraries/Lockers.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";

contract Counter is BaseHook {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeModifyPosition: true, // prevent v4 liquidity from being added
            afterModifyPosition: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            noOp: true, // no-op PoolManager.swap in favor of constant sum curve
            accessLock: true
        });
    }

    /// @notice Constant sum swap via custom accounting, tokens are exchanged 1:1
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4)
    {
        uint256 tokenAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // 0 -> 1
        if (params.zeroForOne) {
            // take currency0 from the PoolManager, forcing the router to pay debt with user's currency0
            poolManager.take(key.currency0, address(this), tokenAmount);

            // provide currency1 to the PoolManager, forcing the router to forward currency1 to the user
            key.currency1.transfer(address(poolManager), tokenAmount);
            poolManager.settle(key.currency1);
        }
        // 1 -> 0
        else {
            // take currency1 from the PoolManager, forcing the router to pay debt with user's currency1
            poolManager.take(key.currency1, address(this), tokenAmount);

            // provide currency0 to the PoolManager, forcing the router to forward currency0 to the user
            key.currency0.transfer(address(poolManager), tokenAmount);
            poolManager.settle(key.currency0);
        }

        // prevent normal v4 swap logic from executing
        return Hooks.NO_OP_SELECTOR;
    }

    /// @notice No liquidity will be managed by v4 PoolManager
    function beforeModifyPosition(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        revert("No v4 Liquidity allowed");
    }

    // -----------------------------------------------
    // Liquidity Functions, not production ready
    // -----------------------------------------------
    /// @notice Add liquidity 1:1 for the constant sum curve
    /// @param key PoolKey of the pool to add liquidity to
    /// @param liquiditySum The sum of the liquidity to add (token0 + token1)
    function addLiquidity(PoolKey calldata key, uint256 liquiditySum) external {
        require(liquiditySum % 2 == 0, "liquiditySum must be even");
        uint256 tokenAmounts = liquiditySum / 2;

        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), tokenAmounts);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), tokenAmounts);

        // TODO: should mint a receipt token to msg.sender
    }
}
