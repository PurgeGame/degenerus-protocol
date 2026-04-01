# Phase 130: Bot Race - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 130-bot-race
**Areas discussed:** Tool setup, Triage policy, Finding disposition

---

## Tool Setup

### 4naly3er Installation

| Option | Description | Selected |
|--------|-------------|----------|
| You install it | Claude handles git clone + setup during execution phase | ✓ |
| I'll set it up | User installs before start | |
| Skip 4naly3er | Focus on Slither only | |

**User's choice:** You install it
**Notes:** None

### Contract Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Production only (Recommended) | 17 contracts + 5 libraries + 12 interfaces — matches C4A scope | ✓ |
| Everything | Include mocks and test helpers too | |

**User's choice:** Production only
**Notes:** None

### Detector Configuration

| Option | Description | Selected |
|--------|-------------|----------|
| All detectors, filter after | Maximum coverage — matches what C4A bots do | ✓ |
| High/medium only | Cleaner output but might miss something | |

**User's choice:** All detectors, filter after
**Notes:** None

---

## Triage Policy

### Default Disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Fix if cheap (<5 min) | Trivial fixes reduce warden filing surface | |
| Document everything | Add to KNOWN-ISSUES.md — minimize contract changes close to audit | ✓ |
| Fix medium+, document low | Fix medium+ severity, document low/informational | |

**User's choice:** Document everything
**Notes:** User wants to minimize contract changes this close to audit

### KNOWN-ISSUES.md Formatting

| Option | Description | Selected |
|--------|-------------|----------|
| One-liner per finding | Brief — enough for wardens to recognize | |
| Structured entries | Severity + location + reasoning per finding | |
| You decide | Claude picks appropriate detail level | ✓ |

**User's choice:** You decide
**Notes:** None

---

## Finding Disposition

### False Positive Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Bulk document as known | Group all FPs of same type into one KNOWN-ISSUES entry | |
| Per-function entries | Document each FP individually | |
| You decide | Claude judges per-finding whether to group or itemize | ✓ |

**User's choice:** You decide
**Notes:** None

### Escalation Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Escalate immediately | Stop and flag medium+ findings | |
| Batch for review | Present full triage at end — user decides in Phase 134 | ✓ |

**User's choice:** Batch for review
**Notes:** None

---

## Claude's Discretion

- KNOWN-ISSUES.md formatting and detail level per finding
- Whether to group or itemize false positives
- 4naly3er detector configuration

## Deferred Ideas

None
