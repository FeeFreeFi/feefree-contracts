// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFeeFreeManager} from "../interfaces/IFeeFreeManager.sol";

/// @title Library for abi decoding in calldata
library CalldataDecoder {
    using CalldataDecoder for bytes;

    // error SliceOutOfBounds();

    /// @notice mask used for offsets and lengths to ensure no overflow
    /// @dev no sane abi encoding will pass in an offset or length greater than type(uint32).max
    ///      (note that this does deviate from standard solidity behavior and offsets/lengths will
    ///      be interpreted as mod type(uint32).max which will only impact malicious/buggy callers)
    uint256 constant OFFSET_OR_LENGTH_MASK = 0xffffffff;
    // uint256 constant OFFSET_OR_LENGTH_MASK_AND_WORD_ALIGN = 0xffffffe0;

    /// @notice equivalent to SliceOutOfBounds.selector, stored in least-significant bits
    uint256 constant SLICE_ERROR_SELECTOR = 0x3b99b53d;

    // /// @dev equivalent to: abi.decode(params, (uint256, bytes)) in calldata
    function decodeActionParams(bytes calldata params)
        internal
        pure
        returns (uint256 action, bytes calldata actionParams)
    {
        assembly ("memory-safe") {
            action := calldataload(params.offset)
        }

        actionParams = params.toBytes(1);
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.LaunchParams))
    function decodeLaunchParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.LaunchParams calldata launchParams)
    {
        assembly ("memory-safe") {
            launchParams := add(params.offset, calldataload(params.offset))
        }
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.InitializeParams))
    function decodeInitializeParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.InitializeParams calldata initializeParams)
    {
        assembly ("memory-safe") {
            initializeParams := params.offset
        }
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.AddLiquidityParams))
    function decodeAddLiquidityParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.AddLiquidityParams calldata addLiquidityParams)
    {
        assembly ("memory-safe") {
            addLiquidityParams := params.offset
        }
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.RemoveLiquidityParams))
    function decodeRemoveLiquidityParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.RemoveLiquidityParams calldata removeLiquidityParams)
    {
        assembly ("memory-safe") {
            removeLiquidityParams := params.offset
        }
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.SwapParams))
    function decodeSwapParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.SwapParams calldata swapParams)
    {
        assembly ("memory-safe") {
            swapParams := add(params.offset, calldataload(params.offset))
        }
    }

    /// @dev equivalent to: abi.decode(params, (IFeeFreeManager.ExchangeParams))
    function decodeExchangeParams(bytes calldata params)
        internal
        pure
        returns (IFeeFreeManager.ExchangeParams calldata exchangeParams)
    {
        assembly ("memory-safe") {
            exchangeParams := params.offset
        }
    }

    /// @notice Decode the `_arg`-th element in `_bytes` as `bytes`
    /// @param _bytes The input bytes string to extract a bytes string from
    /// @param _arg The index of the argument to extract
    function toBytes(bytes calldata _bytes, uint256 _arg) internal pure returns (bytes calldata res) {
        uint256 length;
        assembly ("memory-safe") {
            // The offset of the `_arg`-th element is `32 * arg`, which stores the offset of the length pointer.
            // shl(5, x) is equivalent to mul(32, x)
            let lengthPtr :=
                add(_bytes.offset, and(calldataload(add(_bytes.offset, shl(5, _arg))), OFFSET_OR_LENGTH_MASK))
            // the number of bytes in the bytes string
            length := and(calldataload(lengthPtr), OFFSET_OR_LENGTH_MASK)
            // the offset where the bytes string begins
            let offset := add(lengthPtr, 0x20)
            // assign the return parameters
            res.length := length
            res.offset := offset

            // if the provided bytes string isnt as long as the encoding says, revert
            if lt(add(_bytes.length, _bytes.offset), add(length, offset)) {
                mstore(0, SLICE_ERROR_SELECTOR)
                revert(0x1c, 4)
            }
        }
    }
}
