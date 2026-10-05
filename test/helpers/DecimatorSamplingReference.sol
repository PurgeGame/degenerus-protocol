// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Test oracle expressed in unrotated coordinates, independently of worker cursors.
library DecimatorSampleReference {
    bytes32 private constant TAG = keccak256("decimator.battle.sample.v1");

    function count(uint256 total) internal pure returns (uint16) {
        return uint16((total + 1) / 2 < 1000 ? (total + 1) / 2 : 1000);
    }

    function at(uint256 word, uint24 lvl, uint256 total, uint256 stratum) internal pure returns (uint64) {
        uint256 n = count(total);
        uint256 start = stratum * total / n;
        uint256 width = (stratum + 1) * total / n - start;
        uint256 rotation = uint256(keccak256(abi.encode(TAG, word, lvl))) % total;
        uint256 offset = uint256(keccak256(abi.encode(TAG, word, lvl, stratum))) % width;
        return uint64((rotation + start + offset) % total + 1);
    }

    /// @dev Invert the rotation, then find the unique stratum containing the candidate.
    ///      This checks winner membership without rescanning either entries or strata.
    function contains(uint256 word, uint24 lvl, uint256 total, uint64 id) internal pure returns (bool) {
        if (id == 0 || id > total) return false;
        uint256 rotation = uint256(keccak256(abi.encode(TAG, word, lvl))) % total;
        uint256 pos = (uint256(id) - 1 + total - rotation) % total;
        uint256 stratum = ((pos + 1) * count(total) - 1) / total;
        return at(word, lvl, total, stratum) == id;
    }
}
