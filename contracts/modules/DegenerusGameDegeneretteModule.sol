// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {
    IDegenerusGameLootboxModule
} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {DegenerusGamePayoutUtils} from "./DegenerusGamePayoutUtils.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @notice Minimal interface for WWXRP game burn/mint operations.
interface IWWXRP {
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
 *      on the inherited DegenerusGameStorage. Supports ETH, FLIP, and WWXRP currencies.
 *      FLIP payouts face a per-bet survival flip (double-or-nothing) at resolution,
 *      so all FLIP entering existence survives at least one coinflip.
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

    /// @notice Emitted when a Degenerette bet is placed.
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

    /// @notice Emitted when Degenerette bets are resolved.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param spinCount Number of spins resolved.
    /// @param totalPayout Total payout across all spins (for FLIP bets: after the
    ///        survival flip — doubled or zeroed vs the per-spin DegeneretteResult sums).
    /// @param resultTraits The spin-0 result traits (additional spin results are derived per spinIndex).
    event DegeneretteResolved(
        address indexed player,
        uint64 indexed betId,
        uint8 spinCount,
        uint256 totalPayout,
        uint32 resultTraits
    );

    /// @notice Emitted for each individual Degenerette spin result.
    /// @param player The player address.
    /// @param betId The bet ID.
    /// @param spinIndex Index of this spin (0 to count-1).
    /// @param playerTraits The player's spin traits.
    /// @param matches Composite Variant-2 score S (0-9; color gated behind symbol,
    ///        hero symbol +2). Field name retained for the off-chain indexer.
    /// @param payout Payout for this spin.
    event DegeneretteResult(
        address indexed player,
        uint64 indexed betId,
        uint8 spinIndex,
        uint32 playerTraits,
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

    /// @notice A lootbox roll resolved as a Degenerette spin (WWXRP / FLIP×3 / ETH) — the single
    ///         self-contained record of a box-spin outcome (replaces the per-spin DegeneretteResult /
    ///         DegeneretteResolved for box rolls). Every reel + every output reward is here or, for
    ///         the ETH recirc, in the fresh box's own (now-emitted) events.
    /// @param player The reward recipient.
    /// @param betId Self-classifying id: bit 63 = box-origin sentinel, bits 62-60 = spin type
    ///        (0=WWXRP, 1=FLIP, 2=ETH), bits 59-0 = seed entropy (unique per box-spin).
    /// @param packedSpins Per-spin reels packed low→high, each spin = [playerTraits:32 |
    ///        resultTraits:32 | score:8] (72 bits, spin 0 lowest); bits 216-223 = spin count;
    ///        bit 224 = FLIP survival flag (1 = the survival flip won; unused for WWXRP/ETH).
    /// @param payout Total reward: FLIP/WWXRP minted, or the ETH gross (= ethShare + the recirc).
    /// @param ethShare ETH credited to the player's claimable winnings (0 for WWXRP/FLIP). The
    ///        recirculated remainder is derivable as `payout - ethShare` (ETH only); that recirc
    ///        box emits its own LootBoxOpened / BoxSpin so its contents are itemized.
    event BoxSpin(
        address indexed player,
        uint64 betId,
        uint256 packedSpins,
        uint256 payout,
        uint256 ethShare
    );

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Reverts with the provided reason bytes from a delegatecall failure.
    /// @param reason The revert reason bytes from the failed call.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    /// @dev Reference to the WWXRP token contract for burn/mint operations.
    IWWXRP internal constant wwxrp =
        IWWXRP(ContractAddresses.WWXRP);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Activity score at the curve knee K (seg-A end; deity pass theoretical max).
    uint16 private constant ACTIVITY_SCORE_MAX_POINTS = 305;

    /// @dev Minimum ROI in basis points (90%, score 0).
    uint16 private constant ROI_MIN_BPS = 9_000;

    /// @dev ROI at the knee K (90% of the gain delivered).
    uint16 private constant ROI_VA_BPS = 9_891;

    /// @dev ROI at the seg-B knee (98% of the gain).
    uint16 private constant ROI_VB_BPS = 9_970;

    /// @dev Maximum ROI in basis points (99.9%, reached at the effective cap).
    uint16 private constant ROI_MAX_BPS = 9_990;

    /// @dev Bonus ROI for ETH bets in basis points (+5%), redistributed to high buckets.
    uint16 private constant ETH_ROI_BONUS_BPS = 500;

    /// @dev WWXRP rigged floor ROI (flat 70%): the guaranteed multiplier applied to
    ///      every WWXRP roll's base payout (all score tiers). The surplus
    ///      `_wwxrpRoi(score) - WWXRP_FLOOR_BPS` is redistributed into the top score
    ///      buckets (S=6-9). 70% is the score-0 RTP, and `_wwxrpRoi >= 7000` at every
    ///      score, so the floor is flat and never binds above the curve.
    uint16 private constant WWXRP_FLOOR_BPS = 7_000;

    /// @dev WWXRP total-RTP curve (the rigged WWXRP payout RTP equals this / 10000).
    ///      Steep ramp 70%->115% (score 0 to K=305), shallow leg to 118% (seg-B knee),
    ///      near-flat crawl to 120% at the effective cap. MIN equals the flat floor, so
    ///      the bonus redistribution is zero at score 0 and grows with activity.
    uint16 private constant WWXRP_ROI_MIN_BPS = 7_000;
    uint16 private constant WWXRP_ROI_VA_BPS = 11_500;
    uint16 private constant WWXRP_ROI_VB_BPS = 11_800;
    uint16 private constant WWXRP_ROI_MAX_BPS = 12_000;

    /// @dev Maximum ETH payout as percentage of futurePool in basis points (10%).
    uint16 private constant ETH_WIN_CAP_BPS = 1_000;

    /// @dev sDGNRS contract reference for degenerette DGNRS rewards
    IsDGNRS private constant sdgnrs =
        IsDGNRS(ContractAddresses.SDGNRS);

    /// @dev Degenerette DGNRS reward BPS (per ETH wagered, % of remaining Reward pool),
    ///      keyed on the top-3 score tiers S=7/8/9.
    uint16 private constant DEGEN_DGNRS_7_BPS = 400; // S=7: 4% per ETH
    uint16 private constant DEGEN_DGNRS_8_BPS = 800; // S=8: 8% per ETH
    uint16 private constant DEGEN_DGNRS_9_BPS = 1500; // S=9: 15% per ETH

    /// @dev Currency type identifier for ETH.
    uint8 private constant CURRENCY_ETH = 0;

    /// @dev Currency type identifier for FLIP token.
    uint8 private constant CURRENCY_FLIP = 1;

    /// @dev Currency type identifier for WWXRP token.
    uint8 private constant CURRENCY_WWXRP = 3;

    /// @dev Minimum bet amount for ETH (0.005 ETH on mainnet).
    uint256 private constant MIN_BET_ETH = 5 ether / 1000;

    /// @dev Minimum bet amount for FLIP (100 tokens with 18 decimals).
    uint256 private constant MIN_BET_FLIP = 100 ether;

    /// @dev Minimum bet amount for WWXRP (1 token with 18 decimals).
    uint256 private constant MIN_BET_WWXRP = 1 ether;

    /// @dev Maximum spins per bet, per currency (encoded as ticketCount in the packed bet).
    uint8 private constant MAX_SPINS_ETH = 25;
    uint8 private constant MAX_SPINS_FLIP = 15;
    uint8 private constant MAX_SPINS_WWXRP = 5;

    // -------------------------------------------------------------------------
    // Quick Play Constants
    // -------------------------------------------------------------------------

    /// @dev Salt for quick play ticket generation.
    bytes1 private constant QUICK_PLAY_SALT = 0x51; // 'Q'

    // -------------------------------------------------------------------------
    // Per-(N, hero-is-gold) Base Payout Tables (Full Ticket — honest lane, Option B)
    // -------------------------------------------------------------------------
    //
    // Indexed by N = _countGoldQuadrants(playerTraits) ∈ {0..4} AND, on the honest
    // lane, by whether the hero quadrant is gold (Variant-2 couples color to symbol,
    // so hero-goldness shifts P(S)). Each table is calibrated against THAT sub-case's
    // Variant-2 score distribution P_(N,heroGold)(S) (color gated behind symbol,
    // hero symbol +2; S ∈ {0..9}) so that basePayoutEV = exactly 100 centi-x per
    // sub-case (DEC-02 Option B — exact EV-equality across hero placement). EV-equality
    // across picks is enforced by the table calibration; runtime payout =
    // bet × basePayout_(N,heroGold)(S) × roiBps / 1_000_000.
    // Player RTP at activity tier r equals exactly r/10000 (90.00% min, 99.90% max).
    //
    // Bit layout (S=0..7 packed): 32 bits per score index, [S*32 .. S*32+31].
    // S=8 and S=9 exceed the packed jackpot range and are held as separate per-N
    // uint256 constants below (S=9 is the jackpot tier).
    //
    // The S∈{0..9} payout constants are calibrated to basePayoutEV =
    // 100 centi-x per (N, hero-is-gold) sub-case (Variant-2, DEC-02 Option B).
    // The S=0..7 values are packed below; S=8 and S=9 are held as separate
    // per-N uint256 constants (S=9 is the jackpot tier). Under Variant-2 the
    // hero quadrant's gold-ness shifts P(S), so the HONEST family is split per
    // (N, hero-is-gold): N0 (always hero-common) and N4 (always hero-gold)
    // collapse to one table each; N∈{1,2,3} carry a _HEROGOLD / _HEROCOMMON
    // infix. _getBasePayoutBps consults heroIsGold only on the honest lane.
    uint256 private constant QUICK_PLAY_PAYOUTS_N0_PACKED = 0x0001905a00004e1400001103000005fe000001e7000000c30000000000000000;  // N0/heroCOMMON EV=99.9997
    uint256 private constant QUICK_PLAY_PAYOUTS_N1_HEROGOLD_PACKED = 0x0001c57f0000587000001346000006ca00000227000000dd0000000000000000;  // N1/heroGOLD EV=99.9999
    uint256 private constant QUICK_PLAY_PAYOUTS_N1_HEROCOMMON_PACKED = 0x0001b880000055e6000012b80000069d00000218000000d60000000000000000;  // N1/heroCOMMON EV=99.9999
    uint256 private constant QUICK_PLAY_PAYOUTS_N2_HEROGOLD_PACKED = 0x0001ef28000060910000150a0000076c0000025a000000f10000000000000000;  // N2/heroGOLD EV=100.0000
    uint256 private constant QUICK_PLAY_PAYOUTS_N2_HEROCOMMON_PACKED = 0x0001e0c700005dc10000146f0000073300000249000000ea0000000000000000;  // N2/heroCOMMON EV=99.9999
    uint256 private constant QUICK_PLAY_PAYOUTS_N3_HEROGOLD_PACKED = 0x0002185400006898000016c80000080b0000028c000001050000000000000000;  // N3/heroGOLD EV=100.0000
    uint256 private constant QUICK_PLAY_PAYOUTS_N3_HEROCOMMON_PACKED = 0x00020899000065880000161e000007d200000279000000fd0000000000000000;  // N3/heroCOMMON EV=100.0000
    uint256 private constant QUICK_PLAY_PAYOUTS_N4_PACKED = 0x000241430000708c0000188c000008a5000002be000001190000000000000000;  // N4/heroGOLD EV=99.9999

    /// @dev Per-N S=9 jackpot tier (exceeds 32-bit slot; held as separate uint256).
    ///      Values are strictly monotonic in N.
    uint256 private constant QUICK_PLAY_PAYOUT_N0_S9 = 10_756_411; // 107,564.11x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_S9 = 12_583_037; // 125,830.37x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_S9 = 14_792_939; // 147,929.39x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_S9 = 17_512_324; // 175,123.24x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N4_S9 = 20_916_435; // 209,164.35x bet

    /// @dev Per-(N, hero-is-gold) S=8 tier (separate uint256, exceeds 32-bit slot).
    ///      Calibrated to basePayoutEV = 100 centi-x per honest sub-case (Option B).
    ///      N0/N4 collapse to one table each; N∈{1,2,3} split _HEROGOLD / _HEROCOMMON.
    uint256 private constant QUICK_PLAY_PAYOUT_N0_S8 =     5124517;  // N0/heroCOMMON    51,245.17x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_HEROGOLD_S8 =     5804753;  // N1/heroGOLD    58,047.53x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N1_HEROCOMMON_S8 =     5638394;  // N1/heroCOMMON    56,383.94x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_HEROGOLD_S8 =     6337987;  // N2/heroGOLD    63,379.87x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N2_HEROCOMMON_S8 =     6153960;  // N2/heroCOMMON    61,539.60x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_HEROGOLD_S8 =     6865005;  // N3/heroGOLD    68,650.05x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N3_HEROCOMMON_S8 =     6663665;  // N3/heroCOMMON    66,636.65x bet
    uint256 private constant QUICK_PLAY_PAYOUT_N4_S8 =     7388959;  // N4/heroGOLD    73,889.59x bet

    // -------------------------------------------------------------------------
    // WWXRP Bonus EV Redistribution (Full Ticket — 5 per-N factor tables)
    // -------------------------------------------------------------------------
    //
    // Per-N factors derived from each N's basePayout schedule + binomial-
    // convolution P_N(S) + 10/30/30/30 split across the top buckets S=6/7/8/9. Total
    // ETH bonus EV = exactly 5.000% per N. These honest factors serve ETH bets
    // (ETH_ROI_BONUS_BPS = 500); WWXRP uses the separate rigged factors below
    // (WWXRP_FACTORS_RIG_*) against its rigged distribution.
    //
    // Bit layout (B=6..9 packed): 64 bits per bucket index, [B=6 | B=7 | B=8 | B=9],
    // with B=6 in the low 64 bits. Read via `(packed >> ((bucket - 6) * 64)) & 0xFFFFFFFFFFFFFFFF`.
    //
    // The factor constants below are calibrated for the S∈{0..9} distribution so that
    // total ETH bonus EV = exactly 5.000% per N.
    uint256 private constant WWXRP_BONUS_FACTOR_SCALE = 1_000_000;
    uint256 private constant WWXRP_FACTORS_N0_PACKED = 0x0000000002278add00000000002c86d300000000008cd6ca0000000000176ea0;
    uint256 private constant WWXRP_FACTORS_N1_HEROGOLD_PACKED = 0x0000000003aef46a00000000003d043e0000000000b767d900000000001b448b;
    uint256 private constant WWXRP_FACTORS_N1_HEROCOMMON_PACKED = 0x0000000003aef46a00000000003ed11d0000000000ac8f35000000000019c09e;
    uint256 private constant WWXRP_FACTORS_N2_HEROGOLD_PACKED = 0x0000000006442ce700000000005b52330000000000e67b0800000000001f15da;
    uint256 private constant WWXRP_FACTORS_N2_HEROCOMMON_PACKED = 0x0000000006442ce700000000005e0d4c0000000000def66500000000001d41de;
    uint256 private constant WWXRP_FACTORS_N3_HEROGOLD_PACKED = 0x000000000a96251f00000000008e8baa000000000133ace4000000000024a679;
    uint256 private constant WWXRP_FACTORS_N3_HEROCOMMON_PACKED = 0x000000000a96251f000000000092da3f00000000012ed253000000000022cef8;
    uint256 private constant WWXRP_FACTORS_N4_PACKED = 0x0000000011ba25db0000000000e5669e0000000001aeccdd00000000002d2c05;

    // -------------------------------------------------------------------------
    // WWXRP RIG FAMILY — rigged base tables + factors (WWXRP currency only)
    // -------------------------------------------------------------------------
    //
    // WWXRP reels are rigged (DEC-01 R2, Variant-2 aware): when >= 2 cells are unmatched
    // (M <= 6), one *score-bearing* cell is forced to a real match with probability 3/5 —
    // an unmatched non-hero symbol (+1, or +2 when the color already matched: the unlock),
    // or an unmatched color on a symbol-matched quad (+1, incl. the hero color). The hero
    // symbol and no-op colors are excluded; an empty pool is a no-op. Caps at M=7 so the
    // rig can never make S=9 (P(S=9) invariant). The rig shifts the WWXRP score
    // distribution upward, so WWXRP uses its OWN per-N base tables — calibrated to
    // basePayoutEV = 100 centi-x against the RIGGED distribution P_N^rig(S) — and its OWN
    // per-N redistribution factors (the rigged family stays AVERAGED at 5 by-N tables;
    // WWXRP hero-placement drift accepted by-design). S=8 differs; S=9 reuses the honest
    // QUICK_PLAY_PAYOUT_N{N}_S9 pin (the jackpot event and odds are unchanged by the rig).
    // ETH/FLIP keep the per-(N,hero-gold) honest tables above. The byte-reproduce gate
    // regenerates these from derive_5_tables.py — never hand-typed.
    uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N0_PACKED = 0x00005e9a00001273000004030000016c000000730000002e0000000000000000;  // EV=99.9986
    uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N1_PACKED = 0x000070aa000015f6000004cc000001af00000089000000370000000000000000;  // EV=99.9995
    uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N2_PACKED = 0x00008532000019f6000005aa000001fe000000a2000000410000000000000000;  // EV=99.9989
    uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N3_PACKED = 0x00009b9a00001e5a0000069d00000254000000bd0000004c0000000000000000;  // EV=99.9990
    uint256 private constant QUICK_PLAY_PAYOUTS_RIG_N4_PACKED = 0x0000b330000022ed0000079d000002b1000000da000000570000000000000000;  // EV=99.9992

    /// @dev Per-N rigged S=8 tier (separate uint256; calibrated to EV=100 under the rigged dist).
    uint256 private constant QUICK_PLAY_PAYOUT_RIG_N0_S8 =     1210913;  //    12,109.13x bet
    uint256 private constant QUICK_PLAY_PAYOUT_RIG_N1_S8 =     1442106;  //    14,421.06x bet
    uint256 private constant QUICK_PLAY_PAYOUT_RIG_N2_S8 =     1704918;  //    17,049.18x bet
    uint256 private constant QUICK_PLAY_PAYOUT_RIG_N3_S8 =     1991686;  //    19,916.86x bet
    uint256 private constant QUICK_PLAY_PAYOUT_RIG_N4_S8 =     2293601;  //    22,936.01x bet

    /// @dev Per-N rigged WWXRP factors (B=6..9 packed, B=6 low). 10/30/30/30 split over
    ///      the rigged dist + rigged tables → bonus uplift = bonusBps/10000 of RTP exactly.
    uint256 private constant WWXRP_FACTORS_RIG_N0_PACKED = 0x0000000002278add00000000000ccc0200000000004153c400000000000fda8b;
    uint256 private constant WWXRP_FACTORS_RIG_N1_PACKED = 0x0000000003aef46a00000000000f5126000000000046a39f00000000000fa6f4;
    uint256 private constant WWXRP_FACTORS_RIG_N2_PACKED = 0x0000000006442ce7000000000013314300000000004ecda200000000000fd37a;
    uint256 private constant WWXRP_FACTORS_RIG_N3_PACKED = 0x000000000a96251f000000000019298500000000005b77db0000000000108293;
    uint256 private constant WWXRP_FACTORS_RIG_N4_PACKED = 0x0000000011ba25db00000000002269d300000000006ee3e2000000000011eefc;

    /// @dev Reel-independent seed tag for the WWXRP rig draw (gate + cell pick).
    uint256 private constant WWXRP_RIG_SALT = 0x52494721; // "RIG!"

    // -------------------------------------------------------------------------
    // Packed Bet Layout
    // -------------------------------------------------------------------------
    //
    // A bet packs into one uint256 (4 traits, match-based payouts):
    // [0..31]    customTraits (32 bits): packed 4×8-bit quadrants
    // [32..39]   spinCount (8 bits): per-currency cap (ETH 25 / FLIP 15 / WWXRP 5)
    // [40..41]   currency (2 bits)
    // [42..169]  amountPerSpin (128 bits)
    // [170..201] index (32 bits): lootbox RNG index
    // [202..217] activityScore (16 bits)
    // [218..219] heroQuadrant (2 bits): always-on hero quadrant (0..3)
    //
    /// EV-equality across picks: each pick maps to exactly one of 5 per-N tables;
    /// basePayoutEV is calibrated to 100 centi-x per table; runtime payout =
    /// bet × basePayout_N(M) × roiBps / 1_000_000. No per-outcome correction needed.
    //
    // -------------------------------------------------------------------------

    // Degenerette packed-bet bit positions
    uint256 private constant DEGEN_TRAITS_SHIFT = 0;
    uint256 private constant DEGEN_COUNT_SHIFT = 32;
    uint256 private constant DEGEN_CURRENCY_SHIFT = 40;
    uint256 private constant DEGEN_AMOUNT_SHIFT = 42;
    uint256 private constant DEGEN_INDEX_SHIFT = 170;
    uint256 private constant DEGEN_ACTIVITY_SHIFT = 202;
    uint256 private constant DEGEN_HERO_SHIFT = 218; // 2 bits: hero quadrant (0..3)

    // Common masks
    uint256 private constant MASK_2 = 0x3;
    uint256 private constant MASK_8 = 0xFF;
    uint256 private constant MASK_16 = 0xFFFF;
    uint256 private constant MASK_32 = 0xFFFFFFFF;
    uint256 private constant MASK_128 = (uint256(1) << 128) - 1;

    // -------------------------------------------------------------------------
    // Public API
    // -------------------------------------------------------------------------

    /// @notice Places a Degenerette bet (4 traits, match-based payouts).
    /// @dev Single chosen-attribute pick.
    ///      spinCount is treated as "spin count": each spin resolves independently but shares
    ///      the same lootbox RNG index/word (derived per spin).
    ///      The bet always belongs to `player` (zero address = caller). Funding source: the
    ///      player or an approved operator spends the player's funds; any other caller funds the
    ///      bet itself — a permissionless gift (the caller pays, the player receives the bet and
    ///      its winnings). WWXRP is excluded from gifting (player-or-approved only).
    /// @param player The player the bet belongs to (use zero address for msg.sender).
    /// @param currency Currency type (0=ETH, 1=FLIP, 2=unsupported, 3=WWXRP).
    /// @param amountPerSpin Bet amount per ticket.
    /// @param spinCount Number of spins (per-currency cap: ETH 25 / FLIP 15 / WWXRP 5).
    /// @param customTraits Custom packed traits. Format: [D:24-31][C:16-23][B:8-15][A:0-7].
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost. Required; inputs >= 4 (including 0xFF) revert with `InvalidBet`.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint32 customTraits,
        uint8 heroQuadrant
    ) external payable {
        if (player == address(0)) player = msg.sender;
        address funder;
        if (player == msg.sender || operatorApprovals[player][msg.sender]) {
            // The player or an approved operator spends the player's own funds.
            funder = player;
        } else {
            // Permissionless gift: the caller funds, the player receives the bet. WWXRP is
            // scarce/whale-pass-grade, so its bets stay player-or-approved only.
            if (currency == CURRENCY_WWXRP) revert NotApproved();
            funder = msg.sender;
        }
        _placeDegeneretteBet(
            player,
            funder,
            currency,
            amountPerSpin,
            spinCount,
            customTraits,
            heroQuadrant
        );
    }

    /// @dev Cross-bet payout accumulator threaded through resolveDegeneretteBets → _resolveBet
    ///      → _distributePayout. Per-currency payouts are
    ///      summed across the whole resolveDegeneretteBets call and flushed ONCE (additive, so
    ///      byte-identical to the per-spin writes). The prize-pool decrement runs
    ///      against a running local that mirrors the live storage value spin-by-spin:
    ///      read once at first ETH win, decremented in memory per spin (so each
    ///      spin's ETH_WIN_CAP_BPS cap sees the same shrinking pool it would have
    ///      read from storage today), written back once at flush. Lootbox-share is
    ///      NOT accumulated here — it is summed PER betId and resolved once per bet
    ///      inside _resolveBet (resolution-batch-invariant).
    struct ResolveAcc {
        uint256 ethClaimable; // summed ETH claimable across all bets
        uint256 flipMint; // summed FLIP mint across all bets
        uint256 wwxrpMint; // summed WWXRP mint across all bets
        bool poolFrozen; // prizePoolFrozen snapshot (loaded with the pool locals)
        bool poolLoaded; // running pool locals initialized?
        uint256 runningFuture; // unfrozen: running futurePrizePool
        uint128 pendingNext; // frozen: running pending next pool
        uint128 pendingFuture; // frozen: running pending future pool
    }

    /// @notice Resolves one or more pending bets for a player.
    /// @dev Permissionless: payouts always credit the bet owner, so any caller may settle
    ///      any player's bets. Requires RNG word to be available. Processes wins by minting
    ///      tokens or crediting ETH. ETH/FLIP/WWXRP payouts are accumulated across the whole
    ///      call and flushed once per currency (one mint per currency, one claimable +
    ///      claimablePool write, one prize-pool write); lootbox-share is summed per betId and
    ///      resolved per bet.
    /// @param player Bet owner whose bets to settle (use zero address for msg.sender).
    /// @param betIds Array of bet IDs to resolve.
    function resolveDegeneretteBets(address player, uint64[] calldata betIds) external {
        // Once game-over liveness has drained the balance into claimable, resolving a
        // pending bet would credit ETH claimable out of the already-distributed
        // futurePrizePool residual, pushing claimablePool above the ETH balance
        // (unbacked obligation). Same guard as claimWhalePass: pending bets are settled
        // by the game-over drain, never resolved into claimable after it.
        if (_livenessTriggered()) revert GameOver();
        // Permissionless: a resolved bet only ever credits the player who placed it, never the
        // caller, so anyone may settle any player's pending bets (zero address = caller).
        // Placement debits the funder (the player/approved operator, else the caller for a
        // gift), so it carries its own funding gate.
        if (player == address(0)) player = msg.sender;
        ResolveAcc memory acc;
        uint256 len = betIds.length;
        for (uint256 i; i < len; ) {
            // First bet (i==0) fail-fasts on an already-resolved/not-ready bet so a racing
            // duplicate settle bails cheaply; later bets skip instead, so an en-masse settle
            // tolerates stale/not-ready ids mixed into the batch.
            _resolveBet(player, betIds[i], acc, i == 0);
            unchecked {
                ++i;
            }
        }

        // Single per-currency flush (additive → byte-identical to the per-spin writes).
        if (acc.flipMint != 0) coin.mintForGame(player, acc.flipMint);
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

    /// @dev Internal implementation for placing a Degenerette bet. The bet (and its quest
    ///      progress / winnings) belongs to `player`; the funds are debited from `funder`
    ///      (== player for a self/approved bet, == the caller for a permissionless gift).
    function _placeDegeneretteBet(
        address player,
        address funder,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint32 customTraits,
        uint8 heroQuadrant
    ) private {
        uint24 lvl = level;
        uint256 totalBet = _placeDegeneretteBetCore(
            player,
            currency,
            amountPerSpin,
            spinCount,
            customTraits,
            heroQuadrant,
            lvl
        );

        _collectBetFunds(funder, currency, totalBet, msg.value);

        // Quest progress for Degenerette bets (slot 1 only) — credited to the funder (the
        // spender earns the quest, e.g. a gifter advancing their own streak).
        if (currency == CURRENCY_ETH || currency == CURRENCY_FLIP) {
            quests.handleDegenerette(
                funder,
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
        uint128 amountPerSpin,
        uint8 spinCount,
        uint32 customTraits,
        uint8 heroQuadrant,
        uint24 lvl
    ) private returns (uint256 totalBet) {
        // Single per-currency dispatch: spin cap + min bet together. The explicit
        // WWXRP arm keeps any unknown currency out of the WWXRP bounds — unsupported
        // values reject here, the only currency-validation point.
        uint8 maxSpins;
        uint256 minBet;
        if (currency == CURRENCY_ETH) {
            maxSpins = MAX_SPINS_ETH;
            minBet = MIN_BET_ETH;
        } else if (currency == CURRENCY_FLIP) {
            maxSpins = MAX_SPINS_FLIP;
            minBet = MIN_BET_FLIP;
        } else if (currency == CURRENCY_WWXRP) {
            maxSpins = MAX_SPINS_WWXRP;
            minBet = MIN_BET_WWXRP;
        } else {
            revert UnsupportedCurrency();
        }
        if (spinCount == 0 || spinCount > maxSpins) revert InvalidBet();
        if (uint256(amountPerSpin) < minBet) revert InvalidBet();
        if (heroQuadrant >= 4) revert InvalidBet();

        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (index == 0) revert NotStarted();
        if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();

        totalBet = uint256(amountPerSpin) * uint256(spinCount);
        // Decay-aware effective quest streak (mirrors the DECSTREAK chokepoint fix): a streak
        // lapsed past its shields reads 0, so a returning-inactive player can't snapshot a
        // stale-high streak into the bet's activityScore (which scales the ETH ROI and the
        // lootbox-share EV multiplier). WWXRP bets never sync via handleDegenerette, so a raw
        // playerQuestStates read would let the zombie streak persist indefinitely.
        uint32 questStreak = _effectiveQuestStreak(player);
        uint16 activityScore = uint16(
            _playerActivityScore(player, questStreak, lvl + 1)
        );

        // Pack the bet
        uint256 packed = _packDegeneretteBet(
            customTraits,
            spinCount,
            currency,
            amountPerSpin,
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
            uint8 heroSymbol = uint8(customTraits >> (heroQuadrant * 8)) & 7;
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

    /// @dev Processes bet funds (burn tokens, handle ETH, check pool).
    function _collectBetFunds(
        address player,
        uint8 currency,
        uint256 totalBet,
        uint256 ethPaid
    ) private {
        if (currency == CURRENCY_ETH) {
            // ETH covers the bet first; any shortfall draws claimable (to the 1-wei
            // sentinel) then afking via the canonical single-sink waterfall.
            if (ethPaid > totalBet) revert InvalidBet();
            if (ethPaid < totalBet) {
                _settleShortfall(player, totalBet - ethPaid, true);
            }

            // Update pool and pending
            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(pNext, pFuture + uint128(totalBet));
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(next, future + uint128(totalBet));
            }
            _lrAdd(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, _packEthToMilliEth(totalBet));
            // No max payout check needed: ETH payouts are capped at 10% of pool at distribution
            // time, so solvency is guaranteed regardless of jackpot size
        } else if (currency == CURRENCY_FLIP) {
            coin.burnCoin(player, totalBet);
            _lrAdd(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, _packFlipToWhole(totalBet));
        } else if (currency == CURRENCY_WWXRP) {
            wwxrp.burnForGame(player, totalBet);
        }
    }

    /// @dev Resolves a single bet: decodes the packed bet and materializes its spins against
    ///      the lootbox RNG word. Per-currency payouts accumulate into `acc` (flushed once
    ///      cross-bet by resolveDegeneretteBets); lootbox-share is summed across this bet's
    ///      spins and resolved ONCE here (one box per betId). `strict` is set for the first bet
    ///      of a batch: it reverts on any non-resolvable bet (already-resolved or RNG-not-ready)
    ///      so a racing duplicate settle bails cheaply; a trailing (non-strict) bet skips those
    ///      cases so one stale/not-ready id can't brick the rest of the batch.
    function _resolveBet(
        address player,
        uint64 betId,
        ResolveAcc memory acc,
        bool strict
    ) private {
        uint256 packed = degeneretteBets[player][betId];
        if (packed == 0) {
            if (strict) revert InvalidBet();
            return;
        }

        // Decode packed bet
        uint32 customTraits = uint32((packed >> DEGEN_TRAITS_SHIFT) & MASK_32);
        uint8 spinCount = uint8((packed >> DEGEN_COUNT_SHIFT) & MASK_8);
        uint8 currency = uint8((packed >> DEGEN_CURRENCY_SHIFT) & MASK_2);
        uint128 amountPerSpin = uint128(
            (packed >> DEGEN_AMOUNT_SHIFT) & MASK_128
        );
        uint32 index = uint32((packed >> DEGEN_INDEX_SHIFT) & MASK_32);
        uint16 activityScore = uint16((packed >> DEGEN_ACTIVITY_SHIFT) & MASK_16);
        uint8 heroQuadrant = uint8((packed >> DEGEN_HERO_SHIFT) & MASK_2);

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) {
            // RNG not yet fulfilled: the first bet reverts RngNotReady; a later bet skips
            // and stays pending for a future settle (same first-strict tolerance as the
            // packed==0 gate). Nothing is mutated above this point, so a skip is a clean no-op.
            if (strict) revert RngNotReady();
            return;
        }

        delete degeneretteBets[player][betId];

        // WWXRP uses a flat 70% floor (the rigged path); ETH/FLIP use the shared base ROI curve.
        uint256 roiBps = (currency == CURRENCY_WWXRP)
            ? WWXRP_FLOOR_BPS
            : _roiBpsFromScore(activityScore);
        // WWXRP total-RTP target for bonus redistribution (0 if not WWXRP).
        uint256 wwxrpHighRoi = (currency == CURRENCY_WWXRP)
            ? _wwxrpRoi(activityScore)
            : 0;

        uint32 playerTraits = customTraits;
        // Gold-quadrant count is a pure function of the player's pick — identical
        // for every spin of this bet, so it is computed once here.
        uint8 goldCount = _countGoldQuadrants(playerTraits);
        // Honest-lane payout selector: is the hero quadrant's color gold (bits 5-3 == 7)?
        // Constant for the bet (same pick + hero), so computed once with goldCount.
        bool heroIsGold = ((playerTraits >> (heroQuadrant * 8 + 3)) & 7) == 7;

        uint256 totalPayout;
        uint32 firstResultTraits;
        // Lootbox-share summed across THIS bet's spins → one box per betId.
        uint256 betLootboxShare;
        // Box value from high-match (s>=5) ETH spins only → affiliate reward basis.
        uint256 affiliateBoxShare;

        for (uint8 spinIdx; spinIdx < spinCount; ) {
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
            uint32 resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(
                resultSeed
            );
            // WWXRP-only reel rig (R2): lift one unmatched score-bearing cell to a real
            // match (60%) when >= 2 cells miss, so the displayed reel and the scored
            // result agree. A no-op for ETH/FLIP (and for WWXRP full / 1-off reels).
            if (currency == CURRENCY_WWXRP) {
                resultTraits = _rigWwxrpResult(
                    playerTraits,
                    resultTraits,
                    heroQuadrant,
                    EntropyLib.hash2(resultSeed, WWXRP_RIG_SALT)
                );
            }
            if (spinIdx == 0) {
                firstResultTraits = resultTraits;
            }

            // Score this spin: Variant-2 (color gated behind symbol, hero +2), S ∈ {0..9}
            uint8 s = _score(playerTraits, resultTraits, heroQuadrant);

            // Calculate payout (dispatches on the per-N score table)
            uint256 payout = _degenerettePayout(
                goldCount,
                s,
                currency,
                amountPerSpin,
                roiBps,
                wwxrpHighRoi,
                heroIsGold
            );

            emit DegeneretteResult(
                player,
                betId,
                spinIdx,
                playerTraits,
                s,
                payout
            );

            if (payout != 0) {
                totalPayout += payout;

                // Accumulate this spin's payout. ETH credits + the running-pool
                // decrement / cap land in `acc` (flushed cross-bet); the spin's
                // lootbox-share is returned and summed into this bet's box.
                uint256 spinLootboxShare = _distributePayout(
                    player,
                    currency,
                    amountPerSpin,
                    payout,
                    acc
                );
                betLootboxShare += spinLootboxShare;
                // Only a high-match (s>=5) spin's box value earns the affiliate reward;
                // the share is 0 for FLIP/WWXRP, so this stays ETH-only implicitly.
                if (s >= 5) affiliateBoxShare += spinLootboxShare;
            }

            // Award sDGNRS from Reward pool on S>=7 ETH bets. Stays per-spin:
            // _awardDegeneretteDgnrs reads poolBalance fresh per call, so summing
            // off a stale balance would change the payout.
            if (currency == CURRENCY_ETH && s >= 7) {
                _awardDegeneretteDgnrs(player, amountPerSpin, s);
            }

            // First WWXRP jackpot in this level/10 bracket grants the bettor one
            // whale halfpass (deferred via whalePassClaims, no ETH/pool touch).
            // The s == 9 check short-circuits first, so non-jackpot spins read no
            // new state. The award always credits the bet owner `player`.
            if (
                s == 9 &&
                currency == CURRENCY_WWXRP &&
                amountPerSpin >= MIN_BET_WWXRP
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

        // FLIP survival flip: every FLIP payout must survive one fair coinflip before
        // it mints — the bet's whole payout double-or-nothings on a single bet-keyed flip
        // (EV-neutral: x2 at 50/50). The seed is the per-bet lootbox seed, which FLIP
        // bets never otherwise consume (lootbox-share is ETH-only). Both rngWord and betId
        // are committed before the VRF word lands, so the outcome is fixed at fulfillment;
        // a losing bet pays zero whether resolved or abandoned, so selective resolution
        // earns nothing. The accumulator holds exactly this bet's payout once (added per
        // spin), so doubling adds it again and zeroing subtracts it back out. The outcome
        // reads off DegeneretteResolved: totalPayout vs the per-spin DegeneretteResult sums.
        if (currency == CURRENCY_FLIP && totalPayout != 0) {
            if (EntropyLib.hash2(rngWord, betId) & 1 == 1) {
                acc.flipMint += totalPayout;
                totalPayout *= 2;
            } else {
                acc.flipMint -= totalPayout;
                totalPayout = 0;
            }
        }

        // One lootbox per betId, on the summed lootbox-share. The box seed binds the immutable
        // betId (keccak'd with the index word) so each of a player's bets at the same index rolls
        // independently; the live lootbox-share is NOT a seed input. Never summed across betIds.
        if (betLootboxShare > 0) {
            // The bet-win recirc box itemizes its contents via LootBoxOpened (like every box path)
            // so the per-box FLIP datum is recoverable.
            _resolveLootboxDirect(
                player,
                betLootboxShare,
                EntropyLib.hash2(rngWord, betId),
                activityScore
            );
        }

        // Affiliate reward: 7% of the box value from high-match (s>=5) ETH spins, as FLIP
        // to the player's referrer (getReferrer returns VAULT when unreferred).
        if (affiliateBoxShare > 0) {
            uint256 refFlip = (affiliateBoxShare * PRICE_COIN_UNIT) /
                PriceLookupLib.priceForLevel(level + 1);
            coinflip.creditFlip(affiliate.getReferrer(player), (refFlip * 7) / 100);
        }

        emit DegeneretteResolved(
            player,
            betId,
            spinCount,
            totalPayout,
            firstResultTraits
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
    ///      CURRENCY_FLIP accumulates toward the coin mint (the per-bet survival
    ///      flip in _resolveBet then doubles or zeroes the bet's total
    ///      before the flush); CURRENCY_WWXRP pays directly via the wwxrp mint.
    ///      Neither honors the 3-tier split (which applies only to the
    ///      lootbox-convertible ETH path).
    /// @param player The player to receive the payout.
    /// @param currency The currency type (0=ETH, 1=FLIP, 3=WWXRP).
    /// @param betAmount The per-ticket bet amount (uint128) — the tier-threshold reference.
    /// @param payout The total payout amount (uint256).
    /// @param acc Cross-bet accumulator: ETH claimable + the running prize-pool
    ///        local accumulate here (flushed once by resolveDegeneretteBets); FLIP/WWXRP
    ///        mint totals accumulate here too.
    /// @return lootboxShare The ETH lootbox-share for this spin (0 for FLIP/WWXRP),
    ///         summed by the caller into the per-bet box.
    function _distributePayout(
        address player,
        uint8 currency,
        uint128 betAmount,
        uint256 payout,
        ResolveAcc memory acc
    ) private returns (uint256 lootboxShare) {
        if (currency == CURRENCY_ETH) {
            // 3-tier split rule
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
            // have held — byte-identical to per-spin. Flushed once by resolveDegeneretteBets.
            if (!acc.poolLoaded) {
                acc.poolLoaded = true;
                acc.poolFrozen = prizePoolFrozen;
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
                if (uint256(acc.pendingFuture) < ethShare) revert Insolvent();
                acc.pendingFuture -= uint128(ethShare);
            } else {
                // Unfrozen path: pool cap (ETH_WIN_CAP_BPS) takes PRECEDENCE over
                // the 3-tier split. After capping,
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
        } else if (currency == CURRENCY_FLIP) {
            acc.flipMint += payout;
        } else if (currency == CURRENCY_WWXRP) {
            acc.wwxrpMint += payout;
        }
    }

    /// @dev Delegates to the lootbox open module to resolve lootbox rewards directly.
    ///      Applies activity-score EV multiplier (90-145%) to match regular lootbox opens.
    ///      The resolved box itemizes its contents via `LootBoxOpened` like every box path.
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

    /// @dev Packs a Degenerette bet for storage. Hero quadrant is always-on.
    ///      Expects `heroQuadrant` in {0..3}; entry-point validation in
    ///      `_placeDegeneretteBetCore` reverts on `>= 4` with `InvalidBet`,
    ///      so the packed bet and the dailyHeroWagers ledger share the same
    ///      validated input. `spinCount` is validated `>= 1`, so a live bet
    ///      is always non-zero (the `packed == 0` resolved-sentinel holds).
    function _packDegeneretteBet(
        uint32 customTraits,
        uint8 spinCount,
        uint8 currency,
        uint128 amountPerSpin,
        uint32 index,
        uint16 activityScore,
        uint8 heroQuadrant
    ) private pure returns (uint256 packed) {
        packed =
            (uint256(customTraits) << DEGEN_TRAITS_SHIFT) |
            (uint256(spinCount) << DEGEN_COUNT_SHIFT) |
            (uint256(currency) << DEGEN_CURRENCY_SHIFT) |
            (uint256(amountPerSpin) << DEGEN_AMOUNT_SHIFT) |
            (uint256(index) << DEGEN_INDEX_SHIFT) |
            (uint256(activityScore) << DEGEN_ACTIVITY_SHIFT) |
            (uint256(heroQuadrant) << DEGEN_HERO_SHIFT);
    }

    // -------------------------------------------------------------------------
    // Bet Math + Outcome
    // -------------------------------------------------------------------------

    /// @dev Counts gold (color == 7) quadrants in a packed ticket.
    ///      Color tier occupies bits 5-3 of each per-quadrant byte; gold is the
    ///      strict equality `color == 7` (not `>= 7`). Returns N ∈ {0..4} —
    ///      the index for per-N payout / hero / WWXRP factor table dispatch.
    /// @param traits The packed player traits (uint32, [QQ][CCC][SSS] per byte).
    /// @return count Number of gold quadrants (0..4).
    function _countGoldQuadrants(uint32 traits) private pure returns (uint8 count) {
        unchecked {
            for (uint8 q = 0; q < 4; ++q) {
                uint8 color = uint8((traits >> (q * 8 + 3)) & 7);
                if (color == 7) ++count;
            }
        }
    }

    /// @dev Scores a player ticket against a result ticket — Variant-2
    ///      (color-gated-by-symbol). Per quadrant a SYMBOL match scores +1 (the hero
    ///      quadrant's symbol scores +2), and that quadrant's COLOR scores +1 ONLY IF
    ///      that quadrant's symbol ALSO matched. The color is no longer an independent
    ///      axis — it is gated behind the same quadrant's symbol. Net per quadrant:
    ///        ordinary: 0 (symbol miss) | +1 (symbol only) | +2 (symbol + color double)
    ///        hero:     0 (symbol miss) | +2 (hero symbol only) | +3 (hero maxed)
    ///      Max S = 9 (hero quad 3 + three ordinary quads ×2). S=9 is exactly the
    ///      all-8-axes event — byte-identical odds/pin to the old M=8 jackpot. The pay
    ///      floor S≥2 is NOT enforced here; it lives in the payout SHAPE (S=0,1 pay 0
    ///      in the constants, DEC-03) — `_score` returns the raw 0..9 score.
    /// @param playerTraits The player's ticket (packed traits).
    /// @param resultTraits The result ticket (packed traits).
    /// @param heroQuadrant The always-on hero quadrant (0..3) whose symbol scores +2.
    /// @return s Composite score (0-9).
    function _score(
        uint32 playerTraits,
        uint32 resultTraits,
        uint8 heroQuadrant
    ) private pure returns (uint8 s) {
        for (uint8 q = 0; q < 4; ) {
            uint8 pQuad = uint8(playerTraits >> (q * 8));
            uint8 rQuad = uint8(resultTraits >> (q * 8));

            // Symbol = bits 2-0. A symbol match scores +1 (hero quadrant +2). The
            // quadrant's COLOR (bits 5-3) scores +1 ONLY IF the symbol also matched
            // (Variant-2: color gated behind symbol — never counted on its own).
            if ((pQuad & 7) == (rQuad & 7)) {
                unchecked {
                    s += (q == heroQuadrant) ? 2 : 1;
                    if (((pQuad >> 3) & 7) == ((rQuad >> 3) & 7)) {
                        ++s;
                    }
                }
            }

            unchecked {
                ++q;
            }
        }
    }

    /// @dev Maps a score S to a WWXRP bonus bucket.
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
    /// @param isWwxrp True selects the rigged WWXRP factor family (by N only, averaged
    ///        by-design); false the honest (ETH/FLIP) family.
    /// @param heroIsGold Whether the player's hero quadrant is gold. Consulted ONLY on the
    ///        honest lane (!isWwxrp) — the honest factors are split per (N, heroIsGold)
    ///        (DEC-02 Option B; N0/N4 collapse). Ignored on the rigged WWXRP lane.
    /// @return factor 64-bit factor; multiply with `bonusRoiBps` and divide by `WWXRP_BONUS_FACTOR_SCALE`.
    function _wwxrpFactor(uint8 N, uint8 bucket, bool isWwxrp, bool heroIsGold) private pure returns (uint256 factor) {
        uint256 packed;
        if (isWwxrp) {
            // Rigged WWXRP lane: by N only (averaged over hero placement by-design).
            if (N == 0) packed = WWXRP_FACTORS_RIG_N0_PACKED;
            else if (N == 1) packed = WWXRP_FACTORS_RIG_N1_PACKED;
            else if (N == 2) packed = WWXRP_FACTORS_RIG_N2_PACKED;
            else if (N == 3) packed = WWXRP_FACTORS_RIG_N3_PACKED;
            else packed = WWXRP_FACTORS_RIG_N4_PACKED;
        } else if (N == 0) {
            // Honest lane, (N, heroIsGold): N0 always hero-common -> one table.
            packed = WWXRP_FACTORS_N0_PACKED;
        } else if (N == 4) {
            // N4 always hero-gold -> one table.
            packed = WWXRP_FACTORS_N4_PACKED;
        } else if (heroIsGold) {
            // N in {1,2,3}, hero gold.
            if (N == 1) packed = WWXRP_FACTORS_N1_HEROGOLD_PACKED;
            else if (N == 2) packed = WWXRP_FACTORS_N2_HEROGOLD_PACKED;
            else packed = WWXRP_FACTORS_N3_HEROGOLD_PACKED;
        } else {
            // N in {1,2,3}, hero common.
            if (N == 1) packed = WWXRP_FACTORS_N1_HEROCOMMON_PACKED;
            else if (N == 2) packed = WWXRP_FACTORS_N2_HEROCOMMON_PACKED;
            else packed = WWXRP_FACTORS_N3_HEROCOMMON_PACKED;
        }
        factor = (packed >> (uint256(bucket - 6) * 64)) & 0xFFFFFFFFFFFFFFFF;
    }

    /// @dev Calculates Full Ticket payout based on the score S and activity score ROI.
    ///      On the honest (ETH/FLIP) lane it dispatches per (N, heroIsGold) — the
    ///      gold-quadrant count plus whether the hero quadrant is gold (DEC-02 Option B,
    ///      exact EV-equality across hero placement under Variant-2). The rigged WWXRP
    ///      lane dispatches by N only (heroIsGold ignored — averaged by-design). Each
    ///      sub-case table is calibrated so basePayoutEV = exactly 100 centi-x against its
    ///      own Variant-2 P(S) — equal EV across picks within rounding. The hero is scored
    ///      directly into S (Variant-2), so there is no separate hero multiplier.
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param s The composite score (0-9).
    /// @param currency Currency type (0=ETH, 1=FLIP, 3=WWXRP).
    /// @param betAmount The bet amount per ticket.
    /// @param roiBps The ROI in basis points (from activity score).
    /// @param wwxrpHighRoi The WWXRP total-RTP target (0 if not WWXRP).
    /// @param heroIsGold Whether the player's hero quadrant is gold (honest-lane selector).
    /// @return payout The payout amount.
    function _degenerettePayout(
        uint8 N,
        uint8 s,
        uint8 currency,
        uint128 betAmount,
        uint256 roiBps,
        uint256 wwxrpHighRoi,
        bool heroIsGold
    ) private pure returns (uint256 payout) {
        bool isWwxrp = currency == CURRENCY_WWXRP;
        uint256 basePayoutBps = _getBasePayoutBps(N, s, isWwxrp, heroIsGold);

        // Bonus ROI is redistributed into the top score buckets via per-N factor lookup.
        uint256 effectiveRoi = roiBps;
        uint8 bucket = _wwxrpBonusBucket(s);
        if (bucket != 0) {
            uint256 baseBonus;
            if (isWwxrp && wwxrpHighRoi > roiBps) {
                baseBonus = wwxrpHighRoi - roiBps;
            } else if (currency == CURRENCY_ETH) {
                baseBonus = ETH_ROI_BONUS_BPS;
            }
            if (baseBonus != 0) {
                uint256 factor = _wwxrpFactor(N, bucket, isWwxrp, heroIsGold);
                effectiveRoi = roiBps + (baseBonus * factor) / WWXRP_BONUS_FACTOR_SCALE;
            }
        }

        // Apply ROI scaling: payout = betAmount × basePayout × roiBps / 1_000_000
        // basePayout is in "centi-x" (190 = 1.90x), roiBps is in bps (9000 = 90%).
        payout =
            (uint256(betAmount) * basePayoutBps * effectiveRoi) /
            1_000_000;
    }

    /// @dev Dispatches to the base payout table for the given score S.
    ///      S = 0..7 are packed 32 bits each into the table's _PACKED constant; S = 8 and
    ///      S = 9 each exceed the 32-bit slot so each table has separate _S8 / _S9
    ///      constants (S=9 is the jackpot tier). On the honest (ETH/FLIP) lane the table
    ///      is indexed by (N, heroIsGold) (DEC-02 Option B, exact EV-equality); the rigged
    ///      WWXRP lane is indexed by N only (heroIsGold ignored — averaged by-design). The
    ///      S=9 pin is by N only (P(S=9) is placement-independent, shared across lanes).
    /// @param N Gold-quadrant count of the player ticket (0..4).
    /// @param s Composite score (0..9).
    /// @param isWwxrp True selects the rigged WWXRP base table (S=0..8); false the honest
    ///        (ETH/FLIP) table. S=9 is shared — the rig leaves the jackpot pin unchanged.
    /// @param heroIsGold Whether the player's hero quadrant is gold — honest-lane selector
    ///        (N0/N4 collapse to one table each; consulted only for N in {1,2,3}).
    /// @return Base payout in centi-x (e.g. 204 = 2.04x at 100% ROI).
    function _getBasePayoutBps(uint8 N, uint8 s, bool isWwxrp, bool heroIsGold) private pure returns (uint256) {
        if (s >= 9) {
            // S=9 jackpot pin: by N only (P(S=9) placement-independent; shared by both lanes).
            if (N == 0) return QUICK_PLAY_PAYOUT_N0_S9;
            if (N == 1) return QUICK_PLAY_PAYOUT_N1_S9;
            if (N == 2) return QUICK_PLAY_PAYOUT_N2_S9;
            if (N == 3) return QUICK_PLAY_PAYOUT_N3_S9;
            return QUICK_PLAY_PAYOUT_N4_S9;
        }
        if (s == 8) {
            if (isWwxrp) {
                // Rigged WWXRP lane: by N only.
                if (N == 0) return QUICK_PLAY_PAYOUT_RIG_N0_S8;
                if (N == 1) return QUICK_PLAY_PAYOUT_RIG_N1_S8;
                if (N == 2) return QUICK_PLAY_PAYOUT_RIG_N2_S8;
                if (N == 3) return QUICK_PLAY_PAYOUT_RIG_N3_S8;
                return QUICK_PLAY_PAYOUT_RIG_N4_S8;
            }
            // Honest lane: by (N, heroIsGold). N0/N4 collapse to one table each.
            if (N == 0) return QUICK_PLAY_PAYOUT_N0_S8;
            if (N == 4) return QUICK_PLAY_PAYOUT_N4_S8;
            if (heroIsGold) {
                if (N == 1) return QUICK_PLAY_PAYOUT_N1_HEROGOLD_S8;
                if (N == 2) return QUICK_PLAY_PAYOUT_N2_HEROGOLD_S8;
                return QUICK_PLAY_PAYOUT_N3_HEROGOLD_S8;
            }
            if (N == 1) return QUICK_PLAY_PAYOUT_N1_HEROCOMMON_S8;
            if (N == 2) return QUICK_PLAY_PAYOUT_N2_HEROCOMMON_S8;
            return QUICK_PLAY_PAYOUT_N3_HEROCOMMON_S8;
        }
        uint256 packed;
        if (isWwxrp) {
            // Rigged WWXRP lane: by N only.
            if (N == 0) packed = QUICK_PLAY_PAYOUTS_RIG_N0_PACKED;
            else if (N == 1) packed = QUICK_PLAY_PAYOUTS_RIG_N1_PACKED;
            else if (N == 2) packed = QUICK_PLAY_PAYOUTS_RIG_N2_PACKED;
            else if (N == 3) packed = QUICK_PLAY_PAYOUTS_RIG_N3_PACKED;
            else packed = QUICK_PLAY_PAYOUTS_RIG_N4_PACKED;
        } else if (N == 0) {
            // Honest lane, (N, heroIsGold): N0 always hero-common -> one table.
            packed = QUICK_PLAY_PAYOUTS_N0_PACKED;
        } else if (N == 4) {
            // N4 always hero-gold -> one table.
            packed = QUICK_PLAY_PAYOUTS_N4_PACKED;
        } else if (heroIsGold) {
            // N in {1,2,3}, hero gold.
            if (N == 1) packed = QUICK_PLAY_PAYOUTS_N1_HEROGOLD_PACKED;
            else if (N == 2) packed = QUICK_PLAY_PAYOUTS_N2_HEROGOLD_PACKED;
            else packed = QUICK_PLAY_PAYOUTS_N3_HEROGOLD_PACKED;
        } else {
            // N in {1,2,3}, hero common.
            if (N == 1) packed = QUICK_PLAY_PAYOUTS_N1_HEROCOMMON_PACKED;
            else if (N == 2) packed = QUICK_PLAY_PAYOUTS_N2_HEROCOMMON_PACKED;
            else packed = QUICK_PLAY_PAYOUTS_N3_HEROCOMMON_PACKED;
        }
        return (packed >> (uint256(s) * 32)) & 0xFFFFFFFF;
    }

    // -------------------------------------------------------------------------
    // Payout Math
    // -------------------------------------------------------------------------

    /// @dev Computes ROI in basis points based on activity score.
    ///      Steep ramp 90%→98.91% (0 to K=305 points), shallow leg 98.91%→99.7%
    ///      (305 to the seg-B knee), then a near-flat crawl to 99.9% at the effective cap.
    ///      Stays strictly below 100% at every score.
    /// @param score The activity score in whole points.
    /// @return roiBps The ROI in basis points.
    function _roiBpsFromScore(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score >= ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            return ROI_MAX_BPS;
        }
        if (score <= ACTIVITY_SCORE_MAX_POINTS) {
            return
                ROI_MIN_BPS +
                (score * (ROI_VA_BPS - ROI_MIN_BPS)) /
                ACTIVITY_SCORE_MAX_POINTS;
        }
        if (score <= ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                ROI_VA_BPS +
                ((score - ACTIVITY_SCORE_MAX_POINTS) * (ROI_VB_BPS - ROI_VA_BPS)) /
                (ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS -
                    ACTIVITY_SCORE_MAX_POINTS);
        }
        return
            ROI_VB_BPS +
            ((score - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) *
                (ROI_MAX_BPS - ROI_VB_BPS)) /
            (ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS -
                ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @dev WWXRP total-RTP curve E(score): the rigged WWXRP payout RTP equals this
    ///      value / 10000. Steep ramp 70%→115% (0 to K=305), shallow leg to 118%
    ///      (seg-B knee), near-flat crawl to 120% at the effective cap, flat beyond.
    ///      Used as the bonus-redistribution target above the flat WWXRP_FLOOR_BPS;
    ///      MIN equals the floor, so redistribution is zero at score 0 and grows with activity.
    /// @param score The activity score in whole points.
    /// @return roiBps The WWXRP total-RTP target in basis points.
    function _wwxrpRoi(
        uint256 score
    ) private pure returns (uint256 roiBps) {
        if (score >= ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            return WWXRP_ROI_MAX_BPS;
        }
        if (score <= ACTIVITY_SCORE_MAX_POINTS) {
            return
                WWXRP_ROI_MIN_BPS +
                (score * (WWXRP_ROI_VA_BPS - WWXRP_ROI_MIN_BPS)) /
                ACTIVITY_SCORE_MAX_POINTS;
        }
        if (score <= ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) {
            return
                WWXRP_ROI_VA_BPS +
                ((score - ACTIVITY_SCORE_MAX_POINTS) *
                    (WWXRP_ROI_VB_BPS - WWXRP_ROI_VA_BPS)) /
                (ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS -
                    ACTIVITY_SCORE_MAX_POINTS);
        }
        return
            WWXRP_ROI_VB_BPS +
            ((score - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) *
                (WWXRP_ROI_MAX_BPS - WWXRP_ROI_VB_BPS)) /
            (ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS -
                ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @dev WWXRP-only reel rig — DEC-01 R2 SCORE-BEARING pool (Variant-2 aware).
    ///      When >= 2 cells are unmatched (M <= 6), force ONE *score-bearing* cell to a
    ///      real match with probability 3/5. Under Variant-2 only these unmatched cells
    ///      RAISE S, so the eligible pool is narrowed to:
    ///        (a) an unmatched NON-HERO symbol (any color state) — forcing the symbol
    ///            lifts S by +1, or by +2 when that quadrant's color already matched (the
    ///            forced symbol UNLOCKS the gated color; the +2 unlock is ALLOWED); and
    ///        (b) an unmatched COLOR on a quadrant whose symbol ALREADY matched
    ///            (symMatch && !colorMatch) — forcing the color lifts S by +1. This
    ///            INCLUDES the hero quadrant's color (an ordinary axis); only the hero
    ///            SYMBOL is excluded from the pool.
    ///      EXCLUDED: the hero symbol cell, and *no-op* colors (an unmatched color on a
    ///      quadrant whose symbol is still unmatched — buys nothing under Variant-2).
    ///      EMPTY-POOL no-op: if M <= 6 but every unmatched cell is excluded (only the
    ///      hero symbol and/or no-op colors), the eligible count u == 0 — no lift this
    ///      round (and the `% u` pick is guarded against div-by-zero). Caps at M=7, so a
    ///      fired roll has M <= 6 -> post-force M <= 7 -> S <= 8: the rig can NEVER make
    ///      S=9 (P(S=9) invariant). Rewrites `resultTraits` so the displayed reel honestly
    ///      shows the forced match; `_score` then reads the lifted score. `rigSeed` is a
    ///      frozen, reel-independent hash of the spin seed. Matches the generator's
    ///      `p_score_distribution_rigged` per-pick +1/+2 model.
    /// @param playerTraits The player's (or box-spin's) ticket.
    /// @param resultTraits The drawn result reel.
    /// @param heroQuadrant The hero quadrant (0..3) whose SYMBOL is excluded from the rig pool.
    /// @param rigSeed Reel-independent rig entropy (gate + cell pick).
    /// @return rigged The (possibly modified) result ticket.
    function _rigWwxrpResult(
        uint32 playerTraits,
        uint32 resultTraits,
        uint8 heroQuadrant,
        uint256 rigSeed
    ) private pure returns (uint32 rigged) {
        rigged = resultTraits;
        // Pass 1: count matched axes (M, all 8) and SCORE-BEARING eligible cells (u).
        uint8 m;
        uint8 u;
        for (uint8 q; q < 4; ) {
            uint8 pq = uint8(playerTraits >> (q * 8));
            uint8 rq = uint8(resultTraits >> (q * 8));
            bool colorMatch = ((pq >> 3) & 7) == ((rq >> 3) & 7);
            bool symMatch = (pq & 7) == (rq & 7);
            if (colorMatch) ++m;
            if (symMatch) ++m;
            // (b) unmatched color on a symbol-matched quad (incl. the hero quad's color):
            //     forcing the color unlocks +1 (Variant-2: color counts only when its
            //     own symbol matched). A no-op color (symbol still unmatched) is excluded.
            if (symMatch && !colorMatch) ++u;
            // (a) unmatched non-hero symbol: forcing the symbol scores +1 (or +2 if the
            //     color already matched — the +2 unlock). The hero symbol is excluded.
            if (q != heroQuadrant && !symMatch) ++u;
            unchecked {
                ++q;
            }
        }
        // Only rig when >= 2 cells miss (M <= 6); leave full match / 1-off alone.
        if (m >= 7) return rigged;
        // 60% gate (3 of 5); 40% no-op.
        if (rigSeed % 5 >= 3) return rigged;
        // Empty score-bearing pool (every unmatched cell is excluded): no lift, guard the
        // uniform pick against a division-by-zero on `% u`.
        if (u == 0) return rigged;
        // Pick one score-bearing cell uniformly (u >= 1 here).
        uint8 pick = uint8((rigSeed >> 8) % u);
        // Pass 2: walk the SAME fixed order with the SAME pass-1 eligibility predicates so
        // the pick index lines up; force the pick-th score-bearing cell.
        for (uint8 q; q < 4; ) {
            uint8 pq = uint8(playerTraits >> (q * 8));
            uint8 rq = uint8(resultTraits >> (q * 8));
            bool colorMatch = ((pq >> 3) & 7) == ((rq >> 3) & 7);
            bool symMatch = (pq & 7) == (rq & 7);
            // (b) eligible color: symbol already matched, color unmatched (incl. hero color).
            if (symMatch && !colorMatch) {
                if (pick == 0) {
                    // Force the result color to the player's color (bits 5-3 of the byte).
                    return
                        (rigged & ~(uint32(0x38) << (q * 8))) |
                        (uint32((pq >> 3) & 7) << (q * 8 + 3));
                }
                unchecked {
                    --pick;
                }
            }
            // (a) eligible symbol: non-hero quadrant, symbol unmatched.
            if (q != heroQuadrant && !symMatch) {
                if (pick == 0) {
                    // Force the result symbol to the player's symbol (bits 2-0). The +2
                    // unlock (when this quad's color already matched) happens naturally.
                    return
                        (rigged & ~(uint32(0x07) << (q * 8))) |
                        (uint32(pq & 7) << (q * 8));
                }
                unchecked {
                    --pick;
                }
            }
            unchecked {
                ++q;
            }
        }
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
            IsDGNRS.Pool.Reward
        );
        if (poolBalance == 0) return;

        uint256 cappedBet = betWei > 1 ether ? 1 ether : betWei;
        uint256 reward = (poolBalance * bps * cappedBet) / (10_000 * 1 ether);
        if (reward == 0) return;

        sdgnrs.transferFromPool(
            IsDGNRS.Pool.Reward,
            player,
            reward
        );
    }

    // -------------------------------------------------------------------------
    // Lootbox-triggered Degenerette spins
    // -------------------------------------------------------------------------
    // Three lootbox value rolls resolve as Degenerette spins instead of flat awards.
    // Each is delegatecalled by the lootbox module in the Game's storage context; the
    // `address(this) != GAME` guard rejects any direct call on the deployed module
    // instance. Spin draws derive purely from the passed (hash2-tagged, freeze-safe)
    // seed — no live state enters the seed, so the outcome is fixed at fulfillment.
    // Each spin emits the same DegeneretteResult / DegeneretteResolved pair a regular bet
    // does (synthetic betId = low 64 bits of the seed) so the off-chain indexer renders
    // box spins exactly like ordinary spins, plus one Box* marker carrying the box-origin
    // stake / split.

    uint256 private constant BOX_FLIP_SPINS = 3;
    uint256 private constant BOX_SURVIVAL_TAG = 0x537572766976616c; // "Survival"
    uint256 private constant BOX_RECIRC_TAG = 0x5265636972; // "Recir"

    // Box-spin BoxSpin.betId header. Bit 63 is a box-origin sentinel (real bet nonces increment
    // from 1, so they never reach it); bits 62-60 carry the spin type; bits 59-0 are seed entropy
    // (a unique per-box-spin id). The off-chain UI reads `betId >> 63` (is-box-spin) and
    // `(betId >> 60) & 7` (type) directly off the indexed topic.
    uint256 private constant BOX_BETID_SENTINEL = uint256(1) << 63;
    uint8 private constant BOX_SPIN_TYPE_WWXRP = 0;
    uint8 private constant BOX_SPIN_TYPE_FLIP = 1;
    uint8 private constant BOX_SPIN_TYPE_ETH = 2;
    // BoxSpin.packedSpins layout: spin i occupies bits [i*72 .. i*72+71] as
    // [playerTraits:32 | resultTraits:32 | score:8]; bits 216-223 = spin count; bit 224 = survived.
    uint256 private constant BOX_SPIN_COUNT_SHIFT = 216;
    uint256 private constant BOX_SPIN_SURVIVED_SHIFT = 224;

    function _boxBetId(uint256 seed, uint8 spinType) private pure returns (uint64) {
        return uint64(
            BOX_BETID_SENTINEL |
            (uint256(spinType) << 60) |
            (seed & ((uint256(1) << 60) - 1))
        );
    }

    /// @dev Pack one spin's reel into `packedSpins` at slot `i` (72 bits): player ticket,
    ///      result ticket, score. OR the returned word into the accumulator.
    function _packSpin(
        uint256 i,
        uint32 playerTraits,
        uint32 resultTraits,
        uint8 score
    ) private pure returns (uint256) {
        return
            (uint256(playerTraits) |
                (uint256(resultTraits) << 32) |
                (uint256(score) << 64)) << (i * 72);
    }

    /// @notice One WWXRP Degenerette spin staking a lootbox WWXRP roll (replaces the flat mint).
    /// @dev Mirrors a regular WWXRP bet spin: the same reel rig, the rigged tables + total-RTP
    ///      bonus redistribution, and the S==9 bracket whale-halfpass award (deduped
    ///      one-per-10-level-bracket, shared with ordinary WWXRP jackpots). No pool / ETH touch —
    ///      WWXRP is minted directly.
    function resolveWwxrpSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint32 customTraits
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (stake == 0 || stake > type(uint128).max) return;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_WWXRP);
        uint128 betAmount = uint128(stake);
        uint256 roiBps = WWXRP_FLOOR_BPS;
        uint256 wwxrpHighRoi = _wwxrpRoi(activityScore);

        uint8 heroQuadrant = uint8(seed & MASK_2);
        uint32 playerTraits = customTraits != 0
            ? customTraits
            : DegenerusTraitUtils.packedTraitsDegenerette(seed);
        uint32 resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(
            EntropyLib.hash2(seed, 1)
        );
        // WWXRP reel rig (identical to a regular WWXRP bet spin, R2): lift one unmatched
        // score-bearing cell to a real match (60%) when >= 2 cells miss. The emitted
        // BoxSpin packs the rigged reel, so the displayed result and the score agree.
        resultTraits = _rigWwxrpResult(
            playerTraits,
            resultTraits,
            heroQuadrant,
            EntropyLib.hash2(seed, WWXRP_RIG_SALT)
        );
        uint8 s = _score(playerTraits, resultTraits, heroQuadrant);
        uint256 payout = _degenerettePayout(
            _countGoldQuadrants(playerTraits),
            s,
            CURRENCY_WWXRP,
            betAmount,
            roiBps,
            wwxrpHighRoi,
            ((playerTraits >> (heroQuadrant * 8 + 3)) & 7) == 7
        );

        if (payout != 0) wwxrp.mintPrize(player, payout);

        // S==9 jackpot grants the bracket's one whale halfpass (identical to a regular
        // WWXRP bet jackpot; the per-bracket flag is shared, so still one award per bracket).
        if (s == 9 && betAmount >= MIN_BET_WWXRP) {
            uint256 bracket = uint256(level) / 10;
            if (!wwxrpJackpotWhalePassBracketAwarded[bracket]) {
                whalePassClaims[player] += 1;
                wwxrpJackpotWhalePassBracketAwarded[bracket] = true;
                emit WwxrpJackpotWhalePass(player, bracket);
            }
        }

        // One self-contained record: the single reel + WWXRP-minted payout (no ETH split).
        emit BoxSpin(
            player,
            betId,
            _packSpin(0, playerTraits, resultTraits, s) |
                (uint256(1) << BOX_SPIN_COUNT_SHIFT),
            payout,
            0
        );
    }

    /// @notice Three FLIP Degenerette spins under one survival flip (mint-only, safe on any box).
    /// @dev The total stake is split evenly across three spins; the summed payout then double-or-
    ///      nothings on one fair flip (EV-neutral) before a single FLIP mint. No pool / ETH /
    ///      recirc touch, so this is solvency-safe on every box path including recirc.
    function resolveFlipSpinsFromBox(
        address player,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed,
        uint32 customTraits
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (totalStake == 0) return;
        uint128 perSpin = uint128(totalStake / BOX_FLIP_SPINS);
        if (perSpin == 0) return;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_FLIP);
        uint256 roiBps = _roiBpsFromScore(activityScore);

        uint256 total;
        uint256 packedSpins;
        for (uint256 i; i < BOX_FLIP_SPINS; ) {
            uint256 ss = EntropyLib.hash2(seed, i);
            uint32 playerTraits = customTraits != 0
                ? customTraits
                : DegenerusTraitUtils.packedTraitsDegenerette(ss);
            uint32 resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(
                EntropyLib.hash2(ss, 1)
            );
            // Hoist the hero quadrant to a named local so _score and the heroIsGold
            // derivation read the same value.
            uint8 heroQuadrant = uint8(ss & MASK_2);
            uint8 s = _score(playerTraits, resultTraits, heroQuadrant);
            total += _degenerettePayout(
                _countGoldQuadrants(playerTraits),
                s,
                CURRENCY_FLIP,
                perSpin,
                roiBps,
                0,
                ((playerTraits >> (heroQuadrant * 8 + 3)) & 7) == 7
            );
            packedSpins |= _packSpin(i, playerTraits, resultTraits, s);
            unchecked {
                ++i;
            }
        }

        // Survival flip on the summed payout (the seed bit never otherwise consumed by the spins).
        bool survived = total != 0 &&
            (EntropyLib.hash2(seed, BOX_SURVIVAL_TAG) & 1 == 1);
        total = survived ? total * 2 : 0;
        if (total != 0) coin.mintForGame(player, total);

        // One self-contained record: all three reels + count + survival + the final FLIP mint.
        packedSpins |=
            (uint256(BOX_FLIP_SPINS) << BOX_SPIN_COUNT_SHIFT) |
            (survived ? (uint256(1) << BOX_SPIN_SURVIVED_SHIFT) : 0);
        emit BoxSpin(player, betId, packedSpins, total, 0);
    }

    /// @notice One ETH Degenerette spin staking a lootbox roll's ticket budget.
    /// @dev Reuses the regular 3-tier ETH split (`_distributePayout`): the ETH share credits
    ///      claimable and the lootbox share recircs into a fresh re-hashed box. This spin's
    ///      pool/claimable writes are flushed to storage BEFORE the recirc so the recirc reads
    ///      fresh state, and the recirc box is opened with the ETH-spin path disabled (the box
    ///      module passes allowEthSpin=false on the recirc entry) so no ETH-spin can cascade.
    function resolveEthSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed,
        uint32 customTraits
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (stake == 0 || stake > type(uint128).max) return;
        uint64 betId = _boxBetId(seed, BOX_SPIN_TYPE_ETH);
        uint128 betAmount = uint128(stake);
        uint256 roiBps = _roiBpsFromScore(activityScore);

        uint32 playerTraits = customTraits != 0
            ? customTraits
            : DegenerusTraitUtils.packedTraitsDegenerette(seed);
        uint32 resultTraits = DegenerusTraitUtils.packedTraitsDegenerette(
            EntropyLib.hash2(seed, 1)
        );
        // Hoist the hero quadrant to a named local so _score and the heroIsGold
        // derivation read the same value.
        uint8 heroQuadrant = uint8(seed & MASK_2);
        uint8 s = _score(playerTraits, resultTraits, heroQuadrant);
        uint256 payout = _degenerettePayout(
            _countGoldQuadrants(playerTraits),
            s,
            CURRENCY_ETH,
            betAmount,
            roiBps,
            0,
            ((playerTraits >> (heroQuadrant * 8 + 3)) & 7) == 7
        );

        uint256 packed = _packSpin(0, playerTraits, resultTraits, s) |
            (uint256(1) << BOX_SPIN_COUNT_SHIFT);
        if (payout == 0) {
            emit BoxSpin(player, betId, packed, 0, 0);
            return;
        }

        ResolveAcc memory acc;
        uint256 lootboxShare = _distributePayout(player, CURRENCY_ETH, betAmount, payout, acc);
        if (s >= 7) _awardDegeneretteDgnrs(player, betAmount, s);

        // Flush THIS spin's pool/claimable BEFORE recirc so recirc reads fresh storage.
        if (acc.ethClaimable != 0) _addClaimableEth(player, acc.ethClaimable);
        if (acc.poolLoaded) {
            if (acc.poolFrozen) {
                _setPendingPools(acc.pendingNext, acc.pendingFuture);
            } else {
                _setFuturePrizePool(acc.runningFuture);
            }
        }

        // One self-contained record: the reel + ETH gross + the claimable share. The
        // recirculated remainder (payout - ethShare) is itemized by the recirc box's own events.
        emit BoxSpin(player, betId, packed, payout, acc.ethClaimable);

        // Recirc into a fresh re-hashed box; allowEthSpin=false there -> no ETH-spin cascade.
        // The recirculated box's contents are itemized for the UI via its own LootBoxOpened.
        if (lootboxShare != 0) {
            _resolveLootboxDirect(
                player,
                lootboxShare,
                EntropyLib.hash2(seed, BOX_RECIRC_TAG),
                activityScore
            );
        }
    }
}
