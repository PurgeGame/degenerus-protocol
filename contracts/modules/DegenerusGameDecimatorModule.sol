// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

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
        if (reason.length == 0) revert E();
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
        if (m.bucket == 0) {
            m.bucket = bucket;
            m.subBucket = _decSubbucketFor(player, lvl, bucket);
        } else if (bucket != 0 && bucket < m.bucket) {
            // Better bucket selected: migrate burn to new subbucket.
            _decRemoveSubbucket(lvl, m.bucket, m.subBucket, prevBurn);
            m.bucket = bucket;
            m.subBucket = _decSubbucketFor(player, lvl, bucket);
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
        e.burn = newBurn;
        e.bucket = m.bucket;
        e.subBucket = m.subBucket;

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
        if (decClaimRounds[lvl].poolWei != 0) {
            return poolWei;
        }

        uint256 totalBurn;
        uint64 packedOffsets;

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
            uint256 subTotal = decBucketBurnTotal[lvl][denom][winningSub];
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
        decClaimRounds[lvl].poolWei = poolWei;
        decClaimRounds[lvl].totalBurn = uint232(totalBurn);
        decClaimRounds[lvl].rngWord = rngWord;

        return 0; // All funds held for claims
    }

    /*+======================================================================+
      |                      DECIMATOR CLAIM FUNCTIONS                       |
      +======================================================================+*/

    /// @dev Internal claim validation and marking.
    ///      Validates eligibility and marks as claimed if successful.
    /// @param player Address claiming the jackpot.
    /// @param lvl Level to claim from.
    /// @return amountWei Pro-rata payout amount.
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    /// @custom:reverts DecAlreadyClaimed When player has already claimed for this level.
    /// @custom:reverts DecNotWinner When player's subbucket did not win.
    function _consumeDecClaim(
        address player,
        uint24 lvl
    ) internal returns (uint256 amountWei) {
        DecClaimRound storage round = decClaimRounds[lvl];
        if (round.poolWei == 0) revert DecClaimInactive();

        DecEntry storage e = decBurn[lvl][player];
        if (e.claimed != 0) revert DecAlreadyClaimed();

        // Calculate pro-rata share if player's subbucket won
        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        uint256 totalBurn = uint256(round.totalBurn);
        amountWei = _decClaimableFromEntry(
            round.poolWei,
            totalBurn,
            e,
            packedOffsets
        );
        if (amountWei == 0) revert DecNotWinner();

        // Mark as claimed to prevent double-claiming
        e.claimed = 1;
    }

    /// @notice Consume Decimator claim on behalf of player.
    /// @dev Used for game-initiated claims.
    /// @param player Address to claim for.
    /// @param lvl Level to claim from.
    /// @return amountWei Pro-rata payout amount.
    /// @custom:access Restricted to game contract.
    function consumeDecClaim(
        address player,
        uint24 lvl
    ) external returns (uint256 amountWei) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        return _consumeDecClaim(player, lvl);
    }

    /// @notice Claim Decimator jackpot for caller.
    /// @dev Public function for players to claim their own jackpot.
    ///      Credits payout to player's claimable balance.
    /// @param lvl Level to claim from.
    /// @custom:reverts DecClaimInactive When no decimator snapshot exists for this level.
    /// @custom:reverts DecAlreadyClaimed When caller has already claimed for this level.
    /// @custom:reverts DecNotWinner When caller's subbucket did not win.
    function claimDecimatorJackpot(uint24 lvl) external {
        // Block claims while prize pools are frozen (active during VRF window).
        // This path writes to futurePrizePool (lootbox portion) — allowing it
        // during freeze would corrupt the live pool that advanceGame operates on.
        if (prizePoolFrozen) revert E();

        uint256 amountWei = _consumeDecClaim(msg.sender, lvl);

        if (gameOver) {
            _creditClaimable(msg.sender, amountWei);
            emit DecimatorClaimed(msg.sender, lvl, amountWei, amountWei, 0);
            return;
        }

        uint256 lootboxPortion = _creditDecJackpotClaimCore(
            msg.sender,
            amountWei,
            decClaimRounds[lvl].rngWord
        );
        if (lootboxPortion != 0) {
            _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);
        }
        emit DecimatorClaimed(
            msg.sender,
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
        uint256 rngWord
    ) private returns (uint256 lootboxPortion) {
        // Split 50/50: half ETH, half lootbox tickets
        uint256 ethPortion = amount >> 1;
        lootboxPortion = amount - ethPortion;

        _creditClaimable(account, ethPortion);

        // Lootbox portion is no longer claimable ETH; remove from reserved pool.
        claimablePool -= uint128(lootboxPortion); // Safe: lootboxPortion is a fraction of claimablePool, fits uint128
        _awardDecimatorLootbox(account, lootboxPortion, rngWord);
    }

    /// @dev Apply multiplier until the cap is reached; extra amount is counted at 1x.
    /// @param prevBurn Previous accumulated burn amount.
    /// @param baseAmount New burn amount before multiplier.
    /// @param multBps Multiplier in basis points.
    /// @return effectiveAmount The effective burn amount after applying capped multiplier.
    function _decEffectiveAmount(
        uint256 prevBurn,
        uint256 baseAmount,
        uint256 multBps
    ) private pure returns (uint256 effectiveAmount) {
        if (baseAmount == 0) return 0;
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

    /// @dev Unpack a winning subbucket from the packed uint64.
    /// @param packed Packed winning subbuckets.
    /// @param denom Denominator to unpack (2-12).
    /// @return Winning subbucket for this denom.
    function _unpackDecWinningSubbucket(
        uint64 packed,
        uint8 denom
    ) private pure returns (uint8) {
        if (denom < 2) return 0;
        uint8 shift = (denom - 2) << 2;
        return uint8((packed >> shift) & 0xF);
    }

    /// @dev Calculate pro-rata claimable amount for a player's DecEntry.
    /// @param poolWei Total pool available for claims.
    /// @param totalBurn Total qualifying burn (denominator for pro-rata).
    /// @param e Player's DecEntry storage reference.
    /// @param packedOffsets Packed winning subbuckets.
    /// @return amountWei Player's pro-rata share (0 if not winner).
    function _decClaimableFromEntry(
        uint256 poolWei,
        uint256 totalBurn,
        DecEntry storage e,
        uint64 packedOffsets
    ) private view returns (uint256 amountWei) {
        if (totalBurn == 0) return 0;

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

    /// @dev Update aggregated burn totals for a subbucket.
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
        if (delta == 0 || denom == 0) return;
        decBucketBurnTotal[lvl][denom][sub] += uint256(delta);
    }

    /// @dev Remove aggregated burn totals for a subbucket.
    /// @param lvl Level number.
    /// @param denom Denominator (bucket).
    /// @param sub Subbucket index.
    /// @param delta Burn amount to remove.
    function _decRemoveSubbucket(
        uint24 lvl,
        uint8 denom,
        uint8 sub,
        uint192 delta
    ) internal {
        if (delta == 0 || denom == 0) return;
        uint256 slotTotal = decBucketBurnTotal[lvl][denom][sub];
        if (slotTotal < uint256(delta)) revert E();
        decBucketBurnTotal[lvl][denom][sub] = slotTotal - uint256(delta);
    }

    /// @dev Deterministically assign subbucket for a player.
    ///      Hash of (player, lvl, bucket) ensures consistent assignment.
    /// @param player Address.
    /// @param lvl Level number.
    /// @param bucket Denominator.
    /// @return Subbucket index (0 to bucket-1).
    function _decSubbucketFor(
        address player,
        uint24 lvl,
        uint8 bucket
    ) private pure returns (uint8) {
        if (bucket == 0) return 0;
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
        uint256 rngWord
    ) private {
        if (winner == address(0) || amount == 0) return;
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
            uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);
            if (fullHalfPasses != 0) {
                uint24 startLevel = level + 1;
                _applyWhalePassStats(winner, startLevel);
                _queueTicketRange(winner, startLevel, 100, uint32(fullHalfPasses), false);
            }
            if (remainder != 0) {
                _creditClaimable(winner, remainder);
            }
            return;
        }
        // Resolve lootbox via delegatecall to open module
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    winner,
                    amount,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
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

    // -------------------------------------------------------------------------
    // Terminal Decimator Errors
    // -------------------------------------------------------------------------

    error TerminalDecCapped();
    error TerminalDecNotActive();
    error TerminalDecNotWinner();
    error TerminalDecDeadlinePassed();

    // -------------------------------------------------------------------------
    // Terminal Decimator Constants
    // -------------------------------------------------------------------------

    uint32 private constant TERMINAL_DEC_IDLE_TIMEOUT_DAYS = 365;
    uint32 private constant TERMINAL_DEC_DEATH_CLOCK_DAYS = 120;

    // -------------------------------------------------------------------------
    // Terminal Decimator Burn Tracking
    // -------------------------------------------------------------------------

    /// @dev Bucket base and min for terminal decimator (lvl 100 rules).
    uint8 private constant TERMINAL_DEC_BUCKET_BASE = 12;
    uint8 private constant TERMINAL_DEC_MIN_BUCKET = 2;
    uint16 private constant TERMINAL_DEC_ACTIVITY_CAP_BPS = 23_500;

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
        uint256 bonusBps = IDegenerusGame(address(this)).playerActivityScore(
            player
        );
        if (bonusBps > TERMINAL_DEC_ACTIVITY_CAP_BPS)
            bonusBps = TERMINAL_DEC_ACTIVITY_CAP_BPS;
        uint8 bucket = _terminalDecBucket(bonusBps);
        uint256 multBps = bonusBps == 0
            ? BPS_DENOMINATOR
            : BPS_DENOMINATOR + (bonusBps / 3);

        TerminalDecEntry storage e = terminalDecEntries[player];

        // Lazy reset: if entry is from a previous level, zero it out
        if (e.burnLevel != uint48(lvl)) {
            e.totalBurn = 0;
            e.weightedBurn = 0;
            e.bucket = 0;
            e.subBucket = 0;
            e.burnLevel = uint48(lvl);
        }

        // First burn this level: set bucket and subbucket
        if (e.bucket == 0) {
            e.bucket = bucket;
            e.subBucket = _decSubbucketFor(player, lvl, bucket);
        }

        // Apply activity multiplier and cap
        uint256 effectiveAmount = _decEffectiveAmount(
            uint256(e.totalBurn),
            baseAmount,
            multBps
        );
        if (effectiveAmount == 0) revert TerminalDecCapped();

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
        bytes32 bucketKey = keccak256(abi.encode(lvl, e.bucket, e.subBucket));
        terminalDecBucketBurnTotal[bucketKey] += weightedAmount;

        emit TerminalDecBurnRecorded(
            player,
            lvl,
            e.bucket,
            e.subBucket,
            effectiveAmount,
            weightedAmount,
            timeMultBps
        );
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

        // Store packed offsets for claim validation
        decBucketOffsetPacked[lvl] = packedOffsets;

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
    function claimTerminalDecimatorJackpot() external {
        uint256 amountWei = _consumeTerminalDecClaim(msg.sender);

        _creditClaimable(msg.sender, amountWei);
        emit TerminalDecimatorClaimed(
            msg.sender,
            lastTerminalDecClaimRound.lvl,
            amountWei
        );
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

        uint64 packedOffsets = decBucketOffsetPacked[lvl];
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
    function _consumeTerminalDecClaim(
        address player
    ) private returns (uint256 amountWei) {
        uint24 lvl = lastTerminalDecClaimRound.lvl;
        if (lvl == 0) revert TerminalDecNotActive();

        TerminalDecEntry storage e = terminalDecEntries[player];
        if (e.burnLevel != uint48(lvl) || e.weightedBurn == 0)
            revert TerminalDecNotWinner();

        // Use totalBurn == 0 as claimed flag (set to 0 after claiming)
        uint88 weight = e.weightedBurn;

        uint64 packedOffsets = decBucketOffsetPacked[lvl];
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

    /// @dev Compute terminal decimator bucket from activity score (lvl 100 rules).
    function _terminalDecBucket(uint256 bonusBps) private pure returns (uint8) {
        if (bonusBps == 0) return TERMINAL_DEC_BUCKET_BASE;
        uint256 range = uint256(TERMINAL_DEC_BUCKET_BASE) -
            uint256(TERMINAL_DEC_MIN_BUCKET);
        uint256 reduction = (range *
            bonusBps +
            (TERMINAL_DEC_ACTIVITY_CAP_BPS / 2)) /
            TERMINAL_DEC_ACTIVITY_CAP_BPS;
        uint256 b = uint256(TERMINAL_DEC_BUCKET_BASE) - reduction;
        if (b < TERMINAL_DEC_MIN_BUCKET) b = TERMINAL_DEC_MIN_BUCKET;
        return uint8(b);
    }

    /// @dev Calculate days remaining on death clock using day-index arithmetic. Returns 0 if expired.
    function _terminalDecDaysRemaining() private view returns (uint256) {
        uint32 currentDay = _simulatedDayIndex();
        uint32 psd = purchaseStartDay;
        uint256 deadlineDay = uint256(psd) +
            (
                level == 0
                    ? uint256(TERMINAL_DEC_IDLE_TIMEOUT_DAYS)
                    : TERMINAL_DEC_DEATH_CLOCK_DAYS
            );
        if (currentDay >= deadlineDay) return 0;
        return deadlineDay - currentDay;
    }
}
