# Admin Resistance Warden Report

**Warden:** Admin Resistance Specialist (Fresh Eyes)
**Date:** 2026-03-28
**Scope:** All 24 Degenerus protocol contracts
**Methodology:** Zero prior context. Read C4A README + KNOWN-ISSUES.md first, then systematically traced every access-controlled function.

---

## Executive Summary

The Degenerus protocol uses a DGVE-majority ownership model (>50.1% of vault shares) rather than a single admin address. Admin power is concentrated in DegenerusAdmin.sol, which serves as a gateway for liquidity management and governance-gated VRF/feed swaps. The protocol has **no upgradeability, no proxy patterns, and no emergency fund extraction paths**.

The admin's governance weight during bootstrap is bounded by a DGNRS vesting schedule (50B initial, 5B per level, capped at 200B at level 30 out of 1T total supply). Two governance paths (VRF coordinator swap and price feed swap) are gated behind Chainlink service death prerequisites, preventing abuse during normal operation.

**Bottom line:** A hostile admin (compromised DGVE majority holder) cannot extract ETH, manipulate RNG, or grief players during normal game operation. Admin power is limited to: (1) value-neutral liquidity operations, (2) cosmetic DeityPass metadata, (3) lootbox RNG threshold configuration, and (4) governance proposals that require both a Chainlink failure prerequisite AND community inattention to execute. This is a well-defended admin model.

**Findings:** 0 HIGH, 0 MEDIUM, 0 LOW. 3 INFO-level observations. All attack surfaces are SAFE or pre-documented in KNOWN-ISSUES.md.

---

## Methodology

1. Identified all access control modifiers and inline sender checks across all 24 contracts
2. Classified every admin-restricted function by power level (configuration, fund-moving, critical)
3. Traced the DGVE ownership model through DegenerusVault.isVaultOwner
4. Analyzed DGNRS vesting schedule for governance weight at bootstrap vs post-distribution
5. Traced both Chainlink-death-gated governance paths end-to-end
6. Attempted to construct admin abuse scenarios for each attack surface

---

## Admin Function Matrix

### DegenerusAdmin.sol (Gateway Contract)

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `swapGameEthForStEth()` | `onlyOwner` | Configuration | Admin sends ETH to game, receives equal stETH. Value-neutral. | Same. No extraction. |
| `stakeGameEthToStEth(amount)` | `onlyOwner` | Configuration | Stakes excess ETH to Lido. Protected by reserve check in DegenerusGame. | Same. |
| `setLootboxRngThreshold(newThreshold)` | `onlyOwner` | Configuration | Changes mid-day lootbox VRF trigger threshold. No fund impact. | Same. |
| `propose(newCoordinator, newKeyHash)` | Vault owner path or 0.5% sDGNRS community path | Critical (gated) | Requires 20h+ VRF stall (admin) or 7d+ (community). Cannot be called during normal VRF operation. | Same. |
| `vote(proposalId, approve)` | Any sDGNRS holder | Critical (gated) | Requires VRF stall >= 20h to not revert. Changeable votes. | Same. |
| `proposeFeedSwap(newFeed)` | Vault owner or 0.5% sDGNRS | Critical (gated) | Requires 2d+ feed unhealthy (admin) or 7d+ (community). | Same. |
| `voteFeedSwap(proposalId, approve)` | Any sDGNRS holder | Critical (gated) | Reverts if feed is healthy. | Same. |
| `onTokenTransfer(from, amount, data)` | LINK token only | Fund-routing | Credits BURNIE for LINK donations. Cannot be called by admin. | Same. |
| `shutdownVrf()` | GAME contract only | Critical | Only callable post-gameover during handleFinalSweep. | Same. |

### DegenerusGame.sol (Core Game)

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `wireVrf(coordinator_, subId, keyHash_)` | `ADMIN` only | Critical | One-time VRF setup during deployment. Can be called again but only by ADMIN contract. | Same. |
| `updateVrfCoordinatorAndSub(newCoord, newSubId, newKeyHash)` | `ADMIN` only | Critical | Governance-gated in DegenerusAdmin. Resets all VRF state. | Same. |
| `adminSwapEthForStEth(recipient, amount)` | `ADMIN` only | Fund-moving (neutral) | Value-neutral: admin sends ETH to game, receives equal stETH. stETH balance check prevents over-extraction. | Same. |
| `adminStakeEthForStEth(amount)` | `ADMIN` only | Fund-moving (neutral) | Stakes game ETH to Lido. Reserve check protects claimablePool. | Same. |
| `setLootboxRngThreshold(newThreshold)` | `ADMIN` only | Configuration | Changes VRF request trigger. Non-zero check. No fund impact. | Same. |

### DegenerusDeityPass.sol

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `setRenderer(newRenderer)` | `onlyOwner` | Cosmetic | Changes metadata renderer. Zero fund impact. Fallback to internal renderer if external fails. | Same. |
| `setRenderColors(outline, bg, symbol)` | `onlyOwner` | Cosmetic | Changes on-chain SVG colors. Zero fund impact. | Same. |

### DegenerusStonk.sol (DGNRS Wrapper)

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `unwrapTo(recipient, amount)` | `vault.isVaultOwner` | Fund-moving (self-owned) | Burns admin's own DGNRS to give recipient soulbound sDGNRS. Blocked when `rngLocked()`. | Same. |
| `claimVested()` | `vault.isVaultOwner` | Fund-moving (self-owned) | Claims vested DGNRS from contract's own balance. Level-gated. | Same. |

### BurnieCoin.sol

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `creditLinkReward(player, amount)` | `onlyAdmin` | Fund-routing | Credits BURNIE flip stake. Only callable from LINK donation flow. | Same. |

### GNRUS.sol (Charity Governance)

| Function | Modifier | Power Level | Bootstrap Impact | Post-Distribution Impact |
|---|---|---|---|---|
| `propose(recipient)` | Vault owner (up to 5/level) or 0.5% sDGNRS | Governance | Vault owner can submit 5 proposals per level. | Same. |
| `vote(proposalId, approveVote)` | Any sDGNRS holder | Governance | Vault owner gets +5% snapshot weight bonus. Community can outvote. | Same. |
| `pickCharity(level)` | `onlyGame` | Governance execution | Called by game on level transition. Cannot be admin-triggered. | Same. |

### All Other Contracts

| Contract | Admin Functions | Access Control |
|---|---|---|
| StakedDegenerusStonk | `transferFromPool`, `poolRebalance`, deposits | `onlyGame` only. No admin access. |
| BurnieCoinflip | `creditFlip` | `onlyStakedDegenerusStonk` only. |
| DegenerusAffiliate | Record/update | `onlyGame` or `onlyCoin` only. |
| DegenerusJackpots | State management | `onlyGame` or `onlyCoin/Coinflip` only. |
| DegenerusQuests | Quest tracking | `onlyGame` only. |
| DegenerusVault | `deposit` | `onlyGame` only. Player actions self-authorize. |
| WrappedWrappedXRP | `vaultMintTo` | `onlyVault` only. |
| DeityBoonViewer | Pure view | No state changes. |
| Icons32Data | Pure view | No state changes. |
| All 10 delegatecall modules | Via DegenerusGame | Executed in Game context with Game's access control. |
| Libraries (EntropyLib, BitPackingLib, etc.) | Pure/internal | No external access. |

---

## Governance Analysis

### DGNRS Vesting Schedule and Governance Weight

**Supply distribution:**
- Total sDGNRS supply: 1,000,000,000,000 (1T)
- Creator allocation (wrapped as DGNRS): 200,000,000,000 (200B = 20%)
- Pool allocations (retained in sDGNRS contract): 800,000,000,000 (800B = 80%)
  - Whale: 100B, Affiliate: 350B, Lootbox: 200B, Reward: 50B, Earlybird: 100B

**Creator vesting:**
- Deploy: 50B DGNRS to CREATOR (5% of total supply)
- Per level: 5B DGNRS claimable via `claimVested()`
- Fully vested at level 30: 200B total (20% of total supply)
- To participate in governance, creator must `unwrapTo` DGNRS -> sDGNRS (blocked during `rngLocked()`)

**Circulating supply calculation** (DegenerusAdmin.circulatingSupply):
```
circulating = sDGNRS.totalSupply - sDGNRS.balanceOf(SDGNRS) - sDGNRS.balanceOf(DGNRS)
```
This excludes undistributed pool balances and unwrapped DGNRS backing from governance weight.

**Bootstrap phase (levels 0-5):**
- Creator has 50B + (level * 5B) DGNRS available
- At level 0: creator can unwrap up to 50B sDGNRS
- Players accumulating sDGNRS from pools (whale, lootbox, reward, earlybird, affiliate)
- Creator may dominate early governance if few players have sDGNRS
- **But**: VRF governance requires a 20h+ VRF stall to even propose. During normal operation, no governance action is possible.

**Post-distribution (levels 10+):**
- Creator has at most 100B DGNRS (10% of total)
- Players accumulate sDGNRS from pools, especially affiliate (350B pool) and lootbox (200B pool)
- Community rapidly outweighs creator in governance votes
- VRF governance threshold decays from 50% to 5% over 7 days, but still requires VRF death

**Level 30+ (fully vested):**
- Creator has 200B DGNRS maximum (20% of total)
- Even if all unwrapped, pool distributions likely put majority sDGNRS in community hands
- Creator governance influence is bounded and decreasing relative to community

**Can admin prevent transition from bootstrap to post-distribution?**
- No. Game level advancement is permissionless (`advanceGame()` is callable by anyone)
- Pool distributions happen automatically during game operation
- Admin cannot stop sDGNRS pool spending by game contract (onlyGame modifier)
- The DGNRS vesting schedule has no admin-controllable mechanism to accelerate or delay

### GNRUS Governance Weight

The vault owner (DGVE majority) gets a **+5% of sDGNRS snapshot** bonus weight when voting in GNRUS governance. This is bounded and community-outweighable. The vault owner can submit up to 5 proposals per level (vs 1 for community members). GNRUS governance only controls donation distribution (2% of unallocated GNRUS per level) -- no fund extraction path.

---

## Chainlink Death Clock Assessment

### VRF Coordinator Swap

**Prerequisites to propose:**
1. VRF must be stalled for 20h+ (admin path) or 7d+ (community path)
2. Stall measured as `block.timestamp - gameAdmin.lastVrfProcessed()`
3. `subscriptionId` must be non-zero
4. Game must not be over

**Voting mechanism:**
- Every `vote()` call re-checks stall: `block.timestamp - lastVrfProcessed < 20h` causes revert
- If VRF recovers (a fulfillment comes through), all votes revert -- **auto-cancellation**
- Threshold decays: 50% -> 40% -> 30% -> 20% -> 10% -> 5% over 7 days
- Both approve > reject AND approve weight >= threshold * snapshot required for execution
- Single reject voter with > approve weight blocks execution

**Execution (`_executeSwap`):**
1. Marks proposal as Executed
2. Voids all other active proposals (CEI: before external calls)
3. Cancels old VRF subscription (try/catch for edge cases)
4. Creates new subscription on proposed coordinator
5. Adds Game as consumer
6. Pushes new config to Game via `updateVrfCoordinatorAndSub`
7. Transfers LINK balance to new subscription

**`updateVrfCoordinatorAndSub` in AdvanceModule:**
- Resets: `rngLockedFlag = false`, `vrfRequestId = 0`, `rngRequestTime = 0`, `rngWordCurrent = 0`, `midDayTicketRngPending = false`
- Does NOT reset `totalFlipReversals` (preserves user value from BURNIE burns)
- Does NOT reset `lastVrfProcessedTimestamp` (allows rapid re-swap if new coordinator also fails)

**Attack scenario: Compromised admin proposes malicious coordinator**
- Requires: VRF stalled 20h+ AND community doesn't reject within 7 days
- Even at 5% threshold (day 6+), community reject weight > approve weight blocks execution
- Pre-documented in KNOWN-ISSUES.md as WAR-01 (Medium)

**SAFE proof:** The VRF stall prerequisite is enforced at both `propose()` and every `vote()` call. There is no path to bypass the stall check. The `lastVrfProcessed` timestamp is set by `_unlockRng` in AdvanceModule (line 1437: `dailyIdx = day`), which only runs after successful VRF fulfillment processing. An admin cannot manipulate this timestamp -- it is set exclusively during the delegatecall flow from `advanceGame()` -> `rawFulfillRandomWords()`.

**File:line references:**
- Stall check in vote: `DegenerusAdmin.sol:738-739`
- Stall check in propose: `DegenerusAdmin.sol:699-704`
- Auto-cancellation on VRF recovery: `DegenerusAdmin.sol:738-739` (reverts if stall < 20h)
- _executeSwap CEI: `DegenerusAdmin.sol:899-960`
- _voidAllActive before external calls: `DegenerusAdmin.sol:904`
- updateVrfCoordinatorAndSub: `DegenerusGameAdvanceModule.sol:1402-1431`

### Price Feed Swap

**Prerequisites to propose:**
1. Feed must be unhealthy for 2d+ (admin path) or 7d+ (community path)
2. Feed health checked via `_feedStallDuration` (stale data, revert, bad answer, zero updatedAt)
3. Proposed feed must have `decimals() == 18` (or be address(0) to disable)
4. Game must not be over

**Voting mechanism:**
- Every `voteFeedSwap()` call re-checks feed health: if feed recovers, reverts `FeedHealthy()`
- Defence-weighted threshold: 50% -> 40% -> 25% -> 15% (floor) over 4 days
- Higher floor than VRF governance (15% vs 5%) -- intentionally more conservative
- Same approve > reject AND threshold requirement

**Execution (`_executeFeedSwap`):**
1. Marks proposal as Executed
2. Voids all other active feed proposals
3. Updates `linkEthPriceFeed` state variable

**Impact of malicious feed:**
- Feed is ONLY used for LINK donation BURNIE credit calculation
- A bad feed cannot affect ETH game flows, prize pools, RNG, or any core game mechanic
- Worst case: inflated/deflated BURNIE credits for LINK donors
- Pre-documented in KNOWN-ISSUES.md

**SAFE proof:** Feed governance cannot extract funds. The price feed is used exclusively in `linkAmountToEth()` (DegenerusAdmin.sol:1068-1089) which is called only from `onTokenTransfer()` (the LINK donation handler). The ETH equivalent is used to calculate BURNIE flip credits. A malicious feed could inflate these credits, but BURNIE is not backed by ETH -- it has its own coinflip-based economy. The BURNIE credit is given as flip stake (via `creditLinkReward` -> `creditFlip`), not as free tokens.

**File:line references:**
- Feed stall check: `DegenerusAdmin.sol:1113-1131`
- Feed health check in vote: `DegenerusAdmin.sol:564`
- Defence-weighted threshold: `DegenerusAdmin.sol:600-607`
- Feed usage: `DegenerusAdmin.sol:1046-1051` (try/catch in onTokenTransfer)
- Credit path: `DegenerusAdmin.sol:1059` -> `BurnieCoin.sol:592-596`

---

## Findings

No HIGH, MEDIUM, or LOW findings discovered. All admin attack surfaces are either SAFE by construction or pre-documented in KNOWN-ISSUES.md.

---

## SAFE Proofs

### SAFE-1: Admin Cannot Extract ETH

**Attack surface:** `swapGameEthForStEth()` and `adminStakeEthForStEth()` could theoretically be used to drain game ETH.

**Access control trace:**
1. `DegenerusAdmin.swapGameEthForStEth()` (line 652): `onlyOwner` modifier -> `vault.isVaultOwner(msg.sender)` -> requires >50.1% DGVE
2. Calls `gameAdmin.adminSwapEthForStEth{value: msg.value}(msg.sender, msg.value)` -- admin must SEND ETH equal to stETH received
3. `DegenerusGame.adminSwapEthForStEth()` (line 1818): checks `msg.sender != ContractAddresses.ADMIN` -> only ADMIN contract can call
4. Checks `msg.value != amount` -> revert. Checks `stBal < amount` -> revert. Value-neutral swap.

For staking:
1. `DegenerusAdmin.stakeGameEthToStEth(amount)` (line 659): `onlyOwner`
2. Calls `gameAdmin.adminStakeEthForStEth(amount)`
3. `DegenerusGame.adminStakeEthForStEth(amount)` (line 1839): checks `msg.sender != ADMIN`
4. Reserve check (lines 1846-1853): calculates `reserve = claimablePool - stethSettleable`, ensures `amount <= ethBal - reserve`
5. Stakes via `steth.submit{value: amount}(address(0))` -- ETH converted to stETH, still held by game contract

**Conclusion:** SAFE. Admin swap is value-neutral (sends ETH, receives equal stETH). Admin stake converts ETH to stETH within the game contract (no extraction). Reserve check prevents staking ETH needed for player claims. Neither function provides an ETH extraction path.

### SAFE-2: Admin Cannot Manipulate RNG

**Attack surface:** `wireVrf()` and `updateVrfCoordinatorAndSub()` could set a malicious VRF coordinator.

**Access control trace:**
1. `wireVrf` in AdvanceModule (line 418): `msg.sender != ContractAddresses.ADMIN` check
2. Called only from `DegenerusAdmin` constructor (line 479) during deployment
3. `updateVrfCoordinatorAndSub` in AdvanceModule (line 1402): same ADMIN check
4. Called from `_executeSwap` which requires governance vote passing threshold

**Conclusion:** SAFE during normal operation. `wireVrf` is one-time setup. `updateVrfCoordinatorAndSub` requires governance approval that is gated behind VRF death (20h+ stall). An admin cannot swap the VRF coordinator while Chainlink is operating normally. The stall check is verified on every vote, not just at proposal creation. Pre-documented as WAR-01.

### SAFE-3: Admin Cannot Grief Active Players

**Attack surface:** Could admin change game parameters mid-round to disadvantage players?

**Trace:**
1. `setLootboxRngThreshold`: Changes when mid-day lootbox VRF is requested. No impact on game outcomes, prizes, or player state. Non-zero check only validation.
2. `swapGameEthForStEth`: Value-neutral. Game contract still holds equivalent assets.
3. `adminStakeEthForStEth`: Reserve check protects player claims. Staking improves yield.
4. DeityPass `setRenderer`/`setRenderColors`: Cosmetic metadata only. Bounded staticcall with fallback ensures external renderer cannot break tokenURI.

**No admin function can:**
- Pause the game (no pause function exists)
- Change ticket prices (calculated from level-based formula)
- Modify prize pool allocations (hardcoded BPS constants)
- Alter jackpot logic (delegatecall modules with no admin parameters)
- Change RNG during normal VRF operation (governance-gated)
- Front-run with parameter changes (only lootbox threshold is changeable, cosmetic impact)
- Strand player funds (no pausable claim paths)

**Conclusion:** SAFE. Admin has no meaningful griefing vector during active gameplay. All impactful parameters are hardcoded constants or formula-derived.

### SAFE-4: No Ownership Transfer / Privilege Escalation

**Trace:**
1. No `transferOwnership()` function in any contract
2. No `renounceOwnership()` function in any contract
3. Ownership model is DGVE share-based -- owning >50.1% DGVE makes you the "owner"
4. DGVE is a standard transferable ERC20 (DegenerusVaultShare) -- ownership changes via market
5. No proxy patterns (verified: no `delegatecall` to user-supplied addresses, only to compile-time constants)
6. No `selfdestruct` in any contract
7. No assembly-level hidden checks beyond standard bit packing operations
8. No backdoor admin functions -- all access control is via `onlyOwner` modifier or inline `msg.sender` checks against `ContractAddresses` constants

**Conclusion:** SAFE. Privilege escalation is impossible. Contract addresses are immutable compile-time constants. No upgrade mechanism exists.

### SAFE-5: unwrapTo Guard Prevents Vote-Stacking

**Attack surface:** Admin could unwrap DGNRS to sDGNRS just before a governance vote to inflate voting weight.

**Access control trace:**
1. `DegenerusStonk.unwrapTo()` (line 187-194): requires `vault.isVaultOwner(msg.sender)`, `recipient != address(0)`, and `!game.rngLocked()`
2. `rngLocked()` returns true during active VRF request/fulfillment
3. During VRF governance: VRF is stalled (no fulfillments happening), so `rngLocked()` depends on whether a request timed out
4. If VRF is dead, the 12h timeout resets rngLockedFlag via retry, so `unwrapTo` is available between request windows
5. BUT: during VRF stall, no level advancement occurs, so no new sDGNRS is distributed from pools
6. The circulating supply snapshot is taken at proposal creation time

**Conclusion:** SAFE. The `rngLocked()` guard prevents just-in-time vote manipulation during VRF callback windows. During VRF stall governance, the supply is effectively frozen (no game advancement = no pool distributions). The circulating snapshot at proposal time ensures vote weight is measured against a fixed denominator.

### SAFE-6: yearSweep Cannot Be Exploited

**Attack surface:** `DegenerusStonk.yearSweep()` distributes remaining sDGNRS backing after 1 year post-gameover.

**Trace:**
1. Permissionless function (anyone can call)
2. Requires `game.gameOver() == true`
3. Requires `block.timestamp >= gameOverTimestamp + 365 days`
4. Burns all remaining sDGNRS held by DGNRS contract
5. Splits proceeds 50/50 between GNRUS and VAULT

**Conclusion:** SAFE. Not admin-specific. Purely time-locked post-gameover cleanup. No manipulation vector.

---

## Cross-Domain Findings

### INFO-1: GNRUS Vault Owner Vote Weight Bonus

The vault owner receives a +5% sDGNRS snapshot bonus weight when voting in GNRUS charity governance (GNRUS.sol:427). While bounded and documented, this gives the admin disproportionate influence over charity distribution at each level. The bonus is additive with the vault owner's actual sDGNRS holdings. At bootstrap (few community sDGNRS holders), the vault owner could effectively control charity direction.

**Impact:** INFO. Charity governance controls 2% of remaining unallocated GNRUS per level. No fund extraction path. Community can outvote the bonus at scale.

### INFO-2: Lootbox RNG Threshold Has No Upper Bound

`setLootboxRngThreshold(newThreshold)` in DegenerusGame.sol (line 514) only validates `newThreshold != 0`. An admin could set an astronomically high threshold, effectively preventing mid-day lootbox VRF requests. This does not affect daily RNG, game advancement, or any fund flows. Lootboxes would still resolve via daily VRF fulfillment.

**Impact:** INFO. No fund impact. Lootbox resolution delayed but not prevented. Daily VRF flow is unaffected.

### INFO-3: wireVrf Is Not One-Shot

`wireVrf()` in AdvanceModule (line 418-431) has no guard preventing re-invocation. It is access-controlled to `ADMIN` only, and the ADMIN contract only calls it in the constructor. However, if a governance-executed VRF swap calls `updateVrfCoordinatorAndSub` instead of `wireVrf`, this is benign. The `wireVrf` function sets `lastVrfProcessedTimestamp = uint48(block.timestamp)` which `updateVrfCoordinatorAndSub` intentionally does NOT do (to allow rapid re-swap). The distinction is correct by design.

**Impact:** INFO. No separate exploit path. ADMIN contract only calls `wireVrf` in constructor and `updateVrfCoordinatorAndSub` via governance.

---

## Attack Surface Inventory

| # | Contract | Function | Access | Power | Disposition | Notes |
|---|---|---|---|---|---|---|
| 1 | DegenerusAdmin | swapGameEthForStEth | onlyOwner | Configuration | SAFE | Value-neutral swap. SAFE-1. |
| 2 | DegenerusAdmin | stakeGameEthToStEth | onlyOwner | Configuration | SAFE | Reserve-protected. SAFE-1. |
| 3 | DegenerusAdmin | setLootboxRngThreshold | onlyOwner | Configuration | SAFE | No fund impact. INFO-2. |
| 4 | DegenerusAdmin | propose | Vault owner or 0.5% sDGNRS | Critical (gated) | KNOWN (WAR-01) | Requires 20h+ VRF stall. |
| 5 | DegenerusAdmin | vote | Any sDGNRS holder | Critical (gated) | KNOWN (WAR-01) | Auto-cancels on VRF recovery. |
| 6 | DegenerusAdmin | proposeFeedSwap | Vault owner or 0.5% sDGNRS | Critical (gated) | KNOWN | Requires 2d+ feed unhealthy. |
| 7 | DegenerusAdmin | voteFeedSwap | Any sDGNRS holder | Critical (gated) | KNOWN | Auto-cancels on feed recovery. |
| 8 | DegenerusAdmin | shutdownVrf | GAME only | Critical | SAFE | Only post-gameover. Not admin-callable. |
| 9 | DegenerusAdmin | onTokenTransfer | LINK token only | Fund-routing | SAFE | Not admin-callable. |
| 10 | DegenerusGame | wireVrf | ADMIN only | Critical | SAFE | Constructor-only in practice. INFO-3. |
| 11 | DegenerusGame | updateVrfCoordinatorAndSub | ADMIN only | Critical | KNOWN (WAR-01) | Governance-gated. SAFE-2. |
| 12 | DegenerusGame | adminSwapEthForStEth | ADMIN only | Fund-moving | SAFE | Value-neutral. SAFE-1. |
| 13 | DegenerusGame | adminStakeEthForStEth | ADMIN only | Fund-moving | SAFE | Reserve-protected. SAFE-1. |
| 14 | DegenerusGame | setLootboxRngThreshold | ADMIN only | Configuration | SAFE | No fund impact. INFO-2. |
| 15 | DegenerusDeityPass | setRenderer | onlyOwner | Cosmetic | SAFE | Metadata only. Fallback on failure. |
| 16 | DegenerusDeityPass | setRenderColors | onlyOwner | Cosmetic | SAFE | SVG colors only. |
| 17 | DegenerusStonk | unwrapTo | isVaultOwner | Self-fund | SAFE | Burns own DGNRS. rngLocked guard. SAFE-5. |
| 18 | DegenerusStonk | claimVested | isVaultOwner | Self-fund | SAFE | Claims own vesting. Level-gated. |
| 19 | BurnieCoin | creditLinkReward | onlyAdmin | Fund-routing | SAFE | Only from LINK donation flow. |
| 20 | GNRUS | propose (vault owner path) | isVaultOwner | Governance | SAFE | 5 proposals/level cap. INFO-1. |
| 21 | GNRUS | vote (vault owner bonus) | isVaultOwner | Governance | SAFE | +5% weight bonus. INFO-1. |
| 22 | DegenerusVault | isVaultOwner | Public view | N/A | SAFE | Read-only. |
| 23 | AdvanceModule | advanceBounty bypass | isVaultOwner | Game mechanic | SAFE | Allows advance without today's mint. |
| 24 | StakedDegenerusStonk | All pool functions | onlyGame | N/A | SAFE | No admin access. |
| 25 | BurnieCoinflip | creditFlip | onlyStakedDegenerusStonk | N/A | SAFE | No admin access. |
| 26 | DegenerusAffiliate | All functions | onlyGame/onlyCoin | N/A | SAFE | No admin access. |
| 27 | DegenerusJackpots | All functions | onlyGame/onlyCoin | N/A | SAFE | No admin access. |
| 28 | DegenerusQuests | All functions | onlyGame | N/A | SAFE | No admin access. |
| 29 | DegenerusVault | deposit | onlyGame | N/A | SAFE | No admin access. |
| 30 | WrappedWrappedXRP | vaultMintTo | onlyVault | N/A | SAFE | No admin access. |

**Coverage: 30/30 admin-accessible or admin-adjacent surfaces audited. 100% coverage.**

---

## Conclusion

The Degenerus protocol implements a robust admin resistance model:

1. **No single admin address** -- ownership is via DGVE token majority (transferable)
2. **No fund extraction paths** -- all admin operations are value-neutral or value-preserving
3. **No game parameter manipulation** -- all impactful parameters are hardcoded constants
4. **No upgrade mechanism** -- all contracts are immutable with compile-time address constants
5. **Governance gated behind Chainlink death** -- both VRF and feed swap require external service failure
6. **Auto-cancellation on recovery** -- governance becomes invalid the moment Chainlink resumes
7. **DGNRS vesting bounds admin governance weight** -- creator allocation is 20% max, decreasing relative to community over time
8. **rngLocked guard on unwrapTo** -- prevents vote-stacking during VRF windows

All pre-documented KNOWN-ISSUES findings (WAR-01, WAR-02, WAR-06) are confirmed as accurate descriptions of the actual admin risk model.
