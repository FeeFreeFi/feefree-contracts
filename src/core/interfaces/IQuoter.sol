// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {IERC721Capped} from "./IERC721Capped.sol";
import {ITimelock} from "./ITimelock.sol";
import {Currency} from "../../uniswap/types/Currency.sol";
import {PoolId} from "../../uniswap/types/PoolId.sol";
import {PoolKey} from "../../uniswap/types/PoolKey.sol";

interface IQuoter {
    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
    }

    struct SwapParams {
        Currency[] paths;
        int128 amountSpecified;
    }

    struct TokenMeta {
        string name;
        string symbol;
        uint8 decimals;
        address addr;
    }

    struct PoolMeta {
        PoolId id;
        TokenMeta token0;
        TokenMeta token1;
        uint8 tag;
    }

    function addLiquidity(AddLiquidityParams calldata params) external view returns (uint128 amount0Desired, uint128 amount1Desired, uint128 liquidity);
    function removeLiquidity(RemoveLiquidityParams calldata params) external view returns (uint128 amount0Min, uint128 amount1Min);
    function swap(SwapParams calldata params) external returns (uint128 amountIn, uint128 amountOut);

    function getTokenMeta(Currency currency) external view returns (TokenMeta memory);

    function getPoolKey(Currency currency0, Currency currency1) external view returns (PoolKey memory key);
    function getPoolMeta(PoolId id) external view returns (PoolMeta memory);
    function getPoolState(PoolId id) external view returns (uint160 sqrtPriceX96, uint128 liquidity);

    function getPoolIds(address account) external view returns (PoolId[] memory);
    function getLockDatas(address account, PoolId id) external view returns (ITimelock.LockData[] memory);

    function getFees() external view returns (uint256 swapFee, uint256 exchangeFee, uint24 lpFee);

    function getMinted(IERC721Capped[] memory nfts) external view returns (uint256[] memory);
}
