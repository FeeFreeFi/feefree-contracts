// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {Currency} from "../uniswap/types/Currency.sol";
import {BalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {Hooks} from "../uniswap/libraries/Hooks.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
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
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: true
        });
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

        (uint8 tag, address feeManager, uint24 lpFee) = abi.decode(hookData, (uint8, address, uint24));
        if (tag != PoolTags.NORMAL) {
            hookDelta = FeeLibrary.getFeeDelta(delta, lpFee);
            (int128 amount0, int128 amount1) = (hookDelta.amount0(), hookDelta.amount1());

            if (poolManager.getLiquidity(key.toId()) > 0) {
                bool isZero = tag == PoolTags.ZERO;
                int128 amount = isZero ? -amount0 : -amount1;
                BalanceDelta swapDelta = poolManager.swap(key, PoolLibrary.getSwapData(isZero, amount), PoolLibrary.ZERO_BYTES);
                (amount0, amount1) = isZero ? (int128(0), amount1 + swapDelta.amount1()) : (amount0 + swapDelta.amount0(), int128(0));
            }

            if (amount0 > 0) {
                poolManager.take(key.currency0, feeManager, amount0.toUint128());
            }
            if (amount1 > 0) {
                poolManager.take(key.currency1, feeManager, amount1.toUint128());
            }
        }
    }
}