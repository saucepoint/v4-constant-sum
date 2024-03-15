// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// TODO: update to v4-periphery/BaseHook.sol when its compatible
import {BaseHook} from "./forks/BaseHook.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";

contract Counter is BaseHook {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: true,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiqReturnDelta: false,
            afterRemoveLiqReturnDelta: false
        });
    }

    /// @notice Constant sum swap via custom accounting, tokens are exchanged 1:1
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, int128)
    {
        // tokens are always swapped 1:1, so inputToken/outputToken amounts are the same even if the user uses exact-output-swap
        uint256 tokenAmount =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // determine inputToken/outputToken token based on 0->1 or 1->0 swap
        (Currency inputToken, Currency outputToken) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        // take the inputToken token from the PoolManager, debt is paid by the swapper via the swap router
        // (inputToken token is added to hook's reserves)
        poolManager.take(inputToken, address(this), tokenAmount);

        // provide outputToken token to the PoolManager, credit is claimed by the swap router who forwards it to the swapper
        // (outputToken token is removed from hook's reserves)
        // outputToken.transfer(address(poolManager), tokenAmount);
        // poolManager.settle(outputToken);

        // prevent normal v4 swap logic from executing
        // TODO: safe casting
        return (BaseHook.beforeSwap.selector, int128(uint128(tokenAmount)));
    }

    function afterSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, int128) {
        // poolManager.take(key.currency1, sender, uint256(-params.amountSpecified));
        // return (BaseHook.afterSwap.selector, int128(params.amountSpecified));
        return (BaseHook.afterSwap.selector, int128(params.amountSpecified));
    }

    /// @notice No liquidity will be managed by v4 PoolManager
    function beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        revert("No v4 Liquidity allowed");
    }

    // -----------------------------------------------
    // Liquidity Functions, not production ready
    // -----------------------------------------------
    /// @notice Add liquidity 1:1 for the constant sum curve
    /// @param key PoolKey of the pool to add liquidity to
    /// @param liquiditySum The sum of the liquidity to add (token0 + token1)
    function addLiquidity(PoolKey memory key, uint256 liquiditySum) external {
        // theoretically in CSMM, the liquidity ratio should attempt to move the reserves to 50/50
        // for demo purposes, we'll just require liquidity to be 50/50 ratio

        require(liquiditySum % 2 == 0, "liquiditySum must be even");
        uint256 tokenAmounts = liquiditySum / 2;

        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), tokenAmounts);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), tokenAmounts);

        // TODO: should mint a receipt token to msg.sender
    }
}
