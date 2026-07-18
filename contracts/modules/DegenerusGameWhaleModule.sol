// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

/**
 * @title DegenerusGameWhaleModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling whale pass, lazy pass, and deity pass purchases.
 * @dev This module is called via delegatecall from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 */
contract DegenerusGameWhaleModule is DegenerusGameMintStreakUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
    // error InvalidQuantity() — inherited from DegenerusGameMintStreakUtils
    error MinQuantityRequired(); // At a century milestone level (passLevel % 100 == 0) at least two whale passes must be purchased.
    error InvalidLevelForPass(); // Current game level is not eligible for a lazy pass purchase (not level 0-2, x9, x0, or an unlocked century) and the caller has no valid lazy pass boon.
    error DeityPassConflict(); // Buyer already holds a deity pass, which is incompatible with purchasing a lazy pass.
    error PassNotExpired(); // The player's existing frozen pass has more than 7 levels remaining and is not yet eligible for early renewal.
    error InvalidSymbol(); // Symbol ID is out of the valid range (must be 0-31).
    error SymbolTaken(); // The requested deity symbol has already been claimed by another buyer.
    error AlreadyOwnsDeityPass(); // The buyer already holds a deity pass; only one per address is permitted.
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
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether;

    /// @dev Lootbox boost expiry duration (2 game days, expires at jackpot reset).
    uint32 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

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

    /// @dev Whale pass bonus entries per level for levels up to 10.
    uint32 private constant WHALE_BONUS_ENTRIES_PER_LEVEL = 40;

    /// @dev Half-passes per whale pass (1 half-pass = 1 entry/level equivalent); the
    ///      standard leg awards these as whole-ticket chunks via _queueHalfPassAward.
    uint256 private constant WHALE_HALF_PASSES_PER_PASS = 2;

    /// @dev Last level eligible for whale pass bonus entries.
    uint24 private constant WHALE_BONUS_END_LEVEL = 10;

    /// @dev Whale pass lootbox share (10%).
    uint16 private constant WHALE_LOOTBOX_BPS = 1000;

    /// @dev Deity pass lootbox share (10%).
    uint16 private constant DEITY_LOOTBOX_BPS = 1000;

    /// @dev Deity pass base price (24 ETH, unscaled). Actual price = 24 + T(n) where T(n) = n*(n+1)/2, n = passes sold so far.
    uint256 private constant DEITY_PASS_BASE = 24 ether;

    /// @dev Deity pass boon expiry (4 game days, expires at jackpot reset).
    uint32 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------

    /**
     * @notice Purchase a 100-level whale pass.
     * @dev Available at any level. Tickets always start at x1.
     *      - Boosts levelCount by delta between current freeze and new freeze (max 100, no double dipping).
     *      - Queues 40 × quantity bonus entries/lvl for levels passLevel-10; the rest of the span
     *        is awarded as whole tickets (4 entries each): quantity/2 tickets on every level, plus
     *        one ticket every 2nd level when quantity is odd (1 pass = 1 whole ticket per 2 levels).
     *      - Lootbox: 10% of price.
     *      - Distributes DGNRS minter rewards to the buyer.
     *      - Affiliate: 20% fresh / 5% recycled of the price in FLIP, exactly like a ticket mint
     *        (kickback share credited back to the buyer).
     *
     *      Price: 2.4 ETH at levels 0-3, 4 ETH at levels 4+, 10/25/50% off standard with boon.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 30% next pool, 70% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the pass.
     * @param quantity Number of passes to purchase (1-100).
     * @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
     * @custom:reverts GameOver When gameOver is true.
     * @custom:reverts InvalidQuantity When quantity is 0 or exceeds 100.
     * @custom:reverts MinQuantityRequired When a century (x00) pass level is purchased with quantity < 2.
     */
    function purchaseWhalePass(
        address buyer,
        uint256 quantity,
        bytes32 affiliateCode
    ) external payable {
        if (_livenessTriggered()) revert GameOver();
        uint24 passLevel = level + 1;

        if (quantity == 0 || quantity > 100) revert InvalidQuantity();

        // Check for valid whale boon (10/25/50% off standard price)
        bool hasValidBoon = false;
        BoonPacked storage bp = boonPacked[buyer];
        uint256 s0 = bp.slot0;
        uint24 boonDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        if (boonDay != 0) {
            uint24 currentDay = _simulatedDayIndex();
            // Deity-granted boons are valid only on the grant day; lootbox-rolled
            // keep the 4-day window (mirrors the BoonModule/deity-pass siblings).
            uint24 deityWhaleDay = uint24(s0 >> BP_DEITY_WHALE_DAY_SHIFT);
            hasValidBoon = deityWhaleDay != 0
                ? deityWhaleDay == currentDay
                : currentDay <= boonDay + 4;
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

        // Pass covers 100 levels starting from current level
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

        // Price: boon discount applies to first pass only,
        //        otherwise 2.4 ETH at levels 0-3, 4 ETH after
        uint256 totalPrice;
        if (hasValidBoon) {
            uint8 wTier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
            uint16 discountBps = _whaleTierToBps(wTier);
            uint256 discountedPrice = (WHALE_PASS_STANDARD_PRICE *
                (10_000 - discountBps)) / 10_000;
            // Clear whale fields (consumed)
            bp.slot0 = s0 & BP_WHALE_CLEAR;
            totalPrice =
                discountedPrice +
                WHALE_PASS_STANDARD_PRICE *
                (quantity - 1);
        } else {
            // x99 levels: minimum 2 passes (8 ETH) to deter fresh-account century bonus farming
            if (passLevel % 100 == 0 && quantity < 2) revert MinQuantityRequired();
            uint256 unitPrice = passLevel <= 4
                ? WHALE_PASS_EARLY_PRICE
                : WHALE_PASS_STANDARD_PRICE;
            totalPrice = unitPrice * quantity;
        }

        // Claimable-pay: msg.value first (overpay -> payer's afking), claimable covers the rest.
        uint256 freshPaid = msg.value > totalPrice ? totalPrice : msg.value;
        _creditAfkingValue(msg.sender, msg.value - freshPaid);
        _settleShortfall(buyer, totalPrice - freshPaid, true);
        // Whale-pass ETH-in (any funding source): the full price routes to the pools; the
        // pass lootbox is a pool-funded reward, so its LootBoxBuy must NOT be re-counted.
        emit WhalePassPurchased(buyer, quantity, totalPrice);
        // Coin-presale-box credit accrual: 25% of the committed ETH while presale open.
        if (!presaleOver) {
            presaleBoxCredit[buyer] += totalPrice / 4;
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

        // Queue entries: 40*quantity/lvl for bonus levels (passLevel to 10); the standard
        // leg awards 2*quantity half-passes as whole-ticket chunks (strided when odd).
        uint32 bonusEntries = uint32(WHALE_BONUS_ENTRIES_PER_LEVEL * quantity);
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
            WHALE_HALF_PASSES_PER_PASS * quantity,
            false
        );

        // Affiliate, 20% fresh / 5% recycle exactly like a normal ticket mint: the fresh
        // portion (freshPaid) at the fresh rate, the claimable/afking-funded remainder at
        // the recycle rate, both frozen at level + 1 like the ticket affiliate (score 0,
        // same as tickets). The FLIP basis converts at the pass ticket level's price; the
        // kickback share is credited back to the buyer in one Coinflip write.
        {
            uint256 passPriceWei = PriceLookupLib.priceForLevel(passLevel);
            uint256 kickback;
            if (freshPaid != 0) {
                kickback = affiliate.payAffiliate(
                    (freshPaid * PRICE_COIN_UNIT) / passPriceWei,
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

        for (uint256 i = 0; i < quantity; ) {
            _rewardWhalePassDgnrs(buyer);
            unchecked {
                ++i;
            }
        }

        // Split payment: pre-game 70/30, post-game 95/5 (future/next)
        uint256 nextShare;

        if (level == 0) {
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

        // Lootbox: 10% of price
        uint256 lootboxAmount = (totalPrice * WHALE_LOOTBOX_BPS) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount);
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
     *      - Affiliate: 20% fresh / 5% recycled of the price in FLIP, exactly like a ticket mint
     *        (kickback share credited back to the buyer).
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
        // Allow if <7 levels remain on freeze (early renewal window)
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
        if (currentLevel <= 2) {
            benefitValue = 0.24 ether;
            uint256 balance = benefitValue - baseCost;
            if (balance != 0) {
                uint256 ticketPrice = PriceLookupLib.priceForLevel(startLevel);
                bonusEntries = uint32((balance * 4) / ticketPrice);
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

        // Affiliate, 20% fresh / 5% recycle exactly like a normal ticket mint: the fresh
        // portion (freshPaid) at the fresh rate, the claimable/afking-funded remainder at
        // the recycle rate, both frozen at level + 1 like the ticket affiliate (score 0,
        // same as tickets). The FLIP basis converts at the pass start level's price; the
        // kickback share is credited back to the buyer in one Coinflip write.
        {
            uint256 passPriceWei = PriceLookupLib.priceForLevel(startLevel);
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
        _recordLootboxEntry(buyer, lootboxAmount);
        _grantSeatCoin(buyer);
    }

    /**
     * @notice Purchase a deity pass for a specific symbol.
     * @dev Available before gameOver. One per player, up to 32 total (one per symbol).
     *      Buyer chooses from available symbols (0-31). Virtual trait-targeted jackpot
     *      entries are computed at resolution time — no explicit ticket queuing needed.
     *
     *      Price: 24 + T(n) ETH where n = passes sold so far, T(n) = n*(n+1)/2.
     *      First pass costs 24 ETH, last (32nd) costs 520 ETH.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 30% next pool, 70% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the pass.
     * @param symbolId Symbol to claim (0-31: Q0 Crypto 0-7, Q1 Zodiac 8-15, Q2 Cards 16-23, Q3 Dice 24-31).
     * @custom:reverts OnlyDelegatecall When invoked outside the Game delegatecall context.
     * @custom:reverts RngLocked When an RNG word is locked.
     * @custom:reverts GameOver When the liveness/game-over state is triggered.
     * @custom:reverts InvalidSymbol When symbolId is out of range (>= 32).
     * @custom:reverts SymbolTaken When the symbol is already claimed.
     * @custom:reverts AlreadyOwnsDeityPass When the buyer already owns a deity pass.
     */
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable {
        // Delegatecall-only: address(this) == GAME under the nested dispatch. A direct call on the
        // deployed module would trap the in-flight msg.value against empty local state.
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        if (rngLockedFlag) revert RngLocked();
        if (_livenessTriggered()) revert GameOver();
        if (symbolId >= 32) revert InvalidSymbol();
        if (deityBySymbol[symbolId] != address(0)) revert SymbolTaken();
        // mintPacked_[buyer] is read once and reused for the deity-bit set below — nothing
        // between here and that write touches mintPacked_ or makes an external call.
        uint256 mp = mintPacked_[buyer];
        if (mp >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) revert AlreadyOwnsDeityPass();

        uint256 k = deityPassOwners.length;
        uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;

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

        mintPacked_[buyer] = BitPackingLib.setPacked(
            mp,
            BitPackingLib.HAS_DEITY_PASS_SHIFT,
            1,
            1
        );
        deityPassOwners.push(buyer);
        deityBySymbol[symbolId] = buyer;

        // Mint ERC721 token (tokenId = symbolId)
        IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(
            buyer,
            symbolId
        );

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
        _rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2);

        // The deity buyer's OWN jackpot benefit is the virtual symbol-bucket entries
        // (JackpotModule via deityBySymbol) — they get NO queued tickets. The whale pass the
        // purchase confers goes to the deity's affiliate (affiliateAddr is always non-zero —
        // getReferrer defaults to VAULT when the buyer has no real referrer): queued immediately
        // for 100 levels from passLevel (= level + 1), 40/lvl over the level-1-10 bonus window +
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
        _grantSeatCoin(affiliateAddr);

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

        // Lootbox: 10% of price
        uint256 lootboxAmount = (totalPrice * DEITY_LOOTBOX_BPS) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount);

        emit DeityPassPurchased(buyer, symbolId, totalPrice, passLevel);
        _grantSeatCoin(buyer);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Compute the total ETH cost of a 10-level lazy pass starting at startLevel.
    ///      Cost equals the sum of per-level ticket prices (4 tickets per level).
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

    /// @dev Distribute the DGNRS minter reward for a whale pass purchase to the buyer.
    ///      Affiliates are compensated in FLIP by the purchase path (payAffiliate), not DGNRS.
    /// @param buyer The pass purchaser receiving the minter reward (1% of the Whale pool).
    function _rewardWhalePassDgnrs(address buyer) private {
        uint256 whaleReserve = dgnrs.poolBalance(
            IsDGNRS.Pool.Whale
        );
        if (whaleReserve != 0) {
            uint256 minterShare = (whaleReserve * DGNRS_WHALE_MINTER_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (minterShare != 0) {
                dgnrs.transferFromPool(
                    IsDGNRS.Pool.Whale,
                    buyer,
                    minterShare
                );
            }
        }
    }

    /// @dev Distribute DGNRS rewards for deity pass purchase to buyer and affiliates.
    /// @param buyer The pass purchaser receiving 5% of whale pool.
    /// @param affiliateAddr Direct referrer (receives 0.5% of the unreserved affiliate pool).
    /// @param upline Second-level referrer (receives 0.1% of the unreserved affiliate pool).
    /// @param upline2 Third-level referrer (receives 0.05% of the unreserved affiliate pool).
    function _rewardDeityPassDgnrs(
        address buyer,
        address affiliateAddr,
        address upline,
        address upline2
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
        (uint256 allocation, uint256 claimed) = _getLevelDgnrs(level);
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

    function _recordLootboxEntry(
        address buyer,
        uint256 lootboxAmount
    ) private {
        // Single read of lootboxRngPacked: nothing below writes the slot (the units
        // recorder writes mintPacked_, the boost writes boonPacked, the box enqueue
        // writes boxPlayers, the score read only staticcalls quests), so the pending-eth
        // update at the end is rebuilt from this cached word.
        uint256 lr = lootboxRngPacked;
        uint48 index = uint48((lr >> LR_INDEX_SHIFT) & LR_INDEX_MASK);
        uint24 capKey = level + 1; // resolver open level == the per-(player, level) cap key

        // Pass-bundled lootbox spend joins the minted-units tally (400 units = one
        // ticket-price), combining with ticket spend for the participation floor.
        _recordLootboxUnits(buyer, lootboxAmount);

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & LB_AMOUNT_MASK;

        uint16 score;
        uint64 adj;
        if (existingAmount == 0) {
            // Purchase-time EV-cap tally (first deposit). The score is snapshotted
            // inline (DIV-2) and the multiplier frozen from it; the cap key is
            // level + 1 (== the resolver's currentLevel = level + 1). A bonus box
            // (mult > NEUTRAL) draws add = min(deposit, CAP - used) from the shared
            // per-(player, level) accumulator; sub-neutral/neutral boxes draw zero cap.
            uint256 activityScore = _playerActivityScore(
                buyer,
                _effectiveQuestStreak(buyer)
            );
            score = uint16(activityScore);
            uint256 mult = _lootboxEvMultiplierFromScore(activityScore);
            if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                uint256 used = _lootboxEvUsedFor(buyer, capKey);
                uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                    ? 0
                    : LOOTBOX_EV_BENEFIT_CAP - used;
                uint256 add = lootboxAmount < remaining ? lootboxAmount : remaining;
                _setLootboxEvUsedFor(buyer, capKey, used + add);
                adj = uint64(add);
            }
            // First deposit for this (index, buyer): enqueue for the permissionless
            // box auto-open cursor, exactly like the human-mint and afking-cover box
            // paths. Without it a pass-bundled lootbox never auto-opens, letting the
            // sole opener (manual openBox is operator-gated) hold the box and time
            // the open against the known per-index word. The consumer gates each index
            // on lootboxRngWordByIndex != 0, so this is producer-only.
            boxPlayers[index].push(buyer);
        } else {
            // Subsequent deposit: the frozen score and accumulated adj come from the box's
            // prior packed word; the multiplier stays FROZEN from the first-deposit snapshot.
            (, uint64 priorAdj, uint16 priorScore, ) = _unpackLootbox(packed);
            score = priorScore;
            adj = priorAdj;
            uint256 mult = _lootboxEvMultiplierFromScore(uint256(priorScore));
            if (mult > LOOTBOX_EV_NEUTRAL_BPS) {
                uint256 used = _lootboxEvUsedFor(buyer, capKey);
                uint256 remaining = used >= LOOTBOX_EV_BENEFIT_CAP
                    ? 0
                    : LOOTBOX_EV_BENEFIT_CAP - used;
                uint256 add = lootboxAmount < remaining ? lootboxAmount : remaining;
                if (add != 0) {
                    _setLootboxEvUsedFor(buyer, capKey, used + add);
                    adj = priorAdj + uint64(add);
                }
            }
        }
        // Subsequent deposits accumulate onto the existing box — no day-coherence gate and no stored
        // day (the box binds to lootboxRngWordByIndex[index] and rolls from the LIVE open level, so
        // cross-day deposits at an un-advanced index are harmless).

        uint256 boostedAmount = _applyLootboxBoostOnPurchase(buyer, lootboxAmount);
        uint256 newAmount = existingAmount + boostedAmount;
        uint256 pendingEth = ((lr >> LR_PENDING_ETH_SHIFT) & LR_PENDING_ETH_MASK) +
            _packEthToMilliEth(lootboxAmount);
        lootboxRngPacked =
            (lr & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)) |
            ((pendingEth & LR_PENDING_ETH_MASK) << LR_PENDING_ETH_SHIFT);

        // Track distress-mode portion (0.01-ETH granularity) for the proportional ticket bonus
        // at open time; it rides in the same packed slot, accumulated per-deposit.
        uint256 distressUnits = (packed >> LB_DISTRESS_SHIFT) & LB_DISTRESS_MASK;
        if (_isDistressMode()) {
            distressUnits += boostedAmount / LB_DISTRESS_SCALE;
        }

        lootboxEth[index][buyer] = _packLootbox(newAmount, adj, score, distressUnits);

        // One box-buy event across paths (same topic as the mint module's LootBoxBuy), on every
        // deposit.
        emit LootBoxBuy(buyer, index, lootboxAmount);
    }

    /// @dev Apply any active lootbox boost boon to the purchase amount.
    ///      Reads packed lootbox tier from boonPacked[player].slot0. The purchase day is read
    ///      in-function (only on the boost path) for the expiry check.
    ///      Boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH) and expires after 2 game days.
    /// @param player The player whose boost to check and consume.
    /// @param amount The base lootbox amount before boost.
    /// @return boostedAmount The lootbox amount after applying any boost.
    function _applyLootboxBoostOnPurchase(
        address player,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return boostedAmount;

        // The purchase day (== the buy is happening now) — read here, only on the boost path.
        uint24 day = _simulatedDayIndex();
        // Deity-granted boosts are valid only on the grant day.
        uint24 deityDay = uint24(s0 >> BP_DEITY_LOOTBOX_DAY_SHIFT);
        if (deityDay != 0 && deityDay != day) {
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return boostedAmount;
        }
        // Check expiry
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (
            stampDay > 0 && day > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS
        ) {
            // Expired: clear lootbox fields
            bp.slot0 = s0 & BP_LOOTBOX_CLEAR;
            return boostedAmount;
        }

        // Apply boost
        uint16 boostBps = _lootboxTierToBps(tier);
        uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE
            ? LOOTBOX_BOOST_MAX_VALUE
            : amount;
        uint256 boost = (cappedAmount * boostBps) / 10_000;
        boostedAmount += boost;

        // Clear lootbox fields (consumed)
        bp.slot0 = s0 & BP_LOOTBOX_CLEAR;

        emit LootBoxBoostConsumed(player, day, amount, boostedAmount, boostBps);
    }

    // =========================================================================
    // Whale Pass Claims
    // =========================================================================

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
        _grantSeatCoin(player);
    }

    /// @dev One-per-address-LIFETIME AFKing seat eligibility latch, fired on
    ///      every pass acquisition through this module (whale/lazy/deity
    ///      purchase, the deity purchase's conferred affiliate pass, and the
    ///      whale-pass claim). Latch-only — no external call: the AFKing Subscription Token reads the
    ///      `mintPacked_` SEAT_CLAIMED bit through the game's mintPackedFor
    ///      view when the buyer claims their seat (claimSeat, buyer-chosen
    ///      traits), and the token caps free claims at 1,000 on its side.
    ///      The bit stays set even once the free tranche is exhausted, so
    ///      each address consumes its one chance exactly once and every
    ///      pass acquisition after the first pays only this bit test.
    function _grantSeatCoin(address who) private {
        uint256 packed = mintPacked_[who];
        if ((packed >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1 == 0) {
            mintPacked_[who] =
                packed |
                (uint256(1) << BitPackingLib.SEAT_CLAIMED_SHIFT);
        }
    }
}

/// @dev Minimal interface for minting deity pass ERC721 tokens.
interface IDegenerusDeityPassMint {
    /// @param to Recipient of the minted deity pass.
    /// @param tokenId Token ID to mint (matches the deity symbol ID).
    function mint(address to, uint256 tokenId) external;
}