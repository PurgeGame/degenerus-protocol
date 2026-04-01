# Phase 138: KNOWN-ISSUES Triage + Contest README Fixes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 138-known-issues-triage-contest-readme-fixes
**Areas discussed:** Triage criteria, Quantification depth, Admin resistance framing, README tone/structure

---

## Triage Criteria

### Q1: What should happen to design documentation entries?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete them | Remove entirely — they don't belong and add noise | |
| Separate section | Keep in KNOWN-ISSUES.md under a 'Design Decisions' header | |
| Move to NatSpec | Put the explanation in contract comments, remove from KNOWN-ISSUES.md | x |

**User's choice:** Move to NatSpec
**Notes:** Design docs belong in the code. KNOWN-ISSUES.md should only contain things a warden could file.

### Q2: Triage flow — autonomous or reviewed?

| Option | Description | Selected |
|--------|-------------|----------|
| Agent triages, I review | Agent classifies all entries, presents table, user approves/overrides | x |
| Fully autonomous | Agent triages and executes without review | |

**User's choice:** Agent triages, I review

---

## Quantification Depth

### Q1: How deep should fuzzy claim quantification go?

| Option | Description | Selected |
|--------|-------------|----------|
| Quick worst-case | Back-of-envelope estimates | |
| Rigorous computation | Exact worst-case with real constants | |
| Only where material | Quick for most, rigorous only where worst case could exceed dust | x |

**User's choice:** Only where material

---

## Admin Resistance Framing

### Q1: How much vesting detail to expose?

| Option | Description | Selected |
|--------|-------------|----------|
| Full mechanics | 50B initial, 5B/level, vault owner claims, level 30 | |
| High-level only | 'Creator allocation vests linearly over 30 levels' | |
| Threat model focus | 'Admin cannot dominate governance after level X' — security property | x |

**User's choice:** Threat model focus

### Q2: Framing for Chainlink-death-gated governance paths?

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit prerequisite | Clear statement in README | |
| Threat scenario | WAR-01/WAR-02 update in KNOWN-ISSUES | |
| Both | Prerequisite in README, scenario in KNOWN-ISSUES | x |

**User's choice:** Both

---

## README Tone/Structure

### Q1: Are the 4 priorities still right?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep all 4 | Admin still matters, just update description | |
| Merge admin into money | Admin-steals-funds is money correctness. Drop to 3. | x |
| Reorder | Keep 4 but reorder: Money > RNG > Gas > Admin | |

**User's choice:** Merge admin into money

### Q2: Out-of-scope aggressiveness?

| Option | Description | Selected |
|--------|-------------|----------|
| Keep as-is | 9 categories comprehensive enough | x |
| Tighten wording | Sharper language | |
| Add vesting/rngLocked | Explicitly mark new changes as out-of-scope | |

**User's choice:** Keep as-is

---

## Claude's Discretion

None — all areas had explicit user decisions.

## Deferred Ideas

None — discussion stayed within phase scope.
