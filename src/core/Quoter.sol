// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {IUnlockCallback} from "../uniswap/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {PoolId, PoolIdLibrary} from "../uniswap/types/PoolId.sol";
import {Currency} from "../uniswap/types/Currency.sol";
import {BalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {IFeeFreeManager} from "./interfaces/IFeeFreeManager.sol";
import {IQuoter} from "./interfaces/IQuoter.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {ILiquidityToken} from "./interfaces/ILiquidityToken.sol";
import {ITimelock} from "./interfaces/ITimelock.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {IERC721Capped} from "./interfaces/IERC721Capped.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {PoolLibrary} from "./libraries/PoolLibrary.sol";
import {PoolTags} from "./libraries/PoolTags.sol";
import {FeeLibrary} from "./libraries/FeeLibrary.sol";

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
contract Quoter is IUnlockCallback, IQuoter {
    using StateLibrary for IPoolManager;
    using SafeCast for int128;
    using SafeCast for uint128;
    using SafeCast for int256;
    using PoolIdLibrary for PoolKey;

    error UnexpectedCallSuccess();
    /// @notice Thrown when calling unlockCallback where the caller is not PoolManager
    error NotPoolManager();

    error QuoteSwap(uint128 amountIn, uint128 amountOut);

    IFeeFreeManager public immutable manager;
    IPoolManager public immutable poolManager;
    IHooks public immutable hooks;
    ILiquidityToken public immutable liquidityToken;
    ITimelock public immutable timelock;
    string private nativeLabel;

    constructor(IFeeFreeManager _manager, string memory _nativeLabel) {
        manager = _manager;
        poolManager = manager.poolManager();
        hooks = manager.hooks();
        liquidityToken = manager.liquidityToken();
        timelock = manager.timelock();
        nativeLabel = _nativeLabel;
    }

    /// @notice Only allow calls from the PoolManager contract
    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    function addLiquidity(AddLiquidityParams calldata params) external view override returns (uint128 amount0Desired, uint128 amount1Desired, uint128 liquidity) {
        uint160 sqrtPriceX96 = poolManager.getSqrtPriceX96(_getPoolId(params.currency0, params.currency1));
        liquidity = PoolLibrary.getLiquidityForAmounts(sqrtPriceX96, params.amount0Max, params.amount1Max);
        (int128 amount0, int128 amount1) = PoolLibrary.getAmountsForLiquidity(sqrtPriceX96, liquidity.toInt128());

        amount0Desired = (-amount0).toUint128();
        amount1Desired = (-amount1).toUint128();
    }

    function removeLiquidity(RemoveLiquidityParams calldata params) external view override returns (uint128 amount0Min, uint128 amount1Min) {
        PoolId id = _getPoolId(params.currency0, params.currency1);

        uint160 sqrtPriceX96 = poolManager.getSqrtPriceX96(id);
        (int128 amount0, int128 amount1) = PoolLibrary.getAmountsForLiquidity(sqrtPriceX96, -(params.liquidity.toInt128()));

        (,,uint8 tag) = manager.getPoolInfo(id);
        if (tag != PoolTags.DEFAULT) {
            (amount0Min, amount1Min) = FeeLibrary.getAmountsAfterFee(amount0.toUint128(), amount1.toUint128(), manager.feeManager().lpFee());
        } else {
            amount0Min = amount0.toUint128();
            amount1Min = amount1.toUint128();
        }
    }

    function swap(SwapParams calldata params) external override returns (uint128 amountIn, uint128 amountOut) {
        try poolManager.unlock(abi.encodeCall(this._swap, (params))) {}
        catch (bytes memory reason) {
            assembly ("memory-safe") {
                amountIn := mload(add(reason, 0x24))
                amountOut := mload(add(reason, 0x44))
            }
        }
    }

    function getTokenMeta(Currency currency) public view override returns (TokenMeta memory meta) {
        if (currency.isAddressZero()) {
            meta.name = nativeLabel;
            meta.symbol = nativeLabel;
            meta.decimals = 18;
        } else {
            IERC20Metadata metadata = IERC20Metadata(Currency.unwrap(currency));
            meta.addr = Currency.unwrap(currency);
            meta.name = metadata.name();
            meta.symbol = metadata.symbol();
            meta.decimals = metadata.decimals();
        }
    }

    function getPoolKey(Currency currency0, Currency currency1) external view override returns (PoolKey memory key) {
        (key, ) = PoolLibrary.getPoolKey(currency0, currency1, hooks);
    }

    function getPoolMeta(PoolId id) external view override returns (PoolMeta memory meta) {
        (Currency currency0, Currency currency1, uint8 tag) = manager.getPoolInfo(id);

        meta.id = id;
        meta.token0 = getTokenMeta(currency0);
        meta.token1 = getTokenMeta(currency1);
        meta.tag = tag;
    }

    function getPoolState(PoolId id) public view override returns (uint160 sqrtPriceX96, uint128 liquidity) {
        (sqrtPriceX96, liquidity) = poolManager.getSqrtPriceX96AndLiquidity(id);
    }

    function getPoolIds(address account) external view override returns (PoolId[] memory result) {
        uint256[] memory ids1 = liquidityToken.getOwnedIds(account);
        uint256[] memory ids2 = timelock.getTokenIds(account);

        uint256 len1 = ids1.length;
        uint256 len2 = ids2.length;
        uint256 count = len1 + len2;
        result = new PoolId[](count);

        uint256 i = 0;
        for (; i < len1;) {
            result[i] = PoolId.wrap(bytes32(ids1[i]));
            unchecked {
                ++i;
            }
        }

        for (i = 0; i < len2;) {
            result[i + len1] = PoolId.wrap(bytes32(ids2[i]));
            unchecked {
                ++i;
            }
        }
    }

    function getLockDatas(address account, PoolId id) external view override returns (ITimelock.LockData[] memory result) {
        bytes32[] memory lockIds = timelock.getLockIds(account, uint256(PoolId.unwrap(id)));

        uint256 length = lockIds.length;
        result = new ITimelock.LockData[](length);
        for (uint256 i = 0; i < length; ) {
            result[i] = timelock.getLockData(lockIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    function getFees() public view override returns (uint256 swapFee, uint256 exchangeFee, uint24 lpFee) {
        IFeeManager feeManager = manager.feeManager();
        swapFee = feeManager.swapFee();
        exchangeFee = feeManager.exchangeFee();
        lpFee = feeManager.lpFee();
    }

    function getMinted(IERC721Capped[] memory nfts) external view override returns (uint256[] memory result) {
        uint256 length = nfts.length;
        result = new uint256[](length);
        for (uint256 i = 0; i < length; ) {
            result[i] = nfts[i].totalSupply();
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUnlockCallback
    /// @dev We force the onlyPoolManager modifier by exposing a virtual function after the onlyPoolManager check.
    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) revert UnexpectedCallSuccess();

        assembly ("memory-safe") {
            revert(add(returnData, 0x20), mload(returnData))
        }
    }

    function _swap(SwapParams calldata params) external returns (bytes memory) {
        uint256 i;
        uint256 j;
        int128 amountSpecified = params.amountSpecified;

        uint256 step = params.paths.length - 1;
        if (amountSpecified < 0) {
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

        revert QuoteSwap(uint128(-_currencyDelta(params.paths[0])), uint128(_currencyDelta(params.paths[step])));
    }

    function _swapOne(Currency input, Currency output, int128 amountSpecified, bool direction) internal returns (int128) {
        (PoolKey memory key, bool reverse) = PoolLibrary.getPoolKey(input, output, hooks);

        PoolId id = key.toId();
        (uint160 sqrtPriceX96, uint128 liquidity) = getPoolState(id);

        (,,uint8 tag) = manager.getPoolInfo(id);
        BalanceDelta delta = poolManager.swap(
            key,
            PoolLibrary.getSwapData(!reverse, amountSpecified),
            abi.encode(sqrtPriceX96, liquidity, tag)
        );

        return reverse != direction ? -delta.amount0() : -delta.amount1();
    }

    function _getPoolId(Currency currency0, Currency currency1) internal view returns (PoolId) {
        (PoolKey memory key,) = PoolLibrary.getPoolKey(currency0, currency1, hooks);
        return key.toId();
    }

    function _currencyDelta(Currency currency) internal view returns (int128) {
        return poolManager.currencyDelta(address(this), currency).toInt128();
    }
}
