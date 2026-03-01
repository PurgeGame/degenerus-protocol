# Phase 03a Plan 06: Input Validation Sweep Findings

**Date:** 2026-03-01
**Scope:** MintModule, JackpotModule, EndgameModule
**Auditor:** Automated read-only analysis
**Contract Files (READ-ONLY):**
- `contracts/modules/DegenerusGameMintModule.sol` (1114 lines)
- `contracts/modules/DegenerusGameJackpotModule.sol` (2740 lines)
- `contracts/modules/DegenerusGameEndgameModule.sol` (517 lines)
- `contracts/DegenerusGame.sol` (entry points, _resolvePlayer, _processMintPayment)
- `contracts/interfaces/IDegenerusGame.sol` (MintPaymentKind enum)

---

## 1. MintModule Input Validation Matrix

### 1.1 `purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`

Entry flow: `DegenerusGame.purchase()` -> `_resolvePlayer(buyer)` -> `_purchaseFor()` -> delegatecall to `MintModule.purchase()` -> `_purchaseFor()`.

| Parameter | Type | Validation | Mechanism | Bypass Possible? | Line(s) |
|-----------|------|------------|-----------|------------------|---------|
| `buyer` | `address` | YES | `_resolvePlayer`: address(0) -> msg.sender; non-sender requires operator approval | NO - validated in DegenerusGame.sol:497-503 before delegatecall | Game:497-503 |
| `ticketQuantity` | `uint256` | YES | Three-layer: (1) > type(uint32).max reverts at Mint:800,613; (2) costWei==0 reverts at Mint:811; (3) costWei < TICKET_MIN_BUYIN_WEI reverts at Mint:812 | NO | Mint:800,811,812,613 |
| `lootBoxAmount` | `uint256` | YES (minimum) | lootBoxAmount != 0 && < LOOTBOX_MIN (0.01 ETH) reverts at Mint:608. No explicit upper bound. | NO for minimum. Upper bound analyzed below. | Mint:608 |
| `affiliateCode` | `bytes32` | N/A | Not validated; bytes32(0) is handled gracefully by affiliate contract. No security implication. | N/A | -- |
| `payKind` | `MintPaymentKind` | YES (defense-in-depth) | Layer 1: ABI decoder rejects out-of-range enum values. Layer 2: else-revert in _callTicketPurchase at Mint:870-871. Layer 3: else-revert in _processMintPayment at Game:1076-1077. | NO - triple-validated | ABI, Mint:870, Game:1077 |

### 1.2 `purchaseBurnieLootbox(buyer, burnieAmount)`

Entry flow: `DegenerusGame.purchaseBurnieLootbox()` -> `_resolvePlayer(buyer)` -> delegatecall to `MintModule.purchaseBurnieLootbox()`.

| Parameter | Type | Validation | Mechanism | Bypass Possible? | Line(s) |
|-----------|------|------------|-----------|------------------|---------|
| `buyer` | `address` | YES (double) | `_resolvePlayer` in Game:611 converts address(0) -> msg.sender. Additionally, explicit `address(0)` check at Mint:568 (`if (buyer == address(0)) revert E()`). | NO - double-guarded | Game:497-503, Mint:568 |
| `burnieAmount` | `uint256` | YES | `< BURNIE_LOOTBOX_MIN (1000 ether)` reverts at Mint:956. | NO | Mint:956 |

### 1.3 `purchaseCoin(buyer, ticketQuantity, lootBoxBurnieAmount)`

Entry flow: `DegenerusGame.purchaseCoin()` -> `_resolvePlayer(buyer)` -> delegatecall to `MintModule.purchaseCoin()`.

| Parameter | Type | Validation | Mechanism | Bypass Possible? | Line(s) |
|-----------|------|------------|-----------|------------------|---------|
| `buyer` | `address` | YES | `_resolvePlayer` in Game:590 | NO | Game:497-503 |
| `ticketQuantity` | `uint256` | YES | Routed to `_callTicketPurchase` which checks qty==0 and qty > type(uint32).max at Mint:800, plus costWei checks | NO | Mint:800,811,812 |
| `lootBoxBurnieAmount` | `uint256` | YES | Routed to `_purchaseBurnieLootboxFor` which checks `< BURNIE_LOOTBOX_MIN` at Mint:956 | NO | Mint:956 |

---

## 2. INPT-01: Ticket Quantity Bounds Deep Dive

### 2.1 Upper Bound

**Validation:** `ticketQuantity > type(uint32).max` reverts (Mint:613 in `_purchaseFor`, Mint:800 in `_callTicketPurchase`).

- type(uint32).max = 4,294,967,295
- At maximum ticketQuantity and minimum price (0.01 ETH): costWei = (0.01e18 * 4294967295) / 400 = ~107,374,182 ETH
- This is far above any realistic ETH holding, so the uint32 cap is effectively unreachable. The real upper bound is msg.value.

**Post-boost overflow protection:** After purchase boost is applied, `adjustedQuantity` is capped at `type(uint32).max` again at Mint:830-832.

**Verdict: PASS** -- Upper bound comprehensively enforced.

### 2.2 Lower Bound (ticketQuantity == 0)

**Path analysis:**
- `ticketQuantity == 0` in `_purchaseFor`: skips to lootbox path at Mint:612. If lootBoxAmount is also 0, totalCost == 0 reverts at Mint:618. If lootBoxAmount != 0, purchase proceeds as lootbox-only. Correct behavior.
- `ticketQuantity == 0` in `_callTicketPurchase`: explicit `quantity == 0` check at Mint:800 reverts.

**Verdict: PASS** -- Zero quantity is rejected in all ticket-purchase paths.

### 2.3 ticketQuantity == 1 (costWei rounds to zero check)

**Trace:** costWei = (priceWei * 1) / 400.
- At priceWei = 0.01 ether: costWei = 10000000000000000 / 400 = 25,000,000,000,000 = 0.000025 ETH
- This is > 0 (passes costWei == 0 check) but < 0.0025 ETH (fails TICKET_MIN_BUYIN_WEI check at Mint:812)
- Correctly rejected.

### 2.4 Minimum Valid ticketQuantity at Each Price Tier

Formula: `costWei = (priceWei * ticketQuantity) / 400`
Constraint: `costWei >= TICKET_MIN_BUYIN_WEI (0.0025 ETH)`

| Price Tier | priceWei | Levels | Min Qty | Resulting costWei |
|------------|----------|--------|---------|-------------------|
| 0.01 ETH | 10^16 | 0-4 | 100 | 0.002500 ETH |
| 0.02 ETH | 2*10^16 | 5-9 | 50 | 0.002500 ETH |
| 0.04 ETH | 4*10^16 | 10-29, x01-x29 | 25 | 0.002500 ETH |
| 0.08 ETH | 8*10^16 | 30-59, x30-x59 | 13 | 0.002600 ETH |
| 0.12 ETH | 12*10^16 | 60-89, x60-x89 | 9 | 0.002700 ETH |
| 0.16 ETH | 16*10^16 | 90-99, x90-x99 | 7 | 0.002800 ETH |
| 0.24 ETH | 24*10^16 | Milestones (100,200...) | 5 | 0.003000 ETH |

Note: At the 0.01 ETH tier, minimum quantity 100 scaled means 100/400 = 0.25 of a full ticket. This is a quarter-ticket purchase, the smallest allowed unit.

**Verdict: PASS (INPT-01)** -- Ticket quantity is bounded on all sides: upper by uint32 cap, lower by costWei > 0 and TICKET_MIN_BUYIN_WEI. Integer rounding protects against dust quantities.

---

## 3. INPT-02: Lootbox Amount Bounds

### 3.1 Minimum

**Validation:** `lootBoxAmount != 0 && lootBoxAmount < LOOTBOX_MIN` reverts (Mint:608).
- LOOTBOX_MIN = 0.01 ether
- Zero is allowed (skips lootbox path entirely, only tickets purchased)

**Verdict: PASS** -- Minimum enforced.

### 3.2 Maximum (No Explicit Upper Bound)

**Analysis of overflow risk at extreme values:**

The lootBoxAmount feeds into several BPS calculations:
```solidity
uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;  // Mint:708
uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;      // Mint:709
uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;    // Mint:710
```

Maximum futureBps = 9000 (worst case).
At lootBoxAmount = 10,000 ETH (10^22 wei): `10^22 * 9000 = 9 * 10^25`, well within uint256 (max ~1.15 * 10^77).

**Overflow threshold:** `type(uint256).max / 10000 = ~1.15 * 10^73 wei = ~1.15 * 10^55 ETH`. Far beyond total ETH supply (~120M ETH = 1.2 * 10^26 wei).

**Accumulator analysis:**
- `lootboxEthTotal += lootBoxAmount` (Mint:696): uint256 accumulator, cannot overflow with realistic values.
- `futurePrizePool += futureDelta` (Mint:718): uint256, same.
- `lootboxEth[index][buyer]` packing: amount stored in lower 232 bits. Max = 2^232 - 1 = ~6.9 * 10^69 wei. Far beyond ETH supply.
- `lootboxPresaleMintEth += lootBoxAmount` (Mint:701): uint256, same.

**Practical bound:** msg.value constrains the actual maximum. Even with Claimable/Combined payment, claimableWinnings limits the amount.

**Verdict: PASS (INPT-02)** -- No explicit upper bound exists, but overflow is impossible with uint256 arithmetic. The practical bound is the user's available balance. Severity: INFORMATIONAL (no action needed).

---

## 4. INPT-03: MintPaymentKind Enum Validation

### 4.1 ABI Layer (Layer 1)

Solidity 0.8+ ABI decoder reverts when decoding an out-of-range enum value from calldata. The `MintPaymentKind` enum has 3 variants (0=DirectEth, 1=Claimable, 2=Combined). Any calldata value >= 3 will revert at the ABI decode stage.

### 4.2 Application Layer -- _callTicketPurchase (Layer 2)

At Mint:860-872, the payKind is checked via if/else if/else:
```solidity
if (payKind == MintPaymentKind.DirectEth) { ... }
else if (payKind == MintPaymentKind.Claimable) { ... }
else if (payKind == MintPaymentKind.Combined) { ... }
else { revert E(); }  // Line 870-871
```

### 4.3 Application Layer -- _processMintPayment (Layer 3)

At Game:1037-1078, the payKind is checked identically:
```solidity
if (payKind == MintPaymentKind.DirectEth) { ... }
else if (payKind == MintPaymentKind.Claimable) { ... }
else if (payKind == MintPaymentKind.Combined) { ... }
else { revert E(); }  // Line 1076-1077
```

### 4.4 Direct Delegatecall Bypass Analysis

**Question:** Can a direct delegatecall bypass ABI encoding and pass a raw uint8 value > 2?

**Answer: NO.** The modules are separate contracts. The only way to execute module code in the context of DegenerusGame is through DegenerusGame's dispatch functions, which use `abi.encodeWithSelector(...)` (e.g., Game:567-574). The ABI encoding uses the compiler's type system, so the enum is correctly encoded. External calls to module contracts directly would operate on the module's own empty storage (useless) and are not callable by users because:
1. Modules have no access control of their own -- they rely on DegenerusGame being the only caller via delegatecall.
2. Direct external calls to a module execute in the module's context, not the game's storage. No state corruption possible.

**Verdict: PASS (INPT-03)** -- Triple-layered defense-in-depth. ABI decoder + two application-level else-reverts. No bypass path exists.

---

## 5. INPT-04: Zero-Address Guard Sweep

### 5.1 MintModule Functions

| Function | Parameter | Guard | Mechanism | Verdict |
|----------|-----------|-------|-----------|---------|
| `purchase(buyer, ...)` | `buyer` | YES | `_resolvePlayer` in DegenerusGame.sol:497-503 converts address(0) to msg.sender before delegatecall | PASS |
| `purchaseBurnieLootbox(buyer, ...)` | `buyer` | YES (double) | `_resolvePlayer` in Game:611 + explicit `address(0)` revert in Mint:568 | PASS |
| `purchaseCoin(buyer, ...)` | `buyer` | YES | `_resolvePlayer` in Game:590 | PASS |
| `_callTicketPurchase(buyer, payer, ...)` | `buyer`, `payer` | INTERNAL | Called only from `_purchaseFor` and `_purchaseCoinFor` with pre-validated addresses from `_resolvePlayer` | PASS (guarded by caller) |

### 5.2 JackpotModule Functions

All JackpotModule functions are called via delegatecall from DegenerusGame's internal advance logic. None accept user-supplied addresses directly.

| Function | Visibility | Address Params | Guard | Verdict |
|----------|-----------|----------------|-------|---------|
| `payDailyJackpot(isDaily, lvl, randWord)` | external | None | N/A | PASS (no address params) |
| `payDailyJackpotCoinAndTickets(randWord)` | external | None | N/A | PASS (no address params) |
| `awardFinalDayDgnrsReward(lvl, rngWord)` | external | None | N/A | PASS (no address params) |
| `payEarlyBirdLootboxJackpot(lvl, rngWord)` | external | None | N/A | PASS (no address params) |
| `consolidatePrizePools(lvl, rngWord)` | external | None | N/A | PASS (no address params) |
| `processTicketBatch(lvl)` | external | None | N/A | PASS (no address params) |
| `payDailyCoinJackpot(lvl, randWord)` | external | None | N/A | PASS (no address params) |

**Internal address-handling functions:**

| Function | Address Param | Guard | Analysis | Verdict |
|----------|---------------|-------|----------|---------|
| `_addClaimableEth(beneficiary, weiAmount, entropy)` | `beneficiary` | IMPLICIT | Called with addresses from jackpot winner arrays. Winners come from `_randTraitTicket` which reads from `traitBurnTicket` mapping. Code explicitly checks `w != address(0)` at line 1432 before calling `_addClaimableEth`. Also, `_addClaimableEth` itself handles weiAmount==0 early return (line 916). | PASS |
| `_processAutoRebuy(player, ...)` | `player` | IMPLICIT | Called only from `_addClaimableEth`, which is only called with non-zero addresses (checked at call sites). | PASS (guarded by caller chain) |
| `_creditClaimable(beneficiary, weiAmount)` | `beneficiary` | NO (explicit) | In `DegenerusGamePayoutUtils.sol:30-36`. No address(0) check. However: all callers either check for address(0) before calling, or the address comes from validated storage. If address(0) were passed, it would credit `claimableWinnings[address(0)]`, which is harmless (no one can claim from address(0)). | PASS (low risk, defended by callers) |

### 5.3 EndgameModule Functions

| Function | Visibility | Address Params | Guard | Verdict |
|----------|-----------|----------------|-------|---------|
| `rewardTopAffiliate(lvl)` | external | None (reads from affiliate contract) | Returns early if `top == address(0)` at line 102. | PASS |
| `runRewardJackpots(lvl, rngWord)` | external | None | No address params. Internal winner handling via `_runBafJackpot` which delegates to jackpots contract. | PASS |
| `claimWhalePass(player)` | external | `player` | Called via DegenerusGame.claimWhalePass (Game:1777) which runs `_resolvePlayer` first. Additionally, `whalePassClaims[player] == 0` returns early (line 494-495). For address(0): `_resolvePlayer` converts to msg.sender, so address(0) never reaches the module. | PASS |
| `_addClaimableEth(beneficiary, weiAmount, entropy)` | private | `beneficiary` | Same as JackpotModule version. weiAmount==0 returns early (line 222). Called from `_runBafJackpot` with winner addresses from jackpots contract. `_queueWhalePassClaimCore` explicitly checks `winner == address(0)` (PayoutUtils:78). | PASS |

### 5.4 _queueWhalePassClaimCore Address(0) Guard

Located in `DegenerusGamePayoutUtils.sol:77-93`:
```solidity
function _queueWhalePassClaimCore(address winner, uint256 amount) internal {
    if (winner == address(0) || amount == 0) return;  // Explicit guard
    ...
}
```

**Verdict: PASS** -- Explicitly guards against address(0).

---

## 6. Delegatecall Parameter Forwarding Analysis

### 6.1 Encoding Safety

All delegatecalls from DegenerusGame to modules use `abi.encodeWithSelector(...)`:
```solidity
// Example from Game:564-575
(bool ok, bytes memory data) = ContractAddresses.GAME_MINT_MODULE.delegatecall(
    abi.encodeWithSelector(
        IDegenerusGameMintModule.purchase.selector,
        buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind
    )
);
```

**Safety properties:**
1. `abi.encodeWithSelector` uses Solidity's type system at compile time. Parameters are ABI-encoded according to their declared types.
2. No raw byte manipulation (`abi.encodePacked`, manual byte assembly, or `msg.data` forwarding) is used.
3. The function selector is a compile-time constant from the interface, ensuring the correct function is called.
4. The enum `MintPaymentKind` is encoded as a uint8 by the ABI encoder with range validation.

### 6.2 Direct Module Call Protection

**Question:** Can a user call module functions directly to bypass DegenerusGame's validation?

**Answer: NO.** Modules (MintModule, JackpotModule, EndgameModule) are deployed as separate contracts but are designed to be called only via delegatecall from DegenerusGame. If called directly:
1. They execute against their own empty storage (all storage slots are zeroed).
2. `address(this)` would be the module's address, not the game's address.
3. Any state changes would affect the module's own storage, not the game's.
4. No funds are held at module addresses.
5. External contract calls (e.g., to `coin`, `affiliate`) would fail because ContractAddresses constants point to contracts that check `msg.sender == GAME`.

There is no access control modifier on module external functions (e.g., `payDailyJackpot` is `external` with no modifier), but this is by design -- the only meaningful way to use these functions is via delegatecall from the game contract.

**Verdict: PASS** -- Parameter forwarding is type-safe via ABI encoding. No bypass path exists for direct module calls.

---

## 7. Summary Table: INPT Requirements

| Requirement | Description | Verdict | Severity | Details |
|-------------|-------------|---------|----------|---------|
| **INPT-01** | Ticket quantity bounds enforced on every purchase path | **PASS** | N/A | Upper: uint32 max. Lower: costWei > 0 + TICKET_MIN_BUYIN_WEI. Zero quantity: rejected. Min valid qty computed per price tier (5-100 depending on level). |
| **INPT-02** | Lootbox amount minimum enforced; no upper bound issue | **PASS** | INFORMATIONAL | Minimum: 0.01 ETH enforced. No explicit max, but uint256 arithmetic makes overflow impossible. Practical bound is user's balance. |
| **INPT-03** | MintPaymentKind enum validated by ABI decoder and application code | **PASS** | N/A | Triple validation: ABI decoder + else-revert in _callTicketPurchase + else-revert in _processMintPayment. Defense-in-depth. |
| **INPT-04** | Zero-address guards on all external-facing address parameters | **PASS** | N/A | All external entry points use `_resolvePlayer` (address(0) -> msg.sender). Internal functions either check callers or are guarded by caller chains. `_queueWhalePassClaimCore` has explicit address(0) guard. No missing guards found. |

---

## 8. Additional Observations

### 8.1 totalCost == 0 Revert (Mint:618)

The check `if (totalCost == 0) revert E()` at Mint:618 serves as a catch-all for the case where both ticketQuantity and lootBoxAmount are zero. This prevents a no-op purchase call that would waste gas without any meaningful action.

### 8.2 Lootbox Presale Block During RNG-Locked Jackpot Levels (Mint:607)

The check `if (lootBoxAmount != 0 && rngLockedFlag && lastPurchaseDay && (purchaseLevel % 5 == 0)) revert E()` prevents lootbox purchases during BAF/Decimator resolution windows. This is a state-dependent validation, not an input validation per se, but it prevents manipulation of lootbox pool during sensitive jackpot periods. Correctly implemented.

### 8.3 purchaseBurnieLootbox Redundant address(0) Check

`purchaseBurnieLootbox` at Mint:568 has `if (buyer == address(0)) revert E()`, but the buyer is already resolved via `_resolvePlayer` in DegenerusGame.sol:611 before the delegatecall. The explicit check in the module is redundant but provides defense-in-depth. No issue.

### 8.4 _callTicketPurchase: Double uint32 Clamp

The function checks `quantity > type(uint32).max` at Mint:800 (revert), then after applying purchase boost, clamps `adjustedQuantity` to `type(uint32).max` at Mint:830-832 (saturate, not revert). This is correct: the raw user quantity must fit in uint32 (strict), but the boosted quantity may overflow and should saturate (generous to user).

---

## 9. Findings Summary

**Total Findings: 0 (all checks PASS)**

No input validation vulnerabilities were found across MintModule, JackpotModule, or EndgameModule. All external-facing parameters are properly validated through a combination of:
1. `_resolvePlayer` for address parameters (address(0) -> msg.sender pattern)
2. Explicit bounds checks for numeric parameters (uint32 max, LOOTBOX_MIN, TICKET_MIN_BUYIN_WEI, BURNIE_LOOTBOX_MIN)
3. ABI decoder + application-level else-revert for enum parameters
4. Type-safe ABI encoding for delegatecall parameter forwarding
5. Defense-in-depth patterns (redundant checks at multiple layers)

The codebase demonstrates a strong input validation posture with no gaps identified.
