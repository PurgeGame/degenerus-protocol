# Phase 22: Warden Simulation + Regression Check - Research

**Researched:** 2026-03-17
**Domain:** Multi-agent adversarial smart contract security audit + regression verification
**Confidence:** HIGH

## Summary

Phase 22 requires two distinct but complementary activities: (1) multi-agent adversarial simulation where 3+ independent agents with different specializations review the current codebase blind, and (2) a comprehensive regression check that verifies every prior audit finding (v1.0 through v2.0 + Phase 21 novel analysis) against the current code, classifying each as still-valid, fixed, or N/A.

The project has accumulated a substantial audit corpus: 1 Medium finding (M-02), 1 Low finding (DELTA-L-01), 12 Informational findings (I-03, I-09, I-10, I-13, I-17, I-19, I-20, I-22, DELTA-I-01 through DELTA-I-04), 4 adversarial sessions (ADVR-01 through ADVR-04, all clean), 56 v1 requirements (all PASS), 8 v2.0 DELTA requirements (all PASS), 8 v1.0 attack scenarios (all re-verified in v1.2), 9 v1.2 new attack surface findings, 26 v1.2 modified attack surface findings, 9 NOVEL requirement analyses (all SAFE), and the existing EXTERNAL-AUDIT-PROMPT.md which provides a ready-made blind audit prompt for the warden agents. The total audit corpus spans 30,705 lines across 33 audit documents.

The critical insight for planning is that the warden simulation (NOVEL-07) and the regression check (NOVEL-08) should be independent plans, since they serve different purposes and have different methodologies. The warden simulation uses blind adversarial analysis to find NEW vulnerabilities. The regression check is a systematic diff-verification of ALL prior findings to ensure nothing has regressed. These should not be confused.

**Primary recommendation:** Structure as 3 plans: (1) Three independent warden agent reports using the existing EXTERNAL-AUDIT-PROMPT.md as the base prompt with role-specific constraints, (2) systematic regression verification of all prior findings against current code, and (3) cross-reference deduplication and consolidated findings report.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| NOVEL-07 | Multi-agent adversarial simulation (3+ independent auditors cross-referencing findings) | EXTERNAL-AUDIT-PROMPT.md provides ready-made blind audit prompt; three agent personas defined (contract-auditor, zero-day-hunter, economic-analyst); C4A warden methodology documented; cross-reference and deduplication protocol specified |
| NOVEL-08 | Regression check -- diff every prior audit finding against current code | Complete inventory of 14 formal findings (1M + 1L + 12I) plus 8 v1.0 attack scenarios, 35 v1.2 surface findings, 9 NOVEL analyses, 64 requirement verdicts, and 4 adversarial sessions; v1.2 delta re-verification pattern from v1.2-delta-attack-reverification.md provides proven methodology |
</phase_requirements>

## Standard Stack

This phase is an adversarial analysis and verification phase, not a code implementation phase. The "stack" is the analysis methodology and tooling.

### Core Analysis Framework
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| C4A warden methodology | Blind adversarial audit with structured findings | Industry standard for competitive audits; EXTERNAL-AUDIT-PROMPT.md already codifies this |
| Multi-agent role specialization | Different agents find different vulnerability classes | Research shows specialized perspectives (contract, economic, zero-day) catch complementary issues |
| Regression diff methodology | Line-by-line re-verification of prior findings | Proven pattern from v1.2-delta-attack-reverification.md (8/8 re-verified with updated line numbers) |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| Manual code tracing | Line-by-line attack path verification | Every warden agent finding must trace to specific file:line |
| Hardhat test suite | Regression validation (1074 passing) | Confirm no test regressions after any changes |
| Foundry fuzz tests | Invariant testing for new claims | If any warden claims an invariant violation |
| FINAL-FINDINGS-REPORT.md | Canonical findings registry | Source of truth for all formal findings |
| KNOWN-ISSUES.md | Known design trade-offs | Pre-existing acknowledged issues that wardens should not re-report |

## Architecture Patterns

### Phase Decomposition

```
Phase 22: Warden Simulation + Regression Check
  |
  |-- Plan 22-01: Multi-Agent Warden Simulation (NOVEL-07)
  |   |-- Task 1: Contract Auditor Agent (storage, reentrancy, CEI, access control)
  |   |-- Task 2: Zero-Day Hunter Agent (EVM-level, composition, temporal, unchecked)
  |   |-- Task 3: Economic Analyst Agent (MEV, flash loan, pricing, solvency)
  |
  |-- Plan 22-02: Regression Verification (NOVEL-08)
  |   |-- Task 1: Formal findings regression (M-02, DELTA-L-01, I-03 through I-22, DELTA-I-01 through DELTA-I-04)
  |   |-- Task 2: v1 requirements re-verification (56 requirements, spot-check critical ones)
  |   |-- Task 3: v1.0 attack scenarios + v1.2 delta surfaces re-verification
  |   |-- Task 4: Phase 21 novel findings still-valid check
  |
  |-- Plan 22-03: Cross-Reference and Consolidated Report (NOVEL-07 + NOVEL-08)
  |   |-- Task 1: Deduplicate warden findings against each other and prior corpus
  |   |-- Task 2: Merge regression results into consolidated findings report
  |   |-- Task 3: Update FINAL-FINDINGS-REPORT.md with Phase 22 results
```

### Warden Agent Personas

Each warden agent receives the EXTERNAL-AUDIT-PROMPT.md plus a role-specific focus area. The key is that agents operate BLIND -- they should not anchor on prior audit findings.

**Agent 1: Contract Auditor**
- Focus: Storage layout, delegatecall safety, reentrancy, CEI patterns, access control, state machine correctness
- Strengths: Systematic, thorough, follows code flow step-by-step
- Output: Structured C4A findings with file:line citations
- Key areas: All 14 core contracts + 10 modules; delegatecall pattern verification; modifier correctness; constructor safety

**Agent 2: Zero-Day Hunter**
- Focus: EVM-level exploits, unchecked arithmetic, assembly correctness, composition attacks, temporal edge cases, novel attack vectors
- Strengths: Creative, adversarial thinking, looks for unusual code paths
- Output: Exploit-first analysis -- attack path then code verification
- Key areas: `unchecked` blocks in all contracts; assembly SLOAD/SSTORE in libraries; forced ETH via selfdestruct; cross-function state interactions; game-over multi-step race conditions

**Agent 3: Economic Analyst**
- Focus: MEV, flash loans, sandwich attacks, pricing manipulation, solvency invariants, economic game theory
- Strengths: Quantitative, models economic viability, thinks in terms of profit/cost
- Output: EV calculations with concrete numbers for each attack vector
- Key areas: DGNRS burn-redeem economics; stETH yield timing; pool BPS splitting; lootbox EV manipulation; affiliate farming; vault share math; deity pass pricing

### Regression Check Methodology

The regression check follows the proven pattern from `v1.2-delta-attack-reverification.md`:

For each prior finding:
1. State the original finding ID, severity, contract, and description
2. Locate the specific code referenced (file:line)
3. Verify the guard/mechanism/pattern is still present at current line numbers
4. Note any delta (line number shifts, structural changes, unchanged)
5. Render verdict: STILL VALID / FIXED / N/A / REGRESSED

### Anti-Patterns to Avoid
- **Anchoring on prior findings:** Warden agents must be BLIND -- do not provide them access to prior audit findings
- **Same-model bias:** The EXTERNAL-AUDIT-PROMPT.md explicitly warns about this -- ideally use a different model, but since all agents are Claude they MUST operate independently with no cross-contamination
- **Regression check as rubber stamp:** Each finding must be re-verified with current file:line evidence, not assumed unchanged
- **Severity inflation by wardens:** Strict C4A severity calibration -- H requires direct loss/theft, M requires meaningful value loss under specific conditions
- **Combining new and known findings:** Wardens report everything; the deduplication plan filters out known issues

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Blind audit prompt | Custom prompt per agent | EXTERNAL-AUDIT-PROMPT.md (258 lines) | Already battle-tested, covers all 10 audit areas, includes threat model and severity calibration |
| Finding deduplication | Ad-hoc comparison | Formal cross-reference table: finding ID vs prior ID vs status | Ensures no finding is silently dropped or double-counted |
| Regression methodology | Abstract re-review | v1.2-delta-attack-reverification.md pattern (original -> current code check -> delta -> verdict) | Proven pattern that successfully re-verified 8/8 attack scenarios |
| Consolidated report format | New report format | Update existing FINAL-FINDINGS-REPORT.md | Maintains single source of truth rather than fragmenting findings |

## Common Pitfalls

### Pitfall 1: Warden Agents Re-Discovering Known Issues
**What goes wrong:** Agents spend time reporting M-02, DELTA-L-01, and informational findings that are already documented in KNOWN-ISSUES.md.
**Why it happens:** Agents are blind by design; they SHOULD find these if they are doing their job.
**How to avoid:** Do NOT prevent agents from finding them. Instead, the deduplication step (Plan 22-03) filters known issues. A warden finding a known issue is VALIDATION, not waste.
**Warning signs:** If NO warden finds M-02, the agent's coverage is likely incomplete.

### Pitfall 2: Regression Check Missing Line Number Shifts
**What goes wrong:** Code was reorganized, line numbers shifted, and the regression check marks a finding as "unchanged" because the function name is the same, but misses that the actual guard moved or was restructured.
**Why it happens:** Lazy pattern matching on function names instead of verifying the actual guard logic at the current line.
**How to avoid:** For each finding, grep/search the current code for the specific guard pattern, not just the function name. Verify the guard logic matches, not just that the function exists.
**Warning signs:** All findings marked "UNCHANGED" with no line number updates.

### Pitfall 3: Warden Agents Producing Speculative Findings
**What goes wrong:** Agents report "possible reentrancy" or "potential overflow" without concrete attack paths, producing noise that must be triaged.
**Why it happens:** Wardens are incentivized to find issues; they may report uncertain findings.
**How to avoid:** EXTERNAL-AUDIT-PROMPT.md already addresses this: "Prefer one real bug over ten speculative claims." Enforce finding quality bar: file:line references, concrete attack path, quantified economic impact.
**Warning signs:** Findings without file:line citations or "possible" / "maybe" / "potential" without verification.

### Pitfall 4: Regression Check Scope Creep
**What goes wrong:** The regression check expands into a full re-audit, taking 10x longer than necessary.
**Why it happens:** Every finding leads to "but what about this adjacent code?"
**How to avoid:** Strict scope: verify the SPECIFIC mechanism referenced in the original finding. Do not audit adjacent code. That is the wardens' job.
**Warning signs:** Regression tasks generating more than 20 lines of analysis per finding.

### Pitfall 5: Not Testing After Changes
**What goes wrong:** A regression is found and fixed, but the fix introduces a new test failure.
**Why it happens:** Code changes without running the test suite.
**How to avoid:** If ANY code changes are made (which should be rare -- this phase is primarily analysis), run `npx hardhat test` to confirm 1074+ passing, 26 pre-existing failures, 0 new failures.
**Warning signs:** Skipping test runs after any code modification.

## Code Examples

### Warden Agent Prompt Structure

Each agent receives the EXTERNAL-AUDIT-PROMPT.md content plus a role-specific preamble:

```markdown
# Agent Role: {Contract Auditor | Zero-Day Hunter | Economic Analyst}

You are one of three independent wardens reviewing this protocol.
Your specific focus areas are: {role-specific focus list}.
Other agents cover different areas -- do NOT try to be comprehensive.
Spend 80% of your time on your focus areas, 20% on general review.

Do NOT anchor on any prior audit. Review the code fresh.
Do NOT assume safety because other agents are also reviewing.

{EXTERNAL-AUDIT-PROMPT.md content follows}
```

### Regression Verification Entry Pattern
```markdown
### Finding: {ID} -- {Title}

**Original:** {severity}, {contract}, {description}
**Original Evidence:** {file:line from original report}

**Current Code Check:**
- {guard/mechanism 1}: {current file:line} -- {PRESENT/ABSENT/CHANGED}
- {guard/mechanism 2}: {current file:line} -- {PRESENT/ABSENT/CHANGED}

**Delta:** {UNCHANGED / LINE_SHIFT / STRUCTURAL_CHANGE / REGRESSED}
**Current Verdict:** {STILL VALID / FIXED / N/A / REGRESSED}
```

### Cross-Reference Deduplication Table
```markdown
| Warden Finding | Severity | Matches Prior | Prior ID | Status |
|----------------|----------|---------------|----------|--------|
| W1-H-01: ... | High | YES | M-02 | KNOWN -- already in KNOWN-ISSUES.md |
| W2-M-01: ... | Medium | NO | -- | NEW -- requires triage |
| W3-L-01: ... | Low | YES | DELTA-L-01 | KNOWN -- validates prior finding |
| W1-QA-01: ... | QA | PARTIAL | I-20 | KNOWN -- extends prior observation |
```

## Complete Findings Inventory for Regression Check (NOVEL-08)

This is the exhaustive list of all findings that must be regression-checked:

### Formal Findings (14 total)

| ID | Severity | Contract | Status | Description |
|----|----------|----------|--------|-------------|
| M-02 | Medium | DegenerusGame/DegenerusAdmin | Acknowledged | Admin + VRF failure scenarios |
| DELTA-L-01 | Low | DegenerusStonk | Acknowledged | DGNRS transfer-to-self token lock |
| I-03 | Info | EntropyLib | Acknowledged | Non-standard xorshift constants |
| I-09 | Info | DegenerusAdmin | Acknowledged | wireVrf() lacks re-init guard |
| I-10 | Info | DegenerusAdmin | Acknowledged | wireVrf() lacks zero-address check |
| I-13 | Info | LootboxModule | Acknowledged | Hardcoded 80% lootbox reward rate |
| I-17 | Info | Affiliate | Acknowledged | Non-VRF affiliate winner entropy |
| I-19 | Info | Game | Acknowledged | Auto-rebuy dust as untracked ETH |
| I-20 | Info | StakedDegenerusStonk | Acknowledged | stETH 1-2 wei rounding retained |
| I-22 | Info | Game/AdvanceModule | Acknowledged | _threeDayRngGap() duplication |
| DELTA-I-01 | Info | StakedDegenerusStonk | Acknowledged | Stale poolBalances after burnRemainingPools |
| DELTA-I-02 | Info | DegenerusStonk | Acknowledged | Stray ETH locked in DGNRS |
| DELTA-I-03 | Info | StakedDegenerusStonk | By Design | previewBurn/burn ETH split discrepancy |
| DELTA-I-04 | Info | DegenerusGameStorage | Acknowledged | Stale comment at line 1086 |

### v1.0 Attack Scenarios (8 + FIX-1)
From `v1.2-delta-attack-reverification.md` -- all re-verified at v1.2, need re-verification at v2.0:

1. VRF Callback Race Condition (BLOCKED)
2. Deity Pass Purchase During Jackpot (BLOCKED)
3. Ticket Purchase Manipulation During Lock (SAFE)
4. Lootbox Open Timing Manipulation (SAFE)
5. Nudge Grinding / reverseFlip (SAFE)
6. Block Builder VRF Front-Running (SAFE)
7. Stale RNG Word Exploitation (SAFE)
8. 50% Ticket Conversion Economic Impact (SAFE)
9. FIX-1: claimDecimatorJackpot Freeze Guard (CONFIRMED)

### v1.2 Delta Surface Analysis (35 total)
From `v1.2-delta-rng-impact-assessment.md`:
- 9 NEW SURFACE findings
- 26 MODIFIED SURFACE findings

### Manipulation Window Verdicts (from v1.2-manipulation-windows.md)
- 9 daily RNG manipulation windows (D1-D9, all BLOCKED/SAFE)
- 6 lootbox RNG manipulation windows (L1-L6, all BLOCKED/SAFE)
- Additional temporal edge cases

### v1 Requirements (56 total)
From FINAL-FINDINGS-REPORT.md requirement coverage matrix. All PASS. Spot-check the critical ones:
- ACCT-01 through ACCT-10 (ETH solvency)
- RNG-01 through RNG-10 (VRF integrity)
- XCON-01 through XCON-07 (cross-contract safety)

### v2.0 DELTA Requirements (8 total)
All PASS in v2.0-delta-findings-consolidated.md.

### Phase 21 NOVEL Analyses (9 total)
All SAFE in novel-01 through novel-04. Verify the specific SAFE verdicts still hold:
- NOVEL-01: 5 economic vectors (flash loan, selfdestruct, sandwich, donation, accumulation)
- NOVEL-02: 5 composition call chains
- NOVEL-03: 6 griefing vectors
- NOVEL-04: 15 edge cases
- NOVEL-05: 4 invariants
- NOVEL-09: 4 escalation vectors
- NOVEL-10: stETH rebasing (< $2 extractable)
- NOVEL-11: 5 race conditions (algebraic proof)
- NOVEL-12: 4 amplifier scenarios

### Adversarial Sessions (4)
ADVR-01 through ADVR-04 from KNOWN-ISSUES.md -- all clean.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single-auditor review | Multi-agent adversarial with role specialization | 2024-2025 | Catches 30-40% more findings per academic research |
| Manual regression checking | Systematic finding-by-finding re-verification with line-level evidence | Standard practice | Prevents "assumed unchanged" errors |
| Separate findings per audit version | Consolidated findings report with version tracking | This project already uses this | Single source of truth in FINAL-FINDINGS-REPORT.md |
| Ad-hoc deduplication | Formal cross-reference table | Best practice | Ensures complete coverage, no silent drops |

## Open Questions

1. **Whether code has changed since Phase 21 completed**
   - What we know: Phase 21 was analysis-only (no code changes). Phase 20 made NatDoc and test changes.
   - What's unclear: Whether any commits between Phase 21 completion and Phase 22 start modified contract code.
   - Recommendation: Git diff check at plan execution time. If no code changes, regression check is simpler (line numbers should match Phase 21 evidence exactly).

2. **Warden agent independence**
   - What we know: All three agents will be Claude instances. Same model = potential for same blind spots.
   - What's unclear: How much the role-specific focus actually diversifies findings.
   - Recommendation: Accept this limitation and document it. The value is in systematic coverage, not model diversity. The EXTERNAL-AUDIT-PROMPT.md note about using different models applies but is not feasible in this automation context.

3. **Regression check depth for 56 v1 requirements**
   - What we know: All 56 requirements passed in v1.0-v1.2 audit. v2.0 delta audit confirmed "no requirement affected by the split."
   - What's unclear: Whether a full re-check of all 56 is necessary or spot-checking critical categories suffices.
   - Recommendation: Spot-check the 10 highest-risk categories (ACCT, RNG, XCON) rather than re-verifying all 56. The v2.0 delta audit already confirmed structural compatibility.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat + Foundry (dual framework) |
| Config file | `hardhat.config.js` (Hardhat), `foundry.toml` (Foundry) |
| Quick run command | `npx hardhat test test/edge/DGNRSLiquid.test.js` |
| Full suite command | `npx hardhat test` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NOVEL-07 | Multi-agent warden simulation produces findings | manual-only | N/A -- analysis output, not code | N/A |
| NOVEL-08 | Regression check verifies all prior findings | manual-only (with spot-check tests) | `npx hardhat test` (full suite, confirms no regression) | Existing suite |

### Sampling Rate
- **Per task commit:** No code changes expected -- this is analysis-only
- **Per wave merge:** `npx hardhat test` if ANY code changes are made
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers all phase requirements. Phase 22 is primarily analysis and documentation, not code changes. If any fix is needed (unlikely given prior audit results), existing test infrastructure is sufficient.

## Sources

### Primary (HIGH confidence)
- Project audit corpus: 33 audit documents, 30,705 lines (read directly from `audit/` directory)
- FINAL-FINDINGS-REPORT.md -- canonical findings registry with all 13 formal findings and 64 requirement verdicts
- KNOWN-ISSUES.md -- acknowledged design trade-offs and adversarial session results
- EXTERNAL-AUDIT-PROMPT.md -- ready-made blind audit prompt (258 lines)
- v1.2-delta-attack-reverification.md -- proven regression check methodology
- v2.0-delta-findings-consolidated.md -- v2.0 delta findings with requirement coverage
- Phase 21 novel attack reports (novel-01 through novel-04) -- latest adversarial analysis

### Secondary (MEDIUM confidence)
- [Code4rena audit methodology](https://code4rena.com/how-it-works) -- C4A warden process and severity calibration
- [Multi-agent smart contract audit research](https://thesai.org/Downloads/Volume15No5/Paper_76-Enhancing_Smart_Contract_Security.pdf) -- Multi-agent framework showing specialized roles improve coverage

### Tertiary (LOW confidence)
- [Veritas Protocol multi-agent framework](https://www.veritasprotocol.com/blog/multi-agent-ai-framework-for-smart-contract-security?9b368c60_page=45) -- Commercial multi-agent audit approach (not verified against academic literature)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- methodology is well-established (C4A warden + regression diff)
- Architecture: HIGH -- pattern proven by v1.2-delta-attack-reverification.md and Phase 21 novel analysis
- Pitfalls: HIGH -- derived from direct experience with this project's audit history
- Findings inventory: HIGH -- exhaustive enumeration from actual audit documents in the repository

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (stable -- methodology and findings corpus are project-specific, not technology-dependent)
