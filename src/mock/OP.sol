// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

contract OP is ERC20 {
    constructor() ERC20("OP", "OP", 18) {
        _mint(msg.sender, 1e40);
    }
}
