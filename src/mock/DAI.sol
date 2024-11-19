// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "../core/base/ERC20.sol";

contract DAI is ERC20 {
    constructor(address to) ERC20("DAI", "DAI", 18) {
        _mint(to, 1e64);
    }
}