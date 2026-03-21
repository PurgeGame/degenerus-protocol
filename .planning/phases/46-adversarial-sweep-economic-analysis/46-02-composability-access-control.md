# Phase 46 Plan 02: Composability Attack Catalog + Access Control Audit
**Date:** 2026-03-21
**Scope:** Cross-contract interaction sequences + 4 new entry points
**Reference:** Phase 44 Plan 03 mapped 26 cross-contract calls

---

## Section 1: Cross-Contract Composability Attack Catalog

### Sequence 1: Burn-then-claim-in-same-tx
**Attack Path:** `sDGNRS.burn()` -> `sDGNRS.claimRedemption()` (same tx via attacker contract)
**Guard Bypass Attempted:** Skip the resolution period to claim immediately after burning
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:438` -- `_submitGamblingClaim(msg.sender, amount)` records claim with `periodIndex = currentPeriod` (line 729)
- `StakedDegenerusStonk.sol:580` -- `if (period.roll == 0) revert NotResolved()` -- the period is unresolved (roll defaults to 0)
- `StakedDegenerusStonk.sol:562-565` -- `resolveRedemptionPeriod` can only be called by `ContractAddresses.GAME` (line 544)
**Detail:** When `burn()` is called during active game, `_submitGamblingClaim` records a pending redemption with the current period's index. The `claimRedemption()` function checks that the period's roll is non-zero (line 580). Since `resolveRedemptionPeriod` can only be called by the game contract via `advanceGame()` (which requires VRF fulfillment in a future transaction), the period cannot be resolved in the same transaction. The call reverts with `NotResolved()`.

### Sequence 2: Flash-loan-burn
**Attack Path:** Flash loan sDGNRS -> `sDGNRS.burn()` -> `sDGNRS.claimRedemption()` -> repay flash loan
**Guard Bypass Attempted:** Borrow sDGNRS, burn for gambling claim, claim immediately, repay
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- sDGNRS is soulbound -- no `transfer()` function exists in `StakedDegenerusStonk.sol` (no ERC20 transfer or transferFrom)
- `StakedDegenerusStonk.sol:57` -- contract declaration, no transfer function in entire contract
- Flash loans require transferability for borrow/repay cycle
**Detail:** sDGNRS tokens are soulbound by design -- the contract has no `transfer()` or `transferFrom()` function. There is only `wrapperTransferTo()` (line 301) restricted to the DGNRS wrapper contract. Flash loans are structurally impossible because the attacker cannot borrow sDGNRS (no lending protocol can hold it, and it cannot be transferred to the attacker). Even if an attacker could somehow obtain sDGNRS, the claim requires a future-transaction resolution (Sequence 1 guard).

### Sequence 3: Re-enter-via-_payEth
**Attack Path:** `sDGNRS.claimRedemption()` -> `_payEth()` -> `player.call{value:}` -> re-enter `claimRedemption()`
**Guard Bypass Attempted:** Re-enter claimRedemption to double-claim ETH
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:599` -- `pendingRedemptionEthValue -= ethPayout` (state update BEFORE external call)
- `StakedDegenerusStonk.sol:601-607` -- if `flipResolved`: `delete pendingRedemptions[player]` (full delete BEFORE external call); else: `claim.ethValueOwed = 0` (clear ETH portion BEFORE external call)
- `StakedDegenerusStonk.sol:610` -- `_payEth(player, ethPayout)` (external call AFTER state updates)
- `StakedDegenerusStonk.sol:577` -- re-entry check: `if (claim.periodIndex == 0) revert NoClaim()` -- after delete, periodIndex is 0
**Detail:** The `claimRedemption` function follows CEI (Checks-Effects-Interactions). The segregated ETH value is decremented at line 599, and the player's claim is either fully deleted (line 603) or has ethValueOwed zeroed (line 606) BEFORE `_payEth` makes the external ETH transfer at line 746. If the player's fallback re-enters `claimRedemption`, either `claim.periodIndex == 0` (NoClaim revert) or `claim.ethValueOwed == 0` (producing ethPayout = 0). No double-claim is possible.

### Sequence 4: Re-enter-via-stETH-fallback
**Attack Path:** `sDGNRS.claimRedemption()` -> `_payEth()` -> `steth.transfer(player, stethOut)` -> re-enter sDGNRS
**Guard Bypass Attempted:** Exploit stETH transfer callback to re-enter sDGNRS during payout
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:755` -- `steth.transfer(player, stethOut)` -- stETH is Lido's ERC20 implementation
- stETH uses standard `_transfer` (internal balance update) with no ERC777-style hooks or callbacks
- Even if a callback existed, CEI protections from Sequence 3 analysis apply: claim data is already deleted/zeroed before `_payEth` is called (lines 599-607)
**Detail:** Lido's stETH is a standard rebasing ERC20. Its `transfer` function performs a balance update via `_transfer` with no receiver callbacks or hooks. There is no ERC777 `tokensReceived` hook, no ERC1363 `onTransferReceived`, and no other callback mechanism. Even if a hypothetical callback existed, the CEI pattern (Sequence 3) ensures claim data is already consumed before any external call.

### Sequence 5: Delegatecall-module-redemption-bypass
**Attack Path:** `DegenerusGame.advanceGame()` -> `delegatecall(AdvanceModule)` -> access sDGNRS storage directly
**Guard Bypass Attempted:** Use delegatecall module context to manipulate sDGNRS storage slots directly
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `DegenerusGame.sol:316-322` -- `ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(...)` -- executes in DegenerusGame's storage context
- `ContractAddresses.sol:28` -- `SDGNRS = address(0x92a6649Fdcc044DA968d94202465578a9371C7b1)` -- separate contract address
- `StakedDegenerusStonk.sol` is deployed at its own address, with its own storage
- `DegenerusGameAdvanceModule.sol:791-794` -- module calls `sdgnrs.resolveRedemptionPeriod()` via external call, not storage access
**Detail:** Delegatecall modules execute in DegenerusGame's storage context, not sDGNRS's. sDGNRS is a separate contract deployed at `0x92a6...7b1`. The AdvanceModule interacts with sDGNRS exclusively through external function calls (`hasPendingRedemptions()` at line 791, `resolveRedemptionPeriod()` at line 794). There is no shared storage layout between DegenerusGame and sDGNRS. A delegatecall module cannot read or write sDGNRS storage slots.

### Sequence 6: Multiple-burn-before-resolution
**Attack Path:** `sDGNRS.burn()` (1st) -> `sDGNRS.burn()` (2nd) in same period before advanceGame resolves
**Guard Bypass Attempted:** Stack multiple burn claims to amplify ETH segregation beyond proportional share
**Tested:** YES
**Outcome:** SAFE (stacking within same period is allowed by design; cross-period stacking is blocked)
**Evidence:**
- `StakedDegenerusStonk.sol:724` -- `if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod)` -- reverts with `UnresolvedClaim` only if previous claim is from a DIFFERENT period
- `StakedDegenerusStonk.sol:727-729` -- same-period burns are ADDED to existing claim: `claim.ethValueOwed += ethValueOwed; claim.burnieOwed += burnieOwed; claim.periodIndex = currentPeriod`
- `StakedDegenerusStonk.sol:691` -- 50% supply cap check: `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient()`
**Detail:** The design intentionally allows a player to burn multiple times within the same period -- the claims are stacked (ethValueOwed and burnieOwed are accumulated). This is safe because: (1) each burn computes a proportional share based on totalSupply at time of burn, (2) the supply decreases with each burn making subsequent burns' proportional share smaller, (3) the 50% supply cap (line 691) limits total burns per period. A cross-period stack attempt (burning in period N, then again in period N+1 without claiming N) is blocked by `UnresolvedClaim` at line 725.

### Sequence 7: AdvanceModule-redemption-skip
**Attack Path:** `DegenerusGame.advanceGame()` -> VRF fulfilled -> `rngGate` skips `resolveRedemptionPeriod`
**Guard Bypass Attempted:** Cause advanceGame to process daily RNG without resolving pending redemptions, leaving claims permanently unresolvable
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `DegenerusGameAdvanceModule.sol:791` -- `if (sdgnrs.hasPendingRedemptions())` -- conditional call only when pending
- `StakedDegenerusStonk.sol:534-536` -- `hasPendingRedemptions()` returns true when `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0`
- `StakedDegenerusStonk.sol:437` -- `if (game.rngLocked()) revert BurnsBlockedDuringRng()` -- no burns can occur between VRF request and fulfillment
- `DegenerusGameAdvanceModule.sol:850-861` -- `_gameOverEntropy` also calls `resolveRedemptionPeriod` (mirrors rngGate)
- `DegenerusGameAdvanceModule.sol:879-890` -- fallback VRF path also calls `resolveRedemptionPeriod`
**Detail:** The `rngGate` function checks `hasPendingRedemptions()` at line 791 and calls `resolveRedemptionPeriod` if true. Since `burn()` reverts with `BurnsBlockedDuringRng` when `rngLocked()` is true (line 437), no new burns can be submitted between VRF request and fulfillment. This means the `hasPendingRedemptions()` state is stable during the rngGate execution window. All three RNG paths (rngGate normal, _gameOverEntropy normal, _gameOverEntropy fallback) include the resolution check. A period's redemptions cannot be skipped.

### Sequence 8: BurnieCoinflip-direct-call
**Attack Path:** External caller -> `BurnieCoinflip.claimCoinflipsForRedemption()` directly
**Guard Bypass Attempted:** Call claimCoinflipsForRedemption to mint BURNIE without going through sDGNRS redemption flow
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `BurnieCoinflip.sol:349` -- `if (msg.sender != ContractAddresses.SDGNRS) revert OnlyStakedDegenerusStonk()`
- `ContractAddresses.sol:28` -- `SDGNRS = address(0x92a6649Fdcc044DA968d94202465578a9371C7b1)` -- immutable compile-time constant
- Only call site: `StakedDegenerusStonk.sol:768` -- `coinflip.claimCoinflipsForRedemption(address(this), remaining)` inside `_payBurnie`
**Detail:** The `claimCoinflipsForRedemption` function has an explicit `msg.sender` check against the immutable `ContractAddresses.SDGNRS` address (line 349). Direct external calls from any address other than the sDGNRS contract revert with `OnlyStakedDegenerusStonk()`. The SDGNRS address is a compile-time constant and cannot be changed at runtime.

### Sequence 9: burnForSdgnrs-direct-call
**Attack Path:** External caller -> `DegenerusStonk.burnForSdgnrs(victim, amount)` directly
**Guard Bypass Attempted:** Burn another player's DGNRS without authorization
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `DegenerusStonk.sol:238` -- `if (msg.sender != ContractAddresses.SDGNRS) revert Unauthorized()`
- `ContractAddresses.sol:28` -- `SDGNRS = address(0x92a6649Fdcc044DA968d94202465578a9371C7b1)` -- immutable compile-time constant
- Only call site: `StakedDegenerusStonk.sol:450` -- `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` inside `burnWrapped`
**Detail:** The `burnForSdgnrs` function checks that `msg.sender` is the sDGNRS contract (line 238). The only call site is in `StakedDegenerusStonk.burnWrapped()` (line 450), which passes `msg.sender` as the player -- meaning only the actual caller's DGNRS can be burned. Direct external calls revert with `Unauthorized()`. The SDGNRS address is immutable.

### Sequence 10: Cross-period-claim-manipulation
**Attack Path:** Player burns in period N -> waits for resolution -> manipulates period N+1 RNG to retroactively improve period N roll
**Guard Bypass Attempted:** Change the roll applied to an already-submitted claim
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:562-565` -- `redemptionPeriods[period] = RedemptionPeriod({roll: roll, flipDay: flipDay})` -- roll is stored at resolution time
- `StakedDegenerusStonk.sol:579-582` -- claim reads `period.roll` from stored resolution: `RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex]; ... uint16 roll = period.roll`
- `DegenerusGameAdvanceModule.sol:792` -- roll computed from VRF word: `uint16((currentWord >> 8) % 151 + 25)` -- range [25, 175]
- VRF word is provided by Chainlink VRF v2 (unpredictable, delivered in a separate tx)
**Detail:** The roll for a period is computed from the VRF random word at resolution time and stored immutably in `redemptionPeriods[period].roll` (line 562). Once stored, subsequent advanceGame calls do not overwrite it (they create new period entries with new indices). The player's claim is locked to `claim.periodIndex` (set at burn time, line 729). The player cannot change which period their claim references, and they cannot change the roll stored for that period. The VRF word is unpredictable (Chainlink VRF v2), so the roll cannot be front-run or manipulated.

### Sequence 11: burnWrapped-delegation-confusion
**Attack Path:** Player calls `sDGNRS.burnWrapped(amount)` -> `DGNRS.burnForSdgnrs(msg.sender, amount)` -> who is msg.sender?
**Guard Bypass Attempted:** Exploit the delegation chain to burn someone else's DGNRS tokens
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:450` -- `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)` -- passes the ORIGINAL caller as player
- `DegenerusStonk.sol:237-246` -- `burnForSdgnrs(address player, uint256 amount)` -- burns from `balanceOf[player]` (line 239-242)
- msg.sender to `burnForSdgnrs` is the sDGNRS contract (verified by guard at line 238)
- The `player` parameter is set to the original caller of `burnWrapped`
**Detail:** When a player calls `sDGNRS.burnWrapped(amount)`, sDGNRS calls `dgnrsWrapper.burnForSdgnrs(msg.sender, amount)`. In this call, `msg.sender` to DGNRS is the sDGNRS contract (passes the guard), and the `player` parameter is the original caller (the player who called burnWrapped). DGNRS burns from `balanceOf[player]`, which is the original caller's DGNRS balance. An attacker cannot specify a different victim address -- the `player` is always `msg.sender` of the `burnWrapped` call.

### Sequence 12: Partial-claim-reentrancy
**Attack Path:** `sDGNRS.claimRedemption()` with unresolved flip -> `_payEth()` -> re-enter `claimRedemption()` to claim ETH again
**Guard Bypass Attempted:** Exploit the partial claim path (flip unresolved) where claim is NOT fully deleted to double-claim ETH
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `StakedDegenerusStonk.sol:604-606` -- partial claim path: `claim.ethValueOwed = 0` (zeroed BEFORE external call)
- `StakedDegenerusStonk.sol:599` -- `pendingRedemptionEthValue -= ethPayout` (global counter decremented BEFORE external call)
- `StakedDegenerusStonk.sol:585` -- `ethPayout = (claim.ethValueOwed * roll) / 100` -- on re-entry, ethValueOwed is 0, so ethPayout = 0
**Detail:** The partial claim path (when coinflip is unresolved) keeps the claim alive for BURNIE but zeros `claim.ethValueOwed` at line 606 BEFORE the `_payEth` external call at line 610. If the player re-enters via their ETH receive fallback, `claim.ethValueOwed` is already 0, producing `ethPayout = 0`. The `pendingRedemptionEthValue` global counter is also already decremented (line 599), so no double accounting is possible.

### Sequence 13: DGNRS-burn-during-active-game
**Attack Path:** Player calls `DegenerusStonk.burn(amount)` during active game to burn DGNRS directly
**Guard Bypass Attempted:** Bypass the gambling burn flow by going through DGNRS.burn() instead of sDGNRS.burnWrapped()
**Tested:** YES
**Outcome:** SAFE
**Evidence:**
- `DegenerusStonk.sol:169` -- `if (!IDegenerusGame(ContractAddresses.GAME).gameOver()) revert GameNotOver()`
- `DegenerusStonk.sol:167-185` -- `burn()` function requires `gameOver()` to be true
- During active game, only `sDGNRS.burn()` and `sDGNRS.burnWrapped()` are available (gambling path)
**Detail:** The `DegenerusStonk.burn()` function explicitly checks `gameOver()` at line 169 and reverts with `GameNotOver()` if the game is still active. This was the fix for Seam-1 (confirmed HIGH in Phase 44) which previously allowed DGNRS burns during active game to orphan gambling claims. Players wanting to burn during the active game must use `sDGNRS.burn()` (for soulbound tokens) or `sDGNRS.burnWrapped()` (for DGNRS tokens, which routes through the gambling burn flow).
