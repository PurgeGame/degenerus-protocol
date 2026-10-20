// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

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

import {CrapsPriceLib} from "../libraries/CrapsPriceLib.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IStETH} from "../interfaces/IStETH.sol";

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
    function creditPrize(uint32 to, uint256 amount) external;
}

/// @notice The craps table's day-pass door. Called ONCE per lootbox entry that rolled any pass,
///         never once per box, and it never reverts on an unavailable day.
interface ICrapsPassDelivery {
    /// @notice Bank a rolled pass award as day-pass credits for wallet `id`, revert-free
    ///         (CrapsBattle, game-only; the Game passes the nonzero ID it holds).
    function creditPasses(uint32 id, uint32 normal, uint32 high) external;

    /// @notice Seat a rolled pass award for wallet `id` on tomorrow when available, banking the
    ///         rest as credit (CrapsBattle, game/vault-only; revert-free; the Game passes the
    ///         nonzero ID it holds).
    function deliverPasses(uint32 id, uint32 normal, uint32 high) external returns (uint24 day);
}

/**
 * @title DegenerusGameLootboxModule
 * @author Burnie Degenerus
 * @notice Delegatecall module for lootbox opening and boon consumption.
 *
 * @dev This module is called via `delegatecall` from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 *
 * ## Functions
 *
 * - Box opening (resolveHumanBoxOrder, resolveAfkingBox, resolveLootboxDirect, resolveRedemptionLootbox)
 * - Deity-boon event declarations shared with DegenerusGameBoonModule (issueDeityBoon lives there)
 */
contract DegenerusGameLootboxModule is DegenerusGameStorage {
    // =========================================================================
    // Errors
    // =========================================================================

    // error E() — inherited from DegenerusGameStorage
    /// @notice Thrown when msg.value exceeds the declared lootbox or credit amount.
    error MsgValueExceedsAmount();

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when an ETH lootbox is successfully opened
    /// @param id The reward account's wallet ID.
    /// @param lootboxIndex Entry tag: QUEUED_ENTRY_TAG | position << 1 | buffer for a queued
    ///        entry; REDEMPTION_INDEX_TAG | batchId for an sDGNRS redemption order; 0 for the
    ///        single-box resolvers. With the sealed session it identifies the entry permanently.
    /// @param amount The ETH amount of the lootbox (in wei)
    /// @param futureLevel The target level for future tickets
    /// @param futureTickets The pre-Bernoulli scaled (× QTY_SCALE) future ticket count
    /// @param flip The total FLIP tokens awarded (in wei)
    /// @param roundedUp True iff the Bernoulli round-up incremented the awarded
    ///        whole-ticket count by 1
    event LootBoxOpened(
        uint32 indexed id,
        uint48 indexed lootboxIndex,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint256 flip,
        bool roundedUp
    );

    /// @notice Emitted when a lootbox awards a whale pass jackpot
    /// @param id The reward account's wallet ID.
    /// @param targetLevel Level AT BOX-OPEN TIME (`level + 1`), reported for
    ///        downstream indexers. Ticket queuing is deferred to the player-paid
    ///        `claimWhalePass` endpoint; tickets actually get queued at the level
    ///        when the beneficiary calls `claimWhalePass`, which may be greater
    ///        than this value (the player can delay the claim).
    /// @param entriesPerLevel Entries per level the materialized whale pass grants (2: a
    ///        full pass, one whole ticket every other level)
    /// @param statsBoost 0 at open; stats are applied at `claimWhalePass`
    /// @param frozenUntilLevel 0 at open; the freeze is applied at `claimWhalePass`
    event LootBoxWhalePassJackpot(
        uint32 indexed id,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 entriesPerLevel,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    /// @notice Aggregated DGNRS settlement for an opened entry's contiguous reward batch.
    /// @dev An ETH-spin boundary may split one entry into multiple batches because that spin can
    ///      recursively open another box and mutate the same pool.
    /// @param id The reward account's wallet ID.
    /// @param requested Total DGNRS this contiguous batch priced (pre-clamp).
    /// @param paid DGNRS actually credited from the pool.
    event LootBoxDgnrsBatch(uint32 indexed id, uint256 requested, uint256 paid);

    /// @notice A lootbox entry rolled Craps day passes. `day` is the future day one of them was
    ///         placed on, or zero where none could be — in which case every pass was banked as
    ///         credit instead. Emitted once per entry, never once per box.
    event LootBoxCrapsPasses(uint32 indexed id, uint32 normal, uint32 highRoller, uint24 day);

    /// @notice Unified lootbox reward event for boon awards
    /// @param id The reward account's wallet ID.
    /// @param rewardType The type of reward (2=CoinflipBoon, 4=Boost5, 5=Boost15, 6=Boost25/Purchase, 8=DecimatorBoost, 9=WhaleBoon, 10=ActivityBoon/DeityPassBoon, 11=LazyPassBoon, 12=QuestShield, 13=DegeneretteBoon, 14=CrapsBoon)
    /// @param amount Primary reward amount (varies by type: BPS for boosts, token amount for boons; for type 13 the rolled boonType 32-40, which identifies the boon's currency and size)
    event LootBoxReward(uint32 indexed id, uint8 indexed rewardType, uint256 lootboxAmount, uint256 amount);

    /// @notice Emitted when a lootbox-drawn boon is discarded instead of delivered — the
    ///         statically-drawn type is a deity-pass discount and the player already holds a
    ///         pass or supply is capped. Every other type, decimator tiers included, is
    ///         delivered. Nothing is written; the draw itself stays fully deterministic.
    /// @param id The reward account's wallet ID.
    /// @param boonType The statically-drawn boon type that was discarded
    event BoonDiscarded(uint32 indexed id, uint8 boonType);

    /// @notice Emitted when a deity issues a boon to another player
    /// @param deity The deity pass holder issuing the boon
    /// @param recipient The player receiving the boon
    /// @param day The day index when the boon was issued
    /// @param slot The slot index (0-2) of the boon
    /// @param boonType The type of boon issued (1-43; 10-12 and 20-21 are unused)
    event DeityBoonIssued(
        uint32 indexed deity, uint32 indexed recipient, uint24 indexed day, uint8 slot, uint8 boonType
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
    /// @dev Base ticket budget in BPS of the roll's MAIN amount — the box amount after the
    ///      boon budget (10%, capped at 1 ETH) is carved off in `_resolveLootboxCommon` — for
    ///      ONE ticket outcome, before the variance tiers (~0.941x mean) and the EV-neutral
    ///      near/far distance weighting: ~185% of the main amount per ticket outcome, so a
    ///      neutral 1 ETH box (0.9 ETH main) carries ~1.67 ETH of ticket face on a ticket
    ///      roll. Ticket outcomes are 40% of direct-box rolls and 45% of recirculated-box
    ///      rolls (roll 19 pays tickets there instead of the ETH spin).
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 19_678;
    /// @dev Budget weighting by target-level distance, applied to the ticket roll budget.
    ///      Far-future ticket rolls (20% of ticket rolls) capture 30% of the aggregate
    ///      ticket budget at 1.5x; near rolls take 0.875x. EV-neutral across the 20%/80%
    ///      far/near split (0.8*0.875 + 0.2*1.5 = 1.0), so total ticket value is unchanged.
    uint16 private constant LOOTBOX_TICKET_FAR_BUDGET_BPS = 15_000;
    uint16 private constant LOOTBOX_TICKET_NEAR_BUDGET_BPS = 8750;
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
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS = 5923; // 0.5923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS = 9923; // 0.9923x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS = 3600; // 0.36x
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS = 7200; // 0.72x
    /// @dev 0.001% of DGNRS pool per ETH for small tier
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10;
    /// @dev 0.039% of DGNRS pool per ETH for medium tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390;
    /// @dev 0.08% of DGNRS pool per ETH for large tier
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800;
    /// @dev 0.8% of DGNRS pool per ETH for mega tier
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000;
    /// @dev One whole WWXRP token: the floor
    ///      under every size-scaled box WWXRP amount (see `_boxWwxrpStake`).
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 1;
    /// @dev WWXRP per ETH of roll value — 5 tokens per 0.01 ETH. Since WWXRP carries 18
    ///      decimals like wei, the conversion is a bare multiply on the wei amount.
    uint256 private constant LOOTBOX_WWXRP_PER_ETH = 500;
    /// @dev Domain-separation tags mixed (via hash2) into the box seed to derive each
    ///      Degenerette-spin sub-seed. Counter-tagged off the primary chunk, so the spins
    ///      consume no primary-chunk bits and never collide with the box's own draws.
    uint256 private constant BOX_WWXRP_SPIN_TAG = 0x57777872705370696e; // "WwxrpSpin"
    uint256 private constant BOX_FLIP_SPIN_TAG = 0x4275726e69655370696e; // "BurnieSpin"
    uint256 private constant BOX_ETH_SPIN_TAG = 0x4574685370696e; // "EthSpin"
    // Draw identities, never financial inputs. Separate entry, boon and AFKing streams
    // explicitly instead of relying on a box amount to make their preimages differ. A redemption
    // order rolls through the entry stream on its own player-mixed word with a tagged index.
    uint256 private constant BOX_OPEN_TAG = 0x426f784f70656e; // "BoxOpen"
    uint256 private constant BOX_BOON_TAG = 0x426f78426f6f6e; // "BoxBoon"
    uint256 private constant AFKING_BOX_TAG = 0x41666b696e67426f78; // "AfkingBox"
    /// @dev Domain-separation tag for the 100-FLIP award collapse. Keyed off the box/roll
    ///      seed rather than a spare bit-slice, so the bit budgets documented above stay
    ///      accurate and the roll is fixed at VRF fulfillment.
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
    /// @dev Extractors for the pass lane. Domain-separated so the fractional pass, the fallback
    ///      spin and every other draw off the same box read independent bits of one VRF word —
    ///      these are EXTRACTORS from committed entropy, never a source of their own.
    uint256 private constant BOX_PASS_ROUND_TAG = 0x50617373526f756e64; // "PassRound"
    uint256 private constant BOX_PASS_SPIN_TAG = 0x506173735370696e; // "PassSpin"
    /// @dev Base BPS for low FLIP path (43.88%)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_BASE_BPS = 4388;
    /// @dev Step increase in BPS for low FLIP path (3.60% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_LOW_STEP_BPS = 360;
    /// @dev Base BPS for high FLIP path (231.99%)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS = 23_199;
    /// @dev Step increase in BPS for high FLIP path (71.25% per step)
    uint16 private constant LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS = 7125;
    /// @dev Stake haircut (70.60%) applied to the FLIP-spins branch (roll 17-18) on top of
    ///      the reduced large-FLIP ladder, so the flat FLIP branch carries more of the FLIP
    ///      EV (flat:spins split 68:32 within FLIP). The flat FLIP roll (14) is not haircut, and
    ///      neither is the pass roll (15-16) that denominates the same budget.
    uint16 private constant LOOTBOX_FLIP_SPINS_STAKE_BPS = 7060;

    /// @dev Distress-mode ticket bonus in basis points (25%).
    uint16 private constant DISTRESS_TICKET_BONUS_BPS = 2500;

    // Boon categories — players may hold one boon per category simultaneously.
    // Within a category, upgrade semantics apply (higher tier replaces lower).

    // Deity boon constants

    // Deity boon weights (used for weighted random selection)

    // =========================================================================
    // Lootbox Opening Functions
    // =========================================================================

    /// @dev Apply the EV multiplier against the per-account per-level bonus allowance: the
    ///      first 10 ETH of bonus spend takes the full multiplier, the bonus then tapers to
    ///      half at 20 ETH and to neutral at 40 ETH (`_lootboxEvEligible`). The non-eligible
    ///      remainder gets 100% EV (neutral).
    /// @param id Wallet ID whose allowance is drawn
    /// @param lvl Current game level
    /// @param amount Lootbox ETH amount
    /// @param evMultiplierBps EV multiplier in basis points (9000-14500)
    /// @return scaledAmount Amount after EV adjustment
    function _applyEvMultiplierWithCap(uint32 id, uint24 lvl, uint256 amount, uint256 evMultiplierBps)
        private
        returns (uint256 scaledAmount)
    {
        // Bonus-only allowance: penalty (< NEUTRAL) and neutral (== NEUTRAL) boxes apply the
        // multiplier on the full amount and draw nothing. Only a bonus box (> NEUTRAL) falls
        // through to the draw below.
        if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) {
            return (amount * evMultiplierBps) / 10_000;
        }

        uint256 usedBenefit = _lootboxEvUsedFor(id, lvl);
        if (usedBenefit >= LOOTBOX_EV_ZERO_ETH) {
            // Allowance exhausted: apply 100% EV (neutral)
            return amount;
        }

        (uint256 eligible, uint256 usedAfter) = _lootboxEvEligible(usedBenefit, amount);
        _setLootboxEvUsedFor(id, lvl, usedAfter);

        // The eligible portion gets the EV multiplier, the rest 100% EV.
        scaledAmount = (eligible * evMultiplierBps) / 10_000 + (amount - eligible);
    }

    // =========================================================================
    // Box purchase entries (delegatecalled from the Mint, Whale and Afking modules)
    // =========================================================================
    //
    // Every purchase builds one complete entry word and appends it once to the write buffer.
    // No purchase reads, merges into or moves an earlier entry.

    /// @dev Portion of a box's EV reserved for the boon/pass draw (10%), capped. The haircut
    ///      is taken here because it comes off each box's reward amount; the DRAW itself lives
    ///      in the boon module.
    uint16 private constant LOOTBOX_BOON_BUDGET_BPS = 1000;
    uint256 private constant LOOTBOX_BOON_MAX_BUDGET = 1 ether;

    /// @notice Emitted when a box entry is appended. Same topic as the Mint / Whale / Afking
    ///         declarations — one box-buy event across every path.
    /// @param index Physical write buffer (0/1) the entry joined.
    /// @param position The entry's zero-based position in that buffer.
    event LootBoxBuy(uint32 indexed buyer, uint48 indexed index, uint32 position, uint256 amount);

    /// @notice Emitted when a lootbox-boost boon is consumed by a buy.
    event BoostUsed(
        uint32 indexed player, uint24 indexed day, uint256 originalAmount, uint256 boostedAmount, uint16 boostBps
    );

    /// @dev Floor for the biggest-box bounty.
    uint256 private constant BIGGEST_BOX_MIN_ETH = 5 ether;
    /// @dev Rake-free: all box ETH routes to the prize pools. Distress sends 100% next;
    ///      otherwise 90% future / 10% next.
    uint16 private constant BOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant BOX_SPLIT_NEXT_BPS = 1000;
    /// @dev Boon boost: capped uplift, expiring, consumed on use.
    uint256 private constant BOX_BOOST_MAX_VALUE = 10 ether;
    uint32 private constant BOX_BOOST_EXPIRY_DAYS = 2;

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
    function _consumeBoxBoost(uint32 id, uint256 amount) private returns (uint256 extra) {
        BoonPacked storage bp = boonPacked[id];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return 0;

        uint24 day = _simulatedDayIndex();
        uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
        if (deityDay != 0 && deityDay != day) {
            bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (stampDay != 0 && day > stampDay + BOX_BOOST_EXPIRY_DAYS) {
            bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
            return 0;
        }

        uint16 boostBps = _lootboxTierToBps(tier);
        extra = _boostAmount(amount, boostBps);
        bp.slot0 = (s0 & BP_LOOTBOX_CLEAR) | BP_SLOT0_RETAINED;
        emit BoostUsed(id, day, amount, amount + extra, boostBps);
    }

    /// @notice Build a purchase's ordinary entry: validate and price the order at the active
    ///         level, consume a live boost, snapshot distress, and arm the biggest-box bounty.
    ///         Nothing is queued here — `applyBoxOrderScore` finalizes the word and the caller
    ///         appends it once every leg of the purchase is complete.
    /// @dev Delegatecall entrypoint from the Mint module; runs in the Game's storage context.
    /// @param buyerId The buyer's wallet ID.
    /// @param boxOrder Packed purchase input: [quantity:7][kind:2][customUnits:21].
    /// @return costWei Total wei the order costs.
    /// @return shares Prize-pool shares packed as (future << 128) | next. One return value
    ///         rather than two: the caller holds them across a long stretch of its body, and
    ///         two live locals there is exactly what tips it into a Yul stack-too-deep.
    /// @return flipCredit Any biggest-box bounty claim, to join the buyer's flip credit.
    /// @return word The in-flight entry word, still missing its score.
    function beginBoxOrder(uint32 buyerId, uint256 boxOrder)
        external
        payable
        returns (uint256 costWei, uint256 shares, uint256 flipCredit, uint256 word)
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        (word, costWei) = _decodeBoxOrder(boxOrder, _activeTicketLevel());
        // The boost is capped at a quarter of the spend, so the fraction fits its lane.
        word |= uint256(buyerId) | ((_consumeBoxBoost(buyerId, costWei) * 10_000 / costWei) << LB_BOOST_SHIFT);
        bool distress = _isDistressMode();
        if (distress) word |= LB_DISTRESS;

        // Biggest-box bounty: a CUSTOM only, and its per-box size, never the order's total.
        // Presets are excluded outright — the bounty marks deliberately going big, and a large
        // at a milestone price would clear the floor on its own. With presets out and the
        // candidate a single box, no quantity of small buys can reach it.
        if ((boxOrder >> BO_KIND_SHIFT) & 3 == BO_KIND_CUSTOM) {
            uint256 candidate = (boxOrder >> BO_UNITS_SHIFT) * LB_VALUE_UNIT;
            if (candidate >= BIGGEST_BOX_MIN_ETH) {
                flipCredit = coinflip.armRecord(RECORD_KIND_LUCKBOX, buyerId, candidate);
            }
        }

        unchecked {
            shares = (((costWei * (distress ? 0 : BOX_SPLIT_FUTURE_BPS)) / 10_000) << 128)
                | ((costWei * (distress ? 10_000 : BOX_SPLIT_NEXT_BPS)) / 10_000);
        }
    }

    /// @notice Finalize a purchase's ordinary entry with its post-action activity score.
    /// @dev Delegatecall entrypoint from the Mint module, called once the post-action score is
    ///      known. The score is the resolver's frozen EV knob — the anti-gaming property, since
    ///      the open level is not player-timable but the buy is. Stored as its 12-bit code
    ///      (`_scoreCode`).
    /// @param word The in-flight entry from `beginBoxOrder`.
    /// @param cachedScore Caller's post-action activity score in whole points.
    /// @return The completed ordinary fields.
    function applyBoxOrderScore(uint256 word, uint256 cachedScore)
        external
        payable
        returns (uint256)
    {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return word | (_scoreCode(cachedScore) << LB_SCORE_SHIFT);
    }

    /// @dev Last activity score a queued entry stores exactly; above it the code steps by
    ///      SCORE_CODE_STEP points, reaching ACTIVITY_EFFECTIVE_CAP_POINTS at code 4,039.
    uint256 private constant SCORE_CODE_EXACT = 2042;
    uint256 private constant SCORE_CODE_STEP = 14;

    /// @dev 12-bit code of a queued entry's activity score: clamp to the curves' effective cap,
    ///      then floor-encode. Exact through SCORE_CODE_EXACT and at the cap; in between it
    ///      decodes at most 13 points low, where every curve is nearly flat.
    function _scoreCode(uint256 score) internal pure returns (uint256) {
        if (score > ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            score = ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS;
        }
        unchecked {
            return score <= SCORE_CODE_EXACT ? score : SCORE_CODE_EXACT + (score - SCORE_CODE_EXACT) / SCORE_CODE_STEP;
        }
    }

    /// @dev Whole-point activity score of a 12-bit code.
    function _scoreFromCode(uint256 code) internal pure returns (uint256) {
        unchecked {
            return code <= SCORE_CODE_EXACT ? code : SCORE_CODE_EXACT + (code - SCORE_CODE_EXACT) * SCORE_CODE_STEP;
        }
    }

    /// @notice Append a system-granted box entry — the pass purchases.
    ///         A grant is `count` boxes of equal value (`count == 0` is one box). Each grant is
    ///         its own entry.
    /// @dev Delegatecall entrypoint of the Whale module; runs in the Game's
    ///      storage context. Each box floors to whole LB_VALUE_UNITs; the remainder is reward-side
    ///      only, since the paid and credited ETH stays in the callers' accounting. A grant below
    ///      one unit per box appends nothing, consumes no boost and never blocks the caller. The
    ///      producers bound every grant to LB_UNITS_MAX per box and MAX_BOXES_PER_ORDER boxes;
    ///      nothing here re-checks those bounds.
    /// @param id Player receiving the boxes (registered; its mint word is already loaded).
    /// @param amountWei Box spend in wei.
    /// @param score Caller's activity-score snapshot.
    /// @param boost Whether to consume a live lootbox-boost boon and snapshot distress.
    /// @param count Boxes (whale: min(passes, 100)); zero for one box.
    function recordCoverBox(
        uint32 id,
        uint256 amountWei,
        uint16 score,
        bool boost,
        uint8 count
    ) external payable {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        uint256 qty = count == 0 ? 1 : count;
        uint256 units = amountWei / (qty * LB_VALUE_UNIT);
        if (units == 0) return;
        uint256 word = uint256(id) | (units << LB_UNITS_SHIFT) | (_scoreCode(score) << LB_SCORE_SHIFT)
            | (qty << LB_QTY_SHIFT);
        if (boost) {
            word |= (_consumeBoxBoost(id, amountWei) * 10_000 / amountWei) << LB_BOOST_SHIFT;
            if (_isDistressMode()) word |= LB_DISTRESS;
        }
        (uint48 idx, uint32 position) = _appendBoxEntry(word, amountWei);
        emit LootBoxBuy(id, idx, position, amountWei);
    }

    /// @dev Draw an order's weighted eligible share at opening, before any reward can recurse.
    ///      The caller only draws for a bonus multiplier and a nonzero represented nominal value.
    ///      All orders share the same per-(wallet, opening level) accumulator.
    function _drawEvBenefit(uint32 id, uint24 capLevel, uint256 spend)
        private
        returns (uint256 evExtra)
    {
        uint256 used = _lootboxEvUsedFor(id, capLevel);
        uint256 usedAfter;
        (evExtra, usedAfter) = _lootboxEvEligible(used, spend);
        if (usedAfter != used) _setLootboxEvUsedFor(id, capLevel, usedAfter);
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
        uint256 dgnrsPool; // Lootbox-pool snapshot, read once per recursion-delimited batch
        bool dgnrsPoolLoaded;
        // One bit per non-zero ticket lane. The counters stay unpacked for cheap per-roll
        // updates; bit-scanning makes the final flush proportional to distinct winning levels
        // while preserving the old ascending-level event/write order.
        uint64 ticketTouched;
        uint32[51] tickets;
        // Craps day passes this entry rolled, by denomination. Accumulated across the batch and
        // delivered in ONE call at the end — a winning box does not reach out to Craps on its own.
        uint32 passNormal;
        uint32 passHigh;
        // The entry owner's wallet ID, handed to a nested ETH spin so it needs no lookup.
        uint32 id;
        address payee; // Filled only when a token payout needs it.
    }

    /// @dev Resolve a token recipient once per entry, only on a path that transfers tokens.
    function _boxPayee(BoxAcc memory acc) private view returns (address) {
        if (acc.payee == address(0)) acc.payee = _payee(_walletElement(acc.id));
        return acc.payee;
    }

    /// @dev Resolution context for one order, carried as a single memory struct rather than a
    ///      spread of locals: the box loop threads all of it, and a wide parameter list here is
    ///      exactly what tips this module into a Yul stack-too-deep.
    struct BoxRoll {
        uint32 id; // the entry's wallet ID: the owner input of every seed
        uint48 index; // event tag: the entry reference or the redemption batch tag
        uint256 rootWord; // committed per-entry root every box seed derives from
        uint24 currentLevel;
        uint256 evBps;
        uint256 boostBps;
        uint256 distressBps;
        uint256 adjBps;
        BoxAcc acc; // the entry's shared reward accumulator
        uint16 score;
        uint256 nonce; // boxes rolled so far — also each box's seed nonce
        uint256 boonSeed; // each box's draw is (boonSeed, its nonce)
    }

    /// @dev Draw the order's EV allowance, then resolve its `count` boxes of `size` wei each for
    ///      wallet `c.id` off `c.rootWord`, then settle the order. The caller fills the order's
    ///      identity, level, frozen score, boost and distress into `c`. Box `n` (1-based) seeds
    ///      from hash4(rootWord, id, BOX_OPEN_TAG, n) and the order's boon draws from
    ///      hash4(rootWord, id, BOX_BOON_TAG, boonIndex). Queued entries pass their order root
    ///      and physical buffer; the sDGNRS redemption order passes its ID-mixed word and its
    ///      tagged batch, which no buffer can equal. Every box resolves as its OWN roll.
    function _rollOrder(BoxRoll memory c, uint256 boonIndex, uint256 count, uint256 size) private {
        c.boonSeed = EntropyLib.hash4(c.rootWord, uint256(c.id), BOX_BOON_TAG, boonIndex);
        // The EV multiplier stays FROZEN at buy (`score`) — that is the anti-gaming knob. The
        // box rolls from the LIVE level at open, which the holder cannot steer: the
        // permissionless bounty opens every ready box as soon as it can. One allowance draw
        // covers the WHOLE order before the first roll, including before any nested ETH-spin box.
        c.evBps = _lootboxEvMultiplierFromScore(c.score);
        if (c.evBps > LOOTBOX_EV_NEUTRAL_BPS) {
            // System-grant dust stays in the funded pools; only represented boxes draw EV.
            uint256 nominal = size * count;
            if (nominal != 0) c.adjBps = _drawEvBenefit(c.id, c.currentLevel, nominal) * 10_000 / nominal;
        }
        _rollBoxes(c, count, size);

        // Final settlement for the whole order: one call per remaining fungible lane, one ticket
        // write per distinct level. DGNRS may already be checkpointed at an ETH-spin boundary.
        // Boon draws have completed before this remaining fungible/ticket flush.
        _flushBoxAcc(c.id, c.acc, c.currentLevel);
    }

    /// @dev Re-raise a failed nested module call with its own revert data. Empty data (the
    ///      sub-call ran out of gas) becomes EmptyRevert(), which callers metering gas treat as
    ///      caller-withheld gas; any other failure keeps its reason.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev One box's boon draw, for the resolvers that settle a single box outside the
    ///      entry sweep (daily afking boxes, degenerette auto-resolve, ETH-spin recirc).
    ///      Identical draw to the entry path's per-order call;
    ///      `seed` is the box's own account-specific resolution seed, drawn at nonce 0.
    function _rollSingleBoxBoons(uint32 id, uint256 amount, uint24 currentLevel, uint256 seed) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.rollBoxBoons.selector,
                    id,
                    _lootboxBoonBudget(amount),
                    1,
                    amount,
                    currentLevel,
                    seed,
                    0
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Settle an entry's remaining accumulated rewards: one call per fungible lane, one
    ///      ticket write per distinct target level. DGNRS may already have been checkpointed at
    ///      an ETH-spin recursion boundary; every other lane settles only here.
    function _flushBoxAcc(uint32 id, BoxAcc memory acc, uint24 currentLevel) private {
        uint256 touched = acc.ticketTouched;
        while (touched != 0) {
            // Find the least-significant set bit in six bounded steps (all lanes are 0..50),
            // then clear it. This walks only populated lanes, in ascending lane order.
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
            _queueEntries(id, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false);
            unchecked {
                touched &= touched - 1;
            }
        }
        if (acc.dgnrs != 0) {
            uint256 paid = _creditDgnrsReward(acc, acc.dgnrs);
            // One aggregated emit for the entry's remaining batch, under its OWN event: reusing the per-box
            // LootBoxDgnrsReward schema would silently put DGNRS units in a field indexers
            // read as box ETH.
            if (paid != 0) emit LootBoxDgnrsBatch(id, acc.dgnrs, paid);
        }
        if (acc.flip != 0) coinflip.creditFlip(id, acc.flip);
        if (acc.wwxrp != 0) wwxrp.creditPrize(id, acc.wwxrp);
        if ((acc.passNormal | acc.passHigh) != 0) _deliverPasses(id, acc);
    }

    /// @dev Hand the entry's whole pass award to the craps table in ONE call — not one per winning
    ///      box — and let it place at most one of them on tomorrow.
    ///
    ///      BARE. For the Game the table's delivery door is revert-free — its standing is a
    ///      constant, the reservation only declines, and every balance write saturates — so the
    ///      call can only fail with the whole transaction, and the entry then stays retryable.
    ///      The roll is announced from HERE, and the table's own `CrapsPassesCredited` /
    ///      `CrapsDayReserved` logs say which disposition it landed in, so an indexer reconciles
    ///      every rolled pass.
    function _deliverPasses(uint32 id, BoxAcc memory acc) private {
        uint24 day = ICrapsPassDelivery(ContractAddresses.CRAPS).deliverPasses(
            id, acc.passNormal, acc.passHigh
        );
        emit LootBoxCrapsPasses(id, acc.passNormal, acc.passHigh, day);
    }

    /// @dev Add whole tickets to one target-level offset and remember that offset on first touch.
    ///      Saturating the per-offset count keeps the eventual entry shift
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

    /// @dev Roll `count` boxes of `size` wei each, then dispatch their boon draws in one
    ///      delegatecall. Every box takes its own seed — the nonce is its position in the order —
    ///      so two boxes of one order draw independently (their outcomes may still coincide).
    function _rollBoxes(BoxRoll memory c, uint256 count, uint256 size) private {
        if (count == 0 || size == 0) return;
        uint256 scaled;
        unchecked {
            // The boon uplift was banked as a fraction of the order's nominal value; each box
            // carries its proportional share.
            uint256 boosted = size + (size * c.boostBps) / 10_000;
            // A penalty or neutral order scales the whole box; a bonus order scales only the
            // weighted eligible fraction drawn once at the start of this open and pays the rest —
            // including the boon uplift — at 100%. The adj fraction applies to the RAW size,
            // matching the order's allowance draw (raw nominal value, not boosted): applying it to
            // the boosted basis would quietly extend the EV bonus onto the boost itself. No
            // cap read per box — the order's fraction is already fixed in memory.
            uint256 adjWei = (size * c.adjBps) / 10_000;
            scaled = c.evBps <= LOOTBOX_EV_NEUTRAL_BPS
                ? (boosted * c.evBps) / 10_000
                : (adjWei * c.evBps) / 10_000 + (boosted - adjWei);
            uint256 distressEth = (boosted * c.distressBps) / 10_000;

            for (uint256 i; i < count; ++i) {
                // Seed = the entry's committed root (fixed before the buffer's word is requested,
                // unknowable at buy) + wallet ID + domain + this box's position in the order.
                // Size only prices the award; the nonce already distinguishes every box.
                uint256 seed = EntropyLib.hash4(c.rootWord, uint256(c.id), BOX_OPEN_TAG, ++c.nonce);
                _resolveLootboxCommon(
                    c.id,
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

        (bool okBoon, bytes memory data) = ContractAddresses.GAME_BOON_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameBoonModule.rollBoxBoons.selector,
                    c.id,
                    _lootboxBoonBudget(scaled),
                    count,
                    scaled,
                    c.currentLevel,
                    c.boonSeed,
                    0
                )
            );
        if (!okBoon) _revertDelegate(data);
    }

    /// @dev Domain of a queued entry's root: hash4(QUEUED_ORDER_DOMAIN, word, buffer, position).
    uint256 private constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572; // "QueuedOrder"

    /// @dev Event-tag bit of a queued entry: QUEUED_ENTRY_TAG | position << 1 | buffer. It keeps
    ///      every queued tag apart from the single-box resolvers' 0 and from redemption batches.
    uint48 private constant QUEUED_ENTRY_TAG = uint48(1) << 46;

    /// @notice Settle one queued entry atomically.
    /// @dev Delegatecall target of the AFKing box worker, which owns queue order and stores the
    ///      advanced cursor before this call, so an entry settles at most once. The entry's
    ///      root binds the cohort word to the entry's buffer and position, both fixed when the
    ///      purchase appended it, before that buffer's word was requested; every box and boon
    ///      seed then mixes the stored wallet ID. Token recipients are decoded only when a
    ///      payout transfers tokens.
    /// @param buffer Physical read buffer (0/1).
    /// @param position The entry's zero-based position in that buffer.
    /// @param entry The stored 85-bit entry (LB_* layout).
    /// @param rngWord The buffer's published session word.
    /// @param currentLevel Open level (`level + 1`).
    function resolveHumanBoxOrder(uint48 buffer, uint256 position, uint256 entry, uint256 rngWord, uint24 currentLevel)
        external
    {
        BoxRoll memory c;
        c.id = uint32(entry);
        c.acc.id = c.id;
        c.rootWord = EntropyLib.hash4(QUEUED_ORDER_DOMAIN, rngWord, buffer, position);
        c.index = QUEUED_ENTRY_TAG | (uint48(position) << 1) | buffer;
        c.currentLevel = currentLevel;
        c.score = uint16(_scoreFromCode((entry >> LB_SCORE_SHIFT) & LB_SCORE_MASK));
        c.boostBps = (entry >> LB_BOOST_SHIFT) & LB_BOOST_MASK;
        if (entry & LB_DISTRESS != 0) c.distressBps = 10_000;
        _rollOrder(
            c, buffer, _boxEntryCount(entry), ((entry >> LB_UNITS_SHIFT) & LB_UNITS_MASK) * LB_VALUE_UNIT
        );
    }

    /// @notice Resolve a direct lootbox: an internal ETH reward spin's recirculated box or a
    ///         purchased Degenerette bet's combined win box.
    /// @dev Rolls full boons + passes via the common resolver over the STATIC table — this
    ///      path's open timing is claimant-controlled, so no live eligibility may reach the
    ///      draw; ineligible drawn types are discarded at delivery (`_deliverBoon`). Emits
    ///      the per-box `LootBoxOpened` summary like every box path; no cold-bust
    ///      consolation on this auto-resolve path.
    /// @param id Wallet ID to resolve for
    /// @param amount ETH amount for the lootbox resolution
    /// @param rngWord RNG word to use for resolution
    /// @param activityScore Whole-point activity score frozen at commitment by the caller —
    ///        degenerette passes the score snapshotted at bet time. Never a live read.
    // payable: reachable from the payable redemption path via an ETH-spin's recirc
    // (`resolveEthSpinFromBox` -> `_resolveLootboxDirect`); delegatecall preserves the
    // in-flight msg.value, so a non-payable callvalue guard here would revert the claim.
    function resolveLootboxDirect(uint32 id, uint256 amount, uint256 rngWord, uint16 activityScore)
        external
        payable
    {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value (the amount==0 early-return path).
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (amount == 0) return;

        uint24 currentLevel = level + 1;
        // Freeze-safe seed: only the committed rngWord — which the caller domain-separates per
        // resolution (Degenerette mixes the immutable betId) — and the owner's permanent wallet
        // ID, committed with that bet, feed it. No live, post-word-reveal input enters the seed,
        // so neither claim timing nor a futurePrizePool nudge can re-roll the outcome. No live
        // day is read here either — boon expiry uses the boon path's own currentDay.
        uint256 seed = EntropyLib.hash2(rngWord, uint256(id));
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        uint256 evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));
        uint256 scaledAmount = _applyEvMultiplierWithCap(id, currentLevel, amount, evMultiplierBps);

        // allowEthSpin=false: this is the recirc entry, called inside runDegeneretteWork's deferred
        // ETH-pool flush window — an ETH-spin RMW here would be clobbered by that flush. Roll
        // 19 awards tickets instead. Every box itemizes its contents, so this path emits the
        // `LootBoxOpened` summary unconditionally (gated only by the spin suppression downstream).
        BoxAcc memory acc;
        acc.id = id;
        _resolveLootboxCommon(
            id, 0, scaledAmount, targetLevel, currentLevel, seed, false, 0, 0, activityScore, false, acc
        );
        // Single-box entry: the accumulator exists for uniformity, and flushing it
        // here keeps every reward credit on one path.
        _flushBoxAcc(id, acc, currentLevel);
        // The boon draw the box's 10% haircut paid for. The common resolver takes the
        // haircut for EVERY caller, so every caller must also draw — the entry sweep does
        // it per order; the single-box resolvers do it here.
        _rollSingleBoxBoons(id, scaledAmount, currentLevel, seed);
    }

    /// @dev Tag bit on a redemption order's index: the batch id rides below it, and a real
    ///      lootbox buffer index is 0 or 1, so the two never collide in seeds or events.
    uint48 private constant REDEMPTION_INDEX_TAG = uint48(1) << 47;

    /// @notice Resolve redemption lootboxes for an sDGNRS gambling burn claim.
    /// @dev Forwarded ETH and the protected redemption reserve fund one box order. The ledger
    ///      remainder leaves claimablePool when the value enters the prize pool. The order
    ///      resolves at the live level using the burn's activity snapshot and batch entropy.
    /// @param id The claim's beneficiary wallet ID
    /// @param amount Total lootbox value to resolve (msg.value ETH plus reserved Game backing)
    /// @param rngWord RNG entropy for lootbox resolution
    /// @param activityScore Snapshotted activity score (whole points) from burn submission
    /// @param batchId The redemption batch the claim belongs to (seed and event tag)
    function resolveRedemptionLootbox(
        uint32 id, uint256 amount, uint256 rngWord, uint16 activityScore, uint32 batchId
    ) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (amount == 0) return;
        if (msg.value > amount) revert MsgValueExceedsAmount();
        uint256 ledgerPortion = amount - msg.value;
        if (ledgerPortion != 0) {
            _setRedemptionReserve(_redemptionReserve() - ledgerPortion);
            claimablePool -= uint128(ledgerPortion);
        }

        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(pNext, pFuture + uint128(amount));
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(amount));
        }

        // One order: ~1 ETH boxes up to 20 ETH, then 20 equal larger boxes, each floored to
        // whole gwei. The leg is at least the 0.01 ETH lootbox floor, so every box keeps a
        // nonzero size. Never queued, so no queued-entry width or cap applies.
        uint256 boxes = (amount - 1) / GasBounds.REDEMPTION_BOX_UNIT + 1;
        if (boxes > GasBounds.REDEMPTION_BOXES_MAX) boxes = GasBounds.REDEMPTION_BOXES_MAX;
        // No queue position: the ID-mixed redemption word is the root and the tagged batch keys
        // the boon draw.
        BoxRoll memory c;
        c.id = id;
        c.acc.id = id;
        c.rootWord = rngWord;
        c.index = REDEMPTION_INDEX_TAG | uint48(batchId);
        c.currentLevel = level + 1;
        c.score = activityScore > ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS
            ? uint16(ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS)
            : activityScore;
        _rollOrder(c, c.index, boxes, amount / boxes / 1 gwei * 1 gwei);
    }

    /// @notice Credit the direct half of an sDGNRS redemption claim to `id`'s claimable winnings.
    /// @dev Forwarded ETH increases the pool; the remainder moves protected redemption
    ///      backing to the beneficiary without changing the pool total.
    /// @param id Claimant wallet ID credited.
    /// @param amount Total direct-half value (msg.value ETH plus reserved Game backing).
    function creditRedemptionDirect(uint32 id, uint256 amount) external payable {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlySDGNRS();
        if (msg.value > amount) revert MsgValueExceedsAmount();
        if (amount == 0) return;
        uint256 ledgerPortion = amount - msg.value;
        if (ledgerPortion != 0) _setRedemptionReserve(_redemptionReserve() - ledgerPortion);
        _creditClaimableLogged(id, amount);
        claimablePool += uint128(msg.value);
    }

    /// @notice Resolve an AfKing-subscription box at the LIVE level from a caller-passed
    ///         frozen-day word.
    /// @dev The afking open route: the LIVE-LEVEL twin of `resolveLootboxDirect` — identical
    ///      resolution shape (derive the seed, roll the target level from the LIVE level, apply
    ///      the frozen EV multiplier, then `_resolveLootboxCommon`) — with three AFKing-specific
    ///      twists (vs a queued entry):
    ///
    ///        1. the RNG `rngWord` is a CALLER-PASSED param (the GameAfkingModule open-leg
    ///           passes the frozen stamp day's word), NOT read from any index-keyed map; and
    ///        2. the seed `day` is the FROZEN stamped process day (a passed param), NOT the
    ///           live `_simulatedDayIndex()` — the day MUST stay frozen in the seed or a
    ///           self-mining id could grind the seed by open-timing; and
    ///        3. the per-level EV allowance is neither read nor drawn: the subscription's 1-8
    ///           unit daily cap bounds these boxes instead.
    ///
    ///      The live-level handling matches `resolveLootboxDirect`: `currentLevel = level +
    ///      1` LIVE, `targetLevel = _rollTargetLevel(currentLevel, seed)` rolls from the LIVE
    ///      level (NO stored baseLevel floor — auto-open removes the id's ability to time
    ///      the level, so the level freeze is unnecessary). The seed carries ZERO `block.*`
    ///      entropy.
    ///
    ///      Boons OFF for afking boxes ⇒ `amount` IS the spend exactly (there is no
    ///      boosted-amount freeze field — the stamped `amount` is the unboosted box value).
    ///      The boon/pass ROLL inside `_resolveLootboxCommon` still runs on every ETH-lootbox
    ///      path (gated by real game-state, identical to the auto-resolve callers); the
    ///      boons-off rule governs the AMOUNT field, not the roll.
    ///
    ///      Tail flags match the queued box open for outcome parity (an afking box must be
    ///      identical to a normal box in every way that matters): it emits the `LootBoxOpened`
    ///      summary like any box open, and `payColdBustConsolation = true` (a
    ///      bust pays the same WWXRP consolation a human box does). The ONE intentional
    ///      exception is the distress bonus — `distressEth = 0` / `totalPackedEth = 0`: the
    ///      human value is frozen at buy in the order's distress fraction, which the
    ///      stamp-only afking box never writes. Deliberately omitted as a mega-niche
    ///      end-game feature (active only the final day before game-over, by which point
    ///      afking subscribers are gone). No `RngNotReady` guard here — the caller (the
    ///      GameAfkingModule open leg `_runAfkingWork`) gates on the active published word and a sealed stamp day,
    ///      so a zero word never reaches this function. Sole caller: the GameAfkingModule open-leg, via the
    ///      GAME_LOOTBOX_MODULE delegatecall (the box materialization is private to this
    ///      module — `resolveAfkingBox` binds the caller-passed active session word;
    ///      `resolveLootboxDirect` reads no day at all and takes the committed word its caller
    ///      passes — the Degenerette's betId-mixed word).
    /// @param id Box owner (resolved by the GameAfkingModule open-leg from the sub).
    /// @param amount The stamped spend in wei (boons OFF ⇒ amount == spend).
    /// @param day The boundary-pinned PROCESS day stamped at process (frozen in the seed).
    /// @param rngWord The active published session word, retained until all pending boxes finish.
    /// @param activityScore The stamped activity score in whole points (the FROZEN EV input).
    function resolveAfkingBox(uint32 id, uint256 amount, uint24 day, uint256 rngWord, uint16 activityScore)
        external
    {
        if (amount == 0) return;

        // Seed = the CALLER-PASSED active session word + the subscriber's wallet ID + the FROZEN
        // stamped `day` (prevents seed-grinding by open-timing) + this route's domain.
        // The amount sizes the award and never selects the outcome.
        uint256 seed = EntropyLib.hash4(rngWord, uint256(id), AFKING_BOX_TAG, day);

        // LIVE level, exactly like resolveLootboxDirect: auto-open removes the
        // id's ability to time the level, so the box rolls from the live level with
        // NO stored baseLevel floor.
        uint24 currentLevel = level + 1;
        uint24 targetLevel = _rollTargetLevel(currentLevel, seed);

        // Daily AFKing boxes neither read nor draw the per-level EV allowance: the whole
        // amount takes the FROZEN multiplier. The subscription's 1-8 unit daily cap bounds
        // them instead; manual and recycled boxes keep the allowance.
        uint256 scaledAmount = (amount * _lootboxEvMultiplierFromScore(uint256(activityScore))) / 10_000;

        BoxAcc memory acc;
        acc.id = id;
        _resolveLootboxCommon(
            id, 0, scaledAmount, targetLevel, currentLevel, seed, true, 0, 0, activityScore, true, acc
        );
        // Single-box entry: the accumulator exists for uniformity, and flushing it
        // here keeps every reward credit on one path.
        _flushBoxAcc(id, acc, currentLevel);
        // The boon draw the box's 10% haircut paid for. The common resolver takes the
        // haircut for EVERY caller, so every caller must also draw — the entry sweep does
        // it per order; the single-box resolvers do it here.
        _rollSingleBoxBoons(id, scaledAmount, currentLevel, seed);
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
    function _rollTargetLevel(uint24 baseLevel, uint256 seed) private pure returns (uint24 targetLevel) {
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
    /// @param id Wallet ID receiving rewards
    /// @param index Entry tag (see `LootBoxOpened.lootboxIndex`). Used purely as the
    ///        `lootboxIndex` identifier on the `LootBoxOpened` emit; auto-resolve
    ///        callers pass `0`.
    /// @param amount ETH-equivalent amount for reward calculations
    /// @param targetLevel Target level for future tickets
    /// @param currentLevel Open level (`level + 1`, the level new tickets route to); the
    ///        target-level roll's base and the FLIP legs' price basis.
    /// @param seed Per-resolution 256-bit keccak seed (single-source-of-entropy threaded through all sub-rolls and bit-sliced per-consumer)
    /// @dev One keccak seed per box, derived by the caller from the committed word and the
    ///      box's immutable identity, with the owner's wallet ID as the owner input — queued
    ///      entry: hash4(orderRoot, id, BOX_OPEN_TAG, nonce) where orderRoot =
    ///      hash4(QUEUED_ORDER_DOMAIN, word, buffer, position); sDGNRS redemption order:
    ///      hash4(redemptionWord, id, BOX_OPEN_TAG, nonce), the redemption word being already
    ///      ID-mixed; direct auto-resolve: hash2(rngWord, id); afking:
    ///      hash4(rngWord, id, AFKING_BOX_TAG, frozenDay) — and bit-sliced per consumer:
    ///        bits[0..15]    rangeRoll % 100         (_rollTargetLevel)
    ///        bits[16..23]   near-offset % 5         (_rollTargetLevel)
    ///        bits[24..39]   far-offset % 46         (_rollTargetLevel)
    ///        bits[40..55]   pathRoll % 20           (_resolveLootboxRoll)
    ///        bits[56..79]   tierRoll % 1000         (_lootboxDgnrsReward sub-call)
    ///        bits[80..95]   varianceRoll % 20       (_largeFlipOut)
    ///        bits[96..119]  ticketVariance % 10000  (_ticketVarianceBps)
    ///        bits[224..255] fracRoundUp % 100      (_settleLootboxRoll ticket whole-collapse;
    ///        uint32 window, bias ~2e-8)
    ///      One box, one roll: no split and no second chunk. The boon draw is not sliced from
    ///      this seed — the Boon module rolls it from hash2(boonSeed, nonce) >> 120 (queued
    ///      entry: boonSeed = hash4(orderRoot, id, BOX_BOON_TAG, buffer); redemption order:
    ///      hash4(redemptionWord, id, BOX_BOON_TAG, taggedBatch); single-box resolvers pass the
    ///      box seed at nonce 0). The Degenerette-spin rolls (WWXRP / FLIP-spins / ETH-spin) derive
    ///      their sub-seeds via hash2(seed, BOX_*_SPIN_TAG) and consume no primary bits.
    /// @param payColdBustConsolation Whether a ticket-path cold-bust (`whole == 0`) pays the
    ///        roll's `_boxWwxrpStake` in WWXRP; `true` for queued entries
    ///        and `resolveAfkingBox`, `false` for the auto-resolve callers (`resolveLootboxDirect`,
    ///        `resolveRedemptionLootbox`), which stay silent on cold-bust
    /// @param distressEth Portion of lootbox ETH bought during distress mode (pre-EV-scaling basis)
    /// @param totalPackedEth Total packed lootbox ETH (pre-EV-scaling basis, denominator for distress fraction)
    /// @param activityScore Frozen whole-point activity score threaded to the Degenerette spin rolls
    ///        (WWXRP / FLIP-spins / ETH-spin); identical to the score the box committed.
    /// @param allowEthSpin When false (recirc entry), the 5% ETH-spin roll awards tickets
    ///        instead — see `_resolveLootboxRoll`. Directly-opened boxes pass true.
    /// @param acc Running reward accumulator the caller flushes after all of a box's rolls settle.
    function _resolveLootboxCommon(
        uint32 id,
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
            id,
            index,
            mainAmount,
            amount,
            targetLevel,
            seed,
            payColdBustConsolation,
            distressEth,
            totalPackedEth,
            targetLevel >= currentLevel + 5,
            activityScore,
            allowEthSpin,
            currentLevel,
            acc
        );
    }

    /// @dev Settle ONE reward roll: the reward-type draw, then (for a ticket roll) the distress
    ///      bonus + single Bernoulli whole-collapse + queue at `rollLevel`, the whole-FLIP
    ///      floor + creditFlip, and one LootBoxOpened. `rollAmount` drives the reward calc;
    ///      `fullAmount` fills the event's amount field. One box resolves here exactly once.
    /// @param id Wallet ID receiving rewards.
    /// @param index Entry tag (see `LootBoxOpened.lootboxIndex`) — event tag only.
    /// @param rollAmount This roll's ETH chunk (the box's main amount, boon budget removed).
    /// @param fullAmount The box's full ETH-equivalent amount — event amount field only, not the reward basis.
    /// @param rollLevel The target level this roll's tickets queue at.
    /// @param rollSeed This box's seed.
    /// @param payColdBustConsolation Whether a ticket-path cold-bust (`whole == 0`) pays the
    ///        roll's `_boxWwxrpStake` in WWXRP.
    /// @param distressEth Portion of lootbox ETH bought during distress mode (pre-EV-scaling
    ///        basis).
    /// @param totalPackedEth Total packed lootbox ETH (pre-EV-scaling basis, denominator for
    ///        distress fraction).
    /// @param isFarFuture True when rollLevel is far-future (>= base + 5) — weights the ticket budget.
    /// @param activityScore Frozen whole-point activity score threaded to the Degenerette
    ///        spin rolls.
    /// @param allowEthSpin When false, the 5% ETH-spin roll awards tickets instead.
    /// @param currentLevel Open level (`level + 1`, the level new tickets route to); the
    ///        target-level roll's base and the FLIP legs' price basis.
    /// @param acc Running reward accumulator this roll adds its FLIP, whole tickets (by level
    ///        offset), DGNRS, WWXRP and pass output to.
    function _settleLootboxRoll(
        uint32 id,
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

        (uint256 flipOut, uint32 scaledWholeTickets, uint256 dgnrsOut, uint256 wwxrpOut, bool wasSpin) = _resolveLootboxRoll(
            id, rollAmount, targetPrice, rollSeed, isFarFuture, activityScore, allowEthSpin, currentLevel, acc
        );
        acc.dgnrs += dgnrsOut;
        acc.wwxrp += wwxrpOut;

        // Collapsed onto a whole 100-FLIP multiple, EV-preserving, above the threshold where
        // the granule is a small slice of the award; a minimum box at the milestone price
        // pays about 18 FLIP, so smaller awards keep the whole-FLIP floor rather than round
        // to nothing. The roll keys on a domain-separated hash of this roll's own seed,
        // consuming none of the primary chunk's documented bit windows.
        uint256 flipAmount = flipOut > FlipRoundLib.FLIP_ROUND_THRESHOLD
            ? FlipRoundLib.roundFlipToHundreds(flipOut, EntropyLib.hash2(rollSeed, FLIP_ROUND_TAG))
            : FlipRoundLib.floorWholeFlip(flipOut);

        bool roundedUp;
        if (scaledWholeTickets != 0) {
            // Distress-mode ticket bonus: 25% extra on the distress-bought fraction.
            if (distressEth != 0 && totalPackedEth != 0) {
                uint256 bonus =
                    (uint256(scaledWholeTickets) * distressEth * DISTRESS_TICKET_BONUS_BPS) / (totalPackedEth * 10_000);
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
                unchecked {
                    whole += 1;
                }
                roundedUp = true;
            }
            // Accumulated by level offset, flushed once per distinct level by `_flushBoxAcc`.
            // Saturated, never checked-overflowed: one roll's `whole` fits uint32 by the roll
            // cap, but a hundred accumulated rolls need not — and a checked revert here would
            // wedge the sweep on this entry forever (first-entry-always-runs retries it every
            // call). The cap keeps `wholeTicketsToEntries`' `<< 2` in range too. Reachable
            // only at economically absurd (though encodable) order sizes; saturation matches
            // the per-roll ceiling's own graceful-cap policy.
            // Queued entries and `resolveAfkingBox` pay the WWXRP cold-bust consolation;
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
            emit LootBoxOpened(id, index, fullAmount, rollLevel, scaledWholeTickets, flipAmount, roundedUp);
        }
    }

    /// @dev Resolve a single lootbox roll to determine reward type. Split (roll % 20):
    ///      40% tickets, 15% DGNRS, 15% WWXRP-spin, 5% FLIP (flat),
    ///      10% Craps day passes, 10% FLIP-spins ×3, 5% ETH-spin. The three spin rolls dispatch into the
    ///      Degenerette module; their sub-seeds are hash2-tagged off `seed` (no primary-
    ///      chunk bits consumed). The ETH-spin only fires on directly-opened boxes
    ///      (`allowEthSpin`); on recirc boxes roll 19 awards tickets instead, which keeps
    ///      every box resolved inside a bet resolution (the sweep's `runDegeneretteWork`, the
    ///      ETH-pool memory-accumulator context) free of an ETH-pool
    ///      read-modify-write.
    /// @param id Wallet ID receiving the reward
    /// @param amount The roll's main amount (box amount less the boon budget)
    /// @param targetPrice Price at the rolled target level (ticket legs only)
    /// @param seed The box's 256-bit keccak seed (sliced inline)
    /// @param isFarFuture True when this roll's target level is far-future (>= base + 5),
    ///        weighting the ticket budget up (1.5x) vs near (0.875x).
    /// @param activityScore Frozen whole-point activity score threaded from the box commitment;
    ///        scales the spin ROI / EV exactly as a regular bet's snapshot does.
    /// @param allowEthSpin When false (recirc boxes), roll 19 awards tickets instead of an
    ///        ETH spin — no ETH-pool RMW can race a deferred `runDegeneretteWork` pool flush.
    /// @param currentLevel Open level (`level + 1`), the FLIP legs' price basis.
    /// @param acc Running reward accumulator: caches the DGNRS pool read (priced net of DGNRS
    ///        already pending), is flushed/invalidated around an ETH spin, and receives the
    ///        Craps-pass branch's pass counts. DGNRS/WWXRP output is returned, not accumulated here.
    /// @return flipOut FLIP tokens to award
    /// @return ticketsOut Tickets to queue for future level (scaled by QTY_SCALE)
    /// @return dgnrsOut DGNRS tokens to award (0 unless the DGNRS branch rolled)
    /// @return wwxrpOut WWXRP tokens to award (0 unless the WWXRP-spin branch rolled)
    /// @return wasSpin True when a Degenerette spin fired (WWXRP-spin, FLIP-spins, ETH-spin, or the
    ///         Craps-pass branch's zero-pass WWXRP-spin fallback) rather than a flat award (tickets,
    ///         DGNRS, flat FLIP, or passes) — the spin's own BoxSpin event replaces LootBoxOpened
    /// @dev Bit budget (consumed from `seed`):
    ///        - pathRoll: bits[40..55]     via uint16(seed >> 40) % 20  (bias 0.02%)
    ///        - DGNRS tier sub-call slice: bits[56..79] (consumed by _lootboxDgnrsReward)
    ///        - large-FLIP varianceRoll: bits[80..95]   via uint16(seed >> 80) % 20  (bias 0.02%)
    ///      Spin sub-seeds use hash2-tagged chunks (BOX_*_SPIN_TAG), counter-tagged and
    ///      collision-free vs the primary chunk, so they consume no additional primary bits.
    function _resolveLootboxRoll(
        uint32 id,
        uint256 amount,
        uint256 targetPrice,
        uint256 seed,
        bool isFarFuture,
        uint16 activityScore,
        bool allowEthSpin,
        uint24 currentLevel,
        BoxAcc memory acc
    ) private returns (uint256 flipOut, uint32 ticketsOut, uint256 dgnrsOut, uint256 wwxrpOut, bool wasSpin) {
        if (amount == 0) return (0, 0, 0, 0, false);

        uint256 roll = uint16(seed >> 40) % 20;
        if (roll < 8) {
            // 40% chance: tickets (returned as scaled × QTY_SCALE).
            ticketsOut = _lootboxTicketCount(_ticketBudget(amount, isFarFuture), targetPrice, seed);
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
            dgnrsOut = _lootboxDgnrsReward(amount, seed, acc.dgnrsPool > acc.dgnrs ? acc.dgnrsPool - acc.dgnrs : 0);
        } else if (roll < 14) {
            // 15% chance: one WWXRP Degenerette spin staking the roll's size-scaled WWXRP.
            wwxrpOut = _callWwxrpSpin(
                id, _boxWwxrpSpinStake(amount), activityScore, EntropyLib.hash2(seed, BOX_WWXRP_SPIN_TAG)
            );
            wasSpin = true;
        } else if (roll == 14) {
            // 5% chance: large FLIP reward with variance (flat → creditFlip).
            flipOut = _largeFlipOut(amount, seed, currentLevel) / TOKEN_MATH_SCALE;
        } else if (roll < 17) {
            // 10% chance: CRAPS DAY PASSES, denominated out of the same flat-FLIP budget the roll
            // above pays in coin. The budget is used UNROUNDED on purpose — the whole/100-FLIP
            // granule below exists to make a credited balance legible, and a pass is counted, not
            // credited, so rounding first would throw away value before it was ever denominated.
            //
            // DENOMINATED, NOT EQUIVALENT. A pass is priced at the EXPECTED COST of the day it
            // buys, and roughly two thirds of that cost is bankroll the table then plays — so what
            // the holder ends up with is a day's play, not the FLIP the coin roll would have
            // credited. That is the trade the branch is making, not an accident of rounding.
            wasSpin =
                _rollCrapsPasses(id, _largeFlipOut(amount, seed, currentLevel), amount, seed, activityScore, acc);
        } else if (roll < 19) {
            // 10% chance: three FLIP Degenerette spins under one survival flip. Stake = the
            // would-be large FLIP haircut to 70.60% (LOOTBOX_FLIP_SPINS_STAKE_BPS). Mint-only
            // (no pool / recirc) → safe on every box path.
            uint256 stake = (_largeFlipOut(amount, seed, currentLevel) * LOOTBOX_FLIP_SPINS_STAKE_BPS) / 10_000;
            if (stake != 0) {
                flipOut = _callFlipSpins(id, stake, activityScore, EntropyLib.hash2(seed, BOX_FLIP_SPIN_TAG));
                wasSpin = true;
            }
        } else {
            // 5% chance: one ETH Degenerette spin (direct boxes only). On recirc boxes
            // (allowEthSpin=false) this awards tickets instead, so no ETH-pool RMW occurs
            // inside a deferred-flush context. Stake = the ticket budget it replaces
            // (EV-equal to those tickets), in wei.
            if (allowEthSpin) {
                uint256 ethStake = (_ticketBudget(amount, isFarFuture) * _ticketVarianceBps(seed)) / 10_000;
                if (ethStake != 0) {
                    // The ETH spin may recursively resolve a recirculated lootbox, whose own
                    // accumulator debits Pool.Lootbox immediately. Settle the parent's pending
                    // DGNRS first so the child cannot price against tokens already promised to
                    // the parent. Clear before the external interaction so the final entry flush
                    // cannot pay this batch twice.
                    uint256 pendingDgnrs = acc.dgnrs;
                    if (pendingDgnrs != 0) {
                        acc.dgnrs = 0;
                        uint256 paid = _creditDgnrsReward(acc, pendingDgnrs);
                        if (paid != 0) emit LootBoxDgnrsBatch(id, pendingDgnrs, paid);
                    }
                    _callEthSpin(id, ethStake, activityScore, EntropyLib.hash2(seed, BOX_ETH_SPIN_TAG));
                    // The child may have changed Pool.Lootbox even when the parent had nothing
                    // pending. Force any later parent DGNRS roll to observe the live balance.
                    acc.dgnrsPoolLoaded = false;
                    wasSpin = true;
                }
            } else {
                ticketsOut = _lootboxTicketCount(_ticketBudget(amount, isFarFuture), targetPrice, seed);
            }
        }
    }

    /// @dev The ticket-roll ETH budget: the base ticket-roll BPS of `amount`, weighted by the
    ///      far/near target-distance factor. Shared by the ticket roll and the ETH-spin stake
    ///      (which is EV-equal to the tickets roll 19 replaces).
    function _ticketBudget(uint256 amount, bool isFarFuture) private pure returns (uint256) {
        uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
        return (ticketBudget * (isFarFuture ? LOOTBOX_TICKET_FAR_BUDGET_BPS : LOOTBOX_TICKET_NEAR_BUDGET_BPS)) / 10_000;
    }

    /// @dev The large-FLIP output for a roll: variance-tiered BPS of `amount`, converted to
    ///      FLIP at the next-level ticket price (the box's own denomination) — FLIP is
    ///      level-less and spends at the live peg, so the rolled ticket level plays no part.
    ///      Returns 10^18 sub-units per FLIP, retaining fractions for the spin/pass branches.
    ///      The flat award converts to whole tokens at its payment boundary.
    function _largeFlipOut(uint256 amount, uint256 seed, uint24 currentLevel) private pure returns (uint256) {
        uint256 varianceRoll = uint16(seed >> 80) % 20;
        uint256 largeFlipBps;
        if (varianceRoll < 16) {
            // Low path (80%): rolls 0-15, 43.88%-97.88% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_LOW_BASE_BPS + varianceRoll * LOOTBOX_LARGE_FLIP_LOW_STEP_BPS;
        } else {
            // High path (20%): rolls 16-19, 231.99%-445.74% of value
            largeFlipBps = LOOTBOX_LARGE_FLIP_HIGH_BASE_BPS + (varianceRoll - 16) * LOOTBOX_LARGE_FLIP_HIGH_STEP_BPS;
        }
        uint256 flipBudget = (amount * largeFlipBps) / 10_000;
        return (flipBudget * (PRICE_COIN_UNIT * TOKEN_MATH_SCALE)) / PriceLookupLib.priceForLevel(currentLevel);
    }

    /// @dev Turn one box's flat-FLIP budget into whole day passes.
    ///
    ///      ONE BOX PAYS ONE DENOMINATION. Under twenty-two normal passes' worth it pays normal ones;
    ///      past that the WHOLE award becomes high-roller passes. Never a mixture — a box that
    ///      would pay twenty-three normal instead pays a bit over one high, which is the same value
    ///      in the denomination that suits it, and the switch is evaluated per box rather than
    ///      over a batch so a big order cannot be split or merged to move the threshold.
    ///
    ///      THE FRACTION IS PLAYED, NOT DROPPED. A budget worth 7.3 passes pays seven and takes a
    ///      30% shot at the eighth, off its own extractor. Flooring would quietly tax every box,
    ///      and ceiling would quietly subsidise one; over many boxes this pays exactly the budget.
    ///
    ///      A NORMAL BOX THAT ROUNDS TO ZERO is not a blank: it takes a WWXRP spin instead, so the
    ///      smallest pass-winning boxes still hand something over. The high branch cannot reach
    ///      zero — it is only entered above twenty-two normal units, so its count is over one before
    ///      the coin is even tossed.
    /// @return spun Whether the zero-pass fallback consumed a spin.
    function _rollCrapsPasses(
        uint32 id,
        uint256 budget,
        uint256 amount,
        uint256 seed,
        uint16 activityScore,
        BoxAcc memory acc
    ) private returns (bool spun) {
        bool high = budget > CrapsPriceLib.HIGH_SWITCH * TOKEN_MATH_SCALE;
        uint256 unit = (high ? HIGH_ROLLER_DAY_PASS_VALUE : NORMAL_DAY_PASS_VALUE) * TOKEN_MATH_SCALE;
        uint256 count;
        unchecked {
            count = budget / unit;
            uint256 remainder = budget % unit;
            // The fractional pass, decided on its own extractor: the chance of the extra one is
            // exactly the fraction left over. The modulo bias from reducing a 256-bit uniform by
            // a ~2.48e22 unit is far below any threshold that could matter here.
            if (remainder != 0 && EntropyLib.hash2(seed, BOX_PASS_ROUND_TAG) % unit < remainder) {
                ++count;
            }
        }
        if (count == 0) {
            // Rounded away — take the consolation spin instead. Additive by design: it is not
            // deducted from the budget and not netted off anywhere else.
            acc.wwxrp += _callWwxrpSpin(
                id, _boxWwxrpSpinStake(amount), activityScore, EntropyLib.hash2(seed, BOX_PASS_SPIN_TAG)
            );
            return true;
        }
        unchecked {
            if (high) acc.passHigh += uint32(count);
            else acc.passNormal += uint32(count);
        }
    }

    /// @dev The WWXRP magnitude a roll works with: `LOOTBOX_WWXRP_PER_ETH` scaled off the
    ///      roll's main amount — the same basis the ticket, FLIP and DGNRS legs use, so every
    ///      box path stakes in proportion to its size, with a one-token minimum stake.
    function _boxWwxrpStake(uint256 amount) private pure returns (uint256 stake) {
        return _boxWwxrpSpinStake(amount) / TOKEN_MATH_SCALE;
    }

    /// @dev Virtual spin stake retains fractional tokens; the one-token minimum is unchanged.
    function _boxWwxrpSpinStake(uint256 amount) private pure returns (uint256 stake) {
        stake = amount * LOOTBOX_WWXRP_PER_ETH;
        if (stake < LOOTBOX_WWXRP_PRIZE * TOKEN_MATH_SCALE) stake = LOOTBOX_WWXRP_PRIZE * TOKEN_MATH_SCALE;
    }

    /// @dev Delegatecall the Degenerette module's WWXRP box-spin resolver (Game storage context).
    function _callWwxrpSpin(uint32 id, uint256 stake, uint16 activityScore, uint256 seed)
        private
        returns (uint256 wwxrpOut)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector,
                    id,
                    stake,
                    activityScore,
                    seed,
                    uint8(32)
                )
            );
        if (!ok) _revertDelegate(data);
        wwxrpOut = abi.decode(data, (uint256));
    }

    /// @dev Delegatecall the Degenerette module's triple-FLIP box-spin resolver.
    function _callFlipSpins(uint32 id, uint256 stake, uint16 activityScore, uint256 seed)
        private
        returns (uint256 flipOut)
    {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector,
                    id,
                    stake,
                    activityScore,
                    seed,
                    uint8(32)
                )
            );
        if (!ok) _revertDelegate(data);
        flipOut = abi.decode(data, (uint256));
    }

    /// @dev Delegatecall the Degenerette module's ETH box-spin resolver.
    function _callEthSpin(uint32 id, uint256 stake, uint16 activityScore, uint256 seed) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_DEGENERETTE_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector,
                    id,
                    stake,
                    activityScore,
                    seed,
                    uint8(32)
                )
            );
        if (!ok) _revertDelegate(data);
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
    function _lootboxTicketCount(uint256 budgetWei, uint256 priceWei, uint256 seed)
        private
        pure
        returns (uint32 scaledWholeTickets)
    {
        if (budgetWei == 0) {
            return 0;
        }
        uint256 adjustedBudget = (budgetWei * _ticketVarianceBps(seed)) / 10_000;
        uint256 scaled = (adjustedBudget * QTY_SCALE) / priceWei;
        // Saturate at the uint32 ceiling instead of wrapping. The ceiling (4,294,967,295
        // scaled units, ~42.9M whole tickets in a single roll) is only reachable at
        // economically-impossible box sizes; a graceful cap avoids a silent modular wrap to
        // a tiny count.
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
                varianceRoll, 0, c1, LOOTBOX_TICKET_VARIANCE_TIER1_LOW_BPS, LOOTBOX_TICKET_VARIANCE_TIER1_HIGH_BPS
            );
        } else if (varianceRoll < c2) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c1, c2, LOOTBOX_TICKET_VARIANCE_TIER2_LOW_BPS, LOOTBOX_TICKET_VARIANCE_TIER2_HIGH_BPS
            );
        } else if (varianceRoll < c3) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c2, c3, LOOTBOX_TICKET_VARIANCE_TIER3_LOW_BPS, LOOTBOX_TICKET_VARIANCE_TIER3_HIGH_BPS
            );
        } else if (varianceRoll < c4) {
            ticketBps = _ticketRangeBps(
                varianceRoll, c3, c4, LOOTBOX_TICKET_VARIANCE_TIER4_LOW_BPS, LOOTBOX_TICKET_VARIANCE_TIER4_HIGH_BPS
            );
        } else {
            ticketBps = _ticketRangeBps(
                varianceRoll, c4, 10_000, LOOTBOX_TICKET_VARIANCE_TIER5_LOW_BPS, LOOTBOX_TICKET_VARIANCE_TIER5_HIGH_BPS
            );
        }
    }

    /// @dev Linearly map a uniform `roll` within [windowLow, windowHigh) onto the inclusive
    ///      BPS range [bpsLow, bpsHigh]: the window's first index maps to bpsLow, its last to
    ///      bpsHigh. A roll uniform over the window yields a uniform multiplier whose mean is
    ///      the range midpoint, i.e. the tier's per-tier mean.
    function _ticketRangeBps(uint256 roll, uint256 windowLow, uint256 windowHigh, uint256 bpsLow, uint256 bpsHigh)
        private
        pure
        returns (uint256)
    {
        uint256 span = windowHigh - windowLow - 1;
        if (span == 0) return bpsLow;
        return bpsLow + ((roll - windowLow) * (bpsHigh - bpsLow)) / span;
    }

    /// @dev Calculate DGNRS reward amount from the lootbox pool.
    ///      49.7% small tier, 36.7% medium, 13.1% large, 0.5% mega.
    ///      Bit budget (consumed from `entropy` — the threaded per-resolution seed):
    ///        - tierRoll: bits[56..79] via uint24(entropy >> 56) % 1000 (bias 0.0024%)
    /// @param amount ETH amount for calculation
    /// @param entropy Per-resolution 256-bit seed (sliced inline; no advance)
    /// @param poolBalance Remaining DGNRS lootbox-pool balance; the award clamps to this ceiling.
    /// @return dgnrsAmount DGNRS tokens to award
    function _lootboxDgnrsReward(uint256 amount, uint256 entropy, uint256 poolBalance)
        private
        pure
        returns (uint256 dgnrsAmount)
    {
        uint256 tierRoll = uint24(entropy >> 56) % 1000;
        uint256 ppm;
        if (tierRoll < 497) {
            ppm = LOOTBOX_DGNRS_POOL_SMALL_PPM;
        } else if (tierRoll < 864) {
            ppm = LOOTBOX_DGNRS_POOL_MEDIUM_PPM;
        } else if (tierRoll < 995) {
            ppm = LOOTBOX_DGNRS_POOL_LARGE_PPM;
        } else {
            ppm = LOOTBOX_DGNRS_POOL_MEGA_PPM;
        }

        if (poolBalance == 0 || ppm == 0) return 0;
        // Three significant figures. The pool clamp is applied
        // AFTER the collapse, so a clamped award is the pool balance exactly rather than a
        // figure the pool cannot cover.
        dgnrsAmount = SigFigLib.floorToThreeSigFigs((poolBalance * ppm * amount) / (1_000_000 * 1 ether));
        if (dgnrsAmount > poolBalance) {
            dgnrsAmount = poolBalance;
        }
    }

    /// @dev Credit DGNRS reward from the Lootbox pool to box owner `id`'s payee (its own key,
    ///      or the owner's for a smurf). Resolve the payee only on the first token transfer.
    /// @param acc Entry accumulator holding the owner ID and lazy token-recipient cache.
    /// @param amount Requested DGNRS amount to credit
    /// @return paid Actual DGNRS amount paid from pool
    function _creditDgnrsReward(BoxAcc memory acc, uint256 amount) private returns (uint256 paid) {
        if (amount == 0) return 0;
        paid = dgnrs.transferFromPool(IsDGNRS.Pool.Lootbox, _boxPayee(acc), amount);
    }
}
