# Phase 175 Comment Audit — Plan 02 Findings
**Contract:** DegenerusGameJackpotModule
**Requirement:** CMT-01
**Date:** 2026-04-03
**Total findings this plan:** 4 LOW, 6 INFO

---

## DegenerusGameJackpotModule — Lines 1-1400

### Finding 175-02-001 [INFO] — JACKPOT_FLOW_OVERVIEW numbered list skips item 3

**Location:** `DegenerusGameJackpotModule.sol` lines 28-31

**Comment says:**
```
JACKPOT FLOW OVERVIEW:
1. Pool consolidation at level transition (prize pool splits and merges).
2. `payDailyJackpot` — Handles early-burn rewards during purchase phase and rolling dailies at EOL.
4. `processTicketBatch` — Batched airdrop processing with gas budgeting to stay block-safe.
```

**Code does:** The list jumps from item 2 to item 4, omitting item 3. The actual flow includes `payDailyJackpotCoinAndTickets` as a Phase 2 step between daily ETH distribution and ticket processing. Item 3 was removed during a refactor but the numbering was not corrected, leaving a misleading gap in the overview.

---

### Finding 175-02-002 [LOW] — `runTerminalJackpot` @dev claims "EndgameModule" as caller — stale reference

**Location:** `DegenerusGameJackpotModule.sol` line 224

**Comment says:**
```
/// @dev Called via IDegenerusGame(address(this)) from EndgameModule and GameOverModule.
```

**Code does:** `runTerminalJackpot` is called exclusively from `DegenerusGameGameOverModule` (via `IDegenerusGame(address(this)).runTerminalJackpot(...)` at `DegenerusGameGameOverModule.sol:169`). No call site exists in `DegenerusGameEndgameModule`. The reference to "EndgameModule" is a stale caller attribution that misleads readers about the function's invocation contract.

---

### Finding 175-02-003 [LOW] — `payDailyJackpot` EARLY-BURN PATH NatSpec misattributes "BURNIE-only distribution" to `_executeJackpot`

**Location:** `DegenerusGameJackpotModule.sol` line 282

**Comment says:**
```
///      - Day 1 of each level: BURNIE-only distribution via _executeJackpot.
```

**Code does:** On day 1 of a level (when `isEthDay` is false), `ethDaySlice` remains 0. `_executeJackpot` is called with `ethPool = 0`, causing it to return immediately with no distribution (the ETH branch at line 1162 is skipped when `jp.ethPool == 0`). There is no BURNIE distribution via `_executeJackpot` — the function handles ETH only. On day 1 there is effectively no early-burn jackpot distribution of any kind.

---

### Finding 175-02-004 [INFO] — `payDailyJackpot` NatSpec mentions "Rolls daily quest at the end" — no such call exists

**Location:** `DegenerusGameJackpotModule.sol` line 283

**Comment says:**
```
///      - Rolls daily quest at the end.
```

**Code does:** The early-burn path (lines 440-497) ends after `_distributeLootboxAndTickets` or `_executeJackpot`. There is no call to any quest-roll function in the early-burn code path. The comment appears to be a stale note from a previous design where quest rolls were triggered from this path.

---

### Finding 175-02-005 [INFO] — `_distributeYieldSurplus` @dev names recipients as "DGNRS" but code credits sDGNRS contract

**Location:** `DegenerusGameJackpotModule.sol` line 743

**Comment says:**
```
/// @dev Distributes yield surplus (stETH appreciation) to stakeholders.
///      23% each to DGNRS, vault, and charity claimable, 23% yield accumulator (~8% buffer).
```

**Code does:** The three `_addClaimableEth` calls at lines 761-775 credit:
- `ContractAddresses.VAULT`
- `ContractAddresses.SDGNRS` (StakedDegenerusStonk / sDGNRS, not DGNRS)
- `ContractAddresses.GNRUS` (DegenerusCharity)

The comment says "DGNRS" but the code uses `SDGNRS`. The recipients should be described as "sDGNRS (staked governance token), vault, and charity (GNRUS)."

---

### Finding 175-02-006 [INFO] — `_resolveZeroOwedRemainder` has unnamed `uint24` parameter with no documentation

**Location:** `DegenerusGameJackpotModule.sol` line 1744

**Comment says:** The @dev at line 1740 says "Returns (newPacked, skip) where skip=true means player should be skipped" — no mention of the anonymous parameter.

**Code does:** The function signature includes `uint24,` as the second parameter (unnamed, unused). It is not documented in the @dev comment, so a reader has no way to know what this parameter was intended to represent (likely `lvl`, retained for ABI stability or future use).

---

## DegenerusGameJackpotModule — Lines 1401-end

### Finding 175-02-007 [LOW] — Orphaned comment between `_processSoloBucketWinner` and `_getWinningTraits` references a non-existent function

**Location:** `DegenerusGameJackpotModule.sol` lines 1584-1586

**Comment says:**
```
/// @dev Distributes jackpot loot box rewards to winners based on trait buckets.
///      Awards tickets only (no BURNIE) using jackpot loot box mechanics.
```

**Code does:** This two-line NatSpec block is followed immediately by `_getWinningTraits` at line 1594, which has nothing to do with lootbox reward distribution. The comment is an orphan from a function that was removed or renamed during refactoring. The dangling NatSpec is misleading — a reader would assume `_getWinningTraits` distributes lootbox rewards, when in fact it derives winning trait IDs.

---

### Finding 175-02-008 [INFO] — `processTicketBatch` @dev says "first batch is scaled down by 35%" but the code scales the write budget, not the batch

**Location:** `DegenerusGameJackpotModule.sol` lines 1666-1669

**Comment says:**
```
///      The first batch in a new level round is
///      scaled down by 35% to account for cold storage access costs.
```

**Code does:** At line 1699: `writesBudget -= (writesBudget * 35) / 100;` — this reduces the WRITES BUDGET by 35%, not the batch size directly. The batch processes as many tickets as the reduced budget allows. "Scaled down by 35%" imprecisely describes a budget reduction (WRITES_BUDGET_SAFE × 0.65) rather than a batch count reduction. The actual effect is correct but the description conflates budget with batch size.

---

### Finding 175-02-009 [LOW] — `_raritySymbolBatch` storage layout comment claims `mapping(uint24 => address[256])` but actual type uses `address[][256]`

**Location:** `DegenerusGameJackpotModule.sol` lines 1968-1973

**Comment says:**
```
// Layout assumption: traitBurnTicket is mapping(uint24 => address[256]).
// Solidity stores mapping(key => fixedArray) as keccak256(key . slot) + index,
// with dynamic array elements at keccak256(keccak256(key . slot) + index).
```

**Code does:** `traitBurnTicket` is typed as `address[][256] storage` (line 2026 and 2082 in function signatures), meaning it is a mapping from `uint24` to a static array of 256 dynamic arrays (a fixed-length array of dynamic arrays). The comment's description of "mapping(uint24 => address[256])" implies a fixed array of addresses, but it is actually a fixed-length array of dynamic address arrays. The layout comment partially describes this with "dynamic array elements at keccak256(keccak256(key . slot) + index)" but the type description in the first line is imprecise and would mislead a reader trying to verify the assembly slot calculation.

---

### Finding 175-02-010 [INFO] — `payDailyCoinJackpot` @dev says "75% goes to near-future ([lvl, lvl+4])" but code picks exactly one level, not distributes to all five

**Location:** `DegenerusGameJackpotModule.sol` lines 2143-2145

**Comment says:**
```
/// @dev ... 75% goes to near-future trait-matched winners ([lvl, lvl+4]).
```

**Code does:** `_selectDailyCoinTargetLevel` at lines 2193-2203 picks ONE random level from [lvl, lvl+4] and returns it (or 0 if that level has no eligible tickets). All of the 75% budget goes to winners at that single chosen level, not spread across the range [lvl, lvl+4]. The comment implies distribution across the range when in reality it is a single-level pick.
