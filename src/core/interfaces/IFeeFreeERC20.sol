// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeFreeERC20 {
    function totalSupply() external view returns (uint256);
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}
