// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title BurnieCoinflip
 * @author Burnie Degenerus
 * @notice Standalone daily coinflip wagering system for BurnieCoin
 *
 * @dev ARCHITECTURE:
 *      - Extracted from BurnieCoin to reduce contract size
 *      - Manages the daily coinflip system with a flat recycle bonus
 *      - Integrates with BurnieCoin for burn/mint operations
 *      - Handles the bounty system and quest rewards
 *
 * @dev INTERACTIONS:
 *      - Burns BURNIE from players on deposit (via BurnieCoin.burnForCoinflip)
 *      - Mints BURNIE to players on claim (via BurnieCoin.mintForGame)
 *      - Receives quest flip credits from game contract
 *      - Processes RNG results for payout calculations
 */

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

/// @notice Interface for BurnieCoin contract methods used by BurnieCoinflip.
interface IBurnieCoin {
    /// @notice Burn BURNIE from a player for coinflip deposit.
    function burnForCoinflip(address from, uint256 amount) external;
    /// @notice Mint BURNIE to a player (coinflip claims, degenerette wins).
    function mintForGame(address to, uint256 amount) external;
    /// @notice Get the BURNIE balance of an address.
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Interface for WWXRP contract methods used by BurnieCoinflip.
interface IWrappedWrappedXRP {
    /// @notice Mint WWXRP consolation prize to a player on coinflip loss.
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
        uint32 indexed day,
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
        uint32 indexed day,
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
        uint32 indexed day,
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
    error OnlyStakedDegenerusStonk();
    error OnlyDegenerusGame();
    error AutoRebuyNotEnabled();
    error AutoRebuyAlreadyEnabled();
    error RngLocked();
    error Insufficient();
    error NotApproved();

    /*+======================================================================+
      |                         STORAGE VARIABLES                            |
      +======================================================================+*/

    // Constant contract references (addresses from ContractAddresses)
    IBurnieCoin public constant burnie = IBurnieCoin(ContractAddresses.COIN);
    IDegenerusGame public constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);
    IDegenerusJackpots public constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IWrappedWrappedXRP public constant wwxrp = IWrappedWrappedXRP(ContractAddresses.WWXRP);

    // Constants
    uint256 private constant MIN = 100 ether;
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 1 ether;
    uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;
    uint16 private constant COINFLIP_EXTRA_RANGE = 38;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant RECYCLE_BONUS_BPS = 75;
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint8 private constant COIN_CLAIM_DAYS = 90;
    uint8 private constant COIN_CLAIM_FIRST_DAYS = 30;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1095;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
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
        uint32 lastClaim;
        uint32 autoRebuyStartDay;
        bool autoRebuyEnabled;
        uint128 autoRebuyStop;
        uint128 autoRebuyCarry;
    }

    // Daily coinflip storage
    mapping(uint32 => mapping(address => uint256)) internal coinflipBalance;
    mapping(uint32 => CoinflipDayResult) internal coinflipDayResult;
    mapping(address => PlayerCoinflipState) internal playerState;


    // Bounty system
    uint128 public currentBounty = 1_000 ether;
    uint128 public biggestFlipEver;
    address internal bountyOwedTo;

    // RNG state
    uint32 internal flipsClaimableDay;

    // Leaderboard
    struct PlayerScore {
        address player;
        uint96 score;
    }
    mapping(uint32 => PlayerScore) internal coinflipTopByDay;

    // No constructor needed — all contract references are compile-time constants.

    /*+======================================================================+
      |                         MODIFIERS                                    |
      +======================================================================+*/

    modifier onlyDegenerusGameContract() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();
        _;
    }

    /// @notice Restricts access to authorized flip creditors.
    /// @dev Allowed callers: GAME (delegatecall modules), QUESTS (level quest rewards), AFFILIATE, ADMIN,
    ///      AF_KING (keeper sweep bounty, gas-pegged creditFlip), SDGNRS (redemption flip-credit at
    ///      submit via redeemBurnieShare — net BURNIE neutral, offset by burn+consume).
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.QUESTS &&
            sender != ContractAddresses.AFFILIATE &&
            sender != ContractAddresses.ADMIN &&
            sender != ContractAddresses.AF_KING &&
            sender != ContractAddresses.SDGNRS
        ) revert OnlyFlipCreditors();
        _;
    }

    /// @dev Restricts access to the burn-consume callers: BurnieCoin (shortfall consume for burns)
    ///      and SDGNRS (consume its own coinflip stake during redemption settle).
    modifier onlyBurnieCoin() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.COIN &&
            sender != ContractAddresses.SDGNRS
        ) revert OnlyBurnieCoin();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Deposit BURNIE into daily coinflip system.
    /// @param player The depositor (address(0) or msg.sender for self-deposit, otherwise operator-approved).
    /// @param amount Amount of BURNIE to deposit (min 100 BURNIE, or 0 to settle pending claims).
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
            // Block deposits during BAF jackpot resolution to prevent
            // auto-claim from updating the BAF leaderboard mid-resolution.
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
        uint256 creditedFlip = amount + questReward;
        uint256 rollAmount = state.autoRebuyEnabled
            ? state.autoRebuyCarry
            : uint256(state.claimableStored);
        uint256 rebetAmount = creditedFlip <= rollAmount
            ? creditedFlip
            : rollAmount;
        if (rebetAmount != 0) {
            // Recycling bonus applies only to the rebet portion (not fresh money).
            creditedFlip += _recyclingBonus(rebetAmount);
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
    /// @dev Processes resolved days and claims from claimableStored (accumulated from
    ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
    /// @param player The player to claim for (address(0) for msg.sender, else operator-approved).
    /// @param amount Maximum BURNIE to claim (actual may be less if insufficient claimable).
    /// @return claimed Actual amount of BURNIE minted and claimed.
    function claimCoinflips(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        return _claimCoinflipsAmount(_resolvePlayer(player), amount, true);
    }

    /// @notice Claim coinflip winnings via BurnieCoin to cover token transfers/burns.
    /// @dev Access: BurnieCoin only. Processes resolved days and claims from claimableStored.
    ///      Auto-rebuy carry is never exposed to this path.
    /// @param player The player whose coinflip winnings to claim.
    /// @param amount Maximum BURNIE to claim.
    /// @return claimed Actual amount of BURNIE minted and claimed.
    function claimCoinflipsFromBurnie(
        address player,
        uint256 amount
    ) external onlyBurnieCoin returns (uint256 claimed) {
        return _claimCoinflipsAmount(player, amount, true);
    }

    /// @notice Claim coinflip winnings for sDGNRS redemption (skips RNG lock).
    /// @dev Access: sDGNRS only. Used during claimRedemption() when wallet balance
    ///      is insufficient and coinflip winnings need to be sourced.
    /// @param player The player whose coinflip winnings to claim.
    /// @param amount Maximum BURNIE to claim.
    /// @return claimed Actual amount of BURNIE minted and claimed.
    function claimCoinflipsForRedemption(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();
        return _claimCoinflipsAmount(player, amount, true);
    }

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win) {
        CoinflipDayResult memory result = coinflipDayResult[day];
        return (result.rewardPercent, result.win);
    }

    /// @notice Consume coinflip winnings via BurnieCoin for burns (no mint).
    /// @dev Access: BurnieCoin only. Same safety as claimCoinflipsFromBurnie —
    ///      only claimableStored is consumable, carry stays in autoRebuyCarry.
    /// @param player The player whose coinflip winnings to consume.
    /// @param amount Maximum BURNIE to consume.
    /// @return consumed Actual amount of BURNIE consumed (deducted from claimable, no token mint).
    function consumeCoinflipsForBurn(
        address player,
        uint256 amount
    ) external onlyBurnieCoin returns (uint256 consumed) {
        return _claimCoinflipsAmount(player, amount, false);
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
                burnie.mintForGame(player, toClaim);
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
        uint32 latest = flipsClaimableDay;
        uint32 start = state.lastClaim;

        bool rebuyActive = state.autoRebuyEnabled;
        bool deep = deepAutoRebuy && rebuyActive;
        uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;
        uint256 carry;
        uint256 winningBafCredit;
        uint32 bafResolvedDay;
        bool bafResolvedDayCached;
        uint256 lossCount;
        bool levelCached;
        uint24 cachedLevel;

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
        uint32 minClaimableDay;
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

        uint32 cursor;
        unchecked {
            cursor = start + 1;
        }
        uint32 processed = start;

        uint32 remaining;
        if (deep) {
            uint32 available = latest - start;
            uint32 cap = available > AUTO_REBUY_OFF_CLAIM_DAYS_MAX
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
                    if (!bafResolvedDayCached) {
                        bafResolvedDay = jackpots.getLastBafResolvedDay();
                        bafResolvedDayCached = true;
                    }
                    if (cursor >= bafResolvedDay) {
                        winningBafCredit += payout;
                    }
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
                            carry += _recyclingBonus(carry);
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

        // sDGNRS is excluded from BAF in jackpots (recordBafFlip returns early).
        // Skip the BAF section entirely so this path doesn't hit the rngLocked guard
        // when called from processCoinflipPayouts during advanceGame.
        if (winningBafCredit != 0 && player != ContractAddresses.SDGNRS) {
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
                cachedLevel != 0 &&
                cachedLevel % 10 == 0
            ) {
                revert RngLocked();
            }
            uint24 bafLevel = cachedLevel;
            if (!inJackpotPhase && !over) {
                bafLevel = purchaseLevel_;
            } else if (inJackpotPhase && cachedLevel != 0 && cachedLevel % 10 == 0) {
                bafLevel = cachedLevel + 1;
            }
            uint24 bafLvl = _bafBracketLevel(bafLevel);
            jackpots.recordBafFlip(player, bafLvl, winningBafCredit);
        }

        // Update last claim pointer if we processed any days
        if (processed != start) {
            state.lastClaim = processed;
        }

        if (rebuyActive && oldCarry != carry) {
            // Safe truncation: carry is bounded by a single day's coinflip payout; uint128 max is unreachable.
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
        uint32 targetDay = _targetFlipDay();

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
    /// @param player The player to configure (address(0) for msg.sender).
    /// @param enabled True to enable auto-rebuy, false to disable and cash out carry.
    /// @param takeProfit Amount reserved from wins before rolling remainder (0 = roll all).
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
    /// @param player The player to configure (address(0) for msg.sender, else operator-approved).
    /// @param takeProfit New take-profit threshold (0 = roll all winnings).
    function setCoinflipAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) external {
        _setCoinflipAutoRebuyTakeProfit(_resolvePlayer(player), takeProfit);
    }

    /// @dev Internal auto-rebuy configuration.
    ///      Blocked during RNG lock — toggling off would extract carry before a known loss.
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
        }

        if (mintable != 0) {
            burnie.mintForGame(player, mintable);
        }
    }

    /// @dev Internal auto-rebuy take profit configuration.
    ///      Blocked during RNG lock — changing take-profit could extract carry before a known loss.
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
            burnie.mintForGame(player, mintable);
        }
    }

    /*+======================================================================+
      |                    RNG PROCESSING                                    |
      +======================================================================+*/

    /// @notice Process coinflip payout for a day (called by game contract).
    /// @param bonusFlip True if presale lootbox bonus applies to this day.
    /// @param rngWord VRF-derived random word for determining win/loss and bonus.
    /// @param epoch The day index being resolved.
    function processCoinflipPayouts(
        bool bonusFlip,
        uint256 rngWord,
        uint32 epoch
    ) external onlyDegenerusGameContract {
        // Mix entropy with epoch for unique per-day randomness
        uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

        // Determine payout bonus percent:
        // ~5% each for extreme bonus outcomes (50% or 150%), rest is [78%, 115%]
        // Presale bonus adds +6pp, so max is 156% during presale
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
                game.payCoinflipBountyDgnrs(to, slice, currentBounty_);
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

        // Keep sDGNRS flip cursor current — reuses _claimCoinflipsInternal
        // (BAF skipped for sDGNRS, no rngLocked guard on this path).
        _claimCoinflipsInternal(ContractAddresses.SDGNRS, false);
    }

    /*+======================================================================+
      |                    FLIP CREDITING                                    |
      +======================================================================+*/

    /// @notice Credit flip to a player (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of BURNIE-denominated flip stake to credit.
    function creditFlip(
        address player,
        uint256 amount
    ) external onlyFlipCreditors {
        if (player == address(0) || amount == 0) return;
        _addDailyFlip(player, amount, 0, false, false);
    }

    /// @notice Credit flips to multiple players (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
    /// @param players Array of 3 player addresses to credit (address(0) entries are skipped).
    /// @param amounts Array of 3 BURNIE-denominated flip stake amounts (0 entries are skipped).
    function creditFlipBatch(
        address[] calldata players,
        uint256[] calldata amounts
    ) external onlyFlipCreditors {
        uint256 len = players.length;
        for (uint256 i; i < len; ) {
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

    /// @notice Settle a redemption's BURNIE share entirely at submit (sDGNRS only).
    /// @dev Atomic, BURNIE-conserving: destroys `base` of sDGNRS's own BURNIE backing (held
    ///      balance first, then its coinflip stake), then credits an equal flip stake to the
    ///      redeemer. The deferred creditFlip mint of `base` is exactly offset by the burn+consume,
    ///      so net new BURNIE across the call == 0.
    ///      Airtight by construction: sDGNRS computes base = (held + stake) * amount / supply at
    ///      submit, so base <= held + stake and the burn→consume waterfall always covers base.
    /// @param redeemer The player receiving the flip credit.
    /// @param base The proportional BURNIE backing to settle (no roll — BURNIE gambles via the flip).
    function redeemBurnieShare(address redeemer, uint256 base) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk();
        if (base == 0) return;

        // Burn from sDGNRS's held wallet balance first via the COINFLIP-gated burn
        // (this contract IS COINFLIP; burnForCoinflip is BurnieCoin's generic _burn entry).
        uint256 held = burnie.balanceOf(ContractAddresses.SDGNRS);
        uint256 burnFromHeld = base <= held ? base : held;
        if (burnFromHeld != 0) {
            burnie.burnForCoinflip(ContractAddresses.SDGNRS, burnFromHeld);
        }

        // Consume the remainder from sDGNRS's own coinflip stake (no token mint — this removes a
        // future mint of `remainder`, the conservation analogue of the held-balance burn above).
        uint256 remainder = base - burnFromHeld;
        if (remainder != 0) {
            uint256 consumed = _claimCoinflipsAmount(ContractAddresses.SDGNRS, remainder, false);
            // Defense-in-depth: airtight by construction (remainder <= claimable stake), but
            // fail-closed rather than over-credit if the stake somehow falls short.
            if (consumed < remainder) revert Insufficient();
        }

        // Deferred mint of `base` to the redeemer, offset 1:1 by the burn+consume ⇒ conserved.
        _addDailyFlip(redeemer, base, 0, false, false);
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
        uint32 targetDay = _targetFlipDay();
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
            uint32 startDay
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
        uint32 lastDay = flipsClaimableDay;
        if (lastDay == 0) return (address(0), 0);
        PlayerScore memory top = coinflipTopByDay[lastDay];
        return (top.player, uint128(top.score));
    }

    /// @dev View helper for daily coinflip claimable winnings.
    function _viewClaimableCoin(
        address player
    ) internal view returns (uint256 total) {
        // Pending flip winnings within the claim window; staking removed.
        uint32 latestDay = flipsClaimableDay;
        uint32 startDay = playerState[player].lastClaim;
        if (startDay >= latestDay) return 0;

        uint8 windowDays = startDay == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint32 minClaimableDay;
        unchecked {
            minClaimableDay = latestDay > windowDays
                ? latestDay - windowDays
                : 0;
        }
        if (startDay < minClaimableDay) {
            startDay = minClaimableDay;
        }

        uint8 remaining = windowDays;
        uint32 cursor;
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
    ///      Only blocks at levels where BAF jackpot fires (every 10th). Deposits
    ///      trigger auto-claim which records BAF leaderboard credit — must block
    ///      to prevent front-running the leaderboard between VRF request and fulfillment.
    function _coinflipLockedDuringTransition()
        private
        view
        returns (bool locked)
    {
        (
            ,
            bool inJackpotPhase,
            bool lastPurchaseDay_,
            bool rngLocked_,

        ) = degenerusGame.purchaseInfo();
        uint24 lvl = degenerusGame.level();
        locked = (!inJackpotPhase) && !degenerusGame.gameOver() && lastPurchaseDay_ && rngLocked_ && lvl != 0 && (lvl % 10 == 0);
    }

    /// @dev Calculate recycling bonus for daily flip deposits (0.75% bonus, capped at 1000 BURNIE).
    ///      Base is total claimableStored (all accumulated unclaimed winnings).
    ///      Bonus feeds into creditedFlip, not back into claimableStored (no feedback loop).
    function _recyclingBonus(
        uint256 amount
    ) private pure returns (uint256 bonus) {
        if (amount == 0) return 0;
        bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR);
        uint256 bonusCap = 1000 ether;
        if (bonus > bonusCap) bonus = bonusCap;
    }

    /// @dev Calculate the target day for new coinflip deposits.
    ///      Derived locally from GameTimeLib — the same time-only source that
    ///      DegenerusGame.currentDayView resolves to — so this equals the game's
    ///      day index without a cross-contract call.
    function _targetFlipDay() internal view returns (uint32) {
        return GameTimeLib.currentDayIndex() + 1;
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
        uint32 day
    ) private {
        uint96 score = _score96(stakeScore);
        PlayerScore memory dayLeader = coinflipTopByDay[day];
        if (score > dayLeader.score || dayLeader.player == address(0)) {
            coinflipTopByDay[day] = PlayerScore({player: player, score: score});
            emit CoinflipTopUpdated(day, player, score);
        }
    }

    /// @dev Round level up to next BAF bracket (multiple of 10).
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
                revert NotApproved();
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
