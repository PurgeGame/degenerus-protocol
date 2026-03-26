# Unit Charity Plan 01: Token Operations Adversarial Audit

**Contract:** `contracts/DegenerusCharity.sol` (538 lines)
**Scope:** All 9 token-domain functions: constructor, _mint, totalSupply, balanceOf, transfer, transferFrom, approve, burn, receive
**Methodology:** v5.0 three-agent adversarial system (Mad Genius / Skeptic / Taskmaster)
**Date:** 2026-03-26

---

## MAD GENIUS ATTACK ANALYSIS

---

### 1. DegenerusCharity::constructor() (line 245-247)

#### Call Tree
```
constructor()
  -> _mint(address(this), INITIAL_SUPPLY)        [line 246, private]
       -> if (to == address(0)) revert ZeroAddress()  [line 531]
       -> totalSupply += amount                        [line 533, unchecked]
       -> balanceOf[to] += amount                      [line 534, unchecked]
       -> emit Transfer(address(0), to, amount)        [line 536]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `totalSupply` | `_mint` | 533 |
| `balanceOf[address(this)]` | `_mint` | 534 |

#### Attack Analysis

**A1. Constructor re-invocation:** Constructors execute once during deployment. After deployment, the constructor bytecode is not stored on-chain. Cannot be called again. **VERDICT: SAFE**

**A2. INITIAL_SUPPLY correctness:** `INITIAL_SUPPLY = 1_000_000_000_000 * 1e18` = 1e30. This is 1 trillion tokens with 18 decimals. uint256 max is ~1.15e77. No overflow risk in the unchecked block. **VERDICT: SAFE**

**A3. Mint-to-self:** Tokens are minted to `address(this)`, not to any EOA. This creates the "unallocated pool" that governance distributes from. The contract starts with 100% of supply. No external address has tokens at deploy. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
No locals cached. `_mint` writes directly to storage. No BAF risk.

**VERDICT: SAFE**

---

### 2. DegenerusCharity::_mint(address, uint256) (line 530-537)

#### Call Tree
```
_mint(to, amount)                                 [private]
  -> if (to == address(0)) revert ZeroAddress()   [line 531]
  -> totalSupply += amount                         [line 533, unchecked]
  -> balanceOf[to] += amount                       [line 534, unchecked]
  -> emit Transfer(address(0), to, amount)         [line 536]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `totalSupply` | `_mint` | 533 |
| `balanceOf[to]` | `_mint` | 534 |

#### Attack Analysis

**A1. Visibility:** `_mint` is declared `private` (line 530). It cannot be called from outside this contract, nor from derived contracts (there are none -- `DegenerusCharity` is not inherited). Verified: `_mint` is called exactly once, from the constructor (line 246). No other call site exists in the contract (grep confirmed: only two matches for `_mint` in entire file). **VERDICT: SAFE**

**A2. Unchecked overflow:** Both additions are in an `unchecked` block. Since `_mint` is only called once with `INITIAL_SUPPLY = 1e30` and both `totalSupply` and `balanceOf[address(this)]` start at 0, overflow is impossible (1e30 << 1.15e77 uint256 max). **VERDICT: SAFE**

**A3. Zero-address check:** Line 531 reverts if `to == address(0)`. Constructor passes `address(this)` which is always non-zero. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
No locals cached. Direct storage writes only. No BAF risk.

**VERDICT: SAFE**

---

### 3. DegenerusCharity::totalSupply (line 134)

#### Call Tree
```
totalSupply                                       [public state variable, auto-getter]
  -> returns storage slot value (no logic)
```

#### Storage Writes (Full Tree)
None -- view/read-only auto-getter.

#### Attack Analysis

**A1. Manipulation:** `totalSupply` is a public `uint256` state variable. The auto-generated getter is a pure storage read with no side effects. It decreases on `burn()` and `handleGameOver()`, never increases after constructor. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
N/A -- view function, no cache possible.

**VERDICT: SAFE**

---

### 4. DegenerusCharity::balanceOf(address) (line 137)

#### Call Tree
```
balanceOf[account]                                [public mapping, auto-getter]
  -> returns mapping value for given address (no logic)
```

#### Storage Writes (Full Tree)
None -- view/read-only auto-getter.

#### Attack Analysis

**A1. Manipulation:** Public mapping auto-getter. Returns the GNRUS balance for any address. Modified by `_mint`, `burn`, `resolveLevel`, and `handleGameOver`. No external attack surface on the getter itself. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
N/A -- view function, no cache possible.

**VERDICT: SAFE**

---

### 5. DegenerusCharity::transfer(address, uint256) (line 254)

#### Call Tree
```
transfer(address, uint256)                        [external pure]
  -> revert TransferDisabled()                    [line 254, unconditional]
```

#### Storage Writes (Full Tree)
None -- function always reverts before any storage access.

#### Attack Analysis

**A1. Soulbound bypass:** The function is declared `pure` (line 254: `function transfer(address, uint256) external pure returns (bool)`). The `pure` modifier means the function cannot read or write storage, cannot read `msg.sender`, `msg.value`, or any blockchain state. The `revert TransferDisabled()` is the first and only instruction. There is no conditional logic, no assembly, no way to skip the revert. This is an unconditional, permanent block on transfers. **VERDICT: SAFE**

**A2. ERC20 compatibility concern:** Some protocols may attempt `transfer` on GNRUS and silently fail or revert. This is by design (soulbound). The revert with a named error (`TransferDisabled()`) provides clear feedback. **VERDICT: SAFE (INFO -- design intent)**

#### Cached-Local-vs-Storage Check
N/A -- pure function, no storage access possible.

**VERDICT: SAFE**

---

### 6. DegenerusCharity::transferFrom(address, address, uint256) (line 257)

#### Call Tree
```
transferFrom(address, address, uint256)           [external pure]
  -> revert TransferDisabled()                    [line 257, unconditional]
```

#### Storage Writes (Full Tree)
None -- function always reverts.

#### Attack Analysis

**A1. Soulbound bypass:** Identical analysis to `transfer`. Declared `pure` (line 257: `function transferFrom(address, address, uint256) external pure returns (bool)`). Unconditional `revert TransferDisabled()`. No conditional paths, no assembly, no storage access possible due to `pure`. **VERDICT: SAFE**

**A2. Allowance-based attack:** No `allowance` mapping exists anywhere in the contract (grep-verified: zero matches for "allowance" in the entire file). Even if `transferFrom` did not revert, there would be no allowance mechanism to exploit. Double defense. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
N/A -- pure function, no storage access possible.

**VERDICT: SAFE**

---

### 7. DegenerusCharity::approve(address, uint256) (line 260)

#### Call Tree
```
approve(address, uint256)                         [external pure]
  -> revert TransferDisabled()                    [line 260, unconditional]
```

#### Storage Writes (Full Tree)
None -- function always reverts.

#### Attack Analysis

**A1. Soulbound bypass:** Declared `pure` (line 260: `function approve(address, uint256) external pure returns (bool)`). Unconditional revert. No allowance state can be set. **VERDICT: SAFE**

**A2. No allowance mapping:** As verified above, no `allowance` mapping exists. Even if `approve` were somehow callable, there is no storage to write to. The contract has no ERC20 approval mechanism at all. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
N/A -- pure function, no storage access possible.

**VERDICT: SAFE**

---

### 8. DegenerusCharity::burn(uint256) (line 273-320) -- PRIMARY ATTACK SURFACE

#### Call Tree
```
burn(amount)                                                      [external, line 273]
  -> if (amount < MIN_BURN) revert InsufficientBurn()             [line 274]
  -> supply = totalSupply                                          [line 276, cache SLOAD]
  -> burner = msg.sender                                           [line 277]
  -> burnerBal = balanceOf[burner]                                 [line 278, cache SLOAD]
  -> LAST-HOLDER SWEEP: conditional amount override                [line 282-284]
  -> ethBal = address(this).balance                                [line 287]
  -> steth.balanceOf(address(this))                                [line 288, external call to Lido stETH]
  -> game.claimableWinningsOf(address(this))                       [line 289, external call to DegenerusGame]
  -> claimable adjustment (-1 for stETH rounding)                  [line 290]
  -> owed = ((ethBal + stethBal + claimable) * amount) / supply    [line 292]
  -> onHand = ethBal + stethBal                                    [line 295]
  -> if (owed > onHand):                                           [line 296]
       -> game.claimWinnings(address(this))                        [line 297, external call]
       -> ethBal = address(this).balance                           [line 298, re-read]
       -> stethBal = steth.balanceOf(address(this))                [line 299, re-read]
  -> ethOut = owed <= ethBal ? owed : ethBal                       [line 302]
  -> stethOut = owed - ethOut                                      [line 303]
  -> balanceOf[burner] -= amount                                   [line 306, Solidity 0.8 underflow check]
  -> unchecked { totalSupply = supply - amount }                   [line 307]
  -> emit Transfer(burner, address(0), amount)                     [line 309]
  -> emit Burn(burner, amount, ethOut, stethOut)                   [line 310]
  -> if (stethOut != 0):
       -> steth.transfer(burner, stethOut)                         [line 314, external call to Lido]
  -> if (ethOut != 0):
       -> burner.call{value: ethOut}("")                           [line 317, raw ETH transfer]
```

#### Storage Writes (Full Tree)
| Variable | Written By | Line |
|----------|-----------|------|
| `balanceOf[burner]` | `burn` | 306 |
| `totalSupply` | `burn` | 307 (via cached `supply`) |

Note: `game.claimWinnings(address(this))` at line 297 is an external call to DegenerusGame. It writes to DegenerusGame storage (`claimableEth[address(this)]` reset to 0) and sends ETH to this contract, but does NOT write to any DegenerusCharity storage variables. No BAF risk from this call.

#### Attack Analysis

**A1. Reentrancy via raw ETH transfer (line 317-318):**
The `burner.call{value: ethOut}("")` at line 317 is a raw call that transfers control to `burner`. If `burner` is a contract, it can reenter `burn()`.

**Reentrancy trace:** If burner reenters `burn()`:
- `totalSupply` was already decremented on line 307 (written from cached `supply - amount`)
- `balanceOf[burner]` was already decremented on line 306

The state updates (lines 306-307) happen BEFORE the external calls (lines 313-318). This follows the Checks-Effects-Interactions (CEI) pattern correctly. A reentrant call to `burn()` would see the updated (reduced) `totalSupply` and `balanceOf[burner]`, so the proportional calculation would be based on the reduced values. The reentrant call cannot extract more than its proportional share of the remaining pool.

However, there is a subtlety: the `steth.transfer` on line 314 happens BEFORE the ETH transfer on line 317. If a reentrant attacker calls `burn()` during the ETH callback, they see reduced token balances but the stETH balance has already been reduced by the first burn's stethOut. This is correct because `stethBal` is read fresh from `steth.balanceOf(address(this))` on each burn call, and totalSupply has been decremented. The proportional math holds.

**VERDICT: SAFE** -- CEI pattern holds. State updates before all external calls. Reentrant burn() sees correct reduced state.

**A2. Reentrancy via game.claimWinnings (line 297):**
`game.claimWinnings(address(this))` is called BEFORE state updates (lines 306-307). If `game.claimWinnings` triggers a callback to DegenerusCharity (e.g., via ETH transfer to this contract through `receive()`), what state does the callback see?

The `receive()` function at line 506 is just `receive() external payable {}` -- it does nothing, just accepts ETH. There is no reentrancy vector through `receive()`.

Could `game.claimWinnings` call back into `burn()` or any other state-changing function? The game contract's `claimWinnings` sends ETH to `address(this)` (DegenerusCharity), which hits `receive()`. No callback to any state-changing function occurs.

**VERDICT: SAFE** -- game.claimWinnings sends ETH to this contract's receive(), which is a no-op. No reentrancy path.

**A3. Reentrancy via stETH.transfer (line 314):**
Lido's stETH is a standard rebasing ERC20. It does NOT implement ERC-777 hooks (no `tokensReceived` callback). The `steth.transfer` call to the burner does not trigger any callback to DegenerusCharity.

**VERDICT: SAFE** -- stETH has no transfer hooks. No reentrancy vector.

**A4. Last-holder sweep logic (line 282-284):**
```solidity
if (burnerBal == amount || (supply - balanceOf[address(this)]) == amount) {
    amount = burnerBal; // sweep
}
```

Two sweep conditions:
1. `burnerBal == amount` -- User is burning their entire balance. `amount` gets set to `burnerBal` (same value). No change.
2. `(supply - balanceOf[address(this)]) == amount` -- User is burning ALL non-contract GNRUS (i.e., all circulating GNRUS). `amount` gets replaced with `burnerBal`, which could be LARGER than the original `amount`.

**Attack scenario for condition 2:** Suppose Alice has 100 GNRUS, Bob has 50 GNRUS, and the contract has 850 GNRUS. Total supply = 1000. Circulating = 1000 - 850 = 150. If Alice calls `burn(150)`, the second condition triggers because `(1000 - 850) == 150`. Then `amount = burnerBal = 100`. Wait -- `amount` DECREASES from 150 to 100. Alice had `burnerBal = 100` but requested to burn 150, which would have failed on line 306 (`balanceOf[burner] -= amount` underflow for 100 - 150). The sweep actually HELPS Alice by reducing `amount` to her actual balance, preventing a revert.

But what if Alice is the ONLY non-contract holder? Alice has 150 GNRUS, contract has 850. `supply - balanceOf[address(this)] = 150 == amount`. `amount = burnerBal = 150`. Same value. No exploit.

What if Alice has MORE than circulating? Impossible -- Alice's balance is part of circulating supply.

**Can condition 2 be gamed?** An attacker would need `(supply - balanceOf[address(this)]) == amount` where `amount` is carefully chosen. But the sweep replaces `amount` with `burnerBal`. The attacker can never get MORE than their proportional share because the proportional calculation `(backing * amount) / supply` scales linearly with `amount`, and `amount` becomes their actual balance. They get `(backing * burnerBal) / supply` which is exactly their proportional share.

**VERDICT: SAFE** -- Last-holder sweep prevents dust, cannot be exploited for disproportionate payouts.

**A5. Claimable winnings accounting and -1 adjustment (line 289-290):**
```solidity
uint256 claimable = game.claimableWinningsOf(address(this));
if (claimable > 1) { unchecked { claimable -= 1; } } else { claimable = 0; }
```

The `-1` is a protection against stETH's known 1-2 wei rounding behavior. When stETH is transferred, the actual amount received can differ by 1 wei from the requested amount due to share-based accounting. By subtracting 1 from claimable, the contract avoids promising more than it can deliver.

If `claimable <= 1`, it is set to 0 (treating dust as nothing). This is conservative and correct.

**VERDICT: SAFE** -- Conservative rounding protection. Burner gets slightly less than theoretical maximum, not more.

**A6. Division precision and zero-supply (line 292):**
```solidity
uint256 owed = ((ethBal + stethBal + claimable) * amount) / supply;
```

**Division by zero:** Can `supply` be 0? For `burn()` to be called, someone must have GNRUS tokens (`balanceOf[burner] >= amount >= MIN_BURN = 1e18`). If any address has tokens, `totalSupply > 0`. So `supply` cannot be 0 when `burn()` is called. **SAFE.**

**Overflow of numerator:** `(ethBal + stethBal + claimable)` is the total backing in wei. Even at 1 billion ETH backing (1e27 wei) and burning 1T tokens (1e30), the product is 1e57, well under uint256 max (1.15e77). **SAFE.**

**Rounding:** Integer division truncates. Burner receives slightly less than proportional. Dust accumulates in the contract. Last-holder sweep (A4) handles this for the final burner. **SAFE.**

**VERDICT: SAFE** -- No zero-division, no overflow, rounding is conservative (truncation favors the contract).

**A7. BAF-class cache-overwrite check:**
`burn()` caches two storage values into locals:
- `supply = totalSupply` (line 276)
- `burnerBal = balanceOf[burner]` (line 278)

Then it writes them back:
- `balanceOf[burner] -= amount` (line 306) -- writes directly to storage, NOT using `burnerBal` cache. Safe.
- `totalSupply = supply - amount` (line 307) -- writes using `supply` cache.

**Can any called function modify `totalSupply` between the read (line 276) and the write (line 307)?**

Called functions between lines 276 and 307:
1. `steth.balanceOf(address(this))` (line 288) -- external call to Lido, reads stETH state. Cannot modify DegenerusCharity storage.
2. `game.claimableWinningsOf(address(this))` (line 289) -- external view call to Game. Cannot modify DegenerusCharity storage.
3. `game.claimWinnings(address(this))` (line 297, conditional) -- external call to Game. Sends ETH to `this.receive()`. `receive()` is a no-op. Cannot modify DegenerusCharity's `totalSupply`.

**No function in the call tree writes to `totalSupply` or `balanceOf[burner]` between the cache reads and the storage writes.**

Additionally: `balanceOf[burner] -= amount` on line 306 is a DIRECT storage write (not using the cached `burnerBal`). The cached `burnerBal` is only used for the sweep logic (line 282-284) and is not written back. This is a clean pattern.

**VERDICT: SAFE** -- No BAF-class cache-overwrite risk. External calls cannot modify DegenerusCharity storage. The `supply` cache is used to write `totalSupply` but no intervening call can modify `totalSupply`.

**A8. ethOut / stethOut calculation (lines 295-303):**
```solidity
uint256 onHand = ethBal + stethBal;
if (owed > onHand) {
    game.claimWinnings(address(this));
    ethBal = address(this).balance;
    stethBal = steth.balanceOf(address(this));
}
uint256 ethOut = owed <= ethBal ? owed : ethBal;
uint256 stethOut = owed - ethOut;
```

**Can `stethOut` exceed `steth.balanceOf(address(this))`?** After `claimWinnings` is called (which may send ETH and/or claim stETH), `ethBal` and `stethBal` are re-read. `owed` was calculated from the total backing (ETH + stETH + claimable). After claimWinnings, the ETH balance increases by `claimable` (approximately). So `ethBal + stethBal >= owed` should hold.

But what if `game.claimWinnings` pays in ETH only? Then `ethBal` increases while `stethBal` stays the same. `ethOut = min(owed, ethBal)`. If `ethBal >= owed` after claim, then `ethOut = owed` and `stethOut = 0`. If `ethBal < owed`, then `stethOut = owed - ethBal`. Since `owed` was computed from `ethBal_old + stethBal + claimable` and now `ethBal_new = ethBal_old + claimable_actual`, we have `ethBal_new + stethBal >= owed` (minus 1 wei from the claimable adjustment). The stethOut would not exceed stethBal.

Edge case: claimable was reduced by 1 (line 290), so `owed` is slightly less than the true total backing. This makes `stethOut` even smaller. Conservative.

**What if claimWinnings is NOT called?** (owed <= onHand): Then `ethOut = min(owed, ethBal)` and `stethOut = owed - ethOut`. If `owed > ethBal`, then `stethOut = owed - ethBal`. Since `owed <= ethBal + stethBal`, `stethOut <= stethBal`. Safe.

**VERDICT: SAFE** -- ETH-preferred payout with stETH as fallback. Cannot exceed available balances.

**A9. Unchecked totalSupply decrement (line 307):**
```solidity
unchecked { totalSupply = supply - amount; }
```

Is `supply >= amount` guaranteed? Yes:
- `supply = totalSupply` (line 276)
- `balanceOf[burner] -= amount` on line 306 succeeds (Solidity 0.8 underflow check)
- `balanceOf[burner] <= totalSupply` is a protocol invariant (maintained by _mint, burn, resolveLevel, handleGameOver -- proven below in Supply Invariant section)
- Therefore `totalSupply >= balanceOf[burner] >= amount`

**VERDICT: SAFE** -- Unchecked is safe because the checked `balanceOf` decrement on line 306 implicitly proves `supply >= amount`.

**A10. Front-running / MEV on burn:**
An attacker could front-run a burn transaction by burning their own GNRUS first, reducing the ETH/stETH pool. But this is proportional -- the front-runner gets their proportional share, and the victim gets their proportional share of the remainder. No profitable MEV exists because burn is strictly proportional.

An attacker could also deposit ETH to the contract (via `receive()`) before someone else's burn to inflate the apparent backing and then burn after. But this would give other burners a larger proportional payout at the attacker's expense. Net negative for attacker.

**VERDICT: SAFE** -- Proportional burn is MEV-resistant by design.

#### Cached-Local-vs-Storage Check

| Ancestor Local | Cached At | Descendant Write | Written At | Verdict |
|---------------|-----------|-----------------|-----------|---------|
| `supply = totalSupply` | line 276 | None in call tree | N/A | SAFE -- no descendant writes `totalSupply` |
| `burnerBal = balanceOf[burner]` | line 278 | None in call tree | N/A | SAFE -- not written back (line 306 writes directly to storage) |
| `ethBal = address(this).balance` | line 287 | `game.claimWinnings` sends ETH | line 297 | SAFE -- `ethBal` is RE-READ at line 298 after the claimWinnings call |
| `stethBal = steth.balanceOf(...)` | line 288 | `game.claimWinnings` may move stETH | line 297 | SAFE -- `stethBal` is RE-READ at line 299 after the claimWinnings call |

**VERDICT: SAFE**

---

### 9. DegenerusCharity::receive() (line 506)

#### Call Tree
```
receive()                                         [external payable]
  -> (empty body)                                  [line 506]
```

#### Storage Writes (Full Tree)
None -- empty function body. Only accepts ETH.

#### Attack Analysis

**A1. ETH flooding:** Anyone can send ETH to this contract. This increases the proportional redemption value for GNRUS holders. An attacker sending ETH to the contract is donating to all holders. Net positive for the protocol. **VERDICT: SAFE**

**A2. Griefing via forced ETH:** Even with self-destruct (deprecated post-Cancun but still possible on some chains), forced ETH just increases redemption value. No state corruption possible since `receive()` writes nothing. **VERDICT: SAFE**

#### Cached-Local-vs-Storage Check
N/A -- no storage access, no logic.

**VERDICT: SAFE**

---

## INVARIANT PROOFS

---

### Soulbound Invariant: No code path transfers GNRUS between external addresses

**Proof by exhaustive enumeration of all `balanceOf` mutations:**

1. **`_mint(to, amount)`** (line 530-537): Increases `balanceOf[to]` and `totalSupply`. Called once in constructor with `to = address(this)`. Private -- no external caller. Only creates tokens for the contract itself.

2. **`burn(amount)`** (line 273-320): Decreases `balanceOf[msg.sender]` (line 306) and `totalSupply` (line 307). Burns from the caller only -- never moves tokens to another address. Emits `Transfer(burner, address(0), amount)`.

3. **`resolveLevel(uint24)`** (line 443-498): Decreases `balanceOf[address(this)]` and increases `balanceOf[recipient]` (lines 494-495). This moves tokens FROM the contract's unallocated pool TO a governance-selected recipient. This is a transfer from `address(this)` to `recipient`, not between two external addresses.

4. **`handleGameOver()`** (line 331-343): Decreases `balanceOf[address(this)]` and `totalSupply` (lines 337-338). Burns unallocated tokens. Never moves tokens to another address.

5. **`transfer`**, **`transferFrom`**, **`approve`**: All declared `pure`, all revert unconditionally with `TransferDisabled()`.

**Conclusion:** The only path that moves GNRUS to an external address is `resolveLevel`, which moves from `address(this)` (the unallocated pool) to a recipient. No code path transfers GNRUS from one external address to another. GNRUS is soulbound. **QED.**

---

### Supply Invariant: totalSupply == sum(balanceOf[all addresses]) at all times

**Proof by checking every mutation pair:**

1. **`_mint(to, amount)`**: `totalSupply += amount` (line 533) and `balanceOf[to] += amount` (line 534). Both incremented by `amount`. Sum preserved.

2. **`burn(amount)`**: `balanceOf[burner] -= amount` (line 306) and `totalSupply = supply - amount` (line 307). `supply` was read from `totalSupply` (line 276). No intervening writes to `totalSupply` (proven in BAF check A7). Both decremented by `amount`. Sum preserved.

3. **`resolveLevel`**: `balanceOf[address(this)] = unallocated - distribution` (line 494) and `balanceOf[recipient] += distribution` (line 495). Both in an `unchecked` block. `totalSupply` is NOT modified. The sum of all `balanceOf` entries is unchanged because `distribution` is subtracted from one address and added to another. Sum preserved.

   **Unchecked safety:** `unallocated >= distribution` because `distribution = (unallocated * 200) / 10000 = unallocated * 0.02`, which is always <= unallocated. `balanceOf[recipient] += distribution` cannot overflow because `distribution <= unallocated <= totalSupply <= INITIAL_SUPPLY = 1e30 << uint256 max`. Safe.

4. **`handleGameOver()`**: `balanceOf[address(this)] = 0` (line 337) and `totalSupply -= unallocated` (line 338, unchecked). `unallocated = balanceOf[address(this)]` read at line 335. Both decremented by the same value. Sum preserved.

   **Unchecked safety:** `totalSupply >= balanceOf[address(this)]` by the invariant itself. Safe.

**Conclusion:** Every state-changing path that modifies `balanceOf` also modifies `totalSupply` by the same net amount (or vice versa for redistributions like `resolveLevel`). The invariant holds at construction (both start at 0, then both increase by INITIAL_SUPPLY) and is preserved by every subsequent mutation. **QED.**

---

### Proportional Redemption Correctness

**Claim:** `burn(amount)` pays the burner `amount / totalSupply` of the total backing.

**Proof:**

1. **Total backing computation** (line 287-292):
   ```solidity
   totalBacking = ethBal + stethBal + claimable
   owed = (totalBacking * amount) / supply
   ```
   This is `(totalBacking * amount) / totalSupply`, which equals `amount/totalSupply * totalBacking`. Correct proportional share.

2. **Rounding:** Integer division truncates. Burner receives `floor(totalBacking * amount / supply)`. This means the burner gets slightly LESS than their exact proportional share. The "lost" wei accumulates in the contract. Conservative.

3. **Last-holder sweep (line 282-284):** When the last external holder burns, `amount` is set to `burnerBal` (their entire balance). After this burn, `totalSupply` may still be > 0 if `balanceOf[address(this)] > 0` (unallocated GNRUS exists). The last external holder gets `burnerBal/totalSupply` of backing, NOT 100%. The unallocated GNRUS's share of backing remains in the contract.

   If unallocated = 0 (i.e., `handleGameOver()` burned all unallocated tokens), then `totalSupply = burnerBal` and `owed = totalBacking * burnerBal / burnerBal = totalBacking`. The last holder gets everything. Dust from rounding in previous burns is included.

4. **Edge case -- multiple holders, partial burns:** Each burn reduces both `totalSupply` and backing by proportional amounts. Subsequent burns compute proportional share of REMAINING backing with REMAINING supply. This is mathematically equivalent to each holder receiving their fair share regardless of burn order.

5. **Edge case -- zero backing:** If `ethBal + stethBal + claimable = 0`, then `owed = 0`, `ethOut = 0`, `stethOut = 0`. The burn succeeds (tokens are destroyed) but nothing is paid out. The burner loses their tokens for nothing. This is correct behavior -- if the contract has no backing, there is nothing to redeem.

**VERDICT: Proportional redemption is correct.** Rounding truncation is conservative. Last-holder sweep prevents permanent dust stranding when unallocated pool is empty. **QED.**

---

### Edge Cases Summary (per D-06)

| Edge Case | Behavior | Verdict |
|-----------|----------|---------|
| Last burner, unallocated = 0 | Gets 100% of remaining backing | SAFE |
| Last burner, unallocated > 0 | Gets proportional share only (unallocated's share stays) | SAFE |
| Zero supply after all burns | Unreachable -- requires all holders to burn, then no one can call burn | SAFE |
| Zero backing | Burn succeeds, 0 ETH/stETH paid | SAFE (correct behavior) |
| MIN_BURN enforcement | amount < 1e18 reverts | SAFE |
| Rounding dust | Truncation favors contract; last-holder sweep collects accumulated dust | SAFE |

---

## SKEPTIC VALIDATION

All 9 functions received **SAFE** verdicts from the Mad Genius. Per the Skeptic protocol, SAFE findings do not require explicit CONFIRMED/REFUTED validation. However, the Skeptic performs an independent review of the highest-risk function (`burn`) and the invariant proofs.

### Skeptic Independent Review of burn()

**Skeptic reads burn() lines 273-320 independently:**

1. **CEI pattern:** Lines 306-307 (state updates) precede lines 313-318 (external calls). CONFIRMED correct order.

2. **game.claimWinnings called before state updates (line 297):** This violates CEI ordering IF the called function could reenter DegenerusCharity in a harmful way. Skeptic traces: `game.claimWinnings(address(this))` sends ETH to `address(this)`, hitting `receive()` which is a no-op. No reentrancy vector exists. The only state that matters (`totalSupply`, `balanceOf`) has not yet been modified when `claimWinnings` is called, so even if reentrancy occurred, the reentrant `burn()` would read the SAME `totalSupply` and `balanceOf`, which is actually a WORSE outcome for the attacker (they'd be computing proportional share against the full supply, getting the correct or smaller amount). **CONFIRMED SAFE -- no profitable reentrancy.**

3. **stETH 1-wei rounding:** The `-1` on claimable (line 290) is a known pattern for stETH share-based accounting. The game contract likely uses stETH shares internally. The 1-wei buffer prevents over-promising. **CONFIRMED correct mitigation.**

4. **Last-holder sweep never inflates payout:** Skeptic verifies line 282: `(supply - balanceOf[address(this)]) == amount` can only trigger when `amount` equals total circulating supply. The sweep sets `amount = burnerBal` which is <= circulating supply. The proportional calculation `totalBacking * burnerBal / supply` is always <= `totalBacking`. **CONFIRMED SAFE.**

5. **Unchecked totalSupply decrement:** Skeptic verifies the chain: `balanceOf[burner] -= amount` on line 306 is checked (Solidity 0.8). If it succeeds, then `balanceOf[burner] >= amount`. Since `totalSupply >= sum(balanceOf) >= balanceOf[burner] >= amount`, the unchecked decrement on line 307 is safe. **CONFIRMED SAFE.**

### Skeptic Review of Invariant Proofs

1. **Soulbound invariant:** Skeptic verified all 5 balanceOf mutation sites. The enumeration is complete. No path moves GNRUS from one external address to another. **CONFIRMED.**

2. **Supply invariant:** Skeptic checked all 4 mutation cases. The resolveLevel unchecked block is safe because `distribution = unallocated * 2%` which is always < unallocated. **CONFIRMED.**

3. **Proportional redemption:** Skeptic verified the math. The formula `(totalBacking * amount) / supply` is standard proportional redemption. Truncation is conservative. Last-holder sweep is a UX improvement, not a security concern. **CONFIRMED.**

### Skeptic Final Verdict

No VULNERABLE or INVESTIGATE findings to validate. All Mad Genius analysis is thorough and technically correct. The burn() function analysis correctly identifies CEI compliance, BAF-class safety, and all edge cases. The invariant proofs are sound.

**Skeptic Verdict: ALL FINDINGS CONFIRMED SAFE. Zero issues requiring escalation.**

---

## TASKMASTER COVERAGE REPORT

### Function Checklist

| # | Function | Lines | Analyzed? | Call Tree Complete? | Storage Writes Complete? | Cache Check Done? | Verdict |
|---|----------|-------|-----------|--------------------|-----------------------|------------------|---------|
| 1 | `constructor()` | 245-247 | YES | YES | YES (2 writes) | YES | SAFE |
| 2 | `_mint(address, uint256)` | 530-537 | YES | YES | YES (2 writes) | YES | SAFE |
| 3 | `totalSupply` (auto-getter) | 134 | YES | YES (trivial) | YES (0 writes) | N/A (view) | SAFE |
| 4 | `balanceOf(address)` (auto-getter) | 137 | YES | YES (trivial) | YES (0 writes) | N/A (view) | SAFE |
| 5 | `transfer(address, uint256)` | 254 | YES | YES | YES (0 writes) | N/A (pure) | SAFE |
| 6 | `transferFrom(address, address, uint256)` | 257 | YES | YES | YES (0 writes) | N/A (pure) | SAFE |
| 7 | `approve(address, uint256)` | 260 | YES | YES | YES (0 writes) | N/A (pure) | SAFE |
| 8 | `burn(uint256)` | 273-320 | YES | YES (full expansion) | YES (2 writes) | YES (4 pairs) | SAFE |
| 9 | `receive()` | 506 | YES | YES (trivial) | YES (0 writes) | N/A (no storage) | SAFE |

### Coverage: 9/9 functions analyzed (100%)

### Gaps Found
None. All 9 token-domain functions have complete analysis with:
- Full recursive call trees with line numbers
- Complete storage write maps
- BAF-class cached-local-vs-storage checks (where applicable)
- Explicit VERDICT per function

### Interrogation Log

**Q1:** "burn() caches `supply` and `burnerBal` but only `supply` is written back (line 307). `burnerBal` is used for sweep logic but line 306 writes directly to storage via `balanceOf[burner] -= amount`. Did you verify that `burnerBal` is never written back stale?"
**A1:** Yes. Line 306 is `balanceOf[burner] -= amount` which is a direct storage decrement (not `balanceOf[burner] = burnerBal - amount`). The cached `burnerBal` is only read for the sweep condition (line 282-284). No stale writeback.

**Q2:** "You said `game.claimWinnings` can't modify DegenerusCharity storage. But what if Game uses delegatecall to a module that has a cross-reference?"
**A2:** DegenerusCharity is called via regular CALL, not delegatecall. The Game contract's delegatecall modules execute in Game's storage context, not Charity's. Even if a Game module called back into Charity, it would execute in Charity's own storage context. No cross-context storage corruption is possible.

**Q3:** "The unchecked block in resolveLevel (lines 493-496) -- did you verify both the subtraction AND the addition are safe?"
**A3:** Yes. `unallocated - distribution` is safe because `distribution = (unallocated * 200) / 10000` which is always <= unallocated (2% < 100%). `balanceOf[recipient] += distribution` is safe because `distribution <= unallocated <= INITIAL_SUPPLY = 1e30 << uint256 max`.

### Taskmaster Verdict: **PASS**

All 9 token-domain functions have been analyzed with full depth. Call trees are complete, storage writes are mapped, and cached-local-vs-storage checks are present where applicable. No coverage gaps remain.

---

## SUMMARY

| Function | Verdict | Key Finding |
|----------|---------|-------------|
| `constructor()` | SAFE | Correct 1T mint to self |
| `_mint(address, uint256)` | SAFE | Private, called once, no overflow |
| `totalSupply` | SAFE | View-only auto-getter |
| `balanceOf(address)` | SAFE | View-only auto-getter |
| `transfer(address, uint256)` | SAFE | Pure unconditional revert (soulbound) |
| `transferFrom(address, address, uint256)` | SAFE | Pure unconditional revert (soulbound) |
| `approve(address, uint256)` | SAFE | Pure unconditional revert, no allowance mapping |
| `burn(uint256)` | SAFE | CEI compliant, no BAF risk, proportional math correct |
| `receive()` | SAFE | Empty body, accepts ETH only |

**Findings:** 0 VULNERABLE, 0 INVESTIGATE, 9 SAFE
**Invariants Proven:** Soulbound, Supply Conservation, Proportional Redemption Correctness
**BAF-class check on burn():** SAFE -- no cache-overwrite risk
