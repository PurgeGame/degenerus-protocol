# Phase 248: Backfill Idempotency Proof — Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Prove the new `rngWordByDay[idx + 1] == 0` guard at `contracts/modules/DegenerusGameAdvanceModule.sol:1174` (inside `rngGate`'s fresh-word branch L1165-1209) makes `_backfillGapDays` (sole call site at L1176; function body L1752-1773) execute at most once per VRF lock window across every reachable `advanceGame` re-entry path. Close conservation across the gap range (no doubled `purchaseStartDay`, no doubled coinflip credits, lock-window-scoped supply invariants for sDGNRS/DGNRS/BURNIE per REQUIREMENTS.md OUT OF SCOPE). RE_VERIFY KI EXC-02 (prevrandao fallback) and EXC-03 (gameover RNG substitution) envelopes against the new guard NON-WIDENING.

Six requirements (BFL-01..06 per REQUIREMENTS.md):

- **BFL-01** — Enumerate every code path that reaches `_backfillGapDays`; prove guard makes the call idempotent across every reachable `advanceGame` re-entry within a single VRF lock window.
- **BFL-02** — Enumerate every state write inside the guarded block (whole `if (day > idx + 1 && rngWordByDay[idx + 1] == 0)` branch L1174-1186); prove guard correctly skips repeated execution; verify `rngWordByDay[idx + 1]` is the right sentinel (no off-by-one vs `idx` or `day`).
- **BFL-03** — Adversarially construct the testnet underflow trigger (multi-day VRF stall, fresh-word path re-enters before `_unlockRng`); prove underflow impossible with the guard; produce worked numeric example.
- **BFL-04** — `dailyIdx` ↔ `rngWordByDay[idx]` ↔ `_unlockRng` invariant: prove `dailyIdx` only advances inside `_unlockRng` (sole writer at AdvanceModule:1703) AND that `rngWordByDay[idx + 1]` correctly identifies "backfill not yet run for this lock window."
- **BFL-05** — RE_VERIFY EXC-02 + EXC-03 envelopes against the backfill guard NON-WIDENING; if either widens, narrow the guard or update KNOWN-ISSUES.md per Phase 253 D-09 gating.
- **BFL-06** — Conservation proof scoped to lock window: total ETH credited to coinflip pools across gap range = expected non-doubled amount; `purchaseStartDay` increments exactly once per gap day; sDGNRS/DGNRS/BURNIE supplies invariant.

Anchor: HEAD `acd88512` (Phase 247's anchor; both WIP guards already committed inside this SHA — turbo guard L173 + backfill guard L1174). Deliverable: `audit/v32-248-BFL.md` (single file, READ-only after plan-close per D-247-22 carry-forward).

Phase 248 is a pure-proof phase. Zero `contracts/` writes, zero `test/` writes — all forge / hardhat reproduction lives in Phase 251 TST-04 per D-247-02. Finding-ID emission deferred to Phase 253 (FIND-01..04) per D-247-21 carry-forward.

</domain>

<decisions>
## Implementation Decisions

### Anchor & Deliverable
- **D-248-01 (HEAD anchor `acd88512`):** Phase 248 inherits Phase 247's anchor at HEAD `acd88512`. Both WIP guards (turbo at L173 + backfill at L1174) are already committed inside this SHA. ContractAddresses.sol working-tree changes ignored per D-247-03 carry-forward. Phase 247 Consumer Index D-247-I001..I006 = sole scope input for BFL-01..06; Phase 248 does NOT re-derive the universe from git diffs.
- **D-248-02 (single deliverable `audit/v32-248-BFL.md`):** Per ROADMAP Phase 248 success criterion 1. Mirrors v31 / v30 / v29 single-deliverable format. READ-only flip on plan-close per D-247-22 carry-forward.
- **D-248-03 (no `F-32-NN` emission — Phase 253 owns):** Phase 247 D-247-21 carry-forward. Any finding-candidate flagged in Phase 248 routes to a `Finding Candidates` subsection with `path:line` + suggested severity for Phase 253 routing. No `F-32-` IDs in this phase.
- **D-248-04 (cross-repo READ-only LIFTED at milestone level — Phase 248 is pure-proof regardless):** v32.0 lifted READ-only at the milestone but Phase 248, being pure-proof, has zero `contracts/` or `test/` writes. Writes confined to `.planning/phases/248-*/` and `audit/v32-248-*` files. KNOWN-ISSUES.md is NOT touched in Phase 248 (KI promotions are Phase 253 FIND-03 only).

### Cross-Phase Test Boundary (D-248-05 / D-248-06)
- **D-248-05 (Phase 251 owns all forge / hardhat tests):** Phase 248 is a pure-proof phase. BFL-03's "worked numeric example" is a symbolic / algebraic state-transition table — NO forge `.t.sol` or hardhat `.test.js` written by Phase 248. All test/ inventory routes to Phase 251 TST-04 per D-247-02 carry-forward. Mirrors v31 phase-244 (proof) → phase-246 (test) split.
- **D-248-06 (test-stub design hand-off to Phase 251):** Phase 248 produces a test-stub design block at the end of the deliverable (under a `## Phase 251 TST-04 Hand-Off` section): sketch of `it()` block (or `function test_*` for forge), expected pre-fix revert (panic 0x11 OR purchaseStartDay underflow), expected post-fix pass, suggested test file name (likely `test/edge/BackfillIdempotency.test.js` or `.t.sol` — Phase 251 picks final name). Phase 251 plan reads this hand-off as scope input.

### Proof Shape (D-248-07 / D-248-08)
- **D-248-07 (state-transition table for both BFL-03 and BFL-04):** Tabular grep-friendly representation. Mirrors v31 / v30 / v29 / Phase 247 tabular-no-mermaid pattern.
  - **BFL-03 worked example** — Row-per-`advanceGame` invocation across the multi-day VRF stall window. Columns: `Step | block.timestamp | day | dailyIdx | rngLockedFlag | rngRequestTime | currentWord | rngWordByDay[idx+1] | guard verdict | purchaseStartDay (post) | gapDays (post) | _backfillGapDays called?`. Pre-guard execution shows double-execution path; post-guard execution shows the `rngWordByDay[idx+1] == 0` short-circuit on re-entry. Use concrete testnet block numbers (10759449 + 10761786) as the seed.
  - **BFL-04 invariant table** — Row-per-write-site of `dailyIdx` AND `rngWordByDay[*]` across `contracts/`. Columns: `Site (file:line) | Function | Write | Guard preconditions | Holds dailyIdx-only-advances-inside-_unlockRng? | Holds rngWordByDay[idx+1]-is-correct-sentinel?`. Verdicts in {HOLDS, VIOLATES, FINDING_CANDIDATE}.
- **D-248-08 (BFL-01 single-rngGate-walk + 3-path multiplier):** One state-transition table walks the rngGate fresh-word branch reachability (the "inner" proof — path-invariant). A separate single-row attestation table notes that all 3 advanceGame entry paths from Phase 247 D-247-X027..X029 (DegenerusGame.sol:289 delegatecall + DegenerusVault.sol:503 cross-contract + StakedDegenerusStonk.sol:355 cross-contract) funnel into the same top-level dispatcher and therefore share the rngGate-side reachability surface. Avoids 3× duplication of the inner proof; rngGate's branch selection is purely on `rngWordByDay[day]` / `currentWord` / `rngRequestTime`, none of which the 3 entry paths set differently.

### Enumeration Scope (D-248-09 / D-248-10)
- **D-248-09 (BFL-02 = whole guarded fresh-word branch):** Enumeration scope is every state write the guard at L1174 protects from re-execution — NOT just `_backfillGapDays` body (L1752-1773). Specifically the entire `if (day > idx + 1 && rngWordByDay[idx + 1] == 0)` block (L1174-1186):
  - `_backfillGapDays` body writes: `rngWordByDay[gapDay]` at L1766, `coinflip.processCoinflipPayouts(...)` external call at L1767, `DailyRngApplied(...)` event at L1768.
  - Sibling writes inside the same guarded block: `_backfillOrphanedLootboxIndices(currentWord)` at L1180 (mutates `lootboxRngWordByIndex[i]` + emits `LootboxRngApplied`), `purchaseStartDay += gapCount` at L1184, `gapDays = gapCount` at L1185.
  - Rationale: `purchaseStartDay += gapCount` at L1184 is the literal testnet bug trigger (REQUIREMENTS.md trigger context: "doubling purchaseStartDay"), and it sits OUTSIDE `_backfillGapDays`. Restricting BFL-02 to the function body would miss the load-bearing write the guard protects.
  - Always-executed writes inside the broader fresh-word branch (`_applyDailyRng`, `quests.rollDailyQuest`, `sdgnrs.resolveRedemptionPeriod`, `_finalizeLootboxRng`) are OUT of BFL-02 scope — they run on every `rngGate` invocation regardless of the guard, and are correct by virtue of the always-checked early-return at L1160 (`if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0)`).
- **D-248-10 (External-call boundary — boundary record + behavioral cite):** External calls inside the guarded block (`coinflip.processCoinflipPayouts`, `_backfillOrphanedLootboxIndices` is internal but emits + calls into BurnieCoinflip transitively, `sdgnrs.resolveRedemptionPeriod` runs outside the guard so out-of-scope per D-248-09) are recorded as single boundary write rows with a one-line semantic cite (e.g., "credits ETH coinflip pool / debits per-day reservation per `contracts/BurnieCoinflip.sol:LINE`"). BFL-06 conservation walks into BurnieCoinflip storage writes only enough to verify per-call ETH-pool credit math (1 row per call × N gap days = expected non-doubled total). Avoids re-auditing BurnieCoinflip itself — v25/v29/v30/v31 already proved coinflip-pool conservation; v32.0 OUT OF SCOPE confirms "ETH/BURNIE/sDGNRS/DGNRS conservation on non-delta surfaces" is not re-litigated.

### Plan Topology + Row-ID + Verdict Scheme (Default-Inherited)
- **D-248-11 (single-plan multi-task — Phase 247 / 246 / 242 carry-forward):** Default-inherited from v32 Phase 247 (`247-01-PLAN.md` 5-task structure) and v30 Phase 242 / v31 Phase 246 single-plan multi-task atomic-commit pattern. Suggested task ordering (planner final call):
  1. **Task 1 (BFL-01 + BFL-02 enumeration)** — rngGate fresh-word branch state-transition table + 3-path multiplier attestation + BFL-02 state-write inventory.
  2. **Task 2 (BFL-03 + BFL-04 invariant proof)** — multi-day VRF stall worked example (testnet block 10759449 + 10761786 seed) + dailyIdx ↔ rngWordByDay invariant table.
  3. **Task 3 (BFL-05 EXC envelope RE_VERIFY)** — dual-carrier attestation rows for EXC-02 + EXC-03 against the new guard.
  4. **Task 4 (BFL-06 conservation proof + Phase 251 hand-off)** — lock-window conservation algebra (purchaseStartDay arithmetic + per-gap-day coinflip credit total) + test-stub design hand-off block.
  5. **Task 5 (Final assembly + READ-only flip)** — assemble `audit/v32-248-BFL.md` 7-section format; mark FINAL READ-only on plan-close commit.
  Each task lands its own atomic commit per Phase 247 D-247-14 atomic-task-commit pattern.
- **D-248-12 (V-row scheme with 3-bucket verdict):** Inherit v31 Phase 244 V-row pattern. Row IDs: `BFL-NN-VMM` (REQ-anchored, monotonic-within-REQ; e.g., `BFL-01-V01`, `BFL-01-V02`, ..., `BFL-02-V01`, ...). Verdicts in 3-bucket {SAFE, EXCEPTION, FINDING_CANDIDATE} — broader than ROADMAP success criterion 1's 2-bucket {SAFE, FINDING_CANDIDATE} so EXC-02/EXC-03 envelope re-verify rows can land their own verdict bucket without forcing into FINDING_CANDIDATE. Per CONTEXT.md D-247-10 column shape: `Row ID | Site (file:line) | Description | Pre-state | Post-state | Verdict | Evidence Cite`.
- **D-248-13 (EXC-02/EXC-03 dual-carrier attestation — v31 carry-forward):** Inherit v31 SDR-08-V01 / GOE-01-V01 / GOE-04-V02 dual-carrier pattern. BFL-05 emits separate per-consumer attestation rows for each EXC envelope:
  - EXC-02 (prevrandao fallback at `_getHistoricalRngFallback` AdvanceModule:1301): 1 carrier row attesting non-widening against new guard (rngGate is the only v32 delta touching the EXC-02 trigger surface).
  - EXC-03 (gameover RNG substitution at `_gameOverEntropy` AdvanceModule:1222-1246): 1 carrier row attesting non-widening (rngGate's backfill guard does not change the gameover RNG substitution envelope).
  Each carrier row carries `Carrier ID | EXC ID | Trigger condition (path:line) | Pre-guard envelope | Post-guard envelope | Widening? (bool) | Evidence cite`. Default verdict NON-WIDENING; if either widens, route to Phase 253 D-09 3-predicate gating walk and update KNOWN-ISSUES.md.

### Methodology — Phase 247 Carry-Forward
- **D-248-14 (scope-guard deferral rule — D-247-22 carry-forward):** If Phase 248 finds a changed function / state-var / event / interface method / call site NOT in Phase 247's catalog, record a scope-guard deferral in this phase's SUMMARY.md (when the plan closes); Phase 247 output (`audit/v32-247-DELTA-SURFACE.md`) is NOT re-edited. Gaps become Phase 253 finding candidates.
- **D-248-15 (grep-reproducibility for path enumeration):** Every BFL-01 reachability claim + BFL-04 invariant claim cites the exact `grep` command used to find every write site / call site. Portable POSIX syntax (no GNU `-P` / Perl regex).
- **D-248-16 (testnet block reproduction seed):** BFL-03 worked example uses testnet block numbers 10759449 + 10761786 as the concrete seed (per REQUIREMENTS.md trigger context + Phase 247 §1.6 advanceGame turbo-guard INFO bullet). Walk through pre-fix sequence showing `purchaseStartDay` doubling on second `advanceGame` call across the multi-day stall, then walk through post-fix sequence showing the `rngWordByDay[idx + 1] == 0` short-circuit on re-entry.

### Claude's Discretion
- Final section ordering within `audit/v32-248-BFL.md` (planner picks readable shape — likely 7 sections matching ROADMAP success criteria + Phase 251 hand-off appendix).
- Whether the BFL-04 invariant table uses one row per write site or groups same-function multi-write sites under a single row.
- Whether Task 4's lock-window conservation algebra is presented inline in the per-REQ section or as a small companion appendix.
- Whether the test-stub design hand-off names the file `BackfillIdempotency.test.js` or extends `test/edge/LastPurchaseDayRace.test.js` with a new `it()` block — Phase 251 final call.
- Whether finding-candidate severity is suggested in Phase 248's `Finding Candidates` subsection (recommended INFO baseline per D-247-21 spirit) or left blank for Phase 253 D-08 5-bucket rubric.
- Per-REQ section header naming (e.g., `## BFL-01 — ...` vs `## Section 1 — BFL-01`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v32.0 requirements; BFL-01..06 (this phase) + 4 accepted RNG exceptions + OUT OF SCOPE clauses (especially "BFL-06 conservation proof is scoped to the lock window only" + "Re-litigating the 4 accepted KNOWN-ISSUES RNG exceptions — acceptance NOT re-litigated; envelope re-verify only (BFL-05)").
- `.planning/ROADMAP.md` — Phase 248 success criteria (5 items); deliverable target `audit/v32-248-BFL.md`; per-criterion verdict-row guidance.
- `.planning/PROJECT.md` — Current Milestone section lists the bug context + READ-only-LIFTED write policy.

### Phase 247 scope input (MUST read — sole scope input per Phase 247 success criterion 4)
- `audit/v32-247-DELTA-SURFACE.md` — FINAL READ-only at HEAD `acd88512`. Specifically Section 1.4 (acd88512 commit changelog rows D-247-C011 + C012), Section 1.6 finding-candidate bullets for `advanceGame` turbo guard L173 + `rngGate` backfill guard L1173, Section 2 classification rows D-247-F010 + F011 (both MODIFIED_LOGIC), Section 3 call-site rows D-247-X027..X030 (3 advanceGame entry paths + 1 rngGate caller), Section 6 Consumer Index rows D-247-I001..I006 (BFL-01..06 row scope mapping).
- `.planning/phases/247-delta-extraction-classification/247-CONTEXT.md` — D-247-21 (no F-32-NN emission), D-247-22 (READ-only after plan-close), D-247-02 (test/-out-of-scope routes to Phase 251) — all carried forward into Phase 248.
- `.planning/phases/247-delta-extraction-classification/247-01-PLAN.md` — single-plan multi-task atomic-commit precedent for D-248-11 plan topology.
- `.planning/phases/247-delta-extraction-classification/247-01-SUMMARY.md` — Phase 247 closure verification.

### In-scope code (HEAD acd88512)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — primary audit target. Specifically:
  - `rngGate` function at L1152-1224 (the changed function); guarded fresh-word branch at L1165-1209; backfill guard at L1174 (`if (day > idx + 1 && rngWordByDay[idx + 1] == 0)`).
  - `_backfillGapDays` function at L1752-1773 (the function whose idempotency is being proven).
  - `_unlockRng` function at L1702-1710 (sole writer of `dailyIdx` per BFL-04 invariant; the dependency the guard relies on).
  - `_applyDailyRng` function at L1801-1817 (mutates `rngWordCurrent` + `rngWordByDay[day]`; called inside the always-executed portion of the fresh-word branch).
  - `_backfillOrphanedLootboxIndices` function at L1779-1798 (sibling write inside the guarded block).
  - `advanceGame` function at L160-488 (entry point; reaches `rngGate` at L292; the 3 entry paths from Phase 247 D-247-X027..X029 all funnel here).
- `contracts/BurnieCoinflip.sol` — `processCoinflipPayouts` callee for BFL-02 boundary record + BFL-06 conservation per-call ETH-pool credit math (read enough to cite the credit math, do NOT re-audit per OUT OF SCOPE).

### KI envelopes (MUST read for BFL-05)
- `KNOWN-ISSUES.md` — entries for EXC-02 (Gameover prevrandao fallback) + EXC-03 (Gameover RNG substitution for mid-cycle write-buffer tickets). BFL-05 RE_VERIFIES both envelopes against the new guard NON-WIDENING. Acceptance rationale NOT re-litigated.

### Methodology precedents (carry-forward, not re-litigated)
- `.planning/milestones/v31.0-phases/244-per-commit-adversarial-audit/` — V-row pattern + 3-bucket verdict precedent (D-248-12). Specifically the per-REQ Vnn row format with {SAFE, EXCEPTION, FINDING_CANDIDATE} verdicts.
- `audit/v31-244-EVT.md` / `v31-244-RNG.md` / `v31-244-QST.md` / `v31-244-GOX.md` — direct format precedent for V-row tables in `audit/v32-248-BFL.md`.
- `audit/v31-245-SDR.md` / `v31-245-GOE.md` — dual-carrier attestation precedent for D-248-13 EXC envelope RE_VERIFY (specifically SDR-08-V01 / GOE-01-V01 / GOE-04-V02 carrier rows).
- `audit/v31-246-FINDINGS.md` — single-plan multi-task pattern reference; no findings IDs in mid-milestone phases (D-247-21 / D-248-03).
- `.planning/milestones/v30.0-phases/242-findings-consolidation/` — single-plan multi-task pattern reference (D-248-11).

### Prior audit outputs (light cross-cite for BFL-04 + BFL-05)
- `audit/FINDINGS-v31.0.md` — 33 V-rows / 142 verdicts; lean regression appendix. BFL-04 invariant table cross-cites any v31 row whose underlying function is `dailyIdx` / `rngWordByDay` / `_unlockRng` writer.
- `audit/FINDINGS-v30.0.md` — VRF consumer determinism audit; per-consumer freeze proofs. BFL-05 EXC-02 carrier row cross-cites v30 §238 freeze-proof rows on `_getHistoricalRngFallback`.
- `audit/FINDINGS-v29.0.md` — F-29-04 gameover RNG substitution finding (the EXC-03 codification source).
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; BFL-04 invariant table can cross-cite the existing dailyIdx / rngWordByDay write inventory.

### Project feedback rules (apply across all plans in Phase 248)
- `memory/feedback_no_contract_commits.md` — explicit per-commit user approval required for any `contracts/` or `test/` write. Phase 248 has zero such writes by D-248-04 / D-248-05 but the rule binds if any agent-level surprise emerges.
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source.
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED (BFL deliverable is allowed to describe pre-vs-post-guard state for proof purposes — that's the entire point — but rationale prose must read as descriptive, not as patch-history narration).
- `memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time. Relevant to BFL-05 EXC-02/EXC-03 envelope re-verify.
- `memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Relevant to BFL-04 invariant proof (`dailyIdx` mutation window vs VRF lock window).
- `memory/feedback_skip_research_test_phases.md` — skip research for obvious/mechanical phases. Phase 248 is a proof phase grounded in Phase 247's catalog + REQUIREMENTS.md trigger context — research is unlikely to add value beyond the existing canonical refs.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 247 Section 6 Consumer Index (D-247-I001..I006)** — directly defines BFL-01..06 row scope. Phase 248 plan does NOT re-derive the universe.
- **v31 Phase 244 V-row table format** — direct shape reuse for `audit/v32-248-BFL.md`'s per-REQ sections (BFL-NN-VMM rows with 3-bucket verdicts).
- **v31 Phase 245 dual-carrier attestation rows (SDR-08-V01 / GOE-01-V01 / GOE-04-V02)** — direct shape reuse for D-248-13 BFL-05 EXC envelope RE_VERIFY carrier rows.
- **Phase 247 single-plan multi-task atomic-commit pattern (D-247-13 / D-247-14)** — direct reuse for D-248-11 plan topology.
- **Existing `audit/v31-243-DELTA-SURFACE.md` 7-section single-file format** — rough format precedent for `audit/v32-248-BFL.md` (likely fewer sections — per-REQ structure + Finding Candidates + Phase 251 hand-off appendix).
- **`KNOWN-ISSUES.md` EXC-02 + EXC-03 entries** — pre-locked acceptance rationales; Phase 248 only re-verifies envelope-non-widening, never re-litigates acceptance.

### Established Patterns
- **State-transition table for sequential proofs** — pattern carry-forward from v31 Phase 244 RNG section's Vnn rows (per-call pre-state / post-state columns).
- **3-bucket verdict {SAFE, EXCEPTION, FINDING_CANDIDATE}** — v31 Phase 244 / 245 carry-forward.
- **Boundary-record + behavioral-cite for external calls** — v25 / v29 / v31 ETH-flow / RNG-consumer audits use the same pattern (cite the callee's storage write at the file:line level, do not walk the callee's body unless the audit target spans both contracts).
- **Lock-window-scoped conservation** — v31 BFL-equivalent locks; v25 / v29 conservation proofs scope to operation boundaries.
- **No F-NN-NN emission in proof / catalog phases** — v29 Phase 230 / v30 Phase 237 / v31 Phase 243 / v32 Phase 247 all defer ID emission to terminal findings-consolidation phase.

### Integration Points
- **Phase 247 → Phase 248** — `audit/v32-247-DELTA-SURFACE.md` Section 6 D-247-I001..I006 maps BFL-01..06 to specific Phase 247 row IDs. Phase 248 plan opens by citing these rows and then walks the proof inward.
- **Phase 248 → Phase 251** — Phase 248 deliverable's `## Phase 251 TST-04 Hand-Off` section provides test-stub design (sketch + expected pre-fix / post-fix behavior + suggested file name). Phase 251 plan reads this hand-off as scope input for TST-04.
- **Phase 248 → Phase 252** — POST31-02 RE_VERIFIES that the new turbo guard composes with `8bdeabc2`'s productive-pause early-return; BFL-04 invariant table's `_unlockRng` write-site row should cross-cite the productive-pause path so Phase 252 inherits the composition target.
- **Phase 248 → Phase 253** — Any BFL-NN-Vmm row classified `FINDING_CANDIDATE` routes into Phase 253 FIND-01 finding-block emission (D-248-03). KI envelope re-verify NON-WIDENING attestations route to Phase 253 D-09 gating walk only if any envelope widens.
- **Phase 248 → Phase 250** — SIB-01..05 sibling-pattern sweep uses the BFL-04 invariant table as one input; if Phase 248 surfaces additional `dailyIdx` / `rngWordByDay` write sites Phase 247 missed, those route to Phase 250 SIB-01 sweep scope per D-248-14 scope-guard deferral.

### Git Infrastructure (verified 2026-05-01)
- HEAD anchor `acd88512`; current git HEAD `415d421d` (Phase 247 closure docs commits above `acd88512` touch only `.planning/`).
- Working tree at start of Phase 248 execution: `contracts/ContractAddresses.sol` modified (deploy regen, ignored per D-247-03 carry-forward), `test/edge/LastPurchaseDayRace.test.js` untracked (Phase 251 scope per D-247-02).
- No `git diff` runs in Phase 248 plan — Phase 247 catalog is the sole scope input per Phase 247 success criterion 4. Plan opens with a sanity gate `git rev-parse acd88512` to confirm anchor presence, then walks Phase 247's row IDs inward.

</code_context>

<specifics>
## Specific Ideas

- **Use testnet block numbers 10759449 + 10761786 as BFL-03 worked example seed** — concrete, traceable, ties back to the bug report context in REQUIREMENTS.md trigger section. Pre-fix walk shows the second-day re-entry doubling `purchaseStartDay`; post-fix walk shows `rngWordByDay[idx + 1] == 0` short-circuiting before any state mutation.
- **BFL-04 invariant table row format suggestion**: `Site (file:line) | Function | State-var written | Write expression | Guard preconditions | Holds 'dailyIdx only mutates inside _unlockRng'? | Holds 'rngWordByDay[idx+1] is correct sentinel'? | Verdict`. Use grep to find every site: `grep -rn '\bdailyIdx\s*=' contracts/` + `grep -rn '\brngWordByDay\[' contracts/`.
- **BFL-02 always-executed-vs-guarded write distinction** — BFL-02 deliverable should explicitly call out the always-executed writes (`_applyDailyRng`, `quests.rollDailyQuest`, `sdgnrs.resolveRedemptionPeriod`, `_finalizeLootboxRng`) as "OUT-of-scope-by-construction" rows so a reviewer can see the boundary was deliberate.
- **D-248-13 dual-carrier table column suggestion**: `Carrier ID | EXC ID | Trigger condition (path:line) | Pre-guard envelope (one-line) | Post-guard envelope (one-line) | Widening? | Evidence cite (KI text + Phase 247 row)`. Mirror v31 SDR-08 / GOE-01 / GOE-04 row shape.
- **BFL-06 conservation algebra suggestion** — single inline algebraic block: pre-fix: `purchaseStartDay_after = purchaseStartDay_before + 2*gapCount` (doubled), post-fix: `purchaseStartDay_after = purchaseStartDay_before + gapCount` (single application). For ETH coinflip: pre-fix: `pool_credit = 2 * sum_{d=startDay..endDay-1}(processCoinflipPayouts ETH credit on day d)`, post-fix: `pool_credit = sum_{d=startDay..endDay-1}(...)` once.
- **Phase 251 hand-off block format suggestion** — `## Phase 251 TST-04 Hand-Off` section at the bottom of the deliverable. Three sub-blocks:
  1. **Symbolic spec** — pre-state setup (lock window crosses ≥2 wall-clock days; fresh-word path re-enters before `_unlockRng`); call sequence to trigger; expected pre-fix revert kind (panic 0x11 OR purchaseStartDay underflow) and revert site (`path:line`); expected post-fix pass behavior.
  2. **Suggested test file** — `test/edge/BackfillIdempotency.test.js` (hardhat) OR extend `test/edge/LastPurchaseDayRace.test.js` with a new `it()` block. Phase 251 final call.
  3. **Phase 247 row anchors** — list the Phase 247 catalog rows the test exercises (D-247-C012 + D-247-F011 + D-247-X030).

</specifics>

<deferred>
## Deferred Ideas

- **Forge fuzz invariant test for the dailyIdx ↔ rngWordByDay bijection** — could augment Phase 251's hardhat reproduction with a forge `invariant_*` test asserting `rngWordByDay[idx + 1] == 0` whenever `dailyIdx == idx`. Out of Phase 248 scope (pure-proof phase per D-248-05); flag for Phase 251 TST-04 if planner judges value.
- **Cross-milestone delta chain audit for `_backfillGapDays`** — `_backfillGapDays` was first introduced in v3.6 (Phases 59-62 VRF-stall-resilience). Phase 247 §1.7 confirms `acd88512` is the first delta against the function since then. A retroactive audit chain would be informative but is OUT of v32.0 scope (REQUIREMENTS.md Out of Scope: "ETH/BURNIE/sDGNRS/DGNRS conservation on non-delta surfaces — covered in v25.0/v29.0/v30.0/v31.0; not re-proven globally").
- **Automated CI gate for VRF lock-window invariants** — wiring the `dailyIdx ↔ rngWordByDay` bijection into a CI check that runs on every PR. Out of v32.0 scope; flag as future-milestone candidate (mirrored from Phase 247 deferred §"Automated CI gate on deltas").
- **Phase 250 SIB-01 sibling sweep for other backfill-class races** — if BFL-04 invariant table surfaces a `dailyIdx` / `rngWordByDay` write site that has the same shape as the testnet bug, Phase 250 SIB-01 owns the sibling sweep. Phase 248 records the candidate via the `Finding Candidates` subsection and routes via D-248-14 scope-guard deferral.
- **Storage-layout add-row for any new state-var introduced by future backfill-guard hardening** — Phase 247 §5 confirms zero storage-layout delta in v32.0 in-scope SHAs. If planner-added hardening adds a new state-var (none expected), it routes to Phase 252 POST31-01 storage-layout re-verify.

</deferred>

---

*Phase: 248-backfill-idempotency-proof*
*Context gathered: 2026-05-01*
