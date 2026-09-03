// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameBingoModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling claimBingo color-completion claims.
 * @dev A player who owns one post-RNG-resolved ticket entry in each of the 8 color
 *      buckets of a single symbol on a level may claim one reward for that level:
 *      0.05% Pool.Reward + 1_000e18 FLIP.
 *      All storage reads/writes operate on the inherited DegenerusGameStorage layout.
 *      claimBingo is a strict READ-ONLY consumer of lvlTraitEntry — it adds NO write
 *      to it (RNG-freeze-safe). The only state it writes is
 *      its own per-player/per-level bingoClaimed flag. CEI: the claim flag is set
 *      before interactions (transferFromPool / creditFlip).
 */
contract DegenerusGameBingoModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    error ScoreTooLow(); // Thrown when the player (the claim beneficiary — claims are permissionless, so not necessarily the caller) is not a deity holder and their affiliate score is below AFFILIATE_DGNRS_MIN_SCORE.

    /// @notice Thrown when caller does not own the slot at the cited trait/index,
    ///         or the slot index is out of bounds for that trait's bucket.
    error NotSlotOwner();

    /// @notice Thrown when the symbol is out of range (>= 32).
    error InvalidSymbol();

    /// @notice Thrown when this player has already claimed on this level.
    error AlreadyClaimed();

    // -------------------------------------------------------------------------
    // Reward constants
    // -------------------------------------------------------------------------

    /// @dev sDGNRS draw: 0.05% of Pool.Reward.
    uint256 internal constant BINGO_DGNRS_BPS = 5;

    /// @dev FLIP credit paid for a bingo.
    uint256 internal constant BINGO_FLIP = 1_000e18;

    // -------------------------------------------------------------------------
    // claimAffiliateDgnrs constants
    // -------------------------------------------------------------------------

    /// @dev Bonus FLIP credit for deity-pass affiliate claims: 20% of the claimant's affiliate score, capped (see CAP_ETH).
    uint16 private constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

    /// @dev Max deity bonus per level, denominated in ETH (converted to FLIP at current price).
    uint256 private constant AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH = 5 ether;

    /// @dev Minimum FLIP-basis affiliate score to claim without a deity pass — a dust
    ///      filter; the payout itself is score-proportional, so units cancel there.
    uint256 private constant AFFILIATE_DGNRS_MIN_SCORE = 10 ether;

    // -------------------------------------------------------------------------
    // Events (player-only indexed; amounts/level/symbol non-indexed)
    // -------------------------------------------------------------------------

    /// @notice Universal record emitted on every successful claim, carrying the paid amounts.
    event BingoClaimed(
        address indexed player,
        uint256 level,
        uint8 symbol,
        uint256 flipReward,
        uint256 dgnrsPaid
    );

    /// @notice Emitted when a player claims DGNRS affiliate rewards. Carries the affiliate,
    ///         the level, the calling address, the claimant's frozen affiliate score, and
    ///         the amount paid.
    event AffiliateDgnrsClaimed(
        address indexed affiliate,
        uint24 indexed level,
        address indexed caller,
        uint256 score,
        uint256 amount
    );

    // -------------------------------------------------------------------------
    // claimBingo
    // -------------------------------------------------------------------------

    /// @notice Claim a level's color-completion bingo: all 8 colors of one symbol.
    /// @dev Permissionless: the reward settles to `player` (the slot owner the 8-color check
    ///      verifies), never the caller, so an uninvited claim only ever harvests inward.
    ///      Each player may claim at most once per level, regardless of which qualifying
    ///      symbol they use.
    /// @param player The bingo owner to claim for (address(0) = msg.sender).
    /// @param level The level to claim on (uint24 — the internal storage key width;
    ///        the ABI decoder fail-closes on an oversized value, no truncation).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in lvlTraitEntry[level][traitId] the owner occupies.
    function claimBingo(address player, uint24 level, uint8 symbol, uint32[8] calldata slots) external {
        // Permissionless: a settled claim only ever credits the slot owner, never the caller.
        if (player == address(0)) player = msg.sender;
        // ---- Validation (gameOver hard cutoff + range gates) ----
        // No level upper-bound guard: the 8-color ownership check below is
        // self-gating — an unresolved/future-level bucket is empty, so the
        // require fails closed on its own. claimBingo only READS lvlTraitEntry
        // (never writes it) and writes only its own claim flag, so a read
        // against an in-flight/future bucket simply reverts; it cannot corrupt
        // VRF state (freeze-safe; no level gate is needed).
        if (gameOver) revert GameOver();
        if (symbol >= 32) revert InvalidSymbol();
        if (bingoClaimed[level][player]) revert AlreadyClaimed();

        uint8 quadrant = symbol >> 3; // bits 7-6 of the trait byte
        uint8 symInQ = symbol & 7; // bits 2-0 of the trait byte

        // ---- Ownership read (READ-ONLY; NO write to lvlTraitEntry) ----
        // For each color c the owner must occupy occurrence slots[c] in the bucket of
        // traitId = (quadrant << 6) | (c << 3) | symInQ. Guard the index against the
        // array length BEFORE the read so a bad index fails closed with one clean
        // custom error (no bare Panic(0x32)).
        uint256[][256] storage levelBuckets = lvlTraitEntry[level];
        uint256 traitBase = (uint256(quadrant) << 6) | uint256(symInQ);
        for (uint256 c = 0; c < 8; ) {
            uint8 traitId = uint8(traitBase | (c << 3));
            uint256 slot = slots[c];
            if (
                slot >= levelBuckets[traitId].length ||
                _bucketOwnerAt(level, traitId, slot) != player
            ) {
                revert NotSlotOwner();
            }
            unchecked {
                ++c;
            }
        }

        // ---- Per-player/per-level dedup (EFFECT) ----
        bingoClaimed[level][player] = true;

        // ---- Interactions (after all effects) ----
        // sDGNRS draw: transferFromPool clamps to the available Reward pool and
        // returns the actual amount paid. An empty/0 pool is a graceful no-op
        // (dgnrsPaid == 0, no revert; the claim stays set and FLIP is still credited).
        uint256 poolBal = dgnrs.poolBalance(IsDGNRS.Pool.Reward);
        uint256 dgnrsPaid = dgnrs.transferFromPool(
            IsDGNRS.Pool.Reward,
            player,
            (poolBal * BINGO_DGNRS_BPS) / 10_000
        );

        // FLIP credit is always paid, even when the Reward pool is empty.
        coinflip.creditFlip(player, BINGO_FLIP);

        emit BingoClaimed(player, level, symbol, BINGO_FLIP, dgnrsPaid);
    }

    // -------------------------------------------------------------------------
    // claimAffiliateDgnrs — the body lives here; the Game keeps a thin delegatecall
    // dispatch stub shaped like claimBingo. It is reached via the Game's
    // delegatecall (so the outbound msg.sender to SDGNRS / coinflip is GAME, which
    // both transferFromPool [onlyGame] and creditFlip [onlyFlipCreditors] require);
    // a direct call to this module address would revert at those gates.
    // -------------------------------------------------------------------------

    /// @notice Claim DGNRS affiliate rewards for the current level.
    /// @dev Requires a minimum affiliate score and allows one claim per level.
    ///      Draws from a segregated allocation (5% of the affiliate pool snapshotted
    ///      at level transition). All claimants for the same level share a fixed pot,
    ///      eliminating first-mover advantage. Uses totalAffiliateScore as the exact
    ///      denominator for score-proportional distribution.
    ///      Affiliate scores always route to level + 1 during gameplay, so at
    ///      transition time all scores for currLevel are frozen and immutable.
    /// @dev Permissionless: the reward is deterministic (frozen score / fixed pot, no timing
    ///      edge) and credits the affiliate, so any caller may settle any affiliate's claim.
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external {
        // Permissionless: a settled claim only ever credits the affiliate, never the caller.
        if (player == address(0)) player = msg.sender;

        uint24 currLevel = level;
        if (currLevel == 0) revert NotStarted();

        if (affiliateDgnrsClaimedBy[currLevel][player]) revert AlreadyClaimed();

        uint256 score = affiliate.affiliateScore(currLevel, player);
        bool isDeityHolder = mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        if (!isDeityHolder && score < AFFILIATE_DGNRS_MIN_SCORE) revert ScoreTooLow();

        uint256 denominator = affiliate.totalAffiliateScore(currLevel);
        if (denominator == 0) revert ZeroValue();

        (uint256 allocation, ) = _getLevelDgnrs(currLevel);
        if (allocation == 0) revert ZeroValue();
        uint256 reward = (allocation * score) / denominator;
        if (reward == 0) revert ZeroValue();

        uint256 paid = dgnrs.transferFromPool(
            IsDGNRS.Pool.Affiliate,
            player,
            reward
        );
        if (paid == 0) revert NothingToClaim();

        _addLevelDgnrsClaimed(currLevel, paid);

        // score != 0 is guaranteed here: reward = (allocation * score) / denominator
        // reverted above when reward == 0, which a zero score would force.
        if (isDeityHolder) {
            uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;
            uint256 cap = (AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH *
                PRICE_COIN_UNIT) / PriceLookupLib.priceForLevel(currLevel);
            if (bonus > cap) {
                bonus = cap;
            }
            if (bonus != 0) {
                coinflip.creditFlip(player, bonus);
            }
        }

        affiliateDgnrsClaimedBy[currLevel][player] = true;
        emit AffiliateDgnrsClaimed(player, currLevel, msg.sender, score, paid);
    }
}
