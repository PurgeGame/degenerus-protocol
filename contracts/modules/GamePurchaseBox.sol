// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {RECORD_KIND_LUCKBOX} from "../interfaces/ICoinflip.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

abstract contract GamePurchaseBox is DegenerusGameStorage {
    /// @notice Emitted when a lootbox-boost boon is consumed by a buy.
    event BoostUsed(
        uint32 indexed player, uint24 indexed day, uint256 originalAmount, uint256 boostedAmount, uint16 boostBps
    );

    /// @dev Whole-point increment for codes above SCORE_CODE_EXACT.
    uint256 private constant SCORE_CODE_STEP = 14;

    /// @dev Last activity score a queued entry stores exactly; above it the code steps by
    ///      SCORE_CODE_STEP points, reaching ACTIVITY_EFFECTIVE_CAP_POINTS at code 4,039.
    uint256 private constant SCORE_CODE_EXACT = 2042;

    /// @dev Boon boost: capped uplift, expiring, consumed on use.
    uint32 private constant BOX_BOOST_EXPIRY_DAYS = 2;

    /// @dev Maximum spend receiving the boon uplift.
    uint256 private constant BOX_BOOST_MAX_VALUE = 10 ether;

    /// @dev Rake-free: all box ETH routes to the prize pools. Distress sends 100% next;
    ///      otherwise 90% future / 10% next.
    uint16 private constant BOX_SPLIT_NEXT_BPS = 1000;

    /// @dev Future-pool share outside distress.
    uint16 private constant BOX_SPLIT_FUTURE_BPS = 9000;

    /// @dev Floor for the biggest-box bounty.
    uint256 private constant BIGGEST_BOX_MIN_ETH = 5 ether;

    /// @dev Capped boon uplift on one purchase's spend.
    function _boostAmount(uint256 amount, uint16 bonusBps) internal pure returns (uint256) {
        uint256 capped = amount > BOX_BOOST_MAX_VALUE ? BOX_BOOST_MAX_VALUE : amount;
        unchecked {
            return (capped * bonusBps) / 10_000;
        }
    }

    /// @dev Consume the player's lootbox-boost boon, if live, and return the uplift in wei.
    ///      Deity-granted boosts are valid only on their grant day; others expire after
    ///      BOX_BOOST_EXPIRY_DAYS. Either way the boon is cleared here — it is one-shot.
    function _consumeBoxBoost(uint32 id, uint256 amount) internal returns (uint256 extra) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 day = _gameDay();
        uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
        if (deityDay != 0 && deityDay != day) {
            bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (stampDay != 0 && day > stampDay + BOX_BOOST_EXPIRY_DAYS) {
            bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }

        uint16 boostBps = _lootboxTierToBps(tier);
        extra = _boostAmount(amount, boostBps);
        bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
        emit BoostUsed(id, day, amount, amount + extra, boostBps);
    }

    /// @notice Build a purchase's ordinary entry: validate and price the order at the active
    ///         level, consume a live boost, snapshot distress, and arm the biggest-box bounty.
    ///         Nothing is queued here; the caller finalizes the score and appends the entry.
    /// @param buyerId The buyer's wallet ID.
    /// @param boxOrder Packed purchase input: [quantity:7][kind:2][customUnits:21].
    /// @return costWei Total wei the order costs.
    /// @return shares Prize-pool shares packed as (future << 128) | next.
    /// @return flipCredit Any biggest-box bounty claim, to join the buyer's flip credit.
    /// @return word The in-flight entry word, still missing its score.
    function _beginBoxOrder(uint32 buyerId, uint256 boxOrder)
        internal
        returns (uint256 costWei, uint256 shares, uint256 flipCredit, uint256 word)
    {
        (word, costWei) = _decodeBoxOrder(boxOrder, _activeTicketLevel());
        // The boost is capped at a quarter of the spend, so the fraction fits its lane.
        word |= uint256(buyerId) | ((_consumeBoxBoost(buyerId, costWei) * 10_000 / costWei) << LB_BOOST_SHIFT);
        bool distress = _isDistressMode();
        if (distress) word |= LB_DISTRESS;

        // Biggest-box bounty: a CUSTOM only, and its per-box size, never the order's total.
        // Presets are excluded outright — the bounty marks deliberately going big, and a large
        // at a milestone price would clear the floor on its own. With presets out and the
        // candidate a single box, no quantity of small buys can reach it.
        if ((boxOrder >> BO_KIND_SHIFT) & 3 == BO_KIND_CUSTOM) {
            uint256 candidate = (boxOrder >> BO_UNITS_SHIFT) * LB_VALUE_UNIT;
            if (candidate >= BIGGEST_BOX_MIN_ETH) {
                flipCredit = coinflip.armRecord(RECORD_KIND_LUCKBOX, buyerId, candidate);
            }
        }

        unchecked {
            shares = (((costWei * (distress ? 0 : BOX_SPLIT_FUTURE_BPS)) / 10_000) << 128)
                | ((costWei * (distress ? 10_000 : BOX_SPLIT_NEXT_BPS)) / 10_000);
        }
    }

    /// @notice Finalize a purchase's ordinary entry with its post-action activity score.
    /// @dev The frozen score determines the resolver's EV and is stored as its 12-bit code.
    /// @param word The in-flight entry from `_beginBoxOrder`.
    /// @param cachedScore Caller's post-action activity score in whole points.
    /// @return The completed ordinary fields.
    function _applyBoxOrderScore(uint256 word, uint256 cachedScore)
        internal pure
        returns (uint256)
    {
        return word | (_scoreCode(cachedScore) << LB_SCORE_SHIFT);
    }

    /// @dev 12-bit code of a queued entry's activity score: clamp to the curves' effective cap,
    ///      then floor-encode. Exact through SCORE_CODE_EXACT and at the cap; in between it
    ///      decodes at most 13 points low, where every curve is nearly flat.
    function _scoreCode(uint256 score) internal pure returns (uint256) {
        if (score > ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            score = ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS;
        }
        unchecked {
            return score <= SCORE_CODE_EXACT ? score : SCORE_CODE_EXACT + (score - SCORE_CODE_EXACT) / SCORE_CODE_STEP;
        }
    }

    /// @dev Whole-point activity score of a 12-bit code.
    function _scoreFromCode(uint256 code) internal pure returns (uint256) {
        unchecked {
            return code <= SCORE_CODE_EXACT ? code : SCORE_CODE_EXACT + (code - SCORE_CODE_EXACT) * SCORE_CODE_STEP;
        }
    }
}
