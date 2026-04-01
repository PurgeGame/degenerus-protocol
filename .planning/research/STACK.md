# C4A Contest Mechanics: Rules, Severity, Payouts, and Judging

**Project:** Degenerus Protocol -- v9.0 Contest Dry Run
**Researched:** 2026-03-28
**Confidence:** HIGH (verified against official Code4rena documentation and multiple corroborating sources)

---

## Purpose

This document captures the rules engine that governs Code4rena competitive audits. The v9.0 milestone simulates realistic C4A warden behavior -- every simulated warden agent must follow these rules to produce findings that match what real wardens would submit, at the severity levels real judges would assign, targeting the payouts that real incentives would drive.

---

## Severity Classification

C4A uses a strict three-tier system for payable findings (High/Medium) plus two bulk-report categories (QA/Gas). There is no "Critical" tier -- C4A's highest is High.

### High Severity

**Definition:** Assets can be stolen, lost, or compromised directly. Or indirectly if there is a valid attack path that does not have hand-wavy hypotheticals.

**Concrete criteria:**
- Direct theft of user funds or protocol funds
- Permanent freezing of funds (no recovery path)
- Protocol insolvency (liabilities exceed assets)
- Unauthorized minting/burning that extracts value
- RNG manipulation that lets an attacker guarantee favorable outcomes

**Proof requirement:** Coded, runnable PoC is REQUIRED for all High submissions in Solidity/EVM audits.

**Share weight:** 10 base shares per unique High finding.

**For Degenerus simulation:** Maps to the contest README's "critical finding" language for RNG integrity and money correctness. A warden proving unauthorized ETH extraction or RNG manipulation with a concrete PoC = High.

### Medium Severity

**Definition:** Assets are not at direct risk, but the function of the protocol or its availability could be impacted, or leak value with a hypothetical attack path with stated assumptions but external requirements.

**Concrete criteria:**
- Griefing that blocks protocol functionality (DoS)
- Gas ceiling breach that prevents essential functions from executing
- Value leakage under specific (but realistic) conditions
- Governance manipulation that bypasses intended checks
- State corruption that degrades protocol function without direct fund loss

**Proof requirement:** Coded, runnable PoC is REQUIRED for all Medium submissions in Solidity/EVM audits.

**Share weight:** 3 base shares per unique Medium finding.

**For Degenerus simulation:** Maps to "medium finding" in the contest README for admin resistance failures. A warden proving a hostile admin can damage the game without governance approval = Medium. Gas ceiling breach under attacker-forceable conditions = High (per the README, which elevates this).

### Low Severity (QA Category)

**Definition:** Non-critical issues -- code style, clarity, syntax, versioning, off-chain monitoring (events), and low-risk findings where assets are not at risk but best practices are violated.

**Key rule:** Low findings CANNOT be submitted individually. They MUST be bundled into a single QA report per warden.

**Share weight:** QA reports compete for 4% of the total pool. Only top 3 QA reports receive awards, graded A/B/C by the judge.

**For Degenerus simulation:** The contest README explicitly says "everything else is noise" beyond the 4 priority areas. QA-grade findings are low-value for wardens. Simulated wardens should deprioritize these.

### QA Report (Bulk Category)

**Contents:** All Low severity + Non-critical findings bundled together.
**Grading:** Judge assigns A (score 2), B (score 1), or C (score 0.5).
**Awards:** Top 3 reports only, from the 4% QA pool.
**Quality bar:** "Only submissions that demonstrate full effort worthy of consideration for inclusion in the report will be eligible for rewards."

### Gas Report (Bulk Category)

**Contents:** All gas optimization recommendations bundled together.
**Awards:** Separate allocation (historically ~2-5% of pool). Top reports only.
**For Degenerus:** The contest README puts gas optimization OUT OF SCOPE. Gas reports would be rejected.

### Governance / Centralization Risk

**Rule:** All centralization risk findings must be submitted as part of the QA report, not as individual High/Medium findings.
**For Degenerus:** The contest README already acknowledges admin risk and defines the trust model (hostile admin + engaged community). Centralization findings that merely restate "admin has power" without demonstrating bypass of governance = QA at best, invalid at worst.

---

## What Makes a Finding "Payable" vs "Rejected"

### Payable Finding Requirements

1. **Novel** -- Not in the contest's Known Issues / Automated Findings section
2. **In scope** -- Targets contracts listed as in-scope in the contest README
3. **Correctly severed** -- Severity matches the rubric (assets at risk = High, protocol function impacted = Medium)
4. **Proved** -- Coded PoC for H/M in Solidity/EVM audits
5. **Sufficiently described** -- "Comparable to a draft report by a professional auditor"
6. **Not a duplicate of a higher-quality submission** -- If duplicate, still receives partial shares

### Automatic Rejection Reasons

| Reason | Rule |
|--------|------|
| Known issue | Listed in KNOWN-ISSUES.md or contest README's known issues section |
| Out of scope | Target contract/category excluded in contest README |
| Automated tool finding | Covered by bot race results or disclosed automated findings |
| Insufficient proof | Judge needs to do additional research/coding to validate claims |
| Severity mismatch (downgrade to QA) | H/M submission downgraded to Low = **ineligible for any award** (penalty rule) |
| Hand-wavy hypotheticals | "Could theoretically happen if..." without concrete attack path |
| Informational only | No impact demonstrated, just an observation |
| Design disagreement | "I would have done X differently" without vulnerability |

### The Downgrade Penalty

This is the sharpest rule for simulation purposes: **High or Medium submissions downgraded by the judge to Low/QA are ineligible for ALL awards.** They don't even get QA credit. This means wardens are strongly disincentivized from submitting borderline findings as H/M -- the penalty for misjudging severity is total loss, not partial credit.

**Implication for simulation:** Simulated wardens should be conservative about severity classification. A finding that is genuinely Medium should be submitted as Medium. A finding that might be Low should go in QA, not be submitted as Medium hoping it sticks.

---

## Payout Formula

### Pool Structure

| Pool | Allocation | Recipients |
|------|-----------|------------|
| High + Medium pool | ~96% of total | All wardens with valid H/M findings |
| QA pool | ~4% of total | Top 3 QA reports only |
| Gas pool | Variable (often 0-5%) | Top gas reports (when in scope) |

### Share Calculation for H/M Findings

Each unique finding creates a "pie." The pie size depends on severity and how many wardens found it.

**Formula:**
```
High Risk Pie  = 10 * (0.85 ^ (duplicateCount - 1))
Medium Risk Pie = 3 * (0.85 ^ (duplicateCount - 1))
```

Each warden who found the same issue gets a "slice":
```
Slice = Pie / duplicateCount
```

**Report inclusion bonus:** The submission selected as the best write-up for the audit report gets a 30% slice bonus.

**Hunter bonus:** 10% of the H/M pool goes to the warden who finds the most unique H/M findings.

### Payout Examples

**Solo High finding (1 warden finds it):**
```
Pie = 10 * (0.85 ^ 0) = 10
Slice = 10 / 1 = 10 shares
+ 30% report bonus = 13 shares
```

**High finding with 5 duplicates:**
```
Pie = 10 * (0.85 ^ 4) = 5.22
Slice = 5.22 / 5 = 1.04 shares each
Best write-up gets: 1.04 * 1.3 = 1.35 shares
```

**Solo Medium finding:**
```
Pie = 3 * (0.85 ^ 0) = 3
Slice = 3 / 1 = 3 shares
+ 30% report bonus = 3.9 shares
```

**Medium finding with 10 duplicates:**
```
Pie = 3 * (0.85 ^ 9) = 0.69
Slice = 0.69 / 10 = 0.069 shares each
```

### What This Incentivizes

The exponential decay (0.85^n) and division by n create extreme value concentration:

| Finding Type | Solo Value | 3 Duplicates | 10 Duplicates | 50 Duplicates |
|-------------|-----------|--------------|---------------|---------------|
| High | 10.0 | 2.41 | 0.20 | 0.001 |
| Medium | 3.0 | 0.72 | 0.059 | 0.0003 |

**Key insight for simulation:** A solo Medium is worth MORE than a High with 5+ duplicates. Top wardens hunt for unique findings, not obvious ones. The payout structure punishes "me too" submissions severely.

**Behavioral implication:** Real wardens spend ~60-70% of their time on deep, unique analysis of complex logic (seeking solo H/M finds) and ~30-40% on systematic coverage. Bot-detectable findings (reentrancy patterns, missing checks on standard operations) are essentially worthless because 50+ wardens will all find them.

---

## Duplicate Rules

### Core Rule
All submissions that identify the **same functional vulnerability** are duplicates, regardless of:
- Different exploit paths to the same root cause
- Different severity rationale
- Different PoC approaches

### Partial Credit
Submissions that identify the root cause but fail to demonstrate the highest-impact exploit path receive partial credit:
- 75% of shares: identified root cause, close to full impact
- 50% of shares: identified root cause, partial impact understanding
- 25% of shares: identified root cause, minimal impact understanding

Judge has sole discretion on partial credit percentages.

### Partial Credit Still Counts as a Duplicate
Partial-credit submissions count as 1 in the duplicate count (affecting the 0.85^n decay) but the submitting warden receives reduced shares.

### What Is NOT a Duplicate
- Different root causes producing similar symptoms
- Same contract but different vulnerable functions with independent fixes
- Same vulnerability class (e.g., reentrancy) in unrelated code paths

---

## Contest Timeline

### Typical Duration
- **Short contests:** 3 days (small scope, focused audit)
- **Standard contests:** 5-7 days (most common)
- **Large contests:** 14-28 days (massive codebases)

### Phase Timeline

| Phase | Duration | What Happens |
|-------|----------|-------------|
| **Contest active** | 3-28 days | Wardens review code, submit findings |
| **Judging** | 1-4 weeks | Judge reviews all submissions, assigns severity, groups duplicates |
| **Post-judging QA** | 48 hours | Sponsor and wardens comment on preliminary judgments |
| **Final judging** | 1-2 weeks | Judge incorporates QA feedback, finalizes awards |
| **Report publication** | After final | Audit report published with selected findings |

### For Degenerus Simulation
The Degenerus codebase (~15,000 lines, 24 contracts) would likely be a 7-14 day contest. Simulated wardens should allocate time as a real warden would over that period.

---

## Typical Warden Workflow and Time Allocation

### Phase 1: Reconnaissance (10-15% of time)

1. Read the contest README thoroughly -- understand what the sponsor cares about
2. Read KNOWN-ISSUES.md -- everything listed there is wasted effort
3. Map the architecture -- which contracts interact with which
4. Identify high-value targets based on sponsor's stated priorities

### Phase 2: Deep Analysis (60-70% of time)

1. Trace money flows (ETH in, ETH out, token minting, token burning)
2. Trace permission boundaries (who can call what, under what conditions)
3. Trace state transitions (what state changes enable what subsequent actions)
4. Focus on cross-contract interactions and edge cases
5. Build PoCs for any suspicious behavior

### Phase 3: Systematic Coverage (15-25% of time)

1. Check for standard vulnerability classes (reentrancy, integer overflow, access control)
2. Review event emissions and return values
3. Gas analysis (if in scope)
4. Compile QA report from low-severity findings

### Phase 4: Write-up and Submission (5-10% of time)

1. Write clear, professional finding descriptions
2. Include coded PoC for every H/M submission
3. Bundle Low/Non-critical into QA report
4. Submit before the deadline (forms slow down near cutoff)

### Top Warden Tools

| Tool | Purpose |
|------|---------|
| Foundry (forge) | PoC development, testing exploit paths |
| Slither | Static analysis baseline (but findings are usually pre-disclosed) |
| VS Code + Solidity extensions | Code navigation, cross-reference |
| Etherscan / block explorers | If mainnet fork testing needed |
| Custom scripts | Automated pattern scanning, state tracing |
| Manual code review | Still the primary method for High/Medium findings |

---

## Implications for Degenerus v9.0 Simulation

### What Real Wardens Would Target (Based on Contest README)

The contest README explicitly states 4 priorities. Smart wardens read this first and allocate accordingly:

1. **RNG Integrity (Critical/High):** VRF commitment windows, request-to-fulfillment manipulation, block proposer bias. Solo findings here = maximum payout.

2. **Gas Ceiling Safety (High):** advanceGame paths that an attacker can force to exceed block gas limit. This is elevated to High per the README.

3. **Money Correctness (Critical/High):** ETH/token accounting errors enabling unauthorized extraction.

4. **Admin Resistance (Medium):** Hostile admin without governance approval causing damage. Capped at Medium per the README.

### What Real Wardens Would NOT Target

- Gas optimization (explicitly out of scope = zero payout)
- Code style / NatSpec (out of scope)
- ERC-20 deviations in DGNRS/BURNIE (documented as intentional)
- sDGNRS/GNRUS "ERC-20 compliance" (soulbound tokens, not ERC-20)
- Anything in KNOWN-ISSUES.md (34+ entries pre-disclosed)
- Bot race findings (Slither + 4naly3er already run and disclosed)

### Behavioral Model for Simulated Wardens

Each simulated warden should:

1. **Start fresh** -- zero prior context, read only what a real warden would have access to (contest README, KNOWN-ISSUES.md, contract source code)
2. **Follow the money** -- trace ETH flows and token accounting first
3. **Seek uniqueness** -- the payout formula crushes duplicate value; focus on deep, non-obvious analysis
4. **Require PoC** -- every H/M finding must include a coded, runnable exploit
5. **Be severity-conservative** -- the downgrade penalty (H/M downgraded to QA = zero payout) means borderline findings should be submitted at lower severity
6. **Check known issues first** -- any finding already in KNOWN-ISSUES.md = wasted effort and zero payout
7. **Produce concrete output** -- "SAFE proof" or "exploit PoC", never vague observations

### Severity Mapping for Degenerus Contest

| Contest README Language | C4A Severity | Payout Tier |
|------------------------|-------------|-------------|
| "critical finding" (RNG manipulation, unauthorized extraction) | High | 10 base shares |
| "high finding" (gas ceiling breach) | High | 10 base shares |
| "medium finding" (admin damage without governance) | Medium | 3 base shares |
| Everything else | QA (if valid) | 4% pool, top 3 only |

---

## Sources

- [Code4rena Awarding Documentation](https://docs.code4rena.com/awarding) -- payout formula, share calculation, duplicate rules, partial credit, hunter bonus
- [Code4rena Submission Guidelines](https://docs.code4rena.com/competitions/submission-guidelines) -- severity definitions, PoC requirements, QA/Gas report rules, known issue exclusions
- [Code4rena Severity Standardization](https://medium.com/code4rena/severity-standardization-in-code4rena-1d18214de666) -- High/Medium definitions, judge discretion, standardization rationale
- [Code4rena Competitions Documentation](https://docs.code4rena.com/competitions) -- contest timeline, post-judging QA phase, sponsor acknowledgment
- [Code4rena How Wardens Work](https://code4rena.com/how-it-works/wardens) -- warden registration, participation mechanics
- [Competitive Audit Strategy Guide](https://medium.com/@JohnnyTime/complete-audit-competitions-guide-strategies-cantina-code4rena-sherlock-more-bf55bdfe8542) -- warden workflow, time allocation, tool usage

---
*Stack research for: v9.0 C4A Contest Dry Run*
*Researched: 2026-03-28*
