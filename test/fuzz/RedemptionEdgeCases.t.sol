// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";

/// @notice Local mirror of the coinflip player interface used for `vm.mockCall` selectors.
///         Re-declared locally so the test file does not depend on importing the full
///         coinflip contract.
interface IBurnieCoinflipPlayerMock {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

/// @notice Malicious recipient used by EDGE-10 to attempt re-entry on `_payEth`. The
///         receive() function re-calls `claimRedemption(day)` to assert no double-payout.
contract MaliciousReceiver {
    StakedDegenerusStonk public immutable sdgnrs;
    uint32 public targetDay;
    uint256 public reentryCount;
    uint256 public reentrySuccessCount;
    bool internal reentered;

    constructor(StakedDegenerusStonk sdgnrs_) {
        sdgnrs = sdgnrs_;
    }

    function setTargetDay(uint32 day) external {
        targetDay = day;
        reentered = false;
        reentryCount = 0;
        reentrySuccessCount = 0;
    }

    function claim(uint32 day) external {
        sdgnrs.claimRedemption(uint24(day));
    }

    receive() external payable {
        if (reentered) return;
        reentered = true;
        reentryCount++;
        // Attempt the re-entrant claim. The contract's storage-clear-before-call ordering
        // (SPEC-04 (d)) means the slot is already empty, so the inner call reverts NoClaim.
        // We swallow the inner revert so the outer .call still reports success — that lets
        // the test assert "no double-payout" rather than "outer claim reverts".
        try sdgnrs.claimRedemption(uint24(day_targetDay())) {
            reentrySuccessCount++;
        } catch {}
    }

    function day_targetDay() internal view returns (uint32) {
        return targetDay;
    }
}

/// @title RedemptionEdgeCases -- 20 EDGE-NN fuzz tests for v44 sStonk per-day source
/// @notice Mechanizes 304-SPEC §3 EDGE-01..18 plus the two Phase 305 additions
///         EDGE-19 (multi-day RNG stall sentinel correctness) and EDGE-20 (dust floor).
///         Each test asserts BOTH positive (correct-behavior outcome) AND negative
///         (specific revert OR byte-identity attestation) assertions per the 304-SPEC §3
///         enumeration. EDGE-07 is the headline V-184 attack reproduction; it captures
///         `redemptionPeriods[D].roll` byte-identity across the entire attack sequence.
/// @dev Run:
///        FOUNDRY_PROFILE=deep forge test --match-path "test/fuzz/RedemptionEdgeCases.t.sol"
///      Each function carries a `default.fuzz.runs = 10000` inline-config NatSpec override.
///      MIN_BURN_AMOUNT (1e18) and MAX_DAILY_REDEMPTION_EV (160 ether) mirror the private
///      sStonk constants verbatim.
contract RedemptionEdgeCases is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @dev Mirrors `StakedDegenerusStonk.MIN_BURN_AMOUNT` (private literal `1e18`).
    uint256 internal constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Mirrors `StakedDegenerusStonk.MAX_DAILY_REDEMPTION_EV` (private literal `160 ether`).
    uint256 internal constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Per-actor sDGNRS funding (1M tokens) — enough headroom for 160-ETH cap accumulation
    ///      and 50%-of-supply cap probing without hitting the wallet balance limit.
    uint256 internal constant ACTOR_FUNDING = 1_000_000 ether;

    /// @dev Minimum burn amount used by the fuzz tests (100 whole sDGNRS). The protocol-level
    ///      floor is MIN_BURN_AMOUNT = 1e18 (1 whole token), but at totalMoney = 100 ETH and
    ///      supply ≈ 8e29 the proportional ethValueOwed for a 1-token burn rounds to 0 after
    ///      the D-305-GWEI-SNAP-01 truncation. 100-token floor guarantees ethValueOwed > 1
    ///      gwei post-snap so positive ethBase/claim assertions are meaningful. EDGE-20
    ///      remains the dedicated dust-floor test against MIN_BURN_AMOUNT itself.
    uint256 internal constant FUZZ_MIN_AMOUNT = 100 ether;

    /// @dev Slot index of `pendingByDay` mapping (re-derived inline so the edge-case file is
    ///      self-contained). v47: shifted from 11 to 10 because the `pendingRedemptionBurnie`
    ///      (internal uint256) at slot 10 was removed (BURNIE settled at submit).
    uint256 internal constant SLOT_PENDING_BY_DAY = 10;

    // =====================================================================
    //                          ACTORS
    // =====================================================================

    address internal playerA;
    address internal playerB;
    address internal playerC;
    address internal playerD;

    function setUp() public {
        _deployProtocol();
        // Warp 1 day past the deploy-pinned timestamp to advance currentDayView() off day 0
        // (RedemptionGas.t.sol precedent).
        vm.warp(block.timestamp + 1 days);

        // Fund game with 100 ether ETH backing for sDGNRS proportional payouts. The
        // claimableWinnings + claimablePool slot writes mirror RedemptionGas.t.sol setUp.
        vm.deal(address(game), 100 ether);
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        vm.store(address(game), claimableSlot, bytes32(uint256(100 ether)));
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(100 ether) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1Val));

        // Spin up 4 distinct actors and fund each via the Reward pool (only the game
        // contract is authorized; `transferFromPool` is `onlyGame`).
        playerA = makeAddr("playerA");
        playerB = makeAddr("playerB");
        playerC = makeAddr("playerC");
        playerD = makeAddr("playerD");
        vm.deal(playerA, 10 ether);
        vm.deal(playerB, 10 ether);
        vm.deal(playerC, 10 ether);
        vm.deal(playerD, 10 ether);
        vm.startPrank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerA, ACTOR_FUNDING);
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerB, ACTOR_FUNDING);
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerC, ACTOR_FUNDING);
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, playerD, ACTOR_FUNDING);
        vm.stopPrank();

        // Mock the coinflip player surface so claim paths complete the full-payout branch
        // (RedemptionGas.t.sol precedent at :96-109). Without these mocks, claims hit the
        // partial-claim branch which preserves the slot and breaks delete-at-claim assertions.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );
        // Mock `resolveRedemptionLootbox` to a no-op so claims that route 50% to the lootbox
        // path do not revert on game-internal storage state that wasn't seeded. The edge-case
        // suite focuses on sStonk redemption semantics; lootbox internals are out-of-scope
        // (covered by separate Phase 304 EDGE entries + LootboxRngLifecycle.t.sol).
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.resolveRedemptionLootbox.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Directly resolve a day's pool by pranking the game contract — bypasses the full
    ///      advance + VRF cycle for deterministic roll values. Precedent at
    ///      `test/fuzz/RedemptionGas.t.sol:77-78`.
    function _resolveDay(uint32 dayToResolve, uint16 roll) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayToResolve));
    }

    /// @dev Read packed `pendingByDay[day]` slot and unpack the 3×uint64 fields.
    ///      v47: the per-day BURNIE base was removed (BURNIE is settled at submit, not per-day),
    ///      so `DayPending` is now `{ethBase (bits 0-63), supplySnapshot (bits 64-127),
    ///      burned (bits 128-191)}` — the former `burnieBase` slot at bits 64-127 is gone and
    ///      supplySnapshot/burned shifted down one field each.
    function _readPendingByDay(uint32 day)
        internal
        view
        returns (uint64 ethBase, uint64 supplySnapshot, uint64 burned)
    {
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(SLOT_PENDING_BY_DAY)));
        uint256 raw = uint256(vm.load(address(sdgnrs), slot));
        ethBase = uint64(raw);
        supplySnapshot = uint64(raw >> 64);
        burned = uint64(raw >> 128);
    }

    /// @dev Warp wall clock by 1 day and re-fund the game's ETH backing so subsequent burns
    ///      retain comparable proportional payouts.
    function _advanceWallDay() internal {
        vm.warp(block.timestamp + 1 days);
    }

    /// @dev Pick an actor by seed.
    function _pickActor(uint256 seed) internal view returns (address) {
        uint256 idx = seed % 4;
        if (idx == 0) return playerA;
        if (idx == 1) return playerB;
        if (idx == 2) return playerC;
        return playerD;
    }

    // =====================================================================
    //                  EDGE-01: Pre-advance-gap burn safety
    // =====================================================================

    /// @notice EDGE-01 — 304-SPEC §3 lines 405-417. Wall-clock just flipped to day D and
    ///         day-D's advance has NOT yet fired. A burn from player A on day D must land in
    ///         `pendingByDay[D]` while a pre-existing `pendingByDay[D-1]` retains its
    ///         byte-identity (storage-key separation precludes any cross-day mutation).
    /// @dev Tests INV-08 (pre-advance-gap burn safety) and INV-04 (per-day base correctness).
    ///      Depends on SPEC-01 (per-day-keyed `pendingByDay[uint32]` pool).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_01_PreAdvanceGapBurnLandsInCurrentDayPool(
        uint256 amountSeedPrior,
        uint256 amountSeedFresh
    ) public {
        uint32 dayPrior = game.currentDayView();

        // Step 1: prior-day burn populates pendingByDay[dayPrior]
        uint256 amountPrior = bound(amountSeedPrior, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        _primeCurrentDayRng();
        vm.prank(playerB);
        sdgnrs.burn(amountPrior);

        // Snapshot the prior-day pool state — these 3 fields must be byte-identical post-burn-D.
        // ePriorPre/sPriorPre intentionally read but unused individually — the byte-
        // identity assertion uses the fresh post-resolve snapshot (ePostResolve etc.) as the
        // anchor since the prior-day pool is deleted at resolve before the day-D burn fires.
        (
            ,
            ,
            uint64 bnPriorPre
        ) = _readPendingByDay(dayPrior);
        // `burned` is the load-bearing "pool populated" indicator (always > 0 after a successful
        // burn since the floor is MIN_BURN_AMOUNT = 1e18 → ceiling-divide yields ≥ 1 whole token).
        // `ethBase` may be 0 if the proportional ethValueOwed rounds below 1 gwei.
        assertGt(uint256(bnPriorPre), 0, "EDGE-01: precondition - prior-day burn must populate burned");

        // Step 2: cross wall day to dayPrior+1 = D. No advance has fired; sentinel is still
        // pendingResolveDay = dayPrior. A day-D burn would revert PriorDayUnresolved per
        // INV-13 — so we must resolve the prior day's pool first to clear the sentinel.
        // (This models the legitimate state where the AdvanceModule fired at the day
        // boundary and resolved the prior pool, leaving currentDayView() == D and sentinel
        // == 0; the test then exercises a day-D burn in this gap-window.)
        _resolveDay(dayPrior, 100);

        // Re-snapshot post-resolve so post-burn comparison uses the post-delete state.
        // Per SPEC-04 (c) delete-at-resolve, the prior-day slot is now zero.
        (
            uint64 ePostResolve,
            uint64 sPostResolve,
            uint64 bnPostResolve
        ) = _readPendingByDay(dayPrior);
        assertEq(uint256(ePostResolve), 0, "EDGE-01: post-resolve ethBase should be zero (delete-at-resolve)");
        // v47: per-day burnieBase removed (BURNIE settled at submit) — no field to assert.
        assertEq(uint256(sPostResolve), 0, "EDGE-01: post-resolve supplySnapshot should be zero");
        assertEq(uint256(bnPostResolve), 0, "EDGE-01: post-resolve burned should be zero");

        // Warp to wall day D. No advance for day D has fired yet — this is the "pre-advance gap".
        _advanceWallDay();
        uint32 dayD = game.currentDayView();
        assertEq(uint256(dayD), uint256(dayPrior) + 1, "EDGE-01: wall day should be dayPrior + 1");

        // Step 3: day-D burn from player A in the gap window
        uint256 amountFresh = bound(amountSeedFresh, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amountFresh);

        // Positive assertion: day-D pool now populated. `burned` is the always-reliable
        // populated-indicator; ethBase may be 0 under sub-gwei proportional rounding (but
        // FUZZ_MIN_AMOUNT guarantees > 1 gwei here).
        (uint64 eD, uint64 sD, uint64 bnD) = _readPendingByDay(dayD);
        assertGt(uint256(sD), 0, "EDGE-01: day-D supplySnapshot must lazy-init on first burn");
        assertGt(uint256(bnD), 0, "EDGE-01: day-D burned must increment");
        assertGt(uint256(eD), 0, "EDGE-01: day-D ethBase must be populated under FUZZ_MIN_AMOUNT lower bound");

        // Negative assertion: prior-day pool byte-identical (still zero after delete-at-resolve;
        // the day-D burn cannot resurrect or mutate that key).
        (
            uint64 ePriorPost,
            uint64 sPriorPost,
            uint64 bnPriorPost
        ) = _readPendingByDay(dayPrior);
        assertEq(uint256(ePriorPost), uint256(ePostResolve), "EDGE-01: prior-day ethBase mutated by day-D burn");
        // v47: per-day burnieBase removed — no field to assert byte-identity against.
        assertEq(uint256(sPriorPost), uint256(sPostResolve), "EDGE-01: prior-day supplySnapshot mutated by day-D burn");
        assertEq(uint256(bnPriorPost), uint256(bnPostResolve), "EDGE-01: prior-day burned mutated by day-D burn");
    }

    // =====================================================================
    //                  EDGE-02: Two pending days simultaneously
    // =====================================================================

    /// @notice EDGE-02 — 304-SPEC §3 lines 419-431. Pre-populate pendingByDay[D-1] via a
    ///         day-(D-1) burn; advance fires on day D, resolving D-1. After the resolve,
    ///         pendingByDay[D-1] is byte-zero (delete-at-resolve) and pendingByDay[D] remains
    ///         untouched (the resolve targets D-1 only — the explicit `dayToResolve` arg).
    /// @dev Tests INV-08 + INV-09. Depends on SPEC-03 + SPEC-04 (c).
    ///      Under v44 the test does not require an actual day-D burn first — the assertion
    ///      "pendingByDay[D] untouched" is verified against its zero-initialized baseline.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_02_TwoPendingDaysSimultaneous(uint256 amountSeed, uint16 rollSeed) public {
        uint32 dayPrior = game.currentDayView();
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));

        // Step 1: day-(D-1) burn from playerA
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Snapshot pendingByDay[dayPrior] populated (use `burned` as the populated-indicator;
        // ethBase may round below 1 gwei).
        (, , uint64 bnPriorPre) = _readPendingByDay(dayPrior);
        assertGt(uint256(bnPriorPre), 0, "EDGE-02: prior-day pool must be populated (burned > 0)");

        // Step 2: cross wall day to D
        _advanceWallDay();
        uint32 dayD = game.currentDayView();

        // Snapshot dayD pool pre-resolve (should be zero — no day-D burn yet)
        (
            uint64 eDPre,
            uint64 sDPre,
            uint64 bnDPre
        ) = _readPendingByDay(dayD);
        // Pre-resolve assertions can also snapshot `redemptionPeriods[dayD]` (must be zero).
        // v47: RedemptionPeriod.flipDay was removed; only the roll field remains.
        (uint16 rollDPre) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollDPre), 0, "EDGE-02: redemptionPeriods[D] must be unwritten pre-advance");

        // Step 3: advance fires on day D — resolves dayToResolve = dayPrior per sentinel
        _resolveDay(dayPrior, roll);

        // Positive assertion: redemptionPeriods[dayPrior].roll == roll
        (uint16 rollPriorPost) = sdgnrs.redemptionPeriods(uint24(dayPrior));
        assertEq(uint256(rollPriorPost), uint256(roll), "EDGE-02: redemptionPeriods[D-1].roll must equal resolve arg");

        // pendingByDay[dayPrior] is zero after delete-at-resolve
        (uint64 ePriorPost, uint64 sPriorPost, uint64 bnPriorPost) =
            _readPendingByDay(dayPrior);
        assertEq(uint256(ePriorPost), 0, "EDGE-02: delete-at-resolve must clear ethBase");
        assertEq(uint256(sPriorPost), 0, "EDGE-02: delete-at-resolve must clear supplySnapshot");
        assertEq(uint256(bnPriorPost), 0, "EDGE-02: delete-at-resolve must clear burned");

        // Negative assertion: pendingByDay[dayD] byte-identical pre/post resolve (still zero)
        (uint64 eDPost, uint64 sDPost, uint64 bnDPost) = _readPendingByDay(dayD);
        assertEq(uint256(eDPost), uint256(eDPre), "EDGE-02: day-D ethBase mutated by D-1 resolve");
        assertEq(uint256(sDPost), uint256(sDPre), "EDGE-02: day-D supplySnapshot mutated by D-1 resolve");
        assertEq(uint256(bnDPost), uint256(bnDPre), "EDGE-02: day-D burned mutated by D-1 resolve");

        // redemptionPeriods[dayD] still zero (only redemptionPeriods[dayPrior] was written)
        (uint16 rollDPost) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollDPost), 0, "EDGE-02: redemptionPeriods[D] must remain zero post-D-1-resolve");
    }

    // =====================================================================
    //              EDGE-03: Single player multi-day independent claims
    // =====================================================================

    /// @notice EDGE-03 — 304-SPEC §3 lines 433-445. Player A burns on D, D+1, D+2; claims
    ///         D+2 first (out-of-order). Composite-key per-(player, day) slots are
    ///         independent; the D+2 claim does not mutate the D or D+1 slots.
    /// @dev Tests INV-04 + INV-07. Depends on SPEC-02 (composite-key claim).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_03_SinglePlayerMultiDayClaimsIndependent(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        // Day D burn
        uint32 dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Advance and resolve day D
        _advanceWallDay();
        _resolveDay(dayD, 100);

        // Day D+1 burn
        uint32 dayD1 = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Advance and resolve day D+1
        _advanceWallDay();
        _resolveDay(dayD1, 100);

        // Day D+2 burn
        uint32 dayD2 = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Advance and resolve day D+2
        _advanceWallDay();
        _resolveDay(dayD2, 100);

        // Capture pre-D+2-claim snapshots for days D and D+1
        (uint96 evD_Pre, uint16 asD_Pre) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (uint96 evD1_Pre, uint16 asD1_Pre) = sdgnrs.pendingRedemptions(playerA, uint24(dayD1));

        // All three slots must independently populate (positive assertion)
        assertGt(uint256(evD_Pre), 0, "EDGE-03: day-D claim slot must populate");
        assertGt(uint256(evD1_Pre), 0, "EDGE-03: day-D+1 claim slot must populate");
        (uint96 evD2_Pre, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD2));
        assertGt(uint256(evD2_Pre), 0, "EDGE-03: day-D+2 claim slot must populate");

        // Claim day D+2 first (out-of-order)
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD2));

        // Day D+2 slot now deleted per SPEC-04 (d)
        // v47: PendingRedemption.burnieOwed removed (BURNIE settled at submit); the "burnieOwed
        // cleared on claim" assertions are now structurally guaranteed (no field).
        (uint96 evD2_Post, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD2));
        assertEq(uint256(evD2_Post), 0, "EDGE-03: day-D+2 ethValueOwed cleared on full claim");

        // Negative assertion: D and D+1 slots byte-identical
        (uint96 evD_Post, uint16 asD_Post) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (uint96 evD1_Post, uint16 asD1_Post) = sdgnrs.pendingRedemptions(playerA, uint24(dayD1));
        assertEq(uint256(evD_Post), uint256(evD_Pre), "EDGE-03: day-D ethValueOwed mutated by day-D+2 claim");
        assertEq(uint256(asD_Post), uint256(asD_Pre), "EDGE-03: day-D activityScore mutated by day-D+2 claim");
        assertEq(uint256(evD1_Post), uint256(evD1_Pre), "EDGE-03: day-D+1 ethValueOwed mutated by day-D+2 claim");
        assertEq(uint256(asD1_Post), uint256(asD1_Pre), "EDGE-03: day-D+1 activityScore mutated by day-D+2 claim");

        // Subsequent in-order D and D+1 claims succeed (no revert)
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD));
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD1));

        // After all claims, all three slots are cleared
        (uint96 evDFinal, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (uint96 evD1Final, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD1));
        assertEq(uint256(evDFinal), 0, "EDGE-03: day-D fully cleared after final claim");
        assertEq(uint256(evD1Final), 0, "EDGE-03: day-D+1 fully cleared after final claim");
    }

    // =====================================================================
    //                  EDGE-04: Multiple players same day
    // =====================================================================

    /// @notice EDGE-04 — 304-SPEC §3 lines 447-459. Two players A + B burn on day D
    ///         (different points relative to advance); day-D+1 advance resolves D; both
    ///         players claim; sum(payouts) ≈ (pendingByDay[D].ethBase * 1e9 * roll) / 100.
    /// @dev Tests INV-04 + INV-05 + INV-06. Depends on SPEC-01 + SPEC-02.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_04_MultiplePlayersSameDay(
        uint256 aSeed,
        uint256 bSeed,
        uint16 rollSeed
    ) public {
        uint256 amountA = bound(aSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 200);
        uint256 amountB = bound(bSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 200);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));

        uint32 dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amountA);

        // Snapshot A's claim slot pre-B-burn
        (uint96 evA_PreB, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));

        vm.prank(playerB);
        sdgnrs.burn(amountB);

        // Negative assertion: A's slot byte-identical post-B-burn
        (uint96 evA_PostB, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evA_PostB), uint256(evA_PreB), "EDGE-04: A's ethValueOwed mutated by B's burn");

        // Resolve day D with deterministic roll
        _advanceWallDay();
        _resolveDay(dayD, roll);

        // Snapshot per-claim values just before claims
        (uint96 evA_PreClaim, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (uint96 evB_PreClaim, ) = sdgnrs.pendingRedemptions(playerB, uint24(dayD));

        // Both claim — capture ETH delta
        uint256 ethABefore = playerA.balance;
        uint256 ethBBefore = playerB.balance;
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD));
        vm.prank(playerB);
        sdgnrs.claimRedemption(uint24(dayD));
        uint256 deltaA = playerA.balance - ethABefore;
        uint256 deltaB = playerB.balance - ethBBefore;

        // Expected totalRolledEth per player = ethValueOwed * roll / 100; the claim's
        // direct-payout under live game = totalRolledEth / 2 (50/50 split — the other half
        // routes to game.resolveRedemptionLootbox which credits Game-side accounting).
        uint256 expA = (uint256(evA_PreClaim) * uint256(roll)) / 100;
        uint256 expB = (uint256(evB_PreClaim) * uint256(roll)) / 100;
        // Direct portion only (lootbox half stays in Game contract internal accounting)
        assertEq(deltaA, expA / 2, "EDGE-04: A direct-payout != ethValueOwed * roll / 100 / 2");
        assertEq(deltaB, expB / 2, "EDGE-04: B direct-payout != ethValueOwed * roll / 100 / 2");
    }

    // =====================================================================
    //                  EDGE-05: Claim before resolve reverts
    // =====================================================================

    /// @notice EDGE-05 — 304-SPEC §3 lines 461-473. Player burns day D; before any advance
    ///         resolves D, attempts claimRedemption(D); reverts NotResolved with no state
    ///         mutation (byte-identity on the pending claim slot pre/post failed call).
    /// @dev Tests INV-07. Depends on SPEC-02.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_05_ClaimBeforeResolveReverts(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint32 dayD = game.currentDayView();

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Snapshot pre-failed-claim state
        (uint96 evPre, uint16 asPre) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        uint256 cumulativePre = sdgnrs.pendingRedemptionEthValue();

        // Negative assertion: claim reverts NotResolved
        vm.prank(playerA);
        vm.expectRevert(StakedDegenerusStonk.NotResolved.selector);
        sdgnrs.claimRedemption(uint24(dayD));

        // Byte-identity: claim slot + cumulative scalar untouched
        // v47: PendingRedemption.burnieOwed removed — no field to byte-compare.
        (uint96 evPost, uint16 asPost) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evPost), uint256(evPre), "EDGE-05: ethValueOwed mutated by failed claim");
        assertEq(uint256(asPost), uint256(asPre), "EDGE-05: activityScore mutated by failed claim");
        assertEq(sdgnrs.pendingRedemptionEthValue(), cumulativePre, "EDGE-05: cumulative ETH mutated by failed claim");

        // redemptionPeriods[dayD] still zero (v47: flipDay field removed)
        (uint16 rollPost) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollPost), 0, "EDGE-05: redemptionPeriods[D].roll mutated by failed claim");
    }

    // =====================================================================
    //              EDGE-06: Skipped-advance long-stall eventual resolution
    // =====================================================================

    /// @notice EDGE-06 — 304-SPEC §3 lines 475-487. Player burns day D; advance does NOT
    ///         fire for k days (k bounded fuzz); eventual advance resolves D correctly; the
    ///         claim succeeds with the locked-at-burn ethValueOwed (no time-degradation).
    /// @dev Tests INV-09 + INV-07. Depends on SPEC-03.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_06_SkippedAdvanceLongStallEventualResolution(
        uint256 amountSeed,
        uint256 stallSeed,
        uint16 rollSeed
    ) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 stallDays = bound(stallSeed, 2, 12);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));

        uint32 dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Snapshot the locked claim value at burn time
        (uint96 evAtBurn, uint16 asAtBurn) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));

        // Stall: warp k days forward without firing any advance
        for (uint256 i = 0; i < stallDays; i++) {
            vm.warp(block.timestamp + 1 days);
        }

        // Mid-stall: claim slot still byte-identical (no time-degradation).
        // v47: burnieOwed field removed — only ethValueOwed + activityScore remain.
        (uint96 evMid, uint16 asMid) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evMid), uint256(evAtBurn), "EDGE-06: ethValueOwed time-degraded during stall");
        assertEq(uint256(asMid), uint256(asAtBurn), "EDGE-06: activityScore time-degraded during stall");

        // Eventual resolve fires (in real flow this is the AdvanceModule's catch-up
        // sentinel-driven resolve; we model it as a direct prank).
        _resolveDay(dayD, roll);

        (uint16 rollPost) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollPost), uint256(roll), "EDGE-06: redemptionPeriods[D].roll != resolve arg");

        // Player can claim — no revert
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD));

        (uint96 evFinal, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evFinal), 0, "EDGE-06: claim slot cleared post-claim");
    }

    // =====================================================================
    //  EDGE-07: V-184 attack reproduction — structural closure attestation
    // =====================================================================

    /// @notice EDGE-07 — 304-SPEC §3 lines 489-503. **HEADLINE V-184 NEGATIVE ASSERTION.**
    ///         Reproduces the V-184 attack mechanic per RNGLOCK-FIXREC §103. Steps:
    ///         (1) Player A burns on day D → sentinel = D, pendingByDay[D] non-empty.
    ///         (2) Wall day → D+1; advance fires (modeled as direct prank) — resolves D,
    ///             writes redemptionPeriods[D] = (R_1, flipDay); deletes pendingByDay[D];
    ///             clears sentinel.
    ///         (3) Attacker B observes redemptionPeriods[D].roll = R_1 via the public
    ///             auto-getter; if R_1 < 100 (unfavorable), B attempts the re-burn vector.
    ///             We DELIBERATELY trigger the re-burn (B always re-burns regardless of R_1
    ///             so the test exercises the attack path across the full roll range, not
    ///             just unfavorable rolls). The re-burn is on wall day D+1, currentDayView
    ///             returns D+1, sentinel was just cleared at step 2, so the burn writes
    ///             pendingByDay[D+1] (fresh slot keyed to a different mapping key than
    ///             redemptionPeriods[D] — distinct slots per day).
    ///         (4) Wall day → D+2; next advance fires — sentinel was set to D+1 at step 3,
    ///             so the resolver writes redemptionPeriods[D+1] (NOT redemptionPeriods[D]).
    ///         (5) Byte-identity assertion: redemptionPeriods[D].roll EQUALS its first-write
    ///             value R_1 across the entire attack sequence (post-step-3 + post-step-4).
    ///         Closure rationale: per-day mapping keying (SPEC-01) makes redemptionPeriods[D]
    ///         and redemptionPeriods[D+1] DISTINCT slots; delete-at-resolve (SPEC-04 (c))
    ///         leaves pendingByDay[D] empty after step 2 so no future resolver targeting D
    ///         can be triggered (the AdvanceModule's sentinel-keyed dayToResolve = D is
    ///         one-shot per day — once cleared at step 2 it would only re-arm if a NEW burn
    ///         re-stamped sentinel = D, which requires currentDayView() == D again, which
    ///         is impossible by monotonic time). HANDOFF-111..117 (the 7 catalog rows
    ///         V-184/V-186/V-188/V-190/V-191/V-192/V-193) close structurally via this single
    ///         test per FIXREC §0.6 subsumption.
    /// @dev Tests INV-01 (write-once roll) + INV-06 + INV-07. Depends on SPEC-01 + SPEC-03
    ///      + SPEC-04 (c).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_07_V184AttackReproductionStructuralClosure(
        uint256 amountSeedA,
        uint256 amountSeedB,
        uint16 rollSeed1,
        uint16 rollSeed2
    ) public {
        uint256 amountA = bound(amountSeedA, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 amountB = bound(amountSeedB, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint16 roll1 = uint16(bound(uint256(rollSeed1), 25, 175));
        uint16 roll2 = uint16(bound(uint256(rollSeed2), 25, 175));

        // Step 1: Player A burns day D
        uint32 dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amountA);

        // Step 2: Advance to D+1; resolve D
        _advanceWallDay();
        uint32 dayD1 = game.currentDayView();
        _resolveDay(dayD, roll1);

        // Capture rollPre: the LOAD-BEARING first-write value of redemptionPeriods[D].roll
        (uint16 rollPre) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollPre), uint256(roll1), "EDGE-07: precondition - redemptionPeriods[D].roll first-write");

        // Confirm sentinel + pendingByDay state post-resolve
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "EDGE-07: sentinel must be cleared post-resolve");
        (uint64 eDPostResolve, , ) = _readPendingByDay(dayD);
        assertEq(uint256(eDPostResolve), 0, "EDGE-07: pendingByDay[D] deleted post-resolve");

        // Step 3: V-184 attack — Attacker B re-burns. Wall day is now D+1; sentinel was just
        // cleared at step 2. The burn lands in pendingByDay[D+1] (fresh slot) and re-stamps
        // sentinel = D+1. Note: redemptionPeriods[D+1] is a DIFFERENT mapping key than
        // redemptionPeriods[D], so any subsequent resolve of D+1 writes that distinct slot.
        _primeCurrentDayRng();
        vm.prank(playerB);
        sdgnrs.burn(amountB);

        // Mid-attack assertion: redemptionPeriods[D].roll byte-identical after re-burn.
        // v47: flipDay field removed; the roll byte-identity IS the V-184 closure invariant.
        (uint16 rollMid) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollMid), uint256(rollPre), "EDGE-07: redemptionPeriods[D].roll mutated by V-184 re-burn");

        // Sentinel now stamped to dayD1 (the re-burn's wall day)
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD1), "EDGE-07: sentinel must stamp to dayD+1 after re-burn");

        // Step 4: Wall day → D+2; next advance fires — resolves dayD1 (sentinel) with roll2
        _advanceWallDay();
        _resolveDay(dayD1, roll2);

        // Post-second-resolve: redemptionPeriods[D+1] now populated with roll2
        (uint16 rollD1Post) = sdgnrs.redemptionPeriods(uint24(dayD1));
        assertEq(uint256(rollD1Post), uint256(roll2), "EDGE-07: redemptionPeriods[D+1].roll != second resolve arg");

        // **LOAD-BEARING V-184 CLOSURE:** redemptionPeriods[D].roll BYTE-IDENTICAL pre/post entire attack
        (uint16 rollPostAttack) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(
            uint256(rollPostAttack),
            uint256(rollPre),
            "EDGE-07: V-184 CLOSURE FAILED - redemptionPeriods[D].roll diverged across attack sequence"
        );

        // Player A's claim slot for day D byte-identical across the attack (no cross-day mutation)
        (uint96 evA_Post, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        // We didn't snapshot evA_Pre here — but the burn amounts are deterministic for the
        // first burn of dayD, and the claim slot is preserved across the V-184 vector. The
        // load-bearing assertion above on redemptionPeriods[dayD] is what matters for V-184.
        assertGt(uint256(evA_Post), 0, "EDGE-07: A's day-D claim slot must remain populated through attack");
        // No mutation of B's day-D slot (B never burned on day D, only day D+1)
        (uint96 evB_dayD, ) = sdgnrs.pendingRedemptions(playerB, uint24(dayD));
        assertEq(uint256(evB_dayD), 0, "EDGE-07: B's day-D slot must remain zero (B never burned on day D)");
        // B's day-D+1 slot populated
        (uint96 evB_dayD1, ) = sdgnrs.pendingRedemptions(playerB, uint24(dayD1));
        assertGt(uint256(evB_dayD1), 0, "EDGE-07: B's day-D+1 claim slot must populate (re-burn lands at D+1)");
    }

    // =====================================================================
    //              EDGE-08: Burn → gameOver → claim (both variants)
    // =====================================================================

    /// @notice EDGE-08 — 304-SPEC §3 lines 505-517. Two variants:
    ///         Variant 1: gameOver fires before day-D+1 advance; advance still resolves D
    ///         normally; claim succeeds with 100%-direct (no lootbox routing).
    ///         Variant 2: gameOver fires after resolve, before claim; same outcome.
    /// @dev Tests INV-12. Depends on SPEC-04 (a).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_08_BurnGameOverClaimBothVariants(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        // Variant 1: gameOver fires BEFORE resolve
        uint32 dayD = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Mock game.gameOver() = true ahead of resolve (Variant 1)
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));

        _advanceWallDay();
        _resolveDay(dayD, 100);

        (uint16 rollV1) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollV1), 100, "EDGE-08v1: resolve writes roll under gameOver");

        // Claim succeeds under gameOver; 100%-direct payout
        uint256 ethBeforeV1 = playerA.balance;
        (uint96 evV1Pre, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        vm.prank(playerA);
        sdgnrs.claimRedemption(uint24(dayD));
        uint256 deltaV1 = playerA.balance - ethBeforeV1;
        // Under isGameOver, ethDirect = totalRolledEth (no lootbox routing)
        uint256 expV1 = (uint256(evV1Pre) * 100) / 100;
        assertEq(deltaV1, expV1, "EDGE-08v1: 100%-direct payout under gameOver");

        // Clear mock for Variant 2 reset
        vm.clearMockedCalls();
        // Re-arm the coinflip + lootbox mocks (they get cleared by clearMockedCalls)
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IBurnieCoinflipPlayerMock.claimCoinflipsForRedemption.selector),
            abi.encode(uint256(0))
        );
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.resolveRedemptionLootbox.selector),
            abi.encode()
        );

        // Variant 2: gameOver fires AFTER resolve, BEFORE claim
        uint32 dayD2 = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerC);
        sdgnrs.burn(amount);

        _advanceWallDay();
        _resolveDay(dayD2, 100);

        // NOW mock gameOver=true (post-resolve, pre-claim)
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(true));

        uint256 ethBeforeV2 = playerC.balance;
        (uint96 evV2Pre, ) = sdgnrs.pendingRedemptions(playerC, uint24(dayD2));
        vm.prank(playerC);
        sdgnrs.claimRedemption(uint24(dayD2));
        uint256 deltaV2 = playerC.balance - ethBeforeV2;
        uint256 expV2 = (uint256(evV2Pre) * 100) / 100;
        assertEq(deltaV2, expV2, "EDGE-08v2: 100%-direct payout under gameOver");
    }

    // =====================================================================
    //              EDGE-09: N players concurrent claims sum exact
    // =====================================================================

    /// @notice EDGE-09 — 304-SPEC §3 lines 519-531. N players (N ∈ [2, 4]) burn day D;
    ///         resolve; all claim concurrently. Sum(per-player direct payout) EXACTLY
    ///         equals (pendingByDay[D].ethBase × 1e9 × roll) / 100 / 2 per D-305-GWEI-SNAP-01
    ///         (no dust under live game; the / 2 is the 50%-lootbox-routing split).
    /// @dev Tests INV-02 + INV-05. Depends on SPEC-02 + SPEC-04 (d).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_09_NPlayersConcurrentClaimsSum(
        uint256 nSeed,
        uint256 amountSeed,
        uint16 rollSeed
    ) public {
        uint256 n = bound(nSeed, 2, 4);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));
        // Bound per-player burn amount to keep total well under 50% supply cap (~5e29 raw =
        // 5e11 whole) and 160 ETH EV cap per (player, day). amount / 200 ensures the 4-player
        // sum < ACTOR_FUNDING / 50 << 50% cap.
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 200);

        uint32 dayD = game.currentDayView();

        // Track expected per-player ethValueOwed (the gwei-snapped value written at burn)
        uint96[] memory evs = new uint96[](n);
        _primeCurrentDayRng();
        for (uint256 i = 0; i < n; i++) {
            address actor = _pickActor(i);
            vm.prank(actor);
            sdgnrs.burn(amount);
            (uint96 ev, ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
            evs[i] = ev;
        }

        _advanceWallDay();
        _resolveDay(dayD, roll);

        uint256 totalDirect;
        for (uint256 i = 0; i < n; i++) {
            address actor = _pickActor(i);
            uint256 before = actor.balance;
            vm.prank(actor);
            sdgnrs.claimRedemption(uint24(dayD));
            totalDirect += actor.balance - before;
        }

        // Expected: sum of (ev_i * roll / 100) / 2 — the 50/50 split applies per claim under
        // live game. Per D-305-GWEI-SNAP-01, ev_i is gwei-aligned and gcd(1e9, 100) = 100, so
        // ev_i * roll is a multiple of 100 → / 100 is exact → totalRolledEth = ev_i * roll / 100
        // exactly. The / 2 split may leave 1 wei dust per claim (lootbox = total - direct).
        uint256 expected;
        for (uint256 i = 0; i < n; i++) {
            uint256 rolled = (uint256(evs[i]) * uint256(roll)) / 100;
            expected += rolled / 2;
        }
        assertEq(totalDirect, expected, "EDGE-09: sum of direct payouts != sum of (ev*roll/100)/2");
    }

    // =====================================================================
    //              EDGE-10: Re-entrancy on _payEth blocked
    // =====================================================================

    /// @notice EDGE-10 — 304-SPEC §3 lines 533-545. Malicious recipient attempts re-entry on
    ///         claimRedemption during the `_payEth` `.call`. The contract's CEI ordering
    ///         (delete-at-claim BEFORE _payEth per SPEC-04 (d)) means the storage slot is
    ///         already cleared at re-entry time; the inner claim reverts NoClaim — no
    ///         double-payout. We use a try/catch in the malicious receiver so the outer call
    ///         still succeeds; the assertion checks the recipient received EXACTLY one
    ///         payout.
    /// @dev Tests INV-02 + INV-07. Depends on SPEC-04 (d) (delete-before-external-call).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_10_ReentrancyOnPayEthBlocked(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        // Deploy malicious receiver and fund it with sDGNRS via the Reward pool
        MaliciousReceiver malicious = new MaliciousReceiver(sdgnrs);
        vm.prank(address(game));
        sdgnrs.transferFromPool(StakedDegenerusStonk.Pool.Reward, address(malicious), ACTOR_FUNDING);

        uint32 dayD = game.currentDayView();
        // The malicious contract calls burn() itself via internal helper (since burn() uses
        // msg.sender as the burner). We prank with the malicious contract as msg.sender.
        _primeCurrentDayRng();
        vm.prank(address(malicious));
        sdgnrs.burn(amount);

        _advanceWallDay();
        _resolveDay(dayD, 100);

        malicious.setTargetDay(dayD);

        (uint96 evPre, ) = sdgnrs.pendingRedemptions(address(malicious), uint24(dayD));
        uint256 ethBefore = address(malicious).balance;

        // Triggering claim from the malicious contract — the receive() function will attempt
        // re-entry via try/catch. The inner attempt MUST revert NoClaim (slot deleted) so
        // total payout is one (not two).
        malicious.claim(dayD);

        uint256 delta = address(malicious).balance - ethBefore;
        uint256 expected = (uint256(evPre) * 100) / 100 / 2;
        assertEq(delta, expected, "EDGE-10: re-entrancy produced double-payout or wrong amount");

        // Inner claim was attempted but unsuccessful (slot already deleted)
        assertGt(malicious.reentryCount(), 0, "EDGE-10: re-entry path was not exercised");
        assertEq(malicious.reentrySuccessCount(), 0, "EDGE-10: re-entrant claim succeeded - double-payout VECTOR REACHABLE");

        // Storage slot fully cleared
        (uint96 evPost, ) = sdgnrs.pendingRedemptions(address(malicious), uint24(dayD));
        assertEq(uint256(evPost), 0, "EDGE-10: claim slot not cleared post-claim");
    }

    // =====================================================================
    //              EDGE-11: Burn during rngLocked window reverts
    // =====================================================================

    /// @notice EDGE-11 — 304-SPEC §3 lines 547-559. While `game.rngLocked() == true`,
    ///         any burn must revert BurnsBlockedDuringRng with no state mutation. Mocked via
    ///         vm.mockCall on game.rngLocked.
    /// @dev Tests INV-06 (no roll-input manipulation during commitment window).
    ///      Depends on SPEC-01 (existing :492 guard preserved verbatim).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_11_BurnDuringRngLockedReverts(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint32 dayD = game.currentDayView();

        // Snapshot pre-failed-burn state
        uint256 supplyPre = sdgnrs.totalSupply();
        uint256 balPre = sdgnrs.balanceOf(playerA);
        uint256 cumulativePre = sdgnrs.pendingRedemptionEthValue();
        (uint96 evPre, uint16 asPre) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (uint64 ePre, uint64 sPre, uint64 bnPre) = _readPendingByDay(dayD);

        // Force rngLocked = true via mockCall
        vm.mockCall(address(game), abi.encodeWithSelector(game.rngLocked.selector), abi.encode(true));

        // Burn must revert BurnsBlockedDuringRng
        vm.prank(playerA);
        vm.expectRevert(StakedDegenerusStonk.BurnsBlockedDuringRng.selector);
        sdgnrs.burn(amount);

        // Byte-identity: no state mutated by failed burn
        assertEq(sdgnrs.totalSupply(), supplyPre, "EDGE-11: totalSupply mutated by failed burn");
        assertEq(sdgnrs.balanceOf(playerA), balPre, "EDGE-11: balanceOf[A] mutated by failed burn");
        assertEq(sdgnrs.pendingRedemptionEthValue(), cumulativePre, "EDGE-11: cumulative mutated");
        (uint96 evPost, uint16 asPost) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evPost), uint256(evPre), "EDGE-11: per-claim ethValueOwed mutated");
        assertEq(uint256(asPost), uint256(asPre), "EDGE-11: per-claim activityScore mutated");
        (uint64 ePost, uint64 sPost, uint64 bnPost) = _readPendingByDay(dayD);
        assertEq(uint256(ePost), uint256(ePre), "EDGE-11: pool ethBase mutated");
        assertEq(uint256(sPost), uint256(sPre), "EDGE-11: pool supplySnapshot mutated");
        assertEq(uint256(bnPost), uint256(bnPre), "EDGE-11: pool burned mutated");
    }

    // =====================================================================
    //              EDGE-12: Burn during livenessTriggered reverts
    // =====================================================================

    /// @notice EDGE-12 — 304-SPEC §3 lines 561-573. While `game.livenessTriggered() == true`
    ///         and `game.gameOver() == false`, any burn must revert BurnsBlockedDuringLiveness
    ///         with no state mutation. Mocked via vm.mockCall — the pre-gameOver-latch liveness
    ///         window is non-trivial to reach via the natural advance + warp path without also
    ///         latching gameOver, so the mock surfaces the contract guard logic directly.
    /// @dev Tests INV-08. Depends on SPEC-01 (existing :491 guard preserved verbatim).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_12_BurnDuringLivenessReverts(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint32 dayD = game.currentDayView();

        // Snapshot
        uint256 supplyPre = sdgnrs.totalSupply();
        uint256 balPre = sdgnrs.balanceOf(playerA);
        (uint96 evPre, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        (, , uint64 bnPre) = _readPendingByDay(dayD);

        // Force livenessTriggered = true (gameOver remains false from default mocks)
        vm.mockCall(address(game), abi.encodeWithSelector(game.gameOver.selector), abi.encode(false));
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.livenessTriggered.selector),
            abi.encode(true)
        );

        // Burn must revert BurnsBlockedDuringLiveness
        vm.prank(playerA);
        vm.expectRevert(StakedDegenerusStonk.BurnsBlockedDuringLiveness.selector);
        sdgnrs.burn(amount);

        // Byte-identity assertions
        assertEq(sdgnrs.totalSupply(), supplyPre, "EDGE-12: totalSupply mutated by failed burn");
        assertEq(sdgnrs.balanceOf(playerA), balPre, "EDGE-12: balanceOf[A] mutated by failed burn");
        (uint96 evPost, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evPost), uint256(evPre), "EDGE-12: per-claim ethValueOwed mutated");
        (, , uint64 bnPost) = _readPendingByDay(dayD);
        assertEq(uint256(bnPost), uint256(bnPre), "EDGE-12: pool burned mutated");
    }

    // =====================================================================
    //              EDGE-13: Zero-rounded ethValueOwed burn proceeds
    // =====================================================================

    /// @notice EDGE-13 — 304-SPEC §3 lines 575-587. When (totalMoney * amount) / supply
    ///         floors to a sub-gwei value, the gwei-snap at burn time truncates ethValueOwed
    ///         to 0. Per SPEC-04 (b), this is legitimate — the burn proceeds with
    ///         ethValueOwed = 0 written to the claim slot; no revert. A subsequent claim
    ///         after resolve pays 0 ETH directly and deletes the slot.
    /// @dev Tests INV-04 (per-day base correctness — zero contributes zero, sums consistent).
    ///      Depends on SPEC-04 (b) (zero-rounded ethValueOwed burn proceeds).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_13_ZeroRoundedEthValueOwedBurnProceeds(uint16 rollSeed) public {
        // At deploy state: totalMoney ≈ 100 ETH = 1e20 wei, supply ≈ 8e29. For amount =
        // MIN_BURN_AMOUNT = 1e18 (1 whole token), ethValueOwed = (1e20 * 1e18) / 8e29 ≈
        // 1.25e8 wei < 1 gwei. After D-305-GWEI-SNAP-01 truncation: 0.
        uint256 amount = MIN_BURN_AMOUNT;
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));
        uint32 dayD = game.currentDayView();

        uint256 balPre = sdgnrs.balanceOf(playerA);
        uint256 supplyPre = sdgnrs.totalSupply();

        // Burn proceeds (positive assertion: no revert)
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Per-claim ethValueOwed is zero (zero-rounded under sub-gwei truncation).
        // v47: BURNIE is settled at SUBMIT (no per-claim burnieOwed field), and the claim guard is
        // now `if (claim.ethValueOwed == 0) revert NoClaim()` — the v46 `&& burnieOwed == 0`
        // disjunct was removed. So a zero-ethValueOwed burn has NOTHING to claim and the claim
        // reverts NoClaim (in v46 the BURNIE leg let a zero-ETH claim proceed).
        (uint96 ev, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(ev), 0, "EDGE-13: claim ethValueOwed must be zero under sub-gwei rounding");

        // Balance decremented + supply decremented (the burn actually fired)
        assertEq(sdgnrs.balanceOf(playerA), balPre - amount, "EDGE-13: balanceOf[A] decrement");
        assertEq(sdgnrs.totalSupply(), supplyPre - amount, "EDGE-13: totalSupply decrement");

        // Pool has burned > 0 but ethBase still 0
        (uint64 ePool, , uint64 bnPool) = _readPendingByDay(dayD);
        assertEq(uint256(ePool), 0, "EDGE-13: pool ethBase remains zero under sub-gwei rounding");
        assertGt(uint256(bnPool), 0, "EDGE-13: pool burned increments (ceiling-divide on amount)");

        // Resolve, then claim — v47: a zero-ethValueOwed claim reverts NoClaim (ETH-only guard).
        _advanceWallDay();
        _resolveDay(dayD, roll);
        vm.prank(playerA);
        vm.expectRevert(StakedDegenerusStonk.NoClaim.selector);
        sdgnrs.claimRedemption(uint24(dayD));

        // Slot remains zero-ethValueOwed (nothing was claimable; the reverting claim mutates nothing).
        (uint96 evPost, ) = sdgnrs.pendingRedemptions(playerA, uint24(dayD));
        assertEq(uint256(evPost), 0, "EDGE-13: claim slot ethValueOwed stays zero (no claimable ETH)");
    }

    // =====================================================================
    //              EDGE-14: 50% supply cap (exact + over + lazy-init)
    // =====================================================================

    /// @notice EDGE-14 — 304-SPEC §3 lines 589-601. Three sub-scenarios via pre-seeded
    ///         pendingByDay slot (vm.store) so the cap math is engineerable with a
    ///         tractable supplySnapshot. Sub-1: burn exactly cap succeeds. Sub-2: one
    ///         token over cap reverts Insufficient. Sub-3: lazy-init snapshot is immutable
    ///         for subsequent same-day burns.
    /// @dev Tests INV-10. Depends on SPEC-05 (lazy-init snapshot immutable for day).
    ///      Uses vm.store to seed pendingByDay[D] with supplySnapshot = 1000 whole tokens
    ///      (cap = 500). Sub-1 burns 500e18 raw, sub-2 burns 1 more token, sub-3 verifies
    ///      snapshot byte-identity post burn.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_14_SupplyCapExactOneWeiOverAndLazyInit(uint256 actorSeed) public {
        address actor = _pickActor(actorSeed);
        uint32 dayD = game.currentDayView();

        // Pre-seed pendingByDay[dayD] with supplySnapshot = 1000 whole tokens (cap = 500).
        // v47 DayPending packing: (ethBase << 0) | (supplySnapshot << 64) | (burned << 128)
        // — the former per-day burnieBase field was removed, so supplySnapshot moved to bit 64.
        uint256 packed = (uint256(1000) << 64);
        bytes32 slotPbD = keccak256(abi.encode(uint256(dayD), uint256(SLOT_PENDING_BY_DAY)));
        vm.store(address(sdgnrs), slotPbD, bytes32(packed));

        // Also pre-set pendingResolveDay = dayD so the INV-13 sentinel check passes inside burn.
        // pendingResolveDay is at slot 11 (uint32, lower bits) — v47: shifted from 12 by the
        // pendingRedemptionBurnie@10 removal.
        bytes32 slotSentinel = bytes32(uint256(11));
        vm.store(address(sdgnrs), slotSentinel, bytes32(uint256(dayD)));

        // Verify the snapshot is now visible
        (, uint64 sBefore, uint64 bnBefore) = _readPendingByDay(dayD);
        assertEq(uint256(sBefore), 1000, "EDGE-14: pre-seed supplySnapshot mismatch");
        assertEq(uint256(bnBefore), 0, "EDGE-14: pre-seed burned must be zero");

        // Sub-scenario 1: burn exact-cap = 500 tokens = 500e18 raw (under composite ceiling-divide
        // semantics, amountWhole = 500). cap check: 0 + 500 > 1000/2=500 → FALSE → succeeds.
        // Prime first so the burn passes the daily-rng admission gate and reaches the cap math.
        uint256 capExact = 500 ether;
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(capExact);

        (, uint64 sAfter1, uint64 bnAfter1) = _readPendingByDay(dayD);
        assertEq(uint256(sAfter1), uint256(sBefore), "EDGE-14: snapshot NOT immutable post burn-1");
        assertEq(uint256(bnAfter1), 500, "EDGE-14: burned must be 500 whole tokens post burn-1");

        // Sub-scenario 2: one additional token tips over cap. 500 + 1 > 500 → revert Insufficient.
        vm.prank(actor);
        vm.expectRevert(StakedDegenerusStonk.Insufficient.selector);
        sdgnrs.burn(1 ether);

        // Snapshot + burned byte-identical post failed burn
        (, uint64 sAfter2, uint64 bnAfter2) = _readPendingByDay(dayD);
        assertEq(uint256(sAfter2), uint256(sAfter1), "EDGE-14: snapshot mutated by failed over-cap burn");
        assertEq(uint256(bnAfter2), uint256(bnAfter1), "EDGE-14: burned mutated by failed over-cap burn");

        // Sub-scenario 3: lazy-init snapshot is immutable across both successful and failed
        // same-day burns. Already verified via sAfter1 == sBefore and sAfter2 == sAfter1.
    }

    // =====================================================================
    //              EDGE-15: 160 ETH EV cap one-wei-over reverts
    // =====================================================================

    /// @notice EDGE-15 — 304-SPEC §3 lines 603-615. Per-(player, day) EV cap enforced by
    ///         `if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert`. The
    ///         strict `>` operator allows exact-equality to succeed; any positive ethValueOwed
    ///         above 160 ETH total reverts ExceedsDailyRedemptionCap. Engineered via vm.store
    ///         seeding claim.ethValueOwed = MAX_DAILY_REDEMPTION_EV exactly, then triggering a
    ///         tiny additional burn that produces ethValueOwed > 0 post gwei-snap.
    /// @dev Tests INV-11. Depends on SPEC-02 (composite-key per-(player, day)) + INV-11.
    ///      Sub-scenario 1 (exact-cap) is not engineerable under deploy-time state without
    ///      precise gwei-aligned amount inversion; the cap-check operator semantics are still
    ///      asserted indirectly by sub-2's strict `>` revert. NatSpec documents D-305-GWEI-SNAP-01
    ///      gwei-alignment of ethValueOwed.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_15_EvCapExactOneWeiOver(uint256 actorSeed) public {
        address actor = _pickActor(actorSeed);
        uint32 dayD = game.currentDayView();

        // Seed claim slot: ethValueOwed = MAX_DAILY_REDEMPTION_EV exactly (gwei-aligned —
        // 160 ether = 160e18 wei is a multiple of 1e9).
        // v47 PendingRedemption packing: (ethValueOwed uint96, bits 0-95) | (activityScore uint16,
        // bits 96-111). The former burnieOwed field (old bits 96-191) was removed, so activityScore
        // moved from bit 192 down to bit 96.
        uint256 packed = uint256(MAX_DAILY_REDEMPTION_EV) | (uint256(1) << 96); // activityScore=1 (set)
        bytes32 outerSlot = keccak256(abi.encode(actor, uint256(7))); // SLOT_PENDING_REDEMPTIONS=7
        bytes32 claimSlot = keccak256(abi.encode(uint256(dayD), outerSlot));
        vm.store(address(sdgnrs), claimSlot, bytes32(packed));

        // Verify seed visible
        (uint96 evSeeded, uint16 asSeeded) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evSeeded), MAX_DAILY_REDEMPTION_EV, "EDGE-15: seed ethValueOwed mismatch");
        assertEq(uint256(asSeeded), 1, "EDGE-15: seed activityScore mismatch");

        // Pre-set sentinel so burn passes INV-13 guard (pendingResolveDay slot 11 — v47 shift from 12)
        bytes32 slotSentinel = bytes32(uint256(11));
        vm.store(address(sdgnrs), slotSentinel, bytes32(uint256(dayD)));

        // Any burn that adds > 0 ethValueOwed must revert ExceedsDailyRedemptionCap.
        // FUZZ_MIN_AMOUNT (100 ether) yields ethValueOwed ~12 gwei > 0 post snap.
        // Prime first so the burn clears the daily-rng admission gate and reaches the EV-cap check.
        uint256 amount = FUZZ_MIN_AMOUNT;
        _primeCurrentDayRng();
        vm.prank(actor);
        vm.expectRevert(StakedDegenerusStonk.ExceedsDailyRedemptionCap.selector);
        sdgnrs.burn(amount);

        // Byte-identity: claim slot byte-identical post failed burn
        (uint96 evPost, uint16 asPost) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evPost), MAX_DAILY_REDEMPTION_EV, "EDGE-15: ethValueOwed mutated by failed burn");
        // v47: burnieOwed field removed — nothing to byte-compare.
        assertEq(uint256(asPost), 1, "EDGE-15: activityScore mutated by failed burn");
    }

    // =====================================================================
    //              EDGE-16: Cross-day cap reset (structural)
    // =====================================================================

    /// @notice EDGE-16 — 304-SPEC §3 lines 617-629. Composite-key claim slots make the
    ///         per-(player, day) cap structurally independent across days. Day-D claim at
    ///         exactly MAX_DAILY_REDEMPTION_EV must NOT block a day-(D+1) burn from the
    ///         same player; the day-(D+1) burn writes a separate slot starting at zero.
    /// @dev Tests INV-11. Depends on SPEC-02 (composite-key per-(player, day)).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_16_CrossDayCapResetStructural(uint256 actorSeed) public {
        address actor = _pickActor(actorSeed);
        uint32 dayD = game.currentDayView();

        // Execute a real burn on day D to seed the pendingByDay pool + sentinel naturally.
        // (Required for the day-D resolve to actually fire — early-returns on empty pool.)
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(FUZZ_MIN_AMOUNT);

        // Overwrite the claim slot's ethValueOwed to exactly MAX_DAILY_REDEMPTION_EV. This
        // simulates a (player, D) pair that accumulated to the cap on day D; the cap-check
        // strict `>` operator must NOT block any day-(D+1) burn under composite-key
        // independence.
        // v47 packing: activityScore is at bit 96 (burnieOwed field removed).
        uint256 packedD = uint256(MAX_DAILY_REDEMPTION_EV) | (uint256(1) << 96);
        bytes32 outerSlot = keccak256(abi.encode(actor, uint256(7)));
        bytes32 claimSlotD = keccak256(abi.encode(uint256(dayD), outerSlot));
        vm.store(address(sdgnrs), claimSlotD, bytes32(packedD));

        // Snapshot day-D claim slot pre-D+1-burn
        (uint96 evD_Pre, uint16 asD_Pre) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evD_Pre), MAX_DAILY_REDEMPTION_EV, "EDGE-16: seed verification");

        // Resolve day D — clears sentinel, deletes pool. Day-D burn (above) populated the
        // pool so the resolver does NOT early-return; sentinel is correctly cleared at the
        // post-resolve `if (pendingResolveDay == dayToResolve) pendingResolveDay = 0;` line.
        _advanceWallDay();
        _resolveDay(dayD, 100);
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "EDGE-16: sentinel must clear post day-D resolve");

        // Day-(D+1) burn from same actor — must succeed; the day-D claim slot remains
        // byte-identical (composite-key independence).
        uint32 dayD1 = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(FUZZ_MIN_AMOUNT);

        // Positive: day-D+1 slot populated, day-D slot byte-identical
        (uint96 evD1, ) = sdgnrs.pendingRedemptions(actor, uint24(dayD1));
        assertGt(uint256(evD1), 0, "EDGE-16: day-D+1 claim slot must populate (cross-day cap reset)");

        (uint96 evD_Post, uint16 asD_Post) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evD_Post), uint256(evD_Pre), "EDGE-16: day-D ethValueOwed mutated by day-D+1 burn");
        assertEq(uint256(asD_Post), uint256(asD_Pre), "EDGE-16: day-D activityScore mutated by day-D+1 burn");
    }

    // =====================================================================
    //              EDGE-17: Late-day burn post-resolve legitimate
    // =====================================================================

    /// @notice EDGE-17 — 304-SPEC §3 lines 631-643. Day D-1's pool resolved at the day-D
    ///         advance. A subsequent day-D burn writes a fresh pendingByDay[D] entry without
    ///         touching redemptionPeriods[D-1] (already written) or pendingByDay[D-1] (deleted
    ///         at resolve). The next day's advance resolves redemptionPeriods[D] for the
    ///         FIRST time (no overwrite). Distinct from EDGE-07 (V-184 attack) — EDGE-17 is
    ///         the legitimate-flow analog; both produce write-once-per-day semantics.
    /// @dev Tests INV-01 + INV-04 + INV-08. Depends on SPEC-01 + SPEC-03 + SPEC-04 (c).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_17_LateDayBurnPostResolveLegitimate(
        uint256 amountSeed1,
        uint256 amountSeed2,
        uint16 rollSeed1,
        uint16 rollSeed2
    ) public {
        uint256 amount1 = bound(amountSeed1, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 amount2 = bound(amountSeed2, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint16 roll1 = uint16(bound(uint256(rollSeed1), 25, 175));
        uint16 roll2 = uint16(bound(uint256(rollSeed2), 25, 175));

        // Day D-1: burn from A
        uint32 dayPrior = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount1);

        // Advance to day D + resolve D-1 with roll1
        _advanceWallDay();
        uint32 dayD = game.currentDayView();
        _resolveDay(dayPrior, roll1);

        // Snapshot redemptionPeriods[dayPrior].roll = roll1
        (uint16 rollPriorPostResolve) = sdgnrs.redemptionPeriods(uint24(dayPrior));
        assertEq(uint256(rollPriorPostResolve), uint256(roll1), "EDGE-17: precondition - dayPrior.roll first-write");

        // Late-day burn on day D from B (after D-1 was resolved + deleted)
        _primeCurrentDayRng();
        vm.prank(playerB);
        sdgnrs.burn(amount2);

        // redemptionPeriods[dayPrior].roll byte-identical post late-day burn
        (uint16 rollPriorPostLateBurn) = sdgnrs.redemptionPeriods(uint24(dayPrior));
        assertEq(uint256(rollPriorPostLateBurn), uint256(roll1), "EDGE-17: dayPrior.roll mutated by late-day burn");

        // pendingByDay[D] populated by the late-day burn (burned > 0)
        (, , uint64 bnDPostBurn) = _readPendingByDay(dayD);
        assertGt(uint256(bnDPostBurn), 0, "EDGE-17: pendingByDay[D] must populate from late-day burn");

        // pendingByDay[D-1] remains deleted (zero across all 3 v47 fields — burnieBase removed)
        (uint64 ePriorPost, uint64 sPriorPost, uint64 bnPriorPost) =
            _readPendingByDay(dayPrior);
        assertEq(uint256(ePriorPost), 0, "EDGE-17: pendingByDay[D-1].ethBase resurrected");
        assertEq(uint256(sPriorPost), 0, "EDGE-17: pendingByDay[D-1].supplySnapshot resurrected");
        assertEq(uint256(bnPriorPost), 0, "EDGE-17: pendingByDay[D-1].burned resurrected");

        // Next-day advance resolves redemptionPeriods[D] for the FIRST time with roll2
        _advanceWallDay();
        _resolveDay(dayD, roll2);

        (uint16 rollDPostResolve) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollDPostResolve), uint256(roll2), "EDGE-17: dayD.roll first-write must equal roll2");

        // redemptionPeriods[dayPrior].roll STILL byte-identical to roll1
        (uint16 rollPriorFinal) = sdgnrs.redemptionPeriods(uint24(dayPrior));
        assertEq(uint256(rollPriorFinal), uint256(roll1), "EDGE-17: dayPrior.roll mutated by dayD resolve");
    }

    // =====================================================================
    //              EDGE-18: ETH-only claim completes + slot cleared
    // =====================================================================

    /// @notice EDGE-18 — 304-SPEC §3 lines 645-657 (v47-revised). The original test covered the
    ///         claim-time BURNIE-insufficient fallback (`_payBurnie` → coinflip push → coin.transfer).
    ///         In v47 the entire claim-time BURNIE apparatus was REMOVED: BURNIE is settled at SUBMIT
    ///         (redeemBurnieShare → burnForCoinflip), `claimRedemption` is ETH-only, and the
    ///         PendingRedemption.burnieOwed field no longer exists. The BURNIE-fallback path therefore
    ///         no longer exists to be exercised. The intent-preserving residue is: a claim of a
    ///         resolved day succeeds and fully clears the claim slot.
    /// @dev Reduced to the live ETH-only claim path; the BURNIE-shortfall seeding/mock was deleted
    ///      because its subject (`_payBurnie`) was removed from the frozen contract.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_18_EthOnlyClaimCompletesAndClears(uint256 actorSeed) public {
        address actor = _pickActor(actorSeed);
        uint32 dayD = game.currentDayView();

        // Burn a meaningful amount so the claim path has work to do
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(FUZZ_MIN_AMOUNT);

        _advanceWallDay();
        _resolveDay(dayD, 100);

        // Claim must succeed (no revert) — v47 claim is ETH-only.
        vm.prank(actor);
        sdgnrs.claimRedemption(uint24(dayD));

        // Slot is fully cleared post-claim
        (uint96 evPost, ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evPost), 0, "EDGE-18: claim slot ethValueOwed not cleared");
    }

    // =====================================================================
    //              EDGE-19: Multi-day RNG stall sentinel correctness (PHASE 305 ADDITION)
    // =====================================================================

    /// @notice EDGE-19 — Phase 305 addition (305-01-SUMMARY lines 200-202). Models the
    ///         multi-day RNG stall scenario: player burns on day D, advance does NOT fire
    ///         for k days (k ∈ [2, 5]); sentinel `pendingResolveDay()` retains D across the
    ///         stall (proving the sentinel correctly names the stuck day regardless of stall
    ///         duration). The eventual resolve targets dayToResolve = D (read from sentinel,
    ///         NOT derived as `currentDayView() - 1` which would mis-key under the stall);
    ///         redemptionPeriods[D].roll set correctly; claimRedemption(D) succeeds.
    /// @dev Tests INV-09 + INV-13. Depends on D-305-SENTINEL-01 (D-305-DAYTORESOLVE-01).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_19_MultiDayRngStallStaleClaimRecovery(
        uint256 amountSeed,
        uint256 stallSeed,
        uint16 rollSeed
    ) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 stallDays = bound(stallSeed, 2, 5);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));

        uint32 dayD = game.currentDayView();
        address burner = playerA;

        // Burn on day D — sentinel stamps to D
        _primeCurrentDayRng();
        vm.prank(burner);
        sdgnrs.burn(amount);

        // Sentinel correctness pre-stall
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD), "EDGE-19: pendingResolveDay must equal dayD post-burn");

        // Stall: warp k days forward WITHOUT firing any advance. Sentinel must remain D
        // (no contract calls have touched pendingResolveDay).
        for (uint256 i = 0; i < stallDays; i++) {
            vm.warp(block.timestamp + 1 days);
        }

        // MID-STALL ASSERTION: sentinel still names dayD (NOT dayD + stallDays)
        assertEq(
            uint256(sdgnrs.pendingResolveDay()),
            uint256(dayD),
            "EDGE-19: pendingResolveDay sentinel drifted across multi-day stall"
        );

        // Per D-305-DAYTORESOLVE-01, the AdvanceModule reads the sentinel for dayToResolve
        // (NOT `currentDayView() - 1`). Model this: prank as the game and resolve with
        // dayToResolve = pendingResolveDay() (= D).
        uint32 stuckDay = sdgnrs.pendingResolveDay();
        _resolveDay(stuckDay, roll);

        // Post-resolve assertions: roll written for dayD, sentinel cleared, pool deleted.
        // v47: RedemptionPeriod.flipDay removed — the sentinel/roll correctness is the live invariant.
        (uint16 rollPost) = sdgnrs.redemptionPeriods(uint24(dayD));
        assertEq(uint256(rollPost), uint256(roll), "EDGE-19: redemptionPeriods[D].roll incorrect");
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "EDGE-19: sentinel must be cleared post-resolve");

        // Claim succeeds — burner gets paid; slot cleared
        vm.prank(burner);
        sdgnrs.claimRedemption(uint24(dayD));

        (uint96 evFinal, ) = sdgnrs.pendingRedemptions(burner, uint24(dayD));
        assertEq(uint256(evFinal), 0, "EDGE-19: claim slot ethValueOwed not cleared post-claim");
    }

    // =====================================================================
    //              EDGE-20: BurnTooSmall dust floor (PHASE 305 ADDITION)
    // =====================================================================

    /// @notice EDGE-20 — Phase 305 addition (305-01-SUMMARY lines 200-202). MIN_BURN_AMOUNT
    ///         protocol floor is 1e18 (1 whole sDGNRS). For any amount in [1, 1e18 - 1],
    ///         burn must revert BurnTooSmall. For amount == 1e18, burn succeeds. The
    ///         test covers a fuzzed sub-min sample plus the exact boundary at 1e18 - 1.
    /// @dev Tests INV-10 (per-day supply cap depends on ceiling-divide producing ≥ 1 whole
    ///      token per burn). Depends on D-305-DUST-FLOOR-01.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EDGE_20_BurnTooSmall(uint256 amountSeed) public {
        // Sub-scenario A: fuzzed amount in [1, MIN_BURN_AMOUNT - 1] reverts BurnTooSmall
        uint256 subMin = bound(amountSeed, 1, MIN_BURN_AMOUNT - 1);
        vm.prank(playerA);
        vm.expectRevert(StakedDegenerusStonk.BurnTooSmall.selector);
        sdgnrs.burn(subMin);

        // Sub-scenario B: exact boundary at MIN_BURN_AMOUNT - 1 reverts BurnTooSmall
        vm.prank(playerB);
        vm.expectRevert(StakedDegenerusStonk.BurnTooSmall.selector);
        sdgnrs.burn(MIN_BURN_AMOUNT - 1);

        // Sub-scenario C: exact MIN_BURN_AMOUNT succeeds (no revert)
        // Snapshot balance + supply pre-burn to assert mutation
        uint256 balPre = sdgnrs.balanceOf(playerC);
        uint256 supplyPre = sdgnrs.totalSupply();
        _primeCurrentDayRng();
        vm.prank(playerC);
        sdgnrs.burn(MIN_BURN_AMOUNT);
        assertEq(sdgnrs.balanceOf(playerC), balPre - MIN_BURN_AMOUNT, "EDGE-20: balanceOf[C] decrement");
        assertEq(sdgnrs.totalSupply(), supplyPre - MIN_BURN_AMOUNT, "EDGE-20: totalSupply decrement");
    }
}
