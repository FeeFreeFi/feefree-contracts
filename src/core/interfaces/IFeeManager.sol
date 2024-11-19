// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeManager {
    function swapFee() external view returns (uint256);
    function exchangeFee() external view returns (uint256);
    function lpFee() external view returns (uint24);
}