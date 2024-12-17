// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "./base/ERC20.sol";

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
contract ShortableToken is ERC20 {
    string private constant NEGATIVE_SUFFIX = "-";

    address public opponent;
    bool public positive;

    error OpponentExisted();

    constructor(string memory name, string memory symbol, uint256 totalSupply, address recipient) ERC20(name, symbol, 18) {
        _mint(recipient, totalSupply);
    }

    function setOpponent(address _opponent) public {
        if (address(opponent) != address(0)) {
            revert OpponentExisted();
        }

        opponent = _opponent;

        positive = address(this) < _opponent;
        if (!positive) {
            name = string.concat(name, NEGATIVE_SUFFIX);
            symbol = string.concat(symbol, NEGATIVE_SUFFIX);
        }
    }
}
