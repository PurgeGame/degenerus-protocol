# Unit 11: sDGNRS + DGNRS -- Coverage Checklist

## Contracts Under Audit
- `contracts/StakedDegenerusStonk.sol` (839 lines, 26 functions)
- `contracts/DegenerusStonk.sol` (251 lines, 11 functions)
- **Total: 1,090 lines, 37 functions**

## Methodology
- Per D-01: Categories B/C/D only (no Category A -- these are standalone contracts, not delegatecall modules)
- Per D-04: Both contracts audited as single unit (tightly coupled mutual calls)
- Per D-05: Cross-contract calls between sDGNRS and DGNRS fully traced
- Per D-06: Gambling burn redemption pipeline is PRIORITY investigation
- Per D-08: Fresh analysis -- do not trust prior audit findings
- Per D-12: Follow ULTIMATE-AUDIT-DESIGN.md format

## Checklist Summary

| Category | Count | Analysis Depth |
|----------|-------|---------------|
| B: External State-Changing | 19 | Full Mad Genius (per D-02) |
| C: Internal Helpers (State-Changing) | 7 | Via caller call tree; standalone for [MULTI-PARENT] (per D-03) |
| D: View/Pure | 6 | Security note review |
| Setup (constructors) | 2 | Supply math + initialization verification |
| **TOTAL** | **34** | (excluding 3 trivial wrappers counted separately) |

---

## Constructor Analysis

### sDGNRS Constructor (L262-296)

**Supply Math Verification:**
- INITIAL_SUPPLY = 1,000,000,000,000 * 1e18 = 1e30
- CREATOR_BPS = 2000 -> creatorAmount = 1e30 * 2000 / 10000 = 2e29 (200B tokens)
- WHALE_POOL_BPS = 1000 -> whaleAmount = 1e29 (100B tokens)
- AFFILIATE_POOL_BPS = 3500 -> affiliateAmount = 3.5e29 (350B tokens)
- LOOTBOX_POOL_BPS = 2000 -> lootboxAmount = 2e29 (200B tokens)
- REWARD_POOL_BPS = 500 -> rewardAmount = 5e28 (50B tokens)
- EARLYBIRD_POOL_BPS = 1000 -> earlybirdAmount = 1e29 (100B tokens)
- Total BPS = 2000+1000+3500+2000+500+1000 = 10000 (exactly 100%)
- Dust check at L270-276: adds any remainder to lootbox. With exact 100%, dust = 0.
- Pool total = non-creator amount, minted to address(this)
- poolBalances array initialized correctly to match minted amounts
- game.claimWhalePass(address(0)) + game.setAfKingMode: configures sDGNRS as game participant

**Verdict:** Supply math is exact. No dust. Allocations match. VERIFIED.

### DGNRS Constructor (L87-93)

- Reads `stonk.balanceOf(address(this))` -- the sDGNRS balance held by DGNRS contract
- Requires deposited > 0 (reverts with Insufficient if DGNRS deployed before sDGNRS mints)
- Sets totalSupply = deposited, balanceOf[CREATOR] = deposited
- This means DGNRS totalSupply = sDGNRS creator allocation (200B tokens)

**Verdict:** Correctly mirrors sDGNRS creator allocation. Requires deployment ordering (sDGNRS first). VERIFIED.

---

## Category B: External State-Changing Functions

### StakedDegenerusStonk (B1-B12)

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|-----------|-----------|-------------|-------------|
| B1 | `burn(uint256)` | L443-451 | external (anyone) | totalSupply, balanceOf, pendingRedemption*, pending* segregation vars | game.gameOver(), game.rngLocked(), game.claimWinnings(), game.currentDayView(), game.playerActivityScore() | Tier 1 | BURN-GATEWAY | pending | pending | pending | pending |
| B2 | `burnWrapped(uint256)` | L461-470 | external (anyone) | totalSupply, balanceOf (DGNRS+player), pendingRedemption*, pending* segregation vars | dgnrsWrapper.burnForSdgnrs(), game.gameOver(), game.rngLocked(), game.claimWinnings(), game.currentDayView() | Tier 1 | BURN-WRAPPED | pending | pending | pending | pending |
| B3 | `claimRedemption()` | L573-639 | external (anyone, must have pending claim) | pendingRedemptions[player], pendingRedemptionEthValue | coinflip.getCoinflipDayResult(), game.gameOver(), game.rngWordForDay(), game.resolveRedemptionLootbox(), game.claimWinnings(), coinflip.claimCoinflipsForRedemption(), coin.transfer() | Tier 1 | CLAIM | pending | pending | pending | pending |
| B4 | `resolveRedemptionPeriod(uint16, uint48)` | L540-565 | external (game only) | pendingRedemptionEthValue, pendingRedemptionEthBase, pendingRedemptionBurnie, pendingRedemptionBurnieBase, redemptionPeriods[period] | none | Tier 1 | RESOLVE | pending | pending | pending | pending |
| B5 | `transferFromPool(Pool, address, uint256)` | L376-393 | external (game only) | poolBalances[idx], balanceOf[address(this)], balanceOf[to] | none | Tier 2 | POOL-SPEND | pending | pending | pending | pending |
| B6 | `transferBetweenPools(Pool, Pool, uint256)` | L401-416 | external (game only) | poolBalances[fromIdx], poolBalances[toIdx] | none | Tier 2 | POOL-REBALANCE | pending | pending | pending | pending |
| B7 | `burnRemainingPools()` | L420-429 | external (game only) | balanceOf[address(this)], totalSupply, poolBalances (deleted) | none | Tier 2 | POOL-BURN | pending | pending | pending | pending |
| B8 | `wrapperTransferTo(address, uint256)` | L310-320 | external (DGNRS only) | balanceOf[DGNRS], balanceOf[to] | none | Tier 2 | WRAPPER | pending | pending | pending | pending |
| B9 | `depositSteth(uint256)` | L352-355 | external (game only) | (stETH balance via transferFrom) | steth.transferFrom() | Tier 3 | DEPOSIT | pending | pending | pending | pending |
| B10 | `receive() payable` | L343-345 | external (game only) | (ETH balance via msg.value) | none | Tier 3 | DEPOSIT | pending | pending | pending | pending |
| B11 | `gameAdvance()` | L327-329 | external (anyone) | (game state via delegatecall) | game.advanceGame() | Tier 3 | PROXY | pending | pending | pending | pending |
| B12 | `gameClaimWhalePass()` | L332-334 | external (anyone) | (game state via delegatecall) | game.claimWhalePass(address(0)) | Tier 3 | PROXY | pending | pending | pending | pending |

### DegenerusStonk (B13-B19)

| # | Function | Lines | Access Control | Primary Storage Writes | External Calls | Risk Tier | Subsystem | Analyzed? | Call Tree? | Storage Map? | Cache Check? |
|---|----------|-------|---------------|----------------------|----------------|-----------|-----------|-----------|-----------|-------------|-------------|
| B13 | `burn(uint256)` | L171-189 | external (anyone) | balanceOf[sender], totalSupply | game.gameOver(), stonk.burn() -> sends ETH/stETH/BURNIE | Tier 1 | DGNRS-BURN | pending | pending | pending | pending |
| B14 | `unwrapTo(address, uint256)` | L152-161 | external (creator only) | balanceOf[sender], totalSupply | game.lastVrfProcessed(), stonk.wrapperTransferTo() | Tier 2 | DGNRS-UNWRAP | pending | pending | pending | pending |
| B15 | `burnForSdgnrs(address, uint256)` | L241-250 | external (sDGNRS only) | balanceOf[player], totalSupply | none | Tier 2 | DGNRS-BURN-FOR | pending | pending | pending | pending |
| B16 | `transfer(address, uint256)` | L112-114 | external (anyone) | balanceOf[sender], balanceOf[to] | none | Tier 3 | DGNRS-ERC20 | pending | pending | pending | pending |
| B17 | `transferFrom(address, address, uint256)` | L125-134 | external (anyone) | allowance[from][sender], balanceOf[from], balanceOf[to] | none | Tier 3 | DGNRS-ERC20 | pending | pending | pending | pending |
| B18 | `approve(address, uint256)` | L140-144 | external (anyone) | allowance[sender][spender] | none | Tier 3 | DGNRS-ERC20 | pending | pending | pending | pending |
| B19 | `receive() payable` | L97-99 | external (sDGNRS only) | (ETH balance via msg.value) | none | Tier 3 | DGNRS-RECEIVE | pending | pending | pending | pending |

---

## Category C: Internal/Private State-Changing Helpers

| # | Function | Lines | Called By | Primary Storage Writes | External Calls | Multi-Parent? | Analyzed? |
|---|----------|-------|----------|----------------------|----------------|--------------|-----------|
| C1 | `_deterministicBurnFrom(address, address, uint256)` | L481-523 | burn() [via _deterministicBurn], burnWrapped() | balanceOf[burnFrom], totalSupply | game.claimWinnings(), steth.transfer(), .call{value} | YES (burn + burnWrapped) [MULTI-PARENT] | pending |
| C2 | `_submitGamblingClaimFrom(address, address, uint256)` | L707-769 | burn() [via _submitGamblingClaim], burnWrapped() | balanceOf[burnFrom], totalSupply, pendingRedemptionEthValue, pendingRedemptionEthBase, pendingRedemptionBurnie, pendingRedemptionBurnieBase, pendingRedemptions[beneficiary], redemptionPeriodSupplySnapshot, redemptionPeriodIndex, redemptionPeriodBurned | game.currentDayView(), game.playerActivityScore(), steth.balanceOf(), coin.balanceOf(), coinflip.previewClaimCoinflips() | YES (burn + burnWrapped) [MULTI-PARENT] | pending |
| C3 | `_payEth(address, uint256)` | L772-794 | claimRedemption() | (ETH/stETH transfers) | game.claimWinnings(), .call{value}, steth.transfer() | NO (single parent) | pending |
| C4 | `_payBurnie(address, uint256)` | L797-808 | claimRedemption() | (BURNIE transfers) | coin.transfer(), coinflip.claimCoinflipsForRedemption() | NO (single parent) | pending |
| C5 | `_mint(address, uint256)` | L829-836 | constructor only | totalSupply, balanceOf[to] | none | NO (constructor only) | pending |
| C6 | `DGNRS._transfer(address, address, uint256)` | L209-220 | transfer(), transferFrom() | balanceOf[from], balanceOf[to] | none | YES [MULTI-PARENT] | pending |
| C7 | `DGNRS._burn(address, uint256)` | L222-230 | burn(), unwrapTo() | balanceOf[from], totalSupply | none | YES [MULTI-PARENT] | pending |

**Note:** `_deterministicBurn` (L473-475) and `_submitGamblingClaim` (L699-701) are trivial wrappers that call their `*From` variants with `(player, player, amount)`. They are covered in their parent's call tree and do not need standalone sections.

---

## Category D: View/Pure Functions

| # | Function | Lines | Contract | Returns | Security Notes |
|---|----------|-------|----------|---------|---------------|
| D1 | `previewBurn(uint256)` | L653-683 | sDGNRS | (ethOut, stethOut, burnieOut) | Deducts pendingRedemptionEthValue and pendingRedemptionBurnie. Check for underflow if pending > total. |
| D2 | `hasPendingRedemptions()` | L531-533 | sDGNRS | bool | Checks ethBase or burnieBase != 0. Simple. |
| D3 | `burnieReserve()` | L688-692 | sDGNRS | uint256 | Balance + claimable - pending. Underflow if pending > available? |
| D4 | `poolBalance(Pool)` | L364-366 | sDGNRS | uint256 | Delegates to poolBalances[_poolIndex(pool)]. |
| D5 | `_claimableWinnings()` | L812-816 | sDGNRS | uint256 | Returns stored-1 if stored > 1, else 0. Dust handling. |
| D6 | `_poolIndex(Pool)` | L821-823 | sDGNRS | uint8 | Cast enum to uint8. Safe (Pool has 5 values). |
| D7 | `DGNRS.previewBurn(uint256)` | L201-203 | DGNRS | (ethOut, stethOut, burnieOut) | Delegates to stonk.previewBurn(). |

---

## Cross-Contract Call Matrix

### sDGNRS -> External Contracts

| Caller | Target | Function | Purpose |
|--------|--------|----------|---------|
| burn, burnWrapped | Game | gameOver() | Check game state |
| burn, burnWrapped | Game | rngLocked() | Block burns during VRF |
| _deterministicBurnFrom | Game | claimWinnings(address(0)) | Retrieve ETH if insufficient |
| _submitGamblingClaimFrom | Game | currentDayView() | Get current period index |
| _submitGamblingClaimFrom | Game | playerActivityScore() | Snapshot activity for lootbox |
| claimRedemption | Coinflip | getCoinflipDayResult() | Check BURNIE gamble result |
| claimRedemption | Game | gameOver() | 50/50 vs 100% ETH split |
| claimRedemption | Game | rngWordForDay() | Entropy for lootbox |
| claimRedemption | Game | resolveRedemptionLootbox() | Route lootbox ETH |
| _payEth | Game | claimWinnings(address(0)) | Retrieve ETH if insufficient |
| _payBurnie | Coinflip | claimCoinflipsForRedemption() | Claim BURNIE from coinflip |
| _payBurnie, claimRedemption | Coin | transfer() | Pay BURNIE to player |
| depositSteth | stETH | transferFrom() | Receive stETH deposit |
| _deterministicBurnFrom, _payEth | stETH | transfer() | Pay stETH to player |
| _deterministicBurnFrom, _payEth | (player) | .call{value}() | Pay ETH to player |
| burnWrapped | DGNRSWrapper | burnForSdgnrs() | Burn DGNRS for wrapped path |
| gameAdvance | Game | advanceGame() | Proxy advance |
| gameClaimWhalePass | Game | claimWhalePass() | Proxy whale pass |

### DGNRS -> External Contracts

| Caller | Target | Function | Purpose |
|--------|--------|----------|---------|
| unwrapTo | Game | lastVrfProcessed() | VRF stall guard |
| unwrapTo | stonk (sDGNRS) | wrapperTransferTo() | Move sDGNRS to recipient |
| burn | Game | gameOver() | Game over check |
| burn | stonk (sDGNRS) | burn() | Burn sDGNRS for backing |
| burn | stETH | transfer() | Forward stETH |
| burn | burnie | transfer() | Forward BURNIE |
| burn | (player) | .call{value}() | Forward ETH |

### External -> sDGNRS

| Caller | Function | Purpose |
|--------|----------|---------|
| Game | transferFromPool() | Distribute sDGNRS rewards |
| Game | transferBetweenPools() | Rebalance pools |
| Game | burnRemainingPools() | Burn at game over |
| Game | resolveRedemptionPeriod() | Resolve gambling period |
| Game | receive() payable | Deposit ETH |
| Game | depositSteth() | Deposit stETH |
| DGNRS | wrapperTransferTo() | Unwrap to soulbound |

### External -> DGNRS

| Caller | Function | Purpose |
|--------|----------|---------|
| sDGNRS | burnForSdgnrs() | Burn DGNRS for wrapped gambling |

---

## Risk Tier Summary

| Tier | Count | Functions |
|------|-------|-----------|
| Tier 1 (Complex) | 5 | B1 burn, B2 burnWrapped, B3 claimRedemption, B4 resolveRedemptionPeriod, B13 DGNRS.burn |
| Tier 2 (Moderate) | 5 | B5 transferFromPool, B6 transferBetweenPools, B7 burnRemainingPools, B8 wrapperTransferTo, B14 unwrapTo, B15 burnForSdgnrs |
| Tier 3 (Simple) | 9 | B9-B12 (deposits/proxy), B16-B19 (DGNRS ERC20/receive) |

**MULTI-PARENT Category C functions requiring standalone analysis:** C1 (_deterministicBurnFrom), C2 (_submitGamblingClaimFrom), C6 (DGNRS._transfer), C7 (DGNRS._burn)

---

## Pending: Awaiting Mad Genius (Plan 113-02)
