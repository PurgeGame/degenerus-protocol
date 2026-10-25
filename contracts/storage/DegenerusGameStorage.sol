// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {EntropyLib} from "../libraries/EntropyLib.sol";
import {RngTags} from "../libraries/RngTags.sol";

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
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {BoundedCall} from "../libraries/BoundedCall.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
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

    function minerMaintenancePending_g11976() external view returns (bool);
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
 *   - GameBingo (inherited Game entry points)
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
 * | [3:6]   dailyIdx                 uint24   Most recently accepted logical round |
 * | [6:12]  rngRequestTime           uint48   When last VRF request was fired       |
 * | [12:15] level                    uint24   Current jackpot level (starts at 0)   |
 * | [15:16] jackpotPhaseFlag         bool     Payout mode: purchase(F)/jackpot(T)   |
 * | [16:17] jackpotCounter           uint8    Jackpots processed this level         |
 * | [17:18] lastPurchaseDay          bool     Prize target met flag                 |
 * | [18:19] decimatorFlags          uint8    bit0=window open, bit1=opening day, bit2=loans due |
 * | [19:20] rngLockedFlag            bool     Daily RNG lock (jackpot window)       |
 * | [20:21] phaseTransitionActive    bool     Level transition in progress          |
 * | [21:22] gameOver                 bool     Terminal state flag                   |
 * | [22:23] dailyJackpotCoinTicketsPending bool Split jackpot pending flag          |
 * | [23:24] jackpotFlags    uint8    bit0=turbo bit1=bonus owed          |
 * | [24:25] ticketsFullyProcessed    bool     Read slot fully drained flag          |
 * | [25:26] ticketWriteSlot          bool     Double-buffer write toggle            |
 * | [26:27] prizePoolFrozen          bool     Prize pool freeze active flag         |
 * | [27:28] degenesisClosed          uint8    Degenesis cohorts closed (0..7)       |
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
 * Fixed arrays: contiguous elements, using Solidity's usual packing rules.
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
 *    - purchaseStartDay = logical day 9 at level 0, excluding the seven Degenesis cohorts
 *    - jackpotPhaseFlag = false (purchase phase)
 *    - decimatorFlags = 0 (window opens at level 4 jackpot phase start)
 *    - levelPrizePool[level] is the per-level ratchet target; levelPrizePool[0] is set to
 *      BOOTSTRAP_PRIZE_POOL (50 ether) in the constructor (also the zero-fallback in the view)
 *
 * 5. OVERFLOW PROTECTION: Solidity 0.8+ provides automatic overflow checks.
 *    `unchecked` blocks in modules are intentional optimizations for safe ops.
 *
 * 6. TRAIT BUFFERS: A header is at lvlTraitEntry.slot + (level & 1) * 256 + traitId.
 *    The full buffer level and per-buffer bitmap validate it. Completed occurrence
 *    words begin at keccak256(headerSlot).
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

    uint256 internal constant SMURF_SCORE_PER_CREATION = 120;

    /// @dev Floor streak points for active pass holders (50 points).
    uint16 internal constant PASS_STREAK_FLOOR_POINTS = 50;

    /// @dev Floor mint count points for active pass holders (25 points).
    uint16 internal constant PASS_MINT_COUNT_FLOOR_POINTS = 25;

    /// @dev Conversion factor for FLIP token amounts (FLIP has 0 decimals).
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


    /// @dev Final purchase/rescue day after level 0; game-over is eligible the following day.
    uint24 internal constant _PURCHASE_TIMEOUT_DAYS = 30;

    /// @dev How long an unanswered VRF request — daily, or a mid-day one blocking the next
    ///      day's advance — may hold the game before the deterministic ending. Measured from the
    ///      original send: the vault owner's retry of a daily request and coordinator swaps do not
    ///      re-stamp. This is also the window a daily
    ///      stall straddling the purchase deadline has to recover in.
    uint48 internal constant _VRF_DEAD_TIMEOUT = 14 days;

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
    error SmurfCreationLimitReached();
    error InvalidSmurfBaseIncrease();
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
    ///      Initialized to logical day 9, after the seven Degenesis rounds.
    ///      Used for purchase timeout, distress mode and the future-pool take curve.
    ///
    ///      SECURITY: uint24 holds day indices up to ~16.7 million — effectively unlimited
    ///      for day-granularity counters.
    uint24 internal purchaseStartDay;

    /// @dev Most recently requested normal logical round. Bootstrap is day 1;
    ///      only an accepted fresh daily request increments it, exactly once.
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
    ///      clears bit 1; a retry preserves it. Bit 2 marks loans due at the level just entered
    ///      and still unseized. The flags share byte 18 and remain independent.
    uint8 internal decimatorFlags;
    uint8 internal constant DEC_WINDOW_OPEN = 1;
    uint8 internal constant DEC_DAY_ONE_ACTIVE = 2;
    uint8 internal constant LOANS_DUE_PENDING = 4;

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

    function _loansDuePending() internal view returns (bool) {
        return decimatorFlags & LOANS_DUE_PENDING != 0;
    }

    function _setLoansDuePending(bool pending) internal {
        decimatorFlags = pending ? decimatorFlags | LOANS_DUE_PENDING : decimatorFlags & ~LOANS_DUE_PENDING;
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

    /// @dev Degenesis cohorts closed, 0..7. The next cohort to price is Degenesis day
    ///      degenesisClosed + 1; reaching 7 burns the leftover Degenesis inventory. One byte in
    ///      slot 0 (LootboxCraps reads this slot's top bits).
    uint8 internal degenesisClosed;

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

    /// @dev Slot-0 bytes 30..31. Bits 0..7 hold the nudge count (0..65535); bit8 marks RNG
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

    /// @dev Logical day the request in flight belongs to, independent of transport/retry time;
    ///      zero for a mid-day request and on terminal entry until the terminal request.
    uint24 internal rngRequestDay;
    /// @dev True only after every consumer of the most recent daily request has finished.
    bool internal dailyComplete = true;

    /// @dev Timestamp of the last successfully processed VRF word.
    ///      Used by governance to detect VRF transport stalls; game liveness instead
    ///      reads the final daily completion timestamp.
    ///      Initialized in initVrf(), updated in _applyDailyRng(). Shares slot 4 with the
    ///      request day and the ticket buffer stamps.
    uint48 internal lastVrfProcessedTimestamp;
    /// @dev Even/odd ticket epochs: two uint24 levels, slot-4 bytes 10..15.
    uint48 internal ticketBufferLevels;
    /// @dev Next index of `_loansDue[level]` to seize while `LOANS_DUE_PENDING` is set;
    ///      slot-4 bytes 16..19.
    uint32 internal loanSeizeCursor;
    /// @dev Last resolved day the Game successfully settled the Vault through. A lower
    ///      bound on its actual Coinflip cursor; slot-4 bytes 20..22, preserving later roots.
    uint24 internal vaultFlipSettledDay;
    /// @dev Bits 0/1 invalidate the retained even/odd trait bitmap until its first append.
    uint8 internal traitBucketStale;
    /// @dev Exact round occupying the reusable Decimator entry words.
    uint24 internal decEntriesLevel;
    /// @dev Actual reset window of the last accepted daily request (slot 4, byte 27).
    uint24 internal lastDailyRequestWallDay;

    /// @dev Packed daily jackpot ticket data, handed from one advance stage to the next.
    ///      Layout: [reserved (8 bits @ 0)] [dailyEntries (64 bits @ 8)] [battlePending (1 bit @ 72)]
    ///              [retained (1 bit @ 73)] [unused (70 bits @ 74)] [earlyBirdEntries (64 bits @ 144)]
    ///              [purchaseEntries (48 bits @ 208)]
    ///      Jackpot phase: set by the ETH stage; on the early-bird day the early-bird stage
    ///      consumes the earlyBird field and clears it; the battle stage clears battlePending; the
    ///      coin+tickets stage consumes dailyEntries and retains the sentinel. Purchase phase: the
    ///      daily prices its ticket leg into the top field and the purchase ticket stage consumes
    ///      and clears it after the purchase battle stage consumes battlePending. Both phases use
    ///      the same battle bit and keep the RNG lock until their final stage. Every predicate
    ///      masks its own field.
    uint256 internal dailyTicketBudgetsPacked;
    uint256 internal constant DAILY_TICKET_BUDGET_RETAINED = 1 << 73;

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

    /// @dev Exact tag authentication also serves pinned processing days older than
    ///      yesterday. A committed word cannot be overwritten before consumers finish.
    function _recordedDailyWord(uint24 day) internal view returns (uint256) {
        uint256 shift = uint256(day & 1) * 24;
        if (day == 0 || uint24(uint256(rngDayTags) >> shift) != day) return 0;
        return rngWordByDay[day & 1];
    }

    /// @dev The active Degenesis cohort keeps its bound day's word past the two-day ring.
    function _recordDailyRng(uint24 day, uint256 word) internal {
        uint256 shift = uint256(day & 1) * 24;
        rngDayTags = uint48((uint256(rngDayTags) & ~(uint256(type(uint24).max) << shift)) | (uint256(day) << shift));
        rngWordByDay[day & 1] = word;
        if (degenesisClosed < DEGENESIS_DAYS && uint24(degenesisActive >> GA_DAY_SHIFT) == day) degenesisWord = word;
    }

    function _latestDailyResultDay() internal view returns (uint24) {
        uint24 a = uint24(rngDayTags);
        uint24 b = uint24(rngDayTags >> 24);
        return a > b ? a : b;
    }

    function _latestFoilDrawDay() internal view returns (uint24) {
        uint24 a = uint24(dailyFoilDraw[0] >> _FOIL_DRAW_DAY_SHIFT);
        uint24 b = uint24(dailyFoilDraw[1] >> _FOIL_DRAW_DAY_SHIFT);
        return a > b ? a : b;
    }

    function _retainedDailyWord(uint24 day) internal view returns (uint256) {
        uint24 today = _latestDailyResultDay();
        if (day > today || uint256(today) - day > 1) return 0;
        return _recordedDailyWord(day);
    }

    // =========================================================================
    // Future Mint Awards
    // =========================================================================

    /// @dev Packed pending accumulators for revenue credited during prize pool freeze.
    ///      [255] POOL_PENDING_SENTINEL | [128:255] futurePending | [0:128] nextPending
    ///      Accumulated while prizePoolFrozen == true; applied atomically by _unfreezePool().
    ///
    ///      SECURITY: Credit-only: nothing debits the buffer. Every value bit is zero while
    ///      unfrozen: the unfreeze folds the buffer into the live pools and leaves only the
    ///      sentinel, so the first credit of the next freeze rewrites a nonzero slot. Game
    ///      over zeroes it. Readers mask the sentinel off.
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

    /// @dev Emitted when a native donation adds mid-day RNG credit, in wei.
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
        Idle, Terminal, Wait, Publish, Tickets, DailyApply, DailyPhase,
        Redemption, Afking, HumanBoxes, Degenerette, Decimator, Craps,
        CertifyRead, PrepareSubscriptions, Maintenance, RequestDaily, RequestMidday, GrowthSettle,
        SeizeLoans, DegenesisSettle
    }

    function _minerMaintenancePending() internal view returns (bool) {
        return IGameMinerMaintenance(ContractAddresses.CRAPS).minerMaintenancePending_g11976();
    }

    /// @dev `caller` is the account whose donated credit may pay the mid-day threshold gate;
    ///      address(0) selects as a creditless caller.
    function _nextMinerAction(address caller) internal view returns (MinerAction) {
        MineFlipGas.Meter memory meter;
        return _nextMinerAction(caller, meter);
    }

    function _nextMinerAction(address caller, MineFlipGas.Meter memory meter) internal view returns (MinerAction) {
        if (gameOver) {
            if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) == 0) return MinerAction.Terminal;
            uint256 ended = _goRead(GO_TIME_SHIFT, GO_TIME_MASK);
            return ended != 0 && block.timestamp >= ended + 30 days && _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) == 0
                ? MinerAction.Terminal : MinerAction.Idle;
        }
        if (_livenessTriggered()) {
            // The first terminal call must latch its cohort. Once latched, waiting
            // cannot advance it; a dead VRF still takes precedence over the wait, and
            // loan settlement owed by the ending runs ahead of both.
            if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) != 0
                && _goRead(GO_LOAN_STEP_SHIFT, GO_LOAN_STEP_MASK) == 0
                && _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) == 0
                && _rngRequestActive() && _currentRngWord() == 0 && _endingReason() != EndingReason.HardStall) return MinerAction.Wait;
            return MinerAction.Terminal;
        }
        // Loans due at the level just entered are seized before anything uses its word.
        if (_loansDuePending()) return MinerAction.SeizeLoans;
        if (_rngRequestActive() && _currentRngWord() == 0) {
            return MinerAction.Wait;
        }
        if (_rngRequestActive() && !_rngSessionPublished()) return MinerAction.Publish;
        if (!_rngComplete()) {
            if (!_rngSessionPublished() || _currentRngWord() == 0) return MinerAction.Wait;
            if (!ticketsFullyProcessed) return MinerAction.Tickets;
            if (rngLockedFlag) {
                if (_recordedDailyWord(rngRequestDay) != 0) return MinerAction.DailyPhase;
                return MinerAction.DailyApply;
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
        bool dailyDue = dailyComplete && _dailyRequestDue();
        if (dailyDue && (_afkingResetDay <= dailyIdx || !subsFullyProcessed)) return MinerAction.PrepareSubscriptions;
        if (_minerMaintenancePending()) return MinerAction.Maintenance;
        if (dailyDue) return MinerAction.RequestDaily;
        // Behind the day's request, so a long settlement never delays the daily word; ahead of
        // the optional mid-day request, which would otherwise starve it.
        if (_growthSettlePending()) return MinerAction.GrowthSettle;
        if (_degenesisSettlePending()) return MinerAction.DegenesisSettle;
        return _minerMiddayEligible(caller, meter) ? MinerAction.RequestMidday : MinerAction.Idle;
    }

    error ExternalRequestRefused();
    uint256 internal constant EXTERNAL_READ_GAS = 50_000;
    uint256 internal constant VRF_REQUEST_MIN_GAS = 500_000;
    // A request may create its id slot and seal packed state before returning to
    // the checkpoint caller. These are caller reserves, never coordinator caps.
    uint256 internal constant VRF_REQUEST_RESERVE = 500_000;
    // Coordinator reads and funding forward all gas above the meter floor and these caller
    // tails, like the request; the minimum admits the call and never caps it.
    uint256 internal constant VRF_READ_RESERVE = 200_000;
    // A first funding creates the subscription's balance slot: 125,077 gas natively.
    uint256 internal constant VRF_FUND_MIN_GAS = 150_000;

    /// @dev Native balance is the second static ABI word; never decode consumers.
    function _vrfNativeBalance(MineFlipGas.Meter memory meter, uint256 tail)
        internal view returns (bool ok, uint256 nativeBalance)
    {
        bytes memory result;
        (ok, result) = BoundedCall.staticcallRemaining(meter, address(vrfCoordinator), EXTERNAL_READ_GAS, tail,
            abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector, vrfSubscriptionId), 64);
        if (ok) assembly ("memory-safe") { nativeBalance := mload(add(result, 64)) }
        ok = ok && nativeBalance <= type(uint96).max;
    }

    // VRFV2PlusClient.ExtraArgsV1({nativePayment: true}), tag plus one ABI bool.
    bytes internal constant VRF_NATIVE_EXTRA_ARGS =
        hex"92fd13380000000000000000000000000000000000000000000000000000000000000001";

    // Five scheduled mid-day windows plus one daily word; each includes one retry.
    // 33 days plus one boundary and one terminal commitment: 2 * (33 * 6 + 2).
    uint256 internal constant VRF_REQUESTS_PER_DAY = 12;
    uint256 internal constant VRF_MAX_REQUESTS_PER_INTERVAL = 400;
    uint256 internal constant VRF_STRESS_COST =
        300_000 * 1 gwei * (100 + ContractAddresses.VRF_NATIVE_PREMIUM) / 100;
    uint256 internal constant VRF_NATIVE_LOW_WATER =
        2 * ContractAddresses.VRF_LANE_MAX_GAS_PRICE * 350_000 * (100 + ContractAddresses.VRF_NATIVE_PREMIUM) / 100
        + 5 * VRF_REQUESTS_PER_DAY * VRF_STRESS_COST;
    uint256 internal constant VRF_NATIVE_TARGET =
        VRF_NATIVE_LOW_WATER + 2 * VRF_MAX_REQUESTS_PER_INTERVAL * VRF_STRESS_COST;
    // Per callback gas above 150k: two lane minimums plus the low-water and interval stress cost.
    uint256 internal constant VRF_LOW_WATER_PER_GAS = (2 * ContractAddresses.VRF_LANE_MAX_GAS_PRICE
        + 5 * VRF_REQUESTS_PER_DAY * 1 gwei) * (100 + ContractAddresses.VRF_NATIVE_PREMIUM) / 100;
    uint256 internal constant VRF_TARGET_PER_GAS =
        VRF_LOW_WATER_PER_GAS + 2 * VRF_MAX_REQUESTS_PER_INTERVAL * 1 gwei * (100 + ContractAddresses.VRF_NATIVE_PREMIUM) / 100;
    event VrfFunded(uint24 level, uint256 fromYield, uint256 fromSdgnrs);

    function _vrfMinFulfillBalance() internal view returns (uint256) {
        return ContractAddresses.VRF_LANE_MAX_GAS_PRICE * (200_000 + uint256(vrfCallbackGasLimit))
            * (100 + ContractAddresses.VRF_NATIVE_PREMIUM) / 100;
    }

    /// @dev Governance may raise the callback cap; low-water and target rise with it.
    /// The default-sized constants remain a minimum, even for a smaller callback.
    function _vrfNativeLevels() internal view returns (uint256 lowWater, uint256 target) {
        uint256 callbackGas = vrfCallbackGasLimit;
        uint256 extra = callbackGas > 150_000 ? callbackGas - 150_000 : 0;
        lowWater = VRF_NATIVE_LOW_WATER + extra * VRF_LOW_WATER_PER_GAS;
        target = VRF_NATIVE_TARGET + extra * VRF_TARGET_PER_GAS;
    }

    /// @dev Count all ETH obligations, including the frozen purchase buffer, exactly once.
    function _untrackedYield(uint256 stBal) internal view returns (uint256) {
        (uint128 nextPool, uint128 futurePool) = _getPrizePools();
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        uint256 obligations = _getCurrentPrizePool() + uint256(nextPool) + uint256(futurePool)
            + claimablePool + yieldAccumulator + uint256(pNext) + uint256(pFuture);
        uint256 assets = address(this).balance + stBal;
        return assets > obligations ? assets - obligations : 0;
    }

    /// @dev A failed stETH read cannot establish source order, so skip the optional pull.
    ///      Like the coordinator calls, the read forwards all gas above the meter floor and `tail`.
    function _vrfYieldSurplus(MineFlipGas.Meter memory meter, uint256 tail)
        internal view returns (bool ok, uint256 surplus)
    {
        uint256 stBal;
        (ok, stBal) = BoundedCall.staticWordRemaining(meter, ContractAddresses.STETH_TOKEN, EXTERNAL_READ_GAS, tail,
            abi.encodeWithSelector(IStETH.balanceOf.selector, address(this)));
        if (!ok || stBal > type(uint128).max) return (false, 0);
        return (true, _untrackedYield(stBal));
    }

    /// @dev Fresh daily request and coordinator swap. The normal day reads only the subscription.
    /// `tail` is the caller's work after the refill, kept back from both coordinator calls.
    function _refillVrfNative(MineFlipGas.Meter memory meter, uint256 tail) internal {
        if (address(this).balance == 0) return;
        (bool ok, uint256 balance) = _vrfNativeBalance(meter, tail);
        if (!ok) return;
        (uint256 lowWater, uint256 target) = _vrfNativeLevels();
        if (balance >= lowWater) return;
        uint256 surplus;
        (ok, surplus) = _vrfYieldSurplus(meter, tail);
        if (ok) _topUpVrfNative(meter, tail, target - balance, surplus);
    }

    /// @dev Yield first, then the protocol's ordinary claimable, then AFKing. Claim ETH is a
    /// soft liquidity reservation; every non-yield wei sent removes one wei of obligations.
    /// Callers read the subscription with a 64-byte return, so the coordinator has code.
    /// Returns only the yield actually sent, so the caller can split the remaining surplus.
    function _topUpVrfNative(MineFlipGas.Meter memory meter, uint256 tail, uint256 deficit, uint256 surplus)
        internal returns (uint256 fromYield)
    {
        uint256 available = address(this).balance;
        if (available > deficit) available = deficit;
        fromYield = available < surplus ? available : surplus;
        uint256 remaining = available - fromYield;
        uint256 fromClaimable;
        uint256 fromAfking;
        if (remaining != 0) {
            // The unbacked one-wei wallet sentinel is never a funding source.
            uint256 claimable = _claimableOf(SDGNRS_WALLET_ID);
            if (claimable != 0) --claimable;
            fromClaimable = remaining < claimable ? remaining : claimable;
            remaining -= fromClaimable;
            if (remaining != 0) {
                uint256 afking = _afkingOf(SDGNRS_WALLET_ID);
                fromAfking = remaining < afking ? remaining : afking;
            }
        }
        uint256 fromSdgnrs = fromClaimable + fromAfking;
        uint256 amount = fromYield + fromSdgnrs;
        if (amount == 0) return 0;
        (bool ok,) = BoundedCall.callValueRemaining(meter, address(vrfCoordinator), amount, VRF_FUND_MIN_GAS, tail,
            abi.encodeWithSelector(IVRFCoordinator.fundSubscriptionWithNative.selector, vrfSubscriptionId), 0);
        if (!ok) return 0;
        if (fromSdgnrs != 0) {
            _debitClaimableAndAfking(SDGNRS_WALLET_ID, fromClaimable, fromAfking);
            claimablePool -= uint128(fromSdgnrs);
        }
        emit VrfFunded(level, fromYield, fromSdgnrs);
    }

    /// @dev Impossible reported balances are refused before they can overflow fund arithmetic.
    function _boundedStethBalance(MineFlipGas.Meter memory meter, uint256 tail) internal view returns (uint256 balance) {
        (bool ok, uint256 value) = BoundedCall.staticWordRemaining(meter, ContractAddresses.STETH_TOKEN, EXTERNAL_READ_GAS, tail,
            abi.encodeWithSelector(IStETH.balanceOf.selector, address(this)));
        if (ok && value <= type(uint128).max) balance = value;
    }

    function _boundedVrfRequest(uint16 confirmations, MineFlipGas.Meter memory meter) internal returns (bool ok, uint256 id) {
        BoundedCall.admitFirst(meter, VRF_REQUEST_MIN_GAS, VRF_REQUEST_RESERVE);
        bytes memory result;
        (ok, result) = BoundedCall.callRemaining(meter, address(vrfCoordinator), VRF_REQUEST_MIN_GAS, VRF_REQUEST_RESERVE,
            abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector, VRFRandomWordsRequest({
                keyHash: vrfKeyHash, subId: vrfSubscriptionId, requestConfirmations: confirmations,
                callbackGasLimit: vrfCallbackGasLimit, numWords: 1, extraArgs: VRF_NATIVE_EXTRA_ARGS
            })), 32);
        if (ok) id = abi.decode(result, (uint256));
        ok = ok && id != 0;
    }


    /// @dev The mid-day request's own refusal gates, read before selecting it: an optional
    ///      request that would certainly be refused is not work. Daily, read, maintenance and
    ///      liveness gates already hold on the path that reaches this check. A pending
    ///      write-side Craps window waives both pending-value gates. Otherwise an empty queue
    ///      is never eligible, and a queue below the threshold is eligible only when `caller`'s
    ///      donated credit covers the charge, priced last only when
    ///      every other gate passes.
    function _minerMiddayEligible(address caller, MineFlipGas.Meter memory meter) internal view returns (bool) {
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
        if (!dailyComplete || _dailyRequestDue()) return false;
        uint256 maxBasefee = _lrRead(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK);
        if (maxBasefee != 0 && block.basefee > maxBasefee * (crapsWork ? 4 gwei : 1 gwei)) return false;
        if ((block.timestamp - 82_620) % 1 days >= 1 days - 1 minutes) return false;
        if (_recordedDailyWord(_gameDay()) == 0) return false;
        // No coordinator is wired before VRF setup, so nothing can be requested yet.
        if (address(vrfCoordinator) == address(0)) return false;
        if (!crapsWork) {
            (bool ok, uint256 nativeBal) = _vrfNativeBalance(meter, VRF_READ_RESERVE);
            if (!ok || nativeBal < _vrfMinFulfillBalance() * 3 / 2) return false;
        }
        if (!needsCredit) return true;
        (bool covered,,,) = _middayCreditCharge(caller);
        return covered;
    }

    /// @dev Credit is denominated in wei. The floor keeps near-zero basefee requests paid.
    function _middayCreditCharge(address caller)
        internal view returns (bool covered, uint256 charge, uint256 balance, uint32 id)
    {
        id = _walletIdOf(caller);
        balance = middayRngCredit[id];
        uint256 fee = block.basefee;
        if (fee < MIDDAY_BASEFEE_FLOOR) fee = MIDDAY_BASEFEE_FLOOR;
        charge = MIDDAY_RNG_BILLED_GAS * fee * MIDDAY_RNG_CHARGE_MULT;
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
        return _gameDay() >= _purchaseDeadlineDay();
    }

    /// @dev Shared day boundary for distress and purchase-phase liveness.
    function _purchaseDeadlineDay() internal view returns (uint24) {
        return purchaseStartDay + _PURCHASE_TIMEOUT_DAYS;
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

    /// @dev Top bit of the pending slot. It keeps the slot nonzero between freezes, so it is
    ///      never pool value; the future half beneath it holds 127 bits.
    uint256 internal constant POOL_PENDING_SENTINEL = uint256(1) << 255;

    /// @dev Largest future value the pending slot holds below the sentinel (~1.7e38 wei).
    uint256 internal constant POOL_FUTURE_MAX = type(uint128).max >> 1;

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
            POOL_PENDING_SENTINEL |
            (uint256(future) << POOL_FUTURE_SHIFT) |
            uint256(next);
    }

    /// @dev Reads (0, 0) while unfrozen: the unfreeze leaves only the sentinel behind.
    function _getPendingPools()
        internal
        view
        returns (uint128 next, uint128 future)
    {
        uint256 packed = prizePoolPendingPacked;
        next = uint128(packed);
        future = uint128((packed >> POOL_FUTURE_SHIFT) & POOL_FUTURE_MAX);
    }

    /// @dev Add a combined prize contribution to the active accumulator in ONE RMW. The purchase
    ///      path computes each leg's next/future split (ticket and lootbox legs use different
    ///      ratios), sums the post-split totals, and lands both in a single packed slot — the
    ///      pending buffer while the pool is frozen, otherwise the live pools.
    ///
    ///      SATURATES rather than reverting. Both ceilings (2^128 - 1 next, 2^127 - 1 future below
    ///      the pending sentinel) are far above any reachable value, so
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
        // needs, and neither can carry into the other or into the pending sentinel, which
        // carries through unchanged.
        uint256 next = (slot & POOL_HALF_MAX) + nextAdd;
        uint256 future = ((slot >> POOL_FUTURE_SHIFT) & POOL_FUTURE_MAX) + futureAdd;
        if (next > POOL_HALF_MAX) next = POOL_HALF_MAX;
        if (future > POOL_FUTURE_MAX) future = POOL_FUTURE_MAX;

        uint256 packed = (slot & POOL_PENDING_SENTINEL) | (future << POOL_FUTURE_SHIFT) | next;
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
    event SmurfBaseAllowanceRaised(uint32 indexed mainId, uint16 previousBase, uint16 newBase);

    /// @dev With createSmurf, the only writer of a wallet's identity. Returns the existing ID or allocates the
    ///      next table position, publishing both directions (the table element and walletIds)
    ///      and seeding the claimable sentinel in the same call. Existing mint history is returned; new registration does not write it.
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
        // Unbacked claimable sentinel, outside claimablePool and never paid out: every later
        // credit to the account is a nonzero write.
        balancesPacked[id] = 1;
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

    /// @dev `_resolveAccountId` plus the account's payee. The self shorthand pays the caller
    ///      without a table read: a registered address's current ID is its own ordinary main
    ///      (a main sale clears the address's ID), whose payee is that address.
    function _resolveAccountPayee(uint32 id) internal view returns (uint32, address) {
        if (id == 0) return (_walletIdOf(msg.sender), msg.sender);
        (, address payee, bool authorized) = _account(id, msg.sender);
        if (!authorized) revert NotApproved();
        return (id, payee);
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
                    if iszero(and(lane, 0x80000000)) { lane := 0 }
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
            uint256 lane = 0x40000000;
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
        return trait == GoldSixLib.TRAIT ? 0 : uint32(deityBySymbol[(trait >> 6) * 8 + (trait & 7)]);
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

    /// @dev Wallet ID of occurrence `k` in lvlTraitEntry[(lvl) & 1][trait]. No bound check: callers
    ///      gate on the length.
    function _bucketIdAtUnchecked(uint24 lvl, uint8 trait, uint256 k) internal view returns (uint32) {
        return _bucketIdFromWord(_bucketWordAtUnchecked(lvl, trait, k), k);
    }

    /// @dev Header: uint32 occurrence count, then up to seven low-first uint32 tail lanes.
    ///      Only complete words reach data storage. The practical per-level bound is below
    ///      2^32 occurrences per trait; reaching it needs over 536 million word writes.
    ///      Returns physical writes classified by the slot value before each store.
    ///      Caller has prepared lvl and provides the nonzero wallet ID.
    /// @custom:storage-write traitBucketLive
    function _bucketAppendRun(
        uint256 levelSlot,
        uint8 traitId,
        uint256 ownerIdx,
        uint256 occurrences,
        uint24 lvl
    ) internal returns (uint256 fresh, uint256 dirty) {
        assembly ("memory-safe") {
            let parity := and(lvl, 1)
            let bitmapSlot := add(traitBucketLive.slot, parity)
            let physicalBits := sload(bitmapSlot)
            let bits := physicalBits
            let staleMask := shl(add(mul(traitBucketStale.offset, 8), parity), 1)
            let stamps := sload(traitBucketStale.slot)
            if and(stamps, staleMask) {
                bits := 0
                sstore(traitBucketStale.slot, and(stamps, not(staleMask)))
                dirty := add(dirty, 1)
            }
            let bit := shl(traitId, 1)
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            switch iszero(header)
            case 1 { fresh := 1 }
            default { dirty := add(dirty, 1) }
            if iszero(and(bits, bit)) {
                header := 0
                sstore(bitmapSlot, or(bits, bit))
                switch iszero(physicalBits)
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
            let parity := and(lvl, 1)
            let bitmapSlot := add(traitBucketLive.slot, parity)
            let physicalBits := sload(bitmapSlot)
            let bits := physicalBits
            let staleMask := shl(add(mul(traitBucketStale.offset, 8), parity), 1)
            let stamps := sload(traitBucketStale.slot)
            if and(stamps, staleMask) {
                bits := 0
                sstore(traitBucketStale.slot, and(stamps, not(staleMask)))
                dirty := add(dirty, 1)
            }
            let bit := shl(traitId, 1)
            let elem := add(levelSlot, traitId)
            let header := sload(elem)
            switch iszero(header)
            case 1 { fresh := 1 }
            default { dirty := add(dirty, 1) }
            if iszero(and(bits, bit)) {
                header := 0
                sstore(bitmapSlot, or(bits, bit))
                switch iszero(physicalBits)
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
        target = _levelPrizePool(purchaseLvl - 1);
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

    /// @dev Game-held redemption value remains inside claimablePool, outside wallet balances.
    function _redemptionReserve() internal view returns (uint256) {
        return _redemptionReserveStored - 1;
    }

    function _setRedemptionReserve(uint256 amount) internal {
        // The reserve is drawn from a uint128 claimable balance excluding its sentinel.
        _redemptionReserveStored = uint128(amount + 1);
    }

    function _releaseRedemptionReserve() internal {
        uint256 amount = _redemptionReserve();
        if (amount == 0) return;
        _setRedemptionReserve(0);
        _creditClaimableLogged(SDGNRS_WALLET_ID, amount);
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

    /// @dev `_debitClaimableAndAfking` from the caller's own load `packed` of `balancesPacked[id]`,
    ///      with the same two guards; returns the stored word.
    function _debitClaimableAndAfkingFrom(
        uint32 id,
        uint256 packed,
        uint256 claimableAmount,
        uint256 afkingAmount
    ) internal returns (uint256 updated) {
        if (uint128(packed) < claimableAmount) revert Insolvent();
        if ((packed >> 128) < afkingAmount) revert Insolvent();
        updated = packed - claimableAmount - (afkingAmount << 128);
        balancesPacked[id] = updated;
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

    // Box queue (`boxQueue`): three 85-bit entries per word. Logical position p sits in word
    // p / 3 at bit (p % 3) * 85; bit 255 stays zero. Entry, LSB -> MSB:
    //   [0:32]   wallet ID   nonzero beneficiary
    //   [32:53]  units       per-box value in LB_VALUE_UNIT, 1..LB_UNITS_MAX
    //   [53:65]  score code  post-action activity score, 12-bit piecewise code (Lootbox module)
    //   [65:77]  boostBps    boon uplift as a fraction of the order's spend, at most 2,500
    //   [77:84]  quantity    boxes, 1..MAX_BOXES_PER_ORDER
    //   [84]     distress    bought in distress mode
    uint256 internal constant LB_ENTRY_BITS = 85;
    uint256 internal constant LB_ENTRY_MASK = 0x1FFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant LB_UNITS_SHIFT = 32;
    uint256 internal constant LB_UNITS_MASK = 0x1FFFFF;
    uint256 internal constant LB_SCORE_SHIFT = 53;
    uint256 internal constant LB_SCORE_MASK = 0xFFF;
    uint256 internal constant LB_BOOST_SHIFT = 65;
    uint256 internal constant LB_BOOST_MASK = 0xFFF;
    uint256 internal constant LB_QTY_SHIFT = 77;
    uint256 internal constant LB_QTY_MASK = 0x7F;
    uint256 internal constant LB_DISTRESS = uint256(1) << 84;

    /// @dev Queued box values are whole 0.001 ETH units. A system grant floors per box; the
    ///      remainder stays in the pools its payment funded.
    uint256 internal constant LB_VALUE_UNIT = 0.001 ether;

    /// @dev Hard per-box cap for queued boxes (2,000 ETH). Purchases revert above it; system
    ///      grants stay inside it by their producer formulas.
    uint256 internal constant LB_UNITS_MAX = 2_000_000;

    /// @dev Preset multipliers against the purchase level's ticket price.
    uint256 internal constant LB_MED_MULTIPLE = 5;
    uint256 internal constant LB_LARGE_MULTIPLE = 25;

    /// @dev Boxes one purchase may hold. Sized so a maximum entry — every box rolled, plus one
    ///      recirculated box per ETH spin — resolves inside a block alongside the afking leg
    ///      that shares the `mineFlip()` transaction. Not a spend limit: a player wanting more
    ///      exposure buys a larger custom, or another entry.
    uint256 internal constant MAX_BOXES_PER_ORDER = 100;

    /// @dev Minimum custom box (0.01 ETH). Presets clear it structurally: the cheapest ticket
    ///      price is 0.01 ETH and a small is one of those.
    uint256 internal constant BOX_CUSTOM_MIN_UNITS = 10;

    // Purchase input (`boxOrder`): [quantity:7][kind:2][customUnits:21]; kind 0 small, 1 medium,
    // 2 large, 3 custom; custom units are zero for presets. Every bit at or above 30 must be
    // zero; zero means no ordinary leg.
    uint256 internal constant BO_QTY_MASK = 0x7F;
    uint256 internal constant BO_KIND_SHIFT = 7;
    uint256 internal constant BO_UNITS_SHIFT = 9;
    uint256 internal constant BO_KIND_CUSTOM = 3;

    /// @dev Validate one purchase's `boxOrder` input as wide integers and price it at `lvl`.
    ///      `fields` holds the per-box units and quantity already positioned for the entry.
    /// @custom:reverts E On a quantity outside 1..MAX_BOXES_PER_ORDER, a nonzero bit at or above
    ///         30, custom units outside BOX_CUSTOM_MIN_UNITS..LB_UNITS_MAX, or a preset carrying units.
    function _decodeBoxOrder(uint256 boxOrder, uint24 lvl) internal pure returns (uint256 fields, uint256 cost) {
        uint256 qty = boxOrder & BO_QTY_MASK;
        uint256 kind = (boxOrder >> BO_KIND_SHIFT) & 3;
        uint256 units = boxOrder >> BO_UNITS_SHIFT;
        if (qty == 0 || qty > MAX_BOXES_PER_ORDER) revert E();
        if (kind == BO_KIND_CUSTOM) {
            if (units < BOX_CUSTOM_MIN_UNITS || units > LB_UNITS_MAX) revert E();
        } else {
            if (units != 0) revert E();
            units = PriceLookupLib.priceForLevel(lvl)
                * (kind == 0 ? 1 : (kind == 1 ? LB_MED_MULTIPLE : LB_LARGE_MULTIPLE)) / LB_VALUE_UNIT;
        }
        unchecked {
            cost = qty * units * LB_VALUE_UNIT;
        }
        fields = (units << LB_UNITS_SHIFT) | (qty << LB_QTY_SHIFT);
    }

    /// @dev Boxes an entry resolves.
    function _boxEntryCount(uint256 entry) internal pure returns (uint256) {
        return (entry >> LB_QTY_SHIFT) & LB_QTY_MASK;
    }

    /// @dev Append a complete entry (no bit above 84) to the write buffer at position = its write
    ///      count. The count and `pendingWei` (the ordinary leg's RNG-pending ETH) commit in one
    ///      lootboxRngPacked write. Lane 0 overwrites the whole word, clearing the buffer's stale
    ///      lanes; lanes 1 and 2 OR into the word their group's lane 0 cleared, since the write
    ///      count only grows until the buffer is resealed. Returns the buffer and position.
    function _appendBoxEntry(uint256 entry, uint256 pendingWei) internal returns (uint48 buffer, uint32 position) {
        uint256 lr = lootboxRngPacked;
        position = uint32(lr >> LR_BOX_COUNT_SHIFT);
        uint256 pending = ((lr >> LR_PENDING_ETH_SHIFT) + pendingWei / LR_ETH_SCALE) & LR_PENDING_ETH_MASK;
        lootboxRngPacked = (lr & ~(LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT))
            + (pending << LR_PENDING_ETH_SHIFT) + (uint256(1) << LR_BOX_COUNT_SHIFT);
        buffer = _rngWriteBuffer();
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            let slot := add(keccak256(0x00, 0x20), div(position, 3))
            let lane := mod(position, 3)
            switch lane
            case 0 { sstore(slot, entry) }
            default { sstore(slot, or(sload(slot), shl(mul(lane, LB_ENTRY_BITS), entry))) }
        }
    }

    /// @dev Entry `position` of `buffer`. Callers bound `position` by that buffer's count.
    function _boxEntryAt(uint48 buffer, uint256 position) internal view returns (uint256 entry) {
        uint256[] storage q = boxQueue[buffer];
        assembly ("memory-safe") {
            mstore(0x00, q.slot)
            entry := and(
                shr(mul(mod(position, 3), LB_ENTRY_BITS), sload(add(keccak256(0x00, 0x20), div(position, 3)))),
                LB_ENTRY_MASK
            )
        }
    }

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
    // Degenesis State
    // =========================================================================

    /// @dev The Vault's 25% of split Degenesis volume: a reserved purchase obligation inside
    ///      claimablePool, outside Vault claimable, AFKing, backing and lending capacity.
    uint128 internal degenesisVaultBudget;
    /// @dev Only full daily completion refreshes this real-time escape clock.
    uint48 internal lastDailyCompletedAt = uint48(block.timestamp);
    /// @dev Exact opening request of the current Degenesis cohort; slot 12, byte 22.
    ///      Midday requests, retries and completion never restart its six-hour bonus.
    uint48 internal degenesisOpenedAt;

    /// @dev Degenesis spending credit per wallet: 25% of qualifying spend while the credit
    ///      window is open, consumed 1:1 by Degenesis purchases.
    mapping(uint32 => uint256) internal degenesisCredit;

    // =========================================================================
    // Game Over State (packed: 5 variables in 104/256 bits)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits  0:47]  gameOverTime              uint48   Timestamp when gameover triggered (0 = active)
    //   [bits 48:55]  gameOverFinalJackpotPaid   uint8   1 = final jackpot paid
    //   [bits 56:63]  finalSwept                 uint8   1 = 30-day sweep executed
    //   [bits 64:71]  terminalLoanStep           uint8   0 = no terminal loan work; else settling level + step
    //   [bits 72:103] terminalLoanIndex          uint32  Next entry of that level's due list

    /// @dev Packed game over state. See layout comment above.
    uint256 internal gameOverStatePacked;

    // ---- gameOverState shifts and masks ----
    uint256 internal constant GO_TIME_SHIFT = 0;
    uint256 internal constant GO_TIME_MASK = 0xFFFFFFFFFFFF;     // 48 bits
    uint256 internal constant GO_JACKPOT_PAID_SHIFT = 48;
    uint256 internal constant GO_JACKPOT_PAID_MASK = 0xFF;       // 8 bits
    uint256 internal constant GO_SWEPT_SHIFT = 56;
    uint256 internal constant GO_SWEPT_MASK = 0xFF;              // 8 bits
    /// @dev The due level being settled, as an offset from `level`: 1 when an ending decided with
    ///      VRF alive latches, up to LOAN_HORIZON_LEVELS - 1; zero when no settlement is owed or it
    ///      has finished. While nonzero, the terminal phase settles loans and nothing else.
    uint256 internal constant GO_LOAN_STEP_SHIFT = 64;
    uint256 internal constant GO_LOAN_STEP_MASK = 0xFF;          // 8 bits
    uint256 internal constant GO_LOAN_INDEX_SHIFT = 72;
    uint256 internal constant GO_LOAN_INDEX_MASK = 0xFFFFFFFF;   // 32 bits

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

    // =========================================================================
    // Operator Approvals
    // =========================================================================

    /// @dev account wallet ID => operator => approved (game-wide delegated control).
    mapping(uint32 => mapping(address => bool)) internal operatorApprovals;

    // =========================================================================
    // Affiliate DGNRS Claims
    // =========================================================================

    function _levelPrizePool(uint24 lvl) internal view returns (uint256) {
        uint256 word = levelPrizePool[lvl & 3];
        return word >> 128 == uint256(lvl) + 1 ? uint128(word) : 0;
    }

    function _setLevelPrizePool(uint24 lvl, uint256 amount) internal {
        levelPrizePool[lvl & 3] = (uint256(lvl) + 1) << 128 | uint128(amount);
    }

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

    /// @dev Current level allocation (low 128), claimed (next 127), and retained bit 255.
    ///      Both values are bounded by the sDGNRS supply, far below 2^127.
    uint256 internal levelDgnrsPacked;
    uint256 internal constant DGNRS_CLAIMED_MASK = (uint256(1) << 127) - 1;

    function _getLevelDgnrs(uint24 lvl) internal view returns (uint256 allocation, uint256 claimed) {
        if (lvl != level) return (0, 0);
        uint256 word = levelDgnrsPacked;
        return (uint128(word), (word >> 128) & DGNRS_CLAIMED_MASK);
    }

    /// @dev The level bump replaces both accounting halves before assigning the new level.
    function _setLevelDgnrsAllocation(uint24, uint256 allocation) internal {
        levelDgnrsPacked = uint128(allocation) | (uint256(1) << 255);
    }

    function _addLevelDgnrsClaimed(uint24, uint256 add) internal {
        uint256 word = levelDgnrsPacked;
        uint256 claimed = ((word >> 128) & DGNRS_CLAIMED_MASK) + add;
        levelDgnrsPacked = uint128(word) | (claimed << 128) | (uint256(1) << 255);
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
    /// @custom:storage-write deityBoonPacked
    function _pushDeityId(uint32 id) internal {
        assembly ("memory-safe") {
            let count := sload(deityPassIds.slot)
            mstore(0, deityPassIds.slot)
            let slot := add(keccak256(0, 32), shr(3, count))
            let shift := shl(5, and(count, 7))
            sstore(slot, or(and(sload(slot), not(shl(shift, 0xffffffff))), shl(shift, id)))
            sstore(deityPassIds.slot, add(count, 1))
            mstore(0, id)
            mstore(32, deityBoonPacked.slot)
            slot := keccak256(0, 64)
            sstore(slot, or(and(sload(slot), 0xffffffff), shl(32, count)))
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

    // =========================================================================
    // Degenesis Settlement
    // =========================================================================

    /// @dev The one priced, unsettled Degenesis cohort (degenesisClosed + 1); zero when none.
    ///      [0:80] Q payout budget, [80:160] sDGNRS paid, [160:184] bound request day,
    ///      [184:216] settlement cursor. The reservation is 1.5Q - paid.
    uint256 internal degenesisActive;

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
    function _gameDay() internal view returns (uint24) {
        return dailyIdx;
    }

    /// @dev One ending authority for mining dispatch, views and paid-entry guards.
    enum EndingReason { None, PurchaseTimeout, HardStall }

    function _endingReason() internal view returns (EndingReason) {
        if (_vrfDeadmanFired() || _vrfDead()) return EndingReason.HardStall;
        // Terminal entry sets the header latch before returning or requesting entropy.
        // Ordinary calls need no cold lootboxRngPacked read just to exclude a latch.
        if (gameOver || rngFlagsAndNudges & (uint16(1) << 13) != 0) {
            return _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0
                ? EndingReason.HardStall : EndingReason.PurchaseTimeout;
        }
        // Header-only exclusions precede the separate completion/request word.
        if (lastPurchaseDay || jackpotPhaseFlag || dailyIdx < purchaseStartDay
            || dailyIdx - purchaseStartDay < _PURCHASE_TIMEOUT_DAYS || !dailyComplete || !_dailyRequestDue()
            || _wallDay() <= _wallDayAt(lastDailyCompletedAt)) return EndingReason.None;
        if (_getNextPrizePool() > _prizePoolTarget(level + 1)) return EndingReason.None;
        return EndingReason.PurchaseTimeout;
    }

    function _livenessTriggered() internal view returns (bool) {
        return _endingReason() != EndingReason.None;
    }

    function _vrfDeadmanFired() internal view returns (bool) {
        return block.timestamp >= uint256(lastDailyCompletedAt) + _VRF_DEAD_TIMEOUT;
    }

    /// @dev An active request whose word is not yet in use (published) expires from its original
    ///      timestamp, whether or not the word has been delivered. Retained idle
    ///      timestamps grant neither callback authority nor a timeout. A refused terminal
    ///      attempt has no active request, but keeps its one-shot timer and unpublished latch.
    function _vrfDead() internal view returns (bool) {
        // A published word is in use and cannot expire, whether active or idle.
        // This header read also avoids the terminal metadata word in the common case.
        if (_rngSessionPublished()) return false;
        uint48 t = rngRequestTime;
        if (block.timestamp < uint256(t) + _VRF_DEAD_TIMEOUT) return false;
        if (!_rngRequestActive()) {
            if (_lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0) return true;
            if (_lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0) return false;
        }
        // Dead unless the word is already in use: a word delivered after the timeout, or
        // left unpublished past it, is never applied, so the ending depends only on time.
        return !_rngSessionPublished();
    }

    /// @dev Returns the day index for a specific timestamp.
    function _wallDay() internal view returns (uint24) {
        return GameTimeLib.currentDayIndex();
    }

    function _dailyRequestDue() internal view returns (bool) {
        return _wallDay() > lastDailyRequestWallDay;
    }

    function _wallDayAt(uint48 ts) internal pure returns (uint24) {
        return GameTimeLib.currentDayIndexAt(ts);
    }

    /// @dev Mint activity is stamped by the requested logical game day.
    function _currentMintDay() internal view returns (uint24) { return dailyIdx; }

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

    /// @dev Callback gas limit sent with every VRF request. Packs into the coordinator's
    ///      slot, so requests read both with one SLOAD. Rotated only with the coordinator.
    uint32 internal vrfCallbackGasLimit;

    /// @dev Low 64 bits of the latest VRF request ID, in the coordinator's slot so the callback
    ///      reads its caller check and ID with one SLOAD. Callback authority also requires the
    ///      packed active bit. A superseded request (retry, re-issue) never matches again.
    uint64 internal vrfRequestId;

    /// @dev VRF key hash identifying the oracle and gas lane.
    ///      Rotatable with coordinator; determines gas price tier.
    bytes32 internal vrfKeyHash;

    /// @dev VRF subscription ID for native billing.
    ///      Mutable to allow subscription rotation without redeploying.
    uint256 internal vrfSubscriptionId;

    // =========================================================================
    // Lootbox RNG Packed Slot (amounts, ticket latches and Craps pending flags)
    // =========================================================================
    //
    // Layout (LSB -> MSB):
    //   [bits   0:23]   heroRequestDay            uint24   (sealed pool labels day - 1)
    //   [bits  24:29]   heroQuadrantsValid        uint6    (3 quadrant bits per buffer)
    //   [bits  30:37]   middayMaxBasefeeGwei      uint8    (whole gwei, 0 disables the gate)
    //   [bit      38]   heroWriteBuffer          bool
    //   [bits  39:47]   unused
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

    /// @dev Measured mainnet native billing normalized to the full 150k callback was at most
    /// 246,071 gas in three samples; 300k includes headroom for coordinator overhead.
    uint256 internal constant MIDDAY_RNG_BILLED_GAS = 300_000;
    uint256 internal constant MIDDAY_RNG_CHARGE_MULT = 2;
    uint256 internal constant MIDDAY_BASEFEE_FLOOR = 0.01 gwei;

    /// @dev Scale factor for pending ETH packing (0.001 ETH resolution).
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
    /// @dev Per-(account, level) bonus spend that takes the full EV bonus
    uint256 internal constant LOOTBOX_EV_FULL_ETH = 10 ether;
    /// @dev Cumulative bonus spend at which the marginal box keeps half the EV bonus
    uint256 internal constant LOOTBOX_EV_HALF_ETH = 20 ether;
    /// @dev Cumulative bonus spend at which the marginal box is back to neutral EV
    uint256 internal constant LOOTBOX_EV_ZERO_ETH = 40 ether;

    /// @dev Weighted share of `spend` that takes the EV bonus, starting `used` into the
    ///      per-(account, level) bonus spend. The marginal weight is 1 up to FULL, falls
    ///      linearly to 1/2 at HALF, then linearly to 0 at ZERO; `eligible` is its integral
    ///      over [used, usedAfter], so splitting or reordering purchases cannot raise the
    ///      total. Each segment floors, so rounding never favours the player.
    function _lootboxEvEligible(uint256 used, uint256 spend)
        internal
        pure
        returns (uint256 eligible, uint256 usedAfter)
    {
        if (used >= LOOTBOX_EV_ZERO_ETH) return (0, used);
        usedAfter = used + spend;
        if (usedAfter > LOOTBOX_EV_ZERO_ETH) usedAfter = LOOTBOX_EV_ZERO_ETH;
        if (used < LOOTBOX_EV_FULL_ETH) {
            eligible = (usedAfter < LOOTBOX_EV_FULL_ETH ? usedAfter : LOOTBOX_EV_FULL_ETH) - used;
        }
        // Segment weights (P - x) / K: 1 -> 1/2 over [FULL, HALF], 1/2 -> 0 over [HALF, ZERO].
        eligible += _lootboxEvSegment(
            used,
            usedAfter,
            LOOTBOX_EV_FULL_ETH,
            LOOTBOX_EV_HALF_ETH,
            2 * LOOTBOX_EV_HALF_ETH - LOOTBOX_EV_FULL_ETH,
            2 * (LOOTBOX_EV_HALF_ETH - LOOTBOX_EV_FULL_ETH)
        );
        eligible += _lootboxEvSegment(
            used,
            usedAfter,
            LOOTBOX_EV_HALF_ETH,
            LOOTBOX_EV_ZERO_ETH,
            LOOTBOX_EV_ZERO_ETH,
            2 * (LOOTBOX_EV_ZERO_ETH - LOOTBOX_EV_HALF_ETH)
        );
    }

    /// @dev Integral of (p - x) / k over [lo, hi] clipped to [from, to], floored.
    function _lootboxEvSegment(uint256 lo, uint256 hi, uint256 from, uint256 to, uint256 p, uint256 k)
        private
        pure
        returns (uint256)
    {
        uint256 a = lo > from ? lo : from;
        uint256 b = hi < to ? hi : to;
        if (b <= a) return 0;
        return ((p - a) * (p - a) - (p - b) * (p - b)) / (2 * k);
    }

    /// @dev Read a field from the packed lootbox RNG slot.
    function _lrRead(uint256 shift, uint256 mask) internal view returns (uint256) {
        return (lootboxRngPacked >> shift) & mask;
    }

    /// @dev Write a field to the packed lootbox RNG slot.
    function _lrWrite(uint256 shift, uint256 mask, uint256 value) internal {
        lootboxRngPacked = (lootboxRngPacked & ~(mask << shift)) | ((value & mask) << shift);
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
    ///      Bits 32..36 retain the immutable deity registration ordinal.
    mapping(uint32 => uint64) internal deityBoonPacked;

    // =========================================================================
    // Degenerette Bets
    // =========================================================================

    /// @dev Biggest-spin record bounty in WHOLE FLIP for a queued bet, keyed
    ///      (index << 64) | betId. Written only when a placement arms the record (the bet word's
    ///      record flag), read only by that live bet and retained for the next flagged overwrite.
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
    ///      one slot. All box routes draw at settlement against their live opening level;
    ///      deposits leave the allowance untouched. Retain the two-window storage layout.
    ///      Each window: used (72 bits) + level
    ///      stamp (24 bits). `used` is the cumulative bonus spend, clamped to
    ///      LOOTBOX_EV_ZERO_ETH = 4e19 < 2^72 at every write. A non-matching stamp reads as 0
    ///      (a fresh allowance).
    ///      Window A: bits [0:72) used, [72:96) level. Window B: bits [96:168) used, [168:192) level.
    mapping(uint32 => uint256) internal lootboxEvCapPacked;

    uint256 private constant _EV_USED_MASK = (uint256(1) << 72) - 1;
    uint256 private constant _EV_WINDOW_A_MASK = (uint256(1) << 96) - 1;
    uint256 private constant _EV_WINDOW_B_MASK =
        ((uint256(1) << 96) - 1) << 96;

    /// @dev A player's EV benefit used for `level`; 0 if neither window is stamped to it.
    function _lootboxEvUsedFor(uint32 id, uint24 level)
        internal
        view
        returns (uint256)
    {
        uint256 packed = lootboxEvCapPacked[id];
        if (uint24(packed >> 72) == level) return packed & _EV_USED_MASK;
        if (uint24(packed >> 168) == level) return (packed >> 96) & _EV_USED_MASK;
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
        uint24 lvlA = uint24(packed >> 72);
        uint24 lvlB = uint24(packed >> 168);
        uint256 windowA = (uint256(level) << 72) | (used & _EV_USED_MASK);
        if (lvlA == level) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else if (lvlB == level) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 96);
        } else if (lvlA <= lvlB) {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_A_MASK) |
                windowA;
        } else {
            lootboxEvCapPacked[id] =
                (packed & ~_EV_WINDOW_B_MASK) |
                (windowA << 96);
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
    ///      unrelated storage. Two entries share key (id - 1) >> 1, IDs starting
    ///      at one. Each 128-bit lane packs wallet ID32, board30 and stack66, low to high.
    ///      Resolution and lens readers consume this same compact lane directly.
    ///      A wallet's slot, reused
    ///      window after window, holds its latest entry's level (bits 64..87) and id (0..63).
    mapping(uint256 => uint256) internal decBattleEntries;
    mapping(uint24 => DecBattleRound) internal decBattleRounds;
    mapping(uint32 => uint256) internal decBattlePlayers;

    // =========================================================================
    // Degenerette Hero Wager Tracking (Daily)
    // =========================================================================

    uint256 internal constant HERO_WRITE_SHIFT = 38;

    /// @dev The sealed pool is labeled request day - 1. Today's view exposes the
    ///      accumulating pool; other days have no retained calendar-day history.
    function _dailyHeroWagerWord(uint24 day, uint8 quadrant) internal view returns (uint256) {
        if (quadrant >= 3) return 0;
        uint256 meta = lootboxRngPacked;
        uint256 key = (meta >> HERO_WRITE_SHIFT) & 1;
        if (uint256(day) + 1 == uint24(meta)) key ^= 1;
        else if (day != _gameDay()) return 0;
        if (meta & (uint256(1) << (24 + key * 3 + quadrant)) == 0) return 0;
        return dailyHeroWagers[key][quadrant];
    }

    /// @dev Only a fresh daily commitment swaps hero pools. Retry and midday RNG
    ///      leave the frozen pool and accumulating pool unchanged.
    function _sealHeroWagers(uint24 day) internal {
        uint256 meta = lootboxRngPacked;
        uint256 next = ((meta >> HERO_WRITE_SHIFT) & 1) ^ 1;
        meta = (meta ^ (uint256(1) << HERO_WRITE_SHIFT)) &
            ~(uint256(type(uint24).max) | (uint256(7) << (24 + next * 3)));
        lootboxRngPacked = meta | day;
    }

    /// @dev Three packed quadrants, eight saturating uint32 weights each. The first
    ///      wager after reuse overwrites stale lanes without clearing storage.
    function _recordHeroWager(uint8 quadrant, uint8 symbol, uint256 units, uint256 meta)
        internal returns (uint256)
    {
        unchecked {
            uint256 key = (meta >> HERO_WRITE_SHIFT) & 1;
            uint256 bit = uint256(1) << (24 + key * 3 + quadrant);
            uint256 packed = meta & bit != 0 ? dailyHeroWagers[key][quadrant] : 0;
            uint256 shift = uint256(symbol) * 32;
            uint256 updated = uint32(packed >> shift) + units;
            if (updated > type(uint32).max) updated = type(uint32).max;
            dailyHeroWagers[key][quadrant] = (packed & ~(uint256(type(uint32).max) << shift)) | (updated << shift);
            return meta | bit;
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
    ///   [248-249] whaleTier            uint2    0=none, 1=10%, 2=20%, 3=35%
    ///   [250-254] (free)
    ///   [255]     retained             bool     Sticky storage-reuse sentinel
    ///
    /// Slot 1 (bit 24 keeps the allocated word nonzero; bits 25-71 free):
    ///   [0-23]    craps                uint24   Craps stake-boon lane (the LOW lane, so the
    ///                                           consumption hot path masks without shifting)
    ///   [24]      retained             bool     Sticky storage-reuse sentinel
    ///   [25-71]   (free)                        Activity awards are credited to player
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
    ///      Slot0 bit 255 and slot1 bit 24 record allocation, not live boons.
    ///      UI readers combine with currentDayView_g542950() to compute per-category expiry. WWXRP.enter
    ///      reads slot1's WWXRP lane by raw slot `keccak256(id, slot) + 1` (its
    ///      GAME_BOON_PACKED_SLOT / GAME_WWXRP_LANE_SHIFT / GAME_LANE_TIER_MASK mirror this
    ///      mapping's slot, BP_WWXRP_LANE_SHIFT and BP_LANE_TIER_MASK): moving any of them
    ///      must move those too (pinned by test/fuzz/WwxrpBoonLaneSkip.t.sol).
    mapping(uint32 => BoonPacked) public boonPacked;

    uint256 internal constant BP_SLOT0_RETAINED = 1 << 255;

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

    // ---- Slot 1 shifts (the craps lane owns bits 0-23; bit 24 retains the word) ----
    uint256 internal constant BP_SLOT1_RETAINED = 1 << 24;
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
    // Whale: bits 200-249; bit 255 retains the word.
    uint256 internal constant BP_WHALE_CLEAR = ~(uint256((1 << 50) - 1) << 200);

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

    /// @notice AfKing subscriber record: one 85-bit lane in the two-ended set `_subscribers`,
    ///         three lanes per word (position `p` is lane `p % 3` of word `p / 3`).
    /// @dev Lane layout (LSB -> MSB):
    ///        [0..31]  wallet ID (0 = empty lane)
    ///        [32..34] daily quantity minus 1 (quantity 1..8)
    ///        [35]     mode: set = tickets, clear = lootboxes
    ///        [36..45] activity-score code, frozen by preparation for a box member
    ///        [46..67] checkpoint day
    ///        [68]     removal pending: a seized run that the next preparation pass removes
    ///        [69..84] checkpoint streak, saturating
    ///      Rewards are derived, never stored. For each day after the checkpoint day through the
    ///      endpoint `E` (`_afkingEndpoint`), a member earns 100 whole FLIP, plus 100 per ticket in
    ///      ticket mode, and 70 per unit of affiliate base. Settlement pays both, moves the
    ///      checkpoint day to `E` and folds the elapsed days into the checkpoint streak, so the
    ///      live streak is `checkpoint streak + (E - checkpoint day)` and never depends on when
    ///      anyone settled. A paused protocol seat's checkpoint day is parked at
    ///      `SUB_PAUSED_DAY`, past every endpoint, so it earns nothing and its streak stands
    ///      still until its resume sets the checkpoint day to the endpoint.
    uint256 internal constant SUB_LANE_BITS = 85;
    uint256 internal constant SUB_LANE_MASK = (uint256(1) << 85) - 1;
    uint256 internal constant SUB_QTY_SHIFT = 32;
    uint256 internal constant SUB_TICKETS_BIT = uint256(1) << 35;
    uint256 internal constant SUB_SCORE_SHIFT = 36;
    uint256 internal constant SUB_SCORE_MASK = 0x3ff;
    uint256 internal constant SUB_DAY_SHIFT = 46;
    uint256 internal constant SUB_DAY_MASK = (uint256(1) << 22) - 1;
    uint256 internal constant SUB_PAUSED_DAY = SUB_DAY_MASK;
    uint256 internal constant SUB_REMOVAL_BIT = uint256(1) << 68;
    uint256 internal constant SUB_STREAK_SHIFT = 69;
    uint256 internal constant SUB_STREAK_MAX = 0xffff;

    /// @dev Largest daily quantity a subscription may hold.
    uint256 internal constant SUB_MAX_QUANTITY = 8;

    /// @dev Score code: exact through the seg-B knee (500), then steps of 64 points rounded down;
    ///      code 961 is the 30,000-point effective cap.
    function _encodeSubScore(uint256 score) internal pure returns (uint256) {
        if (score <= 500) return score;
        if (score >= 30_000) return 961;
        return 500 + ((score - 500) >> 6);
    }

    function _decodeSubScore(uint256 code) internal pure returns (uint16) {
        if (code <= 500) return uint16(code);
        if (code >= 961) return 30_000;
        return uint16(500 + ((code - 500) << 6));
    }

    function _subQuantity(uint256 lane) internal pure returns (uint256) {
        return ((lane >> SUB_QTY_SHIFT) & 7) + 1;
    }

    function _subDay(uint256 lane) internal pure returns (uint24) {
        return uint24((lane >> SUB_DAY_SHIFT) & SUB_DAY_MASK);
    }

    function _subCheckpointStreak(uint256 lane) internal pure returns (uint256) {
        return (lane >> SUB_STREAK_SHIFT) & SUB_STREAK_MAX;
    }

    /// @dev Rewrite a lane's checkpoint day and streak, saturating the streak.
    function _withSubCheckpoint(uint256 lane, uint256 day, uint256 streak) internal pure returns (uint256) {
        if (streak > SUB_STREAK_MAX) streak = SUB_STREAK_MAX;
        return (lane & ~((SUB_DAY_MASK << SUB_DAY_SHIFT) | (SUB_STREAK_MAX << SUB_STREAK_SHIFT)))
            | (day << SUB_DAY_SHIFT) | (streak << SUB_STREAK_SHIFT);
    }

    /// @dev Last day whose subscriber pass completed: rewards accrue through it and no further,
    ///      so a day is never credited before its purchase has run.
    function _afkingEndpoint() internal view returns (uint24) {
        return _afkingEndpointDay;
    }

    /// @dev Live streak of a lane at endpoint `endpoint`.
    function _subStreakAt(uint256 lane, uint24 endpoint) internal pure returns (uint256 streak) {
        streak = _subCheckpointStreak(lane);
        uint24 day = _subDay(lane);
        if (endpoint > day) streak += endpoint - day;
    }

    /// @dev Protocol subscription flags in `_afkingProtocolFlags`. The two BOUGHT bits record
    ///      which protocol seats bought into the current box cohort. A protocol seat is paused
    ///      while any of its pause bits is set: the Vault owner's pause (sticky, set and cleared
    ///      only by the owner) or an unfunded pause (cleared by preparation on the first day the
    ///      seat can pay again).
    uint8 internal constant AFK_VAULT_BOUGHT = 1;
    uint8 internal constant AFK_SDGNRS_BOUGHT = 2;
    uint8 internal constant AFK_VAULT_OWNER_PAUSED = 4;
    uint8 internal constant AFK_VAULT_UNFUNDED = 8;
    uint8 internal constant AFK_SDGNRS_UNFUNDED = 16;

    function _protocolPaused(uint32 id) internal view returns (bool) {
        uint8 flags = _afkingProtocolFlags;
        if (id == VAULT_WALLET_ID) return flags & (AFK_VAULT_OWNER_PAUSED | AFK_VAULT_UNFUNDED) != 0;
        if (id == SDGNRS_WALLET_ID) return flags & AFK_SDGNRS_UNFUNDED != 0;
        return false;
    }

    /// @dev A member's lane, or 0 when `id` is not in the set.
    function _subLaneOf(uint32 id) internal view returns (uint256 lane, uint256 position1) {
        position1 = _subPosition1(id);
        if (position1 != 0) lane = _subLaneAt(position1 - 1);
    }

    /// @dev The live (non-removed) afking streak for wallet `id` if it is mid-run; otherwise
    ///      (false, 0), so callers fall back to the manual streak. No DegenerusQuests STATICCALL.
    function _liveAfkingStreak(uint32 id) internal view returns (bool live, uint32 streak) {
        (uint256 lane, uint256 position1) = _subLaneOf(id);
        if (position1 == 0 || lane & SUB_REMOVAL_BIT != 0) return (false, 0);
        // At most 2^16 - 1 + 2^22 days: always fits.
        streak = uint32(_subStreakAt(lane, _afkingEndpoint()));
        live = streak != 0;
    }

    /// @dev Single source of truth for a player's effective quest streak, so the activity score
    ///      is one unified value everywhere it is read. A live afking sub reads its derived streak;
    ///      everyone else (and a run pending removal) reads the manual decay-aware streak.
    function _effectiveQuestStreak(uint32 id) internal view returns (uint32) {
        // Most players are not afking subs, so learn the afking flag from the quest-streak read we
        // make anyway: a non-afker returns here with no subscriber lookup. ID 0 has no quest
        // state: (0, false).
        (uint32 manualStreak, bool afking) = quests.effectiveBaseStreakAndAfking_g1521(id, dailyIdx);
        if (!afking) return manualStreak;
        (bool live, uint32 a) = _liveAfkingStreak(id);
        return live ? a : manualStreak;
    }

    /// @dev Reverse lookup by wallet ID, four 64-bit lanes per word (lane `id & 3` of key
    ///      `id >> 2`): [0..10] set position + 1 (0 = not a member), [11..32] run-start day, the
    ///      daily draw's age base; bit 63 retains an allocated lane. Only individual interactions
    ///      read it; the daily passes walk
    ///      `_subscribers` directly.
    mapping(uint256 => uint256) internal _subMeta;

    function _subMetaLane(uint32 id) internal view returns (uint256) {
        return uint64(_subMeta[id >> 2] >> ((id & 3) * 64)) & ((uint256(1) << 63) - 1);
    }

    function _setSubMetaLane(uint32 id, uint256 lane) internal {
        uint256 shift = (id & 3) * 64;
        uint256 key = id >> 2;
        _subMeta[key] = (_subMeta[key] & ~(uint256(type(uint64).max) << shift))
            | ((lane | (uint256(1) << 63)) << shift);
    }

    function _subPosition1(uint32 id) internal view returns (uint256) {
        return _subMetaLane(id) & 0x7ff;
    }

    function _subRunStart(uint32 id) internal view returns (uint24) {
        return uint24((_subMetaLane(id) >> 11) & SUB_DAY_MASK);
    }

    function _setSubPosition1(uint32 id, uint256 position1) internal {
        _setSubMetaLane(id, (_subMetaLane(id) & ~uint256(0x7ff)) | position1);
    }

    function _setSubRunStart(uint32 id, uint256 day) internal {
        _setSubMetaLane(id, (_subMetaLane(id) & 0x7ff) | (day << 11));
    }

    /// @dev Two-ended packed set: boxes at [0,B), tickets descending from 2000, at most
    ///      2000 members and one empty sentinel. The length word is logical membership,
    ///      NOT the physical extent. Use _subLaneAt/_setSubLaneAt; never index/push/pop.
    ///      Vault and sDGNRS remain at box positions 0 and 1; protocol ticket mode is forbidden.
    uint256[] internal _subscribers;

    /// @dev Purchase cursor: bit 15 selects tickets, low bits are the section offset.
    ///      Packed with the opening cursor, reset day and cohort counters below.
    uint16 internal _subCursor;

    /// @dev Monotonic physical box position, reset once before each daily preparation.
    uint16 internal _subOpenCursor;

    /// @dev The day the process STAGE was last reset for. When the advance first enters
    ///      a new `day` with the lock down and `_recordedDailyWord(day)` still uncommitted
    ///      (`_afkingResetDay != day`), it resets `subsFullyProcessed` + the
    ///      `_subCursor` and `_subOpenCursor` ONCE, before that day's STAGE drains — a forward-looking reset
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

    /// @dev Exact count of stamped but unopened boxes. Preparation and the monotonic opener
    ///      each apply their chunk's total in one write.
    ///      The scheduler finishes the prior cohort before preparation; subscribe locks all
    ///      membership/configuration changes until this cohort opens. Zero is the O(1) done
    ///      check. Shares the cursor slot; at most 2000 paid stamps fit the subscriber set.
    uint16 internal _pendingBoxCount;

    /// @dev Box-side membership. Ticket count is _subscribers.length - _subBoxCount.
    ///      Subscription changes are locked from daily due through the last AFKing open.
    uint16 internal _subBoxCount;

    /// @dev Spend per unit of the current box cohort in milli-ETH, written by the preparation
    ///      pass that stamps it and read by its openings (ticket prices are 0.01-ETH multiples).
    uint16 internal _afkingCohortPriceMilli;

    /// @dev Protocol subscription flags (AFK_* above): which protocol seats bought into the
    ///      current box cohort, and each protocol seat's pause bits.
    uint8 internal _afkingProtocolFlags;

    /// @dev The last day whose subscriber pass completed, written as the pass completes: the
    ///      reward endpoint `_afkingEndpoint`.
    uint24 internal _afkingEndpointDay;

    uint256 internal constant SUBSCRIBER_CAP = 2000;
    uint256 internal constant SUBSCRIBER_TICKET_PHASE = 1 << 15;

    // =========================================================================
    // Foil Pack
    // =========================================================================

    /// @dev Two reusable day lanes per player, set before payout. Each 32-bit lane
    ///      stores its exact day [0..23] and four ticket claim bits [24..27].
    mapping(uint32 => uint256) internal foilMatchClaimed;

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
    /// @dev Keeps the cohort cursor word allocated when both queues are empty.
    bool internal foilSlotRetained;

    /// @dev Lifetime gift counts per recipient: one four-bit lane per deity ordinal.
    ///      Each lane caps at ten and remains nonzero after its first gift.
    mapping(uint32 => uint128) internal deityRecipientBoonCount;

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
        uint256 today = _latestDailyResultDay();
        return day != 0 && day <= dailyIdx && (today <= day || today - day <= 1);
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
        uint24 today = _latestFoilDrawDay();
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
        uint256 seed = uint128(uint256(EntropyLib.hash2(RngTags.FOIL_PAYOUT, rngWord)));
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

    /// @dev Unspent request credit in wei; donations bank floor(value / 4).
    /// Only the donor's own mineFlip can spend it, against nonempty pending work.
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

    /// @dev Latest generation window: level in low 24 bits, first block above it.
    ///      Repeated marks preserve the first block; historical bounds are emitted.
    ///      Level 1 starts at deployment. This is discovery metadata, not a payout gate.
    uint256 internal ticketGenerationStartBlock;
    event TicketGenerationStarted(uint24 indexed level, uint256 blockNumber);

    function _markTicketGenerationStart(uint24 lvl) internal {
        if (uint24(ticketGenerationStartBlock) == lvl) return;
        ticketGenerationStartBlock = (block.number << 24) | lvl;
        emit TicketGenerationStarted(lvl, block.number);
    }

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
        if (lvl != decEntriesLevel || id == 0 || id > decBattleRounds[lvl].count) return 0;
        uint256 p = uint256(id) - 1;
        return uint128(decBattleEntries[p >> 1] >> ((p & 1) * 128));
    }

    function _storeDecEntry(uint24 lvl, uint64 id, uint256 word) internal {
        if (id == 0) return;
        uint256 p = uint256(id) - 1;
        uint256 key = p >> 1;
        uint256 lane = uint128(word);
        if (p & 1 == 0 && id == decBattleRounds[lvl].count) {
            decBattleEntries[key] = lane;
        } else {
            uint256 shift = (p & 1) * 128;
            decBattleEntries[key] = (decBattleEntries[key] & ~(uint256(type(uint128).max) << shift))
                | (lane << shift);
        }
    }

    /// @dev The shared session payload is usable by lootbox consumers only after fulfillment.
    ///      Daily callback stores its final nudge; the miner publishes readiness and unlock retains it.
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

    /// @dev The word holding positions `3k..3k+2`. Callers bound positions to [0,2000].
    function _subscriberWordAt(uint256 position) internal view returns (uint256 word) {
        assembly ("memory-safe") {
            mstore(0, _subscribers.slot)
            word := sload(add(keccak256(0, 32), div(position, 3)))
        }
    }

    function _subLaneAt(uint256 position) internal view returns (uint256) {
        return (_subscriberWordAt(position) >> ((position % 3) * SUB_LANE_BITS)) & SUB_LANE_MASK;
    }

    function _subscriberAt(uint256 position) internal view returns (uint32) {
        return uint32(_subLaneAt(position));
    }

    /// @dev Preserve the word's other two lanes, including across the empty section gap.
    function _setSubLaneAt(uint256 position, uint256 lane) internal {
        uint256 shift = (position % 3) * SUB_LANE_BITS;
        uint256 mask = SUB_LANE_MASK << shift;
        lane <<= shift;
        assembly ("memory-safe") {
            mstore(0, _subscribers.slot)
            let slot := add(keccak256(0, 32), div(position, 3))
            sstore(slot, or(and(sload(slot), not(mask)), lane))
        }
    }

    /// @dev Logical length only: physical ticket positions deliberately lie beyond it.
    function _setSubscriberCount(uint256 count) internal {
        assembly ("memory-safe") { sstore(_subscribers.slot, count) }
    }

    function _lootboxReadComplete() internal view virtual returns (bool) {
        return _rngComplete();
    }

    /// @dev One ordering authority for the miner and its read-consumer workers. The read
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
    event DailySessionCompleted(uint24 indexed day, uint48 completedAt);

    function _certifyRngComplete() internal {
        _setRngComplete(true);
        if (!dailyComplete && rngRequestDay == dailyIdx && !gameOver
            && rngFlagsAndNudges & (uint16(1) << 13) == 0) {
            dailyComplete = true;
            lastDailyCompletedAt = uint48(block.timestamp);
            emit DailySessionCompleted(dailyIdx, lastDailyCompletedAt);
        }
    }

    function _tryCompleteRng() internal {
        if (_rngComplete() || rngLockedFlag || _rngRequestActive() || !_rngSessionPublished()) return;
        if (_rngConsumersComplete()) _certifyRngComplete();
    }
    uint256 internal constant LR_CRAPS_PENDING_SHIFT = 250;

    function _ticketBufferLevel(uint24 lvl) internal view returns (uint24 result) {
        assembly ("memory-safe") {
            result := and(shr(add(mul(ticketBufferLevels.offset, 8), mul(and(lvl, 1), 24)), sload(ticketBufferLevels.slot)), 0xffffff)
        }
    }

    function _setTicketBufferLevel(uint24 lvl) internal {
        uint256 shift = (lvl & 1) * 24;
        if (uint24(uint256(ticketBufferLevels) >> shift) != lvl) traitBucketStale |= uint8(1 << (lvl & 1));
        ticketBufferLevels = uint48((uint256(ticketBufferLevels) & ~(uint256(type(uint24).max) << shift))
            | (uint256(lvl) << shift));
    }

    function _traitBitmap(uint24 lvl) internal view returns (uint256) {
        if (_ticketBufferLevel(lvl) != lvl || traitBucketStale & (1 << (lvl & 1)) != 0) return 0;
        return traitBucketLive[lvl & 1];
    }

    function _ticketLevelRetired(uint24 lvl) internal view returns (bool) {
        return _ticketBufferLevel(lvl) > lvl;
    }

    function _assertReadableTicketLevel(uint24 lvl) internal view {
        if (_ticketLevelRetired(lvl)) revert E();
    }

    /// @dev Select once for batch loops; the branch prevents arithmetic rematerialization.
    function _traitBatchBase(uint24 lvl) internal pure returns (uint256 base) {
        assembly ("memory-safe") {
            switch and(lvl, 1)
            case 0 { base := lvlTraitEntry.slot }
            default { base := add(lvlTraitEntry.slot, 256) }
        }
    }

    function _traitBufferBase(uint24 lvl) internal pure returns (uint256 base) {
        assembly ("memory-safe") {
            base := add(lvlTraitEntry.slot, shl(8, and(lvl, 1)))
        }
    }

    /// @dev Every production append adds at least one entry, and entries are never
    ///      removed from an active level. Its live bit therefore proves gold six was
    ///      taken without reading the bucket header. Authenticate the full level so
    ///      recycled parity buffers cannot carry the cap into a later level.
    function _goldSixTaken(uint24 lvl) internal view returns (bool) {
        uint24 storedLevel = _ticketBufferLevel(lvl);
        if (storedLevel > lvl) revert E();
        return storedLevel == lvl && _traitBitmap(lvl) & (uint256(1) << GoldSixLib.TRAIT) != 0;
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
            let stamps := sload(ticketBufferLevels.slot)
            if and(eq(and(shr(shift, stamps), 0xffffff), lvl),
                iszero(and(stamps, shl(add(mul(traitBucketStale.offset, 8), parity), 1)))) {
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
        return _levelPrizePool(lvl);
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

    /// @dev `kind` alone marks the record live. Retiring clears only it; every start writes the
    ///      whole record, so no field of a retired leg is ever read.
    function _retireJackpotWork() internal {
        jackpotWork.kind = 0;
    }

    /// @dev Start a leg: both words written whole (paid, winner and direct round zero). Bit
    ///      offsets follow the struct's compiled layout: traits 0, lvl 32, kind 72, quadrant 80,
    ///      finalDay 88, directTickets 128.
    function _startJackpotWork(uint128 budget, uint32 traits, uint24 lvl, uint8 kind, uint8 quadrant,
        bool finalDay, bool directTickets) internal
    {
        uint256 head = uint256(traits) | (uint256(lvl) << 32) | (uint256(kind) << 72)
            | (uint256(quadrant) << 80) | (finalDay ? uint256(1) << 88 : 0)
            | (directTickets ? uint256(1) << 128 : 0);
        assembly ("memory-safe") {
            sstore(jackpotWork.slot, budget)
            sstore(add(jackpotWork.slot, 1), head)
        }
    }

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

    /// @dev Covers the bonus chips an entry can add before its multiplier: the decimator boon's
    ///      25,000 FLIP plus quest rewards.
    uint256 private constant DEC_AUTO_BONUS_MARGIN = 30_000;

    /// @dev Four times the previous round's average entry.
    function _decReferenceCap() internal view returns (uint256) {
        return decPreviousCount == 0 ? 8000 : uint256(decPreviousStack) * 4 / decPreviousCount;
    }

    /// @dev The reference cap, held inside round `lvl`'s 64-bit aggregate: credited weight is at
    ///      most twice the entry plus its bonus chips, so the automatic entry inside DailyApply
    ///      can never trip the aggregate bound.
    function _decAutomaticCap(uint24 lvl) internal view returns (uint256 cap) {
        cap = _decReferenceCap();
        uint256 room = (type(uint64).max - uint256(decBattleRounds[lvl].totalCreditedStack)) / 2;
        uint256 fit = room > DEC_AUTO_BONUS_MARGIN ? room - DEC_AUTO_BONUS_MARGIN : 0;
        if (fit < cap) cap = fit;
    }

    error AfkingStethPullFailed();
    /// @dev Forward identity lookup for address-boundary authorization and ERC20 integration.
    ///      Mint statistics are stored separately by ID; only ordinary-wallet registration writes this.
    // Low 32 bits: current gameplay account. High 32: immutable wallet identity.
    mapping(address => uint64) internal walletIds;

    /// @dev Smurf IDs by owning main ID, eight packed uint32 lanes per word (lane `i & 7` of word
    ///      `i >> 3`). Append-only at `createSmurf`; the main's lifetime `SMURF_COUNT` in
    ///      `mintPacked_` is the list length. A main's loan seizure walks it to stop the family's AFKing.
    mapping(uint32 => mapping(uint256 => uint256)) internal _smurfWords;

    // =========================================================================
    // Account loans
    // =========================================================================

    /// @dev Open loan by account ID; zero means none. Packed: principal wei (bits 0-95),
    ///      lender wallet ID (96-103), level at borrowing (104-127), due level (128-151),
    ///      index in `_loansDue[due]` (152-183), subscriptions its seizure may cancel (184-191).
    mapping(uint32 => uint256) internal _loans;
    /// @dev Account IDs due at each level, eight packed uint32 lanes per word.
    mapping(uint24 => mapping(uint256 => uint256)) internal _loansDue;
    /// @dev Open loans due at each level; seizure leaves a level's count behind.
    mapping(uint24 => uint256) internal _loansDueCount;

    uint256 internal constant LOAN_MIN_PRINCIPAL = 0.05 ether;
    uint256 internal constant LOAN_INTEREST_BPS_PER_LEVEL = 500;
    uint256 internal constant LOAN_EARLY_FEE_BPS_PER_LEVEL = 100;
    uint256 internal constant LOAN_MAX_SMURFS = 5;
    /// @dev Borrowing needs dueLevel + 2 <= the live ticket level + LOAN_HORIZON_LEVELS, and the
    ///      live ticket level is at most level + 1, so every open loan is due by
    ///      level + LOAN_HORIZON_LEVELS - 1. Game over settles exactly that range.
    uint256 internal constant LOAN_HORIZON_LEVELS = 100;
    /// @dev A loan taken more than this many days into a level pays half its principal as tickets.
    uint256 internal constant LOAN_TICKET_AFTER_DAYS = 20;

    uint256 internal constant LOAN_RETAINED = 1 << 255;
    uint256 internal constant LOAN_LENDER_SHIFT = 96;
    uint256 internal constant LOAN_START_SHIFT = 104;
    uint256 internal constant LOAN_DUE_SHIFT = 128;
    uint256 internal constant LOAN_INDEX_SHIFT = 152;
    uint256 internal constant LOAN_FAMILY_SHIFT = 184;

    /// @dev What repaying `loan` costs while the game is at level `lvl` (at most its due level):
    ///      principal plus 5% per level used (at least one) plus 1% per unused level of the
    ///      chosen term. At the due level every level is used, so this is the full term.
    function _loanOwedAt(uint256 loan, uint256 lvl) internal pure returns (uint256) {
        uint256 start = uint24(loan >> LOAN_START_SHIFT);
        uint256 used = lvl > start ? lvl - start : 1;
        return uint96(loan) * (10_000 + used * LOAN_INTEREST_BPS_PER_LEVEL
            + (uint24(loan >> LOAN_DUE_SHIFT) - start - used) * LOAN_EARLY_FEE_BPS_PER_LEVEL) / 10_000;
    }

    function _loanDueAt(uint24 due, uint256 i) internal view returns (uint32) {
        return uint32(_loansDue[due][i >> 3] >> ((i & 7) << 5));
    }

    function _setLoanDueAt(uint24 due, uint256 i, uint32 id) internal {
        uint256 shift = (i & 7) << 5;
        uint256 word = _loansDue[due][i >> 3];
        _loansDue[due][i >> 3] = (word & ~(uint256(type(uint32).max) << shift)) | (uint256(id) << shift);
    }

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

    // =========================================================================
    // Degenesis Orders
    // =========================================================================

    /// @dev The settling cohort's daily word, copied when its bound day's word is recorded.
    uint256 internal degenesisWord;
    /// @dev Per Degenesis day (1..7): [0:48] volume V in DEGENESIS_UNIT, [48:80] order count, [80] split.
    mapping(uint256 => uint256) internal degenesisDays;
    /// @dev Orders keyed degenesisDay << 32 | index / 3, three 85-bit lanes per word, order `index`
    ///      at bit 85 * (index % 3): [0:32] wallet ID, [32:70] amount in DEGENESIS_UNIT,
    ///      [70:85] seconds into its day, capped at DEGENESIS_BONUS_WINDOW.
    mapping(uint256 => uint256) internal degenesisOrders;
    /// @dev Dedicated redemption reserve, amount + 1; releasing it never clears this home.
    uint128 internal _redemptionReserveStored = 1;

    /// @dev Two parity buffers of 256 headers: uint32 count plus seven uint32 tail lanes.
    ///      Full buffer levels and traitBucketLive authenticate each header. Completed
    ///      eight-lane words start at keccak256(headerSlot).
    uint256[256][2] internal lvlTraitEntry;

    uint256 internal constant DEGENESIS_DAYS = 7;
    uint256 internal constant DEGENESIS_UNIT = 0.0001 ether;
    uint256 internal constant DEGENESIS_MIN = 0.01 ether;
    /// @dev Per-order bound in DEGENESIS_UNIT (about 27.5M ETH); larger orders revert.
    uint256 internal constant DEGENESIS_AMOUNT_MASK = (uint256(1) << 38) - 1;
    uint256 internal constant DEGENESIS_LANE_BITS = 85;
    uint256 internal constant DEGENESIS_LANE_MASK = (uint256(1) << 85) - 1;
    uint256 internal constant DEGENESIS_AMOUNT_SHIFT = 32;
    uint256 internal constant DEGENESIS_SECONDS_SHIFT = 70;
    uint256 internal constant DEGENESIS_BONUS_WINDOW = 6 hours;
    uint256 internal constant GD_COUNT_SHIFT = 48;
    uint256 internal constant GD_SPLIT = uint256(1) << 80;
    uint256 internal constant GA_FIELD_MASK = (uint256(1) << 80) - 1;
    uint256 internal constant GA_PAID_SHIFT = 80;
    uint256 internal constant GA_DAY_SHIFT = 160;
    uint256 internal constant GA_CURSOR_SHIFT = 184;

    function _degenesisCreditOpen() internal view returns (bool) {
        return dailyIdx < GameTimeLib.MAIN_LAUNCH_DAY;
    }

    /// @dev Credit 25% of a qualifying spend while the window is open. The protocol bodies earn none.
    function _accrueDegenesisCredit(uint32 id, uint256 spend) internal {
        if (_degenesisCreditOpen() && id != VAULT_WALLET_ID && id != SDGNRS_WALLET_ID) {
            degenesisCredit[id] += spend / 4;
        }
    }

    /// @dev A priced cohort's word has arrived and the game is not terminal. The word is set only
    ///      for the active cohort and cleared when it closes.
    function _degenesisSettlePending() internal view returns (bool) {
        return degenesisClosed < DEGENESIS_DAYS && rngFlagsAndNudges & (uint16(1) << 13) == 0 && degenesisWord != 0;
    }
    /// @dev Frozen and accumulating hero pools, each three packed symbol quadrants.
    uint256[3][2] internal dailyHeroWagers;

    /// @dev Two reusable word slots, indexed by day parity and authenticated
    ///      by rngDayTags. Events provide historical replay; live views expose
    ///      today/yesterday only.
    uint256[2] internal rngWordByDay;

    /// @dev Four retained prize snapshots: uint128 amount below a level+1 tag.
    uint256[4] internal levelPrizePool;

    /// @dev Two reusable draws keyed by day & 1: traits [0..31], level [64..87],
    ///      payout seed [88..215], seed-present flag 216, exact day [217..240].
    uint256[2] internal dailyFoilDraw;

    /// @dev Reverse lookup: symbol ID (0-31) → the holding deity's wallet ID (0 = unclaimed).
    uint256[32] internal deityBySymbol;

    /// @dev The leaderboard of the round at the head of the queue, keyed by heap position: a
    ///      node is its score (whole-FLIP stack x normalized peak) above the 64-bit entry id, and
    ///      equal scores order by a random tiebreak recomputed from the id. The FIFO settles one
    ///      round at a time, so every round reuses these slots.
    uint256[200] internal decBattleHeap;

    /// @dev Four reusable pack slots per player, keyed by level & 3 and authenticated
    ///      by the full level at bits 208..231. Purchase freezes boost and activity, but no day.
    ///      Materialization writes four uint32 lines at bits 56..183, the first
    ///      eligible draw at bits 0..23, generation day at bits 184..207, and ready
    ///      at bit 255. Bit 232 marks gold paid. No historical reveal word is needed after generation.
    mapping(uint32 => uint256)[4] internal foilRecord;

    /// @dev Two-slot rings keyed [issuer index][day & 1] (Vault 0, sDGNRS 1); each day reuses slots written two
    ///      days earlier instead of fresh zero slots. Sound because day D's pool and entries are
    ///      written only on logical day D and drawn only on logical day
    ///      D + 1 (resolveProtocolBoonDraws returns unless the award day is today), so when day
    ///      D + 2 reuses the slots, day D has been drawn or never can be. A pool whose `day` tag
    ///      is not the day asked for holds another day and reads as empty; the first entry
    ///      of a new day resets it. Entries at or past the pool's entryCount are leftovers.
    ProtocolBoonPool[2][2] internal protocolBoonPools;

    mapping(uint32 => ProtocolBoonEntry)[2][2] internal protocolBoonEntries;

    /// @dev Box purchase queue per physical RNG buffer (keys 0/1): one 85-bit entry per
    ///      purchase, three to a word, appended to the write buffer and settled FIFO from
    ///      `boxCursor` once the buffer is sealed and its word published. Entries are never
    ///      updated after their append. Logical position `p` sits in word
    ///      `keccak256(boxQueue[buffer].slot) + p / 3` at bit `(p % 3) * 85`; the write count
    ///      lives in lootboxRngPacked and the read length in `boxReadCount`, both in entries.
    ///      Never use Solidity length, push, pop or element indexing for these packed payloads. A drained buffer is
    ///      reused by resetting only its count. Entry layout: the LB_* constants.
    uint256[][2] internal boxQueue;

    /// @dev Foil read/write cohorts (keys 0/1), frozen at the daily request only.
    ///      New buys always append to the write half. Manually addressed: pack `p` of cohort
    ///      `key` sits at `keccak256(foilQueue[key].slot) + p`, and the cohort lengths are
    ///      foilWriteCount / foilReadCount. Never use Solidity length, push, pop or indexing.
    uint256[][2] internal foilQueue;

    /// @dev Degenerette bets per physical RNG buffer, two 128-bit lanes per word in placement order.
    ///      A bet's id is its position + 1. Placement appends only to the write buffer; the
    ///      ordered miner chain resolves the read buffer after its box entries. The cursor authenticates
    ///      the resolved prefix. Manually addressed like `boxQueue`: bet `p` sits at
    ///      `keccak256(degeneretteQueue[buffer].slot) + (p >> 1)`, the write count lives in
    ///      lootboxRngPacked and the read length in `degeneretteReadCount`. Never use Solidity
    ///      length, push, pop or element indexing for these packed payloads.
    ///      Compact layout used by storage, resolution, events and views (lane p & 1):
    ///      - [0..31]    owner wallet ID
    ///      - [32..36]   chosen hero symbol (0..23; hero quadrant = symbol >> 3; Dice excluded)
    ///      - [37..41]   spin count (1..25)
    ///      - [42]       currency (0 = ETH, 1 = FLIP)
    ///      - [43]       record flag: a biggest-spin record bounty waits in degeneretteRecordBounty
    ///      - [44..59]   activity score in whole points
    ///      - [60..123]  stake per spin in currency units (ETH: gwei, FLIP: whole FLIP)
    ///      - [124..127] reserved (always zero)
    uint256[][2] internal degeneretteQueue;

    function _protocolBoonIndex(uint32 issuer) internal pure returns (uint256) {
        return issuer == VAULT_WALLET_ID ? 0 : 1;
    }

}
