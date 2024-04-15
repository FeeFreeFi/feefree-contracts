// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Owned} from "solmate/auth/Owned.sol";
import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {BalanceDelta, toBalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {Currency, CurrencyLibrary} from "../uniswap/types/Currency.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../uniswap/types/PoolId.sol";
import {Hooks} from "../uniswap/libraries/Hooks.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {FullMath} from "../uniswap/libraries/FullMath.sol";
import {FixedPoint96} from "../uniswap/libraries/FixedPoint96.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {BaseHook} from "./BaseHook.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {IFeeFreeRouter} from "./interfaces/IFeeFreeRouter.sol";
import {IFeeController} from "./interfaces/IFeeController.sol";
import {IFeeFreeERC20} from "./interfaces/IFeeFreeERC20.sol";
import {FeeFreeERC20} from "./FeeFreeERC20.sol";

contract FeeFreeRouter is Owned, BaseHook, IFeeFreeRouter {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SafeCast for uint128;

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();
    /// @notice Thrown when trying to initialize an already initialized pool
    error PoolAlreadyInitialized();
    error TickSpacingNotDefault();
    error LiquidityDoesntMeetMinimum();
    // error SenderMustBeHook();
    error ExpiredPastDeadline();
    error TooMuchSlippage();
    error NotRawCurrency();

    bytes private constant ZERO_BYTES = bytes("");

    /// @dev Min tick for full range with tick spacing of 60
    int24 private constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 private constant MAX_TICK = 887220;
    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 private constant MIN_SQRT_RATIO = 4306310044;
    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 private constant MAX_SQRT_RATIO = 1457652066949847389969617340386294118487833376468;

    uint16 private constant MINIMUM_LIQUIDITY = 1000;
    string private constant NATIVE_SYMBOL = "NATIVE";

    mapping(PoolId => address) public override liquidityToken;
    mapping(address => address) public override exchangeToken;
    mapping(address => bool) private isExchange;

    IFeeController public feeController;

    constructor(IPoolManager _poolManager, address _owner) Owned(_owner) BaseHook(_poolManager) {}

    modifier ensure(uint96 deadline) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }

    function initialize(InitializeParams memory params) public override returns (int24 tick) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);
        if (sqrtPriceX96 != 0) {
            revert PoolAlreadyInitialized();
        }

        string memory tokenSymbol = string(abi.encodePacked(_getCurrencySymbol(key.currency0), "-", _getCurrencySymbol(key.currency1)));
        liquidityToken[poolId] = address(new FeeFreeERC20(tokenSymbol, tokenSymbol, 18));

        tick = poolManager.initialize(key, params.sqrtPriceX96, ZERO_BYTES);
    }

    function addLiquidity(AddLiquidityParams calldata params) external payable override ensure(params.deadline) returns (uint128 liquidity) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) {
            sqrtPriceX96 = (FixedPointMathLib.sqrt(FullMath.mulDiv(FixedPoint96.Q96, params.amount1Desired, params.amount0Desired)) << 48).toUint160();
            InitializeParams memory initParams = InitializeParams({
                currency0: params.currency0,
                currency1: params.currency1,
                sqrtPriceX96: sqrtPriceX96
            });

            initialize(initParams);
        }

        uint128 poolLiquidity;
        (poolLiquidity, liquidity) = _getLiquidities(poolId, sqrtPriceX96, params.amount0Desired, params.amount1Desired);
        BalanceDelta addedDelta = _modifyLiquidity(key, _getModifyLiquidityParams(liquidity.toInt256()));

        if (poolLiquidity == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            liquidity -= MINIMUM_LIQUIDITY;
            IFeeFreeERC20(liquidityToken[poolId]).mint(address(0), MINIMUM_LIQUIDITY);
        }

        IFeeFreeERC20(liquidityToken[poolId]).mint(params.to, liquidity);

        if (uint128(-addedDelta.amount0()) < params.amount0Min || uint128(-addedDelta.amount1()) < params.amount1Min) {
            revert TooMuchSlippage();
        }
    }

    function removeLiquidity(RemoveLiquidityParams calldata params) external override ensure(params.deadline) returns (BalanceDelta delta) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        delta = _modifyLiquidity(key, _getModifyLiquidityParams(-(params.liquidity.toInt256())));

        IFeeFreeERC20(liquidityToken[poolId]).burn(msg.sender, params.liquidity);
    }

    function swap(SwapParams calldata params) external payable override ensure(params.deadline) returns (BalanceDelta delta) {
        delta = abi.decode(poolManager.unlock(abi.encodeWithSelector(this.onSwap.selector, params.paths, params.sqrtPriceX96Limits, params.amountSpecified, params.to, msg.sender)), (BalanceDelta));
    }

    function exchange(ExchangeParams calldata params) external payable override {
        poolManager.unlock(abi.encodeWithSelector(this.onExchange.selector, params.currency, params.amountSpecified, params.to, msg.sender));
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

    function getPoolId(address currency0, address currency1) external override view returns (bytes32) {
        if (currency0 > currency1) {
            (currency0, currency1) = (currency1, currency0);
        }

        return PoolId.unwrap(_getPoolKey(Currency.wrap(currency0), Currency.wrap(currency1)).toId());
    }

    function getPoolState(bytes32 id) external override view returns (uint160 sqrtPriceX96, uint128 liquidity) {
        PoolId poolId = PoolId.wrap(id);
        (sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        liquidity = poolManager.getLiquidity(poolId);
    }

    function getFee() external override view returns (uint96 fee) {
        if (address(feeController) != address(0)) {
            fee = feeController.fee();
        }
    }

    function onSwap(Currency[] memory paths, uint160[] memory sqrtPriceX96Limits, int128 amountSpecified, address to, address sender) external selfOnly returns (BalanceDelta delta) {
        uint256 step = paths.length - 1;

        PoolKey memory key;
        IPoolManager.SwapParams memory params;
        uint256 i;
        uint256 j;

        if (amountSpecified < 0) {
            j = 1;
            while (i < step) {
                (key, params) = _getSwapData(paths[i], paths[j], amountSpecified, sqrtPriceX96Limits[i]);
                delta = poolManager.swap(key, params, ZERO_BYTES);
                amountSpecified = params.zeroForOne ? -delta.amount1() : -delta.amount0();
                unchecked {
                    ++i;
                    ++j;
                }
            }
        } else {
            i = step;
            j = step - 1;
            while (i > 0) {
                (key, params) = _getSwapData(paths[j], paths[i], amountSpecified, sqrtPriceX96Limits[j]);
                delta = poolManager.swap(key, params, ZERO_BYTES);
                amountSpecified = params.zeroForOne ? -delta.amount0() : -delta.amount1();
                unchecked {
                    --i;
                    --j;
                }
            }
        }

        Currency inputCurrency = paths[0];
        Currency outputCurrency = paths[step];

        int256 amount0 = poolManager.currencyDelta(address(this), inputCurrency);
        int256 amount1 = poolManager.currencyDelta(address(this), outputCurrency);

        _settleDelta(sender, inputCurrency, uint128(-amount0.toInt128()));
        _takeDelta(to, outputCurrency, uint128(amount1.toInt128()));

        _collectFee(PoolId.unwrap(key.toId()));

        delta = toBalanceDelta(amount0.toInt128(), amount1.toInt128());
    }

    function onModifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params, address sender) external selfOnly returns (BalanceDelta delta) {
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

    function onExchange(Currency currency, int128 amountSpecified, address to, address sender) external payable selfOnly returns (bytes memory) {
        address currencyAddress = Currency.unwrap(currency);
        if (isExchange[currencyAddress]) {
            revert NotRawCurrency();
        }

        address exchangeAddress = exchangeToken[currencyAddress];
        if (exchangeAddress == address(0)) {
            string memory tokenSymbol = string(abi.encodePacked(_getCurrencySymbol(currency), "+"));
            exchangeAddress = address(new FeeFreeERC20(tokenSymbol, tokenSymbol, currency.isNative() ? 18 : IERC20Metadata(currencyAddress).decimals()));
            exchangeToken[currencyAddress] = exchangeAddress;
            isExchange[exchangeAddress] = true;
        }

        uint256 amount;
        if (amountSpecified < 0) {
            _settleDelta(sender, currency, uint128(-amountSpecified));
            amount = uint256(poolManager.currencyDelta(address(this), currency));
            poolManager.mint(address(this), currency.toId(), amount);
            IFeeFreeERC20(exchangeAddress).mint(sender, amount);
        } else {
            amount = uint128(amountSpecified);
            _takeDelta(to, currency, uint128(amountSpecified));
            poolManager.burn(address(this), currency.toId(), amount);
            IFeeFreeERC20(exchangeAddress).burn(sender, amount);
        }

        _collectFee(bytes32(0));

        return ZERO_BYTES;
    }

    function onQuoteSwap(Currency[] memory paths, int128 amountSpecified) external selfOnly returns (bytes memory) {
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
                (key, params) = _getSwapData(paths[i], paths[j], amountSpecified, 0);

                deltaAmounts[i] = amountSpecified;
                delta = poolManager.swap(key, params, ZERO_BYTES);
                (sqrtPriceX96Afters[i],,,) = poolManager.getSlot0(key.toId());

                deltaAmount = params.zeroForOne ? delta.amount1() : delta.amount0();
                amountSpecified = -deltaAmount;
                unchecked {
                    ++i;
                    ++j;
                }
            }
            deltaAmounts[step] = deltaAmount;
        } else {
            i = step;
            j = step - 1;
            while (i > 0) {
                (key, params) = _getSwapData(paths[j], paths[i], amountSpecified, 0);

                deltaAmounts[i] = amountSpecified;
                delta = poolManager.swap(key, params, ZERO_BYTES);
                (sqrtPriceX96Afters[j],,,) = poolManager.getSlot0(key.toId());

                deltaAmount = params.zeroForOne ? delta.amount0() : delta.amount1();
                amountSpecified = -deltaAmount;
                unchecked {
                    --i;
                    --j;
                }
            }
            deltaAmounts[0] = deltaAmount;
        }

        bytes memory result = abi.encode(deltaAmounts, sqrtPriceX96Afters);
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function onQuoteAddLiquidity(QuoteAddLiquidityParams calldata params) external selfOnly returns (bytes memory) {
        (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        (uint128 poolLiquidity, uint128 liquidity) = _getLiquidities(poolId, sqrtPriceX96, params.amount0Desired, params.amount1Desired);
        (BalanceDelta addedDelta,) = poolManager.modifyLiquidity(key, _getModifyLiquidityParams(liquidity.toInt256()), ZERO_BYTES);

        if (poolLiquidity == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            liquidity -= MINIMUM_LIQUIDITY;
        }

        bytes memory result = abi.encode(uint128(-addedDelta.amount0()), uint128(-addedDelta.amount1()), liquidity);
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function onQuoteRemoveLiquidity(QuoteRemoveLiquidityParams calldata params) external selfOnly returns (bytes memory) {
        (PoolKey memory key, , uint160 sqrtPriceX96) = _getPoolMeta(params.currency0, params.currency1);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        BalanceDelta delta = _removeLiquidity(key, _getModifyLiquidityParams(-(params.liquidity.toInt256())));

        bytes memory result = abi.encode(uint128(delta.amount0()), uint128(delta.amount1()));
        assembly {
            revert(add(0x20, result), mload(result))
        }
    }

    function setFeeController(IFeeController _feeController) external onlyOwner {
        feeController = _feeController;
    }

    function _modifyLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params) private returns (BalanceDelta delta) {
        delta = abi.decode(poolManager.unlock(abi.encodeWithSelector(this.onModifyLiquidity.selector, key, params, msg.sender)), (BalanceDelta));
    }

    function _removeLiquidity(PoolKey memory key, IPoolManager.ModifyLiquidityParams memory params) private returns (BalanceDelta delta) {
        PoolId poolId = key.toId();

        uint256 liquidityToRemove = FullMath.mulDiv(
            uint256(-params.liquidityDelta),
            poolManager.getLiquidity(poolId),
            IFeeFreeERC20(liquidityToken[poolId]).totalSupply()
        );

        params.liquidityDelta = -(liquidityToRemove.toInt256());
        (delta,) = poolManager.modifyLiquidity(key, params, ZERO_BYTES);
    }

    function _settleDelta(address sender, Currency currency, uint128 amount) private {
        if (currency.isNative()) {
            poolManager.settle{value: amount}(currency);
        } else {
            IERC20(Currency.unwrap(currency)).transferFrom(sender, address(poolManager), amount);
            poolManager.settle(currency);
        }
    }

    function _takeDelta(address to, Currency currency, uint128 amount) private {
        poolManager.take(currency, to, amount);
    }

    function _getSwapData(Currency input, Currency output, int128 amountSpecified, uint160 sqrtPriceLimitX96) private view returns (PoolKey memory key, IPoolManager.SwapParams memory params) {
        (Currency currency0, Currency currency1) = input < output ? (input, output) : (output, input);

        bool zeroForOne = input == currency0;
        if (sqrtPriceLimitX96 == 0) {
            sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO : MAX_SQRT_RATIO;
        }

        key = _getPoolKey(currency0, currency1);
        params = IPoolManager.SwapParams(zeroForOne, amountSpecified, sqrtPriceLimitX96);
    }

    function _getPoolKey(Currency currency0, Currency currency1) private view returns (PoolKey memory) {
        return PoolKey(currency0, currency1, 0x800000, 60, IHooks(address(this)));
    }

    function _getPoolMeta(Currency currency0, Currency currency1) private view returns (PoolKey memory key, PoolId poolId, uint160 sqrtPriceX96) {
        key = _getPoolKey(currency0, currency1);
        poolId = key.toId();
        (sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
    }

    function _getModifyLiquidityParams(int256 liquidityDelta) private pure returns (IPoolManager.ModifyLiquidityParams memory params) {
        params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: liquidityDelta
        });
    }

    function _getLiquidities(PoolId poolId, uint160 sqrtPriceX96, uint256 amount0, uint256 amount1) private view returns (uint128 poolLiquidity, uint128 liquidity) {
        poolLiquidity = poolManager.getLiquidity(poolId);

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            MIN_SQRT_RATIO,
            MAX_SQRT_RATIO,
            amount0,
            amount1
        );

        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }
    }

    function _getCurrencySymbol(Currency currency) private view returns (string memory) {
        return currency.isNative() ? NATIVE_SYMBOL : IERC20Metadata(Currency.unwrap(currency)).symbol();
    }

    function _collectFee(bytes32 id) private {
        if (address(feeController) != address(0)) {
            uint96 fee = feeController.fee();
            if (fee > 0) {
                feeController.collectFee{value:fee}(id);
            }
        }
    }
}
