// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "./EntropyLib.sol";
import {RngTags} from "./RngTags.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/**
 * @title FlipRoundLib
 * @notice Rounds whole-FLIP awards to hundreds with a committed random word, and maps a
 *         word to a coinflip day's reward percentage.
 * @dev A remainder of r tokens rounds up with probability r/100. Callers bind entropy
 *      to immutable per-award data and round individual awards, never caller-chosen batches.
 */
library FlipRoundLib {
    uint256 internal constant FLIP_ROUND_UNIT = 100;
    uint256 internal constant FLIP_ROUND_THRESHOLD = 1_000;

    uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;
    uint16 private constant COINFLIP_EXTRA_RANGE = 38;

    /// @dev Reward percentage paid on a winning flip: principal + principal * percent / 100.
    ///      ~5% each for 50 or 150, otherwise [78, 115], plus `bonus`. The tagged seed keeps
    ///      the size independent of the word's other draws. Coinflip days and the sDGNRS
    ///      redemption flip share this mapping; the draw depends only on `rngWord`.
    function coinflipRewardPercent(uint8 bonus, uint256 rngWord)
        internal pure returns (uint16 rewardPercent)
    {
        uint256 seedWord = uint256(EntropyLib.hash2(RngTags.FLIP_REWARD, rngWord));
        uint256 roll = seedWord % 20;
        if (roll == 0) {
            rewardPercent = 50;
        } else if (roll == 1) {
            rewardPercent = 150;
        } else {
            rewardPercent = uint16((seedWord % COINFLIP_EXTRA_RANGE) + COINFLIP_EXTRA_MIN_PERCENT);
        }
        // Max 150 + 6, so the add cannot overflow.
        unchecked {
            rewardPercent += bonus;
        }
    }

    /// @dev `uint32(entropy) % 100` carries a negligible modulo bias.
    function roundFlipToHundreds(uint256 amount, uint256 entropy) internal pure returns (uint256) {
        uint256 hundreds = amount / FLIP_ROUND_UNIT;
        uint256 remFlip = amount % FLIP_ROUND_UNIT;
        if (remFlip != 0 && uint32(entropy) % 100 < remFlip) {
            unchecked { ++hundreds; }
        }
        return hundreds * FLIP_ROUND_UNIT;
    }
}
