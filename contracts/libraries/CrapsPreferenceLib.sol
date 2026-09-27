// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Address-wide board in CrapsBattle's pass-credit word. The raw reader's base slot is
///      pinned against the actual storage layout by CrapsPreferredBoard tests.
library CrapsPreferenceLib {
    uint256 internal constant PASS_SLOT = 15;
    uint256 internal constant SHIFT = 64;
    uint256 internal constant MASK = 0xFFFFF << SHIFT;
    uint256 internal constant INITIALIZED = 1 << 84;

    /// @dev Compress an ALREADY VALIDATED canonical board (three bits per leg) to two bits.
    function compress(uint256 chips) internal pure returns (uint256 compact) {
        unchecked {
            for (uint256 shift; chips != 0; shift += 2) {
                compact |= (chips & 3) << shift;
                chips >>= 3;
            }
        }
    }

    /// @dev Decode only the preference, ignoring balances, sentinel, and reserved high bits.
    function decode(uint256 word) internal pure returns (uint32 chips, uint256 placed) {
        uint256 compact = (word & MASK) >> SHIFT;
        unchecked {
            for (uint256 shift; compact != 0; shift += 3) {
                uint256 count = compact & 3;
                chips |= uint32(count << shift);
                placed += count;
                compact >>= 2;
            }
        }
    }
}
