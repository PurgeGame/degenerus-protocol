# Phase 267: Degenerette Producer + 5-Table Payout Rewrite - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `267-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-10
**Phase:** 267-degenerette-producer-5-table-payout-rewrite
**Areas discussed:** `_countGoldQuadrants` signature reconciliation, plan decomposition shape, constant-verification policy, comment-rewrite granularity, `packedTraitsDegenerette` visibility (self-check follow-up), ETH payout 3-tier split rule (mid-discussion scope expansion)

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

## ETH payout 3-tier split rule (mid-discussion scope expansion)

User-initiated scope addition after the original 5 areas closed. User requested: "payouts of ≤ 3× bet to be all eth and larger than that to be 75% lootbox 25% eth". Pre-discovery surface scan found existing `_distributePayout` at `DegenerusGameDegeneretteModule.sol:678-734` already does unconditional 25% ETH / 75% lootbox split (with a 10%-pool-cap secondary protection for ETH-portion solvency). User's request was therefore narrower than first read: add a small-payout passthrough — skip the 25/75 split when `payout ≤ 3 × bet`, pay 100% ETH instead.

### Q1: Threshold semantics — what happens at exactly 3× bet?

| Option | Description | Selected |
|--------|-------------|----------|
| `payout <= 3 * bet` inclusive (3.0× pays all ETH) | Verbatim user wording. Discontinuity at 3.0× → 3.01× boundary (3.0× pays 100% ETH = 3× bet; 3.01× pays 0.7525× bet under naive 25%). Document discontinuity as accepted. | |
| `payout < 3 * bet` strict (3.0× itself splits) | Cleaner "strictly under 3×" framing; same discontinuity issue, just shifted. | |
| Smooth transition (linear ramp 2-4× bet) | Avoids discontinuity; ~20 extra LOC + new constant. | |
| **User-typed (Other)**: "can we do a min payment of 2.5x on the lootbox path (with the rest lootbox if 2.5x is more than 25%)" | Min-2.5× ETH guarantee on the lootbox path (`payout > 3 * bet`). Resolved via `ethShare = max(2.5 * bet, payout / 4)`. Eliminates the boundary discontinuity (3.0× → 2.5× drop at 3.01× instead of 3.0× → 0.7525× drop). Three-band rule: ≤3× → all ETH; 3-10× → 2.5× bet ETH floor + remainder lootbox; >10× → existing 25/75 split. | ✓ |

**User's choice:** User-typed min-2.5× ETH guarantee on lootbox path.
**Notes:** Decisions recorded as D-267-PAYSPLIT-01 (≤3× all-ETH) + D-267-PAYSPLIT-02 (3-10× 2.5× floor + ≥10× 25% standard). Boundary discontinuity at exactly 3.0× bet (3.0× → 2.5× ETH drop at 3.01×) accepted as documented design.

### Q2: Pool-cap interaction — does the 10% pool cap (`ETH_WIN_CAP_BPS`) still apply to the all-ETH small-payout path?

| Option | Description | Selected |
|--------|-------------|----------|
| Pool cap still applies; cap takes precedence | If 3× bet payout > 10% of futurePool, excess flips to lootbox per existing logic. Smallest-diff path; preserves solvency invariant. | ✓ |
| Skip pool cap for ≤3× payouts (strict 'always all ETH') | Honors all-ETH semantics strictly but introduces unbounded ETH drain risk in thin pools. Would need separate per-bet hard cap. | |
| Apply 10% pool cap only to amounts above 3× bet (marginal) | Three branches; messiest call-graph; highest §3.A delta-surface row count. | |

**User's choice:** Pool cap still applies; cap takes precedence.
**Notes:** Decision recorded as D-267-PAYSPLIT-03. NatSpec on `_distributePayout` documents "pool cap takes precedence over small-payout passthrough and 2.5× floor".

### Q3: Scope of the new rule — which currencies / paths does the threshold apply to?

| Option | Description | Selected |
|--------|-------------|----------|
| ETH-currency Degenerette quickPlay only | Matches "Degenerette payouts for eth" wording. CURRENCY_BURNIE + CURRENCY_WWXRP UNCHANGED. JackpotModule UNTOUCHED. | ✓ |
| ETH-currency Degenerette + jackpot ETH distribution | Larger blast radius; breaks Phase 268 SURF-02 byte-identity claim for JackpotModule; conflicts with v34 D-262 closure-signal carry. | |

**User's choice:** ETH-currency Degenerette quickPlay only.
**Notes:** Decision recorded as D-267-PAYSPLIT-04. `_distributePayout` `CURRENCY_ETH` branch is the sole mutation site; `CURRENCY_BURNIE` (line 735-736) + `CURRENCY_WWXRP` (line 737-739) UNCHANGED.

### Apply scope check

User confirmed "Apply all updates now" — REQUIREMENTS.md (PAY-SPLIT-01..03 + STAT-07 + AUDIT-02 surface (h) + Coverage 47→51 + Traceability), ROADMAP.md (Phase 267 inline goal + success criterion 6 + Phase 268 STAT-07 + Phase 271 AUDIT-02 surface (h)), 267-CONTEXT.md (D-267-PAYSPLIT-01..05 + phase boundary + plan task wording), all updated in single agent-commit per D-267-APPROVAL-01 carry.

### Implementation impact summary

- `_distributePayout` signature gains a 5th argument: `uint128 betAmount` (threaded from `amountPerTicket` at L656 call site).
- `_distributePayout` ETH branch body rewritten with 3-tier split rule.
- ~15-20 LOC net addition; surrounding non-ETH branches and frozen-pool branch UNCHANGED at body-level.
- 3 new requirements: PAY-SPLIT-01 + PAY-SPLIT-02 + PAY-SPLIT-03.
- 1 new ROADMAP success criterion: criterion 6.
- 1 new STAT requirement (Phase 268): STAT-07.
- 1 new AUDIT-02 surface (Phase 271): (h) ETH split rule monotonicity + boundary-gaming.
- v37.0 milestone requirement count: 47 → 51 (+4: PAY-SPLIT-01..03 + STAT-07; AUDIT-02 surface (h) is an existing-req-extension not a new req).

---

## Claude's Discretion

- Per-N dispatch style (chained if/else if vs assembly switch vs jumptable) — planner picks; default chained-if per planning note.
- `_wwxrpFactor` placement (separate helper vs inlined into `_fullTicketPayout`) — planner picks; planning note shows separate helper for clarity.
- NatSpec line-budget per function — planner picks; minimum specified in D-267-COMMENTS-01.
- Naming convention for the new private helper in TraitUtils (`_degTrait` vs `_packDegenQuadrant` vs other) — planner picks; default `_degTrait` per planning note.
- Plan-task ordering interleaving (e.g., REQUIREMENTS.md fix can land in same agent commit as PLAN.md authoring) — planner picks; per-task atomic-commit discipline preserved.
- `_distributePayout` PAY-SPLIT exact Solidity form (e.g., `(2 * bet + bet/2)` vs `(5 * bet) / 2` vs named constant `MIN_LOOTBOX_ETH_FLOOR_NUMERATOR=5/2`) — planner picks; D-267-PAYSPLIT-02 specifies the math, not the syntax. Inline literals 3 and 2.5 (as `3`, `5/2`, etc.) are kept inline; planner may promote to named constants if NatSpec readability demands.
- `betAmount` argument-ordering insertion in `_distributePayout` signature — planner picks; D-267-PAYSPLIT-05 default is between `currency` and `payout` (currency-bet-payout adjacency).

## Deferred Ideas

- `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry) — Next-Milestone Backlog.
- Phase 269 lootbox dead BURNIE-conversion branch deletion (LBX-01..03) — separate phase in v37.0.
- Phase 269 SURF-05 gas-pin re-pinning (GASPIN-01..03) — separate phase in v37.0.
- Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`) — separate phase in v37.0.
- `/economic-analyst` + `/degen-skeptic` Phase 271 adversarial-skill expansion — Phase 271 discuss-phase decision.
- `runrewardjackpots` module-misplacement (stale 2026-04-02 backlog note) — out of v37.0 scope.
- Game-over thorough hardening — out of v37.0 scope; defer to dedicated milestone.
- Single-normalizer alternative design (`derive_constants.py`) — REJECTED; superseded by 5-table design.
