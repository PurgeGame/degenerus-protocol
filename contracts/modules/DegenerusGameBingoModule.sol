// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameBingoModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling claimBingo color-completion claims.
 * @dev A player who owns one post-RNG-resolved ticket entry in each of the 8 color
 *      buckets of a single symbol on a level may claim a tiered reward:
 *        - regular         (0.05% Pool.Reward + 1_000e18 FLIP),
 *        - symbol-first     (additive: 0.1% + 2_000e18 FLIP),
 *        - quadrant-first   (replacement: 0.5% + 5_000e18 FLIP, suppresses symbol bonus).
 *      All storage reads/writes operate on the inherited DegenerusGameStorage layout.
 *      claimBingo is a strict READ-ONLY consumer of traitBurnTicket — it adds NO write
 *      to it (RNG-freeze-safe). The only state it writes is
 *      its own bitfields (bingoClaimed / bingoFirsts). CEI:
 *      effects (the bit sets) precede interactions (transferFromPool / creditFlip).
 */
contract DegenerusGameBingoModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    /// @notice Thrown when caller does not own the slot at the cited trait/index,
    ///         or the slot index is out of bounds for that trait's holder array.
    error NotSlotOwner();

    /// @notice Thrown when the symbol is out of range (>= 32).
    error InvalidSymbol();

    /// @notice Thrown when this player has already claimed this (level, quadrant).
    error AlreadyClaimed();

    /// @notice Thrown when msg.sender is neither the player nor an approved operator.
    error NotApproved();

    // -------------------------------------------------------------------------
    // Reward constants
    // -------------------------------------------------------------------------

    /// @dev Baseline sDGNRS draw: 0.05% of Pool.Reward.
    uint256 internal constant REGULAR_DGNRS_BPS = 5;
    /// @dev Symbol-first bonus sDGNRS: +0.05% ADDED to regular (-> 0.1% total).
    uint256 internal constant FIRST_SYMBOL_BONUS_DGNRS_BPS = 5;
    /// @dev Quadrant-first sDGNRS: 0.5% REPLACEMENT (supersedes regular + symbol bonus).
    uint256 internal constant FIRST_QUADRANT_DGNRS_BPS = 50;

    /// @dev Baseline FLIP flip credit.
    uint256 internal constant REGULAR_FLIP = 1_000e18;
    /// @dev Symbol-first bonus FLIP: ADDED to regular (-> 2_000e18 total).
    uint256 internal constant FIRST_SYMBOL_BONUS_FLIP = 1_000e18;
    /// @dev Quadrant-first FLIP: REPLACES regular + symbol bonus.
    uint256 internal constant FIRST_QUADRANT_FLIP = 5_000e18;

    // -------------------------------------------------------------------------
    // claimAffiliateDgnrs constants
    // -------------------------------------------------------------------------

    /// @dev Bonus FLIP flip credit for deity pass affiliate claims (20% of payout).
    uint16 private constant AFFILIATE_DGNRS_DEITY_BONUS_BPS = 2000;

    /// @dev Max deity bonus per level, denominated in ETH (converted to FLIP at current price).
    uint256 private constant AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH = 5 ether;

    /// @dev Minimum affiliate score (approx 10 ETH of referral volume).
    uint256 private constant AFFILIATE_DGNRS_MIN_SCORE = 10 ether;

    // -------------------------------------------------------------------------
    // Events (player-only indexed; amounts/level/symbol non-indexed)
    // -------------------------------------------------------------------------

    /// @notice Emitted on a quadrant-first claim (the systemwide first bingo for a quadrant).
    event FirstQuadrantBingo(address indexed player, uint256 level, uint8 symbol);

    /// @notice Emitted on a symbol-first (non-quadrant-first) claim.
    event FirstSymbolBingo(address indexed player, uint256 level, uint8 symbol);

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

    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @param level The level to claim on (uint24 — the internal storage key width;
    ///        the ABI decoder fail-closes on an oversized value, no truncation).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in traitBurnTicket[level][traitId] the caller occupies.
    function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external {
        // ---- Validation (gameOver hard cutoff + range gates) ----
        // No level upper-bound guard: the 8-color ownership check below is
        // self-gating — an unresolved/future-level bucket is empty, so the
        // require fails closed on its own. claimBingo only READS traitBurnTicket
        // (never writes it) and writes only its own 3 bitfields, so a read
        // against an in-flight/future bucket simply reverts; it cannot corrupt
        // VRF state (freeze-safe; no level gate is needed).
        if (gameOver) revert E();
        if (symbol >= 32) revert InvalidSymbol();

        uint8 quadrant = symbol >> 3; // bits 7-6 of the trait byte
        uint8 symInQ = symbol & 7; // bits 2-0 of the trait byte
        uint8 qMask = uint8(1 << quadrant);
        uint32 sMask = uint32(1) << symbol;

        // ---- Ownership read (READ-ONLY; NO write to traitBurnTicket) ----
        // For each color c the caller must occupy slots[c] in the holder array of
        // traitId = (quadrant << 6) | (c << 3) | symInQ. Guard the index against the
        // array length BEFORE the read so a bad index fails closed with one clean
        // custom error (no bare Panic(0x32)).
        address[][256] storage levelBuckets = traitBurnTicket[level];
        uint256 traitBase = (uint256(quadrant) << 6) | uint256(symInQ);
        for (uint256 c = 0; c < 8; ) {
            address[] storage holders = levelBuckets[uint8(traitBase | (c << 3))];
            uint256 slot = slots[c];
            if (slot >= holders.length || holders[slot] != msg.sender) {
                revert NotSlotOwner();
            }
            unchecked {
                ++c;
            }
        }

        // ---- Per-player (level, quadrant) dedup (EFFECT) ----
        uint8 claimedBits = bingoClaimed[level][msg.sender];
        if (claimedBits & qMask != 0) revert AlreadyClaimed();
        bingoClaimed[level][msg.sender] = claimedBits | qMask;

        // ---- Tier cascade (EFFECTS — bits set before any external call) ----
        // Quadrant-first is checked BEFORE symbol-first (the binding ordering).
        // A quadrant-first marks BOTH bits — the double-pay-trap guard — and
        // suppresses the symbol-first bonus.
        uint64 bf = bingoFirsts[level];
        uint8 fq = uint8(bf >> 32); // quadrant mask in bits [32:36)
        uint32 fs = uint32(bf); // symbol mask in bits [0:32)
        bool isQuadrantFirst = (fq & qMask) == 0;
        bool isSymbolFirst = (fs & sMask) == 0;

        uint256 dgnrsBps;
        uint256 flip;
        if (isQuadrantFirst) {
            // BOTH bits — closes the double-pay window — in one packed write
            bingoFirsts[level] =
                uint64(uint32(fs | sMask)) |
                (uint64(uint8(fq | qMask)) << 32);
            dgnrsBps = FIRST_QUADRANT_DGNRS_BPS;
            flip = FIRST_QUADRANT_FLIP;
            emit FirstQuadrantBingo(msg.sender, level, symbol);
        } else if (isSymbolFirst) {
            // mark only the symbol bit, preserving the co-resident quadrant mask
            bingoFirsts[level] = (bf & ~uint64(0xFFFFFFFF)) | uint64(fs | sMask);
            dgnrsBps = REGULAR_DGNRS_BPS + FIRST_SYMBOL_BONUS_DGNRS_BPS;
            flip = REGULAR_FLIP + FIRST_SYMBOL_BONUS_FLIP;
            emit FirstSymbolBingo(msg.sender, level, symbol);
        } else {
            dgnrsBps = REGULAR_DGNRS_BPS;
            flip = REGULAR_FLIP;
        }

        // ---- Interactions (after all effects) ----
        // sDGNRS draw: transferFromPool clamps to the available Reward pool and
        // returns the actual amount paid. An empty/0 pool is a graceful no-op
        // (dgnrsPaid == 0, no revert; bits stay set and FLIP is still credited).
        uint256 poolBal = dgnrs.poolBalance(IsDGNRS.Pool.Reward);
        uint256 dgnrsPaid = dgnrs.transferFromPool(
            IsDGNRS.Pool.Reward,
            msg.sender,
            (poolBal * dgnrsBps) / 10_000
        );

        // FLIP flip credit (always paid; tier amount is always non-zero).
        coinflip.creditFlip(msg.sender, flip);

        emit BingoClaimed(msg.sender, level, symbol, flip, dgnrsPaid);
    }

    // -------------------------------------------------------------------------
    // claimAffiliateDgnrs — the body lives here; the Game keeps a thin delegatecall
    // dispatch stub shaped like claimBingo. It is reached via the Game's
    // delegatecall (so the outbound msg.sender to SDGNRS / coinflip is GAME, which
    // both transferFromPool [onlyGame] and creditFlip [onlyFlipCreditors] require);
    // a direct call to this module address would revert at those gates. The private
    // caller-resolution helper (_resolvePlayer) travels with it (operatorApprovals
    // is inherited from DegenerusGameStorage).
    // -------------------------------------------------------------------------

    /// @notice Claim DGNRS affiliate rewards for the current level.
    /// @dev Requires a minimum affiliate score and allows one claim per level.
    ///      Draws from a segregated allocation (5% of the affiliate pool snapshotted
    ///      at level transition). All claimants for the same level share a fixed pot,
    ///      eliminating first-mover advantage. Uses totalAffiliateScore as the exact
    ///      denominator for score-proportional distribution.
    ///      Affiliate scores always route to level + 1 during gameplay, so at
    ///      transition time all scores for currLevel are frozen and immutable.
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external {
        player = _resolvePlayer(player);

        uint24 currLevel = level;
        if (currLevel == 0) revert E();

        if (affiliateDgnrsClaimedBy[currLevel][player]) revert E();

        uint256 score = affiliate.affiliateScore(currLevel, player);
        bool isDeityHolder = mintPacked_[player] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0;
        if (!isDeityHolder && score < AFFILIATE_DGNRS_MIN_SCORE) revert E();

        uint256 denominator = affiliate.totalAffiliateScore(currLevel);
        if (denominator == 0) revert E();

        (uint256 allocation, ) = _getLevelDgnrs(currLevel);
        if (allocation == 0) revert E();
        uint256 reward = (allocation * score) / denominator;
        if (reward == 0) revert E();

        uint256 paid = dgnrs.transferFromPool(
            IsDGNRS.Pool.Affiliate,
            player,
            reward
        );
        if (paid == 0) revert E();

        _addLevelDgnrsClaimed(currLevel, paid);

        // score != 0 is guaranteed here: reward = (allocation * score) / denominator
        // reverted above when reward == 0, which a zero score would force.
        if (isDeityHolder) {
            uint256 bonus = (score * AFFILIATE_DGNRS_DEITY_BONUS_BPS) / 10_000;
            uint256 cap = (AFFILIATE_DGNRS_DEITY_BONUS_CAP_ETH *
                PRICE_COIN_UNIT) / PriceLookupLib.priceForLevel(level);
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

    /// @dev Resolve a player argument: address(0) -> msg.sender; otherwise require
    ///      msg.sender is the player or an approved operator. Relocated with
    ///      claimAffiliateDgnrs (the Game retains its own copies for other callers).
    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
        return player;
    }
}
