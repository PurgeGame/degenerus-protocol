// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusStonk} from "../interfaces/IDegenerusStonk.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusTrophies} from "../interfaces/IDegenerusTrophies.sol";
import {IDegenerusLazyPass} from "../interfaces/IDegenerusLazyPass.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

/**
 * @title DegenerusGameWhaleModule
 * @author Burnie Degenerus
 * @notice Delegate-called module handling whale bundle purchases.
 *
 * @dev This module is called via delegatecall from DegenerusGame, meaning all storage
 *      reads/writes operate on the game contract's storage.
 */
contract DegenerusGameWhaleModule is DegenerusGameStorage {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Generic revert for invalid values.
    error E();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LootBoxBoostConsumed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );
    event LootBoxIndexAssigned(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );

    // -------------------------------------------------------------------------
    // External Contract References (compile-time constants)
    // -------------------------------------------------------------------------

    IDegenerusAffiliate internal constant affiliate = IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IDegenerusStonk internal constant dgnrs = IDegenerusStonk(ContractAddresses.DGNRS);
    IDegenerusTrophies internal constant trophies =
        IDegenerusTrophies(ContractAddresses.TROPHIES);
    IDegenerusLazyPass internal constant lazyPass =
        IDegenerusLazyPass(ContractAddresses.LAZY_PASS);

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    /// @notice Time offset for day calculation (matches game's jackpot reset time).
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    /// @dev Sentinel value for levelStartTime indicating "not started".
    uint48 private constant LEVEL_START_SENTINEL = type(uint48).max;

    /// @dev Lootbox boost boons: enhance next lootbox value.
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500; // 5% boost to lootbox value
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500; // 15% boost to lootbox value
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether / ContractAddresses.COST_DIVISOR; // Max 10 ETH lootbox
    uint48 private constant LOOTBOX_BOOST_EXPIRY_SECONDS = 172800; // 2 days (48 hours)
    uint32 private constant LOOTBOX_VRF_CALLBACK_GAS_LIMIT = 200_000;
    uint16 private constant LOOTBOX_VRF_REQUEST_CONFIRMATIONS = 10;

    /// @dev DGNRS pool distribution (ppm of remaining pool).
    uint32 private constant DGNRS_WHALE_REWARD_PPM_SCALE = 1_000_000;
    uint32 private constant DGNRS_WHALE_MINTER_PPM = 10_000; // 1%
    uint32 private constant DGNRS_AFFILIATE_DIRECT_WHALE_PPM = 1_000; // 0.1%
    uint32 private constant DGNRS_AFFILIATE_UPLINE_WHALE_PPM = 200; // 0.02%
    uint32 private constant DGNRS_AFFILIATE_DIRECT_DEITY_PPM = 5_000; // 0.5%
    uint32 private constant DGNRS_AFFILIATE_UPLINE_DEITY_PPM = 1_000; // 0.1%
    uint16 private constant DEITY_WHALE_POOL_BPS = 500; // 5%

    /// @dev Fixed whale pass price used for jackpot EV calculations.
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE = 3.4 ether / ContractAddresses.COST_DIVISOR;

    /// @dev Deity pass price and bundled perks.
    uint256 private constant DEITY_PASS_PRICE = 25 ether / ContractAddresses.COST_DIVISOR;
    uint256 private constant DEITY_PASS_LOOTBOX = 5 ether / ContractAddresses.COST_DIVISOR;
    uint16 private constant DEITY_PASS_10LEVEL_CREDITS = 20;
    uint24 private constant DEITY_PASS_TICKET_LEVELS = 100;
    uint32 private constant DEITY_PASS_TICKETS_PER_LEVEL = 4;
    uint32 private constant DEITY_PASS_EARLY_TICKETS = 160;

    /// @notice Mask for 24-bit fields.
    uint256 private constant MINT_MASK_24 = (uint256(1) << 24) - 1;

    /// @notice Mask for 32-bit fields.
    uint256 private constant MINT_MASK_32 = (uint256(1) << 32) - 1;

    /// @notice Bit shift for last minted level (24 bits at position 0).
    uint256 private constant ETH_LAST_LEVEL_SHIFT = 0;

    /// @notice Bit shift for level count (24 bits at position 24).
    uint256 private constant ETH_LEVEL_COUNT_SHIFT = 24;

    /// @notice Bit shift for consecutive level streak (24 bits at position 48).
    uint256 private constant ETH_LEVEL_STREAK_SHIFT = 48;

    /// @notice Bit shift for last mint day (32 bits at position 72).
    uint256 private constant ETH_DAY_SHIFT = 72;

    /// @notice Bit shift for frozen-until-level (24 bits at position 128).
    uint256 private constant ETH_FROZEN_UNTIL_LEVEL_SHIFT = 128;

    /// @notice Bit shift for whale bundle type (2 bits at position 152).
    uint256 private constant ETH_WHALE_BUNDLE_TYPE_SHIFT = 152;

    // -------------------------------------------------------------------------
    // Purchases
    // -------------------------------------------------------------------------

    /**
     * @notice Purchase whale bundle: boosts Activity Score to 100 levels and awards 200 tickets + 0.5 ETH lootbox.
     * @dev Available when the effective bundle level is %50 == 1 (levels 1, 51, 101, 151...)
     *      or when a valid whale boon is active (one-time override).
     *      Effective level is current level in setup/purchase, or current level + 1 in burn,
     *      so the window opens during the previous level's burn and closes at purchase end.
     *      Can be purchased multiple times (each purchase resets the frozen window).
     *      Activity Score boost: Sets levelCount and streak to 100, frozen until (bundle level + 99).
     *      Queues 2 tickets for each of levels [bundle level, bundle level+99] (200 tickets total).
     *      Includes 0.5 ETH lootbox for all purchases.
     *      Price: 3 ETH at level 1, 3.5 ETH at other levels (scaled by COST_DIVISOR on testnet).
     *
     *      Fund distribution:
     *      - Level 1: 50% next pool, 25% reward pool, 25% future pool
     *      - Other levels: 50% future pool, 45% reward pool, 5% next pool
     *
     *      Example at level 1: 2 tickets each for levels 1-100, stats=100, frozen until 100, 0.5 ETH lootbox.
     *      Example at level 51: 2 tickets each for levels 51-150, stats=100, frozen until 150, 0.5 ETH lootbox.
     */
    function purchaseWhaleBundle(address buyer, uint256 quantity) external payable {
        _purchaseWhaleBundle(buyer, quantity);
    }

    function _purchaseWhaleBundle(
        address buyer,
        uint256 quantity
    ) private {
        uint24 currentLevel = level;
        uint24 passLevel = currentLevel;

        // Check if purchase is allowed: standard level or valid whale boon
        bool isStandardLevel = (passLevel % 50 == 1);
        bool hasValidBoon = false;
        uint48 boonDay = whaleBoonDay[buyer];

        if (!isStandardLevel) {
            // Not a standard level - check for boon
            if (boonDay == 0) revert E(); // No boon
            uint48 currentDay = _currentMintDay();
            if (currentDay > boonDay + 4) revert E(); // Boon expired (4 days)
            hasValidBoon = true;
        }

        if (quantity == 0 || quantity > 100) revert E(); // Reasonable limits

        uint256 prevData = mintPacked_[buyer];

        // Check if player is already frozen from a previous whale bundle
        uint24 frozenUntilLevel = uint24((prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
        if (frozenUntilLevel > 0 && currentLevel < frozenUntilLevel) {
            revert E(); // Cannot buy whale bundle while frozen from previous bundle
        }

        // Unpack current values
        uint24 lastLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 levelCount = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);

        // Bundle covers 100 levels, quantity increases tickets per level
        uint24 ticketStartLevel = passLevel;
        uint24 newFrozenLevel = passLevel + 99;
        uint32 ticketsPerLevel = uint32(2 * quantity);

        // Price calculation
        uint256 unitPrice;
        if (hasValidBoon) {
            // Boon price: 10% off standard whale pass price
            unitPrice = (LOOTBOX_WHALE_PASS_PRICE * 9000) / 10_000;
            delete whaleBoonDay[buyer]; // Clear boon (one-time use)
        } else if (passLevel == 1) {
            unitPrice = 3 ether / ContractAddresses.COST_DIVISOR;
        } else {
            unitPrice = LOOTBOX_WHALE_PASS_PRICE;
        }
        uint256 totalPrice = unitPrice * quantity;

        if (msg.value != totalPrice) revert E();
        _awardEarlybirdDgnrs(buyer, totalPrice);

        // Add 100 to levelCount and streak (quantity doesn't affect stats, only tickets)
        bool alreadyMintedAtCurrentLevel = (lastLevel == passLevel);
        uint24 levelsToAdd = alreadyMintedAtCurrentLevel ? 99 : 100;

        uint24 newLevelCount = levelCount + levelsToAdd;
        uint24 newStreak = streak + levelsToAdd;

        // Update mint data
        uint256 data = prevData;
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, newLevelCount);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, newStreak);
        data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);
        data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 3); // 3 = 100-level bundle (always set)
        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);

        // Update mint day
        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, ETH_DAY_SHIFT, MINT_MASK_32);

        mintPacked_[buyer] = data;

        uint24 lazyPassLevel = _lazyPassStartLevel(passLevel);
        lazyPass.mintPasses(buyer, quantity, lazyPassLevel);

        // Queue (4 * quantity) tickets for each of the 100 levels
        for (uint24 i = 0; i < 100; ) {
            _queueTickets(buyer, ticketStartLevel + i, ticketsPerLevel);
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

        // Split payment based on level
        uint256 futureShare;
        uint256 nextShare;
        uint256 rewardShare;

        if (passLevel == 1) {
            // Level 1: 50% next, 25% reward, 25% future
            nextShare = (totalPrice * 5000) / 10_000;
            rewardShare = (totalPrice * 2500) / 10_000;
            futureShare = totalPrice - nextShare - rewardShare;
        } else {
            // Other levels: 50% future, 45% reward, 5% next
            futureShare = (totalPrice * 5000) / 10_000;
            rewardShare = (totalPrice * 4500) / 10_000;
            nextShare = totalPrice - futureShare - rewardShare;
        }

        futurePrizePool += futureShare;
        nextPrizePool += nextShare;
        futurePrizePool += rewardShare;

        // Lootbox: 0.5 ETH at all levels
        uint256 lootboxAmount = 0.5 ether / ContractAddresses.COST_DIVISOR;
        lootboxAmount = lootboxAmount * quantity;
        uint48 dayIndex = _currentDayIndex();
        uint48 index = lootboxRngIndex;
        bool presale = lootboxPresaleActive;

        _recordLootboxMintDay(buyer, uint32(dayIndex));

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & ((1 << 232) - 1);
        uint48 storedDay = lootboxDay[index][buyer];

        if (existingAmount == 0) {
            lootboxDay[index][buyer] = dayIndex;
            lootboxIndexQueue[buyer].push(index);
            emit LootBoxIndexAssigned(buyer, index, dayIndex);
            if (presale) {
                lootboxPresale[index][buyer] = true;
            }
        } else {
            if (storedDay != dayIndex) revert E();
            if (lootboxPresale[index][buyer] != presale) revert E();
        }

        // Pack: [232 bits: amount] [24 bits: purchase level]
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

        uint24 purchaseLevel = passLevel;
        uint256 newAmount = existingAmount + boostedAmount;
        lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
        lootboxEthTotal += lootboxAmount;
        _maybeRequestLootboxRng(lootboxAmount);
    }

    function purchaseWhaleBundle10(address buyer, uint256 quantity) external payable {
        _purchaseWhaleBundle10(buyer, quantity);
    }

    function _purchaseWhaleBundle10(
        address buyer,
        uint256 quantity
    ) private {
        uint24 currentLevel = level;
        uint24 passLevel = currentLevel;
        if (gameState == GAME_STATE_BURN) {
            unchecked {
                passLevel = currentLevel + 1;
            }
        }

        // Check if purchase is allowed at this level (every x1 level)
        if (passLevel % 10 != 1) revert E();

        if (quantity == 0 || quantity > 100) revert E();

        uint256 prevData = mintPacked_[buyer];

        // Check if player is already frozen from a previous whale bundle
        uint24 frozenUntilLevel = uint24((prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
        if (frozenUntilLevel > 0 && currentLevel < frozenUntilLevel) {
            revert E(); // Cannot buy whale bundle while frozen from previous bundle
        }

        // Unpack current values
        uint24 lastLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 levelCount = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);

        // Bundle covers 10 levels, quantity increases tickets per level
        uint24 ticketStartLevel = passLevel;
        uint24 newFrozenLevel = passLevel + 9;
        uint32 ticketsPerLevel = uint32(4 * quantity);

        // Unit price and lootbox based on level
        uint256 unitPrice;
        uint256 unitLootbox;
        uint24 levelMod100 = passLevel % 100;

        if (passLevel == 1) {
            unitPrice = 0.25 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.04 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 == 91) {  // 91, 191, 291, etc.
            unitPrice = 1.30 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.06 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 == 81) {  // 81, 181, 281, etc.
            unitPrice = 1.20 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.06 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 == 71) {  // 71, 171, 271, etc.
            unitPrice = 1.10 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.16 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 >= 41) {  // 41, 51, 61, 141, 151, 161, etc.
            unitPrice = 1.05 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.13 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 == 31) {  // 31, 131, 231, etc.
            unitPrice = 0.60 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.10 ether / ContractAddresses.COST_DIVISOR;
        } else if (levelMod100 >= 11) {  // 11, 21, 111, 121, etc.
            unitPrice = 0.55 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.09 ether / ContractAddresses.COST_DIVISOR;
        } else {  // 101, 201, 301, etc.
            unitPrice = 0.50 ether / ContractAddresses.COST_DIVISOR;
            unitLootbox = 0.04 ether / ContractAddresses.COST_DIVISOR;
        }

        uint256 totalPrice = unitPrice * quantity;
        uint256 totalLootbox = unitLootbox * quantity;

        if (msg.value != totalPrice) revert E();
        _awardEarlybirdDgnrs(buyer, totalPrice);

        // Add 10 to levelCount and streak (quantity doesn't affect stats, only tickets)
        bool alreadyMintedAtCurrentLevel = (lastLevel == passLevel);
        uint24 levelsToAdd = alreadyMintedAtCurrentLevel ? 9 : 10;

        uint24 newLevelCount = levelCount + levelsToAdd;
        uint24 newStreak = streak + levelsToAdd;

        // Update mint data
        uint256 data = prevData;
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, newLevelCount);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, newStreak);
        data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);

        // Only update bundle type if new type is >= current type (prevent downgrades)
        uint8 currentBundleType = uint8((prevData >> ETH_WHALE_BUNDLE_TYPE_SHIFT) & 3);
        if (1 >= currentBundleType) {
            data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 1); // 1 = 10-level bundle
        }

        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);

        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, ETH_DAY_SHIFT, MINT_MASK_32);

        mintPacked_[buyer] = data;

        // Queue (4 * quantity) tickets for each of the 10 levels
        for (uint24 i = 0; i < 10; ) {
            _queueTickets(buyer, ticketStartLevel + i, ticketsPerLevel);
            unchecked { ++i; }
        }

        // Split payment based on level
        uint256 futureShare;
        uint256 nextShare;
        uint256 rewardShare;

        if (passLevel == 1) {
            // Level 1: 50% next, 25% reward, 25% future
            nextShare = (totalPrice * 5000) / 10_000;
            rewardShare = (totalPrice * 2500) / 10_000;
            futureShare = totalPrice - nextShare - rewardShare;
        } else {
            // Other levels: 50% future, 45% reward, 5% next
            futureShare = (totalPrice * 5000) / 10_000;
            rewardShare = (totalPrice * 4500) / 10_000;
            nextShare = totalPrice - futureShare - rewardShare;
        }

        futurePrizePool += futureShare;
        nextPrizePool += nextShare;
        futurePrizePool += rewardShare;

        // Add lootbox
        uint48 dayIndex = _currentDayIndex();
        uint48 index = lootboxRngIndex;
        bool presale = lootboxPresaleActive;

        _recordLootboxMintDay(buyer, uint32(dayIndex));

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & ((1 << 232) - 1);
        uint48 storedDay = lootboxDay[index][buyer];

        if (existingAmount == 0) {
            lootboxDay[index][buyer] = dayIndex;
            lootboxIndexQueue[buyer].push(index);
            emit LootBoxIndexAssigned(buyer, index, dayIndex);
            if (presale) {
                lootboxPresale[index][buyer] = true;
            }
        } else {
            if (storedDay != dayIndex) revert E();
            if (lootboxPresale[index][buyer] != presale) revert E();
        }

        uint256 boostedAmount = _applyLootboxBoostOnPurchase(
            buyer,
            dayIndex,
            totalLootbox
        );
        uint256 existingBase = lootboxEthBase[index][buyer];
        if (existingAmount != 0 && existingBase == 0) {
            existingBase = existingAmount;
        }
        lootboxEthBase[index][buyer] = existingBase + totalLootbox;

        uint24 purchaseLevel = passLevel;
        uint256 newAmount = existingAmount + boostedAmount;
        lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
        lootboxEthTotal += totalLootbox;
        _maybeRequestLootboxRng(totalLootbox);
    }

    function purchaseDeityPass(address buyer, uint256 quantity) external payable {
        _purchaseDeityPass(buyer, quantity);
    }

    function _purchaseDeityPass(
        address buyer,
        uint256 quantity
    ) private {
        uint24 passLevel = level;

        if (passLevel != 1) revert E();
        if (!lootboxPresaleActive) revert E();

        if (quantity == 0 || quantity > 100) revert E();

        uint256 totalPrice = DEITY_PASS_PRICE * quantity;
        if (msg.value != totalPrice) revert E();
        _awardEarlybirdDgnrs(buyer, totalPrice);

        uint16 prevPassCount = deityPassCount[buyer];
        deityPassCount[buyer] = prevPassCount + uint16(quantity);
        if (prevPassCount == 0) {
            deityPassOwners.push(buyer);
        }

        uint256 creditIncrease = quantity * DEITY_PASS_10LEVEL_CREDITS;
        uint24 lazyPassLevel = _lazyPassStartLevel(passLevel);
        lazyPass.mintPasses(buyer, creditIncrease, lazyPassLevel);

        uint32 ticketsPerLevel = uint32(quantity) * DEITY_PASS_TICKETS_PER_LEVEL;
        _queueTicketRange(buyer, passLevel, DEITY_PASS_TICKET_LEVELS, ticketsPerLevel);

        uint32 earlyTickets = uint32(quantity) * DEITY_PASS_EARLY_TICKETS;
        _queueTickets(buyer, 1, earlyTickets);
        _queueTickets(buyer, 2, earlyTickets);

        address affiliateAddr = affiliate.getReferrer(buyer);
        address upline = address(0);
        address upline2 = address(0);
        if (affiliateAddr != address(0)) {
            upline = affiliate.getReferrer(affiliateAddr);
            if (upline != address(0)) {
                upline2 = affiliate.getReferrer(upline);
            }
        }
        if (affiliateAddr != address(0) && affiliateAddr != buyer) {
            _grantWhaleBundleStats(affiliateAddr, passLevel, ticketsPerLevel);
        }
        for (uint256 i; i < quantity; ) {
            uint96 dgnrsPaid = _rewardDeityPassDgnrs(
                buyer,
                affiliateAddr,
                upline,
                upline2
            );
            trophies.mintDeity(buyer, passLevel, dgnrsPaid);
            unchecked {
                ++i;
            }
        }

        if (levelStartTime == LEVEL_START_SENTINEL) {
            deityPassRefundable[buyer] += totalPrice;
        }
        // Level 1 distribution: 50% next, 25% reward, 25% future (reward tracked in futurePrizePool).
        uint256 nextShare = (totalPrice * 5000) / 10_000;
        uint256 rewardShare = (totalPrice * 2500) / 10_000;
        uint256 futureShare;
        unchecked {
            futureShare = totalPrice - nextShare - rewardShare;
        }
        nextPrizePool += nextShare;
        futurePrizePool += rewardShare;
        futurePrizePool += futureShare;

        uint256 lootboxAmount = DEITY_PASS_LOOTBOX * quantity;
        uint48 dayIndex = _currentDayIndex();
        uint48 index = lootboxRngIndex;
        bool presale = lootboxPresaleActive;

        _recordLootboxMintDay(buyer, uint32(dayIndex));

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & ((1 << 232) - 1);
        uint48 storedDay = lootboxDay[index][buyer];

        if (existingAmount == 0) {
            lootboxDay[index][buyer] = dayIndex;
            lootboxIndexQueue[buyer].push(index);
            emit LootBoxIndexAssigned(buyer, index, dayIndex);
            if (presale) {
                lootboxPresale[index][buyer] = true;
            }
        } else {
            if (storedDay != dayIndex) revert E();
            if (lootboxPresale[index][buyer] != presale) revert E();
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

        uint24 purchaseLevel = passLevel;
        uint256 newAmount = existingAmount + boostedAmount;
        lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
        lootboxEthTotal += lootboxAmount;
        _maybeRequestLootboxRng(lootboxAmount);
    }

    function redeemWhaleBundle10Pass(address buyer, uint256 quantity) external {
        _redeemWhaleBundle10Pass(buyer, quantity);
    }

    function _redeemWhaleBundle10Pass(
        address buyer,
        uint256 quantity
    ) private {
        uint24 currentLevel = level;
        uint24 passLevel = currentLevel;

        if (passLevel % 10 != 1) revert E();

        if (quantity == 0 || quantity > 100) revert E();

        uint256 prevData = mintPacked_[buyer];

        uint24 frozenUntilLevel = uint24((prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
        if (frozenUntilLevel > 0 && currentLevel < frozenUntilLevel) {
            revert E();
        }

        uint24 lastLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 levelCount = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);

        uint24 ticketStartLevel = passLevel;
        uint24 newFrozenLevel = passLevel + 9;
        uint32 ticketsPerLevel = uint32(4 * quantity);

        bool alreadyMintedAtCurrentLevel = (lastLevel == passLevel);
        uint24 levelsToAdd = alreadyMintedAtCurrentLevel ? 9 : 10;

        uint24 newLevelCount = levelCount + levelsToAdd;
        uint24 newStreak = streak + levelsToAdd;

        uint256 data = prevData;
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, newLevelCount);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, newStreak);
        data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);

        uint8 currentBundleType = uint8((prevData >> ETH_WHALE_BUNDLE_TYPE_SHIFT) & 3);
        if (1 >= currentBundleType) {
            data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 1);
        }

        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);

        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, ETH_DAY_SHIFT, MINT_MASK_32);

        mintPacked_[buyer] = data;

        _queueTicketRange(buyer, ticketStartLevel, 10, ticketsPerLevel);
    }

    // -------------------------------------------------------------------------
    // Internal Helpers
    // -------------------------------------------------------------------------

    function _lazyPassStartLevel(uint24 effectiveLevel) private pure returns (uint24) {
        if (effectiveLevel == 0) return 1;
        uint24 offset = uint24((effectiveLevel - 1) % 10);
        return effectiveLevel - offset;
    }

    function _grantWhaleBundleStats(
        address player,
        uint24 passLevel,
        uint32 ticketsPerLevel
    ) private {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24((prevData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 lastLevel = uint24((prevData >> ETH_LAST_LEVEL_SHIFT) & MINT_MASK_24);
        uint24 levelCount = uint24((prevData >> ETH_LEVEL_COUNT_SHIFT) & MINT_MASK_24);
        uint24 streak = uint24((prevData >> ETH_LEVEL_STREAK_SHIFT) & MINT_MASK_24);

        uint24 newFrozenLevel = passLevel + (DEITY_PASS_TICKET_LEVELS - 1);
        if (frozenUntilLevel > newFrozenLevel) {
            newFrozenLevel = frozenUntilLevel;
        }

        bool alreadyMintedAtCurrentLevel = (lastLevel == passLevel);
        uint24 levelsToAdd = alreadyMintedAtCurrentLevel
            ? (DEITY_PASS_TICKET_LEVELS - 1)
            : DEITY_PASS_TICKET_LEVELS;

        uint24 newLevelCount = levelCount + levelsToAdd;
        uint24 newStreak = streak + levelsToAdd;
        uint24 lastLevelTarget = newFrozenLevel > lastLevel
            ? newFrozenLevel
            : lastLevel;

        uint256 data = prevData;
        data = _setPacked(data, ETH_LEVEL_COUNT_SHIFT, MINT_MASK_24, newLevelCount);
        data = _setPacked(data, ETH_LEVEL_STREAK_SHIFT, MINT_MASK_24, newStreak);
        data = _setPacked(data, ETH_FROZEN_UNTIL_LEVEL_SHIFT, MINT_MASK_24, newFrozenLevel);
        data = _setPacked(data, ETH_WHALE_BUNDLE_TYPE_SHIFT, 3, 3);
        data = _setPacked(data, ETH_LAST_LEVEL_SHIFT, MINT_MASK_24, lastLevelTarget);

        uint32 day = _currentMintDay();
        data = _setMintDay(data, day, ETH_DAY_SHIFT, MINT_MASK_32);

        mintPacked_[player] = data;
        _queueTicketRange(player, passLevel, DEITY_PASS_TICKET_LEVELS, ticketsPerLevel);
    }

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

    function _maybeRequestLootboxRng(uint256 lootboxAmount) private {
        uint256 threshold = lootboxRngThreshold;
        if (threshold == 0) {
            threshold = 1 ether / ContractAddresses.COST_DIVISOR;
        }

        uint256 pending = lootboxRngPendingEth + lootboxAmount;
        if (pending < threshold) {
            lootboxRngPendingEth = pending;
            return;
        }

        uint48 index = lootboxRngIndex;
        if (_tryRequestLootboxRng(index)) {
            lootboxRngPendingEth = pending - threshold;
            lootboxRngIndex = index + 1;
        } else {
            lootboxRngPendingEth = pending;
        }
    }

    function _tryRequestLootboxRng(uint48 index) private returns (bool requested) {
        if (index == 0) return false;
        if (lootboxRngWordByIndex[index] != 0) return false;
        if (
            address(vrfCoordinator) == address(0) ||
            vrfKeyHash == bytes32(0) ||
            vrfSubscriptionId == 0
        ) {
            return false;
        }

        try
            vrfCoordinator.requestRandomWords(
                VRFRandomWordsRequest({
                    keyHash: vrfKeyHash,
                    subId: vrfSubscriptionId,
                    requestConfirmations: LOOTBOX_VRF_REQUEST_CONFIRMATIONS,
                    callbackGasLimit: LOOTBOX_VRF_CALLBACK_GAS_LIMIT,
                    numWords: 1,
                    extraArgs: hex""
                })
            )
        returns (uint256 requestId) {
            lootboxRngRequestIndexById[requestId] = index;
            requested = true;
        } catch {}
    }

    function _applyLootboxBoostOnPurchase(
        address player,
        uint48 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        uint16 consumedBoostBps = 0;

        // Check 15% boost first (rarer, better boost)
        bool has15Boost = lootboxBoon15Active[player];
        uint48 boost15Timestamp = lootboxBoon15Timestamp[player];
        if (has15Boost && block.timestamp > uint256(boost15Timestamp) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
            has15Boost = false;
            lootboxBoon15Active[player] = false;
        }
        if (has15Boost) {
            // Apply 15% boost (capped at 10 ETH lootbox value)
            uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
            uint256 boost = (cappedAmount * LOOTBOX_BOOST_15_BONUS_BPS) / 10_000;
            boostedAmount += boost;
            consumedBoostBps = LOOTBOX_BOOST_15_BONUS_BPS;
            lootboxBoon15Active[player] = false;
        } else {
            // Check 5% boost if no 15% boost
            bool has5Boost = lootboxBoon5Active[player];
            uint48 boost5Timestamp = lootboxBoon5Timestamp[player];
            if (has5Boost && block.timestamp > uint256(boost5Timestamp) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                has5Boost = false;
                lootboxBoon5Active[player] = false;
            }
            if (has5Boost) {
                // Apply 5% boost (capped at 10 ETH lootbox value)
                uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
                uint256 boost = (cappedAmount * LOOTBOX_BOOST_5_BONUS_BPS) / 10_000;
                boostedAmount += boost;
                consumedBoostBps = LOOTBOX_BOOST_5_BONUS_BPS;
                lootboxBoon5Active[player] = false;
            }
        }

        if (consumedBoostBps != 0) {
            emit LootBoxBoostConsumed(player, day, amount, boostedAmount, consumedBoostBps);
        }
    }

    function _recordLootboxMintDay(address player, uint32 day) private {
        uint256 prevData = mintPacked_[player];
        uint32 prevDay = uint32((prevData >> ETH_DAY_SHIFT) & MINT_MASK_32);
        if (prevDay == day) {
            return;
        }
        uint256 clearedDay = prevData & ~(MINT_MASK_32 << ETH_DAY_SHIFT);
        mintPacked_[player] = clearedDay | (uint256(day) << ETH_DAY_SHIFT);
    }

    function _currentDayIndex() private view returns (uint48) {
        uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    /**
     * @notice Get current day index for mint tracking.
     * @dev Returns day index relative to deploy time (day 1 = deploy day).
     *      Days reset at JACKPOT_RESET_TIME (22:57 UTC), not midnight.
     * @return Day index (1-indexed from deploy day).
     */
    function _currentMintDay() private view returns (uint32) {
        uint48 day = dailyIdx;
        if (day == 0) {
            // Calculate from timestamp if not yet set
            uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
            day = currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
        }
        return uint32(day);
    }

    /**
     * @notice Update day field in packed data (only if changed).
     * @param data Current packed data.
     * @param day New day value.
     * @param dayShift Bit position of day field.
     * @param dayMask Mask for day field.
     * @return Updated packed data.
     */
    function _setMintDay(uint256 data, uint32 day, uint256 dayShift, uint256 dayMask) private pure returns (uint256) {
        uint32 prevDay = uint32((data >> dayShift) & dayMask);
        if (prevDay == day) {
            return data; // No change needed
        }
        uint256 clearedDay = data & ~(dayMask << dayShift);
        return clearedDay | (uint256(day) << dayShift);
    }

    /**
     * @notice Set a field in packed data.
     * @param data Current packed data.
     * @param shift Bit position of field.
     * @param mask Mask for field width.
     * @param value New value for field.
     * @return Updated packed data.
     */
    function _setPacked(uint256 data, uint256 shift, uint256 mask, uint256 value) private pure returns (uint256) {
        return (data & ~(mask << shift)) | ((value & mask) << shift);
    }
}
