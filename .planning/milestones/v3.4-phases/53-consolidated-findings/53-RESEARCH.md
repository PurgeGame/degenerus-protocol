# Phase 53: Consolidated Findings - Research

**Researched:** 2026-03-21
**Domain:** Audit findings consolidation, severity classification, master table construction
**Confidence:** HIGH

## Summary

Phase 53 consolidates all v3.4 audit findings from Phases 50-52 into a single master table, sorted by severity, and includes outstanding v3.2 LOW/INFO findings for completeness. This is a documentation-only phase with no code changes.

The v3.4 audit produced 5 new findings across Phases 50-51 (0 HIGH, 1 MEDIUM, 0 LOW, 4 INFO). Phase 52 (invariant test suite) produced no findings -- it produced test infrastructure only. The outstanding v3.2 findings comprise 30 items (6 LOW, 24 INFO) from the prior consolidated report (audit/v3.2-findings-consolidated.md). Combined, the master table will contain 35 findings.

**Primary recommendation:** Follow the established Phase 43 consolidated findings pattern -- single deliverable in `audit/v3.4-findings-consolidated.md` with executive summary, master table sorted by severity, per-contract counts, and per-phase summaries. Include a cross-reference section linking to the v3.2 consolidated findings rather than duplicating all 30 items inline.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIND-01 | All v3.4 findings consolidated with severity, contract, line ref, and recommendation | Complete findings inventory from Phases 50-52 documented below; Phase 43 format established as template |
| FIND-02 | Outstanding v3.2 LOW/INFO findings included in master list for completeness | v3.2-findings-consolidated.md contains 30 findings (6 LOW, 24 INFO); carry forward by reference or inline |
| FIND-03 | Master findings table sorted by severity for manual triage before C4A | Sort order: MEDIUM > LOW > INFO; v3.4 has 1 MEDIUM (new highest for this milestone) |
</phase_requirements>

## Standard Stack

Not applicable -- this phase is documentation-only. No libraries, frameworks, or tooling needed. The deliverable is a Markdown document.

## Architecture Patterns

### Established Consolidation Pattern (Phase 43 Precedent)

Phase 43 (v3.2 consolidated findings) established the canonical format for this project's consolidated findings documents. Phase 53 MUST follow the same structure for consistency.

**Canonical deliverable location:** `audit/v3.4-findings-consolidated.md`

**Required sections (from Phase 43 pattern):**
1. Header Block (milestone, date, scope, mode)
2. Executive Summary Table (total counts by severity, by category, by phase)
3. Deduplication Notes (if applicable -- check for overlaps between Phase 50 and 51 findings)
4. Master Findings Table (sorted by severity: MEDIUM > LOW > INFO)
5. Per-Contract Summary Table
6. Per-Phase Summary (one paragraph per phase with verdict and finding count)
7. Recommended Fix Priority (HIGH/MEDIUM/LOW action groupings)
8. Outstanding v3.2 Findings (reference or inline)
9. Source Deliverables Appendix

### v3.4 Findings Inventory (Complete)

#### Phase 50: Skim Redesign Audit (3 INFO)

| ID | Severity | Contract | Lines | Description | Requirement |
|----|----------|----------|-------|-------------|-------------|
| F-50-01 | INFO | DegenerusGameAdvanceModule.sol | 1020-1025 | Additive random step uses `rngWord % 1001` on full 256-bit VRF word, not bit-isolated to [0:63] as documented. Functionally independent via modulo but does not match stated bit-window design. | SKIM-03 |
| F-50-02 | INFO | DegenerusGameAdvanceModule.sol | 1020-1025 | roll1 (`rngWord>>64`) and roll2 (`rngWord>>192`) share bits [192:255]. Modulo makes outputs functionally independent for practical ranges. | SKIM-03 |
| F-50-03 | INFO | DegenerusGameAdvanceModule.sol | test gap | Test `test_level1_overshootDormant` uses unreachable `lastPool=0`. Production level 1 has `lastPool=50 ether` (bootstrap). Recommend adding production-realistic test case. | ECON-03 |

**Source:** `.planning/phases/50-skim-redesign-audit/50-03-economic-analysis.md` (Phase 50 Overall Findings Summary table)

**Source files:**
- `.planning/phases/50-skim-redesign-audit/50-01-pipeline-arithmetic.md` (SKIM-01 through SKIM-05 verdicts)
- `.planning/phases/50-skim-redesign-audit/50-02-conservation-insurance.md` (SKIM-06, SKIM-07 verdicts)
- `.planning/phases/50-skim-redesign-audit/50-03-economic-analysis.md` (ECON-01 through ECON-03 verdicts + findings summary)

#### Phase 51: Redemption Lootbox Audit (1 MEDIUM, 2 INFO)

| ID | Severity | Contract | Lines | Description | Requirement |
|----|----------|----------|-------|-------------|-------------|
| REDM-06-A | MEDIUM | DegenerusGame.sol | 1809-1813 | Unchecked subtraction in `resolveRedemptionLootbox`: `claimableWinnings[SDGNRS] -= amount` can underflow when prior claims drain sDGNRS's claimable via `_payEth` -> `game.claimWinnings()`. Corrupts accounting (inflated to near `uint256.max`), DoS on future sDGNRS claims from Game. Not directly exploitable for theft because `claimablePool -= payout` reverts on inflated amount. | REDM-06 |
| INFO-01 (51-01) | INFO | StakedDegenerusStonk.sol | 584-594 | Rounding dust accumulates in `pendingRedemptionEthValue` -- at most `n-1` wei per period for `n` claimants. No exploit vector, no economic impact. | REDM-01 |
| INFO-01 (51-02) | INFO | StakedDegenerusStonk.sol | 755 | `burnieOwed` field in PendingRedemption lacks explicit cap analogous to `MAX_DAILY_REDEMPTION_EV`. Theoretical uint96 truncation if BURNIE supply grows 20,000x from initial 2M allocation. Safe under realistic economics. | REDM-05 |

**NOTE on finding ID collision:** Both Plan 51-01 and Plan 51-02 independently used the ID "INFO-01". The master table must assign unique IDs. Recommend: F-51-01 (rounding dust), F-51-02 (burnieOwed cap), keeping REDM-06-A as-is since it is a unique ID.

**Source files:**
- `.planning/phases/51-redemption-lootbox-audit/51-01-split-routing-findings.md` (REDM-01, REDM-02 verdicts + INFO-01)
- `.planning/phases/51-redemption-lootbox-audit/51-02-daily-cap-packing-findings.md` (REDM-03, REDM-05 verdicts + INFO-01)
- `.planning/phases/51-redemption-lootbox-audit/51-03-activity-score-findings.md` (REDM-04 verdict, no findings)
- `.planning/phases/51-redemption-lootbox-audit/51-04-access-control-reclassification-findings.md` (REDM-06, REDM-07 verdicts + REDM-06-A finding)

#### Phase 52: Invariant Test Suite (0 findings)

Phase 52 produced fuzz test infrastructure, not audit findings. No findings to consolidate.

- Plan 52-01: 4 INV-named fuzz tests for skim conservation + take cap
- Plan 52-02: 3 pure arithmetic fuzz tests + 1 lifecycle invariant for redemption split

**Source files:**
- `.planning/phases/52-invariant-test-suite/52-01-SUMMARY.md`
- `.planning/phases/52-invariant-test-suite/52-02-SUMMARY.md`

#### Outstanding v3.2 Findings (30 total: 6 LOW, 24 INFO)

All 30 findings are documented in `audit/v3.2-findings-consolidated.md`. These are NatSpec/comment findings that were flagged but not fixed (by design -- "flag-only" mode). For FIND-02, these must be included in the master list.

**Key question for the planner:** Should the v3.2 findings be duplicated inline in the v3.4 consolidated report, or referenced by pointer to the v3.2 report?

**Recommendation: Reference by pointer.** The v3.2 findings are unchanged (no re-audit) and duplicating 30 entries adds bulk without new information. Include a summary row count in the executive summary and a reference section pointing to `audit/v3.2-findings-consolidated.md`. The requirement says "included in the master list for completeness" which can be satisfied by an appendix section that lists the v3.2 findings with a note "carried forward from v3.2, not re-audited."

However, if FIND-02 is interpreted as requiring all 30 to appear as rows in the master table, the planner should include them. The requirement text says "Outstanding v3.2 LOW/INFO findings are included in the master list for completeness (not re-audited, just consolidated)." This leans toward inline inclusion. Let the planner decide -- provide both approaches as options.

### Deduplication Analysis

**Cross-phase overlap check:**
- F-50-01 and F-50-02 are related (both SKIM-03 bit-field findings from the same code section) but distinct findings (different bit ranges, different mechanisms). Keep as separate entries.
- INFO-01 from 51-01 and INFO-01 from 51-02 are distinct findings with colliding IDs. Assign unique IDs.
- No overlap between Phase 50 and Phase 51 findings (different contracts, different features).
- No overlap between v3.4 findings and v3.2 findings (v3.4 audits new code; v3.2 was NatSpec-only).

**Result: 0 deduplication needed for v3.4 findings. Total unique v3.4 findings: 5.**

### Severity Sort Order

Per FIND-03 and the established v3.2 pattern:

```
MEDIUM (1): REDM-06-A
LOW (0 new v3.4; 6 from v3.2 if carried forward)
INFO (4 new v3.4; 24 from v3.2 if carried forward)
```

This is the first milestone to produce a MEDIUM-severity finding. The v3.3 findings (CP-08, CP-06, Seam-1, CP-07) were all HIGH/MEDIUM but were fixed in code -- they should NOT appear in this consolidated report as they are resolved. The FINAL-FINDINGS-REPORT.md already documents them as FIXED.

### Recommended Fix Priority Classification

Following the Phase 43 pattern:

| Priority | Findings | Rationale |
|----------|----------|-----------|
| **Fix before C4A (HIGH priority)** | REDM-06-A | MEDIUM severity -- accounting corruption via unchecked arithmetic. Wardens will find this. |
| **Consider fixing (MEDIUM priority)** | F-50-01, F-50-02 | INFO but wardens may flag NatSpec/documentation mismatches on new code. Easy to fix (update comments or add bit masking). |
| **Accept as known (LOW priority)** | F-50-03, F-51-01, F-51-02 | Test gap and negligible economic impacts. Not warden targets. |
| **Carry-forward v3.2** | 6 LOW + 24 INFO | Already documented. Fix or accept per v3.2 priority guide. |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding deduplication | Manual comparison of raw finding lists | Systematic cross-check with canonical ID assignment | Phase 43 had 4 duplicates that were missed until Task 2 validation |
| Severity counting | Mental arithmetic | Table with running totals + validation task | Phase 43 plan had incorrect count estimates (79 vs 76 FIXED) corrected during execution |

**Key insight:** The Phase 43 execution revealed that finding counts estimated during planning were wrong. Phase 53 planning should build in a validation task that cross-checks all counts against source files, same as Phase 43 did.

## Common Pitfalls

### Pitfall 1: Finding ID Collisions
**What goes wrong:** Multiple plans within a phase independently assign the same finding ID (e.g., both 51-01 and 51-02 used "INFO-01").
**Why it happens:** Each plan is executed independently without visibility into other plans' ID assignments.
**How to avoid:** The consolidation task must assign globally unique IDs. Use the format `F-{phase}-{seq}` for all new v3.4 findings. Keep REDM-06-A as-is since it has a unique namespace.
**Warning signs:** Two findings with the same ID in the master table.

### Pitfall 2: Miscounting Findings
**What goes wrong:** Executive summary claims N findings but the master table has N+/-K entries.
**Why it happens:** Counting errors during planning, especially when merging multiple sources.
**How to avoid:** Add a validation task (like Phase 43's Task 2) that programmatically counts table rows and cross-checks against claimed totals.
**Warning signs:** Sum of per-contract/per-phase counts doesn't match grand total.

### Pitfall 3: Including Fixed Findings
**What goes wrong:** v3.3 findings (CP-08, CP-06, Seam-1, CP-07) or other already-fixed findings appear in the "open findings" table.
**Why it happens:** Copy-paste from STATE.md which mentions all findings from all milestones.
**How to avoid:** Only include UNFIXED findings. v3.3 findings are already in FINAL-FINDINGS-REPORT.md as FIXED. v3.4 findings (this phase) are all new/open.
**Warning signs:** Any finding with "FIXED" status in the master table.

### Pitfall 4: Missing Source Traceability
**What goes wrong:** Finding in master table cannot be traced back to the source verdict document.
**Why it happens:** Summary-level information was used instead of referencing specific files.
**How to avoid:** Every finding row must include the source file path (the specific findings .md file from Phase 50/51).
**Warning signs:** A finding row that lacks a "Source" reference.

## Code Examples

Not applicable -- this phase produces a Markdown document, not code. The "code" is the findings table format:

### Master Table Row Format (from Phase 43 precedent)
```markdown
| ID | Severity | Contract | Phase | Lines | Summary | Recommendation |
|----|----------|----------|-------|-------|---------|----------------|
| REDM-06-A | MEDIUM | DegenerusGame.sol | 51 | 1809-1813 | Unchecked subtraction underflow in resolveRedemptionLootbox | Use checked arithmetic or dedicated redemption pool |
```

### Executive Summary Table Format
```markdown
| Metric | Count |
|--------|-------|
| **Total v3.4 findings** | **5** |
| By severity: MEDIUM | 1 |
| By severity: INFO | 4 |
| Outstanding v3.2 (carried forward) | 30 (6 LOW, 24 INFO) |
| **Grand total (all open)** | **35** |
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| v3.1 consolidated in Phase 36 | v3.2 consolidated in Phase 43 with cross-cutting patterns and validation task | Phase 43 (2026-03-19) | Validation task caught count errors; cross-cutting patterns enable batch fixes |

**Established patterns from prior milestones:**
- Phase 36 (v3.1): First consolidated findings report
- Phase 43 (v3.2): Improved with deduplication, cross-cutting patterns, validation task, per-contract counts
- Phase 53 (v3.4): Should follow Phase 43 pattern + add v3.2 carry-forward

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual validation (document review) |
| Config file | None |
| Quick run command | `grep -c "^|" audit/v3.4-findings-consolidated.md` |
| Full suite command | Manual cross-check of finding counts vs source files |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIND-01 | All v3.4 findings in master table with required columns | manual + grep | `grep -E "REDM-06-A\|F-50-01\|F-50-02\|F-50-03\|F-51-01\|F-51-02" audit/v3.4-findings-consolidated.md` | Wave 0 |
| FIND-02 | v3.2 findings included | manual + grep | `grep "v3.2" audit/v3.4-findings-consolidated.md` | Wave 0 |
| FIND-03 | Sorted by severity (MEDIUM > LOW > INFO) | manual | Visual inspection of table order | Wave 0 |

### Sampling Rate
- **Per task commit:** `grep -c "^|" audit/v3.4-findings-consolidated.md` (count table rows)
- **Per wave merge:** Manual review of finding counts and severity ordering
- **Phase gate:** All 5 v3.4 finding IDs present + v3.2 reference section exists

### Wave 0 Gaps
- None -- this phase creates documentation, not test infrastructure. Validation is inline.

## Open Questions

1. **v3.2 findings: inline or by reference?**
   - What we know: FIND-02 says "included in the master list for completeness (not re-audited, just consolidated)"
   - What's unclear: Whether "included" means full table rows or a reference section with summary counts
   - Recommendation: Include as a separate section of the master table (after v3.4 findings) with a header noting they are carried forward from v3.2. This satisfies both interpretations.

2. **REDM-06-A: has it been fixed?**
   - What we know: STATE.md lists it as a finding with MEDIUM severity. It was discovered in Phase 51 and flagged for Phase 53 consolidation.
   - What's unclear: Whether the team has already applied a fix between Phase 51 and now.
   - Recommendation: Include as-is in the consolidated report. If fixed, the executor should verify and mark as FIXED. If not, include as open.

3. **FINAL-FINDINGS-REPORT.md update needed?**
   - What we know: FINAL-FINDINGS-REPORT.md currently says "No open findings" and only documents v3.3 findings as FIXED.
   - What's unclear: Whether Phase 53 should also update FINAL-FINDINGS-REPORT.md to reference v3.4 findings.
   - Recommendation: Out of scope for Phase 53. The consolidated findings document is the v3.4 deliverable. FINAL-FINDINGS-REPORT.md can be updated in a separate cleanup phase if needed.

## Sources

### Primary (HIGH confidence)
- `.planning/phases/50-skim-redesign-audit/50-01-SUMMARY.md` - Phase 50 Plan 01 findings (F-50-01, F-50-02)
- `.planning/phases/50-skim-redesign-audit/50-02-SUMMARY.md` - Phase 50 Plan 02 findings (none)
- `.planning/phases/50-skim-redesign-audit/50-03-SUMMARY.md` - Phase 50 Plan 03 findings (F-50-03)
- `.planning/phases/50-skim-redesign-audit/50-03-economic-analysis.md` - Phase 50 findings summary table
- `.planning/phases/51-redemption-lootbox-audit/51-01-SUMMARY.md` - Phase 51 Plan 01 findings (INFO-01 rounding dust)
- `.planning/phases/51-redemption-lootbox-audit/51-02-SUMMARY.md` - Phase 51 Plan 02 findings (INFO-01 burnieOwed cap)
- `.planning/phases/51-redemption-lootbox-audit/51-03-SUMMARY.md` - Phase 51 Plan 03 findings (none)
- `.planning/phases/51-redemption-lootbox-audit/51-04-SUMMARY.md` - Phase 51 Plan 04 findings (REDM-06-A)
- `.planning/phases/51-redemption-lootbox-audit/51-04-access-control-reclassification-findings.md` - REDM-06-A full details
- `.planning/phases/52-invariant-test-suite/52-01-SUMMARY.md` - Phase 52 Plan 01 (no findings)
- `.planning/phases/52-invariant-test-suite/52-02-SUMMARY.md` - Phase 52 Plan 02 (no findings)
- `audit/v3.2-findings-consolidated.md` - 30 outstanding v3.2 findings (6 LOW, 24 INFO)
- `.planning/phases/43-consolidated-findings/43-01-PLAN.md` - Phase 43 plan format (template for Phase 53)
- `.planning/phases/43-consolidated-findings/43-01-SUMMARY.md` - Phase 43 execution results (pattern reference)
- `audit/FINAL-FINDINGS-REPORT.md` - Current state of the final audit report (v3.3 findings all FIXED)
- `audit/KNOWN-ISSUES.md` - Known design decisions (not findings)
- `.planning/STATE.md` - Accumulated decisions from all phases

### Secondary (MEDIUM confidence)
- None needed -- all sources are first-party project files

### Tertiary (LOW confidence)
- None

## Metadata

**Confidence breakdown:**
- Findings inventory: HIGH - all source files read and cross-checked
- Architecture/format: HIGH - Phase 43 precedent is well-documented and was successfully executed
- Pitfalls: HIGH - Phase 43 execution revealed specific count errors, same pattern applies here

**Research date:** 2026-03-21
**Valid until:** 2026-04-21 (stable -- findings are static once audit phases complete)
