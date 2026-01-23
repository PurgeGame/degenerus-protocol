// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title BurnieCoinflip
 * @author Burnie Degenerus
 * @notice Standalone coinflip wagering system for BurnieCoin
 *
 * @dev ARCHITECTURE:
 *      - Extracted from BurnieCoin to reduce contract size
 *      - Manages daily and afKing coinflip systems
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
    function questModule() external view returns (IDegenerusQuests);
    function _resolvePlayer(address player) external view returns (address);
}

interface IWrappedWrappedXRP {
    function mintPrize(address to, uint256 amount) external;
}

contract BurnieCoinflip {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    event CoinflipDeposit(address indexed player, uint256 creditedFlip);
    event AfKingFlipRecorded(uint48 indexed epoch, uint16 rewardPercent, bool win);
    event AfKingRngModeUpdated(address indexed player, bool dailyOnly);
    event CoinflipAutoRebuyToggled(address indexed player, bool enabled);
    event CoinflipAutoRebuyStopSet(address indexed player, uint256 stopAmount);
    event QuestCompleted(
        address indexed player,
        uint8 questType,
        uint32 streak,
        uint256 reward,
        bool hardMode,
        bool completedBoth
    );
    event BountyOwed(address indexed player, uint128 bounty, uint256 recordFlip);
    event BountyPaid(address indexed to, uint256 amount);
    event CoinflipFinished(bool win);

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
    error KeepMultipleZero();
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
    uint256 private constant MIN = 10_000 ether;
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 0.1 ether;
    uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;
    uint16 private constant COINFLIP_EXTRA_RANGE = 38;
    uint16 private constant COINFLIP_RATIO_BPS_SCALE = 10_000;
    uint16 private constant COINFLIP_RATIO_BPS_EQUAL = 10_000;
    uint16 private constant COINFLIP_RATIO_BPS_TRIPLE = 30_000;
    int256 private constant COINFLIP_EV_EQUAL_BPS = 0;
    int256 private constant COINFLIP_EV_TRIPLE_BPS = 300;
    uint16 private constant COINFLIP_REWARD_MEAN_BPS = 9685;
    uint16 private constant COINFLIP_NORMAL_MEAN_BPS =
        uint16(
            (uint256(COINFLIP_EXTRA_MIN_PERCENT) * 2 +
                uint256(COINFLIP_EXTRA_RANGE) -
                1) * 100 / 2
        );
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant AFKING_RECYCLE_BONUS_BPS = 160;
    uint16 private constant AFKING_DEITY_EDGE_BPS = 150;
    uint16 private constant AFKING_DAILY_ONLY_WIN_PENALTY_BPS = 50;
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint8 private constant COIN_CLAIM_DAYS = 90;
    uint8 private constant COIN_CLAIM_FIRST_DAYS = 30;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    uint256 private constant AFKING_KEEP_MIN_COIN = 20_000 ether;

    // Coinflip day result struct
    struct CoinflipDayResult {
        uint128 totalIn;
        uint128 totalOut;
        uint16 rewardPercent;
        bool win;
    }

    // Daily coinflip storage
    mapping(uint48 => mapping(address => uint256)) internal coinflipBalance;
    mapping(uint48 => CoinflipDayResult) internal coinflipDayResult;
    mapping(address => uint48) internal lastCoinflipClaim;
    mapping(address => bool) internal coinflipAutoRebuyEnabled;
    mapping(address => uint256) internal coinflipAutoRebuyStop;
    mapping(address => uint256) internal coinflipAutoRebuyCarry;
    mapping(address => uint256) internal coinflipClaimableStored;
    mapping(address => uint48) internal coinflipAutoRebuyStartDay;

    // AfKing flip storage
    mapping(address => bool) internal afKingDailyOnly;
    mapping(uint48 => mapping(address => uint256)) internal afKingFlipBalance;
    mapping(uint48 => CoinflipDayResult) internal afKingFlipResult;
    mapping(address => uint48) internal afKingLastClaim;
    mapping(address => uint256) internal afKingClaimableStored;
    mapping(address => uint256) internal afKingAutoRebuyCarry;
    mapping(address => uint48) internal afKingAutoRebuyStartEpoch;

    // Bounty system
    uint128 public currentBounty = 1_000 ether;
    uint128 public biggestFlipEver;
    address internal bountyOwedTo;

    // RNG state
    uint48 internal flipsClaimableDay;
    uint48 internal afKingFlipsClaimableEpoch;

    // Leaderboard
    struct PlayerScore {
        address player;
        uint128 score;
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

    modifier onlyDegenerusGame() {
        if (msg.sender != address(degenerusGame)) revert OnlyDegenerusGame();
        _;
    }

    modifier onlyDegenerusGameContract() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();
        _;
    }

    modifier onlyFlipCreditors() {
        if (
            msg.sender != ContractAddresses.LAZY_PASS &&
            msg.sender != address(degenerusGame)
        ) revert OnlyFlipCreditors();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Deposit BURNIE into coinflip system (daily or afKing mode).
    function depositCoinflip(address player, uint256 amount) external {
        bool directDeposit = player == address(0) || player == msg.sender;
        address caller = _resolvePlayer(player);
        if (degenerusGame.afKingModeFor(caller)) {
            if (afKingDailyOnly[caller]) {
                _depositCoinflip(caller, amount, directDeposit);
            } else {
                _depositAfKingCoinflip(caller, amount, directDeposit);
            }
        } else {
            _depositCoinflip(caller, amount, directDeposit);
        }
    }

    /// @dev Internal deposit for daily coinflip mode.
    function _depositCoinflip(
        address caller,
        uint256 amount,
        bool directDeposit
    ) private {
        if (amount != 0) {
            // Prevent deposits during critical RNG resolution phase
            if (_coinflipLockedDuringLevelJackpot()) revert CoinflipLocked();
            if (amount < MIN) revert AmountLTMin();
        }

        uint256 mintable = _claimCoinflipsInternal(caller, false);
        if (mintable != 0) {
            coinflipClaimableStored[caller] += mintable;
        }

        if (amount == 0) {
            emit CoinflipDeposit(caller, 0);
            return;
        }

        // CEI PATTERN: Burn first so reentrancy into downstream module calls cannot spend the same balance twice.
        burnie.burnForCoinflip(caller, amount);

        // Quests can layer on bonus flip credit when the quest is active/completed.
        IDegenerusQuests module = burnie.questModule();
        uint256 questReward;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleFlip(caller, amount);
        questReward = _questApplyReward(
            caller,
            reward,
            hardMode,
            questType,
            streak,
            completed,
            completedBoth
        );

        // Principal + quest bonus become the pending flip stake.
        uint256 creditedFlip = amount + questReward;
        uint256 rollAmount = coinflipAutoRebuyEnabled[caller]
            ? coinflipAutoRebuyCarry[caller]
            : mintable;
        if (creditedFlip > rollAmount) {
            uint256 bonus = _recyclingBonus(creditedFlip - rollAmount);
            creditedFlip += bonus;
        }
        // Direct deposits can set biggestFlip/bounty; indirect deposits cannot.
        addFlip(
            caller,
            creditedFlip,
            directDeposit ? amount : 0,
            directDeposit,
            directDeposit
        );
        degenerusGame.recordCoinflipDeposit(amount);

        emit CoinflipDeposit(caller, amount);
    }

    /// @dev Internal deposit for afKing coinflip mode.
    function _depositAfKingCoinflip(
        address caller,
        uint256 amount,
        bool directDeposit
    ) private {
        if (amount != 0) {
            if (_coinflipLockedDuringLevelJackpot()) revert CoinflipLocked();
            if (amount < MIN) revert AmountLTMin();
        }

        uint256 mintableDaily = _claimCoinflipsInternal(caller, false);
        if (mintableDaily != 0) {
            coinflipClaimableStored[caller] += mintableDaily;
        }

        uint256 mintable = _claimAfKingFlipsInternal(caller, false);
        if (mintable != 0) {
            afKingClaimableStored[caller] += mintable;
        }

        if (amount == 0) {
            emit CoinflipDeposit(caller, 0);
            return;
        }

        burnie.burnForCoinflip(caller, amount);

        IDegenerusQuests module = burnie.questModule();
        uint256 questReward;
        (
            uint256 reward,
            bool hardMode,
            uint8 questType,
            uint32 streak,
            bool completed,
            bool completedBoth
        ) = module.handleFlip(caller, amount);
        questReward = _questApplyReward(
            caller,
            reward,
            hardMode,
            questType,
            streak,
            completed,
            completedBoth
        );

        uint256 creditedFlip = amount + questReward;
        uint256 rollAmount = coinflipAutoRebuyEnabled[caller]
            ? afKingAutoRebuyCarry[caller]
            : mintable;
        if (creditedFlip > rollAmount) {
            uint256 bonus = _recyclingBonus(creditedFlip - rollAmount);
            creditedFlip += bonus;
        }

        addFlip(
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
    function claimCoinflips(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        return _claimCoinflipsAmount(_resolvePlayer(player), amount);
    }

    /// @notice Claim coinflip winnings (keep multiples).
    function claimCoinflipsKeepMultiple(
        address player,
        uint256 multiples
    ) external returns (uint256 claimed) {
        return _claimCoinflipsKeepMultiple(_resolvePlayer(player), multiples);
    }

    /// @dev Internal claim keeping multiples of auto-rebuy stop amount.
    function _claimCoinflipsKeepMultiple(
        address player,
        uint256 multiples
    ) private returns (uint256 claimed) {
        if (!coinflipAutoRebuyEnabled[player]) revert AutoRebuyNotEnabled();

        uint256 keepMultiple = coinflipAutoRebuyStop[player];
        if (keepMultiple == 0) revert KeepMultipleZero();

        uint256 mintableDaily = _claimCoinflipsInternal(player, false);
        uint256 mintableAfKing = _claimAfKingFlipsInternal(player, false);
        uint256 storedDaily = coinflipClaimableStored[player] + mintableDaily;
        uint256 storedAfKing = afKingClaimableStored[player] + mintableAfKing;
        uint256 available = storedDaily + storedAfKing;
        if (available < keepMultiple) {
            coinflipClaimableStored[player] = storedDaily;
            afKingClaimableStored[player] = storedAfKing;
            return 0;
        }

        uint256 maxMultiples = available / keepMultiple;
        uint256 claimMultiples = multiples == 0 || multiples > maxMultiples ? maxMultiples : multiples;
        uint256 toClaim = claimMultiples * keepMultiple;

        if (toClaim >= storedDaily) {
            uint256 remaining = toClaim - storedDaily;
            coinflipClaimableStored[player] = 0;
            afKingClaimableStored[player] = storedAfKing - remaining;
        } else {
            coinflipClaimableStored[player] = storedDaily - toClaim;
            afKingClaimableStored[player] = storedAfKing;
        }
        burnie.mintForCoinflip(player, toClaim);
        claimed = toClaim;
    }

    /// @dev Internal claim exact amount.
    function _claimCoinflipsAmount(
        address player,
        uint256 amount
    ) private returns (uint256 claimed) {
        uint256 mintableDaily = _claimCoinflipsInternal(player, false);
        uint256 mintableAfKing = _claimAfKingFlipsInternal(player, false);
        uint256 storedDaily = coinflipClaimableStored[player] + mintableDaily;
        uint256 storedAfKing = afKingClaimableStored[player] + mintableAfKing;
        uint256 available = storedDaily + storedAfKing;
        if (available == 0) return 0;

        uint256 toClaim = amount;
        if (toClaim > available) {
            toClaim = available;
        }
        if (toClaim >= storedDaily) {
            uint256 remaining = toClaim - storedDaily;
            coinflipClaimableStored[player] = 0;
            afKingClaimableStored[player] = storedAfKing - remaining;
        } else {
            coinflipClaimableStored[player] = storedDaily - toClaim;
            afKingClaimableStored[player] = storedAfKing;
        }

        if (toClaim != 0) {
            burnie.mintForCoinflip(player, toClaim);
            claimed = toClaim;
        }
    }

    /// @dev Process daily coinflip claims and calculate winnings.
    function _claimCoinflipsInternal(
        address player,
        bool deepAutoRebuy
    ) internal returns (uint256 mintable) {
        uint48 latest = flipsClaimableDay;
        uint48 start = lastCoinflipClaim[player];

        bool rebuyActive = coinflipAutoRebuyEnabled[player];
        bool deep = deepAutoRebuy && rebuyActive;
        uint256 keepMultiple = rebuyActive ? coinflipAutoRebuyStop[player] : 0;
        uint256 carry;
        uint256 winningBafCredit;
        uint256 lossCount;
        bool afKingMode = degenerusGame.afKingModeFor(player);
        bool afKingActive = rebuyActive && afKingMode;
        bool dailyOnlyPenalty = afKingMode && afKingDailyOnly[player];
        bool hasDeityPass = afKingActive &&
            degenerusGame.deityPassCountFor(player) != 0;

        if (rebuyActive) {
            carry = coinflipAutoRebuyCarry[player];
        } else {
            uint256 staleCarry = coinflipAutoRebuyCarry[player];
            if (staleCarry != 0) {
                mintable += staleCarry;
                coinflipAutoRebuyCarry[player] = 0;
            }
        }

        if (start >= latest) return mintable;

        // Enforce claim window unless auto-rebuy is enabled (settles back to enable day).
        uint8 windowDays = _claimWindowDays(player);
        uint48 minClaimableDay;
        if (rebuyActive) {
            minClaimableDay = coinflipAutoRebuyStartDay[player];
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
            uint48 available = latest > start ? latest - start : 0;
            uint48 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                ? AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                : available;
            remaining = uint32(cap);
        } else {
            remaining = windowDays;
        }

        // Auto-rebuy-off processes a larger fixed window while keeping tx cost bounded.
        while (remaining != 0 && cursor <= latest) {
            CoinflipDayResult storage result = coinflipDayResult[cursor];

            // Unresolved day detection: stop processing
            if (result.rewardPercent == 0 && !result.win) {
                break; // day not settled yet; keep stake intact
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
                if (result.win) {
                    // Winnings = principal + (principal * rewardPercent%) where rewardPercent already in percent (not bps).
                    uint256 payout = stake +
                        (stake * uint256(result.rewardPercent)) /
                        100;
                    if (dailyOnlyPenalty) {
                        uint256 penalty = (stake *
                            uint256(AFKING_DAILY_ONLY_WIN_PENALTY_BPS)) /
                            BPS_DENOMINATOR;
                        payout -= penalty;
                    }
                    winningBafCredit += payout;
                    if (rebuyActive) {
                        if (keepMultiple != 0) {
                            uint256 reserved = (payout / keepMultiple) *
                                keepMultiple;
                            if (reserved != 0) {
                                mintable += reserved;
                            }
                            carry = payout - reserved;
                        } else {
                            carry = payout;
                        }
                        if (carry != 0) {
                            if (afKingActive) {
                                carry += _afKingRecyclingBonus(carry, hasDeityPass);
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
            uint24 bafLvl = _bafBracketLevel(degenerusGame.level());
            jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
        }

        // Update last claim pointer if we processed any days
        if (processed != start) {
            lastCoinflipClaim[player] = processed;
        }

        if (rebuyActive) {
            coinflipAutoRebuyCarry[player] = carry;
        } else if (coinflipAutoRebuyCarry[player] != 0) {
            coinflipAutoRebuyCarry[player] = 0;
        }

        if (lossCount != 0) {
            wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
        }

        return mintable;
    }

    /// @dev Process afKing coinflip claims and calculate winnings.
    function _claimAfKingFlipsInternal(
        address player,
        bool deepAutoRebuy
    ) internal returns (uint256 mintable) {
        uint48 latest = afKingFlipsClaimableEpoch;
        uint48 start = afKingLastClaim[player];

        bool rebuyActive = coinflipAutoRebuyEnabled[player];
        bool deep = deepAutoRebuy && rebuyActive;
        uint256 keepMultiple = rebuyActive ? coinflipAutoRebuyStop[player] : 0;
        uint256 carry;
        uint256 winningBafCredit;
        uint256 lossCount;
        bool afKingActive = rebuyActive && degenerusGame.afKingModeFor(player);
        bool hasDeityPass = afKingActive &&
            degenerusGame.deityPassCountFor(player) != 0;

        if (rebuyActive) {
            carry = afKingAutoRebuyCarry[player];
        } else {
            uint256 staleCarry = afKingAutoRebuyCarry[player];
            if (staleCarry != 0) {
                mintable += staleCarry;
                afKingAutoRebuyCarry[player] = 0;
            }
        }

        if (start >= latest) return mintable;

        uint8 windowEpochs = _claimWindowEpochs(start);
        uint48 minClaimableEpoch;
        if (rebuyActive) {
            minClaimableEpoch = afKingAutoRebuyStartEpoch[player];
            if (minClaimableEpoch > latest) {
                minClaimableEpoch = latest;
            }
        } else {
            unchecked {
                minClaimableEpoch = latest > windowEpochs
                    ? latest - windowEpochs
                    : 0;
            }
        }
        if (start < minClaimableEpoch) {
            start = minClaimableEpoch;
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
            uint48 available = latest > start ? latest - start : 0;
            uint48 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                ? AUTO_REBUY_OFF_CLAIM_DAYS_MAX
                : available;
            remaining = uint32(cap);
        } else {
            remaining = windowEpochs;
        }

        while (remaining != 0 && cursor <= latest) {
            CoinflipDayResult storage result = afKingFlipResult[cursor];
            if (result.rewardPercent == 0 && !result.win) {
                break;
            }

            uint256 storedStake = afKingFlipBalance[cursor][player];
            uint256 stake = storedStake;
            if (rebuyActive && carry != 0) {
                stake += carry;
            }

            if (storedStake != 0) {
                afKingFlipBalance[cursor][player] = 0;
            }

            if (stake != 0) {
                if (result.win) {
                    uint256 payout = stake +
                        (stake * uint256(result.rewardPercent)) /
                        100;
                    winningBafCredit += payout;
                    if (rebuyActive) {
                        if (keepMultiple != 0) {
                            uint256 reserved = (payout / keepMultiple) *
                                keepMultiple;
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
                                    hasDeityPass
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
            uint24 bafLvl = _bafBracketLevel(degenerusGame.level());
            jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
        }

        if (processed != start) {
            afKingLastClaim[player] = processed;
        }

        if (rebuyActive) {
            afKingAutoRebuyCarry[player] = carry;
        } else if (afKingAutoRebuyCarry[player] != 0) {
            afKingAutoRebuyCarry[player] = 0;
        }

        if (lossCount != 0) {
            wwxrp.mintPrize(player, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
        }

        return mintable;
    }

    /*+======================================================================+
      |                    STAKE MANAGEMENT                                  |
      +======================================================================+*/

    /// @dev Internal function to add flip stake to player's balance.
    function addFlip(
        address player,
        uint256 coinflipDeposit,
        uint256 recordAmount,
        bool canArmBounty,
        bool bountyEligible
    ) internal {
        if (degenerusGame.afKingModeFor(player)) {
            if (afKingDailyOnly[player]) {
                _addDailyFlip(
                    player,
                    coinflipDeposit,
                    recordAmount,
                    canArmBounty,
                    bountyEligible
                );
            } else {
                _addAfKingFlip(
                    player,
                    coinflipDeposit,
                    recordAmount,
                    canArmBounty,
                    bountyEligible
                );
            }
            return;
        }
        _addDailyFlip(
            player,
            coinflipDeposit,
            recordAmount,
            canArmBounty,
            bountyEligible
        );
    }

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
        bool rngLocked = game.rngLocked();
        uint48 targetDay = _targetFlipDay();

        uint256 prevStake = coinflipBalance[targetDay][player];
        uint256 newStake = prevStake + coinflipDeposit;

        // Update player's stake for target day
        coinflipBalance[targetDay][player] = newStake;
        _updateTopDayBettor(player, newStake, targetDay);

        // Bounty logic: only when RNG not locked (prevents manipulation after VRF request).
        // Uses the raw deposit amount (recordAmount), not bonuses or existing stake.
        if (!rngLocked && canArmBounty && bountyEligible && recordAmount != 0) {
            uint256 record = biggestFlipEver;
            if (recordAmount > record) {
                // Guard against overflow: cap at uint128.max for record tracking
                if (recordAmount > type(uint128).max) revert Insufficient();
                biggestFlipEver = uint128(recordAmount);

                // Bounty arms when setting a new record with an eligible stake.
                // If bounty already armed, must exceed by 1% (min +1) to steal it.
                uint256 threshold = record;
                if (bountyOwedTo != address(0)) {
                    uint256 onePercent = record / 100;
                    // Ensure minimum 1 wei increase if 1% rounds to 0
                    threshold = record + (onePercent == 0 ? 1 : onePercent);
                }
                if (recordAmount >= threshold) {
                    bountyOwedTo = player;
                    emit BountyOwed(player, currentBounty, recordAmount);
                }
            }
        }
    }

    /// @dev Add afKing flip stake for player.
    function _addAfKingFlip(
        address player,
        uint256 coinflipDeposit,
        uint256 recordAmount,
        bool canArmBounty,
        bool bountyEligible
    ) private {
        if (recordAmount != 0) {
            uint16 boonBps = degenerusGame.consumeCoinflipBoon(player);
            if (boonBps > 0) {
                uint256 maxDeposit = 100_000 ether;
                uint256 cappedDeposit = coinflipDeposit > maxDeposit
                    ? maxDeposit
                    : coinflipDeposit;
                uint256 boost = (cappedDeposit * boonBps) / 10_000;
                coinflipDeposit += boost;
            }
        }

        uint48 targetEpoch = _targetAfKingEpoch();
        uint256 prevStake = afKingFlipBalance[targetEpoch][player];
        afKingFlipBalance[targetEpoch][player] = prevStake + coinflipDeposit;

        if (canArmBounty && bountyEligible) {
            // afKing flips do not arm daily bounty records.
        }
    }

    /*+======================================================================+
      |                    AUTO-REBUY FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Configure auto-rebuy mode for coinflips.
    function setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 keepMultiple
    ) external {
        bool fromGame = msg.sender == ContractAddresses.GAME;
        if (player == address(0)) {
            player = msg.sender;
        } else if (!fromGame && player != msg.sender) {
            _requireApproved(player);
        }
        _setCoinflipAutoRebuy(player, enabled, keepMultiple, !fromGame);
    }

    /// @notice Set auto-rebuy keep multiple.
    function setCoinflipAutoRebuyKeepMultiple(
        address player,
        uint256 keepMultiple
    ) external {
        _setCoinflipAutoRebuyKeepMultiple(_resolvePlayer(player), keepMultiple);
    }

    /// @dev Internal auto-rebuy configuration.
    function _setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 keepMultiple,
        bool strict
    ) private {
        uint256 mintable;
        if (degenerusGame.rngLocked()) revert RngLocked();

        if (enabled) {
            mintable = _claimCoinflipsInternal(player, false);
            uint256 mintableAfKing = _claimAfKingFlipsInternal(player, false);
            if (mintableAfKing != 0) {
                mintable += mintableAfKing;
            }
            if (coinflipAutoRebuyEnabled[player]) {
                if (strict) revert AutoRebuyAlreadyEnabled();
                coinflipAutoRebuyStop[player] = keepMultiple;
                emit CoinflipAutoRebuyStopSet(player, keepMultiple);
            } else {
                if (strict) {
                    coinflipAutoRebuyStop[player] = keepMultiple;
                    coinflipAutoRebuyEnabled[player] = true;
                    coinflipAutoRebuyStartDay[player] = lastCoinflipClaim[player];
                    afKingAutoRebuyStartEpoch[player] = afKingLastClaim[player];
                    emit CoinflipAutoRebuyStopSet(player, keepMultiple);
                    emit CoinflipAutoRebuyToggled(player, true);
                } else {
                    coinflipAutoRebuyEnabled[player] = true;
                    coinflipAutoRebuyStartDay[player] = lastCoinflipClaim[player];
                    afKingAutoRebuyStartEpoch[player] = afKingLastClaim[player];
                    emit CoinflipAutoRebuyToggled(player, true);
                    coinflipAutoRebuyStop[player] = keepMultiple;
                    emit CoinflipAutoRebuyStopSet(player, keepMultiple);
                }
            }
        } else {
            mintable = _claimCoinflipsInternal(player, true);
            uint256 mintableAfKing = _claimAfKingFlipsInternal(player, true);
            if (mintableAfKing != 0) {
                mintable += mintableAfKing;
            }
            uint256 carry = coinflipAutoRebuyCarry[player];
            if (carry != 0) {
                mintable += carry;
                coinflipAutoRebuyCarry[player] = 0;
            }
            uint256 afKingCarry = afKingAutoRebuyCarry[player];
            if (afKingCarry != 0) {
                mintable += afKingCarry;
                afKingAutoRebuyCarry[player] = 0;
            }
            coinflipAutoRebuyEnabled[player] = false;
            coinflipAutoRebuyStartDay[player] = 0;
            afKingAutoRebuyStartEpoch[player] = 0;
            emit CoinflipAutoRebuyToggled(player, false);
            degenerusGame.deactivateAfKingFromCoin(player);
        }

        if (mintable != 0) {
            burnie.mintForCoinflip(player, mintable);
        }
    }

    /// @dev Internal auto-rebuy keep multiple configuration.
    function _setCoinflipAutoRebuyKeepMultiple(
        address player,
        uint256 keepMultiple
    ) private {
        if (degenerusGame.rngLocked()) revert RngLocked();
        if (!coinflipAutoRebuyEnabled[player]) revert AutoRebuyNotEnabled();

        uint256 mintable = _claimCoinflipsInternal(player, false);
        uint256 mintableAfKing = _claimAfKingFlipsInternal(player, false);
        if (mintableAfKing != 0) {
            mintable += mintableAfKing;
        }
        coinflipAutoRebuyStop[player] = keepMultiple;
        emit CoinflipAutoRebuyStopSet(player, keepMultiple);

        if (mintable != 0) {
            burnie.mintForCoinflip(player, mintable);
        }

        if (keepMultiple != 0 && keepMultiple < AFKING_KEEP_MIN_COIN) {
            degenerusGame.deactivateAfKingFromCoin(player);
        }
    }

    /// @notice Toggle afKing daily-only mode.
    function setAfKingDailyOnly(address player, bool dailyOnly) external {
        address caller = _resolvePlayer(player);
        if (afKingDailyOnly[caller] == dailyOnly) return;

        uint256 mintableDaily = _claimCoinflipsInternal(caller, false);
        if (mintableDaily != 0) {
            coinflipClaimableStored[caller] += mintableDaily;
        }
        uint256 mintableAfKing = _claimAfKingFlipsInternal(caller, false);
        if (mintableAfKing != 0) {
            afKingClaimableStored[caller] += mintableAfKing;
        }

        afKingDailyOnly[caller] = dailyOnly;
        emit AfKingRngModeUpdated(caller, dailyOnly);
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
        CoinflipDayResult storage dayResult = coinflipDayResult[epoch];
        dayResult.rewardPercent = rewardPercent;
        dayResult.win = win;

        // Bounty resolution: if someone armed the bounty, remove half; if win, credit that half to them.
        uint128 currentBounty_ = currentBounty;
        uint256 slice;
        address to;
        if (bountyOwedTo != address(0) && currentBounty_ > 0) {
            to = bountyOwedTo;
            slice = currentBounty_ >> 1; // pay/delete half of the bounty pool
            unchecked {
                currentBounty_ -= uint128(slice);
            }
            if (win) {
                // Credit as flip stake, not direct mint
                addFlip(to, slice, 0, false, false);
                emit BountyPaid(to, slice);
                game.payCoinflipBountyDgnrs(to);
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

        emit CoinflipFinished(win);
    }

    /// @notice Record afKing flip RNG result (called by game contract).
    function recordAfKingRng(
        uint256 rngWord,
        bool bonusFlip
    ) external onlyDegenerusGameContract {
        if (rngWord == 0) return;

        uint48 epoch = afKingFlipsClaimableEpoch + 1;
        afKingFlipsClaimableEpoch = epoch;

        (uint16 rewardPercent, bool win) = _afKingRngResult(
            rngWord,
            epoch,
            bonusFlip
        );
        afKingFlipResult[epoch] = CoinflipDayResult({
            totalIn: 0,
            totalOut: 0,
            rewardPercent: rewardPercent,
            win: win
        });
        emit AfKingFlipRecorded(epoch, rewardPercent, win);
    }

    /// @dev Calculate afKing RNG result.
    function _afKingRngResult(
        uint256 rngWord,
        uint48 epoch,
        bool bonusFlip
    ) private view returns (uint16 rewardPercent, bool win) {
        uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

        uint256 roll = seedWord % 20;
        if (roll == 0) {
            rewardPercent = 50;
        } else if (roll == 1) {
            rewardPercent = 150;
        } else {
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
        } else if (bonusFlip) {
            (uint256 prevTotal, uint256 currentTotal) = game
                .lastPurchaseDayFlipTotals();
            int256 evBps = _coinflipTargetEvBps(prevTotal, currentTotal);
            rewardPercent = _applyEvToRewardPercent(rewardPercent, evBps);
        }

        win = (seedWord & 1) == 1;
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
        addFlip(player, amount, 0, false, false);
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
                addFlip(player, amount, 0, false, false);
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
        uint256 afKing = _viewClaimableAfKing(player);
        uint256 stored = coinflipClaimableStored[player] + afKingClaimableStored[player];
        return daily + afKing + stored;
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
        enabled = coinflipAutoRebuyEnabled[player];
        stop = coinflipAutoRebuyStop[player];
        carry = coinflipAutoRebuyCarry[player];
        startDay = coinflipAutoRebuyStartDay[player];
    }

    /// @notice Get player's afKing daily-only mode.
    function afKingDailyOnlyMode(address player) external view returns (bool dailyOnly) {
        return afKingDailyOnly[player];
    }

    /// @notice Get last day's coinflip leaderboard winner.
    function coinflipTopLastDay()
        external
        view
        returns (address player, uint128 score)
    {
        uint48 lastDay = flipsClaimableDay;
        if (lastDay == 0) return (address(0), 0);
        PlayerScore storage top = coinflipTopByDay[lastDay];
        return (top.player, top.score);
    }

    /// @dev View helper for daily coinflip claimable winnings.
    function _viewClaimableCoin(
        address player
    ) internal view returns (uint256 total) {
        // Pending flip winnings within the claim window; staking removed.
        uint48 latestDay = flipsClaimableDay;
        uint48 startDay = lastCoinflipClaim[player];
        if (startDay >= latestDay) return 0;

        bool dailyOnlyPenalty = afKingDailyOnly[player] &&
            degenerusGame.afKingModeFor(player);

        uint8 windowDays = _claimWindowDays(player);
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
        uint48 cursor = startDay + 1;
        while (remaining != 0 && cursor <= latestDay) {
            CoinflipDayResult storage result = coinflipDayResult[cursor];
            // Unresolved day detection: both fields zero means day not yet settled
            if (result.rewardPercent == 0 && !result.win) break;

            uint256 flipStake = coinflipBalance[cursor][player];
            if (flipStake != 0 && result.win) {
                // Payout = principal + (principal * rewardPercent%)
                uint256 payout = flipStake +
                    (flipStake * uint256(result.rewardPercent)) /
                    100;
                if (dailyOnlyPenalty) {
                    uint256 penalty = (flipStake *
                        uint256(AFKING_DAILY_ONLY_WIN_PENALTY_BPS)) /
                        BPS_DENOMINATOR;
                    payout -= penalty;
                }
                total += payout;
            }
            unchecked {
                ++cursor;
                --remaining;
            }
        }
    }

    /// @dev View helper for afKing coinflip claimable winnings.
    function _viewClaimableAfKing(
        address player
    ) internal view returns (uint256 total) {
        uint48 latestEpoch = afKingFlipsClaimableEpoch;
        uint48 startEpoch = afKingLastClaim[player];
        if (startEpoch >= latestEpoch) return 0;

        uint8 windowEpochs = _claimWindowEpochs(startEpoch);
        uint48 minClaimableEpoch;
        unchecked {
            minClaimableEpoch = latestEpoch > windowEpochs
                ? latestEpoch - windowEpochs
                : 0;
        }
        if (startEpoch < minClaimableEpoch) {
            startEpoch = minClaimableEpoch;
        }

        uint8 remaining = windowEpochs;
        uint48 cursor = startEpoch + 1;
        while (remaining != 0 && cursor <= latestEpoch) {
            CoinflipDayResult storage result = afKingFlipResult[cursor];
            if (result.rewardPercent == 0 && !result.win) break;

            uint256 flipStake = afKingFlipBalance[cursor][player];
            if (flipStake != 0 && result.win) {
                uint256 payout = flipStake +
                    (flipStake * uint256(result.rewardPercent)) /
                    100;
                total += payout;
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

    /// @dev Check if coinflip deposits are locked during level jackpot resolution.
    function _coinflipLockedDuringLevelJackpot()
        private
        view
        returns (bool locked)
    {
        (
            ,
            uint8 gameState_,
            bool lastPurchaseDay_,
            bool rngLocked_,

        ) = degenerusGame.purchaseInfo();
        locked = (gameState_ == 2) && lastPurchaseDay_ && rngLocked_;
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
    function _afKingRecyclingBonus(
        uint256 amount,
        bool hasDeityPass
    ) private pure returns (uint256 bonus) {
        if (amount == 0) return 0;
        uint16 bonusBps = hasDeityPass
            ? AFKING_RECYCLE_BONUS_BPS + AFKING_DEITY_EDGE_BPS
            : AFKING_RECYCLE_BONUS_BPS;
        bonus = (amount * bonusBps) / BPS_DENOMINATOR;
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
        uint48 currentDayBoundary = uint48(
            (block.timestamp - JACKPOT_RESET_TIME) / 1 days
        );
        uint48 currentDay = currentDayBoundary -
            ContractAddresses.DEPLOY_DAY_BOUNDARY +
            1;
        return currentDay + 1;
    }

    /// @dev Calculate the target epoch for new afKing flip deposits.
    function _targetAfKingEpoch() private view returns (uint48) {
        return afKingFlipsClaimableEpoch + 1;
    }

    /// @dev Helper to process quest rewards and emit event.
    function _questApplyReward(
        address player,
        uint256 reward,
        bool hardMode,
        uint8 questType,
        uint32 streak,
        bool completed,
        bool completedBoth
    ) private returns (uint256) {
        if (!completed) return 0;
        emit QuestCompleted(
            player,
            questType,
            streak,
            reward,
            hardMode,
            completedBoth
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
        }
    }

    /// @dev Calculate claim window days for a player.
    function _claimWindowDays(address player) private view returns (uint8 windowDays) {
        windowDays = lastCoinflipClaim[player] == 0
            ? COIN_CLAIM_FIRST_DAYS
            : COIN_CLAIM_DAYS;
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

    /// @dev Calculate claim window epochs for afKing flips.
    function _claimWindowEpochs(
        uint48 lastClaim
    ) private pure returns (uint8 windowEpochs) {
        windowEpochs = lastClaim == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
    }

    /// @dev Check if caller is approved to act on behalf of player.
    function _requireApproved(address player) private view {
        if (msg.sender != player && !degenerusGame.isOperatorApproved(player, msg.sender)) {
            revert NotApproved();
        }
    }
}
