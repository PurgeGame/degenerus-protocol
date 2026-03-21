// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title IBurnieCoinflip
 * @notice Interface for BurnieCoinflip contract - handles all BURNIE coinflip wagering logic.
 * @dev Standalone daily coinflip wagering system extracted from BurnieCoin to reduce contract size.
 *      Integrates with BurnieCoin for burn/mint operations and DegenerusGame for game state.
 */
interface IBurnieCoinflip {
    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Deposit BURNIE into the daily coinflip system.
    /// @dev Burns BURNIE from caller via BurnieCoin.burnForCoinflip, processes any pending claims,
    ///      applies quest bonuses and recycling bonuses, then adds stake for the next day's flip.
    ///      Can be called by player directly (player=address(0) or player=msg.sender) or by an
    ///      approved operator on behalf of a player.
    /// @param player The player making the deposit (address(0) or msg.sender for direct deposit).
    /// @param amount Amount of BURNIE to deposit (must be >= 100 BURNIE minimum).
    /// @custom:reverts AmountLTMin If amount is non-zero but less than 100 BURNIE.
    /// @custom:reverts CoinflipLocked If deposits are locked during level transition RNG resolution.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function depositCoinflip(address player, uint256 amount) external;

    /// @notice Claim an exact amount of coinflip winnings as BURNIE tokens.
    /// @dev Processes pending daily claims, then mints up to the requested amount.
    ///      Caller can claim for themselves or as an approved operator for another player.
    /// @param player The player claiming (address(0) for msg.sender).
    /// @param amount Amount to claim (will be capped at available balance).
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim coinflip winnings via BurnieCoin contract to cover token transfers/burns.
    /// @dev Access restricted to BurnieCoin contract only. Processes pending claims and mints tokens.
    /// @param player The player claiming.
    /// @param amount Amount to claim.
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts OnlyBurnieCoin If caller is not the BurnieCoin contract.
    function claimCoinflipsFromBurnie(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Consume coinflip winnings via BurnieCoin for burns without minting new tokens.
    /// @dev Access restricted to BurnieCoin contract only. Reduces claimable balance without minting.
    /// @param player The player whose balance to consume.
    /// @param amount Amount to consume.
    /// @return consumed The actual amount consumed.
    /// @custom:reverts OnlyBurnieCoin If caller is not the BurnieCoin contract.
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

    /// @notice Settle coinflip state before afKing mode changes.
    /// @dev Processes pending claims and stores them so mode change doesn't affect in-flight flips.
    ///      Called by DegenerusGame when toggling afKing mode.
    /// @param player The player to settle.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function settleFlipModeChange(address player) external;

    /*+======================================================================+
      |                       RNG PROCESSING                                 |
      +======================================================================+*/

    /// @notice Process coinflip payout for a completed epoch (called by game contract after VRF fulfillment).
    /// @dev Determines win/loss and reward percent from RNG, resolves bounty, advances claimable day.
    ///      Reward percent ranges: 5% chance of 50% (unlucky), 5% chance of 150% (lucky),
    ///      90% chance of 78-115% (normal). Bonus flip days add +6% during presale.
    /// @param bonusFlip Whether this is a bonus flip day (first jackpot day of a level).
    /// @param rngWord The VRF random word for determining outcome.
    /// @param epoch The epoch (day) index being resolved.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function processCoinflipPayouts(
        bool bonusFlip,
        uint256 rngWord,
        uint48 epoch
    ) external;

    /*+======================================================================+
      |                       CREDIT SYSTEM                                  |
      +======================================================================+*/

    /// @notice Credit flip stake to a player without burning tokens.
    /// @dev Called by authorized creditors (LazyPass, DegenerusGame, or BurnieCoin) for rewards.
    ///      Does not set bounty records or trigger bounty eligibility.
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of flip credit to add to next day's stake.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit flips to multiple players in a single call.
    /// @dev Batch version of creditFlip for gas efficiency. Skips zero addresses and amounts.
    /// @param players Fixed array of 3 player addresses.
    /// @param amounts Fixed array of 3 credit amounts corresponding to each player.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipBatch(
        address[3] calldata players,
        uint256[3] calldata amounts
    ) external;

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Preview total claimable BURNIE for a player including pending daily claims.
    /// @dev Calculates claimable from stored balance plus unprocessed winning days within claim window.
    /// @param player The player to check.
    /// @return mintable Total amount that would be claimable if claimed now.
    function previewClaimCoinflips(
        address player
    ) external view returns (uint256 mintable);

    /// @notice Get player's current coinflip stake for the next day's flip.
    /// @dev Returns the stake amount deposited for the upcoming flip day.
    /// @param player The player to check.
    /// @return The stake amount in BURNIE for the next flip.
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
            uint48 startDay
        );

    /// @notice Get the top bettor from the most recently resolved flip day.
    /// @dev Returns the player with the highest stake on the last completed day.
    /// @return player The address of the top bettor (address(0) if no flips resolved yet).
    /// @return score The top stake amount in whole tokens (capped to uint128).
    function coinflipTopLastDay()
        external
        view
        returns (address player, uint128 score);

    /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
    /// @dev Only callable by sDGNRS contract. Used during claimRedemption() when wallet
    ///      balance is insufficient and coinflip winnings need to be sourced.
    /// @param player The player whose winnings to claim.
    /// @param amount Amount to claim.
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts OnlyStakedDegenerusStonk If caller is not the sDGNRS contract.
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint48 day) external view returns (uint16 rewardPercent, bool win);
}
