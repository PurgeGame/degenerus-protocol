---
phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa
plan: 02
subsystem: audit
tags: [rng-audit-kit, vrf-freeze, freeze-invariant-target, exempt-entries, multi-round-protocol, no-answer-key, documentation, package-only, layout-b]

# Dependency graph
requires:
  - phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa
    plan: 01
    provides: "RNG-AUDIT-KIT.md with the cold-start context pack 4a-4e + the reserved protocol-head placeholder block; 337-ANCHOR-ATTESTATION.md as the HEAD-resolved anchor source-of-truth"
  - phase: 334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu
    provides: "the locked R1->R4 round semantics (§3), the exempt-set table (§2), the canonical freeze-invariant target (§1), and the no-answer-key / package-only / model-agnostic framing (§5) the kit fills"
provides:
  - "audit/rng-audit-kit/RNG-AUDIT-KIT.md §1 — the freeze-invariant TARGET stated verbatim (canonical '+' form) as the external auditor's single goal (RNGAUDIT-01)"
  - "audit/rng-audit-kit/RNG-AUDIT-KIT.md §2 — the 4 exempt VRF-window writers with HEAD anchors + one-line structural reasons (RNGAUDIT-01)"
  - "audit/rng-audit-kit/RNG-AUDIT-KIT.md §3 — the R1->R4 self-driven multi-round adversarial protocol with NO answer key (RNGAUDIT-02)"
  - "The assembled paste-into-model file now reads: invariant target -> exempt set -> R1->R4 -> 337-01 context pack"
affects: [337-03-chunk-manifest-and-packaging, 337-04-anchor-resolution-lint, 338-terminal-internal-sweep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Question-not-answer authoring: §1 states the target property as the auditor's goal; the freeze verdict is withheld and assigned to the model's R4 output"
    - "Exempt-set as the single allowed near-conclusion: §2 names WHERE the legitimate resolution writes live (structural orientation) without asserting the freeze status of anything else"
    - "Model-output framing for round semantics: R2 ships the three classification CATEGORIES (frozen / reverts-if-written-during-lock / proven-non-participating) as the choice the model makes, never pre-filled per slot"
    - "Paraphrase-the-prohibition discipline: answer-key constraints are described without reproducing any forbidden literal token, so the literal lints stay at zero"

key-files:
  created: []
  modified:
    - audit/rng-audit-kit/RNG-AUDIT-KIT.md

key-decisions:
  - "Used the REQUIREMENTS.md / ROADMAP SC1 '+' wording VERBATIM as the kit's canonical freeze-invariant target (the 334 sketch §1 used the 'and' form); deliberately converged on the '+' form so it matches the 337-04 lint's exact grep target"
  - "The exempt-entry table cites the HEAD anchors from 337-ANCHOR-ATTESTATION.md (advanceGame:154 / rawFulfillRandomWords:1735 / retryLootboxRng:1105 / rngGate:1152, all in the v50-UNCHANGED AdvanceModule) — spot-resolved each at HEAD before shipping"
  - "Both plan tasks edit the same single file as one indivisible protocol-head insertion, so they landed in ONE atomic docs commit covering RNGAUDIT-01 + RNGAUDIT-02 (rather than splitting one continuous markdown insertion with prohibited partial-staging / git-stash)"
  - "Heeded the Wave-1 lint lesson: every answer-key prohibition in the prose is PARAPHRASED ('our internal findings/catalog documents', 'evades the lock' instead of 'no escape', 'what the answer should be' instead of a verdict) so the literal answer-key + self-containment greps return zero"

patterns-established:
  - "Pattern: the R3 zero-day-hunter leg references the METHODOLOGY (cross-module state composition + edge-of-lifecycle) as a method to apply against THIS subject, explicitly NOT as a source of pre-existing findings"
  - "Pattern: R4 instructs an explicit 'no issue found, here is why' result (do-not-inflate AND do-not-stay-silent) mirroring the EXTERNAL-AUDIT-PROMPT tone but stricter (no pre-stated conclusions)"

requirements-completed: [RNGAUDIT-01, RNGAUDIT-02]

# Metrics
duration: 6min
completed: 2026-05-28
---

# Phase 337 Plan 02: RNGAUDIT Protocol Head (Invariant Target + Exempt Set + R1->R4) Summary

**Prepended the protocol head into RNG-AUDIT-KIT.md — the freeze-invariant TARGET stated verbatim ('+' form) as the external auditor's single goal (§1), the 4 exempt VRF-window writers with HEAD anchors (§2), and the R1->R4 self-driven multi-round adversarial protocol with no answer key (§3) — so the assembled file reads invariant -> exempt -> R1->R4 -> context pack, lint-clean.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-28T19:58:10Z
- **Completed:** 2026-05-28T20:04:xxZ
- **Tasks:** 2 (landed in one atomic commit — see Deviations)
- **Files modified:** 1 (`RNG-AUDIT-KIT.md`)

## Accomplishments
- Authored `## 1 — The Freeze Invariant (Your Target)`: a short "this kit drives YOU, an external model" framing, the canonical invariant string VERBATIM as a blockquote (the REQUIREMENTS '+' form), the operational restatement from the 334 sketch §1, the terminal-`_livenessTriggered`-freeze pointer, and an explicit "this kit does NOT tell you whether the property is satisfied — reaching that verdict is your job." No freeze verdict stated.
- Authored `## 2 — Exempt Entry Points (the legitimate VRF-window writers)`: a 4-row table (Exempt entry · HEAD anchor · structural reason) for advanceGame() (`AdvanceModule.sol:154`), rawFulfillRandomWords (`:1735` / facade `DegenerusGame.sol:2226`), retryLootboxRng() (`:1105` / facade `:2177`), rngGate(...) (`:1152`), framed as the ONE allowed near-conclusion (structural orientation, not a verdict).
- Authored `## 3 — The Protocol (Multi-Round, Self-Driven)`: the blind-review + single-multi-turn-session + persist-your-R1-catalog framing, the verbatim-in-spirit no-answer-key statement ("you are given the codebase, the methodology, and the invariant target — and nothing about what the answer should be ... a different perspective is the entire point"), then the four exact-heading rounds:
  - **R1 — Catalog the VRF Read-Graph:** enumerate every participating slot + writers + readers across all 11 modules + Storage + facade + peripherals, built FROM the context pack ("you build this catalog — you are not handed a pre-built answer").
  - **R2 — Independently Re-Derive Each Slot's Freeze Status:** classify each slot into one of the three OUTPUT categories (frozen / reverts-if-written-during-lock / proven-non-participating) re-derived from source; the kit pre-fills none.
  - **R3 — Adversarially Challenge the Catalog:** the zero-day-hunter leg — hunt for a single writer that evades the lock and any cross-module composition that does; emulate the zero-day-hunter METHOD (cross-module state composition + edge-of-lifecycle states) explicitly NOT as pre-existing findings.
  - **R4 — Reconcile and Report:** reconcile R2 vs R3, resolve every discrepancy, report the verified per-slot status + any evasion in the model's own words, state "no issue found" explicitly where none, cite file:line for every claim.
- Verified the assembled order (§1 line 30 -> §2 line 44 -> §3 line 57 -> R1..R4 lines 69/73/83/97 -> Context Pack 4a line 113) and that all 4 exempt anchors resolve exactly at HEAD.

## Task Commits

Both tasks edit the SAME single file as one indivisible protocol-head insertion (see Deviations); they landed in one atomic docs commit:

1. **Task 1 (RNGAUDIT-01: invariant target + exempt set) + Task 2 (RNGAUDIT-02: R1->R4 protocol)** - `59d373a3` (docs) — `docs(337-02): prepend RNGAUDIT-01/02 protocol head into RNG-AUDIT-KIT.md`

**Plan metadata:** (this bookkeeping commit) (docs: complete plan)

## Files Created/Modified
- `audit/rng-audit-kit/RNG-AUDIT-KIT.md` (137 -> 206 lines; +77/-8) - Prepended the protocol head (§1 invariant target, §2 exempt-entry table, §3 R1->R4 protocol) into the reserved block ABOVE the 337-01 context pack. The context pack (4a-4e) is unchanged.

## Decisions Made
- **Canonical freeze-invariant string = the REQUIREMENTS '+' form, VERBATIM.** RESEARCH §8 flagged the open `+`-vs-`and` mismatch (334 sketch §1 used "and"). Shipped the '+' form because RNGAUDIT-01 is the acceptance bar and the 337-04 lint greps that exact string. `grep -cF` of the '+' string returns 1; `grep -c` of the 'and' form returns 0.
- **Exempt anchors drawn from 337-ANCHOR-ATTESTATION.md and spot-resolved at HEAD.** All four exempt entries live in `DegenerusGameAdvanceModule.sol`, which v50 did NOT touch, so the lines are byte-identical to the pre-v50 baseline; `sed -n` confirmed `:154` advanceGame, `:1735` rawFulfillRandomWords, `:1105` retryLootboxRng, `:1152` rngGate, plus the facade dispatches `:2226` / `:2177`.
- **One atomic commit for both tasks.** The two tasks insert one continuous protocol head into one file; splitting it would require prohibited partial-staging / `git stash`. The single commit names both RNGAUDIT-01 and RNGAUDIT-02 for traceability.

## Deviations from Plan

### Process deviation (not a code change)

**1. [Process] Both plan tasks landed in ONE atomic commit**
- **Reason:** Tasks 1 (sections 1-2) and 2 (section 3) edit the same single file `RNG-AUDIT-KIT.md` as one indivisible protocol-head insertion above the context pack. Committing them separately after both edits were applied would require sub-file partial staging or `git stash`, both of which are avoided per the destructive-git discipline.
- **Resolution:** Single `docs(337-02)` commit `59d373a3` whose message enumerates both RNGAUDIT-01 (§1+§2) and RNGAUDIT-02 (§3). Each task's `<automated>` verify chain was run and PASSED independently before the commit.
- **Impact:** Zero substantive impact; full traceability preserved in the commit body. Zero scope creep, zero `contracts/` impact.

### Lint-trap avoidance (proactive, per the Wave-1 lesson)

**2. [Discipline] Paraphrased every answer-key prohibition to keep the literal lints at zero**
- **Context:** Wave 1 (337-01) twice self-tripped the literal greps by reproducing forbidden strings inside *prohibition* sentences. The plan's critical-lesson block forbade reproducing `FINDINGS-v...`, `audit/FINDINGS`, `RNGLOCK-CATALOG`, and freeze-VERDICT phrasings ("no escape", "the invariant holds", "safe by construction", "is frozen because") in any prose that ships.
- **What I did:** Referred to the withheld answer key as "our internal findings/catalog documents"; phrased the R3 hunt target as a writer that "evades the lock" / "mutates ... without reverting" (never "no escape"); described the no-answer-key constraint as "nothing about what the answer should be" (never a verdict). The ONE canonical exception — the '+' freeze-invariant target string — IS present verbatim (it is the auditor's target, not a verdict).
- **Verification:** the Task-2 whole-file no-answer-key lint and the self-containment lint both return 0 matches; a broader skeptic sweep (`we found|we confirmed|frozen because|proven safe`) also returns 0.

---

**Total deviations:** 1 process (two tasks -> one commit), 1 proactive discipline note (lint-trap avoidance). Zero `contracts/*.sol` modified.

## Verification Results

All acceptance criteria and `<automated>` verify chains pass:

**Task 1 (RNGAUDIT-01):**
- canonical '+' invariant string present verbatim exactly once: `grep -cF` -> 1 ✅
- '+' form not 'and': `grep -c 'VRF word and its deterministic derivations'` -> 0 ✅
- all 4 exempt anchors present: `grep -cE 'AdvanceModule.sol:154|...:1735|...:1105|...:1152'` -> 8 (>= 4) ✅
- no freeze verdict: `grep -riE 'the invariant holds|we verified|no (writer )?escape'` -> 0 ✅
- automated chain -> PASS

**Task 2 (RNGAUDIT-02):**
- 4 round headings: `grep -cE '^### R[1-4] '` -> 4 ✅
- R1 references context pack: `grep -c 'Context Pack'` -> 10 (>= 1) ✅
- R3 names zero-day method: `grep -ci 'zero-day'` -> 2 (>= 1) ✅
- no-answer-key whole-file lint: `grep -riE 'FINDINGS-v[0-9]|audit/FINDINGS|RNGLOCK-CATALOG|safe by construction|no (writer )?escape|the invariant holds|is frozen because'` -> 0 ✅
- R2 output category present: `grep -cE 'reverts-if-written-during-lock'` -> 1 (hand-confirmed: presented as one of three classification options the model selects, NOT a per-slot verdict) ✅
- automated chain -> PASS

**Prompt success criteria:**
- canonical '+' string verbatim present; 'and' form absent ✅
- self-containment + no-answer-key greps return 0 over `audit/rng-audit-kit/` ✅
- zero `contracts/*.sol` modified (`git diff --name-only HEAD -- contracts/` empty) ✅
- assembled order invariant -> exempt -> R1->R4 -> context pack ✅
- file >= 200 lines (206); `contains: "while \`rngLockedFlag = true\`"` satisfied ✅

## Issues Encountered
- The kit directory `audit/rng-audit-kit/` is gitignored but force-tracked (337-01 added the file with `-f`); the already-tracked `RNG-AUDIT-KIT.md` committed normally via `git add` despite the addIgnoredFile hint. No `-f` re-add was needed for an already-tracked path.

## User Setup Required
None - documentation-only deliverable; no external service configuration, no package installs.

## Next Phase Readiness
- **337-03** can author `CHUNK-MANIFEST.md` (the human-ops feeding manual) referencing the 4d inventory + the per-file sizes from RESEARCH §5; the paste-into-model artifact (`RNG-AUDIT-KIT.md`) is now structurally complete (protocol head + context pack).
- **337-04** anchor-resolution + no-answer-key + self-containment + freeze-invariant-verbatim lints all currently return their passing values over the kit; the canonical '+' string is the exact freeze-invariant grep target.
- No blockers. `contracts/*.sol` untouched.

## Self-Check: PASSED

- FOUND: audit/rng-audit-kit/RNG-AUDIT-KIT.md (modified; 206 lines)
- FOUND: .planning/phases/337-audit-protocol-author-the-model-agnostic-multi-round-externa/337-02-SUMMARY.md
- FOUND commit: 59d373a3 (Task 1 + Task 2 protocol head)
- canonical '+' invariant string verbatim == 1; 'and' form == 0
- no-answer-key + self-containment lints == 0 over audit/rng-audit-kit/
- zero contracts/*.sol modified

---
*Phase: 337-audit-protocol-author-the-model-agnostic-multi-round-externa*
*Completed: 2026-05-28*
