// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev One ID-keyed pass-credit word holds normal passes [0:31], high passes [32:63],
///      compact board [64:83] and initialized bit [84]. Door helpers carry an ID in memory
///      above bit 84; it is never persisted. PASS_SLOT is pinned against compiled storage.
library CrapsPreferenceLib {
    uint256 internal constant PASS_SLOT = 14;
    uint256 internal constant SHIFT = 64;
    uint256 internal constant MASK = 0xFFFFF << SHIFT;
    uint256 internal constant INITIALIZED = 1 << 84;
    uint256 internal constant ID_SHIFT = 85;

    /// @dev Compress an ALREADY VALIDATED canonical board (three bits per leg) to two bits.
    function compress(uint256 chips) internal pure returns (uint256 compact) {
        unchecked {
            for (uint256 shift; chips != 0; shift += 2) {
                compact |= (chips & 3) << shift;
                chips >>= 3;
            }
        }
    }

    /// @dev Decode only the preference, ignoring balances, sentinel and temporary memory ID.
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
