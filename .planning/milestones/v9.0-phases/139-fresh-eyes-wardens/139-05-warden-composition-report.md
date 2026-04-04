# Composition Warden Audit Report -- Degenerus Protocol

**Auditor:** Composition Specialist Warden (Fresh Eyes)
**Scope:** Cross-domain attack sequences, delegatecall module seam interactions, multi-step exploit chains
**Date:** 2026-03-28
**Contracts:** 24 deployable contracts (14 core + 10 delegatecall modules)
**Methodology:** Zero prior context. Read C4A README and KNOWN-ISSUES first, then systematically tested every composition attack surface.

---

## Executive Summary

The Degenerus Protocol uses a delegatecall-based module architecture where DegenerusGame dispatches to 10 specialized modules sharing a single storage layout (`DegenerusGameStorage`). Cross-contract interactions span RNG (Chainlink VRF), ETH accounting (game + vault + sDGNRS), token operations (DGNRS/sDGNRS/BURNIE), and governance (VRF/feed swap proposals).

After systematic analysis of all composition attack surfaces, **zero Medium+ findings** were identified. The protocol's defense-in-depth approach -- soulbound governance tokens, rngLocked guards, CEI compliance, compile-time constant addresses, and no upgradeability -- effectively neutralizes cross-domain attack chains at multiple points.

**Key architecture strengths observed:**
1. sDGNRS is soulbound (no transfer), blocking flash loan governance attacks entirely
2. `rngLocked` guard blocks burns/unwraps during VRF window, preventing vote-stacking
3. All module addresses are compile-time constants, eliminating routing manipulation
4. Pull pattern for ETH claims (claimableWinnings) with CEI compliance
5. No upgradeability or proxy patterns -- attack surface is static

---

## Methodology

Composition attack audit approach:
1. Map all delegatecall module storage interactions (shared slots read/written by each module)
2. Trace all external calls across contract boundaries for reentrancy windows
3. Test cross-domain attack sequences combining RNG, Money, Gas, and Admin domains
4. Assess state transition attack chains across game lifecycle
5. Evaluate flash loan, sandwich, and MEV extraction vectors
6. Trace token interaction chains (DGNRS -> sDGNRS -> governance -> admin action)

For each attack surface: construct the full multi-step attack sequence, identify where it breaks, and produce a SAFE proof with cross-contract trace.

---

## Module Seam Map

All 10 modules inherit `DegenerusGameStorage` and execute via `delegatecall` in DegenerusGame's context. The following table maps critical shared storage interactions between modules.

| Module A (Writer) | Shared State | Module B (Reader) | Risk | Assessment |
|---|---|---|---|---|
| AdvanceModule | `rngLockedFlag`, `rngWordCurrent`, `rngRequestTime` | All modules (via guards) | HIGH | SAFE -- rngLockedFlag set atomically in `_finalizeRngRequest`, cleared only in `_unlockRng`. All burn/unwrap paths check this flag. |
| AdvanceModule | `jackpotPhaseFlag`, `level`, `jackpotCounter` | JackpotModule, EndgameModule | HIGH | SAFE -- state machine transitions are sequential within `advanceGame`. No concurrent module calls modify these. |
| AdvanceModule | `dailyIdx`, `rngWordByDay[day]` | JackpotModule (winner selection), LootboxModule | HIGH | SAFE -- `rngWordByDay` written once by `_applyDailyRng`, never overwritten. JackpotModule reads after write in same tx. |
| MintModule | `ticketQueue`, `ticketsOwedPacked`, `prizePoolsPacked` | AdvanceModule (ticket processing) | MEDIUM | SAFE -- MintModule writes to write-slot, AdvanceModule reads from read-slot. Double-buffer prevents concurrent access. |
| MintModule | `prizePoolsPacked` / `prizePoolPendingPacked` | AdvanceModule (pool consolidation) | MEDIUM | SAFE -- `prizePoolFrozen` flag routes writes to pending accumulators during jackpot phase. `_unfreezePool` applies atomically. |
| JackpotModule | `claimableWinnings`, `claimablePool` | DegenerusGame (claimWinnings) | HIGH | SAFE -- credits increment both atomically. Claims debit both before external call (CEI). |
| EndgameModule | `claimableWinnings`, `claimablePool`, `prizePoolsPacked` | AdvanceModule (next iteration) | MEDIUM | SAFE -- `runRewardJackpots` uses BAF delta reconciliation (v4.4 fix) to preserve auto-rebuy contributions. |
| LootboxModule | `lootboxEth`, `lootboxRngWordByIndex` | AdvanceModule (RNG finalization) | MEDIUM | SAFE -- lootbox purchases target `lootboxRngIndex`, which advances at VRF request. Word written by VRF callback or daily finalization. |
| DecimatorModule | `claimableWinnings`, `claimablePool` | DegenerusGame (claims) | MEDIUM | SAFE -- decimator reserves full pool in claimablePool before individual credits. |
| GameOverModule | `gameOver`, `claimableWinnings`, `claimablePool` | All modules | HIGH | SAFE -- `gameOver` is terminal (never cleared). Post-gameOver paths are separate code branches. |
| WhaleModule | `ticketQueue` (via `_queueTicketRange`) | AdvanceModule | LOW | SAFE -- ticket range uses same double-buffer routing as MintModule. `rngLocked` guard on far-future writes. |
| BoonModule | `mintPacked_` (boon effects) | MintModule (activity score) | LOW | SAFE -- boon effects modify bonus multipliers, not core ticket accounting. |

### Storage Slot Collision Analysis

All modules inherit `DegenerusGameStorage` without declaring any additional storage variables. Verified by:
- DegenerusGameStorage is the sole storage contract, inherited transitively by all modules
- No module declares `uint256`, `mapping`, or any storage variable outside the inherited layout
- `DegenerusGameMintStreakUtils` (intermediate inheritance) adds only constants and internal pure/view functions
- `DegenerusGamePayoutUtils` (intermediate inheritance) adds only constants, structs, events, and internal functions

**Verdict:** No storage slot collision risk. The single-source-of-truth pattern is correctly implemented.

---

## Cross-Domain Attack Matrix

### 1. RNG + Money

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Manipulate VRF to win jackpot | 1. Buy tickets 2. Observe VRF request 3. Try to influence VRF word | SAFE | VRF word comes from Chainlink -- block proposer cannot influence. All ticket purchases committed before VRF request (rngLockedFlag blocks new writes). |
| VRF fulfillment timing exploitation | 1. Buy tickets 2. Wait for VRF request 3. Front-run fulfillment with state changes | SAFE | `rawFulfillRandomWords` only stores the word (no state changes). `rngLockedFlag` blocks burns, unwraps, and far-future ticket writes during the window. Ticket purchases route to the write slot which is separate from the read slot being processed. |
| Lootbox RNG manipulation | 1. Buy lootboxes 2. Observe lootbox RNG word 3. Open lootbox after seeing word | SAFE | Lootbox purchases target `lootboxRngIndex` (current). VRF request advances the index (`lootboxRngIndex++` in `_finalizeRngRequest`). Word is unknown at purchase time. Mid-day VRF word goes directly to `lootboxRngWordByIndex` -- player cannot see it before purchase. |
| Gambling burn + RNG timing | 1. Submit gambling burn 2. Manipulate RNG roll | SAFE | `sDGNRS.burn()` reverts with `BurnsBlockedDuringRng` when `game.rngLocked()` is true. Burns submitted before VRF request get batched into a period. Roll is derived from VRF word (`(currentWord >> 8) % 151 + 25`) -- unknown at submission time. |
| Redemption lootbox entropy manipulation | 1. Claim redemption 2. Manipulate lootbox RNG word | SAFE | `claimRedemption` uses `rngWordForDay(claimPeriodIndex)` which is already recorded. Entropy is `keccak256(rngWord, player)` -- player address is fixed, word is historical. No manipulation vector. |

**SAFE Proof -- RNG + Money (Jackpot Manipulation):**

Attack chain: Player buys tickets at level N -> VRF requested -> Player tries to alter state to change jackpot outcome.

Cross-contract trace:
```
1. DegenerusGame.purchase() -> MintModule.recordMintData() [delegatecall]
   - Tickets written to ticketQueue[_tqWriteKey(level+1)]
   - Pool splits written to prizePoolsPacked or prizePoolPendingPacked

2. DegenerusGame.advanceGame() -> AdvanceModule.advanceGame() [delegatecall]
   - Day boundary crossed -> _swapAndFreeze(purchaseLevel)
   - _requestRng() called: rngLockedFlag = true, lootboxRngIndex++

3. [VRF WINDOW - rngLockedFlag = true]
   - purchase() still works BUT: tickets go to write slot (not being read)
   - sDGNRS.burn() REVERTS (BurnsBlockedDuringRng)
   - DegenerusStonk.unwrapTo() REVERTS (game.rngLocked())
   - Far-future ticket writes REVERT (RngLocked error in _queueTickets)

4. rawFulfillRandomWords(requestId, [word])
   - Only stores: rngWordCurrent = word (if rngLockedFlag)
   - No jackpot logic executes here

5. Next advanceGame() call -> rngGate() -> _applyDailyRng(day, word)
   - Jackpot winner selection uses word + ticket arrays (both frozen before VRF)
   - No manipulation possible: inputs were committed at step 1-2
```

The attack chain breaks at step 3: `rngLockedFlag` prevents all state modifications that could influence jackpot outcomes during the VRF window. The word is unknown at ticket purchase time (step 1). Winner selection inputs (ticket arrays, pool sizes) are frozen at step 2.

### 2. Admin + Gas

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Admin parameters cause gas limit breach | 1. Admin sets extreme parameters 2. advanceGame exceeds block gas | SAFE | Admin cannot modify game parameters that affect advanceGame gas consumption. Admin functions are: `swapGameEthForStEth`, `stakeGameEthToStEth`, `setLootboxRngThreshold`, VRF/feed governance. None affect jackpot loop sizes, ticket batch sizes, or payout iteration counts. |
| Admin bricks protocol via config | 1. Admin changes critical config 2. Protocol becomes non-functional | SAFE | All contract addresses are compile-time constants (immutable). Admin cannot change module addresses, token addresses, or game parameters. VRF coordinator swap requires governance vote + 20h+ stall. Feed swap requires governance vote + 2d+ stall. Admin can only stake ETH (operational, not destructive). |
| Governance + gas manipulation | 1. Create governance proposal 2. Force gas-expensive vote counting | SAFE | Vote recording is O(1) -- single SLOAD/SSTORE per vote (no loops over voters). Proposal execution is a single delegatecall to `updateVrfCoordinatorAndSub`. No gas amplification vector. |

**SAFE Proof -- Admin + Gas (Parameter Manipulation):**

Cross-contract trace of all admin-callable functions:
```
DegenerusAdmin (onlyOwner):
  swapGameEthForStEth()  -> game.adminSwapEthForStEth()  -- ETH->stETH swap, bounded by msg.value
  stakeGameEthToStEth()  -> game.adminStakeEthForStEth() -- ETH->stETH via Lido, bounded by amount
  setLootboxRngThreshold() -> game.setLootboxRngThreshold() -- uint256 threshold for mid-day VRF

DegenerusAdmin (governance-gated):
  execute()  -> game.updateVrfCoordinatorAndSub() -- VRF coordinator swap (requires 20h+ stall + vote)
  executeFeedSwap() -> game.updatePriceFeed() -- feed swap (requires 2d+ stall + vote)
```

None of these functions modify:
- Ticket batch sizes (hardcoded: WRITES_BUDGET_SAFE = 550)
- Jackpot iteration caps (hardcoded: JACKPOT_LEVEL_CAP = 5, DAILY_ETH_MAX_WINNERS = 50)
- Prize pool split BPS (hardcoded constants)
- Any loop bound that affects advanceGame gas

The gas ceiling is determined entirely by compile-time constants and on-chain state growth (ticket queue length, which is bounded by economic cost of ticket purchases).

### 3. RNG + Admin

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Admin controls VRF coordinator to manipulate RNG | 1. Admin proposes coordinator swap 2. New coordinator returns predictable words | SAFE | Swap requires: (a) 20h+ VRF stall (Chainlink death clock), (b) sDGNRS governance vote with approve > reject, (c) time-decaying threshold. Admin's governance weight is bounded by DGNRS vesting (50B + 5B/level, max 200B at level 30). Community can reject. |
| Governance timing around VRF | 1. Time proposal around VRF fulfillment for advantage | SAFE | VRF governance only activates after 20h+ stall. During stall, `rngLockedFlag` may or may not be set. `unwrapTo` is blocked when `rngLocked()` is true, preventing just-in-time sDGNRS minting for vote-stacking. Supply is effectively frozen during VRF stall (no game advances = no new sDGNRS minting). |
| Admin proposes malicious price feed | 1. Admin proposes fake feed 2. Feed returns arbitrary LINK/ETH price | SAFE | Feed only affects BURNIE credit for LINK donations -- not core game economics or ETH flows. Even with a malicious feed, no ETH can be extracted. Governance vote with defence-weighted threshold (50%->15% floor) provides additional protection. |

**SAFE Proof -- RNG + Admin (VRF Coordinator Swap):**

Cross-contract trace:
```
1. DegenerusAdmin.propose(newCoord, newKeyHash)
   - Requires: vault.isVaultOwner(msg.sender) && stall >= 20h
   - OR: sDGNRS.balanceOf(msg.sender) * BPS >= circ * COMMUNITY_PROPOSE_BPS && stall >= 7d
   - Records: proposal with coordinator, keyHash, circulatingSnapshot

2. DegenerusAdmin.vote(proposalId, approve)
   - Re-checks: stall >= 20h (if VRF recovers, ALL proposals invalid)
   - Weight = sDGNRS.balanceOf(msg.sender) / 1 ether (truncated to uint40)
   - Threshold: decays from ~48% to ~22% over proposal lifetime
   - CANNOT be manipulated via: unwrapTo (blocked by rngLocked during stall),
     flash loans (sDGNRS is soulbound, no transfer/transferFrom)

3. DegenerusAdmin.execute(proposalId)
   - Re-checks: stall >= 20h, approve > reject, approve >= threshold
   - Calls: game.updateVrfCoordinatorAndSub(newCoord, subId, newKeyHash)
   - Resets: all VRF state (coordinator, subscription, keyHash, request tracking)
```

Attack breaks at step 2: Admin's max governance weight is bounded by vesting schedule (200B max at level 30). Any legitimate sDGNRS holder can vote REJECT with weight proportional to their holdings. During VRF stall, no new sDGNRS is minted (game doesn't advance), making supply effectively frozen. Admin cannot unwrap DGNRS to sDGNRS during stall (rngLocked guard on unwrapTo blocks this when VRF is pending).

### 4. Money + Gas

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Accumulate state to DoS payouts | 1. Many small transactions 2. Payout loops exceed gas | SAFE | Payouts use pull pattern (claimableWinnings mapping). No payout loop iterates over all players. Jackpot winner selection iterates over bounded ticket arrays (DAILY_ETH_MAX_WINNERS = 50 cap). |
| Ticket queue growth blocks advanceGame | 1. Buy many tickets 2. Queue grows unbounded 3. Processing exceeds gas | SAFE | Ticket processing is batched: `_runProcessTicketBatch` processes up to WRITES_BUDGET_SAFE (550) entries per advanceGame call. Multiple calls drain the queue incrementally. Gas ceiling verified at 14M under worst-case load. |
| Many pending lootboxes block resolution | 1. Buy many lootboxes 2. Resolution loop exceeds gas | SAFE | Lootboxes are opened individually (`openLootBox(player, index)`). No loop over all pending lootboxes. Each lootbox resolution is O(1). |

**SAFE Proof -- Money + Gas (Ticket Queue DoS):**

Cross-contract trace:
```
1. Player calls purchase() -> MintModule._recordMint() [delegatecall]
   - _queueTickets(buyer, targetLevel, quantity) pushes to ticketQueue[writeKey]
   - Queue grows proportional to unique addresses * levels purchased

2. advanceGame() -> AdvanceModule.advanceGame() [delegatecall]
   - _runProcessTicketBatch(level) processes up to WRITES_BUDGET_SAFE (550) entries
   - If queue not drained: returns (true, false) -> emits STAGE_TICKETS_WORKING
   - Caller gets ADVANCE_BOUNTY_ETH worth of BURNIE credit
   - Function returns -- next caller continues from where this left off

3. Repeat step 2 until queue fully drained (ticketsFullyProcessed = true)
   - Gas per call bounded: 550 * (SLOAD + SSTORE + trait generation) < 14M
   - Economic cost: each advanceGame call costs gas but rewards bounty
```

Queue growth is bounded by economic cost (buying tickets costs ETH). Processing is incremental with bounded gas per call. No single advanceGame call can be forced to exceed block gas limit by queue size.

### 5. Money + Admin

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Admin drains funds via ETH/stETH swap | 1. Admin calls swapGameEthForStEth 2. ETH leaves game contract | SAFE | `swapGameEthForStEth` requires admin to send ETH (`msg.value`) -- admin replaces game ETH with their own ETH, receiving stETH. Net effect: game's ETH balance decreases but stETH increases by equal amount. Solvency invariant maintained. |
| Admin redirects affiliate fees | 1. Admin manipulates affiliate routing | SAFE | Affiliate routing is deterministic based on referral codes. Admin has no function to modify affiliate fee recipients. `DegenerusAffiliate` contract manages all affiliate state independently. |
| Admin stakes all ETH to Lido | 1. Admin calls stakeGameEthToStEth with large amount 2. Game has no ETH for claims | SAFE | `_payoutWithStethFallback` and `_payoutWithEthFallback` handle mixed ETH/stETH payouts. If ETH is insufficient, stETH is used as fallback. Solvency invariant is ETH + stETH >= claimablePool. Staking preserves total value. |

**SAFE Proof -- Money + Admin (Fund Extraction):**

Cross-contract trace of all admin-accessible ETH flows:
```
Admin functions that touch ETH:
1. swapGameEthForStEth{value: X}():
   - Admin sends X ETH to game
   - Game sends X ETH worth of stETH to admin
   - Net: game.ETH unchanged, game.stETH -= X, admin gets stETH
   - BUT: admin must send ETH first -- cannot extract more than they put in

2. stakeGameEthToStEth(amount):
   - Game sends `amount` ETH to Lido
   - Game receives ~`amount` stETH from Lido
   - Net: game.ETH -= amount, game.stETH += amount (minus 1-2 wei rounding)
   - Solvency preserved: ETH + stETH stays ~constant

No admin function can:
- Decrement claimablePool without paying the player
- Transfer ETH/stETH to arbitrary addresses
- Modify pool accounting variables
- Change payout recipient addresses (compile-time constants)
```

---

## State Transition Attack Chains

### Game Lifecycle: PURCHASE -> JACKPOT -> (repeat) -> GAMEOVER

| Transition | Attack Vector | Result | Verdict |
|---|---|---|---|
| PURCHASE -> JACKPOT (premature) | Force nextPrizePool >= levelPrizePool[level] early | SAFE | Requires depositing real ETH via purchases. No way to inflate nextPrizePool without payment. Economic cost makes artificial acceleration unprofitable. |
| JACKPOT -> PURCHASE (skip jackpots) | Bypass jackpot processing to avoid payouts | SAFE | `jackpotCounter` must reach JACKPOT_LEVEL_CAP (5) before phase transition. Cannot be incremented except through daily jackpot processing. |
| Active -> GAMEOVER (forced) | Trigger liveness guard early | SAFE | Liveness guard: level 0 = DEPLOY_IDLE_TIMEOUT_DAYS (365d), level 1+ = 120 days since levelStartTime. Cannot advance timestamp (block.timestamp is validator-controlled but within bounds). Safety check: if nextPool >= target, levelStartTime is refreshed. |
| GAMEOVER reversal | Clear gameOver flag | SAFE | `gameOver` is a bool in Slot 0 byte 28. No code path ever sets it back to false. Terminal by design. |
| Phase transition race condition | Two callers race to execute advanceGame during transition | SAFE | `advanceGame` is not reentrant (no external calls before state updates in the critical path). `phaseTransitionActive` flag prevents re-entry into transition logic. The do-while(false) pattern means each call processes exactly one stage. |

**SAFE Proof -- State Transition Race Condition:**

Cross-contract trace:
```
Caller A: advanceGame() at transition boundary
  1. Reads jackpotPhaseFlag, level, dailyIdx
  2. rngGate() -> VRF word available -> proceeds
  3. jackpotCounter >= JACKPOT_LEVEL_CAP:
     - _endPhase(): phaseTransitionActive = true, jackpotCounter = 0
     - _unlockRng(day): rngLockedFlag = false
     - Returns STAGE_JACKPOT_PHASE_ENDED

Caller B: advanceGame() immediately after A
  1. Reads jackpotPhaseFlag (still true), phaseTransitionActive (true)
  2. rngGate() -> needs new RNG for new day, requests VRF
  3. Returns STAGE_RNG_REQUESTED (waiting for VRF)

OR if same day:
  1. day == dailyIdx -> mid-day path
  2. ticketsFullyProcessed check -> revert NotTimeYet()
```

No race condition: each advanceGame call processes exactly one stage and updates state atomically before returning. The `phaseTransitionActive` flag serializes transition housekeeping across calls.

---

## Flash Loan and Sandwich Attacks

| Attack Pattern | Steps | Result | Verdict |
|---|---|---|---|
| Flash loan sDGNRS for governance votes | 1. Flash loan sDGNRS 2. Vote with borrowed weight 3. Return | SAFE | sDGNRS is soulbound -- no `transfer` or `transferFrom` function exists. Flash loans impossible by construction. |
| Flash loan DGNRS -> unwrap -> vote | 1. Flash loan DGNRS 2. unwrapTo -> get sDGNRS 3. Vote 4. Re-wrap | SAFE | `unwrapTo` is restricted to vault owner only (`vault.isVaultOwner(msg.sender)`). Non-owner cannot call. Additionally, re-wrapping sDGNRS back to DGNRS is not possible (no wrap function exists). |
| Sandwich advanceGame for MEV | 1. See advanceGame in mempool 2. Front-run with purchase 3. Back-run with claim | SAFE | Purchases during the same day go to the write slot (not currently being processed). Jackpot winners are determined by ticket arrays in the read slot (committed before VRF). Front-running cannot influence outcome. |
| Sandwich jackpot distributions | 1. See jackpot payout tx 2. Buy tickets to get into winner pool | SAFE | Winner selection uses read-slot tickets (committed in prior phase). Write-slot tickets are for NEXT level's jackpots. Cannot enter current level's winner pool via sandwich. |
| MEV extraction from advanceGame | 1. MEV bot calls advanceGame 2. Extracts value from bounty | SAFE (by design) | advanceGame bounty is intentionally permissionless. Bounty is BURNIE credit (not ETH). MEV bots calling advanceGame is desired behavior (keeps game progressing). |

**SAFE Proof -- Flash Loan Governance Attack:**

Cross-contract trace:
```
Attack attempt:
1. Attacker flash-borrows DGNRS from DEX
2. Calls DegenerusStonk.unwrapTo(self, amount)
   -> REVERTS: vault.isVaultOwner(msg.sender) returns false
   -> Only vault owner can unwrap DGNRS to sDGNRS

Alternative: attacker IS vault owner
1. Vault owner flash-borrows DGNRS
2. Calls unwrapTo(self, amount)
   -> REVERTS if game.rngLocked() (during VRF stall when governance active)
   -> If VRF is NOT stalled: governance proposals cannot be created (stall < 20h)
   -> If VRF IS stalled: rngLocked likely true, blocking unwrapTo

3. Even if unwrapTo succeeds (VRF stall just started, rngLocked cleared from last advance):
   -> sDGNRS is soulbound, cannot be returned to lender
   -> Flash loan FAILS because repayment requires DGNRS transfer
   -> But attacker burned DGNRS to get sDGNRS (one-way conversion)
   -> Cannot re-wrap: no sDGNRS -> DGNRS function exists
```

The attack chain breaks at multiple points: soulbound property, vault-owner restriction, rngLocked guard, and the one-way nature of unwrapping.

---

## Reentrancy Across Contract Boundaries

### External Call Inventory (DegenerusGame)

| External Call Site | State Modified Before | State Modified After | CEI Compliant? | Risk |
|---|---|---|---|---|
| `_payoutWithStethFallback` (player.call{value}) | claimableWinnings[player] = 1, claimablePool -= payout | None | YES | SAFE |
| `_payoutWithEthFallback` (player.call{value}) | claimableWinnings[player] = 1, claimablePool -= payout | None | YES | SAFE |
| `coin.creditFlip(caller, bounty)` in advanceGame | All advanceGame state updates | None | YES | SAFE (trusted contract) |
| `coinflip.processCoinflipPayouts()` in rngGate | rngWordByDay[day] recorded | None | YES | SAFE (trusted contract) |
| `sdgnrs.resolveRedemptionPeriod()` in rngGate | rngWordByDay[day] recorded | None | YES | SAFE (trusted contract) |
| `steth.transfer()` | Balance accounting done | None | YES | SAFE (Lido stETH, trusted) |
| `vrfCoordinator.requestRandomWords()` | None significant | rngLockedFlag, vrfRequestId, etc. | N/A (request, not payout) | SAFE |

### External Call Inventory (StakedDegenerusStonk)

| External Call Site | State Modified Before | State Modified After | CEI Compliant? | Risk |
|---|---|---|---|---|
| `_deterministicBurnFrom` (beneficiary.call{value}) | balanceOf, totalSupply decremented | None | YES | SAFE |
| `claimRedemption` (_payEth at end) | pendingRedemptionEthValue decremented, claim deleted | None | YES | SAFE |
| `game.resolveRedemptionLootbox()` in claimRedemption | pendingRedemptionEthValue decremented | None | YES | SAFE (trusted contract) |

### Cross-Contract Reentrancy Analysis

**Scenario:** Player receives ETH from claimWinnings, reenters via receive() to call another game function.

Cross-contract trace:
```
1. DegenerusGame.claimWinnings(player)
   -> claimableWinnings[player] = 1  (sentinel, prevents re-claim)
   -> claimablePool -= payout
   -> _payoutWithStethFallback(player, payout)
     -> player.call{value: ethSend}("")

2. Attacker's receive() triggers:
   a. claimWinnings again -> REVERTS (claimableWinnings[player] = 1, amount <= 1 check fails)
   b. purchase() -> succeeds but doesn't affect already-committed jackpot outcomes
   c. advanceGame() -> succeeds but processes independent game logic
   d. openLootBox() -> succeeds but uses pre-committed RNG word
```

No reentrancy vulnerability: the sentinel pattern (`claimableWinnings[player] = 1`) prevents double-claim. Other game functions operate on independent state and cannot extract additional value.

**Scenario:** sDGNRS burn reentrancy via ETH payout.

Cross-contract trace:
```
1. StakedDegenerusStonk._deterministicBurnFrom(beneficiary, burnFrom, amount)
   -> balanceOf[burnFrom] -= amount
   -> totalSupply -= amount
   -> steth.transfer(beneficiary, stethOut)  (trusted token, no reentrancy)
   -> beneficiary.call{value: ethOut}("")

2. Attacker's receive() triggers:
   a. burn() again -> balanceOf already decremented, will compute proportional on reduced balance
   b. burnWrapped() -> requires DGNRS balance (separate token), independent
```

No reentrancy vulnerability: balance is decremented before external call (CEI). Re-entering burn would use the already-reduced balance, computing a smaller proportional payout.

---

## Token Interaction Chains

### Chain 1: DGNRS -> sDGNRS -> Governance -> Admin Action

```
DegenerusStonk.unwrapTo(recipient, amount)    [vault owner only, rngLocked guard]
  -> _burn(msg.sender, amount)                 [DGNRS balance decremented]
  -> stonk.wrapperTransferTo(recipient, amount) [sDGNRS minted to recipient]

DegenerusAdmin.vote(proposalId, approve)        [sDGNRS balance as weight]
  -> weight = sDGNRS.balanceOf(msg.sender) / 1 ether
  -> records vote with weight

DegenerusAdmin.execute(proposalId)              [if threshold met]
  -> game.updateVrfCoordinatorAndSub(...)       [VRF coordinator changed]
```

**Assessment:** SAFE. The chain requires vault owner privilege, VRF stall prerequisite (20h+), and community acquiescence. rngLocked guard on unwrapTo prevents manipulation during VRF window.

### Chain 2: BURNIE -> Coinflip -> ETH Payout

```
BurnieCoin.transfer(VAULT, amount)             [burns BURNIE, credits vault allowance]
DegenerusVault.claimBurnieYield()              [claims BURNIE from vault]
BurnieCoinflip.depositCoinflip(player, amount) [enters daily flip]
  -> Next day: processCoinflipPayouts(bonusFlip, rngWord, day)
  -> Win: BURNIE minted to player
  -> Lose: BURNIE stays in coinflip pool
```

**Assessment:** SAFE. BURNIE coinflip is a gambling mechanism with known house edge. No cross-contract exploitation: coinflip resolution uses VRF word (committed before deposit). Deposit amount is capped by player's BURNIE balance.

### Chain 3: GNRUS -> Burn -> ETH/stETH Redemption

```
GNRUS.burn(amount)
  -> _burn(msg.sender, amount)                  [GNRUS balance decremented, totalSupply reduced]
  -> ethBal = address(this).balance
  -> stethBal = steth.balanceOf(address(this))
  -> proportional payout: (ethBal + stethBal) * amount / totalSupply
  -> steth.transfer(burner, stethOut)
  -> burner.call{value: ethOut}("")
```

**Assessment:** SAFE. GNRUS is soulbound (no transfer). Cannot flash-loan. Burn is proportional to balance/supply with CEI compliance. Reentrancy via ETH payout would find reduced totalSupply and balance, computing correct (smaller) proportional payout.

### Chain 4: Interleaved Token Operations

**Scenario:** Interleave sDGNRS gambling burn with DGNRS burn to create inconsistent state.

```
1. sDGNRS.burn(amount1) -> gambling claim submitted (pendingRedemptionEthBase += ...)
2. DGNRS.burn(amount2) -> REVERTS (game.gameOver() required, otherwise Seam-1 guard)
   During active game: DGNRS.burn() calls game.gameOver() -> returns false -> reverts GameNotOver
3. Cannot interleave: DGNRS.burn is post-gameOver only, sDGNRS.burn gambling is during-game only
```

**Assessment:** SAFE. The Seam-1 fix on DGNRS.burn (gameOver guard) ensures DGNRS burns only happen post-gameOver, while sDGNRS gambling burns only happen during active game. The two paths are mutually exclusive.

---

## Attack Surface Inventory

| # | Surface | Domain | Attack Tested | Disposition | Evidence |
|---|---|---|---|---|---|
| 1 | Delegatecall module routing | Architecture | Function selector collision, fallback manipulation | SAFE | All module addresses are compile-time constants. No dynamic dispatch. No fallback function that delegates. Selectors are explicit ABI-encoded calls. |
| 2 | Shared storage across modules | Architecture | Storage slot corruption, cross-module inconsistency | SAFE | Single DegenerusGameStorage inheritance. No module adds storage variables. Verified: all modules inherit only DegenerusGameStorage (or its subcontracts). |
| 3 | VRF fulfillment -> jackpot winner | RNG+Money | Predict/influence VRF word to win jackpot | SAFE | Chainlink VRF is cryptographically secure. All inputs committed before request. rngLockedFlag blocks state changes during window. |
| 4 | Lootbox purchase -> RNG word | RNG+Money | Purchase after seeing RNG word | SAFE | lootboxRngIndex advances at VRF request. Purchases target current index. Word written to index-1. |
| 5 | Gambling burn -> redemption roll | RNG+Money | Time burn to get favorable roll | SAFE | Burns blocked during rngLocked. Roll derived from next-day VRF word (unknown at burn time). |
| 6 | Admin -> gas ceiling | Admin+Gas | Admin parameters cause advanceGame DoS | SAFE | No admin-modifiable parameter affects gas-sensitive loops. All bounds are compile-time constants. |
| 7 | Governance proposal during stall | Admin+RNG | VRF swap to controlled coordinator | SAFE | 20h stall + governance vote + rngLocked guard on unwrapTo. Community can reject. |
| 8 | Price feed swap | Admin+Money | Malicious feed for BURNIE hyperinflation | SAFE | Feed only used for LINK donation BURNIE credit. No ETH extraction path. Governance-gated with defence-weighted threshold. |
| 9 | Ticket queue growth | Money+Gas | Unbounded queue blocks advanceGame | SAFE | Batched processing (550 per call). Gas bounded. Economic cost to grow queue. |
| 10 | claimablePool accounting | Money | Double-claim, over-credit | SAFE | CEI pattern. Sentinel value (1) prevents re-claim. claimablePool decremented before external call. |
| 11 | Prize pool freeze/unfreeze | Money | Pending accumulators lost or double-applied | SAFE | `_unfreezePool` applies pending pools exactly once (clears prizePoolFrozen flag). Pending pools zeroed at freeze start. |
| 12 | Flash loan sDGNRS for votes | Money+Admin | Borrow sDGNRS, vote, return | SAFE | sDGNRS is soulbound. No transfer function. Flash loans impossible. |
| 13 | Flash loan DGNRS -> unwrap -> vote | Money+Admin | Convert borrowed DGNRS to sDGNRS | SAFE | unwrapTo restricted to vault owner. One-way conversion (no re-wrap). Cannot repay flash loan. |
| 14 | Sandwich advanceGame | Money+MEV | Front-run to enter winner pool | SAFE | Write/read slot separation. Current jackpot uses read-slot tickets (committed prior phase). |
| 15 | Game state machine bypass | State | Skip jackpot phase, force gameover | SAFE | jackpotCounter must reach cap (5). gameOver requires liveness guard (120d). No shortcuts. |
| 16 | Phase transition race | State | Two callers racing transition logic | SAFE | phaseTransitionActive flag serializes. Each call processes one stage. |
| 17 | Cross-contract reentrancy (Game) | Money | Re-enter via ETH payout callback | SAFE | CEI: claimableWinnings zeroed before call. Sentinel prevents re-claim. |
| 18 | Cross-contract reentrancy (sDGNRS) | Money | Re-enter via burn ETH payout | SAFE | CEI: balanceOf/totalSupply decremented before call. Proportional calc uses reduced values on re-entry. |
| 19 | DGNRS/sDGNRS interleave | Money | Mix gambling and deterministic burns | SAFE | Seam-1 guard: DGNRS.burn requires gameOver. Gambling burn during-game only. Mutually exclusive. |
| 20 | Redemption lootbox manipulation | RNG+Money | Manipulate lootbox outcome during claim | SAFE | RNG word from historical day (already recorded). Entropy = keccak256(word, player). No manipulation. |
| 21 | GNRUS burn reentrancy | Money | Re-enter GNRUS.burn via ETH callback | SAFE | CEI: balance/supply decremented before payout. Re-entry computes smaller proportional. |
| 22 | Double-buffer key collision | Architecture | Ticket keys from different slots overlap | SAFE | Three disjoint key spaces: Slot0 [0x000000-0x3FFFFF], FF [0x400000-0x7FFFFF], Slot1 [0x800000-0xBFFFFF]. Collision impossible for level < 2^22. |
| 23 | VRF timeout + gap backfill | RNG | Manipulate backfilled RNG words | SAFE | Backfill uses keccak256(vrfWord, gapDay). VRF word is cryptographically random. Derived words inherit unpredictability. |
| 24 | Coinflip + redemption timing | Money+RNG | Time redemption claim around coinflip result | SAFE | Coinflip day is set at resolution time (flipDay = day + 1). Claimant cannot choose favorable flip day. |
| 25 | Multi-contract ETH conservation | Money | ETH created/destroyed across contracts | SAFE | Pull pattern: ETH credited to claimableWinnings (internal accounting), claimed via explicit withdrawal. No ETH created from nothing. Solvency invariant: balance + stETH >= claimablePool. |

---

## Findings

No Medium or High severity findings identified.

The protocol's composition attack surfaces are well-defended through:
1. **Soulbound governance tokens** eliminate flash loan governance attacks
2. **rngLocked guard** prevents state manipulation during VRF commitment window
3. **Compile-time constant addresses** eliminate routing/dispatch manipulation
4. **Pull pattern with CEI** prevents reentrancy-based double-claims
5. **Double-buffer ticket queue** separates current-level processing from new purchases
6. **Mutual exclusion of burn paths** (during-game vs post-gameOver) prevents interleaving attacks
7. **Batched processing with bounded gas** prevents DoS via queue growth
8. **Governance requires Chainlink death prerequisite** preventing casual VRF takeover

---

## Conclusion

After systematic testing of 25 composition attack surfaces spanning all six cross-domain categories (RNG+Money, Admin+Gas, RNG+Admin, Money+Gas, Money+Admin, State Transitions) plus flash loan/sandwich/MEV vectors and cross-contract reentrancy, no exploitable multi-step attack chains were identified. Every composition surface examined has at least one (and typically multiple) defense layers that break the attack chain.

The delegatecall module architecture is correctly implemented with a single shared storage layout, no module-declared storage variables, and compile-time constant addresses. Cross-contract interactions follow CEI pattern consistently. The soulbound property of sDGNRS is the single most important defense against composition attacks, as it eliminates the entire class of flash-loan governance exploits that would otherwise be the highest-risk cross-domain vector.
