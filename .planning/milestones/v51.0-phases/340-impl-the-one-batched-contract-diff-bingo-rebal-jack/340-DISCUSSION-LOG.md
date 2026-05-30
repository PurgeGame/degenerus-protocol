# Phase 340: IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 340-impl-the-one-batched-contract-diff-bingo-rebal-jack
**Areas discussed:** Event indexing topology, Invalid-slot revert behavior, IMPL verification bar

> Note: Phase 340 is an IMPL phase whose design is exhaustively locked by the 339 SPEC (D-01..D-13 + 6 artifacts + the binding edit-order map + the tier-precedence acceptance contract). The three areas below were the ONLY implementation choices the SPEC deliberately left open; everything else was carried forward as locked (no re-asking).

---

## Event indexing topology (the event-only leaderboard)

D-08 makes the bingo leaderboard event-only (no on-chain storage) → the three events ARE the leaderboard. The SPEC locked the event names + param lists but not which params are `indexed`.

| Option | Description | Selected |
|--------|-------------|----------|
| player + level | Index claimer AND level → off-chain "all bingos at level N" queries. (Recommended) | |
| player only | Index just the claimer; matches `JackpotDgnrsWin(address indexed winner, …)` exactly. Minimal/consistent. | ✓ |
| player + level + symbol | Max queryability (3 indexed topics). | |

**User's choice:** player only
**Notes:** Consistent with the dominant codebase convention (`address indexed player/winner`, uint payload non-indexed). Off-chain indexer filters per-level/per-symbol off the non-indexed data fields. → D-340-01.

---

## Invalid-slot revert behavior

When a provided `slots[c]` doesn't resolve to `msg.sender` (wrong slot, or an index past the inner `address[]` length). Fail-closed either way — the question is error clarity for the frontend that builds the slots array.

| Option | Description | Selected |
|--------|-------------|----------|
| Custom error + bounds guard | Explicit length guard + a named custom error so BOTH wrong-owner AND out-of-bounds return one clean error. (Recommended) | ✓ |
| Owner check + native OOB panic | `require(owner==msg.sender)` custom error for wrong owner, but rely on native array-OOB `Panic(0x32)` for bad indices. | |
| You decide | Claude follows the dominant codebase error idiom, keeps it fail-closed. | |

**User's choice:** Custom error + bounds guard
**Notes:** Matches the 452-custom-error-vs-5-require-string codebase idiom; cleanest frontend UX (one failure shape). Exact error identifier left to Claude. → D-340-02.

---

## IMPL verification bar (before the hand-review HARD STOP)

TST is Phase 341, so what proof must the diff pass at 340 before it's HELD at the contract-commit boundary for hand-review?

| Option | Description | Selected |
|--------|-------------|----------|
| Compile + suite non-widening | `forge build` clean + full existing suite NON-WIDENING vs the v50.0 baseline; new tests at 341. (Recommended) | |
| Compile-only | `forge build` green only; defer ALL suite runs to 341. | ✓ |
| + claimBingo smoke test | Compile + non-widening AND one happy-path call at 340. | |

**User's choice:** Compile-only
**Notes:** Lighter than prior-milestone phrasing; intentional — TST-06 (Phase 341) already owns the NON-WIDENING full-suite regression vs `812abeee`, and TST-01..05 own the behavior proofs. 340's gate is "applied + compiles"; no double-work. → D-340-03.

---

## Final check

After the three areas, user selected "Ready for context" (no further gray areas to explore — the rest of 340 is fully SPEC-locked).

## Claude's Discretion

- Interface placement (`IDegenerusGame` + a new `IDegenerusGameBingoModule`) and exact constant/event/error identifiers.
- `currentLevel` / `gameOver` read source inside the module.
- The exact `slots`-validation loop structure (must honor D-340-02).
- (NOT discretionary: CEI ordering — set bits before the external reward calls.)

## Deferred Ideas

- Bingo progress view helper (frontend read-only) — out of v51 scope, deferred follow-up module.
- Internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` — DEFERRED → v52 consolidated audit.
- Cross-level/multi-level bingo, 2nd/3rd-place ladders, commit-reveal anti-MEV, `Pool.Reward` refill automation, Q3 (Dice) naming — explicit non-goals.
- NON-WIDENING regression + per-tier/dedup/empty-pool/jackpot tests — Phase 341 (TST), not 340.

All deferred items were pre-recorded non-goals / downstream phases — no scope creep arose in this discussion.
