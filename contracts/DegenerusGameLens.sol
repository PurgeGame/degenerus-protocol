// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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

import {DegenerusGameMintStreakUtils} from "./modules/DegenerusGameMintStreakUtils.sol";
import {BitPackingLib} from "./libraries/BitPackingLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {ActivityCurveLib} from "./libraries/ActivityCurveLib.sol";

/// @dev Read surface the lens needs from the game: the raw-slot escape hatch plus
///      the authoritative aggregate score.
interface IDegenerusGameLensSource {
    /// @notice DegenerusGame's raw-slot reader, returning the word stored at `slot`.
    function extsload(bytes32 slot) external view returns (bytes32 value);

    /// @notice DegenerusGame's aggregate activity-score read for `player`.
    function playerActivityScore(address player) external view returns (uint256 scorePoints);
}

/// @title DegenerusGameLens
/// @notice Standalone read-only viewer over DegenerusGame's storage, reached through
///         the game's `extsload` raw-slot reader. Decodes the packed records that have
///         no per-field getters on the game (EIP-170 headroom lives here for free):
///         the full afking Sub record, the per-level affiliate DGNRS pool, decimator
///         bets with their subbucket aggregates, foil-pack
///         records, and a per-component activity-score breakdown.
///
///         Deployment-decoupled periphery: not referenced by ContractAddresses, takes
///         the game address per call (the DeityBoonViewer pattern), and can be
///         redeployed/extended after the game is frozen.
///
/// @dev INHERITANCE IS FOR LAYOUT ONLY. This contract inherits
///      DegenerusGameMintStreakUtils to share the game's exact storage layout
///      (`.slot` / `.offset` references resolve at compile time against the real
///      declarations) and its pure helpers/constants. Its OWN storage is never
///      written and never read: every state read goes through
///      `IDegenerusGameLensSource(game).extsload`. Inherited helpers that read
///      storage directly (e.g. _effectiveQuestStreak, _activeTicketLevel) must NOT
///      be called — they would read this contract's empty storage; the lens carries
///      explicit mirrors that source the same fields via extsload instead.
contract DegenerusGameLens is DegenerusGameMintStreakUtils {
    /// @notice Registered deity by owner-list index (genesis first, then paid, in order).
    function deityOwnerAt(address game, uint256 index) external view returns (address owner) {
        uint256 base;
        assembly { base := deityPassOwners.slot }
        if (index >= _sload(game, bytes32(base))) revert E();
        owner = address(uint160(_sload(game, bytes32(uint256(keccak256(abi.encode(base))) + index))));
    }

    /// @notice Paid deity sales, excluding genesis, used by the public price curve.
    function deityPassSalesCount(address game) external view returns (uint8) {
        uint256 base;
        uint256 offset;
        assembly { base := deityPassSales.slot offset := deityPassSales.offset }
        return uint8(_sload(game, bytes32(base)) >> (offset * 8));
    }

    /// @notice Exact paid ETH, scaled weight, entry count and award mask for a draw.
    function protocolBoonPool(address game, address issuer, uint24 day)
        public view returns (ProtocolBoonPool memory pool)
    {
        uint256 base;
        assembly { base := protocolBoonPools.slot }
        uint256 word = _sload(game, _mapSlot(uint256(day), uint256(_mapSlot(issuer, base))));
        pool.totalWageredWei = uint112(word);
        pool.totalWeight = uint64(word >> 112);
        pool.entryCount = uint32(word >> 176);
        pool.awardedMask = uint8(word >> 208);
    }

    /// @notice Immutable player, cumulative weight and activity score snapshot.
    /// @dev An absent index returns zero fields, matching a mapping read.
    function protocolBoonEntryAt(address game, address issuer, uint24 day, uint32 index)
        public view returns (ProtocolBoonEntry memory entry)
    {
        uint256 base;
        assembly { base := protocolBoonEntries.slot }
        bytes32 daySlot = _mapSlot(uint256(day), uint256(_mapSlot(issuer, base)));
        uint256 word = _sload(game, _mapSlot(uint256(index), uint256(daySlot)));
        entry.player = address(uint160(word));
        entry.cumulativeWeight = uint64(word >> 160);
        entry.scoreSnapshot = uint16(word >> 224);
    }

    /// @notice Preview paid ETH weight using the player's canonical pre-bet activity score.
    /// @dev Uses the hero ledger's 0.0001-ETH units; the common multiplier scale is 800.
    ///      This quotes a valid stake, not eligibility or remaining pool capacity.
    function protocolBoonQuote(address game, address player, uint256 amount)
        external view returns (uint256 wagerUnits, uint16 score, uint16 multiplierUnits, uint64 weight)
    {
        if (amount < 0.005 ether) revert E();
        wagerUnits = amount / 1e14;
        uint256 rawScore = IDegenerusGameLensSource(game).playerActivityScore(player);
        if (rawScore > type(uint16).max) revert E();
        score = uint16(rawScore);
        multiplierUnits = uint16(ActivityCurveLib.boonDrawMultUnits(rawScore));
        // Bound units before multiplication so even an arbitrary uint256 quote cannot wrap.
        if (wagerUnits > type(uint64).max / uint256(multiplierUnits)) revert E();
        weight = uint64(wagerUnits * multiplierUnits);
    }

    /// @notice Locate all three winning intervals without an on-chain participant sweep.
    /// @dev Historical outcomes stay inspectable after automatic next-day issuance.
    function findProtocolBoonWinners(address game, address issuer, uint24 day)
        external view returns (bool ready, address[3] memory winners, uint32[3] memory indices, uint64[3] memory rolls)
    {
        if (day == 0 || day == type(uint24).max) return (false, winners, indices, rolls);
        ProtocolBoonPool memory pool = protocolBoonPool(game, issuer, day);
        uint256 word = _rngWordByDayOf(game, day + 1);
        if (pool.totalWeight == 0 || word == 0) {
            return (false, winners, indices, rolls);
        }
        for (uint8 slot; slot < 3; ++slot) {
            uint64 roll = uint64(uint256(keccak256(abi.encode(
                PROTOCOL_BOON_WINNER_TAG, issuer, day, slot, word
            ))) % pool.totalWeight);
            uint32 lo;
            uint32 hi = pool.entryCount;
            while (lo < hi) {
                uint32 mid = lo + (hi - lo) / 2;
                if (protocolBoonEntryAt(game, issuer, day, mid).cumulativeWeight <= roll) lo = mid + 1;
                else hi = mid;
            }
            indices[slot] = lo;
            rolls[slot] = roll;
            winners[slot] = protocolBoonEntryAt(game, issuer, day, lo).player;
        }
        ready = true;
    }


    /*+======================================================================+
      |                          RETURN STRUCTS                              |
      +======================================================================+*/

    /// @notice The full afking Sub record (one game-storage slot) plus the unified
    ///         effective quest streak the activity score reads.
    struct SubFull {
        bool active; // dailyQuantity != 0 (same predicate as DegenerusGame.subInfo)
        uint8 dailyQuantity;
        uint8 flags; // bit 1 = drainGameCreditFirst; bit 2 = useTickets
        uint16 score; // frozen activity score stamp (box EV input)
        uint24 amountMilliEth; // frozen spend stamp, milli-ETH
        uint24 lastAutoBoughtDay;
        uint24 lastOpenedDay;
        uint24 afkCoveredThroughDay;
        uint24 afkingStartDay;
        uint32 affiliateBase; // unclaimed whole-FLIP affiliate accumulator
        uint24 pendingFlip; // claimable whole-FLIP accumulator
        uint16 subStreakLatch; // streakAtAfkingStart (run base)
        uint32 effectiveStreak; // unified streak: live afking compute-on-read, else manual
    }

    /// @notice Per-component activity score attribution. `total` is the game's own
    ///         playerActivityScore (authoritative); the components are the terms the
    ///         game sums before the curse floor and hard cap.
    struct ActivityBreakdown {
        uint256 total; // authoritative aggregate from the game
        uint32 questStreak; // unified effective quest streak input
        uint256 questStreakPoints; // questStreak / 2
        bool deityPass;
        uint256 mintStreakPoints; // deity: 50 flat; else capped streak, pass-floored
        uint256 mintCountPoints; // deity: 25 flat; else participation, pass-floored
        uint256 affiliatePoints;
        uint256 passBonusPoints; // 80 deity / 40 whale / 10 lazy / 0
        uint256 cursePoints; // subtracted, floored at 0, before the hard cap
    }

    /// @notice A player's decimator entry for a level (decBurn[lvl][player]).
    struct DecBurnEntry {
        uint192 burn;
        uint8 bucket; // 0 = no entry this level
        uint8 subBucket;
        bool claimed;
    }

    /// @notice A player's foil-pack record for a cycle level (foilRecord[lvl][player]).
    struct FoilRecordEntry {
        bool present;
        uint24 resolveDay; // seed day + no-look-back floor
        uint16 multBps; // frozen foilBoostBps (20000..60000)
        uint16 activityScore; // frozen at buy (claim-spin RTP input)
    }

    /*+======================================================================+
      |                        RAW-SLOT PLUMBING                             |
      +======================================================================+*/

    /// @dev One extsload read, as uint256.
    function _sload(address game, bytes32 slot) private view returns (uint256) {
        return uint256(IDegenerusGameLensSource(game).extsload(slot));
    }

    /// @dev Value slot of mapping(addressKey => v) at base `base`.
    function _mapSlot(address key, uint256 base) private pure returns (bytes32) {
        return keccak256(abi.encode(key, base));
    }

    /// @dev Value slot of mapping(uintKey => v) at base `base`.
    function _mapSlot(uint256 key, uint256 base) private pure returns (bytes32) {
        return keccak256(abi.encode(key, base));
    }

    /*+======================================================================+
      |                        AFKING SUB RECORD                             |
      +======================================================================+*/

    /// @notice The full Sub record for `player` — every field of the packed slot
    ///         DegenerusGame.subInfo exposes four of — plus the unified effective
    ///         quest streak (the same value _effectiveQuestStreak feeds the score).
    function subInfoFull(address game, address player) external view returns (SubFull memory s) {
        uint256 base;
        assembly {
            base := _subOf.slot
        }
        uint256 w = _sload(game, _mapSlot(player, base));
        s.dailyQuantity = uint8(w);
        s.active = s.dailyQuantity != 0;
        s.flags = uint8(w >> 8);
        s.score = uint16(w >> 16);
        s.amountMilliEth = uint24(w >> 32);
        s.lastAutoBoughtDay = uint24(w >> 56);
        s.lastOpenedDay = uint24(w >> 80);
        s.afkCoveredThroughDay = uint24(w >> 104);
        s.afkingStartDay = uint24(w >> 128);
        s.affiliateBase = uint32(w >> 152);
        s.pendingFlip = uint24(w >> 184);
        s.subStreakLatch = uint16(w >> 208);
        s.effectiveStreak = _effectiveQuestStreakMirror(game, player, w);
    }

    /// @dev Mirror of DegenerusGameStorage._effectiveQuestStreak, sourcing the Sub
    ///      slot via extsload (`subWord`) instead of local storage: a live afking sub
    ///      reads the Sub-side compute-on-read, everyone else the manual streak.
    function _effectiveQuestStreakMirror(
        address game,
        address player,
        uint256 subWord
    ) private view returns (uint32) {
        (uint32 manualStreak, bool afking) = quests.effectiveBaseStreakAndAfking(player);
        if (!afking) return manualStreak;
        if (uint24(subWord >> 128) != 0) {
            uint32 a = _afkingStreakMirror(game, subWord);
            if (a != 0) return a;
        }
        return manualStreak;
    }

    /// @dev Mirror of DegenerusGameStorage._afkingStreak over an extsload-sourced Sub
    ///      word: run base + funded delivered days, decayed to 0 once a playable full
    ///      day passed without a funded delivery (days inside a pending unadvanced
    ///      gap — the next day's word unsealed — do not decay).
    function _afkingStreakMirror(address game, uint256 subWord) private view returns (uint32) {
        uint24 covered = uint24(subWord >> 104); // afkCoveredThroughDay
        uint24 currentDay = GameTimeLib.currentDayIndex();
        if (currentDay == 0) return 0;
        if (uint32(covered) + 1 < uint32(currentDay)) {
            uint24 sealedDay = _dailyIdx(game);
            if (
                uint32(currentDay) <= uint32(sealedDay) + 1 ||
                covered < sealedDay ||
                _rngWordByDayOf(game, uint24(sealedDay + 1)) != 0
            ) return 0;
        }
        return uint32(uint16(subWord >> 208)) + uint32(covered - uint24(subWord >> 128));
    }

    /// @dev rngWordByDay[day] via extsload (read-only periphery mirror of the sealed
    ///      daily word — consumed here only as the afking decay gate's presence test,
    ///      exactly the predicate _afkingStreak applies).
    function _rngWordByDayOf(address game, uint24 day) private view returns (uint256) {
        uint256 base;
        assembly {
            base := rngWordByDay.slot
        }
        return _sload(game, _mapSlot(uint256(day), base));
    }

    /*+======================================================================+
      |                     SLOT-0 SCALARS (day / level / phase)             |
      +======================================================================+*/

    /// @dev dailyIdx from the game's packed slot 0.
    function _dailyIdx(address game) private view returns (uint24) {
        uint256 slot;
        uint256 off;
        assembly {
            slot := dailyIdx.slot
            off := dailyIdx.offset
        }
        return uint24(_sload(game, bytes32(slot)) >> (off << 3));
    }

    /// @dev The game's slot-0 word (level + phase flags share it with dailyIdx).
    function _levelWord(address game) private view returns (uint256 w) {
        uint256 slot;
        assembly {
            slot := level.slot
        }
        return _sload(game, bytes32(slot));
    }

    /// @dev Mirror of DegenerusGameMintStreakUtils._activeTicketLevel over the
    ///      extsload-sourced slot-0 word: jackpot phase routes buys to the current
    ///      level; the purchase phase, a transition in progress, or the sealed final
    ///      jackpot request route to level + 1.
    function _activeTicketLevelMirror(uint256 w) private pure returns (uint24) {
        uint24 lvl;
        bool jackpotPhase;
        bool phaseTransition;
        bool rngLocked;
        uint8 cnt;
        uint8 flags;
        {
            uint256 o;
            assembly {
                o := level.offset
            }
            lvl = uint24(w >> (o << 3));
            assembly {
                o := jackpotPhaseFlag.offset
            }
            jackpotPhase = uint8(w >> (o << 3)) != 0;
            assembly {
                o := phaseTransitionActive.offset
            }
            phaseTransition = uint8(w >> (o << 3)) != 0;
            assembly {
                o := rngLockedFlag.offset
            }
            rngLocked = uint8(w >> (o << 3)) != 0;
            assembly {
                o := jackpotCounter.offset
            }
            cnt = uint8(w >> (o << 3));
            assembly {
                o := jackpotFlags.offset
            }
            flags = uint8(w >> (o << 3));
        }
        if (!jackpotPhase) return lvl + 1;
        if (phaseTransition) return lvl + 1;
        if (rngLocked && _isFinalJackpotDay(cnt, flags)) return lvl + 1;
        return lvl;
    }

    /// @notice The level a ticket bought right now routes to — the same routing
    ///         _activeTicketLevel applies (jackpot phase → current level; purchase
    ///         phase / transition / sealed final request → next).
    function activeTicketLevelOf(address game) external view returns (uint24) {
        return _activeTicketLevelMirror(_levelWord(game));
    }

    /*+======================================================================+
      |                     ACTIVITY SCORE BREAKDOWN                         |
      +======================================================================+*/

    /// @notice Per-component attribution of the game's activity score, so a UI never
    ///         re-implements the scoring formula. `total` comes from the game's own
    ///         playerActivityScore; the components mirror _playerActivityScoreAt term
    ///         by term over the same inputs (mintPacked_ word, unified quest streak,
    ///         affiliate cache) — total == clamp(sum of components - curse).
    function activityScoreBreakdown(
        address game,
        address player
    ) external view returns (ActivityBreakdown memory b) {
        b.total = IDegenerusGameLensSource(game).playerActivityScore(player);
        if (player == address(0)) return b;

        uint256 packedBase;
        uint256 subBase;
        assembly {
            packedBase := mintPacked_.slot
            subBase := _subOf.slot
        }
        uint256 packed = _sload(game, _mapSlot(player, packedBase));
        uint256 subWord = _sload(game, _mapSlot(player, subBase));
        uint256 w = _levelWord(game);
        uint24 currLevel;
        {
            uint256 o;
            assembly {
                o := level.offset
            }
            currLevel = uint24(w >> (o << 3));
        }

        b.questStreak = _effectiveQuestStreakMirror(game, player, subWord);
        b.questStreakPoints = uint256(b.questStreak) / 2;

        b.deityPass = packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        uint24 frozenUntilLevel = uint24(
            (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint8 passType = uint8((packed >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3);

        if (b.deityPass) {
            b.mintStreakPoints = 50;
            b.mintCountPoints = 25;
            b.passBonusPoints = DEITY_PASS_ACTIVITY_BONUS_POINTS;
        } else {
            uint24 streak = _mintStreakEffectiveFromPacked(packed, _activeTicketLevelMirror(w));
            uint256 streakPoints = streak > 50 ? 50 : uint256(streak);
            uint256 mintCountPoints = _mintCountBonusPoints(
                uint24((packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24),
                currLevel
            );
            bool passActive = frozenUntilLevel >= currLevel && (passType == 1 || passType == 3);
            if (passActive) {
                if (streakPoints < PASS_STREAK_FLOOR_POINTS) streakPoints = PASS_STREAK_FLOOR_POINTS;
                if (mintCountPoints < PASS_MINT_COUNT_FLOOR_POINTS) {
                    mintCountPoints = PASS_MINT_COUNT_FLOOR_POINTS;
                }
            }
            b.mintStreakPoints = streakPoints;
            b.mintCountPoints = mintCountPoints;
            if (frozenUntilLevel >= currLevel) {
                if (passType == 1) b.passBonusPoints = 10;
                else if (passType == 3) b.passBonusPoints = 40;
            }
        }

        {
            uint256 cachedLevel = (packed >> BitPackingLib.AFFILIATE_BONUS_LEVEL_SHIFT) &
                BitPackingLib.MASK_24;
            if (cachedLevel == uint256(currLevel)) {
                b.affiliatePoints =
                    (packed >> BitPackingLib.AFFILIATE_BONUS_POINTS_SHIFT) &
                    BitPackingLib.MASK_6;
            } else {
                b.affiliatePoints = affiliate.affiliateBonusPointsBest(currLevel, player);
            }
        }

        b.cursePoints = (packed >> BitPackingLib.CURSE_COUNT_SHIFT) & BitPackingLib.MASK_8;
    }

    /*+======================================================================+
      |                    LEVEL DGNRS ALLOCATION                            |
      +======================================================================+*/

    /// @notice The level's per-affiliate DGNRS claim pool: the segregated allocation
    ///         and the amount already claimed against it (levelDgnrsPacked[lvl]).
    function levelDgnrsInfo(
        address game,
        uint24 lvl
    ) external view returns (uint128 allocation, uint128 claimed) {
        uint256 base;
        assembly {
            base := levelDgnrsPacked.slot
        }
        uint256 w = _sload(game, _mapSlot(uint256(lvl), base));
        allocation = uint128(w);
        claimed = uint128(w >> 128);
    }

    /*+======================================================================+
      |                          DECIMATOR                                   |
      +======================================================================+*/

    /// @notice A player's decimator entry for a level (decBurn[lvl][player]).
    function decBurnOf(
        address game,
        uint24 lvl,
        address player
    ) external view returns (DecBurnEntry memory e) {
        uint256 base;
        assembly {
            base := decBurn.slot
        }
        uint256 w = _sload(
            game,
            _mapSlot(player, uint256(_mapSlot(uint256(lvl), base)))
        );
        e.burn = uint192(w);
        e.bucket = uint8(w >> 192);
        e.subBucket = uint8(w >> 200);
        e.claimed = uint8(w >> 208) != 0;
    }

    /// @notice Aggregated decimator burn for a level/denominator/subbucket — the
    ///         pro-rata denominator a claim divides by (decBucketBurnTotal).
    function decBucketTotal(
        address game,
        uint24 lvl,
        uint8 denom,
        uint8 subBucket
    ) external view returns (uint256) {
        uint256 base;
        assembly {
            base := decBucketBurnTotal.slot
        }
        // mapping(uint24 => uint256[13][13]): [denom] strides 13 slots, [subBucket] one.
        uint256 arrBase = uint256(_mapSlot(uint256(lvl), base));
        return _sload(game, bytes32(arrBase + uint256(denom) * 13 + subBucket));
    }

    /// @notice Find the first matching owner index in a bounded page of a trait bucket.
    /// @dev View-only periphery: no Game write or hot-path cost. `ownerIndices` must
    ///      be sorted ascending. A result is a discovery hint; claimBingo checks
    ///      actual ownership itself. Limit both calldata and the cold-read budget.
    function findTraitEntry(
        address game, uint24 lvl, uint8 trait, uint32[] calldata ownerIndices,
        uint32 offset, uint16 maxWords
    ) external view returns (bool found, uint32 position, uint32 nextOffset, uint32 total) {
        require(ownerIndices.length > 0 && ownerIndices.length <= 1024, "indices");
        uint256 base;
        assembly { base := lvlTraitEntry.slot }
        bytes32 slot = bytes32(uint256(_mapSlot(uint256(lvl), base)) + trait);
        return _findPackedIndex(game, slot, ownerIndices, offset, maxWords);
    }

    /// @notice Find a registry position in a bounded page of a packed ticket queue.
    /// @dev Queue lanes store position+1; trait lanes store zero-based indices.
    function findQueueEntry(
        address game, uint24 key, uint32 ownerPosition, uint32 offset, uint16 maxWords
    ) external view returns (bool found, uint32 position, uint32 nextOffset, uint32 total) {
        uint256 base;
        assembly { base := ticketQueue.slot }
        uint32[] memory targets = new uint32[](1);
        targets[0] = ownerPosition;
        return _findPackedIndex(game, _mapSlot(uint256(key), base), targets, offset, maxWords);
    }

    function _findPackedIndex(
        address game, bytes32 slot, uint32[] memory targets, uint32 offset, uint16 maxWords
    ) private view returns (bool found, uint32 position, uint32 nextOffset, uint32 total) {
        require(maxWords > 0 && maxWords <= 2048, "page");
        total = uint32(_sload(game, slot));
        if (offset >= total) return (false, 0, total, total);
        uint256 end = ((uint256(offset) >> 3) + maxWords) << 3;
        if (end > total) end = total;
        uint256 data = uint256(keccak256(abi.encode(slot)));
        uint256 packed;
        for (uint256 i = offset; i < end; ++i) {
            if (i == offset || (i & 7) == 0) packed = _sload(game, bytes32(data + (i >> 3)));
            uint32 value = uint32(packed >> ((i & 7) * 32));
            uint256 lo;
            uint256 hi = targets.length;
            while (lo < hi) {
                uint256 mid = (lo + hi) >> 1;
                if (targets[mid] < value) lo = mid + 1;
                else hi = mid;
            }
            if (lo < targets.length && targets[lo] == value) return (true, uint32(i), uint32(i + 1), total);
        }
        return (false, 0, uint32(end), total);
    }

    /*+======================================================================+
      |                          FOIL PACKS                                  |
      +======================================================================+*/

    /// @notice A player's foil-pack record for a cycle level (foilRecord[lvl][player]):
    ///         presence, resolve day, frozen boost (bps) and frozen activity score.
    function foilRecordOf(
        address game,
        uint24 lvl,
        address player
    ) external view returns (FoilRecordEntry memory f) {
        uint256 base;
        assembly {
            base := foilRecord.slot
        }
        uint256 w = _sload(
            game,
            _mapSlot(player, uint256(_mapSlot(uint256(lvl), base)))
        );
        f.present = w != 0;
        f.resolveDay = uint24(w);
        f.multBps = uint16(w >> _FOIL_MULT_SHIFT);
        f.activityScore = uint16(w >> _FOIL_SCORE_SHIFT);
    }
}
