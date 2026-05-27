---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: 02
subsystem: testing
tags: [gas, GAS-05, GAS-06, keeper-router, doWork, degeneretteResolve, faucet, round-trip, WR-01, CR-01, foundry, fuzz, flip-credit-illiquidity]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the committed flat-per-tx keeper-router 63bc16ca (AfKing.doWork() buy/open bounty + DegenerusGame.degeneretteResolve flat RESOLVE_FLAT_BURNIE >=3 gate) — the subject these guards prove faucet-safe"
  - phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
    provides: "D-04 GAS-05 round-trip floor + D-05c real-gas anti-exploit basis (flip-credit <= mintPrice/1000 ETH; >=220k for the >=3 min vs 5-50+ gwei)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca (331-01)
    provides: "the measured per-category marginals + the RouterWorstCaseGas.t.sol fixture idiom (healthy-buying-sub setup, slot consts, day-offset helper) these guards reuse"
provides:
  - "test/fuzz/CrankFaucetResistance.t.sol — 10 new GAS-05/GAS-06 flat-per-tx round-trip guards (router open small-batch corner + buy leg + degeneretteResolve flat reward + the >=3/1-2-unpaid/0-reverts/WWXRP-excluded gate behaviors)"
  - "the SAFE-01 hard-floor proof that no positive-EV self-crank loop exists under the v49 flat-per-tx model, judged against REAL prevailing gas (1..2000 gwei) + flip-credit illiquidity"
affects: [331-04-peg-calibration, 331-05-contract-gate, 332-TST, 333-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WR-01 round-trip guard for the flat-per-tx router: reward computed/observed from the LIVE break-even unit (afKing.BOUNTY_ETH_TARGET()/mintPrice), valued at the 0.5-gwei peg, asserted < real measured gas at 1..2000 gwei"
    - "observe-the-reward-via-credit-delta (NOT hardcode): read coinflip.coinflipAmount delta for the actual bounty the contract pays, so the guard holds for whatever 331-04 lands"
    - "guard-the-guard mirror check: bind the mirrored BUY_RATIO to the live observed doWork buy delta so a contract ratio drift trips RED rather than silently mis-pricing"
    - "front-load all degenerette placements before the RNG word lands (placeDegeneretteBet binds to the active index and reverts RngNotReady once a word is set)"

key-files:
  created:
    - ".planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/deferred-items.md"
  modified:
    - "test/fuzz/CrankFaucetResistance.t.sol"

key-decisions:
  - "Open-leg gas measured via the unrewarded afKing.autoOpen(k) passthrough (whose body IS doWork's open box-opening work) + the open reward computed from the LIVE unit — avoids the rngLock routing fragility of forcing doWork() to the open leg while still proving round-trip <= 0 vs real gas"
  - "Buy-leg reward OBSERVED directly off the doWork() credit delta (buy is top-priority on a fresh day with healthy subs) — proves the live buy ratio end to end; a dedicated mirror test binds BUY_RATIO to that live delta"
  - "Exploitability judged against REAL prevailing gas 1..2000 gwei + flip-credit illiquidity, NOT the 0.5-gwei AUTO_GAS_PRICE_REF peg (feedback_bounty_exploit_uses_real_gas_not_peg_ref)"
  - "RESOLVE_FLAT_BURNIE effect read via the keeper credit delta (NOT hardcoded 1e18); credit-at-peg asserted <= mintPrice/1000 ETH (the D-05c illiquid-credit ceiling) AND < real >=3-resolution gas"

patterns-established:
  - "flat-per-tx router faucet guard: one round-trip test per leg + a fuzzed-gas variant, reward from live unit, cost from real measured gas"
  - "degeneretteResolve gate-behavior coverage: >=3 paid-once / 1-2 committed-unpaid / 0 reverts NoWork / WWXRP resolved-but-uncounted"

requirements-completed: [GAS-05, GAS-06]

# Metrics
duration: ~45min
completed: 2026-05-27
---

# Phase 331 Plan 02: Flat-Per-Tx Router + degeneretteResolve Round-Trip Faucet Guards Summary

**10 new WR-01-style round-trip guards in `CrankFaucetResistance.t.sol` proving no positive-EV self-crank loop exists under the v49 flat-per-tx keeper-router — the doWork() open small-batch hot corner (`unit*min(k,OPEN_KNEE)/OPEN_KNEE`) and flat 1.5x buy leg, plus the degeneretteResolve flat ~1-BURNIE reward (>=3 non-WWXRP gate) — all judged against REAL prevailing gas (1..2000 gwei) + flip-credit illiquidity, with the reward read LIVE so the guards hold for whatever 331-04 calibrates.**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-05-27 (after 331-01 complete)
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 1 test file (zero `contracts/*.sol`); 1 deferred-items doc created

## Accomplishments
- **GAS-05 (Task 1):** added the flat-per-tx router round-trip guards — `testRouterOpenSelfCrankRoundTripNonPositive` (k in {1,2,3,4,5,12}, spanning the below-knee pro-rated small-batch corner the `OPEN_KNEE` pro-rate exists to close) + its fuzzed variant (k 1..2*KNEE, 1..2000 gwei), `testRouterBuySelfCrankRoundTripNonPositive` (flat 1.5x buy reward observed off the doWork credit delta) + its fuzzed variant, and `testRouterBuyRewardMatchesLiveUnitRatio` (binds the mirrored buy ratio to the live unit so a contract drift trips RED).
- **GAS-06 (Task 2):** added the `degeneretteResolve` flat-reward guard — `testDegeneretteResolveFlatRewardRoundTripNonPositive` (3 non-WWXRP resolutions earn the flat credit once, valued at peg <= `mintPrice/1000` ETH, below real >=3-resolution gas at 1/20 gwei) + its fuzzed-gas variant, plus the gate-behavior coverage: `testDegeneretteResolveBelowGateUnpaid` (1 and 2 resolutions COMMIT but pay 0), `testDegeneretteResolveZeroReverts` (0 resolved → `NoWork()`), `testDegeneretteResolveWwxrpExcludedFromGate` (3 WWXRP resolve unpaid; 3 non-WWXRP then meet the gate, paid once).
- All 10 new guards PASS (the 4 fuzz variants at 1000 runs each); the 3 originally-passing tests in the file stay green; the 9 pre-existing v48-model failures (deferred to Phase 332 TST) are unchanged — no regression introduced.

## Task Commits

Each task was committed atomically:

1. **Task 1: router open-leg + buy-leg round-trip guards (the flat-per-tx hot corner)** — `921599c2` (test)
2. **Task 2: degeneretteResolve flat ~1-BURNIE round-trip guard + gate behaviors** — `480fa54f` (test)

_Note: both tasks are `tdd="true"`; the new round-trip-guard assertions ARE the test (a faucet-floor proof harness, the 319 WR-01 idiom), so each is a single `test(...)` commit rather than a RED/GREEN split — the contract under test already exists at `63bc16ca`._

## Files Created/Modified
- `test/fuzz/CrankFaucetResistance.t.sol` — +10 tests +helpers: the v49 flat-per-tx router reward mirror (BUY_RATIO/OPEN_KNEE + AfKing slot consts), `_liveUnit`/`_openLegRewardEthAtPeg`/`_queueKBoxesAtActiveIndex`/`_setupHealthyBuyingSubs`/`_placeNLosingBets`/`_today`/`_lastAutoBoughtDayOf`, and the two new test sections (Task 1 router + Task 2 resolve).
- `.planning/phases/331-.../deferred-items.md` — logs the 9 pre-existing v48-model failures as DEFERRED-to-332 (out of 331-02 scope).

## Decisions Made
- **Open-leg via the unrewarded `autoOpen(k)` passthrough + computed reward, not forced doWork() routing.** Forcing `doWork()` to the open leg requires clearing the buy + advance predicates; the fresh fixture has `advanceDue()==TRUE`, and driving the advance enters `rngLock` (which structurally blocks the open leg, RD-3). The `autoOpen(k)` body performs the IDENTICAL box-opening work the doWork open leg does, so measuring its real gas + computing the reward doWork would pay (from the live unit) proves the same round-trip floor without the rngLock fragility. The buy leg, by contrast, IS cleanly observable via `doWork()` (top priority on a fresh day) — so the buy reward is read directly off the credit delta and a mirror test binds the ratio.
- **Reward read LIVE, never hardcoded.** `unit = afKing.BOUNTY_ETH_TARGET() * PRICE_COIN_UNIT / mintPrice` is read off the deployed immutable; the resolve credit is read off the keeper's `coinflipAmount` delta. So the guards stay correct for whatever 331-04 lands (BOUNTY_ETH_TARGET is a deploy-param; RESOLVE_FLAT_BURNIE may be re-pegged). The only mirrored literals are `BUY_RATIO_NUM/DEN` and `OPEN_KNEE` (AfKing `internal constant`s with no getter) — flagged as test-mirror-sync and cross-validated against the live buy delta.
- **Exploitability lens = REAL gas + illiquidity, not the peg ref** (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`): every guard asserts reward-at-peg < `gasUsed * realPrice` for realPrice in [1 gwei, 2000 gwei], and the resolve guard additionally asserts credit-at-peg <= `mintPrice/1000` (the D-05c illiquid-credit ceiling) + that the credit never lands as liquid BURNIE.

## Deviations from Plan

None — both tasks executed as written. Two in-line reconciliations (not behavior deviations):

- **PLAN `<action>` said "drives `doWork()` opens".** The committed `63bc16ca` router enters `rngLock` after the new-day advance, and the open leg is FALSE during rngLock (RD-3) — so forcing `doWork()` to the open leg on the fresh fixture is not reliably reachable. Resolved per the plan's own "do not hardcode — read the live values" intent: measure the real open work via the gas-identical unrewarded `autoOpen(k)` passthrough and compute the doWork open reward from the live `unit`. The buy leg IS observed via `doWork()` directly (a stronger, end-to-end observation), and the mirror test binds the ratio. The round-trip floor proved is identical.
- **`placeDegeneretteBet` index-binding.** It binds a bet to the active lootbox index and reverts `RngNotReady` once that index's word is set, so all placements in the gate-behavior tests are front-loaded BEFORE the single word injection (caught during Task 2 — two tests initially failed `RngNotReady` and were fixed by reordering placement-then-inject).

## Issues Encountered
- Task 2 `testDegeneretteResolveBelowGateUnpaid` + `testDegeneretteResolveWwxrpExcludedFromGate` first failed with `RngNotReady()` because they placed a second batch of bets AFTER injecting the RNG word (the index had advanced / the word was already set). Fixed by placing ALL bets up front, injecting once, then resolving in sub-batches. Re-ran: 5/5 Task-2 tests green.

## Scope-Boundary Note (pre-existing failures — NOT this plan's work)
- The file `test/fuzz/CrankFaucetResistance.t.sol` carries **9 pre-existing FAILING tests** that assert the SUPERSEDED v48 per-item gas-units reward model (`CRANK_RESOLVE_BET_GAS_UNITS`, the unrewarded `autoOpen`, single-bet `degeneretteResolve` reward). They fail against the committed 330 redesign `63bc16ca` and are part of the documented 58-failure baseline (STATE.md: "v48.0 baseline + 16 reward-rehoming tests INTENTIONALLY deferred to Phase 332 TST"). They are OUT OF 331-02 SCOPE (the reward-rehoming proof is Phase 332 TST-01..04) and were NOT modified. Logged in `deferred-items.md`. Consequently `forge test --match-path test/fuzz/CrankFaucetResistance.t.sol` exits non-zero on the WHOLE file due to these pre-existing items; the **10 new 331-02 guards all pass** (verified via `--match-test "Router|Degenerette"`).

## User Setup Required
None — test + doc only; no `contracts/*.sol` touched and no constant landed (that is 331-04/05 under the second USER-approved gate).

## Next Phase Readiness
- GAS-05 + GAS-06 anti-exploit basis is proven against the COMMITTED model and is parameterized on the live contract, so the guards stay GREEN after 331-04 lands the calibrated `BOUNTY_ETH_TARGET`/ratios/`RESOLVE_FLAT_BURNIE`. If 331-04 changes `BUY_RATIO_NUM/DEN` or `OPEN_KNEE` in `AfKing.sol`, re-sync the mirrored constants in this file (`testRouterBuyRewardMatchesLiveUnitRatio` will trip RED on a buy-ratio drift).
- **Contract-boundary HARD STOP reminder:** 331-04 lands `AfKing.sol`/`DegenerusGame.sol` constants; 331-05 is the `autonomous:false` USER-approval gate — NOT this plan, not touched here. `contracts/` is clean on disk.
- Phase 332 TST owns rewriting the 9 deferred v48-model assertions to the v49 flat-per-tx model (TST-01..04) — this plan already covers the v49 model's faucet floor end to end.
- No blockers.

## Self-Check: PASSED

- `test/fuzz/CrankFaucetResistance.t.sol` (modified) — FOUND
- `.planning/phases/331-.../deferred-items.md` — FOUND
- Commit `921599c2` (Task 1) — FOUND
- Commit `480fa54f` (Task 2) — FOUND
- `forge test --match-path test/fuzz/CrankFaucetResistance.t.sol --match-test "Router|Degenerette"` — 10/10 PASS
- `git diff --name-only -- contracts/` for this plan — EMPTY (no contract mutation)

---
*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca*
*Completed: 2026-05-27*
