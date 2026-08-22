// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended, not a
 * malfunction and not a defect. Do not commit funds you are not prepared to lose
 * entirely.
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
import {IStETH} from "../interfaces/IStETH.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

import {IDegenerusGameBoonModule, IDegenerusGameDegeneretteModule} from "../interfaces/IDegenerusGameModules.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {RECORD_KIND_LUCKBOX} from "../interfaces/ICoinflip.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {FlipRoundLib} from "../libraries/FlipRoundLib.sol";
import {SigFigLib} from "../libraries/SigFigLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";

/// @notice Interface for minting WWXRP prize tokens
interface IWWXRP {
    /// @notice Mint prize tokens to a recipient
    /// @param to The address to receive the prize
    /// @param amount The amount of tokens to mint
    function mintPrize(address to, uint256 amount) external;
}

/**
 * @title DegenerusGameLootboxModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for lootbox opening, boon consumption, and deity boon system.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - Box opening (openBox, resolveLootboxDirect, resolveRedemptionLootbox)
 * - Deity boon system (issueDeityBoon)
 */
contract DegenerusGameLootboxModule is DegenerusGameStorage {
    // =========================================================================
    // Errors
    // =========================================================================

    // error E() — inherited from DegenerusGameStorage
    error MsgValueExceedsAmount(); // msg.value exceeds the declared lootbox or credit amount

    /// @notice RNG word has not been set for the requested lootbox index
    error RngNotReady();


    // =========================================================================
    // Events
    // =========================================================================


    /// @notice Emitted when an ETH lootbox is successfully opened
    /// @param player The player who opened the lootbox
    /// @param lootboxIndex The shared (system-wide) RNG index of the opened lootbox
    /// @param amount The ETH amount of the lootbox (in wei)
    /// @param futureLevel The target level for future tickets
    /// @param futureTickets The pre-Bernoulli scaled (× QTY_SCALE) future ticket count
    /// @param flip The total FLIP tokens awarded (in wei)
    /// @param roundedUp True iff the Bernoulli round-up incremented the awarded
    ///        whole-ticket count by 1
    event LootBoxOpened(
        address indexed player,
        uint48 indexed lootboxIndex,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint256 flip,
        bool roundedUp
    );

    /// @notice Emitted when a lootbox awards a whale pass jackpot
    /// @param player The player who won the jackpot
    /// @param targetLevel Level AT BOX-OPEN TIME (`level + 1`), reported for
    ///        downstream indexers. Ticket queuing is deferred to the player-paid
    ///        `claimWhalePass` endpoint; tickets actually get queued at the level
    ///        when the beneficiary calls `claimWhalePass`, which may be greater
    ///        than this value (the player can delay the claim).
    /// @param entriesPerLevel Entries per level the materialized whale pass grants
    /// @param statsBoost Reserved for future use (always 0)
    /// @param frozenUntilLevel Reserved for future use (always 0)
    event LootBoxWhalePassJackpot(
        address indexed player,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 entriesPerLevel,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Aggregated DGNRS settlement for an opened entry's contiguous reward batch.
    /// @dev An ETH-spin boundary may split one entry into multiple batches because that spin can
    ///      recursively open another box and mutate the same pool.
    /// @param player Reward recipient.
    /// @param requested Total DGNRS this contiguous batch priced (pre-clamp).
    /// @param paid DGNRS actually credited from the pool.
    event LootBoxDgnrsBatch(address indexed player, uint256 requested, uint256 paid);

    /// @notice Emitted when a coin-presale box is resolved.
    /// @param player The box owner.
    /// @param index The box's RNG index.
    /// @param amount The box ETH resolved.
    /// @param flip FLIP credited (0 if not a FLIP roll).
    /// @param dgnrs DGNRS paid (roll award + any closing-box sweep).
    /// @param wwxrp WWXRP minted (0 unless the 10% dud roll).
    /// @param closing True iff this was the 50-ETH-crossing closing box.
    event PresaleBoxOpened(
        address indexed player,
        uint48 indexed index,
        uint256 amount,
        uint256 flip,
        uint256 dgnrs,
        uint256 wwxrp,
        bool closing
    );

    /// @notice Unified lootbox reward event for boon awards
    /// @param player The player receiving the reward
    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon, 11=LazyPassBoon, 12=QuestShield, 13=DegeneretteBoon)
    /// @param amount Primary reward amount (varies by type: BPS for boosts, token amount for boons; for type 13 the rolled boonType 32-40, which identifies the boon's currency and size)
    event LootBoxReward(
        address indexed player,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    /// @notice Emitted when a lootbox-drawn boon is discarded instead of delivered — the
    ///         statically-drawn type is not currently usable by this player (decimator tier
    ///         outside the burn window; deity tier while the player holds a pass or supply
    ///         is capped). Nothing is written; the draw itself stays fully deterministic.
    /// @param player The player whose draw was discarded
    /// @param boonType The statically-drawn boon type that was discarded
    event BoonDiscarded(address indexed player, uint8 boonType);

    /// @notice Emitted when a deity issues a boon to another player
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param day The day index when the boon was issued
    /// @param slot The slot index (0-2) of the boon
    /// @param boonType The type of boon issued (1-40; 10-12 and 20-21 are unused)
    event DeityBoonIssued(
        address indexed deity,
        address indexed recipient,
        uint24 indexed day,
        uint8 slot,
        uint8 boonType
    );

    // =========================================================================
    // External Contract References
    // =========================================================================

    /// @notice Reference to the WWXRP token contract
    IWWXRP internal constant wwxrp = IWWXRP(ContractAddresses.WWXRP);

    /// @notice Reference to the stETH token (redemption-direct stETH-remainder pull)
    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);


    // =========================================================================
    // Constants
    // =========================================================================



    // Boon bonus values

    // Lootbox roll constants
    /// @dev Base ticket roll budget in BPS (~155% EV after variance, 45% chance path).
    ///      Sized so the 45%-frequency ticket path distributes the same aggregate ETH
    ///      value as the prior 55%-frequency path (16_100 * 11 / 9).
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 19_678;
    /// @dev Budget weighting by target-level distance, applied to the ticket roll budget.
    ///      Far-future ticket rolls (20% of ticket rolls) capture 30% of the aggregate
    ///      ticket budget at 1.5x; near rolls take 0.875x. EV-neutral across the 20%/80%
    ///      far/near split (0.8*0.875 + 0.2*1.5 = 1.0), so total ticket value is unchanged.
    uint16 private constant LOOTBOX_TICKET_FAR_BUDGET_BPS = 15_000;
    uint16 private constant LOOTBOX_TICKET_NEAR_BUDGET_BPS = 8_750;
    /// @dev 1% chance for tier 1 ticket variance (5.25x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100;
    /// @dev 4% chance for tier 2 ticket variance (2.75x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400;
    /// @dev 20% chance for tier 3 ticket variance (1.30x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000;
    /// @dev 45% chance for tier 4 ticket variance (0.792x mean)
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500;
    /// @dev Per-tier multiplier ranges (BPS). Each [LOW, HIGH] band is symmetric about its
    ///      per-tier mean; across the tier chances the overall variance EV is ~0.941x. The
    ///      position within a tier reuses the same varianceRoll that selected the tier
    ///      (uniform within the tier's chance window), so no extra entropy is drawn. Tier 5
    ///      (default, ~30%) covers the remaining window.
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_LOW_BPS = 40_000; // 4.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_HIGH_BPS = 65_000; // 6.50x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_LOW_BPS = 20_000; // 2.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_HIGH_BPS = 35_000; // 3.50x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_LOW_BPS = 10_000; // 1.00x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_HIGH_BPS = 16_000; // 1.60x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS = 5_923; // 0.5923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS = 9_923; // 0.9923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS = 3_600; // 0.36x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS = 7_200; // 0.72x
    /// @dev 0.001% of DGNRS pool per ETH for small tier
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10;
    /// @dev 0.039% of DGNRS pool per ETH for medium tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390;
    /// @dev 0.08% of DGNRS pool per ETH for large tier
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800;
    /// @dev 0.8% of DGNRS pool per ETH for mega tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000;
    /// @dev One whole WWXRP token: the presale box's flat 10%-path award, and the floor
    ///      under every size-scaled box WWXRP amount (see `_boxWwxrpStake`).
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 1 ether;
    /// @dev WWXRP per ETH of roll value — 5 tokens per 0.01 ETH. Since WWXRP carries 18
    ///      decimals like wei, the conversion is a bare multiply on the wei amount.
    uint256 private constant LOOTBOX_WWXRP_PER_ETH = 500;
    /// @dev Domain-separation tags mixed (via hash2) into the box seed to derive each
    ///      Degenerette-spin sub-seed. Counter-tagged off the primary chunk, so the spins
    ///      consume no primary-chunk bits and never collide with the box's own draws.
    uint256 private constant BOX_WWXRP_SPIN_TAG = 0x57777872705370696e; // "WwxrpSpin"
    uint256 private constant BOX_FLIP_SPIN_TAG = 0x4275726e69655370696e; // "FlipSpin"
    uint256 private constant BOX_ETH_SPIN_TAG = 0x4574685370696e; // "EthSpin"
    /// @dev Domain-separation tag for the 100-FLIP award collapse. Keyed off the box/roll
    ///      seed rather than a spare bit-slice, so the bit budgets documented above stay
    ///      accurate and the roll is fixed at VRF fulfillment.
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    /// @dev Base BPS for low FLIP path (43.88%)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_BASE_BPS = 4_388;
    /// @dev Step increase in BPS for low FLIP path (3.60% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_STEP_BPS = 360;
    /// @dev Base BPS for high FLIP path (231.99%)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS = 23_199;
    /// @dev Step increase in BPS for high FLIP path (71.25% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS = 7_125;
    /// @dev Stake haircut (70.60%) applied to the FLIP-spins branch (roll 17-18) on top of
    ///      the reduced large-FLIP ladder, so the flat FLIP branch carries more of the FLIP
    ///      EV (flat:spins split 68:32 within FLIP). The flat FLIP roll (14-16) is not haircut.
    uint16 private constant LOOTBOX_FLIP_SPINS_STAKE_BPS = 7_060;

    // ---- Coin-presale-box FLIP band (lootbox band recentered on a 400% branch mean) ----
    // E[largeFlipBps] = 0.8*lowMean + 0.2*highMean = 40000 (400% of box ETH on the
    // FLIP branch -> 200% all-boxes average since FLIP rolls 50%).
    /// @dev Base BPS for low presale-box FLIP path (rolls 0-15, p=80%).
    uint32 private constant PRESALE_BOX_FLIP_LOW_BASE_BPS = 14_098;
    /// @dev Step BPS per roll for low presale-box FLIP path.
    uint32 private constant PRESALE_BOX_FLIP_LOW_STEP_BPS = 1_158;
    /// @dev Base BPS for high presale-box FLIP path (rolls 16-19, p=20%).
    uint32 private constant PRESALE_BOX_FLIP_HIGH_BASE_BPS = 74_534;
    /// @dev Step BPS per roll for high presale-box FLIP path.
    uint32 private constant PRESALE_BOX_FLIP_HIGH_STEP_BPS = 22_890;

    // ---- Coin-presale-box DGNRS curve (5 tiers x 10 ETH cumulative box volume) ----
    // Relative DGNRS-per-ETH rates [3.0, 2.5, 2.0, 1.5, 1.0] x base, base = poolStart/40.
    // Over 50 ETH the full deterministic draw sums to 100*base = 2.5*poolStart; with the
    // ~40% DGNRS branch rate the pool drains through the boxes (closing sweep clamps to dust).
    /// @dev DGNRS tier multipliers in tenths (3.0x .. 1.0x), by cumulative box volume.
    uint16 private constant PRESALE_BOX_DGNRS_TIER1_TENTHS = 30;
    uint16 private constant PRESALE_BOX_DGNRS_TIER2_TENTHS = 25;
    uint16 private constant PRESALE_BOX_DGNRS_TIER3_TENTHS = 20;
    uint16 private constant PRESALE_BOX_DGNRS_TIER4_TENTHS = 15;
    uint16 private constant PRESALE_BOX_DGNRS_TIER5_TENTHS = 10;
    /// @dev Cumulative box-ETH width of each DGNRS tier (10 ETH).
    uint256 private constant PRESALE_BOX_DGNRS_TIER_WIDTH = 10 ether;


    /// @dev Distress-mode ticket bonus in basis points (25%).
    uint16 private constant DISTRESS_TICKET_BONUS_BPS = 2500;


    // Boon categories — players may hold one boon per category simultaneously.
    // Within a category, upgrade semantics apply (higher tier replaces lower).

    // Deity boon constants



    // Deity boon weights (used for weighted random selection)


    // =========================================================================
    // Lootbox Opening Functions
    // =========================================================================

    /// @dev Apply EV multiplier with per-account per-level cap of 10 ETH.
    ///      Tracks how much benefit has been used and only applies EV adjustment
    ///      to the uncapped portion. Remainder gets 100% EV (neutral).
    /// @param player Player address
    /// @param lvl Current game level
    /// @param amount Lootbox ETH amount
    /// @param evMultiplierBps EV multiplier in basis points (9000-14500)
    /// @return scaledAmount Amount after EV adjustment
    function _applyEvMultiplierWithCap(
        address player,
        uint24 lvl,
        uint256 amount,
        uint256 evMultiplierBps
    ) private returns (uint256 scaledAmount) {
        // Bonus-only cap: penalty (< NEUTRAL) and neutral (== NEUTRAL) boxes apply the
        // multiplier on the full amount and draw nothing from the cap. Only a bonus box
        // (> NEUTRAL) falls through to the cap-draw branch below.
        if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {
            return (amount * evMultiplierBps) / 10_000;
        }

        // Check how much EV benefit capacity remains for this level
        uint256 usedBenefit = _lootboxEvUsedFor(player, lvl);
        uint256 remainingCap = usedBenefit >= LOOTBOX_EV_BENEFIT_CAP
            ? 0
            : LOOTBOX_EV_BENEFIT_CAP - usedBenefit;

        if (remainingCap == 0) {
            // Cap exhausted: apply 100% EV (neutral)
            return amount;
        }

        // Determine how much of this lootbox gets the EV adjustment
        uint256 adjustedPortion = amount > remainingCap ? remainingCap : amount;
        uint256 neutralPortion = amount - adjustedPortion;

        // Update tracking
        _setLootboxEvUsedFor(player, lvl, usedBenefit + adjustedPortion);

        // Calculate scaled amount:
        // - adjustedPortion gets the full EV multiplier
        // - neutralPortion gets 100% EV
        uint256 adjustedValue = (adjustedPortion * evMultiplierBps) / 10_000;
        scaledAmount = adjustedValue + neutralPortion;
    }

    // =========================================================================
    // Box-order buy leg (delegatecalled from the Mint module)
    // =========================================================================
    //
    // The buy path's box work lives here rather than in the Mint module for two reasons: it
    // belongs with the rest of the box logic, and the Mint module sits ~250 bytes under the
    // EIP-170 ceiling while this one has room. The Mint module keeps only what is genuinely
    // mint-side — the minted-units tally, the payment split, the combined pool write.

    /// @dev Portion of a box's EV reserved for the boon/pass draw (10%), capped. The haircut
    ///      is taken here because it comes off each box's reward amount; the DRAW itself lives
    ///      in the boon module.
    uint16 private constant LOOTBOX_BOON_BUDGET_BPS = 1000;
    uint256 private constant LOOTBOX_BOON_MAX_BUDGET = 1 ether;

    /// @notice Emitted when boxes are bought and queued for resolution. Same topic as the
    ///         Mint / Whale / Afking declarations — one box-buy event across every path.
    event LootBoxBuy(address indexed buyer, uint48 indexed index, uint256 amount);

    /// @notice Emitted when a lootbox-boost boon is consumed by a buy.
    event BoostUsed(
        address indexed player,
        uint24 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    /// @dev Minimum wei for a custom box. Presets clear it structurally: the cheapest ticket
    ///      price is 0.01 ETH and a small is one of those.
    uint256 private constant BOX_CUSTOM_MIN = 0.01 ether;
    /// @dev Floor for the biggest-box bounty.
    uint256 private constant BIGGEST_BOX_MIN_ETH = 5 ether;
    /// @dev Rake-free: all box ETH routes to the prize pools. Distress sends 100% next;
    ///      otherwise 90% future / 10% next.
    uint16 private constant BOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant BOX_SPLIT_NEXT_BPS = 1000;
    /// @dev Boon boost: capped uplift, expiring, consumed on use.
    uint256 private constant BOX_BOOST_MAX_VALUE = 10 ether;
    uint32 private constant BOX_BOOST_EXPIRY_DAYS = 2;

    // Packed order calldata: [small:8][med:8][large:8][customCount:8][customSize:48], 80 bits
    // of 256. `customSize` carries the SAME 1e12-granularity units the slot stores, so the size
    // charged and the size stored are the same number by construction rather than by a flooring
    // step that could drift. Callers scale wei down by LB_CUSTOM_SCALE; the UI owns that.
    uint256 private constant BO_MED_SHIFT = 8;
    uint256 private constant BO_LARGE_SHIFT = 16;
    uint256 private constant BO_CUSTOM_COUNT_SHIFT = 24;
    uint256 private constant BO_CUSTOM_SIZE_SHIFT = 32;
    uint256 private constant BO_COUNT_MASK = 0xFF;
    uint256 private constant BO_CUSTOM_SIZE_MASK = 0xFFFFFFFFFFFF;               // 48 bits

    /// @dev Merge a purchase's order into the player's existing order for this index and price
    ///      it. Works on the packed word in place — the order is one uint256, and a memory
    ///      struct would cost a full word per field to materialise something already packed.
    ///
    ///      `level` freezes on the period's first box, so a small costs what a small cost when
    ///      the player started — a period can straddle a level change, and pricing tiers off a
    ///      moving level would let the charge and the rolled size disagree. `customSize` freezes
    ///      the same way: a second custom at a different size REVERTS rather than repricing
    ///      boxes already held. The UI reads the frozen size and locks the input. Only the
    ///      player or their APPROVED operators can reach this at all (_resolvePlayer), and
    ///      operators are trusted by design — the size freeze is not defended against them.
    /// @return word Merged order, counts applied, bps lanes still to be folded.
    /// @return costWei Total wei this order costs.
    /// @return priorNominal Nominal wei already held here — the denominator the bps lanes
    ///         re-weight against.
    /// @custom:reverts E On an empty order, a sub-minimum custom, a custom-size change, or a
    ///         count over MAX_BOXES_PER_ORDER.
    function _mergeBoxOrder(
        uint256 existing,
        uint256 boxOrder,
        uint24 activeLevel
    ) private pure returns (uint256 word, uint256 costWei, uint256 priorNominal) {
        uint256 small = boxOrder & BO_COUNT_MASK;
        uint256 med = (boxOrder >> BO_MED_SHIFT) & BO_COUNT_MASK;
        uint256 large = (boxOrder >> BO_LARGE_SHIFT) & BO_COUNT_MASK;
        uint256 customCount = (boxOrder >> BO_CUSTOM_COUNT_SHIFT) & BO_COUNT_MASK;
        // Same 1e12 units the slot stores, so charge and storage agree by construction.
        uint256 customScaled = (boxOrder >> BO_CUSTOM_SIZE_SHIFT) & BO_CUSTOM_SIZE_MASK;

        uint256 added = small + med + large + customCount;
        if (added == 0) revert E();
        if (customCount != 0 && customScaled * LB_CUSTOM_SCALE < BOX_CUSTOM_MIN) revert E();

        word = existing;
        if (word == 0) {
            word =
                _lbSet(0, LB_LEVEL_SHIFT, LB_LEVEL_MASK, activeLevel) |
                (customScaled << LB_CUSTOM_SIZE_SHIFT);
        } else if (customCount != 0) {
            uint256 held = _lbGet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK);
            if (_lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK) == 0) {
                word = _lbSet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK, customScaled);
            } else if (held != customScaled) {
                revert E();
            }
        }

        uint256 sHeld = _lbGet(word, LB_SMALL_SHIFT, LB_COUNT_MASK);
        uint256 mHeld = _lbGet(word, LB_MED_SHIFT, LB_COUNT_MASK);
        uint256 lHeld = _lbGet(word, LB_LARGE_SHIFT, LB_COUNT_MASK);
        uint256 cHeld = _lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK);

        // Summed as uint256 before the cap check: 8-bit lanes would wrap a large request back
        // under the ceiling and let it through.
        if (sHeld + mHeld + lHeld + cHeld + added > MAX_BOXES_PER_ORDER) revert E();

        uint256 price = PriceLookupLib.priceForLevel(
            uint24(_lbGet(word, LB_LEVEL_SHIFT, LB_LEVEL_MASK))
        );
        uint256 customWei = _lbGet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK) *
            LB_CUSTOM_SCALE;

        unchecked {
            // Nominal already held, while the counts still describe only that. The cover lane
            // is part of it: the bps lanes blend against the WHOLE order, and
            // `applyBoxOrderScore` keys its score freeze off this being zero — omitting the
            // cover would erase a cover-first period's blended fractions and re-freeze its
            // score on the next manual buy.
            priorNominal =
                (sHeld + LB_MED_MULTIPLE * mHeld + LB_LARGE_MULTIPLE * lHeld) *
                price +
                cHeld *
                customWei +
                _lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) *
                LB_CUSTOM_SCALE;

            costWei =
                (small + LB_MED_MULTIPLE * med + LB_LARGE_MULTIPLE * large) *
                price +
                customCount *
                customWei;

            word = _lbSet(word, LB_SMALL_SHIFT, LB_COUNT_MASK, sHeld + small);
            word = _lbSet(word, LB_MED_SHIFT, LB_COUNT_MASK, mHeld + med);
            word = _lbSet(word, LB_LARGE_SHIFT, LB_COUNT_MASK, lHeld + large);
            word = _lbSet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK, cHeld + customCount);
        }
    }

    /// @dev Fold one purchase's extra into a running fraction of the order's nominal value.
    ///      All three lanes have this shape: each purchase contributes its own uplift over its
    ///      own slice, and the stored fraction must stay correct for the order as a whole.
    ///      Saturates at 100%; a zero-value order reads zero.
    ///
    ///      One ACCEPTED approximation: re-blending from an already-floored fraction makes
    ///      the stored bps depend on purchase batching by up to ~1 bps per purchase. (The
    ///      boost/distress correlation is NOT approximated — the distress lane blends over
    ///      boosted value precisely so the resolver's product is exact.)
    function _blendBps(
        uint16 oldBps,
        uint256 priorNominal,
        uint256 extra,
        uint256 addedNominal
    ) private pure returns (uint16) {
        uint256 t = priorNominal + addedNominal;
        if (t == 0) return 0;
        uint256 bps = (uint256(oldBps) * priorNominal + extra * 10_000) / t;
        return uint16(bps > 10_000 ? 10_000 : bps);
    }

    /// @dev Capped boon uplift on one purchase's spend.
    function _boostAmount(uint256 amount, uint16 bonusBps) private pure returns (uint256) {
        uint256 capped = amount > BOX_BOOST_MAX_VALUE ? BOX_BOOST_MAX_VALUE : amount;
        unchecked {
            return (capped * bonusBps) / 10_000;
        }
    }

    /// @dev Consume the player's lootbox-boost boon, if live, and return the uplift in wei.
    ///      Deity-granted boosts are valid only on their grant day; others expire after
    ///      BOX_BOOST_EXPIRY_DAYS. Either way the boon is cleared here — it is one-shot.
    function _consumeBoxBoost(address player, uint256 amount) private returns (uint256 extra) {
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 day = _simulatedDayIndex();
        uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
        if (deityDay != 0 && deityDay != day) {
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (stampDay != 0 && day > stampDay + BOX_BOOST_EXPIRY_DAYS) {
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return 0;
        }

        uint16 boostBps = _lootboxTierToBps(tier);
        extra = _boostAmount(amount, boostBps);
        bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
        emit BoostUsed(player, day, amount, amount + extra, boostBps);
    }

    /// @notice Price a box order without touching state — the buy path's overpay cap needs the
    ///         cost before it splits payment, and the cost depends on stored state because the
    ///         tier sizes come off the order's FROZEN level.
    /// @dev Delegatecall entrypoint from the Mint module; runs in the Game's storage context.
    /// @param buyer Player the order is for.
    /// @param boxOrder Packed order.
    /// @return costWei Total wei the order costs.
    function quoteBoxOrder(address buyer, uint256 boxOrder)
        external
        payable
        returns (uint256 costWei)
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (boxOrder == 0) return 0;
        uint48 idx = uint48((lootboxRngPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        (, costWei, ) = _mergeBoxOrder(
            lootboxOrder[idx][buyer],
            boxOrder,
            _activeTicketLevel()
        );
    }

    /// @notice Record a purchase's box order: merge the counts, freeze level and custom size,
    ///         fold the boost and distress lanes, enqueue the player once per index, bump the
    ///         RNG pending-eth, and arm the biggest-box bounty.
    /// @dev Delegatecall entrypoint from the Mint module; runs in the Game's storage context.
    ///      The EV lane is left zero here and folded by `applyBoxOrderScore` once the caller
    ///      has its post-action score — two warm writes to one slot rather than deferring the
    ///      pool split past the point the buy path can publish it.
    /// @param buyer Player the order is for.
    /// @param boxOrder Packed order.
    /// @return costWei Total wei the order costs.
    /// @return shares Prize-pool shares packed as (future << 128) | next. One return value
    ///         rather than two: the caller holds them across a long stretch of its body, and
    ///         two live locals there is exactly what tips it into a Yul stack-too-deep.
    /// @return flipCredit Any biggest-box bounty claim, to join the buyer's flip credit.
    /// @return priorNominal Nominal wei held here before this purchase — the caller threads it
    ///         back into `applyBoxOrderScore` so the EV lane weights the same way.
    function beginBoxOrder(address buyer, uint256 boxOrder)
        external
        payable
        returns (
            uint256 costWei,
            uint256 shares,
            uint256 flipCredit,
            uint256 priorNominal
        )
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (boxOrder == 0) return (0, 0, 0, 0);

        uint256 lrWord = lootboxRngPacked;
        uint48 idx = uint48((lrWord >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        uint256 existing = lootboxOrder[idx][buyer];

        uint256 word;
        (word, costWei, priorNominal) = _mergeBoxOrder(existing, boxOrder, _activeTicketLevel());

        if (existing == 0) {
            // First box for this (index, buyer): enqueue for the permissionless open cursor.
            // The consumer walk gates each index on lootboxRngWordByIndex != 0 (VRF
            // orphan-index protection), so enqueue is producer-only here — and it happens ONCE
            // per player per index however many boxes they buy, which is what keeps the sweep
            // queue bounded by buyers rather than by boxes.
            boxPlayers[idx].push(buyer);
        }

        // The boon uplift is capped per purchase and only one purchase in a period can carry a
        // boon at all, so it cannot be a frozen multiplier on the whole order. It rides as a
        // running fraction of RAW nominal; the resolver scales each box's derived size by it.
        uint16 oldBoost = uint16(_lbGet(word, LB_BOOST_SHIFT, LB_BPS_MASK));
        uint256 boostExtra = _consumeBoxBoost(buyer, costWei);
        word = _lbSet(
            word,
            LB_BOOST_SHIFT,
            LB_BPS_MASK,
            _blendBps(oldBoost, priorNominal, boostExtra, costWei)
        );

        // Distress can toggle between two purchases in one period, so it is a fraction too.
        // It blends over BOOSTED value — the denominator grossed by the PRIOR boost fraction,
        // this purchase's weight including its own uplift only when the purchase itself lands
        // in distress — because the resolver takes distressEth = boostedSize * distressBps:
        // a raw-basis fraction would let a boosted non-distress buy inflate (or deflate) the
        // distress ticket-bonus basis of the boxes around it.
        bool distress = _isDistressMode();
        {
            uint256 boostedPrior = priorNominal + (priorNominal * oldBoost) / 10_000;
            uint256 boostedAdded = costWei + boostExtra;
            word = _lbSet(
                word,
                LB_DISTRESS_SHIFT,
                LB_BPS_MASK,
                _blendBps(
                    uint16(_lbGet(word, LB_DISTRESS_SHIFT, LB_BPS_MASK)),
                    boostedPrior,
                    distress ? boostedAdded : 0,
                    boostedAdded
                )
            );
        }

        lootboxOrder[idx][buyer] = word;

        // Biggest-box bounty: a CUSTOM only, and its per-box size, never the order's total.
        // Presets are excluded outright — the bounty marks deliberately going big, and a large
        // at a milestone price would clear the floor on its own. With presets out and the
        // candidate a single box, no quantity of small buys can reach it.
        if (((boxOrder >> BO_CUSTOM_COUNT_SHIFT) & BO_COUNT_MASK) != 0) {
            uint256 candidate = ((boxOrder >> BO_CUSTOM_SIZE_SHIFT) & BO_CUSTOM_SIZE_MASK) *
                LB_CUSTOM_SCALE;
            if (candidate >= BIGGEST_BOX_MIN_ETH) {
                flipCredit = coinflip.armRecord(RECORD_KIND_LUCKBOX, buyer, candidate);
            }
        }

        uint256 newPendingEth = ((lrWord >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK) +
            _packEthToMilliEth(costWei);
        lootboxRngPacked =
            (lrWord & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)) |
            ((newPendingEth & LR_PENDING_ETH_MASK) << LR_PENDING_ETH_SHIFT);

        unchecked {
            shares =
                (((costWei * (distress ? 0 : BOX_SPLIT_FUTURE_BPS)) / 10_000) << 128) |
                ((costWei * (distress ? 10_000 : BOX_SPLIT_NEXT_BPS)) / 10_000);
        }

        emit LootBoxBuy(buyer, idx, costWei);
    }

    /// @notice Record a system-granted cover box — the whale-pass bundle and the afking
    ///         auto-buy. Accumulates into the order's cover lane and resolves as ONE extra box.
    /// @dev Delegatecall entrypoint shared by the Whale and Afking modules; runs in the Game's
    ///      storage context. Deliberately outside `MAX_BOXES_PER_ORDER`: a cover is granted, not
    ///      chosen, so it must never be able to lock a player out of buying — and it never
    ///      touches `customSize`, so it cannot strand a player behind a size they did not pick.
    ///      The player's own EV score/level freeze on the first box either way, so a cover
    ///      arriving first is what seeds them.
    /// @param player Player receiving the cover.
    /// @param amountWei Cover spend in wei.
    /// @param score Caller's activity-score snapshot, used only if this is the first box.
    /// @param capKey Level key for the shared per-(player, level) EV-cap accumulator.
    /// @param boost Whether to consume a live lootbox-boost boon (whale bundle yes, afking no).
    function recordCoverBox(
        address player,
        uint256 amountWei,
        uint16 score,
        uint24 capKey,
        bool boost
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        // Below storage granularity the cover lane would round to a ZERO count while the
        // level/score write left the word non-zero — a queue slot the sweep skips forever.
        // Sub-1e12-wei covers are unreachable from both cover paths; the guard makes the
        // invariant (non-zero word => openable) structural rather than incidental.
        if (amountWei < LB_CUSTOM_SCALE) return;

        uint256 lrWord = lootboxRngPacked;
        uint48 idx = uint48((lrWord >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        uint256 word = lootboxOrder[idx][player];

        if (word == 0) {
            boxPlayers[idx].push(player);
            word =
                _lbSet(0, LB_LEVEL_SHIFT, LB_LEVEL_MASK, _activeTicketLevel()) |
                _lbSet(
                    0,
                    LB_SCORE_SHIFT,
                    LB_SCORE_MASK,
                    score > ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS
                        ? ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS
                        : score
                );
        }

        uint256 priorNominal = _orderNominal(word);
        uint16 oldBoost = uint16(_lbGet(word, LB_BOOST_SHIFT, LB_BPS_MASK));
        uint256 extra = boost ? _consumeBoxBoost(player, amountWei) : 0;
        word = _lbSet(
            word,
            LB_BOOST_SHIFT,
            LB_BPS_MASK,
            _blendBps(oldBoost, priorNominal, extra, amountWei)
        );

        // Distress rides the same flag as the boost: the whale bundle carried both lanes
        // before the relocation, the afking cover carried neither (it always preserved zero
        // distress). Blended over BOOSTED value, mirroring beginBoxOrder — the resolver's
        // distress basis is boostedSize * distressBps.
        {
            uint256 boostedPrior = priorNominal + (priorNominal * oldBoost) / 10_000;
            uint256 boostedAdded = amountWei + extra;
            word = _lbSet(
                word,
                LB_DISTRESS_SHIFT,
                LB_BPS_MASK,
                _blendBps(
                    uint16(_lbGet(word, LB_DISTRESS_SHIFT, LB_BPS_MASK)),
                    boostedPrior,
                    (boost && _isDistressMode()) ? boostedAdded : 0,
                    boostedAdded
                )
            );
        }

        // EV-cap draw against the shared per-(player, level) accumulator, same as a bought box.
        uint256 evExtra;
        if (
            _lootboxEvMultiplierFromScore(_lbGet(word, LB_SCORE_SHIFT, LB_SCORE_MASK)) >
            LOOTBOX_EV_NEUTRAL_BPS
        ) {
            uint256 used = _lootboxEvUsedFor(player, capKey);
            uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                ? 0
                : LOOTBOX_EV_BENEFIT_CAP - used;
            evExtra = amountWei < remaining ? amountWei : remaining;
            if (evExtra != 0) _setLootboxEvUsedFor(player, capKey, used + evExtra);
        }
        word = _lbSet(
            word,
            LB_ADJ_SHIFT,
            LB_BPS_MASK,
            _blendBps(
                uint16(_lbGet(word, LB_ADJ_SHIFT, LB_BPS_MASK)),
                priorNominal,
                evExtra,
                amountWei
            )
        );

        // Covers accumulate into one box rather than one each: they arrive on a schedule the
        // player does not control, so counting them would let the sweep's per-entry cost drift
        // with subscription cadence rather than with what anyone chose to buy.
        word = _lbSet(
            word,
            LB_COVER_SHIFT,
            LB_COVER_MASK,
            _lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) + amountWei / LB_CUSTOM_SCALE
        );
        lootboxOrder[idx][player] = word;

        uint256 newPendingEth = ((lrWord >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK) +
            _packEthToMilliEth(amountWei);
        lootboxRngPacked =
            (lrWord & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)) |
            ((newPendingEth & LR_PENDING_ETH_MASK) << LR_PENDING_ETH_SHIFT);

        emit LootBoxBuy(player, idx, amountWei);
    }

    /// @dev Nominal wei an order currently represents — the four bought tiers at the frozen
    ///      level's prices, plus the cover lane. The denominator every bps lane re-weights on.
    function _orderNominal(uint256 word) private pure returns (uint256) {
        uint256 price = PriceLookupLib.priceForLevel(
            uint24(_lbGet(word, LB_LEVEL_SHIFT, LB_LEVEL_MASK))
        );
        unchecked {
            return
                (_lbGet(word, LB_SMALL_SHIFT, LB_COUNT_MASK) +
                    LB_MED_MULTIPLE *
                    _lbGet(word, LB_MED_SHIFT, LB_COUNT_MASK) +
                    LB_LARGE_MULTIPLE *
                    _lbGet(word, LB_LARGE_SHIFT, LB_COUNT_MASK)) *
                price +
                _lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK) *
                _lbGet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK) *
                LB_CUSTOM_SCALE +
                _lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) *
                LB_CUSTOM_SCALE;
        }
    }

    /// @notice Freeze the order's activity score (first box of the period only) and fold this
    ///         purchase's EV-cap draw into the order's adj lane.
    /// @dev Delegatecall entrypoint from the Mint module, called after its post-action score is
    ///      known. The score is the resolver's frozen EV knob — the anti-gaming property, since
    ///      the open level is not player-timable but the buy is.
    /// @param buyer Player the order is for.
    /// @param cachedScore Caller's post-action activity score in whole points.
    /// @param capLevel Level key for the shared per-(player, level) EV-cap accumulator.
    /// @param costWei This purchase's box spend, the lane's weight for this slice.
    /// @param priorNominal Nominal wei held before this purchase.
    function applyBoxOrderScore(
        address buyer,
        uint256 cachedScore,
        uint24 capLevel,
        uint256 costWei,
        uint256 priorNominal
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint48 idx = uint48((lootboxRngPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        uint256 word = lootboxOrder[idx][buyer];
        if (word == 0) return;

        // Score freezes on the period's FIRST box. Clamped to the curve's effective cap so it
        // fits the 15-bit lane; the multiplier is flat above that point, so the clamp changes
        // no outcome.
        if (priorNominal == 0) {
            word = _lbSet(
                word,
                LB_SCORE_SHIFT,
                LB_SCORE_MASK,
                cachedScore > ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS
                    ? ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS
                    : cachedScore
            );
        }

        // A bonus order (mult > NEUTRAL) draws min(spend, CAP - used) from the shared
        // per-(player, level) accumulator; neutral and sub-neutral orders draw nothing.
        uint256 evExtra;
        if (
            _lootboxEvMultiplierFromScore(_lbGet(word, LB_SCORE_SHIFT, LB_SCORE_MASK)) >
            LOOTBOX_EV_NEUTRAL_BPS
        ) {
            uint256 used = _lootboxEvUsedFor(buyer, capLevel);
            uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                ? 0
                : LOOTBOX_EV_BENEFIT_CAP - used;
            evExtra = costWei < remaining ? costWei : remaining;
            if (evExtra != 0) _setLootboxEvUsedFor(buyer, capLevel, used + evExtra);
        }
        word = _lbSet(
            word,
            LB_ADJ_SHIFT,
            LB_BPS_MASK,
            _blendBps(
                uint16(_lbGet(word, LB_ADJ_SHIFT, LB_BPS_MASK)),
                priorNominal,
                evExtra,
                costWei
            )
        );

        lootboxOrder[idx][buyer] = word;
    }

    /// @dev Open the ETH-lootbox leg of an index for a player, if one is queued. Applies the
    ///      frozen activity-score EV multiplier (the 10 ETH cap was drawn at deposit). Returns
    ///      false (no-op) when no lootbox is queued, so the unified open path can still resolve
    ///      the presale leg; the manual `openBox` shell turns an all-empty index into a revert.
    /// @param player Player address to open the lootbox for.
    /// @param index The RNG index of the lootbox.
    /// @return opened True if a lootbox leg was resolved.
    /// @custom:reverts RngNotReady When the lootbox is queued but its RNG word is not yet set.
    function _openLootBoxLeg(address player, uint48 index, uint24 currentLevel) internal returns (bool opened) {
        uint256 word = lootboxOrder[index][player];
        // Early-out before the rngWord SLOAD when no boxes are queued (the presale leg loads
        // the word itself).
        if (_boxOrderCount(word) == 0) return false;
        return _openLootBoxLegWith(player, index, word, lootboxRngWordByIndex[index], currentLevel);
    }

    /// @dev Per-entry reward accumulator. Every lane an entry's boxes can pay into is summed
    ///      here and normally settled ONCE at the end, rather than credited per roll: the
    ///      fungible lanes collapse to a single call each, and tickets collapse to one write per
    ///      distinct target level. DGNRS is the sole exception: it is checkpointed before an
    ///      ETH spin because that spin can recursively open another box against the same pool.
    ///      That asymmetry is the point of the count model — a hundred boxes for one player share
    ///      every per-player slot, where a hundred players would each pay for their own cold set.
    ///
    ///      Tickets index by level OFFSET from the open level. `_rollTargetLevel` only ever
    ///      produces `base + 0..4` (80%) or `base + 5..50` (20%), so a fixed 51-wide lane is
    ///      exhaustive. A touched-lane bitmap makes settlement proportional to distinct winning
    ///      levels rather than scanning all 51 lanes.
    struct BoxAcc {
        uint256 flip;
        uint256 dgnrs;
        uint256 wwxrp;
        uint256 dgnrsPool;    // Lootbox-pool snapshot, read once per recursion-delimited batch
        bool dgnrsPoolLoaded;
        // One bit per non-zero ticket lane. The counters stay unpacked for cheap per-roll
        // updates; bit-scanning makes the final flush proportional to distinct winning levels
        // while preserving the old ascending-level event/write order.
        uint64 ticketTouched;
        uint32[51] tickets;
    }

    /// @dev Resolution context for one entry, carried as a single memory struct rather than a
    ///      spread of locals: the tier loop threads all of it, and a wide parameter list here is
    ///      exactly what tips this module into a Yul stack-too-deep.
    struct BoxRoll {
        address player;
        uint48 index;
        uint256 rngWord;
        uint24 currentLevel;
        uint256 evBps;
        uint256 boostBps;
        uint256 distressBps;
        uint256 adjBps;
        BoxAcc acc;         // the entry's shared reward accumulator
        uint16 score;
        uint256 nonce;      // boxes rolled so far — also each box's seed nonce
        uint256 boonSeed;   // player-mixed; each box's draw is (boonSeed, its nonce)
    }

    /// @dev Box-leg body operating on pre-loaded values: `word` is the player's packed order at
    ///      `index`, `rngWord` the index's committed VRF word. The sweep loads both once per
    ///      entry and threads them down; the manual shell loads them itself. Values cannot go
    ///      stale between load and use: no callee on this path hands control to player code, and
    ///      an order write at a worded index is unreachable from the buy path.
    ///
    ///      Every box in the order resolves as its OWN roll at its OWN size — a small rolls
    ///      small and a medium rolls medium. There is no split threshold: one box, one roll.
    /// @custom:reverts RngNotReady When boxes are queued but `rngWord` is zero.
    function _openLootBoxLegWith(
        address player,
        uint48 index,
        uint256 word,
        uint256 rngWord,
        uint24 currentLevel
    ) internal returns (bool opened) {
        if (_boxOrderCount(word) == 0) return false;
        if (rngWord == 0) revert RngNotReady();

        // Cleared before any resolution: the roll path makes external calls, and a zeroed slot
        // means a re-entrant open finds nothing left to open.
        lootboxOrder[index][player] = 0;

        // `c`'s declaration allocates its nested BoxAcc; use it directly rather than
        // allocating a second one and repointing.
        BoxRoll memory c;
        c.player = player;
        c.index = index;
        c.rngWord = rngWord;
        // The boon seed MUST mix the player: the raw index word is shared by every entry at
        // this index, and an unmixed seed would hand every player the same per-box roll
        // values — correlated boon outcomes across the whole index.
        c.boonSeed = EntropyLib.hash2(rngWord, uint256(uint160(player)));
        c.currentLevel = currentLevel;
        c.score = uint16(_lbGet(word, LB_SCORE_SHIFT, LB_SCORE_MASK));
        // The EV multiplier stays FROZEN at buy (`score`) — that is the anti-gaming knob. The
        // box rolls from the LIVE level at open, which the holder cannot steer: the
        // permissionless bounty opens every ready box as soon as it can.
        c.evBps = _lootboxEvMultiplierFromScore(c.score);
        c.boostBps = _lbGet(word, LB_BOOST_SHIFT, LB_BPS_MASK);
        c.distressBps = _lbGet(word, LB_DISTRESS_SHIFT, LB_BPS_MASK);
        c.adjBps = _lbGet(word, LB_ADJ_SHIFT, LB_BPS_MASK);

        uint256 price = PriceLookupLib.priceForLevel(
            uint24(_lbGet(word, LB_LEVEL_SHIFT, LB_LEVEL_MASK))
        );

        // Keep the overwhelmingly common one-tier order on the lean existing path. Only a
        // genuinely mixed order allocates the five-lane batch and pays its packing work.
        if (_boxOrderIsMixed(word)) {
            _rollBatchedTiers(c, word, price);
        } else {
            _rollTierImmediate(c, _lbGet(word, LB_SMALL_SHIFT, LB_COUNT_MASK), price);
            _rollTierImmediate(c, _lbGet(word, LB_MED_SHIFT, LB_COUNT_MASK), price * LB_MED_MULTIPLE);
            _rollTierImmediate(c, _lbGet(word, LB_LARGE_SHIFT, LB_COUNT_MASK), price * LB_LARGE_MULTIPLE);
            _rollTierImmediate(
                c,
                _lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK),
                _lbGet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK) * LB_CUSTOM_SCALE
            );
            // The cover lane resolves as ONE box of its accumulated value.
            _rollTierImmediate(c, 1, _lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) * LB_CUSTOM_SCALE);
        }

        // Final settlement for the whole entry: one call per remaining fungible lane, one ticket
        // write per distinct level. DGNRS may already be checkpointed at an ETH-spin boundary.
        // Boon draws have completed before this remaining fungible/ticket flush.
        _flushBoxAcc(player, c.acc, currentLevel);

        return true;
    }

    /// @dev One box's boon draw, for the resolvers that settle a single box outside the
    ///      entry sweep (afking covers, decimator/degenerette auto-resolve, ETH-spin recirc,
    ///      sDGNRS redemption chunks). Identical draw to the entry path's per-tier call;
    ///      `seed` is the box's own player-specific resolution seed, drawn at nonce 0.
    function _rollSingleBoxBoons(
        address player,
        uint256 amount,
        uint24 currentLevel,
        uint256 seed
    ) private {
        (bool ok, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameBoonModule.rollBoxBoons.selector,
                player,
                _lootboxBoonBudget(amount),
                1,
                amount,
                currentLevel,
                seed,
                0
            )
        );
        if (!ok) revert EmptyRevert();
    }

    /// @dev Settle an entry's remaining accumulated rewards: one call per fungible lane, one
    ///      ticket write per distinct target level. DGNRS may already have been checkpointed at
    ///      an ETH-spin recursion boundary; every other lane settles only here.
    function _flushBoxAcc(address player, BoxAcc memory acc, uint24 currentLevel) private {
        uint256 touched = acc.ticketTouched;
        while (touched != 0) {
            // Find the least-significant set bit in six bounded steps (all lanes are 0..50),
            // then clear it. This walks only populated lanes, in the same ascending order as
            // the former exhaustive 0..50 scan.
            uint256 scan = touched;
            uint256 offset;
            if (uint32(scan) == 0) {
                offset = 32;
                scan >>= 32;
            }
            if (uint16(scan) == 0) {
                offset += 16;
                scan >>= 16;
            }
            if (uint8(scan) == 0) {
                offset += 8;
                scan >>= 8;
            }
            if ((scan & 0xF) == 0) {
                offset += 4;
                scan >>= 4;
            }
            if ((scan & 0x3) == 0) {
                offset += 2;
                scan >>= 2;
            }
            if ((scan & 1) == 0) offset += 1;

            uint32 whole = acc.tickets[offset];
            _queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false);
            unchecked {
                touched &= touched - 1;
            }
        }
        if (acc.dgnrs != 0) {
            uint256 paid = _creditDgnrsReward(player, acc.dgnrs);
            // One aggregated emit for the entry's remaining batch, under its OWN event: reusing the per-box
            // LootBoxDgnrsReward schema would silently put DGNRS units in a field indexers
            // read as box ETH.
            if (paid != 0) emit LootBoxDgnrsBatch(player, acc.dgnrs, paid);
        }
        if (acc.flip != 0) coinflip.creditFlip(player, acc.flip);
        if (acc.wwxrp != 0) wwxrp.mintPrize(player, acc.wwxrp);
    }

    /// @dev Add whole tickets to one target-level offset and remember that offset on first touch.
    ///      The same saturation rule as the former inline update keeps the eventual entry shift
    ///      (`wholeTicketsToEntries`) in range and prevents an extreme order from wedging a sweep.
    function _addBoxTickets(BoxAcc memory acc, uint256 offset, uint32 whole) private pure {
        if (whole == 0) return;

        uint32 prior = acc.tickets[offset];
        if (prior == 0) {
            acc.ticketTouched |= uint64(uint256(1) << offset);
        }

        uint256 lane = uint256(prior) + whole;
        uint256 laneCap = uint256(type(uint32).max) >> 2;
        acc.tickets[offset] = lane > laneCap ? uint32(laneCap) : uint32(lane);
    }

    /// @dev True when two or more of small/medium/large/custom/cover are populated. The four
    ///      bought counts are contiguous bytes, so collapse each byte to one presence bit and
    ///      use the standard `x & (x - 1)` multiple-bit test; the cover becomes a fifth bit.
    function _boxOrderIsMixed(uint256 word) private pure returns (bool) {
        uint256 laneBits = (word >> LB_SMALL_SHIFT) & 0xFFFFFFFF;
        laneBits |= laneBits >> 4;
        laneBits |= laneBits >> 2;
        laneBits = (laneBits | (laneBits >> 1)) & 0x01010101;
        if (_lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) != 0) laneBits |= uint256(1) << 32;
        return laneBits != 0 && (laneBits & (laneBits - 1)) != 0;
    }

    /// @dev Resolve one populated tier and immediately dispatch its boon draws. Kept separate
    ///      from `_rollTier` so one-tier orders never allocate or carry the mixed-order batch.
    function _rollTierImmediate(BoxRoll memory c, uint256 count, uint256 size) private {
        if (count == 0 || size == 0) return;
        uint256 nonceBase = c.nonce;
        uint256 scaled = _rollTier(c, count, size);

        (bool okBoon, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameBoonModule.rollBoxBoons.selector,
                c.player,
                _lootboxBoonBudget(scaled),
                count,
                scaled,
                c.currentLevel,
                c.boonSeed,
                nonceBase
            )
        );
        if (!okBoon) revert EmptyRevert();
    }

    /// @dev Roll `count` boxes of `size` wei each. Every box takes its own seed — the nonce is
    ///      its position in the entry — so two same-size boxes from one player at one index can
    ///      never resolve identically. Returns zero for an empty lane, otherwise its scaled size.
    function _rollTier(BoxRoll memory c, uint256 count, uint256 size) private returns (uint256 scaled) {
        if (count == 0 || size == 0) return 0;

        unchecked {
            // The boon uplift was banked as a fraction of the order's nominal value; each box
            // carries its proportional share.
            uint256 boosted = size + (size * c.boostBps) / 10_000;
            // Frozen EV application: a penalty or neutral order scales the whole box; a bonus
            // order scales only the cap-eligible fraction drawn at buy and pays the rest —
            // including the boon uplift — at 100%. The adj fraction applies to the RAW size,
            // matching the buy-side draw (which capped raw spend, not boosted): applying it to
            // the boosted basis would quietly extend the EV bonus onto the boost itself. No
            // cap read here — the draw happened at purchase.
            uint256 adjWei = (size * c.adjBps) / 10_000;
            scaled = c.evBps <= LOOTBOX_EV_NEUTRAL_BPS
                ? (boosted * c.evBps) / 10_000
                : (adjWei * c.evBps) / 10_000 + (boosted - adjWei);
            uint256 distressEth = (boosted * c.distressBps) / 10_000;

            for (uint256 i; i < count; ++i) {
                // Seed = the per-index VRF anchor (fixed at the index's advance, unknowable at
                // buy) + player + size + this box's position. No day term: the box binds to the
                // index word, and a day keyed to the OPEN day would be re-rollable by timing.
                uint256 seed = EntropyLib.hash4(
                    c.rngWord,
                    uint256(uint160(c.player)),
                    size,
                    ++c.nonce
                );
                _resolveLootboxCommon(
                    c.player,
                    c.index,
                    scaled,
                    _rollTargetLevel(c.currentLevel, seed),
                    c.currentLevel,
                    seed,
                    true,
                    distressEth,
                    boosted,
                    c.score,
                    true,
                    c.acc
                );
            }
        }
    }

    /// @dev Resolve all five lanes of a mixed order, then dispatch their boon draws together.
    ///      Tier amounts stay separate so chance saturation is byte-identical; only call frames
    ///      and repeated normalization collapse. This helper is never entered by one-tier orders,
    ///      so its fixed array is not allocated on their hot path.
    function _rollBatchedTiers(BoxRoll memory c, uint256 word, uint256 price) private {
        uint256[5] memory amounts;
        uint40 countsPacked;
        uint256 count = _lbGet(word, LB_SMALL_SHIFT, LB_COUNT_MASK);
        amounts[0] = _rollTier(c, count, price);
        if (amounts[0] != 0) countsPacked = uint40(count);

        count = _lbGet(word, LB_MED_SHIFT, LB_COUNT_MASK);
        amounts[1] = _rollTier(c, count, price * LB_MED_MULTIPLE);
        if (amounts[1] != 0) countsPacked |= uint40(count << 8);

        count = _lbGet(word, LB_LARGE_SHIFT, LB_COUNT_MASK);
        amounts[2] = _rollTier(c, count, price * LB_LARGE_MULTIPLE);
        if (amounts[2] != 0) countsPacked |= uint40(count << 16);

        count = _lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK);
        amounts[3] = _rollTier(
            c,
            count,
            _lbGet(word, LB_CUSTOM_SIZE_SHIFT, LB_CUSTOM_SIZE_MASK) * LB_CUSTOM_SCALE
        );
        if (amounts[3] != 0) countsPacked |= uint40(count << 24);

        uint256 coverSize = _lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) * LB_CUSTOM_SCALE;
        amounts[4] = _rollTier(c, 1, coverSize);
        if (amounts[4] != 0) countsPacked |= uint40(1) << 32;

        (bool okBoon, ) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameBoonModule.rollBoxBoonTiers.selector,
                c.player,
                amounts,
                countsPacked,
                c.currentLevel,
                c.boonSeed
            )
        );
        if (!okBoon) revert EmptyRevert();
    }

    /// @notice Open every box queued at an RNG index for a player — the ETH-lootbox leg, the
    ///         coin-presale-box leg, or both (one committed word, two domain-separated draws,
    ///         each leg robust to being empty). The unified manual open entrypoint.
    /// @param player Player that owns the box(es) (resolved by the entrypoint).
    /// @param index The shared RNG index the box(es) queued at.
    /// @custom:reverts NothingToClaim When neither leg has a box queued at this index for the player.
    /// @custom:reverts RngNotReady When a queued leg's committed RNG word is not yet set.
    /// @custom:reverts E Once the liveness timeout has fired (see the gate below).
    function openBox(address player, uint48 index) external {
        // A roll queues ticket entries at the write buffer, so the open is a
        // position-creating action and closes with the game: past the liveness
        // trigger the terminal word is public, which would let a caller open only
        // the boxes whose entries match the already-known winning traits and have
        // the terminal swap commit them. The sweep sibling gates identically. The
        // box's ETH is not stranded — it was banked into the pools at purchase and
        // is distributed by the terminal drain.
        if (_livenessTriggered()) revert E();
        // A wide order queues tickets at up to 51 levels and the far band reverts under the
        // daily RNG lock, so a 100-box open during the lock fails with near-certainty anyway
        // (P ~= 1 - 0.92^N). Gate here so it fails FAST with the real reason; the sweep is
        // already lock-gated, and the lock clears within the day.
        if (rngLockedFlag) revert RngLocked();
        // Permissionless: box rewards always credit the owner, so any caller may open any
        // player's ready boxes (zero address = caller).
        if (player == address(0)) player = msg.sender;
        // Probe the presale leg until the sweep has drained presale (free slot-0 read of the flag).
        if (!_openBoxBoth(player, index, !presaleDrained, level + 1)) revert NothingToClaim();
    }

    /// @dev Both-leg open body for the manual `openBox` entrypoint (the sweep threads
    ///      pre-loaded values into `_openLootBoxLegWith` directly). Resolves the lootbox leg
    ///      (if queued) then, when `checkPresale`, the presale-box leg (if queued); each robust
    ///      to being empty. The `player` is the resolved owner — `openBox` maps the zero address
    ///      to msg.sender, and the sweep passes a concrete owner. Runs in the game's storage context.
    /// @param player Box owner (already resolved).
    /// @param index The shared RNG index.
    /// @param checkPresale Whether to probe the presale-box leg — the caller passes `!presaleDrained`,
    ///        skipping the cold presaleBoxEth SLOAD once presale is fully drained.
    /// @return any True if at least one leg was resolved.
    function _openBoxBoth(address player, uint48 index, bool checkPresale, uint24 currentLevel) internal returns (bool any) {
        // Lootbox leg: resolves (and reports) only if one is queued — its own seed derivation.
        if (_openLootBoxLeg(player, index, currentLevel)) any = true;
        // Presale-box leg: probed only while presale boxes are outstanding. Boon-less, own
        // resolution (NOT a _resolveLootboxCommon caller): a credit-funded box can never mint a
        // whale pass. 50/40/10 FLIP/DGNRS/WWXRP.
        if (checkPresale) {
            uint256 stored = presaleBoxEth[index][player];
            if (stored != 0) {
                uint256 rngWord = lootboxRngWordByIndex[index];
                if (rngWord == 0) revert RngNotReady();
                presaleBoxEth[index][player] = 0; // dequeue
                _resolvePresaleBox(player, index, stored, rngWord, currentLevel);
                any = true;
            }
        }
    }

    /// @notice Human-box leg of openBoxes(): a permissionless, gas-bounded MULTI-INDEX sweep.
    /// @dev Delegatecall entrypoint from DegenerusGame.openBoxes — runs in the Game's storage
    ///      context, mirroring the afking leg's drainAfkingBoxes delegatecall. Walks the open
    ///      frontier from boxCursorIndex up to LR_INDEX-1 (the finalized indices — words land at
    ///      LR_INDEX-1, one behind the pre-incremented active index), opening every ready box at
    ///      each index, then advancing to the next. `budget` bounds the ENTRIES scanned this call:
    ///      opens AND skips each cost one step, so a long skip-prefix (already-opened or
    ///      presale-only entries) can never gas-wall the tx — progress is monotonic and persists
    ///      across calls via (boxCursorIndex, boxCursor). Each entry resolves BOTH legs
    ///      (lootbox + presale, robust to either empty) from values loaded once per entry —
    ///      the skip-check reads are threaded into the opens. Orphan-index
    ///      coupling: the sweep STOPS at any index whose VRF word has not landed
    ///      (orphaned mid-day by a coordinator rotation) instead of advancing past it, so its boxes
    ///      are never marooned — it resumes once the re-issued word lands. Every leg is O(1)
    ///      (whale-pass materialization is deferred to claimWhalePass).
    /// @param budget Walk budget in the shared open-weight unit (~4.7k gas each) — the same
    ///        unit the afking leg spends. An entry costs OPEN_HUMAN_ENTRY_WEIGHT plus
    ///        OPEN_HUMAN_BOX_WEIGHT for each box; a skip or index-header costs
    ///        one. Neither entries nor boxes are the unit, because neither predicts the gas.
    /// @return opened Total boxes opened this call.
    /// @return unitsSpent Walk units this call consumed — the crank's work-based bounty basis.
    ///         Crediting the knee per BOX would let one five-small order saturate it at a
    ///         fraction of the work five distinct entries used to represent.
    function openHumanBoxes(uint256 budget)
        external
        returns (uint256 opened, uint256 unitsSpent)
    {
        // Entry-gate: the open path's revert sources — rngLock and the terminal-jackpot
        // liveness control — are excluded pre-loop so the loop body is guaranteed-non-reverting.
        if (rngLockedFlag || _livenessTriggered()) return (0, 0);

        uint48 active = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (active <= 1) return (0, 0); // no finalized index yet (LR_INDEX is genesis-1, monotonic)
        uint48 finalized = active - 1; // highest openable index — where the word lands

        uint48 idx = boxCursorIndex;
        if (idx == 0) idx = 1; // index 0 is unused; the genesis box index is 1
        uint256 cur = boxCursor;
        // Free slot-0 read (the entry-gate above already SLOAD'd slot 0 for rngLockedFlag): probe
        // the presale leg until presale is fully drained. The flag is flipped (below) once this
        // sweep advances past presaleCloseIndex, after which every entry skips the cold
        // presaleBoxEth SLOAD. Cached once per call.
        bool checkPresale = !presaleDrained;
        // `level`'s sole writer (advanceGame) is unreachable from this sweep, so the open level
        // is invariant across the whole call — read `level + 1` once and thread it into every leg.
        uint24 currentLevel = level + 1;

        uint256 steps; // entries + index-headers scanned this call — bounds the tx gas
        while (idx <= finalized && steps < budget) {
            unchecked {
                ++steps; // each index visit costs a step (bounds an empty-index crawl)
            }
            // Orphan-index coupling: never advance past an un-worded index, or its boxes maroon.
            // The word is loaded once per index and threaded into every open below.
            uint256 indexWord = lootboxRngWordByIndex[idx];
            if (indexWord == 0) break;

            address[] storage queue = boxPlayers[idx];
            uint256 qlen = queue.length;
            while (cur < qlen && steps < budget) {
                address player = queue[cur];
                // Open if EITHER leg is still owed: the box order or the presale leg
                // (presaleBoxEth, probed only while boxes are outstanding). Both are zeroed on
                // open, so a zero/zero entry is already-drained (or never carried a box of this
                // type) and is skipped. Each leg's word is loaded ONCE here and threaded into
                // its open — the skip-check values double as the open's inputs.
                uint256 word = lootboxOrder[idx][player];
                uint256 stored = checkPresale ? presaleBoxEth[idx][player] : 0;
                uint256 boxes = _boxOrderCount(word);
                if (boxes == 0 && stored == 0) {
                    unchecked {
                        ++cur;
                        ++steps; // a skip still costs a step, so a long drained prefix cannot wall
                    }
                    continue;
                }

                // Charge what the entry ACTUALLY costs, in the shared walk unit. The floor is
                // the per-entry weight — the cold per-player settlement every entry pays however
                // few boxes it holds — plus a lighter weight for each box. Boxes after the first
                // ride the lanes the first one already opened. A flat step per entry stopped
                // meaning anything the moment counts landed, and a flat step per BOX would
                // over-charge wide entries by ~5x.
                uint256 cost = OPEN_HUMAN_ENTRY_WEIGHT +
                    boxes * OPEN_HUMAN_BOX_WEIGHT +
                    (stored == 0 ? 0 : OPEN_HUMAN_ENTRY_WEIGHT);
                // BREAK, never skip. Advancing `cur` past an entry that did not fit would lose
                // it: the cursor is monotonic and never revisits. Breaking leaves the cursor on
                // it for the next call. Paired with the `opened != 0` guard — the first entry of
                // a call always runs, whatever its size — every entry is eventually attempted
                // against a full fresh budget, so nothing can wedge behind a large one.
                if (opened != 0 && steps + cost > budget) break;
                unchecked {
                    ++cur;
                    steps += cost;
                }

                // Guaranteed-non-reverting under the entry-gate + the word!=0 index gate above:
                // resolves the box AND presale legs (each robust to being empty). The cached
                // values cannot go stale across the box leg's external calls: no callee on that
                // path hands control to player code, and a presaleBoxEth write at a worded index
                // is unreachable from the buy path.
                _openLootBoxLegWith(player, idx, word, indexWord, currentLevel);
                if (stored != 0) {
                    presaleBoxEth[idx][player] = 0; // dequeue before resolution
                    _resolvePresaleBox(player, idx, stored, indexWord, currentLevel);
                }
                unchecked {
                    // The presale leg counts as one open: `opened` feeds the crank's progress
                    // and bounty accounting, and a presale-only entry is real work.
                    opened += boxes + (stored != 0 ? 1 : 0);
                }
            }

            if (cur < qlen) break; // budget hit mid-index — resume here next call
            unchecked {
                ++idx; // index fully swept — advance the open frontier (this index is now complete)
            }
            cur = 0;
        }

        unitsSpent = steps;
        boxCursorIndex = idx;
        boxCursor = uint48(cur);
        // Presale is fully drained once the cursor has advanced PAST the close index (every box at
        // indices <= presaleCloseIndex is now opened). One-way, sweep-only; gated on presaleOver so
        // it never fires before the close index is meaningful (zero while presale is open / never
        // closed). Thereafter every open path skips the cold presaleBoxEth SLOAD.
        if (presaleOver && checkPresale && idx > presaleCloseIndex) presaleDrained = true;
    }

    /// @dev Resolve a presale box: 50% FLIP / 40% DGNRS / 10% WWXRP off the salted
    ///      committed word. The closing box also sweeps the Pool.PresaleBox remainder.
    /// @param player Box owner.
    /// @param index The box's RNG index (event tag).
    /// @param stored Packed record: [bit255 closing][96:191 soldBefore][0:95 amount].
    /// @param rngWord The index's committed daily word (lands at the index's advance, not at buy; the box only binds to the index at buy).
    function _resolvePresaleBox(
        address player,
        uint48 index,
        uint256 stored,
        uint256 rngWord,
        uint24 currentLevel
    ) private {
        // A queued record always carries non-zero amount bits (the buy path packs
        // applied >= the box minimum), so a non-zero `stored` implies amount != 0.
        uint256 amount = stored & PRESALE_BOX_AMOUNT_MASK;
        uint256 soldBefore = (stored >> PRESALE_BOX_SOLD_SHIFT) & PRESALE_BOX_AMOUNT_MASK;
        bool closing = (stored & PRESALE_BOX_CLOSING_FLAG) != 0;

        // Domain-separated draw off the committed word + the box's immutable buy data
        // (player + amount). No new mutable SLOAD enters the roll (RNG freeze).
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount)
            )
        );

        uint256 outcome = uint16(seed) % 100;
        uint256 flipOut;
        uint256 dgnrsOut;
        uint256 wwxrpOut;
        if (outcome < 50) {
            // 50% FLIP: variance band recentered on a 400% branch mean.
            uint256 varianceRoll = uint16(seed >> 80) % 20;
            uint256 flipBps;
            if (varianceRoll < 16) {
                flipBps = PRESALE_BOX_FLIP_LOW_BASE_BPS +
                    varianceRoll * PRESALE_BOX_FLIP_LOW_STEP_BPS;
            } else {
                flipBps = PRESALE_BOX_FLIP_HIGH_BASE_BPS +
                    (varianceRoll - 16) * PRESALE_BOX_FLIP_HIGH_STEP_BPS;
            }
            // priceForLevel returns a non-zero constant for every level.
            uint256 priceWei = PriceLookupLib.priceForLevel(currentLevel);
            uint256 flipBudget = (amount * flipBps) / 10_000;
            flipOut = (flipBudget * PRICE_COIN_UNIT) / priceWei;
            // Collapse onto a whole 100-FLIP multiple, EV-preserving, mirroring the lootbox.
            // Only above the threshold: at the milestone price a minimum box bottoms out near
            // 59 FLIP, where a 100-FLIP granule would be the whole prize, so small awards keep
            // the whole-FLIP floor instead. The roll keys on this box's own committed seed —
            // immutable buy data hashed with the index's word — so it is fixed at fulfillment
            // and unsteerable.
            flipOut = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(
                    flipOut,
                    EntropyLib.hash2(seed, FLIP_ROUND_TAG)
                )
                : FlipRoundLib.floorWholeFlip(flipOut);
            if (flipOut != 0) {
                coinflip.creditFlip(player, flipOut);
            }
        } else if (outcome < 90) {
            // 40% DGNRS: 5-tier %-of-pool curve keyed on the FROZEN buy-time cumulative.
            dgnrsOut = _presaleBoxDgnrsReward(player, amount, soldBefore);
        } else {
            // 10% WWXRP: 1 token flavor "dud".
            wwxrpOut = LOOTBOX_WWXRP_PRIZE;
            wwxrp.mintPrize(player, wwxrpOut);
        }

        // Closing box: sweep ALL remaining Pool.PresaleBox DGNRS to this buyer, ON TOP
        // of the roll, regardless of outcome — zeroes the pool for a clean wrap-up.
        uint256 swept;
        if (closing) {
            uint256 remaining = dgnrs.poolBalance(
                IsDGNRS.Pool.PresaleBox
            );
            if (remaining != 0) {
                swept = dgnrs.transferFromPool(
                    IsDGNRS.Pool.PresaleBox,
                    player,
                    remaining
                );
                dgnrsOut += swept;
            }
        }

        emit PresaleBoxOpened(player, index, amount, flipOut, dgnrsOut, wwxrpOut, closing);
    }

    /// @dev Presale-box DGNRS award: tierMultiplier x base x boxEth, base = poolStart/40,
    ///      tier by the FROZEN buy-time cumulative box volume (5 tiers x 10 ETH).
    ///      Snapshots Pool.PresaleBox into presaleBoxDgnrsPoolStart on first resolution.
    /// @param player Box owner to credit.
    /// @param amount Box ETH for this resolution.
    /// @param soldBefore Cumulative box ETH before this box's buy (tier selector).
    /// @return paid Actual DGNRS transferred from the pool.
    function _presaleBoxDgnrsReward(
        address player,
        uint256 amount,
        uint256 soldBefore
    ) private returns (uint256 paid) {
        uint256 poolStart = presaleBoxDgnrsPoolStart;
        if (poolStart == 0) {
            poolStart = dgnrs.poolBalance(IsDGNRS.Pool.PresaleBox);
            if (poolStart == 0) return 0;
            presaleBoxDgnrsPoolStart = poolStart;
        }
        // base = poolStart / 40 DGNRS per ETH; tier multiplier in tenths.
        uint256 tierTenths = _presaleBoxDgnrsTierTenths(soldBefore);
        // amount (wei) * (poolStart/40) per ETH * tier/10:
        //   = poolStart * tierTenths * amount / (40 * 10 * 1 ether)
        // Collapse onto three significant figures so the award reads as a round number
        // at any pool size. A pure floor: no entropy, and the truncation is under 1%.
        uint256 dgnrsAmount = SigFigLib.floorToThreeSigFigs(
            (poolStart * tierTenths * amount) / (400 * 1 ether)
        );
        if (dgnrsAmount == 0) return 0;
        paid = dgnrs.transferFromPool(
            IsDGNRS.Pool.PresaleBox,
            player,
            dgnrsAmount
        );
    }

    /// @dev DGNRS tier multiplier (tenths) by buy-time cumulative box volume.
    ///      [0,10) -> 3.0x, [10,20) -> 2.5x, [20,30) -> 2.0x, [30,40) -> 1.5x, >=40 -> 1.0x.
    /// @param soldBefore Cumulative box ETH before the buy.
    /// @return tenths Tier multiplier x10.
    function _presaleBoxDgnrsTierTenths(
        uint256 soldBefore
    ) private pure returns (uint256 tenths) {
        if (soldBefore < PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER1_TENTHS;
        } else if (soldBefore < 2 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER2_TENTHS;
        } else if (soldBefore < 3 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER3_TENTHS;
        } else if (soldBefore < 4 * PRESALE_BOX_DGNRS_TIER_WIDTH) {
            tenths = PRESALE_BOX_DGNRS_TIER4_TENTHS;
        } else {
            tenths = PRESALE_BOX_DGNRS_TIER5_TENTHS;
        }
    }

    /// @notice Resolve a lootbox directly for decimator/degenerette wins (no RNG wait needed)
    /// @dev Rolls full boons + passes via the common resolver over the STATIC table — this
    ///      path's open timing is claimant-controlled, so no live eligibility may reach the
    ///      draw; ineligible drawn types are discarded at delivery (`_deliverBoon`). Emits
    ///      the per-box `LootBoxOpened` summary like every box path; no cold-bust
    ///      consolation on this auto-resolve path.
    /// @param player Player address to resolve for
    /// @param amount ETH amount for the lootbox resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Whole-point activity score frozen at commitment by the caller — decimator
    ///        claims pass the min score of the winning decimator bucket (sealed at burn);
    ///        degenerette passes the score snapshotted at bet time. Never a live read.
    // payable: reachable from the payable redemption path via an ETH-spin's recirc
    // (`resolveEthSpinFromBox` -> `_resolveLootboxDirect`); delegatecall preserves the
    // in-flight msg.value, so a non-payable callvalue guard here would revert the claim.
    function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (the amount==0 early-return path).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (amount == 0) return;

        uint24 currentLevel = level + 1;
        // Freeze-safe seed: only the committed rngWord — which the caller domain-separates per
        // resolution (Degenerette mixes the immutable betId, the decimator passes its per-level
        // word) — and the player feed it. No live, post-word-reveal input enters the seed, so
        // neither claim timing nor a futurePrizePool nudge can re-roll the outcome. No live day is
        // read here either — boon expiry uses the boon path's own currentDay.
        uint256 seed = EntropyLib.hash2(rngWord, uint256(uint160(player)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        // allowEthSpin=false: this is the recirc entry, called inside resolveDegeneretteBets' deferred
        // ETH-pool flush window — an ETH-spin RMW here would be clobbered by that flush. Roll
        // 19 awards tickets instead. Every box itemizes its contents, so this path emits the
        // `LootBoxOpened` summary unconditionally (gated only by the spin suppression downstream).
        BoxAcc memory acc;
        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            0,
            0,
            activityScore,
            false,
            acc
        );
        // Single-box entry: the accumulator exists for uniformity, and flushing it
        // here keeps every reward credit on one path.
        _flushBoxAcc(player, acc, currentLevel);
        // The boon draw the box's 10% haircut paid for. The common resolver takes the
        // haircut for EVERY caller, so every caller must also draw — the entry sweep does
        // it per tier; the single-box resolvers do it here.
        _rollSingleBoxBoons(player, scaledAmount, currentLevel, seed);
    }

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Delegatecall target of the Game's resolveRedemptionLootbox stub, so msg.sender
    ///      (sDGNRS), msg.value, and address(this) (the Game) are all the caller's. The owed value
    ///      arrives as forwarded ETH (msg.value) plus a stETH top-up for any remainder: msg.value
    ///      covers 0..amount and the rest is pulled via transferFrom (sDGNRS pre-approves GAME for
    ///      max). This lets a partial- or zero-ETH sDGNRS (mid-game depletion) still settle — an
    ///      ETH-only forward would revert and strand the whole claim. Both media credit
    ///      futurePrizePool and count toward the game's claimablePool backing identically. No
    ///      claimableWinnings[SDGNRS] debit occurs — pullRedemptionReserve backed the reservation
    ///      sDGNRS-side at submit (claimable already debited on the ETH leg, never owed on the
    ///      custody leg), so debiting claimable here would double-spend it. Splits into 5 ETH
    ///      boxes resolved by plain internal calls inside this one
    ///      delegatecall frame (same Game storage context, identical per-chunk seed-rehash chain).
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox value to resolve (msg.value ETH + the stETH remainder pulled here)
    /// @param rngWord RNG entropy for lootbox resolution
    /// @param activityScore Snapshotted activity score (whole points) from burn submission
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (amount == 0) return;
        // Forwarded ETH (msg.value) funds the leg; any remainder is pulled as stETH so a
        // partial-ETH sDGNRS can still settle. msg.value must not exceed the leg amount.
        if (msg.value > amount) revert MsgValueExceedsAmount();
        uint256 stethPortion;
        unchecked { stethPortion = amount - msg.value; }
        if (stethPortion != 0) {
            if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert TransferFailed();
        }

        // Credit the just-arrived value to the future prize pool (respects freeze state). The
        // value was segregated out of claimableWinnings[SDGNRS] at submit, so there is no
        // claimable debit here — only a real-value-in credit.
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(amount));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(amount));
        }

        // Resolve lootboxes in 5 ETH chunks
        uint256 remaining = amount;
        while (remaining != 0) {
            uint256 box = remaining > 5 ether ? 5 ether : remaining;
            _resolveRedemptionChunk(player, box, rngWord, activityScore);
            remaining -= box;
            rngWord = EntropyLib.hash1(rngWord);
        }
    }

    /// @dev Resolve one redemption lootbox chunk (≤ 5 ETH, never 0) with a snapshotted activity
    ///      score. Uses the provided score instead of reading current (snapshotted at submission).
    /// @param player Player address to resolve for
    /// @param amount ETH amount for this chunk's resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Raw activity score (whole points) snapshotted at burn submission
    function _resolveRedemptionChunk(address player, uint256 amount, uint256 rngWord, uint16 activityScore) private {
        uint24 currentLevel = level + 1;
        // Freeze-safe seed with NO live day: claim timing must not re-roll the outcome (rngWord,
        // frozen at submission, already domain-separates). No live day is read here — boon expiry
        // uses the boon path's own currentDay, and the event day is unused for this claim.
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, amount)));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        // Each chunk emits its own itemized LootBoxOpened so the per-chunk FLIP datum (otherwise
        // lost in the commingled creditFlip) is recoverable — every box, including a redemption
        // chunk, leaves exactly one settlement event. payColdBustConsolation stays false (no WWXRP
        // on a redemption cold-bust).
        // allowEthSpin=true: redemption credits the pool to storage before this loop, so each
        // chunk's ETH-spin reads/writes fresh storage — no deferred memory-accumulator to race.
        BoxAcc memory acc;
        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            false,
            0,
            0,
            activityScore,
            true,
            acc
        );
        // Single-box entry: the accumulator exists for uniformity, and flushing it
        // here keeps every reward credit on one path.
        _flushBoxAcc(player, acc, currentLevel);
        // The boon draw the box's 10% haircut paid for. The common resolver takes the
        // haircut for EVERY caller, so every caller must also draw — the entry sweep does
        // it per tier; the single-box resolvers do it here.
        _rollSingleBoxBoons(player, scaledAmount, currentLevel, seed);
    }

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @dev Delegatecall target of the Game's creditRedemptionDirect stub, so msg.sender (sDGNRS),
    ///      msg.value, and address(this) (the Game) are all the caller's. The value arrives with the
    ///      same funding mix as resolveRedemptionLootbox — msg.value covers 0..amount and the rest is
    ///      pulled as stETH (sDGNRS pre-approves GAME for max) — so a mid-game ETH-depleted sDGNRS
    ///      still settles. The credit rides the claimable reserve (claimablePool in tandem); the
    ///      arriving value backs it and the player withdraws via the access-gated claimWinnings.
    /// @param player Claimant credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(address player, uint256 amount) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (msg.value > amount) revert MsgValueExceedsAmount();
        if (amount == 0) return;
        uint256 stethPortion;
        unchecked { stethPortion = amount - msg.value; }
        if (stethPortion != 0) {
            if (!steth.transferFrom(msg.sender, address(this), stethPortion)) revert TransferFailed();
        }
        _creditClaimable(player, amount);
        claimablePool += uint128(amount);
    }

    /// @notice Back the sDGNRS redemption reservation: segregate game-side ETH, or verify custody.
    /// @dev Delegatecall target of the Game's pullRedemptionReserve stub, so msg.sender (sDGNRS)
    ///      and address(this) (the Game) are both the caller's — the ETH leg's debit hits the
    ///      Game's ledger and the transfer draws the Game's balance, exactly as an inline body
    ///      would. Called by sDGNRS at gambling-burn submit to reserve the MAX (175%) owed for this
    ///      burn so it can never be re-spent by a concurrent claimable drain (AfKing self-sub,
    ///      claimWinnings, a second same-day claimant). Fail-closed, donation-robust:
    ///      - ETH leg: if claimableWinnings[SDGNRS] AND the game's liquid ETH both cover `amount`,
    ///        physically move the at-risk ETH out to sDGNRS (CHECKED debit, CEI).
    ///      - Custody leg: otherwise (mid-game ETH depletion, or a stETH donation inflating the
    ///        submit base beyond claimable), sDGNRS's own ETH + stETH custody backs the reservation
    ///        in place — no game-side move or ledger debit; the caller's pendingRedemptionEthValue
    ///        records it and the claim pays from custody. Coverage is CUMULATIVE (custody covers
    ///        every outstanding reservation plus this one), keeping in-contract ETH + stETH >=
    ///        pendingRedemptionEthValue an invariant.
    ///      - Neither leg covers => revert (fail-closed).
    /// @param amount The MAX 175% reservation for this burn.
    /// @custom:reverts OnlySDGNRS If caller is not sDGNRS.
    /// @custom:reverts TransferFailed If the ETH transfer fails.
    /// @custom:reverts Insolvent If neither the ETH nor the custody leg covers `amount`.
    function pullRedemptionReserve(uint256 amount) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (amount == 0) return;

        // ETH leg: the claimable[SDGNRS] ledger AND the game's liquid ETH both cover
        // `amount` — segregate the at-risk ETH out to sDGNRS. CHECKED debit (no unchecked); CEI.
        uint256 packedSD = balancesPacked[ContractAddresses.SDGNRS];
        if (
            uint128(packedSD) >= amount &&
            address(this).balance >= amount
        ) {
            // _debitClaimable's guard is dead here — the branch already proved the low half
            // covers `amount`, so `packedSD - amount` touches only the low half (no borrow).
            // Residual for the event is the post-debit low half, computed from the cache.
            balancesPacked[ContractAddresses.SDGNRS] = packedSD - amount;
            claimablePool -= uint128(amount);
            emit ClaimableSpent(ContractAddresses.SDGNRS, amount, uint128(packedSD) - amount, MintPaymentKind.Internal, amount);
            (bool ok, ) = payable(ContractAddresses.SDGNRS).call{value: amount}("");
            if (!ok) revert TransferFailed();
            return;
        }

        // Custody leg (fallback): the ETH side cannot cover (mid-game ETH depletion, or a stETH
        // donation inflated the submit base beyond claimable[SDGNRS]). sDGNRS's own ETH + stETH
        // custody backs the reservation in place, so NO game-side move or ledger debit is needed —
        // the caller's pendingRedemptionEthValue records it and the claim pays from custody.
        // Coverage is CUMULATIVE: custody must cover every outstanding reservation plus this one
        // (pendingRedemptionEthValue is read pre-increment), so the same custody can never back two
        // reservations and in-contract ETH + stETH >= pendingRedemptionEthValue holds inductively.
        if (
            ContractAddresses.SDGNRS.balance + steth.balanceOf(ContractAddresses.SDGNRS) >=
            IsDGNRS(ContractAddresses.SDGNRS).pendingRedemptionEthValue() + amount
        ) {
            return;
        }

        // Neither leg covers => fail-closed.
        revert Insolvent();
    }

    /// @notice Resolve an AfKing-subscription box at the LIVE level from a caller-passed
    ///         frozen-day word.
    /// @dev The afking open route: the LIVE-LEVEL twin of `resolveLootboxDirect` — identical
    ///      resolution shape (derive the seed, roll the target level from the LIVE level, do
    ///      the SINGLE `_applyEvMultiplierWithCap` RMW at open, then `_resolveLootboxCommon`)
    ///      — with two AFKing-specific twists (vs the human `_openLootBoxLeg`):
    ///
    ///        1. the RNG `rngWord` is a CALLER-PASSED param (the GameAfkingModule open-leg
    ///           passes the frozen stamp day's word), NOT read from any index-keyed map; and
    ///        2. the seed `day` is the FROZEN stamped process day (a passed param), NOT the
    ///           live `_simulatedDayIndex()` — the day MUST stay frozen in the seed or a
    ///           self-keepering player could grind the seed by open-timing.
    ///
    ///      The live-level handling matches `resolveLootboxDirect`: `currentLevel = level +
    ///      1` LIVE, `targetLevel = _rollTargetLevel(currentLevel, seed)` rolls from the LIVE
    ///      level (NO stored baseLevel floor — auto-open removes the player's ability to time
    ///      the level, so the level freeze is unnecessary),
    ///      and the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, amount,
    ///      evMultiplierBps)` RMW — the sole residual live-read, a benign monotonic
    ///      down-clamp, keyed on the SAME per-level window of
    ///      `lootboxEvCapPacked[player]` the human buy-time write uses
    ///      so the human + afking boxes share the one per-level 10-ETH EV budget.
    ///      The buy-time EV write is bypassed for afking boxes (the process pass STAMPS only),
    ///      so this is the single draw (no double-draw). The cap hard-clamps at 10 ETH with the
    ///      no-write 100%-EV short-circuit ⇒ NO revert. The seed carries ZERO `block.*`
    ///      entropy.
    ///
    ///      Boons OFF for afking boxes ⇒ `amount` IS the spend exactly (there is no
    ///      boosted-amount freeze field — the stamped `amount` is the unboosted box value).
    ///      The boon/pass ROLL inside `_resolveLootboxCommon` still runs on every ETH-lootbox
    ///      path (gated by real game-state, identical to the auto-resolve callers); the
    ///      boons-off rule governs the AMOUNT field, not the roll.
    ///
    ///      Tail flags match the HUMAN box open (`_openLootBoxLeg`) for outcome parity (an afking box must be
    ///      identical to a normal box in every way that matters): it emits the `LootBoxOpened`
    ///      summary like any box open, and `payColdBustConsolation = true` (a
    ///      bust pays the same WWXRP consolation a human box does). The ONE intentional
    ///      exception is the distress bonus — `distressEth = 0` / `totalPackedEth = 0`: the
    ///      human value is frozen at buy in the order's distress fraction, which the
    ///      stamp-only afking box never writes. Deliberately omitted as a mega-niche
    ///      end-game feature (active only the final day before game-over, by which point
    ///      afking subscribers are gone). No `RngNotReady` guard here — the caller (the
    ///      GameAfkingModule open leg `_autoOpen`) pre-gates on a landed `rngWordByDay[day] != 0`,
    ///      so a zero word never reaches this function. Sole caller: the GameAfkingModule open-leg, via the
    ///      GAME_LOOTBOX_MODULE delegatecall (the box materialization is private to this
    ///      module — `resolveAfkingBox` is the one freeze-correct seam; `resolveLootboxDirect`
    ///      derives the seed from the LIVE day and would not freeze the seed `day`).
    /// @param player Box owner (resolved by the GameAfkingModule open-leg from the sub).
    /// @param amount The stamped spend in wei (boons OFF ⇒ amount == spend).
    /// @param day The boundary-pinned PROCESS day stamped at process (frozen in the seed).
    /// @param rngWord The frozen stamp day's word `rngWordByDay[day]`, passed by the caller.
    /// @param activityScore The stamped activity score in whole points (the FROZEN EV input).
    function resolveAfkingBox(
        address player,
        uint256 amount,
        uint24 day,
        uint256 rngWord,
        uint16 activityScore
    ) external {
        if (amount == 0) return;

        // Same abi.encode seed shape as the human box open (`_openLootBoxLeg`) plus a FROZEN
        // stamped `day` (prevents seed-grinding by open-timing) and the CALLER-PASSED frozen-day
        // word `rngWordByDay[day]`; resolveLootboxDirect uses a different preimage (hash2, no day).
        uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));

        // LIVE level, exactly like resolveLootboxDirect: auto-open removes the
        // player's ability to time the level, so the box rolls from the live level with
        // NO stored baseLevel floor.
        uint24 currentLevel = level + 1;
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        // The SINGLE EV-cap RMW at open — the sole residual live-read, a benign
        // monotonic down-clamp, keyed [player][currentLevel] on the SAME
        // per-level 10-ETH budget map the human buy-time write uses. Fed the FROZEN
        // evMultiplierBps from the stamped activityScore. Hard-clamped, no revert.
        // sDGNRS's protocol-owned self-subscription boxes are exempt: the full amount
        // takes the multiplier and no per-level budget is drawn — its EV benefit is
        // redemption backing, not a player subsidy to bound.
        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = player == ContractAddresses.SDGNRS
            ? (amount * evMultiplierBps) / 10_000
            : _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);

        BoxAcc memory acc;
        _resolveLootboxCommon(
            player,
            0,
            scaledAmount,
            targetLevel,
            currentLevel,
            seed,
            true,
            0,
            0,
            activityScore,
            true,
            acc
        );
        // Single-box entry: the accumulator exists for uniformity, and flushing it
        // here keeps every reward credit on one path.
        _flushBoxAcc(player, acc, currentLevel);
        // The boon draw the box's 10% haircut paid for. The common resolver takes the
        // haircut for EVERY caller, so every caller must also draw — the entry sweep does
        // it per tier; the single-box resolvers do it here.
        _rollSingleBoxBoons(player, scaledAmount, currentLevel, seed);
    }

    // =========================================================================
    // Deity Boon Functions
    // =========================================================================


    // =========================================================================
    // Internal Helper Functions
    // =========================================================================

    /// @dev Roll a target level for lootbox resolution.
    ///      80% chance: 0-4 levels above base. 20% chance: 5-50 levels above base.
    ///      Bit budget (consumed from `seed`):
    ///        - rangeRoll: bits[0..15]   via uint16(seed)         % 100   (bias 0.05%)
    ///        - near-level offset: bits[16..23] via uint8(seed >> 16) % 5 (bias 0.39%)
    ///        - far-level offset:  bits[24..39] via uint16(seed >> 24) % 46 (bias 0.05%)
    /// @param baseLevel The base level to roll from
    /// @param seed Per-resolution 256-bit keccak seed (derived once at _resolveLootboxCommon entry)
    /// @return targetLevel The rolled target level
    function _rollTargetLevel(
        uint24 baseLevel,
        uint256 seed
    ) private pure returns (uint24 targetLevel) {
        uint256 rangeRoll = uint16(seed) % 100;
        if (rangeRoll < 20) {
            // 20% chance: far future (5-50 levels ahead)
            uint256 farOffset = uint16(seed >> 24) % 46;
            targetLevel = baseLevel + uint24(farOffset + 5);
        } else {
            // 80% chance: near future (0-4 levels ahead)
            uint256 nearOffset = uint8(seed >> 16) % 5;
            targetLevel = baseLevel + uint24(nearOffset);
        }
    }

    /// @dev Computes the lootbox value allocated to the boon/pass draw: a fixed BPS of
    ///      the resolution amount, capped at `LOOTBOX_BOON_MAX_BUDGET`.
    /// @param amount ETH-equivalent resolution amount
    /// @return boonBudget Amount allocated to the boon/pass draw
    function _lootboxBoonBudget(uint256 amount) private pure returns (uint256 boonBudget) {
        boonBudget = (amount * LOOTBOX_BOON_BUDGET_BPS) / 10_000;
        if (boonBudget > LOOTBOX_BOON_MAX_BUDGET) {
            boonBudget = LOOTBOX_BOON_MAX_BUDGET;
        }
    }

    /// @dev Common lootbox resolution logic shared by ETH and FLIP lootboxes.
    ///      Handles whale pass jackpots, lazy pass awards, ticket/FLIP rolls, and boons.
    /// @param player Player receiving rewards
    /// @param index Shared (system-wide) RNG index of the lootbox being opened. Used purely as
    ///        the `lootboxIndex` identifier on the manual `LootBoxOpened` emit; auto-resolve
    ///        callers pass `0`.
    /// @param amount ETH-equivalent amount for reward calculations
    /// @param targetLevel Target level for future tickets
    /// @param currentLevel Current game level
    /// @param seed Per-resolution 256-bit keccak seed (single-source-of-entropy threaded through all sub-rolls and bit-sliced per-consumer)
    /// @dev Single-keccak-per-resolution entropy: caller derives `seed` once at entry
    ///      via keccak256(abi.encode(rngWord, player, day, amount)); thread through
    ///      downstream sub-rolls. Bit allocation in primary chunk (`seed`):
    ///        bits[0..15]    rangeRoll % 100         (_rollTargetLevel)
    ///        bits[16..23]   near-offset % 5         (_rollTargetLevel)
    ///        bits[24..39]   far-offset % 46         (_rollTargetLevel)
    ///        bits[40..55]   pathRoll % 20           (_resolveLootboxRoll)
    ///        bits[56..79]   tierRoll % 1000         (_lootboxDgnrsReward sub-call)
    ///        bits[80..95]   varianceRoll % 20       (_resolveLootboxRoll large-FLIP)
    ///        bits[96..119]  ticketVariance % 10000  (_lootboxTicketCount)
    ///        bits[120..151] boon roll % BOON_PPM_SCALE (_rollLootboxBoons)
    ///        bits[224..255] fracRoundUp % 100      (_settleLootboxRoll ticket whole-collapse, per roll; uint32 window, bias ~2e-8)
    ///      Primary-chunk consumption: bits[0..151] (draws) + bits[224..255] (round-up); bits[152..223] free.
    ///      The split second roll uses seed2 = EntropyLib.hash2(seed, 1) (counter-tagged chunk 1,
    ///      collision-free vs primary chunk 0) for BOTH its reward draw AND its own re-rolled
    ///      target level (seed2 bits[0..39], unused by chunk 1's reward draw).
    ///      The Degenerette-spin rolls (WWXRP / FLIP-spins / ETH-spin) derive their sub-seeds
    ///      via hash2(seed, BOX_*_SPIN_TAG) — fresh tagged chunks that consume no primary bits.
    /// @param payColdBustConsolation Whether a ticket-path cold-bust (`whole == 0`) pays the
    ///        roll's `_boxWwxrpStake` in WWXRP; `true` for the manual caller `_openLootBoxLeg`
    ///        and `resolveAfkingBox`, `false` for the auto-resolve callers (`resolveLootboxDirect`,
    ///        `resolveRedemptionLootbox`), which stay silent on cold-bust
    /// @param distressEth Portion of lootbox ETH bought during distress mode (pre-EV-scaling basis)
    /// @param totalPackedEth Total packed lootbox ETH (pre-EV-scaling basis, denominator for distress fraction)
    /// @param activityScore Frozen whole-point activity score threaded to the Degenerette spin rolls
    ///        (WWXRP / FLIP-spins / ETH-spin); identical to the score the box committed.
    /// @param allowEthSpin When false (recirc entry), the 5% ETH-spin roll awards tickets
    ///        instead — see `_resolveLootboxRoll`. Directly-opened boxes pass true.
    function _resolveLootboxCommon(
        address player,
        uint48 index,
        uint256 amount,
        uint24 targetLevel,
        uint24 currentLevel,
        uint256 seed,
        bool payColdBustConsolation,
        uint256 distressEth,
        uint256 totalPackedEth,
        uint16 activityScore,
        bool allowEthSpin,
        BoxAcc memory acc
    ) private {
        uint256 boonBudget = _lootboxBoonBudget(amount);
        uint256 mainAmount = amount - boonBudget;

        // One box, one roll, at the box's own size. The old split-into-two threshold is gone:
        // a medium that resolved as two smalls was the thing the count model exists to stop.
        // A target >= base + 5 is a far-future roll (near offsets are 0-4), which weights the
        // ticket budget up.
        _settleLootboxRoll(
            player, index, mainAmount, amount, targetLevel, seed,
            payColdBustConsolation, distressEth, totalPackedEth,
            targetLevel >= currentLevel + 5, activityScore, allowEthSpin, currentLevel, acc
        );
    }

    /// @dev Settle ONE reward roll: the reward-type draw, then (for a ticket roll) the distress
    ///      bonus + single Bernoulli whole-collapse + queue at `rollLevel`, the whole-FLIP
    ///      floor + creditFlip, and one LootBoxOpened. `rollAmount` drives the reward calc;
    ///      `fullAmount` fills the event's amount field. One box resolves here exactly once.
    /// @param rollAmount This roll's ETH chunk (the box's main amount, boon budget removed).
    /// @param fullAmount The box's full ETH-equivalent amount — event amount field only, not the reward basis.
    /// @param rollLevel The target level this roll's tickets queue at.
    /// @param rollSeed This box's seed.
    /// @param isFarFuture True when rollLevel is far-future (>= base + 5) — weights the ticket budget.
    function _settleLootboxRoll(
        address player,
        uint48 index,
        uint256 rollAmount,
        uint256 fullAmount,
        uint24 rollLevel,
        uint256 rollSeed,
        bool payColdBustConsolation,
        uint256 distressEth,
        uint256 totalPackedEth,
        bool isFarFuture,
        uint16 activityScore,
        bool allowEthSpin,
        uint24 currentLevel,
        BoxAcc memory acc
    ) private {
        if (rollAmount == 0) return;
        // priceForLevel returns a non-zero constant for every level, so targetPrice is
        // always a safe divisor downstream. It prices the TICKET legs (the level the
        // tickets queue at); the FLIP legs derive their own next-level price inside
        // _largeFlipOut.
        uint256 targetPrice = PriceLookupLib.priceForLevel(rollLevel);

        (uint256 flipOut, uint32 scaledWholeTickets, uint256 dgnrsOut, uint256 wwxrpOut, bool wasSpin) =
            _resolveLootboxRoll(player, rollAmount, targetPrice, rollSeed, isFarFuture, activityScore, allowEthSpin, currentLevel, acc);
        acc.dgnrs += dgnrsOut;
        acc.wwxrp += wwxrpOut;

        // Collapsed onto a whole 100-FLIP multiple, EV-preserving, above the threshold where
        // the granule is a small slice of the award; a minimum box at the milestone price
        // pays about 18 FLIP, so smaller awards keep the whole-FLIP floor rather than round
        // to nothing. The roll keys on a domain-separated hash of this roll's own seed,
        // consuming none of the primary chunk's documented bit windows.
        uint256 flipAmount = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(
                flipOut,
                EntropyLib.hash2(rollSeed, FLIP_ROUND_TAG)
            )
            : FlipRoundLib.floorWholeFlip(flipOut);

        bool roundedUp;
        if (scaledWholeTickets != 0) {
            // Distress-mode ticket bonus: 25% extra on the distress-bought fraction.
            if (distressEth != 0 && totalPackedEth != 0) {
                uint256 bonus = (uint256(scaledWholeTickets) * distressEth * DISTRESS_TICKET_BONUS_BPS)
                    / (totalPackedEth * 10_000);
                if (bonus != 0) {
                    // Saturate at the uint32 ceiling instead of wrapping (see _lootboxTicketCount).
                    uint256 boosted = uint256(scaledWholeTickets) + bonus;
                    scaledWholeTickets = boosted > type(uint32).max ? type(uint32).max : uint32(boosted);
                }
            }
            // Collapse scaled tickets to whole via a single Bernoulli round-up on bits[224..255]
            // of THIS roll's seed — a uint32 window, negligible % QTY_SCALE modulo bias (~2e-8);
            // `scaledWholeTickets` stays at the scaled value for the event emit.
            uint32 whole = scaledWholeTickets / uint32(QTY_SCALE);
            uint32 frac = scaledWholeTickets % uint32(QTY_SCALE);
            if (frac != 0 && (uint32(rollSeed >> 224) % uint32(QTY_SCALE)) < frac) {
                unchecked { whole += 1; }
                roundedUp = true;
            }
            // Accumulated by level offset, flushed once per distinct level by `_flushBoxAcc`.
            // Saturated, never checked-overflowed: one roll's `whole` fits uint32 by the roll
            // cap, but a hundred accumulated rolls need not — and a checked revert here would
            // wedge the sweep on this entry forever (first-entry-always-runs retries it every
            // call). The cap keeps `wholeTicketsToEntries`' `<< 2` in range too. Reachable
            // only at economically absurd (though encodable) order sizes; saturation matches
            // the per-roll ceiling's own graceful-cap policy.
            // `_openLootBoxLeg` and `resolveAfkingBox` pay the WWXRP cold-bust consolation;
            // the other auto-resolve callers stay silent.
            _addBoxTickets(acc, rollLevel - currentLevel, whole);
            if (payColdBustConsolation && whole == 0) {
                acc.wwxrp += _boxWwxrpStake(rollAmount);
            }
        }

        acc.flip += flipAmount;

        // Every box roll emits exactly one settlement event. Spin rolls (WWXRP / FLIP-spins /
        // ETH-spin) are recorded by their own single BoxSpin event from the Degenerette module, so
        // the (all-zero) LootBoxOpened is suppressed for them; every other roll emits LootBoxOpened.
        if (!wasSpin) {
            emit LootBoxOpened(
                player,
                index,
                fullAmount,
                rollLevel,
                scaledWholeTickets,
                flipAmount,
                roundedUp
            );
        }
    }








    /// @dev Resolve a single lootbox roll to determine reward type. Split (roll % 20):
    ///      40% tickets, 15% DGNRS, 15% WWXRP-spin, 15% FLIP (flat),
    ///      10% FLIP-spins ×3, 5% ETH-spin. The three spin rolls dispatch into the
    ///      Degenerette module; their sub-seeds are hash2-tagged off `seed` (no primary-
    ///      chunk bits consumed). The ETH-spin only fires on directly-opened boxes
    ///      (`allowEthSpin`); on recirc boxes roll 19 awards tickets instead, which keeps
    ///      every box resolved inside `resolveDegeneretteBets` (the only ETH-pool memory-accumulator
    ///      context) free of an ETH-pool read-modify-write.
    /// @param player Player receiving the reward
    /// @param amount Amount for this roll (may be half of total for split lootboxes)
    /// @param targetPrice Price at the rolled target level (ticket legs only)
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; first invocation uses primary chunk, ETH-amount-second branch uses seed2 = EntropyLib.hash2(seed, 1))
    /// @param isFarFuture True when this roll's target level is far-future (>= base + 5),
    ///        weighting the ticket budget up (1.5x) vs near (0.875x).
    /// @param activityScore Frozen whole-point activity score threaded from the box commitment;
    ///        scales the spin ROI / EV exactly as a regular bet's snapshot does.
    /// @param allowEthSpin When false (recirc boxes), roll 19 awards tickets instead of an
    ///        ETH spin — no ETH-pool RMW can race a deferred `resolveDegeneretteBets` pool flush.
    /// @return flipOut FLIP tokens to award
    /// @return ticketsOut Tickets to queue for future level
    /// @dev Bit budget (consumed from `seed`):
    ///        - pathRoll: bits[40..55]     via uint16(seed >> 40) % 20  (bias 0.02%)
    ///        - DGNRS tier sub-call slice: bits[56..79] (consumed by _lootboxDgnrsReward)
    ///        - large-FLIP varianceRoll: bits[80..95]   via uint16(seed >> 80) % 20  (bias 0.02%)
    ///      Spin sub-seeds use hash2-tagged chunks (BOX_*_SPIN_TAG), counter-tagged and
    ///      collision-free vs the primary chunk, so they consume no additional primary bits.
    function _resolveLootboxRoll(
        address player,
        uint256 amount,
        uint256 targetPrice,
        uint256 seed,
        bool isFarFuture,
        uint16 activityScore,
        bool allowEthSpin,
        uint24 currentLevel,
        BoxAcc memory acc
    )
        private
        returns (uint256 flipOut, uint32 ticketsOut, uint256 dgnrsOut, uint256 wwxrpOut, bool wasSpin)
    {
        if (amount == 0) return (0, 0, 0, 0, false);

        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 8) {
            // 40% chance: tickets (returned as scaled × QTY_SCALE).
            ticketsOut = _lootboxTicketCount(
                _ticketBudget(amount, isFarFuture),
                targetPrice,
                seed
            );
        } else if (roll < 11) {
            // 15% chance: DGNRS tokens. Returned rather than credited — the entry credits each
            // recursion-delimited batch once. Each roll prices against that batch's snapshot
            // MINUS what earlier rolls already claimed, reproducing sequential-purchase economics:
            // pricing every roll off the undecremented balance would let a batched entry take
            // measurably more from a low pool than the same boxes settled one at a time. One
            // staticcall per batch instead of one per DGNRS-winning box. Only an intervening
            // ETH spin can start another batch.
            if (!acc.dgnrsPoolLoaded) {
                acc.dgnrsPool = dgnrs.poolBalance(IsDGNRS.Pool.Lootbox);
                acc.dgnrsPoolLoaded = true;
            }
            dgnrsOut = _lootboxDgnrsReward(
                amount,
                seed,
                acc.dgnrsPool > acc.dgnrs ? acc.dgnrsPool - acc.dgnrs : 0
            );
        } else if (roll < 14) {
            // 15% chance: one WWXRP Degenerette spin staking the roll's size-scaled WWXRP.
            wwxrpOut = _callWwxrpSpin(
                player,
                _boxWwxrpStake(amount),
                activityScore,
                EntropyLib.hash2(seed, BOX_WWXRP_SPIN_TAG)
            );
            wasSpin = true;
        } else if (roll < 17) {
            // 15% chance: large FLIP reward with variance (flat → creditFlip).
            flipOut = _largeFlipOut(amount, seed, currentLevel);
        } else if (roll < 19) {
            // 10% chance: three FLIP Degenerette spins under one survival flip. Stake = the
            // would-be large FLIP haircut to 70.60% (LOOTBOX_FLIP_SPINS_STAKE_BPS). Mint-only
            // (no pool / recirc) → safe on every box path.
            uint256 stake = (_largeFlipOut(amount, seed, currentLevel) *
                LOOTBOX_FLIP_SPINS_STAKE_BPS) / 10_000;
            if (stake != 0) {
                flipOut = _callFlipSpins(
                    player,
                    stake,
                    activityScore,
                    EntropyLib.hash2(seed, BOX_FLIP_SPIN_TAG)
                );
                wasSpin = true;
            }
        } else {
            // 5% chance: one ETH Degenerette spin (direct boxes only). On recirc boxes
            // (allowEthSpin=false) this awards tickets instead, so no ETH-pool RMW occurs
            // inside a deferred-flush context. Stake = the ticket budget it replaces
            // (EV-equal to those tickets), in wei.
            if (allowEthSpin) {
                uint256 ethStake = (_ticketBudget(amount, isFarFuture) *
                    _ticketVarianceBps(seed)) / 10_000;
                if (ethStake != 0) {
                    // The ETH spin may recursively resolve a recirculated lootbox, whose own
                    // accumulator debits Pool.Lootbox immediately. Settle the parent's pending
                    // DGNRS first so the child cannot price against tokens already promised to
                    // the parent. Clear before the external interaction so the final entry flush
                    // cannot pay this batch twice.
                    uint256 pendingDgnrs = acc.dgnrs;
                    if (pendingDgnrs != 0) {
                        acc.dgnrs = 0;
                        uint256 paid = _creditDgnrsReward(player, pendingDgnrs);
                        if (paid != 0) emit LootBoxDgnrsBatch(player, pendingDgnrs, paid);
                    }
                    _callEthSpin(
                        player,
                        ethStake,
                        activityScore,
                        EntropyLib.hash2(seed, BOX_ETH_SPIN_TAG)
                    );
                    // The child may have changed Pool.Lootbox even when the parent had nothing
                    // pending. Force any later parent DGNRS roll to observe the live balance.
                    acc.dgnrsPoolLoaded = false;
                    wasSpin = true;
                }
            } else {
                ticketsOut = _lootboxTicketCount(
                    _ticketBudget(amount, isFarFuture),
                    targetPrice,
                    seed
                );
            }
        }
    }

    /// @dev The ticket-roll ETH budget: the base ticket-roll BPS of `amount`, weighted by the
    ///      far/near target-distance factor. Shared by the ticket roll and the ETH-spin stake
    ///      (which is EV-equal to the tickets roll 19 replaces).
    function _ticketBudget(uint256 amount, bool isFarFuture)
        private
        pure
        returns (uint256)
    {
        uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
        return
            (ticketBudget *
                (isFarFuture
                    ? LOOTBOX_TICKET_FAR_BUDGET_BPS
                    : LOOTBOX_TICKET_NEAR_BUDGET_BPS)) / 10_000;
    }

    /// @dev The large-FLIP output for a roll: variance-tiered BPS of `amount`, converted to
    ///      FLIP at the next-level ticket price (the box's own denomination) — FLIP is
    ///      level-less and spends at the live peg, so the rolled ticket level plays no part.
    ///      Shared by the flat FLIP roll and the FLIP-spins stake.
    function _largeFlipOut(
        uint256 amount,
        uint256 seed,
        uint24 currentLevel
    ) private pure returns (uint256) {
        uint256 varianceRoll = uint16(seed >> 80) % 20;
        uint256 largeFlipBps;
        if (varianceRoll < 16) {
            // Low path (80%): rolls 0-15, 43.88%-97.88% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_LOW_BASE_BPS +
                varianceRoll * LOOTBOX_LARGE_FLIP_LOW_STEP_BPS;
        } else {
            // High path (20%): rolls 16-19, 231.99%-445.74% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS +
                (varianceRoll - 16) * LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS;
        }
        uint256 flipBudget = (amount * largeFlipBps) / 10_000;
        return
            (flipBudget * PRICE_COIN_UNIT) /
            PriceLookupLib.priceForLevel(currentLevel);
    }

    /// @dev The WWXRP magnitude a roll works with: `LOOTBOX_WWXRP_PER_ETH` scaled off the
    ///      roll's own ETH chunk — the same basis the ticket, FLIP and DGNRS legs use, so a
    ///      split box's two halves stay EV-equal to the unsplit box they replace. Floored at
    ///      one whole token so the smallest box still clears `MIN_BET_WWXRP`, which is what
    ///      keeps its spin eligible for the S=9 whale-halfpass award.
    function _boxWwxrpStake(uint256 amount) private pure returns (uint256 stake) {
        stake = amount * LOOTBOX_WWXRP_PER_ETH;
        if (stake < LOOTBOX_WWXRP_PRIZE) stake = LOOTBOX_WWXRP_PRIZE;
    }

    /// @dev Delegatecall the Degenerette module's WWXRP box-spin resolver (Game storage context).
    function _callWwxrpSpin(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private returns (uint256 wwxrpOut) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
        wwxrpOut = abi.decode(data, (uint256));
    }

    /// @dev Delegatecall the Degenerette module's triple-FLIP box-spin resolver.
    function _callFlipSpins(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private returns (uint256 flipOut) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
        flipOut = abi.decode(data, (uint256));
    }

    /// @dev Delegatecall the Degenerette module's ETH box-spin resolver.
    function _callEthSpin(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) private {
        (bool ok, ) = ContractAddresses.GAME_DEGENERETTE_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector,
                player,
                stake,
                activityScore,
                seed,
                uint32(0)
            )
        );
        if (!ok) revert EmptyRevert();
    }

    /// @dev Calculate scaled ticket count from budget with ranged variance tiers.
    ///      Returns count × QTY_SCALE (100) for fractional ticket support. The tier
    ///      chances are 1% / 4% / 20% / 45% / 30%, and each tier draws a multiplier
    ///      uniformly across a symmetric BPS band about its per-tier mean; the overall
    ///      variance EV is ~0.941x:
    ///        1% -> 4.00x-6.50x, 4% -> 2.00x-3.50x, 20% -> 1.00x-1.60x,
    ///        45% -> 0.5923x-0.9923x, 30% -> 0.360x-0.720x.
    ///      The within-tier position reuses the SAME varianceRoll that selects the tier
    ///      (uniform within the tier's chance window), so no extra entropy is drawn.
    ///      Bit budget (consumed from `seed`):
    ///        - varianceRoll: bits[96..119] via uint24(seed >> 96) % 10_000 (bias 0.045%)
    /// @param budgetWei ETH budget for tickets
    /// @param priceWei Price per ticket at target level (a non-zero price-table constant)
    /// @param seed Per-resolution 256-bit keccak seed (sliced inline; no advance)
    /// @return scaledWholeTickets Scaled whole-ticket count (whole x QTY_SCALE), collapsed to entries at queue via wholeTicketsToEntries
    function _lootboxTicketCount(
        uint256 budgetWei,
        uint256 priceWei,
        uint256 seed
    ) private pure returns (uint32 scaledWholeTickets) {
        if (budgetWei == 0) {
            return 0;
        }
        uint256 adjustedBudget = (budgetWei * _ticketVarianceBps(seed)) / 10_000;
        uint256 scaled = (adjustedBudget * QTY_SCALE) / priceWei;
        // Saturate at the uint32 ceiling instead of wrapping. The ceiling (~42.9M scaled
        // whole-tickets in a single roll) is only reachable at economically-impossible box
        // sizes; a graceful cap avoids a silent modular wrap to a tiny count.
        scaledWholeTickets = scaled > type(uint32).max ? type(uint32).max : uint32(scaled);
    }

    /// @dev Draw the within-budget ticket multiplier (BPS) from the variance tiers. Extracted
    ///      from `_lootboxTicketCount` so the ETH-spin stake can reuse the SAME multiplier the
    ///      tickets it replaces would have drawn (EV-equal). Consumes bits[96..119] of `seed`.
    function _ticketVarianceBps(uint256 seed) private pure returns (uint256 ticketBps) {
        uint256 varianceRoll = uint24(seed >> 96) % 10_000;
        uint256 c1 = LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS;
        uint256 c2 = c1 + LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS;
        uint256 c3 = c2 + LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS;
        uint256 c4 = c3 + LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS;

        if (varianceRoll < c1) {
            ticketBps = _ticketRangeBps(
                varianceRoll, 0, c1,
                LOOTBOX_TICKET_VARIANCE_TIER1_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER1_HIGH_BPS
            );
        } else if (varianceRoll < c2) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c1, c2,
                LOOTBOX_TICKET_VARIANCE_TIER2_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER2_HIGH_BPS
            );
        } else if (varianceRoll < c3) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c2, c3,
                LOOTBOX_TICKET_VARIANCE_TIER3_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER3_HIGH_BPS
            );
        } else if (varianceRoll < c4) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c3, c4,
                LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS
            );
        } else {
            ticketBps = _ticketRangeBps(
                varianceRoll, c4, 10_000,
                LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS,
                LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS
            );
        }
    }

    /// @dev Linearly map a uniform `roll` within [windowLow, windowHigh) onto the inclusive
    ///      BPS range [bpsLow, bpsHigh]: the window's first index maps to bpsLow, its last to
    ///      bpsHigh. A roll uniform over the window yields a uniform multiplier whose mean is
    ///      the range midpoint, i.e. the tier's per-tier mean.
    function _ticketRangeBps(
        uint256 roll,
        uint256 windowLow,
        uint256 windowHigh,
        uint256 bpsLow,
        uint256 bpsHigh
    ) private pure returns (uint256) {
        uint256 span = windowHigh - windowLow - 1;
        if (span == 0) return bpsLow;
        return bpsLow + ((roll - windowLow) * (bpsHigh - bpsLow)) / span;
    }

    /// @dev Calculate DGNRS reward amount from the lootbox pool.
    ///      79.5% small tier, 15% medium, 5% large, 0.5% mega.
    ///      Bit budget (consumed from `entropy` — the threaded per-resolution seed):
    ///        - tierRoll: bits[56..79] via uint24(entropy >> 56) % 1000 (bias 0.0024%)
    /// @param amount ETH amount for calculation
    /// @param entropy Per-resolution 256-bit seed (sliced inline; no advance)
    /// @return dgnrsAmount DGNRS tokens to award
    function _lootboxDgnrsReward(
        uint256 amount,
        uint256 entropy,
        uint256 poolBalance
    ) private pure returns (uint256 dgnrsAmount) {
        uint256 tierRoll = uint24(entropy >> 56) % 1000;
        uint256 ppm;
        if (tierRoll < 795) {
            ppm = LOOTBOX_DGNRS_POOL_SMALL_PPM;
        } else if (tierRoll < 945) {
            ppm = LOOTBOX_DGNRS_POOL_MEDIUM_PPM;
        } else if (tierRoll < 995) {
            ppm = LOOTBOX_DGNRS_POOL_LARGE_PPM;
        } else {
            ppm = LOOTBOX_DGNRS_POOL_MEGA_PPM;
        }

        if (poolBalance == 0 || ppm == 0) return 0;
        // Three significant figures, mirroring the presale box. The pool clamp is applied
        // AFTER the collapse, so a clamped award is the pool balance exactly rather than a
        // figure the pool cannot cover.
        dgnrsAmount = SigFigLib.floorToThreeSigFigs(
            (poolBalance * ppm * amount) / (1_000_000 * 1 ether)
        );
        if (dgnrsAmount > poolBalance) {
            dgnrsAmount = poolBalance;
        }
    }

    /// @dev Credit DGNRS reward to player from pool only.
    /// @param player Player to credit
    /// @param amount Requested DGNRS amount to credit
    /// @return paid Actual DGNRS amount paid from pool
    function _creditDgnrsReward(address player, uint256 amount) private returns (uint256 paid) {
        if (amount == 0) return 0;
        paid = dgnrs.transferFromPool(
            IsDGNRS.Pool.Lootbox,
            player,
            amount
        );
    }



}
