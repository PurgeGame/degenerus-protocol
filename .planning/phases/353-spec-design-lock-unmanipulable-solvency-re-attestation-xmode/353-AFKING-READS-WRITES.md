# AfKing Buy + Open — Storage Reads/Writes Inventory

**Purpose:** A SLOAD/SSTORE map of the everyday afking paths, marking which accesses are *strictly necessary for the path to function* vs the deferrable "extraneous stuff" v56 batches into the ~10-day settle. The gas-optimization substrate for the v56.0 SPEC (feeds AGG/GAS/TKT/OPEN).

**Source:** `contracts/modules/GameAfkingModule.sol` @ the v55.0 frozen subject `453f8073` (working tree byte-identical, per `353-RESEARCH.md`).

**Verdict legend**

| Mark | Meaning |
|:--:|---|
| ✅ | core — required for the path to function |
| 💰 | solvency-critical — the ETH/`claimablePool` debit (must stay byte-unchanged in v56) |
| ⚠️ | conditional — only needed in some sub configs |
| ◑ | rare — only on an uncommon branch (common path skips) |
| 🔁 | **deferrable** — the cross-contract "extraneous stuff" v56 moves to the settle |

> The `Sub` record is a **single 256-bit slot** (232/256 packed — `DegenerusGameStorage.sol:1867-1899`), so every per-sub field touch is ONE warm SLOAD / ONE warm SSTORE (marked `¹`).

---

## 1. AFKING BUY — `processSubscriberStage` (`:539`), per subscriber

**Hoisted once per chunk** (not per-sub): price/`_activeTicketLevel` (`:543`), `level`→`currentLevel` (`:546`), `_subCursor` (1 SLOAD in `:548` / 1 SSTORE out `:849`).

### Reads

| Access | Site | Op | |
|---|---|---|:--:|
| `_subscribers[cursor]` → player | `:551` | SLOAD | ✅ |
| `_subOf[player]` (flags, markers, dailyQty, reinvestPct, validThroughLevel, scorePlus1, amount) | `:552` | SLOAD¹ | ✅ |
| `_goRead(swept)` | `:461` | SLOAD | ✅ |
| `claimableWinnings[player]` | `:463` | SLOAD | ⚠️ |
| `afkingFunding[player]` → playerFunding | `:464` | SLOAD | ✅ |
| `_fundingSourceOf[player]` | `:649` | SLOAD | ◑ |
| `afkingFunding[src]` (funding-skip) | `:662` | SLOAD | ◑ |

### Writes (common funded path)

| Access | Site | Op | |
|---|---|---|:--:|
| `afkingFunding[src] -= ethValue` | `:709` | SSTORE | ✅💰 |
| `claimablePool -= uint128(ethValue)` | `:710` | SSTORE | ✅💰 |
| stamp `sub.scorePlus1` + `sub.amount` (lootbox) | `:793-794` | SSTORE¹ | ✅ |
| `sub.lastAutoBoughtDay = processDay` | `:840` | SSTORE¹ | ✅ |
| `sub.lastOpenedDay = processDay` (ticket only) | `:734` | SSTORE¹ | ✅ |

### The cross-contract "storm" (lootbox branch `:749-832`) — all deferrable

| Call | Site | What it costs | |
|---|---|---|:--:|
| `quests.handlePurchase` | `:760` | QUESTS writes + internal COINFLIP credit (+ the **O1** double-credit `:890`) | 🔁 |
| `recordMintQuestStreak` | `:773` | self-call (streak bookkeeping) | 🔁 |
| `_playerActivityScore` | `:785` | activity SLOADs | ⚠️🔁 |
| `affiliate.payAffiliate` (fresh) | `:806` | 3 leaderboard writes + roll + 2 cross-calls | 🔁 |
| `affiliate.payAffiliate` (claimable) | `:816` | same | 🔁 |
| `coinflip.creditFlip(player, …)` | `:831` | the per-buy reward payout | 🔁 |

**Notes**
- **`_subOf` (R2)** — one slot, warm after the first field read; covers the no-orphan guard, tombstone, idempotency, pass-gate, and `_resolveBuy` reads.
- **`claimableWinnings` (R4)** — only *meaningful* when `reinvestPct>0` or `drainFirst`; read unconditionally today (skipped only when swept).
- **`_fundingSourceOf` / `afkingFunding[src]` (R6/R7)** — common self-funded path skips both (OPENE-02); only the operator-funded sub (`FLAG_EXTERNAL_FUNDING`) pays them.
- **`claimablePool -= ` (W2)** — the SOLVENCY-01 site; v56 keeps it byte-unchanged (affiliate/quest are BURNIE-only, never an ETH cut).
- **`_playerActivityScore`** — the box *stamp* genuinely needs the score (frozen into `scorePlus1`); only its affiliate-taper use defers.
- **Ticket mode is worse:** the whole `purchaseWith` delegatecall (`:718-731`, ~262k) does the queue write **plus** its own internal storm. v56 replaces it with a minimal queue-write + the same deferred accrue.

### Irreducible afking buy (v56 target)

```
reads:  R1 player · R2 Sub · R3 swept · R5 afkingFunding[player]
debit:  W1 afkingFunding -= · W2 claimablePool -=        [💰 byte-unchanged]
stamp:  W3+W4 (lootbox)  OR  minimal ticket-queue write + W5
accrue: +1 warm SSTORE   (affiliate base + quest progress + window markers)
```

**Accumulator (LOCKED — USER 2026-06-01, supersedes RESEARCH §3):** the `Sub` slot starts at 232/256 (24 spare), but the accumulator fits **in the same slot** — NO new cold slot — via: (1) affiliate base in **whole BURNIE**, uint32 with a **100M saturating clamp** (per-window accrual never exceeds 100M; round-down <1 BURNIE is immaterial); (2) **re-pack** the Sub struct — `amount` in 0.001-ETH/milli-ETH units (uint96→~uint32), `validThroughLevel`+`lastAutoBoughtDay`+`lastOpenedDay` uint32→uint24 — reclaiming well over the ~64 bits needed; (3) `windowStartDay` dropped (derived from a global ~10-day epoch). So the accrue is **one warm per-buy SSTORE into the re-packed Sub slot, zero new cold SSTORE** — even cheaper than RESEARCH's new-slot option. GAS-02 re-framed accordingly; exact widths confirmed at IMPL 354.

---

## 2. AFKING OPEN — `_autoOpen` (`:938`) → `_openAfkingBox` (`:888`) → `resolveAfkingBox`, per box

**Hoisted per call:** entry gate `rngLockedFlag` + `_livenessTriggered()` (`:941`), `_subscribers.length` (`:943`), `_subOpenCursor` (1 SLOAD `:945` / 1 SSTORE `:965`).

### Reads

| Access | Site | Op | |
|---|---|---|:--:|
| `_subscribers[cursor]` → player | `:951` | SLOAD | ✅ |
| `_subOf[player]` (markers, amount, scorePlus1) | `:952` | SLOAD¹ | ✅ |
| `rngWordByDay[lastAutoBoughtDay]` (ready + resolve) | `:921`/`:905` | SLOAD | ✅ |

### Writes

| Access | Site | Op | |
|---|---|---|:--:|
| `sub.lastOpenedDay = day` (no-double-open) | `:892` | SSTORE¹ | ✅ |
| EV-cap `lootboxEvBenefitUsedByLevel[player][level]` RMW + ticket-queue writes | `resolveAfkingBox` `:897-908` | SLOAD + SSTORE | ✅ |
| `_subOpenCursor = cursor` | `:965` | SSTORE | ✅ |
| `coinflip.creditFlip(msg.sender, bounty)` (in `mintBurnie`) | `:1015` | SSTORE | bounty |

**Verdict on OPEN: already lean.** No cold ledger — the box is the warm `Sub` stamp + `rngWordByDay[day]`. One marker write (W1), the EV-cap RMW + queue write that *are* the box, one cursor write per call, one bounty per call. **There is no fat to cut on open** — OPEN-01's job is to confirm exactly this (shared cheapest materialization with human `openLootBox`, `lastOpenedDay` monotone, EV-cap exactly-once, no shared-state hazard).

**All v56 everyday-gas savings live on the BUY side** (collapsing the storm into a cheap accrue + a deferred settle). OPEN is a re-verification (unmanipulability + no-double-open), not an optimization target.

---

*Generated 2026-06-01 for Phase 353 (v56.0 SPEC design-lock). Anchors verified vs `453f8073`.*
