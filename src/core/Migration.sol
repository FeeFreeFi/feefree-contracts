// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "../uniswap/interfaces/IPoolManager.sol";
import {IHooks} from "../uniswap/interfaces/IHooks.sol";
import {Currency} from "../uniswap/types/Currency.sol";
import {PoolKey} from "../uniswap/types/PoolKey.sol";
import {BalanceDelta} from "../uniswap/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "../uniswap/types/PoolId.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IFeeFreeManager} from "./interfaces/IFeeFreeManager.sol";
import {IFeeFreeRouter} from "./old/interfaces/IFeeFreeRouter.sol";
import {SafeCast} from "../uniswap/libraries/SafeCast.sol";
import {PoolLibrary} from "./libraries/PoolLibrary.sol";
import {StateLibrary} from "./libraries/StateLibrary.sol";
import {Actions} from "./libraries/Actions.sol";

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
contract Migration {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SafeCast for int128;

    IFeeFreeRouter public immutable router;
    IFeeFreeManager public immutable manager;
    IHooks public immutable hooks;
    IPoolManager public immutable poolManager;

    constructor(IFeeFreeRouter _router, IFeeFreeManager _manager) {
        router = _router;
        manager = _manager;
        hooks = manager.hooks();
        poolManager = manager.poolManager();
    }

    function unexchange(Currency currency) external payable {
        IERC20 exchange = IERC20(router.exchangeToken(Currency.unwrap(currency)));
        uint256 amount = exchange.balanceOf(msg.sender);
        exchange.transferFrom(msg.sender, address(this), amount);

        router.exchange{value:msg.value}(IFeeFreeRouter.ExchangeParams({
            currency: currency,
            amountSpecified: amount.toInt128(),
            to: msg.sender
        }));
    }

    function removeLiquidity(PoolKey memory key) external {
        (uint128 amount0, uint128 amount1) = _removeLiquidity(key);

        key.currency0.transfer(msg.sender, amount0);
        key.currency1.transfer(msg.sender, amount1);
    }

    function migrateLiquidity(PoolKey memory key) external {
        (uint128 amount0Out, uint128 amount1Out) = _removeLiquidity(key);

        (key,) = PoolLibrary.getPoolKey(key.currency0, key.currency1, hooks);
        uint160 sqrtPriceX96 = poolManager.getSqrtPriceX96(key.toId());
        uint128 liquidity = PoolLibrary.getLiquidityForAmounts(sqrtPriceX96, amount0Out, amount1Out);
        (int128 _amount0, int128 _amount1) = PoolLibrary.getAmountsForLiquidity(sqrtPriceX96, liquidity.toInt128());
        uint128 amount0 = (-_amount0).toUint128();
        uint128 amount1 = (-_amount1).toUint128();

        _approve(key.currency0, amount0);
        _approve(key.currency1, amount1);

        IFeeFreeManager.AddLiquidityParams memory params = IFeeFreeManager.AddLiquidityParams({
            currency0: key.currency0,
            currency1: key.currency1,
            liquidity: liquidity,
            amount0Max: amount0,
            amount1Max: amount1,
            recipient: msg.sender
        });
        bytes memory data = abi.encode(Actions.ADD_LIQUIDITY, abi.encode(params));

        uint256 value = key.currency0.isAddressZero() ? amount0 : 0;
        manager.addLiquidity{value:value}(data, (block.timestamp + 1800));

        _transfer(key.currency0, msg.sender, key.currency0.balanceOfSelf());
        _transfer(key.currency1, msg.sender, key.currency1.balanceOfSelf());
    }

    function _removeLiquidity(PoolKey memory key) internal returns (uint128 amount0, uint128 amount1) {
        IERC20 liquidity = IERC20(router.liquidityToken(key.toId()));
        uint256 amount = liquidity.balanceOf(msg.sender);
        liquidity.transferFrom(msg.sender, address(this), amount);
        liquidity.approve(address(router), amount);

        BalanceDelta delta = router.removeLiquidity(IFeeFreeRouter.RemoveLiquidityParams({
            currency0: key.currency0,
            currency1: key.currency1,
            liquidity: amount.toUint128(),
            deadline: uint96(block.timestamp + 1800)
        }));

        amount0 = delta.amount0().toUint128();
        amount1 = delta.amount1().toUint128();
    }

    function _transfer(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;
        currency.transfer(to, amount);
    }

    function _approve(Currency currency, uint256 amount) internal {
        if (!currency.isAddressZero()) {
            IERC20(Currency.unwrap(currency)).approve(address(manager), amount);
        }
    }

    receive() external payable {}
}