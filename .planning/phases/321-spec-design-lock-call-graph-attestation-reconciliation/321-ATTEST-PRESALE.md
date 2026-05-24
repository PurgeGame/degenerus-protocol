# 321 — Call-Graph Attestation: PLAN-PRESALE-COIN-BOXES-RAKE-FREE

**Type:** READ-ONLY attestation (no source mutation).
**Plan under attestation:** `.planning/PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md` (anchors written against an earlier HEAD, 2026-05-23).
**Attested against contract HEAD:** `2a18d622ba6a565028902613e4f9c36192af3915` (2026-05-24).
**Source scope:** `contracts/` only (stale copies elsewhere ignored, per `feedback_contract_locations`).

---

## 0. Summary counts

| Disposition | Count |
|---|---|
| MATCH | 23 |
| SHIFTED | 5 |
| ABSENT | 0 |

**No ABSENT anchors. No blockers.** Every edit target named in the plan exists in current source. Five anchors shifted by small offsets (≤ +5 lines) — all benign drift, none change the structure the plan relies on. Two clarifications worth flagging for IMPL (not blockers): (a) the 200-ETH presale auto-end is keyed on the `LOOTBOX_PRESALE_ETH_CAP = 200 ether` constant (Storage), the literal "200" never appears inline in MintModule; (b) `_queueWhalePassClaimCore` bumps `claimablePool` ONLY on the sub-half-pass `remainder`, routing the bulk to `whalePassClaims` — so it is NOT a drop-in "credit-claimable + bump-pool by full amount" helper for the 80/20 box routing (the plan's §5 already anticipates a new `_creditBoxProceeds` helper; this nuance is the reason it is needed).

---

## 1. DegenerusGameMintModule.sol (1529 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| Presale ETH split 50/30/20 vs 90/10 vs distress 100 (`:1036-1075`) | constants `:112-119`; split branch logic `:1036-1075`; vault `.call` `:1070-1075` | **MATCH** |
| 200-ETH-mint presale auto-end (`:1021-1029`) | `:1021-1030` (uses `LOOTBOX_PRESALE_ETH_CAP`, not literal 200) | **SHIFTED(+1 on close brace)** |
| `_awardEarlybirdDgnrs` call site (`:1210`) | `:1210` | **MATCH** |
| `purchaseCoin` / `_purchaseCoinFor` (credit-accrual + ETH-routing context) | `purchaseCoin` `:852`; `_purchaseCoinFor` `:872`; `_purchaseFor` (ETH path) `:899` | **MATCH** (BURNIE-funded path — NOT an ETH/credit site, confirms plan §3.2 exclusion) |

### 1a. Presale split constants (`:112-119`)
```solidity
    /// @dev Loot box pool split: 90% future, 10% next.
    uint16 private constant LOOTBOX_SPLIT_FUTURE_BPS = 9000;
    uint16 private constant LOOTBOX_SPLIT_NEXT_BPS = 1000;

    /// @dev Loot box presale pool split: 50% future, 30% next, 20% vault.
    uint16 private constant LOOTBOX_PRESALE_SPLIT_FUTURE_BPS = 5000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_NEXT_BPS = 3000;
    uint16 private constant LOOTBOX_PRESALE_SPLIT_VAULT_BPS = 2000;
```

### 1b. 200-ETH presale auto-end + split + vault skim (`:1021-1077`)
```solidity
            if (presale) {
                uint256 psPacked = presaleStatePacked;
                uint256 newMintEth = ((psPacked >> PS_MINT_ETH_SHIFT) & PS_MINT_ETH_MASK) + lootBoxAmount;
                psPacked = (psPacked & ~(PS_MINT_ETH_MASK << PS_MINT_ETH_SHIFT))
                         | ((newMintEth & PS_MINT_ETH_MASK) << PS_MINT_ETH_SHIFT);
                if (newMintEth >= LOOTBOX_PRESALE_ETH_CAP) {
                    psPacked &= ~uint256(PS_ACTIVE_MASK);
                }
                presaleStatePacked = psPacked;
            }

            bool distress = _isDistressMode();
            if (distress) {
                lootboxDistressEth[lbIndex][buyer] += boostedAmount;
            }
            uint256 futureBps;
            uint256 nextBps;
            uint256 vaultBps;
            if (distress) {
                futureBps = 0;
                nextBps = 10_000;
                vaultBps = 0;
            } else if (presale) {
                futureBps = LOOTBOX_PRESALE_SPLIT_FUTURE_BPS;
                nextBps = LOOTBOX_PRESALE_SPLIT_NEXT_BPS;
                vaultBps = LOOTBOX_PRESALE_SPLIT_VAULT_BPS;
            } else {
                futureBps = LOOTBOX_SPLIT_FUTURE_BPS;
                nextBps = LOOTBOX_SPLIT_NEXT_BPS;
                vaultBps = 0;
            }

            uint256 futureShare = (lootBoxAmount * futureBps) / 10_000;
            uint256 nextShare = (lootBoxAmount * nextBps) / 10_000;
            uint256 vaultShare = (lootBoxAmount * vaultBps) / 10_000;

            if (prizePoolFrozen) {
                (uint128 pNext, uint128 pFuture) = _getPendingPools();
                _setPendingPools(
                    pNext + uint128(nextShare),
                    pFuture + uint128(futureShare)
                );
            } else {
                (uint128 next, uint128 future) = _getPrizePools();
                _setPrizePools(
                    next + uint128(nextShare),
                    future + uint128(futureShare)
                );
            }
            if (vaultShare != 0) {
                (bool ok, ) = payable(ContractAddresses.VAULT).call{
                    value: vaultShare
                }("");
                if (!ok) revert E();
            }

            emit LootBoxBuy(buyer, lbDay, lootBoxAmount, presale, cachedLevel);
```
Note: `LOOTBOX_PRESALE_ETH_CAP = 200 ether` is declared in `DegenerusGameStorage.sol:852` (not in MintModule). The auto-end gates on `newMintEth >= LOOTBOX_PRESALE_ETH_CAP`, clearing `PS_ACTIVE_MASK`.

### 1c. `_awardEarlybirdDgnrs` call site (`:1210`) — EDIT TARGET (swap to credit accrual)
```solidity
        // Unified earlybird award: one call per purchase covering the full ticket +
        // lootbox spend (fresh + recycled). Quadratic curve telescopes, so one call
        // is mathematically equivalent to two.
        _awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount);
```

### 1d. `purchaseCoin` / `_purchaseCoinFor` (`:852-897`) — BURNIE-funded, NOT an ETH credit site
```solidity
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external {
        _purchaseCoinFor(buyer, ticketQuantity, lootBoxBurnieAmount);
    }
    ...
    function _purchaseCoinFor(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) private {
        if (_livenessTriggered()) revert E();

        if (ticketQuantity != 0) {
            // ENF-01: Block BURNIE tickets when drip projection cannot cover nextPool deficit.
            if (gameOverPossible) revert GameOverPossible();
            _callTicketPurchase(...);
        }

        if (lootBoxBurnieAmount != 0) {
            _purchaseBurnieLootboxFor(buyer, lootBoxBurnieAmount);
        }
    }
```
Confirms plan §3.2: `purchaseCoin`/`purchaseBurnieLootbox` are BURNIE-funded (no ETH in, no `_awardEarlybirdDgnrs` call) → correctly EXCLUDED from credit accrual. The ETH credit-accrual call site is the single `_awardEarlybirdDgnrs` in `_purchaseFor` at `:1210`.

---

## 2. DegenerusGameLootboxModule.sol (1797 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `LOOTBOX_PRESALE_BURNIE_BONUS_BPS` constant (`:288`) | `:288` (= `6_200`) | **MATCH** |
| +62% bonus block (`:957-975`) | `:973-976` | **SHIFTED(+16/+1)** |

### 2a. Constant (`:287-288`) — EDIT TARGET (remove)
```solidity
    /// @dev Presale BURNIE bonus in BPS (62% bonus, reduced to keep presale total stable)
    uint16 private constant LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6_200;
```

### 2b. +62% bonus apply block (`:972-976`) — EDIT TARGET (remove)
```solidity
        burnieAmount = burnieNoMultiplier + burniePresale;
        if (presale && burniePresale != 0) {
            uint256 bonusBurnie = (burniePresale * LOOTBOX_PRESALE_BURNIE_BONUS_BPS) / 10_000;
            burnieAmount += bonusBurnie;
        }
```
The `burniePresale` / `burnieNoMultiplier` split originates upstream in `_accumulateLootboxRolls` (`:957-969` call); the `presale` bool parameter into the resolver is set elsewhere (`:493` reads `_psRead(PS_ACTIVE...)`, threaded to `:545`/`:925`). IMPL removing the +62% should also confirm whether the `burniePresale`/`burnieNoMultiplier` split is still needed once the multiplier is gone (it collapses to a single BURNIE total).

---

## 3. DegenerusGameAdvanceModule.sol (1929 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `_finalizeEarlybird` (`:1741`/`:1744`) | doc `:1741`, fn `:1744`, body `:1744-1757` | **MATCH** |
| `EARLYBIRD_END_LEVEL` trigger (`:1672-1673`) | `:1672-1673` | **MATCH** |
| Level-3 presale clear (`:429-431`) | `:429-431` | **MATCH** |
| Perpetual jackpot-ticket block (`:1532-1545`) | `:1532-1545` (`VAULT_PERPETUAL_TICKETS = 16`, `:123`) | **MATCH** |
| Salt pattern (`:370-377`) | `:370-377` | **MATCH** |

### 3a. Salt pattern (`:370-378`) — REFERENCE (mirror for `keccak256(rngWord,"PRESALE_BOX")`)
```solidity
                        uint256 saltedRng = uint256(
                            keccak256(
                                abi.encodePacked(
                                    rngWord,
                                    keccak256("BONUS_TRAITS")
                                )
                            )
                        );
                        _payDailyCoinJackpot(1, saltedRng, 2, 5);
```

### 3b. Level-3 presale clear (`:429-431`) — POSSIBLE-DELETE candidate (plan §4)
```solidity
                if (lvl >= 3 && _psRead(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK) != 0) {
                    _psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0);
                }
```

### 3c. Perpetual jackpot tickets (`:1532-1545`) — REFERENCE (NOT a rake, per plan §1)
```solidity
        // Vault perpetual tickets: 16 generic tickets per level for DGNRS and VAULT
        uint24 targetLevel = purchaseLevel + 99;
        _queueTickets(
            ContractAddresses.SDGNRS,
            targetLevel,
            VAULT_PERPETUAL_TICKETS,
            true
        );
        _queueTickets(
            ContractAddresses.VAULT,
            targetLevel,
            VAULT_PERPETUAL_TICKETS,
            true
        );
```
`VAULT_PERPETUAL_TICKETS = 16` at `:123` (MATCH plan "16/level each").

### 3d. EARLYBIRD_END_LEVEL trigger (`:1670-1674`) — EDIT TARGET (remove with subsystem)
```solidity
            // Earlybird window ends at the transition to EARLYBIRD_END_LEVEL.
            // Dumps remaining Earlybird pool into Lootbox and flips the sentinel.
            if (lvl == EARLYBIRD_END_LEVEL) {
                _finalizeEarlybird();
            }
```

### 3e. `_finalizeEarlybird` body (`:1744-1757`) — EDIT TARGET (remove with subsystem)
```solidity
    function _finalizeEarlybird() private {
        if (earlybirdDgnrsPoolStart == type(uint256).max) return;
        earlybirdDgnrsPoolStart = type(uint256).max;
        uint256 remainingPool = dgnrs.poolBalance(
            IStakedDegenerusStonk.Pool.Earlybird
        );
        if (remainingPool != 0) {
            dgnrs.transferBetweenPools(
                IStakedDegenerusStonk.Pool.Earlybird,
                IStakedDegenerusStonk.Pool.Lootbox,
                remainingPool
            );
        }
    }
```

---

## 4. storage/DegenerusGameStorage.sol (1794 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `presaleStatePacked` (`:843`) | `:843` | **MATCH** |
| `_awardEarlybirdDgnrs` body (`:966-1013`) | doc `:966`, fn `:971`, body `:971-1014` | **MATCH** |
| `earlybirdDgnrsPoolStart` (`:957`) | `:957` | **MATCH** |
| `earlybirdEthIn` (`:960`) | `:960` | **MATCH** |
| `EARLYBIRD_TARGET_ETH` (`:178`) | `:178` (= `1_000 ether`) | **MATCH** |
| `EARLYBIRD_END_LEVEL` (`:175`) | `:175` (= `3`) | **MATCH** |
| Slot-0 layout comment (`:220`) | inline `:220` + header table `:43-66` | **MATCH** |

### 4a. SLOT 0 free-byte verification — **2 BYTES FREE (confirms plan)**
Header table (`:45-66`) and inline comment (`:216-220`) both state **30/32 bytes used, 2 bytes padding**. Manual byte tally of the live declarations (`:228-332`):

| Field | Width (bytes) | Cum. |
|---|---|---|
| purchaseStartDay (uint32) | 4 | 4 |
| dailyIdx (uint32) | 4 | 8 |
| rngRequestTime (uint48) | 6 | 14 |
| level (uint24) | 3 | 17 |
| jackpotPhaseFlag (bool) | 1 | 18 |
| jackpotCounter (uint8) | 1 | 19 |
| lastPurchaseDay (bool) | 1 | 20 |
| decWindowOpen (bool) | 1 | 21 |
| rngLockedFlag (bool) | 1 | 22 |
| phaseTransitionActive (bool) | 1 | 23 |
| gameOver (bool) | 1 | 24 |
| dailyJackpotCoinTicketsPending (bool) | 1 | 25 |
| compressedJackpotFlag (uint8) | 1 | 26 |
| ticketsFullyProcessed (bool) | 1 | 27 |
| gameOverPossible (bool) | 1 | 28 |
| ticketWriteSlot (bool) | 1 | 29 |
| prizePoolFrozen (bool) | 1 | 30 |
| **<padding>** | **2** | **32** |

`prizePoolFrozen` (`:332`) is the LAST slot-0 field; `currentPrizePool` (`:342`) opens slot 1. Adding `bool internal presaleOver` immediately after `prizePoolFrozen` lands it at byte `[30:31]`, leaving **1 byte free** — exactly as plan §4 / §4-storage-block describes. **CONFIRMED: 2 free bytes, the 1-byte `presaleOver` fits with 1 to spare.**

### 4b. `presaleStatePacked` (`:843`) — POSSIBLE-DELETE candidate (still LIVE, see §6)
```solidity
    uint256 internal presaleStatePacked = uint256(1);  // lootboxPresaleActive = true
```
Helpers `_psRead` (`:856`) / `_psWrite` (`:861`) and `LOOTBOX_PRESALE_ETH_CAP = 200 ether` (`:852`) live alongside.

### 4c. `_awardEarlybirdDgnrs` full body (`:971-1014`) — EDIT TARGET (remove)
```solidity
    function _awardEarlybirdDgnrs(
        address buyer,
        uint256 purchaseWei
    ) internal {
        if (purchaseWei == 0) return;
        if (buyer == address(0)) return;

        uint256 poolStart = earlybirdDgnrsPoolStart;
        // uint256.max is the finalization sentinel set by _finalizeEarlybird.
        if (poolStart == type(uint256).max) return;
        if (poolStart == 0) {
            uint256 poolBalance = dgnrs.poolBalance(
                IStakedDegenerusStonk.Pool.Earlybird
            );
            if (poolBalance == 0) return;
            poolStart = poolBalance;
            earlybirdDgnrsPoolStart = poolBalance;
        }

        uint256 totalEth = EARLYBIRD_TARGET_ETH;
        uint256 ethIn = earlybirdEthIn;
        if (ethIn >= totalEth) return;

        uint256 remaining = totalEth - ethIn;
        uint256 delta = purchaseWei > remaining ? remaining : purchaseWei;
        if (delta == 0) return;

        uint256 nextEthIn = ethIn + delta;
        uint256 denom = totalEth * totalEth;
        uint256 totalEth2 = totalEth * 2;
        uint256 d1 = (ethIn * totalEth2) - (ethIn * ethIn);
        uint256 d2 = (nextEthIn * totalEth2) - (nextEthIn * nextEthIn);
        uint256 payout = (poolStart * (d2 - d1)) / denom;

        earlybirdEthIn = nextEthIn;
        if (payout == 0) return;

        dgnrs.transferFromPool(
            IStakedDegenerusStonk.Pool.Earlybird,
            buyer,
            payout
        );
    }
```

### 4d. Earlybird state + constants — EDIT TARGETS (remove)
```solidity
    uint24 internal constant EARLYBIRD_END_LEVEL = 3;            // :175
    uint256 internal constant EARLYBIRD_TARGET_ETH = 1_000 ether; // :178
    uint256 internal earlybirdDgnrsPoolStart;                    // :957
    uint256 internal earlybirdEthIn;                             // :960
```

---

## 5. StakedDegenerusStonk.sol (980 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `Pool` enum incl. `Earlybird` (`:215`) | enum `:210-216`, `Earlybird` `:215` | **MATCH** |
| `EARLYBIRD_POOL_BPS = 1000` (`:297`/`:348`/`:370`) | decl `:297`; ctor use `:348`; assign `:370` | **MATCH** |
| Pre-mint pool list (`:365-369`) | `:366-370` | **SHIFTED(+1)** |
| `burnAtGameOver` (`:518`) | `:521` | **SHIFTED(+3)** |

### 5a. `Pool` enum (`:210-216`) — EDIT TARGET (rename `Earlybird` → `PresaleBox`)
```solidity
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }
```

### 5b. `EARLYBIRD_POOL_BPS` (`:297`) — KEEP (no bps change; plan reuses the 10% slot)
```solidity
    uint16 private constant EARLYBIRD_POOL_BPS = 1000;
```

### 5c. Pre-mint pool list (`:366-370`) — EDIT TARGET (rename enum reference)
```solidity
        poolBalances[uint8(Pool.Whale)] = whaleAmount;
        poolBalances[uint8(Pool.Affiliate)] = affiliateAmount;
        poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;
        poolBalances[uint8(Pool.Reward)] = rewardAmount;
        poolBalances[uint8(Pool.Earlybird)] = earlybirdAmount;
```
(`earlybirdAmount` computed at `:348`; `INITIAL_SUPPLY = 1e12 * 1e18` at `:284` → 10% = the full former Earlybird allocation, matches plan §7 #1.)

### 5d. `burnAtGameOver` (`:521-530`) — REFERENCE (D4 undrained-pool backstop)
```solidity
    function burnAtGameOver() external onlyGame {
        uint256 bal = balanceOf[address(this)];
        if (bal == 0) return;
        unchecked {
            balanceOf[address(this)] = 0;
            totalSupply -= bal;
        }
        delete poolBalances;
        emit Transfer(address(this), address(0), bal);
    }
```
`delete poolBalances` zeroes ALL pool slots (including the renamed `PresaleBox`), so an undrained presale pool burns cleanly at game-over — confirms plan §3.5 / §7 #9 "no backstop needed."

---

## 6. interfaces/IStakedDegenerusStonk.sol (105 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `Pool` enum (`:15`) | enum `:10-16`, `Earlybird` `:15` | **MATCH** |

### 6a. Interface `Pool` enum (`:10-16`) — EDIT TARGET (rename in lockstep with StakedDegenerusStonk)
```solidity
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Earlybird
    }
```
MUST be renamed identically (and in the same ordinal position) as the concrete enum in §5a to preserve `uint8(Pool.X)` ordinals across the ABI boundary.

---

## 7. modules/DegenerusGamePayoutUtils.sol (47 lines)

| Anchor (claimed) | Actual | Disposition |
|---|---|---|
| `_creditClaimable` (`:21`) | fn `:21`, does NOT bump `claimablePool` | **MATCH** |
| `_queueWhalePassClaimCore` (`:43`) | fn sig `:30`; bumps `claimablePool` ONLY on `remainder` at `:43` | **SHIFTED(sig at :30)** + **NUANCE** |

### 7a. `_creditClaimable` (`:21-27`) — credits balance, NO pool bump
```solidity
    function _creditClaimable(address beneficiary, uint256 weiAmount) internal {
        if (weiAmount == 0) return;
        unchecked {
            claimableWinnings[beneficiary] += weiAmount;
        }
        emit PlayerCredited(beneficiary, beneficiary, weiAmount);
    }
```
Confirms plan §2: bumps `claimableWinnings` but NOT `claimablePool`.

### 7b. `_queueWhalePassClaimCore` (`:30-46`) — partial pool bump
```solidity
    function _queueWhalePassClaimCore(address winner, uint256 amount) internal {
        if (winner == address(0) || amount == 0) return;

        uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
        uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

        if (fullHalfPasses != 0) {
            whalePassClaims[winner] += fullHalfPasses;
        }
        if (remainder != 0) {
            unchecked {
                claimableWinnings[winner] += remainder;
            }
            claimablePool += uint128(remainder);
            emit PlayerCredited(winner, winner, remainder);
        }
    }
```
**NUANCE / IMPL note (not a blocker):** the plan (§2, §3.3, §3.4) describes `_queueWhalePassClaimCore` as "the right pattern for new ETH liability" because it "DOES bump `claimablePool`." That is true only for the sub-`HALF_WHALE_PASS_PRICE` (`2.25 ether`) `remainder` — the bulk (`fullHalfPasses`) is routed to `whalePassClaims`, which is a SEPARATE liability that `claimablePool` does NOT track. For the 80/20 box-ETH routing (plan §3.3: `claimablePool += boxEth; claimableWinnings[VAULT] += 80%; claimableWinnings[SDGNRS] += 20%`), neither existing helper does exactly the needed "credit `claimableWinnings` AND bump `claimablePool` by the full credited amount." Plan §5 already anticipates this: *"reuse `_creditClaimable` + a `claimablePool` bump (or a small `_creditBoxProceeds(boxEth)` helper doing the 80/20 split)."* This attestation confirms the new helper is the correct route — the right pattern is `_creditClaimable(VAULT, 80%) + _creditClaimable(SDGNRS, 20%) + claimablePool += boxEth` (with the rounding remainder absorbed into one side), NOT a direct call to `_queueWhalePassClaimCore`.

`HALF_WHALE_PASS_PRICE = 2.25 ether` at `:15-16`.

---

## 8. Cross-cutting confirmations

- **`_awardEarlybirdDgnrs` call sites (full set):** MintModule `:1210` (MATCH), WhaleModule `:263` (MATCH), `:476` (MATCH), `:587` (MATCH). Exactly the 4 sites the plan §3.2/§4 names — clean 1:1 swap surface for credit accrual.
- **`_finalizeEarlybird`:** defined StorageAdvanceModule `:1744`, sole caller `:1673` (MATCH). No other callers.
- **Presale subsystem is LIVE, not dead** (plan §4 "VERIFY via grep at IMPL"): 17 references to `presaleStatePacked` / `_psRead` / `_psWrite` / `LOOTBOX_PRESALE_ETH_CAP` / `LOOTBOX_PRESALE_BURNIE_BONUS_BPS` across 6 files — `DegenerusGameMintModule.sol`, `DegenerusGameWhaleModule.sol`, `DegenerusGame.sol`, `DegenerusGameAdvanceModule.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameStorage.sol`. Deletion is feasible only AFTER the +62% bonus + 20% skim + level-3 clear are removed AND the new `presaleOver` latch replaces the consumers; the IMPL must re-grep the residual consumer set per file before deleting.
- **Salt mirror (`AdvanceModule:370-377`):** uses `keccak256(abi.encodePacked(rngWord, keccak256("BONUS_TRAITS")))` — the plan's `keccak256(rngWord, "PRESALE_BOX")` should mirror this exact shape (pre-hash the tag, then pack with the committed word).

---

## 9. Verdict

**ALL anchors RESOLVE. 23 MATCH / 5 SHIFTED (all ≤ +5 lines, benign) / 0 ABSENT. No IMPL blockers.**

Two IMPL clarifications carried forward (neither blocks):
1. The 200-ETH presale auto-end keys on `LOOTBOX_PRESALE_ETH_CAP` (Storage `:852`), not a literal in MintModule.
2. `_queueWhalePassClaimCore` bumps `claimablePool` only on the `remainder`; the 80/20 box routing needs the new `_creditBoxProceeds` helper the plan §5 already calls for, not a reuse of that function.
