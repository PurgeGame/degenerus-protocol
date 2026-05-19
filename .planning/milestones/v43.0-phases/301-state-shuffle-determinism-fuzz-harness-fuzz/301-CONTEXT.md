# Phase 301: State-Shuffle Determinism Fuzz Harness (FUZZ) - Context

**Gathered:** 2026-05-18
**Status:** Ready for planning
**Posture:** AUDIT-ONLY milestone with `test/` mutations permitted; `contracts/` MUST remain unchanged per `D-43N-AUDIT-ONLY-01`.

<domain>
## Phase Boundary

Foundry harness phase that ships `test/fuzz/RngLockDeterminism.t.sol` exercising randomized action sequences mid-rngLock window (between VRF request and fulfillment). For each randomized perturbation sequence, asserts byte-identical VRF-derived outputs (jackpot recipients, jackpot amounts, trait awards, lootbox tickets, hero-override outcome) vs no-perturbation baseline. Action set per FUZZ-02: bets, mints, claims, ERC20/ERC721 transfers, approvals, affiliate registration, every admin/owner function (from Phase 300 ADMA-01 enumeration), `retryLootboxRng` invocations. Coverage: every CAT-01 13-consumer surface exercised by ≥1 fuzz case. Edge cases per FUZZ-05: admin-during-lock, near-end-of-window, multi-tx-batch, multi-block within window, retryLootboxRng-during-lock. Runs count: 10k per fuzz case per `D-43N-FUZZ-RUNS-01`. **`vm.skip` strategy per `D-43N-FUZZ-VMSKIP-01`:** fuzz cases that reproduce a CATALOG VIOLATION at current contract state are `vm.skip`-gated so CI passes green at v43.0 closure; v44.0 FIX-MILESTONE flips skips to assertions as fixes land per the FIXREC-05 handoff anchors. Harness ships as regression oracle for v44.0 consumption. Wave shape: 1 AGENT-COMMITTED batched test commit (test-tree only) per `D-43N-TEST-COMMITS-AUTO-01` user-authorization 2026-05-18 (only mainnet contracts/*.sol require approval; test/ + .planning/ + docs free to commit autonomously per `feedback_no_contract_commits.md` clarified policy). **Zero `contracts/` mutations.** Requirements FUZZ-01..05 (5).

</domain>

<decisions>
## Implementation Decisions

### Foundry Harness Architecture

- **D-301-HARNESS-ARCH-01:** **Single `test/fuzz/RngLockDeterminism.t.sol` Foundry harness file** with per-CAT-01-consumer fuzz function (`testFuzz_RngLockDeterminism_<ConsumerName>`). Each per-consumer test:
  1. Setup phase: deploy game (or fork pre-launch state); arrange to VRF-request boundary; capture pre-lock baseline state snapshot via `vm.snapshot()`
  2. Lock phase: assert `game.rngLocked() == true`; capture additional baseline at lock-entry
  3. Perturbation phase: execute randomized action sequence (fuzzed inputs) drawn from the action set per FUZZ-02
  4. Resolution phase: deliver mock VRF word; advance to consumer execution; capture VRF-derived output(s) for THIS consumer
  5. Baseline phase: `vm.revertTo()` to pre-perturbation snapshot; re-execute lock + resolution WITHOUT perturbations; capture baseline VRF-derived output(s)
  6. Assert phase: compare perturbation output(s) vs baseline output(s); assert byte-identical OR `vm.skip()` if known-failing per `D-43N-FUZZ-VMSKIP-01`

- **D-301-RUNS-01:** **10k runs per fuzz case** per `D-43N-FUZZ-RUNS-01`. Foundry-config'd via `[fuzz] runs = 10000` in `foundry.toml` (project-scoped or test-scoped). CI default. Diminishing-return coverage gain past 10k for state-shuffle determinism; 1k risks under-sampling rare-perturbation classes; 100k risks CI timeouts.

- **D-301-VMSKIP-MECHANISM-01:** **`vm.skip` strategy** per `D-43N-FUZZ-VMSKIP-01`. Mechanism options:
  - Option A: Per-test-function `vm.skip(true)` at top of test body (whole-function skip) — coarse; one entire fuzz function skipped per VIOLATION
  - Option B: Per-fuzz-iteration `vm.assume()` gate filtering out known-failing perturbation classes — fine-grained but harder to maintain
  - Option C: Per-VIOLATION skip block with explicit cross-reference comment to RNGLOCK-FIXREC.md §N entry — coarse but traceable for v44.0 flip
  - **Selected: Option C** — explicit per-VIOLATION skip blocks with comment `// SKIP: RNGLOCK-FIXREC.md §{N} — {brief VIOLATION summary} — v44.0 D-43N-V44-HANDOFF-{NN} flips this to strict assertion`. v44.0 flip removes the skip + asserts byte-identity. **Why:** traceability for v44.0 plan-phase consumption; clear audit trail per skip; matches `feedback_no_history_in_comments.md` discipline (the comment describes WHAT IS — the skip's purpose + cross-reference — not what changed).

### Coverage Strategy

- **D-301-COVERAGE-01:** **≥1 fuzz function per CAT-01 13-consumer surface** per FUZZ-04. Plan-phase 301 authors one `testFuzz_RngLockDeterminism_<ConsumerName>` function per consumer in the 13-entry CAT-01 list (Phase 298 `D-298-CONSUMER-LIST-01`):
  1. `testFuzz_RngLockDeterminism_PayDailyJackpot`
  2. `testFuzz_RngLockDeterminism_PayDailyJackpotCoinAndTickets`
  3. `testFuzz_RngLockDeterminism_RunTerminalJackpot`
  4. `testFuzz_RngLockDeterminism_RunTerminalDecimatorJackpot`
  5. `testFuzz_RngLockDeterminism_GameOverRngSubstitution`
  6. `testFuzz_RngLockDeterminism_ResolveRedemptionLootbox`
  7. `testFuzz_RngLockDeterminism_ResolveLootboxCommon`
  8. `testFuzz_RngLockDeterminism_DegeneretteLootboxDirect`
  9. `testFuzz_RngLockDeterminism_RetryLootboxRng` (exempt-path; asserts the failsafe DOES change VRF-derived output via fresh VRF word — opposite-direction assertion)
  10. `testFuzz_RngLockDeterminism_MintTraitGeneration`
  11. `testFuzz_RngLockDeterminism_BurnieCoinflipResolve`
  12. `testFuzz_RngLockDeterminism_StakedStonkRedemption`
  13. `testFuzz_RngLockDeterminism_DecimatorAwardLootbox`

- **D-301-EDGE-CASES-01:** **5 edge-case fuzz functions per FUZZ-05** (separate from per-consumer functions):
  - `testFuzz_EdgeCase_AdminDuringLock` — every admin function (from ADMA-01) called during lock window; assert per-consumer VRF outputs byte-identical
  - `testFuzz_EdgeCase_NearEndOfWindow` — perturbations in last block before unlock
  - `testFuzz_EdgeCase_MultiTxBatch` — multi-tx perturbations within a single block
  - `testFuzz_EdgeCase_MultiBlock` — perturbations across multiple blocks within the window
  - `testFuzz_EdgeCase_RetryLootboxRngDuringLock` — failsafe-path-during-lock interaction

### Claude's Discretion (planner & executor latitude)

- **D-301-WAVE-SHAPE-01 — 1 AGENT-COMMITTED batched test commit.** Test-tree only per `D-43N-TEST-COMMITS-AUTO-01`. Bundle: `test/fuzz/RngLockDeterminism.t.sol` + any helper files in `test/fuzz/helpers/` + Foundry config delta if needed (`foundry.toml` `[fuzz]` section). Autonomous commit per `feedback_no_contract_commits.md` clarified policy (only mainnet `.sol` files require approval; tests are free). `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` continue to apply ONLY to mainnet contracts (none touched at Phase 301).

- **D-301-EXEC-SHAPE-01 — Main-context end-to-end.** Foundry harness authoring is a single concentrated work-stream; main-context is appropriate. If individual `testFuzz_*` functions are heavy enough, plan-phase may decompose into parallel sub-agents per consumer (mirroring `D-298-EXEC-SHAPE-01` shape).

- **D-301-FORGE-CONFIG-01 — Project-scoped `[fuzz]` config or test-scoped pragma.** Plan-phase chooses based on whether existing Foundry tests have a different default runs count. If existing tests use default 256 runs, the 10k runs for this harness should be test-scoped (not project-scoped) to avoid slowing other test suites.

- **D-301-RESEARCH-AGENT-01 — Plan-phase skips research-agent dispatch.** Foundry fuzz patterns are well-known; methodology locked.

- **D-301-VERIFICATION-01 — `forge test --match-path test/fuzz/RngLockDeterminism.t.sol` PASSES at commit time.** All non-skipped fuzz cases assert byte-identity successfully; skipped cases enumerated with explicit cross-reference comments.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 301 Anchors
- `.planning/ROADMAP.md` — Phase 301 entry (FUZZ harness with vm.skip strategy)
- `.planning/REQUIREMENTS.md` — FUZZ-01..05 verbatim (post-pivot with vm.skip note)
- `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` — Phase 298 CATALOG context; CAT-01 13-consumer list (`D-298-CONSUMER-LIST-01`) drives per-consumer fuzz function set
- `.planning/phases/299-fix-recommendation-document-fixrec/299-CONTEXT.md` — FIXREC §N entries drive vm.skip-block cross-references
- `.planning/phases/300-admin-path-enumeration-audit-adma/300-CONTEXT.md` — ADMA-01 admin function enumeration drives FUZZ-02 action set + `testFuzz_EdgeCase_AdminDuringLock`
- `.planning/RNGLOCK-CATALOG.md` (Phase 298 output) — load-bearing input for per-consumer assertion-target identification
- `.planning/RNGLOCK-FIXREC.md` (Phase 299 output) — vm.skip-block cross-references

### Foundry Tooling
- `foundry.toml` (project root) — Foundry config; may need `[fuzz] runs = 10000` per-test or project-scoped per `D-301-FORGE-CONFIG-01`
- Existing `test/` directory layout (check before authoring) — confirm `test/fuzz/` subdirectory exists or needs creation

### v44.0 FIX-MILESTONE Forward Handoff
- v44.0 plan-phase: as each FIX-NN sub-phase lands, removes the corresponding `vm.skip` block + flips to strict byte-identity assertion + verifies the harness PASSES on the fixed contract. Harness becomes v44.0's primary acceptance-test artifact.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Existing `test/` directory layout** — check for Foundry vs Hardhat split; v42 milestones used Hardhat heavily (TST-MINTCLN, TST-HRROLL, TST-DPNERF) but v43 explicitly Foundry per FUZZ-01 wording
- **Phase 296 `123f2dac` VRFStallEdgeCases.t.sol** — Foundry test precedent in the codebase (check format for inheritance pattern)
- **`game.rngLocked()` public view** — direct rngLock-window probe; harness assertion lever

### Established Patterns
- **USER-APPROVED batched test commit gate** — Phase 282/286/289/291/293/295 + 296 mid-sweep test commits precedent
- **vm.skip with explicit cross-reference comment** — new pattern; tracks back to FIXREC §N for v44.0 flip discipline

### Integration Points
- **Phase 298 → Phase 301**: CAT-01 13-consumer list = 13 per-consumer fuzz functions
- **Phase 299 → Phase 301**: FIXREC §N entries = vm.skip-block cross-references
- **Phase 300 → Phase 301**: ADMA-01 admin function set = FUZZ-02 action set + EdgeCase fuzz function
- **Phase 301 → Phase 303**: §3.A delta-surface table includes the test commit; AUDIT-01 lists this as the SOLE USER-APPROVED commit at v43.0 close

</code_context>

<specifics>
## Specific Ideas

- **`vm.skip` block format** with cross-reference comment to RNGLOCK-FIXREC.md §N + v44.0 handoff anchor ID — load-bearing for v44.0 flip discipline
- **Mock VRF word delivery** — harness uses Foundry cheatcodes to deliver mock VRF without invoking the actual Chainlink coordinator; deterministic baseline derivation
- **`vm.snapshot()` + `vm.revertTo()`** baseline pattern — single fuzz iteration runs both perturbation + baseline paths, asserts equivalence

</specifics>

<deferred>
## Deferred Ideas

- **Per-VIOLATION strict-mode flag** (e.g., `FORGE_FUZZ_STRICT=1` env-var that disables all `vm.skip` blocks) — considered + rejected per `D-43N-FUZZ-VMSKIP-01` "vm.skip strategy" wording. Single-mode harness simpler. v44.0 flips skips inline as fixes land.
- **Property-based invariant tests** (`forge test --match-path` with `invariant_*` functions) — defer to v44.0 if a class of invariants emerges that's hard to express in `testFuzz_*` shape
- **Differential fuzzing** (compare against external implementation) — out of scope; rngLock determinism is self-referential (perturbation vs baseline on same contract)

</deferred>

---

*Phase: 301-State-Shuffle-Determinism-Fuzz-Harness-FUZZ*
*Context gathered: 2026-05-18*
