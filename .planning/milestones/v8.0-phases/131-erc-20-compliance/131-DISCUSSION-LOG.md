# Phase 131: ERC-20 Compliance - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-27
**Phase:** 131-erc-20-compliance
**Areas discussed:** Deviation policy, Edge case scope, Output format

---

## Deviation Policy

| Option | Description | Selected |
|--------|-------------|----------|
| Not ERC-20 tokens | State sDGNRS/GNRUS are NOT ERC-20. Wardens can't file compliance issues on non-ERC-20. | ✓ |
| ERC-20 with deviations | Frame as ERC-20 with documented deviations | |
| You decide | Claude picks framing | |

**User's choice:** Not ERC-20 tokens
**Notes:** Defensive framing — invalidates warden filings on soulbound tokens

---

## Edge Case Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Standard edge cases | Zero-amount, self-transfer, max-uint, return values | |
| Deep + weird | Standard plus approve race, EIP-2612, zero-address, contract receiver, reentrancy | ✓ |
| You decide | Cover what wardens would file | |

**User's choice:** Deep + weird
**Notes:** None

---

## Output Format

| Option | Description | Selected |
|--------|-------------|----------|
| Per-token reports | 4 separate files | |
| Single consolidated | One doc with sections per token | ✓ |
| You decide | Claude picks format | |

**User's choice:** Single consolidated
**Notes:** Easier for Phase 134 to consume

---

## Claude's Discretion

- Per-finding severity assessment
- Whether to include ERC-20 metadata compliance

## Deferred Ideas

None
