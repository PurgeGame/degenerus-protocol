---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 02
subsystem: spec-attestation
tags: [degeneretteResolve, D-05, keeper-router, redesign, call-graph-attestation, paper-only, BATCH-01, losing-bet-liveness, GASOPT-04]
requires:
  - frozen v48.0-closure HEAD 0cc5d10f (the audit baseline)
  - 329-CONTEXT.md (D-05 carry-forward — rename + flat >=3-gate re-peg + WWXRP exclusion + non-foldability + D-05c real-gas + D-05f liveness)
  - 330-ROUTER-REDESIGN-INTENT.md (the GASOPT-04 AutoBought test-file list)
provides:
  - 329-ATTEST-DEGENERETTE-RESOLVE.md (regenerated; sections A/B/C/D/E + Roll-up)
  - D-05a rename-surface enumeration (2 contract targets + self-call; interfaces ABSENT; 5 test files / 57 refs)
  - D-05f losing-bet-liveness finding (INERT-SAFE re-confirmed; SURFACE-TO-USER NONE)
  - D-05c corrected real-gas net-loss basis; D-05b flat-shape feasibility; ROUTER-05 non-foldability
  - GASOPT-04 cross-coordination collision set (CrankNonBrick + CrankLeversAndPacking)
affects:
  - 329-03 (reconciliation + edit-order map consumes these anchors + the D-05f finding)
  - 330 re-IMPL BATCH-02 (the rename + re-peg + the two-file test collision land together)
  - 331 GAS-06 (real-gas sanity-check handoff) / 332 TST-05 (re-green the renamed literals)
tech-stack:
  added: []
  patterns: [grep-against-frozen-blob, per-anchor-MATCH-SHIFTED-ABSENT, baseline-anchored-attestation, full-consumer-enumeration]
key-files:
  created:
    - .planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md
  modified: []
decisions:
  - "D-05 SURVIVES the keeper-router redesign VERBATIM — not a router leg; RD-1..RD-5 do not touch the Degenerette resolve path"
  - "Interface rename rows are ABSENT/no-op at 0cc5d10f (autoResolve/_autoResolveBet defined only on DegenerusGame.sol) — SHRINKS the surface"
  - "Rename test surface = 5 files / 57 refs is the ACTUAL 0cc5d10f baseline count, NOT a held-tree-only artifact"
  - "GASOPT-04 collision set = exactly CrankNonBrick.t.sol + CrankLeversAndPacking.t.sol (both rename AND AutoBought) -> both edits land together in BATCH-02"
  - "D-05f INERT-SAFE re-confirmed: degeneretteBets = 8 consumers in 3 files; all 11 other modules grep-CLEAN; no counter/tally; SURFACE-TO-USER NONE"
metrics:
  duration: ~20m
  completed: 2026-05-26
  tasks: 2
  files: 1
  blockers: 0
---

# Phase 329 Plan 02: DEGENERETTE-RESOLVE (D-05) Attestation Summary

Re-attested the D-05 family — the `autoResolve` → `degeneretteResolve` rename + flat ~1-BURNIE "lose"
re-peg — against the FROZEN v48.0-closure HEAD `0cc5d10f`, regenerating the stale pre-redesign ATTEST
doc. **D-05 SURVIVES the keeper-router redesign VERBATIM** (it is NOT a router leg; RD-1..RD-5 do not
touch the Degenerette resolve path). **0 IMPL blockers.** The load-bearing D-05f losing-bet-liveness
finding is RE-CONFIRMED **INERT-SAFE** — no path requires losing Degenerette bets resolved; **SURFACE-TO-USER: NONE.**

## What was produced

`.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md`
(sections A/B/C/D/E + a Roll-up), fully OVERWRITING the stale pre-redesign output (Write, not append),
then Section E + Roll-up appended:

- **Section A — rename surface (D-05a).** 2 contract definition targets (`autoResolve` `DegenerusGame.sol:1587`,
  `_autoResolveBet` :1684) + the self-call site `try this._autoResolveBet` :1606; interface files **ABSENT**
  (grep of all `contracts/interfaces/` → ZERO matches — the rename is CONTRACT-only at the interface layer,
  confirming the CONTEXT "no degeneretteResolve interface row" note and SHRINKING the surface); test surface =
  **5 files / 57 refs** (RE-VERIFIED against `0cc5d10f`, NOT a held-tree-only artifact). The
  `CrankLeversAndPacking.t.sol` literal source-string assertions `_countOccurrences(game_, "function
  autoResolve(")` at :277/:278/:279/:290 are load-bearing (break without atomic rename). AUTO-02 / try-catch /
  WWXRP / self-resolve / one-creditFlip-CEI-last all PRESERVED (D-05d). **GASOPT-04 cross-coordination:** the
  rename ∩ `AutoBought`-removal collision set = exactly **CrankNonBrick.t.sol + CrankLeversAndPacking.t.sol**
  (the two files carrying BOTH surfaces → both edits land together in BATCH-02).
- **Section B — flat-shape feasibility (D-05b).** FEASIBLE on the existing `:1587-1622` per-item loop:
  per-item-accumulate (:1611-1614) → `++successCount`; post-loop (:1622) → `successCount >= 3` flat-creditFlip;
  `NoWork()` at zero resolved; 1–2 resolved → resolved-but-UNPAID (do-NOT-revert, never strand the tail). Edit
  targets pinned. Exact ~1 BURNIE literal deferred to GAS (D-05e). `AUTO_RESOLVE_BET_GAS_UNITS` :1545 likely
  goes dead (autoOpen uses the separate :1546) — IMPL housekeeping, not a blocker.
- **Section C — corrected real-gas basis (D-05c).** 1 BURNIE ≤ mintPrice/1000 ≤ 0.00024 ETH (PRICE_COIN_UNIT
  = 1000 ether at DegenerusAdmin:393, inverted) AND illiquid (coinflip-locked flip-credit). Keeper pays REAL
  prevailing gas (≥220k for the ≥3 min × 5–50+ gwei = 0.0011–0.011+ ETH = ~4.6–46× the peg), NOT the 0.5-gwei
  `AUTO_GAS_PRICE_REF`. Every qualifying tx is a NET LOSS; the ≥3 gate widens the margin. GAS-06 sanity-check
  handed to Phase 331.
- **Section D — architectural non-foldability (ROUTER-05).** `degeneretteBets` is a nested mapping
  (`DegenerusGameStorage.sol:1449`) with NO O(1) enumeration + no pending-count sidecar → on-chain discovery is
  impossible-or-unbounded (violates ROUTER-04). Stays a SEPARATE caller-supplied-arrays call; the unified one
  button is a frontend concern. RD-1..RD-5 do NOT touch the path.
- **Section E — D-05f losing-bet-liveness finding (the load-bearing deliverable).** Full `degeneretteBets`
  enumeration across ALL `contracts/*.sol` modules: **8 consumer sites in 3 files** (Storage:1449; DegeneretteModule
  write :526 / read :605 / delete :634; DegenerusGame probe :1596 / loop :1601 / view :2319), each classified
  NO-dependency. Candidate modules GameOver / Jackpot / Advance — and all 8 other modules — are grep-CLEAN
  (0 hits each). No outstanding-bet counter / per-day tally / require-empty anywhere; the RNG slot is a read,
  never freed-on-delete. **FINDING: INERT — SAFE (re-confirmed vs the prior 329 run); SURFACE-TO-USER: NONE.**
  The flat reward mildly IMPROVES backlog liveness (max work per paid tx).
- **Roll-up** — 0 IMPL blockers; the D-05f / D-05c / D-05b / D-05a / ROUTER-05 verdicts.

## Headline verdicts (for Plan 03)

- **Aggregate IMPL-blocker count: 0.** No ABSENT code anchor; the only ABSENT is the interface-rename rows
  (which SHRINKS the surface — a non-blocking correction). Two NON-blocking housekeeping notes: interface rows
  no-op (§A.2), `AUTO_RESOLVE_BET_GAS_UNITS` :1545 likely dead after re-peg (§B.2).
- **D-05f LOSING-BET LIVENESS: INERT-SAFE, SURFACE-TO-USER NONE.** No invariant / accounting / RNG-slot /
  gameOver / sweep / jackpot / cleanup path requires losing Degenerette bets resolved. Re-confirmed against the
  frozen baseline; the flat re-peg does not starve liveness, it mildly improves it.
- **D-05c REAL-GAS: NET LOSS, no positive-EV farm.** The corrected basis is REAL prevailing gas (5–50+ gwei),
  NOT the 0.5-gwei peg ref. Comfortable net-loss margin at every realistic gas price.
- **D-05b FLAT SHAPE: FEASIBLE.** Localized arithmetic + boundary swap on the current loop.
- **ROUTER-05 NON-FOLDABILITY: CONFIRMED, unchanged by the redesign.** Nested mapping, no O(1) enumeration.
- **GASOPT-04 CROSS-COORDINATION:** collision set = CrankNonBrick.t.sol + CrankLeversAndPacking.t.sol — both
  the rename test-fixes AND the AutoBought-event-removal oracle migration must land together in BATCH-02 there.

## Deviations from Plan

None — plan executed exactly as written. One material RE-VERIFICATION recorded in-doc (not a deviation):
the re-plan flagged the "5 files / 57 refs" test count as a possible HELD-TREE artifact to re-verify; the
FROZEN-baseline grep confirms the count IS 5 files / 57 refs at `0cc5d10f` (it is NOT a held-tree-only
artifact — the actual baseline `autoResolve` reference count is 57). Minor line-anchors recorded vs the plan's
cited values where the body greps tightened them: WWXRP decode at :1604 / fork :1607-1615 (plan cited
:1607-1608); per-item peg :1611-1614; PRICE_COIN_UNIT at DegenerusAdmin:393. All MATCH in substance.

## Known Stubs

None. Paper-only attestation — ZERO `contracts/*.sol` mutation. The pre-existing held-330 diff on the working
tree (6 dirty `.sol` + 7 dirty test files) was NOT touched, staged, or committed by this plan; only the
`.planning/` ATTEST doc + this SUMMARY were written and committed (explicit file paths under
`CONTRACTS_COMMIT_APPROVED=1`). STATE.md / ROADMAP.md / REQUIREMENTS.md were NOT modified (orchestrator-owned).

## Threat Flags

None. No new security-relevant surface introduced — paper-only attestation. The load-bearing T-329-D1
(losing-bet-liveness false-negative) was mitigated by enumerating `degeneretteBets` across EVERY module (not
just the two obvious ones); the finding is INERT-SAFE with SURFACE-TO-USER NONE.

## Commits

- `e9cba730` docs(329-02): attest degeneretteResolve rename + flat re-peg vs 0cc5d10f (A/B/C/D)
- `3b2bf287` docs(329-02): record D-05f losing-bet-liveness finding + Roll-up (E)

## Self-Check: PASSED

- FOUND: `329-ATTEST-DEGENERETTE-RESOLVE.md` (regenerated, sections A/B/C/D/E + Roll-up)
- FOUND: `329-02-SUMMARY.md`
- FOUND commits: `e9cba730`, `3b2bf287`
- VERIFIED: no `contracts/`/`test/` file is in either commit (`git show --name-only` per commit lists only the
  ATTEST doc); STATE.md / ROADMAP.md / REQUIREMENTS.md NOT modified by this plan; the held-330 dirty tree
  (6 `.sol` + 7 test files) untouched.
