// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {StakedDegenerusStonk} from "../../contracts/StakedDegenerusStonk.sol";

/// @notice Local mirror of the coinflip player surface for vm.mockCall selectors. Mirrors the
///         interface in RedemptionEdgeCases.t.sol and RedemptionGas.t.sol; redeclared locally
///         so this file does not depend on the coinflip contract import.
interface IBurnieCoinflipPlayerMock {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

/// @title StakedStonkRedemption — Per-function fuzz suite for v44 sStonk gambling surface
/// @notice Mechanizes ROADMAP §306 Success Criterion 1: per-function fuzz coverage isolated to a
///         single sStonk surface function each. Six ROADMAP-canonical names (verbatim per the
///         §306 list) plus two extras for ACL + sentinel coverage:
///
///         ROADMAP-canonical:
///         - testFuzz_BurnLandsInCurrentDayPool
///         - testFuzz_ResolveWritesCorrectDay
///         - testFuzz_ClaimReadsCorrectDay
///         - testFuzz_MultipleSameDayBurnsAggregate
///         - testFuzz_SupplyCapEnforced
///         - testFuzz_EvCapEnforced
///
///         Plan-augment additions:
///         - testFuzz_ResolveRevertsForNonGame   (ACL — Unauthorized revert for non-game callers)
///         - testFuzz_BurnSetsSentinelOnFirstBurnOfDay (INV-13 sentinel write/clear cycle)
///
///         Each function focuses on a single function's post-condition + an edge boundary in
///         isolation. Cross-action invariant coverage is delegated to Plan 01
///         (test/invariant/RedemptionAccounting.t.sol). Scenario coverage is delegated to Plan 02
///         (test/fuzz/RedemptionEdgeCases.t.sol). EDGE-07 V-184 byte-identity attestation is in
///         Plan 02.
///
/// @dev Run:
///        FOUNDRY_PROFILE=deep forge test --match-path "test/fuzz/StakedStonkRedemption.t.sol"
///      Each function carries a `default.fuzz.runs = 10000` inline-config NatSpec override so
///      the 10k-runs target applies regardless of which profile invokes `forge test`.
///
///      MIN_BURN_AMOUNT (1e18) and MAX_DAILY_REDEMPTION_EV (160 ether) mirror the private sStonk
///      constants verbatim; FUZZ_MIN_AMOUNT (100 ether) is the test-side lower bound for burns
///      that need ethValueOwed > 1 gwei post D-305-GWEI-SNAP-01 (the protocol floor of 1 token
///      produces sub-gwei proportional value at deploy-time supply).
contract StakedStonkRedemption is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @dev Mirrors `StakedDegenerusStonk.MIN_BURN_AMOUNT` (private literal `1e18`).
    uint256 internal constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Mirrors `StakedDegenerusStonk.MAX_DAILY_REDEMPTION_EV` (private literal `160 ether`).
    uint256 internal constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Per-actor sDGNRS funding (1M tokens). Enough headroom for repeated burns without
    ///      hitting per-wallet balance limits across the suite.
    uint256 internal constant ACTOR_FUNDING = 1_000_000 ether;

    /// @dev Test-side lower bound for amount fuzzing. The protocol floor MIN_BURN_AMOUNT (1e18 =
    ///      1 whole token) produces ethValueOwed ≈ 0.125 gwei at deploy-time supply (~8e29) and
    ///      totalMoney = 100 ETH; that value truncates to 0 post D-305-GWEI-SNAP-01. Using
    ///      100 ether as the lower bound guarantees ethValueOwed ≥ ~12 gwei (positive post-snap)
    ///      so the per-function assertions on positive ethBase/ethValueOwed are well-formed.
    uint256 internal constant FUZZ_MIN_AMOUNT = 100 ether;

    /// @dev Storage slot of the `pendingByDay` mapping per v44 layout. Derived once via
    ///      `forge inspect contracts/StakedDegenerusStonk.sol:StakedDegenerusStonk storage-layout`
    ///      in Phase 305 305-01-SUMMARY (slot 11). Embedded inline so the test file is
    ///      self-contained.
    uint256 internal constant SLOT_PENDING_BY_DAY = 11;

    /// @dev Storage slot of the outer `pendingRedemptions` mapping (composite key:
    ///      mapping(address => mapping(uint32 => PendingRedemption))). Slot 7 per v44 layout.
    uint256 internal constant SLOT_PENDING_REDEMPTIONS = 7;

    /// @dev Storage slot of the `pendingResolveDay` sentinel (uint32, slot 12 per v44 layout).
    uint256 internal constant SLOT_PENDING_RESOLVE_DAY = 12;

    // =====================================================================
    //                          ACTORS
    // =====================================================================

    address internal playerA;
    address internal playerB;
    address internal playerC;
    address internal playerD;

    function setUp() public {
        _deployProtocol();
        // Warp 1 day past the deploy-pinned timestamp so currentDayView() is off day 0
        // (RedemptionGas.t.sol setUp precedent).
        vm.warp(block.timestamp + 1 days);

        // Fund game with 100 ETH backing + credit it to sDGNRS's claimableWinnings entry so
        // proportional payout math has nonzero totalMoney. Slot 7 = claimableWinnings mapping;
        // slot 1 upper 128 bits = claimablePool. Both writes mirror RedemptionGas.t.sol :32-38.
        vm.deal(address(game), 100 ether);
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        vm.store(address(game), claimableSlot, bytes32(uint256(100 ether)));
        uint256 slot1Val = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1Val = (slot1Val & type(uint128).max) | (uint256(100 ether) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1Val));

        // Spin up 4 distinct actors and fund via the Reward pool (game contract is the
        // authorized caller for transferFromPool).
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

        // Mock coinflip player surface so claim path takes the full-payout branch (precedent
        // from RedemptionGas.t.sol :96-109). Without these mocks, claim hits the partial-claim
        // branch which preserves the slot — breaks the delete-at-full-claim assertion in
        // testFuzz_ClaimReadsCorrectDay.
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
        // Mock resolveRedemptionLootbox to a no-op so the 50%-lootbox-routing branch in claim
        // (live game) does not revert on un-seeded game-side lootbox slots. The per-function
        // suite focuses on sStonk surface semantics; lootbox internals are out-of-scope.
        vm.mockCall(
            address(game),
            abi.encodeWithSelector(game.resolveRedemptionLootbox.selector),
            abi.encode()
        );
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Resolve a day's pool by pranking the game contract. Bypasses the full advance + VRF
    ///      cycle for deterministic roll values. Precedent at
    ///      `test/fuzz/RedemptionGas.t.sol:77-78`.
    function _resolveDay(uint32 dayToResolve, uint16 roll, uint32 flipDay) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, flipDay, dayToResolve);
    }

    /// @dev Read packed `pendingByDay[day]` slot and unpack 4×uint64 fields per the v44 layout
    ///      defined in `StakedDegenerusStonk.DayPending`.
    function _readPendingByDay(uint32 day)
        internal
        view
        returns (uint64 ethBase, uint64 burnieBase, uint64 supplySnapshot, uint64 burned)
    {
        bytes32 slot = keccak256(abi.encode(uint256(day), uint256(SLOT_PENDING_BY_DAY)));
        uint256 raw = uint256(vm.load(address(sdgnrs), slot));
        ethBase = uint64(raw);
        burnieBase = uint64(raw >> 64);
        supplySnapshot = uint64(raw >> 128);
        burned = uint64(raw >> 192);
    }

    /// @dev Pack a 4×uint64 DayPending into a single 256-bit word (test-side mirror of the
    ///      sStonk layout). Used by tests that seed a pool via vm.store.
    function _packPendingByDay(
        uint64 ethBase,
        uint64 burnieBase,
        uint64 supplySnapshot,
        uint64 burned
    ) internal pure returns (uint256) {
        return uint256(ethBase)
            | (uint256(burnieBase) << 64)
            | (uint256(supplySnapshot) << 128)
            | (uint256(burned) << 192);
    }

    /// @dev Warp the wall clock by 1 day.
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
    //         testFuzz_BurnLandsInCurrentDayPool (ROADMAP-canonical)
    // =====================================================================

    /// @notice burn(amount) writes to `pendingByDay[game.currentDayView()]` and to no other day.
    ///         Captures D_pre = currentDayView(); after the burn `pendingByDay[D_pre]` has
    ///         `burned > 0` (always) and `ethBase > 0` (under FUZZ_MIN_AMOUNT lower bound), and
    ///         every other day in [D_pre - 3, D_pre + 3] except D_pre is byte-identical pre/post.
    ///         currentDayView() is unchanged (no day advance side effect). The sentinel
    ///         `pendingResolveDay()` equals D_pre after the burn (304-SPEC §1 INV-13).
    /// @dev Tests `burn` (gambling path) in isolation. Anchors: INV-04 (per-day base
    ///      correctness), SPEC-01 (per-day-keyed pool), D-305-SENTINEL-01 (INV-13 stamp).
    ///      Assertion strategy: capture a 7-day window pre-burn, burn, verify only D_pre slot
    ///      mutated.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_BurnLandsInCurrentDayPool(uint256 actorSeed, uint256 amountSeed) public {
        address actor = _pickActor(actorSeed);
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        uint32 dayPre = game.currentDayView();

        // Snapshot a 7-day window centered on dayPre. uint32 subtraction safety: dayPre >= 1
        // post-setUp (warped 1 day past deploy-pinned timestamp); the window probes 3 days back
        // which underflows only if dayPre < 3. _deployProtocol pins timestamp at 86400, then we
        // warp +1 day → currentDayView is approximately initial-day + 1. Initial day is the
        // sStonk deployment day index (≥ 1). Use saturating arithmetic to keep the test robust
        // under any future setUp timing change.
        uint32 windowStart = dayPre > 3 ? dayPre - 3 : 0;
        uint32 windowEnd = dayPre + 3;

        // Pre-burn snapshot of every day's packed slot.
        uint256[7] memory rawPre;
        for (uint32 d = windowStart; d <= windowEnd; d++) {
            bytes32 slot = keccak256(abi.encode(uint256(d), uint256(SLOT_PENDING_BY_DAY)));
            rawPre[d - windowStart] = uint256(vm.load(address(sdgnrs), slot));
        }

        // Burn — must succeed (gambling path; not gameOver / not rngLocked / not livenessTriggered
        // at deploy-time state).
        vm.prank(actor);
        sdgnrs.burn(amount);

        // Positive assertion: dayPre slot populated. `burned` is the always-reliable
        // populated-indicator (≥1 whole token via ceiling-divide); `ethBase > 0` under
        // FUZZ_MIN_AMOUNT lower bound; `supplySnapshot > 0` via lazy-init (SPEC-05).
        (uint64 ePost, , uint64 sPost, uint64 bnPost) = _readPendingByDay(dayPre);
        assertGt(uint256(sPost), 0, "burn: supplySnapshot must lazy-init on first burn of day");
        assertGt(uint256(bnPost), 0, "burn: burned must increment (ceiling-divide >= 1 whole token)");
        assertGt(uint256(ePost), 0, "burn: ethBase must be populated under FUZZ_MIN_AMOUNT lower bound");

        // currentDayView() unchanged
        assertEq(uint256(game.currentDayView()), uint256(dayPre), "burn: currentDayView side-effected");

        // Sentinel == dayPre per INV-13 stamp
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayPre), "burn: pendingResolveDay sentinel not stamped to dayPre");

        // Negative assertion: every OTHER day in the window byte-identical pre/post.
        for (uint32 d = windowStart; d <= windowEnd; d++) {
            if (d == dayPre) continue;
            bytes32 slot = keccak256(abi.encode(uint256(d), uint256(SLOT_PENDING_BY_DAY)));
            uint256 rawPost = uint256(vm.load(address(sdgnrs), slot));
            assertEq(rawPost, rawPre[d - windowStart], "burn: non-current-day pendingByDay slot mutated");
        }
    }

    // =====================================================================
    //         testFuzz_ResolveWritesCorrectDay (ROADMAP-canonical)
    // =====================================================================

    /// @notice resolveRedemptionPeriod(roll, flipDay, dayToResolve) writes exactly to
    ///         `redemptionPeriods[dayToResolve]` and to no other day; deletes
    ///         `pendingByDay[dayToResolve]`; clears the sentinel when it matches dayToResolve.
    ///         Asserts adjacent days [dayToResolve - 1, dayToResolve + 1] are byte-identical
    ///         pre/post.
    /// @dev Tests `resolveRedemptionPeriod` in isolation. Anchors: SPEC-03 (per-day resolve),
    ///      SPEC-04 (c) (delete-at-resolve), D-305-SENTINEL-01 (sentinel clear).
    ///      Roll bounded to [25, 175] per AdvanceModule's production range (resolveRedemptionPeriod
    ///      itself does not enforce — passes through — but we honor the realistic range in fuzz
    ///      since roll == 0 is the unresolved sentinel and out-of-range writes are out-of-scope
    ///      for this per-function assertion).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_ResolveWritesCorrectDay(
        uint256 amountSeed,
        uint16 rollSeed,
        uint32 flipDaySeed
    ) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));
        // Bound flipDay to a small positive range — flipDay is the coinflip-day index, not the
        // wall day. Use [1, type(uint32).max / 2] to ensure non-zero and avoid edge-int issues.
        uint32 flipDay = uint32(bound(uint256(flipDaySeed), 1, type(uint32).max / 2));

        // Step 1: burn on day D_burn so the resolver has a non-empty pool to act on (otherwise
        // resolveRedemptionPeriod early-returns at the `if (ethBase == 0 && burnieBase == 0)
        // return;` guard at sStonk:641 — no state mutation, the per-day write would never fire).
        uint32 dayBurn = game.currentDayView();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Verify pool populated
        (, , , uint64 bnPreResolve) = _readPendingByDay(dayBurn);
        assertGt(uint256(bnPreResolve), 0, "resolve: precondition - pool must be populated");

        // Snapshot redemptionPeriods at dayBurn - 1 and dayBurn + 1 (must be byte-identical
        // pre/post since the resolver only writes [dayBurn]).
        uint32 dayLow = dayBurn > 0 ? dayBurn - 1 : 0;
        uint32 dayHigh = dayBurn + 1;
        (uint16 rollLowPre, uint32 fdLowPre) = sdgnrs.redemptionPeriods(dayLow);
        (uint16 rollHighPre, uint32 fdHighPre) = sdgnrs.redemptionPeriods(dayHigh);

        // Step 2: advance wall day so we're no longer on dayBurn — production semantics
        // (AdvanceModule resolves the prior day after the wall clock has crossed the boundary).
        _advanceWallDay();

        // Step 3: resolve dayBurn
        _resolveDay(dayBurn, roll, flipDay);

        // Positive assertion: redemptionPeriods[dayBurn] == (roll, flipDay)
        (uint16 rollPost, uint32 fdPost) = sdgnrs.redemptionPeriods(dayBurn);
        assertEq(uint256(rollPost), uint256(roll), "resolve: redemptionPeriods[dayBurn].roll mismatch");
        assertEq(uint256(fdPost), uint256(flipDay), "resolve: redemptionPeriods[dayBurn].flipDay mismatch");

        // Negative assertion: adjacent days byte-identical pre/post
        (uint16 rollLowPost, uint32 fdLowPost) = sdgnrs.redemptionPeriods(dayLow);
        (uint16 rollHighPost, uint32 fdHighPost) = sdgnrs.redemptionPeriods(dayHigh);
        assertEq(uint256(rollLowPost), uint256(rollLowPre), "resolve: dayBurn-1.roll mutated");
        assertEq(uint256(fdLowPost), uint256(fdLowPre), "resolve: dayBurn-1.flipDay mutated");
        assertEq(uint256(rollHighPost), uint256(rollHighPre), "resolve: dayBurn+1.roll mutated");
        assertEq(uint256(fdHighPost), uint256(fdHighPre), "resolve: dayBurn+1.flipDay mutated");

        // pendingByDay[dayBurn] fully zeroed per SPEC-04 (c) delete-at-resolve
        (uint64 ePost, uint64 bPost, uint64 sPost, uint64 bnPost) = _readPendingByDay(dayBurn);
        assertEq(uint256(ePost), 0, "resolve: delete-at-resolve must zero ethBase");
        assertEq(uint256(bPost), 0, "resolve: delete-at-resolve must zero burnieBase");
        assertEq(uint256(sPost), 0, "resolve: delete-at-resolve must zero supplySnapshot");
        assertEq(uint256(bnPost), 0, "resolve: delete-at-resolve must zero burned");

        // Sentinel cleared per D-305-SENTINEL-01
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "resolve: sentinel must clear when pendingResolveDay == dayToResolve");
    }

    // =====================================================================
    //         testFuzz_ClaimReadsCorrectDay (ROADMAP-canonical)
    // =====================================================================

    /// @notice claimRedemption(day) reads the (msg.sender, day) composite-key slot — not
    ///         (sender, day ± 1) — pays out the correct rolled amount, and clears the slot on
    ///         full-claim path. Adjacent days' claim slots are byte-identical pre/post.
    /// @dev Tests `claimRedemption` in isolation. Anchors: SPEC-02 (composite key), SPEC-04 (d)
    ///      (delete-on-full-claim). The expected ETH delivered to the player is
    ///      `(claim.ethValueOwed * roll / 100) / 2` (50% direct, 50% routed to lootbox under live
    ///      game). With gwei-aligned ethValueOwed (D-305-GWEI-SNAP-01) and roll ∈ [25, 175], the
    ///      arithmetic `× roll / 100` is exact since gcd(1e9, 100) = 100. The 50/50 split is
    ///      integer division; if totalRolledEth is odd-wei, the split would skew 1 wei, but
    ///      gwei-aligned values × any roll are always even multiples of 100, so totalRolledEth
    ///      is always divisible by 2 — ethDirect == totalRolledEth / 2 exactly.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_ClaimReadsCorrectDay(
        uint256 actorSeed,
        uint256 amountSeed,
        uint16 rollSeed
    ) public {
        address actor = _pickActor(actorSeed);
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));

        // Step 1: burn on dayBurn
        uint32 dayBurn = game.currentDayView();
        vm.prank(actor);
        sdgnrs.burn(amount);

        // Step 2: advance + resolve dayBurn with the deterministic roll
        _advanceWallDay();
        _resolveDay(dayBurn, roll, dayBurn);

        // Capture pre-claim state: actor's claim slot at dayBurn + adjacent slots at dayBurn-1
        // and dayBurn+1 (must be byte-identical pre/post since claim only touches [actor][dayBurn]).
        // Only ethValueOwed is needed for the payout-equality assertion; the slot is asserted
        // cleared post-claim via a fresh read.
        (uint96 evBurnPre, , ) = sdgnrs.pendingRedemptions(actor, dayBurn);
        uint32 dayLow = dayBurn > 0 ? dayBurn - 1 : 0;
        uint32 dayHigh = dayBurn + 1;
        (uint96 evLowPre, uint96 bvLowPre, uint16 asLowPre) =
            sdgnrs.pendingRedemptions(actor, dayLow);
        (uint96 evHighPre, uint96 bvHighPre, uint16 asHighPre) =
            sdgnrs.pendingRedemptions(actor, dayHigh);

        // Pre-burn slot must be populated for the test to be meaningful.
        assertGt(uint256(evBurnPre), 0, "claim: precondition - claim slot must populate post-burn");

        // Compute expected ETH delivered to the player.
        // totalRolledEth = (ethValueOwed * roll) / 100  — gwei-aligned + gcd(1e9, 100)=100 → exact
        // ethDirect = totalRolledEth / 2 (live game; gameOver path would deliver totalRolledEth)
        uint256 expectedTotalRolledEth = (uint256(evBurnPre) * uint256(roll)) / 100;
        uint256 expectedEthDirect = expectedTotalRolledEth / 2;

        // Step 3: claim — capture ETH delta
        uint256 ethBefore = actor.balance;
        vm.prank(actor);
        sdgnrs.claimRedemption(dayBurn);
        uint256 ethDelta = actor.balance - ethBefore;

        // Positive: payout matches expected EXACTLY (D-305-GWEI-SNAP-01 zero-drift)
        assertEq(ethDelta, expectedEthDirect, "claim: ETH delivered != expected (ethValueOwed * roll / 100 / 2)");

        // Slot cleared on full-claim path (coinflip mock returns (100, true) so flipResolved=true)
        (uint96 evBurnPost, uint96 bvBurnPost, ) = sdgnrs.pendingRedemptions(actor, dayBurn);
        assertEq(uint256(evBurnPost), 0, "claim: full-claim path must delete ethValueOwed");
        assertEq(uint256(bvBurnPost), 0, "claim: full-claim path must delete burnieOwed");

        // Negative assertion: adjacent days' slots byte-identical
        (uint96 evLowPost, uint96 bvLowPost, uint16 asLowPost) =
            sdgnrs.pendingRedemptions(actor, dayLow);
        (uint96 evHighPost, uint96 bvHighPost, uint16 asHighPost) =
            sdgnrs.pendingRedemptions(actor, dayHigh);
        assertEq(uint256(evLowPost), uint256(evLowPre), "claim: dayBurn-1 ethValueOwed mutated");
        assertEq(uint256(bvLowPost), uint256(bvLowPre), "claim: dayBurn-1 burnieOwed mutated");
        assertEq(uint256(asLowPost), uint256(asLowPre), "claim: dayBurn-1 activityScore mutated");
        assertEq(uint256(evHighPost), uint256(evHighPre), "claim: dayBurn+1 ethValueOwed mutated");
        assertEq(uint256(bvHighPost), uint256(bvHighPre), "claim: dayBurn+1 burnieOwed mutated");
        assertEq(uint256(asHighPost), uint256(asHighPre), "claim: dayBurn+1 activityScore mutated");
    }

    // =====================================================================
    //     testFuzz_MultipleSameDayBurnsAggregate (ROADMAP-canonical)
    // =====================================================================

    /// @notice Three same-day burns from the same actor aggregate into one claim slot.
    ///         claim.ethValueOwed after burn3 equals the sum of per-burn deltas, AND
    ///         `pendingByDay[D].ethBase * 1e9 == claim.ethValueOwed` exactly (single-burner
    ///         scenario — D-305-GWEI-SNAP-01 zero-drift). Strict assertEq (no dust tolerance).
    /// @dev Tests the burn aggregation path (same-day, same-actor). Anchors: SPEC-01 (per-day
    ///      pool aggregation), SPEC-02 (composite-key claim slot), D-305-GWEI-SNAP-01 (exact
    ///      accounting). Also asserts `pool.burned * 1e18 >= a1 + a2 + a3` — ceiling-divide
    ///      preserves the cap-accounting upper bound for INV-10.
    ///      Amounts bounded to ACTOR_FUNDING / 100 each so three burns stay well under the
    ///      wallet balance limit (3% of funding).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_MultipleSameDayBurnsAggregate(
        uint256 actorSeed,
        uint256 a1Seed,
        uint256 a2Seed,
        uint256 a3Seed
    ) public {
        address actor = _pickActor(actorSeed);
        // Cap each burn at funding/100 → max sum ≈ 30000 ether. ethValueOwed proportional to
        // amount × (~100e18 / 8e29) ≈ 1.25e-9 wei/wei → 30000e18 × 1.25e-9 ≈ 3.75e10 wei = 37.5
        // gwei. Well under the 160 ETH per-(wallet, day) EV cap so no ExceedsDailyRedemptionCap
        // revert is triggered.
        uint256 a1 = bound(a1Seed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 a2 = bound(a2Seed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint256 a3 = bound(a3Seed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        uint32 dayD = game.currentDayView();

        // Burn 1 — capture per-burn delta
        uint96 evPre1 = 0; // claim slot is zero-init pre-burn-1
        vm.prank(actor);
        sdgnrs.burn(a1);
        (uint96 evPost1, , ) = sdgnrs.pendingRedemptions(actor, dayD);
        uint256 delta1 = uint256(evPost1) - uint256(evPre1);

        // Burn 2 — capture per-burn delta
        vm.prank(actor);
        sdgnrs.burn(a2);
        (uint96 evPost2, , ) = sdgnrs.pendingRedemptions(actor, dayD);
        uint256 delta2 = uint256(evPost2) - uint256(evPost1);

        // Burn 3 — capture per-burn delta
        vm.prank(actor);
        sdgnrs.burn(a3);
        (uint96 evPost3, , ) = sdgnrs.pendingRedemptions(actor, dayD);
        uint256 delta3 = uint256(evPost3) - uint256(evPost2);

        // Positive assertion: aggregate equals sum of deltas (strict assertEq — gwei alignment)
        uint256 sumDeltas = delta1 + delta2 + delta3;
        assertEq(uint256(evPost3), sumDeltas, "aggregate: claim.ethValueOwed != sum of per-burn deltas");

        // Pool↔claim single-burner exact equality (D-305-GWEI-SNAP-01: pool.ethBase × 1e9 ==
        // sum-of-claims). Since this is a single burner, sum-of-claims == claim.ethValueOwed.
        (uint64 ethBase, , , uint64 burned) = _readPendingByDay(dayD);
        assertEq(
            uint256(ethBase) * 1e9,
            uint256(evPost3),
            "aggregate: pool.ethBase * 1e9 != claim.ethValueOwed (D-305-GWEI-SNAP-01 violation)"
        );

        // Cap-accounting upper bound: pool.burned * 1e18 >= a1 + a2 + a3 (ceiling-divide
        // semantics preserve INV-10 — pool.burned is always >= actual cumulative burns).
        assertGe(
            uint256(burned) * 1e18,
            a1 + a2 + a3,
            "aggregate: pool.burned * 1e18 < a1+a2+a3 (ceiling-divide cap-accounting violation)"
        );
    }

    // =====================================================================
    //         testFuzz_SupplyCapEnforced (ROADMAP-canonical)
    // =====================================================================

    /// @notice The 50% per-day supply cap is enforced by `if (pool.burned + amountWhole >
    ///         pool.supplySnapshot / 2) revert Insufficient();` at sStonk:835. Positive: burning
    ///         exactly to the cap succeeds. Negative: one wei over the cap reverts Insufficient
    ///         AND the pool's (supplySnapshot, burned) fields are byte-identical post the failed
    ///         burn.
    /// @dev Tests the supply-cap guard in isolation. Anchors: SPEC-05 (lazy-init snapshot),
    ///      INV-10 (per-day supply cap), D-305-STRUCT-TIGHTEN-01 (whole-token cap accounting).
    ///      Approach: pre-seed `pendingByDay[D]` with supplySnapshot = 1000 whole tokens (cap =
    ///      500) via vm.store + pre-stamp pendingResolveDay = D so the INV-13 guard inside burn
    ///      passes. Then burn exactly 500 tokens (success), then burn 1 more token (revert).
    ///      Same construction pattern as RedemptionEdgeCases.testFuzz_EDGE_14.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_SupplyCapEnforced(uint256 firstBurnSeed, uint256 secondBurnSeed) public {
        address actor = _pickActor(firstBurnSeed);
        uint32 dayD = game.currentDayView();

        // Seed pendingByDay[dayD] with supplySnapshot = 1000 whole tokens (cap = 500).
        uint256 packed = _packPendingByDay(0, 0, 1000, 0);
        bytes32 slotPbD = keccak256(abi.encode(uint256(dayD), uint256(SLOT_PENDING_BY_DAY)));
        vm.store(address(sdgnrs), slotPbD, bytes32(packed));

        // Pre-stamp the sentinel so the INV-13 guard inside burn does NOT trip the
        // PriorDayUnresolved revert. The sentinel must equal currentDayView (= dayD) or 0; we
        // set it to dayD for parity with the burned-by-day pool's seed.
        vm.store(address(sdgnrs), bytes32(uint256(SLOT_PENDING_RESOLVE_DAY)), bytes32(uint256(dayD)));

        // Verify seed visible
        (, , uint64 sBefore, uint64 bnBefore) = _readPendingByDay(dayD);
        assertEq(uint256(sBefore), 1000, "supplyCap: pre-seed supplySnapshot mismatch");
        assertEq(uint256(bnBefore), 0, "supplyCap: pre-seed burned must be zero");

        // Positive sub-scenario: burn EXACTLY to the cap. firstBurnAmount = 500 ether (500 whole
        // tokens). Under ceiling-divide, amountWhole = 500. Cap check: 0 + 500 > 1000/2=500 →
        // FALSE → succeeds. Burn is fuzzed slightly via secondBurnSeed for the over-cap case,
        // but the exact-cap probe uses a deterministic 500 ether for assertion clarity.
        uint256 capExact = 500 ether;
        vm.prank(actor);
        sdgnrs.burn(capExact);

        // Pool state after exact-cap burn
        (, , uint64 sAfter1, uint64 bnAfter1) = _readPendingByDay(dayD);
        assertEq(uint256(sAfter1), uint256(sBefore), "supplyCap: supplySnapshot NOT immutable post burn-1 (SPEC-05)");
        assertEq(uint256(bnAfter1), 500, "supplyCap: burned must equal 500 whole tokens post exact-cap burn");

        // Negative sub-scenario: any subsequent burn tips over the cap. The minimum legal
        // amount under the protocol floor is MIN_BURN_AMOUNT (1 whole token); use a fuzzed
        // amount in [1e18, ACTOR_FUNDING / 100] to ensure all probe values would push burned ≥ 501.
        uint256 overCap = bound(secondBurnSeed, MIN_BURN_AMOUNT, ACTOR_FUNDING / 100);
        vm.prank(actor);
        vm.expectRevert(StakedDegenerusStonk.Insufficient.selector);
        sdgnrs.burn(overCap);

        // Pool state byte-identical post failed burn
        (, , uint64 sAfter2, uint64 bnAfter2) = _readPendingByDay(dayD);
        assertEq(uint256(sAfter2), uint256(sAfter1), "supplyCap: supplySnapshot mutated by failed over-cap burn");
        assertEq(uint256(bnAfter2), uint256(bnAfter1), "supplyCap: burned mutated by failed over-cap burn");
    }

    // =====================================================================
    //         testFuzz_EvCapEnforced (ROADMAP-canonical)
    // =====================================================================

    /// @notice The 160 ETH per-(wallet, day) EV cap is enforced by `if (claim.ethValueOwed +
    ///         ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();` at
    ///         sStonk:883. Approach: pre-seed `pendingRedemptions[actor][D].ethValueOwed =
    ///         MAX_DAILY_REDEMPTION_EV` exactly via vm.store, then any burn that adds positive
    ///         ethValueOwed must revert. Strict `>` operator allows exact-equality (160 ETH
    ///         exactly) to remain valid; the test asserts the FIRST burn whose ethValueOwed > 0
    ///         post the cap-seed reverts.
    /// @dev Tests the EV-cap guard in isolation. Anchors: INV-11 (per-wallet per-day EV cap),
    ///      SPEC-02 (composite-key claim slot). Same vm.store seed pattern as
    ///      RedemptionEdgeCases.testFuzz_EDGE_15.
    ///      The plan describes accumulating burns until the cap is approached, but at deploy-time
    ///      state (totalMoney = 100 ETH, supply ~ 8e29), reaching 160 ETH of ethValueOwed via
    ///      legitimate burns would require burning ~1.28e30 tokens which exceeds totalSupply.
    ///      vm.store is the only tractable path to test the strict-`>` operator semantics; the
    ///      cap-check logic itself is byte-identical regardless of how the claim slot reached
    ///      the cap.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_EvCapEnforced(uint256 actorSeed, uint256 amountSeed) public {
        address actor = _pickActor(actorSeed);
        uint32 dayD = game.currentDayView();

        // Pack PendingRedemption: bits 0-95 = ethValueOwed, 96-191 = burnieOwed, 192-207 =
        // activityScore. Seed ethValueOwed = MAX_DAILY_REDEMPTION_EV (gwei-aligned since 160e18
        // is a multiple of 1e9); activityScore = 1 (treat as set so the lazy-init branch in
        // _submitGamblingClaimFrom does NOT overwrite it).
        uint256 packed = uint256(MAX_DAILY_REDEMPTION_EV) | (uint256(1) << 192);
        bytes32 outerSlot = keccak256(abi.encode(actor, uint256(SLOT_PENDING_REDEMPTIONS)));
        bytes32 claimSlot = keccak256(abi.encode(uint256(dayD), outerSlot));
        vm.store(address(sdgnrs), claimSlot, bytes32(packed));

        // Verify seed visible
        (uint96 evSeed, , uint16 asSeed) = sdgnrs.pendingRedemptions(actor, dayD);
        assertEq(uint256(evSeed), MAX_DAILY_REDEMPTION_EV, "evCap: pre-seed ethValueOwed mismatch");
        assertEq(uint256(asSeed), 1, "evCap: pre-seed activityScore mismatch");

        // Pre-stamp sentinel so INV-13 guard does NOT trip
        vm.store(address(sdgnrs), bytes32(uint256(SLOT_PENDING_RESOLVE_DAY)), bytes32(uint256(dayD)));

        // Any burn that produces ethValueOwed > 0 (post gwei-snap) must revert. FUZZ_MIN_AMOUNT
        // (100 ether) yields ethValueOwed ~12.5 gwei post-snap > 0 → cap check trips. Fuzz the
        // amount in [FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100] to assert the revert across a range.
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        vm.prank(actor);
        vm.expectRevert(StakedDegenerusStonk.ExceedsDailyRedemptionCap.selector);
        sdgnrs.burn(amount);

        // Negative assertion: claim slot byte-identical post failed burn
        (uint96 evPost, uint96 bvPost, uint16 asPost) = sdgnrs.pendingRedemptions(actor, dayD);
        assertEq(uint256(evPost), MAX_DAILY_REDEMPTION_EV, "evCap: ethValueOwed mutated by failed burn");
        assertEq(uint256(bvPost), 0, "evCap: burnieOwed mutated by failed burn");
        assertEq(uint256(asPost), 1, "evCap: activityScore mutated by failed burn");
    }

    // =====================================================================
    //         testFuzz_ResolveRevertsForNonGame (ACL — plan augment)
    // =====================================================================

    /// @notice resolveRedemptionPeriod reverts Unauthorized for any caller != address(game).
    ///         Negative-only test: no positive path (positive ACL coverage is in
    ///         testFuzz_ResolveWritesCorrectDay). Asserts no state mutation occurs on the
    ///         reverting path.
    /// @dev Tests the `if (msg.sender != ContractAddresses.GAME) revert Unauthorized();` guard
    ///      at sStonk:634. Excludes address(game) (would not revert) and address(0) (would
    ///      revert with the same Unauthorized error but the prank semantics on the zero address
    ///      are degenerate). vm.assume keeps reject-rate low: 2^160 - 2 valid addresses out of
    ///      2^160 fuzz inputs → ~0% rejection.
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_ResolveRevertsForNonGame(
        address caller,
        uint16 roll,
        uint32 flipDay,
        uint32 day
    ) public {
        vm.assume(caller != address(game));
        vm.assume(caller != address(0));

        // Pre-state snapshots (must be byte-identical pre/post revert).
        (uint16 rollPre, uint32 fdPre) = sdgnrs.redemptionPeriods(day);
        uint256 cumulativeEthPre = sdgnrs.pendingRedemptionEthValue();
        uint32 sentinelPre = sdgnrs.pendingResolveDay();
        // pendingByDay[day] packed slot snapshot
        bytes32 pbdSlot = keccak256(abi.encode(uint256(day), uint256(SLOT_PENDING_BY_DAY)));
        uint256 pbdRawPre = uint256(vm.load(address(sdgnrs), pbdSlot));

        // Reverting call
        vm.prank(caller);
        vm.expectRevert(StakedDegenerusStonk.Unauthorized.selector);
        sdgnrs.resolveRedemptionPeriod(roll, flipDay, day);

        // Negative assertions: no state change.
        (uint16 rollPost, uint32 fdPost) = sdgnrs.redemptionPeriods(day);
        uint256 cumulativeEthPost = sdgnrs.pendingRedemptionEthValue();
        uint32 sentinelPost = sdgnrs.pendingResolveDay();
        uint256 pbdRawPost = uint256(vm.load(address(sdgnrs), pbdSlot));

        assertEq(uint256(rollPost), uint256(rollPre), "resolveACL: redemptionPeriods.roll mutated by reverting call");
        assertEq(uint256(fdPost), uint256(fdPre), "resolveACL: redemptionPeriods.flipDay mutated by reverting call");
        assertEq(cumulativeEthPost, cumulativeEthPre, "resolveACL: pendingRedemptionEthValue mutated by reverting call");
        assertEq(uint256(sentinelPost), uint256(sentinelPre), "resolveACL: pendingResolveDay mutated by reverting call");
        assertEq(pbdRawPost, pbdRawPre, "resolveACL: pendingByDay[day] mutated by reverting call");
    }

    // =====================================================================
    //   testFuzz_BurnSetsSentinelOnFirstBurnOfDay (INV-13 — plan augment)
    // =====================================================================

    /// @notice INV-13 sentinel write/clear cycle: first burn of a fresh day stamps
    ///         pendingResolveDay = currentDayView; second burn on the same day leaves sentinel
    ///         unchanged; resolve clears the sentinel to 0; first burn of a NEW day re-stamps
    ///         the sentinel to that new day.
    /// @dev Tests the sentinel guard at sStonk:819-821 and the sentinel clear at sStonk:665.
    ///      Anchors: INV-13 (single-pool invariant), D-305-SENTINEL-01 (pendingResolveDay slot).
    /// forge-config: default.fuzz.runs = 10000
    function testFuzz_BurnSetsSentinelOnFirstBurnOfDay(uint256 actorSeed, uint256 amountSeed) public {
        address actor = _pickActor(actorSeed);
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);

        uint32 dayD = game.currentDayView();

        // Precondition: sentinel == 0 at deploy-time fresh state (no prior burns).
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "sentinel: pre-burn sentinel must be 0 (fresh state)");

        // First burn of dayD — sentinel stamps to dayD
        vm.prank(actor);
        sdgnrs.burn(amount);
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD), "sentinel: post first-burn must stamp pendingResolveDay = dayD");

        // Second burn on same day — sentinel unchanged (stamp == currentPeriod branch at
        // sStonk:819-821 takes the "stamp != 0 && stamp == currentPeriod" path → no write).
        // Use a smaller follow-up amount to stay within the per-(wallet, day) EV cap.
        vm.prank(actor);
        sdgnrs.burn(MIN_BURN_AMOUNT);
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD), "sentinel: post second-burn-same-day must remain == dayD");

        // Advance + resolve dayD — sentinel clears to 0 per the `if (pendingResolveDay ==
        // dayToResolve) pendingResolveDay = 0;` line at sStonk:665.
        _advanceWallDay();
        _resolveDay(dayD, 100, dayD);
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "sentinel: post-resolve must clear sentinel to 0");

        // First burn of a NEW day (dayD + 1, since we _advanceWallDay'd above) — sentinel
        // re-stamps to the new currentDayView.
        uint32 dayD1 = game.currentDayView();
        assertEq(uint256(dayD1), uint256(dayD) + 1, "sentinel: precondition - wall day must have advanced");
        vm.prank(actor);
        sdgnrs.burn(amount);
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD1), "sentinel: first burn of new day must re-stamp sentinel to new dayD1");
    }
}
