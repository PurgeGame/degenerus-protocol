---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 03
subsystem: keeper-router (AfKing) + advance-bounty + Degenerette-resolve — v49.0 design-lock (paper-only)
tags: [spec, design-lock, attestation, keeper-router, redesign, BATCH-01, ROUTER-07, ADV-04, GAS-03]
requires:
  - "329-01-SUMMARY.md / 329-ATTEST-ROUTER-ADVANCE.md (the redesigned router+advance verdict — 0 blockers)"
  - "329-02-SUMMARY.md / 329-ATTEST-DEGENERETTE-RESOLVE.md (the D-05 family verdict — 0 blockers; D-05f INERT-SAFE)"
  - "330-ROUTER-REDESIGN-INTENT.md (the 5 locked RD changes + survivors-vs-reworked split)"
provides:
  - "329-SPEC.md — the reconciled v49.0 keeper-router-REDESIGN design-lock blueprint (§0 roll-up / §1 redesigned signatures / §2 the 4 invariants + dispositions + RD/D-08/D-05 / §3 producer-before-consumer survivors-vs-reworked edit-order map)"
  - ".planning/REQUIREMENTS.md amended to the redesign (31 → 36 active reqs; ROUTER-08/09/10 + GASOPT-03/04/05 registered; GASOPT-02 SUBSUMED)"
  - ".planning/ROADMAP.md amended (Phase 329 GOAL + SC1..SC4 + plan list + Phase 330 GOAL/SC/reqs + Coverage/per-category tables → 36)"
affects:
  - "Phase 330 IMPL — re-authors the ONE batched contract diff from §3's edit-order map (survivors carried, bounty portions reworked)"
  - "Phase 331 GAS — calibrates the D-07 flat-per-tx placeholders (1× / 1·1.5·2 / KNEE) + the RESOLVE_FLAT_BURNIE ~1 BURNIE"
  - "Phase 332 TST — TST-01 freeze-fuzz (autoBuy-during-rngLock / autoOpen-blocked) + TST-02 no-double-pay + TST-04 GASOPT-04 oracle-migration net-zero + TST-05 degeneretteResolve"
  - "Phase 333 TERMINAL — SWEEP re-attests the 4 OPEN-E protections without :676 (GASOPT-05 BLOCKING-CONDITION)"
tech-stack:
  added: []
  patterns: [paper-only-reconciliation, grep-attestation-vs-frozen-baseline, producer-before-consumer-edit-order, survivors-vs-reworked-split]
key-files:
  created: []
  modified:
    - ".planning/phases/329-.../329-SPEC.md (re-authored from the superseded design)"
    - ".planning/REQUIREMENTS.md"
    - ".planning/ROADMAP.md"
decisions:
  - "ROUTER-07 = NO nonReentrant guard, re-grounded on the unified single creditFlip (RD-4) — STRONGER than the old per-leg case"
  - "GAS-03 = satisfied-by-deletion (D-03 dissolved by D-07; advance is the sole stall epoch)"
  - "doWork() is PARAMETERLESS (D-07 supersedes D-06; no maxCount==0 sentinel)"
  - "GASOPT-02 SUBSUMED into GASOPT-03 (batched keeper read is the superset) — 36 active reqs, not 37"
metrics:
  duration: "~1 session"
  completed: 2026-05-26
  tasks: 3
  files: 3
---

# Phase 329 Plan 03: Reconcile into 329-SPEC.md + amend REQUIREMENTS/ROADMAP to the keeper-router REDESIGN — Summary

**One-liner:** Re-authored `329-SPEC.md` from the superseded pre-redesign design into the reconciled v49.0 keeper-router-REDESIGN design-lock blueprint (parameterless `doWork()` · `autoBuy→advance→autoOpen` · unified single `creditFlip` · D-07 flat-per-tx · ROUTER-07 no-guard re-grounded · GAS-03 satisfied-by-deletion) and amended REQUIREMENTS.md + ROADMAP.md to match (31 → 36 active reqs), folding both regenerated Wave-1 ATTEST docs (0 IMPL blockers each).

## What was produced

### 329-SPEC.md sections (re-authored, not appended)
- **§0 Attestation verdict roll-up** — folds BOTH `329-ATTEST-*.md` into a single 0-IMPL-blocker tally; the C1-C15 held-tree-vs-`0cc5d10f` line-drift corrections; and the explicit verdicts: Q5 (no other `batchPurchase` dependent), ROUTER-07 (no-guard basis holds, re-grounded on the unified `creditFlip`), GAS-03 (satisfied-by-deletion), ADV-04 (no new in-window read, autoBuy-pre-entropy), RD-5 (entry-gate replicates both revert sources), invariant-(c)/D-04a (fallback callers intact), RD-4 (6 creditFlip→1), design-1 return, KEEP-04 survival, GASOPT-01/03/04/05 baselines, and the **D-05f clean negative (INERT-SAFE; SURFACE-TO-USER NONE)** carried verbatim, not softened.
- **§1 Shared Signatures** (the redesigned surface) — R1 `advanceGame (uint8 mult, bool rewardable)` + mid-day `mult=1` + the `:275` wrapper decode; R2 PARAMETERLESS `doWork()` + `NoWork()` + the standalone UNREWARDED `autoOpen(count)`/`autoBuy(count)` escapes (NO `maxCount==0` sentinel); R3 the rngLock-aware O(1) discovery views; R4 the unified single `creditFlip` in `doWork` (the 5 pull-out sites + KEEP-04 survival); R5 the D-07 flat-per-tx model (advance `2×·mult` / buy `1.5×` / open `1×` pro-rated, GAS-331 placeholders + the faucet constraint). Each R-row names the producing + consuming files + an explicit apply-order.
- **§2 Invariants + dispositions + RD changes + D-08 + D-05 design-lock** — locks the 4 structural invariants under the redesign + the 5 RD changes + ROUTER-07 (re-grounded) + GAS-03 (satisfied-by-deletion) + D-08 GASOPT-03/04/05 + the D-05 degeneretteResolve design item.
- **§3 IMPL blueprint + edit-order map** — the producer-before-consumer survivors-vs-reworked edit-order map (AdvanceModule → Game → interfaces → AfKing → MintModule → tests) + per-work-area blueprint + the SC1..SC4 checklist + the SOURCE-TREE-not-mutated line.

### The 4 structural invariants (locked under the REDESIGN, §2)
- **(a) one-category structural early-return** — `doWork` routes `autoBuy → advance → autoOpen` (RD-1) and returns after the first rewarded category (a code invariant; one creditFlip after the return point).
- **(b) frozen advance-consume (ADV-04)** — autoBuy runs PRE-ENTROPY at day-open before advance requests the word; advance consumes via the design-1 return; no new in-window SLOAD; `totalFlipReversals` frozen request→consume; TST-01 empirical handoff.
- **(c) guaranteed free-fallback caller (D-04/D-04a)** — EXISTING paths only: PRIMARY the rewarded advance leg (blocked while buys pend under autoBuy-first); SECONDARY the 30-min permissionless bypass + Vault/sStonk `gameAdvance()`; TERTIARY the 120-day death-clock. Re-homing removes no structural caller.
- **(d) single day-start epoch — SATISFIED BY DELETION (GAS-03/D-03 dissolved by D-07)** — the autoBuy stall ladder + absolute epoch are deleted; advance is the SOLE stall epoch; no two epochs to collapse.

### The settled REDESIGNED shared signatures (SC2)
`advanceGame (uint8 mult, bool rewardable)` (mid-day `mult=1`) / **PARAMETERLESS `doWork()`** + `NoWork()` + standalone unrewarded `autoOpen(count)`/`autoBuy(count)` / the rngLock-aware O(1) views (advanceDue / boxesPending-rngLock-aware / buys-pending-TRUE-during-rngLock) / the unified single `creditFlip` in `doWork` / the D-07 flat-per-tx model.

### The two dispositions (SC3)
- **ROUTER-07 = NO `nonReentrant` guard**, re-grounded on the unified single `creditFlip` (under RD-4 exactly ONE creditFlip in `doWork`, CEI-last, fed by non-self-crediting legs — STRONGER than the old per-leg case); basis = keeper-never-a-payee + no untrusted ETH send + one-category early-return + single-`creditFlip`-last CEI; D-01b TST-02 backstop.
- **GAS-03 = satisfied-by-deletion** (cross-ref invariant d).

### The 5 RD changes + D-08 + D-05 design-lock
- **RD-1** order autoBuy→advance→autoOpen · **RD-2** drop the rngLock guards (AfKing `:568` + game-side `:1737`, KEEP `gameOver :1738`; Q5 verdict) · **RD-3** boxesPending rngLock-aware + block autoOpen during rngLock · **RD-4** unify the bounty into `doWork` · **RD-5** drop the autoOpen try/catch + entry-gate on `rngLocked()||_livenessTriggered()` (basis: the `storage/DegenerusGameStorage.sol:571` liveness control).
- **D-08** GASOPT-03 (batched keeper read, SUBSUMES GASOPT-02) / GASOPT-04 (drop AutoBought + the test-oracle migration) / GASOPT-05 (drop per-iteration isOperatorApproved `:676`, KEEP subscribe-time `:401`; the 333-SWEEP-re-attests-4-OPEN-E-protections BLOCKING-CONDITION).
- **D-05** degeneretteResolve rename + flat ~1-BURNIE/≥3-NON-WWXRP-gate/revert-on-no-work re-peg + D-05c real-gas basis + **D-05f INERT-SAFE (the clean negative — SURFACE-TO-USER NONE)** + router-fold OUT (survives the redesign verbatim; code at 330/BATCH-02, REQ GAS-06/TST-05 at 331/332).

## REQUIREMENTS.md / ROADMAP.md amendments applied
- **ROUTER-01** parameterless `doWork()` (maxCount==0 sentinel dropped) · **ROUTER-02** order autoBuy→advance→autoOpen · **ROUTER-04** boxesPending rngLock-aware + buys-pending-during-rngLock · **ROUTER-05** `_autoBuy` refactor + dropped guard + unified bounty · **ROUTER-07** NO-guard re-grounded.
- **NEW ROUTER-08/09/10** (RD-2 / RD-3+RD-5 / RD-4) + **NEW GASOPT-03/04/05** registered, all Phase 330 IMPL; **GASOPT-02 SUBSUMED** into GASOPT-03 (pointer row, not counted).
- **ADV-02** mid-day mult=1 · **GAS-02** flat-per-tx · **GAS-03** satisfied-by-deletion · **GAS-04** stall ladder advance-only · **GAS-05** re-prove no +EV under flat-per-tx · **GAS-01** sizes the D-07 model (not the D-06 default-count).
- **TST-01** (autoBuy-during-rngLock-safe / autoOpen-blocked / no-double-pay) · **TST-02** (parameterless-doWork default-batch + D-01b backstop) · **TST-04** (GASOPT-04 oracle-migration net-zero).
- **ROADMAP Phase 329 GOAL + SC1..SC4 + plan list** rewritten to the redesign; **Phase 330 GOAL/SC + Requirements line** re-homed; **Coverage + per-category split + per-phase count** tables → **36 active reqs** (4 SPEC · 18 IMPL · 5 GAS · 5 TST · 4 TERMINAL); ROUTER 7→10, GASOPT 2→4-active (02 subsumed); the §13e note + center-of-gravity rationale + scope-source + footnote updated; D-06 superseded-by-D-07 noted.
- **Phase 329's own coverage stays BATCH-01/ROUTER-07/ADV-04/GAS-03** — the new reqs are Phase 330 IMPL reqs (registered, NOT phase-329 targets).
- **Self-consistency verified:** 37 distinct REQ-IDs − 1 SUBSUMED (GASOPT-02) = 36 active; per-phase counts sum to 36; every REQ-ID appears in exactly one Traceability row + exactly one phase.

## SC1..SC4 coverage for the Phase 329 verification
- **SC1** — the 4 invariants locked under the redesign (§2). ✅
- **SC2** — the redesigned shared signatures settled (§1 R1-R5). ✅
- **SC3** — ROUTER-07 no-guard re-grounded + GAS-03 satisfied-by-deletion (§2). ✅
- **SC4** — every cited `file:line` grep-attested vs `0cc5d10f` (0 blockers, §0 C1-C15) + the producer-before-consumer survivors-vs-reworked edit-order map produced (§3). ✅

## Deviations from Plan

None — plan executed exactly as written. (Two consistency-driven edits beyond the literal enumeration, both within the plan's "update count tables / reword the existing reqs to match" mandate: TST-02's stale D-06 `doWork(0)` reference was reworded to the parameterless-`doWork()` default-batch + D-01b backstop; a stray `</content>` tag at the foot of ROADMAP.md was removed while updating the footnote.) Active requirement count landed at **36** (the plan's "~34" was an estimate; 36 is the self-consistent count with GASOPT-02 subsumed).

## Commits
- `3e961575` — docs(329-03): author 329-SPEC.md §0 + §1
- `1cb91124` — docs(329-03): author 329-SPEC.md §2 + §3
- `282ea135` — docs(329-03): amend REQUIREMENTS.md + ROADMAP.md (31 → 36 reqs)

## Notes
- **ZERO `contracts/*.sol` mutation.** The held-330 diff (13 dirty `.sol`/test files) was left untouched; every grep was run against the frozen blob via `git show 0cc5d10f:`. `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` is EMPTY.
- STATE.md was NOT modified and no plan-progress/tracking helper was invoked (orchestrator-owned).

## Self-Check: PASSED
- Files exist: `329-SPEC.md`, `329-03-SUMMARY.md`, `REQUIREMENTS.md`, `ROADMAP.md` — all FOUND.
- Commits exist: `3e961575`, `1cb91124`, `282ea135`, `2d16f165` — all FOUND in the log.
- Scope guard: 13 contracts/test files remain dirty+untouched; `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` EMPTY (contracts byte-identical to baseline); STATE.md remains modified+unstaged (orchestrator-owned).
