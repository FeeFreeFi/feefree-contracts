// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFactory {
    function deploy(string memory name, string memory symbol, uint256 totalSupply, address recipient) external returns (address pAddr, address nAddr);
}