# ECON-04: MEV Attack Surface on Ticket Purchase Price Escalation

**Auditor:** Automated security audit (Phase 05, Plan 04)
**Date:** 2026-03-01
**Scope:** MEV/sandwich/frontrunning vectors on ticket pricing at level boundaries
**Verdict:** ECON-04 **PASS** -- No profitable MEV strategy exists for ticket purchase price escalation

---

## Executive Summary

Standard MEV attacks (sandwich, frontrunning) rely on price being affected by transaction ordering within a block. This analysis examines whether any such value extraction is possible in the Degenerus ticket pricing system. The key finding is that the combination of (1) deterministic storage-variable pricing updated atomically with the RNG lock, (2) `rngLockedFlag` blocking all ticket purchases during price transitions, and (3) per-level prize pool isolation eliminates all standard MEV vectors on ticket pricing.

---

## 1. Price Determinism Verification

### 1.1 PriceLookupLib: Pure Function (No State Reads)

**File:** `contracts/libraries/PriceLookupLib.sol` (47 lines)

```solidity
function priceForLevel(uint24 targetLevel) internal pure returns (uint256) {
    if (targetLevel < 5) return 0.01 ether;
    if (targetLevel < 10) return 0.02 ether;
    if (targetLevel < 30) return 0.04 ether;
    // ... step-function continues
}
```

**Confirmed:** This is a `pure` function with zero state reads (no `sload`, no storage variable access). It maps level number to price via constant comparisons. No oracle, no AMM, no external data source.

### 1.2 The `price` Storage Variable: Actual Purchase Price Source

**Critical finding:** Ticket purchases do **NOT** use `PriceLookupLib` directly. They use the `price` storage variable.

**Evidence from MintModule (`contracts/modules/DegenerusGameMintModule.sol`):**

- Line 604: `uint256 priceWei = price;` -- reads the storage variable
- Line 614: `ticketCost = (priceWei * ticketQuantity) / (4 * TICKET_SCALE);` -- uses it for cost
- Line 809-810: `uint256 priceWei = price;` / `uint256 costWei = (priceWei * quantity) / (4 * TICKET_SCALE);` -- same in `_callTicketPurchase`

**The `price` storage variable** is defined in `DegenerusGameStorage.sol` at slot 2:
- Type: `uint128`
- Initial value: `0.01 ether`
- Updated in: `AdvanceModule._finalizeRngRequest()` at tier boundaries (lines 1100-1121)

This creates a theoretical sandwich window around `advanceGame()` calls that trigger a level transition. Analysis follows.

### 1.3 When `price` Is Updated

The `price` variable is updated inside `_finalizeRngRequest()` (AdvanceModule lines 1096-1123), which is called from `_requestRng()`, which is called from `rngGate()` during `advanceGame()`.

The update occurs **only** at tier boundaries (not every level):
- Level 5: 0.01 -> 0.02 ETH
- Level 10: 0.02 -> 0.04 ETH
- Level 30: 0.04 -> 0.08 ETH
- Level 60: 0.08 -> 0.12 ETH
- Level 100: 0.16 -> 0.24 ETH
- Level x01 (101, 201, ...): 0.24 -> 0.04 ETH (saw-tooth drop)
- Level x30: 0.04 -> 0.08 ETH
- Level x60: 0.08 -> 0.12 ETH
- Level x00 (200, 300, ...): 0.16 -> 0.24 ETH

**Note:** Within a tier (e.g., levels 10-29), `price` is NOT updated at each level. It stays at 0.04 ETH for all 20 levels.

---

## 2. Sandwich Attack on advanceGame() -- BLOCKED by rngLockedFlag

### 2.1 The Theoretical Attack

A block proposer observes a pending `advanceGame()` transaction that will trigger a level transition at a tier boundary (e.g., level 4 -> 5, where price goes from 0.01 to 0.02 ETH).

**Proposed sandwich:**
1. Front-run: Buy tickets at the OLD (lower) price before `advanceGame`
2. Include: `advanceGame()` which updates `price`
3. Back-run: The attacker's tickets were bought cheaply, competing in a higher-value pool

### 2.2 Why This Attack Fails: Atomic RNG Lock

The `price` update happens inside `_finalizeRngRequest()`, which **simultaneously** sets `rngLockedFlag = true` (line 1085):

```solidity
function _finalizeRngRequest(bool isTicketJackpotDay, uint24 lvl, uint256 requestId) private {
    // ... VRF request setup ...
    rngLockedFlag = true;                    // <-- Line 1085: Lock set
    // ...
    if (isTicketJackpotDay && !isRetry) {
        level = lvl;                          // <-- Line 1097: Level updated
        if (lvl == 5) {
            price = uint128(0.02 ether);      // <-- Line 1101: Price updated
        }
        // ...
    }
}
```

Meanwhile, `_callTicketPurchase()` in MintModule checks:

```solidity
function _callTicketPurchase(...) private {
    if (rngLockedFlag) revert E();            // <-- Line 802: Blocks ALL ticket purchases
    // ...
}
```

**The `rngLockedFlag` is set BEFORE `price` is updated** (line 1085 before lines 1100-1121, within the same function). Since Solidity storage writes are visible within the same transaction, by the time `price` changes, `rngLockedFlag` is already true.

**Any subsequent transaction** in the same block trying to buy tickets will revert with `E()` because `rngLockedFlag` is true. The flag remains true until `_unlockRng()` is called in a later `advanceGame()` call (on a different day).

### 2.3 Sandwich Timing Analysis

The complete level transition sequence is:

```
Day N:     advanceGame() -> lastPurchaseDay = true  (tickets still purchasable at old price)
Day N+1:   advanceGame() -> rngGate() -> _requestRng() -> _finalizeRngRequest()
                            |-> rngLockedFlag = true   (tickets BLOCKED)
                            |-> level = lvl            (level incremented)
                            |-> price = newPrice       (price updated)
                            Returns 1 (RNG_REQUESTED stage)
Day N+2+:  VRF fulfillment arrives (callback stores rngWordCurrent)
Day N+2+:  advanceGame() -> rngGate() returns word -> processes jackpot -> _endPhase()
           -> jackpotPhaseFlag = true
           ... (jackpot phase, multiple days) ...
Day N+X:   advanceGame() -> _processPhaseTransition() -> _unlockRng()
                            |-> rngLockedFlag = false  (tickets UNBLOCKED)
                            |-> jackpotPhaseFlag = false
```

**Key observation:** From the moment `price` changes until tickets are purchasable again, the entire jackpot phase must complete (multiple days). There is **no single-block or same-day window** where `price` has changed but tickets are still purchasable at the old price.

### 2.4 Front-Running the `lastPurchaseDay` Transition

A subtler attack: On the day `lastPurchaseDay` becomes true (Day N), the attacker buys many tickets knowing this is the last day. Does this help?

**No.** All tickets bought on Day N are at the CURRENT price tier (before any change). The price does not change until Day N+1 when `_finalizeRngRequest` runs. Everyone buys at the same price on Day N. There is no information asymmetry -- `lastPurchaseDay` is set in the same `advanceGame()` transaction that checks `nextPrizePool >= levelPrizePool[purchaseLevel - 1]`, and this condition is visible on-chain. The flag itself does not change the price.

---

## 3. Transaction Ordering Within a Level -- No Price Impact

### 3.1 Flat Step-Function Pricing

Within a single level, every ticket costs the same:
- `costWei = (priceWei * ticketQuantity) / (4 * TICKET_SCALE)`
- `priceWei` is a fixed storage variable that does not change within a level
- There is no AMM curve, no bonding curve, no slippage
- Buying 1 ticket or 10,000 tickets does not change the price for the next buyer

### 3.2 No Volume-Dependent Price Impact

Standard DEX sandwich attacks rely on price impact: large buy -> price moves up -> victim buys at higher price -> attacker sells at profit. In Degenerus:
- Price does not move based on volume
- There is no sell mechanism (tickets cannot be resold)
- All tickets within a level cost identical amounts per unit

### 3.3 Ticket Queue Position and Jackpot Probability

**Question:** Does being earlier in the ticket queue affect jackpot probability?

Tickets are processed in the order they were queued. The scatter jackpot is trait-based (VRF determines which trait wins), and all tickets with the matching trait are paid. The daily jackpot uses a VRF-derived random word applied uniformly. Queue position does not affect the probability of winning any jackpot.

**Queue position is irrelevant** because:
1. Scatter jackpot: Based on trait ownership, not position
2. Daily jackpot: VRF-based random selection across all eligible tickets
3. BAF (Best Affiliate Fund): Based on affiliate score, not ticket position
4. All jackpot distributions use VRF randomness that is committed AFTER all purchases for the level are complete

**Conclusion:** Transaction ordering within a level creates zero extractable value.

---

## 4. advanceGame Timing Control by Block Proposer

### 4.1 What the Proposer Controls

A block proposer (validator) can:
- Choose whether to include an `advanceGame()` transaction in their block
- Order transactions within their block (potentially their own purchases before/after advanceGame)

### 4.2 Day-Index Gate Prevents Multi-Advance

```solidity
if (day == dailyIdx) revert NotTimeYet();   // AdvanceModule line 140
```

`advanceGame()` can only succeed once per day (after a day boundary crossing). A proposer cannot:
- Call advanceGame multiple times in one block
- Skip ahead multiple levels in one transaction
- Delay advanceGame beyond one block (~12 seconds) since any user can submit it in the next block

### 4.3 Outcome Determinism

Even if a proposer delays advanceGame by one block:
- The VRF word is already committed (stored in `rngWordCurrent`)
- The game state is deterministic given the VRF word
- Jackpot outcomes are computed from VRF + ticket ownership, neither of which the proposer can change by reordering
- The day index is derived from `block.timestamp` via `_simulatedDayIndexAt()`, and manipulating timestamp by the allowed 12-second drift does not change the day boundary

### 4.4 Same-Block Purchase + advanceGame Ordering

**Scenario:** Proposer places their own `purchase()` tx BEFORE `advanceGame()` in the same block.

**Result:** The proposer buys tickets at the current level/price, then advanceGame processes (may or may not transition). This is identical to any user buying tickets before calling advanceGame. No advantage:
- If advanceGame sets `lastPurchaseDay = true`: the proposer bought at the current price, same as everyone else that day
- If advanceGame transitions the level: `rngLockedFlag` blocks any purchases AFTER the transition. The proposer's pre-transition purchase was at the old price, but so was every other purchase that day

**Conclusion:** Block proposer timing control over advanceGame creates no MEV opportunity.

---

## 5. Lootbox MEV Analysis

### 5.1 VRF-Based Randomness -- Unmanipulable

Lootbox outcomes are determined by VRF words (confirmed unmanipulable in Phase 2). The VRF fulfillment stores the random word, and lootbox opening uses entropy stepping from that committed word. Players cannot predict or influence outcomes.

### 5.2 Front-Running VRF Fulfillment

**Scenario:** A block proposer sees the VRF `rawFulfillRandomWords` callback pending and front-runs it with a lootbox purchase.

**Result:** The player's lootbox purchase is assigned to the CURRENT `lootboxRngIndex`. The VRF callback finalizes the PREVIOUS index's word. The player's purchase will use the NEXT VRF word, not the one being fulfilled. There is no information advantage.

### 5.3 Lootbox Pricing During Level Transitions

Lootbox purchases specify the ETH amount directly (`lootBoxAmount` parameter). The `price` storage variable is used only for:
- Affiliate BURNIE conversion: `_ethToBurnieValue(lootboxFreshEth, priceWei)` (line 732)
- Quest progress units: `lootBoxAmount / priceWei` (line 757)

Neither affects the lootbox's actual ETH value or EV. The EV multiplier depends on the player's activity score, not the price variable.

**Conclusion:** No meaningful lootbox MEV vector exists.

---

## 6. Whale Bundle / Deity Pass Purchase MEV

### 6.1 Whale Bundle: Fixed Pricing, No MEV

Whale bundle prices are hardcoded:
- 2.4 ETH (levels 0-3, or with level guard as intended but currently missing per Finding F01)
- 4.0 ETH (all other levels)

These prices do not change based on transaction ordering or volume. No sandwich opportunity exists.

### 6.2 Deity Pass: Escalating Price Frontrunning

Deity pass pricing escalates with `deityPassOwners.length`:

```solidity
uint256 k = deityPassOwners.length;
uint256 basePrice = DEITY_PASS_BASE + (k * (k + 1) * 1 ether) / 2;
// First pass: 24 ETH, second: 25 ETH, third: 27 ETH, ..., 32nd: 520 ETH
```

**Frontrunning scenario:** Attacker sees a victim's `purchaseDeityPass` transaction. Attacker front-runs with their own purchase, making the victim pay k+1 price instead of k price. Attacker gets pass at k price instead of k+1.

**Why this is non-exploitable:**

1. **Tiny target pool:** Only 32 deity pass symbols exist (symbolId 0-31). Maximum 32 purchases ever. The chance of two deity pass purchases being pending in the same mempool is extremely low.

2. **One pass per address:** `if (deityPassCount[buyer] != 0) revert E()` -- each address can only buy one deity pass. The attacker cannot repeatedly frontrun.

3. **Price escalation makes frontrunning costly:** The attacker saves T(k) - T(k-1) = k ETH by being k-th instead of (k+1)-th buyer. But they must actually SPEND 24 + T(k) ETH to buy the pass. The "savings" are only relevant if the attacker already intended to buy a pass. Pure front-running for profit is impossible because:
   - The attacker cannot resell the pass back to the victim (transfers require 5 ETH BURNIE cost)
   - The attacker cannot refund the pass (refunds only available pre-level-1 with DEITY_PASS_REFUND_DAYS)
   - The attacker is stuck with a 24+ ETH asset in a gaming protocol

4. **Boon discount complicates timing:** Players may have deity pass boon discounts (10/25/50%) that expire on a per-day basis. A frontrunner buying without a boon pays full price.

**Conclusion:** Deity pass frontrunning is theoretically possible but economically impractical. The attacker must commit 24+ ETH, can only do it once, and the value extracted (k ETH, where k is the current pass count) requires being an actual deity pass buyer. Rated **INFORMATIONAL** -- not an exploitable MEV vector.

---

## 7. Cross-Level Ticket Arbitrage Analysis

### 7.1 Ticket Queue Isolation by Level

Tickets purchased during a level are queued for THAT level's prize pool:

```solidity
// MintModule line 807
uint24 targetLevel = jackpotPhaseFlag ? level : level + 1;
```

During purchase phase, tickets target `level + 1` (the next level). When the level transitions:

```solidity
// AdvanceModule line 220
levelPrizePool[purchaseLevel] = nextPrizePool;
```

The `nextPrizePool` is assigned to the current level's prize pool. All ticket holders for that level compete for that level's pool. When the next level starts:

```solidity
// AdvanceModule line 242
_drawDownFuturePrizePool(lvl);
```

A new `nextPrizePool` is funded from `futurePrizePool`. Level N+1 tickets compete for Level N+1's pool, not Level N's pool.

### 7.2 No Cross-Level Arbitrage

Tickets bought at Level N price cannot participate in Level N+1's jackpot:
- Level N tickets are in Level N's queue, resolved at Level N's jackpot
- Level N+1 starts with a fresh queue, funded by fresh deposits + futurePrizePool drawdown
- There is no mechanism to carry tickets across levels

Even if the price changes at a tier boundary, the ticket buyer paid the correct price for the level they entered. Their expected return is proportional to their share of THAT level's total deposits and prize pool.

**Conclusion:** Cross-level ticket arbitrage is impossible by construction.

---

## 8. ECON-04 Verdict

### Per-Vector Summary

| MEV Vector | Status | Reasoning |
|---|---|---|
| Sandwich on advanceGame (price change) | **ELIMINATED** | `rngLockedFlag` blocks ALL ticket purchases atomically with `price` update. No window exists where new price is readable but purchases are possible. |
| Frontrunning lastPurchaseDay | **ELIMINATED** | No price change occurs on the day `lastPurchaseDay` is set. All purchases on that day use the same price. |
| Transaction ordering within a level | **ELIMINATED** | Step-function pricing: every ticket at the same level costs the same regardless of volume or ordering. No price impact, no slippage. |
| Block proposer advanceGame timing | **ELIMINATED** | VRF word committed before advanceGame. Day-index gate limits to one advance per day. Outcome is deterministic. |
| Lootbox frontrunning | **ELIMINATED** | VRF randomness unmanipulable. Lootbox RNG index assigned at purchase, resolved by later VRF. No information advantage. |
| Cross-level ticket arbitrage | **ELIMINATED** | Per-level prize pool isolation. Tickets bought at level N compete for level N pool only. |
| Deity pass frontrunning | **INFORMATIONAL** | Theoretically possible but economically impractical: requires 24+ ETH commitment, one-pass-per-address limit, tiny pool (32 max), no profitable exit. |
| Whale bundle sandwich | **ELIMINATED** | Fixed pricing (2.4/4.0 ETH). No dynamic component. |

### Verdict: ECON-04 PASS

**MEV/sandwich attacks on ticket purchase price escalation cannot extract value at phase boundaries.**

The protocol's defenses are structural:

1. **Deterministic step-function pricing** (not AMM/bonding curve) eliminates volume-based price impact
2. **Atomic rngLockedFlag + price update** in `_finalizeRngRequest` eliminates sandwich windows
3. **Per-level prize pool isolation** eliminates cross-level arbitrage
4. **Multi-day VRF cycle** for level transitions (not single-block) eliminates same-block sandwich
5. **One-advance-per-day gate** (`NotTimeYet`) eliminates multi-level manipulation

The only non-eliminated vector (deity pass frontrunning) is rated INFORMATIONAL due to extreme impracticality.

---

## Appendix: Code Reference Index

| Location | What | Line(s) |
|---|---|---|
| `PriceLookupLib.sol` | Pure price function | 21-46 |
| `DegenerusGameStorage.sol` | `price` storage variable | 278-279 |
| `DegenerusGameMintModule.sol` | `priceWei = price` in purchase | 604, 809 |
| `DegenerusGameMintModule.sol` | `rngLockedFlag` check blocking tickets | 802 |
| `DegenerusGameMintModule.sol` | Lootbox rngLocked partial check | 607 |
| `DegenerusGameAdvanceModule.sol` | `rngLockedFlag = true` | 1085 |
| `DegenerusGameAdvanceModule.sol` | `price` update at tier boundaries | 1100-1121 |
| `DegenerusGameAdvanceModule.sol` | `level = lvl` (level increment) | 1097 |
| `DegenerusGameAdvanceModule.sol` | Day-index gate (`NotTimeYet`) | 140 |
| `DegenerusGameAdvanceModule.sol` | `_unlockRng` (rngLockedFlag = false) | 1158-1163 |
| `DegenerusGameAdvanceModule.sol` | `_endPhase` (jackpot phase start) | 370-380 |
| `DegenerusGameAdvanceModule.sol` | `_drawDownFuturePrizePool` | 869-881 |
| `DegenerusGameAdvanceModule.sol` | `levelPrizePool[purchaseLevel] = nextPrizePool` | 220 |
| `DegenerusGameWhaleModule.sol` | Deity pass pricing: `DEITY_PASS_BASE + T(k)` | 441-442 |

---

*Audit completed: 2026-03-01*
*Requirement: ECON-04 PASS*
