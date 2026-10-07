// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/**
 * @title Coinflip
 * @author Burnie Degenerus
 * @notice Standalone daily coinflip wagering system for FLIP
 *
 * @dev ARCHITECTURE:
 *      - A standalone contract separate from FLIP, keeping FLIP within its size budget
 *      - Manages the daily coinflip system with a flat recycle bonus
 *      - Integrates with FLIP for burn/mint operations
 *      - Holds the all-time record pool (flip / degenerette spin / lootbox deposit /
 *        ticket buy) and quest rewards
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
import {RECORD_KIND_FLIP, RECORD_KIND_SPIN, RECORD_KIND_LUCKBOX, RECORD_KIND_DICE_RUN} from "./interfaces/ICoinflip.sol";
import {IDegenerusQuests} from "./interfaces/IDegenerusQuests.sol";
import {IDegenerusJackpots} from "./interfaces/IDegenerusJackpots.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

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

/// @notice Interface for the soulbound record-bounty trophy moved on record ratchets.
interface IDegenerusRecordBounty {
    /// @notice Stamp record `kind`'s new mark and hand its trophy to `to`.
    function recordSet(uint8 kind, address to, uint256 value) external;
}

contract Coinflip {
    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    /// @notice Emitted when a coinflip deposit is credited to the player's pending stake.
    /// @param player The depositor credited.
    /// @param creditedFlip The deposit principal actually funded, in whole FLIP: the requested amount
    ///        floored to whole FLIP (the quest and recycling bonuses that join the stake are not
    ///        included); 0 on a zero-amount deposit.
    event CoinflipDeposit(address indexed player, uint256 creditedFlip);
    /// @notice Emitted when a player's coinflip auto-rebuy is turned on or off.
    /// @param player The player whose auto-rebuy state changed.
    /// @param enabled True when auto-rebuy is now on, false when turned off.
    event CoinflipAutoRebuyToggled(address indexed player, bool enabled);
    /// @notice Emitted when a player's auto-rebuy take-profit threshold is set or updated.
    /// @param player The auto-rebuy player.
    /// @param stopAmount The take-profit threshold: winnings bank in whole multiples of it,
    ///        the remainder rolls.
    event CoinflipAutoRebuyStopSet(address indexed player, uint256 stopAmount);
    /// @notice Emitted when a coinflip deposit completes a quest.
    /// @param player The player credited with the quest reward.
    /// @param questType The completed quest's type identifier.
    /// @param streak The player's streak count at completion.
    /// @param reward The FLIP bonus credited for completing the quest.
    event QuestCompleted(
        address indexed player,
        uint8 questType,
        uint32 streak,
        uint256 reward
    );
    /// @notice Emitted when flip stake is credited to a future day. Authoritative for the stake
    ///         accepted: stakes are stored in whole FLIP and capped per wallet and day
    ///         (STAKE_LANE_MAX), so component events (QuestCompleted, BigRecordUpdated,
    ///         CoinflipDeposit) describe nominal awards while this one reports what the lane
    ///         actually took after rounding and capping. The VAULT and sDGNRS seed stake is not
    ///         stored and never appears here: SeedWindowArmed carries it.
    /// @param id The wallet ID receiving stake credit.
    /// @param day The target flip day being credited.
    /// @param amount The stake actually added (new total minus previous total), whole FLIP.
    /// @param newTotal The stored total stake for that day, whole FLIP; for VAULT and sDGNRS on a
    ///        seed-window day the day's stake is this plus the window's amountPerDay.
    event CoinflipStakeUpdated(
        uint32 indexed id,
        uint24 indexed day,
        uint256 amount,
        uint256 newTotal
    );
    /// @notice Emitted when a seed window opens for VAULT and sDGNRS: the deploy window
    ///         (century 0) and each x00 level's. A window replaces the previous one.
    /// @param century The century index (level / 100) the window belongs to.
    /// @param firstDay First flip day carrying the seed stake.
    /// @param dayCount Number of consecutive days seeded.
    /// @param amountPerDay Seed stake each recipient holds on every window day, on top of the
    ///        day's stored stake; no CoinflipStakeUpdated reports it.
    event SeedWindowArmed(
        uint24 indexed century,
        uint24 indexed firstDay,
        uint24 dayCount,
        uint256 amountPerDay
    );
    /// @notice Emitted when a coinflip day is resolved.
    /// @param day The resolved day.
    /// @param win Whether the flip outcome is a win.
    /// @param rewardPercent Bonus percent applied on wins.
    /// @param recordPoolAfter The record pool after the daily drip.
    event CoinflipDayResolved(
        uint24 indexed day,
        bool win,
        uint16 rewardPercent,
        uint128 recordPoolAfter
    );
    /// @notice Emitted when the game arms a flip day for the BAF weighted draw.
    /// @param day The flip day whose direct deposits enter the draw.
    event BafDrawArmed(uint24 indexed day);
    /// @notice Emitted for every interval recorded in an armed day's draw book.
    /// @param day The armed flip day.
    /// @param id The depositor's wallet ID, paid if the winner roll lands in the interval.
    /// @param index The entry's index in the day's book.
    /// @param weight This deposit's weight: the whole-FLIP floor of its raw principal.
    /// @param cumulativeWeight The entry's cumulative endpoint (exclusive).
    event BafDrawEntered(
        uint24 indexed day,
        uint32 indexed id,
        uint32 index,
        uint96 weight,
        uint96 cumulativeWeight
    );
    /// @notice Emitted whenever an all-time record moves. One event covers both
    ///         outcomes: a zero `paid` is a bare ratchet, anything else is a claim.
    /// @param kind Which record moved (RECORD_KIND_*).
    /// @param id The wallet ID the record — and any claim — accrues to.
    /// @param value The new mark, in that record's unit (flip: whole FLIP; spin and
    ///        lootbox deposit: ETH wei; ticket buy: whole tickets; dice run: score
    ///        basis points, 10,000 = 1x).
    /// @param paid FLIP credited for the claim — the category's accrued share of the
    ///        record pool — 0 on a bare ratchet (kinds 0-3: the candidate did not clear
    ///        the mark by a fifth) or when the share of the pool computes to zero. A
    ///        nominal figure: the stake it joins is whole FLIP, so CoinflipStakeUpdated
    ///        reports the accepted amount.
    /// @param sdgnrsPaid sDGNRS paid for the claim from the reward pool (the same
    ///        accrued share at 1/500 scale), 0 on a bare ratchet or an empty pool.
    event BigRecordUpdated(
        uint8 indexed kind,
        uint32 indexed id,
        uint256 value,
        uint128 paid,
        uint256 sdgnrsPaid
    );

    /// @notice Emitted whenever a player's coinflip claim-state changes, so off-chain consumers can
    ///         reconstruct claimable + carry from logs alone (no eth_call). Carries the committed
    ///         post-update state of the three mutable PlayerCoinflipState fields.
    /// @param player          The player whose claim-state changed.
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

    /// @notice Thrown when a nonzero deposit amount is below the minimum stake.
    error AmountLTMin();
    /// @notice Thrown when a manual deposit, with its bonuses, would take the player's stake
    ///         for the target day past STAKE_LANE_MAX whole FLIP.
    error StakeAboveDailyCap();
    /// @notice Thrown when the caller is not one of the contracts allowed to credit flip stake.
    error OnlyFlipCreditors();
    /// @notice Thrown when the caller is not the FLIP contract.
    error OnlyFLIP();
    /// @notice Thrown when the caller is not sDGNRS.
    error OnlysDGNRS();
    /// @notice Thrown when the caller is not the game contract.
    error OnlyDegenerusGame();
    /// @notice Thrown when the caller is not the craps table.
    error OnlyCraps();
    /// @notice Thrown when a take-profit or off action targets a player without auto-rebuy enabled.
    error AutoRebuyNotEnabled();
    /// @notice Thrown when an enable call targets an account that already has auto-rebuy on.
    error AutoRebuyAlreadyEnabled();
    /// @notice Thrown when a take-profit threshold does not fit its stored uint128 value.
    error TakeProfitTooLarge();
    /// @notice Thrown when an auto-rebuy action is attempted while today's flip is frozen for RNG.
    error RngLocked();
    /// @notice Thrown when the caller may not act for the account: it is neither the account's
    ///         key, a smurf's owner, nor an approved operator.
    error NotApproved();

    /*+======================================================================+
      |                         STORAGE VARIABLES                            |
      +======================================================================+*/

    // Constant contract references (addresses from ContractAddresses)
    /// @notice The FLIP coin contract.
    IFLIP public constant flip = IFLIP(ContractAddresses.COIN);
    /// @notice The main game contract.
    IDegenerusGame public constant degenerusGame = IDegenerusGame(ContractAddresses.GAME);
    /// @notice The jackpots contract.
    IDegenerusJackpots public constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    /// @notice The WWXRP consolation-prize contract.
    IWWXRP public constant wwxrp = IWWXRP(ContractAddresses.WWXRP);

    // Constants
    uint256 private constant MIN = 100;
    /// @dev Stake lanes store whole FLIP: at most STAKE_LANE_MAX tokens per
    ///      player per day. Eight 32-bit lanes pack one storage word.
    uint256 private constant STAKE_LANE_MAX = type(uint32).max;
    uint256 private constant COINFLIP_LOSS_WWXRP_REWARD = 1;
    uint16 private constant BPS_DENOMINATOR = 10_000;
    uint16 private constant RECYCLE_BONUS_BPS = 75;
    /// @dev Daily drip into the shared record pool, applied at settlement. Adding the
    ///      dice-run category adds no drip and no take rate: it is a fifth way to claim
    ///      from the pool this line funds, not a fifth pool.

    uint256 private constant RECORD_POOL_DAILY_FLIP = 2_000;
    /// @dev A record claim must clear the standing mark by mark/5 (a fifth) — for the
    ///      four ORIGINAL kinds. The dice run claims on any strict improvement.
    uint256 private constant RECORD_BEAT_DIV = 5;
    /// @dev Claim share of the pool: a 5% floor, +0.5% per day the record's own
    ///      category has gone unclaimed, capped at 75% (reached 140 days after a
    ///      claim). Each category keeps its own clock, and the clock resets on a
    ///      claim only — a bare ratchet cannot zero an accrued share.
    uint256 private constant RECORD_SHARE_FLOOR_BPS = 500;
    uint256 private constant RECORD_SHARE_PER_DAY_BPS = 50;
    uint256 private constant RECORD_SHARE_CEIL_BPS = 7_500;
    /// @dev Entry floor for the flip record. A direct deposit under it never reads the
    ///      record slot, and the mark is only ever written by a deposit that cleared it —
    ///      so the mark is always 0 or at or above the floor, and a sub-floor deposit
    ///      could not have beaten it anyway. The game-side records gate their own floors
    ///      at their call sites.
    uint256 private constant BIGGEST_FLIP_MIN = 200_000;
    /// @dev Entry floor for the DICE RUN record: a 100x high point against the run's
    ///      own starting bankroll, in score basis points (10,000 = 1x). The craps
    ///      table gates it at the call site too, so a field that never got near a
    ///      record does not pay for the call.
    uint256 private constant BIGGEST_DICE_RUN_MIN = 1_000_000;
    /// @dev Domain tag for the BAF weighted-draw winner roll.
    bytes32 private constant BAF_DRAW_TAG = "COINFLIP_BAF_DRAW_WINNER";
    uint16 private constant COIN_CLAIM_DAYS = 365;
    uint16 private constant COIN_CLAIM_FIRST_DAYS = 180;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1460;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    /// @dev Initial-emission seed stakes: 200k FLIP per day for days 1-20, each to
    ///      VAULT and sDGNRS. All initial FLIP must survive a coinflip before minting.
    uint256 private constant SEED_FLIP_DAILY = 200_000;
    uint24 private constant SEED_FLIP_DAYS = 20;
    /// @dev Levels between seed windows. The deploy window covers the first, and every
    ///      x00 level re-arms one for VAULT and sDGNRS on the same terms.
    uint24 private constant SEED_CENTURY_LEVELS = 100;
    /// @dev The Game's constant wallet IDs for the two seed recipients.
    uint32 private constant VAULT_WALLET_ID = 1;
    uint32 private constant SDGNRS_WALLET_ID = 2;
    IDegenerusQuests internal constant questModule =
        IDegenerusQuests(ContractAddresses.QUESTS);

    // Player coinflip state: two slots. Slot A holds the claim bank, cursor, auto-rebuy
    // flags and the wallet's Game ID (a write-once cache every player action reads for
    // free); slot B holds the take-profit stop and the rolling carry.
    struct PlayerCoinflipState {
        uint128 claimableStored;
        uint24 lastClaim;
        uint24 autoRebuyStartDay;
        bool autoRebuyEnabled;
        uint32 id;
        uint128 autoRebuyStop;
        uint128 autoRebuyCarry;
    }

    // Daily coinflip storage. coinflipStakePacked banks 8 days per slot (key =
    // day>>3, then wallet ID; 32-bit whole-FLIP lanes; every addition floors to whole
    // FLIP and saturates at STAKE_LANE_MAX); coinflipDayResultPacked banks 32 days per
    // slot (key = day>>5, 8-bit lanes, 3-state). Access via the helpers.
    mapping(uint24 => mapping(uint32 => uint256)) internal coinflipStakePacked;
    mapping(uint24 => uint256) internal coinflipDayResultPacked;
    mapping(address => PlayerCoinflipState) internal playerState;


    // All-time record pool: ONE FLIP pool shared by the five biggest-* records
    // (flip deposit, degenerette spin, lootbox deposit, ticket buy, dice run).
    // Grows by a daily settlement drip and by level-transition funding. The four
    // original kinds claim an accruing share of it (RECORD_SHARE_*) when a record
    // is beaten by a fifth; the dice run claims on any strict improvement above
    // its own floor, with same-day repeats priced at the 5% floor of the already-
    // reduced pool (see armDiceRunRecord). The game-armed marks sit at the end of
    // the storage section so every prior slot keeps its index.
    /// @notice Shared FLIP pool the biggest-* all-time records draw their claim payouts from.
    uint128 public recordPool = 10_000;
    /// @notice The all-time biggest single flip deposit, in whole FLIP.
    uint128 public biggestFlipEver;

    // RNG state + the five per-category record claim clocks (all pack into one slot)
    uint24 internal flipsClaimableDay;
    /// @dev One-shot latch: sDGNRS perpetual auto-rebuy arms once the final seeded day settles.
    bool internal sdgnrsAutoRebuyArmed;
    /// @dev Day a record category last claimed, one clock per kind. Stamped on the
    ///      category's bootstrap write too — an unstamped zero would read the whole
    ///      day index as elapsed and max the very next claim's share.
    uint24 internal recordDayFlip;
    uint24 internal recordDaySpin;
    uint24 internal recordDayLuckbox;
    uint24 internal recordDayBuy;
    /// @dev The flip day whose direct deposits enter the BAF weighted draw — armed
    ///      by the game when an x0 purchase level enters its last purchase day
    ///      (that day's deposits stake day + 1). Packs into the slot the deposit
    ///      path's claim walk already loads, so the per-deposit gate costs one
    ///      warm read.
    uint24 internal bafDrawDay;
    /// @dev Highest century (level / SEED_CENTURY_LEVELS) whose seed window has been armed.
    ///      Appended into this slot's free bytes, so every later slot keeps its index.
    uint24 internal lastSeededCentury;
    /// @dev The DICE RUN category's claim clock, stamped on every hit. Appended into
    ///      the same slot's remaining free bytes, so every later slot keeps its index.
    ///      It accrues the claim share exactly as the other four clocks do, and — since
    ///      this kind claims on ANY strict improvement rather than on a fifth — the
    ///      reset it performs is also what prices a second hit on the same day at the
    ///      5% floor of an already-reduced pool.
    uint24 internal recordDayDiceRun;
    /// @dev First day of the active seed window: VAULT and sDGNRS each hold SEED_FLIP_DAILY of
    ///      unstored stake on days [seedWindowStart, seedWindowStart + SEED_FLIP_DAYS). One window
    ///      suffices: both claim cursors pass a window before the next one arms.
    uint24 internal seedWindowStart;

    // BAF weighted draw. Book-kept only for the armed day (the x0 level's last
    // purchase day stakes it): every direct self-funded deposit staking that day
    // appends a cumulative interval weighted by its raw FLIP principal, and the
    // BAF top-flipper slice pays ONE winner drawn over those intervals. Declared
    // here so the record marks below keep their slot indexes.
    /// @dev Per-day draw header:
    ///      bits [0..95]   total weight (whole FLIP; the last cumulative endpoint)
    ///      bits [96..127] entry count
    mapping(uint24 => uint256) internal bafDrawHeader;

    /// @dev The game-armed all-time records (appended so every prior slot keeps its
    ///      index; the flip mark packs with recordPool above). biggestSpinEver and
    ///      biggestLuckboxEver are ETH wei; biggestBuyEver is whole tickets.
    uint128 public biggestSpinEver;
    /// @notice The all-time biggest lootbox deposit, in ETH wei.
    uint128 public biggestLuckboxEver;
    /// @notice The all-time biggest ticket buy, in whole tickets.
    uint128 public biggestBuyEver;
    /// @dev THE BIGGEST DICE RUN, in score basis points: the winning scheduled craps
    ///      run's high point over its own starting bankroll, 10,000 = 1x. Packed into
    ///      biggestBuyEver's free half, so it moves no slot.
    uint128 public biggestDiceRunEver;

    /// @dev One packed interval entry per (armed day, index):
    ///      bits [0..95]   cumulative weight endpoint (exclusive, whole FLIP)
    ///      bits [96..127] depositor wallet ID
    ///      Key: (day << 32) | index. Never zero for a recorded entry — MIN is
    ///      100 FLIP, so every weight is at least 100.
    mapping(uint256 => uint256) internal bafDrawEntry;

    /// @notice Seeds the initial FLIP emission as flip stakes: 200k per day for days 1-20,
    ///         each to VAULT and sDGNRS, by opening the deploy seed window. The claim walk
    ///         reads the seed from the window rather than a stake lane, so the seeds stay off
    ///         the BAF weighted draw and the flip record.
    ///         Nothing mints up front — each day's seed only becomes claimable FLIP if it
    ///         survives that day's flip.
    constructor() {
        // Record clocks start at deploy, so each category's FIRST claim draws the
        // share accrued since launch (the 5% floor plus 0.5% per untouched day,
        // ceiling 75%) — a dormant category grows until its bounty justifies its
        // entry floor.
        uint24 recordStartDay = GameTimeLib.currentDayIndex();
        recordDayFlip = recordStartDay;
        recordDaySpin = recordStartDay;
        recordDayLuckbox = recordStartDay;
        recordDayBuy = recordStartDay;
        recordDayDiceRun = recordStartDay;

        seedWindowStart = 1;
        emit SeedWindowArmed(0, 1, SEED_FLIP_DAYS, SEED_FLIP_DAILY);

        // The seed recipients' ID caches hold the Game's protocol constants from deploy, so
        // the vault's own actions and every sDGNRS settlement read them without a Game call.
        playerState[ContractAddresses.VAULT].id = VAULT_WALLET_ID;
        playerState[ContractAddresses.SDGNRS].id = SDGNRS_WALLET_ID;

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "coinflip.degenerus.eth")
            );
            ok;
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
    ///      QUESTS (level quest rewards), AFFILIATE, ADMIN, SDGNRS (redemption win-credit at settlement:
    ///      the escrowed slice was already removed from sDGNRS's backing at batch close via
    ///      withdrawRedeemedFlip, so the settlement mint to the redeemer is FLIP-neutral),
    ///      WWXRP (daily-draw prizes: a fixed, RNG-verified stake credited to the
    ///      recorded winner), PARIMUTUEL (growth-market payouts from the game-driven
    ///      settlement stage — re-mints of stakes the market burned at placement),
    ///      and CRAPS (theo rakeback: a fixed slice of a settled bet's expected loss,
    ///      comped as next-day stake).
    modifier onlyFlipCreditors() {
        address sender = msg.sender;
        if (
            sender != ContractAddresses.GAME &&
            sender != ContractAddresses.QUESTS &&
            sender != ContractAddresses.AFFILIATE &&
            sender != ContractAddresses.ADMIN &&
            sender != ContractAddresses.CRAPS &&
            sender != ContractAddresses.SDGNRS &&
            sender != ContractAddresses.WWXRP &&
            sender != ContractAddresses.PARIMUTUEL
        ) revert OnlyFlipCreditors();
        _;
    }

    /// @dev Restricts access to FLIP, which uses this both to claim/consume a player's
    ///      unclaimed coinflip winnings (covering transfer and burn shortfalls) and to
    ///      route de-circulated FLIP into sDGNRS's coinflip-claimable backing.
    modifier onlyFLIP() {
        if (msg.sender != ContractAddresses.COIN) revert OnlyFLIP();
        _;
    }

    /*+======================================================================+
      |                    CORE COINFLIP FUNCTIONS                           |
      +======================================================================+*/

    /// @notice Deposit FLIP into the daily coinflip system for account `id`.
    /// @dev The stake and its winnings belong to the account. An authorized caller (`id == 0`,
    ///      the account's key, a smurf's owner or an approved operator) acts as the account: the
    ///      deposit spends the account's settled winnings first and burns the account's payee's
    ///      wallet FLIP for the remainder, and the quest progress is the account's. Any other
    ///      caller makes a permissionless gift: it funds the whole stake from its own FLIP, earns
    ///      the quest itself, and never touches the account's winnings. Any completed quest's
    ///      reward joins the account's stake. The recycling bonus pays on the winnings leg only.
    ///      Only the account's own hand (the caller is the payee: a self deposit or a smurf's
    ///      owner) makes a direct deposit, which can set the flip record, enter the BAF draw and
    ///      spend the account's coinflip boon.
    ///      The principal is floored to whole FLIP before funding; the remainder stays with the
    ///      funder. Reverts StakeAboveDailyCap if the stake, with its bonuses, would exceed
    ///      STAKE_LANE_MAX whole FLIP on the target day.
    ///      The stake is keyed by wallet ID. A paid self deposit registers the caller on first
    ///      contact; a nonzero `id` is allocated (Game `resolveAccount` reverts otherwise), and a
    ///      gift's paying funder registers for its quest.
    /// @param id The account receiving the stake (0 = caller).
    /// @param amount Amount of FLIP to deposit (min 100 FLIP, or 0 to settle pending claims);
    ///        floored to whole FLIP.
    function depositCoinflip(uint32 id, uint256 amount) external {
        (address key, address payee, bool authorized) = _resolve(id);
        _depositCoinflip(key, payee, id, amount, !authorized);
    }

    /// @dev Internal deposit for daily coinflip mode. The stake and its winnings belong to the
    ///      account (`key`, wallet `id`, 0 = look it up). An authorized deposit is funded
    ///      claimable-first and burns `payee`'s wallet FLIP for whatever the settled winnings did
    ///      not cover; a gift burns the caller's FLIP for the whole principal. Any loss
    ///      consolation of the claim walk mints to `payee`.
    function _depositCoinflip(
        address key,
        address payee,
        uint32 id,
        uint256 amount,
        bool gift
    ) private {
        PlayerCoinflipState storage state = playerState[key];
        if (amount != 0 && amount < MIN) revert AmountLTMin();
        // A paid self deposit allocates (nonzero or Game `E`); a resolved account is already
        // allocated. Only a zero-amount self settle can leave the ID zero: nothing to settle.
        id = _walletId(key, state, id, amount != 0);
        // Stake lanes hold whole FLIP: fund, burn, score and record the floored principal
        // only, so the funder keeps the fraction the lane could not take.
        // Deposits flow through every RNG lock. A deposit on day N stakes day
        // N+1, and the word that resolves day N+1 is not requested until day
        // N+1 — so every stake write (and every BAF draw interval, which keys
        // the same target day) structurally precedes the request of the word
        // that consumes it. The BAF bracket needs no deposit lock either: an
        // in-window auto-claim records its credit to the NEXT bracket
        // (claim-time routing off the promoted level) — state the pending draw
        // never reads.

        uint256 mintable = _claimCoinflipsInternal(payee, id, state, false);
        uint128 storedBefore = state.claimableStored;
        uint128 storedAfter = storedBefore;
        if (mintable != 0) {
            storedAfter = uint128(uint256(storedAfter) + mintable);
        }

        // Claimable-first waterfall: settled winnings fund the stake before the wallet does, so a
        // rebet spends the bank instead of requiring a claim-out that would mint the FLIP just to
        // burn it again. Supply-neutral: claimableStored is UNMINTED (mintForGame fires only when
        // FLIP is claimed out) and a day stake is off-supply too — a normal deposit burns its
        // principal to create one — so moving between the two mints and burns nothing. Gated on
        // an authorized caller: a permissionless gift funds the whole stake from the caller's own
        // FLIP and can never push a non-consenting account's winnings onto a flip.
        uint256 fromClaimable;
        if (!gift) {
            fromClaimable = amount <= storedAfter ? amount : storedAfter;
            if (fromClaimable != 0) {
                unchecked {
                    storedAfter = uint128(uint256(storedAfter) - fromClaimable);
                }
            }
        }
        if (storedAfter != storedBefore) {
            state.claimableStored = storedAfter;
        }
        // claimableStored / lastClaim / carry are finalized here — nothing below mutates them
        // (burnForCoinflip and handleFlip never reach a claimable writer, _addDailyFlip writes
        // only per-day stake). One emit covers both exits.
        _emitClaimState(key);

        if (amount == 0) {
            emit CoinflipDeposit(key, 0);
            return;
        }

        // CEI PATTERN: the claimable leg is already debited above and the wallet leg burns here,
        // so reentrancy into downstream module calls cannot spend either source twice.
        uint256 fromWallet;
        unchecked {
            fromWallet = amount - fromClaimable;
        }
        // An authorized deposit burns the payee's wallet FLIP; a gift burns the caller's.
        address funder = gift ? msg.sender : payee;
        if (fromWallet != 0) flip.burnForCoinflip(funder, fromWallet);

        // Quests can layer on bonus flip credit when the quest is active/completed. Quest
        // progress is the account's for an authorized deposit and the funder's for a gift; the
        // resulting bonus flows into the account's stake below. A gift's funder pays, so it
        // registers.
        address quester = gift ? msg.sender : key;
        uint32 questId = gift ? _walletId(quester, playerState[quester], 0, true) : id;
        (
            uint256 reward,
            uint8 questType,
            uint32 streak,
            bool completed
        ) = questModule.handleFlip(questId, amount);
        uint256 questReward = _questApplyReward(
            quester,
            reward,
            questType,
            streak,
            completed
        );

        // Principal + quest bonus become the pending flip stake.
        uint256 creditedFlip = amount + questReward;
        if (fromClaimable != 0) {
            // Recycling bonus applies only to the rebet portion (not fresh money): the winnings
            // this deposit actually spent, never the wallet-funded remainder. An auto-rebuy
            // player's carry earns its own bonus where it rolls, in _claimCoinflipsInternal.
            creditedFlip += _recyclingBonus(fromClaimable);
        }
        // Direct deposits (the caller is the payee) can set the flip record and enter the BAF
        // weighted draw; operator deposits and gifts cannot. Every manual route reverts past the
        // daily cap.
        _addDailyFlip(id, creditedFlip, payee == msg.sender ? amount : 0, true);
        emit CoinflipDeposit(key, amount);
    }

    /*+======================================================================+
      |                    CLAIM FUNCTIONS                                   |
      +======================================================================+*/

    /// @notice Claim account `id`'s coinflip winnings (exact amount).
    /// @dev Processes resolved days and claims from claimableStored (accumulated from
    ///      settlements, take-profit, and mode changes). Auto-rebuy carry is never exposed.
    ///      The FLIP mints to the account's payee.
    /// @param id The account to claim for (0 = caller, else the caller must be authorized).
    /// @param amount Maximum FLIP to claim (actual may be less if insufficient claimable).
    /// @return claimed Actual amount of FLIP minted and claimed.
    function claimCoinflips(
        uint32 id,
        uint256 amount
    ) external returns (uint256 claimed) {
        (address key, address payee) = _account(id);
        return _claimCoinflipsAmount(key, payee, id, amount, true);
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
        return _claimCoinflipsAmount(player, player, 0, amount, true);
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
        return _claimCoinflipsAmount(player, player, 0, amount, false);
    }

    /// @notice Consume `amount` of `player`'s coinflip-resident backing for salvage or auto-decimator (FLIP only).
    /// @dev Settle-then-drain waterfall matching the redemption desk's withdrawRedeemedFlip: settled
    ///      claimable FIRST (no mint — removes a future mint of the consumed slice), then the rolling
    ///      auto-rebuy carry. For the vault FLIP first drains the virtual allowance (its held leg);
    ///      sDGNRS has no wallet leg, so this covers its entire backing (claimable + carry). Reaching
    ///      the carry is freeze-safe because salvage rejects the RNG lock and the automatic
    ///      sDGNRS decimator entry requires today's flip to be settled before calling here.
    /// @param player The backing owner (sDGNRS or the vault).
    /// @param amount Maximum FLIP (whole tokens) to consume from claimable + carry.
    /// @return consumed Actual amount removed (claimable consumed + carry decremented).
    function consumeFlipForSalvage(
        address player,
        uint256 amount
    ) external onlyFLIP returns (uint256 consumed) {
        consumed = _claimCoinflipsAmount(player, player, 0, amount, false);
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
    /// @dev Called by FLIP when a transfer or an intercepted mint lands on
    ///      ContractAddresses.SDGNRS: FLIP keeps the amount out of circulating supply and
    ///      routes it here, so sDGNRS never holds a wallet balance and its FLIP stays
    ///      uncirculated. Day-keyed like every deposit — the credit becomes TOMORROW's
    ///      stake, whose word cannot exist yet (the same structural freeze-safety all
    ///      player deposits have). Direct stake write, off the leaderboard/flip record like
    ///      the seed program. A win settles through the sDGNRS payout branch into
    ///      the rolling carry; claimableStored stays the genesis seed reserve burns
    ///      drain first. FLIP has already removed the whole amount from supply; the lane
    ///      takes its whole-FLIP floor and saturates at the daily cap, so this never reverts
    ///      a transfer.
    /// @param amount FLIP (whole tokens) staked onto sDGNRS's next flip.
    function creditSdgnrsBacking(uint256 amount) external onlyFLIP {
        if (amount == 0) return;
        _addFlipStake(SDGNRS_WALLET_ID, _targetFlipDay(), amount);
    }

    /// @dev Emit the player's committed coinflip claim-state (claimable + carry + cursor) for
    ///      off-chain reconstruction without an eth_call. Call as the LAST statement after the three
    ///      PlayerCoinflipState fields are finalized; never inside _claimCoinflipsInternal (its
    ///      callers finalize claimableStored after it returns, so an emit there would be stale).
    function _emitClaimState(address player) private {
        PlayerCoinflipState storage s = playerState[player];
        emit CoinflipClaimState(player, s.claimableStored, s.autoRebuyCarry, s.lastClaim);
    }

    /// @dev Internal claim exact amount for the account keyed `key` (wallet `id`, 0 = look it
    ///      up); FLIP and any loss consolation mint to `payee`. A wallet with no ID has no stake
    ///      and claims nothing.
    function _claimCoinflipsAmount(
        address key,
        address payee,
        uint32 id,
        uint256 amount,
        bool mintTokens
    ) private returns (uint256 claimed) {
        PlayerCoinflipState storage state = playerState[key];
        uint256 mintable = _claimCoinflipsInternal(payee, _walletId(key, state, id, false), state, false);
        uint128 storedBefore = state.claimableStored;
        uint256 stored = storedBefore + mintable;
        if (stored == 0) {
            // _claimCoinflipsInternal may still have advanced lastClaim / settled carry.
            _emitClaimState(key);
            return 0;
        }

        uint256 toClaim = amount;
        if (toClaim > stored) {
            toClaim = stored;
        }
        uint128 remainder = uint128(stored - toClaim);
        if (remainder != storedBefore) {
            state.claimableStored = remainder;
        }

        if (toClaim != 0) {
            if (mintTokens) {
                flip.mintForGame(payee, toClaim);
            }
            claimed = toClaim;
        }
        _emitClaimState(key);
    }

    /// @dev The wallet ID of the account keyed `key`, from its coinflip state. A miss fills the
    ///      write-once cache from `id`, the account's ID that Game `resolveAccount` resolved, or
    ///      for a self action (`id == 0`) from the Game: `allocate` (a paying action) registers a
    ///      new wallet, otherwise the lookup returns the existing ID or zero.
    function _walletId(
        address key,
        PlayerCoinflipState storage state,
        uint32 id,
        bool allocate
    ) private returns (uint32) {
        uint32 cached = state.id;
        if (cached != 0) return cached;
        if (id == 0) id = degenerusGame.registerWallet(key, allocate);
        if (id != 0) state.id = id;
        return id;
    }

    /// @dev `player`'s wallet ID for a view: the cached ID, else the Game's (0 = none).
    function _viewWalletId(address player) private view returns (uint32 id) {
        id = playerState[player].id;
        if (id == 0) id = degenerusGame.walletIdOf(player);
    }

    /// @dev Process daily coinflip claims and calculate winnings. `id` keys the stake lanes;
    ///      `payee` is the address the loss consolation mints to.
    function _claimCoinflipsInternal(
        address payee,
        uint32 id,
        PlayerCoinflipState storage state,
        bool deepAutoRebuy
    ) internal returns (uint256 mintable) {
        IDegenerusGame game = degenerusGame;
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
        if (id == 0) {
            // No wallet ID, so no stake and no carry: the walk would settle nothing, and only
            // the cursor moves.
            state.lastClaim = latest;
            return mintable;
        }

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
        (bool seeded, uint24 seedStart) = _seedWindow(id);

        // Results at or before `latest` cannot change during this walk. Cache one
        // 32-day word; the sentinel is above every uint24 day's possible word key.
        uint24 cachedResultKey = type(uint24).max;
        uint256 cachedResults;
        // Eight stake days share a word. Clear resolved lanes in memory and flush
        // once per word, preserving unresolved and out-of-window siblings. The
        // only external call inside this loop is getLastBafResolvedDay (STATICCALL,
        // reading the jackpot's own clock); no stake writer can run between load
        // and flush. Flush the final word before any mutable external call below.
        uint24 cachedStakeKey = type(uint24).max;
        uint256 cachedStakes;
        bool stakesChanged;
        // Auto-rebuy-off processes a larger fixed window while keeping tx cost bounded.
        while (remaining != 0 && cursor <= latest) {
            uint24 resultKey = cursor >> 5;
            if (resultKey != cachedResultKey) {
                cachedResults = coinflipDayResultPacked[resultKey];
                cachedResultKey = resultKey;
            }
            uint16 rewardPercent = uint8(cachedResults >> ((cursor & 31) * 8));
            bool win = rewardPercent >= 50;

            // Skip unresolved days (gaps from testnet day-advance or missed resolution)
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            uint24 stakeKey = cursor >> 3;
            if (stakeKey != cachedStakeKey) {
                if (stakesChanged) coinflipStakePacked[cachedStakeKey][id] = cachedStakes;
                cachedStakes = coinflipStakePacked[stakeKey][id];
                cachedStakeKey = stakeKey;
                stakesChanged = false;
            }
            uint256 stakeShift = (cursor & 7) << 5;
            uint256 storedStake = uint32(cachedStakes >> stakeShift);
            uint256 stake = storedStake;
            if (seeded) {
                stake += _seedStake(cursor, seedStart);
            }
            if (rebuyActive && carry != 0) {
                stake += carry;
            }

            if (storedStake != 0) {
                // Clear stake whether win or loss (loss = forfeit principal). A seed is never
                // stored: the cursor passing its day consumes it.
                cachedStakes &= ~(STAKE_LANE_MAX << stakeShift);
                stakesChanged = true;
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
                    // Inclusive: a flip that RESOLVED on the BAF day itself (staked
                    // the day before) seeds the NEXT bracket via claim-time routing,
                    // so no flip day is score-dead. Days before the resolution stay
                    // filtered out.
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

        if (stakesChanged) coinflipStakePacked[cachedStakeKey][id] = cachedStakes;

        // sDGNRS gets no BAF score: skip the recordBafFlip call entirely for it (the
        // daily coinflip resolution auto-claims sDGNRS through this walk).
        if (winningBafCredit != 0 && id != SDGNRS_WALLET_ID) {
            (uint24 cachedLevel, , , , ) = game.purchaseInfo();
            // purchaseInfo.lvl is the ACTUAL game level (one snapshot, no separate
            // level() read); the bracket keys on the real level, not the routed buy
            // level (which diverges on the final jackpot day).
            //
            // Recording is unconditional — even inside a resolving BAF window. The
            // bracket below is _bafBracketLevel(level + 1), which during an x0 window
            // is the NEXT bracket: state the pending draw never reads, so a mid-window
            // claim is freeze-safe, and a flip that resolved on the BAF day seeds the
            // next bracket rather than dying with the old one.
            //
            // BAF bracket = the level's decade ceiling: a level in [10k, 10k+9] records
            // to bracket 10*(k+1). _bafBracketLevel rounds up to the next multiple of
            // 10, so (level + 1) maps every decade — including the x10 boundary — to
            // its closing bracket.
            uint24 bafLvl = _bafBracketLevel(cachedLevel + 1);
            jackpots.recordBafFlip(id, bafLvl, winningBafCredit);
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
            wwxrp.mintPrize(payee, lossCount * COINFLIP_LOSS_WWXRP_REWARD);
        }

        return mintable;
    }

    /*+======================================================================+
      |                    STAKE MANAGEMENT                                  |
      +======================================================================+*/

    /// @dev Add daily flip stake for wallet `id`. recordAmount is the raw principal of a
    ///      direct self-funded deposit (zero for every credit path): it alone can arm
    ///      the flip record and it alone carries BAF draw weight. `manual` marks the
    ///      deposit routes (self, operator, gift): they revert StakeAboveDailyCap when the
    ///      stake with its bonuses would pass the lane's whole-FLIP cap, so the caller's
    ///      funding, quest and record mutations roll back with it. Credit routes saturate
    ///      instead, so a recipient at the cap can never brick a batch payout or the crank.
    function _addDailyFlip(
        uint32 id,
        uint256 coinflipDeposit,
        uint256 recordAmount,
        bool manual
    ) private {
        if (recordAmount != 0) {
            // Manual deposits only: check and consume coinflip boon (5%/10%/25% boost on max 100k FLIP deposit)
            // Max bonuses: 5% = 5k, 10% = 10k, 25% = 25k. The game handle is read HERE rather than
            // at the top of the frame: every credit path passes recordAmount 0, and only this
            // branch consults the game, so a credit must not pay for the storage read.
            uint16 boonBps = degenerusGame.consumeCoinflipBoon(id);
            if (boonBps > 0) {
                uint256 maxDeposit = 100_000; // Cap at 100k FLIP for boost calc
                uint256 cappedDeposit = coinflipDeposit > maxDeposit
                    ? maxDeposit
                    : coinflipDeposit;
                uint256 boost = (cappedDeposit * boonBps) / 10_000;
                coinflipDeposit += boost;
            }
        }

        // Flip record: judged on the raw direct-deposit amount (recordAmount — zero for
        // every credit path, so credits and record claims can never re-arm), not bonuses
        // or existing stake. The entry-floor gate keeps the record SLOAD off ordinary
        // deposits. No RNG-lock gate: the claim is fixed by pool state alone and rides
        // this deposit's own coin toss, so there is nothing to arm against a known word.
        // Armed AFTER the boon boost (a claim never earns the boon) and BEFORE the stake
        // read below, so the claim joins this deposit in one write and the read still
        // follows every external call this frame makes.
        if (recordAmount >= BIGGEST_FLIP_MIN && recordAmount > biggestFlipEver) {
            coinflipDeposit += _armBigRecord(
                RECORD_KIND_FLIP,
                id,
                recordAmount
            );
        }

        // Determine which future day this stake applies to (always the next window).
        uint24 targetDay = _targetFlipDay();

        // Principal, already floored bonuses and claims are summed in whole FLIP;
        // the lane event reports the accepted delta and total.
        _addFlipStake(id, targetDay, coinflipDeposit, manual);
        // BAF weighted draw: on the armed day (an x0 level's last purchase day
        // stakes it), every direct self-funded deposit appends an interval
        // weighted by its raw principal (recordAmount) — never bonuses, boon
        // boosts, record claims, or credits, so free stake carries no draw
        // weight. Ordinary days pay one warm read: bafDrawDay shares the packed
        // slot the deposit's claim walk already loaded. Credit paths (quests,
        // gifts, operator deposits, sDGNRS backing) skip even that —
        // their recordAmount is zero and the compare short-circuits.
        if (recordAmount != 0 && targetDay == bafDrawDay) {
            _appendBafDrawEntry(targetDay, id, recordAmount);
        }
    }

    /// @dev Add `amount` whole FLIP to `day`'s lane for wallet `id`, saturating at the cap, and emit
    ///      the accepted delta and total. Every stake-writing route funnels through here.
    function _addFlipStake(uint32 id, uint24 day, uint256 amount) private returns (uint256) {
        return _addFlipStake(id, day, amount, false);
    }

    /// @dev `revertAtCap` variant for manual deposits: the whole-FLIP total may not pass
    ///      STAKE_LANE_MAX. The prior lane is read fresh here, after every external call the
    ///      caller made.
    function _addFlipStake(
        uint32 id,
        uint24 day,
        uint256 amount,
        bool revertAtCap
    ) private returns (uint256 newStake) {
        uint24 key = day >> 3;
        uint256 shift = (day & 7) << 5;
        uint256 packed = coinflipStakePacked[key][id];
        uint256 prevStake = uint32(packed >> shift);
        uint256 requested = prevStake + amount;
        if (revertAtCap && requested > STAKE_LANE_MAX) revert StakeAboveDailyCap();
        newStake = requested > STAKE_LANE_MAX ? STAKE_LANE_MAX : requested;
        if (newStake != prevStake) {
            coinflipStakePacked[key][id] = (packed & ~(STAKE_LANE_MAX << shift)) | (newStake << shift);
        }
        emit CoinflipStakeUpdated(id, day, newStake - prevStake, newStake);
    }

    /// @dev Append wallet `id`'s weighted interval to the armed day's draw book.
    ///      Weight is the whole-FLIP deposited principal. The depositor's win probability
    ///      is their recorded principal divided by the day's total. Manual deposits
    ///      must fit a uint32 stake lane before reaching here; fewer than 2^32 entries
    ///      therefore sum to less than 2^64, safely inside the uint96 cumulative lane.
    function _appendBafDrawEntry(
        uint24 day,
        uint32 id,
        uint256 amount
    ) private {
        uint96 weight = _score96(amount);
        uint256 header = bafDrawHeader[day];
        uint256 newTotal = (header & type(uint96).max) + weight;
        uint32 index = uint32(header >> 96);
        bafDrawEntry[(uint256(day) << 32) | index] = (uint256(id) << 96) | newTotal;
        bafDrawHeader[day] = (uint256(index + 1) << 96) | newTotal;
        emit BafDrawEntered(day, id, index, weight, uint96(newTotal));
    }

    /// @dev Ratchets record `kind` to `candidate` and pays the claim when the candidate
    ///      clears the standing mark by a fifth: an accruing share of the record pool —
    ///      the RECORD_SHARE_* floor plus per-day growth since this category last
    ///      claimed, clamped at the ceiling. The claim is RETURNED, never credited here:
    ///      every arming path already pays the player FLIP in the same transaction, so
    ///      the caller folds the claim into that credit rather than taking a second
    ///      stake write. Every other larger candidate ratchets the mark alone, raising
    ///      the bar while the share keeps accruing. The first mark a record ever takes
    ///      has no bar to clear and draws the share accrued since deploy (the
    ///      constructor starts every category clock at the deploy day). Marks never
    ///      reset.
    ///
    ///      Callers gate their record's entry floor, so a mark is always 0 or at or
    ///      above that floor — a sub-floor candidate could not have beaten it anyway.
    ///
    ///      Every ratchet calls the Game's `payRecordSdgnrs` (share 0 when the candidate does
    ///      not clear the claim bar), which names the payee the trophy goes to.
    /// @param kind Which record (RECORD_KIND_*).
    /// @param id The wallet ID the record and any claim accrue to (nonzero: callers hold it).
    /// @param candidate The value offered against the mark, in the record's unit.
    ///        Width-bound to uint128 by every caller: the flip deposit's two funding
    ///        legs are each uint128-bound (claimableStored width, FLIP._burn supply
    ///        accounting), the spin and lootbox units are ETH wei, and the buy unit
    ///        is a whole-ticket count.
    /// @return paid FLIP drawn from the record pool for the caller to credit.
    function _armBigRecord(
        uint8 kind,
        uint32 id,
        uint256 candidate
    ) private returns (uint128 paid) {
        uint128 mark;
        if (kind == RECORD_KIND_FLIP) mark = biggestFlipEver;
        else if (kind == RECORD_KIND_SPIN) mark = biggestSpinEver;
        else if (kind == RECORD_KIND_LUCKBOX) mark = biggestLuckboxEver;
        else mark = biggestBuyEver;
        if (candidate <= mark) return 0;

        uint256 shareBps;
        // A first mark has no bar to clear; after that the candidate must clear the
        // mark by an exact fifth: `mark + mark / 5` floors the bar, so a mark not
        // divisible by five would let a candidate claim on strictly less than a
        // fifth. Multiplying the increase instead is exact.
        if (mark == 0 || (candidate - mark) * RECORD_BEAT_DIV >= mark) {
            uint24 today = GameTimeLib.currentDayIndex();
            uint256 stamped = _recordDay(kind);
            shareBps = RECORD_SHARE_FLOOR_BPS +
                (uint256(today) > stamped ? uint256(today) - stamped : 0) *
                RECORD_SHARE_PER_DAY_BPS;
            if (shareBps > RECORD_SHARE_CEIL_BPS) {
                shareBps = RECORD_SHARE_CEIL_BPS;
            }
            uint128 pool = recordPool;
            paid = uint128((uint256(pool) * shareBps) / 10_000);
            if (paid != 0) {
                recordPool = pool - paid;
            }
            _stampRecordDay(kind, today);
        }
        // The sDGNRS leg rides the same accrued share at 1/500 scale, drawn from the
        // sDGNRS reward pool via the game (which sDGNRS authorizes); a bare ratchet
        // passes share 0 and only learns the payee.
        (uint256 sdgnrsPaid, address payee) = degenerusGame.payRecordSdgnrs(id, shareBps);

        if (kind == RECORD_KIND_FLIP) biggestFlipEver = uint128(candidate);
        else if (kind == RECORD_KIND_SPIN) biggestSpinEver = uint128(candidate);
        else if (kind == RECORD_KIND_LUCKBOX) biggestLuckboxEver = uint128(candidate);
        else biggestBuyEver = uint128(candidate);
        emit BigRecordUpdated(kind, id, candidate, paid, sdgnrsPaid);

        // Hand the record's soulbound trophy to the new mark holder. Every
        // ratchet moves it — the claim bar gates only the pool share, never the
        // trophy. Cosmetic-only state (nothing game-side reads the trophy
        // contract), and recordSet does no recipient callback, so the call
        // cannot re-enter or brick the arming path.
        IDegenerusRecordBounty(ContractAddresses.RECORD_BOUNTY).recordSet(
            kind,
            payee,
            candidate
        );
    }

    /// @dev The day record category `kind` last claimed (or bootstrapped).
    function _recordDay(uint8 kind) private view returns (uint24) {
        if (kind == RECORD_KIND_FLIP) return recordDayFlip;
        if (kind == RECORD_KIND_SPIN) return recordDaySpin;
        if (kind == RECORD_KIND_LUCKBOX) return recordDayLuckbox;
        return recordDayBuy;
    }

    /// @dev Stamp record category `kind`'s claim clock to `day`.
    function _stampRecordDay(uint8 kind, uint24 day) private {
        if (kind == RECORD_KIND_FLIP) recordDayFlip = day;
        else if (kind == RECORD_KIND_SPIN) recordDaySpin = day;
        else if (kind == RECORD_KIND_LUCKBOX) recordDayLuckbox = day;
        else recordDayBuy = day;
    }

    /// @notice Arm a game-side all-time record for wallet `id` with `candidate` in the
    ///         record's own unit (spin and lootbox deposit: ETH wei; buy: whole tickets).
    /// @dev GAME only — the modules gate each record's entry floor at the call site
    ///      before paying for this call, and each passes its own kind as a constant.
    ///      The flip record arms internally on direct deposits; nothing routes it here.
    /// @param kind Which record (RECORD_KIND_*), excluding flip and dice run.
    /// @param id The wallet ID whose candidate is being armed (nonzero).
    /// @param candidate The candidate mark to ratchet the record with.
    /// @return The FLIP claimed from the pool, for the calling module to fold into the
    ///         FLIP its own path already pays. Nothing is credited here.
    function armRecord(
        uint8 kind,
        uint32 id,
        uint256 candidate
    ) external onlyDegenerusGameContract returns (uint256) {
        return _armBigRecord(kind, id, candidate);
    }

    /// @notice Arm THE BIGGEST DICE RUN with `candidate`, the winning scheduled craps
    ///         run's high point over its own starting bankroll in score basis points.
    /// @dev CRAPS ONLY, and this kind only. It is deliberately NOT the generic
    ///      `armRecord` door: that one is the GAME's and carries the four existing
    ///      kinds' rule that a claim must beat the standing mark by a fifth, which is
    ///      not this kind's rule and must not become it. Nothing here funds the pool,
    ///      adds a drip, or changes a take rate — the dice run is a fifth way to CLAIM
    ///      from a pool that already exists.
    ///
    ///      THE CLAIM RULE. Every strict improvement at or above the floor ratchets the
    ///      mark, moves the trophy, and claims the accruing share — 5% plus half a point
    ///      per elapsed day, capped at 75% — and then stamps the clock to today.
    ///
    ///      THE CLOCK IS THE ANTI-STACKING RULE, and it needs no second one. Craps fields
    ///      close on their own schedule and are finalized by whoever cranks them, so a
    ///      keeper walking several already-closed fields in ASCENDING order of high point
    ///      makes each of them a strict improvement. The reset is what prices that: the
    ///      first claim of a day takes its accrued share, and every further claim that day
    ///      takes 5% of what the previous one left. Stacking `k` claims in a day therefore
    ///      costs the pool `1 - 0.95^k` beyond the first rather than `k` accrued shares,
    ///      and every one of them had to be a genuine new record.
    ///
    ///      What ordering cannot move: the day's final MARK and the trophy holder are the
    ///      maximum over the day's candidates however the fields were resolved.
    ///
    ///      The claim is CREDITED HERE rather than returned: unlike the other kinds,
    ///      nothing on the craps side is already paying this player in the same call, so
    ///      handing the figure back would only buy a second cross-contract hop. The
    ///      sDGNRS leg rides the same accrued share as every other record's.
    /// @param id The winning scheduled run owner's wallet ID (nonzero: every seat holds one).
    /// @param candidate The high-point score in basis points (10,000 = 1x).
    /// @return claimed FLIP credited out of the shared record pool; zero for a ratchet
    ///         that claimed nothing.
    function armDiceRunRecord(
        uint32 id,
        uint256 candidate
    ) external returns (uint256 claimed) {
        if (msg.sender != ContractAddresses.CRAPS) revert OnlyCraps();
        if (candidate < BIGGEST_DICE_RUN_MIN) return 0;
        uint128 mark = biggestDiceRunEver;
        if (candidate <= mark) return 0;
        biggestDiceRunEver = uint128(candidate);

        uint24 today = GameTimeLib.currentDayIndex();
        uint256 stamped = recordDayDiceRun;
        uint256 shareBps = RECORD_SHARE_FLOOR_BPS +
            (uint256(today) > stamped ? uint256(today) - stamped : 0) *
            RECORD_SHARE_PER_DAY_BPS;
        if (shareBps > RECORD_SHARE_CEIL_BPS) {
            shareBps = RECORD_SHARE_CEIL_BPS;
        }
        uint128 pool = recordPool;
        uint128 paid = uint128((uint256(pool) * shareBps) / 10_000);
        if (paid != 0) {
            recordPool = pool - paid;
            _addDailyFlip(id, paid, 0, false);
        }
        // The sDGNRS leg rides the same accrued share at 1/500 scale, exactly as the
        // other four kinds' does. A record is a record: the dice run claims from the
        // shared pool on its own rule, and is paid alongside it on everyone else's.
        (uint256 sdgnrsPaid, address payee) = degenerusGame.payRecordSdgnrs(id, shareBps);
        recordDayDiceRun = today;
        emit BigRecordUpdated(RECORD_KIND_DICE_RUN, id, candidate, paid, sdgnrsPaid);

        IDegenerusRecordBounty(ContractAddresses.RECORD_BOUNTY).recordSet(
            RECORD_KIND_DICE_RUN,
            payee,
            candidate
        );
        return paid;
    }

    /// @notice Arm this century's seed window: SEED_FLIP_DAILY per day for
    ///         SEED_FLIP_DAYS days to VAULT and to sDGNRS, on the same terms as the deploy program.
    /// @dev GAME only, called from the advance as an x00 level's transition closes and the next
    ///      purchase phase opens. It has no revert path by design: a revert here would brick the
    ///      daily crank at a level boundary, so a call with nothing due simply writes nothing. It
    ///      arms the LOWEST unarmed century, so a boundary the game passed without arming is
    ///      picked up by the next one rather than lost.
    ///
    ///      Takes the level from the caller rather than reading `purchaseInfo` back, which
    ///      would re-enter a mid-advance game. No RNG-lock gate is needed: the window starts
    ///      at `_targetFlipDay()`, strictly later than the day any pending word resolves.
    ///
    ///      Arming stores the window's first day and writes no stake lane: the claim walk adds
    ///      the seed to whatever a window day's lane holds, so a stake sDGNRS has already rolled
    ///      forward onto that day is kept.
    /// @param lvl The level whose jackpot phase just ended.
    function armCenturySeed(uint24 lvl) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();

        uint24 century = lastSeededCentury + 1;
        if (uint256(lvl) < uint256(century) * SEED_CENTURY_LEVELS) return;
        lastSeededCentury = century;

        uint24 firstDay = _targetFlipDay();
        seedWindowStart = firstDay;

        emit SeedWindowArmed(century, firstDay, SEED_FLIP_DAYS, SEED_FLIP_DAILY);
    }

    /// @notice Add FLIP to the shared record pool.
    /// @dev GAME only. Level transitions push 0.2% of the completed level's prize pool,
    ///      converted notionally at that level's ticket price — no ETH moves. Clamped
    ///      at the pool's uint128 width rather than wrapping, so a huge push cannot
    ///      zero an accrued pool.
    function fundRecordPool(uint256 amount) external onlyDegenerusGameContract {
        uint256 grown = uint256(recordPool) + amount;
        recordPool = grown > type(uint128).max
            ? type(uint128).max
            : uint128(grown);
    }

    /// @notice Arm flip day `day` for the BAF weighted draw (GAME only).
    /// @dev The advance path arms exactly one day per BAF bracket: when an x0
    ///      purchase level enters its last purchase day, it arms day + 1 — the flip
    ///      day the sealed window's direct deposits stake, and the day the bracket's
    ///      transition word resolves. Entries close structurally at the day
    ///      boundary, before that word can be requested.
    function armBafDraw(uint24 day) external onlyDegenerusGameContract {
        bafDrawDay = day;
        emit BafDrawArmed(day);
    }

    /*+======================================================================+
      |                    AUTO-REBUY FUNCTIONS                              |
      +======================================================================+*/

    /// @notice True once today's flip has been applied — its VRF word recorded and paid out.
    /// @dev Settlement marker for the carry freeze, and the sole gate on every carry mutator.
    ///      The advance records the day's word and runs processCoinflipPayouts in one step, so
    ///      past this point the carry has resolved through today's word and rides tomorrow —
    ///      whose word has not been requested. The game's RNG lock is deliberately NOT read:
    ///      it spans request -> _unlockRng and advanceGame defers that unlock behind chunked
    ///      ticket drains, a pending daily jackpot, and a phase transition, so it stays up long
    ///      after the word that priced the carry was consumed. This marker is also strictly
    ///      tighter than the lock — it stays shut from the day boundary until the word lands,
    ///      covering the pre-request gap the lock leaves open — and needs no cross-contract
    ///      read. `day` never exceeds the wall day (the advance clamps it down to dailyIdx + 1),
    ///      so equality is the settled state and the comparison cannot open early.
    function flipResolvedToday() external view returns (bool) {
        return flipsClaimableDay >= GameTimeLib.currentDayIndex();
    }

    /// @dev Freeze predicate for the carry: today's flip is unapplied, so a word that prices the
    ///      carry may be knowable but unconsumed.
    function _flipFrozen() private view returns (bool) {
        return flipsClaimableDay < GameTimeLib.currentDayIndex();
    }

    /// @notice Configure auto-rebuy mode for account `id`'s coinflips.
    /// @dev Any FLIP the mode change surfaces mints to the account's payee.
    /// @param id The account to configure (0 = caller, else the caller must be authorized).
    /// @param enabled True to enable auto-rebuy, false to disable and cash out carry.
    /// @param takeProfit Threshold up to uint128 max: every whole multiple in a win is banked, the remainder rolls (0 = roll all). Ignored when disabling.
    function setCoinflipAutoRebuy(
        uint32 id,
        bool enabled,
        uint256 takeProfit
    ) external {
        (address key, address payee) = _account(id);
        _setCoinflipAutoRebuy(key, payee, id, enabled, takeProfit);
    }

    /// @notice Set account `id`'s auto-rebuy take profit.
    /// @dev Any settled winnings the update surfaces mint to the account's payee.
    /// @param id The account to configure (0 = caller, else the caller must be authorized).
    /// @param takeProfit New take-profit threshold, at most uint128 max (0 = roll all winnings).
    function setCoinflipAutoRebuyTakeProfit(
        uint32 id,
        uint256 takeProfit
    ) external {
        (address key, address payee) = _account(id);
        _setCoinflipAutoRebuyTakeProfit(key, payee, id, takeProfit);
    }

    /// @dev Internal auto-rebuy configuration.
    ///      A position already on auto-rebuy is frozen while a day is unresolved: it holds a
    ///      carry that the pending word prices, so toggling off would extract it before a known
    ///      loss. Arming stays open while only today is unresolved (a known result can only roll
    ///      into an unknown day) but is frozen once two or more days are unresolved: after a stall
    ///      every such day's result derives from one delivered word, and arming then would
    ///      compound a stake through a run of results that are already readable.
    function _setCoinflipAutoRebuy(
        address key,
        address payee,
        uint32 id,
        bool enabled,
        uint256 takeProfit
    ) private {
        PlayerCoinflipState storage state = playerState[key];
        uint256 mintable;
        if (_flipFrozen() && (state.autoRebuyEnabled || flipsClaimableDay + 1 < GameTimeLib.currentDayIndex())) {
            revert RngLocked();
        }
        id = _walletId(key, state, id, false);

        if (enabled) {
            if (takeProfit > type(uint128).max) revert TakeProfitTooLarge();
            if (state.autoRebuyEnabled) revert AutoRebuyAlreadyEnabled();
            mintable = _claimCoinflipsInternal(payee, id, state, false);
            state.autoRebuyStop = uint128(takeProfit);
            state.autoRebuyEnabled = true;
            state.autoRebuyStartDay = state.lastClaim;
            emit CoinflipAutoRebuyStopSet(key, takeProfit);
            emit CoinflipAutoRebuyToggled(key, true);
        } else {
            mintable = _claimCoinflipsInternal(payee, id, state, true);
            uint256 carry = state.autoRebuyCarry;
            if (carry != 0) {
                mintable += carry;
                state.autoRebuyCarry = 0;
            }
            state.autoRebuyEnabled = false;
            state.autoRebuyStartDay = 0;
            emit CoinflipAutoRebuyToggled(key, false);
        }

        if (mintable != 0) {
            flip.mintForGame(payee, mintable);
        }
        _emitClaimState(key);
    }

    /// @dev Internal auto-rebuy take profit configuration.
    ///      Blocked while today's flip is frozen — the threshold splits the pending day's payout
    ///      between the banked chunk and the rolling carry, so a known win could be banked whole.
    ///      The enablement check leads, so only a position actually on auto-rebuy meets the freeze.
    function _setCoinflipAutoRebuyTakeProfit(
        address key,
        address payee,
        uint32 id,
        uint256 takeProfit
    ) private {
        PlayerCoinflipState storage state = playerState[key];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();
        if (_flipFrozen()) revert RngLocked();
        if (takeProfit > type(uint128).max) revert TakeProfitTooLarge();

        uint256 mintable = _claimCoinflipsInternal(payee, _walletId(key, state, id, false), state, false);
        state.autoRebuyStop = uint128(takeProfit);
        emit CoinflipAutoRebuyStopSet(key, takeProfit);

        if (mintable != 0) {
            flip.mintForGame(payee, mintable);
        }
        _emitClaimState(key);
    }

    /// @notice Claim up to `amount` of the auto-rebuy carry as minted FLIP while
    ///         staying on auto-rebuy; the remainder keeps rolling.
    /// @dev Runs the ordinary bounded claim walk FIRST — up to `COIN_CLAIM_FIRST_DAYS` days on
    ///      a first claim and `COIN_CLAIM_DAYS` after, wins rolling into the carry per the
    ///      take-profit config and a loss zeroing it — then withdraws from the carry as
    ///      settled so far. A longer backlog needs the walk repeated before the carry is final.
    ///      Blocked while today's flip is frozen for the same reason as the
    ///      rebuy toggle: the carry is the pending day's stake, and the day's word may
    ///      already be on-chain before the resolution walk applies it. Take-profit
    ///      chunks surfaced by the settle bank into claimableStored (claimCoinflips
    ///      territory); this function pays out of the carry only.
    ///      The FLIP mints to the account's payee.
    /// @param id The account to claim for (0 = caller, else the caller must be authorized).
    /// @param amount Maximum carry to claim.
    /// @return claimed Actual amount of FLIP minted from the carry.
    function claimCoinflipCarry(
        uint32 id,
        uint256 amount
    ) external returns (uint256 claimed) {
        (address key, address payee) = _account(id);
        PlayerCoinflipState storage state = playerState[key];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();
        if (_flipFrozen()) revert RngLocked();

        uint256 mintable = _claimCoinflipsInternal(payee, _walletId(key, state, id, false), state, false);
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
            flip.mintForGame(payee, claimed);
        }
        _emitClaimState(key);
    }

    /*+======================================================================+
      |                    RNG PROCESSING                                    |
      +======================================================================+*/

    /// @notice Process coinflip payout for a day (called by game contract).
    /// @param bonus Reward-percent bonus for this day, precomputed by the caller from frozen state:
    ///        0 = normal day, 2 = bonus day (a level-0 day, the second day of a level's jackpot
    ///        phase, or the first purchase day after a turbo collapse), 6 = the same on an x0
    ///        BAF level (10, 20, 30, …).
    /// @param rngWord VRF-derived random word for determining win/loss and bonus.
    /// @param epoch The day index being resolved.
    function processCoinflipPayouts(
        uint8 bonus,
        uint256 rngWord,
        uint24 epoch
    ) external onlyDegenerusGameContract {
        uint16 rewardPercent = _coinflipReward(bonus, rngWord, epoch);
        bool win = (rngWord & 1) == 1;
        _storeDayResult(epoch, rewardPercent, win);
        _settleCoinflipDay(epoch, rewardPercent, win);
    }

    /// @dev Tagged reward derivation for normally resolved days. `bonus` is precomputed by the
    ///      caller from frozen protocol state (not a player-flippable flag): 0 on a normal day,
    ///      +2 on a bonus day (a level-0 day, the second day of a level's jackpot phase, or the
    ///      first purchase day after a turbo collapse), +6 on an x0 BAF-level bonus day. Sized so
    ///      a recycling player nets ~99.9% / ~101.9% RTP after the recycle bonus compounds.
    function _coinflipReward(uint8 bonus, uint256 rngWord, uint24 epoch) private pure returns (uint16) {
        return FlipRoundLib.coinflipRewardPercent(bonus, rngWord, epoch);
    }

    /// @notice Resolve at most 31 skipped days at double-or-nothing payouts.
    /// @dev Raw root bits 1..31 supply wins in the caller's original day order; bit 0
    ///      stays separate for the recovery day. Every gap reward is fixed at 100% profit.
    ///      Skipping an already-settled prefix must not restart the bit sequence.
    ///      The Game's shared recovery caller caps the range to 31 days before this call.
    function processCoinflipGap(uint256 root, uint24 start, uint24 end) external onlyDegenerusGameContract {
        if (end <= start) return;
        uint24 originalStart = start;
        if (start <= flipsClaimableDay) start = flipsClaimableDay + 1;
        if (end <= start) return;
        uint32 wins = uint32(root >> (1 + uint256(start) - originalStart));
        uint24 key = start >> 5;
        uint256 packed = coinflipDayResultPacked[key];
        for (uint24 day = start; day < end; ++day) {
            uint24 nextKey = day >> 5;
            if (nextKey != key) {
                coinflipDayResultPacked[key] = packed;
                key = nextKey;
                packed = coinflipDayResultPacked[key];
            }
            uint256 offset = day - start;
            bool win = wins & (uint32(1) << offset) != 0;
            uint256 shift = (day & 31) * 8;
            packed = (packed & ~(uint256(255) << shift)) | (uint256(win ? 100 : 1) << shift);
        }
        coinflipDayResultPacked[key] = packed;
        // Preserve per-day funding, seed-window transitions, and sequential sDGNRS carry.
        for (uint24 day = start; day < end; ++day) {
            _settleCoinflipDay(day, 100, wins & 1 != 0);
            wins >>= 1;
        }
    }

    function _settleCoinflipDay(uint24 epoch, uint16 rewardPercent, bool win) private {
        // Move the active window forward; the resolved day becomes claimable immediately.
        flipsClaimableDay = epoch;

        // Daily drip into the shared record pool. Saturating like fundRecordPool:
        // a wrap here would zero a pool the funding path deliberately clamped.
        uint128 newPool = recordPool;
        unchecked {
            newPool = newPool > type(uint128).max - uint128(RECORD_POOL_DAILY_FLIP)
                ? type(uint128).max
                : newPool + uint128(RECORD_POOL_DAILY_FLIP);
        }
        recordPool = newPool;

        emit CoinflipDayResolved(epoch, win, rewardPercent, newPool);

        // Keep sDGNRS's flip cursor current (BAF is skipped for sDGNRS, so both paths
        // stay off the rngLocked guard). sDGNRS never mints FLIP to a wallet balance:
        // its FLIP stays uncirculated as coinflip backing and is read by redemptions /
        // salvage as claimableStored + carry. During the seed window each settled win
        // folds into claimableStored — the genesis seed reserve burns drain first;
        // once auto-rebuy is armed, winnings (including incoming credits staked via
        // creditSdgnrsBacking) settle into the rolling carry (structurally zero
        // return under 0-take-profit rebuy). FLIP leaves sDGNRS's position solely
        // through a redemption/salvage consume leg or the opening-day decimator burn.
        //
        // The seed reserve does not drip onto the active flip. It remains available to
        // redemptions, salvage, and the capped opening-day decimator entry; only new flip
        // credits and existing carry ride the daily result after auto-rebuy is armed.
        PlayerCoinflipState storage sdgnrsState = playerState[
            ContractAddresses.SDGNRS
        ];
        if (sdgnrsAutoRebuyArmed) {
            _claimCoinflipsInternal(ContractAddresses.SDGNRS, SDGNRS_WALLET_ID, sdgnrsState, false);
        } else {
            uint256 mintable =
                _claimCoinflipsInternal(ContractAddresses.SDGNRS, SDGNRS_WALLET_ID, sdgnrsState, false);
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

    /// @notice Credit flip to wallet `id` through the authorized protocol/game creditor lane.
    /// @dev Keyed by wallet ID alone: writes the ID-keyed stake lane and never reads the
    ///      address-keyed player state. The credit floors to whole FLIP on its own (two sub-FLIP
    ///      credits add nothing) and saturates at the daily cap; CoinflipStakeUpdated reports the
    ///      accepted amount. A zero ID or amount is a no-op.
    /// @param id The wallet ID receiving the flip credit (0 = no wallet: skipped).
    /// @param amount Amount of FLIP-denominated flip stake to credit.
    function creditFlip(
        uint32 id,
        uint256 amount
    ) external onlyFlipCreditors {
        if (id == 0 || amount == 0) return;
        _addDailyFlip(id, amount, 0, false);
    }

    /// @notice Credit flips to multiple wallets (called by GAME jackpot modules, the craps
    ///         table and the PARIMUTUEL settlement stage).
    /// @param ids Wallet IDs to credit (0 entries are skipped).
    /// @param amounts FLIP-denominated flip stake amounts, one per ID (0 entries are skipped).
    function creditFlipBatch(
        uint32[] calldata ids,
        uint256[] calldata amounts
    ) external onlyFlipCreditors {
        uint256 len = ids.length;
        for (uint256 i; i < len; ) {
            uint32 id = ids[i];
            uint256 amount = amounts[i];
            if (id != 0 && amount != 0) {
                _addDailyFlip(id, amount, 0, false);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Credit flips to exactly two wallets (called by the GAME purchase path).
    /// @dev Fixed-arity variant of creditFlipBatch for the purchase hot path — spares the
    ///      caller the two array allocations and the dynamic ABI encode. Zero-ID and
    ///      zero-amount legs are skipped, matching the batch behavior.
    /// @param id1 First recipient wallet ID (0 entries are skipped).
    /// @param amount1 First FLIP-denominated flip stake amount (0 entries are skipped).
    /// @param id2 Second recipient wallet ID (0 entries are skipped).
    /// @param amount2 Second FLIP-denominated flip stake amount (0 entries are skipped).
    function creditFlipPair(
        uint32 id1,
        uint256 amount1,
        uint32 id2,
        uint256 amount2
    ) external onlyFlipCreditors {
        if (id1 != 0 && amount1 != 0) {
            _addDailyFlip(id1, amount1, 0, false);
        }
        if (id2 != 0 && amount2 != 0) {
            _addDailyFlip(id2, amount2, 0, false);
        }
    }

    /// @notice Settle-then-read sDGNRS's redeemable FLIP coinflip backing (sDGNRS only).
    /// @dev Forces all resolved days into claimableStored / autoRebuyCarry first so the two summed
    ///      components are disjoint and current even after a multi-day advance stall (otherwise a
    ///      resolved-but-unsettled win day could be counted in both claimable and the carry). In
    ///      steady state sDGNRS is already settled each advance, so the walk is a no-op.
    /// @return backing sDGNRS's claimableStored + autoRebuyCarry — its settled FLIP
    ///         backing (sDGNRS never holds a wallet balance; incoming FLIP de-circulates
    ///         into tomorrow's stake and settles here; claimableStored is the genesis
    ///         seed reserve burns drain first).
    function redeemableFlipBacking() external returns (uint256 backing) {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlysDGNRS();
        address s = ContractAddresses.SDGNRS;
        PlayerCoinflipState storage state = playerState[s];
        uint256 mintable = _claimCoinflipsInternal(s, SDGNRS_WALLET_ID, state, false);
        if (mintable != 0) {
            state.claimableStored = uint128(uint256(state.claimableStored) + mintable);
        }
        _emitClaimState(s);
        return uint256(state.claimableStored) + uint256(state.autoRebuyCarry);
    }

    /// @notice Remove up to `base` whole FLIP of sDGNRS's own FLIP backing as a redemption batch
    ///         closes (sDGNRS only). Never reverts on the amount.
    /// @dev Waterfall: settled claimable (consumed, no mint) → auto-rebuy carry (decremented) —
    ///      sDGNRS holds no wallet balance, so its backing lives entirely in these two. Credits
    ///      NOTHING — the batch escrow is paid later, only on the batch's synthetic flip win, via
    ///      creditFlip, so the win path is a pure deferred mint of an amount already removed from
    ///      sDGNRS's backing here. sDGNRS sizes `base` from redeemableFlipBacking in the same
    ///      close, so the clamp to the carry only keeps the batch close total.
    /// @param base The whole-FLIP backing to remove from sDGNRS.
    /// @return removed Whole FLIP actually removed (equals `base` unless the clamp binds).
    function withdrawRedeemedFlip(uint256 base) external returns (uint256 removed) {
        if (msg.sender != ContractAddresses.SDGNRS) revert OnlysDGNRS();
        if (base == 0) return 0;
        address s = ContractAddresses.SDGNRS;

        // Consume the settled genesis seed reserve first (no token mint — removes a
        // future mint of `removed`).
        removed = _claimCoinflipsAmount(s, s, SDGNRS_WALLET_ID, base, false);
        uint256 remainder = base - removed;
        if (remainder == 0) return removed;

        // Decrement the rolling auto-rebuy carry for the rest (post-day-20 steady state).
        PlayerCoinflipState storage state = playerState[s];
        uint256 carry = state.autoRebuyCarry;
        if (remainder > carry) remainder = carry;
        unchecked {
            state.autoRebuyCarry = uint128(carry - remainder);
            removed += remainder;
        }
        _emitClaimState(s);
    }

    /*+======================================================================+
      |                    VIEW FUNCTIONS                                    |
      +======================================================================+*/

    /// @notice Preview claimable coinflip winnings.
    /// @dev Equals the ceiling `claimCoinflips` would pay: the settled bank plus whatever
    ///      the pending resolved days surface. The carry is excluded — it is not claimable
    ///      through this path — except where a disabled position still holds one, which a
    ///      claim cashes out.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
        PlayerCoinflipState storage state = playerState[player];
        (uint256 daily, ) = _viewClaimableCoin(state, _viewWalletId(player));
        return daily + state.claimableStored;
    }

    /// @notice Preview `player`'s salvage-spendable coinflip backing: claimable + auto-rebuy carry (view).
    /// @dev The carry-inclusive read the salvage quote caps against, mirroring
    ///      redeemableFlipBacking's components but as a pure VIEW (no settle) so the preview
    ///      and execution offer stay re-derivable. Both legs come from the same replay, so
    ///      the carry reported is the one the settle LEAVES — a pending losing day has
    ///      already wiped it here, exactly as consumeFlipForSalvage will.
    function previewSalvageFlipBacking(address player) external view returns (uint256) {
        PlayerCoinflipState storage state = playerState[player];
        (uint256 daily, uint256 carry) = _viewClaimableCoin(state, _viewWalletId(player));
        return daily + state.claimableStored + carry;
    }

    /// @notice Get player's current coinflip stake for next day, the VAULT and sDGNRS seed included.
    function coinflipAmount(address player) external view returns (uint256 amount) {
        uint24 targetDay = _targetFlipDay();
        uint32 id = _viewWalletId(player);
        amount = _flipStake(targetDay, id);
        (bool seeded, uint24 seedStart) = _seedWindow(id);
        if (seeded) {
            amount += _seedStake(targetDay, seedStart);
        }
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

    /// @notice One amount-weighted random winner among the armed day's direct
    ///         deposits as a wallet ID, or 0 when the day recorded no entries (the BAF
    ///         slice then refunds its 5% share to the pool).
    /// @dev Winner probability = a player's recorded principal / the day's total,
    ///      by cumulative-interval measure. The roll is domain-separated from the
    ///      BAF transition word (fixed tag, this contract, the armed day), so it
    ///      perturbs no other consumer of that word. Winner = the entry with the
    ///      smallest cumulative endpoint strictly above the roll, by binary search.
    /// @param rngWord The BAF transition VRF word.
    /// @return winnerId The drawn depositor's wallet ID, or 0 if the armed day recorded no entries.
    function bafDrawWinner(uint256 rngWord) external view returns (uint32 winnerId) {
        uint24 day = bafDrawDay;
        uint256 header = bafDrawHeader[day];
        uint256 total = header & type(uint96).max;
        if (total == 0) return 0;
        uint256 roll = uint256(
            keccak256(abi.encodePacked(BAF_DRAW_TAG, address(this), day, rngWord))
        ) % total;

        // Smallest index whose cumulative endpoint exceeds the roll.
        uint32 lo;
        uint32 hi = uint32(header >> 96) - 1;
        while (lo < hi) {
            uint32 mid = lo + (hi - lo) / 2;
            if ((bafDrawEntry[(uint256(day) << 32) | mid] & type(uint96).max) > roll) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        }
        winnerId = uint32(bafDrawEntry[(uint256(day) << 32) | lo] >> 96);
    }

    /// @notice The armed BAF draw day and its book totals.
    function bafDrawInfo()
        external
        view
        returns (uint24 day, uint96 totalWeight, uint32 entryCount)
    {
        day = bafDrawDay;
        uint256 header = bafDrawHeader[day];
        totalWeight = uint96(header);
        entryCount = uint32(header >> 96);
    }

    /// @notice A recorded draw entry's depositor wallet ID and cumulative endpoint (whole FLIP).
    function bafDrawEntryAt(
        uint24 day,
        uint32 index
    ) external view returns (uint32 id, uint96 cumulativeWeight) {
        uint256 entry = bafDrawEntry[(uint256(day) << 32) | index];
        id = uint32(entry >> 96);
        cumulativeWeight = uint96(entry);
    }

    /// @dev View twin of the settle walk in _claimCoinflipsInternal: replays the resolved
    ///      days a claim would process and reports what they leave behind, so a preview and
    ///      the claim that follows it can never disagree.
    ///
    ///      Auto-rebuy accounting is mirrored, not approximated. A rebuy position is ONE
    ///      rolling stake, not a series of independent day payouts: the carry joins every
    ///      day's stake, a win splits into banked take-profit chunks plus a re-rolled
    ///      remainder carrying its recycle bonus, and a loss zeroes the whole carry. Scoring
    ///      each winning day on its stored stake alone would report a win that a later
    ///      losing day has already destroyed.
    ///
    ///      Walks the non-deep window (COIN_CLAIM_FIRST_DAYS / COIN_CLAIM_DAYS), matching
    ///      every consumer of the two preview views; the deeper walk belongs to the
    ///      auto-rebuy exit, which is not previewed.
    /// @param state The position to replay.
    /// @param id The position's wallet ID (0 = none: no stake to replay).
    /// @return mintable Winnings a claim would surface: settled payouts and banked
    ///         take-profit chunks, plus a stale carry left on a disabled position.
    /// @return endCarry The rolling carry the walk leaves in place; 0 when auto-rebuy is off.
    function _viewClaimableCoin(
        PlayerCoinflipState storage state,
        uint32 id
    ) internal view returns (uint256 mintable, uint256 endCarry) {
        uint24 latestDay = flipsClaimableDay;
        uint24 startDay = state.lastClaim;

        bool rebuyActive = state.autoRebuyEnabled;
        uint256 carry = state.autoRebuyCarry;
        if (rebuyActive) {
            endCarry = carry;
        } else if (carry != 0) {
            // A disabled position's leftover carry cashes out on the next claim.
            mintable = carry;
            carry = 0;
        }
        if (startDay >= latestDay || id == 0) return (mintable, endCarry);

        uint256 takeProfit = rebuyActive ? state.autoRebuyStop : 0;

        uint16 windowDays = startDay == 0 ? COIN_CLAIM_FIRST_DAYS : COIN_CLAIM_DAYS;
        uint24 minClaimableDay;
        if (rebuyActive) {
            minClaimableDay = state.autoRebuyStartDay;
            if (minClaimableDay > latestDay) {
                minClaimableDay = latestDay;
            }
        } else {
            unchecked {
                minClaimableDay = latestDay > windowDays
                    ? latestDay - windowDays
                    : 0;
            }
        }
        if (startDay < minClaimableDay) {
            startDay = minClaimableDay;
            if (rebuyActive && carry != 0) {
                carry = 0;
            }
        }

        uint16 remaining = windowDays;
        uint24 cursor;
        unchecked {
            cursor = startDay + 1;
        }
        (bool seeded, uint24 seedStart) = _seedWindow(id);
        while (remaining != 0 && cursor <= latestDay) {
            (uint16 rewardPercent, bool win) = _dayResult(cursor);
            // Skip unresolved days (both fields zero) instead of breaking,
            // to handle gaps from testnet day-advance or missed resolution.
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            uint256 stake = _flipStake(cursor, id);
            if (seeded) {
                stake += _seedStake(cursor, seedStart);
            }
            if (rebuyActive && carry != 0) {
                stake += carry;
            }

            if (stake != 0) {
                if (win) {
                    // Payout = principal + (principal * rewardPercent%)
                    uint256 payout = stake +
                        (stake * uint256(rewardPercent)) /
                        100;
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
                } else if (rebuyActive) {
                    carry = 0;
                }
            }
            unchecked {
                ++cursor;
                --remaining;
            }
        }
        if (rebuyActive) {
            endCarry = carry;
        }
    }

    /*+======================================================================+
      |                    INTERNAL HELPER FUNCTIONS                         |
      +======================================================================+*/

    /// @dev Wallet `id`'s stake for `day` in whole FLIP: 8 days per slot (key = day >> 3),
    ///      with 32-bit lanes. Ordinary callers read fresh; the claim walk caches
    ///      its words locally and flushes before any mutable external call.
    function _flipStake(uint24 day, uint32 id) internal view returns (uint256) {
        return uint256(uint32(coinflipStakePacked[day >> 3][id] >> ((day & 7) << 5)));
    }

    /// @dev Whether wallet `id` is a seed recipient (VAULT or sDGNRS), and the active seed window's
    ///      first day when it is. Read once per walk, ahead of its day loop.
    function _seedWindow(uint32 id) private view returns (bool seeded, uint24 start) {
        seeded = id == VAULT_WALLET_ID || id == SDGNRS_WALLET_ID;
        if (seeded) start = seedWindowStart;
    }

    /// @dev A seed recipient's unstored stake on `day`: SEED_FLIP_DAILY inside the window opening
    ///      at `start`, else 0. A day before `start` wraps far past the window.
    function _seedStake(uint24 day, uint24 start) private pure returns (uint256) {
        unchecked {
            return uint256(day) - start < SEED_FLIP_DAYS ? SEED_FLIP_DAILY : 0;
        }
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

    /// @dev Calculate recycling bonus for daily flip deposits (flat 0.75%).
    ///      Base is the recycled amount (the re-bet or auto-rebuy carry being deposited).
    ///      Bonus feeds into creditedFlip, not back into claimableStored (no feedback loop).
    ///      Each call floors its bonus to whole FLIP. Splitting a recycle may therefore
    ///      reduce its total bonus; amounts below 134 FLIP receive no recycling bonus.
    function _recyclingBonus(
        uint256 amount
    ) private pure returns (uint256 bonus) {
        bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR);
    }

    /// @dev The target day for new coinflip deposits: tomorrow's index. GameTimeLib is the
    ///      same time-only source DegenerusGame.currentDayView resolves to, so the day is
    ///      derived locally without a cross-contract call.
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
        uint256 wholeTokens = s;
        if (wholeTokens > type(uint96).max) {
            wholeTokens = type(uint96).max;
        }
        return uint96(wholeTokens);
    }

    /// @dev Round level up to next BAF bracket (multiple of 10).
    function _bafBracketLevel(uint24 lvl) private pure returns (uint24) {
        uint256 bracket = ((uint256(lvl) + 9) / 10) * 10;
        if (bracket > type(uint24).max) return MAX_BAF_BRACKET;
        return uint24(bracket);
    }

    /// @dev Account `id` for the caller: `id == 0` is the caller itself (key and payee, no Game
    ///      call); any other ID resolves through Game `resolveAccount` (reverts `E` when unallocated).
    function _resolve(uint32 id) private view returns (address key, address payee, bool authorized) {
        if (id == 0) return (msg.sender, msg.sender, true);
        return degenerusGame.resolveAccount(id, msg.sender);
    }

    /// @dev Account `id` for an authorized action: reverts NotApproved unless the caller is the
    ///      account's key, a smurf's owner or an approved operator.
    function _account(uint32 id) private view returns (address key, address payee) {
        bool authorized;
        (key, payee, authorized) = _resolve(id);
        if (!authorized) revert NotApproved();
    }
}
