// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract DAI is ERC20 {
    constructor() ERC20("DAI", "DAI", 18) {
        _mint(msg.sender, 1e40);
    }
}