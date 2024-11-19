// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeeController {
    error InsufficientFee();
    event FeeChanged(uint96 oldFee, uint96 newFee);

    function fee() external view returns (uint96);
    function collectFee(bytes32 id) external payable;
}