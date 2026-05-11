# Phase 269: Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Two orthogonal maintenance workstreams under one phase boundary:

1. **LBX-01..03 — Dead-branch cleanup.** `contracts/modules/DegenerusGameLootboxModule.sol` `_resolveLootboxRoll` at L1568-1581 deletes the structurally-dead `if (targetLevel < currentLevel) { burnieOut = ... }` branch (the inner third layer of a triple-defense pattern; layers 1 and 2 at `openLootBox` L557 and `_resolveLootboxCommon` L882 already clamp `targetLevel = max(targetLevel, currentLevel)` before the inner check is reached). Replace with direct `if (ticketsScaled != 0) { ticketsOut = ticketsScaled; }`. Single batched USER-APPROVED contract commit. ZERO behavioral change at any timing for any player (caller-clamp invariant proves byte-equivalence). `test/gas/LootboxOpenGas.test.js` extended with v37.0 describe asserting per-tickets-path-open gas savings ≥30 g and ≤80 g (~50g/open headline; 55%-tickets-path probability profile = ~27g amortized) + bytecode shrink via deployment-byte-count delta. LBX-03 audit-trail row authored in Phase 271 §3.A delta-surface (line numbers may shift; bit-slice budget UNAFFECTED).

2. **GASPIN-01..03 — SURF-05 gas-pin drift.** Phase 261/264 SURF-05 gas pins in `test/gas/AdvanceGameGas.test.js` (Phase 264 SURF-05 describe at L1464+) and/or `test/gas/Phase264GasRegression.test.js` drift ~120K under `npm run test:stat` ordering vs standalone-stable. Hypotheses: (a) state pollution from prior test files; (b) gas-meter snapshot ordering; (c) fixture-loader caching; (d) hardhat node restart timing. Bisect-by-removal across the 14-file `test:stat` ordering identifies the polluting predecessor; stabilization path chosen post-RCA from {re-pin / ordering-fix / split-files} on least-invasive principle. Decision recorded inline at the test fixture per ROADMAP letter (no separate working file).

**Audit baseline:** v36.0 closure HEAD `1c0f09132d7439af9881c56fe197f81757f8164a`. v37.0 source-tree HEAD at Phase 269 entry = Phase 267 contract commit `e1136071`. Phase 268 (test/stat-only) shipped at `4b277aaf`.

**Phase 269 boundary state at close:**

- 1 batched USER-APPROVED contract commit (LBX-01: ~5-line hunk at `DegenerusGameLootboxModule.sol` L1568-1581 → 3-line replacement).
- 1 batched USER-APPROVED test commit covering: (a) `test/gas/LootboxOpenGas.test.js` v37.0 describe extension (LBX-02); (b) GASPIN re-pin / ordering-fix / split-files diff (whichever stabilization path the RCA dictates); (c) `test/stat/SurfaceRegression.test.js` SURF-03 update (re-baseline to Phase-269-close HEAD per D-269-SURF03-01); (d) `package.json` wiring deltas IF the RCA dictates split-files.
- 6 of 6 LBX-01..03 + GASPIN-01..03 requirements flipped to PASS at Phase 269 close; PROGRESS table 0/0 → 1/1 (single multi-task plan).
- ZERO new storage slots; zero new public/external mutation entry points; zero new modifiers; zero new admin functions.
- LBX-03 §3.A audit-trail row authored in Phase 271 (NOT Phase 269).
- Phase 269 LBX deletion is behavior-preserving cleanup → adversarial pass (`/contract-auditor` + `/zero-day-hunter`) deferred to Phase 271 §4 surface (f).

</domain>

<decisions>
## Implementation Decisions

### Carry-forward (locked from prior milestones — not re-asked)

- **D-269-FILES-01 (single canonical audit deliverable, Phase 271):** Mirror v37 D-267-FILES-01 / D-268-FILES-01. NOT a Phase 269 concern.
- **D-269-CLOSURE-01 (signal SHA = HEAD at audit-pass-close):** Mirror v37 D-267-CLOSURE-01 / D-268-CLOSURE-01. NOT a Phase 269 concern.
- **D-269-CLOSURE-02 (commit-readiness register §9.NN three-subsection):** Mirror v37 D-267-CLOSURE-02 / D-268-CLOSURE-02. Phase 269 SUMMARY contributes both §9.NN.i USER-APPROVED contracts row (LBX-01) AND §9.NN.ii USER-APPROVED tests row (LBX-02 + GASPIN fix + SURF-03 update).
- **D-269-SEV-01 (D-08 5-bucket severity rubric):** NOT a Phase 269 concern.
- **D-269-APPROVAL-01 (audit/.planning writes agent-author):** Phase 269 SUMMARY + PLAN + DISCUSSION-LOG + CONTEXT all AGENT-COMMITTED.
- **D-269-APPROVAL-02 (contract + test commits USER-APPROVED batched):** Per `feedback_no_contract_commits.md` (test-tree treated identically to contract-tree per Phase 268 D-268-APPROVAL-02 carry) + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Phase 269 has 1 batched contract commit AND 1 batched test commit; agent presents diff and waits for explicit user "approved" before each.
- **D-269-LBX-CALLERCLAMP-CARRY-01 (caller-clamp invariant proven byte-equivalent at runtime):** Triple-defense pattern documented during discussion: layer 1 = `openLootBox` L557 outer caller clamp; layer 2 = `_resolveLootboxCommon` L882 inner caller clamp; layer 3 = `_resolveLootboxRoll` L1574 dead inner check. Layers 1 + 2 unconditionally execute before layer 3 is reachable; both came in at the initial commit `aafb7e0d` (git pickaxe trace). LBX-01 deletion removes layer 3 only; layers 1 + 2 remain untouched → byte-equivalent player-facing behavior at any timing for any open path (ETH lootbox, BURNIE lootbox, direct resolve, redemption resolve).
- **D-269-LBX-GAMETHEORY-CARRY-01 (delay confers no advantage; bounded loss of optionality only):** Discussion-time game-theory analysis: `targetLevel` is rolled at resolve-time via `_rollTargetLevel(baseLevel, seed)` (90% near-future = baseLevel + 0..4; 10% far-future = baseLevel + 5..50). `baseLevel` selected by 7-day grace-period rule at `openLootBox` L549-552 (`withinGracePeriod = currentDay <= day + 7`; `baseLevel = withinGracePeriod ? graceLevel : purchaseLevel`). Player who holds past grace gets `baseLevel = purchaseLevel` → most rolls land below currentLevel → triple-defense clamp pulls `targetLevel` up to currentLevel → tickets queue at currentLevel (immediate next cycle). NO tickets lost; NO past-bucket queueing; NO advantage from waiting (cannot pick `targetLevel` by timing — `seed = keccak256(rngWord, player, day, amount)` is fixed for ETH lootboxes since `day = lootboxDay[index][player]` is snapshotted at buy by `MintModule.sol` L1409-1410); ONLY loses far-future bucket distribution variety (the 10% far-future roll's spread collapses to "currentLevel only"). Validates `D-269-LBX-SHAPE-01` pure-deletion choice.

### Locked this discussion

- **D-269-LBX-SHAPE-01 (pure deletion of L1568-1581 dead branch):** Replace L1568-1581 with `if (ticketsScaled != 0) { ticketsOut = ticketsScaled; }`. NO `require(targetLevel >= currentLevel)` invariant assert; NO NatSpec contract on caller's responsibility. Maximum gas savings (~50g/open + bytecode shrink) per `feedback_no_dead_guards.md` letter. Forward-risk bound: (a) `_resolveLootboxRoll` is `private` (`grep -rn "_resolveLootboxRoll" contracts/` returns only the definition + 2 caller-sites at `_resolveLootboxCommon` L910 + L938 — no widening of the call graph possible without external visibility change); (b) Phase 271 LBX-03 §3.A audit-trail row enforces post-deletion grep recipe consistency. NO trace comment at the deletion site per `feedback_no_history_in_comments.md` (caller-clamp invariant is self-evident from local L860-884 reading).

- **D-269-PLAN-01 (single multi-task PLAN covering both workstreams; LBX-first sequencing):** Single `269-01-PLAN.md` with ~5 atomic tasks. Mirrors Phase 267/268 single-multi-task-atomic-commit-per-task precedent. Default ordering (planner refines exact decomposition):
  1. **GASPIN-01 root-cause investigation:** bisect-by-removal across `test:stat` 14-file ordering (per D-269-RCA-01); identify the polluting predecessor file + mechanism (state pollution / gas-meter snapshot ordering / fixture-loader caching / hardhat node restart timing). Document RCA in `269-01-PLAN.md` short root-cause section. AGENT-COMMITTED chore commit if any planning artifact lands at this step.
  2. **LBX-01 batched USER-APPROVED contract commit:** delete L1568-1581 dead branch per D-269-LBX-SHAPE-01; single hunk in `contracts/modules/DegenerusGameLootboxModule.sol`. Compile cleanly. Present diff, wait for explicit "approved", commit.
  3. **LBX-02 + GASPIN-02 + SURF-03 batched USER-APPROVED test commit:** all four test deltas together — (a) `test/gas/LootboxOpenGas.test.js` v37.0 describe (LBX-02 ≥30g and ≤80g per-open savings + bytecode shrink + worst-case derivation in NatSpec header per `feedback_gas_worst_case.md` D-269-WORSTGAS-01); (b) GASPIN stabilization (re-pin / ordering-fix / split-files diff per D-269-STAB-01 RCA-driven choice); (c) `test/stat/SurfaceRegression.test.js` SURF-03 re-baseline to Phase-269-close HEAD per D-269-SURF03-01; (d) `package.json` wiring deltas if RCA chose split-files. One diff, one approval, one commit.
  4. **Phase-close:** `269-01-SUMMARY.md` + 6-requirement PASS table + STATE.md flip + commit-readiness register update.
  ~3-4 atomic commits total (depending on whether GASPIN RCA produces a standalone chore commit). Single-plan-multi-task discipline.

- **D-269-COMMITS-01 (single batched USER-APPROVED test commit):** ONE test commit covering LBX-02 LootboxOpenGas extension + GASPIN re-pin/fix + SURF-03 update + any `package.json` wiring. Mirrors Phase 268 `4b277aaf` batching pattern. Treats all test-tree edits in this phase as a single coherent change set. One approval round. Per `feedback_batch_contract_approval.md`. Plural "test/chore commit(s)" wording in ROADMAP §"Phase 269: ..." accommodates this single-commit shape (the singular case satisfies the plural).

- **D-269-RCA-01 (bisect-by-removal first, escalate to instrumentation if inconclusive):** GASPIN-01 root-cause method: start with bisect — remove test files from `test:stat` ordering one at a time (in reverse order of execution, then forward), identify which prior file pollutes SURF-05 gas pins in `test/gas/AdvanceGameGas.test.js` (Phase 264 SURF-05 describe L1464+) and/or `test/gas/Phase264GasRegression.test.js`. Cheap and likely conclusive (drift is order-dependent → a specific predecessor file is the most probable cause; the 14-file ordering is small enough for log₂(14) ≈ 4 bisect rounds to isolate). If bisect doesn't isolate (e.g., drift is multi-file-cumulative or hardhat-node-restart-timing-related), escalate to instrumented hardhat-snapshot diff or per-test gas-meter trace inspection. Deliverable: short root-cause section IN `269-01-PLAN.md` + inline NatSpec at the affected test fixture (per ROADMAP letter — "decision documented inline at the test fixture"). NO separate `269-NN-GASPIN-RCA.md` working file (Phase 270 owns the only working-file appendix in v37.0; Phase 269 stays plan-internal).

- **D-269-STAB-01 (wait for RCA, then pick least-invasive):** GASPIN-02 stabilization preference NOT pre-locked. Post-RCA, agent picks among ROADMAP's three options on least-invasive principle:
  - **(a) re-pin to combined-suite-stable values + document offset rationale inline** — least-invasive when pollution mechanism is structural (e.g., known fixture-loader cache behavior; cannot be eliminated cheaply).
  - **(b) ordering-fix via `before(() => vm.reset())` injection or test-file isolation** — least-invasive when RCA reveals a one-line surgical fix (e.g., specific fixture re-deployment between describes).
  - **(c) split affected describes across separate test files** — chosen only if (a) and (b) prove infeasible (e.g., pollution is hardhat-node-restart-timing; isolation requires file-boundary).
  Decision recorded inline at the test fixture (per `feedback_no_history_in_comments.md` — describe what IS, not what changed). Test commit lands per D-269-COMMITS-01.

- **D-269-SURF03-01 (re-baseline SURF-03 to Phase-269-close HEAD):** Phase 268 D-268-SURF03-01 carried this update to Phase 269. Pure deletion of L1574-1577 lines + hoist of `ticketsOut = ticketsScaled;` is a small coherent hunk (~5-line diff in one function). Update `test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe (or its SURF-03 specific assertion) to re-baseline against the Phase-269-close HEAD instead of Phase-268-close HEAD. Cleaner than allowed-hunk exception (which would require maintaining a hunk-allowlist that future phases would have to grow). Update lands in the same batched test commit per D-269-COMMITS-01.

- **D-269-WORSTGAS-01 (LBX-02 worst-case derivation in NatSpec header per `feedback_gas_worst_case.md`):** Theoretical worst-case 55%-tickets-path open derived FIRST in `test/gas/LootboxOpenGas.test.js` v37.0 describe NatSpec header BEFORE measurement. Worst-case dimensions:
  - **55%-tickets-path roll** — `roll < 11` branch fires (the path containing the deleted dead branch).
  - **`ticketsScaled != 0`** — inner guard passes; `ticketsOut = ticketsScaled` assignment executes (the path that was always-taken pre-deletion AND is now the unconditional assignment post-deletion).
  - **Maximally cold storage state** — fresh fixture; no pre-warmed slots. Worst-case SLOAD cost.
  - **Tickets-path consumption full** — `_lootboxTicketCount` returns max ticketsScaled (within bounds) to exercise the full BURNIE-arithmetic-removal benefit on the cold-storage branch.
  Test construction: deterministic seed engineered so `uint16(seed >> 40) % 20 < 11` (tickets-path) AND `_lootboxTicketCount(...)` returns nonzero. Measure pre-deletion baseline gas vs post-deletion gas; assert delta ∈ [30, 80] gas (ROADMAP-locked envelope). NO trace comment at the deletion site per `feedback_no_history_in_comments.md`. Per `feedback_gas_worst_case.md`: builds the exact state, doesn't statistically reach.

### Claude's Discretion (planner refines)

- **Bisect ordering** for D-269-RCA-01 — reverse-order vs forward-order vs binary partition first. Planner picks; reverse-order (start by removing trailing files) is the most-common-cause-first heuristic but binary partition is fewer rounds.
- **GASPIN-02 stabilization choice** — locked only post-RCA per D-269-STAB-01; planner reports the chosen path with rationale in `269-01-PLAN.md`.
- **`package.json` `test:stat` wiring** — only changes if RCA chooses split-files (D-269-STAB-01 option c); planner adds the new file path(s) to the existing space-separated list per Phase 268 precedent.
- **LBX-02 test-file shape** — extending an existing `LootboxOpenGas.test.js` describe vs adding a new top-level describe block within the same file. ROADMAP says "extended"; planner picks describe-shape per file-organization preference.
- **Worst-case seed engineering form** for D-269-WORSTGAS-01 — direct `keccak256(...)` precomputed seed vs deterministic VRF-injection helper. Planner picks; if the existing `LootboxOpenGas.test.js` already has a deterministic-seed helper, reuse it; otherwise compute inline.
- **Atomic-commit count** — D-269-PLAN-01 estimates ~3-4 commits; planner finalizes (e.g., whether GASPIN RCA produces a standalone chore commit before the test commit, or folds into the same approval round).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 269 Anchors

- `.planning/ROADMAP.md` §"Phase 269: Lootbox Dead-Branch Cleanup + SURF-05 Gas-Pin Re-Pinning" — 5 success criteria; depends-on = nothing (mixed-maintenance phase; sequenced after Phase 267-268 batched-commit gates per ROADMAP wording).
- `.planning/REQUIREMENTS.md` LBX-01..03 + GASPIN-01..03 — 6 v37.0 requirements all mapped to Phase 269.
- `.planning/STATE.md` — milestone v37.0 status; Phase 268 SHIPPED (`4b277aaf` test commit + 2 AGENT-COMMITTED planning); Phase 269 next.
- `.planning/PROJECT.md` — current focus banner.

### Phase Seed (governing discovery context)

- `.planning/notes/2026-05-10-resolveLootboxRoll-dead-burnie-conversion-branch.md` — discovery context (Phase 266 `/contract-auditor` Hypothesis (m)); structural-dead-code argument; user disposition deferring cleanup to v37.0; proposed cleanup diff (matches D-269-LBX-SHAPE-01); forward-cite to v37.0.

### Phase 268 Source-of-Truth (SURF-03 handoff to Phase 269)

- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-CONTEXT.md` — Phase 268 lock register. Phase 269 inherits D-268-SURF03-01 carry-forward (Phase 268 SURF-03 file-level zero-diff at Phase 268 close → Phase 269 owns SURF-03 update for the LBX dead-branch hunk).
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-PLAN.md` — Phase 268 single-multi-task plan precedent (Phase 269 mirrors structure).
- `.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/268-01-SUMMARY.md` — phase-closure SUMMARY format precedent.

### Live Contract State (test subject — Phase 268 close HEAD `4b277aaf`)

- `contracts/modules/DegenerusGameLootboxModule.sol` — primary mutation target:
  - `_resolveLootboxRoll` (L1548-1646) — LBX-01 dead-branch deletion site at L1568-1581. Dead branch L1574-1576 (`if (targetLevel < currentLevel) { burnieOut = (uint256(ticketsScaled) * PRICE_COIN_UNIT) / TICKET_SCALE; }`); replacement: hoist `ticketsOut = ticketsScaled;` from L1578 unconditional within the surviving `if (ticketsScaled != 0)` guard.
  - `_resolveLootboxCommon` L860-988 — sole caller of `_resolveLootboxRoll` (called at L910 + L938). Layer-2 caller clamp at L882-884 (`if (targetLevel < currentLevel) targetLevel = currentLevel;`). Byte-equivalence proof source.
  - `openLootBox` L526-598 — outer ETH-lootbox open path. Layer-1 outer caller clamp at L557-559. Grace-period rule at L549-552. `seed = keccak256(rngWord, player, day, amount)` at L554. `day` snapshotted at buy via `MintModule.sol` L1409-1410.
  - `openBurnieLootBox` L606-661 — outer BURNIE-lootbox open path. Layer-1 not present (BURNIE path uses `currentLevel` as `baseLevel` directly at L629); relies on `_resolveLootboxCommon` layer-2 + `_resolveLootboxRoll` layer-3 (now layer-2-only post-deletion). `day` fallback to `_simulatedDayIndex()` at L623-626 → flagged for v38+ backlog (potential RNG-grindable IF a BURNIE-lootbox buy path leaves `lootboxDay == 0`).
  - `resolveLootboxDirect` L668-694 — direct resolve path (decimator claim). Uses `_rollTargetLevel(currentLevel, seed)` directly; rolls land at currentLevel + offset → layer-1 clamp redundant; relies on layer-2 only.
  - `resolveRedemptionLootbox` L703-729 — redemption resolve path (sDGNRS burn). Same structure as `resolveLootboxDirect`.
  - `_rollTargetLevel` L812-826 — rolls 90% near-future (baseLevel + 0..4) / 10% far-future (baseLevel + 5..50). Bit-budget consumed per L805-808 NatSpec.

### Test Infrastructure (mutation targets — Phase 269 test commit)

- `test/gas/LootboxOpenGas.test.js` — LBX-02 mutation target. Phase 266 `16ed452b` introduced this file as part of the lootbox-entropy-refactor test commit. Phase 269 extends with v37.0 describe asserting per-tickets-path-open gas savings ≥30 g and ≤80 g + bytecode shrink. Worst-case derivation in NatSpec header per D-269-WORSTGAS-01 + `feedback_gas_worst_case.md`.
- `test/gas/AdvanceGameGas.test.js` — Phase 264 SURF-05 describe at L1464+ (`describe("Phase 264 SURF-05 — advanceGame 1.99× margin preserved at v35.0 HEAD")`). Primary GASPIN-01 drift candidate (1.99× margin assertion at L1627-1635). MAX_BLOCK_GAS = 30_000_000n at L1467.
- `test/gas/Phase264GasRegression.test.js` — Phase 264 gas-pin file. Secondary GASPIN-01 drift candidate (planner identifies which file holds the actually-drifting pin via D-269-RCA-01 bisect).
- `test/stat/SurfaceRegression.test.js` — SURF-03 update target per D-269-SURF03-01. Phase 268 v37.0 SURF-01..04 describe block holds the SURF-03 file-level zero-diff assertion against `1c0f0913` baseline; Phase 269 re-baselines to Phase-269-close HEAD.
- `package.json` `test:stat` script — current ordering (Phase 268 close): `Phase261GasRegression.test.js Phase264GasRegression.test.js Phase268GasRegression.test.js TraitDistribution.test.js GoldSoloCoverage.test.js SoloEvUplift.test.js PackFeel.test.js SurfaceRegression.test.js PerPullLevelDistribution.test.js PerPullEmptyBucketSkip.test.js LootboxEntropyDistribution.test.js DegenerettePerNEvExactness.test.js DegeneretteProducerChi2.test.js DegeneretteBonusEv.test.js`. Bisect target for D-269-RCA-01.

### v36.0 / v37-Phase-267 / v37-Phase-268 Precedent (commit-batching discipline)

- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-PLAN.md` — single-multi-task atomic-commit-per-task precedent.
- Phase 266 `16ed452b` test-tree commit — single batched USER-APPROVED commit (introduced `LootboxOpenGas.test.js`).
- Phase 268 `4b277aaf` test-tree commit — single batched USER-APPROVED commit (5 test files + `package.json` wiring +2,277/-1 LOC). Phase 269 mirrors batching discipline.
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md` — phase-closure SUMMARY format precedent.

### Memory / Feedback Governing This Phase

- `feedback_no_dead_guards.md` — **PRIMARY governing memory for LBX-01.** "Remove unreachable safety caps; don't waste gas on dead branches." Validates D-269-LBX-SHAPE-01 pure-deletion choice over `require`-invariant or NatSpec alternatives.
- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 269 has 1 batched contract commit + 1 batched test commit.
- `feedback_batch_contract_approval.md` — batch all phase contract/test edits, present one diff at end. Phase 269 follows for both contract (single hunk) and test (LBX-02 + GASPIN + SURF-03 + optional package.json) sides.
- `feedback_never_preapprove_contracts.md` — orchestrator/agent must NOT pre-approve any contract or test commit.
- `feedback_wait_for_approval.md` — D-269-APPROVAL-02 contract + test diff approval gates. Agent presents each batched diff, waits for explicit "approved" before committing.
- `feedback_manual_review_before_push.md` — final user-review gate before any push. NO `git push` by agent.
- `feedback_no_history_in_comments.md` — NO trace comment at the LBX-01 deletion site (caller-clamp invariant is self-evident from local `_resolveLootboxCommon` L860-884 reading); GASPIN-02 inline test-fixture decision documents the CURRENT stabilization shape, NOT what was changed.
- `feedback_gas_worst_case.md` — D-269-WORSTGAS-01 derives theoretical worst-case 55%-tickets-path open FIRST in NatSpec header, then constructs deterministic test that hits exactly that state.
- `feedback_skip_research_test_phases.md` — Phase 269 has clear scope (LBX is mechanical single-hunk deletion; GASPIN is bisect-driven RCA per D-269-RCA-01). Skip phase-researcher-agent dispatch; jump straight to plan-phase.
- `feedback_test_rnglock.md` — N/A for Phase 269 (no rngLocked changes; LBX deletion doesn't touch coinflip RNG locks).
- `feedback_rng_backward_trace.md` — N/A for Phase 269 LBX/GASPIN scope. The discussion-time analysis identified the BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 as a candidate concern; routed to v38+ backlog (NOT Phase 269).
- `feedback_contractaddresses_policy.md` — N/A; Phase 269 doesn't touch `ContractAddresses.sol`.

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at v36.0 close. EXC-04 NARROWED to BAF-jackpot-only scope at v36. Phase 269 makes no KI changes. LBX-01 dead-branch cleanup does NOT warrant a new KI entry (defensive-cleanup with byte-equivalent runtime behavior; not a published-behavior change). GASPIN test-infrastructure-only changes do NOT warrant a KI entry. KI walkthrough lives in Phase 271 AUDIT-05.

### Phase 271 Forward-Cite (downstream consumer)

- Phase 271 §3.A delta-surface table — LBX-03 audit-trail row authored here (NOT Phase 269). Confirms ENT-02 (v36.0 Phase 266 entropy refactor) callsite numbering remains consistent post-deletion: `_resolveLootboxRoll` 4 hash2/bit-slice callsites at L1548 / L1569 / L1585 / L1599 (v36.0 line numbers) survive byte-identical at the structural level; bit-slice budget UNAFFECTED; line numbers may shift downward by a few lines after the dead-branch removal but the post-Phase-269 grep recipe stays valid.
- Phase 271 §4 surface (f) — lootbox dead-branch removal byte-equivalence audit (caller-clamp invariant at L860-884). Adversarial pass via `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL after full §4 draft per Phase 271 D-NN-ADVERSARIAL-02 carry; expected verdict SAFE_BY_STRUCTURAL_CLOSURE (caller-clamp invariant proven).
- Phase 271 §5 REG-01 — re-verifies v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` non-widening at v37.0 HEAD; lootbox v36.0-refactored bodies byte-identical EXCEPT for LBX-01 dead-branch deletion (no-behavior-change cleanup, audit-trail row at AUDIT-01 §3.A).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`test/gas/LootboxOpenGas.test.js`:** Phase 266 `16ed452b` introduced this file as part of the lootbox-entropy-refactor test commit. Existing infrastructure for measuring per-open gas across the multi-roll path. Phase 269 extends with v37.0 describe asserting LBX-02 ≥30g/≤80g per-tickets-path-open savings + bytecode-shrink delta. Same fixture pattern can be reused; planner identifies whether the existing file has a deterministic-seed helper for D-269-WORSTGAS-01 worst-case construction (or adds a minimal one inline).
- **`test/gas/Phase264GasRegression.test.js` shape:** Reference template for any GASPIN-02 file-split alternative (D-269-STAB-01 option c). Phase 261/264 gas-regression files live in `test:stat`.
- **`test/gas/AdvanceGameGas.test.js` Phase 264 SURF-05 describe at L1464+:** Primary drift candidate for GASPIN-01 bisect. `MAX_BLOCK_GAS = 30_000_000n` invariant + 1.99× margin assertion. Worst-case stage capture pattern at L1615-1635.
- **`test/stat/SurfaceRegression.test.js` SURF-03 describe pattern:** Existing v37.0 SURF-01..04 describe (per Phase 268 STAT-06 / SURF-03..04 work) shows the file-level zero-diff hunk-intersection check pattern. Phase 269 re-baselines SURF-03 to Phase-269-close HEAD per D-269-SURF03-01.
- **`loadFixture` deployment pattern:** standard Hardhat test pattern for any GASPIN-02 ordering-fix attempt (D-269-STAB-01 option b — `before(() => vm.reset())` injection).

### Established Patterns

- **Single batched contract commit + single batched test commit per phase** — Phase 267 `e1136071` (contract) + Phase 268 `4b277aaf` (test) precedent. Phase 269 inherits both shapes.
- **Atomic-commit per task** — v33/v34/v35/v36/v37-P267/v37-P268 single-plan multi-task pattern.
- **Sample-budget / worst-case derivation in test-file NatSpec header** — Phase 266 LootboxOpenGas precedent + Phase 268 SURF-06 precedent. LBX-02 + GASPIN-02 fixture comments follow.
- **Phase-internal RCA documentation** — v32-v37 phases keep root-cause discussion inside `NN-01-PLAN.md` short root-cause section unless the artifact is genuinely cross-phase (Phase 270 owns `270-01-DELTA-SURFACE.md` because it feeds Phase 271 §3.A authoring; Phase 269 GASPIN RCA is plan-internal per D-269-RCA-01).
- **Caller-clamp invariant as byte-equivalence proof** — established by the discussion-time triple-defense trace; used by LBX-03 §3.A audit-trail row in Phase 271 to assert ENT-02 callsite-numbering consistency.

### Integration Points

- **`contracts/modules/DegenerusGameLootboxModule.sol`** — single hunk at L1568-1581 → ~3-line replacement. ZERO other contract-tree mutations in Phase 269.
- **`test/gas/LootboxOpenGas.test.js`** — LBX-02 v37.0 describe extension.
- **`test/gas/AdvanceGameGas.test.js` and/or `test/gas/Phase264GasRegression.test.js`** — GASPIN-02 mutation target (which file mutates depends on D-269-RCA-01 bisect outcome). Inline NatSpec at affected fixture documents RCA finding + chosen stabilization rationale.
- **`test/stat/SurfaceRegression.test.js`** — SURF-03 re-baseline per D-269-SURF03-01.
- **`package.json`** — `test:stat` script wiring delta IF GASPIN-02 chooses split-files (D-269-STAB-01 option c).
- **`.planning/phases/269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning/`** — phase artifacts: `269-CONTEXT.md` (this file), `269-01-PLAN.md` (planner output, includes short root-cause section per D-269-RCA-01), `269-01-SUMMARY.md` (executor output), `269-DISCUSSION-LOG.md` (sibling to this file).
- **`audit/FINDINGS-v37.0.md`** — does NOT exist yet at Phase 269 close; authored in Phase 271. Phase 269 contributes the §3a per-phase summary content (LBX cleanup + GASPIN test infrastructure stabilization) and §3.A delta-surface row source for LBX-03 + §4 surface (f) byte-equivalence input.

</code_context>

<specifics>
## Specific Ideas

### LBX-01 deletion diff (paste-ready)

```diff
             uint32 ticketsScaled =
                 _lootboxTicketCount(ticketBudget, targetPrice, seed);
             if (ticketsScaled != 0) {
-                if (targetLevel < currentLevel) {
-                    // Convert to BURNIE if target level already passed
-                    burnieOut = (uint256(ticketsScaled) * PRICE_COIN_UNIT) / TICKET_SCALE;
-                } else {
-                    ticketsOut = ticketsScaled;
-                }
+                ticketsOut = ticketsScaled;
             }
             applyPresaleMultiplier = false;
```

Net diff: -5 lines, +1 line. Single hunk in `contracts/modules/DegenerusGameLootboxModule.sol` `_resolveLootboxRoll` (L1568-1581 region).

### LBX-02 worst-case derivation (NatSpec header sketch per D-269-WORSTGAS-01)

```javascript
// LBX-02 — per-tickets-path lootbox-open gas savings (v37.0).
//
// Per `feedback_gas_worst_case.md`, the theoretical worst-case 55%-tickets-path
// open is derived FIRST, then constructed deterministically.
//
// Worst-case dimensions:
//   roll < 11        — 55%-tickets-path branch (the path containing the
//                      deleted dead inner check).
//   ticketsScaled != 0 — inner guard passes; ticketsOut = ticketsScaled
//                      assignment executes (was always-taken pre-deletion;
//                      now unconditional post-deletion).
//   cold storage     — fresh fixture; no pre-warmed slots.
//   max ticketsScaled — _lootboxTicketCount returns a high value within
//                      bounds to exercise the full BURNIE-arithmetic-removal
//                      benefit on the cold-storage branch.
//
// Construction: deterministic seed engineered so
//   uint16(seed >> 40) % 20 < 11   (tickets-path roll)
// AND _lootboxTicketCount(...) returns nonzero with high ticketsScaled.
//
// Assertion: per-open gas delta vs v36.0 baseline ∈ [30, 80] gas.
//            Bytecode shrink confirmed via deployment-byte-count delta.
```

### GASPIN-01 bisect plan sketch (per D-269-RCA-01)

`npm run test:stat` runs 14 files in this order at Phase 268 close:

```
test/gas/Phase261GasRegression.test.js
test/gas/Phase264GasRegression.test.js                   ← SURF-05 candidate site
test/gas/Phase268GasRegression.test.js
test/stat/TraitDistribution.test.js
test/stat/GoldSoloCoverage.test.js
test/stat/SoloEvUplift.test.js
test/stat/PackFeel.test.js
test/stat/SurfaceRegression.test.js
test/stat/PerPullLevelDistribution.test.js
test/stat/PerPullEmptyBucketSkip.test.js
test/stat/LootboxEntropyDistribution.test.js
test/stat/DegenerettePerNEvExactness.test.js
test/stat/DegeneretteProducerChi2.test.js
test/stat/DegeneretteBonusEv.test.js
```

(Note: SURF-05 `Phase 264 SURF-05` describe also lives in `test/gas/AdvanceGameGas.test.js` L1464+, which is NOT in `test:stat` ordering — confirm during RCA whether the drift hits the stat-suite-included `Phase264GasRegression.test.js` SURF-05 pin OR the `AdvanceGameGas.test.js` SURF-05 describe under a different test command.)

Bisect rounds (binary partition; ~log₂(14) ≈ 4 rounds to isolate one polluting predecessor):

1. Run `test:stat` with files [1..7] (predecessors of `SurfaceRegression`); observe SURF-05 drift?
2. Halve the failing set; iterate.
3. Identify the specific predecessor file(s) + the mechanism (reproducible standalone or only-in-combo).
4. If single-file pollution: confirm cause (state pollution / fixture cache / snapshot ordering); pick GASPIN-02 stabilization path per D-269-STAB-01.
5. If multi-file cumulative pollution: escalate to instrumented hardhat-snapshot diff or per-test gas-meter trace inspection per D-269-RCA-01 escalation clause.

### SURF-03 re-baseline form (per D-269-SURF03-01)

`test/stat/SurfaceRegression.test.js` v37.0 SURF-01..04 describe block currently asserts `git diff 1c0f0913 HEAD -- contracts/modules/DegenerusGameLootboxModule.sol` returns empty (true at Phase 268 close). Phase 269 updates the baseline anchor to Phase-269-close HEAD (the post-LBX-deletion sha). Format mirrors existing describe; only the baseline-sha string changes.

</specifics>

<deferred>
## Deferred Ideas

### BURNIE-lootbox `lootboxDay = 0` fallback at `openBurnieLootBox` L623-626 (v38+ candidate)

Discussion-time analysis flagged: `openBurnieLootBox` L623-626 falls back to `day = _simulatedDayIndex()` if `lootboxDay[index][player] == 0`. Since `seed = keccak256(rngWord, player, day, amount)` (L628), this could let a player grind the seed by choosing the open day, IF a BURNIE-lootbox buy path leaves `lootboxDay` unset. ETH-lootbox path is safe (`MintModule.sol` L1409-1410 sets `lootboxDay` at buy unconditionally). Confirmation requires tracing all BURNIE-lootbox buy paths to verify they all write `lootboxDay`. NOT a Phase 269 concern (orthogonal to LBX dead-branch cleanup AND GASPIN drift). Routed to v38+ backlog or a dedicated maintenance phase if confirmed exploitable.

### Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`)

Carry-forward deferral. Phase 270 audit-only. NOT a Phase 269 concern. Phase 270 can run in parallel with Phase 269 from a content perspective (both feed Phase 271 §3.A delta-surface authoring independently).

### Phase 271 §3.A LBX-03 audit-trail row

Authored at Phase 271, NOT Phase 269. Confirms ENT-02 callsite numbering consistency post-deletion. Phase 269 LBX-01 commit produces the post-deletion HEAD against which the §3.A row is authored.

### Phase 271 §4 surface (f) lootbox dead-branch removal byte-equivalence audit

Adversarial pass via `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL after full §4 draft. Expected verdict SAFE_BY_STRUCTURAL_CLOSURE (caller-clamp invariant proven during this discussion). NOT a Phase 269 concern.

### `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion for Phase 271

Resolve at Phase 271 discuss-phase. NOT a Phase 269 concern (LBX/GASPIN cleanup has zero economic-mechanism implications; behavior-preserving cleanup + test-infrastructure stabilization).

### `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry)

Out of v37.0 scope per `.planning/REQUIREMENTS.md` Out of Scope table. Tracked for future milestone.

### `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note)

Out of v37.0 scope.

### Game-over thorough hardening (`gameover-thorough-test.md`)

Out of v37.0 scope.

</deferred>

---

*Phase: 269-lootbox-dead-branch-cleanup-surf-05-gas-pin-re-pinning*
*Context gathered: 2026-05-10*
