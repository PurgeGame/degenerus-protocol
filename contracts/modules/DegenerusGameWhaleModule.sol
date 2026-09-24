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
import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGameLootboxModule} from "../interfaces/IDegenerusGameModules.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

/// @dev CrapsBattle's credit-only pass door. OnlyGame-gated; this module runs as a delegatecall
///      inside the Game, so the external call reaches the table with msg.sender == GAME. The
///      door makes no external calls and saturates at the lane cap instead of reverting.
interface ICrapsPassCredit {
    /// @notice Bank a rolled pass award as day-pass credits, revert-free (CrapsBattle, game-only).
    function creditPasses(address player, uint32 normal, uint32 high) external;
}

/**
 * @title DegenerusGameWhaleModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling whale pass, lazy pass, and deity pass purchases.
 * @dev This module is called via delegatecall from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 */
contract DegenerusGameWhaleModule is DegenerusGameMintStreakUtils {
    /// @notice Register both protocol deities and batch their first 100 perpetual tickets.
    /// @dev One creator transaction after deployment; registration rejects a repeated grant.
    function initProtocolDeity() external {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (msg.sender != ContractAddresses.CREATOR) revert E();
        _registerDeity(ContractAddresses.VAULT, VAULT_DEITY_SYMBOL);
        _registerDeity(ContractAddresses.SDGNRS, SDGNRS_DEITY_SYMBOL);
        _latchConstructionSeat(ContractAddresses.VAULT);
        _latchConstructionSeat(ContractAddresses.SDGNRS);
        emit EntriesQueuedRange(ContractAddresses.VAULT, 1, 100, 1, DEITY_PERPETUAL_ENTRIES);
        emit EntriesQueuedRange(ContractAddresses.SDGNRS, 1, 100, 1, DEITY_PERPETUAL_ENTRIES);
        uint24 mintCeiling = _mintCeiling();
        uint24 writeSlotBit = ticketWriteSlot ? TICKET_SLOT_BIT : 0;
        for (uint24 lvl = 1; lvl <= 100; ++lvl) {
            uint24 key = lvl > mintCeiling ? _tqFarFutureKey(lvl) : lvl | writeSlotBit;
            _queueGenesisDeities(lvl, key);
        }
    }


    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    // error InvalidQuantity() — inherited from DegenerusGameMintStreakUtils
    /// @notice Thrown when, at a century milestone level (passLevel % 100 == 0), a
    ///         standard-price purchase takes fewer than two whale passes; the
    ///         boon-discount branch is not gated.
    error MinQuantityRequired();
    /// @notice Thrown when the current game level is not eligible for a lazy pass
    ///         purchase (not level 0-2, x9, x0, or an unlocked century) and the caller
    ///         has no valid lazy pass boon.
    error InvalidLevelForPass();
    /// @notice Thrown when the buyer already holds a deity pass, which is incompatible
    ///         with purchasing a lazy pass.
    error DeityPassConflict();
    /// @notice Thrown when the player's existing frozen pass has more than 7 levels
    ///         remaining and is not yet eligible for early renewal.
    error PassNotExpired();
    /// @notice Thrown when the symbol ID is out of the valid range (must be 0-31).
    error InvalidSymbol();
    /// @notice Thrown when the requested deity symbol has already been claimed by
    ///         another buyer.
    error SymbolTaken();
    /// @notice Thrown when the buyer already holds a deity pass; only one per address
    ///         is permitted.
    error AlreadyOwnsDeityPass();
    // error RngLocked() — inherited from DegenerusGameStorage

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a lootbox boost boon is consumed during a purchase.
    /// @param player The address whose boost was consumed.
    /// @param day The day index when the boost was consumed.
    /// @param originalAmount The base lootbox amount before boost.
    /// @param boostedAmount The lootbox amount after applying the boost.
    /// @param boostBps The boost percentage in basis points that was applied.
    event LootBoxBoostConsumed(
        address indexed player,
        uint24 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    /// @notice Emitted on every pass-bundled lootbox deposit (whale / lazy / deity pass). Same
    ///         signature/topic as the mint module's `LootBoxBuy` — one box-buy event across paths.
    /// @param buyer The box recipient.
    /// @param index The lootbox RNG index the box queued at.
    /// @param amount The deposited box ETH (this deposit).
    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 amount
    );

    /// @notice weiIn = whale-pass ETH-in (any funding source); the pass's reward LootBoxBuy is
    ///         excluded from off-chain ETH-in by tx-correlation with this event.
    event WhalePassPurchased(address indexed buyer, uint256 quantity, uint256 weiIn);

    /// @notice weiIn = lazy-pass ETH-in (any funding source); the pass's reward LootBoxBuy is
    ///         excluded from off-chain ETH-in by tx-correlation with this event.
    event LazyPassPurchased(address indexed buyer, uint24 startLevel, uint256 weiIn);

    /// @notice Emitted when whale pass rewards are claimed.
    /// @param player Player receiving tickets.
    /// @param caller Address that initiated the claim.
    /// @param halfPasses Half-pass count used for ticket awards.
    /// @param startLevel Level where ticket awards begin.
    event WhalePassClaimed(
        address indexed player,
        address indexed caller,
        uint256 halfPasses,
        uint24 startLevel
    );

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev Maximum lootbox value eligible for boost (10 ETH scaled).

    /// @dev Lootbox boost expiry duration (2 game days, expires at jackpot reset).

    /// @dev PPM scale for DGNRS pool calculations (1,000,000 = 100%).
    uint32 private constant DGNRS_WHALE_REWARD_PPM_SCALE = 1_000_000;

    /// @dev Whale pass minter reward: 1% of whale pool.
    uint32 private constant DGNRS_WHALE_MINTER_PPM = 10_000;

    /// @dev Direct affiliate reward for deity pass: 0.5% of the unreserved affiliate pool (after reserving outstanding level claims).
    uint32 private constant DGNRS_AFFILIATE_DIRECT_DEITY_PPM = 5_000;

    /// @dev Upline affiliate reward for deity pass: 0.1% of the unreserved affiliate pool.
    uint32 private constant DGNRS_AFFILIATE_UPLINE_DEITY_PPM = 1_000;

    /// @dev Deity pass buyer reward: 5% of whale pool.
    uint16 private constant DEITY_WHALE_POOL_BPS = 500;

    /// @dev Lazy pass: number of levels covered.
    uint24 private constant LAZY_PASS_LEVELS = 10;

    /// @dev Lazy pass: entries per level (4 entries = 1 whole ticket).
    uint32 private constant LAZY_PASS_ENTRIES_PER_LEVEL = 4;

    /// @dev Lazy pass: share of purchase value awarded as lootbox (10%).
    uint16 private constant LAZY_PASS_LOOTBOX_BPS = 1000;

    /// @dev Lazy pass: split to future pool (matches standard purchase split).
    uint16 private constant LAZY_PASS_TO_FUTURE_BPS = 1000;

    /// @dev Whale pass early price (levels 0-3).
    uint256 private constant WHALE_PASS_EARLY_PRICE = 2.4 ether;

    /// @dev Whale pass standard price (levels 4+).
    uint256 private constant WHALE_PASS_STANDARD_PRICE = 4 ether;

    /// @dev Whale pass bonus entries per level over the intro-price window (5 whole tickets).
    uint32 private constant WHALE_BONUS_ENTRIES_PER_LEVEL = 20;

    /// @dev Half-passes per whale pass (1 half-pass = 1 entry/level equivalent); the
    ///      standard leg awards these as whole-ticket chunks via _queueHalfPassAward.
    uint256 private constant WHALE_HALF_PASSES_PER_PASS = 2;

    /// @dev Last level eligible for whale pass bonus entries — the end of the intro price
    ///      tier (levels 0-9); level 10 opens the standard 100-level cycle pricing.
    uint24 private constant WHALE_BONUS_END_LEVEL = 9;

    /// @dev Bulk buy: every 5 passes in one purchase award one more pass's entries (same
    ///      shape as a paid pass). Price, lootbox, DGNRS, affiliate and Craps credit follow
    ///      the paid quantity only.
    uint256 private constant WHALE_BULK_BONUS_DIVISOR = 5;

    /// @dev Whale pass lootbox share (10%).
    uint16 private constant WHALE_LOOTBOX_BPS = 1000;

    /// @dev Paid passes one whale purchase may carry (player route and the sDGNRS automatic
    ///      purchase alike). Bounds the bundled box count (`uint8`), the Craps credit and the
    ///      local reward recurrence; the aggregate ticket award is one range walk regardless.
    uint256 private constant WHALE_MAX_QUANTITY = 100;

    /// @dev sDGNRS's automatic purchase spends at most this fraction of its game-side claimable
    ///      (1/4): `budget = claimable / SDGNRS_WHALE_BUDGET_DIVISOR`.
    uint256 private constant SDGNRS_WHALE_BUDGET_DIVISOR = 4;

    /// @dev Deity pass lootbox share (10%) from level 10 on.
    uint16 private constant DEITY_LOOTBOX_BPS = 1000;

    /// @dev Deity pass lootbox share below level 10 (5%): the halved lootbox funds the
    ///      high-roller Craps pass the early purchase banks.
    uint16 private constant DEITY_EARLY_LOOTBOX_BPS = 500;

    /// @dev Deity pass base price (24 ETH, unscaled). Price = 24 + T(n) where T(n) = n*(n+1)/2,
    ///      n = paid sales, through the 24th paid pass (n = 23, 300 ETH); every later pass
    ///      doubles the one before it, so the 30th costs 19,200 ETH.
    uint256 private constant DEITY_PASS_BASE = 24 ether;
    uint256 private constant DEITY_DOUBLING_ANCHOR_SOLD = 23;
    uint256 private constant DEITY_DOUBLING_ANCHOR_PRICE = 300 ether;

    /// @dev Deity pass boon expiry (4 game days, expires at jackpot reset).
    uint32 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------

    /**
     * @notice Purchase a 100-level whale pass.
     * @dev Available at any level. The 100-level span starts at current level + 1.
     *      - Boosts levelCount by delta between current freeze and new freeze (max 100, no double dipping).
     *      - Queues 20 × awardQty bonus entries/lvl for levels passLevel-9; the rest of the span
     *        is awarded as whole tickets (4 entries each): awardQty/2 tickets on every level, plus
     *        one ticket every 2nd level when awardQty is odd (1 pass = 1 whole ticket per 2 levels).
     *        awardQty = paid quantity plus the bulk bonus below.
     *      - Bulk buy: every 5 passes in one purchase award one more pass's entries; the
     *        price, lootbox, DGNRS, affiliate and Craps credit follow the paid quantity.
     *      - Lootbox: 10% of price, as one custom box per pass bought; fewer, larger boxes as
     *        the entry's 100-box cap closes, held customs averaged in (a full entry with no
     *        custom to fold into reverts; the next RNG index clears it).
     *      - Below level 10: one Craps day-pass credit per pass purchased, banked at the
     *        table (credit-only, spendable via applyCrapsPasses). Keys on passes bought,
     *        not price paid, so a boon-discounted purchase earns the same.
     *      - Distributes DGNRS minter rewards to the buyer.
     *      - Affiliate: fresh 25% (affiliate levels 1-3) or 20% (4+), halved to
     *        12.5% / 10% for bulk buys (5+ paid passes). Recycled funds earn 5% of the price
     *        in FLIP, exactly like a ticket mint (kickback share credited back to the buyer).
     *
     *      Price: 2.4 ETH at levels 0-3, 4 ETH at levels 4+, 10/20/35% off standard with boon.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 30% next pool, 70% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the pass.
     * @param quantity Number of passes to purchase (1-100).
     * @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
     * @custom:reverts GameOver When gameOver is true.
     * @custom:reverts InvalidQuantity When quantity is 0 or exceeds 100.
     * @custom:reverts MinQuantityRequired When a century (x00) pass level is purchased with quantity < 2
     *         on the standard-price path. A boon purchase takes the discount branch and is not gated.
     */
    function purchaseWhalePass(
        address buyer,
        uint256 quantity,
        bytes32 affiliateCode
    ) external payable {
        if (_livenessTriggered()) revert GameOver();
        uint24 passLevel = level + 1;

        if (quantity == 0 || quantity > WHALE_MAX_QUANTITY) revert InvalidQuantity();

        (bool hasValidBoon, uint256 s0) = _whaleBoonState(buyer);
        // x00 (century) levels: minimum 2 passes (8 ETH) to deter fresh-account century bonus
        // farming. Standard-price path only; a boon purchase takes the discount branch.
        if (!hasValidBoon && passLevel % 100 == 0 && quantity < 2) revert MinQuantityRequired();
        (uint256 firstPrice, uint256 restPrice) = _whaleUnitPrices(passLevel, hasValidBoon, s0);
        uint256 totalPrice = firstPrice + restPrice * (quantity - 1);

        // Claimable-pay: msg.value first (overpay -> payer's afking), claimable covers the rest.
        uint256 freshPaid = msg.value > totalPrice ? totalPrice : msg.value;
        _creditAfkingValue(msg.sender, msg.value - freshPaid);
        _deliverWhalePass(buyer, passLevel, quantity, totalPrice, freshPaid, hasValidBoon, s0, affiliateCode);
    }

    /**
     * @notice sDGNRS's once-per-level automatic whale purchase, driven from the afking process
     *         STAGE (GameAfkingModule.processSubscriberStage) — never a player entry.
     * @dev Delegatecall-only inside the Game (the STAGE nests into this module from its own
     *      delegatecall context); no facade stub forwards this selector, so nothing outside the
     *      daily crank can trigger reserve spending. Sizes the buy at the largest whole group of
     *      `WHALE_BULK_BONUS_DIVISOR` (five) paid passes whose ACTUAL quote — the same quote a
     *      player pays, boon discount included — fits one quarter of sDGNRS's game-side claimable
     *      (raw ledger, sentinel included: a quarter is inherently <= claimable - 1), capped at
     *      the public route's `WHALE_MAX_QUANTITY`. Below one group nothing is bought and nothing
     *      is consumed; the caller latches the level on the attempt either way (one probe per
     *      level, no later retry).
     *
     *      RNG timing contract: the entries this queues must never land against a word that
     *      already exists. The STAGE runs unlocked and pre-RNG, and this re-checks both halves
     *      live — lock down AND the process day's word uncommitted (a VRF-gap replay is unlocked
     *      yet holds a public word) — before any debit, boon consumption or award. A zero return
     *      costs the level its purchase, never the crank its day; the caller charges the STAGE
     *      weight only on a non-zero return.
     *
     *      Liveness: the delivery's one refusing path (a full lootbox entry with no custom box to
     *      fold the bundled reward into) is preflighted here and skipped, so the crank never
     *      stalls on the purchase; a terminal game buys nothing. Everything else the delivery
     *      touches is revert-free for a claimable-funded protocol buyer: the quote is within
     *      claimable, the affiliate code is blank (vault default, recycle-rate leg only), the
     *      seat bit was latched at genesis, and the Craps door saturates instead of reverting.
     *
     *      Gas: one aggregate award (never per pass) — the STAGE charges
     *      `SUB_STAGE_SDGNRS_WHALE_WEIGHT` against its chunk budget on a non-zero return.
     * @param processDay The STAGE's boundary-pinned process day (the word key checked live).
     * @return paidPasses Paid passes bought this call (a multiple of five), 0 when nothing was.
     */
    function purchaseWhalePassForSdgnrs(uint24 processDay) external returns (uint256 paidPasses) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (rngLockedFlag || rngWordByDay[processDay] != 0) return 0;
        if (_livenessTriggered()) return 0;

        uint24 passLevel = level + 1;
        (bool hasValidBoon, uint256 s0) = _whaleBoonState(ContractAddresses.SDGNRS);
        (uint256 firstPrice, uint256 restPrice) = _whaleUnitPrices(passLevel, hasValidBoon, s0);
        uint256 budget = _claimableOf(ContractAddresses.SDGNRS) / SDGNRS_WHALE_BUDGET_DIVISOR;
        // quote(q) = firstPrice + restPrice * (q - 1) <= budget  <=>  q * restPrice <= budget + restPrice - firstPrice.
        // firstPrice <= restPrice on every path (the boon only discounts), so the sum never underflows.
        uint256 groups = (budget + restPrice - firstPrice) / (restPrice * WHALE_BULK_BONUS_DIVISOR);
        if (groups > WHALE_MAX_QUANTITY / WHALE_BULK_BONUS_DIVISOR) {
            groups = WHALE_MAX_QUANTITY / WHALE_BULK_BONUS_DIVISOR;
        }
        if (groups == 0) return 0;
        if (_lootboxEntryRefusesPass(ContractAddresses.SDGNRS)) return 0;

        paidPasses = groups * WHALE_BULK_BONUS_DIVISOR;
        uint256 totalPrice = firstPrice + restPrice * (paidPasses - 1);
        _deliverWhalePass(
            ContractAddresses.SDGNRS, passLevel, paidPasses, totalPrice, 0, hasValidBoon, s0, bytes32(0)
        );
    }

    /// @dev Whale boon lane read: whether `buyer` holds a live whale discount boon and the packed
    ///      slot-0 word the consumer clears from. Deity-granted boons are valid only on the grant
    ///      day; lootbox-rolled keep the 4-day window (mirrors the BoonModule/deity-pass siblings).
    ///      A read only — nothing is consumed here, so a quote can be sized before committing.
    function _whaleBoonState(address buyer) private view returns (bool valid, uint256 s0) {
        s0 = boonPacked[buyer].slot0;
        uint24 boonDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        if (boonDay != 0) {
            uint24 currentDay = _simulatedDayIndex();
            uint24 deityWhaleDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
            valid = deityWhaleDay != 0 ? deityWhaleDay == currentDay : currentDay <= boonDay + 4;
        }
    }

    /// @dev The canonical whale quote's two unit prices: `first` for the first pass, `rest` for
    ///      every further one (total = first + rest * (quantity - 1)). With a live boon the first
    ///      pass takes the tier discount off the STANDARD price and the rest pay standard — the
    ///      boon branch never sees the intro price; otherwise 2.4 ETH through passLevel 4 (stored
    ///      levels 0-3) and 4 ETH after. `first <= rest` on every path.
    function _whaleUnitPrices(
        uint24 passLevel,
        bool hasValidBoon,
        uint256 s0
    ) private pure returns (uint256 first, uint256 rest) {
        if (hasValidBoon) {
            uint16 discountBps = _whaleTierToBps(uint8(s0 >> BP_WHALE_TIER_SHIFT));
            first = (WHALE_PASS_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
            rest = WHALE_PASS_STANDARD_PRICE;
        } else {
            first = passLevel <= 4 ? WHALE_PASS_EARLY_PRICE : WHALE_PASS_STANDARD_PRICE;
            rest = first;
        }
    }

    /// @dev True when `recordCoverBox` would refuse a pass purchase for `player` at the live
    ///      lootbox index: the entry already holds `MAX_BOXES_PER_ORDER` boxes and no custom box
    ///      exists to fold the bundled reward into. Mirrors the recorder's own count exactly.
    function _lootboxEntryRefusesPass(address player) private view returns (bool) {
        uint48 idx = uint48((lootboxRngPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        uint256 word = lootboxOrder[idx][player];
        if (word == 0) return false;
        if (_lbGet(word, LB_CUSTOM_COUNT_SHIFT, LB_COUNT_MASK) != 0) return false;
        uint256 held = _lbGet(word, LB_SMALL_SHIFT, LB_COUNT_MASK)
            + _lbGet(word, LB_MED_SHIFT, LB_COUNT_MASK)
            + _lbGet(word, LB_LARGE_SHIFT, LB_COUNT_MASK)
            + (_lbGet(word, LB_COVER_SHIFT, LB_COVER_MASK) == 0 ? 0 : 1);
        return held >= MAX_BOXES_PER_ORDER;
    }

    /// @dev The whale purchase past its quote: consumes the boon, debits the price (fresh ETH
    ///      first, then claimable, then afking), extends the freeze/streak, queues the aggregate
    ///      ticket award, pays the affiliate legs, the batched DGNRS minter reward, the pool split,
    ///      the bundled lootbox, the early Craps credit and the one-time seat. Shared by the player
    ///      route and the sDGNRS automatic purchase, so the two can never diverge.
    /// @param buyer The address receiving the pass.
    /// @param passLevel `level + 1`, cached by the caller (invariant across the call).
    /// @param quantity Paid passes (1..WHALE_MAX_QUANTITY).
    /// @param totalPrice The canonical quote for `quantity` at these boon terms.
    /// @param freshPaid The msg.value applied to the price (0 for the automatic purchase).
    /// @param hasValidBoon Whether the quote took the boon discount (consumed here).
    /// @param s0 The buyer's packed boon slot-0 word, read with the boon state.
    /// @param affiliateCode Affiliate/referral code (bytes32(0) = stored code / vault default).
    function _deliverWhalePass(
        address buyer,
        uint24 passLevel,
        uint256 quantity,
        uint256 totalPrice,
        uint256 freshPaid,
        bool hasValidBoon,
        uint256 s0,
        bytes32 affiliateCode
    ) private {
        if (hasValidBoon) {
            // Clear whale fields (consumed)
            boonPacked[buyer].slot0 = s0 & BP_WHALE_CLEAR;
        }
        _settleShortfall(buyer, totalPrice - freshPaid, true);
        // Whale-pass ETH-in (any funding source): the full price routes to the pools; the
        // pass lootbox is a pool-funded reward, so its LootBoxBuy must NOT be re-counted.
        emit WhalePassPurchased(buyer, quantity, totalPrice);
        // Coin-presale-box credit accrual: 25% of the committed ETH while presale open.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += totalPrice / 4;
        }

        uint256 prevData = mintPacked_[buyer];

        // Unpack current values
        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );

        // Pass covers 100 levels starting from the next level
        uint24 ticketStartLevel = passLevel;

        // Calculate freeze extension and stat boost (delta-based, no double dipping)
        uint24 targetFrozenLevel = ticketStartLevel + 99;
        uint24 newFrozenLevel = frozenUntilLevel > targetFrozenLevel
            ? frozenUntilLevel
            : targetFrozenLevel;
        uint24 deltaFreeze = newFrozenLevel > frozenUntilLevel
            ? (newFrozenLevel - frozenUntilLevel)
            : 0;
        uint24 levelsToAdd = 100;
        if (levelsToAdd > deltaFreeze) {
            levelsToAdd = deltaFreeze;
        }

        uint24 newLevelCount = levelCount + levelsToAdd;

        // Update mint data
        uint256 data = prevData;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_COUNT_SHIFT,
            BitPackingLib.MASK_24,
            newLevelCount
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.WHALE_PASS_TYPE_SHIFT,
            3,
            3
        ); // 3 = 100-level pass
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );

        // Update mint day
        uint24 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );

        // Front-load the LEVEL mint streak by the same freeze delta (survives pass expiry).
        data = _withPassStreakFrontLoad(
            data,
            ticketStartLevel,
            newFrozenLevel,
            levelsToAdd
        );

        mintPacked_[buyer] = data;
        emit PassActivated(buyer, true, ticketStartLevel, newFrozenLevel, data);

        // Queue entries for the paid passes plus one bonus pass per 5 bought: 20/lvl per pass
        // for bonus levels (passLevel to 9); the standard leg awards 2 half-passes per pass
        // as whole-ticket chunks (strided when odd). ONE aggregate award for the whole
        // quantity — never per pass.
        uint256 awardQty = quantity + quantity / WHALE_BULK_BONUS_DIVISOR;
        uint32 bonusEntries = uint32(WHALE_BONUS_ENTRIES_PER_LEVEL * awardQty);
        uint24 bonusCount = passLevel <= WHALE_BONUS_END_LEVEL
            ? (WHALE_BONUS_END_LEVEL - passLevel + 1)
            : 0;
        if (bonusCount != 0) {
            _queueEntryRange(
                buyer,
                ticketStartLevel,
                bonusCount,
                bonusEntries,
                false
            );
        }
        _queueHalfPassAward(
            buyer,
            ticketStartLevel + bonusCount,
            100 - bonusCount,
            WHALE_HALF_PASSES_PER_PASS * awardQty,
            false
        );

        // Affiliate, fresh 25% at affiliate levels 1-3 / 20% at 4+, halved for
        // bulk buys, and 5% recycle exactly like a
        // normal ticket mint: the fresh portion (freshPaid) at the fresh rate, the
        // claimable/afking-funded remainder at the recycle rate, both frozen at level + 1
        // like the ticket affiliate (score 0, same as tickets). The FLIP basis converts at
        // the pass ticket level's price; the kickback share is credited back to the buyer
        // in one Coinflip write.
        {
            uint256 passPriceWei = PriceLookupLib.priceForLevel(passLevel);
            uint256 kickback;
            if (freshPaid != 0) {
                uint256 freshFlip = (freshPaid * PRICE_COIN_UNIT) / passPriceWei;
                if (quantity >= WHALE_BULK_BONUS_DIVISOR) {
                    // Halve the normal fresh reward, including the buyer's kickback.
                    freshFlip >>= 1;
                }
                kickback = affiliate.payAffiliate(
                    freshFlip,
                    affiliateCode,
                    buyer,
                    passLevel,
                    true,
                    0
                );
            }
            uint256 recycled = totalPrice - freshPaid;
            if (recycled != 0) {
                kickback += affiliate.payAffiliate(
                    (recycled * PRICE_COIN_UNIT) / passPriceWei,
                    affiliateCode,
                    buyer,
                    passLevel,
                    false,
                    0
                );
            }
            if (kickback != 0) coinflip.creditFlip(buyer, kickback);
        }

        _rewardWhalePassDgnrs(buyer, quantity);

        // Split payment: pre-game 70/30, post-game 95/5 (future/next). `level` is invariant
        // across this call (no reachable callee advances it), so the cached `passLevel`
        // (== level + 1) decides the split: passLevel == 1 iff level == 0 (pre-game).
        uint256 nextShare;

        if (passLevel == 1) {
            nextShare = (totalPrice * 3000) / 10_000;
        } else {
            nextShare = (totalPrice * 500) / 10_000;
        }

        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(
                pNext + uint128(nextShare),
                pFuture + uint128(totalPrice - nextShare)
            );
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(
                next + uint128(nextShare),
                future + uint128(totalPrice - nextShare)
            );
        }

        // Lootbox: 10% of price, one box per pass bought
        uint256 lootboxAmount = (totalPrice * WHALE_LOOTBOX_BPS) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount, uint8(quantity));
        // Below level 10 (passLevel == level + 1, invariant across this call) every pass
        // bought banks one Craps day-pass credit on the table's credit-only door.
        if (passLevel <= 10) {
            ICrapsPassCredit(ContractAddresses.CRAPS).creditPasses(
                buyer,
                uint32(quantity),
                0
            );
        }
        _grantSeatCoin(buyer);
    }

    /**
     * @notice Purchase a 10-level lazy pass (direct in-game activation).
     * @dev Available at levels 0-2, x9 (9, 19, 29...; not x99), any x0 (10, 20, 30...), a century
     *      x00 during its purchase phase (blocked once jackpotPhaseFlag is set), or with a valid lazy pass boon.
     *      Can renew when 7 or fewer levels remain on current pass freeze.
     *      - Grants 4 entries (one whole ticket) per level for the next 10 levels (starting at current level + 1).
     *      - Applies the standard 10-level stat boost via _activate10LevelPass.
     *      - Price: flat 0.24 ETH at levels 0-2 (excess buys bonus tickets), sum of per-level
     *        ticket prices across the 10-level window at levels 3+.
     *      - Awards a lootbox equal to 10% of pass value.
     *      - Boon purchases apply the boon's tier discount (10/25/50%) to the payment amount.
     *      - Affiliate: fresh 25% (affiliate levels 1-3, i.e. current level 0-2) or 20% (4+), 5% recycled, of the price
     *        in FLIP, exactly like a ticket mint (kickback share credited back to the buyer).
     * @param buyer The address receiving the pass.
     * @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
     * @custom:reverts OnlyDelegatecall When invoked outside the Game delegatecall context.
     * @custom:reverts InvalidLevelForPass When the level is not 0-2, x9 (excl. x99), any x0, or a century x00 in its purchase phase, and no boon applies.
     * @custom:reverts DeityPassConflict When the buyer already holds a deity pass.
     * @custom:reverts PassNotExpired When an active frozen pass still has 8+ levels remaining.
     */
    function purchaseLazyPass(
        address buyer,
        bytes32 affiliateCode
    ) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value against empty local state.
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (_livenessTriggered()) revert GameOver();
        uint24 currentLevel = level;
        bool hasValidBoon = false;
        BoonPacked storage bpLazy = boonPacked[buyer];
        uint256 s1 = bpLazy.slot1;
        uint8 lazyTier = uint8(s1 >> BP_LAZY_PASS_TIER_SHIFT);
        uint16 boonDiscountBps = _lazyPassTierToBps(lazyTier);
        uint24 boonDay = uint24(s1 >> BP_LAZY_PASS_DAY_SHIFT);
        if (boonDay != 0) {
            uint24 currentDay = _simulatedDayIndex();
            uint24 deityDay = uint24(s1 >> BP_DEITY_LAZY_PASS_DAY_SHIFT);
            if (deityDay != 0 && deityDay != currentDay) {
                bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
                boonDay = 0;
                boonDiscountBps = 0;
            } else if (currentDay <= boonDay + 4) {
                hasValidBoon = true;
            } else {
                bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
                boonDay = 0;
                boonDiscountBps = 0;
            }
        }
        // Purchasable at levels 0-2, x9 (9,19,...; not x99), x0 (10,20,...), a century x00
        // during its purchase phase (!jackpotPhaseFlag) — its x01-x10 window holds no century
        // level and never overruns — or with a boon. Blocked during the x00 jackpot phase.
        if (
            currentLevel > 2 &&
            (currentLevel % 10 != 9 || currentLevel % 100 == 99) &&
            (currentLevel % 10 != 0 ||
                (currentLevel % 100 == 0 && jackpotPhaseFlag)) &&
            !hasValidBoon
        ) revert InvalidLevelForPass();

        // Cap 1: disallow if player has deity pass or active frozen pass
        uint256 prevData = mintPacked_[buyer];
        if (
            prevData >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0
        ) revert DeityPassConflict();
        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        // Allow if 7 or fewer levels remain on freeze (early renewal window)
        if (frozenUntilLevel > currentLevel + 7) revert PassNotExpired();

        uint24 startLevel = currentLevel == 0 ? 1 : currentLevel + 1;
        uint256 baseCost = _lazyPassCost(startLevel);

        // Levels 0-2: flat 0.24 ETH worth of benefits, balance → bonus tickets
        // Boon at 0-2: same benefits, discounted payment
        // Levels 3+: baseCost, boon applies discount to baseCost
        // benefitValue = undiscounted package value; derives totalPrice + the level 0-2 bonus
        // tickets. Presale-box credit, lootbox, and pool splits all scale on totalPrice (paid).
        uint256 totalPrice;
        uint256 benefitValue;
        uint32 bonusEntries;
        // priceForLevel(startLevel) is pure; compute once so both the level-0-2 bonus-entry calc
        // and the affiliate FLIP basis below reuse it (the conditional use below does not dominate
        // the unconditional one, so the optimizer would otherwise recompute it).
        uint256 startLevelPrice = PriceLookupLib.priceForLevel(startLevel);
        if (currentLevel <= 2) {
            benefitValue = 0.24 ether;
            uint256 balance = benefitValue - baseCost;
            if (balance != 0) {
                bonusEntries = uint32((balance * 4) / startLevelPrice);
            }
            if (hasValidBoon) {
                totalPrice =
                    (benefitValue * (10_000 - boonDiscountBps)) /
                    10_000;
            } else {
                totalPrice = benefitValue;
            }
        } else {
            benefitValue = baseCost;
            if (hasValidBoon) {
                totalPrice = (baseCost * (10_000 - boonDiscountBps)) / 10_000;
            } else {
                totalPrice = baseCost;
            }
        }
        if (hasValidBoon) {
            // Clear lazy pass fields (consumed)
            bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
        }
        // Claimable-pay: msg.value first (overpay -> payer's afking), claimable covers the rest.
        uint256 freshPaid = msg.value > totalPrice ? totalPrice : msg.value;
        _creditAfkingValue(msg.sender, msg.value - freshPaid);
        _settleShortfall(buyer, totalPrice - freshPaid, true);
        // Lazy-pass ETH-in (any funding source): the full price routes to the pools; the
        // pass lootbox is a pool-funded reward, so its LootBoxBuy must NOT be re-counted.
        emit LazyPassPurchased(buyer, startLevel, totalPrice);
        // Coin-presale-box credit accrual: 25% of the price paid while presale open.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += totalPrice / 4;
        }

        // Affiliate, fresh 25% at affiliate levels 1-3 / 20% at 4+ (paid at level + 1) and 5% recycle exactly like a
        // normal ticket mint: the fresh portion (freshPaid) at the fresh rate, the
        // claimable/afking-funded remainder at the recycle rate, both frozen at level + 1
        // like the ticket affiliate (score 0, same as tickets). The FLIP basis converts at
        // the pass start level's price; the kickback share is credited back to the buyer
        // in one Coinflip write.
        {
            uint256 passPriceWei = startLevelPrice;
            uint256 kickback;
            if (freshPaid != 0) {
                kickback = affiliate.payAffiliate(
                    (freshPaid * PRICE_COIN_UNIT) / passPriceWei,
                    affiliateCode,
                    buyer,
                    currentLevel + 1,
                    true,
                    0
                );
            }
            uint256 recycled = totalPrice - freshPaid;
            if (recycled != 0) {
                kickback += affiliate.payAffiliate(
                    (recycled * PRICE_COIN_UNIT) / passPriceWei,
                    affiliateCode,
                    buyer,
                    currentLevel + 1,
                    false,
                    0
                );
            }
            if (kickback != 0) coinflip.creditFlip(buyer, kickback);
        }

        _activate10LevelPass(buyer, startLevel, LAZY_PASS_ENTRIES_PER_LEVEL);

        // Queue bonus tickets from flat-price overpayment at early levels
        if (bonusEntries != 0) {
            _queueEntries(buyer, startLevel, bonusEntries, false);
        }

        // Split actual payment into pools (future + next)
        uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
        uint256 nextShare;
        unchecked {
            nextShare = totalPrice - futureShare;
        }
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(
                pNext + uint128(nextShare),
                pFuture + uint128(futureShare)
            );
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(
                next + uint128(nextShare),
                future + uint128(futureShare)
            );
        }

        // Award lootbox as 10% of the price paid
        uint256 lootboxAmount = (totalPrice * LAZY_PASS_LOOTBOX_BPS) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount, 1);
        _grantSeatCoin(buyer);
    }

    /**
     * @notice Purchase a deity pass for a specific symbol.
     * @dev Available before gameOver. One per player, 30 paid plus two genesis passes (one per symbol).
     *      Buyer chooses from available symbols (0-31). Virtual trait-targeted jackpot
     *      entries are computed at resolution time; ordinary perpetual tickets are queued.
     *
     *      Price: 24 + T(n) ETH where n = paid sales, T(n) = n*(n+1)/2, through the
     *      24th paid pass (300 ETH); then double each sale, ending at 19,200 ETH.
     *      Genesis grants do not advance the curve.
     *
     *      Craps award (every deity purchase): below level 10 the lootbox is 5% of price
     *      and the buyer banks one HIGH-ROLLER Craps pass credit; from level 10 the
     *      lootbox is 10% and the credit is one normal day pass.
     *
     *      - Affiliate: no FLIP commission — the conferred whale pass below is the affiliate's
     *        compensation. A supplied code only binds the buyer's referrer (when they have none
     *        yet) so that pass and the DGNRS uplines reach the right address.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 30% next pool, 70% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the pass.
     * @param symbolId Symbol to claim (0-31: Q0 Crypto 0-7, Q1 Zodiac 8-15, Q2 Cards 16-23, Q3 Dice 24-31).
     * @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
     * @custom:reverts OnlyDelegatecall When invoked outside the Game delegatecall context.
     * @custom:reverts RngLocked When an RNG word is locked.
     * @custom:reverts GameOver When the liveness/game-over state is triggered.
     * @custom:reverts InvalidSymbol When symbolId is out of range (>= 32).
     * @custom:reverts SymbolTaken When the symbol is already claimed.
     * @custom:reverts AlreadyOwnsDeityPass When the buyer already owns a deity pass.
     */
    function purchaseDeityPass(
        address buyer,
        uint8 symbolId,
        bytes32 affiliateCode
    ) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value against empty local state.
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (rngLockedFlag) revert RngLocked();
        if (_livenessTriggered()) revert GameOver();
        if (symbolId >= 32) revert InvalidSymbol();
        if (symbolId == VAULT_DEITY_SYMBOL || symbolId == SDGNRS_DEITY_SYMBOL) revert SymbolTaken();
        if (deityBySymbol[symbolId] != address(0)) revert SymbolTaken();
        // Link the buyer's referral before anything reads it, exactly as a ticket mint does:
        // payAffiliate stores the supplied code when the buyer has none yet, and keeps the
        // stored one otherwise. The zero amount takes its no-reward return, so the pass links
        // without paying — the conferred whale pass below stays the affiliate's compensation.
        // A blank code is skipped rather than forwarded: forwarding it would lock an unreferred
        // buyer to the VAULT, which the pass does not do today.
        if (affiliateCode != bytes32(0)) {
            affiliate.payAffiliate(0, affiliateCode, buyer, level + 1, true, 0);
        }
        // One deity per buyer; the shared registration helper sets the ownership bit.
        uint256 mp = mintPacked_[buyer];
        if (mp >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) revert AlreadyOwnsDeityPass();

        uint256 basePrice = _deityPassBasePrice(deityPassSales);

        // Apply discount boon if active (tier 1=10%, 2=20%, 3=35%)
        uint256 totalPrice = basePrice;
        BoonPacked storage bpDeity = boonPacked[buyer];
        uint256 s1Deity = bpDeity.slot1;
        uint8 boonTier = uint8(s1Deity >> BP_DEITY_PASS_TIER_SHIFT);
        if (boonTier != 0) {
            // Check expiry: 4 days for lootbox-rolled, 1 day for deity-granted
            bool expired;
            uint24 deityDay = uint24(s1Deity >> BP_DEITY_DEITY_PASS_DAY_SHIFT);
            if (deityDay != 0) {
                expired = uint24(_simulatedDayIndex()) > deityDay;
            } else {
                uint24 stampDay = uint24(s1Deity >> BP_DEITY_PASS_DAY_SHIFT);
                expired =
                    stampDay > 0 &&
                    uint24(_simulatedDayIndex()) >
                    stampDay + DEITY_PASS_BOON_EXPIRY_DAYS;
            }
            if (!expired) {
                uint16 discountBps = boonTier == 3
                    ? uint16(3500)
                    : (boonTier == 2 ? uint16(2000) : uint16(1000));
                totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
            }
            // Consume boon regardless of expiry — clear deity pass fields
            bpDeity.slot1 = s1Deity & BP_DEITY_PASS_CLEAR;
        }
        // Claimable-pay: msg.value first (overpay -> payer's afking), claimable covers the rest.
        uint256 freshPaid = msg.value > totalPrice ? totalPrice : msg.value;
        _creditAfkingValue(msg.sender, msg.value - freshPaid);
        _settleShortfall(buyer, totalPrice - freshPaid, true);

        uint24 passLevel = level + 1;

        // Record the price paid (caps the early-game-over refund). A buyer holds exactly one deity
        // pass (the HAS_DEITY_PASS guard above blocks a second), so this is a plain assignment.
        deityPassPricePaid[buyer] = uint96(totalPrice);
        // Coin-presale-box credit accrual: 25% of the committed ETH while presale open.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += totalPrice / 4;
        }

        _registerDeity(buyer, symbolId);
        // The next transition extends every deity to level + 100. In the purchase phase
        // passLevel is level + 1, so a 100-level grant ends at level + 100 and the next
        // transition (targeting level + 101) continues it; in the jackpot phase the level
        // is already promoted, passLevel is level + 1 and the next transition targets
        // level + 100 itself, so the grant stops one level short.
        _queueEntryRange(buyer, passLevel, jackpotPhaseFlag ? 99 : 100, DEITY_PERPETUAL_ENTRIES, false);
        ++deityPassSales;

        // DGNRS rewards
        address affiliateAddr = affiliate.getReferrer(buyer);
        address upline;
        address upline2;
        if (affiliateAddr != address(0)) {
            upline = affiliate.getReferrer(affiliateAddr);
            if (upline != address(0)) {
                upline2 = affiliate.getReferrer(upline);
            }
        }
        _rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2, passLevel - 1);

        // The buyer's perpetual ticket range was granted by _registerDeity above.
        // The separate whale pass the
        // purchase confers goes to the deity's affiliate (affiliateAddr is always non-zero —
        // getReferrer defaults to VAULT when the buyer has no real referrer): queued immediately
        // for 100 levels from passLevel (= level + 1), 5/lvl over the level-1-9 bonus window +
        // one whole ticket every 2nd level standard, plus the whale-pass freeze/stat boost.
        uint24 ticketStartLevel = passLevel;
        uint24 bonusCount = passLevel <= WHALE_BONUS_END_LEVEL
            ? (WHALE_BONUS_END_LEVEL - passLevel + 1)
            : 0;
        if (bonusCount != 0) {
            _queueEntryRange(
                affiliateAddr,
                ticketStartLevel,
                bonusCount,
                WHALE_BONUS_ENTRIES_PER_LEVEL,
                false
            );
        }
        _queueHalfPassAward(
            affiliateAddr,
            ticketStartLevel + bonusCount,
            100 - bonusCount,
            WHALE_HALF_PASSES_PER_PASS,
            false
        );
        _applyWhalePassStats(affiliateAddr, ticketStartLevel);

        // Fund distribution: pre-game 70/30, post-game 95/5 (future/next).
        // passLevel == 1 <=> level == 0: level cannot move within the purchase.
        uint256 nextShare;
        if (passLevel == 1) {
            nextShare = (totalPrice * 3000) / 10_000;
        } else {
            nextShare = (totalPrice * 500) / 10_000;
        }
        if (prizePoolFrozen) {
            (uint128 pNext, uint128 pFuture) = _getPendingPools();
            _setPendingPools(
                pNext + uint128(nextShare),
                pFuture + uint128(totalPrice - nextShare)
            );
        } else {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(
                next + uint128(nextShare),
                future + uint128(totalPrice - nextShare)
            );
        }

        // Craps award rides every deity purchase: below level 10 the lootbox drops to 5%
        // and the buyer banks one HIGH-ROLLER pass credit; from level 10 the lootbox is
        // the full 10% and the credit is a normal day pass.
        bool earlyDeity = passLevel <= 10;
        uint256 lootboxAmount = (totalPrice
            * (earlyDeity ? DEITY_EARLY_LOOTBOX_BPS : DEITY_LOOTBOX_BPS)) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount, 1);
        ICrapsPassCredit(ContractAddresses.CRAPS).creditPasses(
            buyer,
            earlyDeity ? 0 : 1,
            earlyDeity ? 1 : 0
        );

        emit DeityPassPurchased(buyer, symbolId, totalPrice, passLevel);
        // Only the buyer takes a seat: the affiliate's pass is conferred by someone else's
        // purchase, so it earns no seat and never competes for the free tranche's last slot.
        // (The affiliate's own pass stats were applied above; only the seat leg is withheld.)
        _grantSeatCoin(buyer);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Shared paid/genesis ownership registration. Callers queue the initial
    ///      range separately so genesis can append both owners in one packed group.
    function _registerDeity(address buyer, uint8 symbolId) private {
        uint256 mp = mintPacked_[buyer];
        if (mp >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) revert AlreadyOwnsDeityPass();
        if (deityBySymbol[symbolId] != address(0)) revert SymbolTaken();
        if (deityPassOwners.length >= 32) revert E();
        uint256 packed = mp | (uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT);
        mintPacked_[buyer] = packed;
        deityBySymbol[symbolId] = buyer;
        deityPassOwners.push(buyer);
        emit MintRecorded(buyer, packed);
        IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId);
    }

    /// @dev Batch both genesis owners for one level. Registry length and packed
    ///      queue lanes commit once; each fresh owner/owed record is one word write.
    ///      Existing purchases and partial queue tails are preserved.
    function _queueGenesisDeities(uint24 lvl, uint24 key) private {
        EntryOwner[] storage owners = lvlEntryOwner[lvl];
        uint256 ownerCount = owners.length;
        uint256 records;
        assembly ("memory-safe") {
            mstore(0, owners.slot)
            records := keccak256(0, 32)
        }
        uint256 lanes;
        uint256 count;
        for (uint256 i; i < 2; ++i) {
            address buyer = i == 0 ? ContractAddresses.VAULT : ContractAddresses.SDGNRS;
            uint80 packed = _entriesOwed(key, buyer);
            if (packed != 0) {
                uint32 owed = uint32(packed >> 8) + DEITY_PERPETUAL_ENTRIES;
                _setEntryOwed(lvl, uint32(packed >> OWNER_IDX_SHIFT),
                    (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(uint8(packed)));
                continue;
            }
            if (ownerCount >= type(uint32).max - 1) revert E();
            uint32 pos = uint32(ownerCount + 1);
            uint256 record = uint256(uint160(buyer)) | (
                ((uint256(pos) << OWNER_IDX_SHIFT) | (uint256(DEITY_PERPETUAL_ENTRIES) << 8)) << 160
            );
            assembly ("memory-safe") { sstore(add(records, ownerCount), record) }
            emit EntryOwnerRegistered(lvl, uint32(ownerCount), buyer);
            ++ownerCount;
            entryOwnerPosition[key][buyer] = pos;
            lanes |= uint256(pos) << (count * 32);
            ++count;
        }
        if (count != 0) {
            assembly ("memory-safe") { sstore(owners.slot, ownerCount) }
            _tqAppendLanes(key, lanes, count);
        }
    }

    /// @dev Compute the total ETH cost of a 10-level lazy pass starting at startLevel.
    ///      Cost equals the sum of per-level ticket prices (one whole ticket, 4 entries, per level).
    function _lazyPassCost(
        uint24 startLevel
    ) private pure returns (uint256 total) {
        for (uint24 i = 0; i < LAZY_PASS_LEVELS; ) {
            total += PriceLookupLib.priceForLevel(startLevel + i);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Distribute the DGNRS minter reward for a whale pass purchase to the buyer: 1% of the
    ///      Whale pool per paid pass, each pass taking 1% of what the previous one left. The
    ///      per-pass recurrence (`remaining -= floor(remaining / 100)`, integer rounding at every
    ///      step) is computed locally from ONE reserve read and paid in ONE pool transfer, so the
    ///      pool and supply land exactly where `quantity` separate 1% transfers would have put
    ///      them, minus the repeated cross-contract calls and writes. A protocol self-award (the
    ///      sDGNRS automatic purchase) burns at the token. Bounded by `WHALE_MAX_QUANTITY`.
    ///      Affiliates are compensated in FLIP by the purchase path (payAffiliate), not DGNRS.
    /// @param buyer The pass purchaser receiving the minter reward.
    /// @param quantity Paid passes bought (1..WHALE_MAX_QUANTITY).
    function _rewardWhalePassDgnrs(address buyer, uint256 quantity) private {
        uint256 whaleReserve = dgnrs.poolBalance(IsDGNRS.Pool.Whale);
        if (whaleReserve == 0) return;
        uint256 remaining = whaleReserve;
        for (uint256 i = 0; i < quantity; ) {
            unchecked {
                // Each step's share is <= remaining, and the product fits: the pool is a
                // bps slice of the 1e30 supply, far below 2^256 / PPM_SCALE.
                remaining -= (remaining * DGNRS_WHALE_MINTER_PPM) / DGNRS_WHALE_REWARD_PPM_SCALE;
                ++i;
            }
        }
        uint256 reward = whaleReserve - remaining;
        if (reward != 0) {
            dgnrs.transferFromPool(IsDGNRS.Pool.Whale, buyer, reward);
        }
    }

    /// @dev Distribute DGNRS rewards for deity pass purchase to buyer and affiliates.
    /// @param buyer The pass purchaser receiving 5% of whale pool.
    /// @param affiliateAddr Direct referrer (receives 0.5% of the unreserved affiliate pool).
    /// @param upline Second-level referrer (receives 0.1% of the unreserved affiliate pool).
    /// @param upline2 Third-level referrer (receives 0.05% of the unreserved affiliate pool).
    /// @param currentLevel Current game level, used to read the level's DGNRS allocation.
    function _rewardDeityPassDgnrs(
        address buyer,
        address affiliateAddr,
        address upline,
        address upline2,
        uint24 currentLevel
    ) private {
        uint256 whaleReserve = dgnrs.poolBalance(
            IsDGNRS.Pool.Whale
        );
        if (whaleReserve != 0) {
            uint256 totalReward = (whaleReserve * DEITY_WHALE_POOL_BPS) /
                10_000;
            if (totalReward != 0) {
                dgnrs.transferFromPool(
                    IsDGNRS.Pool.Whale,
                    buyer,
                    totalReward
                );
            }
        }

        uint256 affiliateReserve = dgnrs.poolBalance(
            IsDGNRS.Pool.Affiliate
        );
        if (affiliateReserve == 0) return;
        // Reserve the outstanding level claim allocation so deity purchases
        // cannot drain tokens owed to affiliate claimants.
        (uint256 allocation, uint256 claimed) = _getLevelDgnrs(currentLevel);
        uint256 reserved = allocation - claimed;
        if (reserved >= affiliateReserve) return;
        affiliateReserve -= reserved;

        if (affiliateAddr != address(0)) {
            uint256 affiliateShare = (affiliateReserve *
                DGNRS_AFFILIATE_DIRECT_DEITY_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (affiliateShare != 0) {
                dgnrs.transferFromPool(
                    IsDGNRS.Pool.Affiliate,
                    affiliateAddr,
                    affiliateShare
                );
            }
        }

        uint256 uplineShare = (affiliateReserve *
            DGNRS_AFFILIATE_UPLINE_DEITY_PPM) / DGNRS_WHALE_REWARD_PPM_SCALE;
        if (upline != address(0) && uplineShare != 0) {
            dgnrs.transferFromPool(
                IsDGNRS.Pool.Affiliate,
                upline,
                uplineShare
            );
        }
        uint256 upline2Share = uplineShare / 2;
        if (upline2 != address(0) && upline2Share != 0) {
            dgnrs.transferFromPool(
                IsDGNRS.Pool.Affiliate,
                upline2,
                upline2Share
            );
        }
    }

    /// @dev Undiscounted deity pass price with `sold` passes already taken: triangular through
    ///      the anchor (23 paid sales = 300 ETH), then doubling from the anchor.
    function _deityPassBasePrice(uint256 sold) private pure returns (uint256) {
        if (sold <= DEITY_DOUBLING_ANCHOR_SOLD) {
            return DEITY_PASS_BASE + (sold * (sold + 1) * 1 ether) / 2;
        }
        return DEITY_DOUBLING_ANCHOR_PRICE << (sold - DEITY_DOUBLING_ANCHOR_SOLD);
    }

    /// @dev Record a pass purchase's lootbox spend as `boxes` custom boxes of equal value.
    function _recordLootboxEntry(
        address buyer,
        uint256 lootboxAmount,
        uint8 boxes
    ) private {
        // Pass-bundled lootbox spend joins the minted-units tally (400 units = one
        // ticket-price), combining with ticket spend for the participation floor.
        _recordLootboxUnits(buyer, lootboxAmount);

        // The boxes themselves are recorded by the Lootbox module — one place owns the order
        // slot's encoding, and boons stay ON for the pass bundle.
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.recordCoverBox.selector,
                buyer,
                lootboxAmount,
                _clampScore(_playerActivityScore(buyer, _effectiveQuestStreak(buyer))),
                level + 1,
                true,
                boxes
            )
        );
        if (!ok) {
            if (data.length == 0) revert E();
            assembly ("memory-safe") {
                revert(add(32, data), mload(data))
            }
        }
    }

    /// @dev Clamp a raw activity score into the cover call's uint16 — a bare cast would wrap
    ///      a large score to a small one. Mirrors the afking cover's guard.
    function _clampScore(uint256 raw) private pure returns (uint16) {
        return raw > type(uint16).max ? type(uint16).max : uint16(raw);
    }


    // =========================================================================
    // Whale Pass Claims
    // =========================================================================

    bytes32 private constant EARLY_BIRD_WHALE_TAG = keccak256("early-bird-whale");
    bytes32 private constant QUADRANT_WHALE_TAG = keccak256("jackpot-quadrant-whale");

    /// @dev Same event as JackpotModule; denominated in half-pass claim units.
    event JackpotWhalePassWin(address indexed winner, uint256 halfPasses, uint8 source);

    /// @notice Nested jackpot award against GAME storage, with deferred delivery.
    /// @dev Early bird supplies half-pass units and never moves pools. A quadrant
    ///      supplies its original ETH budget; whole passes consume at most 25%,
    ///      with the exact cost credited to futurePrizePool. JackpotModule includes
    ///      that spend in its matching current-pool debit, and pays all remaining ETH.
    /// @return spent Award value credited (early bird ignores this return).
    function awardWhalePass(uint24 lvl, uint32 traits, uint256 amount, uint256 randWord, bool earlyBird)
        external returns (uint256 spent)
    {
        uint256 halfPasses = earlyBird ? amount : (amount / (8 * HALF_WHALE_PASS_PRICE)) * 2;
        if (halfPasses == 0) return 0;
        address winner = _drawWhalePassWinner(lvl, traits, randWord, earlyBird);
        if (winner == address(0)) return 0;
        whalePassClaims[winner] += halfPasses;
        spent = halfPasses * HALF_WHALE_PASS_PRICE;
        if (!earlyBird) {
            (uint128 next, uint128 future) = _getPrizePools();
            _setPrizePools(next, future + uint128(spent));
        }
        emit JackpotWhalePassWin(winner, halfPasses, earlyBird ? 4 : 5);
    }

    /// @dev The deity holding a trait's symbol: the symbol id is the trait's quadrant (bits 7..6)
    ///      times eight plus its symbol (bits 2..0) — derived from the trait alone, the same form
    ///      the jackpot's deity lookups use, never from where the trait sits on a board.
    function _deityOfTrait(uint8 trait) private view returns (address) {
        return deityBySymbol[(trait >> 6) * 8 + (trait & 7)];
    }

    /// @dev Fresh recipient from frozen GAME inventory. Early bird supplies the
    ///      official bonus board and prefers eligible gold buckets. Quadrant ETH
    ///      conversion supplies one trait in the low byte and its bucket entropy.
    ///      Both preserve real/deity entry weights and exclude award sizes from seeds.
    function _drawWhalePassWinner(uint24 lvl, uint32 traits, uint256 randWord, bool earlyBird)
        private view returns (address)
    {
        uint256 entropy = EntropyLib.hash4(
            randWord, uint256(earlyBird ? EARLY_BIRD_WHALE_TAG : QUADRANT_WHALE_TAG), dailyIdx, lvl
        );
        uint8 selectedTrait = uint8(traits);
        if (earlyBird) {
            uint256 candidates;
            uint256 count;
            bool goldOnly;
            for (uint8 q; q < 4; ++q) {
                uint8 trait = uint8(traits >> (q * 8));
                address deity = _deityOfTrait(trait);
                if (lvlTraitEntry[lvl][trait].length == 0 && deity == address(0)) continue;
                bool gold = ((trait >> 3) & 7) == 7;
                if (gold && !goldOnly) {
                    candidates = 0;
                    count = 0;
                    goldOnly = true;
                }
                if (gold || !goldOnly) {
                    candidates |= uint256(trait) << (count * 8);
                    ++count;
                }
            }
            if (count == 0) return address(0);
            selectedTrait = uint8(candidates >> ((entropy % count) * 8));
        }
        uint256 len = lvlTraitEntry[lvl][selectedTrait].length;
        address deity = _deityOfTrait(selectedTrait);
        uint256 effectiveLen = len + _deityVirtualCount(selectedTrait, len, deity);
        if (effectiveLen == 0) return address(0);
        // A single recipient needs no packed-word group/cursor. Sample directly
        // over the same real-plus-virtual entries and resolve the packed owner.
        uint256 index = EntropyLib.hash2(entropy, 1) % effectiveLen;
        return index < len ? _bucketOwnerAt(lvl, selectedTrait, index) : deity;
    }

    /// @notice Claim deferred whale pass rewards for a player.
    /// @dev Awards deterministic tickets based on pre-calculated half-pass count.
    ///      Tickets start at current level + 1 to avoid giving tickets for an already-active level.
    /// @param player Player address to claim for.
    /// @custom:reverts NothingToClaim If the player has no pending whale-pass claims.
    function claimWhalePass(address player) external {
        if (_livenessTriggered()) revert GameOver();
        uint256 halfPasses = whalePassClaims[player];
        if (halfPasses == 0) revert NothingToClaim();

        // Clear before awarding to avoid double-claiming
        whalePassClaims[player] = 0;

        // Award the half-passes over 100 levels as whole-ticket (4-entry) chunks:
        // halfPasses/4 tickets on every level, remainder strided (2 half-passes = one
        // ticket every 2nd level, 1 = every 4th). Entries start at level+1 to avoid
        // awarding for an already-active level.
        // Example: 5 half-passes = 4 entries/level + 4 entries every 4th level = 500 entries.
        // Safe: halfPasses fits in uint32 (ETH supply limits prevent overflow)
        uint24 startLevel = level + 1;

        _applyWhalePassStats(player, startLevel);
        emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);
        _queueHalfPassAward(player, startLevel, 100, halfPasses, false);
    }

    /// @dev One-per-address-LIFETIME AFKing seat latch. The seat is a perk of BUYING a
    ///      pass, never of winning or being handed one, so this fires only where an
    ///      address pays for its own pass (whale/lazy/deity purchase). Passes that arrive
    ///      any other way — the whale-pass claim and every `whalePassClaims` feeder behind
    ///      it, and a deity buyer's conferred affiliate pass — mint no seat. The seat
    ///      ARRIVES here: `mintSeatFor` mints it with deterministic default art the holder
    ///      can restyle at any time (setSeatTraits), so no separate claim step stands
    ///      between a purchased pass and its seat. The token silently declines once its
    ///      1,000-seat free tranche is exhausted, so this never brings down a purchase.
    ///
    ///      The `mintPacked_` bit is the ONLY once-per-address guard — the token keeps no
    ///      twin and mints whatever it is handed. So the bit is set BEFORE the call, and
    ///      every call site keeps this last in its function, where no later whole-word
    ///      write to `mintPacked_[who]` can clobber it. Each address consumes its one
    ///      chance exactly once, and every pass purchase after the first pays only the
    ///      bit test — no external call on the repeat path.
    /// @dev Genesis: both protocol wallets already hold the construction seats (serials 1 and 2,
    ///      minted by the AFKing Subscription Token constructor), so latch their game-side
    ///      SEAT_CLAIMED bit here. `_grantSeatCoin` is then a pure bit test for either — no second
    ///      free-tranche seat, and no seat-token call on the sDGNRS automatic purchase's crank path.
    ///      A bit-OR on the word `_registerDeity` just wrote (warm), mirrored to the indexer.
    function _latchConstructionSeat(address who) private {
        uint256 packed = mintPacked_[who] | (uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT);
        mintPacked_[who] = packed;
        emit MintRecorded(who, packed);
    }

    function _grantSeatCoin(address who) private {
        uint256 packed = mintPacked_[who];
        if ((packed >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1 == 0) {
            uint256 seatPacked = packed |
                (uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT);
            mintPacked_[who] = seatPacked;
            emit MintRecorded(who, seatPacked);
            IAFKingSeatMint(ContractAddresses.AFKING_SUB_TOKEN).mintSeatFor(who);
        }
    }
}

/// @dev Minimal interface for the GAME-gated AFKing seat mint.
interface IAFKingSeatMint {
    /// @param to Pass purchaser receiving a free-tranche seat (silent no-op once the
    ///        1,000-seat free tranche is exhausted).
    function mintSeatFor(address to) external;
}

/// @dev Minimal interface for minting deity pass ERC721 tokens.
interface IDegenerusDeityPassMint {
    /// @param to Recipient of the minted deity pass.
    /// @param tokenId Token ID to mint (matches the deity symbol ID).
    function mint(address to, uint256 tokenId) external;
}
