---
phase: 326-impl-the-one-batched-contract-diff-all-7-items
plan: 01
status: complete
requirements: [PFIX-01]
files_modified:
  - contracts/modules/DegenerusGameLootboxModule.sol
committed: false
---

# 326-01 PFIX — presale closing-box DGNRS over-distribution (F-47-01)

## What changed
`_presaleBoxDgnrsReward` divisor moved **`1_000 * 1 ether` → `400 * 1 ether`** (the only
arithmetic change), i.e. `base = poolStart/100 → poolStart/40`. Per-box DGNRS reward rises
~2.5x so the ~40%-DGNRS branch draws the pool down through the boxes; the closing-box
`transferFromPool` sweep (clamped to live pool balance) now mops up only variance dust.

## Edit map (DegenerusGameLootboxModule.sol)
- `:720` divisor `(1_000 * 1 ether)` → `(400 * 1 ether)`.
- `:716` derivation comment `base = poolStart / 100` → `poolStart / 40`.
- `:718-719` derivation comment `(poolStart/100)` / `(100 * 10 * 1 ether)` → `(poolStart/40)` / `(40 * 10 * 1 ether)`.
- `:300-301` curve-constants comment: `base = poolStart/100` → `poolStart/40`, and the
  arithmetic identity `100*base = poolStart` → `100*base = 2.5*poolStart` with a note that
  the ~40% branch rate drains the pool through the boxes (comment describes what IS).
- `:698` NatSpec `base = poolStart/100` → `poolStart/40`.

## Byte-unchanged (verified)
- `_presaleBoxDgnrsTierTenths` tier ladder `[3.0,2.5,2.0,1.5,1.0]` (`PRESALE_BOX_DGNRS_TIER1..5_TENTHS`) — tier-1 still 3x tier-5 (scale-only move, both legs share the new divisor).
- The closing-box `transferFromPool` sweep block — still clamps to live pool balance (cannot over-draw / returns 0 on empty).

## Verification
- `grep "400 * 1 ether"` = 1; `grep "1_000 * 1 ether"` = 0; no residual `poolStart/100` / `(100 * 10 * 1 ether)`.
- `git diff` hunks only at the comment + reward-fn lines; no hunk in the tier fn or the sweep.
- Compile deferred to the wave-end batched `forge build` (326-08 full-tree build is authoritative).

## Not committed
Batched-diff discipline — committed only after the 326-08 user hand-review.
