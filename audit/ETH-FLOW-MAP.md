# Degenerus Protocol — ETH Flow Map

**Refreshed:** v74.0 As-Built Milestone Audit (frozen `contracts/` tree `f06b1ef6` @ impl `93d17288`).
**Scope:** every ETH entry point, internal flow path, and exit point across the in-scope contracts.
Tokens renamed vs the v55-era map (BURNIE → FLIP, BurnieCoinflip → Coinflip, StakedDegenerusStonk →
sDGNRS, DegenerusStonk → DGNRS, WrappedWrappedXRP → WWXRP); `EndgameModule` removed (folded into
Advance/GameOver/Jackpot); DGVE/DGVF are the vault's internal share classes. New flows folded in: the
**sDGNRS level-start lootbox** (claimable → box prize pool), **caller-funded gift** placement
(spend = funder), **afking funding** deposits, **partial `claimWinnings`**, and the **gas faucet**
(donation → distribute), which is value-isolated from protocol backing.

---

## Executive summary

ETH lives primarily in `DegenerusGame`, with token-mediated flows through `DegenerusVault`, `sDGNRS`,
`DGNRS`, and four token contracts (FLIP, sDGNRS, DGNRS, WWXRP).

**Master solvency invariant (SOLV-01):** the game's live ETH balance always covers its canonical
obligation set — LIVE: `currentPrizePool + nextPrizePool + futurePrizePool + claimablePool + yieldAcc…`;
at gameOver: `claimablePool`. Backed by `eth_getBalance(game) + stETH.balanceOf(game)`.

This holds because:
1. Every ETH entry adds to both the contract balance AND pool accounting.
2. Every ETH exit deducts from pool accounting BEFORE sending ETH (CEI).
3. Integer division rounds toward the protocol (remainders stay in the source pool).
4. stETH positive rebases create surplus (yield); negative rebases are absorbed by an 8% buffer.

The **gas faucet is outside this system**: it custodies only externally-donated ETH (its only inflow
is `receive()`), has no pool accounting, and cannot touch protocol backing.

---

## Part 1: ETH entry points

| # | Entry | Contract | Handler | Destination |
|---|-------|----------|---------|-------------|
| 1 | Ticket purchase | Game | `purchase()` (MintModule) | next/future split (`_addPrizeContribution`), `claimablePool` (affiliate + vault), vault ETH share |
| 2 | Whale pass | Game | `purchaseWhalePass()` (WhaleModule) | prize pools + claimablePool |
| 3 | Lazy pass | Game | `purchaseLazyPass()` (WhaleModule) | prize pools + claimablePool |
| 4 | Deity pass | Game | `purchaseDeityPass()` (WhaleModule) | prize pools + claimablePool |
| 5 | Degenerette bet (ETH leg) | Game | `placeDegeneretteBet()` (DegeneretteModule) | prize-pool ETH-bet contribution |
| 6 | Afking funding | Game | `depositAfkingFunding(player)` | player afking-funding balance (caller-funded; credited to player) |
| 7 | Direct ETH send | Game | `receive()` | `prizePoolsPacked` (future), or `prizePoolPendingPacked` if frozen |
| 8 | Vault deposit / receive | Vault | `deposit()` / `receive()` | vault ETH reserve |
| 9 | sDGNRS receive | sDGNRS | `receive()` | sDGNRS ETH reserve (DGNRS-burn flow) |
| 10 | DGNRS receive | DGNRS | `receive()` | DGNRS balance (from sDGNRS during burn) |
| 11 | Admin receive | Admin | `receive()` | best-effort forwarded to VAULT (never reverts; VRF cancel-refund safety) |
| 12 | Gas-faucet donation | GasFaucet | `receive()` | faucet balance (isolated; not protocol backing) |

### Ticket purchase (primary entry #1)

`purchase()` splits `msg.value` via the as-built hot-path fold (`_purchaseForWithCached`): a single
combined prize-pool RMW (`_addPrizeContribution`) and a single aggregate `claimablePool` decrement
(`_settleShortfallNoPool`) instead of per-leg writes.

```
msg.value
  ├─► nextPrizePool / futurePrizePool   (one _addPrizeContribution)
  ├─► claimablePool                      (winners' claimable)
  ├─► Vault (ETH share)                  (fixed % of purchase)
  ├─► Affiliate commission (if referred) (FLIP coin credit via creditFlipBatch — payAffiliateCombined)
  └─► yieldAccumulator                   (stETH yield tracking)
```

The combined affiliate roll `payAffiliateCombined` returns a **FLIP `winnerCredit`** (coin, never
ETH-backed) credited by the MintModule caller in one `creditFlipBatch([buyer, affWinner])` — it moves
0 ETH (SOLV-08 / SOLV-04).

---

## Part 2: internal ETH flow

### Prize-pool progression

```
futurePrizePool ──[consolidate]──► nextPrizePool ──[level transition]──► currentPrizePool
   ▲ purchase splits, auto-rebuy,                                          │
   │ direct sends, yield surplus                  [payDailyJackpot,        │
                                                   runRewardJackpots]      ▼
                                            claimableWinnings[player] ──[claimWinnings]──► player wallet
```

`prizePoolFrozen` brackets the advance jackpot math; direct ETH sent during a freeze accrues in
`prizePoolPendingPacked` and applies when the freeze lifts. **GameOver freeze-clear:** every
game-over path zeroes `prizePoolPendingPacked` and clears `prizePoolFrozen` before any
`_unfreezePool` / post-gameover resolution, so zeroed pools cannot be resurrected (SOLV-07).

### sDGNRS level-start lootbox (new flow)

Once per level, during the pre-RNG subscriber stage (`GameAfkingModule._runSubscriberStage`):

```
LIVE cl = _claimableOf(SDGNRS)
box = min(cl/20, 6 ether), floored at mp           (5% of sDGNRS claimable, capped 6 ETH)
  ├─► claimablePool       -= box                    (claimableUse = box)
  └─► box prize pool      += box                    (_routeAfkingPoolEth(box, 0))
```

Conservation: the `claimablePool` debit exactly equals the box prize-pool credit; the `cl > mp` guard
keeps the 1-wei sentinel (`box <= cl-1`), so `claimablePool >= Σ claimable` holds (SOLV-05/SOLV-07).
Sized strictly before the day's word is requested; a once-per-level latch (`currentLevel >
_sdgnrsBonusLevel`) blocks re-sizing (RNG-04, see KNOWN-ISSUES §3b).

### Caller-funded gift placement (new flow — token, not ETH-pool)

`Coinflip.depositCoinflip(player, amount)` / Degenerette gift: the FLIP principal is burned from the
**funder** (`= msg.sender` on the gift branch; `= player` when self/operator-approved); the
stake/position belongs to `player`. WWXRP is gift-excluded. No non-consenting party's FLIP is spent
(ACCESS-01).

### Auto-rebuy diversion & yield surplus

```
claimableWinnings[player] ──[_processAutoRebuy]──► futurePrizePool (rebuy ticket ETH) + claimableDelta to player
stETH positive rebase ──[_distributeYieldSurplus]──► stakeholderShare → Vault + sDGNRS;  accumulatorShare → yieldAccumulator → futurePrizePool
```

8% of yield is left unextracted to absorb negative rebases.

---

## Part 3: ETH exit points

| # | Exit | Contract | Function | Source |
|---|------|----------|----------|--------|
| 1 | Claim winnings (ETH first) | Game | `claimWinnings(player)` | `claimableWinnings[player]` |
| 2 | Claim winnings (partial) | Game | `claimWinnings(player, maxClaim)` | capped slice; sentinel kept pre-gameOver; cap ignored post-gameOver (SOLV-06) |
| 3 | Claim winnings (stETH first) | Game | `claimWinningsStethFirst()` | stETH transferred first, ETH for remainder |
| 4 | Withdraw afking funding | Game | `withdrawAfkingFunding(amount)` | own afking-funding balance |
| 5 | Vault share burn (ETH) | Vault | `burnEth(uint256)` | proportional DGVE ETH reserve |
| 6 | sDGNRS claim redemption | sDGNRS | `claimRedemption(player, day)` | `pendingRedemptionEthValue` (delete-before-pay) |
| 7 | sDGNRS / DGNRS burn | sDGNRS/DGNRS | `burn()` | proportional ETH+stETH+FLIP backing |
| 8 | Game-over drain → Vault | Game | GameOverModule | surplus ETH after all claims allocated |
| 9 | Game-over drain → sDGNRS | Game | GameOverModule | surplus ETH for sDGNRS reserve |
| 10 | Vault ETH share | Game | `purchase()` (MintModule) | fixed % of purchase `msg.value` |
| 11 | Admin → Vault forward | Admin | `receive()` | stray/VRF-refund native (never reverts) |
| 12 | Faucet distribute / withdraw | GasFaucet | `distribute` / `withdraw` | donated ETH only (isolated) |

### Claim flow (CEI)

```
claimWinnings(player[, maxClaim])
  1. claimablePool -= payout         (effect)
  2. claimableWinnings[player] -= payout / = 0
  3. .call{value: payout}            (interaction)
  (stETH-first: transfer stETH, then ETH for remainder)
```

### Game-over drain

```
handleGameOverDrain()
  1. deity-pass refunds → claimableWinnings[deityOwners]
  2. remaining ETH split → Vault (ETH) + sDGNRS (ETH) + stETH transfer to Vault
```

---

## Part 4: token supply flows

### FLIP (formerly BURNIE)

```
Mint:  mintForGame [GAME] · creditFlip/creditFlipBatch [GAME/COINFLIP] · vaultMintTo [VAULT] · mintForCoinflip [COINFLIP]
Burn:  burnForCoinflip [COINFLIP] · decimatorBurn/terminalDecimatorBurn [GAME] · burnCoin/burnCoinForSalvage [GAME]
Neutral: transfer/transferFrom (transfer-to-VAULT BURNS → virtual vaultAllowance) · vaultEscrow [VAULT]
Invariant (COIN-01): totalSupply + vaultMintAllowance == supplyIncUncirculated  (always)
```

### sDGNRS (soulbound)

```
Mint:  depositSteth / gameDeposit [GAME]
Burn:  burn / burnWrapped [permissionless, own] · gambling/redemption resolution [GAME]
Neutral: transferFromPool / transferBetweenPools [GAME] · wrapperTransferTo [DGNRS]
Backed by: ETH + stETH + claimable ETH + FLIP reserves; REDEEM-01 segregates redemption ETH.
```

### DGNRS (wrapper)

```
No runtime mint (constructor + creator vesting). Burn: burn [permissionless → sDGNRS backing] · burnForSdgnrs [sDGNRS].
unwrapTo [CREATOR]. Backed by sDGNRS held by the DGNRS contract.
```

### WWXRP

```
Mint: mintPrize [GAME/COIN/COINFLIP/VAULT] (intentionally unbacked) · vaultMintTo [VAULT] · wrap [1:1 wXRP]
Burn: unwrap [first-come vs wXRPReserves] · burnForGame [GAME] · burn [own]
Model: intentionally undercollateralized; value = whale-pass position, not redeemability (see KNOWN-ISSUES §2).
```

### DGVE / DGVF (vault share classes)

```
Mint/Burn: vaultMint / vaultBurn [VAULT only]. DGVE (ETH+stETH claims) standard ERC-20; DGVF soulbound.
Vault-owner role = > 50.1% of DGVE supply.
```

---

## Part 5: conservation

### ETH conservation (proof sketch)

1. **Entry:** every ETH entry adds to `address(this).balance` AND ≥1 pool variable.
2. **Exit:** every ETH exit deducts pool accounting BEFORE the send (CEI) — e.g. `claimWinnings`
   decrements `claimablePool` before `.call{value}`.
3. **Internal zero-sum:** future → next → current → claimable are zero-sum; auto-rebuy and the sDGNRS
   box are internal claimable↔pool transfers (creation/destruction-free).
4. **Rounding:** integer divisions floor; remainders stay in the source pool (solvency strengthened).
5. **stETH rebase:** positive rebases add backing without adding obligations (surplus); negative
   rebases are absorbed by the 8% buffer.

### Rounding behavior

| Operation | Direction | Effect |
|-----------|-----------|--------|
| Prize-pool BPS splits | Floor | Remainders stay in source (surplus) |
| sDGNRS box (`cl/20`, cap 6 ETH) | Floor + `cl>mp` guard | 1-wei sentinel preserved |
| Auto-rebuy ticket conversion | Floor | Sub-ticket dust dropped (documented) |
| sDGNRS / DGNRS proportional burn | Floor | Favors remaining holders |
| Vault (DGVE) share burn | Floor | Favors vault |
| Coinflip payout division | Floor | Favors protocol |
| stETH 1:1 transfer | 1–2 wei retained | Strengthens solvency |

---

*ETH flow map refreshed for the v74.0 frozen subject (`f06b1ef6` @ `93d17288`). Pool/exit mechanics
verified against the in-scope sources; the sDGNRS level-lootbox, caller-funded gift, partial-claim,
afking-funding, and gas-faucet flows folded in. Conservation cross-references the MAN-01 invariant
manifest (SOLV-01..08, REDEEM-01, COIN-01).*
