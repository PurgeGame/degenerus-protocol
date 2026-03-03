// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/**
 * @title DegenerusGameWhaleModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling whale bundle, lazy pass, and deity pass purchases.
 * @dev This module is called via delegatecall from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 */
contract DegenerusGameWhaleModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Reverts on invalid input, unauthorized access, or failed validation.
    error E();

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
        uint48 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    /// @notice Emitted when a player is assigned a new lootbox index for the day.
    /// @param buyer The address receiving the lootbox assignment.
    /// @param index The lootbox RNG index assigned.
    /// @param day The day index of the assignment.
    event LootBoxIndexAssigned(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    /// @dev Affiliate contract for referral tracking.
    IDegenerusAffiliate internal constant affiliate = IDegenerusAffiliate(ContractAddresses.AFFILIATE);

    /// @dev DGNRS token contract for pool rewards.
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);


    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @dev 5% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;

    /// @dev 15% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;

    /// @dev 25% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;

    /// @dev Testnet ETH divisor — scales all ETH prices down by 1M.
    uint256 private constant D = 1_000_000;

    /// @dev Maximum lootbox value eligible for boost (10 ETH scaled).
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether / D;

    /// @dev Lootbox boost expiry duration (2 game days, expires at jackpot reset).
    uint48 private constant LOOTBOX_BOOST_EXPIRY_DAYS = 2;

    /// @dev PPM scale for DGNRS pool calculations (1,000,000 = 100%).
    uint32 private constant DGNRS_WHALE_REWARD_PPM_SCALE = 1_000_000;

    /// @dev Whale bundle minter reward: 1% of whale pool.
    uint32 private constant DGNRS_WHALE_MINTER_PPM = 10_000;

    /// @dev Direct affiliate reward for whale bundle: 0.1% of affiliate pool.
    uint32 private constant DGNRS_AFFILIATE_DIRECT_WHALE_PPM = 1_000;

    /// @dev Upline affiliate reward for whale bundle: 0.02% of affiliate pool.
    uint32 private constant DGNRS_AFFILIATE_UPLINE_WHALE_PPM = 200;

    /// @dev Direct affiliate reward for deity pass: 0.5% of affiliate pool.
    uint32 private constant DGNRS_AFFILIATE_DIRECT_DEITY_PPM = 5_000;

    /// @dev Upline affiliate reward for deity pass: 0.1% of affiliate pool.
    uint32 private constant DGNRS_AFFILIATE_UPLINE_DEITY_PPM = 1_000;

    /// @dev Deity pass buyer reward: 5% of whale pool.
    uint16 private constant DEITY_WHALE_POOL_BPS = 500;

    /// @dev Lazy pass: number of levels covered.
    uint24 private constant LAZY_PASS_LEVELS = 10;

    /// @dev Lazy pass: tickets per level (4 tickets = 1 level).
    uint32 private constant LAZY_PASS_TICKETS_PER_LEVEL = 4;

    /// @dev Lazy pass: share of purchase value awarded as lootbox during presale (20%).
    uint16 private constant LAZY_PASS_LOOTBOX_PRESALE_BPS = 2000;

    /// @dev Lazy pass: share of purchase value awarded as lootbox after presale (10%).
    uint16 private constant LAZY_PASS_LOOTBOX_POST_BPS = 1000;

    /// @dev Lazy pass: default discount for legacy boons without stored tier (10%).
    uint16 private constant LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000;

    /// @dev Lazy pass: split to future pool (matches standard purchase split).
    uint16 private constant LAZY_PASS_TO_FUTURE_BPS = 1000;

    /// @dev Whale bundle early price (levels 0-3).
    uint256 private constant WHALE_BUNDLE_EARLY_PRICE = 2.4 ether / D;

    /// @dev Whale bundle standard price (x49/x99 levels).
    uint256 private constant WHALE_BUNDLE_STANDARD_PRICE = 4 ether / D;

    /// @dev Whale bundle bonus tickets per level for levels up to 10.
    uint32 private constant WHALE_BONUS_TICKETS_PER_LEVEL = 40;

    /// @dev Whale bundle standard tickets per level for levels 11+.
    uint32 private constant WHALE_STANDARD_TICKETS_PER_LEVEL = 2;

    /// @dev Last level eligible for whale bundle bonus tickets.
    uint24 private constant WHALE_BONUS_END_LEVEL = 10;

    /// @dev Whale bundle lootbox share during presale (20%).
    uint16 private constant WHALE_LOOTBOX_PRESALE_BPS = 2000;

    /// @dev Whale bundle lootbox share after presale (10%).
    uint16 private constant WHALE_LOOTBOX_POST_BPS = 1000;

    /// @dev Deity pass lootbox share during presale (20%).
    uint16 private constant DEITY_LOOTBOX_PRESALE_BPS = 2000;

    /// @dev Deity pass lootbox share after presale (10%).
    uint16 private constant DEITY_LOOTBOX_POST_BPS = 1000;

    /// @dev Deity pass base price (24 ETH, unscaled). Actual price = 24 + T(n) where T(n) = n*(n+1)/2, n = passes sold so far.
    uint256 private constant DEITY_PASS_BASE = 24 ether / D;

    /// @dev BURNIE transfer cost for deity pass trade (5 ETH worth, scaled).
    uint256 private constant DEITY_TRANSFER_ETH_COST = 5 ether / D;

    /// @dev Deity pass boon expiry (4 game days, expires at jackpot reset).
    uint48 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------

    /**
     * @notice Purchase a 100-level whale bundle.
     * @dev Available at levels 0-3, x49/x99, or any level with a valid whale boon. Tickets always start at x1.
     *      - Boosts levelCount by delta between current freeze and new freeze (max 100, no double dipping).
     *      - Queues 40 × quantity bonus tickets/lvl for levels passLevel-10, 2 × quantity standard tickets/lvl for the rest.
     *      - Lootbox: 20% of price (presale), 10% (post-presale).
     *      - Distributes DGNRS rewards to buyer and affiliates.
     *
     *      Price: 2.4 ETH at levels 0-3, 4 ETH at x49/x99, 10/25/50% off standard with boon.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 50% next pool, 50% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the bundle.
     * @param quantity Number of bundles to purchase (1-100).
     * @custom:reverts E When not at level 0-3 or x49/x99 and no valid boon exists.
     * @custom:reverts E When quantity is 0 or exceeds 100.
     * @custom:reverts E When msg.value does not match required price.
     */
    function purchaseWhaleBundle(address buyer, uint256 quantity) external payable {
        _purchaseWhaleBundle(buyer, quantity);
    }

    function _purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) private {
        uint24 passLevel = level + 1;

        if (quantity == 0 || quantity > 100) revert E();

        // Check for valid whale boon (10/25/50% off standard price)
        bool hasValidBoon = false;
        uint48 boonDay = whaleBoonDay[buyer];
        if (boonDay != 0) {
            uint48 currentDay = _simulatedDayIndex();
            hasValidBoon = currentDay <= boonDay + 4;
        }

        // TESTNET: whale bundle purchasable at any level (no x49/x99 gate)
        // Without a boon at levels 0-3, use early price; otherwise standard price

        uint256 prevData = mintPacked_[buyer];

        // Unpack current values
        uint24 frozenUntilLevel = uint24((prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
        uint24 levelCount = uint24((prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24);

        // Bundle covers 100 levels starting from current level (levels 0-3 start at 1)
        uint24 ticketStartLevel = passLevel <= 4 ? 1 : passLevel;

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

        // Price: boon applies 10/25/50% off standard price at any level,
        //        otherwise 2.4 ETH at levels 0-3, 4 ETH at all other levels
        uint256 unitPrice;
        if (hasValidBoon) {
            uint16 discountBps = whaleBoonDiscountBps[buyer];
            if (discountBps == 0) discountBps = 1000; // Default 10% for legacy boons
            unitPrice = (WHALE_BUNDLE_STANDARD_PRICE * (10_000 - discountBps)) / 10_000;
            delete whaleBoonDay[buyer];
            delete whaleBoonDiscountBps[buyer];
        } else if (passLevel <= 4) {
            unitPrice = WHALE_BUNDLE_EARLY_PRICE;
        } else {
            unitPrice = WHALE_BUNDLE_STANDARD_PRICE;
        }
        uint256 totalPrice = unitPrice * quantity;

        if (msg.value != totalPrice) revert E();
        _awardEarlybirdDgnrs(buyer, totalPrice, passLevel);

        uint24 newLevelCount = levelCount + levelsToAdd;

        // Update mint data
        uint256 data = prevData;
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_COUNT_SHIFT, BitPackingLib.MASK_24, newLevelCount);
        data = BitPackingLib.setPacked(data, BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT, BitPackingLib.MASK_24, newFrozenLevel);
        data = BitPackingLib.setPacked(data, BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT, 3, 3); // 3 = 100-level bundle
        data = BitPackingLib.setPacked(data, BitPackingLib.LAST_LEVEL_SHIFT, BitPackingLib.MASK_24, newFrozenLevel);

        // Update mint day
        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, BitPackingLib.DAY_SHIFT, BitPackingLib.MASK_32);

        mintPacked_[buyer] = data;

        // Queue tickets: 40/lvl for bonus levels (passLevel to 10), 2/lvl for the rest
        uint32 bonusTickets = uint32(WHALE_BONUS_TICKETS_PER_LEVEL * quantity);
        uint32 standardTickets = uint32(WHALE_STANDARD_TICKETS_PER_LEVEL * quantity);
        for (uint24 i = 0; i < 100; ) {
            uint24 lvl = ticketStartLevel + i;
            bool isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL);
            _queueTickets(buyer, lvl, isBonus ? bonusTickets : standardTickets);
            unchecked { ++i; }
        }

        address affiliateAddr = affiliate.getReferrer(buyer);
        address upline = address(0);
        address upline2 = address(0);
        if (affiliateAddr != address(0)) {
            upline = affiliate.getReferrer(affiliateAddr);
            if (upline != address(0)) {
                upline2 = affiliate.getReferrer(upline);
            }
        }

        for (uint256 i = 0; i < quantity; ) {
            _rewardWhaleBundleDgnrs(buyer, affiliateAddr, upline, upline2);
            unchecked { ++i; }
        }

        // Split payment: pre-game 70/30, post-game 95/5 (future/next)
        uint256 nextShare;

        if (level == 0) {
            nextShare = (totalPrice * 3000) / 10_000;
        } else {
            nextShare = (totalPrice * 500) / 10_000;
        }

        futurePrizePool += totalPrice - nextShare;
        nextPrizePool += nextShare;

        // Lootbox: 20% of price during presale, 10% after
        uint16 whaleLootboxBps = lootboxPresaleActive ? WHALE_LOOTBOX_PRESALE_BPS : WHALE_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (totalPrice * whaleLootboxBps) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount, passLevel, data);
    }

    /**
     * @notice Purchase a 10-level lazy pass (direct in-game activation).
     * @dev Available at levels 0-3 or x9 (9, 19, 29...), or with a valid lazy pass boon.
     *      Can renew when <7 levels remain on current pass freeze.
     *      - Grants 4 tickets per level for the next 10 levels (starting at current level + 1).
     *      - Applies the standard 10-level stat boost via _activate10LevelPass.
     *      - Price equals sum of per-level ticket prices across the 10-level window.
     *      - Awards a lootbox equal to 20% (presale) or 10% (post-presale) of pass value.
     *      - Boon purchases apply a 10/15/25% discount and always include a 10% lootbox.
     * @param buyer The address receiving the pass.
     * @custom:reverts E When level is not 0-3 or x9 and no boon, pass has 7+ levels remaining, or msg.value is incorrect.
     */
    function purchaseLazyPass(address buyer) external payable {
        _purchaseLazyPass(buyer);
    }

    function _purchaseLazyPass(address buyer) private {
        uint24 currentLevel = level;
        bool hasValidBoon = false;
        uint16 boonDiscountBps = lazyPassBoonDiscountBps[buyer];
        uint48 boonDay = lazyPassBoonDay[buyer];
        if (boonDay != 0) {
            uint48 currentDay = _simulatedDayIndex();
            uint48 deityDay = deityLazyPassBoonDay[buyer];
            if (deityDay != 0 && deityDay != currentDay) {
                lazyPassBoonDay[buyer] = 0;
                lazyPassBoonDiscountBps[buyer] = 0;
                deityLazyPassBoonDay[buyer] = 0;
            } else if (currentDay <= boonDay + 4) {
                hasValidBoon = true;
            } else {
                lazyPassBoonDay[buyer] = 0;
                lazyPassBoonDiscountBps[buyer] = 0;
                deityLazyPassBoonDay[buyer] = 0;
            }
        } else if (boonDiscountBps != 0) {
            lazyPassBoonDiscountBps[buyer] = 0;
        }
        if (currentLevel > 2 && currentLevel % 10 != 9 && !hasValidBoon) revert E();

        // Cap 1: disallow if player has deity pass or active frozen pass
        if (deityPassCount[buyer] != 0) revert E();
        uint256 prevData = mintPacked_[buyer];
        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        // Allow if <7 levels remain on freeze (early renewal window)
        if (frozenUntilLevel > currentLevel + 7) revert E();

        uint24 startLevel = currentLevel == 0 ? 1 : currentLevel + 1;
        uint256 baseCost = _lazyPassCost(startLevel);
        if (baseCost == 0) revert E();

        // Levels 0-2: flat 0.24 ETH worth of benefits, balance → bonus tickets
        // Boon at 0-2: same benefits, discounted payment
        // Levels 3+: baseCost, boon applies discount to baseCost
        // benefitValue = undiscounted value used for earlybird/lootbox/pool splits
        uint256 totalPrice;
        uint256 benefitValue;
        uint32 bonusTickets;
        if (currentLevel <= 2) {
            benefitValue = 0.24 ether / D;
            uint256 balance = benefitValue - baseCost;
            if (balance != 0) {
                uint256 ticketPrice = PriceLookupLib.priceForLevel(startLevel);
                bonusTickets = uint32((balance * 4) / ticketPrice);
            }
            if (hasValidBoon) {
                if (boonDiscountBps == 0) {
                    boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS;
                }
                totalPrice = (benefitValue * (10_000 - boonDiscountBps)) / 10_000;
            } else {
                totalPrice = benefitValue;
            }
        } else {
            benefitValue = baseCost;
            if (hasValidBoon) {
                if (boonDiscountBps == 0) {
                    boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS;
                }
                totalPrice =
                    (baseCost * (10_000 - boonDiscountBps)) /
                    10_000;
            } else {
                totalPrice = baseCost;
            }
        }
        if (hasValidBoon) {
            lazyPassBoonDay[buyer] = 0;
            lazyPassBoonDiscountBps[buyer] = 0;
            deityLazyPassBoonDay[buyer] = 0;
        }
        if (msg.value != totalPrice) revert E();

        _awardEarlybirdDgnrs(buyer, benefitValue, startLevel);

        _activate10LevelPass(
            buyer,
            startLevel,
            LAZY_PASS_TICKETS_PER_LEVEL
        );

        // Queue bonus tickets from flat-price overpayment at early levels
        if (bonusTickets != 0) {
            _queueTickets(buyer, startLevel, bonusTickets);
        }

        // Split actual payment into pools (future + next)
        uint256 futureShare = (totalPrice * LAZY_PASS_TO_FUTURE_BPS) / 10_000;
        if (futureShare != 0) {
            futurePrizePool += futureShare;
        }
        uint256 nextShare;
        unchecked {
            nextShare = totalPrice - futureShare;
        }
        if (nextShare != 0) {
            nextPrizePool += nextShare;
        }

        // Award lootbox as a percentage of pass value (presale 20%, post 10%)
        uint16 lootboxBps = lootboxPresaleActive
            ? LAZY_PASS_LOOTBOX_PRESALE_BPS
            : LAZY_PASS_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (benefitValue * lootboxBps) / 10_000;
        if (lootboxAmount == 0) return;

        _recordLootboxEntry(buyer, lootboxAmount, currentLevel + 1, mintPacked_[buyer]);
    }

    /**
     * @notice Purchase a deity pass for a specific symbol.
     * @dev Available at any time. One per player, max 24 total (one per non-dice symbol).
     *      Buyer chooses from available symbols (0-23). Virtual trait-targeted jackpot
     *      entries are computed at resolution time — no explicit ticket queuing needed.
     *
     *      Price: 24 + T(n) ETH where n = passes sold so far, T(n) = n*(n+1)/2.
     *      First pass costs 24 ETH, last (24th) costs 300 ETH.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 50% next pool, 50% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the pass.
     * @param symbolId Symbol to claim (0-23: Q0 Crypto 0-7, Q1 Zodiac 8-15, Q2 Cards 16-23).
     * @custom:reverts E When 24 deity passes have already been issued.
     * @custom:reverts E When buyer already owns a deity pass.
     * @custom:reverts E When symbolId is out of range or already taken.
     * @custom:reverts E When msg.value does not match current deity pass price.
     */
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable {
        _purchaseDeityPass(buyer, symbolId);
    }

    function _purchaseDeityPass(address buyer, uint8 symbolId) private {
        if (symbolId >= 32) revert E();
        if (deityBySymbol[symbolId] != address(0)) revert E();
        if (deityPassCount[buyer] != 0) revert E();

        uint256 k = deityPassOwners.length;
        uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * (1 ether / D)) / 2;

        // Apply discount boon if active (tier 1=10%, 2=25%, 3=50%)
        uint256 totalPrice = basePrice;
        uint8 boonTier = deityPassBoonTier[buyer];
        if (boonTier != 0) {
            // Check expiry: 4 days for lootbox-rolled, 1 day for deity-granted
            bool expired;
            uint48 deityDay = deityDeityPassBoonDay[buyer];
            if (deityDay != 0) {
                expired = _simulatedDayIndex() > deityDay;
            } else {
                uint48 stampDay = deityPassBoonDay[buyer];
                expired = stampDay > 0 && _simulatedDayIndex() > stampDay + DEITY_PASS_BOON_EXPIRY_DAYS;
            }
            if (!expired) {
                uint16 discountBps = boonTier == 3 ? uint16(5000) : (boonTier == 2 ? uint16(2500) : uint16(1000));
                totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
            }
            // Consume boon regardless of expiry
            deityPassBoonTier[buyer] = 0;
            deityPassBoonDay[buyer] = 0;
            deityDeityPassBoonDay[buyer] = 0;
        }
        if (msg.value != totalPrice) revert E();

        uint24 passLevel = level + 1;

        // Issue the pass with symbol
        deityPassPaidTotal[buyer] += totalPrice;
        _awardEarlybirdDgnrs(buyer, totalPrice, passLevel);

        deityPassCount[buyer] = 1;
        deityPassPurchasedCount[buyer] += 1;
        deityPassOwners.push(buyer);
        deityPassSymbol[buyer] = symbolId;
        deityBySymbol[symbolId] = buyer;

        // Mint ERC721 token (tokenId = symbolId)
        IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId);

        // DGNRS rewards
        address affiliateAddr = affiliate.getReferrer(buyer);
        address upline = address(0);
        address upline2 = address(0);
        if (affiliateAddr != address(0)) {
            upline = affiliate.getReferrer(affiliateAddr);
            if (upline != address(0)) {
                upline2 = affiliate.getReferrer(upline);
            }
        }
        _rewardDeityPassDgnrs(buyer, affiliateAddr, upline, upline2);

        // Queue whale-equivalent tickets: 40/lvl bonus (1-10), 2/lvl standard (11-100)
        uint24 ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel + 1) / 50) * 50 + 1);
        for (uint24 i = 0; i < 100; ) {
            uint24 lvl = ticketStartLevel + i;
            bool isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL);
            _queueTickets(buyer, lvl, isBonus ? WHALE_BONUS_TICKETS_PER_LEVEL : WHALE_STANDARD_TICKETS_PER_LEVEL);
            unchecked { ++i; }
        }

        // Refundable if game hasn't started
        if (level == 0 && !gameOver) {
            deityPassRefundable[buyer] += totalPrice;
        }

        // Fund distribution: pre-game 70/30, post-game 95/5 (future/next)
        uint256 nextShare;
        if (level == 0) {
            nextShare = (totalPrice * 3000) / 10_000;
        } else {
            nextShare = (totalPrice * 500) / 10_000;
        }
        nextPrizePool += nextShare;
        futurePrizePool += totalPrice - nextShare;

        // Lootbox: 20% presale, 10% post
        uint16 deityLootboxBps = lootboxPresaleActive ? DEITY_LOOTBOX_PRESALE_BPS : DEITY_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
        if (lootboxAmount != 0) {
            _recordLootboxEntry(buyer, lootboxAmount, passLevel, mintPacked_[buyer]);
        }
    }

    /**
     * @notice Handle deity pass transfer callback from the ERC721 contract.
     * @dev Called via delegatecall from game's onDeityPassTransfer (triggered by ERC721 transfer).
     *      Burns 5 ETH worth of BURNIE from sender. Nukes sender's mint stats and quest streak.
     * @param from The current deity pass holder.
     * @param to The address receiving the pass.
     */
    function handleDeityPassTransfer(address from, address to) external {
        _handleDeityPassTransfer(from, to);
    }

    function _handleDeityPassTransfer(address from, address to) private {
        if (level == 0) revert E();
        if (deityPassCount[from] == 0) revert E();
        if (deityPassCount[to] != 0) revert E();

        // Burn 5 ETH worth of BURNIE from sender
        uint256 burnAmount = (DEITY_TRANSFER_ETH_COST * PRICE_COIN_UNIT) / price;
        IDegenerusCoin(ContractAddresses.COIN).burnCoin(from, burnAmount);

        // Move pass ownership
        uint8 symbolId = deityPassSymbol[from];
        deityBySymbol[symbolId] = to;
        deityPassSymbol[to] = symbolId;
        delete deityPassSymbol[from];

        deityPassCount[to] = 1;
        deityPassCount[from] = 0;

        deityPassPurchasedCount[to] = deityPassPurchasedCount[from];
        deityPassPurchasedCount[from] = 0;
        deityPassPaidTotal[to] = deityPassPaidTotal[from];
        deityPassPaidTotal[from] = 0;

        // Replace sender in owners array
        uint256 len = deityPassOwners.length;
        for (uint256 i; i < len; ) {
            if (deityPassOwners[i] == from) {
                deityPassOwners[i] = to;
                break;
            }
            unchecked { ++i; }
        }

        // Zero refundable (transfer forfeits refund rights)
        deityPassRefundable[from] = 0;

        // Nuke sender stats
        _nukePassHolderStats(from);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    /// @dev Compute the total ETH cost of a 10-level lazy pass starting at startLevel.
    ///      Cost equals the sum of per-level ticket prices (4 tickets per level).
    function _lazyPassCost(uint24 startLevel) private pure returns (uint256 total) {
        for (uint24 i = 0; i < LAZY_PASS_LEVELS; ) {
            total += PriceLookupLib.priceForLevel(startLevel + i);
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Distribute DGNRS rewards for whale bundle purchase to buyer and affiliates.
    /// @param buyer The bundle purchaser receiving minter reward.
    /// @param affiliateAddr Direct referrer (receives 0.1% of affiliate pool).
    /// @param upline Second-level referrer (receives 0.02% of affiliate pool).
    /// @param upline2 Third-level referrer (receives 0.01% of affiliate pool).
    function _rewardWhaleBundleDgnrs(
        address buyer,
        address affiliateAddr,
        address upline,
        address upline2
    ) private {
        uint256 whaleReserve = dgnrs.poolBalance(IDegenerusStonk.Pool.Whale);
        if (whaleReserve != 0) {
            uint256 minterShare = (whaleReserve * DGNRS_WHALE_MINTER_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (minterShare != 0) {
                dgnrs.transferFromPool(
                    IDegenerusStonk.Pool.Whale,
                    buyer,
                    minterShare
                );
            }
        }

        uint256 affiliateReserve = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
        if (affiliateReserve == 0) return;

        if (affiliateAddr != address(0)) {
            uint256 affiliateShare = (affiliateReserve *
                DGNRS_AFFILIATE_DIRECT_WHALE_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (affiliateShare != 0) {
                dgnrs.transferFromPool(
                    IDegenerusStonk.Pool.Affiliate,
                    affiliateAddr,
                    affiliateShare
                );
            }
        }

        uint256 uplineShare = (affiliateReserve * DGNRS_AFFILIATE_UPLINE_WHALE_PPM) /
            DGNRS_WHALE_REWARD_PPM_SCALE;
        if (upline != address(0) && uplineShare != 0) {
            dgnrs.transferFromPool(
                IDegenerusStonk.Pool.Affiliate,
                upline,
                uplineShare
            );
        }
        uint256 upline2Share = uplineShare / 2;
        if (upline2 != address(0) && upline2Share != 0) {
            dgnrs.transferFromPool(
                IDegenerusStonk.Pool.Affiliate,
                upline2,
                upline2Share
            );
        }
    }

    /// @dev Distribute DGNRS rewards for deity pass purchase to buyer and affiliates.
    /// @param buyer The pass purchaser receiving 5% of whale pool.
    /// @param affiliateAddr Direct referrer (receives 0.5% of affiliate pool).
    /// @param upline Second-level referrer (receives 0.1% of affiliate pool).
    /// @param upline2 Third-level referrer (receives 0.05% of affiliate pool).
    /// @return buyerDgnrs The amount of DGNRS transferred to the buyer.
    function _rewardDeityPassDgnrs(
        address buyer,
        address affiliateAddr,
        address upline,
        address upline2
    ) private returns (uint96 buyerDgnrs) {
        uint256 whaleReserve = dgnrs.poolBalance(IDegenerusStonk.Pool.Whale);
        if (whaleReserve != 0) {
            uint256 totalReward = (whaleReserve * DEITY_WHALE_POOL_BPS) / 10_000;
            if (totalReward != 0) {
                uint256 paid = dgnrs.transferFromPool(
                    IDegenerusStonk.Pool.Whale,
                    buyer,
                    totalReward
                );
                if (paid != 0) {
                    buyerDgnrs = paid > type(uint96).max ? type(uint96).max : uint96(paid);
                }
            }
        }

        uint256 affiliateReserve = dgnrs.poolBalance(IDegenerusStonk.Pool.Affiliate);
        if (affiliateReserve == 0) return buyerDgnrs;

        if (affiliateAddr != address(0)) {
            uint256 affiliateShare = (affiliateReserve *
                DGNRS_AFFILIATE_DIRECT_DEITY_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (affiliateShare != 0) {
                dgnrs.transferFromPool(
                    IDegenerusStonk.Pool.Affiliate,
                    affiliateAddr,
                    affiliateShare
                );
            }
        }

        uint256 uplineShare = (affiliateReserve * DGNRS_AFFILIATE_UPLINE_DEITY_PPM) /
            DGNRS_WHALE_REWARD_PPM_SCALE;
        if (upline != address(0) && uplineShare != 0) {
            dgnrs.transferFromPool(
                IDegenerusStonk.Pool.Affiliate,
                upline,
                uplineShare
            );
        }
        uint256 upline2Share = uplineShare / 2;
        if (upline2 != address(0) && upline2Share != 0) {
            dgnrs.transferFromPool(
                IDegenerusStonk.Pool.Affiliate,
                upline2,
                upline2Share
            );
        }
        return buyerDgnrs;
    }

    function _recordLootboxEntry(
        address buyer,
        uint256 lootboxAmount,
        uint24 purchaseLevel,
        uint256 cachedPacked
    ) private {
        uint48 dayIndex = _simulatedDayIndex();
        uint48 index = lootboxRngIndex;

        _recordLootboxMintDay(buyer, uint32(dayIndex), cachedPacked);

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & ((1 << 232) - 1);
        uint48 storedDay = lootboxDay[index][buyer];

        if (existingAmount == 0) {
            lootboxDay[index][buyer] = dayIndex;
            lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);
            lootboxEvScorePacked[index][buyer] =
                uint16(IDegenerusGame(address(this)).playerActivityScore(buyer) + 1);
            lootboxIndexQueue[buyer].push(index);
            emit LootBoxIndexAssigned(buyer, index, dayIndex);
        } else {
            if (storedDay != dayIndex) revert E();
        }

        uint256 boostedAmount = _applyLootboxBoostOnPurchase(
            buyer,
            dayIndex,
            lootboxAmount
        );
        uint256 existingBase = lootboxEthBase[index][buyer];
        if (existingAmount != 0 && existingBase == 0) {
            existingBase = existingAmount;
        }
        lootboxEthBase[index][buyer] = existingBase + lootboxAmount;

        uint256 newAmount = existingAmount + boostedAmount;
        lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
        lootboxEthTotal += lootboxAmount;
        _maybeRequestLootboxRng(lootboxAmount);
    }

    /// @dev Accumulate lootbox ETH for pending RNG request.
    /// @param lootboxAmount The lootbox amount to add to pending total.
    function _maybeRequestLootboxRng(uint256 lootboxAmount) private {
        lootboxRngPendingEth += lootboxAmount;
    }

    /// @dev Apply any active lootbox boost boon to the purchase amount.
    ///      Checks boosts in order: 25% > 15% > 5%. Consumes the first valid boost found.
    ///      Boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH) and expires after 48 hours.
    /// @param player The player whose boost to check and consume.
    /// @param day The current day index for event emission.
    /// @param amount The base lootbox amount before boost.
    /// @return boostedAmount The lootbox amount after applying any boost.
    function _applyLootboxBoostOnPurchase(
        address player,
        uint48 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        uint16 consumedBoostBps = 0;

        uint48 currentDay = _simulatedDayIndex();

        // Check 25% boost first (rarest, best boost)
        bool has25Boost = lootboxBoon25Active[player];
        if (has25Boost) {
            uint48 stampDay = lootboxBoon25Day[player];
            if (stampDay > 0 && currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                has25Boost = false;
                lootboxBoon25Active[player] = false;
            }
        }
        if (has25Boost) {
            uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
            uint256 boost = (cappedAmount * LOOTBOX_BOOST_25_BONUS_BPS) / 10_000;
            boostedAmount += boost;
            consumedBoostBps = LOOTBOX_BOOST_25_BONUS_BPS;
            lootboxBoon25Active[player] = false;
        } else {
            // Check 15% boost next
            bool has15Boost = lootboxBoon15Active[player];
            if (has15Boost) {
                uint48 stampDay = lootboxBoon15Day[player];
                if (stampDay > 0 && currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                    has15Boost = false;
                    lootboxBoon15Active[player] = false;
                }
            }
            if (has15Boost) {
                uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
                uint256 boost = (cappedAmount * LOOTBOX_BOOST_15_BONUS_BPS) / 10_000;
                boostedAmount += boost;
                consumedBoostBps = LOOTBOX_BOOST_15_BONUS_BPS;
                lootboxBoon15Active[player] = false;
            } else {
                // Check 5% boost last
                bool has5Boost = lootboxBoon5Active[player];
                if (has5Boost) {
                    uint48 stampDay = lootboxBoon5Day[player];
                    if (stampDay > 0 && currentDay > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS) {
                        has5Boost = false;
                        lootboxBoon5Active[player] = false;
                    }
                }
                if (has5Boost) {
                    uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
                    uint256 boost = (cappedAmount * LOOTBOX_BOOST_5_BONUS_BPS) / 10_000;
                    boostedAmount += boost;
                    consumedBoostBps = LOOTBOX_BOOST_5_BONUS_BPS;
                    lootboxBoon5Active[player] = false;
                }
            }
        }

        if (consumedBoostBps != 0) {
            emit LootBoxBoostConsumed(player, day, amount, boostedAmount, consumedBoostBps);
        }
    }

    /// @dev Record the mint day in player's packed data for lootbox tracking.
    /// @param player The player address.
    /// @param day The current day index.
    /// @param cachedPacked The caller's cached mintPacked_ value to avoid a redundant SLOAD.
    function _recordLootboxMintDay(address player, uint32 day, uint256 cachedPacked) private {
        uint32 prevDay = uint32((cachedPacked >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32);
        if (prevDay == day) {
            return;
        }
        uint256 clearedDay = cachedPacked & ~(BitPackingLib.MASK_32 << BitPackingLib.DAY_SHIFT);
        mintPacked_[player] = clearedDay | (uint256(day) << BitPackingLib.DAY_SHIFT);
    }

    /// @dev Zero mint stats and quest streak for a player (penalty for deity pass transfer).
    function _nukePassHolderStats(address player) private {
        uint256 data = mintPacked_[player];
        // Zero: LEVEL_COUNT, LEVEL_STREAK, LAST_LEVEL, MINT_STREAK_LAST_COMPLETED
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_COUNT_SHIFT, BitPackingLib.MASK_24, 0);
        data = BitPackingLib.setPacked(data, BitPackingLib.LEVEL_STREAK_SHIFT, BitPackingLib.MASK_24, 0);
        data = BitPackingLib.setPacked(data, BitPackingLib.LAST_LEVEL_SHIFT, BitPackingLib.MASK_24, 0);
        // MINT_STREAK_LAST_COMPLETED is at shift 160 (from MintStreakUtils)
        data = BitPackingLib.setPacked(data, 160, BitPackingLib.MASK_24, 0);
        mintPacked_[player] = data;

        // Reset quest streak via external call to quests contract
        IDegenerusQuestsReset(ContractAddresses.QUESTS).resetQuestStreak(player);
    }
}

/// @dev Minimal interface for quest streak reset (called via delegatecall context as GAME).
interface IDegenerusQuestsReset {
    function resetQuestStreak(address player) external;
}

/// @dev Minimal interface for minting deity pass ERC721 tokens.
interface IDegenerusDeityPassMint {
    function mint(address to, uint256 tokenId) external;
}
