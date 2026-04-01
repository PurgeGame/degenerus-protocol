# Phase 70: Coinflip Commitment Window - Research

**Researched:** 2026-03-22
**Domain:** Solidity smart contract security audit -- coinflip RNG lifecycle and commitment window analysis
**Confidence:** HIGH

## Summary

Phase 70 is a focused security audit of the BurnieCoinflip contract's RNG lifecycle. The coinflip system is a daily 50/50 BURNIE wagering mechanism where players deposit BURNIE (burned on deposit), outcomes are determined by VRF-derived entropy during `advanceGame`, and winnings are claimed as newly minted BURNIE. The critical security question: can any player-controllable action between bet placement and resolution influence the outcome?

Phase 69 already produced SAFE verdicts for all 6 BurnieCoinflip storage variables (coinflipBalance, coinflipDayResult, playerState, currentBounty, bountyOwedTo, flipsClaimableDay) at the per-variable mutation level. Phase 70 goes deeper: it traces the complete lifecycle end-to-end, identifies ALL player-controllable state (not just VRF-touched variables), and models multi-transaction attack sequences that chain operations across the commitment window.

The architecture has a key design property: `_targetFlipDay() = currentDayView() + 1` provides temporal separation so deposits always target tomorrow's coinflip while resolution processes today's. The win/loss outcome is determined by `(rngWord & 1) == 1` (BurnieCoinflip:810) and the reward percent by `seedWord % 20` + range mapping (BurnieCoinflip:789-799). Both are pure functions of the VRF word and epoch -- no player-writable storage feeds into the outcome computation itself. The audit must verify this claim exhaustively, including edge cases (gap-day backfill, game-over fallback, auto-rebuy carry extraction, and BAF leaderboard interactions).

**Primary recommendation:** Structure the audit as (1) a complete lifecycle trace with state-transition diagram, (2) a systematic enumeration of every player-callable function on BurnieCoinflip and every game function that crosses into coinflip state, with per-function commitment window analysis, and (3) a catalog of multi-tx attack sequences with exploitation feasibility verdicts.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| COIN-01 | Full coinflip lifecycle traced: bet placement -> RNG request -> fulfillment -> roll computation -> payout, with every state transition identified | BurnieCoinflip contract (1129 lines) fully read; lifecycle spans depositCoinflip (line 225) -> advanceGame/rngGate -> processCoinflipPayouts (line 778) -> _claimCoinflipsInternal (line 400); all entry points cataloged below |
| COIN-02 | Commitment window analysis specific to coinflip: what player-controllable state exists between bet and resolution | Phase 69 verdicts cover 6 CF variables; this phase must also cover player-callable functions (claimCoinflips, setCoinflipAutoRebuy, reverseFlip) and cross-contract interactions (boon consumption, quest handling, BAF recording) |
| COIN-03 | Multi-tx attack sequences modeled: bet + manipulate + claim patterns tested against commitment window | Research identifies 5 primary attack patterns to model: (1) deposit-during-lock, (2) auto-rebuy-toggle extraction, (3) bounty-arm-during-window, (4) BAF-credit-frontrunning, (5) claim-timing manipulation |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Contract file authority:** Only read contracts from `contracts/` directory; stale copies exist elsewhere
- **No contract commits:** NEVER commit contracts/ or test/ changes without explicit user approval
- **Present and wait:** Present fix recommendations and wait for explicit approval before editing code
- **Backward trace discipline:** Every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time
- **Commitment window check:** Every RNG audit must check what player-controllable state can change between VRF request and fulfillment
- **Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins

## Standard Stack

This phase is pure audit analysis -- no new libraries or tools required.

### Core Tools
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source reading | Primary evidence source for lifecycle trace and verdicts | All claims must cite contract line numbers |
| Phase 68 inventory | Input data: 6 BurnieCoinflip variables already cataloged with slots and mutation surfaces | Canonical inventory consumed by this phase |
| Phase 69 verdicts | Input data: all 6 CF variables already received SAFE verdicts | Baseline verdicts to build upon with deeper analysis |

### Audit Methodology
| Method | Purpose | When to Use |
|--------|---------|-------------|
| Lifecycle state-transition trace | Map every storage write/read across the full bet-to-payout path | COIN-01: the end-to-end trace |
| Per-function commitment window analysis | For each player-callable function, determine what state it can modify during the window | COIN-02: systematic enumeration |
| Multi-tx attack modeling | Chain player actions across the commitment window and assess exploitation feasibility | COIN-03: attacker simulation |
| Backward trace from outcome | From win/loss determination, trace backward to all inputs and verify immutability | Memory-mandated RNG audit discipline |

## Architecture Patterns

### Coinflip Lifecycle State Machine

The coinflip follows a strict temporal lifecycle:

```
Day N: Player deposits BURNIE
  depositCoinflip() -> burnForCoinflip() -> _addDailyFlip()
  Writes to: coinflipBalance[N+1][player] (always targets TOMORROW)
  Also writes: playerState (cursor), bountyOwedTo (if record), coinflipTopByDay

Day N+1: Game resolves coinflip via advanceGame
  advanceGame() -> rngGate() -> processCoinflipPayouts(rngWord, epoch=N+1)
  Reads: rngWord (VRF-derived)
  Computes: win = (rngWord & 1) == 1
  Computes: rewardPercent = seedWord % 20 -> range mapping
  Writes: coinflipDayResult[N+1], flipsClaimableDay, currentBounty, bountyOwedTo

Day N+1+: Player claims winnings
  claimCoinflips() -> _claimCoinflipsInternal()
  Reads: coinflipDayResult[epoch], coinflipBalance[epoch][player]
  Computes: payout = stake + (stake * rewardPercent / 100) if win
  Writes: playerState (cursor), coinflipBalance (cleared)
```

### Key Temporal Separation Property

```
_targetFlipDay() = degenerusGame.currentDayView() + 1    [BurnieCoinflip:1060-1062]
currentDayView() = _simulatedDayIndex()                   [DegenerusGame:506-507]
_simulatedDayIndex() = GameTimeLib.currentDayIndex()       [DegenerusGameStorage:1262-1264]
```

Deposits always target `currentDay + 1`. Resolution processes `currentDay`. No key overlap possible because:
1. `currentDayView()` is time-derived (not a writable storage variable)
2. During daily processing, `dailyIdx` is updated only at `_unlockRng()` which runs AFTER rngGate (after all coinflip processing)
3. During mid-day window, `dailyIdx` already reflects today (prerequisite: daily RNG must be done)

### BurnieCoinflip External Entry Points (Attack Surface)

| Function | Access | rngLocked Guard | Writes To |
|----------|--------|-----------------|-----------|
| `depositCoinflip()` | permissionless | NO (but _coinflipLockedDuringTransition blocks at BAF levels) | coinflipBalance[day+1], playerState, bountyOwedTo (if record, guarded by !game.rngLocked()), coinflipTopByDay |
| `claimCoinflips()` | permissionless | NO | playerState (cursor), coinflipBalance (cleared) |
| `claimCoinflipsFromBurnie()` | onlyBurnieCoin | NO | Same as claimCoinflips |
| `claimCoinflipsForRedemption()` | onlySDGNRS | NO | Same as claimCoinflips |
| `consumeCoinflipsForBurn()` | onlyBurnieCoin | NO | Same as claimCoinflips |
| `setCoinflipAutoRebuy()` | permissionless | YES (line 706) | playerState (auto-rebuy config, carry) |
| `setCoinflipAutoRebuyTakeProfit()` | permissionless | YES (line 756) | playerState (takeProfit) |
| `settleFlipModeChange()` | onlyDegenerusGame | NO | playerState (claimableStored) |
| `creditFlip()` | onlyFlipCreditors | NO | coinflipBalance[day+1] |
| `creditFlipBatch()` | onlyFlipCreditors | NO | coinflipBalance[day+1] |
| `processCoinflipPayouts()` | onlyDegenerusGame | N/A (called from rngGate) | coinflipDayResult, currentBounty, bountyOwedTo, flipsClaimableDay, playerState (sDGNRS cursor) |

### Win/Loss Outcome Computation

The outcome is determined by exactly two values, both derived from the VRF word:

```solidity
// BurnieCoinflip:784 -- unique per-day seed
uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));

// BurnieCoinflip:810 -- 50/50 using original VRF word bit 0
bool win = (rngWord & 1) == 1;

// BurnieCoinflip:789-799 -- reward percent from seedWord
uint256 roll = seedWord % 20;
// roll 0 -> 50%, roll 1 -> 150%, else -> [78, 115]
```

No player-writable storage feeds into this computation. The inputs are `rngWord` (from VRF via _applyDailyRng which adds totalFlipReversals -- guarded by rngLockedFlag) and `epoch` (the day index, time-derived).

### VRF Word Path to Coinflip

```
rawFulfillRandomWords (VRF coordinator callback)
  -> rngWordCurrent = word                           [AdvanceModule:1451]

advanceGame (next call)
  -> rngGate()
    -> currentWord = rngWordCurrent                  [AdvanceModule:778]
    -> _applyDailyRng(day, currentWord)              [AdvanceModule:798]
      -> finalWord = rawWord + totalFlipReversals    [AdvanceModule:1524-1528]
    -> coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)  [AdvanceModule:799]
```

Note: `_applyDailyRng` returns `finalWord` and updates `rngWordCurrent`, but the value passed to `processCoinflipPayouts` at line 799 is `currentWord` which is the LOCAL variable assigned from the return of `_applyDailyRng` at line 798. This IS the nudge-applied word. The planner should verify this data flow precisely.

### Protection Mechanisms for Coinflip

Five mechanisms protect coinflip integrity:

1. **Temporal separation (day+1 keying):** Deposits target tomorrow; resolution processes today
2. **rngLockedFlag:** Blocks reverseFlip, setCoinflipAutoRebuy, setCoinflipAutoRebuyTakeProfit during daily VRF window
3. **Pure-function outcome:** win/loss and rewardPercent are pure functions of VRF word + epoch
4. **onlyDegenerusGameContract:** processCoinflipPayouts only callable by game contract during rngGate
5. **_coinflipLockedDuringTransition:** Extra guard blocking deposits at BAF resolution levels

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| State transition diagrams | Free-form narrative descriptions | Structured state machine tables with From/To/Trigger/Guard/Action columns | Ensures completeness -- every transition is documented, missing transitions are gaps |
| Attack sequence modeling | Ad-hoc "what if" reasoning | Structured attack trees with preconditions, actions, postconditions, and feasibility verdicts | Reproducible analysis; prevents missing attack chains |

## Common Pitfalls

### Pitfall 1: Confusing "Variable SAFE" with "System SAFE"
**What goes wrong:** Phase 69 proved all 6 CF variables SAFE at the individual level. An auditor might conclude "coinflip is safe" without deeper analysis. But multi-tx attack sequences can chain individually-safe operations into exploitable patterns.
**Why it happens:** The per-variable methodology from Phase 69 asks "can this variable be mutated during the window?" not "can a sequence of operations extract value?"
**How to avoid:** Phase 70 must model attack SEQUENCES, not just individual mutations. The auto-rebuy toggle is a key example: even though playerState is not an outcome input, toggling auto-rebuy OFF extracts carry value that depends on future (not-yet-resolved) flip outcomes.
**Warning signs:** Any conclusion that says "SAFE because Phase 69 said so" without independent analysis.

### Pitfall 2: Missing the Auto-Rebuy Carry Extraction Vector
**What goes wrong:** `setCoinflipAutoRebuy(false)` processes all pending claims and extracts `autoRebuyCarry` as a mint. If a player could do this after seeing the VRF word but before resolution, they could extract value on known losses.
**Why it happens:** The carry represents accumulated winnings that haven't been claimed yet -- it's a significant value store.
**How to avoid:** Verify that `setCoinflipAutoRebuy` IS guarded by `rngLockedFlag` (confirmed: line 706). But also check the mid-day window (rngLockedFlag is false) -- carry extraction during mid-day is harmless because coinflip resolution only happens during daily rngGate, not mid-day.
**Warning signs:** Unguarded carry extraction paths during any commitment window.

### Pitfall 3: Gap-Day Backfill Coinflip Resolution
**What goes wrong:** During VRF stalls, gap days are backfilled via `_backfillGapDays` which calls `processCoinflipPayouts` for each gap day. If deposits were made during the stall period targeting those gap days, they would be resolved with words derived from the first post-gap VRF word.
**Why it happens:** Gap-day words are derived as `keccak256(vrfWord, gapDay)` which is deterministic once the VRF word arrives.
**How to avoid:** Verify that deposits during the stall period targeted future days (day+1 from the time of deposit), not the gap days being backfilled. Since `_targetFlipDay()` uses the time-based `currentDayView()`, deposits during a stall would target the current real-time day+1, which is AHEAD of the gap days being backfilled (gap days are historical days the game missed). So deposits are safe.
**Warning signs:** Any scenario where `_targetFlipDay()` could return a day index that equals a gap day being backfilled.

### Pitfall 4: Game-Over Fallback Coinflip Path
**What goes wrong:** During game-over processing, `_gameOverEntropy` calls `processCoinflipPayouts` (line 868) but with a fallback word derived from historical VRF data if VRF times out (3-day timeout). If the fallback word were predictable, outcomes could be known in advance.
**Why it happens:** The fallback uses the earliest historical RNG word (`rngWordByDay[1]`), which is on-chain and readable by anyone.
**How to avoid:** Verify that at game-over, coinflip resolution with a predictable fallback word is acceptable. The game is ending -- players cannot make new deposits (game is over). The only concern is whether existing unresolved bets could be front-run, but since the fallback word is known to ALL parties equally and no new bets can be placed, the impact is limited (INFO-level at most).
**Warning signs:** Any path where a predictable RNG word resolves bets that were placed AFTER the word became predictable.

### Pitfall 5: BAF Leaderboard Credit During RNG Window
**What goes wrong:** `_claimCoinflipsInternal` records BAF leaderboard credit via `jackpots.recordBafFlip()` (line 583). This is called during `processCoinflipPayouts` for sDGNRS auto-claim (line 861). If a player could manipulate their BAF credit during the daily RNG window, they could front-run the BAF jackpot draw.
**Why it happens:** BAF credit depends on winning flip amounts, which are resolved during rngGate.
**How to avoid:** The sDGNRS path at line 861 calls `_claimCoinflipsInternal(ContractAddresses.SDGNRS, false)` which skips BAF recording (line 556: `player != ContractAddresses.SDGNRS` check). For player-initiated claims, `_coinflipLockedDuringTransition()` blocks deposits at BAF-relevant levels (every 10th level on last purchase day when rngLocked). Verify this guard covers all paths.
**Warning signs:** Any path where `recordBafFlip` executes during the daily commitment window for a player-controlled address.

## Code Examples

### Lifecycle Trace: Bet Placement
```solidity
// Source: BurnieCoinflip.sol:225-316
// depositCoinflip -> _depositCoinflip -> burnForCoinflip -> handleFlip -> _addDailyFlip
// Key: _addDailyFlip calls _targetFlipDay() which returns currentDayView()+1
// Result: coinflipBalance[day+1][player] += creditedFlip
```

### Lifecycle Trace: Resolution
```solidity
// Source: AdvanceModule:796-799 + BurnieCoinflip:778-862
// rngGate -> processCoinflipPayouts(bonusFlip, currentWord, day)
// Key: win = (rngWord & 1) == 1  [line 810]
// Key: coinflipDayResult[epoch] = CoinflipDayResult({rewardPercent, win})  [line 813-816]
// Key: flipsClaimableDay = epoch  [line 842]
```

### Lifecycle Trace: Claim
```solidity
// Source: BurnieCoinflip:400-601
// _claimCoinflipsInternal iterates cursor from lastClaim+1 to flipsClaimableDay
// Reads coinflipDayResult[cursor] for win/loss + rewardPercent
// Reads coinflipBalance[cursor][player] for stake
// Payout = stake + (stake * rewardPercent / 100) if win
// Clears coinflipBalance[cursor][player] = 0
```

### Auto-Rebuy Guard
```solidity
// Source: BurnieCoinflip:706
// _setCoinflipAutoRebuy checks:
if (degenerusGame.rngLocked()) revert RngLocked();
// This prevents toggle-off carry extraction during daily VRF window
```

### BAF Resolution Lock
```solidity
// Source: BurnieCoinflip:1000-1013
// _coinflipLockedDuringTransition returns true when:
// !inJackpotPhase && !gameOver && lastPurchaseDay && rngLocked && (level % 10 == 0)
// This blocks deposits at levels where BAF jackpot fires
```

## Specific Attack Sequences to Model

Research identifies these multi-tx patterns that COIN-03 must analyze:

### Attack 1: Deposit-During-Lock
**Sequence:** Attacker sees VRF request tx -> deposits BURNIE -> VRF fulfilled -> advanceGame
**Target state:** coinflipBalance
**Expected verdict:** SAFE -- deposits target day+1, resolution uses current day
**Verify:** _targetFlipDay() returns currentDayView()+1 during lock

### Attack 2: Auto-Rebuy Toggle Extraction
**Sequence:** Attacker sees VRF word on-chain -> toggles auto-rebuy OFF to extract carry -> avoids loss
**Target state:** playerState.autoRebuyCarry
**Expected verdict:** SAFE -- setCoinflipAutoRebuy guarded by rngLockedFlag (line 706)
**Verify:** Guard applies to both enable AND disable paths

### Attack 3: Bounty-Arm During Mid-Day Window
**Sequence:** Attacker makes record flip during mid-day (rngLocked=false) -> arms bounty -> next daily resolution pays bounty on win
**Target state:** bountyOwedTo, biggestFlipEver
**Expected verdict:** SAFE -- bounty is a side-effect recipient, not outcome input. VRF word determines win/loss, not who receives bounty.
**Verify:** bountyOwedTo does not feed into win/loss or rewardPercent computation

### Attack 4: BAF Credit Front-Running
**Sequence:** Attacker deposits large amount -> triggers auto-claim -> records BAF credit -> BAF jackpot resolves with known VRF
**Target state:** BAF leaderboard (in JackpotModule via recordBafFlip)
**Expected verdict:** SAFE -- _coinflipLockedDuringTransition blocks deposits at BAF levels
**Verify:** Guard covers the specific conditions (level % 10 == 0 AND lastPurchaseDay AND rngLocked)

### Attack 5: Claim-Timing Manipulation
**Sequence:** Player has unresolved days -> sees VRF word -> selectively claims before/after resolution to optimize
**Target state:** playerState.lastClaim, playerState.claimableStored
**Expected verdict:** SAFE -- claiming does not affect win/loss outcomes; a player cannot selectively "skip" losses because the claim window iterates sequentially from lastClaim+1 to flipsClaimableDay
**Verify:** _claimCoinflipsInternal processes ALL days in sequence, no selective skip possible

### Attack 6: Cross-Contract Boon Consumption
**Sequence:** Player deposits coinflip to consume boon during VRF window, affecting stake size for tomorrow's flip
**Target state:** boonPacked (DegenerusGameStorage slot 107)
**Expected verdict:** SAFE -- boon affects TOMORROW's stake (day+1 keying), not the day being resolved
**Verify:** consumeCoinflipBoon is called within _addDailyFlip which writes to _targetFlipDay()

### Attack 7: Game-Over Predictable Fallback
**Sequence:** Game over pending -> VRF stalls -> 3-day timeout -> fallback word from rngWordByDay[1] used -> outcomes predictable
**Target state:** coinflipBalance for the game-over day
**Expected verdict:** Needs analysis -- if gameOver is true, can new deposits still target the game-over day? Check whether depositCoinflip is blocked during game-over.
**Verify:** Whether game-over blocks deposits and whether the fallback word path in _gameOverEntropy resolves existing bets fairly

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Phase 69: per-variable SAFE/VULNERABLE | Phase 70: per-function + multi-tx attack modeling | This phase | Deeper coverage: system-level safety, not just variable-level |
| Forward-only trace | Backward + forward trace (memory-mandated) | v3.8 methodology | Catches bypass paths where data reaches RNG consumer without passing through VRF request flow |

## Open Questions

1. **Game-over deposit blocking**
   - What we know: `_coinflipLockedDuringTransition` checks `!gameOver`, but this is in the LOCK direction (returns false when game is over, meaning deposits are NOT blocked by this function during game-over)
   - What's unclear: Is there a separate game-over guard on depositCoinflip? If not, can a player deposit AFTER game-over is triggered but before the final day is resolved with a predictable fallback word?
   - Recommendation: Trace depositCoinflip -> _depositCoinflip -> _addDailyFlip -> _targetFlipDay during game-over conditions. Check if advanceGame/gameover processing blocks deposits.

2. **Nudge (reverseFlip) impact on coinflip fairness**
   - What we know: reverseFlip adds 1 to totalFlipReversals, which is added to the VRF word in _applyDailyRng. This changes bit 0 (used for win/loss). One nudge flips the outcome.
   - What's unclear: Is this documented as intended? Each nudge costs escalating BURNIE (100 base, +50% compound). Odd nudge count flips the outcome; even nudge count preserves it.
   - Recommendation: Document the nudge economics and note that each individual nudge flips the outcome. This is likely by design (the feature is called "reverseFlip") but should be explicitly noted as a mechanism for collective outcome influence (not per-player -- affects all coinflip participants equally).

3. **sDGNRS auto-claim during processCoinflipPayouts**
   - What we know: processCoinflipPayouts calls `_claimCoinflipsInternal(ContractAddresses.SDGNRS, false)` at line 861. This processes sDGNRS coinflip claims during daily resolution.
   - What's unclear: Can this internal claim interact with concurrent player claims in a way that creates issues? Since sDGNRS is a contract address (not a player), the risk is likely minimal.
   - Recommendation: Verify that sDGNRS BAF exclusion (line 556) prevents any rngLocked revert during processCoinflipPayouts.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat (hardhat test) |
| Config file | foundry.toml + hardhat.config.js |
| Quick run command | `forge test --match-path test/fuzz/VRFCore.t.sol -vv` |
| Full suite command | `forge test -vv` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COIN-01 | Full coinflip lifecycle trace with state transitions | manual-only (audit doc, not code) | N/A -- audit document output | N/A |
| COIN-02 | All player-controllable state identified with verdicts | manual-only (audit doc, not code) | N/A -- audit document output | N/A |
| COIN-03 | Multi-tx attack sequences modeled with verdicts | manual-only (audit doc, not code) | N/A -- audit document output | N/A |

**Justification for manual-only:** This phase produces audit documentation (security analysis), not code changes. The deliverable is a structured security report appended to the existing audit document. There are no code entry points to test. Contract-level spot-checks (line references, function signatures, guard conditions) are verified by reading source directly.

### Sampling Rate
- **Per task commit:** Verify line references against contract source
- **Per wave merge:** N/A (single document output)
- **Phase gate:** All 3 success criteria met before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing Foundry test infrastructure covers contract behavior. This phase adds audit analysis documentation, not test code.

## Output Document Structure

The audit deliverable should extend `audit/v3.8-commitment-window-inventory.md` (append new section), maintaining the single-source-of-truth pattern from Phases 68-69. The appended section should contain:

### Section 1: Coinflip Lifecycle Trace (COIN-01)
- State transition table: From/To/Trigger/Guard/Storage-Writes
- 4 code paths: normal daily, gap-day backfill, game-over, game-over fallback
- Backward trace from win/loss outcome to all inputs

### Section 2: Commitment Window Analysis (COIN-02)
- Per-function table for all 10 external BurnieCoinflip entry points
- For each: what it writes, what guards it, whether writes can influence outcomes
- Cross-contract interactions (boon consumption, quest handling, BAF recording)

### Section 3: Multi-TX Attack Sequences (COIN-03)
- 7+ attack sequences from the research catalog above
- Per-sequence: preconditions, action steps, postconditions, verdict, feasibility
- Summary table with C4A severity rating per finding

## Sources

### Primary (HIGH confidence)
- `contracts/BurnieCoinflip.sol` (1129 lines) -- complete contract source, all functions traced
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- rngGate, _applyDailyRng, rawFulfillRandomWords, _backfillGapDays, _gameOverEntropy, reverseFlip
- `contracts/DegenerusGame.sol` -- currentDayView, consumeCoinflipBoon
- `contracts/storage/DegenerusGameStorage.sol` -- _simulatedDayIndex, slot layout
- `audit/v3.8-commitment-window-inventory.md` -- Phase 68-69 inventory and verdicts

### Secondary (MEDIUM confidence)
- Phase 68 verification report (68-VERIFICATION.md) -- confirmed all line references
- Phase 69 verification report (69-VERIFICATION.md) -- confirmed all 55 SAFE verdicts

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- pure audit analysis, no libraries needed, methodology proven in Phases 68-69
- Architecture: HIGH -- complete BurnieCoinflip contract read, all entry points cataloged, lifecycle traced
- Pitfalls: HIGH -- directly derived from contract code analysis with specific line references

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- contract code is frozen for audit)
