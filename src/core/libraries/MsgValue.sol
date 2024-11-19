// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice This is a temporary library that allows us to use transient storage (tstore/tload)
library MsgValue {
    // The slot holding the locker state, transiently. bytes32(uint256(keccak256("msg.value")) - 1)
    bytes32 constant MSG_VALUE_SLOT = 0x6db8129b0eb46ff9c244864adb640599eb6526b25fcec38a32405b8f9c5ad6f0;

    function set(uint256 value) internal {
        assembly ("memory-safe") {
            tstore(MSG_VALUE_SLOT, value)
        }
    }

    function get() internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := tload(MSG_VALUE_SLOT)
        }
    }
}
