// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {MerkleProofLib} from "solmate/src/utils/MerkleProofLib.sol";
import {Currency, CurrencyLibrary} from "../uniswap/types/Currency.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/***
 *    00000000\                  00000000\
 *    00  _____|                 00  _____|
 *    00 |    000000\   000000\  00 |    000000\   000000\   000000\
 *    00000\ 00  __00\ 00  __00\ 00000\ 00  __00\ 00  __00\ 00  __00\
 *    00  __|00000000 |00000000 |00  __|00 |  \__|00000000 |00000000 |
 *    00 |   00   ____|00   ____|00 |   00 |      00   ____|00   ____|
 *    00 |   \0000000\ \0000000\ 00 |   00 |      \0000000\ \0000000\
 *    \__|    \_______| \_______|\__|   \__|       \_______| \_______|
 */
contract FeeManager is Owned, IFeeManager {
    error InvalidProof();
    error ClaimExpired();
    error AlreadyClaimed();

    event SwapFeeChange(uint256 oldFee, uint256 newFee);
    event ExchangeFeeChange(uint256 oldFee, uint256 newFee);
    event LpFeeChange(uint24 oldFee, uint24 newFee);

    event RootChange(bytes32 oldRoot, bytes32 newRoot, uint256 deadline);
    event Claim(address indexed account, uint256 amount, bytes32 leaf, bytes32 root);

    uint256 public override swapFee;
    uint256 public override exchangeFee;
    uint24 public override lpFee;
    bytes32 public root;
    uint256 public deadline;

    mapping(bytes32 => bool) private _leavesClaimed;

    constructor(uint256 _swapFee, uint256 _exchangeFee, uint24 _lpFee) Owned(msg.sender) {
        swapFee = _swapFee;
        exchangeFee = _exchangeFee;
        lpFee = _lpFee;
    }

    function setSwapFee(uint256 _swapFee) external onlyOwner {
        emit SwapFeeChange(swapFee, _swapFee);
        swapFee = _swapFee;
    }

    function setExchangeFee(uint256 _exchangeFee) external onlyOwner {
        emit ExchangeFeeChange(exchangeFee, _exchangeFee);
        exchangeFee = _exchangeFee;
    }

    function setLpFee(uint24 _lpFee) external onlyOwner {
        emit LpFeeChange(lpFee, _lpFee);
        lpFee = _lpFee;
    }

    function withdraw(Currency currency, address to, uint256 amount) external onlyOwner {
        currency.transfer(to, amount);
    }

    function updateRoot(bytes32 newRoot, uint256 newDeadline) external onlyOwner {
        emit RootChange(root, newRoot, newDeadline);
        root = newRoot;
        deadline = newDeadline;
    }

    function claim(uint256 amount, address to, bytes32 nonce, bytes32[] calldata proof) external {
        if (deadline < block.timestamp) {
            revert ClaimExpired();
        }

        bytes32 leaf = _getLeaf(msg.sender, amount, nonce);
        if (!_isValidLeaf(leaf, proof)) {
            revert InvalidProof();
        }

        if (_leavesClaimed[leaf]) {
            revert AlreadyClaimed();
        }

        _leavesClaimed[leaf] = true;
        CurrencyLibrary.ADDRESS_ZERO.transfer(to, amount);

        emit Claim(msg.sender, amount, leaf, root);
    }

    function isValid(address account, uint256 amount, bytes32 nonce, bytes32[] calldata proof) external view returns (bool) {
        bytes32 leaf = _getLeaf(account, amount, nonce);
        return _isValidLeaf(leaf, proof) && !_leavesClaimed[leaf];
    }

    function _getLeaf(address account, uint256 amount, bytes32 nonce) private pure returns (bytes32) {
        return keccak256(abi.encode(account, amount, nonce));
    }

    function _isValidLeaf(bytes32 leaf, bytes32[] calldata proof) private view returns (bool) {
        return MerkleProofLib.verify(proof, root, leaf);
    }

    receive() external payable {}
}