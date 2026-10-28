// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev Shared internal implementation in Game storage.
abstract contract GameBingo is DegenerusGameStorage {
    /// @notice Thrown when the player (the claim beneficiary — claims are permissionless, so not
    ///         necessarily the caller) is not a deity holder and their affiliate score is below
    ///         AFFILIATE_DGNRS_MIN_SCORE.
    error ScoreTooLow();

    /// @notice Thrown when the claim beneficiary (`player`, not necessarily the caller) does
    ///         not own the slot at the cited trait/index, or the slot index is out of bounds
    ///         for that trait's bucket.
    error NotSlotOwner();

    /// @notice Thrown when the symbol is out of range (>= 32).
    error InvalidSymbol();

    /// @notice Thrown when this account has already claimed this level's bingo or affiliate reward.
    error AlreadyClaimed();

    /// @notice Thrown when a later same-parity level has taken over the claimed level's ticket
    ///         buffer.
    error BingoExpired();

    /// @dev sDGNRS draw: 0.05% of Pool.Reward.
    uint256 internal constant BINGO_DGNRS_BPS = 5;

    /// @dev FLIP credit paid for a bingo.
    uint256 internal constant BINGO_FLIP = 1_000;

    /// @dev Bonus FLIP credit for deity-pass affiliate claims: 20% of the claimant's affiliate
    ///      score, capped by AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH.
    uint16 internal constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

    /// @dev Max deity bonus per level, denominated in ETH (converted to FLIP at current price).
    uint256 internal constant AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH = 5 ether;

    /// @dev Minimum FLIP-basis affiliate score to claim without a deity pass — a dust
    ///      filter; the payout itself is score-proportional, so units cancel there.
    uint256 internal constant AFFILIATE_DGNRS_MIN_SCORE = 10;

    /// @notice Universal record emitted on every successful claim, carrying the paid amounts.
    event BingoClaimed(
        uint32 indexed player,
        uint256 level,
        uint8 symbol,
        uint256 flipReward,
        uint256 dgnrsPaid
    );

    /// @notice Emitted when a player claims DGNRS affiliate rewards. Carries the affiliate,
    ///         the level, the calling address, the claimant's frozen affiliate score, and
    ///         the amount paid.
    event AffiliateDgnrsClaimed(
        uint32 indexed affiliate,
        uint24 indexed level,
        address indexed caller,
        uint256 score,
        uint256 amount
    );

    /// @notice Claim a level's color-completion bingo: all 8 colors of one symbol.
    /// @dev Permissionless: the reward settles to account `id` (the slot owner the 8-color
    ///      check verifies), never the caller, so an uninvited claim only ever harvests inward;
    ///      the DGNRS leg goes to the account's payee. Each account may claim at most once per
    ///      level, regardless of which qualifying symbol it uses. A level's bingo remains
    ///      claimable until L+2 takes over its parity ticket buffer; starting the next level
    ///      alone does not expire it.
    /// @param id The bingo owner to claim for (0 = caller, which must hold an ID; otherwise allocated).
    /// @param lvl The level to claim on (uint24 — the internal storage key width;
    ///        the ABI decoder fail-closes on an oversized value, no truncation).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in the level's trait buckets that the owner occupies.
    /// @custom:reverts BingoExpired If a later same-parity level has taken over the ticket buffer.
    function _claimBingo(uint32 id, uint24 lvl, uint8 symbol, uint32[8] calldata slots) internal {
        // Permissionless: a settled claim only ever credits the slot owner, never the caller.
        // Bucket lanes hold wallet IDs; a caller with no ID owns no slot.
        uint32 playerId = _creditAccountId(id);
        // A self claim pays the caller: its ID is its own ordinary main.
        address payee = id == 0 ? msg.sender : _payee(_walletElement(playerId));
        // ---- Validation (gameOver hard cutoff + range gates) ----
        // No level upper-bound guard: the 8-color ownership check below is the gate —
        // an unmaterialized bucket is empty and fails it, while a bucket the sweep has
        // already filled for a future level qualifies on ownership alone. _claimBingo
        // only READS the trait buckets (never writes them) and writes only its own claim flag,
        // so this cannot corrupt VRF state (freeze-safe). The only level gate is the expiry:
        // a level's bingo closes when L+2 actually takes over its ticket buffer.
        if (gameOver) revert GameOver();
        if (_ticketLevelRetired(lvl)) revert BingoExpired();
        if (symbol >= 32) revert InvalidSymbol();
        if (_bingoClaimed(lvl, playerId)) revert AlreadyClaimed();

        uint8 quadrant = symbol >> 3; // bits 7-6 of the trait byte
        uint8 symInQ = symbol & 7; // bits 2-0 of the trait byte

        // ---- Ownership read (read-only; no write to the trait buckets) ----
        // For each color c the owner must occupy occurrence slots[c] in the bucket of
        // traitId = (quadrant << 6) | (c << 3) | symInQ. Guard the index against the
        // array length BEFORE the read so a bad index fails closed with one clean
        // custom error (no bare Panic(0x32)).
        uint256 traitBase = (uint256(quadrant) << 6) | uint256(symInQ);
        for (uint256 c = 0; c < 8; ) {
            uint8 traitId = uint8(traitBase | (c << 3));
            uint256 slot = slots[c];
            if (
                slot >= _bucketLength(lvl, traitId) ||
                _bucketIdAtUnchecked(lvl, traitId, slot) != playerId
            ) {
                revert NotSlotOwner();
            }
            unchecked {
                ++c;
            }
        }

        // ---- Per-player/per-level dedup (EFFECT) ----
        _markBingoClaimed(lvl, playerId);

        // ---- Interactions (after all effects) ----
        // sDGNRS draw: transferFromPool_g106128 clamps to the available Reward pool and
        // returns the actual amount paid. An empty/0 pool is a graceful no-op
        // (dgnrsPaid == 0, no revert; the claim stays set and FLIP is still credited).
        uint256 poolBal = dgnrs.poolBalance(IsDGNRS.Pool.Reward);
        uint256 dgnrsPaid = dgnrs.transferFromPool_g106128(
            IsDGNRS.Pool.Reward,
            payee,
            (poolBal * BINGO_DGNRS_BPS) / 10_000
        );

        // FLIP credit is always paid, even when the Reward pool is empty.
        coinflip.creditFlip_g317(playerId, BINGO_FLIP);

        emit BingoClaimed(playerId, lvl, symbol, BINGO_FLIP, dgnrsPaid);
    }

    /// @notice Claim DGNRS affiliate rewards for the current level.
    /// @dev Requires a minimum affiliate score and allows one claim per level.
    ///      Draws from a segregated allocation (2.5% of the affiliate pool snapshotted
    ///      at level transition). All claimants for the same level share a fixed pot,
    ///      eliminating first-mover advantage. Uses totalAffiliateScore as the exact
    ///      denominator for score-proportional distribution.
    ///      Affiliate scores always route to level + 1 during gameplay, so at
    ///      transition time all scores for currLevel are frozen and immutable.
    /// @dev Permissionless: the reward is deterministic (frozen score / fixed pot, no timing
    ///      edge) and credits the affiliate, so any caller may settle any affiliate's claim.
    ///      The DGNRS leg goes to the account's payee; the FLIP bonus credits the account by ID.
    /// @param id Affiliate account to claim for (0 = caller; otherwise allocated).
    function _claimAffiliateDgnrs(uint32 id) internal {
        // Permissionless: a settled claim only ever credits the affiliate, never the caller.
        uint32 playerId = id == 0 ? _walletIdOf(msg.sender) : _creditAccountId(id);
        // A self claim pays the caller: its ID is its own ordinary main.
        address payee = id == 0 ? msg.sender : _payee(_walletElement(playerId));

        uint24 currLevel = level;
        if (currLevel == 0) revert NotStarted();

        uint256 word = mintPacked_[playerId];
        // Every affiliate registered when its code was first used; no ID means no score.
        if (playerId == 0) revert ScoreTooLow();
        if (_affiliateDgnrsClaimed(currLevel, playerId)) revert AlreadyClaimed();

        (uint256 score, uint256 denominator) = affiliate.affiliateScoreAndTotal_g4013(currLevel, playerId);
        bool isDeityHolder = word >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        if (!isDeityHolder && score < AFFILIATE_DGNRS_MIN_SCORE) revert ScoreTooLow();

        if (denominator == 0) revert ZeroValue();

        (uint256 allocation, ) = _getLevelDgnrs(currLevel);
        if (allocation == 0) revert ZeroValue();
        uint256 reward = (allocation * score) / denominator;
        if (reward == 0) revert ZeroValue();

        // Mark before interactions. A failed transfer reverts the stamp; a callback cannot
        // replay this claim or be overwritten by a stale copy of the shared bingo word.
        _markAffiliateDgnrsClaimed(currLevel, playerId);
        uint256 paid = dgnrs.transferFromPool_g106128(
            IsDGNRS.Pool.Affiliate,
            payee,
            reward
        );
        if (paid == 0) revert NothingToClaim();

        _addLevelDgnrsClaimed(paid);

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
                coinflip.creditFlip_g317(playerId, bonus);
            }
        }

        emit AffiliateDgnrsClaimed(playerId, currLevel, msg.sender, score, paid);
    }
}
