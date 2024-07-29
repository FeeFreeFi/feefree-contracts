// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {IPoolManager} from "../../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../../uniswap/interfaces/IHooks.sol";
import {PoolKey} from "../../uniswap/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../../uniswap/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "../../uniswap/types/Currency.sol";
import {FullMath} from "../../uniswap/libraries/FullMath.sol";
import {FixedPoint96} from "../../uniswap/libraries/FixedPoint96.sol";
import {SafeCast} from "../../uniswap/libraries/SafeCast.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";

library PoolLibrary {
    using SafeCast for uint256;
    using PoolIdLibrary for PoolKey;

    /// @dev Min tick for full range with tick spacing of 60
    int24 constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 constant MAX_TICK = 887220;
        /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 constant MIN_SQRT_RATIO = 4306310044;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 constant MAX_SQRT_RATIO = 1457652066949847389969617340386294118487833376468;

    function getPoolKey(Currency currency0, Currency currency1) internal pure returns (PoolKey memory) {
        return PoolKey(currency0, currency1, 0, 60, IHooks(address(0)));
    }

    function getPoolId(address currency0, address currency1) internal pure returns (bytes32) {
        if (currency0 > currency1) {
            (currency0, currency1) = (currency1, currency0);
        }

        return PoolId.unwrap(getPoolKey(Currency.wrap(currency0), Currency.wrap(currency1)).toId());
    }

    function getModifyLiquidityParams(int256 liquidityDelta) internal pure returns (IPoolManager.ModifyLiquidityParams memory) {
        return IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: liquidityDelta,
            salt: 0
        });
    }

    function getSwapData(Currency input, Currency output, int128 amountSpecified, uint160 sqrtPriceLimitX96) internal pure returns (PoolKey memory key, IPoolManager.SwapParams memory params) {
        (Currency currency0, Currency currency1) = input < output ? (input, output) : (output, input);

        bool zeroForOne = input == currency0;
        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;
        }

        key = getPoolKey(currency0, currency1);
        params = IPoolManager.SwapParams(zeroForOne, amountSpecified, sqrtPriceLimitX96);
    }

    function getNewLiquidity(uint160 sqrtPriceX96, uint256 amount0, uint256 amount1) internal pure returns (uint128) {
        return LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            MIN_SQRT_RATIO,
            MAX_SQRT_RATIO,
            amount0,
            amount1
        );
    }

    function getSqrtPriceX96(uint128 amount0, uint128 amount1) internal pure returns (uint160) {
        return (FixedPointMathLib.sqrt(FullMath.mulDiv(FixedPoint96.Q96, amount1, amount0)) << 48).toUint160();
    }
}
