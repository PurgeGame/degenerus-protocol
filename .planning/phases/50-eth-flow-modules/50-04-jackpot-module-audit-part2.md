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

---

## Ticket Batch Processing

### `_resolveZeroOwedRemainder(uint40 packed, uint24 lvl, address player, uint256 entropy, uint256 rollSalt)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _resolveZeroOwedRemainder(uint40 packed, uint24 lvl, address player, uint256 entropy, uint256 rollSalt) private returns (uint40 newPacked, bool skip)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `packed` (uint40): Packed ticket owed (owed:32, remainder:8); `lvl` (uint24): Level; `player` (address): Ticket holder; `entropy` (uint256): VRF entropy; `rollSalt` (uint256): Deterministic salt for remainder roll |
| **Returns** | `newPacked` (uint40): Updated packed value; `skip` (bool): True if player should be skipped |

**State Reads:** None (packed passed in)
**State Writes:** `ticketsOwedPacked[lvl][player]` (cleared or updated)

**Callers:** `_processOneTicketEntry`
**Callees:** `_rollRemainder`

**ETH Flow:** None.

**Logic:**
1. Extract `rem = uint8(packed)` (fractional remainder, 0-99).
2. If `rem == 0`: Clear storage if packed was non-zero, return skip=true.
3. If `rem != 0`: Roll `_rollRemainder(entropy, rollSalt, rem)` -- `rem%` chance of winning 1 extra ticket.
   - Win: Set `newPacked = 1 << 8` (1 ticket owed, 0 remainder). Update storage if changed.
   - Lose: Clear storage, return skip=true.

**Invariants:**
- Handles the edge case where a player's owed count is 0 but they have a fractional remainder.
- The remainder roll is deterministic (same entropy + salt = same result).
- Storage is only written if the value actually changes (gas optimization).

**NatSpec Accuracy:** Matches. "Resolves the zero-owed remainder case for ticket processing."

**Gas Flags:** 1 SSTORE on average (either clear or update). Efficient.

**Verdict:** CORRECT

---

### `_processOneTicketEntry(address player, uint24 lvl, uint32 room, uint32 processed, uint256 entropy, uint256 queueIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _processOneTicketEntry(address player, uint24 lvl, uint32 room, uint32 processed, uint256 entropy, uint256 queueIdx) private returns (uint32 writesUsed, bool advance)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `lvl` (uint24): Level; `room` (uint32): Remaining SSTORE budget; `processed` (uint32): Tickets already processed this entry; `entropy` (uint256): VRF entropy; `queueIdx` (uint256): Position in ticketQueue |
| **Returns** | `writesUsed` (uint32): SSTOREs consumed; `advance` (bool): True if this entry is complete |

**State Reads:** `ticketsOwedPacked[lvl][player]`
**State Writes:** `ticketsOwedPacked[lvl][player]` (via `_finalizeTicketEntry`); `traitBurnTicket` (via `_generateTicketBatch`)

**Callers:** `processTicketBatch`
**Callees:** `_resolveZeroOwedRemainder`, `_generateTicketBatch`, `_finalizeTicketEntry`

**ETH Flow:** None.

**Processing logic:**
1. Load packed owed: `owed = uint32(packed >> 8)`, remainder = `uint8(packed)`.
2. If `owed == 0`: Handle via `_resolveZeroOwedRemainder`. Charge 1 budget unit even on skip.
3. Calculate overhead: `baseOv = 4` (first batch with <=2 owed) or `2` (subsequent).
4. Calculate batch size `take`: `min(owed, maxT)` where `maxT` depends on available room.
   - If `availRoom <= 256`: `maxT = availRoom / 2` (2 writes per ticket: array push + count).
   - If `availRoom > 256`: `maxT = availRoom - 256` (amortized overhead for large batches).
5. Generate trait tickets via `_generateTicketBatch`.
6. Calculate writesUsed: `(take <= 256 ? take*2 : take+256) + baseOv + (take==owed ? 1 : 0)`.
7. Finalize via `_finalizeTicketEntry`.

**Invariants:**
- `rollSalt = (lvl << 224) | (queueIdx << 192) | (player << 32)` -- deterministic per-entry.
- Budget accounting ensures gas stays within block limits.
- Returns `(0, false)` when budget is exhausted (signals caller to stop).

**NatSpec Accuracy:** Matches. "Processes a single ticket entry, returning writes used and whether to advance."

**Gas Flags:** The writes-used formula accurately models the SSTORE cost of `_raritySymbolBatch` assembly. The threshold at 256 accounts for the trait-counting overhead in memory.

**Verdict:** CORRECT

---

### `_generateTicketBatch(address player, uint24 lvl, uint32 processed, uint32 take, uint256 entropy, uint256 queueIdx)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _generateTicketBatch(address player, uint24 lvl, uint32 processed, uint32 take, uint256 entropy, uint256 queueIdx) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `lvl` (uint24): Level; `processed` (uint32): Start index; `take` (uint32): Count; `entropy` (uint256): VRF entropy; `queueIdx` (uint256): Queue position |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][traitId].length` (via assembly)
**State Writes:** `traitBurnTicket[lvl][traitId]` -- pushes player address N times per trait occurrence

**Callers:** `_processOneTicketEntry`
**Callees:** `_raritySymbolBatch`, emits `TraitsGenerated`

**ETH Flow:** None.

**Algorithm:**
1. Constructs `baseKey = (lvl << 224) | (queueIdx << 192) | (player << 32)`.
2. Delegates to `_raritySymbolBatch` for LCG-based trait generation and storage writes.
3. Emits `TraitsGenerated(player, lvl, queueIdx, processed, take, entropy)`.

**LCG verification (TICKET_LCG_MULT = 0x5851F42D4C957F2D):**
- This is Knuth's MMIX LCG multiplier (6364136223846793005). Full 64-bit period when seed is odd.
- The seed is forced odd via `uint64(seed) | 1`.
- Each group of 16 tickets shares a seed derived from `(baseKey + groupIdx) ^ entropyWord`.
- Within a group, LCG steps produce independent trait values.

**Invariants:**
- Deterministic: same inputs always produce same traits.
- `processed` parameter allows resuming mid-entry (different startIndex each call).

**NatSpec Accuracy:** "Wrapper for _raritySymbolBatch to reduce stack usage." Accurate.

**Gas Flags:** None. Assembly-optimized batch writes.

**Verdict:** CORRECT

---

### `_finalizeTicketEntry(uint24 lvl, address player, uint40 packed, uint32 owed, uint32 take, uint256 entropy, uint256 rollSalt)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _finalizeTicketEntry(uint24 lvl, address player, uint40 packed, uint32 owed, uint32 take, uint256 entropy, uint256 rollSalt) private returns (bool done)` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `lvl` (uint24): Level; `player` (address): Ticket holder; `packed` (uint40): Current packed state; `owed` (uint32): Total owed; `take` (uint32): Processed this batch; `entropy` (uint256): VRF entropy; `rollSalt` (uint256): Salt for remainder roll |
| **Returns** | `bool`: True if entry is complete |

**State Reads:** None (packed passed in)
**State Writes:** `ticketsOwedPacked[lvl][player]` (updated or unchanged)

**Callers:** `_processOneTicketEntry`
**Callees:** `_rollRemainder`

**ETH Flow:** None.

**Logic:**
1. `remainingOwed = owed - take` (unchecked -- safe because `take <= owed`).
2. If `remainingOwed == 0` and `rem != 0`: Roll remainder. If win, set `remainingOwed = 1`. Clear `rem`.
3. Pack new value: `(remainingOwed << 8) | rem`.
4. Write to storage only if changed.
5. Return `remainingOwed == 0` (done).

**Invariants:**
- Remainder is only rolled when all owed tickets are processed (`remainingOwed == 0`).
- After remainder roll: either 0 or 1 ticket owed, remainder cleared.
- Storage write only when value changes (gas optimization).

**NatSpec Accuracy:** Matches. "Finalizes ticket entry after processing, rolling remainder dust."

**Gas Flags:** 0-1 SSTOREs. Efficient.

**Verdict:** CORRECT

---

### `_rollRemainder(uint256 entropy, uint256 rollSalt, uint8 rem)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _rollRemainder(uint256 entropy, uint256 rollSalt, uint8 rem) private pure returns (bool win)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `entropy` (uint256): VRF entropy; `rollSalt` (uint256): Deterministic salt; `rem` (uint8): Remainder value (0-99) |
| **Returns** | `bool`: True if remainder roll wins (probability = rem/100) |

**State Reads:** None
**State Writes:** None

**Callers:** `_resolveZeroOwedRemainder`, `_finalizeTicketEntry`
**Callees:** `EntropyLib.entropyStep`

**ETH Flow:** None.

**Fairness verification:**
- `rollEntropy = EntropyLib.entropyStep(entropy ^ rollSalt)` -- xorshift64 derivation.
- `win = (rollEntropy % TICKET_SCALE) < rem` where `TICKET_SCALE = 100`.
- For `rem = 50`: 50% chance. For `rem = 1`: 1% chance. For `rem = 99`: 99% chance.
- The modulo bias is negligible for a 256-bit input modulo 100.

**Invariants:**
- `rem` must be in range 0-99 (guaranteed by the packing format: uint8 with max 99 from ticket scaling).
- `rem = 0` means 0% chance (but callers check for this before calling).
- Deterministic: same entropy + salt = same result.

**NatSpec Accuracy:** Matches. "Roll remainder chance for a fractional ticket (0-99)."

**Gas Flags:** None. Single computation.

**Verdict:** CORRECT

---

### `_raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _raritySymbolBatch(address player, uint256 baseKey, uint32 startIndex, uint32 count, uint256 entropyWord) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `player` (address): Ticket holder; `baseKey` (uint256): Encoded (lvl, queueIdx, player); `startIndex` (uint32): Starting ticket index; `count` (uint32): Tickets to generate; `entropyWord` (uint256): VRF entropy |
| **Returns** | None |

**State Reads:** `traitBurnTicket[lvl][traitId].length` (via assembly)
**State Writes:** `traitBurnTicket[lvl][traitId]` -- appends player address for each trait occurrence (via assembly)

**Callers:** `_generateTicketBatch`
**Callees:** `DegenerusTraitUtils.traitFromWord`

**ETH Flow:** None.

**Algorithm:**
1. **Trait generation** (groups of 16 using LCG):
   - For each group of 16 tickets: `seed = (baseKey + groupIdx) ^ entropyWord`.
   - `s = uint64(seed) | 1` (force odd for full LCG period).
   - LCG step: `s = s * TICKET_LCG_MULT + 1` per ticket.
   - Trait: `DegenerusTraitUtils.traitFromWord(s) + (uint8(i & 3) << 6)` -- adds quadrant from ticket index mod 4.
   - Tracks unique traits and occurrence counts in memory arrays.

2. **Batch storage writes** (assembly):
   - For each unique trait: load array length, extend by occurrences, write player address.
   - Uses keccak256-based storage slot calculation matching Solidity's dynamic array layout.

**DegenerusTraitUtils.traitFromWord verification:**
- Takes uint64, splits into low 32 (category via `weightedBucket`) and high 32 (sub via `weightedBucket`).
- Returns 6-bit trait: `(category << 3) | sub`.
- Quadrant bits (2 MSBs) added by caller: `(i & 3) << 6`.
- Result is full 8-bit trait ID: `[QQ][CCC][SSS]`.

**Invariants:**
- LCG produces deterministic, non-repeating sequence within each 16-ticket group.
- Quadrant assignment cycles through 0,1,2,3 based on ticket index, ensuring balanced distribution.
- Assembly writes are memory-safe (declared with `"memory-safe"` annotation).
- Storage slot calculation matches Solidity compiler's layout for `mapping(uint24 => address[][256])`.

**NatSpec Accuracy:** Matches. Documents the 3-step algorithm (generate, track, batch-write).

**Gas Flags:** Assembly-optimized. ~2 SSTOREs per ticket (array length update + data slot write). This is the minimum possible for appending to a storage array.

**Verdict:** CORRECT

---

## Winner Selection

### `_randTraitTicket(address[][256] storage traitBurnTicket_, uint256 randomWord, uint8 trait, uint8 numWinners, uint8 salt)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _randTraitTicket(address[][256] storage traitBurnTicket_, uint256 randomWord, uint8 trait, uint8 numWinners, uint8 salt) private view returns (address[] memory winners)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `traitBurnTicket_` (storage ref): Trait ticket mapping; `randomWord` (uint256): VRF entropy; `trait` (uint8): Trait ID; `numWinners` (uint8): Winners to select (max 255); `salt` (uint8): Additional entropy differentiation |
| **Returns** | `address[]`: Selected winner addresses (may contain duplicates) |

**State Reads:** `traitBurnTicket_[trait].length`, `traitBurnTicket_[trait][idx]`, `deityBySymbol[fullSymId]`
**State Writes:** None

**Callers:** `_runEarlyBirdLootboxJackpot`, `_distributeTicketsToBucket`, `awardFinalDayDgnrsReward`
**Callees:** None

**ETH Flow:** None.

**Winner selection algorithm:**
1. `effectiveLen = len + virtualCount` where `virtualCount = max(len/50, 2)` if deity exists for this symbol.
2. Entropy derivation: `slice = randomWord ^ (trait << 128) ^ (salt << 192)`.
3. For each winner: `idx = slice % effectiveLen`. If `idx < len`, select from holders. If `idx >= len`, select deity.
4. Advance: `slice = (slice >> 16) | (slice << 240)` -- 16-bit rotation per winner.

**Deity virtual entries:**
- `fullSymId = (trait >> 6) * 8 + (trait & 0x07)` -- maps trait to one of 32 unique symbols.
- If `deityBySymbol[fullSymId] != address(0)`, deity gets `virtualCount` virtual entries.
- `virtualCount = max(len/50, 2)` -- floor(2% of bucket tickets), minimum 2.
- Deity can win multiple times (duplicates allowed).

**Duplicate handling:**
- Duplicates are intentionally allowed. A player with N tickets in the pool has N/effectiveLen probability of being selected per draw. Multiple draws mean they can win multiple times.

**Empty array handling:**
- If `effectiveLen == 0 || numWinners == 0`: returns empty array. Graceful.

**Entropy quality:**
- 16-bit rotation means after 16 winners, the entropy repeats. However, `numWinners` is capped at MAX_BUCKET_WINNERS (250), so with `effectiveLen` typically much larger than 2^16, the selection remains well-distributed. For small pools (< 16 entries), the modulo operation provides sufficient differentiation.

**Invariants:**
- Deterministic: same inputs = same winners.
- Salt prevents different callers with same randomWord from selecting the same winners.
- No storage mutations -- safe for view context.

**NatSpec Accuracy:** Matches. Documents duplicates, virtual deity entries, and selection algorithm.

**Gas Flags:** Up to 250 storage reads for `holders[idx]`. Each is a cold read on first access but may be warm for duplicates.

**Verdict:** CORRECT

---

### `_randTraitTicketWithIndices(address[][256] storage traitBurnTicket_, uint256 randomWord, uint8 trait, uint8 numWinners, uint8 salt)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _randTraitTicketWithIndices(address[][256] storage traitBurnTicket_, uint256 randomWord, uint8 trait, uint8 numWinners, uint8 salt) private view returns (address[] memory winners, uint256[] memory ticketIndexes)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | Same as `_randTraitTicket` |
| **Returns** | `winners` (address[]): Selected winners; `ticketIndexes` (uint256[]): Corresponding ticket indices (uint256.max for deity virtual entries) |

**State Reads:** Same as `_randTraitTicket`
**State Writes:** None

**Callers:** `_processDailyEthChunk`, `_resolveTraitWinners`, `_awardDailyCoinToTraitWinners`
**Callees:** None

**ETH Flow:** None.

**Behavior comparison with `_randTraitTicket`:**
- Identical winner selection algorithm (same entropy derivation, same rotation, same deity logic).
- Additionally returns `ticketIndexes[i]`: the actual index in the holders array, or `type(uint256).max` for deity virtual entries.
- Used for `JackpotTicketWinner` event emission which includes the winning ticket index.

**Invariants:**
- Same inputs produce same winners as `_randTraitTicket` (algorithms are identical).
- `ticketIndexes[i] == type(uint256).max` iff `winners[i] == deity`.

**NatSpec Accuracy:** Matches. "Same selection as _randTraitTicket plus winner ticket indices."

**Gas Flags:** Same as `_randTraitTicket` + memory allocation for ticketIndexes array.

**Verdict:** CORRECT

---

## Utility Helpers

### `_calculateDayIndex()` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _calculateDayIndex() private view returns (uint48)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | None |
| **Returns** | `uint48`: Day index (1-indexed from deploy day) |

**State Reads:** Via `_simulatedDayIndex` (reads `block.timestamp` and storage for testnet offset)
**State Writes:** None

**Callers:** `payDailyJackpot`, `_getWinningTraits`, `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** `_simulatedDayIndex` (inherited from DegenerusGameStorage)

**ETH Flow:** None.

**Day boundary:** Days reset at JACKPOT_RESET_TIME = 82620 seconds = 22:57 UTC. Day 1 corresponds to deploy day.

**Invariants:**
- Single delegate to `_simulatedDayIndex()` which handles testnet time simulation.
- Monotonically increasing within a level (time only moves forward).

**NatSpec Accuracy:** Matches. "Calculate current day index with testnet offset applied."

**Gas Flags:** None.

**Verdict:** CORRECT

---

### `_creditDgnrsCoinflip(uint256 prizePoolWei)` [private]

| Field | Value |
|-------|-------|
| **Signature** | `function _creditDgnrsCoinflip(uint256 prizePoolWei) private` |
| **Visibility** | private |
| **Mutability** | state-changing |
| **Parameters** | `prizePoolWei` (uint256): Current prize pool size |
| **Returns** | None |

**State Reads:** `price`
**State Writes:** None directly (external call to coin.creditFlip)

**Callers:** `consolidatePrizePools`
**Callees:** `coin.creditFlip`

**ETH Flow:** None. Credits BURNIE to DGNRS contract address for coinflip rewards.

**BURNIE calculation:**
- `coinAmount = (prizePoolWei * PRICE_COIN_UNIT) / (priceWei * 20)`
- PRICE_COIN_UNIT = 1000 ether (1000 BURNIE per ETH at reference price).
- Effective: `coinAmount = prizePoolWei * 1000 / (price * 20) = prizePoolWei * 50 / price`.
- This credits 5% of the prize pool's BURNIE-equivalent to the DGNRS coinflip system.

**Invariants:**
- No-op if `price == 0` (division by zero protection).
- No-op if `coinAmount == 0` (small prize pools).
- Credits go to `ContractAddresses.DGNRS` address.

**NatSpec Accuracy:** No NatSpec. Function name is self-documenting.

**Gas Flags:** 1 external call to `coin.creditFlip`. Acceptable.

**Verdict:** CORRECT

---

### `_calcDailyCoinBudget(uint24 lvl)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _calcDailyCoinBudget(uint24 lvl) private view returns (uint256)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Current level |
| **Returns** | `uint256`: Daily BURNIE budget in wei-equivalent |

**State Reads:** `price`, `levelPrizePool[lvl - 1]`
**State Writes:** None

**Callers:** `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** None

**ETH Flow:** None. Pure calculation.

**Budget formula:**
- `(levelPrizePool[lvl - 1] * PRICE_COIN_UNIT) / (priceWei * 200)`
- `= levelPrizePool[lvl-1] * 1000 / (price * 200)`
- `= levelPrizePool[lvl-1] * 5 / price`
- This is 0.5% of the level's prize pool expressed in BURNIE units.

**Invariants:**
- Uses `lvl - 1` to reference the previous level's prize pool (the pool that was accumulated during purchases).
- No-op (returns 0) if `price == 0`.

**NatSpec Accuracy:** Matches. "Calculate 0.5% of prize pool target in BURNIE."

**Gas Flags:** 2 SLOADs (price + levelPrizePool). Both likely warm in jackpot context.

**Verdict:** CORRECT

---

### `_dailyCurrentPoolBps(uint8 counter, uint256 randWord)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _dailyCurrentPoolBps(uint8 counter, uint256 randWord) private pure returns (uint16 bps)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `counter` (uint8): Jackpot day counter (0-4); `randWord` (uint256): VRF entropy |
| **Returns** | `uint16`: Basis points of currentPrizePool to distribute |

**State Reads:** None
**State Writes:** None

**Callers:** `payDailyJackpot` (daily path)
**Callees:** None

**ETH Flow:** None. Determines the percentage of currentPrizePool to distribute.

**BPS calculation:**
- Day 5 (`counter >= JACKPOT_LEVEL_CAP - 1 = 4`): Returns 10000 (100%).
- Days 1-4: `seed = keccak256(randWord, DAILY_CURRENT_BPS_TAG, counter)`.
  - `bps = DAILY_CURRENT_BPS_MIN + (seed % range)` where range = 1400 - 600 + 1 = 801.
  - Result: uniform random in [600, 1400] = [6%, 14%], average 10%.

**Bounds verification:**
- Minimum: 600 bps = 6%.
- Maximum: 600 + 800 = 1400 bps = 14%.
- Range = 1400 - 600 + 1 = 801 values. Uniform distribution.
- Day 5: 10000 bps = 100%. All remaining currentPrizePool distributed.

**Invariants:**
- Counter-dependent entropy (counter is part of keccak256 input), so each day gets a different percentage.
- Deterministic: same randWord + counter = same bps.

**NatSpec Accuracy:** Matches. "Days 1-4: random 6%-14% (avg 10%). Day 5: 100%."

**Gas Flags:** Single keccak256. Efficient.

**Verdict:** CORRECT

---

### `_hasActualTraitTickets(uint24 lvl, uint32 packedTraits)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _hasActualTraitTickets(uint24 lvl, uint32 packedTraits) private view returns (bool)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Level to check; `packedTraits` (uint32): Packed winning traits |
| **Returns** | `bool`: True if any winning trait has non-virtual tickets at this level |

**State Reads:** `traitBurnTicket[lvl][traitIds[i]].length` for i in 0..3
**State Writes:** None

**Callers:** `_highestCarryoverSourceOffset`, `_selectCarryoverSourceOffset`
**Callees:** `JackpotBucketLib.unpackWinningTraits`

**ETH Flow:** None.

**Difference from `_hasTraitTickets`:**
- `_hasTraitTickets` checks both actual tickets AND virtual deity entries.
- `_hasActualTraitTickets` only checks actual tickets (non-zero array length).
- Used for carryover source selection where deity-only levels should not be eligible (deity entries are virtual, not backed by actual ticket purchases).

**Invariants:**
- Returns true if ANY of the 4 winning traits has at least 1 actual ticket at the level.

**NatSpec Accuracy:** Matches. "Return true if any winning trait has actual (non-virtual) tickets."

**Gas Flags:** Up to 4 SLOADs for array lengths. Acceptable.

**Verdict:** CORRECT

---

### `_highestCarryoverSourceOffset(uint24 lvl, uint32 winningTraitsPacked)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _highestCarryoverSourceOffset(uint24 lvl, uint32 winningTraitsPacked) private view returns (uint8 offset)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Current level; `winningTraitsPacked` (uint32): Packed traits |
| **Returns** | `uint8`: Highest eligible offset (1-5) or 0 if none |

**State Reads:** Via `_hasActualTraitTickets` (traitBurnTicket)
**State Writes:** None

**Callers:** `_selectCarryoverSourceOffset`
**Callees:** `_hasActualTraitTickets`

**ETH Flow:** None.

**Scan logic:** Iterates from offset 5 down to 1. Returns the first offset where `lvl + offset` has actual trait tickets for the winning traits. Returns 0 if none found.

**Invariants:**
- Maximum offset is DAILY_CARRYOVER_MAX_OFFSET (5), checking levels lvl+5, lvl+4, ..., lvl+1.
- Only considers actual (non-virtual) tickets via `_hasActualTraitTickets`.

**NatSpec Accuracy:** Matches. "Return highest eligible carryover source offset in [1..5] with actual winning-trait tickets."

**Gas Flags:** Up to 5 x 4 = 20 SLOADs. Bounded.

**Verdict:** CORRECT

---

### `_selectCarryoverSourceOffset(uint24 lvl, uint32 winningTraitsPacked, uint256 randWord, uint8 counter)` [private view]

| Field | Value |
|-------|-------|
| **Signature** | `function _selectCarryoverSourceOffset(uint24 lvl, uint32 winningTraitsPacked, uint256 randWord, uint8 counter) private view returns (uint8 offset)` |
| **Visibility** | private |
| **Mutability** | view |
| **Parameters** | `lvl` (uint24): Current level; `winningTraitsPacked` (uint32): Packed traits; `randWord` (uint256): VRF entropy; `counter` (uint8): Jackpot counter |
| **Returns** | `uint8`: Selected carryover source offset (1-5) or 0 if none |

**State Reads:** Via `_highestCarryoverSourceOffset` and `_hasActualTraitTickets`
**State Writes:** None

**Callers:** `payDailyJackpot` (daily path, non-early-bird days)
**Callees:** `_highestCarryoverSourceOffset`, `_hasActualTraitTickets`

**ETH Flow:** None.

**Selection algorithm:**
1. Find `highestEligible` via `_highestCarryoverSourceOffset`.
2. If 0: no eligible source. If 1: only one option, return 1.
3. Random start: `startOffset = (keccak256(randWord, DAILY_CARRYOVER_SOURCE_TAG, counter) % highestEligible) + 1`.
4. Probe all offsets in [1..highestEligible] cyclically from startOffset.
5. Return first offset with actual trait tickets.

**Invariants:**
- Counter-dependent entropy (different carryover source per jackpot day).
- Falls back to 0 if no offset has actual tickets (shouldn't happen if `highestEligible > 0`, but defensive).
- The cyclic probe ensures all eligible offsets are checked.

**NatSpec Accuracy:** Matches. "Select a random eligible carryover source offset in [1..highestEligible]."

**Gas Flags:** Up to 5 x 4 = 20 SLOADs for the probe (worst case all 5 offsets checked). Bounded.

**Verdict:** CORRECT

---

### `_packDailyTicketBudgets(uint8 counterStep, uint256 dailyTicketUnits, uint256 carryoverTicketUnits, uint8 carryoverSourceOffset)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _packDailyTicketBudgets(uint8 counterStep, uint256 dailyTicketUnits, uint256 carryoverTicketUnits, uint8 carryoverSourceOffset) private pure returns (uint256)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `counterStep` (uint8): Counter increment (1 or 2); `dailyTicketUnits` (uint256): Ticket units for daily distribution; `carryoverTicketUnits` (uint256): Ticket units for carryover; `carryoverSourceOffset` (uint8): Carryover source level offset |
| **Returns** | `uint256`: Packed value |

**State Reads:** None
**State Writes:** None

**Callers:** `payDailyJackpot` (daily path)
**Callees:** None

**ETH Flow:** None.

**Bit layout verification:**
```
Bits [7:0]     = counterStep (8 bits)
Bits [71:8]    = dailyTicketUnits (64 bits)
Bits [135:72]  = carryoverTicketUnits (64 bits)
Bits [143:136] = carryoverSourceOffset (8 bits)
Total: 144 bits used out of 256
```

**Packing formula:**
- `counterStep | (dailyTicketUnits << 8) | (carryoverTicketUnits << 72) | (carryoverSourceOffset << 136)`

**Invariants:**
- `dailyTicketUnits` is cast from uint256 but only 64 bits are meaningful (capped by `_budgetToTicketUnits` which returns values fitting in uint64).
- `carryoverTicketUnits` similarly fits in 64 bits.
- No overlap between fields.

**NatSpec Accuracy:** No explicit NatSpec but the packing layout comment in `payDailyJackpot` matches.

**Gas Flags:** None. Pure bitwise operations.

**Verdict:** CORRECT

---

### `_unpackDailyTicketBudgets(uint256 packed)` [private pure]

| Field | Value |
|-------|-------|
| **Signature** | `function _unpackDailyTicketBudgets(uint256 packed) private pure returns (uint8 counterStep, uint256 dailyTicketUnits, uint256 carryoverTicketUnits, uint8 carryoverSourceOffset)` |
| **Visibility** | private |
| **Mutability** | pure |
| **Parameters** | `packed` (uint256): Packed ticket budgets |
| **Returns** | `counterStep` (uint8): Counter increment; `dailyTicketUnits` (uint256): Daily ticket units; `carryoverTicketUnits` (uint256): Carryover ticket units; `carryoverSourceOffset` (uint8): Carryover source offset |

**State Reads:** None
**State Writes:** None

**Callers:** `payDailyJackpot`, `payDailyJackpotCoinAndTickets`
**Callees:** None

**ETH Flow:** None.

**Unpacking formula:**
- `counterStep = uint8(packed)` -- bits [7:0]
- `dailyTicketUnits = uint64(packed >> 8)` -- bits [71:8], masked to 64 bits
- `carryoverTicketUnits = uint64(packed >> 72)` -- bits [135:72], masked to 64 bits
- `carryoverSourceOffset = uint8(packed >> 136)` -- bits [143:136]

**Symmetry verification:** The unpack operations are the exact inverse of the pack operations in `_packDailyTicketBudgets`. The `uint64()` cast on ticket units matches the 64-bit field width, preventing data from bleeding between fields.

**NatSpec Accuracy:** No explicit NatSpec. Self-documenting.

**Gas Flags:** None. Pure bitwise operations.

**Verdict:** CORRECT

---

## ETH Mutation Path Map (Part 2)

### Jackpot ETH Distribution Flow

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | ethPool (from caller) | 4 bucket shares | `JackpotBucketLib.bucketShares(ethPool, shareBps, bucketCounts, remainderIdx, unit)` | `_distributeJackpotEth` |
| 2 | Bucket share | Per-winner amount | `perWinner = share / totalCount` | `_processOneBucket` -> `_resolveTraitWinners` |
| 3a | Per-winner (multi-bucket) | `claimableWinnings[winner]` | Full `perWinner` via `_addClaimableEth` | `_resolveTraitWinners` |
| 3b | Per-winner (solo bucket, >= 8.7 ETH) | 75% `claimableWinnings[winner]` + 25% `whalePassClaims[winner]` + `futurePrizePool` | `ethAmount = perWinner - whalePassSpent` | `_processSoloBucketWinner` |
| 3c | Per-winner (solo bucket, < 8.7 ETH) | `claimableWinnings[winner]` | Full `perWinner` | `_processSoloBucketWinner` |
| 3d | Per-winner (auto-rebuy enabled) | `nextPrizePool` or `futurePrizePool` + `ticketQueue` + `claimableWinnings[winner]` (take-profit) | `_processAutoRebuy` splits based on level offset | `_addClaimableEth` -> `_processAutoRebuy` |
| 4 | Aggregate liability | `claimablePool += liabilityDelta` | Sum of all claimable credits (excludes auto-rebuy and whale pass conversions) | `_distributeJackpotEth` / `_processDailyEthChunk` |

### Chunked Daily ETH Distribution Flow

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | `currentPrizePool` | `dailyEthPoolBudget` | `currentPrizePool * dailyBps / 10000` (6-14% days 1-4, 100% day 5) | `payDailyJackpot` |
| 2 | `dailyEthPoolBudget` | Per-bucket shares | Via `_processDailyEthChunk` | `payDailyJackpot` Phase 0 |
| 3 | Per-bucket share | Per-winner credit | `perWinner = share / totalCount` with gas-bounded cursor | `_processDailyEthChunk` |
| 4 | `futurePrizePool` | `dailyCarryoverEthPool` | 1% of futurePrizePool (non-early-bird days) | `payDailyJackpot` |
| 5 | `dailyCarryoverEthPool` | Per-winner credit (carryover level) | Via `_processDailyEthChunk` Phase 1 | `payDailyJackpot` Phase 1 |
| 6 | Paid ETH (daily) | `currentPrizePool -= paidDailyEth` | Deducted after Phase 0 completes | `payDailyJackpot` |

### Coin (BURNIE) Distribution Flow

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | `levelPrizePool[lvl-1]` | `coinBudget` | `levelPrizePool * 1000 / (price * 200)` = 0.5% in BURNIE | `_calcDailyCoinBudget` |
| 2 | `coinBudget` | 75% near-future + 25% far-future | `farBudget = coinBudget * 2500 / 10000` | `payDailyCoinJackpot` |
| 3a | Near-future budget | Trait-matched winners [lvl, lvl+4] | `coin.creditFlipBatch(winners, amounts)` | `_awardDailyCoinToTraitWinners` |
| 3b | Far-future budget | ticketQueue winners [lvl+5, lvl+99] | `coin.creditFlipBatch(winners, amounts)` | `_awardFarFutureCoinJackpot` |
| 4 | DGNRS coinflip credit | `coin.creditFlip(DGNRS, amount)` | 5% of prizePool in BURNIE-equivalent | `_creditDgnrsCoinflip` |

### Ticket Generation Flow

| Step | Source | Destination | Amount/Formula | Function |
|------|--------|-------------|----------------|----------|
| 1 | Winning traits (from VRF) | 4 trait IDs | `_rollWinningTraits` -> burn-weighted or random | `_rollWinningTraits` |
| 2 | Trait IDs + level | Winner addresses | `_randTraitTicket(traitBurnTicket[lvl], entropy, traitId, count, salt)` | `_distributeTicketJackpot` |
| 3 | Winners + ticket units | Queued tickets | `_queueTickets(winner, lvl+1, units)` | `_distributeTicketsToBucket` |
| 4 | Queued tickets | Trait burn tickets | `_raritySymbolBatch` -> `traitBurnTicket[lvl][traitId].push(player)` | `processTicketBatch` |

## Cross-Reference: Part 1 <-> Part 2 Linkage

### Entry Point -> Distribution Chain

| Part 1 Entry Point | Part 2 Internal Functions Called | Flow Description |
|---|---|---|
| `payDailyJackpot` (daily=true) | `_processDailyEthChunk` -> `_skipEntropyToBucket` -> `_randTraitTicketWithIndices` -> `_addClaimableEth` | Daily ETH jackpot with chunked gas-safe distribution. Phase 0: current level. Phase 1: carryover level. |
| `payDailyJackpot` (daily=false) | `_executeJackpot` -> `_runJackpotEthFlow` -> `_distributeJackpotEth` -> `_processOneBucket` -> `_resolveTraitWinners` -> `_creditJackpot` / `_processSoloBucketWinner` | Early-burn jackpot with non-chunked ETH distribution. |
| `payDailyJackpotCoinAndTickets` | `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners`, `_distributeTicketJackpot` | Phase 2: coin + ticket distribution after daily ETH completes. |
| `payDailyCoinJackpot` | `_calcDailyCoinBudget`, `_awardFarFutureCoinJackpot`, `_loadDailyWinningTraits`, `_rollWinningTraits`, `_selectDailyCoinTargetLevel`, `_awardDailyCoinToTraitWinners` | Standalone daily BURNIE jackpot (called separately from ETH jackpot). |
| `runTerminalJackpot` | `_rollWinningTraits`, `_distributeJackpotEth` -> `_processOneBucket` -> `_resolveTraitWinners` | Terminal (x00 level / endgame) jackpot with FINAL_DAY_SHARES_PACKED. |
| `consolidatePrizePools` | `_creditDgnrsCoinflip`, `_distributeYieldSurplus` (Part 1) | Pool consolidation at level transition: merge next->current, future dump roll, yield surplus. |
| `processTicketBatch` | `_processOneTicketEntry` -> `_resolveZeroOwedRemainder`, `_generateTicketBatch` -> `_raritySymbolBatch`, `_finalizeTicketEntry`, `_rollRemainder` | Batched ticket processing with gas-bounded iteration. |

### Shared Helpers (used by both Part 1 and Part 2 functions)

| Helper | Part 1 Users | Part 2 Users |
|---|---|---|
| `_rollWinningTraits` | `payDailyJackpot` | `payDailyCoinJackpot`, `runTerminalJackpot` |
| `_syncDailyWinningTraits` | `payDailyJackpot` | `payDailyCoinJackpot` |
| `_calculateDayIndex` | `payDailyJackpot` | `_getWinningTraits`, `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets` |
| `_addClaimableEth` | `_distributeYieldSurplus` | `_resolveTraitWinners`, `_processDailyEthChunk`, `_processSoloBucketWinner` |
| `_hasTraitTickets` | `_validateTicketBudget` | `_selectDailyCoinTargetLevel` |

## Findings Summary (Part 2)

| Severity | Count | Details |
|----------|-------|---------|
| BUG | 0 | No bugs found |
| CONCERN | 0 | No concerns identified |
| GAS | 1 | Minor: `_distributeJackpotEth` computes `soloBucketIndex(entropy)` twice when `dgnrsReward != 0` (once for `remainderIdx`, once for `soloIdx`). Both produce identical results. Compiler likely optimizes. |
| CORRECT | 36 | All functions verified correct |

**NatSpec notes:**
- `_executeJackpot`: NatSpec mentions COIN distribution but function only handles ETH. Stale comment, no behavioral impact.
- `_processSoloBucketWinner`: Return name `lootboxSpent` is legacy; actually tracks whale pass conversions.

## Combined JackpotModule Summary

### Function Coverage

| Part | Scope | Functions Audited | Lines |
|------|-------|-------------------|-------|
| Part 1 (Plan 50-03) | External entry points, pool consolidation, yield surplus, auto-rebuy, early-bird lootbox, ticket distribution helpers | ~30 functions | 1-1318 |
| Part 2 (Plan 50-04) | Internal distribution engine, coin jackpots, ticket batch processing, winner selection, trait/entropy helpers | 36 functions | 1319-2794 |
| **Total** | **Full contract** | **~66 functions** | **2794 lines** |

### Overall Verdict

**CORRECT** -- No bugs or security concerns found in Part 2 scope.

Key architectural strengths:
1. **Gas safety:** Chunked daily distribution with cursor-based resumption prevents block gas limit violations.
2. **Determinism:** All entropy derivation is reproducible from VRF seed + salts, enabling resumption mid-distribution.
3. **Fair winner selection:** Duplicates allowed by design (more tickets = more chances). Deity virtual entries give pass holders proportional representation (2%, min 2).
4. **Balanced ETH flow:** Solo bucket gets largest share (60% on day 5) but must accept 25% whale pass conversion for large payouts, recycling ETH back into the prize pool.
5. **Separation of concerns:** ETH distribution (Phase 1) and COIN+ticket distribution (Phase 2) are separated into different transactions to stay within gas limits.

