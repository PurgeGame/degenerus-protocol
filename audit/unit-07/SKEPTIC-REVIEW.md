# Unit 7: Decimator System -- Skeptic Review

**Skeptic Identity:** I am a senior Solidity security researcher who has reviewed thousands of audit findings. I know that 80% of automated findings are false positives, and I can explain exactly WHY in precise technical terms. I am the counterweight to the Mad Genius -- my job is to separate signal from noise.

**Source:** ATTACK-REPORT.md for Unit 7 (DegenerusGameDecimatorModule)

---

## Finding Review

### DEC-OFFSET-COLLISION: decBucketOffsetPacked shared between regular and terminal decimator

**Mad Genius Verdict:** INVESTIGATE -- Potential MEDIUM severity
**Mad Genius Claim:** Both `runDecimatorJackpot` (B2, L248) and `runTerminalDecimatorJackpot` (B6, L817) write to `decBucketOffsetPacked[lvl]`. If both run at the same level, the second overwrites the first's winning subbucket selections, corrupting claims for the first resolution type.

**Skeptic Analysis:**

I read the following code paths to trace whether both resolutions can occur at the same level:

1. **Regular decimator resolution** -- called from `EndgameModule.runRewardJackpots()` (L215, L231):
   - Fires at levels where `lvl % 100 == 0` (L211) or `lvl % 10 == 5 && lvl % 100 != 95` (L226).
   - Uses `decBucketBurnTotal[lvl][denom][winningSub]` for burn aggregates.
   - Writes `decBucketOffsetPacked[lvl]` at L248.
   - Writes `decClaimRounds[lvl]` at L251-253.

2. **Terminal decimator resolution** -- called from `GameOverModule.handleGameOverDrain()` (L139):
   - Fires only at GAMEOVER, using `lvl = level` (current level, L71 of GameOverModule).
   - Uses `terminalDecBucketBurnTotal[keccak256(lvl, denom, winningSub)]` for burn aggregates (DIFFERENT from regular).
   - Writes `decBucketOffsetPacked[lvl]` at L817 (SAME SLOT as regular).
   - Writes `lastTerminalDecClaimRound` at L820-822 (DIFFERENT from regular).

3. **Can both fire at the same level?**
   - Regular decimator fires during `runRewardJackpots`, which is called during the normal jackpot phase of the `advanceGame` flow.
   - GAMEOVER triggers when the death clock expires (120 days from `levelStartTime` for level > 0, or 365 days for level == 0).
   - Scenario: Level N enters jackpot phase. `runRewardJackpots` is called for level N, which calls `runDecimatorJackpot(poolWei, N, rngWord)`. This writes `decBucketOffsetPacked[N]` with regular decimator selections. Level N's jackpots complete, but before level N+1 starts, the death clock expires. `advanceGame` triggers `_handleGameOverPath` which calls `handleGameOverDrain`, which calls `runTerminalDecimatorJackpot(decPool, N, rngWord2)`. This overwrites `decBucketOffsetPacked[N]`.

   **HOWEVER**, I must check whether `runRewardJackpots` actually fires the decimator at every level:
   - Level 100: `lvl % 100 == 0` -> YES (30% pool)
   - Level 105: `lvl % 10 == 5 && lvl % 100 != 95` -> YES (10% pool)
   - Level 200: same as 100
   - But for levels like 1, 2, 3, 4, 6, 7, 8, 9, 11, ... the regular decimator does NOT fire.

   So the collision only occurs if GAMEOVER happens at a level where the regular decimator was also fired (levels ending in 0 mod 100 or 5 mod 10 except 95).

4. **Impact if collision occurs:**
   - Regular decimator claims for level N (via `claimDecimatorJackpot` -> `_consumeDecClaim` at L281) read `decBucketOffsetPacked[N]` to determine winning subbuckets. If B6 overwrote this, the winning subbucket indices are now the terminal decimator's selections (which used a DIFFERENT rngWord from GAMEOVER, L139 vs L215 rngWord).
   - Players who were winners under the regular selections may no longer be winners. Players who were losers may now appear as winners.
   - Since `decClaimRounds[N].totalBurn` and the actual burn amounts in `decBucketBurnTotal[N]` are unchanged, the pro-rata calculation would use the wrong subbucket to filter winners but the totalBurn would still reflect the old subbucket's winners. This creates an accounting mismatch: totalBurn was computed from the ORIGINAL winning subbuckets but claims now use the OVERWRITTEN subbuckets.
   - Concretely: if original winning sub for denom 5 was sub 2 (with 100 ETH burned), and terminal overwrite changes it to sub 3 (with 50 ETH burned), then: `decClaimRounds[N].totalBurn` includes 100 ETH from sub 2 players. But claim validation now checks sub 3. So sub 3 players each get `(poolWei * their_burn) / 100_ETH_totalBurn` which could be more than their fair share (since 50 < 100). Sub 2 players get nothing despite being the original winners.

5. **Is there a guard that prevents this?**
   - `runDecimatorJackpot` (B2) has a double-snapshot guard at L213: `if (decClaimRounds[lvl].poolWei != 0) return poolWei`. This prevents B2 from running twice. But it does NOT prevent B6 from overwriting B2's offsets.
   - `runTerminalDecimatorJackpot` (B6) has a double-resolution guard at L791: `if (lastTerminalDecClaimRound.lvl == lvl) return poolWei`. This prevents B6 from running twice. But it does NOT check if B2 already wrote to the same packed offsets.
   - **No guard prevents the cross-type collision.**

6. **Practical likelihood:**
   - GAMEOVER requires death clock expiry (120 days with no level advancement). This means the game is VERY stagnant -- essentially dead.
   - During stagnation, daily jackpots and level transitions still fire via `advanceGame` on the regular cadence. So it's possible that a level's regular decimator fires during one of the jackpot days, and then 120 days later (without another level transition), GAMEOVER triggers at the same level.
   - This is a realistic scenario for a dying game.

**Skeptic Verdict: CONFIRMED -- MEDIUM severity.**

The `decBucketOffsetPacked[lvl]` collision between regular and terminal decimator resolution is a real bug. At the GAMEOVER level, if regular decimator had previously resolved, the terminal resolution overwrites the winning subbucket selections. This corrupts regular decimator claims at that level: original winners can no longer claim, and non-winners may gain access to the pool with an incorrect totalBurn denominator, leading to payout miscalculation.

**Impact:** Limited to the single level where GAMEOVER occurs AND regular decimator had previously fired. Requires specific level modulo conditions (level % 100 == 0 or level % 10 == 5, except 95). Does not affect terminal decimator claims (which read from `lastTerminalDecClaimRound` for their totalBurn). Does not affect regular decimator claims at other levels.

**Recommendation:** Store terminal decimator winning subbuckets in a separate storage slot (e.g., `terminalDecBucketOffsetPacked`) instead of reusing `decBucketOffsetPacked[lvl]`. Update `_consumeTerminalDecClaim` to read from the new slot.

---

### B4 BAF Pattern (claimDecimatorJackpot futurePrizePool read-after-write)

**Mad Genius Verdict:** SAFE
**Mad Genius Claim:** The `_getFuturePrizePool()` read at L336 is a fresh storage read after all subordinate writes complete. No BAF-class stale-cache overwrite.

**Skeptic Analysis:**

I traced the exact execution flow of `claimDecimatorJackpot`:

```
L323: amountWei = _consumeDecClaim(msg.sender, lvl)  // marks claimed
L330: lootboxPortion = _creditDecJackpotClaimCore(...)
  L442: _addClaimableEth(account, ethPortion, rngWord)
    L420: _processAutoRebuy(beneficiary, weiAmount, entropy)
      L387: _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)  // WRITES futurePrizePool
L335-336: if (lootboxPortion != 0)
            _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion)  // READS then WRITES futurePrizePool
```

The critical check: is the `_getFuturePrizePool()` at L336 a fresh storage read?

- There is NO local variable in `claimDecimatorJackpot` caching futurePrizePool before the call to `_creditDecJackpotClaimCore` at L330.
- `_getFuturePrizePool()` at Storage L746-748 reads directly from `prizePoolsPacked` via `_getPrizePools()`.
- The Solidity compiler does not optimize away SLOAD operations across external/internal function calls that may have side effects.
- Therefore, the SLOAD at L336 reads the CURRENT storage value, which includes any modifications made by `_processAutoRebuy` at L387.

**However**, there is a separate concern I want to flag:

In `_setFuturePrizePool` (Storage L752-754):
```solidity
function _setFuturePrizePool(uint256 val) internal {
    (uint128 next, ) = _getPrizePools();
    _setPrizePools(next, uint128(val));
}
```

This reads `next` from `prizePoolsPacked`, then writes back `(next, future)`. If `_processAutoRebuy` at L387 called `_setFuturePrizePool` (which reads next, writes next+future), and then at L389 called `_setNextPrizePool` (which reads future, writes next+future), these two operations are sequential and each reads fresh from storage. No conflict.

Then at L336, `_setFuturePrizePool` again reads `next` from storage (which may have been modified by L389). This is correct -- it reads the latest next value.

**Skeptic Verdict: CONFIRMED SAFE.** The Mad Genius analysis is correct. The futurePrizePool read at L336 is a fresh storage read. No BAF-class stale-cache overwrite occurs in `claimDecimatorJackpot`. This function was correctly designed to avoid the BAF pattern.

---

### B1 Bucket Parameter Validation (bucket > DECIMATOR_MAX_DENOM)

**Mad Genius Verdict:** SAFE (OnlyCoin controls the bucket parameter)
**Mad Genius Claim:** A player with bucket > 12 would never win, but this is a self-harm scenario controlled by the Coin contract.

**Skeptic Analysis:**

The `recordDecBurn` function accepts `bucket` as a parameter from the Coin contract. The Coin contract is the caller (enforced by `OnlyCoin` at L136). The Coin contract controls what bucket value it passes.

If the Coin contract is correctly implemented (audited in Phase 112), it will only pass valid bucket values (2-12). This module correctly relies on its caller for input validation in this case.

**Skeptic Verdict: CONFIRMED SAFE.** Trust boundary is at the module interface; the Coin contract is responsible for valid bucket values.

---

### B2/B6 Ordering Dust (pro-rata integer division)

**Mad Genius Verdict:** SAFE (standard dust from integer division)
**Mad Genius Claim:** Sum of pro-rata shares may be less than poolWei due to truncation.

**Skeptic Analysis:**

For each winner: `amountWei = (poolWei * entryBurn) / totalBurn`.
Sum across all winners: `sum(amountWei) = sum((poolWei * burn_i) / totalBurn)`.
Due to truncation: `sum <= poolWei * sum(burn_i) / totalBurn = poolWei`.

The dust (unclaimed remainder) stays in the contract as part of claimablePool. It is not extractable by any player and does not cause insolvency.

**Skeptic Verdict: CONFIRMED SAFE.** Standard integer division dust. No economic impact.

---

### B5 Self-Call Reentrancy (playerActivityScore)

**Mad Genius Verdict:** SAFE (view function, no state changes)
**Mad Genius Claim:** The self-call to `playerActivityScore` is a view function and cannot cause reentrancy.

**Skeptic Analysis:**

`IDegenerusGame(address(this)).playerActivityScore(player)` at L718:
- Routes through the Game contract's fallback
- Dispatches to the appropriate module (likely the Game contract itself at L2415)
- `playerActivityScore` is declared as `view` in the interface (IDegenerusGame L87)
- Even though this is a CALL (not STATICCALL for view functions called via external dispatch), the dispatched module function is `view` and only reads storage
- No storage writes occur during this call
- The function is called BEFORE any storage writes in `recordTerminalDecBurn` (L718 is before L727-L764)

**Skeptic Verdict: CONFIRMED SAFE.** View function via self-call; no state changes possible; called before writes.

---

### B6 uint96 Truncation

**Mad Genius Verdict:** SAFE (unreachable in practice)
**Mad Genius Claim:** type(uint96).max is ~79,228 ETH, far exceeding realistic pool sizes.

**Skeptic Analysis:**

Terminal decimator receives 10% of `available` at GAMEOVER (GameOverModule L137: `remaining / 10`). For truncation to occur, `available` must exceed ~792,280 ETH. The entire Ethereum staking ecosystem has ~34M ETH staked. A single game contract holding 792K ETH is beyond any reasonable projection.

**Skeptic Verdict: CONFIRMED SAFE.** Unreachable in practice by orders of magnitude.

---

## Summary of Verdicts

| Finding | Mad Genius Verdict | Skeptic Verdict | Severity |
|---------|-------------------|----------------|----------|
| DEC-OFFSET-COLLISION (decBucketOffsetPacked shared between regular and terminal decimator) | INVESTIGATE | **CONFIRMED** | **MEDIUM** |
| B4 BAF Pattern (futurePrizePool read-after-write) | SAFE | CONFIRMED SAFE | N/A |
| B1 Bucket Validation | SAFE | CONFIRMED SAFE | N/A |
| B2/B6 Pro-rata Dust | SAFE | CONFIRMED SAFE | N/A |
| B5 Self-Call Reentrancy | SAFE | CONFIRMED SAFE | N/A |
| B6 uint96 Truncation | SAFE | CONFIRMED SAFE | N/A |

**Confirmed Findings: 1 (MEDIUM)**
**False Positives: 0**
**Downgraded: 0**

---

*Skeptic review completed: 2026-03-25*
*All INVESTIGATE findings have been resolved with definitive verdicts.*
