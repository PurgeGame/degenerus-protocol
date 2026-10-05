// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DecimatorSamplingLib as Sampling} from "./libraries/DecimatorSamplingLib.sol";


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
    function rngWordForDay(uint24 day) external view returns (uint256);
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
///         battle entries, sealed rounds and eligible winner heaps, foil-pack
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
    /// @dev Pools live in two-day rings (DegenerusGameStorage.protocolBoonPools), so a day's
    ///      pool stays readable until a later day of the same parity (normally two days on)
    ///      takes over its slot; a day whose slot now holds another day reads as empty.
    ///      The events (ProtocolBoonDrawEntered / ProtocolBoonDrawAwarded) keep the history.
    function protocolBoonPool(address game, address issuer, uint24 day)
        public view returns (ProtocolBoonPool memory pool)
    {
        uint256 base;
        assembly { base := protocolBoonPools.slot }
        uint256 word = _sload(game, _mapSlot(uint256(day & 1), uint256(_mapSlot(issuer, base))));
        if (uint24(word >> 216) != day) return pool;
        pool.totalWageredWei = uint112(word);
        pool.totalWeight = uint64(word >> 112);
        pool.entryCount = uint32(word >> 176);
        pool.awardedMask = uint8(word >> 208);
        pool.day = day;
    }

    /// @notice Player, cumulative weight and activity score snapshot of a held pool's entry
    ///         (entries are overwritten once a later day takes over the ring slot).
    /// @dev An index outside the day's held pool returns zero fields, matching a mapping read.
    function protocolBoonEntryAt(address game, address issuer, uint24 day, uint32 index)
        public view returns (ProtocolBoonEntry memory entry)
    {
        if (index >= protocolBoonPool(game, issuer, day).entryCount) return entry;
        uint256 base;
        assembly { base := protocolBoonEntries.slot }
        bytes32 daySlot = _mapSlot(uint256(day & 1), uint256(_mapSlot(issuer, base)));
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
    /// @dev Inspectable while the day's pool is held (the wager day and the day after, which is
    ///      when it is drawn) until a later same-parity day takes over the slot; after that the
    ///      day reads not-ready, and its entries and awards remain in the events.
    function findProtocolBoonWinners(address game, address issuer, uint24 day)
        external view returns (bool ready, address[3] memory winners, uint32[3] memory indices, uint64[3] memory rolls)
    {
        if (day == 0 || day == type(uint24).max) return (false, winners, indices, rolls);
        ProtocolBoonPool memory pool = protocolBoonPool(game, issuer, day);
        uint256 word = IDegenerusGameLensSource(game).rngWordForDay(day + 1);
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

    /// @notice A wallet's accumulated entry for one event; `stack` in wei of virtual chips.
    struct DecBurnEntry {
        uint64 entryId;
        address owner;
        uint256 stack;
        uint32 chips; // the chosen board, in the normal battles' thirty-bit encoding
    }

    /// @notice A retained heads result: score, full ordering key (192-bit random tiebreak
    ///         above the 64-bit entry id), and the owner of this original or generated entry.
    struct DecWinner {
        uint256 score;
        uint256 key;
        address owner;
    }

    /// @notice A player's retained foil-pack record for a cycle level.
    struct FoilRecordEntry {
        bool present;
        uint24 resolveDay; // first eligible draw; zero while pending
        uint16 multBps; // frozen foilBoostBps (20000..60000)
        uint16 activityScore; // frozen at buy (claim-spin RTP input)
        bool resolved;
        uint24 generatedDay;
        uint32[4] lines;
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

    /// @dev _recordedDailyWord(day) via extsload (read-only periphery mirror of the sealed
    ///      daily word — consumed here only as the afking decay gate's presence test,
    ///      exactly the predicate _afkingStreak applies).
    function _rngWordByDayOf(address game, uint24 day) private view returns (uint256) {
        uint256 root;
        uint256 tagsSlot;
        assembly { root := rngWordByDay.slot tagsSlot := rngDayTags.slot }
        uint256 tags = _sload(game, bytes32(tagsSlot));
        if (day == 0 || uint24(tags >> ((day & 1) * 24)) != day) return 0;
        return _sload(game, _mapSlot(uint256(day & 1), root));
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

    /// @dev The wallet slot names only its latest event; an earlier one reads by id (decEntryAt).
    function decBurnOf(address game, uint24 lvl, address player)
        external view returns (DecBurnEntry memory e)
    {
        uint256 root;
        assembly { root := decBattlePlayers.slot }
        uint256 latest = _sload(game, _mapSlot(player, root));
        if (uint24(latest >> 64) != lvl) return e;
        e.entryId = uint64(latest);
        (e.owner, e.stack, e.chips) = decEntryAt(game, lvl, e.entryId);
    }

    function decEntryAt(address game, uint24 lvl, uint64 id)
        public view returns (address owner, uint256 stack, uint32 chips)
    {
        uint256 root;
        assembly { root := decBattleEntries.slot }
        uint256 entry = _sload(game, _mapSlot((uint256(lvl) << 64) | id, root));
        return (address(uint160(entry)), (entry >> 190), uint32((entry >> 160) & 0x3FFFFFFF));
    }

    function decBattleRoundOf(address game, uint24 lvl)
        public view returns (DecBattleRound memory r)
    {
        uint256 root;
        assembly { root := decBattleRounds.slot }
        uint256 slot = uint256(_mapSlot(uint256(lvl), root));
        uint256 word = _sload(game, bytes32(slot));
        r.poolWei = uint96(word);
        r.count = uint40(word >> 96);
        r.totalCreditedStack = uint64(word >> 136);
        r.openedDay = uint24(word >> 200);
        r.phase = uint8(word >> 224);
        r.capacity = uint8(word >> 232);
        r.winners = uint8(word >> 240);
        r.paid = uint8(word >> 248);
        word = _sload(game, bytes32(slot + 1));
        r.cursor = uint64(word);
        r.champion = uint64(word >> 64);
        r.next = uint24(word >> 128);
    }

    /// @notice Last sealed original average as an exact fraction, plus the next automatic cap.
    function decBurnReferenceOf(address game)
        external view returns (uint64 stack, uint40 count, uint256 automaticCap)
    {
        bytes32 slot;
        assembly { slot := decPreviousStack.slot }
        uint256 word = _sload(game, slot);
        stack = uint64(word);
        count = uint40(word >> 64);
        automaticCap = count == 0 ? 8000 : uint256(stack) * 4 / count;
    }

    /// @notice A retained eligible run. Heap order is NOT merit rank; champion is in the round.
    /// @dev Absolute peak in whole FLIP is score / (3000 * 1e18), where 1e18 is engine precision.
    ///      One leaderboard is reused round after round, so it is readable only while `lvl` is at
    ///      the head of the settlement queue; finished rounds are in their DecimatorRanked and
    ///      DecimatorClaimed events.
    function decWinnerAt(address game, uint24 lvl, uint8 index)
        public view returns (DecWinner memory node)
    {
        DecBattleRound memory r = decBattleRoundOf(game, lvl);
        bytes32 queueSlot;
        uint256 root;
        assembly {
            queueSlot := decBattleQueue.slot
            root := decBattleHeap.slot
        }
        if (index >= r.winners || uint24(_sload(game, queueSlot)) != lvl
            || (r.phase != 1 && r.phase != 2)) revert E();
        uint256 rngWord = _decActiveWordOf(game);
        if (rngWord == 0) revert E();
        uint256 stored = _sload(game, _mapSlot(uint256(index), root));
        uint64 id = uint64(stored);
        bytes32 tag = keccak256("decimator.battle.tie.v1");
        node.score = stored >> 64;
        node.key = (uint256(keccak256(abi.encode(tag, rngWord, lvl, id)))
            & ~uint256(type(uint64).max)) | id;
        if (id > r.count) {
            assembly { root := decGeneratedOwners.slot }
            node.owner = address(uint160(_sload(game, _mapSlot(uint256(id - r.count), root))));
        } else {
            (node.owner,,) = decEntryAt(game, lvl, id);
        }
    }

    function decJackpotPlanOf(address game, uint24 lvl) public view returns (DecJackpotPlan memory p) {
        uint256 root;
        assembly { root := decJackpotPlans.slot }
        uint256 slot = uint256(_mapSlot(uint256(lvl), root));
        uint256 w = _sload(game, bytes32(slot));
        p.soloAmount = uint128(w);
        p.weights = uint64(w >> 128);
        p.generatedEntries = uint40(w >> 192);
        p.cursor = uint16(w >> 232);
        p.mode = uint8(w >> 248);
    }

    /// @notice Replay a survivor from its sealed word, level, final field size and stratum.
    function decSurvivorAt(uint256 word, uint24 lvl, uint64 fieldEntries, uint16 stratum)
        external pure returns (uint64)
    {
        uint256 count = Sampling.survivors(fieldEntries);
        if (stratum >= count) revert E();
        return Sampling.sample(word, lvl, fieldEntries, count,
            Sampling.rotation(word, lvl, fieldEntries), stratum);
    }

    /// @dev The pending battle owns this published session until its final payout.
    function _decActiveWordOf(address game) private view returns (uint256 word) {
        bytes32 flagsSlot;
        bytes32 wordSlot;
        uint256 offset;
        assembly {
            flagsSlot := rngFlagsAndNudges.slot
            offset := rngFlagsAndNudges.offset
            wordSlot := rngWordCurrent.slot
        }
        uint256 flags = _sload(game, flagsSlot) >> (offset * 8);
        if (flags & (uint256(1) << 15) == 0 || flags & (uint256(1) << 13) != 0) return 0;
        word = _sload(game, wordSlot);
        if (word == RNG_WORD_WAITING) return 0;
    }

    function decSettleCursorOf(address game)
        external view returns (uint24 head, uint24 tail)
    {
        bytes32 slot;
        assembly { slot := decBattleQueue.slot }
        uint256 word = _sload(game, slot);
        return (uint24(word), uint24(word >> 24));
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
        bytes32 stampSlot;
        uint256 stampOffset;
        assembly {
            stampSlot := ticketBufferLevels.slot
            stampOffset := ticketBufferLevels.offset
        }
        uint24 occupyingLevel = uint24(_sload(game, stampSlot) >> (stampOffset * 8 + (lvl & 1) * 24));
        if (occupyingLevel != lvl) return (false, 0, 0, 0);
        uint256 bitmapBase;
        assembly { bitmapBase := traitBucketLive.slot }
        if (_sload(game, bytes32(bitmapBase + (lvl & 1))) & (uint256(1) << trait) == 0) return (false, 0, 0, 0);
        uint256 base;
        assembly { base := lvlTraitEntry.slot }
        bytes32 slot = bytes32(uint256(_mapSlot(uint256(lvl & 1), base)) + trait);
        return _findPackedIndex(game, slot, ownerIndices, offset, maxWords, true);
    }

    /// @notice Permanent wallet ID, or zero before its first registration.
    function walletIdOf(address game, address player) external view returns (uint32) {
        uint256 base;
        assembly { base := ticketOwnerId.slot }
        return uint32(_sload(game, _mapSlot(player, base)));
    }

    /// @notice Wallet owning an ID; zero for an unallocated or zero ID.
    function walletOfId(address game, uint32 id) external view returns (address) {
        if (id == 0) return address(0);
        uint256 base;
        assembly { base := ticketOwners.slot }
        if (id > uint256(_sload(game, bytes32(base)))) return address(0);
        return address(uint160(uint256(_sload(game, bytes32(uint256(keccak256(abi.encode(base))) + id - 1)))));
    }

    /// @notice Find a registry position in a bounded page of a packed ticket queue.
    /// @dev Queue lanes store position+1; trait lanes store zero-based indices.
    function findQueueEntry(
        address game, uint24 key, uint32 ownerPosition, uint32 offset, uint16 maxWords
    ) external view returns (bool found, uint32 position, uint32 nextOffset, uint32 total) {
        uint256 base;
        uint24 physical = _ticketQueueStorageKey(key);
        assembly { base := ticketQueueLevels.slot }
        uint24 occupying = uint24(_sload(game, _mapSlot(uint256(physical), base)));
        if (occupying == 0) occupying = physical & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT);
        if (occupying != key & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT)) return (false, 0, 0, 0);
        assembly { base := ticketQueue.slot }
        uint32[] memory targets = new uint32[](1);
        targets[0] = ownerPosition;
        return _findPackedIndex(game, _mapSlot(uint256(physical), base), targets, offset, maxWords, false);
    }

    function _findPackedIndex(
        address game, bytes32 slot, uint32[] memory targets, uint32 offset, uint16 maxWords, bool headerTail
    ) private view returns (bool found, uint32 position, uint32 nextOffset, uint32 total) {
        require(maxWords > 0 && maxWords <= 2048, "page");
        uint256 header = _sload(game, slot);
        total = uint32(header);
        if (offset >= total) return (false, 0, total, total);
        uint256 end = ((uint256(offset) >> 3) + maxWords) << 3;
        if (end > total) end = total;
        uint256 data = uint256(keccak256(abi.encode(slot)));
        uint256 packed;
        for (uint256 i = offset; i < end; ++i) {
            if (i == offset || (i & 7) == 0) {
                packed = headerTail && (i >> 3) == (uint256(total) >> 3)
                    ? header >> 32 : _sload(game, bytes32(data + (i >> 3)));
            }
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

    /// @notice A player's retained foil-pack record for a cycle level:
    ///         presence, resolve day, frozen boost (bps) and frozen activity score.
    /// @dev Records use four reusable slots per player; an overwritten level returns
    ///      an absent, zeroed entry. This view does not provide permanent history.
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
            _mapSlot(player, uint256(_mapSlot(uint256(lvl & 3), base)))
        );
        if (w == 0 || uint24(w >> _FOIL_LEVEL_SHIFT) != lvl) return f;
        f.present = true;
        f.resolveDay = uint24(w);
        f.multBps = uint16(w >> _FOIL_MULT_SHIFT);
        f.activityScore = uint16(w >> _FOIL_SCORE_SHIFT);
        f.resolved = w & _FOIL_READY != 0;
        f.generatedDay = uint24(w >> _FOIL_GENERATED_DAY_SHIFT);
        for (uint256 i; i < 4; ++i) f.lines[i] = uint32(w >> (_FOIL_LINES_SHIFT + i * 32));
    }
}
