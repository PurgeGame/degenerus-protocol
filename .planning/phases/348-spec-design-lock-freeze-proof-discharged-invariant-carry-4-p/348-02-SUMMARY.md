---
phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
plan: 02
subsystem: testing
tags: [code-size, eip-170, forge-build-sizes, gas-scavenger, gas-inventory, afking, lootbox, solvency, freeze]

# Dependency graph
requires:
  - phase: 348-01
    provides: "348-GREP-ATTESTATION.md — the re-pinned v55 anchors (claimAffiliateDgnrs :1553, previewSellFarFutureTickets :2113, playerActivityScore :2676; the box-ledger/affiliate sites) the measurement cross-references"
provides:
  - "348-CODE-SIZE-PLAN.md (ARCH-04) — measured DegenerusGame runtime = 24,358 B / headroom = 218 B vs 24,576; per-target reclaim table re-derived; sequenced edit-order with a running-total column proving < 24,576 at every step (reclaim FIRST)"
  - "348-GAS-INVENTORY.md — the /gas-scavenger advisory candidate list (7 SCAV rows, all UNVALIDATED, 350 /gas-skeptic the only gate) + the §6 scorecard levers (GAS-01/02 flagged structural) + the GAS-03 SAFE-WITH-CONDITIONS carve-out"
  - "deferred-items.md — the pre-existing stale AfKing.poolOf test failures (5 files) routed to 351 TST"
affects: [349-impl-the-one-batched-contract-diff, 350-gas-behavior-identical-wins, 351-tst, 352-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Measured (not trusted) code-size budget: forge build --sizes + forge inspect deployedBytecode on the live tree; running-total edit-order arithmetic proving the EIP-170 ceiling is never breached mid-flight (D-348-08)"
    - "gas-scavenger-at-SPEC → gas-skeptic-at-GAS: advisory UNVALIDATED candidate list front-loaded so IMPL builds wins in from the start; the dedicated GAS phase is the only validation gate (D-348-09, mirrors 343 D-02)"

key-files:
  created:
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-CODE-SIZE-PLAN.md"
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/348-GAS-INVENTORY.md"
    - ".planning/phases/348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p/deferred-items.md"
  modified: []

key-decisions:
  - "MEASURED: DegenerusGame runtime = 24,358 B exactly; headroom = 218 B vs the 24,576 EIP-170 ceiling — the v55 PLAN doc's '218B headroom' figure is ACCURATE (not stale) on the live 20ca1f79 tree"
  - "CORRECTED the doc's '~2.8KB realistic clean reclaim' → ~1.4-1.7KB clean (R3 playerActivityScore's 953B requires retargeting 5 cross-contract/delegatecall callers — it is NOT a free deletion); R1 claimAffiliateDgnrs (~1.2-1.35KB, true void → BingoModule) alone covers the ~1-1.5KB stub budget"
  - "Edit-order running-total proven < 24,576 at every step; worst-case (R1 low + stubs high) breaches by 82B with R1-only → 349 MUST also pull R2 + the R3 wrapper (both retarget-free) for a safe ≥158B margin"
  - "GAS-01 (~120k box-buy) + GAS-02 (~3-5k staticcall→SLOAD) are STRUCTURAL to the relocation (they ARE the redesign); GAS-03 (same-slot flush ~0.6-1.2M/50-sub) is the residual 350-validated change"
  - "GAS-03 SAFE-WITH-CONDITIONS recorded verbatim: bucket affiliate payout by roll-winner is SAFE; quests.handlePurchase/handleAffiliate MUST NOT be batched (non-linear completion logic) — pre-marked for 350 rejection if attempted"

patterns-established:
  - "When forge build halts on a stale TEST-file compile error (out of scope), build contracts with --skip 'test/**' --skip '*.t.sol' and log the test failure to deferred-items.md for the owning TST phase — never touch the test files in a paper-only SPEC plan"

requirements-completed: [ARCH-04]

# Metrics
duration: 8min
completed: 2026-05-30
---

# Phase 348 Plan 02: Code-Size + GAS Measurement Producers Summary

**Measured DegenerusGame at 24,358 B / 218 B headroom (doc figure confirmed accurate), authored a running-total reclaim edit-order proving < 24,576 at every step, and front-loaded the /gas-scavenger advisory list with the §6 levers + the GAS-03 no-batch-handleAffiliate carve-out.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-30T17:42:14Z
- **Completed:** 2026-05-30T17:50:19Z
- **Tasks:** 2
- **Files modified:** 3 created (2 declared deliverables + 1 deferred-items log)

## Accomplishments
- **MEASURED the live code-size budget** (D-348-08): `forge build --sizes` + `forge inspect DegenerusGame deployedBytecode` both give exactly **24,358 B runtime** → **218 B headroom** vs the 24,576 EIP-170 ceiling. The doc's most load-bearing figure (218B) is **ACCURATE on `20ca1f79`, not stale** — and genuinely thin (0.9%).
- **Re-derived the per-target reclaim** rather than copying: R1 `claimAffiliateDgnrs` (~1.2-1.35 KB, a clean void → `BingoModule`, 0 external callers) is the big win; R2/R3 are thin Game-proper wrappers over inherited `MintStreakUtils` bodies. **Corrected the doc's "~2.8KB clean reclaim" to ~1.4-1.7KB clean** — R3 `playerActivityScore`'s 953 B is NOT free (it has 5 callers incl. 2 delegatecall modules + 2 cross-contract → a retarget, not a deletion).
- **Authored a sequenced edit-order with a running-total column** proving < 24,576 at EVERY intermediate step (reclaim FIRST → add stubs → lens/drop-`view`), including a worst-case stress scenario (R1-low + stubs-high breaches by 82B → mitigation: pull R2 + R3-wrapper for a ≥158B margin) and a central scenario (R1 alone lands at 24,275, margin 301).
- **Ran the /gas-scavenger lens at SPEC** (D-348-09) over the v55 keeper/funding blast radius → 7 ADVISORY/UNVALIDATED candidates against real `file:line` anchors, all gated on the 350 `/gas-skeptic`.
- **Transcribed the §6 scorecard** with GAS-01 (~120k box-buy) + GAS-02 (~3-5k staticcall→SLOAD) flagged STRUCTURAL-to-the-relocation, and recorded the **GAS-03 SAFE-WITH-CONDITIONS** carve-out verbatim (bucket affiliate by roll-winner SAFE; do NOT batch `quests.handleAffiliate` — non-linear).

## Task Commits

Each task was committed atomically:

1. **Task 1: Measure code-size + author 348-CODE-SIZE-PLAN.md** - `84ec372a` (docs)
2. **Task 2: Run /gas-scavenger + author 348-GAS-INVENTORY.md** - `3ccd4300` (docs)

**Plan metadata:** (this commit) `docs(348-02): complete code-size + gas-inventory measurement plan`

## Files Created/Modified
- `.planning/phases/348-.../348-CODE-SIZE-PLAN.md` - ARCH-04: measured baseline (24,358 / 218), per-target reclaim table (re-derived), sequenced running-total edit-order < 24,576 at every step, 349 hand-off notes
- `.planning/phases/348-.../348-GAS-INVENTORY.md` - /gas-scavenger advisory list (7 SCAV rows), §6 scorecard transcription (GAS-01/02 structural), GAS-03 SAFE-WITH-CONDITIONS carve-out, security-over-gas floor, threat cross-ref
- `.planning/phases/348-.../deferred-items.md` - the pre-existing stale `AfKing.poolOf` test failures (5 files) → 351 TST owner

## Decisions Made
- **218B headroom is exact, not stale** — recorded as an explicit verdict (the doc figure is correct); but the reclaim *total* the doc claims (~2.8KB clean) is overstated and corrected to ~1.4-1.7KB clean / ~2.8KB with-retarget.
- **R1 FIRST is mandatory and re-affirmed by measurement** — moving `claimAffiliateDgnrs` to `BingoModule` (the existing `GAME_BINGO_MODULE` delegatecall lane, mirroring `claimBingo` :328-344, as a true void with no Game stub) must precede the stub additions or the running total spikes through 24,576.
- **A delegatecall stub cannot be `view`** (precedent `DeityBoonViewer.sol`) — so R2/R3 read-aggregators must drop `view` or move to a lens, not become stubs; carried into the 349 hand-off.
- **GAS-03 carve-out is load-bearing** — bucketing affiliate payout by roll-winner is order-independent/same-results, but quest completion is non-linear, so `quests.handlePurchase`/`handleAffiliate` must run per-sub in order; any batching is pre-marked for 350 rejection under `feedback_security_over_gas`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `forge build --sizes` halted on a pre-existing stale-test compile error**
- **Found during:** Task 1 (running `forge build --sizes` to measure the live Game size)
- **Issue:** A bare `forge build --sizes` fails at `test/fuzz/AfKingConcurrency.t.sol:516` — `afKing.poolOf(sub)` references `AfKing.poolOf`, which v54's de-custody (`20ca1f79`) deleted (→ Game-side `afkingFundingOf`, `DegenerusGame.sol:1540`). 5 test files still call the removed `poolOf` — stale because v54.0 was CLOSED-as-superseded with 346 TST dropped, so the suite was never re-synced. This blocked the load-bearing measurement.
- **Fix:** Built the **contracts only** with `forge build --sizes --skip "test/**" --skip "*.t.sol"` (contracts compile with zero errors; the runtime-size table is authoritative). Per the Scope Boundary, this is a pre-existing, unrelated TEST-only failure — NOT fixed here (the plan touches ZERO `test/`). Logged to `deferred-items.md` for 351 TST to re-sync the AfKing suite.
- **Files modified:** none in `contracts/` or `test/`; `deferred-items.md` created to record the discovery.
- **Verification:** `forge inspect DegenerusGame deployedBytecode | wc -c` cross-checks the table (both = 24,358 B); `git diff --name-only -- contracts/` is EMPTY.
- **Committed in:** `84ec372a` (Task 1 commit, alongside the code-size plan)

---

**Total deviations:** 1 auto-fixed (1 blocking — a build-invocation workaround for a pre-existing out-of-scope test failure, NOT a contract/test fix)
**Impact on plan:** The `--skip` workaround was necessary to produce the load-bearing measurement; it did not alter any contract or test file. No scope creep. The stale-test discovery is correctly routed to its owning phase (351), not fixed here.

## Issues Encountered
- The `.planning/` directory is gitignored (`.gitignore:22`), but prior 348-01 commits established that planning artifacts are committed with `git add -f`. Used `git add -f` for the new deliverables; verified `scope.txt` (the pre-existing unrelated working-tree change) was never staged.

## User Setup Required
None - paper-only SPEC measurement; no external service configuration required.

## Next Phase Readiness
- **349 IMPL** has the measured code-size budget + the running-total edit-order it needs to author a code-size-safe diff: reclaim R1 FIRST (true void → BingoModule), then add the ~8 `GameAfkingModule` dispatch stubs, then pull R2 + R3-wrapper (both retarget-free) — the 349 `forge build --sizes` is the FINAL verification, with the reserve set + the R3 caller-retarget as escalation headroom.
- **350 GAS** has the front-loaded /gas-scavenger candidate list (7 rows) + the §6 levers + the GAS-03 SAFE-WITH-CONDITIONS carve-out to validate via `/gas-skeptic` under the security-over-gas floor.
- **351 TST** owns the stale `AfKing.poolOf` test re-sync (deferred-items.md).
- **Concern (carried to 349):** the 218B margin is thin and the clean reclaim is ~1.4-1.7KB (not the doc's 2.8KB) — 349 must land R1 + R2 + R3-wrapper, not assume R1 alone always suffices.

## Self-Check: PASSED
- FOUND: `.planning/phases/348-.../348-CODE-SIZE-PLAN.md`
- FOUND: `.planning/phases/348-.../348-GAS-INVENTORY.md`
- FOUND: commit `84ec372a` (Task 1)
- FOUND: commit `3ccd4300` (Task 2)
- `git diff --name-only -- contracts/` EMPTY (zero contract edits); `scope.txt` untouched.

---
*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p*
*Completed: 2026-05-30*
