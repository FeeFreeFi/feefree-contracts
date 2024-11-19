// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Currency} from "../../uniswap/types/Currency.sol";
import {PoolKey} from "../../uniswap/types/PoolKey.sol";
import {PoolId} from "../../uniswap/types/PoolId.sol";
import {IPoolManager} from "../../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../../uniswap/interfaces/IHooks.sol";
import {IFeeManager} from "./IFeeManager.sol";
import {IFactory} from "./IFactory.sol";
import {ILiquidityToken} from "./ILiquidityToken.sol";
import {ITimelock} from "./ITimelock.sol";

interface IFeeFreeManager {
    /// @notice Thrown when calling unlockCallback where the caller is not PoolManager
    error NotPoolManager();
    /// @notice emitted when an inheriting contract does not support an action
    error UnsupportedAction(uint256 action);
    error InvalidAmount();
    error DeadlinePassed(uint256 deadline);
    error TooLittleReceived(uint256 minAmountOutReceived, uint256 amountReceived);
    error TooMuchRequested(uint256 maxAmountInRequested, uint256 amountRequested);

    event AddLiquidity(
        PoolId indexed id,
        address indexed sender,
        uint128 liquidity
    );

    event RemoveLiquidity(
        PoolId indexed id,
        address indexed sender,
        uint128 liquidity
    );

    event Swap(
        address indexed sender,
        Currency indexed input,
        Currency indexed output,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFee
    );

    event Exchange(
        address indexed sender,
        Currency indexed currency,
        int128 amount,
        uint256 exchangeFee
    );

    struct LaunchParams {
        string name;
        string symbol;
        Currency asset;
        uint256 amount;
        uint256 totalSupply;
        address recipient;
        uint256 duration;
    }

    struct InitializeParams {
        Currency currency0;
        Currency currency1;
        uint128 amount0;
        uint128 amount1;
        address recipient;
        uint256 duration;
    }

    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        uint128 amount0Max;
        uint128 amount1Max;
        address recipient;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        uint128 amount0Min;
        uint128 amount1Min;
        address recipient;
    }

    struct SwapParams {
        Currency[] paths;
        int128 amountSpecified;
        uint128 amountDesired;
        address recipient;
    }

    struct ExchangeParams {
        Currency currency;
        int128 amountSpecified;
        address recipient;
    }

    struct PoolInfo {
        Currency currency0;
        Currency currency1;
        uint8 tag;
    }

    function launch(bytes calldata data) external payable;
    function initialize(bytes calldata data) external payable;
    function addLiquidity(bytes calldata data, uint256 deadline) external payable;
    function removeLiquidity(bytes calldata data, uint256 deadline) external;
    function swap(bytes calldata data, uint256 deadline) external payable;
    function exchange(bytes calldata data) external payable;

    function getPoolInfo(PoolId id) external view returns (Currency currency0, Currency currency1, uint8 tag);

    function poolManager() external view returns (IPoolManager);
    function hooks() external view returns (IHooks);
    function feeManager() external view returns (IFeeManager);
    function factory() external view returns (IFactory);
    function liquidityToken() external view returns (ILiquidityToken);
    function timelock() external view returns (ITimelock);
}
