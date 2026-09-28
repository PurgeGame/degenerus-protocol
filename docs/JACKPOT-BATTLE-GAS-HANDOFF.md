# Jackpot battle: roll cap, bigger budgets, fewer transactions

The gas derivation for the daily jackpot battle's draw and settlement budgets, with the dated work log (2026-09-27) that produced it. Where the log and the code differ, the code and [VERIFICATION.md](VERIFICATION.md) are current:

- **One roll ceiling for everything.** Production has one `_SLIP_ROLL_BUDGET = 1_000` and `_SLIP_ROLL_CEILING = 1_511`, shared by all engine entry points and all battle types. The jackpot-only constants and selection branch described below were removed, so the notes about ordinary runs keeping a larger budget are historical. The jackpot gas envelope uses the same ceiling.
- **The Added formula** moved from `DegenerusGameAdvanceModule._finalizeRngRequest` into `JackpotBattle.lockJackpotBattle`.
- **Verification.** All source gates, the storage-layout oracle and the full Foundry and Hardhat suites pass. The largest measured jackpot transaction is 7,196,658 gas. See [the verification snapshot](JACKPOT-FIXED-8K-PROPOSAL.md#verification-snapshot) for sizes, coverage and limits. The estimates and sampled tails below do not constitute a proof of maximum transaction gas.

## Design constraints

- Fixed 8,000-FLIP jackpot fee.
- Added = max(floor, 0.5% of the recorded pool): the floor is 150,000 FLIP while the Game's `level` is 0 or 1, and 50,000 after.
- One award per 10,000 of Added, capped at 500.
- Every entry in a field throws the same dice.
- Added money is not craps action. Only the fee-funded bankroll is booked, at seal.
- The daily RNG lock may stay held through the whole battle.
- Gas:
  - no call over 10M except in fewer than 1% of cases;
  - never 11M in any realistic case;
  - 12M must be impossible.
  - With the roll cap below, the target is a **hard** 10M.
- No reverts on the hot chain that depend on another module's invariants.

## Starting point (180/180 tests)

- **`CrapsPriceLib`:** the Added floors, `JACKPOT_AWARD_VALUE = 10,000`, and `jackpotAdded(X, level)`.
- **`DegenerusGameAdvanceModule._finalizeRngRequest`:** applies the floor.
- **`JackpotBattle`:**
  - awards = Added / 10,000;
  - `_bookFees` books action at seal and credits the 2% comp once;
  - `_append` skips malformed or empty entries;
  - a resumed `_prepare` keeps the frozen round.
- **`CrapsBattle`:** `resolveSlot` and `_payout` book and comp nothing for jackpot slots.
- **`CrapsEngine.settleBattle`:** shared dice for every entry. An award keys only its scatter, survival coin and shooter boost to `hash3(word, "JackpotAwarded", betId)`.
- **`DegenerusGameJackpotModule._collectJackpotChunk`:** an empty queue forfeits the draw instead of dividing by zero.
- **Tests:**
  - `JackpotBattle.t.sol`: the dice identity test, fee-only booking, an award-only field booking nothing, bad draws skipped;
  - `CrapsPricing.t.sol`: floors by level;
  - `JackpotMergeAdvance.t.sol`: a small pool is raised to the floor.
- **Manifest:** a row for `IFlipCrapsComps.creditCrapsComps` in `_bookFees`.
- **Gates:**
  - red before these changes, and still showing only those failures (merge-manifest drift): `check-advance-calls`, `check-rng-taint`, `check-unchecked`;
  - all other gates are green.
- **Measured:**
  - The largest real cold battle transaction is 1.38M across 8 end-to-end scenarios, at 300 units per call.
  - Engine gas is at most ~643 per roll, all-in.
  - In 50,000 realistic runs (3,000 bankroll, 5× goal, jackpot boost and rotation, mixed boards), rolls are p50 61, p99 173, p99.9 242, max 397. Engine gas at p99.9 is ~145k.
  - The fitted tail puts P(rolls > R) at 1e-6 near R ≈ 480, 1e-9 near 715, and 1e-12 near 950.

## Tasks

1. **Confirm the tail before choosing the cap.**
   - Sample about 1M runs across a wider board set: blank; each single leg at counts 1 to 3; mixed 5- to 7-chip boards; don't-pass-heavy boards.
   - Report P(rolls > R) for R = 480, 715, 1,000, 1,511, per board class and pooled.
   - Run length is scale-free, so the bankroll size doesn't matter.
   - Harness pattern (scratch only, not committed): call `CrapsEngine.settleBattle((6<<64)|seat, header, 60, 3_000 ether, 15_000 ether, 6, (60<<64)|seat, word)` in a loop, with a random word per run. Log `totalRolls` and `gasleft` deltas, run with `--gas-limit 900000000000`, and split the loop across tests.

2. **Cap jackpot runs at 1,000 rolls** (or whatever task 1 supports, keeping at least 1e-6 margin with room to spare).
   - In `CrapsEngine.settleBattle`, pass a roll budget of 1,000 when `bound < 2**40 && bound % 8 == 6`, and the normal `_SLIP_ROLL_BUDGET` otherwise.
   - Trace `_play` → `_settleSlip(b, seed, bankroll, goal, cap, rollBudget, player, boost)` and `_handCursor` to confirm what happens at the cap:
     - a budget of 512 or more is checked between shooters, so the ceiling is budget − 1 + 512 = 1,511 rolls;
     - after the goal is reached, the run stops and keeps what it has;
     - before the goal, the existing hard-bound rule counts it as a bust.
   - Ordinary windows keep the full limits.
   - Add a test proving a jackpot run can never exceed 1,511 rolls, and that ordinary windows are unchanged.

3. **Raise the settle budget from 300 to 1,500 units.**
   - The literal is in `_playJackpotBattle` (`advanceJackpotBattle(300)`).
   - Update the manifest rationale that says "300 work units", the NatSpec and the docs.

4. **Raise the draw chunk from 50 to 150 entries.**
   - Change `JACKPOT_BATTLE_ENTRANTS` in the jackpot module, the `field.length > 50` check in `JackpotBattle._append`, and the "at most 50" comments in `JackpotBattleFieldLib` and the `appendJackpotBattle` NatSpec.
   - Measure a 150-entry append, including the worst case for the field lib's deduplication: many distinct wallets sharing one low address byte, which forces the linear scan.

5. **Prove the gas bound.** The worst possible settle call is 1,499 units of prior seats (at ≤4.7k per unit) + one capped run (≤1,511 rolls at ≤700) + seat bookkeeping and credit + the final payout (main pot, lane, RIU with pass split, record arm) + call overhead. It must stay at or below 10M.
   - Measure the finalization and overhead terms directly. The current `_FINAL_UNITS = 6` understates finalization.
   - Re-measure `JackpotMergeAdvance` under `FOUNDRY_ISOLATE=true` and report the largest transaction and the number of settle transactions.

6. **Optional:**
   - Let one settle call cross from paid runs into awarded runs by removing the clamp `if (from < paidEnd && end > paidEnd) end = paidEnd;` in `resolveSlot`, and update `test_PaidOwnThenDayThenAwarded_NoEarlyFinalization`.
   - Start settling in the seal transaction.

## How to verify

- **Focused run:** `python3 scripts/test-foundry-groups.py --file <test> …` patches the deployment pins, runs the listed sources as one compile unit and restores the pins.
- **Suites:**
  - `test/craps/{CrapsCompBudget,CrapsHighRoller,CrapsPasses,CrapsPricing,JackpotBattle}.t.sol`, plus the helpers `CrapsPins.sol`, `CrapsPreferenceStore.sol` and `CrapsViews.sol`;
  - `test/fuzz/{CrapsCompDonation,CrapsCompLane,CrapsPassAwards,JackpotMergeAdvance,LootboxCrapsPasses,SdgnrsLevelHighPasses}.t.sol`, plus `test/fuzz/helpers/DeployProtocol.sol`.
- **Sizes:** `forge build --skip test` then `node scripts/check-deployment-sizes.js`. With patched addresses CrapsBattle was 24,390 bytes at this stage; keep it under the 24,450-byte rail.
- **Gates:** `make -s check-*`, judged by exit code.

## Results (2026-09-27)

Tasks 1–6 are done. Task 6 was adopted on the condition that the sealing call's draw is charged against the same budget.

### 1. Run-length tail

10,000,000 uncapped jackpot runs (bound 6, 3,000 bankroll, 5× goal, random field size 1–650 and seat, half with award keys), 2.5M per board class:

| Class | > 480 | > 715 | > 1,000 | > 1,511 | Max | Fitted P(> 1,000) |
| --- | --- | --- | --- | --- | --- | --- |
| Blank | 9 | 0 | 0 | 0 | 554 | 8.6e-12 |
| One leg, count 1–3 | 6 | 0 | 0 | 0 | 639 | 3.8e-12 |
| Mixed 5–7 chips | 8 | 0 | 0 | 0 | 576 | 2.5e-12 |
| Don't-pass heavy | 3 | 0 | 0 | 0 | 520 | 3.0e-14 |
| Pooled | 26 | 0 | 0 | 0 | 639 | 3.2e-12 |

- Past 250 rolls the tail falls by one e-fold every ~39 rolls, and the fit reproduces the 26 observed hits past 480.
- Pooled fit: P(> 715) ≈ 5e-9, P(> 1,000) ≈ 3e-12, P(> 1,511) ≈ 6e-18. Blank boards are the heaviest class, at 9e-12 past 1,000.
- A 1,000-roll cap therefore binds on about one run in 10^11.

### 2. Roll cap

- `Craps._JACKPOT_ROLL_BUDGET = 1000`, with `_JACKPOT_ROLL_CEILING = 1,511`.
- `CrapsEngine.settleBattle` applies it when `bound < 2**40 && bound % 8 >= 6`.
- **Remainder 7 matters.** A warm-up or skipped day's detached jackpot slot sits at remainder 7, and `_slotWindow` passes bound = slot. So the test mirrors `_isJackpotSlot`, not `== 6`.
- At the budget the run stops between shooters. Before its goal it is a bust and pays nothing. After the goal it stops as a Goal, and the reserve keeps the bankroll at or above the goal.
- Tests in `JackpotBattle.t.sol`:
  - `testFuzz_JackpotRunStopsInsideItsRollCeiling`: 1,000 runs across attached and detached slots, latched and not; every run stops within [1,000, 1,511].
  - `testFuzz_OrdinaryAndCustomRunsKeepTheFullLimits`: ordinary and custom runs reach the 512-shooter cap, past 1,511 rolls.

### 3–4. Budget and chunk

- `JACKPOT_BATTLE_SETTLE_UNITS = 1_500` in the jackpot module.
- `JackpotBattleFieldLib.MAX_CHUNK = 150` is shared by the module's `JACKPOT_BATTLE_ENTRANTS` and by `JackpotBattle._append`'s length check. The two sides can no longer disagree.
- NatSpec, manifest rationale and `JACKPOT-BATTLE-MERGE.md` are updated.

### 5. Gas bound

Measured on the real protocol under `FOUNDRY_ISOLATE`, with a probed scratch copy of `CrapsBattle`:

| Term | Measured | Used in the bound |
| --- | --- | --- |
| Warm seat, gas per charged unit (engine, plumbing and credit) | ≤ 4.27k | 4.7k |
| Cold first seat's extra plumbing | ≤ 22.5k | 22.5k |
| Warm seat plumbing, net of the engine | ≤ 12.4k (high seat) | 12.5k |
| Capped run (200k runs, 1,000–1,094 rolls) | ≤ 718k; ≤ 704 gas/roll all-in | 1,511 × 704 = 1.064M |
| Credit per paying seat | ~26.5k | 26.5k |
| Finalization: main pot, contested lane, rare RIU with pass split, record arm, routine stamp (forced) | 215–254k | 300k |
| Call overhead (advance tx, delegate, resolver entry) | ~90–120k | 130k |

**Worst settle call:**

0.13 (overhead) + 1,499 × 4.7k (7.05) + 0.0225 (cold first seat) + 0.035 + 1.064 + 0.027 (last seat: plumbing, capped run, credit) + 0.30 (finalization) ≈ **8.63M**.

With the measured 4.27k per unit instead of 4.7k, it is ≈ 7.95M.

The 4.7k-per-unit figure holds for any hand-length pattern on the shared dice. Short hands drain every legal board, so short-hand runs are short: at most 17 rolls below 3 rolls per hand. Across 12,000 sampled runs, with the worst plumbing added, no seat costs more than 4.23k per unit.

**Monte Carlo:** 102,400 shared-dice fields, one 1,500-unit call each, with the worst plumbing, full credits and the forced finalization charged on every call. Max 6.45M, mean 5.75M, none above 8M, at most 183 seats in one call.

**Draw chunk:** a 150-entry chunk costs 6.9–7.2M. The worst case has distinct wallets on one low byte, which forces the dedupe's full scan. `JackpotBattleFieldLib.prepare` alone costs 2.6M in that case, against 0.54M with distinct low bytes.

**`JackpotMergeAdvance`** (isolate):
- The existing 8 scenarios' largest jackpot tx is 0.67M–2.87M, with 2 settle transactions each.
- The new `test_FullDrawChunksAndSettleCallsStayUnderTenMillion` covers 42 paid seats and 500 awards drawn over one low byte. Largest tx 7.20M (a draw chunk), 4 draw and 9 settle transactions. At 300 units it would take 38 settle transactions.
- The test asserts ≤ 10M per transaction, 4 draws and ≤ 10 settles.

**`_FINAL_UNITS = 6`** understates finalization (~250k), but nothing depends on it:
- The finalizing seat is the field's last, so `resolveSlot` has no seat after it.
- `keepScheduled` breaks after one `resolveSlot`.

### Verification

- 188/188 tests pass in the isolated copy, with and without `FOUNDRY_ISOLATE`. That is the 180 listed above plus the 2 cap tests, 5 rewritten `test/gas/JackpotBattleDedupGas.t.sol` cases (now at 150 entries) and the full-chunk advance test.
- Mutation checks all fail as they should: the cap removed, `>= 6` changed to `== 6`, `MAX_CHUNK` set back to 50, the budget set back to 300.
- Sizes are unchanged except CrapsEngine (7,585 B). CrapsBattle is 24,390 B (patched addresses), 186 under the ceiling.
- Gates: the same three are red with identical failures before and after (`check-advance-calls`, `check-rng-taint`, `check-unchecked`). The other seven are green. `check-interfaces` was not run, because it builds in the repo and no selector changed.

### Merge drift found at this stage

These predated this work; all were resolved before commit:
- `unchecked-manifest` row `_playJackpotBattle ++found`.
- `test/unit/JackpotFarFutureCoinUnits.test.js`, which regex-checks `JACKPOT_BATTLE_ENTRANTS = 50` and the old walk.
- The old-design `JACKPOT_BATTLE_ENTRANTS = 50` constants in `test/gas/{JackpotBattleStageGas,PurchaseDailyWorstCase,AdvanceNestedFullCompositionGas}.t.sol`.
- `ContractAddresses.sol`'s JACKPOT_BATTLE comment ("holds no storage … GAME credits the result").

### 6. One walk across the paid boundary; settling in the sealing call

- **Paid → awarded:** the clamp in `CrapsBattle.resolveSlot` is gone.
  - Settlement needs the round's word, which exists only once the whole field is sealed, and the entrant count includes the awards from that moment. So one walk can cross from paid into awarded seats and the field still finalizes exactly once.
  - CrapsBattle shrinks to 24,273 B (303 left).
- **Sealing call:** the call that seals the field charges its own draw `JACKPOT_DRAW_BASE_UNITS + n × JACKPOT_DRAW_ENTRY_UNITS` (110 + 10 per entry) and settles on whatever is left of the 1,500 units.
  - Measured draw cost is ~496k + 34.8k·n + 61·n² (the dedupe scan). The charge covers every chunk size: at 147 entries it budgets 7.41M against 6.92M measured.
  - A sealing chunk of 139+ entries leaves no budget and settles nothing.
  - The budget is a pure function of the chunk size, with no gas meter.
- **Bound:** the draw and the settlement are charged in the same 4.7k units against one 1,500 budget, so the worst sealing call stays within the 8.6M bound above.
- **Measured sealing calls:**

| Sealing chunk | Units left to settle | Sealing call gas |
| --- | --- | --- |
| 5 | 1,340 | 4.23M (whole field finished, payout included) |
| 25 | 1,140 | 5.24M |
| 50 | 890 | 5.18–5.39M |
| 100 | 390 | 5.96M |
| 128 | 110 | 6.37M |
| 138 | 10 | 6.54M |
| 147 | none | 6.92M |

- **`JackpotMergeAdvance` (isolate):** 6 of the 8 small scenarios now finish the whole battle in the sealing call; the other two (40 paid seats each) take one settle transaction after it. In the 500-award case: 4 draw and 7 settle transactions; largest tx 7.20M (a full draw chunk).
- **New tests:**
  - `test_PaidOwnThenDayThenAwarded_OneWalkFinalizesOnce`: one walk runs from paid through awarded seats and emits one finalization.
  - `test_FullSealingChunkLeavesNoSettleBudget`: about 448 awards, so the sealing chunk is 139+ entries and must not settle.
  - `test_SealingCallSettlesExactlyWhatItsDrawLeft`: replays the sealing call with the table call mocked out, then settles 890 units by hand and requires the same cursor.
- **Mutation checks:**
  - no settling in the sealing call;
  - the clamp restored;
  - the entry charge at 0 (the call runs out of gas at the 10.5M cap);
  - the full 1,500 passed at the seal;
  - the base charge at 0.

  All caught.
- **Suites:** verified set 190/190 at this stage. The remaining merge-drift suites (the battle-stage gas tests and `test/gas/AdvanceNestedFullCompositionGas.t.sol`) were ported before commit; the full Foundry and Hardhat results are in [VERIFICATION.md](VERIFICATION.md).
