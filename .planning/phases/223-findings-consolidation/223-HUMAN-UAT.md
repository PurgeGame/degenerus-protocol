---
status: partial
phase: 223-findings-consolidation
source: [223-VERIFICATION.md]
started: 2026-04-12T00:00:00Z
updated: 2026-04-12T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Reconcile FINDINGS-v27.0.md Audit Date vs re-verification date
expected: Either change `Audit Date: 2026-04-13` to `2026-04-12` to match the 222-VERIFICATION.md `verified: 2026-04-12T00:00:00Z` timestamp cited in F-27-13/F-27-14 Status blocks, OR add a one-line clarification that 2026-04-13 is the publication target date
result: [pending]

### 2. Fix stale line reference in F-27-16 sub-point B
expected: Sub-point B currently cites `scripts/coverage-check.sh:200-204` (pre-fix line range). Post-fix the LCOV_FILE missing-file WARN logic lives at `:230-232` after Plan 222-03's 45-line preflight matrix parser shift. Update to current lines or add `(pre-fix)` marker matching F-27-14's convention.
result: [pending]

### 3. Clarify Executive Summary count ambiguity
expected: Executive Summary line 21 interleaves must-haves-verified counts (9/9, 13/13, 4/4) with finding-tier breakdowns (3 WR + 5 IN etc.) inside the same parenthetical. Suggested rewrite separates the two metrics or user confirms current compact form is acceptable.
result: [pending]

### 4. Reconcile "5 observations resolved in-cycle" vs 4 finding-ID-level Resolved markers
expected: Executive Summary says "Five observations were resolved in-cycle" but grep for `Status: Resolved` returns 5 sub-point-level hits mapping to 4 finding IDs (F-27-07, F-27-08, F-27-13 [2 sub-points], F-27-14). Add a footnote "(counted at sub-point granularity)" or rephrase.
result: [pending]

### 5. Tighten F-25-08 evidence quote and line range
expected: F-25-08 regression row cites `DegenerusGameAdvanceModule.sol:1191-1221` and quotes 'prevrandao adds unpredictability at the cost of 1-bit bias'. Actual function body is :1200-1224 (docstring at :1189-1199) and the verbatim comment at :1192 reads '1-bit validator manipulation', not '1-bit bias'. Quoted text should match verbatim or drop single-quotes.
result: [pending]

### 6. Add post-fix location marker for F-27-14 Function field
expected: F-27-14 Function field reads `check_matrix_drift` `:89-164` (pre-fix). Auditor navigating current tree goes to :89 and finds the preflight parser, not the drift-check function (now at :118-164). Append post-fix location matching the convention used in F-27-07/F-27-08.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
