# Phase 336: TST — Equivalence + Freeze-Safety + Divergence-Repro + Non-Widening Regression - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Empirically prove the v50.0 IMPL diff (FROZEN at `e756a6f3`) behaviorally correct against the v49.0 baseline `b0511ca2`, via four proofs (TST-01..04):

1. **TST-01** — whale-pass refactor proven equivalent + uniform-O(1) + freeze-safe.
2. **TST-02** — AFSUB pass-gated subs proven (sweep / evict / refresh / no-pass-SLOAD on non-crossing / OPEN-E re-attest / swap-pop invariant).
3. **TST-03** — MINTDIV byte-identical-traits-across-split regression (the 334-MINTDIV01-REACHABILITY-VERDICT closes empirically).
4. **TST-04** — full-suite NON-WIDENING vs v49.0 baseline; the `test/REGRESSION-BASELINE-v50.md` baseline ledger is authored.

**Posture:** `test/` + `.planning/` only. **NO `contracts/*.sol` mutation** (v49 332 D-precedent + `feedback_no_contract_commits`). The audit subject stays FROZEN at `e756a6f3`. If a proof surfaces a contract defect, STOP and re-spec — do NOT patch a mainnet contract under a TST phase.

**Audit subject:** v50.0 IMPL HEAD `e756a6f3677f3142aafba7f044e106cd416d0d3b` (the BATCH-02 USER-approved commit landing WHALE-01..03 + AFSUB-01..05 + MINTDIV-02 + the 8 test-file migrations from 335 D-IMPL-02).

**Baseline carried forward against:** `test/REGRESSION-BASELINE-v49.md` §2 — the 42-by-NAME v49 red union (clean baseline at `b0511ca2`).

**Already-covered surfaces from 335 D-IMPL-02 (do NOT re-author):** the WHALE-01/02 roundtrip equivalence assertions + the AFSUB pass-eviction empirical proofs (sweep-while-valid, evict-at-crossing-with-no-valid-pass, refresh-at-crossing-with-valid-pass, OPEN-E 4-protection re-attest, SUB-07 cancel-tombstone, swap-pop membership invariant) ALREADY landed inside the 8 migrated test files at `e756a6f3`. Phase 336 ADDS the surfaces those migrations EXPLICITLY DEFERRED (per `335-CONTEXT.md` D-IMPL-02): the freeze-fuzz extension of the `RngLockDeterminism` harness (TST-01 freeze leg), the MINTDIV same-traits-across-split regression (TST-03), and the v50.0 baseline ledger replacing v49's 666/42/17 (TST-04). Plus the explicit oracle additions captured below (D-TST01-03/04 and D-TST02-02).

</domain>

<decisions>
## Implementation Decisions

### TST-03 — MINTDIV byte-identical-traits-across-split regression (USER-DISCUSSED)

- **D-TST03-01 — Shape: deterministic anchor + boundary fuzz overlay.** Both-rails per the v49 332 invariant-proof D-precedent. The deterministic test is the audit anchor that cites `334-MINTDIV01-REACHABILITY-VERDICT.md` by path; the fuzz overlay scans `owed ∈ [maxT+1, maxT+200]` (i.e., values that force a split mid-player) to catch LCG-boundary surprises.
- **D-TST03-02 — Oracle: cross-path equality (across-split == contiguous).** Same scenario, two distinct paths: (A) `processTicketBatch` invoked across N narrow budget slices that force the split mid-player, (B) `processTicketBatch` invoked once with a fat-enough budget that the whole player completes contiguously. Assert per-ticket trait byte-identity between A and B. Rejected: reference-loop equality vs `processFutureTicketBatch:502` (couples the test to the reference loop's evolution); rejected: startIndex-advance assertion (weaker than LCG-output equivalence — proves the arithmetic, not the trait byte-identity).
- **D-TST03-03 — Anchor scenario: 334-research verbatim.** `owed=300` at level L, `WRITES_BUDGET_SAFE=550`, `maxT=292`, `take=292 < 300` — single deterministic test function, 1:1 verdict-to-test mapping. The test's docstring cites `.planning/phases/334-.../334-MINTDIV01-REACHABILITY-VERDICT.md` by path so audit lineage is traceable. The boundary edge (`owed=293`) is covered by the fuzz overlay from D-TST03-01, **NOT** by a second deterministic function.
- **D-TST03-04 — File home: planner's pattern-mapper picks closest analog.** Mirrors v49 332's "you decide" delegation for proof-file homes. The pattern-mapper scans existing MintModule-related tests and picks the closest analog; a new dedicated file (e.g., `test/fuzz/MintModuleDivergenceAcrossSplit.t.sol`) is the fallback if no close analog exists.

### TST-01 — Equivalence + uniform-O(1) + freeze-safe (Claude defaults — un-discussed area, lockable)

- **D-TST01-01 — Freeze-fuzz extension HOME: extend `test/fuzz/RngLockDeterminism.t.sol` directly.** Locked by the ROADMAP Phase-336 TST-01 acceptance criterion ("extending the v43 `RngLockDeterminism` harness") AND by the v49 332 D-precedent ("TST-01 extends `RngLockDeterminism.t.sol`, which is locked by the roadmap"). The deferred-claim freeze proof — that `box-open → record whalePassClaims +=` adds NO entropy input to the current RNG window, and that `claimWhalePass` always queues `currentLevel+1..+100` (future-window-only writes per D-03 claim-time anchoring) — lives here. The trivial new-write-path assertions (the `whalePassClaims +=` writer is not a frozen-slot write; `lazyPassHorizon` is not an RNG-window read) ALREADY landed in `test/fuzz/RngFreezeAndRemovalProofs.t.sol` via 335 D-IMPL-02 — do NOT relocate them.

- **D-TST01-02 — Freeze-fuzz DEPTH: default suite + `FOUNDRY_PROFILE=deep` gate.** v44 INV / v49 332 D-precedent. Routine suite runs at the default profile (fuzz 1000 / invariant 256×128); the **deep** freeze proof gates under `FOUNDRY_PROFILE=deep` (fuzz 10000 / invariant 1000×256). Add a dedicated stateful invariant handler if the same-tx-with-`autoOpen` / same-tx-with-`claimWhalePass` perturbation needs one — planner's call.

- **D-TST01-03 — Correct claim-time grant oracle (TST-01 equivalence per D-05).** Add a focused oracle asserting the claim materializes `[currentLevel+1 .. currentLevel+100]` exactly, with `_applyWhalePassStats` applied at the same claim-time anchor, and that the pre-claim box-open writes ONLY the O(1) accumulator (no `mintPacked_` perturbation, per D-04). If the 335-migrated tests already prove this (per 335 D-IMPL-02 "the O(1) box-open + claim equivalence (the WHALE-01/02 roundtrip)"), the pattern-mapper discovers it and 336 adds only a narrow gap-closer. If absent, the pattern-mapper picks a home for a small dedicated TST-01 equivalence contract.

- **D-TST01-04 — Uniform-O(1) opens attestation.** Re-use the existing `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` harness (D-IMPL-04 already wired it for the OPEN_BATCH=200 picker at 335-06). 336 ADDS a one-line `whale_opener_gas == non_whale_opener_gas` equivalence assertion within a documented tolerance (e.g., `|Δ| ≤ 500 gas`), proving the worst-case opener gas is independent of the opener's whale-pass status. The single-figure measurement already in the harness is sufficient; the equivalence assertion is the narrative one-line addition.

### TST-02 — AFSUB pass-gated subs proven (Claude defaults — un-discussed area, lockable)

- **D-TST02-01 — Coverage largely landed at 335 D-IMPL-02.** The migrated `AfKingSubscription.t.sol` / `AfKingFundingWaterfall.t.sol` / `AfKingConcurrency.t.sol` / `KeeperNonBrick.t.sol` assert: sweep-while-valid (`currentLevel <= validThroughLevel`); evict-at-crossing-with-no-valid-pass; refresh-at-crossing-with-valid-pass; OPEN-E `fundingSource` 4-protection re-attestation; SUB-07 cancel-tombstone preservation; v49 swap-pop membership invariant (`membership ⟺ packed != 0`). 336 does NOT re-author these — the pattern-mapper inventories what 335 covered and 336 closes only explicit gaps.

- **D-TST02-02 — "NO external pass SLOAD on non-crossing path" oracle: `vm.expectCall(..., count: 0)`.** Hot-path-accurate Foundry-native pattern — mirrors v49 332 D-02's "exactly one `creditFlip` call" oracle (`vm.expectCall` / `vm.recordLogs`). Rejected: static grep (misses dynamic indirect dispatch); rejected: call-graph trace (heavier infra than the 332-precedent oracle warrants). Concretely: stage an active subscription, advance N levels under `currentLevel <= validThroughLevel`, then `vm.expectCall(IGame.lazyPassHorizon.selector, count: 0)` around the full sweep — assert zero external pass reads on the non-crossing path.

### TST-04 — Full-suite NON-WIDENING + v50.0 baseline ledger (Claude defaults — un-discussed area, lockable)

- **D-TST04-01 — Ledger format: full re-enumeration mirror of `test/REGRESSION-BASELINE-v49.md`.** Author `test/REGRESSION-BASELINE-v50.md`. The §2-equivalent table FULLY re-enumerates the v50 42-by-NAME union (NOT v49-delta-only — the binding gate is strict `live failing set == 42-name union BY NAME` set-equality, and a partial-delta makes future re-derivation harder). The delta narrative (B9 OUT + `invariant_noEthCreation` IN + `invariant_ghostAccountingNetPositive` IN; total stays 42) is documented inline in a delta section but the §2-equivalent table re-enumerates all 42 names with per-test status annotations. The §1 arithmetic table starts from the IMPL HEAD `e756a6f3` (666/42/17) and tracks any per-plan red-set churn at TST HEAD.

- **D-TST04-02 — Binding headline: name-set equality, never bare count.** Mirror the v49 ledger's headline verbatim (version + commit substituted): *"at the v50 TST HEAD, the `forge test` failing set == the 42 v50.0 §2 enumerated union BY NAME — net-zero new regression. The gate is a strict NAME-set equality, NOT a count match."* A count-only gate would mask a real new regression that coincidentally offsets a 335 D-IMPL-02 fixture-migration artifact.

- **D-TST04-03 — Hardhat parity: precedent-locked.** Keep the Hardhat side green at its v49 last-known parity (v49 332 D-precedent). The Foundry NON-WIDENING ledger is the authoritative regression gate for v50.0.

- **D-TST04-04 — Hard constraint: zero `contracts/*.sol` mutation.** A 336 plan that proposes a contract edit triggers STOP and re-spec. The 332 precedent's `feedback_no_contract_commits` is honored at every plan boundary. If a proof red surfaces that is a genuine v50 contract regression (not a 335 D-IMPL-02 fixture-migration artifact), stop the phase and re-open the IMPL boundary — do NOT patch the contract under TST-04's NON-WIDENING reconciliation.

### Cross-cutting (Claude defaults — un-discussed area, lockable)

- **D-CC-01 — Commit cadence: per-plan atomic.** v49 332 D-precedent (each plan its own commit). NO single batched commit (332 was NOT batched; only IMPL phases batch per the v49 330 / v50 335 BATCH-02 protocol).

- **D-CC-02 — Worktrees posture: sequential-on-main, no-worktrees.** v49 332 D-precedent ("sequential-on-main no-worktrees [submodule+node_modules]"). The submodule + node_modules friction makes worktrees unusable for this repo; plans run sequentially on `main`.

- **D-CC-03 — Plan `autonomous` flag policy.** All test/-only commits: `autonomous: true` (test/ + .planning/ is agent-committable per `feedback_no_contract_commits`). **The final ledger commit** (the binding "live failing set == 42-name union BY NAME" attestation that closes Phase 336): `autonomous: false` — USER reviews the binding headline before commit. This mirrors the v49 333 TERMINAL closure gate, applied here at the v50.0 baseline-ledger boundary.

- **D-CC-04 — NO `git push`.** Push gate is separate per `feedback_wait_for_approval` / `feedback_manual_review_before_push`. Push happens at v50.0 closure (Phase 338) per the v49 precedent.

### Claude's Discretion

Constrained by the locked decisions above, the planner has discretion over:
- The TST-03 file home (D-TST03-04 — pattern-mapper picks).
- The TST-01 dedicated equivalence/grant-correctness test home (D-TST01-03 — pattern-mapper picks if a gap exists vs 335-migrated coverage).
- The TST-01 stateful invariant handler decision (D-TST01-02 — only add if same-tx perturbation requires one).
- The TST-02 `vm.expectCall(count: 0)` oracle home (D-TST02-02 — picked among the 4 migrated AfKing test files).
- The number of waves / plans / fan-out shape — v49 332 used 6 plans; 336's narrower scope likely needs fewer.

### Folded Todos

None — no pending todos matched Phase 336 in the cross-reference scan.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, researcher, executor) MUST read these before authoring tests.**

### Milestone scope (read first)
- `.planning/ROADMAP.md` — Phase 336 §Success Criteria 1–4 + the v50.0 cross-cutting rule (security/RNG-freeze floor; one batched diff already landed at IMPL 335 — 336 is test/-only).
- `.planning/REQUIREMENTS.md` — Phase 336's 4 requirements: TST-01, TST-02, TST-03, TST-04 (lines 36-39, 92-95, 109).

### v50.0 IMPL audit subject (FROZEN)
- `e756a6f3677f3142aafba7f044e106cd416d0d3b` — the BATCH-02 USER-approved commit at the Phase 335 IMPL HEAD. The v50.0 audit subject 336 builds against (5 contracts + 8 tests, 1239 ins / 1311 del, net −72 lines; see 335-07-SUMMARY for the full diff envelope).

### Phase-334 SPEC (the design contract for v50.0)
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-SPEC-INDEX.md` — navigation + multi-source coverage audit; start here for the SPEC map.
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-MINTDIV01-REACHABILITY-VERDICT.md` — the MINTDIV-01 PROVEN REACHABLE verdict (−17 warm trace, `owed=300` scenario). **The TST-03 deterministic anchor cites this doc by path** (per D-TST03-03).
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-WHALE04-FREEZE-PROOF.md` — the WHALE-04 freeze-safety paper proof. **TST-01's freeze-fuzz extension empirically re-attests it** (per D-TST01-01 / D-TST01-02).
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-CONTEXT.md` — the D-01..D-23 design lock (esp. D-03 claim-time anchoring, D-04 stats-at-claim, D-05 equivalence reinterpretation).
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-DESIGN-LOCK-AFKING.md` — `validThroughLevel` placement + `lazyPassHorizon` view + refresh-or-evict + OPEN-E/SUB-07/swap-pop preservation criteria.

### Phase-335 IMPL (where the migrated tests landed)
- `.planning/phases/335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re/335-CONTEXT.md` — D-IMPL-01..D-IMPL-04 + the explicit list of 8 test files migrated in 335 and what assertions each gained. **336 reads this to know what TST-01/TST-02 surfaces are already covered.**
- `.planning/phases/335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re/335-LOCAL-VERIFICATION.md` — the forge build/test ledger at IMPL HEAD; the **666/42/17 starting position** for TST-04's arithmetic.
- `.planning/phases/335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re/335-07-SUMMARY.md` — the BATCH-02 closure narrative + the 16-anchor re-attestation table; **the OPEN_BATCH=200 picker** + the "B9 OUT, two invariants IN" baseline-evolution note.

### v49 332 TST precedent (mirror this phase against it)
- `.planning/milestones/v49.0-phases/332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg/332-CONTEXT.md` — the parent decision template: TST-01 extends `RngLockDeterminism.t.sol` (locked); deep-fuzz gates under `FOUNDRY_PROFILE=deep`; sequential-on-main no-worktrees; per-plan atomic commits; ledger format.
- `test/REGRESSION-BASELINE-v49.md` — **the LEDGER MODEL** `test/REGRESSION-BASELINE-v50.md` MUST MIRROR (per D-TST04-01): §1 arithmetic table, §2 42-by-NAME enumeration, headline form "live failing set == §2 union BY NAME".

### TST-01 surfaces (freeze-fuzz + equivalence)
- `test/fuzz/RngLockDeterminism.t.sol` — the v43 harness extended for the deferred-claim freeze proof (per D-TST01-01). **The roadmap LOCKS this file** as the freeze-fuzz home.
- `test/fuzz/RngLockRotationDeterminism.t.sol` — sibling rotation determinism harness (background context, not the extension target).
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol` — already touched in 335 with the trivial new-write-path assertions (`whalePassClaims +=` non-frozen; `lazyPassHorizon` non-RNG-window). 336 does NOT relocate those.
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — the uniform-O(1) measurement harness; 336 adds the whale-vs-non-whale gas-equivalence assertion within tolerance (per D-TST01-04).
- `contracts/modules/DegenerusGameWhaleModule.sol:1018` — the existing deployed `claimWhalePass(address player)` (the materialization entrypoint TST-01 exercises).
- `contracts/modules/DegenerusGameLootboxModule.sol:1253` — the O(1) `whalePassClaims[player] +=` writer (the box-open boon recorded post-WHALE-01).
- `contracts/storage/DegenerusGameStorage.sol` — `_applyWhalePassStats:1111` (stats applied at claim per D-04); `_livenessTriggered:1213` (structural guard satisfying D-IMPL-01's gameOver-forfeit attestation — TST-01 may re-attest empirically).

### TST-02 surfaces (AFSUB pass-gated subs)
- `contracts/AfKing.sol` — the migrated `Sub.validThroughLevel` (offset 5), `subscribe:374`, `_autoBuy:605` swap-pop, the `_autoBuy:628` `lazyPassHorizon` crossing read (the ONLY external pass read on the hot path per A11 in 335-07).
- `contracts/DegenerusGame.sol:1540` — the `lazyPassHorizon(address) external view returns (uint24)` view that **TST-02's `vm.expectCall` oracle (D-TST02-02) targets by selector**.
- `test/fuzz/AfKingSubscription.t.sol`, `test/fuzz/AfKingFundingWaterfall.t.sol`, `test/fuzz/AfKingConcurrency.t.sol`, `test/fuzz/KeeperNonBrick.t.sol` — the 4 migrated files where TST-02 sweep/evict/refresh/OPEN-E/swap-pop coverage ALREADY LANDED at 335. 336 reads these to find the gap (the explicit "no-pass-SLOAD on non-crossing" oracle is the known gap per D-TST02-02).

### TST-03 surfaces (MINTDIV byte-identical-traits-across-split)
- `contracts/modules/DegenerusGameMintModule.sol:719` — `processed += take;` (MINTDIV-02 fix; the cross-path equality test asserts the invariant this fix preserves).
- `contracts/modules/DegenerusGameMintModule.sol:502` — `processFutureTicketBatch:393`'s correct `processed += take;` (reference background; NOT used as oracle per D-TST03-02).
- `contracts/modules/DegenerusGameMintModule.sol:93` — `WRITES_BUDGET_SAFE = 550` (the warm budget binding the −17 trace; the deterministic anchor uses this).
- `contracts/modules/DegenerusGameMintModule.sol` — `_raritySymbolBatch` LCG consumer (the trait-generator the cross-path equality oracle observes).
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-MINTDIV01-REACHABILITY-VERDICT.md` — **the deterministic-anchor scenario source** (per D-TST03-03). Test docstring cites this.

### TST-04 surfaces (NON-WIDENING + v50.0 baseline ledger)
- `test/REGRESSION-BASELINE-v49.md` — **the FORMAT MODEL** (per D-TST04-01). `test/REGRESSION-BASELINE-v50.md` mirrors §1 arithmetic + §2 42-by-NAME enumeration + headline form.
- `.planning/phases/335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re/335-LOCAL-VERIFICATION.md` — the IMPL HEAD 666/42/17 starting position + the per-test reconciliation 335 already did against the v49 baseline names; 336 starts from there.

### Invariants / preserved properties (must NOT regress)
- `v45-vrf-freeze-invariant` — re-attested empirically by TST-01's freeze-fuzz extension.
- `open-e-operator-approval-trust-boundary` — the 4 structural protections re-attested by the TST-02 surfaces already in the migrated tests.
- `afking-cancel-tombstone-streak-finding` — the SUB-07 cancel-tombstone + swap-pop membership invariant re-attested by the migrated AfKing tests.

### Feedback / policy
- `feedback_no_contract_commits` — Phase 336 mutates ONLY `test/` + `.planning/` (D-TST04-04 hard constraint).
- `feedback_security_over_gas` — the security/RNG floor is THE hard constraint; D-TST04-04 stops the phase and re-opens IMPL rather than masking a real regression.
- `feedback_wait_for_approval` / `feedback_manual_review_before_push` — no push during Phase 336; push gate at v50.0 closure (338).
- `feedback_pause_at_contract_phase_boundaries` — 336 is NOT a contract phase; the user-gate is only at the binding TST-04 ledger headline (per D-CC-03).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`test/fuzz/RngLockDeterminism.t.sol`** — the v43 freeze-fuzz harness LOCKED BY THE ROADMAP as the TST-01 freeze-leg home. Extend in place; do not author a parallel harness.
- **`test/gas/KeeperOpenBoxWorstCaseGas.t.sol`** — already wired in 335 D-IMPL-04 for the OPEN_BATCH=200 picker. 336 adds a one-line whale-vs-non-whale gas-equivalence assertion; no new harness.
- **`vm.expectCall(..., count: 0)`** — Foundry-native call-count oracle pattern; v49 332 D-02 precedent established the use of `vm.expectCall` for hot-path call-count assertions. TST-02 D-TST02-02 reuses this pattern verbatim for the "no-pass-SLOAD on non-crossing" oracle.
- **`test/REGRESSION-BASELINE-v49.md`** — §1 arithmetic + §2 enumeration + headline-form template for the v50 ledger; mirror it verbatim per D-TST04-01.
- **The 8 test files migrated at 335 (per `335-CONTEXT.md` D-IMPL-02)** — TST-01 equivalence + TST-02 sweep/evict/refresh assertions ALREADY landed there. 336 reads them to identify the explicit gaps (the freeze-fuzz extension, the no-pass-SLOAD oracle, the uniform-O(1) gas-equivalence assertion) — do NOT re-author existing coverage.

### Established Patterns
- **Foundry results-equality (cross-path oracle)** — same scenario, two paths, assert byte-identical output. v49 332's D-precedent for the GASOPT micro-opts + the `degeneretteResolve` byte-identical-results proof. TST-03 D-TST03-02 reuses this shape for the across-split == contiguous invariant.
- **Deep-fuzz gating via `FOUNDRY_PROFILE=deep`** — v44 INV + v49 332 D-precedent. Routine suite default-profile; deep proof gated. TST-01 D-TST01-02 honors this.
- **Per-plan atomic commits + sequential-on-main no-worktrees** — v49 332 D-precedent for test-only phases. The submodule + node_modules friction makes worktrees unusable.
- **NON-WIDENING name-set-equality gate** — v48→v49 332 ledger form; the headline is strict NAME equality, never a bare count. TST-04 D-TST04-02 mirrors this verbatim.
- **`feedback_no_contract_commits`** — TST phases mutate ONLY `test/` + `.planning/`. The contract-commit guard does not require the `CONTRACTS_COMMIT_APPROVED=1` envelope for these.

### Integration Points
- **The freeze-fuzz extension** — adds new test contracts to `RngLockDeterminism.t.sol` covering the deferred `whalePassClaims +=` record + claim path; the existing v43 harness's setup helpers are reused.
- **The whale-vs-non-whale gas equivalence one-liner** — added to `KeeperOpenBoxWorstCaseGas.t.sol`; no new harness, no new fixture.
- **The `vm.expectCall(..., count: 0)` no-SLOAD oracle** — added to the appropriate AfKing test file (pattern-mapper picks among the 4 already-migrated ones).
- **The TST-03 cross-path equality test** — new test contract in a planner-picked home; uses MintModule's existing `processTicketBatch` / `_raritySymbolBatch` surfaces; no contract change.
- **The `test/REGRESSION-BASELINE-v50.md` ledger** — sits alongside `REGRESSION-BASELINE-v49.md`; authored at the binding TST-04 close (USER-gated per D-CC-03).

</code_context>

<specifics>
## Specific Ideas

- **TST-03 anchor pins to the 334 verdict by path.** The deterministic test's docstring includes the verbatim text *"per `.planning/phases/334-.../334-MINTDIV01-REACHABILITY-VERDICT.md`: owed=300 at level L, warm budget 550, maxT=292"* — so audit lineage is 1:1 traceable. This is the user's "deterministic anchor + boundary fuzz" choice (D-TST03-01) given concrete form.
- **TST-04 headline language mirrors v49 verbatim.** The binding sentence in `test/REGRESSION-BASELINE-v50.md` is the v49 ledger's headline with version + commit substituted — same NAME-set-equality wording, same warning about bare counts.
- **No new freeze-fuzz file authored.** The roadmap LOCKS `RngLockDeterminism.t.sol` as the home (D-TST01-01); authoring `RngLockFreezeSafetyV50.t.sol` (or similar) would be a parallel-harness anti-pattern.

</specifics>

<deferred>
## Deferred Ideas

- **The external RNG-audit protocol package + cold-start context pack** — Phase 337 deliverable, NOT 336's. (337 authors the model-agnostic R1→R4 multi-round kit against the FROZEN post-v50 tree; 336 just produces that frozen tree.)
- **The 3-skill genuine-PARALLEL adversarial sweep + the internal delta-audit + the `audit/FINDINGS-v50.0.md` closure deliverable** — Phase 338 TERMINAL, NOT 336.
- **Hardhat-side parity beyond "stay-green-at-v49-last-known"** — the Foundry NON-WIDENING ledger is the authoritative gate (D-TST04-03); deeper Hardhat parity work is out of v50.0 scope.
- **Full MintModule loop dedup** — D-15 rejected for v50; TST-03 proves the one-liner-fix invariant, not the dedup-equivalence invariant. Standing maintenance idea for a future cycle.
- **A dedicated `refreshPass()` entrypoint regression test** — D-10 rejected `refreshPass()`; the lazy-only crossing-refresh is the surface TST-02 covers. No test needed for a rejected surface.
- **The ≤level-10 whale-pass bonus band regression test** — D-21 DROPPED the band at IMPL; no test needed for removed code (and the 338 SWEEP economic-analyst re-attests the value-delta per D-06).

### Reviewed Todos (not folded)

None — no pending todos matched Phase 336 in the cross-reference scan.

</deferred>

---

*Phase: 336-tst-equivalence-freeze-safety-divergence-repro-non-widening-*
*Context gathered: 2026-05-28*
