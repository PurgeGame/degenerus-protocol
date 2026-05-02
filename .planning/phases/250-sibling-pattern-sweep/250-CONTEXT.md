# Phase 250: Sibling-Pattern Sweep — Context

**Gathered:** 2026-05-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Hunt other turbo-class and backfill-class races across `DegenerusGameAdvanceModule.sol` and every delegating module — every interaction between `rngLockedFlag` and one of {`lastPurchaseDay`, `jackpotPhaseFlag`, `dailyIdx`, `level`, `purchaseStartDay`, `rngWordByDay[*]`, `phaseTransitionActive`} is enumerated and classified, so any latent sibling bug surfaces as an explicit FINDING_CANDIDATE before consolidation. Five requirements (SIB-01..05 per REQUIREMENTS.md):

- **SIB-01** — Enumerate every interaction in `DegenerusGameAdvanceModule.sol` where `rngLockedFlag` is read or written alongside one of the 7 partner state-vars (one `SIB-01-Vnn` row per interaction) with `path:line` evidence and a grep-reproducible discovery recipe. Scout: 44 raw hits across the 7 partners in AdvanceModule.
- **SIB-02** — Classify every SIB-01 row under the {turbo-class, backfill-class, ORTHOGONAL_PROVEN} taxonomy with explicit reasoning per row; ORTHOGONAL_PROVEN rows carry an isolation argument equivalent in form to v30 Phase 239's lootbox-index-advance / `phaseTransitionActive` proofs.
- **SIB-03** — Audit each delegating module (Mint, Jackpot, Whale, Lootbox, Degenerette, Boon, Decimator, GameOver) for the same patterns reading the same state, with at least one row per module (or a documented NEGATIVE-scope verdict). Scout: 13 hits across 6 modules; 3 modules (Jackpot, Boon, Degenerette) have zero hits → mandatory NEGATIVE-scope rows. MintModule:923 pre-flagged by Phase 249 D-249-01 as the live FINDING_CANDIDATE seed.
- **SIB-04** — Cross-check the 4 post-v31.0 landed commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) for sibling patterns; `8bdeabc2` (productive-pause liveness) called out explicitly as the closest sibling shape and verdict-justified.
- **SIB-05** — Document any new bug found with reproducible trigger sequence, severity classification under the D-08 5-bucket rubric, and an explicit `awaiting-approval` proposed-fix block per `feedback_no_contract_commits.md`. Zero new bugs → explicit zero-state attestation. No contract / test edits land without prior recorded user approval.

Anchor: HEAD `acd88512` (Phase 247's anchor — both WIP guards already committed inside this SHA: turbo guard at AdvanceModule:173 + backfill guard at AdvanceModule:1174). Deliverable: `audit/v32-250-SIB.md` (single file, READ-only after plan-close per D-247-22 / D-248-02 / D-249-CF-02 carry-forward).

Phase 250 is a pure-proof phase. Zero `contracts/` writes, zero `test/` writes — all forge / hardhat reproduction lives in Phase 251 TST-01..04 per D-247-02 / D-248-05 / D-249-CF-05 carry-forward. Finding-ID emission deferred to Phase 253 (FIND-01..04) per D-247-21 / D-248-03 / D-249-CF-03 carry-forward; Phase 250 emits FINDING_CANDIDATE rows only.

</domain>

<decisions>
## Implementation Decisions

### Anchor & Deliverable (Carry-Forward from Phase 247 / 248 / 249)

- **D-250-CF-01 (HEAD anchor `acd88512`):** Phase 250 inherits Phase 247/248/249's anchor. Both WIP guards (turbo at L173 + backfill at L1174) committed inside this SHA. `contracts/ContractAddresses.sol` working-tree changes ignored per D-247-03 carry-forward. Phase 247 catalog (Section 2 classification + Section 3 call-site index + Section 6 Consumer Index) = primary scope input for SIB-01..04.
- **D-250-CF-02 (single deliverable `audit/v32-250-SIB.md`):** Per ROADMAP Phase 250 success criteria. READ-only flip on plan-close per D-247-22 / D-248-02 / D-249-CF-02 carry-forward. Single-file 5-section format mirrors Phase 247/248/249.
- **D-250-CF-03 (no `F-32-NN` emission — Phase 253 owns):** Carry-forward D-247-21 / D-248-03 / D-249-CF-03. SIB-05 emits `SIB-05-Vnn` finding-candidate rows with `path:line`, suggested severity (recommended INFO baseline), and proposed-fix sketch (`awaiting-approval` block); Phase 253 FIND-01/02 routes them to F-32-NN finding blocks with final D-08 severity.
- **D-250-CF-04 (pure-proof phase; zero contract/test writes):** Carry-forward D-249-CF-04. v32.0 lifted READ-only at the milestone but Phase 250's writes are confined to `.planning/phases/250-*/` and `audit/v32-250-*` files. KNOWN-ISSUES.md is NOT touched in Phase 250 (KI promotions are Phase 253 FIND-03 only). Any proposed fix for a SIB-05 finding-candidate is recorded as an `awaiting-approval` block, NOT autonomously committed.
- **D-250-CF-05 (V-row scheme + 3-bucket verdict for SIB-01/SIB-03/SIB-04/SIB-05):** Inherit D-249-CF-06 V-row pattern. Row IDs: `SIB-NN-VMM` (REQ-anchored, monotonic-within-REQ; e.g., `SIB-01-V01`, `SIB-03-V01`, `SIB-05-V01`). SIB-01/SIB-03/SIB-04 verdicts in 3-bucket {SAFE, EXCEPTION, FINDING_CANDIDATE}; SIB-05 rows carry suggested severity instead. SIB-02 verdict bucket is the dedicated 3-class taxonomy {turbo-class, backfill-class, ORTHOGONAL_PROVEN} per ROADMAP success criterion 2 — see D-250-08.
- **D-250-CF-06 (single-plan multi-task atomic-commit):** Carry-forward D-247-12 / D-248-11 / D-249-CF-07. Suggested 4-task ordering (planner final call) — see D-250-PLN-01.
- **D-250-CF-07 (scope-guard deferral rule):** Carry-forward D-247-22 / D-248-14 / D-249-CF-08. If Phase 250 finds a changed function / state-var / event / interface method / call site NOT in Phase 247's catalog, record a scope-guard deferral in this phase's SUMMARY.md (when the plan closes); Phase 247 output is NOT re-edited. Gaps become Phase 253 finding candidates.
- **D-250-CF-08 (grep-reproducibility for path enumeration):** Carry-forward D-247-19 / D-248-15 / D-249-CF-09. Every SIB-01 / SIB-03 enumeration row cites the exact `grep` command used to find that interaction. Portable POSIX syntax (no GNU `-P` / Perl regex). Section 1's discovery recipe block lists the master grep set.
- **D-250-CF-09 (`feedback_no_contract_commits.md` audit trail):** Phase 250 has zero proposed contract/test writes by D-250-CF-04. If SIB-05 surfaces a new bug requiring a fix, the proposed fix is recorded in an `awaiting-approval` block with `path:line` + diff sketch + severity rationale — never autonomously committed. Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change for any executor agent.

### SIB-01 Enumeration Scope (D-250-01 / D-250-02 / D-250-03)

- **D-250-01 (state-var pair sweep — `rngLockedFlag` × 7 partners):** SIB-01 enumerates every site in `DegenerusGameAdvanceModule.sol` where `rngLockedFlag` is read or written and one of {`lastPurchaseDay`, `jackpotPhaseFlag`, `dailyIdx`, `level`, `purchaseStartDay`, `rngWordByDay[*]`, `phaseTransitionActive`} is read or written within the same control-flow span (same function, same branch, or sequential statements with no intervening write that breaks the dependency). 7 master grep recipes (one per partner) form the discovery layer; per-function context narrows from raw-hit count (44) to interaction rows. Per `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md`: every row touching a VRF-request → VRF-fulfillment span carries an explicit "what player-controllable state can change in this window?" annotation.
- **D-250-02 (column shape — 8-col interaction row):** Inherit D-247-10 / D-248-12 / D-249-CF-06 base + add interaction-specific columns:
  ```
  Row ID | Site (file:line) | Function | rngLockedFlag op {read/write} | Partner state-var | Partner op {read/write} | Same-branch span? | Verdict {SAFE, EXCEPTION, FINDING_CANDIDATE} | Evidence cite
  ```
  Evidence cite carries the grep recipe AND the inline reasoning sentence. Same-branch span column distinguishes co-reads inside one `if` body vs. sequential reads across branches (the latter rarely qualify as race-shape interactions but are tabled for completeness).
- **D-250-03 (pre-seeded interactions — turbo guard L173 + backfill guard L1174):** Two SIB-01 rows are pre-seeded as the v32.0 fix anchors:
  - `SIB-01-V01` — AdvanceModule:173 turbo guard `!rngLockedFlag && !lastPurchaseDay && !inJackpot` reads `rngLockedFlag` + `lastPurchaseDay` + `jackpotPhaseFlag` + `phaseTransitionActive`-equivalent in one expression. Verdict SAFE-via-PLV-03 (the fix). Cross-cite Phase 249 PLV-03 ternary unreachable proof.
  - `SIB-01-V02` — AdvanceModule:1174 backfill guard `rngWordByDay[idx + 1] == 0` reads `rngWordByDay[*]` while the surrounding `_backfillGapDays` body reads `rngLockedFlag` (via the call-site at L1176 inside `rngGate`'s fresh-word branch). Verdict SAFE-via-BFL-02 (the fix). Cross-cite Phase 248 BFL-02 guard-evaluation evidence.

### SIB-02 Classification Taxonomy (D-250-04 / D-250-05 / D-250-06)

- **D-250-04 (strict 3-bucket taxonomy {turbo-class, backfill-class, ORTHOGONAL_PROVEN}):** Per ROADMAP success criterion 2. No "AMBIGUOUS_FLAG" overflow bucket — every SIB-01 row classifies into exactly one of the three. If a row resists classification, treat as FINDING_CANDIDATE in SIB-01 (verdict column) and route to SIB-05 with `awaiting-approval` proposed-fix or proposed-investigation block.
- **D-250-05 (turbo-class definition):** A SIB-01 interaction is **turbo-class** iff it satisfies all three:
  1. control flow takes one branch under one flag combination but a sibling branch could fire under a different combination,
  2. the second branch's preconditions are not symmetric to the first's, AND
  3. there exists a `(flagA, flagB)` cell where the branching predicate's intent (per code-comment / function-name semantics) is violated.
  The turbo guard fix at L173 is the canonical example: turbo block intended only when `!rngLockedFlag` AND `!lastPurchaseDay`, but pre-fix could fire under `(rngLockedFlag = T, lastPurchaseDay = F)` because `rngLockedFlag` was not in the guard.
- **D-250-06 (backfill-class definition):** A SIB-01 interaction is **backfill-class** iff it satisfies all three:
  1. a state write is intended to execute idempotently (at most once),
  2. the index-advance / sentinel-clear that gates re-entry is in a different state-var than the one being written, AND
  3. the gap between write and gate-clear admits a re-entry under the right `(flag, state)` combination.
  The backfill guard fix at L1174 is the canonical example: `_backfillGapDays` writes were intended once-per-VRF-lock-window, but `rngLockedFlag` cleared before `rngWordByDay[idx + 1]` was populated, admitting double-execution.
- **D-250-07 (ORTHOGONAL_PROVEN isolation argument shape):** Each ORTHOGONAL_PROVEN row carries an isolation argument equivalent in form to the v30 Phase 239 lootbox-index-advance / `phaseTransitionActive` proofs:
  - **Form 1 (no shared write boundary):** "rngLockedFlag is read at L<X>, partner state-var is written at L<Y> in a different function on a different call path; no caller composes the two reads into a single execution."
  - **Form 2 (sequential ordering enforced):** "rngLockedFlag write at L<X> precedes partner read at L<Y> by `n` statements with no intervening control flow that could re-order; both states are observed under the same monotonic invariant."
  - **Form 3 (mutex-equivalent):** "rngLockedFlag = T ⇒ <invariant> holds at the partner read site; the invariant is enforced by <named gate> upstream."
  Each ORTHOGONAL_PROVEN row picks one form and cites the upstream invariant by name (carry-forward INV-PLV-A-NN / INV-PLV-B-NN / INV-PLV-C-NN scheme from D-249-05 if applicable).

### SIB-03 Module Audit Depth (D-250-08 / D-250-09 / D-250-10 / D-250-11)

- **D-250-08 (same-shape only filter):** Per discussion. SIB-03 enumerates ONLY co-reads where a flag (`rngLockedFlag` / `jackpotPhaseFlag` / `lastPurchaseDay` / `phaseTransitionActive`) is read alongside a counter (`level` / `dailyIdx` / `purchaseStartDay` / `rngWordByDay[*]`) at the same call site — the structural shape that produced the two known v32.0 bugs. Skips legitimate single-state reads (e.g., MintModule reading `level` for pricing without a flag co-read). Tractable scope: 13 raw hits across 6 modules → likely 3-6 same-shape rows after filtering, plus the MintModule:923 pre-flagged ternary.
- **D-250-09 (NEGATIVE-scope rows: one-line grep cite per zero-hit module):** Per discussion. Modules with zero hits on the 7 partner state-vars (Jackpot, Boon, Degenerette per scout) get one row each:
  ```
  Module | NEGATIVE | grep -nE '(rngLockedFlag|lastPurchaseDay|jackpotPhaseFlag|dailyIdx|level|purchaseStartDay|rngWordByDay|phaseTransitionActive)' contracts/modules/<Module>.sol → 0 matches | SAFE-by-vacuity
  ```
  Reproducible, minimal, satisfies ROADMAP criterion 3 ("at least one row per module or a documented NEGATIVE-scope verdict").
- **D-250-10 (MintModule:923 ownership — cross-cite + classify + finding-candidate):** Per discussion. Phase 249 PLV-01 already wrote the reachability proof for MintModule:923 (`uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;`). Phase 250 SIB-03 emits ONE row pointing at the Phase 249 PLV-01 row by ID:
  ```
  SIB-03-Vnn | MintModule.sol:923 | bafTransfer | cachedJpFlag (read) | cachedLevel (read) | turbo-class | FINDING_CANDIDATE | Cross-cite Phase 249 PLV-01 row <ID> + PLV-01-V<MM>; same ternary shape as AdvanceModule:185 WITHOUT `!rngLockedFlag` guard analog
  ```
  If Phase 249's PLV-01 row landed FINDING_CANDIDATE (i.e., the `(cachedJpFlag = T ∧ cachedLevel = 0)` cell is REACHABLE), emit one SIB-05-Vnn row with `awaiting-approval` proposed-fix block (see D-250-15). If Phase 249's row landed SAFE (cell UNREACHABLE), emit ORTHOGONAL_PROVEN under SIB-02 with the upstream invariant cite. No re-derivation of reachability.
- **D-250-11 (Phase 249 PLV-01 cross-module rows beyond Mint:923 — cross-cite by row ID):** Per discussion. Each Phase 249 PLV-01 cross-module row (Whale:841, Lootbox:532, BurnieCoinflip:578/1035, AdvanceModule helpers L734/L1097/L1504) gets one SIB-03 row pointing at its PLV-01 row ID + SIB-02 classification verdict. Most are passthrough/parameter shapes that classify ORTHOGONAL_PROVEN under SIB-02 D-250-07 Form 2 (sequential ordering enforced — caller binds `purchaseLevel` upstream and passes by parameter, no flag-vs-counter co-read at the receive site). Lootbox:532 packed-decode is a write-time invariant (Form 3 — mutex-equivalent: writer's `purchaseLevel ≥ 1` enforced by the binder at AdvanceModule:185 / MintModule:923). No re-derivation of the underlying invariant.

### SIB-04 Commit Cross-Check (D-250-12 / D-250-13)

- **D-250-12 (per-commit row + 8bdeabc2 explicit carrier row):** SIB-04 emits one row per post-v31.0 commit:
  - `SIB-04-V01` — `8bdeabc2` (productive-pause liveness): closest sibling shape per ROADMAP criterion 4. Verdict-justified row noting `_pauseDeathClockDuringProductivePhase` reads `lastPurchaseDay || jackpotPhaseFlag` at the productive-pause boundary; cross-cite Phase 249 PLV-06 daily-jackpot strand-disproof. Classification under SIB-02: turbo-class candidate IF the productive-pause reads compose un-monotonically with the new L173 turbo guard, ORTHOGONAL_PROVEN otherwise. Phase 252 POST31-02 will RE_VERIFY this row's verdict against the WIP guard composition.
  - `SIB-04-V02` — `ad41973c` (liveness regression test commit): test-only commit; zero `contracts/` delta surface. Verdict NEGATIVE-scope (test added, no logic change).
  - `SIB-04-V03` — `6a63705b` (purchaseCoin buyer-charge fix): contract delta but on a non-flag-vs-counter shape. Cross-cite Phase 247 §1.4 commit changelog row + classification ORTHOGONAL_PROVEN under D-250-07.
  - `SIB-04-V04` — `48554f8f` (vault redemption decoupling): contract delta on vault-redemption boundary; no `rngLockedFlag` interaction. Cross-cite Phase 247 §1.4 + classification ORTHOGONAL_PROVEN.
- **D-250-13 (column shape — commit-anchored row):** Inherit D-250-02 base + replace `Function` with `Commit SHA` + `Hunk anchor`:
  ```
  Row ID | Commit SHA | Hunk anchor (file:line range from Phase 247 §1.4) | Sibling-shape verdict | SIB-02 classification | Phase 252 POST31 inheritance | Evidence cite
  ```

### SIB-05 Finding Routing (D-250-14 / D-250-15 / D-250-16)

- **D-250-14 (SIB-05 row schema — proposed-fix block per row):** Each SIB-05 row carries:
  ```
  Row ID | Source row (SIB-01-Vnn / SIB-03-Vnn / SIB-04-Vnn) | Bug class {turbo, backfill, novel} | Trigger sequence | Suggested severity (D-08 5-bucket, recommended INFO baseline) | Proposed fix block (`awaiting-approval`) | Phase 253 FIND-01 routing target
  ```
  The proposed-fix block follows `feedback_no_contract_commits.md` format: `path:line` of the proposed change, diff sketch (3-5 lines of context with `+` / `-` markers), one-paragraph rationale. The block is explicitly marked `awaiting-approval` — no autonomous landing.
- **D-250-15 (zero-state attestation if no SIB-05 rows):** Per ROADMAP success criterion 5. If zero SIB-05 rows emit, Section 5 contains an explicit attestation paragraph + zero-row footer:
  ```
  ## Section 5 — SIB-05 New-Bug Documentation

  Phase 250 SIB-01..04 sweep emitted 0 FINDING_CANDIDATE rows. No new sibling-pattern bugs surface beyond
  the v32.0 fix anchors at AdvanceModule:173 (turbo) and AdvanceModule:1174 (backfill).

  | SIB-05-Vnn rows emitted | 0 |
  ```
  Cross-cite each Section 1-4 verdict count to confirm full coverage. The MintModule:923 pre-flagged candidate from Phase 249 D-249-01 either lands as a SIB-05 row (if reachable) or is explicitly cited as "zero-state-confirmed-by-PLV-01-V<MM>".
- **D-250-16 (severity recommendation = INFO baseline; Phase 253 final call):** Per D-247-21 / D-249-CF-03 carry-forward. SIB-05 rows recommend INFO severity unless the proposed-fix block changes runtime behavior under reachable inputs (in which case suggest LOW or above with justification). Phase 253 FIND-02 makes the final D-08 5-bucket call; SIB-05 severity is advisory.

### Plan Topology (D-250-PLN-01)

- **D-250-PLN-01 (suggested 4-task split — planner final call):**
  1. **Task 1 (SIB-01 enumeration + SIB-02 classification — single walk):** AdvanceModule pair-grep sweep across `rngLockedFlag` × 7 partners; per-row classification under {turbo-class, backfill-class, ORTHOGONAL_PROVEN}. ~15-25 rows expected after the same-branch-span filter trims 44 raw hits. Pre-seeded SIB-01-V01 (turbo guard L173) + SIB-01-V02 (backfill guard L1174). Combined task because classification is cheap once the row is enumerated; splitting them creates redundant per-function context loading.
  2. **Task 2 (SIB-03 module sweep):** 8 delegating modules. NEGATIVE-scope rows for Jackpot/Boon/Degenerette (one-line grep cite each per D-250-09); same-shape rows for Mint/Whale/Lootbox/Decimator/GameOver per D-250-08. MintModule:923 cross-cite + classify per D-250-10. Cross-module Phase 249 PLV-01 inheritance per D-250-11.
  3. **Task 3 (SIB-04 commit cross-check):** 4-row table per D-250-12. `8bdeabc2` carrier row gets the deepest treatment; the other three are ORTHOGONAL_PROVEN with Phase 247 §1.4 hunk-anchor cites.
  4. **Task 4 (SIB-05 finding documentation + Final assembly + READ-only flip):** Aggregate FINDING_CANDIDATE rows from Tasks 1-3; emit SIB-05 rows with `awaiting-approval` proposed-fix blocks (or zero-state attestation if none). Assemble `audit/v32-250-SIB.md`, write Phase 251 hand-off appendix (if any SIB-05 row implies a reproduction-test obligation), mark FINAL READ-only on plan-close commit.

  Each task lands its own atomic commit per D-247-14 atomic-task-commit pattern.

### Claude's Discretion

- Sweep enumeration mechanics for SIB-01 — pair-wise grep matrix vs. hybrid pair-grep + per-function context vs. pure per-function walk. Recommended: hybrid (pair-grep for discovery, per-function context for classification — 7 master greps + per-function read of AdvanceModule to disambiguate same-branch-span). Planner final call.
- Final section ordering within `audit/v32-250-SIB.md` (planner picks readable shape — likely 5-section format §1 SIB-01 enumeration / §2 SIB-02 classification / §3 SIB-03 modules / §4 SIB-04 commits / §5 SIB-05 finding-rows or zero-state, plus the standard appendix block).
- Whether SIB-01 and SIB-02 get separate sections (one row per REQ) or are inlined as a single 8-column table where the SIB-02 verdict is just a column on the SIB-01 row. Inline likely cleaner; per-REQ separable for traceability. Planner final call.
- Whether SIB-04-V01 (`8bdeabc2`) is given its own narrative paragraph in addition to the row (because it's the closest sibling shape and the Phase 252 POST31-02 hand-off carrier) or stays as a single row with cross-cites. Recommended: dedicated paragraph + row, mirroring Phase 248 BFL-04's narrative-plus-table pattern.
- Suggested severity for any SIB-05 row whose proposed-fix block is structural (e.g., MintModule:923 if reachable). Recommended: LOW-or-MEDIUM with justification, leaving Phase 253 FIND-02 D-08 5-bucket as the final call. Planner can emit INFO baseline if the cell is reachable but only under a vanishingly improbable trigger sequence (sub-block-time invariant violation, etc.).
- Phase 251 hand-off block — only emit if Phase 250 SIB-05 surfaces a bug requiring an additional reproduction test beyond `LastPurchaseDayRace.test.js`. Otherwise omit (Phase 248/249 hand-off blocks suffice).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v32.0 requirements; SIB-01..05 (this phase) + 4 accepted RNG exceptions + Out of Scope clauses; non-AdvanceModule subsystems explicitly out of scope except for SIB-03 cross-module sibling-pattern sweep.
- `.planning/ROADMAP.md` — Phase 250 success criteria (5 items); deliverable target `audit/v32-250-SIB.md`; per-criterion verdict-row guidance; explicit `8bdeabc2` carrier mention in criterion 4.
- `.planning/PROJECT.md` — Current Milestone section lists the bug context + READ-only-LIFTED write policy + the 4 post-v31.0 contract-touching commits.
- `.planning/STATE.md` — Active milestone v32.0 status; 7 phases / 32 REQs / Phase 247-249 complete.

### Phase 247 scope input (MUST read — sole catalog input per Phase 247 success criterion 4)
- `audit/v32-247-DELTA-SURFACE.md` — FINAL READ-only at HEAD `acd88512`. Specifically:
  - Section 1.4 acd88512 commit changelog rows D-247-C011 (advanceGame turbo guard hunk) + D-247-C012 (rngGate backfill guard hunk).
  - Section 1.4 commit rows for the 4 post-v31.0 commits (`8bdeabc2`, `ad41973c`, `6a63705b`, `48554f8f`) — SIB-04 row anchor surface.
  - Section 1.6 finding-candidate bullets for `advanceGame` turbo guard L173.
  - Section 2 classification rows D-247-F010 (advanceGame MODIFIED_LOGIC) + the 4 post-v31.0-commit classification rows.
  - Section 3 call-site rows D-247-X027..X029 (3 advanceGame entry paths).
  - Section 6 Consumer Index — provides the cross-module re-derivation surface inherited by SIB-03 D-250-11.
- `.planning/phases/247-delta-extraction-classification/247-CONTEXT.md` — D-247-21 (no F-32-NN emission), D-247-22 (READ-only after plan-close), D-247-02 (test/-out-of-scope routes to Phase 251) — all carried forward into Phase 250.
- `.planning/phases/247-delta-extraction-classification/247-01-PLAN.md` — single-plan multi-task atomic-commit precedent for D-250-CF-06 plan topology.
- `.planning/phases/247-delta-extraction-classification/247-01-SUMMARY.md` — Phase 247 closure verification.

### Phase 248 carry-forward (MUST read — backfill-class shape source)
- `audit/v32-248-BFL.md` — sibling pure-proof phase. Specifically §3 BFL-03 worked-numeric-example state-transition table format (precedent for D-250-12 `8bdeabc2` narrative paragraph), §4 BFL-04 invariant-table format (precedent for SIB-02 ORTHOGONAL_PROVEN isolation arguments per D-250-07), §5 BFL-05 dual-carrier attestation row format, §6 BFL-06 conservation algebra block. Direct source for the `backfill-class` taxonomy definition in D-250-06.
- `.planning/phases/248-backfill-idempotency-proof/248-CONTEXT.md` — D-248-02 (single deliverable READ-only flip), D-248-12 (V-row scheme + 3-bucket verdict), D-248-15 (grep-reproducibility), D-248-10 (BurnieCoinflip OOS-by-construction precedent). Carried forward into D-250-CF-NN.
- `.planning/phases/248-backfill-idempotency-proof/248-01-*-SUMMARY.md` (and per-task commits) — 5-task split precedent for D-250-CF-06 4-task simplification.

### Phase 249 carry-forward (MUST read — turbo-class shape source + MintModule:923 finding-candidate seed)
- `audit/v32-249-PLV.md` — sibling pure-proof phase. Specifically:
  - §3 PLV-03 ternary unreachable-state proof (the load-bearing `(T,T,lvl=0)` UNREACHABLE row at AdvanceModule:185, anchored on the L173 turbo guard) — direct source for the `turbo-class` taxonomy definition in D-250-05.
  - §1 PLV-01 wider scope cross-module re-derivation rows (MintModule:923, WhaleModule:841, LootboxModule:532, BurnieCoinflip:578/1035, AdvanceModule helpers L734/L1097/L1504) — SIB-03 D-250-10 / D-250-11 cross-cite anchors.
  - §6 PLV-06 daily-jackpot strand-disproof composition hand-off row — D-250-12 SIB-04-V01 `8bdeabc2` carrier cross-cite.
  - §5 PLV-05 testnet panic 0x11 reproduction walk — sibling-pattern lens for any SIB-04-V01 productive-pause composition concern.
- `.planning/phases/249-purchaselevel-correctness-proof/249-CONTEXT.md` — D-249-01 (MintModule:923 wider-scope rationale + live FINDING_CANDIDATE seed), D-249-02 (full per-row reachability proof depth — key to D-250-10 cross-cite vs. re-derive choice), D-249-CF-03 (no F-32-NN emission), D-249-CF-08 (scope-guard deferral). Direct precedent for D-250-CF-NN scheme.
- `.planning/phases/249-purchaselevel-correctness-proof/249-01-PLAN.md` — 4-task split precedent for D-250-PLN-01.
- `.planning/phases/249-purchaselevel-correctness-proof/249-01-SUMMARY.md` — Phase 249 closure + the actual MintModule:923 verdict (REACHABLE → FINDING_CANDIDATE vs. UNREACHABLE → ORTHOGONAL_PROVEN). Phase 250 SIB-03 row classification depends on this verdict.

### In-scope code (HEAD acd88512)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — primary audit target. Specifically:
  - `advanceGame` function L160-488 (the changed function with the new turbo guard hunk). Turbo block L167-182 with `!rngLockedFlag` guard at L173 (SIB-01-V01 pre-seed).
  - `_backfillGapDays` function and surrounding `rngGate` fresh-word branch — backfill guard at L1174 `rngWordByDay[idx + 1] == 0` (SIB-01-V02 pre-seed); call site at L1176.
  - 7 master grep targets per D-250-CF-08:
    ```
    grep -n 'rngLockedFlag' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'lastPurchaseDay' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'jackpotPhaseFlag' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'dailyIdx' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -nE '\blevel\b' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'purchaseStartDay' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'rngWordByDay' contracts/modules/DegenerusGameAdvanceModule.sol
    grep -n 'phaseTransitionActive' contracts/modules/DegenerusGameAdvanceModule.sol
    ```
  - Daily-jackpot region L370-407 (already proven by Phase 249 PLV-06; cross-cite for any SIB-04-V01 composition concern).
- `contracts/modules/DegenerusGameMintModule.sol` — SIB-03 row scope. Specifically L923 `uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;` (the live FINDING_CANDIDATE-or-ORTHOGONAL_PROVEN row per D-250-10).
- `contracts/modules/DegenerusGameJackpotModule.sol` — SIB-03 NEGATIVE-scope row. Scout: 0 hits on the 7 partner state-vars.
- `contracts/modules/DegenerusGameWhaleModule.sol` — SIB-03 row scope (1 hit). Specifically L841 (parameter receive — passthrough; cross-cite Phase 249 PLV-01) + L876 packing site `lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;`.
- `contracts/modules/DegenerusGameLootboxModule.sol` — SIB-03 row scope (3 hits). Specifically L532 `uint24 purchaseLevel = uint24(packed >> 232);` (packed-decode invariant; ORTHOGONAL_PROVEN under D-250-07 Form 3 — mutex-equivalent).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — SIB-03 NEGATIVE-scope row. Scout: 0 hits.
- `contracts/modules/DegenerusGameBoonModule.sol` — SIB-03 NEGATIVE-scope row. Scout: 0 hits.
- `contracts/modules/DegenerusGameDecimatorModule.sol` — SIB-03 row scope (1 hit). Investigate the single hit per D-250-08 same-shape filter.
- `contracts/modules/DegenerusGameGameOverModule.sol` — SIB-03 row scope (4 hits). Investigate the four hits per D-250-08 same-shape filter.
- `contracts/BurnieCoinflip.sol` — Phase 249 PLV-01 cross-module passthrough site (L578/L1035 receive, L590/L1041 modular arithmetic). SIB-03 cross-cite per D-250-11.
- `contracts/storage/DegenerusGameStorage.sol` — `level` storage at L250; `rngLockedFlag` / `lastPurchaseDay` / `jackpotPhaseFlag` / `dailyIdx` / `purchaseStartDay` / `phaseTransitionActive` storage declarations. Reference for SIB-01 row pre-state / post-state context.

### Methodology precedents (carry-forward, not re-litigated)
- `.planning/milestones/v30.0-phases/239-*` — v30 lootbox-index-advance / `phaseTransitionActive` orthogonality proof shape; direct precedent for D-250-07 ORTHOGONAL_PROVEN isolation argument forms.
- `.planning/milestones/v31.0-phases/244-per-commit-adversarial-audit/` — V-row pattern + 3-bucket verdict precedent (D-250-CF-05).
- `audit/v31-244-EVT.md` / `v31-244-RNG.md` / `v31-244-QST.md` / `v31-244-GOX.md` — direct format precedent for V-row tables in `audit/v32-250-SIB.md`.
- `audit/v31-245-SDR.md` / `v31-245-GOE.md` — dual-carrier attestation precedent for D-250-12 SIB-04-V01 `8bdeabc2` carrier row.
- `audit/v31-246-FINDINGS.md` — single-plan multi-task pattern reference; no findings IDs in mid-milestone phases.

### Prior audit outputs (light cross-cite)
- `audit/FINDINGS-v31.0.md` — 33 V-rows / 142 verdicts; lean regression appendix. SIB-01..04 rows cross-cite any v31 row whose underlying interaction overlaps the 7 partner state-var sweep.
- `audit/FINDINGS-v30.0.md` — VRF consumer determinism audit; per-consumer freeze proofs. Cross-cite for any rngWord-dependent SIB-01 path.
- `audit/FINDINGS-v29.0.md` — F-29-04 gameover RNG substitution finding (the EXC-03 codification source). SIB-04 row for `48554f8f` (vault redemption decoupling) may cross-cite if the decoupling boundary touches EXC-03 envelope.
- `audit/STORAGE-WRITE-MAP.md` — prior storage-write catalog; SIB-01 enumeration may cross-cite for `lastPurchaseDay` / `rngLockedFlag` / `level` write inventory.
- `audit/ACCESS-CONTROL-MATRIX.md` — prior access-control context; relevant if SIB-03 surfaces a flag-gated access path.
- `audit/KNOWN-ISSUES.md` — 4 accepted RNG exceptions (EXC-01..04) per `feedback_rng_backward_trace.md` / `feedback_rng_commitment_window.md`. Phase 250 does NOT re-litigate; envelope re-verify is Phase 252 POST31-01 / Phase 248 BFL-05 territory.

### Project feedback rules (apply across all plans in Phase 250)
- `memory/feedback_no_contract_commits.md` — explicit per-commit user approval required for any `contracts/` or `test/` write. Phase 250 has zero such writes by D-250-CF-04 but the rule binds if any SIB-05 finding-candidate proposes a fix.
- `memory/feedback_never_preapprove_contracts.md` — orchestrator does NOT pre-approve any contract change for any executor agent. SIB-05 proposed-fix blocks are explicitly `awaiting-approval`.
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source.
- `memory/feedback_no_history_in_comments.md` — deliverable docs describe what IS, not what CHANGED. Phase 250 deliverable describes interaction state at HEAD `acd88512` (which contains both fix guards); rationale prose reads as descriptive, not as patch-history narration.
- `memory/feedback_rng_backward_trace.md` — every RNG audit must trace BACKWARD from each consumer. Relevant to SIB-01 rows touching VRF-request → VRF-fulfillment spans.
- `memory/feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Relevant to SIB-01 same-branch-span column annotations.
- `memory/feedback_skip_research_test_phases.md` — skip research for obvious/mechanical phases. Phase 250 is a pure-proof sibling-pattern sweep grounded in Phase 247's catalog + Phase 248 BFL pattern + Phase 249 PLV pattern + REQUIREMENTS.md; research unlikely to add value.
- `memory/feedback_gas_worst_case.md` — N/A for Phase 250 (no gas analysis; pure sibling-pattern proof phase).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 247 Section 6 Consumer Index** — directly defines SIB-01..04 row scope through the 4 post-v31.0 commit changelog rows + advanceGame call-site rows. Phase 250 plan does NOT re-derive the universe.
- **Phase 248 V-row table format** — direct shape reuse for `audit/v32-250-SIB.md` Section 1 SIB-01-Vnn rows.
- **Phase 248 BFL-03 worked-numeric-example state-transition walk** — pattern available if SIB-04-V01 (`8bdeabc2` carrier) needs a sequential trigger walk.
- **Phase 248 BFL-04 invariant-table format** — pattern available for ORTHOGONAL_PROVEN isolation arguments per D-250-07 Form 3.
- **Phase 249 PLV-01 wider-scope cross-module enumeration** — directly cited by SIB-03 D-250-11 (5 cross-module rows + Mint:923). Phase 250 inherits the verdicts; no re-derivation.
- **Phase 249 PLV-03 ternary unreachable proof** — direct source for the `turbo-class` taxonomy definition in D-250-05.
- **Phase 249 PLV-06 daily-jackpot strand-disproof composition hand-off** — direct cross-cite for SIB-04-V01 `8bdeabc2` carrier row per D-250-12.
- **Phase 247 single-plan multi-task atomic-commit pattern (D-247-13 / D-247-14)** — direct reuse for D-250-CF-06 / D-250-PLN-01.
- **Existing 5-section single-file format from `audit/v31-243-DELTA-SURFACE.md` / `audit/v32-247-DELTA-SURFACE.md` / `audit/v32-248-BFL.md` / `audit/v32-249-PLV.md`** — format precedent for `audit/v32-250-SIB.md`.

### Established Patterns
- **State-var pair sweep with grep recipes** — pattern carry-forward from Phase 247 §3 Consumer Index discovery; applied to SIB-01 `rngLockedFlag` × 7 partners.
- **3-bucket verdict {SAFE, EXCEPTION, FINDING_CANDIDATE}** — Phase 244 / 245 / 248 / 249 carry-forward for SIB-01 / SIB-03 / SIB-04 / SIB-05.
- **Dedicated taxonomy bucket for classification REQs** — first appearance in v32.0 (SIB-02 {turbo-class, backfill-class, ORTHOGONAL_PROVEN}); verdict column shape inherits the same row format with bucket value substituted.
- **ORTHOGONAL_PROVEN isolation argument** — pattern from v30 Phase 239 lootbox-index-advance / `phaseTransitionActive` proofs; three forms documented in D-250-07.
- **Cross-cite chain for derivative facts** — pattern from Phase 248 BFL-06; applied to SIB-03 D-250-10 / D-250-11 cross-cite of Phase 249 PLV-01.
- **No F-NN-NN emission in proof / catalog phases** — v29 / v30 / v31 / Phase 247 / Phase 248 / Phase 249 carry-forward.
- **One-line grep cite for NEGATIVE-scope rows** — first appearance in v32.0 Phase 250 SIB-03 D-250-09; structural precedent in v25/v29/v30 boundary-record format.
- **`awaiting-approval` proposed-fix block format per `feedback_no_contract_commits.md`** — standard format across the entire v32.0 milestone (READ-only LIFTED but per-commit user approval still required).

### Integration Points
- **Phase 247 → Phase 250** — `audit/v32-247-DELTA-SURFACE.md` Section 1.4 commit changelog (4 post-v31.0 commits) maps to SIB-04-V01..V04 row anchor; Section 6 Consumer Index maps cross-module re-derivations to SIB-03 D-250-11 inheritance set.
- **Phase 248 → Phase 250** — `audit/v32-248-BFL.md` BFL-02 guard-evaluation evidence cross-cited by SIB-01-V02 (backfill guard L1174 pre-seed); BFL-03/BFL-04 patterns available as ORTHOGONAL_PROVEN isolation argument templates.
- **Phase 249 → Phase 250** — `audit/v32-249-PLV.md` PLV-01 cross-module rows cross-cited by SIB-03 D-250-11; PLV-03 ternary unreachable cross-cited by SIB-01-V01 (turbo guard L173 pre-seed); PLV-06 daily-jackpot composition cross-cited by SIB-04-V01 (`8bdeabc2` carrier).
- **Phase 250 → Phase 251** — Phase 250 SIB-05 rows (if any) emit a Phase 251 hand-off appendix block IF a SIB-05 finding-candidate implies a reproduction-test obligation beyond `LastPurchaseDayRace.test.js`. If zero SIB-05 rows, no hand-off needed (Phase 248/249 hand-off blocks suffice for TST-01..04).
- **Phase 250 → Phase 252** — D-250-12 SIB-04-V01 `8bdeabc2` carrier row carries the Phase 252 POST31-02 inheritance verdict ("Phase 252 RE_VERIFIES productive-pause + L173 turbo guard composition under WIP guard active"). Phase 252 plan reads SIB-04-V01 as the confirmed composition target.
- **Phase 250 → Phase 253** — Any SIB-05-Vnn row (or SIB-01/SIB-03/SIB-04 row classified FINDING_CANDIDATE) routes to Phase 253 FIND-01 finding-block emission per D-250-CF-03. Recommended INFO baseline severity per D-250-16; Phase 253 FIND-02 makes final D-08 5-bucket call.
- **Scope-guard deferral (D-250-CF-07) → Phase 253:** Any state-var pair / interaction Phase 247 missed routes to Phase 253 FIND-04 commit-readiness register.

### Git Infrastructure (verified 2026-05-01)
- HEAD anchor `acd88512`; current git HEAD recently at `9d11f44c` (Phase 249 closure docs commits above `acd88512` touch only `.planning/` and `audit/v32-249-*`).
- Working tree at start of Phase 250 execution: `contracts/ContractAddresses.sol` modified (deploy regen, ignored per D-247-03 carry-forward), `test/edge/LastPurchaseDayRace.test.js` untracked (Phase 251 scope per D-247-02).
- No `git diff` runs in Phase 250 plan — Phase 247 catalog is the sole scope input. Plan opens with a sanity gate `git rev-parse acd88512` to confirm anchor presence.
- 7 partner state-vars across `contracts/modules/DegenerusGameAdvanceModule.sol` produce 44 raw hits (per scout); same set across the 8 delegating modules produces 13 hits with 3 modules (Jackpot/Boon/Degenerette) at zero. SIB-01 row count after the same-branch-span filter expected 15-25; SIB-03 row count expected 8-12 (5-7 same-shape + 3 NEGATIVE-scope).

</code_context>

<specifics>
## Specific Ideas

- **MintModule:923 SIB-03 row template** — depending on Phase 249 PLV-01-V<MM> verdict:
  - If REACHABLE → `SIB-03-V<NN> | MintModule.sol:923 | bafTransfer | cachedJpFlag (read) | cachedLevel (read) | turbo-class | FINDING_CANDIDATE | Cross-cite Phase 249 PLV-01-V<MM> REACHABLE; same ternary shape as AdvanceModule:185 missing `!rngLockedFlag` guard analog. → SIB-05-V01 awaiting-approval fix block`
  - If UNREACHABLE → `SIB-03-V<NN> | MintModule.sol:923 | bafTransfer | cachedJpFlag (read) | cachedLevel (read) | ORTHOGONAL_PROVEN | SAFE | Cross-cite Phase 249 PLV-01-V<MM> UNREACHABLE via <invariant ID>; isolation form 3 (mutex-equivalent — upstream invariant prevents (cachedJpFlag = T ∧ cachedLevel = 0) cell)`
- **Master grep recipe block (Section 1 discovery preamble)** — single block at the top of Section 1 listing the 7 master greps + the AdvanceModule line-count summary (44 hits) + the same-branch-span filter rule. Reproducible per D-250-CF-08.
- **SIB-04-V01 `8bdeabc2` narrative paragraph format** — single paragraph by-inspection of `_pauseDeathClockDuringProductivePhase` reads of `lastPurchaseDay || jackpotPhaseFlag` against the new L173 turbo guard composition:
  > Commit `8bdeabc2` introduced productive-phase liveness pause that reads `lastPurchaseDay || jackpotPhaseFlag` to suppress the death clock during productive multi-call windows. The new L173 turbo guard `!rngLockedFlag && !lastPurchaseDay && !inJackpot` shares two of the three operands. Composition under WIP guards: when `rngLockedFlag = T`, turbo block is skipped (PLV-03); when `lastPurchaseDay = T` OR `jackpotPhaseFlag = T`, productive pause engages and death clock is suppressed. The two reads compose without race because the productive-pause path never modifies `rngLockedFlag` and the turbo block never modifies `lastPurchaseDay` or `jackpotPhaseFlag` (the `lastPurchaseDay = true` write at L399 is post-`_unlockRng(day)` at L404, after `rngLockedFlag` has already cleared). Phase 252 POST31-02 RE_VERIFIES this composition empirically.
- **NEGATIVE-scope row format** — exact:
  ```
  | SIB-03-V<NN> | DegenerusGameJackpotModule.sol | NEGATIVE | grep -nE '(rngLockedFlag\|lastPurchaseDay\|jackpotPhaseFlag\|dailyIdx\|level\|purchaseStartDay\|rngWordByDay\|phaseTransitionActive)' contracts/modules/DegenerusGameJackpotModule.sol → 0 matches | SAFE-by-vacuity |
  ```
  Same row for Boon and Degenerette; mass-attestation paragraph optional.
- **SIB-05 zero-state attestation language (if no FINDING_CANDIDATE)** — exact:
  > Phase 250 SIB-01..04 sweep emitted 0 FINDING_CANDIDATE rows. The MintModule:923 sibling pre-flagged by Phase 249 D-249-01 was classified ORTHOGONAL_PROVEN under SIB-02 with cross-cite to Phase 249 PLV-01-V<MM>. No new sibling-pattern bugs surface beyond the v32.0 fix anchors at AdvanceModule:173 (turbo) and AdvanceModule:1174 (backfill). SIB-05-Vnn rows emitted: 0.
- **`awaiting-approval` proposed-fix block format (template for SIB-05 if any row emits)**:
  ```markdown
  ### SIB-05-V<NN> — `awaiting-approval` proposed-fix block

  **Source:** SIB-03-V<NN> (MintModule.sol:923, bafTransfer, turbo-class FINDING_CANDIDATE)
  **Bug class:** turbo-class — same ternary shape as AdvanceModule:185 missing `!rngLockedFlag` guard analog
  **Trigger sequence:** [step-by-step state walk producing `cachedJpFlag = T ∧ cachedLevel = 0` cell]
  **Proposed fix (`path:line` + diff sketch):**
  ```diff
  -        uint24 purchaseLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1;
  +        uint24 purchaseLevel = (cachedJpFlag && !cachedRngLocked) ? cachedLevel : cachedLevel + 1;
  ```
  **Rationale:** [one paragraph]
  **Suggested severity:** [INFO / LOW / MEDIUM] — Phase 253 FIND-02 final call.
  **User approval audit trail:** AWAITING.
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Forge invariant fuzz tests for sibling-pattern interactions** — could augment Phase 251's hardhat reproduction with forge `invariant_*` tests asserting structural sibling-pattern absences (e.g., `invariant_rngLockedFlag_implies_turbo_guard_holds`). Out of Phase 250 scope (pure-proof phase per D-250-CF-04); flag for Phase 251 TST or future-milestone follow-up.
- **MintModule:923 fix landing** — if SIB-05 surfaces this as a FINDING_CANDIDATE, the structural fix is the `!rngLockedFlag`-conjunctive-guard analog at MintModule:923. Out of Phase 250 scope (pure-proof + per D-250-CF-03 no F-32-NN emission); routes to Phase 253 FIND-01/02 + per-commit user-approval audit trail per `feedback_no_contract_commits.md`.
- **Cross-milestone delta chain for sibling-pattern coverage** — a retroactive sibling-pattern audit chain across v25/v29/v30/v31 would be informative but is OUT of v32.0 scope (REQUIREMENTS.md Out of Scope: "non-delta surfaces — covered in v25.0/v29.0/v30.0/v31.0; not re-proven globally"). Future-milestone candidate.
- **State-var pair expansion beyond the 7 partners** — REQUIREMENTS.md SIB-01 lists 7 partners + "etc." If Phase 250 enumeration surfaces a meaningful interaction outside the 7 (e.g., `rngLockedFlag` × `jackpotMessageHash` if such a state-var existed), record via D-250-CF-07 scope-guard deferral and route to Phase 253. No implicit expansion of the 7-partner sweep universe in this phase.
- **Phase 252 SIB-04-V01 deep composition proof** — D-250-12 emits a SIB-04-V01 row + narrative paragraph for `8bdeabc2`. The deep composition proof (productive-pause × WIP turbo guard × WIP backfill guard, three-way) is Phase 252 POST31-02's responsibility. Phase 250 stops at the narrative + cross-cite to PLV-06.
- **`level` storage interaction sub-sweep** — `level` is one of the 7 partners but appears in many legitimate contexts (price lookups, level-tier prize pools, gameOver checks). The same-shape filter per D-250-08 will likely produce a small set of `rngLockedFlag` × `level` interactions; if the filter rejects too many legitimate patterns, planner can selectively expand to flag-gated branch reads per the SIB-03 audit-depth question's option 3. Defer that decision to the planner pending row-count signal.
- **`dailyIdx` / `purchaseStartDay` interaction sub-sweep** — these two are tightly coupled (daily ticket processing chain). Phase 250 SIB-01 enumerates each independently; if the interaction graph between the two warrants its own sub-section in the deliverable (e.g., a backfill-class-shape sub-graph), planner final call.

</deferred>

---

*Phase: 250-sibling-pattern-sweep*
*Context gathered: 2026-05-01*
