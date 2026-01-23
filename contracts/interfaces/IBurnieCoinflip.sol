// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IBurnieCoinflip
 * @notice Interface for BurnieCoinflip contract - handles all BURNIE coinflip wagering logic.
 */
interface IBurnieCoinflip {
    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Deposit BURNIE into coinflip system.
    /// @param player The player making the deposit.
    /// @param amount Amount of BURNIE to deposit.
    function depositCoinflip(address player, uint256 amount) external;

    /// @notice Claim coinflip winnings (exact amount).
    /// @param player The player claiming.
    /// @param amount Amount to claim.
    function claimCoinflips(address player, uint256 amount) external;

    /// @notice Claim coinflip winnings (keep multiples).
    /// @param player The player claiming.
    /// @param multiples Multiples to keep.
    function claimCoinflipsKeepMultiple(
        address player,
        uint256 multiples
    ) external;

    /// @notice Configure auto-rebuy mode for coinflips.
    /// @param player The player configuring auto-rebuy.
    /// @param enabled Whether auto-rebuy is enabled.
    /// @param keepMultiple The multiple to keep when auto-rebuying.
    function setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 keepMultiple
    ) external;

    /// @notice Set auto-rebuy keep multiple.
    /// @param player The player configuring.
    /// @param keepMultiple The multiple to keep.
    function setCoinflipAutoRebuyKeepMultiple(
        address player,
        uint256 keepMultiple
    ) external;

    /// @notice Set afKing daily-only mode.
    /// @param player The player configuring.
    /// @param dailyOnly Whether to use daily-only mode.
    function setAfKingDailyOnly(address player, bool dailyOnly) external;

    /*+======================================================================+
      |                       RNG PROCESSING                                 |
      +======================================================================+*/

    /// @notice Process coinflip payout for a day (called by game contract).
    /// @param bonusFlip Whether this is a bonus flip day.
    /// @param rngWord The VRF random word.
    /// @param epoch The epoch (day) index.
    function processCoinflipPayouts(
        bool bonusFlip,
        uint256 rngWord,
        uint48 epoch
    ) external;

    /// @notice Record afKing flip RNG result (called by game contract).
    /// @param rngWord The VRF random word.
    /// @param bonusFlip Whether this is a bonus flip.
    function recordAfKingRng(uint256 rngWord, bool bonusFlip) external;

    /*+======================================================================+
      |                       CREDIT SYSTEM                                  |
      +======================================================================+*/

    /// @notice Credit flip to a player (called by authorized creditors).
    /// @param player The player receiving the credit.
    /// @param amount Amount of flip credit.
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit flips to multiple players (batch).
    /// @param players Array of players.
    /// @param amounts Array of amounts.
    function creditFlipBatch(
        address[3] calldata players,
        uint256[3] calldata amounts
    ) external;

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Preview total claimable BURNIE for a player.
    /// @param player The player to check.
    /// @return mintable Total claimable amount.
    function previewClaimCoinflips(
        address player
    ) external view returns (uint256 mintable);

    /// @notice Get player's current coinflip stake for next day.
    /// @param player The player to check.
    /// @return Current stake amount.
    function coinflipAmount(address player) external view returns (uint256);

    /// @notice Get player's auto-rebuy configuration.
    /// @param player The player to check.
    /// @return enabled Whether auto-rebuy is enabled.
    /// @return stop The stop threshold.
    /// @return carry The carry amount.
    /// @return startDay The start day.
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

    /// @notice Get player's afKing daily-only mode.
    /// @param player The player to check.
    /// @return dailyOnly Whether daily-only mode is active.
    function afKingDailyOnlyMode(
        address player
    ) external view returns (bool dailyOnly);

    /// @notice Get last day's coinflip leaderboard winner.
    /// @return player The winning player.
    /// @return score The winning score.
    function coinflipTopLastDay()
        external
        view
        returns (address player, uint128 score);
}
