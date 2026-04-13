---
phase: 223-findings-consolidation
reviewed: 2026-04-12T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - audit/FINDINGS-v27.0.md
  - KNOWN-ISSUES.md
findings:
  critical: 0
  warning: 0
  info: 6
  total: 6
status: issues_found
---

# Phase 223: Code Review Report

**Reviewed:** 2026-04-12T00:00:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Both documents were reviewed against their source artifacts
(220/221/222 REVIEW.md, 222-VERIFICATION.md), the sibling template
(`audit/FINDINGS-v25.0.md`), and the live codebase. No broken internal
references, severity/status inconsistencies, or factual contradictions
between KNOWN-ISSUES.md and the F-27-NN entries it cites.

All 16 F-27-NN identifiers (01-16) are defined in-document; the F-25-NN
regression appendix covers the full v25.0 catalog (01-13). All four
resolution SHAs cited (`f799da98`, `ef83c5cd`, `e0a1aa3e`, `e4064d67`)
exist in `git log` and correspond to their described fixes. The
"5 observations resolved in-cycle" Executive Summary tally reconciles to
the per-sub-point breakdown in the Audit Trail (2 for Phase 221 +
3 for Phase 222 = 5). Structural parity with v25.0 is tight (same
heading levels, same field table per finding, same Executive Summary
and Audit Trail tables, same Regression Appendix shape).

Six informational observations are filed:

- One factual-drift hit where a cited line range is stale against the
  current `scripts/coverage-check.sh` after the in-cycle fix
  (`F-27-16` sub-point B).
- One forward-dated `Audit Date` field (2026-04-13 while today is
  2026-04-12) -- intentional publication target or typo, worth a
  one-line clarification.
- One clarity snag where the Executive Summary interleaves two
  different metrics (must-haves verified vs. finding tier breakdown)
  inside the same parenthetical, which is prone to misreading as
  "9 findings" / "13 findings".
- One inconsistency between finding-ID-level ("4 resolved") and
  sub-point-level ("5 observations resolved") counting of the in-cycle
  resolutions -- internally self-consistent, but the two counts are
  adjacent in the document without cross-reference.
- One stale-line-reference in the F-25-08 regression row where the
  cited range starts mid-docstring rather than at the function
  signature, and the quoted comment phrase ("1-bit bias") is a close
  paraphrase rather than a verbatim quote from the code.
- One imprecision in the pre-fix `:89-164` / `:104` line annotations
  on F-27-14: the "(pre-fix)" qualifier is correct but the current
  live `check_matrix_drift` location (line 118) is not mentioned, so
  an auditor navigating the doc without checking out the old commit
  will not find the cited lines.

No source file was modified. Review is read-only.

## Info

### IN-01: F-27-16 sub-point B cites stale line range for `scripts/coverage-check.sh` LCOV_FILE missing-file path

**File:** `audit/FINDINGS-v27.0.md:297`
**Issue:** F-27-16 sub-point B states "`scripts/coverage-check.sh:200-204`"
when describing the "`lcov.info` not found -> YELLOW WARN" skip path.
The live file puts that logic at lines 230-232 (the `if [[ ! -f
"$LCOV_FILE" ]]; then printf ... WARN ... skipping REGRESSED_COVERAGE
check` block). Lines 200-204 in the current file are the `gsub_trim`
helper, unrelated to the finding. This is the original line number
from the 222-REVIEW.md (which also cites `:200-204`, IN-04 at line
318), faithfully transcribed. The drift is a side-effect of the
in-cycle fix commit `e0a1aa3e` (contract-scoped drift mode) which
added a ~45-line preflight matrix parser earlier in the file and
shifted the subsequent line numbers down. The fix is to bump the
reference to the current `:230-232` (or an equivalent range that
spans the WARN `printf` and the `return 0` that follows), matching
the convention used elsewhere in v27.0 where line references point
to current-tree locations unless explicitly marked "pre-fix".

**Fix:** Update sub-point B to read `scripts/coverage-check.sh:230-232`
(or `:230-236` if you want to include the documentation header at
lines 24-25 it cross-references). If keeping the original
`:200-204`, add the "(pre-fix)" marker used elsewhere in the doc
(e.g., F-27-14's "`check_matrix_drift` `:89-164` (pre-fix ...)").

### IN-02: `Audit Date: 2026-04-13` is one day in the future relative to today (2026-04-12)

**File:** `audit/FINDINGS-v27.0.md:3`
**Issue:** Line 3 reads "**Audit Date:** 2026-04-13" but today is
2026-04-12 (per system clock and the latest git commit date). The
neighboring `Methodology` paragraph and both the F-27-13 and F-27-14
Status blocks reference "re-verified ... on 2026-04-12" -- the
audit is internally dated on the day AFTER the verification. This is
either a publication-target date (the doc goes live tomorrow) or a
one-digit typo from 12 to 13. Either is defensible; the drift is
with the 222-VERIFICATION.md `verified: 2026-04-12T00:00:00Z` stamp
cited twice in the body. Not a correctness issue, but a reader who
cross-checks timestamps may wonder whether the document claims to
describe work that was done after it was written.

**Fix:** Either (a) change `Audit Date:` to `2026-04-12` to match the
re-verification dates in F-27-13 / F-27-14, or (b) add a one-line
clarification that the date is the publication target and work was
completed 2026-04-12.

### IN-03: Executive Summary conflates must-haves-verified with finding-tier counts inside one parenthetical

**File:** `audit/FINDINGS-v27.0.md:21`
**Issue:** The sentence "Phase 220 passed code review 9/9 (3 WR + 5
IN, all INFO-class), Phase 221 closed 13/13 (2 WR **resolved
in-cycle** + 3 IN), Phase 222 re-verified 4/4 after Plan 222-03
landed the two VERIFICATION-gap fixes (4 WR, 2 of which were also
the two verification gaps, plus 6 IN)." uses X/Y for must-haves
verified (sourced from each phase's VERIFICATION.md `score` field
-- 9/9, 13/13, 4/4) and then splits finding counts inside the
parenthetical. A reader not familiar with the must-have framework
will reasonably assume "9/9" and "13/13" are finding counts, then
get confused when the parenthetical shows `3 WR + 5 IN = 8` and
`2 WR + 3 IN = 5`. The Audit Trail section (lines 344-349)
disambiguates correctly ("8 raw (3 WR + 5 IN) / 6 consolidated
INFO") but the Executive Summary is the document's high-level
pitch; ambiguity there is felt.

**Fix:** Rewrite along the lines of "Phase 220 satisfied 9/9
must-have truths with 3 WR + 5 IN raw review findings consolidated
to 6 INFO entries; Phase 221 satisfied 13/13 with 2 WR + 3 IN
consolidated to 5 INFO (2 resolved in-cycle); Phase 222 satisfied
4/4 after ..." -- separating the must-have metric from the finding
breakdown.

### IN-04: "Five observations resolved in-cycle" uses sub-point-level counting that is not flagged to the reader

**File:** `audit/FINDINGS-v27.0.md:21`
**Issue:** The Executive Summary sentence "Five observations were
resolved in-cycle and carry resolving commit shas below" counts
F-27-13 as two items (sub-point A resolved by `ef83c5cd`, sub-point
B resolved by `ef83c5cd`), producing 2 (Phase 221: F-27-07, F-27-08)
+ 3 (Phase 222: F-27-13/A, F-27-13/B, F-27-14) = 5. The Audit Trail
at line 348 uses the same sub-point-level count ("3 resolved
in-cycle" for Phase 222). But the reader scanning the Findings
section and grepping for "Status: Resolved" will find only four
finding-ID-level entries marked Resolved (F-27-07, F-27-08, F-27-13,
F-27-14), because F-27-13's two sub-point Status lines live inside
the same finding. The 5-vs-4 mismatch is internally consistent once
the counting rule is understood, but there is no in-document
footnote or cross-reference making the rule explicit. Contrast with
the "(A/B)" breakdown used elsewhere in the same finding.

**Fix:** Either (a) add a one-line aside after "Five observations
were resolved in-cycle" -- e.g., "(counted at sub-point
granularity; F-27-13 contributes two)" -- or (b) change the count
to match finding-ID granularity ("Four findings carry resolving
commit shas; F-27-13 contains two sub-points both closed by
commit `ef83c5cd`").

### IN-05: F-25-08 regression row cites line range `:1191-1221` that starts inside the docstring, and "1-bit bias" is a paraphrase rather than a verbatim code quote

**File:** `audit/FINDINGS-v27.0.md:372`
**Issue:** The F-25-08 regression evidence reads "Gameover
historical-VRF + `block.prevrandao` fallback still present at
`DegenerusGameAdvanceModule.sol:1191-1221` (see comment 'prevrandao
adds unpredictability at the cost of 1-bit bias' and the
`keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))`
construction at `:1221`)." Two minor issues: (1) line 1191 in the
live file is inside the docstring (`///      with currentDay and
block.prevrandao. Historical words are committed VRF`) -- the actual
function signature `_getHistoricalRngFallback` is at line 1200, and
the function body ends at line 1224. A tighter range would be
`:1200-1224` (function body) or `:1189-1224` (docstring + function).
(2) The quoted phrase "1-bit bias" does not appear verbatim in the
code -- the live comment at line 1192-1193 reads "prevrandao adds
unpredictability at the cost of 1-bit validator manipulation". The
quoted phrase is a reasonable shortening but the single-quotes
around it signal a verbatim quote; most auditors will paste-grep
for the exact string and come up empty.

**Fix:** Update evidence line to `_getHistoricalRngFallback` still
present at `DegenerusGameAdvanceModule.sol:1200-1224` (docstring
:1189-1199) with the `keccak256(abi.encodePacked(combined, currentDay,
block.prevrandao))` construction at `:1221` and the "1-bit validator
manipulation" trade-off noted in the docstring at `:1192-1194`. Drop
the single-quotes around the paraphrase or replace with the
verbatim text.

### IN-06: F-27-14 "pre-fix" line annotations do not include current-tree location for reader navigation

**File:** `audit/FINDINGS-v27.0.md:258`
**Issue:** F-27-14's Function field reads "`check_matrix_drift`
`:89-164` (pre-fix, specifically the global `grep -qF` at `:104`)".
The "(pre-fix)" marker correctly signals that the line numbers
predate the in-cycle fix (commit `e0a1aa3e`), but the current-tree
location of `check_matrix_drift` (line 118) is not noted anywhere
in the finding. An auditor without a checkout of the pre-fix tree
will scroll `scripts/coverage-check.sh` to line 89 and find the
preflight matrix parser instead of the drift-check function. The
Status block at the bottom of F-27-14 describes the fix in detail
but also refers to the old semantics ("Script length: 285 lines
(<= 300-line budget)") without anchoring the reader to the new
starting line. Contrast with F-27-07 and F-27-08 which cite both
pre-fix line numbers and the post-fix `:29-32` / `fail_total == 0`
anchor.

**Fix:** Add a parenthetical to the Function field: "`check_matrix_drift`
`:89-164` (pre-fix, specifically the global `grep -qF` at `:104`;
post-fix the function lives at `:118-164`)" -- or add a line to the
Status block noting the post-fix location.

---

_Reviewed: 2026-04-12T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
