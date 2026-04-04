# Money Correctness Warden Report

**Warden:** Fresh-eyes specialist (zero prior context)
**Scope:** All ETH flows, token accounting, BPS rounding, cross-token interactions
**Date:** 2026-03-28
**Methodology:** Adversarial trace of every payable function entry, every `.call{value:}` exit, every mint/burn path, every BPS calculation chain

---

## Executive Summary

After systematically tracing every ETH entry point, exit point, token mint/burn path, BPS rounding chain, and cross-token interaction across 24 contracts (~15,000 lines Solidity), **zero HIGH or MEDIUM severity money correctness findings** were identified.

The protocol's money correctness posture is strong:
- Every ETH inflow has a matching accounting destination (prize pool, claimable, vault)
- Every ETH outflow is gated by prior state decrement (CEI pattern enforced)
- All BPS rounding directions favor protocol solvency (floor division on payouts)
- Token supply invariants are maintained across all mint/burn paths
- Cross-token interactions preserve value conservation

---

## Methodology

### Flow Tracing Approach

1. **Entry-to-exit tracing:** For each `payable` function, traced where `msg.value` lands (which storage variable increments)
2. **Exit verification:** For each `.call{value:}`, verified that a corresponding state decrement precedes the external call
3. **BPS chain analysis:** For each basis-point calculation, verified rounding direction and calculated worst-case cumulative error
4. **Token invariant verification:** For each token, verified `totalSupply == sum(balanceOf[*])` across all mint/burn/transfer paths
5. **Cross-reference checking:** Verified that when Contract A calls Contract B expecting value X, Contract B actually delivers X

---

## ETH Flow Map

### Entry Points (payable functions)

| Contract | Function | msg.value Destination | Split | Access Control |
|----------|----------|----------------------|-------|----------------|
| DegenerusGame | `recordMint()` | nextPrizePool (90%) + futurePrizePool (10%) | PURCHASE_TO_FUTURE_BPS=1000 | self-call only |
| DegenerusGame | `purchase()` | Delegates to MintModule._purchaseFor | See MintModule | Public |
| DegenerusGame | `purchaseCoin()` | Delegates to MintModule._purchaseCoinFor | Ticket + lootbox | Public |
| DegenerusGame | `purchaseWhaleBundle()` | Delegates to WhaleModule | Ticket-equivalent | Public |
| DegenerusGame | `purchaseLazyPass()` | Delegates to WhaleModule | Pass price | Public |
| DegenerusGame | `purchaseDeityPass()` | Delegates to WhaleModule | Pass price | Public |
| DegenerusGame | `adminSwapEthForStEth()` | Contract keeps ETH, sends stETH out | 1:1 value-neutral | ADMIN only |
| DegenerusGame | `adminStakeEthForStEth()` | Lido staking | Value-preserving | ADMIN only |
| DegenerusGame | `receive()` | futurePrizePool (or pendingPools if frozen) | 100% to future | Public (gameOver guard) |
| DegenerusVault | `deposit()` | Vault ETH reserve | Direct | GAME only |
| DegenerusVault | `receive()` | Vault ETH reserve | Direct | Public |
| DegenerusVault | `gamePurchase()` | Routed to Game.purchase | Pass-through | Vault owner |
| DegenerusVault | `gamePurchaseDeityPassFromBoon()` | Routed to Game.purchaseDeityPass | Pass-through | Vault owner |
| DegenerusVault | `gameDegeneretteBet()` | Routed to Game.degeneretteBet | Pass-through | Vault owner |
| StakedDegenerusStonk | `receive()` | sDGNRS ETH reserve | Direct | GAME only |
| DegenerusStonk | `receive()` | Temporary (burn-through) | From sDGNRS only | sDGNRS only |
| GNRUS | `receive()` | GNRUS ETH reserve (burn redemption) | Direct | Public |
| DegenerusAdmin | `swapGameEthForStEth()` | Routed to Game.adminSwapEthForStEth | Pass-through | Owner only |
| DegenerusGame | Degenerette module | collectBetFunds | Bet amount | Public |

### Exit Points (.call{value:} sends)

| Contract | Function | Source of Funds | Pre-send State Update | CEI |
|----------|----------|----------------|----------------------|-----|
| DegenerusGame | `_payoutWithStethFallback()` | claimableWinnings | `claimablePool -= payout` before call | YES |
| DegenerusGame | `_payoutWithEthFallback()` | claimableWinnings | `claimablePool -= payout` before call | YES |
| DegenerusGame | GameOverModule._sendStethFirst | Terminal distribution | gameOver flag set, pools zeroed | YES |
| StakedDegenerusStonk | `_deterministicBurnFrom()` | sDGNRS ETH reserve | `totalSupply -= amount` before call | YES |
| StakedDegenerusStonk | `_payEth()` | sDGNRS ETH reserve | `pendingRedemptionEthValue -= totalRolledEth` before call | YES |
| StakedDegenerusStonk | `claimRedemption()` | Segregated ETH | `pendingRedemptionEthValue` decremented; claim deleted/zeroed | YES |
| DegenerusStonk | `burn()` | sDGNRS backing | `_burn(msg.sender, amount)` before stonk.burn call | YES |
| DegenerusStonk | `yearSweep()` | sDGNRS backing | stonk.burn called; balance goes to zero | YES |
| GNRUS | `burn()` | GNRUS ETH reserve | `balanceOf[burner] -= amount; totalSupply -= amount` before call | YES |
| DegenerusVault | `_payEth()` | Vault ETH reserve | Share burned before payout | YES |
| MintModule | Lootbox vault share | Lootbox ETH split | Accounting complete before send | YES |

**Arithmetic trace (CEI verification):**
- `DegenerusGame._claimWinningsInternal` (line 1366-1381): State updates `claimableWinnings[player] = 1` and `claimablePool -= payout` at lines 1372-1375, BEFORE external call at line 1378/1380. SAFE.
- `StakedDegenerusStonk._deterministicBurnFrom` (line 501-543): `balanceOf[burnFrom] = bal - amount; totalSupply -= amount` at lines 512-514, BEFORE `.call{value:}` at line 537. SAFE.
- `StakedDegenerusStonk.claimRedemption` (line 593-658): `pendingRedemptionEthValue -= totalRolledEth` at line 632, claim cleared at lines 634-639, BEFORE `_payEth` at line 658. SAFE.

---

## BPS Rounding Chain Analysis

### Chain 1: Ticket Purchase Split (recordMint)

```
prizeContribution = amount  (full cost)
futureShare = (prizeContribution * 1000) / 10_000  [floor division]
nextShare = prizeContribution - futureShare  [remainder to next]
```

**Rounding direction:** Floor division on futureShare means next pool gets slightly more. Both pools belong to the protocol. No value leak.

**Worst case:** For a 1 wei payment: futureShare = 0, nextShare = 1. All wei accounted for.

### Chain 2: Lootbox ETH Split (MintModule._purchaseFor)

```
futureShare = (lootBoxAmount * futureBps) / 10_000  [floor]
nextShare = (lootBoxAmount * nextBps) / 10_000  [floor]
vaultShare = (lootBoxAmount * vaultBps) / 10_000  [floor]
// Dust stays in contract as yield buffer (per NatSpec line 757)
```

**Normal mode BPS:** futureBps=6000, nextBps=4000, vaultBps=0. Sum = 10000.
**Presale mode BPS:** futureBps=3000, nextBps=3000, vaultBps=4000. Sum = 10000.
**Distress mode BPS:** futureBps=0, nextBps=10000, vaultBps=0. Sum = 10000.

**Worst case (normal, 1 wei):** futureShare = 0, nextShare = 0. 1 wei stays in contract. Protocol keeps it. SAFE.
**Worst case (normal, 10001 wei):** futureShare = 6000, nextShare = 4000, dust = 1 wei in contract. SAFE.

**Cumulative rounding per level (estimated):** With thousands of lootbox purchases per level at typical 0.01-10 ETH range, cumulative dust is O(1 wei per purchase). At 10,000 purchases/level: ~10,000 wei = 0.00000000001 ETH. Negligible.

### Chain 3: Affiliate Reward Scaling

```
scaledAmount = (amount * rewardScaleBps) / BPS_DENOMINATOR  [floor]
kickbackShare = (scaledAmount * kickbackPct) / 100  [floor]
affiliateShareBase = scaledAmount - kickbackShare  [remainder]
```

**Rounding direction:** Floor division means affiliate receives slightly less, player kickback slightly less. Protocol retains dust. SAFE.

### Chain 4: sDGNRS Deterministic Burn

```
totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue
totalValueOwed = (totalMoney * amount) / supplyBefore  [floor]
```

**Rounding direction:** Floor division means burner receives slightly less than proportional share. Protocol retains dust. SAFE.

**Solvency proof:** Each burn reduces both numerator (via asset transfer) and denominator (via supply reduction). Since `(totalMoney * amount) / supply` uses floor division, the remaining `totalMoney - totalValueOwed` divided by `supply - amount` is >= the pre-burn ratio. This means later burners receive at least their fair share. Formally: `(M - floor(M*a/S)) / (S-a) >= M/S` when `a < S`. SAFE.

### Chain 5: sDGNRS Gambling Burn Roll

```
rolledEth = (pendingRedemptionEthBase * roll) / 100  [floor, roll in 25-175]
totalRolledEth = (claim.ethValueOwed * roll) / 100  [floor]
ethDirect = totalRolledEth / 2  [floor]
lootboxEth = totalRolledEth - ethDirect  [remainder]
```

**Rounding direction:** All floor divisions. Player receives slightly less. SAFE.

**Solvency check:** `pendingRedemptionEthValue` is updated by `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth` (line 568). Since `rolledEth = floor(base * roll / 100)` and the max roll is 175, the new segregation is at most `1.75 * base` above the pre-base value. The original segregation reserved `base` worth of ETH. At roll=175: segregation increases by `0.75 * base`, which is backed by the proportional share removed from circulation (supply decreased). The sDGNRS contract holds ETH/stETH/claimable backing from game deposits, so the increased obligation is covered by the fact that fewer sDGNRS tokens exist to claim the remaining backing. SAFE.

### Chain 6: Game Over Distribution

```
thirdShare = amount / 3  [floor]
gnrusAmount = amount - thirdShare - thirdShare  [remainder = 34%]
```

**Rounding:** `amount / 3` floors. GNRUS gets the 1-2 wei remainder. All ETH accounted for. SAFE.

### Chain 7: Auto-Rebuy Ticket Conversion

```
ticketPrice = PriceLookupLib.priceForLevel(targetLevel) >> 2
baseTickets = rebuyAmount / ticketPrice  [floor]
ethSpent = baseTickets * ticketPrice  [exact]
remainder = weiAmount - reserved - ethSpent  [goes to claimable]
```

**Rounding:** Floor division on ticket count means unconverted ETH returns to claimable. No value lost. SAFE.

### Chain 8: DGVE/DGVB Vault Share Redemption

```
claimValue = (reserve * amount) / supplyBefore  [floor]
```

**Rounding:** Floor. Share holder receives slightly less. Vault retains dust. SAFE.

---

## Token Accounting Summary

### DGNRS (DegenerusStonk.sol)

| Property | Status |
|----------|--------|
| Mint paths | Constructor only: `totalSupply = deposited; balanceOf[CREATOR] = deposited` |
| Burn paths | `_burn()`: `balanceOf[from] -= amount; totalSupply -= amount` (atomically) |
| Burn paths | `burnForSdgnrs()`: same as `_burn()` but callable by sDGNRS only |
| Transfer paths | Standard `_transfer()`: `balanceOf[from] -= amount; balanceOf[to] += amount` |
| Supply invariant | `totalSupply` decremented on every burn, never incremented post-constructor |
| Overflow risk | Solidity 0.8.34 overflow protection. `unchecked` blocks used only where mathematically safe (balance already validated >= amount) |

**Verdict: totalSupply == sum(balanceOf[*]) at all times.** SAFE.

### sDGNRS (StakedDegenerusStonk.sol)

| Property | Status |
|----------|--------|
| Mint paths | `_mint()` at constructor only: creator allocation + pool total |
| Burn paths | `_deterministicBurnFrom()`, `_submitGamblingClaimFrom()`, `burnAtGameOver()` |
| Transfer paths | `transferFromPool()`: pool -> player (balance only, no totalSupply change) |
| Transfer paths | `wrapperTransferTo()`: DGNRS -> recipient (balance only, no totalSupply change) |
| Supply invariant | Every burn: `totalSupply -= amount` paired with `balanceOf[from] -= amount` |
| Pool accounting | `poolBalances[idx]` decremented on transfer, zeroed on burnAtGameOver |

**Arithmetic trace for supply invariant:**
- Constructor: `_mint(DGNRS, creatorAmount)` + `_mint(this, poolTotal)`. totalSupply = creatorAmount + poolTotal. balanceOf[DGNRS] = creatorAmount, balanceOf[this] = poolTotal. Sum matches.
- `transferFromPool()`: `balanceOf[this] -= amount; balanceOf[to] += amount`. Net zero change in sum. totalSupply unchanged. SAFE.
- `_submitGamblingClaimFrom()`: `balanceOf[burnFrom] -= amount; totalSupply -= amount`. Sum decreases by `amount`, totalSupply decreases by `amount`. SAFE.
- `burnAtGameOver()`: `balanceOf[this] = 0; totalSupply -= bal`. SAFE.

**Verdict: totalSupply == sum(balanceOf[*]) at all times.** SAFE.

### BURNIE (BurnieCoin.sol)

| Property | Status |
|----------|--------|
| Mint paths | `_mint()`: `totalSupply += amount128; balanceOf[to] += amount` (vault special: vaultAllowance instead) |
| Burn paths | `_burn()`: `balanceOf[from] -= amount; totalSupply -= amount128` (vault special: vaultAllowance) |
| Transfer paths | `_transfer()`: standard balance debit/credit; vault special burns-on-receive |
| Supply invariant | `totalSupply + vaultAllowance = supplyIncUncirculated` (per NatSpec line 18-19) |

**Vault escrow special case:** When tokens are transferred to VAULT address, they are burned and `vaultAllowance` increases. When vault mints to a player, `vaultAllowance` decreases and `totalSupply` increases. This maintains the invariant: `totalSupply + vaultAllowance = const` (modulo external mints/burns). SAFE.

**External mint callers (access control):**
- `mintForCoinflip()`: coinflipContract only
- `mintForGame()`: GAME only
- `creditCoin()`: GAME or AFFILIATE only
- `vaultMintTo()`: called via vault path

All gated. No unauthorized mint paths. SAFE.

### GNRUS (GNRUS.sol)

| Property | Status |
|----------|--------|
| Mint paths | Constructor only: `_mint(address(this), INITIAL_SUPPLY)` |
| Burn paths | `burn()`: `balanceOf[burner] -= amount; totalSupply -= amount` |
| Burn paths | `burnAtGameOver()`: `balanceOf[this] = 0; totalSupply -= unallocated` |
| Transfer paths | Soulbound: `transfer()`, `transferFrom()`, `approve()` all revert |
| Distribution | `onLevelUp()` (GAME only): `balanceOf[this] -= amount; balanceOf[recipient] += amount` |

**Verdict:** No external mint after constructor. All burns atomic. Soulbound prevents unauthorized transfers. SAFE.

### wXRP (WrappedWrappedXRP.sol)

| Property | Status |
|----------|--------|
| Mint paths | `mintPrize()` (GAME/COIN/COINFLIP only), `vaultMintTo()` (VAULT only), `_wrap()` (on wXRP deposit) |
| Burn paths | `_burn()` via `unwrap()` (requires wXRP reserve), `burnForGame()` (GAME only) |
| Transfer paths | Standard ERC20 |
| Supply invariant | `totalSupply` increases on all mints, decreases on all burns |
| Backing | Intentionally under-collateralized (mintPrize creates unbacked tokens). This is by design -- wXRP is a game token. |

**Verdict:** SAFE. Under-collateralization is intentional (documented in contract NatSpec).

### VaultShares (DGVB, DGVE via DegenerusVaultShare)

| Property | Status |
|----------|--------|
| Mint paths | Constructor (1T to CREATOR), `vaultMint()` (VAULT only, refill on full-burn) |
| Burn paths | `vaultBurn()` (VAULT only) |
| Transfer paths | Standard ERC20 |

**Verdict:** Controlled mint/burn via vault only. SAFE.

---

## Cross-Token Interaction Analysis

### 1. DGNRS <-> sDGNRS Wrap/Unwrap

**Wrap path (unwrapTo):**
```
DegenerusStonk.unwrapTo(recipient, amount):
  1. Vault owner check
  2. VRF stall check (5h guard)
  3. _burn(msg.sender, amount)  -- burns DGNRS
  4. stonk.wrapperTransferTo(recipient, amount)  -- moves sDGNRS
```

**Analysis:** `_burn` decreases DGNRS totalSupply. `wrapperTransferTo` moves sDGNRS from DGNRS contract's balance to recipient. No new tokens created. The DGNRS supply shrinks while sDGNRS balance redistributes. The total backing (ETH+stETH in sDGNRS) is unchanged. SAFE.

**Sandwich attack surface:** The 5h VRF stall guard prevents unwrap during periods when governance votes might be in flight. The function is restricted to vault owner only. No sandwich opportunity -- there's no price oracle involved in the unwrap. SAFE.

### 2. DGNRS -> sDGNRS Burn (burnWrapped)

```
StakedDegenerusStonk.burnWrapped(amount):
  1. dgnrsWrapper.burnForSdgnrs(msg.sender, amount)  -- burns DGNRS from player
  2. If gameOver: _deterministicBurnFrom(msg.sender, DGNRS, amount)
     -- burns sDGNRS from DGNRS contract's balance, pays ETH/stETH to msg.sender
  3. If !gameOver: _submitGamblingClaimFrom(msg.sender, DGNRS, amount)
     -- burns sDGNRS from DGNRS contract's balance, segregates proportional value
```

**Analysis:** The DGNRS contract's `burnForSdgnrs` requires `msg.sender == SDGNRS`. It burns the player's DGNRS, making the DGNRS supply shrink. Then sDGNRS burns the equivalent sDGNRS from the DGNRS contract's balance. Both supplies decrease by `amount`. The player receives proportional backing. SAFE.

**Double-burn check:** Could a player call both `burn()` on DGNRS and `burnWrapped()` on sDGNRS for the same tokens? No. `DGNRS.burn()` calls `_burn(msg.sender, amount)` which decrements `balanceOf[msg.sender]`. `burnWrapped()` calls `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` which also decrements `balanceOf[msg.sender]`. Both decrement the same balance mapping. Solidity 0.8 underflow protection prevents double-spend. SAFE.

### 3. BURNIE Burn-to-Play (BurnieCoinflip)

The coinflip system uses a credit/stake model:
- `creditFlip()` records virtual stake (no actual token movement)
- Daily resolution uses VRF to determine win/loss
- Winners can `claimCoinflips()` which mints new BURNIE via `coin.mintForCoinflip()`
- Losers' stakes are simply not claimable

**Solvency:** BURNIE is inflationary by design (minting on wins, burning on stakes via `burnForCoinflip`). The coinflip house edge (weighted toward losses) ensures long-term deflationary pressure. This is documented in KNOWN-ISSUES.md. SAFE.

### 4. GNRUS Burn Redemption

```
GNRUS.burn(amount):
  1. Last-holder sweep logic
  2. owed = ((ethBal + stethBal + claimable) * amount) / supply  [floor]
  3. balanceOf[burner] -= amount; totalSupply -= amount  [CEI: before transfers]
  4. stETH transfer, then ETH transfer
```

**Analysis:** Proportional redemption with floor division favoring remaining holders. CEI enforced. `claimableWinnings` from game are auto-claimed if needed. SAFE.

**Attack surface:** Could an attacker front-run a large GNRUS burn to extract value? The attacker would need GNRUS tokens (soulbound -- no transfer). They can only burn their own tokens. Each burn reduces supply proportionally. No extraction possible. SAFE.

### 5. Vault Share-to-Asset (DGVE -> ETH/stETH)

```
DegenerusVault._burnEthFor(player, amount):
  reserve = (ethBal + stBal) + claimable
  claimValue = (reserve * amount) / supplyBefore  [floor]
  share.vaultBurn(player, amount)
  if supplyBefore == amount: share.vaultMint(player, REFILL_SUPPLY)
  pay ETH/stETH
```

**Analysis:** Standard proportional share redemption. Auto-claims game winnings if needed. Refill mechanism (1T new shares) when last holder burns all shares prevents permanent lockout. SAFE.

**Refill attack:** If an attacker burns all DGVE shares, they receive all ETH/stETH. Then they get 1T new shares on an empty vault. This is correct behavior -- they owned all shares and redeemed all value. New shares are worthless until new deposits arrive. SAFE.

---

## Findings

No HIGH or MEDIUM severity findings.

---

## SAFE Proofs

### SAFE-M01: Reentrancy on claimWinnings

**Attack surface:** DegenerusGame._claimWinningsInternal sends ETH to player addresses. A malicious contract could re-enter.

**Arithmetic trace:**
```
File: DegenerusGame.sol:1366-1381

1. amount = claimableWinnings[player]       // Read
2. claimableWinnings[player] = 1            // Write: sentinel (line 1372)
3. payout = amount - 1                      // Calculate
4. claimablePool -= payout                  // Write: aggregate (line 1375)
5. _payoutWithStethFallback(player, payout)  // External call (line 1380)
```

On re-entry to `claimWinnings`, step 1 reads `claimableWinnings[player] = 1` (sentinel). Step 2 checks `amount <= 1` and reverts. Re-entrancy is blocked by the sentinel pattern. **SAFE.**

### SAFE-M02: Admin ETH Extraction via adminSwapEthForStEth

**Attack surface:** Compromised admin calls `adminSwapEthForStEth` to extract game stETH.

**Arithmetic trace:**
```
File: DegenerusGame.sol:1818-1830

1. msg.sender != ADMIN → revert                    // Access check
2. msg.value != amount → revert                    // Value check
3. stBal < amount → revert                         // Balance check
4. steth.transfer(recipient, amount)                // Send stETH out
5. Contract keeps msg.value (ETH)                   // Receive ETH in
```

The swap is value-neutral: admin sends X ETH, receives X stETH. The game's total value (ETH + stETH) is unchanged. Admin cannot extract net value. **SAFE.**

### SAFE-M03: Admin ETH Extraction via adminStakeEthForStEth

**Attack surface:** Compromised admin stakes all ETH, then stETH depegs.

**Arithmetic trace:**
```
File: DegenerusGame.sol:1839-1860

1. reserve = claimablePool - stethSettleable       // Player claims reserve
2. stakeable = ethBal - reserve                     // Only excess staked
3. amount > stakeable → revert                      // Guard
4. steth.submit{value: amount}(address(0))          // Stake to Lido
```

Admin can only stake ETH above the player-claims reserve. `stethSettleable` accounts for vault/sDGNRS claims that can be settled in stETH (they accept stETH natively). Player ETH claims are always backed. stETH depeg is an external risk (Lido dependency documented in KNOWN-ISSUES). **SAFE.**

### SAFE-M04: sDGNRS Gambling Burn Solvency

**Attack surface:** Multiple players submit gambling burns. Roll is 175 (max). Can total obligations exceed backing?

**Arithmetic trace:**
```
File: StakedDegenerusStonk.sol:727-789

1. ethValueOwed = (totalMoney * amount) / supplyBefore   // Proportional share
2. pendingRedemptionEthValue += ethValueOwed               // Segregate
3. totalSupply -= amount                                   // Burn
```

After step 3, `totalMoney` decreased by 0 (no ETH moved yet) but `pendingRedemptionEthValue` increased by `ethValueOwed`. Next burner sees:
```
totalMoney' = (ethBal + stethBal + claimableEth) - pendingRedemptionEthValue'
```
Where `pendingRedemptionEthValue'` now includes the previous segregation. The next burner's proportional share is computed on the reduced `totalMoney'` and reduced `supplyBefore'`. This correctly prevents over-allocation.

**Roll=175 solvency:** After resolution, `pendingRedemptionEthValue` becomes `pendingRedemptionEthValue - base + rolledEth`. If roll=175: `rolledEth = base * 1.75`. The increase is `0.75 * base`. But the burned sDGNRS tokens no longer have a claim on the backing. The protocol is solvent as long as `totalBacking >= pendingRedemptionEthValue + (remaining_supply_pro_rata_value)`. Since burns reduce supply proportionally, and the 50% per-period cap limits exposure, the system remains solvent. **SAFE.**

**50% supply cap:** `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2 → revert`. This limits worst-case exposure per period to 50% * 1.75 = 87.5% of the period's proportional backing. With the supply snapshot taken at period start, this is conservative. **SAFE.**

### SAFE-M05: Double-Claim on Gambling Redemption

**Attack surface:** Player calls `claimRedemption()` twice to double-claim ETH.

**Arithmetic trace:**
```
File: StakedDegenerusStonk.sol:593-658

1. claim = pendingRedemptions[player]           // Read
2. claim.periodIndex == 0 → revert NoClaim      // Guard (line 596)
3. period.roll == 0 → revert NotResolved         // Guard (line 599)
4. pendingRedemptionEthValue -= totalRolledEth   // Decrement (line 632)
5. If flipResolved: delete pendingRedemptions[player]  // Clear (line 636)
6. Else: claim.ethValueOwed = 0                  // Zero ETH portion (line 639)
7. _payEth(player, ethDirect)                    // Pay (line 658)
```

On second call: if flipResolved, step 2 reverts (periodIndex is 0 after delete). If not flipResolved, `claim.ethValueOwed = 0`, so `totalRolledEth = 0`, and `ethDirect = 0`. No double-payment. **SAFE.**

### SAFE-M06: claimablePool Accounting Integrity

**Attack surface:** claimablePool diverges from sum of claimableWinnings, enabling extraction.

**All increment paths:**
- `_creditClaimable()` in PayoutUtils: `claimableWinnings[b] += weiAmount` (no claimablePool update here -- caller must update)
- `_addClaimableEth()` and `_distributeJackpotEth()` in JackpotModule: return `claimableDelta` which caller adds to `claimablePool`
- `GameOverModule.handleGameOverDrain`: `claimablePool += totalRefunded` (deity pass refunds)
- `GameOverModule.handleGameOverDrain`: `claimablePool += decSpend` (decimator spend)
- EndgameModule: `claimablePool += claimableDelta` (BAF/decimator rewards)
- DegeneretteModule: `claimablePool += weiAmount` (bet winnings)

**All decrement paths:**
- `_claimWinningsInternal()`: `claimablePool -= payout`
- `_processMintPayment()`: `claimablePool -= claimableUsed` (spending claimable on tickets)
- `MintModule._purchaseFor()`: `claimablePool -= shortfall` (lootbox claimable)
- `DegeneretteModule._collectBetFunds`: `claimablePool -= fromClaimable`
- `DecimatorModule`: `claimablePool -= calc.ethSpent` (ticket conversion)
- `DecimatorModule`: `claimablePool -= lootboxPortion`
- `resolveRedemptionLootbox` (called from sDGNRS): decrements claimablePool via game

**Pattern:** Every path that increments `claimableWinnings[player]` has a corresponding `claimablePool +=` (either inline or via returned delta). Every path that decrements `claimableWinnings[player]` has a corresponding `claimablePool -=`. The accounting is symmetric. **SAFE.**

### SAFE-M07: Affiliate Self-Referral Extraction

**Attack surface:** Player creates affiliate code, refers themselves, extracts excess BURNIE rewards.

**Trace:**
```
File: DegenerusAffiliate.sol:396-568

1. If code owner == sender → lock to VAULT (line 438)
2. Self-referral is explicitly checked and rejected
```

Self-referral is impossible: `resolved == sender` triggers VAULT default. The player gets no affiliate commission. Even with two accounts (Sybil), the commission is capped at 0.5 ETH BURNIE per referrer-per-sender-per-level (`MAX_COMMISSION_PER_REFERRER_PER_LEVEL`). **SAFE.**

### SAFE-M08: Vault Owner Fund Extraction

**Attack surface:** Vault owner (>50.1% DGVE) extracts vault funds via gameplay actions.

**Trace:** Vault owner can:
- `gamePurchase()`: Buys tickets/lootboxes using vault ETH → ETH goes to game prize pools. Value converted to game assets, not extractable.
- `gamePurchaseDeityPassFromBoon()`: Uses claimable + vault ETH for deity pass. Price is deterministic. No arbitrage.
- `burnEth()`: Burns DGVE shares → receives proportional ETH/stETH. This is the correct redemption path.
- `burnCoin()`: Burns DGVB shares → receives proportional BURNIE. Correct.

Vault owner cannot: extract more than their proportional share (share math is pro-rata), bypass share redemption, or directly transfer vault funds. **SAFE.**

### SAFE-M09: uint96 Truncation in Gambling Claims

**Attack surface:** `claim.ethValueOwed += uint96(ethValueOwed)` could truncate if ethValueOwed exceeds uint96.max (~79.2 billion ETH).

**Trace:** The 160 ETH daily cap (`MAX_DAILY_REDEMPTION_EV` check at line 776) ensures ethValueOwed per claim never approaches uint96 range. Even without the cap: sDGNRS totalSupply at maximum realistic values (~200B tokens * $0.01 = ~$2B backing) would produce ethValueOwed well within uint96. **SAFE.**

### SAFE-M10: Prize Pool Frozen/Pending Pools Accounting

**Attack surface:** ETH arrives during `prizePoolFrozen=true`, goes to pending pools. Could it be lost?

**Trace:** When prize pool is frozen (during jackpot processing), ETH is routed to `pendingPools` via `_setPendingPools`. At the end of jackpot processing (level transition), pending pools are merged into active pools. The AdvanceModule handles this merge. No ETH is lost during the frozen window -- it's just deferred. **SAFE.**

---

## Cross-Domain Findings

### INFO-CD01: stETH 1-2 Wei Rounding (Lido Rebasing)

Lido stETH transfers may deliver 1-2 wei less than the requested amount due to share-based accounting. This is documented in KNOWN-ISSUES.md ("All rounding favors solvency"). The protocol handles this by using stETH as a fallback asset (ETH preferred for player claims). The 1-2 wei discrepancy is economically negligible and structurally favorable to the protocol.

### INFO-CD02: Degenerette Bet Funds Collection

The `_collectBetFunds` function in DegeneretteModule allows bets to be funded from claimable winnings. This correctly decrements `claimablePool` when claimable is used. The BURNIE and wXRP bet paths use standard burn/transfer patterns. No money correctness issue.

---

## Attack Surface Inventory

| # | Surface | Contract(s) | Functions | Disposition | Evidence |
|---|---------|-------------|-----------|-------------|----------|
| 1 | ETH overpay on ticket purchase | DegenerusGame | recordMint, _processMintPayment | SAFE | Overpay ignored for accounting; exact `amount` goes to pools |
| 2 | claimableWinnings sentinel bypass | DegenerusGame | _claimWinningsInternal | SAFE | Sentinel=1; requires amount>1 to claim (SAFE-M01) |
| 3 | Admin ETH swap extraction | DegenerusGame | adminSwapEthForStEth | SAFE | Value-neutral: ETH in = stETH out (SAFE-M02) |
| 4 | Admin staking drains player reserve | DegenerusGame | adminStakeEthForStEth | SAFE | Reserve guard prevents staking player claims (SAFE-M03) |
| 5 | Prize pool manipulation via receive() | DegenerusGame | receive() | SAFE | gameOver guard; funds go to future pool only |
| 6 | sDGNRS deterministic burn over-payout | StakedDegenerusStonk | _deterministicBurnFrom | SAFE | Floor division favors protocol (SAFE-M04 partial) |
| 7 | sDGNRS gambling burn solvency | StakedDegenerusStonk | _submitGamblingClaimFrom | SAFE | 50% supply cap + segregation + supply reduction (SAFE-M04) |
| 8 | Gambling burn double-claim | StakedDegenerusStonk | claimRedemption | SAFE | Claim deleted/zeroed before payment (SAFE-M05) |
| 9 | Gambling roll 175 max extraction | StakedDegenerusStonk | resolveRedemptionPeriod | SAFE | Supply reduction compensates increased obligation (SAFE-M04) |
| 10 | CP-08: deterministic burn ignores pending | StakedDegenerusStonk | _deterministicBurnFrom | SAFE | `pendingRedemptionEthValue` subtracted from totalMoney (line 509) |
| 11 | DGNRS burn double-spend | DegenerusStonk | burn, burnForSdgnrs | SAFE | Same balanceOf mapping; Solidity underflow prevents (Cross-Token #2) |
| 12 | DGNRS yearSweep premature | DegenerusStonk | yearSweep | SAFE | Requires gameOver + 365 days elapsed |
| 13 | GNRUS proportional burn overpay | GNRUS | burn | SAFE | Floor division; last-holder sweep handles dust |
| 14 | GNRUS unauthorized distribution | GNRUS | onLevelUp | SAFE | onlyGame modifier; soulbound prevents transfer |
| 15 | Vault DGVE share redemption over-claim | DegenerusVault | _burnEthFor | SAFE | Pro-rata floor division; auto-claim if needed (SAFE-M08) |
| 16 | Vault DGVB share redemption | DegenerusVault | burnCoin | SAFE | Pro-rata floor division with refill mechanism |
| 17 | Vault owner fund extraction | DegenerusVault | gamePurchase, burnEth | SAFE | Only pro-rata redemption or game purchases (SAFE-M08) |
| 18 | Affiliate self-referral | DegenerusAffiliate | payAffiliate | SAFE | Self-referral → VAULT default (SAFE-M07) |
| 19 | Affiliate commission cap bypass | DegenerusAffiliate | payAffiliate | SAFE | Per-sender-per-level cap enforced |
| 20 | Lootbox ETH split rounding | DegenerusGameMintModule | _purchaseFor | SAFE | Dust stays in contract as yield buffer |
| 21 | Lootbox payment with claimable | DegenerusGameMintModule | _purchaseFor | SAFE | claimablePool correctly decremented |
| 22 | Ticket purchase BPS split | DegenerusGame | recordMint | SAFE | Floor on future share; remainder to next pool |
| 23 | Whale bundle pricing | DegenerusGameWhaleModule | purchaseWhaleBundle | SAFE | msg.value != totalPrice → revert |
| 24 | Lazy pass pricing | DegenerusGameWhaleModule | purchaseLazyPass | SAFE | msg.value != totalPrice → revert |
| 25 | Deity pass pricing | DegenerusGameWhaleModule | purchaseDeityPass | SAFE | msg.value != totalPrice → revert |
| 26 | Game over deity pass refund | DegenerusGameGameOverModule | handleGameOverDrain | SAFE | Budget-capped to available minus claimablePool |
| 27 | Game over terminal jackpot | DegenerusGameGameOverModule | handleGameOverDrain | SAFE | claimablePool updated; remainder to vault |
| 28 | Final sweep (30 day) | DegenerusGameGameOverModule | handleFinalSweep | SAFE | 33/33/34 split to sDGNRS/vault/GNRUS |
| 29 | claimablePool accounting divergence | DegenerusGame + modules | All credit/debit paths | SAFE | Symmetric increment/decrement verified (SAFE-M06) |
| 30 | BURNIE unauthorized mint | BurnieCoin | _mint, mintForCoinflip, mintForGame | SAFE | Access-gated to COINFLIP, GAME, AFFILIATE |
| 31 | BURNIE vault escrow manipulation | BurnieCoin | vaultEscrow, _mint(VAULT) | SAFE | Only GAME can call vaultEscrow; vault special-cased |
| 32 | BURNIE auto-claim on transfer | BurnieCoin | _claimCoinflipShortfall | SAFE | Mints from coinflip claimable; backed by prior wins |
| 33 | wXRP unbacked mint inflation | WrappedWrappedXRP | mintPrize | SAFE | Intentional design; documented as under-collateralized |
| 34 | wXRP unwrap when reserves empty | WrappedWrappedXRP | unwrap | SAFE | `wXRPReserves < amount → revert` guard |
| 35 | Degenerette bet fund collection | DegenerusGameDegeneretteModule | _collectBetFunds | SAFE | claimablePool decremented for claimable usage |
| 36 | Decimator pool reservation | DegenerusGameDecimatorModule | via claimablePool | SAFE | Pre-reserved; decremented on ticket conversion |
| 37 | BAF/Endgame reward jackpots | DegenerusGameEndgameModule | runRewardJackpots | SAFE | claimableDelta tracked and added to claimablePool |
| 38 | Auto-rebuy ticket conversion | DegenerusGamePayoutUtils | _calcAutoRebuy | SAFE | Floor division; remainder to claimable |
| 39 | Coinflip bounty DGNRS payout | DegenerusGame | payCoinflipBountyDgnrs | SAFE | Floor division on pool; gated by min bet/pool |
| 40 | DGNRS vesting claim | StakedDegenerusStonk | claimVested (via wrapper) | SAFE | Capped at 5B per level, max 200B total at level 30 |
| 41 | Redemption lootbox internal debit | DegenerusGame | resolveRedemptionLootbox | SAFE | Debits from sDGNRS claimable; no double-spend |
| 42 | sDGNRS receive() ETH deposit | StakedDegenerusStonk | receive() | SAFE | onlyGame modifier prevents unauthorized deposits |

**Coverage:** 42 attack surfaces identified and assessed. All payable functions and all ETH-sending functions appear in the inventory. Every money path traced from entry to exit.

---

## Conclusion

The Degenerus Protocol exhibits strong money correctness properties:

1. **CEI enforcement is universal.** Every ETH-sending function updates state before the external call. The 1-wei sentinel pattern provides additional reentrancy protection on claimable winnings.

2. **BPS rounding is uniformly favorable to protocol solvency.** Floor division on all payouts means the protocol retains dust. Cumulative rounding error across thousands of transactions is economically negligible (< 1 gwei per level).

3. **Token supply invariants are maintained.** All six token types maintain `totalSupply == sum(balanceOf[*])` (with the BURNIE vault allowance accounting correctly handled as a separate bucket).

4. **Cross-token interactions are value-preserving.** The DGNRS/sDGNRS wrap/unwrap, BURNIE coinflip, GNRUS redemption, and vault share systems all use proportional math with correct denominator handling.

5. **Admin cannot extract funds.** The swap and staking functions are value-neutral by construction. Governance-gated operations (VRF swap, price feed swap) require community approval.

Zero HIGH, zero MEDIUM, zero LOW findings. The protocol's money flows are correct.
