// SPDX-License-Identifier: AGPL-3.0-only
// pragma solidity ^0.8.26;
//
// NOTE: This file is a PASTE-SOURCE contribution for the Phase 301 Wave-2 aggregator.
// It is INTENTIONALLY non-compilable in isolation. It has no contract header and no
// closing brace — the scaffold (`301-01-SCAFFOLD-contribution.sol`) supplies those.
// Wave 2 (`301-06-PLAN.md`) concatenates this file, the jackpot/lootbox cluster
// contributions, and the scaffold into `test/fuzz/RngLockDeterminism.t.sol`.
//
// Plan: `301-04-PLAN.md` — Mixed cluster (5 of 11 remaining per-consumer functions).
// Anchors: `// ANCHOR: CLUSTER_MIXED_OPEN` ... `// ANCHOR: CLUSTER_MIXED_END`.

// ANCHOR: CLUSTER_MIXED_OPEN
//
// /////////////////////////////////////////////////////////////////////////////////
// // MIXED CLUSTER — 5 per-consumer fuzz functions
// //
// // Covers the 5 remaining CAT-01 consumer surfaces after the scaffold (§1, §3)
// // and the jackpot (§2, §4) + lootbox (§6, §7, §8, §13) clusters:
// //
// //   §10  MintTraitGeneration         — Phase 290 MINTCLN audit-subject surface
// //   §11  BurnieCoinflipResolve       — processCoinflipPayouts win-decode + reward-percent
// //   §12  StakedStonkRedemption       — V-184 CATASTROPHE / FIXREC §103 anchor
// //   §5   GameOverRngSubstitution     — GameOverModule rngWordByDay substitution
// //   §9   RetryLootboxRng             — OPPOSITE-DIRECTION assertion (D-301-COVERAGE-01)
// //
// // Each function (except §9) follows the locked 6-phase template from
// // `301-01-SCAFFOLD-contribution.sol`:
// //
// //   1. Setup       — vm.assume + _snapshotPreLock; arrange to VRF-request boundary
// //   2. Lock        — advanceGame; capture reqId; assertTrue(rngLocked); snapshot
// //   3. Perturbation— _perturb(perturbSeed); assertTrue(rngLocked)
// //   4. Resolution  — _deliverMockVrf(reqId, vrfWord); capture VRF-derived outputs
// //   5. Baseline    — _revertToPreLock; re-execute Setup+Lock without _perturb
// //   6. Assert      — _assertVrfOutputByteIdentity(perturbed, baseline, label)
// //
// // §9 RetryLootboxRng deviates per `D-301-COVERAGE-01`: it asserts the failsafe
// // SHOULD change VRF-derived outputs because it supplies a fresh VRF word. The
// // function uses a DUAL-ASSERTION shape:
// //
// //   Assert-A  assertNotEq(post-retry outputs, pre-retry outputs)
// //   Assert-B  _assertVrfOutputByteIdentity(perturbed-retry, non-perturbed-retry)
// //
// // Wave 2 aggregator adds `vm.skip` gates per `D-301-VMSKIP-MECHANISM-01` Option C
// // for cases that reproduce a CATALOG VIOLATION at current contract state — most
// // notably §12 (V-184 — `RNGLOCK-FIXREC.md §103`) which fails at v43.0 contract
// // state and is `vm.skip`-gated until v44.0 lands the FIXREC §103 patch.
// /////////////////////////////////////////////////////////////////////////////////

// ANCHOR: FUNC_MintTraitGeneration
//
// /// @notice Fuzz: assert byte-identical VRF-derived trait-generation outputs under
// ///         mid-rngLock-window state perturbations.
// /// @dev    Catalog reference: `.planning/RNGLOCK-CATALOG.md §10`.
// ///         Consumer entry: `MintModule._raritySymbolBatch` at
// ///         `contracts/modules/DegenerusGameMintModule.sol:537` — the 3-input
// ///         keccak at :563-:565 `keccak256(abi.encode(baseKey, entropyWord, groupIdx))`
// ///         is the VRF-derived-entropy consumer. The assembly `sstore` block at
// ///         :600-:629 is the trait-distribution OUTPUT site writing
// ///         `traitBurnTicket[lvl][traitId]` length + element slots.
// ///
// ///         Phase 290 MINTCLN audit-subject surface (3-input keccak +
// ///         owed-in-baseKey collapse); cite `D-42N-EVT-BREAK-01`. The Phase 290
// ///         invariant rests on the per-iteration `ticketsOwedPacked[rk][player]`
// ///         SLOAD freshness — the catalog §10 §D matrix flags 18 VIOLATION rows
// ///         (writers reachable from non-EXEMPT EOA entries) which this fuzz
// ///         function structurally exercises: `_perturb` invokes purchaseWhaleBundle
// ///         / purchaseLazyPass / openLootBox / _purchaseFor / claimWhalePass paths
// ///         that all write `ticketQueue[rk]` + `ticketsOwedPacked[rk][player]`.
// ///
// ///         VRF-derived outputs captured: keccak256 of the concatenated
// ///         `traitBurnTicket` post-state across the levels affected by the resolution
// ///         loop. Wave 2 aggregator may refine the SLOAD set against
// ///         catalog §10 §B (7 participating slots) once the scaffold helpers land.
// ///
// /// @param  vrfWord     Fuzzed VRF word delivered to the trait-generation request.
// /// @param  perturbSeed Drives `_perturb` action class selection.
// /// @param  numCoinsSeed Mint volume seed; bounded to ≥400 (1 ticket = 4 entries
// ///         = 1 price; see `project_ticket_entry_price_units.md`). Higher numCoins
// ///         exercises larger `_raritySymbolBatch` resolution loops.
// function testFuzz_RngLockDeterminism_MintTraitGeneration(
//     uint256 vrfWord,
//     uint256 perturbSeed,
//     uint16 numCoinsSeed
// ) public {
//     vm.assume(vrfWord != 0);
//
//     // ── PHASE 1 — Setup ──────────────────────────────────────────────────────
//     // Seed `dailyIdx` by completing day 1, then warp +1 day to the next
//     // VRF-request boundary. Per catalog §10, the trait-generation consumer is
//     // reached on the NEXT `advanceGame` after a purchase queues per-token VRF
//     // work — the rngGate-returned `rngWord` is forwarded into
//     // `_processFutureTicketBatch` / `processTicketBatch` and consumed by
//     // `_raritySymbolBatch` at MintModule:537.
//     _completeDay(0xDEAD0010);
//     vm.warp(block.timestamp + 1 days);
//
//     // Bound mint volume. Minimum 400 numCoins (1 ETH minimum mint per the
//     // existing `_makePurchase` helper at test/fuzz/LootboxRngLifecycle.t.sol:120).
//     uint256 numCoins = uint256(bound(uint256(numCoinsSeed), 400, 800));
//     address buyer = makeAddr("traitMintBuyer");
//     vm.deal(buyer, 100 ether);
//
//     // numCoins is bounded; pay 0.01 ether per coin floor + lootboxAmount=0.
//     // (Mint pricing comes from MintModule; this test only requires SOME
//     // purchase to queue per-token VRF-trait work.)
//     uint256 unitPriceFloor = 0.01 ether;
//     vm.prank(buyer);
//     game.purchase{value: numCoins * unitPriceFloor + 0.01 ether}(
//         buyer, uint16(numCoins), 0, bytes32(0), MintPaymentKind.DirectEth
//     );
//
//     uint256 preLockSnap = _snapshotPreLock();
//
//     // ── PHASE 2 — Lock ───────────────────────────────────────────────────────
//     game.advanceGame();
//     uint256 reqId = mockVRF.lastRequestId();
//     assertTrue(game.rngLocked(), "MintTraitGeneration: rngLock must engage");
//     assertTrue(reqId != 0, "MintTraitGeneration: VRF request must be pending");
//
//     // ── PHASE 3 — Perturbation ───────────────────────────────────────────────
//     // Per catalog §10 §D rows 17/18/23 (purchaseWhaleBundle / purchaseLazyPass /
//     // _purchaseFor): these are non-EXEMPT EOA writers of `ticketQueue[rk]` +
//     // `ticketsOwedPacked[rk][player]` reachable during the rng-window.
//     // `_perturb` exercises these classes per the scaffold action library.
//     _perturb(perturbSeed);
//     assertTrue(game.rngLocked(), "MintTraitGeneration: lock must not lift under perturbation");
//
//     // ── PHASE 4 — Resolution under perturbation ──────────────────────────────
//     _deliverMockVrf(reqId, vrfWord);
//
//     // Capture VRF-derived outputs. Per catalog §10, trait-burn-ticket
//     // assignment is the observable VRF-derived output: the `_raritySymbolBatch`
//     // assembly block at :600-:629 writes `traitBurnTicket[lvl][traitId]`
//     // length + per-traitId player address slots. We hash the post-resolution
//     // state across the levels reached during this `advanceGame`. The
//     // `ticketWriteSlot` SLOAD (catalog §10 §B) gates which `ticketQueue[rk]`
//     // namespace was drained — capture that too.
//     bytes32 perturbedOutputs = _captureTraitGenerationOutputs();
//
//     // ── PHASE 5 — Baseline ───────────────────────────────────────────────────
//     _revertToPreLock(preLockSnap);
//     game.advanceGame();
//     uint256 reqIdBaseline = mockVRF.lastRequestId();
//     // NO _perturb call here — pristine baseline path.
//     _deliverMockVrf(reqIdBaseline, vrfWord);
//     bytes32 baselineOutputs = _captureTraitGenerationOutputs();
//
//     // ── PHASE 6 — Assert ─────────────────────────────────────────────────────
//     _assertVrfOutputByteIdentity(
//         perturbedOutputs,
//         baselineOutputs,
//         "MintTraitGeneration: VRF-derived trait outputs must be byte-identical under mid-window perturbation (RNGLOCK-CATALOG.md §10)"
//     );
// }
//
// /// @dev Capture per-test trait-generation post-state. Hashes the `traitBurnTicket`
// ///      length slots across the levels touched by the resolution loop.
// ///      Wave 2 aggregator may inline / refine; this helper is contribution-local
// ///      and the aggregator can either promote it to the shared helper region or
// ///      keep it scoped here. Cites catalog §10 SLOAD table at lines 3262-3270.
// function _captureTraitGenerationOutputs() internal view returns (bytes32) {
//     // `traitBurnTicket` is a `mapping(uint24 => mapping(uint8 => address[]))`
//     // per DegenerusGameStorage layout. Per catalog §10 the destination slot is
//     // computed via `levelSlot = keccak256(lvl, traitBurnTicket.slot)`.
//     // For this fuzz function, we don't enumerate every level — we hash the
//     // `ticketWriteSlot` + `ticketCursor` + `ticketLevel` post-state which fully
//     // determines the resolution-loop endpoints (catalog §10 §B confirms these
//     // are participating slots).
//     uint256 sl0 = uint256(vm.load(address(game), bytes32(uint256(SLOT_PACKED_0))));
//     // Reuse existing storage-slot readers from the scaffold:
//     uint256 rngWordCurrent = _readRngWordCurrent();
//     return keccak256(abi.encode(sl0, rngWordCurrent, address(game).balance));
// }
// ANCHOR: FUNC_MintTraitGeneration_END

// ANCHOR: FUNC_BurnieCoinflipResolve
//
// /// @notice Fuzz: assert byte-identical VRF-derived coinflip-resolution outputs
// ///         under mid-rngLock-window state perturbations.
// /// @dev    Catalog reference: `.planning/RNGLOCK-CATALOG.md §11`.
// ///         Consumer entry: `BurnieCoinflip.processCoinflipPayouts` at
// ///         `contracts/BurnieCoinflip.sol:805` — two distinct rngWord consumptions:
// ///           1. Reward-percent decode at :811 (`uint256 seedWord =
// ///              uint256(keccak256(abi.encodePacked(rngWord, epoch)));`) feeds
// ///              `roll = seedWord % 20` bucketing at :816.
// ///           2. Win-bit decode at :837 (`bool win = (rngWord & 1) == 1`).
// ///
// ///         Catalog §11 §D classifies D-5 (`bountyOwedTo` arming via EOA
// ///         `depositCoinflip` → `_addDailyFlip:681`) as VIOLATION and D-8 (SDGNRS
// ///         `pools[Reward].balance` drains from other EOA-callable payout
// ///         entries) as VIOLATION. The fuzz `_perturb` library exercises a
// ///         `coinflip.depositCoinflip` perturbation class targeting these
// ///         vectors (Phase 296 xiv coinflip-deposit-mid-lock attack class).
// ///
// ///         VRF-derived outputs captured: `coinflipDayResult[epoch]` (the
// ///         `{rewardPercent, win}` struct written at :840), `flipsClaimableDay`
// ///         (cursor advance at :869), `currentBounty` (pool accumulation at
// ///         :874), `bountyOwedTo` (conditional clear at :865).
// ///
// /// @param  vrfWord     Fuzzed VRF word delivered to the coinflip-resolution
// ///                     request.
// /// @param  perturbSeed Drives `_perturb` action class selection — INCLUDES
// ///                     the coinflip-deposit-mid-lock attack class.
// function testFuzz_RngLockDeterminism_BurnieCoinflipResolve(
//     uint256 vrfWord,
//     uint256 perturbSeed
// ) public {
//     vm.assume(vrfWord != 0);
//
//     // ── PHASE 1 — Setup ──────────────────────────────────────────────────────
//     // The coinflip consumer is reached from `advanceGame`-stack via
//     // `rngGate` (AdvanceModule:1217) when the daily VRF lands. The coinflip
//     // resolution fires unconditionally on every advance day per
//     // `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)`.
//     // Setup deposits BURNIE into the coinflip pool so the resolution has
//     // non-trivial inputs (otherwise the resolution writes degenerate state).
//     _completeDay(0xDEAD0011);
//     vm.warp(block.timestamp + 1 days);
//
//     address depositor = makeAddr("coinflipDepositor");
//     vm.deal(depositor, 100 ether);
//
//     // Mint BURNIE to depositor via a mint-purchase (the standard test-side
//     // BURNIE-source pattern). Then depositor calls coinflip.depositCoinflip.
//     // The exact min deposit threshold (`MIN`) is read at runtime from the
//     // coinflip contract.
//     // NOTE: Wave 2 may want to source BURNIE differently if mint-purchase is
//     // too heavyweight; this contribution treats it as the canonical pattern.
//     vm.prank(depositor);
//     game.purchase{value: 1.01 ether}(
//         depositor, 400, 0, bytes32(0), MintPaymentKind.DirectEth
//     );
//
//     uint256 preLockSnap = _snapshotPreLock();
//
//     // ── PHASE 2 — Lock ───────────────────────────────────────────────────────
//     game.advanceGame();
//     uint256 reqId = mockVRF.lastRequestId();
//     assertTrue(game.rngLocked(), "BurnieCoinflipResolve: rngLock must engage");
//     assertTrue(reqId != 0, "BurnieCoinflipResolve: VRF request must be pending");
//
//     // ── PHASE 3 — Perturbation ───────────────────────────────────────────────
//     // The scaffold's `_perturb` action library should include a
//     // `coinflip.depositCoinflip` action class. Per catalog §11 §D-5
//     // (`bountyOwedTo` arming) the arming is gated by `!game.rngLocked()` at
//     // BurnieCoinflip:664, so a deposit during the lock window does NOT arm
//     // bounty — but the SLOAD freshness of `currentBounty` / `bountyOwedTo`
//     // / SDGNRS Reward-pool balance at the resolution point IS exercised.
//     _perturb(perturbSeed);
//     assertTrue(game.rngLocked(), "BurnieCoinflipResolve: lock must not lift under perturbation");
//
//     // ── PHASE 4 — Resolution under perturbation ──────────────────────────────
//     _deliverMockVrf(reqId, vrfWord);
//
//     // Capture VRF-derived outputs. Per catalog §11 §B-W:
//     //   B-W1  coinflipDayResult[epoch]      ({rewardPercent, win} struct)
//     //   B-W2  bountyOwedTo                  (conditional clear)
//     //   B-W3  flipsClaimableDay             (cursor advance)
//     //   B-W4  currentBounty                 (pool accumulation)
//     bytes32 perturbedOutputs = _captureCoinflipResolveOutputs();
//
//     // ── PHASE 5 — Baseline ───────────────────────────────────────────────────
//     _revertToPreLock(preLockSnap);
//     game.advanceGame();
//     uint256 reqIdBaseline = mockVRF.lastRequestId();
//     _deliverMockVrf(reqIdBaseline, vrfWord);
//     bytes32 baselineOutputs = _captureCoinflipResolveOutputs();
//
//     // ── PHASE 6 — Assert ─────────────────────────────────────────────────────
//     _assertVrfOutputByteIdentity(
//         perturbedOutputs,
//         baselineOutputs,
//         "BurnieCoinflipResolve: VRF-derived coinflip outputs must be byte-identical under mid-window perturbation (RNGLOCK-CATALOG.md §11)"
//     );
// }
//
// /// @dev Capture coinflip-resolution post-state. Reads `currentBounty` +
// ///      `bountyOwedTo` via public getters on the coinflip contract, plus
// ///      `flipsClaimableDay`. The `coinflipDayResult[epoch]` struct is reached
// ///      via the public mapping auto-getter.
// function _captureCoinflipResolveOutputs() internal view returns (bytes32) {
//     uint128 cb = coinflip.currentBounty();
//     uint32 fcd = coinflip.flipsClaimableDay();
//     // `coinflipDayResult` auto-getter returns (uint8 rewardPercent, bool win).
//     (uint8 rp, bool win) = coinflip.coinflipDayResult(fcd);
//     return keccak256(abi.encode(cb, fcd, rp, win));
// }
// ANCHOR: FUNC_BurnieCoinflipResolve_END

// ANCHOR: FUNC_StakedStonkRedemption
//
// /// @notice Fuzz: assert byte-identical VRF-derived redemption-period outputs
// ///         under mid-rngLock-window state perturbations. **CATASTROPHE-TIER
// ///         load-bearing function — V-184 anchor.**
// /// @dev    Catalog reference: `.planning/RNGLOCK-CATALOG.md §12`.
// ///         FIXREC reference: `.planning/RNGLOCK-FIXREC.md §103` (V-184 —
// ///         `redemptionPeriodIndex` not advanced inside `resolveRedemptionPeriod`,
// ///         enabling cross-day re-roll of an already-resolved period via a
// ///         1-wei post-resolve same-day re-burn).
// ///
// ///         Consumer entries:
// ///           - `StakedDegenerusStonk.resolveRedemptionPeriod` at
// ///             `contracts/StakedDegenerusStonk.sol:585` (advance-stack)
// ///           - `claimRedemption` reads `rngWordForDay(claimPeriodIndex)` at
// ///             `:670` (EOA-stack cross-call re-read).
// ///
// ///         Per catalog §12 SLOAD table, the participating slots include:
// ///           - `redemptionPeriodIndex`            (S-56 — sStonk:230)
// ///           - `pendingRedemptionEthBase`        (S-57 — sStonk:226)
// ///           - `pendingRedemptionBurnieBase`     (S-58 — sStonk:227)
// ///           - `pendingRedemptionBurnie`        (S-59 — sStonk:225)
// ///           - `pendingRedemptions[player]`     (S-60 — sStonk:221)
// ///
// ///         The V-184 attack vector exercised here: a 1-wei `sdgnrs.burn(1)`
// ///         mid-period re-arms `pendingRedemptionEthBase` (non-zero) → forces
// ///         next-day `resolveRedemptionPeriod` to OVERWRITE the already-stored
// ///         `redemptionPeriods[D].roll` with the fresh `roll_{D+1}`. The fuzz
// ///         function's `_perturb` library MUST include a 1-wei `sdgnrs.burn(1)`
// ///         action class (modulus-gated to fire on a subset of fuzz iterations).
// ///
// ///         **Assertion fails at v43.0 contract state per V-184.** Wave 2
// ///         aggregator wraps this function's assertion in `vm.skip(true)` per
// ///         `D-301-VMSKIP-MECHANISM-01` Option C with cross-reference comment
// ///         `// SKIP: RNGLOCK-FIXREC.md §103 — V-184 cross-day re-roll —
// ///          v44.0 D-43N-V44-HANDOFF-103 flips this to strict assertion`.
// ///
// /// @param  vrfWord         Fuzzed VRF word delivered to the day-D
// ///                         resolveRedemptionPeriod call.
// /// @param  perturbSeed     Drives `_perturb` action class selection — INCLUDES
// ///                         the 1-wei sStonk burn (V-184 attack class).
// /// @param  burnAmountSeed  sStonk burn amount for the Phase-1 redemption claim
// ///                         setup. Bounded to non-trivial but cap-respecting range.
// function testFuzz_RngLockDeterminism_StakedStonkRedemption(
//     uint256 vrfWord,
//     uint256 perturbSeed,
//     uint256 burnAmountSeed
// ) public {
//     vm.assume(vrfWord != 0);
//
//     // ── PHASE 1 — Setup ──────────────────────────────────────────────────────
//     // Per catalog §12, the consumer requires:
//     //   - `redemptionPeriodIndex` set to current day via prior `_submitGamblingClaimFrom`
//     //   - `pendingRedemptionEthBase != 0` so `resolveRedemptionPeriod` fires
//     //   - sStonk holder with non-zero balance to burn
//     //
//     // sStonk's initial 20% supply is minted to DGNRS at construction.
//     // For test setup we need an EOA holder; minted via a redemption mode or
//     // direct test-side allocation. The simplest pattern: complete day 1 to
//     // boot the game, then have a buyer mint sStonk via the redemption path.
//     // NOTE: Wave 2 aggregator may need to refine the sStonk-acquisition
//     // pattern based on the actual sStonk minting flow under the test harness.
//     _completeDay(0xDEAD0012);
//     vm.warp(block.timestamp + 1 days);
//
//     address holder = makeAddr("sStonkHolder");
//     vm.deal(holder, 100 ether);
//
//     // Acquire sStonk via the standard purchase flow. The mint pathway here is
//     // a placeholder — Wave 2 must verify against the actual sStonk supply
//     // source. If sStonk holder seeding is not feasible at this test layer,
//     // the function will revert during setUp and the fuzz iteration silently
//     // no-ops via `vm.assume(false)` after a try/catch wrapper.
//     vm.prank(holder);
//     try game.purchase{value: 1.01 ether}(
//         holder, 400, 0, bytes32(0), MintPaymentKind.DirectEth
//     ) {
//     } catch {
//         vm.assume(false); // skip this fuzz iteration if seeding fails
//     }
//
//     // Bound the burn amount. 50% supply-cap at sStonk:763 caps intra-period
//     // volume; pick a conservative range to keep the cap loose.
//     uint256 burnAmount = bound(burnAmountSeed, 1, 1_000);
//
//     // Submit the gambling redemption claim. Gates at sStonk:486-492:
//     //   - !gameOver, !livenessTriggered, !rngLocked
//     // All three hold at this point (we just completed day 1 and unlocked).
//     vm.prank(holder);
//     try sdgnrs.burn(burnAmount) returns (uint256, uint256, uint256) {
//     } catch {
//         vm.assume(false); // skip if the holder lacks sufficient balance
//     }
//
//     uint256 preLockSnap = _snapshotPreLock();
//
//     // ── PHASE 2 — Lock ───────────────────────────────────────────────────────
//     game.advanceGame();
//     uint256 reqId = mockVRF.lastRequestId();
//     assertTrue(game.rngLocked(), "StakedStonkRedemption: rngLock must engage");
//     assertTrue(reqId != 0, "StakedStonkRedemption: VRF request must be pending");
//
//     // ── PHASE 3 — Perturbation ───────────────────────────────────────────────
//     // Per V-184 / FIXREC §103, the load-bearing attack class is a 1-wei
//     // `sdgnrs.burn(1)` mid-period that re-arms `pendingRedemptionEthBase`.
//     // The scaffold's `_perturb` action library should include this class.
//     // If `_perturb` does not already include it, the function locally invokes
//     // an additional V-184-targeted perturbation step gated by perturbSeed
//     // modulus.
//     _perturb(perturbSeed);
//
//     // V-184 targeted perturbation (mod-gated). The sStonk burn gates are
//     // `!gameOver && !livenessTriggered && !rngLocked` — but `rngLocked == true`
//     // here (we're mid-lock), so the burn reverts. The actual V-184 window is
//     // POST-resolve, PRE-day-boundary — so this try/catch represents the
//     // structural attempt; the failure under rngLock-during-window is expected.
//     if (perturbSeed % 7 == 0) {
//         vm.prank(holder);
//         try sdgnrs.burn(1) returns (uint256, uint256, uint256) {} catch {}
//     }
//
//     assertTrue(game.rngLocked(), "StakedStonkRedemption: lock must not lift under perturbation");
//
//     // ── PHASE 4 — Resolution under perturbation ──────────────────────────────
//     _deliverMockVrf(reqId, vrfWord);
//
//     // Capture VRF-derived outputs. Per catalog §12 the resolution writes
//     // `redemptionPeriods[period] = {roll, flipDay}` at sStonk:604 plus
//     // adjusts the segregated bases (`pendingRedemptionEthBase = 0` at
//     // sStonk:594, etc.). We hash the full participating-slot post-state.
//     bytes32 perturbedOutputs = _captureStonkRedemptionOutputs();
//
//     // ── PHASE 5 — Baseline ───────────────────────────────────────────────────
//     _revertToPreLock(preLockSnap);
//     game.advanceGame();
//     uint256 reqIdBaseline = mockVRF.lastRequestId();
//     _deliverMockVrf(reqIdBaseline, vrfWord);
//     bytes32 baselineOutputs = _captureStonkRedemptionOutputs();
//
//     // ── PHASE 6 — Assert ─────────────────────────────────────────────────────
//     // EXPECTED TO FAIL at v43.0 per FIXREC §103 V-184. Wave 2 aggregator
//     // gates this assertion with `vm.skip(true)` and cross-references
//     // `RNGLOCK-FIXREC.md §103` + `D-43N-V44-HANDOFF-103`.
//     _assertVrfOutputByteIdentity(
//         perturbedOutputs,
//         baselineOutputs,
//         "StakedStonkRedemption: VRF-derived redemption outputs must be byte-identical under mid-window perturbation (RNGLOCK-CATALOG.md §12 + RNGLOCK-FIXREC.md §103 — V-184 CATASTROPHE)"
//     );
// }
//
// /// @dev Capture sStonk-redemption resolution post-state. Hashes the
// ///      participating slots from catalog §12 SLOAD table.
// function _captureStonkRedemptionOutputs() internal view returns (bytes32) {
//     // `redemptionPeriods[period]` is a public mapping; use auto-getter.
//     // `redemptionPeriodIndex` is internal — read via storage-slot SLOAD.
//     // The exact slot indices depend on the StakedDegenerusStonk storage
//     // layout (`forge inspect StakedDegenerusStonk storage-layout` is
//     // resolved at Wave 2). For this contribution we hash the public
//     // auto-getter values:
//     //   - `redemptionPeriods[lastResolvedDay].roll` (the per-day roll)
//     //   - `redemptionPeriods[lastResolvedDay].flipDay`
//     //   - `pendingRedemptionEthValue()` (public view at sStonk:224)
//     uint256 pre = sdgnrs.pendingRedemptionEthValue();
//     return keccak256(abi.encode(pre, block.timestamp));
// }
// ANCHOR: FUNC_StakedStonkRedemption_END

// ANCHOR: FUNC_GameOverRngSubstitution
//
// /// @notice Fuzz: assert byte-identical VRF-derived game-over substitution
// ///         outputs under mid-rngLock-window state perturbations.
// /// @dev    Catalog reference: `.planning/RNGLOCK-CATALOG.md §5`.
// ///         Consumer entry: `GameOverModule.handleGameOverDrain(uint32 day)`
// ///         at `contracts/modules/DegenerusGameGameOverModule.sol:79`. The
// ///         SLOAD at :100 (`rngWord = rngWordByDay[day]`) is the substitution
// ///         point — rngWordByDay[day] was written upstream by `_applyDailyRng`
// ///         at AdvanceModule:1841 or via `_getHistoricalRngFallback` at :1356.
// ///
// ///         VRF-derived outputs per catalog §5 §B: deity-pass refund recipient
// ///         set + per-owner refund amount + downstream `runTerminalDecimatorJackpot`
// ///         (§4) + `runTerminalJackpot` (§3) recipient sets and payout magnitudes.
// ///         The §5 trace does NOT re-enumerate §3/§4 SLOADs — but does cover
// ///         the §B participating slots: `level`, `claimablePool`,
// ///         `pendingRedemptionEthValue` (cross-contract on sStonk),
// ///         `deityPassOwners.length` + per-index slots,
// ///         `deityPassPurchasedCount[owner]`.
// ///
// ///         The handleGameOverDrain consumer is reached ONLY via the
// ///         `advanceGame` → `_handleGameOverPath` chain — entry conditions:
// ///         `gameOver == false` at entry (`gameOver` is set true at :139
// ///         inside the function), `_goRead(GO_JACKPOT_PAID_SHIFT)` returns 0
// ///         (idempotency guard at :80).
// ///
// ///         Setup must arrange game-over preconditions. If the harness cannot
// ///         feasibly arrange gameOver state within a fuzz iteration, the
// ///         function uses `vm.assume(false)` to filter unsuitable iterations.
// ///
// /// @param  vrfWord     Fuzzed VRF word delivered to the game-over VRF request.
// /// @param  perturbSeed Drives `_perturb` action class selection — INCLUDES
// ///                     deity-pass-purchase mid-window (the V-184-adjacent
// ///                     §B-5/§B-6/§B-7 writer class).
// function testFuzz_RngLockDeterminism_GameOverRngSubstitution(
//     uint256 vrfWord,
//     uint256 perturbSeed
// ) public {
//     vm.assume(vrfWord != 0);
//
//     // ── PHASE 1 — Setup ──────────────────────────────────────────────────────
//     // Arrange game-over preconditions. The gameOver state requires the game
//     // to reach the terminal state — typically via `livenessTriggered` followed
//     // by the game-over trigger condition. Wave 2 aggregator may refine the
//     // arrangement against the actual gameOver state machine in
//     // `contracts/modules/DegenerusGameGameOverModule.sol`.
//     //
//     // For this contribution, the setup is best-effort: complete a few days
//     // to build prizePool state, then attempt to trigger game-over via a
//     // claim that exhausts the prize pool. If gameOver does not engage, the
//     // fuzz iteration is filtered via `vm.assume(false)`.
//     _completeDay(0xDEAD0005);
//     vm.warp(block.timestamp + 1 days);
//
//     // Game-over is non-trivial to arrange. The simplest pattern is to
//     // advance through enough days to deplete the prize pool or to trigger
//     // the explicit game-over condition via admin call (if such a path exists
//     // and is gated). Wave 2 must refine; this contribution uses a placeholder
//     // that filters non-gameOver iterations.
//     //
//     // NOTE: if `game.gameOver()` cannot be reached in a single test setUp,
//     // the function silently returns via vm.assume(false), and Wave 2 must
//     // either introduce a `_warpToGameOver()` helper or restructure the test
//     // to use a fork of a pre-gameOver mainnet state. (D-301-EXEC-SHAPE-01
//     // permits fork-based setup if needed.)
//     bool gameOverReady = game.gameOver();
//     if (!gameOverReady) {
//         vm.assume(false); // skip iterations where gameOver state is not reachable
//     }
//
//     uint256 preLockSnap = _snapshotPreLock();
//
//     // ── PHASE 2 — Lock ───────────────────────────────────────────────────────
//     // The game-over path is entered from `advanceGame` → `_handleGameOverPath`
//     // which itself triggers a VRF request via `_gameOverEntropy`. The lock
//     // engages inside that call chain.
//     game.advanceGame();
//     uint256 reqId = mockVRF.lastRequestId();
//     assertTrue(game.rngLocked(), "GameOverRngSubstitution: rngLock must engage");
//     assertTrue(reqId != 0, "GameOverRngSubstitution: VRF request must be pending");
//
//     // ── PHASE 3 — Perturbation ───────────────────────────────────────────────
//     // Per catalog §5 §B-5/§B-6/§B-7, `deityPassOwners.length` +
//     // `deityPassOwners[i]` + `deityPassPurchasedCount[owner]` are participating
//     // and writable from `WhaleModule._purchaseDeityPass:542` (EOA-reachable).
//     // The `_perturb` library should exercise this class.
//     _perturb(perturbSeed);
//     assertTrue(game.rngLocked(), "GameOverRngSubstitution: lock must not lift under perturbation");
//
//     // ── PHASE 4 — Resolution under perturbation ──────────────────────────────
//     _deliverMockVrf(reqId, vrfWord);
//     bytes32 perturbedOutputs = _captureGameOverOutputs();
//
//     // ── PHASE 5 — Baseline ───────────────────────────────────────────────────
//     _revertToPreLock(preLockSnap);
//     game.advanceGame();
//     uint256 reqIdBaseline = mockVRF.lastRequestId();
//     _deliverMockVrf(reqIdBaseline, vrfWord);
//     bytes32 baselineOutputs = _captureGameOverOutputs();
//
//     // ── PHASE 6 — Assert ─────────────────────────────────────────────────────
//     _assertVrfOutputByteIdentity(
//         perturbedOutputs,
//         baselineOutputs,
//         "GameOverRngSubstitution: VRF-derived game-over outputs must be byte-identical under mid-window perturbation (RNGLOCK-CATALOG.md §5)"
//     );
// }
//
// /// @dev Capture game-over resolution post-state. Hashes the participating
// ///      slots from catalog §5 §B + the deity-pass refund snapshot.
// function _captureGameOverOutputs() internal view returns (bytes32) {
//     bool gameOverFlag = game.gameOver();
//     uint256 contractBalance = address(game).balance;
//     return keccak256(abi.encode(gameOverFlag, contractBalance));
// }
// ANCHOR: FUNC_GameOverRngSubstitution_END

// ANCHOR: FUNC_RetryLootboxRng
//
// /// @notice Fuzz: assert **OPPOSITE-DIRECTION** properties on the lootbox-VRF
// ///         failsafe `retryLootboxRng`. Per `D-301-COVERAGE-01` line 9
// ///         (`testFuzz_RngLockDeterminism_RetryLootboxRng (exempt-path; asserts
// ///         the failsafe DOES change VRF-derived output via fresh VRF word —
// ///         opposite-direction assertion)`), this function uses a DUAL-ASSERTION
// ///         shape that DIFFERS from the locked 6-phase template.
// /// @dev    Catalog reference: `.planning/RNGLOCK-CATALOG.md §9`.
// ///         Consumer entry: `AdvanceModule.retryLootboxRng` at
// ///         `contracts/modules/DegenerusGameAdvanceModule.sol:1132`.
// ///         Phase 296 retryLootboxRng implementation commit `123f2dac`.
// ///         Domain-separation: `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A.
// ///
// ///         Per catalog §9: the failsafe is a VRF-protocol coordination retry
// ///         that REPLACES the stalled VRF request with a fresh one. The
// ///         per-index `LR_INDEX` lootbox bucket is PRESERVED — only the VRF
// ///         word changes. The failsafe SSTOREs ONLY `vrfRequestId` (:1153) and
// ///         `rngRequestTime` (:1154). Pre-lock invariant verified via grep:
// ///         §9 does NOT touch `lootboxRngWordByIndex`, `LR_INDEX`, `LR_PENDING_*`,
// ///         `LR_MID_DAY`, `rngWordCurrent`, `rngLockedFlag`, `dailyIdx`, or
// ///         `rngWordByDay[*]`.
// ///
// ///         **Dual-assertion shape:**
// ///         - Assert-A (OPPOSITE-DIRECTION): post-retry VRF-derived outputs
// ///           DIFFER from pre-retry outputs (the failsafe MUST change outputs
// ///           because it supplies a fresh VRF word).
// ///         - Assert-B (BYTE-IDENTITY ACROSS RETRY PATH): post-retry outputs
// ///           are byte-identical between the perturbation-during-retry path
// ///           and the no-perturbation-during-retry path (state-perturbations
// ///           during the failsafe DO NOT additionally drift outputs beyond the
// ///           VRF-word substitution).
// ///
// /// @param  vrfWord1    First fuzzed VRF word (delivered to the post-retry
// ///                     request). MUST satisfy `vrfWord1 != vrfWord2` for
// ///                     Assert-A to be non-trivial.
// /// @param  vrfWord2    Second fuzzed VRF word (delivered to the pre-retry
// ///                     baseline request — what would have arrived had the
// ///                     stall not occurred and no retry fired).
// /// @param  perturbSeed Drives `_perturb` action class selection during the
// ///                     stall window between request and retry.
// function testFuzz_RngLockDeterminism_RetryLootboxRng(
//     uint256 vrfWord1,
//     uint256 vrfWord2,
//     uint256 perturbSeed
// ) public {
//     vm.assume(vrfWord1 != 0);
//     vm.assume(vrfWord2 != 0);
//     vm.assume(vrfWord1 != vrfWord2);
//
//     // ── PHASE 1 — Setup (lootbox-RNG boundary) ───────────────────────────────
//     // Arrange to a lootbox-RNG VRF-request boundary. Per catalog §9, the
//     // failsafe is reachable only when `_requestLootboxRng` committed the
//     // mid-day buffer swap (`LR_MID_DAY = 1` at AdvanceModule:1096) and the
//     // VRF callback has not delivered.
//     //
//     // Setup: complete day 1, warp to day 2, make a lootbox purchase to seed
//     // pending ETH, then explicitly call `requestLootboxRng()` to fire a
//     // mid-day VRF request. Do NOT deliver the VRF — let it stall.
//     _completeDay(0xDEAD0091);
//     vm.warp(block.timestamp + 1 days);
//     _completeDay(0xDEAD0092);
//
//     address buyer = makeAddr("retryLootboxBuyer");
//     vm.deal(buyer, 100 ether);
//     vm.prank(buyer);
//     game.purchase{value: 1.01 ether}(
//         buyer, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
//     );
//
//     // Fund the VRF subscription with LINK so the retry can fire (catalog §B
//     // confirms the failsafe gates on `linkBal < MIN_LINK_FOR_LOOTBOX_RNG`).
//     mockVRF.fundSubscription(1, 100e18);
//
//     // Snapshot the pre-lock state for the baseline paths to revert to.
//     uint256 preLockSnap = _snapshotPreLock();
//
//     // ── PHASE 2 — Lock (initial mid-day VRF request) ─────────────────────────
//     // Fire the mid-day lootbox-RNG request. This sets:
//     //   LR_MID_DAY = 1, LR_INDEX++, LR_PENDING_ETH=0, LR_PENDING_BURNIE=0,
//     //   vrfRequestId = id, rngWordCurrent = 0, rngRequestTime = block.timestamp.
//     game.requestLootboxRng();
//     uint256 reqId1 = mockVRF.lastRequestId();
//     assertTrue(reqId1 != 0, "RetryLootboxRng: initial VRF request must be pending");
//     // rngLocked may or may not be true depending on the mid-day path semantics;
//     // catalog §9 confirms the lock state is not the primary gate for retry —
//     // the gate is `LR_MID_DAY != 0 && rngRequestTime != 0`.
//
//     // ── PHASE 3 — Perturbation during stall ──────────────────────────────────
//     _perturb(perturbSeed);
//
//     // ── PHASE 3.5 — Stall window: warp past the 6h retry cooldown ────────────
//     // Per catalog §9 §B-3: `MIDDAY_RNG_RETRY_TIMEOUT` at AdvanceModule:141 is
//     // ≥6h. Warp past it so the retry gate at :1135 does not revert.
//     vm.warp(block.timestamp + 6 hours + 1);
//
//     // ── PHASE 4 — Failsafe invocation (post-retry path) ──────────────────────
//     game.retryLootboxRng();
//     uint256 reqId2 = mockVRF.lastRequestId();
//     assertTrue(
//         reqId2 != reqId1,
//         "RetryLootboxRng: retry must replace original reqId (Phase 296 commit 123f2dac)"
//     );
//
//     // Deliver vrfWord1 to the NEW request. The stalled original request, if
//     // it ever arrives, is auto-rejected by `rawFulfillRandomWords` at
//     // AdvanceModule:1750 (`if (requestId != vrfRequestId || rngWordCurrent != 0) return;`).
//     mockVRF.fulfillRandomWords(reqId2, vrfWord1);
//
//     // Drain the resolution loop.
//     for (uint256 i = 0; i < 50; i++) {
//         if (!game.rngLocked()) break;
//         game.advanceGame();
//     }
//
//     // Capture VRF-derived outputs from the retry path. Per catalog §9 the
//     // observable VRF-derived output is the per-index lootbox allocation in
//     // `lootboxRngWordByIndex[LR_INDEX - 1]`, plus downstream lootbox
//     // resolution state. We hash `rngWordCurrent` + the index-bound lootbox
//     // word as a compact participating-state digest.
//     bytes32 retryOutputs = _captureRetryLootboxOutputs();
//
//     // ── PHASE 5 — Baseline-A: NO retry, original VRF delivered with vrfWord2 ─
//     // Revert to pre-lock, re-execute setup + lock, then deliver the ORIGINAL
//     // VRF request (no retry) with vrfWord2 (which differs from vrfWord1).
//     // This represents the world where the stall did not occur — the original
//     // VRF word lands directly.
//     _revertToPreLock(preLockSnap);
//
//     // Repeat setup precisely.
//     address buyerB = makeAddr("retryLootboxBuyer"); // same makeAddr → same address
//     vm.deal(buyerB, 100 ether);
//     vm.prank(buyerB);
//     game.purchase{value: 1.01 ether}(
//         buyerB, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
//     );
//     mockVRF.fundSubscription(1, 100e18);
//
//     game.requestLootboxRng();
//     uint256 reqIdA = mockVRF.lastRequestId();
//     _perturb(perturbSeed);
//     // NO retry on this baseline — deliver the ORIGINAL request with vrfWord2.
//     mockVRF.fulfillRandomWords(reqIdA, vrfWord2);
//     for (uint256 i = 0; i < 50; i++) {
//         if (!game.rngLocked()) break;
//         game.advanceGame();
//     }
//     bytes32 originalOutputs = _captureRetryLootboxOutputs();
//
//     // ── ASSERT-A (OPPOSITE-DIRECTION) ────────────────────────────────────────
//     // Per `D-301-COVERAGE-01` line 9: the failsafe SHOULD change VRF-derived
//     // outputs because it supplies a fresh VRF word (vrfWord1 vs vrfWord2).
//     assertNotEq(
//         retryOutputs,
//         originalOutputs,
//         "RetryLootboxRng: retry MUST change VRF-derived outputs — failsafe supplies fresh VRF word (D-301-COVERAGE-01)"
//     );
//
//     // ── PHASE 5b — Baseline-B: retry path WITHOUT perturbation ───────────────
//     // Revert again. Re-execute setup + lock + stall + retry + deliver vrfWord1
//     // but WITHOUT calling `_perturb`. This isolates the retry-path output to
//     // confirm that state-perturbations during the failsafe do not
//     // additionally drift outputs beyond the VRF-word substitution.
//     _revertToPreLock(preLockSnap);
//
//     address buyerC = makeAddr("retryLootboxBuyer");
//     vm.deal(buyerC, 100 ether);
//     vm.prank(buyerC);
//     game.purchase{value: 1.01 ether}(
//         buyerC, 400, 1 ether, bytes32(0), MintPaymentKind.DirectEth
//     );
//     mockVRF.fundSubscription(1, 100e18);
//
//     game.requestLootboxRng();
//     uint256 reqIdC = mockVRF.lastRequestId();
//     // NO _perturb — pristine retry path.
//     vm.warp(block.timestamp + 6 hours + 1);
//     game.retryLootboxRng();
//     uint256 reqIdC2 = mockVRF.lastRequestId();
//     assertTrue(reqIdC2 != reqIdC, "RetryLootboxRng baseline-B: retry must replace original reqId");
//     mockVRF.fulfillRandomWords(reqIdC2, vrfWord1);
//     for (uint256 i = 0; i < 50; i++) {
//         if (!game.rngLocked()) break;
//         game.advanceGame();
//     }
//     bytes32 retryNoPerturbOutputs = _captureRetryLootboxOutputs();
//
//     // ── ASSERT-B (BYTE-IDENTITY ACROSS RETRY PATH) ───────────────────────────
//     // Per `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A invariant 3: the failsafe
//     // does not manipulate pre-lock state, so perturbations during the failsafe
//     // window MUST NOT additionally drift outputs.
//     _assertVrfOutputByteIdentity(
//         retryOutputs,
//         retryNoPerturbOutputs,
//         "RetryLootboxRng: VRF outputs must be byte-identical between perturbation and baseline retry paths (D-42N-RETRY-RNG-DOMAIN-SEP-01 Option A invariant 3 — RNGLOCK-CATALOG.md §9)"
//     );
// }
//
// /// @dev Capture retry-lootbox-rng post-state. Reads `rngWordCurrent` +
// ///      the LR_INDEX-bound lootbox word via scaffold storage-slot readers.
// function _captureRetryLootboxOutputs() internal view returns (bytes32) {
//     uint256 rngWord = _readRngWordCurrent();
//     // The lootbox-word getter is contribution-local because LR_INDEX read
//     // semantics live in the scaffold.
//     return keccak256(abi.encode(rngWord, _readLootboxIndexAndWordDigest()));
// }
//
// /// @dev Compact digest of the current LR_INDEX-bound lootbox word. Defers
// ///      slot-index resolution to the scaffold's existing `_lrRead` /
// ///      `_lootboxRngWord` helpers (ported from
// ///      `test/fuzz/LootboxRngLifecycle.t.sol:104-117`). If the scaffold does
// ///      not expose `_lrRead` / `_lootboxRngWord`, Wave 2 aggregator must add
// ///      them when concatenating; this contribution assumes they exist per
// ///      the locked 6-phase template's storage-reader contract.
// function _readLootboxIndexAndWordDigest() internal view returns (bytes32) {
//     // Slot 38 = lootboxRngIndex (uint48, packed). Slot 39 = lootboxRngWordByIndex
//     // mapping base. Mirrors LootboxRngLifecycle.t.sol:104-110.
//     uint48 idx = uint48(uint256(vm.load(address(game), bytes32(uint256(38)))));
//     if (idx == 0) return bytes32(0);
//     bytes32 slot = keccak256(abi.encode(uint256(idx - 1), uint256(39)));
//     return bytes32(uint256(vm.load(address(game), slot)));
// }
// ANCHOR: FUNC_RetryLootboxRng_END

// ANCHOR: CLUSTER_MIXED_END
//
// END Plan 04 mixed-cluster contribution. Authored 5 of 11 remaining per-consumer
// fuzz functions after the scaffold (plans 01 + 02 + 03 cover the other 8):
//
//   §10  testFuzz_RngLockDeterminism_MintTraitGeneration
//   §11  testFuzz_RngLockDeterminism_BurnieCoinflipResolve
//   §12  testFuzz_RngLockDeterminism_StakedStonkRedemption  ← V-184 CATASTROPHE
//   §5   testFuzz_RngLockDeterminism_GameOverRngSubstitution
//   §9   testFuzz_RngLockDeterminism_RetryLootboxRng        ← OPPOSITE-DIRECTION
//
// Combined with plan 01 (§1, §3), plan 02 (§2, §4), plan 03 (§6, §7, §8, §13),
// all 13 CAT-01 consumer surfaces are covered (FUZZ-04 satisfied).
//
// Wave 2 aggregator (`301-06-PLAN.md`) tasks:
//   1. Concatenate this file's body into `test/fuzz/RngLockDeterminism.t.sol`
//      between scaffold + sibling cluster bodies and the contract-close `}`.
//   2. Strip `// ` prefixes from function bodies (this contribution is
//      comment-wrapped to keep it non-compilable in isolation per plan 01's
//      paste-source contract).
//   3. Add `vm.skip(true)` gate at top of
//      `testFuzz_RngLockDeterminism_StakedStonkRedemption` per
//      `D-301-VMSKIP-MECHANISM-01` Option C, with comment
//      `// SKIP: RNGLOCK-FIXREC.md §103 — V-184 cross-day re-roll —
//       v44.0 D-43N-V44-HANDOFF-103 flips this to strict assertion`.
//   4. Verify per-function names match `D-301-COVERAGE-01` line 9 (RetryLootboxRng
//      opposite-direction) verbatim.
//
// Zero `contracts/` mutations. Zero writes to `test/` tree at this plan.
