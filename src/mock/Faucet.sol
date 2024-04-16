// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Faucet {
    function send(IERC20 token, address to) external {
        token.transfer(to, 1e21);
    }
}