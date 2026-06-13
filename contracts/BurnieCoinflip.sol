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
 *      - Seeds the initial BURNIE emission as flip stakes (200k/day, days 1-20, to
 *        VAULT and sDGNRS); arms sDGNRS perpetual auto-rebuy after the seed window
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
        uint24 indexed day,
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
        uint24 indexed day,
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
        uint24 indexed day,
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
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint16 private constant COIN_CLAIM_DAYS = 365;
    uint16 private constant COIN_CLAIM_FIRST_DAYS = 30;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1460;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    /// @dev Initial-emission seed stakes: 200k BURNIE per day for days 1-20, each to
    ///      VAULT and sDGNRS. All initial BURNIE must survive a coinflip before minting.
    uint256 private constant SEED_FLIP_DAILY = 200_000 ether;
    uint24 private constant SEED_FLIP_DAYS = 20;
    IDegenerusQuests internal constant questModule =
        IDegenerusQuests(ContractAddresses.QUESTS);

    // Player coinflip state (packed where possible)
    struct PlayerCoinflipState {
        uint128 claimableStored;
        uint24 lastClaim;
        uint24 autoRebuyStartDay;
        bool autoRebuyEnabled;
        uint128 autoRebuyStop;
        uint128 autoRebuyCarry;
    }

    // Daily coinflip storage. coinflipStakePacked banks 2 days per slot (key =
    // day>>1, 128-bit wei lanes, lossless — flip credits can be sub-1-BURNIE);
    // coinflipDayResultPacked banks 32 days per slot (key = day>>5, 8-bit lanes,
    // 3-state). Access via the helpers.
    mapping(uint24 => mapping(address => uint256)) internal coinflipStakePacked;
    mapping(uint24 => uint256) internal coinflipDayResultPacked;
    mapping(address => PlayerCoinflipState) internal playerState;


    // Bounty system
    uint128 public currentBounty = 1_000 ether;
    uint128 public biggestFlipEver;
    address internal bountyOwedTo;

    // RNG state (packs with bountyOwedTo)
    uint24 internal flipsClaimableDay;
    /// @dev One-shot latch: sDGNRS perpetual auto-rebuy arms once the final seeded day settles.
    bool internal sdgnrsAutoRebuyArmed;

    // Leaderboard
    struct PlayerScore {
        address player;
        uint96 score;
    }
    mapping(uint24 => PlayerScore) internal coinflipTopByDay;

    /// @notice Seeds the initial BURNIE emission as flip stakes: 200k per day for days 1-20,
    ///         each to VAULT and sDGNRS. Direct storage writes (not _addDailyFlip) keep the
    ///         seeds off the daily top-bettor leaderboard and the bounty/biggest-flip records.
    ///         Nothing mints up front — each day's seed only becomes claimable BURNIE if it
    ///         survives that day's flip.
    constructor() {
        for (uint24 d = 1; d <= SEED_FLIP_DAYS; ) {
            _setFlipStake(d, ContractAddresses.VAULT, SEED_FLIP_DAILY);
            _setFlipStake(d, ContractAddresses.SDGNRS, SEED_FLIP_DAILY);
            emit CoinflipStakeUpdated(ContractAddresses.VAULT, d, SEED_FLIP_DAILY, SEED_FLIP_DAILY);
            emit CoinflipStakeUpdated(ContractAddresses.SDGNRS, d, SEED_FLIP_DAILY, SEED_FLIP_DAILY);
            unchecked {
                ++d;
            }
        }
    }

    /*+======================================================================+
      |                         MODIFIERS                                    |
      +======================================================================+*/

    modifier onlyDegenerusGameContract() {
        if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();
        _;
    }

    /// @notice Restricts access to authorized flip creditors.
    /// @dev Allowed callers: GAME (delegatecall modules — incl. the afking router's
    ///      in-context creditFlip bounty, which pays AS the GAME, not a separate keeper contract),
    ///      QUESTS (level quest rewards), AFFILIATE, ADMIN, SDGNRS (redemption flip-credit at
    ///      submit via redeemBurnieShare — net BURNIE neutral, offset by burn+consume).
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.QUESTS &&
            sender != ContractAddresses.AFFILIATE &&
            sender != ContractAddresses.ADMIN &&
            sender != ContractAddresses.SDGNRS
        ) revert OnlyFlipCreditors();
        _;
    }

    /// @dev Restricts access to BurnieCoin, which claims/consumes a player's unclaimed
    ///      coinflip winnings to cover transfer and burn shortfalls.
    modifier onlyBurnieCoin() {
        if (msg.sender != ContractAddresses.COIN) revert OnlyBurnieCoin();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Deposit BURNIE into daily coinflip system.
    /// @param player The depositor (address(0) or msg.sender for self-deposit, otherwise operator-approved).
    /// @param amount Amount of BURNIE to deposit (min 100 BURNIE, or 0 to settle pending claims).
    function depositCoinflip(address player, uint256 amount) external {
        address caller = _resolvePlayer(player);
        _depositCoinflip(caller, amount, caller == msg.sender);
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
        // storedAfter mirrors claimableStored through this frame; no call below can
        // mutate it (burnForCoinflip and handleFlip never reach a claimable writer).
        uint128 storedAfter = state.claimableStored;
        if (mintable != 0) {
            storedAfter = uint128(uint256(storedAfter) + mintable);
            state.claimableStored = storedAfter;
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
            : uint256(storedAfter);
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

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win) {
        return _dayResult(day);
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
        uint24 latest = flipsClaimableDay;
        uint24 start = state.lastClaim;

        bool rebuyActive = state.autoRebuyEnabled;
        bool deep = deepAutoRebuy && rebuyActive;
        uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;
        uint256 carry;
        uint256 winningBafCredit;
        uint24 bafResolvedDay;
        bool bafResolvedDayCached;
        uint256 lossCount;

        uint256 oldCarry = state.autoRebuyCarry;
        if (rebuyActive) {
            carry = oldCarry;
        } else if (oldCarry != 0) {
            mintable += oldCarry;
            state.autoRebuyCarry = 0;
        }

        if (start >= latest) return mintable;

        // Enforce claim window unless auto-rebuy is enabled (settles back to enable day).
        uint16 windowDays = start == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint24 minClaimableDay;
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

        uint24 cursor;
        unchecked {
            cursor = start + 1;
        }
        uint24 processed = start;

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
            (uint16 rewardPercent, bool win) = _dayResult(cursor);

            // Skip unresolved days (gaps from testnet day-advance or missed resolution)
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            uint256 storedStake = _flipStake(cursor, player);
            uint256 stake = storedStake;
            if (rebuyActive && carry != 0) {
                stake += carry;
            }

            if (storedStake != 0) {
                // Clear stake whether win or loss (loss = forfeit principal)
                _setFlipStake(cursor, player, 0);
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

        // sDGNRS gets no BAF score: skip the recordBafFlip call entirely for it. This is also
        // load-bearing for advanceGame — the daily coinflip resolution auto-claims sDGNRS here,
        // and skipping the BAF section keeps that path off the rngLocked guard below.
        if (winningBafCredit != 0 && player != ContractAddresses.SDGNRS) {
            (
                uint24 purchaseLevel_,
                bool inJackpotPhase,
                bool lastPurchaseDay_,
                bool rngLocked_,

            ) = game.purchaseInfo();
            // The active ticket level is level+1 during the purchase phase and level
            // during the jackpot phase, so the game level derives from the same
            // atomic purchaseInfo snapshot (purchaseLevel_ >= 1 outside jackpot phase).
            uint24 cachedLevel = inJackpotPhase
                ? purchaseLevel_
                : purchaseLevel_ - 1;
            // lastPurchaseDay_ is true only outside the jackpot phase, so it alone
            // restricts this guard to purchase-phase states. No game-over state can
            // reach it: every gameOver latch leaves jackpotPhaseFlag set or
            // lastPurchaseDay false, and neither is ever written again post-latch.
            if (
                lastPurchaseDay_ &&
                rngLocked_ &&
                cachedLevel != 0 &&
                cachedLevel % 10 == 0
            ) {
                revert RngLocked();
            }
            uint24 bafLevel = cachedLevel;
            if (!inJackpotPhase) {
                bafLevel = purchaseLevel_;
            } else if (cachedLevel != 0 && cachedLevel % 10 == 0) {
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
        uint24 targetDay = _targetFlipDay();

        uint256 prevStake = _flipStake(targetDay, player);
        uint256 newStake = prevStake + coinflipDeposit;

        // Update player's stake for target day
        _setFlipStake(targetDay, player, newStake);
        _updateTopDayBettor(player, newStake, targetDay);
        emit CoinflipStakeUpdated(player, targetDay, coinflipDeposit, newStake);

        // Bounty logic: only when RNG not locked (prevents manipulation after VRF request).
        // Uses the raw deposit amount (recordAmount), not bonuses or existing stake.
        if (canArmBounty && bountyEligible && recordAmount != 0) {
            uint128 record = biggestFlipEver;
            if (recordAmount > record && !game.rngLocked()) {
                address currentBountyOwner = bountyOwedTo;
                uint128 bounty = currentBounty;
                // recordAmount fits uint128: it was already burned via BurnieCoin._burn,
                // whose supply accounting bounds every burn amount to uint128.
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
        if (fromGame) {
            if (player == address(0)) player = msg.sender;
        } else {
            player = _resolvePlayer(player);
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
                state.autoRebuyStop = uint128(takeProfit);
                state.autoRebuyEnabled = true;
                state.autoRebuyStartDay = state.lastClaim;
                emit CoinflipAutoRebuyStopSet(player, takeProfit);
                emit CoinflipAutoRebuyToggled(player, true);
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

    /// @notice Claim up to `amount` of the auto-rebuy carry as minted BURNIE while
    ///         staying on auto-rebuy; the remainder keeps rolling.
    /// @dev Settles all resolved days FIRST — wins roll into the carry per the
    ///      take-profit config and a pending loss zeroes it — then withdraws from the
    ///      settled carry. Blocked during the RNG lock for the same reason as the
    ///      rebuy toggle: the carry is the pending day's stake, and the day's word may
    ///      already be on-chain before the resolution walk applies it. Take-profit
    ///      chunks surfaced by the settle bank into claimableStored (claimCoinflips
    ///      territory); this function pays out of the carry only.
    /// @param player The player to claim for (address(0) for msg.sender, else operator-approved).
    /// @param amount Maximum carry to claim.
    /// @return claimed Actual amount of BURNIE minted from the carry.
    function claimCoinflipCarry(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        player = _resolvePlayer(player);
        if (degenerusGame.rngLocked()) revert RngLocked();
        PlayerCoinflipState storage state = playerState[player];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();

        uint256 mintable = _claimCoinflipsInternal(player, false);
        if (mintable != 0) {
            state.claimableStored = uint128(
                uint256(state.claimableStored) + mintable
            );
        }

        uint256 carry = state.autoRebuyCarry;
        claimed = amount < carry ? amount : carry;
        if (claimed != 0) {
            unchecked {
                state.autoRebuyCarry = uint128(carry - claimed);
            }
            burnie.mintForGame(player, claimed);
        }
    }

    /*+======================================================================+
      |                    RNG PROCESSING                                    |
      +======================================================================+*/

    /// @notice Process coinflip payout for a day (called by game contract).
    /// @param bonus Reward-percent bonus for this day, precomputed by the caller from frozen state:
    ///        0 = normal day, 2 = bonus day (level 0 or a first jackpot day), 6 = x0-level bonus day.
    /// @param rngWord VRF-derived random word for determining win/loss and bonus.
    /// @param epoch The day index being resolved.
    function processCoinflipPayouts(
        uint8 bonus,
        uint256 rngWord,
        uint24 epoch
    ) external onlyDegenerusGameContract {
        // Mix entropy with epoch for unique per-day randomness
        uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

        // Determine payout bonus percent:
        // ~5% each for extreme bonus outcomes (50% or 150%), rest is [78%, 115%]
        // Bonus days add +2 (or +6 on x0 levels), so max is 156% on an x0 bonus day
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
        // Apply the day's coinflip bonus, precomputed by the caller from frozen protocol state
        // (not a player-flippable flag): 0 on a normal day, +2 on a bonus day (level 0 or a
        // level's first jackpot day), +6 on a post-BAF x0-level bonus day. Sized so a recycling
        // player nets ~99.9% / ~101.9% RTP after the recycle bonus compounds. Adding 0 is a no-op.
        unchecked {
            rewardPercent += bonus;
        }

        // Preserve original 50/50 win roll.
        bool win = (rngWord & 1) == 1;

        // Record the day's result for future claims
        _storeDayResult(epoch, rewardPercent, win);

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
        uint128 newBounty;
        unchecked {
            // Gas-optimized: wraps on overflow, which would effectively reset the bounty.
            newBounty = currentBounty_ + uint128(PRICE_COIN_UNIT);
        }
        currentBounty = newBounty;

        emit CoinflipDayResolved(
            epoch,
            win,
            rewardPercent,
            newBounty,
            bountyPaid,
            to
        );

        // Keep sDGNRS's flip cursor current (BAF is skipped for sDGNRS, so both paths
        // stay off the rngLocked guard). During the seed window each settled win is
        // claimed straight to its wallet balance, where it backs redemptions. Once
        // auto-rebuy is armed, winnings are NEVER claimed: they settle into the
        // rolling carry (the return is structurally zero under 0-take-profit rebuy)
        // and BURNIE leaves sDGNRS's flip position solely through a redemption's
        // burn+consume leg.
        if (sdgnrsAutoRebuyArmed) {
            _claimCoinflipsInternal(ContractAddresses.SDGNRS, false);
        } else {
            _claimCoinflipsAmount(ContractAddresses.SDGNRS, type(uint256).max, true);

            // Once the final seeded day settles, sDGNRS goes on perpetual auto-rebuy
            // (0 take-profit): every later flip credit rolls win-after-win until a loss.
            if (epoch >= SEED_FLIP_DAYS) {
                sdgnrsAutoRebuyArmed = true;
                PlayerCoinflipState storage sdgnrsState = playerState[
                    ContractAddresses.SDGNRS
                ];
                sdgnrsState.autoRebuyEnabled = true;
                sdgnrsState.autoRebuyStartDay = sdgnrsState.lastClaim;
                emit CoinflipAutoRebuyToggled(ContractAddresses.SDGNRS, true);
            }
        }
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
        uint24 targetDay = _targetFlipDay();
        return _flipStake(targetDay, player);
    }

    /// @notice Get player's auto-rebuy configuration.
    function coinflipAutoRebuyInfo(address player)
        external
        view
        returns (
            bool enabled,
            uint256 stop,
            uint256 carry,
            uint24 startDay
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
        uint24 lastDay = flipsClaimableDay;
        if (lastDay == 0) return (address(0), 0);
        PlayerScore memory top = coinflipTopByDay[lastDay];
        return (top.player, uint128(top.score));
    }

    /// @dev View helper for daily coinflip claimable winnings.
    function _viewClaimableCoin(
        address player
    ) internal view returns (uint256 total) {
        // Pending flip winnings within the claim window; staking removed.
        uint24 latestDay = flipsClaimableDay;
        uint24 startDay = playerState[player].lastClaim;
        if (startDay >= latestDay) return 0;

        uint16 windowDays = startDay == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint24 minClaimableDay;
        unchecked {
            minClaimableDay = latestDay > windowDays
                ? latestDay - windowDays
                : 0;
        }
        if (startDay < minClaimableDay) {
            startDay = minClaimableDay;
        }

        uint16 remaining = windowDays;
        uint24 cursor;
        unchecked {
            cursor = startDay + 1;
        }
        while (remaining != 0 && cursor <= latestDay) {
            (uint16 rewardPercent, bool win) = _dayResult(cursor);
            // Skip unresolved days (both fields zero) instead of breaking,
            // to handle gaps from testnet day-advance or missed resolution.
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            if (win) {
                uint256 flipStake = _flipStake(cursor, player);
                if (flipStake != 0) {
                    // Payout = principal + (principal * rewardPercent%)
                    uint256 payout = flipStake +
                        (flipStake * uint256(rewardPercent)) /
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

    /// @dev Player stake for `day` in wei (2 days/slot, 128-bit lanes, lossless).
    ///      Stored in wei — flip credits (keeper advance rewards, redemption shares)
    ///      can be sub-1-BURNIE, so whole-token granularity would zero them. Fresh
    ///      SLOAD — never cached across the claim loop's external calls.
    function _flipStake(uint24 day, address p) internal view returns (uint256) {
        return uint128(coinflipStakePacked[day >> 1][p] >> ((day & 1) * 128));
    }

    /// @dev Masked write of `day`'s stake lane, preserving the sibling day. weiAmount
    ///      is provably <= uint128 (BurnieCoin caps total supply at uint128, and a
    ///      stake never exceeds supply). Fresh SLOAD/SSTORE.
    function _setFlipStake(uint24 day, address p, uint256 weiAmount) internal {
        uint256 shift = (day & 1) * 128;
        uint24 key = day >> 1;
        uint256 w = coinflipStakePacked[key][p];
        w = (w & ~(uint256(type(uint128).max) << shift)) | (weiAmount << shift);
        coinflipStakePacked[key][p] = w;
    }

    /// @dev Day result for `day` (32 days/slot, 8-bit lanes). 3-state byte:
    ///      0 = unresolved, 1 = resolved loss, 50..156 = resolved win at that reward%.
    ///      win is derived (byte >= 50, since every win stores reward >= 50); losing
    ///      days don't retain the (functionally unused) reward%. Resolution detection
    ///      stays `rewardPercent != 0` — a resolved loss reads back as 1, not 0.
    function _dayResult(uint24 day) internal view returns (uint16 rewardPercent, bool win) {
        uint8 b = uint8(coinflipDayResultPacked[day >> 5] >> ((day & 31) * 8));
        rewardPercent = b;
        win = b >= 50;
    }

    /// @dev Masked write of `day`'s result lane, preserving the other 31 days.
    function _storeDayResult(uint24 day, uint16 rewardPercent, bool win) internal {
        uint256 b = win ? uint256(rewardPercent) : 1; // win: 50..156; loss: nonzero sentinel
        uint256 shift = (day & 31) * 8;
        uint24 key = day >> 5;
        uint256 w = coinflipDayResultPacked[key];
        w = (w & ~(uint256(0xFF) << shift)) | (b << shift);
        coinflipDayResultPacked[key] = w;
    }

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
            ,
            bool lastPurchaseDay_,
            bool rngLocked_,

        ) = degenerusGame.purchaseInfo();
        // Early-return on the purchaseInfo flags so normal days cost a single
        // external read; level is only consulted once those pass.
        // lastPurchaseDay_ is true only outside the jackpot phase, so it alone
        // restricts the lock to purchase-phase states. No game-over state can
        // reach here: every gameOver latch leaves jackpotPhaseFlag set or
        // lastPurchaseDay false, and neither is ever written again post-latch.
        if (!lastPurchaseDay_ || !rngLocked_) return false;
        uint24 lvl = degenerusGame.level();
        locked = lvl != 0 && lvl % 10 == 0;
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
    function _targetFlipDay() internal view returns (uint24) {
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
        uint24 day
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
}
