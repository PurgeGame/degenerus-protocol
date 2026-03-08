# 03b-04 FINDINGS: Degenerette Bet Timing Audit

**Audit date:** 2026-03-01
**Auditor:** Automated static analysis (read-only)
**Target:** `contracts/modules/DegenerusGameDegeneretteModule.sol` (1177 lines)
**Requirement:** MATH-06 -- Degenerette bet resolution pays out correctly; no bet timing creates advantaged positions

---

## 1. Commit-Reveal Pattern Verification

### 1a. Bet Placement Guard (`_placeFullTicketBetsCore`, lines 487-553)

The bet placement function reads `lootboxRngIndex` from storage and enforces two guards:

```solidity
// Line 498-500
uint48 index = lootboxRngIndex;
if (index == 0) revert E();
if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();
```

- **`lootboxRngIndex`** is a storage variable (declared in `DegenerusGameStorage.sol:1185`, initialized to `1`). It is NOT computed -- it is a direct storage read.
- **Guard 1** (`index == 0`): Defense-in-depth. Since `lootboxRngIndex` is initialized to 1 and only incremented, this can never fire in normal operation. Prevents bets against a zero index.
- **Guard 2** (`lootboxRngWordByIndex[index] != 0` reverts): This is the critical commit-reveal guard. The word for the current index must be **zero** (unknown) for a bet to proceed. If the VRF word has already been stored for this index, the bet reverts.

After the guards pass, the following data is packed into the bet:

| Field | Bits | Source |
|-------|------|--------|
| mode | [0] | Constant `MODE_FULL_TICKET = 1` |
| customTicket | [2..33] | Player's trait selection |
| ticketCount | [34..41] | Spin count (1-10) |
| currency | [42..43] | ETH=0, BURNIE=1, WWXRP=3 |
| amountPerTicket | [44..171] | uint128 bet amount |
| index | [172..219] | Current `lootboxRngIndex` value (48 bits) |
| activityScore | [220..235] | Snapshot of `_playerActivityScoreInternal(player)` (16 bits) |
| hasCustom | [236] | Always 1 |
| hero | [237..239] | Hero quadrant (3 bits) |

The **index** and **activityScore** are both snapshotted at bet time and stored in the packed bet word.

### 1b. Bet Resolution Guard (`_resolveFullTicketBet`, lines 610-692)

```solidity
// Line 616: extract index from packed bet (NOT from current lootboxRngIndex)
uint48 index = uint48((packed >> FT_INDEX_SHIFT) & MASK_48);

// Line 617: extract activity score from packed bet (NOT recalculated)
uint16 activityScore = uint16((packed >> FT_ACTIVITY_SHIFT) & MASK_16);

// Line 622-623
uint256 rngWord = lootboxRngWordByIndex[index];
if (rngWord == 0) revert RngNotReady();
```

- The index is **read from the stored bet**, not from the current `lootboxRngIndex`. This ensures the bet resolves against the same RNG epoch it was placed in.
- The activity score is **read from the stored bet** at bits [220..235], not recalculated via `_playerActivityScoreInternal`.
- The guard requires `rngWord != 0` -- the VRF word **must exist** before resolution can proceed.

### 1c. Foreknowledge Analysis

**Critical question: Can a player place a bet for index N and know the VRF word before it is stored?**

1. **VRF word storage paths.** The word for index N is written in exactly two code paths:
   - **Mid-day RNG** (`rawFulfillRandomWords`, line 1214-1215): `lootboxRngWordByIndex[index] = word;` -- executed directly in the VRF callback when `rngLockedFlag` is false.
   - **Daily RNG** (`_finalizeLootboxRng`, line 682): `lootboxRngWordByIndex[index] = rngWord;` -- called during `advanceGame` after the daily VRF word arrives.

2. **Only the Chainlink VRF coordinator can call `rawFulfillRandomWords`** (line 1203: `if (msg.sender != address(vrfCoordinator)) revert E()`). No player or operator can invoke this.

3. **The word is stored atomically.** There is no partial state -- the mapping goes from 0 to the full 256-bit VRF word in a single SSTORE.

4. **Front-running analysis:**
   - A player who sees the `rawFulfillRandomWords` transaction in the mempool and tries to front-run with a bet placement: The bet requires `lootboxRngWordByIndex[index] != 0` to revert (i.e., word must be zero). If the front-run succeeds (bet tx included before fulfillment tx), the word is still 0 at bet time -- the bet is valid but the player still does NOT know the word. If the front-run fails (fulfillment included first), the word is now non-zero, and `RngNotReady()` reverts the bet.
   - A player who sees the fulfillment tx and tries to place a bet after it: The word is non-zero, so `RngNotReady()` fires. The player cannot bet on a known outcome.

5. **Index advancement timing:** When `_reserveLootboxRngIndex` is called (line 1183-1190), `lootboxRngIndex` is incremented immediately. New bets target the new (higher) index whose word is still unknown. The old index's word will be filled by the pending VRF callback.

**Verdict: Foreknowledge is impossible.** The commit-reveal pattern is sound. Bets can only be placed when the word is unknown (word == 0), and resolution requires the word to be known (word != 0). There is no window where a player can bet with knowledge of the outcome.

---

## 2. lootboxRngIndex Lifecycle Trace

### 2a. Initialization

`lootboxRngIndex` is initialized to `1` in storage (DegenerusGameStorage.sol:1185). This means the first bets target index 1.

### 2b. Index Increment (`_reserveLootboxRngIndex`, AdvanceModule line 1183-1190)

```solidity
function _reserveLootboxRngIndex(uint256 requestId) private {
    uint48 index = lootboxRngIndex;
    lootboxRngRequestIndexById[requestId] = index;
    lootboxRngIndex = index + 1;
    lootboxRngPendingEth = 0;
    lootboxRngPendingBurnie = 0;
}
```

Called from two locations:
1. **`_finalizeRngRequest`** (daily RNG flow, line 1079) -- on fresh requests (not retries)
2. **`requestLootboxRng`** (mid-day RNG flow, line 625) -- standalone lootbox RNG

Effect: The current index is mapped to the VRF requestId, then `lootboxRngIndex` is bumped to `index + 1`. All subsequent bets now target the new index. Pending ETH/BURNIE counters are reset for the new epoch.

### 2c. Word Storage

The VRF word for index N is written when Chainlink delivers the random word:

1. **Mid-day path** (`rawFulfillRandomWords`, line 1214-1215): When `rngLockedFlag` is false (mid-day request), the word is stored directly:
   ```solidity
   uint48 index = lootboxRngRequestIndexById[requestId];
   lootboxRngWordByIndex[index] = word;
   ```

2. **Daily path** (`_finalizeLootboxRng`, line 679-683): When `rngLockedFlag` is true (daily advance), the word is stored during `advanceGame` processing:
   ```solidity
   uint48 index = lootboxRngRequestIndexById[vrfRequestId];
   if (index == 0) return;
   lootboxRngWordByIndex[index] = rngWord;
   ```

### 2d. Full Lifecycle Timeline

```
Time T0: lootboxRngIndex = N, lootboxRngWordByIndex[N] = 0
  |-- Players place bets targeting index N (word is 0, guard passes)
  |
Time T1: VRF request submitted, _reserveLootboxRngIndex called
  |-- lootboxRngIndex incremented to N+1
  |-- New bets now target index N+1 (word for N+1 is also 0)
  |-- Old bets on index N remain pending
  |
Time T2: Chainlink fulfills VRF, lootboxRngWordByIndex[N] = word
  |-- Bets on index N can now be resolved (word != 0)
  |-- No new bets can be placed on index N (lootboxRngIndex is now N+1)
  |-- New bets continue on index N+1 (word for N+1 still 0)
```

### 2e. Race Condition Analysis

**Can a bet be placed between VRF request and fulfillment?**
Yes, but this is by design. After `_reserveLootboxRngIndex` increments the index to N+1, new bets target N+1 whose word is still unknown. Old bets on N are waiting for fulfillment. There is no race -- the index advancement ensures clean epoch separation.

**Retry handling** (`_finalizeRngRequest`, line 1066-1074): On VRF timeout retries, the reserved index is remapped to the new requestId without incrementing the index again. This prevents double-incrementing and ensures the same epoch's bets all resolve with the same word.

---

## 3. Activity Score Snapshot Verification

### 3a. Snapshot at Bet Time (line 508)

```solidity
uint16 activityScore = uint16(_playerActivityScoreInternal(player));
```

The score is computed at bet placement and immediately packed into the bet storage word at bit position `FT_ACTIVITY_SHIFT = 220`, occupying 16 bits (lines 511-515 via `_packFullTicketBet`).

### 3b. Read from Storage at Resolution (line 617)

```solidity
uint16 activityScore = uint16((packed >> FT_ACTIVITY_SHIFT) & MASK_16);
```

The score is extracted from the packed bet word using the same bit position and mask. The resolution function does NOT call `_playerActivityScoreInternal` -- it uses the stored snapshot.

### 3c. Field Position Verification

- `FT_ACTIVITY_SHIFT = 220` (line 345)
- `MASK_16 = 0xFFFF` (line 363)
- Extraction: `(packed >> 220) & 0xFFFF` yields exactly the 16-bit activity score stored at bit positions [220..235].
- The score is used to compute ROI via `_roiBpsFromScore(activityScore)` at line 627.

### 3d. Can a player manipulate score between bet and resolution?

Even if they increase their activity score (by completing quests, increasing streak, etc.) between bet placement and resolution, it does NOT affect the payout. The snapshot stored at bet time is used for resolution. There is **no code path** in `_resolveFullTicketBet` that recalculates the activity score.

**Confirmed: Activity score is immutably snapshotted at bet time and read from packed storage at resolution. No recalculation path exists.**

---

## 4. Bet Currency and Amount Validation

### 4a. Supported Currencies

Three currencies are supported:
- **ETH** (`CURRENCY_ETH = 0`): Collected via `msg.value` or `claimableWinnings`, credited to `futurePrizePool`
- **BURNIE** (`CURRENCY_BURNIE = 1`): Burned from player via `coin.burnCoin(player, totalBet)`
- **WWXRP** (`CURRENCY_WWXRP = 3`): Burned from player via `wwxrp.burnForGame(player, totalBet)`

Any other currency value reverts with `UnsupportedCurrency()` (line 564).

### 4b. Minimum Bet Enforcement (`_validateMinBet`, lines 556-566)

| Currency | Minimum | Constant |
|----------|---------|----------|
| ETH | 0.005 ETH | `MIN_BET_ETH = 5 ether / 1000` |
| BURNIE | 100 tokens | `MIN_BET_BURNIE = 100 ether` |
| WWXRP | 1 token | `MIN_BET_WWXRP = 1 ether` |

Called at line 502, after the commit-reveal guard passes.

### 4c. Maximum Spin Count (`MAX_SPINS_PER_BET = 10`, line 252)

Enforced at line 495: `if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET) revert InvalidBet()`

### 4d. Zero Amount Check

Line 496: `if (amountPerTicket == 0) revert InvalidBet()` -- zero-amount bets are rejected.

### 4e. ETH Jackpot Resolution Block

Line 504-505: During jackpot resolution phases (when `rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0)`), ETH bets are blocked entirely to prevent pool interference.

---

## 5. ROI Curve Verification (`_roiBpsFromScore`, lines 1113-1142)

### 5a. Constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `ACTIVITY_SCORE_MID_BPS` | 7,500 | 75% activity |
| `ACTIVITY_SCORE_HIGH_BPS` | 25,500 | 255% activity |
| `ACTIVITY_SCORE_MAX_BPS` | 30,500 | 305% activity (cap) |
| `ROI_MIN_BPS` | 9,000 | 90% ROI |
| `ROI_MID_BPS` | 9,500 | 95% ROI |
| `ROI_HIGH_BPS` | 9,950 | 99.5% ROI |
| `ROI_MAX_BPS` | 9,990 | 99.9% ROI |

### 5b. Segment 1: Quadratic 90% to 95% (score 0 to 7500)

```solidity
uint256 term1 = (1000 * xNum) / xDen;        // xNum = score, xDen = 7500
uint256 term2 = (500 * xNum * xNum) / (xDen * xDen);
roiBps = ROI_MIN_BPS + term1 - term2;         // 9000 + term1 - term2
```

This is a **concave quadratic** curve: `f(x) = 9000 + 1000x - 500x^2` where `x = score/7500`.

**Spot-checks:**

- **score = 0:** `x = 0`, `term1 = 0`, `term2 = 0`, `roiBps = 9000 + 0 - 0 = 9000` (90%). **CORRECT.**
- **score = 3750 (50% of mid):** `x = 0.5`, `term1 = 500`, `term2 = 125`, `roiBps = 9000 + 500 - 125 = 9375` (93.75%).
- **score = 7500:** `x = 1.0`, `term1 = 1000`, `term2 = 500`, `roiBps = 9000 + 1000 - 500 = 9500` (95%). **CORRECT -- matches ROI_MID_BPS.**

The quadratic curve is concave (rises fast initially, then flattens approaching 95%). The derivative at x=0 is `1000/7500 = 0.133 BPS per score BPS`, falling to `0` at x=1.

### 5c. Segment 2: Linear 95% to 99.5% (score 7500 to 25500)

```solidity
uint256 delta = score - ACTIVITY_SCORE_MID_BPS;    // score - 7500
uint256 span = ACTIVITY_SCORE_HIGH_BPS - ACTIVITY_SCORE_MID_BPS; // 25500 - 7500 = 18000
uint256 roiDelta = ROI_HIGH_BPS - ROI_MID_BPS;     // 9950 - 9500 = 450
roiBps = ROI_MID_BPS + (delta * roiDelta) / span;  // 9500 + delta * 450 / 18000
```

Slope: 450 / 18000 = 0.025 BPS per score BPS.

**Spot-checks:**

- **score = 7500:** `delta = 0`, `roiBps = 9500` (95%). **CORRECT -- boundary match.**
- **score = 16500 (midpoint):** `delta = 9000`, `roiBps = 9500 + (9000 * 450) / 18000 = 9500 + 225 = 9725` (97.25%).
- **score = 25500:** `delta = 18000`, `roiBps = 9500 + (18000 * 450) / 18000 = 9500 + 450 = 9950` (99.5%). **CORRECT -- matches ROI_HIGH_BPS.**

### 5d. Segment 3: Linear 99.5% to 99.9% (score 25500 to 30500)

```solidity
uint256 delta = score - ACTIVITY_SCORE_HIGH_BPS;    // score - 25500
uint256 span = ACTIVITY_SCORE_MAX_BPS - ACTIVITY_SCORE_HIGH_BPS; // 30500 - 25500 = 5000
uint256 roiDelta = ROI_MAX_BPS - ROI_HIGH_BPS;      // 9990 - 9950 = 40
roiBps = ROI_HIGH_BPS + (delta * roiDelta) / span;  // 9950 + delta * 40 / 5000
```

Slope: 40 / 5000 = 0.008 BPS per score BPS.

**Spot-checks:**

- **score = 25500:** `delta = 0`, `roiBps = 9950` (99.5%). **CORRECT -- boundary match.**
- **score = 30500:** `delta = 5000`, `roiBps = 9950 + (5000 * 40) / 5000 = 9950 + 40 = 9990` (99.9%). **CORRECT -- matches ROI_MAX_BPS.**

### 5e. Cap at 305%

Line 1116-1118: `if (score > ACTIVITY_SCORE_MAX_BPS) { score = ACTIVITY_SCORE_MAX_BPS; }` -- any score above 30500 is clamped to 30500, yielding max ROI of 99.9%.

### 5f. Integer Division Precision Analysis

- **Segment 1 boundary (score = 7500):** `term1 = (1000 * 7500) / 7500 = 1000` (exact), `term2 = (500 * 7500 * 7500) / (7500 * 7500) = 500` (exact). No precision loss at boundary.
- **Segment 2 boundary (score = 25500):** `delta * roiDelta / span = 18000 * 450 / 18000 = 450` (exact). No precision loss.
- **Segment 3 boundary (score = 30500):** `delta * roiDelta / span = 5000 * 40 / 5000 = 40` (exact). No precision loss.
- **Mid-range values:** Integer division truncates, e.g., `score = 100` in segment 1: `term1 = 100000/7500 = 13`, `term2 = 5000000/56250000 = 0`. Truncation of at most 1 BPS (0.01% ROI), always in the house's favor. This is acceptable.

**Confirmed: ROI curve matches documentation at all segment boundaries. Precision loss is at most 1 BPS (truncation), always favoring the house.**

---

## 6. EV Normalization Math (`_evNormalizationRatio`, lines 818-861)

### 6a. Problem Statement

Different trait selections have different match probabilities. Buckets 0-3 have weight 10 (probability 10/75 = 13.3%), buckets 4-6 have weight 9 (12.0%), bucket 7 has weight 8 (10.7%). Without normalization, a player selecting common traits would have lower payouts per match but higher match probability, potentially creating different expected values.

### 6b. Per-Quadrant Ratio Computation

For each of the 4 quadrants, the function computes the ratio `P(uniform) / P(actual)`:

| Outcome | Uniform Probability | Actual Probability | Ratio |
|---------|--------------------|--------------------|-------|
| Both match (color AND symbol) | 100/5625 | (wC * wS)/5625 | 100 / (wC * wS) |
| One match (color XOR symbol) | 1300/5625 | [75*(wC+wS) - 2*wC*wS] / 5625 | 1300 / [75*(wC+wS) - 2*wC*wS] |
| No match | 4225/5625 | (75-wC)*(75-wS)/5625 | 4225 / [(75-wC)*(75-wS)] |

The 5625 denominators cancel, leaving the ratios shown in the rightmost column.

**Verification of uniform probabilities:**
- `100 + 1300 + 4225 = 5625 = 75^2`. Confirmed: probabilities sum to 1 under uniform weights.
- Uniform "both match": `(75/75) * (10/75) * (10/75) * 75^2 = 100` -- this assumes a weight-10 bucket uniformly. The magic constant 100 = 10*10, which is the "average" wC*wS for the uniform case.

Wait -- the uniform case for "both match" should be: `E[wC * wS]` averaged over all possible trait choices. The code uses a fixed constant `100`, which equals `10 * 10`. This assumes the "uniform ticket" has weight-10 traits in all positions. Let me verify this is the correct normalization.

**Detailed verification:** The normalization ratio is `num/den` where `num = product of uniform_numerators` and `den = product of actual_numerators`. For a given outcome (match pattern), the payout is multiplied by `num/den`. This means:

```
Expected payout = sum over all outcomes: P(outcome) * base_payout * (num/den)
                = sum: [actual_P(outcome)] * base_payout * [uniform_P(outcome) / actual_P(outcome)]
                = sum: uniform_P(outcome) * base_payout
```

This is independent of the player's trait selection. The normalization transforms any ticket's EV to match the uniform ticket's EV. This is **mathematically exact** -- no approximation.

### 6c. One-Match Probability Derivation

For one quadrant with player color weight wC and symbol weight wS, the probability of exactly one attribute matching (color XOR symbol):

```
P(one match) = P(color match) * P(symbol no match) + P(color no match) * P(symbol match)
             = (wC/75) * (1 - wS/75) + (1 - wC/75) * (wS/75)
             = (wC * (75 - wS) + (75 - wC) * wS) / 75^2
             = (75*wC - wC*wS + 75*wS - wC*wS) / 5625
             = (75*(wC + wS) - 2*wC*wS) / 5625
```

This matches the code at line 851: `den *= 75 * (wC + wS) - 2 * wC * wS`. **CORRECT.**

### 6d. Overflow Analysis

Each quadrant contributes one multiply to both `num` and `den`. Maximum values per quadrant:

| Outcome | Max num factor | Max den factor |
|---------|---------------|---------------|
| Both match | 100 | 10 * 10 = 100 |
| One match | 1300 | 75*(10+10) - 2*10*10 = 1300 |
| No match | 4225 | (75-8)*(75-8) = 4489 |

- **Max num:** 4225^4 = 3.18 * 10^14. Fits in uint256 (max ~1.16 * 10^77).
- **Max den:** 4489^4 = 4.06 * 10^14. Also fits.
- **After multiplication in payout:** `(payout * evNum) / evDen` where payout is at most ~`betAmount * 10_000_000 * 9990 / 1_000_000 = betAmount * 99_900`. With max betAmount = uint128 (~3.4 * 10^38): `3.4 * 10^38 * 99_900 * 3.18 * 10^14 = ~1.08 * 10^58`. Still fits in uint256.

**No overflow risk.**

### 6e. Division Truncation

The final `(payout * evNum) / evDen` uses integer division. With `evNum` and `evDen` both in the range ~10^14, truncation loss is at most 1 wei per payout. This is negligible.

**Confirmed: EV normalization produces mathematically exact equal EV for all trait selections, with negligible (1 wei) truncation. No overflow risk.**

---

## 7. Match Count and Payout Formula

### 7a. Match Counting (`_countMatches`, lines 867-891)

For each of 4 quadrants, two comparisons are made:
- **Color match:** Bits [5:3] of each quadrant byte (the category bucket 0-7)
- **Symbol match:** Bits [2:0] of each quadrant byte (the sub-bucket 0-7)

Each match increments the counter. Maximum matches: 4 quadrants * 2 attributes = 8.

### 7b. Base Payout Table (centi-x multipliers at 100% ROI)

| Matches | Centi-x | Multiplier |
|---------|---------|------------|
| 0 | 0 | 0x (total loss) |
| 1 | 0 | 0x (total loss) |
| 2 | 190 | 1.90x |
| 3 | 475 | 4.75x |
| 4 | 1,500 | 15x |
| 5 | 4,250 | 42.5x |
| 6 | 19,500 | 195x |
| 7 | 100,000 | 1,000x |
| 8 | 10,000,000 | 100,000x |

Source: `QUICK_PLAY_BASE_PAYOUTS_PACKED` (lines 274-282) and `QUICK_PLAY_BASE_PAYOUT_8_MATCHES` (line 285).

### 7c. Payout Formula (line 963)

```solidity
payout = (uint256(betAmount) * basePayoutBps * effectiveRoi) / 1_000_000;
```

Where:
- `basePayoutBps` is in centi-x (100 = 1x)
- `effectiveRoi` is in BPS (10000 = 100%)
- Division by 1,000,000 = 100 (centi-x) * 10,000 (BPS)

Then EV normalization is applied: `payout = (payout * evNum) / evDen`.

### 7d. Can 8-Match Payout Exceed futurePrizePool?

At 8 matches: `payout = betAmount * 10,000,000 * ROI / 1,000,000 = betAmount * 10 * ROI`. At max ROI (99.9%): `payout = betAmount * 10 * 9990 / 1000 = betAmount * 99.9`.

With EV normalization for an 8-match (all 4 quadrants both-match): `evNum = 100^4 = 10^8`, `evDen = (wC1*wS1)*(wC2*wS2)*(wC3*wS3)*(wC4*wS4)`. Minimum denominator (all weight-8 traits): `8^8 = 16,777,216`. Maximum normalization: `10^8 / 16,777,216 = 5.96x`.

So maximum 8-match payout: `betAmount * 99.9 * 5.96 = betAmount * 595.4`.

For ETH bets, the payout goes through `_distributePayout` where only 25% is paid as ETH (capped at 10% of pool). The remaining 75%+ is converted to lootbox. This means the maximum direct ETH extraction per bet is bounded by `futurePrizePool * 10%` regardless of match count. See Section 8 for detailed analysis.

---

## 8. ETH Payout Cap and futurePrizePool Safety

### 8a. Payout Distribution (`_distributePayout`, lines 700-730)

For ETH bets:

```solidity
uint256 ethPortion = payout / 4;              // 25% as ETH
uint256 lootboxPortion = payout - ethPortion;  // 75% as lootbox

uint256 maxEth = (pool * ETH_WIN_CAP_BPS) / 10_000; // 10% of futurePrizePool
if (ethPortion > maxEth) {
    lootboxPortion += ethPortion - maxEth;     // Excess to lootbox
    ethPortion = maxEth;
}

unchecked { pool -= ethPortion; }
futurePrizePool = pool;
```

- **ETH_WIN_CAP_BPS = 1000** (line 224): 10% of pool.
- The ETH portion (25% of payout) is capped at 10% of `futurePrizePool`.
- Excess is redirected to lootbox.
- `futurePrizePool` is decremented by the actual ETH paid out.

### 8b. Pool Depletion Analysis

Each ETH payout removes at most 10% of the current pool:
```
After 1 payout: pool * 0.9
After N payouts: pool * 0.9^N
```

This is a geometric series converging to 0. After 10 consecutive max-cap payouts: `pool * 0.9^10 = pool * 0.349`. After 100 payouts: `pool * 0.9^100 = pool * 2.66e-5`.

**Is there a minimum balance guard?** No explicit minimum. However:
- When `futurePrizePool` approaches 0, `maxEth = (pool * 1000) / 10000` also approaches 0.
- When pool = 0: `maxEth = 0`, all payouts become lootbox-only (no ETH extraction).
- The pool can reach exactly 0 only through rounding: if pool = 1 wei, `maxEth = 0` (integer truncation), so no ETH is paid and pool stays at 1 wei.

**Can the pool reach 0?** Only if `ethPortion <= maxEth` happens to extract the last wei. With `pool = 10 wei`: `maxEth = (10 * 1000) / 10000 = 1 wei`. After payout: `pool = 9 wei`. This continues: 9 -> 8 -> 7 -> ... -> 1 -> 0 (when pool=1, maxEth=0, no extraction). So pool converges to 1 wei and stays there indefinitely.

Actually, let me re-examine: with `pool = 1`: `maxEth = (1 * 1000) / 10000 = 0`. So ethPortion is capped at 0. Pool stays at 1. The pool can never reach exactly 0 from the cap mechanism alone.

### 8c. Pool Replenishment

`futurePrizePool` is **replenished** when new ETH bets are placed:
```solidity
// Line 589 in _collectBetFunds:
futurePrizePool += totalBet;
```

Every ETH degenerette bet adds its full amount to the pool. So active betting continuously replenishes what payouts drain. Additionally, mint purchases, whale bundles, and daily jackpot mechanisms also add to `futurePrizePool`.

### 8d. Multi-Spin Jackpot Scenario

A bet with 10 spins could potentially hit multiple high-match payouts. Each spin's payout is processed independently through `_distributePayout` (line 678). Each call reads the **current** `futurePrizePool` (line 702), so sequential payouts see the pool shrinking:

```
Spin 0: pool -= min(ethPortion, pool * 10%)
Spin 1: pool -= min(ethPortion, reduced_pool * 10%)
...
```

The 10% cap is applied per-spin against the updated pool. This prevents compound extraction.

### 8e. Griefing via Small Bets

Can a player place many minimum ETH bets to drain the pool?

- Minimum ETH bet: 0.005 ETH per ticket, up to 10 spins = 0.05 ETH total.
- This adds 0.05 ETH to `futurePrizePool` (line 589).
- Even with a max payout (100,000x jackpot on 8 matches), the ETH portion is capped at 10% of pool.
- Since each bet adds its value to the pool before resolution (at different lootboxRngIndex), the pool grows from bets and is only drained at resolution. The pool is net positive from most bets (since house edge is 0.1% to 10%).

**The pool is self-sustaining as long as there is betting activity. Depletion to zero is mathematically impossible through the cap mechanism alone.**

### 8f. `unchecked` Block Safety

Line 717: `unchecked { pool -= ethPortion; }`

This is safe because `ethPortion <= maxEth = pool * 10% < pool`. The subtraction cannot underflow. The invariant `ethPortion <= pool` is enforced by the cap.

---

## 9. Additional Timing and Safety Checks

### 9a. Can a Player Cancel or Modify a Bet?

**No.** Once `degeneretteBets[player][nonce] = packed` is written (line 521), there is no cancel or modify function. The bet can only be resolved via `resolveBets` after the VRF word is available. The bet is deleted at resolution (line 625: `delete degeneretteBets[player][betId]`).

### 9b. Can a Player Resolve Someone Else's Bet?

The `resolveBets` function (line 435) calls `_resolvePlayer(player)` which checks `_requireApproved(player)` if `player != msg.sender`. So:
- A player can resolve their own bets.
- An approved operator can resolve a player's bets on their behalf.
- An unapproved third party **cannot** resolve another player's bets.

This is a safety feature -- it prevents front-running of resolution transactions where the outcome might differ based on timing (though in this system, the outcome is deterministic once the VRF word is known).

### 9c. What If the VRF Word Is Never Fulfilled?

If the VRF word for index N is never stored:
- `lootboxRngWordByIndex[N]` remains 0.
- Resolution attempts revert with `RngNotReady()`.
- The bet is stuck until the word is delivered.

**Mitigations:**
1. The VRF retry mechanism (18-hour timeout) re-requests if the original request is not fulfilled.
2. The 3-day emergency coordinator rotation (`updateVrfCoordinatorAndSub`) allows admin to switch to a working VRF source.
3. For mid-day RNG: `requestLootboxRng` can be called again once the previous request times out.

In the worst case, bets remain pending indefinitely but funds are not lost -- they are held in the contract and can be resolved once a VRF word is eventually provided.

### 9d. Can a Player Have Multiple Concurrent Bets on the Same Index?

**Yes.** Each bet gets a unique `betId` (from `degeneretteBetNonce[player]`, incremented at line 518). Multiple bets can target the same `lootboxRngIndex`. They will all resolve using the same VRF word but each bet has its own packed data (ticket, amount, activity score).

This is by design -- it allows batch betting within a single RNG epoch.

### 9e. ETH Bet During Jackpot Resolution

Line 504-505: `jackpotResolutionActive = rngLockedFlag && lastPurchaseDay && ((level + 1) % 5 == 0)`. If true and currency is ETH, the bet reverts (line 505 and re-checked at line 577). This prevents ETH pool manipulation during sensitive jackpot resolution windows.

BURNIE and WWXRP bets are not blocked during jackpot resolution since they don't affect ETH pools.

### 9f. Consolation Prize System

Fully-losing bets (total payout = 0 across all spins) receive 1 WWXRP consolation prize if the bet amount exceeds a threshold:
- ETH >= 0.01 ETH
- BURNIE >= 500 tokens
- WWXRP >= 20 tokens

This is minted via `wwxrp.mintPrize(player, CONSOLATION_PRIZE_WWXRP)` (line 749). Since WWXRP is a mintable token, this does not drain any ETH pool.

### 9g. Lootbox Direct Resolution for ETH Payouts

When ETH degenerette payouts include a lootbox portion (75%+ of payout), this is resolved via `_resolveLootboxDirect` (line 756), which delegatecalls into the LootboxModule. The lootbox resolution uses the same RNG word (or a derived lootbox word per spin, line 675-677) to determine lootbox rewards. Each spin uses a unique lootbox word derived from `keccak256(rngWord, index, spinIdx, 0x4c)` to avoid identical lootbox results across spins with the same payout amount.

---

## 10. MATH-06 Verdict: Bet Resolution Timing Safety

### Requirement

> MATH-06: Degenerette bet resolution pays out correctly; no bet timing creates advantaged positions.

### Evidence Summary

| Property | Status | Evidence |
|----------|--------|----------|
| Commit-reveal pattern | **VERIFIED** | Bet requires word==0 (line 500), resolution requires word!=0 (line 623) |
| Index stored in bet | **VERIFIED** | Index packed at FT_INDEX_SHIFT=172 (line 512), read from packed at resolution (line 616) |
| Activity score snapshot | **VERIFIED** | Snapshotted at bet time (line 508), read from packed storage at resolution (line 617), no recalculation |
| No foreknowledge window | **VERIFIED** | VRF word delivered by Chainlink coordinator only (line 1203); atomic storage; front-running analyzed |
| ROI curve correct | **VERIFIED** | All 4 boundary values match documentation; quadratic/linear/linear segments verified |
| EV normalization correct | **VERIFIED** | Product-of-4-ratios produces mathematically exact equal EV regardless of trait selection |
| ETH payout cap | **VERIFIED** | 25% ETH capped at 10% of futurePrizePool (line 710); pool convergence analysis shows it cannot reach 0 |
| Pool self-sustaining | **VERIFIED** | ETH bets add to futurePrizePool at placement (line 589); geometric decay prevents complete depletion |
| No bet cancellation | **VERIFIED** | No cancel/modify function exists; bets are immutable once placed |
| Multiple concurrent bets | **VERIFIED** | Allowed by design with unique betIds; same VRF word resolves all bets in the epoch |

### Verdict

**MATH-06: PASS**

The degenerette bet system implements a sound commit-reveal pattern where:
1. Bets can ONLY be placed when the VRF word for the current index is unknown (`lootboxRngWordByIndex[index] == 0`).
2. Bets can ONLY be resolved when the VRF word is known (`lootboxRngWordByIndex[index] != 0`).
3. The VRF word can only be stored by the Chainlink VRF coordinator via `rawFulfillRandomWords`.
4. No timing window exists where a bet can be placed with knowledge of the VRF word that will resolve it.
5. Activity score is immutably snapshotted at bet time, preventing post-bet score manipulation.
6. The ROI curve and EV normalization math are correct, ensuring fair payouts.
7. The ETH payout cap protects the futurePrizePool from catastrophic depletion.

No advantaged position is achievable through bet timing relative to VRF delivery.

---

## 11. Findings

### INFORMATIONAL Findings

**INF-01: ETH ROI Bonus Redistribution into 5+ Match Buckets**

ETH bets receive a +5% ROI bonus (`ETH_ROI_BONUS_BPS = 500`, line 213) that is redistributed exclusively into 5+ match buckets via `_wwxrpBonusRoiForBucket` (lines 949-957). This creates a slightly top-heavy payout distribution for ETH bets compared to BURNIE/WWXRP, but is EV-neutral overall since the bonus is redistributed, not added on top.

**INF-02: Consolation Prize as Mint Mechanism**

The WWXRP consolation prize (1 token for qualifying losing bets) is minted, not drawn from a pool. This means losing bets with sufficient size receive a small consolation that does not impact any ETH pool. The economic cost is borne by WWXRP inflation, which is outside the scope of this audit.

**INF-03: Hero Quadrant Multiplier is EV-Neutral by Design**

The hero boost/penalty system (lines 348-356, 973-999) applies a per-match-count boost when the hero quadrant fully matches, and a 5% penalty otherwise. The constraint `P(hero|M) * boost(M) + (1-P(hero|M)) * penalty = HERO_SCALE` ensures EV neutrality. This is verified by the packed boost constants matching the mathematical constraint for each match count M=2..7. M=0,1 have zero payout (no adjustment needed); M=8 always has the hero quadrant matching (probability 1), so boost = HERO_SCALE = 10000 (no adjustment).

### No HIGH or MEDIUM Severity Findings

The degenerette bet timing system is well-designed with robust commit-reveal enforcement, correct mathematical formulas, and proper pool protection mechanisms.

---

*Audit completed: 2026-03-01*
*Target: DegenerusGameDegeneretteModule.sol (1177 lines)*
*No contract files were modified during this audit.*
