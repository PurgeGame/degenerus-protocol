// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusTrophies} from "../interfaces/IDegenerusTrophies.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/**
 * @title DegenerusGameEndgameModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling endgame reward jackpots and exterminator payouts.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame during state 1 (setup),
 *      meaning all storage reads/writes operate on the game contract's storage.
 *
 * ## When Called
 *
 * After a level ends (timeout only), the game transitions to state 1 and calls
 * `finalizeEndgame()` to settle reward jackpots before starting the next level.
 * Exterminator payouts are handled during burn via `payExterminatorOnJackpot()`.
 *
 * ## Settlement Flow
 *
 * ```
 * payExterminatorOnJackpot()
 *     +- Mint exterminator trophy (winnings packed)
 *     +- Pay exterminator (20-40% of prize pool ETH + 2% of remaining exterminator pool)
 *
 * finalizeEndgame()
 *     +- Mint affiliate trophy for top affiliate (+ 1% of remaining affiliate pool)
 *     +- Run reward jackpots:
 *         +- BAF (every 10 levels): 10-25% of future pool
 *         +- Decimator (levels 5,15,25...85): 10% of future pool
 * ```
 *
 * ## Exterminator Share Calculation
 *
 * - "Big-ex" levels (14, 24, 34...): Fixed 40%
 * - All other levels: Random 20-40% (VRF-derived, 1% steps)
 *
 *
 */
contract DegenerusGameEndgameModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when ETH is credited to a player's claimable balance.
    /// @param player Winner address credited.
    /// @param amount ETH amount credited.
    event PlayerCredited(
        address indexed player,
        uint256 amount
    );

    /// @notice Emitted when auto-rebuy converts winnings to tickets.
    /// @param player Player who had auto-rebuy enabled.
    /// @param ethAmount ETH amount converted.
    /// @param ticketsAwarded Number of tickets awarded (includes auto-rebuy bonus).
    /// @param targetLevel Level for which tickets were awarded.
    event AutoRebuyExecuted(
        address indexed player,
        uint256 ethAmount,
        uint32 ticketsAwarded,
        uint24 targetLevel
    );

    /// @notice Emitted when DGNRS is rewarded to the exterminator.
    /// @param exterminator Address of the exterminator.
    /// @param level Level that was exterminated.
    /// @param dgnrsAmount Amount of DGNRS paid from the exterminator pool.
    event ExterminatorDgnrsReward(
        address indexed exterminator,
        uint24 indexed level,
        uint256 dgnrsAmount
    );

    /// @notice Emitted when DGNRS is rewarded to the top affiliate.
    /// @param affiliate Address of the top affiliate.
    /// @param level Level for which they were top affiliate.
    /// @param dgnrsAmount Amount of DGNRS paid from the affiliate pool.
    event AffiliateDgnrsReward(
        address indexed affiliate,
        uint24 indexed level,
        uint256 dgnrsAmount
    );

    /// @notice Emitted when whale pass rewards are claimed.
    /// @param player Player receiving tickets.
    /// @param caller Address that initiated the claim.
    /// @param halfPasses Half-pass count used for ticket awards.
    /// @param startLevel Level where ticket awards begin.
    event WhalePassClaimed(
        address indexed player,
        address indexed caller,
        uint256 halfPasses,
        uint24 startLevel
    );

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IDegenerusJackpots internal constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IDegenerusTrophies internal constant trophies =
        IDegenerusTrophies(ContractAddresses.TROPHIES);
    IDegenerusStonk internal constant dgnrs =
        IDegenerusStonk(ContractAddresses.DGNRS);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Sentinel value indicating level ended via timeout, not extermination.
    uint16 private constant TRAIT_ID_TIMEOUT = 420;

    /// @notice DGNRS reward for exterminator: 2% of remaining exterminator pool.
    uint16 private constant EXTERMINATOR_POOL_REWARD_BPS = 200;

    /// @notice DGNRS reward for top affiliate: 1% of remaining affiliate pool.
    uint16 private constant AFFILIATE_POOL_REWARD_BPS = 100;

    // -------------------------------------------------------------------------
    // Main Entry Point
    // -------------------------------------------------------------------------

    /**
     * @notice Pay the exterminator on the first jackpot after extermination.
     * @dev Called via delegatecall from DegenerusGame during burn phase.
     *      Mints trophy, pays claimable ETH, and transfers DGNRS reward.
     * @param lvl Current level index (1-based).
     * @param rngWord VRF entropy for share calculation.
     */
    function payExterminatorOnJackpot(uint24 lvl, uint256 rngWord) external {
        if (exterminationPaidThisLevel) return;

        uint16 traitRaw = currentExterminatedTrait;
        if (traitRaw == TRAIT_ID_TIMEOUT) return;

        address ex = levelExterminators[lvl];
        if (ex == address(0)) return;

        uint256 poolValue = currentPrizePool;
        uint16 exShareBps = _exterminatorShareBps(lvl, rngWord);
        uint256 totalShare = (poolValue * exShareBps) / 10_000;
        uint256 rewardPenalty;
        uint256 exterminatorShare = totalShare;
        if (exterminationInvertFlag && totalShare != 0) {
            rewardPenalty = totalShare / 2;
            exterminatorShare = totalShare - rewardPenalty;
            futurePrizePool += rewardPenalty;
        }

        (uint256 claimableDelta, uint96 dgnrsPaid) = _payExterminatorShare(
            ex,
            exterminatorShare,
            lvl,
            rngWord
        );
        uint96 exterminatorWinnings = uint96(exterminatorShare);
        trophies.mintExterminator(
            ex,
            lvl,
            uint8(traitRaw),
            exterminationInvertFlag,
            exterminatorWinnings,
            dgnrsPaid
        );
        if (claimableDelta != 0) {
            claimablePool += claimableDelta;
        }
        if (totalShare != 0) {
            currentPrizePool -= totalShare;
        }
        exterminationPaidThisLevel = true;
    }

    /**
     * @notice Settle a completed level by running reward jackpots.
     * @dev Called via delegatecall from DegenerusGame during state 1.
     *      Exterminator payouts are handled during burn via payExterminatorOnJackpot().
     *
     * @param lvl Current level index (1-based) - this is the NEW level after advancement.
     * @param rngWord VRF entropy for jackpot selection and randomization.
     */
    function finalizeEndgame(uint24 lvl, uint256 rngWord) external {
        uint24 prevLevel = lvl - 1; // The level that just ended
        if (prevLevel == 0) {
            return;
        }

        _topAffiliateReward(prevLevel);
        uint256 claimableDelta = _runRewardJackpots(prevLevel, rngWord);
        if (claimableDelta != 0) {
            claimablePool += claimableDelta;
        }
    }

    /// @notice Mint trophy and DGNRS reward for the top affiliate of a level.
    /// @dev Callable during the level jackpot; guarded by a per-level paid flag.
    /// @param lvl The level to reward.
    function rewardTopAffiliate(uint24 lvl) external {
        if (lvl == 0) return;
        _topAffiliateReward(lvl);
    }

    // -------------------------------------------------------------------------
    // Reward Jackpots (BAF & Decimator)
    // -------------------------------------------------------------------------

    /**
     * @notice Run BAF and Decimator jackpots based on level triggers.
     * @dev BAF fires every 10 levels, Decimator fires mid-decile.
     *
     * @param prevLevel The level that just completed.
     * @param rngWord VRF entropy for jackpot resolution.
     * @return claimableDelta Total ETH credited to claimable balances.
     *
     * ## BAF (Big-Ass Flip) Trigger Schedule
     *
     * | Level         | Pool Source    | Pool Size       |
     * |---------------|----------------|-----------------|
     * | 10, 20, 30... | future pool    | 10%             |
     * | 50            | future pool    | 25%             |
     * | 100           | bafHundredPool | reserved amount |
     *
     * ## Decimator Trigger Schedule
     *
     * Fires at: 5, 15, 25, 35, 45, 55, 65, 75, 85 (NOT 95)
     * Pool: 10% of future pool
     */
    function _runRewardJackpots(
        uint24 prevLevel,
        uint256 rngWord
    ) private returns (uint256 claimableDelta) {
        uint256 futurePoolLocal = futurePrizePool;
        uint24 prevMod10 = prevLevel % 10;
        uint24 prevMod100 = prevLevel % 100;

        // ---------------------------------------------------------------------
        // BAF Jackpot (every 10 levels)
        // ---------------------------------------------------------------------

        if (prevMod10 == 0) {
            uint256 bafPoolWei;
            bool reservedBaf;

            if (prevMod100 == 0 && bafHundredPool != 0) {
                // Level 100: use reserved pool (carved out earlier)
                bafPoolWei = bafHundredPool;
                bafHundredPool = 0;
                reservedBaf = true;
            } else {
                // Regular BAF: 10% of future pool (25% at level 50)
                bafPoolWei =
                    (futurePoolLocal * (prevLevel == 50 ? 25 : 10)) /
                    100;
            }

            (
                uint256 netSpend,
                uint256 claimed,
                uint256 lootboxToFuture
            ) = _rewardJackpot(
                0,
                bafPoolWei,
                prevLevel,
                rngWord
            );
            claimableDelta += claimed;

            if (reservedBaf) {
                // Reserved pool was already removed; only return refund
                uint256 refund = bafPoolWei - netSpend;
                if (refund != 0) {
                    futurePoolLocal += refund;
                }
            } else {
                futurePoolLocal -= netSpend;
            }

            if (lootboxToFuture != 0) {
                futurePoolLocal += lootboxToFuture;
            }
        }

        // ---------------------------------------------------------------------
        // Decimator Jackpot (levels ending in 5, except 95)
        // ---------------------------------------------------------------------

        if (prevMod10 == 5 && prevMod100 != 95) {
            // Fire decimator midway through each decile (5, 15, 25... not 95)
            uint256 decPoolWei = (futurePoolLocal * 10) / 100;
            if (decPoolWei != 0) {
                (
                    uint256 spend,
                    uint256 claimed,
                    uint256 lootboxToFuture
                ) = _rewardJackpot(
                    1,
                    decPoolWei,
                    prevLevel,
                    rngWord
                );
                futurePoolLocal -= spend;
                if (lootboxToFuture != 0) {
                    futurePoolLocal += lootboxToFuture;
                }
                claimableDelta += claimed;
            }
        }

        // Commit future pool update
        futurePrizePool = futurePoolLocal;
        return claimableDelta;
    }

    /**
     * @notice Mint trophy and DGNRS reward for the top affiliate of a completed level.
     * @param prevLevel The level that just completed.
     */
    function _topAffiliateReward(uint24 prevLevel) private {
        if (affiliateTopRewardPaid[prevLevel]) return;
        (address top, uint96 score) = affiliate.affiliateTop(prevLevel);
        if (top == address(0)) return;

        uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
        uint96 dgnrsPaid;
        uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) / 10_000;
        if (dgnrsReward != 0) {
            uint256 paid = dgnrs.transferFromPool(IDegenerusStonk.Pool.Affiliate, top, dgnrsReward);
            if (paid != 0) {
                dgnrsPaid = paid > type(uint96).max ? type(uint96).max : uint96(paid);
                emit AffiliateDgnrsReward(top, prevLevel, paid);
            }
        }

        // Mint affiliate trophy
        trophies.mintAffiliate(top, prevLevel, score, dgnrsPaid);
        affiliateTopRewardPaid[prevLevel] = true;
    }

    // -------------------------------------------------------------------------
    // Exterminator Payout
    // -------------------------------------------------------------------------

    /**
     * @notice Pay the exterminator their share as claimable ETH and transfer DGNRS reward.
     * @param ex Exterminator address.
     * @param exterminatorShare Total ETH share.
     * @param level Level that was exterminated.
     * @return claimableDelta ETH credited to claimable balance.
     * @return dgnrsPaid DGNRS paid to the exterminator.
     */
    function _payExterminatorShare(
        address ex,
        uint256 exterminatorShare,
        uint24 level,
        uint256 entropy
    ) private returns (uint256 claimableDelta, uint96 dgnrsPaid) {
        // Pay claimable ETH
        claimableDelta = _addClaimableEth(ex, exterminatorShare, entropy);

        uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Exterminator);
        uint256 dgnrsReward = (poolBalance * EXTERMINATOR_POOL_REWARD_BPS) / 10_000;
        if (dgnrsReward != 0) {
            uint256 paid = dgnrs.transferFromPool(IDegenerusStonk.Pool.Exterminator, ex, dgnrsReward);
            if (paid != 0) {
                dgnrsPaid = paid > type(uint96).max ? type(uint96).max : uint96(paid);
                emit ExterminatorDgnrsReward(ex, level, paid);
            }
        }

        return (claimableDelta, dgnrsPaid);
    }

    /**
     * @notice Credit ETH to a player's claimable balance.
     * @dev If auto-rebuy is enabled, converts the remainder to tickets with auto-rebuy
     *      bonus instead of crediting claimable balance. Complete keep-multiples
     *      remain claimable, and fractional dust rolls into a chance for +1 ticket.
     *
     * @param beneficiary Address to credit.
     * @param weiAmount ETH amount to credit.
     * @param entropy RNG seed for fractional ticket roll.
     * @return claimableDelta Amount to add to claimablePool for this credit.
     */
    function _addClaimableEth(
        address beneficiary,
        uint256 weiAmount,
        uint256 entropy
    ) private returns (uint256 claimableDelta) {
        if (weiAmount == 0) return 0;

        // Auto-rebuy: convert winnings to tickets if enabled
        if (autoRebuyEnabled[beneficiary]) {
            // Reserve full keep-multiples for claim; rebuy remainder.
            uint256 keepMultiple = autoRebuyKeepMultiple[beneficiary];
            uint256 reserved;
            uint256 rebuyAmount = weiAmount;
            if (keepMultiple != 0) {
                reserved = (weiAmount / keepMultiple) * keepMultiple;
                rebuyAmount = weiAmount - reserved;
            }

            uint24 targetLevel = (gameState == GAME_STATE_BURN)
                ? level + 1
                : level;
            uint256 ticketPrice = _priceForLevel(targetLevel) / 4;
            if (ticketPrice == 0) {
                ticketPrice = 0.00625 ether / ContractAddresses.COST_DIVISOR;
            }

            // Calculate base tickets from ETH
            uint256 baseTickets = rebuyAmount / ticketPrice;
            uint256 ethSpent = baseTickets * ticketPrice;
            uint256 dustRemainder = rebuyAmount - ethSpent;

            // Roll fractional remainder into a chance for +1 base ticket.
            if (dustRemainder != 0) {
                uint256 rollSeed = _entropyStep(
                    entropy ^
                        uint256(uint160(beneficiary)) ^
                        rebuyAmount ^
                        ticketPrice
                );
                if ((rollSeed % ticketPrice) < dustRemainder) {
                    ++baseTickets;
                    ethSpent = rebuyAmount;
                    dustRemainder = 0;
                }
            }

            if (baseTickets == 0) {
                unchecked {
                    claimableWinnings[beneficiary] += weiAmount;
                }
                emit PlayerCredited(beneficiary, weiAmount);
                return weiAmount;
            }

            // Apply auto-rebuy bonus (30% default, 45% in afKing mode)
            uint256 bonusBps = afKingMode[beneficiary] ? 14500 : 13000;
            uint256 bonusTickets = (baseTickets * bonusBps) / 10000;
            uint32 ticketCount = bonusTickets > type(uint32).max
                ? type(uint32).max
                : uint32(bonusTickets);

            // Fund next level's prize pool
            nextPrizePool += ethSpent;

            // Award tickets for target level
            _queueTickets(beneficiary, targetLevel, ticketCount);

            uint256 totalRemainder = reserved + dustRemainder;
            if (totalRemainder != 0) {
                unchecked {
                    claimableWinnings[beneficiary] += totalRemainder;
                    claimablePool += totalRemainder;
                }
            }

            emit AutoRebuyExecuted(
                beneficiary,
                rebuyAmount,
                ticketCount,
                targetLevel
            );
            return 0;
        }

        // Normal claimable balance credit (no auto-rebuy or insufficient amount)
        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, weiAmount);
        return weiAmount;
    }

    /**
     * @notice Xorshift PRNG step for deterministic pseudo-randomness.
     * @dev Standard xorshift64 algorithm. Seeded from VRF, so ultimately secure.
     * @param state Current PRNG state.
     * @return Next PRNG state.
     */
    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }


    // -------------------------------------------------------------------------
    // Reward Jackpot Dispatch
    // -------------------------------------------------------------------------

    /**
     * @notice Route a jackpot slice to the appropriate jackpot handler.
     * @param kind Jackpot type: 0 = BAF, 1 = Decimator.
     * @param poolWei ETH amount for the jackpot.
     * @param lvl Level tied to the jackpot.
     * @param rngWord VRF entropy for jackpot resolution.
     * @return netSpend Amount of future pool consumed (poolWei minus refund).
     * @return claimableDelta ETH credited to claimable balances.
     * @return lootboxToFuture Lootbox ETH recycled back into future pool.
     */
    function _rewardJackpot(
        uint8 kind,
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    )
        private
        returns (
            uint256 netSpend,
            uint256 claimableDelta,
            uint256 lootboxToFuture
        )
    {
        if (kind == 0) {
            return _runBafJackpot(poolWei, lvl, rngWord);
        }
        if (kind == 1) {
            // Decimator: jackpots contract handles distribution
            uint256 returnWei = jackpots.runDecimatorJackpot(
                poolWei,
                lvl,
                rngWord
            );
            // Decimator pool is reserved in claimablePool; per-player credits happen on claim
            uint256 spend = poolWei - returnWei;
            return (spend, spend, 0);
        }
        return (0, 0, 0);
    }

    // -------------------------------------------------------------------------
    // BAF Jackpot
    // -------------------------------------------------------------------------

    /**
     * @notice Execute BAF (Big-Ass Flip) jackpot distribution.
     * @dev All winners receive 50% ETH / 50% lootbox-style rewards.
     *
     * @param poolWei Total ETH for BAF distribution.
     * @param lvl Level triggering the BAF.
     * @param rngWord VRF entropy for winner selection.
     * @return netSpend Amount consumed from future pool.
     * @return claimableDelta ETH credited to claimable balances.
     * @return lootboxToFuture Lootbox ETH recycled into future pool.
     *
     * ## Payout Split (All Winners)
     *
     * | Portion | Reward Type                              |
     * |---------|------------------------------------------|
     * | 50%     | Claimable ETH (immediate)                |
     * | 50%     | Lootbox future tickets (claimWhalePass)  |
     *
     * ## Lootbox Flow (Tiered by Amount)
     *
     * **All payouts:**
     * - Large lootbox payouts defer via `claimWhalePass` for gas safety
     *
     * All lootbox ETH added to futurePrizePool.
     *
     * ## Trophy
     *
     * First winner (winners[0]) receives BAF trophy.
     */
    function _runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    )
        private
        returns (
            uint256 netSpend,
            uint256 claimableDelta,
            uint256 lootboxToFuture
        )
    {
        // Get winners and payout info from jackpots contract
        (
            address[] memory winnersArr,
            uint256[] memory amountsArr,
            ,
            uint256 refund
        ) = jackpots.runBafJackpot(poolWei, lvl, rngWord);

        uint256 lootboxTotal;

        // ---------------------------------------------------------------------
        // Process each winner with gas-optimized payout structure
        // Large winners (≥5% of pool): 50% ETH, 50% lootbox (balanced)
        // Small winners (<5% of pool): alternate 100% ETH or 100% lootbox (gas-efficient)
        // ---------------------------------------------------------------------

        uint256 largeWinnerThreshold = poolWei / 20; // 5% of total BAF pool

        for (uint256 i; i < winnersArr.length; ) {
            uint256 amount = amountsArr[i];

            // Large winners: keep 50/50 split for balanced payout
            if (amount >= largeWinnerThreshold) {
                uint256 ethPortion = amount / 2;
                uint256 lootboxPortion = amount - ethPortion;

                // Credit ETH half to claimable balance
                claimableDelta += _addClaimableEth(
                    winnersArr[i],
                    ethPortion,
                    rngWord
                );

                // Lootbox half: small amounts awarded immediately, large deferred
                if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                    // Small lootbox: award immediately (2 rolls, probabilistic targeting)
                    rngWord = _awardJackpotTickets(
                        winnersArr[i],
                        lootboxPortion,
                        lvl,
                        rngWord
                    );
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent)
                    // Calculate half-passes with VRF remainder roll for security
                    // Half-pass = 100 levels × 1 ticket = 100 tickets @ 1.75 ETH
                    uint256 HALF_WHALE_PASS_PRICE = 1.75 ether /
                        ContractAddresses.COST_DIVISOR;
                    uint256 fullHalfPasses = lootboxPortion / HALF_WHALE_PASS_PRICE;
                    uint256 remainder = lootboxPortion -
                        (fullHalfPasses * HALF_WHALE_PASS_PRICE);

                    // Probabilistic roll for +1 half pass using VRF RNG
                    if (remainder > 0) {
                        rngWord = _entropyStep(rngWord);
                        uint256 chanceBps = (remainder * 10000) /
                            HALF_WHALE_PASS_PRICE;
                        uint256 roll = rngWord % 10000;
                        if (roll < chanceBps) {
                            unchecked {
                                ++fullHalfPasses;
                            }
                        }
                    }

                    // Store half-pass count (safe: ETH supply limits prevent overflow)
                    whalePassClaims[winnersArr[i]] += fullHalfPasses;
                }
                lootboxTotal += lootboxPortion;
            }
            // Small winners: alternate between 100% ETH and 100% lootbox for gas efficiency
            else if (i % 2 == 0) {
                // Even index: 100% ETH (immediate liquidity)
                claimableDelta += _addClaimableEth(
                    winnersArr[i],
                    amount,
                    rngWord
                );
            } else {
                // Odd index: 100% lootbox (upside exposure)
                rngWord = _awardJackpotTickets(winnersArr[i], amount, lvl, rngWord);
                lootboxTotal += amount;
            }

            unchecked {
                ++i;
            }
        }

        // ---------------------------------------------------------------------
        // Move lootbox funds to pools (20% next, 80% future)
        // ---------------------------------------------------------------------

        if (lootboxTotal != 0) {
            uint256 toNext = lootboxTotal / 5;
            if (toNext != 0) {
                nextPrizePool += toNext;
            }
            lootboxToFuture = lootboxTotal - toNext;
        }

        // ---------------------------------------------------------------------
        // Mint BAF trophy for first winner
        // ---------------------------------------------------------------------

        if (winnersArr.length != 0) {
            try trophies.mintBaf(winnersArr[0], lvl, 0) {} catch {}
        }

        netSpend = poolWei - refund;
        return (netSpend, claimableDelta, lootboxToFuture);
    }

    /**
     * @notice Unified jackpot ticket award function for all jackpots.
     * @dev Awards tickets using two-tier system:
     *      Small (0.5-5 ETH): Split in half, 2 probabilistic rolls
     *      Large (> 5 ETH): Whale pass equivalent (100-ticket chunks)
     *      Uses actual game ticket pricing for target levels.
     *
     * @param winner Address to receive rewards.
     * @param amount ETH amount for ticket conversion.
     * @param minTargetLevel Minimum target level for tickets.
     * @param entropy RNG state.
     * @return Updated entropy state.
     */
    function _awardJackpotTickets(
        address winner,
        uint256 amount,
        uint24 minTargetLevel,
        uint256 entropy
    ) private returns (uint256) {
        // Large amounts (> 5 ETH): defer to whale pass claim system
        if (amount > LOOTBOX_CLAIM_THRESHOLD) {
            // Calculate half-passes with VRF remainder roll for security
            // Half-pass = 100 levels × 1 ticket = 100 tickets @ 1.75 ETH
            uint256 HALF_WHALE_PASS_PRICE = 1.75 ether / ContractAddresses.COST_DIVISOR;
            uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
            uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

            // Probabilistic roll for +1 half pass using VRF RNG
            if (remainder > 0) {
                entropy = _entropyStep(entropy);
                uint256 chanceBps = (remainder * 10000) / HALF_WHALE_PASS_PRICE;
                uint256 roll = entropy % 10000;
                if (roll < chanceBps) {
                    unchecked { ++fullHalfPasses; }
                }
            }

            // Store half-pass count (safe: ETH supply limits prevent overflow)
            whalePassClaims[winner] += fullHalfPasses;
            return entropy;
        }

        // Very small amounts (≤ 0.5 ETH): single roll
        if (amount <= 0.5 ether) {
            return _jackpotTicketRoll(winner, amount, minTargetLevel, entropy);
        }

        // Medium amounts (0.5-5 ETH): split in half, 2 rolls
        uint256 halfAmount = amount / 2;

        // First roll
        entropy = _jackpotTicketRoll(
            winner,
            halfAmount,
            minTargetLevel,
            entropy
        );

        // Second roll (with remainder if amount was odd)
        uint256 secondAmount = amount - halfAmount;
        entropy = _jackpotTicketRoll(
            winner,
            secondAmount,
            minTargetLevel,
            entropy
        );

        return entropy;
    }

    /**
     * @notice Resolve a single jackpot ticket roll into ticket awards.
     * @dev Selects target level based on probability, then awards tickets.
     *      Uses actual game pricing for the selected target level.
     * @param winner Address to receive tickets.
     * @param amount ETH amount for this roll.
     * @param minTargetLevel Minimum target level (usually current level during SETUP phase).
     * @param entropy RNG state.
     * @return Updated entropy state.
     */
    function _jackpotTicketRoll(
        address winner,
        uint256 amount,
        uint24 minTargetLevel,
        uint256 entropy
    ) private returns (uint256) {
        entropy = _entropyStep(entropy);

        // Roll for outcome (0-99 for percentage-based probabilities)
        uint256 roll = entropy % 100;
        uint24 targetLevel;

        if (roll < 30) {
            // 30% chance: minimum level ticket
            targetLevel = minTargetLevel;
        } else if (roll < 95) {
            // 65% chance: +1 to +4 levels ahead
            uint256 offset = 1 + ((entropy / 100) % 4); // 1-4 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        } else {
            // 5% chance: +5 to +50 levels ahead (rare)
            uint256 offset = 5 + ((entropy / 100) % 46); // 5-50 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        }

        // Calculate tickets for target level
        uint256 targetPrice = _priceForLevel(targetLevel);

        uint256 fullTickets = amount / targetPrice;
        uint256 remainder = amount - (fullTickets * targetPrice);

        _queueLootboxTickets(
            winner,
            targetLevel,
            fullTickets,
            remainder,
            targetPrice,
            entropy
        );

        return entropy;
    }

    /**
     * @notice Claim deferred whale pass rewards for the caller.
     * @dev Unified claim function for all large lootbox rewards (>5 ETH).
     *      Awards deterministic tickets based on pre-calculated half-pass count.
     *      Tickets start at current level + 1 to avoid giving tickets for an already-active level.
     */
    /**
     * @notice Claim deferred whale pass rewards for a player.
     * @param player Player address to claim for.
     */
    function claimWhalePass(address player) external {
        _claimWhalePass(player);
    }

    function _claimWhalePass(address winner) private {
        uint256 halfPasses = whalePassClaims[winner];
        if (halfPasses == 0) return;

        // Clear before awarding to avoid double-claiming
        whalePassClaims[winner] = 0;

        // Award tickets for 100 levels, with N tickets per level (where N = half-passes)
        // Start level depends on game state:
        // - BURN phase (state 3): tickets won't be processed this level, start at level+1
        // - Otherwise: tickets can be processed this level, start at current level
        // Example: 3 half-passes = 3 tickets/level × 100 levels = 300 tickets
        // Safe: halfPasses fits in uint32 (ETH supply limits prevent overflow)
        uint24 startLevel = (gameState == GAME_STATE_BURN) ? level + 1 : level;

        emit WhalePassClaimed(winner, msg.sender, halfPasses, startLevel);
        _queueTicketRange(winner, startLevel, 100, uint32(halfPasses));
    }

    /**
     * @notice Get actual individual ticket price for a target level.
     * @dev Matches the real game pricing formula from DegenerusGame._priceForLevel().
     *      Pricing changes at specific points in each 100-level cycle.
     *
     * @param targetLevel Level to query.
     * @return Price in wei per individual ticket at that level.
     */
    function _priceForLevel(uint24 targetLevel) private pure returns (uint256) {
        // First 10 levels (0-9) start at lower price
        if (targetLevel < 10)
            return 0.025 ether / ContractAddresses.COST_DIVISOR;

        uint256 cycleOffset = targetLevel % 100;

        // Price changes at specific points in the 100-level cycle
        if (cycleOffset == 0) {
            return 0.25 ether / ContractAddresses.COST_DIVISOR; // Levels 100, 200, 300...
        } else if (cycleOffset >= 80) {
            return 0.125 ether / ContractAddresses.COST_DIVISOR; // Levels 80-99, 180-199...
        } else if (cycleOffset >= 40) {
            return 0.1 ether / ContractAddresses.COST_DIVISOR; // Levels 40-79, 140-179...
        } else {
            // Levels 10-39, 101-139... = 0.05 ether
            return 0.05 ether / ContractAddresses.COST_DIVISOR;
        }
    }

    // -------------------------------------------------------------------------
    // Utility Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Calculate exterminator share in basis points.
     * @dev "Big-ex" levels (14, 24, 34...) get fixed 40%. Others get random 20-40%.
     *
     * @param prevLevel The level that was exterminated.
     * @param rngWord VRF entropy for randomization.
     * @return Exterminator share in basis points (2000-4000).
     */
    function _exterminatorShareBps(
        uint24 prevLevel,
        uint256 rngWord
    ) private pure returns (uint16) {
        // Big-ex levels: fixed 40% (levels 14, 24, 34... but not 4)
        if (prevLevel % 10 == 4 && prevLevel != 4) {
            return 4000;
        }

        // Random 20-40% in 1% steps
        uint256 seed = uint256(
            keccak256(abi.encode(rngWord, prevLevel, "ex_share"))
        );
        uint256 roll = seed % 21; // 0-20 inclusive
        return uint16(2000 + roll * 100); // 20-40%
    }
}
