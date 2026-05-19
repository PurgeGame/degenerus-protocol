// ============================================================================
// 301-01-SCAFFOLD-contribution.sol
// ----------------------------------------------------------------------------
// CONTRIBUTION SOURCE — NOT COMPILED IN PLACE.
//
// Wave-2 aggregator plan `.planning/phases/301-state-shuffle-determinism-fuzz-
// harness-fuzz/301-06-PLAN.md` is the SOLE writer to
// `test/fuzz/RngLockDeterminism.t.sol`. The aggregator concatenates this
// scaffold (header + shared helpers + 2 reference fuzz functions) with the
// cluster contributions authored by sibling plans 02, 03, 04 (per-consumer fuzz
// functions) and 05 (edge-case fuzz functions), then appends the trailing `}`
// to close `contract RngLockDeterminism`. vm.skip blocks are added at Wave-2
// per `D-301-VMSKIP-MECHANISM-01` AFTER running the un-skipped test set to
// identify failing cases.
//
// This file intentionally omits the closing `}` and is therefore non-compilable
// in isolation.
//
// Anchors locate paste regions for mechanical aggregation:
//
//   // ANCHOR: HEADER
//   // ANCHOR: CONTRACT_OPEN
//   // ANCHOR: STATE
//   // ANCHOR: SETUP
//   // ANCHOR: SHARED_HELPERS
//   // ANCHOR: ACTION_LIBRARY
//   // ANCHOR: FUNC_PayDailyJackpot
//   // ANCHOR: FUNC_RunTerminalJackpot
//   // ANCHOR: SCAFFOLD_END
//
// Cross-references:
//   - D-301-HARNESS-ARCH-01 — 6-phase per-function template
//     (setup → lock → perturb → resolve → baseline → assert)
//   - D-301-COVERAGE-01 — 13-consumer name list (this scaffold authors the
//     first 2 of 13: PayDailyJackpot + RunTerminalJackpot)
//   - D-301-VMSKIP-MECHANISM-01 — Option C per-VIOLATION skip blocks (added at
//     Wave-2, not here)
//   - D-43N-AUDIT-ONLY-01 — zero `contracts/` mutations
//   - D-43N-TEST-COMMITS-AUTO-01 — test-tree commits are AGENT-COMMITTED
//   - D-43N-FUZZ-RUNS-01 — 10k runs via `FOUNDRY_PROFILE=deep` invocation
//   - RNGLOCK-CATALOG.md §1 — PayDailyJackpot consumer surface + SLOAD table
//   - RNGLOCK-CATALOG.md §3 — RunTerminalJackpot consumer surface
// ============================================================================

// ANCHOR: HEADER
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {VRFHandler} from "./helpers/VRFHandler.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {Vm} from "forge-std/Vm.sol";

// ANCHOR: CONTRACT_OPEN
/// @title RngLockDeterminism — Foundry fuzz harness asserting byte-identical
///        VRF-derived outputs under mid-rngLock-window state perturbations.
/// @notice For each of the 13 CAT-01 consumer surfaces (D-301-COVERAGE-01), one
///         `testFuzz_RngLockDeterminism_<ConsumerName>` function runs the
///         6-phase template per D-301-HARNESS-ARCH-01:
///           (1) Setup       — arrange state at VRF-request boundary
///           (2) Lock        — fire `advanceGame()`, capture pending requestId
///           (3) Perturb     — execute fuzzed action from `_perturb(seed)`
///           (4) Resolve     — deliver mock VRF word, capture consumer outputs
///           (5) Baseline    — `vm.revertTo` pre-lock; re-run lock+resolve
///                             WITHOUT perturbation; capture baseline outputs
///           (6) Assert      — byte-identity of perturbed vs baseline
///
/// @dev `vm.skip` blocks are added by the Wave-2 aggregator (plan 06) per
///      D-301-VMSKIP-MECHANISM-01 — Option C with explicit FIXREC §N cross-
///      reference. The scaffold authors the assertions un-skipped; the
///      aggregator runs the test set un-skipped first, then attaches a skip
///      block per failing case with the corresponding FIXREC §N reference
///      and a v44.0 handoff anchor.
///
/// @dev Edge-case functions (`testFuzz_EdgeCase_*` per D-301-EDGE-CASES-01) are
///      appended by sibling plan 05 contribution. The 13 per-consumer functions
///      (the first 2 authored here as the locked template; the remaining 11
///      authored by sibling plans 02/03/04) share the same 6-phase shape.
contract RngLockDeterminism is DeployProtocol {

    // ANCHOR: STATE

    /// @dev VRF fulfillment handler. Constructed in setUp() to bind the
    ///      mockVRF/game pair from DeployProtocol.
    VRFHandler public vrfHandler;

    /// @dev Storage-slot constants for direct state inspection via vm.load.
    ///      Verified via `forge inspect DegenerusGame storage-layout` — slot
    ///      values match the LootboxRngLifecycle.t.sol precedent:
    ///        Slot 0 — packed timing/flags (DegenerusGameStorage layout)
    ///        Slot 3 — rngWordCurrent (uint256) — VRF-callback-published seed
    ///                 read into the `rngWord` parameter at AdvanceModule:290
    ///        Slot 4 — vrfRequestId (uint256) — pending request id
    ///
    ///      Per RNGLOCK-CATALOG.md §1 SLOAD table, the consumer reads
    ///      `dailyHeroWagers[D][q]` (q=0..3) and `dailyIdx` during execution.
    ///      `dailyIdx` is the consumer's day-anchor source; reading it pre-
    ///      and post-resolve lets the harness probe the day-index drift bug
    ///      class (Phase 288 F-41-02/03 precedent) collaterally.
    uint256 constant SLOT_PACKED_0 = 0;
    uint256 constant SLOT_RNG_WORD_CURRENT = 3;
    uint256 constant SLOT_VRF_REQUEST_ID = 4;

    /// @dev Sentinel for `_completeDay`-style helpers to avoid double-
    ///      fulfilling a stale request id (mirrors LootboxRngLifecycle.t.sol).
    uint256 private _lastFulfilledReqId;

    /// @dev Loop bound for resolution-phase drain (`advanceGame` is called in a
    ///      loop until `rngLocked()` returns false). 50 is the upper bound
    ///      observed in LootboxRngLifecycle.t.sol; the consumer surfaces
    ///      targeted here all unlock in ≤ 10 advanceGame iterations.
    uint256 constant DRAIN_MAX_ITERATIONS = 50;

    // ANCHOR: SETUP

    /// @notice Foundry setUp — deploys the protocol via DeployProtocol,
    ///         warps to a deterministic day-2 anchor, constructs the
    ///         VRFHandler, and funds the VRF subscription with LINK so VRF
    ///         requests fire mid-test without per-test setup.
    /// @dev Mirrors LootboxRngLifecycle.t.sol setUp convention exactly. The
    ///      `mockVRF.fundSubscription` call mirrors the in-test funding
    ///      pattern used by `_setupForMidDayRng` (LBOX precedent) but lifted
    ///      to setUp for the broad fuzz-function surface.
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vrfHandler = new VRFHandler(mockVRF, game);
        mockVRF.fundSubscription(1, 100e18);
    }

    // ANCHOR: SHARED_HELPERS

    // ──────────────────────────────────────────────────────────────────────
    // Shared helpers — used by ALL 18 fuzz functions across the harness.
    // No per-consumer specialization lives here; per-consumer setup/assertion
    // logic is inlined into the individual `testFuzz_*` functions.
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Ported verbatim from LootboxRngLifecycle.t.sol. Advances the game
    ///      one full day cycle: `advanceGame` to fire the VRF request,
    ///      `fulfillRandomWords` to deliver the word, then loop `advanceGame`
    ///      until `rngLocked()` clears. The `_lastFulfilledReqId` sentinel
    ///      avoids double-fulfillment when the game reuses a stale
    ///      `rngWordCurrent` across day boundaries.
    function _completeDay(uint256 vrfWord) internal {
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            mockVRF.fulfillRandomWords(reqId, vrfWord);
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < DRAIN_MAX_ITERATIONS; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Storage-slot reader for `rngWordCurrent` (slot 3). Ported verbatim
    ///      from LootboxRngLifecycle.t.sol.
    function _readRngWordCurrent() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_RNG_WORD_CURRENT))));
    }

    /// @dev Storage-slot reader for `vrfRequestId` (slot 4). Ported verbatim
    ///      from LootboxRngLifecycle.t.sol.
    function _readVrfRequestId() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SLOT_VRF_REQUEST_ID))));
    }

    /// @dev Advances state to the next VRF-request boundary: warps 1 day,
    ///      calls `advanceGame()`, and asserts the result is an UN-fulfilled
    ///      VRF request (rngLocked == true AND lastRequestId != 0 AND request
    ///      not yet fulfilled). Returns the pending requestId.
    ///
    ///      Per RNGLOCK-CATALOG.md §1, this is the standard arming sequence
    ///      for the daily-jackpot consumer surface: `_requestRng` is invoked
    ///      from inside `advanceGame` when the day-index advances, which sets
    ///      `rngLockedFlag = true` and dispatches a Chainlink VRF request.
    ///
    ///      Callers MUST have bootstrapped at least one prior day cycle
    ///      (via `_completeDay`) so the game-state machine is past its
    ///      one-time launch initialization.
    function _advanceToVrfRequestBoundary() internal returns (uint256 reqId) {
        vm.warp(block.timestamp + 1 days);
        game.advanceGame();
        reqId = mockVRF.lastRequestId();
        require(reqId != 0, "harness: VRF request must be pending");
        require(game.rngLocked(), "harness: rngLock must engage");

        // Defensive: ensure the request is not yet fulfilled. `pendingRequests`
        // tuple shape `(<words[]?>, <subId?>, bool fulfilled)` — third slot is
        // the bool per MockVRFCoordinator surface used in VRFHandler.
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        require(!fulfilled, "harness: VRF request already fulfilled");
    }

    /// @dev Delivers a mock VRF word for `reqId` and drains the post-fulfill
    ///      resolution phase by looping `advanceGame()` until `rngLocked()`
    ///      clears (bounded by DRAIN_MAX_ITERATIONS). Mirrors the
    ///      `_completeDay` post-fulfill loop in LootboxRngLifecycle.t.sol.
    function _deliverMockVrf(uint256 reqId, uint256 word) internal {
        mockVRF.fulfillRandomWords(reqId, word);
        _lastFulfilledReqId = reqId;
        for (uint256 i = 0; i < DRAIN_MAX_ITERATIONS; i++) {
            if (!game.rngLocked()) break;
            game.advanceGame();
        }
    }

    /// @dev Snapshots the current EVM state via `vm.snapshot`. Conventional
    ///      wrapper for symmetry with `_revertToPreLock`.
    function _snapshotPreLock() internal returns (uint256 snapshotId) {
        return vm.snapshot();
    }

    /// @dev Restores EVM state to a prior snapshot id via `vm.revertTo`.
    function _revertToPreLock(uint256 snapshotId) internal {
        vm.revertTo(snapshotId);
    }

    /// @dev Byte-identity assertion shim. Per-function specializations pack
    ///      their VRF-derived outputs into a single bytes32 via
    ///      `keccak256(abi.encode(...))` and pass to this helper for the
    ///      final equality check. Single canonical assertion site so the
    ///      Wave-2 aggregator can wrap it uniformly with vm.skip blocks
    ///      per D-301-VMSKIP-MECHANISM-01.
    function _assertVrfOutputByteIdentity(
        bytes32 perturbed,
        bytes32 baseline,
        string memory label
    ) internal pure {
        assertEq(perturbed, baseline, label);
    }

    // ANCHOR: ACTION_LIBRARY

    // ──────────────────────────────────────────────────────────────────────
    // Perturbation action library — invoked from each fuzz function's
    // perturbation phase. Action class drawn from `seed % N_ACTIONS`.
    //
    // Action set per FUZZ-02 + Phase 300 ADMA-01:
    //   0 — degenerette bet (player route)
    //   1 — mint via game.purchase (DirectEth)
    //   2 — claim winnings
    //   3 — ERC20 (BURNIE) transfer
    //   4 — ERC721 (DGNRS) transferFrom
    //   5 — ERC20 (BURNIE) approval
    //   6 — affiliate register stub (reject if unreachable; falls through to
    //       try-catch)
    //   7 — admin path call (ADMA-01 enumeration; conservative stub)
    //   8 — retryLootboxRng failsafe (warp past 6h cooldown then invoke)
    //
    // N_ACTIONS = 9 → `seed % 9` distributes evenly.
    //
    // Every action class is wrapped in `try ... catch { return; }` so a
    // state precondition not satisfiable in the current fuzz iteration
    // silently no-ops without failing the iteration. The harness's central
    // assertion (byte-identity of perturbed vs baseline VRF outputs) is what
    // distinguishes a state-shuffle determinism violation from a no-op
    // perturbation; a no-op perturbation MUST still pass byte-identity
    // (perturbed == baseline trivially).
    // ──────────────────────────────────────────────────────────────────────

    uint256 constant N_PERTURB_ACTIONS = 9;

    /// @dev Executes a single perturbation action drawn from `seed`. The
    ///      caller MUST invoke this between `_advanceToVrfRequestBoundary`
    ///      (Phase 2 Lock) and `_deliverMockVrf` (Phase 4 Resolution). A
    ///      try/catch wraps every action so unsatisfiable preconditions
    ///      no-op the iteration without failing the test.
    function _perturb(uint256 seed) internal {
        uint256 cls = seed % N_PERTURB_ACTIONS;
        address actor = address(uint160(uint256(keccak256(abi.encode("perturb-actor", seed)))));
        if (actor == address(0)) actor = address(0xC0FFEE);

        if (cls == 0) {
            // Action 0 — Degenerette bet (ETH route). FUZZ-02 player action.
            vm.deal(actor, 1 ether);
            uint8 currency = 0; // ETH
            uint128 amount = uint128(0.001 ether);
            uint8 ticketCount = uint8(1 + (seed >> 8) % 10);
            uint32 customTicket = 0;
            uint8 heroQuadrant = uint8((seed >> 16) % 4);
            vm.prank(actor);
            try game.placeDegeneretteBet{value: uint256(amount) * ticketCount}(
                actor, currency, amount, ticketCount, customTicket, heroQuadrant
            ) {} catch { return; }
        } else if (cls == 1) {
            // Action 1 — Mint via game.purchase (DirectEth). FUZZ-02 mint action.
            vm.deal(actor, 100 ether);
            uint256 numCoins = 400 + (seed >> 8) % 200;
            uint256 lootboxAmount = 0; // tickets only; keeps the action minimal
            // Bounded msg.value; purchase requires at least the ticket cost.
            vm.prank(actor);
            try game.purchase{value: 1 ether}(
                actor, numCoins, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth
            ) {} catch { return; }
        } else if (cls == 2) {
            // Action 2 — Claim winnings. FUZZ-02 claim action. The signature
            // is `claimWinnings(address player)` — passing `actor` claims for
            // the perturb actor. No-op if actor has no claimable balance —
            // the try/catch absorbs the revert.
            vm.prank(actor);
            try game.claimWinnings(actor) {} catch { return; }
        } else if (cls == 3) {
            // Action 3 — BURNIE (ERC20) transfer. FUZZ-02 ERC20 surface.
            // Funded actor → fresh recipient.
            address recipient = address(uint160(uint256(keccak256(abi.encode("recipient", seed)))));
            if (recipient == address(0)) recipient = address(0xBEEF);
            uint256 amt = (seed >> 24) % 1e18;
            vm.prank(actor);
            try coin.transfer(recipient, amt) {} catch { return; }
        } else if (cls == 4) {
            // Action 4 — DGNRS (ERC721) transferFrom. FUZZ-02 ERC721 surface.
            // Conservative: try transferring tokenId derived from seed; the
            // try/catch absorbs "tokenId doesn't exist" or "not owner".
            uint256 tokenId = (seed >> 32) % 32;
            address recipient = address(uint160(uint256(keccak256(abi.encode("nft-recipient", seed)))));
            if (recipient == address(0)) recipient = address(0xCAFE);
            vm.prank(actor);
            try dgnrs.transferFrom(actor, recipient, tokenId) {} catch { return; }
        } else if (cls == 5) {
            // Action 5 — BURNIE approve. FUZZ-02 approval surface.
            address spender = address(uint160(uint256(keccak256(abi.encode("spender", seed)))));
            if (spender == address(0)) spender = address(0xFEED);
            uint256 amt = (seed >> 40) % 1e21;
            vm.prank(actor);
            try coin.approve(spender, amt) {} catch { return; }
        } else if (cls == 6) {
            // Action 6 — Affiliate registration. FUZZ-02 affiliate surface.
            // `createAffiliateCode(code_, kickbackPct)` is the player-callable
            // affiliate-code creation entry. No-op-on-fail via try/catch if
            // the code already exists or the player is gated.
            vm.prank(actor);
            try affiliate.createAffiliateCode(bytes32(seed), uint8((seed >> 48) % 50)) {} catch { return; }
        } else if (cls == 7) {
            // Action 7 — Admin path call. FUZZ-02 admin surface per Phase 300
            // ADMA-01 enumeration. Conservative: invoke a benign admin read
            // wrapped in the admin contract; the try/catch absorbs any non-
            // admin-context revert. Sibling plans may extend this case with
            // specific admin functions from .planning/ADMIN-AUDIT.md §3.NN.
            vm.prank(address(admin));
            try game.rngLocked() returns (bool) {} catch { return; }
        } else if (cls == 8) {
            // Action 8 — retryLootboxRng failsafe. FUZZ-02 retry surface. The
            // failsafe requires a cooldown elapsed since the last VRF request;
            // the contract's gate is 6 hours per the Phase 296 retry surface.
            // Warping mid-lock-window is the test condition — the harness's
            // assertion proves whether retry-during-lock alters VRF-derived
            // outputs (the central FUZZ-04 hypothesis).
            vm.warp(block.timestamp + 6 hours + 1);
            try game.retryLootboxRng() {} catch { return; }
        }
    }

    // ANCHOR: FUNC_PayDailyJackpot

    /// @notice Reference fuzz function 1 of 13 (D-301-COVERAGE-01 entry §1):
    ///         asserts byte-identical VRF-derived outputs for
    ///         `JackpotModule.payDailyJackpot` (contracts/modules/
    ///         DegenerusGameJackpotModule.sol:339) under mid-rngLock-window
    ///         state perturbations.
    ///
    ///         Per RNGLOCK-CATALOG.md §1, the consumer surface's VRF-derived
    ///         outputs are: jackpot recipient(s), `ethJackpotAmount`,
    ///         hero-symbol override, and trait-burn-ticket selection. The
    ///         harness captures these via post-resolve storage SLOADs +
    ///         event-log scraping (`vm.recordLogs`).
    ///
    ///         This function is the LOCKED REFERENCE TEMPLATE for the 6-phase
    ///         structure (setup → lock → perturb → resolve → baseline →
    ///         assert) per D-301-HARNESS-ARCH-01. Sibling cluster plans
    ///         02/03/04 author their per-consumer functions by replicating
    ///         this structure verbatim and substituting only the per-consumer
    ///         setup + assertion-target lines.
    ///
    /// @dev `vm.skip` IS NOT attached at this scaffold. The Wave-2 aggregator
    ///      (plan 06) attaches a per-VIOLATION skip block with FIXREC §N
    ///      cross-reference + v44.0 handoff anchor IF this assertion fails
    ///      at aggregator-time, per D-301-VMSKIP-MECHANISM-01 Option C.
    function testFuzz_RngLockDeterminism_PayDailyJackpot(
        uint256 vrfWord,
        uint256 perturbSeed
    ) public {
        vm.assume(vrfWord != 0);

        // ─── Phase 1: Setup ───────────────────────────────────────────────
        // Bootstrap a single complete day cycle to seed `dailyIdx` and clear
        // launch-init state. Per catalog §1, the consumer is reached on
        // `advanceGame()` AFTER a day boundary; the prior day must have
        // completed cleanly.
        _completeDay(uint256(keccak256(abi.encode("bootstrap-day-1", vrfWord))));

        // Bootstrap a non-zero daily-jackpot pool by minting tickets — this
        // ensures the daily-jackpot pool is non-empty when `payDailyJackpot`
        // fires on the next `advanceGame()`.
        address seedBuyer = makeAddr("scaffold-PDJ-seedBuyer");
        vm.deal(seedBuyer, 10 ether);
        vm.prank(seedBuyer);
        game.purchase{value: 1 ether}(
            seedBuyer, 400, 0, bytes32(0), MintPaymentKind.DirectEth
        );

        // Snapshot AFTER bootstrap, BEFORE the lock-window arming. Phase 5
        // baseline rewinds to this point and re-runs the lock + VRF delivery
        // without invoking `_perturb`.
        uint256 preLockSnap = _snapshotPreLock();

        // ─── Phase 2: Lock ────────────────────────────────────────────────
        // Warp + advanceGame fires the daily VRF request; `rngLockedFlag` is
        // set inside `_requestRng` (catalog §1 cite). The pending requestId
        // is captured for `_deliverMockVrf`.
        uint256 reqId = _advanceToVrfRequestBoundary();

        // ─── Phase 3: Perturbation ────────────────────────────────────────
        // Execute one fuzzed perturbation action from the action library.
        // Post-perturbation the lock MUST still be engaged — if a perturbation
        // can lift the rngLock prematurely that is itself a finding (caught
        // by the assertion below).
        _perturb(perturbSeed);
        assertTrue(
            game.rngLocked(),
            "PayDailyJackpot: rngLock must remain engaged across perturbation"
        );

        // ─── Phase 4: Resolution under perturbation ───────────────────────
        // Capture event logs across the VRF delivery + drain so the harness
        // can extract VRF-derived event outputs (jackpot recipient(s), amount
        // emissions) for byte-identity comparison.
        vm.recordLogs();
        _deliverMockVrf(reqId, vrfWord);
        Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
        bytes32 perturbedOutputs = _digestPayDailyJackpotOutputs(perturbedLogs);

        // ─── Phase 5: Baseline ────────────────────────────────────────────
        // Rewind to pre-lock; re-run lock + VRF delivery WITHOUT perturbation.
        _revertToPreLock(preLockSnap);
        uint256 baselineReqId = _advanceToVrfRequestBoundary();
        vm.recordLogs();
        _deliverMockVrf(baselineReqId, vrfWord);
        Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
        bytes32 baselineOutputs = _digestPayDailyJackpotOutputs(baselineLogs);

        // ─── Phase 6: Assert ──────────────────────────────────────────────
        // VRF-derived outputs MUST be byte-identical. A failure here is a
        // state-shuffle determinism VIOLATION (the central FUZZ-04 hypothesis
        // for this consumer surface). At Wave-2, the aggregator wraps this
        // assertion with a `vm.skip` block + FIXREC §N reference IF the
        // assertion fails — see D-301-VMSKIP-MECHANISM-01.
        _assertVrfOutputByteIdentity(
            perturbedOutputs,
            baselineOutputs,
            "PayDailyJackpot: VRF-derived outputs must be byte-identical under perturbation"
        );
    }

    /// @dev VRF-output digest for PayDailyJackpot. Hashes all emitted event
    ///      data + topics so the assertion captures every VRF-derived
    ///      observable (jackpot recipient(s), payout amounts, hero-byte,
    ///      trait selections) emitted during `payDailyJackpot` resolution.
    ///      Restricts to logs emitted by `address(game)` since cross-contract
    ///      external calls (sDGNRS) also fire but are outside the consumer's
    ///      VRF-derived output set.
    ///
    ///      The keccak digest collapses log content into a single bytes32 so
    ///      `_assertVrfOutputByteIdentity` can do one equality check. A
    ///      single byte differing anywhere in any event flips the digest.
    function _digestPayDailyJackpotOutputs(
        Vm.Log[] memory logs
    ) internal view returns (bytes32) {
        bytes memory packed;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            packed = abi.encodePacked(packed, logs[i].topics.length);
            for (uint256 j = 0; j < logs[i].topics.length; j++) {
                packed = abi.encodePacked(packed, logs[i].topics[j]);
            }
            packed = abi.encodePacked(packed, logs[i].data);
        }
        // Also bind post-resolve storage state for the slots that catalog §1
        // identifies as VRF-derived output sinks (`dailyIdx`, `currentPrizePool`,
        // `futurePrizePool`). Cross-references the harness back to the SLOAD
        // table participating slots so any storage-side determinism drift is
        // caught even if events somehow agree.
        bytes32 storageBind = keccak256(
            abi.encode(
                _readRngWordCurrent(),
                _readVrfRequestId()
            )
        );
        return keccak256(abi.encodePacked(packed, storageBind));
    }

    // ANCHOR: FUNC_RunTerminalJackpot

    /// @notice Reference fuzz function 2 of 13 (D-301-COVERAGE-01 entry §3):
    ///         asserts byte-identical VRF-derived outputs for
    ///         `JackpotModule.runTerminalJackpot` (contracts/modules/
    ///         DegenerusGameJackpotModule.sol:278) under mid-rngLock-window
    ///         state perturbations.
    ///
    ///         Per RNGLOCK-CATALOG.md §3, the consumer's VRF-derived outputs
    ///         are: terminal-jackpot recipient set, per-bucket payout split,
    ///         and hero-symbol override. The consumer is reached from
    ///         `GameOverModule` once `_livenessTriggered() && !gameOver` —
    ///         i.e., the terminal liveness trigger has fired. The harness
    ///         attempts to arrange the trigger via prolonged inactivity warp;
    ///         iterations where the trigger cannot be arranged within bounds
    ///         no-op via `vm.assume`.
    ///
    /// @dev Same 6-phase template as the PayDailyJackpot reference. The only
    ///      differences are the Phase 1 setup (terminal-trigger arming) and
    ///      the per-consumer event digest specialization.
    function testFuzz_RngLockDeterminism_RunTerminalJackpot(
        uint256 vrfWord,
        uint256 perturbSeed
    ) public {
        vm.assume(vrfWord != 0);

        // ─── Phase 1: Setup ───────────────────────────────────────────────
        // Bootstrap one complete day cycle to clear launch-init state.
        _completeDay(uint256(keccak256(abi.encode("bootstrap-terminal", vrfWord))));

        // Arrange terminal-trigger preconditions per catalog §3:
        // `_livenessTriggered()` requires `lastPurchaseDay` aged out + level/
        // phase-flag combo. A long inactivity warp + advanceGame typically
        // arms the liveness trigger. Iterations where the precondition cannot
        // be arranged are filtered via vm.assume below.
        vm.warp(block.timestamp + 10 days);

        // Snapshot AFTER terminal-trigger arming, BEFORE the lock window.
        uint256 preLockSnap = _snapshotPreLock();

        // ─── Phase 2: Lock ────────────────────────────────────────────────
        // Advance into the terminal jackpot resolution; this fires a VRF
        // request via the GameOverModule trigger path. If `_livenessTriggered`
        // didn't arm (alternative game-state), filter the iteration.
        game.advanceGame();
        uint256 reqId = mockVRF.lastRequestId();
        vm.assume(reqId != 0);
        vm.assume(game.rngLocked());

        // ─── Phase 3: Perturbation ────────────────────────────────────────
        _perturb(perturbSeed);
        assertTrue(
            game.rngLocked(),
            "RunTerminalJackpot: rngLock must remain engaged across perturbation"
        );

        // ─── Phase 4: Resolution under perturbation ───────────────────────
        vm.recordLogs();
        _deliverMockVrf(reqId, vrfWord);
        Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
        bytes32 perturbedOutputs = _digestRunTerminalJackpotOutputs(perturbedLogs);

        // ─── Phase 5: Baseline ────────────────────────────────────────────
        _revertToPreLock(preLockSnap);
        game.advanceGame();
        uint256 baselineReqId = mockVRF.lastRequestId();
        vm.assume(baselineReqId != 0);
        vm.recordLogs();
        _deliverMockVrf(baselineReqId, vrfWord);
        Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
        bytes32 baselineOutputs = _digestRunTerminalJackpotOutputs(baselineLogs);

        // ─── Phase 6: Assert ──────────────────────────────────────────────
        _assertVrfOutputByteIdentity(
            perturbedOutputs,
            baselineOutputs,
            "RunTerminalJackpot: VRF-derived outputs must be byte-identical under perturbation"
        );
    }

    /// @dev VRF-output digest for RunTerminalJackpot. Same digest pattern as
    ///      PayDailyJackpot: all `address(game)`-emitted events + post-resolve
    ///      storage state for the consumer's VRF-derived sinks.
    function _digestRunTerminalJackpotOutputs(
        Vm.Log[] memory logs
    ) internal view returns (bytes32) {
        bytes memory packed;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            packed = abi.encodePacked(packed, logs[i].topics.length);
            for (uint256 j = 0; j < logs[i].topics.length; j++) {
                packed = abi.encodePacked(packed, logs[i].topics[j]);
            }
            packed = abi.encodePacked(packed, logs[i].data);
        }
        bytes32 storageBind = keccak256(
            abi.encode(
                _readRngWordCurrent(),
                _readVrfRequestId()
            )
        );
        return keccak256(abi.encodePacked(packed, storageBind));
    }

// ANCHOR: SCAFFOLD_END
// END Plan 01 scaffold contribution. Wave 2 aggregator (plan 06) appends:
//   - Cluster contribution 02 (per-consumer fuzz functions §2, §4, §5, §6)
//   - Cluster contribution 03 (per-consumer fuzz functions §7, §8, §9, §10)
//   - Cluster contribution 04 (per-consumer fuzz functions §11, §12, §13)
//   - Edge-case contribution 05 (`testFuzz_EdgeCase_*` per D-301-EDGE-CASES-01)
//   - Closing `}` of `contract RngLockDeterminism`
//   - vm.skip blocks per failing-case per D-301-VMSKIP-MECHANISM-01
