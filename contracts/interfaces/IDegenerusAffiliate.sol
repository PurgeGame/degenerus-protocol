// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @title IDegenerusAffiliate
/// @notice Interface for the affiliate referral system (contract-to-contract calls only).
/// @dev Implements 3-tier referral structure: Player -> Affiliate (75%) -> Upline1 (20%) -> Upline2 (5%).
interface IDegenerusAffiliate {
    /// @notice Process affiliate rewards for a purchase or gameplay action.
    /// @dev Handles referral resolution, reward scaling, and multi-tier distribution.
    ///      Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+).
    ///      Recycled ETH rewards: 5% (all levels).
    ///      Access restricted to GAME purchase paths.
    /// @param amount Base reward amount (18 decimals).
    /// @param code Affiliate code provided with the transaction (may be bytes32(0)).
    /// @param sender The player making the purchase.
    /// @param lvl Current game level (for leaderboard tracking).
    /// @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
    /// @param lootboxActivityScore Buyer's activity score in whole points for lootbox taper (0 = no taper).
    /// @return playerKickback Amount of kickback to credit to the player.
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        address sender,
        uint24 lvl,
        bool isFreshEth,
        uint16 lootboxActivityScore
    ) external returns (uint256 playerKickback);

    /// @notice Settle all of a buy's affiliate legs (ticket + lootbox, fresh + recycled) in ONE call.
    /// @dev GAME-only. Resolves the referral once, accrues each leg at its own scale (fresh/recycled
    ///      bps, taper on the lootbox-fresh leg), rolls ONE winner on the shared (day, sender, code)
    ///      entropy, and RETURNS the winner credit instead of paying it so the caller batches the
    ///      winner + buyer credits into one Coinflip write.
    /// @param code Referral code supplied with the buy (resolved + locked once).
    /// @param sender The buyer.
    /// @param lvl Leaderboard level for all legs (ticket and lootbox both freeze at level + 1).
    /// @param tktFreshFlip Ticket-leg fresh spend in FLIP base units.
    /// @param tktRecycledFlip Ticket-leg recycled spend in FLIP base units.
    /// @param lbFreshFlip Lootbox-leg fresh spend in FLIP base units (tapered).
    /// @param lbRecycledFlip Lootbox-leg recycled spend in FLIP base units.
    /// @param lbFreshScore Activity score tapering the lootbox-fresh leg (0 = no taper).
    /// @return winner Single rolled recipient of the pooled affiliate share.
    /// @return winnerCredit FLIP owed the winner (share + quest reward); 0 if none or winner==sender.
    /// @return playerKickback FLIP kickback owed the buyer (summed across legs).
    function payAffiliateCombined(
        bytes32 code,
        address sender,
        uint24 lvl,
        uint256 tktFreshFlip,
        uint256 tktRecycledFlip,
        uint256 lbFreshFlip,
        uint256 lbRecycledFlip,
        uint16 lbFreshScore
    ) external returns (address winner, uint256 winnerCredit, uint256 playerKickback);

    /// @notice Settle a batch of afking subs' accrued affiliate base to the upline chain.
    /// @dev Permissionless. All `subs` must resolve to the same direct affiliate `A` (else revert).
    ///      Drains each sub's `affiliateBase` atomically at the Game storage owner, splits the total
    ///      75/20/5 (floored, remainder to A) and pays A / U1 / U2 directly via `creditFlip`; no-referrer
    ///      subs split 50/50 VAULT/sDGNRS. Fixed split (no roll, no seed). Leaderboard credits A once.
    /// @param subs Afking subscribers to settle; all must share the same direct affiliate `A`.
    function claim(address[] calldata subs) external;

    /// @notice Get the top affiliate for a given game level.
    /// @dev Returns the affiliate with the highest earnings for that level.
    ///      Used to pay the top affiliate a DGNRS pool reward at level transition.
    /// @param lvl The game level to query.
    /// @return player Address of the top affiliate.
    /// @return score Their score in FLIP base units (18 decimals).
    function affiliateTop(uint24 lvl) external view returns (address player, uint96 score);

    /// @notice Get an affiliate's base earnings score for a level.
    /// @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
    /// @param lvl The game level to query.
    /// @param player The affiliate address to query.
    /// @return score The base affiliate score (18 decimals).
    function affiliateScore(uint24 lvl, address player) external view returns (uint256 score);

    /// @notice Get the total affiliate score across all affiliates for a level.
    /// @param lvl The game level to query.
    /// @return total The total affiliate score (18 decimals).
    function totalAffiliateScore(uint24 lvl) external view returns (uint256 total);

    /// @notice Calculate the affiliate bonus points for a player.
    /// @dev Sums the player's affiliate scores for the previous 5 levels, converted to
    ///      weighted referred ETH volume (score × level ticket price / PRICE_COIN_UNIT,
    ///      normalized by the 20% fresh reward rate; fresh ≈ 1:1, recycled 0.25×).
    ///      Awards 4 points per ETH for the first 5 ETH, 1.5 points per ETH for the next 20 ETH, capped at 50.
    /// @param currLevel The current game level.
    /// @param player The player to calculate bonus for.
    /// @return points Bonus points (0 to 50).
    function affiliateBonusPointsBest(uint24 currLevel, address player) external view returns (uint256 points);

    /// @notice Get the referrer address for a player.
    /// @dev Never returns address(0): resolves to the VAULT when the player has no valid
    ///      referrer (code unset, locked, vault-coded, or its owner unresolvable), so
    ///      referral chains always terminate at the VAULT.
    /// @param player The player to look up.
    /// @return The referrer's address (the VAULT when the player has no real referrer).
    function getReferrer(address player) external view returns (address);
}
