// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @title PendingPools
/// @notice Decodes a raw prizePoolPendingPacked word for tests that read the slot directly.
/// @dev Bit 255 is the slot's nonzero sentinel, never pool value; the future half holds 127 bits.
library PendingPools {
    uint256 internal constant SENTINEL = uint256(1) << 255;
    uint256 internal constant FUTURE_MASK = type(uint128).max >> 1;

    function next(uint256 packed) internal pure returns (uint256) {
        return uint128(packed);
    }

    function future(uint256 packed) internal pure returns (uint256) {
        return (packed >> 128) & FUTURE_MASK;
    }

    /// @dev Value bits only: zero whenever the pools are unfrozen.
    function value(uint256 packed) internal pure returns (uint256) {
        return packed & ~SENTINEL;
    }
}
