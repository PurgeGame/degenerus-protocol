// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {SettleClaimableShortfallTester} from "../../contracts/test/SettleClaimableShortfallTester.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

/// @notice Local mirror of the coinflip player surface for vm.mockCall selectors. Mirrors the
///         interface in RedemptionEdgeCases.t.sol and RedemptionGas.t.sol; redeclared locally
///         so this file does not depend on the coinflip contract import.
interface IFlipCoinflipPlayerMock {
    function getCoinflipDayResult(uint32 day) external view returns (uint16 rewardPercent, bool win);
    function claimCoinflipsForRedemption(address player, uint256 amount) external returns (uint256 claimed);
}

/// @notice Selector mirror for the MODULE-side resolveRedemptionLootbox (the delegatecall target
///         inside the Game-side resolveRedemptionLootbox 5-ETH-chunk loop). Mocked to a no-op in
///         the REDEEM-08 repro so the lootbox materialization loop returns without seeded game
///         state, while the Game-side body (the audited claimable-debit site) runs for real.
interface IGameLootboxModuleRRL {
    function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external;
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

    /// @dev Mirrors `sDGNRS.MIN_BURN_AMOUNT` (private literal `1e18`).
    uint256 internal constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Mirrors `sDGNRS.MAX_DAILY_REDEMPTION_EV` (private literal `160 ether`).
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

    /// @dev Storage slot of the `pendingByDay` mapping. v47: shifted from 11 to 10 because the
    ///      `pendingRedemptionFlip` (internal uint256) at slot 10 was removed (FLIP settled at
    ///      submit). Embedded inline so the test file is self-contained.
    /// @dev POST RT-PACKING-12: scalars packed into slot 0, mappings shifted down (pendingByDay 10->7).
    uint256 internal constant SLOT_PENDING_BY_DAY = 7;

    /// @dev Storage slot of the outer `pendingRedemptions` mapping (composite key:
    ///      mapping(address => mapping(uint32 => PendingRedemption))). POST RT-PACKING-12: 7->5.
    uint256 internal constant SLOT_PENDING_REDEMPTIONS = 5;

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

        // Fund game with 100 ETH backing + credit sDGNRS's claimable balance so proportional
        // payout math has nonzero totalMoney. Slot 7 = balancesPacked mapping (v61 PACK fold),
        // claimable in the LOW 128 bits; slot 1 upper 128 bits = claimablePool. Both writes
        // mirror RedemptionGas.t.sol. The low-half write preserves the afking high half.
        vm.deal(address(game), 100 ether);
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packedVal = uint256(vm.load(address(game), claimableSlot));
        packedVal = (packedVal & (type(uint256).max << 128)) | uint128(uint256(100 ether));
        vm.store(address(game), claimableSlot, bytes32(packedVal));
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
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerA, ACTOR_FUNDING);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerB, ACTOR_FUNDING);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerC, ACTOR_FUNDING);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, playerD, ACTOR_FUNDING);
        vm.stopPrank();

        // Mock coinflip player surface so claim path takes the full-payout branch (precedent
        // from RedemptionGas.t.sol :96-109). Without these mocks, claim hits the partial-claim
        // branch which preserves the slot — breaks the delete-at-full-claim assertion in
        // testFuzz_ClaimReadsCorrectDay.
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IFlipCoinflipPlayerMock.getCoinflipDayResult.selector),
            abi.encode(uint16(100), true)
        );
        vm.mockCall(
            address(coinflip),
            abi.encodeWithSelector(IFlipCoinflipPlayerMock.claimCoinflipsForRedemption.selector),
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
    function _resolveDay(uint32 dayToResolve, uint16 roll) internal {
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayToResolve));
    }

    /// @dev Write day `day`'s REAL coinflip result into Coinflip storage so the redemption
    ///      claim's contingency leg reads it through the production getCoinflipDayResult(uint24) ->
    ///      _dayResult path (no mockCall shim — this also exercises the real coinflipDayResultPacked
    ///      packing: slot 1, 32 days/slot, 8-bit lanes; win -> reward byte 50..156, loss -> 1).
    ///      Self-validating against the live getter. The full processCoinflipPayouts -> resolve
    ///      ordering is exercised separately by the RedemptionAccounting / RedemptionInvariants suites.
    function _setRealDayResult(uint24 day, uint8 rewardByte) internal {
        bytes32 slot = keccak256(abi.encode(uint256(day >> 5), uint256(1)));
        uint256 shift = (uint256(day) & 31) * 8;
        uint256 w = uint256(vm.load(address(coinflip), slot));
        w = (w & ~(uint256(0xFF) << shift)) | (uint256(rewardByte) << shift);
        vm.store(address(coinflip), slot, bytes32(w));
        (uint16 rp, bool win) = coinflip.getCoinflipDayResult(day);
        require(rp == rewardByte && win == (rewardByte >= 50), "setRealDayResult: lane mismatch");
    }

    /// @dev Set `_pendingResolveDay` (slot 0, lane [224:247]) via a masked store so the packed
    ///      `_totalSupply` / `_pendingRedemptionEthValue` lanes survive (POST RT-PACKING-12).
    function _storePendingResolveDay(uint24 dayD) internal {
        uint256 slot0 = uint256(vm.load(address(sdgnrs), bytes32(uint256(0))));
        slot0 = (slot0 & ~(uint256(0xffffff) << 224)) | (uint256(dayD) << 224);
        vm.store(address(sdgnrs), bytes32(uint256(0)), bytes32(slot0));
    }

    /// @dev Read packed `pendingByDay[day]` slot and unpack the 3×uint64 fields per the v47 layout
    ///      defined in `sDGNRS.DayPending`. v47: per-day flipBase removed (FLIP
    ///      settled at submit) — `{ethBase (0-63), supplySnapshot (64-127), burned (128-191)}`.
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

    /// @dev Pack a 3×uint64 DayPending into a single 256-bit word (test-side mirror of the v47
    ///      sStonk layout). Used by tests that seed a pool via vm.store.
    function _packPendingByDay(
        uint64 ethBase,
        uint64 supplySnapshot,
        uint64 burned
    ) internal pure returns (uint256) {
        return uint256(ethBase)
            | (uint256(supplySnapshot) << 64)
            | (uint256(burned) << 128);
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
    //   test_GamblingBurnRevertsBeforeDailyRng (v62 redemption-zero-seed gate)
    // =====================================================================

    /// @notice Pins the `BurnsBlockedBeforeDailyRng` admission gate (the post-v62 redemption
    ///         pre-draw guard in `sDGNRS._submitGamblingClaimFrom`): a gambling burn
    ///         submitted before the current day's VRF word is recorded must revert. Every other
    ///         test in this suite calls `_primeCurrentDayRng()` first, so removing the gate would
    ///         otherwise go undetected — the lootbox leg would then read a zero, fully-predictable
    ///         `rngWordForDay(day + 1)`. Reinjecting the pre-gate code flips this test to FAIL.
    function test_GamblingBurnRevertsBeforeDailyRng() public {
        // No _primeCurrentDayRng(): the current day's VRF word is unset at deploy-time state.
        assertEq(
            game.rngWordForDay(uint24(game.currentDayView())),
            0,
            "precondition: current day's RNG word must be unprimed (pre-draw window)"
        );
        // Valid gambling burn (>= MIN_BURN_AMOUNT, <= funding, well under the 160-ETH EV cap):
        // the only admission failure it can hit is the pre-draw gate.
        vm.prank(playerA);
        vm.expectRevert(sDGNRS.BurnsBlockedBeforeDailyRng.selector);
        sdgnrs.burn(FUZZ_MIN_AMOUNT);
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
        // at deploy-time state). Prime the current view day's RNG to satisfy the burn-admission gate.
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(amount);

        // Positive assertion: dayPre slot populated. `burned` is the always-reliable
        // populated-indicator (≥1 whole token via ceiling-divide); `ethBase > 0` under
        // FUZZ_MIN_AMOUNT lower bound; `supplySnapshot > 0` via lazy-init (SPEC-05).
        (uint64 ePost, uint64 sPost, uint64 bnPost) = _readPendingByDay(dayPre);
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

    /// @notice resolveRedemptionPeriod(roll, dayToResolve) writes exactly to
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
        uint16 rollSeed
    ) public {
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        uint16 roll = uint16(bound(uint256(rollSeed), 25, 175));
        // v47: resolveRedemptionPeriod is now 2-arg (roll, dayToResolve); the flipDay param and
        // the RedemptionPeriod.flipDay field were removed.

        // Step 1: burn on day D_burn so the resolver has a non-empty pool to act on (otherwise
        // resolveRedemptionPeriod early-returns at the `if (ethBase == 0)` guard — no state
        // mutation, the per-day write would never fire).
        uint32 dayBurn = game.currentDayView();
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(amount);

        // Verify pool populated
        (, , uint64 bnPreResolve) = _readPendingByDay(dayBurn);
        assertGt(uint256(bnPreResolve), 0, "resolve: precondition - pool must be populated");

        // Snapshot redemptionPeriods at dayBurn - 1 and dayBurn + 1 (must be byte-identical
        // pre/post since the resolver only writes [dayBurn]).
        uint32 dayLow = dayBurn > 0 ? dayBurn - 1 : 0;
        uint32 dayHigh = dayBurn + 1;
        (uint16 rollLowPre) = sdgnrs.redemptionPeriods(uint24(dayLow));
        (uint16 rollHighPre) = sdgnrs.redemptionPeriods(uint24(dayHigh));

        // Step 2: advance wall day so we're no longer on dayBurn — production semantics
        // (AdvanceModule resolves the prior day after the wall clock has crossed the boundary).
        _advanceWallDay();

        // Step 3: resolve dayBurn
        _resolveDay(dayBurn, roll);

        // Positive assertion: redemptionPeriods[dayBurn].roll == roll
        (uint16 rollPost) = sdgnrs.redemptionPeriods(uint24(dayBurn));
        assertEq(uint256(rollPost), uint256(roll), "resolve: redemptionPeriods[dayBurn].roll mismatch");

        // Negative assertion: adjacent days byte-identical pre/post
        (uint16 rollLowPost) = sdgnrs.redemptionPeriods(uint24(dayLow));
        (uint16 rollHighPost) = sdgnrs.redemptionPeriods(uint24(dayHigh));
        assertEq(uint256(rollLowPost), uint256(rollLowPre), "resolve: dayBurn-1.roll mutated");
        assertEq(uint256(rollHighPost), uint256(rollHighPre), "resolve: dayBurn+1.roll mutated");

        // pendingByDay[dayBurn] fully zeroed per SPEC-04 (c) delete-at-resolve
        (uint64 ePost, uint64 sPost, uint64 bnPost) = _readPendingByDay(dayBurn);
        assertEq(uint256(ePost), 0, "resolve: delete-at-resolve must zero ethBase");
        assertEq(uint256(sPost), 0, "resolve: delete-at-resolve must zero supplySnapshot");
        assertEq(uint256(bnPost), 0, "resolve: delete-at-resolve must zero burned");

        // Sentinel cleared per D-305-SENTINEL-01
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "resolve: sentinel must clear when pendingResolveDay == dayToResolve");
    }

    // =====================================================================
    //         testFuzz_ClaimReadsCorrectDay (ROADMAP-canonical)
    // =====================================================================

    /// @notice claimRedemption(player, day) reads the (player, day) composite-key slot — not
    ///         (player, day ± 1) — credits the correct rolled amount, and clears the slot on
    ///         full-claim path. Adjacent days' claim slots are byte-identical pre/post.
    /// @dev Tests `claimRedemption` in isolation. Anchors: SPEC-02 (composite key), SPEC-04 (d)
    ///      (delete-on-full-claim). The expected direct credit (into the player's game claimable;
    ///      live game pushes nothing at the claimant) is `(claim.ethValueOwed * roll / 100) / 2`
    ///      (50% direct, 50% routed to lootbox under live game). With gwei-aligned ethValueOwed
    ///      (D-305-GWEI-SNAP-01) and roll ∈ [25, 175], the arithmetic `× roll / 100` is exact
    ///      since gcd(1e9, 100) = 100. The 50/50 split is integer division; if totalRolledEth is
    ///      odd-wei, the split would skew 1 wei, but gwei-aligned values × any roll are always
    ///      even multiples of 100, so totalRolledEth is always divisible by 2 — ethDirect ==
    ///      totalRolledEth / 2 exactly.
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
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(amount);

        // Step 2: advance + resolve dayBurn with the deterministic roll
        _advanceWallDay();
        _resolveDay(dayBurn, roll);

        // Capture pre-claim state: actor's claim slot at dayBurn + adjacent slots at dayBurn-1
        // and dayBurn+1 (must be byte-identical pre/post since claim only touches [actor][dayBurn]).
        // Only ethValueOwed is needed for the payout-equality assertion; the slot is asserted
        // cleared post-claim via a fresh read.
        (uint96 evBurnPre, , ) = sdgnrs.pendingRedemptions(actor, uint24(dayBurn));
        uint32 dayLow = dayBurn > 0 ? dayBurn - 1 : 0;
        uint32 dayHigh = dayBurn + 1;
        (uint96 evLowPre, uint16 asLowPre, ) =
            sdgnrs.pendingRedemptions(actor, uint24(dayLow));
        (uint96 evHighPre, uint16 asHighPre, ) =
            sdgnrs.pendingRedemptions(actor, uint24(dayHigh));

        // Pre-burn slot must be populated for the test to be meaningful.
        assertGt(uint256(evBurnPre), 0, "claim: precondition - claim slot must populate post-burn");

        // Compute expected ETH delivered to the player.
        // totalRolledEth = (ethValueOwed * roll) / 100  — gwei-aligned + gcd(1e9, 100)=100 → exact
        // ethDirect = totalRolledEth / 2 (live game; gameOver path would deliver totalRolledEth)
        uint256 expectedTotalRolledEth = (uint256(evBurnPre) * uint256(roll)) / 100;
        uint256 expectedEthDirect = expectedTotalRolledEth / 2;

        // Step 3: claim — capture the player's game-claimable delta (live game routes the
        // direct half into game claimable; nothing is pushed at the claimant's wallet).
        uint256 ethBefore = actor.balance;
        uint256 claimableBefore = game.claimableWinningsOf(actor);
        vm.prank(actor);
        sdgnrs.claimRedemption(actor, uint24(dayBurn));

        // Positive: credit matches expected EXACTLY (D-305-GWEI-SNAP-01 zero-drift)
        assertEq(actor.balance - ethBefore, 0, "claim: live-game claim must not push ETH at the claimant");
        assertEq(
            game.claimableWinningsOf(actor) - claimableBefore,
            expectedEthDirect,
            "claim: game claimable credited != expected (ethValueOwed * roll / 100 / 2)"
        );

        // Slot cleared on claim (v47 claim is ETH-only; flipOwed field removed).
        (uint96 evBurnPost, , ) = sdgnrs.pendingRedemptions(actor, uint24(dayBurn));
        assertEq(uint256(evBurnPost), 0, "claim: full-claim path must delete ethValueOwed");

        // Negative assertion: adjacent days' slots byte-identical
        (uint96 evLowPost, uint16 asLowPost, ) =
            sdgnrs.pendingRedemptions(actor, uint24(dayLow));
        (uint96 evHighPost, uint16 asHighPost, ) =
            sdgnrs.pendingRedemptions(actor, uint24(dayHigh));
        assertEq(uint256(evLowPost), uint256(evLowPre), "claim: dayBurn-1 ethValueOwed mutated");
        assertEq(uint256(asLowPost), uint256(asLowPre), "claim: dayBurn-1 activityScore mutated");
        assertEq(uint256(evHighPost), uint256(evHighPre), "claim: dayBurn+1 ethValueOwed mutated");
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

        // Prime dayD's RNG once — all three same-day burns share the admission gate.
        _primeCurrentDayRng();

        // Burn 1 — capture per-burn delta
        uint96 evPre1 = 0; // claim slot is zero-init pre-burn-1
        vm.prank(actor);
        sdgnrs.burn(a1);
        (uint96 evPost1, , ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        uint256 delta1 = uint256(evPost1) - uint256(evPre1);

        // Burn 2 — capture per-burn delta
        vm.prank(actor);
        sdgnrs.burn(a2);
        (uint96 evPost2, , ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        uint256 delta2 = uint256(evPost2) - uint256(evPost1);

        // Burn 3 — capture per-burn delta
        vm.prank(actor);
        sdgnrs.burn(a3);
        (uint96 evPost3, , ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        uint256 delta3 = uint256(evPost3) - uint256(evPost2);

        // Positive assertion: aggregate equals sum of deltas (strict assertEq — gwei alignment)
        uint256 sumDeltas = delta1 + delta2 + delta3;
        assertEq(uint256(evPost3), sumDeltas, "aggregate: claim.ethValueOwed != sum of per-burn deltas");

        // Pool↔claim single-burner exact equality (D-305-GWEI-SNAP-01: pool.ethBase × 1e9 ==
        // sum-of-claims). Since this is a single burner, sum-of-claims == claim.ethValueOwed.
        (uint64 ethBase, , uint64 burned) = _readPendingByDay(dayD);
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
        // v47 DayPending packing: (ethBase, supplySnapshot, burned) — flipBase field removed.
        uint256 packed = _packPendingByDay(0, 1000, 0);
        bytes32 slotPbD = keccak256(abi.encode(uint256(dayD), uint256(SLOT_PENDING_BY_DAY)));
        vm.store(address(sdgnrs), slotPbD, bytes32(packed));

        // Pre-stamp the sentinel so the INV-13 guard inside burn does NOT trip the
        // PriorDayUnresolved revert. The sentinel must equal currentDayView (= dayD) or 0; we
        // set it to dayD for parity with the burned-by-day pool's seed.
        _storePendingResolveDay(uint24(dayD));

        // Prime dayD's RNG so both the exact-cap burn and the over-cap burn pass the admission
        // gate and reach the supply-cap guard (the over-cap case must revert Insufficient, not
        // the gate).
        _primeCurrentDayRng();

        // Verify seed visible
        (, uint64 sBefore, uint64 bnBefore) = _readPendingByDay(dayD);
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
        (, uint64 sAfter1, uint64 bnAfter1) = _readPendingByDay(dayD);
        assertEq(uint256(sAfter1), uint256(sBefore), "supplyCap: supplySnapshot NOT immutable post burn-1 (SPEC-05)");
        assertEq(uint256(bnAfter1), 500, "supplyCap: burned must equal 500 whole tokens post exact-cap burn");

        // Negative sub-scenario: any subsequent burn tips over the cap. The minimum legal
        // amount under the protocol floor is MIN_BURN_AMOUNT (1 whole token); use a fuzzed
        // amount in [1e18, ACTOR_FUNDING / 100] to ensure all probe values would push burned ≥ 501.
        uint256 overCap = bound(secondBurnSeed, MIN_BURN_AMOUNT, ACTOR_FUNDING / 100);
        vm.prank(actor);
        vm.expectRevert(sDGNRS.Insufficient.selector);
        sdgnrs.burn(overCap);

        // Pool state byte-identical post failed burn
        (, uint64 sAfter2, uint64 bnAfter2) = _readPendingByDay(dayD);
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

        // Pack PendingRedemption: bits 0-95 = ethValueOwed, 96-191 = flipOwed, 192-207 =
        // activityScore. Seed ethValueOwed = MAX_DAILY_REDEMPTION_EV (gwei-aligned since 160e18
        // is a multiple of 1e9); activityScore = 1 (treat as set so the lazy-init branch in
        // _submitGamblingClaimFrom does NOT overwrite it).
        // v47 PendingRedemption packing: ethValueOwed (bits 0-95) | activityScore (bits 96-111).
        // The former flipOwed field (old bits 96-191) was removed, so activityScore is at bit 96.
        uint256 packed = uint256(MAX_DAILY_REDEMPTION_EV) | (uint256(1) << 96);
        bytes32 outerSlot = keccak256(abi.encode(actor, uint256(SLOT_PENDING_REDEMPTIONS)));
        bytes32 claimSlot = keccak256(abi.encode(uint256(dayD), outerSlot));
        vm.store(address(sdgnrs), claimSlot, bytes32(packed));

        // Verify seed visible
        (uint96 evSeed, uint16 asSeed, ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evSeed), MAX_DAILY_REDEMPTION_EV, "evCap: pre-seed ethValueOwed mismatch");
        assertEq(uint256(asSeed), 1, "evCap: pre-seed activityScore mismatch");

        // Pre-stamp sentinel so INV-13 guard does NOT trip
        _storePendingResolveDay(uint24(dayD));

        // Prime dayD's RNG so the burn passes the admission gate and reaches the EV-cap check
        // (the burn must revert ExceedsDailyRedemptionCap, not BurnsBlockedBeforeDailyRng).
        _primeCurrentDayRng();

        // Any burn that produces ethValueOwed > 0 (post gwei-snap) must revert. FUZZ_MIN_AMOUNT
        // (100 ether) yields ethValueOwed ~12.5 gwei post-snap > 0 → cap check trips. Fuzz the
        // amount in [FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100] to assert the revert across a range.
        uint256 amount = bound(amountSeed, FUZZ_MIN_AMOUNT, ACTOR_FUNDING / 100);
        vm.prank(actor);
        vm.expectRevert(sDGNRS.ExceedsDailyRedemptionCap.selector);
        sdgnrs.burn(amount);

        // Negative assertion: claim slot byte-identical post failed burn
        (uint96 evPost, uint16 asPost, ) = sdgnrs.pendingRedemptions(actor, uint24(dayD));
        assertEq(uint256(evPost), MAX_DAILY_REDEMPTION_EV, "evCap: ethValueOwed mutated by failed burn");
        // v47: flipOwed field removed — nothing to byte-compare.
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
        uint32 day
    ) public {
        vm.assume(caller != address(game));
        vm.assume(caller != address(0));

        // Pre-state snapshots (must be byte-identical pre/post revert).
        // v47: resolveRedemptionPeriod is 2-arg (roll, dayToResolve); RedemptionPeriod.flipDay removed.
        (uint16 rollPre) = sdgnrs.redemptionPeriods(uint24(day));
        uint256 cumulativeEthPre = sdgnrs.pendingRedemptionEthValue();
        uint32 sentinelPre = sdgnrs.pendingResolveDay();
        // pendingByDay[day] packed slot snapshot
        bytes32 pbdSlot = keccak256(abi.encode(uint256(day), uint256(SLOT_PENDING_BY_DAY)));
        uint256 pbdRawPre = uint256(vm.load(address(sdgnrs), pbdSlot));

        // Reverting call
        vm.prank(caller);
        vm.expectRevert(sDGNRS.Unauthorized.selector);
        sdgnrs.resolveRedemptionPeriod(roll, uint24(day));

        // Negative assertions: no state change.
        (uint16 rollPost) = sdgnrs.redemptionPeriods(uint24(day));
        uint256 cumulativeEthPost = sdgnrs.pendingRedemptionEthValue();
        uint32 sentinelPost = sdgnrs.pendingResolveDay();
        uint256 pbdRawPost = uint256(vm.load(address(sdgnrs), pbdSlot));

        assertEq(uint256(rollPost), uint256(rollPre), "resolveACL: redemptionPeriods.roll mutated by reverting call");
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

        // First burn of dayD — sentinel stamps to dayD. Prime dayD's RNG (admission gate); the
        // game-side RNG word does not touch the sStonk sentinel, so the fresh-state precondition
        // above and the stamp assertion below remain valid.
        _primeCurrentDayRng();
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
        _resolveDay(dayD, 100);
        assertEq(uint256(sdgnrs.pendingResolveDay()), 0, "sentinel: post-resolve must clear sentinel to 0");

        // First burn of a NEW day (dayD + 1, since we _advanceWallDay'd above) — sentinel
        // re-stamps to the new currentDayView.
        uint32 dayD1 = game.currentDayView();
        assertEq(uint256(dayD1), uint256(dayD) + 1, "sentinel: precondition - wall day must have advanced");
        // New view day after the warp — prime dayD1's RNG to pass the admission gate.
        _primeCurrentDayRng();
        vm.prank(actor);
        sdgnrs.burn(amount);
        assertEq(uint256(sdgnrs.pendingResolveDay()), uint256(dayD1), "sentinel: first burn of new day must re-stamp sentinel to new dayD1");
    }

    // =====================================================================
    //   REDEEM-08 REPRO-FIRST: two-claimant same-day ETH underflow
    // =====================================================================
    //
    // PRE-FIX DEFECT (Defect A, fb29ed51^:DegenerusGame.sol:1802-1804): the now-deleted
    //   uint256 claimable = claimableWinnings[SDGNRS];
    //   unchecked { claimableWinnings[SDGNRS] = claimable - amount; }
    //   claimablePool -= uint128(amount);
    // block lived inside resolveRedemptionLootbox and ran at CLAIM time. A second same-day
    // claimant (or an AfKing SUB-09 daily drain) whose lootbox `amount` exceeded the remaining
    // claimableWinnings[SDGNRS] underflowed the UNCHECKED subtraction → claimableWinnings[SDGNRS]
    // wrapped toward 2^256 (and claimablePool toward 2^128).
    //
    // POST-FIX (v47): resolveRedemptionLootbox is `external payable`, the ETH PHYSICALLY arrives as
    // msg.value, and the function does NO claimableWinnings[SDGNRS] debit at all. The only surviving
    // claimable[SDGNRS] debit moved to SUBMIT time in the CHECKED pullRedemptionReserve (segregation
    // of the MAX 175% out of claimable into the sDGNRS balance). Solidity-0.8 reverts fail-closed on
    // shortfall, so the wrap can never form.
    //
    // REPRO MECHANISM (cross-tree): _reproDriveSecondClaimantLootbox() drives the exact wrap site —
    // resolveRedemptionLootbox called twice (as SDGNRS), the second time with amount > remaining
    // claimable. Run as-is against the post-fix tree it PASSES (no debit → claimable never wraps);
    // re-introducing ONLY the deleted unchecked block (the documented fallback mechanism in a scratch
    // worktree checkout of this same contract) makes the second call wrap and the assertion FAIL.
    // The 323-03 SUMMARY records the captured pre-fix failure output.

    /// @dev Read claimable[SDGNRS] = low 128 bits of balancesPacked[SDGNRS] (slot 7, v61 PACK
    ///      fold) via vm.load. Same slot the setUp seeds. Masking to the low half lets the
    ///      post-fix invariant assert the claimable half never wrapped toward 2^128 independent
    ///      of the afking high half.
    function _claimableSdgnrs() internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        return uint128(uint256(vm.load(address(game), slot)));
    }

    /// @dev Drive the exact pre-fix wrap site: call resolveRedemptionLootbox twice as SDGNRS. The
    ///      first call consumes (pre-fix) all but a sliver of claimable; the second requests MORE
    ///      ETH than the remaining claimable. Pre-fix that second unchecked `claimable - amount`
    ///      wraps; post-fix there is no claimable debit (msg.value carries the ETH in), so claimable
    ///      is untouched by the call and can never wrap.
    /// @param seedClaimable claimableWinnings[SDGNRS] to seed before the two calls.
    /// @param firstAmount   ETH the first claimant's lootbox resolves (≈ drains claimable pre-fix).
    /// @param secondAmount  ETH the second claimant's lootbox resolves (> remaining claimable).
    function _reproDriveSecondClaimantLootbox(
        uint256 seedClaimable,
        uint256 firstAmount,
        uint256 secondAmount
    ) internal {
        // Seed claimableWinnings[SDGNRS] to sDGNRS's (small) slice, but claimablePool to a LARGE
        // GLOBAL pool. This mirrors the real Defect-A precondition: the global pool still holds OTHER
        // players' funds (so the pre-fix CHECKED `claimablePool -= amount` does NOT revert) while
        // sDGNRS's own claimable slice is small (so the pre-fix UNCHECKED `claimableWinnings[SDGNRS]
        // -= amount` wraps on the second claimant). Decoupling the two is what exposes the wrap —
        // a single shared value would revert on claimablePool before claimableWinnings could wrap.
        // slot 7 = balancesPacked (v61); seed the claimable LOW half, preserve the afking high half.
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packed = uint256(vm.load(address(game), claimableSlot));
        packed = (packed & (type(uint256).max << 128)) | uint128(seedClaimable);
        vm.store(address(game), claimableSlot, bytes32(packed));
        uint256 globalPool = 1000 ether; // global claimablePool has ample headroom (other players)
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1 = (slot1 & type(uint128).max) | (uint256(uint128(globalPool)) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1));

        // Give the game enough physical ETH that pre-fix (which keeps ETH in-game and only
        // reassigns claimable) and post-fix (msg.value carries ETH in) both have liquidity. The
        // post-fix payable path requires msg.value == amount, so fund sDGNRS to forward it.
        vm.deal(address(game), 1000 ether);
        vm.deal(address(sdgnrs), 1000 ether);

        // The setUp mocks the WHOLE game.resolveRedemptionLootbox to a no-op (out-of-scope lootbox
        // internals); clear it so the REAL Game-side function runs (so the deleted-debit site IS
        // exercised pre-fix, and proven absent post-fix). Then mock only the MODULE-side
        // resolveRedemptionLootbox (the delegatecall target) to a no-op so the 5-ETH-chunk lootbox
        // materialization loop returns cleanly without needing seeded game lootbox state. The Game-
        // side body (the pre-fix unchecked claimable debit / the post-fix msg.value credit) runs in
        // full either way — the debit precedes the loop.
        vm.clearMockedCalls();
        vm.mockCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(IGameLootboxModuleRRL.resolveRedemptionLootbox.selector),
            abi.encode()
        );

        // Both calls are pranked as SDGNRS (the only authorized caller).
        vm.prank(address(sdgnrs));
        game.resolveRedemptionLootbox{value: firstAmount}(playerA, firstAmount, uint256(0xABCD), 1);

        vm.prank(address(sdgnrs));
        game.resolveRedemptionLootbox{value: secondAmount}(playerB, secondAmount, uint256(0x1234), 1);
    }

    /// @notice REDEEM-08 repro-first headline: two same-day claimants cannot wrap
    ///         claimableWinnings[SDGNRS] toward 2^256. PASSES post-fix (no claim-time claimable
    ///         debit — ETH arrives as msg.value); FAILS pre-fix (the deleted unchecked debit wraps
    ///         on the second claimant). Evidence of the pre-fix failure is recorded in the SUMMARY.
    /// @dev seedClaimable = 1 ether; first claimant resolves ~1 ether (drains pre-fix claimable to
    ///      ~0), second claimant resolves 3 ether (> remaining). Pre-fix: claimable - 3 ether wraps
    ///      toward 2^256. Post-fix: claimable is NEVER touched by resolveRedemptionLootbox, so it
    ///      stays at the seeded 1 ether — far below type(uint96).max. The tight post-fix bound
    ///      (< type(uint96).max ≈ 7.9e28 wei ≈ 7.9e10 ETH) catches any wrap (a wrapped value is
    ///      ~1.16e77).
    function testReproTwoClaimantSameDayNoUnderflow() public {
        uint256 seedClaimable = 1 ether;
        uint256 firstAmount = 1 ether;   // drains pre-fix claimable to exactly 0
        uint256 secondAmount = 3 ether;  // > remaining (0) → pre-fix unchecked wrap

        _reproDriveSecondClaimantLootbox(seedClaimable, firstAmount, secondAmount);

        // POST-FIX INVARIANT: resolveRedemptionLootbox does NO claimable debit, so the raw word
        // is untouched and nowhere near 2^256. Pre-fix this wraps and the assertion trips.
        uint256 claimableAfter = _claimableSdgnrs();
        assertLt(
            claimableAfter,
            uint256(type(uint96).max),
            "REDEEM-08: claimableWinnings[SDGNRS] wrapped toward 2^256 (pre-fix unchecked debit underflow)"
        );

        // claimablePool likewise never wraps toward 2^128 (post-fix: resolveRedemptionLootbox does
        // not touch claimablePool; it only credits futurePrizePool from msg.value).
        assertLt(
            game.claimablePoolView(),
            uint256(type(uint96).max),
            "REDEEM-08: claimablePool wrapped toward 2^128 (pre-fix unchecked debit underflow)"
        );

        // Post-fix concrete equality: the seeded claimable is untouched (no claim-time debit).
        assertEq(
            claimableAfter,
            seedClaimable,
            "REDEEM-08: post-fix resolveRedemptionLootbox must NOT debit claimableWinnings[SDGNRS]"
        );
    }

    /// @notice REDEEM-08 full-flow two-claimant proof: two distinct redeemers submit gambling-burn
    ///         claims on the SAME day, the day resolves, both claim. The post-fix path segregates
    ///         each redeemer's MAX(175%) at SUBMIT via the CHECKED pullRedemptionReserve, so the
    ///         claim-time path holds no unchecked claimable debit — claimableWinnings[SDGNRS] can
    ///         only ever have decreased by the two CHECKED submit pulls and never wraps.
    /// @dev claimablePool == claimableWinnings[SDGNRS] stays balanced through both submits. Both
    ///      submits draw down the shared claimable; the second submit's CHECKED pull reverts
    ///      fail-closed if claimable is short (proven separately in the drain variant). Here claimable
    ///      is large enough to cover both, so both submits succeed and claimable never wraps.
    function testReproTwoClaimantFullFlowNoUnderflow() public {
        // Seed a generous claimable so both submits' MAX(175%) pulls succeed.
        // slot 7 = balancesPacked (v61); seed the claimable LOW half, preserve the afking high half.
        uint256 seedClaimable = 100 ether;
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packed = uint256(vm.load(address(game), claimableSlot));
        packed = (packed & (type(uint256).max << 128)) | uint128(seedClaimable);
        vm.store(address(game), claimableSlot, bytes32(packed));
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1 = (slot1 & type(uint128).max) | (uint256(uint128(seedClaimable)) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1));
        vm.deal(address(game), 100 ether);

        uint32 dayBurn = game.currentDayView();
        uint256 burnAmount = 1000 ether;

        // Prime dayBurn's RNG once — both same-day submits share the admission gate.
        _primeCurrentDayRng();

        // Both redeemers submit on the SAME day.
        vm.prank(playerA);
        sdgnrs.burn(burnAmount);
        vm.prank(playerB);
        sdgnrs.burn(burnAmount);

        // Both submit-time CHECKED pulls succeeded → claimable decreased, never wrapped.
        uint256 claimableAfterSubmits = _claimableSdgnrs();
        assertLt(
            claimableAfterSubmits,
            uint256(type(uint96).max),
            "REDEEM-08 full-flow: claimableWinnings[SDGNRS] wrapped during two same-day submits"
        );
        // claimablePool == claimableWinnings[SDGNRS] balanced (sole holder is sDGNRS in this harness).
        assertEq(
            game.claimablePoolView(),
            claimableAfterSubmits,
            "REDEEM-08 full-flow: claimablePool diverged from claimableWinnings[SDGNRS]"
        );

        // Resolve the shared day, then both claim. The REDEEM-08 safety property is that a claim never
        // DEBITS claimableWinnings[SDGNRS] (which could underflow/wrap). With this harness's 1-trillion
        // supply the redemption value is dust (well under the 0.02 ETH lootbox floor), so each claim
        // drops the lootbox half and forfeits it BACK to claimable[SDGNRS] — a credit, never a debit.
        _advanceWallDay();
        _resolveDay(dayBurn, 100);

        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));
        vm.prank(playerB);
        sdgnrs.claimRedemption(playerB, uint24(dayBurn));

        uint256 claimableAfterClaims = _claimableSdgnrs();
        assertGe(
            claimableAfterClaims,
            claimableAfterSubmits,
            "REDEEM-08 full-flow: claim-time path must never debit claimableWinnings[SDGNRS]"
        );
        assertLt(
            claimableAfterClaims,
            uint256(type(uint96).max),
            "REDEEM-08 full-flow: claimableWinnings[SDGNRS] wrapped during two same-day claims"
        );
    }

    /// @notice REDEEM-08 C5 fail-closed drain variant (AfKing SUB-09): if claimableWinnings[SDGNRS]
    ///         is drained below the MAX(175%) the submit needs, the CHECKED pullRedemptionReserve
    ///         reverts — fail-closed — rather than leaving a virtual reserve a later drain could
    ///         underflow. Once claimable recovers, the same burn succeeds.
    /// @dev The realistic drain: by the time the submit computes its MAX(175%) increment, the
    ///      AfKing SUB-09 self-sub has already pulled claimableWinnings[SDGNRS] down (between days).
    ///      The burn's `ethValueOwed` is proportional to `totalMoney = sDGNRS.balance + stETH +
    ///      claimable - pendingRedemptionEthValue`; to reach a positive `ethValueOwed` (hence a
    ///      positive `maxIncrement` to segregate) WHILE claimable is short, fund sDGNRS's own ETH
    ///      balance (drives totalMoney up) but starve claimableWinnings[SDGNRS] (the segregation
    ///      source). The CHECKED debit in pullRedemptionReserve then underflows → reverts → the whole
    ///      burn reverts (the redeemer's sDGNRS is NOT burned). After claimable recovers, the burn lands.
    function testReproSubmitFailClosedOnClaimableShortfall() public {
        uint32 dayBurn = game.currentDayView();
        uint256 burnAmount = 1000 ether;

        // Drive totalMoney up via sDGNRS's own ETH balance (so ethValueOwed > 0 → maxIncrement > 0),
        // but STARVE claimable[SDGNRS] (the segregation source the CHECKED pull draws from).
        // slot 7 = balancesPacked (v61); starve the claimable LOW half, preserve the afking high half.
        vm.deal(address(sdgnrs), 100 ether);
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packed = uint256(vm.load(address(game), claimableSlot));
        packed = (packed & (type(uint256).max << 128)) | uint128(uint256(1));
        vm.store(address(game), claimableSlot, bytes32(packed));
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1 = (slot1 & type(uint128).max) | (uint256(1) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1));

        uint256 supplyBefore = sdgnrs.totalSupply();
        uint256 balBefore = sdgnrs.balanceOf(playerA);

        // Prime dayBurn's RNG so the burn passes the admission gate and the revert it hits is the
        // intended shortfall fail-closed (CHECKED pullRedemptionReserve underflow), not the gate.
        // Both this fail-closed burn and the post-recovery burn below land on dayBurn → one prime.
        _primeCurrentDayRng();

        // Fail-closed: the burn reverts because the CHECKED pull can't segregate the MAX.
        vm.prank(playerA);
        vm.expectRevert();
        sdgnrs.burn(burnAmount);

        // No sDGNRS was burned (fail-closed: state rolled back), claimable did NOT wrap.
        assertEq(sdgnrs.totalSupply(), supplyBefore, "drain: supply changed on a fail-closed burn");
        assertEq(sdgnrs.balanceOf(playerA), balBefore, "drain: balance changed on a fail-closed burn");
        assertLt(_claimableSdgnrs(), uint256(type(uint96).max), "drain: claimable wrapped on shortfall");

        // Recover claimable (the AfKing drain reverses / the pool refills) → the burn now succeeds.
        // Refill the claimable LOW half of balancesPacked, preserving the afking high half.
        packed = uint256(vm.load(address(game), claimableSlot));
        packed = (packed & (type(uint256).max << 128)) | uint128(uint256(100 ether));
        vm.store(address(game), claimableSlot, bytes32(packed));
        slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1 = (slot1 & type(uint128).max) | (uint256(100 ether) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1));
        vm.deal(address(game), 100 ether);

        vm.prank(playerA);
        sdgnrs.burn(burnAmount);

        // Burn landed: supply dropped, a claim slot exists for the day.
        assertLt(sdgnrs.totalSupply(), supplyBefore, "drain: burn did not land after claimable recovered");
        (uint96 ev, , ) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(ev), 0, "drain: claim slot not populated after recovery burn");
    }

    // =====================================================================
    //   REDEEM-08: FLIP-can't-block-ETH + R1/R3/R4 refinement coverage
    // =====================================================================

    /// @dev Fund sDGNRS's held FLIP balance via the GAME-gated mint (the post-seed-window
    ///      state: daily-claimed flip wins sit on its wallet as redemption backing).
    function _fundSdgnrsFlip(uint256 amount) internal {
        vm.prank(address(game));
        coin.mintForGame(ContractAddresses.SDGNRS, amount);
    }

    /// @dev Seed a generous claimable[SDGNRS] + claimablePool + game ETH so submit-time
    ///      MAX(175%) segregation pulls succeed. Reused by the Task-2 full-flow tests.
    ///      slot 7 = balancesPacked (v61); seed the claimable LOW half, preserve the afking high half.
    function _seedRedemptionBacking(uint256 amount) internal {
        bytes32 claimableSlot = keccak256(abi.encode(address(sdgnrs), uint256(7)));
        uint256 packed = uint256(vm.load(address(game), claimableSlot));
        packed = (packed & (type(uint256).max << 128)) | uint128(amount);
        vm.store(address(game), claimableSlot, bytes32(packed));
        uint256 slot1 = uint256(vm.load(address(game), bytes32(uint256(1))));
        slot1 = (slot1 & type(uint128).max) | (uint256(uint128(amount)) << 128);
        vm.store(address(game), bytes32(uint256(1)), bytes32(slot1));
        vm.deal(address(game), amount);
    }

    /// @notice REDEEM-08 FLIP-can't-block-ETH: the ETH leg of claimRedemption pays in full from
    ///         the segregated balance regardless of the redeemer's FLIP share. The redeemed FLIP
    ///         slice is removed from sDGNRS at submit and escrowed; the claim-time FLIP leg (a
    ///         contingent flip credit paid only on the resolving day's coinflip win) is independent of
    ///         the ETH/stETH legs and cannot stall them. The claim's ETH delivered equals the rolled
    ///         segregated amount, period.
    /// @dev Drives a full submit → resolve → claim with sDGNRS holding a large FLIP balance (so a
    ///      pre-fix FLIP-reserve apparatus would have had a fat FLIP leg to settle/stall on). The
    ///      direct credit (game claimable) is asserted to equal (claim.ethValueOwed * roll / 100) / 2
    ///      (the live-game 50% direct split — the 50% lootbox leg is routed via the setUp no-op
    ///      mock), independent of any FLIP.
    function testFlipCannotBlockEthLeg() public {
        _seedRedemptionBacking(100 ether);

        uint32 dayBurn = game.currentDayView();
        uint256 burnAmount = 1000 ether;
        uint16 roll = 100;

        // Fund sDGNRS with a large held FLIP balance (the post-seed-window state: claimed
        // flip wins sit on its wallet), so the redeemer's proportional FLIP share is
        // non-trivial — exactly the case a pre-fix FLIP-reserve leg could have stalled.
        // Submit settles it all at submit.
        _fundSdgnrsFlip(2_000_000 ether);
        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(burnAmount);

        (uint96 evOwed, , ) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(evOwed), 0, "flip-block: claim slot must populate post-burn");

        _advanceWallDay();
        _resolveDay(dayBurn, roll);

        uint256 expectedTotalRolled = (uint256(evOwed) * uint256(roll)) / 100;
        uint256 expectedEthDirect = expectedTotalRolled / 2; // live game: 50% direct, 50% lootbox

        uint256 claimableBefore = game.claimableWinningsOf(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));
        uint256 creditDelta = game.claimableWinningsOf(playerA) - claimableBefore;

        // ETH leg credits in full irrespective of FLIP — there is no FLIP leg to block it.
        assertEq(
            creditDelta,
            expectedEthDirect,
            "REDEEM-08: ETH leg did not credit full rolled/2 - FLIP must not be able to block ETH"
        );
        // Claim slot fully cleared (ETH-only full-claim path).
        (uint96 evAfter, , ) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertEq(uint256(evAfter), 0, "REDEEM-08: claim slot not cleared after ETH-only claim");
    }

    /// @dev Fund sDGNRS with enough held FLIP that a 1000-token burn escrows a nonzero WHOLE-token
    ///      slice. backing*amount/supply >= 1e18 needs backing >= supply/amount whole tokens; at the
    ///      ~1e12-token deploy supply with a 1000-token burn that is ~1e9 FLIP, so 1e12 FLIP
    ///      yields ~1000 whole-token escrow with comfortable headroom.
    uint256 internal constant SDGNRS_FLIP_FUND = 1_000_000_000_000 ether;

    /// @notice FLIP-04 (submit-time backing removal): the redeemed FLIP share is REMOVED from
    ///         sDGNRS's backing at submit (held burned → claimable consumed → carry decremented) and
    ///         escrowed WHOLE-token against (redeemer, day) — NOT credited to the redeemer. The
    ///         redeemer is paid only later, on a winning resolving-day (day+1) coinflip. So the
    ///         "spendable FLIP universe" DROPS by exactly the escrowed amount at submit: the slice
    ///         leaves sDGNRS now and re-enters as the redeemer's flip credit only on a win (else it
    ///         is forfeited, symmetric with the auto-rebuy carry zeroing for every holder on a loss).
    /// @dev Universe scalar = coin.totalSupply() + coinflipAmount(SDGNRS) + coinflipAmount(redeemer).
    ///      Pre-day-20 sDGNRS holds its backing as wallet FLIP, so withdrawRedeemedFlip burns the
    ///      whole escrow out of held → totalSupply drops by escrowWei; the redeemer's stake is
    ///      untouched at submit; the escrow is recorded in pendingRedemptions[redeemer][day].
    function testRedeemFlipRemovedFromBackingAtSubmit() public {
        _seedRedemptionBacking(100 ether);

        uint32 dayBurn = game.currentDayView();
        uint256 burnAmount = 1000 ether;
        address SDGNRS = ContractAddresses.SDGNRS;

        _fundSdgnrsFlip(SDGNRS_FLIP_FUND);

        uint256 universeBefore = coin.totalSupply()
            + coinflip.coinflipAmount(SDGNRS)
            + coinflip.coinflipAmount(playerA);
        uint256 redeemerStakeBefore = coinflip.coinflipAmount(playerA);

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(burnAmount);

        // The escrowed slice is recorded WHOLE-token against (redeemer, dayBurn).
        (, , uint96 escrowWhole) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(escrowWhole), 0, "FLIP-04: escrow not recorded (backing*amount/supply should be > 0)");
        uint256 escrowWei = uint256(escrowWhole) * 1e18;

        uint256 universeAfter = coin.totalSupply()
            + coinflip.coinflipAmount(SDGNRS)
            + coinflip.coinflipAmount(playerA);

        // The universe DROPS by exactly the escrowed amount at submit — the slice is removed from
        // sDGNRS's backing now, with nothing credited to the redeemer (paid later on a day+1 win).
        assertEq(
            universeBefore - universeAfter,
            escrowWei,
            "FLIP-04: submit must remove exactly the escrowed slice from the spendable universe"
        );

        // The redeemer is credited NOTHING at submit (contingent on the resolving flip).
        assertEq(
            coinflip.coinflipAmount(playerA),
            redeemerStakeBefore,
            "FLIP-04: redeemer must receive no flip credit at submit (paid only on a day+1 win)"
        );
    }

    /// @notice FLIP-04 win-path: on a WINNING resolving-day (day+1) coinflip, the escrowed
    ///         whole-token slice is minted to the redeemer as a flip credit at claim (and the slot
    ///         is cleared). The ETH leg is unaffected.
    function testRedeemFlipEscrowPaidOnDayPlus1Win() public {
        _seedRedemptionBacking(100 ether);
        uint32 dayBurn = game.currentDayView();
        _fundSdgnrsFlip(SDGNRS_FLIP_FUND);

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(1000 ether);
        (, , uint96 escrowWhole) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(escrowWhole), 0, "win: escrow must be recorded at submit");
        uint256 escrowWei = uint256(escrowWhole) * 1e18;

        _advanceWallDay();
        _resolveDay(dayBurn, 100);
        _setRealDayResult(uint24(dayBurn) + 1, 100); // resolving-day coinflip WON (real storage)

        uint256 redeemerStakeBefore = coinflip.coinflipAmount(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));

        // On a win the escrow earns the day+1 win multiplier (principal + principal*rewardPercent%),
        // the same payout a held backing slice earns; rewardPercent=100 here -> 2x. The minted credit
        // then rides the redeemer's own next flip.
        assertEq(
            coinflip.coinflipAmount(playerA) - redeemerStakeBefore,
            escrowWei * 2,
            "win: redeemer must receive escrow + day+1 win multiplier (2x at rewardPercent=100)"
        );
        // Slot fully cleared (ETH + FLIP).
        (uint96 evAfter, , uint96 escAfter) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertEq(uint256(evAfter), 0, "win: ethValueOwed not cleared");
        assertEq(uint256(escAfter), 0, "win: flipEscrow not cleared");
    }

    /// @notice Win-multiplier formula: on a winning resolving-day (day+1) coinflip the escrow pays
    ///         principal + principal*rewardPercent% — the identical payout a non-redeeming holder's
    ///         backing earns — not face. Pins the general formula at a non-trivial percent (78).
    function testRedeemFlipEscrowPaidWithDayPlus1WinMultiplier() public {
        _seedRedemptionBacking(100 ether);
        uint32 dayBurn = game.currentDayView();
        _fundSdgnrsFlip(SDGNRS_FLIP_FUND);

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(1000 ether);
        (, , uint96 escrowWhole) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(escrowWhole), 0, "mult: escrow must be recorded at submit");
        uint256 escrowWei = uint256(escrowWhole) * 1e18;

        _advanceWallDay();
        _resolveDay(dayBurn, 100);
        _setRealDayResult(uint24(dayBurn) + 1, 78); // resolving-day coinflip WON at rewardPercent 78

        uint256 redeemerStakeBefore = coinflip.coinflipAmount(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));

        // principal + principal*78/100 (computed the same way the contract does).
        uint256 expected = escrowWei + (escrowWei * 78) / 100;
        assertEq(
            coinflip.coinflipAmount(playerA) - redeemerStakeBefore,
            expected,
            "mult: redeemer must receive principal + principal*rewardPercent%"
        );
    }

    /// @notice FLIP-04 loss-path: on a LOSING resolving-day (day+1) coinflip, the escrowed slice
    ///         pays nothing — it was already removed from sDGNRS at submit, so the loss simply
    ///         forfeits it (the redeemer gets no flip credit), and the slot is cleared.
    function testRedeemFlipEscrowForfeitedOnDayPlus1Loss() public {
        _seedRedemptionBacking(100 ether);
        uint32 dayBurn = game.currentDayView();
        _fundSdgnrsFlip(SDGNRS_FLIP_FUND);

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(1000 ether);
        (, , uint96 escrowWhole) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertGt(uint256(escrowWhole), 0, "loss: escrow must be recorded at submit");

        _advanceWallDay();
        _resolveDay(dayBurn, 100);
        _setRealDayResult(uint24(dayBurn) + 1, 1); // resolving-day coinflip LOST (real storage)

        uint256 redeemerStakeBefore = coinflip.coinflipAmount(playerA);
        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));

        // Redeemer receives no FLIP flip credit on a losing resolving-day flip.
        assertEq(
            coinflip.coinflipAmount(playerA),
            redeemerStakeBefore,
            "loss: redeemer must receive no FLIP on a losing resolving-day coinflip"
        );
        (, , uint96 escAfter) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertEq(uint256(escAfter), 0, "loss: flipEscrow not cleared");
    }

    /// @notice REDEEM-08 R4 (resolveRedemptionPeriod 2-arg): the v47 2-arg signature
    ///         `(uint16 roll, uint32 dayToResolve)` resolves the period — writes
    ///         redemptionPeriods[day].roll and lowers pendingRedemptionEthValue MAX→rolled.
    /// @dev Asserts the AdvanceModule-shaped 2-arg call (the flipDay param + RedemptionPeriod.flipDay
    ///      field were removed in R4) sets the roll and that pendingRedemptionEthValue drops from the
    ///      submit-time MAX(175%) reservation to the rolled amount.
    function testResolveRedemptionPeriod2Arg() public {
        _seedRedemptionBacking(100 ether);

        uint32 dayBurn = game.currentDayView();
        uint256 burnAmount = 1000 ether;
        uint16 roll = 100; // rolled < MAX_ROLL(175) so the MAX→rolled lowering is observable

        _primeCurrentDayRng();
        vm.prank(playerA);
        sdgnrs.burn(burnAmount);

        uint256 pendingMaxReserved = sdgnrs.pendingRedemptionEthValue();
        assertGt(pendingMaxReserved, 0, "R4: submit must reserve the MAX (175%) into pendingRedemptionEthValue");

        _advanceWallDay();
        // The 2-arg call (roll, dayToResolve) — this is the v47 signature.
        vm.prank(address(game));
        sdgnrs.resolveRedemptionPeriod(roll, uint24(dayBurn));

        // roll written.
        (uint16 rollAfter) = sdgnrs.redemptionPeriods(uint24(dayBurn));
        assertEq(uint256(rollAfter), uint256(roll), "R4: 2-arg resolveRedemptionPeriod did not write roll");

        // pendingRedemptionEthValue lowered from MAX(175%) to rolled(100%): rolled < MAX → strictly down.
        uint256 pendingRolled = sdgnrs.pendingRedemptionEthValue();
        assertLt(
            pendingRolled,
            pendingMaxReserved,
            "R4: pendingRedemptionEthValue not lowered MAX->rolled on 2-arg resolve"
        );
    }

    /// @notice REDEEM-08 R3 (_settleClaimableShortfall invariant): the canonical CPAY shortfall
    ///         settle (used by 5 whale/mint callers, NOT the redemption path) keeps the global
    ///         invariant `claimablePool == Σ claimableWinnings` balanced — it debits
    ///         claimableWinnings[buyer] and claimablePool by the same `shortfall` and preserves the
    ///         STRICT 1-wei sentinel (`basis <= shortfall` reverts E()).
    /// @dev Focused refinement check via the SettleClaimableShortfallTester (runs the EXACT
    ///      production _settleClaimableShortfall body). Single-buyer harness: Σ claimableWinnings ==
    ///      claimableWinnings[buyer]. Fuzz the basis + shortfall; assert the paired debit keeps the
    ///      invariant on the success path and the strict sentinel reverts on `basis <= shortfall`.
    /// forge-config: default.fuzz.runs = 10000
    function testSettleClaimableShortfallInvariant(uint256 basisSeed, uint256 shortfallSeed) public {
        SettleClaimableShortfallTester tester = new SettleClaimableShortfallTester();
        address buyer = playerA;

        // basis in [2, 1e24]; shortfall in [1, basis-1] so the success path is exercised and the
        // strict 1-wei sentinel (basis > shortfall) holds. Seed pool == claimable (single buyer).
        uint256 basis = bound(basisSeed, 2, 1e24);
        uint256 shortfall = bound(shortfallSeed, 1, basis - 1);

        tester.setClaimable(buyer, basis);
        tester.setClaimablePool(basis); // single buyer ⇒ pool == Σ claimableWinnings == basis

        tester.settle(buyer, shortfall, true);

        // Paired debit: both dropped by exactly `shortfall`; invariant preserved.
        assertEq(tester.getClaimable(buyer), basis - shortfall, "R3: claimableWinnings[buyer] != basis - shortfall");
        assertEq(tester.getClaimablePool(), basis - shortfall, "R3: claimablePool != basis - shortfall");
        assertEq(
            tester.getClaimablePool(),
            tester.getClaimable(buyer),
            "R3: claimablePool diverged from Sigma claimableWinnings after settle"
        );

        // Strict 1-wei sentinel: settling a shortfall == basis (would zero claimable, violating the
        // strict-positive sentinel) reverts E() — `if (basis <= shortfall) revert E();`. The
        // The shortfall settle now reverts Insolvent() (inherited from DegenerusGameStorage);
        // assert the revert selector matches its 4-byte id.
        uint256 cur = tester.getClaimable(buyer);
        vm.expectRevert(bytes4(0xfc220038)); // Insolvent()
        tester.settle(buyer, cur, true); // shortfall == claimable: claimable to sentinel, then afking (0) short → revert Insolvent()
    }

    // =====================================================================
    //   MECH-01: un-mocked lootbox seed pins the day+1 RNG operand
    // =====================================================================

    /// @dev Write `rngWordByDay[day] = word` on the GAME (mapping(uint32 => uint256) at slot 10,
    ///      the same slot `_primeCurrentDayRng` writes). Lets the test give `day` and `day + 1`
    ///      DISTINCT non-zero words so the seed derivation's choice of operand is observable.
    function _setRngWordForDay(uint24 day, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(day), uint256(10))), bytes32(word));
        require(game.rngWordForDay(day) == word, "setRngWordForDay: slot mismatch");
    }

    /// @notice MECH-01 — the live-game redemption claim derives the lootbox seed from the NEXT
    ///         day's VRF word: `entropy = EntropyLib.hash2(game.rngWordForDay(day + 1), player)`
    ///         (sDGNRS._claimRedemptionFor). This pins the `day + 1` operand by driving a REAL
    ///         submit→resolve→claim with the lootbox half ABOVE the 0.01-ETH floor (so the leg
    ///         actually fires) and the production seed source UN-mocked, then asserting via
    ///         `vm.expectCall` that the real `game.resolveRedemptionLootbox` is invoked with
    ///         `entropy == hash2(rngWordForDay(day + 1), player)` and NOT
    ///         `hash2(rngWordForDay(day), player)`.
    ///
    ///         Why the rest of the suite is blind to a `day + 1 -> day` swap (the v62
    ///         REDEMPTION-ZERO-SEED class): every other redemption test runs against the
    ///         1-trillion-token deploy supply, where the rolled ETH is dust (well under the
    ///         0.02-ETH rolled threshold) so the lootbox half is forfeited and
    ///         `resolveRedemptionLootbox` is NEVER reached; and the few tests that do reach it
    ///         mock `game.resolveRedemptionLootbox` to a no-op (setUp :151) and
    ///         `getCoinflipDayResult` to a constant, so neither the `rngWordForDay(day + 1)` read
    ///         nor the resulting `entropy` argument is ever observed. A mutant that reads
    ///         `rngWordForDay(day)` instead would compute a different entropy yet keep the claim's
    ///         ETH legs identical — invisible to every existing assertion. This test makes the two
    ///         day-words distinct and pins the EXACT entropy argument, so the swap fails the
    ///         `expectCall` match.
    function test_LootboxSeedUsesDayPlusOneRngWord() public {
        uint32 dayBurn = game.currentDayView();

        // Distinct non-zero VRF words for `dayBurn` and the resolving day `dayBurn + 1`. If a
        // mutant read `rngWordForDay(dayBurn)`, the derived entropy would differ from the value
        // pinned below — provided the two words are distinct, which the assertion guarantees.
        uint256 wordDay = uint256(keccak256(abi.encode("mech01-day", dayBurn)));
        uint256 wordDayPlus1 = uint256(keccak256(abi.encode("mech01-dayPlus1", dayBurn)));
        assertTrue(wordDay != wordDayPlus1, "MECH-01: day and day+1 words must differ to expose the operand");
        _setRngWordForDay(uint24(dayBurn), wordDay);
        _setRngWordForDay(uint24(dayBurn) + 1, wordDayPlus1);

        // Seed a single (player, day) claim with a LARGE gwei-aligned ethValueOwed so the rolled
        // ETH clears the 0.02-ETH lootbox-floor (lootboxEth >= 0.01 ETH) and the
        // resolveRedemptionLootbox leg actually fires. PendingRedemption packing:
        // ethValueOwed (bits 0-95) | activityScore (bits 96-111) | flipEscrow (bits 112-207).
        // activityScore = 1 (treated as set; snapshotted score is activityScore - 1 = 0);
        // flipEscrow = 0 so the contingent-FLIP branch is skipped and only the lootbox-seed path
        // is exercised.
        uint256 ethValueOwed = 1 ether; // gwei-aligned; roll 100 -> totalRolledEth = 1 ether
        uint256 packedClaim = ethValueOwed | (uint256(1) << 96);
        bytes32 outerSlot = keccak256(abi.encode(playerA, uint256(SLOT_PENDING_REDEMPTIONS)));
        bytes32 claimSlot = keccak256(abi.encode(uint256(dayBurn), outerSlot));
        vm.store(address(sdgnrs), claimSlot, bytes32(packedClaim));

        // Seed _pendingRedemptionEthValue (slot 0, bits [128:223]) to the MAX(175%) reservation so
        // the release `_pendingRedemptionEthValue - totalRolledEth` at the end of the claim does
        // not underflow. Preserve the packed _totalSupply (bits [0:127]) and _pendingResolveDay
        // (bits [224:247]) lanes.
        uint256 maxReserve = (ethValueOwed * 175) / 100; // MAX_ROLL = 175 -> 1.75 ether
        uint256 slot0 = uint256(vm.load(address(sdgnrs), bytes32(uint256(0))));
        slot0 = (slot0 & ~(uint256(type(uint96).max) << 128)) | (uint256(uint96(maxReserve)) << 128);
        vm.store(address(sdgnrs), bytes32(uint256(0)), bytes32(slot0));

        // Mark the period resolved: redemptionPeriods (mapping(uint24=>uint16)) at slot 6.
        uint16 roll = 100;
        vm.store(
            address(sdgnrs),
            keccak256(abi.encode(uint256(dayBurn), uint256(6))),
            bytes32(uint256(roll))
        );
        assertEq(uint256(sdgnrs.redemptionPeriods(uint24(dayBurn))), uint256(roll), "MECH-01: roll seed mismatch");

        // Fund sDGNRS with ETH so both legs forward real msg.value (no stETH remainder pull).
        vm.deal(address(sdgnrs), 100 ether);

        // Swap the setUp shims: clear the GAME-side resolveRedemptionLootbox no-op (so the REAL
        // Game-side stub runs and is recorded by expectCall) and instead no-op ONLY the MODULE-side
        // delegatecall targets (resolveRedemptionLootbox + creditRedemptionDirect), so the deep
        // lootbox materialization loop and the direct-credit body return cleanly without seeded
        // game lootbox state. The production seed derivation in sDGNRS — rngWordForDay(day + 1) and
        // hash2 — is NOT mocked and runs for real; expectCall observes its result on the wire.
        vm.clearMockedCalls();
        vm.mockCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(IGameLootboxModuleRRL.resolveRedemptionLootbox.selector),
            abi.encode()
        );
        vm.mockCall(
            ContractAddresses.GAME_LOOTBOX_MODULE,
            abi.encodeWithSelector(bytes4(keccak256("creditRedemptionDirect(address,uint256)"))),
            abi.encode()
        );

        // Production-equivalent leg arithmetic (live game, not gameOver):
        //   totalRolledEth = ethValueOwed * roll / 100
        //   ethDirect      = totalRolledEth / 2
        //   lootboxEth     = totalRolledEth - ethDirect   (>= 0.01 ETH here, so the leg fires)
        //   actScore       = activityScore - 1 = 0
        uint256 totalRolledEth = (ethValueOwed * uint256(roll)) / 100;
        uint256 ethDirect = totalRolledEth / 2;
        uint256 lootboxEth = totalRolledEth - ethDirect;
        assertGe(lootboxEth, 0.01 ether, "MECH-01: lootbox half must clear the floor so the real leg fires");
        uint16 actScore = 0;

        // The CORRECT seed the production code must pass to resolveRedemptionLootbox: keyed to the
        // NEXT day's word. A `day + 1 -> day` mutant would instead pass
        // hash2(rngWordForDay(dayBurn), playerA), which differs (the words above are distinct), so
        // this expectCall would not match and the test would FAIL.
        uint256 expectedEntropy = EntropyLib.hash2(wordDayPlus1, uint256(uint160(playerA)));
        // Sanity: the mutant's value is genuinely different, so the pin is discriminating.
        uint256 mutantEntropy = EntropyLib.hash2(wordDay, uint256(uint160(playerA)));
        assertTrue(expectedEntropy != mutantEntropy, "MECH-01: day+1 vs day entropy must differ to catch the mutant");

        vm.expectCall(
            address(game),
            abi.encodeCall(
                IGameLootboxModuleRRL.resolveRedemptionLootbox,
                (playerA, lootboxEth, expectedEntropy, actScore)
            ),
            1
        );

        vm.prank(playerA);
        sdgnrs.claimRedemption(playerA, uint24(dayBurn));

        // Claim consumed the seeded slot (full-claim delete), confirming the path ran end-to-end.
        (uint96 evAfter, , uint96 escAfter) = sdgnrs.pendingRedemptions(playerA, uint24(dayBurn));
        assertEq(uint256(evAfter), 0, "MECH-01: claim slot must clear after full claim");
        assertEq(uint256(escAfter), 0, "MECH-01: flipEscrow must remain zero");
    }
}
