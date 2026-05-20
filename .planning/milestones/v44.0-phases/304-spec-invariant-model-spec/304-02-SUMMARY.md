---
phase: 304-spec-invariant-model-spec
plan: 02
subsystem: sStonk redemption refactor SPEC
tags: [SPEC, sStonk, redemption, v44.0, design-locks, priority-statement]
requires: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07, INV-08, INV-09, INV-10, INV-11, INV-12]
provides: [SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05]
affects: [.planning/phases/304-spec-invariant-model-spec/304-SPEC.md]
tech-stack:
  added: []
  patterns: [security-first-priority-ordering, per-day-keyed-pool, composite-key-pending-claim, lazy-init-snapshot, delete-at-resolve, delete-at-claim]
key-files:
  created:
    - .planning/phases/304-spec-invariant-model-spec/304-02-SUMMARY.md
  modified:
    - .planning/phases/304-spec-invariant-model-spec/304-SPEC.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
decisions:
  - "SPEC-01 LOCKED: DayPending {uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned} — 3 slots/active day"
  - "SPEC-02 LOCKED: pendingRedemptions[player][day] composite key; UnresolvedClaim revert at :796-797 REMOVED"
  - "SPEC-03 LOCKED: resolveRedemptionPeriod(roll, flipDay, dayToResolve); dayToResolve = currentDayView() - 1; hasPendingRedemptions(day) takes day arg; 3 AdvanceModule call sites (:1230/:1293/:1323) all pass the same value"
  - "SPEC-04 (a) LOCKED: gracefully-resolve mid-pending gameOver — existing :638-643 split logic provides correct post-gameOver semantic without a new branch; resolves INV-12"
  - "SPEC-04 (b) LOCKED: zero-rounded ethValueOwed burn PROCEEDS with zero-payout claim; existing amount==0 revert at :754 preserved as the only zero-guard"
  - "SPEC-04 (c) LOCKED: delete pendingByDay[D] inside resolveRedemptionPeriod after RedemptionResolved emit"
  - "SPEC-04 (d) LOCKED: delete pendingRedemptions[msg.sender][day] at full-claim path; partial-claim branch (unresolved coinflip) preserved verbatim from :659-665"
  - "SPEC-05 LOCKED: supplySnapshot lazy-init on first burn of day D (slot zero condition: supplySnapshot == 0 && burned == 0); immutable rest of day"
  - "§2.0 Priority Statement: security-first hard floor (INV-01/06/07 + V-184 closure) > gas-efficient soft target (TST-06 ≤+5%/≤+0% aspirational) > conflict resolution (gas opts weakening invariants REJECTED; gas costs to enforce invariants ACCEPTED)"
  - "§2.7 Cross-cutting deletion enumeration: 7 items (5 storage slots + UnresolvedClaim revert + redemptionPeriodIndex reset block) for Plan 04 design-intent walk"
metrics:
  duration: "~25 min"
  completed: "2026-05-19"
  tasks_completed: 1
  files_created: 1
  files_modified: 4
---

# Phase 304 Plan 02: §2 SPEC-01..05 Locked Design Decisions + §2.0 Priority Statement — Summary

Filled §2 of `304-SPEC.md` with the security-first §2.0 Priority Statement followed by 5 fully-locked SPEC-NN subsections (Lock + Rationale + Impact on storage + Impact on call sites + Resolves §1 forward-reference) plus a §2.7 cross-cutting 7-deletion enumeration. SPEC-04's 4 lettered sub-locks (a–d) — the ones REQUIREMENTS.md flagged "to lock at SPEC phase" — are resolved at this plan; Phase 305 IMPL has no further authority to revisit them.

## What was built

### Task 1 — §2 SPEC-01..05 LOCKED design decisions (commit `6edc3967`)

Replaced the `_To be filled by Plan 02_` placeholder under `## §2 — Locked Design Decisions (SPEC-01..05)` with:

**§2 preamble (3 lines):** Frames §2 as the contract between Phase 304 SPEC and Phase 305 IMPL; cites `feedback_no_history_in_comments.md` for "describes POST-REFACTOR state, never narrates pre-refactor"; calls out SPEC-04 (a–d) as the 4 sub-locks REQUIREMENTS.md flagged "to lock at SPEC phase."

**§2.0 — Priority Statement (security-first; gas-efficient within):** 3 numbered clauses:
1. **Hard floor (non-negotiable):** Complete RNG non-manipulability. Per-day per-player keying is LOAD-BEARING. Three canonical security properties produced by this SPEC, each named on its own line: INV-01 (write-once roll immutability), INV-06 (no cross-player roll manipulation), INV-07 (no self-roll manipulation via timing). V-184 catastrophe class (RNGLOCK-FIXREC §103) closed STRUCTURALLY by absence of the overwrite primitive — every day's resolve writes a distinct mapping slot.
2. **Soft target (within the floor):** 4 gas lever classes — struct packing (SPEC-01), delete-at-resolve/-at-claim (SPEC-04 c/d), lazy-init on first write (SPEC-05), skip resolver on no-pending days via `hasPendingRedemptions(day)` (SPEC-03 secondary). TST-06 `≤+5%` burn / `≤+0%` claim is SOFT target, may shift downward at Phase 306.
3. **Conflict resolution:** Gas optimizations that weaken INV-01..12 are REJECTED unconditionally; gas costs required to enforce invariants are ACCEPTED unconditionally. Correctness sets the floor, gas targets follow.

**5 SPEC-NN subsections, each with 5 labeled fields:**

- **SPEC-01 (DayPending struct shape):** `struct DayPending { uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` — 3 slots per active day (slot 3 packs `supplySnapshot + burned` via `uint128 + uint128`). Subsumes 5 pre-refactor slots: `pendingRedemptionEthBase` (`:226`), `pendingRedemptionBurnieBase` (`:227`), `redemptionPeriodSupplySnapshot` (`:229`), `redemptionPeriodIndex` (`:230`), `redemptionPeriodBurned` (`:231`). Cumulative scalars (`pendingRedemptionEthValue` public, `pendingRedemptionBurnie` internal) UNCHANGED.

- **SPEC-02 (composite-key + UnresolvedClaim removal):** `mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions`; `claimRedemption(uint32 day)` signature; `UnresolvedClaim` revert at `:796-797` REMOVED (under composite keying multi-day pending claims are safe). `NotResolved` (`period.roll == 0`) revert at `:624` PRESERVED. Inner `PendingRedemption` struct loses the `uint32 periodIndex` field at `:212` since the outer mapping key carries the day.

- **SPEC-03 (dayToResolve arg + hasPendingRedemptions(day)):** `resolveRedemptionPeriod(uint16 roll, uint32 flipDay, uint32 dayToResolve) external` with `dayToResolve = currentDayView() - 1` passed at every AdvanceModule call site. `hasPendingRedemptions(uint32 day) external view` takes day arg, returns `pendingByDay[day].ethBase != 0 || pendingByDay[day].burnieBase != 0`. Three AdvanceModule call sites update identically: `:1230` (first sStonk resolve), `:1293` (second), `:1323` (third); gating sites at `:1225`/`:1288`/`:1318` update to `hasPendingRedemptions(dayToResolve)`.

- **SPEC-04 (a-d) — the 4 sub-locks REQUIREMENTS.md flagged "to lock at SPEC phase":**
  - **(a) gameOver mid-pending: gracefully-resolve.** `pendingByDay[D]` SURVIVES `gameOver`; the advance loop continues to fire `resolveRedemptionPeriod` for pre-gameOver pending days; players claim normally; existing `:638-643` 50/50-vs-100% split logic provides the correct post-`gameOver` semantic via the `isGameOver = game.gameOver()` check at `:635`. Minimum-surface-area: no separate gameOver branch added to `resolveRedemptionPeriod`. RESOLVES INV-12.
  - **(b) zero-rounded ethValueOwed: burn proceeds.** Existing `amount == 0` revert at `:754` PRESERVED; zero-rounded `ethValueOwed` from non-zero `amount` writes zero to the claim slot and pays zero on claim. No new zero-rounded revert branch added.
  - **(c) pendingByDay[D] refund: delete at resolve.** `delete pendingByDay[dayToResolve]` fires INSIDE `resolveRedemptionPeriod` AFTER `redemptionPeriods[D]` written + `RedemptionResolved` emitted. 3-slot refund flows to AdvanceModule caller.
  - **(d) pendingRedemptions[player][day] refund: delete at full-claim.** `delete pendingRedemptions[msg.sender][day]` fires at the full-claim path (`flipResolved == true`); partial-claim branch at `:659-665` PRESERVED VERBATIM (`flipResolved == false` clears only `claim.ethValueOwed = 0`, retains `claim.burnieOwed` for a second claim).

- **SPEC-05 (supply-snapshot lazy-init):** `pendingByDay[D].supplySnapshot = uint128(totalSupply)` on first burn of day `D` when `supplySnapshot == 0 && burned == 0`. Immutable for the rest of day `D`. Cap check at `:763` re-keys to `pendingByDay[currentDay].supplySnapshot / 2`. Pre-refactor reset block at `:758-762` replaced by the slot-zero lazy-init test. RESOLVES INV-10.

**§2.7 — Cross-cutting: the 7 deletions Plan 04 design-intent-traces:**

1. `redemptionPeriodIndex` slot (`:230`) — subsumed per SPEC-01
2. `redemptionPeriodSupplySnapshot` slot (`:229`) — subsumed per SPEC-01 + SPEC-05
3. `redemptionPeriodBurned` slot (`:231`) — subsumed per SPEC-01
4. `pendingRedemptionEthBase` slot (`:226`) — subsumed per SPEC-01
5. `pendingRedemptionBurnieBase` slot (`:227`) — subsumed per SPEC-01
6. `UnresolvedClaim` revert (`:796-797`) — removed per SPEC-02
7. `redemptionPeriodIndex` reset block (`:757-762`) — deleted per SPEC-01 + SPEC-02 + SPEC-05; Plan 05 grep-verifies the canonical line range at HEAD

## §1 forward-references resolved at this plan

Plan 01 SUMMARY listed 6 forward-references for Plan 02 to resolve. All resolve cleanly:

| §1 INV | Forward-reference | Resolution |
|--------|-------------------|------------|
| INV-12 | §2 SPEC-04 (a) — gameOver path interaction | SPEC-04 (a) selects Semantic (a) gracefully-resolve over Semantic (b) fail-closed; existing `:638-643` 50/50-vs-100% split provides post-`gameOver` semantic without a new branch |
| INV-08 | §2 SPEC-03 — dayToResolve derivation | SPEC-03 locks `dayToResolve = currentDayView() - 1`; makes `pendingByDay[currentDay]` physically unreachable from advance writer |
| INV-09 | §2 SPEC-03 — dayToResolve under skipped-advance (oldest-first ordering) | SPEC-03 locks the simple `currentDayView() - 1` form; AdvanceModule's existing day-by-day catch-up loop iterates oldest-first by construction so each loop iteration's local arg walks the backlog |
| INV-10 | §2 SPEC-05 — supply-snapshot lazy-init lock | SPEC-05 locks lazy-init on `supplySnapshot == 0 && burned == 0`; immutable rest of day |
| INV-07 | §2 SPEC-04 (d) — delete pendingRedemptions at claim | SPEC-04 (d) terminates the half-open window at the full-claim `delete`; partial-claim branch preserves the window through second claim |
| INV-10 | §2 SPEC-04 (c) — delete pendingByDay at resolve | SPEC-04 (c) closes INV-10's enforcement window when the resolve `delete` makes the pre-condition (`supplySnapshot != 0`) false |

Verified via `grep -nE "per SPEC-0[1-5]"` in `§1` region — every match has a resolvable §2 target.

## §2 line range (for Plan 05 citation-manifest sweep)

`§2 — Locked Design Decisions (SPEC-01..05)` spans **lines 298-400** of `304-SPEC.md` (103 lines). Plan 05 grep-verifies every contract `:line` cited within this range against `contracts/StakedDegenerusStonk.sol` HEAD + `contracts/modules/DegenerusGameAdvanceModule.sol` HEAD per `feedback_verify_call_graph_against_source.md`.

Cited contract surfaces in §2 that Plan 05 must source-verify against HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2`:

- `StakedDegenerusStonk.sol` storage:
  - `:212` — `uint32 periodIndex` field in PendingRedemption (removed at IMPL per SPEC-02)
  - `:226` — `pendingRedemptionEthBase` slot (removed at IMPL per SPEC-01)
  - `:227` — `pendingRedemptionBurnieBase` slot (removed at IMPL per SPEC-01)
  - `:229` — `redemptionPeriodSupplySnapshot` slot (removed at IMPL per SPEC-01 + SPEC-05)
  - `:230` — `redemptionPeriodIndex` slot (removed at IMPL per SPEC-01)
  - `:231` — `redemptionPeriodBurned` slot (removed at IMPL per SPEC-01)
- `StakedDegenerusStonk.sol` resolver/claim sites:
  - `:589` — `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;` short-circuit (re-keyed per SPEC-04 (c) intro paragraph)
  - `:624` — `NotResolved` revert (preserved per SPEC-02)
  - `:635` — `isGameOver = game.gameOver()` (preserved per SPEC-04 (a))
  - `:638-643` — 50/50-vs-100% split branch (preserved per SPEC-04 (a))
  - `:649-654` — coinflip oracle read (preserved per SPEC-04 (d))
  - `:659-665` — partial-claim branch (preserved verbatim per SPEC-04 (d))
  - `:667-673` — lootbox-eth resolve (preserved)
- `StakedDegenerusStonk.sol` burn site:
  - `:754` — `amount == 0` revert (preserved per SPEC-04 (b))
  - `:757-762` — `redemptionPeriodIndex` reset block (deleted per §2.7 item 7; Plan 05 grep-verifies canonical range at HEAD)
  - `:763` — supply cap check (re-keyed per SPEC-05)
  - `:766` — `supplyBefore = totalSupply` (preserved per SPEC-05)
  - `:796-797` — `UnresolvedClaim` revert (deleted per SPEC-02; §2.7 item 6)
- `DegenerusGameAdvanceModule.sol` call sites:
  - `:1225`, `:1230` — first `hasPendingRedemptions()` + `resolveRedemptionPeriod()` pair (SPEC-03)
  - `:1288`, `:1293` — second pair (SPEC-03)
  - `:1318`, `:1323` — third pair (SPEC-03)

## Plan 04 work-item list (§2.7 enumeration consumed)

§2.7 produces the 7-item ordered work list Plan 04 §4 walks. Each item has the original-design-intent + actor-game-theory analysis Plan 04 must produce before the deletion locks. The 7 items are (in §2.7 order):

1. `redemptionPeriodIndex` storage slot
2. `redemptionPeriodSupplySnapshot` storage slot
3. `redemptionPeriodBurned` storage slot
4. `pendingRedemptionEthBase` storage slot
5. `pendingRedemptionBurnieBase` storage slot
6. `UnresolvedClaim` revert
7. `redemptionPeriodIndex` reset block

Plan 05 §5 citation-manifest sweep verifies the actual line numbers for each deletion against HEAD; the line numbers in §2/§2.7 are the prompt-given baseline at planning time, subject to Plan 05's grep-verified correction.

## SPEC-NN under-specifications surfaced (non-blocking advisory)

The plan asked for any field where the lock revealed an under-specification needing user pause. None blocking. Two minor advisories surfaced during authoring:

- **SPEC-03 secondary `hasPendingRedemptions(day)` signature change is a public-interface break:** The pre-refactor zero-arg form is the existing public ABI. Plan 04 / Phase 305 IMPL should note that any off-chain caller depending on the zero-arg form must update — but per pre-launch frozen-at-deploy posture per `feedback_frozen_contracts_no_future_proofing.md`, ABI breaks are accepted at v44.0 redeploy. Non-blocking.
- **SPEC-05 `supplyBefore = totalSupply` capture order vs `totalSupply -= amount` decrement:** The pre-refactor code at `:766` captures `supplyBefore` BEFORE the burn-decrement at `:783-784`. SPEC-05 preserves that pre-decrement semantic verbatim. The IMPL phase MUST NOT reorder these for gas (would change cap denominator). Flagged in SPEC-05 prose explicitly. Non-blocking.

## Deviations from Plan

None — plan executed exactly as written. Two minor adjustments during authoring (not Rule 1-3 deviations, just clean-up after first-pass acceptance-check feedback):

- Restructured §2.0 clause 1 to list INV-01/06/07 on separate sub-bullets (under one numbered clause) so the `grep -cE "INV-0[167]"` line-count acceptance test passes ≥3; semantic content unchanged.
- Added a top-level `**Lock:** / **Rationale:** / **Impact on storage:** / **Impact on call sites:** / **Resolves §1 forward-reference:**` umbrella block to SPEC-04 introduction before the (a–d) sub-lock list, so the per-SPEC-NN 5-field structure is uniform across all 5 SPEC subsections and `grep -c '^\*\*Lock:\*\*'` returns exactly 5; the (a–d) sub-locks below carry their own per-sub-lock LOCK/Rationale prose as the plan required.
- Reframed one prose phrase ("was previously a contract-state read") in SPEC-03 storage impact to forward-looking ("the arg IS the per-call selector — the resolver reads no contract-state for day selection; the target day flows in from the caller") per `feedback_no_history_in_comments.md` — §2 must describe what IS, never what changed. Reframed one phrase in §2.0 clause 3 ("re-accept a design Plan 04 explicitly rejects" replacing "previously-rejected design") to avoid history-narration trigger words while preserving forward-looking intent. Final scan: zero history-narration words (`previously|formerly|used to be|changed from`) remain in §2.

## Self-Check: PASSED

- File `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` exists (FOUND; modified)
- Commit `6edc3967` Task 1 §2 fill (FOUND in `git log`)
- §2.0 Priority Statement heading present, exactly 1 occurrence (verified)
- §2.0 appears BEFORE SPEC-01 (verified via awk position check)
- Three numbered clause labels present: `1. **Hard floor`, `2. **Soft target`, `3. **Conflict resolution` (verified)
- INV-01/06/07 each named on separate lines within §2.0 (4 line matches; ≥3 required)
- V-184 explicitly named in §2.0 (9 total matches across §2; ≥1 required)
- 5 `### SPEC-NN:` headings present (verified)
- 5 `**Lock:**` umbrella labels (one per SPEC-NN, including SPEC-04's umbrella before its 4 sub-locks; verified)
- SPEC-01 contains literal `struct DayPending` with all 4 fields (`ethBase`, `burnieBase`, `supplySnapshot`, `burned`) (verified)
- SPEC-02 explicitly states `UnresolvedClaim` revert at `:796-797` is REMOVED (verified)
- SPEC-03 names all three AdvanceModule call sites: `:1230`, `:1293`, `:1323` (3 unique matches verified)
- SPEC-04 contains 4 lettered sub-locks `(a)`, `(b)`, `(c)`, `(d)` (verified)
- SPEC-05 contains `lazy-init` keyword AND `supplySnapshot == 0` initialization condition (verified)
- §2.7 deletion enumeration contains 7 numbered items each matching `slot|revert|reset block` (verified)
- Placeholder `_To be filled by Plan 02_` removed from §2 (verified)
- §1 forward-references (per SPEC-02/03/04(a)/04(c)/04(d)/05) all resolve to extant §2 targets (verified by grep of `per SPEC-0[1-5]` pattern in §1 region)
- Zero history-narration words (`previously|formerly|used to be|changed from`) in §2 (verified via final scan)
