// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ContractAddresses} from "./ContractAddresses.sol";

/**
 * @title BurnieLootbox
 * @author Burnie Degenerus
 * @notice Standalone lootbox system for BurnieCoin ecosystem
 *
 * @dev ARCHITECTURE:
 *      - Extracted from DegenerusGameLootboxModule as standalone contract
 *      - Manages ETH and BURNIE lootbox purchases, storage, and opening
 *      - Integrates with game contract for RNG resolution
 *      - Handles boon/boost mechanics for player rewards
 */

interface IBurnieCoin {
    function burnCoin(address from, uint256 amount) external;
    function creditFlip(address to, uint256 amount) external;
    function notifyQuestLootBox(address player, uint256 amount) external;
}

interface IDegenerusGame {
    function level() external view returns (uint24);
    function currentMintDay() external view returns (uint32);
    function mintPrice() external view returns (uint256);
    function lootboxPresaleActiveFlag() external view returns (bool);
    function consumeCoinflipBoon(address player) external returns (uint16 boostBps);
    function consumeGamepieceBoost(address player) external returns (uint16 boostBps);
    function consumeTicketBoost(address player) external returns (uint16 boostBps);
    function consumeDecimatorBoon(address player) external returns (uint16 boostBps);
}

interface IDegenerusGamepieces {
    function purchase(
        uint256 quantity,
        uint8 gamepieceKind,
        uint8 payKind,
        bool fromGame,
        bytes32 affiliateCode
    ) external payable;
}

interface IDegenerusAffiliate {
    function payAffiliate(
        uint256 amount,
        bytes32 code,
        address buyer,
        uint24 level,
        bool freshEth
    ) external returns (uint256 rakeback);
}

interface IDegenerusLazyPass {
    function mintPrize(address to, uint24 passLevel) external;
}

interface IDegenerusQuests {
    // Quest interface placeholder
}

interface IDegenerusStonk {
    function mintPrize(address to, uint256 amount) external;
}

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

contract BurnieLootbox {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    error E();
    error RngNotReady();
    error OnlyGame();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    event LootBoxBuy(
        address indexed buyer,
        uint48 indexed day,
        uint256 amount,
        bool presale,
        uint256 futureShare,
        uint256 nextPrizeShare,
        uint256 vaultShare,
        uint256 rewardShare
    );

    event LootBoxIdx(
        address indexed buyer,
        uint48 indexed index,
        uint48 indexed day
    );

    event BurnieLootBuy(
        address indexed buyer,
        uint48 indexed index,
        uint256 burnieAmount
    );

    event LootBoxOpened(
        address indexed player,
        uint48 indexed day,
        uint256 amount,
        uint24 futureLevel,
        uint32 futureTickets,
        uint32 currentTickets,
        uint256 burnie,
        uint256 bonusBurnie
    );

    event BurnieLootOpen(
        address indexed player,
        uint48 indexed day,
        uint256 burnieAmount,
        uint24 ticketLevel,
        uint32 tickets,
        uint256 burnieReward
    );

    event LootBoxDecayed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 decayedAmount
    );

    event WhaleJackpot(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 targetLevel,
        uint32 tickets,
        uint24 statsBoost,
        uint24 frozenUntilLevel
    );

    event LazyPassWon(
        address indexed player,
        uint48 indexed day,
        uint256 lootboxAmount,
        uint24 passLevel,
        bool activatedNow
    );

    event LootBoxReward(
        address indexed player,
        uint48 indexed day,
        uint8 indexed rewardType,
        uint256 lootboxAmount,
        uint256 amount
    );

    event BoostUsed(
        address indexed player,
        uint48 indexed day,
        uint256 originalAmount,
        uint256 boostedAmount,
        uint16 boostBps
    );

    /*+======================================================================+
      |                             STRUCTS                                  |
      +======================================================================+*/

    struct LootboxRollState {
        uint256 burniePresale;
        uint256 burnieNoMultiplier;
        uint32 futureTickets;
        bool megaJackpotHit;
        bool lazyPassAwarded;
        bool tokenRewarded;
        uint256 entropy;
    }

    /*+======================================================================+
      |                         IMMUTABLE REFERENCES                         |
      +======================================================================+*/

    IBurnieCoin public immutable burnie;
    IDegenerusGame public immutable degenerusGame;
    IDegenerusGamepieces public immutable gamepieces;
    IDegenerusAffiliate public immutable affiliate;
    IDegenerusLazyPass public immutable lazyPass;
    IDegenerusQuests public immutable quests;
    IDegenerusStonk public immutable dgnrs;
    IWrappedWrappedXRP public immutable wwxrp;

    /*+======================================================================+
      |                         STORAGE VARIABLES                            |
      +======================================================================+*/

    // Lootbox balances by day/player
    mapping(address => mapping(uint48 => uint256)) public lootboxBalance;
    mapping(address => mapping(uint48 => uint256)) public burnieLootboxBalance;

    // RNG resolution tracking
    mapping(uint48 => uint256) public lootboxRngRequestId;
    mapping(uint48 => uint256) public lootboxRngWord;
    uint48 public lootboxPurchaseDay;
    uint48 public lootboxResolvedDay;

    // Loot box ETH per RNG index per player (amount may accumulate within an index)
    // Packed: [232 bits: amount] [24 bits: purchase level]
    mapping(uint48 => mapping(address => uint256)) internal lootboxEth;

    // Base (pre-boost) lootbox ETH per RNG index per player
    mapping(uint48 => mapping(address => uint256)) internal lootboxEthBase;

    // Presale flag per index/player
    mapping(uint48 => mapping(address => bool)) internal lootboxPresale;

    // Day per index/player
    mapping(uint48 => mapping(address => uint48)) internal lootboxDay;

    // BURNIE lootbox amounts keyed by lootbox RNG index and player
    mapping(uint48 => mapping(address => uint256)) internal lootboxBurnie;

    // Per-player queue of lootbox RNG indices for auto-open processing
    mapping(address => uint48[]) internal lootboxIndexQueue;

    // Cursor into lootboxIndexQueue for auto-open processing
    mapping(address => uint32) internal lootboxIndexCursor;

    // Current lootbox RNG index for new purchases (1-based)
    uint48 internal lootboxRngIndex = 1;

    // Total ETH spent on lootboxes
    uint256 internal lootboxEthTotal;

    // Total pending BURNIE lootbox amount (for manual RNG trigger threshold)
    uint256 internal lootboxRngPendingBurnie;

    // Boost/boon storage
    mapping(address => bool) public lootboxBoon5Active;
    mapping(address => uint48) public lootboxBoon5Timestamp;
    mapping(address => bool) public lootboxBoon15Active;
    mapping(address => uint48) public lootboxBoon15Timestamp;

    mapping(address => uint16) public gamepieceBoostBps;
    mapping(address => uint48) public gamepieceBoostTimestamp;
    mapping(address => uint16) public ticketBoostBps;
    mapping(address => uint48) public ticketBoostTimestamp;
    mapping(address => uint16) public decimatorBoostBps;

    mapping(address => uint16) public coinflipBoonBps;
    mapping(address => uint48) public coinflipBoonTimestamp;

    mapping(address => bool) public burnBoonActive;
    mapping(address => uint24) public burnBoonLevel;

    mapping(address => uint48) public whaleBoonDay;

    mapping(address => uint24) public activityBoonPending;
    mapping(address => uint48) public activityBoonTimestamp;

    // Lootbox RNG resolution tracking
    mapping(uint48 => uint256) public lootboxRngWordByIndex;
    mapping(uint256 => uint48) public lootboxRngRequestIndexById;

    /*+======================================================================+
      |                         CONSTANTS                                    |
      +======================================================================+*/

    uint48 private constant JACKPOT_RESET_TIME = 82620;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;

    // Lootbox constants
    uint256 private constant LOOTBOX_MIN = 0.01 ether / ContractAddresses.COST_DIVISOR;
    uint256 private constant BURNIE_LOOTBOX_MIN = 1000 ether;

    // Boost/boon expiry times
    uint48 private constant LOOTBOX_BOOST_EXPIRY_SECONDS = 172800; // 2 days
    uint48 private constant PURCHASE_BOOST_EXPIRY_SECONDS = 345600; // 4 days
    uint48 private constant COINFLIP_BOON_EXPIRY_SECONDS = 172800; // 2 days

    // Boost bonus values
    uint16 private constant LOOTBOX_BOOST_5_BONUS_BPS = 500; // 5%
    uint16 private constant LOOTBOX_BOOST_15_BONUS_BPS = 1500; // 15%
    uint256 private constant LOOTBOX_BOOST_MAX_VALUE = 10 ether / ContractAddresses.COST_DIVISOR;

    // Pool split constants
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 6000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 2000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 1000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_NEXT_BPS = 3000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_VAULT_BPS = 3000;

    // Lootbox roll constants
    uint256 private constant LOOTBOX_SPLIT_THRESHOLD = 0.5 ether / ContractAddresses.COST_DIVISOR;
    uint16 private constant LOOTBOX_TICKET_ROLL_BPS = 12_720; // 127.2%
    uint16 private constant BURNIE_LOOTBOX_TICKET_BPS = 6000;
    uint16 private constant BURNIE_LOOTBOX_BURNIE_BPS = 1000;
    uint256 private constant LOOTBOX_MULTIPLIER_CAP = 5 ether / ContractAddresses.COST_DIVISOR;

    // Ticket variance tiers
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS = 100;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS = 400;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS = 2000;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS = 4500;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_CHANCE_BPS = 3000;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER1_BPS = 46_000;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER2_BPS = 23_000;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER3_BPS = 11_000;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER4_BPS = 6_510;
    uint16 private constant LOOTBOX_TICKET_VARIANCE_TIER5_BPS = 4_500;

    // DGNRS reward constants
    uint16 private constant LOOTBOX_DGNRS_POOL_SMALL_PPM = 10;
    uint16 private constant LOOTBOX_DGNRS_POOL_MEDIUM_PPM = 390;
    uint16 private constant LOOTBOX_DGNRS_POOL_LARGE_PPM = 800;
    uint16 private constant LOOTBOX_DGNRS_POOL_MEGA_PPM = 8000;
    uint256 private constant LOOTBOX_DGNRS_MEGA_CAP = 5 ether / ContractAddresses.COST_DIVISOR;
    uint256 private constant DGNRS_VALUE_MULTIPLIER_BPS = 15_000;
    uint256 private constant DGNRS_MIN_BACKING_ETH = 10_000 ether;

    // WWXRP reward
    uint256 private constant LOOTBOX_WWXRP_PRIZE = 0.1 ether;

    // Large BURNIE variance
    uint32 private constant LOOTBOX_LARGE_BURNIE_MAX_BPS = 31_458;
    uint16 private constant LOOTBOX_LARGE_BURNIE_LOW_BPS = 7_216;
    uint16 private constant LOOTBOX_LARGE_BURNIE_MID_BPS = 8_755;

    // Boon roll chances (per ETH)
    uint16 private constant LOOTBOX_BOON_CHANCE_PER_ETH_BPS = 200; // 2% per ETH (coinflip 5%)
    uint16 private constant LOOTBOX_COINFLIP_10_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH
    uint16 private constant LOOTBOX_COINFLIP_25_CHANCE_PER_ETH_BPS = 10; // 0.1% per ETH
    uint16 private constant LOOTBOX_BURN_BOON_CHANCE_PER_ETH_BPS = 100; // 1% per ETH
    uint16 private constant LOOTBOX_BOOST_5_CHANCE_PER_ETH_BPS = 200; // 2% per ETH
    uint16 private constant LOOTBOX_BOOST_15_CHANCE_PER_ETH_BPS = 50; // 0.5% per ETH
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_CHANCE_PER_ETH_BPS = 200;
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_CHANCE_PER_ETH_BPS = 50;
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_CHANCE_PER_ETH_BPS = 10;
    uint16 private constant LOOTBOX_WHALE_BOON_CHANCE_PER_ETH_BPS = 100; // 1% per ETH
    uint16 private constant LOOTBOX_DECIMATOR_10_CHANCE_PER_ETH_BPS = 50;
    uint16 private constant LOOTBOX_DECIMATOR_25_CHANCE_PER_ETH_BPS = 10;
    uint16 private constant LOOTBOX_DECIMATOR_50_CHANCE_PER_ETH_BPS = 3;
    uint16 private constant LOOTBOX_ACTIVITY_BOON_10_CHANCE_PER_ETH_BPS = 100;
    uint16 private constant LOOTBOX_ACTIVITY_BOON_25_CHANCE_PER_ETH_BPS = 30;
    uint16 private constant LOOTBOX_ACTIVITY_BOON_50_CHANCE_PER_ETH_BPS = 10;

    // Boon bonus values
    uint16 private constant LOOTBOX_BOON_BONUS_BPS = 500; // 5% coinflip bonus
    uint256 private constant LOOTBOX_BOON_MAX_BONUS = 5000 ether;
    uint16 private constant LOOTBOX_COINFLIP_10_BONUS_BPS = 1000; // 10%
    uint16 private constant LOOTBOX_COINFLIP_25_BONUS_BPS = 2500; // 25%
    uint256 private constant LOOTBOX_BURN_BOON_BONUS = 100 ether;
    uint16 private constant LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS = 500;
    uint16 private constant LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS = 1500;
    uint16 private constant LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS = 2500;
    uint16 private constant LOOTBOX_DECIMATOR_10_BONUS_BPS = 1000;
    uint16 private constant LOOTBOX_DECIMATOR_25_BONUS_BPS = 2500;
    uint16 private constant LOOTBOX_DECIMATOR_50_BONUS_BPS = 5000;
    uint24 private constant LOOTBOX_ACTIVITY_BOON_10_BONUS = 10;
    uint24 private constant LOOTBOX_ACTIVITY_BOON_25_BONUS = 25;
    uint24 private constant LOOTBOX_ACTIVITY_BOON_50_BONUS = 50;

    // BURNIE factor curve
    uint16 private constant LOOTBOX_BURNIE_BASE_SCALE_BPS = 8_500;
    uint16 private constant LOOTBOX_BURNIE_FACTOR_50_BPS = 14_160;
    uint16 private constant LOOTBOX_BURNIE_FACTOR_110_BPS = 15_580;
    uint16 private constant LOOTBOX_BURNIE_FACTOR_265_BPS = 18_130;
    uint16 private constant LOOTBOX_BONUS_50_BPS = 5_000;
    uint16 private constant LOOTBOX_BONUS_110_BPS = 11_000;
    uint16 private constant LOOTBOX_BONUS_265_BPS = 26_500;
    uint16 private constant LOOTBOX_BONUS_EXCESS_DAMP_BPS = 8_500;
    uint16 private constant LOOTBOX_BONUS_PRESALE_BPS = 15_000;
    uint16 private constant LOOTBOX_PRESALE_NO_WHALE_MULTIPLIER_BPS = 18_000;
    uint16 private constant LOOTBOX_PRESALE_WHALE_10_MULTIPLIER_BPS = 25_000;
    uint16 private constant LOOTBOX_PRESALE_WHALE_100_MULTIPLIER_BPS = 30_000;
    uint16 private constant LOOTBOX_TICKET_BONUS_SHARE_BPS = 3_000;

    // Whale/Lazy pass jackpots
    uint8 private constant LOOTBOX_WHALE_PASS_LEVELS = 100;
    uint16 private constant LOOTBOX_WHALE_PASS_EV_BPS = 500;
    uint256 private constant LOOTBOX_WHALE_PASS_PRICE = 3.4 ether / ContractAddresses.COST_DIVISOR;
    uint16 private constant LOOTBOX_LAZY_PASS_EV_BPS = 200;

    // DGNRS whale rewards (ppm)
    uint32 private constant DGNRS_WHALE_REWARD_PPM_SCALE = 1_000_000;
    uint32 private constant DGNRS_WHALE_MINTER_PPM = 9_000;
    uint32 private constant DGNRS_WHALE_AFFILIATE_PPM = 800;
    uint32 private constant DGNRS_WHALE_UPLINE_PPM = 150;
    uint32 private constant DGNRS_WHALE_UPLINE2_PPM = 50;

    uint48 private constant LOOTBOX_BOON_EXPIRY_SECONDS = 172800;

    /*+======================================================================+
      |                         CONSTRUCTOR                                  |
      +======================================================================+*/

    constructor(
        address burnie_,
        address game_,
        address gamepieces_,
        address affiliate_,
        address lazyPass_,
        address quests_,
        address dgnrs_,
        address wwxrp_
    ) {
        burnie = IBurnieCoin(burnie_);
        degenerusGame = IDegenerusGame(game_);
        gamepieces = IDegenerusGamepieces(gamepieces_);
        affiliate = IDegenerusAffiliate(affiliate_);
        lazyPass = IDegenerusLazyPass(lazyPass_);
        quests = IDegenerusQuests(quests_);
        dgnrs = IDegenerusStonk(dgnrs_);
        wwxrp = IWrappedWrappedXRP(wwxrp_);
    }

    /*+======================================================================+
      |                         MODIFIERS                                    |
      +======================================================================+*/

    modifier onlyGame() {
        if (msg.sender != address(degenerusGame)) revert OnlyGame();
        _;
    }

    /*+======================================================================+
      |                    CORE LOOTBOX FUNCTIONS                            |
      +======================================================================+*/

    /// @notice Purchase ETH lootbox
    function purchase(
        address buyer,
        uint256 lootBoxAmount,
        bytes32 affiliateCode
    ) external payable {
        if (msg.value < lootBoxAmount) revert E();
        if (lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN) revert E();
        if (lootBoxAmount == 0) return;

        uint48 day = _currentDayIndex();
        uint48 index = lootboxRngIndex;
        bool presale = degenerusGame.lootboxPresaleActiveFlag();

        uint256 packed = lootboxEth[index][buyer];
        uint256 existingAmount = packed & ((1 << 232) - 1);
        uint48 storedDay = lootboxDay[index][buyer];

        if (existingAmount == 0) {
            lootboxDay[index][buyer] = day;
            lootboxIndexQueue[buyer].push(index);
            emit LootBoxIdx(buyer, index, day);
            if (presale) {
                lootboxPresale[index][buyer] = true;
            }
        } else {
            if (storedDay != day) revert E();
            if (lootboxPresale[index][buyer] != presale) revert E();
        }

        uint256 boostedAmount = _applyLootboxBoostOnPurchase(buyer, day, lootBoxAmount);
        uint256 existingBase = lootboxEthBase[index][buyer];
        if (existingAmount != 0 && existingBase == 0) {
            existingBase = existingAmount;
        }
        lootboxEthBase[index][buyer] = existingBase + lootBoxAmount;

        // Pack: [232 bits: amount] [24 bits: purchase level]
        uint24 purchaseLevel = degenerusGame.level();
        uint256 newAmount = existingAmount + boostedAmount;
        lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;
        lootboxEthTotal += lootBoxAmount;

        uint256 futureBps = presale ? LOOTBOX_PRESALE_SPLIT_FUTURE_BPS : LOOTBOX_SPLIT_FUTURE_BPS;
        uint256 nextBps = presale ? LOOTBOX_PRESALE_SPLIT_NEXT_BPS : LOOTBOX_SPLIT_NEXT_BPS;
        uint256 vaultBps = presale ? LOOTBOX_PRESALE_SPLIT_VAULT_BPS : 0;

        uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
        uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
        uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;
        uint256 rewardShare;
        unchecked {
            rewardShare = lootBoxAmount - futureShare - nextShare - vaultShare;
        }

        // Send vault share if applicable
        if (vaultShare != 0) {
            (bool ok, ) = payable(ContractAddresses.VAULT).call{value: vaultShare}("");
            if (!ok) revert E();
        }

        // Handle affiliate if provided
        if (affiliateCode != bytes32(0)) {
            uint24 affiliateLevel = degenerusGame.level();
            uint256 lootboxRakeback = affiliate.payAffiliate(
                lootBoxAmount,
                affiliateCode,
                buyer,
                affiliateLevel,
                true
            );
            if (lootboxRakeback != 0) {
                burnie.creditFlip(buyer, lootboxRakeback);
            }
        }

        emit LootBoxBuy(buyer, day, lootBoxAmount, presale, futureShare, nextShare, vaultShare, rewardShare);
        burnie.notifyQuestLootBox(buyer, lootBoxAmount);
    }

    /// @notice Purchase BURNIE lootbox
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external {
        if (buyer == address(0)) revert E();
        if (burnieAmount < BURNIE_LOOTBOX_MIN) revert E();

        uint48 index = lootboxRngIndex;
        if (index == 0) revert E();

        burnie.burnCoin(buyer, burnieAmount);

        uint256 existingAmount = lootboxBurnie[index][buyer];
        uint256 newAmount = existingAmount + burnieAmount;
        if (newAmount < existingAmount) revert E();
        lootboxBurnie[index][buyer] = newAmount;

        // Track total pending BURNIE for manual RNG trigger
        lootboxRngPendingBurnie += burnieAmount;

        emit BurnieLootBuy(buyer, index, burnieAmount);
    }

    /// @notice Open ETH lootbox once RNG is available
    function openLootBox(address player, uint48 index) external {
        _openLootBoxFor(player, index);
    }

    /// @notice Open BURNIE lootbox once RNG is available
    function openBurnieLootBox(address player, uint48 index) external {
        _openBurnieLootBoxFor(player, index);
    }

    /// @notice Resolve lootbox directly for decimator claims (no RNG needed)
    function resolveLootboxDirect(address player, uint256 amount, uint256 rngWord) external onlyGame {
        if (amount == 0) return;
        uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, amount)));
        _openLootBoxResolvedDirect(player, amount, entropy);
    }

    /// @notice Game contract resolves RNG for a day
    function resolveLootboxRng(uint256 rngWord, uint48 day) external onlyGame {
        lootboxRngWord[day] = rngWord;
        lootboxResolvedDay = day;
    }

    /*+======================================================================+
      |                    VIEW FUNCTIONS                                    |
      +======================================================================+*/

    function lootboxAmountFor(address player, uint48 day) external view returns (uint256) {
        return lootboxBalance[player][day];
    }

    function burnieLootboxAmountFor(address player, uint48 day) external view returns (uint256) {
        return burnieLootboxBalance[player][day];
    }

    function currentPurchaseDay() external view returns (uint48) {
        return lootboxPurchaseDay;
    }

    function currentLootboxIndex() external view returns (uint48) {
        return lootboxRngIndex;
    }

    function lootboxRngWordForIndex(uint48 index) external view returns (uint256) {
        return lootboxRngWord[index];
    }

    function lootboxRngPendingBurnieAmount() external view returns (uint256) {
        return lootboxRngPendingBurnie;
    }

    /*+======================================================================+
      |                    INTERNAL HELPER FUNCTIONS                         |
      +======================================================================+*/

    function _currentDayIndex() private view returns (uint48) {
        uint48 currentDayBoundary = uint48((block.timestamp - JACKPOT_RESET_TIME) / 1 days);
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    function _checkBoostExpired(bool hasBoost, uint48 timestamp) private view returns (bool) {
        if (!hasBoost) return false;
        return block.timestamp <= uint256(timestamp) + LOOTBOX_BOOST_EXPIRY_SECONDS;
    }

    function _calculateBoost(uint256 amount, uint16 bonusBps) private pure returns (uint256) {
        uint256 cappedAmount = amount > LOOTBOX_BOOST_MAX_VALUE ? LOOTBOX_BOOST_MAX_VALUE : amount;
        return (cappedAmount * bonusBps) / 10_000;
    }

    function _applyLootboxBoostOnPurchase(
        address player,
        uint48 day,
        uint256 amount
    ) private returns (uint256 boostedAmount) {
        boostedAmount = amount;
        uint16 consumedBoostBps = 0;

        // Check 15% boost first (rarer, better boost)
        bool has15 = _checkBoostExpired(lootboxBoon15Active[player], lootboxBoon15Timestamp[player]);
        if (!has15 && lootboxBoon15Active[player]) {
            lootboxBoon15Active[player] = false;
        }
        if (has15) {
            boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_15_BONUS_BPS);
            consumedBoostBps = LOOTBOX_BOOST_15_BONUS_BPS;
            lootboxBoon15Active[player] = false;
        } else {
            // Check 5% boost if no 15% boost
            bool has5 = _checkBoostExpired(lootboxBoon5Active[player], lootboxBoon5Timestamp[player]);
            if (!has5 && lootboxBoon5Active[player]) {
                lootboxBoon5Active[player] = false;
            }
            if (has5) {
                boostedAmount += _calculateBoost(amount, LOOTBOX_BOOST_5_BONUS_BPS);
                consumedBoostBps = LOOTBOX_BOOST_5_BONUS_BPS;
                lootboxBoon5Active[player] = false;
            }
        }

        if (consumedBoostBps != 0) {
            emit BoostUsed(player, day, amount, boostedAmount, consumedBoostBps);
        }
    }

    /*+======================================================================+
      |                   LOOTBOX OPENING IMPLEMENTATION                     |
      +======================================================================+*/

    function _openLootBoxFor(address player, uint48 index) private {
        uint256 packed = lootboxEth[index][player];
        if (packed == 0) revert E();

        uint256 amount = packed & ((1 << 232) - 1);
        uint24 purchaseLevel = uint24(packed >> 232);

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        _openLootBoxResolved(player, index, amount, rngWord, amount, purchaseLevel);
    }

    function _openBurnieLootBoxFor(address player, uint48 index) private {
        uint256 burnieAmount = lootboxBurnie[index][player];
        if (burnieAmount == 0) revert E();

        uint256 rngWord = lootboxRngWordByIndex[index];
        if (rngWord == 0) revert RngNotReady();

        _openBurnieLootBoxResolved(player, index, burnieAmount, rngWord);
    }

    function _openLootBoxResolved(
        address player,
        uint48 index,
        uint256 amount,
        uint256 rngWord,
        uint256 entropyAmount,
        uint24 purchaseLevel
    ) private {
        uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, index, entropyAmount)));
        uint48 day = lootboxDay[index][player];

        uint24 currentLevel = degenerusGame.level();
        uint48 currentDay = _currentDayIndex();

        // Grace period: within 7 days, use current level
        bool withinGracePeriod = (currentDay <= day + 7);
        uint24 baseLevel = withinGracePeriod ? currentLevel : purchaseLevel;

        // Calculate target level
        uint24 targetLevel;
        uint256 levelEntropy = _entropyStep(entropy);
        uint256 rangeRoll = levelEntropy % 100;
        if (rangeRoll < 5) {
            uint256 farEntropy = _entropyStep(levelEntropy);
            uint256 levelOffset = (farEntropy % 46) + 5; // 5-50 ahead
            targetLevel = baseLevel + uint24(levelOffset);
            entropy = farEntropy;
        } else {
            uint256 levelOffset = levelEntropy % 6; // 0-5 ahead
            targetLevel = baseLevel + uint24(levelOffset);
            entropy = levelEntropy;
        }

        // If target level already passed (outside grace period), lootbox is worthless
        if (targetLevel <= currentLevel && !withinGracePeriod) {
            lootboxEth[index][player] = 0;
            return;
        }

        // Lootbox is valid - process it
        lootboxEth[index][player] = 0;
        bool presale = lootboxPresale[index][player];
        if (presale) {
            lootboxPresale[index][player] = false;
        }

        _openLootBoxResolvedCommon(player, day, amount, targetLevel, purchaseLevel, entropy, presale);
    }

    function _openLootBoxResolvedDirect(
        address player,
        uint256 amount,
        uint256 entropy
    ) private {
        uint48 day = _currentDayIndex();
        uint24 currentLevel = degenerusGame.level();

        // Direct resolution uses current level + small offset
        uint256 levelEntropy = _entropyStep(entropy);
        uint256 levelOffset = levelEntropy % 6;
        uint24 targetLevel = currentLevel + uint24(levelOffset);

        _openLootBoxResolvedCommon(player, day, amount, targetLevel, currentLevel, levelEntropy, false);
    }

    function _openBurnieLootBoxResolved(
        address player,
        uint48 index,
        uint256 burnieAmount,
        uint256 rngWord
    ) private {
        lootboxBurnie[index][player] = 0;

        // Decrement pending BURNIE counter
        if (lootboxRngPendingBurnie >= burnieAmount) {
            lootboxRngPendingBurnie -= burnieAmount;
        } else {
            lootboxRngPendingBurnie = 0;
        }

        uint48 day = lootboxDay[index][player];

        uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, index, burnieAmount)));
        uint24 currentLevel = degenerusGame.level();

        uint256 levelEntropy = _entropyStep(entropy);
        uint256 levelOffset = levelEntropy % 6;
        uint24 targetLevel = currentLevel + uint24(levelOffset);

        uint256 targetPrice = _priceForLevel(targetLevel);
        if (targetPrice == 0) revert E();

        uint256 ticketBudget = (burnieAmount * BURNIE_LOOTBOX_TICKET_BPS) / 10_000;
        uint256 ticketValue = (ticketBudget * targetPrice) / PRICE_COIN_UNIT;

        (uint32 tickets, ) = _lootboxTicketCount(ticketValue, targetPrice, levelEntropy);

        uint256 burnieReward = (burnieAmount * BURNIE_LOOTBOX_BURNIE_BPS) / 10_000;
        if (burnieReward != 0) {
            burnie.creditFlip(player, burnieReward);
        }

        if (tickets != 0) {
            // Queue tickets via game contract
            // Note: This needs to be implemented in the game contract interface
            // For now we'll emit the event
        }

        emit BurnieLootOpen(player, day, burnieAmount, targetLevel, tickets, burnieReward);
    }

    function _openLootBoxResolvedCommon(
        address player,
        uint48 day,
        uint256 amount,
        uint24 targetLevel,
        uint24 purchaseLevel,
        uint256 entropy,
        bool /* presale */
    ) private {
        uint256 targetPrice = _priceForLevel(targetLevel);
        if (targetPrice == 0) revert E();

        uint256 burniePresale;
        uint256 burnieNoMultiplier;
        uint32 futureTickets;

        // Split lootbox into 1 or 2 rolls
        LootboxRollState memory state;
        state.entropy = entropy;

        _resolveLootboxRolls(
            player,
            amount,
            targetLevel,
            targetPrice,
            purchaseLevel,
            state
        );

        burniePresale = state.burniePresale;
        burnieNoMultiplier = state.burnieNoMultiplier;
        futureTickets = state.futureTickets;

        // Roll for boons
        _rollLootboxBoons(player, day, amount, amount, state.entropy);

        // Calculate final BURNIE amount with multipliers
        uint256 baseBurnie = burnieNoMultiplier + burniePresale;
        uint256 burnieAmount = baseBurnie;
        uint256 burnieBonus = 0;
        uint256 bonusBps = _lootboxBurnieFactorBps(0); // Simplified - would need game contract integration

        if (baseBurnie != 0) {
            uint256 baseScaleBps = LOOTBOX_BURNIE_BASE_SCALE_BPS;
            uint256 scaledBase = (baseBurnie * baseScaleBps) / 10_000;
            burnieAmount = scaledBase;

            if (bonusBps > baseScaleBps) {
                uint256 extraBps = bonusBps - baseScaleBps;
                burnieBonus = (baseBurnie * extraBps) / 10_000;
                burnieAmount += burnieBonus;
            }
        }

        if (burnieAmount != 0) {
            burnie.creditFlip(player, burnieAmount);
        }

        emit LootBoxOpened(player, day, amount, targetLevel, futureTickets, 0, burnieAmount, burnieBonus);
    }

    function _resolveLootboxRolls(
        address player,
        uint256 amount,
        uint24 targetLevel,
        uint256 targetPrice,
        uint24 purchaseLevel,
        LootboxRollState memory state
    ) private view {
        uint256 amountFirst = amount;
        uint256 amountSecond = 0;

        if (amount > LOOTBOX_SPLIT_THRESHOLD) {
            amountFirst = amount / 2;
            amountSecond = amount - amountFirst;
        }

        // First roll
        (
            uint256 burnieOut,
            uint32 ticketsOut,
            uint256 nextEntropy,
            bool applyMultiplier
        ) = _resolveLootboxRoll(player, amountFirst, targetLevel, targetPrice, state.entropy, purchaseLevel);

        if (burnieOut != 0) {
            if (applyMultiplier) {
                state.burniePresale += burnieOut;
            } else {
                state.burnieNoMultiplier += burnieOut;
            }
        }
        if (ticketsOut != 0) {
            state.futureTickets += ticketsOut;
        }
        state.entropy = nextEntropy;

        // Second roll if needed
        if (amountSecond != 0) {
            (burnieOut, ticketsOut, nextEntropy, applyMultiplier) =
                _resolveLootboxRoll(player, amountSecond, targetLevel, targetPrice, state.entropy, purchaseLevel);

            if (burnieOut != 0) {
                if (applyMultiplier) {
                    state.burniePresale += burnieOut;
                } else {
                    state.burnieNoMultiplier += burnieOut;
                }
            }
            if (ticketsOut != 0) {
                state.futureTickets += ticketsOut;
            }
            state.entropy = nextEntropy;
        }
    }

    function _resolveLootboxRoll(
        address /*player*/,
        uint256 amount,
        uint24 targetLevel,
        uint256 targetPrice,
        uint256 entropy,
        uint24 /*purchaseLevel*/
    )
        private
        view
        returns (
            uint256 burnieOut,
            uint32 ticketsOut,
            uint256 nextEntropy,
            bool applyPresaleMultiplier
        )
    {
        nextEntropy = _entropyStep(entropy);
        if (amount == 0) return (0, 0, nextEntropy, false);

        uint256 rollMax = 20;
        uint256 ticketThreshold = 11;
        uint256 dgnrsThreshold = 13;
        uint256 wwxrpThreshold = 15;

        uint256 roll = nextEntropy % rollMax;

        if (roll < ticketThreshold) {
            // Ticket roll (55%)
            uint256 ticketBudget = (amount * LOOTBOX_TICKET_ROLL_BPS) / 10_000;
            (uint32 tickets, uint256 entropyAfter) = _lootboxTicketCount(ticketBudget, targetPrice, nextEntropy);
            nextEntropy = entropyAfter;

            uint24 currentLevel = degenerusGame.level();
            if (targetLevel <= currentLevel) {
                burnieOut = uint256(tickets) * PRICE_COIN_UNIT;
            } else {
                ticketsOut = tickets;
            }
            applyPresaleMultiplier = false;
        } else if (roll < dgnrsThreshold) {
            // DGNRS roll (10%) - would need DGNRS integration
            applyPresaleMultiplier = false;
        } else if (roll < wwxrpThreshold) {
            // WWXRP roll (10%) - would need WWXRP integration
            applyPresaleMultiplier = false;
        } else {
            // Large BURNIE roll (25%)
            nextEntropy = _entropyStep(nextEntropy);
            uint256 varianceRoll = nextEntropy % 20;
            uint256 largeBurnieBps;
            if (varianceRoll == 0) {
                largeBurnieBps = LOOTBOX_LARGE_BURNIE_MAX_BPS;
            } else if (varianceRoll == 1) {
                largeBurnieBps = LOOTBOX_LARGE_BURNIE_MID_BPS;
            } else {
                largeBurnieBps = LOOTBOX_LARGE_BURNIE_LOW_BPS;
            }

            uint256 burnieBudget = (amount * largeBurnieBps) / 10_000;
            burnieOut = (burnieBudget * PRICE_COIN_UNIT) / targetPrice;
            applyPresaleMultiplier = true;
        }
    }

    function _rollLootboxBoons(
        address player,
        uint48 day,
        uint256 /* amount */,
        uint256 originalAmount,
        uint256 entropy
    ) private {
        uint256 originalAmountInEth = originalAmount / (1 ether / ContractAddresses.COST_DIVISOR);

        // Check for existing boons and auto-expire
        _checkAndClearExpiredBoon(player);

        // Only roll if player has NO active boons
        bool hasAnyBoon = (
            whaleBoonDay[player] != 0 ||
            coinflipBoonBps[player] != 0 ||
            burnBoonActive[player] ||
            lootboxBoon15Active[player] ||
            lootboxBoon5Active[player]
        );

        if (!hasAnyBoon) {
            uint256 boonRoll = entropy % 10_000;

            // Try to award boost boon (15% or 5%)
            if (_tryAwardBoostBoon(player, day, originalAmount, originalAmountInEth, boonRoll)) {
                return;
            }

            // Try to award burn boon
            uint256 burnChance = originalAmountInEth * LOOTBOX_BURN_BOON_CHANCE_PER_ETH_BPS;
            if (burnChance > 0 && boonRoll < burnChance) {
                burnBoonActive[player] = true;
                burnBoonLevel[player] = degenerusGame.level();
                emit LootBoxReward(player, day, 3, originalAmount, LOOTBOX_BURN_BOON_BONUS);
                return;
            }

            // Try to award coinflip boon
            uint256 coinflipChance = originalAmountInEth * LOOTBOX_BOON_CHANCE_PER_ETH_BPS;
            if (coinflipChance > 0 && boonRoll < coinflipChance) {
                coinflipBoonBps[player] = LOOTBOX_BOON_BONUS_BPS;
                coinflipBoonTimestamp[player] = uint48(block.timestamp);
                emit LootBoxReward(player, day, 2, originalAmount, LOOTBOX_BOON_MAX_BONUS);
                return;
            }

            // Try to award whale boon
            uint256 whaleChance = originalAmountInEth * LOOTBOX_WHALE_BOON_CHANCE_PER_ETH_BPS;
            if (whaleChance > 0 && boonRoll < whaleChance) {
                whaleBoonDay[player] = _currentDayIndex();
                emit LootBoxReward(player, day, 9, originalAmount, 0);
                return;
            }

            // Try to award purchase boost (gamepiece or ticket)
            uint256 purchase5Chance = originalAmountInEth * LOOTBOX_PURCHASE_BOOST_5_CHANCE_PER_ETH_BPS;
            if (purchase5Chance > 0 && boonRoll < purchase5Chance) {
                gamepieceBoostBps[player] = LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS;
                gamepieceBoostTimestamp[player] = uint48(block.timestamp);
                emit LootBoxReward(player, day, 6, originalAmount, LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS);
                return;
            }

            // Try to award decimator boost
            uint256 decimator10Chance = originalAmountInEth * LOOTBOX_DECIMATOR_10_CHANCE_PER_ETH_BPS;
            if (decimator10Chance > 0 && boonRoll < decimator10Chance) {
                decimatorBoostBps[player] = LOOTBOX_DECIMATOR_10_BONUS_BPS;
                emit LootBoxReward(player, day, 8, originalAmount, LOOTBOX_DECIMATOR_10_BONUS_BPS);
                return;
            }

            // Try to award activity boon
            _assignActivityBoon(player, day, originalAmount, originalAmountInEth, boonRoll);
        }
    }

    function _checkAndClearExpiredBoon(address player) private {
        // Check coinflip boon expiry
        if (coinflipBoonBps[player] != 0) {
            uint48 ts = coinflipBoonTimestamp[player];
            if (ts > 0 && block.timestamp > uint256(ts) + LOOTBOX_BOON_EXPIRY_SECONDS) {
                coinflipBoonBps[player] = 0;
                coinflipBoonTimestamp[player] = 0;
            }
        }

        // Check burn boon expiry
        if (burnBoonActive[player]) {
            uint24 boonLevel = burnBoonLevel[player];
            if (degenerusGame.level() > boonLevel) {
                burnBoonActive[player] = false;
            }
        }

        // Check lootbox boost expiry
        if (lootboxBoon15Active[player]) {
            uint48 ts = lootboxBoon15Timestamp[player];
            if (ts > 0 && block.timestamp > uint256(ts) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                lootboxBoon15Active[player] = false;
            }
        }
        if (lootboxBoon5Active[player]) {
            uint48 ts = lootboxBoon5Timestamp[player];
            if (ts > 0 && block.timestamp > uint256(ts) + LOOTBOX_BOOST_EXPIRY_SECONDS) {
                lootboxBoon5Active[player] = false;
            }
        }
    }

    function _tryAwardBoostBoon(
        address player,
        uint48 day,
        uint256 originalAmount,
        uint256 originalAmountInEth,
        uint256 boonRoll
    ) private returns (bool awarded) {
        uint256 boost15Chance = originalAmountInEth * LOOTBOX_BOOST_15_CHANCE_PER_ETH_BPS;
        if (boost15Chance > 0 && boonRoll < boost15Chance) {
            lootboxBoon15Active[player] = true;
            lootboxBoon15Timestamp[player] = uint48(block.timestamp);
            emit LootBoxReward(player, day, 5, originalAmount, LOOTBOX_BOOST_15_BONUS_BPS);
            return true;
        }

        uint256 boost5Chance = originalAmountInEth * LOOTBOX_BOOST_5_CHANCE_PER_ETH_BPS;
        if (boost5Chance > 0 && boonRoll < boost5Chance) {
            lootboxBoon5Active[player] = true;
            lootboxBoon5Timestamp[player] = uint48(block.timestamp);
            emit LootBoxReward(player, day, 4, originalAmount, LOOTBOX_BOOST_5_BONUS_BPS);
            return true;
        }

        return false;
    }

    function _selectBoostTier(
        uint256 originalAmountInEth,
        uint256 boonRoll
    ) private pure returns (uint16 boostBps) {
        uint256 boost25Chance = originalAmountInEth * LOOTBOX_PURCHASE_BOOST_25_CHANCE_PER_ETH_BPS;
        if (boost25Chance > 0 && boonRoll < boost25Chance) {
            return LOOTBOX_PURCHASE_BOOST_25_BONUS_BPS;
        }

        uint256 boost15Chance = originalAmountInEth * LOOTBOX_PURCHASE_BOOST_15_CHANCE_PER_ETH_BPS;
        if (boost15Chance > 0 && boonRoll < boost15Chance) {
            return LOOTBOX_PURCHASE_BOOST_15_BONUS_BPS;
        }

        uint256 boost5Chance = originalAmountInEth * LOOTBOX_PURCHASE_BOOST_5_CHANCE_PER_ETH_BPS;
        if (boost5Chance > 0 && boonRoll < boost5Chance) {
            return LOOTBOX_PURCHASE_BOOST_5_BONUS_BPS;
        }

        return 0;
    }

    function _assignActivityBoon(
        address player,
        uint48 day,
        uint256 originalAmount,
        uint256 originalAmountInEth,
        uint256 boonRoll
    ) private {
        uint256 activity50Chance = originalAmountInEth * LOOTBOX_ACTIVITY_BOON_50_CHANCE_PER_ETH_BPS;
        if (activity50Chance > 0 && boonRoll < activity50Chance) {
            activityBoonPending[player] = LOOTBOX_ACTIVITY_BOON_50_BONUS;
            activityBoonTimestamp[player] = uint48(block.timestamp);
            emit LootBoxReward(player, day, 10, originalAmount, LOOTBOX_ACTIVITY_BOON_50_BONUS);
            return;
        }

        uint256 activity25Chance = originalAmountInEth * LOOTBOX_ACTIVITY_BOON_25_CHANCE_PER_ETH_BPS;
        if (activity25Chance > 0 && boonRoll < activity25Chance) {
            activityBoonPending[player] = LOOTBOX_ACTIVITY_BOON_25_BONUS;
            activityBoonTimestamp[player] = uint48(block.timestamp);
            emit LootBoxReward(player, day, 10, originalAmount, LOOTBOX_ACTIVITY_BOON_25_BONUS);
            return;
        }

        uint256 activity10Chance = originalAmountInEth * LOOTBOX_ACTIVITY_BOON_10_CHANCE_PER_ETH_BPS;
        if (activity10Chance > 0 && boonRoll < activity10Chance) {
            activityBoonPending[player] = LOOTBOX_ACTIVITY_BOON_10_BONUS;
            activityBoonTimestamp[player] = uint48(block.timestamp);
            emit LootBoxReward(player, day, 10, originalAmount, LOOTBOX_ACTIVITY_BOON_10_BONUS);
        }
    }

    function _applyActivityBoonToMintStats(address /*player*/) private {
        // This would update mint stats in the game contract
        // Left as placeholder for game contract integration
    }

    function _recordLootboxMintDay(address /*player*/, uint32 /*day*/) private {
        // This would update the last mint day in game contract
        // Left as placeholder for game contract integration
    }

    function _mintTokenRewards(address /*player*/, uint256 /*amount*/) private {
        // This would mint DGNRS or other token rewards
        // Left as placeholder for integration
    }

    function _awardWhalePassJackpot(address /*player*/, uint48 /*day*/, uint256 /*amount*/) private {
        // This would award whale pass jackpot
        // Left as placeholder for integration
    }

    function _awardLazyPassFromLootbox(address /*player*/, uint48 /*day*/, uint256 /*amount*/) private {
        // This would award lazy pass
        // Left as placeholder for integration
    }

    function _activateLazyPassFromLootbox(address /*player*/, uint24 /*passLevel*/) private {
        // This would activate lazy pass
        // Left as placeholder for integration
    }

    function _lootboxTicketCount(
        uint256 budgetWei,
        uint256 priceWei,
        uint256 entropy
    ) private pure returns (uint32 count, uint256 nextEntropy) {
        if (budgetWei == 0 || priceWei == 0) {
            return (0, entropy);
        }

        nextEntropy = _entropyStep(entropy);

        // Apply ticket variance
        uint256 varianceRoll = nextEntropy % 10_000;
        uint256 ticketBps;

        if (varianceRoll < LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER1_BPS; // 4.6x
        } else if (varianceRoll < LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER2_BPS; // 2.3x
        } else if (varianceRoll < LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER3_BPS; // 1.1x
        } else if (varianceRoll < LOOTBOX_TICKET_VARIANCE_TIER1_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER2_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER3_CHANCE_BPS + LOOTBOX_TICKET_VARIANCE_TIER4_CHANCE_BPS) {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER4_BPS; // 0.651x
        } else {
            ticketBps = LOOTBOX_TICKET_VARIANCE_TIER5_BPS; // 0.45x
        }

        uint256 adjustedBudget = (budgetWei * ticketBps) / 10_000;
        uint256 base = adjustedBudget / priceWei;

        if (base > type(uint32).max) revert E();
        count = uint32(base);
    }

    function _lootboxBurnieFactorBps(uint256 bonusBps) private pure returns (uint256 factorBps) {
        if (bonusBps <= LOOTBOX_BONUS_50_BPS) {
            uint256 delta = LOOTBOX_BURNIE_FACTOR_50_BPS - LOOTBOX_BURNIE_BASE_SCALE_BPS;
            return LOOTBOX_BURNIE_BASE_SCALE_BPS + (bonusBps * delta) / LOOTBOX_BONUS_50_BPS;
        }
        if (bonusBps <= LOOTBOX_BONUS_110_BPS) {
            uint256 delta = LOOTBOX_BURNIE_FACTOR_110_BPS - LOOTBOX_BURNIE_FACTOR_50_BPS;
            return LOOTBOX_BURNIE_FACTOR_50_BPS + ((bonusBps - LOOTBOX_BONUS_50_BPS) * delta) / (LOOTBOX_BONUS_110_BPS - LOOTBOX_BONUS_50_BPS);
        }
        if (bonusBps <= LOOTBOX_BONUS_265_BPS) {
            uint256 dampedBonus = LOOTBOX_BONUS_110_BPS + ((bonusBps - LOOTBOX_BONUS_110_BPS) * LOOTBOX_BONUS_EXCESS_DAMP_BPS) / 10_000;
            uint256 delta = LOOTBOX_BURNIE_FACTOR_265_BPS - LOOTBOX_BURNIE_FACTOR_110_BPS;
            return LOOTBOX_BURNIE_FACTOR_110_BPS + ((dampedBonus - LOOTBOX_BONUS_110_BPS) * delta) / (LOOTBOX_BONUS_265_BPS - LOOTBOX_BONUS_110_BPS);
        }
        return LOOTBOX_BURNIE_FACTOR_265_BPS;
    }

    function _priceForLevel(uint24 targetLevel) private pure returns (uint256) {
        if (targetLevel == 0) return 0;
        if (targetLevel < 10) {
            return 0.025 ether / ContractAddresses.COST_DIVISOR;
        }
        uint24 offset = targetLevel % 100;
        if (offset == 0) {
            return 0.25 ether / ContractAddresses.COST_DIVISOR;
        }
        if (offset >= 30) {
            return 0.1 ether / ContractAddresses.COST_DIVISOR;
        }
        return 0.05 ether / ContractAddresses.COST_DIVISOR;
    }

    function _nextLazyPassLevel(uint24 /*currentLevel*/) private pure returns (uint24) {
        // Calculate next lazy pass level
        return 0; // Placeholder
    }

    function _lazyPassPriceForLevel(uint24 /*passLevel*/) private pure returns (uint256) {
        // Calculate lazy pass price
        return 0; // Placeholder
    }

    function _lootboxDgnrsFromPoolScaled(uint256 /*amount*/) private pure returns (uint256) {
        // Calculate DGNRS amount from pool
        return 0; // Placeholder
    }

    function _autoOpenLootboxes(address /*player*/) private {
        // Auto-open pending lootboxes
        // This would iterate through lootboxIndexQueue and open all resolved lootboxes
        // Left as placeholder for optimization
    }

    function _claimActivityBoon(address player) private {
        uint24 pending = activityBoonPending[player];
        if (pending == 0) return;

        activityBoonPending[player] = 0;
        activityBoonTimestamp[player] = 0;

        _applyActivityBoonToMintStats(player);
    }

    function _entropyStep(uint256 state) private pure returns (uint256) {
        unchecked {
            state ^= state << 7;
            state ^= state >> 9;
            state ^= state << 8;
        }
        return state;
    }
}
