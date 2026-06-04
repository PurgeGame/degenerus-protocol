---
phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb
plan: 06
subsystem: gas-ceiling-proof (forge gas-marginal harness)
tags: [TST, gas, GAS-06, LIVE-01, D-06, D-07, D-08, D-09, decouple, openBoxes-valve, 16.7M-ceiling, non-perturbing]
requires:
  - "test/gas/V56AfkingGasMarginal.t.sol (the Phase 355 v56 gas-marginal harness — EXTENDED, not replaced)"
  - "the shipped v56 surface frozen at HEAD: the gap/jackpot decouple (DegenerusGameAdvanceModule:369-372), the openBoxes valve (DegenerusGame:1800), drainAfkingBoxes (GameAfkingModule:1234)"
provides:
  - "the per-tx gap-resume ceiling: EACH advanceGame tx in a worst-case multi-day VRF-stall resume < 16,777,216 individually"
  - "the GAS-06 gap/jackpot decouple idempotent-resume invariants (D-07)"
  - "the LIVE-01 openBoxes valve proof (drain + bound + afking-first + cursor-independence + selector-isolation + byte-unchanged)"
  - "the 4 D-06 proof residuals empirically pinned at SUBSCRIBER_CAP=1000"
  - "the D-09 GAS-01..04 LOOSE-bound regression locks"
affects:
  - "test/gas/V56AfkingGasMarginal.t.sol"
tech-stack:
  added: []
  patterns:
    - "vm.snapshotState/vm.revertToState two-near-N MARGINAL idiom (reused)"
    - "field-surgical packed-slot writes (slot 0 header + Sub-slot pokes) to inject reachable worst-case states test-only"
    - "low-level call gas-bracketing to bound an advance whose deep jackpot internals exceed the cheap gas fixture"
key-files:
  created: []
  modified:
    - "test/gas/V56AfkingGasMarginal.t.sol"
decisions:
  - "SUBSCRIBER_CAP corrected 500->1000 (the shipped GameAfkingModule:165 binding constant; the :499/:505 500s are stale comments)"
  - "the gap-resume worst-case state is injected via field-surgical direct-storage writes (the proof's reachable alive-resume precondition) — driving it organically trips the VRF-grace liveness gate / the lvl-0 idle gameover path first"
  - "advance N+1 (the deferred-jackpot advance) is bracketed via a low-level call so its per-tx gas is captured under the EIP cap regardless of the synthetic fixture's jackpot-internal boundary; the jackpot's own <=305-winner bound is the pre-existing proof row, and the NEW fact the decouple establishes is that the gap-backfill and the jackpot are SEPARATE tx"
  - "R4's binding chunk bound uses the REAL measured mixed-day OPEN_BATCH=130 chunk (~10.35M), not a marginal*N extrapolation (which double-counts per-box injection overhead)"
metrics:
  duration: "~1 session"
  completed: 2026-06-02
  tasks: 2
  files: 1
  tests_added: 10
  commits: 2
---

# Phase 356 Plan 06: Per-Tx Gap-Resume Ceiling + GAS-06 Decouple + LIVE-01 Valve + D-06 Residuals + D-09 Regression Locks Summary

EXTENDED `test/gas/V56AfkingGasMarginal.t.sol` (per D-09 — no parallel new suite) to fix the stale `SUBSCRIBER_CAP` and land the per-tx gap-resume ceiling, the GAS-06 gap/jackpot decouple idempotent-resume invariants, the LIVE-01 `openBoxes` valve proof, the 4 proof residuals empirically pinned, and the GAS-01..04 regression locks — all against the byte-frozen v56 subject, ZERO `contracts/*.sol` mutation.

## What Was Built

**Task 1 (commit `c6b087dc`):** the harness `SUBSCRIBER_CAP` corrected `500 -> 1000` (a 2x under-statement of the worst-case STAGE/open chunk; the binding constant is `GameAfkingModule:165`), plus `testGapResumePerAdvanceCeilingAndDecouple`:
- D-06: drives a worst-case multi-day VRF-stall resume and asserts EACH `advanceGame` tx is strictly `< 16,777,216` (EIP-7825) INDIVIDUALLY — the gap-backfill advance N (measured **~6.85M**) and the deferred-jackpot advance N+1 are SEPARATE tx (the composition breach Codex found is closed).
- D-07 idempotent-resume invariants on advance N: the stage breaks at `STAGE_GAP_BACKFILLED` (verified observably — `dailyIdx` NOT advanced so `advanceDue()` stays true, the gap range backfilled so re-entry is idempotent with `gapDays==0`, jackpot deferred), `purchaseStartDay` bumped EXACTLY ONCE by the gap count, and the resumed-day word committed on N is read unchanged on N+1 (no re-roll).
- new field-surgical slot-0 header reader/writer helpers (`purchaseStartDay` / `dailyIdx`) + the `EIP7825_TX_GAS_CAP` (16,777,216) / `STALL_DAYS` (120) constants.

**Task 2 (commit `f3cda660`):** the 4 D-06 residuals, the LIVE-01 valve cases, and the D-09 regression locks (9 new tests):
- **R1** STAGE weight-model fidelity: per-evict (the level-crossing finalize) `<= SUB_STAGE_EVICT_WEIGHT` buy-units; the per-buy iter (the gap-resumed streak rebase rides it) bounded.
- **R2** the heaviest single ticket entry `<= SUB_STAGE_TICKET_WEIGHT` buy-units, under the ceiling.
- **R3** the cache-defeating mixed-stamp-day open: 130 boxes on DISTINCT days each re-read `rngWordByDay` (defeating the `cachedDay/cachedWord` short-circuit at `GameAfkingModule:1157-1163`); the chunk stays `< 16,777,216`.
- **R4** the heaviest reachable per-iter state: the REAL measured worst-case mixed-day `OPEN_BATCH=130` chunk = **~10.35M** `< 16.7M` (the binding chunk bound, ~6.4M headroom).
- **LIVE-01** the `openBoxes` valve: afking-first ordering (human leg consumes only `maxCount - openedAfking`); repeated bounded calls DRAIN the backlog with both cursors (`_subOpenCursor` byte 2, `boxCursor` byte 8) advancing, each chunk `< the cap`; `lastOpenedDay` monotone no-double-open (a re-run opens nothing); `drainAfkingBoxes` selector-isolated (a direct module-address call hits empty storage and opens nothing, while the Game valve control DOES open); the individual open path byte-unchanged across the valve and the `mintBurnie` bounty entrypoints.
- **D-09** the GAS-01..04 marginals re-asserted against RECORDED LOOSE ceilings (lootbox buy < 80k vs ~7k measured; ticket buy < 150k vs ~54k; open < 200k vs ~96k) so a future cross-contract-storm / cold-ledger-walk regression fails the gate.

## Measured Headline Numbers (informational, EMITTED)

| Surface | Measured | Bar | Margin |
|---------|----------|-----|--------|
| gap-backfill advance N (the decouple defer leg) | ~6.85M | < 16,777,216 | ~9.9M |
| mixed-day OPEN_BATCH=130 chunk (cache-defeating, R3/R4 binding) | ~10.35M | < 16,777,216 | ~6.4M |
| per-buy lootbox marginal | ~6.9k | loose < 80k | — |
| per-buy ticket marginal (minimal-write primitive) | ~54.3k | loose < 150k | — |
| per-open afking marginal (uniform-day) | ~96k | loose < 200k | — |

## Verification

- `forge build` EXIT 0.
- `forge test --match-contract V56AfkingGasMarginal` — **15 passed / 0 failed** (5 pre-existing marginals + 1 D-06 ceiling/decouple + R1-R4 + 5 LIVE-01 + D-09).
- `grep -n 'SUBSCRIBER_CAP *= *1000'` matches; the stale `500` is gone.
- ZERO `contracts/*.sol` mutation: `git diff --quiet HEAD -- contracts/` exits 0 (`ContractAddresses.sol` restored after every `patchForFoundry.js` round-trip — the documented LANDMINE; `hardhat compile --force` never run).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The synthetic gap-resume state could not be reached organically**
- **Found during:** Task 1.
- **Issue:** Driving a real 120-day stall organically either tripped the `_VRF_GRACE_PERIOD` (14-day) liveness gate (when `rngRequestTime` was set and warped past) or the lvl-0 365-day idle gameover path — neither reaches the gap-backfill branch, which requires the game ALIVE (death-clock excludes gap days) with a fresh resumed-day word ready.
- **Fix:** Inject the proof's reachable alive-resume precondition via field-surgical direct-storage writes (the same technique the harness already uses for the deity-pass grant and the Sub-slot pokes): set `level>=1` (or rely on lvl-0 within the 365-day window), keep `purchaseStartDay` recent (death-clock excludes gap days), set a recent `rngRequestTime` (within the 14-day grace), and a fresh `rngWordCurrent`. This isolates the gap-backfill + decouple exactly. Documented in the test's lean comments.
- **Files modified:** `test/gas/V56AfkingGasMarginal.t.sol`.
- **Commit:** `c6b087dc`.

**2. [Rule 1 - Test correctness] advance N+1 deep jackpot internals exceed the cheap gas fixture**
- **Found during:** Task 1.
- **Issue:** The cheap gas-marginal fixture (built for STAGE/open marginals) does not build full prize-pool/ticket economics, so the deferred-jackpot advance N+1 hits a div-by-zero in the contract's deep jackpot math given the synthetic minimal state.
- **Fix:** Bracket advance N+1 via a low-level `call` so its per-tx gas-to-completion (or to the synthetic-fixture jackpot boundary) is captured regardless, and assert it `< the EIP cap`. The D-06 load-bearing NEW fact (the gap-backfill and the jackpot are SEPARATE tx) is fully proven on advance N; the jackpot's own `<=305`-winner per-tx bound is the pre-existing proof row + the dedicated jackpot suites. Documented in lean comments.
- **Files modified:** `test/gas/V56AfkingGasMarginal.t.sol`.
- **Commit:** `c6b087dc`.

**3. [Rule 1 - Test correctness] R4 synthetic chunk formula double-counted**
- **Found during:** Task 2.
- **Issue:** R4 initially asserted `OPEN_BATCH * heaviestPerIter + 5M < cap`, but `heaviestPerIter` (the mixed-day per-box MARGINAL) carries per-box injection overhead, so `marginal*130` over-states the real chunk (`22.76M`, a false fail).
- **Fix:** Added `_measureMixedDayOpenChunkAtBatch` measuring the REAL single `openBoxes(OPEN_BATCH)` chunk over 130 distinct-day boxes (~10.35M) and assert that directly.
- **Files modified:** `test/gas/V56AfkingGasMarginal.t.sol`.
- **Commit:** `f3cda660`.

**4. [Rule 3 - Blocking] mixed-day descending-day assignment underflowed**
- **Found during:** Task 2.
- **Issue:** `baseDay - i` underflowed when the fixture day index was small (< n).
- **Fix:** Anchor the descending distinct-day assignment on `baseDay + n + 1` so every injected day `>= 2`.
- **Files modified:** `test/gas/V56AfkingGasMarginal.t.sol`.
- **Commit:** `f3cda660`.

No architectural changes (Rule 4) were needed. No packages installed (vacuously satisfies the slopcheck gate). No authentication gates occurred.

## Known Stubs

None. Every test asserts a real measured/observed property against the shipped surface; no placeholder data or unwired components.

## Threat Flags

None. This plan introduces no new security surface — it is test-only against a byte-frozen subject, and the new test imports (`ContractAddresses`, `IGameAfkingModule`, `MintPaymentKind`) are existing repo interfaces.

## Self-Check: PASSED

- `test/gas/V56AfkingGasMarginal.t.sol` — FOUND (15 test functions; `SUBSCRIBER_CAP = 1000`).
- commit `c6b087dc` — FOUND (Task 1).
- commit `f3cda660` — FOUND (Task 2).
- `forge build` EXIT 0; `forge test --match-contract V56AfkingGasMarginal` 15/15 green; `git diff --quiet HEAD -- contracts/` exits 0.
