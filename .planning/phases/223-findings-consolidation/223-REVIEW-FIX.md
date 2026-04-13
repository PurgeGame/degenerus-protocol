---
phase: 223-findings-consolidation
fixed_at: 2026-04-12T00:00:00Z
review_path: .planning/phases/223-findings-consolidation/223-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 223: Code Review Fix Report

**Fixed at:** 2026-04-12
**Source review:** `.planning/phases/223-findings-consolidation/223-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (6 INFO from REVIEW.md + 1 cross-doc consistency fix on `.planning/ROADMAP.md:10`)
- Fixed: 7
- Skipped: 0

All 6 REVIEW.md INFO findings were applied as described, plus the
operator-supplied cross-document consistency fix flipping the v27.0
milestone marker in `.planning/ROADMAP.md` from 🚧 in-progress to ✅
shipped (matches `PROJECT.md` Completed Milestone and
`.planning/MILESTONES.md` "Shipped: 2026-04-13" header).

## Fixed Issues

### IN-01: F-27-16 sub-point B cites stale line range for `scripts/coverage-check.sh` LCOV_FILE missing-file path

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `1f1637e6`
**Applied fix:** Updated F-27-16 sub-point B line reference from
`scripts/coverage-check.sh:200-204` to `:230-232` (current post-fix
location after Plan 222-03's preflight matrix parser shift) and
appended ` (post-fix; IN-222-04 originally reported :200-204 pre-fix)`
to preserve the pre-fix anchor. Matches dual citation convention of
F-27-07, F-27-08, F-27-14.

### IN-02: `Audit Date: 2026-04-13` forward-dated relative to verification timestamps

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `2765d2e7`
**Applied fix:** Changed `**Audit Date:** 2026-04-13` to
`**Audit Date:** 2026-04-12` on line 3 to match the
222-VERIFICATION.md `verified: 2026-04-12T00:00:00Z` timestamp cited
inside F-27-13 and F-27-14 Status blocks.

### IN-03: Executive Summary conflates must-haves-verified with finding-tier counts

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `5e54efaf`
**Applied fix:** Rewrote the phase-verdict sentence on line 21 to
separate must-have scores (9/9, 13/13, 4/4) from raw-review finding
counts and consolidated INFO counts. New form: "Phase N satisfied
X/Y must-have truths with R raw findings consolidated into C INFO
entries."

### IN-04: "Five observations resolved in-cycle" uses unflagged sub-point-level count

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `576cb026`
**Applied fix:** Expanded the sentence to read "Five sub-point-level
Status markers (covering four finding-ID-level entries: F-27-07,
F-27-08, F-27-13 [two sub-points], F-27-14) were resolved in-cycle
and carry resolving commit shas below." This makes the 5-vs-4
counting rule explicit without changing the Audit Trail table.

### IN-05: F-25-08 regression row line range + "1-bit bias" paraphrase

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `1d41773d`
**Applied fix:** Updated line range from
`DegenerusGameAdvanceModule.sol:1191-1221` to `:1200-1224` (the
`_getHistoricalRngFallback` function body) with `:1189-1199` noted
as the docstring range. Replaced the paraphrase "1-bit bias" with
the verbatim source-comment quote "1-bit validator manipulation"
(line 1192). Single-quoted style converted to double-quote.

Verified against live source: `DegenerusGameAdvanceModule.sol:1189`
opens the docstring, `:1192-1193` contains "1-bit validator
manipulation", `:1200-1224` spans the function body (signature at
`:1200`, closing brace at `:1224`), `keccak256(...)` construction
at `:1220-1222`.

### IN-06: F-27-14 pre-fix line annotations missing current-tree location

**Files modified:** `audit/FINDINGS-v27.0.md`
**Commit:** `8fcd8ca6`
**Applied fix:** Appended post-fix location to F-27-14's Function
field: "`check_matrix_drift` `:89-164` (pre-fix, specifically the
global `grep -qF` at `:104`; post-fix the function lives at
`:118-164` after the preflight matrix parser was inserted above)."
Verified against live source: `check_matrix_drift()` opens at
`scripts/coverage-check.sh:118`.

### Cross-doc fix: ROADMAP v27.0 milestone marker

**Files modified:** `.planning/ROADMAP.md`
**Commit:** `106cd102`
**Applied fix:** Changed line 10 from
`- 🚧 **v27.0 Call-Site Integrity Audit** — Phases 220-223 (in progress)`
to
`- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)`.
Aligns with the Phases table below (which already marks 220-223 as
Complete) and with `PROJECT.md` and `.planning/MILESTONES.md` which
both record v27.0 as shipped 2026-04-13.

## Skipped Issues

None — all 7 in-scope findings were applied cleanly.

---

_Fixed: 2026-04-12_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
