// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.26;

import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
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

    /// @notice Emitted when auto-rebuy converts winnings to tickets.
    /// @param player Player whose winnings were converted.
    /// @param targetLevel Level for which tickets were purchased.
    /// @param ticketsAwarded Number of tickets credited (including bonus).
    /// @param ethSpent Amount of ETH spent on tickets.
    /// @param remainder Amount returned to claimableWinnings (reserved + dust).
    event AutoRebuyProcessed(
        address indexed player,
        uint24 targetLevel,
        uint32 ticketsAwarded,
        uint256 ethSpent,
        uint256 remainder
    );

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

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for invalid parameters or unauthorized access.
    error E();

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

    /// @dev Auto-rebuy bonus in basis points (130% = 1.3x tickets).
    uint16 private constant AUTO_REBUY_BONUS_BPS = 13_000;

    /// @dev afKing mode auto-rebuy bonus in basis points (145% = 1.45x tickets).
    uint16 private constant AFKING_AUTO_REBUY_BONUS_BPS = 14_500;

    /// @dev Basis points denominator (10000 = 100%).
    uint16 private constant BPS_DENOMINATOR = 10_000;

    /// @dev Multiplier cap for Decimator burns (200 mints worth).
    uint256 private constant DECIMATOR_MULTIPLIER_CAP = 200 * PRICE_COIN_UNIT;

    /// @dev Maximum denominator for Decimator buckets (2-12 inclusive).
    uint8 private constant DECIMATOR_MAX_DENOM = 12;

    // -------------------------------------------------------------------------
    // External Entry Points (delegatecall targets)
    // -------------------------------------------------------------------------

    /// @notice Credits decimator jackpot claims to multiple accounts in a batch.
    /// @dev Access: Only callable by ContractAddresses.JACKPOTS contract.
    ///      During GAMEOVER state, credits 100% as ETH.
    ///      During normal play, splits 50/50 between ETH and lootbox tickets.
    ///      Uses VRF randomness from jackpot resolution for lootbox derivation.
    /// @param accounts Array of player addresses to credit.
    /// @param amounts Array of corresponding wei amounts (total before split).
    /// @param rngWord VRF random word from jackpot resolution.
    /// @custom:reverts E When caller is not JACKPOTS contract.
    /// @custom:reverts E When accounts and amounts arrays have different lengths.
    function creditDecJackpotClaimBatch(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 rngWord
    ) external {
        if (msg.sender != ContractAddresses.JACKPOTS) revert E();
        uint256 len = accounts.length;
        if (len != amounts.length) revert E();

        if (gameOver) {
            for (uint256 i; i < len; ) {
                uint256 amt = amounts[i];
                address account = accounts[i];
                if (amt != 0 && account != address(0)) {
                    _addClaimableEth(account, amt, rngWord);
                }
                unchecked {
                    ++i;
                }
            }
            return;
        }

        uint256 totalLootbox;

        for (uint256 i; i < len; ) {
            uint256 amt = amounts[i];
            address account = accounts[i];
            if (amt != 0 && account != address(0)) {
                uint256 lootboxPortion = _creditDecJackpotClaimCore(
                    account,
                    amt,
                    rngWord
                );
                if (lootboxPortion != 0) {
                    unchecked {
                        totalLootbox += lootboxPortion;
                    }
                }
            }
            unchecked {
                ++i;
            }
        }

        // Add all lootbox ETH to futurePrizePool once at the end
        if (totalLootbox != 0) {
            futurePrizePool += totalLootbox;
        }
    }

    /// @notice Credits a single decimator jackpot claim to an account.
    /// @dev Access: Only callable by ContractAddresses.JACKPOTS contract.
    ///      During GAMEOVER state, credits 100% as ETH.
    ///      During normal play, splits 50/50 between ETH and lootbox tickets.
    ///      Uses VRF randomness from jackpot resolution for lootbox derivation.
    /// @param account Player address to credit.
    /// @param amount Wei amount to credit (total before split).
    /// @param rngWord VRF random word from jackpot resolution.
    /// @custom:reverts E When caller is not JACKPOTS contract.
    function creditDecJackpotClaim(
        address account,
        uint256 amount,
        uint256 rngWord
    ) external {
        if (msg.sender != ContractAddresses.JACKPOTS) revert E();
        if (amount == 0 || account == address(0)) return;

        if (gameOver) {
            _addClaimableEth(account, amount, rngWord);
            return;
        }

        uint256 lootboxPortion = _creditDecJackpotClaimCore(
            account,
            amount,
            rngWord
        );
        if (lootboxPortion != 0) {
            futurePrizePool += lootboxPortion;
        }
    }

    // -------------------------------------------------------------------------
    // Decimator Burn Tracking
    // -------------------------------------------------------------------------

    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @dev Called by coin contract on every Decimator burn.
    ///      First burn sets player's bucket (denominator) choice.
    ///      Subbucket is deterministically assigned from hash(player, lvl, bucket).
    ///      Subsequent burns accumulate in that bucket unless a strictly better
    ///      bucket (lower denominator) is provided. On improvement, previous burn
    ///      is removed from old aggregate, player burn resets, and entry migrates.
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

        // Prevent double-snapshotting: return pool if this level already active
        if (lastDecClaimRound.lvl == lvl) {
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

        // Safety: If totalBurn exceeds uint232, return pool (economically impossible but defensive)
        if (totalBurn > type(uint232).max) {
            return poolWei;
        }

        // Store packed winning subbuckets for claim validation
        decBucketOffsetPacked[lvl] = packedOffsets;

        // Snapshot last claim round (overwrites previous - old claims expire)
        lastDecClaimRound.lvl = lvl;
        lastDecClaimRound.poolWei = poolWei;
        lastDecClaimRound.totalBurn = uint232(totalBurn);
        lastDecClaimRound.rngWord = rngWord;

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
    /// @custom:reverts DecClaimInactive When lvl is not the current active decimator round.
    /// @custom:reverts DecAlreadyClaimed When player has already claimed for this level.
    /// @custom:reverts DecNotWinner When player's subbucket did not win.
    function _consumeDecClaim(
        address player,
        uint24 lvl
    ) internal returns (uint256 amountWei) {
        // Only allow claims for the last decimator (claims expire when next decimator runs)
        if (lastDecClaimRound.lvl != lvl) revert DecClaimInactive();

        DecEntry storage e = decBurn[lvl][player];
        if (e.claimed != 0) revert DecAlreadyClaimed();

        // Calculate pro-rata share if player's subbucket won
        uint64 packedOffsets = decBucketOffsetPacked[lvl];
        uint256 totalBurn = uint256(lastDecClaimRound.totalBurn);
        amountWei = _decClaimableFromEntry(
            lastDecClaimRound.poolWei,
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
    ///      Claims expire when next decimator runs.
    /// @param lvl Level to claim from (must be the last decimator).
    /// @custom:reverts DecClaimInactive When lvl is not the current active decimator round.
    /// @custom:reverts DecAlreadyClaimed When caller has already claimed for this level.
    /// @custom:reverts DecNotWinner When caller's subbucket did not win.
    function claimDecimatorJackpot(uint24 lvl) external {
        uint256 amountWei = _consumeDecClaim(msg.sender, lvl);

        if (gameOver) {
            _addClaimableEth(msg.sender, amountWei, lastDecClaimRound.rngWord);
            return;
        }

        uint256 lootboxPortion = _creditDecJackpotClaimCore(
            msg.sender,
            amountWei,
            lastDecClaimRound.rngWord
        );
        if (lootboxPortion != 0) {
            futurePrizePool += lootboxPortion;
        }
    }

    /// @notice Check if player can claim Decimator jackpot for a level.
    /// @dev View function for UI to show claimable amounts.
    ///      Only returns non-zero for the last decimator (claims expire when next one runs).
    /// @param player Address to check.
    /// @param lvl Level to check (must be the last decimator).
    /// @return amountWei Claimable amount (0 if not winner, already claimed, or expired).
    /// @return winner True if player is a winner for this level.
    function decClaimable(
        address player,
        uint24 lvl
    ) external view returns (uint256 amountWei, bool winner) {
        // Only show claimable for the last decimator
        if (lastDecClaimRound.lvl != lvl) {
            return (0, false);
        }
        return _decClaimable(lastDecClaimRound, player, lvl);
    }

    /// @dev Processes auto-rebuy if enabled, converting ETH winnings to tickets.
    /// @param beneficiary The player to process.
    /// @param weiAmount The ETH amount to potentially convert.
    /// @param entropy RNG seed for level selection.
    /// @return handled True if auto-rebuy processed the funds.
    function _processAutoRebuy(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    ) private returns (bool handled) {
        AutoRebuyState memory state = autoRebuyState[beneficiary];
        if (!state.autoRebuyEnabled) return false;
        if (decimatorAutoRebuyDisabled[beneficiary]) return false;

        AutoRebuyCalc memory calc = _calcAutoRebuy(
            beneficiary,
            weiAmount,
            entropy,
            state,
            level,
            AUTO_REBUY_BONUS_BPS,
            AFKING_AUTO_REBUY_BONUS_BPS
        );
        if (!calc.hasTickets) {
            _creditClaimable(beneficiary, weiAmount);
            return true;
        }

        if (calc.toFuture) {
            futurePrizePool += calc.ethSpent;
        } else {
            nextPrizePool += calc.ethSpent;
        }
        _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount);

        if (calc.reserved != 0) {
            _creditClaimable(beneficiary, calc.reserved);
        }

        // Decimator pool was pre-reserved in claimablePool; deduct ticket conversion.
        claimablePool -= calc.ethSpent;

        emit AutoRebuyProcessed(
            beneficiary,
            calc.targetLevel,
            calc.ticketCount,
            calc.ethSpent,
            calc.reserved
        );
        return true;
    }

    /// @dev Credits ETH winnings to a player's claimable balance.
    /// @param beneficiary Player to credit.
    /// @param weiAmount Amount in wei to add.
    /// @param entropy RNG seed for auto-rebuy level selection.
    function _addClaimableEth(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    ) private {
        if (weiAmount == 0) return;
        if (_processAutoRebuy(beneficiary, weiAmount, entropy)) {
            return;
        }
        _creditClaimable(beneficiary, weiAmount);
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

        _addClaimableEth(account, ethPortion, rngWord);

        // Lootbox portion is no longer claimable ETH; remove from reserved pool.
        claimablePool -= lootboxPortion;
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
        if (denom == 0) return 0;
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
    /// @param round LastDecClaimRound storage reference.
    /// @param player Address to check.
    /// @param lvl Level number.
    /// @return amountWei Claimable amount.
    /// @return winner True if player is a winner.
    function _decClaimable(
        LastDecClaimRound storage round,
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
            _queueWhalePassClaimCore(winner, amount);
            return;
        }
        // Resolve lootbox via delegatecall to open module
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule
                        .resolveLootboxDirect
                        .selector,
                    winner,
                    amount,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

}
