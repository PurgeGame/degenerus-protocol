# ADVR-02 Findings: Brick advanceGame

**Warden:** "Game Breaker" (griefing specialist persona)
**Brief:** Prove advanceGame() can be permanently bricked
**Scope:** DegenerusGameAdvanceModule, VRF lifecycle, JackpotModule, EndgameModule
**Information:** Source code + architecture docs (no prior findings)
**Session Date:** 2026-03-05

## Summary

**Result: No Medium+ findings discovered.**

After systematically enumerating all revert paths in advanceGame() and all recovery mechanisms, no permanent bricking state was found. Every revert condition is either (a) transient and self-resolving, (b) recoverable via timeout/rotation, or (c) leads to a graceful game-over state which is an intentional design outcome.

## Methodology

1. Enumerated every revert condition in DegenerusGameAdvanceModule.advanceGame()
2. For each revert: analyzed whether it can become permanent
3. Tested all 4 recovery mechanisms for completeness
4. Analyzed gas exhaustion scenarios
5. Checked delegatecall sub-module failure modes

## Revert Path Analysis

### Path 1: MustMintToday() (AdvanceModule.sol, _enforceDailyMintGate)

**Condition:** Caller must have minted today (ETH mint on current purchase level). CREATOR bypasses this gate.

**Can this brick?** NO.
- CREATOR address (ContractAddresses.CREATOR) always bypasses the daily mint gate
- CREATOR is a compile-time constant -- cannot be changed or zeroed
- Even if all players stop minting, CREATOR can call advanceGame()
- **Defense:** AdvanceModule `_enforceDailyMintGate()` has `if (caller == ContractAddresses.CREATOR) return;` bypass

### Path 2: NotTimeYet() (AdvanceModule.sol:136)

**Condition:** `if (day == dailyIdx) revert NotTimeYet()`

**Can this brick?** NO.
- This reverts if advanceGame is called on the same day it was last processed
- Time always advances (block.timestamp increases monotonically)
- After 24 hours, `day > dailyIdx` and the check passes
- **Defense:** Physical time progression. Not attacker-controllable.

### Path 3: RNG Lifecycle (rngGate)

**Condition:** rngGate returns 1 (VRF request sent, waiting for fulfillment)

**Can this brick?** NO, due to 3-layer recovery:

**Layer 1: 18h VRF timeout**
- If VRF not fulfilled within 18 hours, rngGate allows retry with new request
- Chainlink refunds LINK for unfulfilled requests
- New request uses same subscription, may succeed

**Layer 2: 3-day coordinator rotation**
- If VRF stalls for 3+ days: `updateVrfCoordinatorAndSub()` available to ADMIN
- ADMIN can point to a new VRF coordinator (different oracle, different gas lane)
- **Code:** AdvanceModule.sol:304-310 -- wireVrf can be re-called (no one-time restriction after 3-day stall via updateVrfCoordinatorAndSub)

**Layer 3: Game-over fallback**
- AdvanceModule `_gameOverEntropy()` provides fallback RNG after 3 days
- Uses `rngWordByDay` from previous fulfillment or blockhash-derived entropy
- Even without VRF, game-over path can acquire entropy

**But what about VRF coordinator griefing?**
- Attacker controls the VRF coordinator (compromised operator)
- Coordinator accepts requests but never fulfills
- After 18h: retry (still no fulfillment)
- After 3 days: ADMIN rotates to new coordinator
- **Defense:** Coordinator rotation is the ultimate escape hatch

**What if ADMIN is compromised?**
- ADMIN refuses to rotate coordinator
- After 912 days (level 0) or 365 days (level 1+): liveness guard triggers game-over
- Game-over uses `_gameOverEntropy()` which has blockhash fallback
- **Defense:** Liveness guards do NOT require VRF -- they have independent RNG fallback

### Path 4: Gas Exhaustion in processTicketBatch

**Condition:** Ticket batch processing loop uses too much gas

**Can this brick?** NO.
- `WRITES_BUDGET_SAFE = 550` limits SSTORE operations per call
- Each advanceGame call processes at most 550 ticket writes
- Even with millions of queued tickets, processing completes over multiple calls
- **Defense:** AdvanceModule uses `_runProcessTicketBatch()` with bounded writes budget. JackpotModule.sol `processTicketBatch()` decrements writes budget and returns when exhausted.

**What if the queue is enormous?**
- Attacker queues millions of tickets via whale bundles (100 levels * 100 quantity * 40 tickets = 400k tickets per whale bundle)
- Each ticket queue entry costs 2.4-4 ETH per whale bundle -- prohibitively expensive to create millions
- processTicketBatch cursor advances monotonically -- never resets, never retries
- **Defense:** Economic cost of attack >> cost of processing delay. Processing always makes forward progress.

### Path 5: Jackpot Module payDailyJackpot Permanent Revert

**Condition:** JackpotModule.payDailyJackpot reverts on every call

**Can this brick?** NO.
- payDailyJackpot has chunked processing (dailyEthPhase, dailyEthBucketCursor, dailyEthWinnerCursor)
- Each chunk processes a bounded number of winners
- If no tickets exist at a level: bucket counts are 0, distribution completes instantly
- If an individual winner credit fails: the credit uses `_creditClaimable()` which is an SSTORE -- cannot revert on valid addresses
- **Defense:** Chunked processing ensures bounded gas. No external calls during distribution (pull pattern).

### Path 6: EndgameModule runRewardJackpots Permanent Revert

**Condition:** Reward jackpot processing (BAF/Decimator) reverts

**Can this brick?** NO.
- runRewardJackpots is called via delegatecall from AdvanceModule
- BAF calls `jackpots.runBafJackpot()` which is an external call to DegenerusJackpots
- If DegenerusJackpots is bricked: delegatecall failure bubbles up
- BUT: runRewardJackpots is only called at level transitions (every 10/100 levels)
- If it reverts: advanceGame reverts, but the game is in jackpot phase
- Next call to advanceGame goes through the same path
- **Can ADMIN fix?** No direct admin intervention for this path
- **BUT:** After 365 days of no progress: liveness guard triggers game-over
- **Defense:** Liveness guard is the ultimate recovery -- independent of jackpot processing

### Path 7: Storage State Creating Impossible Conditions

**Condition:** Storage variables reach a state that makes all paths revert

**Can this brick?** Analyzed all critical state variables:

- `jackpotCounter`: uint8, incremented in bounded loop (0-5). Reset to 0 at _endPhase(). Cannot overflow with 0.8.x checked arithmetic.
- `level`: uint24, max 16,777,215. Incremented once per level transition. No overflow concern for practical game lifetime.
- `jackpotPhaseFlag`: bool. Only set by advanceGame flow. Always toggles correctly.
- `phaseTransitionActive`: bool. Set to true at _endPhase(), set to false when transition completes.
- `rngLockedFlag`: bool. Set in _requestRng(), cleared in _unlockRng(). 18h timeout allows clearing even without fulfillment.
- `dailyIdx`: uint48. Updated to current day index. Monotonically advances.

**Defense:** All state transitions are well-ordered. Solidity 0.8.x overflow protection prevents arithmetic corruption.

### Path 8: ADMIN Key Compromise -- Malicious Admin

**Condition:** ADMIN calls malicious functions to brick the game

**Can ADMIN brick advanceGame directly?** NO.
- ADMIN can call: wireVrf, updateVrfCoordinatorAndSub, setLootboxRngThreshold, adminSwapEthForStEth, adminStakeEthForStEth
- wireVrf: sets VRF coordinator/subscription. If set to address(0), VRF requests fail -> 18h timeout -> retry
- updateVrfCoordinatorAndSub: requires 3-day stall condition. Same as wireVrf.
- setLootboxRngThreshold: affects lootbox RNG only, not game advance RNG
- adminSwapEthForStEth: value-neutral, doesn't affect state machine
- adminStakeEthForStEth: converts ETH to stETH, doesn't affect state machine

**Worst case:** ADMIN sets coordinator to address(0) -> all VRF requests fail -> 18h timeout allows retry -> 3-day stall allows rotation -> BUT ADMIN refuses to rotate -> 365-day liveness guard triggers game-over.

**Defense:** ADMIN cannot prevent liveness guard from firing. After 365 days without level advancement, game enters terminal state regardless of VRF status.

### Path 9: Batch Processing Cursor Infinite Loop

**Condition:** processTicketBatch cursor state creates infinite retry

**Can this brick?** NO.
- Batch cursor `ticketBatchCursor` advances by the number of tickets processed
- Each call processes up to WRITES_BUDGET_SAFE (550) entries
- Cursor is compared against `ticketQueue[level].length` which is append-only
- When cursor reaches queue length: batch is done
- Cursor cannot go backward or wrap around (uint256)
- **Defense:** Monotonic cursor advancement. O(n) completion guarantee.

## Recovery Mechanism Verification

| Mechanism | Trigger Condition | Verified? | Evidence |
|-----------|-------------------|-----------|----------|
| 18h VRF timeout | `block.timestamp - rngRequestTime > 18 hours` | YES | AdvanceModule rngGate checks timestamp and allows new request |
| 3-day coordinator rotation | `block.timestamp - rngRequestTime > 3 days` | YES | updateVrfCoordinatorAndSub checks 3-day gap |
| 912-day deploy timeout | Level 0 + `ts - levelStartTime > 912 days` | YES | AdvanceModule._handleGameOverPath line 328 |
| 365-day inactivity guard | Level 1+ + `ts - 365 days > levelStartTime` | YES | AdvanceModule._handleGameOverPath line 329 |

## Conclusion

advanceGame() cannot be permanently bricked. The defense-in-depth architecture provides 4 independent recovery layers:

1. **Time-based retry** (18h): Resolves VRF fulfillment delays
2. **Coordinator rotation** (3 days): Resolves VRF coordinator failures
3. **Liveness guards** (365/912 days): Resolves complete game abandonment
4. **CREATOR bypass**: Ensures at least one address can always call advanceGame

The liveness guard is the ultimate backstop -- it operates independently of VRF, ADMIN, and all other external dependencies. It triggers game-over, which is a graceful termination (remaining funds distributed to ticket holders and claimable balances preserved).

The only "bricking" that occurs is an intentional design outcome: game-over is a terminal state by design, not a failure mode.
