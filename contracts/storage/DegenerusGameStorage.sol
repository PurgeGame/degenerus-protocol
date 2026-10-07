// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {GoldSixLib} from "../libraries/GoldSixLib.sol";

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

import {ContractAddresses} from "../ContractAddresses.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {IDegenerusAffiliate} from "../interfaces/IDegenerusAffiliate.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {ICoinflip} from "../interfaces/ICoinflip.sol";
import {IDegenerusParimutuel} from "../interfaces/IDegenerusParimutuel.sol";
import {IDegenerusQuests} from "../interfaces/IDegenerusQuests.sol";
import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";
import {ActivityCurveLib} from "../libraries/ActivityCurveLib.sol";
import {CrapsPriceLib} from "../libraries/CrapsPriceLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {MintPaymentKind} from "../interfaces/IDegenerusGame.sol";

interface IGameMinerMaintenance {
    function minerMaintenancePending() external view returns (bool);
}

interface IAdminLinkValue {
    function linkAmountToEth(uint256 amount) external view returns (uint256);
}

/**
 * @title DegenerusGameStorage
 * @author Burnie Degenerus
 * @notice Shared storage layout between DegenerusGame and its delegatecall modules.
 *
 * @dev ARCHITECTURE OVERVIEW
 * -----------------------------------------------------------------------------
 * This contract defines the canonical storage layout for the Degenerus game ecosystem.
 * It is inherited by:
 *   - DegenerusGame (main contract, holds actual state)
 *   - DegenerusGameAdvanceModule (delegatecall module)
 *   - DegenerusGameJackpotModule (delegatecall module)
 *   - DegenerusGameMintModule (delegatecall module)
 *   - DegenerusGameLootboxModule (delegatecall module)
 *   - DegenerusGameWhaleModule (delegatecall module)
 *   - DegenerusGameBoonModule (delegatecall module)
 *   - DegenerusGameDecimatorModule (delegatecall module)
 *   - DegenerusGameDegeneretteModule (delegatecall module)
 *   - DegenerusGameGameOverModule (delegatecall module)
 *   - DegenerusGameBingoModule (delegatecall module)
 *   - GameAfkingModule (delegatecall module)
 *   - DegenerusGameFoilPackModule (delegatecall module)
 *
 * DELEGATECALL PATTERN:
 * When DegenerusGame calls `module.delegatecall(...)`, the module's code executes
 * in the context of DegenerusGame's storage. This means:
 *   1. Storage slots MUST match exactly between the main contract and all modules.
 *   2. This contract ensures slot alignment by providing a single source of truth.
 *   3. Never add storage variables to module contracts — they would collide with game storage.
 *
 * STORAGE SLOT LAYOUT (EVM assigns slots sequentially):
 * -----------------------------------------------------------------------------
 *
 * +---------------------------------------------------------------------------------+
 * | EVM SLOT 0 (32 bytes) -- Timing, per-level flags, counters, buffer, freeze      |
 * +---------------------------------------------------------------------------------+
 * | [0:3]   purchaseStartDay         uint24   Deploy-relative day idx level began   |
 * | [3:6]   dailyIdx                 uint24   Deploy-rel day idx of last sealed day |
 * | [6:12]  rngRequestTime           uint48   When last VRF request was fired       |
 * | [12:15] level                    uint24   Current jackpot level (starts at 0)   |
 * | [15:16] jackpotPhaseFlag         bool     Payout mode: purchase(F)/jackpot(T)   |
 * | [16:17] jackpotCounter           uint8    Jackpots processed this level         |
 * | [17:18] lastPurchaseDay          bool     Prize target met flag                 |
 * | [18:19] decimatorFlags          uint8    bit0=window open, bit1=opening day      |
 * | [19:20] rngLockedFlag            bool     Daily RNG lock (jackpot window)       |
 * | [20:21] phaseTransitionActive    bool     Level transition in progress          |
 * | [21:22] gameOver                 bool     Terminal state flag                   |
 * | [22:23] dailyJackpotCoinTicketsPending bool Split jackpot pending flag          |
 * | [23:24] jackpotFlags    uint8    bit0=turbo bit1=bonus owed          |
 * | [24:25] ticketsFullyProcessed    bool     Read slot fully drained flag          |
 * | [25:26] ticketWriteSlot          bool     Double-buffer write toggle            |
 * | [26:27] prizePoolFrozen          bool     Prize pool freeze active flag         |
 * | [27:28] presaleOver              bool     Coin-presale-box terminal latch       |
 * | [28:29] subsFullyProcessed       bool     Afking STAGE drain-complete flag      |
 * | [29:30] humanReadComplete        bool     Read cohort's box entries all settled |
 * | [30:32] rngFlagsAndNudges        uint16   Eight-bit nudges, completion and window  |
 * +---------------------------------------------------------------------------------+
 *   Total: 32 bytes used (0 bytes padding -- FULL)
 *
 * +---------------------------------------------------------------------------------+
 * | EVM SLOT 1 (32 bytes) -- Prize Pools                                            |
 * +---------------------------------------------------------------------------------+
 * | [0:16]  currentPrizePool         uint128  Active prize pool for current level   |
 * | [16:32] claimablePool            uint128  Aggregate ETH liability for claims    |
 * +---------------------------------------------------------------------------------+
 *   Total: 32 bytes used (0 bytes padding -- FULL)
 *
 * SLOTS 2+ -- Full-width variables, arrays, and mappings
 * -----------------------------------------------------------------------------
 * Each uint256, array length, or mapping root occupies its own slot.
 * Dynamic arrays: length at slot N, data at keccak256(N).
 * Mappings: value at keccak256(key . slot).
 *
 * SECURITY CONSIDERATIONS
 * -----------------------------------------------------------------------------
 * 1. SLOT STABILITY: Never reorder, remove, or change types of existing variables.
 *    Append-only additions are safe for non-upgradeable contracts.
 *
 * 2. DELEGATECALL SAFETY: All modules inherit this exact layout. If a module
 *    declared its own storage variables, they would occupy the same slots as
 *    game data, causing catastrophic corruption.
 *
 * 3. ACCESS CONTROL: Most state is `internal`; `level`, `gameOver`, and `boonPacked` are `public`
 *    (auto-getters). Other external reads go through explicit getters in DegenerusGame.
 *
 * 4. INITIALIZATION: Default values are set inline. For critical variables:
 *    - purchaseStartDay = deploy day index (set in constructor via GameTimeLib.currentDayIndex())
 *    - jackpotPhaseFlag = false (purchase phase)
 *    - decimatorFlags = 0 (window opens at level 4 jackpot phase start)
 *    - levelPrizePool[level] is the per-level ratchet target; levelPrizePool[0] is set to
 *      BOOTSTRAP_PRIZE_POOL (50 ether) in the constructor (also the zero-fallback in the view)
 *
 * 5. OVERFLOW PROTECTION: Solidity 0.8+ provides automatic overflow checks.
 *    `unchecked` blocks in modules are intentional optimizations for safe ops.
 *
 * 6. MAPPING COLLISION: Mappings use keccak256(key . slot), making collisions
 *    computationally infeasible. lvlTraitEntry maps physical parity to 256 tail-bearing
 *    headers, validated by the full buffer level and a per-buffer bitmap. A bucket header is at keccak256((level & 1) . slot) + traitId;
 *    packed occurrence words begin at keccak256(headerSlot).
 *
 * UPGRADE NOTES
 * -----------------------------------------------------------------------------
 * This contract is NOT upgradeable (no proxy pattern).
 *
 * VARIABLE DOCUMENTATION
 * -----------------------------------------------------------------------------
 * See inline comments for each variable group below.
 */

abstract contract DegenerusGameStorage {
    /// @dev Wallet ID 0 means "none": the table's length starts at 1, so element 0 is never
    ///      assigned and a zero lane decodes to address(0).
    constructor() {
        assembly ("memory-safe") { sstore(wallets.slot, 1) }
    }

    // =========================================================================
    // CONSTANTS
    // =========================================================================

    /// @dev Prize accounting unit: one half-pass grants 100 quarter-ticket entries
    ///      over 100 levels. A full prize pass is two units (4.5 ETH award value).
    uint256 internal constant HALF_WHALE_PASS_PRICE = 2.25 ether;

    IDegenerusCoin internal constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    ICoinflip internal constant coinflip =
        ICoinflip(ContractAddresses.COINFLIP);
    IDegenerusQuests internal constant quests =
        IDegenerusQuests(ContractAddresses.QUESTS);
    IDegenerusAffiliate internal constant affiliate =
        IDegenerusAffiliate(ContractAddresses.AFFILIATE);
    IsDGNRS internal constant dgnrs =
        IsDGNRS(ContractAddresses.SDGNRS);
    IDegenerusParimutuel internal constant parimutuel =
        IDegenerusParimutuel(ContractAddresses.PARIMUTUEL);

    /// @dev Deity pass activity bonus (+80 points).
    uint16 internal constant DEITY_PASS_ACTIVITY_BONUS_POINTS = 80;

    /// @dev Hard ceiling on the total activity score (points). Quest completions are
    ///      uncapped, so this bounds the sum. Set one below uint16 max because the
    ///      sDGNRS redemption snapshot stores uint16(score) + 1 (a 0 = unset sentinel),
    ///      which would overflow at 65,535.
    uint16 internal constant ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534;

    /// @dev Floor streak points for active pass holders (50 points).
    uint16 internal constant PASS_STREAK_FLOOR_POINTS = 50;

    /// @dev Floor mint count points for active pass holders (25 points).
    uint16 internal constant PASS_MINT_COUNT_FLOOR_POINTS = 25;

    /// @dev Conversion factor for FLIP token amounts.
    ///      FLIP uses 18 decimals, so 1000 FLIP = 1e21 base units.
    ///      Used in price calculations: price / PRICE_COIN_UNIT = FLIP per mint.
    uint256 internal constant PRICE_COIN_UNIT = 1000;

    /// @dev Fractional precision for virtual reward spins, independent of token decimals.
    ///      Divide once at the final award boundary; custody and stored token amounts are whole.
    uint256 internal constant TOKEN_MATH_SCALE = 1e18;

    /// @dev Scale factor for fractional ticket calculations (2 decimal places).
    ///      100 means 1 ticket = 100 scaled units.
    uint256 internal constant QTY_SCALE = 100;

    /// @dev Only Crypto, Zodiac and Cards can be Degenerette heroes; Dice still roll naturally.
    uint8 internal constant DEGENERETTE_HERO_COUNT = 24;

    /// @dev Marker bit on entry owed values: set by the drain once a player's
    ///      owed balance has been divided by 2^snapShift, so a budget-split resume
    ///      never divides the same balance twice.
    uint80 internal constant SNAP_DONE_BIT = uint80(1) << 40;

    /// @dev Owner-registry position of a queued entry, stored plus one in the owed word's
    ///      bits 48..79; every sink stamps it on the first push, so an owed word with a
    ///      balance always carries one. A foil pack carries its position in the foilQueue
    ///      word the same way.
    uint256 internal constant OWNER_IDX_SHIFT = 48;
    uint80 internal constant OWNER_IDX_MASK = uint80(type(uint32).max) << 48;

    /// @dev Seat floor of the round drain: a queue segment with fewer entries than this drains
    ///      entry by entry (thin rounds cost more than per-trait runs).
    uint256 internal constant ROUND_MIN_SEATS = 4;

    /// @dev Seats in a drain round: one packed lane word per quadrant carries every seat.
    uint256 internal constant ROUND_SEATS = 8;
    /// @dev Color tiers at or above this spread a round's seats across the quadrant's eight
    ///      symbols, one lane per bucket, so the smallest buckets never take a whole round.
    uint8 internal constant ROUND_SPLIT_COLOR = 6;

    /// @dev ETH threshold for whale pass claim eligibility from lootbox wins.
    uint256 internal constant LOOTBOX_CLAIM_THRESHOLD = 5 ether;

    /// @dev Bootstrap value for prize pool target at level 1 (before any level completes).
    ///      levelPrizePool[0] is initialized to this value conceptually.
    uint256 internal constant BOOTSTRAP_PRIZE_POOL = 50 ether;

    /// @dev Current-pool daily jackpot percentage is rolled in JackpotModule.
    ///      Three-day phases pay 6%-14% on day one, 12%-28% on day two, then the remainder.
    ///      Turbo pays 100% of the currentPrizePool in its sole physical day.

    /// @dev Bit mask for ticket queue double-buffer key encoding.
    ///      Set bit 23 of the uint24 level key to distinguish write/read slots.
    ///      Max real level: 2^22 - 1 = 4,194,303 (game would take millennia).
    uint24 internal constant TICKET_SLOT_BIT = 1 << 23;

    /// @dev Bit mask for far-future ticket key encoding.
    ///      Set bit 22 of the uint24 level key to create a third key space
    ///      disjoint from both double-buffer slots (bit 23).
    ///      Far-future = tickets targeting a level above _mintCeiling() (unminted levels).
    ///      Three key spaces: Slot0 [0x000000-0x3FFFFF], FF [0x400000-0x7FFFFF],
    ///      Slot1 [0x800000-0xBFFFFF]. Disjoint for all lvl < 2^22.
    uint24 internal constant TICKET_FAR_FUTURE_BIT = 1 << 22;

    /// @dev Deploy idle timeout in days (mirrors DegenerusGame / AdvanceModule).
    uint32 internal constant _DEPLOY_IDLE_TIMEOUT_DAYS = 250;

    /// @dev Final purchase/rescue day after level 0; game-over is eligible the following day.
    uint24 internal constant _PURCHASE_TIMEOUT_DAYS = 30;

    /// @dev How long an unanswered VRF request — daily, or a mid-day one blocking the next
    ///      day's advance — may hold the game before the deterministic ending. Measured from the
    ///      original send: the vault owner's retry of a daily request and coordinator swaps do not
    ///      re-stamp. This is also the window a daily
    ///      stall straddling the purchase deadline has to recover in.
    uint48 internal constant _VRF_DEAD_TIMEOUT = 14 days;

    /// @dev Deadman: no day sealed for this many days ends the game in every phase. dailyIdx
    ///      advances on a successful day-seal or when a stalled word lands and its gap is
    ///      skipped, so currentDay - dailyIdx counts days since the last sealed day. A dead VRF
    ///      reaches _vrfDead first, so with VRF alive this is a game nobody advances (or a ticket
    ///      backlog longer than the window) and it ends on the normal VRF payout. It also bounds
    ///      every gap the backfill can meet (GAP_BACKFILL_MAX_DAYS). Applied at every level,
    ///      including level 0, whose 250-day deploy window therefore needs a sealed day at
    ///      least every 30 days. It clears only after game-over latches.
    uint24 internal constant _VRF_DEADMAN_DAYS = 30;

    // =========================================================================
    // Errors
    // =========================================================================

    /// @dev Gas-minimal revert signal. Matches codebase convention (DegenerusGame, modules).
    error E();

    /// @dev Reverts when a permissionless far-future ticket write is attempted during VRF commitment window.
    error RngLocked();

    // Shared named reverts (inherited by every Game module). Each carries no data — the name
    // alone identifies the failing guard for off-chain decoding. Domain-specific reverts stay
    // declared locally in the module that owns them.
    /// @notice Thrown by the nested-dispatch guard when `address(this) != GAME`.
    error OnlyDelegatecall();
    /// @notice Thrown when the caller is not the contract itself.
    error OnlySelf();
    /// @notice Thrown when the caller is not the admin.
    error OnlyAdmin();
    /// @notice Thrown when the caller is not the vault or the vault owner.
    error OnlyVault();
    /// @notice Thrown when the caller is not the sDGNRS contract.
    error OnlySDGNRS();
    /// @notice Thrown when a thanos declaration falls outside its sanity bounds.
    error ThanosBounds();
    /// @notice Thrown when the caller is not the VRF coordinator.
    error OnlyCoordinator();
    /// @notice Thrown on a generic access-control failure.
    error Unauthorized();
    /// @notice Thrown when the game has ended (or the liveness-timeout game-over trigger fired).
    error GameOver();
    /// @notice Thrown when the game or phase has not started.
    error NotStarted();
    /// @notice Thrown when a delegatecall reverts with empty returndata.
    error EmptyRevert();
    /// @notice Thrown when a native or token transfer fails.
    error TransferFailed();
    /// @notice Thrown when a balance or pool draw would underflow its backing.
    error Insolvent();
    /// @notice Thrown when an internal invariant is violated.
    error Invariant();
    /// @notice Thrown when a required address argument is the zero address.
    error ZeroAddress();
    /// @notice Thrown when a required value argument is zero.
    error ZeroValue();
    /// @notice Thrown when there is no balance available to claim.
    error NothingToClaim();
    /// @notice Thrown when the target has already been swept or finalized.
    error AlreadySwept();
    /// @notice Thrown when array-length arguments disagree.
    error LengthMismatch();
    /// @notice Thrown when the caller may not act for the requested account.
    error NotApproved();

    // =========================================================================
    // SLOT 0: Timing, FSM, Counters, Flags, Buffer, Freeze
    // =========================================================================
    // These variables pack into a single 32-byte storage slot for gas efficiency.
    // Order matters: EVM packs from low to high within a slot.
    // All 32 bytes are used — see the SLOT 0 table in the file header for byte offsets.

    /// @dev Game day index when the purchase phase (or deploy) began.
    ///      Initialized to GameTimeLib.currentDayIndex() in the constructor.
    ///      Used for death clock, distress mode, future take curve, and gap extension.
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal purchaseStartDay;

    /// @dev Monotonically increasing "day" counter derived from block timestamps.
    ///      Incremented during game progression; used to key RNG words and track
    ///      daily jackpot eligibility. NOT tied to calendar days — it's the deploy-relative day index (frozen during a VRF stall).
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal dailyIdx;

    /// @dev Timestamp when the last VRF (Chainlink) request was submitted.
    ///      Starts at nonzero idle sentinel 1, then retains the last request timestamp.
    ///      The packed active bit identifies live requests; nonzeroness does not.
    ///
    ///      SECURITY: Timeout mechanism prevents permanent lockup if VRF fails.
    ///      Note: rngLockedFlag (separate bool) controls the daily RNG lock state.
    uint48 internal rngRequestTime = 1;

    /// @notice Current jackpot level (starts at 0). Purchase phase targets level + 1.
    ///
    ///      SECURITY: uint24 supports ~16M levels — game would take millennia
    ///      to overflow at realistic progression rates.
    uint24 public level = 0;

    /// @notice Current game phase flag.
    ///      false = purchase phase
    ///      true  = jackpot phase
    ///
    ///      SECURITY: Phase transitions are guarded by advanceGame flow.
    bool internal jackpotPhaseFlag;

    // =========================================================================
    // EVM SLOT 0 (continued): Counters and Flags
    // =========================================================================

    /// @dev Physical jackpot days completed within the current level.
    ///      Ends at 1 for turbo or 3 otherwise. Reset at level start.
    ///
    ///      SECURITY: uint8 is sufficient (max 255, only need 0-3).
    uint8 internal jackpotCounter;

    /// @dev True once the prize target is met for current level.
    ///      When true, next tick skips normal daily/jackpot prep and proceeds
    ///      to jackpot window. Allows early level completion on high activity.
    bool internal lastPurchaseDay;

    /// @dev Bit 0 holds the burn window open from x4/x99 until x5/x00 (excluding x94/x95).
    ///      Bit 1 marks its opening-day quest and auto-entry. The next fresh daily request
    ///      clears bit 1; a retry preserves it. The flags share byte 18 and remain independent.
    uint8 internal decimatorFlags;
    uint8 internal constant DEC_WINDOW_OPEN = 1;
    uint8 internal constant DEC_DAY_ONE_ACTIVE = 2;

    function _decWindowOpen() internal view returns (bool) {
        return decimatorFlags & DEC_WINDOW_OPEN != 0;
    }

    function _decDayOneActive() internal view returns (bool) {
        return decimatorFlags & DEC_DAY_ONE_ACTIVE != 0;
    }

    function _setDecWindowOpen(bool open) internal {
        decimatorFlags = open ? decimatorFlags | DEC_WINDOW_OPEN : decimatorFlags & ~DEC_WINDOW_OPEN;
    }

    function _setDecDayOneActive(bool active) internal {
        decimatorFlags = active ? decimatorFlags | DEC_DAY_ONE_ACTIVE : decimatorFlags & ~DEC_DAY_ONE_ACTIVE;
    }

    /// @dev True when daily RNG is locked (jackpot resolution in progress).
    ///      Set when daily VRF is requested, cleared when daily processing completes.
    ///      Mid-day lootbox RNG does NOT set this flag.
    ///      Used to block burns/opens during jackpot resolution window.
    bool internal rngLockedFlag;

    /// @dev True while jackpot→purchase transition housekeeping is in progress.
    bool internal phaseTransitionActive;

    /// @dev True once gameover has been triggered (terminal state).
    bool public gameOver;

    /// @dev True when daily jackpot ETH phase completed but coin+tickets phase pending.
    ///      Splits the daily jackpot into multiple advanceGame calls so each stays under the
    ///      per-tx gas cap. Cleared after the ticket distribution.
    bool internal dailyJackpotCoinTicketsPending;

    /// @dev Packed jackpot state: bit 0 selects turbo (one day instead of three);
    ///      bit 1 records a turbo coinflip bonus owed on the next purchase settlement.
    ///      The bits are independent: a new turbo may arm while the prior bonus is owed.
    uint8 internal constant JACKPOT_TURBO = 1;
    uint8 internal constant TURBO_BONUS_PENDING = 2;
    uint8 internal jackpotFlags;

    /// @dev True when the read slot has been fully drained (all tickets processed).
    ///      Gate for RNG requests and jackpot logic in advanceGame daily path.
    ///
    ///      SECURITY: Must be set to true before any jackpot/phase logic executes.
    ///      Reset to false on every queue slot swap.
    bool internal ticketsFullyProcessed;

    // EVM SLOT 0 (continued): Double-Buffer + Freeze

    /// @dev Active write buffer toggle for ticket queue double-buffering.
    ///      Toggled via negation (`ticketWriteSlot = !ticketWriteSlot`) during queue slot swaps.
    ///      Write path uses this value; read path uses the opposite.
    ///
    ///      SECURITY: bool toggle via negation. Only values false/true are valid.
    bool internal ticketWriteSlot;

    /// @dev True when purchase revenue redirects to pending accumulators.
    ///      Set at daily RNG request time; cleared by _unfreezePool().
    ///
    ///      SECURITY: Held for one daily / transition lock window — set at the daily
    ///      request, cleared when _unlockRng seals that day (a final-jackpot chain
    ///      keeps it through the phase transition). Every jackpot payout inside a
    ///      window reads pre-freeze pool values. _unfreezePool is the single control
    ///      point.
    bool internal prizePoolFrozen;

    /// @dev Latching terminal for the coin-presale-box window. Set once, in the
    ///      box purchase that crosses the 50-ETH cumulative box cap. While false,
    ///      ETH buys accrue presaleBoxCredit; once true, no further box buys or
    ///      credit accrual occur. Packed into slot 0.
    bool internal presaleOver;

    /// @dev Afking process-STAGE drain-completion flag — the subscriber-drain sibling
    ///      of `ticketsFullyProcessed`. False while the STAGE is stamping the funded
    ///      subscriber set this day; set true once the set is fully drained; flipped back
    ///      to false forward-looking at the start of the next day (the advance's
    ///      `_afkingResetDay != day` gate), so it always reflects "afking done for the
    ///      current day". Packed into slot 0 alongside `level` / `rngLockedFlag` /
    ///      `ticketsFullyProcessed`, which the advance-path STAGE already SLOADs, so it
    ///      costs no additional cold slot access on that path.
    bool internal subsFullyProcessed;

    /// @dev True only after every box entry in the sealed read buffer has settled. Fresh
    ///      requests clear it; retries preserve it and the cursor. Packed into slot 0 beside the
    ///      RNG flags that `_rngConsumerStage` and `_swapRngBuffers` already read and write.
    bool internal humanReadComplete = true;

    /// @dev Slot-0 bytes 30..31. Bits 0..7 hold the nudge count (0..255); bit8 marks RNG
    ///      complete, bit9 the FLIP redemption window, bit10 the request's spent retry; bit11
    ///      marks unpaid parimutuel growth winners, bit12 selects write, bit13 marks terminal;
    ///      bits14/15 identify an active request / published session. All setters preserve
    ///      neighboring fields.
    ///      Complete and published start true; the redemption window and request closed.
    uint16 internal rngFlagsAndNudges = (uint16(1) << 8) | (uint16(1) << 15);
    uint16 internal constant RNG_NUDGE_CAP = 255;
    uint16 private constant RNG_NUDGE_BITS = 0xFF;

    function _ticketRedemptionOpen() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 9) != 0; }
    function _setTicketRedemptionOpen(bool on) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 9)) | (on ? uint16(1) << 9 : 0);
    }
    /// @dev One retry per request: set by the retry and by a coordinator swap's re-issue,
    ///      cleared by every fresh request stamp.
    function _rngRetrySpent() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 10) != 0; }
    function _spendRngRetry() internal { rngFlagsAndNudges |= uint16(1) << 10; }
    function _rearmRngRetry() internal { rngFlagsAndNudges &= ~(uint16(1) << 10); }
    /// @dev Set when a growth-round seal reports unpaid winners; cleared when the mining
    ///      settlement stage reports every sealed round paid.
    function _growthSettlePending() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 11) != 0; }
    function _setGrowthSettlePending(bool on) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 11)) | (on ? uint16(1) << 11 : 0);
    }
    function _rngComplete() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 8) != 0; }
    function _setRngComplete(bool on) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 8)) | (on ? uint16(1) << 8 : 0);
    }
    /// @dev Retained nonzero request metadata is historical; only this bit grants callback authority.
    function _rngRequestActive() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 14) != 0; }
    function _setRngRequestActive(bool on) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 14)) | (on ? uint16(1) << 14 : 0);
    }
    function _rngSessionPublished() internal view returns (bool) { return rngFlagsAndNudges & (uint16(1) << 15) != 0; }
    function _setRngSessionPublished(bool on) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 15)) | (on ? uint16(1) << 15 : 0);
    }

    /// @dev Bit12 selects the accumulating write buffer; the other is sealed read.
    function _rngWriteBuffer() internal view returns (uint48) { return uint48((rngFlagsAndNudges >> 12) & 1); }
    function _rngReadBuffer() internal view returns (uint48) { return _rngWriteBuffer() ^ 1; }
    /// @dev The write buffer becomes the read buffer: its box and bet write counts become the
    ///      read lengths the drains walk, and the new write buffer counts from zero. Pending ETH
    ///      and FLIP clear in the same lootboxRngPacked write. Normal seals and the terminal
    ///      request only; a retry never relatches.
    function _swapRngBuffers() internal {
        uint256 lr = lootboxRngPacked;
        lootboxRngPacked = lr & ~((LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
            | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT) | (LR_COUNT_MASK << LR_BOX_COUNT_SHIFT)
            | (LR_COUNT_MASK << LR_BET_COUNT_SHIFT));
        rngFlagsAndNudges ^= uint16(1) << 12;
        humanReadComplete = false;
        boxCursor = 0;
        boxReadCount = uint32(lr >> LR_BOX_COUNT_SHIFT);
        degeneretteCursor = 0;
        degeneretteReadCount = uint32(lr >> LR_BET_COUNT_SHIFT);
        _setRngComplete(false);
        _setRngSessionPublished(false);
    }
    /// @dev Terminal entry kills unfinished box/bet/Craps consumers, independently of tickets.
    function _setRngTerminal() internal { rngFlagsAndNudges |= uint16(1) << 13; }

    function _nudgeCount() internal view returns (uint256) {
        return rngFlagsAndNudges & RNG_NUDGE_BITS;
    }
    function _setNudgeCount(uint256 count) internal {
        rngFlagsAndNudges = (rngFlagsAndNudges & ~RNG_NUDGE_BITS) | uint16(count);
    }
    function _clearAppliedNudges() internal {
        uint16 old = rngFlagsAndNudges;
        uint16 cleared = old & ~RNG_NUDGE_BITS;
        if (old != cleared) rngFlagsAndNudges = cleared;
    }
    /// @dev Recover the pre-nudge raw word for gap derivation and replay events.
    /// The counter stays frozen under the daily lock until the day recorder clears it.
    function _rawDailyRngWord(uint256 finalWord) internal view returns (uint256 rawWord) {
        unchecked { rawWord = finalWord - _nudgeCount(); }
    }

    // =========================================================================
    // EVM SLOT 1: Prize Pools
    // =========================================================================

    /// @dev Active prize pool for the current level.
    ///      Accumulated from mint fees and distributed via jackpots.
    ///      Packed into slot 1 as uint128 (max ~3.4e20 ETH, far exceeds total supply).
    ///      Access through _getCurrentPrizePool()/_setCurrentPrizePool() helpers.
    uint128 internal currentPrizePool;

    /// @dev Aggregate ETH reserve for player winnings and afking funding.
    ///      INVARIANT: claimablePool >= total payable winnings + total afking funding.
    ///      Decimator settlement reserves the full pool before individual claims are credited.
    ///
    ///      uint128 max ~3.4e20 ETH — far exceeds total ETH supply.
    ///      Packed into slot 1 alongside currentPrizePool.
    uint128 internal claimablePool;

    // =========================================================================
    // SLOT 2+: Full-Width Balances and Pools
    // =========================================================================
    // Each uint256 occupies its own 32-byte slot. These track ETH/token flows.

    /// @dev Packed live prize pools:
    ///      [128:256] futurePrizePool | [0:128] nextPrizePool
    ///      uint128 max ~= 3.4e38 wei, far above any reachable pool.
    ///      Saves 1 SSTORE on every purchase: both halves are written together, so the
    ///      pool split costs one RMW rather than two.
    ///
    ///      SECURITY: All access through _getPrizePools()/_setPrizePools() helpers.
    ///      Direct reads of this variable will get corrupted data.
    uint256 internal prizePoolsPacked;

    /// @dev Nonzero waiting sentinel; accepted session words are always greater than1.
    ///      _currentRngWord() reports the waiting sentinel as absence to consumers.
    uint256 internal constant RNG_WORD_WAITING = 1;
    /// @dev Nonzero waiting payload avoids a fresh SSTORE in the billed callback.
    ///      Final words 0/1 are refused and remain pending for the existing request retry.
    uint256 internal rngWordCurrent = RNG_WORD_WAITING;

    function _currentRngWord() internal view returns (uint256) {
        uint256 stored = rngWordCurrent;
        return stored == RNG_WORD_WAITING ? 0 : stored;
    }

    /// @dev Retained last VRF request ID, initialized to nonzero idle sentinel 1.
    ///      Callback authority requires the packed active bit as well as ID matching.
    ///
    ///      SECURITY: Request ID matching prevents replay attacks on RNG.
    uint256 internal vrfRequestId = 1;

    /// @dev Logical day the request in flight belongs to, independent of transport/retry time;
    ///      zero for a mid-day request and on terminal entry until the terminal request.
    uint24 internal rngRequestDay;
    /// @dev Set once the request day's skipped-day gap is backfilled; a fresh request clears it.
    bool internal rngGapApplied;

    /// @dev Timestamp of the last successfully processed VRF word.
    ///      Used by governance to detect VRF stalls (time-based vs day-gap-based); game
    ///      liveness does not read it (a gap behind dailyIdx is itself the stall signal).
    ///      Initialized in wireVrf(), updated in _applyDailyRng(). Shares slot 5 with the
    ///      request day and the ticket buffer stamps.
    uint48 internal lastVrfProcessedTimestamp;
    /// @dev Even/odd ticket epochs: two uint24 levels, slot-5 bytes 10..15.
    uint48 internal ticketBufferLevels;

    /// @dev Packed daily jackpot ticket data, handed from one advance stage to the next.
    ///      Layout: [reserved (8 bits @ 0)] [dailyEntries (64 bits @ 8)] [battlePending (1 bit @ 72)]
    ///              [unused (71 bits @ 73)] [earlyBirdEntries (64 bits @ 144)]
    ///              [purchaseEntries (48 bits @ 208)]
    ///      Jackpot phase: set by the ETH stage; on the early-bird day the early-bird stage
    ///      consumes the earlyBird field and clears it; the battle stage clears battlePending; the
    ///      coin+tickets stage consumes dailyEntries and zeroes the word. Purchase phase: the
    ///      daily prices its ticket leg into the top field and the purchase ticket stage consumes
    ///      and clears it after the purchase battle stage consumes battlePending. Both phases use
    ///      the same battle bit and keep the RNG lock until their final stage. Every predicate
    ///      masks its own field.
    uint256 internal dailyTicketBudgetsPacked;

    // =========================================================================
    // Token State and Jackpot Mechanics
    // =========================================================================

    /// @dev Per-player ETH balances packed into one slot: [afking:high128 | claimable:low128].
    ///      - claimable (low 128 bits): ETH claimable from jackpot winnings.
    ///      - afking (high 128 bits): prepaid AfKing subscription funding.
    ///      Both halves ride inside claimablePool (no separate aggregate); each mutation moves
    ///      claimablePool in tandem at the call site. Read and written only through the
    ///      _claimableOf / _afkingOf / _credit* / _debit* accessors, which split and recombine
    ///      the two halves; per-player ETH <= total supply (~1.2e26 wei << 2^128), so neither
    ///      half can overflow.
    ///
    ///      Keyed by wallet ID: every payout already holds the ID; address-only paths (withdraw,
    ///      deposits, views) read it from mintPacked_ once. ID 0 never holds a balance.
    ///
    ///      SECURITY: Pull pattern — players and funders withdraw their own funds (the claim
    ///      function / withdrawAfkingFunding), separating credit from transfer.
    mapping(uint32 => uint256) internal balancesPacked;

    /// @dev Two physical trait buffers, keyed by actualLevel & 1. Each header packs
    ///      a uint32 count and up to seven uint32 owner-index tail lanes above it.
    ///      Full buffer level plus traitBucketLive validate each header. Completed
    ///      words hold eight uint32 indices at keccak256(headerSlot).
    ///      Owner registries remain keyed by actual level. Never treat a header as
    ///      a Solidity array length; all readers use the validated bucket helpers.
    mapping(uint24 => uint256[256]) internal lvlTraitEntry;

    /// @dev Bit-packed mint history per player.
    ///      Layout defined by constants in BitPackingLib and MintStreakUtils.
    ///      Tracks mint counts, bonuses, eligibility flags, deity pass, and affiliate bonus cache.
    ///      Single SLOAD/SSTORE for all mint-related player data.
    ///
    ///      SECURITY: Packing reduces gas and storage footprint.
    ///      Bit manipulation requires careful masking (done via BitPackingLib shifts and masks).
    mapping(uint32 => uint256) internal mintPacked_;

    // =========================================================================
    // RNG History
    // =========================================================================

    /// @dev Two reusable word slots, indexed by day parity and authenticated
    ///      by rngDayTags. Events provide historical replay; live views expose
    ///      today/yesterday only.
    mapping(uint24 => uint256) internal rngWordByDay;

    /// @dev Exact tag authentication also serves pinned processing days older than
    ///      yesterday. A committed word cannot be overwritten before consumers finish.
    function _recordedDailyWord(uint24 day) internal view returns (uint256) {
        uint256 shift = uint256(day & 1) * 24;
        if (day == 0 || uint24(uint256(rngDayTags) >> shift) != day) return 0;
        return rngWordByDay[day & 1];
    }

    function _recordDailyRng(uint24 day, uint256 word) internal {
        uint256 shift = uint256(day & 1) * 24;
        rngDayTags = uint48((uint256(rngDayTags) & ~(uint256(type(uint24).max) << shift)) | (uint256(day) << shift));
        rngWordByDay[day & 1] = word;
    }

    function _retainedDailyWord(uint24 day) internal view returns (uint256) {
        uint24 today = _simulatedDayIndex();
        if (day > today || uint256(today) - day > 1) return 0;
        return _recordedDailyWord(day);
    }

    // =========================================================================
    // Future Mint Awards
    // =========================================================================

    /// @dev Packed pending accumulators for purchase revenue during prize pool freeze.
    ///      [128:256] futurePending | [0:128] nextPending
    ///      Accumulated while prizePoolFrozen == true; applied atomically by _unfreezePool().
    ///
    ///      SECURITY: Zeroed at freeze start (if not already frozen) and at unfreeze.
    ///      Accumulators grow for the length of one lock window (request -> day seal);
    ///      a jackpot day re-freezes at its own request.
    uint256 internal prizePoolPendingPacked;

    /// @dev Queue of players with tickets (purchase/burn sources) per level.
    ///      Purchases, lootbox rewards and deferred jackpot awards queue here.
    ///      Main-daily awards can materialize directly in an already active next level.
    ///
    ///      PROCESSING SCHEDULE:
    ///      - Minted window [purchaseLevel-1 .. purchaseLevel]: the read cohort of each key
    ///        is drained by the ticket worker (TicketModule runTicketWork); the daily slot swap commits
    ///        the write cohort.
    ///      - Unminted future levels (above _mintCeiling()): held in the far-future key space
    ///        with no traits. A fresh mid-day request after level L meets its goal can
    ///        activate L+1 early. A turbo transition also activates it; the ordinary
    ///        purchase daily waits. The last-purchase latch may close its far-future queue earlier;
    ///        in either case that frozen queue mints on a word requested after the freeze,
    ///        before the last-purchase consolidation, so the BAF, the
    ///        early-bird and the jackpot-phase bonus draws all see L+1 minted.
    ///
    ///      EXAMPLE (level 5 purchase phase, level = 4, purchaseLevel = 5):
    ///      - ticketQueue[_ticketQueueStorageKey(4..5)] read cohorts → swept every advance
    ///      - ticketQueue[_ticketQueueStorageKey(6+)] → far-future space; 6 can mint once level 5 meets its goal
    ///
    ///      Near queues reuse two parity slots; far-future queues reuse slots 1..100.
    ///      Logical keys pass through _ticketQueueStorageKey; the header's level tag authenticates them.
    ///      Keys retain their domain flags: bit 23 selects the
    ///      double-buffer write/read half (ticketWriteSlot); tickets targeting > level+1 use the
    ///      disjoint far-future key space (bit 22). Raw-level indices above hold only when
    ///      ticketWriteSlot is false.
    ///      The length word is a HEADER: bits 0..31 count QUEUED OWNERS and bits 32..55 tag the
    ///      occupying absolute level (zero: the physical slot's own level, `physical & 0x7f`).
    ///      Release clears only the count, so a reused root keeps a nonzero header. Data word w
    ///      holds eight uint32 lanes for positions 8w..8w+7, low lane first, each holding a
    ///      nonzero wallet ID (the wallet table position). Never use Solidity array indexing,
    ///      length, push, pop or delete on this mapping. Readers are length-gated; append
    ///      overwrites the selected lane after queue reuse.
    mapping(uint24 => uint256[]) internal ticketQueue;

    /// @dev Wallet table: an ordinary account stores its payout address [0:160). A subaccount
    ///      stores zero there and its ordinary owner's ID [160:192). Whale half-pass count
    ///      occupies [192:256). Acquired roots retain the seller key and store buyer ID in
    ///      the owner lane; children keep their parent. Element zero is unassigned. walletIds
    ///      supplies the forward lookup for ordinary wallets only.
    uint256[] internal wallets;

    /// @dev Cursor for ticket queue processing (dual-purpose).
    ///      - SETUP phase: tracks near-future level progress (1-4), reset to 0 when done.
    ///      - PURCHASE phase: tracks mint batch progress through ticketQueue.
    ///      - JACKPOT phase: tracks jackpot batch progress through ticketQueue.
    ///      Phases are mutually exclusive, so cursor is reused safely.
    uint32 internal ticketCursor;

    /// @dev Current level being processed in ticket queue operations.
    uint24 internal ticketLevel;

    /// @dev Active snap divisor exponent: drained owed balances for levels below
    ///      snapLevel divide by 2^snapShift. Moves only at level commit, by folding
    ///      in a reached declaration. Zero outside runaway-demand states.
    uint8 internal snapShift;

    /// @dev Pending thanos declaration: levels >= snapLevel drain at snapPendingShift
    ///      instead of snapShift. Declared via setThanosLevel at least 3 levels ahead,
    ///      strictly before the target's first materialization (the seal of level
    ///      target-1's purchase phase, while level == target-2), so one level's entries always
    ///      share one exponent regardless of when they were bought or drained —
    ///      the invariant that keeps any declared change (raise or lower) EV-neutral.
    ///      snapLevel == 0 means no pending declaration.
    uint24 internal snapLevel;

    /// @dev Shift that applies from snapLevel onward. Folded into snapShift at the
    ///      level commit that reaches snapLevel.
    uint8 internal snapPendingShift;

    /// @dev Round counter for the seated ticket drain: every round of group trait rolls
    ///      keys its derivation off this value, so a budget-split resume continues the
    ///      same sequence. Never reset.
    uint32 internal ticketRound;

    /// @dev Absolute solo position for the current authenticated ticket owner.
    uint32 internal ticketSoloOffset;
    /// @dev Independent read-side bet cursor; packed into unused ticket-control bytes.
    uint48 internal degeneretteCursor;
    /// @dev Bets in the sealed read buffer, latched from the write count at the seal. The
    ///      drain walks positions [degeneretteCursor, degeneretteReadCount).
    uint32 internal degeneretteReadCount;

    // =========================================================================
    // Ticket Queue Helpers
    // =========================================================================

    /// @notice Emitted when traits are generated for a wallet's ticket batch.
    ///         Records the encoded key + count needed to replay trait generation off-chain.
    ///         The key carries the wallet ID in bits 32..63 and the run's start offset in
    ///         bits 0..31. Solo baseKey bit 255 records whether gold six was already taken
    ///         before this run. Strip that event-only bit and the offset before deriving
    ///         the stream's entropy.
    event TraitsGenerated(
        uint32 indexed walletId,
        uint256 baseKey,
        uint32 take
    );

    /// @notice Direct entry reveals for up to four wallets, without a signature topic.
    ///         Each nonzero topic is (uint256(level) << 160) | walletId. Query all
    ///         four topic positions separately and deduplicate by transaction/log index.
    ///         An unused player topic is zero. In `entries`, byte (4*j+q) is player j's
    ///         trait in quadrant q; bit (128+4*j+q) marks that byte as present. Trait zero
    ///         is valid, so the presence bits MUST be checked. The trait byte itself
    ///         includes the quadrant in its top two bits. This is entry inventory only:
    ///         no card identity, generation boundary or owner-registry lookup is needed.
    ///         Decode with this explicit anonymous ABI, not topic0 signature discovery.
    event EntryTraitsRevealed(
        uint256 indexed player0,
        uint256 indexed player1,
        uint256 indexed player2,
        uint256 indexed player3,
        uint144 entries
    ) anonymous;

    /// @notice Emitted when a future level is declared a thanos level.
    event ThanosLevelSet(uint24 targetLevel, uint8 shift);

    /// @notice Emitted when entries are queued for a wallet at a specific level. The queue
    ///         sinks hold only the wallet ID; WalletRegistered maps it to the address.
    event EntriesQueued(
        uint32 indexed walletId,
        uint24 targetLevel,
        uint32 entries
    );

    /// @notice Emitted when scaled entries (entries × QTY_SCALE) are queued for a wallet.
    event EntriesQueuedScaled(
        uint32 indexed walletId,
        uint24 targetLevel,
        uint32 entriesScaled
    );

    /// @notice Emitted when entries are queued across a range of levels. Covered levels are
    ///         startLevel, startLevel + stride, ... (numLevels of them); stride 1 = contiguous.
    event EntriesQueuedRange(
        uint32 indexed walletId,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel
    );

    /// @notice Emitted when a deity pass is purchased.
    event DeityPassPurchased(
        uint32 indexed buyer,
        uint8 symbolId,
        uint256 price,
        uint24 level
    );

    /// @dev Whale pass awarded in place of an ETH, lootbox or early-bird ticket payout — otherwise the
    ///      wallet-table half-pass increment is silent. Declared once here for JackpotModule and WhaleModule,
    ///      which both emit it through GAME's delegatecall. `halfPassCount` is in half-pass claim units.
    ///      The award is a bare half-pass counter binding to no level: claimWhalePass sets the target
    ///      from the level standing at claim time and reports it on WhalePassClaimed. The paying level
    ///      is not carried here either — every emit site sits in a receipt that already stamps it.
    ///      `source`: 2 BAF direct, 3 award tickets (JackpotModule), 4 early bird, 5 quadrant
    ///      conversion (WhaleModule); 1 (the solo-only half-pass conversion) is retired.
    event JackpotWhalePassWin(
        uint32 indexed walletId,
        uint256 halfPassCount,
        uint8 source
    );

    /// @notice Emitted when game-over drain processes terminal jackpots.
    event GameOverDrained(
        uint24 level,
        uint256 available,
        uint256 claimablePool
    );

    /// @notice Once-per-day snapshot of the prize-pool triple plus the claimable reserve, the
    ///         solvency total (ETH + stETH), and the yield accumulator, emitted at the conclusion
    ///         of each daily advance and once at game-over. Lets the off-chain indexer mirror the
    ///         pool balances — which are mutated at many sites with no per-delta event — and keep a
    ///         daily solvency checksum from logs alone. Field order/names are read by the indexer.
    ///         `day` is the sealed day the snapshot belongs to, so the reading side never
    ///         infers it from surrounding event order. It carries no level or phase: the
    ///         seal runs ahead of the stage-3 purchaseStartDay/jackpotPhaseFlag writes, so
    ///         those fields would report pre-transition state here.
    event PrizePoolDailySnapshot(
        uint256 next,
        uint256 future,
        uint256 current,
        uint256 claimable,
        uint256 totalBalance,
        uint256 yieldAccumulator,
        uint24 day
    );

    /// @notice Emitted when final sweep forfeits unclaimed winnings 30 days post-gameover.
    event FinalSwept(uint256 totalFunds);

    /// @dev Emitted when a wallet's claimable balance is credited at a site with no event of its
    ///      own naming the wallet and amount (see _creditClaimableLogged).
    event PlayerCredited(uint32 indexed walletId, uint256 amount);

    /// @dev Emitted when a VRF word is bound to a lootbox RNG index (mid-day finalize,
    ///      daily apply, or dead-man fallback). Emitted from both the Game callback and
    ///      the AdvanceModule, so it lives in the shared base.
    event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId);

    /// @dev Emitted when a LINK donation adds mid-day RNG credit, in juels.
    ///      `balance` is the post-credit balance.
    event MiddayRngCredited(
        address indexed donor,
        uint256 added,
        uint256 balance
    );

    /// @dev Emitted when credit is charged to pay a mid-day request's threshold gate.
    ///      `balance` is the post-charge balance. Emitted from the RNG module, paired with
    ///      MiddayRngCredited from the Game, so both live in the shared base.
    event MiddayRngCreditSpent(
        address indexed spender,
        uint256 charged,
        uint256 balance
    );

    /// @dev Emitted when the vault owner retunes the mid-day basefee ceiling, in gwei.
    event MiddayMaxBasefeeUpdated(uint256 prev, uint256 next);

    /// @dev Emitted whenever prepaid afking ETH is spent to fund a buy (the afking-as-payment
    ///      waterfall's third tier) — full observability of where afking principal goes.
    event AfkingSpent(uint32 indexed walletId, uint256 amount);

    /// @dev A mining crank paid in FLIP. The credit itself rides `coinflip.creditFlip`, which
    ///      emits nothing attributable, so without this the whole miner revenue stream is
    ///      readable only by scanning tx selectors. The unified miner emits it with
    ///      `MINER_BOUNTY_ADVANCE`, the only kind production pays.
    event MinerBounty(
        uint8 kind,
        address indexed miner,
        uint256 flipAmount
    );

    /// @dev `MinerBounty.kind` for a paid mining crank.
    uint8 internal constant MINER_BOUNTY_ADVANCE = 1;

    /// @dev Emitted whenever a player's claimable balance is debited by the protocol. Covers
    ///      mint payments (MintPaymentKind.Claimable / Combined), lootbox/ticket shortfall
    ///      (Internal), foil pack shortfall (Internal), salvage debits (Internal), sDGNRS
    ///      redemption reserve (Internal), and game-over sweep (Internal). `amount` is the
    ///      exact claimable wei removed; `newBalance` is the post-debit claimable balance.
    event ClaimableSpent(
        uint32 indexed walletId,
        uint256 amount,
        uint256 newBalance,
        MintPaymentKind payKind,
        uint256 costWei
    );

    /// @notice Emitted when a boon is consumed by a player.
    /// @dev boonType: 1 coinflip, 2 purchase, 3 decimator, 4 degenerette,
    ///      5 activity award, 6 craps, 7 WWXRP ecosystem.
    event BoonConsumed(uint32 indexed walletId, uint8 boonType, uint16 boostBps);

    /// @notice Emitted when admin swaps game ETH for stETH.
    event AdminSwapEthForStEth(address indexed recipient, uint256 amount);

    /// @notice Emitted when admin stakes game ETH into Lido stETH.
    event AdminStakeEthForStEth(uint256 amount);

    /// @dev The logical ticket level the terminal game-over jackpot pays from. Purchase-phase
    ///      tickets normally target `lvl + 1`; jackpot-phase tickets target the current `lvl`.
    ///      The locked last-purchase transition is the one semantic exception: the RNG request has
    ///      already promoted `level`, so the purchase cohort committed before that request now sits
    ///      at `lvl`, while later write-buffer purchases target `lvl + 1`. Shared by the game-over
    ///      ticket DRAIN (AdvanceModule) and terminal-jackpot READ (GameOverModule), keeping the
    ///      materialized trait bucket and payout bucket identical in every terminal state.
    ///      The terminal path latches the answer on its first entry and every later read
    ///      returns the latch. That is what lets the terminal sequence hold the RNG lock:
    ///      the un-latched form infers "the last-purchase request already promoted level"
    ///      from rngLockedFlag, so a lock taken for terminal reasons would otherwise move
    ///      this level between transactions and split the drained cohort from the payout
    ///      bucket. `level` itself cannot move once the game-over path owns the advance.
    function _gameOverTicketLevel(uint24 lvl) internal view returns (uint24) {
        uint256 latched = _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK);
        if (latched != 0) return latched == 1 ? lvl : lvl + 1;
        return (jackpotPhaseFlag || (lastPurchaseDay && rngLockedFlag)) ? lvl : lvl + 1;
    }

    /// @dev Highest level whose tickets are minted: entries up to it take the double buffer,
    ///      entries above it wait unminted in the far-future key space. Normally level + 1.
    ///      From the seal that latches lastPurchaseDay until the last-purchase request bumps
    ///      `level`, it is level + 2: that seal freezes the next level's far-future pool (later
    ///      entries take its write buffer). The pool mints inside the unified sweep with the first
    ///      cohort committed after the seal — the first RNG request after it, mid-day or daily
    ///      (TicketModule runTicketWork). The last-purchase request takes the lock and bumps
    ///      `level`, returning the ceiling to level + 1 = the same level. A target-met
    ///      request may activate that same level earlier; retain its ceiling after
    ///      draining so later purchases never reopen the frozen queue.
    function _mintCeiling() internal view returns (uint24) {
        uint24 ceiling = level + ((lastPurchaseDay && !rngLockedFlag) ? 2 : 1);
        uint24 early = earlyTicketLevel;
        return early > ceiling ? early : ceiling;
    }

    /// @dev The frozen next-level pool is sweep work only once a cohort has been
    ///      committed AFTER the latch — the last-purchase request (rngLockedFlag) or a post-latch
    ///      mid-day request (mid-day latch). Before that no word exists for it, and a stale
    ///      !ticketsFullyProcessed (genesis) would make the drain gate demand one that never comes.
    ///      The isolated early-pool latch is itself a commitment made with a fresh request.
    function _frozenPoolDue() internal view returns (bool) {
        // An isolated early pool has earlyTicketLevel == level + 2. If a final-day
        // retry promotes level before its drain, lastPurchaseDay still holds the latch.
        return (lastPurchaseDay || earlyTicketLevel > level + 1)
            && (rngLockedFlag || _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0);
    }

    /// @dev Derived actions only: no independently stored engine stage can become stale.
    enum MinerAction {
        Idle, Terminal, Wait, Publish, Tickets, DailyGap, DailyApply, DailyPhase,
        Redemption, Afking, HumanBoxes, Degenerette, Decimator, Craps,
        CertifyRead, PrepareSubscriptions, Maintenance, RequestDaily, RequestMidday, GrowthSettle
    }

    function _minerMaintenancePending() internal view returns (bool) {
        return IGameMinerMaintenance(ContractAddresses.CRAPS).minerMaintenancePending();
    }

    /// @dev `caller` is the account whose donated credit may pay the mid-day threshold gate;
    ///      address(0) selects as a creditless caller.
    function _nextMinerAction(address caller) internal view returns (MinerAction) {
        if (gameOver) {
            if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) == 0) return MinerAction.Terminal;
            uint256 ended = _goRead(GO_TIME_SHIFT, GO_TIME_MASK);
            return ended != 0 && block.timestamp >= ended + 30 days && _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) == 0
                ? MinerAction.Terminal : MinerAction.Idle;
        }
        if (_livenessTriggered()) {
            // The first terminal call must latch its cohort. Once latched, waiting
            // cannot advance it; a dead VRF still takes precedence over the wait.
            if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0
                && _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) == 0
                && _rngRequestActive() && _currentRngWord() == 0 && !_vrfDead()) return MinerAction.Wait;
            return MinerAction.Terminal;
        }
        if (_rngRequestActive() && _currentRngWord() == 0) {
            return MinerAction.Wait;
        }
        if (_rngRequestActive() && !_rngSessionPublished()) return MinerAction.Publish;
        if (!_rngComplete()) {
            if (!_rngSessionPublished() || _currentRngWord() == 0) return MinerAction.Wait;
            if (!ticketsFullyProcessed) return MinerAction.Tickets;
            if (rngLockedFlag) {
                if (_recordedDailyWord(rngRequestDay) != 0) return MinerAction.DailyPhase;
                return rngRequestDay > dailyIdx + 1 ? MinerAction.DailyGap : MinerAction.DailyApply;
            }
            uint8 consumer = _rngConsumerStage();
            if (consumer == 1) return MinerAction.Redemption;
            if (consumer == 2) return MinerAction.Afking;
            if (consumer == 3) return MinerAction.HumanBoxes;
            if (consumer == 4) return MinerAction.Degenerette;
            if (consumer == 5) return MinerAction.Decimator;
            if (consumer == 6) return MinerAction.Craps;
            return consumer == 7 ? MinerAction.CertifyRead : MinerAction.Wait;
        }
        // The old read certificate stays valid while NEW subscriptions are stamped.
        bool dailyDue = _afkingResetDay > dailyIdx || _simulatedDayIndex() > dailyIdx;
        if (dailyDue && (_afkingResetDay <= dailyIdx || !subsFullyProcessed)) return MinerAction.PrepareSubscriptions;
        if (_minerMaintenancePending()) return MinerAction.Maintenance;
        if (dailyDue) return MinerAction.RequestDaily;
        // Behind the day's request, so a long settlement never delays the daily word; ahead of
        // the optional mid-day request, which would otherwise starve it.
        if (_growthSettlePending()) return MinerAction.GrowthSettle;
        return _minerMiddayEligible(caller) ? MinerAction.RequestMidday : MinerAction.Idle;
    }

    uint96 internal constant MIN_LINK_FOR_LOOTBOX_RNG = 40 ether;
    uint96 internal constant MIN_LINK_FOR_CRAPS_RNG = 10 ether;

    /// @dev The mid-day request's own refusal gates, read before selecting it: an optional
    ///      request that would certainly be refused is not work. Daily, read, maintenance and
    ///      liveness gates already hold on the path that reaches this check. A pending
    ///      write-side Craps window waives both pending-value gates. Otherwise an empty queue
    ///      is never eligible, and a queue below the threshold is eligible only when `caller`'s
    ///      donated credit covers the charge, priced last so the Admin feed is read only when
    ///      every other gate passes.
    function _minerMiddayEligible(address caller) internal view returns (bool) {
        bool crapsWork = (lootboxRngPacked >> (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer())) & 1 != 0;
        bool needsCredit;
        if (!crapsWork) {
            uint256 pendingEth = _unpackMilliEthToWei(uint64(_lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK)));
            if (pendingEth == 0 && _lrRead(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK) == 0) return false;
            uint256 threshold = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
            if (threshold != 0 && pendingEth < threshold) {
                if (caller == address(0)) return false;
                needsCredit = true;
            }
        }
        if (_simulatedDayIndex() != dailyIdx) return false;
        uint256 maxBasefee = _lrRead(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK);
        if (maxBasefee != 0 && block.basefee > maxBasefee * 1 gwei) return false;
        if ((block.timestamp - 82_620) % 1 days >= 1 days - 1 minutes) return false;
        if (_recordedDailyWord(_simulatedDayIndex()) == 0) return false;
        // No coordinator is wired before VRF setup, so nothing can be requested yet.
        if (address(vrfCoordinator) == address(0)) return false;
        (uint96 linkBal,,,,) = vrfCoordinator.getSubscription(vrfSubscriptionId);
        if (linkBal < (crapsWork ? MIN_LINK_FOR_CRAPS_RNG : MIN_LINK_FOR_LOOTBOX_RNG)) return false;
        if (!needsCredit) return true;
        (bool covered,,,) = _middayCreditCharge(caller);
        return covered;
    }

    /// @dev The donated-credit charge for one mid-day request at this block's basefee:
    ///      MIDDAY_RNG_CHARGE_MULT times the billed gas, converted to juels at the Admin's
    ///      LINK/ETH price. `covered` is false for a zero balance or an unpriced feed, so the
    ///      selector and the RNG module's charge always agree within a transaction.
    function _middayCreditCharge(address caller)
        internal view returns (bool covered, uint256 charge, uint256 balance, uint32 id)
    {
        id = _walletIdOf(caller);
        balance = middayRngCredit[id];
        // A zero balance never qualifies, even where basefee (and so the charge) is zero.
        if (balance == 0) return (false, 0, 0, id);
        uint256 weiPerLink = IAdminLinkValue(ContractAddresses.ADMIN).linkAmountToEth(1 ether);
        if (weiPerLink == 0) return (false, 0, balance, id);
        charge = (MIDDAY_RNG_BILLED_GAS * block.basefee * MIDDAY_RNG_CHARGE_MULT * 1 ether) / weiPerLink;
        covered = balance >= charge;
    }

    /// @dev True while the early-bird ticket leg of a jackpot-phase day-1 daily waits for its
    ///      own advance stage: the ETH stage priced it into the top field of
    ///      dailyTicketBudgetsPacked. The coin+tickets stage is not reached until that stage
    ///      clears the field, so the day stays locked across all three.
    function _earlyBirdLegPending() internal view returns (bool) {
        return uint64(dailyTicketBudgetsPacked >> 144) != 0;
    }

    /// @dev The battle-pending bit of dailyTicketBudgetsPacked (see its layout).
    uint256 internal constant _JACKPOT_BATTLE_PENDING = uint256(1) << 72;

    /// @dev True while either phase's jackpot battle still owes work. The daily RNG request latches
    ///      it when it locks the field; the battle stage clears it once the field completes, before
    ///      any other daily stage runs.
    function _jackpotBattlePending() internal view returns (bool) {
        return (dailyTicketBudgetsPacked & _JACKPOT_BATTLE_PENDING) != 0;
    }

    /// @dev True while the ticket leg of a purchase-phase daily waits for its own advance
    ///      stage: runDailyJackpot(false) priced it into the top field of
    ///      dailyTicketBudgetsPacked. The day stays locked until that stage seals it.
    function _purchaseTicketLegPending() internal view returns (bool) {
        return dailyTicketBudgetsPacked >> 208 != 0;
    }

    /// @dev True from the purchase deadline day (the last day before liveness can fire) until
    ///      the level's target is met: once lastPurchaseDay or jackpotPhaseFlag is set the level
    ///      can no longer die by liveness, so there is nothing left to rescue.
    ///      Used to activate distress-mode lootbox behaviour: 100% nextpool allocation
    ///      and 25% ticket bonus on the distress-bought portion.
    function _isDistressMode() internal view returns (bool) {
        if (gameOver || lastPurchaseDay || jackpotPhaseFlag) return false;
        return _simulatedDayIndex() >= _purchaseDeadlineDay();
    }

    /// @dev Shared day boundary for distress and purchase-phase liveness.
    function _purchaseDeadlineDay() internal view returns (uint24) {
        return purchaseStartDay + (level == 0 ? uint24(_DEPLOY_IDLE_TIMEOUT_DAYS) : _PURCHASE_TIMEOUT_DAYS);
    }

    /// @dev Queues entries for a wallet at a target level. The `entries` arg is in
    ///      entry units (price/4 each), NOT whole tickets — 4 entries per
    ///      whole ticket. `owed` accumulates entries.
    ///      If the wallet has no existing entries at that level, adds it to the queue.
    ///      Far-future owed saturates at 2^30-1; normal cohorts retain uint32 owed.
    /// @param id Wallet ID to receive entries.
    /// @param targetLevel Level for which entries are queued.
    /// @param entries Number of entries to queue (price/4 units).
    /// @param rngLockExempt True to skip the RngLocked revert on a new far-future lane.
    function _queueEntries(
        uint32 id,
        uint24 targetLevel,
        uint32 entries,
        bool rngLockExempt
    ) internal {
        if (entries == 0) return;
        // No liveness gate here: tickets queued during the liveness-timeout window are harmless.
        // They are never processed (the game-over drain ends the game without a further daily
        // draw) or the resolving daily word has not been requested yet, so no terminal jackpot
        // can be manipulated by them. Player purchase paths gate liveness at their own entry; the
        // advance-chain daily-jackpot distribution also queues through this sink and must NOT be
        // reverted here, so the gate stays off the shared sink.
        // Levels above _mintCeiling() are unminted: they stay queued in the far-future key space
        // until their level's pool mints. Unminted-level draws sample one queue lane per wallet,
        // so under the RNG lock only a NEW lane could move them and reverts;
        // a top-up only raises owed.
        bool isFarFuture = targetLevel > _mintCeiling();
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint80 packed = _entryPacked(wk, id);
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (packed == 0) {
            if (isFarFuture && rngLockedFlag && !rngLockExempt) revert RngLocked();
            packed = uint80(id) << OWNER_IDX_SHIFT;
            _tqAppend(wk, id);
        }
        emit EntriesQueued(id, targetLevel, entries);
        owed = _addOwed(owed, entries, isFarFuture);
        _setEntryOwed(wk, id, (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem));
    }

    /// @dev Converts a post-Bernoulli whole-ticket count into the entries unit the
    ///      entry owed sink accumulates. One whole ticket (priceForLevel(level))
    ///      is 4 entries (each = price/4), so entries = wholeTickets << 2.
    ///      The sole canonical whole->entries conversion both prize legs route through.
    ///      Both callers bound the input so `<< 2` fits uint32 with no guard: the jackpot
    ///      roll passes at most ~42.9M (scaledWholeTickets/100, uint32-capped), and the
    ///      lootbox accumulator saturates each lane at uint32.max >> 2 before flushing.
    /// @param wholeTickets Whole-ticket count (each = priceForLevel(level)).
    /// @return Entries count (each = price/4); 4 per whole ticket.
    function wholeTicketsToEntries(uint32 wholeTickets) internal pure returns (uint32) {
        return wholeTickets << 2;
    }

    /// @dev Snap exponent for a target level's drain: the pending declaration for
    ///      levels at or past snapLevel, the active snapShift below it. One warm
    ///      SLOAD (shares the ticketCursor slot) plus two compares. Shared by the
    ///      ticket drains (MintModule) and the foil buy gate (FoilPackModule).
    function _snapShiftFor(uint24 targetLvl) internal view returns (uint8) {
        uint24 pl = snapLevel;
        if (pl != 0 && targetLvl >= pl) return snapPendingShift;
        return snapShift;
    }

    /// @dev Queues scaled entries (2 decimal places) for fractional purchases.
    ///      Handles remainder accumulation and promotes to a whole owed entry when
    ///      remainder >= QTY_SCALE.
    /// @param id Wallet ID to receive entries.
    /// @param targetLevel Level for which entries are queued.
    /// @param entriesScaled Scaled entries (entries x 100); owed gains entriesScaled / QTY_SCALE entries.
    function _queueEntriesScaled(
        uint32 id,
        uint24 targetLevel,
        uint32 entriesScaled
    ) internal {
        if (entriesScaled == 0) return;
        _queueEntriesScaledCore(id, targetLevel, entriesScaled, targetLevel > _mintCeiling());
    }

    /// @dev Purchase callers route through _activeTicketLevel(), which never exceeds level+1.
    ///      These entries are always inside the normal ceiling, including final-jackpot reroutes;
    ///      skip the far-future ceiling's cold earlyTicketLevel read and share the same codec.
    function _queuePurchaseEntries(uint32 id, uint24 targetLevel, uint32 entriesScaled) internal {
        if (entriesScaled == 0) return;
        _queueEntriesScaledCore(id, targetLevel, entriesScaled, false);
    }

    function _queueEntriesScaledCore(
        uint32 id,
        uint24 targetLevel,
        uint32 entriesScaled,
        bool isFarFuture
    ) private {
        // No liveness gate (see _queueEntries): post-liveness queued tickets are harmless.
        uint24 wk = isFarFuture
            ? _tqFarFutureKey(targetLevel)
            : _tqWriteKey(targetLevel);
        uint80 packed = _entryPacked(wk, id);
        uint32 owed = uint32(packed >> 8);
        uint8 rem = uint8(packed);
        if (packed == 0) {
            if (isFarFuture && rngLockedFlag) revert RngLocked();
            packed = uint80(id) << OWNER_IDX_SHIFT;
            _tqAppend(wk, id);
        }
        emit EntriesQueuedScaled(id, targetLevel, entriesScaled);

        uint32 whole = uint32(uint256(entriesScaled) / QTY_SCALE);
        uint8 frac = uint8(uint256(entriesScaled) % QTY_SCALE);
        owed = _addOwed(owed, whole, isFarFuture);

        if (frac != 0) {
            uint16 newRem;
            unchecked {
                newRem = uint16(rem) + uint16(frac);
            }
            if (newRem >= QTY_SCALE) {
                owed = _addOwed(owed, 1, isFarFuture);
                newRem -= uint16(QTY_SCALE);
            }
            rem = uint8(newRem);
        }
        uint80 newPacked = (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem);
        if (newPacked != packed) {
            _setEntryOwed(wk, id, newPacked);
        }
    }

    /// @dev Queues tickets for a contiguous range of levels with same quantity per level.
    /// @param id Wallet ID to receive tickets.
    /// @param startLevel First level in range (inclusive).
    /// @param numLevels Number of consecutive levels.
    /// @param entriesPerLevel Entries to award per level (4 entries = 1 whole ticket).
    function _queueEntryRange(
        uint32 id,
        uint24 startLevel,
        uint24 numLevels,
        uint32 entriesPerLevel
    ) internal {
        _queueEntryRangeStridedCore(
            id, startLevel, numLevels, 1, entriesPerLevel,
            _mintCeiling(), rngLockedFlag, ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0)
        );
    }

    /// @dev Queues entries at every `stride`-th level: startLevel, startLevel + stride, ...
    ///      (`numLevels` covered levels). Shared walk for contiguous (stride 1) and strided
    ///      whole-ticket awards; far-future routing, RNG-lock revert, and write-slot selection
    ///      are per-level, so skipped levels need no handling.
    /// @param id Wallet ID to receive tickets.
    /// @param startLevel First covered level (inclusive).
    /// @param numLevels Number of covered levels.
    /// @param stride Gap between covered levels (1 = contiguous).
    /// @param entriesPerLevel Entries to award per covered level (4 entries = 1 whole ticket).
    /// @param mintCeiling Caller's cached _mintCeiling(), read once for every leg of the walk.
    /// @param rngLockedCached Caller's cached `rngLockedFlag`, read once for every leg.
    /// @param writeSlotBit Caller's cached ticket write-slot bit
    ///        (`ticketWriteSlot ? TICKET_SLOT_BIT : 0`).
    function _queueEntryRangeStridedCore(
        uint32 id,
        uint24 startLevel,
        uint24 numLevels,
        uint24 stride,
        uint32 entriesPerLevel,
        uint24 mintCeiling,
        bool rngLockedCached,
        uint24 writeSlotBit
    ) internal {
        emit EntriesQueuedRange(id, startLevel, numLevels, stride, entriesPerLevel);
        uint80 idBits = uint80(id) << OWNER_IDX_SHIFT;
        uint24 lvl = startLevel;
        uint256 owedRoot;
        assembly ("memory-safe") {
            mstore(0, id)
            mstore(32, farFutureOwed.slot)
            owedRoot := keccak256(0, 64)
        }
        bool loaded;
        uint256 cachedSlot;
        uint256 cachedWord;
        for (uint24 i; i < numLevels; ) {
            if (lvl > mintCeiling) {
                uint24 logicalLevel = lvl & 0x3fffff;
                uint256 position = (uint256(logicalLevel) - 1) % 100;
                uint256 slot;
                unchecked { slot = owedRoot + (position >> 3); }
                if (!loaded || slot != cachedSlot) {
                    if (loaded) {
                        assembly ("memory-safe") { sstore(cachedSlot, cachedWord) }
                    }
                    assembly ("memory-safe") { cachedWord := sload(slot) }
                    cachedSlot = slot;
                    loaded = true;
                }
                uint256 offset = (position & 7) << 5;
                uint256 lane;
                // Preserve the production cycle check before using a recycled lane.
                assembly ("memory-safe") {
                    mstore(0, or(add(position, 1), 0x400000))
                    mstore(32, ticketQueue.slot)
                    let occupying := and(shr(32, sload(keccak256(0, 64))), 0xffffff)
                    if iszero(occupying) { occupying := add(position, 1) }
                    if eq(occupying, logicalLevel) {
                        lane := and(shr(offset, cachedWord), 0xffffffff)
                    }
                }
                if (lane & 0x80000000 == 0) {
                    if (rngLockedCached) revert RngLocked();
                    _tqAppend(_tqFarFutureKey(lvl), id);
                    lane = 0;
                }
                // Like the current credit sink, a top-up clears the snap marker.
                uint256 nextLane = 0x80000000
                    | _saturateFarFutureOwed((lane & 0x3fffffff) + uint256(entriesPerLevel));
                cachedWord = (cachedWord & ~(uint256(0xffffffff) << offset)) | (nextLane << offset);
            } else {
                uint24 wk = lvl | writeSlotBit;
                uint80 packed = _entryPacked(wk, id);
                uint32 owed = uint32(packed >> 8);
                uint8 rem = uint8(packed);
                if (packed == 0) {
                    packed = idBits;
                    _tqAppend(wk, id);
                }
                owed = _addOwed(owed, entriesPerLevel, false);
                _setEntryOwed(wk, id,
                    (packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem));
            }
            unchecked {
                lvl += stride;
                ++i;
            }
        }
        if (loaded) {
            assembly ("memory-safe") { sstore(cachedSlot, cachedWord) }
        }
    }

    /// @dev Queues a half-pass award (1 half-pass = 1 entry/level over the span) as
    ///      whole-ticket (4-entry) chunks so every chunk spans all four trait quadrants:
    ///      - base leg: (halfPasses / 4) * 4 entries on every level of the span;
    ///      - remainder 2: one whole ticket every 2nd level (offsets 0, 2, ...);
    ///      - remainder 1: one whole ticket every 4th level (offsets 0, 4, ...);
    ///      - remainder 3: both legs, the every-4th leg offset by +1 (offsets 1, 5, ...)
    ///        so the two remainder legs cover disjoint levels.
    ///      Covered-level counts round up on odd spans (at most one extra whole ticket
    ///      per leg, in the buyer's favor). Total queued entries = halfPasses × span for
    ///      stride-aligned spans (any span divisible by 4, incl. the 100-level claims).
    /// @param id Wallet ID to receive tickets.
    /// @param startLevel First level of the span (inclusive).
    /// @param span Number of levels the award covers.
    /// @param halfPasses Half-pass count (1 half-pass = 1 entry/level equivalent).
    function _queueHalfPassAward(
        uint32 id,
        uint24 startLevel,
        uint24 span,
        uint256 halfPasses
    ) internal {
        // Read the loop-invariant slot-0 fields once for all <=3 legs — none is written by the
        // core body, so this is identical to each leg re-reading them, minus the repeated SLOADs.
        uint24 mintCeiling = _mintCeiling();
        bool rngLockedCached = rngLockedFlag;
        uint24 writeSlotBit = ticketWriteSlot ? TICKET_SLOT_BIT : uint24(0);
        uint32 baseEntries = uint32((halfPasses / 4) * 4);
        if (baseEntries != 0) {
            _queueEntryRangeStridedCore(id, startLevel, span, 1, baseEntries, mintCeiling, rngLockedCached, writeSlotBit);
        }
        uint256 rem = halfPasses % 4;
        if (rem == 0) return;
        if (rem >= 2) {
            _queueEntryRangeStridedCore(id, startLevel, (span + 1) / 2, 2, 4, mintCeiling, rngLockedCached, writeSlotBit);
        }
        if (rem == 1) {
            _queueEntryRangeStridedCore(id, startLevel, (span + 3) / 4, 4, 4, mintCeiling, rngLockedCached, writeSlotBit);
        } else if (rem == 3) {
            _queueEntryRangeStridedCore(id, startLevel + 1, (span + 2) / 4, 4, 4, mintCeiling, rngLockedCached, writeSlotBit);
        }
    }

    // =========================================================================
    // Packed Prize Pool Helpers
    // =========================================================================

    /// @dev Bit offset of the future half inside both packed pool slots.
    uint256 internal constant POOL_FUTURE_SHIFT = 128;

    /// @dev Largest value either pool half holds, and the mask that extracts one.
    ///      uint128 ~= 3.4e38 wei, far above any reachable pool.
    uint256 internal constant POOL_HALF_MAX = type(uint128).max;

    /// @dev Writes both pool halves. Each half owns exactly half the slot, so the write
    ///      is a whole-word overwrite with nothing to preserve.
    function _setPrizePools(uint128 next, uint128 future) internal {
        prizePoolsPacked = (uint256(future) << POOL_FUTURE_SHIFT) | uint256(next);
    }

    function _getPrizePools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolsPacked;
        next = uint128(packed);
        future = uint128(packed >> POOL_FUTURE_SHIFT);
    }

    function _setPendingPools(uint128 next, uint128 future) internal {
        prizePoolPendingPacked =
            (uint256(future) << POOL_FUTURE_SHIFT) |
            uint256(next);
    }

    function _getPendingPools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolPendingPacked;
        next = uint128(packed);
        future = uint128(packed >> POOL_FUTURE_SHIFT);
    }

    /// @dev Add a combined prize contribution to the active accumulator in ONE RMW. The purchase
    ///      path computes each leg's next/future split (ticket and lootbox legs use different
    ///      ratios), sums the post-split totals, and lands both in a single packed slot — the
    ///      pending buffer while the pool is frozen, otherwise the live pools.
    ///
    ///      SATURATES rather than reverting. uint128 (~3.4e38 wei) is far above any reachable value, so
    ///      neither half can reach the ceiling from real value — but the write sits on the
    ///      purchase hot path, and a revert there would brick the game outright rather than
    ///      degrade it. Clamping trades an impossible accounting error for guaranteed
    ///      liveness: past the ceiling the ledger would under-report what is owed, which
    ///      leaves the contract over-collateralised rather than insolvent, and every
    ///      solvency check still reads balance >= obligations.
    function _addPrizeContribution(uint128 nextAdd, uint128 futureAdd) internal {
        if (nextAdd == 0 && futureAdd == 0) return;
        bool frozen = prizePoolFrozen;
        uint256 slot = frozen ? prizePoolPendingPacked : prizePoolsPacked;

        // Masked and shifted operands keep both sums in uint256 — adding a uint128 half
        // to a uint128 addend would evaluate in uint128 and revert exactly where the
        // clamp is meant to catch it — so the clamp is the only ceiling either half
        // needs, and neither can carry into the other.
        uint256 next = (slot & POOL_HALF_MAX) + nextAdd;
        uint256 future = (slot >> POOL_FUTURE_SHIFT) + futureAdd;
        if (next > POOL_HALF_MAX) next = POOL_HALF_MAX;
        if (future > POOL_HALF_MAX) future = POOL_HALF_MAX;

        uint256 packed = (future << POOL_FUTURE_SHIFT) | next;
        if (frozen) {
            prizePoolPendingPacked = packed;
        } else {
            prizePoolsPacked = packed;
        }
    }

    /// @dev Registered-wallet count at and above which only a Game paying entry of at least
    ///      PAID_ADMISSION_MIN_SPEND (ETH equivalent) may create a new wallet ID.
    uint256 internal constant PAID_ADMISSION_WALLETS = 3_000_000_000;
    uint256 internal constant PAID_ADMISSION_MIN_SPEND = 0.04 ether;

    /// @notice Emitted exactly once per wallet ID, when the wallet is registered.
    event WalletRegistered(uint32 indexed id, address indexed owner);

    /// @notice Emitted once per subaccount allocation.
    /// @param ownerId The owning wallet's ID (the smurf's payee).
    /// @param smurfId The smurf account's wallet ID.
    event SmurfCreated(uint32 indexed ownerId, uint32 indexed smurfId);

    /// @dev With createSmurf, the only writer of a wallet's identity. Returns the existing ID or allocates the
    ///      next table position, publishing both directions (the table element and walletIds)
    ///      in the same call. Existing mint history is returned; new registration does not write it.
    ///      Callers register before anything else in the transaction loads `owner`'s mint word.
    ///      `quotedSpend` is the ETH-equivalent total the paying call charges (zero for the
    ///      external hook); it is read only when a new wallet would be admitted at or above
    ///      PAID_ADMISSION_WALLETS registered wallets.
    function _registerWallet(address owner, uint256 quotedSpend) internal returns (uint32 id, uint256 word) {
        uint64 registry = walletIds[owner];
        id = uint32(registry);
        if (id != 0) return (id, mintPacked_[id]);
        if (owner == address(0)) revert E();
        uint256 position = wallets.length;
        if (position > PAID_ADMISSION_WALLETS && quotedSpend < PAID_ADMISSION_MIN_SPEND) revert E();
        if (position > type(uint32).max) revert E();
        id = uint32(position);
        wallets.push(uint160(owner));
        uint32 identity = uint32(registry >> 32);
        walletIds[owner] = (uint64(identity == 0 ? id : identity) << 32) | id;
        // A new account has no mint history; registration does not write a statistics word.
        word = 0;
        emit WalletRegistered(id, owner);
    }

    /// @dev Current default gameplay account; zero before registration or after its sale.
    function _walletIdOf(address owner) internal view returns (uint32) {
        return uint32(walletIds[owner]);
    }

    function _requireWalletId(address owner) internal view returns (uint32 id) {
        id = uint32(walletIds[owner]);
        if (id == 0) revert E();
    }

    /// @dev Storage slot of wallet-table element `id`; callers hold a stored, nonzero ID.
    function _walletSlot(uint32 id) internal pure returns (uint256 slot) {
        assembly ("memory-safe") {
            mstore(0, wallets.slot)
            slot := add(keccak256(0, 32), id)
        }
    }



    /// @dev Raw wallet-table element for a stored, nonzero ID.
    function _walletElement(uint32 id) internal view returns (uint256 element) {
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") { element := sload(slot) }
    }

    /// @dev Account key for a stored, nonzero ID (queue and bucket lanes, deity lanes): no bounds
    ///      check, since only allocated IDs are ever stored.
    function _walletKey(uint32 id) internal view returns (address) {
        return address(uint160(_walletElement(id)));
    }



    /// @dev Payout recipient for a wallet-table element: its own key, or for a smurf account the
    ///      owner's key. Every ETH/stETH/token payout edge that holds an ID resolves through here.
    ///      At most two links: child -> acquired main -> reserved protocol buyer.
    ///      Only creation and liquidation write owner lanes; protocol roots cannot be sold.
    function _payee(uint256 element) internal view returns (address) {
        uint256 owner = (element >> 160) & 0xffffffff;
        if (owner != 0) element = _walletElement(uint32(owner));
        owner = uint32(element >> 160);
        if (owner != 0) element = _walletElement(uint32(owner));
        return address(uint160(element));
    }

    /// @dev Revert `E` unless `id` is an allocated, nonzero wallet ID.
    function _requireAllocated(uint32 id) internal view {
        if (id == 0 || id >= wallets.length) revert E();
    }

    /// @dev Key and payee of the allocated account `id` (reverts `E` otherwise).
    function _accountKeys(uint32 id) internal view returns (address key, address payee) {
        _requireAllocated(id);
        uint256 element = _walletElement(id);
        key = address(uint160(element));
        payee = _payee(element);
    }

    /// @dev Resolve an allocated account's external owner and authorization. Ordinary
    ///      accounts return their address as key; subaccounts have key zero. Ownership comes
    ///      from the table's owner-ID lane; operators are approved for the selected ID only.
    function _account(uint32 id, address caller)
        internal
        view
        returns (address key, address payee, bool authorized)
    {
        _requireAllocated(id);
        uint256 element = _walletElement(id);
        key = address(uint160(element));
        payee = _payee(element);
        authorized = payee == caller || (_acquiredRoot(id, element) == 0 && operatorApprovals[id][caller]);
    }

    /// @dev Resolve the self shorthand without allocating, or authorize an explicit account.
    function _resolveAccountId(uint32 id) internal view returns (uint32) {
        if (id == 0) return _walletIdOf(msg.sender);
        (, , bool authorized) = _account(id, msg.sender);
        if (!authorized) revert NotApproved();
        return id;
    }

    /// @dev Only an unregistered self caller can reach this helper with ID zero.
    function _registerCallerAccount(uint32 id, uint256 spend) internal returns (uint32) {
        if (id != 0) return id;
        (id, ) = _registerWallet(msg.sender, spend);
        return id;
    }

    function _creditAccountId(uint32 id) internal view returns (uint32) {
        if (id == 0) return _requireWalletId(msg.sender);
        _requireAllocated(id);
        return id;
    }



    // =========================================================================
    // Whale-pass half-pass count (wallet-table bits 192..255)
    // =========================================================================

    uint256 private constant HALF_PASS_SHIFT = 192;

    /// @dev Half passes held by a wallet, awaiting claimWhalePass.
    function _halfPassCount(uint32 id) internal view returns (uint256) {
        return _walletElement(id) >> HALF_PASS_SHIFT;
    }

    /// @dev Credit half passes. The count is the element's top field, so a checked add makes an
    ///      overflow revert instead of reaching the account-key or owner bits.
    function _addHalfPasses(uint32 id, uint256 halfPasses) internal {
        // Element 0 must stay empty: an unregistered address claims against it.
        if (id == 0) revert E();
        uint256 slot = _walletSlot(id);
        uint256 element;
        assembly ("memory-safe") { element := sload(slot) }
        element += halfPasses << HALF_PASS_SHIFT;
        assembly ("memory-safe") { sstore(slot, element) }
    }

    /// @dev Read and clear a wallet's half passes, keeping the account key and owner lane.
    function _takeHalfPasses(uint32 id) internal returns (uint256 halfPasses) {
        uint256 slot = _walletSlot(id);
        assembly ("memory-safe") {
            let element := sload(slot)
            halfPasses := shr(HALF_PASS_SHIFT, element)
            if halfPasses { sstore(slot, and(element, sub(shl(HALF_PASS_SHIFT, 1), 1))) }
        }
    }

    // =========================================================================
    // Owed Balance Helpers (shared by the mint and foil drains)
    // =========================================================================

    /// @dev Preserve logical absolute levels while recycling physical queue storage.
    function _ticketQueueStorageKey(uint24 key) internal pure returns (uint24 physical) {
        assembly ("memory-safe") {
            let lvl := and(key, 0x3fffff)
            physical := and(key, 0xc00000)
            if lvl {
                let slot := and(sub(lvl, 1), 1)
                if and(key, 0x400000) { slot := mod(sub(lvl, 1), 100) }
                physical := or(physical, add(slot, 1))
            }
        }
    }

    /// @dev A reused root cannot make an old level appear to have a pending queue.
    function _ticketQueueLength(uint24 key) internal view returns (uint256 length) {
        uint24 physical = _ticketQueueStorageKey(key);
        assembly ("memory-safe") {
            mstore(0, physical)
            mstore(32, ticketQueue.slot)
            let header := sload(keccak256(0, 64))
            let occupying := and(shr(32, header), 0xffffff)
            if iszero(occupying) { occupying := and(physical, 0x7f) }
            if eq(occupying, and(key, 0x3fffff)) { length := and(header, 0xffffffff) }
        }
    }

    /// @dev Bind only an empty queue. A collision must preserve every paid obligation.
    ///      Returns the header the caller's append writes back: the live count under an
    ///      explicit tag for `key`'s level, so the first append also materializes the tag.
    function _bindTicketQueue(uint24 key) internal view returns (uint256[] storage q, uint256 header) {
        uint24 physical = _ticketQueueStorageKey(key);
        assembly ("memory-safe") {
            mstore(0, physical)
            mstore(32, ticketQueue.slot)
            q.slot := keccak256(0, 64)
            header := sload(q.slot)
            let lvl := and(key, 0x3fffff)
            let occupying := and(shr(32, header), 0xffffff)
            if iszero(occupying) { occupying := and(physical, 0x7f) }
            let len := and(header, 0xffffffff)
            if iszero(eq(occupying, lvl)) {
                if len {
                    mstore(0, 0x92bbf6e8)
                    revert(28, 4)
                }
            }
            header := or(len, shl(32, lvl))
        }
    }

    /// @dev Clamp before narrowing so an owed add cannot spill into an adjacent level.
    function _saturateFarFutureOwed(uint256 owed) internal pure returns (uint32) {
        return uint32(owed > 0x3fffffff ? 0x3fffffff : owed);
    }

    /// @dev The one owed-count add: far-future lanes saturate at 2^30-1, normal lanes
    ///      accumulate unchecked, bounded only by economic scale.
    function _addOwed(uint32 owed, uint256 added, bool isFarFuture) internal pure returns (uint32) {
        unchecked {
            return isFarFuture ? _saturateFarFutureOwed(uint256(owed) + added) : owed + uint32(added);
        }
    }

    /// @dev Queue tags authenticate the cycle before reading a reused owner lane.
    function _farFutureLane(uint24 lvl, uint32 id) internal view returns (uint256 lane) {
        assembly ("memory-safe") {
            if lvl {
                let position := mod(sub(lvl, 1), 100)
                mstore(0, or(add(position, 1), 0x400000))
                mstore(32, ticketQueue.slot)
                let occupying := and(shr(32, sload(keccak256(0, 64))), 0xffffff)
                if iszero(occupying) { occupying := add(position, 1) }
                if eq(occupying, lvl) {
                    mstore(0, id)
                    mstore(32, farFutureOwed.slot)
                    lane := and(shr(shl(5, and(position, 7)),
                        sload(add(keccak256(0, 64), shr(3, position)))), 0xffffffff)
                }
            }
        }
    }

    function _entryPacked(uint24 key, uint32 id) internal view returns (uint80 packed) {
        if (key & TICKET_FAR_FUTURE_BIT != 0) {
            uint256 lane = _farFutureLane(key & 0x3fffff, id);
            if (lane & 0x80000000 != 0) {
                return (uint80(id) << OWNER_IDX_SHIFT) | uint80((lane & 0x3fffffff) << 8)
                    | uint80((lane & 0x40000000) << 10);
            }
            return 0;
        }
        assembly ("memory-safe") {
            mstore(0, id)
            mstore(32, ticketPending.slot)
            let word := sload(keccak256(0, 64))
            let parity := and(key, 1)
            let shift := mul(parity, 84)
            if and(key, 0x800000) { shift := add(shift, 42) }
            if eq(and(shr(add(168, mul(parity, 24)), word), 0xffffff), and(key, 0x3fffff)) {
                let lane := and(shr(shift, word), 0x3ffffffffff)
                if and(lane, 0x20000000000) { packed := or(shl(48, id), and(lane, 0x1ffffffffff)) }
            }
        }
    }

    /// @dev Sum both normal cohorts and the authoritative far-future balance.
    function _entriesOwedTotal(uint24 lvl, uint32 id) internal view returns (uint32 total) {
        if (id == 0) return 0;
        uint256 word = ticketPending[id];
        uint256 futureLane = _farFutureLane(lvl, id);
        assembly ("memory-safe") {
            let parity := and(lvl, 1)
            if eq(and(shr(add(168, mul(parity, 24)), word), 0xffffff), lvl) {
                let shift := mul(parity, 84)
                total := add(and(shr(add(shift, 8), word), 0xffffffff),
                    and(shr(add(shift, 50), word), 0xffffffff))
            }
            total := add(total, and(futureLane, 0x3fffffff))
            total := and(total, 0xffffffff)
        }
    }

    /// @dev Reload at writeback and mask only this lane, preserving all other cohorts.
    /// @custom:storage-write farFutureOwed
    function _setEntryOwed(uint24 key, uint32 id, uint80 packed) internal {
        if (key & TICKET_FAR_FUTURE_BIT != 0) {
            uint24 lvl = key & 0x3fffff;
            if (lvl == 0 || uint8(packed) != 0) revert E();
            uint256 lane;
            if (packed != 0) {
                lane = 0x80000000 | _saturateFarFutureOwed(uint32(packed >> 8))
                    | ((uint256(packed) >> 10) & 0x40000000);
            }
            assembly ("memory-safe") {
                let position := mod(sub(lvl, 1), 100)
                let offset := shl(5, and(position, 7))
                mstore(0, id)
                mstore(32, farFutureOwed.slot)
                let target := add(keccak256(0, 64), shr(3, position))
                sstore(target, or(and(sload(target), not(shl(offset, 0xffffffff))), shl(offset, lane)))
            }
            return;
        }
        uint256 oldWord = ticketPending[id];
        uint256 next;
        assembly ("memory-safe") {
            let parity := and(key, 1)
            let shift := mul(parity, 84)
            if and(key, 0x800000) { shift := add(shift, 42) }
            let tagShift := add(168, mul(parity, 24))
            let tagMask := shl(tagShift, 0xffffff)
            let pairMask := shl(mul(parity, 84), sub(shl(84, 1), 1))
            let lvl := and(key, 0x3fffff)
            let matches := eq(and(shr(tagShift, oldWord), 0xffffff), lvl)
            next := oldWord
            if or(matches, packed) {
                if iszero(matches) {
                    if and(oldWord, pairMask) {
                        mstore(0, 0x92bbf6e8)
                        revert(28, 4)
                    }
                }
                next := or(and(next, not(or(shl(shift, 0x3ffffffffff), tagMask))), shl(255, 1))
                if packed { next := or(next, shl(shift, or(and(packed, 0x1ffffffffff), 0x20000000000))) }
                if and(next, pairMask) { next := or(next, shl(tagShift, lvl)) }
            }
        }
        ticketPending[id] = next;
    }

    /// @dev Divide a not-yet-snapped owed balance by 2^s, folding the shifted-out
    ///      fraction into the QTY_SCALE remainder (sub-remainder residue evaporates,
    ///      matching the sub-unit handling of scaled purchases). Marks the value
    ///      snap-done so a resumed drain never divides it again.
    function _snapOwedPacked(uint80 packed, uint8 s) internal pure returns (uint80) {
        uint256 scaled = (uint256(uint32(packed >> 8)) * QTY_SCALE +
            uint8(packed)) >> s;
        return
            (packed & OWNER_IDX_MASK) |
            SNAP_DONE_BIT |
            (uint80(scaled / QTY_SCALE) << 8) |
            uint80(scaled % QTY_SCALE);
    }

    // =========================================================================
    // Packed Trait Buckets
    // =========================================================================

    /// @dev Load the eight owner indices in the packed word containing occurrence `base`.
    function _bucketWordAtUnchecked(uint24 lvl, uint8 trait, uint256 base) internal view returns (uint256 word) {
        uint256 elem = _traitBufferBase(lvl) + trait;
        assembly ("memory-safe") {
            let header := sload(elem)
            switch eq(shr(3, base), shr(3, and(header, 0xffffffff)))
            case 1 { word := shr(32, header) }
            default {
                mstore(0, elem)
                word := sload(add(keccak256(0, 32), shr(3, base)))
            }
        }
    }

    /// @dev Wallet ID in lane `k & 7` of an already loaded bucket word.
    function _bucketIdFromWord(uint256 word, uint256 k) internal pure returns (uint32 id) {
        assembly ("memory-safe") { id := and(shr(shl(5, and(k, 7)), word), 0xffffffff) }
    }

    /// @dev Wallet ID of the deity holding a trait's symbol, or zero. Gold six has no virtual
    ///      deity entry; actual purchased entries remain eligible.
    function _traitDeity(uint8 trait) internal view returns (uint32) {
        return trait == GoldSixLib.TRAIT ? 0 : deityBySymbol[(trait >> 6) * 8 + (trait & 7)];
    }

    /// @dev Virtual deity entry count for a trait bucket of size `len` (zero
    ///      when no deity holds the trait's symbol):
    ///        Gold tier (color == 7): flat 1 virtual entry, except gold Dice 6 (zero).
    ///        Colors 5/6: floor(1% of bucket), minimum 1.
    ///        Colors 0..4: floor(2% of bucket), minimum 2.
    function _deityVirtualCount(
        uint8 trait,
        uint256 len,
        uint32 deity
    ) internal pure returns (uint256 virtualCount) {
        if (deity != 0 && trait != GoldSixLib.TRAIT) {
            uint8 color = (trait >> 3) & 7;
            if (color == 7) {
                virtualCount = 1;
            } else if (color >= 5) {
                virtualCount = len / 100;
                if (virtualCount == 0) virtualCount = 1;
            } else {
                virtualCount = len / 50;
                if (virtualCount < 2) virtualCount = 2;
            }
        }
    }

    /// @dev Wallet ID of occurrence `k` in lvlTraitEntry[lvl][trait]. No bound check: callers
    ///      gate on the length.
    function _bucketIdAtUnchecked(uint24 lvl, uint8 trait, uint256 k) internal view returns (uint32) {
        return _bucketIdFromWord(_bucketWordAtUnchecked(lvl, trait, k), k);
    }


    /// @dev Header: uint32 occurrence count, then up to seven low-first uint32 tail lanes.
    ///      Only complete words reach data storage. The practical per-level bound is below
    ///      2^32 occurrences per trait; reaching it needs over 536 million word writes.
    ///      Returns physical writes classified by the slot value before each store.
    ///      Caller has prepared lvl and provides the nonzero wallet ID.
    function _bucketAppendRun(
        uint256 levelSlot,
        uint8 traitId,
        uint256 ownerIdx,
        uint256 occurrences,
        uint24 lvl
    ) internal returns (uint256 fresh, uint256 dirty) {
        assembly ("memory-safe") {
            let bitmapSlot := add(traitBucketLive.slot, and(lvl, 1))
            let bits := sload(bitmapSlot)
            let bit := shl(traitId, 1)
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            switch iszero(header)
            case 1 { fresh := 1 }
            default { dirty := 1 }
            if iszero(and(bits, bit)) {
                header := 0
                sstore(bitmapSlot, or(bits, bit))
                switch iszero(bits)
                case 1 { fresh := add(fresh, 1) }
                default { dirty := add(dirty, 1) }
            }
            let len := and(header, 0xffffffff)
            let nextLen := add(len, occurrences)
            let fill := and(len, 7)
            let tail := shr(32, header)
            let full := mul(ownerIdx, 0x0000000100000001000000010000000100000001000000010000000100000001)
            mstore(0, elem)
            let w := add(keccak256(0, 32), shr(3, len))
            if fill {
                let room := sub(8, fill)
                let take := room
                if lt(occurrences, take) { take := occurrences }
                tail := or(tail, shl(shl(5, fill), and(full, sub(shl(shl(5, take), 1), 1))))
                occurrences := sub(occurrences, take)
                if eq(take, room) {
                    switch iszero(sload(w))
                    case 1 { fresh := add(fresh, 1) }
                    default { dirty := add(dirty, 1) }
                    sstore(w, tail)
                    w := add(w, 1)
                    tail := 0
                }
            }
            for {} gt(occurrences, 7) {} {
                switch iszero(sload(w))
                case 1 { fresh := add(fresh, 1) }
                default { dirty := add(dirty, 1) }
                sstore(w, full)
                w := add(w, 1)
                occurrences := sub(occurrences, 8)
            }
            if occurrences { tail := and(full, sub(shl(shl(5, occurrences), 1), 1)) }
            sstore(elem, or(nextLen, shl(32, tail)))
        }
    }

    /// @dev Append up to eight packed low-first uint32 wallet-ID lanes. Persist the unfinished
    ///      word in the header and write at most one complete data word. Slot-value write charges.
    function _bucketAppendLanes(
        uint256 levelSlot,
        uint8 traitId,
        uint256 lanesWord,
        uint256 count,
        uint24 lvl
    ) internal returns (uint256 fresh, uint256 dirty) {
        assembly ("memory-safe") {
            let bitmapSlot := add(traitBucketLive.slot, and(lvl, 1))
            let bits := sload(bitmapSlot)
            let bit := shl(traitId, 1)
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            switch iszero(header)
            case 1 { fresh := 1 }
            default { dirty := 1 }
            if iszero(and(bits, bit)) {
                header := 0
                sstore(bitmapSlot, or(bits, bit))
                switch iszero(bits)
                case 1 { fresh := add(fresh, 1) }
                default { dirty := add(dirty, 1) }
            }
            let len := and(header, 0xffffffff)
            let fill := and(len, 7)
            let tail := shr(32, header)
            tail := or(tail, shl(shl(5, fill), lanesWord))
            if gt(add(fill, count), 7) {
                mstore(0, elem)
                let w := add(keccak256(0, 32), shr(3, len))
                switch iszero(sload(w))
                case 1 { fresh := add(fresh, 1) }
                default { dirty := add(dirty, 1) }
                sstore(w, tail)
                tail := shr(shl(5, sub(8, fill)), lanesWord)
            }
            sstore(elem, or(add(len, count), shl(32, tail)))
        }
    }

    // =========================================================================
    // Ticket Queue Key Encoding
    // =========================================================================

    /// @dev Append a nonzero wallet ID. The length counts lanes, like a
    ///      trait bucket. A mask replaces stale lanes after release or swap-pop; lane zero
    ///      starts a whole word so the fresh tail has no inherited upper lanes.
    function _tqAppend(uint24 key, uint32 ownerPos) internal {
        if (ownerPos == 0) revert E();
        (uint256[] storage q, uint256 header) = _bindTicketQueue(key);
        assembly ("memory-safe") {
            let len := and(header, 0xffffffff)
            mstore(0x00, q.slot)
            let slot := add(keccak256(0x00, 0x20), shr(3, len))
            let shift := shl(5, and(len, 7))
            let value := and(ownerPos, 0xffffffff)
            if shift {
                value := or(and(sload(slot), not(shl(shift, 0xffffffff))), shl(shift, value))
            }
            sstore(slot, value)
            sstore(q.slot, add(header, 1))
        }
    }

    /// @dev Append up to eight nonzero wallet IDs packed low-lane first. Overwrite
    ///      stale tail lanes after queue reuse; preserve only the live prefix. Used by
    ///      deity renewal to update the queue length once per packed group.
    function _tqAppendLanes(uint24 key, uint256 lanes, uint256 count) internal {
        (uint256[] storage q, uint256 header) = _bindTicketQueue(key);
        assembly ("memory-safe") {
            let len := and(header, 0xffffffff)
            mstore(0, q.slot)
            let slot := add(keccak256(0, 32), shr(3, len))
            let fill := and(len, 7)
            let shift := shl(5, fill)
            let prefix := and(sload(slot), sub(shl(shift, 1), 1))
            sstore(slot, or(prefix, shl(shift, lanes)))
            let room := sub(8, fill)
            if gt(count, room) { sstore(add(slot, 1), shr(shl(5, room), lanes)) }
            sstore(q.slot, add(header, count))
        }
    }

    /// @dev Read the packed queue word holding logical entry index `index` (eight lanes per word).
    function _tqWordAt(uint256[] storage q, uint256 index) internal view returns (uint256 word) {
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            word := sload(add(keccak256(0x00, 0x20), shr(3, index)))
        }
    }

    /// @dev Read one full-width uint32 lane. Callers gate k on the logical queue length.
    function _tqPositionAt(uint256[] storage q, uint256 k) internal view returns (uint32 pos) {
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            let word := sload(add(keccak256(0x00, 0x20), shr(3, k)))
            pos := and(shr(shl(5, and(k, 7)), word), 0xffffffff)
        }
    }

    /// @dev Remove a verified queue index by replacing it with the last lane. Clear only
    ///      that last lane, preserving neighbours even when both positions share a word.
    function _tqSwapPop(uint256[] storage q, uint256 k) internal {
        assembly ("memory-safe") {
            let header := sload(q.slot)
            let last := sub(and(header, 0xffffffff), 1)
            mstore(0x00, q.slot)
            let base := keccak256(0x00, 0x20)
            let lastSlot := add(base, shr(3, last))
            let lastShift := shl(5, and(last, 7))
            let lastWord := sload(lastSlot)
            let pos := and(shr(lastShift, lastWord), 0xffffffff)
            sstore(lastSlot, and(lastWord, not(shl(lastShift, 0xffffffff))))
            if iszero(eq(k, last)) {
                let slot := add(base, shr(3, k))
                let shift := shl(5, and(k, 7))
                sstore(slot, or(and(sload(slot), not(shl(shift, 0xffffffff))), shl(shift, pos)))
            }
            sstore(q.slot, sub(header, 1))
        }
    }

    /// @dev Compute the ticket queue key for the write slot.
    ///      Slot 0 uses raw level, slot 1 sets bit 23.
    function _tqWriteKey(uint24 lvl) internal view returns (uint24) {
        return ticketWriteSlot ? lvl | TICKET_SLOT_BIT : lvl;
    }

    /// @dev Compute the ticket queue key for the read slot (opposite of write).
    function _tqReadKey(uint24 lvl) internal view returns (uint24) {
        return !ticketWriteSlot ? lvl | TICKET_SLOT_BIT : lvl;
    }

    /// @dev Compute the ticket queue key for the far-future key space.
    ///      Always sets bit 22, independent of ticketWriteSlot.
    ///      Far-future tickets are not double-buffered; they persist until
    ///      minted as a latched last purchase day's frozen pool (TicketModule runTicketWork).
    function _tqFarFutureKey(uint24 lvl) internal pure returns (uint24) {
        return lvl | TICKET_FAR_FUTURE_BIT;
    }

    /// @dev Release a drained ticket queue in O(1): clear only the header's count, keeping
    ///      the level tag. Element slots stay behind; they are unreachable because every
    ///      read is length-gated and an append overwrites lanes from index 0 upward. A
    ///      stale release (another level now occupies the root) changes nothing.
    function _releaseTicketQueue(uint24 rk) internal {
        uint24 physical = _ticketQueueStorageKey(rk);
        bool matched;
        assembly ("memory-safe") {
            mstore(0, physical)
            mstore(32, ticketQueue.slot)
            let slot := keccak256(0, 64)
            let header := sload(slot)
            let occupying := and(shr(32, header), 0xffffff)
            if iszero(occupying) { occupying := and(physical, 0x7f) }
            if eq(occupying, and(rk, 0x3fffff)) {
                matched := 1
                if and(header, 0xffffffff) { sstore(slot, and(header, not(0xffffffff))) }
            }
        }
        if (!matched) return;
        if (ticketSeats != 0) ticketSeats = 0;
        if (ticketSoloOffset != 0) ticketSoloOffset = 0;
    }

    // =========================================================================
    // Single-Component Prize Pool Accessors
    // =========================================================================

    /// @dev Returns the next pool component.
    function _getNextPrizePool() internal view returns (uint256) {
        (uint128 next, ) = _getPrizePools();
        return uint256(next);
    }

    /// @dev Returns the future pool component.
    function _getFuturePrizePool() internal view returns (uint256) {
        (, uint128 future) = _getPrizePools();
        return uint256(future);
    }

    /// @dev Sets only the future pool component.
    function _setFuturePrizePool(uint256 val) internal {
        (uint128 next, ) = _getPrizePools();
        _setPrizePools(next, uint128(val));
    }

    /// @dev Century growth curve: an x00 level's target must reach a multiple of the
    ///      previous century's achieved pool — 2x by default, tapering as the game gets
    ///      huge (1.5x above 500k ETH, 1.3x above 1M ETH) so late centuries stay
    ///      reachable while still forcing real growth.
    uint256 internal constant CENTURY_FLOOR_BPS = 20_000;
    uint256 internal constant CENTURY_FLOOR_MID_BPS = 15_000;
    uint256 internal constant CENTURY_FLOOR_TOP_BPS = 13_000;
    uint256 internal constant CENTURY_FLOOR_MID_THRESHOLD = 500_000 ether;
    uint256 internal constant CENTURY_FLOOR_TOP_THRESHOLD = 1_000_000 ether;

    /// @dev Effective next-pool ratchet target for a purchase level: the previous
    ///      level's recorded pool, raised at century levels (x00) to at least the
    ///      curved multiple of the previous century's achieved pool — the newest entry
    ///      of centuryPrizePools. Every gate compares nextPrizePool strictly greater
    ///      than this target. The history is empty until the first century completes,
    ///      and a zero snapshot imposes no floor, so level 100 runs on the plain ratchet.
    function _prizePoolTarget(
        uint24 purchaseLvl
    ) internal view returns (uint256 target) {
        target = levelPrizePool[purchaseLvl - 1];
        if (purchaseLvl % 100 == 0) {
            uint256 completed = centuryPrizePools.length;
            uint256 snap = completed == 0
                ? 0
                : uint256(centuryPrizePools[completed - 1]);
            uint256 multBps = snap > CENTURY_FLOOR_TOP_THRESHOLD
                ? CENTURY_FLOOR_TOP_BPS
                : snap > CENTURY_FLOOR_MID_THRESHOLD
                    ? CENTURY_FLOOR_MID_BPS
                    : CENTURY_FLOOR_BPS;
            uint256 centuryFloor = (snap * multBps) / 10_000;
            if (centuryFloor > target) target = centuryFloor;
        }
    }

    // =========================================================================
    // Current Prize Pool Helpers
    // =========================================================================

    /// @dev Returns the current prize pool value as uint256.
    ///      Reads the uint128 packed variable and widens to uint256.
    function _getCurrentPrizePool() internal view returns (uint256) {
        return uint256(currentPrizePool);
    }

    /// @dev Sets the current prize pool value.
    ///      Narrows from uint256 to uint128. Safe because currentPrizePool
    ///      can never exceed total ETH supply (~1.2e26 wei << uint128 max ~3.4e38 wei).
    function _setCurrentPrizePool(uint256 val) internal {
        currentPrizePool = uint128(val);
    }

    /// @dev Canonical shortfall settle: cover `shortfall` wei from the buyer's own balances,
    ///      claimable first (only when `allowClaimable`) then prepaid afking. Tier 1 draws
    ///      claimable down to the STRICT 1-wei sentinel; tier 2 drains afking toward 0 (no
    ///      sentinel). The two tiers' draws pair a single aggregate `claimablePool` debit so
    ///      the solvency total stays exact, and an afking draw emits AfkingSpent. Reverts E()
    ///      when the two tiers together cannot cover the shortfall. Single sink so the sentinel
    ///      + the aggregate debit cannot drift across the ETH-in paths that accept claimable/
    ///      afking shortfall.
    /// @param id Wallet whose claimable/afking balances cover the shortfall.
    /// @param shortfall Wei still owed after the buyer's direct payment.
    /// @param allowClaimable True to draw claimable balance first; false skips tier 1 entirely.
    /// @return claimableUsed Wei drawn from claimable. @return afkingUsed Wei drawn from afking.
    function _settleShortfall(uint32 id, uint256 shortfall, bool allowClaimable)
        internal
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        (claimableUsed, afkingUsed) = _settleShortfallNoPool(
            id,
            shortfall,
            allowClaimable
        );
        // One claimablePool RMW for both tiers — linear aggregate, same underflow domain as
        // the sequential per-tier debits; the per-player balance debits stay per-tier.
        uint256 poolDraw = claimableUsed + afkingUsed;
        if (poolDraw != 0) claimablePool -= uint128(poolDraw);
    }

    /// @dev Identical to _settleShortfall but WITHOUT the trailing claimablePool decrement, so a
    ///      combined ticket+lootbox purchase can fold both legs' pool draws into one RMW. The
    ///      per-player claimable/afking debits and the AfkingSpent emit still run here; the caller
    ///      MUST apply `claimablePool -= (claimableUsed + afkingUsed)` for the returned draw.
    function _settleShortfallNoPool(uint32 id, uint256 shortfall, bool allowClaimable)
        internal
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        if (shortfall == 0) return (0, 0);
        // Single packed load; both halves debited in one combined store below. No external call
        // in this body, so the cache cannot go stale between the reads and the write.
        uint256 packed = balancesPacked[id];
        if (allowClaimable) {
            uint256 claimable = uint128(packed);
            if (claimable > 1) {
                uint256 available = claimable - 1; // preserve the 1-wei sentinel
                claimableUsed = shortfall < available ? shortfall : available;
                if (claimableUsed != 0) {
                    // _debitClaimable's guard is dead here: claimableUsed <= claimable-1 < low half.
                    emit ClaimableSpent(id, claimableUsed, claimable - claimableUsed, MintPaymentKind.Internal, claimableUsed);
                }
            }
        }
        uint256 remaining = shortfall - claimableUsed;
        if (remaining != 0) {
            if ((packed >> 128) < remaining) revert Insolvent();
            afkingUsed = remaining;
            emit AfkingSpent(id, afkingUsed);
        }
        // One combined store == sequential _debitClaimable + _debitAfking: claimableUsed sits in
        // the low half (< it, no borrow) and afkingUsed in the high half (guarded >= above), so
        // neither borrows across halves. At least one is non-zero past the early return.
        if (claimableUsed != 0 || afkingUsed != 0) {
            balancesPacked[id] = packed - claimableUsed - (afkingUsed << 128);
        }
    }

    // =========================================================================
    // Balance accessors — claimable / afking, the canonical readers/writers of the
    // shared per-wallet slot. claimableWinnings and afkingFunding are folded into
    // one word per wallet ID; the few direct packed operations (shortfall settlement,
    // combined debits, the claim paths) reproduce this same layout. claimablePool
    // pairing is kept at the call sites (the solvency total is maintained in
    // tandem there).
    // =========================================================================

    /// @dev A wallet's claimable winnings balance (low 128 bits of the packed slot).
    function _claimableOf(uint32 id) internal view returns (uint256) {
        return uint128(balancesPacked[id]);
    }

    /// @dev A wallet's prepaid afking balance (high 128 bits of the packed slot).
    function _afkingOf(uint32 id) internal view returns (uint256) {
        return balancesPacked[id] >> 128;
    }

    /// @dev Credit claimable (the low half) without a log: the caller's own event names the
    ///      wallet and amount. A full-word add is safe: per-wallet ETH <= total supply
    ///      (~1.2e26 wei << 2^128), so claimable + amount never carries into the afking half.
    function _creditClaimable(uint32 id, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (id == 0) revert E();
        balancesPacked[id] += weiAmount;
    }

    /// @dev Credit claimable at a site that has no event of its own naming the wallet and amount.
    function _creditClaimableLogged(uint32 id, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (id == 0) revert E();
        balancesPacked[id] += weiAmount;
        emit PlayerCredited(id, weiAmount);
    }

    /// @dev Debit claimable (the low half). Guard low >= amount so the subtraction never borrows
    ///      from the afking half — a low-half borrow would be invisible to 0.8's full-word check.
    function _debitClaimable(uint32 id, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (uint128(balancesPacked[id]) < weiAmount) revert Insolvent();
        balancesPacked[id] -= weiAmount;
    }

    /// @dev Debit afking (the high half). Stands alone, unlike the credit side: the afking
    ///      delivery debits the wallet here and applies its own claimablePool move for the
    ///      combined afking + claimable draw in the same call, so the pool pairing lives at
    ///      that site rather than in this primitive.
    ///      The full-word subtraction is naturally fail-loud: if afking < amount the whole word
    ///      underflows and 0.8 reverts (no silent low-half borrow).
    function _debitAfking(uint32 id, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        balancesPacked[id] -= weiAmount << 128;
    }

    /// @dev Debit claimable (low half) and afking (high half) in ONE load + store. Each half is
    ///      guarded explicitly BEFORE the combined subtraction: a low-half borrow is invisible to
    ///      0.8's full-word check, and an oversized afking amount would silently truncate in the
    ///      unchecked-by-construction `<< 128` — the guards close both. Reverts match the
    ///      sequential _debitClaimable + _debitAfking exactly.
    function _debitClaimableAndAfking(
        uint32 id,
        uint256 claimableAmount,
        uint256 afkingAmount
    ) internal {
        uint256 packed = balancesPacked[id];
        if (uint128(packed) < claimableAmount) revert Insolvent();
        if ((packed >> 128) < afkingAmount) revert Insolvent();
        balancesPacked[id] = packed - claimableAmount - (afkingAmount << 128);
    }

    /// @notice Emitted when ETH is credited to a wallet's prepaid afking balance.
    event AfkingFunded(uint32 indexed walletId, uint256 amount);

    /// @dev Credit excess/stray ETH to a wallet's withdrawable prepaid afking balance,
    ///      preserving the solvency identity (claimablePool tracks the afking half). Used to
    ///      absorb purchase overpay and bare sends instead of reverting, stranding, or routing
    ///      to the prize pool — the ETH is already held by the contract, so this just records
    ///      the liability. Withdrawable via withdrawAfkingFunding (pre final sweep).
    ///
    ///      This is the ONLY afking credit: the per-wallet half, the claimablePool half and the
    ///      log move together or not at all. No bare credit primitive exists — an unpaired
    ///      credit raises obligations without the pool backing them (the SOLVENCY-01 break) and
    ///      touches no identifier the pool-write gate tracks. The debit twin stands alone only
    ///      because the afking delivery pairs its pool debit itself (one combined afking +
    ///      claimable RMW per delivery); credit always pairs in place here.
    ///
    ///      The full-word add is safe: afking + amount <= 2*supply << 2^128 (no overflow), and
    ///      amount << 128 leaves the claimable low half untouched.
    function _creditAfkingValue(uint32 id, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        if (id == 0) revert E();
        balancesPacked[id] += weiAmount << 128;
        claimablePool += uint128(weiAmount);
        emit AfkingFunded(id, weiAmount);
    }

    // =========================================================================
    // Loot Box State
    // =========================================================================

    // Box queue entry (`boxQueue`), one complete word per purchase, LSB -> MSB:
    //   [0:32]     wallet ID       nonzero beneficiary
    //   [32:56]    level           purchase level; prices the preset tiers
    //   [56:71]    score           post-action activity score, clamped to the effective cap
    //   [71:85]    boostBps        boon uplift as a fraction of this purchase's spend
    //   [85:99]    evBps           EV-cap-eligible fraction drawn at purchase
    //   [99]       distress        bought in distress mode
    //   [100:128]  small/med/large/custom counts, 7 bits each, summing to at most 100
    //   [128:184]  size            custom or cover box size in gwei
    //   [184]      cover           one system-granted cover box of `size`; no counts
    //   [185:251]  presaleAmount   exact applied presale wei; zero means no presale leg
    //   [251:254]  presaleTier     DGNRS tier frozen from the purchase's starting sold amount
    //   [254]      presaleClosing  this purchase closed the presale
    //   [255]      zero
    uint256 internal constant LB_ID_MASK = 0xFFFFFFFF;
    uint256 internal constant LB_LEVEL_SHIFT = 32;
    uint256 internal constant LB_LEVEL_MASK = 0xFFFFFF;
    uint256 internal constant LB_SCORE_SHIFT = 56;
    uint256 internal constant LB_SCORE_MASK = 0x7FFF;
    uint256 internal constant LB_BOOST_SHIFT = 71;
    uint256 internal constant LB_EV_SHIFT = 85;
    uint256 internal constant LB_BPS_MASK = 0x3FFF;
    uint256 internal constant LB_DISTRESS = uint256(1) << 99;
    uint256 internal constant LB_SMALL_SHIFT = 100;
    uint256 internal constant LB_MED_SHIFT = 107;
    uint256 internal constant LB_LARGE_SHIFT = 114;
    uint256 internal constant LB_CUSTOM_COUNT_SHIFT = 121;
    uint256 internal constant LB_COUNT_MASK = 0x7F;
    uint256 internal constant LB_SIZE_SHIFT = 128;
    uint256 internal constant LB_SIZE_MASK = 0xFFFFFFFFFFFFFF;                    // 56 bits
    uint256 internal constant LB_COVER = uint256(1) << 184;
    uint256 internal constant LB_PRESALE_SHIFT = 185;
    uint256 internal constant LB_PRESALE_MASK = 0x3FFFFFFFFFFFFFFFF;              // 66 bits
    uint256 internal constant LB_TIER_SHIFT = 251;
    uint256 internal constant LB_CLOSING = uint256(1) << 254;

    /// @dev Custom and cover sizes are whole gwei; the remainder of a system grant below one
    ///      gwei per box is reward-side only, the pool split banks the exact wei.
    uint256 internal constant LB_SIZE_UNIT = 1 gwei;

    /// @dev Preset multipliers against the entry's level ticket price.
    uint256 internal constant LB_MED_MULTIPLE = 5;
    uint256 internal constant LB_LARGE_MULTIPLE = 25;

    /// @dev Boxes one purchase may hold. Sized so a maximum entry — every box rolled, plus one
    ///      recirculated box per ETH spin — resolves inside a block alongside the afking leg
    ///      that shares the `mineFlip()` transaction. Not a spend limit: a player wanting more
    ///      exposure buys a larger custom, or another entry.
    uint256 internal constant MAX_BOXES_PER_ORDER = 100;

    /// @dev Minimum custom box. Presets clear it structurally: the cheapest ticket price is
    ///      0.01 ETH and a small is one of those.
    uint256 internal constant BOX_CUSTOM_MIN = 0.01 ether;

    // Purchase input (`boxOrder`): [small:8][med:8][large:8][customCount:8][customSize:56 gwei].
    // Every bit at or above 88 must be zero; zero means no ordinary leg.
    uint256 internal constant BO_MED_SHIFT = 8;
    uint256 internal constant BO_LARGE_SHIFT = 16;
    uint256 internal constant BO_CUSTOM_COUNT_SHIFT = 24;
    uint256 internal constant BO_SIZE_SHIFT = 32;
    uint256 internal constant BO_COUNT_MASK = 0xFF;

    /// @dev Validate one purchase's `boxOrder` input as wide integers and price it at `lvl`.
    ///      `lanes` holds the counts, size and level already positioned for the entry word.
    /// @custom:reverts E On a nonzero bit at or above 88, an empty order, more than
    ///         MAX_BOXES_PER_ORDER boxes, a custom below BOX_CUSTOM_MIN, or a size without customs.
    function _decodeBoxOrder(uint256 boxOrder, uint24 lvl) internal pure returns (uint256 lanes, uint256 cost) {
        uint256 small = boxOrder & BO_COUNT_MASK;
        uint256 med = (boxOrder >> BO_MED_SHIFT) & BO_COUNT_MASK;
        uint256 large = (boxOrder >> BO_LARGE_SHIFT) & BO_COUNT_MASK;
        uint256 custom = (boxOrder >> BO_CUSTOM_COUNT_SHIFT) & BO_COUNT_MASK;
        uint256 size = boxOrder >> BO_SIZE_SHIFT;
        uint256 boxes = small + med + large + custom;
        if (
            size > LB_SIZE_MASK || boxes == 0 || boxes > MAX_BOXES_PER_ORDER
                || (custom == 0 ? size != 0 : size * LB_SIZE_UNIT < BOX_CUSTOM_MIN)
        ) revert E();
        unchecked {
            cost = (small + LB_MED_MULTIPLE * med + LB_LARGE_MULTIPLE * large) * PriceLookupLib.priceForLevel(lvl)
                + custom * size * LB_SIZE_UNIT;
        }
        lanes = (uint256(lvl) << LB_LEVEL_SHIFT) | (small << LB_SMALL_SHIFT) | (med << LB_MED_SHIFT)
            | (large << LB_LARGE_SHIFT) | (custom << LB_CUSTOM_COUNT_SHIFT) | (size << LB_SIZE_SHIFT);
    }

    /// @dev Boxes an entry resolves: the four bought counts, or its one cover box.
    function _boxEntryCount(uint256 word) internal pure returns (uint256) {
        unchecked {
            return ((word >> LB_SMALL_SHIFT) & LB_COUNT_MASK) + ((word >> LB_MED_SHIFT) & LB_COUNT_MASK)
                + ((word >> LB_LARGE_SHIFT) & LB_COUNT_MASK) + ((word >> LB_CUSTOM_COUNT_SHIFT) & LB_COUNT_MASK)
                + ((word >> 184) & 1);
        }
    }

    /// @dev Append a complete entry to the write buffer at position = its write count. The
    ///      count and `pendingWei` (the ordinary leg's RNG-pending ETH) commit in one
    ///      lootboxRngPacked write. Returns the buffer and position the entry occupies.
    function _appendBoxEntry(uint256 word, uint256 pendingWei) internal returns (uint48 buffer, uint32 position) {
        uint256 lr = lootboxRngPacked;
        position = uint32(lr >> LR_BOX_COUNT_SHIFT);
        uint256 pending = ((lr >> LR_PENDING_ETH_SHIFT) + pendingWei / LR_ETH_SCALE) & LR_PENDING_ETH_MASK;
        lootboxRngPacked = (lr & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT))
            + (pending << LR_PENDING_ETH_SHIFT) + (uint256(1) << LR_BOX_COUNT_SHIFT);
        buffer = _rngWriteBuffer();
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            sstore(add(keccak256(0x00, 0x20), position), word)
        }
    }

    /// @dev Entry `position` of `buffer`. Callers bound `position` by that buffer's count.
    function _boxEntryAt(uint48 buffer, uint256 position) internal view returns (uint256 word) {
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            word := sload(add(keccak256(0x00, 0x20), position))
        }
    }

    /// @dev Presale DGNRS tier of a purchase that starts at `soldBefore` cumulative box ETH:
    ///      [0,10) [10,20) [20,30) [30,40) [40,50) ETH map to tiers 0..4. A purchase crossing a
    ///      boundary keeps its starting tier. Settlement prices the tier, never the amount.
    function _presaleTier(uint256 soldBefore) internal pure returns (uint256 tier) {
        tier = soldBefore / PRESALE_TIER_WIDTH;
        if (tier > 4) tier = 4;
    }

    /// @dev Cumulative box-ETH width of each presale DGNRS tier.
    uint256 internal constant PRESALE_TIER_WIDTH = 10 ether;

    uint8 internal constant JACKPOT_DAYS = 3;

    /// @dev The selected schedule. A pending bonus alone does not select turbo.
    function _jackpotDays() internal view returns (uint8) {
        return (jackpotFlags & JACKPOT_TURBO) != 0 ? 1 : JACKPOT_DAYS;
    }

    /// @dev True when the next draw ends this phase. Shared by routing, quests and payouts.
    function _isFinalJackpotDay(uint8 counter, uint8 flags) internal pure returns (bool) {
        return (flags & JACKPOT_TURBO) != 0 || counter >= JACKPOT_DAYS - 1;
    }

    /// @dev The level a ticket bought RIGHT NOW routes to — the single source of truth for the
    ///      purchase quote/charge, the ticket + foil delivery, participation/streak recording, and
    ///      every buy-now price view, so they can never diverge. Jackpot phase → current level;
    ///      purchase phase → next. Once the level's jackpots end this level seals no further daily
    ///      draw, so buys route to level + 1 — quoting the old level would strand the buyer's overpay
    ///      or misprice tickets in a level that has ended. Two states mark that sealed window: the
    ///      final jackpot day's RNG request (rngLocked, jackpot counter about to reach the cap), and
    ///      the span after _endPhase runs (phaseTransitionActive, jackpotCounter already zeroed, level
    ///      not yet incremented) while the transition drains. (Salvage/settlement callers are
    ///      rngLock-gated, so this branch is a no-op for them.)
    function _activeTicketLevel() internal view returns (uint24) {
        if (!jackpotPhaseFlag) return level + 1;
        // Transition underway: _endPhase set phaseTransitionActive and zeroed jackpotCounter, so the
        // counter test below can no longer key off the sealed level. phaseTransitionActive is the
        // standalone signal that this level's draws have ended, so buys route to the next level.
        if (phaseTransitionActive) return level + 1;
        if (rngLockedFlag && _isFinalJackpotDay(jackpotCounter, jackpotFlags)) return level + 1;
        return level;
    }

    // =========================================================================
    // Coin-Presale-Box State
    // =========================================================================

    /// @dev Cumulative ETH spent on coin-presale boxes. Read+written per box buy
    ///      during the presale to enforce the 50-ETH cap, freeze each purchase's DGNRS tier
    ///      and detect the closing purchase. Never read after the presaleOver latch.
    uint96 internal presaleBoxEthSold;

    /// @dev Spendable presale-box credit accrued per wallet from ETH buys while
    ///      the presale is open (presaleBoxCredit += 0.25 * purchaseEth). Consumed
    ///      1:1 when a box is bought.
    mapping(uint32 => uint256) internal presaleBoxCredit;

    // =========================================================================
    // Presale State
    // =========================================================================

    /// @dev Cumulative coin-presale-box ETH cap. The box buy crossing this latches
    ///      presaleOver.
    uint256 internal constant PRESALE_BOX_ETH_CAP = 50 ether;

    // =========================================================================
    // Game Over State (packed: 3 variables in 64/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits  0:47]  gameOverTime              uint48   Timestamp when gameover triggered (0 = active)
    //   [bits 48:55]  gameOverFinalJackpotPaid   uint8   1 = final jackpot paid
    //   [bits 56:63]  finalSwept                 uint8   1 = 30-day sweep executed

    /// @dev Packed game over state. See layout comment above.
    uint256 internal gameOverStatePacked;

    // ---- gameOverState shifts and masks ----
    uint256 internal constant GO_TIME_SHIFT = 0;
    uint256 internal constant GO_TIME_MASK = 0xFFFFFFFFFFFF;     // 48 bits
    uint256 internal constant GO_JACKPOT_PAID_SHIFT = 48;
    uint256 internal constant GO_JACKPOT_PAID_MASK = 0xFF;       // 8 bits
    uint256 internal constant GO_SWEPT_SHIFT = 56;
    uint256 internal constant GO_SWEPT_MASK = 0xFF;              // 8 bits

    /// @dev Read a field from the packed game over state.
    function _goRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (gameOverStatePacked >> shift) & mask;
    }

    /// @dev Write a field to the packed game over state.
    function _goWrite(uint256 shift, uint256 mask, uint256 value) internal {
        gameOverStatePacked = (gameOverStatePacked & ~(mask << shift)) | ((value & mask) << shift);
    }

    // =========================================================================
    // Degenerette Bet Queue
    // =========================================================================

    /// @dev Degenerette bets per physical RNG buffer, two 128-bit lanes per word in placement order.
    ///      A bet's id is its position + 1. Placement appends only to the write buffer; the
    ///      ordered miner chain resolves the read buffer after its box entries. The cursor authenticates
    ///      the resolved prefix. Manually addressed like `boxQueue`: bet `p` sits at
    ///      `keccak256(degeneretteQueue[buffer].slot) + (p >> 1)`, the write count lives in
    ///      lootboxRngPacked and the read length in `degeneretteReadCount`. Never use Solidity
    ///      length, push, pop or indexing on this mapping.
    ///      Compact layout used by storage, resolution, events and views (lane p & 1):
    ///      - [0..31]    owner wallet ID
    ///      - [32..36]   chosen hero symbol (0..23; hero quadrant = symbol >> 3; Dice excluded)
    ///      - [37..41]   spin count (1..25)
    ///      - [42]       currency (0 = ETH, 1 = FLIP)
    ///      - [43]       record flag: a biggest-spin record bounty waits in degeneretteRecordBounty
    ///      - [44..59]   activity score in whole points
    ///      - [60..123]  stake per spin in currency units (ETH: gwei, FLIP: whole FLIP)
    ///      - [124..127] reserved (always zero)
    mapping(uint48 => uint256[]) internal degeneretteQueue;

    // =========================================================================
    // Operator Approvals
    // =========================================================================

    /// @dev account wallet ID => operator => approved (game-wide delegated control).
    mapping(uint32 => mapping(address => bool)) internal operatorApprovals;

    // =========================================================================
    // Affiliate DGNRS Claims
    // =========================================================================

    /// @dev Per-level prize pool snapshot used for affiliate DGNRS weighting.
    mapping(uint24 => uint256) internal levelPrizePool;

    /// @dev One reusable claim word per wallet. Bits 0..24 and 25..49 hold
    ///      bingo level+1 stamps for even/odd ticket buffers (zero = never claimed).
    ///      Bits 50..73 hold the affiliate claim level (level zero is not claimable).
    ///      A bingo stamp is overwritten only after that parity's old ticket level retires.
    mapping(uint32 => uint256) internal playerClaimWord;

    function _bingoClaimed(uint24 lvl, uint32 id) internal view returns (bool) {
        return ((playerClaimWord[id] >> ((lvl & 1) * 25)) & 0x1ffffff) == uint256(lvl) + 1;
    }

    function _markBingoClaimed(uint24 lvl, uint32 id) internal {
        uint256 shift = (lvl & 1) * 25;
        playerClaimWord[id] = (playerClaimWord[id] & ~(uint256(0x1ffffff) << shift))
            | ((uint256(lvl) + 1) << shift);
    }

    function _affiliateDgnrsClaimed(uint24 lvl, uint32 id) internal view returns (bool) {
        return uint24(playerClaimWord[id] >> 50) == lvl;
    }

    function _markAffiliateDgnrsClaimed(uint24 lvl, uint32 id) internal {
        playerClaimWord[id] = (playerClaimWord[id] & ~(uint256(type(uint24).max) << 50))
            | (uint256(lvl) << 50);
    }

    /// @dev Segregated DGNRS allocation + cumulative claimed per level, packed into one
    ///      slot: bits [0:128) = allocation (2.5% of affiliate pool, snapshot at transition),
    ///      bits [128:256) = cumulative claimed. Both are DGNRS base units, bounded by the
    ///      sDGNRS supply (~1e24) << uint128 (3.4e38). Claims draw against the fixed
    ///      allocation, not the live pool, eliminating first-mover advantage.
    mapping(uint24 => uint256) internal levelDgnrsPacked;

    /// @dev Unpack a level's (allocation, claimed) from the packed slot.
    function _getLevelDgnrs(uint24 lvl)
        internal
        view
        returns (uint256 allocation, uint256 claimed)
    {
        uint256 w = levelDgnrsPacked[lvl];
        allocation = uint128(w);
        claimed = w >> 128;
    }

    /// @dev Set a level's allocation half, preserving the claimed half.
    function _setLevelDgnrsAllocation(uint24 lvl, uint256 allocation) internal {
        uint256 w = levelDgnrsPacked[lvl];
        levelDgnrsPacked[lvl] =
            (w & (uint256(type(uint128).max) << 128)) |
            uint128(allocation);
    }

    /// @dev Add to a level's claimed half, preserving the allocation half. claimed is
    ///      monotone toward allocation (<= uint128), so the high half never overflows.
    function _addLevelDgnrsClaimed(uint24 lvl, uint256 add) internal {
        uint256 w = levelDgnrsPacked[lvl];
        uint256 newClaimed = (w >> 128) + add;
        levelDgnrsPacked[lvl] = uint128(w) | (newClaimed << 128);
    }

    // =========================================================================
    // Deity Pass (Perma Whale) Grants
    // =========================================================================

    /// @dev ETH paid for a buyer's (single) deity pass, by wallet ID. The early-game-over refund
    ///      is capped at this, so a boon-discounted deity that paid < 20 ETH refunds only what it
    ///      actually paid. Ownership itself is tracked by the HAS_DEITY_PASS bit in mintPacked_.
    mapping(uint32 => uint96) internal deityPassPricePaid;

    /// @dev Every soulbound deity, genesis and paid, in registration order, as wallet IDs packed
    ///      eight uint32 lanes per word (low lane first). The root's length counts deities (at
    ///      most 32); data word w holds deities 8w..8w+7. Each deity holds one perpetual ticket
    ///      per level: the initial grant covers through level + 100 at registration and every
    ///      level transition extends every owner by one level (queuePerpetualTickets), which the
    ///      advance runs exactly once per transition. Read and append only through the lane
    ///      helpers; Solidity indexing would treat every word as one deity.
    uint256[] internal deityPassIds;

    /// @dev Number of deities.
    function _deityCount() internal view returns (uint256 count) {
        assembly ("memory-safe") { count := sload(deityPassIds.slot) }
    }

    /// @dev Packed word holding deities 8w..8w+7.
    function _deityWord(uint256 w) internal view returns (uint256 word) {
        assembly ("memory-safe") {
            mstore(0, deityPassIds.slot)
            word := sload(add(keccak256(0, 32), w))
        }
    }

    /// @dev Wallet ID of deity `i` (registration order).
    function _deityIdAt(uint256 i) internal view returns (uint32) {
        return uint32(_deityWord(i >> 3) >> ((i & 7) << 5));
    }

    /// @dev Append one deity ID in the next lane and bump the count.
    function _pushDeityId(uint32 id) internal {
        assembly ("memory-safe") {
            let count := sload(deityPassIds.slot)
            mstore(0, deityPassIds.slot)
            let slot := add(keccak256(0, 32), shr(3, count))
            let shift := shl(5, and(count, 7))
            sstore(slot, or(and(sload(slot), not(shl(shift, 0xffffffff))), shl(shift, id)))
            sstore(deityPassIds.slot, add(count, 1))
        }
    }

    /// @dev Protocol wallet IDs, registered in this order by the Game constructor before any
    ///      public door exists.
    uint32 internal constant VAULT_WALLET_ID = 1;
    uint32 internal constant SDGNRS_WALLET_ID = 2;
    uint32 internal constant GNRUS_WALLET_ID = 3;

    uint8 internal constant VAULT_DEITY_SYMBOL = 0;
    uint8 internal constant SDGNRS_DEITY_SYMBOL = 6;
    uint32 internal constant DEITY_PERPETUAL_ENTRIES = 4;

    /// @dev Reverse lookup: symbol ID (0-31) → the holding deity's wallet ID (0 = unclaimed).
    mapping(uint8 => uint32) internal deityBySymbol;

    // =========================================================================
    // Coin-Presale-Box DGNRS Curve
    // =========================================================================

    /// @dev Pool.PresaleBox DGNRS balance snapshot, set on the first box resolution.
    ///      The per-box DGNRS award uses base = presaleBoxDgnrsPoolStart / 100 and the
    ///      5-tier cumulative-volume multiplier curve [3.0, 2.5, 2.0, 1.5, 1.0].
    uint256 internal presaleBoxDgnrsPoolStart;

    // =========================================================================
    // Internal Helpers
    // =========================================================================


    /// @dev Front-load the LEVEL mint streak by a pass's freeze delta. Contiguity-aware: if the
    ///      prior completed run reaches the pass start with no gap, extend the streak by
    ///      `levelsToAdd`; otherwise reset to that span. `lastCompleted` advances to the pass
    ///      horizon and never regresses. `MASK_24`-saturating. Folds into the packed `data` word
    ///      before its single SSTORE — no ticket/freeze side effects.
    function _withPassStreakFrontLoad(
        uint256 data,
        uint24 startLevel,
        uint24 throughLevel,
        uint24 levelsToAdd
    ) internal pure returns (uint256) {
        if (levelsToAdd == 0) return data;
        uint24 lastCompleted = uint24(
            (data >> BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint256 prevStreak = (data >> BitPackingLib.LEVEL_STREAK_SHIFT) &
            BitPackingLib.MASK_24;
        // Continue the prior run while it is still alive. The streak decay rule tolerates one
        // un-minted level (alive at lastCompleted+1, breaks at +2), and startLevel == currentLevel+1,
        // so the run is alive at purchase iff startLevel <= lastCompleted+2. Otherwise a full level
        // lapsed with no mint — reset to this pass's span.
        uint256 newStreak = uint256(lastCompleted) + 2 >= startLevel
            ? prevStreak + levelsToAdd
            : levelsToAdd;
        if (newStreak > BitPackingLib.MASK_24) newStreak = BitPackingLib.MASK_24;
        uint24 newLastCompleted = throughLevel > lastCompleted
            ? throughLevel
            : lastCompleted;
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.MINT_STREAK_LAST_COMPLETED_SHIFT,
            BitPackingLib.MASK_24,
            newLastCompleted
        );
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LEVEL_STREAK_SHIFT,
            BitPackingLib.MASK_24,
            uint24(newStreak)
        );
        return data;
    }

    /// @notice Emitted with the absolute post-write `mintPacked_` word whenever a
    ///         mint-lane path writes it (units/streak/count/day/affiliate-cache
    ///         records, the boon level-count grant, the deity/seat bit latches).
    ///         One data word carries every field — units + their level, mint streak
    ///         + last-completed, lifetime count, mint day, freeze window, pass type,
    ///         curse, affiliate cache — so indexers fold absolute state per log and
    ///         never accumulate deltas or replay price math. Pass activations carry
    ///         the same word on PassActivated, and curse writes carry their absolute
    ///         field on CurseChanged. Cache-only affiliate refreshes are unlogged;
    ///         indexers should derive current affiliate points or call the score view.
    /// @param player The player whose mintPacked_ record was written.
    /// @param packedAfter The full mintPacked_ word after the write (BitPackingLib layout).
    event MintRecorded(uint32 indexed player, uint256 packedAfter);

    /// @notice Emitted on every pass activation (purchase AND award paths — this event
    ///         does not imply that the player bought the pass or received an AFKing seat).
    ///         It is the authoritative pass signal; the shared internals below and the whale
    ///         purchase's inline stats write all emit it). Carries the post-merge
    ///         freeze end so stacked/overlapping passes need no span heuristics,
    ///         plus the absolute post-write mintPacked_ word (the activation also
    ///         moves levelCount / passType / front-loaded streak).
    /// @param player The player the pass activates for.
    /// @param isWhale true = 100-level whale pass; false = 10-level lazy pass.
    /// @param startLevel First level of the pass's ticket range.
    /// @param frozenUntilAfter The FROZEN_UNTIL_LEVEL field after this activation
    ///        (max of the prior freeze and this pass's span end).
    /// @param packedAfter The full mintPacked_ word after the activation write.
    event PassActivated(
        uint32 indexed player,
        bool isWhale,
        uint24 startLevel,
        uint24 frozenUntilAfter,
        uint256 packedAfter
    );

    /// @dev Activates a 10-level pass for a registered player. Shared logic for lazy pass purchases
    ///      and awards. Updates mintPacked_ (levelCount +10, frozenUntilLevel, passType, lastLevel,
    ///      day) and queues tickets for the 10-level range under the wallet ID the word carries.
    /// @param player Address receiving the pass activation.
    /// @param ticketStartLevel First level of the 10-level range.
    /// @param entriesPerLevel Number of tickets to queue per level.
    function _activate10LevelPass(
        uint32 player,
        uint24 ticketStartLevel,
        uint32 entriesPerLevel
    ) internal {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 lastLevel = uint24(
            (prevData >> BitPackingLib.LAST_LEVEL_SHIFT) & BitPackingLib.MASK_24
        );
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 baseLevelsToAdd = 10;

        uint24 targetFrozenLevel = ticketStartLevel + 9; // Freeze for 10 levels from pass start
        uint24 newFrozenLevel = frozenUntilLevel > targetFrozenLevel
            ? frozenUntilLevel
            : targetFrozenLevel;
        uint24 deltaFreeze = newFrozenLevel > frozenUntilLevel
            ? (newFrozenLevel - frozenUntilLevel)
            : 0;
        uint24 levelsToAdd = baseLevelsToAdd;
        if (levelsToAdd > deltaFreeze) {
            levelsToAdd = deltaFreeze;
        }

        uint24 newLevelCount = levelCount + levelsToAdd;

        uint8 currentPassType = uint8(
            (prevData >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3
        );
        uint24 lastLevelTarget = newFrozenLevel > lastLevel
            ? newFrozenLevel
            : lastLevel;

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
        if (1 >= currentPassType) {
            data = BitPackingLib.setPacked(
                data,
                BitPackingLib.WHALE_PASS_TYPE_SHIFT,
                3,
                1
            );
        }
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            lastLevelTarget
        );

        uint24 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_24
        );

        // Front-load the LEVEL mint streak by the same freeze delta (survives pass expiry).
        data = _withPassStreakFrontLoad(
            data,
            ticketStartLevel,
            newFrozenLevel,
            levelsToAdd
        );

        mintPacked_[player] = data;

        _queueEntryRange(player, ticketStartLevel, 10, entriesPerLevel);
        emit PassActivated(player, false, ticketStartLevel, newFrozenLevel, data);
    }

    /// @dev Apply whale pass stats (levelCount/freeze/passType/lastLevel/day) without queueing tickets.
    /// @param player Registered address receiving the whale pass stats.
    /// @param ticketStartLevel First level of the 100-level range for whale pass tickets.
    /// @return id The player's wallet ID, read from the same word.
    function _applyWhalePassStats(
        uint32 player,
        uint24 ticketStartLevel
    ) internal returns (uint32 id) {
        uint256 prevData = mintPacked_[player];

        uint24 frozenUntilLevel = uint24(
            (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                BitPackingLib.MASK_24
        );
        uint24 levelCount = uint24(
            (prevData >> BitPackingLib.LEVEL_COUNT_SHIFT) &
                BitPackingLib.MASK_24
        );

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

        uint24 newLevelCount = levelCount + levelsToAdd;

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
            BitPackingLib.WHALE_PASS_TYPE_SHIFT,
            3,
            3
        ); // 3 = 100-level pass
        data = BitPackingLib.setPacked(
            data,
            BitPackingLib.LAST_LEVEL_SHIFT,
            BitPackingLib.MASK_24,
            newFrozenLevel
        );

        uint24 day = _currentMintDay();
        data = _setMintDay(
            data,
            day,
            BitPackingLib.DAY_SHIFT,
            BitPackingLib.MASK_24
        );
        // Front-load the LEVEL mint streak by the same freeze delta (survives pass expiry).
        data = _withPassStreakFrontLoad(
            data,
            ticketStartLevel,
            newFrozenLevel,
            levelsToAdd
        );

        mintPacked_[player] = data;
        emit PassActivated(player, true, ticketStartLevel, newFrozenLevel, data);
        id = player;
    }

    /// @dev Returns the current day index.
    function _simulatedDayIndex() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex();
    }

    /// @dev Whether the game-over trigger is active. Three causes:
    ///
    ///      VRF dead (_vrfDead): an unanswered daily request, or an unanswered mid-day request
    ///      whose normal promotion was blocked by an ending, reaches _VRF_DEAD_TIMEOUT.
    ///      That ending is deterministic and uses no entropy at all.
    ///
    ///      Deadman: no day sealed for _VRF_DEADMAN_DAYS, in any phase. A dead VRF is caught by
    ///      the first cause long before this, so here VRF is alive and the ending is the
    ///      normal VRF payout.
    ///
    ///      Purchase deadline, purchase phase only: purchaseStartDay + 250 days at level 0
    ///      (deploy idle) or + 30 days after. Past it the trigger reads exactly what the
    ///      advance's game-over path will decide: it fires once the ending has started (the
    ///      drain-level latch, which keeps it firing across the multi-tx drain), never while the
    ///      next pool beats the level's target (the rescue _handleGameOverPath applies), never on
    ///      a day that already holds its word, and otherwise only at a caught-up day
    ///      (today == dailyIdx + 1). A gap behind dailyIdx is a stall of that length — a VRF
    ///      request that has not come back (daily or mid-day), a multi-day ticket backlog, or
    ///      days nobody advanced — and it waits: the next advance requests the day's word, and
    ///      rngGate's backfill credits the skipped days to purchaseStartDay when that word is
    ///      applied. So a stall that opens on or before the deadline day and straddles it keeps
    ///      the level alive with the stalled days not counted, however its word comes back, and
    ///      needs no record of when it did. A gap that opens after the deadline is credited too,
    ///      but the credit never outruns the clock (the deadline stays at or behind dailyIdx), so
    ///      the next caught-up day still ends the level. The deadman and the VRF-dead window
    ///      bound how long any gap can last. A caught-up day that nobody advances can
    ///      therefore read true and then false once it has passed; the ending needs one advance
    ///      on a caught-up day, which the keeper router's advance leg sends whenever an advance
    ///      is due. A day that already holds its word is finished on it, even when
    ///      its own catch-up credit left the deadline behind it: the ending starts the next
    ///      day, before any word exists, so its terminal word is always requested after the
    ///      freeze and every cohort bought up to then is drawn.
    ///
    ///      Jackpot / last-purchase suppress the deadline: it would false-fire in the
    ///      productive window between target-met and transition close, where purchaseStartDay
    ///      has not yet moved.
    ///
    ///      Normal-path cost: the deadman compare and the VRF-dead probe read slot 0 only (the
    ///      probe reads the request day's word solely once a request is a whole window old), and
    ///      the latch, the pool target and today's word are read only past the deadline.
    function _livenessTriggered() internal view returns (bool) {
        uint24 today = _simulatedDayIndex();
        uint24 idx = dailyIdx;
        if (today > idx + _VRF_DEADMAN_DAYS) return true;
        if (_vrfDead()) return true;
        if (lastPurchaseDay || jackpotPhaseFlag) return false;
        if (today <= _purchaseDeadlineDay()) return false;
        return _pastDeadlineTriggered(today, idx);
    }

    /// @dev The purchase-deadline half of `_livenessTriggered`, reached only past the deadline.
    ///      Virtual so the near-full mint module can answer it through the Game's own view
    ///      rather than carry a copy (see the mint module's override); every other contract
    ///      evaluates it here.
    function _pastDeadlineTriggered(uint24 today, uint24 idx) internal view virtual returns (bool) {
        // The ending has started: irreversible.
        if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0) return true;
        // A met target rescues the level, exactly as _handleGameOverPath decides (the deadman
        // and a dead VRF already returned above).
        uint24 lvl = level;
        if (lvl != 0 && _getNextPrizePool() > _prizePoolTarget(lvl + 1)) return false;
        // A day that holds its word is finished on it.
        if (_recordedDailyWord(today) != 0) return false;
        // Gap credit advances dailyIdx before the separate daily-word action. Preserve
        // that already published current-day commitment across this checkpoint; otherwise
        // becoming caught up would trigger the deadline between credit and application.
        // An older day's commitment cannot defer today's ending.
        if (rngGapApplied && rngLockedFlag && rngRequestDay == today
            && _rngRequestActive() && _rngSessionPublished() && rngWordCurrent > RNG_WORD_WAITING) return false;
        // Only a caught-up day fires. A gap behind dailyIdx is a stall of that length and waits for
        // the backfill the next daily word runs to credit it.
        return today == idx + 1;
    }

    /// @dev Deadman: true once no day has sealed for _VRF_DEADMAN_DAYS. dailyIdx advances in
    ///      _unlockRng (a completed day) and past a stall's gap when its word lands (rngGate's
    ///      backfill), so currentDay - dailyIdx counts days since real progress. It stays
    ///      frozen after game over (the terminal _unlockRng leaves dailyIdx alone), so it never
    ///      evaporates mid-drain.
    function _vrfDeadmanFired() internal view returns (bool) {
        return _simulatedDayIndex() > uint24(dailyIdx) + _VRF_DEADMAN_DAYS;
    }

    /// @dev An active, unanswered request expires from its original timestamp. A delivered
    ///      word proves VRF is alive even while the keeper has not published it. Retained idle
    ///      timestamps grant neither callback authority nor a timeout. A refused terminal
    ///      attempt has no active request, but keeps its one-shot timer and unpublished latch.
    function _vrfDead() internal view returns (bool) {
        uint48 t = rngRequestTime;
        if (block.timestamp < uint256(t) + _VRF_DEAD_TIMEOUT) return false;
        if (!_rngRequestActive()) {
            if (_rngSessionPublished()) return false;
            if (_lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0) return true;
            if (_lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0) return false;
        }
        // Active/waiting authority is sufficient. A previously recorded day cannot
        // excuse an unanswered terminal or replacement request.
        return rngWordCurrent == RNG_WORD_WAITING;
    }

    /// @dev Returns the day index for a specific timestamp.
    function _simulatedDayIndexAt(uint48 ts) internal pure returns (uint24) {
        return GameTimeLib.currentDayIndexAt(ts);
    }

    /// @dev Gets the current mint day from dailyIdx or calculates from timestamp.
    function _currentMintDay() internal view returns (uint24) {
        uint24 day = dailyIdx;
        if (day == 0) {
            day = _simulatedDayIndex();
        }
        return day;
    }

    /// @dev Updates the day field in packed mint data if changed.
    function _setMintDay(
        uint256 data,
        uint24 day,
        uint256 dayShift,
        uint256 dayMask
    ) internal pure returns (uint256) {
        uint24 prevDay = uint24((data >> dayShift) & dayMask);
        if (prevDay == day) return data;
        uint256 clearedDay = data & ~(dayMask << dayShift);
        return clearedDay | (uint256(day) << dayShift);
    }

    // =========================================================================
    // VRF Configuration (on the shared base for module access)
    // =========================================================================

    /// @dev Chainlink VRF V2.5 coordinator contract.
    ///      Mutable for emergency rotation; see updateVrfCoordinatorAndSub().
    IVRFCoordinator internal vrfCoordinator;

    /// @dev VRF key hash identifying the oracle and gas lane.
    ///      Rotatable with coordinator; determines gas price tier.
    bytes32 internal vrfKeyHash;

    /// @dev VRF subscription ID for LINK billing.
    ///      Mutable to allow subscription rotation without redeploying.
    uint256 internal vrfSubscriptionId;

    // =========================================================================
    // Lootbox RNG Packed Slot (amounts, ticket latches and Craps pending flags)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits   0:23]   heroBufferDay             uint24   (latest day in the hero ring)
    //   [bits  24:29]   heroQuadrantsValid        uint6    (3 quadrant bits per parity)
    //   [bits  30:37]   middayMaxBasefeeGwei      uint8    (whole gwei, 0 disables the gate)
    //   [bits  38:47]   unused
    //   [bits  48:87]   lootboxRngPendingEth      uint40   (scaled /1e15, 0.001 ETH res, ~1.1B ETH)
    //   [bits  88:119]  lootboxRngThreshold       uint32   (scaled /1e15, 0.001 ETH res, ~4.29M ETH)
    //   [bits 120:151]  boxWriteCount             uint32   (box entries appended to the write buffer)
    //   [bits 152:183]  betWriteCount             uint32   (Degenerette bets appended to the write buffer)
    //   [bits 184:223]  lootboxRngPendingFlip  uint40   (whole FLIP, max ~1.1T FLIP)
    //   [bits 224:231]  midDayTicketRngPending   uint8    (0=idle, 1=ordinary, 2=isolated future pool)
    //   [bits 232:239]  gameOverDeadLatched      uint8    (bool flag, 8 bits)
    //   [bits 240:247]  gameOverDrainLevelLatch  uint8    (0=unset, 1=lvl, 2=lvl+1)
    //   [bit 248]       gameOverTerminalRequested bool
    //   [bit 249]       unused (publication now lives in slot0)
    //   [bits 250:251]  crapsRngPending           bool per physical buffer
    //   [bits 252:255]  reserved

    /// @dev Packed lootbox RNG state. See layout comment above.
    ///      Initialized with lootboxRngThreshold=1 ether (scaled=1000),
    ///      middayMaxBasefeeGwei=5.
    uint256 internal lootboxRngPacked =
        (uint256(1000) << 88)                     // lootboxRngThreshold = 1 ether / 1e15 = 1000
        | (uint256(5) << 30);                       // middayMaxBasefeeGwei = 5

    // ---- lootboxRng shifts and masks ----
    uint256 internal constant LR_PENDING_ETH_SHIFT = 48;
    uint256 internal constant LR_PENDING_ETH_MASK = 0xFFFFFFFFFF;            // 40 bits
    uint256 internal constant LR_THRESHOLD_SHIFT = 88;
    uint256 internal constant LR_THRESHOLD_MASK = 0xFFFFFFFF;                // 32 bits
    /// @dev Write-side queue counts. Each purchase or bet commits its count in the
    ///      lootboxRngPacked write it already makes; the seal copies them into the read lengths.
    uint256 internal constant LR_BOX_COUNT_SHIFT = 120;
    uint256 internal constant LR_BET_COUNT_SHIFT = 152;
    uint256 internal constant LR_COUNT_MASK = 0xFFFFFFFF;                    // 32 bits
    uint256 internal constant LR_PENDING_FLIP_SHIFT = 184;
    uint256 internal constant LR_PENDING_FLIP_MASK = 0xFFFFFFFFFF;         // 40 bits
    uint256 internal constant LR_MID_DAY_SHIFT = 224;
    uint256 internal constant LR_MID_DAY_MASK = 0xFF;                       // 8 bits
    /// @dev An isolated next-level pool, committed without swapping the ordinary ticket queues.
    ///      Like an ordinary mid-day batch (1), it pins the sealed read buffer until the drain completes.
    uint256 internal constant MID_DAY_FUTURE_POOL = 2;
    uint256 internal constant LR_MAX_BASEFEE_SHIFT = 30;
    uint256 internal constant LR_MAX_BASEFEE_MASK = 0xFF;                   // 8 bits
    /// @dev Set on the first entry of the deterministic (VRF-dead) ending; never cleared.
    uint256 internal constant LR_GO_DEAD_SHIFT = 232;
    uint256 internal constant LR_GO_DEAD_MASK = 0xFF;                       // 8 bits
    uint256 internal constant LR_GO_LVL_SHIFT = 240;
    uint256 internal constant LR_GO_LVL_MASK = 0xFF;                        // 8 bits
    /// @dev Set when the normal ending sends its own terminal request (its one ticket swap, if
    ///      any, goes just before); never cleared. Until then a held daily lock is a pre-freeze
    ///      request, never the terminal word.
    uint256 internal constant LR_GO_SWAP_SHIFT = 248;
    uint256 internal constant LR_GO_SWAP_MASK = 1;

    /// @dev Ceiling on the tunable mid-day basefee gate, in whole gwei (the field is 8
    ///      bits). Zero disables the gate, letting mid-day requests issue at any price.
    uint256 internal constant MIDDAY_MAX_BASEFEE_GWEI_CAP = 255;

    /// @dev Gas a mid-day fulfillment bills, summing the three terms the coordinator
    ///      charges for: the ~50k callback, mainnet's ~112k proof verification, and the
    ///      coordinator's own gasAfterPaymentCalculation of 38,900, which it adds to the
    ///      gas it measured. It bills gas actually used, not the request's
    ///      callbackGasLimit, so this tracks the real figure rather than the reservation.
    uint256 internal constant MIDDAY_RNG_BILLED_GAS = 201_000;

    /// @dev Multiple of the billed gas charged against a donor's credit: a 5x markup times
    ///      the coordinator's 20% LINK premium. Charging a multiple of what the request
    ///      actually costs — rather than a fixed price — keeps the charge tracking gas
    ///      with no stored rate to re-calibrate as gas or LINK/ETH drifts. The markup
    ///      holds while a fulfillment prices within 5x the request block's basefee and the
    ///      feed tracks the coordinator's own LINK valuation; outside that band a
    ///      redemption bills more than it charged. What bounds the subscription's exposure
    ///      is the mid-day LINK floor rather than this multiple — requests stop below
    ///      MIN_LINK_FOR_LOOTBOX_RNG, leaving that balance to the daily word, which is
    ///      never gated. A pending craps window answers to MIN_LINK_FOR_CRAPS_RNG instead, a
    ///      reserve sized to one daily word rather than to a queue that can wait for it.
    uint256 internal constant MIDDAY_RNG_CHARGE_MULT = 6;

    /// @dev Scale factor for ETH/LINK packing (0.001 resolution).
    uint256 internal constant LR_ETH_SCALE = 1e15;

    // Activity score EV multiplier constants (ETH lootbox only)
    /// @dev 60-point activity score = neutral 100% EV
    uint16 internal constant LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS = 60;
    /// @dev 400-point activity score = the seg-A knee (~139.5% EV)
    uint16 internal constant LOOTBOX_EV_ACTIVITY_MAX_POINTS = 400;
    /// @dev Minimum EV at 0-point activity (90%)
    uint16 internal constant LOOTBOX_EV_MIN_BPS = 9_000;
    /// @dev Neutral EV at 60-point activity (100%)
    uint16 internal constant LOOTBOX_EV_NEUTRAL_BPS = 10_000;
    /// @dev EV at the seg-A knee (139.5%, 90% of the gain)
    uint16 internal constant LOOTBOX_EV_VA_BPS = 13_950;
    /// @dev EV at the seg-B knee (143.9%, 98% of the gain)
    uint16 internal constant LOOTBOX_EV_VB_BPS = 14_390;
    /// @dev Maximum EV (145%, reached at the effective cap)
    uint16 internal constant LOOTBOX_EV_MAX_BPS = 14_500;
    /// @dev Maximum EV benefit cap per account per level (10 ETH scaled)
    uint256 internal constant LOOTBOX_EV_BENEFIT_CAP =
        10 ether;

    /// @dev Read a field from the packed lootbox RNG slot.
    function _lrRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (lootboxRngPacked >> shift) & mask;
    }

    /// @dev Write a field to the packed lootbox RNG slot.
    function _lrWrite(uint256 shift, uint256 mask, uint256 value) internal {
        lootboxRngPacked = (lootboxRngPacked & ~(mask << shift)) | ((value & mask) << shift);
    }

    /// @dev Add a delta to a field of the packed lootbox RNG slot in one load + store.
    ///      The summed field re-masks before the merge — the same wrap-on-mask
    ///      semantics as _lrWrite(shift, mask, _lrRead(shift, mask) + delta).
    function _lrAdd(uint256 shift, uint256 mask, uint256 delta) internal {
        uint256 packed = lootboxRngPacked;
        lootboxRngPacked =
            (packed & ~(mask << shift)) |
            (((((packed >> shift) & mask) + delta) & mask) << shift);
    }

    /// @dev Pack a wei amount to milli-ETH (divide by 1e15). 0.001 ETH resolution.
    function _packEthToMilliEth(uint256 wei_) internal pure returns (uint64) {
        return uint64(wei_ / LR_ETH_SCALE);
    }

    /// @dev Unpack milli-ETH to wei (multiply by 1e15).
    function _unpackMilliEthToWei(uint64 milli) internal pure returns (uint256) {
        return uint256(milli) * LR_ETH_SCALE;
    }


    /// @dev EV multiplier from a raw activity score (whole points).
    ///      Unchanged low anchor 90%→100% (0 to 60 points), then a steep ramp to vA
    ///      (139.5%) at the 400-point knee, a shallow leg to vB (143.9%) at the seg-B
    ///      knee, and a near-flat crawl to 145% at the effective cap.
    /// @param score The activity score in whole points
    /// @return The EV multiplier in basis points (9000-14500)
    function _lootboxEvMultiplierFromScore(
        uint256 score
    ) internal pure returns (uint256) {
        if (score <= LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS) {
            // Linear: 0-point → 90% EV, 60-point → 100% EV
            return LOOTBOX_EV_MIN_BPS +
                (score * (LOOTBOX_EV_NEUTRAL_BPS - LOOTBOX_EV_MIN_BPS)) /
                LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS;
        }
        if (score >= ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS) {
            return LOOTBOX_EV_MAX_BPS;
        }
        if (score <= LOOTBOX_EV_ACTIVITY_MAX_POINTS) {
            // seg A: 60-point → 100% EV, 400-point → 139.5% EV
            return
                LOOTBOX_EV_NEUTRAL_BPS +
                ((score - LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS) *
                    (LOOTBOX_EV_VA_BPS - LOOTBOX_EV_NEUTRAL_BPS)) /
                (LOOTBOX_EV_ACTIVITY_MAX_POINTS -
                    LOOTBOX_EV_ACTIVITY_NEUTRAL_POINTS);
        }
        if (score <= ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) {
            // seg B: 400-point → 139.5% EV, seg-B knee → 143.9% EV
            return
                LOOTBOX_EV_VA_BPS +
                ((score - LOOTBOX_EV_ACTIVITY_MAX_POINTS) *
                    (LOOTBOX_EV_VB_BPS - LOOTBOX_EV_VA_BPS)) /
                (ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS -
                    LOOTBOX_EV_ACTIVITY_MAX_POINTS);
        }
        // seg C: seg-B knee → 143.9% EV, effective cap → 145% EV
        return
            LOOTBOX_EV_VB_BPS +
            ((score - ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS) *
                (LOOTBOX_EV_MAX_BPS - LOOTBOX_EV_VB_BPS)) /
            (ActivityCurveLib.ACTIVITY_EFFECTIVE_CAP_POINTS -
                ActivityCurveLib.ACTIVITY_SEG_B_KNEE_POINTS);
    }

    /// @dev RNG words keyed by lootbox RNG index.
    uint256 internal rngDayTags; // Absolute-day tags for the two reusable daily RNG slots.

    // =========================================================================
    // Deity Boon Tracking
    // =========================================================================

    /// @dev Per-deity boon assignment day + used-slot mask, packed into one slot:
    ///      bits [0:24) = day the boon slots were assigned, bits [24:32) = bitmask of
    ///      used slots for that day (bit i = slot i used). A stale day reads its mask
    ///      as irrelevant because every reader gates on the day matching; the day-roll
    ///      write re-stamps the day with a fresh (zero) mask in one store.
    mapping(uint32 => uint32) internal deityBoonPacked;

    /// @dev Day when recipient last received a deity boon (prevents double-receipt
    ///      on the same day, regardless of which deity issues it).
    mapping(uint32 => uint24) internal deityBoonRecipientDay;

    // =========================================================================
    // Degenerette Bets
    // =========================================================================

    /// @dev Biggest-spin record bounty in WHOLE FLIP for a queued bet, keyed
    ///      (index << 64) | betId. Written only when a placement arms the record (the bet word's
    ///      record flag), read and cleared when that bet resolves.
    mapping(uint256 => uint256) internal degeneretteRecordBounty;

    // =========================================================================
    // Early Ticket Activation
    // =========================================================================

    /// @dev Highest next-level pool activated by a target-met fresh RNG request. Kept after its
    ///      drain so later entries cannot reopen that level's frozen far-future queue. The
    ///      ordinary mint ceiling catches up at the last-purchase level promotion.
    uint24 internal earlyTicketLevel;

    // =========================================================================
    // Lootbox EV Multiplier Cap Tracking
    // =========================================================================

    /// @dev Per-player lootbox EV-multiplier benefit used, two level-stamped windows in
    ///      one slot. At any instant only the keys {currentLevel, currentLevel+1} are live
    ///      (opens RMW currentLevel, deposits RMW level+1), so two windows hold the full
    ///      live set with no eviction of a live key. Each window: used (64 bits) + level
    ///      stamp (24 bits). `used` is clamped to LOOTBOX_EV_BENEFIT_CAP = 10 ether = 1e19
    ///      < 2^64 at every write. A non-matching stamp reads as 0 (a fresh allowance).
    ///      Window A: bits [0:64) used, [64:88) level. Window B: bits [88:152) used, [152:176) level.
    mapping(uint32 => uint256) internal lootboxEvCapPacked;

    uint256 private constant _EV_USED_MASK = (uint256(1) << 64) - 1;
    uint256 private constant _EV_WINDOW_A_MASK = (uint256(1) << 88) - 1;
    uint256 private constant _EV_WINDOW_B_MASK =
        ((uint256(1) << 88) - 1) << 88;

    /// @dev A player's EV benefit used for `level`; 0 if neither window is stamped to it.
    function _lootboxEvUsedFor(uint32 id, uint24 level)
        internal
        view
        returns (uint256)
    {
        uint256 packed = lootboxEvCapPacked[id];
        if (uint24(packed >> 64) == level) return packed & _EV_USED_MASK;
        if (uint24(packed >> 152) == level) return (packed >> 88) & _EV_USED_MASK;
        return 0;
    }

    /// @dev Record `used` for `level`: into the window already stamped to `level`, else
    ///      evict the smaller-level window (the older of the two; never a live key, since
    ///      the live set is {currentLevel, currentLevel+1}).
    function _setLootboxEvUsedFor(
        uint32 id,
        uint24 level,
        uint256 used
    ) internal {
        uint256 packed = lootboxEvCapPacked[id];
        uint24 lvlA = uint24(packed >> 64);
        uint24 lvlB = uint24(packed >> 152);
        uint256 windowA = (uint256(level) << 64) | (used & _EV_USED_MASK);
        if (lvlA == level) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else if (lvlB == level) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 88);
        } else if (lvlA <= lvlB) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 88);
        }
    }

    // =========================================================================
    // Decimator Jackpot State
    // =========================================================================
    // All decimator logic is consolidated into the DecimatorModule.

    /// @dev Frozen event and bounded settlement cursors. Phase: 0 entry, 1 runs, 2 payouts, 3 done.
    struct DecBattleRound {
        uint96 poolWei;
        uint40 count;
        uint64 totalCreditedStack;
        uint24 openedDay;
        uint8 phase;
        uint8 capacity;
        uint8 winners;
        uint8 paid;
        uint64 cursor; // Sampled strata completed, at most 1000.
        uint64 champion;
        uint24 next;
    }

    /// @dev Four mapping roots replace the four retired bucket-system roots without moving
    ///      unrelated storage. Two entries share key (level << 64) | ((id - 1) >> 1), IDs starting
    ///      at one. Each 128-bit lane packs wallet ID32, board30 and stack66, low to high.
    ///      Resolution and lens readers consume this same compact lane directly.
    ///      A wallet's slot, reused
    ///      window after window, holds its latest entry's level (bits 64..87) and id (0..63).
    mapping(uint256 => uint256) internal decBattleEntries;
    mapping(uint24 => DecBattleRound) internal decBattleRounds;
    /// @dev The leaderboard of the round at the head of the queue, keyed by heap position: a
    ///      node is its score (whole-FLIP stack x normalized peak) above the 64-bit entry id, and
    ///      equal scores order by a random tiebreak recomputed from the id. The FIFO settles one
    ///      round at a time, so every round reuses these slots.
    mapping(uint256 => uint256) internal decBattleHeap;
    mapping(uint32 => uint256) internal decBattlePlayers;

    // =========================================================================
    // Degenerette Hero Wager Tracking (Daily)
    // =========================================================================

    /// @dev Daily hero symbol wagers (ETH only). Keys 0/1 are reusable day-parity buffers;
    ///      their day and quadrant-valid bits live in lootboxRngPacked's low 30 bits.
    ///      While advance is behind, days beyond dailyIdx+1 use their full day as the key
    ///      (always >=2), preserving the frozen jackpot pool until settlement catches up.
    ///      Value: 4 packed uint256s (only the first three quadrants are eligible).
    ///      Each uint256 packs 8 × 32-bit amounts (one per symbol in that quadrant).
    ///      Amounts stored in units of 1e14 wei (0.0001 ETH) to fit 32 bits
    ///      (max ~429,500 ETH per symbol per day).
    mapping(uint24 => uint256[4]) internal dailyHeroWagers;

    uint256 internal constant HERO_BUFFER_META_MASK = (1 << 30) - 1;

    /// @dev Read a retained hero pool. Days older than the ring return zero, including
    ///      any retired spill prefix. An invalid quadrant never exposes an old buffer.
    function _dailyHeroWagerWord(uint24 day, uint8 quadrant) internal view returns (uint256) {
        unchecked {
            if (quadrant >= 3) return 0;
            uint256 meta = lootboxRngPacked;
            uint256 latest = uint24(meta);
            if (uint256(day) + 1 < latest) return 0;
            uint256 bit = uint256(1) << (24 + (day & 1) * 3 + quadrant);
            if (latest >= day && meta & bit != 0) {
                return dailyHeroWagers[day & 1][quadrant];
            }
            return day > 1 ? dailyHeroWagers[day][quadrant] : 0;
        }
    }

    /// @dev Only a day at/before dailyIdx+1 can recycle a buffer: everything evicted is
    ///      strictly older than the jackpot's frozen dailyIdx. Later wall-clock days spill
    ///      instead. When advance catches up, each quadrant lazily imports its spill word.
    ///      Valid bits reset counts logically; the old nonzero word is overwritten directly,
    ///      avoiding both a clearing SSTORE and a fresh zero-to-nonzero SSTORE.
    ///      The caller merges returned metadata with its existing pending-ETH write.
    function _recordDailyHeroWager(uint24 day, uint8 quadrant, uint8 symbol, uint256 units, uint256 meta)
        internal returns (uint256)
    {
        // Validated symbol <24 bounds every shift; the uint24 days are widened before
        // adding one. Paid units come from <=25 uint128 stakes /1e14, so adding a
        // uint32 lane is also far below uint256's limit before saturation.
        unchecked {
            uint24 key = day;
            uint256 packed;
            uint256 latest = uint24(meta);
            if (day == latest || uint256(day) <= uint256(dailyIdx) + 1) {
                key = day & 1;
                uint256 valid = (meta >> 24) & 63;
                if (day != latest) {
                    valid = uint256(day) == latest + 1 ? valid & ~(uint256(7) << (key * 3)) : 0;
                }
                uint256 bit = uint256(1) << (key * 3 + quadrant);
                if (valid & bit != 0) {
                    packed = dailyHeroWagers[key][quadrant];
                } else {
                    // A day first seen during a stall may already have paid wagers.
                    packed = day > 1 ? dailyHeroWagers[day][quadrant] : 0;
                    meta = (meta & ~HERO_BUFFER_META_MASK) | day | ((valid | bit) << 24);
                }
            } else {
                packed = dailyHeroWagers[key][quadrant];
            }
            uint256 shift = uint256(symbol) * 32;
            uint256 updated = uint32(packed >> shift) + units;
            if (updated > type(uint32).max) updated = type(uint32).max;
            dailyHeroWagers[key][quadrant] = (packed & ~(uint256(type(uint32).max) << shift)) | (updated << shift);
            return meta;
        }
    }

    // =========================================================================
    // Segregated Yield Accumulator
    // =========================================================================

    /// @dev Segregated stETH yield accumulator.
    ///      Collects 23% of yield surplus each level transition (one of four 23% shares).
    ///      x00 milestones: 50% to currentPrizePool, 50% retained as terminal insurance.
    ///      INVARIANT: counted as obligation in yield surplus calculation.
    uint256 internal yieldAccumulator;

    // =========================================================================
    // Century (x00) Ticket Bonus Tracking
    // =========================================================================

    /// @dev Per-player century (x00) bonus usage, packed as (level << 224 | used).
    ///      The high bits stamp WHICH x00 level the usage applies to, so every
    ///      player is independent: a value stamped to a prior century reads as 0
    ///      (a fresh 20-ETH allowance) with no global reset. Enforces the
    ///      20-ETH-equivalent per-player cap across multiple buys at one level.
    mapping(uint32 => uint256) internal centuryBonusUsed;

    uint256 private constant _CENTURY_USED_MASK = (uint256(1) << 224) - 1;

    /// @dev A player's century-bonus usage for the given x00 level; 0 if the
    ///      stored stamp belongs to a prior century (stale).
    function _centuryUsedFor(uint32 id, uint256 level) internal view returns (uint256) {
        uint256 packed = centuryBonusUsed[id];
        return (packed >> 224) == level ? (packed & _CENTURY_USED_MASK) : 0;
    }

    /// @dev Records a player's century-bonus usage, stamped to the given x00 level.
    function _setCenturyUsedFor(uint32 id, uint256 level, uint256 used) internal {
        centuryBonusUsed[id] = (level << 224) | (used & _CENTURY_USED_MASK);
    }

    // =========================================================================
    // Deity sales and protocol boon draws
    // =========================================================================

    /// @dev Paid deity purchases only: the two genesis grants never advance pricing.
    uint8 internal deityPassSales;

    /// @dev 240 bits. Paid ETH stays in wei; weight uses 0.0001-ETH units times
    ///      the activity multiplier scaled by 800. Three award bits, one per boon. `day` is
    ///      the wager day the pool's ring slot currently holds (see protocolBoonPools).
    struct ProtocolBoonPool {
        uint112 totalWageredWei;
        uint64 totalWeight;
        uint32 entryCount;
        uint8 awardedMask;
        uint24 day;
    }

    /// @dev 112 bits, one slot. Checked uint64 cumulative weight bounds the pool's
    ///      paid ETH below uint112 capacity, including each entry's sub-unit dust.
    struct ProtocolBoonEntry {
        uint32 playerId;
        uint64 cumulativeWeight;
        uint16 scoreSnapshot;
    }

    /// @dev Two-slot rings keyed [issuer][day & 1], so each day reuses the slots written two
    ///      days earlier instead of fresh zero slots. Sound because day D's pool and entries are
    ///      written only on wall day D (placement keys the wall day) and drawn only on wall day
    ///      D + 1 (resolveProtocolBoonDraws returns unless the award day is today), so when day
    ///      D + 2 reuses the slots, day D has been drawn or never can be. A pool whose `day` tag
    ///      is not the day asked for holds another day and reads as empty; the first entry
    ///      of a new day resets it. Entries at or past the pool's entryCount are leftovers.
    mapping(uint32 => mapping(uint24 => ProtocolBoonPool)) internal protocolBoonPools;
    mapping(uint32 => mapping(uint24 => mapping(uint32 => ProtocolBoonEntry))) internal protocolBoonEntries;

    bytes32 internal constant PROTOCOL_BOON_WINNER_TAG = keccak256("degenerus.protocol.boon.winner");

    // =========================================================================
    // Boon Packed Storage
    // =========================================================================

    /// @dev Packed boon state for a single player. 2 storage slots.
    ///
    /// Slot 0 (256 bits):
    ///   [0-23]    coinflipDay          uint24   Day coinflip boon was awarded
    ///   [24-47]   deityCoinflipDay     uint24   Deity-source day for coinflip boon
    ///   [48-55]   coinflipTier         uint8    0=none, 1=5%, 2=10%, 3=25%
    ///   [56-79]   lootboxBoostDay      uint24   Day lootbox boost was awarded
    ///   [80-103]  deityLootboxDay      uint24   Deity-source day for lootbox boost
    ///   [104-111] lootboxBoostTier     uint8    0=none, 1=5%, 2=15%, 3=25%
    ///   [112-135] purchaseDay          uint24   Day purchase boost was awarded
    ///   [136-159] deityPurchaseDay     uint24   Deity-source day for purchase boost
    ///   [160-167] purchaseTier         uint8    0=none, 1=5%, 2=15%, 3=25%
    ///   [168-175] decimatorTier        uint8    0=none, 1=10%, 2=25%, 3=50%
    ///   [176-199] deityDecimatorDay    uint24   Deity-source day for decimator
    ///   [200-223] whaleDay             uint24   Day whale boon was awarded
    ///   [224-247] deityWhaleDay        uint24   Deity-source day for whale boon
    ///   [248-255] whaleTier            uint8    0=none, 1=10%, 2=20%, 3=35%
    ///
    /// Slot 1 (bits 0-23 and 72-255 used; bits 24-71 free):
    ///   [0-23]    craps                uint24   Craps stake-boon lane (the LOW lane, so the
    ///                                           consumption hot path masks without shifting)
    ///   [24-71]   (free)                        Activity awards are credited to player
    ///                                           stats on award and hold no boon state
    ///   [72-79]   deityPassTier        uint8    0=none, 1=10%, 2=20%, 3=35%
    ///   [80-103]  deityPassDay         uint24   Day deity pass boon was awarded
    ///   [104-127] deityDeityPassDay    uint24   Deity-granted deity pass boon day
    ///   [128-151] lazyPassDay          uint24   Day lazy pass boon was awarded
    ///   [152-175] deityLazyPassDay     uint24   Deity-source day for lazy pass boon
    ///   [176-183] lazyPassTier         uint8    0=none, 1=10%, 2=25%, 3=50%
    ///   [184-207] degeneretteEth       uint24   ETH degenerette stake-boon lane
    ///   [208-231] degeneretteFlip      uint24   FLIP degenerette stake-boon lane
    ///   [232-255] wwxrp                uint24   WWXRP ecosystem boon lane
    ///
    /// The craps, ETH/FLIP degenerette and WWXRP lanes share ONE 24-bit encoding:
    ///   [0-1]  tier    0=none, else 1..3 — the family decodes the size
    ///   [2]    isDeity deity-granted boons die at the end of their game day (22:57 UTC reset)
    ///   [3-23] day     low 21 bits of the award day (lootbox-rolled boons live
    ///                  BOON_LANE_EXPIRY_DAYS past it; comparisons run on
    ///                  masked values, wrapping after ~5,700 years)
    ///
    /// Tier decode is per-family and NOT part of the encoding: degenerette and WWXRP lanes
    /// read tier x 400 (+4/8/12%), the craps lane reads _coinflipTierToBps on the wire
    /// (500/1000/2500) and the craps table pays it at 5/10/15%.
    ///
    /// A degenerette lane is one INDEPENDENT per-currency stake boon — lanes coexist and only a
    /// boon of the same currency can displace one — and is spent by the next bet in its own
    /// currency. The craps lane is spent by the next paid craps burn. The WWXRP lane
    /// is consumed through the token for a supported ecosystem action, including draw entry.
    struct BoonPacked {
        uint256 slot0;
        uint256 slot1;
    }

    /// @dev Packed boon state by wallet ID; nothing is ever written under ID 0, so its lanes
    ///      read empty. Public getter returns (uint256 slot0, uint256 slot1); bit layout above.
    ///      UI readers combine with currentDayView() to compute per-category expiry. WWXRP.enter
    ///      reads slot1's WWXRP lane by raw slot `keccak256(id, slot) + 1` (its
    ///      GAME_BOON_PACKED_SLOT / GAME_WWXRP_LANE_SHIFT / GAME_LANE_TIER_MASK mirror this
    ///      mapping's slot, BP_WWXRP_LANE_SHIFT and BP_LANE_TIER_MASK): moving any of them
    ///      must move those too (pinned by test/fuzz/WwxrpBoonLaneSkip.t.sol).
    mapping(uint32 => BoonPacked) public boonPacked;

    // ---- Slot 0 shifts ----
    uint256 internal constant BP_COINFLIP_DAY_SHIFT = 0;
    uint256 internal constant BP_DEITY_COINFLIP_DAY_SHIFT = 24;
    uint256 internal constant BP_COINFLIP_TIER_SHIFT = 48;
    uint256 internal constant BP_LOOTBOX_DAY_SHIFT = 56;
    uint256 internal constant BP_DEITY_LOOTBOX_DAY_SHIFT = 80;
    uint256 internal constant BP_LOOTBOX_TIER_SHIFT = 104;
    uint256 internal constant BP_PURCHASE_DAY_SHIFT = 112;
    uint256 internal constant BP_DEITY_PURCHASE_DAY_SHIFT = 136;
    uint256 internal constant BP_PURCHASE_TIER_SHIFT = 160;
    uint256 internal constant BP_DECIMATOR_TIER_SHIFT = 168;
    uint256 internal constant BP_DEITY_DECIMATOR_DAY_SHIFT = 176;
    uint256 internal constant BP_WHALE_DAY_SHIFT = 200;
    uint256 internal constant BP_DEITY_WHALE_DAY_SHIFT = 224;
    uint256 internal constant BP_WHALE_TIER_SHIFT = 248;

    // ---- Slot 1 shifts (the craps lane owns bits 0-23; bits 24-71 are free) ----
    uint256 internal constant BP_DEITY_PASS_TIER_SHIFT = 72;
    uint256 internal constant BP_DEITY_PASS_DAY_SHIFT = 80;
    uint256 internal constant BP_DEITY_DEITY_PASS_DAY_SHIFT = 104;
    uint256 internal constant BP_LAZY_PASS_DAY_SHIFT = 128;
    uint256 internal constant BP_DEITY_LAZY_PASS_DAY_SHIFT = 152;
    uint256 internal constant BP_LAZY_PASS_TIER_SHIFT = 176;
    uint256 internal constant BP_DEGEN_LANE0_SHIFT = 184;
    uint256 internal constant BP_WWXRP_LANE_SHIFT = 232; // mirrored in WWXRP (see boonPacked)
    uint256 internal constant BP_LANE_MASK = 0xFFFFFF;
    uint256 internal constant BP_LANE_TIER_MASK = 0x3;
    uint256 internal constant BP_LANE_DEITY_BIT = 0x4;
    uint256 internal constant BP_LANE_DAY_SHIFT = 3;
    uint256 internal constant BP_LANE_DAY_MASK = 0x1FFFFF;
    /// @dev Days a lootbox-rolled lane boon lives past its stamp day. Shared by the degenerette,
    ///      WWXRP and craps lanes, which carry the same two-day life as the coinflip boon.
    uint24 internal constant BOON_LANE_EXPIRY_DAYS = 2;
    /// @dev Stake-bonus base caps for ETH/FLIP degenerette boons (+4/8/12% of the bet's
    ///      total, up to the cap). The WWXRP ecosystem boon has a separate token consume path.
    ///      Shared by the Degenerette module and the Boon module's EV normalization.
    uint256 internal constant DEGENERETTE_BOON_ETH_CAP = 10 ether;
    uint256 internal constant DEGENERETTE_BOON_FLIP_CAP = 100_000;

    /// @dev What ONE Craps day pass is worth, as a lootbox denomination. This is the expected cost
    ///      of entering all six scheduled windows at 1x: 24,825 FLIP, rounded to 24,800.
    ///      The shared pricing library also supplies the table and FLIP comp allowance.
    ///
    ///      A DENOMINATION, NOT A QUOTE. The realised cost of any particular day is drawn from that
    ///      day's word and moves; the pass is committed before the word lands, and that is what
    ///      makes a fixed expected-value unit the honest way to price it.
    ///
    ///      ⚠ Tied to the preset table. Any edit to the scheduled bankroll or bounty distribution
    ///      must recompute the expectation, re-round to the nearest 100, and update CrapsPriceLib.
    ///      test/craps/CrapsPricing.t.sol exhausts the tier/bounty cycle to verify the mean.
    uint256 internal constant NORMAL_DAY_PASS_VALUE = CrapsPriceLib.NORMAL_VALUE;

    /// @dev And what a HIGH-ROLLER day pass is worth: exactly twenty-one normal ones. The day's
    ///      multiplier is 10 in 79 of 90 buckets and 100 in 11, so its expectation is exactly 21. Defining
    ///      the high value as a multiple keeps the denominations in proportion.
    uint256 internal constant HIGH_ROLLER_DAY_PASS_VALUE = CrapsPriceLib.HIGH_VALUE;

    // ---- Masks ----
    uint256 internal constant BP_MASK_24 = 0xFFFFFF;
    uint256 internal constant BP_MASK_8 = 0xFF;

    // ---- Clear masks for boon categories (slot 0) ----
    // Coinflip: bits 0-55 (coinflipDay[24] + deityCoinflipDay[24] + coinflipTier[8])
    uint256 internal constant BP_COINFLIP_CLEAR = ~uint256((1 << 56) - 1);
    // Lootbox: bits 56-111 (lootboxDay[24] + deityLootboxDay[24] + lootboxTier[8])
    uint256 internal constant BP_LOOTBOX_CLEAR =
        ~(uint256((1 << 56) - 1) << 56);
    // Purchase: bits 112-167 (purchaseDay[24] + deityPurchaseDay[24] + purchaseTier[8])
    uint256 internal constant BP_PURCHASE_CLEAR =
        ~(uint256((1 << 56) - 1) << 112);
    // Decimator: bits 168-199 (decimatorTier[8] + deityDecimatorDay[24])
    uint256 internal constant BP_DECIMATOR_CLEAR =
        ~(uint256((1 << 32) - 1) << 168);
    // Whale: bits 200-255 (whaleDay[24] + deityWhaleDay[24] + whaleTier[8])
    uint256 internal constant BP_WHALE_CLEAR = ~(uint256((1 << 56) - 1) << 200);

    // ---- Clear masks for boon categories (slot 1) ----
    // Deity pass: bits 72-127 (deityPassTier[8] + deityPassDay[24] + deityDeityPassDay[24])
    uint256 internal constant BP_DEITY_PASS_CLEAR =
        ~(uint256((1 << 56) - 1) << 72);
    // Lazy pass: bits 128-183 (lazyPassDay[24] + deityLazyPassDay[24] + lazyPassTier[8])
    uint256 internal constant BP_LAZY_PASS_CLEAR =
        ~(uint256((1 << 56) - 1) << 128);

    // =========================================================================
    // Boon Tier <-> BPS Decode/Encode Helpers
    // =========================================================================

    /// @dev Decode coinflip tier to BPS. Tier: 0=0, 1=500, 2=1000, 3=2500.
    function _coinflipTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1000;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode lootbox boost tier to BPS. Tier: 0=0, 1=500, 2=1500, 3=2500.
    function _lootboxTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1500;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode purchase boost tier to BPS. Tier: 0=0, 1=500, 2=1500, 3=2500.
    function _purchaseTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 2500;
        if (tier == 2) return 1500;
        if (tier == 1) return 500;
        return 0;
    }

    /// @dev Decode decimator boost tier to BPS. Tier: 0=0, 1=1000, 2=2500, 3=5000.
    function _decimatorTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 5000;
        if (tier == 2) return 2500;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Decode whale boon tier to BPS. Tier: 0=0, 1=1000, 2=2000, 3=3500.
    function _whaleTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 3500;
        if (tier == 2) return 2000;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Shift of the degenerette lane for a supported bet currency (0=ETH, 1=FLIP).
    ///      Callers validate currency; the WWXRP ecosystem lane uses BP_WWXRP_LANE_SHIFT.
    function _degeneretteLaneShift(uint8 currency) internal pure returns (uint256) {
        return BP_DEGEN_LANE0_SHIFT + uint256(currency) * 24;
    }

    /// @dev Decode a degenerette lane tier to BPS (0-3 → 0/400/800/1200).
    function _degeneretteTierToBps(uint8 tier) internal pure returns (uint16) {
        return uint16(tier) * 400;
    }

    /// @dev Is this packed lane's boon live on `currentDay`? A deity-granted boon
    ///      dies at the end of its game day (22:57 UTC reset); a lootbox-rolled one lives
    ///      BOON_LANE_EXPIRY_DAYS past its stamp (a day-0 stamp is exempt from
    ///      the stamp rule, mirroring the sibling families). Day fields are 21-bit, so
    ///      both sides compare masked.
    function _boonLaneLive(
        uint256 lane,
        uint24 currentDay
    ) internal pure returns (bool) {
        if (lane & BP_LANE_TIER_MASK == 0) return false;
        uint256 day = (lane >> BP_LANE_DAY_SHIFT) & BP_LANE_DAY_MASK;
        uint256 nowDay = currentDay & BP_LANE_DAY_MASK;
        if (lane & BP_LANE_DEITY_BIT != 0) return day == nowDay;
        return day == 0 || nowDay <= day + BOON_LANE_EXPIRY_DAYS;
    }

    /// @dev Decode lazy pass boon tier to BPS. Tier: 0=0, 1=1000, 2=2500, 3=5000.
    function _lazyPassTierToBps(uint8 tier) internal pure returns (uint16) {
        if (tier == 3) return 5000;
        if (tier == 2) return 2500;
        if (tier == 1) return 1000;
        return 0;
    }

    /// @dev Encode coinflip BPS to tier. 500->1, 1000->2, 2500->3, else 0.
    function _coinflipBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 2500) return 3;
        if (bps >= 1000) return 2;
        if (bps >= 500) return 1;
        return 0;
    }

    /// @dev Encode purchase BPS to tier. 500->1, 1500->2, 2500->3, else 0.
    function _purchaseBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 2500) return 3;
        if (bps >= 1500) return 2;
        if (bps >= 500) return 1;
        return 0;
    }

    /// @dev Encode decimator BPS to tier. 1000->1, 2500->2, 5000->3, else 0.
    function _decimatorBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 5000) return 3;
        if (bps >= 2500) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Encode whale BPS to tier. 1000->1, 2000->2, 3500->3, else 0.
    function _whaleBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 3500) return 3;
        if (bps >= 2000) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Encode lazy pass BPS to tier. 1000->1, 2500->2, 5000->3, else 0.
    function _lazyPassBpsToTier(uint16 bps) internal pure returns (uint8) {
        if (bps >= 5000) return 3;
        if (bps >= 2500) return 2;
        if (bps >= 1000) return 1;
        return 0;
    }

    /// @dev Calculate mint count bonus points (max 25% for perfect participation).
    ///      Perfect participation (100% mints) always = 25 points (25%).
    /// @param mintCount Player's total level mint count.
    /// @param currLevel Current game level.
    /// @return Bonus points (0-25) scaled by participation percentage (integer division).
    function _mintCountBonusPoints(
        uint24 mintCount,
        uint24 currLevel
    ) internal pure returns (uint256) {
        if (currLevel == 0) return 0;
        if (mintCount >= currLevel) return 25;
        return (uint256(mintCount) * 25) / uint256(currLevel);
    }

    // =========================================================================
    // AfKing Subscriptions (game-resident; shared with the GameAfkingModule
    // and the AdvanceModule process STAGE)
    // =========================================================================
    // The subscriber set lives on the shared base so the process/open passes
    // operate on it in-context (plain SLOADs), with the per-sub box stamp read
    // back from the same record at open. The systemwide afking ETH total is
    // already carried inside `claimablePool` via the `afkingFunding` ledger
    // (declared above); no separate aggregate is introduced.

    /// @notice Per-wallet AfKing subscription record: the per-buy box stamp, the in-slot per-sub
    ///         accumulator and the wallet's position in the subscriber set.
    /// @dev Layout (Solidity packs sequentially) — exactly ONE 32-byte slot, so the whole record
    ///      reads/writes as a single warm slot with no extra cold slot:
    ///        config (16b):  dailyQuantity(8) + flags(8)
    ///        per-sub stamp (40b): score(16) + amount(24, milli-ETH)
    ///        markers (96b): lastAutoBoughtDay(24) + lastOpenedDay(24) + afkCoveredThroughDay(24) + afkingStartDay(24)
    ///        accumulator (72b): affiliateBase(32) + pendingFlip(24) + subStreakLatch(16)
    ///        set position (32b): 1-indexed position in `_subscribers` (0 = not in the set)
    ///      There is NO per-day epoch: the box resolves at the LIVE level at open (no
    ///      stored roll floor) and uses the active published session word. Every stamped box
    ///      must finish before the next request. The frozen per-sub inputs are
    ///      `score` (activity score) and `amount`
    ///      (mp×qty spend). `fundingSource` lives in the sparse `_fundingSourceOf` map
    ///      (absent ⇒ self, the common case stores nothing). `lastAutoBoughtDay`
    ///      double-duties as the success-marker AND the frozen seed `day`.
    ///      `amount` is stored in milli-ETH so it packs into uint24; the open unpacks it
    ///      back to wei before the box seed / EV-cap payout math. The stamp freezes the
    ///      box's SPEND and the seed `day`; the LEVEL and the EV-cap key read LIVE at
    ///      open, so the player cannot time the level. The milli-ETH round-down only
    ///      touches this recorded EV/seed input — the actual ETH/`claimablePool` debit
    ///      consumes the full wei `ethValue` and is never rounded.
    ///
    ///      Compute-on-read streak: `afkingStartDay` + `subStreakLatch`'s `streakAtAfkingStart`
    ///      (full uint16) frame the run; the effective afking quest streak is derived on read from
    ///      `afkCoveredThroughDay` (no DegenerusQuests STATICCALL on the buy path) and handed
    ///      back to the manual quest system on any sub-ending path (finalize).
    ///
    ///      In-slot accumulator (cheap per-buy; advanced by the per-buy accrue write into this
    ///      already-warm slot, so no new cold slot):
    ///        • `affiliateBase` — per-sub running unclaimed AFFILIATE balance, whole
    ///          FLIP; drained and paid out by `DegenerusAffiliate.claim`, zeroed there
    ///          so a re-claim finds 0.
    ///        • `pendingFlip` — per-sub running CLAIMABLE FLIP balance, whole FLIP,
    ///          accrued per delivered day (the slot-0 quest reward every mode + the
    ///          ticket-mode 10%/15% buyer bonus). Paid out only by the player-pull
    ///          `claimAfkingFlip`, zeroed there.
    ///        • `subStreakLatch` — the full uint16 afking-run streak base (snapshot + in-run secondaries).
    ///      `affiliateBase` is uint32 with a 100M-whole-FLIP saturating clamp and
    ///      `pendingFlip` is uint24 with a ~16.7M (2^24-1) saturating clamp at the accrue
    ///      write — each clamp binds before its field's type ceiling, and it can only ever
    ///      UNDER-credit a pathological high-volume whale (off the solvency path). The accumulator fields are written on
    ///      the buy-accrue path and the open markers (`lastOpenedDay`/`lastAutoBoughtDay`)
    ///      on the open path — disjoint fields in one warm slot, no collision.
    ///      There are no settle-day markers: the running balances self-mark, the pull has
    ///      no window, and the quest flush drains the counters so a double-fire finds 0.
    ///      `afkCoveredThroughDay` is a delivered-day high-water mark, not a settle
    ///      marker.
    struct Sub {
        // --- config (16 bits) ---
        /// @dev 0 = paused / never-subscribed; minimum 1 when active.
        uint8 dailyQuantity;
        /// @dev bit 0 = externalFunding; bit 1 = drainGameCreditFirst; bit 2 = useTickets.
        uint8 flags;
        // --- per-sub stamp (40 bits) ---
        /// @dev Stamp: the frozen activity score (the EV multiplier input at open).
        ///      Genuinely per-sub (each subscriber's own activity score).
        uint16 score;
        /// @dev Stamp: spend in milli-ETH (0.001-ETH units; boons off, so amount ==
        ///      spend, = mp × effectiveQty). Milli-ETH in a uint24 (16,777 ETH/buy of
        ///      headroom — a single auto-buy never approaches it); packed via
        ///      `_packEthToMilliEth` at the stamp write and unpacked via
        ///      `_unpackMilliEthToWei` before the box seed / EV-cap payout math. The
        ///      round-down is on this recorded EV/seed input only — the actual ETH debit
        ///      still uses the full wei `ethValue`.
        uint24 amount;
        // --- markers (96 bits) ---
        /// @dev Success-marker AND the frozen seed `day` (the same process day):
        ///      day index of the last successful buy, written only after a successful
        ///      afkingFunding debit. The open sources the box word from
        ///      `_recordedDailyWord(lastAutoBoughtDay)` and freezes this `day` in the seed.
        ///      uint24 day index ~ 45,000 years of headroom.
        uint24 lastAutoBoughtDay;
        /// @dev Day-keyed no-double-open marker: the open leg materializes a box only
        ///      while `lastOpenedDay < lastAutoBoughtDay`; after the open it sets
        ///      `lastOpenedDay = lastAutoBoughtDay`, making the predicate false until
        ///      the next successful buy advances `lastAutoBoughtDay`. The no-orphan
        ///      guard (process stage) keys on the same two day fields.
        ///      uint24 day index, same width as lastAutoBoughtDay.
        uint24 lastOpenedDay;
        /// @dev Delivered-day high-water mark: monotone, advanced only on a day whose
        ///      ETH debit actually fired (a skipped/un-debited day does not advance it).
        ///      The afking quest streak is computed ON READ from this marker (no
        ///      DegenerusQuests STATICCALL on the buy path): the effective streak is
        ///      `streakAtAfkingStart + (afkCoveredThroughDay - afkingStartDay)` while the
        ///      last funded day is no older than yesterday, else 0 (decay-on-read). Advanced
        ///      in the same warm slot accrue write. uint24 day index.
        uint24 afkCoveredThroughDay;
        /// @dev Day the current afking run's streak snapshot was taken — the base day for the
        ///      compute-on-read `afkCoveredThroughDay - afkingStartDay` span. Set at subscribe
        ///      (the funded day-0) and re-based on a gap-resumed delivered day; cleared at
        ///      finalize when streak control hands back to the manual quest system. uint24 day
        ///      index, same width as the other day markers.
        uint24 afkingStartDay;
        // --- in-slot accumulator (72 bits) ---
        /// @dev Per-sub running unclaimed affiliate balance, whole FLIP. Accrued a flat
        ///      7% per buy (one warm in-slot `+=`); drained and paid out by
        ///      `DegenerusAffiliate.claim`, zeroed there so a re-claim finds 0. uint32
        ///      with a 100,000,000-whole-FLIP saturating clamp at the accrue write
        ///      (uint32 holds ~4.29e9 > 100M, so the clamp binds first); the clamp can
        ///      only ever under-credit, off the solvency path.
        uint32 affiliateBase;
        /// @dev Per-sub running CLAIMABLE FLIP balance, whole FLIP. Accrued per
        ///      delivered day by the warm in-slot buy accrue: the slot-0 quest reward
        ///      (every mode) plus the ticket-mode 10%/15% buyer bonus. Paid out only by the
        ///      player-pull `claimAfkingFlip` (one creditFlip, zeroed there so a re-claim
        ///      finds 0); the sub claims whenever, so there is no settle/claim-timing edge.
        ///      uint24 with a ~16.7M (2^24-1) saturating clamp + under-credit-only
        ///      behaviour, same in kind as `affiliateBase`.
        uint24 pendingFlip;
        /// @dev `streakAtAfkingStart` — the afking-run streak base (0..65535): the snapshot at run
        ///      start plus the secondary/level completions the player makes during the run
        ///      (bumped via recordAfkingSecondary). The compute-on-read effective streak adds the
        ///      funded delivered days `(afkCoveredThroughDay - afkingStartDay)` to this base. Read
        ///      per buy as a mask op, so `affiliateBase`/`pendingFlip` stay unmasked for the hot
        ///      accrue.
        uint16 subStreakLatch;
        // --- set membership (32 bits) ---
        /// @dev 1-indexed position in `_subscribers`; 0 = not in the set. Swap-pop rewrites the
        ///      mover's record; delete clears it with the rest of the record.
        uint32 setPosition;
    }

    /// @dev `subStreakLatch` is the full uint16 — `streakAtAfkingStart` (0..65535). It carries the
    ///      run's pre-run snapshot plus the secondary/level completions the player makes during
    ///      the run (bumped via recordAfkingSecondary); the funded delivered days add on top of
    ///      this base. Clamped at uint16 max, far past where the activity-score caps make it matter.
    uint16 internal constant SUB_STREAK_MASK = 0xffff;

    /// @dev Read the afking-run streak base (the full packed latch uint16).
    function _streakBaseOf(Sub storage sub) internal view returns (uint16) {
        return sub.subStreakLatch & SUB_STREAK_MASK;
    }

    /// @dev Write the afking-run streak base, clamped to uint16 max so the live +1 bump
    ///      saturates instead of wrapping the field at the ceiling.
    function _setStreakBase(Sub storage sub, uint256 value) internal {
        sub.subStreakLatch = value > type(uint16).max ? type(uint16).max : uint16(value);
    }

    /// @dev Compute-on-read effective afking quest streak from the Sub slot — no DegenerusQuests
    ///      STATICCALL. The run's streak base (`streakAtAfkingStart`: snapshot + in-run
    ///      secondaries) plus the funded delivered days since the run's base day. A playable full
    ///      day without a funded delivery decays to 0; calendar days inside a pending unadvanced
    ///      gap are excluded because no subscriber could receive the daily delivery.
    function _afkingStreak(Sub storage sub, uint24 currentDay) internal view returns (uint32) {
        uint24 covered = sub.afkCoveredThroughDay;
        if (currentDay == 0) return 0;
        if (uint32(covered) + 1 < uint32(currentDay)) {
            uint24 sealedDay = dailyIdx;
            if (
                uint32(currentDay) <= uint32(sealedDay) + 1 ||
                covered < sealedDay ||
                _recordedDailyWord(sealedDay + 1) != 0
            ) return 0;
        }
        return uint32(_streakBaseOf(sub)) + uint32(covered - sub.afkingStartDay);
    }

    /// @dev The live (non-lapsed) afking streak for wallet `id` if it is mid-run; otherwise
    ///      (false, 0). A genuinely lapsed run, a sub with no active run, and a non-subscriber all return
    ///      (false, 0) so callers fall back to the manual streak — a lapsed-but-still-minting sub
    ///      is never zeroed. No DegenerusQuests STATICCALL on the live-run path.
    function _liveAfkingStreak(uint32 id) internal view returns (bool live, uint32 streak) {
        // `afkingStartDay` is set at run start and cleared at finalize (every sub-ending path),
        // and a non-subscriber's Sub slot is zero — so a non-zero start day alone identifies a
        // live run, off the single Sub-slot SLOAD _afkingStreak needs anyway. A paused/lapsed run
        // keeps a start day but _afkingStreak decays it to 0 below.
        Sub storage sub = _subOf[id];
        if (sub.afkingStartDay != 0) {
            uint32 a = _afkingStreak(sub, _simulatedDayIndex());
            if (a != 0) return (true, a);
        }
        return (false, 0);
    }

    /// @dev Single source of truth for a player's effective quest streak, so the activity score
    ///      is one unified value everywhere it is read. A live afking sub reads the Sub-side
    ///      compute-on-read (carrying the run's funded days + in-run secondaries); everyone else
    ///      (and a lapsed run) reads the manual decay-aware streak.
    function _effectiveQuestStreak(uint32 id) internal view returns (uint32) {
        // Most players are not afking subs, so learn the afking flag from the quest-streak read we
        // make anyway: a non-afker returns here with no Sub-slot lookup. Only an afking player pays
        // the extra Sub read for the compute-on-read (funded days + in-run secondaries); a lapsed
        // run falls back to the manual streak just read. ID 0 has no quest state: (0, false).
        (uint32 manualStreak, bool afking) = quests.effectiveBaseStreakAndAfking(id);
        if (!afking) return manualStreak;
        (bool live, uint32 a) = _liveAfkingStreak(id);
        return live ? a : manualStreak;
    }

    /// @dev Per-subscriber record by wallet ID: the per-sub stamp, the day markers (incl.
    ///      `afkingStartDay` / `afkCoveredThroughDay` for the compute-on-read streak), the in-slot
    ///      accumulator (affiliateBase / pendingFlip / subStreakLatch) and the set position.
    mapping(uint32 => Sub) internal _subOf;

    /// @dev Sparse funder ID keyed by subscriber ID — the account whose `afkingFunding` funds a sub.
    ///      Absent ⇒
    ///      self-funded (the common case, which stores NOTHING). Written at subscribe
    ///      (set-if-nonzero / delete-if-self) and read once per process iteration to resolve the
    ///      source (not needed at open — funding is already debited at process).
    mapping(uint32 => uint32) internal _fundingSourceOf;

    /// @dev Insertion-ordered subscriber IDs, eight per storage word. Cancellation uses swap-pop.
    ///      Mint history, affiliate claims and funding use IDs; stETH pulls resolve the owner at transfer.
    uint32[] internal _subscribers;

    /// @dev The two uint16 cursors + the uint24 afking reset-day pack into ONE slot
    ///      (16 + 16 + 24 = 56 bits). The cursors index `_subscribers` (every entry but the
    ///      two exempt protocol subscriptions burned an AFKing seat, and live seats plus set
    ///      entries never exceed the token's 2,000 cap, so the set stays well within uint16)
    ///      and are drained in chunks across advanceGame / router calls.
    /// @dev Process-STAGE cursor: the pre-RNG stamp pass position.
    uint16 internal _subCursor;

    /// @dev Open-leg cursor: the post-RNG box-open pass position (the
    ///      OPEN_BATCH-style router-category cursor).
    uint16 internal _subOpenCursor;

    /// @dev The day the process STAGE was last reset for. When the advance first enters
    ///      a new `day` with the lock down and `_recordedDailyWord(day)` still uncommitted
    ///      (`_afkingResetDay != day`), it resets `subsFullyProcessed` + the
    ///      `_subCursor` ONCE, before that day's STAGE drains — a forward-looking reset
    ///      (at the start of the new day, not trailing after the prior day completes),
    ///      firing exactly once per day regardless of which RNG path runs.
    uint24 internal _afkingResetDay;

    // =========================================================================
    // Human-Box Auto-Open Sweep State
    // =========================================================================

    /// @dev Next unsettled position in boxQueue[_rngReadBuffer()]. Stored before each entry's
    ///      rewards run, so an entry settles at most once; reset by the seal.
    uint48 internal boxCursor;

    /// @dev Box entries in the sealed read buffer, latched from the write count at the seal.
    uint32 internal boxReadCount;

    /// @dev Once-per-level latch for sDGNRS's automatic whale purchase: the level at which the
    ///      process STAGE already bought (DegenerusGameWhaleModule.purchaseWhalePassForSdgnrs,
    ///      up to a quarter of sDGNRS's claimable in whole groups of five passes). The STAGE
    ///      attempts the purchase once at its start (before the per-sub loop) while
    ///      `level > _sdgnrsBonusLevel` and stamps the level here on the ATTEMPT, bought or not —
    ///      one probe per level, so a too-poor first day buys nothing that level and no later
    ///      chunk/tx this level tries again. Level 0 is excluded (the latch starts at 0). Packs into the cursor slot (loaded for `_subCursor` every STAGE), so its
    ///      read/write is warm; a uint24 holds the full level range (matches `level`).
    uint24 internal _sdgnrsBonusLevel;

    /// @dev Count of stamped-but-unopened afking boxes (at most one per subscriber — the
    ///      no-orphan rule blocks re-stamping, eviction, reclaim, and funding-kill while a
    ///      box is pending, so the daily STAGE box stamps are the ONLY increment — batched
    ///      one add per STAGE chunk — and the box open the ONLY per-box decrement). The open worker
    ///      early-outs on zero, making a drained-ring "any work?" check O(1) instead of a full
    ///      ring scan; a full scan that finds no openable stamp clears the count. Packs into the
    ///      cursor slot (warm for both writers); uint16 covers the seat-bounded subscriber set.
    uint16 internal _pendingBoxCount;

    /// @dev Box purchase queue per physical RNG buffer (keys 0/1): one complete entry word per
    ///      purchase, appended to the write buffer and settled FIFO from `boxCursor` once the
    ///      buffer is sealed and its word published. Entries are never updated after their
    ///      append; the array index is the position. Entry `p` sits at
    ///      `keccak256(boxQueue[buffer].slot) + p`; the write count lives in lootboxRngPacked
    ///      and the read length in `boxReadCount`. Never use Solidity length, push, pop or
    ///      indexing on this mapping. A drained buffer is reused by resetting only its count.
    ///      Entry layout: the LB_* constants.
    mapping(uint48 => uint256[]) internal boxQueue;

    // =========================================================================
    // Foil Pack
    // =========================================================================

    /// @dev Four reusable pack slots per player, keyed by level & 3 and authenticated
    ///      by the full level at bits 208..231. Purchase freezes boost and activity, but no day.
    ///      Materialization writes four uint32 lines at bits 56..183, the first
    ///      eligible draw at bits 0..23, generation day at bits 184..207, and ready
    ///      at bit 255. Bit 232 marks gold paid. No historical reveal word is needed after generation.
    mapping(uint24 => mapping(uint32 => uint256)) internal foilRecord;

    /// @dev Two reusable day lanes per player, set before payout. Each 32-bit lane
    ///      stores its exact day [0..23] and four ticket claim bits [24..27].
    mapping(uint32 => uint256) internal foilMatchClaimed;

    /// @dev Two reusable draws keyed by day & 1: traits [0..31], level [64..87],
    ///      payout seed [88..215], seed-present flag 216, exact day [217..240].
    mapping(uint24 => uint256) internal dailyFoilDraw;

    /// @dev Foil read/write cohorts (keys 0/1), frozen at the daily request only.
    ///      New buys always append to the write half. Manually addressed: pack `p` of cohort
    ///      `key` sits at `keccak256(foilQueue[key].slot) + p`, and the cohort lengths are
    ///      foilWriteCount / foilReadCount. Never use Solidity length, push, pop or indexing.
    mapping(uint24 => uint256[]) internal foilQueue;

    /// @dev Resumable read cursor and cohort-wide generation/eligibility stamps.
    uint32 internal foilCursor;
    uint24 internal foilGenerationDay;
    uint24 internal foilFirstDrawDay;
    /// @dev Foil cohort write toggle. Flips at a daily request or the one terminal swap,
    ///      never at a mid-day request, so packs always generate from a daily word.
    bool internal foilWriteSlot;
    /// @dev Packs in the write cohort and in the sealed read cohort. `_swapFoilSlot` swaps the
    ///      two with the cohorts themselves; a completed drain zeroes the read count. A buy
    ///      writes its count into this slot, which `_foilWriteKey` already loaded.
    uint32 internal foilWriteCount;
    uint32 internal foilReadCount;

    /// @dev Lifetime count of deity boons issued from a given deity to a given
    ///      recipient, keyed [deity][recipient]. Capped at DEITY_RECIPIENT_BOON_CAP
    ///      in issueDeityBoon.
    mapping(uint32 => mapping(uint32 => uint8)) internal deityRecipientBoonCount;

    /// @dev 75/25 next/future split for the foil leg (forked from the 90/10
    ///      ticket split's PURCHASE_TO_FUTURE_BPS = 1000).
    uint16 internal constant FOIL_TO_FUTURE_BPS = 2500;

    /// @dev A foil pack resolves a fixed 16 boosted entries (4 tickets x 4
    ///      quadrants). The drain resolves this many per queued buyer.
    uint32 internal constant FOIL_PACK_ENTRIES = 16;

    /// @dev The foil SKU is priced at ten ticket prices and records ten mint units
    ///      (price-equivalent activity, not the four packed tickets). Shared by the
    ///      mint-path cost computation and the foil delivery module.
    uint256 internal constant FOIL_PACK_TICKETS = 10;

    uint256 private constant _FOIL_RESOLVEDAY_MASK = (uint256(1) << 24) - 1;
    uint256 internal constant _FOIL_MULT_SHIFT = 24;
    uint256 private constant _FOIL_MULT_MASK = (uint256(1) << 16) - 1;
    uint256 internal constant _FOIL_SCORE_SHIFT = 40;
    uint256 private constant _FOIL_SCORE_MASK = (uint256(1) << 16) - 1;

    uint256 internal constant _FOIL_LINES_SHIFT = 56;
    uint256 internal constant _FOIL_GENERATED_DAY_SHIFT = 184;
    uint256 internal constant _FOIL_LEVEL_SHIFT = 208;
    uint256 internal constant _FOIL_GOLD_CLAIMED = uint256(1) << 232;
    uint256 internal constant _FOIL_READY = uint256(1) << 255;

    uint256 private constant _FOIL_DRAW_MAIN_MASK = (uint256(1) << 32) - 1;
    uint256 private constant _FOIL_DRAW_LEVEL_SHIFT = 64;
    uint256 private constant _FOIL_DRAW_LEVEL_MASK = (uint256(1) << 24) - 1;
    uint256 internal constant _FOIL_DRAW_SEED_SHIFT = 88;
    uint256 internal constant _FOIL_DRAW_SEEDED = uint256(1) << 216;
    uint256 internal constant _FOIL_DRAW_DAY_SHIFT = 217;
    bytes32 internal constant FOIL_PAYOUT_SEED_TAG = keccak256("foil-payout-seed");

    /// @dev Domain-separated seed for the drain-side match-line roll, so the foil
    ///      tuples derive from a keccak lane disjoint from the normal-ticket LCG
    ///      seeds and the daily winning-set derivation.
    bytes32 internal constant FOIL_SEED_TAG = keccak256("foil-seed");

    /// @dev Claim-side entropy lanes off the retained daily word — distinct keccak
    ///      domains from each other. FOIL_CCY_TAG rolls the
    ///      40/40/20 currency split; FOIL_SPIN_TAG seeds the Degenerette box-spin the
    ///      tier magnitude is staked into.
    bytes32 internal constant FOIL_CCY_TAG = keccak256("foil-currency");
    bytes32 internal constant FOIL_SPIN_TAG = keccak256("foil-spin");

    /// @dev A player's foil record; resolveDay now means first eligible draw day.
    ///      Pending records have day zero; generated lines are stored, never re-derived.
    /// @dev A player's foil record for a cycle level (one SLOAD): the frozen boost
    ///      and the first eligible draw day pinned at materialization. The boost/activity
    ///      fields make a pending purchase present even while its day is zero.
    function _foilRecordFor(uint32 id, uint256 lvl)
        internal
        view
        returns (bool present, uint16 multBps, uint24 resolveDay, uint16 activityScore)
    {
        uint256 packed = _foilRecordWord(id, uint24(lvl));
        present = packed != 0;
        resolveDay = uint24(packed & _FOIL_RESOLVEDAY_MASK);
        multBps = uint16((packed >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK);
        activityScore = uint16((packed >> _FOIL_SCORE_SHIFT) & _FOIL_SCORE_MASK);
    }

    /// @dev The frozen activity multiplier from a player's foil record for a cycle
    ///      level (one SLOAD); 0 when the player holds no pack for the cycle. The
    ///      queue drain reads only this field to boost the resolved entries.
    function _foilMultFor(uint32 id, uint256 lvl) internal view returns (uint16) {
        return uint16(
            (_foilRecordWord(id, uint24(lvl)) >> _FOIL_MULT_SHIFT) & _FOIL_MULT_MASK
        );
    }

    function _foilWriteKey() internal view returns (uint24) {
        return foilWriteSlot ? 1 : 0;
    }

    function _foilReadKey() internal view returns (uint24) {
        return foilWriteSlot ? 0 : 1;
    }

    /// @dev Paid read-side work must finish before its committed word is released.
    function _foilDrainPending() internal view returns (bool) {
        return foilCursor < foilReadCount;
    }

    /// @dev Packs queued in cohort `key` (0/1).
    function _foilCount(uint24 key) internal view returns (uint256) {
        return key == _foilWriteKey() ? foilWriteCount : foilReadCount;
    }

    /// @dev Slot of pack `position` in cohort `key`. Callers bound `position` by `_foilCount`.
    function _foilSlot(uint24 key, uint256 position) internal view returns (uint256 slot) {
        uint256[] storage q = foilQueue[key];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            slot := add(keccak256(0x00, 0x20), position)
        }
    }

    function _foilStoredLines(uint32 id, uint24 lvl) internal view returns (uint32[4] memory lines) {
        uint256 packed = _foilRecordWord(id, lvl) >> _FOIL_LINES_SHIFT;
        for (uint256 i; i < 4; ++i) lines[i] = uint32(packed >> (i * 32));
    }

    function _foilGoldClaimOpen(uint256 day) internal view returns (bool) {
        uint256 today = _simulatedDayIndex();
        return day != 0 && day <= today && today - day <= 1;
    }

    /// @dev The per-cycle one-pack cap: true iff the player already bought a foil
    ///      pack for this cycle. Keyed on the active ticket level — the same cycle
    ///      key the buy's record write and ticket queue use.
    function _foilBoughtThisLevel(uint32 id, uint256 lvl) internal view returns (bool) {
        return _foilRecordWord(id, uint24(lvl)) != 0;
    }

    /// @dev All logical pack reads authenticate the full level before using a recycled slot.
    function _foilRecordWord(uint32 id, uint24 lvl) internal view returns (uint256 packed) {
        packed = foilRecord[lvl & 3][id];
        if (uint24(packed >> _FOIL_LEVEL_SHIFT) != lvl) return 0;
    }

    /// @dev Only a new purchase may reuse a pack slot. Preserve pending materialization,
    ///      late-generated gold claims and both live match days, even across stalled/turbo
    ///      transitions. A collision rejects that purchase; it never blocks the advance.
    function _foilRecordReusable(uint256 packed) internal view returns (bool) {
        if (packed == 0) return true;
        uint24 oldLevel = uint24(packed >> _FOIL_LEVEL_SHIFT);
        if (packed & _FOIL_READY == 0 || oldLevel >= level
            || _foilGoldClaimOpen(uint24(packed >> _FOIL_GENERATED_DAY_SHIFT))) return false;
        uint24 today = _simulatedDayIndex();
        (, , uint24 todayLevel) = _foilDrawFor(today);
        (, , uint24 yesterdayLevel) = _foilDrawFor(today == 0 ? 0 : today - 1);
        return oldLevel != todayLevel && oldLevel != yesterdayLevel;
    }

    function _foilMatchAlreadyClaimed(uint32 id, uint24 day, uint256 ticketIndex)
        internal view returns (bool)
    {
        uint256 lane = foilMatchClaimed[id] >> (uint256(day & 1) * 32);
        return uint24(lane) == day && lane & (uint256(1) << (24 + ticketIndex)) != 0;
    }

    /// @dev Expiry is checked before this write. Replacing an old parity lane cannot
    ///      reopen that old day's claims, and preserves the other still-live day.
    function _markFoilMatchClaimed(uint32 id, uint24 day, uint256 ticketIndex) internal {
        uint256 shift = uint256(day & 1) * 32;
        uint256 packed = foilMatchClaimed[id];
        uint256 lane = uint32(packed >> shift);
        if (uint24(lane) != day) lane = day;
        lane |= uint256(1) << (24 + ticketIndex);
        foilMatchClaimed[id] = (packed & ~(uint256(type(uint32).max) << shift)) | (lane << shift);
    }

    /// @dev Seal the board and payout entropy together. The explicit flag admits a zero
    ///      truncated seed while rejecting old records that never stored payout entropy.
    function _packFoilDraw(uint32 mainSet, uint24 lvl, uint24 day, uint256 rngWord)
        internal pure returns (uint256)
    {
        uint256 seed = uint128(uint256(keccak256(abi.encode(rngWord, day, FOIL_PAYOUT_SEED_TAG))));
        return uint256(mainSet) | (uint256(lvl) << _FOIL_DRAW_LEVEL_SHIFT)
            | (seed << _FOIL_DRAW_SEED_SHIFT) | _FOIL_DRAW_SEEDED
            | (uint256(day) << _FOIL_DRAW_DAY_SHIFT);
    }

    /// @dev Exact-tag lookup, deliberately without a wall-age gate: an in-flight
    ///      purchase jackpot can still need its sealed logical day after a stall.
    function _foilDrawWord(uint256 day) internal view returns (uint256 packed) {
        if (day == 0 || day > type(uint24).max) return 0;
        packed = dailyFoilDraw[uint24(day) & 1];
        if (uint24(packed >> _FOIL_DRAW_DAY_SHIFT) != day) return 0;
    }

    /// @dev Unpack the daily foil draw for a day (one SLOAD). present = (slot !=
    ///      0); a sealed day always has a nonzero level.
    function _foilDrawFor(uint256 day)
        internal
        view
        returns (bool present, uint32 mainSet, uint24 lvl)
    {
        uint256 packed = _foilDrawWord(day);
        present = packed != 0;
        mainSet = uint32(packed & _FOIL_DRAW_MAIN_MASK);
        lvl = uint24((packed >> _FOIL_DRAW_LEVEL_SHIFT) & _FOIL_DRAW_LEVEL_MASK);
    }

    /// @dev Golden-ticket cross-day state, one packed slot (appended so every
    ///      prior slot keeps its index). Armed on a 4-gold main board (jackpot
    ///      phase); resolved by the next main-board draw. Written and read only by
    ///      the advance-driven jackpot draw (JackpotModule) off the sealed word —
    ///      no player entrypoint touches it.
    ///      Layout (LSB up):
    ///      [31:0]    armed winner wallet ID (solo bucket winner of the arm day)
    ///      [159:32]  zero
    ///      [161:160] armed solo quadrant
    ///      [164:162] armed solo symbol (official, post-hero)
    ///      [188:165] armedIdx — frozen dailyIdx during the arm draw
    ///      [189]     armed flag
    ///      [190]     resolve-day ban flag (keeps the hero ban stable for the
    ///                resolve day's later re-rolls after the armed fields are
    ///                cleared or overwritten by a same-day chain arm)
    ///      [192:191] resolve-day ban quadrant
    ///      [216:193] resolve-day ban idx — frozen dailyIdx of the resolve draw
    uint256 internal goldenTicket;

    /// @dev Unspent mid-day RNG credit per donor, in juels of donated LINK (appended so
    ///      every prior slot keeps its index). Held in LINK because LINK is what the
    ///      subscription is billed in, so a balance means exactly what it says: the LINK
    ///      this donor put in and has not yet spent against.
    ///      A redemption debits MIDDAY_RNG_CHARGE_MULT times what the request itself
    ///      bills, priced at redemption rather than banked at a fixed rate — so the
    ///      balance buys fewer requests when gas is expensive and more when it is cheap.
    mapping(uint32 => uint256) internal middayRngCredit;

    /// @dev Achieved prize pool of every completed century level (x00) — the pre-skim
    ///      nextPrizePool recorded at each x00 purchase→jackpot transition — in completion
    ///      order, so century N sits at index N-1 (appended so every prior slot keeps its
    ///      index). levelPrizePool[x00] cannot serve as this history: _endPhase overwrites
    ///      it with 40% of futurePool as the reachable x01 ratchet base, so the achieved value
    ///      survives only here.
    ///
    ///      Two readers, both needing the value past that overwrite. _prizePoolTarget
    ///      takes the newest entry as the century floor, so each century jackpot must
    ///      outgrow the last. _growthRatchet takes the entry for a specific century, so
    ///      the growth market prices a boundary round against real growth — and, because
    ///      an entry is written once and never revisited, a settled round's answer can
    ///      never change.
    uint128[] internal centuryPrizePools;

    /// @dev The seats a ticket drain left occupied when its write budget ran out: up to
    ///      eight queue indices plus one (lane j = bits 32j..32j+31, zero = empty), in queue
    ///      order, for the queue named by ticketLevel. The next chunk re-seats them and
    ///      resumes filling from ticketCursor, which is the scan FRONTIER (every index below
    ///      it is exhausted or seated), so exhausted holes are never rescanned and a
    ///      long-lived seat can never pin the cursor. Cleared at queue release.
    uint256 internal ticketSeats;

    /// @dev Inclusive lower block bound for a level's first generation window. Level 1
    ///      starts at deployment (level 0 never holds tickets); level L+1 starts when level
    ///      L first requests fresh mid-day RNG after meeting its goal, or its last purchase day latches, before
    ///      any drain can execute for that window. Written once per
    ///      level OUTSIDE charged drain steps. Permanent rather than a recycling ring:
    ///      old levels remain claimable in Bingo and must retain their discovery bound.
    ///      The uint256 mapping key uses the same 32-byte ABI encoding as a uint24 level.
    ///      Read via extsload(keccak256(abi.encode(uint256(lvl), this mapping's slot))).
    ///      Off-chain metadata; on-chain writers only preserve an already-set bound. It gates
    ///      no generation or payout. An unreached level reads 0, which means "window not open", NOT
    ///      "scan from genesis". The bound covers TRAIT GENERATION only; it does not
    ///      bound EntryOwnerRegistered, which far-future queueing can emit up to 99
    ///      levels ahead of the level whose window this stamps.
    mapping(uint256 => uint256) internal ticketGenerationStartBlock;

    // =========================================================================
    // Deterministic (VRF-dead) ending — GameOverModule _tallyDeadVrf / claimDeadVrf
    // =========================================================================
    // One slot of tally state, then one slot of payout state, then the claimed bitmap.
    // All zero for the life of the game; written only once the dead ending latches.

    /// @dev Tally cursor within one terminal ticket queue; deadTallyFoilDay selects the queue during stage 0.
    uint32 internal deadTallyPos;

    /// @dev Tally cursor over the undrained foil buckets: the resolve day being counted.
    uint24 internal deadTallyFoilDay;

    /// @dev Tally cursor over the undrained foil buckets: the next index in that day's bucket.
    uint32 internal deadTallyFoilIdx;

    /// @dev Tally stage: 0 queued entries, 1 foil packs, 2 trait buckets, 3 finished.
    uint8 internal deadTallyStage;

    /// @dev How many of the terminal level's 256 trait buckets hold at least one ticket.
    uint16 internal deadTraitCount;

    /// @dev Uncreated weight: every queued entry and undrained foil pack of the terminal level,
    ///      in QTY_SCALE units (an entry is QTY_SCALE; a fractional remainder its fraction).
    uint64 internal deadUncreated;

    /// @dev Created tickets: the terminal level's total trait-bucket occurrences.
    uint64 internal deadCreated;

    /// @dev The pot every terminal-level ticket shares, fixed when the dead ending pays out.
    uint128 internal deadPot;

    /// @dev Total weight the pot divides by: deadCreated * QTY_SCALE + deadUncreated.
    uint64 internal deadTotal;

    /// @dev Uncreated weight not yet claimed; each uncreated claim debits it, so claims can
    ///      never exceed what the tally counted.
    uint64 internal deadUncreatedLeft;

    /// @dev Claimed bits for created tickets: key (trait << 64) | (occurrence >> 8), bit
    ///      occurrence & 255.
    mapping(uint256 => uint256) internal deadClaimed;

    /// @dev FIFO of sealed Decimator battles: head in bits 0..23, tail in 24..47.
    uint256 internal decBattleQueue;

    /// @dev Bit t identifies a trait header initialized for ticketBufferLevels[parity].
    ///      Cleared only on successful buffer takeover; owner index zero remains valid.
    uint256[2] internal traitBucketLive;

    /// @dev ticketPending[id] holds even A/B then odd A/B in bits0..167.
    ///      Even/odd level tags occupy bits168..215.
    ///      Bit255 stays nonzero after all lanes and tags are consumed.
    mapping(uint32 => uint256) internal ticketPending;

    /// @dev Transient batch cursor plus one. Zero means no Degenerette worker is active.
    ///      Serializes callbacks and keeps in-flight bet views consistent without entry writes.
    bytes32 private constant DEGENERETTE_ACTIVE_CURSOR = keccak256("degenerus.degenerette.active.cursor");

    function _activeDegeneretteCursor() internal view returns (uint256 active) {
        bytes32 slot = DEGENERETTE_ACTIVE_CURSOR;
        assembly ("memory-safe") { active := tload(slot) }
    }

    function _setActiveDegeneretteCursor(uint256 active) internal {
        bytes32 slot = DEGENERETTE_ACTIVE_CURSOR;
        assembly ("memory-safe") { tstore(slot, active) }
    }

    function _loadDecEntry(uint24 lvl, uint64 id) internal view returns (uint256) {
        if (id == 0) return 0;
        uint256 p = uint256(id) - 1;
        return uint128(decBattleEntries[(uint256(lvl) << 64) | (p >> 1)] >> ((p & 1) * 128));
    }

    function _storeDecEntry(uint24 lvl, uint64 id, uint256 word) internal {
        if (id == 0) revert E();
        uint256 p = uint256(id) - 1;
        uint256 key = (uint256(lvl) << 64) | (p >> 1);
        uint256 shift = (p & 1) * 128;
        uint256 lane = uint128(word);
        decBattleEntries[key] = (decBattleEntries[key] & ~(uint256(type(uint128).max) << shift)) | (lane << shift);
    }

    /// @dev The shared session payload is usable by lootbox consumers only after fulfillment.
    ///      Daily callback stores its final nudge; the keeper publishes readiness and unlock retains it.
    function _lootboxWord(uint48 buffer) internal view returns (uint256) {
        return buffer == _rngReadBuffer() && _rngSessionPublished() ? _currentRngWord() : 0;
    }

    /// @dev References are physical buffer tags, never increasing generations.
    function _lootboxBufferValid(uint48 buffer) internal pure returns (bool) { return buffer < 2; }

    /// @dev Slot of Degenerette bet `position` (zero-based) in `buffer`.
    function _betSlot(uint48 buffer, uint256 position) internal view returns (uint256 slot) {
        uint256[] storage q = degeneretteQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            slot := add(keccak256(0x00, 0x20), shr(1, position))
        }
    }

    function _loadDegeneretteBet(uint48 buffer, uint256 position) internal view returns (uint256) {
        uint256 slot = _betSlot(buffer, position);
        uint256 word;
        assembly ("memory-safe") { word := sload(slot) }
        return uint128(word >> ((position & 1) * 128));
    }

    function _storeDegeneretteBet(uint48 buffer, uint256 position, uint256 bet) internal {
        uint256 slot = _betSlot(buffer, position);
        uint256 shift = (position & 1) * 128;
        uint256 lane = uint128(bet);
        assembly ("memory-safe") {
            sstore(slot, or(and(sload(slot), not(shl(shift, 0xffffffffffffffffffffffffffffffff))), shl(shift, lane)))
        }
    }

    function _lootboxReadComplete() internal view virtual returns (bool) {
        return _rngComplete();
    }

    /// @dev One ordering authority for keeper and manual read consumers. The read
    ///      cohort alone determines the stage; fresh write-side work cannot cut in.
    ///      0 blocked, 1 redemption, 2 AFKing, 3 human boxes, 4 Degenerette,
    ///      5 Decimator, 6 read-bound Craps, 7 drained. Timed claims are independent.
    function _rngConsumerStage() internal view returns (uint8) {
        uint256 packed = lootboxRngPacked;
        if (gameOver || rngLockedFlag || _rngRequestActive()
            || rngFlagsAndNudges & (uint16(1) << 13) != 0 || _livenessTriggered()) return 0;
        // Preparation stamps belong to the NEXT commitment and cannot reopen old work.
        if (_rngComplete()) return 7;
        if (!_rngSessionPublished()
            || _currentRngWord() == 0 || !ticketsFullyProcessed
            || ((packed >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK) != 0) return 0;
        if (IsDGNRS(ContractAddresses.SDGNRS).redemptionSettlementPending()) return 1;
        if (_pendingBoxCount != 0) return 2;
        if (!humanReadComplete) return 3;
        if (degeneretteCursor < degeneretteReadCount) return 4;
        if (decBattleQueue != 0) return 5;
        if (packed & (uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer())) != 0) return 6;
        return 7;
    }

    /// @dev Checked only at consumer-completion transitions, never by a fresh request.
    function _rngConsumersComplete() internal view returns (bool) {
        uint256 packed = lootboxRngPacked;
        if (!_rngSessionPublished() || _currentRngWord() == 0 || !ticketsFullyProcessed
            || ((packed >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK) != 0 || !humanReadComplete
            || degeneretteCursor < degeneretteReadCount
            || _pendingBoxCount != 0 || decBattleQueue != 0) return false;
        if (IsDGNRS(ContractAddresses.SDGNRS).redemptionSettlementPending()) return false;
        return packed & (uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer())) == 0;
    }

    /// @dev Daily work must seal too. A delivered word with unpaid consumers is not complete.
    ///      Reverts in a consumer's effects roll this marker back with the rest of that transaction.
    function _tryCompleteRng() internal {
        if (_rngComplete() || rngLockedFlag || _rngRequestActive() || !_rngSessionPublished()) return;
        if (_rngConsumersComplete()) _setRngComplete(true);
    }
    uint256 internal constant LR_CRAPS_PENDING_SHIFT = 250;

    function _ticketBufferLevel(uint24 lvl) internal view returns (uint24 result) {
        assembly ("memory-safe") {
            result := and(shr(add(mul(ticketBufferLevels.offset, 8), mul(and(lvl, 1), 24)), sload(ticketBufferLevels.slot)), 0xffffff)
        }
    }

    function _setTicketBufferLevel(uint24 lvl) internal {
        uint256 shift = (lvl & 1) * 24;
        if (uint24(uint256(ticketBufferLevels) >> shift) != lvl) traitBucketLive[lvl & 1] = 0;
        ticketBufferLevels = uint48((uint256(ticketBufferLevels) & ~(uint256(type(uint24).max) << shift))
            | (uint256(lvl) << shift));
    }

    function _ticketLevelRetired(uint24 lvl) internal view returns (bool) {
        return _ticketBufferLevel(lvl) > lvl;
    }

    function _assertReadableTicketLevel(uint24 lvl) internal view {
        if (_ticketLevelRetired(lvl)) revert E();
    }

    function _traitBufferBase(uint24 lvl) internal pure returns (uint256 base) {
        assembly ("memory-safe") {
            mstore(0, and(lvl, 1))
            mstore(32, lvlTraitEntry.slot)
            base := keccak256(0, 64)
        }
    }

    /// @dev Every production append adds at least one entry, and entries are never
    ///      removed from an active level. Its live bit therefore proves gold six was
    ///      taken without reading the bucket header. Authenticate the full level so
    ///      recycled parity buffers cannot carry the cap into a later level.
    function _goldSixTaken(uint24 lvl) internal view returns (bool) {
        uint24 storedLevel = _ticketBufferLevel(lvl);
        if (storedLevel > lvl) revert E();
        return storedLevel == lvl && traitBucketLive[lvl & 1] & (uint256(1) << GoldSixLib.TRAIT) != 0;
    }

    function _bucketLength(uint24 lvl, uint256 trait) internal view returns (uint256) {
        _assertReadableTicketLevel(lvl);
        return _bucketLengthUnchecked(lvl, trait);
    }

    /// @dev Caller has validated the level before any empty-bucket/deity branch.
    function _bucketLengthUnchecked(uint24 lvl, uint256 trait) internal view returns (uint256 count) {
        uint256 elem = _traitBufferBase(lvl) + trait;
        assembly ("memory-safe") {
            let parity := and(lvl, 1)
            let shift := add(mul(ticketBufferLevels.offset, 8), mul(parity, 24))
            if eq(and(shr(shift, sload(ticketBufferLevels.slot)), 0xffffff), lvl) {
                if and(sload(add(traitBucketLive.slot, parity)), shl(trait, 1)) {
                    count := and(sload(elem), 0xffffffff)
                }
            }
        }
    }

    /// @dev The chronological foil worker already drained older packs before this buyer.
    ///      It must not block itself on the current global foil backlog.
    function _prepareTicketLevelAfterFoil(uint24 lvl) internal returns (bool) {
        uint24 slot = lvl & 1;
        uint24 old = _ticketBufferLevel(slot);
        if (old == lvl) return true;
        if (old > lvl || lvl == 0) return false;
        bool terminal = gameOver || _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0
            || _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0;
        // The freeze protects the payout cohort. Its first preparation is still required;
        // unrelated older inventory is outside the established terminal payout scope.
        if (terminal && lvl != _gameOverTicketLevel(level)) return false;
        if (old != 0 && !terminal) {
            // level is completed during purchase phase, live during jackpot phase.
            if (old > level || (old == level && jackpotPhaseFlag)) return false;
            if (_ticketQueueLength(old) != 0 || _ticketQueueLength(old | TICKET_SLOT_BIT) != 0
                || _ticketQueueLength(_tqFarFutureKey(old)) != 0) return false;
            if ((ticketLevel & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT)) == old
                && ticketSeats != 0) return false;
        }
        if (old != 0 && (ticketLevel & ~(TICKET_SLOT_BIT | TICKET_FAR_FUTURE_BIT)) == old) {
            ticketLevel = 0;
            ticketCursor = 0;
            ticketSoloOffset = 0;
        }
        _setTicketBufferLevel(lvl);
        return true;
    }

    /// @dev The ratchet entry for `lvl` as the growth market must see it: a century level
    ///      reads its pushed achieved pool rather than the overwritten levelPrizePool
    ///      entry, so growth across a century boundary measures the game and not the
    ///      reset artifact.
    ///
    ///      Returns 0 for a century that has not completed. That is the point: the market
    ///      treats a zero successor entry as "not settled yet", and a bare index would
    ///      revert out of bounds instead, bricking the read. Level 0 is excluded from the
    ///      century branch so the genesis round keeps reading BOOTSTRAP_PRIZE_POOL.
    function _growthRatchet(uint24 lvl) internal view returns (uint256) {
        if (lvl != 0 && lvl % 100 == 0) {
            uint256 idx = lvl / 100 - 1;
            return
                idx < centuryPrizePools.length
                    ? uint256(centuryPrizePools[idx])
                    : 0;
        }
        return levelPrizePool[lvl];
    }

    /// @dev One resumable jackpot leg. The existing session lock freezes its word
    ///      and source buckets; only pricing and payout progress need persistence.
    struct JackpotWork {
        uint128 budget;
        uint128 paid;
        uint32 traits;
        uint24 lvl;
        uint16 winner;
        uint8 kind;
        uint8 quadrant;
        bool finalDay;
        // Main daily only: completed whole-ticket rounds for the current batch.
        // These fields fit in the existing second word of JackpotWork.
        uint32 directTicketRound;
        bool directTickets;
    }
    JackpotWork internal jackpotWork;

    /// @dev 100 circular level lanes per owner: owed[0:29], snap[30], present[31].
    mapping(uint32 => uint256[13]) internal farFutureOwed;

    /// @dev Previous nonempty sealed original field; generated jackpot entries never enter it.
    uint64 internal decPreviousStack;
    uint40 internal decPreviousCount;

    /// @dev Mode 0: original-only; 1: awaiting jackpot pricing; 2: fixed/funded.
    ///      One word per jackpot round; pricing inputs are carried by the plan event.
    struct DecJackpotPlan {
        uint128 soloAmount; // Solo cash/pass budget after matching; unpaid surplus is swept.
        uint64 weights;
        uint40 generatedEntries;
        uint16 cursor; // Sampled strata completed in the locked phase.
        uint8 mode;
    }
    mapping(uint24 => DecJackpotPlan) internal decJackpotPlans;
    /// @dev Drawn owner wallet IDs keyed by generated ordinal (1..original count), reused across
    ///      rounds. Only retained candidates write; every entry runs once and the shared heap has
    ///      one active round.
    mapping(uint256 => uint32) internal decGeneratedOwners;

    function _decAutomaticCap() internal view returns (uint256) {
        return decPreviousCount == 0 ? 8000 : uint256(decPreviousStack) * 4 / decPreviousCount;
    }

    error AfkingStethPullFailed();
    /// @dev Forward identity lookup for address-boundary authorization and ERC20 integration.
    ///      Mint statistics are stored separately by ID; only ordinary-wallet registration writes this.
    // Low 32 bits: current gameplay account. High 32: immutable wallet identity.
    mapping(address => uint64) internal walletIds;
    /// @dev Explicit account-to-account funding consent, independent of external operator rights.
    mapping(uint32 => mapping(uint32 => bool)) internal afkingFundingApprovals;

    /// @dev Ordinary main: address only; child: parent only; acquired root: seller + buyer.
    ///      Children can have only one ordinary parent, so one parent read is sufficient.
    function _acquiredRoot(uint32 id, uint256 element) internal view returns (uint32) {
        uint32 parent = uint32(element >> 160);
        if (parent == 0) return 0;
        if (uint160(element) != 0) return id;
        return uint32(_walletElement(parent) >> 160) == 0 ? 0 : parent;
    }

    function _isAcquired(uint32 id) internal view returns (bool) {
        return _acquiredRoot(id, _walletElement(id)) != 0;
    }

    function _acquiredBuyer(uint32 id) internal view returns (uint32) {
        uint256 element = _walletElement(id);
        uint32 root = _acquiredRoot(id, element);
        if (root == 0) return 0;
        if (root != id) element = _walletElement(root);
        return uint32(element >> 160);
    }

    function _ownerWalletId(uint32 id) internal view returns (uint32) {
        uint32 ownerId = uint32(_walletElement(id) >> 160);
        if (ownerId == 0) return id;
        uint32 parent = uint32(_walletElement(ownerId) >> 160);
        return parent == 0 ? ownerId : parent;
    }

    function _afkingFundingAllowed(uint32 subscriberId, uint32 funderId) internal view returns (bool) {
        if (_isAcquired(subscriberId) || _isAcquired(funderId)) return false;
        return subscriberId == funderId || afkingFundingApprovals[funderId][subscriberId]
            || _ownerWalletId(subscriberId) == _ownerWalletId(funderId);
    }
}
