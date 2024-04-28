// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IFeeController} from "./interfaces/IFeeController.sol";

contract FeeController is IFeeController {
    address public owner;
    uint96 public override fee;

    error InvalidCaller();
    error WithdrawFail();
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);

    mapping(bytes32 => uint256) public poolFee;

    constructor(address _owner, uint96 _fee) {
        owner = _owner;
        fee = _fee;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert InvalidCaller();
        _;
    }

    function setOwner(address newOwner) external onlyOwner {
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setFee(uint96 newFee) external onlyOwner {
        emit FeeChanged(fee, newFee);
        fee = newFee;
    }

    function collectFee(bytes32 id) external payable override {
        uint96 _fee = fee;
        if (_fee == 0) return;

        if (msg.value < _fee) {
            revert InsufficientFee();
        }

        poolFee[id] += msg.value;
    }

    function withdrawFee(bytes32 id, uint256 amount, address to) external onlyOwner {
        poolFee[id] -= amount;

        bool success;
        assembly {
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) revert WithdrawFail();
    }

    receive() external payable {
        poolFee[bytes32(0)] += msg.value;
    }
}