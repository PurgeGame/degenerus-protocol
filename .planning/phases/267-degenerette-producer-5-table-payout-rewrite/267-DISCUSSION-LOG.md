# Phase 267: Degenerette Producer + 5-Table Payout Rewrite - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `267-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-10
**Phase:** 267-degenerette-producer-5-table-payout-rewrite
**Areas discussed:** `_countGoldQuadrants` signature reconciliation, plan decomposition shape, constant-verification policy, comment-rewrite granularity, `packedTraitsDegenerette` visibility (self-check follow-up)

---

## `_countGoldQuadrants` signature reconciliation

Pre-discussion conflict: REQUIREMENTS.md DGN-03 specified `(uint8[4]) internal pure returns (uint8)`; ROADMAP success criterion 2 + the planning note both specified `(uint32) private pure returns (uint8)` with body operating directly on the packed `uint32` ticket.

| Option | Description | Selected |
|--------|-------------|----------|
| `(uint32 ticket) private pure returns (uint8)` | Matches ROADMAP success criterion 2 + planning note implementation. Operates directly on packed ticket via shifts; zero unpack overhead at the `_fullTicketPayout` call site (which already has `playerTicket` as uint32). Plan task fixes REQUIREMENTS.md DGN-03 wording to match. | ✓ |
| `(uint8[4]) internal pure returns (uint8)` | Matches REQUIREMENTS.md DGN-03 as written. Forces caller to unpack `playerTicket` into a uint8[4] memory array before calling — ~5 SLOAD-equivalents extra mem-write + reads. Plan task fixes ROADMAP success criterion 2 + rewrites the planning-note body. | |

**User's choice:** `(uint32 ticket) private pure returns (uint8)`.
**Notes:** REQUIREMENTS.md DGN-03 wording will be corrected to match as a Phase 267 plan chore task. Decision recorded as D-267-COUNTGOLD-01.

---

## Plan decomposition shape

| Option | Description | Selected |
|--------|-------------|----------|
| Single multi-task plan (267-01-PLAN.md) | Mirror v33 P257 / v34 P262 / v35 P265 / v36 P266 single-plan precedent. Atomic-commit-per-task ordering: REQ DGN-03 fix → script verify → batched contract diff (USER-APPROVED) → phase-close summary. ~4-6 atomic commits total. | ✓ |
| Split: 267-01 TraitUtils + 267-02 DegeneretteModule | Cleaner ownership boundary between producer and consumer. Costs an extra plan-create overhead and breaks the "single batched contract commit" discipline. Planning note explicitly recommends single. | |
| Split: 267-01 prep (REQ fix + script verify) + 267-02 contract | Separates pre-flight chores from the contract change. Preserves single batched contract commit. Costs extra plan-create overhead vs single-plan. | |

**User's choice:** Single multi-task plan.
**Notes:** ~4 atomic commits total (REQ fix → script-verify → batched contract → phase-close). Decision recorded as D-267-PLAN-01. Carry-forward from v33/v34/v35/v36 single-multi-task pattern.

---

## Constant-verification policy

| Option | Description | Selected |
|--------|-------------|----------|
| Re-run script + grep-assert + Phase 268 STAT-05 empirical | Plan task: agent re-runs `derive_5_tables.py`, captures stdout, grep-asserts every constant byte-string in the script output matches the .sol pasted hex byte-for-byte; output captured into `267-01-CONSTANTS-VERIFY.md`. Phase 268 STAT-05 then verifies empirical drift ±0.5 centi-x. Closes the verification gap that bit Phase 259. | ✓ |
| Paste-only-trust + Phase 268 STAT-05 empirical drift | Trust the planning note's pasted constants. Phase 268 STAT-05 catches drift empirically. Lighter plan; relies on STAT-05 sample size to catch single-bit flips (paste typo could go undetected). | |
| Re-run script + grep-assert only (skip empirical) | Closes the script-vs-source gap but still leaves empirical EV-equality unverified — except STAT-05 is locked in Phase 268 anyway, so this option doesn't actually save anything vs (Recommended). | |

**User's choice:** Re-run script + grep-assert + Phase 268 STAT-05 empirical (three-part verification chain).
**Notes:** Decision recorded as D-267-CONSTVERIFY-01. Any byte-mismatch between script output and pasted .sol hex BLOCKS the contract commit. Phase 268 STAT-05 catches drift the script-grep missed.

---

## Comment-rewrite granularity (DGN-13)

| Option | Description | Selected |
|--------|-------------|----------|
| NatSpec-first + surgical inline (a + c blend) | Author full NatSpec on `packedTraitsDegenerette`, `_countGoldQuadrants`, `_getBasePayoutBps`, `_applyHeroMultiplier`, `_wwxrpFactor` describing per-N table dispatch + bit layout + EV invariant. DELETE § L287-298 'EXACT EV NORMALIZATION' prose entirely (it describes the deleted normalizer). Surgically rewrite L239 + L262 + L316 to per-N reality. Block headers L235-251 / L253-268 / L314-322 get fresh §-headers describing what IS. | ✓ |
| Surgical line-by-line (DGN-13 minimum) | Touch only the 4 named comment surfaces: L239, L262, L287-298, L316. Smallest diff blast radius; easiest §3.A row classification. Risk: surrounding comment context drifts into stale-by-association territory. | |
| Block-rewrite (replace L235-322 wholesale) | Delete § L235-322 entirely + author fresh per-N §-block prose. Largest blast radius; highest §3.A row count; cleanest "what IS" state. Risk: touches more lines than needed, makes audit-trail diff harder to read. | |

**User's choice:** NatSpec-first + surgical inline.
**Notes:** Decision recorded as D-267-COMMENTS-01. All comments framed in language of CURRENT design only (per `feedback_no_history_in_comments.md` — never references "this used to be" or "previous" anywhere). Phase 271 §3.A delta-surface row count higher than DGN-13 minimum but each row carries clear DOC-CLEANUP classification.

---

## `packedTraitsDegenerette` visibility (self-check follow-up)

Pre-discussion conflict: REQUIREMENTS.md DGN-01 + ROADMAP success criterion 1 + 5 + Phase 271 AUDIT-04 attestation specified `external pure` ("ALLOWED-NEW-STATELESS-ENTRY"). Planning note Solidity body: `internal pure`. Existing `packedTraitsFromSeed` at `contracts/DegenerusTraitUtils.sol:169` is `internal pure`. Surfaced during self-check after Areas 1-4 closed.

| Option | Description | Selected |
|--------|-------------|----------|
| `internal pure` (matches existing library convention) | Mirrors `packedTraitsFromSeed`. Inlined into consumer at L607 — zero DELEGATECALL overhead, zero new function selector in public ABI. Plan task corrects upstream doc wording (REQUIREMENTS.md DGN-01 + ROADMAP success criteria 1+5 + Phase 271 AUDIT-04 attestation language). | ✓ |
| `external pure` (matches REQ/ROADMAP/AUDIT-04 wording as written) | Adds new selector to library public ABI; forces consumer at L607 into DELEGATECALL (~2K gas/call) with zero behavioral benefit. Plan task rewrites planning-note Solidity body to `external pure`. | |

**User's choice:** `internal pure`.
**Notes:** Decision recorded as D-267-VISIBILITY-01. AUDIT-04 attestation language corrected: drop "ALLOWED-NEW-STATELESS-ENTRY" entirely; AUDIT-04 attests zero new external mutation entries + zero new external pure entries. Same kind of doc-fix-in-Phase-267 chore as the `_countGoldQuadrants` signature reconciliation.

---

## Claude's Discretion

- Per-N dispatch style (chained if/else if vs assembly switch vs jumptable) — planner picks; default chained-if per planning note.
- `_wwxrpFactor` placement (separate helper vs inlined into `_fullTicketPayout`) — planner picks; planning note shows separate helper for clarity.
- NatSpec line-budget per function — planner picks; minimum specified in D-267-COMMENTS-01.
- Naming convention for the new private helper in TraitUtils (`_degTrait` vs `_packDegenQuadrant` vs other) — planner picks; default `_degTrait` per planning note.
- Plan-task ordering interleaving (e.g., REQUIREMENTS.md fix can land in same agent commit as PLAN.md authoring) — planner picks; per-task atomic-commit discipline preserved.

## Deferred Ideas

- `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry) — Next-Milestone Backlog.
- Phase 269 lootbox dead BURNIE-conversion branch deletion (LBX-01..03) — separate phase in v37.0.
- Phase 269 SURF-05 gas-pin re-pinning (GASPIN-01..03) — separate phase in v37.0.
- Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`) — separate phase in v37.0.
- `/economic-analyst` + `/degen-skeptic` Phase 271 adversarial-skill expansion — Phase 271 discuss-phase decision.
- `runrewardjackpots` module-misplacement (stale 2026-04-02 backlog note) — out of v37.0 scope.
- Game-over thorough hardening — out of v37.0 scope; defer to dedicated milestone.
- Single-normalizer alternative design (`derive_constants.py`) — REJECTED; superseded by 5-table design.
