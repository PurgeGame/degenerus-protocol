// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
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
import {RECORD_KIND_FLIP, RECORD_KIND_SPIN, RECORD_KIND_LUCKBOX} from "./interfaces/ICoinflip.sol";
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

/// @notice Interface for the soulbound record-bounty trophy moved on record ratchets.
interface IDegenerusRecordBounty {
    /// @notice Stamp record `kind`'s new mark and hand its trophy to `to`.
    function recordSet(uint8 kind, address to, uint256 value) external;
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
    /// @notice Emitted when an x00 level's seed window is armed for VAULT and sDGNRS.
    /// @param century The century index (level / 100) the window belongs to.
    /// @param firstDay First flip day carrying the seed stake.
    /// @param dayCount Number of consecutive days seeded.
    /// @param amountPerDay Seed stake added per day, per recipient.
    event SeedWindowArmed(
        uint24 indexed century,
        uint24 indexed firstDay,
        uint24 dayCount,
        uint256 amountPerDay
    );
    /// @notice Emitted when a century arm tops up the vault's WWXRP reserve.
    /// @param century The century index that paid it.
    /// @param amount WWXRP added to the vault's uncirculated allowance.
    event VaultWwxrpToppedUp(uint24 indexed century, uint256 amount);
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
    /// @param player The depositor the interval pays if the winner roll lands in it.
    /// @param index The entry's index in the day's book.
    /// @param weight This deposit's weight: the whole-FLIP floor of its raw principal.
    /// @param cumulativeWeight The entry's cumulative endpoint (exclusive).
    event BafDrawEntered(
        uint24 indexed day,
        address indexed player,
        uint32 index,
        uint96 weight,
        uint96 cumulativeWeight
    );
    /// @notice Emitted whenever an all-time record moves. One event covers both
    ///         outcomes: a zero `paid` is a bare ratchet, anything else is a claim.
    /// @param kind Which record moved (RECORD_KIND_*).
    /// @param player The player the record — and any claim — accrues to.
    /// @param value The new mark, in that record's unit (flip: FLIP wei; spin and
    ///        lootbox deposit: ETH wei; ticket buy: whole tickets).
    /// @param paid FLIP credited for the claim — the category's accrued share of the
    ///        record pool — 0 when the candidate ratcheted the mark without clearing
    ///        it by a fifth.
    /// @param sdgnrsPaid sDGNRS paid for the claim from the reward pool (the same
    ///        accrued share at 1/500 scale), 0 on a bare ratchet or an empty pool.
    event BigRecordUpdated(
        uint8 indexed kind,
        address indexed player,
        uint256 value,
        uint128 paid,
        uint256 sdgnrsPaid
    );

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
    /// @dev Daily drip into the shared record pool, applied at settlement.
    uint256 private constant RECORD_POOL_DAILY_FLIP = 2_000 ether;
    /// @dev A record claim must clear the standing mark by mark/5 (a fifth).
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
    uint256 private constant BIGGEST_FLIP_MIN = 200_000 ether;
    /// @dev Domain tag for the BAF weighted-draw winner roll.
    bytes32 private constant BAF_DRAW_TAG = "COINFLIP_BAF_DRAW_WINNER";
    uint16 private constant COIN_CLAIM_DAYS = 365;
    uint16 private constant COIN_CLAIM_FIRST_DAYS = 180;
    uint16 private constant AUTO_REBUY_OFF_CLAIM_DAYS_MAX = 1460;
    uint24 private constant MAX_BAF_BRACKET = (type(uint24).max / 10) * 10;
    /// @dev Initial-emission seed stakes: 200k FLIP per day for days 1-20, each to
    ///      VAULT and sDGNRS. All initial FLIP must survive a coinflip before minting.
    uint256 private constant SEED_FLIP_DAILY = 200_000 ether;
    uint24 private constant SEED_FLIP_DAYS = 20;
    /// @dev Levels between seed windows. The deploy window covers the first, and every
    ///      x00 level re-arms one for VAULT and sDGNRS on the same terms.
    uint24 private constant SEED_CENTURY_LEVELS = 100;
    /// @dev Mirrors `WWXRP.INITIAL_VAULT_ALLOWANCE`, the vault's deploy-time WWXRP reserve.
    ///      Each century arm pays the vault double the previous payment, counting that
    ///      deploy reserve as the first, so arm N pays `WWXRP_VAULT_SEED << N`. Held as a
    ///      local constant rather than read across the wire; the equality is pinned by test.
    uint256 private constant WWXRP_VAULT_SEED = 1_000_000_000 ether;
    /// @dev Doubling stops past this century. `<<` truncates silently rather than
    ///      reverting, and the seed overflows uint256 somewhere past 166 doublings; 60 is
    ///      far beyond any reachable level and keeps the shift provably in range.
    uint24 private constant WWXRP_MAX_DOUBLINGS = 60;

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


    // All-time record pool: one FLIP pool shared by the four biggest-* records
    // (flip deposit, degenerette spin, lootbox deposit, ticket buy). Grows by a
    // daily settlement drip and by level-transition funding; a record beaten by
    // a fifth claims an accruing share of it (RECORD_SHARE_*). The three
    // game-armed marks sit at the end of the storage section so every prior
    // slot keeps its index.
    uint128 public recordPool = 10_000 ether;
    uint128 public biggestFlipEver;

    // RNG state + the four per-category record claim clocks (all pack into one slot)
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
    uint128 public biggestLuckboxEver;
    uint128 public biggestBuyEver;

    /// @dev One packed interval entry per (armed day, index):
    ///      bits [0..95]   cumulative weight endpoint (exclusive, whole FLIP)
    ///      bits [96..255] player address
    ///      Key: (day << 32) | index. Never zero for a recorded entry — MIN is
    ///      100 FLIP, so every weight is at least 100.
    mapping(uint256 => uint256) internal bafDrawEntry;

    /// @notice Seeds the initial FLIP emission as flip stakes: 200k per day for days 1-20,
    ///         each to VAULT and sDGNRS. Direct storage writes (not _addDailyFlip) keep the
    ///         seeds off the BAF weighted draw and the flip record.
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

        for (uint24 d = 1; d <= SEED_FLIP_DAYS; ) {
            _setFlipStake(d, ContractAddresses.VAULT, SEED_FLIP_DAILY);
            _setFlipStake(d, ContractAddresses.SDGNRS, SEED_FLIP_DAILY);
            emit CoinflipStakeUpdated(ContractAddresses.VAULT, d, SEED_FLIP_DAILY, SEED_FLIP_DAILY);
            emit CoinflipStakeUpdated(ContractAddresses.SDGNRS, d, SEED_FLIP_DAILY, SEED_FLIP_DAILY);
            unchecked {
                ++d;
            }
        }

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
    ///      QUESTS (level quest rewards), AFFILIATE, ADMIN, SDGNRS (redemption win-credit at claim:
    ///      the escrowed slice was already removed from sDGNRS's backing at submit via
    ///      withdrawRedeemedFlip, so the claim-time mint to the redeemer is FLIP-neutral),
    ///      WWXRP (daily-draw prizes: a fixed, RNG-verified stake credited to the
    ///      recorded winner), PARIMUTUEL (market payouts and refunds — re-mints of
    ///      stakes the market burned at placement — plus its two bounded extras, the
    ///      gas-pegged settlement bounty and the gated, decaying volume placement credit),
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

    /// @notice Deposit FLIP into the daily coinflip system.
    /// @dev The deposit (stake, quest progress, winnings) belongs to `player`. The player or an
    ///      approved operator funds it from the player's settled winnings first and their wallet
    ///      FLIP for the remainder; any other caller funds the whole stake from their own FLIP —
    ///      a permissionless gift (the caller pays, the player gets the stake) that never touches
    ///      the player's winnings. The recycling bonus pays on the winnings leg only.
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
    ///      belongs to `player`; the FLIP principal is funded claimable-first when funder == player
    ///      (a self/approved deposit) and burned from `funder`'s wallet for whatever the settled
    ///      winnings did not cover. A permissionless gift (funder == the caller) is wallet-only.
    function _depositCoinflip(
        address player,
        address funder,
        uint256 amount,
        bool directDeposit
    ) private {
        PlayerCoinflipState storage state = playerState[player];
        if (amount != 0 && amount < MIN) revert AmountLTMin();
        // Deposits flow through every RNG lock. A deposit on day N stakes day
        // N+1, and the word that resolves day N+1 is not requested until day
        // N+1 — so every stake write (and every BAF draw interval, which keys
        // the same target day) structurally precedes the request of the word
        // that consumes it. The BAF bracket needs no deposit lock either: an
        // in-window auto-claim records its credit to the NEXT bracket
        // (claim-time routing off the promoted level) — state the pending draw
        // never reads.

        uint256 mintable = _claimCoinflipsInternal(player, state, false);
        uint128 storedAfter = state.claimableStored;
        if (mintable != 0) {
            storedAfter = uint128(uint256(storedAfter) + mintable);
        }

        // Claimable-first waterfall: settled winnings fund the stake before the wallet does, so a
        // rebet spends the bank instead of requiring a claim-out that would mint the FLIP just to
        // burn it again. Supply-neutral: claimableStored is UNMINTED (mintForGame fires only when
        // FLIP is claimed out) and a day stake is off-supply too — a normal deposit burns its
        // principal to create one — so moving between the two mints and burns nothing. Gated on
        // funder == player (self or operator-approved): a
        // permissionless gift funds the whole stake from the caller's own FLIP and can never
        // push a non-consenting player's winnings onto a flip.
        uint256 fromClaimable;
        if (funder == player) {
            fromClaimable = amount <= storedAfter ? amount : storedAfter;
            if (fromClaimable != 0) {
                unchecked {
                    storedAfter = uint128(uint256(storedAfter) - fromClaimable);
                }
            }
        }
        if (mintable != 0 || fromClaimable != 0) {
            state.claimableStored = storedAfter;
        }
        // claimableStored / lastClaim / carry are finalized here — nothing below mutates them
        // (burnForCoinflip and handleFlip never reach a claimable writer, _addDailyFlip writes
        // only per-day stake). One emit covers both exits.
        _emitClaimState(player);

        if (amount == 0) {
            emit CoinflipDeposit(player, 0);
            return;
        }

        // CEI PATTERN: the claimable leg is already debited above and the wallet leg burns here,
        // so reentrancy into downstream module calls cannot spend either source twice.
        uint256 fromWallet;
        unchecked {
            fromWallet = amount - fromClaimable;
        }
        if (fromWallet != 0) flip.burnForCoinflip(funder, fromWallet);

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
        if (fromClaimable != 0) {
            // Recycling bonus applies only to the rebet portion (not fresh money): the winnings
            // this deposit actually spent, never the wallet-funded remainder. An auto-rebuy
            // player's carry earns its own bonus where it rolls, in _claimCoinflipsInternal.
            creditedFlip += _recyclingBonus(fromClaimable);
        }
        // Direct deposits can set the flip record and enter the BAF weighted
        // draw; indirect deposits cannot.
        _addDailyFlip(player, creditedFlip, directDeposit ? amount : 0);
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
    ///      the carry is freeze-safe because the swap queues far-future entries first, and that sink
    ///      reverts under the RNG lock, so this never runs mid-window.
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
    /// @dev Called by FLIP when a transfer or an intercepted mint lands on
    ///      ContractAddresses.SDGNRS: FLIP keeps the amount out of circulating supply and
    ///      routes it here, so sDGNRS never holds a wallet balance and its FLIP stays
    ///      uncirculated. Day-keyed like every deposit — the credit becomes TOMORROW's
    ///      stake, whose word cannot exist yet (the same structural freeze-safety all
    ///      player deposits have). Direct stake write, off the leaderboard/flip record like
    ///      the constructor seed. A win settles through the sDGNRS payout branch into
    ///      the rolling carry; claimableStored stays the genesis seed reserve burns
    ///      drain first.
    /// @param amount FLIP (wei) staked onto sDGNRS's next flip.
    function creditSdgnrsBacking(uint256 amount) external onlyFLIP {
        if (amount == 0) return;
        uint24 targetDay = _targetFlipDay();
        uint256 newStake = _flipStake(targetDay, ContractAddresses.SDGNRS) + amount;
        _setFlipStake(targetDay, ContractAddresses.SDGNRS, newStake);
        emit CoinflipStakeUpdated(
            ContractAddresses.SDGNRS,
            targetDay,
            amount,
            newStake
        );
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
        uint256 mintable = _claimCoinflipsInternal(player, state, false);
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

        // sDGNRS gets no BAF score: skip the recordBafFlip call entirely for it (the
        // daily coinflip resolution auto-claims sDGNRS through this walk).
        if (winningBafCredit != 0 && player != ContractAddresses.SDGNRS) {
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

    /// @dev Add daily flip stake for player. recordAmount is the raw principal of a
    ///      direct self-funded deposit (zero for every credit path): it alone can arm
    ///      the flip record and it alone carries BAF draw weight.
    function _addDailyFlip(
        address player,
        uint256 coinflipDeposit,
        uint256 recordAmount
    ) private {
        if (recordAmount != 0) {
            // Manual deposits only: check and consume coinflip boon (5%/10%/25% boost on max 100k FLIP deposit)
            // Max bonuses: 5% = 5k, 10% = 10k, 25% = 25k. The game handle is read HERE rather than
            // at the top of the frame: every credit path passes recordAmount 0, and only this
            // branch consults the game, so a credit must not pay for the storage read.
            uint16 boonBps = degenerusGame.consumeCoinflipBoon(player);
            if (boonBps > 0) {
                uint256 maxDeposit = 100_000 ether; // Cap at 100k FLIP for boost calc
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
                player,
                recordAmount
            );
        }

        // Determine which future day this stake applies to (always the next window).
        uint24 targetDay = _targetFlipDay();

        uint256 prevStake = _flipStake(targetDay, player);
        uint256 newStake = prevStake + coinflipDeposit;

        // Update player's stake for target day
        _setFlipStake(targetDay, player, newStake);
        // BAF weighted draw: on the armed day (an x0 level's last purchase day
        // stakes it), every direct self-funded deposit appends an interval
        // weighted by its raw principal (recordAmount) — never bonuses, boon
        // boosts, record claims, or credits, so free stake carries no draw
        // weight. Ordinary days pay one warm read: bafDrawDay shares the packed
        // slot the deposit's claim walk already loaded. Credit paths (quests,
        // gifts via funder!=player, operators, sDGNRS backing) skip even that —
        // their recordAmount is zero and the compare short-circuits.
        if (recordAmount != 0 && targetDay == bafDrawDay) {
            _appendBafDrawEntry(targetDay, player, recordAmount);
        }
        // `coinflipDeposit` is everything credited by this call — principal, quest and
        // recycling bonuses, the boon boost, and any flip-record claim folded in above.
        // BigRecordUpdated itemizes the claim's own share.
        emit CoinflipStakeUpdated(player, targetDay, coinflipDeposit, newStake);
    }

    /// @dev Append `player`'s weighted interval to the armed day's draw book.
    ///      Weight is the whole-FLIP floor of the raw deposited principal, so a
    ///      player's win probability is their recorded principal over the day's
    ///      total by interval measure: repeat deposits are additive and splitting
    ///      a deposit (or a wallet) moves no probability. The uint96 cumulative
    ///      lane cannot saturate — FLIP supply is uint128-wei capped (~3.4e20
    ///      whole tokens) against a 7.9e28 lane.
    function _appendBafDrawEntry(
        uint24 day,
        address player,
        uint256 amount
    ) private {
        uint96 weight = _score96(amount);
        uint256 header = bafDrawHeader[day];
        uint256 newTotal = (header & type(uint96).max) + weight;
        uint32 index = uint32(header >> 96);
        bafDrawEntry[(uint256(day) << 32) | index] =
            (uint256(uint160(player)) << 96) |
            newTotal;
        bafDrawHeader[day] = (uint256(index + 1) << 96) | newTotal;
        emit BafDrawEntered(day, player, index, weight, uint96(newTotal));
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
    /// @param kind Which record (RECORD_KIND_*).
    /// @param player The player the record and any claim accrue to.
    /// @param candidate The value offered against the mark, in the record's unit.
    ///        Width-bound to uint128 by every caller: the flip deposit's two funding
    ///        legs are each uint128-bound (claimableStored width, FLIP._burn supply
    ///        accounting), the spin and lootbox units are ETH wei, and the buy unit
    ///        is a whole-ticket count.
    /// @return paid FLIP drawn from the record pool for the caller to credit.
    function _armBigRecord(
        uint8 kind,
        address player,
        uint256 candidate
    ) private returns (uint128 paid) {
        uint128 mark;
        if (kind == RECORD_KIND_FLIP) mark = biggestFlipEver;
        else if (kind == RECORD_KIND_SPIN) mark = biggestSpinEver;
        else if (kind == RECORD_KIND_LUCKBOX) mark = biggestLuckboxEver;
        else mark = biggestBuyEver;
        if (candidate <= mark) return 0;

        uint256 sdgnrsPaid;
        // A first mark has no bar to clear; after that the candidate must clear the
        // mark by an exact fifth: `mark + mark / 5` floors the bar, so a mark not
        // divisible by five would let a candidate claim on strictly less than a
        // fifth. Multiplying the increase instead is exact.
        if (mark == 0 || (candidate - mark) * RECORD_BEAT_DIV >= mark) {
            uint24 today = GameTimeLib.currentDayIndex();
            uint256 stamped = _recordDay(kind);
            uint256 shareBps = RECORD_SHARE_FLOOR_BPS +
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
            // The sDGNRS leg rides the same accrued share at 1/500 scale, drawn from
            // the sDGNRS reward pool via the game (which sDGNRS authorizes).
            sdgnrsPaid = degenerusGame.payRecordSdgnrs(player, shareBps);
            _stampRecordDay(kind, today);
        }

        if (kind == RECORD_KIND_FLIP) biggestFlipEver = uint128(candidate);
        else if (kind == RECORD_KIND_SPIN) biggestSpinEver = uint128(candidate);
        else if (kind == RECORD_KIND_LUCKBOX) biggestLuckboxEver = uint128(candidate);
        else biggestBuyEver = uint128(candidate);
        emit BigRecordUpdated(kind, player, candidate, paid, sdgnrsPaid);

        // Hand the record's soulbound trophy to the new mark holder. Every
        // ratchet moves it — the claim bar gates only the pool share, never the
        // trophy. Cosmetic-only state (nothing game-side reads the trophy
        // contract), and recordSet does no recipient callback, so the call
        // cannot re-enter or brick the arming path.
        IDegenerusRecordBounty(ContractAddresses.RECORD_BOUNTY).recordSet(
            kind,
            player,
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

    /// @notice Arm a game-side all-time record for `player` with `candidate` in the
    ///         record's own unit (spin and lootbox deposit: ETH wei; buy: whole tickets).
    /// @dev GAME only — the modules gate each record's entry floor at the call site
    ///      before paying for this call, and each passes its own kind as a constant.
    ///      The flip record arms internally on direct deposits; nothing routes it here.
    /// @return The FLIP claimed from the pool, for the calling module to fold into the
    ///         FLIP its own path already pays. Nothing is credited here.
    function armRecord(
        uint8 kind,
        address player,
        uint256 candidate
    ) external onlyDegenerusGameContract returns (uint256) {
        return _armBigRecord(kind, player, candidate);
    }

    /// @notice Arm this century's seed window: SEED_FLIP_DAILY per day for
    ///         SEED_FLIP_DAYS days to VAULT and to sDGNRS, plus the vault's doubling WWXRP
    ///         reserve, on the same terms as the deploy program.
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
    ///      Stakes ADD to a day's lane rather than replacing it — `_setFlipStake` is a masked
    ///      overwrite and sDGNRS is on perpetual auto-rebuy by level 100, so a replace would
    ///      destroy a stake the protocol had already rolled forward.
    /// @param lvl The level whose jackpot phase just ended.
    function armCenturySeed(uint24 lvl) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();

        uint24 century = lastSeededCentury + 1;
        if (uint256(lvl) < uint256(century) * SEED_CENTURY_LEVELS) return;
        lastSeededCentury = century;

        uint24 firstDay = _targetFlipDay();
        for (uint24 i = 0; i < SEED_FLIP_DAYS; ) {
            uint24 d = firstDay + i;
            uint256 vaultTotal = _flipStake(d, ContractAddresses.VAULT) + SEED_FLIP_DAILY;
            uint256 sdgnrsTotal = _flipStake(d, ContractAddresses.SDGNRS) + SEED_FLIP_DAILY;
            _setFlipStake(d, ContractAddresses.VAULT, vaultTotal);
            _setFlipStake(d, ContractAddresses.SDGNRS, sdgnrsTotal);
            emit CoinflipStakeUpdated(ContractAddresses.VAULT, d, SEED_FLIP_DAILY, vaultTotal);
            emit CoinflipStakeUpdated(ContractAddresses.SDGNRS, d, SEED_FLIP_DAILY, sdgnrsTotal);
            unchecked {
                ++i;
            }
        }

        emit SeedWindowArmed(century, firstDay, SEED_FLIP_DAYS, SEED_FLIP_DAILY);

        // Vault WWXRP reserve, doubling each century off the deploy allowance: century N
        // pays `WWXRP_VAULT_SEED << N`. `mintPrize` to VAULT is intercepted by WWXRP._mint
        // into `vaultAllowance`, so this raises the uncirculated reserve, not a balance.
        if (century <= WWXRP_MAX_DOUBLINGS) {
            uint256 wwxrpAmount = WWXRP_VAULT_SEED << uint256(century);
            wwxrp.mintPrize(ContractAddresses.VAULT, wwxrpAmount);
            emit VaultWwxrpToppedUp(century, wwxrpAmount);
        }
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
    ///      The freeze applies only to a position ALREADY on auto-rebuy: that is the only state
    ///      holding a carry, and the carry is the pending day's stake, so toggling off would
    ///      extract it before a known loss and re-setting the stop would bank a known win whole.
    ///      A player not on auto-rebuy holds no carry — arming it moves nothing the pending word
    ///      prices — so the arm stays open.
    function _setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 takeProfit,
        bool strict
    ) private {
        PlayerCoinflipState storage state = playerState[player];
        uint256 mintable;
        if (state.autoRebuyEnabled && _flipFrozen()) revert RngLocked();

        if (enabled) {
            mintable = _claimCoinflipsInternal(player, state, false);
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
            mintable = _claimCoinflipsInternal(player, state, true);
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
    ///      Blocked while today's flip is frozen — the threshold splits the pending day's payout
    ///      between the banked chunk and the rolling carry, so a known win could be banked whole.
    ///      The enablement check leads, so only a position actually on auto-rebuy meets the freeze.
    function _setCoinflipAutoRebuyTakeProfit(
        address player,
        uint256 takeProfit
    ) private {
        PlayerCoinflipState storage state = playerState[player];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();
        if (_flipFrozen()) revert RngLocked();

        uint256 mintable = _claimCoinflipsInternal(player, state, false);
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
    ///      settled carry. Blocked while today's flip is frozen for the same reason as the
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
        PlayerCoinflipState storage state = playerState[player];
        if (!state.autoRebuyEnabled) revert AutoRebuyNotEnabled();
        if (_flipFrozen()) revert RngLocked();

        uint256 mintable = _claimCoinflipsInternal(player, state, false);
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
        // Apply the day's coinflip bonus, precomputed by the caller from frozen protocol state
        // (not a player-flippable flag): 0 on a normal day, +2 on a bonus day (a level-0 day,
        // the second day of a level's jackpot phase, or the first purchase day after a turbo
        // collapse), +6 on an x0 BAF-level bonus day. Sized so a recycling player nets
        // ~99.9% / ~101.9% RTP after the recycle bonus compounds. Adding 0 is a no-op.
        unchecked {
            rewardPercent += bonus;
        }

        // 50/50 win roll off the low bit of the VRF word.
        bool win = (rngWord & 1) == 1;

        // Record the day's result for future claims
        _storeDayResult(epoch, rewardPercent, win);

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
        // through a redemption/salvage consume leg.
        //
        // THE RESERVE IS STATIC ONCE ARMED. It used to bleed 2% a day onto the active flip so
        // the protocol's own backing kept a position on the coin; craps now puts a far larger
        // and genuinely player-funded burn through the table, so the reserve no longer has to
        // manufacture one out of the redemption backing it exists to be.
        PlayerCoinflipState storage sdgnrsState = playerState[
            ContractAddresses.SDGNRS
        ];
        if (sdgnrsAutoRebuyArmed) {
            _claimCoinflipsInternal(ContractAddresses.SDGNRS, sdgnrsState, false);
        } else {
            uint256 mintable = _claimCoinflipsInternal(ContractAddresses.SDGNRS, sdgnrsState, false);
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

    /// @notice Credit flip to a player through the authorized protocol/game creditor lane.
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of FLIP-denominated flip stake to credit.
    function creditFlip(
        address player,
        uint256 amount
    ) external onlyFlipCreditors {
        if (player == address(0) || amount == 0) return;
        _addDailyFlip(player, amount, 0);
    }

    /// @notice Credit flips to multiple players (called by GAME jackpot modules and the
    ///         PARIMUTUEL settlement crank).
    /// @param players Player addresses to credit (address(0) entries are skipped).
    /// @param amounts FLIP-denominated flip stake amounts, one per player (0 entries are skipped).
    function creditFlipBatch(
        address[] calldata players,
        uint256[] calldata amounts
    ) external onlyFlipCreditors {
        uint256 len = players.length;
        for (uint256 i; i < len; ) {
            address player = players[i];
            uint256 amount = amounts[i];
            if (player != address(0) && amount != 0) {
                _addDailyFlip(player, amount, 0);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Credit flips to exactly two players (called by the GAME purchase path).
    /// @dev Fixed-arity variant of creditFlipBatch for the purchase hot path — spares the
    ///      caller the two array allocations and the dynamic ABI encode. address(0) and
    ///      zero-amount legs are skipped, matching the batch behavior.
    /// @param player1 First recipient (address(0) entries are skipped).
    /// @param amount1 First FLIP-denominated flip stake amount (0 entries are skipped).
    /// @param player2 Second recipient (address(0) entries are skipped).
    /// @param amount2 Second FLIP-denominated flip stake amount (0 entries are skipped).
    function creditFlipPair(
        address player1,
        uint256 amount1,
        address player2,
        uint256 amount2
    ) external onlyFlipCreditors {
        if (player1 != address(0) && amount1 != 0) {
            _addDailyFlip(player1, amount1, 0);
        }
        if (player2 != address(0) && amount2 != 0) {
            _addDailyFlip(player2, amount2, 0);
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
        uint256 mintable = _claimCoinflipsInternal(s, state, false);
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

        // Consume the settled genesis seed reserve first (no token mint — removes a
        // future mint of `consumed`).
        uint256 consumed = _claimCoinflipsAmount(s, base, false);
        uint256 remainder = base - consumed;
        if (remainder == 0) return;

        // Decrement the rolling auto-rebuy carry for the rest (post-day-20 steady state).
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
    /// @dev Equals the ceiling `claimCoinflips` would pay: the settled bank plus whatever
    ///      the pending resolved days surface. The carry is excluded — it is not claimable
    ///      through this path — except where a disabled position still holds one, which a
    ///      claim cashes out.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable) {
        (uint256 daily, ) = _viewClaimableCoin(player);
        uint256 stored = playerState[player].claimableStored;
        return daily + stored;
    }

    /// @notice Preview `player`'s salvage-spendable coinflip backing: claimable + auto-rebuy carry (view).
    /// @dev The carry-inclusive read the salvage quote caps against, mirroring
    ///      redeemableFlipBacking's components but as a pure VIEW (no settle) so the preview
    ///      and execution offer stay re-derivable. Both legs come from the same replay, so
    ///      the carry reported is the one the settle LEAVES — a pending losing day has
    ///      already wiped it here, exactly as consumeFlipForSalvage will.
    function previewSalvageFlipBacking(address player) external view returns (uint256) {
        (uint256 daily, uint256 carry) = _viewClaimableCoin(player);
        return daily + playerState[player].claimableStored + carry;
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

    /// @notice One amount-weighted random winner among the armed day's direct
    ///         deposits, or address(0) when the day recorded no entries (the BAF
    ///         slice then refunds its 5% share to the pool).
    /// @dev Winner probability = a player's recorded principal / the day's total,
    ///      by cumulative-interval measure. The roll is domain-separated from the
    ///      BAF transition word (fixed tag, this contract, the armed day), so it
    ///      perturbs no other consumer of that word. Winner = the entry with the
    ///      smallest cumulative endpoint strictly above the roll, by binary search.
    /// @param rngWord The BAF transition VRF word.
    function bafDrawWinner(uint256 rngWord) external view returns (address winner) {
        uint24 day = bafDrawDay;
        uint256 header = bafDrawHeader[day];
        uint256 total = header & type(uint96).max;
        if (total == 0) return address(0);
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
        winner = address(uint160(bafDrawEntry[(uint256(day) << 32) | lo] >> 96));
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

    /// @notice A recorded draw entry's player and cumulative endpoint (whole FLIP).
    function bafDrawEntryAt(
        uint24 day,
        uint32 index
    ) external view returns (address player, uint96 cumulativeWeight) {
        uint256 entry = bafDrawEntry[(uint256(day) << 32) | index];
        player = address(uint160(entry >> 96));
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
    /// @param player The position to replay.
    /// @return mintable Winnings a claim would surface: settled payouts and banked
    ///         take-profit chunks, plus a stale carry left on a disabled position.
    /// @return endCarry The rolling carry the walk leaves in place; 0 when auto-rebuy is off.
    function _viewClaimableCoin(
        address player
    ) internal view returns (uint256 mintable, uint256 endCarry) {
        PlayerCoinflipState storage state = playerState[player];
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
        if (startDay >= latestDay) return (mintable, endCarry);

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
        while (remaining != 0 && cursor <= latestDay) {
            (uint16 rewardPercent, bool win) = _dayResult(cursor);
            // Skip unresolved days (both fields zero) instead of breaking,
            // to handle gaps from testnet day-advance or missed resolution.
            if (rewardPercent == 0 && !win) {
                unchecked { ++cursor; --remaining; }
                continue;
            }

            uint256 stake = _flipStake(cursor, player);
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

    /// @dev Player stake for `day` in wei (2 days/slot, 128-bit lanes, lossless).
    ///      Stored in wei — flip credits (keeper advance rewards, redemption shares)
    ///      can be sub-1-FLIP, so whole-token granularity would zero them. Fresh
    ///      SLOAD — never cached across the claim loop's external calls.
    function _flipStake(uint24 day, address p) internal view returns (uint256) {
        return uint128(coinflipStakePacked[day >> 1][p] >> ((day & 1) * 128));
    }

    /// @dev Masked write of `day`'s stake lane, preserving the sibling day. Saturating,
    ///      on the same grounds as the prize pools' packed halves: the lane is 128 bits
    ///      wide and the write is masked, so an over-wide value would not truncate — it
    ///      would spill into the SIBLING DAY's lane and hand that day a stake nobody
    ///      deposited. Clamping makes that impossible by construction instead of by an
    ///      invariant every caller has to keep holding.
    ///
    ///      The clamp is unreachable in practice: FLIP caps total supply at uint128 and
    ///      a stake never exceeds supply. It is here so that if the credit paths ever
    ///      outgrow that, the failure is one capped stake rather than a neighbouring
    ///      day's books. Fresh SLOAD/SSTORE.
    function _setFlipStake(uint24 day, address p, uint256 weiAmount) internal {
        if (weiAmount > type(uint128).max) weiAmount = type(uint128).max;
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

    /// @dev Calculate recycling bonus for daily flip deposits (flat 0.75%).
    ///      Base is the recycled amount (the re-bet or auto-rebuy carry being deposited).
    ///      Bonus feeds into creditedFlip, not back into claimableStored (no feedback loop).
    ///      Rate-only, so the same percentage applies at every size: splitting a recycle
    ///      across several deposits earns exactly what one deposit would, and the RTP the
    ///      day's reward percent is sized against holds for a whale and a minnow alike.
    function _recyclingBonus(
        uint256 amount
    ) private pure returns (uint256 bonus) {
        bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR);
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
