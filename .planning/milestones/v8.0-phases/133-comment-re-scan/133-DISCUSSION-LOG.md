# Phase 133: Comment Re-scan - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 133-comment-re-scan
**Areas discussed:** Fix vs document policy, Scope boundary, Output format

---

## Fix vs Document Policy

| Option | Description | Selected |
|--------|-------------|----------|
| FIX comment issues directly | Edit contracts — comment changes are zero-risk to behavior | ✓ |
| DOCUMENT only | Same as Phases 130-132, let Phase 134 decide | |
| Hybrid | Fix obvious, document judgment calls | |

**User's choice:** FIX everything
**Notes:** Comments are free to change, incorrect comments actively mislead auditors. Last pass before C4A.

---

## Scope Boundary

| Option | Description | Selected |
|--------|-------------|----------|
| Full codebase sweep | Every .sol file including mocks | |
| Delta contracts only | Only contracts changed since v3.5 | |
| Production + interfaces, skip mocks | Wardens read interfaces but not mocks | ✓ |

**User's choice:** Production + interfaces, skip mocks
**Notes:** Initially selected "full codebase" but corrected to option 3. Wardens won't read mocks.

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Single audit doc + bot appendix | Same pattern as Phase 132 | |
| No audit doc — just fix and commit | Fixes are the deliverable, git history suffices | |
| Commit-per-contract + lightweight summary | Fix, commit individually, brief summary for Phase 134 | ✓ |

**User's choice:** Commit-per-contract + lightweight summary
**Notes:** Full audit doc is redundant when fixing. Phase 134 needs quick reference + bot-race appendix closure.

---

## Claude's Discretion

- Commit grouping (per-contract vs batching small files)
- NatSpec on arguably self-documenting functions
- Magic number handling (constants vs inline comments)

## Deferred Ideas

None — discussion stayed within phase scope
