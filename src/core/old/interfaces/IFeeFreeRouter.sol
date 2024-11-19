// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Currency} from "../../../uniswap/types/Currency.sol";
import {BalanceDelta} from "../../../uniswap/types/BalanceDelta.sol";
import {PoolId} from "../../../uniswap/types/PoolId.sol";

interface IFeeFreeRouter {
    struct InitializeParams {
        Currency currency0;
        Currency currency1;
        uint160 sqrtPriceX96;
    }

    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 amount0Desired;
        uint128 amount1Desired;
        uint128 amount0Min;
        uint128 amount1Min;
        address to;
        uint96 deadline;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        uint96 deadline;
    }

    struct SwapParams {
        Currency[] paths;
        uint160[] sqrtPriceX96Limits;
        int128 amountSpecified;
        address to;
        uint96 deadline;
    }

    struct ExchangeParams {
        Currency currency;
        int128 amountSpecified;
        address to;
    }

    struct QuoteSwapParams {
        Currency[] paths;
        int128 amountSpecified;
    }

    struct QuoteAddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 amount0Desired;
        uint128 amount1Desired;
    }

    struct QuoteRemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
    }

    function initialize(InitializeParams calldata params) external returns (int24 tick);
    function addLiquidity(AddLiquidityParams calldata params) external payable returns (uint128 liquidity);
    function removeLiquidity(RemoveLiquidityParams calldata params) external returns (BalanceDelta delta);
    function swap(SwapParams calldata params) external payable returns (BalanceDelta delta);
    function exchange(ExchangeParams calldata params) external payable;

    function quoteSwap(QuoteSwapParams calldata params) external returns (int128[] memory deltaAmounts, uint160[] memory sqrtPriceX96Afters);
    function quoteAddLiquidity(QuoteAddLiquidityParams calldata params) external returns (uint128 amount0Min, uint128 amount1Min, uint128 liquidity);
    function quoteRemoveLiquidity(QuoteRemoveLiquidityParams calldata params) external returns (uint128 amount0, uint128 amount1);

    function getPoolState(bytes32 id) external view returns (uint160 sqrtPriceX96, uint128 liquidity);
    function getFee() external view returns (uint96);

    function liquidityToken(PoolId id) external view returns (address);
    function exchangeToken(address token) external view returns (address);
}