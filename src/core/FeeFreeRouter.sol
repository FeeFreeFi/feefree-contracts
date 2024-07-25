// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "../uniswap/interfaces/callback/IUnlockCallback.sol";
import {BalanceDelta, toBalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../uniswap/types/Currency.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../uniswap/types/PoolId.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {FullMath} from "../uniswap/libraries/FullMath.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {PoolLibrary} from "./libraries/PoolLibrary.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IFeeFreeRouter} from "./interfaces/IFeeFreeRouter.sol";
import {IFeeController} from "./interfaces/IFeeController.sol";
import {IFeeFreeERC20} from "./interfaces/IFeeFreeERC20.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {FeeFreeERC20} from "./FeeFreeERC20.sol";

contract FeeFreeRouter is Owned, IUnlockCallback, IFeeFreeRouter {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for uint128;

    error NotPoolManager();
    error NotSelf();
    error LockFailure();
    error PoolNotInitialized();
    error PoolAlreadyInitialized();
    error LiquidityDoesntMeetMinimum();
    error ExpiredPastDeadline();
    error TooMuchSlippage();
    error NotRawCurrency();

    bytes private constant ZERO_BYTES = bytes("");

    uint16 private constant MINIMUM_LIQUIDITY = 1000;

    IPoolManager public immutable poolManager;
    IFeeController public feeController;

    mapping(PoolId => address) public override liquidityToken;
    mapping(address => address) public override exchangeToken;
    mapping(address => bool) private isExchange;

    constructor(IPoolManager _poolManager, address _owner) Owned(_owner) {
        poolManager = _poolManager;
    }

    modifier onlyPool() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    modifier ensure(uint96 deadline) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        _;
    }

    function unlockCallback(bytes calldata data) external override onlyPool returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    function initialize(InitializeParams memory params) public override returns (int24 tick) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 != 0) revert PoolAlreadyInitialized();

        liquidityToken[poolId] = _deployLiquidityToken(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));

        tick = poolManager.initialize(key, params.sqrtPriceX96, ZERO_BYTES);
    }

    function addLiquidity(AddLiquidityParams calldata params) external payable override ensure(params.deadline) returns (uint128 liquidity) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) {
            sqrtPriceX96 = PoolLibrary.getSqrtPriceX96(params.amount1Desired, params.amount0Desired);
            InitializeParams memory initParams = InitializeParams({
                currency0: params.currency0,
                currency1: params.currency1,
                sqrtPriceX96: sqrtPriceX96
            });

            initialize(initParams);
        }

        uint128 poolLiquidity = _getLiquidity(poolId);
        liquidity = PoolLibrary.getNewLiquidity(sqrtPriceX96, params.amount0Desired, params.amount1Desired);
        _checkLiquidity(poolLiquidity, liquidity);

        BalanceDelta addedDelta = _modifyLiquidity(key, PoolLibrary.getModifyLiquidityParams(liquidity.toInt256()));

        if (poolLiquidity == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            liquidity -= MINIMUM_LIQUIDITY;
            _mintToken(liquidityToken[poolId], address(0), MINIMUM_LIQUIDITY);
        }

        _mintToken(liquidityToken[poolId], params.to, liquidity);

        if (uint128(-addedDelta.amount0()) < params.amount0Min || uint128(-addedDelta.amount1()) < params.amount1Min) {
            revert TooMuchSlippage();
        }

        if (params.currency0.isNative()) {
            uint256 remain = msg.value - uint128(-addedDelta.amount0());
            if (remain > 0) {
                params.currency0.transfer(msg.sender, remain);
            }
        }
    }

    function removeLiquidity(RemoveLiquidityParams calldata params) external override ensure(params.deadline) returns (BalanceDelta delta) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        delta = _modifyLiquidity(key, PoolLibrary.getModifyLiquidityParams(-(params.liquidity.toInt256())));

        _burnToken(liquidityToken[poolId], msg.sender, params.liquidity);
    }

    function swap(SwapParams calldata params) external payable override ensure(params.deadline) returns (BalanceDelta delta) {
        delta = abi.decode(_unlock(abi.encodeWithSelector(this.onSwap.selector, params.paths, params.sqrtPriceX96Limits, params.amountSpecified, params.to, msg.sender)), (BalanceDelta));
    }

    function exchange(ExchangeParams calldata params) external payable override {
        _unlock(abi.encodeWithSelector(this.onExchange.selector, params.currency, params.amountSpecified, params.to, msg.sender));
    }

    function quoteSwap(QuoteSwapParams calldata params) external override returns (int128[] memory deltaAmounts, uint160[] memory sqrtPriceX96Afters) {
        try poolManager.unlock(abi.encodeWithSelector(this.onQuoteSwap.selector, params.paths, params.amountSpecified)) {}
        catch (bytes memory reason) {
            (deltaAmounts, sqrtPriceX96Afters) = abi.decode(reason, (int128[], uint160[]));
        }
    }

    function quoteAddLiquidity(QuoteAddLiquidityParams calldata params) external override returns (uint128 amount0Min, uint128 amount1Min, uint128 liquidity) {
        try poolManager.unlock(abi.encodeWithSelector(this.onQuoteAddLiquidity.selector, params)) {}
        catch (bytes memory reason) {
            (amount0Min, amount1Min, liquidity) = abi.decode(reason, (uint128, uint128, uint128));
        }
    }

    function quoteRemoveLiquidity(QuoteRemoveLiquidityParams calldata params) external override returns (uint128 amount0, uint128 amount1) {
        try poolManager.unlock(abi.encodeWithSelector(this.onQuoteRemoveLiquidity.selector, params)) {}
        catch (bytes memory reason) {
            (amount0, amount1) = abi.decode(reason, (uint128, uint128));
        }
    }

    function getPoolId(address currency0, address currency1) external override pure returns (bytes32) {
        return PoolLibrary.getPoolId(currency0, currency1);
    }

    function getPoolState(bytes32 id) external override view returns (uint160 sqrtPriceX96, uint128 liquidity) {
        PoolId poolId = PoolId.wrap(id);
        sqrtPriceX96 = _getPoolSqrtPrice(poolId);
        liquidity = _getLiquidity(poolId);
    }

    function getFee() external override view returns (uint96 fee) {
        if (address(feeController) != address(0)) {
            fee = feeController.fee();
        }
    }

    function onSwap(Currency[] memory paths, uint160[] memory sqrtPriceX96Limits, int128 amountSpecified, address to, address sender) external onlySelf returns (BalanceDelta delta) {
        uint256 step = paths.length - 1;

        PoolKey memory key;
        IPoolManager.SwapParams memory params;
        uint256 i;
        uint256 j;

        if (amountSpecified < 0) {
            j = 1;
            while (i < step) {
                (key, params, delta, amountSpecified) = _swap(paths[i], paths[j], amountSpecified, sqrtPriceX96Limits[i], false);
                unchecked {
                    ++i;
                    ++j;
                }
            }
        } else {
            i = step;
            j = step - 1;
            while (i > 0) {
                (key, params, delta, amountSpecified) = _swap(paths[j], paths[i], amountSpecified, sqrtPriceX96Limits[j], true);
                unchecked {
                    --i;
                    --j;
                }
            }
        }

        int256 amountIn = _getCurrencyDelta(paths[0]);
        int256 amountOut = _getCurrencyDelta(paths[step]);
        if (amountOut == 0) {
            revert TooMuchSlippage();
        }

        _settleDelta(sender, paths[0], uint256(-amountIn));
        _takeDelta(to, paths[step], uint256(amountOut));

        _collectFee(PoolId.unwrap(key.toId()));

        delta = toBalanceDelta(amountIn.toInt128(), amountOut.toInt128());
    }

    function onModifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params, address sender) external onlySelf returns (BalanceDelta delta) {
        if (params.liquidityDelta < 0) {
            delta = _removeLiquidity(key, params);
            _takeDelta(sender, key.currency0, uint128(delta.amount0()));
            _takeDelta(sender, key.currency1, uint128(delta.amount1()));
        } else {
            (delta,) = poolManager.modifyLiquidity(key, params, ZERO_BYTES);
            _settleDelta(sender, key.currency0, uint128(-delta.amount0()));
            _settleDelta(sender, key.currency1, uint128(-delta.amount1()));
        }
    }

    function onExchange(Currency currency, int128 amountSpecified, address to, address sender) external payable onlySelf returns (bytes memory) {
        address currencyAddress = Currency.unwrap(currency);
        if (isExchange[currencyAddress]) {
            revert NotRawCurrency();
        }

        address exchangeAddress = exchangeToken[currencyAddress];
        if (exchangeAddress == address(0)) {
            exchangeAddress = _deployExchangeToken(Currency.unwrap(currency));
            exchangeToken[currencyAddress] = exchangeAddress;
            isExchange[exchangeAddress] = true;
        }

        uint256 amount;
        if (amountSpecified < 0) {
            _settleDelta(sender, currency, uint128(-amountSpecified));
            amount = uint256(_getCurrencyDelta(currency));
            poolManager.mint(address(this), currency.toId(), amount);
            _mintToken(exchangeAddress, sender, amount);
        } else {
            amount = uint128(amountSpecified);
            _takeDelta(to, currency, uint128(amountSpecified));
            poolManager.burn(address(this), currency.toId(), amount);
            _burnToken(exchangeAddress, sender, amount);
        }

        _collectFee(bytes32(0));

        return ZERO_BYTES;
    }

    function onQuoteSwap(Currency[] memory paths, int128 amountSpecified) external onlySelf returns (bytes memory) {
        uint256 length = paths.length;
        uint256 step = length - 1;

        int128[] memory deltaAmounts = new int128[](length);
        uint160[] memory sqrtPriceX96Afters = new uint160[](step);

        PoolKey memory key;
        IPoolManager.SwapParams memory params;
        BalanceDelta delta;

        int128 deltaAmount;
        uint256 i;
        uint256 j;

        if (amountSpecified < 0) {
            j = 1;
            while (i < step) {
                deltaAmounts[i] = amountSpecified;
                (key, params, delta, amountSpecified) = _swap(paths[i], paths[j], amountSpecified, 0, false);
                sqrtPriceX96Afters[i] = _getPoolSqrtPrice(key.toId());
                deltaAmount = -amountSpecified;
                unchecked {
                    ++i;
                    ++j;
                }
            }
        } else {
            i = step;
            j = step - 1;
            while (i > 0) {
                deltaAmounts[i] = amountSpecified;
                (key, params, delta, amountSpecified) = _swap(paths[j], paths[i], amountSpecified, 0, true);
                sqrtPriceX96Afters[j] = _getPoolSqrtPrice(key.toId());
                deltaAmount = -amountSpecified;
                unchecked {
                    --i;
                    --j;
                }
            }
        }
        deltaAmounts[i] = deltaAmount;

        bytes memory result = abi.encode(deltaAmounts, sqrtPriceX96Afters);
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function onQuoteAddLiquidity(QuoteAddLiquidityParams calldata params) external onlySelf returns (bytes memory) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        uint128 poolLiquidity = _getLiquidity(poolId);
        uint128 liquidity = PoolLibrary.getNewLiquidity(sqrtPriceX96, params.amount0Desired, params.amount1Desired);
        _checkLiquidity(poolLiquidity, liquidity);

        (BalanceDelta addedDelta,) = poolManager.modifyLiquidity(key, PoolLibrary.getModifyLiquidityParams(liquidity.toInt256()), ZERO_BYTES);

        if (poolLiquidity == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            liquidity -= MINIMUM_LIQUIDITY;
        }

        bytes memory result = abi.encode(uint128(-addedDelta.amount0()), uint128(-addedDelta.amount1()), liquidity);
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function onQuoteRemoveLiquidity(QuoteRemoveLiquidityParams calldata params) external onlySelf returns (bytes memory) {
        (PoolKey memory key, , uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        BalanceDelta delta = _removeLiquidity(key, PoolLibrary.getModifyLiquidityParams(-(params.liquidity.toInt256())));

        bytes memory result = abi.encode(uint128(delta.amount0()), uint128(delta.amount1()));
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function setFeeController(IFeeController _feeController) external onlyOwner {
        feeController = _feeController;
    }

    function rescue(address token, address to, uint256 amount) external onlyOwner {
        Currency.wrap(token).transfer(to, amount);
    }

    function _unlock(bytes memory data) private returns (bytes memory) {
        return poolManager.unlock(data);
    }

    function _modifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params) private returns (BalanceDelta delta) {
        delta = abi.decode(_unlock(abi.encodeWithSelector(this.onModifyLiquidity.selector, key, params, msg.sender)), (BalanceDelta));
    }

    function _removeLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params) private returns (BalanceDelta delta) {
        PoolId poolId = key.toId();

        uint256 liquidityToRemove = FullMath.mulDiv(
            uint256(-params.liquidityDelta),
            _getLiquidity(poolId),
            IFeeFreeERC20(liquidityToken[poolId]).totalSupply()
        );

        params.liquidityDelta = -(liquidityToRemove.toInt256());
        (delta,) = poolManager.modifyLiquidity(key, params, ZERO_BYTES);
    }

    function _swap(Currency input, Currency output, int128 amountSpecified, uint160 sqrtPriceLimitX96, bool reverse) private returns (PoolKey memory key, IPoolManager.SwapParams memory params, BalanceDelta delta, int128 amountOut) {
        (key, params) = PoolLibrary.getSwapData(input, output, amountSpecified, sqrtPriceLimitX96);
        delta = poolManager.swap(key, params, ZERO_BYTES);
        amountOut = params.zeroForOne == reverse ? -delta.amount0() : -delta.amount1();
    }

    function _settleDelta(address sender, Currency currency, uint256 amount) private {
        if (currency.isNative()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            IERC20(Currency.unwrap(currency)).transferFrom(sender, address(poolManager), amount);
            poolManager.settle();
        }
    }

    function _takeDelta(address to, Currency currency, uint256 amount) private {
        poolManager.take(currency, to, amount);
    }

    function _mintToken(address token, address to, uint256 amount) private {
        IFeeFreeERC20(token).mint(to, amount);
    }

    function _burnToken(address token, address sender, uint256 amount) private {
        IFeeFreeERC20(token).burn(sender, amount);
    }

    function _deployLiquidityToken(address currency0, address currency1) private returns (address) {
        string memory symbol = string.concat(_getSymbol(currency0), "-", _getSymbol(currency1));
        return address(new FeeFreeERC20(symbol, symbol, 18));
    }

    function _deployExchangeToken(address currency) private returns (address) {
        string memory symbol = string.concat(_getSymbol(currency), "+");
        uint8 decimals = _isNative(currency) ? 18 : IERC20Metadata(currency).decimals();
        return address(new FeeFreeERC20(symbol, symbol, decimals));
    }

    function _collectFee(bytes32 id) private {
        if (address(feeController) != address(0)) {
            uint96 fee = feeController.fee();
            if (fee > 0) {
                feeController.collectFee{value:fee}(id);
            }
        }
    }

    function _checkLiquidity(uint128 poolLiquidity, uint128 liquidity) private pure {
        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }
    }

    function _getSymbol(address currency) private view returns (string memory) {
        return _isNative(currency) ? "NATIVE" : IERC20Metadata(currency).symbol();
    }

    function _isNative(address currency) private pure returns (bool) {
        return currency == address(0);
    }

    function _getCurrencyDelta(Currency currency) private view returns (int256) {
        return poolManager.currencyDelta(address(this), currency);
    }

    function _getPoolSqrtPrice(PoolId poolId) private view returns (uint160) {
        return poolManager.getSqrtPriceX96(poolId);
    }

    function _getLiquidity(PoolId poolId) private view returns (uint128) {
        return poolManager.getLiquidity(poolId);
    }

    function _getPoolMeta(Currency currency0, Currency currency1) private view returns (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) {
        key = PoolLibrary.getPoolKey(currency0, currency1);
        poolId = key.toId();
        sqrtPriceX96 = _getPoolSqrtPrice(poolId);
    }
}
