// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
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
    /// @param effectiveAmount Burn amount after multiplier (capped).
    /// @param newTotalBurn Player's new total burn for this level.
    event DecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint8 bucket,
        uint8 subBucket,
        uint256 effectiveAmount,
        uint256 newTotalBurn
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
    error PrizePoolFrozen(); // Claim attempted while the prize pool is frozen (advanceGame in progress).

    /// @notice Caller is not the authorized coin contract.
    error OnlyCoin();

    /// @notice Caller is not the authorized game contract.
    error OnlyGame();

    /// @notice Claim attempted for an inactive decimator round.
    error DecClaimInactive();

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

    /// @dev Multiplier cap for Decimator burns (200 mints worth).
    uint256 private constant DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT;

    /// @dev Maximum denominator for Decimator buckets (2-12 inclusive).
    uint8 private constant DECIMATOR_MAX_DENOM = 12;

    /// @dev Keeper box-bounty target (ETH wei) per settled decimator claim. Sized so the FLIP
    ///      bounty's ETH-value reimburses the ~30k-gas per-box settle at the ~0.5-gwei reference.
    ///      The reward is an illiquid coinflip credit, and every claimable entry costs a real
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
    ///      First burn sets player's bucket (denominator) choice.
    ///      Subbucket is deterministically assigned from hash(player, lvl, bucket).
    ///      Subsequent burns accumulate in that bucket unless a strictly better
    ///      bucket (lower denominator) is provided. On improvement, previous burn
    ///      is removed from old aggregate, carried over to the new bucket, and entry migrates.
    ///      Burn amount capped at uint192.max with saturation.
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param bucket Player's chosen denominator (2-12).
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Player bonus multiplier in basis points (10000 = 1x).
    /// @return bucketUsed The bucket actually used (may differ from requested if not an improvement).
    /// @custom:access Restricted to coin contract.
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint8 bucket,
        uint256 baseAmount,
        uint256 multBps
    ) external returns (uint8 bucketUsed) {
        if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();

        DecEntry storage e = decBurn[lvl][player];
        DecEntry memory m = e;
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
            m.bucket = bucket;
            m.subBucket = _decSubbucketFor(player, lvl, bucket);
            e.bucket = m.bucket;
            e.subBucket = m.subBucket;
            // Seed new subbucket with carried-over burn.
            if (prevBurn != 0) {
                _decUpdateSubbucket(lvl, m.bucket, m.subBucket, prevBurn);
            }
        }

        bucketUsed = m.bucket;

        uint256 effectiveAmount = _decEffectiveAmount(
            uint256(prevBurn),
            baseAmount,
            multBps
        );

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
        // into decBucketOffsetPacked; only the claim-time lootbox seed is stored, narrowed.
        round.rngWord = uint32(rngWord);

        return 0; // All funds held for claims
    }

    /*+======================================================================+
      |                      DECIMATOR CLAIM FUNCTIONS                       |
      +======================================================================+*/

    /// @notice Claim Decimator jackpot for caller.
    /// @dev Public function for players to claim their own jackpot.
    ///      Credits payout to player's claimable balance.
    /// @param lvl Level to claim from.
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    /// @custom:reverts DecAlreadyClaimed When caller has already claimed for this level.
    /// @custom:reverts DecNotWinner When caller's subbucket did not win.
    function claimDecimatorJackpot(address player, uint24 lvl) external {
        // Permissionless: anyone may resolve `player`'s claim — all value credits to `player` (the
        // winner), never the caller. Taking the winner's exclusive claim timing away removes the
        // lootbox round-up from any single party's control. Resolution-into-claimable only (no ETH
        // leaves here); the player withdraws via the access-gated claimWinnings.
        if (prizePoolFrozen) revert PrizePoolFrozen();

        DecClaimRound storage round = decClaimRounds[lvl];
        uint256 poolWei = round.poolWei;
        if (poolWei == 0) revert DecClaimInactive();

        DecEntry storage e = decBurn[lvl][player];
        if (e.claimed != 0) revert DecAlreadyClaimed();

        // Calculate pro-rata share if player's subbucket won
        uint256 amountWei = _decClaimableFromEntry(
            poolWei,
            uint256(round.totalBurn),
            e,
            decBucketOffsetPacked[lvl]
        );
        if (amountWei == 0) revert DecNotWinner();

        _claimDecimatorJackpotFor(player, lvl, e, round, amountWei, gameOver);
    }

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players.
    /// @dev Non-claimable entries (already claimed / non-winner) are skipped, not reverted,
    ///      so one stale address can't poison a mass-claim sweep.
    /// @param players Winners whose claims to resolve.
    /// @param lvl Level to claim from (must be the last decimator).
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    function claimDecimatorJackpotMany(
        address[] calldata players,
        uint24 lvl
    ) external {
        if (prizePoolFrozen) revert PrizePoolFrozen();

        DecClaimRound storage round = decClaimRounds[lvl];
        uint256 poolWei = round.poolWei;
        if (poolWei == 0) revert DecClaimInactive();

        // Loop-invariant snapshot values: the claim round is written exactly once
        // (runDecimatorJackpot is idempotent per level) and gameOver only flips in
        // game-over resolution — none of the claim effects below can change them.
        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        uint256 totalBurn = uint256(round.totalBurn);
        mapping(address => DecEntry) storage levelEntries = decBurn[lvl];
        bool over = gameOver;
        uint256 settled;
        for (uint256 i; i < players.length; ++i) {
            DecEntry storage e = levelEntries[players[i]];
            if (e.claimed != 0) continue;
            uint256 amountWei = _decClaimableFromEntry(
                poolWei,
                totalBurn,
                e,
                packedOffsets
            );
            if (amountWei == 0) continue;
            _claimDecimatorJackpotFor(players[i], lvl, e, round, amountWei, over);
            unchecked {
                ++settled;
            }
        }

        // Keeper bounty: a small FLIP flip-credit per box actually settled this call, paid to the
        // caller during a live game (no liveness need post-gameOver). Counts only settled boxes —
        // already-claimed and non-winner entries are skipped above and earn nothing. The ETH-value
        // tracks the per-box settle gas at the 0.5-gwei reference (FLIP per ETH = PRICE_COIN_UNIT /
        // mintPrice, so the credit holds its gas-reimbursement value across the price curve).
        if (!over && settled != 0) {
            coinflip.creditFlip(
                msg.sender,
                (settled * BOX_BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) /
                    _mintPriceInContext()
            );
        }
    }

    /// @dev In-context mint price for the box-bounty ETH→FLIP conversion, mirroring the Game's
    ///      `mintPrice` (the active ticket level's price): jackpot phase targets the current level,
    ///      purchase phase the next. Read from shared storage so the bounty math needs no self-call.
    function _mintPriceInContext() private view returns (uint256) {
        return PriceLookupLib.priceForLevel(jackpotPhaseFlag ? level : level + 1);
    }

    /// @dev Shared claim core for the single and batch entry points. Callers must check
    ///      prizePoolFrozen first — this path writes to futurePrizePool (lootbox portion);
    ///      allowing it during freeze would corrupt the live pool that advanceGame operates on.
    ///      Callers validate eligibility and compute `amountWei` (nonzero, unclaimed entry);
    ///      this core marks the entry claimed before any credit is applied.
    function _claimDecimatorJackpotFor(
        address player,
        uint24 lvl,
        DecEntry storage e,
        DecClaimRound storage round,
        uint256 amountWei,
        bool over
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
            round.rngWord,
            _minScoreForBucket(winBucket)
        );
        if (lootboxPortion != 0) {
            _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);
        }
        emit DecimatorClaimed(
            player,
            lvl,
            amountWei,
            amountWei - lootboxPortion,
            lootboxPortion
        );
    }

    /// @notice Check if player can claim Decimator jackpot for a level.
    /// @dev View function for UI to show claimable amounts.
    /// @param player Address to check.
    /// @param lvl Level to check.
    /// @return amountWei Claimable amount (0 if not winner or already claimed).
    /// @return winner True if player is a winner for this level.
    function decClaimable(
        address player,
        uint24 lvl
    ) external view returns (uint256 amountWei, bool winner) {
        DecClaimRound storage round = decClaimRounds[lvl];
        if (round.poolWei == 0) {
            return (0, false);
        }
        return _decClaimable(round, player, lvl);
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
        uint16 evScore
    ) private returns (uint256 lootboxPortion) {
        // Split 50/50: half ETH, half lootbox tickets
        uint256 ethPortion = amount >> 1;
        lootboxPortion = amount - ethPortion;

        _creditClaimable(account, ethPortion);

        // Lootbox portion is no longer claimable ETH; remove from reserved pool.
        claimablePool -= uint128(lootboxPortion); // Safe: lootboxPortion is a fraction of claimablePool, fits uint128
        _awardDecimatorLootbox(account, lootboxPortion, rngWord, evScore);
    }

    /// @dev Apply multiplier until the cap is reached; extra amount is counted at 1x.
    ///      Every branch returns 0 for a zero baseAmount, so no zero early-return is needed.
    /// @param prevBurn Previous accumulated burn amount.
    /// @param baseAmount New burn amount before multiplier.
    /// @param multBps Multiplier in basis points.
    /// @return effectiveAmount The effective burn amount after applying capped multiplier.
    function _decEffectiveAmount(
        uint256 prevBurn,
        uint256 baseAmount,
        uint256 multBps
    ) private pure returns (uint256 effectiveAmount) {
        if (
            multBps <= BPS_DENOMINATOR || prevBurn >= DECIMATOR_MULTIPLIER_CAP
        ) {
            return baseAmount;
        }

        uint256 remaining = DECIMATOR_MULTIPLIER_CAP - prevBurn;
        uint256 fullEffective = (baseAmount * multBps) / BPS_DENOMINATOR;
        if (fullEffective <= remaining) return fullEffective;

        uint256 maxMultBase = (remaining * BPS_DENOMINATOR) / multBps;
        uint256 multiplied = (maxMultBase * multBps) / BPS_DENOMINATOR;
        effectiveAmount = multiplied + (baseAmount - maxMultBase);
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

    /// @dev Calculate pro-rata claimable amount for a player's DecEntry.
    /// @param poolWei Total pool available for claims.
    /// @param totalBurn Total qualifying burn (denominator for pro-rata). Callers
    ///        guarantee nonzero: the round snapshot is only written with a nonzero
    ///        totalBurn, and the view path checks it explicitly.
    /// @param e Player's DecEntry storage reference.
    /// @param packedOffsets Packed winning subbuckets.
    /// @return amountWei Player's pro-rata share (0 if not winner).
    function _decClaimableFromEntry(
        uint256 poolWei,
        uint256 totalBurn,
        DecEntry storage e,
        uint64 packedOffsets
    ) private view returns (uint256 amountWei) {
        uint8 denom = e.bucket;
        uint8 sub = e.subBucket;
        uint192 entryBurn = e.burn;

        // No participation or zero burn
        if (denom == 0 || entryBurn == 0) return 0;

        // Check if player's subbucket matches winning subbucket
        uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, denom);
        if (sub != winningSub) return 0;

        // Pro-rata share: (pool × playerBurn) / totalBurn
        amountWei = (poolWei * uint256(entryBurn)) / totalBurn;
    }

    /// @dev Internal view helper for decClaimable.
    /// @param round DecClaimRound storage reference.
    /// @param player Address to check.
    /// @param lvl Level number.
    /// @return amountWei Claimable amount.
    /// @return winner True if player is a winner.
    function _decClaimable(
        DecClaimRound storage round,
        address player,
        uint24 lvl
    ) internal view returns (uint256 amountWei, bool winner) {
        uint256 totalBurn = uint256(round.totalBurn);
        if (totalBurn == 0) return (0, false);

        DecEntry storage e = decBurn[lvl][player];
        if (e.claimed != 0) return (0, false);

        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        amountWei = _decClaimableFromEntry(
            round.poolWei,
            totalBurn,
            e,
            packedOffsets
        );
        winner = amountWei != 0;
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
    /// @param bucket Denominator; always in [2,12] (FLIP's ActivityCurveLib.decBucket
    ///        and _terminalDecBucket both floor at >=2).
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
    function _awardDecimatorLootbox(
        address winner,
        uint256 amount,
        uint256 rngWord,
        uint16 evScore
    ) private {
        if (winner == address(0) || amount == 0) return;
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            // amount > 5 ether here, so fullHalfPasses = amount / 2.25 ether >= 2.
            uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
            uint256 remainder = amount % HALF_WHALE_PASS_PRICE;
            uint24 startLevel = level + 1;
            _applyWhalePassStats(winner, startLevel);
            _queueTicketRange(winner, startLevel, 100, uint32(fullHalfPasses), false);
            // Sub-half-pass remainder (< 2.25 ether, so always below the threshold):
            // falls through to direct-resolve as a futurePool-backed lootbox (like any
            // small decimator claim), staying in futurePrizePool where the caller put it
            // so it is never double-backed. Below 0.01 ETH it is too small to be worth a
            // box, so the dust simply stays in futurePrizePool as future-prize liquidity
            // (no credit).
            if (remainder < 0.01 ether) return;
            amount = remainder;
        }
        // Resolve lootbox via delegatecall to open module
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    winner,
                    amount,
                    rngWord,
                    evScore,
                    false
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

    /*+======================================================================+
      |                    TERMINAL DECIMATOR (DEATH BET)                    |
      +======================================================================+
      |  Burn for GAMEOVER (blocked within 7 days of death clock).           |
      |  Time multiplier rewards early                                       |
      |  conviction. 200k cap equalizes bankroll — timing differentiates.   |
      +======================================================================+*/

    // -------------------------------------------------------------------------
    // Terminal Decimator Events
    // -------------------------------------------------------------------------

    event TerminalDecBurnRecorded(
        address indexed player,
        uint24 indexed lvl,
        uint8 bucket,
        uint8 subBucket,
        uint256 effectiveAmount,
        uint256 weightedAmount,
        uint256 timeMultBps
    );

    /// @notice Emitted when a player claims the terminal decimator jackpot.
    /// @param player The claimer.
    /// @param lvl Terminal decimator level.
    /// @param amountWei Payout credited as ETH claimable.
    event TerminalDecimatorClaimed(
        address indexed player,
        uint24 indexed lvl,
        uint256 amountWei
    );

    /// @notice Emitted when a final-day streak boost scales (and possibly promotes)
    ///         a player's terminal decimator entry.
    /// @param player The boosted player.
    /// @param lvl Terminal decimator level.
    /// @param oldBucket Bucket before the boost.
    /// @param newBucket Bucket after the boost (lower = better; equal if no promotion).
    /// @param newWeightedBurn The post-boost weighted burn (saturated at uint88 max).
    event TerminalDecBoosted(
        address indexed player,
        uint24 indexed lvl,
        uint8 oldBucket,
        uint8 newBucket,
        uint256 newWeightedBurn
    );

    // -------------------------------------------------------------------------
    // Terminal Decimator Errors
    // -------------------------------------------------------------------------

    error TerminalDecNotActive();
    error TerminalDecNotWinner();
    error TerminalDecDeadlinePassed();
    error TerminalDecNotBoostable();
    error TerminalDecAlreadyBoosted();

    // -------------------------------------------------------------------------
    // Terminal Decimator Constants
    // -------------------------------------------------------------------------

    uint32 private constant TERMINAL_DEC_IDLE_TIMEOUT_DAYS = 365;
    uint32 private constant TERMINAL_DEC_DEATH_CLOCK_DAYS = 120;

    // -------------------------------------------------------------------------
    // Terminal Decimator Burn Tracking
    // -------------------------------------------------------------------------

    /// @dev Minimum bucket (floor) for terminal decimator (lvl 100 rules).
    uint8 private constant TERMINAL_DEC_MIN_BUCKET = 2;

    /// @notice Record a terminal decimator burn for GAMEOVER eligibility.
    /// @dev Called by coin contract. Bucket and multiplier computed internally
    ///      from player activity score (lvl 100 rules, min bucket 2).
    ///      Time multiplier computed from days remaining on death clock.
    ///      Burns blocked when <= 7 days remain (7-day cooldown before termination).
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param baseAmount Burn amount before multiplier.
    function recordTerminalDecBurn(
        address player,
        uint24 lvl,
        uint256 baseAmount
    ) external {
        if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();

        uint256 daysRemaining = _terminalDecDaysRemaining();
        if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();

        // Compute bucket and multiplier from activity score (self-call; runs via delegatecall so address(this) == game)
        uint256 bonusPoints = IDegenerusGame(address(this)).playerActivityScore(
            player
        );
        uint8 bucket = _terminalDecBucket(bonusPoints);
        uint256 multBps = ActivityCurveLib.decMultBps(bonusPoints);

        TerminalDecEntry storage e = terminalDecEntries[player];

        // Lazy reset: if entry is from a previous level, zero it out in a single
        // packed-slot write (boost is one-time PER LEVEL; cleared with the rest).
        if (e.burnLevel != uint48(lvl)) {
            terminalDecEntries[player] = TerminalDecEntry({
                totalBurn: 0,
                weightedBurn: 0,
                bucket: 0,
                subBucket: 0,
                burnLevel: uint48(lvl),
                boosted: false
            });
        }

        // First burn this level: set bucket and subbucket
        uint8 entryBucket = e.bucket;
        uint8 entrySub;
        if (entryBucket == 0) {
            entryBucket = bucket;
            entrySub = _decSubbucketFor(player, lvl, bucket);
            e.bucket = entryBucket;
            e.subBucket = entrySub;
        } else {
            entrySub = e.subBucket;
        }

        // Apply activity multiplier and cap; nonzero since the coin enforces a
        // 1,000 FLIP minimum and at the cap the extra burn still counts at 1x.
        uint256 effectiveAmount = _decEffectiveAmount(
            uint256(e.totalBurn),
            baseAmount,
            multBps
        );

        // Update pre-time-multiplier total (for cap enforcement)
        uint256 newTotal = uint256(e.totalBurn) + effectiveAmount;
        if (newTotal > type(uint80).max) newTotal = type(uint80).max;
        e.totalBurn = uint80(newTotal);

        // Apply time multiplier
        uint256 timeMultBps = _terminalDecMultiplierBps(daysRemaining);
        uint256 weightedAmount = (effectiveAmount * timeMultBps) /
            BPS_DENOMINATOR;

        // Update post-time-multiplier total (for claim share)
        uint256 newWeighted = uint256(e.weightedBurn) + weightedAmount;
        if (newWeighted > type(uint88).max) newWeighted = type(uint88).max;
        e.weightedBurn = uint88(newWeighted);

        // Update bucket aggregate (key includes lvl, so old-level entries are naturally stale)
        bytes32 bucketKey = keccak256(abi.encode(lvl, entryBucket, entrySub));
        terminalDecBucketBurnTotal[bucketKey] += weightedAmount;

        emit TerminalDecBurnRecorded(
            player,
            lvl,
            entryBucket,
            entrySub,
            effectiveAmount,
            weightedAmount,
            timeMultBps
        );
    }

    /// @notice Final-day streak boost: scales an existing terminal decimator
    ///         entry by the player's effective quest streak and, if the live
    ///         activity score now qualifies a better (lower) bucket, promotes it.
    /// @dev Weight-only — the ETH/FLIP payout path is untouched. Gated by
    ///      `!_livenessTriggered()` (the death-clock predicate is day-constant),
    ///      so the boost and any promotion provably commit BEFORE the game-over
    ///      resolution word exists: the placement is deterministic from the
    ///      committed burn and a view-read streak, never from draw knowledge.
    ///      Admissible only on the deadline day itself (daysRemaining == 0,
    ///      still pre-liveness) — forcing the streak to be kept alive to the end.
    ///      On promotion the subBucket is re-derived for the new denominator and
    ///      the aggregate is re-keyed (remove from old key, add to new) so total
    ///      weight in `terminalDecBucketBurnTotal` is conserved. One-time per
    ///      level via the `boosted` bit.
    function boostTerminalDecimator() external {
        if (_livenessTriggered()) revert TerminalDecNotActive();
        if (_terminalDecDaysRemaining() != 0) revert TerminalDecNotBoostable();

        address player = msg.sender;
        uint24 lvl = level;

        TerminalDecEntry storage e = terminalDecEntries[player];
        // Scale committed weight — never buy an entry. A stale (prior-level) or
        // empty entry has no weight to boost.
        if (e.burnLevel != uint48(lvl) || e.bucket == 0) {
            revert TerminalDecNotBoostable();
        }
        if (e.boosted) revert TerminalDecAlreadyBoosted();

        uint256 effectiveStreak = uint256(_effectiveQuestStreak(player));
        if (effectiveStreak == 0) revert TerminalDecNotBoostable();

        uint256 oldWeighted = uint256(e.weightedBurn);
        if (oldWeighted == 0) revert TerminalDecNotBoostable();

        // Scale weight by the streak factor, saturating at uint88 max.
        uint256 factorBps = _terminalDecBoostFactorBps(effectiveStreak);
        uint256 newWeighted = (oldWeighted * factorBps) / BPS_DENOMINATOR;
        if (newWeighted > type(uint88).max) newWeighted = type(uint88).max;

        uint8 oldBucket = e.bucket;
        uint8 oldSub = e.subBucket;

        // Recompute the bucket from the LIVE activity score (which now reflects
        // the kept-alive streak). Promote only if strictly better (lower).
        uint256 bonusPoints = IDegenerusGame(address(this)).playerActivityScore(
            player
        );
        uint8 liveBucket = _terminalDecBucket(bonusPoints);

        uint8 newBucket = oldBucket;
        uint8 newSub = oldSub;
        bool promoted = liveBucket < oldBucket;
        if (promoted) {
            newBucket = liveBucket;
            newSub = _decSubbucketFor(player, lvl, liveBucket);
            e.bucket = newBucket;
            e.subBucket = newSub;
        }

        e.weightedBurn = uint88(newWeighted);
        e.boosted = true;

        // Re-key the aggregate so total weight is conserved. On a promotion the
        // pre-boost weight moves off the old key and the post-boost weight lands
        // on the new key; without one the single key takes the net boost delta
        // (newWeighted >= oldWeighted: factorBps >= 1x and the uint88 saturation
        // clamp is itself >= the uint88 oldWeighted).
        bytes32 oldKey = keccak256(abi.encode(lvl, oldBucket, oldSub));
        if (promoted) {
            bytes32 newKey = keccak256(abi.encode(lvl, newBucket, newSub));
            terminalDecBucketBurnTotal[oldKey] -= oldWeighted;
            terminalDecBucketBurnTotal[newKey] += newWeighted;
        } else {
            terminalDecBucketBurnTotal[oldKey] += newWeighted - oldWeighted;
        }

        emit TerminalDecBoosted(player, lvl, oldBucket, newBucket, newWeighted);
    }

    /// @dev Streak → weight multiplier in bps (1x floor at streak 0, 4x at 10,
    ///      20x at 100, capped at 20x). The incoming streak is clamped to 100 here.
    function _terminalDecBoostFactorBps(
        uint256 streak
    ) private pure returns (uint256) {
        if (streak > 100) streak = 100;
        uint256 factorBps;
        if (streak <= 10) {
            factorBps = BPS_DENOMINATOR + streak * 3000;
        } else {
            factorBps = 40000 + (streak - 10) * 1778;
        }
        if (factorBps > 200000) factorBps = 200000;
        return factorBps;
    }

    // -------------------------------------------------------------------------
    // Terminal Decimator Resolution (GAMEOVER only)
    // -------------------------------------------------------------------------

    /// @notice Resolve terminal decimator at GAMEOVER.
    /// @dev Selects winning subbuckets, snapshots claim round.
    ///      Returns poolWei if no qualifying burns.
    /// @param poolWei Total ETH allocated (10% of remaining).
    /// @param lvl Level at GAMEOVER.
    /// @param rngWord VRF-derived randomness.
    /// @return returnAmountWei Amount to return (non-zero if no winners).
    function runTerminalDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();

        // Prevent double-resolution
        if (lastTerminalDecClaimRound.lvl == lvl) {
            return poolWei;
        }

        uint256 totalWinnerBurn;
        uint64 packedOffsets;

        // Select winning subbucket for each denominator (2-12)
        uint256 decSeed = rngWord;
        for (uint8 denom = 2; denom <= DECIMATOR_MAX_DENOM; ) {
            uint8 winningSub = _decWinningSubbucket(decSeed, denom);
            packedOffsets = _packDecWinningSubbucket(
                packedOffsets,
                denom,
                winningSub
            );

            bytes32 bucketKey = keccak256(abi.encode(lvl, denom, winningSub));
            uint256 subTotal = terminalDecBucketBurnTotal[bucketKey];
            if (subTotal != 0) {
                totalWinnerBurn += subTotal;
            }
            unchecked {
                ++denom;
            }
        }

        if (totalWinnerBurn == 0) {
            return poolWei;
        }

        // Store packed offsets at lvl + 1, not lvl, so they never alias the regular decimator
        // round's decBucketOffsetPacked[lvl]: `level` lags the active purchase level by one, so a
        // gameover at this level can coexist with a live, unclaimed regular round keyed at lvl, and
        // sharing the key would let this terminal write corrupt that round's winning subbuckets.
        // lvl + 1 is safe — that level's regular round can only resolve once `level` reaches it
        // (precluded by this gameover), and no regular round resolves after gameover, so the slot is
        // exclusively this terminal round's. The terminal claim path reads the same lvl + 1 slot.
        decBucketOffsetPacked[lvl + 1] = packedOffsets;

        // Snapshot claim round (single slot — no rngWord needed for terminal claims)
        lastTerminalDecClaimRound.lvl = lvl;
        lastTerminalDecClaimRound.poolWei = uint96(poolWei);
        lastTerminalDecClaimRound.totalBurn = uint128(totalWinnerBurn);

        return 0;
    }

    // -------------------------------------------------------------------------
    // Terminal Decimator Claims
    // -------------------------------------------------------------------------

    /// @notice Claim terminal decimator jackpot for caller.
    /// @dev Only callable post-GAMEOVER. Level is read from the resolved claim round.
    ///      Self-claim only: the payout is a pure claimable credit with no lootbox leg,
    ///      so there is no resolution-timing edge to neutralize here.
    function claimTerminalDecimatorJackpot() external {
        (uint256 amountWei, uint24 lvl) = _consumeTerminalDecClaim(msg.sender);

        _creditClaimable(msg.sender, amountWei);
        emit TerminalDecimatorClaimed(msg.sender, lvl, amountWei);
    }

    /// @notice Check if player can claim terminal decimator jackpot.
    /// @param player Address to check.
    /// @return amountWei Claimable amount.
    /// @return winner True if player won.
    function terminalDecClaimable(
        address player
    ) external view returns (uint256 amountWei, bool winner) {
        uint24 lvl = lastTerminalDecClaimRound.lvl;
        if (lvl == 0) return (0, false);

        TerminalDecEntry storage e = terminalDecEntries[player];
        if (
            e.burnLevel != uint48(lvl) || e.weightedBurn == 0 || e.bucket == 0
        ) {
            return (0, false);
        }

        // Terminal offset lives at lvl + 1 (see runTerminalDecimatorJackpot) to avoid aliasing the
        // regular round's decBucketOffsetPacked[lvl].
        uint64 packedOffsets = decBucketOffsetPacked[lvl + 1];
        uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, e.bucket);
        if (e.subBucket != winningSub) return (0, false);

        uint256 totalBurn = uint256(lastTerminalDecClaimRound.totalBurn);
        if (totalBurn == 0) return (0, false);

        amountWei =
            (uint256(lastTerminalDecClaimRound.poolWei) *
                uint256(e.weightedBurn)) /
            totalBurn;
        winner = amountWei != 0;
    }

    /// @dev Validate and consume terminal dec claim.
    /// @return amountWei Pro-rata payout amount.
    /// @return lvl The resolved terminal decimator level (for the claim event).
    function _consumeTerminalDecClaim(
        address player
    ) private returns (uint256 amountWei, uint24 lvl) {
        lvl = lastTerminalDecClaimRound.lvl;
        if (lvl == 0) revert TerminalDecNotActive();

        TerminalDecEntry storage e = terminalDecEntries[player];
        if (e.burnLevel != uint48(lvl) || e.weightedBurn == 0)
            revert TerminalDecNotWinner();

        // Use totalBurn == 0 as claimed flag (set to 0 after claiming)
        uint88 weight = e.weightedBurn;

        // Terminal offset lives at lvl + 1 (see runTerminalDecimatorJackpot) to avoid aliasing the
        // regular round's decBucketOffsetPacked[lvl].
        uint64 packedOffsets = decBucketOffsetPacked[lvl + 1];
        uint8 winningSub = _unpackDecWinningSubbucket(packedOffsets, e.bucket);
        if (e.subBucket != winningSub) revert TerminalDecNotWinner();

        uint256 totalBurn = uint256(lastTerminalDecClaimRound.totalBurn);
        if (totalBurn == 0) revert TerminalDecNotWinner();

        amountWei =
            (uint256(lastTerminalDecClaimRound.poolWei) * uint256(weight)) /
            totalBurn;
        if (amountWei == 0) revert TerminalDecNotWinner();

        // Mark claimed by zeroing weightedBurn
        e.weightedBurn = 0;
    }

    // -------------------------------------------------------------------------
    // Terminal Decimator Helpers
    // -------------------------------------------------------------------------

    /// @dev Time multiplier based on days remaining on death clock.
    ///      > 10 days: linear 20x (day 120) to 1x (day 10)
    ///      7-10 days: flat 1x
    ///      <= 7 days: blocked by caller
    function _terminalDecMultiplierBps(
        uint256 daysRemaining
    ) private pure returns (uint256) {
        if (daysRemaining <= 10) return 10000;
        // Linear: 1x at day 10, 20x at day 120 → slope = 190000 / 110
        return 10000 + ((daysRemaining - 10) * 190000) / 110;
    }

    /// @dev Terminal decimator bucket from activity score (floor 2; lvl 100 rules).
    function _terminalDecBucket(uint256 bonusPoints) private pure returns (uint8) {
        return ActivityCurveLib.decBucket(bonusPoints, TERMINAL_DEC_MIN_BUCKET);
    }

    /// @dev Calculate days remaining on death clock using day-index arithmetic. Returns 0 if expired.
    function _terminalDecDaysRemaining() private view returns (uint256) {
        uint24 currentDay = _simulatedDayIndex();
        uint24 psd = purchaseStartDay;
        uint24 deadlineDay = psd +
            uint24(
                level == 0
                    ? TERMINAL_DEC_IDLE_TIMEOUT_DAYS
                    : TERMINAL_DEC_DEATH_CLOCK_DAYS
            );
        if (currentDay >= deadlineDay) return 0;
        return deadlineDay - currentDay;
    }
}
