# ADVR-04 Findings: Delegatecall Reentrancy

**Warden:** "Reentrancy Specialist" (cross-function reentrancy persona)
**Brief:** Prove CEI-safety can be bypassed through cross-function reentrancy
**Scope:** All 8 `.call{value:}` ETH transfer sites, delegatecall module interactions
**Information:** Full prior audit results (v1.0 + v2.0)
**Session Date:** 2026-03-05

## Summary

**Result: No Medium+ findings discovered.**

After constructing a complete reentrancy matrix covering all 8 ETH transfer sites and all possible re-entry functions, no exploitable reentrancy path was found. Every transfer site has either (a) state fully committed before the external call (CEI), (b) a sentinel/flag that blocks re-entry to the same function, or (c) the recipient is a compile-time constant with known behavior.

## Methodology

1. Enumerated all `.call{value:}` sites in the protocol
2. For each site: identified the state at the moment of the external call
3. For each site: identified all possible re-entry points on DegenerusGame
4. For each (site, re-entry) pair: analyzed whether stale state could be exploited
5. Verified stETH is ERC20 (not ERC777) -- no transfer hooks
6. Analyzed delegatecall self-call patterns (module -> Game -> module)

## Reentrancy Matrix

### Site 1: _payoutWithStethFallback -- ETH send (DegenerusGame.sol:2022)

**Called from:** `_claimWinningsInternal()`, `refundDeityPass()`

**State at call (claimWinnings path):**
- `claimableWinnings[player] = 1` (sentinel set)
- `claimablePool -= payout` (decremented)
- ETH balance reduced by ethSend

| Re-entry Target | Stale State? | Exploitable? | Defense |
|-----------------|-------------|--------------|---------|
| claimWinnings() | claimableWinnings[player] = 1 | NO | `amount <= 1` reverts |
| purchase() | nextPrizePool, futurePrizePool unchanged | NO | Purchase reads msg.value, not balance. No stale state read. |
| refundDeityPass() | deityPassRefundable unchanged | NO | Different accounting (pools, not claimable). Independent. |
| advanceGame() | No relevant state modified | NO | advanceGame does not read claimableWinnings or claimablePool during processing |
| placeFullTicketBets() | claimableWinnings[player] = 1 | NO | If using claimable: amount=1, `amount <= 1` blocks spending. If using msg.value: independent. |

**State at call (refundDeityPass path):**
- `deityPassRefundable[buyer] = 0` (zeroed)
- `deityPassPaidTotal[buyer] = 0` (zeroed)
- futurePrizePool/nextPrizePool decremented

| Re-entry Target | Stale State? | Exploitable? | Defense |
|-----------------|-------------|--------------|---------|
| refundDeityPass() | deityPassRefundable = 0 | NO | `refundAmount == 0` reverts |
| claimWinnings() | claimableWinnings unchanged | NO | Independent accounting, no stale state |
| purchase() | Pool values decremented | NO | Purchase adds to pools, doesn't read them for validation |

### Site 2: _payoutWithStethFallback -- leftover retry (DegenerusGame.sol:2039)

Same function, second `.call{value:}`. Only reached if stETH was insufficient for remainder.

**State at call:** Same as Site 1 plus stETH already transferred. No additional state mutations between the two calls. Same reentrancy analysis applies.

### Site 3: _payoutWithEthFallback (DegenerusGame.sol:2060)

**Called from:** `claimWinningsStethFirst()` (VAULT and DGNRS only)

**Recipient:** `ContractAddresses.VAULT` or `ContractAddresses.DGNRS` -- compile-time constants.

| Re-entry Target | Exploitable? | Defense |
|-----------------|--------------|---------|
| Any function | NO | VAULT is DegenerusVault contract. DGNRS is DegenerusStonk contract. Neither has a receive() that calls back into Game. Even if they did: claimableWinnings[player] = 1, same sentinel defense. |

**Defense:** Recipient is a known contract with known receive() behavior. Compile-time constant address cannot be changed to attacker contract.

### Site 4: MintModule vault share (MintModule.sol:737)

```solidity
(bool ok, ) = payable(ContractAddresses.VAULT).call{value: vaultShare}("");
```

**Recipient:** `ContractAddresses.VAULT` -- compile-time constant.

**State at call:** Inside purchase flow (delegatecall context). vaultShare computed from lootbox split. Pool accounting for the purchase is partially complete.

| Re-entry Target | Exploitable? | Defense |
|-----------------|--------------|---------|
| Any function | NO | Recipient is VAULT (known contract). Not attacker-controllable. |

### Sites 5-6: GameOverModule._sendToVault (GameOverModule.sol:199, 216)

```solidity
(bool ok, ) = payable(ContractAddresses.VAULT).call{value: ethAmount}("");
(bool ok, ) = payable(ContractAddresses.DGNRS).call{value: ethAmount}("");
```

**Recipients:** VAULT and DGNRS -- compile-time constants.

**State at call:** `gameOverFinalJackpotPaid = true`, `gameOver = true`, `gameOverTime` set.

| Re-entry Target | Exploitable? | Defense |
|-----------------|--------------|---------|
| handleGameOverDrain() | gameOverFinalJackpotPaid = true | NO | Early return on line 62 |
| claimWinnings() | Independent | NO | claimWinnings reads own mapping, unaffected |
| purchase() | gameOver = true | NO | Most functions check gameOver state |

**Defense:** Known recipients + idempotent guard.

### Site 7: DegenerusVault withdraw (DegenerusVault.sol:1038)

```solidity
(bool ok, ) = to.call{value: amount}("");
```

**State at call:** Shares burned, balance accounting updated.

This is in the Vault contract, not the Game. A vault withdraw callback cannot re-enter Game in a harmful way because:
- Vault accounting is independent of Game accounting
- Game's claimablePool/claimableWinnings are not read or modified by Vault operations

### Site 8: DegenerusStonk (DegenerusStonk.sol:818)

```solidity
(bool success, ) = player.call{value: ethOut}("");
```

**Recipient:** Player address (attacker-controllable).

**State at call:** Inside DegenerusStonk.sell(). This is a separate contract from Game.

| Re-entry Target | Exploitable? | Defense |
|-----------------|--------------|---------|
| DegenerusStonk.buy() | Price based on supply, shares already burned | Potential concern but independent of Game |
| Game.claimWinnings() | Independent contract | NO | No shared state with Stonk |

**Defense:** DegenerusStonk is isolated from Game's ETH accounting. Reentrancy within Stonk: shares are burned before ETH transfer (CEI).

## DegeneretteModule: No ETH Transfer Sites

DegeneretteModule has zero `.call{value:}` calls. All payouts go through the pull pattern: `_addClaimableEth()` credits to `claimableWinnings`, players claim later via `claimWinnings()`. No reentrancy vector.

## Delegatecall Self-Call Analysis (Vector H)

Several modules make calls back to Game via `IDegenerusGame(address(this)).someFunction()`:

1. **GameOverModule.handleGameOverDrain:**
   - `IDegenerusGame(address(this)).runDecimatorJackpot(...)` -- calls Game, which delegatecalls to DecimatorModule
   - `IDegenerusGame(address(this)).runTerminalJackpot(...)` -- calls Game, which delegatecalls to JackpotModule

2. **EndgameModule.runRewardJackpots:**
   - `IDegenerusGame(address(this)).runDecimatorJackpot(...)` -- same pattern

These are CALL to self (not delegatecall), which then delegatecall to the target module. This creates a nested execution context:

```
GameOverModule (delegatecall) -> Game (CALL to self) -> DecimatorModule (delegatecall)
```

**Is this re-entrant?** Technically yes -- the outer delegatecall is still on the stack when the inner delegatecall executes. Both share Game's storage.

**Can this be exploited?**

Analyzed the state at each self-call point:

1. **handleGameOverDrain -> runDecimatorJackpot:**
   - State before: `gameOverFinalJackpotPaid = true` (line 122)
   - runDecimatorJackpot reads/writes: `lastDecClaimRound`, `decBucketBurnTotal`, `decBucketOffsetPacked`
   - These are independent of the outer function's state modifications (deity refunds, gameOver flag)
   - **SAFE:** No conflicting state reads/writes

2. **handleGameOverDrain -> runTerminalJackpot:**
   - State before: gameOverFinalJackpotPaid = true, claimablePool updated for deity refunds and decimator
   - runTerminalJackpot reads claimablePool (indirectly via _addClaimableEth)
   - **BUT:** runTerminalJackpot ADDS to claimablePool (line 1564). claimablePool was correctly updated before this call.
   - **SAFE:** Sequential, non-conflicting updates

3. **runRewardJackpots -> runDecimatorJackpot:**
   - State before: local variables only (futurePoolLocal, claimableDelta)
   - Storage writes happen AFTER the self-call returns (lines 198-203)
   - **Wait -- is futurePoolLocal stale?** No. The Decimator call returns `returnWei`. The caller computes `spend = decPoolWei - returnWei` and adjusts `futurePoolLocal` locally. The SSTORE happens after.
   - **SAFE:** Local variable pattern prevents stale storage reads

## stETH ERC777 Check (Vector G)

Lido stETH (0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) is a standard ERC20 rebase token. It does NOT implement ERC777 hooks (`tokensReceived`, `tokensToSend`). Confirmed:
- No `IERC1820Registry` interaction
- No `tokensReceived` callback on transfer
- Standard `transfer()` and `transferFrom()` without hooks

stETH transfers in `_payoutWithStethFallback()` and `_payoutWithEthFallback()` cannot trigger callbacks.

## Conclusion

No reentrancy vulnerability found. The protocol defends against cross-function reentrancy through multiple layers:

1. **Sentinel pattern:** `claimableWinnings[player] = 1` before any ETH transfer blocks re-entry to claim functions
2. **CEI pattern:** All state updates (zeroing, decrementing) occur before external calls
3. **Compile-time recipients:** 5 of 8 transfer sites send to known contract addresses (VAULT, DGNRS) that cannot be changed to attacker contracts
4. **Idempotent guards:** `gameOverFinalJackpotPaid` prevents re-processing
5. **No ERC777 hooks:** stETH is standard ERC20, no transfer callbacks
6. **Pull pattern:** DegeneretteModule and all jackpot distributions use credit-then-claim, never push ETH during processing

The delegatecall self-call pattern (module -> Game -> module) creates nested execution but does not create exploitable reentrancy because state updates are either completed before the self-call or use local variable patterns that prevent stale storage reads.
