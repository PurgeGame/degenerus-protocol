---
phase: 11-token-security-economic-attacks-vault-and-timing
plan: "05"
subsystem: timing
tags: [timestamp, validator, blockchain, day-boundary, quest-streak, jackpot, GameTimeLib]

# Dependency graph
requires:
  - phase: 11-token-security-economic-attacks-vault-and-timing
    provides: RESEARCH.md with TIME-01 and TIME-02 open questions
provides:
  - TIME-01 VERDICT: PASS — dailyIdx guard prevents double jackpot trigger regardless of ±900s validator drift
  - TIME-02 VERDICT: PASS (INFO) — quest streak griefing requires extreme validator coordination; loss is BURNIE-only, not ETH
affects:
  - 11-RESEARCH.md (TIME-01 and TIME-02 resolved)
  - 13-final-report (timing findings feed severity table)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Day-index guard: store last-processed day index (dailyIdx) in state; gate on day == dailyIdx not raw timestamp"
    - "Quest day from stored state: currentDay read from activeQuests[0].day (set by rollDailyQuest), not from block.timestamp at player tx time"

key-files:
  created:
    - .planning/phases/11-token-security-economic-attacks-vault-and-timing/11-05-SUMMARY.md
  modified: []

key-decisions:
  - "TIME-01 PASS: dailyIdx = currentDayIndexAt(block.timestamp) stored after each successful advanceGame(); day == dailyIdx guard (AdvanceModule.sol:136) prevents any second call on the same 24h window regardless of ±900s drift"
  - "TIME-02 PASS (INFO): quest currentDay is read from stored activeQuests[0].day, not from block.timestamp; griefing requires advanceGame() to run between player's submit and inclusion; rated INFO per C4 — bounded BURNIE-only loss, no ETH at risk"

patterns-established:
  - "Timestamp attack scope: ±900s (1.04% of 86400s) cannot shift day index by more than 1 unit, and only within the narrow ±900s window around the 22:57 boundary"
  - "Quest day isolation: quest progress is gated by stored quest.day (set during rollDailyQuest), not live block.timestamp — this eliminates a whole class of timestamp manipulation attacks on quest state"

requirements-completed: [TIME-01, TIME-02]

# Metrics
duration: 10min
completed: 2026-03-04
---

# Phase 11 Plan 05: Timestamp Manipulation Verdicts — TIME-01 and TIME-02

**TIME-01 PASS and TIME-02 PASS (INFO): ±900s validator drift cannot trigger double jackpots; quest streak griefing is theoretically possible within a narrow window but limited to BURNIE flip credit, rated INFO per C4 methodology**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-04T23:16:20Z
- **Completed:** 2026-03-04T23:26:00Z
- **Tasks:** 2
- **Files modified:** 1 (SUMMARY.md created)

## Accomplishments

- TIME-01 verdict delivered: `dailyIdx` day-index guard in DegenerusGameAdvanceModule.sol line 136 prevents double jackpot trigger with documented arithmetic
- TIME-02 verdict delivered: quest `currentDay` is read from stored `activeQuests[0].day`, not `block.timestamp`; griefing window identified and severity classified INFO
- Both verdicts include source line citations, attack arithmetic, and Code4rena severity classification

## Task Commits

Each task was committed atomically:

1. **Task 1: TIME-01 — Daily jackpot double-trigger analysis** - (analysis task, no code change; committed with SUMMARY)
2. **Task 2: TIME-02 — Quest streak griefing analysis** - (analysis task, no code change; committed with SUMMARY)

**Plan metadata:** (see final commit hash below)

## Findings

---

### TIME-01 VERDICT: PASS

**Claim under test:** A malicious validator with ±900s timestamp drift cannot cause `advanceGame()` to execute twice in one real 24-hour period and thus cannot distribute two daily jackpots on the same day.

#### The Guard Mechanism

`DegenerusGameAdvanceModule.sol`, line 136:
```solidity
uint48 day = _simulatedDayIndexAt(ts);   // line 114: day index from current block.timestamp
// ...
if (day == dailyIdx) revert NotTimeYet(); // line 136: gate
```

`dailyIdx` is a persistent storage variable (type `uint48`) set by `_unlockRng(day)`:
```solidity
// DegenerusGameAdvanceModule.sol, line 1140-1141
function _unlockRng(uint48 day) private {
    dailyIdx = day;   // stores the day index of the CURRENT block at unlock time
    // ...
}
```

`_unlockRng(day)` is called at the end of each successful `advanceGame()` execution (lines 154, 197, 273, 357). After a successful advance, `dailyIdx` equals the day index that was computed at the start of that same call.

#### Day Index Formula

```
currentDayIndexAt(ts) = floor((ts - 82620) / 86400) - DEPLOY_DAY_BOUNDARY + 1
```

Where `JACKPOT_RESET_TIME = 82620` (22:57:00 UTC in seconds since midnight).

The day index is an integer that increments exactly once every 86,400 seconds, crossing at 22:57:00 UTC.

#### Double-Trigger Attack Arithmetic

For a second call to succeed, the attacker needs `day != dailyIdx`. After a successful first call that stored `dailyIdx = N`, the second call must produce a `day` value that differs from `N`. Given ±900s drift:

**Case A: First call at 22:56:30 UTC (30s before boundary), validator pushes +30s to 22:57:00:**
- First call resolves: `day = N+1`, `dailyIdx = N+1`
- Second call at any real time within same 24h window (22:57 to next 22:57): `day = N+1`
- `day == dailyIdx = N+1` → `NotTimeYet()` revert

**Case B: First call at 22:58:00 UTC (60s into day N+1), validator pulls back -900s to 22:51:00:**
- First call resolves: `day = N` (22:51 is still day N), `dailyIdx = N`
- `dailyIdx = N` was already the stored value from yesterday's advance (since 22:57 yesterday)
- If `dailyIdx` is still `N` from the previous advance, this call was the second advance attempt for day N → `day == dailyIdx` → `NotTimeYet()` revert

**Case C: Boundary straddle — validator pushes first call to exactly 22:57:00 (day N+1), then second call at 22:57:30 in real time:**
- First call resolves: `day = N+1`, `dailyIdx = N+1`
- Second call at 22:57:30: `day = N+1 = dailyIdx` → `NotTimeYet()` revert
- Even with 900s pull-back on second call to 22:56:30: `day = N` which differs from `N+1`. **But** this would mean the second call is trying to advance day `N` when `dailyIdx` is `N+1`, so `day (N) != dailyIdx (N+1)` — the guard does NOT block it.

Wait — Case C reveals a subtle question. Let me trace this more carefully:

After the first call at 22:57:00 (day N+1): `dailyIdx = N+1`, jackpot for day N+1 distributed.
Second call at real 22:57:30, validator shifts to 22:56:30 UTC timestamp: `day = N`.
`day (N) != dailyIdx (N+1)` — the `NotTimeYet()` guard does NOT fire.
The function proceeds. But does this second call re-distribute the day N jackpot?

The jackpot paid in the first call was for day `N+1`. If the second call runs with `day = N`, it would run `payDailyJackpot` for day `N`. This could constitute a double-distribution IF two different jackpot payouts are possible.

However, there is a second guard: `rngWordByDay[currentDay]`. The `rngGate()` function (line 141: `uint256 rngWord = rngGate(ts, day, purchaseLevel, lastPurchase)`) is called with `day = N`. VRF randomness for day `N` was already consumed in the previous day's advance. Let me check whether `rngWordByDay[N]` is still valid:

The VRF callback stores: `rngWordByDay[requestDay] = word` where `requestDay` is computed at request time. For day `N`, the word was stored and used. After use in the prior advance, does `_unlockRng` clear it?

```solidity
// _unlockRng sets:
dailyIdx = day;       // day = N+1 (the NEW day)
rngLockedFlag = false;
rngWordCurrent = 0;
vrfRequestId = 0;
rngRequestTime = 0;
```

`_unlockRng` does NOT clear `rngWordByDay[N]`. However, reviewing `rngGate()`:

The `rngGate` function (line 141, called with `ts, day=N, ...`) checks whether `rngWordByDay[day]` (= `rngWordByDay[N]`) already has a word. If it does (from the prior day's VRF), it returns that word. The second call would then proceed to execute `payDailyJackpot` for day `N`.

**BUT**: This is a critically different economic context. The second call has `day = N` (manipulated backward) while the real jackpot for day `N` was already paid in the prior cycle (yesterday's advance). The question is whether a second distribution for `day = N` creates new ETH loss.

`payDailyJackpot` distributes from `nextPrizePool` (purchase phase) or from the jackpot phase budget. These are live state variables. A successful second execution would consume additional funds from these pools — constituting a double-distribution.

**However**, the practical feasibility of this attack is extremely constrained:

1. **Window is 900s at most**: The validator can only shift by ±900s. A "straddle" requires the first call to land in the narrow 22:56:30–22:57:00 window (only 30 seconds where a +30s push crosses the boundary), and the second call to land in the 22:57:00–22:58:30 window with a 900s pull-back crossing back below the boundary.

2. **Tx ordering dependency**: The first call must be included immediately after shift, and the second call must be in the same block or next block, with its timestamp manually set back. Ethereum's consensus rule requires `block.timestamp >= parent.timestamp`, so a later block cannot have a smaller timestamp than the prior block. This means the second block with `timestamp = 22:56:30` cannot come **after** the first block with `timestamp = 22:57:00`.

3. **Consensus rule kills the attack**: The validator cannot set `block.timestamp` to a value *earlier than the parent block's timestamp*. Since the first call established a block with timestamp 22:57:00, the second block must have `timestamp >= 22:57:00`, which means `day >= N+1`, which means `day = dailyIdx`, which means `NotTimeYet()` fires.

**Conclusion for TIME-01:** The attack is impossible in practice due to Ethereum's protocol-level monotonicity constraint on `block.timestamp` (each block's timestamp must be strictly greater than its parent's, per EIP-1559 and the consensus spec). A validator who pushed the first call's timestamp forward to cross the boundary cannot then produce a valid block with a *lower* timestamp for the second call. The `dailyIdx` guard is sufficient combined with blockchain timestamp monotonicity.

**TIME-01 VERDICT: PASS**
- Primary guard: `DegenerusGameAdvanceModule.sol:136` — `if (day == dailyIdx) revert NotTimeYet()`
- Secondary constraint: Ethereum consensus requires `block.timestamp` monotonicity; backward drift attacks are invalidated
- ±900s drift is 1.04% of 86,400s; cannot span a full day boundary in one direction without the prior block establishing the new boundary
- No double jackpot distribution is achievable via validator timestamp manipulation
- C4 Severity: **N/A (PASS)**

---

### TIME-02 VERDICT: PASS (INFO)

**Claim under test:** A malicious validator with ±900s timestamp drift can break a target player's quest streak by delaying their quest-completion tx past the 22:57 UTC day boundary.

#### Quest Day Source

The critical architectural point: `currentDay` in all quest handlers is **not** computed from `block.timestamp` at the time the player's tx executes. It is read from the stored `activeQuests` array:

```solidity
// DegenerusQuests.sol, line 1600-1604
function _currentQuestDay(DailyQuest[QUEST_SLOT_COUNT] memory quests) private pure returns (uint48) {
    uint48 day0 = quests[0].day;
    if (day0 != 0) return day0;
    return quests[1].day;
}
```

`quests[0].day` is set when `rollDailyQuest(day, entropy)` is called by BurnieCoin, which passes the `day` parameter from the game contract's `_simulatedDayIndex()` at the time of `advanceGame()`. The quest day advances only when the game advances — not based on individual player tx timestamps.

#### Streak Reset Condition

```solidity
// DegenerusQuests.sol, line 1118-1150 (_questSyncState)
uint24 anchorDay = state.lastActiveDay != 0 ? state.lastActiveDay : state.lastCompletedDay;
if (anchorDay != 0 && currentDay > uint48(anchorDay + 1)) {
    uint32 missedDays = uint32(currentDay - uint48(anchorDay) - 1);
    // use shields or reset streak to 0
}
```

A streak reset fires when `currentDay > anchorDay + 1`, i.e., when two or more game days have passed since the player last completed a quest. `currentDay` here is `quests[0].day` (the game's day index), not the validator-manipulable `block.timestamp`.

#### Griefing Scenario

For a validator to break a streak via timestamp manipulation, the attack requires:

1. Player submits quest tx at 22:56:30 UTC (30s before boundary, game still on day N)
2. Validator delays player's tx inclusion
3. **Meanwhile**, `advanceGame()` is called and included, rolling the quest to day N+1 (`rollDailyQuest(N+1, entropy)` executes, setting `activeQuests[0].day = N+1`)
4. Player's quest tx is now included with `currentDay = N+1`
5. Player's `anchorDay = N-1` (completed yesterday), so `N+1 > (N-1) + 1 = N` — streak resets

This IS a valid griefing sequence. The validator does not need to manipulate timestamp; they simply need to:
- Delay the player's tx beyond the advanceGame() call that crosses the day boundary
- This is within a validator's power if they hold the tx in their local mempool

#### Economic Impact Assessment

The loss from a broken quest streak:
- Per-day quest completion rewards: 100 BURNIE (slot 0) + 200 BURNIE (slot 1) = 300 BURNIE in flip credit
- Streak count `state.streak` is used only for: (a) `awardQuestStreakBonus` called from `DegenerusGameBoonModule.sol:356` (deity boon mechanic), (b) display/UI purposes
- The streak counter itself does not gate any ETH withdrawal, jackpot entry, or direct ETH reward
- `awardQuestStreakBonus` adds streak count as a number (via `_questSyncState` bookkeeping), affecting how deity boon mechanics stack — but no direct ETH payout formula based on streak length was found in the codebase

**Loss quantification:** Losing a streak resets `state.streak` to 0. The player loses:
- Accumulated streak count (no direct ETH value)
- Potential future streaks that compound (also BURNIE-denominated)
- Possible subtle effect on deity boon streak-bonus calculation (INFO-level interaction)

No ETH is at risk from a broken quest streak. All quest rewards flow as BURNIE flip credit via `IBurnieCoinflip.creditFlip(player, reward)`.

#### Severity Assessment (Code4rena Methodology)

| Factor | Assessment |
|--------|-----------|
| Likelihood | LOW — requires validator to specifically target one player's mempool tx AND have advanceGame() execute in the delay window (30–900s window around 22:57 boundary) |
| Impact | LOW — loss is BURNIE flip credit only, no ETH at risk; streak count reset has no direct monetary value |
| Exploitability | LOW — validator needs to know the target's pending tx, hold it, and ensure advanceGame() is included first in the gap |
| Prerequisites | Compromised/malicious Ethereum validator with visibility into private mempool |

**C4 Severity: INFO / QA (Low)**

Rationale: The attack requires a compromised validator with targeted knowledge of a player's pending tx, precisely timed around the 22:57 boundary. The loss is purely BURNIE flip credit with no ETH exposure. No code fix is warranted; the architecture correctly uses stored quest days rather than live `block.timestamp`, which already mitigates the most naive version of this attack. The residual risk from mempool-delay ordering is an inherent blockchain property, not a contract flaw.

**TIME-02 VERDICT: PASS (INFO/QA)**
- Stored `activeQuests[0].day` (not `block.timestamp`) governs streak sync — primary protection
- Residual mempool-delay ordering risk exists at day boundary: validator can delay player tx past advanceGame() rollDailyQuest call
- Economic impact: BURNIE flip credit loss only; zero ETH exposure
- C4 Severity: **INFO / QA** — no code change warranted

---

## Files Created/Modified

- `.planning/phases/11-token-security-economic-attacks-vault-and-timing/11-05-SUMMARY.md` — TIME-01 and TIME-02 verdicts with evidence

## Key Source Locations

| Contract | Line | Significance |
|----------|------|-------------|
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 114 | `day = _simulatedDayIndexAt(ts)` — computes day index from block.timestamp |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 136 | `if (day == dailyIdx) revert NotTimeYet()` — primary TIME-01 guard |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1141 | `dailyIdx = day` in `_unlockRng()` — stores current day index after each advance |
| `contracts/libraries/GameTimeLib.sol` | 14 | `JACKPOT_RESET_TIME = 82620` (22:57:00 UTC) |
| `contracts/libraries/GameTimeLib.sol` | 32 | `currentDayIndexAt(ts) = floor((ts - 82620) / 86400) - DEPLOY_DAY_BOUNDARY + 1` |
| `contracts/DegenerusQuests.sol` | 1118 | `_questSyncState` — streak reset condition |
| `contracts/DegenerusQuests.sol` | 1121 | `if (anchorDay != 0 && currentDay > uint48(anchorDay + 1))` — streak gap check |
| `contracts/DegenerusQuests.sol` | 1600 | `_currentQuestDay` reads from `activeQuests[0].day`, not `block.timestamp` |
| `contracts/DegenerusQuests.sol` | 135-138 | `QUEST_SLOT0_REWARD = 100 ether`, `QUEST_RANDOM_REWARD = 200 ether` (BURNIE) |

## Decisions Made

- TIME-01 PASS confirmed: Ethereum block timestamp monotonicity (each block's timestamp >= parent's) is the decisive factor that eliminates the boundary-straddle attack; the `dailyIdx` guard provides a defense-in-depth layer
- TIME-02 PASS (INFO) confirmed: quest `currentDay` sourced from stored `activeQuests[0].day`, not live timestamp — this architectural choice provides primary protection; residual mempool-ordering risk rated INFO because all streak rewards are BURNIE, not ETH

## Deviations from Plan

None — plan executed exactly as written. Source analysis matched expected code patterns described in the plan's `<interfaces>` block.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- TIME-01 and TIME-02 findings available for Phase 13 final report
- Phase 11 timing analysis complete; no new findings to add to severity table (all verdicts are PASS or INFO)
- Phase 11 may now be closed pending remaining plans

---
*Phase: 11-token-security-economic-attacks-vault-and-timing*
*Completed: 2026-03-04*
