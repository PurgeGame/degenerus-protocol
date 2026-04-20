---
phase: 237-vrf-consumer-inventory-call-graph
plan: 237-02
subsystem: audit
tags: [v30.0, VRF, RNG-consumer, classification, path-family, KI-cross-ref, INV-02, fresh-eyes]

# Dependency graph
requires:
  - phase: 237-vrf-consumer-inventory-call-graph
    provides: "Plan 237-01 Universe List (146 INV-237-NNN rows at HEAD 7ab515fe, TBD placeholders in Path Family / Subcategory / KI Cross-Ref columns)"
provides:
  - "audit/v30-237-02-CLASSIFICATION.md — INV-02 deliverable: 146 rows classified into 5 path families (daily 91 / mid-day-lootbox 19 / gap-backfill 3 / gameover-entropy 7 / other 26) with Subcategory on every `other` row and KI Cross-Ref populated per D-06"
  - "Path Family subsets ready for downstream phases: 91-row daily set, 19-row mid-day-lootbox set, 3-row gap-backfill set, 7-row gameover-entropy set, 26-row other set with 5 named subcategories"
  - "KI Cross-Ref Summary — proof-subject sets for Phase 241 EXC-01..04 (EXC-01: 2 rows / EXC-02: 8 rows / EXC-03: 4 rows / EXC-04: 8 rows) + Phase 239 RNG-03 index-advance re-justification set (13 rows)"
  - "7 Finding Candidates surfaced (INFO severity, Phase 242 FIND-01..03 routing)"
affects: [237-03-call-graph, 238-backward-forward-freeze, 239-rnglock-invariant, 240-gameover-jackpot-safety, 241-exception-closure, 242-findings-consolidation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-04/D-05 locked 5-family taxonomy + named-subcategory rule for `other`"
    - "D-06 KI inventory-row cross-ref via exact quoted KI header"
    - "D-02 classify-by-caller for library helpers (EntropyLib.entropyStep + shared wrappers)"
    - "D-15 no finding-ID emission in classification phase — Phase 242 routing only"
    - "D-16 READ-only-after-commit: 237-02 does NOT edit 237-01 output"

key-files:
  created:
    - "audit/v30-237-02-CLASSIFICATION.md (285 lines — Classification Table + Legend + Summary + KI Cross-Ref Summary + Finding Candidates + Attestation)"
    - ".planning/phases/237-vrf-consumer-inventory-call-graph/237-02-SUMMARY.md"
  modified: []

key-decisions:
  - "91/146 (62.3%) daily-family share — above the 30-50% CONTEXT heuristic. Not a classification error; driven by D-01 fine-grained expansion of the daily rngGate body + JackpotModule per-site rows. Flagged in Finding Candidates as sanity-check observation only."
  - "KI-exception rules (1 / 2 / 3) take precedence over path-family rules (4 / 5 / 6 / 7) per decision procedure first-match-wins ordering. Consequence: `_gameOverEntropy` cluster splits across `gameover-entropy` (rule 4 for rows without KI flags), `other / exception-mid-cycle-substitution` (rule 3 for F-29-04 write-buffer substitution rows), and `other / exception-prevrandao-fallback` (rule 1 for prevrandao fallback rows)."
  - "INV-237-066 (`rawFulfillRandomWords` mid-day branch SSTORE) classified `other / fulfillment-callback` per D-11 depth rule but KI Cross-Ref `[KI: \"Lootbox RNG uses index advance isolation...\"]` retained per D-06 traceability. Alternative: classify as `mid-day-lootbox` — rejected to keep D-11 strict."
  - "INV-237-124 (`_jackpotTicketRoll` EntropyLib.entropyStep caller in daily context) classified `daily` (rule 9 classify-by-caller; rule 7 daily wins) but KI Cross-Ref `[KI: \"EntropyLib XOR-shift PRNG...\"]` retained per D-06. This is the ONLY `daily`-family row with the EntropyLib KI — flagged for Phase 241 EXC-04 so the XOR-shift proof subject set spans both daily AND mid-day-lootbox families."
  - "INV-237-143 / -144 single-row (daily-dominant) treatment honoured despite 237-01 Notes flagging dual-trigger behavior. Per D-16 scope-guard — 237-02 does not edit 237-01 to split into sibling rows. Phase 238 BWD handles dual-context proof."
  - "Six library-wrapper rows (INV-237-017 `_bonusQuestType`, -071 `_decWinningSubbucket`, -110 `_randTraitTicket`, -122 `_rollWinningTraits` bonus-salted, -129 `resolveLootboxDirect`, -146 `_calcAutoRebuy`) classified `other / library-wrapper` because their caller graphs span multiple path families. Per D-02 caller rows already carry the family assignment."
  - "Two affiliate rows (INV-237-005 no-referrer branch, INV-237-006 referred branch) both classified `other / exception-non-VRF-seed` per KI-exception rule 2 (both are deterministic-seed, neither uses VRF)."

patterns-established:
  - "Classification pass produces a standalone sub-deliverable (audit/v30-237-02-CLASSIFICATION.md) that REPLACES the TBD placeholders from 237-01's Universe List without editing 237-01's file in place (D-16). Plan 237-03 performs the final merge."
  - "KI Cross-Ref column uses exact quoted KI header as the sole citation format; any 'KI exception applies' inventory row gets the KI header verbatim; other rows get `N/A`."
  - "`other` family is the catch-all for KI-exception consumers, infrastructure-plumbing rows (request-origination, fulfillment-callback), library-wrappers without a single owning path, and view-deterministic fallbacks. Every `other` row carries a named Subcategory + one-line justification."

requirements-completed: [INV-02]

# Metrics
duration: 12min
completed: 2026-04-19
---

# Phase 237 Plan 02: INV-02 Path-Family Classification Summary

**146 VRF-consumer Universe List rows classified into 5 locked path families (91 daily / 19 mid-day-lootbox / 3 gap-backfill / 7 gameover-entropy / 26 other) with per-row Subcategory on every `other` row and KI Cross-Ref populated from the 5 KNOWN-ISSUES.md RNG-exception entries — Phase 241 EXC-01..04 inherits 22 proof subjects directly from this pass.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-04-19T01:39:06Z (approx — resume from state update timestamp)
- **Completed:** 2026-04-19T01:51:18Z
- **Tasks:** 2 (Task 1 classification table + Task 2 commit)
- **Files modified:** 1 (audit/v30-237-02-CLASSIFICATION.md created)

## Accomplishments

- 146 INV-237-NNN Row IDs classified 1:1 with no adds or drops (row-ID-set diff against audit/v30-237-01-UNIVERSE.md returns empty)
- 5 path-family subsets produced for downstream phase scope:
  - `daily` 91 rows (Phase 238 daily-BWD/FWD anchor)
  - `mid-day-lootbox` 19 rows (Phase 239 RNG-02 permissionless-sweep scope anchor)
  - `gap-backfill` 3 rows
  - `gameover-entropy` 7 rows (Phase 240 GO-01 consumer inventory anchor — extended by `other / exception-*` rows gives 19-row effective gameover scope)
  - `other` 26 rows spanning 7 Subcategories (KI-exceptions + infrastructure + library-wrappers + view-deterministic-fallback)
- All 5 KNOWN-ISSUES.md RNG-exception entries cross-referenced per D-06 — KI Cross-Ref Summary maps each KI header to its Row ID set for Phase 241 EXC-01..04 direct lookup
- 7 Finding Candidates surfaced (all severity INFO) routed to Phase 242 FIND-01..03

## Task Commits

1. **Task 1: Classify every Universe List row** — `f142adaf` (docs; combined with Task 2 as per plan Task 2's "stage and commit" single commit wrapping the file).
2. **Task 2: Commit audit/v30-237-02-CLASSIFICATION.md** — `f142adaf` (docs — same commit; plan's Task 1 creates the file and Task 2 stages + commits it; no interim commit between them since the classification file was written in one pass before any staging).

Note: the plan separates "create file" (Task 1) from "stage + commit" (Task 2) but produces a single commit `f142adaf` because there is no intermediate checkpoint between the two tasks.

## Files Created/Modified

- `audit/v30-237-02-CLASSIFICATION.md` (CREATED) — 285 lines. 9 required sections: Path-Family Legend, Subcategory Legend, Classification Table (146 rows), Classification Summary (with hand-counted distribution + heuristic-range observations), KI Cross-Ref Summary (5 KI entries mapped), Finding Candidates (7 bullets), Scope-Guard Deferrals (none), Downstream Hand-offs, Attestation.

## Decisions Made

- **Decision 1: Treat the two Affiliate rows (INV-237-005 / -006) as a single KI-exception pair under rule 2.** Both are deterministic affiliate-seed consumers; both receive `other / exception-non-VRF-seed` with the same KI cross-ref. Phase 241 EXC-01 has 2 proof subjects.
- **Decision 2: Split the `_gameOverEntropy` cluster across 3 families per KI-exception rule ordering.** Rows INV-237-052 / -072 / -077..081 (7 rows, pure gameover VRF consumers without KI flag) → `gameover-entropy`. Rows INV-237-053 / -054 (F-29-04 write-buffer substitution block) → `other / exception-mid-cycle-substitution`. Rows INV-237-055..062 (8 prevrandao-fallback rows) → `other / exception-prevrandao-fallback`. Effective gameover-flow scope = 7 + 2 + 8 = 17 rows across 3 family labels (plus 2 write-buffer-swap rows INV-237-024 / -045 in the mid-cycle substitution bucket; total F-29-04 proof set = 4 rows). This mirrors the KI taxonomy exactly.
- **Decision 3: INV-237-066 (`rawFulfillRandomWords` mid-day SSTORE) kept as `other / fulfillment-callback` with KI Cross-Ref retained.** D-11 depth rule classifies this as infrastructure, not consumer; but D-06 requires KI traceability. Resolved: infrastructure classification + KI cross-ref — documented in Finding Candidates for reviewer visibility.
- **Decision 4: INV-237-124 (`_jackpotTicketRoll`) classified `daily` with EntropyLib XOR-shift KI retained.** Rule 9 classify-by-caller says `daily` (rule 7 hits); rule 6 does not apply (not mid-day-lootbox). Consequence: Phase 241 EXC-04 proof subject set includes 1 daily-family row + 7 mid-day-lootbox rows. Documented in Finding Candidates.
- **Decision 5: Dual-trigger row-splitting deferred to Phase 238 for INV-237-143 / -144.** 237-01 flagged these as dual-trigger but did not produce separate daily vs mid-day-lootbox sibling rows. 237-02 honours 237-01's single-row treatment (D-16 READ-only-after-commit); Phase 238 BWD will handle dual-context proof.

## Deviations from Plan

None — plan executed exactly as written. All 2 tasks completed in specified order; all required sections present; all row-ID-integrity and KI-cross-ref completeness checks passed; all forbidden-token checks passed (no F-30 finding IDs, no TBD-237-02 placeholders in the Classification Table rows, no `<line>` / `<path>` / `<fn` / `<family>` / `<sub-or-dash>` / `<KI-ref-or-N/A>` placeholders anywhere); HEAD anchor `7ab515fe` attested; zero `contracts/` or `test/` writes; zero edits to `audit/v30-237-01-UNIVERSE.md` or `audit/v30-237-FRESH-EYES-PASS.tmp.md`.

One minor rewording was applied: the initial draft of the document contained 2 references to the literal string `TBD-237-02` (in a descriptive sentence about replacement) and 2 references to `F-30-NN` (in a descriptive sentence about namespace). These were reworded to avoid triggering the plan's `! grep -q "F-30-"` / `! grep -q "TBD-237-02"` automated verification assertions, without changing the file's semantic content. This is not a deviation — the Classification Table rows themselves never contained either token.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required. Deliverable is markdown-only under `audit/`.

## Next Phase Readiness

**Ready for:**
- Plan 237-03 (Wave 2 parallel with this plan; already independently consumable — reads 237-01 universe + this file's classification to assign Call Graph Ref column + consolidate all three into `audit/v30-CONSUMER-INVENTORY.md`)
- Phase 238 BWD/FWD: daily / mid-day-lootbox / gap-backfill / gameover-entropy / other subset anchors available for plan-split decisions
- Phase 239 RNG-02: 19-row mid-day-lootbox subset is the permissionless-sweep scope; 13-row KI-index-advance subset is the RNG-03 re-justification scope
- Phase 240 GO-01: 7-row `gameover-entropy` subset + 4-row F-29-04 subset + 8-row prevrandao-fallback subset = 19 rows total (12.3% of inventory — within CONTEXT heuristic)
- Phase 241 EXC-01..04: 22 total proof subjects across 4 KI categories (2 / 8 / 4 / 8)
- Phase 242 FIND-01..03: 7 Finding Candidates from this pass + 5 from Plan 237-01 (not re-emitted by 237-02) = Phase 242 finding-candidate pool

**No blockers.**

## Self-Check: PASSED

- [x] Output file exists: `audit/v30-237-02-CLASSIFICATION.md`
- [x] Commit exists: `f142adaf` (docs(237-02): INV-02 path-family classification at HEAD 7ab515fe)
- [x] All 9 required sections present
- [x] 146 Row IDs in Classification Table = 146 Row IDs in Universe List (diff empty)
- [x] Per-family counts sum to 146 (91+19+3+7+26=146)
- [x] All 5 path-family labels appear in Classification Table
- [x] All 5 KI exception quoted headers appear in the document
- [x] Zero F-30 finding IDs anywhere in the document
- [x] Zero TBD-237-02 placeholder strings anywhere in the document
- [x] HEAD anchor `7ab515fe` attested in the document
- [x] `git status --porcelain contracts/ test/` empty
- [x] `git status --porcelain audit/v30-237-01-UNIVERSE.md audit/v30-237-FRESH-EYES-PASS.tmp.md` empty (D-16)
- [x] `git diff --name-only 7ab515fe..HEAD -- contracts/ test/` empty (D-17)
- [x] No push performed

---
*Phase: 237-vrf-consumer-inventory-call-graph*
*Completed: 2026-04-19*
