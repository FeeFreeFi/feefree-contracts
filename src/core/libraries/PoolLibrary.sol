// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {IPoolManager} from "../../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../../uniswap/interfaces/IHooks.sol";
import {PoolKey} from "../../uniswap/types/PoolKey.sol";
import {Currency} from "../../uniswap/types/Currency.sol";
import {FixedPoint96} from "../../uniswap/libraries/FixedPoint96.sol";
import {FullMath} from "../../uniswap/libraries/FullMath.sol";
import {SafeCast} from "../../uniswap/libraries/SafeCast.sol";
import {SqrtPriceMath} from "../../uniswap/libraries/SqrtPriceMath.sol";

library PoolLibrary {
    using SafeCast for uint256;
    using SafeCast for int256;

    int24 internal constant MIN_TICK = -887220;
    int24 internal constant MAX_TICK = 887220;
    int24 internal constant TICK_SPACING = 60;
    uint160 internal constant MIN_SQRT_PRICE = 4306310044;
    uint160 internal constant MAX_SQRT_PRICE = 1457652066949847389969617340386294118487833376468;
    uint160 internal constant MIN_PRICE_LIMIT = 4306310045;
    uint160 internal constant MAX_PRICE_LIMIT = 1457652066949847389969617340386294118487833376467;

    uint256 internal constant Q192 = 6277101735386680763835789423207666416102355444464034512896;

    bytes internal constant ZERO_BYTES = "";

    function getPoolKey(Currency currency0, Currency currency1, IHooks hooks) internal pure returns (PoolKey memory key, bool reverse) {
        if (currency0 > currency1) {
            (currency0, currency1) = (currency1, currency0);
            reverse = true;
        }

        key = PoolKey(currency0, currency1, 0, TICK_SPACING, hooks);
    }

    function toTokenId(PoolKey memory key) internal pure returns (uint256 tokenId) {
        assembly ("memory-safe") {
            tokenId := keccak256(key, 0xa0)
        }
    }

    function getModifyLiquidityParams(int256 liquidityDelta) internal pure returns (IPoolManager.ModifyLiquidityParams memory) {
        return IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: liquidityDelta,
            salt: 0
        });
    }

    function getSwapData(bool zeroForOne, int128 amountSpecified) internal pure returns (IPoolManager.SwapParams memory) {
        return IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
        });
    }

    function getSqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160 sqrtPriceX96) {
        sqrtPriceX96 = FixedPointMathLib.sqrt(FullMath.mulDiv(Q192, amount1, amount0)).toUint160();
        if (sqrtPriceX96 < MIN_SQRT_PRICE) {
            sqrtPriceX96 = MIN_SQRT_PRICE;
        } else if(sqrtPriceX96 > MAX_SQRT_PRICE) {
            sqrtPriceX96 = MAX_SQRT_PRICE;
        }
    }

    function getLiquidityForAmounts(uint160 sqrtPriceX96, uint256 amount0, uint256 amount1) internal pure returns (uint128 liquidity) {
        if (sqrtPriceX96 <= MIN_SQRT_PRICE) {
            liquidity = getLiquidityForAmount0(MIN_SQRT_PRICE, MAX_SQRT_PRICE, amount0);
        } else if (sqrtPriceX96 < MAX_SQRT_PRICE) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPriceX96, MAX_SQRT_PRICE, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(MIN_SQRT_PRICE, sqrtPriceX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(MIN_SQRT_PRICE, MAX_SQRT_PRICE, amount1);
        }
    }

    function getAmountsForLiquidity(uint160 sqrtPriceX96, int128 liquidity) internal pure returns (int128 amount0, int128 amount1) {
        if (sqrtPriceX96 < MIN_SQRT_PRICE) {
            amount0 = SqrtPriceMath.getAmount0Delta(MIN_SQRT_PRICE, MAX_SQRT_PRICE, liquidity).toInt128();
        } else if (sqrtPriceX96 < MAX_SQRT_PRICE) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceX96, MAX_SQRT_PRICE, liquidity).toInt128();
            amount1 = SqrtPriceMath.getAmount1Delta(MIN_SQRT_PRICE, sqrtPriceX96, liquidity).toInt128();
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(MIN_SQRT_PRICE, MAX_SQRT_PRICE, liquidity).toInt128();
        }
    }

    /// @notice Computes the amount of liquidity received for a given amount of token0 and price range
    /// @dev Calculates amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtPriceAX96 A sqrt price representing the first tick boundary
    /// @param sqrtPriceBX96 A sqrt price representing the second tick boundary
    /// @param amount0 The amount0 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0) private pure returns (uint128 liquidity) {
        return FullMath.mulDiv(amount0, FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96), sqrtPriceBX96 - sqrtPriceAX96).toUint128();
    }

    /// @notice Computes the amount of liquidity received for a given amount of token1 and price range
    /// @dev Calculates amount1 / (sqrt(upper) - sqrt(lower)).
    /// @param sqrtPriceAX96 A sqrt price representing the first tick boundary
    /// @param sqrtPriceBX96 A sqrt price representing the second tick boundary
    /// @param amount1 The amount1 being sent in
    /// @return liquidity The amount of returned liquidity
    function getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1) private pure returns (uint128 liquidity) {
        return FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96).toUint128();
    }
}
