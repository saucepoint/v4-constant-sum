// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";

contract Counter is BaseHook {
    using SafeCast for uint256;
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Constant sum swap via custom accounting, tokens are exchanged 1:1
    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata params, bytes calldata)
        external
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // determine inbound/outbound token based on 0->1 or 1->0 swap
        (Currency inputCurrency, Currency outputCurrency) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);

        // tokens are always swapped 1:1, so inbound/outbound amounts are the same even if the user uses exact-output-swap
        uint256 amount = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

        // take the input token, as ERC6909, from the PoolManager
        // the debt will be paid by the swapper via the swap router
        // input currency is added to hook's reserves
        poolManager.mint(address(this), inputCurrency.toId(), amount);

        // pay the output token, as ERC6909, to the PoolManager
        // the credit will be forwarded to the swap router, which then forwards it to the swapper
        // output currency is paid from the hook's reserves
        poolManager.burn(address(this), outputCurrency.toId(), amount);

        // return the delta to the PoolManager, so it can process the accounting
        // exact input:
        //   specifiedDelta = positive, to offset the input token taken by the hook
        //   unspecifiedDelta = positive, to signal a credit of the output token
        // exact output:
        //   specifiedDelta = negative, to offset the output token paid by the hook
        //   unspecifiedDelta = negative, to signal the input token taken by the hook
        bool isExactInput = params.amountSpecified < 0;
        int128 tokenAmount = amount.toInt128();
        BeforeSwapDelta returnDelta =
            isExactInput ? toBeforeSwapDelta(tokenAmount, tokenAmount) : toBeforeSwapDelta(-tokenAmount, -tokenAmount);

        return (BaseHook.beforeSwap.selector, returnDelta, 0);
    }

    /// @notice No liquidity will be managed by v4 PoolManager
    function beforeAddLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        revert("No v4 Liquidity allowed");
    }

    // -----------------------------------------------
    // Liquidity Functions, not production ready
    // -----------------------------------------------
    /// @notice Add liquidity 1:1 for the constant sum curve
    /// @param key PoolKey of the pool to add liquidity to
    /// @param amountPerToken The amount of each token to be added as liquidity
    function addLiquidity(PoolKey calldata key, uint256 amountPerToken) external {
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amountPerToken);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amountPerToken);

        // TODO: should mint a receipt token to msg.sender
    }
}
