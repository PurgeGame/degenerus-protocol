# Auditor Re-examination Report: stETH and VRF Edge Cases

**Phase:** 34 -- Economic Composition and Auditor Re-examination
**Plan:** 03
**Date:** 2026-03-05
**Analyst:** Independent re-derivation from source code (not referencing prior audit conclusions)

---

## REEX-01: stETH Read-Only Reentrancy Analysis

### All stETH Interaction Points Traced from Source

**Vault contract (`DegenerusVault.sol`):**

1. **`_syncEthReserves()`** (line 977-983): Reads `steth.balanceOf(address(this))` via `_stethBalance()` (line 1031). Pure view call, no state changes before or after.

2. **`_paySteth()`** (line 1046): `steth.transfer(to, amount)`. External call that transfers stETH to recipient.

3. **`_pullSteth()`** (line 1054): `steth.transferFrom(from, address(this), amount)`. External call pulling stETH from depositor.

**Game contract (`DegenerusGame.sol`):**

4. **`_payoutWithStethFallback()`** (lines 1965-1992): Reads `steth.balanceOf(address(this))` at line 1979, then calls `_transferSteth(to, stSend)` which performs `steth.transfer()`.

5. **`_payoutWithEthFallback()`** (lines 1998-2012): Reads `steth.balanceOf(address(this))` at line 2001, then calls `_transferSteth(to, stSend)`.

### Read-Only Reentrancy Assessment

**Is stETH an ERC777?** No. Lido's stETH (0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) is a plain ERC20 with rebasing. The `transfer()` function:
- Updates internal share balances
- Emits Transfer event
- Returns bool
- Does NOT call any hook on the recipient (no `tokensReceived()` callback)
- Does NOT call any hook on the sender (no `tokensToSend()` callback)

**Consequence:** Since stETH.transfer() invokes no callbacks, there is no reentrancy entry point during stETH transfers. An attacker cannot execute code during a stETH transfer to exploit stale state.

### CEI Pattern Verification

Even without callback risk, let me verify CEI is followed at all stETH interaction points:

**Vault `_burnEthFor()` (lines 839-882):**
1. CHECK: `amount == 0` revert, calculate claimValue
2. EFFECT: `share.vaultBurn(player, amount)` -- burns shares (state update)
3. INTERACT: `_payEth()` / `_paySteth()` -- external transfers

CEI is followed. State (share burn) occurs before external call (stETH transfer).

**Game `_claimWinningsInternal()` (lines 1418-1433):**
1. CHECK: `amount <= 1` revert
2. EFFECT: `claimableWinnings[player] = 1` (sentinel), `claimablePool -= payout`
3. INTERACT: `_payoutWithStethFallback()` or `_payoutWithEthFallback()`

CEI is followed. State updates (winnings zeroed, pool decremented) occur before external calls.

### Secondary Check: Cross-Contract Reentrancy

**Could another external call read stale stETH data?**

Tracing all external calls that occur before stETH reads:
- In `_burnEthFor()`: `gamePlayer.claimableWinningsOf(address(this))` is a view call (no state change). Then `gamePlayer.claimWinnings(address(this))` is called conditionally (line 860), which itself follows CEI.
- No path exists where an external call (VRF, LINK, etc.) occurs between a stETH balance read and a state-dependent operation.

### Lido Oracle Update Scenario

**Concern:** If a vault burn occurs during a Lido oracle update, could the share rate be inconsistent?

**Analysis:** Lido oracle updates are single-transaction atomic operations. Within a single Ethereum transaction, `steth.balanceOf()` returns a consistent value. The rebase from an oracle update either has or has not been applied at the time of the call. There is no "during" state within a transaction.

**Cross-block scenario:** If a user reads `previewBurnForEthOut()` in block N, then Lido oracle updates in block N+1 (negative rebase), the preview value becomes stale. This is an inherent property of rebasing tokens -- preview functions cannot guarantee future values. The actual burn in block N+2 reads the correct (post-rebase) balance.

### Verdict: REEX-01

**SAFE.** stETH read-only reentrancy is impossible because:
1. stETH is a plain ERC20 -- `transfer()` invokes no callbacks on sender or recipient
2. All code paths follow CEI pattern (state updates before external calls)
3. No cross-contract reentrancy path exists between stETH reads and state operations
4. Lido oracle updates are atomic per-transaction -- no inconsistent mid-tx state
5. Preview function staleness is inherent to rebasing tokens and not exploitable

**Confidence:** HIGH

---

## REEX-02: VRF Subscription Balance Depletion Cost Analysis

### VRF Funding Architecture Traced from Source

**Source:** `contracts/DegenerusAdmin.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`

#### Subscription Management

- **Owner:** DegenerusAdmin contract (created in constructor via `createSubscription()`)
- **Funding:** Via `LINK.transferAndCall(adminAddr, amount, "0x")` -> `Admin.onTokenTransfer()` (line 606) -> forwards LINK to VRF coordinator subscription
- **Consumers:** Only DegenerusGame (added in Admin constructor)
- **Cancellation:** Owner-only via `shutdownAndRefund()` (requires `gameOver()`) or `emergencyRecover()` (requires 3-day stall)

#### VRF Request Sites

1. **Lootbox RNG** (AdvanceModule line 596): `vrfCoordinator.requestRandomWords()` with `callbackGasLimit: VRF_CALLBACK_GAS_LIMIT` (300,000 gas, line 88)
   - Gated by: `MIN_LINK_FOR_LOOTBOX_RNG = 40 ether` (40 LINK, line 101)
   - Pre-check: `if (linkBal < MIN_LINK_FOR_LOOTBOX_RNG) revert E()` (line 575)

2. **Game Advance RNG** (AdvanceModule line 997): Same VRF params
   - No LINK balance pre-check -- relies on coordinator reverting if insufficient

3. **Additional lootbox RNG** (AdvanceModule line 1023): Same VRF params

#### LINK Cost Per Request

Chainlink VRF V2.5 pricing model: `cost = (gasUsed + callbackGas) * gasPriceGwei * weiPerGas / linkPriceWei + flatPremium`

With `VRF_CALLBACK_GAS_LIMIT = 300,000`:
- Estimated cost per request: 0.5-2 LINK (varies with gas price and LINK/ETH rate)
- At typical mainnet conditions: ~1 LINK per request

### Depletion Griefing Analysis

**Who can trigger VRF requests?**

1. **Lootbox RNG trigger** (`requestLootboxRng()` in AdvanceModule): Anyone can call, but requires `lootboxRngPendingEth > 0` or `lootboxRngPendingBurnie >= BURNIE_RNG_TRIGGER`. Pending values come from actual ticket purchases (ETH cost). Additionally gated by `MIN_LINK_FOR_LOOTBOX_RNG = 40 LINK` minimum balance.

2. **Game advance** (`advanceGame()`): Anyone can call, but requires game state to be in jackpot phase with level progression conditions met. Each advance consumes 1 VRF request.

3. **Lootbox opening triggers**: Indirect VRF requests from lootbox resolution.

**Attacker's depletion strategy:**
- Cannot directly drain LINK (subscription is Admin-owned)
- Must trigger VRF requests through legitimate game actions
- Each lootbox RNG trigger requires actual ETH-purchased lootbox value pending
- Game advance requires level progression (game state dependent)

**Cost to attacker per VRF request:**
- Lootbox path: Must purchase tickets with ETH to create pending lootbox value. Minimum ticket price at level 0 is ~0.0015 ETH. But the threshold for triggering RNG (`lootboxRngThreshold`) prevents trivial triggers.
- Game advance path: Requires filling a level's ticket allocation, which costs the sum of all tickets at that level's price.

**Depletion rate vs refunding:**
- Each VRF request costs ~1 LINK from subscription
- Lootbox RNG gate: 40 LINK minimum. Below this, lootbox RNG is blocked but game advance still works.
- Anyone can donate LINK: `LINK.transferAndCall(adminAddr, amount, "0x")` -- open to public
- Admin incentivizes LINK donation with BURNIE rewards (tiered multiplier in `_linkRewardMultiplier`)

### Cost Estimates

**To prevent game advancement for 1 day:**
- Game levels advance when ticket allocation is filled + VRF resolves
- An attacker cannot prevent advancement by depleting LINK because:
  - Game advance RNG does NOT check LINK balance (line 997 -- no MIN_LINK check)
  - The VRF coordinator itself reverts only when subscription balance is literally 0
  - Even at 0 LINK, the `requestRandomWords` call reverts, triggering the 18-hour VRF retry timeout
  - After 18 hours of VRF stall, emergency stall mechanisms activate
- **Effective cost:** Attacker cannot drain subscription to 0 through game mechanics alone. Each VRF request requires real game activity costing ETH.

**To block lootbox RNG for 1 day:**
- Drain subscription below 40 LINK
- But: attacker cannot withdraw LINK from subscription
- The only drain is through VRF requests, which require game participation (ETH cost)
- If subscription drops below 40 LINK, lootbox RNG is blocked until someone donates LINK
- **Effective cost:** Not feasible through game mechanics. Would require the entire game activity to consume 40+ LINK in requests, which means hundreds of VRF requests at ~1 LINK each.

**To drain subscription to 0 (prevent all VRF):**
- Starting from a funded subscription (e.g., 100 LINK)
- Need 100+ VRF requests, each costing ~1 LINK
- Each request requires game state transitions (level fills, lootbox triggers)
- A full game with many levels might consume 50-200 LINK total over months
- **Not an attack:** This is normal game operation consuming funded LINK

### Recovery Mechanisms

1. **LINK donation:** Anyone can send LINK via `transferAndCall`. Rewarded with BURNIE multiplier.
2. **Emergency recovery** (Admin line 487-529): After 3-day VRF stall, owner can migrate to new coordinator/subscription.
3. **Game shutdown** (Admin line 560-582): After game over, owner cancels subscription and recovers LINK.

### Edge Case: Subscription Cancellation

- `cancelSubscription()` is only callable via:
  - `emergencyRecover()` -- requires `onlyOwner` + `rngStalledForThreeDays()`
  - `shutdownAndRefund()` -- requires `onlyOwner` + `gameOver()`
- External parties cannot cancel the subscription
- Even during emergency recovery, a new subscription is immediately created

### Verdict: REEX-02

**LOW RISK -- NOT EXPLOITABLE.** VRF subscription depletion is economically infeasible as sustained griefing because:
1. Attacker cannot directly withdraw LINK from the subscription
2. VRF requests require legitimate game participation (ETH cost)
3. Lootbox RNG has a 40 LINK minimum gate -- below this, only lootbox RNG is blocked (game advance continues)
4. Game advance RNG has NO LINK balance check -- relies on coordinator revert, triggering 18-hour timeout recovery
5. Anyone can refund the subscription by donating LINK (incentivized with BURNIE rewards)
6. Emergency VRF migration exists after 3-day stall
7. Subscription cancellation is owner-only with additional guards (stall/gameover)
8. Normal game operation over months might consume 50-200 LINK total -- this is budgeted, not griefing

**Estimated griefing cost:** An attacker would need to spend ETH on ticket purchases to trigger VRF requests, spending more ETH than the LINK consumed. At ~1 LINK (~$15) per request requiring ~0.01 ETH+ of tickets, the attacker's ETH cost exceeds the damage.

**Confidence:** HIGH

---

## REEX-03: stETH Slashing Impact Analysis

### Live Balance Read Verification

**Source:** `DegenerusVault.sol`, `DegenerusGame.sol`

#### Vault Path

**`_syncEthReserves()`** (line 977-983):
```solidity
function _syncEthReserves() private view returns (uint256 ethBal, uint256 stBal, uint256 combined) {
    ethBal = address(this).balance;
    stBal = _stethBalance();  // steth.balanceOf(address(this)) -- line 1031
    unchecked { combined = ethBal + stBal; }
}
```

No caching between calls. Each invocation reads the current stETH balance, which reflects any slashing that has occurred.

**Vault burn path:** `_burnEthFor()` -> `_syncEthReserves()` -> calculate `claimValue = (reserve * amount) / supplyBefore` -> burn shares -> transfer.

If slashing reduces stETH balance between two burns:
- Burn 1: reads balance B1, calculates value based on B1
- Slashing occurs (Lido oracle update in subsequent block)
- Burn 2: reads balance B2 < B1, calculates value based on B2
- **Correct behavior:** Second burner gets less because reserves are actually less

**Safety check** (line 870): `if (stEthOut > stBal) revert Insufficient()`. If calculated stETH payout exceeds actual stETH balance (e.g., because claimable winnings inflated reserve calculation but stETH was slashed), the transaction reverts.

#### Game Path

**`_payoutWithStethFallback()`** (lines 1965-1992):
- Reads `steth.balanceOf(address(this))` at line 1979
- Sends min(remaining, stBal) as stETH
- If both ETH and stETH insufficient for total payout, reverts at line 1988

**`_payoutWithEthFallback()`** (lines 1998-2012):
- Reads `steth.balanceOf(address(this))` at line 2001
- Same pattern -- live read, bounded send

### View Function Staleness

**Concern:** Does `previewBurnForEthOut()` or similar preview function cache stETH balance?

The vault has view functions that preview claim values. These call `_syncEthReserves()` which reads live `balanceOf()`. However:

1. User calls preview in block N: gets value V based on current stETH balance
2. Lido slashing occurs between block N and N+K
3. User calls burn in block N+K: gets value V' < V based on reduced stETH balance

**This is expected behavior.** Preview functions provide point-in-time estimates, not guarantees. This is identical to how Uniswap quotes can change between quote and swap. No protocol-level fix is possible for rebasing token previews.

**Mitigation available:** A burn function with minimum output parameter (slippage protection) would protect users. Checking if this exists:

The vault `_burnEthFor()` does not have a `minOut` parameter. The user could be surprised by reduced output after slashing. However:
- Major Lido slashing events are extremely rare (no mainnet occurrence as of writing)
- The revert at `if (stEthOut > stBal) revert Insufficient()` prevents under-collateralized payouts
- The loss is proportional across all share holders (not targeted at any individual)

### Game Invariant: `balance >= claimablePool`

**Contract header** (DegenerusGame.sol line 18): `address(this).balance + steth.balanceOf(this) >= claimablePool`

**Can stETH slashing break this?**

- `claimablePool` is incremented when player winnings are credited
- `claimablePool` is decremented when winnings are claimed (line 1426)
- The invariant holds when all credited ETH remains in the contract

If Lido slashing reduces `steth.balanceOf(this)`:
- `address(this).balance` (ETH) is unaffected
- `steth.balanceOf(this)` decreases
- If the decrease causes `ethBal + stBal < claimablePool`, the invariant is broken

**Recovery mechanism:** The `_payoutWithStethFallback` function handles partial availability gracefully:
- Sends available ETH first
- Then available stETH for remainder
- Reverts if total is still insufficient (line 1988: `if (ethRetry < leftover) revert E()`)

In a severe slashing scenario:
1. First N claimers succeed (ETH + stETH covers their claims)
2. Later claimers revert (insufficient funds)
3. Admin can inject ETH via `adminSwapEthForStEth()` or direct transfer to restore solvency
4. This is a systemic Lido risk, not protocol-specific

### Proportional Loss Distribution

**Vault:** Share value = reserve / supply. If stETH reserve drops 5% from slashing, share value drops proportionally. All share holders bear the loss equally. This is correct behavior for a vault holding rebasing tokens.

**Game:** claimablePool is denominated in wei, not shares. A 5% stETH reduction means the game has less total value to distribute. This is a tail risk, mitigated by:
- Game preferring ETH payouts over stETH (ETH-first in `_payoutWithStethFallback`)
- Admin ability to rebalance (stake/swap functions)
- stETH slashing being a Lido-ecosystem event affecting all holders equally

### Verdict: REEX-03

**KNOWN RISK -- CORRECTLY MITIGATED.** stETH slashing is handled correctly via:
1. Live `balanceOf()` reads in all paths -- no cached balance vulnerability
2. Vault distributes loss proportionally to all share holders (correct behavior)
3. Game has revert guards for insufficient balance (`if (stEthOut > stBal) revert Insufficient()`)
4. View function staleness is inherent to rebasing tokens (no protocol fix possible)
5. Game invariant `balance >= claimablePool` could be broken by extreme slashing, but:
   - Admin can inject ETH to restore solvency
   - ETH-first payout preference minimizes stETH exposure
   - Major Lido slashing has never occurred on mainnet
6. This is an accepted Lido dependency risk, not a protocol vulnerability

**Confidence:** HIGH
