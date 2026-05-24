---
phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas
plan: 04
subsystem: testing
tags: [foundry, gas, security-floor-audit, gas-scavenger, gas-skeptic, contract-auditor, crank, afking-sweep, source-presence-grep, comment-stripping]

# Dependency graph
requires:
  - phase: 319-01
    provides: "319-GAS-DERIVATION.md (the GAS-01 worst-case-first paper derivation that fixes the cost-center file:line chain for each work-type + the G1-G13 source map this plan asserts/audits)"
  - phase: 318
    provides: "the 318-02/03/04/05 proving suites (SAFE-01..04) that establish each G1-G13 guard, plus the CrankFaucetResistance creditFlip-count + CrankNonBrick box-enqueue + JackpotSingleCallCorrectness comment-stripping idioms reused here"
provides:
  - "test/gas/CrankLeversAndPacking.t.sol — the GAS-02/03/04 lever + packing assertion suite (7 tests) + the G1-G13 guard byte-presence pins"
  - "319-GAS-05-GUARDRAILS.md — the GAS-05 Scavenger->Skeptic->contract-auditor security-floor audit deliverable (G1-G13 reject-set + every candidate's disposition + the runs=200 correction)"
  - "SCAV-319-01 GAS-02 loop-invariant hoist surfaced with an approve-if-real-saving / no-op-if-already-hoisted Skeptic disposition -> handed to Plan 05's USER-APPROVED diff"
affects: [319-05, 320]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "GAS-02 one-creditFlip-per-tx proven BEHAVIORALLY by cranker-scoped CoinflipStakeUpdated counting (topics[1] == cranker) to isolate the crank reward from box-winnings credits that go to the box owner"
    - "GAS-04 Sub-1-slot proven by a comment-stripped byte-width SUM (sum of minimum field widths == 13 <= 32) so a widening regression flips RED, with a _structFieldBytes(...)-returns-uint256.max trap on a missing field"
    - "G1-G13 guard byte-presence pinned via the JackpotSingleCallCorrectness _stripComments/_countOccurrences idiom (no == 0 gate on an unfiltered file; NatSpec cannot self-satisfy)"
    - "GAS-05 audit = gas-scavenger (reckless candidates) -> gas-skeptic (G1-G13 hard-reject) -> contract-auditor (invariant proof for any G-row-touching candidate), reasoned from the corrected runs=200 runtime weight (NOT the SKILL.md stale runs=2)"

key-files:
  created:
    - "test/gas/CrankLeversAndPacking.t.sol"
    - ".planning/phases/319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas/319-GAS-05-GUARDRAILS.md"
  modified: []

key-decisions:
  - "crankBoxes one-creditFlip is asserted CRANKER-SCOPED (not raw event count): a box open itself credits BURNIE winnings to the box OWNER via LootboxModule:1036, which conflates with the post-loop crank-reward credit; filtering by the indexed player topic isolates the single crank reward to the cranker"
  - "GAS-04 Sub 1-slot is proven by a byte-width SUM source-presence assert (ffi is OFF in foundry.toml, so forge inspect via vm.ffi is unavailable); the 'a single slot' NatSpec phrase is comment-only and correctly stripped, so the gate keys on 'struct Sub {' + the per-field width sum instead"
  - "GAS-05 verdict: REMOVAL-CLEAN — all six Scavenger candidates rejected or held; the three that touch a G-row (G12 x2, G11) were escalated to contract-auditor and REJECTED; the security floor is intact at HEAD; only SCAV-319-01 (the optional hoist) is handed to Plan 05, gated on a real-saving measurement"
  - "the runs=200 (not the SKILL.md runs=2) correction is the disposition lens: a candidate justified purely by deployment-bytecode size carries LOW weight; a candidate the optimizer already performs (e.g. hoisting a pure call of constants) is a NO-OP at runs=200"

patterns-established:
  - "Cranker-scoped creditFlip counting (filter CoinflipStakeUpdated by topics[1]) to prove one-reward-per-tx on a path where the materialization also credits a distinct recipient"
  - "Comment-stripped byte-width-sum packing assertion as a portable substitute for forge-inspect storage-layout when ffi is disabled"

requirements-completed: [GAS-02, GAS-03, GAS-04, GAS-05]

# Metrics
duration: 22min
completed: 2026-05-24
---

# Phase 319 Plan 04: GAS-02/03/04 Lever Assertions + GAS-05 Security-Floor Audit Summary

**CrankLeversAndPacking.t.sol (7/7 green) proves the batched-reward + packing levers HOLD and pins the G1-G13 guards byte-present RED-on-regression; 319-GAS-05-GUARDRAILS.md runs the Scavenger->Skeptic->contract-auditor pass to a REMOVAL-CLEAN verdict (security floor intact, only the optional GAS-02 hoist handed to Plan 05) — zero contracts/*.sol mutation.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-05-24T08:33Z (approx)
- **Completed:** 2026-05-24
- **Tasks:** 2
- **Files modified:** 2 (both created; zero contract mutation)

## Accomplishments
- **GAS-02 proven BEHAVIORALLY:** a multi-item `crankBets` (N=3 losing bets) and a multi-box `crankBoxes` (N=3 boxes) each emit EXACTLY ONE crank-reward `creditFlip` carrying the summed per-item peg; read-once (`uint24 lvl = _activeTicketLevel();` exactly twice — once per crank fn), one batched AfKing `batchPurchase{value: totalValue}` transfer, and one bounty `creditFlip` per sweep are source-present (comment-stripped).
- **GAS-03 proven:** the parallel-array grouped signatures `crankBets(address[],uint64[])` / `batchPurchase(address[],uint256[],uint8[])` and per-work-type homogeneity (exactly one `crankBets`, one `crankBoxes(uint256 maxCount)`; no mixed-work dispatcher) source-present.
- **GAS-04 proven:** `Sub` packs to one slot (field-width sum == 13 <= 32), `boxCursor`/`boxCursorIndex` are `uint48`, and `enqueueBoxForCrank` is the only crank-added storage write (off the bet/box-placement hot path).
- **G1-G13 pinned:** every security-floor guard asserted byte-present (comment-stripped) at its source — a future regression that deletes a guard flips the suite RED.
- **GAS-05 audit complete:** six Scavenger candidates dispositioned; verdict REMOVAL-CLEAN; the G1-G13 floor VERIFIED-PRESENT; the runs=200 correction documented and applied; SCAV-319-01 (the optional loop-invariant hoist) surfaced with an approve-if-real-saving / no-op-if-already-hoisted disposition for Plan 05.

## Task Commits

Each task was committed atomically:

1. **Task 1: GAS-02/03/04 lever + packing assertion suite** - `dfba3ac1` (test)
2. **Task 2: GAS-05 Scavenger -> Skeptic -> contract-auditor security-floor pass** - `9d1c9481` (docs)

**Plan metadata:** (this commit) `docs(319-04): complete GAS-02/03/04 lever-assertion + GAS-05 security-floor audit plan`

## Files Created/Modified
- `test/gas/CrankLeversAndPacking.t.sol` - GAS-02/03/04 assertion suite (7 tests: behavioral one-creditFlip for both cranks, read-once/one-transfer/one-refund source-presence, GAS-03 grouping+homogeneity, GAS-04 Sub-1-slot + uint48 cursor + no-new-hot-path-storage, G1-G13 grep-presence pins, plus an anti-vacuity harness-is-live test). Reuses the JackpotSingleCallCorrectness `_stripComments`/`_countOccurrences` idiom + the CrankFaucetResistance losing-bet/creditFlip-count + CrankOpenBox box-enqueue idioms.
- `.planning/phases/319-.../319-GAS-05-GUARDRAILS.md` - the GAS-05 deliverable: the full G1-G13 reject-set table (each guard file:line, why load-bearing, proving 318 test, VERIFIED-PRESENT at HEAD), the runs=200 correction, six Scavenger candidates with Skeptic dispositions (three escalated to contract-auditor for the G-rows they touch), and the REMOVAL-CLEAN verdict.

## Decisions Made
- **crankBoxes one-creditFlip is cranker-scoped:** a box open credits BURNIE winnings to the box OWNER (LootboxModule:1036), conflating with the post-loop crank-reward credit. Filtering `CoinflipStakeUpdated` by the indexed `player` topic (`topics[1] == cranker`) isolates the single crank reward — the cranker is distinct from the three box owners.
- **GAS-04 Sub-1-slot via byte-width SUM:** `ffi` is OFF (`foundry.toml`), so `forge inspect ... storage-layout` via `vm.ffi` is unavailable; the plan's stated fallback (source-presence sum of `<= 32` bytes) is used. The "a single slot" phrase is NatSpec-only and correctly stripped, so the gate keys on `struct Sub {` + the per-field width sum (==13).
- **GAS-05 reasoned from runs=200, not runs=2:** the gas-scavenger SKILL.md's stale `runs=2`/bytecode-first framing is corrected throughout — candidates were weighted by runtime SLOAD/SSTORE/CALL effect; the optional hoist is flagged as a likely optimizer no-op at runs=200.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] crankBoxes raw creditFlip count conflated box-winnings with the crank reward**
- **Found during:** Task 1 (assertion suite — first `forge test` run)
- **Issue:** The initial `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` counted ALL `CoinflipStakeUpdated` events and asserted == 1, but got 2: a box open itself credits BURNIE winnings to the box owner via `coinflip.creditFlip(player, burnieAmount)` (LootboxModule:1036), which is a second emission distinct from the post-loop crank-reward credit. The one-creditFlip-per-tx LEVER genuinely holds; the test's counting method was the bug (it must isolate the crank reward, exactly as CrankFaucetResistance isolates it for bets via a losing bet).
- **Fix:** Added a cranker-scoped counter `_countCoinflipStakeUpdatedFor(address who)` that filters on the indexed `player` topic (`topics[1]`); the test now asserts exactly one creditFlip to the cranker (distinct from the box owners).
- **Files modified:** test/gas/CrankLeversAndPacking.t.sol
- **Verification:** test now PASS; the cranker receives exactly one creditFlip; all three boxes confirmed opened (non-vacuity).
- **Committed in:** `dfba3ac1` (Task 1 commit)

**2. [Rule 1 - Bug] GAS-04 grep gate keyed on a comment-only phrase that the comment-stripper removes**
- **Found during:** Task 1 (assertion suite — first `forge test` run)
- **Issue:** `testGas04...` asserted `_countOccurrences(afking, "a single slot") > 0`, but "a single slot" appears ONLY in NatSpec block comments (AfKing.sol:78, :206); the `_stripComments` helper correctly removes it, so the gate fired 0 (failed). A comment-only phrase cannot serve as a code-presence gate (the whole point of comment-stripping).
- **Fix:** Replaced the comment-only phrase gate with `_countOccurrences(afking, "struct Sub {") > 0` (a byte-present code declaration); the single-slot claim is already proven structurally by the field-width SUM == 13 <= 32.
- **Files modified:** test/gas/CrankLeversAndPacking.t.sol
- **Verification:** test now PASS; the Sub struct declaration is byte-present and the width sum == 13.
- **Committed in:** `dfba3ac1` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — test-side assertion bugs; the underlying levers/guards genuinely hold)
**Impact on plan:** Both fixes were necessary for the assertions to correctly measure what the plan intends (one crank reward per tx; Sub one-slot). No scope creep; zero contract mutation; the GAS-02/03/04 levers and the GAS-04 packing floor were confirmed HELD, not changed.

## Issues Encountered
- The compiler emits a spurious "state mutability can be restricted to view" warning on the two log-counting helpers; `vm.getRecordedLogs()` is a state-mutating cheatcode (it drains the log buffer), so the helpers cannot be `view` — the same non-view signature is used by the existing CrankFaucetResistance suite. Left as-is (warning, not error).
- Pre-existing shadow/unused-param warnings in `DegenerusGameJackpotModule.sol` are out of scope (not introduced by this plan).

## Self-Check: PASSED

- FOUND: test/gas/CrankLeversAndPacking.t.sol
- FOUND: .planning/phases/319-.../319-GAS-05-GUARDRAILS.md
- FOUND: .planning/phases/319-.../319-04-SUMMARY.md
- FOUND commit: dfba3ac1 (Task 1)
- FOUND commit: 9d1c9481 (Task 2)

## Next Phase Readiness
- **Plan 05 (calibration + USER-APPROVED contract diff):** receives the GAS-05 REMOVAL-CLEAN verdict and the SCAV-319-01 optional-hoist disposition (ship into the single approved `DegenerusGame.sol` diff IFF Plan 02's before/after shows a real runtime saving at runs=200; otherwise drop as a no-op). The two `*_GAS_UNITS` calibration constants remain the primary subject of Plan 05's USER-APPROVED gate.
- **No NEW failures introduced:** the new suite + all adjacent crank/sweep/jackpot suites are green (71/71 in the targeted run); the change is purely additive test + planning docs reading contracts read-only — it cannot widen the 44-test v45 baseline. The full-suite no-new-failures check is the phase gate (Plan 05 / verify-work).
- **No blockers.** Zero `contracts/*.sol` mutation; the security floor is proven intact.

---
*Phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas*
*Completed: 2026-05-24*
