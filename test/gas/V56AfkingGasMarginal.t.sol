// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title V56AfkingGasMarginal -- the v56 everyday-afking gas-MARGINAL harness (Phase 355, GAS-01/GAS-02)
///        on the e18af451 applied tree (baseline 453f8073). Measures every marginal the GAS phase needs:
///        the per-buy LOOTBOX marginal, the per-buy TICKET marginal (the new minimal-write primitive), the
///        per-OPEN marginal, the per-SETTLE marginal (the settle-day chunk riding the buy stage), and the
///        WORST-CASE per-tx chunk for EVERY batched advance/afking loop — the settle-day STAGE chunk at
///        SUB_STAGE_BATCH (the binding case, where every sub fires _settleQuest) and the OPEN_BATCH open
///        chunk. From each measured worst-case per-item marginal it DERIVES the max safe batch (the largest
///        N keeping the per-tx chunk under the 10M comfort TARGET) and reports the dual bound (< 10M target,
///        provably <= 16.7M hard ceiling). Also proves GAS-02 empirically: the per-buy in-slot accrue makes
///        NO new cold per-buy SSTORE.
///
/// @notice The v56 applied tree (what THIS harness measures — the v55 storm described in the old
///         V55AfkingGasMarginal header is GONE):
///
///         (1) The per-buy hot path (GameAfkingModule.processSubscriberStage, :582-929) collapsed: the
///             SOLVENCY-01 debit (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`,
///             :744-745, byte-frozen from v55) → the per-mode primitive (lootbox box-stamp OR the NEW ticket
///             minimal-write `_queueTicketsScaled` + buyerOwedBurnie accrue, replacing the ~262k purchaseWith
///             heavyweight) → the MODE-AGNOSTIC in-slot accrue (:887-900: affiliateBase flat-7% +=,
///             ++questProgress, afkCoveredThroughDay = processDay) → the lastAutoBoughtDay marker (:907) →
///             IF processDay % SETTLE_PERIOD == 0 THEN _settleQuest (:916-918). The per-buy cross-contract
///             quest/affiliate/coinflip storm of v55 is DEFERRED to the ~10-day aggregator: the everyday buy
///             is a warm SLOAD-mask-SSTORE on ONE Sub slot, no cross-contract calls except the rare settle
///             day.
///
///         (2) The Sub slot (DegenerusGameStorage.sol:1894-1962) is a SINGLE 256-bit slot, 241/256 bits used:
///             config 48 + stamp 48 (scorePlus1 uint16 / amount uint32 milli-ETH) + markers 72
///             (lastAutoBoughtDay/lastOpenedDay/afkCoveredThroughDay uint24 each) + accumulator 73
///             (affiliateBase uint32 / questProgress uint8 / buyerOwedBurnie uint32 / hasEverSubscribed bool).
///             The accumulator is IN-SLOT — the per-buy accrue is a warm write on the SAME slot the stamp
///             dirtied, NOT a new cold slot. THIS is the GAS-02 property (proven in Task 3). The day markers
///             narrowed to uint24 and the accumulator fields are NEW vs v55, so the byte offsets are
///             RE-DERIVED below (the v55 OFF_LASTBOUGHT=21 / OFF_LASTOPENED=25 premise is WRONG here).
///
///         (3) The settle-day ride (:916-918): on a global settle boundary (processDay % SETTLE_PERIOD == 0,
///             ~10-day cadence) every sub fires _settleQuest (:1141 — one coinflip.creditFlip of
///             questProgress×QUEST_SLOT0_REWARD + buyerOwedBurnie, + quests.settleAfkingQuest streak-advance,
///             then drains both counters to 0). The settle-day STAGE chunk is the BINDING worst case for
///             SUB_STAGE_BATCH (every sub pays the settle overhead).
///
/// @notice The MARGINAL rule (CR-01 / 350-SPEC §0, load-bearing, verbatim): every per-item number is the
///         loop-N-divide MARGINAL — (gas for N items − gas for N−1 items), NEVER a single-item TOTAL. A
///         single-item total over-states the per-item cost and (were a reward pegged to it) re-introduces
///         the Phase-319 self-crank faucet. Both the N and the N−1 measurements run from ONE identical clean
///         baseline via `vm.snapshotState()` / `vm.revertToState()` — a LINEAR two-cycle run trips the
///         idle-fixture day saturation + an unfulfilled-RNG `RngNotReady` on the second cycle (the 351-07
///         documented failure). The snapshot/revert form gives both measurements the SAME fresh state, so
///         (gasN − gasNm1) isolates exactly the Nth item's cost.
///
/// @notice The DUAL BOUND (USER-LOCKED this phase): every batched per-tx loop in the daily advance / afking
///         chain must be sized so its WORST-CASE gas TARGETS < 10,000,000 (GAS_TARGET — the design comfort
///         target) AND PROVABLY NEVER EXCEEDS 16,700,000 (EFFECTIVE_GAS_CEILING — the HARD never-exceed kill
///         ceiling; a breach = advanceGame DoS / forced game-over). The headroom (16.7M − the measured chunk
///         at the chosen batch) is the safety margin that absorbs measurement variance + worst-case
///         outliers. foundry.toml inflates block_gas_limit to 30e9 for the harness; the bar is the 16.7M.
///         For each batched loop the harness DERIVES the max safe batch: max N = the largest integer with
///         fixed_tx_overhead + N×worst_case_per_item_marginal < GAS_TARGET ("optimal" = that largest N), and
///         cross-checks the current constant <= that derived N (an over-large constant FAILS the test).
///
/// @dev Live `DeployProtocol` fixture; reuses the validated game-resident driving harness (the
///      `_settleGame`/`_settleClean` VRF drain, the funded-sub setup, `depositAfkingFunding` funding,
///      `_grantDeityPass`, the Sub-slot reads, the snapshot/revert two-near-N form) ported from
///      V55AfkingGasMarginal. All pinned slots RE-DERIVED via `forge inspect DegenerusGame storage` /
///      `storageLayout` against the e18af451 tree (`_subOf = 66`, `_subscribers = 68`, `_subCursor = 70:0`,
///      `_subOpenCursor = 70:2`, `rngWordByDay = 11`; the Sub field byte offsets re-derived from the v56
///      re-pack). Test-only: ZERO contracts/*.sol mutated (`git diff e18af451 -- contracts/` EMPTY).
contract V56AfkingGasMarginal is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots (RE-DERIVED via `forge inspect DegenerusGame storage` @ e18af451)
    // -------------------------------------------------------------------------

    uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — the afking box's DAY-keyed word + readiness gate
    uint256 private constant SUBOF_SLOT = 66;           // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 68;     // address[] _subscribers (slot holds the length)
    uint256 private constant SUBCURSOR_SLOT = 70;       // _subCursor (uint16 @ byte 0) + _subOpenCursor (uint16 @ byte 2) + _afkingResetDay (uint32 @ byte 4)

    // Sub packed-field byte offsets (DegenerusGameStorage.sol:1894-1962; RE-DERIVED via
    // `forge inspect DegenerusGame storageLayout` @ e18af451 — the v56 re-pack narrowed the day markers to
    // uint24 and ADDED the in-slot accumulator, so the v55 offsets are WRONG). Single 256-bit Sub slot:
    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u32 @8
    //   lastAutoBoughtDay u24 @12 · lastOpenedDay u24 @15 · afkCoveredThroughDay u24 @18
    //   affiliateBase u32 @21 · questProgress u8 @25 · buyerOwedBurnie u32 @26 · hasEverSubscribed bool @30
    uint256 private constant OFF_LASTBOUGHT = 12; // uint24 lastAutoBoughtDay (bytes 12..14)
    uint256 private constant OFF_LASTOPENED = 15; // uint24 lastOpenedDay     (bytes 15..17)
    uint256 private constant OFF_AFKCOVERED = 18; // uint24 afkCoveredThroughDay (bytes 18..20)
    uint256 private constant OFF_AFFBASE = 21;    // uint32 affiliateBase    (bytes 21..24)
    uint256 private constant OFF_QUESTPROG = 25;  // uint8  questProgress    (byte 25)
    uint256 private constant OFF_OWEDBURNIE = 26; // uint32 buyerOwedBurnie  (bytes 26..29)

    uint256 private constant MINTPACKED_SLOT = 10;
    uint256 private constant DEITY_SHIFT = 184;

    // -------------------------------------------------------------------------
    // Dual-bound + worst-case / measurement constants
    // -------------------------------------------------------------------------

    /// @dev The 10M design comfort TARGET (USER-LOCKED dual bound). Every batched per-tx loop's worst-case
    ///      chunk at the chosen batch must land BELOW this; the derived max-safe batch is the largest N with
    ///      fixed_overhead + N×worst_case_per_item_marginal < GAS_TARGET.
    uint256 internal constant GAS_TARGET = 10_000_000;

    /// @dev The 16.7M HARD never-exceed kill ceiling (USER-LOCKED dual bound). A breach = advanceGame DoS /
    ///      forced game-over. foundry.toml inflates block_gas_limit to 30e9 for the harness; the never-exceed
    ///      bar is this 16.7M. The headroom (16.7M − the measured-at-target chunk) is the safety margin.
    uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000;

    /// @dev SUB_STAGE_BATCH (DegenerusGameAdvanceModule.sol:149): one advanceGame() STAGE processes up to 50
    ///      funded subs (the per-day buy/stage chunk; there is NO standalone BUY_BATCH constant). The BINDING
    ///      worst case is the settle-day STAGE chunk (processDay % SETTLE_PERIOD == 0, every sub fires
    ///      _settleQuest).
    uint256 internal constant SUB_STAGE_BATCH = 50;

    /// @dev OPEN_BATCH (GameAfkingModule.sol:206): the flat per-box open chunk; each afking box uniform O(1).
    uint256 internal constant OPEN_BATCH = 200;

    /// @dev SETTLE_PERIOD (GameAfkingModule.sol:172): the quest leg settles inline on
    ///      processDay % SETTLE_PERIOD == 0 (~10-day cadence).
    uint256 internal constant SETTLE_PERIOD = 10;

    /// @dev SUBSCRIBER_CAP (GameAfkingModule.sol:164): the worst-case active sub count.
    uint256 internal constant SUBSCRIBER_CAP = 500;

    /// @dev Informational v55/349.2 per-buy lootbox reference (~206k, the v55 measured marginal WITH the
    ///      per-buy cross-contract storm) and the ~130-140k GAS-01 target band (the v56 deferred-settle win).
    ///      Reported as a comparison log, NOT a hard pin — the MEASURED number is the deliverable.
    uint256 internal constant V55_LOOTBOX_BUY_REF = 206_000;
    uint256 internal constant V56_LOOTBOX_TARGET_LO = 130_000;
    uint256 internal constant V56_LOOTBOX_TARGET_HI = 140_000;

    /// @dev The old per-day ~262k purchaseWith reference (the heavyweight the v56 ticket minimal-write
    ///      primitive replaces). Reported as the structural-win comparison for the ticket marginal.
    uint256 internal constant V55_TICKET_PURCHASEWITH_REF = 262_000;

    /// @dev N for the two-near-N marginal: measure N vs N−1 from one clean baseline (snapshot/revert). Big
    ///      enough that the funded set + the 2 deploy subs stay < SUB_STAGE_BATCH (one advance stamps all in
    ///      the first chunk), so the everything-else of the advance is identical across N and N−1.
    uint256 internal constant N_HI = 24;
    uint256 internal constant N_LO = 23;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    // =========================================================================
    // Derived-batch helper (the harness DERIVES the optimal batch, it is not guessed)
    // =========================================================================

    /// @dev The largest N with `fixedOverhead + N×perItemMarginal < GAS_TARGET` — the derived OPTIMAL
    ///      (max-safe, throughput-maximizing) batch size for a per-tx loop. If even N=0 already exceeds the
    ///      target (fixedOverhead >= GAS_TARGET) it returns 0. perItemMarginal must be non-zero (a measured
    ///      marginal always is; guarded to avoid div-by-zero).
    function _maxSafeBatch(uint256 fixedOverhead, uint256 perItemMarginal) internal pure returns (uint256) {
        if (perItemMarginal == 0) return 0;
        if (fixedOverhead >= GAS_TARGET) return 0;
        return (GAS_TARGET - 1 - fixedOverhead) / perItemMarginal;
    }

    // =========================================================================
    // Internal helpers (the validated game-resident driving harness)
    // =========================================================================

    /// @dev Measure a fresh-state new-day advance whose STAGE processes N funded LOOTBOX subs, returning the
    ///      bracketed advance gas. Settles to a clean baseline FIRST (so a prior measurement's unfulfilled
    ///      RNG cannot leave the game rngLocked). n + 2 deploy subs < SUB_STAGE_BATCH so ONE advance stamps
    ///      the whole set in the first chunk; the everything-else of the advance (empty ticket queue) is
    ///      identical across N and N−1 — the (gasN − gasNm1) difference isolates the Nth sub's STAGE cost.
    ///      `landOnSettleDay` warps so the advanced processDay lands on (true) or off (false) a settle
    ///      boundary, so the same helper serves the non-settle per-buy marginal and the settle-day chunk.
    function _measureStageAdvanceGas(uint256 n, string memory prefix, bool isTicket, bool landOnSettleDay)
        internal
        returns (uint256 advGas)
    {
        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "base"))) | 1);
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, isTicket);
        uint32[] memory pre = new uint32[](n);
        for (uint256 i; i < n; ++i) pre[i] = _lastBoughtDayOf(subs[i]);

        _warpToBoundary(landOnSettleDay);
        require(game.advanceDue(), "fixture: advanceDue on the new day");
        uint256 gasBefore = gasleft();
        game.advanceGame();
        advGas = gasBefore - gasleft();

        // Non-vacuity: every measured sub got a NEW stamp this cycle (a real STAGE buy, not a skip).
        for (uint256 i; i < n; ++i) {
            require(_lastBoughtDayOf(subs[i]) > pre[i], "marginal non-vacuity: each funded sub newly stamped");
        }
    }

    /// @dev Warp forward whole days until the next advance's processDay lands ON (settle) or OFF a settle
    ///      boundary (processDay % SETTLE_PERIOD == 0). The advance stamps with the new day index; we warp so
    ///      that next day index has the desired settle parity. Always advances at least one day so
    ///      advanceDue() is true.
    function _warpToBoundary(bool onSettle) internal {
        // The processDay the next advance will stamp is the simulated day for (now + 1 day). Warp day-by-day
        // until that day's settle parity matches the request.
        for (uint256 guardN; guardN < 2 * SETTLE_PERIOD; ++guardN) {
            vm.warp(block.timestamp + 1 days);
            uint32 nextDay = _simulatedDayIndex();
            bool isSettle = (uint256(nextDay) % SETTLE_PERIOD == 0);
            if (isSettle == onSettle) return;
        }
        revert("fixture: could not reach requested settle boundary");
    }

    /// @dev Measure the afking open-leg gas over N freshly-stamped + ready LOOTBOX afking boxes, returning
    ///      the bracketed `mintBurnie()` open-leg gas. The 2 deploy subs add a CONSTANT 2 ready boxes to BOTH
    ///      the N and N−1 measurements, so they cancel in the (gasN − gasNm1) difference — the marginal
    ///      isolates exactly one box. Each call stamps N subs (new-day STAGE), lands the stamp-day word,
    ///      settles clean (so mintBurnie routes to OPEN), opens all.
    function _measureOpenLegGas(uint256 n, string memory prefix) internal returns (uint256 openGas) {
        address[] memory subs = _setupFundedSubs(n, prefix, 5 ether, false);
        _runStageNewDay(uint256(keccak256(abi.encodePacked(prefix, "word"))) | 1);
        uint32 stampDay = _readStampDay(subs);
        require(stampDay > 0, "fixture: subs stamped");
        require(rngWordByDay(stampDay) != 0, "fixture: stamp-day word landed");
        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) < stampDay, "marginal pre: each box queued");
        }

        _settleClean(uint256(keccak256(abi.encodePacked(prefix, "clean"))) | 1);
        require(!game.advanceDue(), "fixture: clean so mintBurnie opens");
        vm.prank(makeAddr(string(abi.encodePacked(prefix, "opener"))));
        uint256 gasBefore = gasleft();
        game.mintBurnie();
        openGas = gasBefore - gasleft();

        for (uint256 i; i < n; ++i) {
            require(_lastOpenedDayOf(subs[i]) == stampDay, "marginal non-vacuity: each box opened");
        }
    }

    /// @dev Subscribe `n` fresh players as funded subs in the requested mode (lootbox = useTickets false /
    ///      ticket = useTickets true), deity-passed so pass-gated valid; funded via depositAfkingFunding so
    ///      the STAGE :744 afkingFunding debit + :745 claimablePool debit land in tandem (SOLVENCY-01
    ///      balanced). The STAGE stamps/queues each into a warm Sub slot (GAS-01) + runs the v56 mode-agnostic
    ///      in-slot accrue (no per-buy cross-contract storm — that is deferred to the settle day).
    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach, bool isTicket)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            _grantDeityPass(who);
            vm.prank(who);
            // self, mode = isTicket, qty 1, reinvest 0, self-funded
            game.subscribe(address(0), false, isTicket, 1, 0, address(0));
            _fundPool(who, poolEach);
        }
    }

    /// @dev Lootbox-mode funded subs (useTickets == false) — the box-stamp primitive.
    function _setupFundedLootboxSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory)
    {
        return _setupFundedSubs(n, prefix, poolEach, false);
    }

    /// @dev Ticket-mode funded subs (useTickets == true) — the new minimal-write `_queueTicketsScaled`
    ///      primitive (off the old ~262k purchaseWith). The ticket leg sets lastOpenedDay ==
    ///      lastAutoBoughtDay so a ticket sub never produces an afking box (open-leg never touches it).
    function _setupFundedTicketSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory)
    {
        return _setupFundedSubs(n, prefix, poolEach, true);
    }

    /// @dev Read the (uniform) stamp day across the subs (each was stamped the same process day by the STAGE).
    function _readStampDay(address[] memory subs) internal view returns (uint32) {
        return _lastBoughtDayOf(subs[0]);
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Drive a fresh new-day STAGE then land the day's word (the per-sub stamp becomes a ready box).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            // Fulfill any in-flight request FIRST (before advancing) — a stamping advance can leave the game
            // rngLocked with an unfilled word, and advanceGame() would revert RngNotReady if called while the
            // word is 0. Fulfilling at the loop top clears the lock so the next advance can proceed.
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A robust settle DEMANDING a clean (`!advanceDue && !rngLocked`) state before returning — used
    ///      before a mintBurnie open so it reliably takes the OPEN leg.
    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev Fulfill the latest pending mock-VRF request (idempotent — no-op if already fulfilled / none).
    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    // ---- Sub-slot reads (RE-DERIVED slot 66 + v56 offsets) ----

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24)); // uint24
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24)); // uint24
    }

    function _afkCoveredOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFKCOVERED, 24)); // uint24
    }

    function _affiliateBaseOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_AFFBASE, 32)); // uint32
    }

    function _questProgressOf(address who) internal view returns (uint8) {
        return uint8(_subField(who, OFF_QUESTPROG, 8)); // uint8
    }

    function _buyerOwedBurnieOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_OWEDBURNIE, 32)); // uint32
    }

    function _subscriberCount() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read the STAGE cursor `_subCursor` (slot 70, byte 0, uint16) — advances by SUB_STAGE_BATCH on a
    ///      full chunk.
    function _subCursor() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBCURSOR_SLOT)))) & 0xFFFF;
    }

    /// @dev Read the DAY-keyed afking word `rngWordByDay[day]` (the open leg's seed + readiness gate).
    function rngWordByDay(uint32 day) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)))));
    }

    /// @dev Land a word for a specific day directly (the open-readiness gate) when the natural drain did not
    ///      fulfill that exact day's word after a partial STAGE drain. The word is the box's frozen seed.
    function _injectRngWordByDay(uint32 day, uint256 word) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(RNG_WORD_BY_DAY_SLOT)));
        vm.store(address(game), slot, bytes32(word | 1));
    }

    /// @dev The simulated day index the next advance stamps with — read in-context via the game's view
    ///      (`currentDayView()` == `_simulatedDayIndexAt(block.timestamp)`, the exact `processDay` the STAGE
    ///      stamps with, AdvanceModule:169). Used to align the warp onto a settle boundary.
    function _simulatedDayIndex() internal view returns (uint32) {
        return game.currentDayView();
    }

    /// @dev Minimal uint -> decimal string for makeAddr label uniqueness.
    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
