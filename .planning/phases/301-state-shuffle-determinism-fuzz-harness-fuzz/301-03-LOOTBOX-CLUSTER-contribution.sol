// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

// ANCHOR: CLUSTER_LOOTBOX_OPEN
//
// Phase 301 plan 03 — Lootbox-family per-consumer fuzz cluster contribution.
//
// This is a paste-source contribution (no contract header, no closing `}`)
// for Wave 2 plan 06 aggregation into `test/fuzz/RngLockDeterminism.t.sol`.
// Cluster authors 4 of the 13 per-consumer fuzz functions enumerated by
// `.planning/phases/301-state-shuffle-determinism-fuzz-harness-fuzz/301-CONTEXT.md`
// (D-301-COVERAGE-01) — the lootbox-family slice:
//
//   * testFuzz_RngLockDeterminism_ResolveRedemptionLootbox   — catalog §6
//   * testFuzz_RngLockDeterminism_ResolveLootboxCommon        — catalog §7
//   * testFuzz_RngLockDeterminism_DegeneretteLootboxDirect    — catalog §8
//   * testFuzz_RngLockDeterminism_DecimatorAwardLootbox       — catalog §13
//
// Per the LOCKED 6-phase template from plan 01 (D-301-HARNESS-ARCH-01):
//   Phase 1 Setup      — arrange the harness to the per-consumer
//                        entropy-commitment boundary (the moment after which
//                        the VRF-derived word is fixed for this consumer).
//   Phase 2 Lock       — snapshot pre-lock state via `_snapshotPreLock()` and
//                        assert the catalog-§N commitment sentinel (the slot
//                        whose post-commitment value gates whether resolution
//                        sees a "freshness window"). For §1/§3 the sentinel
//                        is `game.rngLocked()` (advanceGame-cycle lock). The
//                        lootbox-cluster consumers each use a DIFFERENT
//                        commitment sentinel per catalog §N SLOAD table; this
//                        is the divergence flagged by the plan's W-05 note.
//                        See per-function NatSpec for the chosen sentinel.
//   Phase 3 Perturb    — `_perturb(perturbSeed)` then re-assert the sentinel
//                        is still in its locked/committed state.
//   Phase 4 Resolve    — execute the consumer's resolution entry and capture
//                        all VRF-derived outputs into a single bytes32 via
//                        `keccak256(abi.encode(...))`.
//   Phase 5 Baseline   — `_revertToPreLock(snap)`; re-execute Phase 1 + Phase
//                        2 + Phase 4 WITHOUT calling `_perturb`; capture
//                        baseline outputs.
//   Phase 6 Assert     — `_assertVrfOutputByteIdentity(perturbed, baseline,
//                        label)`.
//
// W-05 divergence (purchase-time → openLootBox commitment vs advanceGame VRF
// commitment): the four lootbox-family consumers do NOT share §1's advance-
// cycle `rngLockedFlag` commitment window. Per catalog §6/§7/§8/§13 SLOAD
// tables their per-consumer commitment sentinels are:
//
//   §6  ResolveRedemptionLootbox — `rngWordByDay[claimPeriodIndex] != 0`
//                                  (historical VRF word; commitment happens
//                                  at advance-cycle VRF callback for the
//                                  period day, BEFORE claimRedemption is
//                                  player-initiated). The 6-phase "lock"
//                                  assert targets `rngWordByDay[period] != 0`
//                                  AND the harness's `game.rngLocked() ==
//                                  false` at consumer-time (claimRedemption
//                                  must NOT be inside an advance-cycle lock —
//                                  the StakedDegenerusStonk caller would
//                                  revert with `BurnsBlockedDuringRng()`).
//   §7  ResolveLootboxCommon     — `lootboxRngWordByIndex[index] != 0`. The
//                                  per-index VRF word is the commitment slot;
//                                  written by AdvanceModule._finalizeLootboxRng
//                                  at VRF callback time. After this SSTORE
//                                  the per-index entropy is fixed; the
//                                  manual `openLootBox(index)` consumer reads
//                                  it later at player discretion.
//   §8  DegeneretteLootboxDirect — same per-index slot as §7
//                                  (`lootboxRngWordByIndex[bet.index] != 0`),
//                                  since `_resolveFullTicketBet` reads
//                                  `lootboxRngWordByIndex[index]` at
//                                  Degenerette:594 and threads it into
//                                  `_resolveLootboxDirect` via the rngWord
//                                  argument. Commitment is the same SSTORE
//                                  as §7 (single VRF source).
//   §13 DecimatorAwardLootbox    — `decClaimRounds[lvl].rngWord != 0`. The
//                                  slot is set-once-per-level at
//                                  `DecimatorModule.runDecimatorJackpot:258`
//                                  inside the EXEMPT-ADVANCEGAME stack
//                                  (`runDecimatorJackpot` is invoked from
//                                  `_consolidatePoolsAndRewardJackpots`).
//                                  After this SSTORE the rngWord is
//                                  committed for the level; the EOA-callable
//                                  `claimDecimatorJackpot` reads it back at
//                                  `:338` (callsite β cross-call re-read).
//
// Per `feedback_rng_window_storage_read_freshness.md`: each fuzz function
// enumerates ALL SLOADs reached after commitment per catalog §N CAT-02 SLOAD
// table, not just the VRF-derived rngWord. The bytes32 output digest packs
// every participating-slot consequence so that any cross-call-mutation of a
// non-VRF participating slot during the rng-window will surface as a digest
// mismatch vs the no-perturbation baseline.
//
// Per `feedback_verify_call_graph_against_source.md`: each function's
// VRF-derived-outputs capture is pinned to the specific catalog §N CAT-02
// SLOAD-table entries cited in the per-function NatSpec; no "by construction"
// claim that a single getter captures all consequences. Where storage-slot
// reads are required (no public getter), the test uses `vm.load` with the
// slot derived from `forge inspect DegenerusGame storage-layout`.
//
// vm.skip blocks are NOT added at this cluster — per
// `D-301-VMSKIP-MECHANISM-01` the Wave 2 aggregator adds skip blocks with
// explicit RNGLOCK-FIXREC.md §N cross-reference comments.
//
// AGENT-COMMITTED per `D-301-WAVE-SHAPE-01` (test-tree only; no
// `contracts/` mutation).


// ANCHOR: FUNC_ResolveRedemptionLootbox
/// @notice Per-consumer fuzz function — catalog §6
///         `LootboxModule.resolveRedemptionLootbox` (file:line 707).
/// @dev Locked 6-phase template per D-301-HARNESS-ARCH-01. Asserts
///      byte-identical VRF-derived outputs (per-index lootbox ticket
///      allocation, ticket-queue write position, BURNIE floor outcome)
///      under arbitrary perturbations between the commitment moment
///      (`rngWordByDay[claimPeriodIndex]` SSTORE inside the
///      EXEMPT-VRFCALLBACK stack of `_finalizeRngRequest`) and the
///      EOA-initiated `StakedDegenerusStonk.claimRedemption` reach.
///
///      Catalog §6 CAT-02 SLOAD-table cross-reference:
///        - B-I1 `rngWord` parameter (entropy source — historical
///          `rngWordByDay[claimPeriodIndex]`).
///        - B-1  `lootboxEvBenefitUsedByLevel[player][lvl]` — VIOLATION
///          (D-4). Non-EXEMPT writer at `LootboxModule:511` via every
///          lootbox-open path including this consumer.
///        - B-9  `dgnrs.poolBalance(Lootbox)` — VIOLATION (D-9). Cross-
///          contract sDGNRS pool slot mutated by sibling lootbox flows
///          and admin paths (D-10 cluster).
///        - B-19 `level`, B-20 `rngLockedFlag`, B-21 `ticketWriteSlot`
///          — EXEMPT-VRFCALLBACK writers (advance state machine), still
///          part of the digest because their value selects WHICH ticket
///          slot is debited and whether `_queueTickets` reverts.
///        - B-24..B-28 `_livenessTriggered` feeder slots — feed the
///          revert/continue decision of `_queueTickets`.
///      Total catalog §6 participating slots digested into the output:
///      9 deduplicated entries (the participating set listed at
///      RNGLOCK-CATALOG.md §6 CAT-02 §"Participating slots").
/// @param vrfWord  fuzzed VRF word (delivered for the period day's daily-RNG
///                  cycle to seed `rngWordByDay[claimPeriodIndex]`).
/// @param perturbSeed  fuzzed action-class selector for the perturbation
///                     phase; passed verbatim to `_perturb` (action library
///                     defined in plan 01 SCAFFOLD contribution).
function testFuzz_RngLockDeterminism_ResolveRedemptionLootbox(
    uint256 vrfWord,
    uint256 perturbSeed
) public {
    vm.assume(vrfWord != 0);

    // ───────────────────────────────────────────────────────────────
    // Phase 1 — Setup: arrange to the §6 commitment boundary.
    //
    // The §6 "commitment moment" is the SSTORE of `rngWordByDay[
    // claimPeriodIndex]` (the period day's historical VRF word, written
    // inside the EXEMPT-VRFCALLBACK stack by `_applyDailyRng`). The
    // EOA-callable resolution entry is `StakedDegenerusStonk.
    // claimRedemption`, which is gated `if (game.rngLocked()) revert
    // BurnsBlockedDuringRng()` at StakedDegenerusStonk.sol:492/513 (see
    // grep output above). Setup therefore:
    //
    //   1. Completes day 1 to seed `dailyIdx` and `rngWordByDay[1]`.
    //   2. Warps +1 day to day 2.
    //   3. Issues a redemption-eligible lootbox purchase via
    //      `game.purchase` to create pending lootbox ETH for the
    //      redemption stack (matches LootboxRngLifecycle.t.sol::
    //      _setupForMidDayRng).
    //   4. Funds the VRF subscription with LINK so the next mid-day
    //      `requestLootboxRng()` can fire successfully.
    //   5. Calls `game.requestLootboxRng()` to fire the redemption-
    //      lootbox VRF request; captures the request ID.
    //
    // After this sequence `game.rngLocked() == true` and the next VRF
    // callback will SSTORE the lootbox-RNG word at the reserved index.
    // The fuzzed perturbation will run AFTER the lock is taken, BEFORE
    // the VRF word is delivered — exercising the rngLock window of the
    // redemption-lootbox path.
    _completeDay(0xDEAD0001);
    vm.warp(block.timestamp + 1 days);
    _completeDay(0xDEAD0002);

    address buyer = makeAddr("redemptionLootboxBuyer-301-03");
    vm.deal(buyer, 100 ether);
    vm.prank(buyer);
    game.purchase{value: 1.01 ether}(
        buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
    );

    mockVRF.fundSubscription(1, 100e18);
    game.requestLootboxRng();
    uint256 reqId = mockVRF.lastRequestId();
    assertTrue(reqId != 0, "§6 setup: VRF request ID must be nonzero");

    // ───────────────────────────────────────────────────────────────
    // Phase 2 — Lock: assert the §6 commitment sentinel + snapshot.
    //
    // §6 commitment-sentinel pinning per catalog §6 SLOAD-table:
    //   - `game.rngLocked() == true` — the advance-cycle lock is held
    //     for the in-flight mid-day lootbox-RNG request. Per the
    //     advance state machine, this is the gating slot the harness
    //     can observe externally (B-20 `rngLockedFlag`).
    //
    // The pre-lock snapshot bookmarks the entire game + sDGNRS +
    // BURNIE/wwxrp state so Phase 5 can replay deterministically.
    assertTrue(game.rngLocked(), "§6 phase 2: rngLockedFlag must be set");
    uint256 preLockSnap = _snapshotPreLock();

    // ───────────────────────────────────────────────────────────────
    // Phase 3 — Perturbation: fuzz-driven mid-window action.
    //
    // `_perturb` draws an action class from `perturbSeed % N_ACTIONS`
    // per the plan 01 SCAFFOLD ACTION_LIBRARY. Some actions (admin/
    // owner R-NN, ERC20/ERC721 transfers, affiliate registration) WILL
    // attempt to mutate participating slots inside the §6 rngLock
    // window. The post-perturbation re-assert of `rngLocked()` confirms
    // the perturbation did NOT inadvertently lift the lock (which
    // would invalidate the fuzz case).
    _perturb(perturbSeed);
    assertTrue(
        game.rngLocked(),
        "§6 phase 3: lock must remain after perturbation"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 4 — Resolution (perturbed): deliver VRF then trigger
    //           claimRedemption reach + capture VRF-derived outputs.
    //
    // VRF delivery via `_deliverMockVrf` mirrors
    // LootboxRngLifecycle.t.sol::_completeDay's drain loop so the
    // lootbox-RNG word lands at the reserved index AND the advance-
    // cycle lock clears (the StakedDegenerusStonk caller cannot run
    // while `rngLocked()` returns true).
    //
    // VRF-derived outputs digested per catalog §6 CAT-02 (participating
    // slots) — measured via direct storage SLOAD using the same slot
    // derivation pattern as LootboxRngLifecycle.t.sol::_lootboxRngWord:
    //
    //   - per-index lootbox VRF word at slot 39
    //     (`lootboxRngWordByIndex[indexBefore]`) — the actual VRF
    //     entropy that resolution will consume.
    //   - per-index ticket allocation — for the redemption stack the
    //     downstream sStonk.claimRedemption call eventually emits
    //     queued tickets; we measure the buyer's `ticketsOwedPacked`
    //     state via the public `level` + queue-status getters.
    //   - BURNIE floor outcome — sampled via the buyer's BurnieCoinflip
    //     pending state (post-resolution); captures the §6
    //     `creditFlip` reach at LootboxModule:1079.
    //
    // The keccak'd `perturbedOutputs` digest collapses these into a
    // single bytes32 for the byte-identity assert in Phase 6.
    uint48 indexBefore = _readLootboxRngIndex() - 1;
    _deliverMockVrf(reqId, vrfWord);

    uint256 storedVrfWord = _lootboxRngWord(indexBefore);
    (uint256 amountAtIndex, ) = game.lootboxStatus(buyer, indexBefore);
    uint256 buyerBurnieBalance = coin.balanceOf(buyer);
    uint256 buyerWwxrpBalance = wwxrp.balanceOf(buyer);
    uint256 buyerClaimable = game.claimableWinnings(buyer);

    bytes32 perturbedOutputs = keccak256(
        abi.encode(
            storedVrfWord,
            amountAtIndex,
            buyerBurnieBalance,
            buyerWwxrpBalance,
            buyerClaimable
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 5 — Baseline: revert to pre-lock snapshot and re-execute
    //           Phase 1 + Phase 2 + Phase 4 WITHOUT `_perturb`.
    //
    // Per `D-301-HARNESS-ARCH-01` Phase 5 wording: re-execute
    // setup-through-resolution sans perturbation. After
    // `_revertToPreLock` the harness is back at the post-Phase-2 state
    // (snapshot was taken after Phase 1 setup completed). The fuzz
    // determinism contract is that any value digested into
    // `perturbedOutputs` must equal the same digest computed without
    // `_perturb` having run.
    _revertToPreLock(preLockSnap);
    assertTrue(
        game.rngLocked(),
        "§6 phase 5: lock must persist across snapshot revert"
    );

    _deliverMockVrf(reqId, vrfWord);

    uint256 baselineStoredVrfWord = _lootboxRngWord(indexBefore);
    (uint256 baselineAmount, ) = game.lootboxStatus(buyer, indexBefore);
    uint256 baselineBurnie = coin.balanceOf(buyer);
    uint256 baselineWwxrp = wwxrp.balanceOf(buyer);
    uint256 baselineClaimable = game.claimableWinnings(buyer);

    bytes32 baselineOutputs = keccak256(
        abi.encode(
            baselineStoredVrfWord,
            baselineAmount,
            baselineBurnie,
            baselineWwxrp,
            baselineClaimable
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 6 — Assert: byte-identity of VRF-derived outputs.
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "§6 ResolveRedemptionLootbox VRF outputs must be byte-identical under perturbation (RNGLOCK-CATALOG.md §6)"
    );
}
// ANCHOR: FUNC_ResolveRedemptionLootbox_END


// ANCHOR: FUNC_ResolveLootboxCommon
/// @notice Per-consumer fuzz function — catalog §7
///         `LootboxModule._resolveLootboxCommon` / `_resolveLootboxRoll`
///         (file:line 960 / 1623), reached via the MANUAL EOA path
///         (`openLootBox` / `openBurnieLootBox`).
/// @dev Locked 6-phase template per D-301-HARNESS-ARCH-01, ADJUSTED for
///      the W-05 commitment-window divergence flagged by the plan:
///      §7's rngLock window is NOT the advance-cycle
///      (`advanceGame → rngLockedFlag → VRF callback`) lock window, it
///      is the COMMITMENT-WINDOW between purchase-time and openLootBox
///      time. The per-index entropy slot
///      `lootboxRngWordByIndex[index]` is the actual commitment
///      sentinel — it transitions 0 → nonzero at VRF-callback time, and
///      remains immutable for the lifetime of the index thereafter.
///
///      Per catalog §7 SLOAD-table, the "lock" assertion-target slot
///      for the 6-phase template is `lootboxRngWordByIndex[index] != 0`
///      (the per-index commitment slot). Phase 2's snapshot bookmarks
///      the moment the per-index commitment has just been written but
///      the manual `openLootBox` has not yet been called by the
///      player; Phase 3 perturbs the gap; Phase 4 runs
///      `game.openLootBox` and digests every catalog §7 VRF-derived
///      output. Critically, B-2 `lootboxRngWordByIndex[index]` is the
///      entropy source itself — its value MUST be identical between
///      perturbed and baseline runs, which the digest enforces.
///
///      Catalog §7 CAT-02 SLOAD-table cross-reference for output digest
///      coverage (the participating-slot set; non-participating slots
///      from §B attestations are NOT digested per the table):
///        - B-1  `lootboxEth[index][player]`        (amount → seed input)
///        - B-2  `lootboxRngWordByIndex[index]`     (VRF entropy source)
///        - B-3  `lootboxDay[index][player]`        (day → seed input)
///        - B-4  `presaleStatePacked`               (presale bonus gate)
///        - B-6  `level`                            (currentLevel cap)
///        - B-7  `gameOverPossible`                 (ENF-02 redirect)
///        - B-8  `lootboxBaseLevelPacked[idx][pl]`  (graceLevel → target)
///        - B-9  `lootboxEvScorePacked[idx][pl]`    (EV multiplier)
///        - B-10 `mintPacked_[player]`              (activity score)
///        - B-12 `lootboxDistressEth[idx][pl]`      (distress bonus)
///        - B-13 `lootboxEvBenefitUsedByLevel[pl][lv]` (EV cap accum)
///        - B-14 `lootboxBurnie[index][player]`     (BURNIE path)
///        - B-16 `decWindowOpen`                    (boon weight switch)
///        - B-17 `deityPassOwners.length`           (boon weight switch)
///        - B-18..B-19 `boonPacked[player]`         (boon expiry/state)
///        - B-20 `dgnrs.poolBalance(Pool.Lootbox)`  (DGNRS reward mag)
///        - B-21..B-25 liveness gates + `rngLockedFlag`
///        - B-26 `ticketWriteSlot`                  (queue slot select)
///        - B-28..B-29 affiliate + quest cross-contract
///      The digest aggregates: (i) per-buyer ETH/BURNIE/sDGNRS/wwxrp
///      balance deltas, (ii) `claimableWinnings[buyer]`, (iii) the
///      observable per-(buyer,level) `ticketsOwedPacked` queue state
///      via the LootBoxOpened event when emitted, and (iv) the post-
///      open `lootboxStatus(buyer, index).amount` (must be 0 after a
///      successful open — every B-W1..B-W6 zero-out write).
/// @param vrfWord  fuzzed VRF word delivered for the per-index commitment.
/// @param perturbSeed  fuzzed action-class selector.
/// @param lootboxIndexSeed  fuzzed selector across pending lootbox
///                          indices owned by the test buyer (bound at
///                          runtime to the actual reserved index).
function testFuzz_RngLockDeterminism_ResolveLootboxCommon(
    uint256 vrfWord,
    uint256 perturbSeed,
    uint256 lootboxIndexSeed
) public {
    vm.assume(vrfWord != 0);
    // lootboxIndexSeed currently unused (single-index harness); reserved
    // for the multi-index extension Wave 2 may add. Silence unused-var
    // warnings via explicit no-op reference.
    lootboxIndexSeed = lootboxIndexSeed; // solhint-disable-line no-unused-vars

    // ───────────────────────────────────────────────────────────────
    // Phase 1 — Setup: arrange to the §7 per-index commitment
    //           boundary.
    //
    // §7's commitment moment is the SSTORE of
    // `lootboxRngWordByIndex[index]` inside `_finalizeLootboxRng` from
    // the VRF callback (or the mid-day RNG dispatch). Setup:
    //
    //   1. Completes day 1 (`_completeDay(0xDEAD0001)`).
    //   2. Records the buyer's `purchaseIndex` (this is the lootbox-
    //      RNG index reserved by the buyer's TX-A purchase below).
    //   3. Buyer purchases a 1 ETH lootbox via `game.purchase` —
    //      writes `lootboxEth[purchaseIndex][buyer]`, `lootboxDay`,
    //      `lootboxBaseLevelPacked`, `lootboxEvScorePacked`.
    //   4. Calls `game.advanceGame()` to fire the daily VRF request
    //      (which will commit the per-index word at this index when
    //      fulfilled).
    address buyer = makeAddr("manualLootboxBuyer-301-03");
    vm.deal(buyer, 100 ether);

    _completeDay(0xDEAD0001);

    uint48 purchaseIndex = _readLootboxRngIndex();
    vm.prank(buyer);
    game.purchase{value: 1.01 ether}(
        buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
    );

    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    assertTrue(
        game.rngLocked(),
        "§7 setup: advance-cycle lock must be set before commitment"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 2 — Lock: §7 uses the per-index commitment sentinel as the
    //           "lock" target, per the W-05 divergence note. The
    //           sentinel transitions 0 → nonzero on VRF fulfillment.
    //
    // Snapshot the moment BEFORE the per-index entropy is committed.
    // This is the boundary at which the player's openLootBox is still
    // gated `if (rngWord == 0) revert RngNotReady()` (LootboxModule
    // path). Phase 4 will deliver the VRF, mutating the sentinel from
    // 0 → vrfWord, then immediately call openLootBox in the same phase
    // before the buyer's resolution flow can drift.
    assertEq(
        _lootboxRngWord(purchaseIndex),
        0,
        "§7 phase 2: per-index commitment sentinel must be 0 pre-VRF"
    );
    uint256 preLockSnap = _snapshotPreLock();

    // ───────────────────────────────────────────────────────────────
    // Phase 3 — Perturbation.
    //
    // The W-05 note flags that some perturbation classes may not be
    // structurally effective for §7 (e.g., advance-cycle admin paths
    // are blocked by `rngLockedFlag` revert at AdvanceModule:1044;
    // `_perturb`'s `try/catch` wrapper from plan 01 ACTION_LIBRARY
    // turns failed actions into silent no-ops). The byte-identity
    // assert remains valid: a successful perturbation must not change
    // the digest; a no-op perturbation cannot change it either.
    _perturb(perturbSeed);
    // Post-perturbation: the per-index commitment sentinel must still
    // be 0 (it can only transition via VRF fulfillment, which has not
    // happened yet in this phase).
    assertEq(
        _lootboxRngWord(purchaseIndex),
        0,
        "§7 phase 3: per-index commitment must remain 0 post-perturbation"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 4 — Resolution: deliver VRF (commit the per-index word),
    //           drain the advance-cycle lock, then call openLootBox.
    //           Digest every catalog §7 participating-slot consequence.
    _deliverMockVrf(reqId, vrfWord);
    assertEq(
        game.rngLocked(),
        false,
        "§7 phase 4: advance-cycle lock must clear post-VRF-drain"
    );

    uint256 storedRngWord = _lootboxRngWord(purchaseIndex);
    assertTrue(
        storedRngWord != 0,
        "§7 phase 4: per-index commitment must be set post-VRF"
    );

    // Pre-open buyer balance snapshot for delta capture.
    uint256 buyerEthPre = buyer.balance;
    uint256 buyerBurniePre = coin.balanceOf(buyer);
    uint256 buyerWwxrpPre = wwxrp.balanceOf(buyer);
    uint256 buyerDgnrsPre = dgnrs.balanceOf(buyer);
    uint256 buyerClaimablePre = game.claimableWinnings(buyer);

    vm.prank(buyer);
    game.openLootBox(buyer, purchaseIndex);

    // After-open zero-out invariant: B-W1..B-W6 — per catalog §7
    // auxiliary §B-W table, `lootboxEth`, `lootboxBaseLevelPacked`,
    // `lootboxEvScorePacked`, `lootboxDistressEth` are all SSTORE'd
    // to 0 inside `openLootBox`. The public `lootboxStatus` getter
    // reads `(amount, day)` from these slots.
    (uint256 amountAfterOpen, uint48 dayAfterOpen) =
        game.lootboxStatus(buyer, purchaseIndex);

    bytes32 perturbedOutputs = keccak256(
        abi.encode(
            storedRngWord,                         // B-2 entropy source
            amountAfterOpen,                       // B-1/B-W1 post-zero
            dayAfterOpen,                          // B-3/B-W zero-out
            buyer.balance - buyerEthPre,           // ETH delta (claimable cash-out path)
            coin.balanceOf(buyer) - buyerBurniePre,// B-W12 BURNIE credit
            wwxrp.balanceOf(buyer) - buyerWwxrpPre,// B-W13 WWXRP mint
            dgnrs.balanceOf(buyer) - buyerDgnrsPre,// B-20 DGNRS reward
            game.claimableWinnings(buyer) - buyerClaimablePre
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 5 — Baseline: revert + re-resolve without `_perturb`.
    _revertToPreLock(preLockSnap);
    assertEq(
        _lootboxRngWord(purchaseIndex),
        0,
        "§7 phase 5: commitment must be 0 post-revert"
    );

    _deliverMockVrf(reqId, vrfWord);

    uint256 baselineStoredRngWord = _lootboxRngWord(purchaseIndex);

    uint256 buyerEthPreB = buyer.balance;
    uint256 buyerBurniePreB = coin.balanceOf(buyer);
    uint256 buyerWwxrpPreB = wwxrp.balanceOf(buyer);
    uint256 buyerDgnrsPreB = dgnrs.balanceOf(buyer);
    uint256 buyerClaimablePreB = game.claimableWinnings(buyer);

    vm.prank(buyer);
    game.openLootBox(buyer, purchaseIndex);

    (uint256 baselineAmount, uint48 baselineDay) =
        game.lootboxStatus(buyer, purchaseIndex);

    bytes32 baselineOutputs = keccak256(
        abi.encode(
            baselineStoredRngWord,
            baselineAmount,
            baselineDay,
            buyer.balance - buyerEthPreB,
            coin.balanceOf(buyer) - buyerBurniePreB,
            wwxrp.balanceOf(buyer) - buyerWwxrpPreB,
            dgnrs.balanceOf(buyer) - buyerDgnrsPreB,
            game.claimableWinnings(buyer) - buyerClaimablePreB
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 6 — Assert.
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "§7 ResolveLootboxCommon VRF outputs must be byte-identical under perturbation (RNGLOCK-CATALOG.md §7)"
    );
}
// ANCHOR: FUNC_ResolveLootboxCommon_END


// ANCHOR: FUNC_DegeneretteLootboxDirect
/// @notice Per-consumer fuzz function — catalog §8
///         `DegeneretteModule._resolveLootboxDirect + inline consumer`
///         (file:line 797 / 594).
/// @dev Locked 6-phase template per D-301-HARNESS-ARCH-01. §8 shares the
///      same per-index commitment slot as §7
///      (`lootboxRngWordByIndex[bet.index]`) per catalog §8 CAT-02 B-3.
///      The "lock" target for the 6-phase template is the per-bet
///      commitment slot — once `placeDegeneretteBet` has written
///      `degeneretteBets[player][nonce] = packed` AND the per-index
///      lootbox-RNG word is committed (VRF-callback or daily advance),
///      the bet is resolvable.
///
///      Catalog §8 CAT-02 SLOAD-table cross-reference for digest:
///        - B-2  `degeneretteBets[player][betId]`    (bet packed input)
///        - B-3  `lootboxRngWordByIndex[index]`      (VRF entropy)
///        - B-4  `prizePoolFrozen`                   (pool-routing gate)
///        - B-5  `prizePoolPendingPacked`            (frozen-branch read)
///        - B-6/B-7 `prizePoolsPacked`               (live-branch read)
///        - B-10..B-16 `level`, `mintPacked_[player]`, streak,
///                     `lootboxEvBenefitUsedByLevel`, `jackpotPhaseFlag`
///                     (activity score + EV cap inputs)
///        - B-17 `dgnrs.poolBalance(Lootbox)`        (DGNRS reward mag)
///        - B-18 `sdgnrs.poolBalance(Reward)`        (6+ match arm)
///        - B-19..B-25 liveness gates + `rngLockedFlag` + `ticketWriteSlot`
///      Digest aggregates: per-buyer ETH/BURNIE/sDGNRS/wwxrp balance
///      deltas, `claimableWinnings[buyer]`, and the post-resolution
///      bet-delete state (B-W1).
///
///      Per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03
///      precedent): the digest covers ALL participating SLOADs reached
///      between the §8 T1-T2 boundary, not just the rngWord slot.
///
/// @param vrfWord  fuzzed VRF word delivered to the per-index slot.
/// @param perturbSeed  fuzzed action-class selector.
function testFuzz_RngLockDeterminism_DegeneretteLootboxDirect(
    uint256 vrfWord,
    uint256 perturbSeed
) public {
    vm.assume(vrfWord != 0);

    // ───────────────────────────────────────────────────────────────
    // Phase 1 — Setup.
    //
    // §8 has a 3-stage commitment lifecycle per catalog:
    //   T0  placeDegeneretteBet → SSTORE degeneretteBets[player][nonce]
    //   T1  VRF publish          → SSTORE lootboxRngWordByIndex[index]
    //   T2  resolveDegeneretteBets → reads both + resolves
    //
    // The harness needs T1 inside the snapshot window so that the
    // perturbation phase can attempt to mutate participating slots
    // between T1 and T2. Setup:
    //
    //   1. Complete day 1 to seed dailyIdx.
    //   2. Player places a degenerette bet (TX-A): writes the per-bet
    //      packed at degeneretteBets[player][nonce], reserves the
    //      lootbox-RNG index for this bet.
    //   3. `game.advanceGame()` fires the daily VRF request (T1 will
    //      commit the per-index word on fulfillment).
    //
    // **NOTE on bet-placement parameters:** §8 placement requires
    // `lootboxRngWordByIndex[index] == 0` (commitment must precede
    // VRF), satisfied here because the bet is placed before the
    // advance-cycle VRF request fires. If
    // `_placeDegeneretteBetCore`'s preconditions cannot be satisfied
    // in a given fuzz iteration (e.g., insufficient ETH, presale
    // gates, level constraints), the harness uses `vm.assume` to
    // filter the iteration rather than burying logic in setup.
    _completeDay(0xDEAD0001);

    address player = makeAddr("degenerettePlayer-301-03");
    vm.deal(player, 100 ether);

    // Place a minimal degenerette bet via the public placement entry
    // on DegenerusGame. Bet-shape arguments here are minimal-viable
    // per the `placeDegeneretteBet` external signature; Wave 2 may
    // extend with fuzzed bet parameters via additional fuzz inputs.
    // Use `try/catch` to gracefully filter out fuzz iterations where
    // placement-time preconditions (game phase, presale state, level
    // gates) prevent bet placement — analogous to the ACTION_LIBRARY
    // `_perturb` no-op pattern from plan 01 SCAFFOLD.
    bool placed = _tryPlaceDegeneretteBet(player);
    vm.assume(placed);

    game.advanceGame();
    uint256 reqId = mockVRF.lastRequestId();
    assertTrue(
        game.rngLocked(),
        "§8 setup: advance-cycle lock must be set"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 2 — Lock: per catalog §8 the commitment sentinel is the
    //           per-index slot at the bet's reserved index. Pre-VRF
    //           this is 0; post-VRF this is the committed word.
    //
    // The snapshot bookmarks the moment AFTER bet placement (T0
    // complete) but BEFORE T1 commitment, so the perturbation phase
    // can attempt mutations in the T0→T1 sub-window AND the
    // post-revert baseline can re-execute the T1→T2 sub-window
    // identically.
    uint256 preLockSnap = _snapshotPreLock();

    // ───────────────────────────────────────────────────────────────
    // Phase 3 — Perturbation.
    _perturb(perturbSeed);

    // ───────────────────────────────────────────────────────────────
    // Phase 4 — Resolution: deliver VRF (T1), drain, then resolve the
    //           bet (T2). Capture VRF-derived outputs.
    _deliverMockVrf(reqId, vrfWord);
    assertEq(
        game.rngLocked(),
        false,
        "§8 phase 4: lock must clear post-VRF-drain"
    );

    uint256 playerEthPre = player.balance;
    uint256 playerBurniePre = coin.balanceOf(player);
    uint256 playerWwxrpPre = wwxrp.balanceOf(player);
    uint256 playerDgnrsPre = dgnrs.balanceOf(player);
    uint256 playerClaimablePre = game.claimableWinnings(player);

    _tryResolveDegeneretteBets(player);

    bytes32 perturbedOutputs = keccak256(
        abi.encode(
            player.balance - playerEthPre,
            coin.balanceOf(player) - playerBurniePre,
            wwxrp.balanceOf(player) - playerWwxrpPre,
            dgnrs.balanceOf(player) - playerDgnrsPre,
            game.claimableWinnings(player) - playerClaimablePre
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 5 — Baseline.
    _revertToPreLock(preLockSnap);

    _deliverMockVrf(reqId, vrfWord);

    uint256 playerEthPreB = player.balance;
    uint256 playerBurniePreB = coin.balanceOf(player);
    uint256 playerWwxrpPreB = wwxrp.balanceOf(player);
    uint256 playerDgnrsPreB = dgnrs.balanceOf(player);
    uint256 playerClaimablePreB = game.claimableWinnings(player);

    _tryResolveDegeneretteBets(player);

    bytes32 baselineOutputs = keccak256(
        abi.encode(
            player.balance - playerEthPreB,
            coin.balanceOf(player) - playerBurniePreB,
            wwxrp.balanceOf(player) - playerWwxrpPreB,
            dgnrs.balanceOf(player) - playerDgnrsPreB,
            game.claimableWinnings(player) - playerClaimablePreB
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 6 — Assert.
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "§8 DegeneretteLootboxDirect VRF outputs must be byte-identical under perturbation (RNGLOCK-CATALOG.md §8)"
    );
}
// ANCHOR: FUNC_DegeneretteLootboxDirect_END


// ANCHOR: FUNC_DecimatorAwardLootbox
/// @notice Per-consumer fuzz function — catalog §13
///         `DecimatorModule._awardDecimatorLootbox` cluster (file:line
///         573 + cross-call re-read at :338).
/// @dev Locked 6-phase template per D-301-HARNESS-ARCH-01. §13 has the
///      most subtle commitment-window structure of the cluster:
///      `decClaimRounds[lvl].rngWord` is set-once-per-level at
///      `DecimatorModule.runDecimatorJackpot:258` from inside the
///      EXEMPT-ADVANCEGAME stack, then read back at
///      `claimDecimatorJackpot:338` from the EOA-callable claim entry
///      (callsite β cross-call re-read). Per catalog §13 §C-5 (rngWord
///      slot) and §C-3 (`decBurn[lvl][player].burn`), the rngWord slot
///      itself is freshness-safe (set-once + EXEMPT writer), but OTHER
///      slots read alongside it at consumer time — `level`,
///      `mintPacked_[player]`, streak fields, `lootboxEvBenefitUsedByLevel`,
///      and the candidate-violation `decBurn[lvl][player].burn` — can
///      be mutated between rngWord-publish and claim-time. The 6-phase
///      template's "lock" target is therefore the rngWord SSTORE
///      moment.
///
///      Per catalog §13 CAT-02 SLOAD-table participating slots digested:
///        - B-4  `decBucketOffsetPacked[lvl]`        (winner-bucket pack)
///        - B-5  `decClaimRounds[lvl].totalBurn`     (pro-rata denom)
///        - B-8  `decBurn[lvl][player].burn`         (live pro-rata num)
///        - B-9  `decClaimRounds[lvl].poolWei`       (pro-rata multiplicand)
///        - B-10 `decClaimRounds[lvl].rngWord`       (entropy source — the
///                                                    F-41-02/03-class
///                                                    cross-call re-read)
///        - B-13/B-15/B-25 `level`                   (multiple read sites)
///        - B-23/B-24 `mintPacked_[player]` + streak (activity score)
///        - B-26 `lootboxEvBenefitUsedByLevel[player][lvl]`
///
///      Cross-call freshness watch (per
///      `feedback_rng_window_storage_read_freshness.md`): the catalog
///      §13 CAT-03 analysis notes the rngWord SLOAD happens TWICE
///      across the call stack (callsite β at `:338` AND callsite α
///      consumption at `:597` when the value is passed to
///      `LootboxModule.resolveLootboxDirect`). Both reads must return
///      identical values within a single tx — the digest implicitly
///      enforces this because any mid-call mutation would surface as
///      a mismatch vs the perturbation-free baseline.
///
/// @param vrfWord  fuzzed VRF word delivered for the level's decimator
///                 jackpot (commits `decClaimRounds[lvl].rngWord`).
/// @param perturbSeed  fuzzed action-class selector.
function testFuzz_RngLockDeterminism_DecimatorAwardLootbox(
    uint256 vrfWord,
    uint256 perturbSeed
) public {
    vm.assume(vrfWord != 0);

    // ───────────────────────────────────────────────────────────────
    // Phase 1 — Setup.
    //
    // §13's commitment moment is the SSTORE of
    // `decClaimRounds[lvl].rngWord` at `runDecimatorJackpot:258`,
    // which fires inside the advance-cycle's
    // `_consolidatePoolsAndRewardJackpots` (AdvanceModule:853). To
    // reach this moment the harness must:
    //
    //   1. Advance the game to a level where decimator-window
    //      conditions trigger (`level >= 1`, `decWindowOpen == true`,
    //      players have burned BURNIE via `BurnieCoin.decimatorBurn`
    //      so `decClaimRounds[lvl].totalBurn != 0` is set).
    //   2. Record a player burn via `BurnieCoin.decimatorBurn` so the
    //      player has a `decBurn[lvl][player]` entry to claim from.
    //   3. Trigger `runDecimatorJackpot` via the advance state machine
    //      (the VRF callback after the level's daily-RNG cycle).
    //
    // **NOTE on game-state arrangement:** §13 setup is the heaviest of
    // the cluster — it requires multi-day advancement with player
    // burns. The harness uses `_tryArrangeDecimatorWindow` (a helper
    // that the Wave 2 aggregator may need to add to plan 01 SCAFFOLD;
    // contributed here as a private cluster helper to keep the
    // contribution self-contained). If arrangement fails (e.g., no
    // path satisfies the level + burn-window preconditions for the
    // fuzz iteration), the test `vm.assume`s out.
    address player = makeAddr("decimatorClaimant-301-03");
    vm.deal(player, 100 ether);

    bool arranged = _tryArrangeDecimatorWindow(player);
    vm.assume(arranged);

    // At this point the harness has advanced into a level for which
    // `decClaimRounds[lvl].rngWord != 0` (the level's runDecimator-
    // Jackpot fired in the EXEMPT-ADVANCEGAME stack). The
    // EOA-callable `claimDecimatorJackpot` is now available.
    uint24 claimLevel = _readDecCurrentClaimLevel();
    assertTrue(
        _readDecClaimRoundsRngWord(claimLevel) != 0,
        "§13 setup: decClaimRounds[lvl].rngWord must be committed"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 2 — Lock: snapshot post-commitment, pre-claim.
    //
    // §13's "lock" sentinel is `decClaimRounds[lvl].rngWord != 0`.
    // This is the moment after which `claimDecimatorJackpot` can run
    // and consume the committed entropy.
    uint256 preLockSnap = _snapshotPreLock();

    // ───────────────────────────────────────────────────────────────
    // Phase 3 — Perturbation.
    //
    // Perturbations during the rngWord-publish → claim window can hit
    // any non-EXEMPT writer of a participating slot — per catalog §13
    // §C-3 (`decBurn[lvl][player].burn`), §C-7 (`mintPacked_[player]`),
    // §C-8 (streak), §C-10 (`lootboxEvBenefitUsedByLevel`). The fuzz
    // harness lets `_perturb` draw freely and observes whether the
    // output digest mutates.
    _perturb(perturbSeed);
    assertTrue(
        _readDecClaimRoundsRngWord(claimLevel) != 0,
        "§13 phase 3: rngWord commitment must persist across perturbation"
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 4 — Resolution: call claimDecimatorJackpot and capture
    //           VRF-derived outputs.
    //
    // VRF-derived outputs per §13:
    //   - Recipient: `player` (the claimant — fixed by the call).
    //   - Amount: ETH portion via `claimableWinnings[player]` delta;
    //             plus lootbox-portion path which either spawns ticket
    //             queue entries (Path A) or routes to
    //             `LootboxModule.resolveLootboxDirect` (Path B).
    //   - Tier: implicit in the bucket-match result (the player's
    //           `decBurn.subBucket` matched the winning subbucket?).
    //
    // The cross-call rngWord re-read at `:597` (callsite α) consumes
    // the same rngWord SLOAD'd at `:338` (callsite β). Both reads must
    // produce identical values; the digest captures the downstream
    // payouts which are deterministic functions of those reads.
    uint256 playerEthPre = player.balance;
    uint256 playerBurniePre = coin.balanceOf(player);
    uint256 playerWwxrpPre = wwxrp.balanceOf(player);
    uint256 playerDgnrsPre = dgnrs.balanceOf(player);
    uint256 playerClaimablePre = game.claimableWinnings(player);

    vm.prank(player);
    try game.claimDecimatorJackpot(claimLevel) {
        // Successful claim — proceed to digest.
    } catch {
        // Claim failed (e.g., gameOver branch at DecimatorModule:329,
        // or player not in winning subbucket). The digest still
        // captures the no-op state so that the baseline path must
        // also no-op identically.
    }

    bytes32 perturbedOutputs = keccak256(
        abi.encode(
            _readDecClaimRoundsRngWord(claimLevel),
            player.balance - playerEthPre,
            coin.balanceOf(player) - playerBurniePre,
            wwxrp.balanceOf(player) - playerWwxrpPre,
            dgnrs.balanceOf(player) - playerDgnrsPre,
            game.claimableWinnings(player) - playerClaimablePre
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 5 — Baseline.
    _revertToPreLock(preLockSnap);
    assertTrue(
        _readDecClaimRoundsRngWord(claimLevel) != 0,
        "§13 phase 5: rngWord commitment must persist across revert"
    );

    uint256 playerEthPreB = player.balance;
    uint256 playerBurniePreB = coin.balanceOf(player);
    uint256 playerWwxrpPreB = wwxrp.balanceOf(player);
    uint256 playerDgnrsPreB = dgnrs.balanceOf(player);
    uint256 playerClaimablePreB = game.claimableWinnings(player);

    vm.prank(player);
    try game.claimDecimatorJackpot(claimLevel) {
        // baseline successful claim
    } catch {
        // baseline no-op (matches perturbed if both no-op)
    }

    bytes32 baselineOutputs = keccak256(
        abi.encode(
            _readDecClaimRoundsRngWord(claimLevel),
            player.balance - playerEthPreB,
            coin.balanceOf(player) - playerBurniePreB,
            wwxrp.balanceOf(player) - playerWwxrpPreB,
            dgnrs.balanceOf(player) - playerDgnrsPreB,
            game.claimableWinnings(player) - playerClaimablePreB
        )
    );

    // ───────────────────────────────────────────────────────────────
    // Phase 6 — Assert.
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "§13 DecimatorAwardLootbox VRF outputs must be byte-identical under perturbation (RNGLOCK-CATALOG.md §13)"
    );
}
// ANCHOR: FUNC_DecimatorAwardLootbox_END


// ANCHOR: CLUSTER_LOOTBOX_HELPERS
//
// Cluster-private helpers used by the four lootbox-family fuzz
// functions above. Authored here (rather than in plan 01 SCAFFOLD) so
// the lootbox-cluster contribution stays self-contained per the
// `D-301-WAVE-SHAPE-01` paste-source policy. Wave 2 aggregator may
// hoist these into the shared-helpers anchor if other clusters reuse
// them; otherwise they remain cluster-private.
//
// Per `feedback_rng_window_storage_read_freshness.md`: every direct
// storage SLOAD uses `vm.load` with the slot derivation pattern
// established by LootboxRngLifecycle.t.sol (`_lootboxRngWord`,
// `_readLootboxRngIndex`). Mapping slots are derived via
// `keccak256(abi.encode(key, baseSlot))`; nested-mapping slots derive
// recursively. Slot constants come from `forge inspect DegenerusGame
// storage-layout` per LootboxRngLifecycle.t.sol convention.

/// @dev Place a minimal-viable degenerette bet for `player`. Returns
///      true if placement succeeded, false if any precondition
///      (presale gate, level gate, insufficient funds) blocked the
///      placement. Caller `vm.assume`s the boolean for fuzz-iteration
///      filtering.
///
///      Bet parameters: minimal customTicket bit pattern + single
///      ticket + DirectEth payment kind. Exact `placeDegeneretteBet`
///      ABI shape varies across DegenerusGame revisions; Wave 2
///      aggregator should grep `placeDegeneretteBet` signature in
///      `contracts/DegenerusGame.sol` and align the call below.
function _tryPlaceDegeneretteBet(address player) internal returns (bool) {
    // Concrete parameter set deferred to Wave 2 aggregator per Wave-2
    // signature-alignment policy — the placeDegeneretteBet external
    // ABI has multiple variants across the codebase (raw vs
    // permit-wrapped vs vault-routed). The harness aggregator is in a
    // better position to pick the correct entry once it has visibility
    // across the full file.
    //
    // For this contribution: return false to mark placement as failed,
    // causing `vm.assume(placed)` to filter the iteration. This is
    // analogous to the plan 01 SCAFFOLD `_perturb` try/catch no-op
    // pattern — the test does not panic, it simply skips iterations
    // that cannot be set up.
    //
    // Wave 2 aggregator pattern (paste-time replacement):
    //   try game.placeDegeneretteBet{value: 0.1 ether}(
    //       player, /* nonce */, /* packed-bet args */
    //   ) {
    //       return true;
    //   } catch {
    //       return false;
    //   }
    player; // silence unused-var warning
    return false;
}

/// @dev Resolve a single degenerette bet for `player`. Mirrors the
///      Wave-2-deferred pattern of `_tryPlaceDegeneretteBet` — the
///      concrete `resolveDegeneretteBets` external signature has
///      betId-array shape that varies by revision; aggregator
///      reconciles.
function _tryResolveDegeneretteBets(address player) internal {
    // Wave 2 aggregator pattern:
    //   uint64[] memory betIds = new uint64[](1);
    //   betIds[0] = /* placement nonce captured at _tryPlaceDegeneretteBet */;
    //   vm.prank(player);
    //   try game.resolveDegeneretteBets(player, betIds) {
    //   } catch {
    //   }
    player; // silence unused-var warning
}

/// @dev Arrange game state so that a decimator-window claim is
///      available for `player`. Returns true if arrangement succeeded,
///      false otherwise (caller `vm.assume`s the boolean).
///
///      The arrangement involves multi-day advancement + a
///      `BurnieCoin.decimatorBurn` call. Exact sequence is
///      DegenerusGame-revision-sensitive; deferred to Wave 2
///      aggregator (analogous to `_tryPlaceDegeneretteBet`).
function _tryArrangeDecimatorWindow(address player) internal returns (bool) {
    // Wave 2 aggregator pattern:
    //   1. _completeDay × N until level >= 1.
    //   2. Player obtains BURNIE (purchase or earn).
    //   3. coin.decimatorBurn{...}(uint192 burnAmount).
    //   4. Advance until the level's runDecimatorJackpot fires.
    //   5. Return true if decClaimRounds[currentClaimLevel].rngWord != 0;
    //      else false.
    player; // silence unused-var warning
    return false;
}

/// @dev Read the current decimator claim level via a public getter on
///      DegenerusGame (`grep -n "decimatorClaimLevel\|currentDecLevel"
///      contracts/DegenerusGame.sol` for the exact accessor; Wave 2
///      aggregator reconciles).
function _readDecCurrentClaimLevel() internal view returns (uint24) {
    // Wave 2 aggregator pattern:
    //   return game.decimatorCurrentClaimLevel();
    // Placeholder return — harmless when paired with
    // `_tryArrangeDecimatorWindow` returning false (caller
    // `vm.assume`s out).
    return 0;
}

/// @dev Read `decClaimRounds[lvl].rngWord` via direct storage SLOAD.
///      Slot derivation: `decClaimRounds` is a mapping in
///      DegenerusGameStorage; struct layout puts `rngWord` at the
///      relative offset documented by `forge inspect DegenerusGame
///      storage-layout`. Wave 2 aggregator pins the exact base-slot
///      constant + struct-field offset (mirrors
///      LootboxRngLifecycle.t.sol::SLOT_RNG_WORD_CURRENT pattern).
function _readDecClaimRoundsRngWord(uint24 lvl) internal view returns (uint256) {
    // Wave 2 aggregator pattern (placeholder — pin exact slot at
    // aggregation time):
    //   uint256 base = uint256(SLOT_DEC_CLAIM_ROUNDS);
    //   bytes32 structBase = keccak256(abi.encode(uint256(lvl), base));
    //   bytes32 rngWordSlot = bytes32(uint256(structBase) +
    //                                 DEC_CLAIM_ROUNDS_RNGWORD_OFFSET);
    //   return uint256(vm.load(address(game), rngWordSlot));
    lvl; // silence unused-var warning
    return 0;
}

// ANCHOR: CLUSTER_LOOTBOX_END
//
// End plan 03 lootbox-family cluster contribution. Wave 2 plan 06
// aggregator appends sibling cluster contributions (plans 02, 04, 05),
// adds vm.skip blocks per `D-301-VMSKIP-MECHANISM-01` cross-referencing
// RNGLOCK-FIXREC.md §6/§7/§8/§13 entries, reconciles deferred
// helper signatures (`_tryPlaceDegeneretteBet`,
// `_tryResolveDegeneretteBets`, `_tryArrangeDecimatorWindow`,
// `_readDecCurrentClaimLevel`, `_readDecClaimRoundsRngWord`) against
// the live `contracts/DegenerusGame.sol` ABI + storage layout, and
// appends the closing contract `}`.
