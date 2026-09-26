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
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
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
    /// @param effectiveAmount Burn weight after the multiplier. The multiplier applies to
    ///        the first DECIMATOR_MULTIPLIER_CAP of BASE burned at this level; the weight
    ///        it produces is itself uncapped.
    /// @param newTotalBurn Player's new total burn for this level.
    event DecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint8 bucket,
        uint8 subBucket,
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
    /// @param movedBurn The carried-over burn (0 when the entry had no burn yet).
    event DecBurnMigrated(
        address indexed player,
        uint24 indexed lvl,
        uint8 fromBucket,
        uint8 fromSubBucket,
        uint8 toBucket,
        uint8 toSubBucket,
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

    /// @notice Emitted when a player claims a decimator jackpot for a level.
    /// @param player The claimer.
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

    /// @notice Claim attempted after already claiming this level.
    error DecAlreadyClaimed();

    /// @notice Claim attempted but player is not a winning subbucket.
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
    /// @dev Unit of DecBet.baseMilli: a thousandth of a FLIP.
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

    /// @dev Keeper box-bounty target (ETH wei) per settled decimator claim. Sized so the FLIP
    ///      bounty's ETH-value reimburses the ~30k-gas per-box settle at the ~0.5-gwei reference.
    ///      The reward is an illiquid coinflip credit, and every claimable bet costs a real
    ///      decimator burn to create, so permissionlessly cranking others' claims is liveness work
    ///      rather than a clean farm even when it roughly breaks even.
    uint256 private constant BOX_BOUNTY_ETH_TARGET = 15_000_000_000_000;

    // -------------------------------------------------------------------------
    // External Entry Points (delegatecall targets)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Decimator Burn Tracking
    // -------------------------------------------------------------------------

    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @dev Called by coin contract on every Decimator burn.
    ///      First burn sets the player's bucket (denominator), derived from their activity score.
    ///      Subbucket is deterministically assigned from hash(player, lvl, bucket).
    ///      Subsequent burns accumulate in that bucket unless a rising activity score qualifies a
    ///      strictly better (lower denominator) bucket. On improvement, previous burn
    ///      is removed from old aggregate, carried over to the new bucket, and bet migrates.
    ///      Burn amount capped at uint192.max with saturation.
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

        DecBet storage e = decBurn[lvl][player];
        DecBet memory m = e;
        uint192 prevBurn = m.burn;

        // First burn this level: set bucket and deterministic subbucket.
        // `bucket` arrives coin-validated in [2,12] (FLIP derives it via
        // ActivityCurveLib.decBucket, floor >=2), so a nonzero check is unnecessary on the migration branch.
        if (m.bucket == 0) {
            m.bucket = bucket;
            m.subBucket = _decSubbucketFor(player, lvl, bucket);
            e.bucket = m.bucket;
            e.subBucket = m.subBucket;
        } else if (bucket < m.bucket) {
            // Better bucket selected: migrate burn to new subbucket.
            _decRemoveSubbucket(lvl, m.bucket, m.subBucket, prevBurn);
            uint8 fromBucket = m.bucket;
            uint8 fromSubBucket = m.subBucket;
            m.bucket = bucket;
            m.subBucket = _decSubbucketFor(player, lvl, bucket);
            e.bucket = m.bucket;
            e.subBucket = m.subBucket;
            // Seed new subbucket with carried-over burn.
            if (prevBurn != 0) {
                _decUpdateSubbucket(lvl, m.bucket, m.subBucket, prevBurn);
            }
            emit DecBurnMigrated(
                player,
                lvl,
                fromBucket,
                fromSubBucket,
                m.bucket,
                m.subBucket,
                prevBurn
            );
        }

        bucketUsed = m.bucket;

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
            uint256(m.baseMilli) * DEC_BASE_UNIT,
            baseAmount,
            multBps
        );
        // Track the base burned (floored to the unit, saturating) so the cap keeps
        // measuring base rather than weight across every later burn this level.
        uint256 baseUnits = uint256(m.baseMilli) + baseAmount / DEC_BASE_UNIT;
        if (baseUnits > type(uint40).max) baseUnits = type(uint40).max;
        e.baseMilli = uint40(baseUnits);

        // Accumulate burn with uint192 saturation
        uint256 updated = uint256(prevBurn) + effectiveAmount;
        if (updated > type(uint192).max) updated = type(uint192).max;
        uint192 newBurn = uint192(updated);
        // bucket/subBucket are already current in storage (written only by the
        // first-burn and migration branches above); only the burn member changes here.
        e.burn = newBurn;

        // Update subbucket aggregate if burn increased
        uint192 delta = newBurn - prevBurn;
        if (delta != 0) {
            _decUpdateSubbucket(lvl, bucketUsed, m.subBucket, delta);
            emit DecBurnRecorded(
                player,
                lvl,
                bucketUsed,
                m.subBucket,
                delta,
                newBurn
            );
        }

        return bucketUsed;
    }

    /*+======================================================================+
      |                    DECIMATOR JACKPOT RESOLUTION                      |
      +======================================================================+
      |  Snapshots winning subbuckets for deferred claim distribution.       |
      +======================================================================+*/

    /// @notice Snapshot Decimator jackpot winners for deferred claims.
    /// @dev Selects winning subbucket per denominator and snapshots totals.
    ///      Actual distribution happens via claim functions.
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
        uint256[13][13] storage levelTotals = decBucketBurnTotal[lvl];

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
            uint256 subTotal = levelTotals[denom][winningSub];
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

    /// @notice Resolve a Decimator jackpot claim for `player` (permissionless).
    /// @dev Anyone may crank any winner's claim; payout always credits `player`, never the
    ///      caller. Resolution-into-claimable only (no ETH leaves here). Whole Whale Pass
    ///      units in a large lootbox portion materialize immediately on this single path.
    /// @param player The winner whose claim this resolves (payout always credits them).
    /// @param lvl Level to claim from.
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    /// @custom:reverts DecAlreadyClaimed When caller has already claimed for this level.
    /// @custom:reverts DecNotWinner When caller's subbucket did not win.
    function claimDecimatorJackpot(address player, uint24 lvl) external {
        // Permissionless: anyone may resolve `player`'s claim — all value credits to `player` (the
        // winner), never the caller. Taking the winner's exclusive claim timing away removes the
        // lootbox round-up from any single party's control. Resolution-into-claimable only (no ETH
        // leaves here); the player withdraws via the access-gated claimWinnings.
        // A frozen pool is no bar: the lootbox backing routes to the pending buffer and
        // the roll seeds off this level's own committed word, never a live one. Only
        // far-future ticket creation is lock-sensitive, and _queueEntries rejects that
        // on its own, so a roll that lands far-future waits for the unlock.
        DecClaimRound storage round = decClaimRounds[lvl];
        uint256 poolWei = round.poolWei;
        if (poolWei == 0) revert DecClaimInactive();

        DecBet storage e = decBurn[lvl][player];
        if (e.claimed != 0) revert DecAlreadyClaimed();

        // Calculate pro-rata share if player's subbucket won
        uint256 amountWei = _decClaimableFromBet(
            poolWei,
            uint256(round.totalBurn),
            e,
            decBucketOffsetPacked[lvl]
        );
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
            player,
            lvl,
            e,
            round.rngWord,
            amountWei,
            _terminalClaim(),
            false
        );
    }

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players.
    /// @dev Non-claimable entries (already claimed / non-winner) are skipped, not reverted,
    ///      so one stale address can't poison a mass-claim sweep. Whole half-pass units (2.25 ETH
    ///      of ticket face each) accumulate in `whalePassClaims`; any sub-unit remainder still
    ///      resolves here.
    /// @param players Winners whose claims to resolve.
    /// @param lvl Level to claim from (any persisted round; snapshots never expire).
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    function claimDecimatorJackpotMany(
        address[] calldata players,
        uint24 lvl
    ) external {
        DecClaimRound storage round = decClaimRounds[lvl];
        uint256 poolWei = round.poolWei;
        if (poolWei == 0) revert DecClaimInactive();

        // Loop-invariant snapshot values: the claim round is written exactly once
        // (runDecimatorJackpot is idempotent per level) and the terminal-mode flag only
        // flips in game-over resolution — none of the claim effects below can change them.
        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        uint256 totalBurn = uint256(round.totalBurn);
        // Loop-invariant: each iteration's lootbox delegatecall would otherwise force a re-SLOAD.
        uint32 rngWordCached = round.rngWord;
        mapping(address => DecBet) storage decLevelBets = decBurn[lvl];
        bool over = _terminalClaim();
        uint256 settled;
        for (uint256 i; i < players.length; ++i) {
            DecBet storage e = decLevelBets[players[i]];
            if (e.claimed != 0) continue;
            uint256 amountWei = _decClaimableFromBet(
                poolWei,
                totalBurn,
                e,
                packedOffsets
            );
            if (amountWei == 0) continue;
            _claimDecimatorJackpotFor(
                players[i],
                lvl,
                e,
                rngWordCached,
                amountWei,
                over,
                true
            );
            unchecked {
                ++settled;
            }
        }

        // Keeper bounty: a small FLIP flip-credit per box actually settled this call, paid to the
        // caller during a live game (no liveness need post-gameOver). Counts only settled boxes —
        // already-claimed and non-winner entries are skipped above and earn nothing. The ETH-value
        // tracks the per-box settle gas at the 0.5-gwei reference (FLIP per ETH = PRICE_COIN_UNIT /
        // the routed ticket price the Game's mintPrice quotes, so the credit holds its
        // gas-reimbursement value across the price curve).
        if (!over && settled != 0) {
            coinflip.creditFlip(
                msg.sender,
                (settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
                    PriceLookupLib.priceForLevel(_activeTicketLevel())
            );
        }
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

    /// @dev Shared claim core for the single and batch entry points. The lootbox portion's
    ///      pool credit is freeze-aware at the call site below — it lands in the pending
    ///      buffer while the pool is frozen and in the live future pool otherwise — so a
    ///      frozen pool is no bar to claiming and callers do not gate on it.
    ///      Callers validate eligibility and compute `amountWei` (nonzero, unclaimed bet);
    ///      this core marks the bet claimed before any credit is applied. `deferWhalePass`
    ///      changes only delivery timing for whole half-pass units.
    function _claimDecimatorJackpotFor(
        address player,
        uint24 lvl,
        DecBet storage e,
        uint32 rngWord,
        uint256 amountWei,
        bool over,
        bool deferWhalePass
    ) private {
        // Capture the winning entry's bucket before the claim consumes it; the bucket encodes
        // the activity score sealed at decimator-burn time (see _minScoreForBucket), freezing
        // the lootbox EV multiplier instead of reading a live, post-word score at claim.
        uint8 winBucket = e.bucket;

        // Mark as claimed to prevent double-claiming
        e.claimed = 1;

        if (over) {
            _creditClaimable(player, amountWei);
            emit DecimatorClaimed(player, lvl, amountWei, amountWei, 0);
            return;
        }

        uint256 lootboxPortion = _creditDecJackpotClaimCore(
            player,
            amountWei,
            uint256(keccak256(abi.encode(uint256(rngWord), DECIMATOR_BOX_TAG, lvl))),
            _minScoreForBucket(winBucket),
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

    /// @dev Calculate pro-rata claimable amount for a player's DecBet.
    /// @param poolWei Total pool available for claims.
    /// @param totalBurn Total qualifying burn (denominator for pro-rata). Callers
    ///        guarantee nonzero: the round snapshot is only written with a nonzero
    ///        totalBurn, and the view path checks it explicitly.
    /// @param e Player's DecBet storage reference.
    /// @param packedOffsets Packed winning subbuckets.
    /// @return amountWei Player's pro-rata share (0 if not winner).
    function _decClaimableFromBet(
        uint256 poolWei,
        uint256 totalBurn,
        DecBet storage e,
        uint64 packedOffsets
    ) private view returns (uint256 amountWei) {
        uint8 denom = e.bucket;
        uint8 sub = e.subBucket;
        uint192 decBetBurn = e.burn;

        // No participation or zero burn
        if (denom == 0 || decBetBurn == 0) return 0;

        // Check if player's subbucket matches winning subbucket
        uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, denom);
        if (sub != winningSub) return 0;

        // Pro-rata share: (pool × playerBurn) / totalBurn
        amountWei = (poolWei * uint256(decBetBurn)) / totalBurn;
    }

    /// @dev Update aggregated burn totals for a subbucket. Callers guarantee
    ///      delta != 0 and denom in [2,12] (coin-validated bucket values).
    /// @param lvl Level number.
    /// @param denom Denominator (bucket).
    /// @param sub Subbucket index.
    /// @param delta Burn amount to add.
    function _decUpdateSubbucket(
        uint24 lvl,
        uint8 denom,
        uint8 sub,
        uint192 delta
    ) internal {
        decBucketBurnTotal[lvl][denom][sub] += uint256(delta);
    }

    /// @dev Remove aggregated burn totals for a subbucket. The sole caller is the
    ///      bucket-migration branch, where denom is a set bucket in [2,12].
    /// @param lvl Level number.
    /// @param denom Denominator (bucket).
    /// @param sub Subbucket index.
    /// @param delta Burn amount to remove (0 when the migrating entry has no burn yet).
    function _decRemoveSubbucket(
        uint24 lvl,
        uint8 denom,
        uint8 sub,
        uint192 delta
    ) internal {
        if (delta == 0) return;
        uint256 slotTotal = decBucketBurnTotal[lvl][denom][sub];
        if (slotTotal < uint256(delta)) revert Invariant();
        decBucketBurnTotal[lvl][denom][sub] = slotTotal - uint256(delta);
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
