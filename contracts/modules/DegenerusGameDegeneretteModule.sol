// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @notice Minimal interface for WWXRP game burn/mint operations.
interface IWrappedWrappedXRP {
    /// @notice Mints WWXRP tokens as a prize to the recipient.
    /// @param to The address to receive the minted tokens.
    /// @param amount The amount of tokens to mint.
    function mintPrize(address to, uint256 amount) external;

    /// @notice Burns WWXRP tokens from a player for game participation.
    /// @param from The address to burn tokens from.
    /// @param amount The amount of tokens to burn.
    function burnForGame(address from, uint256 amount) external;
}

/**
 * @title DegenerusGameDegeneretteModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling Degenerette symbol-roll bets.
 * @dev Uses lootbox RNG index/word for randomness. All storage reads/writes operate
 *      on the inherited DegenerusGameStorage. Supports ETH, BURNIE, and WWXRP currencies.
 */
contract DegenerusGameDegeneretteModule is
    DegenerusGamePayoutUtils,
    DegenerusGameMintStreakUtils
{
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage

    /// @notice Thrown when RNG word is not yet available for bet resolution.
    error RngNotReady();

    /// @notice Thrown when caller is not approved to act on behalf of player.
    error NotApproved();

    /// @notice Thrown when bet parameters are invalid (zero amount, below minimum, invalid spec, etc.).
    error InvalidBet();

    /// @notice Thrown when an unsupported currency type is specified.
    error UnsupportedCurrency();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a bet is placed (either mode).
    /// @param player The address that placed the bet.
    /// @param index The lootbox RNG index this bet is tied to.
    /// @param betId The unique bet identifier for this player.
    /// @param packed The packed bet data.
    event BetPlaced(
        address indexed player,
        uint32 indexed index,
        uint64 indexed betId,
        uint256 packed
    );

    /// @notice Emitted when Full Ticket bets are resolved.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param ticketCount Number of spins resolved.
    /// @param totalPayout Total payout across all tickets.
    /// @param resultTicket The spin-0 result ticket (additional spin results are derived per spinIndex).
    event FullTicketResolved(
        address indexed player,
        uint64 indexed betId,
        uint8 ticketCount,
        uint256 totalPayout,
        uint32 resultTicket
    );

    /// @notice Emitted for each individual Full Ticket result.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param ticketIndex Index of this ticket (0 to count-1).
    /// @param playerTicket The player's ticket traits.
    /// @param matches Number of attribute matches (0-8).
    /// @param payout Payout for this ticket.
    event FullTicketResult(
        address indexed player,
        uint64 indexed betId,
        uint8 ticketIndex,
        uint32 playerTicket,
        uint8 matches,
        uint256 payout
    );

    /// @notice Emitted when ETH payout exceeds pool cap and excess is converted to lootbox.
    /// @param player The player address.
    /// @param cappedEthPayout The ETH payout after capping.
    /// @param excessConverted The excess ETH value converted to lootbox rewards.
    event PayoutCapped(
        address indexed player,
        uint256 cappedEthPayout,
        uint256 excessConverted
    );

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Reverts with the provided reason bytes from a delegatecall failure.
    /// @param reason The revert reason bytes from the failed call.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Reverts if msg.sender is not the player and not an approved operator.
    /// @param player The player address to check approval for.
    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    /// @dev Resolves the player address, defaulting to msg.sender if zero address is passed.
    ///      Validates operator approval if player differs from msg.sender.
    /// @param player The player address (or zero for msg.sender).
    /// @return resolved The resolved player address.
    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) {
            _requireApproved(player);
        }
        return player;
    }

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    /// @dev Reference to the WWXRP token contract for burn/mint operations.
    IWrappedWrappedXRP internal constant wwxrp =
        IWrappedWrappedXRP(ContractAddresses.WWXRP);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Activity score threshold for mid-tier ROI (75% in bps).
    uint16 private constant ACTIVITY_SCORE_MID_BPS = 7_500;

    /// @dev Activity score threshold for high-tier ROI (255% in bps).
    uint16 private constant ACTIVITY_SCORE_HIGH_BPS = 25_500;

    /// @dev Maximum activity score cap (305% in bps, deity pass theoretical max).
    uint16 private constant ACTIVITY_SCORE_MAX_BPS = 30_500;

    /// @dev Minimum ROI in basis points (90%).
    uint16 private constant ROI_MIN_BPS = 9_000;

    /// @dev Mid-tier ROI in basis points (95%).
    uint16 private constant ROI_MID_BPS = 9_500;

    /// @dev High-tier ROI in basis points (99.5%).
    uint16 private constant ROI_HIGH_BPS = 9_950;

    /// @dev Maximum ROI in basis points (99.9%).
    uint16 private constant ROI_MAX_BPS = 9_990;

    /// @dev Bonus ROI for ETH bets in basis points (+5%), redistributed to high buckets.
    uint16 private constant ETH_ROI_BONUS_BPS = 500;

    /// @dev WWXRP high-value ROI base in basis points (90%).
    ///      Used as the target ROI for full-ticket bonus redistribution
    ///      (matches 5-8 + jackpot).
    uint16 private constant WWXRP_HIGH_ROI_BASE_BPS = 9_000;

    /// @dev WWXRP high-value ROI max in basis points (109.9%).
    uint16 private constant WWXRP_HIGH_ROI_MAX_BPS = 10_990;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IStakedDegenerusStonk private constant sdgnrs =
        IStakedDegenerusStonk(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool)
    uint16 private constant DEGEN_DGNRS_6_BPS = 400; // 4% per ETH
    uint16 private constant DEGEN_DGNRS_7_BPS = 800; // 8% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 1500; // 15% per ETH

    /// @dev Currency type identifier for ETH.
    uint8 private constant CURRENCY_ETH = 0;

    /// @dev Currency type identifier for BURNIE token.
    uint8 private constant CURRENCY_BURNIE = 1;

    /// @dev Currency type identifier for WWXRP token.
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev Minimum bet amount for ETH (0.005 ETH on mainnet).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;

    /// @dev Minimum bet amount for BURNIE (100 tokens with 18 decimals).
    uint256 private constant MIN_BET_BURNIE = 100 ether;

    /// @dev Minimum bet amount for WWXRP (1 token with 18 decimals).
    uint256 private constant MIN_BET_WWXRP = 1 ether;

    /// @dev Maximum spins per bet (encoded as ticketCount in packed bet).
    uint8 private constant MAX_SPINS_PER_BET = 10;

    // -------------------------------------------------------------------------
    // Quick Play Constants
    // -------------------------------------------------------------------------

    /// @dev Salt for quick play ticket generation.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    // -------------------------------------------------------------------------
    // Per-N Base Payout Tables (Full Ticket — 5 separate per-N tables)
    // -------------------------------------------------------------------------
    //
    // Indexed by N = _countGoldQuadrants(playerTicket) ∈ {0..4}. Each table is
    // calibrated against THAT N-value's binomial-convolution match-count
    // distribution P_N(M) so that basePayoutEV = exactly 100 centi-x per N.
    // EV-equality across picks is enforced by the table calibration; runtime
    // payout = bet × basePayout_N(M) × roiBps / 1_000_000. Player RTP at activity
    // tier r equals exactly r/10000 (90.00% min, 99.90% max).
    //
    // Bit layout (M=0..7 packed): 32 bits per match index, [M*32 .. M*32+31].
    // Drift per N: ±0.0003 bps (M=4/M=5/M=6 cascade absorbs rounding residual;
    // M=8 stays at the natural uniform-scale value, monotonic in N).
    //
    // Constants are the Fraction-exact output of
    // .planning/notes/degenerette-recalibration/derive_5_tables.py — verified
    // byte-identical at the Phase 267 Task 2 gate (267-01-CONSTANTS-VERIFY.md
    // PASS_ALL_25 per D-267-CONSTVERIFY-01).
    uint256 private constant QUICK_PLAY_PAYOUTS_N0_PACKED = 0x0001a42c000051f1000011da00000654000001ff000000cc0000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N1_PACKED = 0x0001eb8600005fd7000014e70000075f00000256000000ef0000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N2_PACKED = 0x000241d9000070ac00001894000008aa000002bf000001190000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N3_PACKED = 0x0002ac130000856900001d1700000a39000003400000014d0000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N4_PACKED = 0x0003310c00009f5a000022be00000c4d000003e20000018d0000000000000000;

    /// @dev Per-N M=8 jackpot tier (exceeds 32-bit slot; held as separate uint256).
    ///      Values stay at uniform-scale and are strictly monotonic in N.
    uint256 private constant QUICK_PLAY_PAYOUT_N0_M8 = 10_756_411; // 107,564.11x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_M8 = 12_583_037; // 125,830.37x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_M8 = 14_792_939; // 147,929.39x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_M8 = 17_512_324; // 175,123.24x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N4_M8 = 20_916_435; // 209,164.35x bet

    // -------------------------------------------------------------------------
    // WWXRP Bonus EV Redistribution (Full Ticket — 5 per-N factor tables)
    // -------------------------------------------------------------------------
    //
    // Per-N factors derived from each N's basePayout schedule + binomial-
    // convolution P_N(M) + 10/30/30/30 split across buckets 5/6/7/8. Total
    // ETH bonus EV = exactly 5.000% per N (drift ±0.0000 bps in
    // 267-01-CONSTANTS-VERIFY.md). The same per-N factors apply to ETH bets
    // (ETH_ROI_BONUS_BPS = 500) and WWXRP high-roi bets (_wwxrpHighValueRoi).
    //
    // Bit layout (B=5..8 packed): 64 bits per bucket index, [B=5 | B=6 | B=7 | B=8],
    // with B=5 in the low 64 bits. Read via `(packed >> ((bucket - 5) * 64)) & 0xFFFFFFFFFFFFFFFF`.
    uint256 private constant WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
    uint256 private constant WWXRP_FACTORS_N0_PACKED = 0x0000000002278add0000000003fd603d0000000000ddba9f00000000001923d6;
    uint256 private constant WWXRP_FACTORS_N1_PACKED = 0x0000000003aef46a0000000005fd43a60000000001285f2400000000001e36c9;
    uint256 private constant WWXRP_FACTORS_N2_PACKED = 0x0000000006442ce7000000000914e5e4000000000192745c000000000024f43d;
    uint256 private constant WWXRP_FACTORS_N3_PACKED = 0x000000000a96251f000000000dd6ad96000000000228fcb000000000002de0ce;
    uint256 private constant WWXRP_FACTORS_N4_PACKED = 0x0000000011ba25db00000000151a90e70000000002fdeaff0000000000399efe;

    // -------------------------------------------------------------------------
    // Packed Bet Layout
    // -------------------------------------------------------------------------
    //
    // MODE 1: Full Ticket (4 traits, match-based payouts)
    // packed (uint256):
    // [0]        mode (1 bit): 1=full ticket
    // [1]        isRandom (1 bit): must be 0 (no random tickets)
    // [2..33]    customTicket (32 bits): packed traits (required)
    // [34..41]   ticketCount (8 bits): spin count (1..MAX_SPINS_PER_BET)
    // [42..43]   currency (2 bits)
    // [44..171]  amountPerTicket (128 bits)
    // [172..219] index (48 bits)
    // [220..235] activityScore (16 bits)
    // [236]      hasCustom (1 bit): must be 1
    // [237..239] hero (3 bits): [0]=reserved (always set), [1..2]=quadrant (always-on hero, 0..3)
    //
    /// EV-equality across picks: each pick maps to exactly one of 5 per-N tables;
    /// basePayoutEV is calibrated to 100 centi-x per table; runtime payout =
    /// bet × basePayout_N(M) × roiBps / 1_000_000. No per-outcome correction needed.
    //
    // -------------------------------------------------------------------------

    /// @dev Bet mode: full ticket (4 traits, match payouts).
    uint8 private constant MODE_FULL_TICKET = 1;

    // Full Ticket bit positions
    uint256 private constant FT_TICKET_SHIFT = 2;
    uint256 private constant FT_COUNT_SHIFT = 34;
    uint256 private constant FT_CURRENCY_SHIFT = 42;
    uint256 private constant FT_AMOUNT_SHIFT = 44;
    uint256 private constant FT_INDEX_SHIFT = 172;
    uint256 private constant FT_ACTIVITY_SHIFT = 220;
    uint256 private constant FT_HAS_CUSTOM_SHIFT = 236;
    uint256 private constant FT_HERO_SHIFT = 237; // 3 bits: [0]=reserved, [1..2]=quadrant (always-on hero)

    // -------------------------------------------------------------------------
    // Hero Quadrant Multipliers (Per-N, Symbol-Only Match)
    // -------------------------------------------------------------------------
    //
    // Hero match fires on the symbol-axis comparison in the hero quadrant only
    // (color of hero quadrant ignored). P(hero|M, N) × boost(M, N)
    // + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE for each (M, N), so the
    // boost is EV-neutral per match count per N.
    //
    // Bit layout: M=2..7 packed 16 bits each (96 bits total), with M=2 in the
    // low 16 bits: [M=2 | M=3 | M=4 | M=5 | M=6 | M=7]. Read via
    // `(packed >> ((matches - 2) * 16)) & 0xFFFF`. P(hero|M, N) = (1/8) ×
    // P(other-7-axes = M-1 | N) / P_N(M) where the "other 7" comprises 3 sym
    // + 4 color axes.
    uint256 private constant HERO_BOOST_N0_PACKED = 0x275a27be2849291a2a762d2e;
    uint256 private constant HERO_BOOST_N1_PACKED = 0x275027a9282728e52a262ca9;
    uint256 private constant HERO_BOOST_N2_PACKED = 0x27482797280828b529d92c26;
    uint256 private constant HERO_BOOST_N3_PACKED = 0x2742278827ed288829902ba6;
    uint256 private constant HERO_BOOST_N4_PACKED = 0x273d277c27d62860294b2b2a;
    uint16 private constant HERO_PENALTY = 9500;
    uint16 private constant HERO_SCALE = 10_000;

    // Common masks
    uint256 private constant MASK_2 = 0x3;
    uint256 private constant MASK_8 = 0xFF;
    uint256 private constant MASK_16 = 0xFFFF;
    uint256 private constant MASK_32 = 0xFFFFFFFF;
    uint256 private constant MASK_48 = (uint256(1) << 48) - 1;
    uint256 private constant MASK_128 = (uint256(1) << 128) - 1;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// @notice Places Full Ticket bets (4 traits, match-based payouts).
    /// @dev Single chosen-attribute ticket only (no random).
    ///      ticketCount is treated as "spin count": each spin resolves independently but shares
    ///      the same lootbox RNG index/word (derived per spin).
    /// @param player The player address (use zero address for msg.sender).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1..MAX_SPINS_PER_BET).
    /// @param customTicket Custom packed traits. Format: [D:24-31][C:16-23][B:8-15][A:0-7].
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost. Required; inputs >= 4 (including 0xFF) revert with `InvalidBet`.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable {
        _placeDegeneretteBet(
            _resolvePlayer(player),
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        );
    }

    /// @notice Resolves one or more pending bets for a player.
    /// @dev Requires RNG word to be available. Processes wins by minting tokens or crediting ETH.
    /// @param player The player address (use zero address for msg.sender).
    /// @param betIds Array of bet IDs to resolve.
    function resolveBets(address player, uint64[] calldata betIds) external {
        player = _resolvePlayer(player);
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            _resolveBet(player, betIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    // -------------------------------------------------------------------------
    // Internal Bet Logic
    // -------------------------------------------------------------------------

    /// @dev Internal implementation for placing Full Ticket bets.
    function _placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) private {
        uint256 totalBet = _placeDegeneretteBetCore(
            player,
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant
        );

        _collectBetFunds(player, currency, totalBet, msg.value);

        // Quest progress for Degenerette bets (slot 1 only).
        if (currency == CURRENCY_ETH || currency == CURRENCY_BURNIE) {
            quests.handleDegenerette(
                player,
                totalBet,
                currency == CURRENCY_ETH,
                currency == CURRENCY_ETH
                    ? PriceLookupLib.priceForLevel(level)
                    : 0
            );
        }
    }

    function _placeDegeneretteBetCore(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) private returns (uint256 totalBet) {
        if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET)
            revert InvalidBet();
        if (amountPerTicket == 0) revert InvalidBet();
        if (heroQuadrant >= 4) revert InvalidBet();

        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert E();
        if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();

        _validateMinBet(currency, amountPerTicket);

        totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        (uint32 questStreak, , , ) = questView.playerQuestStates(player);
        uint16 activityScore = uint16(
            _playerActivityScore(player, questStreak, level + 1)
        );

        // Pack the bet (isRandom=false, hasCustom=true always)
        uint256 packed = _packFullTicketBet(
            customTicket,
            ticketCount,
            currency,
            amountPerTicket,
            uint32(index),
            activityScore,
            heroQuadrant
        );

        uint64 nonce = degeneretteBetNonce[player];
        unchecked {
            ++nonce;
        }
        degeneretteBetNonce[player] = nonce;

        degeneretteBets[player][nonce] = packed;
        emit BetPlaced(player, uint32(index), nonce, packed);

        // Track hero wagers and player ETH stats (ETH bets only)
        if (currency == CURRENCY_ETH) {
            // 1. Daily hero symbol tracking (heroQuadrant validated to {0..3} above)
            {
                uint32 day = _simulatedDayIndex();
                uint8 heroSymbol = uint8(customTicket >> (heroQuadrant * 8)) &
                    7;
                uint256 wagerUnit = totalBet / 1e12;
                if (wagerUnit > 0) {
                    uint256 wPacked = dailyHeroWagers[day][heroQuadrant];
                    uint256 shift = uint256(heroSymbol) * 32;
                    uint256 current = (wPacked >> shift) & 0xFFFFFFFF;
                    uint256 updated = current + wagerUnit;
                    if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF;
                    wPacked =
                        (wPacked & ~(uint256(0xFFFFFFFF) << shift)) |
                        (updated << shift);
                    dailyHeroWagers[day][heroQuadrant] = wPacked;
                }
            }

            // 2. Per-player per-level ETH wagered
            uint24 lvl = level;
            uint256 playerTotal = playerDegeneretteEthWagered[player][lvl] +
                totalBet;
            playerDegeneretteEthWagered[player][lvl] = playerTotal;
            uint256 topPacked = topDegeneretteByLevel[lvl];
            uint256 topAmount = topPacked >> 160;
            uint256 playerScaled = playerTotal / 1e12;
            if (playerScaled > topAmount) {
                topDegeneretteByLevel[lvl] =
                    (playerScaled << 160) |
                    uint256(uint160(player));
            }
        }
    }

    /// @dev Validates minimum bet amount for currency.
    function _validateMinBet(uint8 currency, uint128 amount) private pure {
        if (currency == CURRENCY_ETH) {
            if (uint256(amount) < MIN_BET_ETH) revert InvalidBet();
        } else if (currency == CURRENCY_BURNIE) {
            if (uint256(amount) < MIN_BET_BURNIE) revert InvalidBet();
        } else if (currency == CURRENCY_WWXRP) {
            if (uint256(amount) < MIN_BET_WWXRP) revert InvalidBet();
        } else {
            revert UnsupportedCurrency();
        }
    }

    /// @dev Processes bet funds (burn tokens, handle ETH, check pool).
    function _collectBetFunds(
        address player,
        uint8 currency,
        uint256 totalBet,
        uint256 ethPaid
    ) private {
        if (currency == CURRENCY_ETH) {
            // Check ETH payment covers bet, or pull from claimable
            if (ethPaid > totalBet) revert InvalidBet();
            if (ethPaid < totalBet) {
                uint256 fromClaimable = totalBet - ethPaid;
                if (claimableWinnings[player] <= fromClaimable)
                    revert InvalidBet();
                claimableWinnings[player] -= fromClaimable;
                claimablePool -= uint128(fromClaimable);
            }

            // Update pool and pending
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(totalBet));
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next, future + uint128(totalBet));
            }
            _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, _lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK) + _packEthToMilliEth(totalBet));
            // No max payout check needed: ETH payouts are capped at 10% of pool at distribution
            // time, so solvency is guaranteed regardless of jackpot size
        } else if (currency == CURRENCY_BURNIE) {
            coin.burnCoin(player, totalBet);
            _lrWrite(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK, _lrRead(LR_PENDING_BURNIE_SHIFT, LR_PENDING_BURNIE_MASK) + _packBurnieToWhole(totalBet));
        } else if (currency == CURRENCY_WWXRP) {
            wwxrp.burnForGame(player, totalBet);
        }
    }

    /// @dev Resolves a bet (determines mode from packed data).
    function _resolveBet(address player, uint64 betId) private {
        uint256 packed = degeneretteBets[player][betId];
        if (packed == 0) revert InvalidBet();

        _resolveFullTicketBet(player, betId, packed);
    }

    /// @dev Resolves a Full Ticket bet.
    function _resolveFullTicketBet(
        address player,
        uint64 betId,
        uint256 packed
    ) private {
        // Decode packed bet
        uint32 customTicket = uint32((packed >> FT_TICKET_SHIFT) & MASK_32);
        uint8 ticketCount = uint8((packed >> FT_COUNT_SHIFT) & MASK_8);
        uint8 currency = uint8((packed >> FT_CURRENCY_SHIFT) & MASK_2);
        uint128 amountPerTicket = uint128(
            (packed >> FT_AMOUNT_SHIFT) & MASK_128
        );
        uint32 index = uint32((packed >> FT_INDEX_SHIFT) & MASK_32);
        uint16 activityScore = uint16((packed >> FT_ACTIVITY_SHIFT) & MASK_16);
        uint8 heroQuadrant = uint8((packed >> (FT_HERO_SHIFT + 1)) & MASK_2);

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        delete degeneretteBets[player][betId];

        uint256 roiBps = _roiBpsFromScore(activityScore);
        // WWXRP high-value ROI target for bonus redistribution (0 if not WWXRP)
        uint256 wwxrpHighRoi = (currency == CURRENCY_WWXRP)
            ? _wwxrpHighValueRoi(activityScore)
            : 0;

        uint32 playerTicket = customTicket;

        uint256 totalPayout;
        uint32 firstResultTicket;

        for (uint8 spinIdx; spinIdx < ticketCount; ) {
            // Spin results are derived deterministically from the lootbox RNG word + index.
            // Spin 0 uses a shorter preimage (no spinIdx mixed in) to produce a distinct seed.
            uint256 resultSeed = spinIdx == 0
                ? uint256(
                    keccak256(abi.encodePacked(rngWord, index, QUICK_PLAY_SALT))
                )
                : uint256(
                    keccak256(
                        abi.encodePacked(
                            rngWord,
                            index,
                            spinIdx,
                            QUICK_PLAY_SALT
                        )
                    )
                );
            uint32 resultTicket = DegenerusTraitUtils.packedTraitsDegenerette(
                resultSeed
            );
            if (spinIdx == 0) {
                firstResultTicket = resultTicket;
            }

            // Count matches
            uint8 matches = _countMatches(playerTicket, resultTicket);

            // Calculate payout (includes per-outcome rarity adjustment for equal EV)
            uint256 payout = _fullTicketPayout(
                playerTicket,
                resultTicket,
                matches,
                currency,
                amountPerTicket,
                roiBps,
                wwxrpHighRoi,
                heroQuadrant
            );

            emit FullTicketResult(
                player,
                betId,
                spinIdx,
                playerTicket,
                matches,
                payout
            );

            if (payout != 0) {
                totalPayout += payout;

                // Ensure each ETH win resolves into an independent lootbox outcome
                // (avoid identical lootbox results when multiple spins share the same payout amount).
                uint256 lootboxWord = spinIdx == 0
                    ? rngWord
                    : uint256(
                        keccak256(
                            abi.encodePacked(
                                rngWord,
                                index,
                                spinIdx,
                                bytes1(0x4c)
                            )
                        )
                    ); // 'L'
                _distributePayout(player, currency, amountPerTicket, payout, lootboxWord, activityScore);
            }

            // Award sDGNRS from Reward pool on 6+ match ETH bets
            if (currency == CURRENCY_ETH && matches >= 6) {
                _awardDegeneretteDgnrs(player, amountPerTicket, matches);
            }

            unchecked {
                ++spinIdx;
            }
        }

        emit FullTicketResolved(
            player,
            betId,
            ticketCount,
            totalPayout,
            firstResultTicket
        );
    }

    /// @dev Distributes payout to player. ETH-currency 3-tier split rule:
    ///        - payout ≤ 3 × betAmount        → 100% ETH (no lootbox conversion).
    ///        - 3×bet < payout ≤ 10 × bet     → 2.5 × betAmount ETH (flat floor) + remainder lootbox.
    ///        - payout > 10 × betAmount       → payout / 4 ETH (25% standard) + remainder lootbox.
    ///      Implementation expresses the upper two tiers as
    ///      `ethShare = max(2.5 × betAmount, payout / 4)`; the two bands meet exactly at
    ///      payout = 10 × bet where `payout / 4 == 2.5 × bet`. Boundary at exactly
    ///      3 × bet is inclusive (3 × bet pays full ETH); the discontinuity at
    ///      3.0× → 3.01× drops ETH from 3.0×bet to 2.5×bet (smaller than the
    ///      naive 25% alternative which would drop to 0.7525×bet).
    ///
    ///      Pool cap (ETH_WIN_CAP_BPS = 10% of futurePool) takes PRECEDENCE over
    ///      all three tiers in the unfrozen branch: if computed ethShare exceeds
    ///      10% of pool, excess flips to lootbox and the PayoutCapped event is
    ///      emitted. Frozen-pool branch retains its solvency-check posture
    ///      (pending future debit with revert-on-insufficient).
    ///
    ///      CURRENCY_BURNIE pays directly via the coin mint; CURRENCY_WWXRP pays
    ///      directly via the wwxrp mint. Neither honors the 3-tier split (which
    ///      applies only to the lootbox-convertible ETH path).
    /// @param player The player to receive the payout.
    /// @param currency The currency type (0=ETH, 1=BURNIE, 3=WWXRP).
    /// @param betAmount The per-ticket bet amount (uint128) — the tier-threshold reference.
    /// @param payout The total payout amount (uint256).
    /// @param rngWord The RNG word for lootbox conversion (only used for ETH).
    function _distributePayout(
        address player,
        uint8 currency,
        uint128 betAmount,
        uint256 payout,
        uint256 rngWord,
        uint16 activityScore
    ) private {
        if (currency == CURRENCY_ETH) {
            // 3-tier split rule (PAY-SPLIT-01..02)
            uint256 ethShare;
            uint256 lootboxShare;
            uint256 threeBet = uint256(betAmount) * 3;
            if (payout <= threeBet) {
                // Tier 1: payout ≤ 3 × bet → 100% ETH.
                ethShare = payout;
                lootboxShare = 0;
            } else {
                // Tier 2 (3 × bet < payout ≤ 10 × bet) → 2.5 × bet floor.
                // Tier 3 (payout > 10 × bet) → payout / 4 standard.
                // The max() resolves cleanly between the two bands.
                uint256 minEth = (uint256(betAmount) * 5) / 2; // 2.5 × bet
                uint256 stdEth = payout / 4;                    // 25% of payout
                ethShare = stdEth > minEth ? stdEth : minEth;
                lootboxShare = payout - ethShare;
            }

            if (prizePoolFrozen) {
                // Frozen path: route ETH share through the pending pool side-channel
                // (matching the bet-placement pattern). The live futurePrizePool
                // snapshot that advanceGame / runRewardJackpots operates on stays
                // intact; the pending future accumulator (credited by purchases
                // during freeze) is debited here with a revert-on-insufficient
                // solvency check.
                (uint128 pNext, uint128 pFuture) = _getPendingPools();

                // Solvency check: pending accumulator must cover the ETH share.
                if (uint256(pFuture) < ethShare) revert E();

                // BAF-SAFE: _setPendingPools write completes before _addClaimableEth
                // (no stale local). DegeneretteModule._addClaimableEth has no
                // auto-rebuy path (no pool writes). _resolveLootboxDirect →
                // LootboxModule has zero pool writes.
                _setPendingPools(pNext, pFuture - uint128(ethShare));
                _addClaimableEth(player, ethShare);
            } else {
                // Unfrozen path: pool cap (ETH_WIN_CAP_BPS) takes PRECEDENCE over
                // the 3-tier split (PAY-SPLIT-03). After capping,
                // ethShare ≤ pool × 10% < pool, so no further solvency check.
                uint256 pool = _getFuturePrizePool();
                uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
                if (ethShare > maxEth) {
                    lootboxShare += ethShare - maxEth;
                    ethShare = maxEth;
                    emit PayoutCapped(player, ethShare, lootboxShare);
                }
                unchecked {
                    pool -= ethShare;
                }
                _setFuturePrizePool(pool);
                _addClaimableEth(player, ethShare);
            }

            // Convert remainder (if any) to lootbox rewards. activityScore is the bet-time
            // snapshot (decoded in _resolveFullTicketBet), so the lootbox EV multiplier is
            // frozen at bet commitment — consistent with the spin payout, never live.
            if (lootboxShare > 0) {
                _resolveLootboxDirect(player, lootboxShare, rngWord, activityScore);
            }
        } else if (currency == CURRENCY_BURNIE) {
            coin.mintForGame(player, payout);
        } else if (currency == CURRENCY_WWXRP) {
            wwxrp.mintPrize(player, payout);
        }
    }

    /// @dev Delegates to the lootbox open module to resolve lootbox rewards directly.
    ///      Applies activity-score EV multiplier (80-135%) to match regular lootbox opens.
    function _resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_LOOTBOX_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameLootboxModule.resolveLootboxDirect.selector,
                    player,
                    amount,
                    rngWord,
                    activityScore
                )
            );
        if (!ok) _revertDelegate(data);
    }

    // -------------------------------------------------------------------------
    // Packed Bet Helpers
    // -------------------------------------------------------------------------

    /// @dev Packs a Full Ticket bet for storage. Hero quadrant is always-on.
    ///      Expects `heroQuadrant` in {0..3}; entry-point validation in
    ///      `_placeDegeneretteBetCore` reverts on `>= 4` with `InvalidBet`,
    ///      so the packed bet and the dailyHeroWagers ledger share the same
    ///      validated input. The reserved bit at FT_HERO_SHIFT is always
    ///      set; the 2-bit quadrant field at FT_HERO_SHIFT + 1 encodes the
    ///      quadrant.
    function _packFullTicketBet(
        uint32 customTicket,
        uint8 ticketCount,
        uint8 currency,
        uint128 amountPerTicket,
        uint32 index,
        uint16 activityScore,
        uint8 heroQuadrant
    ) private pure returns (uint256 packed) {
        packed =
            uint256(MODE_FULL_TICKET) |
            (uint256(customTicket) << FT_TICKET_SHIFT) |
            (uint256(ticketCount) << FT_COUNT_SHIFT) |
            (uint256(currency) << FT_CURRENCY_SHIFT) |
            (uint256(amountPerTicket) << FT_AMOUNT_SHIFT) |
            (uint256(index) << FT_INDEX_SHIFT) |
            (uint256(activityScore) << FT_ACTIVITY_SHIFT) |
            (uint256(1) << FT_HAS_CUSTOM_SHIFT);
        // Hero quadrant: 3 bits at FT_HERO_SHIFT — [0]=reserved, [1..2]=quadrant (always-on)
        packed |=
            (uint256(1) | (uint256(heroQuadrant) << 1)) <<
            FT_HERO_SHIFT;
    }

    // -------------------------------------------------------------------------
    // Bet Math + Outcome
    // -------------------------------------------------------------------------

    /// @dev Counts gold (color == 7) quadrants in a packed ticket.
    ///      Color tier occupies bits 5-3 of each per-quadrant byte; gold is the
    ///      strict equality `color == 7` (not `>= 7`). Returns N ∈ {0..4} —
    ///      the index for per-N payout / hero / WWXRP factor table dispatch.
    /// @param ticket The packed player ticket (uint32, [QQ][CCC][SSS] per byte).
    /// @return count Number of gold quadrants (0..4).
    function _countGoldQuadrants(uint32 ticket) private pure returns (uint8 count) {
        unchecked {
            for (uint8 q = 0; q < 4; ++q) {
                uint8 color = uint8((ticket >> (q * 8 + 3)) & 7);
                if (color == 7) ++count;
            }
        }
    }

    /// @dev Counts matching attributes between player and result tickets.
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @return matches Number of matching attributes (0-8).
    function _countMatches(
        uint32 playerTicket,
        uint32 resultTicket
    ) private pure returns (uint8 matches) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));

            // Color = bits 5-3 (category bucket, ignoring quadrant bits 7-6)
            uint8 pColor = (pQuad >> 3) & 7;
            uint8 rColor = (rQuad >> 3) & 7;
            if (pColor == rColor) {
                unchecked {
                    ++matches;
                }
            }

            // Symbol = bits 2-0 (sub-bucket)
            uint8 pSymbol = pQuad & 7;
            uint8 rSymbol = rQuad & 7;
            if (pSymbol == rSymbol) {
                unchecked {
                    ++matches;
                }
            }

            unchecked {
                ++q;
            }
        }
    }

    /// @dev Maps match count to a WWXRP bonus bucket.
    /// @return bucket 0=none, 5/6/7/8 for matches.
    function _wwxrpBonusBucket(
        uint8 matches
    ) private pure returns (uint8 bucket) {
        if (matches < 5) return 0;
        return matches; // 5,6,7,8
    }

    /// @dev Returns the per-N WWXRP factor for a bucket B ∈ {5, 6, 7, 8}.
    ///      Buckets outside that range yield zero (no bonus). Per-N factors are
    ///      derived from each N's basePayout schedule + binomial-convolution
    ///      P_N(M) + 10/30/30/30 split so total ETH bonus EV = exactly 5.000% per N.
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param bucket WWXRP bonus bucket from `_wwxrpBonusBucket(matches)` (5..8 or 0).
    /// @return factor 64-bit factor; multiply with `bonusRoiBps` and divide by `WWXRP_BONUS_FACTOR_SCALE`.
    function _wwxrpFactor(uint8 N, uint8 bucket) private pure returns (uint256 factor) {
        if (bucket < 5 || bucket > 8) return 0;
        uint256 packed;
        if (N == 0) packed = WWXRP_FACTORS_N0_PACKED;
        else if (N == 1) packed = WWXRP_FACTORS_N1_PACKED;
        else if (N == 2) packed = WWXRP_FACTORS_N2_PACKED;
        else if (N == 3) packed = WWXRP_FACTORS_N3_PACKED;
        else packed = WWXRP_FACTORS_N4_PACKED;
        factor = (packed >> (uint256(bucket - 5) * 64)) & 0xFFFFFFFFFFFFFFFF;
    }

    /// @dev Calculates Full Ticket payout based on matches and activity score ROI.
    ///      Dispatches to one of 5 per-N tables indexed by gold-quadrant count of
    ///      the player's pick (`N = _countGoldQuadrants(playerTicket)`). Each
    ///      per-N table is calibrated so basePayoutEV = exactly 100 centi-x
    ///      against P_N(M) — equal EV across picks within rounding (≤ 0.0003 bps).
    ///      Hero multiplier applies for M ∈ {2..7} under the always-on hero
    ///      schedule; per-N HERO_BOOST tables are calibrated so hero is
    ///      EV-neutral across all (M, N).
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @param matches Number of attribute matches (0-8).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 3=WWXRP).
    /// @param betAmount The bet amount per ticket.
    /// @param roiBps The ROI in basis points (from activity score).
    /// @param wwxrpHighRoi The WWXRP high-value ROI (0 if not WWXRP).
    /// @param heroQuadrant The hero quadrant (0..3) selected by the player.
    /// @return payout The payout amount.
    function _fullTicketPayout(
        uint32 playerTicket,
        uint32 resultTicket,
        uint8 matches,
        uint8 currency,
        uint128 betAmount,
        uint256 roiBps,
        uint256 wwxrpHighRoi,
        uint8 heroQuadrant
    ) private pure returns (uint256 payout) {
        uint8 N = _countGoldQuadrants(playerTicket);
        uint256 basePayoutBps = _getBasePayoutBps(N, matches);

        // Bonus ROI is redistributed into 5+ match buckets via per-N factor lookup.
        uint256 effectiveRoi = roiBps;
        uint8 bucket = _wwxrpBonusBucket(matches);
        if (bucket != 0) {
            uint256 baseBonus;
            if (currency == CURRENCY_WWXRP && wwxrpHighRoi > roiBps) {
                baseBonus = wwxrpHighRoi - roiBps;
            } else if (currency == CURRENCY_ETH) {
                baseBonus = ETH_ROI_BONUS_BPS;
            }
            if (baseBonus != 0) {
                uint256 factor = _wwxrpFactor(N, bucket);
                effectiveRoi = roiBps + (baseBonus * factor) / WWXRP_BONUS_FACTOR_SCALE;
            }
        }

        // Apply ROI scaling: payout = betAmount × basePayout × roiBps / 1_000_000
        // basePayout is in "centi-x" (190 = 1.90x), roiBps is in bps (9000 = 90%).
        payout =
            (uint256(betAmount) * basePayoutBps * effectiveRoi) /
            1_000_000;

        // Hero quadrant: boost payout when hero quadrant symbol matches; penalize otherwise.
        // EV-neutral per match count per N: P(hero|M, N) × boost(M, N)
        // + (1 − P(hero|M, N)) × HERO_PENALTY = HERO_SCALE.
        // No adjustment for M < 2 (payout = 0) or M = 8 (hero EV-neutrality cannot offset).
        if (matches >= 2 && matches < 8) {
            payout = _applyHeroMultiplier(
                payout,
                playerTicket,
                resultTicket,
                matches,
                heroQuadrant,
                N
            );
        }
    }

    /// @dev Applies the per-N hero quadrant boost/penalty to a payout.
    ///      Hero match fires on the symbol-axis comparison in the hero quadrant
    ///      only (color of hero quadrant ignored). If symbol matches, look up
    ///      per-M boost from the per-N HERO_BOOST table; otherwise apply HERO_PENALTY.
    /// @param payout The pre-hero payout (centi-x scaled).
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @param matches Number of attribute matches (2..7 in this branch).
    /// @param heroQuadrant The hero quadrant (0..3).
    /// @param N Gold-quadrant count of the player ticket (0..4) — selects per-N hero table.
    /// @return Adjusted payout after the per-N hero multiplier.
    function _applyHeroMultiplier(
        uint256 payout,
        uint32 playerTicket,
        uint32 resultTicket,
        uint8 matches,
        uint8 heroQuadrant,
        uint8 N
    ) private pure returns (uint256) {
        uint256 shift = uint256(heroQuadrant) * 8;
        bool symbolMatch = ((playerTicket >> shift) & 7) ==
            ((resultTicket >> shift) & 7);

        uint256 multiplier;
        if (symbolMatch) {
            uint256 packed;
            if (N == 0) packed = HERO_BOOST_N0_PACKED;
            else if (N == 1) packed = HERO_BOOST_N1_PACKED;
            else if (N == 2) packed = HERO_BOOST_N2_PACKED;
            else if (N == 3) packed = HERO_BOOST_N3_PACKED;
            else packed = HERO_BOOST_N4_PACKED;
            multiplier = (packed >> (uint256(matches - 2) * 16)) & MASK_16;
        } else {
            multiplier = HERO_PENALTY;
        }
        return (payout * multiplier) / HERO_SCALE;
    }

    /// @dev Dispatches to the per-N base payout table for the given match count.
    ///      M = 0..7 are packed 32 bits each into `QUICK_PLAY_PAYOUTS_N{N}_PACKED`;
    ///      M = 8 jackpot exceeds the 32-bit slot so each N has a separate
    ///      `QUICK_PLAY_PAYOUT_N{N}_M8` constant.
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param matches Number of attribute matches (0..8).
    /// @return Base payout in centi-x (e.g. 204 = 2.04x at 100% ROI).
    function _getBasePayoutBps(uint8 N, uint8 matches) private pure returns (uint256) {
        if (matches >= 8) {
            if (N == 0) return QUICK_PLAY_PAYOUT_N0_M8;
            if (N == 1) return QUICK_PLAY_PAYOUT_N1_M8;
            if (N == 2) return QUICK_PLAY_PAYOUT_N2_M8;
            if (N == 3) return QUICK_PLAY_PAYOUT_N3_M8;
            return QUICK_PLAY_PAYOUT_N4_M8;
        }
        uint256 packed;
        if (N == 0) packed = QUICK_PLAY_PAYOUTS_N0_PACKED;
        else if (N == 1) packed = QUICK_PLAY_PAYOUTS_N1_PACKED;
        else if (N == 2) packed = QUICK_PLAY_PAYOUTS_N2_PACKED;
        else if (N == 3) packed = QUICK_PLAY_PAYOUTS_N3_PACKED;
        else packed = QUICK_PLAY_PAYOUTS_N4_PACKED;
        return (packed >> (uint256(matches) * 32)) & 0xFFFFFFFF;
    }

    // -------------------------------------------------------------------------
    // Payout Math
    // -------------------------------------------------------------------------

    /// @dev Computes ROI in basis points based on activity score.
    ///      Curve: quadratic 90%→95% (0-75% activity), linear 95%→99.5% (75-255% activity),
    ///      linear 99.5%→99.9% (255-305% activity).
    /// @param score The activity score in basis points.
    /// @return roiBps The ROI in basis points.
    function _roiBpsFromScore(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score > ACTIVITY_SCORE_MAX_BPS) {
            score = ACTIVITY_SCORE_MAX_BPS;
        }

        if (score <= ACTIVITY_SCORE_MID_BPS) {
            // Quadratic segment: 0% to 75% activity → 90% to 95% ROI
            uint256 xNum = score;
            uint256 xDen = ACTIVITY_SCORE_MID_BPS;
            uint256 term1 = (1000 * xNum) / xDen;
            uint256 term2 = (500 * xNum * xNum) / (xDen * xDen);
            roiBps = ROI_MIN_BPS + term1 - term2;
        } else if (score <= ACTIVITY_SCORE_HIGH_BPS) {
            // Linear segment: 75% to 255% activity → 95% to 99.5% ROI
            uint256 delta = score - ACTIVITY_SCORE_MID_BPS;
            uint256 span = ACTIVITY_SCORE_HIGH_BPS - ACTIVITY_SCORE_MID_BPS;
            uint256 roiDelta = ROI_HIGH_BPS - ROI_MID_BPS;
            roiBps = ROI_MID_BPS + (delta * roiDelta) / span;
        } else {
            // Linear segment: 255% to 305% activity → 99.5% to 99.9% ROI
            uint256 delta = score - ACTIVITY_SCORE_HIGH_BPS;
            uint256 span = ACTIVITY_SCORE_MAX_BPS - ACTIVITY_SCORE_HIGH_BPS;
            uint256 roiDelta = ROI_MAX_BPS - ROI_HIGH_BPS;
            roiBps = ROI_HIGH_BPS + (delta * roiDelta) / span;
        }

        // ETH bonus is redistributed in full-ticket payouts (not added here).
    }

    /// @dev Calculates WWXRP high-value ROI based on activity score.
    ///      Used as the target ROI for full-ticket bonus redistribution into
    ///      5+ match buckets.
    ///      Scales from 90.0% base to 109.9% max.
    /// @param score The activity score in basis points.
    /// @return roiBps The WWXRP high-value ROI in basis points.
    function _wwxrpHighValueRoi(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score > ACTIVITY_SCORE_MAX_BPS) {
            score = ACTIVITY_SCORE_MAX_BPS;
        }

        // Linear scale from 90.0% (9000 bps) to 109.9% (10990 bps)
        roiBps =
            WWXRP_HIGH_ROI_BASE_BPS +
            (score * (WWXRP_HIGH_ROI_MAX_BPS - WWXRP_HIGH_ROI_BASE_BPS)) /
            ACTIVITY_SCORE_MAX_BPS;
    }

    // -------------------------------------------------------------------------
    // Claimable ETH Credit
    // -------------------------------------------------------------------------

    /// @dev Adds ETH to a player's claimable winnings balance.
    /// @param beneficiary The address to credit.
    /// @param weiAmount The amount in wei to credit.
    function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
        if (weiAmount == 0) return;
        claimablePool += uint128(weiAmount);
        _creditClaimable(beneficiary, weiAmount);
    }

    /// @dev Award sDGNRS from Reward pool on 6+ match Degenerette ETH bets.
    ///      Reward scales by bet size (capped at 1 ETH) and match tier.
    function _awardDegeneretteDgnrs(
        address player,
        uint256 betWei,
        uint8 matchCount
    ) private {
        uint256 bps;
        if (matchCount == 6) bps = DEGEN_DGNRS_6_BPS;
        else if (matchCount == 7) bps = DEGEN_DGNRS_7_BPS;
        else bps = DEGEN_DGNRS_8_BPS;

        uint256 poolBalance = sdgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Reward
        );
        if (poolBalance == 0) return;

        uint256 cappedBet = betWei > 1 ether ? 1 ether : betWei;
        uint256 reward = (poolBalance * bps * cappedBet) / (10_000 * 1 ether);
        if (reward == 0) return;

        sdgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Reward,
            player,
            reward
        );
    }
}
