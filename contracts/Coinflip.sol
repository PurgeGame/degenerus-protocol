// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/**
 * @title Coinflip
 * @author Burnie Degenerus
 * @notice Standalone daily coinflip wagering system for FLIP
 *
 * @dev ARCHITECTURE:
 *      - A standalone contract separate from FLIP, keeping FLIP within its size budget
 *      - Manages the daily coinflip system with a flat recycle bonus
 *      - Integrates with FLIP for burn/mint operations
 *      - Handles the bounty system and quest rewards
 *      - Seeds the initial FLIP emission as flip stakes (200k/day, days 1-20, to
 *        VAULT and sDGNRS); arms sDGNRS perpetual auto-rebuy after the seed window
 *
 * @dev INTERACTIONS:
 *      - Burns FLIP from players on deposit (via FLIP.burnForCoinflip)
 *      - Mints FLIP to players on claim (via FLIP.mintForGame)
 *      - Receives quest flip credits from game contract
 *      - Processes RNG results for payout calculations
 */

import {IDegenerusGame} from "./interfaces/IDegenerusGame.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

/// @notice Interface for FLIP contract methods used by Coinflip.
interface IFLIP {
    /// @notice Burn FLIP from a player for coinflip deposit.
    function burnForCoinflip(address from, uint256 amount) external;
    /// @notice Mint FLIP to a player (coinflip claims, degenerette wins).
    function mintForGame(address to, uint256 amount) external;
}

/// @notice Interface for WWXRP contract methods used by Coinflip.
interface IWWXRP {
    /// @notice Mint WWXRP consolation prize to a player on coinflip loss.
    function mintPrize(address to, uint256 amount) external;
}

contract Coinflip {
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

    /// @notice Emitted whenever a player's coinflip claim-state changes, so off-chain consumers can
    ///         reconstruct claimable + carry from logs alone (no eth_call). Carries the committed
    ///         post-update state of the three mutable PlayerCoinflipState fields.
    /// @param claimableStored Post-update PlayerCoinflipState.claimableStored.
    /// @param autoRebuyCarry  Post-update PlayerCoinflipState.autoRebuyCarry.
    /// @param lastClaim       Post-update PlayerCoinflipState.lastClaim (the claim cursor; lets an
    ///        indexer recompute lazy pending winnings from the day-result + per-day-stake events).
    event CoinflipClaimState(
        address indexed player,
        uint128 claimableStored,
        uint128 autoRebuyCarry,
        uint24  lastClaim
    );

    /*+======================================================================+
      |                          CUSTOM ERRORS                               |
      +======================================================================+*/

    error AmountLTMin();
    error CoinflipLocked();
    error OnlyFlipCreditors();
    error OnlyFLIP();
    error OnlysDGNRS();
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
    IFLIP public constant flip = IFLIP(ContractAddresses.COIN);
    IDegenerusGame public constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);
    IDegenerusJackpots public constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IWWXRP public constant wwxrp = IWWXRP(ContractAddresses.WWXRP);

    // Constants
    uint256 private constant MIN = 100 ether;
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 1 ether;
    uint16 private constant COINFLIP_EXTRA_MIN_PERCENT = 78;
    uint16 private constant COINFLIP_EXTRA_RANGE = 38;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant RECYCLE_BONUS_BPS = 75;
    uint256 private constant PRICE_COIN_UNIT = 1000 ether;
    uint16 private constant COIN_CLAIM_DAYS = 365;
    uint16 private constant COIN_CLAIM_FIRST_DAYS = 180;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1460;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    /// @dev Initial-emission seed stakes: 200k FLIP per day for days 1-20, each to
    ///      VAULT and sDGNRS. All initial FLIP must survive a coinflip before minting.
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
    // day>>1, 128-bit wei lanes, lossless — flip credits can be sub-1-FLIP);
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

    /// @notice Seeds the initial FLIP emission as flip stakes: 200k per day for days 1-20,
    ///         each to VAULT and sDGNRS. Direct storage writes (not _addDailyFlip) keep the
    ///         seeds off the daily top-bettor leaderboard and the bounty/biggest-flip records.
    ///         Nothing mints up front — each day's seed only becomes claimable FLIP if it
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
    ///      QUESTS (level quest rewards), AFFILIATE, ADMIN, SDGNRS (redemption win-credit at claim:
    ///      the escrowed slice was already removed from sDGNRS's backing at submit via
    ///      withdrawRedeemedFlip, so the claim-time mint to the redeemer is FLIP-neutral).
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

    /// @dev Restricts access to FLIP, which claims/consumes a player's unclaimed
    ///      coinflip winnings to cover transfer and burn shortfalls.
    modifier onlyFLIP() {
        if (msg.sender != ContractAddresses.COIN) revert OnlyFLIP();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Deposit FLIP into the daily coinflip system.
    /// @dev The deposit (stake, quest progress, winnings) belongs to `player`. The player or an
    ///      approved operator funds it from the player's FLIP; any other caller funds it from their
    ///      own FLIP — a permissionless gift (the caller pays, the player gets the stake).
    /// @param player The stake owner — i.e. the player (address(0) or msg.sender for self-deposit).
    /// @param amount Amount of FLIP to deposit (min 100 FLIP, or 0 to settle pending claims).
    function depositCoinflip(address player, uint256 amount) external {
        if (player == address(0)) player = msg.sender;
        address funder;
        if (player == msg.sender || degenerusGame.isOperatorApproved(player, msg.sender)) {
            // The player or an approved operator funds the deposit from the player's FLIP.
            funder = player;
        } else {
            // Permissionless gift: the caller's FLIP funds the player's coinflip stake.
            funder = msg.sender;
        }
        _depositCoinflip(player, funder, amount, player == msg.sender);
    }

    /// @dev Internal deposit for daily coinflip mode. The stake (quest progress, winnings)
    ///      belongs to `player`; the FLIP principal is burned from `funder` (== player for a
    ///      self/approved deposit, == the caller for a permissionless gift).
    function _depositCoinflip(
        address player,
        address funder,
        uint256 amount,
        bool directDeposit
    ) private {
        PlayerCoinflipState storage state = playerState[player];
        if (amount != 0) {
            if (amount < MIN) revert AmountLTMin();
            // Block deposits during BAF jackpot resolution to prevent
            // auto-claim from updating the BAF leaderboard mid-resolution.
            if (_coinflipLockedDuringTransition()) revert CoinflipLocked();
        }

        uint256 mintable = _claimCoinflipsInternal(player, false);
        // storedAfter mirrors claimableStored through this frame; no call below can
        // mutate it (burnForCoinflip and handleFlip never reach a claimable writer).
        uint128 storedAfter = state.claimableStored;
        if (mintable != 0) {
            storedAfter = uint128(uint256(storedAfter) + mintable);
            state.claimableStored = storedAfter;
        }
        // claimableStored / lastClaim / carry are finalized here — nothing below mutates them
        // (_addDailyFlip writes only per-day stake). One emit covers both exits.
        _emitClaimState(player);

        if (amount == 0) {
            emit CoinflipDeposit(player, 0);
            return;
        }

        // CEI PATTERN: Burn first so reentrancy into downstream module calls cannot spend the same balance twice.
        flip.burnForCoinflip(funder, amount);

        // Quests can layer on bonus flip credit when the quest is active/completed. Quest
        // progress is credited to the funder (the spender earns the quest); the resulting
        // bonus flows into the player's stake below.
        IDegenerusQuests module = questModule;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = module.handleFlip(funder, amount);
        uint256 questReward = _questApplyReward(
            funder,
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
            player,
            creditedFlip,
            directDeposit ? amount : 0,
            directDeposit,
            directDeposit
        );
        emit CoinflipDeposit(player, amount);
    }

    /*+======================================================================+
      |                    CLAIM FUNCTIONS                                   |
      +======================================================================+*/

    /// @notice Claim coinflip winnings (exact amount).
    /// @dev Processes resolved days and claims from claimableStored (accumulated from
    ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
    /// @param player The player to claim for (address(0) for msg.sender, else operator-approved).
    /// @param amount Maximum FLIP to claim (actual may be less if insufficient claimable).
    /// @return claimed Actual amount of FLIP minted and claimed.
    function claimCoinflips(
        address player,
        uint256 amount
    ) external returns (uint256 claimed) {
        return _claimCoinflipsAmount(_resolvePlayer(player), amount, true);
    }

    /// @notice Claim coinflip winnings via FLIP to cover token transfers/burns.
    /// @dev Access: FLIP only. Processes resolved days and claims from claimableStored.
    ///      Auto-rebuy carry is never exposed to this path.
    /// @param player The player whose coinflip winnings to claim.
    /// @param amount Maximum FLIP to claim.
    /// @return claimed Actual amount of FLIP minted and claimed.
    function claimCoinflipsFromFlip(
        address player,
        uint256 amount
    ) external onlyFLIP returns (uint256 claimed) {
        return _claimCoinflipsAmount(player, amount, true);
    }

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win) {
        return _dayResult(day);
    }

    /// @notice Consume coinflip winnings via FLIP for burns (no mint).
    /// @dev Access: FLIP only. Same safety as claimCoinflipsFromFlip —
    ///      only claimableStored is consumable, carry stays in autoRebuyCarry.
    /// @param player The player whose coinflip winnings to consume.
    /// @param amount Maximum FLIP to consume.
    /// @return consumed Actual amount of FLIP consumed (deducted from claimable, no token mint).
    function consumeCoinflipsForBurn(
        address player,
        uint256 amount
    ) external onlyFLIP returns (uint256 consumed) {
        return _claimCoinflipsAmount(player, amount, false);
    }

    /// @notice Consume `amount` of `player`'s coinflip-resident FLIP backing for a salvage swap (FLIP only).
    /// @dev Settle-then-drain waterfall matching the redemption desk's withdrawRedeemedFlip: settled
    ///      claimable FIRST (no mint — removes a future mint of the consumed slice), then the rolling
    ///      auto-rebuy carry. For the vault FLIP first drains the virtual allowance (its held leg);
    ///      sDGNRS has no wallet leg, so this covers its entire backing (claimable + carry). Reaching
    ///      the carry is freeze-safe because the salvage entrypoint reverts under the RNG lock, so
    ///      this never runs mid-window.
    /// @param player The backing owner (sDGNRS or the vault).
    /// @param amount Maximum FLIP (wei) to consume from claimable + carry.
    /// @return consumed Actual amount removed (claimable consumed + carry decremented).
    function consumeFlipForSalvage(
        address player,
        uint256 amount
    ) external onlyFLIP returns (uint256 consumed) {
        consumed = _claimCoinflipsAmount(player, amount, false);
        uint256 remainder = amount - consumed;
        if (remainder == 0) return consumed;
        PlayerCoinflipState storage state = playerState[player];
        uint256 carry = state.autoRebuyCarry;
        uint256 fromCarry = remainder <= carry ? remainder : carry;
        if (fromCarry != 0) {
            unchecked {
                state.autoRebuyCarry = uint128(carry - fromCarry);
            }
            consumed += fromCarry;
            _emitClaimState(player);
        }
    }

    /// @notice Credit de-circulated FLIP to sDGNRS's redemption backing (FLIP only).
    /// @dev Called by FLIP when a transfer lands on ContractAddresses.SDGNRS: FLIP removes the
    ///      amount from circulating supply and routes it here as sDGNRS claimable backing, so
    ///      sDGNRS never holds a wallet balance and its FLIP stays uncirculated. Storage-only
    ///      (no callback into FLIP). Folds into claimableStored, where redemptions/salvage read it.
    /// @param amount FLIP (wei) to add to sDGNRS's claimable backing.
    function creditSdgnrsBacking(uint256 amount) external onlyFLIP {
        if (amount == 0) return;
        PlayerCoinflipState storage state = playerState[ContractAddresses.SDGNRS];
        state.claimableStored = uint128(uint256(state.claimableStored) + amount);
        _emitClaimState(ContractAddresses.SDGNRS);
    }

    /// @dev Emit the player's committed coinflip claim-state (claimable + carry + cursor) for
    ///      off-chain reconstruction without an eth_call. Call as the LAST statement after the three
    ///      PlayerCoinflipState fields are finalized; never inside _claimCoinflipsInternal (its
    ///      callers finalize claimableStored after it returns, so an emit there would be stale).
    function _emitClaimState(address player) private {
        PlayerCoinflipState storage s = playerState[player];
        emit CoinflipClaimState(player, s.claimableStored, s.autoRebuyCarry, s.lastClaim);
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
        if (stored == 0) {
            // _claimCoinflipsInternal may still have advanced lastClaim / settled carry.
            _emitClaimState(player);
            return 0;
        }

        uint256 toClaim = amount;
        if (toClaim > stored) {
            toClaim = stored;
        }
        if (mintable != 0 || toClaim != 0) {
            state.claimableStored = uint128(stored - toClaim);
        }

        if (toClaim != 0) {
            if (mintTokens) {
                flip.mintForGame(player, toClaim);
            }
            claimed = toClaim;
        }
        _emitClaimState(player);
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
                uint24 cachedLevel,
                ,
                bool lastPurchaseDay_,
                bool rngLocked_,

            ) = game.purchaseInfo();
            // purchaseInfo.lvl is the ACTUAL game level (one snapshot covers level + flags, no
            // separate level() read). The BAF guard and bracket key on the real level, not the
            // routed buy level (which diverges on the final jackpot day).
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
            // BAF bracket = the level's decade ceiling: a level in [10k, 10k+9] records to
            // bracket 10*(k+1). _bafBracketLevel rounds up to the next multiple of 10, so
            // (level + 1) maps every decade — including the x10 boundary — to its closing
            // bracket (equivalent to the former phase-branched bafLevel, minus its dead cases).
            uint24 bafLvl = _bafBracketLevel(cachedLevel + 1);
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
            // Manual deposits only: check and consume coinflip boon (5%/10%/25% boost on max 100k FLIP deposit)
            // Max bonuses: 5% = 5k, 10% = 10k, 25% = 25k
            uint16 boonBps = game.consumeCoinflipBoon(player);
            if (boonBps > 0) {
                uint256 maxDeposit = 100_000 ether; // Cap at 100k FLIP for boost calc
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
                // recordAmount fits uint128: it was already burned via FLIP._burn,
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
            flip.mintForGame(player, mintable);
        }
        _emitClaimState(player);
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
            flip.mintForGame(player, mintable);
        }
        _emitClaimState(player);
    }

    /// @notice Claim up to `amount` of the auto-rebuy carry as minted FLIP while
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
    /// @return claimed Actual amount of FLIP minted from the carry.
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
            flip.mintForGame(player, claimed);
        }
        _emitClaimState(player);
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

        // 50/50 win roll off the low bit of the VRF word.
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
        // stay off the rngLocked guard). sDGNRS never mints FLIP to a wallet balance:
        // its FLIP stays uncirculated as coinflip backing and is read by redemptions /
        // salvage as claimableStored + carry. During the seed window each settled win
        // folds into claimableStored (no mint); once auto-rebuy is armed, winnings
        // settle into the rolling carry (structurally zero return under 0-take-profit
        // rebuy). FLIP leaves sDGNRS's position solely through a redemption/salvage
        // consume leg.
        if (sdgnrsAutoRebuyArmed) {
            _claimCoinflipsInternal(ContractAddresses.SDGNRS, false);
        } else {
            uint256 mintable = _claimCoinflipsInternal(ContractAddresses.SDGNRS, false);
            PlayerCoinflipState storage sdgnrsState = playerState[
                ContractAddresses.SDGNRS
            ];
            if (mintable != 0) {
                sdgnrsState.claimableStored = uint128(
                    uint256(sdgnrsState.claimableStored) + mintable
                );
            }

            // Once the final seeded day settles, sDGNRS goes on perpetual auto-rebuy
            // (0 take-profit): every later flip credit rolls win-after-win until a loss.
            if (epoch >= SEED_FLIP_DAYS) {
                sdgnrsAutoRebuyArmed = true;
                sdgnrsState.autoRebuyEnabled = true;
                sdgnrsState.autoRebuyStartDay = sdgnrsState.lastClaim;
                emit CoinflipAutoRebuyToggled(ContractAddresses.SDGNRS, true);
            }
        }
        // sDGNRS's claim-state was mutated above (the armed branch settles via _claimCoinflipsInternal,
        // which does not emit); surface the committed post-state for log-only reconstruction.
        _emitClaimState(ContractAddresses.SDGNRS);
    }

    /*+======================================================================+
      |                    FLIP CREDITING                                    |
      +======================================================================+*/

    /// @notice Credit flip to a player (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of FLIP-denominated flip stake to credit.
    function creditFlip(
        address player,
        uint256 amount
    ) external onlyFlipCreditors {
        if (player == address(0) || amount == 0) return;
        _addDailyFlip(player, amount, 0, false, false);
    }

    /// @notice Credit flips to multiple players (called by GAME modules, QUESTS, AFFILIATE, or ADMIN).
    /// @param players Array of 3 player addresses to credit (address(0) entries are skipped).
    /// @param amounts Array of 3 FLIP-denominated flip stake amounts (0 entries are skipped).
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

    /// @notice Settle-then-read sDGNRS's redeemable FLIP coinflip backing (sDGNRS only).
    /// @dev Forces all resolved days into claimableStored / autoRebuyCarry first so the two summed
    ///      components are disjoint and current even after a multi-day advance stall (otherwise a
    ///      resolved-but-unsettled win day could be counted in both claimable and the carry). In
    ///      steady state sDGNRS is already settled each advance, so the walk is a no-op.
    /// @return backing sDGNRS's claimableStored + autoRebuyCarry — its entire FLIP backing
    ///         (sDGNRS never holds a wallet balance; incoming FLIP de-circulates into claimable).
    function redeemableFlipBacking() external returns (uint256 backing) {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlysDGNRS();
        address s = ContractAddresses.SDGNRS;
        uint256 mintable = _claimCoinflipsInternal(s, false);
        PlayerCoinflipState storage state = playerState[s];
        if (mintable != 0) {
            state.claimableStored = uint128(uint256(state.claimableStored) + mintable);
        }
        _emitClaimState(s);
        return uint256(state.claimableStored) + uint256(state.autoRebuyCarry);
    }

    /// @notice Remove `base` (wei) of sDGNRS's own FLIP backing at redemption submit (sDGNRS only).
    /// @dev Waterfall: settled claimable (consumed, no mint) → auto-rebuy carry (decremented) —
    ///      sDGNRS holds no wallet balance, so its backing lives entirely in these two. Credits
    ///      NOTHING — the redeemer's escrowed slice is paid later, only on the resolving day's
    ///      coinflip win, via creditFlip, so the win path is a pure deferred mint of an amount
    ///      already removed from sDGNRS's backing here. Fail-closed if the backing falls short
    ///      (cannot happen: sDGNRS sizes base from the same settled backing read via
    ///      redeemableFlipBacking earlier in the same submit).
    /// @param base The whole-token-aligned FLIP backing (wei) to remove from sDGNRS.
    function withdrawRedeemedFlip(uint256 base) external {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlysDGNRS();
        if (base == 0) return;
        address s = ContractAddresses.SDGNRS;

        // Consume settled claimable first (no token mint — removes a future mint of `consumed`).
        uint256 consumed = _claimCoinflipsAmount(s, base, false);
        uint256 remainder = base - consumed;
        if (remainder == 0) return;

        // Decrement the rolling auto-rebuy carry for the rest (post-day-20 steady state, where
        // sDGNRS's FLIP lives entirely in the carry).
        PlayerCoinflipState storage state = playerState[s];
        uint256 carry = state.autoRebuyCarry;
        if (remainder > carry) revert Insufficient();
        unchecked {
            state.autoRebuyCarry = uint128(carry - remainder);
        }
        _emitClaimState(s);
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

    /// @notice Preview `player`'s salvage-spendable coinflip backing: claimable + auto-rebuy carry (view).
    /// @dev The carry-inclusive read the salvage quote caps against, mirroring redeemableFlipBacking's
    ///      components but as a pure VIEW (no settle) so the preview and execution offer stay re-derivable.
    ///      Conservative: reads the carry before any pending settle, so a resolving win day not yet rolled
    ///      in is excluded — the cap can only under-state, never over-state, the burnable backing.
    function previewSalvageFlipBacking(address player) external view returns (uint256) {
        PlayerCoinflipState storage state = playerState[player];
        return _viewClaimableCoin(player) + state.claimableStored + state.autoRebuyCarry;
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
    ///      can be sub-1-FLIP, so whole-token granularity would zero them. Fresh
    ///      SLOAD — never cached across the claim loop's external calls.
    function _flipStake(uint24 day, address p) internal view returns (uint256) {
        return uint128(coinflipStakePacked[day >> 1][p] >> ((day & 1) * 128));
    }

    /// @dev Masked write of `day`'s stake lane, preserving the sibling day. weiAmount
    ///      is provably <= uint128 (FLIP caps total supply at uint128, and a
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
            uint24 lvl,
            ,
            bool lastPurchaseDay_,
            bool rngLocked_,

        ) = degenerusGame.purchaseInfo();
        // lastPurchaseDay_ is true only outside the jackpot phase, so it alone
        // restricts the lock to purchase-phase states. No game-over state can
        // reach here: every gameOver latch leaves jackpotPhaseFlag set or
        // lastPurchaseDay false, and neither is ever written again post-latch. lvl is the
        // ACTUAL game level from the same snapshot — no separate level() read needed.
        if (!lastPurchaseDay_ || !rngLocked_) return false;
        locked = lvl != 0 && lvl % 10 == 0;
    }

    /// @dev Calculate recycling bonus for daily flip deposits (0.75% bonus, capped at 1000 FLIP).
    ///      Base is the recycled amount (the re-bet or auto-rebuy carry being deposited).
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
