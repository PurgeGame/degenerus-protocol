# Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression — Research

**Researched:** 2026-05-28
**Domain:** Foundry test authoring against the v50.0 IMPL HEAD `e756a6f3` (FROZEN audit subject)
**Confidence:** **HIGH** (every mechanic verified vs live source + the v49 332 precedent; no novel infrastructure required)

## Summary

This is a **confirmation + mechanics** research, not a re-design. The Phase-336 design is fully locked by `336-CONTEXT.md` (D-TST01-01..04, D-TST02-01..02, D-TST03-01..04, D-TST04-01..04, D-CC-01..04). Every locked decision is **immediately implementable** against the live test tree at `e756a6f3` — the four narrow proof gaps (TST-01 freeze-fuzz extension, TST-01 dedicated equivalence/grant oracle, TST-01 uniform-O(1) one-liner, TST-02 `vm.expectCall(..., count: 0)` no-pass-SLOAD oracle, TST-03 cross-path equality, TST-04 baseline ledger) all map to existing harnesses or mirror the v49 332 ledger format verbatim.

Two findings sharpen the planner's path:

1. **`vm.expectCall` is brand new to this test tree** — zero existing usages anywhere under `test/` (verified by `grep -rn "expectCall" test/` returning empty). The TST-02 D-TST02-02 oracle is the first such use in the project. The implementation is standard Foundry forge-std cheatcode, but the planner should not assume a prior local pattern to follow — it's a one-off introduction with no risk of churn against existing tests.
2. **The TST-01 dedicated equivalence/grant-correctness oracle (D-TST01-03) IS a genuine gap.** The header of `test/fuzz/RngFreezeAndRemovalProofs.t.sol:38-44` (the 335-migrated file) explicitly DEFERS the box-open + claim roundtrip equivalence ("the `claimWhalePass` invariant under rngLock + the fuzzed roundtrip equivalence" is DEFERRED to 336). The 335 migrations landed ONLY the trivial source-grep + view-purity assertions — the deferred substance is exactly what 336 must close.

**Primary recommendation:** plan 5 sequential plans (mirror v49 332's 6-plan structure, narrower scope) on a single sequential-main branch, per-plan atomic commits, final ledger commit `autonomous: false` (USER gate at the binding NAME-set-equality headline). No worktrees.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Freeze-fuzz extension (TST-01 freeze leg) | `test/fuzz/RngLockDeterminism.t.sol` extension | — | LOCKED by ROADMAP + v49 332 D-precedent; D-TST01-01 |
| Whale-pass equivalence/grant oracle (TST-01 D-TST01-03) | New focused contract OR extension of an existing equivalence-suited file | `test/fuzz/RngFreezeAndRemovalProofs.t.sol` (currently holds only source-grep assertions; pattern-mapper's call whether to extend or author fresh) | The roundtrip equivalence is the explicit DEFERRED-to-336 substance per the file's own header |
| Uniform-O(1) gas equivalence one-liner (TST-01 D-TST01-04) | `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` extension | — | Already wired in 335-06 D-IMPL-04; no new harness |
| `vm.expectCall(IGame.lazyPassHorizon.selector, count: 0)` oracle (TST-02 D-TST02-02) | `test/fuzz/AfKingSubscription.t.sol` (the existing `testNonCrossingPassHolderBuysWithoutRefresh:182` is the closest analog) | OR a sibling test contract therein | Already has the deity-pass setup helpers + non-crossing scaffold; the new `count:0` assertion wraps the existing `afKing.autoBuy(50)` call |
| MINTDIV cross-path equality (TST-03) | New dedicated file (likely `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol`) OR extension of `test/fuzz/GameOverPathIsolation.t.sol` (already drives `processTicketBatch` via gameOver-drain) | — | D-TST03-04 — pattern-mapper picks; no MINTDIV-shaped analog exists |
| v50.0 baseline ledger (TST-04) | New `test/REGRESSION-BASELINE-v50.md` | — | Mirrors `test/REGRESSION-BASELINE-v49.md` §1/§2/§6 verbatim with version + commit substituted |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundry (`forge`) | repo's pinned version (foundry.toml `solc_version = "0.8.34"`, `via_ir = true`) | The whole-tree test runner | The audit subject is exclusively Foundry-tested for the NON-WIDENING gate; Hardhat parity is a SECONDARY gate per D-TST04-03 |
| `forge-std` (`Vm.sol`) | `lib/forge-std/src/` (pinned) | `vm.expectCall` / `vm.recordLogs` / `vm.snapshot`/`vm.revertTo` / `vm.store` / `vm.load` / `vm.prank` / `vm.warp` cheatcodes | The Foundry-native primitives all proofs rest on |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `test/fuzz/helpers/DeployProtocol.sol` | live | Stand up `game` / `coin` / `dgnrs` / `mockVRF` / `vault` / `affiliate` / `admin` / `afKing` for any test | Every existing AfKing / RngLock test inherits from it; TST-03's new file should too |
| `test/fuzz/helpers/VRFHandler.sol` | live | VRF coordinator harness (fulfillRandomWords / pending request tracking) | Required for the freeze-fuzz leg (TST-01 D-TST01-02) when triggering the RNG window |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `vm.expectCall(IGame.lazyPassHorizon.selector, count: 0)` | static grep for `lazyPassHorizon` call sites under `_autoBuy` non-crossing branch | rejected at SPEC (D-TST02-02) — misses dynamic indirect dispatch; the runtime oracle is the load-bearing proof |
| Cross-path equality via `TraitsGenerated` event capture | Direct `traitBurnTicket[level][traitId]` storage diff between path-A and path-B | both work; event capture is the v41 `MintBatchDeterminism.test.js` precedent (Hardhat side); storage diff is cleaner for byte-identity. Planner's call — D-TST03-04 says pattern-mapper picks |
| Re-author the freeze-fuzz proof in a new file | Extend `RngLockDeterminism.t.sol` in place | **HARD LOCKED** by the roadmap (D-TST01-01) — a parallel-harness anti-pattern. Do NOT author `RngLockFreezeSafetyV50.t.sol` |

**Installation:** no new dependencies — every primitive already available via `foundry.toml`.

**Version verification:** N/A (no package installs; the repo's pinned forge-std is the only dependency added).

## Package Legitimacy Audit

**N/A.** This phase installs zero external packages. All test additions reuse the existing Foundry + forge-std cheatcode surface already pinned in `lib/forge-std/`.

## Architecture Patterns

### System Architecture Diagram

```
                ┌────────────────────────────────────────────────────────────┐
                │  Phase 336 — Test/Planning ONLY (NO contracts/*.sol edit)  │
                └────────────────────────────────────────────────────────────┘
                                          │
        ┌──────────────────┬──────────────┴──────────────┬─────────────────────┐
        │                  │                             │                     │
        ▼                  ▼                             ▼                     ▼
  ┌──────────┐       ┌──────────┐               ┌─────────────────┐   ┌─────────────┐
  │  TST-01  │       │  TST-02  │               │     TST-03      │   │   TST-04    │
  │  (3 oracles)     │ (1 oracle)               │ (1 anchor + fuzz)   │ (1 ledger)  │
  └──────────┘       └──────────┘               └─────────────────┘   └─────────────┘
       │                  │                             │                     │
   ┌───┼───┐          (vm.expectCall)             (deterministic +        (mirror v49
   │   │   │          targets the                  boundary fuzz             ledger §1/§2
   ▼   ▼   ▼          IGame.lazyPassHorizon         on owed ∈                §6 verbatim;
 RngLock-  Roundtrip  selector with                 [maxT+1, maxT+200])      42-name set
 Determi-  equiv-     count:0 on the                                          B9 OUT,
 nism      alence/    non-crossing                                            invariant_no
 .t.sol    grant      autoBuy path                                            EthCreation +
 (extend)  oracle     in                                                     invariant_ghost
       │   (D-TST01-  AfKingSubscription                                     AccountingNet-
       │    03 home)  .t.sol                                                  Positive IN)
       │                       │                             │
       ▼                       ▼                             ▼
 KeeperOpenBoxWorstCaseGas    ─── all 4 proofs go into the NAME set for ───── ▶
 .t.sol gas-equivalence
 |whale - non_whale| ≤ 500       test/REGRESSION-BASELINE-v50.md §2          ledger
 (D-TST01-04)                    (the 42-name v50 union)                     authored
                                                                              last,
                                                                              committed
                                                                              autonomous:
                                                                              false
                                                                              (USER gate)
```

### Recommended Project Structure

```
test/
├── fuzz/
│   ├── RngLockDeterminism.t.sol          # EXTEND in place (TST-01 freeze leg)
│   ├── RngFreezeAndRemovalProofs.t.sol   # Possibly extend (TST-01 D-TST01-03 if planner picks this home)
│   ├── AfKingSubscription.t.sol          # EXTEND with the no-pass-SLOAD oracle (TST-02 D-TST02-02)
│   ├── AfKingFundingWaterfall.t.sol      # Candidate home for D-TST02-02 (already has crossing-tests)
│   ├── AfKingConcurrency.t.sol           # Candidate home for D-TST02-02
│   ├── KeeperNonBrick.t.sol              # Candidate home for D-TST02-02
│   └── MintModuleDivergenceAcrossSplit.t.sol  # NEW (TST-03; or extension of GameOverPathIsolation.t.sol)
├── gas/
│   └── KeeperOpenBoxWorstCaseGas.t.sol   # EXTEND with the one-line whale-vs-non-whale equivalence (TST-01 D-TST01-04)
└── REGRESSION-BASELINE-v50.md            # NEW — mirrors REGRESSION-BASELINE-v49.md (TST-04 D-TST04-01)
```

### Pattern 1: Foundry results-equality (cross-path oracle for TST-03)

**What:** Run the SAME scenario through two distinct code paths; assert per-item byte-identical output.
**When to use:** Whenever a one-liner fix changes WHEN something happens but not WHAT (the MINTDIV-02 `:716` `>>1`→`+=take` alignment is the canonical case — the LCG seed `baseKey` is now stable across slice boundaries).
**Example:**
```solidity
// Source: v49 332 D-precedent (GASOPT same-results + degeneretteResolve byte-identical-results)
// Path A: narrow-budget slices — multiple processTicketBatch calls that force a mid-player split
//         at owed=300, maxT=292 (per 334-MINTDIV01-REACHABILITY-VERDICT.md).
// Path B: fat-budget single call — same owed, same player, same level, same VRF word; one
//         contiguous processTicketBatch.
// Oracle: capture per-call TraitsGenerated events (the 3-arg shape: address indexed player,
//         uint256 baseKey, uint32 take) + the post-call traitBurnTicket[level][traitId]
//         storage state for every trait id 0..255 for the player.
// Assert: byte-identical multiset of credited (player, traitId, count) tuples between A and B.
```

### Pattern 2: `vm.expectCall(selector, count)` no-pass-SLOAD oracle (TST-02)

**What:** Wrap a top-level call site with `vm.expectCall(targetAddress, abi.encodeWithSelector(IGame.lazyPassHorizon.selector), 0)` so the cheatcode tracks **every** call into that selector at that address over the duration of the test and asserts the count equals the expected number (0 for the non-crossing path).
**When to use:** The hot path "non-crossing" autoBuy iteration — where pass-eviction must NOT fire `lazyPassHorizon` because `currentLevel <= sub.validThroughLevel` is the cheap stored-field branch.
**Example:**
```solidity
// Source: forge-std cheatcode (the 3-arg variant: target, data, count)
// AfKing.sol:628 reads `GAME.lazyPassHorizon(player)` ONLY inside the crossing branch (:627-:647).
// Non-crossing path: the loop hits the `currentLevel <= sub.validThroughLevel` early-skip
// (no SLOAD into GAME) and proceeds to the cheap buy stamp.

// In the test:
vm.expectCall(
    address(game),                                          // the IGame target (= the game facade)
    abi.encodeWithSelector(IGame.lazyPassHorizon.selector), // the selector
    0                                                       // EXACTLY ZERO calls expected
);
vm.prank(makeAddr("autoBuyer_no_pass_sload"));
afKing.autoBuy(50);
// vm.expectCall is automatically verified at the test's end — no manual assertEq needed.
```

**Trap to watch:** `vm.expectCall` matches based on the calldata prefix (the selector + args), NOT on whether the call is `STATICCALL` vs `CALL`. A view fn called via `STATICCALL` still gets counted. This is correct behavior for the D-TST02-02 oracle — "any external read of the selector" is what we want to assert is zero.

**Trap to watch:** the cheatcode does NOT count a call made BEFORE the `vm.expectCall` line — it only counts calls AFTER it. Make sure the staging (sub setup, deity-pass grant, fund) happens BEFORE the `vm.expectCall` so it doesn't accidentally consume the budget. **Verified pattern:** stage → `vm.expectCall(..., 0)` → `afKing.autoBuy(50)` → end of test.

### Pattern 3: Same-tx freeze-fuzz under default profile + `FOUNDRY_PROFILE=deep` gate (TST-01 freeze leg)

**What:** Routine runs use `[fuzz] runs=1000` / `[invariant] runs=256 depth=128`; deep runs gate behind `FOUNDRY_PROFILE=deep` (`[profile.deep.fuzz] runs=10000` / `[profile.deep.invariant] runs=1000 depth=256`).
**When to use:** Whenever the freeze-byte-identity proof needs to sample a wide perturbation space — the v44 INV / v49 332 D-precedent (D-TST01-02).
**Example:** the existing `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` (RngLockDeterminism.t.sol:1839) is the EXACT template. Author the new same-tx-with-`claimWhalePass` perturbation function the same way: a new `_perturb` class (cls == 11 for `claimWhalePass`, cls == 12 if a stateful invariant handler is added for the same-tx perturbation needs one), and a new test function `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` that mirrors the AutoBuy template with the `claimWhalePass` perturbation. The v44 deep-profile gating mechanism is `foundry.toml`'s `[profile.deep.*]` — no test-side annotation needed; the profile is selected at runtime via env var.

### Anti-Patterns to Avoid

- **Authoring a parallel freeze-fuzz harness file** (e.g., `RngLockFreezeSafetyV50.t.sol`): explicitly LOCKED OUT by D-TST01-01 + the v49 332 D-precedent. The roadmap names `RngLockDeterminism.t.sol` as THE home. A parallel harness duplicates the proof surface (research Pitfall 1) and risks invariant drift between the two.
- **Treating the TST-04 gate as a bare count match** (`failed == 42`): LOCKED OUT by D-TST04-02. The v49 ledger's binding sentence is *"the live failing set == the 42-name §2 enumerated union BY NAME — net-zero new regression. The gate is a strict NAME-set equality, NOT a count match."* Use the v49 §6 ledger's set-comparison protocol (`live − union == ∅` AND `union − live == ∅`).
- **Patching a v50 contract regression under TST-04**: LOCKED OUT by D-TST04-04. If a proof red surfaces that is a genuine new v50 contract regression (not a 335-migration fixture artifact), STOP and re-open IMPL — do NOT mask it as a fixture-migration issue.
- **Re-asserting WHALE-01/02 roundtrip equivalence in the 335-migrated files**: per the explicit deferral at `RngFreezeAndRemovalProofs.t.sol:38-44`, the roundtrip equivalence is the gap 336 must close. Don't re-derive coverage you think 335 already landed; READ the file header first.
- **Using the OLD 6-arg `TraitsGenerated` event signature for TST-03**: the live event at `contracts/storage/DegenerusGameStorage.sol:485` is `TraitsGenerated(address indexed player, uint256 baseKey, uint32 take)` (3 args). The v41-era tests in v49 §2 Bucket B (e.g., `RngIndexDrainBinding.t.sol`'s topic-hash hardcode) expect the OLD 6-arg shape — that's exactly why they're carried-forward reds. TST-03 must use the CURRENT signature.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pass-SLOAD-counting oracle | A custom external-call recorder on `IGame.lazyPassHorizon` | `vm.expectCall(target, abi.encodeWithSelector(IGame.lazyPassHorizon.selector), 0)` | Forge-std handles call tracking + verification at test end; zero infra to author |
| Freeze-byte-identity proof | Hand-roll a `keccak256(state || word)` digest | `vm.snapshot()` / `vm.revertTo()` + per-slot `vm.load()` (the existing `RngLockDeterminism.t.sol` harness shape) | The v43 harness already has the digest-vs-snapshot pattern; reuse the helpers (`_advanceToVrfRequestBoundary`, `_deliverMockVrf`, `_snapshotPreLock`, `_revertToPreLock`, `_assertVrfOutputByteIdentity`) verbatim |
| Cross-path equality oracle | Off-chain reference reimplementation of `_raritySymbolBatch` LCG | Two on-chain calls + storage-diff or event-capture — the LCG is deterministic, so two paths against the SAME `(player, level, owed, queueIdx, entropy)` LCG seed produce byte-identical output | An off-chain mirror (`raritySymbolBatchRef.mjs` exists at `test/helpers/`) drifts vs the contract over time; in-Foundry both paths drive the same compiled `_raritySymbolBatch` |
| v50 baseline ledger | A fresh enumeration scheme | Mirror `test/REGRESSION-BASELINE-v49.md` §1 (arithmetic) + §2 (the 42-name buckets A/B/C) + §6 (set-equality proof + the false-confidence guards FC1-FC4) verbatim | Format is precedent-locked; the planner's job is data, not format |

**Key insight:** The v49 332 TST built every pattern this phase needs. 336 is narrow execution against a fully-locked SPEC — there's no novel architecture to invent.

## Runtime State Inventory

**N/A — Phase 336 is a TST phase, not a rename/refactor/migration.** No stored data is renamed, no live service config is migrated, no OS-registered state is touched, no secret env vars are renamed, no build artifacts carry an old name. The only artifacts authored are: new test functions in 5 existing test files, possibly 1 new test file, and 1 new markdown ledger.

## Common Pitfalls

### Pitfall 1: `vm.expectCall` consumption-before-stage

**What goes wrong:** Calling `vm.expectCall(..., 0)` BEFORE the per-player setup (deity-grant, fund pool, subscribe) — the staging itself reads `lazyPassHorizon` (e.g., `_grantDeityPass` may read it indirectly via state-check helpers), bumping the count to 1 and breaking the "count==0" assertion.
**Why it happens:** `vm.expectCall` starts counting immediately on the next external call; setup code is external by default.
**How to avoid:** Order is **strictly**: (1) stage subscriber, fund pool, ensure non-crossing (currentLevel ≤ validThroughLevel by leaving it at the deity sentinel uint24.max), (2) `vm.expectCall(..., 0)`, (3) `vm.prank(autoBuyer)`, (4) `afKing.autoBuy(50)`. Nothing between 2 and 4.
**Warning signs:** test fails immediately with `vm.expectCall: counted 1 of expected 0 calls` — the offending call is in the staging.

### Pitfall 2: Fixture-migration artifact masquerading as a v50 regression at TST-04

**What goes wrong:** A NEW red in the v50 TST run that LOOKS like a v50 contract regression but is actually a fixture-migration artifact from 335 D-IMPL-02 that wasn't caught at 335-06 LOCAL-VERIFICATION.
**Why it happens:** The 335-06 ledger documented 9 closed migration artifacts (the `_forceCrossingDue` slot-0 byte-14 fix + 4 sibling helpers + a GAME-shortcut grep). A new fixture-migration artifact could still surface if a 336 plan touches one of the migrated files (e.g., adding the no-pass-SLOAD oracle to `AfKingSubscription.t.sol`).
**How to avoid:** Apply D-IMPL-03's row-1 rule from 335-CONTEXT — fixture-migration artifacts are reconciled in the same plan that introduces them. The TST-04 ledger only attests REAL v50 contract behavior (the legitimate `invariant_noEthCreation` + `invariant_ghostAccountingNetPositive` widening per 335-07's B9-OUT / two-invariants-IN narrative is the ONLY legitimate v50 baseline shift; any other NEW red is either a fixture-migration artifact (close in-plan) or a STOP-and-re-spec event (rare; D-TST04-04 says re-open IMPL, not patch the contract under TST-04).
**Warning signs:** A new red that grep-traces to a 336-plan-touched test file. Compare per-test-file diff before/after each plan.

### Pitfall 3: TraitsGenerated event signature drift

**What goes wrong:** Authoring TST-03's TraitsGenerated capture against the OLD 6-arg shape (`address,uint24,uint32,uint32,uint32,uint256`) because it appears in carried-forward red-set test files like `RngIndexDrainBinding.t.sol:25`.
**Why it happens:** Buckets B's v48-era stale-harness tests still ENCODE the old topic hash; they're red precisely because the event was reshaped to the 3-arg form.
**How to avoid:** Use `keccak256("TraitsGenerated(address,uint256,uint32)")` — the live signature at `DegenerusGameStorage.sol:485-489`. The indexed `player` is in `topics[1]`; the non-indexed `(baseKey, take)` are in the data payload.
**Warning signs:** `vm.recordLogs()` returns events but the topic-0 filter matches nothing in the new TST-03 test (silent zero captures = wrong topic-hash).

### Pitfall 4: Mistaking the v49 baseline's B9 / B10 disposition at TST HEAD

**What goes wrong:** The 335-07 SUMMARY notes B9 (`AfKingSubscription.testRenewalExactlyAtCostFullBurn`) was DELETED in Plan 335-05 (the v49 day-31 PAID-renewal premise was retired by AFSUB-01) and B10 (`AfKingFundingWaterfall.testFundingSourceVaultDoesNotInheritExemption`) flipped GREEN at v50 IMPL (the `BurnieChargeFailed` path is structurally gone). The TST-04 §2 v50 enumeration must REMOVE B9 + B10 from the carried-forward set and ADD `invariant_noEthCreation` + `invariant_ghostAccountingNetPositive`. Net 42 → 42 (4 reds replaced — 2 OUT, 2 IN, but only 1 removal in §2 because B10 was already-green at v50 and B9 was deleted).
**Why it happens:** Verbatim-copying the v49 §2 union without applying the documented v50 deltas drops the binding NAME-set-equality property.
**How to avoid:** Compute the v50 set as: `{v49 §2 42-name union} − {B9 testRenewalExactlyAtCostFullBurn (DELETED)} − {B10 testFundingSourceVaultDoesNotInheritExemption (GREEN at v50)} + {invariant_noEthCreation, invariant_ghostAccountingNetPositive}` = 42 − 2 + 2 = **42**. See §"Pre-derived v50 baseline set" below for the explicit enumeration.
**Warning signs:** the §6 set-equality check shows `union − live` returning {B9} or {B10} → confirms you forgot to remove them from §2.

### Pitfall 5: Snapshot/revertTo state pollution across freeze-fuzz iterations

**What goes wrong:** The existing `_perturb` library has 11 perturbation classes; a freeze-fuzz iteration that uses `vm.snapshot()` + `_perturb(seed)` + `vm.revertTo(snapshotId)` MUST ensure the revertTo restores **every** state slot the perturbation touched, including any new state added by the WHALE-01 `whalePassClaims +=` accumulator.
**Why it happens:** `vm.snapshot()` captures full EVM state at the moment of call, but a perturbation that calls `claimWhalePass()` could land state mutations the snapshot was intended to cover.
**How to avoid:** Mirror the existing `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` pattern (lines 1839-1928) — snapshot pre-lock, perturb in-lock, deliver word, capture, revertTo, re-deliver SAME word, capture baseline. The byte-identity assertion is then `perturbedWord == baselineWord`. The existing helpers `_snapshotPreLock` / `_revertToPreLock` handle this correctly.
**Warning signs:** the freeze test passes locally but fails sporadically in CI (state-pollution drift between snapshot and revert).

## Code Examples

Verified patterns from the live test tree at `e756a6f3`:

### Existing TST-01 router-context freeze-byte-identity (the AutoBuy/doWork analog)

```solidity
// Source: test/fuzz/RngLockDeterminism.t.sol:1839-1928 (testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe)
// The EXACT template for the new TST-01 freeze-fuzz extension covering same-tx claimWhalePass

function testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe(uint256 seed) public {
    uint256 vrfWord = uint256(keccak256(abi.encode("tst01-claim-word", seed)));
    address claimant = makeAddr("tst01-claim-claimant");
    address buyer = makeAddr("tst01-claim-buyer");
    vm.deal(buyer, 100 ether);

    _completeDay(0xDEAD0904);
    vm.warp(block.timestamp + 1 days);

    // Pre-load whalePassClaims[claimant] > 0 via the box-open path so the claim has work to do.
    // (Buyer opens a lootbox at the box-open record path; WHALE-01 lands the O(1) += grant.)
    // ... staging code mirroring the AutoBuy test's _fundBurnie + reverseFlip nudges ...

    uint256 preLockSnap = _snapshotPreLock();

    // ---- perturbed: claimWhalePass fires inside the locked window ----
    uint256 reqId = _advanceToVrfRequestBoundary();
    assertTrue(game.rngLocked(), "TST-01 claim: rngLock must engage");

    // The claim during rngLock: per WHALE-04 §2, far-future band (lvl > currentLevel+5) REVERTS
    // under rngLock (Storage:661); near-future band lands in a disjoint write keyspace; the
    // whole claim reverts under _livenessTriggered() (WhaleModule:1019). The freeze proof asserts
    // that this REVERT during rngLock does NOT perturb the consumed VRF-derived output.
    try game.claimWhalePass(claimant) {} catch {} // may revert (expected during rngLock far-future)

    _deliverMockVrf(reqId, vrfWord);
    uint256 perturbedWord = _lootboxRngWord(_readLootboxRngIndex());

    // ---- baseline: SAME word, no claim ----
    _revertToPreLock(preLockSnap);
    _advanceToVrfRequestBoundary();
    _deliverMockVrf(mockVRF.lastRequestId(), vrfWord);
    uint256 baselineWord = _lootboxRngWord(_readLootboxRngIndex());

    _assertVrfOutputByteIdentity(
        bytes32(perturbedWord),
        bytes32(baselineWord),
        "TST-01 claim: claimWhalePass perturbation must NOT alter the consumed per-index word"
    );
}
```

### Existing TST-01 uniform-O(1) gas measurement structure

```solidity
// Source: test/gas/KeeperOpenBoxWorstCaseGas.t.sol (the harness 335-06 already wired)
// The current harness measures per-box marginal (74_756) + per-box single-box total (113_875).
// The 335-06 LOCAL-VERIFICATION already attested uniform-O(1) at the structural level
// (no whale-vs-non-whale code-path divergence at box-open). TST-01 D-TST01-04 ADDS:

function testWhaleOpenerEqualsNonWhaleOpenerGas() public {
    uint48 index = _activeLootboxIndex();

    // Stage two distinct box-openers; one is a whale-pass holder, one is not.
    // Per WHALE-01 D-04 + the 335-02 IMPL, the only state difference at box-open is whether
    // whalePassClaims[opener] gets a `+= 1` accumulator write — strict O(1) regardless of state.
    address nonWhaleOpener = makeAddr("non_whale_opener");
    address whaleOpener   = makeAddr("whale_opener");
    vm.deal(nonWhaleOpener, 100 ether);
    vm.deal(whaleOpener, 100 ether);
    _grantWhalePassBoonOnNextOpen(whaleOpener); // (test-side helper that ensures the BOON_WHALE_PASS
                                                  //  roll deterministically fires on whale's box-open;
                                                  //  the exact mechanism is to pre-seed the per-index
                                                  //  word to a value whose `BOON_WHALE_PASS` bit is set)

    _buyBox(nonWhaleOpener, LOOTBOX_WEI);
    _buyBox(whaleOpener, LOOTBOX_WEI);
    _injectLootboxRngWord(index, FIXED_WORD);

    vm.prank(nonWhaleOpener);
    uint256 g0 = gasleft();
    game.autoOpen(1);
    uint256 gNonWhale = g0 - gasleft();

    vm.prank(whaleOpener);
    g0 = gasleft();
    game.autoOpen(1);
    uint256 gWhale = g0 - gasleft();

    uint256 delta = gWhale > gNonWhale ? gWhale - gNonWhale : gNonWhale - gWhale;
    assertLe(delta, 500, "TST-01 D-TST01-04: |whale - non_whale| ≤ 500 gas (uniform O(1) per WHALE-03)");

    emit log_named_uint("gas_whale_opener", gWhale);
    emit log_named_uint("gas_non_whale_opener", gNonWhale);
    emit log_named_uint("gas_delta", delta);
}
```

**Note:** the 335-06 ledger reports per-box marginal = 74_756. The two openers share the SAME `autoOpen` code path; the only divergence is the `whalePassClaims[opener] += 1` accumulator write inside `_activateWhalePass:1253`. An SSTORE-cold is ~22_100 gas, SSTORE-warm (subsequent) ~5_000 gas; the +1 increment vs no-increment is ~5_000 if the slot has been touched, ~22_100 if cold. **The 500-gas tolerance in D-TST01-04 may be too tight if the whale-pass opener's `whalePassClaims` slot is cold.** Recommendation: the planner should consider widening the tolerance to ~25_000 (cold SSTORE worst case) OR pre-warming the slot in setup (with a no-op `whalePassClaims[whaleOpener] += 0` via `vm.store`). This is a LOW-confidence call — empirical measurement in the plan execution will resolve it.

### Existing TST-02 closest-analog (the non-crossing path test)

```solidity
// Source: test/fuzz/AfKingSubscription.t.sol:182-199 (testNonCrossingPassHolderBuysWithoutRefresh)
// The EXACT staging shape for the new D-TST02-02 oracle:

function testNonCrossingPassHolderBuysWithoutRefresh() public {
    address pass = makeAddr("nx_pass_holder");
    _grantDeityPass(pass);                 // horizon = uint24.max (deity sentinel)
    _subscribeTicketMode(pass, 1);         // validThroughLevel = uint24.max
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);
    // DO NOT force crossing — leave validThroughLevel at the sentinel so currentLevel ≤ horizon.

    vm.recordLogs();
    vm.prank(makeAddr("autoBuyer_nx"));
    afKing.autoBuy(50);

    // Non-crossing path: NO refresh event, NO eviction event for this sub.
    assertEq(_countEventFor(address(afKing), EXTENDED_FREE_SIG, pass), 0, "non-crossing: no refresh");
    assertEq(_countEventFor(address(afKing), SUB_EXPIRED_SIG, pass), 0, "non-crossing: no eviction");
    assertGt(_subscriberIndexOf(pass), 0, "non-crossing sub stays in set");
}

// THE D-TST02-02 ADDITION (new test contract function in the SAME file):
function testNonCrossingPathPerformsZeroLazyPassHorizonSloads() public {
    address pass = makeAddr("nx_no_sload_holder");
    _grantDeityPass(pass);                 // horizon = uint24.max
    _subscribeTicketMode(pass, 1);         // validThroughLevel = uint24.max → non-crossing
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);

    // The hot-path-accurate oracle: zero external pass reads on the non-crossing iteration.
    vm.expectCall(
        address(game),                                          // IGame facade target
        abi.encodeWithSelector(IGame.lazyPassHorizon.selector), // selector only — matches any (address) arg
        0                                                       // EXACTLY ZERO calls
    );
    vm.prank(makeAddr("autoBuyer_no_sload_check"));
    afKing.autoBuy(50);
    // Cheatcode auto-verifies on test teardown — no explicit assertEq needed.
}
```

### TST-03 cross-path equality (the load-bearing new test)

```solidity
// Source: pattern from v49 332 GASOPT same-results D-precedent + the live MintModule code paths.
// Two paths through processTicketBatch with the SAME (player, level, owed, queueIdx, entropy):
// Path A — N narrow slices forced by setting a small budget (via writing a small WRITES_BUDGET
//          via storage forging would require contract surgery — INSTEAD use multiple
//          processTicketBatch calls; each runs against the SAME WRITES_BUDGET_SAFE=550 but
//          stops mid-player because owed > maxT, naturally splitting via the existing budget).
// Path B — A single fat-budget call (would require contract surgery to extend WRITES_BUDGET).
//          ALTERNATIVE: drive a player whose owed fits a single budget by setting owed ≤ maxT
//          (≤292 warm), then independently drive a 300-owed player and verify A and B against
//          the OFF-CHAIN reference oracle (raritySymbolBatchRef.mjs ALREADY exists).

// CLEANEST mechanic per D-TST03-02 (cross-path equality, NOT reference-loop equality):
// Run the same scenario TWICE in two separate forge-test environments (vm.snapshot + vm.revertTo
// for environment isolation), and split the budget DIFFERENTLY per environment:
//   Env A: full budget WRITES_BUDGET_SAFE=550, owed=300 → ONE call splits the player (take=292
//          → 8 leftover → second processTicketBatch call drains the remaining 8).
//   Env B: same owed=300 but call processTicketBatch THREE TIMES with the SAME mockVRF word
//          finalized at the same per-index word, where each call's WRITES budget naturally
//          accommodates ≤292 per slice. The split happens at the SAME 292-boundary in both
//          environments.
// Compare: the player's traitBurnTicket[level][traitId] storage state for ALL trait ids 0..255
//          across (Env A) vs (Env B). Byte-identical → MINTDIV-02 alignment proven empirically.

function testMintDivCrossPathEquality_OwedSplitsAcrossSlices() public {
    // Deterministic anchor: owed=300 at level L, warm budget 550, maxT=292 (per
    // .planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-MINTDIV01-REACHABILITY-VERDICT.md).
    uint24 lvl = 1;
    address player = makeAddr("mintdiv-300-player");
    uint256 entropy = uint256(keccak256("mintdiv-tst03-deterministic-anchor"));

    // Stage: seed player with owed=300 at level L (via direct ticket purchase or test-side queue seeding).
    _seedPlayerWithOwed(player, lvl, 300);

    uint256 snapId = vm.snapshot();

    // === Env A: single processTicketBatch call → split mid-player (take=292; 8 leftover) ===
    // (advance the daily cycle to finalize a per-index word against `entropy`, then drive
    //  the MintModule's processTicketBatch via the gameOver-terminal-drain or the daily
    //  advance path; either lands the same LCG seed because baseKey is deterministic.)
    _driveProcessTicketBatchUntilDone(lvl); // multiple calls under the natural slicing
    bytes32 envADigest = _digestTraitBurnTicketForPlayer(player, lvl);

    vm.revertTo(snapId);

    // === Env B: differently-split processTicketBatch (e.g., manually call processTicketBatch
    //         from a test-side helper that interrupts after the first ticket entry, forcing
    //         a 3-way split) ===
    _seedPlayerWithOwed(player, lvl, 300); // re-stage post-revert
    _driveProcessTicketBatchFractured(lvl, 3); // 3 slices, each running until WRITES_BUDGET hits
    bytes32 envBDigest = _digestTraitBurnTicketForPlayer(player, lvl);

    assertEq(envADigest, envBDigest,
        "TST-03 D-TST03-02: byte-identical trait derivation across budget-slice splits");
}

// Boundary fuzz overlay (D-TST03-01):
function testFuzz_MintDiv_BoundaryOwedCrossPath(uint32 owed) public {
    vm.assume(owed >= 293 && owed <= 492); // [maxT+1, maxT+200]
    // ... mirror the deterministic anchor flow with this fuzzed owed ...
}
```

**Note on TST-03 mechanics:** Both legs MUST share the same VRF-derived per-index entropy word so the `baseKey` (which includes `owed`) and the `entropyWord` are deterministic across environments. The `vm.snapshot()`/`vm.revertTo()` pattern (used in `RngLockDeterminism.t.sol`) is the standard isolation primitive.

**Alternative TST-03 mechanic (simpler):** instead of two `vm.snapshot()` environments, call `processTicketBatch(lvl)` REPEATEDLY in a single test and compare the cumulative state to the SAME scenario where the test pre-seeds the storage to mimic the contiguous endpoint. The MINTDIV-02 one-liner makes the multi-call advance now equal the contiguous endpoint — so the test can be a simple before/after on the same state with no `vm.revertTo`. Planner's pick.

### v50 baseline ledger structure

```markdown
# Regression Baseline — v50.0 (NON-WIDENING clean-baseline gate ledger)

**Plan:** 336-XX (Wave-N full-suite NON-WIDENING regression gate).
**Subject:** the v50.0 IMPL HEAD `e756a6f3677f3142aafba7f044e106cd416d0d3b` (the BATCH-02 commit;
5 contracts + 8 tests; 1239 ins / 1311 del; net −72 lines).
**Baseline carried forward against:** `test/REGRESSION-BASELINE-v49.md §2` — the 42-red v49.0
union BY NAME (the v49.0 clean baseline at `b0511ca2`).

> **THE BINDING HEADLINE (by NAME, never a bare count):**
> at the v50 TST HEAD, the `forge test` failing set **==** the 42 v50.0 §2 enumerated union
> **BY NAME** — net-zero new regression. The gate is a strict NAME-set equality
> (`live failing set == the §2 enumerated 42-name union`), NOT a count match.

## 1. The v50 TST-HEAD arithmetic …
## 2. The 42-name v50.0 union (re-enumerated; see "Pre-derived v50 baseline set" below) …
## 3. v50 deltas vs v49 §2: B9 deleted at 335-05, B10 incidentally green at 335-06 IMPL …
## 4. New green proof files (TST-01 router/equivalence + TST-02 SLOAD oracle + TST-03 cross-path) …
## 5. Set-equality proof (FC1-FC4 false-confidence guards) …
## 6. Scope attestation (full forge test, NOT --match-path; zero contracts/*.sol edits this phase) …
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `vm.recordLogs()` + manual topic-filter + decode + assert count | `vm.expectCall(target, selector_or_calldata, count)` for call-count oracles | forge-std 1.x (long-stable; 2021+) | The expectCall variant is hot-path-accurate, supports both `STATICCALL` and `CALL`, and the cheatcode auto-verifies on test teardown |
| Hand-rolled freeze digest (`keccak256(state)`) | `vm.snapshot()`/`vm.revertTo()` for environment isolation + per-slot `vm.load()` | forge-std 1.x | Snapshot/revert is bidirectional (re-snapshot in same test allowed); no manual state-tracking |
| Bare `failed == N` count gate | NAME-set equality (`live − union == ∅ AND union − live == ∅`) | v48 § ledger precedent → v49 332 D-TST04-01..02 | Prevents a regression that coincidentally offsets a deletion from being masked |

**Deprecated/outdated:**
- The OLD 6-arg `TraitsGenerated(address,uint24,uint32,uint32,uint32,uint256)` event — replaced by the 3-arg form at `DegenerusGameStorage.sol:485`. The v48/v49 stale-harness tests in Bucket B still reference the old signature; that's WHY they're carried-forward reds.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The cold-SSTORE penalty for `whalePassClaims[opener] += 1` may exceed D-TST01-04's 500-gas tolerance | TST-01 D-TST01-04 example | If the tolerance is too tight, the test fails at first run; the planner widens to ~25_000 or pre-warms the slot. LOW risk (caught at first execution; not a correctness issue) |
| A2 | The TST-03 cross-path equality can be expressed as two `vm.snapshot()`/`vm.revertTo()` environments OR as before/after on the same state. The MINTDIV-02 fix makes either path-A==path-B equivalent | TST-03 cross-path mechanic | The two-env shape is the more defensive; if the simpler before/after fails, the planner falls back to two-env. MEDIUM risk if the planner over-couples to a single mechanic |
| A3 | The new TST-01 freeze-fuzz test for `claimWhalePass` perturbation does NOT need a stateful invariant handler (the simple snapshot/perturb/revert pattern from `testFuzz_RngLockDeterminism_AutoBuyDuringLockSafe` is sufficient) | D-TST01-02 ("planner's call") | If the same-tx `claimWhalePass` perturbation needs an invariant handler to find a hostile sequence, the planner adds one — adds one plan-task, no correctness impact |
| A4 | The TST-03 test file home is best as a NEW dedicated file `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol`, NOT an extension of `test/fuzz/GameOverPathIsolation.t.sol` | D-TST03-04 (pattern-mapper picks) | Adding to GameOverPathIsolation co-mingles concerns; a dedicated file is more discoverable in audit. LOW risk |

**If this table is empty:** N/A — there ARE legitimate assumptions that need empirical resolution at execution time. The planner should plan room for the gas tolerance + the cross-path mechanic to be adjusted at first execution.

## Open Questions (RESOLVED)

**None — the SPEC (`336-CONTEXT.md`) is thorough.** Every locked decision flows cleanly to a concrete mechanic. The four `Claude's Discretion` items (TST-03 home, TST-01 equivalence home, TST-01 invariant-handler decision, TST-02 oracle home) are all delegated to the pattern-mapper at planning time, not to research — they have no design ambiguity, just home placement.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `forge` | All TST plans | ✓ | (foundry.toml pinned; project uses `solc 0.8.34 + via_ir + optimizer_runs=200`) | — |
| `forge-std` | `vm.*` cheatcodes (the load-bearing primitive for every plan) | ✓ | `lib/forge-std/src/` (pinned via git submodule) | — |
| Hardhat | TST-04 D-TST04-03 secondary-gate (Hardhat parity at v49 last-known) | (assumed available — used in v49 332 D-TST04-03) | — | If unavailable, the Hardhat parity check is documented as N/A; Foundry NON-WIDENING ledger remains authoritative per D-TST04-03 |
| Node.js (for the Hardhat side + `raritySymbolBatchRef.mjs`) | TST-03 OPTIONAL reference oracle (only if planner picks the off-chain mirror mechanic vs the on-chain two-env mechanic) | ✓ (the `.mjs` file exists at `test/helpers/raritySymbolBatchRef.mjs`) | — | If unavailable, planner uses on-chain two-env mechanic |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** Hardhat (D-TST04-03 is a precedent-locked secondary; loss of Hardhat does not block the load-bearing Foundry gate).

## Validation Architecture

> nyquist_validation status — `.planning/config.json` (if absent or set to true, include this section). The repo's prior milestones (v49 332) used this same architecture; verified applicable here.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (`forge`) + `forge-std` cheatcodes |
| Config file | `foundry.toml` (pinned, no edit needed for 336) |
| Quick run command | `forge test --match-path test/fuzz/RngLockDeterminism.t.sol -vv` (per-file scoped) |
| Full suite command | `forge test` (whole tree) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TST-01 freeze | The deferred `whalePassClaims +=` record + claim perturb no current-window entropy | fuzz (default profile + `FOUNDRY_PROFILE=deep` gate) | `forge test --match-path test/fuzz/RngLockDeterminism.t.sol --match-test ClaimWhalePass` | ❌ NEW (extension) — Wave 1 |
| TST-01 equivalence | Box-open + claim materializes identical to old inline mint | unit/fuzz | `forge test --match-test "testEquivalenceClaimGrant"` (final fn name TBD by planner) | ❌ NEW — Wave 1 |
| TST-01 uniform O(1) | `|gas_whale - gas_non_whale| ≤ tol` | unit | `forge test --match-path test/gas/KeeperOpenBoxWorstCaseGas.t.sol --match-test WhaleEqualsNonWhaleGas` | ❌ NEW (extension) — Wave 1 |
| TST-02 no-pass-SLOAD | `vm.expectCall(..., count: 0)` on non-crossing autoBuy | unit | `forge test --match-test "testNonCrossingPathPerformsZeroLazy"` | ❌ NEW — Wave 2 |
| TST-03 cross-path equality | Byte-identical traits across budget-slice split (deterministic anchor + fuzz overlay) | unit + fuzz | `forge test --match-path test/fuzz/MintModuleDivergenceAcrossSplit.t.sol -vv` | ❌ NEW FILE — Wave 3 |
| TST-04 NON-WIDENING | live failing set == 42-name §2 union BY NAME | ledger + full-suite run | `forge test` (whole tree) + the §6 set-equality protocol from the v49 ledger | ❌ NEW (`test/REGRESSION-BASELINE-v50.md`) — Wave 4 (final, USER gate) |

### Sampling Rate

- **Per task commit:** `forge test --match-path <touched file>` (per-plan quick run)
- **Per wave merge:** `forge test` (full suite, both default + deep profile spot-checks for TST-01)
- **Phase gate:** Full suite green-or-known-baseline at TST HEAD; ledger §6 set-equality proven; USER hand-review of the binding §2 headline

### Wave 0 Gaps

- [ ] None — all test infrastructure exists at `e756a6f3`. Plans add new test contracts/functions to the existing files (or one new file for TST-03), but no Wave-0 framework install is needed.

*(If no gaps: "None — existing test infrastructure covers all phase requirements")*

## Security Domain

> security_enforcement status — the v50.0 milestone has the security/RNG-freeze floor as its HARD constraint per `feedback_security_over_gas`. Include this section.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | TST phase touches no auth |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | no | TST tests against committed contract behavior; no fuzz-style validation testing of access surfaces |
| V6 Cryptography | yes (`v45-vrf-freeze-invariant` re-attest) | The TST-01 freeze-fuzz empirically re-attests the `v45-vrf-freeze-invariant` — every variable interacting with a VRF word is frozen `[rng request → unlock]` vs players. Uses the LCG inside `_raritySymbolBatch` (TICKET_LCG_MULT) as a deterministic seed — Foundry tests do not need to re-derive any cryptographic primitive |

### Known Threat Patterns for {smart-contract test/} stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Test forging contract state to pass | Tampering | TST phase commits ONLY to `test/` + `.planning/`; `contracts/*.sol` byte-identical to `e756a6f3` (D-TST04-04 + `feedback_no_contract_commits`) |
| Test passes by `vm.skip(true)` masking | Repudiation | Per-plan `forge test --gas-report` shows skipped count; ledger §6 explicitly enumerates the 17 skipped (carried verbatim from v49); a new `vm.skip` is recorded in the ledger |
| Fixture-migration artifact masking a v50 regression | Repudiation | D-IMPL-03 row 1 — fixture-migration artifacts close IN-PLAN; D-TST04-04 — STOP-and-re-spec on a genuine v50 contract regression (not patch-under-TST) |

## Project Constraints (from CLAUDE.md)

> No `./CLAUDE.md` exists at the project root (checked 2026-05-28). Project conventions flow via:

- `feedback_no_contract_commits` — Phase 336 mutates ONLY `test/` + `.planning/`. **Honored.**
- `feedback_wait_for_approval` / `feedback_manual_review_before_push` — no `git push` during 336 (D-CC-04). **Honored.**
- `feedback_pause_at_contract_phase_boundaries` — 336 is NOT a contract phase; user-gate only at the binding TST-04 ledger headline (D-CC-03). **Honored.**
- `feedback_security_over_gas` — security/RNG floor over gas; the freeze-fuzz extension is the load-bearing re-attest. **Honored.**
- `feedback_verify_call_graph_against_source` — every cited `file:line` against `e756a6f3`; the 335-LOCAL-VERIFICATION already grep-attested 16 anchors. **Honored.**

The MEMORY.md is essentially CLAUDE.md-equivalent for this project — no additional CLAUDE.md directives override the above.

## Pre-derived v50 baseline set (data the TST-04 plan author needs)

> Per D-TST04-01, the v50 §2 table FULLY re-enumerates all 42 names with per-test status annotations. This subsection PRE-COMPUTES the v50 union from the v49 §2 enumeration + the 335-07 / 335-06 documented deltas, so the TST-04 plan starts with the data assembled.

### Source of the v49 §2 set

From `test/REGRESSION-BASELINE-v49.md §2`:
- **Bucket A — VRF / RNG-window (8 reds):** A1–A8 (all carried verbatim).
- **Bucket B — stale-harness / v48-behavioral (34 reds):** B1 (12) + B2 (4) + B3 (5) + B4 (2) + B5 (2) + B6 (1) + B7 (1) + B8 (2) + B9 (1) + B10 (1) + B11 (1) + B12 (1) + B13 (1).
- **Bucket C — HERO-deferred (Foundry side, 0 reds).**
- **Total: 8 + 34 + 0 = 42.**

### v50 deltas to §2 (per 335-07 SUMMARY + 335-LOCAL-VERIFICATION)

| Delta | Source | Type | Disposition for v50 §2 |
|-------|--------|------|------------------------|
| **B9 OUT** — `AfKingSubscription.testRenewalExactlyAtCostFullBurn` DELETED in Plan 335-05 (test premise retired by AFSUB-01) | 335-LOCAL-VERIFICATION §2 + 335-07-SUMMARY | premise-retired deletion | REMOVE from v50 §2 |
| **B10 OUT** — `AfKingFundingWaterfall.testFundingSourceVaultDoesNotInheritExemption` flipped GREEN at v50 IMPL (the `BurnieChargeFailed` path is structurally gone under AFSUB-01) | 335-LOCAL-VERIFICATION §2 ("Incidental fixes") | contract-side cleanup unblocked the test | REMOVE from v50 §2 |
| **NEW invariant_noEthCreation** IN — co-failure of B12 family, ~22 wei drift from WHALE-01 deferred-claim accounting shift | 335-LOCAL-VERIFICATION §2 ("Incidental NEW reds") | legitimate v50 widening (D-IMPL-03 row 3) | ADD to v50 §2 (Bucket B, sibling of B12) |
| **NEW invariant_ghostAccountingNetPositive** IN — same as above, sister assertion | 335-LOCAL-VERIFICATION §2 ("Incidental NEW reds") | legitimate v50 widening | ADD to v50 §2 (Bucket B, sibling of B12) |

**Net delta:** −2 (B9, B10) + 2 (the two invariants) = 0. **Total stays 42.**

### The v50 §2 union (pre-derived, 42 names)

#### Bucket A — VRF / RNG-window (8 carried verbatim from v49 §2 Bucket A)

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| A1 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_allGapDaysBackfilled` |
| A2 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_rngUnlockedAfterSwap` |
| A3 | `test/fuzz/invariant/VRFPathInvariants.inv.t.sol` | `invariant_stallRecoveryValid` |
| A4 | `test/fuzz/VRFCore.t.sol` | `test_midDayRequest_doesNotBlockDaily` |
| A5 | `test/fuzz/VRFLifecycle.t.sol` | `test_vrfLifecycle_levelAdvancement` |
| A6 | `test/fuzz/VRFPathCoverage.t.sol` | `test_gapBackfillWithMidDayPending_fuzz` |
| A7 | `test/fuzz/RngLockDeterminism.t.sol` | `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`vm.assume` rejected too many inputs; **the TST-01 extension does NOT touch this**) |
| A8 | `test/fuzz/RngIndexDrainBinding.t.sol` | `testBindingConsistencyDailyDrain` |

#### Bucket B — stale-harness / v48-behavioral (34 reds; B9 + B10 OUT, 2 invariants IN)

| # | Suite (file) | Failing test(s) | Count | Note |
|---|--------------|-----------------|-------|------|
| B1 | `test/fuzz/TicketRouting.t.sol` | 12 tests (`testBoundaryLevel5RoutesToWriteKey`, …) | 12 | carried |
| B2 | `test/fuzz/QueueDoubleBuffer.t.sol` (MidDaySwapTest) | 4 tests | 4 | carried |
| B3 | `test/fuzz/QueueDoubleBuffer.t.sol` (QueueDoubleBufferTest) | 5 tests | 5 | carried |
| B4 | `test/fuzz/TicketEdgeCases.t.sol` | 2 tests | 2 | carried |
| B5 | `test/fuzz/PrizePoolFreeze.t.sol` | 2 tests | 2 | carried |
| B6 | `test/fuzz/TicketLifecycle.t.sol` | `testLootboxNearRollTicketsProcessed` | 1 | carried |
| B7 | `test/fuzz/GameOverPathIsolation.t.sol` | `testGameOverDrainsQueuedTickets` | 1 | carried |
| B8 | `test/fuzz/LootboxBoonCoexistence.t.sol` | 2 tests | 2 | carried |
| ~~B9~~ | ~~`test/fuzz/AfKingSubscription.t.sol`~~ | ~~`testRenewalExactlyAtCostFullBurn`~~ | ~~1~~ | **OUT — deleted at 335-05** |
| ~~B10~~ | ~~`test/fuzz/AfKingFundingWaterfall.t.sol`~~ | ~~`testFundingSourceVaultDoesNotInheritExemption`~~ | ~~1~~ | **OUT — flipped GREEN at v50 IMPL** |
| B11 | `test/fuzz/CoverageGap222.t.sol` | `test_gap_gnrus_propose_vote_paths` | 1 | carried |
| B12 | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_solvencyUnderDegenerette` | 1 | carried |
| B13 | `test/fuzz/DegeneretteFreezeResolution.t.sol` | `testDgnrsAwardStaysPerSpin` | 1 | carried |
| **NEW B14** | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_noEthCreation` | 1 | **IN — co-failure of B12 family, WHALE-01 deferred-claim accounting widening** |
| **NEW B15** | `test/fuzz/invariant/DegeneretteBet.inv.t.sol` | `invariant_ghostAccountingNetPositive` | 1 | **IN — co-failure of B12 family, same widening** |

Bucket B totals: 12 + 4 + 5 + 2 + 2 + 1 + 1 + 2 + 0 (~~B9~~) + 0 (~~B10~~) + 1 + 1 + 1 + 1 (B14) + 1 (B15) = **34**.

#### Bucket C — HERO-deferred FOUNDRY-side (0 reds; carried as 0 from v49)

| # | Suite (file) | Failing test |
|---|--------------|--------------|
| — | (none) | (none) |

#### v50 §2 union totals

- Bucket A: **8**
- Bucket B: **34** (B1..B8 + B11..B13 + NEW B14 + NEW B15; B9 and B10 are OUT)
- Bucket C: **0**
- **Total: 42** ✓ — matches the 42-failed count in 335-LOCAL-VERIFICATION.

> **Verification mechanism for TST-04:** the ledger §6 `forge test --json` parse builds a `(suite-basename, testName)` failing set and asserts strict set-equality against this enumeration. If the set-equality fails, the §1 arithmetic STOPS and the ledger emits a `## STOP — NEW REGRESSION OUTSIDE BASELINE` block; the binding sentence is NEVER written over a real regression.

## Sources

### Primary (HIGH confidence)
- `e756a6f3` working tree — every `file:line` cite, every event signature, every storage slot verified against the live source at the FROZEN audit subject
- `.planning/phases/336-.../336-CONTEXT.md` — the locked D-TST01-01..04 / D-TST02-01..02 / D-TST03-01..04 / D-TST04-01..04 / D-CC-01..04 decisions
- `.planning/phases/334-.../334-MINTDIV01-REACHABILITY-VERDICT.md` — the TST-03 deterministic anchor source (owed=300, warm budget 550, maxT=292)
- `.planning/phases/334-.../334-WHALE04-FREEZE-PROOF.md` — the freeze-safety paper proof TST-01 freeze-fuzz empirically re-attests
- `.planning/phases/335-.../335-CONTEXT.md` D-IMPL-02 — the explicit list of 8 test files migrated in 335 and the deferred-to-336 substance (the file header line 38-44 deferral on the WHALE-01/02 roundtrip equivalence in `RngFreezeAndRemovalProofs.t.sol`)
- `.planning/phases/335-.../335-LOCAL-VERIFICATION.md` §2 — the 666/42/17 + B9 OUT + B10 INC-FIX + 2 NEW invariants narrative
- `.planning/phases/335-.../335-07-SUMMARY.md` — the BATCH-02 closure narrative + the FROZEN audit subject SHA
- `.planning/milestones/v49.0-phases/332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg/332-CONTEXT.md` — the parent TST decision template
- `test/REGRESSION-BASELINE-v49.md` — the LEDGER FORMAT MODEL `REGRESSION-BASELINE-v50.md` mirrors verbatim
- `test/fuzz/RngLockDeterminism.t.sol` — the EXACT extension target, verified at lines 160 (cls 9/10 perturbations), 1839 (the AutoBuy template), 1934 (the autoOpen-blocked template), 1986 (the no-marooned-boxes template)
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — the existing harness for the TST-01 D-TST01-04 one-liner extension
- `test/fuzz/AfKingSubscription.t.sol:182-199` — the existing `testNonCrossingPassHolderBuysWithoutRefresh` closest-analog for TST-02 D-TST02-02
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol:38-44` — the explicit deferral of the WHALE-01/02 roundtrip equivalence to Phase 336
- `contracts/AfKing.sol:627-647` — the crossing block where `GAME.lazyPassHorizon(player)` fires exactly ONCE; the non-crossing path is the cheap stored-field compare
- `contracts/DegenerusGame.sol:1540` — `lazyPassHorizon` view def (the selector TST-02's vm.expectCall targets)
- `contracts/modules/DegenerusGameMintModule.sol:393,479,502,546,671,716,719` — the `processTicketBatch` / `processFutureTicketBatch` / `_raritySymbolBatch` / `_processOneTicketEntry` surfaces TST-03 exercises
- `contracts/storage/DegenerusGameStorage.sol:485-489` — the live 3-arg `TraitsGenerated` event signature
- `foundry.toml:1-59` — the default + deep profile config

### Secondary (MEDIUM confidence)
- `test/helpers/raritySymbolBatchRef.mjs` — the off-chain reference LCG mirror (mentioned only as an alternative TST-03 mechanic; the on-chain two-env or before/after mechanic is preferred per the discussion)
- `test/edge/MintBatchDeterminism.test.js` (Hardhat side) — the v41 precedent for the cross-path equality oracle pattern (the on-chain TraitsGenerated event capture, in Hardhat)

### Tertiary (LOW confidence)
- The exact gas tolerance for the TST-01 D-TST01-04 whale-vs-non-whale equivalence (500 gas vs ~25_000 cold-SSTORE) — empirical at execution time (see Assumption A1)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every primitive (vm.expectCall, vm.snapshot/revertTo, vm.recordLogs, foundry.toml profile.deep) verified live
- Architecture: HIGH — every pattern has a v49 332 D-precedent or a live in-tree analog
- Pitfalls: HIGH — the 5 documented pitfalls cover every known sharp edge in the existing harness + the v49 ledger format

**Research date:** 2026-05-28
**Valid until:** 7 days (the v50.0 audit subject is FROZEN at `e756a6f3`; this research stays valid until the v50.0 milestone closes at Phase 338; only a new contract commit invalidates the file:line cites)

---

*Phase 336 research artifact. Verdict: HIGH confidence; zero open questions; the design lock (336-CONTEXT.md) is thorough; the planner has every concrete mechanic + every datum the TST-04 ledger needs pre-assembled.*
