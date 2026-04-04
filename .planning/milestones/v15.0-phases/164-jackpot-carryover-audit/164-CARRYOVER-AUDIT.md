# Jackpot Carryover Ticket Distribution Audit

**Audit scope:** Carryover ticket distribution (JACK-01) and final-day ticket routing (JACK-02)
**Contracts:** DegenerusGameJackpotModule.sol, DegenerusGameAdvanceModule.sol
**Commit under audit:** 6805969e (fix: carryover tickets at current level, source range 1-4, final day to lvl+1)

---

## Part 1: Carryover Ticket Distribution (JACK-01)

### 1.1 Budget Calculation

**Function:** `payDailyJackpot` (JackpotModule lines 373-384)

```
Line 376:  reserveSlice = _getFuturePrizePool() / 200;
Line 379:  _setFuturePrizePool(_getFuturePrizePool() - reserveSlice);
Line 384:  _setNextPrizePool(_getNextPrizePool() + reserveSlice);
```

**Analysis:**
- `/ 200` = exactly 0.5% of futurePrizePool. Correct.
- Upfront deduction: futurePrizePool is reduced immediately at line 379 before any ticket distribution occurs. This prevents double-spending on subsequent calls.
- reserveSlice flows to nextPool at line 384, providing ETH backing for the carryover tickets.

**Guard conditions (lines 375):**
- `!isEarlyBirdDay`: carryover skipped on day 1 (counter == 0). Correct.
- `initCarryoverSourceOffset != 0`: carryover skipped when no eligible source levels exist. Correct.

**Edge cases:**
- `futurePrizePool = 0`: reserveSlice = 0/200 = 0. Guard at line 389 (`reserveSlice != 0`) prevents distribution call. No deduction, no tickets. **SAFE**.
- `futurePrizePool = 1 wei`: reserveSlice = 1/200 = 0 (integer division floor). Same guard prevents distribution. **SAFE**.
- `futurePrizePool = 199 wei`: reserveSlice = 0. Same. **SAFE**.
- `futurePrizePool = 200 wei`: reserveSlice = 1 wei. Deduction is 1 wei, flows to nextPool. `_budgetToTicketUnits(1, lvl)` at line 393 will produce 0 for any level with price >= 4 wei (all levels are >= 0.01 ETH = 10^16 wei). Guard at line 389 checks `reserveSlice != 0` but `carryoverTicketUnits` will be 0. The 1 wei still flows to nextPool (line 384 already executed), which is fine -- it just adds 1 wei of backing with no tickets. **SAFE** (dust-level, no harm).

**Verdict: SAFE**

---

### 1.2 Source Level Selection

**Function:** `_highestCarryoverSourceOffset` (JackpotModule lines 2495-2508)

```
Line 2499:  for (uint8 o = DAILY_CARRYOVER_MAX_OFFSET; o != 0; ) {
Line 2500:      if (_hasActualTraitTickets(lvl + uint24(o), winningTraitsPacked)) {
Line 2501:          return o;
```

**Analysis:**
- `DAILY_CARRYOVER_MAX_OFFSET = 4` (line 132). Loop scans offsets 4, 3, 2, 1 (descending).
- Returns the highest offset with actual trait ticket holders.
- Returns 0 if none are eligible (loop exhausts without match).
- `_hasActualTraitTickets` (line 2477) checks only `traitBurnTicket[lvl][trait].length`, not virtual deity entries. This is intentional -- carryover draws from actual ticket holders, not virtual deity placeholders.

**Verdict: SAFE**

---

**Function:** `_selectCarryoverSourceOffset` (JackpotModule lines 2513-2556)

```
Line 2519:  highestEligible = _highestCarryoverSourceOffset(lvl, winningTraitsPacked);
Line 2523:  if (highestEligible == 0) return 0;
Line 2524:  if (highestEligible == 1) return 1;
Lines 2526-2536:  startOffset = (hash(randWord, TAG, counter) % highestEligible) + 1
Lines 2539-2554:  wrap-around probe over [1..highestEligible]
```

**Analysis:**
- `highestEligible == 0`: returns 0 immediately. No carryover. Correct.
- `highestEligible == 1`: returns 1 directly (only one option, no randomness needed). Correct.
- `highestEligible >= 2`: random start offset in [1..highestEligible]. `% highestEligible` yields [0..highestEligible-1], `+1` shifts to [1..highestEligible]. Correct.
- Wrap-around probe: iterates i from 0 to highestEligible-1. Candidate = `((startOffset - 1 + i) % highestEligible) + 1`. This maps to the full range [1..highestEligible] starting from startOffset, wrapping around. Correct.
- Entropy source: `keccak256(abi.encodePacked(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter))`. Domain-separated by tag and counter. No collision with other entropy derivations.
- Exhaustive probe: all highestEligible offsets are tried. If _highestCarryoverSourceOffset returned N, then offset N has tickets. The probe will find at least that offset if no earlier one matches. Guaranteed to find a result.

**Edge cases:**
- `highestEligible == 4`, all 4 offsets eligible: random start, guaranteed to find one on first probe. **SAFE**.
- `highestEligible == 4`, only offset 4 eligible: probe will try startOffset, wrap around, eventually reach 4. **SAFE**.
- `highestEligible == 3`, offsets 1 and 3 eligible but not 2: _highestCarryoverSourceOffset returns 3. Probe range is [1..3]. Will try random start, find 1 or 3. **SAFE**.

**Subtle point:** The probe checks `_hasActualTraitTickets`, not just `_hasTraitTickets`. This means a level with only deity virtual entries is skipped. Consistent with _highestCarryoverSourceOffset which also uses `_hasActualTraitTickets`. No mismatch.

**Verdict: SAFE**

---

### 1.3 Ticket Unit Conversion

**Function:** `_budgetToTicketUnits` (JackpotModule lines 915-922)

```
Line 919:  if (budget == 0) return 0;
Line 920:  ticketPrice = PriceLookupLib.priceForLevel(lvl);
Line 921:  return ticketPrice == 0 ? 0 : (budget << 2) / ticketPrice;
```

**Analysis:**
- `budget << 2` = budget * 4. Each ticket costs ticketPrice/4, so budget / (ticketPrice/4) = (budget * 4) / ticketPrice. Correct.
- `budget == 0`: early return 0. Correct.
- `ticketPrice == 0`: returns 0. Prevents division by zero.

**Carryover call site (line 393-396):**
```
carryoverTicketUnits = _budgetToTicketUnits(reserveSlice, lvl);
```
Tickets are priced at `lvl` (current level). This is correct -- carryover tickets are queued at the current level during normal days, so they should be priced at the current level.

**Edge cases:**
- Level 0: `priceForLevel(0)` returns 0.01 ETH. Non-zero, no division issue. **SAFE**.
- Arbitrarily high levels: `priceForLevel` cycles every 100 levels (0.04-0.24 ETH range). Always returns non-zero for any level. **SAFE**.
- Overflow: `budget << 2` could overflow if budget > 2^254. But budget is at most futurePrizePool/200, and futurePrizePool is bounded by total ETH in the protocol (far below 2^254 wei). **SAFE**.

**Verdict: SAFE**

---

### 1.4 Pack/Unpack Round-Trip

**Function:** `_packDailyTicketBudgets` (JackpotModule lines 2558-2569)

```
Pack layout:
  [counterStep: 8 bits @ 0]
  [dailyTicketUnits: 64 bits @ 8]
  [carryoverTicketUnits: 64 bits @ 72]
  [carryoverSourceOffset: 8 bits @ 136]

Total: 8 + 64 + 64 + 8 = 144 bits of 256 available. No overlap.
```

**Function:** `_unpackDailyTicketBudgets` (JackpotModule lines 2571-2587)

```
Line 2583:  counterStep = uint8(packed);                    // bits 0-7
Line 2584:  dailyTicketUnits = uint64(packed >> 8);          // bits 8-71
Line 2585:  carryoverTicketUnits = uint64(packed >> 72);     // bits 72-135
Line 2586:  carryoverSourceOffset = uint8(packed >> 136);    // bits 136-143
```

**Round-trip verification:**
- counterStep: packed at bits 0-7 via `uint256(counterStep)`. Unpacked via `uint8(packed)` = bits 0-7. Match.
- dailyTicketUnits: packed at bits 8-71 via `dailyTicketUnits << 8`. Unpacked via `uint64(packed >> 8)` = bits 8-71. The `uint64` cast truncates any bits above 64. Match.
- carryoverTicketUnits: packed at bits 72-135 via `carryoverTicketUnits << 72`. Unpacked via `uint64(packed >> 72)` = bits 72-135. Match.
- carryoverSourceOffset: packed at bits 136-143 via `uint256(carryoverSourceOffset) << 136`. Unpacked via `uint8(packed >> 136)` = bits 136-143. Match.

**Overlap check:**
- Field 1: bits 0-7 (8 bits)
- Field 2: bits 8-71 (64 bits). Starts at 8 = end of field 1. No overlap.
- Field 3: bits 72-135 (64 bits). Starts at 72 = end of field 2. No overlap.
- Field 4: bits 136-143 (8 bits). Starts at 136 = end of field 3. No overlap.

**Edge case -- max values:**
- `dailyTicketUnits` at uint64 max (2^64-1): occupies exactly bits 8-71. The `<< 8` shift places it correctly. The next field starts at bit 72. No bleed.
- `carryoverTicketUnits` at uint64 max (2^64-1): occupies bits 72-135. carryoverSourceOffset at bit 136 is unaffected.
- `carryoverSourceOffset` at uint8 max (255): occupies bits 136-143. No higher fields exist, so no bleed upward.

**Input validation:** Pack inputs are `uint8` for counterStep/offset (already bounded by type), and `uint256` for ticket units which are cast to `uint64` at unpack. If dailyTicketUnits exceeds uint64, the pack would place extra bits above bit 71, potentially colliding with carryoverTicketUnits at bit 72+. However, `_budgetToTicketUnits` returns `(budget << 2) / ticketPrice`. For budget = futurePrizePool (max ~10^23 wei for 100K ETH) and ticketPrice = 0.01 ETH: result = (10^23 * 4) / 10^16 = 4 * 10^7 -- well within uint64 (max ~1.8 * 10^19). **SAFE**.

**Verdict: SAFE**

---

### 1.5 Phase 2 Distribution

**Function:** `payDailyJackpotCoinAndTickets` (JackpotModule lines 525-611)

**Source level reconstruction (lines 540-543):**
```
Line 540:  carryoverSourceLevel = lvl + 1;       // default
Line 541:  if (carryoverSourceOffset != 0) {
Line 542:      carryoverSourceLevel = lvl + uint24(carryoverSourceOffset);
Line 543:  }
```

Matches Phase 1 logic (lines 367-370):
```
Line 358:  carryoverSourceLevel = lvl + 1;       // default
Line 367:  if (initCarryoverSourceOffset != 0) {
Line 368:      carryoverSourceLevel = lvl + uint24(initCarryoverSourceOffset);
Line 369:  }
```

The reconstruction uses the same formula: `lvl + offset`. The offset is preserved through the packed storage. The default `lvl + 1` is only used when offset == 0, in which case the carryover guard at line 590 prevents distribution anyway. **Match confirmed.**

**Entropy derivation (line 544):**
```
Line 544:  entropyNext = randWord ^ (uint256(carryoverSourceLevel) << 192);
```
Domain-separated by carryoverSourceLevel (shifted to high bits). Different from entropyDaily (line 539: `randWord ^ (uint256(lvl) << 192)`). No collision when carryoverSourceLevel != lvl (which is always the case since offset >= 1).

**Distribution call (lines 592-598):**
```
Line 592:  _distributeTicketJackpot(
Line 593:      carryoverSourceLevel,     // sourceLvl: winners drawn from this level
Line 594:      isFinalDay ? lvl + 1 : lvl,  // queueLvl: tickets queued here
Line 595:      winningTraitsPacked,
Line 596:      carryoverTicketUnits,
Line 597:      entropyNext,
Line 598:      LOOTBOX_MAX_WINNERS,
Line 599:      240
Line 600:  );
```

- sourceLvl = carryoverSourceLevel (winners drawn from higher level's trait holders). Correct.
- queueLvl = `lvl` on normal days, `lvl + 1` on final day. Verified separately in Part 2.

**Guard (line 590):**
```
Line 590:  if (carryoverTicketUnits != 0 && carryoverSourceOffset != 0) {
```
Both conditions required: non-zero ticket budget AND a valid source offset. Prevents phantom distribution when either is missing. **SAFE**.

**Data flow tracing: sourceLvl -> winners, queueLvl -> ticket storage:**
1. `_distributeTicketJackpot(sourceLvl, queueLvl, ...)` at line 958
2. `_computeBucketCounts(sourceLvl, ...)` at line 975 -- uses sourceLvl to count trait holders
3. `_distributeTicketsToBuckets(sourceLvl, queueLvl, ...)` at line 983 -- passes both through
4. `_distributeTicketsToBucket(sourceLvl, queueLvl, ...)` at line 1035 -- passes both through
5. `_randTraitTicket(traitBurnTicket[sourceLvl], ...)` at line 1049 -- selects winners from sourceLvl
6. `_queueTickets(winner, queueLvl, units)` at line 1067 -- queues tickets at queueLvl

The separation is clean: winners are always selected from sourceLvl, tickets are always queued at queueLvl.

**Verdict: SAFE**

---

### 1.6 Early-Bird Day Skip

**Lines 316-334, 359, 375 (payDailyJackpot):**
```
Line 316:  isEarlyBirdDay = (counter == 0);
Line 332:  if (isEarlyBirdDay) {
Line 333:      _runEarlyBirdLootboxJackpot(lvl + 1, randWord);
Line 334:  }
Line 359:  if (!isEarlyBirdDay) {    // source selection skipped
Line 375:  if (!isEarlyBirdDay && initCarryoverSourceOffset != 0) {  // budget skipped
```

**Analysis:**
- On day 1 (counter == 0), the early-bird lootbox jackpot runs instead.
- `initCarryoverSourceOffset` remains 0 (never assigned on early-bird path).
- `reserveSlice` remains 0 (guarded by `!isEarlyBirdDay`).
- The packed value will have `carryoverTicketUnits = 0` and `carryoverSourceOffset = 0`.
- In Phase 2, the guard at line 590 prevents distribution.
- No carryover runs on early-bird day. Correct.

**Verdict: SAFE**

---

### 1.7 Edge Case Analysis

**Level 1 (lvl=1):** Source range [lvl+1..lvl+4] = [2..5]. `_hasActualTraitTickets` checks each level. At level 1, levels 2-5 are unlikely to have trait ticket holders (game just started). `_highestCarryoverSourceOffset` returns 0, `_selectCarryoverSourceOffset` returns 0, no carryover. **SAFE**.

**Max level:** `priceForLevel` handles all uint24 values via modular cycling. Level does not affect carryover logic beyond price lookup and trait ticket existence checks. **SAFE**.

**Compressed jackpot (counterStep=2):** Occurs when `compressedJackpotFlag == 1` and `counter > 0` and `counter < 4`. On these days, counter > 0 so `isEarlyBirdDay = false`, carryover runs normally. The doubled `dailyBps` only affects the ETH distribution, not carryover. **SAFE**.

**Turbo mode (counterStep=5):** Occurs when `compressedJackpotFlag == 2` and `counter == 0`. Since `counter == 0`, `isEarlyBirdDay = true`. Carryover is skipped entirely. Turbo has exactly 1 physical day which is the early-bird day, so the early-bird lootbox jackpot runs instead. No carryover gap -- early-bird is a valid alternative. **SAFE**.

---

## Part 1 Function Verdicts

| Function | Lines | Verdict |
|----------|-------|---------|
| `payDailyJackpot` (carryover path) | 357-407 | **SAFE** |
| `_selectCarryoverSourceOffset` | 2513-2556 | **SAFE** |
| `_highestCarryoverSourceOffset` | 2495-2508 | **SAFE** |
| `_budgetToTicketUnits` | 915-922 | **SAFE** |
| `_packDailyTicketBudgets` | 2558-2569 | **SAFE** |
| `_unpackDailyTicketBudgets` | 2571-2587 | **SAFE** |
| `payDailyJackpotCoinAndTickets` (carryover path) | 588-601 | **SAFE** |

---

## Part 2: Final-Day Ticket Routing (JACK-02)

### 2.1 Final-Day Detection in Phase 2

**Function:** `payDailyJackpotCoinAndTickets` (JackpotModule line 591)

```
Line 591:  bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;
```

**Constant:** `JACKPOT_LEVEL_CAP = 5` (JackpotModule line 97).

**Consistency with Phase 1:** Phase 1 uses the same formula at line 314-315:
```
Line 314:  bool isFinalPhysicalDay = (counter + counterStep >= JACKPOT_LEVEL_CAP);
```

Phase 1 captures `counter` from `jackpotCounter` (line 301). Phase 2 reads `jackpotCounter` directly. Since `jackpotCounter` is only incremented at line 605 (AFTER the isFinalDay check at line 591), the values are equivalent. **Consistent.**

**counterStep value trace:**

| Mode | compressedJackpotFlag | counter | counterStep | Formula |
|------|-----------------------|---------|-------------|---------|
| Normal | 0 | 0 | 1 | 0+1=1 < 5 (not final) |
| Normal | 0 | 1 | 1 | 1+1=2 < 5 (not final) |
| Normal | 0 | 2 | 1 | 2+1=3 < 5 (not final) |
| Normal | 0 | 3 | 1 | 3+1=4 < 5 (not final) |
| Normal | 0 | 4 | 1 | 4+1=5 >= 5 (**final**) |
| Compressed | 1 | 0 | 1 | 0+1=1 < 5 (early-bird, carryover skipped) |
| Compressed | 1 | 1 | 2 | 1+2=3 < 5 (not final) |
| Compressed | 1 | 3 | 2 | 3+2=5 >= 5 (**final**) |
| Turbo | 2 | 0 | 5 | 0+5=5 >= 5 (**final**, but early-bird) |

**Turbo analysis:** counter=0 means `isEarlyBirdDay = true`, so carryover is skipped entirely (line 375). The isFinalDay check at line 591 is never reached because `carryoverTicketUnits == 0` and `carryoverSourceOffset == 0`, so the guard at line 590 prevents entry. No gap -- turbo has exactly 1 physical day which runs the early-bird lootbox jackpot, not carryover. **SAFE**.

**Verdict: SAFE**

---

### 2.2 Ticket Routing on Final Day

**Lines 592-600 (payDailyJackpotCoinAndTickets):**

```
Line 592:  _distributeTicketJackpot(
Line 593:      carryoverSourceLevel,              // sourceLvl
Line 594:      isFinalDay ? lvl + 1 : lvl,        // queueLvl
Line 595:      winningTraitsPacked,
Line 596:      carryoverTicketUnits,
Line 597:      entropyNext,
Line 598:      LOOTBOX_MAX_WINNERS,
Line 599:      240
Line 600:  );
```

**Routing logic:**
- Non-final days: `queueLvl = lvl` (current level). Tickets are queued at the current level where they will be eligible for the remaining jackpot days.
- Final day: `queueLvl = lvl + 1`. Tickets are queued at the next level's key space.

**sourceLvl is independent of final-day status:** Line 593 always uses `carryoverSourceLevel` regardless of isFinalDay. This is correct -- the source level (from which winners are drawn) is determined by the random offset selection, not by which day it is.

**Data flow from queueLvl to _queueTickets confirmed (Part 1, Section 1.5):** The queueLvl parameter flows through `_distributeTicketJackpot` -> `_distributeTicketsToBuckets` -> `_distributeTicketsToBucket` -> `_queueTickets(winner, queueLvl, units)` at line 1067. Tickets are stored in the key space corresponding to queueLvl.

**Verdict: SAFE**

---

### 2.3 Why lvl+1 on Final Day Is Correct

**Lifecycle after final jackpot day:**
1. `payDailyJackpotCoinAndTickets` completes, incrementing `jackpotCounter` to >= 5 (line 605)
2. AdvanceModule checks `jackpotCounter >= JACKPOT_LEVEL_CAP` (line 396): true
3. Calls `_awardFinalDayDgnrsReward`, `_rewardTopAffiliate`, `_runRewardJackpots`
4. Calls `_endPhase()` (line 400) which:
   - Sets `phaseTransitionActive = true` (line 512)
   - Resets `jackpotCounter = 0` (line 516)
   - Resets `compressedJackpotFlag = 0` (line 517)
5. On subsequent advanceGame calls, `jackpotPhaseFlag = true` triggers the jackpot-phase branch
6. Eventually transitions: `jackpotPhaseFlag = false`, `lastPurchaseDay = false` (line 377)
7. Level was already incremented at RNG request time (line 1374) before the jackpot phase started

**Why old-level tickets would be stranded:** After `_endPhase`, no more daily jackpot draws occur at the old level. The game transitions to the purchase phase for the next level. Tickets queued at the old level's key space would never participate in a jackpot draw again. By routing to `lvl + 1`, the tickets land in the key space for the next level's purchase/jackpot cycle.

**Cross-reference with MintModule final-day override (line 878-881):**
```
Line 878:  if (cachedJpFlag && rngLockedFlag) {
Line 879:      uint8 step = cachedComp == 2 ? JACKPOT_LEVEL_CAP
Line 880:          : (cachedComp == 1 && cachedCnt > 0 && cachedCnt < JACKPOT_LEVEL_CAP - 1) ? 2 : 1;
Line 881:      if (cachedCnt + step >= JACKPOT_LEVEL_CAP) targetLevel = cachedLevel + 1;
Line 882:  }
```

The MintModule uses the same `counter + step >= JACKPOT_LEVEL_CAP` formula to detect the final day. When detected, `targetLevel = cachedLevel + 1`, routing purchased tickets to the next level. This is consistent with the carryover routing: both systems route to `lvl + 1` on the final day to prevent stranding.

**Verdict: SAFE**

---

### 2.4 lastPurchaseDay Lifecycle

**Set (AdvanceModule lines 327-333):**
```
Line 327:  if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
Line 329:      lastPurchaseDay = true;
Line 330:      if (day - purchaseStartDay <= 3) {
Line 331:          compressedJackpotFlag = 1;
Line 332:      }
Line 333:  }
```
Set when `nextPrizePool` meets or exceeds the level target. Also sets compressed mode if target met within 3 days.

**Early set -- turbo (AdvanceModule lines 144-152):**
```
Line 144:  if (!inJackpot && !lastPurchaseDay) {
Line 147:      if (purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]) {
Line 149:          lastPurchaseDay = true;
Line 150:          compressedJackpotFlag = 2;
```
Set when target met within first 2 days (turbo mode).

**Consumed (AdvanceModule line 1373-1374):**
```
Line 1373:  if (isTicketJackpotDay && !isRetry) {
Line 1374:      level = lvl;
```
The level increment is triggered at RNG request time when `isTicketJackpotDay` (which requires `lastPurchaseDay` to have been true when the purchase-to-jackpot transition occurred). The `!isRetry` guard prevents double-increment on VRF retry.

**Reset (AdvanceModule line 377):**
```
Line 377:  lastPurchaseDay = false;
```
Reset at the jackpot-to-purchase transition (inside the `!inJackpot && lastPurchaseDay` block, after `jackpotPhaseFlag = true`).

**Lifecycle: set -> consumed (level incremented) -> reset. Single-use per level transition. SAFE.**

**Verdict: SAFE**

---

### 2.5 Level Increment Timing

**AdvanceModule line 1370-1374:**
```
Line 1370:  // Increment level at RNG request time when lastPurchaseDay = true.
Line 1371:  // lvl is already purchaseLevel (= level + 1), so set directly.
Line 1372:  // Only on fresh request - retry would double-increment.
Line 1373:  if (isTicketJackpotDay && !isRetry) {
Line 1374:      level = lvl;
```

**Timing:** Level is incremented at VRF _request_ time, not at VRF fulfillment. This happens before the first jackpot day runs. By the time `payDailyJackpot` executes, `level` already reflects the new value. The `lvl` parameter passed to `payDailyJackpot` (line 411: `payDailyJackpot(true, lvl, rngWord)`) is the level at call time.

In the jackpot phase, `lvl = level` (AdvanceModule line 141), which has already been incremented. So during the jackpot phase, `lvl` is the new level (the one just transitioned to), and `lvl + 1` is the next level after that.

For carryover on the final day: `queueLvl = lvl + 1` routes tickets to the level _after_ the current jackpot sequence. This is correct because the current jackpot sequence is about to end.

**Verdict: SAFE**

---

### 2.6 Final-Day Edge Cases

**Final day with zero carryover budget:** If `futurePrizePool` is very small or zero, `reserveSlice = 0`, and `carryoverTicketUnits = 0`. Guard at line 590 (`carryoverTicketUnits != 0`) prevents `_distributeTicketJackpot` call. No tickets queued, none stranded. **SAFE**.

**Final day with zero eligible source levels:** `_selectCarryoverSourceOffset` returns 0, so `carryoverSourceOffset = 0`. Guard at line 590 (`carryoverSourceOffset != 0`) prevents call. **SAFE**.

**Final day + compressed mode (counter=3, step=2):** `isFinalDay = 3+2=5 >= 5 = true`. Carryover runs because counter=3 > 0 (not early-bird), and source selection proceeds normally. Tickets route to `lvl + 1`. **SAFE**.

**Consecutive final days (impossible):** `jackpotCounter` resets to 0 at level transition via `_endPhase` (AdvanceModule line 516). Each level has an independent counter starting from 0. The final day is always the last day of a level's jackpot sequence. Two consecutive final days cannot occur within the same level. **SAFE**.

**Daily ticket (non-carryover) routing on final day:** Daily tickets at line 576-586 always use `queueLvl = lvl + 1` (line 579), regardless of isFinalDay. Carryover tickets use `lvl + 1` only on the final day. On the final day, both distributions queue at `lvl + 1`. On non-final days, daily tickets queue at `lvl + 1` while carryover tickets queue at `lvl`. No key space conflict -- `lvl` and `lvl + 1` are distinct key spaces. **SAFE**.

---

### 2.7 Cross-Check: Phase 1 vs Phase 2 isFinalDay Consistency

Phase 1 (`payDailyJackpot` lines 314-315):
```
bool isFinalPhysicalDay = (counter + counterStep >= JACKPOT_LEVEL_CAP);
```

Phase 2 (`payDailyJackpotCoinAndTickets` line 591):
```
bool isFinalDay = jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP;
```

- Phase 1 `counter` = local copy of `jackpotCounter` (line 301)
- Phase 2 `counterStep` = unpacked from `dailyTicketBudgetsPacked` which was packed in Phase 1
- `jackpotCounter` is not modified between Phase 1 and Phase 2 (only incremented at end of Phase 2, line 605)

These two checks produce the same boolean. **Consistent.**

---

## Part 2 Function Verdicts

| Function / Logic | Lines | Verdict |
|------------------|-------|---------|
| Final-day detection (`isFinalDay`) | 591 | **SAFE** |
| Final-day carryover routing (`queueLvl = lvl+1`) | 592-600 | **SAFE** |
| `lastPurchaseDay` lifecycle | AdvanceModule 144-377 | **SAFE** |
| Level increment timing | AdvanceModule 1370-1374 | **SAFE** |

---

## Summary

### All Function Verdicts

| Function | Lines | Verdict | Notes |
|----------|-------|---------|-------|
| `payDailyJackpot` (carryover path) | JM 357-407 | **SAFE** | 0.5% budget, upfront deduction, current-level pricing |
| `_selectCarryoverSourceOffset` | JM 2513-2556 | **SAFE** | Random probe in [1..highestEligible], exhaustive |
| `_highestCarryoverSourceOffset` | JM 2495-2508 | **SAFE** | Descending scan 4..1, returns 0 if none |
| `_budgetToTicketUnits` | JM 915-922 | **SAFE** | Correct formula, div-by-zero guarded |
| `_packDailyTicketBudgets` | JM 2558-2569 | **SAFE** | 144-bit layout, no overlap |
| `_unpackDailyTicketBudgets` | JM 2571-2587 | **SAFE** | Round-trip preserves all 4 fields |
| `payDailyJackpotCoinAndTickets` (carryover) | JM 588-601 | **SAFE** | Source level reconstructed, guard correct |
| Final-day detection | JM 591 | **SAFE** | Consistent with Phase 1, all modes verified |
| Final-day carryover routing | JM 592-600 | **SAFE** | lvl+1 prevents ticket stranding |
| `lastPurchaseDay` lifecycle | AM 144-377 | **SAFE** | Single-use set/consume/reset |
| Level increment timing | AM 1370-1374 | **SAFE** | At RNG request, before jackpot phase |

JM = DegenerusGameJackpotModule.sol, AM = DegenerusGameAdvanceModule.sol

### Findings

No findings. All audited functions are **SAFE**. The carryover ticket distribution correctly implements:

1. **Budget:** Exactly 0.5% of futurePrizePool with upfront deduction
2. **Source range:** [1..4] with random eligible offset selection
3. **Current-level queueing:** Tickets priced and queued at `lvl` (current level) during normal days
4. **Final-day routing:** Tickets route to `lvl + 1` when `jackpotCounter + counterStep >= JACKPOT_LEVEL_CAP`
5. **No stranding edge cases:** Zero budget, zero sources, and boundary levels all handled by guards
6. **Pack/unpack fidelity:** 144-bit packed storage preserves all 4 fields through Phase 1 to Phase 2
7. **Detection consistency:** `isFinalDay` uses the same formula in both phases and in the MintModule
