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
    /// @param matches Composite score S = A + 2*H (0-9). Field name retained for the
    ///        off-chain indexer (range widening 0-8 → 0-9 is a separate out-of-scope track).
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

    /// @notice Emitted when a WWXRP jackpot awards the bracket's whale halfpass.
    /// @param player The bettor who landed the jackpot (the award recipient).
    /// @param bracket The level/10 bracket whose one halfpass is now claimed.
    event WwxrpJackpotWhalePass(address indexed player, uint256 indexed bracket);

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

    /// @dev Resolves the player address, defaulting to msg.sender if zero address is passed.
    ///      Validates operator approval if player differs from msg.sender.
    /// @param player The player address (or zero for msg.sender).
    /// @return resolved The resolved player address.
    function _resolvePlayer(
        address player
    ) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) {
            if (!operatorApprovals[player][msg.sender]) revert NotApproved();
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
    ///      (top score tiers S=6-9).
    uint16 private constant WWXRP_HIGH_ROI_BASE_BPS = 9_000;

    /// @dev WWXRP high-value ROI max in basis points (109.9%).
    uint16 private constant WWXRP_HIGH_ROI_MAX_BPS = 10_990;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IStakedDegenerusStonk private constant sdgnrs =
        IStakedDegenerusStonk(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool),
    ///      keyed on the top-3 score tiers S=7/8/9 (rarity preserved; shift-by-one from M=6/7/8).
    uint16 private constant DEGEN_DGNRS_7_BPS = 400; // S=7: 4% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 800; // S=8: 8% per ETH
    uint16 private constant DEGEN_DGNRS_9_BPS = 1500; // S=9: 15% per ETH

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

    /// @dev Maximum spins per bet, per currency (encoded as ticketCount in the packed bet).
    uint8 private constant MAX_SPINS_ETH = 25;
    uint8 private constant MAX_SPINS_BURNIE = 15;
    uint8 private constant MAX_SPINS_WWXRP = 5;

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
    // calibrated against THAT N-value's binomial-convolution score
    // distribution P_N(S) (S = A + 2*H ∈ {0..9}) so that basePayoutEV = exactly
    // 100 centi-x per N. EV-equality across picks is enforced by the table
    // calibration; runtime payout = bet × basePayout_N(S) × roiBps / 1_000_000.
    // Player RTP at activity tier r equals exactly r/10000 (90.00% min, 99.90% max).
    //
    // Bit layout (S=0..7 packed): 32 bits per score index, [S*32 .. S*32+31].
    // S=8 and S=9 exceed the packed jackpot range and are held as separate per-N
    // uint256 constants below (S=9 is the jackpot relabel of the old M=8 event).
    //
    // The S∈{0..9} payout constants are recalibrated by
    // .planning/notes/degenerette-recalibration/derive_5_tables.py to basePayoutEV =
    // 100 centi-x per N and byte-reproduced under the Phase-267-style PASS_ALL gate.
    // The S=0..7 values are packed below; S=8 and S=9 are held as separate per-N
    // uint256 constants (S=9 is the jackpot relabel of the old M=8 event).
    uint256 private constant QUICK_PLAY_PAYOUTS_N0_PACKED = 0x0000ccf1000027f8000008b700000311000000f9000000640000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N1_PACKED = 0x0000f45d00002fa800000a61000003aa00000129000000770000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N2_PACKED = 0x000120850000384600000c44000004560000015f0000008c0000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N3_PACKED = 0x0001523e000041f500000e5d000005100000019b000000a50000000000000000;
    uint256 private constant QUICK_PLAY_PAYOUTS_N4_PACKED = 0x00018aa100004cf0000010c8000005ea000001e0000000c00000000000000000;

    /// @dev Per-N S=9 jackpot tier (exceeds 32-bit slot; held as separate uint256).
    ///      S=9 ≡ old M=8 (identical event + odds) — a relabel; values unchanged,
    ///      strictly monotonic in N. FINAL (not a placeholder).
    uint256 private constant QUICK_PLAY_PAYOUT_N0_S9 = 10_756_411; // 107,564.11x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_S9 = 12_583_037; // 125,830.37x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_S9 = 14_792_939; // 147,929.39x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_S9 = 17_512_324; // 175,123.24x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N4_S9 = 20_916_435; // 209,164.35x bet

    /// @dev Per-N S=8 tier (separate uint256, exceeds 32-bit slot). Recalibrated to
    ///      basePayoutEV = 100 centi-x per N by derive_5_tables.py.
    uint256 private constant QUICK_PLAY_PAYOUT_N0_S8 = 2_623_243; // 26,232.43x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_S8 = 3_127_840; // 31,278.40x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_S8 = 3_693_049; // 36,930.49x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_S8 = 4_329_524; // 43,295.24x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N4_S8 = 5_051_269; // 50,512.69x bet

    // -------------------------------------------------------------------------
    // WWXRP Bonus EV Redistribution (Full Ticket — 5 per-N factor tables)
    // -------------------------------------------------------------------------
    //
    // Per-N factors derived from each N's basePayout schedule + binomial-
    // convolution P_N(S) + 10/30/30/30 split across the top buckets S=6/7/8/9. Total
    // ETH bonus EV = exactly 5.000% per N. The same per-N factors apply to ETH bets
    // (ETH_ROI_BONUS_BPS = 500) and WWXRP high-roi bets (_wwxrpHighValueRoi).
    //
    // Bit layout (B=6..9 packed): 64 bits per bucket index, [B=6 | B=7 | B=8 | B=9],
    // with B=6 in the low 64 bits. Read via `(packed >> ((bucket - 6) * 64)) & 0xFFFFFFFFFFFFFFFF`.
    //
    // The factor constants below are calibrated for the S∈{0..9} distribution by
    // derive_5_tables.py; total ETH bonus EV = exactly 5.000% per N.
    uint256 private constant WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
    uint256 private constant WWXRP_FACTORS_N0_PACKED = 0x0000000002278add0000000000301e470000000000769797000000000011b488;
    uint256 private constant WWXRP_FACTORS_N1_PACKED = 0x0000000003aef46a0000000000459aab000000000096dc93000000000014250d;
    uint256 private constant WWXRP_FACTORS_N2_PACKED = 0x0000000006442ce7000000000067a3f90000000000c6a960000000000017af89;
    uint256 private constant WWXRP_FACTORS_N3_PACKED = 0x000000000a96251f00000000009dba9b00000000010d8a6d00000000001cbc40;
    uint256 private constant WWXRP_FACTORS_N4_PACKED = 0x0000000011ba25db0000000000f40c44000000000176ef73000000000023de94;

    // -------------------------------------------------------------------------
    // Packed Bet Layout
    // -------------------------------------------------------------------------
    //
    // MODE 1: Full Ticket (4 traits, match-based payouts)
    // packed (uint256):
    // [0]        mode (1 bit): 1=full ticket
    // [1]        isRandom (1 bit): must be 0 (no random tickets)
    // [2..33]    customTicket (32 bits): packed traits (required)
    // [34..41]   ticketCount (8 bits): spin count (per-currency cap: ETH 25 / BURNIE 15 / WWXRP 5)
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

    // Common masks
    uint256 private constant MASK_2 = 0x3;
    uint256 private constant MASK_8 = 0xFF;
    uint256 private constant MASK_16 = 0xFFFF;
    uint256 private constant MASK_32 = 0xFFFFFFFF;
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
    /// @param ticketCount Number of spins (per-currency cap: ETH 25 / BURNIE 15 / WWXRP 5).
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

    /// @dev Cross-bet payout accumulator threaded through resolveBets → _resolveBet
    ///      → _resolveFullTicketBet → _distributePayout. Per-currency payouts are
    ///      summed across the whole resolveBets call and flushed ONCE (additive, so
    ///      byte-identical to the per-spin writes). The prize-pool decrement runs
    ///      against a running local that mirrors the live storage value spin-by-spin:
    ///      read once at first ETH win, decremented in memory per spin (so each
    ///      spin's ETH_WIN_CAP_BPS cap sees the same shrinking pool it would have
    ///      read from storage today), written back once at flush. Lootbox-share is
    ///      NOT accumulated here — it is summed PER betId and resolved once per bet
    ///      inside _resolveFullTicketBet (resolution-batch-invariant).
    struct ResolveAcc {
        uint256 ethClaimable; // summed ETH claimable across all bets
        uint256 burnieMint; // summed BURNIE mint across all bets
        uint256 wwxrpMint; // summed WWXRP mint across all bets
        bool poolFrozen; // prizePoolFrozen snapshot (stable across the call)
        bool poolLoaded; // running pool locals initialized?
        uint256 runningFuture; // unfrozen: running futurePrizePool
        uint128 pendingNext; // frozen: running pending next pool
        uint128 pendingFuture; // frozen: running pending future pool
    }

    /// @notice Resolves one or more pending bets for a player.
    /// @dev Requires RNG word to be available. Processes wins by minting tokens or crediting ETH.
    ///      ETH/BURNIE/WWXRP payouts are accumulated across the whole call and flushed
    ///      once per currency (one mint per currency, one claimable + claimablePool write,
    ///      one prize-pool write); lootbox-share is summed per betId and resolved per bet.
    /// @param player The player address (use zero address for msg.sender).
    /// @param betIds Array of bet IDs to resolve.
    function resolveBets(address player, uint64[] calldata betIds) external {
        // Once game-over liveness has drained the balance into claimable, resolving a
        // pending bet would credit ETH claimable out of the already-distributed
        // futurePrizePool residual, pushing claimablePool above the ETH balance
        // (unbacked obligation). Same guard as claimWhalePass: pending bets are settled
        // by the game-over drain, never resolved into claimable after it.
        if (_livenessTriggered()) revert E();
        player = _resolvePlayer(player);
        ResolveAcc memory acc;
        acc.poolFrozen = prizePoolFrozen;
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            _resolveBet(player, betIds[i], acc);
            unchecked {
                ++i;
            }
        }

        // Single per-currency flush (additive → byte-identical to the per-spin writes).
        if (acc.burnieMint != 0) coin.mintForGame(player, acc.burnieMint);
        if (acc.wwxrpMint != 0) wwxrp.mintPrize(player, acc.wwxrpMint);
        if (acc.ethClaimable != 0) _addClaimableEth(player, acc.ethClaimable);

        // Single prize-pool write reflecting the running decrement (only if any ETH
        // win touched it — poolLoaded guards against a pointless rewrite otherwise).
        if (acc.poolLoaded) {
            if (acc.poolFrozen) {
                _setPendingPools(acc.pendingNext, acc.pendingFuture);
            } else {
                _setFuturePrizePool(acc.runningFuture);
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
        uint24 lvl = level;
        uint256 totalBet = _placeDegeneretteBetCore(
            player,
            currency,
            amountPerTicket,
            ticketCount,
            customTicket,
            heroQuadrant,
            lvl
        );

        _collectBetFunds(player, currency, totalBet, msg.value);

        // Quest progress for Degenerette bets (slot 1 only).
        if (currency == CURRENCY_ETH || currency == CURRENCY_BURNIE) {
            quests.handleDegenerette(
                player,
                totalBet,
                currency == CURRENCY_ETH,
                currency == CURRENCY_ETH
                    ? PriceLookupLib.priceForLevel(lvl + 1)
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
        uint8 heroQuadrant,
        uint24 lvl
    ) private returns (uint256 totalBet) {
        // Per-currency spin cap (currency is validated to ETH/BURNIE/WWXRP by
        // _validateMinBet below; the WWXRP arm — CURRENCY_WWXRP — is the default).
        uint8 maxSpins = currency == CURRENCY_ETH
            ? MAX_SPINS_ETH
            : currency == CURRENCY_BURNIE
                ? MAX_SPINS_BURNIE
                : MAX_SPINS_WWXRP;
        if (ticketCount == 0 || ticketCount > maxSpins) revert InvalidBet();
        if (amountPerTicket == 0) revert InvalidBet();
        if (heroQuadrant >= 4) revert InvalidBet();

        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert E();
        if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();

        _validateMinBet(currency, amountPerTicket);

        totalBet = uint256(amountPerTicket) * uint256(ticketCount);
        // Decay-aware effective quest streak (mirrors the DECSTREAK chokepoint fix): a streak
        // lapsed past its shields reads 0, so a returning-inactive player can't snapshot a
        // stale-high streak into the bet's activityScore (which scales the ETH ROI and the
        // lootbox-share EV multiplier). WWXRP bets never sync via handleDegenerette, so a raw
        // playerQuestStates read would let the zombie streak persist indefinitely.
        uint32 questStreak = quests.effectiveBaseStreak(player);
        uint16 activityScore = uint16(
            _playerActivityScore(player, questStreak, lvl + 1)
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

        // Track daily hero wagers (ETH bets only)
        if (currency == CURRENCY_ETH) {
            // Daily hero symbol tracking (heroQuadrant validated to {0..3} above)
            uint24 day = _simulatedDayIndex();
            uint8 heroSymbol = uint8(customTicket >> (heroQuadrant * 8)) & 7;
            uint256 wagerUnit = totalBet / 1e14;
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
            // ETH covers the bet first, then claimable to the 1-wei sentinel, then afking.
            if (ethPaid > totalBet) revert InvalidBet();
            if (ethPaid < totalBet) {
                uint256 fromClaimable = totalBet - ethPaid;
                uint256 claimable = _claimableOf(player);
                uint256 cUsed;
                if (claimable > 1) {
                    uint256 available = claimable - 1; // preserve the 1-wei sentinel
                    cUsed = fromClaimable < available ? fromClaimable : available;
                    if (cUsed != 0) {
                        _debitClaimable(player, cUsed);
                        claimablePool -= uint128(cUsed);
                    }
                }
                uint256 remaining = fromClaimable - cUsed;
                if (remaining != 0) {
                    if (_afkingOf(player) < remaining) revert InvalidBet();
                    _debitAfking(player, remaining);
                    claimablePool -= uint128(remaining);
                    emit AfkingSpent(player, remaining);
                }
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
    function _resolveBet(
        address player,
        uint64 betId,
        ResolveAcc memory acc
    ) private {
        uint256 packed = degeneretteBets[player][betId];
        if (packed == 0) revert InvalidBet();

        _resolveFullTicketBet(player, betId, packed, acc);
    }

    /// @dev Resolves a Full Ticket bet. Per-currency payouts accumulate into `acc`
    ///      (flushed once cross-bet by resolveBets); lootbox-share is summed across
    ///      this bet's spins and resolved ONCE here (one box per betId).
    function _resolveFullTicketBet(
        address player,
        uint64 betId,
        uint256 packed,
        ResolveAcc memory acc
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
        // Gold-quadrant count is a pure function of the player's pick — identical
        // for every spin of this bet, so it is computed once here.
        uint8 goldCount = _countGoldQuadrants(playerTicket);

        uint256 totalPayout;
        uint32 firstResultTicket;
        // Lootbox-share summed across THIS bet's spins → one box per betId.
        uint256 betLootboxShare;

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

            // Score this spin: S = A + 2*H (hero symbol worth 2), S ∈ {0..9}
            uint8 s = _score(playerTicket, resultTicket, heroQuadrant);

            // Calculate payout (dispatches on the per-N score table)
            uint256 payout = _fullTicketPayout(
                goldCount,
                s,
                currency,
                amountPerTicket,
                roiBps,
                wwxrpHighRoi
            );

            emit FullTicketResult(
                player,
                betId,
                spinIdx,
                playerTicket,
                s,
                payout
            );

            if (payout != 0) {
                totalPayout += payout;

                // Accumulate this spin's payout. ETH credits + the running-pool
                // decrement / cap land in `acc` (flushed cross-bet); the spin's
                // lootbox-share is returned and summed into this bet's box.
                betLootboxShare += _distributePayout(
                    player,
                    currency,
                    amountPerTicket,
                    payout,
                    acc
                );
            }

            // Award sDGNRS from Reward pool on S>=7 ETH bets. Stays per-spin:
            // _awardDegeneretteDgnrs reads poolBalance fresh per call, so summing
            // off a stale balance would change the payout.
            if (currency == CURRENCY_ETH && s >= 7) {
                _awardDegeneretteDgnrs(player, amountPerTicket, s);
            }

            // First WWXRP jackpot in this level/10 bracket grants the bettor one
            // whale halfpass (deferred via whalePassClaims, no ETH/pool touch).
            // The s == 9 check short-circuits first, so non-jackpot spins read no
            // new state. The award always credits the bet owner `player`.
            if (
                s == 9 &&
                currency == CURRENCY_WWXRP &&
                amountPerTicket >= MIN_BET_WWXRP
            ) {
                uint256 bracket = uint256(level) / 10;
                if (!wwxrpJackpotWhalePassBracketAwarded[bracket]) {
                    whalePassClaims[player] += 1;
                    wwxrpJackpotWhalePassBracketAwarded[bracket] = true;
                    emit WwxrpJackpotWhalePass(player, bracket);
                }
            }

            unchecked {
                ++spinIdx;
            }
        }

        // One lootbox per betId, on the summed lootbox-share. The box seed binds the immutable
        // betId (keccak'd with the index word) so each of a player's bets at the same index rolls
        // independently; the live lootbox-share is NOT a seed input. Never summed across betIds.
        if (betLootboxShare > 0) {
            _resolveLootboxDirect(
                player,
                betLootboxShare,
                uint256(keccak256(abi.encode(rngWord, betId))),
                activityScore
            );
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
    /// @param acc Cross-bet accumulator: ETH claimable + the running prize-pool
    ///        local accumulate here (flushed once by resolveBets); BURNIE/WWXRP
    ///        mint totals accumulate here too.
    /// @return lootboxShare The ETH lootbox-share for this spin (0 for BURNIE/WWXRP),
    ///         summed by the caller into the per-bet box.
    function _distributePayout(
        address player,
        uint8 currency,
        uint128 betAmount,
        uint256 payout,
        ResolveAcc memory acc
    ) private returns (uint256 lootboxShare) {
        if (currency == CURRENCY_ETH) {
            // 3-tier split rule (PAY-SPLIT-01..02)
            uint256 ethShare;
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

            // Load the running prize-pool local on the first ETH win. The first
            // read mirrors the live storage value the per-spin path would have
            // read; subsequent spins decrement the running local in memory, so
            // each spin's cap/solvency sees the same shrinking pool storage would
            // have held — byte-identical to per-spin. Flushed once by resolveBets.
            if (!acc.poolLoaded) {
                acc.poolLoaded = true;
                if (acc.poolFrozen) {
                    (acc.pendingNext, acc.pendingFuture) = _getPendingPools();
                } else {
                    acc.runningFuture = _getFuturePrizePool();
                }
            }

            if (acc.poolFrozen) {
                // Frozen path: route ETH share through the pending pool side-channel
                // (matching the bet-placement pattern). The live futurePrizePool
                // snapshot that advanceGame / runRewardJackpots operates on stays
                // intact; the pending future accumulator (credited by purchases
                // during freeze) is debited here with a revert-on-insufficient
                // solvency check, against the running local.
                if (uint256(acc.pendingFuture) < ethShare) revert E();
                acc.pendingFuture -= uint128(ethShare);
            } else {
                // Unfrozen path: pool cap (ETH_WIN_CAP_BPS) takes PRECEDENCE over
                // the 3-tier split (PAY-SPLIT-03). After capping,
                // ethShare ≤ pool × 10% < pool, so no further solvency check.
                uint256 pool = acc.runningFuture;
                uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000;
                if (ethShare > maxEth) {
                    lootboxShare += ethShare - maxEth;
                    ethShare = maxEth;
                    emit PayoutCapped(player, ethShare, lootboxShare);
                }
                unchecked {
                    pool -= ethShare;
                }
                acc.runningFuture = pool;
            }

            // Accumulate ETH claimable cross-bet (flushed once). The lootbox-share
            // is returned to the caller, summed per betId, and resolved once per bet.
            acc.ethClaimable += ethShare;
        } else if (currency == CURRENCY_BURNIE) {
            acc.burnieMint += payout;
        } else if (currency == CURRENCY_WWXRP) {
            acc.wwxrpMint += payout;
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

    /// @dev Scores a player ticket against a result ticket: S = A + 2*H, where A is the
    ///      ordinary-axis match count (4 color axes + 3 non-hero symbol axes, 0..7) and H is
    ///      1 if the hero quadrant's SYMBOL matches. The hero quadrant's color stays an
    ///      ordinary axis. S ∈ {0..9}; the hero symbol scores 2 (hero-alone match ⇒ S=2 win).
    /// @param playerTicket The player's ticket (packed traits).
    /// @param resultTicket The result ticket (packed traits).
    /// @param heroQuadrant The always-on hero quadrant (0..3) whose symbol axis scores double.
    /// @return s Composite score (0-9).
    function _score(
        uint32 playerTicket,
        uint32 resultTicket,
        uint8 heroQuadrant
    ) private pure returns (uint8 s) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTicket >> (q * 8));
            uint8 rQuad = uint8(resultTicket >> (q * 8));

            // Color = bits 5-3 (ordinary axis for all 4 quadrants)
            if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) {
                unchecked {
                    ++s;
                }
            }

            // Symbol = bits 2-0. The hero quadrant's symbol scores 2; the other 3 score 1.
            if ((pQuad & 7) == (rQuad & 7)) {
                unchecked {
                    s += (q == heroQuadrant) ? 2 : 1;
                }
            }

            unchecked {
                ++q;
            }
        }
    }

    /// @dev Maps a score S to a WWXRP bonus bucket (shift-by-one from the old M scale).
    /// @return bucket 0=none, 6/7/8/9 for the top score tiers.
    function _wwxrpBonusBucket(
        uint8 s
    ) private pure returns (uint8 bucket) {
        if (s < 6) return 0;
        return s; // 6,7,8,9
    }

    /// @dev Returns the per-N WWXRP factor for a bucket B ∈ {6, 7, 8, 9}.
    ///      Precondition: bucket ∈ {6..9} — `_wwxrpBonusBucket` returns 0 or 6..9
    ///      (S is arithmetically capped at 9) and the sole call site is gated on
    ///      `bucket != 0`. Per-N factors are derived from each N's basePayout
    ///      schedule + binomial-convolution P_N(S) + 10/30/30/30 split so total
    ///      ETH bonus EV = exactly 5.000% per N.
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param bucket WWXRP bonus bucket from `_wwxrpBonusBucket(s)` (6..9).
    /// @return factor 64-bit factor; multiply with `bonusRoiBps` and divide by `WWXRP_BONUS_FACTOR_SCALE`.
    function _wwxrpFactor(uint8 N, uint8 bucket) private pure returns (uint256 factor) {
        uint256 packed;
        if (N == 0) packed = WWXRP_FACTORS_N0_PACKED;
        else if (N == 1) packed = WWXRP_FACTORS_N1_PACKED;
        else if (N == 2) packed = WWXRP_FACTORS_N2_PACKED;
        else if (N == 3) packed = WWXRP_FACTORS_N3_PACKED;
        else packed = WWXRP_FACTORS_N4_PACKED;
        factor = (packed >> (uint256(bucket - 6) * 64)) & 0xFFFFFFFFFFFFFFFF;
    }

    /// @dev Calculates Full Ticket payout based on the score S and activity score ROI.
    ///      Dispatches to one of 5 per-N tables indexed by N, the gold-quadrant
    ///      count of the player's pick (computed once per bet by the caller). Each
    ///      per-N table is calibrated so basePayoutEV = exactly 100 centi-x
    ///      against P_N(S) — equal EV across picks within rounding. The hero is
    ///      scored into S (S = A + 2*H), so there is no separate hero multiplier.
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param s The composite score (0-9).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 3=WWXRP).
    /// @param betAmount The bet amount per ticket.
    /// @param roiBps The ROI in basis points (from activity score).
    /// @param wwxrpHighRoi The WWXRP high-value ROI (0 if not WWXRP).
    /// @return payout The payout amount.
    function _fullTicketPayout(
        uint8 N,
        uint8 s,
        uint8 currency,
        uint128 betAmount,
        uint256 roiBps,
        uint256 wwxrpHighRoi
    ) private pure returns (uint256 payout) {
        uint256 basePayoutBps = _getBasePayoutBps(N, s);

        // Bonus ROI is redistributed into the top score buckets via per-N factor lookup.
        uint256 effectiveRoi = roiBps;
        uint8 bucket = _wwxrpBonusBucket(s);
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
    }

    /// @dev Dispatches to the per-N base payout table for the given score S.
    ///      S = 0..7 are packed 32 bits each into `QUICK_PLAY_PAYOUTS_N{N}_PACKED`;
    ///      S = 8 and S = 9 each exceed the 32-bit slot so each N has separate
    ///      `QUICK_PLAY_PAYOUT_N{N}_S8` / `_S9` constants (S=9 is the M=8 jackpot relabel).
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param s Composite score (0..9).
    /// @return Base payout in centi-x (e.g. 204 = 2.04x at 100% ROI).
    function _getBasePayoutBps(uint8 N, uint8 s) private pure returns (uint256) {
        if (s >= 9) {
            if (N == 0) return QUICK_PLAY_PAYOUT_N0_S9;
            if (N == 1) return QUICK_PLAY_PAYOUT_N1_S9;
            if (N == 2) return QUICK_PLAY_PAYOUT_N2_S9;
            if (N == 3) return QUICK_PLAY_PAYOUT_N3_S9;
            return QUICK_PLAY_PAYOUT_N4_S9;
        }
        if (s == 8) {
            if (N == 0) return QUICK_PLAY_PAYOUT_N0_S8;
            if (N == 1) return QUICK_PLAY_PAYOUT_N1_S8;
            if (N == 2) return QUICK_PLAY_PAYOUT_N2_S8;
            if (N == 3) return QUICK_PLAY_PAYOUT_N3_S8;
            return QUICK_PLAY_PAYOUT_N4_S8;
        }
        uint256 packed;
        if (N == 0) packed = QUICK_PLAY_PAYOUTS_N0_PACKED;
        else if (N == 1) packed = QUICK_PLAY_PAYOUTS_N1_PACKED;
        else if (N == 2) packed = QUICK_PLAY_PAYOUTS_N2_PACKED;
        else if (N == 3) packed = QUICK_PLAY_PAYOUTS_N3_PACKED;
        else packed = QUICK_PLAY_PAYOUTS_N4_PACKED;
        return (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;
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

    /// @dev Adds ETH to a player's claimable winnings balance. The sole call site
    ///      is gated on a nonzero amount.
    /// @param beneficiary The address to credit.
    /// @param weiAmount The amount in wei to credit (nonzero).
    function _addClaimableEth(address beneficiary, uint256 weiAmount) private {
        claimablePool += uint128(weiAmount);
        _creditClaimable(beneficiary, weiAmount);
    }

    /// @dev Award sDGNRS from Reward pool on the top-3 score tiers (S>=7) Degenerette ETH bets.
    ///      Reward scales by bet size (capped at 1 ETH) and score tier.
    function _awardDegeneretteDgnrs(
        address player,
        uint256 betWei,
        uint8 s
    ) private {
        uint256 bps;
        if (s == 7) bps = DEGEN_DGNRS_7_BPS;
        else if (s == 8) bps = DEGEN_DGNRS_8_BPS;
        else bps = DEGEN_DGNRS_9_BPS;

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
