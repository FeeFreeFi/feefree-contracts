// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
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
    constructor(address _owner) Owned(_owner) {}

    function deploy(string memory name, string memory symbol, uint256 totalSupply, address recipient) external override onlyOwner returns (address pAddr, address nAddr) {
        ShortableToken tokenA = new ShortableToken(name, symbol, totalSupply, recipient);
        ShortableToken tokenB = new ShortableToken(name, symbol, totalSupply, recipient);

        pAddr = address(tokenA);
        nAddr = address(tokenB);

        tokenA.setOpponent(nAddr);
        tokenB.setOpponent(pAddr);

        if (pAddr > nAddr) (pAddr, nAddr) = (nAddr, pAddr);
    }
}