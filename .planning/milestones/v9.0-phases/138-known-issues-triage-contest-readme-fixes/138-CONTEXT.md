# Phase 138: KNOWN-ISSUES Triage + Contest README Fixes - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden KNOWN-ISSUES.md and C4A-CONTEST-README.md so that wardens and judges work from accurate, precise, defensible documentation. No code changes — documentation only (except NatSpec additions for relocated design docs).

</domain>

<decisions>
## Implementation Decisions

### Triage Criteria
- **D-01:** Every KNOWN-ISSUES.md entry classified as KNOWN-ISSUE (warden could file this, needs judge rejection) or DESIGN-DOC (not a filing risk — explains how the code works, not a bug).
- **D-02:** DESIGN-DOC entries are moved to NatSpec comments in the relevant contract, then removed from KNOWN-ISSUES.md. The explanation belongs in the code, not in an audit defense document.
- **D-03:** Agent performs the triage autonomously but presents the full classification table for user review before making changes. User approves or overrides individual classifications.

### Quantification Depth
- **D-04:** Fuzzy claims get quick worst-case estimates unless the worst case could plausibly exceed dust amounts. If material, do rigorous computation with real constants from the code. Don't burn time proving 3 wei is safe.

### Admin Resistance Framing
- **D-05:** Vesting detail is framed around the security property, not the mechanism: "admin cannot dominate governance after level X" — wardens care about the threat model, not the implementation.
- **D-06:** VRF coordinator swap and price feed swap: explicit prerequisite in README ("requires Chainlink death clock to trigger first"), detailed threat scenario in KNOWN-ISSUES.md showing the multi-factor requirement (compromised admin + Chainlink failure + community inattention).
- **D-07:** Bootstrap assumption corrected: creator holds DGNRS (not sDGNRS), allocation vests over 30 levels. The hostile admin threat model applies post-distribution.

### README Structure
- **D-08:** Drop from 4 priorities to 3: RNG Integrity, Gas Ceiling Safety, Money Correctness. Admin fund theft is a money correctness concern. Governance manipulation is pre-documented in KNOWN-ISSUES.md, not a separate warden priority.
- **D-09:** Severity language corrected throughout — C4A highest tier is High, not Critical.
- **D-10:** Out-of-scope section kept as-is (9 categories). No additions for vesting/rngLocked — those are design decisions documented in KNOWN-ISSUES.md.

### New Changes to Document
- **D-11:** Creator DGNRS vesting (50B initial + 5B/level, vault owner claims, level 30 full vest) documented in KNOWN-ISSUES.md as a design decision.
- **D-12:** unwrapTo guard change (5h lastVrfProcessed timestamp replaced with rngLocked() boolean) documented in KNOWN-ISSUES.md.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Current Documentation
- `KNOWN-ISSUES.md` — The file being triaged. Read every entry.
- `audit/C4A-CONTEST-README.md` — The contest README being updated.

### Contract Changes (for NatSpec additions)
- `contracts/DegenerusStonk.sol` — Vesting logic, rngLocked guard, claimVested()
- `contracts/StakedDegenerusStonk.sol` — Pool allocations, creator mint

### Research
- `.planning/research/STACK.md` — C4A severity tiers, payout mechanics, judging rules
- `.planning/research/PITFALLS.md` — Sponsor blind spots, fuzzy claim risks

### Prior Audit Artifacts
- `audit/v5.0-FINDINGS.md` — Master findings reference
- `audit/v8.0-findings-summary.md` — Latest findings consolidation

</canonical_refs>

<code_context>
## Existing Code Insights

### Relevant Contracts
- DegenerusStonk.sol now has vesting (claimVested), rngLocked guard, game constant
- StakedDegenerusStonk.sol has pool allocation constants (CREATOR_BPS = 2000)
- DegenerusAdmin.sol has governance paths referencing lastVrfProcessed (may need NatSpec update to note DGNRS uses rngLocked instead)

### KNOWN-ISSUES.md Structure
- Currently a flat list of bold-header paragraphs
- Mix of real issues (ERC-20 deviations, governance scenarios) and design documentation (boon coexistence, recycling bonus)
- ~34+ entries as of v8.1

### C4A README Structure
- 4 priorities section ("I Care About Four Things") — needs reduction to 3
- Out of Scope table (9 rows) — kept as-is
- Key Contracts table — accurate
- Architecture section — accurate

</code_context>

<specifics>
## Specific Ideas

- User explicitly called out boon coexistence and recycling bonus entries as design docs that don't belong in KNOWN-ISSUES.md
- Bootstrap assumption currently says "admin holds majority of sDGNRS" — wrong, admin holds DGNRS that can be unwrapped
- "Rounding favors solvency" is the canonical example of a fuzzy claim needing quantification
- Admin resistance merges into money correctness because "admin steals money" is the real concern — governance manipulation scenarios are pre-documented

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 138-known-issues-triage-contest-readme-fixes*
*Context gathered: 2026-03-28*
