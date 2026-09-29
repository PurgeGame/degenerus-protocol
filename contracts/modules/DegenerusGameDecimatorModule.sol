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
 * @notice Delegate-called module handling decimator jackpot tracking, resolution, and claim credits.
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
    /// @param position The entry's position in the (lvl, bucket, subBucket) list — with lvl and
    ///        bucket, what `claimDecimatorJackpot` names.
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

    /// @notice Emitted when a winning decimator entry settles, by claim or by mineFlip's walk.
    /// @param player The entry's owner, credited with the payout.
    /// @param lvl Decimator level being claimed.
    /// @param amountWei Total pro-rata payout in wei.
    /// @param ethPortion Portion credited as ETH claimable.
    /// @param lootboxPortion Portion routed to whale passes / lootbox (0 post-GAMEOVER).
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

    /// @notice Claim attempted for an inactive decimator round.
    error DecClaimInactive();
    /// @notice The game-over trigger reads true but the ending has not finished: a claim waits for
    ///         game over rather than settle in a shape the game might not end in.
    error EndingPending();

    /// @notice The named winning entry is already settled, moved to a better bucket, or past
    ///         the list's end.
    error DecAlreadyClaimed();

    /// @notice The named denominator is outside 2-12, or the entry's share rounds to zero.
    error DecNotWinner();

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

    /// @dev Walk-budget weight of one settle in mineFlip's decimator leg, in the shared open-budget
    ///      unit (1 unit ~= 4.7k gas; see OPEN_HUMAN_ENTRY_WEIGHT). Covers the entry read, the
    ///      claimable credit, the pool moves and the lootbox resolution. Priced at the cold p90 of a
    ///      whale-pass-sized settle (~200k; test/gas/DecimatorSettleGas.t.sol), so a full budget holds
    ///      45 settles: ~9.1M at that p90 and under 11.5M even with every settle at the measured
    ///      maximum. A round probe, a list-length read and an empty entry cost 1 unit each.
    uint256 private constant DEC_SETTLE_WEIGHT = 42;

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
      |  Snapshots winning subbuckets for deferred claim distribution.       |
      +======================================================================+*/

    /// @notice Snapshot Decimator jackpot winners for deferred settlement.
    /// @dev Selects winning subbucket per denominator and snapshots totals.
    ///      Payouts happen when mineFlip's walk or a claim settles each winning entry.
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

        // Store packed winning subbuckets for claim validation
        decBucketOffsetPacked[lvl] = packedOffsets;
        emit DecimatorResolved(lvl, packedOffsets, poolWei, totalBurn);

        // Snapshot claim round for this level (persistent — no expiry)
        round.poolWei = uint96(poolWei);
        round.totalBurn = uint128(totalBurn);
        // Winners were already selected from the full VRF word above (decSeed) and packed
        // into decBucketOffsetPacked; the stored seed serves the claim-time box draw only,
        // on its own tagged stream so no other consumer of the day word shares its bits.
        round.rngWord = uint32(uint256(keccak256(abi.encode(rngWord, DECIMATOR_BOX_TAG))));

        return 0; // All funds held for claims
    }

    /*+======================================================================+
      |                      DECIMATOR CLAIM FUNCTIONS                       |
      +======================================================================+*/

    /// @notice Settle one winning decimator entry (permissionless).
    /// @dev Anyone may settle any winning entry; payout always credits the entry's owner, never the
    ///      caller. Resolution-into-claimable only (no ETH leaves here). Whole Whale Pass units in a
    ///      large lootbox portion materialize immediately on this path. The winning subbucket is
    ///      implied by `denom`, so only winning entries can be named. Stays open after game over,
    ///      where mineFlip's walk no longer runs, and pays the terminal shape there.
    /// @param lvl Level whose round the entry won.
    /// @param denom The entry's denominator (2-12).
    /// @param position The entry's position in its winning list (from DecBurnRecorded or
    ///        DecBurnMigrated).
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    /// @custom:reverts DecNotWinner When `denom` is outside 2-12 or the share rounds to zero.
    /// @custom:reverts DecAlreadyClaimed When no live entry sits at that position.
    function claimDecimatorJackpot(
        uint24 lvl,
        uint8 denom,
        uint32 position
    ) external {
        // Taking the winner's exclusive claim timing away removes the lootbox round-up from any
        // single party's control. A frozen pool is no bar: the lootbox backing routes to the
        // pending buffer and the roll seeds off this level's own committed word, never a live
        // one. Only far-future ticket creation is lock-sensitive, and _queueEntries rejects
        // that on its own, so a roll that lands far-future waits for the unlock.
        DecClaimRound memory round = decClaimRounds[lvl];
        if (round.poolWei == 0) revert DecClaimInactive();
        if (denom < 2 || denom > DECIMATOR_MAX_DENOM) revert DecNotWinner();

        uint8 sub = _unpackDecWinningSubbucket(decBucketOffsetPacked[lvl], denom);
        uint256 key = _decEntryKey(lvl, denom, sub, position);
        DecEntry memory e = decEntry[key];
        if (e.weightMilli == 0) revert DecAlreadyClaimed();

        uint256 amountWei = _decShare(round, e.weightMilli);
        if (amountWei == 0) revert DecNotWinner();

        // Terminal mode covers the whole death sequence: from the liveness trigger to the
        // gameOver latch the claim would otherwise take the live branch and mint a
        // lootbox, whose roll queues ticket entries against an already-public terminal
        // word. Terminal mode pays the full amount as claimable instead — the claim stays
        // open, it just stops creating positions. Both terms are load-bearing: gameOver is
        // the authoritative latch this routing decision must never misread, and liveness
        // extends the same treatment back over the multi-tx drain that precedes it. They
        // share slot 0, so the pair costs one bit-test on an already-loaded word.
        _claimDecimatorJackpotFor(
            e.owner,
            lvl,
            denom,
            key,
            round.rngWord,
            amountWei,
            _terminalClaim(),
            false
        );
    }

    /// @notice mineFlip's decimator leg: settle drawn rounds' winning entries in list order —
    ///         oldest level first, denominators 2 to 12, positions ascending — within
    ///         `budgetUnits` of the shared keeper walk budget.
    /// @dev Delegatecall target of GameAfkingModule.mineFlip, so it runs in the Game's storage.
    ///      Idles, touching nothing, while the RNG lock is up, the liveness trigger reads true, or
    ///      the game is over: under the lock a settle's far-future roll would wait for the unlock,
    ///      and the ending settles through the claim in terminal shape. Every visit costs walk
    ///      units: a round probe, a list-length read or an empty entry 1, a settle
    ///      DEC_SETTLE_WEIGHT. A settle is priced before it runs, so the leg never spends past the
    ///      budget; one that does not fit leaves the cursor on it. Whole half-pass units defer to
    ///      `whalePassClaims`, redeemed later through claimWhalePass.
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
            if (budgetUnits - unitsUsed < DEC_SETTLE_WEIGHT) break;
            _claimDecimatorJackpotFor(
                e.owner,
                lvl,
                denom,
                key,
                round.rngWord,
                amountWei,
                false,
                true
            );
            unitsUsed += DEC_SETTLE_WEIGHT;
            ++settled;
            ++pos;
        }

        moved = lvl != start.lvl || denom != start.denom || pos != start.position;
        if (moved) decSettleCursor = DecSettleCursor(lvl, denom, pos);
    }

    /// @dev Whether a claim settles in terminal shape (100% cash, no lootbox): only once the game
    ///      is over, which is irreversible. While the game-over trigger reads true before that, the
    ///      claim reverts and waits: the trigger can still read false again, and a terminal shape
    ///      taken then would stick; and during the ending itself the live branch would mint a
    ///      lootbox whose roll queues entries against a public word.
    function _terminalClaim() private view returns (bool) {
        if (gameOver) return true;
        if (_livenessTriggered()) revert EndingPending();
        return false;
    }

    /// @dev Shared settle core for the claim and mineFlip's walk. The lootbox portion's
    ///      pool credit is freeze-aware at the call site below — it lands in the pending
    ///      buffer while the pool is frozen and in the live future pool otherwise — so a
    ///      frozen pool is no bar to settling and callers do not gate on it.
    ///      Callers validate eligibility and compute `amountWei` (nonzero, live winning entry);
    ///      this core empties the entry before any credit is applied. `deferWhalePass`
    ///      changes only delivery timing for whole half-pass units.
    function _claimDecimatorJackpotFor(
        address player,
        uint24 lvl,
        uint8 denom,
        uint256 key,
        uint32 rngWord,
        uint256 amountWei,
        bool over,
        bool deferWhalePass
    ) private {
        // Empty the entry to prevent double settlement.
        delete decEntry[key];

        if (over) {
            _creditClaimable(player, amountWei);
            emit DecimatorClaimed(player, lvl, amountWei, amountWei, 0);
            return;
        }

        // The denominator encodes the activity score sealed at decimator-burn time (see
        // _minScoreForBucket), freezing the lootbox EV multiplier instead of reading a live,
        // post-word score at settlement.
        uint256 lootboxPortion = _creditDecJackpotClaimCore(
            player,
            amountWei,
            uint256(keccak256(abi.encode(uint256(rngWord), DECIMATOR_BOX_TAG, lvl))),
            _minScoreForBucket(denom),
            deferWhalePass
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
    }

    // -------------------------------------------------------------------------
    // Decimator Helpers
    // -------------------------------------------------------------------------

    /// @dev Credits decimator claim in normal (non-gameover) mode.
    ///      Callers must ensure amount != 0 and account != address(0).
    /// @return lootboxPortion Amount routed to lootbox tickets.
    function _creditDecJackpotClaimCore(
        address account,
        uint256 amount,
        uint256 rngWord,
        uint16 evScore,
        bool deferWhalePass
    ) private returns (uint256 lootboxPortion) {
        // Split 50/50: half ETH, half lootbox tickets
        uint256 ethPortion = amount >> 1;
        lootboxPortion = amount - ethPortion;

        _creditClaimable(account, ethPortion);

        // Lootbox portion is no longer claimable ETH; remove from reserved pool.
        claimablePool -= uint128(lootboxPortion); // Safe: lootboxPortion is a fraction of claimablePool, fits uint128
        _awardDecimatorLootbox(
            account,
            lootboxPortion,
            rngWord,
            evScore,
            deferWhalePass
        );
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

    /// @dev Awards decimator lootbox rewards to a claimer.
    /// @param winner Address to receive tickets.
    /// @param amount Lootbox portion of decimator claim in wei.
    /// @param rngWord VRF random word for lootbox resolution.
    /// @param evScore Activity score frozen when the winning burn was bucketed.
    /// @param deferWhalePass Whether whole half-pass units are recorded for later claiming.
    function _awardDecimatorLootbox(
        address winner,
        uint256 amount,
        uint256 rngWord,
        uint16 evScore,
        bool deferWhalePass
    ) private {
        if (winner == address(0) || amount == 0) return;
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            // amount > 5 ether here, so fullHalfPasses = amount / 2.25 ether >= 2.
            uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
            uint256 remainder = amount % HALF_WHALE_PASS_PRICE;
            if (deferWhalePass) {
                whalePassClaims[winner] += fullHalfPasses;
            } else {
                uint24 startLevel = level + 1;
                _applyWhalePassStats(winner, startLevel);
                _queueHalfPassAward(winner, startLevel, 100, fullHalfPasses, false);
            }
            // Sub-half-pass remainder (< 2.25 ether, so always below the threshold):
            // falls through to direct-resolve as a futurePool-backed lootbox (like any
            // small decimator claim), staying in futurePrizePool where the caller put it
            // so it is never double-backed. Below 0.01 ETH it is too small to be worth a
            // box, so the dust simply stays in futurePrizePool as future-prize liquidity
            // (no credit).
            if (remainder < 0.01 ether) return;
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
    }

    /// @dev Minimum activity score that lands a burn in `bucket` — the inverse of the
    ///      shared bucket ladder. The decimator-claim lootbox EV multiplier reads this
    ///      sealed value (frozen when the winning burn was bucketed) rather than a live score.
    function _minScoreForBucket(uint8 bucket) private pure returns (uint16) {
        return ActivityCurveLib.minScoreForBucket(bucket);
    }

}
