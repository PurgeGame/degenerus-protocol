---
phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
plan: 07
subsystem: keeper-router
tags: [solidity, afking, dowork, router, one-category, gas-331-placeholder]

requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "330-06 — internal _autoBuy + the local IGame router surface"
provides:
  - "the parameterless doWork() one-category router (priority autoBuy → advance → autoOpen, structural early-return)"
  - "exactly ONE creditFlip in doWork, CEI-last; the D-07 flat-per-tx reward wired as GAS-331 placeholder constants"
  - "NoWork() when all 3 rngLock-aware predicates are empty; standalone UNREWARDED autoBuy(count)/autoOpen(count) escapes; NO nonReentrant guard"
affects: [330-08, 331, 332, 333]

tech-stack:
  added: []
  patterns:
    - "Parameterless one-category router with a structural early-return so no two categories' bounties stack in one tx"
    - "Unified single CEI-last creditFlip fed by legs that return raw counts/mult and never self-credit"

key-files:
  created: []
  modified:
    - contracts/AfKing.sol

key-decisions:
  - "doWork() is parameterless (ROUTER-01) — each leg uses a fixed internal DOWORK_BATCH default (the maxCount==0 sentinel of the superseded D-06 design is gone)."
  - "DEVIATION (USER-approved): the advance leg reads `uint8 mult = GAME.advanceGame();` and pays `if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;` — `mult == 0` encodes the gameover non-rewardable path (replaces the planned `rewardable` bool)."
  - "D-07 flat-per-tx reward: advance 2×·mult / buy flat 1.5× (NUM/DEN, NOT × count) / open 1× × min(opened, OPEN_KNEE)/OPEN_KNEE — all off `unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp`. The ratios + OPEN_KNEE(=5) are clearly-marked GAS-331 PLACEHOLDERS, calibrated at Phase 331 under a USER gate."
  - "The single creditFlip is skipped at bountyEarned==0 but the category still ran (return, not NoWork). NO nonReentrant guard (ROUTER-07); D-01b TST-02 marker comment present at the creditFlip site."

patterns-established:
  - "Discovery routing: AfKing-local buys-pending predicate (TRUE during rngLock) → advanceDue() → boxesPending() (FALSE during rngLock)"

requirements-completed: [ROUTER-01, ROUTER-02, ROUTER-03, ROUTER-06, ROUTER-10, ADV-01, ADV-02, ADV-03, ADV-05]

duration: part of BATCH-02
completed: 2026-05-27
---

# Phase 330 Plan 07: the parameterless doWork() router — Summary

**The reworked heart of the redesign: a single parameterless `doWork()` that does exactly one category of pending work per call (autoBuy → advance → autoOpen, structural early-return) and pays exactly one flat-per-tx bounty CEI-last — the legs return raw counts/mult and never self-credit.**

## Performance
- **Mode:** applied as part of the single USER-approved BATCH-02 diff (commit `63bc16ca`)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- **doWork() (`:868`, ROUTER-01/02/03/04/06):** parameterless; routes on the rngLock-aware O(1) predicates — buys-pending (`_autoBuyDay != _currentDay() || _autoBuyCursor < _subscribers.length`, true during rngLock) → `advanceDue()` → `boxesPending()` (false during rngLock); each branch ends in a single converged `bountyEarned` + `return` (structural one-category early-return); `revert NoWork()` when all 3 empty.
- **Single creditFlip (`:902`, ROUTER-10/R4):** exactly one `ICoinflip(COINFLIP).creditFlip(msg.sender, bountyEarned)`, CEI-last, skipped at 0.
- **D-07 flat-per-tx reward (GAS-331 placeholders):** `unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp`; advance `unit * ADVANCE_RATIO_NUM * mult` (paid only if `mult > 0`); buy flat `(unit * BUY_RATIO_NUM) / BUY_RATIO_DEN`; open `(unit * min(opened, OPEN_KNEE)) / OPEN_KNEE`. `DOWORK_BATCH`, the ratio constants, and `OPEN_KNEE=5` (`:854`) all marked `// GAS-331 PLACEHOLDER`.
- **Escapes + guard:** standalone UNREWARDED `autoBuy(uint256 count)` (`:908`) and `autoOpen(uint256 count)` (`:914`); NO `nonReentrant` guard; the D-01b TST-02 backstop marker in the doWork docblock.

## Task Commits
Applied + committed as part of the single USER-approved batched diff `63bc16ca`, per [[feedback_batch_contract_approval]].

## Files Created/Modified
- `contracts/AfKing.sol` — `doWork()` router + single creditFlip + D-07 GAS-331 placeholders + unrewarded escapes + `NoWork()`.

## Deviations
- Advance leg consumes single-value `(uint8 mult)` with `mult==0` = unrewarded (see 330-01); plan text referenced the `(mult, rewardable)` tuple.

## Self-Check: PASSED
- `doWork()` parameterless; priority autoBuy→advance→autoOpen with structural early-return; exactly one `creditFlip(msg.sender` in doWork; ≥3 GAS-331 placeholder markers + `OPEN_KNEE`; `NoWork()` decl + revert; both escapes present; 0 `nonReentrant`. Compiles within BATCH-02 (`forge build` exit 0). Deep router proofs (one-rewarded-category, no double-pay, mult-honored) are TST-02/03 at Phase 332.
