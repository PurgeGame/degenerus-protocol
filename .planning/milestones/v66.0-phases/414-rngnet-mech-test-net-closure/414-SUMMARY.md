# Phase 414: RNGNET-MECH — Close the Mechanical-Net Gaps (test-only)

**Status:** PASSED. **4/4 MECH GREEN, contracts tree `0dd445a6` byte-frozen throughout (test-only), 0 contract defects.**
New forge baseline ≈ **899/0/109** (was 889/0/110: +10 new passing tests, one `vm.skip` removed; 0 regressions).

## MECH-01 — real un-mocked redemption claim-side seed (the v62 REDEMPTION-ZERO-SEED catcher)
`test/fuzz/StakedStonkRedemption.t.sol::test_LootboxSeedUsesDayPlusOneRngWord`. Drives a REAL submit→resolve→claim
with `rngWordForDay(day) != rngWordForDay(day+1)` and asserts the lootbox seed == `EntropyLib.hash2(rngWordForDay(day+1), player)`.
A `rngWordForDay(day+1)→rngWordForDay(day)` mutant now FAILS (the ETH legs stay byte-identical, so the prior mocked
suite was blind — this pins the `day+1` operand). 20/20 in the redemption suite.

## MECH-02 — un-skip the mid-day cross-day lootbox binding test
`test/fuzz/RngIndexDrainBinding.t.sol::testBindingConsistencyMidDayCrossDay` — removed `vm.skip(true)`, rewrote off
the slimmed event to read `lootboxRngWordByIndex`/`LR_INDEX`/`boxPlayers`/`presaleBoxEth` directly from storage.
Pins: a post-request box binds to the LIVE `LR_INDEX` (not the in-flight `LR_INDEX-1` word), and the in-flight word
lands at `LR_INDEX-1`. Catches a mutant that drops `_lrAdvanceIndexClearPending` or lands the word at the wrong index. PASS.

## MECH-03 — Coinflip RNG-spine behavioral net (replaces the source-string façade)
`test/fuzz/CoinflipRngSpineBehavioral.t.sol` (4 tests): pins the resolved day-result as a PURE function of the frozen
word — `win == (rngWord & 1)`, reward derived from `keccak(rngWord, epoch)`, independent of player-controllable state.
Catches callsite arg-swaps + reward-path + packing-threshold mutants the `testWinLossRngPathByteUnmodified` string-count
missed. **Full gambit mutation campaign on `processCoinflipPayouts`/`_storeDayResult`/`_dayResult` remains CI-resumable**
(per the v63/v64 precedent — not run inline). 4/4 PASS.

## MECH-04 — coinflip win-classification floor (`b >= 50`)
`test/fuzz/CoinflipWinClassificationFloor.t.sol` (5 tests). `COINFLIP_EXTRA_MIN_PERCENT=78` (≥50), range 38 → normal
wins land in [78,115]; fixed branches 50/150; max byte 150+6=156 ≤ 255. Behavioral readback proves **no win ever stores
`b ∈ [2,49]`** (so `getCoinflipDayResult` never misreads a win as a loss). The panel's concern is refuted by construction. 5/5 PASS.
