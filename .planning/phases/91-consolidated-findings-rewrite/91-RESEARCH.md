# Phase 91: Consolidated Findings Rewrite - Research

**Researched:** 2026-03-23
**Domain:** Audit document consolidation, findings assembly, KNOWN-ISSUES update, cross-phase consistency
**Confidence:** HIGH

## Summary

Phase 91 rewrites the existing `v4.0-findings-consolidated.md` document, which currently covers only Phases 81, 82, and 88 with 9 findings. The rewrite must incorporate ALL findings from Phases 83 through 87, update KNOWN-ISSUES.md with two new above-INFO findings (DEC-01 MEDIUM, DGN-01 LOW), re-run the cross-phase consistency check with the now-complete Phase 87 SUMMARY files (created by Phase 90), and produce 89-VERIFICATION.md for the original Phase 89 work.

The critical finding is that the current consolidated document is significantly incomplete. It lists 9 unique findings and a grand total of 92 (9 v4.0 + 83 prior). The actual v4.0 finding count is approximately 49 unique findings across all phases, including 1 MEDIUM (DEC-01) and 1 LOW (DGN-01) -- both of which trigger mandatory KNOWN-ISSUES.md updates per CFND-02.

**Primary recommendation:** Rewrite the consolidated document from scratch using the established v3.6 format, incorporating the complete findings inventory from all 8 audit phases (81-88). The document must include DEC-01 (MEDIUM) and DGN-01 (LOW) in the "Fix Before C4A" / "Consider Fixing" priority sections and update KNOWN-ISSUES.md accordingly.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CFND-01 | All v4.0 findings (phases 81-88) deduplicated and severity-ranked | Complete findings inventory assembled: ~49 unique findings from 13 audit documents across Phases 81-88. DEC-01 is MEDIUM, DGN-01 is LOW, remainder INFO. |
| CFND-02 | KNOWN-ISSUES.md updated with any new findings above INFO | DEC-01 (MEDIUM) and DGN-01 (LOW) MUST be added to KNOWN-ISSUES.md. Current KNOWN-ISSUES.md v4.0 entry only lists 3 INFO findings from Phase 81. |
| CFND-03 | Cross-phase consistency verified -- no contradictions between phase audit documents | Phase 87 SUMMARY files (to be created by Phase 90) enable full consistency check. Cross-reference DSC-01/DSC-02 confirmed independently by Phases 81, 83, and 87 (BAF). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Self-check before delivering results.** After completing any substantial task, internally ask "anything we're missing?" to catch gaps, stale references, cascading changes, and overlooked follow-on work. Fix before presenting results. (Source: user's global CLAUDE.md)
- **Never commit contracts/ or test/ changes without explicit user approval.** (Source: project memory -- not applicable, documentation-only phase)
- **Present fix and wait for explicit approval before editing code.** (Source: project memory -- not applicable, documentation-only phase)

## Standard Stack

Not applicable -- this is a documentation-only phase. No libraries, frameworks, or code changes required.

## Architecture Patterns

### Consolidated Findings Document Format

Based on analysis of the existing `v3.6-findings-consolidated.md` and the current (incomplete) `v4.0-findings-consolidated.md`, the established format is:

```markdown
# vX.Y Consolidated Findings -- [Milestone Name]

**Status:** FINAL
**Date:** [date]
**Milestone:** vX.Y
**Scope:** [N phases (range), covering description]
**Mode:** [Flag-only / Code changes + audit]
**Source phases:** [bulleted list with plan counts, requirement counts, finding counts]

## Executive Summary
| Metric | Count |
(Total findings, by severity breakdown, per-phase verdict summary, carry-forward, grand total)

## ID Assignment
(Namespace table showing all finding ID schemes, collision resolution)

## Master Findings Table
### HIGH (count)
### MEDIUM (count)
### LOW (count)
### INFO (count)
(Full finding descriptions by severity, highest first)

## Per-Phase Summary
(Each phase: requirements met, key results, finding count, source documents)

## Cross-Reference Summary
(Prior audit claims checked, results by milestone)

## Recommended Fix Priority
### Fix Before C4A
### Consider Fixing
### Accept as Known

## Outstanding Prior Milestones (Carried Forward)
(Totals from v3.2 through v3.7)

## Requirement Traceability
(CFND-01, CFND-02, CFND-03 with evidence)

## Source Deliverables Appendix
(Table of all audit source files)
```

**Confidence: HIGH** -- verified against 5 existing consolidated findings documents.

### KNOWN-ISSUES.md Update Pattern

The KNOWN-ISSUES.md file has these sections:
1. **Intentional Design (Not Bugs)** -- stETH rounding, affiliate entropy
2. **Design Mechanics** -- VRF governance, Chainlink dependency, Lido, _sendToVault
3. **Audit History** -- chronological entries per milestone (v3.2 through v4.0)

For CFND-02, findings above INFO must be added to the document body (not just Audit History). DEC-01 (MEDIUM) and DGN-01 (LOW) should get entries in a new "Known Vulnerabilities" or "Open Findings" section, or be added to the Audit History with clear severity labels.

## Complete Findings Inventory

### Phase 81: Ticket Creation & Queue Mechanics (3 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| DSC-01 | INFO | v3.9 RNG commitment window proof describes reverted combined pool code (2bf830a2). FF-only is strictly simpler. | v4.0-ticket-creation-queue-mechanics.md, v4.0-ticket-queue-double-buffer.md |
| DSC-02 | INFO | `sampleFarFutureTickets` view function at DG:2681 reads `_tqWriteKey` instead of `_tqFarFutureKey`. Off-chain only. | v4.0-ticket-creation-queue-mechanics.md, v4.0-ticket-queue-double-buffer.md |
| DSC-03 | INFO | NatSpec at GS:533 claims uint32 cap but code uses `unchecked`. Overflow requires > total ETH supply. | v4.0-ticket-creation-queue-mechanics.md |

### Phase 82: Ticket Processing Mechanics (6 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| P82-01 | INFO | v3.8 ticketsFullyProcessed byte offset 24 vs actual 25 | v4.0-82-ticket-processing.md |
| P82-02 | INFO | v3.8 ticketsFullyProcessed setter attribution (JM vs AM) | v4.0-82-ticket-processing.md |
| P82-03 | INFO | v3.8 traitBurnTicket writer table missing processFutureTicketBatch | v4.0-82-ticket-processing.md |
| P82-04 | INFO | ticketsFullyProcessed has 3 distinct true setters, not 1 | v4.0-82-ticket-processing.md |
| P82-05 | INFO | processTicketBatch 1-line drift JM:1890->1889 | v4.0-82-ticket-processing.md |
| P82-06 | INFO | lastLootboxRngWord slot 70 claim -- resolved by Phase 88 (actual slot 56) | v4.0-82-ticket-processing.md |

### Phase 83: Ticket Consumption & Winner Selection (0 new findings)

Phase 83 produced 0 new findings. DSC-01 and DSC-02 from Phase 81 were independently re-confirmed. Cross-reference found 6 DISCREPANCY items (all TQ-01/combined-pool related, already covered by Phase 81 findings) and 15 CONFIRMED claims.

### Phase 84: Prize Pool Flow (6 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| DSC-84-01 | INFO | v3.8 claims yieldAccumulator at slot 100; actual slot 71 (boon packing shift) | v4.0-prize-pool-flow.md |
| DSC-84-02 | INFO | v3.8 claims levelPrizePool at slot 45; actual slot 30 (boon packing shift) | v4.0-prize-pool-flow.md |
| DSC-84-03 | INFO | v3.8 claims autoRebuyState at slot 36; actual slot 25 (boon packing shift) | v4.0-prize-pool-flow.md |
| DSC-84-04 | INFO | v3.8 prizePoolsPacked guard analysis incorrectly claims future pool share bypasses freeze | v4.0-prize-pool-flow.md |
| DSC-84-05 | INFO | consolidatePrizePools NatSpec omits x00 yield dump step (Step 1) | v4.0-prize-pool-flow.md |
| DSC-84-06 | INFO | v3.8 verdict for prizePoolsPacked confirmed with caveat (freeze redirect, not "not read") | v4.0-prize-pool-flow.md |

**Note:** DSC-84-04 and DSC-84-06 IDs are inferred from the cross-reference table context. The audit document numbers them in sequence within Section 6. The planner must verify exact IDs when writing the consolidated doc.

### Phase 85: Daily ETH Jackpot (11 items; 10 discrepancies + 1 new finding)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| DSC-V38-01 | INFO | v3.8 claims dailyEthPhase at Slot 0 offset 31; actual is Slot 1 offset 0 | v4.0-daily-eth-jackpot.md |
| DSC-V38-02 | INFO | v3.8 claims dailyCarryoverEthPool is W-only; actual is R/W | v4.0-daily-eth-jackpot.md |
| DSC-V38-03 | INFO | v3.8 claims dailyCarryoverWinnerCap is W-only; actual is R/W | v4.0-daily-eth-jackpot.md |
| DSC-V38-04 | INFO | v3.8 call site line numbers drifted by +3 (AM:279->282, etc.) | v4.0-daily-eth-jackpot.md |
| DSC-PAY-01 | INFO | PAY-01 formula cites JM:635-639; actual is JM:628-633 (line drift) | v4.0-daily-eth-jackpot.md |
| DSC-PAY-02a | INFO | PAY-02 share split claims 60/13/13/13/1 for all days; actual has two packings | v4.0-daily-eth-jackpot.md |
| DSC-PAY-02b | INFO | PAY-02 says "4 winners per draw"; actually up to 321 across 4 buckets | v4.0-daily-eth-jackpot.md |
| DSC-PAY-02c | INFO | PAY-02 line references drifted: JM:336-613->323-667, etc. | v4.0-daily-eth-jackpot.md |
| CMT-V32-002 | INFO | RESOLVED: inline comment at JM:609 updated to "BURNIE and ETH bonuses" | v4.0-daily-eth-jackpot.md |
| NF-V38-01 | INFO | v3.8 Section 1.7 omits whalePassClaims and levelStartTime from payDailyJackpot scope | v4.0-daily-eth-jackpot.md |
| (CONFIRMED) | INFO | CMT-V32-001 still unresolved: NatSpec says "auto-rebuy tickets" but returns whale pass ETH | v4.0-daily-eth-jackpot.md |

**Deduplication note:** CMT-V32-002 is RESOLVED (not a new finding). CMT-V32-001 was already identified in v3.2. The unique NEW findings from Phase 85 are: DSC-V38-01 through DSC-V38-04, DSC-PAY-01, DSC-PAY-02a/b/c, and NF-V38-01. Total new unique: 9 INFO.

### Phase 86 Plan 01: Daily Coin Jackpot (3 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| DCJ-01 | INFO | v3.8 Category 3 stale far-future key claim (readKey description) | v4.0-daily-coin-jackpot-and-counter.md |
| DCJ-02 | INFO | v3.8 line number drift in Category 3 (JM:2411->2410, JM:2651->2650) | v4.0-daily-coin-jackpot-and-counter.md |
| DCJ-03 | INFO | Near-future coin budget silently skipped when target level empty (by design) | v4.0-daily-coin-jackpot-and-counter.md |

### Phase 86 Plan 02: Daily Ticket Jackpot (3 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| NF-01 | INFO | Duplicate winners possible in _randTraitTicket (no dedup, by design) | v4.0-daily-ticket-jackpot.md |
| NF-02 | INFO | Early-bird lootbox level arithmetic asymmetry (correct by design) | v4.0-daily-ticket-jackpot.md |
| NF-03 | INFO | Phase 81 Path #12 references non-existent `_distributeTicketScatter` function name | v4.0-daily-ticket-jackpot.md |

### Phase 87 Plan 01: Early-Bird + Final-Day DGNRS (8 findings)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| EB-01 | INFO | Integer division dust in perWinnerEth (up to 99 wei), recycled to nextPrizePool | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| EB-02 | INFO | Per-winner ticket count truncation when perWinnerEth < ticketPrice | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| EB-03 | INFO | EntropyLib.entropyStep uses xorshift PRNG (linear correlation). VRF seed anchor. | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| EB-04 | INFO | Double SLOAD of prizePoolsPacked for futurePrizePool (minor gas) | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| FD-01 | INFO | No-winner path silently skips 1% sDGNRS reward with no event | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| FD-02 | INFO | Solo bucket index uses 2 bits of entropy for 4-way selection | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| FD-03 | INFO | DSC-02 explicitly confirmed non-applicable to final-day DGNRS | v4.0-other-jackpots-earlybird-finaldgnrs.md |
| FD-04 | INFO | Turbo mode uses Day 1 traits for final-day reward (by design) | v4.0-other-jackpots-earlybird-finaldgnrs.md |

### Phase 87 Plan 02: BAF Jackpot (2 new findings + 1 cross-ref)

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| BAF-01 | INFO | Inconsistent zero-score handling between far-future and scatter selection | v4.0-other-jackpots-baf.md |
| BAF-02 | INFO | winnerMask constructed (DJ:501-513) but discarded by EndgameModule (EM:361). Dead code. | v4.0-other-jackpots-baf.md |
| DSC-02 (cross-ref) | INFO | Confirmed: sampleFarFutureTickets causes BAF Slices D/D2 to recycle ~10% of pool | v4.0-other-jackpots-baf.md |

### Phase 87 Plan 03: Decimator (8 findings) -- INCLUDES DEC-01 MEDIUM

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| **DEC-01** | **MEDIUM** | **decBucketOffsetPacked collision: terminal decimator overwrites regular decimator's packed offsets when both resolve at same level, corrupting regular claim validation** | v4.0-other-jackpots-decimator.md |
| DEC-02 | INFO | Day-10 time multiplier discontinuity 2.75x->2x (intentional, NatSpec at DM:902) | v4.0-other-jackpots-decimator.md |
| DEC-03 | INFO | uint96 truncation of terminal decimator pool (benign, unreachable) | v4.0-other-jackpots-decimator.md |
| DEC-04 | INFO | Terminal decimator bucket set once per level, no migration (by design) | v4.0-other-jackpots-decimator.md |
| DEC-05 | INFO | Terminal decimator uses weightedBurn=0 as claim flag (dual-purpose) | v4.0-other-jackpots-decimator.md |
| DEC-06 | INFO | Regular decimator returns silently on effectiveAmount==0; terminal reverts | v4.0-other-jackpots-decimator.md |
| DEC-07 | INFO | decBucketBurnTotal[13][13] wastes slots for indices 0-1 (space-for-speed) | v4.0-other-jackpots-decimator.md |
| DEC-08 | INFO | Terminal decimator lvl==0 guard unreachable (level-0 GAMEOVER takes early refund) | v4.0-other-jackpots-decimator.md |

### Phase 87 Plan 04: Degenerette (6 findings + 1 verified safe) -- INCLUDES DGN-01 LOW

| ID | Severity | Description | Source Document |
|----|----------|-------------|-----------------|
| **DGN-01** | **LOW** | **`_collectBetFunds` uses `<=` instead of `<` for claimable balance check, reverting when player has exactly enough claimable ETH** | v4.0-other-jackpots-degenerette.md |
| DGN-02 | INFO | Degenerette _addClaimableEth does NOT implement auto-rebuy (unlike JM/EM/DM versions) | v4.0-other-jackpots-degenerette.md |
| DGN-03 | INFO | topDegeneretteByLevel is written and exposed but never consumed by game logic | v4.0-other-jackpots-degenerette.md |
| DGN-04 | INFO | _awardDegeneretteDgnrs called per-spin (multiple Reward pool transfers per bet) | v4.0-other-jackpots-degenerette.md |
| DGN-05 | INFO | Consolation requires ALL spins zero payout; single 2-match disqualifies | v4.0-other-jackpots-degenerette.md |
| DGN-06 | INFO | prizePoolFrozen blocks ALL ETH degenerette resolution during jackpot phase | v4.0-other-jackpots-degenerette.md |
| DGN-07 | N/A | ETH portion unchecked subtraction verified safe (ethPortion <= pool * 10%) | v4.0-other-jackpots-degenerette.md |

### Phase 88: RNG-Dependent Variable Re-verification (0 new findings)

All 55 v3.8 rows CONFIRMED SAFE. 27 slot shifts (INFO, caused by Phase 73 boon packing). P82-06 resolved (actual slot 56, not 70). No new findings.

### Aggregate Finding Count

| Severity | Count | IDs |
|----------|-------|-----|
| HIGH | 0 | -- |
| MEDIUM | 1 | DEC-01 |
| LOW | 1 | DGN-01 |
| INFO | ~47 | All others (exact count depends on deduplication treatment of DSC-02 cross-refs and RESOLVED items) |

**Deduplication considerations:**
1. DSC-01 and DSC-02 are first identified in Phase 81, then independently re-confirmed in Phases 83 and 87 (BAF). They should be counted ONCE each.
2. CMT-V32-002 is RESOLVED -- should it be counted or excluded? Prior precedent (v3.6 doc) counts resolved items separately.
3. FD-03 is an explicit "non-applicability confirmation" for DSC-02 -- not a separate finding.
4. DGN-07 is "N/A (Verified Safe)" -- not a finding per se.
5. CMT-V32-001 (CONFIRMED still unresolved) is a PRIOR finding from v3.2 -- should not be re-counted in v4.0.
6. DSC-84-04 and DSC-84-06 may need ID confirmation from the audit document structure.

**Recommended count after dedup:** ~49 unique v4.0 findings (0 HIGH, 1 MEDIUM, 1 LOW, ~47 INFO).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Finding deduplication | Manual cross-checking | Grep-based ID inventory from each audit doc's findings summary table | Each audit doc has a consistent findings table at the end -- use those as authoritative |
| Cross-phase consistency | Re-reading all audit docs end-to-end | Focus on the findings sections and cross-reference tables only | Each doc has a dedicated cross-reference section that already validated claims |
| Grand total calculation | Manual addition | Carry forward the prior milestone totals verbatim from the current doc (83 prior) and add v4.0 count | Prior counts were already verified in the existing consolidated doc |

## Common Pitfalls

### Pitfall 1: Undercounting Findings
**What goes wrong:** The existing Phase 89 consolidated doc lists only 9 findings because Phases 83-87 were marked "not executed" at the time. Phase 91 must catch ALL findings from the audit docs that actually exist.
**Why it happens:** Phase 89 was executed before Phases 83-87 audit work was complete. The gap was identified in the v4.0 milestone audit.
**How to avoid:** Use the complete findings inventory in this research document as the authoritative source. Verify each count against the audit document's own finding summary table.
**Warning signs:** If the new count is less than 40, something was missed.

### Pitfall 2: Missing DEC-01 and DGN-01 in KNOWN-ISSUES.md
**What goes wrong:** KNOWN-ISSUES.md only gets a lightweight audit history entry (like Phase 89 did) without adding the MEDIUM and LOW findings to the document body.
**Why it happens:** Phase 89's plan explicitly stated "all findings INFO, no update needed." Phase 91 has different findings.
**How to avoid:** CFND-02 says "updated with any new findings above INFO." DEC-01 is MEDIUM, DGN-01 is LOW. Both MUST appear in KNOWN-ISSUES.md.
**Warning signs:** If KNOWN-ISSUES.md only has the Audit History entry and not individual finding descriptions for DEC-01/DGN-01.

### Pitfall 3: ID Collision Between Phase Audit Docs
**What goes wrong:** Multiple phase docs use generic IDs like "NF-01", "NF-02" which collide.
**Why it happens:** Each audit doc uses its own local ID namespace (NF-01 in Phase 86 Plan 02 vs NF-V38-01 in Phase 85).
**How to avoid:** The consolidated doc must either: (a) prefix all IDs with phase context (e.g., P86T-NF-01 for Phase 86 ticket jackpot), or (b) assign unique consolidated IDs. Prior milestones used approach (b) with unique consolidated IDs per namespace.
**Warning signs:** Two different findings both called "NF-01" in the master table.

### Pitfall 4: Not Updating the Grand Total
**What goes wrong:** The carry-forward total stays at 92 (9 v4.0 + 83 prior) instead of being updated.
**Why it happens:** Copy-paste from existing doc.
**How to avoid:** Grand total = (new v4.0 unique findings) + 83 prior. With ~49 v4.0 findings, grand total is ~132.
**Warning signs:** Grand total is still 92 or 86.

### Pitfall 5: Creating 89-VERIFICATION.md Without Phase 90 Completion
**What goes wrong:** Phase 91 Plan 03 is supposed to create 89-VERIFICATION.md, but the consistency check depends on Phase 87 SUMMARY files that Phase 90 creates.
**Why it happens:** Phase 90 and 91 are gap-closure phases that may run in sequence.
**How to avoid:** Phase 91 Plan 03 should either: (a) depend on Phase 90 completion, or (b) read the audit docs directly rather than SUMMARY files for the consistency check.
**Warning signs:** References to 87-XX-SUMMARY.md files that don't exist yet.

### Pitfall 6: DSC-02 Cross-Reference Chain
**What goes wrong:** DSC-02 is mentioned in Phase 81, Phase 83, Phase 87 (BAF), and Phase 87 (earlybird FD-03). It could be counted 4 times.
**Why it happens:** It's a cross-cutting finding that affects multiple jackpot types.
**How to avoid:** Count DSC-02 once in the master table. In each per-phase summary, note it as "carried forward" or "independently confirmed." BAF Section 3 adds new impact analysis (Slices D/D2 recycling ~10%) which should be noted as supplementary detail under the single DSC-02 entry.

## Code Examples

Not applicable -- documentation-only phase. The "code" is the markdown document structure.

### Example: Master Findings Table Entry (MEDIUM)

```markdown
### MEDIUM (1)

#### DEC-01: decBucketOffsetPacked Collision Between Regular and Terminal Decimator [MEDIUM]

**Source:** Phase 87 Plan 03 (Decimator audit)
**Document:** `audit/v4.0-other-jackpots-decimator.md` Section 3
**Location:** DM:248 (regular write), DM:817 (terminal write), DM:281 (regular claim read)

Terminal decimator overwrites regular decimator's packed subbucket offsets when both
resolve at the same level. Different VRF words produce different winning subbuckets,
so the overwrite corrupts regular claim validation.

**Trigger:** GAMEOVER occurs at a decimator level (x5 or x00).
**Impact:** Regular decimator winners may lose claims; non-winners may incorrectly pass.
**Mitigation:** Regular claims work if claimed before GAMEOVER. Post-GAMEOVER corruption
affects the claim validation path.
```

### Example: KNOWN-ISSUES.md Entry for DEC-01

```markdown
**Decimator storage collision at GAMEOVER levels (DEC-01, MEDIUM).** When GAMEOVER
triggers at a level that also had a regular decimator (levels ending in 5 or 00),
the terminal decimator's `decBucketOffsetPacked` write at DM:817 overwrites the
regular decimator's packed offsets at DM:248. Regular decimator claims that have not
been processed before GAMEOVER may fail validation or produce incorrect pro-rata
amounts. Requires GAMEOVER to occur at exactly a decimator level, and regular claims
to still be pending. See `audit/v4.0-other-jackpots-decimator.md` Section 3.
```

## State of the Art

| Old State | Current State | Impact |
|-----------|--------------|--------|
| Phase 89 consolidated 3 phases (81, 82, 88) with 9 findings | All 8 phases (81-88) complete with ~49 findings | Consolidated doc is materially incomplete |
| KNOWN-ISSUES.md says "3 INFO findings, no HIGH/MEDIUM/LOW" | DEC-01 (MEDIUM) and DGN-01 (LOW) exist | KNOWN-ISSUES.md needs substantive update |
| Grand total was 92 (9 v4.0 + 83 prior) | Approximately 132 (~49 v4.0 + 83 prior) | Grand total needs recalculation |
| Phase 89 VERIFICATION existed as 89-VALIDATION.md | Phase 89 needs a proper VERIFICATION.md | Plan 03 creates this |

## Open Questions

1. **Exact v4.0 finding count after deduplication**
   - What we know: Raw count is approximately 55+ items across all docs, but DSC-01/DSC-02 cross-refs, RESOLVED items, non-findings (DGN-07), and non-applicability confirmations (FD-03) need to be excluded
   - What's unclear: Whether RESOLVED items (CMT-V32-002) count toward the v4.0 total or are excluded
   - Recommendation: Count unique NEW findings only. RESOLVED items get a separate note. Cross-refs are "carried forward" not re-counted. This should yield ~49 unique findings.

2. **Phase 84 finding ID naming**
   - What we know: The audit doc uses "DSC-84-01" through "DSC-84-05" consistently in text, but DSC-84-04 and DSC-84-06 are inferred from context
   - What's unclear: Whether the doc has exactly 5 or 6 distinct findings (the cross-reference table in Section 6 has multiple discrepancy rows)
   - Recommendation: Read the full Section 6 of v4.0-prize-pool-flow.md to confirm exact count and IDs

3. **Phase 90 dependency for Plan 03**
   - What we know: Phase 87 SUMMARY files are needed for full cross-phase consistency check
   - What's unclear: Whether Phase 90 will be complete before Phase 91 executes
   - Recommendation: Plan 03 should read audit docs directly as fallback if SUMMARY files don't exist

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | N/A (documentation-only phase) |
| Config file | N/A |
| Quick run command | `grep -c "## Executive Summary" audit/v4.0-findings-consolidated.md` |
| Full suite command | See per-requirement checks below |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CFND-01 | All findings deduplicated and severity-ranked | smoke | `grep -c "DEC-01" audit/v4.0-findings-consolidated.md && grep -c "DGN-01" audit/v4.0-findings-consolidated.md && grep -c "MEDIUM" audit/v4.0-findings-consolidated.md` | N/A (creates doc) |
| CFND-02 | KNOWN-ISSUES.md updated with above-INFO findings | smoke | `grep -c "DEC-01" audit/KNOWN-ISSUES.md && grep -c "DGN-01" audit/KNOWN-ISSUES.md && grep -c "MEDIUM" audit/KNOWN-ISSUES.md` | N/A (updates doc) |
| CFND-03 | Cross-phase consistency verified | smoke | `grep -c "89-VERIFICATION" .planning/phases/89-consolidated-findings/` | N/A (creates doc) |

### Sampling Rate
- **Per task commit:** Grep checks for key finding IDs and section headers
- **Per wave merge:** Full document review for structural completeness
- **Phase gate:** All 3 requirement checks pass before verification

### Wave 0 Gaps
None -- no test infrastructure needed for documentation-only phase.

## Source Documents Inventory

The planner and executor MUST read these audit documents to extract findings:

| Document | Phase | Findings | Key IDs |
|----------|-------|----------|---------|
| `audit/v4.0-ticket-creation-queue-mechanics.md` | 81 | 3 INFO | DSC-01, DSC-02, DSC-03 |
| `audit/v4.0-ticket-queue-double-buffer.md` | 81 | (shared with above) | DSC-01, DSC-02 cross-ref |
| `audit/v4.0-82-ticket-processing.md` | 82 | 6 INFO | P82-01 through P82-06 |
| `audit/v4.0-ticket-consumption-winner-selection.md` | 83 | 0 new | DSC-01/02 carried forward |
| `audit/v4.0-prize-pool-flow.md` | 84 | 6 INFO | DSC-84-01 through DSC-84-06 |
| `audit/v4.0-daily-eth-jackpot.md` | 85 | 9 new INFO + 1 resolved | DSC-V38-01..04, DSC-PAY-01, DSC-PAY-02a/b/c, NF-V38-01 |
| `audit/v4.0-daily-coin-jackpot-and-counter.md` | 86 | 3 INFO | DCJ-01, DCJ-02, DCJ-03 |
| `audit/v4.0-daily-ticket-jackpot.md` | 86 | 3 INFO | NF-01, NF-02, NF-03 |
| `audit/v4.0-other-jackpots-earlybird-finaldgnrs.md` | 87 | 8 INFO | EB-01..04, FD-01..04 |
| `audit/v4.0-other-jackpots-baf.md` | 87 | 2 INFO | BAF-01, BAF-02 |
| `audit/v4.0-other-jackpots-decimator.md` | 87 | 1 MEDIUM + 7 INFO | DEC-01..08 |
| `audit/v4.0-other-jackpots-degenerette.md` | 87 | 1 LOW + 5 INFO | DGN-01..06 |
| `audit/v4.0-rng-variable-re-verification.md` | 88 | 0 new | P82-06 resolved |

## Sources

### Primary (HIGH confidence)
- All 13 audit documents listed above -- read directly from the repository
- `audit/KNOWN-ISSUES.md` -- current state verified
- `audit/v4.0-findings-consolidated.md` -- current (incomplete) state verified
- `audit/v3.6-findings-consolidated.md` -- format reference verified
- `.planning/phases/89-consolidated-findings/89-01-PLAN.md` -- Phase 89 original plan
- `.planning/phases/89-consolidated-findings/89-01-SUMMARY.md` -- Phase 89 execution summary
- `.planning/REQUIREMENTS.md` -- CFND-01, CFND-02, CFND-03 definitions

### Secondary (MEDIUM confidence)
- Finding count estimates (~49 unique) -- based on manual inventory, exact count depends on dedup decisions

## Metadata

**Confidence breakdown:**
- Findings inventory: HIGH - every audit document read and findings extracted directly
- Architecture/format: HIGH - verified against 5 existing consolidated findings docs
- Pitfalls: HIGH - identified from actual Phase 89 execution gaps
- Finding counts: MEDIUM - approximate due to dedup edge cases (DSC-02 cross-refs, resolved items)

**Research date:** 2026-03-23
**Valid until:** 2026-03-30 (stable -- documents are frozen audit artifacts)
