// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {MerkleProofLib} from "solmate/src/utils/MerkleProofLib.sol";
import {Currency, CurrencyLibrary} from "../uniswap/types/Currency.sol";
import {IFeeController} from "./interfaces/IFeeController.sol";

contract FeeController is IFeeController {
    using CurrencyLibrary for Currency;

    Currency public constant NATIVE = Currency.wrap(address(0));

    address public owner;
    uint96 public override fee;
    bytes32 public root;
    uint256 public deadline;

    mapping(bytes32 => bool) private _leavesClaimed;

    error InvalidCaller();
    error InvalidProof();
    error ClaimExpired();
    error AlreadyClaimed();

    event OwnerChanged(address oldOwner, address newOwner);
    event RootChanged(bytes32 oldRoot, bytes32 newRoot, uint256 deadline);
    event Claim(address indexed account, uint256 amount, bytes32 leaf, bytes32 root);

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

    function updateRoot(bytes32 newRoot, uint256 newDeadline) external onlyOwner {
        emit RootChanged(root, newRoot, newDeadline);
        root = newRoot;
        deadline = newDeadline;
    }

    function withdraw(address to, uint256 amount) external onlyOwner {
        NATIVE.transfer(to, amount);
    }

    function rescue(address token, address to, uint256 amount) external onlyOwner {
        Currency.wrap(token).transfer(to, amount);
    }

    function collectFee(bytes32) external payable override {
        uint96 _fee = fee;
        if (_fee == 0) return;

        if (msg.value < _fee) {
            revert InsufficientFee();
        }
    }

    function claim(uint256 amount, address to, bytes32 nonce, bytes32[] calldata proof) external {
        if (deadline < block.timestamp) {
            revert ClaimExpired();
        }

        bytes32 leaf = keccak256(abi.encode(msg.sender, amount, nonce));
        bool isValid = MerkleProofLib.verify(proof, root, leaf);
        if (!isValid) {
            revert InvalidProof();
        }

        if (_leavesClaimed[leaf]) {
            revert AlreadyClaimed();
        }

        _leavesClaimed[leaf] = true;
        NATIVE.transfer(to, amount);

        emit Claim(msg.sender, amount, leaf, root);
    }

    receive() external payable {}
}