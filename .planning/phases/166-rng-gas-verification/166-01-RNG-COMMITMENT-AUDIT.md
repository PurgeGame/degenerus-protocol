# Phase 166, Plan 01: RNG Commitment Window Audit

**Phase:** 166-rng-gas-verification
**Plan:** 01
**Requirement:** RNG-01 -- Every new or modified VRF-consuming path has its commitment window verified
**Date:** 2026-04-02

## Methodology

Per decisions D-03, D-04, and D-05:

1. **Full call-chain backward trace (D-03):** For each new VRF consumer, trace backward through the entire call chain from consumer to VRF fulfillment callback, documenting every intermediate state that touches the word.
2. **Backward verification (D-04):** Verify that the VRF word was unknown at input commitment time by tracing backward from each consumer.
3. **Player-controllable state check (D-05):** For each path, identify what player-controllable state can change between VRF request and fulfillment.

**Scope (D-01):** Delta only -- new or modified VRF paths from v11.0-v14.0. Unchanged paths cite prior audit verdicts.

---

## Section 1: VRF Architecture Overview

The protocol uses Chainlink VRF v2 for randomness. The VRF lifecycle:

1. **Request:** `vrfCoordinator.requestRandomWords()` called from `_requestRng` (AdvanceModule line ~1298) for daily RNG, or `requestLootboxRng` (line ~764) for mid-day lootbox RNG. Sets `rngLockedFlag = true`, records `vrfRequestId` and `rngRequestTime`.

2. **Fulfillment:** Chainlink coordinator calls `rawFulfillRandomWords` (line ~1491). Validates `msg.sender == vrfCoordinator` and `requestId == vrfRequestId`. For daily RNG (`rngLockedFlag == true`): stores word in `rngWordCurrent`. For mid-day RNG: directly writes `lootboxRngWordByIndex[index]`.

3. **Consumption:** Next `advanceGame` call enters `rngGate` (line ~806), which detects `rngWordCurrent != 0`. Calls `_applyDailyRng` (line ~1574) which applies nudges, writes `rngWordByDay[day] = finalWord`, and sets `rngWordCurrent = finalWord`. The advanceGame loop then uses `rngWord` for daily processing including quest rolling.

**Key invariant:** The VRF word is unknown to all parties until the Chainlink callback executes. `rngWordCurrent` is only written by `rawFulfillRandomWords` (from coordinator) or `_applyDailyRng` (which consumes the callback-stored value). No party can predict or influence the word.

---

## Section 2: Path-by-Path Commitment Window Traces (New/Modified Paths)

### Path A: rollLevelQuest Entropy (v13.0 NEW)

**Consumer:** `DegenerusQuests.rollLevelQuest(entropy)` at line ~1777

**Entropy derivation:** In AdvanceModule at line ~382:
```solidity
uint256 questEntropy = uint256(keccak256(abi.encodePacked(rngWordByDay[day], "LEVEL_QUEST")));
quests.rollLevelQuest(questEntropy);
```

**BACKWARD TRACE:**
```
rollLevelQuest(questEntropy)
  <- keccak256(rngWordByDay[day], "LEVEL_QUEST")           [AdvanceModule:382]
    <- rngWordByDay[day] written by _applyDailyRng          [AdvanceModule:1587]
      <- rngWordCurrent (with nudges applied)                [AdvanceModule:1586]
        <- rawFulfillRandomWords stores rngWordCurrent       [AdvanceModule:1503]
          <- vrfCoordinator delivers random word             [Chainlink VRF v2]
```

**COMMITMENT WINDOW analysis:**

The `rollLevelQuest` call occurs within the advanceGame loop's level transition block (lines 367-388). The execution sequence within a single advanceGame transaction is:

1. `rngGate` returns the VRF-derived `rngWord` (already processed by `_applyDailyRng` which wrote `rngWordByDay[day]`)
2. Level transition housekeeping completes (`_processPhaseTransition`, FF drain)
3. Phase transition completes (`phaseTransitionActive = false`)
4. Jackpot phase begins (`jackpotPhaseFlag = true`)
5. `_drawDownFuturePrizePool` executes
6. `questEntropy = keccak256(rngWordByDay[day], "LEVEL_QUEST")` computed
7. `quests.rollLevelQuest(questEntropy)` called

The entropy is derived from `rngWordByDay[day]`, which was written by `_applyDailyRng` earlier in the same transaction (via `rngGate`). The VRF word was unknown until the Chainlink callback delivered it. The `"LEVEL_QUEST"` tag provides domain separation from daily quest entropy (which uses the raw word or bit-swapped halves).

**Quest type selection inputs:**
- `entropy`: VRF-derived via keccak256 (unknown before callback)
- `type(uint8).max` as `primaryType`: constant (255, ensures no type excluded as duplicate)
- `decAllowed`: derived from `_canRollDecimatorQuest()` which reads `decWindowOpen` -- set during advanceGame BEFORE VRF request based on level number (deterministic from game state)

**Player-controllable state between VRF request and fulfillment:** NONE. The level transition block in advanceGame runs atomically within a single transaction after `rngWordCurrent` is available. No external calls between entropy derivation and `rollLevelQuest`. The block at lines 367-388 executes sequentially: `jackpotPhaseFlag = true`, dec window check, `_drawDownFuturePrizePool`, `rollLevelQuest`. No player action can interleave.

**Verdict: SAFE**

---

### Path B: rollDailyQuest Entropy (v13.0 MODIFIED -- access control changed from onlyCoin to onlyGame)

**Consumer:** `DegenerusQuests.rollDailyQuest(day, entropy)` at line ~313, delegating to `_rollDailyQuest` at line ~366

**Entropy source:** `rngWord` passed directly from advanceGame at line ~258:
```solidity
quests.rollDailyQuest(day, rngWord);
```

**BACKWARD TRACE:**
```
rollDailyQuest(day, rngWord)
  <- rngWord returned by rngGate                            [AdvanceModule:246]
    <- _applyDailyRng(day, currentWord) returns finalWord   [AdvanceModule:836]
      <- rngWordCurrent stored by VRF callback               [AdvanceModule:1503]
        <- rawFulfillRandomWords                             [AdvanceModule:1491]
          <- vrfCoordinator delivers random word             [Chainlink VRF v2]
```

For gap-day backfill:
```
rollDailyQuest(day, rngWord)
  <- rngWord from rngGate (same path as above for current day)
  Note: gap days get backfilled words via _backfillGapDays, but rollDailyQuest
  is only called for the current day. Gap days do NOT trigger quest rolling.
```

**COMMITMENT WINDOW analysis:**

The `rollDailyQuest` call at line ~258 occurs immediately after `rngGate` returns the VRF-derived word. The entropy is the raw VRF word (after nudge application). For the current day, `rngWord` comes from `rngWordCurrent` stored by the VRF callback. The word was unknown to all parties until the Chainlink coordinator delivered it.

**Inside `_rollDailyQuest`:**
- Idempotent per day (line ~370: `if (quests[0].day == day) return` -- via `_seedQuestType` which checks existing day). Prevents double-rolling.
- Slot 0: fixed to `QUEST_TYPE_MINT_ETH` (constant, no entropy consumed)
- Slot 1: `_bonusQuestType(bonusEntropy, primaryType, decAllowed)` where `bonusEntropy = (entropy >> 128) | (entropy << 128)` -- a deterministic bit-shuffle of the VRF word

**Quest type selection inputs:**
- `bonusEntropy`: deterministic transform of VRF word (unknown before callback)
- `primaryType`: `QUEST_TYPE_MINT_ETH` (constant)
- `decAllowed`: from `_canRollDecimatorQuest()` (reads `decWindowOpen`, deterministic from game state)

**Player-controllable state between VRF request and fulfillment:** NONE. `rollDailyQuest` is called from `advanceGame` which is a permissionless bounty function. The only player-controllable aspect is WHEN `advanceGame` is called (earlier or later), but quest types are deterministic from the VRF word -- calling at a different time does not change the outcome for a given day's VRF word. The idempotent guard prevents re-rolling.

**v13.0 change impact:** Access control changed from `onlyCoin` to `onlyGame`. Previously called through `BurnieCoin.rollDailyQuest` (COIN routing to QUESTS); now called directly from AdvanceModule (GAME via delegatecall). The entropy source and derivation are unchanged. The commitment window is unaffected by the routing change.

**Verdict: SAFE**

---

### Path C: _bonusQuestType Entropy Consumption (v13.0 MODIFIED -- added sentinel 0 skip)

**Consumer:** `DegenerusQuests._bonusQuestType(entropy, primaryType, decAllowed)` at line ~1463

**Called from:**
- `_rollDailyQuest` (Path B) with `bonusEntropy` (bit-swapped VRF word)
- `rollLevelQuest` (Path A) with `questEntropy` (keccak256-derived from VRF word)

**BACKWARD TRACE:** Same as Paths A and B -- entropy flows through from VRF word via the respective callers.

**COMMITMENT WINDOW analysis:**

The function is `private pure` -- it has no state access, no storage reads, no external calls. It consumes entropy deterministically:
1. `entropy % totalWeight` selects from weighted type table
2. Iterates through candidates, accumulating weights
3. Falls through to fallback if no valid types (defensive)

All inputs are either:
- VRF-derived (`entropy`) -- unknown before callback
- Constants (`primaryType` = MINT_ETH for daily, or `type(uint8).max` for level)
- Deterministic flags (`decAllowed` from `decWindowOpen`, set based on level number)

No player manipulation vector exists.

**v13.0 change impact:** Adding `candidate == 0` skip (sentinel value) does not affect the commitment window -- it only changes which quest types are in the selection pool. The skip prevents type 0 (unrolled marker) from being selected. The entropy source and consumption pattern are unchanged.

**Verdict: SAFE**

---

### Path D: payAffiliate PRNG (v13.0 MODIFIED -- winner-takes-all mod-20 roll)

**Consumer:** `DegenerusAffiliate.payAffiliate()` mod-20 roll for 75/20/5 distribution (line ~594)

**Entropy source (NOT VRF-derived):**
```solidity
uint256 roll = uint256(
    keccak256(
        abi.encodePacked(
            AFFILIATE_ROLL_TAG,
            GameTimeLib.currentDayIndex(),
            sender,
            storedCode
        )
    )
) % 20;
```

**BACKWARD TRACE:**
```
roll = keccak256(AFFILIATE_ROLL_TAG, dayIndex, sender, storedCode) % 20
  <- AFFILIATE_ROLL_TAG: constant bytes32 = keccak256("affiliate-payout-roll-v1")  [line ~174]
  <- dayIndex: GameTimeLib.currentDayIndex() (current game day)
  <- sender: msg.sender (the purchasing player)
  <- storedCode: player's stored referral code (immutable per player per referrer)
```

All inputs are on-chain and deterministic. A miner or sophisticated actor can predict the roll outcome for a given transaction.

**No-referrer path:** Same PRNG pattern for VAULT/DGNRS 50/50 flip (line ~568-580). Uses identical entropy derivation with `% 2` instead of `% 20`.

**COMMITMENT WINDOW: N/A -- this is NOT a VRF consumer.** No VRF word is involved. The entropy is a deterministic PRNG using on-chain state.

**Known tradeoff (documented in Phase 165-03 findings):** This is a deliberate design choice. The economic value at stake per roll is small (affiliate commission split among 3 tiers in a winner-takes-all model). The PRNG provides sufficient fairness for the use case:
- Manipulation is EV-neutral (the attacker redistributes between affiliates, not between attacker and protocol)
- VRF would cost ~100K gas per affiliate payment for negligible security benefit
- The 75/20/5 distribution is already skewed heavily toward the primary affiliate

**Verdict: KNOWN TRADEOFF (not VRF, documented as acceptable design choice)**

---

### Path E: clearLevelQuest (v13.0 NEW)

**Consumer:** `DegenerusQuests.clearLevelQuest()` at line ~1784

**Entropy: NONE** -- this function sets `levelQuestType = 0`. It does not consume any entropy.

**Call site in advanceGame (line ~252):**
```solidity
if (rngWord == 1) {
    _swapAndFreeze(purchaseLevel);
    quests.clearLevelQuest();       // <-- HERE: before VRF request
    stage = STAGE_RNG_REQUESTED;
    break;
}
```

**COMMITMENT WINDOW analysis:**

`clearLevelQuest` is called when `rngGate` returns 1, meaning a VRF request was just sent (via `_requestRng` or retry). This happens BEFORE the VRF fulfillment callback. The function:

1. Zeroes `levelQuestType` -- prevents any quest progress from accumulating during the gap between VRF request and fulfillment
2. When `_handleLevelQuestProgress` reads `levelQuestType == 0`, it short-circuits for all handler types (no valid quest type matches 0)
3. When `rollLevelQuest` fires after VRF fulfillment (in a subsequent advanceGame call), it overwrites the zeroed type with a VRF-derived selection

**Ordering verification:**
- `clearLevelQuest` runs BEFORE VRF word is available (when `rngGate` returns 1)
- `rollLevelQuest` runs AFTER VRF word is consumed (in the level transition block)
- The gap between clear and roll has `levelQuestType = 0`, preventing unintended progress

**Player-controllable state:** N/A -- no entropy consumed, no VRF interaction.

**Verdict: SAFE (no entropy consumed, ordering is correct)**

---

## Section 3: Unchanged VRF Paths (Prior Audit Verdicts)

Per D-01, unchanged paths cite prior audit milestones and verdicts without re-tracing.

| Path | Prior Audit | Verdict | Notes |
|------|-------------|---------|-------|
| Coinflip win/loss (bit 0 of rngWord) | v3.7 Phase 63 VRF Request/Fulfillment Core | SAFE | `rngWord & 1` at BurnieCoinflip.sol:809. Unchanged in v11.0-v14.0. |
| Redemption roll (bits 8+) | v3.7 Phase 63 VRF Request/Fulfillment Core | SAFE | `(currentWord >> 8) % 151 + 25` at AdvanceModule.sol:846. Unchanged in v11.0-v14.0. |
| Coinflip reward percent | v3.7 Phase 63 VRF Request/Fulfillment Core | SAFE | `keccak256(rngWord, epoch) % 20` at BurnieCoinflip.sol:783-788. Unchanged. |
| Jackpot winner selection (full word) | v3.7 Phase 63 VRF Request/Fulfillment Core | SAFE | Via delegatecall to JackpotModule. Full word passed. Unchanged. |
| Lootbox RNG (stored as lootboxRngWordByIndex) | v3.7 Phase 64 Lootbox RNG Lifecycle | SAFE | Index-to-word 1:1 mapping verified. Unchanged in v11.0-v14.0. |
| Gap backfill entropy | v3.7 Phase 65 VRF Stall Edge Cases | SAFE | `keccak256(vrfWord, gapDay)` preimage uniqueness verified. Unchanged. |
| Future take variance (full word) | v3.7 Phase 63 | SAFE | `rngWord % (variance * 2 + 1)` at AdvanceModule.sol:~1033. Unchanged. |
| Prize pool consolidation (full word) | v3.7 Phase 63 | SAFE | Via delegatecall to JackpotModule. Unchanged. |
| Final day DGNRS reward (full word) | v3.7 Phase 63 | SAFE | Via delegatecall to JackpotModule. Unchanged. |
| Reward jackpots (full word) | v3.7 Phase 63 | SAFE | Via delegatecall to JackpotModule. Unchanged. |

**Bit allocation table reference** (AdvanceModule lines ~791-808):
- Bit 0: Coinflip win/loss
- Bits 8+: Redemption roll
- Full word (modular/keccak): Coinflip reward %, jackpot selection, coin jackpot, lootbox RNG, future take variance, prize pool consolidation, final day DGNRS, reward jackpots

All "full word" consumers use modular arithmetic or keccak mixing, so bit overlap with bits 0 and 8+ is not a collision concern.

---

## Section 4: Summary Table

| Path | Version | Type | Entropy Source | Commitment Window | Player-Controllable State | Verdict |
|------|---------|------|----------------|-------------------|---------------------------|---------|
| rollLevelQuest | v13.0 | NEW | keccak256(rngWordByDay[day], "LEVEL_QUEST") | VRF word unknown until callback | None (atomic execution in advanceGame) | SAFE |
| rollDailyQuest | v13.0 | MOD | rngWord (direct VRF, post-nudge) | VRF word unknown until callback | None (idempotent per day) | SAFE |
| _bonusQuestType | v13.0 | MOD | Passed from callers (VRF-derived) | Inherits caller's window | None (pure function, no state access) | SAFE |
| payAffiliate PRNG | v13.0 | MOD | keccak256(on-chain state) | N/A (not VRF) | Predictable by design (EV-neutral) | KNOWN TRADEOFF |
| clearLevelQuest | v13.0 | NEW | None consumed | N/A (no entropy) | N/A | SAFE |
| Coinflip win/loss | pre-v11.0 | UNCHANGED | rngWord & 1 | Proven in v3.7 Phase 63 | None (prior audit) | SAFE (prior) |
| Redemption roll | pre-v11.0 | UNCHANGED | (rngWord >> 8) % 151 + 25 | Proven in v3.7 Phase 63 | None (prior audit) | SAFE (prior) |
| Coinflip reward % | pre-v11.0 | UNCHANGED | keccak256(rngWord, epoch) % 20 | Proven in v3.7 Phase 63 | None (prior audit) | SAFE (prior) |
| Jackpot winner selection | pre-v11.0 | UNCHANGED | Full word via delegatecall | Proven in v3.7 Phase 63 | None (prior audit) | SAFE (prior) |
| Lootbox RNG | pre-v11.0 | UNCHANGED | lootboxRngWordByIndex | Proven in v3.7 Phase 64 | None (prior audit) | SAFE (prior) |
| Gap backfill entropy | pre-v11.0 | UNCHANGED | keccak256(vrfWord, gapDay) | Proven in v3.7 Phase 65 | None (prior audit) | SAFE (prior) |

---

## Section 5: Conclusion

**RNG-01 SATISFIED.** All new/modified VRF-consuming paths have verified commitment windows with full backward traces from consumer to VRF fulfillment callback.

**Results:**
- **5 paths traced** (3 NEW, 2 MODIFIED)
- **4 SAFE verdicts** -- VRF-derived entropy with zero player-controllable state between request and fulfillment
- **1 KNOWN TRADEOFF** -- affiliate PRNG is non-VRF by design, documented as acceptable (EV-neutral manipulation, negligible economic value at stake)
- **0 VULNERABLE verdicts**

**Key safety properties verified:**
1. `rollLevelQuest` entropy derives from `rngWordByDay[day]` via keccak256 with domain-separating tag -- VRF word unknown until callback, atomic execution within advanceGame
2. `rollDailyQuest` entropy is the direct VRF word (post-nudge) -- unknown until callback, idempotent per day
3. `_bonusQuestType` is a pure function consuming caller-provided VRF-derived entropy -- no state access, no manipulation vector
4. `clearLevelQuest` consumes no entropy -- correctly orders before VRF request to prevent stale progress
5. All unchanged VRF paths retain their prior SAFE verdicts from v3.7 Phases 63-65

**Unchanged paths:** 6 categories cited from v3.7 Phases 63-65 VRF audits, all previously proven SAFE.
