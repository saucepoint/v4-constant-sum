// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolTestBase} from "v4-core/src/test/PoolTestBase.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";

contract CustomCurveRouter is Test, PoolTestBase {
    using CurrencyLibrary for Currency;
    using Hooks for IHooks;

    constructor(IPoolManager _manager) PoolTestBase(_manager) {}

    error NoSwapOccurred();

    struct CallbackData {
        address sender;
        TestSettings testSettings;
        PoolKey key;
        IPoolManager.SwapParams params;
        bytes hookData;
    }

    struct TestSettings {
        bool withdrawTokens;
        bool settleUsingTransfer;
        bool currencyAlreadySent;
    }

    function swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        TestSettings memory testSettings,
        bytes memory hookData
    ) external payable returns (BalanceDelta delta) {
        delta = abi.decode(
            manager.lock(abi.encode(CallbackData(msg.sender, testSettings, key, params, hookData))), (BalanceDelta)
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
    }

    function lockAcquired(bytes calldata rawData) external returns (bytes memory) {
        require(msg.sender == address(manager));

        CallbackData memory data = abi.decode(rawData, (CallbackData));

        (,,, int256 deltaBefore0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,,, int256 deltaBefore1) = _fetchBalances(data.key.currency1, data.sender, address(this));

        assertEq(deltaBefore0, 0);
        assertEq(deltaBefore1, 0);

        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        (,,, int256 deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,,, int256 deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));
        (,,, int256 deltaAfter0Hook) = _fetchBalances(data.key.currency0, data.sender, address(data.key.hooks));
        (,,, int256 deltaAfter1Hook) = _fetchBalances(data.key.currency1, data.sender, address(data.key.hooks));
        console2.log(deltaAfter0);
        console2.log(deltaAfter1);
        console2.log(deltaAfter0Hook);
        console2.log(deltaAfter1Hook);
        console2.log("----");

        // if (data.params.zeroForOne) {
        //     if (data.params.amountSpecified < 0) {
        //         // exact input, 0 for 1
        //         assertEq(deltaAfter0, data.params.amountSpecified);
        //         assertEq(delta.amount0(), data.params.amountSpecified);
        //         assertGt(deltaAfter1, 0);
        //     } else {
        //         // exact output, 0 for 1
        //         assertLt(deltaAfter0, 0);
        //         assertEq(deltaAfter1, data.params.amountSpecified);
        //         assertEq(delta.amount1(), data.params.amountSpecified);
        //     }
        // } else {
        //     if (data.params.amountSpecified < 0) {
        //         // exact input, 1 for 0
        //         assertEq(deltaAfter1, data.params.amountSpecified);
        //         assertEq(delta.amount1(), data.params.amountSpecified);
        //         assertGt(deltaAfter0, 0);
        //     } else {
        //         // exact output, 1 for 0
        //         assertLt(deltaAfter1, 0);
        //         assertEq(deltaAfter0, data.params.amountSpecified);
        //         assertEq(delta.amount0(), data.params.amountSpecified);
        //     }
        // }

        if (deltaAfter0 < 0) {
            if (data.testSettings.currencyAlreadySent) {
                manager.settle(data.key.currency0);
            } else {
                _settle(data.key.currency0, data.sender, int128(deltaAfter0), data.testSettings.settleUsingTransfer);
            }
        }
        if (deltaAfter1 < 0) {
            if (data.testSettings.currencyAlreadySent) {
                manager.settle(data.key.currency1);
            } else {
                _settle(data.key.currency1, data.sender, int128(deltaAfter1), data.testSettings.settleUsingTransfer);
            }
        }
        if (deltaAfter0 > 0) {
            _take(data.key.currency0, data.sender, int128(deltaAfter0), data.testSettings.withdrawTokens);
        }
        if (deltaAfter1 > 0) {
            _take(data.key.currency1, data.sender, int128(deltaAfter1), data.testSettings.withdrawTokens);
        }

        (,,, deltaAfter0) = _fetchBalances(data.key.currency0, data.sender, address(this));
        (,,, deltaAfter1) = _fetchBalances(data.key.currency1, data.sender, address(this));
        (,,, deltaAfter0Hook) = _fetchBalances(data.key.currency0, data.sender, address(data.key.hooks));
        (,,, deltaAfter1Hook) = _fetchBalances(data.key.currency1, data.sender, address(data.key.hooks));
        console2.log(deltaAfter0);
        console2.log(deltaAfter1);
        console2.log(deltaAfter0Hook);
        console2.log(deltaAfter1Hook);
        console2.log("----");

        // if (deltaAfter0Hook > 0) {
        //     _take(data.key.currency0, data.sender, int128(deltaAfter0Hook), data.testSettings.withdrawTokens);
        // }
        // if (deltaAfter1Hook > 0) {
        //     _take(data.key.currency1, data.sender, int128(deltaAfter1Hook), data.testSettings.withdrawTokens);
        // }

        return abi.encode(delta);
    }
}
