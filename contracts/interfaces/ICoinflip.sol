// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title ICoinflip
 * @notice Interface for Coinflip contract - handles all FLIP coinflip wagering logic.
 * @dev Standalone daily coinflip wagering system extracted from FLIP to reduce contract size.
 *      Integrates with FLIP for burn/mint operations and DegenerusGame for game state.
 */
interface ICoinflip {
    /// @notice Emitted whenever a player's coinflip claim-state changes (claimable + carry + claim
    ///         cursor), so off-chain consumers can reconstruct valuation from logs without an eth_call.
    event CoinflipClaimState(
        address indexed player,
        uint128 claimableStored,
        uint128 autoRebuyCarry,
        uint24  lastClaim
    );

    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Deposit FLIP into the daily coinflip system.
    /// @dev Burns FLIP from caller via FLIP.burnForCoinflip, processes any pending claims,
    ///      applies quest bonuses and recycling bonuses, then adds stake for the next day's flip.
    ///      Can be called by player directly (player=address(0) or player=msg.sender) or by an
    ///      approved operator on behalf of a player.
    /// @param player The player making the deposit (address(0) or msg.sender for direct deposit).
    /// @param amount Amount of FLIP to deposit (must be >= 100 FLIP minimum).
    /// @custom:reverts AmountLTMin If amount is non-zero but less than 100 FLIP.
    /// @custom:reverts CoinflipLocked If deposits are locked during level transition RNG resolution.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function depositCoinflip(address player, uint256 amount) external;

    /// @notice Claim an exact amount of coinflip winnings as FLIP tokens.
    /// @dev Processes pending daily claims, then mints up to the requested amount.
    ///      Caller can claim for themselves or as an approved operator for another player.
    /// @param player The player claiming (address(0) for msg.sender).
    /// @param amount Amount to claim (will be capped at available balance).
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim up to `amount` of the auto-rebuy carry as minted FLIP while staying on auto-rebuy.
    /// @dev Settles all resolved days first (wins roll into the carry, a pending loss zeroes it),
    ///      then withdraws from the settled carry; the remainder keeps rolling. Blocked during
    ///      the RNG lock. Take-profit chunks surfaced by the settle bank into the claimable side.
    /// @param player The player claiming (address(0) for msg.sender).
    /// @param amount Maximum carry to claim.
    /// @return claimed The actual amount minted from the carry.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    /// @custom:reverts RngLocked If a VRF request is pending.
    /// @custom:reverts AutoRebuyNotEnabled If the player is not on auto-rebuy.
    function claimCoinflipCarry(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim coinflip winnings via FLIP contract to cover token transfers/burns.
    /// @dev Access restricted to FLIP contract only. Processes pending claims and mints tokens.
    /// @param player The player claiming.
    /// @param amount Amount to claim.
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function claimCoinflipsFromFlip(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Consume coinflip winnings via FLIP for burns without minting new tokens.
    /// @dev Access restricted to FLIP contract only. Reduces claimable balance without minting.
    /// @param player The player whose balance to consume.
    /// @param amount Amount to consume.
    /// @return consumed The actual amount consumed.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);

    /// @notice Configure auto-rebuy mode for coinflips.
    /// @dev Auto-rebuy automatically rolls over winnings as stake for future flips.
    ///      When enabled, winnings accumulate as carry until claimed. When disabled,
    ///      processes a larger window of pending claims and mints all accumulated tokens.
    /// @param player The player configuring auto-rebuy (address(0) for msg.sender).
    /// @param enabled Whether auto-rebuy should be enabled.
    /// @param takeProfit The threshold amount; winnings above this are auto-claimed in multiples.
    /// @custom:reverts RngLocked If VRF randomness is currently being resolved.
    /// @custom:reverts AutoRebuyAlreadyEnabled If enabling when already enabled (in strict mode).
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 takeProfit
    ) external;

    /// @notice Update the take profit threshold for auto-rebuy mode.
    /// @dev Only callable when auto-rebuy is already enabled. Processes pending claims before updating.
    /// @param player The player configuring (address(0) for msg.sender).
    /// @param takeProfit The new threshold amount for auto-claiming multiples.
    /// @custom:reverts RngLocked If VRF randomness is currently being resolved.
    /// @custom:reverts AutoRebuyNotEnabled If player does not have auto-rebuy enabled.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function setCoinflipAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) external;

    /*+======================================================================+
      |                       RNG PROCESSING                                 |
      +======================================================================+*/

    /// @notice Process coinflip payout for a completed epoch (called by game contract after VRF fulfillment).
    /// @dev Determines win/loss and reward percent from RNG, resolves bounty, advances claimable day.
    ///      Reward percent ranges: 5% chance of 50% (unlucky), 5% chance of 150% (lucky),
    ///      90% chance of 78-115% (normal). The caller adds a precomputed bonus on top.
    /// @param bonus Reward-percent bonus precomputed by the caller from frozen state: 0 = normal day,
    ///        2 = bonus day (level 0 or a level's first jackpot day), 6 = x0-level (post-BAF) bonus day.
    /// @param rngWord The VRF random word for determining outcome.
    /// @param epoch The epoch (day) index being resolved.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function processCoinflipPayouts(
        uint8 bonus,
        uint256 rngWord,
        uint24 epoch
    ) external;

    /*+======================================================================+
      |                       CREDIT SYSTEM                                  |
      +======================================================================+*/

    /// @notice Credit flip stake to a player without burning tokens.
    /// @dev Called by authorized creditors (GAME, QUESTS, AFFILIATE, ADMIN) for rewards.
    ///      Does not set bounty records or trigger bounty eligibility.
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of flip credit to add to next day's stake.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit flips to multiple players in a single call.
    /// @dev Batch version of creditFlip for gas efficiency. Skips zero addresses and amounts.
    /// @param players Player addresses.
    /// @param amounts Credit amounts corresponding to each player.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipBatch(
        address[] calldata players,
        uint256[] calldata amounts
    ) external;

    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (claimableStored + carry).
    /// @dev sDGNRS-only. Settles all resolved days first so the two summed components are disjoint
    ///      and current; the held wallet balance is read separately by sDGNRS.
    /// @return backing claimableStored + autoRebuyCarry for sDGNRS.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function redeemableFlipBacking() external returns (uint256 backing);

    /// @notice Remove `base` (wei) of sDGNRS's FLIP backing at redemption submit.
    /// @dev sDGNRS-only. Waterfall: held wallet balance (burned) → settled claimable (consumed) →
    ///      auto-rebuy carry (decremented). Credits nothing; the redeemer's escrowed slice is paid
    ///      later on the resolving day's coinflip win via creditFlip. Fail-closed if backing < base.
    /// @param base Whole-token-aligned FLIP backing (wei) to remove from sDGNRS.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function withdrawRedeemedFlip(uint256 base) external;

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Preview total claimable FLIP for a player including pending daily claims.
    /// @dev Calculates claimable from stored balance plus unprocessed winning days within claim window.
    /// @param player The player to check.
    /// @return mintable Total amount that would be claimable if claimed now.
    function previewClaimCoinflips(
        address player
    ) external view returns (uint256 mintable);

    /// @notice Get player's current coinflip stake for the next day's flip.
    /// @dev Returns the stake amount deposited for the upcoming flip day.
    /// @param player The player to check.
    /// @return The stake amount in FLIP for the next flip.
    function coinflipAmount(address player) external view returns (uint256);

    /// @notice Get player's auto-rebuy configuration.
    /// @param player The player to check.
    /// @return enabled Whether auto-rebuy mode is currently active.
    /// @return stop The threshold amount for auto-claiming multiples.
    /// @return carry The current accumulated carry amount (winnings below threshold).
    /// @return startDay The day auto-rebuy was enabled (used for claim window calculation).
    function coinflipAutoRebuyInfo(
        address player
    )
        external
        view
        returns (
            bool enabled,
            uint256 stop,
            uint256 carry,
            uint24 startDay
        );

    /// @notice Get the top bettor from the most recently resolved flip day.
    /// @dev Returns the player with the highest stake on the last completed day.
    /// @return player The address of the top bettor (address(0) if no flips resolved yet).
    /// @return score The top stake amount in whole tokens (capped to uint128).
    function coinflipTopLastDay()
        external
        view
        returns (address player, uint128 score);

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win);
}
