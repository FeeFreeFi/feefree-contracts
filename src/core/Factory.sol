// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Currency} from "../uniswap/types/Currency.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {ShortableToken} from "./ShortableToken.sol";

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
contract Factory is Owned, IFactory {
    string private constant NEGATIVE_SUFFIX = "-";

    constructor(address _owner) Owned(_owner) {}

    function deploy(string memory name, string memory symbol, uint256 totalSupply) external override onlyOwner returns (Currency positiveCurrency, Currency negativeCurrency) {
        ShortableToken pToken = new ShortableToken(name, symbol, totalSupply, msg.sender);
        ShortableToken nToken = new ShortableToken(string.concat(name, NEGATIVE_SUFFIX), string.concat(symbol, NEGATIVE_SUFFIX), totalSupply, msg.sender);

        address pAddr = address(pToken);
        address nAddr = address(nToken);

        pToken.setOpponent(nAddr);
        nToken.setOpponent(pAddr);

        positiveCurrency = Currency.wrap(pAddr);
        negativeCurrency = Currency.wrap(nAddr);
    }
}