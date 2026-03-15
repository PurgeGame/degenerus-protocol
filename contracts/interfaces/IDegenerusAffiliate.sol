// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IDegenerusAffiliate
/// @notice Interface for the affiliate referral system (contract-to-contract calls only).
/// @dev Implements 3-tier referral structure: Player -> Affiliate (base) -> Upline1 (20%) -> Upline2 (4%).
interface IDegenerusAffiliate {
    /// @notice Process affiliate rewards for a purchase or gameplay action.
    /// @dev Handles referral resolution, reward scaling, and multi-tier distribution.
    ///      Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+).
    ///      Recycled ETH rewards: 5% (all levels).
    ///      Access restricted to COIN and GAME purchase paths.
    /// @param amount Base reward amount (18 decimals).
    /// @param code Affiliate code provided with the transaction (may be bytes32(0)).
    /// @param sender The player making the purchase.
    /// @param lvl Current game level (for leaderboard tracking).
    /// @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
    /// @param lootboxActivityScore Buyer's activity score in BPS for lootbox taper (0 = no taper).
    /// @return playerKickback Amount of kickback to credit to the player.
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        address sender,
        uint24 lvl,
        bool isFreshEth,
        uint16 lootboxActivityScore
    ) external returns (uint256 playerKickback);

    /// @notice Get the top affiliate for a given game level.
    /// @dev Returns the affiliate with the highest earnings for that level.
    ///      Used for affiliate trophies and jackpot selections.
    /// @param lvl The game level to query.
    /// @return player Address of the top affiliate.
    /// @return score Their score in BURNIE base units (18 decimals).
    function affiliateTop(uint24 lvl) external view returns (address player, uint96 score);

    /// @notice Get an affiliate's base earnings score for a level.
    /// @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
    /// @param lvl The game level to query.
    /// @param player The affiliate address to query.
    /// @return score The base affiliate score (18 decimals).
    function affiliateScore(uint24 lvl, address player) external view returns (uint256 score);

    /// @notice Calculate the affiliate bonus points for a player.
    /// @dev Sums the player's affiliate scores for the previous 5 levels.
    ///      Awards 1 point (1%) per 1 ETH of summed score, capped at 50.
    /// @param currLevel The current game level.
    /// @param player The player to calculate bonus for.
    /// @return points Bonus points (0 to 50).
    function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points);

    /// @notice Get the referrer address for a player.
    /// @dev Returns address(0) if player has no valid referrer.
    /// @param player The player to look up.
    /// @return The referrer's address, or address(0) if none.
    function getReferrer(address player) external view returns (address);
}
