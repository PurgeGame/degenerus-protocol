---
phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
plan: 05
type: execute
wave: 3
completed: 2026-05-28
status: applied (uncommitted — held for BATCH-02 hand-review at Plan 335-07)
files_modified:
  - test/fuzz/AfKingSubscription.t.sol
  - test/fuzz/AfKingFundingWaterfall.t.sol
  - test/fuzz/AfKingConcurrency.t.sol
  - test/fuzz/KeeperNonBrick.t.sol
  - test/fuzz/RngFreezeAndRemovalProofs.t.sol
  - test/gas/KeeperLeversAndPacking.t.sol
  - test/gas/RouterWorstCaseGas.t.sol
files_untouched:
  - test/gas/KeeperOpenBoxWorstCaseGas.t.sol
requirements: [BATCH-02]
---

## Outcome

The 7 affected test files are migrated in lockstep with the contract diff (Plans 335-01..04) per the D-IMPL-02 FULL ALIGNMENT policy. All five v49 surfaces — `Sub.paidThroughDay`, `IBurnie.burnForKeeper`, AfKing-side `IGame.hasAnyLazyPass`, `OPEN_NORMAL_GAS_UNIT`, `_activateWhalePass` — are PURGED from `test/` (system-wide grep returns 0 lines for each). The new v50.0 surfaces — `Sub.validThroughLevel`, `IGame.lazyPassHorizon`, the AFSUB-03 crossing's refresh-or-evict-via-tombstone shape, the `whalePassClaims +=` deferred-claim record, the flat `OPEN_BATCH` placeholder — are positively asserted across the migrated test bodies. `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` is UNTOUCHED per the plan (Plan 335-06 re-runs the existing harness for the D-IMPL-04 OPEN_BATCH empirical pick). NO contract files were re-edited (this plan is test-only — the contracts/ diff from Plans 335-01..04 remains the prior wave's load-bearing surface).

**Working tree at completion:** `git status --short` shows 12 modified files (5 contracts from Plans 335-01..04 + 7 tests from this plan) plus this SUMMARY (untracked-then-committed under the planning-doc force-add pattern). NO modifications to STATE.md / ROADMAP.md — those are the orchestrator's writes at wave-close.

## Per-file migration breakdown (before -> after grep counts)

| File | paidThroughDay | burnForKeeper | hasAnyLazyPass | OPEN_NORMAL_GAS_UNIT | _activateWhalePass | validThroughLevel |
|------|----------------|---------------|----------------|----------------------|---------------------|-------------------|
| `test/fuzz/AfKingSubscription.t.sol` | 14 -> 0 | 11 -> 0 | 3 -> 0 | — | — | 0 -> 27 |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | 5 -> 0 | 6 -> 0 | 3 -> 0 | — | — | 0 -> 9 |
| `test/fuzz/AfKingConcurrency.t.sol` | 18 -> 0 | — | — | — | — | 0 -> 16 |
| `test/fuzz/KeeperNonBrick.t.sol` | 1 -> 0 | — | 1 -> 0 | — | — | 0 -> 7 |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | — | — | 7 -> 0 | — | — | 0 -> 0 |
| `test/gas/KeeperLeversAndPacking.t.sol` | 2 -> 0 | 2 -> 0 | — | — | — | 0 -> 3 |
| `test/gas/RouterWorstCaseGas.t.sol` | — | — | — | 6 -> 0 | 5 -> 0 | 0 -> 0 |
| **TOTAL across test/** | **40 -> 0** | **19 -> 0** | **14 -> 0** | **6 -> 0** | **5 -> 0** | **0 -> 62** |

(The 335-CONTEXT.md headline count was ~70 references across the 7 files. The actual grep totals 84 v49-side references purged, all replaced with the corresponding v50.0 surface or dropped where the v49 mechanism is structurally gone. `validThroughLevel` introduced at 62 lines >> the gate floor of 30.)

## Task-by-task migration record

### Task 1 — `test/fuzz/AfKingSubscription.t.sol` (the heaviest migration)

Storage oracle (`OFF_PAIDTHROUGH`) renamed to `OFF_VALIDTHROUGHLEVEL` (same offset 5, same uint32 width — Plan 335-04 Task 1 picked uint32 for zero packing churn). Helper `_forceRenewalDue` retargeted as `_forceCrossingDue` (writes `validThroughLevel = 0` + bumps `game.level` to ≥ 1 via a slot 0 / low-24-bit poke so `currentLevel > validThroughLevel` predicate is reachable on a fresh fixture). Helper `_fundBurnie` / BURNIE-balance assertions are DROPPED throughout — AFSUB-01 removed BURNIE involvement entirely.

Canonical migration replacements:

| Pre-edit test | Post-edit test | Branch tested |
|---------------|----------------|---------------|
| `testRenewalPassHolderFreeExtendNoCharge` | `testCrossingPassHolderRefreshedNotEvicted` | REFRESH (deity → horizon ≥ currentLevel → SubscriptionExtendedFree, validThroughLevel stamped past currentLevel) |
| `testRenewalNoPassChargedViaBurnForKeeper` | `testCrossingNoPassEvictedViaTombstone` | EVICT (no pass → horizon = 0 < currentLevel → SubscriptionExpired(.,1), dailyQuantity zeroed, swap-pop) |
| `testRenewalShortfallBurnsNothingAndAutoPauses` | `testSubscribeNoBurnieChargeRegardlessOfPass` | AFSUB-01 (no BURNIE charge at subscribe; v49 shortfall failure mode is structurally gone) |
| `testRenewalExactlyAtCostFullBurn` | `testNonCrossingPassHolderBuysWithoutRefresh` | AFSUB-02 (non-crossing per-iter is pure stored-field compare; no refresh event fires) |
| `testCrossAccountBurnieFundsWindowOneAndRenewal` | (subsumed by `testRevokeDoesNotStopActiveSubButDefundDoes` migrated for ETH-only routing) | OPENE-02 (ETH per-day draw — the only OPEN-E surface left after AFSUB-01) |

The `_logsCache` helper pattern (drain-once, lazily on first count call) replaces the v49 consume-per-call `_countEvent` shape. The v49 helper consumed `vm.getRecordedLogs()` per call, which silently zeroed every second assertion against the same buffer (accidentally matching v49 "expect 0" assertions while masking real bugs). The v50.0 drain-once shape supports multiple (sig, who) assertions per autoBuy correctly.

**Gate counts:** `paidThroughDay` 0, `burnForKeeper` 0, `validThroughLevel` 27, `testCrossing*` 2, `SubscriptionExpired` reference present (NatSpec + const decl + per-iter eviction assert).

### Task 2 — `test/fuzz/AfKingFundingWaterfall.t.sol` (OPEN-E re-attest + pass-eviction-preserves-fundingSource)

Funding waterfall branches (DirectEth / Claimable / Combined / sentinel / InsufficientPool) PRESERVED — those tests never touched the BURNIE surface. The pinned-identity SUB-06 exemption tests are PRESERVED; the SDGNRS test fixture is fixed-up via `_grantDeityPass(SDGNRS)` so SDGNRS' AFSUB-02 per-iter check is satisfied and the test reaches the funding-waterfall step (otherwise SDGNRS' v50.0 first-crossing eviction would moot the SUB-06 exemption assertion — see VAULT/SDGNRS handling decision below).

Three v49 tests RETIRED/replaced:

| Pre-edit test | Post-edit test | Reason |
|---------------|----------------|--------|
| `testRenewalLapseStillCancelsExemptSubs` | `testPassEvictionStillCancelsExemptSubs` | Migrated to the v50.0 AFSUB-03 crossing analog of the v49 day-31 BURNIE-shortfall lapse |
| `testCrossAccountBurnieFundsWindowOneAndRenewal` | DELETED | No BURNIE involvement under AFSUB-01; the OPENE-03 BURNIE-routing surface is structurally gone |
| `testCrossAccountBurnieSourceShortfallRevertsSubscribe` | DELETED | `BurnieChargeFailed` error deleted from `AfKing.sol` (Plan 335-04 Task 3 cleanup); test would not compile |
| `testRevokeDoesNotStopActiveSubButDefundDoes` (renamed in FundingWaterfall) | `testRevokeDoesNotEscalatePerDayDraw` | Migrated to ETH-only trust-the-sub property (the BURNIE-routing leg is gone) |

**NEW positive assertion (Task 3e, the new property replacing the v49 BURNIE-shortfall surface):** `testPassEvictionPreservesFundingSourceStorage` — pins the pass-eviction-vs-fundingSource decision (see "Pass-eviction-vs-fundingSource assertion shape" below).

OPEN-E 4-protection assertions all PRESERVED unchanged in spirit: consent-gate-at-subscribe (OPENE-04), default-self byte-identical (`testFundingSourceDefaultSelfIsByteEquivalent`), no-escalation (`testRevokeDoesNotEscalatePerDayDraw`), trust-the-sub temporal bound (same test, ETH leg). The LANDMINE A exemption-spoof test (`testFundingSourceVaultDoesNotInheritExemption`) is unchanged.

**Gate counts:** `paidThroughDay` 0, `burnForKeeper` 0, `fundingSource` 30 (the OPEN-E 4-protection plumbing + the new positive assertion), `hasAnyLazyPass` 0.

### Task 3 — `test/fuzz/AfKingConcurrency.t.sol` (swap-pop invariant + v50.0 AFSUB-05)

All 18 `paidThroughDay` slot writes rebased to `validThroughLevel` slot writes (`_setWindow` → `_setValidThroughLevel`, `_paidThroughDayOf` → `_validThroughLevelOf`). The v47 in-place cancel-tombstone + deferred reclaim invariants ALL PRESERVED — those properties were never tied to BURNIE.

**Major rewrite (Plan 335-04 Task 3 collapsed the preserve-vs-delete fork):** the v47 `testCancelPreservesPaidWindowThroughDeferredReclaim` + `testCancelPreservesPaidUnexpiredWindow` + `testCancelReclaimsUnpaidWindow` triplet (which asserted `windowPaid && paidThroughDay > today → preserve _subOf; else → delete`) is COLLAPSED into a single new `testCancelReclaimAlwaysDeletesSubRecord`. Plan 335-04 Task 3 dropped the `preservePaidWindow` carve-out under AFSUB-01 — every cancel-reclaim now does `delete _subOf[player]` unconditionally (AfKing._autoBuy:601-609). The new test pins this always-delete behavior by stamping a non-zero `validThroughLevel` pre-cancel and asserting the FULL record (dailyQuantity / validThroughLevel / flags / fundingSource) is zeroed at reclaim.

**NEW: v50.0 AFSUB-05 section** with two added tests pinning the swap-pop invariant under AFSUB-03 pass-eviction:
- `testPassEvictionPreservesSwapPopInvariant` — mass-eviction scenario (every test sub forced into the crossing branch with horizon = 0); every evicted sub gets the tombstone shape (`dailyQuantity = 0`, `_removeFromSet`, `SubscriptionExpired(.,1)`); membership ⟺ packed != 0 invariant holds; autoBuy does NOT revert despite N simultaneous evictions.
- `testPassEvictionBehindCursorDoesNotStrandPendingTail` — H-CANCEL-SWAP-MISS re-derivation under pass-eviction; the EVICT continue-without-cursor-advance (AfKing._autoBuy:642-645) ensures the swap-pop occupant is re-read at the freed slot the same iteration; deity-holding odd-indexed subs survive the crossing (REFRESH) while no-pass even-indexed subs evict (TOMBSTONE) and the pending tail is processed without strand.

**Gate counts:** `paidThroughDay` 0, `validThroughLevel` 16, `_subscriberIndexOf` 11 (the swap-pop invariant assertions throughout), "SwapPop"/"swap-pop" 7 (preserved naming + new AFSUB-05 section).

### Task 4 — `test/fuzz/KeeperNonBrick.t.sol`

Small rewrite per the plan. The single `paidThroughDay` reference (in a docstring) is replaced with a v50.0 AFSUB-03 crossing reference; the single `hasAnyLazyPass` reference (in a docstring) is replaced with an AFSUB-01 BURNIE-free-subscribe note. The two `_fundBurnieForSubscribe(player)` call sites are deleted (no BURNIE charge at subscribe under AFSUB-01); the `_fundBurnieForSubscribe` helper is left in place but is no longer reached (a future cleanup can delete it; out-of-scope for this plan's minimal-rewrite mandate).

The v47 `_setupAutoBuySubs` helper (used by 4 tests in this file) keeps its BURNIE-pre-mint call as harmless dead work — at currentLevel = 0 (the fresh fixture state) no crossing fires for test subs whose `validThroughLevel` is also 0, so the existing tests' assertion shapes are preserved without re-deriving the fixture setup.

**NEW: `testNoBrickUnderHeavyPassEviction`** added per Plan 335-05 Task 4(c) — under heavy concurrent pass-expiration (6 test subs forced into the crossing branch with horizon = 0, game.level bumped to 1), `autoBuy` MUST NOT revert AND the H-CANCEL-SWAP-MISS class does NOT reproduce. The new helper `_setValidThroughLevel(who, level)` is added in the `_afk*` helper cluster.

**Gate counts:** `paidThroughDay` 0, `burnForKeeper` 0, `hasAnyLazyPass` 0, `validThroughLevel` 7 (the new helper + the new test body).

### Task 5 — `test/fuzz/RngFreezeAndRemovalProofs.t.sol` (trivial freeze-side migrations)

All 7 `hasAnyLazyPass` references purged. The v45 `testKeptHasAnyLazyPassPresent` attestation is migrated to `testKeptLazyPassHorizonPresent` (asserts the v50.0 `lazyPassHorizon` view is present + returns `type(uint24).max` for the deity-bit holder). The legacy v49 boolean pass-view is documented as ALSO retained on the contract (Plan 335-01 preserved it for non-AfKing callers); the migrated test pins the new view's exposure.

**TWO NEW positive trivial freeze-side assertions added** per Plan 335-05 Task 5(b)+(c):
1. `testWhalePassClaimsWriteIsNonFrozenSlot` — source-level assertion that the `whalePassClaims[player] +=` write site is byte-present in `LootboxModule.sol` (post-Plan-335-02). The slot is a pending-claim accumulator per 334-WHALE04-FREEZE-PROOF §1 — NOT VRF-influenced, not in the freeze write-set.
2. `testLazyPassHorizonReadDoesNotPerturbFrozenSlots` — runtime assertion that `lazyPassHorizon(player)` is a pure read (vm.load-before/after on the `mintPacked_` slot is byte-identical); the freeze invariant is about writes to frozen slots, not reads. 334-WHALE04-FREEZE-PROOF §5 confirms.

**DEFERRED to Phase 336 / TST-01 freeze leg** (documented in the file's NatSpec block): the deeper RNG-freeze fuzz proof of the deferred-claim path — the `WhaleModule.claimWhalePass` invariant under rngLock + the fuzzed roundtrip equivalence. 336 owns the deeper freeze-fuzz extension of `RngLockDeterminism.t.sol`; this plan ships only the trivial assertions.

**Gate counts:** `hasAnyLazyPass` 0, two new test functions present, deferral comment present.

### Task 6 — `test/gas/KeeperLeversAndPacking.t.sol` (packing oracle rename + G8 deletion)

Two surgical edits:
- `_structFieldBytes(afking, "uint32 paidThroughDay;", 4)` → `_structFieldBytes(afking, "uint32 validThroughLevel;", 4)` (Plan 335-04 Task 1 kept uint32, so the width unchanged).
- The G8 byte-presence assertion `assertGt(_countOccurrences(afking, "burnForKeeper("), 0, ...)` is DELETED with its docstring; the `G8` token is purged.

The packing oracle's structural sum (31 bytes ≤ 32, single-slot) is preserved unchanged. The struct-decl NatSpec is updated to describe v50.0 AFSUB-01's in-place repurpose of slot offset 5.

**Gate counts:** `paidThroughDay` 0, `burnForKeeper` 0, `validThroughLevel` 3, `G8` 0.

### Task 7 — `test/gas/RouterWorstCaseGas.t.sol` (flat OPEN_BATCH placeholder + retired gas-weighted tests)

- The `OPEN_NORMAL_GAS_UNIT = 90_000` mirror constant DELETED (6 occurrences purged).
- The `_activateWhalePass`-named helper / docstring references DELETED (5 occurrences purged).
- The `WHALE_CLUSTER_WORD` constant + `_whalePassRngWord()` helper + `WHALE_OWNER_LABEL` + `WHALE_WEI` constants DELETED.
- Three v49 tests RETIRED (their property is structurally moot under v50.0 WHALE-01):
  - `testOpenLegWhalePassBoxMarginalIsTheRareWorstCase` — the 100-iter loop is gone; whale-pass boxes are uniform O(1).
  - `testWeightedOpenBudgetCapsClusteredWhalePassBatchUnderCeiling` — the gas-weighted budget is retired; there is no heavy-box "weight" to cap against.
  - `testWeightedOpenBudgetStructuralBoundUnderCeiling` — same.
- `OPEN_BATCH` constant kept as a PLACEHOLDER value `100` (the v49 carry-over) with a TODO comment citing Plan 335-06 as the finalizer. The TODO text: `TODO(Plan 335-06): finalize OPEN_BATCH from the KeeperOpenBoxWorstCaseGas measurement per D-IMPL-04 (chosen × measured ≤ 16.7M − HEADROOM).`
- `BUY_BATCH = 50` PRESERVED (the v49 buy-side worst-case derivation stands under v50.0 WHALE-01 — buy gas is unaffected).
- `WHALE_PASS_JACKPOT_TOPIC` constant kept (the `LootBoxWhalePassJackpot` event is still emitted at the caller-side per Plan 335-02 SUMMARY); the typical-regime test (`testTypicalOpenBatchAveragesNineMillion`) uses it to assert no whale-pass boon fired under `BOX_FIXED_WORD`.

**Gate counts:** `OPEN_NORMAL_GAS_UNIT` 0, `_activateWhalePass` 0, `WHALE_CLUSTER_WORD` 0, "weighted budget" 0, `OPEN_BATCH` present, `TODO(Plan 335-06)` present, `BUY_BATCH = 50` preserved.

## VAULT/SDGNRS first-crossing-eviction handling decision

**Decision: hybrid — accept eviction in tests that don't need the SUB-09 entries (default), re-seed deity in tests that REQUIRE the SUB-09 exemption surface as the property under test.**

Per Plan 335-04 Task 2's locked behavior change: the SUB-09 deploy-time self-subscribes (VAULT + SDGNRS) encode `validThroughLevel = lazyPassHorizon(VAULT/SDGNRS)`. VAULT carries the permanent deity bit (DegenerusGame ctor :213-214) so VAULT's horizon = `type(uint24).max` (the deity sentinel — VAULT survives any crossing). SDGNRS holds NO pass → SDGNRS' horizon = 0 → on the first autoBuy that reaches SDGNRS at a `currentLevel > 0`, SDGNRS evicts via the AFSUB-03 tombstone path.

Test-fixture handling per file:
- **Default (most tests in `AfKingSubscription.t.sol` + `AfKingFundingWaterfall.t.sol` + `AfKingConcurrency.t.sol` + `KeeperNonBrick.t.sol`):** ACCEPT the eviction as expected behavior on a fresh fixture. On a fresh fixture `game.level = 0` so the crossing predicate `currentLevel > validThroughLevel = 0` is FALSE for SDGNRS (`0 > 0` is false) — SDGNRS is NOT evicted on any test that runs autoBuy at `currentLevel = 0`. Tests that explicitly bump `game.level` to 1 (via `_forceCrossingDue` / `_bumpGameLevelToAtLeastOne`) accept SDGNRS' eviction as a side-effect; their assertions key on the TEST subs only (not SDGNRS).
- **Targeted re-seed (Task 2 `testVaultAndSdgnrsExemptFromFundingSkipKill` ONLY):** This is the ONE test whose property (the SUB-06 pinned-identity funding-skip exemption) requires SDGNRS to reach the funding-waterfall step. The test fixture re-grants the deity bit to SDGNRS via `_grantDeityPass(ContractAddresses.SDGNRS)` so SDGNRS' AFSUB-02 per-iter check is also satisfied (matching VAULT's structural deity coverage) and the test isolates the SUB-06 exemption property as intended. Documented inline in the test's NatSpec.

**Test functions codifying the choice:**
- DEFAULT (accept eviction): `testCrossingNoPassEvictedViaTombstone` (`AfKingSubscription.t.sol:119`), `testPassEvictionPreservesSwapPopInvariant` (`AfKingConcurrency.t.sol`), `testNoBrickUnderHeavyPassEviction` (`KeeperNonBrick.t.sol`), `testPassEvictionPreservesFundingSourceStorage` (`AfKingFundingWaterfall.t.sol`), `testPassEvictionStillCancelsExemptSubs` (`AfKingFundingWaterfall.t.sol` — explicitly clears VAULT's deity bit to force VAULT into the EVICT branch).
- TARGETED RE-SEED: `testVaultAndSdgnrsExemptFromFundingSkipKill` (`AfKingFundingWaterfall.t.sol:208`).

## Pass-eviction-vs-fundingSource assertion shape

**Plan 335-04 Task 3 chose `setDailyQuantity(0)`-style tombstoning (NOT `delete _subOf[player]`) for the AFSUB-03 EVICT branch.** Verified by reading the post-edit `AfKing.sol:638-645`:

```solidity
} else {
    // EVICT — route through tombstone-then-reclaim shape so the
    // v49 swap-pop invariant survives (Pitfall P6 — direct mid-
    // sweep removal would re-open H-CANCEL-SWAP-MISS).
    sub.dailyQuantity = 0;
    _removeFromSet(player);
    emit SubscriptionExpired(player, 1);
    didWork = true;
    unchecked {
        ++processed;
    }
    continue;
}
```

The EVICT branch writes ONLY `dailyQuantity = 0` (the tombstone sentinel); it does NOT do `delete _subOf[player]`. Therefore the `fundingSource` field (and `validThroughLevel`, `flags`, `reinvestPct`, `lastAutoBoughtDay`) are PRESERVED across the AFSUB-03 eviction. Contrast with the CANCEL-RECLAIM branch (AfKing._autoBuy:601-609) which DOES `delete _subOf[player]` on every reclaim under v50.0 AFSUB-01 (the `preservePaidWindow` carve-out is dropped).

**Test function codifying this:** `testPassEvictionPreservesFundingSourceStorage` (`AfKingFundingWaterfall.t.sol:439`). The test sets up a cross-account sub with `fundingSource = S`, no deity, then forces the crossing. Post-autoBuy: `afKing.subscriptionOf(m).fundingSource == s` (preserved), `dailyQuantity == 0` (tombstoned), `_subscriberIndexOf(m) == 0` (swap-popped). A future regression that switched EVICT to `delete _subOf[player]` would flip this RED.

## OPEN_BATCH placeholder + TODO

**Placeholder value used:** `OPEN_BATCH = 100` (the v49 carry-over value).

**TODO text** (`test/gas/RouterWorstCaseGas.t.sol:135-136`):
```
/// TODO(Plan 335-06): finalize OPEN_BATCH from the KeeperOpenBoxWorstCaseGas measurement per
///                   D-IMPL-04 (`chosen × measured ≤ 16.7M − HEADROOM`).
```

The const declaration's full docstring (lines 127-137) explains the v50.0 / Plan 335-01 retirement of the v49 gas-weighting and pins Plan 335-06 as the finalizer per D-IMPL-04.

## Plan-level verification gates (10/10 PASS)

| # | Gate | Result |
|---|------|--------|
| 1 | `grep -rnE "burnForKeeper" test/` returns 0 lines | ✓ 0 |
| 2 | `grep -rnE "paidThroughDay" test/` returns 0 lines | ✓ 0 |
| 3 | `grep -rnE "OPEN_NORMAL_GAS_UNIT" test/` returns 0 lines | ✓ 0 |
| 4 | `grep -rnE "_activateWhalePass" test/` returns 0 lines | ✓ 0 (after final RngFreezeAndRemovalProofs.t.sol NatSpec cleanup) |
| 5 | `grep -rnE "validThroughLevel" test/` returns ≥ 30 lines | ✓ 62 lines |
| 6 | `grep -nE "function testCrossing(PassHolderRefreshedNotEvicted\|NoPassEvictedViaTombstone)" test/fuzz/AfKingSubscription.t.sol` returns ≥ 2 lines | ✓ 2 (lines 81 + 119) |
| 7 | `grep -nE "G8" test/gas/KeeperLeversAndPacking.t.sol` returns 0 lines | ✓ 0 |
| 8 | `grep -nE "OPEN_BATCH" test/gas/RouterWorstCaseGas.t.sol` returns ≥ 1 line + TODO citing Plan 335-06 | ✓ 5 OPEN_BATCH refs + TODO at line 135 |
| 9 | `git diff test/gas/KeeperOpenBoxWorstCaseGas.t.sol` returns empty | ✓ empty (UNTOUCHED) |
| 10 | `grep -n "function hasAnyLazyPass" contracts/DegenerusGame.sol` STILL returns the original line | ✓ `:1520` (preserved per Plan 335-01) |

## Invariants re-attested

- **v45 VRF-freeze invariant** — Task 5 adds two trivial positive assertions: (1) the box-open `whalePassClaims +=` write is byte-present at the LootboxModule whale-pass activation site (a non-frozen-slot, per 334-WHALE04-FREEZE-PROOF §1); (2) the `lazyPassHorizon` view is a pure read that does not perturb the `mintPacked_` slot (334-WHALE04-FREEZE-PROOF §5). The deeper deferred-claim freeze fuzz is DEFERRED to 336/TST-01 freeze leg.
- **OPEN-E operator-approval trust boundary** — Task 2 preserves all 4 protection assertions (consent-gate-at-subscribe, default-self byte-identical, no-escalation, trust-the-sub temporal bound) and adds the new pass-eviction-preserves-fundingSource assertion.
- **AFKING cancel-tombstone + swap-pop invariant** — Tasks 1, 3, and 4 preserve the membership ⟺ packed != 0 invariant assertions; Task 3 re-derives H-CANCEL-SWAP-MISS under pass-eviction (the AFSUB-05 new tests); Task 4 adds the no-brick assertion under heavy concurrent pass-expiration.
- **GASOPT-05 per-iter no-external-read** — not directly asserted in tests (it is a gas-budget property of the contract); Task 6's packing oracle exercises the struct layout (no per-iter SLOAD widening).
- **D-IMPL-01 gameOver-forfeit structural guard** — N/A to test-only migration (the property is contract-side, attested via the `_livenessTriggered` transitivity in Plan 335-02 SUMMARY).

## STRIDE re-attested

| Threat ID | Result |
|-----------|--------|
| T-335-25 — test migration too lenient (drops a property) | Mitigated: PATTERNS §2.7-§2.13 specified concrete replacement assertions per task; the SUMMARY's gate-attestation block confirms each replacement asserts positively (testCrossing* / fundingSource / lazyPassHorizon / validThroughLevel patterns all grep-present). |
| T-335-26 — NEW red at Plan 335-06 = real regression vs fixture artifact | Mitigated: full-alignment D-IMPL-02 ensures tests follow new code in the SAME diff. Any NEW red at 335-06 is a real v50 regression by construction. |
| T-335-27 — test files reveal contract internals | Accepted (existing pattern): pre-edit tests already revealed slot offsets + packing oracles; the migration preserves the pattern, doesn't widen. |
| T-335-28 — VAULT/SDGNRS first-crossing eviction breaks the suite | Mitigated: explicit handling decision recorded above (hybrid: default-accept + targeted re-seed only where the SUB-06 exemption surface requires SDGNRS to reach the funding step). |
| T-335-29 — test imports a deleted symbol | Mitigated: each task's grep gates confirm every deleted symbol (`paidThroughDay`, `burnForKeeper`, `OPEN_NORMAL_GAS_UNIT`, `_activateWhalePass`) returns 0 across `test/`. The system-wide `forge build` gate at Plan 335-06 is the empirical re-attest. |

## Deferrals

- **Deeper RNG-freeze fuzz of the deferred-claim path** — `WhaleModule.claimWhalePass` invariant under rngLock + the fuzzed roundtrip equivalence — DEFERRED to Phase 336 / TST-01 freeze leg per 335-CONTEXT.md D-IMPL-02. Documented inline in `RngFreezeAndRemovalProofs.t.sol`'s NatSpec block.
- **MintModule same-traits-across-split regression test** — TST-03 — DEFERRED to Phase 336 per 335-03 SUMMARY + verdict §97.
- **Final OPEN_BATCH empirical value** — Plan 335-06 picks from the `KeeperOpenBoxWorstCaseGas` re-run per D-IMPL-04 (`chosen × measured ≤ 16.7M − HEADROOM`). This plan installs only the placeholder.
- **`SUB_COST_ETH_TARGET` immutable cleanup** — Plan 335-04's SUMMARY flagged it as a documented dead immutable awaiting either a follow-up cleanup or hand-review consideration at Plan 335-07. Test files keep reading it via `afKing.SUB_COST_ETH_TARGET()` to compute the v49 BURNIE-cost helper values for backwards-compat (those helpers are no longer called under v50.0 but the constant is harmless to read).

## key-files.created / modified

| Path | Action | Notes |
|------|--------|-------|
| `test/fuzz/AfKingSubscription.t.sol` | rewritten | The heaviest migration: pass-OR-pay → pass-eviction-OR-refresh; storage oracle renamed; helpers retargeted; ~28 v49 references purged; canonical `testCrossing*` pair authored. |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | rewritten | OPEN-E 4-protection preserved; BURNIE-side OPENE-03 tests retired; new pass-eviction-preserves-fundingSource positive assertion; SDGNRS deity re-seed for the one SUB-06 exemption test. |
| `test/fuzz/AfKingConcurrency.t.sol` | rewritten | All 18 paidThroughDay slot writes rebased to validThroughLevel; v50.0 AFSUB-05 swap-pop section added; preserve-vs-delete triplet collapsed into always-delete; H-CANCEL-SWAP-MISS re-derivation under pass-eviction. |
| `test/fuzz/KeeperNonBrick.t.sol` | small rewrite | 2 v49 references purged; `testNoBrickUnderHeavyPassEviction` added; `_setValidThroughLevel` helper added; `_fundBurnieForSubscribe` calls dropped. |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | trivial rewrite | 7 hasAnyLazyPass references purged; `testKeptLazyPassHorizonPresent` migrates the KEPT-view attestation; 2 new trivial positive freeze-side assertions; deeper freeze-fuzz deferred to 336/TST-01. |
| `test/gas/KeeperLeversAndPacking.t.sol` | surgical | Packing oracle string renamed; G8 byte-presence assertion + docstring deleted. |
| `test/gas/RouterWorstCaseGas.t.sol` | trimmed + placeholder | OPEN_NORMAL_GAS_UNIT mirror + 3 whale-pass-aware tests + WHALE_CLUSTER_WORD/_whalePassRngWord retired; OPEN_BATCH placeholder + TODO citing Plan 335-06; BUY_BATCH preserved. |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | UNTOUCHED | Plan 335-06 re-runs it for the D-IMPL-04 OPEN_BATCH measurement (the harness already measures the right thing under WHALE-01). |

## Self-Check: PASSED (10/10 plan-level gates pass + 7/7 per-task acceptance criteria pass)

**Self-check verifications:**

- All 7 test files exist and are modified per `git status --short` (the 12-file working tree). ✓
- All 5 contract files from Plans 335-01..04 remain uncommitted in the working tree (no contract re-edit by this plan). ✓
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` is UNTOUCHED (`git diff` empty). ✓
- All 10 plan-level grep gates pass per the verification block above. ✓
- VAULT/SDGNRS first-crossing-eviction handling choice recorded (hybrid: default-accept + targeted re-seed in `testVaultAndSdgnrsExemptFromFundingSkipKill`). ✓
- Pass-eviction-vs-fundingSource assertion shape recorded (Plan 335-04 chose tombstone-not-delete; `testPassEvictionPreservesFundingSourceStorage` pins the choice). ✓
- OPEN_BATCH placeholder value + TODO text recorded (`OPEN_BATCH = 100` placeholder; `TODO(Plan 335-06): finalize OPEN_BATCH from the KeeperOpenBoxWorstCaseGas measurement per D-IMPL-04 (chosen × measured ≤ 16.7M − HEADROOM)`). ✓
- Deferral to 336/TST-01 freeze leg recorded inline in `RngFreezeAndRemovalProofs.t.sol` NatSpec. ✓

**`forge build` + `forge test` are DEFERRED to Plan 335-06 per the plan's success criteria** (D-IMPL-03 / D-IMPL-04). The Wave-3 status at completion is: applied to disk, uncommitted; the integration oracle (`forge build` green) runs at Plan 335-06.

Status: applied to working tree, uncommitted. Wave 3 complete. Next: Plan 335-06 (local verification + OPEN_BATCH empirical pick + `KeeperOpenBoxWorstCaseGas` re-run).
