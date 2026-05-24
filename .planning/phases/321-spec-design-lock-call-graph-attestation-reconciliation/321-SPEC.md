# Phase 321 SPEC — v47.0 Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation

**Milestone:** v47.0. **Baseline HEAD attested against:** `2a18d622` (2026-05-24).
**Inputs:** the 7 plan docs + `.planning/PLAN-V47-MILESTONE-SCOPE.md` (manifest) + the 4 attestation files in this dir (`321-ATTEST-PRESALE.md`, `321-ATTEST-LOOT-DGAS-DSPIN.md`, `321-ATTEST-REDEEM-CPAY.md`, `321-ATTEST-TOMB.md`).
**Owns:** BATCH-01 (shared-surface reconciliation), BATCH-02 (call-graph attestation).

---

## 0. Attestation verdict (BATCH-02)

**0 IMPL blockers across all 7 items.** Every cited `file:line` exists in current source; all drift is line-number-only (≤ a few lines). No "by construction" claims rely on absent code. Re-grep at edit time (the batched diff shifts lines). Raw per-anchor tables: the 4 `321-ATTEST-*.md` files. Material clarifications folded into §2 below.

**Carried corrections (from attestation, override the plan prose):**
- C1. `_resolveLootboxCommon` has **5 bools** (`presale, allowPasses, emitLootboxEvent, payColdBustConsolation, allowBoons`) — remove only `presale`/`allowPasses`/`allowBoons`; **KEEP `emitLootboxEvent` + `payColdBustConsolation`** (they legitimately differ across the 3 callers).
- C2. `resolveRedemptionLootbox` (`DegenerusGame.sol:1788-1838`) resolves the box via `GAME_LOOTBOX_MODULE` delegatecall in 5-ETH chunks — the `allowBoons` behavior change lands inside `_resolveLootboxCommon` (now always rolls boons), not at the call site.
- C3. `_queueWhalePassClaimCore` only pool-bumps the sub-`2.25 ether` remainder (diverts the bulk to `whalePassClaims`) — it is NOT a 80/20 credit helper. Add a new `_creditBoxProceeds`.
- C4. `onlyFlipCreditors` (`BurnieCoinflip:191-201`) = {GAME, QUESTS, AFFILIATE, ADMIN, AF_KING}; SDGNRS absent. `consumeCoinflipsForBurn` (:356-361) is gated by a SEPARATE `onlyBurnieCoin`. REDEEM-07 must touch both.
- C5. sDGNRS ctor subscribe is now 6-arg: `afKing.subscribe(address(this), true, false, 1, 2, address(0))` (v46 OPEN-E). The SUB-09 self-sub still drains `claimableWinnings[SDGNRS]` — the ETH-segregation fix must account for it.
- C6. `CURRENCY_WWXRP = 3` (not 2); use the named constant for the per-currency spin-cap lookup.
- C7. slot 0 has exactly **2 free bytes**; `bool internal presaleOver` after `prizePoolFrozen` lands at byte [30:31], 1 byte still free.
- C8. The 200-ETH presale auto-end is keyed on `LOOTBOX_PRESALE_ETH_CAP` (Storage:852), no inline "200".
- C9. ETH lootbox-share hand-off from Degenerette is via the private `_resolveLootboxDirect` wrapper (`DegeneretteModule:783`, called :772), not the module selector directly.

---

## 1. Reconciliation decisions (BATCH-01) — the cross-plan joint edits

### R1 — `resolveRedemptionLootbox` FINAL signature (joint LOOT-03 + REDEEM-03 + CPAY)
One settled signature; apply in this order inside the diff:
1. **REDEEM-03 first:** make it `payable`; **DELETE** the unchecked debit block (`:1802-1806`: `uint256 claimable = …; unchecked { claimableWinnings[SDGNRS] = claimable - amount; } claimablePool -= uint128(amount);`). Credit `futurePrizePool` from the arriving `msg.value` (freeze-aware, as today) — the ETH now physically arrives instead of being a claimable reassignment.
2. **LOOT-03 second:** the box roll is `allowBoons=true` — achieved by `_resolveLootboxCommon` always rolling boons after R2 (no call-site flag). No separate edit at this call site beyond R2.
- **Final:** `function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable` — SDGNRS-gated, credits `futurePrizePool` from `msg.value`, delegatecalls the (now boon-rolling) common resolver. sDGNRS forwards `lootboxEth` as real `msg.value` (REDEEM-03 caller side).

### R2 — `_resolveLootboxCommon` param reduction (LOOT-04 + LOOT-05 + PRESALE-02)
- REMOVE 3 of 5 bools: `presale` (no consumer after the +62% block goes, PRESALE-02), `allowPasses` (always-true now), `allowBoons` (always-true now). **KEEP** `emitLootboxEvent`, `payColdBustConsolation` (C1).
- Body: delete the `if (presale && …)` +62% BURNIE bonus block; delete the `if (allowBoons)` gate → boon roll always runs; delete the `if (allowPasses)` gates (:1268-1282, :1344-1352) → passes always eligible (still real-state-gated by `lazyPassValue != 0` / deity eligibility). The haircut `mainAmount = amount − _lootboxBoonBudget(amount)` (:949) now always pairs with a spent budget → 10% haircut fixed (LOOT-04).
- Drop the now-unused BURNIE-conversion helper (the `amountEth = burnieAmount*priceWei*80/(PRICE_COIN_UNIT*100)` path) once `openBurnieLootBox` is gone.
- 3 surviving callers updated to the 2-bool tail: `openLootBox(emit=true, coldBust=true)`, `resolveLootboxDirect(emit=false, coldBust=false)`, `resolveRedemptionLootbox(emit=false, coldBust=false)`.

### R3 — claimable accounting / `claimablePool == Σ claimableWinnings` (PRESALE-06 + CPAY-01/03 + REDEEM-01/03)
- **New helper `_creditBoxProceeds(uint256 boxEth)`** (PayoutUtils): `uint256 sdgnrsShare = boxEth*20/100; claimablePool += uint128(boxEth); claimableWinnings[VAULT] += boxEth - sdgnrsShare; claimableWinnings[SDGNRS] += sdgnrsShare;` (remainder to VAULT). Invariant preserved: pool += boxEth, credits sum to boxEth.
- **CPAY shortfall pattern** (the canonical MintModule:929-951 form): no overpay (`msg.value > cost` reverts); `shortfall = cost − msg.value`; STRICT sentinel (`claimableWinnings[buyer] <= shortfall` reverts — preserves the 1-wei sentinel); `claimableWinnings[buyer] -= shortfall`; `claimablePool -= uint128(shortfall)`. Applied to `purchaseWhaleBundle`/`purchaseLazyPass`/`purchaseDeityPass` + the presale box buy.
  - **Box paid from claimable = pure ledger move:** debit player claimable + `claimablePool -= shortfall`, then `_creditBoxProceeds` re-credits VAULT+SDGNRS + `claimablePool += boxEth` → for the claimable-funded portion net pool delta = 0; for the msg.value portion pool += that ETH. Verify the two halves compose to a balanced pool in the combined path.
- **New `pullRedemptionReserve(uint256 amount)`** on Game (REDEEM-01): SDGNRS-gated; checked `claimableWinnings[SDGNRS] -= amount` + `claimablePool -= uint128(amount)`; real ETH transfer to sDGNRS. (This is the only remaining claimable[SDGNRS] debit, and it's CHECKED — Defect A's unchecked one is deleted in R1.)
- **Joint check:** after the diff, grep that every `claimablePool` mutation has a matching `claimableWinnings` mutation of equal magnitude (or a real ETH in/out). No `unchecked` claimable subtraction survives in the redemption path (REDEEM-08).

### R4 — presale-box RNG freeze (PRESALE-12 / PRESALE-07)
- Box gets its own queue index (mirror `lootboxEth`/`lootboxRngWordByIndex`); payout entropy = the committed index/day RNG word + domain salt `keccak256(abi.encodePacked(rngWord, "PRESALE_BOX"))` (mirrors `AdvanceModule:370-377` `keccak256(rngWord, keccak256("BONUS_TRAITS"))`).
- Combined lootbox+box → SAME index → one committed word → two domain-separated draws in `openLootBox`/bundle-open (lootbox uses its existing derivation; box uses the salted one). Robust to either-alone.
- Freeze-safe by the existing lootbox argument: word committed before the player can act, never re-derived from mutable state. Re-verify at secure-phase (no new mutable SLOAD enters the box roll).

### R5 — DegeneretteModule single edit (DGAS + DSPIN, same file)
- DSPIN-01: replace `if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET)` (:445-446) with a per-currency cap (ETH 25 / BURNIE 15 / WWXRP 5) via `currency == CURRENCY_ETH ? 25 : currency == CURRENCY_BURNIE ? 15 : 5` (C6: CURRENCY_WWXRP=3). Retire `MAX_SPINS_PER_BET`, update doc comments (:296, :364).
- DGAS: `resolveBets`/`_resolveBet`/`_resolveFullTicketBet` (currently void) → return per-currency delta tuples; accumulate ETH/BURNIE/WWXRP CROSS-BET, flush once (one mint per currency, one claimable+pool write, one pool write); ETH cap evaluated against a running-pool local (byte-identical); lootbox summed PER `betId` → one `_resolveLootboxDirect` per bet (C9), drop the per-spin `lootboxWord` salting (:646-657) but KEEP the per-spin result seed (:596-609); `_awardDegeneretteDgnrs` stays per-spin (Tier 3).
- Worst case to measure at TST: max 25-spin ETH bets in one `resolveBets` (DSPIN-02 + DGAS-05) — must fit and show the batching absorbs the 2.5× roll work.

### R6 — earlybird→presale-box subsystem swap (PRESALE-03/10/11)
- Rename `Pool.Earlybird → Pool.PresaleBox` (ordinal 4 preserved, ABI-safe) in `StakedDegenerusStonk.sol:210-216` + `IStakedDegenerusStonk.sol:10-16`; `EARLYBIRD_POOL_BPS=1000` allocation unchanged (rename const too).
- DELETE the earlybird emission subsystem: `_awardEarlybirdDgnrs` (Storage:971-1014) + 4 call sites (MintModule:1210, WhaleModule:263/476/587) → replaced 1:1 by `if (!presaleOver) presaleBoxCredit[x] += eth/4`; `_finalizeEarlybird` (AdvanceModule:1744-1757) + `EARLYBIRD_END_LEVEL` trigger (:1672-1673); state `earlybirdDgnrsPoolStart`/`earlybirdEthIn` + consts `EARLYBIRD_TARGET_ETH`/`EARLYBIRD_END_LEVEL`.
- Grep-verify (at edit time) `presaleStatePacked` (Storage:843) + level-3 clear (AdvanceModule:429-431) + 200-ETH auto-end (keyed on `LOOTBOX_PRESALE_ETH_CAP`, Storage:852) have NO surviving consumer after the +62%/20%-skim removal → delete; let `presaleOver` be the sole presale terminal. If any consumer survives, keep that flag and note why.

### R7 — AfKing cancel-tombstone (TOMB, ISOLATED — no cross-plan entanglement)
- Edit 1 (`setDailyQuantity(0)`, :455-472): do NOT call `_removeFromSet`; set `s.dailyQuantity = 0` in place; DEFER the `_subOf` delete-vs-preserve (currently :460-467, uses `FLAG_WINDOW_PAID` + `paidThroughDay > _currentDay()`) to the in-sweep reclaim; keep the `SubscriptionUpdated(…,0,…)` emit; fix the :449 NatSpec mislabel.
- Edit 2 (sweep loop, top at :609): add a loop-top `sub.dailyQuantity == 0` reclaim branch BEFORE/around the `lastSweptDay >= today` skip (:614) so a dead tombstone is always reclaimed — apply the deferred delete-vs-preserve, `_removeFromSet(player)`, emit, and `continue` WITHOUT `++cursor` (mirror the :642-644 / :737-739 no-`++i` pattern) so the swap-pop occupant (a pending mover from ahead) is processed at this index this sweep.
- Confirm `subscribe()` (6-arg, :375/:380-area) does not double-add an in-set tombstoned address (it's still in `_subscriberIndex`); route reactivation through `setDailyQuantity(q>0)` (:470) with no set churn.

---

## 2. Per-item IMPL blueprint (the batched-diff checklist)

> Files in the diff: `storage/DegenerusGameStorage.sol`, `modules/DegenerusGameMintModule.sol`, `modules/DegenerusGameLootboxModule.sol`, `modules/DegenerusGameAdvanceModule.sol`, `modules/DegenerusGameDegeneretteModule.sol`, `modules/DegenerusGameWhaleModule.sol`, `modules/DegenerusGameGameOverModule.sol`, `modules/DegenerusGamePayoutUtils.sol`, `DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `BurnieCoin.sol`, `BurnieCoinflip.sol`, `AfKing.sol`, `interfaces/IDegenerusGame.sol`, `interfaces/IStakedDegenerusStonk.sol`, `DegenerusVault.sol`, `ContractAddresses.sol` (if a new pinned address is needed — none expected). Order: storage/enums first → helpers → callers → entrypoints → interfaces.

**Item 1 (PRESALE):** PRESALE-01..13 — see plan §3–§7 + R3/R4/R6. New storage per PRESALE-11 (C7 slot-0 bool). New `buyPresaleBox`/`buyLootboxAndPresaleBox` + box resolution (50/40/10 roll; DGNRS 5-tier curve [3.0,2.5,2.0,1.5,1.0], base = poolSize/100; BURNIE mean 400%-on-branch; WWXRP 1) + 80/20 routing via `_creditBoxProceeds` + clamp-to-50 close + last-buyer sweep + `presaleOver` latch. Box is BOON-LESS (own resolver, PRESALE-08).
**Item 2 (LOOT):** LOOT-01..06 — BURNIE-lootbox removal spread (LootboxModule/MintModule/Game/Vault per attest table) + R2 param reduction. KEEP BURNIE→tickets + `gamePurchaseTicketsBurnie`.
**Item 3 (DGAS) + Item 6 (DSPIN):** R5 — one DegeneretteModule edit.
**Item 4 (CPAY):** CPAY-01 (3 whale fns) + CPAY-02 (box, with item 1) + CPAY-03 (sweep all DegenerusGame payable entries; `_batchPurchaseUnit` is onlySelf — exclude). R3 pattern.
**Item 5 (REDEEM):** REDEEM-01..08 — sDGNRS ETH segregation (`pullRedemptionReserve` + submit MAX-175% pull, fail-closed) + BURNIE flip-credit-at-submit (`redeemBurnieShare` on Coinflip; SDGNRS into `onlyFlipCreditors` + the consume gate, C4; new SDGNRS-gated burn on BurnieCoin) + R1 (`resolveRedemptionLootbox` payable / debit-removed) + GameOver double-count drop. Delete the BURNIE reserve apparatus.
**Item 7 (TOMB):** R7 — AfKing.sol Edits 1+2 (ISOLATED).

---

## 3. Success criteria (Phase 321)
1. ✅ `resolveRedemptionLootbox` final signature settled (R1) with apply-order recorded.
2. ✅ Every plan anchor grep-attested vs HEAD `2a18d622`; 0 blockers; corrections C1–C9 captured.
3. ✅ `claimablePool == Σ claimableWinnings` joint design locked (R3) incl. the new `_creditBoxProceeds` + `pullRedemptionReserve`.
4. ✅ Presale-box RNG freeze design locked (R4); secure-phase re-verification flagged.
5. ✅ Per-item IMPL blueprint (§2) + the file/edit-order map produced as the load-bearing input to Phase 322.

**SOURCE-TREE not yet mutated at SPEC.** Phase 322 applies the batched diff.
