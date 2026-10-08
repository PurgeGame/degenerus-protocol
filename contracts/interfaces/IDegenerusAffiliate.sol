// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/// @title IDegenerusAffiliate
/// @notice Interface for the affiliate referral system (contract-to-contract calls only).
/// @dev Implements 3-tier referral structure: Player -> Affiliate (75%) -> Upline1 (20%) -> Upline2 (5%).
///      Code owners, uplines, earnings, scores and the per-level leader are keyed by uint32 wallet
///      ID; referral words are keyed by the player ID. Protocol owners are
///      the constant IDs VAULT 1 and SDGNRS 2. Wallet ID 0 means "no wallet".
interface IDegenerusAffiliate {
    /// @notice Process affiliate rewards for a purchase or gameplay action.
    /// @dev Handles referral resolution, reward scaling, and multi-tier distribution.
    ///      Fresh ETH rewards: 25% (levels 0-3), 20% (levels 4+).
    ///      Recycled ETH rewards: 5% (all levels).
    ///      Access restricted to GAME purchase paths. Credits the rolled winner itself by wallet
    ///      ID (`creditFlip(winnerId, ...)`) and skips the leg whose winner ID equals `senderId`.
    ///      A zero `amount` rolls no winner, so `senderId` may be 0 for it (WhaleModule's
    ///      link-only touch).
    /// @param amount Base reward amount (0 decimals).
    /// @param code Affiliate code provided with the transaction (may be bytes32(0)).

    /// @param senderId The player's wallet ID (seeds the winner roll).
    /// @param lvl Current game level (for leaderboard tracking).
    /// @param isFreshEth True if payment is with fresh ETH, false if recycled (claimable).
    /// @param lootboxActivityScore Buyer's activity score in whole points for lootbox taper (0 = no taper).
    /// @return playerKickback Amount of kickback to credit to the player.
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        uint32 senderId,
        uint24 lvl,
        bool isFreshEth,
        uint16 lootboxActivityScore
    ) external returns (uint256 playerKickback);

    /// @notice Settle all of a buy's affiliate legs (ticket + lootbox, fresh + recycled) in ONE call.
    /// @dev GAME-only. Resolves the referral once, accrues each leg at its own scale (fresh/recycled
    ///      bps, taper on the lootbox-fresh leg), rolls ONE winner on the shared (day, senderId, code)
    ///      entropy, and RETURNS the winner credit instead of paying it so the caller batches the
    ///      winner + buyer credits into one Coinflip write:
    ///      `creditFlipPair(senderId, playerKickback, winnerId, winnerCredit)`. The winner is
    ///      rolled among the stored owner and upline IDs, so nothing is decoded.
    /// @param code Referral code supplied with the buy (resolved + locked once).

    /// @param senderId The buyer's wallet ID (seeds the winner roll).
    /// @param lvl Leaderboard level for all legs (ticket and lootbox both freeze at level + 1).
    /// @param tktFreshFlip Ticket-leg fresh spend in FLIP base units.
    /// @param tktRecycledFlip Ticket-leg recycled spend in FLIP base units.
    /// @param lbFreshFlip Lootbox-leg fresh spend in FLIP base units (tapered).
    /// @param lbRecycledFlip Lootbox-leg recycled spend in FLIP base units.
    /// @param lbFreshScore Activity score tapering the lootbox-fresh leg (0 = no taper).
    /// @return winnerId Wallet ID of the single rolled recipient of the pooled affiliate share
    ///         (VAULT 1 or SDGNRS 2, rolled evenly, when the buyer has no referrer); 0 when no
    ///         share accrued.
    /// @return winnerCredit FLIP owed the winner (share + quest reward); 0 if none or
    ///         winnerId == senderId.
    /// @return playerKickback FLIP kickback owed the buyer (summed across legs).
    /// @custom:reverts OnlyAuthorized If caller is not GAME.
    function payAffiliateCombined(
        bytes32 code,
        uint32 senderId,
        uint24 lvl,
        uint256 tktFreshFlip,
        uint256 tktRecycledFlip,
        uint256 lbFreshFlip,
        uint256 lbRecycledFlip,
        uint16 lbFreshScore
    ) external returns (uint32 winnerId, uint256 winnerCredit, uint256 playerKickback);

    /// @notice Permanently refer a fresh smurf to its ordinary main's current gameplay ID.
    /// @dev Game-only; main referral must be resolved, child referral unset. Zero kickback.
    ///      Emits ReferralUpdated with the normalized ID word; no registration or value calls.
    function referSmurf(uint32 ownerId, uint32 smurfId) external;

    /// @notice Settle a batch of afking subs' accrued affiliate base to the upline chain.
    /// @dev Permissionless. All `subs` must resolve to the same direct affiliate `A` (else revert).
    ///      Drains each sub's `affiliateBase` atomically at the Game storage owner, splits the total
    ///      75/20/5 (floored, remainder to A) and pays A / U1 / U2 directly via `creditFlip`; no-referrer
    ///      subs split 50/50 VAULT/sDGNRS. Fixed split (no roll, no seed). Leaderboard credits A once.
    /// @param subs Afking subscribers to settle; all must share the same direct affiliate `A`.
    function claim(uint32[] calldata subs) external;
    function defaultCodeById(uint32 id) external pure returns (bytes32);
    function getReferrerById(uint32 playerId) external view returns (address);
    function getReferrerIdById(uint32 playerId) external view returns (uint32);
    function referrerIdsById(uint32 playerId) external view returns (uint32 affiliate, uint32 upline1, uint32 upline2);

    /// @notice Get the top affiliate for a given game level.
    /// @dev Returns the affiliate with the highest earnings for that level.
    ///      Used to pay the top affiliate a DGNRS pool reward at level transition; the Game
    ///      decodes the ID once per level for that transfer.
    /// @param lvl The game level to query.
    /// @return id Wallet ID of the top affiliate (0 when the level has no leader).
    /// @return score Their score in FLIP base units (0 decimals).
    function affiliateTop(uint24 lvl) external view returns (uint32 id, uint96 score);

    /// @notice Get an affiliate's base earnings score for a level.
    /// @dev Uses direct affiliate earnings only (excludes uplines and quest bonuses).
    /// @param lvl The game level to query.
    /// @param id Wallet ID of the affiliate to query (0 returns 0).
    /// @return score The base affiliate score (0 decimals).
    function affiliateScore(uint24 lvl, uint32 id) external view returns (uint256 score);

    /// @notice Get the total affiliate score across all affiliates for a level.
    /// @param lvl The game level to query.
    /// @return total The total affiliate score (0 decimals).
    function totalAffiliateScore(uint24 lvl) external view returns (uint256 total);

    /// @notice Calculate the affiliate bonus points for a player.
    /// @dev Sums the player's affiliate scores for the previous 5 levels, converted to
    ///      weighted referred ETH volume (score × level ticket price / PRICE_COIN_UNIT,
    ///      normalized by the 20% L4+ fresh reward rate; fresh ≈ 1:1 (levels 0-3 fresh 1.25×),
    ///      recycled 0.25×).
    ///      Awards 4 points per ETH for the first 5 ETH, 1.5 points per ETH for the next 20 ETH, capped at 50.
    ///      Callers hold the ID from the mint word they already read.
    /// @param currLevel The current game level.
    /// @param id Wallet ID of the player to calculate bonus for (0 returns 0).
    /// @return points Bonus points (0 to 50).
    function affiliateBonusPointsBest(uint24 currLevel, uint32 id) external view returns (uint256 points);

    /// @notice Get the referrer address for a player.
    /// @dev Never returns address(0): resolves to the VAULT when the player has no valid
    ///      referrer (code unset, locked, vault-coded, or its owner unresolvable). Chains are
    ///      not acyclic (VAULT and SDGNRS refer each other; mutual player referrals are
    ///      allowed); payouts walk at most two upline hops from the direct referrer.
    /// @param player The player to look up.
    /// @return The referrer's address (the VAULT when the player has no real referrer).
    function getReferrer(address player) external view returns (address);

    /// @notice Get the referrer's wallet ID for a player (ID twin of getReferrer).
    /// @dev View; never allocates. Resolves exactly as getReferrer does: VAULT_WALLET_ID (1)
    ///      when the player has no valid referrer (code unset, locked or vault-coded). Returns 0
    ///      only when the resolved referrer has no wallet ID yet (a bootstrap-code owner whose
    ///      deferred registration has not run); callers treat 0 as "no recipient"
    ///      (`creditFlip(0, ...)` is a no-op).
    /// @param player The player to look up.
    /// @return The referrer's wallet ID.
    function getReferrerId(address player) external view returns (uint32);

    /// @notice The three referrer hops of a player as wallet IDs (deity-pass reward chain).
    /// @dev View; never allocates. Each hop is getReferrerId of the previous hop's wallet:
    ///      `affiliate = getReferrerId(player)`, `upline1` the affiliate's referrer, `upline2`
    ///      upline1's referrer. VAULT (1) and SDGNRS (2) refer each other, so an unreferred
    ///      chain reads (1, 2, 1). A zero hop (referrer without an ID) zeroes every later hop.
    /// @param player The player to look up.
    /// @return affiliate Direct referrer's wallet ID.
    /// @return upline1 The direct referrer's referrer.
    /// @return upline2 upline1's referrer.
    function referrerIds(address player) external view returns (uint32 affiliate, uint32 upline1, uint32 upline2);
}
