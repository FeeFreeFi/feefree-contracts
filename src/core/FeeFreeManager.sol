// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {IUnlockCallback} from "../uniswap/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "../uniswap/types/Currency.sol";
import {BalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "../uniswap/types/PoolId.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IFeeFreeManager} from "./interfaces/IFeeFreeManager.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {ILiquidityToken} from "./interfaces/ILiquidityToken.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {CalldataDecoder} from "./libraries/CalldataDecoder.sol";
import {SlippageCheck} from "./libraries/SlippageCheck.sol";
import {PoolLibrary} from "./libraries/PoolLibrary.sol";
import {MsgValue} from "./libraries/MsgValue.sol";
import {PoolTags} from "./libraries/PoolTags.sol";
import {Actions} from "./libraries/Actions.sol";
import {ReentrancyLock} from "./base/ReentrancyLock.sol";

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
contract FeeFreeManager is ReentrancyLock, Owned, IUnlockCallback, IFeeFreeManager {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint128;
    using CalldataDecoder for bytes;
    using SlippageCheck for BalanceDelta;

    error Initialized();

    IPoolManager public immutable override poolManager;
    IHooks public immutable override hooks;
    IFeeManager public override feeManager;
    IFactory public override factory;
    ILiquidityToken public override liquidityToken;
    ITimelock public override timelock;

    mapping (PoolId => PoolInfo) public override getPoolInfo;

    constructor(address _owner, IPoolManager _poolManager, IHooks _hooks) Owned(_owner) {
        poolManager = _poolManager;
        hooks = _hooks;
    }

    /// @notice Only allow calls from the PoolManager contract
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @notice Reverts if the deadline has passed
    /// @param deadline The timestamp at which the call is no longer valid, passed in by the caller
    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlinePassed(deadline);
        _;
    }

    function init(IFactory _factory, ILiquidityToken _liquidityToken, IFeeManager _feeManager, ITimelock _timelock) external onlyOwner {
        if (address(factory) != address(0)) {
            revert Initialized();
        }

        factory = _factory;
        liquidityToken = _liquidityToken;
        feeManager = _feeManager;
        timelock = _timelock;

        liquidityToken.setOperator(address(timelock), true);
    }

    function setFeeManager(IFeeManager _feeManager) external onlyOwner {
        feeManager = _feeManager;
    }

    function rescue(Currency currency, address to, uint256 amount) external onlyOwner {
        currency.transfer(to, amount);
    }

    function launch(bytes calldata data) external payable override isNotLocked {
        _executeActions(data);
    }

    function initialize(bytes calldata data) external payable override isNotLocked {
        _executeActions(data);
    }

    function addLiquidity(bytes calldata data, uint256 deadline) external payable override isNotLocked checkDeadline(deadline) {
        _executeActions(data);
    }

    function removeLiquidity(bytes calldata data, uint256 deadline) external override isNotLocked checkDeadline(deadline) {
        _executeActions(data);
    }

    function swap(bytes calldata data, uint256 deadline) external payable override isNotLocked checkDeadline(deadline) {
        _executeActions(data);
    }

    function exchange(bytes calldata data) external payable override isNotLocked {
        _executeActions(data);
    }

    /// @inheritdoc IUnlockCallback
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (uint256 action, bytes calldata params) = data.decodeActionParams();
        _handleAction(action, params);

        return PoolLibrary.ZERO_BYTES;
    }

    function _executeActions(bytes calldata data) internal {
        MsgValue.set(msg.value);
        poolManager.unlock(data);
        MsgValue.set(0);
    }

    function _handleAction(uint256 action, bytes calldata params) internal {
        if (action == Actions.LAUNCH) {
            _launch(params.decodeLaunchParams());
            return;
        } else if (action == Actions.INITIALIZE) {
            _initialize(params.decodeInitializeParams());
            return;
        } else if (action == Actions.ADD_LIQUIDITY) {
            _addLiquidity(params.decodeAddLiquidityParams());
            return;
        } else if (action == Actions.REMOVE_LIQUIDITY) {
            _removeLiquidity(params.decodeRemoveLiquidityParams());
            return;
        } else if (action == Actions.SWAP) {
            _swap(params.decodeSwapParams());
            return;
        } else if (action == Actions.EXCHANGE) {
            _exchange(params.decodeExchangeParams());
            return;
        }

        revert UnsupportedAction(action);
    }

    function _launch(LaunchParams calldata params) internal {
        _checkAmount(params.asset.isAddressZero(), params.amount);

        (Currency pCurrency, Currency nCurrency) = factory.deploy(params.name, params.symbol, params.totalSupply);

        uint256 halfAmount = params.amount >> 1;
        uint256 halfSupply = params.totalSupply >> 1;
        (PoolId pId, uint128 pLiquidity) = _initOne(pCurrency, params.asset, halfSupply, halfAmount, params.recipient, params.duration);
        (PoolId nId, uint128 nLiquidity) = _initOne(nCurrency, params.asset, halfSupply, halfAmount, params.recipient, params.duration);

        address sender = _getLocker();
        _settle(params.asset, sender, uint256(-_currencyDelta(params.asset)));

        emit AddLiquidity(pId, sender, pLiquidity);
        emit AddLiquidity(nId, sender, nLiquidity);
    }

    function _initialize(InitializeParams calldata params) internal {
        (PoolKey memory key, PoolId id, uint128 liquidity, bool reverse) = _initializePool(params.currency0, params.currency1, params.amount0, params.amount1, false);

        BalanceDelta delta = _doAddLiquidity(key, liquidity, reverse ? params.amount1 : params.amount0);

        _checkout(key, liquidity, delta, params.recipient, params.duration);

        emit AddLiquidity(id, _getLocker(), liquidity);
    }

    function _addLiquidity(AddLiquidityParams calldata params) internal {
        (PoolKey memory key,) = PoolLibrary.getPoolKey(params.currency0, params.currency1, hooks);
        BalanceDelta delta = _doAddLiquidity(key, params.liquidity, params.amount0Max);
        delta.validateMaxIn(params.amount0Max, params.amount1Max);

        _checkout(key, params.liquidity, delta, params.recipient, 0);

        emit AddLiquidity(key.toId(), _getLocker(), params.liquidity);
    }

    function _removeLiquidity(RemoveLiquidityParams calldata params) internal {
        (PoolKey memory key,) = PoolLibrary.getPoolKey(params.currency0, params.currency1, hooks);
        PoolId id = key.toId();
        (BalanceDelta delta,) = poolManager.modifyLiquidity(
            key,
            PoolLibrary.getModifyLiquidityParams(-(params.liquidity.toInt256())),
            abi.encode(getPoolInfo[id].tag, address(feeManager), feeManager.lpFee())
        );
        delta.validateMinOut(params.amount0Min, params.amount1Min);

        _take(key.currency0, params.recipient, uint128(delta.amount0()));
        _take(key.currency1, params.recipient, uint128(delta.amount1()));

        address sender = _getLocker();
        liquidityToken.burn(sender, PoolLibrary.toTokenId(key),  params.liquidity);

        emit RemoveLiquidity(id, sender, params.liquidity);
    }

    function _swap(SwapParams calldata params) internal {
        uint256 i;
        uint256 j;
        int128 amountSpecified = params.amountSpecified;

        uint256 step = params.paths.length - 1;
        bool exactInput = amountSpecified < 0;
        if (exactInput) {
            j = 1;
            while (i < step) {
                unchecked {
                    amountSpecified = _swapOne(params.paths[i], params.paths[j], amountSpecified, false);
                    ++i;
                    ++j;
                }
            }
        } else {
            i = step - 1;
            j = step;
            while (j > 0) {
                unchecked {
                    amountSpecified = _swapOne(params.paths[i], params.paths[j], amountSpecified, true);
                    --i;
                    --j;
                }
            }
        }

        Currency input = params.paths[0];
        Currency output = params.paths[step];
        uint256 amountIn = uint256(-_currencyDelta(input));
        uint256 amountOut = uint256(_currencyDelta(output));

        bool isNative = input.isAddressZero();
        uint256 swapFee = feeManager.swapFee();
        uint256 value = isNative ? amountIn + swapFee : swapFee;

        if (isNative ? (MsgValue.get() < value) : (MsgValue.get() != value)) {
            revert InvalidAmount();
        }

        if (exactInput && amountOut < params.amountDesired) {
            revert TooLittleReceived(params.amountDesired, amountOut);
        } else if (!exactInput && amountIn > params.amountDesired) {
            revert TooMuchRequested(params.amountDesired, amountIn);
        }

        address sender = _getLocker();
        _settle(input, sender, amountIn);
        _take(output, params.recipient, amountOut);

        _charge(swapFee);
        _refund(value, sender);

        emit Swap(sender, input, output, amountIn, amountOut, swapFee);
    }

    function _exchange(ExchangeParams calldata params) internal {
        bool isIn = params.amountSpecified < 0;

        uint128 amount = isIn ? uint128(-params.amountSpecified) : uint128(params.amountSpecified);
        uint256 exchangeFee = feeManager.exchangeFee();

        uint256 value = params.currency.isAddressZero() && isIn ? amount + exchangeFee : exchangeFee;
        if (MsgValue.get() != value) {
            revert InvalidAmount();
        }

        address sender = _getLocker();
        uint256 tokenId = params.currency.toId();
        if (isIn) {
            _settle(params.currency, sender, amount);
            poolManager.mint(params.recipient, tokenId, amount);
        } else {
            _take(params.currency, params.recipient, amount);
            poolManager.burn(sender, tokenId, amount);
        }

        _charge(exchangeFee);

        emit Exchange(sender, params.currency, params.amountSpecified, exchangeFee);
    }

    function _initOne(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1, address recipient, uint256 duration) internal returns (PoolId, uint128) {
        (PoolKey memory key, PoolId id, uint128 liquidity, bool reverse) = _initializePool(currency0, currency1, amount0, amount1, true);

        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            PoolLibrary.getModifyLiquidityParams(liquidity.toInt256()),
            PoolLibrary.ZERO_BYTES
        );

        _mintLiquidity(PoolLibrary.toTokenId(key), liquidity, recipient, duration);

        _settle(currency0, address(this), uint128(reverse ? -delta.amount1() : -delta.amount0()));
        currency0.transfer(address(hooks), currency0.balanceOfSelf());

        return (id, liquidity);
    }

    function _initializePool(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1, bool isPairToken) internal returns (PoolKey memory key, PoolId id, uint128 liquidity, bool reverse) {
        (key, reverse)  = PoolLibrary.getPoolKey(currency0, currency1, hooks);
        id = key.toId();
        if (reverse) (amount0, amount1) = (amount1, amount0);

        uint160 sqrtPriceX96 = PoolLibrary.getSqrtPriceX96(amount0, amount1);
        liquidity = PoolLibrary.getLiquidityForAmounts(sqrtPriceX96, amount0, amount1);

        poolManager.initialize(key, sqrtPriceX96);

        getPoolInfo[id] = PoolInfo({
            currency0: key.currency0,
            currency1: key.currency1,
            tag: isPairToken ? (reverse ? PoolTags.ONE : PoolTags.ZERO) : PoolTags.DEFAULT
        });
    }

    function _doAddLiquidity(PoolKey memory key, uint128 liquidity, uint256 amount0) internal returns (BalanceDelta delta) {
        _checkAmount(key.currency0.isAddressZero(), amount0);

        (delta, ) = poolManager.modifyLiquidity(
            key,
            PoolLibrary.getModifyLiquidityParams(liquidity.toInt256()),
            PoolLibrary.ZERO_BYTES
        );
    }

    function _checkout(PoolKey memory key, uint128 liquidity, BalanceDelta delta, address recipient, uint256 duration) internal {
        _mintLiquidity(PoolLibrary.toTokenId(key), liquidity, recipient, duration);

        address sender = _getLocker();
        uint128 amount0 = uint128(-delta.amount0());
        _settle(key.currency0, sender, amount0);
        _settle(key.currency1, sender, uint128(-delta.amount1()));

        if (key.currency0.isAddressZero()) {
            _refund(amount0, sender);
        }
    }

    function _mintLiquidity(uint256 tokenId, uint256 liquidity, address recipient, uint256 duration) internal {
        if (duration > 0) {
            liquidityToken.mint(address(this), tokenId, liquidity);
            timelock.lock(liquidityToken, address(this), tokenId, liquidity, duration + block.timestamp, recipient);
        } else {
            liquidityToken.mint(recipient, tokenId, liquidity);
        }
    }

    function _checkAmount(bool isNative, uint256 amount) internal view {
        if (MsgValue.get() != (isNative ? amount : 0)) {
            revert InvalidAmount();
        }
    }

    function _charge(uint256 swapFee) internal {
        if (swapFee > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(address(feeManager), swapFee);
        }
    }

    function _refund(uint256 paid, address sender) internal {
        uint256 remain = MsgValue.get() - paid;
        if (remain > 0) {
            CurrencyLibrary.ADDRESS_ZERO.transfer(sender, remain);
        }
    }

    function _swapOne(Currency input, Currency output, int128 amountSpecified, bool direction) internal returns (int128) {
        (PoolKey memory key, bool reverse) = PoolLibrary.getPoolKey(input, output, hooks);

        PoolId id = key.toId();
        (uint160 sqrtPriceX96, uint128 liquidity) = poolManager.getSqrtPriceX96AndLiquidity(id);

        BalanceDelta delta = poolManager.swap(
            key,
            PoolLibrary.getSwapData(!reverse, amountSpecified),
            abi.encode(sqrtPriceX96, liquidity, getPoolInfo[id].tag)
        );

        return reverse != direction ? -delta.amount0() : -delta.amount1();
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
    /// @param payer Address of the payer
    /// @param amount Amount to send
    /// @dev Returns early if the amount is 0
    function _settle(Currency currency, address payer, uint256 amount) internal {
        if (amount == 0) return;
        if (currency.isAddressZero()) {
            poolManager.settle{value: amount}();
        } else {
            poolManager.sync(currency);
            _pay(currency, payer, amount);
            poolManager.settle();
        }
    }

    /// @notice Abstract function for contracts to implement paying tokens to the poolManager
    /// @dev The recipient of the payment should be the poolManager
    /// @param currency The currency to settle. This is known not to be the native currency
    /// @param payer The address who should pay tokens
    /// @param amount The number of tokens to send
    function _pay(Currency currency, address payer, uint256 amount) internal {
        if (payer == address(this)) {
            currency.transfer(address(poolManager), amount);
        } else {
            IERC20(Currency.unwrap(currency)).transferFrom(payer, address(poolManager), amount);
        }
    }

    function _currencyDelta(Currency currency) internal view returns (int256) {
        return poolManager.currencyDelta(address(this), currency);
    }
}
