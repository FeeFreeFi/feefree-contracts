// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {Currency} from "../uniswap/types/Currency.sol";
import {BalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {Hooks} from "../uniswap/libraries/Hooks.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {IShortableToken} from "./interfaces/IShortableToken.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {PoolLibrary} from "./libraries/PoolLibrary.sol";
import {PoolTags} from "./libraries/PoolTags.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";
import {BaseHook} from "./base/BaseHook.sol";

/***
 *    00000000\                  00000000\
 *    00  _____|                 00  _____|
 *    00 |    000000\   000000\  00 |    000000\   000000\   000000\
 *    00000\ 00  __00\ 00  __00\ 00000\ 00  __00\ 00  __00\ 00  __00\
 *    00  __|00000000 |00000000 |00  __|00 |  \__|00000000 |00000000 |
 *    00 |   00   ____|00   ____|00 |   00 |      00   ____|00   ____|
 *    00 |   \0000000\ \0000000\ 00 |   00 |      \0000000\ \0000000\
 *    \__|    \_______| \_______|\__|   \__|       \_______| \_______|
 */
contract Hook is BaseHook {
    using StateLibrary for IPoolManager;
    using SafeCast for int128;
    using SafeCast for uint128;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
    }

    /// @inheritdoc BaseHook
    function afterSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4 selector, int128 hookDelta) {
        selector = IHooks.afterSwap.selector;

        (uint160 sqrtPriceX96, uint128 liquidity, uint8 tag) = abi.decode(hookData, (uint160, uint128, uint8));
        if (tag != PoolTags.DEFAULT) {
            bool isZero = tag == PoolTags.ZERO;
            (Currency current, Currency asset) = isZero ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
            Currency opponent = Currency.wrap(IShortableToken(Currency.unwrap(current)).opponent());

            (PoolKey memory opponentKey, bool reverse) = PoolLibrary.getPoolKey(opponent, asset, this);

            if (isZero != params.zeroForOne) {
                int128 amountIn = isZero ? delta.amount0() : delta.amount1();

                delta = poolManager.swap(
                    opponentKey,
                    PoolLibrary.getSwapData(!reverse, -amountIn),
                    PoolLibrary.ZERO_BYTES
                );
                int128 amountAsset = reverse ? delta.amount0() : delta.amount1();

                delta = poolManager.swap(
                    key,
                    PoolLibrary.getSwapData(!isZero, -amountAsset),
                    PoolLibrary.ZERO_BYTES
                );
                int128 amountOut = isZero ? delta.amount0() : delta.amount1();

                _checkout(opponent, current, uint128(amountIn), uint128(amountOut));
            } else {
                int128 amountOut = isZero ? delta.amount0() : delta.amount1();
                delta = poolManager.swap(
                    opponentKey,
                    PoolLibrary.getSwapData(reverse, -amountOut),
                    PoolLibrary.ZERO_BYTES
                );
                int128 amountAssetRequired = reverse ? -delta.amount0() : -delta.amount1();

                if (params.amountSpecified < 0) {
                    uint128 amountCurrent = PoolLibrary.getInputFromOutput(sqrtPriceX96, liquidity, uint128(amountAssetRequired), isZero);
                    delta = poolManager.swap(
                        key,
                        PoolLibrary.getSwapData(isZero, -(amountCurrent.toInt128())),
                        PoolLibrary.ZERO_BYTES
                    );
                    int128 amountIn = isZero ? delta.amount0() : delta.amount1();
                    int128 amountAssetActual = isZero ? delta.amount1() : delta.amount0();
                    _checkout(current, opponent, uint128(-amountIn), uint128(-amountOut));

                    hookDelta = amountAssetRequired - amountAssetActual;
                } else {
                    delta = poolManager.swap(
                        key,
                        PoolLibrary.getSwapData(isZero, amountAssetRequired),
                        PoolLibrary.ZERO_BYTES
                    );
                    _take(opponent, address(this), uint128(-amountOut));

                    hookDelta = isZero ? -delta.amount0() : -delta.amount1();
                }
            }
        }
    }

    /// @inheritdoc BaseHook
    function afterRemoveLiquidity(
        address,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata,
        BalanceDelta delta,
        BalanceDelta,
        bytes calldata hookData
    ) external override onlyPoolManager returns (bytes4 selector, BalanceDelta hookDelta) {
        selector = IHooks.afterRemoveLiquidity.selector;

        (uint8 tag, address feeManager, uint24 fee) = abi.decode(hookData, (uint8, address, uint24));
        if (tag != PoolTags.DEFAULT) {
            hookDelta = FeeLibrary.getFeeDelta(delta, fee);
            int128 amount0 = hookDelta.amount0();
            int128 amount1 = hookDelta.amount1();

            if (poolManager.getLiquidity(key.toId()) > 0) {
                bool isZero = tag == PoolTags.ZERO;
                int128 amount = isZero ? -amount0 : -amount1;
                BalanceDelta swapDelta = poolManager.swap(
                    key,
                    PoolLibrary.getSwapData(isZero, amount),
                    PoolLibrary.ZERO_BYTES
                );
                amount0 = isZero ? int128(0) : amount0 + swapDelta.amount0();
                amount1 = isZero ? amount1 + swapDelta.amount1() : int128(0);
            }

            if (amount0 > 0) {
                _take(key.currency0, feeManager, amount0.toUint128());
            }
            if (amount1 > 0) {
                _take(key.currency1, feeManager, amount1.toUint128());
            }
        }
    }

    function _checkout(Currency inputCurrency, Currency outputCurrency, uint128 amountIn, uint128 amountOut) internal {
        _settle(inputCurrency, uint128(amountIn));
        _take(outputCurrency, address(this), uint128(amountOut));
    }

    /// @notice Take an amount of currency out of the PoolManager
    /// @param currency Currency to take
    /// @param recipient Address to receive the currency
    /// @param amount Amount to take
    /// @dev Returns early if the amount is 0
    function _take(Currency currency, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        poolManager.take(currency, recipient, amount);
    }

    /// @notice Pay and settle a currency to the PoolManager
    /// @dev The implementing contract must ensure that the `payer` is a secure address
    /// @param currency Currency to settle
    /// @param amount Amount to send
    /// @dev Returns early if the amount is 0
    function _settle(Currency currency, uint256 amount) internal {
        if (amount == 0) return;
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            currency.transfer(address(poolManager), amount);
            poolManager.settle();
        }
    }
}