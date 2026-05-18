---
phase: 292-hero-override-weighted-roll-hrroll
plan: 02
subsystem: jackpot-payout
tags: [hero-override, weighted-roll, leader-bonus, no-floor, cross-bonus-invariance, rng-bonus-entropy, gas-attestation, public-abi-byte-identity, storage-byte-identity, v42.0]

# Dependency graph
requires:
  - phase: 292-01
    provides: 292-01-DESIGN-INTENT-TRACE.md (HRROLL-10 trace + 7 anchors + HRROLL-05 backward-trace + SWEEP-02(ii) pre-emptive answers) + 292-01-MEASUREMENT.md scaffold (§1 + §3 + §5 FINAL; §2 + §4 + §6 populated post-patch in this plan)
  - phase: v41.0 closure
    provides: MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4 audit baseline + D-288-FIX-SHAPE-01 dailyIdx invariant + D-271-ADVERSARIAL-01..03 carry-forward
provides:
  - HRROLL-01 deletion arm — `_topHeroSymbol(uint32 day)` and its NatSpec entirely removed from DegenerusGameJackpotModule.sol
  - HRROLL-01 addition arm — `_rollHeroSymbol(uint32 day, uint256 entropy)` two-pass weighted roll across 32 packed slots with flat `uint32[32]` cache (D-42N-CACHE-01)
  - HRROLL-02 — ×1.5 leader-weight bonus (`leaderBonus = maxAmount / 2`) applied at the leader's idx in pass 2; strict `>` first-seen tie-break preserved (D-42N-LEADER-BONUS-01)
  - HRROLL-03 — zero eligibility floor; every slot with `amount > 0` participates proportionally (D-42N-FLOOR-01)
  - HRROLL-04 — `_applyHeroOverride` gains `uint256 heroEntropy` 3rd parameter; raw `randWord` plumbed from `_rollWinningTraits` callsite (D-42N-BONUS-ENTROPY-01)
  - HRROLL-06 — storage byte-identity attested via `forge inspect storageLayout` empty diff against v41 close (recorded in 292-01-MEASUREMENT.md §2)
  - HRROLL-07 — public ABI byte-identity attested via `forge inspect methodIdentifiers` empty diff against v41 close (recorded in 292-01-MEASUREMENT.md §4)
  - HRROLL-08 — worst-case gas attestation: theoretical +431 gas vs v41 baseline (~9494 gas) — well under D-42N-GAS-01 soft +500 threshold
affects:
  - 293-tst-hrroll (Phase 293 TST-HRROLL-06 asserts D-42N-GAS-01 empirical regression against the soft +500 / hard +750 threshold from 292-01-MEASUREMENT.md §3)
  - 296-sweep (Phase 296 SWEEP-02(ii) HRROLL adversarial pass tests against the 4 pre-emptive hypotheses in 292-01-DESIGN-INTENT-TRACE.md §SWEEP-02)
  - audit/FINDINGS-v42.0.md §9 (Phase 297 terminal — anchor handoff for D-42N-CACHE-01 + D-42N-GAS-01 + D-42N-BONUS-ENTROPY-01)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-pass weighted-roll with cached uint32[32] flat cache + cumulative cursor sweep (D-42N-CACHE-01 + D-42N-DETERMINISM-01)"
    - "Leader-weight bonus as additive uint64 (`leaderBonus = maxAmount / 2`) applied at idx == leaderIdx (D-42N-LEADER-BONUS-01)"
    - "Orthogonal entropy domains for cross-bonus invariance: color bits read bit-slices of post-tag `r`; symbol roll consumes `keccak256(abi.encode(randWord, day))` (D-42N-COLOR-ENTROPY-01 + D-42N-BONUS-ENTROPY-01)"
    - "Single-site contract callsite verification (B2-degeneration of Phase 290 multi-site pattern)"
    - "USER-APPROVED batched contract commit gate per feedback_no_contract_commits.md + feedback_batch_contract_approval.md + feedback_never_preapprove_contracts.md (orchestrator presents diff, user types 'approved', then ONE commit)"
    - "No dead-guard pattern preserved at function tail per feedback_no_dead_guards.md — implicit `(false, 0, 0)` named-return path replaces the original draft's unreachable revert"

key-files:
  created:
    - .planning/phases/292-hero-override-weighted-roll-hrroll/292-02-SUMMARY.md
  modified:
    - contracts/modules/DegenerusGameJackpotModule.sol (+70 / -23 — locked HRROLL-01..04 patch)
    - .planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md (+84 / -33 — §2 + §4 + §6 populated post-patch; line refs updated for L1941→L1988 callsite shift and 62-line `_rollHeroSymbol` body)

key-decisions:
  - "User-approved removal of the originally-drafted `revert(\"HRROLL: cursor underflow\")` at the loop exit of _rollHeroSymbol — invariant `pick < effectiveTotal == sum(weights) + leaderBonus` guarantees early-return inside the loop; per feedback_no_dead_guards.md the unreachable revert is removed and the implicit `(false, 0, 0)` named-return remains as the safe fall-through, matching the total==0 early-bail shape"
  - "Diff scope strictly bounded to the locked Edits A-F — when an inline forge-fmt run expanded the diff to +228/-62 across 11 unrelated functions, the patch was reset to HEAD and re-applied via Edit tool calls to restore the approved +70/-23 surface"
  - "HRROLL-04 callsite plumbs raw `randWord` (NOT the post-bonus-tag `r`) as the 3rd argument — preserves cross-bonus invariance: bonus + regular _rollWinningTraits invocations within one jackpot resolution land on the SAME (q, symbol) per day; only colors differ"
  - "D-42N-CACHE-01 implementation shipped verbatim per Plan 01 lock: flat `uint32[32] memory weights` indexed by `(q << 3) | s`; uint64-widened `total` + `leaderBonus`; `pick = uint64(uint256(keccak256(abi.encode(entropy, day))) % effectiveTotal)`"
  - "Storage byte-identity (HRROLL-06): forge storageLayout diff against v41 close is EMPTY — Jackpot module declares no storage of its own; INHERITED disposition documented in MEASUREMENT.md §2"
  - "Public ABI byte-identity (HRROLL-07): forge methodIdentifiers diff against v41 close is EMPTY for all 10 public selectors — _applyHeroOverride signature change is a private-function delta and does not count against the public-ABI invariant"

patterns-established:
  - "Pattern: When a forge-fmt or similar formatter expands a locked patch beyond the user-approved scope, reset the file to HEAD and re-apply only the locked hunks via deterministic Edit calls — never commit through the expanded diff. Used here to recover from a continuation agent's pre-commit forge-fmt run."
  - "Pattern: Implicit `(false, 0, 0)` named-return for the (proven-unreachable) loop-exit path replaces a dead-guard revert — matches the existing `total == 0` early-bail shape and saves bytecode."
  - "Pattern: Selector-recalc attestation collected via `forge inspect methodIdentifiers` diff between the patched tree and the milestone audit baseline — recorded as MEASUREMENT.md §4 row table with selector values inline."

requirements-completed:
  - HRROLL-01
  - HRROLL-02
  - HRROLL-03
  - HRROLL-04
  - HRROLL-06
  - HRROLL-07

# Metrics
duration: ~3h (multi-checkpoint: initial executor + user-question on dead-guard + reset-and-replay path)
completed: 2026-05-17
---

# Phase 292 / Plan 02: HRROLL Contract Patch Summary

**Weighted-roll hero-override with ×1.5 leader bonus and no min-wager floor landed as ONE USER-APPROVED batched contract commit; v41 `_topHeroSymbol` deleted; `_rollHeroSymbol` two-pass weighted-roll added; cross-bonus invariance preserved via raw-randWord plumbing.**

## Performance

- **Duration:** ~3 hours (start of Plan 02 dispatch → final commit)
- **Started:** 2026-05-17T14:37Z (first executor dispatch)
- **Completed:** 2026-05-17T17:30Z (USER-APPROVED commit `a0218952` landed)
- **Tasks:** 5/5 complete
- **Files modified:** 2 (1 contract + 1 planning artifact)

## Accomplishments
- Locked HRROLL-01..04 contract patch landed as ONE batched commit (`a0218952`) per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`.
- Storage byte-identity (HRROLL-06) attested via forge `storageLayout` empty diff against the v41 audit baseline.
- Public ABI byte-identity (HRROLL-07) attested via forge `methodIdentifiers` empty diff against the v41 audit baseline; all 10 public selectors recorded inline.
- Single-site callsite verification matrix (MEASUREMENT.md §6) all rows PASS — `_applyHeroOverride` confirmed to have exactly one caller at post-patch L1988.
- Diff scope strictly held to the locked Edits A-F (+70 / -23) — when a forge-fmt run inside a continuation agent expanded the diff to +228/-62 across 11 unrelated functions, the patch was reset to HEAD and re-applied deterministically.
- User-directed removal of the originally-drafted `revert("HRROLL: cursor underflow")` at the (proven-unreachable) loop exit of `_rollHeroSymbol` per `feedback_no_dead_guards.md`; implicit `(false, 0, 0)` named-return remains as the safe fall-through shape, matching the `total == 0` early-bail.

## Task Commits

1. **Task 1: Apply HRROLL Edits A-F to DegenerusGameJackpotModule.sol** — bundled into the single USER-APPROVED batched commit.
2. **Task 2: Populate MEASUREMENT.md §2 (storage-slot grep proof / HRROLL-06)** — bundled.
3. **Task 3: Populate MEASUREMENT.md §4 (selector attestations / HRROLL-07)** — bundled.
4. **Task 4: Populate MEASUREMENT.md §6 (single-site callsite verification)** — bundled.
5. **Task 5: USER-APPROVED batched commit** — `a0218952` `feat(292): HRROLL — weighted-roll hero-override with ×1.5 leader bonus + no floor + cross-bonus invariance [HRROLL-01..04,06,07,08] [USER-APPROVED]`

## Files Created/Modified
- `contracts/modules/DegenerusGameJackpotModule.sol` — HRROLL-01..04 patch (+70 / -23): `_topHeroSymbol` deleted; `_rollHeroSymbol` added with two-pass weighted-roll; `_applyHeroOverride` signature gains `uint256 heroEntropy`; `_rollWinningTraits` callsite at post-patch L1988 reads the 3-arg form with raw `randWord`.
- `.planning/phases/292-hero-override-weighted-roll-hrroll/292-01-MEASUREMENT.md` — §2 + §4 + §6 populated post-patch (+84 / -33); callsite-shift line refs updated (L1941 → L1988, weights cache line L1648 → L1647, body length 74 → 62).

## Deviations from Plan

Two deviations, both surfaced and resolved with explicit user signoff before commit:

1. **forge-fmt scope-expansion (resolved by reset-and-replay).** A continuation executor's pre-commit verification path triggered a forge-fmt run that reformatted 11 unrelated functions (lines wraps in `_pickSoloQuadrant`, `_resumeDailyEth`, `payDailyCoinJackpot`, `emitDailyWinningTraits`, `payDailyCoinBurnie`, `_addClaimableEth`, `_jackpotTicketRollEth`, `_bernoulliTickets`, and the `_rollWinningTraitsAndPickSoloQuadrant` body). The continuation agent correctly refused to commit. The orchestrator reset `contracts/modules/DegenerusGameJackpotModule.sol` to HEAD and re-applied only the locked Edits A-F via deterministic Edit tool calls — the final committed diff is byte-identical to the surface the user reviewed at the checkpoint, minus the unreachable revert (next item).

2. **Removal of unreachable `revert("HRROLL: cursor underflow")` (user-directed).** The original draft of `_rollHeroSymbol` ended with `revert("HRROLL: cursor underflow")` as a defensive marker after the pass-2 cursor loop. The user questioned the dead guard; per `feedback_no_dead_guards.md` + `feedback_frozen_contracts_no_future_proofing.md` the revert was removed and the implicit `(false, 0, 0)` named-return remains as the safe fall-through. Diff stat shrank from the originally-presented +75/-23 to +70/-23 on the contract.

## Self-Check: PASSED

- Contract committed: yes (`a0218952`, `[USER-APPROVED]` trailer present).
- Out-of-scope paths untouched: yes (no `contracts/storage/`, no `contracts/modules/DegenerusGameDegeneretteModule.sol`, no `test/`, no `KNOWN-ISSUES.md` changes in the commit).
- `_topHeroSymbol` post-patch grep: 0 matches.
- `_rollHeroSymbol(uint32 day, uint256 entropy)` post-patch grep: 1 decl at L1639.
- `_applyHeroOverride(traits, r, randWord)` post-patch grep: 1 callsite at L1988.
- `forge build --skip test` exit code: 0.
- `forge inspect storageLayout` diff vs v41 close: EMPTY (HRROLL-06).
- `forge inspect methodIdentifiers` diff vs v41 close: EMPTY for all 10 public selectors (HRROLL-07).
- No `git push` executed (per `feedback_manual_review_before_push.md` — push requires a separate explicit user instruction).
