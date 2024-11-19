// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BalanceDelta, toBalanceDelta} from "../../uniswap/types/BalanceDelta.sol";
import {FullMath} from "../../uniswap/libraries/FullMath.sol";
import {SafeCast} from "../../uniswap/libraries/SafeCast.sol";

library FeeLibrary {
    using SafeCast for int128;
    using SafeCast for uint256;

    uint24 internal constant MAX_LP_FEE = 200000;
    uint24 internal constant FEE_DENOMINATOR = 1e6;

    function getFeeDelta(BalanceDelta delta, uint24 fee) internal pure returns (BalanceDelta) {
        return toBalanceDelta(
            FullMath.mulDiv(delta.amount0().toUint128(), fee, FEE_DENOMINATOR).toInt128(),
            FullMath.mulDiv(delta.amount1().toUint128(), fee, FEE_DENOMINATOR).toInt128()
        );
    }

    function getAmountsAfterFee(uint128 amount0, uint128 amount1, uint24 fee) internal pure returns (uint128 amount0After, uint128 amount1After) {
        amount0After = amount0 - FullMath.mulDiv(amount0, fee, FEE_DENOMINATOR).toUint128();
        amount1After = amount1 - FullMath.mulDiv(amount1, fee, FEE_DENOMINATOR).toUint128();
    }
}
