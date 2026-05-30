---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
plan: 04
subsystem: spec-placement-decision
tags: [spec, placement, required-path, user-override, freeze, liveness, afking-in-game]
requires:
  - "348-01 (348-GREP-ATTESTATION.md) — the re-pinned live anchors (STAGE insertion :272-273, rngGate :1152, _enforceDailyMintGate :973 called :191, index advance :1089/:1629)"
provides:
  - "PLACE-01 — the §4 placement DECISION (required-path, USER override) + the superseded-recommendation record + the two carried proof obligations + the mint-gate-standing acceptance"
affects:
  - "349 IMPL — builds the process-pass as a required-path advanceGame STAGE (not separate legs), with the mint-gate standing accepted and the two proof obligations bound to their proofs; PLACE-02 (bounty) 349-owned"
  - "348-FREEZE-PROOF.md / 348-INVARIANT-CARRY.md (348-03) — the cross-referenced proofs that DISCHARGE the two carried obligations (D-348-02 / D-348-04)"
tech-stack:
  added: []
  patterns:
    - "Recorded-override discipline (343 D-01 precedent): a deliberate USER decision that diverges from a carried artifact is marked SUPERSEDED, not silently reconciled"
    - "Re-pinned-anchor citation (348-GREP-ATTESTATION.md UPSTREAM PRODUCER): cite actual live lines, never drifted doc-cited lines"
key-files:
  created:
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-PLACEMENT-DECISION.md"
  modified: []
decisions:
  - "D-348-01 recorded: §4 placement DECIDED = REQUIRED-PATH (chunked advanceGame STAGE before rngGate), a DELIBERATE USER OVERRIDE of the doc's separate-legs recommendation; PLAN-V55 §4/§9 marked SUPERSEDED on the placement point"
  - "Decision basis = guaranteed-every-day, NOT revert-safety (the REVERT-FREE-CHAIN proof made required-path VIABLE; the §0-Correction-2 liveness fear is discharged for the healthy path)"
  - "D-348-02 carried + bound to 348-FREEZE-PROOF.md (FREEZE-02): the uniform-index-epoch no-interleave guard"
  - "D-348-04 carried + bound to 348-INVARIANT-CARRY.md: obligation-1 as the SOLE no-brick guarantor (try/catch valve DROPPED)"
  - "D-348-03 recorded ACCEPTED: the STAGE inherits advanceGame's existing _enforceDailyMintGate (zero new gate code); decoupling rejected"
  - "Leg chunking: process-leg pre-RNG BUY_BATCH-style inside the STAGE; open-leg a normal post-RNG OPEN_BATCH-style leg (NOT folded into advance) — also resolves the PLACE-02 early-slot drift"
  - "PLACE-02 (bounty) NOTED not decided (349-owned): buy/process bounty folds into advance bounty 2×·mult; farm-by-splitting watched via OPEN_KNEE pro-rate"
metrics:
  duration: "~6 min"
  completed: 2026-05-30
---

# Phase 348 Plan 04: §4 Process/Open Placement Decision Summary

Authored `348-PLACEMENT-DECISION.md` (PLACE-01) — the HEADLINE divergence of the v55.0 milestone, recording the §4 process/open placement as DECIDED = REQUIRED-PATH (a chunked `advanceGame` STAGE before `rngGate`, uniform index epoch, inheriting the mint gate), framed as a DELIBERATE USER OVERRIDE of PLAN-V55 §4/§9's separate-legs recommendation, with the two proof obligations the override creates carried and bound to their proofs.

## What Was Built

A single paper-only SPEC artifact — `348-PLACEMENT-DECISION.md` — promoting the placement-decision content (which Phase 343 folded into its edit-order map) to its own doc because it is the milestone's headline USER override. It contains, in order:

1. **§0 THE DECISION** — required-path, stated up front: a chunked STAGE in `advanceGame` immediately before `rngGate`, guarded by `subsFullyProcessed` + `_subCursor`, inheriting `_enforceDailyMintGate`; the open stays a normal post-RNG leg.
2. **§1 SUPERSEDED RECOMMENDATION** — a labeled table marking PLAN-V55 §4 ("RECOMMENDED — separate permissionless legs"), §0-Correction-2, §9 ("Next step"), and REVERT-FREE-CHAIN-PROOF §8 as SUPERSEDED on the placement point, with the rationale for recording an override rather than silently reconciling (the `T-348-08` Repudiation closure; 343 D-01 precedent).
3. **§2 DECISION BASIS** — guaranteed-every-day, NOT revert-safety: the proof made required-path VIABLE (a funded well-formed sub can't revert → can't freeze the day → the §0-Correction-2 liveness fear is discharged for the healthy path); the choice then rested on guaranteed-every-day vs minimal-surface.
4. **§3 THE MECHANISM** — the chunked STAGE specified against the re-pinned insertion point (`AdvanceModule:272-273`, before `rngGate(:274)`, def `:1152`), the two guards (`subsFullyProcessed` flag mirroring `ticketsFullyProcessed`; `_subCursor` gas budget), and the leg chunking (process pre-RNG `BUY_BATCH`-style; open post-RNG `OPEN_BATCH`-style, NOT folded — resolving the PLACE-02 early-slot drift).
5. **§4 CARRIED PROOF OBLIGATIONS** — D-348-02 (uniform-index-epoch no-interleave guard) bound to `348-FREEZE-PROOF.md` (FREEZE-02); D-348-04 (obligation-1 as the SOLE no-brick guarantor, try/catch valve DROPPED) bound to `348-INVARIANT-CARRY.md`, with the class-B/class-C disposition and the obligation-1 concentration consequence.
6. **§5 MINT-GATE STANDING (D-348-03)** — ACCEPTED with ZERO new gate code, citing `_enforceDailyMintGate` (`:973`, called `:191`); decoupling rejected.
7. **§6 BOUNTY FOLD (PLACE-02)** — NOTED only (349-owned): the fold into the advance bounty `2×·mult`, farm-by-splitting watched via `OPEN_KNEE` pro-rate.
8. **§7 self-audit + §8 attestation** — must-have coverage table; zero-contracts attestation; re-pinned-anchor discipline; valid-until note.

## Key Implementation Details

- **All `file:line` anchors are the RE-PINNED live lines from `348-GREP-ATTESTATION.md`** (the phase's UPSTREAM PRODUCER), not the drifted doc-cited lines — verified directly against the live working tree (`contracts/` byte-identical to `20ca1f79`). Confirmed the STAGE insertion point at `AdvanceModule:272-273` by reading the source (the `// RNG: use existing word or request new one` comment + `bool bonusFlip = …` line, immediately before the `rngGate(` call at `:274`), and the `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` call at `:191`.
- **The override is recorded as deliberate, not reconciled** — the doc explicitly explains why both failure modes (silently following the doc's stale recommendation vs silently following the decision without marking the doc) are the documentation-integrity threat, and marks §4/§9 SUPERSEDED.
- **The proof's §8 "per-sub skip valve" is itself flagged as superseded by D-348-04** — caught that the REVERT-FREE-CHAIN-PROOF §8 + §5 obligation 4 (and the §4 ALTERNATIVE in the redesign) still describe a thin try/catch valve, which D-348-04 DROPPED; the doc records this so the no-valve form is unambiguous for 349.
- **Forward cross-references to 348-03 artifacts are by design** — `348-FREEZE-PROOF.md` and `348-INVARIANT-CARRY.md` are sibling SPEC docs (348-03) that ship before 349 reads the set; the binding keys D-348-02 / D-348-04 connect this decision to those proofs.

## Deviations from Plan

None - plan executed exactly as written. Single `type="auto"` task; all acceptance criteria met on first authoring.

## Verification

Plan automated check (Task 1) PASSED:

```
test -f 348-PLACEMENT-DECISION.md
&& grep -qi "required-path"            → present
&& grep -qiE "supersede"               → present (SUPERSEDED table, §4/§9 ref)
&& grep -qi "guaranteed-every-day"     → present
&& grep -q  "subsFullyProcessed"       → present
&& grep -q  "_enforceDailyMintGate"    → present
&& grep -q  "D-348-02"                 → present (bound to 348-FREEZE-PROOF.md FREEZE-02)
&& grep -q  "D-348-04"                 → present (bound to 348-INVARIANT-CARRY.md)
&& [ -z "$(git diff --name-only -- contracts/)" ]  → contracts/ empty
```

Extra acceptance greps confirmed: `rngGate :1152`, `:272-273` insertion point, `348-FREEZE-PROOF.md`/`FREEZE-02` xref, `348-INVARIANT-CARRY.md` xref, `REVERT-02`, `OPEN_KNEE`/farm-by-split bounty note. `git diff --name-only -- contracts/` and `-- test/` both EMPTY. Only other working-tree change is the pre-existing, unrelated `scope.txt` (left untouched per the execution contract).

## Known Stubs

None. This is a paper-only SPEC decision doc — no code, no data wiring, no placeholders.

## Self-Check: PASSED

- FOUND: .planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-PLACEMENT-DECISION.md
- Commit hash recorded post-commit below.
