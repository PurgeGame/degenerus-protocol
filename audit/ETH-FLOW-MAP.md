# Degenerus Protocol -- ETH Flow Map

**Audit Date:** 2026-03-25
**Source:** v5.0 Ultimate Adversarial Audit, 16 unit phases (103-118)
**Scope:** Every ETH entry point, internal flow path, and exit point across the protocol

---

## Executive Summary

The Degenerus Protocol manages ETH across 4 primary contracts (DegenerusGame, DegenerusVault, StakedDegenerusStonk, DegenerusStonk) with additional token flows through 4 token contracts (BURNIE, sDGNRS, DGNRS, WWXRP).

**Conservation invariant:** `Game.balance + Game.stethBalance >= claimablePool`

This invariant holds because:
1. Every ETH entry adds to both contract balance AND pool accounting
2. Every ETH exit deducts from claimablePool BEFORE sending ETH (CEI pattern)
3. Integer division rounding favors the protocol (remainders stay in source pool)
4. stETH positive rebases create surplus (yield); negative rebases absorbed by 8% buffer

**Verification status:** PROVEN across all 10 entry points and 9 exit points (Unit 16 integration analysis).

---

## Part 1: ETH Entry Points (10)

| # | Entry | Contract | Handler | Destination Pool/Balance | Unit |
|---|-------|----------|---------|-------------------------|------|
| 1 | Ticket purchase | Game | `purchaseFor()` (MintModule) | `prizePoolsPacked` (next + future split), `claimablePool` (affiliate + vault), vault ETH share | 5 |
| 2 | Whale bundle purchase | Game | `purchaseWhaleBundle()` (WhaleModule) | `prizePoolsPacked`, `claimablePool` | 6 |
| 3 | Lazy pass purchase | Game | `purchaseLazyPass()` (WhaleModule) | `prizePoolsPacked`, `claimablePool` | 6 |
| 4 | Deity pass purchase | Game | `purchaseDeityPass()` (WhaleModule) | `prizePoolsPacked`, `claimablePool` | 6 |
| 5 | Degenerette bet (ETH portion) | Game | `placeFullTicketBets()` (DegeneretteModule) | `prizePoolsPacked` (ETH bet pool contribution) | 8 |
| 6 | Direct ETH send | Game | `receive()` | `prizePoolsPacked` (future) or `prizePoolPendingPacked` (if frozen) | 1 |
| 7 | Vault deposit | Vault | `deposit()` | Vault ETH reserve (`address(this).balance`) | 12 |
| 8 | sDGNRS ETH receive | sDGNRS | `receive()` | sDGNRS ETH reserve (only from DGNRS burn flow) | 11 |
| 9 | DGNRS ETH receive | DGNRS | `receive()` | DGNRS contract balance (only from sDGNRS during burn) | 11 |
| 10 | Vault ETH receive | Vault | `receive()` | Vault ETH reserve (game-over surplus) | 12 |

### Ticket Purchase Flow (Primary Entry -- Entry #1)

The largest ETH flow. Each `purchaseFor()` call splits `msg.value` into multiple destinations:

```
msg.value
  |
  +---> nextPrizePool (via prizePoolsPacked)     -- portion for next level's prize pool
  +---> futurePrizePool (via prizePoolsPacked)   -- portion for future levels
  +---> claimablePool                             -- claimable by winners
  +---> Vault (ETH send)                          -- vault share (fixed % of purchase)
  +---> Affiliate commission (if referred)         -- via BURNIE creditFlip
  +---> yieldAccumulator                          -- stETH yield tracking
```

### Whale/Pass Purchase Flow (Entries #2-4)

Similar split to ticket purchase but with fixed prices:
- Whale bundle: 4 ETH base (2.4 ETH at early levels)
- Lazy pass: 10-level pass price
- Deity pass: Quadratic pricing (24+ ETH, increases with pass count)

---

## Part 2: Internal ETH Flow (Prize Pool Chain)

### Pool Progression

```
                    +-------------------+
                    | futurePrizePool   |  <-- Receives: purchase splits, auto-rebuy,
                    | (packed in slot 3)|      direct sends, yield surplus distribution
                    +--------+----------+
                             |
                    [consolidatePrizePools - JackpotModule]
                             |
                    +--------v----------+
                    | nextPrizePool     |  <-- Receives: promoted from future at level end
                    | (packed in slot 3)|
                    +--------+----------+
                             |
                    [level transition - EndgameModule]
                             |
                    +--------v----------+
                    | currentPrizePool  |  <-- Receives: promoted from next at new level
                    | (slot 2)          |      Active prize pool for jackpot distribution
                    +--------+----------+
                             |
                    [payDailyJackpot - JackpotModule]
                    [runRewardJackpots - EndgameModule]
                             |
                    +--------v----------+
                    | claimableWinnings |  <-- Per-player claimable balances
                    | [address]         |      Written by _addClaimableEth helper
                    +--------+----------+
                             |
                    [claimWinnings / claimWinningsStethFirst - Game router]
                             |
                    +--------v----------+
                    | Player wallet     |  <-- ETH sent via .call{value}
                    +-------------------+
```

### Auto-Rebuy Diversion

When a player has auto-rebuy enabled, a portion of their claimable winnings is diverted:

```
claimableWinnings[player]
  |
  +---> [_addClaimableEth -> _processAutoRebuy - JackpotModule]
  |       |
  |       +---> futurePrizePool (auto-rebuy ticket ETH)
  |       +---> return claimableDelta (remaining for player)
  |
  +---> claimablePool += claimableDelta
```

The rebuyDelta reconciliation mechanism (EndgameModule L244-246) ensures all auto-rebuy writes during BAF/Decimator resolution are correctly captured.

### Yield Surplus Distribution

stETH rebases create yield surplus that is distributed:

```
stETH positive rebase
  |
  +---> [_distributeYieldSurplus - JackpotModule]
         |
         +---> stakeholderShare -> Vault (ETH send) + sDGNRS (ETH send)
         +---> accumulatorShare -> yieldAccumulator -> futurePrizePool
```

8% buffer is left unextracted to absorb potential negative rebases.

### Prize Pool Freeze Mechanism

During `advanceGame()` jackpot math, pools are frozen to prevent concurrent writes:

```
prizePoolFrozen = true
  |
  +---> [JackpotModule operations: payDailyJackpot, processTicketBatch, etc.]
  |
prizePoolFrozen = false
```

Any direct ETH sends (`receive()`) during freeze are accumulated in `prizePoolPendingPacked` and applied when the freeze lifts.

---

## Part 3: ETH Exit Points (9)

| # | Exit | Contract | Function | Source Pool | Unit |
|---|------|----------|----------|-------------|------|
| 1 | Claim winnings (ETH first) | Game | `claimWinnings(address)` | `claimableWinnings[player]` | 1 |
| 2 | Claim winnings (stETH first) | Game | `claimWinningsStethFirst(address)` | `claimableWinnings[player]` (stETH transferred first, ETH for remainder) | 1 |
| 3 | Vault share burn (ETH) | Vault | `burnEth(uint256)` | Proportional vault ETH reserve | 12 |
| 4 | sDGNRS claim redemption | sDGNRS | `claimRedemption()` | `pendingRedemptionEthValue` | 11 |
| 5 | sDGNRS deterministic burn | sDGNRS | `burn()` -> `_deterministicBurnFrom()` | Proportional `totalMoney` (ETH + stETH + claimable) | 11 |
| 6 | DGNRS burn | DGNRS | `burn()` -> sDGNRS.burn() | Via sDGNRS burn path | 11 |
| 7 | Game-over drain to Vault | Game | `handleGameOverDrain()` (GameOverModule) | Surplus ETH after all claims allocated | 4 |
| 8 | Game-over drain to sDGNRS | Game | `handleGameOverDrain()` (GameOverModule) | Surplus ETH for sDGNRS reserve | 4 |
| 9 | Vault share to MintModule | Game | `_purchaseFor()` (MintModule) | `vaultShare` (fixed % of purchase msg.value) | 5 |

### Claim Winnings Flow (Exits #1-2)

```
claimWinnings(player)
  |
  1. claimablePool -= payout         [CEI: effect before interaction]
  2. claimableWinnings[player] = 0   [CEI: effect before interaction]
  3. Send ETH via .call{value}       [interaction]
  |
  If stETH-first: transfer stETH first, then ETH for remainder
```

### Game-Over Drain (Exits #7-8)

At game-over, all remaining ETH is drained:

```
handleGameOverDrain()
  |
  1. Deity pass refunds -> claimableWinnings[deityOwners]
  2. Remaining ETH split:
     +---> Vault (ETH send)  -- surplus for shareholders
     +---> sDGNRS (ETH send) -- surplus for token holders
     +---> stETH transfer to Vault
```

---

## Part 4: Token Supply Flows

### BURNIE (BurnieCoin)

```
Minting (supply increase):
  +---> mintForGame(to, amount)        [GAME only - jackpot rewards, streak bonuses]
  +---> mintForCoinflip(to, amount)    [COINFLIP only - coinflip payouts]
  +---> vaultMintTo(to, amount)        [VAULT only - vault BURNIE distribution]
  +---> creditCoin/creditFlip(to, amt) [GAME/COINFLIP - flip credits]

Burning (supply decrease):
  +---> burnForCoinflip(from, amount)  [COINFLIP only - coinflip deposits]
  +---> decimatorBurn(from, amount)    [GAME only - decimator entry burns]
  +---> terminalDecimatorBurn(from, amt) [GAME only - terminal dec burns]

Internal transfer (supply neutral):
  +---> transfer/transferFrom          [Standard ERC20]
  +---> vaultEscrow(from, amount)      [VAULT only - redirect to vault escrow]

Supply invariant: totalSupply + vaultAllowance is conserved across all vault redirect paths.
Authorized minters: GAME, COINFLIP, VAULT, ADMIN (4 compile-time constants).
```

### sDGNRS (StakedDegenerusStonk)

```
Minting (supply increase):
  +---> gameDeposit(amount)            [GAME only - pool allocation]
  +---> deposit(amount)                [GAME only - direct deposit]

Burning (supply decrease):
  +---> burn(amount)                   [Permissionless - deterministic burn]
  +---> burnWrapped(amount)            [Permissionless - wrapped burn]
  +---> _deterministicBurnFrom()       [Internal - proportional ETH/stETH/BURNIE payout]
  +---> _submitGamblingClaimFrom()     [Internal - gambling burn with VRF resolution]

Pool transfers (supply neutral):
  +---> transferFromPool(pool, to, amt) [GAME only - pool to player]
  +---> transferBetweenPools(from, to)  [GAME only - pool rebalancing]
  +---> wrapperTransferTo(to, amount)   [DGNRS only - unwrap to sDGNRS]

Three pools: Whale, Affiliate, Claims. All game-controlled.
Supply is backed by: ETH + stETH + claimable ETH (from Game) + BURNIE reserves.
```

### DGNRS (DegenerusStonk)

```
No runtime minting. Supply set at construction. Monotonically decreasing.

Burning (supply decrease):
  +---> burn(amount)                   [Permissionless after gameOver - burns sDGNRS proportionally]
  +---> burnForSdgnrs(addr, amount)    [sDGNRS only - cross-contract burn path]

Transfer (supply neutral):
  +---> transfer/transferFrom          [Standard ERC20]
  +---> unwrapTo(to, amount)           [CREATOR only - transfers underlying sDGNRS]

Backed by: sDGNRS tokens held by DGNRS contract (wrapping layer).
```

### WWXRP (WrappedWrappedXRP)

```
Minting (supply increase -- intentionally undercollateralized):
  +---> mintPrize(to, amount)          [GAME/COIN/COINFLIP/VAULT - game rewards]
  +---> wrap(amount)                   [Permissionless - 1:1 backed by wXRP deposit]

Burning (supply decrease):
  +---> unwrap(amount)                 [Permissionless - redeems against wXRPReserves]
  +---> burn(amount)                   [Permissionless - burns own tokens]

Supply model: Intentionally undercollateralized. mintPrize creates unbacked tokens.
wXRPReserves tracks actual wXRP backing. unwrap is first-come-first-served.
```

---

## Part 5: Conservation Proofs

### ETH Conservation

**Proof sketch (from Unit 16 integration analysis):**

1. **Entry addition:** Every ETH entry point adds to both `address(this).balance` and at least one pool variable (prizePoolsPacked, claimablePool, etc.)

2. **Exit subtraction:** Every ETH exit deducts from pool accounting BEFORE sending ETH:
   - `claimWinnings`: `claimablePool -= payout` at L1370 before `.call{value}` at L1374
   - `burnEth`: shares burned at L867 before ETH send at L875
   - `claimRedemption`: `pendingRedemptionEthValue -= ethPayout` before send

3. **Internal zero-sum:** Pool transitions (future -> next -> current -> claimable) are zero-sum transfers. Auto-rebuy diverts claimable -> future (internal, not creation/destruction).

4. **Rounding direction:** All integer divisions in pool splits round DOWN (Solidity default). Remainders stay in source pool. Protocol retains more ETH than accounting suggests (solvency strengthened).

5. **stETH rebase:** Positive rebases increase `steth.balanceOf(Game)` without increasing pools (surplus). Negative rebases decrease balance without decreasing pools (potential deficit, absorbed by 8% buffer).

### Token Supply Conservation

| Token | Mint Authority | Burn Paths | Invariant |
|-------|---------------|------------|-----------|
| BURNIE | GAME, COINFLIP, VAULT, ADMIN | COINFLIP (deposits), GAME (decimator) | `totalSupply + vaultAllowance` conserved across vault redirects |
| DGNRS | None (constructor only) | `burn`, `burnForSdgnrs` | Supply monotonically decreasing |
| sDGNRS | GAME only (deposit) | `burn`, `burnWrapped`, `_deterministicBurnFrom` | Backed by proportional `totalMoney` |
| WWXRP | 4 authorized callers | `unwrap`, `burn` | Intentionally undercollateralized (documented design) |

### Rounding Behavior

| Operation | Rounding Direction | Effect |
|-----------|-------------------|--------|
| Prize pool splits (BPS) | Floor (Solidity default) | Remainders stay in source pool (protocol surplus) |
| Auto-rebuy ticket conversion | Floor | Dust < ticketPrice/4 dropped (documented, I-08) |
| sDGNRS proportional burn | Floor | Rounding favors remaining holders |
| Vault share burn | Floor | Rounding favors vault |
| Coinflip payout division | Floor | Rounding favors protocol |
| stETH 1:1 minting | 1-2 wei rounding | Strengthens solvency invariant |

---

## Part 6: Flow Diagrams

### Complete ETH Lifecycle

```
[Player msg.value]
       |
       v
  DegenerusGame
       |
  +----+----+----+----+
  |    |    |    |    |
  v    v    v    v    v
 fut  next  cp  vault yield
 Pool Pool      |     |
  |    |        |     |
  +--->+        |   stETH
       |        |   rebase
       v        |     |
  currentPrize  |     v
  Pool          |  yieldAccum
       |        |     |
       v        |     v
  claimable     |  futurePrize
  Winnings      |  Pool (cycle)
  [per player]  |
       |        |
       v        v
  [ETH send]  [Vault ETH reserve]
  to player    |
               v
            [burnEth]
            to shareholder

Legend:
  fut = futurePrizePool
  next = nextPrizePool
  cp = claimablePool
```

### Game-Over Terminal Flow

```
[Game Over triggered]
       |
       v
  handleGameOverDrain()
       |
  +----+----+----+
  |         |    |
  v         v    v
 Deity    Vault  sDGNRS
 refunds  (ETH)  (ETH)
  |         |      |
  v         |      v
 claimable  |   sDGNRS
 Winnings   |   reserve
  |         |      |
  v         v      v
 [claim]  [burnEth] [burn/claim]
```

---

*ETH flow map compiled from 16 unit audits, v5.0 Ultimate Adversarial Audit.*
*Phase 119 deliverable DEL-04.*
*Date: 2026-03-25*
