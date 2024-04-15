// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeeController} from "./interfaces/IFeeController.sol";

contract FeeController is IFeeController {
    address public owner;
    uint96 public override fee;

    error InvalidCaller();
    error WithdrawFail();
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    mapping(bytes32 => uint256) public poolFees;

    constructor(address _owner, uint96 _fee) {
        owner = _owner;
        fee = _fee;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidCaller();
        _;
    }

    function setOwner(address _owner) external onlyOwner {
        emit OwnerChanged(owner, _owner);
        owner = _owner;
    }

    function setFee(uint96 newFee) external onlyOwner {
        uint96 oldFee = fee;
        fee = newFee;
        emit FeeChanged(oldFee, newFee);
    }

    function collectFee(bytes32 id) external payable override {
        uint96 _fee = fee;
        if (_fee == 0) return;

        if (msg.value < _fee) {
            revert InsufficientFee();
        }

        poolFees[id] += msg.value;
    }

    function withdrawFee(bytes32 id, uint256 amount, address to) external onlyOwner {
        poolFees[id] -= amount;

        bool success;
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) revert WithdrawFail();
    }
}