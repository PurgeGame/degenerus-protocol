# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- ✅ **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (shipped 2026-04-18) — see [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md)
- ✅ **v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit** — Phases 237-242 (shipped 2026-04-20) — see [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md)
- ✅ **v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit** — Phases 243-246 (shipped 2026-04-24) — see [milestones/v31.0-ROADMAP.md](milestones/v31.0-ROADMAP.md)
- 🚧 **v32.0 Backfill Idempotency + purchaseLevel Underflow Audit** — Phases 247-253 (in progress, started 2026-04-30)

## Phases

<details>
<summary>✅ v25.0 Full Audit (Phases 213-217) — SHIPPED 2026-04-11</summary>

- [x] Phase 213: Delta Extraction (3/3 plans) — completed 2026-04-10
- [x] Phase 214: Adversarial Audit (5/5 plans) — completed 2026-04-10
- [x] Phase 215: RNG Fresh Eyes (5/5 plans) — completed 2026-04-11
- [x] Phase 216: Pool & ETH Accounting (3/3 plans) — completed 2026-04-11
- [x] Phase 217: Findings Consolidation (2/2 plans) — completed 2026-04-11

</details>

<details>
<summary>✅ v26.0 Bonus Jackpot Split (Phases 218-219) — SHIPPED 2026-04-12</summary>

- [x] Phase 218: Bonus Split Implementation (2/2 plans) — completed 2026-04-12
- [x] Phase 219: Delta Audit & Gas Verification (2/2 plans) — completed 2026-04-12

</details>

<details>
<summary>✅ v27.0 Call-Site Integrity Audit (Phases 220-223) — SHIPPED 2026-04-13</summary>

- [x] Phase 220: Delegatecall Target Alignment (2/2 plans) — completed 2026-04-12
- [x] Phase 221: Raw Selector & Calldata Audit (2/2 plans) — completed 2026-04-12
- [x] Phase 222: External Function Coverage Gap (3/3 plans) — completed 2026-04-13
- [x] Phase 223: Findings Consolidation (2/2 plans) — completed 2026-04-13

</details>

<details>
<summary>✅ v28.0 Database & API Intent Alignment Audit (Phases 224-229) — SHIPPED 2026-04-15</summary>

- [x] Phase 224: API Route & OpenAPI Alignment (1/1 plans) — completed 2026-04-13
- [x] Phase 225: API Handler Behavior & Validation Schema Alignment (3/3 plans) — completed 2026-04-13
- [x] Phase 226: Schema, Migration & Orphan Audit (4/4 plans) — completed 2026-04-15
- [x] Phase 227: Indexer Event Processing Correctness (3/3 plans) — completed 2026-04-15
- [x] Phase 228: Cursor, Reorg & View Refresh State Machines (2/2 plans) — completed 2026-04-15
- [x] Phase 229: Findings Consolidation (2/2 plans) — completed 2026-04-15

**Findings:** 69 total (0 CRITICAL/HIGH/MEDIUM, 27 LOW, 42 INFO). See [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md) and [audit/FINDINGS-v28.0.md](../audit/FINDINGS-v28.0.md).

</details>

<details>
<summary>✅ v29.0 Post-v27 Contract Delta Audit (Phases 230-236) — SHIPPED 2026-04-18</summary>

- [x] Phase 230: Delta Extraction & Scope Map (1/1 plans) — completed 2026-04-17
- [x] Phase 231: Earlybird Jackpot Audit (3/3 plans) — completed 2026-04-17
- [x] Phase 232: Decimator Audit (3/3 plans) — completed 2026-04-18
- [x] Phase 232.1: RNG-Index Ticket Drain Ordering Enforcement (3/3 plans) — completed 2026-04-18
- [x] Phase 233: Jackpot/BAF + Entropy Audit (3/3 plans) — completed 2026-04-19
- [x] Phase 234: Quests / Boons / Misc Audit (1/1 plans) — completed 2026-04-19
- [x] Phase 235: Conservation + RNG Commitment Re-Proof + Phase Transition (5/5 plans) — completed 2026-04-18
- [x] Phase 236: Regression + Findings Consolidation (2/2 plans) — completed 2026-04-18

**Findings:** 4 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 32 prior findings re-verified (31 PASS + 1 SUPERSEDED + 0 REGRESSED). See [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md) and [audit/FINDINGS-v29.0.md](../audit/FINDINGS-v29.0.md).

</details>

<details>
<summary>✅ v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit (Phases 237-242) — SHIPPED 2026-04-20</summary>

- [x] Phase 237: VRF Consumer Inventory & Call Graph (3/3 plans) — completed 2026-04-19
- [x] Phase 238: Backward & Forward Freeze Proofs (3/3 plans) — completed 2026-04-19
- [x] Phase 239: rngLocked Invariant & Permissionless Sweep (3/3 plans) — completed 2026-04-19
- [x] Phase 240: Gameover Jackpot Safety (3/3 plans) — completed 2026-04-19
- [x] Phase 241: Exception Closure (1/1 plans) — completed 2026-04-19
- [x] Phase 242: Regression + Findings Consolidation (1/1 plans) — completed 2026-04-20

**Findings:** 17 INFO total (0 CRITICAL/HIGH/MEDIUM/LOW). 31 prior findings re-verified (31 PASS + 0 REGRESSED + 0 SUPERSEDED). 0 of 17 candidates promoted to KNOWN-ISSUES.md (D-05 default path). See [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md) and [audit/FINDINGS-v30.0.md](../audit/FINDINGS-v30.0.md).

</details>

<details>
<summary>✅ v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit (Phases 243-246) — SHIPPED 2026-04-24</summary>

- [x] Phase 243: Delta Extraction & Per-Commit Classification (3/3 plans) — completed 2026-04-23
- [x] Phase 244: Per-Commit Adversarial Audit (EVT + RNG + QST + GOX) (4/4 plans) — completed 2026-04-24
- [x] Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification (2/2 plans) — completed 2026-04-24
- [x] Phase 246: Findings Consolidation + Lean Regression Appendix (1/1 plan) — completed 2026-04-24

**Findings:** Zero F-31-NN findings (0 CRITICAL/HIGH/MEDIUM/LOW/INFO across 142 V-rows / 33 REQs). LEAN regression: 6 PASS REG-01 + 1 SUPERSEDED REG-02. KI EXC-02 + EXC-03 envelopes RE_VERIFIED non-widening; KNOWN-ISSUES.md UNMODIFIED per D-07 default. Closure signal `MILESTONE_V31_CLOSED_AT_HEAD_cc68bfc7`. See [milestones/v31.0-ROADMAP.md](milestones/v31.0-ROADMAP.md) and [audit/FINDINGS-v31.0.md](../audit/FINDINGS-v31.0.md).

</details>

### 🚧 v32.0 Backfill Idempotency + purchaseLevel Underflow Audit (In Progress)

**Milestone Goal:** Prove the two testnet bugs in `DegenerusGameAdvanceModule.sol` are correctly fixed by the WIP guards (backfill double-execution → underflow; turbo-vs-rngLockedFlag race → `purchaseLevel = 0` panic 0x11), and sweep AdvanceModule + delegating modules for sibling-pattern races between `rngLockedFlag` / `lastPurchaseDay` / `jackpotPhaseFlag` / `dailyIdx` that could produce other underflows, double-execution, or skipped updates.

**Audit baseline:** v31.0 HEAD `cc68bfc7` → current HEAD `48554f8f` (4 post-v31.0 contract-touching commits) + WIP work-tree (`ContractAddresses.sol`, `DegenerusGameAdvanceModule.sol`, new `test/edge/LastPurchaseDayRace.test.js`).

**Audit posture:** READ-only LIFTED (was held continuously v28.0–v31.0). Audit-then-commit. WIP turbo guard, backfill guard, and reproduction test — plus any new contract / test changes surfaced by the sibling sweep — land via explicit per-commit user approval per `feedback_no_contract_commits.md`. No autonomous contract or test writes by any agent.

**Deliverable target:** `audit/FINDINGS-v32.0.md`.

- [x] **Phase 247: Delta Extraction & Classification** — Established the v32.0 audit surface for the 4 post-v31.0 contract-touching commits (8bdeabc2 / 6a63705b / 48554f8f / acd88512). Delivered `audit/v32-247-DELTA-SURFACE.md` FINAL READ-only at HEAD `acd88512` with closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512`. 7-section single-deliverable: 16 D-247-C### per-source + state/event/error rows / 11 D-247-F### classification rows (8 MODIFIED_LOGIC + 3 DELETED) / 1 D-247-S### storage-layout UNCHANGED row / 30 D-247-X### call-site rows / 29 D-247-I### Consumer Index rows mapping every Phase 248..253 REQ-ID. 5 atomic per-task commits (e2cacc5c → 9961c91a). Zero `F-32-` IDs (Phase 253 owns). Zero contracts/ or test/ writes per D-247-05.
- [x] **Phase 248: Backfill Idempotency Proof** — Proved the new `rngWordByDay[idx + 1] == 0` guard makes `_backfillGapDays` execute at most once per VRF lock window across every reachable `advanceGame` re-entry path. Delivered `audit/v32-248-BFL.md` FINAL READ-only at HEAD `acd88512` with closure signal `PHASE_248_BFL_FINAL_AT_HEAD_acd88512`. 7-section single-deliverable: §1 BFL-01 (7 V-rows + 3 multiplier rows; rngGate fresh-word branch reachability under L1174 guard) / §2 BFL-02 (6 V-rows over the WHOLE guarded block L1174-1186 per D-248-09 + sentinel-correctness 4-step proof) / §3 BFL-03 (15 V-rows; testnet blocks 10759449 + 10761786 worked example, pre-fix doubling vs post-fix short-circuit) / §4 BFL-04 (4 V-rows; dailyIdx ↔ rngWordByDay invariant, grep-cited universe per D-248-15) / §5 BFL-05 (2 V-rows dual-carrier; both EXC-02 + EXC-03 NON-WIDENING; KI UNCHANGED) / §6 BFL-06 (10 V-rows + conservation algebra; sDGNRS / DGNRS / BURNIE supplies invariant via grep evidence) + Phase 251 TST-04 hand-off appendix. 5 atomic per-task commits (b79f3eac → 5545b125). Zero `F-32-` IDs (Phase 253 owns). Zero contracts/ or test/ writes per D-248-04 / D-248-05.
- [x] **Phase 249: purchaseLevel Correctness Proof** — 4-dimensional state-space sweep over `(lastPurchaseDay, rngLockedFlag, jackpotPhaseFlag, level)` proving `purchaseLevel` cannot be 0 once the `!rngLockedFlag` turbo guard at L167 is in place; underflow audit at every `purchaseLevel`-arithmetic call site. (completed 2026-05-02)
- [x] **Phase 250: Sibling-Pattern Sweep** — Hunt other turbo-class and backfill-class races between `rngLockedFlag` / `lastPurchaseDay` / `jackpotPhaseFlag` / `dailyIdx` / `phaseTransitionActive` across AdvanceModule and every delegating module. (completed 2026-05-02)
- [x] **Phase 251: Reproduction Tests** — Empirically validated the v32.0 WIP guards (turbo at AdvanceModule:173 + backfill at AdvanceModule:1174) against three guard-revert states (A: both reverted; C: backfill-only reverted; D: HEAD with both guards). 4 atomic per-task commits (c73c8add → 65b33299). 8 SAFE V-rows total (2 per REQ); zero FINDING_CANDIDATE. State-A run reproduces panic 0x11 in both LPDR `it()` blocks (TST-01-V01 single-day + TST-01-V02 multi-day-drain). State-D run passes deterministically (TST-02 LPDR + TST-03 LivenessProductivePause + TST-03 LivenessMidJackpot). State-C run on newly authored BackfillIdempotency.test.js produces psdDelta=15 (over-bump) + downstream panic 0x11; state-D produces psdDelta=7 (single-bump per gap day) + clean drain to terminal stage 6 — 53% delta reduction empirically isolates L1174 sentinel. Cross-cite PLV-03 + PLV-05 (audit/v32-249-PLV.md), BFL-03 + BFL §7.1 (audit/v32-248-BFL.md), SIB-04-V01 (audit/v32-250-SIB.md). Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`: ZERO `test/edge/*.test.js` files committed across the 4 Phase-251 atomic commits; both `test/edge/LastPurchaseDayRace.test.js` (existing untracked WIP) and `test/edge/BackfillIdempotency.test.js` (newly authored Task 3; sha-256 `03aecc8329a2520e38abeb5f942648a50abf8de1dad23f0efe28dd92eab7ab72`) remain in untracked on-disk state at plan close, listed in §5 commit-readiness register at status `awaiting-approval` for user manual approval. Closure signal `PHASE_251_TST_FINAL_AT_HEAD_65b33299`. Deliverable `audit/v32-251-TST.md` FINAL READ-only at HEAD `c790ae45`. (completed 2026-05-02)
- [ ] **Phase 252: Post-v31.0 Landed-Commit Sanity** — Delta-sanity verify the 4 landed post-v31.0 commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) against the bug envelopes; RE_VERIFY `8bdeabc2` liveness pause composes with the new turbo guard.
- [ ] **Phase 253: Findings Consolidation + Lean Regression** — Publish `audit/FINDINGS-v32.0.md` with executive summary, F-32-NN finding blocks, KI gating walk, lean regression appendix, and fix-readiness signal `MILESTONE_V32_AT_HEAD_<sha>`.

## Phase Details

### Phase 247: Delta Extraction & Classification
**Goal**: Establish the exact v32.0 audit surface — every changed function, state variable, event, and downstream call site — across the 4 post-v31.0 landed commits + WIP working-tree guards, so the proof phases (248-250) and sanity phase (252) have a complete, grep-reproducible target list anchored at HEAD `48554f8f` + WIP overlay.
**Depends on**: Nothing (first phase of v32.0)
**Requirements**: DELTA-01, DELTA-02, DELTA-03
**Success Criteria** (verifier checklist):
  1. `audit/v32-247-DELTA-SURFACE.md` exists and Section 1 enumerates every changed function, state variable, and event across `git diff cc68bfc7..48554f8f` plus the working-tree diff (turbo guard at AdvanceModule L167, backfill guard at AdvanceModule L1167, untracked `test/edge/LastPurchaseDayRace.test.js`, `ContractAddresses.sol` regen) with hunk-level `path:line` evidence per row.
  2. Section 2 classifies every changed function under the D-04 5-bucket rubric (NEW / MODIFIED_LOGIC / REFACTOR_ONLY / DELETED / RENAMED) with the source commit (`8bdeabc2` / `ad41973c` / `6a63705b` / `48554f8f` / WIP) cited per row.
  3. Section 3 emits a grep-reproducible Consumer Index of every downstream call site for each changed function and interface across `contracts/` (one row per call site, with the exact `grep` command preserved).
  4. Reproduction recipe at end of file regenerates Sections 1–3 deterministically from the recorded HEAD anchor (`48554f8f` + WIP overlay), and the file is marked FINAL READ-only on plan-close commit.
**Plans:** 1/1 plans complete

Plans:
- [x] 247-01-PLAN.md — DELTA-01 + DELTA-02 + DELTA-03 single-plan multi-task catalog at HEAD acd88512 (5 atomic per-task commits per D-247-14)

### Phase 248: Backfill Idempotency Proof
**Goal**: Prove the new `rngWordByDay[idx + 1] == 0` guard makes `_backfillGapDays` execute at most once per VRF lock window across every reachable `advanceGame` re-entry path, that conservation closes across the gap range (no doubled `purchaseStartDay`, no doubled coinflip credits), and that KI EXC-02 / EXC-03 envelopes are RE_VERIFIED non-widening.
**Depends on**: Phase 247 (delta surface and call-site catalog)
**Requirements**: BFL-01, BFL-02, BFL-03, BFL-04, BFL-05, BFL-06
**Success Criteria** (verifier checklist):
  1. `audit/v32-248-BFL.md` exists with one `BFL-01-Vnn` row per code path that reaches `_backfillGapDays` (sole call site at AdvanceModule:1176 inside `rngGate`'s fresh-word branch); every row carries a verdict in {SAFE, FINDING_CANDIDATE} with explicit guard-evaluation evidence.
  2. Every state write inside `_backfillGapDays` (`purchaseStartDay`, coinflip pool credits, `rngWordByDay[d]`, daily ticket processing side effects) has its own row proving the `rngWordByDay[idx + 1] == 0` sentinel correctly skips repeated execution and is the right index (no off-by-one against `idx` or `day`); BFL-02 verdicts are all SAFE.
  3. BFL-03 contains a worked numeric multi-day VRF stall scenario reproducing the testnet underflow trigger sequence (lock window crosses ≥2 wall-clock days, `rngGate` fresh-word path re-enters before `_unlockRng`) and shows the guard short-circuits the second call before any state write executes.
  4. BFL-05 RE_VERIFIES KI EXC-02 (prevrandao fallback) and EXC-03 (gameover RNG substitution) envelopes against the backfill guard with explicit NON-WIDENING attestations carrying `path:line` cites; either both attestations land non-widening or KNOWN-ISSUES.md is updated per D-09 with full gating walk recorded inline.
  5. BFL-06 conservation proof closes algebraically: total ETH credited to coinflip pools across the gap range matches the expected non-doubled amount, `purchaseStartDay` increments exactly once per gap day, and sDGNRS / DGNRS / BURNIE supplies are invariant across the lock window with per-mutation row evidence.
**Plans**: 248-01 — COMPLETE 2026-05-02 (5 atomic per-task commits b79f3eac / 838631a8 / 3be95bfe / 5545b125 + plan-close commit; 6/6 BFL REQs satisfied; closure signal `PHASE_248_BFL_FINAL_AT_HEAD_acd88512`).

### Phase 249: purchaseLevel Correctness Proof
**Goal**: Prove `purchaseLevel` can never be 0 (or otherwise produce the panic 0x11 underflow at `levelPrizePool[uint24(0) - 1]`) at any reachable `(lastPurchaseDay, rngLockedFlag, jackpotPhaseFlag, level)` combination once the WIP `!rngLockedFlag` turbo guard at AdvanceModule:167 is in place, and that no `purchaseLevel`-arithmetic call site can underflow / overflow / index out of bounds.
**Depends on**: Phase 247 (delta surface), Phase 248 (RNG lock-window invariants)
**Requirements**: PLV-01, PLV-02, PLV-03, PLV-04, PLV-05, PLV-06
**Success Criteria** (verifier checklist):
  1. `audit/v32-249-PLV.md` Section 1 enumerates every read site of `purchaseLevel` across AdvanceModule and every delegating module (one `PLV-01-Vnn` row per read site) tagged with the local invariant required (`≥1`, `> level`, `level + 1`, etc.) and a verifier-reproducible grep recipe.
  2. Section 2 contains the explicit 4-dimensional state-space sweep over `(lastPurchaseDay ∈ {false, true}) × (rngLockedFlag ∈ {false, true}) × (jackpotPhaseFlag ∈ {false, true}) × (level ∈ {0, 1, …, levelMax})`; every reachable cell has a verdict proving `purchaseLevel ≥ 1` at the bind line (AdvanceModule:185), and every cell marked unreachable has an explicit reachability-disproof citation.
  3. Section 3 names the unreachable state `(lastPurchase = true ∧ rngLockedFlag = true ∧ lvl = 0)` and proves the ternary at AdvanceModule:185 cannot return 0 by showing the `!rngLockedFlag` turbo guard at L167 short-circuits before that combination can bind.
  4. Section 4 lists every `purchaseLevel`-arithmetic call site (notably AdvanceModule:748 `levelPrizePool[uint24(purchaseLevel) - 1]`, plus all `+1`, `+4`, `_tqReadKey(purchaseLevel)` sites) with one verdict row each proving no underflow / overflow / out-of-bounds at any reachable `purchaseLevel` value.
  5. Section 5 symbolically reproduces the testnet panic 0x11 trigger sequence (blocks 10759449 + 10761786) and shows step-by-step that the new turbo guard short-circuits the path before the binding ternary; Section 6 proves the daily-jackpot region (lines 372–404) does not strand state in a "target met but never resolves" condition under the guard.
**Plans:** 1/1 plans complete

Plans:
- [x] 249-01-PLAN.md — PLV-01 + PLV-02 + PLV-03 + PLV-04 + PLV-05 + PLV-06 single-plan multi-task proof at HEAD acd88512 (4 atomic per-task commits per D-247-14 / D-249-CF-07)

### Phase 250: Sibling-Pattern Sweep
**Goal**: Hunt other turbo-class and backfill-class races across AdvanceModule and every delegating module — every interaction between `rngLockedFlag` / `lastPurchaseDay` / `jackpotPhaseFlag` / `dailyIdx` / `level` / `purchaseStartDay` / `rngWordByDay[*]` / `phaseTransitionActive` is enumerated and classified, so any latent sibling bug surfaces as an explicit F-32-NN candidate before consolidation.
**Depends on**: Phase 247 (delta + call-site surface), Phase 248 (backfill race shape understood), Phase 249 (turbo race shape understood)
**Requirements**: SIB-01, SIB-02, SIB-03, SIB-04, SIB-05
**Success Criteria** (verifier checklist):
  1. `audit/v32-250-SIB.md` Section 1 enumerates every interaction in `DegenerusGameAdvanceModule.sol` where `rngLockedFlag` is read or written alongside `lastPurchaseDay`, `jackpotPhaseFlag`, `dailyIdx`, `level`, `purchaseStartDay`, `rngWordByDay[*]`, or `phaseTransitionActive` (one `SIB-01-Vnn` row per interaction) with `path:line` evidence and a grep-reproducible discovery recipe.
  2. Section 2 classifies every interaction under the {turbo-class, backfill-class, ORTHOGONAL_PROVEN} taxonomy with explicit reasoning per row; ORTHOGONAL_PROVEN rows carry an isolation argument equivalent in form to the v30 Phase 239 lootbox-index-advance / `phaseTransitionActive` proofs.
  3. Section 3 audits each delegating module (`DegenerusGameMintModule`, `DegenerusGameJackpotModule`, `DegenerusGameWhaleModule`, `DegenerusGameLootboxModule`, `DegenerusGameDegenetteModule`, `DegenerusGameBoonModule`, `DegenerusGameDecimatorModule`, `DegenerusGameGameOverModule`) for the same patterns reading the same state, with at least one row per module (or a documented NEGATIVE-scope verdict).
  4. Section 4 cross-checks the 4 post-v31.0 landed commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) for sibling patterns, with `8bdeabc2` (liveness pause during productive multi-call window) called out explicitly as the closest sibling shape and verdict-justified.
  5. Section 5 documents every new bug found with a reproducible trigger sequence, severity classification under the D-08 5-bucket rubric, and an explicit `awaiting-approval` proposed fix block per `feedback_no_contract_commits.md`; if zero new bugs, Section 5 contains an explicit zero-state attestation. No contract or test edits are landed without prior recorded user approval.
**Plans**: TBD

### Phase 251: Reproduction Tests
**Goal**: Empirically validate the WIP guards by running the working-tree reproduction test pre-fix vs post-fix, regressing the prior committed liveness tests, and ensuring at least one reproduction test exists per fixed bug class (turbo race + backfill double-execution). Surface any test commit candidates as `awaiting-approval` per `feedback_no_contract_commits.md`.
**Depends on**: Phase 247 (delta surface includes the new test file), Phase 248 + Phase 249 (the WIP guards under test)
**Requirements**: TST-01, TST-02, TST-03, TST-04
**Success Criteria** (verifier checklist):
  1. `audit/v32-251-TST.md` records the explicit pre-fix run of `test/edge/LastPurchaseDayRace.test.js` against the contract tree with WIP guards reverted: TST-01 verdict carries the verbatim panic 0x11 reverter trace and confirms the test fails reliably without the `!rngLockedFlag` turbo guard.
  2. TST-02 verdict records the post-fix run with both WIP guards (`!rngLockedFlag` at L167 + `rngWordByDay[idx + 1] == 0` at L1167) in place: the test passes deterministically; the harness command and full passing output are quoted verbatim.
  3. TST-03 verdict shows `test/edge/LivenessProductivePause.test.js` and `test/edge/LivenessMidJackpot.test.js` (committed in `8bdeabc2` / `ad41973c`) still pass against the WIP guards, with no new failures introduced; verbatim test runner output is preserved.
  4. TST-04 verdict either confirms `LastPurchaseDayRace.test.js` already covers the backfill double-execution underflow (with the asserting lines quoted), OR adds a new reproduction test under `test/edge/` that fails pre-fix (no backfill guard) and passes post-fix (guard in place); the new test, if added, is queued as an `awaiting-approval` commit candidate, NOT autonomously committed.
  5. Every test commit candidate (existing untracked file or new test) is listed in a Section 5 commit-readiness register with status {awaiting-approval, approved-and-committed} and an explicit user-approval audit trail; no test files outside `audit/` or `.planning/` are written or committed by any agent without that audit trail.
**Plans**: TBD

### Phase 252: Post-v31.0 Landed-Commit Sanity
**Goal**: Delta-sanity verify the 4 landed post-v31.0 commits do not widen the bug envelopes being fixed by v32.0 — i.e. the liveness pause (`8bdeabc2`), liveness regression test (`ad41973c`), purchaseCoin buyer-charge fix (`6a63705b`), and vault redemption decoupling (`48554f8f`) introduce no new turbo-class or backfill-class races; and prove the productive-phase liveness pause composes correctly with the WIP `!rngLockedFlag` turbo guard.
**Depends on**: Phase 247 (delta surface), Phase 248 + Phase 249 (bug envelopes characterised), Phase 250 (sibling taxonomy and SIB-04 cross-check)
**Requirements**: POST31-01, POST31-02
**Success Criteria** (verifier checklist):
  1. `audit/v32-252-POST31.md` Section 1 contains one verdict row per landed commit (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) with explicit NON-WIDENING attestations against both bug envelopes (turbo-class and backfill-class), each carrying `path:line` evidence and a domain-cite to the SIB-04 row.
  2. Section 2 enumerates every interaction between the new `_pauseDeathClockDuringProductivePhase`-class state (`8bdeabc2`) and the WIP `!rngLockedFlag` turbo guard at L167, proving the death clock pauses when expected and resumes correctly without leaving liveness state stranded under the guard.
  3. Section 3 records POST31-02 composition proofs for at least three scenarios: (a) productive multi-call window with WIP turbo guard active, (b) death-clock-paused-and-resumed across a VRF lock window with backfill guard active, (c) a documented edge where turbo would previously fire but is now blocked — and shows liveness gates the same in all three.
  4. Section 4 references the SIB-04 row(s) from `audit/v32-250-SIB.md` to confirm zero double-counting between the SIB sweep verdict and POST31 sanity verdict, and explicitly attests both phases agree on the per-commit risk classification.
**Plans**: TBD

### Phase 253: Findings Consolidation + Lean Regression
**Goal**: Publish `audit/FINDINGS-v32.0.md` as the milestone-closure deliverable mirroring v29/v30/v31 shape (executive summary, per-phase sections, F-32-NN finding blocks, lean regression appendix, KI gating walk, milestone-closure attestation); promote items to `KNOWN-ISSUES.md` only if D-09 3-predicate gating passes; emit fix-readiness signal once any approved WIP guard / test commits land.
**Depends on**: Phase 247, Phase 248, Phase 249, Phase 250, Phase 251, Phase 252 (terminal phase — consumes every prior phase artifact)
**Requirements**: FIND-01, FIND-02, FIND-03, FIND-04, REG-01, REG-02
**Success Criteria** (verifier checklist):
  1. `audit/FINDINGS-v32.0.md` exists in canonical v29/v30/v31 deliverable shape: executive summary with severity counts under D-08 5-bucket rubric, per-phase sections covering Phases 247-252, F-32-NN finding blocks (one per surfaced finding, each with severity / source phase / `path:line` / proposed-or-applied resolution), and the FINAL READ-only frontmatter on plan-close commit.
  2. Every F-32-NN finding is classified under D-08 (CRITICAL / HIGH / MEDIUM / LOW / INFO) with explicit severity-justification prose; severity counts in §1 reconcile to the F-32-NN block tally line by line.
  3. The KI gating section runs the D-09 3-predicate walk (accepted-design + non-exploitable + sticky) per F-32-NN candidate and emits either an updated `KNOWN-ISSUES.md` (with diff cited inline) OR an explicit Non-Promotion Ledger documenting the gating decision per row when no candidate qualifies.
  4. The Lean Regression Appendix (REG-01) spot-checks every prior v29 / v30 / v31 finding directly touched by the WIP guards or the post-v31 commits — at minimum every row referencing `_backfillGapDays`, `purchaseLevel`, `rngLockedFlag`, `lastPurchaseDay`, `dailyIdx`, or the turbo block — with verdict in {PASS, REGRESSED, SUPERSEDED} and a domain-cite per row; REG-02 lists any prior finding superseded by the new guards with structural-closure proof.
  5. Section §Milestone-Closure emits the fix-readiness signal `MILESTONE_V32_AT_HEAD_<sha>` (where `<sha>` is the post-WIP-commit HEAD if any guards / tests landed via approved commits, otherwise the at-audit-close HEAD), and a commit-readiness register names every contract / test path landed during the milestone with its review-and-approval audit trail and the user-approval commit reference.
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 247 → 248 → 249 → 250 → 251 → 252 → 253. Phases 248 / 249 / 250 / 251 / 252 are independent of each other once Phase 247 lands the delta surface; orchestrator may parallelize where the working-file model permits.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 247. Delta Extraction & Classification | v32.0 | 1/1 | Complete    | 2026-05-01 |
| 248. Backfill Idempotency Proof | v32.0 | 1/1 | Complete    | 2026-05-02 |
| 249. purchaseLevel Correctness Proof | v32.0 | 1/1 | Complete    | 2026-05-02 |
| 250. Sibling-Pattern Sweep | v32.0 | 1/1 | Complete    | 2026-05-02 |
| 251. Reproduction Tests | v32.0 | 1/1 | Complete    | 2026-05-02 |
| 252. Post-v31.0 Landed-Commit Sanity | v32.0 | 0/TBD | Not started | - |
| 253. Findings Consolidation + Lean Regression | v32.0 | 0/TBD | Not started | - |
