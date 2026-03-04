// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title BurnieCoinflip
 * @author Burnie Degenerus
 * @notice Standalone daily coinflip wagering system for BurnieCoin
 *
 * @dev ARCHITECTURE:
 *      - Extracted from BurnieCoin to reduce contract size
 *      - Manages daily coinflip system with optional afKing mode bonuses
 *      - Integrates with BurnieCoin for burn/mint operations
 *      - Handles auto-rebuy, bounty system, and quest rewards
 *
 * @dev INTERACTIONS:
 *      - Burns BURNIE from players on deposit (via BurnieCoin.burnForCoinflip)
 *      - Mints BURNIE to players on claim (via BurnieCoin.mintForCoinflip)
 *      - Receives quest flip credits from game contract
 *      - Processes RNG results for payout calculations
 */

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";

interface IBurnieCoin {
    function burnForCoinflip(address from, uint256 amount) external;
    function mintForCoinflip(address to, uint256 amount) external;
}

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

contract BurnieCoinflip {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    event CoinflipDeposit(address indexed player, uint256 creditedFlip);
    event CoinflipAutoRebuyToggled(address indexed player, bool enabled);
    event CoinflipAutoRebuyStopSet(address indexed player, uint256 stopAmount);
    event QuestCompleted(
        address indexed player,
        uint8 questType,
        uint32 streak,
        uint256 reward
    );
    /// @notice Emitted when flip stake is credited to a future day.
    /// @param player The player receiving stake credit.
    /// @param day The target flip day being credited.
    /// @param amount The amount credited (includes any boosts).
    /// @param newTotal The new total stake for that day.
    event CoinflipStakeUpdated(
        address indexed player,
        uint48 indexed day,
        uint256 amount,
        uint256 newTotal
    );
    /// @notice Emitted when a coinflip day is resolved.
    /// @param day The resolved day.
    /// @param win Whether the flip outcome is a win.
    /// @param rewardPercent Bonus percent applied on wins.
    /// @param bountyAfter The bounty pool amount after rollover.
    /// @param bountyPaid Amount paid to the bounty owner for this day (0 if none).
    /// @param bountyRecipient Recipient of bounty payout (address(0) if none).
    event CoinflipDayResolved(
        uint48 indexed day,
        bool win,
        uint16 rewardPercent,
        uint128 bountyAfter,
        uint128 bountyPaid,
        address bountyRecipient
    );
    /// @notice Emitted when the daily top bettor is updated.
    /// @param day The day being updated.
    /// @param player New top bettor.
    /// @param score The score in whole tokens (uint96-capped).
    event CoinflipTopUpdated(
        uint48 indexed day,
        address indexed player,
        uint96 score
    );
    /// @notice Emitted when the biggest flip record is updated.
    /// @param player The player setting the record.
    /// @param recordAmount The new record amount (raw, before bonuses).
    event BiggestFlipUpdated(address indexed player, uint256 recordAmount);
    event BountyOwed(address indexed player, uint128 bounty, uint256 recordFlip);
    event BountyPaid(address indexed to, uint256 amount);

    /*+======================================================================+
      |                          CUSTOM ERRORS                               |
      +======================================================================+*/

    error AmountLTMin();
    error CoinflipLocked();
    error OnlyFlipCreditors();
    error OnlyBurnieCoin();
    error OnlyDegenerusGame();
    error AutoRebuyNotEnabled();
    error AutoRebuyAlreadyEnabled();
    error TakeProfitZero();
    error RngLocked();
    error Insufficient();
    error NotApproved();

    /*+======================================================================+
      |                         STORAGE VARIABLES                            |
      +======================================================================+*/

    // Immutable contract references
    IBurnieCoin public immutable burnie;
    IDegenerusGame public immutable degenerusGame;
    IDegenerusJackpots public immutable jackpots;
    IWrappedWrappedXRP public immutable wwxrp;

    // Constants
    uint256 private constant MIN = 100 ether;
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 1 ether;
    uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;
    uint16 private constant COINFLIP_EXTRA_RANGE = 38;
    uint16 private constant COINFLIP_RATIO_BPS_SCALE = 10_000;
    uint16 private constant COINFLIP_RATIO_BPS_EQUAL = 10_000;
    uint16 private constant COINFLIP_RATIO_BPS_TRIPLE = 30_000;
    int256 private constant COINFLIP_EV_EQUAL_BPS = 0;
    int256 private constant COINFLIP_EV_TRIPLE_BPS = 300;
    uint16 private constant COINFLIP_REWARD_MEAN_BPS = 9685;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant AFKING_RECYCLE_BONUS_BPS = 160;
    uint16 private constant AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS = 2;
    uint16 private constant AFKING_DEITY_BONUS_MAX_HALF_BPS = 300;
    uint256 private constant DEITY_RECYCLE_CAP = 1_000_000 ether;
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint8 private constant COIN_CLAIM_DAYS = 90;
    uint8 private constant COIN_CLAIM_FIRST_DAYS = 30;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;
    IDegenerusQuests internal constant questModule =
        IDegenerusQuests(ContractAddresses.QUESTS);

    // Coinflip day result struct
    struct CoinflipDayResult {
        uint16 rewardPercent;
        bool win;
    }

    // Player coinflip state (packed where possible)
    struct PlayerCoinflipState {
        uint128 claimableStored;
        uint48 lastClaim;
        uint48 autoRebuyStartDay;
        bool autoRebuyEnabled;
        uint128 autoRebuyStop;
        uint128 autoRebuyCarry;
    }

    // Daily coinflip storage
    mapping(uint48 => mapping(address => uint256)) internal coinflipBalance;
    mapping(uint48 => CoinflipDayResult) internal coinflipDayResult;
    mapping(address => PlayerCoinflipState) internal playerState;


    // Bounty system
    uint128 public currentBounty = 1_000 ether;
    uint128 public biggestFlipEver;
    address internal bountyOwedTo;

    // RNG state
    uint48 internal flipsClaimableDay;

    // Leaderboard
    struct PlayerScore {
        address player;
        uint96 score;
    }
    mapping(uint48 => PlayerScore) internal coinflipTopByDay;

    /*+======================================================================+
      |                         CONSTRUCTOR                                  |
      +======================================================================+*/

    constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp) {
        burnie = IBurnieCoin(_burnie);
        degenerusGame = IDegenerusGame(_degenerusGame);
        jackpots = IDegenerusJackpots(_jackpots);
        wwxrp = IWrappedWrappedXRP(_wwxrp);
    }

    /*+======================================================================+
      |                         MODIFIERS                                    |
      +======================================================================+*/

    modifier onlyDegenerusGameContract() {
        if (msg.sender != address(degenerusGame)) revert OnlyDegenerusGame();
        _;
    }

    modifier onlyFlipCreditors() {
        if (
            msg.sender != address(degenerusGame) &&
            msg.sender != address(burnie)
        ) revert OnlyFlipCreditors();
        _;
    }

    modifier onlyBurnieCoin() {
        if (msg.sender != address(burnie)) revert OnlyBurnieCoin();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Settle coinflip state before afKing mode changes.
    /// @dev Processes pending claims so mode change doesn't affect in-flight flips.
    /// @param player The player to settle.
    function settleFlipModeChange(address player) external onlyDegenerusGameContract {
        // Process any pending claimable amounts before mode change
        uint256 mintable = _claimCoinflipsInternal(player, false);
        if (mintable != 0) {
            PlayerCoinflipState storage state = playerState[player];
            state.claimableStored = uint128(uint256(state.claimableStored) + mintable);
        }
    }

    /// @notice Deposit BURNIE into daily coinflip system.
    function depositCoinflip(address player, uint256 amount) external {
        address caller;
        bool directDeposit;
        if (player == address(0) || player == msg.sender) {
            caller = msg.sender;
            directDeposit = true;
        } else {
            if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
                revert NotApproved();
            }
            caller = player;
            directDeposit = false;
        }
        _depositCoinflip(caller, amount, directDeposit);
    }

    /// @dev Internal deposit for daily coinflip mode.
    function _depositCoinflip(
        address caller,
        uint256 amount,
        bool directDeposit
    ) private {
        PlayerCoinflipState storage state = playerState[caller];
        if (amount != 0) {
            if (amount < MIN) revert AmountLTMin();
            // Prevent deposits during critical RNG resolution phase
            if (_coinflipLockedDuringTransition()) revert CoinflipLocked();
        }

        uint256 mintable = _claimCoinflipsInternal(caller, false);
        if (mintable != 0) {
            state.claimableStored = uint128(uint256(state.claimableStored) + mintable);
        }

        if (amount == 0) {
            emit CoinflipDeposit(caller, 0);
            return;
        }

        // CEI PATTERN: Burn first so reentrancy into downstream module calls cannot spend the same balance twice.
        burnie.burnForCoinflip(caller, amount);

        // Quests can layer on bonus flip credit when the quest is active/completed.
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleFlip(caller, amount);
        uint256 questReward = _questApplyReward(
            caller,
            reward,
            questType,
            streak,
            completed
        );

        // Principal + quest bonus become the pending flip stake.
        IDegenerusGame game = degenerusGame;
        game.recordCoinflipDeposit(amount);
        uint256 creditedFlip = amount + questReward;
        uint256 rollAmount = state.autoRebuyEnabled
            ? state.autoRebuyCarry
            : mintable;
        uint256 rebetAmount = creditedFlip <= rollAmount
            ? creditedFlip
            : rollAmount;
        if (rebetAmount != 0) {
            // Recycling bonus applies only to the rebet portion (not fresh money).
            uint256 bonus;
            bool isAfKing = game.afKingModeFor(caller);
            if (isAfKing) {
                uint16 deityBonusHalfBps = game.deityPassCountFor(caller) != 0
                    ? _afKingDeityBonusHalfBpsWithLevel(caller, game.level())
                    : 0;
                bonus = _afKingRecyclingBonus(rebetAmount, deityBonusHalfBps);
            } else {
                bonus = _recyclingBonus(rebetAmount);
            }
            creditedFlip += bonus;
        }
        // Direct deposits can set biggestFlip/bounty; indirect deposits cannot.
        _addDailyFlip(
            caller,
            creditedFlip,
            directDeposit ? amount : 0,
            directDeposit,
            directDeposit
        );
        emit CoinflipDeposit(caller, amount);
    }

    /*+======================================================================+
      |                    CLAIM FUNCTIONS                                   |
      +======================================================================+*/

    /// @notice Claim coinflip winnings (exact amount).
    /// @dev Blocked during RNG lock to prevent BAF credit manipulation during jackpots.
    function claimCoinflips(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        if (degenerusGame.rngLocked()) revert RngLocked();
        return _claimCoinflipsAmount(_resolvePlayer(player), amount, true);
    }

    /// @notice Claim coinflip winnings (take profit multiples).
    /// @dev Blocked during RNG lock to prevent BAF credit manipulation during jackpots.
    function claimCoinflipsTakeProfit(
        address player,
        uint256 multiples
    ) external returns (uint256 claimed) {
        if (degenerusGame.rngLocked()) revert RngLocked();
        return _claimCoinflipsTakeProfit(_resolvePlayer(player), multiples);
    }

    /// @notice Claim coinflip winnings via BurnieCoin to cover token transfers/burns.
    /// @dev Access: BurnieCoin only. Blocked during RNG lock.
    function claimCoinflipsFromBurnie(
        address player,
        uint256 amount
    ) external onlyBurnieCoin returns (uint256 claimed) {
        if (degenerusGame.rngLocked()) revert RngLocked();
        return _claimCoinflipsAmount(player, amount, true);
    }

    /// @notice Consume coinflip winnings via BurnieCoin for burns (no mint).
    /// @dev Access: BurnieCoin only. Blocked during RNG lock.
    function consumeCoinflipsForBurn(
        address player,
        uint256 amount
    ) external onlyBurnieCoin returns (uint256 consumed) {
        if (degenerusGame.rngLocked()) revert RngLocked();
        return _claimCoinflipsAmount(player, amount, false);
    }

    /// @dev Internal claim keeping multiples of auto-rebuy stop amount.
    function _claimCoinflipsTakeProfit(
        address player,
        uint256 multiples
    ) private returns (uint256 claimed) {
        PlayerCoinflipState storage state = playerState[player];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();

        uint256 takeProfit = state.autoRebuyStop;
        if (takeProfit == 0) revert TakeProfitZero();

        uint256 mintable = _claimCoinflipsInternal(player, false);
        uint256 stored = state.claimableStored + mintable;
        if (stored < takeProfit) {
            if (mintable != 0) {
                state.claimableStored = uint128(stored);
            }
            return 0;
        }

        uint256 maxMultiples = stored / takeProfit;
        uint256 claimMultiples = multiples == 0 || multiples > maxMultiples ? maxMultiples : multiples;
        uint256 toClaim;
        unchecked {
            toClaim = claimMultiples * takeProfit;
        }

        if (mintable != 0 || toClaim != 0) {
            state.claimableStored = uint128(stored - toClaim);
        }
        burnie.mintForCoinflip(player, toClaim);
        claimed = toClaim;
    }

    /// @dev Internal claim exact amount.
    function _claimCoinflipsAmount(
        address player,
        uint256 amount,
        bool mintTokens
    ) private returns (uint256 claimed) {
        PlayerCoinflipState storage state = playerState[player];
        uint256 mintable = _claimCoinflipsInternal(player, false);
        uint256 stored = state.claimableStored + mintable;
        if (stored == 0) return 0;

        uint256 toClaim = amount;
        if (toClaim > stored) {
            toClaim = stored;
        }
        if (mintable != 0 || toClaim != 0) {
            state.claimableStored = uint128(stored - toClaim);
        }

        if (toClaim != 0) {
            if (mintTokens) {
                burnie.mintForCoinflip(player, toClaim);
            }
            claimed = toClaim;
        }
    }

    /// @dev Process daily coinflip claims and calculate winnings.
    function _claimCoinflipsInternal(
        address player,
        bool deepAutoRebuy
    ) internal returns (uint256 mintable) {
        IDegenerusGame game = degenerusGame;
        PlayerCoinflipState storage state = playerState[player];
        bool afKingMode = game.syncAfKingLazyPassFromCoin(player);
        uint48 latest = flipsClaimableDay;
        uint48 start = state.lastClaim;

        bool rebuyActive = state.autoRebuyEnabled;
        bool deep = deepAutoRebuy && rebuyActive;
        uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;
        uint256 carry;
        uint256 winningBafCredit;
        uint256 lossCount;
        bool afKingActive = rebuyActive && afKingMode;
        bool hasDeityPass = afKingActive && game.deityPassCountFor(player) != 0;
        uint16 deityBonusHalfBps;
        bool levelCached;
        uint24 cachedLevel;
        if (hasDeityPass) {
            cachedLevel = game.level();
            levelCached = true;
            deityBonusHalfBps = _afKingDeityBonusHalfBpsWithLevel(player, cachedLevel);
        }

        uint256 oldCarry = state.autoRebuyCarry;
        if (rebuyActive) {
            carry = oldCarry;
        } else if (oldCarry != 0) {
            mintable += oldCarry;
            state.autoRebuyCarry = 0;
        }

        if (start >= latest) return mintable;

        // Enforce claim window unless auto-rebuy is enabled (settles back to enable day).
        uint8 windowDays = start == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint48 minClaimableDay;
        if (rebuyActive) {
            minClaimableDay = state.autoRebuyStartDay;
            if (minClaimableDay > latest) {
                minClaimableDay = latest;
            }
        } else {
            unchecked {
                minClaimableDay = latest > windowDays ? latest - windowDays : 0;
            }
        }
        if (start < minClaimableDay) {
            start = minClaimableDay;
            if (rebuyActive && carry != 0) {
                carry = 0;
            }
        }

        uint48 cursor;
        unchecked {
            cursor = start + 1;
        }
        uint48 processed = start;

        uint32 remaining;
        if (deep) {
            uint48 available = latest - start;
            uint48 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                ? AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                : available;
            remaining = uint32(cap);
        } else {
            remaining = windowDays;
        }

        // Auto-rebuy-off processes a larger fixed window while keeping tx cost bounded.
        while (remaining != 0 && cursor <= latest) {
            CoinflipDayResult memory result = coinflipDayResult[cursor];
            uint16 rewardPercent = result.rewardPercent;
            bool win = result.win;

            // Skip unresolved days (gaps from testnet day-advance or missed resolution)
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            uint256 storedStake = coinflipBalance[cursor][player];
            uint256 stake = storedStake;
            if (rebuyActive && carry != 0) {
                stake += carry;
            }

            if (storedStake != 0) {
                // Clear stake whether win or loss (loss = forfeit principal)
                coinflipBalance[cursor][player] = 0;
            }

            if (stake != 0) {
                if (win) {
                    // Winnings = principal + (principal * rewardPercent%) where rewardPercent already in percent (not bps).
                    uint256 payout = stake +
                        (stake * uint256(rewardPercent)) /
                        100;
                    winningBafCredit += payout;
                    if (rebuyActive) {
                        if (takeProfit != 0) {
                            uint256 reserved = (payout / takeProfit) *
                                takeProfit;
                            if (reserved != 0) {
                                mintable += reserved;
                            }
                            carry = payout - reserved;
                        } else {
                            carry = payout;
                        }
                        if (carry != 0) {
                            if (afKingActive) {
                                carry += _afKingRecyclingBonus(
                                    carry,
                                    deityBonusHalfBps
                                );
                            } else {
                                carry += _recyclingBonus(carry);
                            }
                        }
                    } else {
                        mintable += payout;
                    }
                } else {
                    unchecked {
                        ++lossCount;
                    }
                    if (rebuyActive) {
                        carry = 0;
                    }
                }
            }

            processed = cursor;
            unchecked {
                ++cursor;
                --remaining;
            }
        }

        if (winningBafCredit != 0) {
            if (!levelCached) {
                cachedLevel = game.level();
                levelCached = true;
            }
            (
                uint24 purchaseLevel_,
                bool inJackpotPhase,
                bool lastPurchaseDay_,
                bool rngLocked_,

            ) = game.purchaseInfo();
            bool over = game.gameOver();
            if (
                !inJackpotPhase &&
                !over &&
                lastPurchaseDay_ &&
                rngLocked_ &&
                (purchaseLevel_ % 10 == 0)
            ) {
                revert RngLocked();
            }
            uint24 bafLevel = cachedLevel;
            if (!inJackpotPhase && !over) {
                bafLevel = purchaseLevel_;
            }
            uint24 bafLvl = _bafBracketLevel(bafLevel);
            jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
        }

        // Update last claim pointer if we processed any days
        if (processed != start) {
            state.lastClaim = processed;
        }

        if (rebuyActive && oldCarry != carry) {
            state.autoRebuyCarry = uint128(carry);
        }

        if (lossCount != 0) {
            wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
        }

        return mintable;
    }

    /*+======================================================================+
      |                    STAKE MANAGEMENT                                  |
      +======================================================================+*/

    /// @dev Add daily flip stake for player.
    function _addDailyFlip(
        address player,
        uint256 coinflipDeposit,
        uint256 recordAmount,
        bool canArmBounty,
        bool bountyEligible
    ) private {
        IDegenerusGame game = degenerusGame;
        if (recordAmount != 0) {
            // Manual deposits only: check and consume coinflip boon (5%/10%/25% boost on max 100k BURNIE deposit)
            // Max bonuses: 5% = 5k, 10% = 10k, 25% = 25k
            uint16 boonBps = game.consumeCoinflipBoon(player);
            if (boonBps > 0) {
                uint256 maxDeposit = 100_000 ether; // Cap at 100k BURNIE for boost calc
                uint256 cappedDeposit = coinflipDeposit > maxDeposit
                    ? maxDeposit
                    : coinflipDeposit;
                uint256 boost = (cappedDeposit * boonBps) / 10_000;
                coinflipDeposit += boost;
            }
        }

        // Determine which future day this stake applies to (always the next window).
        uint48 targetDay = _targetFlipDay();

        uint256 prevStake = coinflipBalance[targetDay][player];
        uint256 newStake = prevStake + coinflipDeposit;

        // Update player's stake for target day
        coinflipBalance[targetDay][player] = newStake;
        _updateTopDayBettor(player, newStake, targetDay);
        emit CoinflipStakeUpdated(player, targetDay, coinflipDeposit, newStake);

        // Bounty logic: only when RNG not locked (prevents manipulation after VRF request).
        // Uses the raw deposit amount (recordAmount), not bonuses or existing stake.
        if (canArmBounty && bountyEligible && recordAmount != 0) {
            uint128 record = biggestFlipEver;
            if (recordAmount > record && !game.rngLocked()) {
                address currentBountyOwner = bountyOwedTo;
                uint128 bounty = currentBounty;
                // Guard against overflow: cap at uint128.max for record tracking
                if (recordAmount > type(uint128).max) revert Insufficient();
                biggestFlipEver = uint128(recordAmount);
                emit BiggestFlipUpdated(player, recordAmount);

                // Bounty arms when setting a new record with an eligible stake.
                // If bounty already armed, must exceed by 1% (min +1) to steal it.
                uint256 threshold = record;
                if (currentBountyOwner != address(0)) {
                    uint256 onePercent = uint256(record) / 100;
                    // Ensure minimum 1 wei increase if 1% rounds to 0
                    threshold = uint256(record) + (onePercent == 0 ? 1 : onePercent);
                }
                if (recordAmount >= threshold) {
                    bountyOwedTo = player;
                    emit BountyOwed(player, bounty, recordAmount);
                }
            }
        }
    }

    /*+======================================================================+
      |                    AUTO-REBUY FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Configure auto-rebuy mode for coinflips.
    function setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 takeProfit
    ) external {
        bool fromGame = msg.sender == ContractAddresses.GAME;
        if (player == address(0)) {
            player = msg.sender;
        } else if (!fromGame && player != msg.sender) {
            _requireApproved(player);
        }
        _setCoinflipAutoRebuy(player, enabled, takeProfit, !fromGame);
    }

    /// @notice Set auto-rebuy take profit.
    function setCoinflipAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) external {
        _setCoinflipAutoRebuyTakeProfit(_resolvePlayer(player), takeProfit);
    }

    /// @dev Internal auto-rebuy configuration.
    function _setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 takeProfit,
        bool strict
    ) private {
        PlayerCoinflipState storage state = playerState[player];
        uint256 mintable;
        if (degenerusGame.rngLocked()) revert RngLocked();

        if (enabled) {
            mintable = _claimCoinflipsInternal(player, false);
            if (state.autoRebuyEnabled) {
                if (strict) revert AutoRebuyAlreadyEnabled();
                state.autoRebuyStop = uint128(takeProfit);
                emit CoinflipAutoRebuyStopSet(player, takeProfit);
            } else {
                if (strict) {
                    state.autoRebuyStop = uint128(takeProfit);
                    state.autoRebuyEnabled = true;
                    state.autoRebuyStartDay = state.lastClaim;
                    emit CoinflipAutoRebuyStopSet(player, takeProfit);
                    emit CoinflipAutoRebuyToggled(player, true);
                } else {
                    state.autoRebuyEnabled = true;
                    state.autoRebuyStartDay = state.lastClaim;
                    emit CoinflipAutoRebuyToggled(player, true);
                    state.autoRebuyStop = uint128(takeProfit);
                    emit CoinflipAutoRebuyStopSet(player, takeProfit);
                }
            }
            if (takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_COIN) {
                degenerusGame.deactivateAfKingFromCoin(player);
            }
        } else {
            mintable = _claimCoinflipsInternal(player, true);
            uint256 carry = state.autoRebuyCarry;
            if (carry != 0) {
                mintable += carry;
                state.autoRebuyCarry = 0;
            }
            state.autoRebuyEnabled = false;
            state.autoRebuyStartDay = 0;
            emit CoinflipAutoRebuyToggled(player, false);
            degenerusGame.deactivateAfKingFromCoin(player);
        }

        if (mintable != 0) {
            burnie.mintForCoinflip(player, mintable);
        }
    }

    /// @dev Internal auto-rebuy take profit configuration.
    function _setCoinflipAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) private {
        if (degenerusGame.rngLocked()) revert RngLocked();
        PlayerCoinflipState storage state = playerState[player];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();

        uint256 mintable = _claimCoinflipsInternal(player, false);
        state.autoRebuyStop = uint128(takeProfit);
        emit CoinflipAutoRebuyStopSet(player, takeProfit);

        if (mintable != 0) {
            burnie.mintForCoinflip(player, mintable);
        }

        if (takeProfit != 0 && takeProfit < AFKING_KEEP_MIN_COIN) {
            degenerusGame.deactivateAfKingFromCoin(player);
        }
    }

    /*+======================================================================+
      |                    RNG PROCESSING                                    |
      +======================================================================+*/

    /// @notice Process coinflip payout for a day (called by game contract).
    function processCoinflipPayouts(
        bool bonusFlip,
        uint256 rngWord,
        uint48 epoch
    ) external onlyDegenerusGameContract {
        // Mix entropy with epoch for unique per-day randomness
        uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

        // Determine payout bonus percent:
        // ~5% each for extreme bonus outcomes (50% or 150%), rest is [78%, 115%]
        uint256 roll = seedWord % 20;
        uint16 rewardPercent;
        if (roll == 0) {
            rewardPercent = 50; // Unlucky: 50% bonus (1.5x total)
        } else if (roll == 1) {
            rewardPercent = 150; // Lucky: 150% bonus (2.5x total)
        } else {
            // Normal bonus range: [78%, 115%]
            rewardPercent = uint16(
                (seedWord % COINFLIP_EXTRA_RANGE) + COINFLIP_EXTRA_MIN_PERCENT
            );
        }
        IDegenerusGame game = degenerusGame;
        bool presaleBonus = bonusFlip && game.lootboxPresaleActiveFlag();
        if (presaleBonus) {
            unchecked {
                rewardPercent += 6;
            }
        }

        if (bonusFlip && !presaleBonus) {
            (uint256 prevTotal, uint256 currentTotal) = game
                .lastPurchaseDayFlipTotals();
            int256 evBps = _coinflipTargetEvBps(prevTotal, currentTotal);
            rewardPercent = _applyEvToRewardPercent(rewardPercent, evBps);
        }

        // Preserve original 50/50 win roll.
        bool win = (rngWord & 1) == 1;

        // Record the day's result for future claims
        coinflipDayResult[epoch] = CoinflipDayResult({
            rewardPercent: rewardPercent,
            win: win
        });

        // Bounty resolution: if someone armed the bounty, remove half; if win, credit that half to them.
        uint128 currentBounty_ = currentBounty;
        uint256 slice;
        address to;
        address bountyOwner = bountyOwedTo;
        uint128 bountyPaid;
        if (bountyOwner != address(0) && currentBounty_ > 0) {
            slice = currentBounty_ >> 1; // pay/delete half of the bounty pool
            unchecked {
                currentBounty_ -= uint128(slice);
            }
            if (win) {
                to = bountyOwner;
                // Credit as flip stake, not direct mint
                _addDailyFlip(to, slice, 0, false, false);
                emit BountyPaid(to, slice);
                game.payCoinflipBountyDgnrs(to);
                bountyPaid = uint128(slice);
            }
            // Clear bounty owner regardless of win/loss
            bountyOwedTo = address(0);
        }

        // Move the active window forward; the resolved day becomes claimable immediately.
        flipsClaimableDay = epoch;

        // Accumulate bounty pool for next window
        unchecked {
            // Gas-optimized: wraps on overflow, which would effectively reset the bounty.
            currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT);
        }

        emit CoinflipDayResolved(
            epoch,
            win,
            rewardPercent,
            currentBounty,
            bountyPaid,
            to
        );
    }

    /*+======================================================================+
      |                    FLIP CREDITING                                    |
      +======================================================================+*/

    /// @notice Credit flip to a player (called by authorized creditors).
    function creditFlip(
        address player,
        uint256 amount
    ) external onlyFlipCreditors {
        if (player == address(0) || amount == 0) return;
        _addDailyFlip(player, amount, 0, false, false);
    }

    /// @notice Credit flips to multiple players (batch).
    function creditFlipBatch(
        address[3] calldata players,
        uint256[3] calldata amounts
    ) external onlyFlipCreditors {
        for (uint256 i; i < 3; ) {
            address player = players[i];
            uint256 amount = amounts[i];
            if (player != address(0) && amount != 0) {
                _addDailyFlip(player, amount, 0, false, false);
            }
            unchecked {
                ++i;
            }
        }
    }

    /*+======================================================================+
      |                    VIEW FUNCTIONS                                    |
      +======================================================================+*/

    /// @notice Preview claimable coinflip winnings.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
        uint256 daily = _viewClaimableCoin(player);
        uint256 stored = playerState[player].claimableStored;
        return daily + stored;
    }

    /// @notice Get player's current coinflip stake for next day.
    function coinflipAmount(address player) external view returns (uint256) {
        uint48 targetDay = _targetFlipDay();
        return coinflipBalance[targetDay][player];
    }

    /// @notice Get player's auto-rebuy configuration.
    function coinflipAutoRebuyInfo(address player)
        external
        view
        returns (
            bool enabled,
            uint256 stop,
            uint256 carry,
            uint48 startDay
        )
    {
        PlayerCoinflipState storage state = playerState[player];
        enabled = state.autoRebuyEnabled;
        stop = state.autoRebuyStop;
        carry = state.autoRebuyCarry;
        startDay = state.autoRebuyStartDay;
    }

    /// @notice Get last day's coinflip leaderboard winner.
    function coinflipTopLastDay()
        external
        view
        returns (address player, uint128 score)
    {
        uint48 lastDay = flipsClaimableDay;
        if (lastDay == 0) return (address(0), 0);
        PlayerScore memory top = coinflipTopByDay[lastDay];
        return (top.player, uint128(top.score));
    }

    /// @dev View helper for daily coinflip claimable winnings.
    function _viewClaimableCoin(
        address player
    ) internal view returns (uint256 total) {
        // Pending flip winnings within the claim window; staking removed.
        uint48 latestDay = flipsClaimableDay;
        uint48 startDay = playerState[player].lastClaim;
        if (startDay >= latestDay) return 0;

        uint8 windowDays = startDay == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint48 minClaimableDay;
        unchecked {
            minClaimableDay = latestDay > windowDays
                ? latestDay - windowDays
                : 0;
        }
        if (startDay < minClaimableDay) {
            startDay = minClaimableDay;
        }

        uint8 remaining = windowDays;
        uint48 cursor;
        unchecked {
            cursor = startDay + 1;
        }
        while (remaining != 0 && cursor <= latestDay) {
            CoinflipDayResult memory result = coinflipDayResult[cursor];
            // Skip unresolved days (both fields zero) instead of breaking,
            // to handle gaps from testnet day-advance or missed resolution.
            if (result.rewardPercent == 0 && !result.win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            if (result.win) {
                uint256 flipStake = coinflipBalance[cursor][player];
                if (flipStake != 0) {
                    // Payout = principal + (principal * rewardPercent%)
                    uint256 payout = flipStake +
                        (flipStake * uint256(result.rewardPercent)) /
                        100;
                    total += payout;
                }
            }
            unchecked {
                ++cursor;
                --remaining;
            }
        }
    }

    /*+======================================================================+
      |                    INTERNAL HELPER FUNCTIONS                         |
      +======================================================================+*/

    /// @dev Check if coinflip deposits are locked during BAF resolution levels.
    ///      Only blocks at levels where BAF jackpot fires (every 10th) to prevent
    ///      front-running the BAF leaderboard between VRF request and fulfillment.
    function _coinflipLockedDuringTransition()
        private
        view
        returns (bool locked)
    {
        (
            uint24 purchaseLevel_,
            bool inJackpotPhase,
            bool lastPurchaseDay_,
            bool rngLocked_,

        ) = degenerusGame.purchaseInfo();
        locked = (!inJackpotPhase) && !degenerusGame.gameOver() && lastPurchaseDay_ && rngLocked_ && (purchaseLevel_ % 10 == 0);
    }

    /// @dev Calculate recycling bonus for daily flip deposits (1% bonus, capped at 1000 BURNIE).
    function _recyclingBonus(
        uint256 amount
    ) private pure returns (uint256 bonus) {
        if (amount == 0) return 0;
        bonus = amount / 100;
        uint256 bonusCap = 1000 ether;
        if (bonus > bonusCap) bonus = bonusCap;
    }

    /// @dev Calculate recycling bonus for afKing flip deposits.
    /// Deity bonus portion is capped at DEITY_RECYCLE_CAP; remainder gets base only.
    function _afKingRecyclingBonus(
        uint256 amount,
        uint16 deityBonusHalfBps
    ) private pure returns (uint256 bonus) {
        if (amount == 0) return 0;
        uint256 baseHalfBps = uint256(AFKING_RECYCLE_BONUS_BPS) * 2;
        if (deityBonusHalfBps == 0 || amount <= DEITY_RECYCLE_CAP) {
            uint256 totalHalfBps = baseHalfBps + uint256(deityBonusHalfBps);
            return (amount * totalHalfBps) / (uint256(BPS_DENOMINATOR) * 2);
        }
        uint256 fullHalfBps = baseHalfBps + uint256(deityBonusHalfBps);
        return (DEITY_RECYCLE_CAP * fullHalfBps + (amount - DEITY_RECYCLE_CAP) * baseHalfBps)
            / (uint256(BPS_DENOMINATOR) * 2);
    }

    /// @dev Calculate deity pass bonus in half-bps using a cached level.
    function _afKingDeityBonusHalfBpsWithLevel(
        address player,
        uint24 currentLevel
    ) private view returns (uint16) {
        uint24 activationLevel = degenerusGame.afKingActivatedLevelFor(player);
        if (activationLevel == 0) return 0;
        if (currentLevel <= activationLevel) return 0;

        uint24 levelsActive = currentLevel - activationLevel;
        uint24 bonus = levelsActive * uint24(AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS);
        if (bonus > AFKING_DEITY_BONUS_MAX_HALF_BPS) {
            return AFKING_DEITY_BONUS_MAX_HALF_BPS;
        }
        return uint16(bonus);
    }

    /// @dev Derive target EV (in bps) based on last-purchase-day flip totals.
    function _coinflipTargetEvBps(
        uint256 prevTotal,
        uint256 currentTotal
    ) private pure returns (int256 evBps) {
        if (prevTotal == 0) {
            return COINFLIP_EV_EQUAL_BPS;
        }

        uint256 ratioBps = (currentTotal * COINFLIP_RATIO_BPS_SCALE) / prevTotal;
        if (ratioBps <= COINFLIP_RATIO_BPS_EQUAL) {
            return COINFLIP_EV_EQUAL_BPS;
        }
        if (ratioBps >= COINFLIP_RATIO_BPS_TRIPLE) {
            return COINFLIP_EV_TRIPLE_BPS;
        }

        return _lerpEvBps(
            COINFLIP_RATIO_BPS_EQUAL,
            COINFLIP_RATIO_BPS_TRIPLE,
            COINFLIP_EV_EQUAL_BPS,
            COINFLIP_EV_TRIPLE_BPS,
            ratioBps
        );
    }

    /// @dev Linear interpolation helper for EV bps.
    function _lerpEvBps(
        uint256 x0,
        uint256 x1,
        int256 y0,
        int256 y1,
        uint256 x
    ) private pure returns (int256) {
        if (x <= x0) return y0;
        if (x >= x1) return y1;
        int256 span = int256(x1 - x0);
        int256 delta = y1 - y0;
        int256 offset = (int256(x - x0) * delta) / span;
        return y0 + offset;
    }

    /// @dev Apply EV-based adjustment to the payout percent (bps) on last purchase day.
    function _applyEvToRewardPercent(
        uint16 rewardPercent,
        int256 evBps
    ) private pure returns (uint16 adjustedPercent) {
        int256 targetRewardBps = int256(uint256(BPS_DENOMINATOR)) + (evBps * 2);
        int256 deltaBps =
            targetRewardBps - int256(uint256(COINFLIP_REWARD_MEAN_BPS));
        int256 adjustedBps = int256(uint256(rewardPercent) * 100) + deltaBps;
        if (adjustedBps <= 0) return 0;
        uint256 rounded = (uint256(adjustedBps) + 50) / 100;
        if (rounded > type(uint16).max) {
            return type(uint16).max;
        }
        adjustedPercent = uint16(rounded);
    }

    /// @dev Calculate the target day for new coinflip deposits.
    function _targetFlipDay() internal view returns (uint48) {
        return degenerusGame.currentDayView() + 1;
    }

    /// @dev Helper to process quest rewards and emit event.
    function _questApplyReward(
        address player,
        uint256 reward,
        uint8 questType,
        uint32 streak,
        bool completed
    ) private returns (uint256) {
        if (!completed) return 0;
        emit QuestCompleted(
            player,
            questType,
            streak,
            reward
        );
        return reward;
    }

    /// @dev Convert stake to uint96 score (whole tokens).
    function _score96(uint256 s) private pure returns (uint96) {
        uint256 wholeTokens = s / 1 ether;
        if (wholeTokens > type(uint96).max) {
            wholeTokens = type(uint96).max;
        }
        return uint96(wholeTokens);
    }

    /// @dev Update day leaderboard if player's score is higher.
    function _updateTopDayBettor(
        address player,
        uint256 stakeScore,
        uint48 day
    ) private {
        uint96 score = _score96(stakeScore);
        PlayerScore memory dayLeader = coinflipTopByDay[day];
        if (score > dayLeader.score || dayLeader.player == address(0)) {
            coinflipTopByDay[day] = PlayerScore({player: player, score: score});
            emit CoinflipTopUpdated(day, player, score);
        }
    }

    /// @dev Round level to BAF bracket (nearest 10).
    function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {
        uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;
        if (bracket > type(uint24).max) return MAX_BAF_BRACKET;
        return uint24(bracket);
    }

    /// @dev Resolve player address (address(0) -> msg.sender, else validate approval).
    function _resolvePlayer(address player) private view returns (address resolved) {
        if (player == address(0)) return msg.sender;
        if (player != msg.sender) {
            if (!degenerusGame.isOperatorApproved(player, msg.sender)) {
                revert OnlyBurnieCoin(); // Reusing error
            }
        }
        return player;
    }

    /// @dev Check if caller is approved to act on behalf of player.
    function _requireApproved(address player) private view {
        if (msg.sender != player && !degenerusGame.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }
}
