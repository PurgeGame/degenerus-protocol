---
phase: 304-spec-invariant-model-spec
plan: 01
subsystem: sStonk redemption refactor SPEC
tags: [SPEC, INV, sStonk, redemption, v44.0, invariant-model]
requires: []
provides: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07, INV-08, INV-09, INV-10, INV-11, INV-12]
affects: [.planning/phases/304-spec-invariant-model-spec/304-SPEC.md]
tech-stack:
  added: []
  patterns: [per-day-keyed-pool, composite-key-pending-claim, formal-invariant-spec]
key-files:
  created:
    - .planning/phases/304-spec-invariant-model-spec/304-SPEC.md
  modified: []
decisions:
  - "INV-12 forward-references §2 SPEC-04 (a) — Plan 02 locks the gracefully-resolve vs fail-closed semantic"
  - "INV-03 BURNIE-conservation timing follows existing v43 semantics — reservation released at resolve, not at claim"
  - "INV-02 dust bound expressed as 99 wei per resolved day (floor-division remainder of (ethBase * roll) / 100)"
  - "§1 line range fixed for Plan 05 citation-manifest sweep: 58-297"
metrics:
  duration: "~12 min"
  completed: "2026-05-19"
  tasks_completed: 2
  files_created: 1
  files_modified: 0
---

# Phase 304 Plan 01: §0 Header + §1 INV-01..12 Formal Invariant Model — Summary

Authored `304-SPEC.md` skeleton (§0 header + §1..§5 headings + traceability table) and filled §1 with 12 fully-formalized invariant subsections. §1 is the formal-accounting backbone of the v44.0 SPEC; every later phase (305 IMPL, 306 TST, 307 SWEEP, 308 TERMINAL §3.F attestation matrix) consumes §1 as load-bearing input.

## What was built

### Task 1 — 304-SPEC.md skeleton (commit `5a5e1034`)

Created `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` (76 lines) with:

- **§0 Header:** Milestone (v44.0), baseline (`MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2`), load-bearing inputs (FINDINGS-v43.0 §9d HANDOFF-111..117 + RNGLOCK-FIXREC §103 V-184 + REQUIREMENTS.md v44.0), Phase 305 IMPL downstream-consumer note, frozen-at-deploy posture attestation, no-history comment-policy attestation.
- **§0 Requirement-Traceability table:** 35 rows mapping INV-01..12 → §1, SPEC-01..05 → §2, EDGE-01..18 → §3. This is the at-a-glance map a Phase 306 TST author uses to locate the SPEC text for any requirement ID.
- **§1..§5 skeleton:** Five `## §N — <title>` headings with `_To be filled by Plan 0N — see PLAN.md_` placeholders so an inadvertent early read cannot mistake an empty section as finished.

### Task 2 — §1 INV-01..12 formal invariant model (commit `46b16273`)

Filled `## §1 — Invariant Model (INV-01..12)` (replaced the placeholder; §1 now spans lines 58-297, total 240 lines). Each of the 12 INV-NN subsections follows the locked structure:

- `### INV-NN: <short name>`
- `**Formal property:** <math/logical assertion>`
- `**Storage variables involved:** <exact post-refactor slot names>`
- `**State transitions across which the property must hold:** <action-set enumeration>`
- `**Test mapping:** <Foundry test function name in `test/invariant/RedemptionAccounting.t.sol` or dedicated EDGE-NN reproduction in `test/fuzz/RedemptionEdgeCases.t.sol`>`

§1 opens with a preamble defining the **action set** (`burn`, `advanceGame`, `claimRedemption(uint32 day)`, `gameOver-latch`, `transfer`, `approve`, `admin-action`) and the **storage variable set** (post-refactor `pendingByDay[uint32].DayPending`, `pendingRedemptions[address][uint32].PendingRedemption`, `redemptionPeriods[uint32].RedemptionPeriod`, cumulative scalars `pendingRedemptionEthValue` + `pendingRedemptionBurnie`, `MAX_DAILY_REDEMPTION_EV` constant) — both referenced uniformly by every INV-NN entry.

## Forward-references that Plan 02 must resolve at §2

| INV-NN | Forward-references | Resolves when |
|--------|--------------------|---------------|
| INV-12 | §2 SPEC-04 (a) — gameOver path interaction (gracefully-resolve vs fail-closed) | Plan 02 fills §2 |
| INV-08 | §2 SPEC-03 — exact `dayToResolve` derivation (`currentDayView() - 1` or equivalent) | Plan 02 fills §2 |
| INV-09 | §2 SPEC-03 — `dayToResolve` selection under skipped-advance (oldest-first ordering: scan `pendingByDay[D']` or AdvanceModule counter) | Plan 02 fills §2 |
| INV-10 | §2 SPEC-05 — supply-snapshot lazy-init lock (first burn of day, immutable rest of day) | Plan 02 fills §2 |
| INV-07 | §2 SPEC-04 (d) — `delete pendingRedemptions[P][D]` after payout (storage refund lock) | Plan 02 fills §2 |
| INV-10 | §2 SPEC-04 (c) — `delete pendingByDay[D]` at resolve (storage refund lock) | Plan 02 fills §2 |

All forward-references are explicitly labeled in §1 ("per SPEC-XX" / "locked at Plan 02") so Plan 02 has a precise checklist.

## §1 prose that flags potential Phase 305 IMPL clarifications (for SPEC-04 lock at Plan 02)

- **INV-12 (gameOver path interaction):** §1 explicitly enumerates two candidate semantics (gracefully-resolve vs fail-closed) and assigns the decision to SPEC-04 (a). Plan 02 must select exactly one. The Phase 306 invariant_INV_12 test branches on the locked semantic.
- **INV-03 (BURNIE release timing at resolve vs claim):** §1 documents the existing v43 semantics — reservation released at resolve at `:600` analog, payment at claim. Plan 02 should explicitly attest this is preserved (SPEC-04 (b)-adjacent) OR call out a change if needed; Phase 305 IMPL relies on this lock.
- **INV-09 (oldest-first selection mechanism):** §1 documents two implementation candidates (scan `pendingByDay[D']` for smallest unresolved D, vs AdvanceModule pre-computed day counter). Plan 02 / SPEC-03 picks one; Phase 305 IMPL builds against the lock.

## §1 line range (for Plan 05 citation-manifest sweep)

`§1 — Invariant Model (INV-01..12)` occupies **lines 58-297** of `304-SPEC.md`. Plan 05 grep-verifies every contract `:line` cited within this range against `contracts/StakedDegenerusStonk.sol` HEAD per `feedback_verify_call_graph_against_source.md`.

Cited contract surfaces in §1 (Plan 05 must source-verify):
- `:254` — `MAX_DAILY_REDEMPTION_EV = 160 ether` (INV-11)
- `:592` analog — `(ethBase * roll) / 100` floor-division dust source (INV-02)
- `:600` analog — `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` BURNIE-release-at-resolve semantics (INV-03)
- `:763` analog — `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2` 50% supply cap site (INV-10)
- `:800` analog — `claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV` per-(player, day) cap site (INV-11)

The "analog" qualifier is the pre-refactor file:line; Plan 05 verifies each against HEAD AND notes which lines move under the SPEC-01..05 storage shape (post-refactor line numbers belong to the post-Phase-305 IMPL diff, out of SPEC's scope).

## Deviations from Plan

None — plan executed exactly as written. Both task acceptance criteria passed on first verify (Task 1: 6 §[0-5] headings + baseline-cited + comment-policy-attested + posture-attested + 35 traceability rows + 5 placeholders. Task 2: 12 INV-NN subsections + 12 each of the 4 required field labels + INV-02 ETH-conservation equation + INV-10 supply-cap equation + INV-11 EV cap + §1 placeholder removed + zero history words in §1).

## Self-Check: PASSED

- File `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` exists (FOUND)
- Commit `5a5e1034` Task 1 scaffold (FOUND in `git log`)
- Commit `46b16273` Task 2 §1 fill (FOUND in `git log`)
- 6 §[N] section headings (verified)
- 12 INV-NN subsections, each with 4 required labels (verified)
- §1 spans lines 58-297 (verified)
- §2/§3/§4/§5 placeholders intact for Plans 02-05 (verified at lines 300, 304, 308, 312)
- Zero history-narration ("previously" / "formerly" / "used to be" / "changed from") in §1 (verified)
- INV-02 ETH-conservation equation with `address(this).balance` + `claimableWinnings` (verified)
- INV-10 `pendingByDay[D].supplySnapshot / 2` cited (verified)
- INV-11 `MAX_DAILY_REDEMPTION_EV` + `160 ether` cited (verified)
