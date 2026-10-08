// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";

/// @dev Fixture board for sessions with no hero wagers or armed golden ticket. Integration
///      fixtures compare it with the real main board before using it for award expectations.
library BafBoardSeed {
    function context(uint24 lvl, uint256 word, uint256 rounds) internal pure returns (uint256 c) {
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        uint256 entropy = EntropyLib.hash2(word, lvl);
        uint8 solo = uint8(3 - (entropy & 3));
        uint8[4] memory golds;
        uint256 n;
        for (uint8 q; q < 4; ++q) if ((traits[q] >> 3) & 7 == 7) golds[n++] = q;
        if (n != 0) solo = golds[(entropy >> 4) % n];
        if (traits[3] == GoldSixLib.TRAIT) solo = 3;
        c = uint256(JackpotBucketLib.packWinningTraits(traits)) | (uint256(lvl) << 56)
            | (rounds << 96) | (uint256(solo) << 120) | (uint256(2) << 128);
    }

    function trait(uint256 round, uint256 rounds, uint256 c) internal pure returns (uint8) {
        uint256 q = (round % (rounds / 4)) % 3;
        if (q >= uint8(c >> 120)) ++q;
        return uint8(uint32(c) >> (q * 8));
    }
}
