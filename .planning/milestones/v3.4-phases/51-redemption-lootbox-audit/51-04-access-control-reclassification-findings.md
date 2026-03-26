# 51-04: Access Control and Lootbox Reclassification Findings

**Audit date:** 2026-03-21
**Contracts:** DegenerusGame.sol, StakedDegenerusStonk.sol, DegenerusGameLootboxModule.sol, ContractAddresses.sol
**Requirements:** REDM-06, REDM-07

---

## REDM-06: Lootbox Reclassification -- No ETH Transfer

**Verdict: SAFE** (no ETH transfer occurs; internal accounting reclassification only)

**Sub-finding: FINDING (MEDIUM) -- Unchecked subtraction can underflow when `claimableWinnings[SDGNRS] < lootboxEth`**

### 1. Debit Side -- Lines 1808-1813

```solidity
// DegenerusGame.sol:1808-1813
uint256 claimable = claimableWinnings[ContractAddresses.SDGNRS];
unchecked {
    claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;
}
claimablePool -= amount;
```

#### 1a. Unchecked Subtraction (Open Question 2)

**Issue:** The unchecked subtraction on line 1811 assumes `claimable >= amount`. If `amount > claimable`, the result silently underflows to `type(uint256).max - (amount - claimable) + 1`, creating a massively inflated `claimableWinnings[SDGNRS]`.

**Source of `amount`:** In `claimRedemption()` (StakedDegenerusStonk.sol:583-624):
```
totalRolledEth = (ethValueOwed * roll) / 100
lootboxEth = totalRolledEth - ethDirect   // = totalRolledEth / 2 (+ 1 wei on odd amounts)
game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)
```

The `ethValueOwed` was computed at submission time as a proportion of `totalMoney`:
```solidity
// StakedDegenerusStonk.sol:721-725
uint256 claimableEth = _claimableWinnings();   // = claimableWinnings[SDGNRS] - 1 (sentinel)
uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
uint256 ethValueOwed = (totalMoney * amount) / supplyBefore;
```

**Critical observation:** `ethValueOwed` is proportional to `totalMoney`, which includes `ethBal`, `stethBal`, AND `claimableEth`. But the lootbox debit on Game.sol:1811 targets ONLY `claimableWinnings[SDGNRS]`. If sDGNRS's backing is predominantly in direct ETH/stETH (not claimable winnings on Game), then `lootboxEth` can exceed `claimableWinnings[SDGNRS]`.

**Underflow scenario:**

| Variable | Value |
|----------|-------|
| sDGNRS `address(this).balance` | 1000 ETH |
| sDGNRS `steth.balanceOf()` | 0 |
| `claimableWinnings[SDGNRS]` on Game | 11 ETH (10 + 1 sentinel) |
| `pendingRedemptionEthValue` | 0 |
| `totalMoney` | 1010 ETH |
| Player burns 10% of supply: `ethValueOwed` | 101 ETH |
| Roll = 175%: `totalRolledEth` | 176.75 ETH |
| `lootboxEth` (half) | 88.375 ETH |
| Game debit: `11 - 88.375 ETH` | **UNDERFLOW** |

After underflow: `claimableWinnings[SDGNRS]` = `2^256 - 77.375 ETH + 1` (massive value).

**Impact assessment:**
- **Accounting corruption:** Invariant `claimablePool >= sum(claimableWinnings[*])` is violated.
- **DoS on sDGNRS claims:** Future calls to `game.claimWinnings()` for sDGNRS will revert at `claimablePool -= payout` (line 1440), because `payout` (the underflowed amount minus 1) far exceeds `claimablePool`.
- **No direct theft:** The massively inflated `claimableWinnings[SDGNRS]` cannot be drained because `claimablePool -= payout` is checked and will revert.
- **Cascading effect:** The `claimablePool` was correctly reduced by `amount` on line 1813, so other players' claims are unaffected. But sDGNRS's claimable is permanently bricked.

**Why the checked `claimablePool` guard (line 1813) does NOT prevent this:**
`claimablePool = sum(all claimableWinnings[*])` (global invariant). If `claimablePool >= amount` (because OTHER players have large claimable balances), the checked subtraction succeeds. Meanwhile, `claimableWinnings[SDGNRS] < amount`, so the unchecked subtraction underflows. The guard only catches the case where the GLOBAL pool is insufficient, not the per-address case.

**When this can occur:**
1. sDGNRS's `claimableWinnings` on Game is small (common early in game before many jackpot distributions).
2. A player burns sDGNRS at a time when most of sDGNRS's backing is in direct ETH/stETH holdings (not claimable on Game).
3. The roll is high (up to 175%), amplifying `lootboxEth` beyond the claimable balance.
4. A prior player's `claimRedemption` drained sDGNRS's claimable via `_payEth` -> `game.claimWinnings(address(0))`, which sets `claimableWinnings[SDGNRS]` to 1 (sentinel).

**Prior claim drain path:**
```
Player A claimRedemption():
  -> resolveRedemptionLootbox: claimableWinnings[SDGNRS] -= lootboxEthA
  -> _payEth(player, ethDirect):
       if (ethDirect > address(this).balance && _claimableWinnings() != 0)
           game.claimWinnings(address(0))   // drains remaining claimable to 1
Player B claimRedemption():
  -> resolveRedemptionLootbox: claimableWinnings[SDGNRS] (now 1) -= lootboxEthB
  -> UNDERFLOW if lootboxEthB > 1
```

**Maximum `lootboxEth`:** 160 ETH cap * 175% roll / 100 / 2 = 140 ETH per claim.

**Severity: MEDIUM** -- Accounting corruption with DoS impact on sDGNRS's future Game claimables. Not directly exploitable for theft (checked `claimablePool` prevents drain), but permanently bricks sDGNRS's claimable accounting on Game. Requires specific but plausible conditions (sDGNRS's claimable < lootbox amount).

**Recommendation:** Add a checked subtraction or a pre-condition check:
```solidity
// Option A: Use checked subtraction (reverts if insufficient)
claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount;  // remove unchecked

// Option B: Credit before debit (ensure sufficient balance)
// sDGNRS sends ETH to Game before calling resolveRedemptionLootbox

// Option C: Conditional path -- only debit what's available, fund the rest from sDGNRS's ETH
if (amount > claimable) {
    // amount exceeds claimable -- reclassify what's available, sDGNRS covers the rest
    claimableWinnings[ContractAddresses.SDGNRS] = 0;
    claimablePool -= claimable;
    // Remaining (amount - claimable) must come from sDGNRS's ETH sent to Game
    uint256 shortfall = amount - claimable;
    // ... handle shortfall
} else {
    unchecked { claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount; }
    claimablePool -= amount;
}
```

#### 1b. Checked claimablePool Subtraction (Line 1813)

```solidity
claimablePool -= amount;
```

**Verdict: SAFE as an individual operation.** This is a checked subtraction (Solidity 0.8.34 overflow protection). If `amount > claimablePool`, the transaction reverts. However, as analyzed in 1a, `claimablePool` can be >= `amount` (from other players' contributions) while `claimableWinnings[SDGNRS] < amount`, so this check does not prevent the per-address underflow.

**Evidence:** `claimablePool` tracks the global sum of all `claimableWinnings[*]`. Confirmed by the invariant comment at DegenerusGameStorage.sol:391:
```
///      INVARIANT: claimablePool >= sum(claimableWinnings[*])
```

When other addresses have significant claimable balances, `claimablePool` exceeds `claimableWinnings[SDGNRS]` by a large margin, so the checked subtraction can succeed even when the per-address debit underflows.

#### 1c. No ETH Transfer (Lines 1808-1813)

**Verdict: SAFE.** Between lines 1808-1813, there are ZERO external calls. The operations are:
- `claimableWinnings[ContractAddresses.SDGNRS]` -- storage read (line 1809)
- `claimableWinnings[ContractAddresses.SDGNRS]` -- storage write (line 1811)
- `claimablePool` -- storage write (line 1813)

No `.call`, `.send`, `.transfer`, `payable` interaction, or any other external call. Pure storage manipulation confirmed.

### 2. Credit Side -- Lines 1815-1822

```solidity
// DegenerusGame.sol:1815-1822
if (prizePoolFrozen) {
    (uint128 pNext, uint128 pFuture) = _getPendingPools();
    _setPendingPools(pNext, pFuture + uint128(amount));
} else {
    (uint128 next, uint128 future) = _getPrizePools();
    _setPrizePools(next, future + uint128(amount));
}
```

#### 2a. uint128 Cast (Open Question 3)

**Verdict: SAFE.** `uint128.max = 3.4e38 wei = 3.4e20 ETH`.

Maximum `amount` per call: 160 ETH (daily cap) * 175% (max roll) / 100 / 2 = 140 ETH = 1.4e20 wei.

`1.4e20 << 3.4e38`. No truncation is possible.

Access control (verified below in REDM-07) ensures only sDGNRS can call this function, and sDGNRS enforces the 160 ETH daily cap (`MAX_DAILY_REDEMPTION_EV`). No other caller can pass a larger `amount`.

Additionally, `uint128(amount)` would only truncate if `amount >= 2^128 = 3.4e38`. Even if a malicious caller bypassed the access control (impossible per REDM-07), they'd need to pass ~340 quintillion ETH, which is physically impossible.

#### 2b. No ETH Transfer (Credit Side)

**Verdict: SAFE.** The `_setPrizePools` and `_setPendingPools` functions are pure storage writes:

```solidity
// DegenerusGameStorage.sol:675-693
function _setPrizePools(uint128 next, uint128 future) internal {
    prizePoolsPacked = uint256(future) << 128 | uint256(next);
}
function _setPendingPools(uint128 next, uint128 future) internal {
    prizePoolPendingPacked = uint256(future) << 128 | uint256(next);
}
```

These are single-slot storage writes with packed uint128 values. No external calls, no ETH movement. The `_getPrizePools` and `_getPendingPools` are view functions that read and unpack the same slots. Confirmed at DegenerusGameStorage.sol:675-693.

#### 2c. Freeze State Handling

**Verdict: SAFE.** The branch is correct:
- `prizePoolFrozen == true`: Credits `pFuture` (pending future pool) via `_setPendingPools`. This pool accumulates during freeze and is released when unfrozen.
- `prizePoolFrozen == false`: Credits `future` (live future pool) via `_setPrizePools`. This pool feeds into the next level's prize pool at level transition.

Both branches credit the future pool (second parameter), which is the correct destination for reclassified lootbox ETH. The ETH enters the future prize pool regardless of freeze state, which is correct behavior -- lootbox reclassification should contribute to future prizes.

### 3. Delegatecall to LootboxModule -- Lines 1824-1844

```solidity
// DegenerusGame.sol:1824-1844
uint256 remaining = amount;
while (remaining != 0) {
    uint256 box = remaining > 5 ether ? 5 ether : remaining;
    (bool ok, bytes memory data) = ContractAddresses
        .GAME_LOOTBOX_MODULE
        .delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameLootboxModule.resolveRedemptionLootbox.selector,
                player, box, rngWord, activityScore
            )
        );
    if (!ok) _revertDelegate(data);
    remaining -= box;
    rngWord = uint256(keccak256(abi.encode(rngWord)));
}
```

#### 3a. 5 ETH Chunking

**Verdict: SAFE.** `box = min(remaining, 5 ether)` by construction. Therefore `box <= remaining` always holds, and `remaining -= box` cannot underflow. The loop terminates because `remaining` strictly decreases each iteration (by at least 1 wei, since `remaining != 0` at loop entry means `box >= 1`).

**Loop bound:** Maximum iterations = ceil(140 ETH / 5 ETH) = 28 iterations. Gas cost is bounded.

#### 3b. Entropy Rotation

**Verdict: SAFE.** Each iteration rotates entropy via:
```solidity
rngWord = uint256(keccak256(abi.encode(rngWord)));
```

This is a deterministic hash chain. Each chunk receives different entropy derived from the previous. The keccak256 hash provides uniform distribution across the uint256 space. The initial entropy comes from:
```solidity
// StakedDegenerusStonk.sol:622-623
uint256 rngWord = game.rngWordForDay(claimPeriodIndex);
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player)));
```

Player-specific entropy seeded from the VRF-derived `rngWord`. Each chunk's entropy is distinct.

#### 3c. No ETH Transfer in LootboxModule

**Verdict: SAFE.** Full scan of `_resolveLootboxCommon` (DegenerusGameLootboxModule.sol:849-1025) confirms ZERO ETH transfer instructions. Specifically:

**Grep result for `.call{value`, `.transfer(`, `.send(`, `payable` in DegenerusGameLootboxModule.sol: NO MATCHES.**

The function performs:
- Storage reads/writes: `_queueTicketsScaled` (DegenerusGameStorage.sol:562) -- updates ticket queue storage
- Token operations via delegatecall context: `coin.creditFlip(player, burnieAmount)` (line 1010) -- credits BURNIE for coinflip
- Token operations: `wwxrp.mintPrize(player, wwxrpAmount)` (line 1624 in `_resolveLootboxRoll`) -- mints WWXRP tokens
- Token transfer: `dgnrs.transferFromPool(...)` (line 1745 in `_creditDgnrsReward`) -- transfers DGNRS from pool
- Delegatecall: `ContractAddresses.GAME_BOON_MODULE.delegatecall(...)` (lines 982, 1049) -- boon operations
- Event emissions: `LootBoxOpened`, `LootBoxDgnrsReward`, `LootBoxWwxrpReward`

None of these are raw ETH transfers. `coin.creditFlip` is a virtual BURNIE credit (no ETH). `wwxrp.mintPrize` mints ERC20 tokens. `dgnrs.transferFromPool` transfers ERC20 tokens.

Since the LootboxModule runs via delegatecall in Game's storage context (Game has no `receive()` or `fallback()` that sends ETH in this path), no ETH leaves Game's balance during lootbox resolution.

#### 3d. Scan of _resolveLootboxCommon for ETH Transfer

**Result: CLEAN.** Comprehensive scan of all code paths within `_resolveLootboxCommon` (lines 849-1025), `_resolveLootboxRoll` (lines 1566-1650), `_rollLootboxBoons` (lines 1037-1101), `_creditDgnrsReward` (lines 1743-1750), and `_queueTicketsScaled` (DegenerusGameStorage.sol:562-591):

No `.call{value:}`, no `.transfer()`, no `.send()`, no `selfdestruct`, no assembly ETH operations. All external interactions are token operations (ERC20 `transfer`, `creditFlip`, `mintPrize`) or nested delegatecalls to other modules (BoonModule).

### 4. Conservation Check

**Verdict: SAFE (with caveat from 1a).**

The `amount` variable is used in both operations:
- **Debit:** `claimableWinnings[SDGNRS] -= amount` and `claimablePool -= amount`
- **Credit:** `futurePrizePool += uint128(amount)` (via `_setPrizePools` or `_setPendingPools`)

Debit exactly equals credit. No ETH is created, destroyed, or transferred. The reclassification moves `amount` from one internal accounting bucket (claimable) to another (future prize pool).

**Caveat:** If the unchecked debit underflows (per finding 1a), the debit side credits `claimableWinnings[SDGNRS]` with a massive value instead of debiting. The credit side still adds `amount` to the future pool. Net effect: `amount` of ETH moved from `claimablePool` to `futurePrizePool` (correct), but `claimableWinnings[SDGNRS]` is inflated (accounting corruption).

---

## REDM-07: Cross-Contract Access Control

**Verdict: SAFE**

### Call Chain Diagram

```
                    EXTERNAL CALL                DELEGATECALL
 sDGNRS (msg.sender) ───────────> Game ─────────────────────> LootboxModule
                                  │                           │
                                  │ Gate: line 1805           │ No gate needed
                                  │ msg.sender == SDGNRS?     │ (runs in Game's
                                  │     YES → proceed         │  storage context)
                                  │     NO  → revert E()      │
                                  │                           │
                                  │ State changes:            │ State changes:
                                  │ - debit claimable         │ - queue tickets
                                  │ - credit futurePrize      │ - credit BURNIE
                                  │                           │ - mint WWXRP
                                  │                           │ - award boons
```

### Hop 1: sDGNRS -> Game (StakedDegenerusStonk.sol:624)

```solidity
// StakedDegenerusStonk.sol:624
game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore);
```

**Caller:** The StakedDegenerusStonk contract (`ContractAddresses.SDGNRS` = `0x92a6649Fdcc044DA968d94202465578a9371C7b1`).

**Callee:** DegenerusGame contract (`ContractAddresses.GAME` = `0x3381cD18e2Fb4dB236BF0525938AB6E43Db0440f`).

**Call type:** External call. `msg.sender` in Game will be the sDGNRS contract address.

### Hop 1 Gate: Game Checks Caller (DegenerusGame.sol:1805)

```solidity
// DegenerusGame.sol:1805
if (msg.sender != ContractAddresses.SDGNRS) revert E();
```

**Verification:**

1. **Correct address:** `ContractAddresses.SDGNRS` = `0x92a6649Fdcc044DA968d94202465578a9371C7b1` (confirmed in ContractAddresses.sol:28). This is the compile-time constant for the sDGNRS contract.

2. **First check in function:** The access control check on line 1805 is the FIRST executable statement in `resolveRedemptionLootbox` (line 1804: function entry). No state changes occur before this check. The only subsequent early return is `if (amount == 0) return;` on line 1806, which is a no-op guard.

3. **Impersonation risk:** ContractAddresses uses compile-time constants populated by the deploy script. The deploy pipeline predicts addresses via CREATE nonce prediction (see ContractAddresses.sol:4-5 comments). An attacker cannot deploy a contract at `0x92a6649F...` because:
   - The address is determined by the deployer's address and nonce at deploy time
   - On mainnet, the deployer's nonce is consumed during initial deployment
   - No CREATE2 is used for sDGNRS deployment (CREATE2 would require knowing the exact bytecode + salt)
   - The address is baked into the compiled bytecode via the library constant

4. **Deterministic address safety:** The ContractAddresses library (ContractAddresses.sol:1-38) contains hardcoded addresses as `internal constant`. These are immutable at compile time. The library is linked at deployment. No runtime modification is possible.

### Hop 2: Game -> LootboxModule (DegenerusGame.sol:1828-1840)

```solidity
// DegenerusGame.sol:1828-1840
(bool ok, bytes memory data) = ContractAddresses
    .GAME_LOOTBOX_MODULE
    .delegatecall(
        abi.encodeWithSelector(
            IDegenerusGameLootboxModule.resolveRedemptionLootbox.selector,
            player, box, rngWord, activityScore
        )
    );
```

**Call type:** DELEGATECALL. The LootboxModule code executes in Game's storage context.

**Context preservation under delegatecall:**
- `msg.sender` in LootboxModule = sDGNRS (original caller, preserved by delegatecall)
- `address(this)` in LootboxModule = Game's address
- Storage reads/writes in LootboxModule = Game's storage slots
- `msg.value` in LootboxModule = 0 (original call from sDGNRS is not payable)

**LootboxModule access control:** The `resolveRedemptionLootbox` function in DegenerusGameLootboxModule.sol (line 724) is `external` with NO access control modifier:

```solidity
// DegenerusGameLootboxModule.sol:724
function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external {
    if (amount == 0) return;
    // ... resolution logic, no msg.sender check
}
```

**Why no access control is needed in the LootboxModule:** Since it runs via delegatecall in Game's context, ALL access control is handled at the Game level (Hop 1 gate). The LootboxModule trusts that it's called correctly because:
1. The ONLY way to reach it with Game's storage is via delegatecall from Game
2. Game already verified `msg.sender == SDGNRS` before the delegatecall
3. The LootboxModule's storage context is Game's storage, so all ticket/BURNIE operations target Game's state

### Hop 2 Verification: ContractAddresses.GAME_LOOTBOX_MODULE

`ContractAddresses.GAME_LOOTBOX_MODULE` = `0x3D7Ebc40AF7092E3F1C81F2e996cbA5Cae2090d7` (ContractAddresses.sol:18). Same compile-time constant safety as SDGNRS.

### Attack Surface Analysis

#### 4a. Can an EOA call Game.resolveRedemptionLootbox directly?

**No.** An EOA's address would not equal `ContractAddresses.SDGNRS` (`0x92a6649F...`). The check on line 1805 reverts. EOAs have addresses derived from their public key and cannot be set to a specific value (birthday attack on keccak256 is computationally infeasible).

#### 4b. Can a malicious contract call Game.resolveRedemptionLootbox?

**No.** Same reason -- the malicious contract's address would not equal `ContractAddresses.SDGNRS`. The attacker would need to deploy a contract at the exact sDGNRS address, which is impossible (address occupied by the legitimate sDGNRS contract).

#### 4c. Can sDGNRS be tricked into calling resolveRedemptionLootbox with attacker-controlled parameters?

**No.** The call to `resolveRedemptionLootbox` (StakedDegenerusStonk.sol:624) occurs within `claimRedemption()`, which:
1. Reads `player = msg.sender` (line 572) -- attacker can only claim their own redemption
2. Reads `lootboxEth` from `totalRolledEth` computation (lines 583-594) -- derived from the player's own `PendingRedemption` storage
3. Reads `entropy` from `game.rngWordForDay(claimPeriodIndex)` (line 622) -- VRF-derived, not attacker-controlled
4. Reads `actScore` from the snapshotted `claim.activityScore` (line 621) -- set at submission, not modifiable

All parameters are derived from on-chain state that the attacker cannot manipulate. The `PendingRedemption` storage is set during `_submitGamblingClaimFrom` which enforces the 160 ETH daily cap.

#### 4d. Reentrancy in Lootbox Resolution

**SAFE.** The function follows checks-effects-interactions pattern:

1. **Checks:** Access control (line 1805), amount guard (line 1806)
2. **Effects:** State mutations BEFORE delegatecall loop:
   - Debit `claimableWinnings[SDGNRS]` (line 1811) -- state updated
   - Debit `claimablePool` (line 1813) -- state updated
   - Credit `futurePrizePool` (lines 1816-1822) -- state updated
3. **Interactions:** Delegatecall loop (lines 1826-1844) -- external code execution

Even if the delegatecall-ed code reenters `resolveRedemptionLootbox`, the access control check ensures only sDGNRS can call it. And sDGNRS doesn't call `resolveRedemptionLootbox` from within the lootbox resolution path (no reentrancy vector through sDGNRS).

The delegatecall to LootboxModule executes `_resolveLootboxCommon`, which makes external calls to:
- `coin.creditFlip(player, burnieAmount)` -- BurnieCoinflip contract (trusted)
- `wwxrp.mintPrize(player, wwxrpAmount)` -- WWXRP contract (trusted)
- `dgnrs.transferFromPool(...)` -- sDGNRS contract (trusted)
- `ContractAddresses.GAME_BOON_MODULE.delegatecall(...)` -- BoonModule (trusted)

All external call targets are protocol-owned contracts at deterministic addresses. None of them call back to `resolveRedemptionLootbox`.

### 5. LootboxModule Direct Call Risk

**Verdict: SAFE (no impact).**

The LootboxModule's `resolveRedemptionLootbox` function (line 724) is `external` with no access control. An EOA or contract COULD call it directly on the LootboxModule contract (not via delegatecall from Game).

**Impact analysis:** If called directly:
- The LootboxModule operates on ITS OWN storage, not Game's storage
- LootboxModule's storage is separate from Game's storage
- All ticket queue operations, claimable credits, and pool updates would target LootboxModule's own (mostly empty/zero) storage slots
- The function would likely revert at various points due to uninitialized storage (e.g., `level + 1` would be 1, `PriceLookupLib.priceForLevel(1)` might return 0 causing `revert E()`)
- Even if it doesn't revert, the effects are confined to LootboxModule's own storage, which is not read by any other contract

**Key point:** No protocol funds are at risk from direct calls to the LootboxModule because:
1. LootboxModule holds no ETH (ETH is in Game)
2. Token operations (`coin.creditFlip`, `dgnrs.transferFromPool`) would use the wrong `msg.sender` (LootboxModule address instead of Game), and the token contracts have their own access control
3. The storage modifications affect LootboxModule's own slots, not Game's

---

## New Findings Summary

| ID | Severity | Description | Lines |
|----|----------|-------------|-------|
| REDM-06-A | MEDIUM | Unchecked subtraction in `resolveRedemptionLootbox` can underflow when `claimableWinnings[SDGNRS] < lootboxEth`. The checked `claimablePool -= amount` does not guard against per-address underflow because `claimablePool` includes other addresses' balances. Impact: accounting corruption of `claimableWinnings[SDGNRS]` (inflated to near `uint256.max`), DoS on sDGNRS future claims from Game. Not directly exploitable for theft. | DegenerusGame.sol:1809-1813 |

## Cross-References

- **Phase 52 INV-03:** The unchecked subtraction finding (REDM-06-A) should inform invariant test design. An invariant `claimableWinnings[SDGNRS] <= claimablePool` should be fuzzed with multi-actor claim sequences where prior claims drain sDGNRS's claimable via `_payEth` -> `game.claimWinnings()`.
- **Phase 53 consolidated findings:** REDM-06-A should be included in the final consolidated findings with a recommendation to either use checked arithmetic or restructure the accounting to debit from a dedicated redemption pool rather than from `claimableWinnings[SDGNRS]`.
