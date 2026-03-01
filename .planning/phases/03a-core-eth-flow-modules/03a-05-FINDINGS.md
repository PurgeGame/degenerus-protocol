# 03a-05 Findings: Deity Pass T(n) Triangular Pricing Audit

**Requirement:** MATH-02
**Scope:** `DegenerusGameWhaleModule._purchaseDeityPass()` (lines 436-525)
**Verdict:** PASS -- No overflow risk, exact arithmetic, bounded k

---

## 1. Formula Implementation (Source of Truth)

**File:** `contracts/modules/DegenerusGameWhaleModule.sol`, line 442

```solidity
uint256 k = deityPassOwners.length;
uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
```

**Constants:**
- `DEITY_PASS_BASE = 24 ether` = 24,000,000,000,000,000,000 (24e18) -- line 153
- `1 ether` = 1,000,000,000,000,000,000 (1e18)

**Checked/Unchecked context:** The formula is in **default checked arithmetic** (Solidity ^0.8.26). No `unchecked` block wraps the price calculation. The only `unchecked` in the function is at line 501 for the ticket-queuing loop counter `++i`. This means:
- Any overflow in `k * (k + 1)`, the subsequent `* 1 ether`, the `/ 2`, or the `+ DEITY_PASS_BASE` would **revert automatically** with a panic(0x11).
- Checked arithmetic provides defense-in-depth: even if the k bound were somehow bypassed, the transaction would revert rather than compute an incorrect price.

---

## 2. k Bound Verification

**Source:** Lines 437-438, 476

```solidity
if (symbolId >= 32) revert E();              // line 437: enforces symbolId in [0, 31]
if (deityBySymbol[symbolId] != address(0)) revert E(); // line 438: each symbolId sold once
if (deityPassCount[buyer] != 0) revert E();  // line 439: one pass per address
...
deityPassOwners.push(buyer);                  // line 476: k grows by 1 per purchase
```

**Analysis:**
1. There are exactly 32 valid symbol IDs: 0 through 31.
2. `deityBySymbol[symbolId]` is set to the buyer's address on line 478 upon purchase.
3. The check at line 438 prevents any symbolId from being sold twice.
4. Therefore, `deityPassOwners` can contain at most 32 entries.
5. When the 32nd pass is sold, `k = 31` at the time of purchase (array had 31 elements before `.push()`).
6. After all 32 passes are sold, every symbolId maps to a non-zero address, so all future purchase attempts revert at line 438.

**Effective k range:** [0, 31]

**Revert condition:** When all 32 symbols are taken, `deityBySymbol[symbolId] != address(0)` is true for every symbolId in [0, 31], and `symbolId >= 32` catches all other inputs. The error is `E()`.

---

## 3. Arithmetic Verification Table

Formula: `basePrice = 24e18 + (k * (k + 1) * 1e18) / 2`

### Step-by-step computation

| k | k*(k+1) | k*(k+1) * 1e18 (intermediate) | / 2 | + 24e18 | Total ETH |
|----:|--------:|------------------------------:|----:|--------:|----------:|
| 0 | 0 | 0 | 0 | 24,000,000,000,000,000,000 | 24 |
| 1 | 2 | 2,000,000,000,000,000,000 | 1,000,000,000,000,000,000 | 25,000,000,000,000,000,000 | 25 |
| 10 | 110 | 110,000,000,000,000,000,000 | 55,000,000,000,000,000,000 | 79,000,000,000,000,000,000 | 79 |
| 31 | 992 | 992,000,000,000,000,000,000 | 496,000,000,000,000,000,000 | 520,000,000,000,000,000,000 | 520 |
| 100 | 10,100 | 10,100,000,000,000,000,000,000 | 5,050,000,000,000,000,000,000 | 5,074,000,000,000,000,000,000 | 5,074 |
| 1,000 | 1,001,000 | 1,001,000,000,000,000,000,000,000 | 500,500,000,000,000,000,000,000 | 500,524,000,000,000,000,000,000 | 500,524 |

### Overflow analysis

**Maximum intermediate value** (worst case at k=1000):
- `k * (k + 1)` = 1,001,000
- `k * (k + 1) * 1e18` = 1,001,000 * 10^18 = 1.001 x 10^24

**uint256 maximum:** 2^256 - 1 = approx 1.158 x 10^77

**Headroom ratio:** 1.158e77 / 1.001e24 = approx 1.157 x 10^53

**Conclusion:** Even at k=1,000 (over 31x the actual maximum), the largest intermediate product is 53 orders of magnitude below uint256 max. **Overflow is mathematically impossible** at any reachable k value. The checked arithmetic context provides a belt-and-suspenders guarantee: if k could somehow exceed physical limits, the transaction would revert rather than wrap.

### Theoretical overflow threshold

Solving for k where `k * (k + 1) * 1e18 > 2^256`:
- k^2 * 1e18 ~ 1.158e77
- k ~ sqrt(1.158e59) ~ 3.4 x 10^29

Overflow would require approximately 3.4 x 10^29 deity passes. This is physically unreachable.

---

## 4. Division Exactness

**Property:** k * (k + 1) is always even.

**Proof:** For any integer k, exactly one of {k, k+1} is even (they are consecutive integers). Therefore their product k * (k + 1) is divisible by 2 with no remainder.

**Consequence:** `(k * (k + 1) * 1 ether) / 2` always produces an exact integer result. No rounding occurs, no wei is lost or gained. This is a mathematical invariant, not a code assumption.

**Solidity confirmation:** Solidity integer division truncates toward zero. Since the numerator is always even, truncation equals exact division. The result is always exact.

---

## 5. msg.value Comparison

**Source:** Line 466

```solidity
if (msg.value != totalPrice) revert E();
```

**Underpayment protection:** YES -- any `msg.value < totalPrice` reverts.

**Overpayment protection:** YES -- any `msg.value > totalPrice` also reverts. The check is strict equality (`!=`), not `<`. No excess ETH can be sent (and potentially lost/retained).

**Implication:** The buyer must send exactly the correct price. This eliminates both underpayment exploits and overpayment loss.

**Note on `totalPrice` vs `basePrice`:** The code allows a discount boon (10%/25%/50% off) applied at lines 444-465. When a boon is active and not expired, `totalPrice` may be less than `basePrice`. The msg.value check is against `totalPrice` (the discounted price), which is correct: buyers with valid boons pay the discounted price.

---

## 6. End-to-End Deity Pass Purchase Flow

### Entry

`purchaseDeityPass(address buyer, uint8 symbolId)` (line 432) delegates to `_purchaseDeityPass(buyer, symbolId)` (line 436).

### Validation phase (lines 437-439)

1. `symbolId >= 32` -- revert. Bounds symbolId to [0, 31].
2. `deityBySymbol[symbolId] != address(0)` -- revert. Symbol already claimed.
3. `deityPassCount[buyer] != 0` -- revert. Buyer already owns a deity pass.

All checks fire **before** any state mutation. This is correct: if the 33rd buyer tries any symbolId, either it is >= 32 (revert at 437) or it is a taken symbolId (revert at 438).

### Price computation (lines 441-466)

1. `k = deityPassOwners.length` -- number of passes already sold.
2. `basePrice = 24e18 + (k * (k+1) * 1e18) / 2` -- triangular pricing.
3. Boon discount applied if active and unexpired (tiers: 10%, 25%, 50%).
4. Boon state consumed regardless of expiry (lines 462-464) -- prevents replay.
5. `msg.value != totalPrice` -- strict equality check.

### State updates (lines 468-478)

1. `deityPassPaidTotal[buyer] += totalPrice` -- accumulates total ETH paid by this buyer.
2. `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` -- earlybird DGNRS reward.
3. `deityPassCount[buyer] = 1` -- marks buyer as deity pass holder.
4. `deityPassPurchasedCount[buyer] += 1` -- purchase counter.
5. `deityPassOwners.push(buyer)` -- adds to iteration array, increments k for next buyer.
6. `deityPassSymbol[buyer] = symbolId` -- records which symbol this buyer chose.
7. `deityBySymbol[symbolId] = buyer` -- reverse mapping for uniqueness check.

### ERC721 minting (line 481)

```solidity
IDegenerusDeityPassMint(ContractAddresses.DEITY_PASS).mint(buyer, symbolId);
```

An external call to the DeityPass ERC721 contract mints token with `tokenId = symbolId`. Since symbolId is in [0, 31] and each is minted exactly once, there are exactly 32 possible deity pass NFTs.

### DGNRS token rewards (lines 483-493)

Distributes DGNRS from the Whale pool (5%) and Affiliate pool:
- Buyer: 5% of whale pool balance (DEITY_WHALE_POOL_BPS = 500)
- Direct affiliate: 0.5% of affiliate pool
- Upline: 0.1% of affiliate pool
- Upline2: 0.05% (half of upline share)

### Ticket queuing (lines 495-502)

```solidity
uint24 ticketStartLevel = passLevel <= 4 ? 1 : uint24(((passLevel + 1) / 50) * 50 + 1);
```

Deity pass holders receive whale-equivalent tickets:
- 40 tickets/level for bonus levels (passLevel through level 10)
- 2 tickets/level for standard levels (11-100)
- 100 levels total coverage

### Refundability (lines 504-507)

```solidity
if (level == 0 && !gameOver) {
    deityPassRefundable[buyer] += totalPrice;
}
```

Pre-game purchases are refundable. Once the game starts (level > 0), deity pass purchases are non-refundable.

### ETH distribution (lines 509-517)

```solidity
uint256 nextShare;
if (level == 0) {
    nextShare = (totalPrice * 3000) / 10_000;  // 30% to next pool
} else {
    nextShare = (totalPrice * 500) / 10_000;   // 5% to next pool
}
nextPrizePool += nextShare;
futurePrizePool += totalPrice - nextShare;      // remainder to future pool
```

- **Pre-game (level 0):** 30% nextPrizePool, 70% futurePrizePool
- **Post-game (level > 0):** 5% nextPrizePool, 95% futurePrizePool

The split accounts for 100% of `totalPrice`. No ETH is lost or unaccounted.

### Lootbox entry (lines 519-524)

```solidity
uint16 deityLootboxBps = lootboxPresaleActive ? DEITY_LOOTBOX_PRESALE_BPS : DEITY_LOOTBOX_POST_BPS;
uint256 lootboxAmount = (totalPrice * deityLootboxBps) / 10_000;
```

- Presale: 20% lootbox value
- Post-presale: 10% lootbox value
- Lootbox is a **virtual** accounting entry (not additional ETH) -- it determines the buyer's weight in the lootbox RNG drawing.

---

## 7. Edge Case Analysis

### k=0 (first deity pass)

- `basePrice = 24e18 + (0 * 1 * 1e18) / 2 = 24e18` = 24 ETH
- `deityPassOwners.length` starts at 0
- After purchase: array length = 1, next buyer sees k=1
- CORRECT

### k=31 (last deity pass)

- `basePrice = 24e18 + (31 * 32 * 1e18) / 2 = 24e18 + 496e18 = 520e18` = 520 ETH
- `deityPassOwners.length` = 31 before purchase
- After purchase: array length = 32
- Next purchase attempt: any symbolId 0-31 hits `deityBySymbol[symbolId] != address(0)`, any >= 32 hits `symbolId >= 32`. All paths revert.
- CORRECT

### k=32 (should be unreachable)

- All 32 symbols are taken after 32 purchases.
- `deityBySymbol[0..31]` all map to non-zero addresses.
- `symbolId >= 32` catches inputs >= 32.
- Double defense: even if this were somehow bypassed, the checked arithmetic at k=32 computes `32 * 33 * 1e18 / 2 = 528e18`, which is well within uint256 range (no overflow to exploit).
- UNREACHABLE as designed

### Duplicate buyer

- `deityPassCount[buyer] != 0` (line 439) prevents the same address from purchasing twice.
- A buyer who transfers their pass (`deityPassCount[from] = 0` in `_handleDeityPassTransfer`) could theoretically re-purchase, but:
  - They would need a fresh symbolId (their old symbolId now belongs to the transferee).
  - Their `deityPassCount` resets to 0, so they pass the check.
  - This appears intentional: transfer forfeits the pass, re-purchase is a fresh transaction at the current k price.

### Deity pass transfer and k count

- `_handleDeityPassTransfer` (line 538) replaces the owner in `deityPassOwners` (line 562-569) rather than removing them. The array length stays constant.
- k = `deityPassOwners.length` always equals the total passes ever sold, regardless of transfers.
- This is correct: transfers do not reduce the supply, so the price curve should not decrease.

---

## 8. Interaction with Whale Bundle System

- Deity pass and whale bundle are **independent** purchase flows.
- `_purchaseDeityPass` does not read or write any whale bundle state (`whaleBoonDay`, `whaleBoonDiscountBps`, etc.).
- Deity pass holders receive whale-equivalent tickets (lines 495-502), meaning they participate in the same ticket system but through a separate code path.
- A deity pass holder cannot purchase a lazy pass: `if (deityPassCount[buyer] != 0) revert E()` at line 338 in `_purchaseLazyPass` blocks this.
- A deity pass holder CAN purchase whale bundles (no deity check in `_purchaseWhaleBundle`). This is consistent: deity holders may want additional ticket coverage beyond their 100-level allocation.

---

## 9. symbolId Uniqueness Verification

The system enforces uniqueness through dual mappings:

1. **Forward mapping:** `deityPassSymbol[buyer] = symbolId` (line 477) -- address to symbol
2. **Reverse mapping:** `deityBySymbol[symbolId] = buyer` (line 478) -- symbol to address

The gate at line 438 (`deityBySymbol[symbolId] != address(0)`) prevents any symbolId from being assigned twice. Once taken, the reverse mapping is non-zero for that symbolId permanently (transfers update it to the new owner, never delete it).

On transfer (line 549): `deityBySymbol[symbolId] = to` -- the symbol stays taken, just mapped to the new owner. No double-claim is possible.

---

## 10. NatSpec Documentation Accuracy Check

**NatSpec (line 420):** "Price: 24 + T(n) ETH where n = passes sold so far, T(n) = n*(n+1)/2."

**Actual formula (line 442):** `DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2` where `k = deityPassOwners.length`.

**Assessment:** The NatSpec is accurate. T(n) = n*(n+1)/2 matches the code. The documentation says "First pass costs 24 ETH, last (32nd) costs 520 ETH" which is confirmed:
- First pass: k=0, T(0) = 0, price = 24 ETH. CORRECT.
- Last pass: k=31, T(31) = 31*32/2 = 496, price = 24 + 496 = 520 ETH. CORRECT.

**NatSpec (line 425):** "Fund distribution: Pre-game (level 0): 30% next pool, 70% future pool"

**Actual (lines 511-512):** `nextShare = (totalPrice * 3000) / 10_000` = 30%. Remainder to futurePrizePool. CORRECT.

---

## MATH-02 Final Verdict: PASS

| Criterion | Result |
|-----------|--------|
| T(n) formula correctly implements triangular pricing | PASS |
| No overflow at k=0, k=1, k=10, k=31 (actual range) | PASS |
| No overflow at k=100 (theoretical) | PASS |
| No overflow at k=1000 (theoretical) | PASS |
| Division always exact (even product property) | PASS |
| k bounded to [0, 31] by symbolId < 32 check | PASS |
| Checked arithmetic provides belt-and-suspenders overflow protection | PASS |
| Strict equality msg.value check prevents under/overpayment | PASS |
| ETH routing accounts for 100% of totalPrice | PASS |
| symbolId uniqueness enforced by dual mapping | PASS |
| State mutations only occur after all validation checks | PASS |

**Summary:** The deity pass triangular pricing formula T(n) = 24 + n*(n+1)/2 ETH is correctly implemented with zero overflow risk. The maximum intermediate value at the actual bound (k=31) is 992e18, which is 10^58 times smaller than uint256 max. Even at the theoretical stress test of k=1000, the headroom exceeds 10^53. The formula produces exact results with no rounding loss. All ETH is accounted for in the prize pool split. No findings.

**Severity:** No findings at any severity level.
