# Unit 7: Decimator System -- Mad Genius Attack Report

**Attacker Identity:** I am the most dangerous smart contract attacker alive. I have 1,000 ETH, unlimited patience, and the source code. I think in call chains, not individual functions. I have seen every class of Solidity exploit and I invent new ones.

**Target:** DegenerusGameDecimatorModule.sol (930 lines) + inherited DegenerusGamePayoutUtils.sol (92 lines)

**Priority:** Auto-rebuy BAF-pattern chains first (Tier 1), then Tier 2, then Tier 3.

---

## B4: claimDecimatorJackpot(uint24 lvl) -- Lines 316-338 [TIER 1, BAF-CRITICAL]

### Call Tree

```
claimDecimatorJackpot(lvl)                              L316
  |-- if (prizePoolFrozen) revert E()                    L321
  |-- amountWei = _consumeDecClaim(msg.sender, lvl)      L323
  |   |-- round = decClaimRounds[lvl]                    L274
  |   |-- if (round.poolWei == 0) revert DecClaimInactive L275
  |   |-- e = decBurn[lvl][msg.sender]                   L277
  |   |-- if (e.claimed != 0) revert DecAlreadyClaimed   L278
  |   |-- packedOffsets = decBucketOffsetPacked[lvl]      L281
  |   |-- totalBurn = uint256(round.totalBurn)            L282
  |   |-- amountWei = _decClaimableFromEntry(...)         L283-288
  |   |   |-- if (totalBurn == 0) return 0                L528
  |   |   |-- denom = e.bucket; sub = e.subBucket         L530-531
  |   |   |-- if (denom == 0 || entryBurn == 0) return 0  L535
  |   |   |-- winningSub = _unpackDecWinningSubbucket(p,d) L538
  |   |   |   |-- if (denom < 2) return 0                 L511
  |   |   |   |-- shift = (denom - 2) << 2                L512
  |   |   |   |-- return uint8((packed >> shift) & 0xF)    L513
  |   |   |-- if (sub != winningSub) return 0              L539
  |   |   |-- amountWei = (poolWei * entryBurn) / totalBurn L542
  |   |-- if (amountWei == 0) revert DecNotWinner          L289
  |   |-- e.claimed = 1                                    L292  *** WRITE: decBurn[lvl][player].claimed ***
  |
  |-- [BRANCH: gameOver == true]
  |   |-- _addClaimableEth(msg.sender, amountWei, rngWord) L326
  |   |   |-- if (weiAmount == 0) return                   L419
  |   |   |-- _processAutoRebuy(beneficiary, weiAmount, entropy) L420
  |   |   |   |-- if (gameOver) return false               L367  <-- returns false, skips auto-rebuy
  |   |   |-- _creditClaimable(msg.sender, amountWei)      L423
  |   |       |-- claimableWinnings[beneficiary] += weiAmount L33  *** WRITE: claimableWinnings ***
  |   |-- return                                           L327
  |
  |-- [BRANCH: gameOver == false, normal path]
  |-- lootboxPortion = _creditDecJackpotClaimCore(...)     L330-334
  |   |-- ethPortion = amount >> 1                         L439
  |   |-- lootboxPortion = amount - ethPortion             L440
  |   |-- _addClaimableEth(account, ethPortion, rngWord)   L442
  |   |   |-- if (weiAmount == 0) return                   L419
  |   |   |-- _processAutoRebuy(beneficiary, weiAmount, entropy) L420
  |   |   |   |-- if (gameOver) return false               L367
  |   |   |   |-- state = autoRebuyState[beneficiary]      L368  *** READ: autoRebuyState ***
  |   |   |   |-- if (!state.autoRebuyEnabled) return false L369
  |   |   |   |-- if (decimatorAutoRebuyDisabled[b]) ret false L370 *** READ: decimatorAutoRebuyDisabled ***
  |   |   |   |-- calc = _calcAutoRebuy(...)               L372-380 (pure)
  |   |   |   |   |-- Computes: reserved, rebuyAmount, targetLevel, ticketCount, ethSpent
  |   |   |   |   |-- EntropyLib.entropyStep for level offset (1-4 ahead)
  |   |   |   |   |-- PriceLookupLib.priceForLevel for ticket price
  |   |   |   |-- if (!calc.hasTickets)                    L381
  |   |   |   |   |-- _creditClaimable(beneficiary, weiAmount) L382 *** WRITE: claimableWinnings ***
  |   |   |   |   |-- return true
  |   |   |   |-- [BRANCH: calc.toFuture == true]
  |   |   |   |   |-- _setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent) L387 *** WRITE: prizePoolsPacked (future) ***
  |   |   |   |-- [BRANCH: calc.toFuture == false]
  |   |   |   |   |-- _setNextPrizePool(_getNextPrizePool() + calc.ethSpent) L389 *** WRITE: prizePoolsPacked (next) ***
  |   |   |   |-- _queueTickets(beneficiary, calc.targetLevel, calc.ticketCount) L391
  |   |   |   |   |-- ticketQueue[wk].push(buyer)         *** WRITE: ticketQueue ***
  |   |   |   |   |-- ticketsOwedPacked[wk][buyer] = ...  *** WRITE: ticketsOwedPacked ***
  |   |   |   |-- if (calc.reserved != 0)
  |   |   |   |   |-- _creditClaimable(beneficiary, calc.reserved) L394 *** WRITE: claimableWinnings ***
  |   |   |   |-- claimablePool -= calc.ethSpent           L398 *** WRITE: claimablePool ***
  |   |   |   |-- emit AutoRebuyProcessed(...)             L400
  |   |   |   |-- return true
  |   |   |-- [fallback: auto-rebuy disabled/not triggered]
  |   |   |-- _creditClaimable(beneficiary, ethPortion)    L423 *** WRITE: claimableWinnings ***
  |   |-- claimablePool -= lootboxPortion                  L445 *** WRITE: claimablePool ***
  |   |-- _awardDecimatorLootbox(account, lootboxPortion, rngWord) L446
  |       |-- if (winner == address(0) || amount == 0) return L632
  |       |-- [BRANCH: amount > LOOTBOX_CLAIM_THRESHOLD]
  |       |   |-- _queueWhalePassClaimCore(winner, amount)  L634
  |       |       |-- fullHalfPasses = amount / HALF_WHALE_PASS_PRICE L78
  |       |       |-- remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE) L79
  |       |       |-- if (fullHalfPasses != 0)
  |       |       |   |-- whalePassClaims[winner] += fullHalfPasses L82 *** WRITE: whalePassClaims ***
  |       |       |-- if (remainder != 0)
  |       |           |-- claimableWinnings[winner] += remainder L86 *** WRITE: claimableWinnings ***
  |       |           |-- claimablePool += remainder        L88 *** WRITE: claimablePool ***
  |       |-- [BRANCH: amount <= LOOTBOX_CLAIM_THRESHOLD]
  |           |-- delegatecall GAME_LOOTBOX_MODULE.resolveLootboxDirect L638-650
  |           |-- if (!ok) _revertDelegate(data)            L650
  |
  |-- if (lootboxPortion != 0)                             L335
  |   |-- _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion) L336 *** READ + WRITE: prizePoolsPacked (future) ***
```

### Storage Writes (Full Tree)

| Variable | Written At | Written By |
|----------|-----------|------------|
| `decBurn[lvl][player].claimed` | L292 | C1 (_consumeDecClaim) |
| `claimableWinnings[beneficiary]` | L33 (PayoutUtils) | C9 (_creditClaimable) -- multiple paths |
| `prizePoolsPacked` (futurePrizePool) | L387, L336 | C2 (_processAutoRebuy), B4 (lootbox portion) |
| `prizePoolsPacked` (nextPrizePool) | L389 | C2 (_processAutoRebuy) |
| `ticketQueue[wk]` | Storage L542 | C12 (_queueTickets) |
| `ticketsOwedPacked[wk][buyer]` | Storage L547 | C12 (_queueTickets) |
| `claimablePool` | L398, L445, L88 | C2 (decrement), C4 (decrement), C11 (increment) |
| `whalePassClaims[winner]` | L82 (PayoutUtils) | C11 (_queueWhalePassClaimCore) |
| (LootboxModule delegatecall) | Various | resolveLootboxDirect -- runs in Game's storage |

### Cached-Local-vs-Storage Check

**THE BAF PATTERN CHECK -- This is the #1 priority for this entire audit unit.**

**Question:** Does any ancestor cache a value in a local variable that a descendant subsequently writes to storage?

**Analysis of L336 (_setFuturePrizePool read-after-write):**

```solidity
// L330-334: _creditDecJackpotClaimCore returns lootboxPortion
uint256 lootboxPortion = _creditDecJackpotClaimCore(msg.sender, amountWei, decClaimRounds[lvl].rngWord);
// L335-337: add lootboxPortion to futurePrizePool
if (lootboxPortion != 0) {
    _setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);
}
```

Inside `_creditDecJackpotClaimCore` (L433-447):
```solidity
function _creditDecJackpotClaimCore(...) private returns (uint256 lootboxPortion) {
    uint256 ethPortion = amount >> 1;
    lootboxPortion = amount - ethPortion;
    _addClaimableEth(account, ethPortion, rngWord);   // L442 -- may write futurePrizePool
    claimablePool -= lootboxPortion;                    // L445
    _awardDecimatorLootbox(account, lootboxPortion, rngWord); // L446
}
```

**The chain:** `_addClaimableEth` -> `_processAutoRebuy` -> `_setFuturePrizePool(_getFuturePrizePool() + calc.ethSpent)` at L387.

**After `_creditDecJackpotClaimCore` returns to L335-336:**
- `_getFuturePrizePool()` at L336 reads directly from `prizePoolsPacked` storage (via `_getPrizePools()` at Storage L746-748).
- There is NO local variable caching futurePrizePool before the `_creditDecJackpotClaimCore` call.
- The read at L336 is a FRESH storage read that will pick up any modifications made by the subordinate auto-rebuy path.

**VERDICT: SAFE.** The futurePrizePool read at L336 is NOT cached before the subordinate call. It reads fresh from storage after auto-rebuy may have modified it. No BAF-class stale-cache overwrite occurs.

**Analysis of claimablePool accounting:**

`claimablePool` is decremented at two points:
1. L398 (inside _processAutoRebuy): `claimablePool -= calc.ethSpent` -- converts ETH from claimable to ticket purchase
2. L445 (inside _creditDecJackpotClaimCore): `claimablePool -= lootboxPortion` -- removes lootbox portion from claimable

Neither of these has a cached local. The decrements are direct storage operations.

However, `claimablePool` can also be INCREMENTED at L88 (PayoutUtils) if `_queueWhalePassClaimCore` has a remainder. This increment follows the decrement at L445, meaning the net accounting is: pool -= lootboxPortion, then pool += remainder-from-whale-pass. These are sequential, not competing, writes.

**VERDICT: SAFE.** No cached-local-vs-storage conflict on claimablePool.

### Attack Analysis

**1. State Coherence (BAF Pattern)**
- **VERDICT: SAFE.** Analyzed above. No local variable caches futurePrizePool, nextPrizePool, or claimablePool before subordinate calls that write to them. The _getFuturePrizePool() at L336 is a fresh storage read after all subordinate writes complete.

**2. Access Control**
- `claimDecimatorJackpot` is callable by anyone (no msg.sender restriction beyond prizePoolFrozen guard at L321).
- This is intentional: players claim their own jackpot. The `_consumeDecClaim` validates that msg.sender is a winner and hasn't already claimed.
- **VERDICT: SAFE.** Player-callable by design; eligibility enforced by _consumeDecClaim.

**3. RNG Manipulation**
- The rngWord used for auto-rebuy level selection comes from `decClaimRounds[lvl].rngWord`, which was stored at resolution time (L253) from a VRF-provided word.
- Player cannot influence this word after resolution. The claim timing does not affect the rngWord.
- The rngWord is also passed to `_awardDecimatorLootbox` for lootbox resolution.
- **VERDICT: SAFE.** RNG word is VRF-derived and immutable once stored.

**4. Cross-Contract State Desync**
- The delegatecall to `LootboxModule.resolveLootboxDirect` at L638-650 runs in Game's storage context. Any storage writes by the lootbox resolution affect the same storage as the calling function.
- After the delegatecall returns, the only remaining write is `_setFuturePrizePool` at L336, which is a fresh read.
- **VERDICT: SAFE.** Delegatecall shares storage context; no desync possible.

**5. Edge Cases**
- **amountWei == 0:** Cannot happen. `_consumeDecClaim` reverts with `DecNotWinner` if amountWei == 0 (L289).
- **ethPortion == 0:** If amountWei == 1, ethPortion = 0 (1 >> 1 = 0). `_addClaimableEth` returns early (L419 check). lootboxPortion = 1 wei. This is functionally correct but 1 wei is trivial.
- **lootboxPortion > LOOTBOX_CLAIM_THRESHOLD:** Routes to whale pass claims instead of lootbox resolution. This is a valid path.
- **VERDICT: SAFE.** Edge cases handled correctly.

**6. Conditional Paths**
- **gameOver path (L325-328):** Routes to `_addClaimableEth` directly, which skips auto-rebuy when gameOver. No lootbox split. The full amountWei is credited as claimable ETH. This is correct behavior for post-game claims.
- **auto-rebuy disabled (L369-370):** Falls through to `_creditClaimable`. ETH goes to claimableWinnings.
- **auto-rebuy enabled but no tickets (L381-383):** Full weiAmount credited to claimable. This happens when ticket price is 0 or baseTickets is 0.
- **VERDICT: SAFE.** All conditional paths produce valid outcomes.

**7. Economic Attacks**
- A player cannot influence which subbucket wins (VRF-determined). A player cannot change their subbucket after registration (deterministic from hash).
- A player could front-run another player's claim to change some global state, but the claim calculation (pro-rata share) is based on immutable snapshot data (poolWei, totalBurn stored at resolution time).
- **VERDICT: SAFE.** Pro-rata is calculated from immutable snapshot.

**8. Griefing**
- No griefing vector. Claims are per-player, idempotent (claimed flag), and do not affect other players' shares.
- **VERDICT: SAFE.**

**9. Ordering/Sequencing**
- Claims can be made in any order. Each is independent because the pro-rata share is computed from the snapshot, not from remaining pool.
- **INVESTIGATE:** If ALL winners claim, does the sum of pro-rata shares exactly equal poolWei? Due to integer division truncation, sum of `(poolWei * burn_i) / totalBurn` across all winners may be less than poolWei. The dust (remainder) stays in the contract. This is not extractable and is economically negligible.
- **VERDICT: SAFE.** Dust from integer division is standard and expected.

**10. Silent Failures**
- If `_awardDecimatorLootbox` delegatecall fails, `_revertDelegate` propagates the revert. No silent failure.
- If `_processAutoRebuy` returns false (disabled), the fallback `_creditClaimable` handles it. No silent skip.
- **VERDICT: SAFE.**

---

## B1: recordDecBurn(address,uint24,uint8,uint256,uint256) -- Lines 129-188 [TIER 2]

### Call Tree

```
recordDecBurn(player, lvl, bucket, baseAmount, multBps)    L129
  |-- if (msg.sender != COIN) revert OnlyCoin()             L136
  |-- e = decBurn[lvl][player]                               L138  *** READ: decBurn ***
  |-- m = e (memory copy)                                     L139
  |-- prevBurn = m.burn                                        L140
  |
  |-- [BRANCH: m.bucket == 0 (first burn)]
  |   |-- m.bucket = bucket                                    L144
  |   |-- m.subBucket = _decSubbucketFor(player, lvl, bucket)  L145
  |       |-- keccak256(player, lvl, bucket) % bucket           L618  (pure)
  |
  |-- [BRANCH: bucket != 0 && bucket < m.bucket (improvement)]
  |   |-- _decRemoveSubbucket(lvl, m.bucket, m.subBucket, prevBurn) L148
  |   |   |-- slotTotal = decBucketBurnTotal[lvl][denom][sub]   L599
  |   |   |-- if (slotTotal < delta) revert E()                 L600
  |   |   |-- decBucketBurnTotal[lvl][denom][sub] = slotTotal - delta L601 *** WRITE ***
  |   |-- m.bucket = bucket                                     L149
  |   |-- m.subBucket = _decSubbucketFor(player, lvl, bucket)   L150
  |   |-- if (prevBurn != 0)                                    L152
  |       |-- _decUpdateSubbucket(lvl, m.bucket, m.subBucket, prevBurn) L153
  |           |-- decBucketBurnTotal[lvl][denom][sub] += delta   L584 *** WRITE ***
  |
  |-- bucketUsed = m.bucket                                     L157
  |-- effectiveAmount = _decEffectiveAmount(prevBurn, baseAmount, multBps) L159-163
  |   |-- (pure arithmetic, multiplier cap logic)               L454-473
  |
  |-- updated = prevBurn + effectiveAmount                      L166
  |-- if (updated > type(uint192).max) updated = type(uint192).max L167
  |-- newBurn = uint192(updated)                                L168
  |-- e.burn = newBurn                                          L169 *** WRITE: decBurn[lvl][player].burn ***
  |-- e.bucket = m.bucket                                       L170 *** WRITE: decBurn[lvl][player].bucket ***
  |-- e.subBucket = m.subBucket                                 L171 *** WRITE: decBurn[lvl][player].subBucket ***
  |
  |-- delta = newBurn - prevBurn                                L174
  |-- if (delta != 0)                                           L175
  |   |-- _decUpdateSubbucket(lvl, bucketUsed, m.subBucket, delta) L176
  |   |   |-- decBucketBurnTotal[lvl][denom][sub] += delta       L584 *** WRITE ***
  |   |-- emit DecBurnRecorded(...)                              L177-185
  |
  |-- return bucketUsed                                         L187
```

### Storage Writes (Full Tree)

| Variable | Written At | Condition |
|----------|-----------|-----------|
| `decBucketBurnTotal[lvl][old_denom][old_sub]` | L601 | Bucket migration (improvement) |
| `decBucketBurnTotal[lvl][new_denom][new_sub]` | L584 | Bucket migration (carry burn to new bucket) |
| `decBurn[lvl][player].burn` | L169 | Always |
| `decBurn[lvl][player].bucket` | L170 | Always (may be unchanged) |
| `decBurn[lvl][player].subBucket` | L171 | Always (may be unchanged) |
| `decBucketBurnTotal[lvl][denom][sub]` | L584 (via L176) | When delta != 0 (new burn recorded) |

### Cached-Local-vs-Storage Check

- `m` (memory copy of DecEntry) at L139 caches the entry. Writes to storage (`e.burn`, `e.bucket`, `e.subBucket`) at L169-171 use the COMPUTED values from `m`, not re-reading from storage. This is correct -- the function owns the full lifecycle of this entry's updates.
- `prevBurn` (L140) caches `m.burn`. Used for delta calculation at L174. Since no other function can modify `decBurn[lvl][player]` between L140 and L174 (single-threaded EVM), this is safe.
- `_decRemoveSubbucket` and `_decUpdateSubbucket` operate on `decBucketBurnTotal`, which is a DIFFERENT storage slot than `decBurn`. No conflict.

**VERDICT: SAFE.** The cached local `m` is a deliberate pattern for efficiency. No BAF-class conflict because the function writes back computed values at L169-171, and the aggregate updates at L176 use fresh delta.

### Attack Analysis

**1. State Coherence:** SAFE. See above.

**2. Access Control:** `OnlyCoin` (L136). Only the BurnieCoin contract can call this. Cannot be bypassed via delegatecall because this function uses `msg.sender` check (not `address(this)` context). **VERDICT: SAFE.**

**3. Bucket Migration Integrity:**
- When a player provides a better (lower) bucket, L148 removes their burn from the old bucket aggregate and L153 adds it to the new bucket aggregate.
- The removal uses `prevBurn` (the burn amount before this call's contribution).
- The aggregate addition at L176 uses `delta` (the NEW burn from this call only).
- The carry-over burn from old to new bucket at L153 uses `prevBurn`.
- Net result: old_aggregate -= prevBurn, new_aggregate += prevBurn + delta. This correctly migrates the full burn amount.
- **INVESTIGATE:** What if `bucket == 0` is passed? The condition `bucket != 0 && bucket < m.bucket` at L146 protects against this. If bucket == 0, no migration occurs.
- **INVESTIGATE:** What if `bucket > DECIMATOR_MAX_DENOM` (e.g., 255)? No guard prevents bucket > 12. However, `_decSubbucketFor` returns `keccak256(...) % bucket` which works for any non-zero bucket. The subbucket and bucket are stored in the player's DecEntry. During resolution (B2), only denoms 2-12 are checked. A player with bucket > 12 would never win -- their subbucket is never in the winning selection. Their burn contributes to the aggregate but the aggregate for denom > 12 is never read for winning selection. **This is an economic griefing vector against the player themselves (self-harm only, no protocol impact).**
- **VERDICT: SAFE.** The coin contract controls the bucket parameter; players cannot pass arbitrary values directly.

**4. uint192 Saturation:**
- L167: `if (updated > type(uint192).max) updated = type(uint192).max`. Saturation is correct.
- However, when saturated, `delta = newBurn - prevBurn` could be less than `effectiveAmount`. The aggregate update at L176 uses this reduced `delta`. This means the aggregate could be slightly less than the true total of all players' saturated burns. The impact is that the pro-rata share calculation becomes slightly inaccurate at astronomical burn values.
- type(uint192).max is ~6.27 x 10^57. With PRICE_COIN_UNIT = 1000 ether = 10^21, that's 6.27 x 10^36 units. Practically unreachable.
- **VERDICT: SAFE.** Saturation arithmetic is correct; unreachable in practice.

**5-10. Remaining angles:** All SAFE. OnlyCoin access prevents unauthorized calls. No RNG involved in burn recording. No external calls. Edge cases (zero baseAmount returns 0 from `_decEffectiveAmount`; first burn correctly initializes bucket/subbucket). No silent failures (all reverts are explicit).

---

## B2: runDecimatorJackpot(uint256,uint24,uint256) -- Lines 205-256 [TIER 2]

### Call Tree

```
runDecimatorJackpot(poolWei, lvl, rngWord)                L205
  |-- if (msg.sender != GAME) revert OnlyGame()            L210
  |-- if (decClaimRounds[lvl].poolWei != 0) return poolWei  L213  (double-snapshot guard)
  |
  |-- totalBurn = 0; packedOffsets = 0                      L217-218
  |-- for denom = 2 to 12:                                  L222-240
  |   |-- winningSub = _decWinningSubbucket(rngWord, denom) L224
  |   |   |-- keccak256(abi.encodePacked(rngWord, denom)) % denom L484 (pure)
  |   |-- packedOffsets = _packDecWinningSubbucket(packed, denom, winningSub) L225-229
  |   |   |-- shift = (denom - 2) << 2                      L498
  |   |   |-- packed with 4-bit mask                         L500 (pure)
  |   |-- subTotal = decBucketBurnTotal[lvl][denom][winningSub] L232 *** READ ***
  |   |-- if (subTotal != 0) totalBurn += subTotal           L233-235
  |
  |-- if (totalBurn == 0) return poolWei                    L243  (no qualifying burns)
  |
  |-- decBucketOffsetPacked[lvl] = packedOffsets             L248 *** WRITE ***
  |-- decClaimRounds[lvl].poolWei = poolWei                  L251 *** WRITE ***
  |-- decClaimRounds[lvl].totalBurn = uint232(totalBurn)     L252 *** WRITE ***
  |-- decClaimRounds[lvl].rngWord = rngWord                  L253 *** WRITE ***
  |-- return 0                                               L255
```

### Storage Writes (Full Tree)

| Variable | Written At |
|----------|-----------|
| `decBucketOffsetPacked[lvl]` | L248 |
| `decClaimRounds[lvl].poolWei` | L251 |
| `decClaimRounds[lvl].totalBurn` | L252 |
| `decClaimRounds[lvl].rngWord` | L253 |

### Cached-Local-vs-Storage Check

- `totalBurn` and `packedOffsets` are local variables built during the loop. They are written to storage only at the end (L248-253). No subordinate call modifies these storage slots between the reads and the writes.
- **VERDICT: SAFE.** Linear function with no subordinate state-changing calls.

### Attack Analysis

**1. State Coherence:** SAFE. No subordinate calls modify storage the parent caches.

**2. Access Control:** `OnlyGame` (L210). Only the Game contract (via its own execution) can call this. **SAFE.**

**3. Double-Snapshot Guard:**
- L213: `if (decClaimRounds[lvl].poolWei != 0) return poolWei`. This prevents re-snapshotting.
- **INVESTIGATE:** What if poolWei is legitimately 0? The function receives poolWei as a parameter from the caller (endgame/jackpot resolution). If the caller passes 0, the double-snapshot guard won't trigger, but the `totalBurn == 0` check at L243 would return 0, and the function would try to snapshot with poolWei = 0. However, L251 writes `decClaimRounds[lvl].poolWei = 0`, which means future calls would pass the double-snapshot guard (poolWei == 0 means "not snapshotted").
- Wait -- if poolWei = 0 is passed AND totalBurn > 0, the function would snapshot with poolWei = 0, meaning winners get 0 ETH each. Their claims would succeed (DecClaimInactive is not triggered because poolWei is checked for 0 at L275 in _consumeDecClaim -- `if (round.poolWei == 0) revert DecClaimInactive`). So claims would revert. This effectively orphans the burn entries.
- This requires the caller to pass poolWei = 0, which would be a bug in the caller. Not a vulnerability in this module.
- **VERDICT: SAFE.** The function correctly handles its inputs; caller is trusted (OnlyGame).

**4. uint232 Truncation of totalBurn:**
- L252: `uint232(totalBurn)`. totalBurn is a sum of up to 11 subbucket aggregates. Each aggregate is uint256. If any single aggregate exceeds uint232.max (~6.9 x 10^69), truncation occurs. But aggregates are sums of uint192 individual burns, so the theoretical max per aggregate is (number_of_players * type(uint192).max). Even with 2^32 players (4 billion), this is ~2.7 x 10^89, which exceeds uint232. However, this scenario is impossibly unrealistic.
- **VERDICT: SAFE.** Unreachable in practice.

**5. decBucketOffsetPacked Collision (CRITICAL INVESTIGATION):**

Both B2 (this function) and B6 (runTerminalDecimatorJackpot) write to `decBucketOffsetPacked[lvl]`.

**Question:** Can B6 overwrite B2's packed offsets at the same level?

**Analysis:**
- B2 is called during normal jackpot phase level transitions.
- B6 is called during GAMEOVER (terminal resolution).
- At GAMEOVER, the current level has NOT yet completed its normal jackpot resolution (GAMEOVER short-circuits the normal flow).
- B2's double-snapshot guard checks `decClaimRounds[lvl].poolWei != 0`. If B2 was called for this level before GAMEOVER, the guard prevents re-snapshotting.
- B6's double-resolution guard checks `lastTerminalDecClaimRound.lvl == lvl`. This is independent of B2's guard.
- **Scenario:** Level N has both regular decimator burns AND terminal decimator burns. Level N reaches its normal jackpot phase, B2 is called and snapshots decBucketOffsetPacked[N] with regular decimator winning subbuckets. Then GAMEOVER occurs at level N, and B6 is called, which OVERWRITES decBucketOffsetPacked[N] with terminal decimator winning subbuckets (selected from a different set of burns and a different rngWord).
- **Impact:** Any unclaimed regular decimator claims for level N now use the WRONG winning subbuckets. A player who was a winner under the regular decimator selection may no longer be a winner, and vice versa.
- **HOWEVER:** Regular decimator resolution (B2) and GAMEOVER resolution (B6) use DIFFERENT storage for their burn aggregates: `decBucketBurnTotal[lvl][denom][sub]` (array-based, B2) vs `terminalDecBucketBurnTotal[keccak256(lvl,denom,sub)]` (mapping-based, B6). But they SHARE `decBucketOffsetPacked[lvl]` for packed winning subbuckets.
- **INVESTIGATION RESULT:** The regular decimator claim flow (_consumeDecClaim at L281) reads `decBucketOffsetPacked[lvl]` to determine the winning subbucket. If B6 overwrites this after B2 wrote it, the winning subbucket values change.
- **Terminal decimator claim flow** (_consumeTerminalDecClaim at L881) ALSO reads `decBucketOffsetPacked[lvl]` to determine its winning subbuckets.
- **This means both claim paths read the SAME packed offsets.** If B6 runs after B2 at the same level, both regular and terminal claims would use B6's selections (terminal decimator's winning subbuckets).

**VERDICT: INVESTIGATE -- Potential decBucketOffsetPacked collision.** If both regular and terminal decimator run at the same level, the terminal resolution overwrites the regular resolution's winning subbuckets. Regular decimator winners could change. This is a potential MEDIUM severity finding -- it depends on whether both resolutions can actually occur at the same level.

**Mitigating factor:** For regular decimator to have been resolved at the same level where GAMEOVER occurs, that level must have entered jackpot phase AND completed decimator resolution before the GAMEOVER trigger. Terminal decimator resolution happens as part of the GAMEOVER flow, which runs at the current level. If the GAMEOVER is triggered during jackpot phase, B2 may have already run. The overwrite would then corrupt regular decimator claims.

**6-10. Remaining angles:** All SAFE. No RNG manipulation (VRF word is input parameter from trusted caller). No external calls. No economic attack (OnlyGame caller).

---

## B5: recordTerminalDecBurn(address,uint24,uint256) -- Lines 707-770 [TIER 2]

### Call Tree

```
recordTerminalDecBurn(player, lvl, baseAmount)             L707
  |-- if (msg.sender != COIN) revert OnlyCoin()             L712
  |-- daysRemaining = _terminalDecDaysRemaining()            L714
  |   |-- timeout = (level == 0) ? 365 days : 120 days       L923-925
  |   |-- deadline = levelStartTime + timeout                  L926
  |   |-- if (block.timestamp >= deadline) return 0            L927
  |   |-- return (deadline - block.timestamp) / 1 days         L928
  |-- if (daysRemaining <= 1) revert TerminalDecDeadlinePassed L715
  |
  |-- bonusBps = IDegenerusGame(address(this)).playerActivityScore(player) L718
  |   *** EXTERNAL SELF-CALL via Game router -> dispatches to appropriate module ***
  |-- if (bonusBps > TERMINAL_DEC_ACTIVITY_CAP_BPS) bonusBps = cap L719
  |-- bucket = _terminalDecBucket(bonusBps)                    L720
  |   |-- (pure: maps activity score to bucket 2-12)           L912-919
  |-- multBps = bonusBps == 0 ? 10000 : 10000 + (bonusBps / 3) L721
  |
  |-- e = terminalDecEntries[player]                           L723 *** READ ***
  |-- [BRANCH: e.burnLevel != lvl (lazy reset)]
  |   |-- e.totalBurn = 0; e.weightedBurn = 0; e.bucket = 0; e.subBucket = 0 L727-730
  |   |-- e.burnLevel = lvl                                    L731 *** WRITE ***
  |
  |-- [BRANCH: e.bucket == 0 (first burn this level)]
  |   |-- e.bucket = bucket                                    L736 *** WRITE ***
  |   |-- e.subBucket = _decSubbucketFor(player, lvl, bucket)  L737 *** WRITE ***
  |
  |-- effectiveAmount = _decEffectiveAmount(e.totalBurn, baseAmount, multBps) L741-745
  |-- if (effectiveAmount == 0) revert TerminalDecCapped       L746
  |
  |-- newTotal = e.totalBurn + effectiveAmount                 L749
  |-- if (newTotal > type(uint80).max) newTotal = type(uint80).max L750
  |-- e.totalBurn = uint80(newTotal)                           L751 *** WRITE ***
  |
  |-- timeMultBps = _terminalDecMultiplierBps(daysRemaining)   L754
  |-- weightedAmount = (effectiveAmount * timeMultBps) / BPS_DENOMINATOR L755
  |
  |-- newWeighted = e.weightedBurn + weightedAmount            L758
  |-- if (newWeighted > type(uint88).max) newWeighted = type(uint88).max L759
  |-- e.weightedBurn = uint88(newWeighted)                     L760 *** WRITE ***
  |
  |-- bucketKey = keccak256(abi.encode(lvl, e.bucket, e.subBucket)) L763
  |-- terminalDecBucketBurnTotal[bucketKey] += weightedAmount  L764 *** WRITE ***
  |
  |-- emit TerminalDecBurnRecorded(...)                        L766-769
```

### Storage Writes (Full Tree)

| Variable | Written At |
|----------|-----------|
| `terminalDecEntries[player].burnLevel` | L731 (lazy reset) |
| `terminalDecEntries[player].totalBurn` | L727 (reset), L751 (update) |
| `terminalDecEntries[player].weightedBurn` | L728 (reset), L760 (update) |
| `terminalDecEntries[player].bucket` | L729 (reset), L736 (first burn) |
| `terminalDecEntries[player].subBucket` | L730 (reset), L737 (first burn) |
| `terminalDecBucketBurnTotal[key]` | L764 |

### Cached-Local-vs-Storage Check

- The function reads `e` (storage reference) at L723 and writes directly to it throughout. No local caching of a value that is later overwritten by a subordinate call.
- The `IDegenerusGame(address(this)).playerActivityScore(player)` call at L718 is a VIEW call (external, but read-only). It does not write to any storage. No BAF concern from this call.

**VERDICT: SAFE.** No cached-local-vs-storage conflict.

### Attack Analysis

**1. State Coherence:** SAFE. See above.

**2. Access Control:** OnlyCoin (L712). **SAFE.**

**3. Self-Call Pattern (L718):**
- `IDegenerusGame(address(this)).playerActivityScore(player)` is an external call to the Game contract (which is `address(this)` in delegatecall context).
- This call goes through the Game's fallback, which dispatches to the appropriate module.
- `playerActivityScore` is a `view` function -- it reads state but writes nothing.
- **Gas concern:** The external call consumes gas for the function dispatch + activity computation. If the computation is expensive, this could fail with out-of-gas. However, since this is called by the Coin contract (which controls the gas provided), and the activity score computation is bounded, this is not exploitable.
- **Reentrancy concern:** Even though this is an external call, it's to `address(this)` which is a view function. No state changes can occur during this call. The nonReentrant guard (if any) would not block a view call.
- **VERDICT: SAFE.** External view call to self; no state changes; gas bounded.

**4. Lazy Reset (L726-731):**
- When `e.burnLevel != lvl`, the entry is reset. This correctly handles level transitions.
- **Edge case:** If a player burned in level N, then level N+1 starts, and they burn in N+1, the old entry is zeroed. The old bucket aggregate at `terminalDecBucketBurnTotal[keccak256(N, old_bucket, old_sub)]` is NOT decremented.
- **INVESTIGATE:** Does this corrupt the aggregate? No -- the aggregate key includes `lvl`. The old aggregate for level N remains but is never used for level N+1 resolution. The resolution (B6) uses the current `lvl` parameter to look up aggregates.
- **VERDICT: SAFE.** Stale aggregates from prior levels are naturally orphaned.

**5. Time Multiplier Edge Cases:**
- `_terminalDecMultiplierBps` at L903-909:
  - `daysRemaining > 10`: returns `daysRemaining * 2500`. At daysRemaining = 120, this is 300000 BPS (30x). At daysRemaining = 11, this is 27500 BPS (2.75x).
  - `daysRemaining <= 10`: returns `10000 + ((daysRemaining - 2) * 10000) / 8`. At daysRemaining = 10, this is 20000 BPS (2x). At daysRemaining = 2, this is 10000 BPS (1x).
  - `daysRemaining == 1`: blocked by L715 (`if (daysRemaining <= 1) revert`).
  - **Edge: daysRemaining == 2:** 10000 + (0 * 10000) / 8 = 10000. Correct (1x).
  - **Edge: daysRemaining == 0:** Blocked by L715.
  - The discontinuity at day 10 (2.75x -> 2x) is intentional per the comment at L902.
- **VERDICT: SAFE.** All boundary values produce correct multipliers.

**6. uint80/uint88 Saturation:**
- `totalBurn` capped at uint80.max (~1.2 x 10^24). With PRICE_COIN_UNIT = 10^21 and DECIMATOR_MULTIPLIER_CAP = 200 * 10^21 = 2 x 10^23, the cap of 200,000 units means totalBurn maxes at 2 x 10^23, which is well within uint80.max. Saturation should never trigger.
- `weightedBurn` capped at uint88.max (~3.1 x 10^26). With 30x max time multiplier applied to 2 x 10^23 max effective, max weighted is ~6 x 10^24, within uint88.max. Saturation should never trigger.
- **VERDICT: SAFE.** Practical values never reach saturation limits.

**7-10. Remaining angles:** All SAFE. No RNG used. No external calls besides view self-call. No economic exploit (OnlyCoin access). No silent failures (explicit reverts on all error paths).

---

## B6: runTerminalDecimatorJackpot(uint256,uint24,uint256) -- Lines 783-825 [TIER 2]

### Call Tree

```
runTerminalDecimatorJackpot(poolWei, lvl, rngWord)        L783
  |-- if (msg.sender != GAME) revert OnlyGame()            L788
  |-- if (lastTerminalDecClaimRound.lvl == lvl) return poolWei L791 (double-resolution guard)
  |
  |-- totalWinnerBurn = 0; packedOffsets = 0                L795-796
  |-- for denom = 2 to 12:                                  L800-810
  |   |-- winningSub = _decWinningSubbucket(rngWord, denom) L801
  |   |-- packedOffsets = _packDecWinningSubbucket(packed, denom, winningSub) L802
  |   |-- bucketKey = keccak256(abi.encode(lvl, denom, winningSub)) L804
  |   |-- subTotal = terminalDecBucketBurnTotal[bucketKey]   L805 *** READ ***
  |   |-- if (subTotal != 0) totalWinnerBurn += subTotal     L806-808
  |
  |-- if (totalWinnerBurn == 0) return poolWei              L812 (no winners)
  |
  |-- decBucketOffsetPacked[lvl] = packedOffsets             L817 *** WRITE (COLLISION) ***
  |-- lastTerminalDecClaimRound.lvl = lvl                    L820 *** WRITE ***
  |-- lastTerminalDecClaimRound.poolWei = uint96(poolWei)    L821 *** WRITE ***
  |-- lastTerminalDecClaimRound.totalBurn = uint128(totalWinnerBurn) L822 *** WRITE ***
  |-- return 0                                               L824
```

### Storage Writes (Full Tree)

| Variable | Written At |
|----------|-----------|
| `decBucketOffsetPacked[lvl]` | L817 |
| `lastTerminalDecClaimRound.lvl` | L820 |
| `lastTerminalDecClaimRound.poolWei` | L821 |
| `lastTerminalDecClaimRound.totalBurn` | L822 |

### Cached-Local-vs-Storage Check

Linear function with no subordinate calls. **SAFE.**

### Attack Analysis

**1. decBucketOffsetPacked Collision (CONTINUED):**
- L817 writes to `decBucketOffsetPacked[lvl]`. As analyzed in B2, this can overwrite regular decimator packed offsets.
- **VERDICT: INVESTIGATE.** See B2 analysis, angle 5. This is the same finding -- both B2 and B6 share this slot.

**2. uint96 Truncation of poolWei:**
- L821: `uint96(poolWei)`. type(uint96).max = ~79,228 ETH. Terminal decimator receives 10% of remaining funds at GAMEOVER. For truncation, the remaining funds would need to exceed ~792K ETH. Given Ethereum's total ETH supply and realistic protocol TVL, this is unreachable.
- **VERDICT: SAFE.** Unreachable in practice.

**3. uint128 Truncation of totalWinnerBurn:**
- L822: `uint128(totalWinnerBurn)`. type(uint128).max = ~3.4 x 10^38. Individual weightedBurn is uint88 max (~3.1 x 10^26). Even with 10^12 players (unrealistic), total is ~3.1 x 10^38, near the limit. Practically unreachable.
- **VERDICT: SAFE.**

**4. Double-Resolution Guard:**
- L791 checks `lastTerminalDecClaimRound.lvl == lvl`. This uses a single global struct (not per-level mapping like the regular decimator). This means only ONE terminal resolution can ever exist.
- If GAMEOVER is called multiple times (should be impossible, but check), only the first creates a claim round.
- **VERDICT: SAFE.** Double-resolution correctly prevented.

**5-10. Remaining angles:** All SAFE. OnlyGame access. No external calls. No RNG manipulation (VRF input). No economic exploit.

---

## B7: claimTerminalDecimatorJackpot() -- Lines 833-840 [TIER 2]

### Call Tree

```
claimTerminalDecimatorJackpot()                            L833
  |-- if (prizePoolFrozen) revert E()                       L834
  |-- amountWei = _consumeTerminalDecClaim(msg.sender)       L836
  |   |-- lvl = lastTerminalDecClaimRound.lvl                L872
  |   |-- if (lvl == 0) revert TerminalDecNotActive          L873
  |   |-- e = terminalDecEntries[msg.sender]                 L875
  |   |-- if (e.burnLevel != lvl || e.weightedBurn == 0)     L876
  |   |   revert TerminalDecNotWinner
  |   |-- weight = e.weightedBurn                            L879
  |   |-- packedOffsets = decBucketOffsetPacked[lvl]          L881 *** READ ***
  |   |-- winningSub = _unpackDecWinningSubbucket(packed, e.bucket) L882
  |   |-- if (e.subBucket != winningSub) revert TerminalDecNotWinner L883
  |   |-- totalBurn = lastTerminalDecClaimRound.totalBurn     L885
  |   |-- if (totalBurn == 0) revert TerminalDecNotWinner     L886
  |   |-- amountWei = (poolWei * weight) / totalBurn           L888
  |   |-- if (amountWei == 0) revert TerminalDecNotWinner     L889
  |   |-- e.weightedBurn = 0                                  L892 *** WRITE: claimed flag ***
  |
  |-- _addClaimableEth(msg.sender, amountWei, 0)             L839
      |-- if (weiAmount == 0) return                          L419
      |-- _processAutoRebuy(msg.sender, amountWei, 0)        L420
      |   |-- if (gameOver) return false                      L367 *** RETURNS FALSE ***
      |-- _creditClaimable(msg.sender, amountWei)             L423
          |-- claimableWinnings[msg.sender] += amountWei      L33 *** WRITE ***
```

### Storage Writes (Full Tree)

| Variable | Written At |
|----------|-----------|
| `terminalDecEntries[player].weightedBurn` | L892 (set to 0 = claimed) |
| `claimableWinnings[player]` | L33 (PayoutUtils) |

### Cached-Local-vs-Storage Check

- No local caching of values that subordinates write. The function is linear: consume claim, then credit ETH.
- The `entropy = 0` parameter means _processAutoRebuy's _calcAutoRebuy would compute with entropy = 0, but it never reaches that code because `gameOver` returns false first (L367).
- **VERDICT: SAFE.**

### Attack Analysis

**1. State Coherence:** SAFE. No cached locals conflict with subordinate writes.

**2. Access Control:** Player-callable. Eligibility enforced by `_consumeTerminalDecClaim`. **SAFE.**

**3. gameOver Bypass:**
- This function does NOT check `gameOver` before proceeding. It relies on `_processAutoRebuy` to skip auto-rebuy when gameOver is true.
- **INVESTIGATE:** Could this be called before GAMEOVER? Yes -- `lastTerminalDecClaimRound.lvl` would be 0 (never resolved), so L873 reverts with `TerminalDecNotActive`. **SAFE.**
- **After GAMEOVER:** gameOver == true. Auto-rebuy correctly skipped. Full amount goes to claimableWinnings. **SAFE.**

**4. Double-Claim Prevention:**
- `_consumeTerminalDecClaim` sets `e.weightedBurn = 0` at L892. On second call, L876 checks `e.weightedBurn == 0` and reverts. **SAFE.**

**5-10. Remaining angles:** All SAFE. No RNG (entropy=0, auto-rebuy skipped). No external calls. Pro-rata from immutable snapshot.

---

## B3: consumeDecClaim(address,uint24) -- Lines 301-307 [TIER 3]

### Call Tree

```
consumeDecClaim(player, lvl)                               L301
  |-- if (msg.sender != GAME) revert OnlyGame()             L305
  |-- return _consumeDecClaim(player, lvl)                   L306
      |-- [Full expansion same as in B4 analysis, C1 section]
```

### Storage Writes (Full Tree)

| Variable | Written At |
|----------|-----------|
| `decBurn[lvl][player].claimed` | L292 |

### Cached-Local-vs-Storage Check

Thin wrapper. No local caching. **SAFE.**

### Attack Analysis

All 10 angles: **SAFE.** OnlyGame access. Delegates entirely to `_consumeDecClaim` which is analyzed under B4. No additional attack surface beyond what B4 covers for the claim consumption path.

---

## DEDICATED SECTION: decBucketOffsetPacked Collision Analysis

### Finding: DEC-OFFSET-COLLISION

**Both `runDecimatorJackpot` (B2, L248) and `runTerminalDecimatorJackpot` (B6, L817) write to `decBucketOffsetPacked[lvl]`.**

**Both `_consumeDecClaim` (C1, L281) and `_consumeTerminalDecClaim` (C8, L881) read from `decBucketOffsetPacked[lvl]`.**

**Scenario:**
1. Level N enters jackpot phase. B2 is called: `decBucketOffsetPacked[N]` = regular decimator winning subbuckets (from regular rngWord).
2. GAMEOVER triggers at level N. B6 is called: `decBucketOffsetPacked[N]` = terminal decimator winning subbuckets (from GAMEOVER rngWord). **Overwrites step 1.**
3. Player A claims regular decimator for level N via B4: `_consumeDecClaim` reads `decBucketOffsetPacked[N]` which now contains terminal decimator selections. Player A's subbucket may not match the terminal selections, causing a false `DecNotWinner` revert.
4. Player B claims terminal decimator via B7: `_consumeTerminalDecClaim` reads `decBucketOffsetPacked[N]` which contains the correct terminal selections. Works correctly.

**Result:** Regular decimator claims at the GAMEOVER level are corrupted if terminal resolution runs after regular resolution.

**Reverse scenario:** If B6 runs before B2 at the same level (unlikely but theoretically possible depending on GAMEOVER flow ordering), B2 overwrites B6's selections, corrupting terminal decimator claims.

**Probability assessment:** Terminal decimator only resolves at GAMEOVER. Regular decimator resolves during normal jackpot phase. For both to execute at the same level, GAMEOVER must occur during or after the level's jackpot phase (when regular decimator has already been resolved). This is a plausible scenario: a level completes its jackpots, then the GAMEOVER condition (death clock expiry) triggers at the same level before a new level starts.

**VERDICT: INVESTIGATE -- Potential MEDIUM severity.** The winning subbuckets for one decimator type get overwritten by the other at the GAMEOVER level. Impact is limited to the final level where GAMEOVER occurs, but affected players lose their rightful claims.

---

## Category C Multi-Parent Analysis

### C1: _consumeDecClaim (MULTI-PARENT)
- Called by B3 (consumeDecClaim -- OnlyGame) and B4 (claimDecimatorJackpot -- player).
- Both callers pass the same parameters (player, lvl). B3 uses an arbitrary `player` address (game-initiated), B4 uses `msg.sender`.
- The function is idempotent: claimed flag prevents double execution.
- **SAFE.** No different cached-local states between parents.

### C3: _addClaimableEth (MULTI-PARENT, BAF-CRITICAL)
- Called by C4 (via B4 normal path), B4 (gameOver path), and B7 (terminal claim).
- In B4 normal path: auto-rebuy may trigger, writing futurePrizePool/nextPrizePool.
- In B4 gameOver path and B7: auto-rebuy returns false (gameOver guard). Only _creditClaimable executes.
- **SAFE.** The gameOver guard prevents BAF-chain execution in the two paths where it would be problematic.

### C5: _decUpdateSubbucket (MULTI-PARENT)
- Called by B1 at L153 (bucket migration carry-over) and L176 (new burn delta).
- Both calls are sequential within the same function. No concurrent access concern.
- **SAFE.**

---

*Attack report completed: 2026-03-25*
*Mad Genius: 7 Category B functions analyzed. 1 finding at INVESTIGATE severity (DEC-OFFSET-COLLISION). All other angles SAFE.*
