---
phase: 279-whole-burnie-floor-bur
plan: 01
subsystem: contracts
tags: [solidity, burnie, lootbox, jackpot, integer-floor, rng-amount, dead-code-removal]

# Dependency graph
requires:
  - phase: 274-lootbox-whole-ticket-rounding
    provides: v39 baseline 6a7455d1 storage layout + the LootboxModule / JackpotModule contract surface that Phase 279 floors
provides:
  - BUR-01 — `_resolveLootboxCommon` floors the post-bonus `burnieAmount` accumulator to a whole-BURNIE multiple
  - BUR-02 — `_awardDailyCoinToTraitWinners` floors `baseAmount` and fully removes the `extra`/`cursor` cursor-rotation machinery
  - BUR-03 — `_awardFarFutureCoinJackpot` floors `perWinner` before the existing `== 0` early-bail
  - BUR-04 — storage-layout byte-identity proof vs v39 baseline 6a7455d1 for both modified modules
  - BUR-05 — theoretical gas worst-case derivation + measured bytecode delta
affects: [279-02 TST-BUR test wave, v40.0 milestone audit baseline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inline `(x / 1 ether) * 1 ether` whole-BURNIE integer-division floor applied once at each RNG-amount-compute site (D-279-INLINE-01) — no shared helper"
    - "Floor ordered BEFORE the existing zero-guard at every site so the existing `!= 0` / `== 0` guards absorb the post-floor-zero case for free"

key-files:
  created:
    - .planning/phases/279-whole-burnie-floor-bur/279-01-STORAGE-LAYOUT-DIFF.md
    - .planning/phases/279-whole-burnie-floor-bur/279-01-GAS-WORSTCASE.md
  modified:
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/modules/DegenerusGameJackpotModule.sol

key-decisions:
  - "BUR-01 burnie-accumulation block reordered to immediately after `_accumulateLootboxRolls` — `_resolveLootboxCommon` is at the Solidity stack-depth ceiling and the floor statement does not compile at the CONTEXT.md-specified position; reorder is within D-279-BUR01-SITE-01 placement discretion"
  - "+114-byte Phase-279-only bytecode delta accepted by explicit user decision — deviates from the plan's BUR-05 NET-NEGATIVE expectation; root cause is the LootboxModule stack-depth-ceiling optimizer stack-spill, the BUR-01 floor is non-negotiable"

patterns-established:
  - "Whole-BURNIE floor at RNG-amount sites: floor the final post-bonus accumulator ONCE, never the per-component values, and place it before the existing zero-guard"

requirements-completed: [BUR-01, BUR-02, BUR-03, BUR-04, BUR-05]

# Metrics
duration: 27min
completed: 2026-05-14
---

# Phase 279 Plan 01: Whole-BURNIE Floor at 3 RNG-Amount Sites Summary

**Inline `(x / 1 ether) * 1 ether` whole-BURNIE floor applied at `_resolveLootboxCommon`'s `burnieAmount`, `_awardDailyCoinToTraitWinners`'s `baseAmount`, and `_awardFarFutureCoinJackpot`'s `perWinner`, plus full removal of the now-dead `extra`/`cursor` cursor-rotation machinery — storage layout proven byte-identical to v39 baseline `6a7455d1`.**

## Performance

- **Duration:** ~27 min
- **Started:** 2026-05-14T08:44:00-05:00
- **Completed:** 2026-05-14T09:11:16-05:00
- **Tasks:** 3
- **Files modified:** 2 contracts + 2 proof artifacts created

## Accomplishments
- BUR-01: `_resolveLootboxCommon` floors the post-bonus `burnieAmount` accumulator in place to a whole-BURNIE multiple before the `if (burnieAmount != 0)` guard; the floored value flows to `coinflip.creditFlip`, the `LootBoxOpened.burnie` event field, and the return tuple.
- BUR-02: `_awardDailyCoinToTraitWinners` floors `baseAmount` via `((coinBudget / cap) / 1 ether) * 1 ether`; the `extra` / `cursor` declarations, both `++cursor`/wrap blocks, and the `amount += 1` cursor-rotation block are fully deleted; `randomWord` and both `++i` increments preserved; NatSpec rewritten to describe the current invariant.
- BUR-03: `_awardFarFutureCoinJackpot` floors `perWinner` via `((farBudget / found) / 1 ether) * 1 ether` before the unchanged `if (perWinner == 0) return` early-bail.
- BUR-04: storage layout proven byte-identical to v39 baseline `6a7455d1` for BOTH `DegenerusGameLootboxModule.sol` and `DegenerusGameJackpotModule.sol` — `forge inspect storage-layout` diff empty, sha256 cross-check identical.
- BUR-05: theoretical gas worst-case derived before benchmarking; measured bytecode delta recorded (+114 bytes vs HEAD, −1,792 vs v39 baseline).
- The OUT-OF-SCOPE ticket-award cursor-rotation near `:1003` (D-279-DISAMBIG-01) was confirmed untouched.

## Task Commits

1. **Task 1: BUR-01 floor the burnieAmount accumulator** — batched into Task 3 commit (per plan: all contract edits land in one user-approved commit)
2. **Task 2: BUR-02 + BUR-03 floor + cursor-rotation dead-var removal** — batched into Task 3 commit
3. **Task 3: storage-layout proof, gas worst-case, batched diff, user-approved commit** — `8ef4a010` (feat)

**Plan metadata / docs:** `docs(279-01)` commit — SUMMARY.md + 2 proof artifacts (separate from the contract commit)

## Files Created/Modified
- `contracts/modules/DegenerusGameLootboxModule.sol` — BUR-01 whole-BURNIE floor on the `_resolveLootboxCommon` `burnieAmount` accumulator; burnie-accumulation block reordered to immediately after `_accumulateLootboxRolls` (stack-depth fix)
- `contracts/modules/DegenerusGameJackpotModule.sol` — BUR-02 `baseAmount` floor + full `extra`/`cursor` dead-var removal in `_awardDailyCoinToTraitWinners`; BUR-03 `perWinner` floor in `_awardFarFutureCoinJackpot`
- `.planning/phases/279-whole-burnie-floor-bur/279-01-STORAGE-LAYOUT-DIFF.md` — BUR-04 storage-layout byte-identity proof vs `6a7455d1`
- `.planning/phases/279-whole-burnie-floor-bur/279-01-GAS-WORSTCASE.md` — BUR-05 worst-case gas derivation + measured bytecode delta

## Decisions Made
- **BUR-01 floor placement → burnie-accumulation reorder.** `_resolveLootboxCommon` is at the Solidity stack-depth ceiling; inserting the floor at the CONTEXT.md-specified position (after the ticket-handling block, before the `if (burnieAmount != 0)` guard) fails to compile with `YulException: Cannot swap … too deep in the stack`. The burnie-accumulation block was moved to sit immediately after `_accumulateLootboxRolls` returns, shortening the live-range of the `burniePresale` / `burnieNoMultiplier` stack locals so the floor statement fits. This is within D-279-BUR01-SITE-01's "Claude's Discretion … exact placement" allowance.
- **+114-byte bytecode delta accepted.** The plan's BUR-05 NET-NEGATIVE expectation did not hold for the Phase-279-only delta. JackpotModule is correctly net-negative (−26 bytes); LootboxModule is +140 bytes and dominates — the optimizer stack-spill consequence of `_resolveLootboxCommon` being at the stack-depth ceiling. Surfaced at the Task 3 checkpoint; user explicitly approved committing as-is.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] BUR-01 burnie-accumulation block reordered to make the floor compile**
- **Found during:** Task 1 (BUR-01 floor the burnieAmount accumulator)
- **Issue:** `_resolveLootboxCommon` is at the Solidity stack-depth ceiling; the BUR-01 floor statement at its CONTEXT.md-specified position fails to compile (`YulException: Cannot swap … too deep in the stack by 1 slots`).
- **Fix:** The `burnieAmount` accumulation block (`burnieAmount = burnieNoMultiplier + burniePresale;` + the presale-bonus `if` + the floor) was relocated to immediately after `_accumulateLootboxRolls` returns, shortening the live-range of the `burniePresale` / `burnieNoMultiplier` stack locals. All 3 downstream consumers (`creditFlip` arg, `LootBoxOpened.burnie` field, return tuple) still read the bare floored `burnieAmount` local. Within D-279-BUR01-SITE-01 placement discretion.
- **Files modified:** contracts/modules/DegenerusGameLootboxModule.sol
- **Verification:** `npx hardhat compile` succeeds; storage layout byte-identical to `6a7455d1` (the reorder relocates only function-body statements, no contract-level state).
- **Committed in:** `8ef4a010` (Task 3 batched contract commit)

### Accepted Deviations (no auto-fix — user decision)

**2. [BUR-05 expectation] +114-byte Phase-279-only bytecode delta — plan expected NET-NEGATIVE**
- **Found during:** Task 3 (gas worst-case derivation + bytecode measurement)
- **Issue:** The plan's BUR-05 success criterion expected the `extra`/`cursor` deletions to outweigh the 3 inline floors → NET-NEGATIVE bytecode. Measured: `DegenerusGameJackpotModule` −26 bytes (as expected), `DegenerusGameLootboxModule` +140 bytes, total **+114 bytes** vs current HEAD.
- **Root cause:** `_resolveLootboxCommon` is at the Solidity stack-depth ceiling. The BUR-01 floor statement forces the Yul optimizer into a less-compact stack schedule (the burnie-accumulation reorder that makes it compile is −96 bytes alone; reorder + floor together is +140). The +140 is the optimizer's stack-spill workaround, not the cost of the `DIV`/`MUL` arithmetic. The BUR-01 floor is non-negotiable.
- **Resolution:** Surfaced at the Task 3 `checkpoint:human-verify`. User explicitly **approved** committing as-is. For context, the delta vs v39 baseline `6a7455d1` (spans Phases 275–279) is −1,792 bytes.
- **Committed in:** `8ef4a010` (recorded in the commit body + `279-01-GAS-WORSTCASE.md`)

---

**Total deviations:** 1 auto-fixed (Rule 3 blocking) + 1 accepted (user-approved bytecode-delta deviation from the BUR-05 NET-NEGATIVE expectation)
**Impact on plan:** The Rule 3 reorder was necessary for the BUR-01 floor to compile and is within the planner's stated placement discretion. The +114-byte delta is an explicitly user-accepted outcome, not scope creep — all 5 BUR requirements are satisfied as specified.

## Issues Encountered
- **Empirical per-invocation gas benchmark — FIXTURE_COVERAGE_GAP_NOTED.** The 3 BUR sites are all `private` with no deterministic full-state harness in the test tree (same gap noted in the Phase 278 GAS artifact). Per `feedback_gas_worst_case.md` + Phase 266/275/276/278 precedent, the analytical worst-case derivation is the load-bearing artifact; the measured bytecode delta provides corroborating empirical evidence of code-size direction. No empirical per-invocation gas numbers were fabricated.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 279-02 (TST-BUR test wave) is ready — it asserts the floor direction + the `mod(amount, 1 ether) == 0` invariant across a representative sweep at all 3 sites.
- Storage-layout byte-identity vs `6a7455d1` is proven, so the v40.0 audit baseline can fold Phase 279 as a function-body-only patch.

---
*Phase: 279-whole-burnie-floor-bur*
*Completed: 2026-05-14*
