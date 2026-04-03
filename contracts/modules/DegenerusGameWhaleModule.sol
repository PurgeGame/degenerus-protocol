// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

/**
 * @title DegenerusGameWhaleModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling whale bundle, lazy pass, and deity pass purchases.
 * @dev This module is called via delegatecall from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 */
contract DegenerusGameWhaleModule is DegenerusGameMintStreakUtils {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    // error E() — inherited from DegenerusGameStorage
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

    /// @dev 5% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500;

    /// @dev 15% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500;

    /// @dev 25% boost to lootbox value in basis points.
    uint16 private constant LOOTBOX_BOOST_25_BONUS_BPS = 2500;

    /// @dev Maximum lootbox value eligible for boost (10 ETH scaled).
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether;

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

    /// @dev Lazy pass: default discount for boons without stored tier (10%).
    uint16 private constant LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS = 1000;

    /// @dev Lazy pass: split to future pool (matches standard purchase split).
    uint16 private constant LAZY_PASS_TO_FUTURE_BPS = 1000;

    /// @dev Whale bundle early price (levels 0-3).
    uint256 private constant WHALE_BUNDLE_EARLY_PRICE = 2.4 ether;

    /// @dev Whale bundle standard price (levels 4+).
    uint256 private constant WHALE_BUNDLE_STANDARD_PRICE = 4 ether;

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
    uint256 private constant DEITY_PASS_BASE = 24 ether;

    /// @dev Deity pass boon expiry (4 game days, expires at jackpot reset).
    uint48 private constant DEITY_PASS_BOON_EXPIRY_DAYS = 4;

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------

    /**
     * @notice Purchase a 100-level whale bundle.
     * @dev Available at any level. Tickets always start at x1.
     *      - Boosts levelCount by delta between current freeze and new freeze (max 100, no double dipping).
     *      - Queues 40 × quantity bonus tickets/lvl for levels passLevel-10, 2 × quantity standard tickets/lvl for the rest.
     *      - Lootbox: 20% of price (presale), 10% (post-presale).
     *      - Distributes DGNRS rewards to buyer and affiliates.
     *
     *      Price: 2.4 ETH at levels 0-3, 4 ETH at levels 4+, 10/25/50% off standard with boon.
     *
     *      Fund distribution:
     *      - Pre-game (level 0): 30% next pool, 70% future pool
     *      - Post-game (level > 0): 5% next pool, 95% future pool
     * @param buyer The address receiving the bundle.
     * @param quantity Number of bundles to purchase (1-100).
     * @custom:reverts E When gameOver is true.
     * @custom:reverts E When quantity is 0 or exceeds 100.
     * @custom:reverts E When msg.value does not match required price.
     */
    function purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) external payable {
        _purchaseWhaleBundle(buyer, quantity);
    }

    function _purchaseWhaleBundle(address buyer, uint256 quantity) private {
        if (gameOver) revert E();
        uint24 passLevel = level + 1;

        if (quantity == 0 || quantity > 100) revert E();

        // Check for valid whale boon (10/25/50% off standard price)
        bool hasValidBoon = false;
        BoonPacked storage bp = boonPacked[buyer];
        uint256 s0 = bp.slot0;
        uint24 boonDay = uint24(s0 >> BP_WHALE_DAY_SHIFT);
        if (boonDay != 0) {
            uint48 currentDay = _simulatedDayIndex();
            hasValidBoon = uint24(currentDay) <= boonDay + 4;
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

        // Bundle covers 100 levels starting from current level
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

        // Price: boon discount applies to first bundle only,
        //        otherwise 2.4 ETH at levels 0-3, 4 ETH after
        uint256 totalPrice;
        if (hasValidBoon) {
            uint8 wTier = uint8(s0 >> BP_WHALE_TIER_SHIFT);
            uint16 discountBps = _whaleTierToBps(wTier);
            if (discountBps == 0) discountBps = 1000; // Default 10% for legacy boons
            uint256 discountedPrice = (WHALE_BUNDLE_STANDARD_PRICE *
                (10_000 - discountBps)) / 10_000;
            // Clear whale fields (consumed)
            bp.slot0 = s0 & BP_WHALE_CLEAR;
            totalPrice =
                discountedPrice +
                WHALE_BUNDLE_STANDARD_PRICE *
                (quantity - 1);
        } else {
            // x99 levels: minimum 2 bundles (8 ETH) to deter fresh-account century bonus farming
            if (passLevel % 100 == 0 && quantity < 2) revert E();
            uint256 unitPrice = passLevel <= 4
                ? WHALE_BUNDLE_EARLY_PRICE
                : WHALE_BUNDLE_STANDARD_PRICE;
            totalPrice = unitPrice * quantity;
        }

        if (msg.value != totalPrice) revert E();
        _awardEarlybirdDgnrs(buyer, totalPrice, passLevel);

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
            BitPackingLib.WHALE_BUNDLE_TYPE_SHIFT,
            3,
            3
        ); // 3 = 100-level bundle
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );

        // Update mint day
        uint32 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_32
        );

        mintPacked_[buyer] = data;

        // Queue tickets: 40/lvl for bonus levels (passLevel to 10), 2/lvl for the rest
        uint32 bonusTickets = uint32(WHALE_BONUS_TICKETS_PER_LEVEL * quantity);
        uint32 standardTickets = uint32(
            WHALE_STANDARD_TICKETS_PER_LEVEL * quantity
        );
        for (uint24 i = 0; i < 100; ) {
            uint24 lvl = ticketStartLevel + i;
            bool isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL);
            _queueTickets(buyer, lvl, isBonus ? bonusTickets : standardTickets);
            unchecked {
                ++i;
            }
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

        // Lootbox: 20% of price during presale, 10% after
        uint16 whaleLootboxBps = lootboxPresaleActive
            ? WHALE_LOOTBOX_PRESALE_BPS
            : WHALE_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (totalPrice * whaleLootboxBps) / 10_000;
        _recordLootboxEntry(buyer, lootboxAmount, passLevel, data);
    }

    /**
     * @notice Purchase a 10-level lazy pass (direct in-game activation).
     * @dev Available at levels 0-2 or x9 (9, 19, 29... excluding x99), or with a valid lazy pass boon.
     *      Can renew when 7 or fewer levels remain on current pass freeze.
     *      - Grants 4 tickets per level for the next 10 levels (starting at current level + 1).
     *      - Applies the standard 10-level stat boost via _activate10LevelPass.
     *      - Price: flat 0.24 ETH at levels 0-2 (excess buys bonus tickets), sum of per-level
     *        ticket prices across the 10-level window at levels 3+.
     *      - Awards a lootbox equal to 20% (presale) or 10% (post-presale) of pass value.
     *      - Boon purchases apply a discount (default 10%) to the payment amount.
     * @param buyer The address receiving the pass.
     * @custom:reverts E When level is not 0-2 or x9 (excluding x99) and no boon, pass has 8+ levels remaining, or msg.value is incorrect.
     */
    function purchaseLazyPass(address buyer) external payable {
        _purchaseLazyPass(buyer);
    }

    function _purchaseLazyPass(address buyer) private {
        if (gameOver) revert E();
        uint24 currentLevel = level;
        bool hasValidBoon = false;
        BoonPacked storage bpLazy = boonPacked[buyer];
        uint256 s1 = bpLazy.slot1;
        uint8 lazyTier = uint8(s1 >> BP_LAZY_PASS_TIER_SHIFT);
        uint16 boonDiscountBps = _lazyPassTierToBps(lazyTier);
        uint24 boonDay = uint24(s1 >> BP_LAZY_PASS_DAY_SHIFT);
        if (boonDay != 0) {
            uint48 currentDay = _simulatedDayIndex();
            uint24 deityDay = uint24(s1 >> BP_DEITY_LAZY_PASS_DAY_SHIFT);
            if (deityDay != 0 && deityDay != uint24(currentDay)) {
                bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
                boonDay = 0;
                boonDiscountBps = 0;
            } else if (uint24(currentDay) <= boonDay + 4) {
                hasValidBoon = true;
            } else {
                bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
                boonDay = 0;
                boonDiscountBps = 0;
            }
        } else if (lazyTier != 0) {
            // Stale tier with no day -- clear
            bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
            boonDiscountBps = 0;
        }
        if (
            currentLevel > 2 &&
            (currentLevel % 10 != 9 || currentLevel % 100 == 99) &&
            !hasValidBoon
        ) revert E();

        // Cap 1: disallow if player has deity pass or active frozen pass
        uint256 prevData = mintPacked_[buyer];
        if (
            prevData >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0
        ) revert E();
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
            benefitValue = 0.24 ether;
            uint256 balance = benefitValue - baseCost;
            if (balance != 0) {
                uint256 ticketPrice = PriceLookupLib.priceForLevel(startLevel);
                bonusTickets = uint32((balance * 4) / ticketPrice);
            }
            if (hasValidBoon) {
                if (boonDiscountBps == 0) {
                    boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS;
                }
                totalPrice =
                    (benefitValue * (10_000 - boonDiscountBps)) /
                    10_000;
            } else {
                totalPrice = benefitValue;
            }
        } else {
            benefitValue = baseCost;
            if (hasValidBoon) {
                if (boonDiscountBps == 0) {
                    boonDiscountBps = LAZY_PASS_BOON_DEFAULT_DISCOUNT_BPS;
                }
                totalPrice = (baseCost * (10_000 - boonDiscountBps)) / 10_000;
            } else {
                totalPrice = baseCost;
            }
        }
        if (hasValidBoon) {
            // Re-read slot1 in case deity path already cleared, then clear lazy pass fields
            s1 = bpLazy.slot1;
            bpLazy.slot1 = s1 & BP_LAZY_PASS_CLEAR;
        }
        if (msg.value != totalPrice) revert E();

        _awardEarlybirdDgnrs(buyer, benefitValue, startLevel);

        _activate10LevelPass(buyer, startLevel, LAZY_PASS_TICKETS_PER_LEVEL);

        // Queue bonus tickets from flat-price overpayment at early levels
        if (bonusTickets != 0) {
            _queueTickets(buyer, startLevel, bonusTickets);
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

        // Award lootbox as a percentage of pass value (presale 20%, post 10%)
        uint16 lootboxBps = lootboxPresaleActive
            ? LAZY_PASS_LOOTBOX_PRESALE_BPS
            : LAZY_PASS_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (benefitValue * lootboxBps) / 10_000;
        if (lootboxAmount == 0) return;

        _recordLootboxEntry(
            buyer,
            lootboxAmount,
            currentLevel + 1,
            mintPacked_[buyer]
        );
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
     * @custom:reverts E When buyer already owns a deity pass.
     * @custom:reverts E When symbolId is out of range or already taken.
     * @custom:reverts E When msg.value does not match current deity pass price.
     */
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable {
        _purchaseDeityPass(buyer, symbolId);
    }

    function _purchaseDeityPass(address buyer, uint8 symbolId) private {
        if (rngLockedFlag) revert RngLocked();
        if (gameOver) revert E();
        if (symbolId >= 32) revert E();
        if (deityBySymbol[symbolId] != address(0)) revert E();
        if (
            mintPacked_[buyer] >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0
        ) revert E();

        uint256 k = deityPassOwners.length;
        uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;

        // Apply discount boon if active (tier 1=10%, 2=25%, 3=50%)
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
                    ? uint16(5000)
                    : (boonTier == 2 ? uint16(2500) : uint16(1000));
                totalPrice = (basePrice * (10_000 - discountBps)) / 10_000;
            }
            // Consume boon regardless of expiry — clear deity pass fields
            bpDeity.slot1 = s1Deity & BP_DEITY_PASS_CLEAR;
        }
        if (msg.value != totalPrice) revert E();

        uint24 passLevel = level + 1;

        // Issue the pass with symbol
        deityPassPaidTotal[buyer] += totalPrice;
        _awardEarlybirdDgnrs(buyer, totalPrice, passLevel);

        mintPacked_[buyer] = BitPackingLib.setPacked(
            mintPacked_[buyer],
            BitPackingLib.HAS_DEITY_PASS_SHIFT,
            1,
            1
        );
        deityPassPurchasedCount[buyer] += 1;
        deityPassOwners.push(buyer);
        deityPassSymbol[buyer] = symbolId;
        deityBySymbol[symbolId] = buyer;

        // Mint ERC721 token (tokenId = symbolId)
        IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(
            buyer,
            symbolId
        );

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
        uint24 ticketStartLevel = passLevel <= 4
            ? 1
            : uint24(((passLevel + 1) / 50) * 50 + 1);
        for (uint24 i = 0; i < 100; ) {
            uint24 lvl = ticketStartLevel + i;
            bool isBonus = (lvl >= passLevel && lvl <= WHALE_BONUS_END_LEVEL);
            _queueTickets(
                buyer,
                lvl,
                isBonus
                    ? WHALE_BONUS_TICKETS_PER_LEVEL
                    : WHALE_STANDARD_TICKETS_PER_LEVEL
            );
            unchecked {
                ++i;
            }
        }

        // Fund distribution: pre-game 70/30, post-game 95/5 (future/next)
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

        // Lootbox: 20% presale, 10% post
        uint16 deityLootboxBps = lootboxPresaleActive
            ? DEITY_LOOTBOX_PRESALE_BPS
            : DEITY_LOOTBOX_POST_BPS;
        uint256 lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
        if (lootboxAmount != 0) {
            _recordLootboxEntry(
                buyer,
                lootboxAmount,
                passLevel,
                mintPacked_[buyer]
            );
        }

        emit DeityPassPurchased(buyer, symbolId, totalPrice, passLevel);
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
        uint256 whaleReserve = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Whale
        );
        if (whaleReserve != 0) {
            uint256 minterShare = (whaleReserve * DGNRS_WHALE_MINTER_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (minterShare != 0) {
                dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Whale,
                    buyer,
                    minterShare
                );
            }
        }

        uint256 affiliateReserve = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Affiliate
        );
        if (affiliateReserve == 0) return;
        // Reserve the outstanding level claim allocation so whale purchases
        // cannot drain tokens owed to affiliate claimants.
        uint256 reserved = levelDgnrsAllocation[level] -
            levelDgnrsClaimed[level];
        if (reserved >= affiliateReserve) return;
        affiliateReserve -= reserved;

        if (affiliateAddr != address(0)) {
            uint256 affiliateShare = (affiliateReserve *
                DGNRS_AFFILIATE_DIRECT_WHALE_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (affiliateShare != 0) {
                dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Affiliate,
                    affiliateAddr,
                    affiliateShare
                );
            }
        }

        uint256 uplineShare = (affiliateReserve *
            DGNRS_AFFILIATE_UPLINE_WHALE_PPM) / DGNRS_WHALE_REWARD_PPM_SCALE;
        if (upline != address(0) && uplineShare != 0) {
            dgnrs.transferFromPool(
                IStakedDegenerusStonk.Pool.Affiliate,
                upline,
                uplineShare
            );
        }
        uint256 upline2Share = uplineShare / 2;
        if (upline2 != address(0) && upline2Share != 0) {
            dgnrs.transferFromPool(
                IStakedDegenerusStonk.Pool.Affiliate,
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
        uint256 whaleReserve = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Whale
        );
        if (whaleReserve != 0) {
            uint256 totalReward = (whaleReserve * DEITY_WHALE_POOL_BPS) /
                10_000;
            if (totalReward != 0) {
                uint256 paid = dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Whale,
                    buyer,
                    totalReward
                );
                if (paid != 0) {
                    buyerDgnrs = paid > type(uint96).max
                        ? type(uint96).max
                        : uint96(paid);
                }
            }
        }

        uint256 affiliateReserve = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Affiliate
        );
        if (affiliateReserve == 0) return buyerDgnrs;
        // Reserve the outstanding level claim allocation so deity purchases
        // cannot drain tokens owed to affiliate claimants.
        uint256 reserved = levelDgnrsAllocation[level] -
            levelDgnrsClaimed[level];
        if (reserved >= affiliateReserve) return buyerDgnrs;
        affiliateReserve -= reserved;

        if (affiliateAddr != address(0)) {
            uint256 affiliateShare = (affiliateReserve *
                DGNRS_AFFILIATE_DIRECT_DEITY_PPM) /
                DGNRS_WHALE_REWARD_PPM_SCALE;
            if (affiliateShare != 0) {
                dgnrs.transferFromPool(
                    IStakedDegenerusStonk.Pool.Affiliate,
                    affiliateAddr,
                    affiliateShare
                );
            }
        }

        uint256 uplineShare = (affiliateReserve *
            DGNRS_AFFILIATE_UPLINE_DEITY_PPM) / DGNRS_WHALE_REWARD_PPM_SCALE;
        if (upline != address(0) && uplineShare != 0) {
            dgnrs.transferFromPool(
                IStakedDegenerusStonk.Pool.Affiliate,
                upline,
                uplineShare
            );
        }
        uint256 upline2Share = uplineShare / 2;
        if (upline2 != address(0) && upline2Share != 0) {
            dgnrs.transferFromPool(
                IStakedDegenerusStonk.Pool.Affiliate,
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
            lootboxEvScorePacked[index][buyer] = uint16(
                IDegenerusGame(address(this)).playerActivityScore(buyer) + 1
            );
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
        _maybeRequestLootboxRng(lootboxAmount);

        // Track distress-mode portion for proportional ticket bonus at open time
        if (_isDistressMode()) {
            lootboxDistressEth[index][buyer] += boostedAmount;
        }
    }

    /// @dev Accumulate lootbox ETH for pending RNG request.
    /// @param lootboxAmount The lootbox amount to add to pending total.
    function _maybeRequestLootboxRng(uint256 lootboxAmount) private {
        lootboxRngPendingEth += lootboxAmount;
    }

    /// @dev Apply any active lootbox boost boon to the purchase amount.
    ///      Reads packed lootbox tier from boonPacked[player].slot0.
    ///      Boost is capped at LOOTBOX_BOOST_MAX_VALUE (10 ETH) and expires after 2 game days.
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
        BoonPacked storage bp = boonPacked[player];
        uint256 s0 = bp.slot0;
        uint8 tier = uint8(s0 >> BP_LOOTBOX_TIER_SHIFT);
        if (tier == 0) return boostedAmount;

        // Check expiry
        uint24 stampDay = uint24(s0 >> BP_LOOTBOX_DAY_SHIFT);
        if (
            stampDay > 0 && uint24(day) > stampDay + LOOTBOX_BOOST_EXPIRY_DAYS
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

    /// @dev Record the mint day in player's packed data for lootbox tracking.
    /// @param player The player address.
    /// @param day The current day index.
    /// @param cachedPacked The caller's cached mintPacked_ value to avoid a redundant SLOAD.
    function _recordLootboxMintDay(
        address player,
        uint32 day,
        uint256 cachedPacked
    ) private {
        uint32 prevDay = uint32(
            (cachedPacked >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32
        );
        if (prevDay == day) {
            return;
        }
        uint256 clearedDay = cachedPacked &
            ~(BitPackingLib.MASK_32 << BitPackingLib.DAY_SHIFT);
        mintPacked_[player] =
            clearedDay |
            (uint256(day) << BitPackingLib.DAY_SHIFT);
    }

    // =========================================================================
    // Whale Pass Claims
    // =========================================================================

    /// @notice Claim deferred whale pass rewards for a player.
    /// @dev Awards deterministic tickets based on pre-calculated half-pass count.
    ///      Tickets start at current level + 1 to avoid giving tickets for an already-active level.
    /// @param player Player address to claim for.
    function claimWhalePass(address player) external {
        if (gameOver) revert E();
        uint256 halfPasses = whalePassClaims[player];
        if (halfPasses == 0) return;

        // Clear before awarding to avoid double-claiming
        whalePassClaims[player] = 0;

        // Award tickets for 100 levels, with N tickets per level (where N = half-passes)
        // Start level depends on game state:
        // - Jackpot phase: tickets won't be processed this level, start at level+1
        // - Otherwise: tickets can be processed this level, start at current level
        // Example: 3 half-passes = 3 tickets/level x 100 levels = 300 tickets
        // Safe: halfPasses fits in uint32 (ETH supply limits prevent overflow)
        uint24 startLevel = level + 1;

        _applyWhalePassStats(player, startLevel);
        emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);
        _queueTicketRange(player, startLevel, 100, uint32(halfPasses));
    }
}

/// @dev Minimal interface for minting deity pass ERC721 tokens.
interface IDegenerusDeityPassMint {
    /// @param to Recipient of the minted deity pass.
    /// @param tokenId Token ID to mint (matches the deity symbol ID).
    function mint(address to, uint256 tokenId) external;
}
