// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @dev Replayable bounded survivor field, shared by settlement and the Lens.
library DecimatorSamplingLib {
    bytes32 internal constant SAMPLE_TAG = keccak256("decimator.battle.sample.v1");

    struct Field {
        uint256 entries;
        uint256 count;
        uint256 rotate;
    }

    function field(uint256 word, uint24 lvl, uint256 entries) internal pure returns (Field memory) {
        return Field(entries, survivors(entries), rotation(word, lvl, entries));
    }

    function sample(uint256 word, uint24 lvl, Field memory f, uint256 stratum)
        internal pure returns (uint64)
    {
        return sample(word, lvl, f.entries, f.count, f.rotate, stratum);
    }

    function survivors(uint256 entries) internal pure returns (uint16) {
        uint256 count = (entries + 1) / 2;
        return uint16(count > 1000 ? 1000 : count);
    }

    function rotation(uint256 word, uint24 lvl, uint256 entries) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(SAMPLE_TAG, word, lvl))) % entries;
    }

    /// @dev Disjoint strata give distinct positions; the common rotation preserves uniqueness
    ///      and makes each slot occur equally often across all possible rotations.
    ///      Both workers cache count/rotation. Internal callers supply a valid stratum.
    function sample(uint256 word, uint24 lvl, uint256 entries, uint256 count, uint256 rotate, uint256 stratum)
        internal pure returns (uint64)
    {
        uint256 lo = stratum * entries / count;
        uint256 hi = (stratum + 1) * entries / count;
        uint256 pos = lo + uint256(keccak256(abi.encode(SAMPLE_TAG, word, lvl, stratum))) % (hi - lo);
        return uint64((pos + rotate) % entries + 1);
    }
}
