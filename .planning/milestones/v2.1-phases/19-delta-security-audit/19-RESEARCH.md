# Phase 19: Delta Security Audit -- sDGNRS/DGNRS Split - Research

**Researched:** 2026-03-16
**Domain:** Solidity smart contract security audit -- soulbound/liquid token split architecture
**Confidence:** HIGH

## Summary

This phase is a focused security audit of all code changed in the sDGNRS/DGNRS split -- the largest code delta since v1.1. The split refactored DegenerusStonk from a single soulbound token into a dual-contract architecture: StakedDegenerusStonk (sDGNRS, soulbound, holds reserves) + DegenerusStonk (DGNRS, transferable ERC20 wrapper for the 20% creator allocation). Every game module that previously interacted with DegenerusStonk now interacts with sDGNRS, and a new DGNRS wrapper contract provides ERC20 functionality with burn-through and unwrap mechanics.

The audit surface is well-bounded: 2 new/rewritten contracts (StakedDegenerusStonk.sol at ~520 lines, DegenerusStonk.sol at ~177 lines), 1 interface (IStakedDegenerusStonk.sol), and 7 consumer modules that call sDGNRS pool functions. The primary risks are: (1) reentrancy in the burn path (ETH/stETH/BURNIE outflows), (2) supply invariant violations between DGNRS and sDGNRS, (3) incorrect pool enum or address usage in callsites, and (4) BPS arithmetic errors in reward calculations.

**Primary recommendation:** Conduct line-by-line review of StakedDegenerusStonk.sol and DegenerusStonk.sol first, then trace every cross-contract call from game modules into sDGNRS, verifying pool enum, address, and return value handling at each callsite. Finish with the supply invariant proof and written audit report.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DELTA-01 | StakedDegenerusStonk reviewed for reentrancy, access control, reserve accounting | Full contract analysis in Architecture Patterns (burn flow, CEI pattern, onlyGame modifier, reserve math) |
| DELTA-02 | DegenerusStonk wrapper reviewed for ERC20 edge cases, burn delegation, unwrapTo | Full contract analysis including allowance handling, burn-through flow, creator-only auth |
| DELTA-03 | Cross-contract interaction DGNRS<->sDGNRS verified (supply sync, burn-through) | Detailed in Cross-Contract Call Chains section: constructor mint, burn-through, wrapperTransferTo |
| DELTA-04 | All game->sDGNRS callsites verified (pool transfers, deposits, burnRemainingPools) | Complete callsite inventory in Game->sDGNRS Callsite Inventory with exact file:line references |
| DELTA-05 | payCoinflipBountyDgnrs 3-arg gating logic verified | Function analysis with exact constants (50k bet, 20k pool, BPS=20) and caller chain |
| DELTA-06 | Degenerette DGNRS reward math (6/7/8 match tiers) verified | Full formula documentation (cappedBet, tier BPS 400/800/1500, pool percentage) |
| DELTA-07 | Earlybird->Lootbox pool dump verified (was Reward), no Reward pool reference remains | Code analysis confirms Earlybird->Lootbox dump is correct; comment mismatch flagged as finding |
| DELTA-08 | Pool BPS rebalance impact on all downstream consumers verified | Complete BPS constant inventory across all consuming contracts |
</phase_requirements>

## Standard Stack

This is a security audit phase -- no new libraries to install. The audit uses the existing project stack.

### Core (Existing Project Stack)
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Solidity | 0.8.34 | Contract language | Project compiler version, overflow protection built-in |
| Hardhat | (project) | Test runner (JS) | 201 tests pass, full protocol deployment fixture |
| Foundry/Forge | (project) | Fuzz testing | Invariant and property-based tests |

### Audit Approach
| Method | Purpose | When to Use |
|--------|---------|-------------|
| Manual line-by-line review | Core security review | StakedDegenerusStonk.sol, DegenerusStonk.sol |
| Cross-reference callsite audit | Verify integration correctness | Every module that calls sDGNRS |
| Invariant analysis | Supply conservation proof | DGNRS.totalSupply + sDGNRS.balanceOf(others) == sDGNRS.totalSupply |
| Test execution | Regression verification | `npm test` for Hardhat, `npm run fuzz` for Foundry |

## Architecture Patterns

### Contract Topology (sDGNRS/DGNRS Split)

```
StakedDegenerusStonk (sDGNRS) -- contracts/StakedDegenerusStonk.sol
|-- Soulbound (no transfer function)
|-- Holds ETH + stETH + BURNIE reserves
|-- 5 reward pools: Whale(0), Affiliate(1), Lootbox(2), Reward(3), Earlybird(4)
|-- Pool functions: transferFromPool, transferBetweenPools, burnRemainingPools
|-- Deposit functions: receive() (ETH), depositSteth()
|-- Burn function: burn() -> returns ETH + stETH + BURNIE
|-- Wrapper function: wrapperTransferTo() (DGNRS contract only)
|
DegenerusStonk (DGNRS) -- contracts/DegenerusStonk.sol
|-- Transferable ERC20 wrapper
|-- Initial supply = sDGNRS.balanceOf(DGNRS address) = 20% creator allocation
|-- burn() -> delegates to sDGNRS.burn(), forwards assets to caller
|-- unwrapTo() -> creator-only, burns DGNRS, sends sDGNRS to recipient
|-- previewBurn() -> delegates to sDGNRS.previewBurn()
```

### Supply Invariant

The fundamental supply invariant that MUST hold at all times:

```
sDGNRS.totalSupply = sum(sDGNRS.balanceOf[addr] for all addr)
DGNRS.totalSupply = sDGNRS.balanceOf[DGNRS_ADDRESS] - (unwrapped sDGNRS sent via wrapperTransferTo)
```

More precisely, because wrapperTransferTo moves sDGNRS FROM the DGNRS contract's sDGNRS balance TO a recipient:
```
sDGNRS.balanceOf[DGNRS_ADDRESS] >= DGNRS.totalSupply  (always)
```

And for the whole system:
```
DGNRS.totalSupply <= sDGNRS.balanceOf[DGNRS_ADDRESS]
```

The gap between `sDGNRS.balanceOf[DGNRS_ADDRESS]` and `DGNRS.totalSupply` represents sDGNRS that was unwrapped (sent to recipients via `unwrapTo` -> `wrapperTransferTo`). This sDGNRS is now soulbound in recipient balances but no longer backed by DGNRS tokens.

### Cross-Contract Call Chains

**Chain 1: DGNRS burn-through**
```
User -> DGNRS.burn(amount)
  -> DGNRS._burn(msg.sender, amount)          [reduces DGNRS balance + totalSupply]
  -> sDGNRS.burn(amount)                       [reduces sDGNRS balance of DGNRS contract + totalSupply]
     -> sDGNRS sends ETH/stETH/BURNIE to DGNRS contract
  -> DGNRS forwards BURNIE to msg.sender       [coin.transfer]
  -> DGNRS forwards stETH to msg.sender        [steth.transfer]
  -> DGNRS forwards ETH to msg.sender          [msg.sender.call{value}]
```

**CRITICAL NOTE:** When DGNRS calls `stonk.burn(amount)`, the sDGNRS contract sends ETH/stETH/BURNIE to `msg.sender` which is the DGNRS contract (not the end user). DGNRS then forwards to the actual user. The sDGNRS `burn()` uses `msg.sender` (line 382: `address player = msg.sender`) -- so when called by DGNRS, the "player" is the DGNRS contract address. This means:
- sDGNRS deducts from `balanceOf[DGNRS_ADDRESS]`
- sDGNRS sends ETH to the DGNRS contract (which has `receive() external payable {}`)
- sDGNRS sends BURNIE to the DGNRS contract
- sDGNRS sends stETH to the DGNRS contract
- DGNRS then re-sends all three to the actual caller

**Chain 2: DGNRS unwrapTo**
```
Creator -> DGNRS.unwrapTo(recipient, amount)
  -> DGNRS._burn(msg.sender, amount)          [reduces creator's DGNRS balance + totalSupply]
  -> sDGNRS.wrapperTransferTo(recipient, amount) [moves sDGNRS from DGNRS balance to recipient]
```

**Chain 3: Game->sDGNRS pool transfer**
```
DegenerusGame (via delegatecall module) -> sDGNRS.transferFromPool(pool, to, amount)
  -> Checks onlyGame (msg.sender == GAME)
  -> Moves tokens from poolBalances[pool] -> balanceOf[to]
  -> Returns actual transferred amount (may be less if pool depleted)
```

**Chain 4: Game->sDGNRS deposit**
```
DegenerusGame -> payable call to sDGNRS address (ETH deposit)
  -> receive() external payable onlyGame
DegenerusGame -> sDGNRS.depositSteth(amount)
  -> onlyGame, transferFrom(game, sDGNRS, amount)
```

**Chain 5: BurnieCoinflip -> DegenerusGame -> sDGNRS (bounty)**
```
BurnieCoinflip._resolveFlip() -> game.payCoinflipBountyDgnrs(to, slice, currentBounty_)
  -> DegenerusGame.payCoinflipBountyDgnrs() [checks COIN/COINFLIP caller]
     -> checks min bet (50k), min pool (20k)
     -> sDGNRS.poolBalance(Pool.Reward)
     -> payout = (poolBalance * 20) / 10_000
     -> sDGNRS.transferFromPool(Pool.Reward, player, payout)
```

### Game->sDGNRS Callsite Inventory

Every location in the codebase where game contracts call sDGNRS functions:

| # | File | Line | Function Called | Pool Used | Purpose |
|---|------|------|-----------------|-----------|---------|
| 1 | DegenerusGame.sol | 477 | `dgnrs.poolBalance(Pool.Reward)` | Reward | Coinflip bounty pool check |
| 2 | DegenerusGame.sol | 482 | `dgnrs.transferFromPool(Pool.Reward, ...)` | Reward | Coinflip bounty payout |
| 3 | DegenerusGame.sol | 1460 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Per-affiliate DGNRS claim |
| 4 | DegenerusGame.sol | 1956 | `dgnrs.depositSteth(amount)` | N/A | stETH deposit to reserves |
| 5 | DegenerusGameStorage.sol | 1092-1098 | `dgnrsContract.poolBalance(Pool.Earlybird)` + `dgnrsContract.transferBetweenPools(Pool.Earlybird, Pool.Lootbox, ...)` | Earlybird->Lootbox | Earlybird dump at level >= 3 |
| 6 | DegenerusGameStorage.sol | 1109 | `dgnrsContract.poolBalance(Pool.Earlybird)` | Earlybird | Earlybird pool start snapshot |
| 7 | DegenerusGameStorage.sol | 1133 | `dgnrsContract.transferFromPool(Pool.Earlybird, ...)` | Earlybird | Earlybird reward payout |
| 8 | DegenerusGameWhaleModule.sol | 634 | `dgnrs.poolBalance(Pool.Whale)` | Whale | Whale bundle minter check |
| 9 | DegenerusGameWhaleModule.sol | 639 | `dgnrs.transferFromPool(Pool.Whale, ...)` | Whale | Whale bundle minter reward |
| 10 | DegenerusGameWhaleModule.sol | 647 | `dgnrs.poolBalance(Pool.Affiliate)` | Affiliate | Whale bundle affiliate check |
| 11 | DegenerusGameWhaleModule.sol | 655 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Whale bundle direct affiliate |
| 12 | DegenerusGameWhaleModule.sol | 666-675 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Whale bundle upline/upline2 |
| 13 | DegenerusGameWhaleModule.sol | 694 | `dgnrs.poolBalance(Pool.Whale)` | Whale | Deity pass whale check |
| 14 | DegenerusGameWhaleModule.sol | 698 | `dgnrs.transferFromPool(Pool.Whale, ...)` | Whale | Deity pass buyer reward |
| 15 | DegenerusGameWhaleModule.sol | 709 | `dgnrs.poolBalance(Pool.Affiliate)` | Affiliate | Deity pass affiliate check |
| 16 | DegenerusGameWhaleModule.sol | 717 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Deity pass direct affiliate |
| 17 | DegenerusGameWhaleModule.sol | 728-737 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Deity pass upline/upline2 |
| 18 | DegenerusGameLootboxModule.sol | 1693 | `dgnrs.poolBalance(Pool.Lootbox)` | Lootbox | Lootbox DGNRS tier check |
| 19 | DegenerusGameLootboxModule.sol | 1710 | `dgnrs.transferFromPool(Pool.Lootbox, ...)` | Lootbox | Lootbox DGNRS payout |
| 20 | DegenerusGameEndgameModule.sol | 122 | `dgnrs.poolBalance(Pool.Affiliate)` | Affiliate | Top affiliate reward check |
| 21 | DegenerusGameEndgameModule.sol | 125 | `dgnrs.transferFromPool(Pool.Affiliate, ...)` | Affiliate | Top affiliate reward payout |
| 22 | DegenerusGameEndgameModule.sol | 135 | `dgnrs.poolBalance(Pool.Affiliate)` | Affiliate | Level allocation snapshot |
| 23 | DegenerusGameJackpotModule.sol | 794 | `dgnrs.poolBalance(Pool.Reward)` | Reward | Final day DGNRS reward check |
| 24 | DegenerusGameJackpotModule.sol | 812 | `dgnrs.transferFromPool(Pool.Reward, ...)` | Reward | Final day DGNRS payout |
| 25 | DegenerusGameDegeneretteModule.sol | 1172 | `sdgnrs.poolBalance(Pool.Reward)` | Reward | Degenerette DGNRS reward check |
| 26 | DegenerusGameDegeneretteModule.sol | 1179 | `sdgnrs.transferFromPool(Pool.Reward, ...)` | Reward | Degenerette DGNRS payout |
| 27 | DegenerusGameGameOverModule.sol | 163 | `dgnrs.burnRemainingPools()` | All | Game over pool burn |
| 28 | DegenerusGameGameOverModule.sol | 219 | `dgnrs.depositSteth(dgnrsAmount)` | N/A | Game over stETH deposit |
| 29 | DegenerusGameGameOverModule.sol | 223 | `dgnrs.depositSteth(stethBal)` | N/A | Game over stETH deposit |
| 30 | DegenerusGameGameOverModule.sol | 227 | `payable(SDGNRS).call{value: ethAmount}` | N/A | Game over ETH deposit |

### Pool Enum Values (Critical -- must match everywhere)

```solidity
enum Pool {
    Whale,      // 0
    Affiliate,  // 1
    Lootbox,    // 2
    Reward,     // 3
    Earlybird   // 4
}
```

Defined in: `StakedDegenerusStonk.sol:133-139` and `IStakedDegenerusStonk.sol:10-16`

### BPS/PPM Constants for All sDGNRS Consumers

**Pool distribution (sDGNRS constructor):**
| Pool | BPS | Percentage | Tokens (of 1T) |
|------|-----|-----------|-----------------|
| Creator | 2000 | 20% | 200B (to DGNRS wrapper) |
| Whale | 1000 | 10% | 100B |
| Affiliate | 3500 | 35% | 350B |
| Lootbox | 2000+dust | 20%+ | 200B+ |
| Reward | 500 | 5% | 50B |
| Earlybird | 1000 | 10% | 100B |

**Reward pool consumers (Pool.Reward):**
| Consumer | BPS/PPM | Scale | Human | File |
|----------|---------|-------|-------|------|
| payCoinflipBountyDgnrs | 20 BPS | /10,000 | 0.2% of pool | DegenerusGame.sol:202 |
| awardFinalDayDgnrsReward | 100 BPS | /10,000 | 1% of pool | JackpotModule.sol:179 |
| _awardDegeneretteDgnrs (6-match) | 400 BPS | /10,000 | 4% per capped ETH | DegeneretteModule.sol:237 |
| _awardDegeneretteDgnrs (7-match) | 800 BPS | /10,000 | 8% per capped ETH | DegeneretteModule.sol:238 |
| _awardDegeneretteDgnrs (8-match) | 1500 BPS | /10,000 | 15% per capped ETH | DegeneretteModule.sol:239 |

**Whale pool consumers (Pool.Whale):**
| Consumer | BPS/PPM | Scale | Human | File |
|----------|---------|-------|-------|------|
| Whale bundle minter | 10,000 PPM | /1,000,000 | 1% of pool | WhaleModule.sol:91 |
| Deity pass buyer | 500 BPS | /10,000 | 5% of pool | WhaleModule.sol:106 |

**Affiliate pool consumers (Pool.Affiliate):**
| Consumer | BPS/PPM | Scale | Human | File |
|----------|---------|-------|-------|------|
| Whale bundle direct | 1,000 PPM | /1,000,000 | 0.1% of pool | WhaleModule.sol:94 |
| Whale bundle upline | 200 PPM | /1,000,000 | 0.02% of pool | WhaleModule.sol:97 |
| Whale bundle upline2 | 100 PPM (upline/2) | derived | 0.01% of pool | WhaleModule.sol:672 |
| Deity pass direct | 5,000 PPM | /1,000,000 | 0.5% of pool | WhaleModule.sol:100 |
| Deity pass upline | 1,000 PPM | /1,000,000 | 0.1% of pool | WhaleModule.sol:103 |
| Deity pass upline2 | 500 PPM (upline/2) | derived | 0.05% of pool | WhaleModule.sol:734 |
| Top affiliate endgame | 100 BPS | /10,000 | 1% of pool | EndgameModule.sol:96 |
| Per-level allocation | 500 BPS | /10,000 | 5% of remaining | EndgameModule.sol:99 |
| Per-affiliate claim | score/denominator * allocation | proportional | variable | DegenerusGame.sol:1457 |
| Deity bonus | score * 2000 BPS / 10,000 | capped at 5 ETH worth | variable | DegenerusGame.sol:1470-1474 |

**Lootbox pool consumers (Pool.Lootbox):**
| Consumer | PPM | Scale | Human | File |
|----------|-----|-------|-------|------|
| Small tier (79.5%) | 10 | /1,000,000 | 0.001% per ETH | LootboxModule.sol:287 |
| Medium tier (15%) | 390 | /1,000,000 | 0.039% per ETH | LootboxModule.sol:289 |
| Large tier (5%) | 800 | /1,000,000 | 0.08% per ETH | LootboxModule.sol:291 |
| Mega tier (0.5%) | 8000 | /1,000,000 | 0.8% per ETH | LootboxModule.sol:293 |

**Earlybird pool consumers (Pool.Earlybird):**
- Quadratic emission curve during levels 0-2 (EARLYBIRD_END_LEVEL=3, exclusive)
- Dump to Lootbox pool at level >= 3

### Anti-Patterns to Avoid in Audit

- **Assuming unchecked blocks are unsafe:** Solidity 0.8.34 has built-in overflow checks. The unchecked blocks in sDGNRS are deliberate: they appear only where underflow is impossible due to prior validation (e.g., `bal - amount` after `if (amount > bal) revert`).
- **Confusing the two dgnrs references:** The DegeneretteModule uses `sdgnrs` (directly referencing sDGNRS), while DegenerusGame and other modules use `dgnrs` (also referencing sDGNRS via ContractAddresses.SDGNRS). Both point to the same contract.
- **Missing that DGNRS wrapper is NOT the game contract:** The DGNRS wrapper calls sDGNRS.burn() with itself as msg.sender. This is distinct from game-only functions.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Supply invariant verification | Manual arithmetic | Trace constructor + every burn/mint/transfer path | Edge cases in unchecked arithmetic |
| Reentrancy analysis | Ad-hoc checking | Systematic CEI pattern verification at each external call | ETH callbacks, stETH callbacks, BURNIE callbacks all different |
| Cross-contract auth | Trust diagrams | Verify msg.sender checks at each entry point | Delegatecall changes msg.sender semantics |

## Common Pitfalls

### Pitfall 1: DGNRS Burn-Through Reentrancy
**What goes wrong:** DGNRS.burn() calls sDGNRS.burn() which sends ETH/tokens to the DGNRS contract, then DGNRS forwards to the user. The user's receive()/fallback() could re-enter.
**Why it happens:** Multiple external calls in sequence with value transfer.
**How to avoid:** Verify CEI pattern: both DGNRS._burn() and sDGNRS balance deduction happen BEFORE any external transfers. sDGNRS deducts balance and totalSupply at lines 398-401 before any transfers. DGNRS._burn() is called at line 126 before stonk.burn() at line 128. The pattern appears correct but must be verified exhaustively.
**Warning signs:** Any state mutation after an external call.

### Pitfall 2: sDGNRS.burn() Called by DGNRS vs Direct
**What goes wrong:** When DGNRS calls sDGNRS.burn(), the "player" is the DGNRS contract. sDGNRS sends ETH to DGNRS, which has `receive() external payable {}`. If sDGNRS.burn() is also callable directly by sDGNRS holders, the same function handles both paths.
**Why it happens:** Shared function with different callers.
**How to avoid:** Verify that sDGNRS.burn() correctly handles both cases: direct callers (sDGNRS holders) and the DGNRS wrapper contract. The sDGNRS burn function has no access control -- it's public. Any holder (including the DGNRS contract) can call it.
**Warning signs:** Assumptions about msg.sender identity in the burn path.

### Pitfall 3: wrapperTransferTo Balance Overflow
**What goes wrong:** The unchecked `balanceOf[to] += amount` in wrapperTransferTo (line 249) could overflow if a recipient already holds a large balance.
**Why it happens:** Unchecked arithmetic for gas optimization.
**How to avoid:** Verify that total supply is bounded (1 trillion * 1e18 = 1e30, well within uint256). Since no address can hold more than totalSupply, and totalSupply fits in uint256, the unchecked add is safe. Same pattern analysis applies to transferFromPool (line 327).
**Warning signs:** Any scenario where balanceOf could exceed totalSupply.

### Pitfall 4: Pool Depletion Race Conditions
**What goes wrong:** Multiple simultaneous transactions could drain a pool below expected values, causing unexpected capped payouts.
**Why it happens:** transferFromPool caps to available balance (line 321-322).
**How to avoid:** Verify that all callers handle the case where transferred < requested. Check return values are used correctly (some callers ignore, some check).
**Warning signs:** Callers that assume transferFromPool returns the requested amount.

### Pitfall 5: stETH Transfer Rounding
**What goes wrong:** stETH transfers involve 1-2 wei rounding. This could cause sDGNRS.burn() to fail if stethOut is calculated precisely but stETH.transfer rounds down.
**Why it happens:** Lido's rebasing mechanics.
**How to avoid:** Verify that the burn function's stETH handling accounts for rounding. The `if (stethOut > stethBal) revert Insufficient()` check at line 415 uses the actual balance, which should be safe.
**Warning signs:** Exact-match assertions on stETH amounts.

### Pitfall 6: Earlybird Comment/Code Mismatch (ALREADY IDENTIFIED)
**What goes wrong:** Comment says "dump remaining earlybird pool into reward pool" (DegenerusGameStorage.sol:1086) but code dumps into Lootbox pool (line 1098: `Pool.Lootbox`).
**Why it happens:** Comment was not updated when the destination pool was changed from Reward to Lootbox.
**How to avoid:** This IS the correct behavior per DELTA-07 ("Earlybird->Lootbox dump verified (was Reward)"). The comment is stale. Flag as informational finding.
**Warning signs:** Any remaining references to "Earlybird->Reward" in code or docs.

### Pitfall 7: DGNRS Constructor Timing
**What goes wrong:** DGNRS constructor reads `stonk.balanceOf(address(this))` and assigns to `balanceOf[CREATOR]`. If the sDGNRS constructor hasn't run yet, this would be zero.
**Why it happens:** Deploy order dependency.
**How to avoid:** Verify that sDGNRS is deployed BEFORE DGNRS. The constructor reverts with `Insufficient()` if deposited == 0, so incorrect deploy order would fail safely. Addresses are baked into ContractAddresses via CREATE nonce prediction.
**Warning signs:** Any way to construct DGNRS before sDGNRS.

## Code Examples

### sDGNRS Burn Flow (Critical Path)

```solidity
// StakedDegenerusStonk.sol:379-441
function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 burnieOut) {
    address player = msg.sender;  // NOTE: This is DGNRS contract when called via burn-through
    uint256 bal = balanceOf[player];
    if (amount == 0 || amount > bal) revert Insufficient();
    uint256 supplyBefore = totalSupply;

    // Calculate proportional shares BEFORE any state changes
    uint256 ethBal = address(this).balance;
    uint256 stethBal = steth.balanceOf(address(this));
    uint256 claimableEth = _claimableWinnings();
    uint256 totalMoney = ethBal + stethBal + claimableEth;
    uint256 totalValueOwed = (totalMoney * amount) / supplyBefore;

    uint256 burnieBal = coin.balanceOf(address(this));
    uint256 claimableBurnie = coinflip.previewClaimCoinflips(address(this));
    uint256 totalBurnie = burnieBal + claimableBurnie;
    burnieOut = (totalBurnie * amount) / supplyBefore;

    // STATE CHANGES (CEI: effects before interactions)
    unchecked {
        balanceOf[player] = bal - amount;
        totalSupply -= amount;
    }
    emit Transfer(player, address(0), amount);

    // Claim game winnings if needed to cover ethOut
    if (totalValueOwed > ethBal && claimableEth != 0) {
        game.claimWinnings(address(0));  // EXTERNAL CALL 1
        ethBal = address(this).balance;
        stethBal = steth.balanceOf(address(this));
    }

    // ETH-preferential payout logic
    if (totalValueOwed <= ethBal) {
        ethOut = totalValueOwed;
    } else {
        ethOut = ethBal;
        stethOut = totalValueOwed - ethOut;
        if (stethOut > stethBal) revert Insufficient();
    }

    // BURNIE payout (balance first, then coinflip claimables)
    // ... transfers BURNIE to player ...

    // stETH transfer
    if (stethOut > 0) {
        if (!steth.transfer(player, stethOut)) revert TransferFailed();  // EXTERNAL CALL
    }

    // ETH transfer (LAST -- CEI pattern)
    if (ethOut > 0) {
        (bool success, ) = player.call{value: ethOut}("");  // EXTERNAL CALL
        if (!success) revert TransferFailed();
    }
}
```

### payCoinflipBountyDgnrs (3-arg gating)

```solidity
// DegenerusGame.sol:464-487
function payCoinflipBountyDgnrs(
    address player,
    uint256 winningBet,     // arg 2: the slice (half of bounty pool)
    uint256 bountyPool      // arg 3: remaining bounty pool after slice
) external {
    if (msg.sender != ContractAddresses.COIN &&
        msg.sender != ContractAddresses.COINFLIP) revert E();
    if (player == address(0)) return;
    if (winningBet < COINFLIP_BOUNTY_DGNRS_MIN_BET) return;   // 50,000 ether (BURNIE)
    if (bountyPool < COINFLIP_BOUNTY_DGNRS_MIN_POOL) return;  // 20,000 ether (BURNIE)
    uint256 poolBalance = dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward);
    if (poolBalance == 0) return;
    uint256 payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000;  // 20 BPS = 0.2%
    if (payout == 0) return;
    dgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, player, payout);
}
```

### Degenerette DGNRS Reward Math

```solidity
// DegenerusGameDegeneretteModule.sol:1166-1180
function _awardDegeneretteDgnrs(address player, uint256 betWei, uint8 matchCount) private {
    uint256 bps;
    if (matchCount == 6) bps = DEGEN_DGNRS_6_BPS;      // 400  = 4%
    else if (matchCount == 7) bps = DEGEN_DGNRS_7_BPS;  // 800  = 8%
    else bps = DEGEN_DGNRS_8_BPS;                        // 1500 = 15%

    uint256 poolBalance = sdgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward);
    if (poolBalance == 0) return;

    uint256 cappedBet = betWei > 1 ether ? 1 ether : betWei;
    // reward = poolBalance * bps * cappedBet / (10_000 * 1 ether)
    // = poolBalance * (bps/10_000) * (cappedBet/1 ether)
    // = poolBalance * tier_percentage * bet_fraction_of_1_ETH
    uint256 reward = (poolBalance * bps * cappedBet) / (10_000 * 1 ether);
    if (reward == 0) return;

    sdgnrs.transferFromPool(IStakedDegenerusStonk.Pool.Reward, player, reward);
}
```

### Earlybird -> Lootbox Dump

```solidity
// DegenerusGameStorage.sol:1085-1101
if (currentLevel >= EARLYBIRD_END_LEVEL) {  // EARLYBIRD_END_LEVEL = 3
    // One-shot: dump remaining earlybird pool into reward pool  <-- STALE COMMENT (actually Lootbox)
    if (earlybirdDgnrsPoolStart != type(uint256).max) {
        earlybirdDgnrsPoolStart = type(uint256).max;
        IStakedDegenerusStonk dgnrsContract = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
        uint256 earlybirdRemaining = dgnrsContract.poolBalance(
            IStakedDegenerusStonk.Pool.Earlybird
        );
        if (earlybirdRemaining != 0) {
            dgnrsContract.transferBetweenPools(
                IStakedDegenerusStonk.Pool.Earlybird,
                IStakedDegenerusStonk.Pool.Lootbox,     // <-- Correct: Lootbox, not Reward
                earlybirdRemaining
            );
        }
    }
    return;
}
```

## State of the Art

| Old Approach (pre-split) | Current Approach (post-split) | When Changed | Impact |
|--------------------------|-------------------------------|--------------|--------|
| Single DegenerusStonk (soulbound) | sDGNRS (soulbound) + DGNRS (transferable wrapper) | v1.3 | Creator allocation now tradeable on secondary markets |
| burnForGame (per-address auth) | burnRemainingPools (game-only, burns all pools) | v1.3 | Cleaner game-over cleanup |
| Direct transfer to players | transferFromPool with return value | v1.3 | Graceful pool depletion handling |
| Single token supply tracking | Dual supply tracking (sDGNRS.totalSupply + DGNRS.totalSupply) | v1.3 | New invariant to verify |

## Open Questions

1. **sDGNRS.burn() reentrancy via claimWinnings**
   - What we know: sDGNRS.burn() calls `game.claimWinnings(address(0))` (line 405) AFTER state changes (lines 398-401) but BEFORE ETH transfer. The claimWinnings call sends ETH to sDGNRS via the game contract's payout mechanism.
   - What's unclear: Could `game.claimWinnings` re-enter sDGNRS? The game contract's claimWinnings sends ETH to the player (sDGNRS in this case) via the `receive()` function, which only emits an event. This appears safe but needs explicit verification.
   - Recommendation: Trace the full call path of `game.claimWinnings(address(0))` to verify no reentrancy window exists.

2. **coinflip.claimCoinflips re-entry risk during burn**
   - What we know: sDGNRS.burn() calls `coinflip.claimCoinflips(address(0), remainingBurnie)` (line 426) to withdraw BURNIE during the burn process. This is called after state changes.
   - What's unclear: Does claimCoinflips have any callback that could re-enter sDGNRS?
   - Recommendation: Verify BurnieCoinflip.claimCoinflips does not call back into sDGNRS.

3. **DGNRS receive() safety**
   - What we know: DGNRS has `receive() external payable {}` (line 79) to accept ETH from sDGNRS during burn-through.
   - What's unclear: Could anyone send ETH to DGNRS outside of the burn flow, permanently locking it?
   - Recommendation: Verify that any ETH sent to DGNRS can only be extracted via the burn-through mechanism. Stray ETH would benefit all DGNRS burners proportionally (since sDGNRS.burn sends ETH to DGNRS, then DGNRS forwards it).

4. **Pool balance consistency after burnRemainingPools**
   - What we know: burnRemainingPools burns `balanceOf[address(this)]` (all pool tokens held by sDGNRS contract). This should equal the sum of all poolBalances[].
   - What's unclear: Could poolBalances[] entries get out of sync with the actual balanceOf[address(this)]?
   - Recommendation: Prove that every poolBalances[] decrement is matched by a balanceOf[address(this)] decrement (this is done in transferFromPool lines 324-326).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Hardhat (Mocha/Chai) + Foundry (Forge) |
| Config file | hardhat.config.js + foundry.toml |
| Quick run command | `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js` |
| Full suite command | `npm test` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DELTA-01 | sDGNRS reentrancy, access control, reserves | manual audit + unit | `npx hardhat test test/unit/DegenerusStonk.test.js` | Yes |
| DELTA-02 | DGNRS ERC20, burn delegation, unwrapTo | manual audit + unit | `npx hardhat test test/unit/DGNRSLiquid.test.js` | Yes |
| DELTA-03 | Cross-contract supply sync | manual audit | manual-only: supply invariant proof is analytical, not automated | N/A |
| DELTA-04 | All game->sDGNRS callsites | manual audit | `npm test` (full suite catches regressions) | Yes (distributed) |
| DELTA-05 | payCoinflipBountyDgnrs gating | manual audit + unit | `npx hardhat test test/unit/BurnieCoinflip.test.js` | Yes |
| DELTA-06 | Degenerette reward math | manual audit | `npx hardhat test test/edge/GameOver.test.js` | Partial |
| DELTA-07 | Earlybird->Lootbox dump | manual audit | manual-only: comment/code mismatch is visual inspection | N/A |
| DELTA-08 | Pool BPS rebalance impact | manual audit | `npm test` (full suite) | Yes (distributed) |

### Sampling Rate
- **Per task commit:** `npx hardhat test test/unit/DegenerusStonk.test.js test/unit/DGNRSLiquid.test.js`
- **Per wave merge:** `npm test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None -- existing test infrastructure covers the code under review. This is an audit phase that produces findings reports, not new code. The existing 201 Hardhat tests and Foundry fuzz tests provide the regression baseline.

## Sources

### Primary (HIGH confidence)
- `contracts/StakedDegenerusStonk.sol` -- full contract read, 520 lines
- `contracts/DegenerusStonk.sol` -- full contract read, 177 lines
- `contracts/interfaces/IStakedDegenerusStonk.sol` -- full interface read
- `contracts/ContractAddresses.sol` -- all address constants
- `contracts/DegenerusGame.sol` -- payCoinflipBountyDgnrs, affiliate claim, stETH deposit
- `contracts/storage/DegenerusGameStorage.sol` -- earlybird logic, storage layout
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- DGNRS reward math
- `contracts/modules/DegenerusGameWhaleModule.sol` -- whale/deity pool distributions
- `contracts/modules/DegenerusGameLootboxModule.sol` -- lootbox DGNRS tier payouts
- `contracts/modules/DegenerusGameEndgameModule.sol` -- affiliate endgame rewards
- `contracts/modules/DegenerusGameJackpotModule.sol` -- final day DGNRS reward
- `contracts/modules/DegenerusGameGameOverModule.sol` -- burnRemainingPools, final sweep
- `contracts/BurnieCoinflip.sol` -- payCoinflipBountyDgnrs callsite
- `audit/v1.1-dgnrs-tokenomics.md` -- existing tokenomics documentation
- `audit/v1.1-parameter-reference.md` -- BPS constant reference
- `audit/KNOWN-ISSUES.md` -- prior findings (M-02 only, no DGNRS-related issues)
- `audit/FINAL-FINDINGS-REPORT.md` -- prior audit report (clean, no critical/high)

### Secondary (MEDIUM confidence)
- `test/unit/DGNRSLiquid.test.js` -- existing DGNRS wrapper tests
- `test/unit/DegenerusStonk.test.js` -- existing sDGNRS tests
- `.planning/REQUIREMENTS.md` -- DELTA-01 through DELTA-08 definitions

### Tertiary (LOW confidence)
- None. All findings based on direct source code analysis.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- direct source code analysis, no external dependencies to verify
- Architecture: HIGH -- full contract reads with cross-reference verification
- Pitfalls: HIGH -- identified from actual code patterns, not hypothetical
- Callsite inventory: HIGH -- exhaustive grep + manual verification of all sDGNRS interactions

**Research date:** 2026-03-16
**Valid until:** Indefinite (source code is the authoritative reference; valid until code changes)
