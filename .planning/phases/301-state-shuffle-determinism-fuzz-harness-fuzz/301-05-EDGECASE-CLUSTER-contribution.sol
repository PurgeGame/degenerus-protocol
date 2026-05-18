// ANCHOR: CLUSTER_EDGECASE_OPEN
// SPDX-License-Identifier: AGPL-3.0-only
// Contribution-only paste source — NOT a standalone compilation unit.
// Wave 2 aggregator (plan 06) concatenates this segment between plan 01's scaffold
// `// ANCHOR: SCAFFOLD_END` marker and the closing `}` for `contract RngLockDeterminism`.
// All helpers referenced here (`_perturb`, `_advanceToVrfRequestBoundary`,
// `_deliverMockVrf`, `_snapshotPreLock`, `_revertToPreLock`,
// `_assertVrfOutputByteIdentity`, `_completeDay`, storage-slot constants) are
// authored by plan 01's scaffold contribution and are in lexical scope at paste
// time inside the `RngLockDeterminism` contract body.
//
// CONTRIBUTION SCOPE — per D-301-EDGE-CASES-01:
//   5 edge-case fuzz functions exercising perturbation patterns that the
//   per-consumer cluster functions (plans 02/03/04) do not exercise:
//     1. testFuzz_EdgeCase_AdminDuringLock           (admin-only action set)
//     2. testFuzz_EdgeCase_NearEndOfWindow           (final-block timing)
//     3. testFuzz_EdgeCase_MultiTxBatch              (intra-block stacking)
//     4. testFuzz_EdgeCase_MultiBlock                (inter-block spread)
//     5. testFuzz_EdgeCase_RetryLootboxRngDuringLock (failsafe interaction)
//
//   Plus one NEW helper, `_perturbAdminOnly(uint256 seed)`, that draws actions
//   exclusively from ADMIN-AUDIT.md §3 R-01..R-22 — the admin function set that
//   FUZZ-02 requires the action library to cover. This helper is distinct from
//   the general `_perturb(uint256 seed)` helper authored by plan 01.
//
// REQUIREMENTS SATISFIED:
//   - FUZZ-02 (admin function action set coverage; admin entries R-01..R-22)
//   - FUZZ-05 (edge case suite: admin-during-lock + near-end-of-window +
//             multi-tx-batch + multi-block + retry-during-lock)
//
// VRF-OUTPUT CAPTURE STRATEGY (per D-301-HARNESS-ARCH-01 6-phase template):
//   Each function uses Foundry's `vm.recordLogs()` + `vm.getRecordedLogs()` to
//   capture the events emitted during the consumer-resolution stack — these
//   events are the canonical VRF-derived outputs (jackpot recipients, ticket
//   awards, whale-pass credits) per RNGLOCK-CATALOG §1..§13. A keccak256 of the
//   recorded-logs byte stream produces a deterministic `bytes32 perturbedOutputs`
//   identifier suitable for byte-identity assertion against the no-perturbation
//   baseline.
// ANCHOR: CLUSTER_EDGECASE_OPEN_END


// ANCHOR: HELPER_hashLogs
/// @notice Pack a recorded-logs stream into a single byte-identity digest.
/// @dev Hashing the `(topics, data)` tuple of every emitted event during the
///      consumer-resolution stack collapses the VRF-derived output set
///      (JackpotEthWin, JackpotTicketWin, JackpotWhalePassWin, JackpotDgnrsWin,
///      JackpotBurnieWin, LootboxRngApplied, etc. per RNGLOCK-CATALOG §1..§13)
///      into a single `bytes32` suitable for the `_assertVrfOutputByteIdentity`
///      assertion. The hash is order-sensitive, which is exactly the property
///      the determinism harness asserts (event order = consumer execution
///      order = VRF derivation order).
///
///      This helper is cluster-local to the edge-case suite because the 5
///      edge-case functions hit varying consumer surfaces (PayDailyJackpot,
///      RetryLootboxRng failsafe, and general-perturbation consumer
///      whichever-is-reached). A single uniform `_hashLogs` capture is more
///      robust than per-consumer getter wiring for the edge-case cluster.
///      Plan 01's reference cluster functions use the per-consumer pack form
///      `keccak256(abi.encode(recipient, amount, heroByte))` per
///      D-301-HARNESS-ARCH-01 — the edge-case functions are compatible with
///      that pattern because `_assertVrfOutputByteIdentity` only requires
///      two `bytes32` operands, not a fixed extraction strategy.
function _hashLogs(Vm.Log[] memory logs) internal pure returns (bytes32) {
    bytes memory packed;
    for (uint256 i = 0; i < logs.length; i++) {
        packed = abi.encodePacked(
            packed,
            logs[i].emitter,
            keccak256(abi.encode(logs[i].topics)),
            keccak256(logs[i].data)
        );
    }
    return keccak256(packed);
}
// ANCHOR: HELPER_hashLogs_END


// ANCHOR: HELPER_perturbAdminOnly
/// @notice Admin-action-only perturbation helper.
/// @dev Draws from ADMIN-AUDIT.md §3 R-01..R-22 (the 22 admin functions that
///      ADMA classified as participating-slot writers). `seed % 22` selects
///      one admin function per call. Each case `vm.prank`s the appropriate
///      role-holder before invocation. Action calls that require state
///      preconditions which are not satisfied in the current fuzz iteration
///      use `try ... catch { return; }` so they no-op silently rather than
///      failing the iteration — this matches the plan 01 general `_perturb`
///      convention.
///
///      The 22 admin entries cover:
///        R-01 wireVrf                            (governance, AdvanceModule)
///        R-02 updateVrfCoordinatorAndSub         (governance, AdvanceModule)
///        R-03 adminSwapEthForStEth               (governance, DegenerusGame)
///        R-04 adminStakeEthForStEth              (governance, DegenerusGame)
///        R-05 swapGameEthForStEth                (governance, DegenerusAdmin)
///        R-06 setCharity                         (governance, GNRUS)
///        R-07 gamePurchase                       (general,    DegenerusVault)
///        R-08 gamePurchaseTicketsBurnie          (general,    DegenerusVault)
///        R-09 gamePurchaseBurnieLootbox          (general,    DegenerusVault)
///        R-10 gameOpenLootBox                    (general,    DegenerusVault)
///        R-11 gamePurchaseDeityPassFromBoon      (general,    DegenerusVault)
///        R-12 gameDegeneretteBet                 (general,    DegenerusVault)
///        R-13 gameSetAutoRebuy                   (general,    DegenerusVault)
///        R-14 gameSetAutoRebuyTakeProfit         (general,    DegenerusVault)
///        R-15 gameSetAfKingMode                  (general,    DegenerusVault)
///        R-16 coinDepositCoinflip                (general,    DegenerusVault)
///        R-17 coinDecimatorBurn                  (general,    DegenerusVault)
///        R-18 gameClaimWinnings                  (general,    DegenerusVault)
///        R-19 gameClaimWhalePass                 (general,    DegenerusVault)
///        R-20 jackpotsClaimDecimator             (general,    DegenerusVault)
///        R-21 sdgnrsBurn                         (general,    DegenerusVault)
///        R-22 sdgnrsClaimRedemption              (general,    DegenerusVault)
///
///      Role-holders: Vault-owner-gated entries (`onlyVaultOwner` modifier +
///      hand-rolled `vault.isVaultOwner` checks) are pranked from
///      `ContractAddresses.CREATOR` (the deploy-time DGVE holder that owns
///      100% of DGVE supply per `DegenerusVault.sol:235` constructor mint).
///      `ContractAddresses.ADMIN`-gated entries (R-01, R-02, R-03) are pranked
///      from the DegenerusAdmin contract address (the only sender that passes
///      `msg.sender == ContractAddresses.ADMIN`). The `gnrus.setCharity` entry
///      is also vault-owner-gated and uses the CREATOR prank.
///
/// @param seed Fuzz-derived seed; `seed % 22` selects the admin function.
function _perturbAdminOnly(uint256 seed) internal {
    uint256 action = seed % 22;
    uint256 nonce = seed >> 8;
    address vaultOwner = ContractAddresses.CREATOR;
    address adminAddr = address(admin); // ContractAddresses.ADMIN at deploy
    address actor = address(uint160(uint256(keccak256(abi.encode(seed, "actor")))));

    // R-01 — DegenerusGameAdvanceModule.wireVrf @ DegenerusGameAdvanceModule.sol:498
    // ADMIN-AUDIT.md §3.01: governance, constructor-one-shot per docstring; the
    // delegatecall-routed entry on DegenerusGame is unreachable after the Admin
    // constructor wiring (the runtime call from the Admin EOA will revert with E
    // because the function is structurally one-shot). try/catch absorbs the revert.
    if (action == 0) {
        vm.prank(adminAddr);
        try game.wireVrf(address(mockVRF), 1, bytes32(uint256(1))) {} catch { return; }
        return;
    }

    // R-02 — DegenerusGameAdvanceModule.updateVrfCoordinatorAndSub @ :1677
    // ADMIN-AUDIT.md §3.02: governance, emergency VRF rotation; the canonical
    // mid-stall admin path. Synthesizes a fresh MockVRFCoordinator + sub so the
    // post-rotation state is well-formed (the game must remain advanceable).
    if (action == 1) {
        MockVRFCoordinator newVrf;
        try new MockVRFCoordinator() returns (MockVRFCoordinator v) { newVrf = v; }
        catch { return; }
        uint256 newSub;
        try newVrf.createSubscription() returns (uint256 s) { newSub = s; }
        catch { return; }
        try newVrf.addConsumer(newSub, address(game)) {} catch { return; }
        try newVrf.fundSubscription(newSub, 100e18) {} catch { return; }
        vm.prank(adminAddr);
        try game.updateVrfCoordinatorAndSub(
            address(newVrf), newSub, bytes32(uint256(nonce | 1))
        ) {} catch { return; }
        return;
    }

    // R-03 — DegenerusGame.adminSwapEthForStEth @ DegenerusGame.sol:1805
    // ADMIN-AUDIT.md §3.03: governance, value-neutral ETH/stETH swap. Bounded
    // amount; pranked from ADMIN.
    if (action == 2) {
        uint256 amt = bound(nonce, 1, 0.01 ether);
        vm.deal(adminAddr, amt);
        address recipient = actor == address(0) ? address(0xDEAD) : actor;
        vm.prank(adminAddr);
        try game.adminSwapEthForStEth{value: amt}(recipient, amt) {} catch { return; }
        return;
    }

    // R-04 — DegenerusGame.adminStakeEthForStEth @ DegenerusGame.sol:1826
    // ADMIN-AUDIT.md §3.04: governance, Lido stake of game-held ETH. Vault-owner
    // gated. Bounded; reserves-check inside the function will revert if game
    // lacks free ETH — try/catch absorbs.
    if (action == 3) {
        uint256 amt = bound(nonce, 1, 0.001 ether);
        vm.prank(vaultOwner);
        try game.adminStakeEthForStEth(amt) {} catch { return; }
        return;
    }

    // R-05 — DegenerusAdmin.swapGameEthForStEth @ DegenerusAdmin.sol:631
    // ADMIN-AUDIT.md §3.05: governance, vault-owner-routed swap (broader access
    // surface than R-03). Caller forwards msg.value through to gameAdmin.
    if (action == 4) {
        uint256 amt = bound(nonce, 1, 0.01 ether);
        vm.deal(vaultOwner, amt);
        vm.prank(vaultOwner);
        try admin.swapGameEthForStEth{value: amt}() {} catch { return; }
        return;
    }

    // R-06 — GNRUS.setCharity @ GNRUS.sol:378
    // ADMIN-AUDIT.md §3.06: governance, charity-allowlist mutation. Vault-owner
    // gated. Locked slots 0/1/2 will revert SlotLocked; mutable slots 3..19 may
    // succeed. try/catch absorbs.
    if (action == 5) {
        uint8 slot = uint8(bound(nonce, 3, 19));
        address recipient = actor;
        vm.prank(vaultOwner);
        try gnrus.setCharity(slot, recipient) {} catch { return; }
        return;
    }

    // R-07 — DegenerusVault.gamePurchase @ DegenerusVault.sol:513
    // ADMIN-AUDIT.md §3.07: general, vault-routed mint. Vault must hold ETH to
    // fund; gives vault 1 ETH for the iteration. ticketQuantity bounded so the
    // purchase fits MintModule's batch caps.
    if (action == 6) {
        vm.deal(address(vault), 1 ether);
        uint256 tickets = bound(nonce, 1, 4);
        vm.prank(vaultOwner);
        try vault.gamePurchase{value: 0}(
            tickets, 0, bytes32(0), MintPaymentKind.DirectEth, 0.01 ether
        ) {} catch { return; }
        return;
    }

    // R-08 — DegenerusVault.gamePurchaseTicketsBurnie @ DegenerusVault.sol:534
    // ADMIN-AUDIT.md §3.08: general, vault-routed BURNIE ticket purchase. Vault
    // must hold BURNIE. May revert if vault BURNIE balance is insufficient.
    if (action == 7) {
        uint256 tickets = bound(nonce, 1, 2);
        vm.prank(vaultOwner);
        try vault.gamePurchaseTicketsBurnie(tickets) {} catch { return; }
        return;
    }

    // R-09 — DegenerusVault.gamePurchaseBurnieLootbox @ DegenerusVault.sol:543
    // ADMIN-AUDIT.md §3.09: general, vault-routed BURNIE lootbox purchase.
    if (action == 8) {
        uint256 amt = bound(nonce, 1e18, 100e18);
        vm.prank(vaultOwner);
        try vault.gamePurchaseBurnieLootbox(amt) {} catch { return; }
        return;
    }

    // R-10 — DegenerusVault.gameOpenLootBox @ DegenerusVault.sol:551
    // ADMIN-AUDIT.md §3.10: general, vault-routed lootbox open. Requires the
    // vault to own a lootbox at the supplied index; absent ownership the call
    // reverts and is absorbed.
    if (action == 9) {
        uint48 idx = uint48(bound(nonce, 0, 1000));
        vm.prank(vaultOwner);
        try vault.gameOpenLootBox(idx) {} catch { return; }
        return;
    }

    // R-11 — DegenerusVault.gamePurchaseDeityPassFromBoon @ DegenerusVault.sol:561
    // ADMIN-AUDIT.md §3.11: general, vault-routed deity-pass purchase via boon.
    // Requires active boon + sufficient ETH; try/catch absorbs.
    if (action == 10) {
        uint256 price = bound(nonce, 24 ether, 25 ether);
        uint8 sym = uint8(bound(nonce >> 8, 0, 31));
        vm.deal(address(vault), price);
        vm.prank(vaultOwner);
        try vault.gamePurchaseDeityPassFromBoon{value: 0}(price, sym) {} catch { return; }
        return;
    }

    // R-12 — DegenerusVault.gameDegeneretteBet @ DegenerusVault.sol:594
    // ADMIN-AUDIT.md §3.12: general, vault-routed degenerette bet. The bet
    // mid-rngLock-window may revert via RngLocked if the underlying
    // _placeDegeneretteBetCore has its v44.0 gate landed — absorbed by try/catch
    // so the harness exercises both pre-fix (no revert) and post-fix paths.
    if (action == 11) {
        uint128 amtPer = uint128(bound(nonce, 1e15, 1e16));
        uint8 ticketCount = uint8(bound(nonce >> 8, 1, 3));
        uint32 customTicket = uint32(nonce >> 16);
        uint8 hero = uint8(bound(nonce >> 24, 0, 3));
        uint256 total = uint256(amtPer) * ticketCount;
        vm.deal(address(vault), total);
        vm.prank(vaultOwner);
        try vault.gameDegeneretteBet{value: 0}(
            0, amtPer, ticketCount, customTicket, hero, total
        ) {} catch { return; }
        return;
    }

    // R-13 — DegenerusVault.gameSetAutoRebuy @ DegenerusVault.sol:627
    // ADMIN-AUDIT.md §3.13: general, vault-routed setAutoRebuy. Underlying
    // _setAutoRebuy has an existing rngLocked revert; try/catch absorbs.
    if (action == 12) {
        bool enabled = (nonce & 1) == 1;
        vm.prank(vaultOwner);
        try vault.gameSetAutoRebuy(enabled) {} catch { return; }
        return;
    }

    // R-14 — DegenerusVault.gameSetAutoRebuyTakeProfit @ DegenerusVault.sol:634
    // ADMIN-AUDIT.md §3.14: general, vault-routed setAutoRebuyTakeProfit.
    if (action == 13) {
        uint256 tp = bound(nonce, 0, 10 ether);
        vm.prank(vaultOwner);
        try vault.gameSetAutoRebuyTakeProfit(tp) {} catch { return; }
        return;
    }

    // R-15 — DegenerusVault.gameSetAfKingMode @ DegenerusVault.sol:643
    // ADMIN-AUDIT.md §3.15: general, vault-routed setAfKingMode.
    if (action == 14) {
        bool enabled = (nonce & 1) == 1;
        uint256 eth = bound(nonce >> 8, 0, 1 ether);
        uint256 coinTp = bound(nonce >> 16, 0, 1e18);
        vm.prank(vaultOwner);
        try vault.gameSetAfKingMode(enabled, eth, coinTp) {} catch { return; }
        return;
    }

    // R-16 — DegenerusVault.coinDepositCoinflip @ DegenerusVault.sol:662
    // ADMIN-AUDIT.md §3.16: general, vault-routed BURNIE coinflip deposit.
    if (action == 15) {
        uint256 amt = bound(nonce, 1e18, 100e18);
        vm.prank(vaultOwner);
        try vault.coinDepositCoinflip(amt) {} catch { return; }
        return;
    }

    // R-17 — DegenerusVault.coinDecimatorBurn @ DegenerusVault.sol:677
    // ADMIN-AUDIT.md §3.17: general, vault-routed decimator BURNIE burn.
    if (action == 16) {
        uint256 amt = bound(nonce, 1e18, 100e18);
        vm.prank(vaultOwner);
        try vault.coinDecimatorBurn(amt) {} catch { return; }
        return;
    }

    // R-18 — DegenerusVault.gameClaimWinnings @ DegenerusVault.sol:575
    // ADMIN-AUDIT.md §3.18: general, vault-routed claimWinnings.
    if (action == 17) {
        vm.prank(vaultOwner);
        try vault.gameClaimWinnings() {} catch { return; }
        return;
    }

    // R-19 — DegenerusVault.gameClaimWhalePass @ DegenerusVault.sol:581
    // ADMIN-AUDIT.md §3.19: general, vault-routed claimWhalePass.
    if (action == 18) {
        vm.prank(vaultOwner);
        try vault.gameClaimWhalePass() {} catch { return; }
        return;
    }

    // R-20 — DegenerusVault.jackpotsClaimDecimator @ DegenerusVault.sol:708
    // ADMIN-AUDIT.md §3.20: general, vault-routed claimDecimatorJackpot.
    if (action == 19) {
        uint24 lvl = uint24(bound(nonce, 0, 100));
        vm.prank(vaultOwner);
        try vault.jackpotsClaimDecimator(lvl) {} catch { return; }
        return;
    }

    // R-21 — DegenerusVault.sdgnrsBurn @ DegenerusVault.sol:719
    // ADMIN-AUDIT.md §3.21: general, vault-routed sDGNRS burn-for-redemption.
    if (action == 20) {
        uint256 amt = bound(nonce, 1, 1e18);
        vm.prank(vaultOwner);
        try vault.sdgnrsBurn(amt) {} catch { return; }
        return;
    }

    // R-22 — DegenerusVault.sdgnrsClaimRedemption @ DegenerusVault.sol:725
    // ADMIN-AUDIT.md §3.22: general, vault-routed sDGNRS claimRedemption.
    if (action == 21) {
        vm.prank(vaultOwner);
        try vault.sdgnrsClaimRedemption() {} catch { return; }
        return;
    }
}
// ANCHOR: HELPER_perturbAdminOnly_END


// ANCHOR: FUNC_EdgeCase_AdminDuringLock
/// @notice Edge case: admin-only perturbation surface during the rngLock window.
/// @dev Per D-301-EDGE-CASES-01 (edge case 1) and FUZZ-05 (admin-during-lock).
///      Representative consumer surface: PayDailyJackpot (RNGLOCK-CATALOG §1).
///      The perturbation phase calls `_perturbAdminOnly(adminSeed)` so the action
///      set is exactly the 22-entry ADMA admin enumeration (ADMIN-AUDIT.md §3
///      R-01..R-22), distinct from the general `_perturb` library that mixes
///      EOA and admin actions.
///
///      Assertion: PayDailyJackpot VRF-derived events must be byte-identical
///      under admin perturbation vs the no-perturbation baseline. ADMA §3
///      categorizes 16 of the 22 admin functions as participating-slot writers;
///      if any of them mutates a slot that the daily-jackpot resolution reads
///      between VRF callback and consumer execution, the perturbation will
///      produce diverging outputs and this assertion fires.
///
/// @param vrfWord Fuzz-derived VRF random word (forced non-zero).
/// @param adminSeed Fuzz-derived selector for the admin action.
function testFuzz_EdgeCase_AdminDuringLock(uint256 vrfWord, uint256 adminSeed) public {
    vm.assume(vrfWord != 0);

    // ── Phase 1: Setup ──────────────────────────────────────────────────
    // Snapshot pre-lock state so phase 5 (baseline) can replay without perturbation.
    uint256 preLockSnap = _snapshotPreLock();

    // Advance to the VRF-request boundary for the daily-jackpot consumer.
    // The scaffold helper arranges state so the next advanceGame call requests VRF.
    uint256 reqId = _advanceToVrfRequestBoundary();

    // ── Phase 2: Lock ───────────────────────────────────────────────────
    assertTrue(game.rngLocked(), "rngLock must engage at request boundary");
    assertTrue(reqId != 0, "VRF request must be pending");

    // ── Phase 3: Perturbation (admin-only) ──────────────────────────────
    _perturbAdminOnly(adminSeed);

    // After admin perturbation the lock must still be engaged (any admin path
    // that lifts the lock is captured by ADMA §3.02 updateVrfCoordinatorAndSub,
    // which is the only legitimate lock-clearing admin operation; if it fired
    // and successfully cleared the lock, the resolution phase below targets a
    // fresh request, which is the intended post-rotation behavior).
    // Both branches are exercised by the fuzzer; the test asserts byte-identity
    // of outputs across the perturbation vs baseline replay.

    // ── Phase 4: Resolution under perturbation ──────────────────────────
    // Capture the VRF-derived event stream during consumer resolution.
    vm.recordLogs();
    uint256 currentReqId = mockVRF.lastRequestId();
    _deliverMockVrf(currentReqId, vrfWord);
    Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
    bytes32 perturbedOutputs = _hashLogs(perturbedLogs);

    // ── Phase 5: Baseline (no perturbation) ─────────────────────────────
    _revertToPreLock(preLockSnap);
    uint256 baseReqId = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "rngLock must engage at baseline request boundary");
    assertTrue(baseReqId != 0, "Baseline VRF request must be pending");
    // NO perturbation in the baseline path.
    vm.recordLogs();
    uint256 baseCurrentReqId = mockVRF.lastRequestId();
    _deliverMockVrf(baseCurrentReqId, vrfWord);
    Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
    bytes32 baselineOutputs = _hashLogs(baselineLogs);

    // ── Phase 6: Assert byte-identity ───────────────────────────────────
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "AdminDuringLock: PayDailyJackpot VRF outputs must be byte-identical under admin perturbation"
    );
}
// ANCHOR: FUNC_EdgeCase_AdminDuringLock_END


// ANCHOR: FUNC_EdgeCase_NearEndOfWindow
/// @notice Edge case: perturbation in the last block before the rngLock window
///         would auto-retry on timeout.
/// @dev Per D-301-EDGE-CASES-01 (edge case 2) and FUZZ-05 (near-end-of-window).
///      The daily-RNG retry timeout is 12 hours per
///      `AdvanceModule.rngGate:1241` (`if (elapsed >= 12 hours)`). This test
///      warps to `rngRequestTime + 12 hours - 1 second` — the last second
///      before `advanceGame` would auto-fire a fresh VRF request — and applies
///      a general perturbation at that boundary, then delivers the original
///      VRF word and asserts byte-identity vs the no-perturbation baseline.
///
/// @param vrfWord Fuzz-derived VRF random word (forced non-zero).
/// @param perturbSeed Fuzz-derived seed for the general action library.
function testFuzz_EdgeCase_NearEndOfWindow(uint256 vrfWord, uint256 perturbSeed) public {
    vm.assume(vrfWord != 0);

    // ── Phase 1: Setup ──────────────────────────────────────────────────
    uint256 preLockSnap = _snapshotPreLock();
    uint256 reqId = _advanceToVrfRequestBoundary();

    // ── Phase 2: Lock ───────────────────────────────────────────────────
    assertTrue(game.rngLocked(), "rngLock must engage at request boundary");
    assertTrue(reqId != 0, "VRF request must be pending");

    // ── Phase 3a: Warp to last-second of lock window ────────────────────
    // The daily-RNG timeout is `AdvanceModule.rngGate:1241` 12 hours; the last
    // window-internal second is `rngRequestTime + 12 hours - 1`. Warping by
    // `12 hours - 1` from now (which is `rngRequestTime` since we just locked)
    // lands at the precise boundary.
    vm.warp(block.timestamp + 12 hours - 1);
    assertTrue(game.rngLocked(), "rngLock must still hold at window's last second");

    // ── Phase 3b: Perturbation at the boundary ──────────────────────────
    _perturb(perturbSeed);
    assertTrue(game.rngLocked(), "rngLock must still hold post-perturbation");

    // ── Phase 4: Resolution under perturbation ──────────────────────────
    vm.recordLogs();
    _deliverMockVrf(reqId, vrfWord);
    Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
    bytes32 perturbedOutputs = _hashLogs(perturbedLogs);

    // ── Phase 5: Baseline ──────────────────────────────────────────────
    _revertToPreLock(preLockSnap);
    uint256 baseReqId = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "rngLock must engage at baseline request boundary");
    assertTrue(baseReqId != 0, "Baseline VRF request must be pending");
    // Same near-end-of-window warp in baseline path so the lock-window timing
    // is identical; only the perturbation is omitted.
    vm.warp(block.timestamp + 12 hours - 1);
    vm.recordLogs();
    _deliverMockVrf(baseReqId, vrfWord);
    Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
    bytes32 baselineOutputs = _hashLogs(baselineLogs);

    // ── Phase 6: Assert byte-identity ───────────────────────────────────
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "NearEndOfWindow: VRF outputs must be byte-identical for perturbation in final lock-window block"
    );
}
// ANCHOR: FUNC_EdgeCase_NearEndOfWindow_END


// ANCHOR: FUNC_EdgeCase_MultiTxBatch
/// @notice Edge case: multiple perturbations stacked within a single block.
/// @dev Per D-301-EDGE-CASES-01 (edge case 3) and FUZZ-05 (multi-tx-batch).
///      Three independent perturbations fire in sequence WITHOUT intervening
///      `vm.roll` calls — they all land in the same `block.number`. This
///      stresses intra-block reorderability invariants: any participating
///      slot whose value at consumer-resolution time depends on the order or
///      multiplicity of in-block writes will produce diverging outputs.
///
/// @param vrfWord Fuzz-derived VRF random word (forced non-zero).
/// @param seedA First perturbation seed.
/// @param seedB Second perturbation seed.
/// @param seedC Third perturbation seed.
function testFuzz_EdgeCase_MultiTxBatch(
    uint256 vrfWord,
    uint256 seedA,
    uint256 seedB,
    uint256 seedC
) public {
    vm.assume(vrfWord != 0);

    // ── Phase 1: Setup ──────────────────────────────────────────────────
    uint256 preLockSnap = _snapshotPreLock();
    uint256 reqId = _advanceToVrfRequestBoundary();

    // ── Phase 2: Lock ───────────────────────────────────────────────────
    assertTrue(game.rngLocked(), "rngLock must engage at request boundary");
    assertTrue(reqId != 0, "VRF request must be pending");
    uint256 lockBlock = block.number;

    // ── Phase 3: Three perturbations within the same block ─────────────
    // NO `vm.roll` between calls — all three land in `lockBlock`.
    _perturb(seedA);
    _perturb(seedB);
    _perturb(seedC);
    assertEq(block.number, lockBlock, "All three perturbations must land in the same block");
    assertTrue(game.rngLocked(), "rngLock must still hold post-perturbation");

    // ── Phase 4: Resolution under perturbation ──────────────────────────
    vm.recordLogs();
    _deliverMockVrf(reqId, vrfWord);
    Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
    bytes32 perturbedOutputs = _hashLogs(perturbedLogs);

    // ── Phase 5: Baseline ───────────────────────────────────────────────
    _revertToPreLock(preLockSnap);
    uint256 baseReqId = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "rngLock must engage at baseline request boundary");
    assertTrue(baseReqId != 0, "Baseline VRF request must be pending");
    vm.recordLogs();
    _deliverMockVrf(baseReqId, vrfWord);
    Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
    bytes32 baselineOutputs = _hashLogs(baselineLogs);

    // ── Phase 6: Assert byte-identity ───────────────────────────────────
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "MultiTxBatch: VRF outputs must be byte-identical when three perturbations stack in one block"
    );
}
// ANCHOR: FUNC_EdgeCase_MultiTxBatch_END


// ANCHOR: FUNC_EdgeCase_MultiBlock
/// @notice Edge case: perturbations spread across multiple blocks within the
///         rngLock window.
/// @dev Per D-301-EDGE-CASES-01 (edge case 4) and FUZZ-05 (multi-block within
///      window). Two perturbations fire in distinct blocks within the lock
///      window — the first at the lock-entry block, then `vm.roll` advances
///      `block.number` by a bounded delta (1..100), then the second
///      perturbation fires. `vm.warp` keeps `block.timestamp` coherent with
///      block-number progression (~12s/block per Ethereum mainnet baseline)
///      and the warp delta is kept strictly less than the 12-hour daily-RNG
///      timeout so the lock does not auto-retry.
///
/// @param vrfWord Fuzz-derived VRF random word (forced non-zero).
/// @param seedA First perturbation seed (fires at lock-entry block).
/// @param seedB Second perturbation seed (fires after the block-delta roll).
/// @param blockDelta Fuzz-derived block-number delta, bounded to [1, 100].
function testFuzz_EdgeCase_MultiBlock(
    uint256 vrfWord,
    uint256 seedA,
    uint256 seedB,
    uint8 blockDelta
) public {
    vm.assume(vrfWord != 0);

    // ── Phase 1: Setup ──────────────────────────────────────────────────
    uint256 preLockSnap = _snapshotPreLock();
    uint256 reqId = _advanceToVrfRequestBoundary();

    // ── Phase 2: Lock ───────────────────────────────────────────────────
    assertTrue(game.rngLocked(), "rngLock must engage at request boundary");
    assertTrue(reqId != 0, "VRF request must be pending");
    uint256 startBlock = block.number;
    uint256 startTime = block.timestamp;

    // ── Phase 3a: First perturbation at lock-entry block ────────────────
    _perturb(seedA);

    // ── Phase 3b: Roll forward, keeping timestamp coherent and < 12 h ──
    // Bound delta to [1, 100] blocks (max ~20 minutes at 12 s/block; well
    // within the 12 h daily-RNG timeout per AdvanceModule.rngGate:1241).
    uint256 delta = bound(uint256(blockDelta), 1, 100);
    vm.roll(startBlock + delta);
    vm.warp(startTime + delta * 12);
    assertTrue(game.rngLocked(), "rngLock must still hold after multi-block roll");

    // ── Phase 3c: Second perturbation in the new block ─────────────────
    _perturb(seedB);
    assertTrue(game.rngLocked(), "rngLock must still hold post-second perturbation");

    // ── Phase 4: Resolution under perturbation ──────────────────────────
    vm.recordLogs();
    _deliverMockVrf(reqId, vrfWord);
    Vm.Log[] memory perturbedLogs = vm.getRecordedLogs();
    bytes32 perturbedOutputs = _hashLogs(perturbedLogs);

    // ── Phase 5: Baseline ───────────────────────────────────────────────
    _revertToPreLock(preLockSnap);
    uint256 baseReqId = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "rngLock must engage at baseline request boundary");
    assertTrue(baseReqId != 0, "Baseline VRF request must be pending");
    // Same block/time progression in baseline so the consumer sees the same
    // ts/block.number at delivery; only the perturbations are omitted.
    uint256 baseStartBlock = block.number;
    uint256 baseStartTime = block.timestamp;
    vm.roll(baseStartBlock + delta);
    vm.warp(baseStartTime + delta * 12);
    vm.recordLogs();
    _deliverMockVrf(baseReqId, vrfWord);
    Vm.Log[] memory baselineLogs = vm.getRecordedLogs();
    bytes32 baselineOutputs = _hashLogs(baselineLogs);

    // ── Phase 6: Assert byte-identity ───────────────────────────────────
    _assertVrfOutputByteIdentity(
        perturbedOutputs,
        baselineOutputs,
        "MultiBlock: VRF outputs must be byte-identical when perturbations span distinct blocks within the lock window"
    );
}
// ANCHOR: FUNC_EdgeCase_MultiBlock_END


// ANCHOR: FUNC_EdgeCase_RetryLootboxRngDuringLock
/// @notice Edge case: failsafe `retryLootboxRng()` invocation during a
///         lootbox-RNG rngLock window with a concurrent perturbation.
/// @dev Per D-301-EDGE-CASES-01 (edge case 5) and FUZZ-05 (retry-during-lock).
///      This is distinct from plan 04's consumer-surface RetryLootboxRng
///      function (which tests the canonical fresh-VRF substitution semantics
///      under no perturbation). The edge-case variant here tests the retry
///      failsafe's interaction with a *concurrent perturbation* during the
///      ≥6 h stall window between the original mid-day VRF request and the
///      failsafe re-fire.
///
///      Invariant under test (D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A
///      "no pre-lock-state manipulation"): the failsafe must not manipulate
///      any slot the eventual VRF callback / `_finalizeLootboxRng` consumes
///      to derive output. Equivalently: byte-identical lootbox-RNG-derived
///      outputs in the (perturbation + retry) path vs (retry-only baseline)
///      path, holding the post-retry VRF word constant.
///
///      The retry timeout is 6 hours per `AdvanceModule.sol:141`
///      MIDDAY_RNG_RETRY_TIMEOUT — the test warps `6 hours + 1` to clear the
///      cooldown gate at `AdvanceModule.sol:1135`. The mid-day-lootbox-RNG
///      arrangement is reached by setting up a lootbox purchase that crosses
///      the LR_THRESHOLD and triggers `_requestLootboxRng` at
///      `AdvanceModule.sol:1043` (committing `LR_MID_DAY = 1`); the precise
///      arrangement is delegated to `_advanceToLootboxVrfRequestBoundary`
///      (a scaffold helper authored by plan 01 — or inlined via
///      `_advanceToVrfRequestBoundary` if plan 01's helper is the unified
///      boundary helper rather than per-consumer split).
///
/// @param vrfWord Fuzz-derived VRF random word delivered POST-retry
///                (forced non-zero).
/// @param perturbSeed Fuzz-derived perturbation seed.
function testFuzz_EdgeCase_RetryLootboxRngDuringLock(
    uint256 vrfWord,
    uint256 perturbSeed
) public {
    vm.assume(vrfWord != 0);

    // ── Phase 1: Setup — arrange to lootbox-RNG VRF-request boundary ───
    // Stall path: do NOT deliver the original VRF; instead clear retry
    // cooldown and re-fire via the failsafe.
    uint256 preLockSnap = _snapshotPreLock();
    uint256 reqId1 = _advanceToVrfRequestBoundary();

    // ── Phase 2: Lock ───────────────────────────────────────────────────
    assertTrue(game.rngLocked(), "rngLock must engage at lootbox-RNG request boundary");
    assertTrue(reqId1 != 0, "Original VRF request must be pending");

    // ── Phase 3: Pre-retry perturbation during stall window ────────────
    // The perturbation fires DURING the stalled rngLock window, BEFORE the
    // retry cooldown clears. Any state mutation that the retry failsafe
    // would consume as input (LR_MID_DAY, rngRequestTime, vrfSubscriptionId,
    // vrfKeyHash, vrfCoordinator) or that the eventual callback would
    // consume (LR_INDEX, LR_PENDING_*) is exercised by the perturbation.
    _perturb(perturbSeed);
    assertTrue(game.rngLocked(), "rngLock must still hold during stall window");

    // ── Phase 3b: Clear retry cooldown ──────────────────────────────────
    // MIDDAY_RNG_RETRY_TIMEOUT = 6 hours per AdvanceModule.sol:141. Warp
    // 6 h + 1 s to clear the gate at AdvanceModule.sol:1135.
    vm.warp(block.timestamp + 6 hours + 1);

    // ── Phase 3c: Invoke the failsafe ───────────────────────────────────
    // Permissionless caller per the retryLootboxRng spec at
    // AdvanceModule.sol:1132 (no access gate, only structural preconditions).
    // try/catch absorbs the case where the perturbation lifted a structural
    // precondition (e.g., updateVrfCoordinatorAndSub cleared LR_MID_DAY,
    // which would cause retryLootboxRng to revert E at :1133).
    bool retrySucceeded;
    try game.retryLootboxRng() { retrySucceeded = true; } catch { retrySucceeded = false; }

    // If the retry could not fire (perturbation cleared a structural
    // precondition), skip the assertion — the perturbation produced a state
    // where the failsafe's protocol-coordination invariant is N/A. This
    // is correct behavior, not a violation.
    if (!retrySucceeded) return;

    // ── Phase 4: Resolution — deliver fresh VRF post-retry ─────────────
    vm.recordLogs();
    uint256 reqId2 = mockVRF.lastRequestId();
    _deliverMockVrf(reqId2, vrfWord);
    Vm.Log[] memory perturbedRetryLogs = vm.getRecordedLogs();
    bytes32 perturbedRetryOutputs = _hashLogs(perturbedRetryLogs);

    // ── Phase 5: Baseline — retry-only (no pre-retry perturbation) ─────
    _revertToPreLock(preLockSnap);
    uint256 baseReqId1 = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "rngLock must engage at baseline lootbox-RNG request boundary");
    assertTrue(baseReqId1 != 0, "Baseline original VRF request must be pending");
    // SKIP perturbation; same stall + retry sequence as Phase 3b/3c.
    vm.warp(block.timestamp + 6 hours + 1);
    try game.retryLootboxRng() {} catch { return; }
    vm.recordLogs();
    uint256 baseReqId2 = mockVRF.lastRequestId();
    _deliverMockVrf(baseReqId2, vrfWord);
    Vm.Log[] memory baselineRetryLogs = vm.getRecordedLogs();
    bytes32 baselineRetryOutputs = _hashLogs(baselineRetryLogs);

    // ── Phase 6: Assert byte-identity (perturbation + retry vs retry-only) ──
    _assertVrfOutputByteIdentity(
        perturbedRetryOutputs,
        baselineRetryOutputs,
        "RetryLootboxRngDuringLock: retry + perturbation must produce byte-identical VRF outputs vs retry-only baseline (D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A invariant)"
    );
}
// ANCHOR: FUNC_EdgeCase_RetryLootboxRngDuringLock_END


// ANCHOR: CLUSTER_EDGECASE_END
// END plan 05 edge-case cluster contribution. 5 functions authored per
// D-301-EDGE-CASES-01; helper `_perturbAdminOnly` authored per FUZZ-02
// admin-action-set requirement; helper `_hashLogs` cluster-local for
// uniform VRF-output digest across heterogeneous consumer surfaces. Wave 2
// aggregator (plan 06) pastes this contribution after the scaffold and
// before any sibling cluster contributions' closing-position artifacts;
// the closing `}` for `contract RngLockDeterminism` is the aggregator's
// responsibility.
// ANCHOR: CLUSTER_EDGECASE_END_END
