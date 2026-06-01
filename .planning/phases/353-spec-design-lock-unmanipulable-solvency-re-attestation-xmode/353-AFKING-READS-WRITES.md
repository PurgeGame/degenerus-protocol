# AfKing Buy + Open — Storage Reads/Writes Inventory

**Purpose:** A SLOAD/SSTORE map of the everyday afking paths, annotated with which accesses are *strictly necessary for the path to function* vs which are the deferrable "extraneous stuff" v56 batches into the ~10-day settle. This is the gas-optimization substrate for the v56.0 SPEC (feeds AGG/GAS/TKT/OPEN).

**Source:** `contracts/modules/GameAfkingModule.sol` at the v55.0 frozen subject `453f8073` (working tree byte-identical, per `353-RESEARCH.md`).
**Key fact:** the `Sub` record is a **single 256-bit slot** (232/256 packed — `contracts/storage/DegenerusGameStorage.sol`), so every per-sub field touch coalesces into ONE warm SLOAD / ONE warm SSTORE.

---

## 1. AFKING BUY — `processSubscriberStage` (`:539`), per subscriber

The per-day `advanceGame` STAGE walks the subscriber set in `SUB_STAGE_BATCH`-sized chunks. `_resolveBuy` (`:440`) is `view` — its reads are listed under the caller.

**Hoisted ONCE per chunk (not per-sub):**
- `_mintPriceInContext()` → `_activeTicketLevel` + price (`:543`)
- `level` → `currentLevel` (`:546`, AFSUB-02 hoist — non-crossing pass needs no per-iter level SLOAD)
- `_subCursor` (`:548` 1 SLOAD in / `:849` 1 SSTORE out)

### Per-subscriber READS

| # | Access | Site | Type | Strictly necessary? |
|---|--------|------|------|---------------------|
| R1 | `_subscribers[cursor]` → player | `:551` | SLOAD (array) | ✅ core — who to process |
| R2 | `_subOf[player]` (flags, lastOpenedDay, lastAutoBoughtDay, dailyQuantity, reinvestPct, validThroughLevel, scorePlus1, amount) | `:552` + field reads | 1 SLOAD (warm after) | ✅ core — config + idempotency/no-orphan markers |
| R3 | `_goRead(GO_SWEPT…)` (swept-gate) | `:461` | SLOAD | ✅ core — mirrors afkingSnapshot/claimableWinningsOf |
| R4 | `claimableWinnings[player]` | `:463` | SLOAD | ⚠️ only meaningful when `reinvestPct>0` OR `drainFirst`; read unconditionally today (skipped only when swept) |
| R5 | `afkingFunding[player]` → playerFunding | `:464` | SLOAD | ✅ core — funded check + debit source |
| R6 | `_fundingSourceOf[player]` | `:649` | SLOAD | rare — ONLY if `FLAG_EXTERNAL_FUNDING` set (common self-funded path skips entirely, OPENE-02) |
| R7 | `afkingFunding[src]` (funding-skip) | `:662` | SLOAD | rare — only if `src != player`; common path reuses R5 (no extra SLOAD) |

### Per-subscriber WRITES (common funded path)

| # | Access | Site | Type | Strictly necessary? |
|---|--------|------|------|---------------------|
| W1 | `afkingFunding[src] -= ethValue` | `:709` | SSTORE | ✅ **core, solvency-critical** (only if ethValue≠0) |
| W2 | `claimablePool -= uint128(ethValue)` | `:710` | SSTORE | ✅ **core — SOLVENCY-01, must stay byte-identical in v56** |
| W3 | `sub.scorePlus1` + `sub.amount` (lootbox stamp) | `:793-794` | 1 SSTORE (warm Sub slot) | ✅ core (lootbox) — IS the box record; materialized at open |
| W4 | `sub.lastAutoBoughtDay = processDay` | `:840` | same slot | ✅ core — idempotency marker + the open's frozen seed `day` |
| W5 | `sub.lastOpenedDay = processDay` (ticket mode only) | `:734` | same slot | ✅ core (ticket) — keeps the open leg/no-orphan guard from treating a ticket sub as box-pending |

### The cross-contract "storm" (lootbox branch `:749-832`) — NONE necessary for the buy to *function*

| Call | Site | What it does | v56 disposition |
|------|------|-------------|-----------------|
| `quests.handlePurchase` | `:760` | quest credit → QUESTS writes + an internal COINFLIP `creditFlip` (and the **O1** double-credit at `DegenerusQuests:890`) | **DEFER → settle** (AGG-01). v56 removes this from the per-buy path entirely; O1 fixed at source |
| `recordMintQuestStreak` | `:773` | streak bookkeeping (self-call), if questCompleted && questType==1 | **DEFER → settle** |
| `_playerActivityScore` | `:785` | reads activity inputs → the stamped score | **partially necessary** — the box STAMP needs the score; the affiliate-taper use of it defers |
| `affiliate.payAffiliate` (fresh) | `:806` | leaderboard (`affiliateCoinEarned` + `_totalAffiliateScore` + `_updateTopAffiliate`) + winner-takes-all roll + `handleAffiliate`→QUESTS + `_routeAffiliateReward`→COINFLIP | **DEFER → settle** — accrue base only per-buy (AGG-01); leaderboard one batched write at settle (option A) |
| `affiliate.payAffiliate` (claimable) | `:816` | same, for the claimable-funded portion | **DEFER → settle** |
| `coinflip.creditFlip(player, flipCredit)` | `:831` | the per-buy reward payout (quest + both affiliate kickbacks) | **DEFER → settle** — one batched creditFlip per window |

**Ticket mode is worse:** the entire `purchaseWith` delegatecall (`:718-731`, the ~262k binding case) does the ticket-queue write **plus** its own internal storm. v56 replaces it with a minimal "write the ticket entries to the queue" primitive + the same deferred accrue.

### Irreducible afking buy (v56 target)
```
reads:  R1 (player) + R2 (Sub) + R3 (swept) + R5 (afkingFunding[player])
debit:  W1 (afkingFunding -=) + W2 (claimablePool -=)        [solvency, byte-unchanged]
stamp:  W3+W4 (lootbox: scorePlus1/amount/lastAutoBoughtDay)  OR  minimal ticket-queue write + W5
accrue: +1 warm SSTORE  (affiliate base + quest progress + window markers)
```
**Caveat (from `353-RESEARCH.md` §2):** the `Sub` slot is full (232/256), so the accumulator can NOT pack into Sub spare bits — it needs a **new dedicated cold slot**. The accrue is therefore one warm per-buy SSTORE into that dedicated slot (still vastly cheaper than the ~5-call cross-contract storm it replaces). GAS-02 is re-framed accordingly.

---

## 2. AFKING OPEN — `_autoOpen` (`:938`) → `_openAfkingBox` (`:888`) → `resolveAfkingBox` (LootboxModule), per box

**Hoisted per call:** `rngLockedFlag` + `_livenessTriggered()` entry gate (`:941`), `_subscribers.length` (`:943`), `_subOpenCursor` (`:945` 1 SLOAD / `:965` 1 SSTORE).

### Per-box READS

| # | Access | Site | Type | Strictly necessary? |
|---|--------|------|------|---------------------|
| R1 | `_subscribers[cursor]` → player | `:951` | SLOAD | ✅ core |
| R2 | `_subOf[player]` (lastOpenedDay, lastAutoBoughtDay, amount, scorePlus1) | `:952` | 1 SLOAD (warm) | ✅ core |
| R3 | `rngWordByDay[lastAutoBoughtDay]` (readiness `:921` + resolve `:905`) | `:921`/`:905` | SLOAD (warm 2nd use) | ✅ core — the box's frozen RNG word |

### Per-box WRITES

| # | Access | Site | Type | Strictly necessary? |
|---|--------|------|------|---------------------|
| W1 | `sub.lastOpenedDay = day` | `:892` | SSTORE (warm slot) | ✅ **core — no-double-open, effects-before-interaction** |
| RW2 | inside `resolveAfkingBox`: EV-cap `lootboxEvBenefitUsedByLevel[player][level]` RMW + live `level` read + ticket-queue writes | delegatecall `:897-908` | SLOAD + cond. SSTORE + queue writes | ✅ **core — IS the box payout** |
| W3 | `_subOpenCursor = uint16(cursor)` | `:965` | SSTORE (per call) | ✅ core — walk progress |
| W4 | `coinflip.creditFlip(msg.sender, bountyEarned)` | `:1015` | SSTORE (per call, in `mintBurnie`) | keeper incentive — necessary for the permissionless-open model, not per-box |

### Verdict on OPEN: already lean
No cold ledger — the box is the warm `Sub` stamp + `rngWordByDay[day]`. One marker write (W1), the EV-cap RMW + ticket-queue write that *are* the box (RW2), one cursor write per call, one bounty creditFlip per call. There is essentially **no fat to cut on open**. OPEN-01's job is to confirm exactly this: cheapest materialization shared with the human `openLootBox` path, `lastOpenedDay` monotone no-double-open, EV-cap drawn exactly-once per `(player, level)`, no shared-state hazard with the human route.

**All the v56 everyday-gas savings live on the BUY side** (collapsing the cross-contract storm into a cheap accrue + a deferred settle). The OPEN side is a re-verification (unmanipulability + no-double-open), not an optimization target.

---

*Generated 2026-06-01 for Phase 353 (v56.0 SPEC design-lock). Anchors verified vs `453f8073`.*
