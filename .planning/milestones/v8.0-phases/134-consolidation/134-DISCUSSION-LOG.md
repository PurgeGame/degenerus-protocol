# Phase 134: Consolidation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 134-consolidation
**Areas discussed:** KNOWN-ISSUES structure, Fix-vs-document triage, Final summary format, C4A contest README scoping

---

## KNOWN-ISSUES Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Flat by severity (Recommended) | Keep existing sections + add new ones grouped by severity/category | ✓ |
| Grouped by audit source | One section per phase output | |
| Single flat list | Everything in one big list with severity tags | |

**User's choice:** Flat by severity
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| 2-3 sentences (Recommended) | Title + explanation covering what tool flags and why intentional | ✓ |
| One-liner per entry | Bold title and one sentence | |
| Full triage reasoning | Copy full reasoning from triage docs | |

**User's choice:** 2-3 sentences
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, include detector IDs | Wardens can ctrl+F their tool output against known issues | ✓ |
| No, keep it tool-agnostic | Describe behavior, not tool finding | |

**User's choice:** Include detector IDs
**Notes:** None

---

## Fix-vs-Document Triage

| Option | Description | Selected |
|--------|-------------|----------|
| GAS-10: immutable vars | 10 constructor-only variables → immutable | manual review |
| DOC-03: dead code removal | Delete _lootboxBpsToTier (unused since v3.8) | ✓ |
| Keep all as DOCUMENT | No code changes | |
| Review L-4 encodePacked | 35 abi.encodePacked instances | |

**User's choice:** DOC-03 (fix), GAS-10 (manual review — present candidates for approval)
**Notes:** User wants to review immutable var candidates individually before any changes

---

## Final Summary Format

| Option | Description | Selected |
|--------|-------------|----------|
| audit/v8.0-findings-summary.md (Recommended) | Full summary in audit/ directory | |
| Inline in KNOWN-ISSUES.md header | Summary table at top of KNOWN-ISSUES | |
| Both | Full in audit/ + brief stats in KNOWN-ISSUES header | ✓ |

**User's choice:** Both
**Notes:** None

---

## C4A Contest README Scoping

| Option | Description | Selected |
|--------|-------------|----------|
| Draft it now (Recommended) | Produce draft C4A README section referencing KNOWN-ISSUES | ✓ |
| KNOWN-ISSUES only | Focus on KNOWN-ISSUES, README later | |

**User's choice:** Draft now
**Notes:** None

---

| Option | Description | Selected |
|--------|-------------|----------|
| Non-financial-impact findings | Gas, style, NatSpec, naming | ✓ |
| Known automated tool findings | Reference KNOWN-ISSUES.md | ✓ |
| Deployment/infrastructure | Scripts, off-chain VRF, frontend | ✓ |
| Formal verification gaps | Deferred items tracked separately | ✓ |

**User's choice:** All four categories
**Notes:** "What I would like is to not have to pay for stuff that has 0 chance of breaking my game. I don't care about my code being immaculate and formatted like it was written and edited by a whole team of people being paid. I'm an amateur who has never released any form of my code to the public. But I do care very much that my RNG cannot be compromised, nothing can make advanceGame cost too much gas to run and that the money is 100% right every time in every place. So I would like to get that point across as concisely as possible."

---

## Claude's Discretion

- Grouping/deduplication of overlapping findings
- Merging related entries into existing KNOWN-ISSUES items
- Exact C4A README wording
- GAS-7 unchecked arithmetic handling

## Deferred Ideas

None
