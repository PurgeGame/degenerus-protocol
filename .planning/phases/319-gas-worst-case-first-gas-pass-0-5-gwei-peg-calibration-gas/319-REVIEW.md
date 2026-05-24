---
phase: 319-gas-worst-case-first-gas-pass-0-5-gwei-peg-calibration-gas
reviewed: 2026-05-24T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - contracts/DegenerusGame.sol
  - test/fuzz/CrankFaucetResistance.t.sol
  - test/fuzz/CrankNonBrick.t.sol
  - test/fuzz/JackpotSingleCallCorrectness.t.sol
  - test/fuzz/RngFreezeAndRemovalProofs.t.sol
  - test/gas/CrankLeversAndPacking.t.sol
  - test/gas/CrankOpenBoxWorstCaseGas.t.sol
  - test/gas/CrankResolveBetWorstCaseGas.t.sol
  - test/gas/SweepPerPlayerWorstCaseGas.t.sol
findings:
  critical: 1
  warning: 2
  info: 3
  total: 6
status: issues_found
---

# Phase 319: Code Review Report

**Reviewed:** 2026-05-24
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 319 is a gas-measurement + reward-peg calibration phase. The only production-contract change is a two-constant recalibration in `contracts/DegenerusGame.sol`: `CRANK_RESOLVE_BET_GAS_UNITS 120_000 -> 66_528` (:1501) and `CRANK_OPEN_BOX_GAS_UNITS 120_000 -> 137_944` (:1502). The remaining eight files are foundry gas harnesses plus peg-mirror constant syncs. The review focused on the stated scope: whether the calibration is faucet-safe under the SAFE-01 self-crank round-trip-<=0 invariant.

The crank machinery, per-item isolation, one-reward-per-item locks, and the test harnesses' assert-is-worst-case + non-vacuity discipline are all sound and well-constructed. The resolve-bet calibration (66_528) is correct: it was measured as a true per-item marginal via loop-N-divide and the down-move strictly tightens the faucet floor.

However, the open-box calibration (137_944, an UP-move) rests on a measurement-methodology inconsistency that undermines the SAFE-01 faucet floor for the multi-box crank path. The box reward is a FLAT per-box amount, identical in shape to the resolve-bet per-item reward, yet the box marginal was measured as a single `crankBoxes(1)` total that bundles the entire per-transaction fixed overhead into one box, whereas the resolve-bet marginal correctly amortized that overhead away. This is the BLOCKER below.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Open-box reward peg (137_944) is calibrated to a single-box TOTAL, not the per-box MARGINAL — opens the SAFE-01 faucet on the multi-box crank path

**File:** `contracts/DegenerusGame.sol:1502` (consumed at `:1621-1624`); measurement source `test/gas/CrankOpenBoxWorstCaseGas.t.sol:84-128`

**Issue:**
The crank reward is FLAT per item for both work types — `crankBets` adds `_ethToBurnieValue(CRANK_RESOLVE_BET_GAS_UNITS * 0.5 gwei, price)` per resolved bet (:1567-1570), and `crankBoxes` adds `_ethToBurnieValue(CRANK_OPEN_BOX_GAS_UNITS * 0.5 gwei, price)` per opened box (:1621-1624). The SAFE-01 hard floor (round-trip <= 0) requires each per-item reward to be <= the *marginal* gas the cranker burns to earn that item, evaluated at the realistic >=1 gwei market floor: `GAS_UNITS * 0.5 gwei <= per_item_marginal_gas * 1 gwei`, i.e. `GAS_UNITS <= 2 * per_item_marginal_gas`. Critically, the relevant quantity is the per-item *marginal* (the incremental cost of adding one more item to an N-item batch), because a cranker opening N boxes in one transaction earns N rewards while paying the per-transaction fixed overhead only ONCE.

The two constants were measured with INCONSISTENT methodologies for this identical flat-per-item shape:

- **Resolve-bet (66_528) — CORRECT.** `CrankResolveBetWorstCaseGas.testPerOneSpinItemMarginalBelowWorstCase` (`test/gas/CrankResolveBetWorstCaseGas.t.sol:197-242`) cranks 8 independent items in one batch and divides by 8 (`perItemMarginal = totalGas / nItems`, :218). This amortizes away the `crankBets` fixed overhead (entry SLOADs, `_activeTicketLevel`, and the once-per-tx post-loop `coinflip.creditFlip`), yielding the true per-item marginal. 319-GAS-DERIVATION.md §1 (line 82) explicitly justifies this: pegging to a number that includes fixed overhead "would OVER-reimburse and risk opening the SAFE-01 self-crank Sybil faucet."

- **Open-box (137_944) — DEFECTIVE.** `CrankOpenBoxWorstCaseGas.testWorstCaseOpenBoxSingleMaterializationFitsBlockGasLimit` (`:84-128`) brackets `game.crankBoxes(1)` for exactly ONE box (`:101-102`) and uses the raw `gasUsed` (137,944) verbatim as the per-box "marginal." This single-box total bundles the ENTIRE per-transaction fixed overhead of `crankBoxes` into the one box:
  - `_lrRead(LR_INDEX_SHIFT, ...)` + the `boxCursorIndex`/`boxCursor` cold SLOADs and conditional SSTORE (`DegenerusGame.sol:1593-1598`),
  - the `lootboxRngWordByIndex[index]` cold SLOAD (`:1603`),
  - the `boxPlayers[index]` length SLOAD and `_activeTicketLevel()` (`:1605-1610`),
  - the final `boxCursor = uint48(cursor)` SSTORE (`:1631`),
  - and the once-per-tx `coinflip.creditFlip(msg.sender, reward)` (`:1632`) — a cross-contract call that on first credit of the day writes a cold `coinflipBalance[targetDay][cranker]` slot (~20-22k) and emits `CoinflipStakeUpdated` (`BurnieCoinflip.sol:849-855`, `_addDailyFlip`).

None of that overhead recurs for the 2nd..Nth box in a multi-box crank, yet each of those boxes still earns the full 137_944-unit reward.

The derivation's own §2 (line 113) states "a single resolve-bet spin ~= one open-box." Since the resolve-bet per-spin *marginal* is 66,528, the open-box per-box *marginal* should be in the same neighborhood (~66-70k), NOT 137,944. The ~71k gap is precisely the per-tx fixed overhead that the single-box measurement mis-attributes to one box.

**Faucet-floor consequence (round-trip > 0 for the Nth box):** at the SAFE-01 standard >=1 gwei market floor, the per-box reward is `137_944 * 0.5 gwei = 68_972 gwei`. For an additional box whose true marginal is ~66-70k gas, the cranker's incremental cost at 1 gwei is ~66_000-70_000 gwei — at or below the 68_972 gwei reward. As batch size grows and the fixed overhead amortizes toward zero per box, the incremental cost per box converges to the bare materialization marginal (~66k), so `reward (68_972 gwei) > marginal_cost (~66_000 gwei)` and the self-crank round-trip becomes strictly POSITIVE on the marginal box at the 1 gwei floor. This is exactly the Sybil-faucet condition the resolve-bet calibration was deliberately tightened to avoid (and the rationale 319-GAS-06-CALIBRATION.md §2 used to justify the resolve down-move). The box up-move (`120_000 -> 137_944`) reintroduces it on the box path.

Note the asymmetry in the existing tests masks this: `CrankFaucetResistance.testSelfCrankRoundTripNonPositive` (`:139-210`) and the fuzz (`:216-247`) only exercise the SINGLE-item `crankBets` path; there is no self-crank round-trip test for a MULTI-box `crankBoxes` batch, and no per-box-marginal (loop-N-divide) gas measurement exists anywhere (confirmed: `CrankLeversAndPacking.testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` `:167-210` measures the reward SUM via `crankBoxes(3)`, never the gas marginal).

**Fix:**
Measure the open-box per-box marginal with the SAME loop-N-divide idiom used for resolve-bet, then peg `CRANK_OPEN_BOX_GAS_UNITS` to that marginal (which will be materially below 137,944). Add the missing harness:
```solidity
// test/gas/CrankOpenBoxWorstCaseGas.t.sol — measure the true per-box marginal
function testPerBoxMarginalAmortizesFixedOverhead() public {
    uint48 index = _activeLootboxIndex();
    uint256 nBoxes = 8;
    for (uint256 i; i < nBoxes; ++i) {
        address o = makeAddr(string(abi.encodePacked("perbox_", vm.toString(i))));
        vm.deal(o, 100_000 ether);
        _buyBox(o, LOOTBOX_WEI);
    }
    _injectLootboxRngWord(index, FIXED_WORD);

    vm.prank(cranker);
    uint256 gasBefore = gasleft();
    game.crankBoxes(nBoxes);          // one tx, N boxes -> fixed overhead paid once
    uint256 perBoxMarginal = (gasBefore - gasleft()) / nBoxes;

    emit log_named_uint("per_box_marginal_gas", perBoxMarginal);  // <- the real CRANK_OPEN_BOX_GAS_UNITS target
}
```
Then set `CRANK_OPEN_BOX_GAS_UNITS` to `perBoxMarginal` (expected ~66-70k, not 137,944), keeping it at/below the marginal so `GAS_UNITS <= 2 * marginal` holds and the multi-box self-crank round-trip stays <= 0 at >=1 gwei. Add a multi-box self-crank round-trip assertion to `CrankFaucetResistance` mirroring `testSelfCrankRoundTripNonPositive` but over `crankBoxes(N)` with N>=4 so a future regression of this peg flips RED. This is a frozen-contract constant behind the USER-approved gate — present the corrected value for explicit approval; do not edit autonomously.

## Warnings

### WR-01: No multi-box self-crank round-trip test — the SAFE-01 proof has a coverage hole on the box path

**File:** `test/fuzz/CrankFaucetResistance.t.sol:139-247`

**Issue:**
The SAFE-01 faucet-resistance suite proves round-trip <= 0 only for the single-item `crankBets` path (`testSelfCrankRoundTripNonPositive`, `testFuzz_RoundTripNonPositiveAcrossGasPrices`). The `crankBoxes` path is exercised only for the wordless-index early-return (`testCrankBoxesBeforeRngWordEmitsNoReward`, `:373-382`) — there is NO test that opens N boxes by a self-cranker and asserts `reward_eth_at_peg < gasUsed * 1 gwei`. Because the box reward is FLAT per box while the per-tx overhead amortizes, the box path is exactly where the round-trip can go positive (see CR-01). The absence of this test is why the defective box calibration passed Phase 319's green bar.

**Fix:**
Add a `crankBoxes(N)` (N>=4, distinct owners) analog of `testSelfCrankRoundTripNonPositive`: measure real `gasUsed`, compute the summed reward's ETH-peg value, and assert `summedRewardEthAtPeg < gasUsed * 1 gwei` (and at fuzzed gas prices). With the current 137_944 peg this assertion should FAIL for large N — proving the faucet hole — and should pass once the peg is corrected per CR-01.

### WR-02: JGAS-04 delta-attribution band is so wide it is near-vacuous

**File:** `test/fuzz/JackpotSingleCallCorrectness.t.sol` (`testJgas04FreedAutoRebuyStateSloadDeltaAttribution`, the diff hunk `+~294..+~388`)

**Issue:**
The attribution test asserts `gasUsed < theoryMinusFreedHi` (measured < ~10.72M) and `gasUsed + ATTRIBUTION_TOLERANCE_GAS >= theoryMinusFreedLo` (measured + 3M >= ~7.72M, i.e. measured >= ~4.72M). For a measured ~7.5M this is an acceptance band of roughly `[4.72M, 10.72M]` — a span of ~6M around a 7.5M measurement. Almost any plausible measurement passes, so the assertion provides little protection against the freed-SLOAD-delta claim being wrong. It documents a hypothesis more than it tests one. This is not a correctness bug (the test is honestly labeled "consistent-with, not exact, per Assumption A2"), but the band width should be acknowledged as a soft assertion, not a proof of the 1.3M attribution.

**Fix:**
Either tighten the band (e.g. derive a narrower expected window from the actually-measured warm/cold state rather than the ±30% paper estimate), or downgrade the assertion's framing so the SUMMARY does not over-claim that JGAS-04 "empirically confirmed" the 1.3M freed delta. The structural source attestation (`_countOccurrences(jp, "autoRebuyState") == 0`) is the load-bearing check here and is sound; the numeric band is the weak part.

## Info

### IN-01: `_findWorstCase` reverts on word-search exhaustion — robust but undocumented test-flakiness surface

**File:** `test/gas/CrankResolveBetWorstCaseGas.t.sol:294-312`

**Issue:**
`_findWorstCase` scans a fixed 4000-word budget (`WORD_SEARCH_BUDGET`) for a word where the greedy ticket wins all 10 spins, and `require(bestMin >= 2, ...)` reverts setUp if none is found. The search is over a deterministic keccak sequence, so it is reproducible today, but the budget is an empirical constant with no proven lower bound — a change to `packedTraitsDegenerette` or the salt would silently turn this into a setUp revert rather than a meaningful failure. Acceptable for a measurement harness; noting for maintainability.

**Fix:** None required. Optionally add a comment recording the empirically-observed iteration count at which a qualifying word is currently found (margin under the 4000 budget).

### IN-02: Hand-rolled `_stripComments` does not strip inline trailing block comments or interior block-comment lines

**File:** `test/gas/CrankLeversAndPacking.t.sol:567-601` (and the byte-identical copy referenced in `JackpotSingleCallCorrectness.t.sol`)

**Issue:**
`_stripComments` removes only (a) `//` line comments to EOL and (b) lines whose first non-space char is `*` or `/*`. It does NOT handle a `/* ... */` block opened mid-line, nor interior block lines that do not start with `*`, nor a `*/` terminator on a code-bearing line. In this codebase NatSpec is `///` and block comments are `*`-prefixed, so the G1-G13 grep gates are currently faithful, but the stripper is brittle: a future contributor adding an inline `/* ... */` containing a guarded substring (e.g. `revert BatchAlreadyTaken();`) could make a grep gate self-satisfy from a comment. `testGuardGrepHarnessIsLive` (`:402-414`) guards against total stripper failure but not against this partial-stripping class.

**Fix:** None required for this phase. If the stripper is relied on long-term, replace it with a proper tokenizer pass or add a test asserting an inline `/* code-like */` comment is stripped.

### IN-03: Magic gas constants duplicated across five files without a single source of truth

**File:** `test/fuzz/CrankFaucetResistance.t.sol:74-75`, `test/fuzz/CrankNonBrick.t.sol:72-73`, `test/gas/CrankLeversAndPacking.t.sol:69-70`, `test/fuzz/RngFreezeAndRemovalProofs.t.sol:56-57`, mirroring `contracts/DegenerusGame.sol:1501-1502`

**Issue:**
The `CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS` peg values are hand-mirrored in four test files plus the contract (the contract constants are `private`, so the mirrors cannot import them). 319-GAS-06-CALIBRATION.md §6 already flagged that the plan named only one of the four mirrors, and `RngFreezeAndRemovalProofs.t.sol` declares but never consumes them (a dead mirror). This is a recurring desync hazard — a future re-peg that misses a mirror produces a false-green peg-equality assertion. The mirrors are correctly synced in THIS diff (all four moved to 66_528 / 137_944), so this is informational.

**Fix:** None required now. Consider exposing the constants via a test-only public getter or a shared test-constants library so the mirrors derive from one source, and remove the unused declaration in `RngFreezeAndRemovalProofs.t.sol` if it is not consumed.

---

_Reviewed: 2026-05-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
