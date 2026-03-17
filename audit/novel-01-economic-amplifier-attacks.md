# Novel Attack Surface: Economic & Amplifier Attack Analysis

**Audit Date:** 2026-03-17
**Auditor:** Claude (AI-assisted adversarial analysis, Claude Opus 4.6)
**Scope:** Economic attack modeling (NOVEL-01) and DGNRS-as-attack-amplifier analysis (NOVEL-12) for the sDGNRS/DGNRS dual-token system
**Methodology:** C4A warden-style: hypothesis, attack path trace with file:line citations, explicit economic viability math, SAFE/EXPLOITABLE/GRIEFABLE/OUT_OF_SCOPE verdicts
**Prior Audit Reference:** v2.0-delta-core-contracts.md (SOUND), v2.0-delta-findings-consolidated.md (1L + 4I)

---

## NOVEL-01: Economic Attack Modeling

This section analyzes five economic attack vectors targeting the DGNRS burn-redeem mechanism and sDGNRS reserves. Each vector is evaluated for profitability: can an attacker extract more value than they invest?

### Vector 1: Flash Loan + Reserve Inflation

**Hypothesis:** An attacker flash-loans ETH, inflates sDGNRS reserves, then burns DGNRS to claim a proportionally larger share of the inflated reserves, repaying the loan at a profit.

**Attack Path:**

1. Attacker flash-loans Y ETH from Aave/Maker
2. Attacker attempts to deposit Y ETH into sDGNRS reserves
3. **BLOCKED:** sDGNRS has only two ETH deposit paths:
   - `StakedDegenerusStonk.sol:282` -- `receive() external payable onlyGame` -- restricted to game contract
   - `StakedDegenerusStonk.sol:291` -- `depositSteth(uint256 amount) external onlyGame` -- restricted to game contract
4. The `onlyGame` modifier (`StakedDegenerusStonk.sol:181-184`) checks `msg.sender != ContractAddresses.GAME` and reverts with `Unauthorized()` for any other caller
5. There is NO public function to deposit ETH or stETH into sDGNRS reserves

**Economic Analysis:**

Even if the deposit were possible (hypothetically):
- Attacker holds X% of total DGNRS supply
- Attacker deposits Y ETH, making total reserves = M + Y
- Attacker burns their DGNRS to claim: `X% * (M + Y)`
- Attacker's net: `X% * (M + Y) - Y = X% * M + X% * Y - Y = X% * M - (1 - X%) * Y`
- The `X% * M` term is what they were already entitled to (and they lose access to future burns)
- The `-(1 - X%) * Y` term is a **net loss** for any holder with < 100% supply

For concrete numbers: if attacker holds 1% of supply and deposits 100 ETH:
- Recovers: `1% * 100 = 1 ETH` from the deposited amount
- Loses: `99 ETH` (gifted to other holders proportionally)
- Total cost: 99 ETH loss + flash loan fee

**Prerequisites:** A public deposit path to sDGNRS reserves (does not exist).

**Verdict:** SAFE

The `onlyGame` restriction on both `receive()` and `depositSteth()` prevents any external actor from depositing ETH or stETH into sDGNRS reserves. Flash loan reserve inflation is architecturally impossible. Even if a deposit path existed, the proportional formula ensures a net loss for any attacker holding less than 100% of supply.

**Evidence:**
- `StakedDegenerusStonk.sol:282` -- `receive() external payable onlyGame`
- `StakedDegenerusStonk.sol:291` -- `function depositSteth(uint256 amount) external onlyGame`
- `StakedDegenerusStonk.sol:181-184` -- `modifier onlyGame()` checks `msg.sender != ContractAddresses.GAME`
- `StakedDegenerusStonk.sol:391` -- proportional formula `(totalMoney * amount) / supplyBefore`

**Mitigation Status:** Already mitigated by design. The `onlyGame` modifier blocks the attack at step 2.

---

### Vector 2: Selfdestruct / Force-Send ETH Injection

**Hypothesis:** An attacker uses `CREATE` + `SELFDESTRUCT` (permitted in the same transaction post-Cancun per EIP-6780) to force-send ETH into the sDGNRS contract, bypassing the `onlyGame` `receive()` guard. Since `burn()` reads `address(this).balance`, the injected ETH inflates burn payouts.

**Attack Path:**

1. Attacker creates a factory contract in transaction T
2. Factory deploys a child contract with `new{value: Y}(sDGNRS_address)` in the same transaction
3. Child contract calls `selfdestruct(payable(sDGNRS_address))` in its constructor
4. Per EIP-6780 (Cancun, March 2024): `SELFDESTRUCT` in the creation transaction still transfers remaining ETH to the target, bypassing `receive()`. The contract's code and storage are erased.
5. sDGNRS now has an additional Y ETH in `address(this).balance`
6. Attacker calls `DegenerusStonk.sol:153` -- `burn(amount)` which calls `StakedDegenerusStonk.sol:379` -- `burn(amount)`
7. At `StakedDegenerusStonk.sol:387`: `ethBal = address(this).balance` -- this **includes** the force-sent Y ETH
8. At `StakedDegenerusStonk.sol:390-391`: `totalMoney = ethBal + stethBal + claimableEth` and `totalValueOwed = (totalMoney * amount) / supplyBefore` -- the inflated ethBal increases totalValueOwed

**Economic Analysis:**

Let:
- M = sDGNRS reserves before injection (ETH + stETH + claimable)
- Y = ETH force-sent by attacker
- X% = attacker's share of total supply (via DGNRS or direct sDGNRS holdings)
- S = totalSupply before burn
- A = attacker's token amount (X% * S)

After injection, the attacker burns A tokens:
```
totalMoney = M + Y
totalValueOwed = ((M + Y) * A) / S = X% * (M + Y)
                = X% * M + X% * Y
```

Cost to attacker: Y ETH (force-sent) + gas
Value received: X% * (M + Y)
Net gain from injection: X% * Y - Y = -(1 - X%) * Y

**For X% = 1%:** Attacker force-sends 100 ETH, recovers 1 ETH from injection, net loss = 99 ETH.
**For X% = 10%:** Attacker force-sends 100 ETH, recovers 10 ETH from injection, net loss = 90 ETH.
**For X% = 50%:** Attacker force-sends 100 ETH, recovers 50 ETH from injection, net loss = 50 ETH.

Force-sent ETH is distributed proportionally to ALL burners, not just the attacker. The attacker always loses `(1 - X%) * Y`, which is positive for any X% < 100%. This is economically a **donation to all token holders**, not an exploit.

**Prerequisites:**
- Attacker must hold DGNRS or sDGNRS tokens to burn
- Attacker must have ETH to force-send
- SELFDESTRUCT force-send still works post-Cancun (EIP-6780 confirms: yes, in creation tx)

**Verdict:** SAFE

Force-sending ETH to sDGNRS is a donation, not an exploit. The proportional burn formula (`StakedDegenerusStonk.sol:391`) ensures that forced ETH is distributed pro-rata to all burners. The attacker cannot recover more than their proportional share of what they injected. Net result is always a loss for the attacker (unless they hold 100% of supply, in which case there is no one to exploit).

**Evidence:**
- `StakedDegenerusStonk.sol:387` -- `uint256 ethBal = address(this).balance` (includes force-sent ETH)
- `StakedDegenerusStonk.sol:390` -- `uint256 totalMoney = ethBal + stethBal + claimableEth`
- `StakedDegenerusStonk.sol:391` -- `uint256 totalValueOwed = (totalMoney * amount) / supplyBefore`
- `StakedDegenerusStonk.sol:282` -- `receive() external payable onlyGame` (bypassed by SELFDESTRUCT)
- EIP-6780: SELFDESTRUCT in creation transaction still force-sends ETH

**Mitigation Status:** No mitigation needed. The proportional formula is the defense -- it makes forced ETH injection unprofitable by design.

---

### Vector 3: MEV Sandwich on DGNRS Burns

**Hypothesis:** An attacker monitors the mempool for pending DGNRS burn transactions. They front-run with their own burn to extract a disproportionately larger share of reserves before the victim's burn reduces them.

**Attack Path:**

1. Victim submits `DGNRS.burn(Y)` to mempool
2. Attacker sees pending tx, submits `DGNRS.burn(X)` with higher gas price (front-run)
3. Block ordering: Attacker's burn executes first, then victim's burn

**Attacker's burn (first in block):**
```
supplyBefore_A = S
totalMoney_A = M
payout_A = (M * X) / S
```
After attacker's burn: supply = S - X, reserves = M - (M * X / S) = M * (S - X) / S

**Victim's burn (second in block):**
```
supplyBefore_V = S - X
totalMoney_V = M * (S - X) / S
payout_V = (totalMoney_V * Y) / supplyBefore_V
         = (M * (S - X) / S * Y) / (S - X)
         = (M * Y) / S
```

**Economic Analysis:**

The critical insight: **ordering does not affect proportional payouts.**

- Attacker's payout: `(M * X) / S`
- Victim's payout: `(M * Y) / S`

Both receive exactly their proportional share of the **original** reserves, regardless of burn ordering. This is because the proportional formula `(totalMoney * amount) / supplyBefore` cancels out perfectly: when the first burner reduces both reserves and supply proportionally, the second burner's ratio `reserves / supply` remains unchanged.

Formally, after burner A removes `X / S` fraction of both supply and reserves:
```
remaining_reserves = M * (1 - X/S)
remaining_supply   = S * (1 - X/S)
ratio = remaining_reserves / remaining_supply = M / S  (unchanged)
```

**For concrete numbers:** Suppose S = 1000 tokens, M = 100 ETH.
- Without front-running: Victim burns 10 tokens, gets `(100 * 10) / 1000 = 1 ETH`
- With front-running (attacker burns 50 first): Reserves become `100 - 5 = 95 ETH`, supply becomes `950`. Victim burns 10, gets `(95 * 10) / 950 = 1 ETH`. **Identical.**

**Prerequisites:** Attacker needs DGNRS tokens to burn (destructive -- tokens are gone).

**Verdict:** SAFE

Sandwich attacks on DGNRS burns are not profitable. The proportional burn-redeem formula ensures that each burner receives exactly `(amount / totalSupply) * totalReserves` regardless of ordering. Front-running a burn does not extract extra value because reserves and supply decrease in lockstep.

**Evidence:**
- `StakedDegenerusStonk.sol:385` -- `uint256 supplyBefore = totalSupply`
- `StakedDegenerusStonk.sol:390-391` -- proportional calculation reads totalSupply and reserves atomically
- `StakedDegenerusStonk.sol:398-400` -- `balanceOf[player] = bal - amount; totalSupply -= amount;` state committed before external calls
- `DegenerusStonk.sol:154` -- `_burn(msg.sender, amount)` reduces DGNRS supply first

**Mitigation Status:** No mitigation needed. Proportional formula is inherently order-independent.

---

### Vector 4: MEV Sandwich on DGNRS DEX Trades

**Hypothesis:** If DGNRS is listed on a DEX (e.g., Uniswap), standard MEV sandwich attacks apply to DGNRS buy/sell trades, extracting value from traders through price manipulation.

**Attack Path:**

1. DGNRS is listed on Uniswap V3 (or similar AMM) as a DGNRS/ETH pair
2. Victim submits a large DGNRS buy on the DEX
3. MEV bot front-runs with own DGNRS buy (pushes price up)
4. Victim's buy executes at worse price
5. MEV bot back-runs by selling DGNRS at the inflated price

**Economic Analysis:**

This is **standard AMM MEV** -- the exact same sandwich attack that applies to any ERC20 token traded on a DEX. The attack targets the DEX liquidity pool, not the DGNRS protocol itself.

Key distinctions:
- The DGNRS protocol has **no DEX integration** -- there is no Uniswap router call, no LP provision, no AMM interaction in either `StakedDegenerusStonk.sol` or `DegenerusStonk.sol`
- If users choose to provide liquidity on a DEX, they do so externally
- The sandwich risk is on the DEX trading pair, not on the DGNRS burn-redeem mechanism
- DGNRS burn value (proportional reserves) is unaffected by DEX price manipulation -- the burn formula reads `address(this).balance` and `steth.balanceOf(address(this))`, not any DEX oracle

**Prerequisites:** DGNRS must be listed on a DEX (external action, not part of the protocol).

**Verdict:** OUT_OF_SCOPE

Standard AMM MEV on external DEX trading is not a DGNRS protocol vulnerability. The protocol's burn-redeem mechanism is unaffected by DEX price movements. MEV protection is the responsibility of the DEX and the trader (private mempools, MEV blockers, slippage limits).

**Evidence:**
- `DegenerusStonk.sol:101-103` -- standard ERC20 `transfer()`, no DEX integration
- `DegenerusStonk.sol:113-122` -- standard `transferFrom()`, no AMM hooks
- `StakedDegenerusStonk.sol:387-391` -- burn reads on-chain balances, not DEX prices

**Mitigation Status:** Out of protocol scope. No protocol-level mitigation needed or possible.

---

### Vector 5: Burn Arbitrage (Market Price vs. Redemption Value)

**Hypothesis:** If DGNRS trades on a secondary market below its burn redemption value, an arbitrageur can buy cheap DGNRS and burn it for the higher underlying value, extracting profit at the protocol's expense.

**Attack Path:**

1. DGNRS burn redemption value = R ETH per token (calculated from `StakedDegenerusStonk.sol:391` as `totalMoney / totalSupply`)
2. DGNRS market price on DEX = P ETH per token, where P < R
3. Arbitrageur buys N DGNRS on DEX for `N * P` ETH
4. Arbitrageur calls `DegenerusStonk.sol:153` -- `burn(N)`
5. Burns through to `StakedDegenerusStonk.sol:379` -- `burn(N)`
6. Receives `N * R` worth of ETH + stETH + BURNIE
7. Profit: `N * (R - P)` minus gas and DEX fees

**Economic Analysis:**

This is **intentional market behavior**, not an exploit. The analysis:

1. The arbitrageur receives exactly `(totalMoney * N) / totalSupply` -- their **proportional share** of reserves. No more, no less.
2. Burn redemption creates a **price floor** at `totalMoney / totalSupply`. If market price drops below this, rational actors buy and burn until the price converges.
3. The protocol is NOT drained beyond what the burner is entitled to. Each DGNRS token represents exactly `1 / totalSupply` of the reserves. Burning redeems that share.
4. After the burn, `totalSupply` decreases and reserves decrease proportionally. Remaining holders' per-token value is **unchanged**.

For concrete numbers:
- Total reserves: 1000 ETH. Total supply: 10,000 tokens. Redemption value: 0.1 ETH/token.
- Arbitrageur buys 100 tokens at 0.08 ETH/token on DEX. Cost: 8 ETH.
- Burns 100 tokens. Receives: `(1000 * 100) / 10000 = 10 ETH`
- Profit: 2 ETH.
- Post-burn: 990 ETH / 9900 tokens = 0.1 ETH/token. **Other holders unaffected.**

The arbitrageur's profit comes from the DEX seller who underpriced their tokens, not from the protocol or other holders.

**Prerequisites:** DGNRS must trade on a secondary market below redemption value (external market condition).

**Verdict:** SAFE

Burn arbitrage is intended economic behavior. It maintains the price floor by ensuring DGNRS never sustainably trades below its redemption value. The proportional formula guarantees that each burn redeems exactly the burner's share -- no more than they are entitled to. Other holders' per-token value remains unchanged after the arbitrage burn.

**Evidence:**
- `StakedDegenerusStonk.sol:391` -- `totalValueOwed = (totalMoney * amount) / supplyBefore` (exact proportional)
- `StakedDegenerusStonk.sol:398-400` -- supply reduction matches payout, maintaining ratio for remaining holders
- `DegenerusStonk.sol:153-170` -- burn-through is public, enabling market arbitrage

**Mitigation Status:** No mitigation needed. This is a designed feature: the burn-redeem floor is a fundamental property of the token's value proposition.

---

## NOVEL-12: DGNRS as Attack Amplifier

This section analyzes what attack strategies are NOW POSSIBLE with transferable DGNRS that were IMPOSSIBLE when the token was soulbound. The sDGNRS/DGNRS split changed the 20% creator allocation from soulbound to freely transferable, creating new interaction surfaces.

### Amplifier 1: Flash Loan DGNRS

**Pre-Split Impossibility:** When DGNRS was soulbound (no transfer function), it could not be deposited into a lending pool, and therefore could not be flash-loaned. Flash loan attacks on DGNRS burn were impossible because the attacker could not borrow tokens they did not already own.

**Post-Split Attack Path:**

1. DGNRS is listed on a lending protocol that supports flash loans (e.g., Aave, dYdX)
2. Attacker flash-loans N DGNRS tokens
3. Attacker calls `DegenerusStonk.sol:153` -- `burn(N)` to claim proportional reserves
4. `DegenerusStonk.sol:154` -- `_burn(msg.sender, amount)` permanently destroys the N tokens
5. `DegenerusStonk.sol:202-210` -- `_burn()` reduces `balanceOf[attacker]` and `totalSupply`
6. Attacker receives ETH + stETH + BURNIE
7. **BLOCKED at step 7:** Attacker must repay N DGNRS tokens to the flash loan pool
8. The N tokens were **destroyed** in step 4 -- they no longer exist. `totalSupply` has decreased by N.
9. There is no `mint()` function in `DegenerusStonk.sol` -- new DGNRS tokens cannot be created
10. Flash loan repayment fails. Transaction reverts. All state changes (including the burn) are rolled back.

**Economic Viability:**

Flash loan + burn is **self-defeating** because burn is a destructive operation. The flash-loaned tokens are the attacker's only asset, and burning destroys them. The flash loan protocol requires repayment of the exact borrowed amount (plus fee) at the end of the transaction. Since the tokens are gone and cannot be re-minted, the repayment always fails.

The only path to repay would be to buy N replacement DGNRS tokens within the same transaction (from a DEX), which costs at least `N * redemption_value` -- exactly what the burn payout is worth. Net profit: 0 minus gas and flash loan fee.

```
Cost: flash_loan_fee + (N * market_price_to_replace_tokens)
Revenue: (totalMoney * N) / totalSupply  [from burn]
Net: (totalMoney * N / totalSupply) - N * market_price - flash_loan_fee
```
Since `market_price >= redemption_value = totalMoney / totalSupply` (floor property from Vector 5), net is always <= -flash_loan_fee.

**Verdict:** SAFE

Flash loan DGNRS for burn is impossible because burn destroys the collateral needed for flash loan repayment. There is no `mint()` function in `DegenerusStonk.sol` to create replacement tokens. The transaction always reverts when the flash loan pool attempts to reclaim the destroyed tokens.

**Evidence:**
- `DegenerusStonk.sol:153-154` -- `burn()` calls `_burn(msg.sender, amount)` destroying tokens permanently
- `DegenerusStonk.sol:202-210` -- `_burn()` reduces `balanceOf` and `totalSupply` with no inverse operation
- `DegenerusStonk.sol` -- **no `mint()` function exists** in the entire contract (search confirms: only constructor sets initial supply via `balanceOf[CREATOR] = deposited`)
- `DegenerusStonk.sol:79-85` -- constructor sets supply from sDGNRS balance, no subsequent minting

**Mitigation Status:** Already mitigated by design. The absence of a `mint()` function and the destructive nature of `burn()` make flash loan attacks self-defeating.

---

### Amplifier 2: DGNRS as Lending Collateral

**Pre-Split Impossibility:** Soulbound tokens cannot be posted as collateral in lending protocols. The transfer function required by `ERC20.transferFrom()` (which lending protocols use to seize collateral during liquidation) did not exist.

**Post-Split Attack Path:**

1. DGNRS is listed on Aave/Compound as collateral
2. User deposits DGNRS, borrows ETH/USDC against it
3. If DGNRS price drops, the lending protocol liquidates by selling the user's DGNRS
4. Liquidator receives DGNRS below market value
5. Liquidator can burn DGNRS for the guaranteed redemption floor value

**Detailed trace:**
- `DegenerusStonk.sol:113-122` -- `transferFrom()` enables lending protocol to seize collateral
- `DegenerusStonk.sol:128-132` -- `approve()` enables user to authorize lending protocol
- After liquidation, liquidator calls `DegenerusStonk.sol:153` -- `burn()` for guaranteed floor value

**Economic Viability:**

This is **standard DeFi composability**, not a protocol exploit:

1. All risk is between the borrower and the lending protocol. The DGNRS protocol is not affected.
2. DGNRS burn-redeem floor provides a **hard minimum value** for collateral, which is actually beneficial for lenders -- they know the collateral has intrinsic value.
3. The DGNRS protocol does not lose funds. Burns always pay exactly the proportional share.
4. Liquidation cascades (mass selling of DGNRS) could temporarily depress DEX price below redemption value, triggering arbitrage burns (Vector 5) -- but this is self-correcting market behavior.

Risk allocation:
- Borrower: standard liquidation risk
- Lending protocol: standard bad debt risk (mitigated by DGNRS floor value)
- DGNRS protocol: **zero additional risk** -- burns always pay proportional share

**Verdict:** OUT_OF_SCOPE

External lending protocol integration risk is not a DGNRS protocol vulnerability. The DGNRS protocol is unaffected by how third parties use the token as collateral. The burn-redeem floor actually makes DGNRS safer collateral than most tokens.

**Evidence:**
- `DegenerusStonk.sol:113-122` -- `transferFrom()` (standard ERC20, enables external protocol interaction)
- `DegenerusStonk.sol:128-132` -- `approve()` (standard ERC20)
- `StakedDegenerusStonk.sol:391` -- proportional formula provides floor value
- No state in sDGNRS or DGNRS is affected by external lending protocol operations

**Mitigation Status:** Out of protocol scope. No protocol-level mitigation needed.

---

### Amplifier 3: Accumulation Attack (Market Buy + Burn)

**Pre-Split Impossibility:** When DGNRS was soulbound, no one could buy tokens on a secondary market to accumulate a burn position. The only way to hold DGNRS/sDGNRS was to receive it directly from the protocol (game rewards, creator allocation).

**Post-Split Attack Path:**

1. Attacker identifies that DGNRS market price < burn redemption value
2. Attacker buys large amounts of DGNRS on DEX via `DegenerusStonk.sol:101` -- `transfer()` (received from sellers)
3. Attacker accumulates X% of total supply
4. Attacker calls `DegenerusStonk.sol:153` -- `burn(accumulated_amount)`
5. Burns through to `StakedDegenerusStonk.sol:379` -- `burn(accumulated_amount)`
6. At `StakedDegenerusStonk.sol:391`: `totalValueOwed = (totalMoney * accumulated_amount) / supplyBefore`
7. Attacker receives exactly their proportional share -- **no amplification effect**

**Economic Viability:**

The burn formula at `StakedDegenerusStonk.sol:389-396` gives each burner exactly their proportional share:
```
ethOut + stethOut = (totalMoney * amount) / supplyBefore
burnieOut         = (totalBurnie * amount) / supplyBefore
```

There is no way to get MORE than proportional. The formula is linear in `amount` -- doubling the burn amount doubles the payout. There is no bonus for large burns, no threshold effect, no concentration premium.

Accumulation and burning is just **arbitrage maintaining the price floor**:
- If market_price < redemption_value: buy and burn for profit (profit comes from underpricing sellers, not the protocol)
- If market_price >= redemption_value: no arbitrage opportunity exists
- After each burn: `totalMoney / totalSupply` ratio remains unchanged for remaining holders

For concrete numbers:
- Reserves: 1000 ETH, Supply: 10,000 tokens, Redemption: 0.1 ETH/token
- Attacker buys 5,000 tokens at 0.09 ETH each (cost: 450 ETH)
- Burns 5,000 tokens: receives `(1000 * 5000) / 10000 = 500 ETH`
- Profit: 50 ETH (from the DEX sellers who sold below redemption value)
- Post-burn: 500 ETH / 5,000 tokens = 0.1 ETH/token. **Remaining holders unaffected.**

**Verdict:** SAFE

Accumulation and burning is intended behavior, not an attack. The proportional formula at `StakedDegenerusStonk.sol:391` ensures no amount of accumulation can extract more than the proportional share. There is no concentration premium, no threshold bonus, and no amplification effect. This is rational arbitrage that maintains the token's price floor.

**Evidence:**
- `StakedDegenerusStonk.sol:391` -- `totalValueOwed = (totalMoney * amount) / supplyBefore` (linear, proportional)
- `StakedDegenerusStonk.sol:396` -- `burnieOut = (totalBurnie * amount) / supplyBefore` (same linear formula)
- `StakedDegenerusStonk.sol:398-400` -- supply and balance reduced atomically, maintaining ratio for remaining holders
- `DegenerusStonk.sol:190-200` -- standard `_transfer()` enables accumulation (intended ERC20 behavior)

**Mitigation Status:** No mitigation needed. This is designed behavior -- the price floor is a feature.

---

### Amplifier 4: DGNRS Transfer to Grief Other Players

**Pre-Split Impossibility:** When DGNRS was soulbound, tokens could not be transferred at all. There was no way to send tokens to another address, whether intentionally or accidentally.

**Post-Split Attack Path:**

1. Attacker transfers DGNRS to another address via `DegenerusStonk.sol:101` -- `transfer(to, amount)`
2. `DegenerusStonk.sol:190-200` -- `_transfer()` moves DGNRS balance from sender to recipient
3. Question: does this create any state inconsistency in sDGNRS?

**State consistency analysis:**

- DGNRS.transfer() only modifies `DegenerusStonk.sol:64` -- `mapping(address => uint256) balanceOf` for DGNRS
- sDGNRS balances are **not affected** -- `StakedDegenerusStonk.sol:126` -- `mapping(address => uint256) balanceOf` is a separate mapping in a separate contract
- `sDGNRS.balanceOf[DGNRS_contract_address]` stays the same because DGNRS.transfer() does not call any sDGNRS function
- The cross-contract supply invariant `sDGNRS.balanceOf[DGNRS] >= DGNRS.totalSupply` is preserved because `DGNRS.totalSupply` does not change on transfer (only on burn)
- `DGNRS.totalSupply` changes only in `DegenerusStonk.sol:207` -- `totalSupply -= amount` (inside `_burn()`), never in `_transfer()`

**Griefing vectors from transfers:**

1. **Transfer to self (`transfer(msg.sender, amount)`):** Works normally -- moves tokens from sender to sender (no-op in effect). No state inconsistency.

2. **Transfer to DGNRS contract (`transfer(DGNRS_address, amount)`):** This is the DELTA-L-01 finding already documented in KNOWN-ISSUES.md. The tokens end up in `balanceOf[DGNRS_contract]` but the DGNRS contract has no function to recover them. They are permanently locked. This is standard ERC20 behavior (same as sending tokens to any non-recovering contract).

3. **Transfer to sDGNRS contract (`transfer(sDGNRS_address, amount)`):** Tokens would be locked in sDGNRS's `DegenerusStonk.balanceOf[sDGNRS_address]`, which is tracked in the DGNRS contract, not sDGNRS. The sDGNRS contract cannot call DGNRS functions to recover them. Again, permanently locked -- standard ERC20 behavior.

4. **Dust transfers (many small transfers to bloat state):** Standard ERC20 concern. `DegenerusStonk.sol:190-200` has no minimum transfer amount. However, this only affects the DGNRS state (balance mapping), not protocol functionality. Gas cost of dust transfers is borne by the attacker.

**DELTA-L-01 confirmation:** The only griefing vector unique to the transfer functionality is DELTA-L-01 (transfer-to-self or transfer-to-DGNRS-contract locks tokens). This is already documented in KNOWN-ISSUES.md as acknowledged, low severity.

**Verdict:** SAFE

DGNRS transfers do not create state inconsistency in the sDGNRS system. The cross-contract supply invariant holds because `DGNRS.totalSupply` is not modified by `transfer()`. The only griefing vector is DELTA-L-01 (token locking via transfer to contract addresses), which is already documented and acknowledged as standard ERC20 behavior with low severity.

**Evidence:**
- `DegenerusStonk.sol:190-200` -- `_transfer()` only modifies DGNRS `balanceOf` mapping
- `DegenerusStonk.sol:207` -- `totalSupply` only changes in `_burn()`, not `_transfer()`
- `StakedDegenerusStonk.sol:126` -- `balanceOf` is a separate mapping in a separate contract
- KNOWN-ISSUES.md: DELTA-L-01 (DGNRS transfer-to-self token lock) already documented

**Mitigation Status:** DELTA-L-01 is acknowledged in KNOWN-ISSUES.md. No additional mitigation needed.

---

### Overall Assessment

DGNRS transferability does NOT create protocol-level exploits. The proportional burn-redeem formula at `StakedDegenerusStonk.sol:391` is the key defense -- no matter how tokens are accumulated, flash-loaned, transferred, or used as collateral, each token redeems for exactly `1 / totalSupply` of reserves. This linear, proportional relationship eliminates all concentration premiums, amplification effects, and timing-based extraction opportunities.

The four amplifier scenarios reveal that while transferability enables new DeFi interactions (DEX trading, lending, flash loans), none of these create extractable value from the protocol itself. Flash loans are self-defeating because burn destroys the loan collateral. Lending integration puts risk on external protocols, not DGNRS. Accumulation is rational arbitrage maintaining the price floor. Transfers do not affect sDGNRS state.

The single pre-existing griefing vector (DELTA-L-01) is the only transfer-related concern, and it is already documented as low severity in KNOWN-ISSUES.md.

---

## Summary Table

| # | Vector | Category | Verdict | Severity | Key Defense |
|---|--------|----------|---------|----------|-------------|
| 1 | Flash Loan + Reserve Inflation | NOVEL-01: Economic | SAFE | N/A | `onlyGame` blocks all deposit paths to sDGNRS reserves |
| 2 | Selfdestruct / Force-Send ETH | NOVEL-01: Economic | SAFE | N/A | Proportional formula makes forced ETH a donation, not an exploit |
| 3 | MEV Sandwich on Burns | NOVEL-01: Economic | SAFE | N/A | Proportional formula is order-independent; burn ordering does not change payouts |
| 4 | MEV Sandwich on DEX Trades | NOVEL-01: Economic | OUT_OF_SCOPE | N/A | Standard AMM MEV; protocol has no DEX integration |
| 5 | Burn Arbitrage (Price < Redemption) | NOVEL-01: Economic | SAFE | N/A | Intentional price floor behavior; burner gets exactly proportional share |
| 6 | Flash Loan DGNRS for Burn | NOVEL-12: Amplifier | SAFE | N/A | Burn destroys tokens needed for flash loan repayment; no mint function |
| 7 | DGNRS as Lending Collateral | NOVEL-12: Amplifier | OUT_OF_SCOPE | N/A | External lending risk; protocol unaffected by third-party collateral use |
| 8 | Accumulation Attack (Buy + Burn) | NOVEL-12: Amplifier | SAFE | N/A | Proportional formula has no concentration premium; accumulation = arbitrage |
| 9 | DGNRS Transfer to Grief | NOVEL-12: Amplifier | SAFE | Low (DELTA-L-01) | Transfer does not affect sDGNRS state; only DELTA-L-01 token lock is griefing vector |

**Overall Verdict:** All 9 vectors are SAFE or OUT_OF_SCOPE. Zero Critical, High, or Medium findings. One pre-existing Low (DELTA-L-01) is already documented. The proportional burn-redeem formula is the fundamental defense across all attack categories.
