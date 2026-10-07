// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Board preference in CrapsBattle's pass-credit words. The ID-keyed `_passCreditsById`
///      word holds normal passes [0:31], high passes [32:63], the compact board [64:83] and the
///      initialized bit [84]. The address-keyed `_passCredits` word holds the same board and
///      initialized lanes plus the holder's cached Game wallet ID [85:116]; its pass lanes are
///      zero. PASS_SLOT is `_passCreditsById`'s root for the raw reader, pinned against the
///      compiled storage layout by tests.
library CrapsPreferenceLib {
    uint256 internal constant PASS_SLOT = 15;
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

    /// @dev Decode only the preference, ignoring balances, sentinel and the cached wallet ID.
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
