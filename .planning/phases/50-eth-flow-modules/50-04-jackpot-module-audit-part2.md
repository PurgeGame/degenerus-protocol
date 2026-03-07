# DegenerusGameJackpotModule.sol -- Function-Level Audit (Part 2: Distribution Engine, Coin Jackpots, Helpers)

**Contract:** DegenerusGameJackpotModule
**File:** contracts/modules/DegenerusGameJackpotModule.sol
**Lines:** 2794
**Solidity:** 0.8.34
**Inherits:** DegenerusGamePayoutUtils (which inherits DegenerusGameStorage)
**Audit date:** 2026-03-07
**Scope:** Part 2 -- Internal distribution engine, coin jackpots, ticket processing, trait/entropy helpers (lines ~1319-2794)

---

## Function Audit

### `_executeJackpot(JackpotParams memory jp)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _executeJackpot(JackpotParams memory jp) private returns (uint256 paidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `jp` (JackpotParams): Packed jackpot parameters containing lvl, ethPool, entropy, winningTraitsPacked, traitShareBpsPacked |
| **Returns** | `uint256`: Total ETH paid out for pool accounting |

**State Reads:** None directly (delegates to callees)
**State Writes:** None directly (delegates to callees)

**Callers:** `payDailyJackpot` (early-burn path)
**Callees:** `JackpotBucketLib.unpackWinningTraits`, `JackpotBucketLib.shareBpsByBucket`, `_runJackpotEthFlow`

**ETH Flow:** Orchestrator only. If `jp.ethPool != 0`, delegates to `_runJackpotEthFlow` which distributes ETH to claimable balances. The caller (payDailyJackpot early-burn path) does not deduct from currentPrizePool since funds come from futurePrizePool which is deducted upfront.

**Invariants:**
- If `jp.ethPool == 0`, no ETH distribution occurs and `paidEth == 0`.
- Share BPS rotation is derived from `jp.entropy & 3`, ensuring fair bucket assignment.

**NatSpec Accuracy:** NatSpec says "distributes ETH and/or COIN to winners" but the function only handles ETH distribution. COIN distribution was removed/refactored -- the COIN path for early-burn is handled separately by `payDailyCoinJackpot`. The NatSpec is slightly stale but the actual behavior is correct.

**Gas Flags:** None. Simple dispatch function with minimal overhead.

**Verdict:** CORRECT

---

### `_runJackpotEthFlow(JackpotParams memory jp, uint8[4] memory traitIds, uint16[4] memory shareBps)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _runJackpotEthFlow(JackpotParams memory jp, uint8[4] memory traitIds, uint16[4] memory shareBps) private returns (uint256 totalPaidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `jp` (JackpotParams): Packed jackpot params; `traitIds` (uint8[4]): Unpacked winning trait IDs; `shareBps` (uint16[4]): Per-bucket share basis points |
| **Returns** | `uint256`: Total ETH paid out |

**State Reads:** Via callees (traitBurnTicket, claimableWinnings, autoRebuyState)
**State Writes:** Via callees (claimableWinnings, claimablePool, whalePassClaims, futurePrizePool)

**Callers:** `_executeJackpot`
**Callees:** `JackpotBucketLib.traitBucketCounts`, `JackpotBucketLib.scaleTraitBucketCountsWithCap`, `_distributeJackpotEth`

**ETH Flow:** Computes scaled bucket counts from `jp.ethPool` (capped at JACKPOT_MAX_WINNERS=300, max scale 4x at 200 ETH), then delegates to `_distributeJackpotEth` with `dgnrsReward=0`.

**Invariants:**
- Bucket counts are always capped at JACKPOT_MAX_WINNERS (300).
- Scale factor: 1x under 10 ETH, linearly to 2x at 50 ETH, linearly to 4x at 200 ETH+.
- Solo bucket always has count=1 (guaranteed by JackpotBucketLib rotation).

**NatSpec Accuracy:** Matches. "Simple ETH flow for jackpot ETH distribution."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_winnerUnits(address winner)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _winnerUnits(address winner) private view returns (uint8 units)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `winner` (address): Address to check |
| **Returns** | `uint8`: 0 for address(0), 3 for auto-rebuy enabled, 1 otherwise |

**State Reads:** `autoRebuyState[winner].autoRebuyEnabled`
**State Writes:** None

**Callers:** `_processDailyEthChunk`
**Callees:** None

**ETH Flow:** None. Pure cost computation for gas budgeting.

**Invariants:**
- address(0) always returns 0 (skipped in processing).
- Auto-rebuy winners cost 3x units because `_processAutoRebuy` does additional storage writes (ticket queueing, pool updates).

**NatSpec Accuracy:** Matches. "Winner unit cost (auto-rebuy counts as 3x)."

**Gas Flags:** None. Single storage read (warm after first access in the loop).

**Verdict:** CORRECT

---

### `_skipEntropyToBucket(uint256 entropy, uint8[4] memory order, uint256[4] memory shares, uint16[4] memory bucketCounts, uint8 startOrderIdx)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _skipEntropyToBucket(uint256 entropy, uint8[4] memory order, uint256[4] memory shares, uint16[4] memory bucketCounts, uint8 startOrderIdx) private pure returns (uint256 entropyState)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): Initial entropy; `order` (uint8[4]): Bucket processing order; `shares` (uint256[4]): Per-bucket shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `startOrderIdx` (uint8): Index to skip to |
| **Returns** | `uint256`: Advanced entropy state |

**State Reads:** None
**State Writes:** None

**Callers:** `_processDailyEthChunk`
**Callees:** `EntropyLib.entropyStep`

**ETH Flow:** None. Entropy advancement only.

**Invariants:**
- The entropy derivation uses `entropyState ^ (uint256(traitIdx) << 64) ^ share`, which matches the derivation in `_processDailyEthChunk` and `_distributeJackpotEth`, ensuring deterministic replay when resuming chunked distribution.
- Skips buckets with `count == 0 || share == 0` (no entropy step for empty buckets), matching the main loop behavior.

**NatSpec Accuracy:** Matches. "Skips entropy forward for already-processed buckets."

**Gas Flags:** None. At most 3 iterations (0 to startOrderIdx-1).

**Verdict:** CORRECT

---

### `_processDailyEthChunk(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint16 unitsBudget)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processDailyEthChunk(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint16 unitsBudget) private returns (uint256 paidEth, bool complete)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner lookup; `ethPool` (uint256): Total ETH budget; `entropy` (uint256): VRF-derived entropy; `traitIds` (uint8[4]): Winning traits; `shareBps` (uint16[4]): Per-bucket shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `unitsBudget` (uint16): Gas budget in units |
| **Returns** | `paidEth` (uint256): ETH distributed; `complete` (bool): True if all buckets processed |

**State Reads:** `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `traitBurnTicket[lvl]`, `autoRebuyState`, `deityBySymbol`, `claimableWinnings`, `gameOver`
**State Writes:** `dailyEthBucketCursor`, `dailyEthWinnerCursor`, `claimablePool`, `claimableWinnings`, (via _addClaimableEth: `whalePassClaims`, `futurePrizePool`, `nextPrizePool`)

**Callers:** `payDailyJackpot` (daily path, Phase 0 and Phase 1)
**Callees:** `PriceLookupLib.priceForLevel`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.bucketShares`, `JackpotBucketLib.bucketOrderLargestFirst`, `_skipEntropyToBucket`, `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `_winnerUnits`, `_addClaimableEth`

**ETH Flow:**
- `ethPool` -> per-bucket shares (via `JackpotBucketLib.bucketShares`)
- per-bucket share -> `perWinner = share / totalCount`
- per winner -> `_addClaimableEth(w, perWinner, entropyState)` -> `claimableWinnings[w]` or auto-rebuy conversion
- liability aggregated and applied to `claimablePool` at end or on yield

**Cursor mechanism for gas-safe resumption:**
1. `dailyEthBucketCursor` (uint8): Which bucket (in processing order) to resume from.
2. `dailyEthWinnerCursor` (uint16): Which winner within the current bucket to resume from.
3. On incomplete: stores cursors and returns `(paidEth, false)`.
4. On complete: resets cursors to 0 and returns `(paidEth, true)`.
5. On resume: `_skipEntropyToBucket` replays entropy for already-processed buckets to reach the correct entropy state.

**Invariants:**
- Winners are processed in largest-bucket-first order (via `bucketOrderLargestFirst`).
- Per-winner amount is `share / totalCount` -- integer division means dust stays in the contract.
- Gas budget tracked via `_winnerUnits(w)`: 1 unit per normal winner, 3 for auto-rebuy.
- `claimablePool` is updated atomically at the end of each chunk (or on yield).
- Entropy derivation per bucket: `entropyState ^ (uint256(traitIdx) << 64) ^ share` -- deterministic and consistent with `_skipEntropyToBucket`.

**NatSpec Accuracy:** Matches. "Processes daily jackpot ETH winners in chunks, resuming mid-bucket if needed."

**Gas Flags:**
- The `bucketOrderLargestFirst` function uses a simple O(n) scan with ties broken by lower index, which is optimal for 4 elements.
- `_randTraitTicketWithIndices` is called once per bucket regardless of chunking -- winner list is regenerated on resume. This is acceptable because the list is deterministic (same entropy, same winners).

**Verdict:** CORRECT

---

### `_distributeJackpotEth(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint256 dgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _distributeJackpotEth(uint24 lvl, uint256 ethPool, uint256 entropy, uint8[4] memory traitIds, uint16[4] memory shareBps, uint16[4] memory bucketCounts, uint256 dgnrsReward) private returns (uint256 totalPaidEth)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level for winner lookup; `ethPool` (uint256): Total ETH budget; `entropy` (uint256): VRF-derived entropy; `traitIds` (uint8[4]): Winning traits; `shareBps` (uint16[4]): Per-bucket shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `dgnrsReward` (uint256): DGNRS reward for solo bucket (0 if none) |
| **Returns** | `uint256`: Total ETH paid (including ticket conversions) |

**State Reads:** Via callees
**State Writes:** `claimablePool` (directly); via callees: `claimableWinnings`, `whalePassClaims`, `futurePrizePool`

**Callers:** `_runJackpotEthFlow`, `runTerminalJackpot`, `payDailyJackpot` (via _runJackpotEthFlow)
**Callees:** `PriceLookupLib.priceForLevel`, `JackpotBucketLib.soloBucketIndex`, `JackpotBucketLib.bucketShares`, `_processOneBucket`

**ETH Flow:**
- `ethPool` -> 4 bucket shares via `JackpotBucketLib.bucketShares` with remainder going to `remainderIdx` (solo bucket).
- Each bucket processed by `_processOneBucket`.
- `ctx.liabilityDelta` accumulated and applied to `claimablePool` after all 4 buckets.
- `ctx.totalPaidEth` = sum of all `ethDelta + ticketSpent` across buckets.

**Solo bucket rotation:** `remainderIdx = JackpotBucketLib.soloBucketIndex(entropy)` = `(3 - (entropy & 3)) & 3`. This rotates which trait gets the solo (1-winner, highest share) bucket. The `soloIdx` for DGNRS reward uses the same formula.

**Invariants:**
- The sum of all 4 bucket shares equals `ethPool` (remainder bucket gets `pool - distributed`).
- `unit = PriceLookupLib.priceForLevel(lvl + 1) >> 2` ensures per-winner amounts are multiples of quarter-ticket price, reducing dust.
- `totalPaidEth` includes both direct ETH credits and whale-pass conversions.

**NatSpec Accuracy:** No explicit NatSpec beyond inline comments. Behavior matches the described flow.

**Gas Flags:**
- `soloIdx` is computed as `JackpotBucketLib.soloBucketIndex(entropy)` only when `dgnrsReward != 0`, but `remainderIdx` is always computed identically. These are the same value. Minor redundancy but the compiler likely optimizes it away.

**Verdict:** CORRECT

---

### `_processOneBucket(JackpotEthCtx memory ctx, uint8 traitIdx, uint8[4] memory traitIds, uint256[4] memory shares, uint16[4] memory bucketCounts, uint256 bucketDgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processOneBucket(JackpotEthCtx memory ctx, uint8 traitIdx, uint8[4] memory traitIds, uint256[4] memory shares, uint16[4] memory bucketCounts, uint256 bucketDgnrsReward) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `ctx` (JackpotEthCtx): Mutable context tracking entropy, liability, paid ETH; `traitIdx` (uint8): Current bucket index; `traitIds` (uint8[4]): Winning trait IDs; `shares` (uint256[4]): Per-bucket ETH shares; `bucketCounts` (uint16[4]): Per-bucket winner counts; `bucketDgnrsReward` (uint256): DGNRS reward (solo bucket only) |
| **Returns** | None (mutates ctx) |

**State Reads:** Via `_resolveTraitWinners`
**State Writes:** Via `_resolveTraitWinners`

**Callers:** `_distributeJackpotEth`
**Callees:** `_resolveTraitWinners`

**ETH Flow:** Delegates to `_resolveTraitWinners` with `payCoin=false`. Updates `ctx.totalPaidEth += ethDelta + ticketSpent` and `ctx.liabilityDelta += bucketLiability`.

**Invariants:**
- Single bucket dispatch. Entropy state flows through ctx to maintain determinism across buckets.
- `ticketSpent` tracks ETH converted to whale passes (moved to futurePrizePool).

**NatSpec Accuracy:** Matches. "Processes a single bucket in ETH distribution."

**Gas Flags:** None. Simple delegation.

**Verdict:** CORRECT

---

### `_resolveTraitWinners(bool payCoin, uint24 lvl, uint8 traitId, uint8 traitIdx, uint256 traitShare, uint256 entropy, uint16 winnerCount, uint256 dgnrsReward)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveTraitWinners(bool payCoin, uint24 lvl, uint8 traitId, uint8 traitIdx, uint256 traitShare, uint256 entropy, uint16 winnerCount, uint256 dgnrsReward) private returns (uint256 entropyState, uint256 ethDelta, uint256 liabilityDelta, uint256 ticketSpent)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payCoin` (bool): Pay BURNIE if true, ETH if false; `lvl` (uint24): Level; `traitId` (uint8): Trait pool to draw from; `traitIdx` (uint8): Bucket index; `traitShare` (uint256): Total allocation for this bucket; `entropy` (uint256): Current entropy; `winnerCount` (uint16): Winners to select; `dgnrsReward` (uint256): DGNRS reward for solo bucket |
| **Returns** | `entropyState` (uint256): Updated entropy; `ethDelta` (uint256): ETH credited; `liabilityDelta` (uint256): Claimable liability added; `ticketSpent` (uint256): ETH converted to whale passes |

**State Reads:** `traitBurnTicket[lvl]`, `deityBySymbol`, `claimableWinnings`, `autoRebuyState`, `gameOver`
**State Writes:** `claimableWinnings`, `whalePassClaims`, `futurePrizePool` (via _processSoloBucketWinner / _addClaimableEth)

**Callers:** `_processOneBucket`
**Callees:** `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `_creditJackpot`, `_processSoloBucketWinner`, `_addClaimableEth`, `dgnrs.transferFromPool`

**ETH Flow:**
- **COIN path** (`payCoin=true`): Calls `_creditJackpot(true, ...)` -> `coin.creditFlip(beneficiary, amount)` for each winner. Returns `(entropyState, 0, 0, 0)` -- no ETH liability.
- **ETH path** (`payCoin=false`):
  - **Solo bucket** (`winnerCount == 1`): Calls `_processSoloBucketWinner` which does 75/25 split: 75% ETH to claimable, 25% as whale passes. If 25% < HALF_WHALE_PASS_PRICE (2.175 ETH), pays 100% as ETH.
  - **Multi-winner bucket**: Calls `_addClaimableEth(w, perWinner, entropyState)` for each winner.
- DGNRS reward: First solo bucket winner gets `dgnrs.transferFromPool(Pool.Reward, w, dgnrsReward)`.

**Deity virtual entries:** The `_randTraitTicketWithIndices` function includes virtual deity entries (2% of bucket, min 2), so deity pass holders can win jackpots even without physical tickets.

**Invariants:**
- `perWinner = traitShare / totalCount` -- integer division, dust stays in contract.
- Duplicates allowed in winner selection (by design -- more tickets = more chances).
- `winnerCount` capped at MAX_BUCKET_WINNERS (250).
- DGNRS reward only paid to first winner (solo bucket, `!dgnrsPaid` guard).
- Entropy derivation: `entropyState ^ (traitIdx << 64) ^ traitShare` -- unique per bucket.
- Salt for `_randTraitTicketWithIndices` is `200 + traitIdx` -- unique per bucket within a jackpot.

**NatSpec Accuracy:** Matches well. Documents the 3-step flow (early exit, winner selection, credit).

**Gas Flags:** None. Well-structured with early exits.

**Verdict:** CORRECT

---

### `_creditJackpot(bool payInCoin, address beneficiary, uint256 amount, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditJackpot(bool payInCoin, address beneficiary, uint256 amount, uint256 entropy) private returns (uint256 claimableDelta)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `payInCoin` (bool): If true, pay BURNIE via coin.creditFlip; `beneficiary` (address): Winner; `amount` (uint256): Amount to credit; `entropy` (uint256): For auto-rebuy roll |
| **Returns** | `uint256`: Amount to add to claimablePool (0 for COIN path) |

**State Reads:** Via `_addClaimableEth` (autoRebuyState, claimableWinnings)
**State Writes:** Via `_addClaimableEth` or `coin.creditFlip`

**Callers:** `_resolveTraitWinners`, `_processSoloBucketWinner` (via _resolveTraitWinners)
**Callees:** `coin.creditFlip` (COIN path), `_addClaimableEth` (ETH path)

**ETH Flow:**
- COIN: `coin.creditFlip(beneficiary, amount)` -- external call to BurnieCoin module. Returns 0 liability.
- ETH: `_addClaimableEth(beneficiary, amount, entropy)` -- credits to claimableWinnings or converts to auto-rebuy tickets. Returns the claimable delta.

**Invariants:**
- COIN path never affects ETH accounting.
- ETH path liability is tracked by caller to avoid per-winner SSTORE cost (batch update to claimablePool).

**NatSpec Accuracy:** Matches. "Credits a jackpot winner with COIN or ETH; no-op if beneficiary is invalid."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_processSoloBucketWinner(address winner, uint256 perWinner, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processSoloBucketWinner(address winner, uint256 perWinner, uint256 entropy) private returns (uint256 claimableDelta, uint256 ethPaid, uint256 lootboxSpent, uint256 newEntropy)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `winner` (address): Solo bucket winner; `perWinner` (uint256): Total ETH for this bucket; `entropy` (uint256): Current entropy state |
| **Returns** | `claimableDelta` (uint256): Claimable liability; `ethPaid` (uint256): Total ETH value credited; `lootboxSpent` (uint256): ETH moved to futurePrizePool for whale passes; `newEntropy` (uint256): Updated entropy |

**State Reads:** Via `_creditJackpot` -> `_addClaimableEth`
**State Writes:** `whalePassClaims[winner]`, `futurePrizePool` (directly); `claimableWinnings` (via _creditJackpot)

**Callers:** `_resolveTraitWinners`
**Callees:** `_creditJackpot`

**ETH Flow:**
- **75/25 split path** (when `quarterAmount >= HALF_WHALE_PASS_PRICE`):
  - `whalePassCount = quarterAmount / HALF_WHALE_PASS_PRICE` whale passes queued.
  - `whalePassSpent = whalePassCount * HALF_WHALE_PASS_PRICE` moved to `futurePrizePool`.
  - `ethAmount = perWinner - whalePassSpent` credited as claimable ETH.
  - Difference from multi-winner: solo gets whale passes, multi-winner gets pure ETH.
- **Full ETH path** (when `quarterAmount < HALF_WHALE_PASS_PRICE`, i.e., `perWinner < 4 * 2.175 = 8.7 ETH`):
  - Full `perWinner` credited as claimable ETH.

**Invariants:**
- `whalePassSpent + ethAmount == perWinner` (no dust loss).
- `whalePassSpent` goes to `futurePrizePool` (recycled into prize pool, backing the whale pass value).
- `lootboxSpent` is added to `ctx.totalPaidEth` by the caller, ensuring pool accounting is correct.

**NatSpec Accuracy:** NatSpec says "lootboxSpent" is "Amount moved to futurePrizePool from whale pass conversion" which is accurate for the current code, though the return name `lootboxSpent` is a legacy name (it's whale passes, not loot boxes).

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_getWinningTraits(uint256 randomWord)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _getWinningTraits(uint256 randomWord) private view returns (uint8[4] memory w)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `randomWord` (uint256): VRF entropy |
| **Returns** | `uint8[4]`: Four winning trait IDs, one per quadrant |

**State Reads:** `dailyHeroWagers` (via `_topHeroSymbol`)
**State Writes:** None

**Callers:** `_rollWinningTraits` (when `useBurnCounts=true`)
**Callees:** `_topHeroSymbol`, `_calculateDayIndex`

**ETH Flow:** None.

**Trait derivation logic:**
- Q0: `(color << 3) | sym` where `color = randomWord & 7`, `sym = 0` (fixed symbol 0). Range: 0-56 in steps of 8.
- Q1: `64 + (color << 3) | sym` where `color = (randomWord >> 3) & 7`, `sym = 0`. Range: 64-120.
- Q2: `128 + (color << 3) | sym` where `color = (randomWord >> 6) & 7`, `sym = 0`. Range: 128-184.
- Q3: `192 + (randomWord >> 9) & 63`. Fully random within quadrant 3.
- Hero override: If a top hero symbol exists for today's day index, that symbol's quadrant is overridden with `(quadrant << 6) | (heroColor << 3) | heroSymbol`.

**Invariants:**
- Q0-Q2 are fixed to symbol 0, varying only by color (8 options each). This concentrates winning into symbol-0 trait pools, creating a "burn-weighted" distribution (symbol 0 traits likely have more tickets since they're common).
- Q3 is fully random across 64 trait options.
- Hero override replaces exactly one quadrant.

**NatSpec Accuracy:** Matches. Documents base path and hero override.

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_topHeroSymbol(uint48 day)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _topHeroSymbol(uint48 day) private view returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `day` (uint48): Day index to query |
| **Returns** | `hasWinner` (bool): Whether any hero wager exists; `winQuadrant` (uint8): Winning quadrant (0-3); `winSymbol` (uint8): Winning symbol (0-7) |

**State Reads:** `dailyHeroWagers[day][q]` for q in 0..3
**State Writes:** None

**Callers:** `_getWinningTraits`
**Callees:** None

**ETH Flow:** None.

**Algorithm:** Linear scan across all 4 quadrants x 8 symbols = 32 entries. Each quadrant's wagers are packed into a uint256 as 8 x uint32 amounts. The symbol with the highest amount wins. Tie-breaker: first-seen order (q ascending, symbol ascending).

**Invariants:**
- Returns `hasWinner=false` if all amounts are 0.
- Deterministic: same day always produces same result given same state.

**NatSpec Accuracy:** Matches. "Returns the top hero symbol for a day across all quadrants."

**Gas Flags:** 4 cold storage reads for `dailyHeroWagers[day][0..3]`. Acceptable for a once-per-jackpot call.

**Verdict:** CORRECT

---

### `_rollWinningTraits(uint24 lvl, uint256 randWord, bool useBurnCounts)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollWinningTraits(uint24 lvl, uint256 randWord, bool useBurnCounts) private view returns (uint32 packed)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Current level (unused); `randWord` (uint256): VRF entropy; `useBurnCounts` (bool): If true, use burn-weighted traits; if false, use fully random traits |
| **Returns** | `uint32`: 4 packed trait IDs (8 bits each) |

**State Reads:** Via `_getWinningTraits` -> `_topHeroSymbol` (dailyHeroWagers)
**State Writes:** None

**Callers:** `payDailyJackpot` (both daily and early-burn paths), `payDailyCoinJackpot`, `runTerminalJackpot`
**Callees:** `_getWinningTraits` (burn-weighted path), `JackpotBucketLib.getRandomTraits` (random path), `JackpotBucketLib.packWinningTraits`

**ETH Flow:** None.

**Trait selection paths:**
- **Burn-weighted** (`useBurnCounts=true`): Uses `_getWinningTraits` which favors symbol 0 (Q0-Q2) and allows hero override. Used during daily jackpots and terminal jackpots.
- **Random** (`useBurnCounts=false`): Uses `JackpotBucketLib.getRandomTraits` which derives 4 fully random traits using 6-bit sub-ranges per quadrant. Used during early-burn jackpots.

**Invariants:**
- `lvl` parameter is explicitly silenced (`lvl;`). This is intentional -- traits are not level-dependent.
- Both paths produce valid packed traits with correct quadrant prefixes.

**NatSpec Accuracy:** Matches. "Roll or derive the packed winning traits for a given level."

**Gas Flags:** The `lvl` parameter is unused -- could be removed, but it's part of the interface for future flexibility.

**Verdict:** CORRECT

---

### `_syncDailyWinningTraits(uint24 lvl, uint32 packed, uint48 questDay)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _syncDailyWinningTraits(uint24 lvl, uint32 packed, uint48 questDay) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `packed` (uint32): Packed winning traits; `questDay` (uint48): Current day index |
| **Returns** | None |

**State Reads:** None
**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay`

**Callers:** `payDailyJackpot`, `payDailyCoinJackpot`
**Callees:** None

**ETH Flow:** None.

**Invariants:**
- Stores the winning traits so they can be reused by subsequent calls on the same day (e.g., Phase 2 coin+ticket distribution).
- Three storage writes per call.

**NatSpec Accuracy:** No NatSpec. Function is self-documenting.

**Gas Flags:** 3 SSTOREs. Acceptable for once-per-jackpot frequency.

**Verdict:** CORRECT

---

### `_loadDailyWinningTraits(uint24 lvl, uint48 questDay)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _loadDailyWinningTraits(uint24 lvl, uint48 questDay) private view returns (uint32 packed, bool valid)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Level to check; `questDay` (uint48): Day to check |
| **Returns** | `packed` (uint32): Stored winning traits; `valid` (bool): True if traits match the requested day and level |

**State Reads:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotDay`, `lastDailyJackpotLevel`
**State Writes:** None

**Callers:** `payDailyCoinJackpot`
**Callees:** None

**ETH Flow:** None.

**Invariants:**
- `valid = (lastDailyJackpotDay == questDay && lastDailyJackpotLevel == lvl)` -- ensures traits are only reused within the same day and level.
- If `!valid`, caller must re-roll traits.

**NatSpec Accuracy:** No NatSpec. Function is self-documenting.

**Gas Flags:** 3 SLOADs. All should be warm if called after `_syncDailyWinningTraits`.

**Verdict:** CORRECT

---

### `payDailyCoinJackpot(uint24 lvl, uint256 randWord)` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current game level; `randWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `price`, `levelPrizePool[lvl-1]`, `lastDailyJackpotWinningTraits`, `lastDailyJackpotDay`, `lastDailyJackpotLevel`, `jackpotPhaseFlag`, `traitBurnTicket`, `deityBySymbol`, `dailyHeroWagers`, `ticketQueue`
**State Writes:** `lastDailyJackpotWinningTraits`, `lastDailyJackpotLevel`, `lastDailyJackpotDay` (via _syncDailyWinningTraits)

**Callers:** Parent game contract via delegatecall (from AdvanceModule)
**Callees:** `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_loadDailyWinningTraits`, `_rollWinningTraits`, `_syncDailyWinningTraits`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`

**ETH Flow:** No ETH moved. BURNIE only.

**BURNIE distribution:**
1. Budget = `_calcDailyCoinBudget(lvl)` = 0.5% of levelPrizePool[lvl-1] in BURNIE terms.
2. 25% (`farBudget`) -> `_awardFarFutureCoinJackpot` (ticketQueue-based, levels lvl+5 to lvl+99).
3. 75% (`nearBudget`) -> `_awardDailyCoinToTraitWinners` (trait-matched, levels lvl to lvl+4).
4. If no valid winning traits for today, re-rolls and syncs.
5. Target level selected randomly from [lvl, lvl+4] that has trait tickets.

**Invariants:**
- No ETH accounting changes.
- Trait reuse: loads previously synced traits for same day/level to ensure consistent winning traits across ETH and COIN jackpots.
- `jackpotPhaseFlag` determines burn-weighted vs random trait selection for fresh rolls.

**NatSpec Accuracy:** Matches. Documents the 75/25 split and ticket-based distribution.

**Gas Flags:** Multiple external calls to `coin.creditFlip` / `coin.creditFlipBatch`. These are gas-bounded by DAILY_COIN_MAX_WINNERS (50) and FAR_FUTURE_COIN_SAMPLES (10).

**Verdict:** CORRECT

---

### `_selectDailyCoinTargetLevel(uint24 lvl, uint32 winningTraitsPacked, uint256 entropy)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _selectDailyCoinTargetLevel(uint24 lvl, uint32 winningTraitsPacked, uint256 entropy) private view returns (uint24 targetLevel)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Current level; `winningTraitsPacked` (uint32): Packed traits; `entropy` (uint256): For random start offset |
| **Returns** | `uint24`: Target level (0 if no eligible level found) |

**State Reads:** `traitBurnTicket`, `deityBySymbol` (via `_hasTraitTickets`)
**State Writes:** None

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `_hasTraitTickets`

**ETH Flow:** None.

**Algorithm:** Random start offset `= entropy % 5`, then probes [lvl, lvl+1, ..., lvl+4] cyclically. Returns first level that has trait tickets (or virtual deity entries). Returns 0 if none found.

**Invariants:**
- At most 5 iterations (bounded).
- Returns 0 gracefully if no eligible level found -- caller skips coin distribution.

**NatSpec Accuracy:** Matches. "Pick a random target level in [lvl, lvl+4] that has winners."

**Gas Flags:** Up to 5 iterations x 4 trait checks = 20 storage reads. Acceptable.

**Verdict:** CORRECT

---

### `_awardDailyCoinToTraitWinners(uint24 lvl, uint32 winningTraitsPacked, uint256 coinBudget, uint256 entropy)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardDailyCoinToTraitWinners(uint24 lvl, uint32 winningTraitsPacked, uint256 coinBudget, uint256 entropy) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Target level; `winningTraitsPacked` (uint32): Packed winning traits; `coinBudget` (uint256): BURNIE to distribute; `entropy` (uint256): For winner selection |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl]`, `deityBySymbol`
**State Writes:** None directly (external calls to coin.creditFlipBatch)

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `JackpotBucketLib.unpackWinningTraits`, `_computeBucketCounts`, `EntropyLib.entropyStep`, `_randTraitTicketWithIndices`, `coin.creditFlipBatch`

**ETH Flow:** None. BURNIE only.

**BURNIE distribution:**
1. Cap winners at DAILY_COIN_MAX_WINNERS (50), further capped by `coinBudget` if budget < 50.
2. Compute bucket counts via `_computeBucketCounts` (even split across active traits).
3. `baseAmount = coinBudget / cap`, `extra = coinBudget % cap` (1 extra unit to first `extra` winners via cursor).
4. Select winners per bucket via `_randTraitTicketWithIndices` with salt `DAILY_COIN_SALT_BASE + traitIdx` (252-255).
5. Batch credit via `coin.creditFlipBatch` (3 winners at a time).
6. Leftover batch (< 3 winners) padded with address(0) and 0 amounts before final `creditFlipBatch`.

**Invariants:**
- Total distributed = `baseAmount * cap + extra = coinBudget` (perfect distribution, no dust).
- Winners capped at MAX_BUCKET_WINNERS (250) per bucket.
- Batch size of 3 matches `coin.creditFlipBatch` signature.

**NatSpec Accuracy:** Matches. "Awards BURNIE to random winners from the packed winning traits."

**Gas Flags:** Up to 50 external calls to `coin.creditFlipBatch` in batches of 3 = ~17 external calls max. Acceptable.

**Verdict:** CORRECT

---

### `_awardFarFutureCoinJackpot(uint24 lvl, uint256 farBudget, uint256 rngWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _awardFarFutureCoinJackpot(uint24 lvl, uint256 farBudget, uint256 rngWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Current level; `farBudget` (uint256): BURNIE budget for far-future winners; `rngWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `ticketQueue[candidate]` for up to 10 random levels
**State Writes:** None directly (external calls to coin.creditFlipBatch)

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `EntropyLib.entropyStep`, `coin.creditFlipBatch`

**ETH Flow:** None. BURNIE only.

**ticketQueue sampling logic:**
1. Entropy derivation: `rngWord ^ (lvl << 192) ^ FAR_FUTURE_COIN_TAG`.
2. Samples up to FAR_FUTURE_COIN_SAMPLES (10) random levels in [lvl+5, lvl+99]:
   - `candidate = lvl + 5 + (entropy % 95)` -- covers the full 95-level range.
   - `idx = (entropy >> 32) % len` -- random index within the queue.
   - If `queue[idx]` is not address(0), winner is recorded.
3. Budget split evenly: `perWinner = farBudget / found`.
4. Credited via `coin.creditFlipBatch` (batches of 3).
5. `FarFutureCoinJackpotWinner` event emitted per winner.

**Invariants:**
- Up to 10 winners max (FAR_FUTURE_COIN_SAMPLES).
- If `found == 0`, function returns without distributing (budget is effectively burned/not minted).
- `perWinner * found <= farBudget` -- integer division dust is not distributed. Since these are BURNIE credits (not ETH), the dust is negligible.
- Same level can be sampled multiple times (no dedup). This is acceptable -- it naturally weights toward levels with more queued players.

**NatSpec Accuracy:** Matches. "Awards 25% of the BURNIE coin budget to random ticket holders on far-future levels."

**Gas Flags:** Up to 10 storage reads for ticketQueue + 4 external calls to coin.creditFlipBatch. Bounded and acceptable.

**Verdict:** CORRECT

