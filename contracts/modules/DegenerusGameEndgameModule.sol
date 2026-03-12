// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameEndgameModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling endgame reward jackpots.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame,
 *      meaning all storage reads/writes operate on the game contract's storage.
 *
 * ## When Called
 *
 * Reward jackpots (BAF/Decimator) are resolved during the level transition RNG period
 * via `runRewardJackpots()`. Affiliate trophies/rewards are minted during level
 * transition via `rewardTopAffiliate()`.
 *
 * ## Settlement Flow
 *
 * ```
 * runRewardJackpots()
 *     +- BAF (every 10 levels): 10-25% of future pool (level 100 uses 20%)
 *     +- Decimator (levels 5,15,25...85): 10% of future pool (level 100 uses 30%)
 * ```
 */
contract DegenerusGameEndgameModule is DegenerusGamePayoutUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

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
    IDegenerusStonk internal constant dgnrs =
        IDegenerusStonk(ContractAddresses.DGNRS);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice DGNRS reward for top affiliate: 1% of remaining affiliate pool.
    uint16 private constant AFFILIATE_POOL_REWARD_BPS = 100;
    uint256 private constant SMALL_LOOTBOX_THRESHOLD = 0.5 ether;

    // -------------------------------------------------------------------------
    // Main Entry Point
    // -------------------------------------------------------------------------

    /// @notice Award DGNRS reward to the top affiliate of a level.
    /// @dev Callable during level transition; guarded by a per-level paid flag.
    /// @param lvl The level to reward.
    function rewardTopAffiliate(uint24 lvl) external {
        (address top, ) = affiliate.affiliateTop(lvl);
        if (top == address(0)) return;

        uint256 poolBalance = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
        uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) /
            10_000;
        uint256 paid = dgnrs.transferFromPool(
            IDegenerusStonk.Pool.Affiliate,
            top,
            dgnrsReward
        );
        emit AffiliateDgnrsReward(top, lvl, paid);
    }

    /// @notice Run reward jackpots (BAF/Decimator) during the level transition RNG period.
    /// @dev Called via delegatecall from DegenerusGame during purchase jackpot time.
    /// @param lvl Level to resolve jackpots for.
    /// @param rngWord VRF entropy for jackpot selection and randomization.
    ///
    /// ## BAF (Big-Ass Flip) Trigger Schedule
    ///
    /// | Level         | Pool Source    | Pool Size       |
    /// |---------------|----------------|-----------------|
    /// | 10, 20, 30... | future pool    | 10%             |
    /// | 50            | future pool    | 25%             |
    /// | 100           | future pool    | 20% special     |
    ///
    /// ## Decimator Trigger Schedule
    ///
    /// Fires at: 5, 15, 25, 35, 45, 55, 65, 75, 85 (NOT 95)
    /// Pool: 10% of future pool (level 100 uses 30% special)
    function runRewardJackpots(uint24 lvl, uint256 rngWord) external {
        uint256 futurePoolLocal = _getFuturePrizePool();
        uint256 baseFuturePool = futurePoolLocal;
        uint24 prevMod10 = lvl % 10;
        uint24 prevMod100 = lvl % 100;
        uint256 claimableDelta;

        // ---------------------------------------------------------------------
        // BAF Jackpot (every 10 levels)
        // ---------------------------------------------------------------------

        if (prevMod10 == 0) {
            uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 25 : 10);
            uint256 bafPoolWei = (baseFuturePool * bafPct) / 100;

            // Pull the full BAF pool out first; refunds/lootbox recycle back in after resolution.
            futurePoolLocal -= bafPoolWei;
            (
                uint256 netSpend,
                uint256 claimed,
                uint256 lootboxToFuture
            ) = _runBafJackpot(bafPoolWei, lvl, rngWord);
            claimableDelta += claimed;

            if (netSpend != bafPoolWei) {
                futurePoolLocal += (bafPoolWei - netSpend);
            }

            if (lootboxToFuture != 0) {
                futurePoolLocal += lootboxToFuture;
            }
        }

        // ---------------------------------------------------------------------
        // Decimator Jackpot (level 100 special)
        // ---------------------------------------------------------------------

        if (prevMod100 == 0) {
            uint256 decPoolWei = (baseFuturePool * 30) / 100;
            if (decPoolWei != 0) {
                uint256 returnWei = IDegenerusGame(address(this))
                    .runDecimatorJackpot(decPoolWei, lvl, rngWord);
                uint256 spend = decPoolWei - returnWei;
                futurePoolLocal -= spend;
                claimableDelta += spend;
            }
        }

        // ---------------------------------------------------------------------
        // Decimator Jackpot (levels ending in 5, except 95)
        // ---------------------------------------------------------------------

        if (prevMod10 == 5 && prevMod100 != 95) {
            // Fire decimator midway through each decile (5, 15, 25... not 95)
            uint256 decPoolWei = (futurePoolLocal * 10) / 100;
            if (decPoolWei != 0) {
                uint256 returnWei = IDegenerusGame(address(this))
                    .runDecimatorJackpot(decPoolWei, lvl, rngWord);
                uint256 spend = decPoolWei - returnWei;
                futurePoolLocal -= spend;
                // Decimator pool is reserved in claimablePool; per-player credits happen on claim
                claimableDelta += spend;
            }
        }

        // Commit future pool update only when changed (saves an SSTORE on non-jackpot levels)
        if (futurePoolLocal != baseFuturePool) {
            _setFuturePrizePool(futurePoolLocal);
        }
        if (claimableDelta != 0) {
            claimablePool += claimableDelta;
        }
    }

    /**
     * @notice Credit ETH to a player's claimable balance.
     * @dev If auto-rebuy is enabled, converts the remainder to tickets with auto-rebuy
     *      bonus instead of crediting claimable balance. Complete take profit multiples
     *      remain claimable, and fractional dust is dropped unconditionally.
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
        AutoRebuyState memory state = autoRebuyState[beneficiary];
        if (state.autoRebuyEnabled) {
            AutoRebuyCalc memory calc = _calcAutoRebuy(
                beneficiary,
                weiAmount,
                entropy,
                state,
                level,
                13_000,
                14_500
            );
            if (!calc.hasTickets) {
                _creditClaimable(beneficiary, weiAmount);
                return weiAmount;
            }

            if (calc.toFuture) {
                _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent);
            } else {
                _setNextPrizePool(_getNextPrizePool() + calc.ethSpent);
            }

            _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount);

            if (calc.reserved != 0) {
                _creditClaimable(beneficiary, calc.reserved);
                claimablePool += calc.reserved;
            }

            emit AutoRebuyExecuted(
                beneficiary,
                calc.rebuyAmount,
                calc.ticketCount,
                calc.targetLevel
            );
            return 0;
        }

        // Normal claimable balance credit (no auto-rebuy or insufficient amount)
        _creditClaimable(beneficiary, weiAmount);
        return weiAmount;
    }

    // -------------------------------------------------------------------------
    // Reward Jackpot Dispatch
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // BAF Jackpot
    // -------------------------------------------------------------------------

    /**
     * @notice Execute BAF (Big-Ass Flip) jackpot distribution.
     * @dev Large winners (>=5% of pool) receive 50% ETH / 50% lootbox.
     *      Small winners (<5% of pool) alternate: even-index gets 100% ETH,
     *      odd-index gets 100% lootbox (gas-efficient batching).
     *
     * @param poolWei Total ETH for BAF distribution.
     * @param lvl Level triggering the BAF.
     * @param rngWord VRF entropy for winner selection.
     * @return netSpend Amount consumed from future pool.
     * @return claimableDelta ETH credited to claimable balances.
     * @return lootboxToFuture Lootbox ETH recycled into future pool.
     *
     * ## Payout Split
     *
     * | Winner Size        | Portion | Reward Type                              |
     * |--------------------|---------|------------------------------------------|
     * | Large (>=5% pool)  | 50%     | Claimable ETH (immediate)                |
     * | Large (>=5% pool)  | 50%     | Lootbox future tickets (claimWhalePass)  |
     * | Small even-index   | 100%    | Claimable ETH (immediate)                |
     * | Small odd-index    | 100%    | Lootbox future tickets                   |
     *
     * ## Lootbox Flow (Tiered by Amount)
     *
     * **All payouts:**
     * - Large lootbox payouts defer via `claimWhalePass` for gas safety
     *
     * All lootbox ETH stays in futurePrizePool (source pool).
     *
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

        uint256 winnersLen = winnersArr.length;
        for (uint256 i; i < winnersLen; ) {
            address winner = winnersArr[i];
            uint256 amount = amountsArr[i];

            // Large winners: keep 50/50 split for balanced payout
            if (amount >= largeWinnerThreshold) {
                uint256 ethPortion = amount / 2;
                uint256 lootboxPortion = amount - ethPortion;

                // Credit ETH half to claimable balance
                claimableDelta += _addClaimableEth(winner, ethPortion, rngWord);

                // Lootbox half: small amounts awarded immediately, large deferred
                if (lootboxPortion <= LOOTBOX_CLAIM_THRESHOLD) {
                    // Small lootbox: award immediately (2 rolls, probabilistic targeting)
                    rngWord = _awardJackpotTickets(
                        winner,
                        lootboxPortion,
                        lvl,
                        rngWord
                    );
                } else {
                    // Large lootbox: defer to claim (whale pass equivalent)
                    _queueWhalePassClaimCore(winner, lootboxPortion);
                }
                lootboxTotal += lootboxPortion;
            }
            // Small winners: alternate between 100% ETH and 100% lootbox for gas efficiency
            else if (i % 2 == 0) {
                // Even index: 100% ETH (immediate liquidity)
                claimableDelta += _addClaimableEth(winner, amount, rngWord);
            } else {
                // Odd index: 100% lootbox (upside exposure)
                rngWord = _awardJackpotTickets(winner, amount, lvl, rngWord);
                lootboxTotal += amount;
            }

            unchecked {
                ++i;
            }
        }

        // Lootbox ETH stays in future pool (it came from there)
        lootboxToFuture = lootboxTotal;

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
            _queueWhalePassClaimCore(winner, amount);
            return entropy;
        }

        // Very small amounts (≤ 0.5 ETH): single roll
        if (amount <= SMALL_LOOTBOX_THRESHOLD) {
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
        entropy = EntropyLib.entropyStep(entropy);

        // Roll for outcome (0-99 for percentage-based probabilities)
        uint256 entropyDiv100 = entropy / 100;
        uint256 roll = entropy - (entropyDiv100 * 100);
        uint24 targetLevel;

        if (roll < 30) {
            // 30% chance: minimum level ticket
            targetLevel = minTargetLevel;
        } else if (roll < 95) {
            // 65% chance: +1 to +4 levels ahead
            uint256 offset = 1 + (entropyDiv100 % 4); // 1-4 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        } else {
            // 5% chance: +5 to +50 levels ahead (rare)
            uint256 offset = 5 + (entropyDiv100 % 46); // 5-50 inclusive
            targetLevel = minTargetLevel + uint24(offset);
        }

        // Calculate tickets for target level
        uint256 targetPrice = PriceLookupLib.priceForLevel(targetLevel);

        uint256 quantityScaled = (amount * TICKET_SCALE) / targetPrice;
        _queueLootboxTickets(winner, targetLevel, quantityScaled);

        return entropy;
    }

    /**
     * @notice Claim deferred whale pass rewards for a player.
     * @dev Unified claim function for all large lootbox rewards (>5 ETH).
     *      Awards deterministic tickets based on pre-calculated half-pass count.
     *      Tickets start at current level + 1 to avoid giving tickets for an already-active level.
     * @param player Player address to claim for.
     */
    function claimWhalePass(address player) external {
        if (gameOver) revert E();
        uint256 halfPasses = whalePassClaims[player];
        if (halfPasses == 0) return;

        // Clear before awarding to avoid double-claiming
        whalePassClaims[player] = 0;

        // Award tickets for 100 levels, with N tickets per level (where N = half-passes)
        // Start level depends on game state:
        // - Jackpot phase: tickets won't be processed this level, start at level+1
        // - Otherwise: tickets can be processed this level, start at current level
        // Example: 3 half-passes = 3 tickets/level × 100 levels = 300 tickets
        // Safe: halfPasses fits in uint32 (ETH supply limits prevent overflow)
        uint24 startLevel = level + 1;

        _applyWhalePassStats(player, startLevel);
        emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);
        _queueTicketRange(player, startLevel, 100, uint32(halfPasses));
    }

    // -------------------------------------------------------------------------
    // Utility Functions
    // -------------------------------------------------------------------------

}
