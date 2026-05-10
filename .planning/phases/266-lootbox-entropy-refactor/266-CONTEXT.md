# Phase 266: Lootbox-Path Entropy Refactor - Context

**Gathered:** 2026-05-09
**Status:** Ready for planning (locked decisions captured below; user approved scope inline during pre-planning conversation; no formal `/gsd-discuss-phase` ceremony required)

<domain>
## Phase Boundary

Replace `EntropyLib.entropyStep` (XOR-shift PRNG) chains in the lootbox-resolution code path with inline bit-sliced reads from `EntropyLib.hash2(rngWord, structured-input)`-derived seeds. Single-phase patch (mirrors lightweight v3.x patch pattern; NOT the full v34/v35 multi-phase milestone shape). v36.0 = Phase 266 only.

**Audit baseline:** v35.0 audit-subject HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6` (closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6` carry-forward from `audit/FINDINGS-v35.0.md` §9c).

**Audit subject HEAD at phase-start:** Same as baseline — `5db8682b`. Phase 266 introduces ONE batched contract commit (per `feedback_batch_contract_approval.md`) + N test commits (per-commit USER-COMMITTED) + AGENT-COMMITTED audit deliverable + closure flips. Final closure signal `MILESTONE_V36_AT_HEAD_<sha>` references the post-Phase-266 contract-tree HEAD.

**24 v36.0 requirements (per REQUIREMENTS.md, all mapped to Phase 266):**

- **ENT-01..06** — 7 lootbox-path `entropyStep` callsites refactored to inline bit-sliced `hash2` draws; per-consumer bit-budget documented inline; `EntropyLib` API stable (no helper additions, no behavior change to existing functions); BAF jackpot xorshift explicitly OUT of scope (ENT-05 deferral).
- **STAT-01..03** — Light statistical validation (chi² uniformity per sub-roll bucket, 5K-10K samples, reusing Phase 261/264 chi² infra; no new tooling).
- **GAS-01..02** — Per-open gas delta within ±300 g; advanceGame envelope unchanged within ±2K (Decimator settlement is the one advanceGame-resident lootbox-resolution caller).
- **SURF-01..04** — Cross-surface preservation: `EntropyLib.sol` body byte-identical; BAF jackpot `_jackpotTicketRoll` byte-identical (ENT-05 verification); MintModule + non-lootbox JackpotModule callsites byte-identical.
- **AUDIT-01..05** — 9-section delta audit deliverable `audit/FINDINGS-v36.0.md`; closure signal `MILESTONE_V36_AT_HEAD_<sha>`; KNOWN-ISSUES.md EntropyLib XOR-shift entry rephrased to BAF-jackpot-only scope.
- **REG-01..04** — v35 + v34 closure signals re-verified non-widening; KI envelope re-verifications (EXC-04 NARROWS to BAF-only); prior-finding spot-check sweep across audit/FINDINGS-v25..v35.

**Pre-decided / locked from inline conversation (no re-discussion):**

- **Phase shape — single phase + single multi-task plan.** Path 2 chosen over Path 1 (v33→258 re-ship pattern). v36.0 opens fresh; v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682b` stays sealed. Phase 266 covers implementation + tests + audit deliverable + closure flips in one phase. Plan likely single multi-task atomic-commit-per-task (mirrors v33 Phase 257 / v34 Phase 262 / v35 Phase 265 single-plan precedent for combined contract+test+audit work).
- **EntropyLib API — inline shifts only, no helpers.** Per user disposition: don't add `byteAt` / `uint16At` / `uint24At` helpers to EntropyLib. Each refactored consumer uses inline `uint16(seed) % 100`, `uint8(seed >> 16) % 5` style. Saves the function-dispatch overhead vs helper functions; costs slight readability. `EntropyLib.entropyStep` and `EntropyLib.hash2` bodies stay byte-identical; `EntropyLib.sol` file gains zero new functions.
- **BAF jackpot `_jackpotTicketRoll` (JackpotModule:2186-2229) — OUT of scope.** Per user disposition "look at 3 but don't change now". Investigation captured: same xorshift pattern, single `entropyStep` call (L2192), identical `% 100` + `% 4` / `% 46` slicing — trivially convertible (~30 bits sliced from one keccak). Captured as future-phase candidate; ENT-05 deferral. SURF-02 verifies byte-identity at v36.0 close.
- **Behavioral equivalence — NOT required.** Per user disposition "behavior change is fine as long as it is correctly random". Pre-/post-refactor output stream produces different concrete outcomes for the same VRF word (both uniformly distributed; specific winners shift). Not a regression — both are uniform. STAT-02 only requires distribution-shape equivalence within statistical tolerance, not specific-outcome replay.
- **Test depth — light.** Per user disposition "just do some tests to assure randomness". Chi² per sub-roll bucket at α=0.05 (5K-10K samples per bucket; not the 10K-aggregated full STAT-01..05 v34/v35 depth). Plus gas regression spot-check + cross-surface byte-identity grep-proof. No D-IMPL-01-style boundary harness; no behavioral-replay tests.
- **KNOWN-ISSUES.md EntropyLib XOR-shift entry** — rephrase to BAF-jackpot-only scope at v36 close (since lootbox path no longer uses xorshift). Don't remove entirely — BAF jackpot still uses xorshift (ENT-05 deferral). Entry text rephrased something like: "EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls. `EntropyLib.entropyStep` is consumed by `_jackpotTicketRoll` (JackpotModule:2192) for BAF jackpot ticket-distribution path (target level + offset selection). [Same security argument: seeded by VRF-derived `keccak256(rngWord, ...)`, small number of steps, modular arithmetic over small ranges.] Lootbox-path consumption removed at v36.0 per Phase 266 refactor; remaining xorshift consumer is BAF jackpot only — candidate for future-phase refactor following the same bit-sliced keccak pattern."
- **Adversarial-pass methodology** — `/contract-auditor` + `/zero-day-hunter` parallel spawn (mirrors v33 Phase 257 / v34 Phase 262 / v35 Phase 265 D-265-ADVERSARIAL-01..03 pattern). Explicitly NOT spawning `/economic-analyst` or `/degen-skeptic` (consistent with v35 D-265-ADVERSARIAL-01 carry).
- **§9 closure-attestation TWO-subsection format** — §9.NN.i USER-APPROVED contracts (1 batched commit) + §9.NN.ii USER-APPROVED tests (N test commits) + §9.NN.iii AGENT-COMMITTED audit artifacts. NO §9.NN.iv awaiting-approval subsection. Mirrors v35 D-265-CLOSURE-02 / v34 D-262-CLOSURE-02 carry.
- **Forward-cite zero-emission** — terminal-phase invariant per D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 carry chain. v36.0 = Phase 266 only, so Phase 266 is the terminal phase. §8 grep-recipe verifies zero forward-cite emission to v37.0+ phases.
- **Closure signal SHA** = `git rev-parse HEAD` at the audit-pass-close commit (typically the final §9 closure-attestation commit). If contract-tree mutation lands during Phase 266 (it WILL — that's the point of this phase), signal SHA references the mutation-inclusive HEAD. Mirrors D-265-CLOSURE-01 carry.
- **Per-commit user approval discipline** — per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. The agent does NOT pre-approve any contract commit. The agent presents the batched diff at end of impl-task block and waits for explicit user "approved" before committing. Tests batched similarly.
- **Final user-review gate before push** — per `feedback_manual_review_before_push.md`. Final task surfaces complete diff (audit deliverable + KNOWN-ISSUES.md changes + ROADMAP/STATE/MILESTONES flips + 266-01-SUMMARY) to user for approval before READ-only flip + closure flips commit. NO `git push` by agent.
- **Inline-execution acceptable** — given the v35 Phase 265 experience where `gsd-executor` subagent was blocked by global `.md`-write guard, user may opt for inline orchestrator execution again at execute-phase time. Plan should be structured to support either delegation or inline (no agent-spawn-specific assumptions in task structure).

**Phase 266 boundary state at close:**

- 1 contract commit landed in `contracts/modules/DegenerusGameLootboxModule.sol` (lootbox refactor; ENT-01..06).
- Zero changes to `contracts/libraries/EntropyLib.sol` (ENT-04 stable-API constraint).
- Zero changes to `contracts/modules/DegenerusGameJackpotModule.sol` (SURF-02 BAF byte-identity + SURF-04 non-lootbox JackpotModule byte-identity).
- Zero changes to `contracts/modules/DegenerusGameMintModule.sol` (SURF-03).
- N test commits under `test/stat/` and/or `test/gas/` (chi² + gas regression).
- `audit/FINDINGS-v36.0.md` published as FINAL READ-only at v36.0 closure HEAD.
- `KNOWN-ISSUES.md` modified — EntropyLib XOR-shift entry rephrased to BAF-only scope.
- ROADMAP / STATE / MILESTONES updated; v36.0 milestone marked SHIPPED.
- Closure signal `MILESTONE_V36_AT_HEAD_<sha>` emitted in 5 locations.

</domain>

<decisions>
## Implementation Decisions

### Refactor Pattern — DEFAULT-APPLIED (per user disposition)

- **D-266-API-01 (no EntropyLib helper additions):** Per user disposition "inline shifts only". `EntropyLib.entropyStep` and `EntropyLib.hash2` bodies stay byte-identical; no `byteAt` / `uint16At` / `uint24At` style helpers added to the library. Each refactored consumer in `DegenerusGameLootboxModule.sol` uses inline `uint8(seed)`, `uint16(seed)`, `uint24(seed)`, `uint8(seed >> 8)`, etc. Per-consumer bit-offset slicing documented inline (NatSpec or comment block).

- **D-266-SEED-01 (single-keccak-per-resolution pattern with overflow fallback):** Each lootbox-resolution invocation derives ONE 256-bit seed at the entry point of `_resolveLootboxCommon` via `EntropyLib.hash2(rngWord, structured-input)` where `structured-input` mixes the player address + day + amount or similar high-bit-diversity inputs. The seed is threaded through `_rollTargetLevel`, `_resolveLootboxRoll`, `_lootboxTicketCount` as a function parameter. Each consumer slices its bit-budget from the threaded seed via inline shifts. Falls back to a second 256-bit chunk via `EntropyLib.hash2(seed, 1)` ONLY if a single resolution exceeds the per-call bit budget (~80-128 bits typical; 256-bit headroom is ample).

- **D-266-BIT-BUDGET-01 (per-consumer bit-budget targets):** Each `% small` slice has a documented modulo bias bound (target ≤ 1% bias for any draw):
  - `% 5` (near-level offset in `_rollTargetLevel` L823): use 8 bits → bias = 256 mod 5 / 256 = 0.39%
  - `% 100` (rangeRoll in `_rollTargetLevel` L814): use 16 bits → bias = 65536 mod 100 / 65536 = 0.05%
  - `% 46` (far-level offset in `_rollTargetLevel` L818): use 16 bits → bias = 65536 mod 46 / 65536 = 0.05%
  - `% 20` (path-roll in `_resolveLootboxRoll` L1551): use 16 bits → bias = 65536 mod 20 / 65536 = 0.02%
  - `% 20` (variance-roll in `_resolveLootboxRoll` L1600): use 16 bits → bias = 0.02%
  - `% 10000` (varianceRoll in `_lootboxTicketCount` L1636): use 24 bits → bias = 16777216 mod 10000 / 16777216 = 0.045%
  - All other small-modulus slices (`% 4` for trait rotation, etc.): use 8 bits → bias under 1%
  - Total per-resolution bit-budget: ~80-128 bits worst case. One 256-bit `hash2` seed covers it 2× over.

- **D-266-CONSUMER-LIST-01 (the exact 7 callsites refactored in scope):** All in `contracts/modules/DegenerusGameLootboxModule.sol` at HEAD `5db8682b`:
  1. L813 `_rollTargetLevel` — `levelEntropy = EntropyLib.entropyStep(entropy);`
  2. L817 `_rollTargetLevel` — `farEntropy = EntropyLib.entropyStep(levelEntropy);` (only on 10% far-level branch)
  3. L1548 `_resolveLootboxRoll` — `nextEntropy = EntropyLib.entropyStep(entropy);` (entry advance)
  4. L1569 `_resolveLootboxRoll` — `nextEntropy = EntropyLib.entropyStep(nextEntropy);` (DGNRS-path advance)
  5. L1585 `_resolveLootboxRoll` — `nextEntropy = EntropyLib.entropyStep(nextEntropy);` (WWXRP-path advance)
  6. L1599 `_resolveLootboxRoll` — `nextEntropy = EntropyLib.entropyStep(nextEntropy);` (large-BURNIE-path advance)
  7. L1635 `_lootboxTicketCount` — `nextEntropy = EntropyLib.entropyStep(entropy);` (variance-tier roll)

  Plus any sub-call paths inside `_resolveLootboxCommon` body (boon roll, whale-pass roll, lazy-pass roll, presale BURNIE multiplier roll) that consume `entropy` and chain onward — planner must enumerate these during planning by reading `_resolveLootboxCommon` body L847-1000+ in detail.

### Out-of-Scope Boundaries — DEFAULT-APPLIED

- **D-266-SCOPE-OUT-01 (BAF jackpot xorshift deferral):** `_jackpotTicketRoll` (`contracts/modules/DegenerusGameJackpotModule.sol:2186-2229`) uses the same xorshift pattern (single `EntropyLib.entropyStep` at L2192 + `% 100` + `% 4` / `% 46` slicing) and would benefit from the same refactor. Explicitly OUT of scope per user disposition. Future-phase candidate. SURF-02 verifies byte-identity at v36.0 close as a deferral-discipline check.
- **D-266-SCOPE-OUT-02 (no EntropyLib API additions):** Per D-266-API-01. SURF-01 verifies `EntropyLib.sol` body byte-identical at v36.0 close.
- **D-266-SCOPE-OUT-03 (no behavioral-replay tests):** Per user disposition "just do some tests to assure randomness". Tests assert distribution uniformity, not specific-outcome replay against pre-refactor baseline. Acceptable that pre/post produces different concrete winners for the same VRF word.
- **D-266-SCOPE-OUT-04 (KNOWN-ISSUES.md "Lootbox RNG uses index advance" entry):** Separate cleanup discussed inline; will be addressed as a follow-on (or as part of Phase 266 KNOWN-ISSUES.md edit task — planner's call). NOT a Phase 266 audit deliverable.

### Adversarial-Pass Methodology (AUDIT-02) — DEFAULT-APPLIED (D-265 carry)

- **D-266-ADVERSARIAL-01 (skill selection):** `/contract-auditor` + `/zero-day-hunter` only. v35 D-265-ADVERSARIAL-01 carry-forward. Explicitly NOT spawning `/economic-analyst` or `/degen-skeptic`.
- **D-266-ADVERSARIAL-02 (timing — sequential after full §4 draft):** v35 D-265-ADVERSARIAL-02 carry. Plan author writes full §4 inline draft (all surfaces verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence). Sequential validation pass after full draft is written. Spawn `/contract-auditor` AND `/zero-day-hunter` in parallel as a single message, BOTH red-teaming the FINISHED §4 draft (not re-deriving from scratch). All adversarial-pass artifacts logged in `266-01-ADVERSARIAL-LOG.md`.
- **D-266-ADVERSARIAL-03 (disagreement disposition):** v35 D-265-ADVERSARIAL-03 carry. Per `feedback_wait_for_approval.md`, any disagreement (skill flags a SAFE verdict as candidate, OR `/zero-day-hunter` surfaces a novel composition) surfaces to user inline. User decides verdict before deliverable READ-only flip.

### File Decomposition — DEFAULT-APPLIED (single-file deliverable)

- **D-266-FILES-01 (single canonical deliverable):** Author `audit/FINDINGS-v36.0.md` directly with all 9 sections embedded. No `audit/v36-*.md` per-AUDIT-NN working files. Mirrors v33 D-257-FILES-01 / v34 D-262-FILES-01 / v35 D-265-FILES-01.

### Closure Attestation (§9) — DEFAULT-APPLIED

- **D-266-CLOSURE-01 (signal SHA = HEAD at audit-pass-close commit):** Mirror v35 D-265-CLOSURE-01 / v34 D-262-CLOSURE-01 / v33 D-257-CLOSURE-01. Closure signal `MILESTONE_V36_AT_HEAD_<sha>` references the post-Phase-266 contract-tree HEAD. Phase 266 WILL introduce contract-tree mutation (LootboxModule refactor); signal SHA references the mutation-inclusive HEAD.
- **D-266-CLOSURE-02 (commit-readiness register §9.NN — TWO subsections):** Mirror v35 D-265-CLOSURE-02 / v34 D-262-CLOSURE-02. §9.NN.i USER-APPROVED contracts (1 batched commit for the LootboxModule refactor) + §9.NN.ii USER-APPROVED tests (N test commits) + §9.NN.iii AGENT-COMMITTED audit artifacts (Phase 266 plan-close commits). NO §9.NN.iv awaiting-approval subsection.

### Plan Decomposition (Claude's Discretion within v33/v34/v35 precedent)

- **D-266-PLAN-01 (single multi-task plan):** Mirror v33 Phase 257 / v34 Phase 262 / v35 Phase 265 single-plan precedent for combined contract+test+audit work. Phase 266 has natural seams: (1) contract refactor batched commit + (2) gas + chi² test commits + (3) §1-§9 audit deliverable atomic-commit-per-section + (4) adversarial-pass + (5) KNOWN-ISSUES.md edit + (6) closure flips. Single multi-task plan with ~12-16 atomic-commit-per-task ordering (smaller than v35 Phase 265's 14-task plan because v36 is narrower scope; some tasks consolidated).
  - **Multi-plan alternative:** Split into 266-01 contract + 266-02 audit. Cleaner ownership boundaries; costs N× plan-creation overhead. Not recommended per single-plan-multi-task precedent.

### Severity Rubric Reference — DEFAULT-APPLIED

- **D-266-SEV-01 (D-08 5-bucket severity rubric carry-forward):** Inherited from v35 D-265-SEV-01 / v34 D-262-SEV-01 / v33 D-257-SEV-01 / v25-onward D-08. No re-derivation.

### Approval & Commit Posture — DEFAULT-APPLIED

- **D-266-APPROVAL-01 (audit/.planning writes agent-author):** Mirror v35 D-265-APPROVAL-01. `audit/FINDINGS-v36.0.md` + `.planning/phases/266-*/*` + ROADMAP/STATE/MILESTONES updates land in atomic-commit chain by agent. User reviews `audit/FINDINGS-v36.0.md` diff before any push per `feedback_manual_review_before_push.md`; READ-only flip locks the deliverable post-approval.
- **D-266-APPROVAL-02 (contract + test commits USER-APPROVED batched):** Mirror v33 / v34 / v35 contract-batched-approval pattern. Per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`: agent does NOT pre-approve any contract commit. The agent presents the batched LootboxModule diff at end of contract-task block and waits for explicit user "approved" before committing. Tests batched similarly. The audit deliverable (after contract+test land) follows the v35 Phase 265 pattern of agent-authored + per-task atomic commits.

### Claude's Discretion

- **Test file structure** — `test/stat/LootboxEntropyDistribution.test.js` (NEW) for chi² + `test/gas/LootboxOpenGas.test.js` or extension of an existing gas test for GAS-01..02. Planner picks single vs split.
- **Bit-slice ordering convention** — which bits of the 256-bit seed map to which sub-roll. Planner picks (e.g., low-to-high, or grouped by sub-function). Consumer-side comments document the mapping.
- **`hash2(seed, N)` chunk indexing** — if a resolution exceeds 256-bit budget, second chunk uses `hash2(seed, 1)` (counter) or `hash2(seed, "boon")` (tagged). Planner picks; AUDIT-02 surface (c) verifies collision-free across consumers.
- **NatSpec depth** — how much per-consumer documentation goes into the contract. Planner picks; minimum: which bits each `% small` consumes + any `hash2(seed, N)` chunk usage.
- **§3 per-phase section** — Phase 266 is its own only-phase, so §3 enumerates Phase 266 work directly (no Phase 263/264-style multi-phase consolidation needed). Single §3a section covering implementation + tests + KNOWN-ISSUES.md edit; §3d AUDIT-01 delta-surface table; §3e AUDIT-03 conservation re-proof; §3c (if needed) AUDIT-06-style indexer / behavioral disclosure note (likely not needed since lootbox outputs aren't indexed in a v34→v35 AUDIT-06-equivalent way — but planner verifies).
- **REG-04 row count** — defensive grep-walk across audit/FINDINGS-v25..v35.0.md for findings referencing v36-touched function set. Planner enumerates during plan execution.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 266 Anchors

- `.planning/ROADMAP.md` §"Phase 266: Lootbox-Path Entropy Refactor" — 5 success criteria; depends-on = nothing (single-phase patch); audit baseline v35.0 closure HEAD `5db8682b`.
- `.planning/REQUIREMENTS.md` ENT-01..06 + STAT-01..03 + GAS-01..02 + SURF-01..04 + AUDIT-01..05 + REG-01..04 — 24 v36.0 requirements all mapped to Phase 266.
- `.planning/STATE.md` — milestone v36.0 status; Phase 266 active; v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682b` carry-forward context.

### v33.0 Phase 257 + v34.0 Phase 262 + v35.0 Phase 265 Precedent (deliverable shape + audit methodology)

- `audit/FINDINGS-v35.0.md` — v35.0 9-section deliverable; closure signal `MILESTONE_V35_AT_HEAD_5db8682b`; 6-of-6 §4 surfaces SAFE_*; STAT-03 reframe row precedent; §9.NN three-subsection format. **Primary template for Phase 266 deliverable shape.**
- `audit/FINDINGS-v34.0.md` — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4`; secondary template precedent.
- `.planning/phases/265-delta-audit-findings-consolidation/265-CONTEXT.md` — Phase 265 carry-forward decision chain (D-265-FILES-01 / D-265-ADVERSARIAL-01..03 / D-265-PLAN-01 / D-265-FIND-01 / D-265-CLOSURE-01..02 / D-265-FCITE-01 / D-265-SEV-01 / D-265-APPROVAL-01..02). **Primary template for Phase 266 decision shape.**
- `.planning/phases/265-delta-audit-findings-consolidation/265-01-PLAN.md` — Phase 265 single-plan multi-task atomic-commit ordering precedent.
- `.planning/phases/265-delta-audit-findings-consolidation/265-01-ADVERSARIAL-LOG.md` — adversarial-pass log format precedent.
- `.planning/phases/265-delta-audit-findings-consolidation/265-01-SUMMARY.md` — phase-closure SUMMARY format precedent.

### Live Contract State (refactor subject — HEAD `5db8682b`)

- `contracts/modules/DegenerusGameLootboxModule.sol` — 7 `EntropyLib.entropyStep` callsites at L813, L817, L1548, L1569, L1585, L1599, L1635. ENT-01..03 modify; AUDIT-01 §3d delta-surface table enumerates all changes.
- `contracts/libraries/EntropyLib.sol` — `entropyStep(uint256) → uint256` (lines 16-23) and `hash2(uint256, uint256) → uint256` (lines 36-42). Both bodies stay byte-identical at v36 (ENT-04 / SURF-01).
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_jackpotTicketRoll` (L2186-2229) BAF jackpot path with single `entropyStep` call at L2192. ENT-05 deferral target; SURF-02 byte-identity verification.
- `contracts/modules/DegenerusGameMintModule.sol` — `EntropyLib.hash2(entropy, rollSalt)` callsite at L652. SURF-03 byte-identity verification.

### Test Surfaces (light statistical validation per user disposition)

- `test/stat/PerPullLevelDistribution.test.js` (Phase 264) — chi² infrastructure (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ`) reused by Phase 266 STAT-01..03.
- `test/stat/SurfaceRegression.test.js` (Phase 264) — extension target for SURF-01..04 byte-identity grep-proof.
- `test/gas/Phase264GasRegression.test.js` (Phase 264) — gas regression infrastructure precedent for GAS-01..02.

### Memory / Feedback Governing This Phase

- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 266 has 1 batched contract commit + N batched test commits, all USER-APPROVED.
- `feedback_batch_contract_approval.md` — batch all phase contract edits, present one diff at end. LootboxModule refactor is one batched commit per this discipline.
- `feedback_never_preapprove_contracts.md` — orchestrator/agent must NOT pre-approve any contract change. Vacuous unless agent attempts to claim pre-approval; just don't.
- `feedback_no_history_in_comments.md` — refactored LootboxModule code describes what IS, never what changed or what it used to be. NatSpec describes the bit-slice scheme as the current design, NOT "this was xorshift before".
- `feedback_wait_for_approval.md` — D-266-ADVERSARIAL-03 escalation rule + D-266-APPROVAL-02 contract-diff approval gate.
- `feedback_manual_review_before_push.md` — user reviews `audit/FINDINGS-v36.0.md` diff before any push.
- `feedback_rng_backward_trace.md` — REG-03 EXC-04 RE_VERIFIED uses backward-trace methodology cited inline (entry NARROWS to BAF-only at v36 since lootbox no longer uses xorshift).
- `feedback_rng_commitment_window.md` — §4 surface (b) addresses commitment-window check (player cannot bias rngWord post-commit; the seed `hash2(rngWord, structured-input)` consumes VRF-derived bits).
- `feedback_gas_worst_case.md` — GAS-01..02 derive theoretical worst-case bit-slice + keccak overhead first, then test.
- `feedback_skip_research_test_phases.md` — single-phase patch with locked decisions; skip research-agent dispatch (this CONTEXT.md captures all locked decisions inline).

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at HEAD `5db8682b` (UNMODIFIED at v35.0 close after AUDIT-06 venue-mismatch revert). EntropyLib XOR-shift entry NARROWS to BAF-jackpot-only scope at v36.0 close per AUDIT-05 / D-266-AUDIT-CARRY-01.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **9-section template prose** — copy structural skeleton from `audit/FINDINGS-v35.0.md` §1-§9 (most recent precedent). Substitute v35→v36 milestone identifiers, v35→v36 closure-signal SHAs, v35→v36 phase IDs.
- **§4 row format** — copy from v35.0 §4 (6-surface a-f + STAT-03 reframe row); adapt for v36 surfaces (likely 4-5 lootbox-entropy-specific surfaces).
- **§5 regression appendix** — copy from v35.0 §5a-d. v36 REG-01 covers v35 closure signal carry-forward + REG-02 covers v34 carry-forward + REG-04 covers prior-finding spot-check.
- **§6 KI gating walk** — copy from v35.0 §6a-c. EXC-04 RE_VERIFIED row in §6b NARROWS scope (BAF-only at v36); §6c verdict summary likely `0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_REPHRASED (1 entry rephrased to BAF-only scope under Design Decisions)`.
- **§9 closure-attestation TWO-subsection format** — copy from v35.0 §9.NN per D-266-CLOSURE-02.
- **Closure-signal emission paragraph** — copy from v35.0 §9c; substitute `MILESTONE_V35` → `MILESTONE_V36` and HEAD SHA.
- **Phase 261/264 chi² infrastructure** — `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim in new `test/stat/LootboxEntropyDistribution.test.js` header per STAT-03 reuse-existing-tooling discipline.

### Established Patterns

- **Pure-consolidation phase discipline does NOT apply at v36** — Phase 266 IS a contract-modifying phase (LootboxModule refactor). Mixed shape: contract + test + audit. Same as v33 Phase 254/255/256 (impl) + v33 Phase 257 (audit) but consolidated into one phase per single-phase-patch shape.
- **Atomic-commit per task** — v33/v34/v35 single-plan multi-task pattern. Phase 266 inherits.
- **Adversarial-pass logging** — v33/v34/v35 wrote `{padded_phase}-01-ADVERSARIAL-LOG.md`. Phase 266 mirrors via `266-01-ADVERSARIAL-LOG.md`.
- **Forward-cite zero-emission** — terminal-phase invariant. §8 grep-recipe verifies zero forward-cite emission across phase artifacts (no v37+ cites).

### Integration Points

- **`audit/FINDINGS-v36.0.md`** — sole canonical deliverable (single-file per D-266-FILES-01). Lives in `audit/` directory alongside FINDINGS-v25.0..v35.0.
- **`KNOWN-ISSUES.md`** — modified ONCE per AUDIT-05 (one entry rephrased to BAF-only scope under Design Decisions). All other modifications gated through D-09 (default UNMODIFIED for the rest of v36.0 surface).
- **`ROADMAP.md`** — closure-signal emission paragraph updated; v36.0 section flipped to COMPLETE; closure-signal `MILESTONE_V36_AT_HEAD_<sha>` recorded.
- **`MILESTONES.md`** — v36.0 entry prepended to top with closure-signal recorded; v35.0 demoted.
- **`STATE.md`** — milestone v36.0 marked closed; Last Shipped Milestone updated; v35.0 demoted to Prior Shipped Milestone.
- **`.planning/phases/266-lootbox-entropy-refactor/`** — phase artifacts: 266-CONTEXT.md (this file), 266-01-PLAN.md (planner output), 266-01-SUMMARY.md (executor output), 266-01-ADVERSARIAL-LOG.md (executor output).

</code_context>

<specifics>
## Specific Ideas

### KNOWN-ISSUES.md EntropyLib XOR-shift entry — rephrased prose at v36 close

Current entry (line 31 of KNOWN-ISSUES.md):

```
**EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.
```

Proposed v36-close prose (planner refines):

```
**EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls.** `EntropyLib.entropyStep()` (256-bit XOR-shift, shifts 7/9/8) is consumed by `_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) for BAF jackpot ticket-distribution path (target level + offset selection per ticket). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded by VRF-derived `keccak256` mix at the upstream call boundary; the single per-ticket step + modular arithmetic over small ranges (`% 100` + `% 4` / `% 46`) mask any non-uniformity. Lootbox-path consumption was removed at v36.0 per Phase 266 refactor (now uses bit-sliced `EntropyLib.hash2` keccak draws); remaining xorshift consumer is BAF jackpot only — candidate for future-phase refactor following the same bit-sliced keccak pattern.
```

### Bit-slice convention example for `_rollTargetLevel`

```solidity
// CURRENT (xorshift) — 7 entropyStep callsites in lootbox path
function _rollTargetLevel(uint24 baseLevel, uint256 entropy)
    private pure returns (uint24 targetLevel, uint256 nextEntropy)
{
    uint256 levelEntropy = EntropyLib.entropyStep(entropy);
    uint256 rangeRoll = levelEntropy % 100;
    if (rangeRoll < 10) {
        uint256 farEntropy = EntropyLib.entropyStep(levelEntropy);
        uint256 levelOffset = (farEntropy % 46) + 5;
        targetLevel = baseLevel + uint24(levelOffset);
        nextEntropy = farEntropy;
    } else {
        uint256 levelOffset = levelEntropy % 5;
        targetLevel = baseLevel + uint24(levelOffset);
        nextEntropy = levelEntropy;
    }
}

// PROPOSED (bit-sliced keccak) — single hash2 seed at entry of _resolveLootboxCommon
// threaded through; this function consumes 24-32 bits of seed via inline shifts.
//
// Bit budget: rangeRoll uses bits[0..15] (% 100, bias 0.05%); near-level offset
// uses bits[16..23] (% 5, bias 0.39%); far-level offset uses bits[24..39] (% 46, bias 0.05%).
function _rollTargetLevel(uint24 baseLevel, uint256 seed)
    private pure returns (uint24 targetLevel)
{
    uint256 rangeRoll = uint16(seed) % 100;        // bits[0..15]
    if (rangeRoll < 10) {
        uint256 farOffset = uint16(seed >> 24) % 46;   // bits[24..39]
        targetLevel = baseLevel + uint24(farOffset + 5);
    } else {
        uint256 nearOffset = uint8(seed >> 16) % 5;   // bits[16..23]
        targetLevel = baseLevel + uint24(nearOffset);
    }
}
```

Note: signature changed (drop `nextEntropy` return; seed is owned by caller). Caller pattern shifts from threading `nextEntropy` through chained calls to slicing offsets from the same seed (or `hash2(seed, N)` chunks for overflow).

</specifics>

<deferred>
## Deferred Ideas

### BAF jackpot `_jackpotTicketRoll` xorshift refactor (ENT-05)

`_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) consumes a single `EntropyLib.entropyStep` at L2192 with `% 100` + `% 4` / `% 46` slicing — same pattern as `_rollTargetLevel`. Trivially convertible (~30 bits sliced from one keccak via `hash2(rngWord, salt)`). Per user disposition: "look at 3 but don't change now". Captured as future-phase candidate; ENT-05 deferral discipline verified by SURF-02 byte-identity grep at v36.0 close. Future phase would mirror Phase 266's bit-slice pattern; KNOWN-ISSUES.md EntropyLib XOR-shift entry could be removed entirely at that point.

### KNOWN-ISSUES.md "Lootbox RNG uses index advance isolation" entry (separate cleanup)

Discussed inline during pre-planning conversation: this entry frames index-advance isolation as a deviation that needs explanation, but per user "this is a common pattern in my contracts" — index-advance is the protocol's standard idiom for non-blocking VRF paths; rngLockedFlag is the special case (daily VRF only). Entry framing is backwards. Removal candidate. NOT a Phase 266 audit deliverable per D-266-SCOPE-OUT-04; can be addressed as a quick standalone cleanup commit either inside Phase 266 (planner's call) or as a separate post-v36 maintenance task.

### v35.0 milestone archive rotation

Per STATE.md operator-next-step note from v35.0 close: "Optionally rotate `.planning/milestones/v35.0-ROADMAP.md` + `v35.0-REQUIREMENTS.md` archive structure (mirroring v34.0 archive pattern)." `v35.0-REQUIREMENTS.md` was archived as part of v36.0 setup (this CONTEXT.md scaffolding commit); `v35.0-ROADMAP.md` and `v35.0-phases/` directory rotation deferred.

### Audit of post-v32.0 unaudited commits (`002bde55`, `2713ce61`)

Carry-forward deferral from v33.0 → v34.0 → v35.0 → v36.0 close per repeated user disposition. NOT a Phase 266 deliverable. Tracked in REQUIREMENTS.md Out of Scope table.

### Adversarial-skill expansion

`/economic-analyst` and `/degen-skeptic` explicitly NOT in scope per D-266-ADVERSARIAL-01 (v35 D-265-ADVERSARIAL-01 carry). If post-adversarial-pass concerns surface around game-theory or practitioner-burned patterns, those skills can be added in a follow-up audit pass — but require a new explicit user opt-in.

### Behavioral-replay tests

Per user disposition: not required. Pre-/post-refactor specific outcomes diverge (different concrete winners for same VRF word); only uniform-distribution equivalence verified. If product team later wants an indexer-replay tool that needs deterministic equivalence, a future phase could add behavioral-replay tests + decide on a deterministic-equivalence-preserving refactor variant. Out of scope at v36.0.

</deferred>

---

*Phase: 266-lootbox-entropy-refactor*
*Context gathered: 2026-05-09*
*Locked decisions captured inline during pre-planning conversation; no formal `/gsd-discuss-phase` ceremony required.*
