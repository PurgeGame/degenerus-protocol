// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

/**
 * @title DegenerusGameBingoModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling claimBingo color-completion claims (v51.0).
 * @dev A player who owns one post-RNG-resolved ticket entry in each of the 8 color
 *      buckets of a single symbol on a level may claim a tiered reward:
 *        - regular         (0.05% Pool.Reward + 1_000e18 BURNIE),
 *        - symbol-first     (additive: 0.1% + 2_000e18 BURNIE),
 *        - quadrant-first   (replacement: 0.5% + 5_000e18 BURNIE, suppresses symbol bonus).
 *      All storage reads/writes operate on the inherited DegenerusGameStorage layout.
 *      claimBingo is a strict READ-ONLY consumer of traitBurnTicket — it adds NO write
 *      to it (RNG-freeze-safe per 339-BINGO06-FREEZE-PROOF). The only state it writes is
 *      its own three bitfields (bingoClaimed / firstQuadrant / firstSymbol). CEI:
 *      effects (the bit sets) precede interactions (transferFromPool / creditFlip).
 */
contract DegenerusGameBingoModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
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

    // -------------------------------------------------------------------------
    // Reward constants (transcribed VERBATIM from 339-DESIGN-LOCK-BINGO §5)
    // -------------------------------------------------------------------------

    /// @dev Baseline sDGNRS draw: 0.05% of Pool.Reward.
    uint256 internal constant REGULAR_DGNRS_BPS = 5;
    /// @dev Symbol-first bonus sDGNRS: +0.05% ADDED to regular (-> 0.1% total).
    uint256 internal constant FIRST_SYMBOL_BONUS_DGNRS_BPS = 5;
    /// @dev Quadrant-first sDGNRS: 0.5% REPLACEMENT (supersedes regular + symbol bonus).
    uint256 internal constant FIRST_QUADRANT_DGNRS_BPS = 50;

    /// @dev Baseline BURNIE flip credit.
    uint256 internal constant REGULAR_BURNIE = 1_000e18;
    /// @dev Symbol-first bonus BURNIE: ADDED to regular (-> 2_000e18 total).
    uint256 internal constant FIRST_SYMBOL_BONUS_BURNIE = 1_000e18;
    /// @dev Quadrant-first BURNIE: REPLACES regular + symbol bonus.
    uint256 internal constant FIRST_QUADRANT_BURNIE = 5_000e18;

    // -------------------------------------------------------------------------
    // Events (D-340-01: player-only indexed; amounts/level/symbol non-indexed)
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
        uint256 burnieReward,
        uint256 dgnrsPaid
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
        // ---- Validation (D-08 hard cutoff + range gates) ----
        // No level upper-bound guard: the 8-color ownership check below is
        // self-gating — an unresolved/future-level bucket is empty, so the
        // require fails closed on its own. claimBingo only READS traitBurnTicket
        // (never writes it) and writes only its own 3 bitfields, so a read
        // against an in-flight/future bucket simply reverts; it cannot corrupt
        // VRF state (freeze-safe; 339-BINGO06 re-attested without the level gate).
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
        for (uint256 c = 0; c < 8; ) {
            uint8 traitId = uint8((uint256(quadrant) << 6) | (c << 3) | uint256(symInQ));
            address[] storage holders = traitBurnTicket[level][traitId];
            uint256 slot = slots[c];
            if (slot >= holders.length || holders[slot] != msg.sender) {
                revert NotSlotOwner();
            }
            unchecked {
                ++c;
            }
        }

        // ---- Per-player (level, quadrant) dedup (EFFECT) ----
        if (bingoClaimed[level][msg.sender] & qMask != 0) revert AlreadyClaimed();
        bingoClaimed[level][msg.sender] |= qMask;

        // ---- Tier cascade (EFFECTS — bits set before any external call) ----
        // Quadrant-first is checked BEFORE symbol-first (the binding ordering,
        // 339-TIER-PRECEDENCE §2). A quadrant-first marks BOTH bits — the
        // double-pay-trap guard (§4) — and suppresses the symbol-first bonus.
        bool isQuadrantFirst = (firstQuadrant[level] & qMask) == 0;
        bool isSymbolFirst = (firstSymbol[level] & sMask) == 0;

        uint256 dgnrsBps;
        uint256 burnie;
        if (isQuadrantFirst) {
            firstQuadrant[level] |= qMask;
            firstSymbol[level] |= sMask; // BOTH bits — closes the double-pay window
            dgnrsBps = FIRST_QUADRANT_DGNRS_BPS;
            burnie = FIRST_QUADRANT_BURNIE;
            emit FirstQuadrantBingo(msg.sender, level, symbol);
        } else if (isSymbolFirst) {
            firstSymbol[level] |= sMask;
            dgnrsBps = REGULAR_DGNRS_BPS + FIRST_SYMBOL_BONUS_DGNRS_BPS;
            burnie = REGULAR_BURNIE + FIRST_SYMBOL_BONUS_BURNIE;
            emit FirstSymbolBingo(msg.sender, level, symbol);
        } else {
            dgnrsBps = REGULAR_DGNRS_BPS;
            burnie = REGULAR_BURNIE;
        }

        // ---- Interactions (after all effects) ----
        // sDGNRS draw: transferFromPool clamps to the available Reward pool and
        // returns the actual amount paid. An empty/0 pool is a graceful no-op
        // (dgnrsPaid == 0, no revert; bits stay set and BURNIE is still credited).
        uint256 poolBal = dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward);
        uint256 dgnrsPaid = dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Reward,
            msg.sender,
            (poolBal * dgnrsBps) / 10_000
        );

        // BURNIE flip credit (always paid; tier amount is always non-zero).
        coinflip.creditFlip(msg.sender, burnie);

        emit BingoClaimed(msg.sender, level, symbol, burnie, dgnrsPaid);
    }
}
