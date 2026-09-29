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

import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

/**
 * @title DegenerusGameDecimatorModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling decimator jackpot tracking, resolution, and settlement.
 * @dev This module is called via delegatecall from DegenerusGame, meaning all
 *      storage reads/writes operate on the game contract's storage.
 */
contract DegenerusGameDecimatorModule is DegenerusGamePayoutUtils {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a player's Decimator burn is recorded.
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param bucket The denominator bucket used (2-12).
    /// @param subBucket The deterministic subbucket assigned (0 to bucket-1).
    /// @param position The entry's position in the (lvl, bucket, subBucket) list.
    /// @param effectiveAmount Burn weight after the multiplier. The multiplier applies to
    ///        the first DECIMATOR_MULTIPLIER_CAP of BASE burned at this level; the weight
    ///        it produces is itself uncapped.
    /// @param newTotalBurn Player's new total burn for this level.
    event DecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint8 bucket,
        uint8 subBucket,
        uint32 position,
        uint256 effectiveAmount,
        uint256 newTotalBurn
    );

    /// @notice Emitted when a rising activity score migrates a player's prior burn
    ///         to a strictly better (lower-denominator) bucket — the carried burn
    ///         moves between subbucket aggregates, so event-derived pro-rata
    ///         denominators stay exact (DecBurnRecorded carries only the fresh
    ///         delta against the NEW bucket).
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param fromBucket Prior denominator bucket the burn leaves.
    /// @param fromSubBucket Prior subbucket the burn leaves.
    /// @param toBucket New denominator bucket the burn enters.
    /// @param toSubBucket New subbucket the burn enters.
    /// @param toPosition The entry's position in the new subbucket's list; the old position is
    ///        left empty.
    /// @param movedBurn The carried-over burn.
    event DecBurnMigrated(
        address indexed player,
        uint24 indexed lvl,
        uint8 fromBucket,
        uint8 fromSubBucket,
        uint8 toBucket,
        uint8 toSubBucket,
        uint32 toPosition,
        uint192 movedBurn
    );

    /// @dev Emitted when decimator winning subbuckets are resolved for a level.
    ///      packedOffsets encodes the winning subbucket for each denom 2-12
    ///      (same packing as decBucketOffsetPacked).
    event DecimatorResolved(
        uint24 indexed lvl,
        uint64 packedOffsets,
        uint256 poolWei,
        uint256 totalBurn
    );

    /// @notice Emitted when mineFlip's walk settles a winning decimator entry.
    /// @param player The entry's owner, credited with the payout.
    /// @param lvl Decimator level the entry won.
    /// @param amountWei Total pro-rata payout in wei.
    /// @param ethPortion Portion credited as ETH claimable.
    /// @param lootboxPortion Portion routed to whale passes / lootbox.
    event DecimatorClaimed(
        address indexed player,
        uint24 indexed lvl,
        uint256 amountWei,
        uint256 ethPortion,
        uint256 lootboxPortion
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    /// @notice Caller is not the authorized coin contract.
    error OnlyCoin();

    /// @notice Caller is not the authorized game contract.
    error OnlyGame();

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Bubbles up revert reason from delegatecall failure.
    /// @param reason The revert data from the failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Basis points denominator (10000 = 100%).
    uint16 private constant BPS_DENOMINATOR = 10_000;

    bytes32 private constant DECIMATOR_BOX_TAG = keccak256("degenerus.decimator.box");

    /// @dev Multiplier cap for Decimator burns: the activity multiplier applies to a
    ///      player's first 500 mints' worth (500k FLIP) of BASE burn at a level; base
    ///      beyond it counts 1x. Measured on base, not on the multiplied weight.
    uint256 private constant DECIMATOR_MULTIPLIER_CAP = 500 * PRICE_COIN_UNIT;
    /// @dev Unit of DecEntry.weightMilli and DecEntry.baseMilli: a thousandth of a FLIP.
    uint256 private constant DEC_BASE_UNIT = 1e15;

    /// @dev Maximum denominator for Decimator buckets (2-12 inclusive).
    uint8 private constant DECIMATOR_MAX_DENOM = 12;

    /// @dev Weight multiplier (bps) for burns on the window-open day. Prices early
    ///      conviction against the information value of waiting for the window close.
    uint16 private constant DEC_DAY_ONE_BONUS_BPS = 12_000;

    /// @dev Weight debuff on decimator burns placed during a level's final purchase
    ///      day (prize target met): 0.9x, tempering last-look burns placed with the
    ///      level's outcome largely visible.
    uint16 private constant DEC_LAST_DAY_DEBUFF_BPS = 9_000;

    /// @dev Walk-unit price (1 unit ~= 4.7k gas) of a settle's own frame in mineFlip's decimator
    ///      leg: the entry read and delete, the claimable credit, the pool moves, the event and the
    ///      box delegatecall. The box is charged separately by its outcome (resolveLootboxDirect's
    ///      return), and deferred whole half-passes add DEC_WHALE_UNITS. Each is the in-batch
    ///      marginal cost for a fresh winner; DEC_CALL_UNITS covers what a call touches once.
    ///      Pinned by test/gas/DecimatorSettleWorstCaseGas.t.sol.
    uint256 private constant DEC_SETTLE_UNITS = 8;
    /// @dev Walk units charged once per call, on its first settle: the first touches a batch
    ///      shares (module code, the credited protocol contracts, the shared Game slots, the open
    ///      level's first append, tomorrow's first seat and the quest re-sync's bitmap words), so
    ///      the per-settle prices carry only what each settle adds inside a batch.
    uint256 private constant DEC_CALL_UNITS = 39;
    uint256 private constant DEC_WHALE_UNITS = 5;

    // -------------------------------------------------------------------------
    // External Entry Points (delegatecall targets)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Decimator Burn Tracking
    // -------------------------------------------------------------------------

    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @dev Called by coin contract on every Decimator burn.
    ///      A player's first burn in a window appends an entry to the list of their bucket
    ///      (denominator, derived from their activity score) and deterministic subbucket
    ///      hash(player, lvl, bucket), and points their pointer at it. Later burns add to that
    ///      entry unless a rising activity score qualifies a strictly better (lower denominator)
    ///      bucket: then the entry's weight leaves the old aggregate, the old position is emptied,
    ///      and the entry re-opens at the end of the new subbucket's list carrying its weight and
    ///      base. Weight and base are kept in thousandths of a FLIP, saturating.
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param bucket Activity-derived denominator (2-12); FLIP computes it from the player's activity score.
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Player bonus multiplier in basis points (10000 = 1x).
    /// @return bucketUsed The bucket actually used (unchanged unless the passed bucket is a strict improvement).
    /// @custom:access Restricted to coin contract.
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint8 bucket,
        uint256 baseAmount,
        uint256 multBps
    ) external returns (uint8 bucketUsed) {
        if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();

        DecPointer memory p = decPointer[player];
        DecEntry memory e;
        // Set when this burn appends an entry: the pointer is rewritten and the list grows.
        bool appended;
        // Weight a migration carries from the old aggregate into the new one, in wei.
        uint256 carriedWei;
        uint8 fromBucket;
        uint8 fromSubBucket;

        // `bucket` arrives coin-validated in [2,12] (FLIP derives it via
        // ActivityCurveLib.decBucket, floor >=2).
        if (p.lvl != lvl) {
            // First burn this window.
            p.lvl = lvl;
            p.bucket = bucket;
            p.subBucket = _decSubbucketFor(player, lvl, bucket);
            e.owner = player;
            appended = true;
        } else {
            uint256 heldKey = _decEntryKey(lvl, p.bucket, p.subBucket, p.position);
            e = decEntry[heldKey];
            if (bucket < p.bucket) {
                // Better bucket selected: move the entry to the new subbucket's list.
                carriedWei = uint256(e.weightMilli) * DEC_BASE_UNIT;
                _decRemoveSubbucket(lvl, p.bucket, p.subBucket, carriedWei);
                delete decEntry[heldKey];
                fromBucket = p.bucket;
                fromSubBucket = p.subBucket;
                p.bucket = bucket;
                p.subBucket = _decSubbucketFor(player, lvl, bucket);
                appended = true;
            }
        }

        bucketUsed = p.bucket;

        // Day-one bonus: burns while the window-open latch is armed carry 1.2x
        // weight. Rides multBps, which DECIMATOR_MULTIPLIER_CAP does NOT bound:
        // the cap limits the BASE that is multiplied, not the weight it produces,
        // so boosted weight reaches DECIMATOR_MULTIPLIER_CAP x multBps (2.14x the
        // cap at max activity on day one).
        if (decDayOneActive) {
            multBps = (multBps * DEC_DAY_ONE_BONUS_BPS) / BPS_DENOMINATOR;
        } else if (lastPurchaseDay) {
            // Final-purchase-day debuff: once the level's prize target is met, the
            // activity multiplier receives a 0.9x debuff, floored at 1.0x — a burn
            // placed with the level's outcome largely visible pays a haircut versus
            // early commitment, but never drops below base weight (a multBps at or
            // below 1.0x returns baseAmount in _decEffectiveAmount). Day-one burns
            // take the bonus branch instead: the window arms on the last purchase
            // day and its opening advance clears the flag only after the auto entry.
            multBps = (multBps * DEC_LAST_DAY_DEBUFF_BPS) / BPS_DENOMINATOR;
        }

        uint256 effectiveAmount = _decEffectiveAmount(
            uint256(e.baseMilli) * DEC_BASE_UNIT,
            baseAmount,
            multBps
        );
        // Track the base burned (floored to the unit, saturating) so the cap keeps
        // measuring base rather than weight across every later burn this level.
        uint256 baseUnits = uint256(e.baseMilli) + baseAmount / DEC_BASE_UNIT;
        if (baseUnits > type(uint32).max) baseUnits = type(uint32).max;
        e.baseMilli = uint32(baseUnits);

        // Accumulate weight with uint64 saturation; the aggregate takes exactly the
        // weight the entry gained, so a subbucket's total is the sum of its entries.
        uint256 weight = uint256(e.weightMilli) + effectiveAmount / DEC_BASE_UNIT;
        if (weight > type(uint64).max) weight = type(uint64).max;
        uint256 deltaWei = (weight - e.weightMilli) * DEC_BASE_UNIT;
        e.weightMilli = uint64(weight);

        DecSubbucket memory agg = decBucketBurnTotal[lvl][bucketUsed][p.subBucket];
        if (appended) {
            p.position = agg.length;
            agg.length = p.position + 1;
            decPointer[player] = p;
        }
        agg.totalBurn += uint192(carriedWei + deltaWei);
        decBucketBurnTotal[lvl][bucketUsed][p.subBucket] = agg;
        decEntry[_decEntryKey(lvl, bucketUsed, p.subBucket, p.position)] = e;

        if (fromBucket != 0) {
            emit DecBurnMigrated(
                player,
                lvl,
                fromBucket,
                fromSubBucket,
                bucketUsed,
                p.subBucket,
                p.position,
                uint192(carriedWei)
            );
        }
        if (deltaWei != 0) {
            emit DecBurnRecorded(
                player,
                lvl,
                bucketUsed,
                p.subBucket,
                p.position,
                deltaWei,
                weight * DEC_BASE_UNIT
            );
        }
    }

    /*+======================================================================+
      |                    DECIMATOR JACKPOT RESOLUTION                      |
      +======================================================================+
      |  Snapshots winning subbuckets for deferred settlement.               |
      +======================================================================+*/

    /// @notice Snapshot Decimator jackpot winners for deferred settlement.
    /// @dev Selects winning subbucket per denominator and snapshots totals.
    ///      Payouts happen when mineFlip's walk settles each winning entry.
    ///      Returns poolWei if level already snapshotted or no qualifying burns.
    /// @param poolWei Total ETH prize pool for this level.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return returnAmountWei Amount to return (non-zero if no winners or already snapshotted).
    /// @custom:access Restricted to game contract.
    function runDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

        // Prevent double-snapshotting: return pool if this level already snapshotted
        DecClaimRound storage round = decClaimRounds[lvl];
        if (round.poolWei != 0) {
            return poolWei;
        }

        uint256 totalBurn;
        uint64 packedOffsets;
        DecSubbucket[13][13] storage levelTotals = decBucketBurnTotal[lvl];

        // Select winning subbucket for each denominator (2-12)
        uint256 decSeed = rngWord;
        for (uint8 denom = 2; denom <= DECIMATOR_MAX_DENOM; ) {
            // Deterministically select winning subbucket from VRF
            uint8 winningSub = _decWinningSubbucket(decSeed, denom);
            packedOffsets = _packDecWinningSubbucket(
                packedOffsets,
                denom,
                winningSub
            );

            // Accumulate burn total from winning subbucket
            uint256 subTotal = levelTotals[denom][winningSub].totalBurn;
            if (subTotal != 0) {
                totalBurn += subTotal;
            }

            unchecked {
                ++denom;
            }
        }

        // No qualifying burns: return full pool
        if (totalBurn == 0) {
            return poolWei;
        }

        // Store packed winning subbuckets for the settle walk
        decBucketOffsetPacked[lvl] = packedOffsets;
        emit DecimatorResolved(lvl, packedOffsets, poolWei, totalBurn);

        // Snapshot the round for this level (persistent — no expiry)
        round.poolWei = uint96(poolWei);
        round.totalBurn = uint128(totalBurn);
        // Winners were already selected from the full VRF word above (decSeed) and packed
        // into decBucketOffsetPacked; the stored seed serves the settle-time box draw only,
        // on its own tagged stream so no other consumer of the day word shares its bits.
        round.rngWord = uint32(uint256(keccak256(abi.encode(rngWord, DECIMATOR_BOX_TAG))));

        return 0; // All funds held for settlement
    }

    /*+======================================================================+
      |                      DECIMATOR SETTLEMENT                            |
      +======================================================================+*/

    /// @notice mineFlip's decimator leg: settle drawn rounds' winning entries in list order —
    ///         oldest level first, denominators 2 to 12, positions ascending — within
    ///         `budgetUnits` of the shared keeper walk budget.
    /// @dev Delegatecall target of GameAfkingModule.mineFlip, so it runs in the Game's storage.
    ///      The walk is the only way a winning entry settles. It idles, touching nothing, while the
    ///      RNG lock is up, the liveness trigger reads true, or the game is over: under the lock a
    ///      settle's far-future roll would wait for the unlock, and a lootbox minted during the
    ///      ending would roll against a public terminal word. Every visit costs walk
    ///      units: a round probe, a list-length read or an empty entry 1, and a settle what it did
    ///      (its frame, any deferred half-passes and its box's outcome). A settle starts only while
    ///      budget remains and is charged after it runs, so only the last one can pass the budget,
    ///      by at most one settle. Whole half-pass units defer to `whalePassClaims`, redeemed later
    ///      through claimWhalePass.
    ///
    ///      A level with no stored round either has its draw still to come or drew no winner. The
    ///      draw runs as that level enters its jackpot phase, so once `level` has passed it the
    ///      walk steps over it; until then the walk waits there.
    /// @param budgetUnits Walk units the leg may spend.
    /// @return settled Entries settled this call.
    /// @return unitsUsed Walk units spent.
    /// @return moved Whether the cursor advanced.
    function settleDecimatorWinners(
        uint256 budgetUnits
    ) external returns (uint256 settled, uint256 unitsUsed, bool moved) {
        if (rngLockedFlag || gameOver || _livenessTriggered()) return (0, 0, false);

        DecSettleCursor memory start = decSettleCursor;
        if (start.lvl == 0) {
            start.lvl = _nextDecRoundLevel(0);
            start.denom = 2;
        }
        uint24 lvl = start.lvl;
        uint8 denom = start.denom;
        uint32 pos = start.position;
        uint24 currentLevel = level;

        DecClaimRound memory round;
        uint64 packed;
        bool haveRound;
        uint8 sub;
        uint32 len;
        bool haveLen;
        while (true) {
            if (!haveRound) {
                if (unitsUsed >= budgetUnits) break;
                ++unitsUsed;
                round = decClaimRounds[lvl];
                if (round.poolWei == 0) {
                    if (lvl >= currentLevel) break;
                    lvl = _nextDecRoundLevel(lvl);
                    denom = 2;
                    pos = 0;
                    continue;
                }
                packed = decBucketOffsetPacked[lvl];
                haveRound = true;
            }
            if (denom > DECIMATOR_MAX_DENOM) {
                lvl = _nextDecRoundLevel(lvl);
                denom = 2;
                pos = 0;
                haveRound = false;
                continue;
            }
            if (!haveLen) {
                if (unitsUsed >= budgetUnits) break;
                ++unitsUsed;
                sub = _unpackDecWinningSubbucket(packed, denom);
                len = decBucketBurnTotal[lvl][denom][sub].length;
                haveLen = true;
            }
            if (pos >= len) {
                ++denom;
                pos = 0;
                haveLen = false;
                continue;
            }
            if (unitsUsed >= budgetUnits) break;
            uint256 key = _decEntryKey(lvl, denom, sub, pos);
            DecEntry memory e = decEntry[key];
            uint256 amountWei = e.weightMilli == 0 ? 0 : _decShare(round, e.weightMilli);
            if (amountWei == 0) {
                ++unitsUsed;
                ++pos;
                continue;
            }
            // The call's first settle also pays for what every call touches once: the module
            // code and the protocol contracts a box credits, and the shared Game slots.
            if (settled == 0) unitsUsed += DEC_CALL_UNITS;
            unitsUsed += _settleDecEntry(e.owner, lvl, denom, key, round.rngWord, amountWei);
            ++settled;
            ++pos;
        }

        moved = lvl != start.lvl || denom != start.denom || pos != start.position;
        if (moved) decSettleCursor = DecSettleCursor(lvl, denom, pos);
    }

    /// @dev Settle one winning entry: half as claimable ETH, half as a lootbox. The lootbox
    ///      portion's pool credit is freeze-aware — it lands in the pending buffer while the pool
    ///      is frozen and in the live future pool otherwise — so a frozen pool is no bar to
    ///      settling. The caller computes `amountWei` (nonzero, live winning entry); this core
    ///      empties the entry before any credit is applied.
    /// @return units The settle's work in walk units: its frame, deferred passes and box.
    function _settleDecEntry(
        address player,
        uint24 lvl,
        uint8 denom,
        uint256 key,
        uint32 rngWord,
        uint256 amountWei
    ) private returns (uint256 units) {
        // Empty the entry to prevent double settlement.
        delete decEntry[key];

        // The denominator encodes the activity score sealed at decimator-burn time (see
        // _minScoreForBucket), freezing the lootbox EV multiplier instead of reading a live,
        // post-word score at settlement.
        (uint256 lootboxPortion, uint256 awardUnits) = _creditDecJackpotClaimCore(
            player,
            amountWei,
            uint256(keccak256(abi.encode(uint256(rngWord), DECIMATOR_BOX_TAG, lvl))),
            _minScoreForBucket(denom)
        );
        if (lootboxPortion != 0) {
            // Credit the lootbox backing to whichever accumulator is live: the pending
            // buffer while the pool is frozen (folded back by _unfreezePool), else the
            // live pools. Same shape as the sDGNRS redemption leg, which credits the
            // future pool ahead of its own lootbox resolution.
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(lootboxPortion));
            } else {
                _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);
            }
        }
        emit DecimatorClaimed(
            player,
            lvl,
            amountWei,
            amountWei - lootboxPortion,
            lootboxPortion
        );
        units = DEC_SETTLE_UNITS + awardUnits;
    }

    // -------------------------------------------------------------------------
    // Decimator Helpers
    // -------------------------------------------------------------------------

    /// @dev Credits a settled decimator win. Callers must ensure amount != 0 and
    ///      account != address(0).
    /// @return lootboxPortion Amount routed to lootbox tickets.
    /// @return units Walk units of the deferred passes and the box.
    function _creditDecJackpotClaimCore(
        address account,
        uint256 amount,
        uint256 rngWord,
        uint16 evScore
    ) private returns (uint256 lootboxPortion, uint256 units) {
        // Split 50/50: half ETH, half lootbox tickets
        uint256 ethPortion = amount >> 1;
        lootboxPortion = amount - ethPortion;

        _creditClaimable(account, ethPortion);

        // Lootbox portion is no longer claimable ETH; remove from reserved pool.
        claimablePool -= uint128(lootboxPortion); // Safe: lootboxPortion is a fraction of claimablePool, fits uint128
        units = _awardDecimatorLootbox(account, lootboxPortion, rngWord, evScore);
    }

    /// @dev Apply the multiplier to the part of this burn's base that still fits under the
    ///      cap (measured on base burned so far, not on weight); the rest counts 1x.
    ///      Every branch returns 0 for a zero baseAmount, so no zero early-return is needed.
    /// @param prevBase Base FLIP burned so far this level (wei).
    /// @param baseAmount New burn amount before multiplier.
    /// @param multBps Multiplier in basis points.
    /// @return effectiveAmount The effective burn amount after applying the capped multiplier.
    function _decEffectiveAmount(
        uint256 prevBase,
        uint256 baseAmount,
        uint256 multBps
    ) private pure returns (uint256 effectiveAmount) {
        if (multBps <= BPS_DENOMINATOR || prevBase >= DECIMATOR_MULTIPLIER_CAP) {
            return baseAmount;
        }
        uint256 remaining = DECIMATOR_MULTIPLIER_CAP - prevBase;
        uint256 multiplied = baseAmount <= remaining ? baseAmount : remaining;
        effectiveAmount = (multiplied * multBps) / BPS_DENOMINATOR + (baseAmount - multiplied);
    }

    /// @dev Deterministically select winning subbucket for a denominator.
    /// @param entropy VRF-derived randomness.
    /// @param denom Denominator (2-12).
    /// @return Winning subbucket index (0 to denom-1).
    function _decWinningSubbucket(
        uint256 entropy,
        uint8 denom
    ) private pure returns (uint8) {
        return
            uint8(uint256(keccak256(abi.encodePacked(entropy, denom))) % denom);
    }

    /// @dev Pack a winning subbucket into the packed uint64.
    ///      Layout: 4 bits per denom, starting at denom 2.
    /// @param packed Current packed value.
    /// @param denom Denominator to pack (2-12).
    /// @param sub Winning subbucket for this denom.
    /// @return Updated packed value.
    function _packDecWinningSubbucket(
        uint64 packed,
        uint8 denom,
        uint8 sub
    ) private pure returns (uint64) {
        uint8 shift = (denom - 2) << 2; // 4 bits per denom
        uint64 mask = uint64(0xF) << shift;
        return (packed & ~mask) | ((uint64(sub) & 0xF) << shift);
    }

    /// @dev Unpack a winning subbucket from the packed uint64. Callers pass a set
    ///      entry bucket, which is always in [2,12].
    /// @param packed Packed winning subbuckets.
    /// @param denom Denominator to unpack (2-12).
    /// @return Winning subbucket for this denom.
    function _unpackDecWinningSubbucket(
        uint64 packed,
        uint8 denom
    ) private pure returns (uint8) {
        uint8 shift = (denom - 2) << 2;
        return uint8((packed >> shift) & 0xF);
    }

    /// @dev Pro-rata share of a round's pool for an entry weight: pool x weight / totalBurn.
    ///      The round snapshot is only written with a nonzero totalBurn.
    function _decShare(
        DecClaimRound memory round,
        uint64 weightMilli
    ) private pure returns (uint256) {
        return
            (uint256(round.poolWei) * (uint256(weightMilli) * DEC_BASE_UNIT)) /
            uint256(round.totalBurn);
    }

    /// @dev Remove a migrating entry's weight from its old subbucket aggregate. The sole
    ///      caller is the bucket-migration branch, where denom is a set bucket in [2,12].
    /// @param lvl Level number.
    /// @param denom Denominator (bucket).
    /// @param sub Subbucket index.
    /// @param delta Burn weight to remove, in wei.
    function _decRemoveSubbucket(
        uint24 lvl,
        uint8 denom,
        uint8 sub,
        uint256 delta
    ) private {
        DecSubbucket storage agg = decBucketBurnTotal[lvl][denom][sub];
        uint256 slotTotal = agg.totalBurn;
        if (slotTotal < delta) revert Invariant();
        agg.totalBurn = uint192(slotTotal - delta);
    }

    /// @dev Slot key of a decimator list entry. The fields occupy disjoint bit ranges, so
    ///      distinct (lvl, denom, sub, position) tuples never share a key.
    function _decEntryKey(
        uint24 lvl,
        uint8 denom,
        uint8 sub,
        uint32 position
    ) private pure returns (uint256) {
        return
            (uint256(lvl) << 48) |
            (uint256(denom) << 40) |
            (uint256(sub) << 32) |
            uint256(position);
    }

    /// @dev The first level above `lvl` that draws a decimator: x5 levels other than x95, and
    ///      x00 levels (the windows open at x4 other than x94, and at x99).
    function _nextDecRoundLevel(uint24 lvl) private pure returns (uint24) {
        uint24 m = lvl % 100;
        uint24 k = ((m + 5) / 10) * 10 + 5;
        return k < 95 ? lvl - m + k : lvl - m + 100;
    }

    /// @dev Deterministically assign subbucket for a player.
    ///      Hash of (player, lvl, bucket) ensures consistent assignment.
    /// @param player Address.
    /// @param lvl Level number.
    /// @param bucket Denominator; always in [2,12] (FLIP's ActivityCurveLib.decBucket floors at >=2).
    /// @return Subbucket index (0 to bucket-1).
    function _decSubbucketFor(
        address player,
        uint24 lvl,
        uint8 bucket
    ) private pure returns (uint8) {
        return
            uint8(
                uint256(keccak256(abi.encodePacked(player, lvl, bucket))) %
                    bucket
            );
    }

    /// @dev Awards a settled winner's lootbox half. Whole half-pass units are recorded in
    ///      `whalePassClaims` for the winner to redeem through claimWhalePass.
    /// @param winner Address to receive tickets.
    /// @param amount Lootbox portion of the win in wei.
    /// @param rngWord VRF random word for lootbox resolution.
    /// @param evScore Activity score frozen when the winning burn was bucketed.
    /// @return units Walk units of the deferred passes and of the box's outcome.
    function _awardDecimatorLootbox(
        address winner,
        uint256 amount,
        uint256 rngWord,
        uint16 evScore
    ) private returns (uint256 units) {
        if (winner == address(0) || amount == 0) return 0;
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            // amount > 5 ether here, so fullHalfPasses = amount / 2.25 ether >= 2.
            uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
            uint256 remainder = amount % HALF_WHALE_PASS_PRICE;
            whalePassClaims[winner] += fullHalfPasses;
            units = DEC_WHALE_UNITS;
            // Sub-half-pass remainder (< 2.25 ether, so always below the threshold):
            // falls through to direct-resolve as a futurePool-backed lootbox (like any
            // small decimator win), staying in futurePrizePool where the caller put it
            // so it is never double-backed. Below 0.01 ETH it is too small to be worth a
            // box, so the dust simply stays in futurePrizePool as future-prize liquidity
            // (no credit).
            if (remainder < 0.01 ether) return units;
            amount = remainder;
        }
        // Resolve lootbox via delegatecall to open module. The decimator recirc box itemizes its
        // contents via LootBoxOpened (per-box FLIP otherwise lost in creditFlip) so every box
        // leaves exactly one settlement event.
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    winner,
                    amount,
                    rngWord,
                    evScore
                )
            );
        if (!ok) _revertDelegate(data);
        units += abi.decode(data, (uint256));
    }

    /// @dev Minimum activity score that lands a burn in `bucket` — the inverse of the
    ///      shared bucket ladder. The decimator lootbox EV multiplier reads this
    ///      sealed value (frozen when the winning burn was bucketed) rather than a live score.
    function _minScoreForBucket(uint8 bucket) private pure returns (uint16) {
        return ActivityCurveLib.minScoreForBucket(bucket);
    }

}
