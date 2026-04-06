# Phase 195: Jackpot Two-Call Split - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-06
**Phase:** 195-jackpot-two-call-split
**Mode:** discuss (interactive)
**Areas discussed:** Split boundary logic, Packed slot layout

## Discussion Summary

### Split Boundary Logic
- **Initial proposal:** Split by bucket type — largest+solo in call 1, two mid in call 2 (from ROADMAP)
- **User correction:** Don't allow buckets to be too big. Cap largest at 159, mid buckets at 100 and 60. Solo always 1.
- **Outcome:** Differentiated per-bucket caps replace single MAX_BUCKET_WINNERS=250. Each call guaranteed ≤160 winners.

### Packed Slot Layout
- **Initial proposal:** Store paidEthSoFar for inter-call accounting
- **User correction:** Why do we need paidEthSoFar? Per-winner payouts happen inline. Just store the total jackpot amount so call 2 knows the correct share base.
- **Follow-up:** Need to preserve original ethPool before payouts reduce it, so call 2 computes identical bucket shares.
- **Outcome:** Store original ethPool as uint128. Non-zero = resume pending.

### Resume Stage (not directly discussed, carried from ROADMAP)
- Stage 8 (unused gap) becomes STAGE_JACKPOT_ETH_RESUME
- Both daily and early-burn paths share this resume stage

## Areas Skipped
- Resume stage design — user was satisfied with ROADMAP specification (stage 8)
