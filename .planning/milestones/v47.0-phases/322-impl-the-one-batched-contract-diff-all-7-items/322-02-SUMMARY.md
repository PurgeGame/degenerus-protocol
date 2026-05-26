# 322-02 SUMMARY — PRESALE rake removal + credit-gated coin-presale box (wave 2)

**Plan:** `322-02-PLAN.md` (wave 2, executor #2 of 7). **Status:** FULLY APPLIED.
**Discipline:** NO git operation performed. Contracts left dirty for the single batched-diff review (322-08).
**Built on:** 322-01's applied tree (Pool rename, presale storage, `_creditBoxProceeds`, earlybird partial-delete). Anchors re-grepped at edit time; drift was line-number-only.
**Requirements:** PRESALE-01,-02,-03,-04,-05,-07,-08,-09,-12, CPAY-02.

---

## Files touched (6)

1. `contracts/modules/DegenerusGameMintModule.sol` — rake removal (90/10 split, vault skim deleted), `presaleBoxCredit` accrual, `_buyPresaleBoxFor` + the two box entrypoints, `PresaleBoxBuy` event, `PRESALE_BOX_MIN` const, now `is DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils` (for `_creditBoxProceeds`).
2. `contracts/modules/DegenerusGameLootboxModule.sol` — +62% BURNIE bonus block + `LOOTBOX_PRESALE_BURNIE_BONUS_BPS` deleted; presale-box resolution (`openPresaleBox`, `openLootboxAndPresaleBox`, `_resolvePresaleBox`, `_presaleBoxDgnrsReward`, `_presaleBoxDgnrsTierTenths`); recentered BURNIE band + DGNRS curve constants; `PresaleBoxOpened` event.
3. `contracts/storage/DegenerusGameStorage.sol` — deleted `_awardEarlybirdDgnrs` body + `earlybirdDgnrsPoolStart`/`earlybirdEthIn`/`EARLYBIRD_TARGET_ETH`; removed unused `presaleBoxRngWordByIndex`; added `presaleBoxDgnrsPoolStart`, `PRESALE_BOX_CLOSING_FLAG`, `PRESALE_BOX_SOLD_SHIFT`, `PRESALE_BOX_AMOUNT_MASK`; repacked `presaleBoxEth` (closing flag + soldBefore + amount).
4. `contracts/DegenerusGame.sol` — `buyPresaleBox` / `buyLootboxAndPresaleBox` (payable) + `openPresaleBox` / `openLootboxAndPresaleBox` entrypoints; `presaleBoxCreditOf` / `presaleBoxEthRemaining` views.
5. `contracts/interfaces/IDegenerusGameModules.sol` — MintModule + LootboxModule box-fn decls.
6. `contracts/interfaces/IDegenerusGame.sol` — box entrypoint + view decls.

---

## Task 1 — Rake removal + credit accrual (PRESALE-01/-02/-03/-12)

### PRESALE-01 — 20% vault skim removed (MintModule)
- Deleted the 3 `LOOTBOX_PRESALE_SPLIT_*` constants.
- Collapsed the lootbox pool-split arm: presale now takes the NORMAL path. Distress = 100% next; everything else (presale + post-presale) = 90% future / 10% next (`LOOTBOX_SPLIT_FUTURE_BPS`/`NEXT_BPS`).
- Deleted the entire `vaultBps`/`vaultShare` machinery + the `if (vaultShare != 0) { payable(VAULT).call{value:} }` skim block. Presale lootbox ETH now routes 100% to prize pools.

### PRESALE-02 — +62% presale BURNIE bonus removed (LootboxModule)
- Deleted the `if (presale && burniePresale != 0) { +62% }` block in `_resolveLootboxCommon` (kept the harmless `burnieAmount = burnieNoMultiplier + burniePresale` sum).
- Deleted `LOOTBOX_PRESALE_BURNIE_BONUS_BPS = 6_200`.
- The `presale` bool PARAM of `_resolveLootboxCommon` is now unused-in-body but KEPT (322-03 drops the param per R2). The `burniePresale`/`burnieNoMultiplier` split is left intact (collapsing it touches `_accumulateLootboxRolls` + `_resolveLootboxRoll.applyPresaleMultiplier` — out of this plan's minimal scope; 322-03 owns the 5→2 reduction).

### PRESALE-03 (D5) — credit accrual swap (MintModule)
- Replaced `_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount)` with `if (!presaleOver) { presaleBoxCredit[buyer] += (ticketCost + lootBoxAmount) / 4; }` (25% credit). Covers `batchPurchase` (routes through mint). Degenerette + BURNIE-funded buys stay excluded (no site there).

### PRESALE-12 dead-flag sweep — DISPOSITION (KEEP, per R6)
**`presaleStatePacked` / `PS_ACTIVE` / `_psRead` / `_psWrite` / `LOOTBOX_PRESALE_ETH_CAP` / the 200-ETH mint auto-end (MintModule) / the level-3 clear (AdvanceModule:429-431) are ALL KEPT.** The PRESALE-12 prose framed them as candidate-dead "after the +62%/20%-skim removal," but grep at edit time found the `lootboxPresaleActive` flag (`PS_ACTIVE`) has MANY surviving LIVE consumers UNRELATED to this plan's scope:
- `WhaleModule:360/506/660` — whale/lazy/deity pass lootbox share is 20% (presale) vs 10% (post), gated on `_psRead(PS_ACTIVE)`.
- `BurnieCoinflip.sol:780` — `game.lootboxPresaleActiveFlag()` drives a +6pp coinflip bonus during presale.
- `DegenerusAffiliate.sol:326/691` — VAULT-referred players may re-set referral only during presale.
- `DegenerusGame.sol:2168/2184` — `lootboxStatus` + `lootboxPresaleActiveFlag()` views.

The 200-ETH auto-end and level-3 clear are the AUTOMATIC terminals that flip `PS_ACTIVE` off for those live consumers — deleting them would leave the flag never auto-clearing (behavior change for whale %, coinflip, affiliate). Per R6 "if any consumer survives, KEEP that flag and note why" → **KEPT, all documented.** `presaleOver` (the NEW coin-box terminal) is a DISTINCT concept (50-ETH box volume) and does not replace `PS_ACTIVE` (mint/lootbox presale window). This is the one deliberate deviation from PRESALE-12's optimistic deletion framing; it is the correct R6 outcome.

---

## Task 2 — Box buy + boon-less 50/40/10 resolution + 80/20 routing + RNG salt

**Box BUY lives in MintModule** (`_buyPresaleBoxFor`); **box RESOLUTION lives in LootboxModule** (`_resolvePresaleBox`).

### PRESALE-04 — credit-gated buy + clamp-close (MintModule `_buyPresaleBoxFor`)
- Reverts if `presaleOver` or liveness-triggered.
- `PRESALE_BOX_MIN = 0.01 ether` checked on the REQUESTED `boxAmount` BEFORE the clamp (sub-floor gap can never lock the close).
- No overpay vs requested: `valueForBox > boxAmount` reverts.
- Global cap via `presaleBoxEthSold`: `remaining = PRESALE_BOX_ETH_CAP(50e18) - sold`; `remaining == 0` reverts (sold out).
- **Clamp:** `applied = min(boxAmount, remaining)`; `closing = (applied == remaining)`.
- **Credit gate (1:1):** `applied > presaleBoxCredit[buyer]` reverts; consume `presaleBoxCredit[buyer] -= applied`. (Gate keys on the applied/clamped amount — a closing buyer with exactly `remaining` credit can still close.)
- **One box per (index, player):** `presaleBoxEth[index][buyer] != 0` reverts (accumulation would corrupt the frozen soldBefore tier snapshot).

### CPAY-02 — claimable-pay on the box (R3 invariant)
- `freshUsed = min(valueForBox, applied)`; `refund = valueForBox - freshUsed`; `shortfall = applied - freshUsed`.
- Shortfall path: STRICT sentinel `claimableWinnings[buyer] <= shortfall` reverts; debit `claimableWinnings[buyer] -= shortfall` + `claimablePool -= uint128(shortfall)`.
- Then `_creditBoxProceeds(applied)` (pool += applied; VAULT 80% + SDGNRS 20% claimable, summing to applied).
- **Net effect (R3 verified):** pool delta = +applied − shortfall = `freshUsed`; claimable-balance delta = +applied (VAULT+SDGNRS) − shortfall (buyer) = `freshUsed`; real ETH in = `freshUsed` (msg.value minus refund). So `claimablePool == Σ claimableWinnings` stays balanced AND the pool is real-ETH-backed. Claimable-funded portion nets pool 0; msg.value portion bumps pool by that ETH — exactly R3/CPAY-02.
- Excess fresh ETH (clamp) refunded to `msg.sender` at the END (checks-effects-interactions; reentrancy-safe, all state settled first).

### PRESALE-05/-07/-08 — queue + boon-less resolution + RNG freeze (R4)
- Box queues at the CURRENT `LR_INDEX` (shared with a same-tx mint lootbox → "one index"); guarded `lootboxRngWordByIndex[index] != 0` reverts (word must be uncommitted = pre-entropy).
- Packed record: `[bit255 closing][bits96:191 soldBefore][bits0:95 applied]`. `soldBefore` (cumulative box ETH before this buy) FREEZES the DGNRS-tier input so the resolution reads no mutable SLOAD.
- Enqueued via `enqueueBoxForCrank(index, buyer)` for permissionless discovery.
- `presaleBoxEthSold = uint96(sold + applied)`; `closing` latches `presaleOver = true` (stops accrual + further box buys).
- **Resolution is its OWN boon-less roll** (`_resolvePresaleBox`), NOT a `_resolveLootboxCommon` caller → a credit-funded box can never mint a whale pass.
- **RNG entropy (R4):** `seed = keccak256(abi.encodePacked(rngWord, keccak256("PRESALE_BOX"), player, amount))` — pre-hashes the domain tag (mirrors `AdvanceModule:370-377` `keccak256(abi.encodePacked(rngWord, keccak256("BONUS_TRAITS")))`) off the SAME committed `lootboxRngWordByIndex[index]`, with the box's immutable buy data (player + amount) for per-player variance (mirrors the lootbox's `keccak256(abi.encode(rngWord, player, day, amount))`). No new mutable SLOAD enters the OUTCOME roll. The `presaleBoxRngWordByIndex` mapping 322-01 added was redundant (box reads `lootboxRngWordByIndex`) → REMOVED.
- **Roll:** `outcome = uint16(seed) % 100`: `<50` BURNIE (50%), `<90` DGNRS (40%), else WWXRP (10%). Variance slice `uint16(seed >> 80) % 20` (disjoint bits from the outcome slice).

### Locked economic numbers
- **BURNIE (mean 400% on branch):** lootbox band recentered ×2.4274 → low `14098 + roll*1158` (rolls 0-15, p=80%), high `74534 + (roll-16)*22890` (rolls 16-19, p=20%). E[bps] = 0.8·22783 + 0.2·108869 = 40000.2 ≈ 40000 (400% branch; 200% all-boxes since BURNIE rolls 50%). Pegged `burnieOut = (amount*bps/10000)*PRICE_COIN_UNIT/priceForLevel(level+1)`, floored to whole BURNIE, `coinflip.creditFlip`. (Price-peg uses live `level` for VALUE conversion like every BURNIE award — NOT part of the frozen outcome roll, identical to the lootbox model.)
- **DGNRS (5-tier curve):** `_presaleBoxDgnrsReward` — `base = poolStart/100` (poolStart = `Pool.PresaleBox` snapshot into `presaleBoxDgnrsPoolStart` on first resolution); tier multiplier (tenths) `[30,25,20,15,10]` by `soldBefore` 10-ETH bands `[0,10)…≥40`; award = `poolStart * tierTenths * amount / (1000 * 1 ether)`; `transferFromPool(Pool.PresaleBox, player, amt)`. Deterministic draws sum to 100·base = poolStart over 50 ETH (drains); since only 40% of boxes draw DGNRS, the closing-box sweep zeroes whatever is left.
- **WWXRP:** `LOOTBOX_WWXRP_PRIZE (1 ether)` via `wwxrp.mintPrize`.

### PRESALE-09 — clamp-close + last-buyer sweep + latch
- The 50-crossing buy is clamped to `applied = remaining` (excess fresh refunded), latches `presaleOver` at BUY.
- At its OPEN, `_resolvePresaleBox` runs the normal 50/40/10 roll on the clamped amount AND (closing flag set) sweeps ALL remaining `Pool.PresaleBox` to that buyer ON TOP of the roll, zeroing the pool. Verified: `transferFromPool(PresaleBox, player, poolBalance(PresaleBox))`.

---

## Task 3 — Entrypoints + interface + views

- `DegenerusGame.buyPresaleBox(address,uint256) external payable` → MintModule `buyPresaleBox` (msg.value forwarded as box fresh-ETH).
- `DegenerusGame.buyLootboxAndPresaleBox(address,uint256,uint256,bytes32,MintPaymentKind,uint256) external payable` → MintModule: `_purchaseFor` (mint leg, msg.value, accrues credit) THEN `_buyPresaleBoxFor(buyer, boxAmount, 0)` (box leg claimable-funded; shares the same `LR_INDEX`).
- `DegenerusGame.openPresaleBox(address,uint48) external` → LootboxModule `openPresaleBox`.
- `DegenerusGame.openLootboxAndPresaleBox(address,uint48) external` → LootboxModule `openLootboxAndPresaleBox` (resolves lootbox leg via a nested delegatecall to the module's own `openLootBox` with the already-resolved player — bypasses the game's `_resolvePlayer` re-gate that would otherwise revert with the game contract as msg.sender — then the salted box leg).
- Views: `presaleBoxCreditOf(address)`, `presaleBoxEthRemaining()`.
- Decls added to `IDegenerusGameModules.sol` (Mint + Lootbox) and `IDegenerusGame.sol` (entrypoints + views).

---

## Earlybird body deletion status
- **`_awardEarlybirdDgnrs` BODY: DELETED by THIS plan (322-02)** (per executor STATE + HARD RULE 6 + 322-01-SUMMARY ownership: 322-02 deletes the body after swapping the MintModule site). `Pool.Earlybird` is now FULLY gone (the 2 storage dangling refs at the old :1017/:1043 are resolved).
- Deleted alongside: `earlybirdDgnrsPoolStart`, `earlybirdEthIn`, `EARLYBIRD_TARGET_ETH` (their sole reader was the body).
- **LEFT for 322-06:** the 3 WhaleModule `_awardEarlybirdDgnrs` call sites (`:263`, `:476`, `:587`) — now the EXPECTED dangling set (they must be swapped to `if (!presaleOver) presaleBoxCredit[x] += eth/4`).

---

## Deviations
1. **MintModule now multi-inherits `DegenerusGamePayoutUtils, DegenerusGameMintStreakUtils`** (was just `MintStreakUtils`) so it can call `_creditBoxProceeds`/`_creditClaimable`. Mirrors the established `DegeneretteModule` pattern (same two-base shape). No constructor conflict (common `DegenerusGameStorage` ancestor, no ctor).
2. **`presaleStatePacked`/`PS_ACTIVE` + 200-ETH auto-end + level-3 clear + `LOOTBOX_PRESALE_ETH_CAP` KEPT** (PRESALE-12 framed them deletable; grep found live consumers → R6 KEEP). See Task 1 disposition.
3. **`presaleBoxRngWordByIndex` (322-01 storage) REMOVED** — redundant; the box reads the SAME `lootboxRngWordByIndex[index]` per R4 (one committed word, shared index). No consumer existed.
4. **Combined `buyLootboxAndPresaleBox` funds the box leg from CLAIMABLE only** (not fresh ETH). Rationale: `_purchaseFor` reads the full `msg.value` and reverts on overfunding, so a clean fresh-ETH split between mint and box without refactoring the mint hot path is not feasible. CPAY-02 explicitly supports the claimable-funded box (pure ledger move); the all-fresh "5B" UX is reachable via the deferred two-tx path (mint, then standalone `buyPresaleBox` with fresh ETH). The standalone `buyPresaleBox` supports BOTH fresh msg.value AND claimable shortfall.
5. **RNG salt extended with `player, amount`** beyond the literal `keccak256(rngWord,"PRESALE_BOX")` for per-player variance (immutable buy data, freeze-safe; mirrors the lootbox). Pre-hashed tag per ATTEST §8 direction.
6. **`presaleBoxDgnrsPoolStart` storage var ADDED** (snapshots the pool start for the DGNRS base; mirrors the deleted earlybird snapshot mechanism). New slot (not slot 0).

Minor: a combined buy enqueues the player at `boxPlayers[index]` twice (once by the mint lootbox first-deposit, once by the box) — duplicate crank entry, idempotent on open, not a correctness bug.

---

## Remaining `forge build` error set (for 322-06)
```
Error (7576): Undeclared identifier.  contracts/modules/DegenerusGameWhaleModule.sol:263:9   _awardEarlybirdDgnrs(buyer, totalPrice);
Error (7576): Undeclared identifier.  contracts/modules/DegenerusGameWhaleModule.sol:476:9   _awardEarlybirdDgnrs(buyer, benefitValue);
Error (7576): Undeclared identifier.  contracts/modules/DegenerusGameWhaleModule.sol:587:9   _awardEarlybirdDgnrs(buyer, totalPrice);
```
Exactly 3 errors, all the WhaleModule earlybird call sites (322-06 swaps them to `presaleBoxCredit` accrual). No errors in any 322-02-edited file. (JackpotModule:432/433/497/498 `-->` lines that appear under "Compiler run failed" are pre-existing `Warning (2519)` shadow-declaration warnings, NOT errors, NOT in scope.) Full build verified at wave 8.

**Existence of this file = 322-02 fully applied.** No git commit performed.
