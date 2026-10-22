// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Isolated R90 codec. Production callers and settlement are tested separately.
contract CoinflipRingPrototype {
    mapping(uint32 => uint256[15]) public ring;
    mapping(uint32 => mapping(uint24 => uint256)) public overflow;
    mapping(uint32 => uint24) public claimed;
    uint24 public frontier;
    uint256 private constant CAP = type(uint32).max;

    error StakeAboveDailyCap();

    function setFrontier(uint24 day) external {
        require(day >= frontier);
        frontier = day;
    }

    function claimThrough(uint32 id, uint24 day) external {
        require(day >= claimed[id] && day <= frontier);
        claimed[id] = day;
    }

    function stake(uint32 id, uint24 day) external view returns (uint256) {
        uint24 page = day / 7;
        uint256 word = ring[id][page % 15];
        if (uint24(word >> 224) != page + 1) word = overflow[id][page];
        if (uint24(word >> 224) != page + 1) return 0;
        return uint32(word >> ((day % 7) * 32));
    }

    function credit(uint32 id, uint24 day, uint256 amount, bool manual) external returns (uint256 total) {
        if (amount == 0) return 0;
        uint24 page = day / 7;
        uint256 index = page % 15;
        uint256 word = ring[id][index];
        bool spill;
        uint256 flagged;
        if (uint24(word >> 224) != page + 1) {
            uint256 marker = 0x80 | (page & 0x7f);
            uint256 existing;
            if (word >> 248 == marker) existing = overflow[id][page];
            if (uint24(existing >> 224) == page + 1) {
                word = existing;
                spill = true;
            } else {
                if (word != 0 && !_reusable(id, word)) {
                    spill = true;
                    flagged = (word & type(uint248).max) | (marker << 248);
                }
                word = uint256(page + 1) << 224;
            }
        }
        uint256 shift = (day % 7) * 32;
        uint256 previous = uint32(word >> shift);
        uint256 room = CAP - previous;
        if (manual && amount > room) revert StakeAboveDailyCap();
        total = previous + (amount > room ? room : amount);
        if (total != previous) {
            word = (word & ~(CAP << shift)) | (total << shift);
            if (spill) overflow[id][page] = word;
            else ring[id][index] = word;
            if (flagged != 0) ring[id][index] = flagged;
        }
    }

    function _reusable(uint32 id, uint256 word) private view returns (bool) {
        uint256 amounts = uint224(word);
        if (amounts == 0) return true;
        uint256 last = (uint256(uint24(word >> 224)) - 1) * 7;
        while (amounts >> 32 != 0) {
            amounts >>= 32;
            ++last;
        }
        uint256 resolved = frontier;
        if (resolved >= 90 && last <= resolved - 90) return true;
        return last <= claimed[id];
    }
}
