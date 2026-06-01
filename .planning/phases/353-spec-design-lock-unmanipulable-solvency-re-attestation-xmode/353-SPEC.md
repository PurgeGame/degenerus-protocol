# Phase 353 — v56.0 Design-Lock SPEC

**Phase:** 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode
**Milestone:** v56.0 — AfKing Everyday-Gas Minimization
**Baseline / frozen subject:** `453f8073` (`MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`)
**Status:** DRAFT (the XMODEL fold-in + the SPEC Lock are PENDING — Plan 02)
**Authored:** 2026-06-01
**Scope note:** PAPER-ONLY. ZERO `contracts/*.sol` mutation is permitted or expected in Phase 353. Every section below cites identifiers + line ranges + behavior only — NO contract code is authored or inlined. The implementation is owned by Phase 354 (IMPL); the empirical proofs by Phase 356 (TST); the close by Phase 357 (TERMINAL).

This SPEC is the **producer**: it design-locks AFF-01 / AFF-02 (OWNED here) and folds in every design feed the IMPL (354) / GAS (355) / TST (356) / TERMINAL (357) phases consume. Plan 02 (the XMODEL cross-model pass) pressure-tests this draft, folds its disposition table into the `## XMODEL-01` section, and then flips the `## SPEC Lock` placeholder.

---

## Anchor Attestation (vs 453f8073)

Every cited `file:line` below was grep/`sed`-re-attested against the working tree on 2026-06-01. Per the frozen-subject guard (next subsection), the working tree is byte-identical to `453f8073`, so each attested line **equals the frozen subject**. The table reconciles the ROADMAP/CONTEXT bare module names to their `contracts/modules/...` full paths and records every drift.

| # | Anchor (as cited upstream) | Reconciled path:line | Symbol confirmed | Drift note |
|---|----------------------------|----------------------|------------------|------------|
| A1 | afking per-buy cross-contract storm `GameAfkingModule.sol:760-831` | `contracts/modules/GameAfkingModule.sol:708-833` (debit `:709-710`; `quests.handlePurchase` `:760`; `affiliate.payAffiliate` `:806`+`:816`; per-buy `coinflip.creditFlip` `:831`) | Y | **DRIFT #1** — the storm spans `:708-833`; the cited `:760-831` is the inner span only. SPEC widens to `:708-833`. |
| A2 | lootbox stamp branch `:735-749` | `contracts/modules/GameAfkingModule.sol:735-833` (the `else` lootbox-stamp branch; comment header `:735-746`; stamp body to `:833`) | Y | OK — `:735` opens the branch; the stamp work extends to `:833`. |
| A3 | ticket-mode `purchaseWith` route `:713-731` | `contracts/modules/GameAfkingModule.sol:713-731` (`if (isTicket)` → `purchaseWith` delegatecall) | Y | EXACT. |
| A4 | affiliate daily-seeded roll `DegenerusAffiliate.sol:558` | `contracts/DegenerusAffiliate.sol:558-567` — `keccak256(AFFILIATE_ROLL_TAG, GameTimeLib.currentDayIndex(), sender, storedCode) % 20` | Y | EXACT (the `roll` decl is `:558`; the `keccak256` body runs `:559-567`). |
| A5 | buyer-never-wins `:579` | `contracts/DegenerusAffiliate.sol:579` — `if (winner != sender) { ... }` (when the buyer would win, the whole reward incl. quest credit is SKIPPED, not redirected) | Y | EXACT. |
| A6 | leaderboard writes `:510`/`:511`/`:521` | `contracts/DegenerusAffiliate.sol:510` (`earned[affiliateAddr] = newTotal`), `:511` (`_totalAffiliateScore[lvl] += scaledAmount`), `:521` (`_updateTopAffiliate(...)`) | Y | EXACT. |
| A7 | `_updateTopAffiliate:776` (read-once-compare) | `contracts/DegenerusAffiliate.sol:776-783` — 1 SLOAD (`affiliateTopByLevel[lvl]`) + conditional SSTORE only when `score > current.score` | Y | EXACT (D-08 confirmed). |
| A8 | taper `:504`/`:787` (`_applyLootboxTaper`) | call site `contracts/DegenerusAffiliate.sol:504-506`; impl `:787-795`; monotone-down (returns `amt * factor`, `factor ≤ BPS_DENOMINATOR`) | Y | EXACT (taper-only-reduces confirmed). |
| A9 | 1%-top consumer `DegenerusGameAdvanceModule.sol:700` (`_rewardTopAffiliate`) | `contracts/modules/DegenerusGameAdvanceModule.sol:700` — `function _rewardTopAffiliate(uint24 lvl)` (reads `affiliate.affiliateTop(lvl)`) | Y | EXACT (bare-name reconciled to `contracts/modules/`). |
| A10 | 5%-proportional consumer `DegenerusGameBingoModule.sol:217` (`claimAffiliateDgnrs`) | `contracts/modules/DegenerusGameBingoModule.sol:216` — `function claimAffiliateDgnrs(address player)` (reads cumulative `affiliateScore`/`totalAffiliateScore`, NOT the live ranking) | Y | **DRIFT #2** — it is `:216`, not `:217`. SPEC cites `:216`. |
| A11 | `DegenerusQuests.sol` `handlePurchase` `:763-898`; O1 at `:887`/`:890`/`:893` | `contracts/DegenerusQuests.sol:763-898`; burnie credit (KEEP) `:887`; **lootbox credit (DROP) `:890`** inside the `if (lootboxReward != 0)` at `:889`; `totalReturned = ethMintReward + lootboxReward` (KEEP) `:893` | Y | **DRIFT #4** — the O1-drop `creditFlip` is line `:890`, inside the `if` at `:889`. SPEC cites `:890` / guard `:889`. |
| A12 | `awardQuestStreakBonus:365` | `contracts/DegenerusQuests.sol:365-384` (`onlyGame`; adds streak days; clamps uint24) | Y | EXACT. |
| A13 | afking open path `_openAfkingBox`→`resolveAfkingBox` + `mintBurnie`/`_autoOpen`/`OPEN_BATCH` | `contracts/modules/GameAfkingModule.sol`: `_openAfkingBox` `:888-910`, `_afkingBoxReady` `:918-922`, `_autoOpen` `:938-966`, `mintBurnie` `:985-...`, `OPEN_BATCH` const `:191`; `resolveAfkingBox` `contracts/modules/DegenerusGameLootboxModule.sol:877-...` | Y | EXACT. |
| A14 | `Sub` 4-field stamp + `lastOpenedDay` in `DegenerusGameStorage.sol` | `contracts/storage/DegenerusGameStorage.sol:1867-1899` — config 56b (`dailyQuantity`8 + `validThroughLevel`32 + `reinvestPct`8 + `flags`8) + stamp 112b (`scorePlus1`16 + `amount`96) + markers 64b (`lastAutoBoughtDay`32 + `lastOpenedDay`32) = **232/256**; `mapping(address=>Sub) _subOf` `:1902` | Y | **DRIFT #5 (accumulator-layout premise)** — the slot is at **232/256 (24 spare)**, NOT the "176/256" CONTEXT/PLAN premise. See `## Accumulator Layout`. |
| A15 | EV-cap `lootboxEvBenefitUsedByLevel[player][level+1]` | `contracts/modules/DegenerusGameLootboxModule.sol` — `_applyEvMultiplierWithCap` `:459-495`; afking call `:902` with `currentLevel = level + 1` (`:894`) | Y | **DRIFT #6** — the EV-cap key is `[player][currentLevel]` where `currentLevel == level + 1` (`:894`/`:902`). SPEC records the key form. |
| A16 | STAGE placement in `DegenerusGameAdvanceModule.sol` | `contracts/modules/DegenerusGameAdvanceModule.sol`: `SUB_STAGE_BATCH` const `:149`; per-buy storm driver via `processSubscriberStage` (`contracts/modules/GameAfkingModule.sol:539`) | Y | EXACT (bare-name reconciled). |
| A17 | `MintModule:1243` century bonus (ROADMAP bare name) | `contracts/modules/DegenerusGameMintModule.sol:1243` — `if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0)` (ticket-mode only); body `:1243-1259` | Y | EXACT (bare-name reconciled). |
| A18 | MintModule O1 re-credit (`:1222-1232`, `:1366-1367`) | `contracts/modules/DegenerusGameMintModule.sol:1222` (`handlePurchase` call), `:1232` (`lootboxFlipCredit += questReward`), `:1366-1367` (batched `creditFlip(buyer, lootboxFlipCredit)`) | Y | EXACT (bare-name reconciled). |
| A19 | `handleLootBox` dead `:698-742` + interface `:107` | `contracts/DegenerusQuests.sol:698-741` (the fn; internal `creditFlip` `:739`); interface decl `contracts/interfaces/IDegenerusQuests.sol:107`; **NO production caller** (only comment refs `:746` / `IDegenerusQuests:126`; test refs in `test/`) | Y | **DRIFT #3** — the fn is `:698-741`, not `:698-742`. SPEC cites `:698-741`. |
| A20 | clean handlers — `handleMint` guard `:513`, `handleFlip` `:533`, `handleDecimator` credit `:629`, `handleAffiliate` `:644`, `handleDegenerette` credit `:954` | `contracts/DegenerusQuests.sol` — `handleMint` guard `:513` (`if (!paidWithEth && totalReward != 0)`); `handleFlip` `:533`; `handleDecimator` `:589` / credit `:629`; `handleAffiliate` `:644`; `handleDegenerette` `:913` / credit `:954` | Y | EXACT (D-04 confirmed — the O1 pattern is ISOLATED to `handlePurchase`'s lootbox leg). |
| A21 | external clean callers — `BurnieCoin:613`, `BurnieCoinflip:275`, `DegeneretteModule:467` | `contracts/BurnieCoin.sol:613` (`handleDecimator`, weight-boost dual-use); `contracts/BurnieCoinflip.sol:275` (`handleFlip`, credited once); `contracts/modules/DegenerusGameDegeneretteModule.sol:467` (`handleDegenerette`, return ignored) | Y | EXACT (D-04 confirmed). |

### Net Drift Recorded (the 5 reconciliations the SPEC carries forward)

1. **Storm range** — the per-buy cross-contract storm is `GameAfkingModule.sol:708-833`, NOT the ROADMAP's `:760-831` (the cited span is the inner storm; the debit at `:709-710` and the stamp tail at `:833` bracket it).
2. **`claimAffiliateDgnrs`** — `DegenerusGameBingoModule.sol:216`, NOT `:217` (one-line off-by-one).
3. **`handleLootBox` dead code** — `DegenerusQuests.sol:698-741`, NOT `:698-742`.
4. **O1-drop `creditFlip`** — line `:890`, inside the `if (lootboxReward != 0)` guard at `:889` (the burnie-credit KEEP is `:887`; the `totalReturned` KEEP is `:893`).
5. **EV-cap key** — `lootboxEvBenefitUsedByLevel[player][currentLevel]` where `currentLevel = level + 1` (`DegenerusGameLootboxModule.sol:894`/`:902`).

(A sixth reconciliation — the accumulator-layout "176/256 → 232/256" premise drift — is folded into A14 and fully resolved in `## Accumulator Layout`.)

All ROADMAP bare module names are reconciled to `contracts/modules/...` full paths in the table above (e.g. `MintModule:1243` → `contracts/modules/DegenerusGameMintModule.sol:1243`; `GameAfkingModule.sol:760` → `contracts/modules/GameAfkingModule.sol:760`).

### Frozen-Subject Guard

`git diff --quiet 453f8073 HEAD -- contracts/` returns **clean** (re-verified 2026-06-01 at execution start — exit 0, `FROZEN_GUARD_PASS`). HEAD is `453f8073` plus docs-only commits, and `453f8073` is an ancestor of HEAD. Therefore the working-tree `contracts/` is **byte-identical** to the frozen subject, and every `file:line` attested above was read directly from the working tree and **equals** the frozen subject `453f8073` — no `git show 453f8073:<path>` indirection was needed. No "by construction" anchor survives un-checked in this SPEC: each load-bearing line is grep/`sed`-attested in this table.

---

## AFF-01 — Affiliate Roll Non-Gameability (LOCKED)

**Requirement OWNED by Phase 353.** AFF-01 locks that the v56 affiliate distribution is non-gameable by settle-timing. Three load-bearing facts, all anchor-attested above, ground the lock (per D-09 + RESEARCH §2.1):

1. **The roll seed's only mutable input is `currentDayIndex()`** — a pure function of `block.timestamp` (`contracts/libraries/GameTimeLib.sol:21-34`; `currentDayIndex()` → `currentDayIndexAt(uint48(block.timestamp))`). The day index advances once per ~24h at the wall-clock boundary; a player **cannot select a day index within a transaction**. So "choosing a favorable roll" demands waiting a full wall-clock day, over which the roll is EV-neutral anyway. The roll body is `keccak256(AFFILIATE_ROLL_TAG, currentDayIndex(), sender, storedCode) % 20` (`contracts/DegenerusAffiliate.sol:558-567`).

2. **The buyer can NEVER receive the roll** — `if (winner != sender)` (`contracts/DegenerusAffiliate.sol:579`). When the roll would pay the buyer, the **entire reward (including the quest credit) is SKIPPED, not redirected** (the guarded block performs both the `handleAffiliate` quest credit and the `_routeAffiliateReward`; neither fires when `winner == sender`). So `sender` (the afking subscriber / their funding wallet) has **zero EV** from the roll outcome regardless of timing.

3. **Redistribution is intra-upline-chain-only** — the roll picks among `affiliateAddr` (75%, roll 0-14), `upline1` (20%, roll 15-18), `upline2` (5%, roll 19) via `_referrerAddress` (`contracts/DegenerusAffiliate.sol:569-576`). Manipulation only moves value among the buyer's own affiliate chain; it never creates or destroys protocol value.

**The design assertion LOCKED:** under the v56 aggregator, the scheduled ~10-day flush re-runs this **same winner-takes-all daily-seeded roll**, seeded by the **FIXED window-boundary day** — a deterministic function of the sub's own subscribe day (`windowStartDay + WINDOW_LEN`-equivalent), **NOT** the live settle-call `currentDayIndex()` (RESEARCH §9 risk #6). The **player-triggered-alteration path** (sub/unsub/param-change flush) uses the **deterministic 75/20/5 split with NO roll** — so a player who flushes early cannot select a roll seed at all. Both paths are timing-immune by facts 1–3.

**No-by-construction obligation (TST 356 must PROVE, SEC-01):** the settle-leg roll seeds on the **window-boundary day**, not the live settle-call day. Because `currentDayIndex()` only changes at the wall-clock boundary the residual risk is small, but the SPEC does NOT accept it "by construction" — TST 356 asserts the seed equals the boundary day so a keeper cannot nudge the seed by choosing WHEN within a day to call the flush. (XMODEL concern C2 also pressure-tests this; see `## XMODEL-01`.)

---

## AFF-02 — Taper-at-Accrue + Leaderboard Option-A (LOCKED)

**Requirement OWNED by Phase 353.** AFF-02 locks the per-buy taper and the option-A leaderboard fold.

### (a) Taper applied per-buy at accrue (immutable, only-reduces)

`_applyLootboxTaper` (`contracts/DegenerusAffiliate.sol:787-795`) is a linear taper 100%→25% as the activity score rises from `LOOTBOX_TAPER_START_SCORE` to `LOOTBOX_TAPER_END_SCORE`; it **only reduces** (`return amt * (BPS_DENOMINATOR - reductionBps) / BPS_DENOMINATOR`, `reductionBps ≥ 0`), applied at the call site `:504-506` BEFORE the leaderboard write. **LOCK:** the v56 accrue path applies the taper **per-buy** on the activity score read at the box stamp (the same `scorePlus1` the lootbox stamp freezes — `GameAfkingModule.sol:793-794`), storing the **already-tapered base** in the accumulator. Because the taper is monotone-down and applied per-buy, **clustering buys into one settle cannot dodge a higher-score taper** — each buy is tapered at its own score, taper-only-reduces → no favorable timing.

### (b) Leaderboard OPTION A (D-07) — one batched settle-level write

At settle, the lumped leaderboard write reproduces `payAffiliate`'s write set (`contracts/DegenerusAffiliate.sol:508-521`) for the accumulated, already-tapered base:

1. `earned[affiliateAddr] += accumulatedBase` (`:510` analog) — warm SSTORE.
2. `_totalAffiliateScore[lvl] += accumulatedBase` (`:511` analog) — warm SSTORE.
3. `_updateTopAffiliate(affiliateAddr, newTotal, lvl)` (`:521` analog) — the **read-once-compare** (`:776-783`): 1 SLOAD + a conditional SSTORE only when the new total beats the top (D-08; cheap).

`lvl` for option A = the **settle-level** (the live `level + 1` at settle time), NOT the buy-time level. v56's aggregator already collapses the current per-buy ×2 `payAffiliate` leaderboard writes into this one-per-window write.

### (c) The accepted cross-level lag (stated explicitly so TST/TERMINAL do not flag it)

Affiliate scores route to `level + 1` during gameplay and freeze at index `lvl` on the L→L+1 transition (`DegenerusGameAdvanceModule.sol:695-696` comment in `_rewardTopAffiliate`). Under option A, a scheduled settle firing AFTER an L→L+1 transition writes the accumulated base to the **settle-time level**, so buys made during level L that settle during level L+1 land their leaderboard credit at index L+1 (one level late). **This is the ACCEPTED lag** (D-07). The SPEC states it explicitly; TST/TERMINAL must NOT flag it as a finding.

### (d) Force-flush-before-jackpot — DECLINED (the §2.4 rationale)

The 5%-proportional DGNRS claim (`claimAffiliateDgnrs`, `contracts/modules/DegenerusGameBingoModule.sol:216`) reads the **cumulative** `affiliate.affiliateScore` (= `affiliateCoinEarned[lvl][player]`) and `affiliate.totalAffiliateScore` (= `_totalAffiliateScore[lvl]`), NOT the live `affiliateTop` ranking; `reward = allocation × score / totalScore`. Option A's lag affects WHICH level the afking slice lands in, but the proportional claim is **exact** for whatever lands at that level (numerator and denominator move together). The only ranking-sensitive consumer is `_rewardTopAffiliate` (the 1%-top, `contracts/modules/DegenerusGameAdvanceModule.sol:700`), a single-winner snapshot at transition — the afking slice landing one level late simply competes in the next level's ranking, and the afking slice is tapered + a minority of the pool. **Therefore force-flush is DECLINED** (option A as-is). TST 356 verifies the proportional claim is exact regardless of lag.

### (e) The leaderboard is NOT deletable (D-06 — cite both consumers)

It pays real DGNRS at every level transition: (1) **1% of the DGNRS Affiliate pool → the top affiliate** (`_rewardTopAffiliate`, `DegenerusGameAdvanceModule.sol:700`); (2) **5% snapshotted, score-proportional per-affiliate claim** (`claimAffiliateDgnrs`, `DegenerusGameBingoModule.sol:216`). The leaderboard stays; option A keeps it cheap (the read-once-compare).

---

## Accumulator Layout (CORRECTED — GAS-02 design feed) (LOCKED — USER 2026-06-01, supersedes RESEARCH §3 Option B)

### Starting occupancy — the premise drift

CONTEXT/PLAN's "the Sub 4-field stamp uses 176/256 → ~80 spare bits" is **inaccurate**. The attested `Sub` struct (`contracts/storage/DegenerusGameStorage.sol:1867-1899`) packs **232 of 256 bits** in its single slot — config 56b (`dailyQuantity`8 + `validThroughLevel`32 + `reinvestPct`8 + `flags`8) + stamp 112b (`scorePlus1`16 + `amount`96) + markers 64b (`lastAutoBoughtDay`32 + `lastOpenedDay`32). **Spare in the existing slot: 24 bits** (not ~80). There is no 176-bit "4-field stamp"; the stamp proper is `scorePlus1`(16) + `amount`(96) = 112b, but the slot also carries 56b config + 64b markers.

### The LOCKED decision — fit IN the re-packed Sub slot (NO new cold slot)

This **SUPERSEDES RESEARCH §3's Option-B (new dedicated cold slot) recommendation.** The accumulator fits in the **SAME single Sub slot** via a re-pack + denomination change, which is cheaper than Option B (it avoids the per-window cold-slot touch entirely). Four locked principles:

1. **Whole-BURNIE affiliate base.** Denominate the accumulated affiliate base in **WHOLE BURNIE** (not 1e18 base units). The per-buy round-down (<1 BURNIE) is **immaterial** — this is a BURNIE reward credit, OFF the ETH/`claimablePool` solvency path, and v56 is explicitly **not** behavior-identical (slight semantic simplifications are accepted under the v56 scope latitude). Magnitude math: `_ethToBurnie(amount, mp) = qty × 1000` whole BURNIE per buy at the box rate; × the ~20% affiliate rate ≈ `qty × 200` whole BURNIE/buy → `≈ qty × 2000` whole BURNIE over a ~10-day window.

2. **uint32 with a 100M saturating clamp.** Store `affiliateBase` as **uint32 with a SATURATING CLAMP at 100,000,000 whole BURNIE** (USER 2026-06-01: the per-window accrual never exceeds 100M whole BURNIE in this game; the clamp caps the unbounded reinvest-whale `effectiveQty` edge — **acceptable** for a BURNIE reward credit off the solvency path; the clamp can only ever *under-credit* the extreme whale, never over-credit, so it cannot be a positive-EV lever). uint32 holds ~4.29e9 > 100M, so the clamp binds before the type does.

3. **Re-pack the Sub struct (free under pre-launch redeploy-fresh).** Reclaim the bits the accumulator needs by narrowing fields whose current widths are wastefully wide:
   - `amount` stored in **0.001-ETH / milli-ETH units** (USER: "round amount to .001 eth") — uint96 → **~uint32** (≈4.3M ETH of headroom in milli-ETH). The granularity is chosen **well below the min box size**, so the box-spend round-down is a negligible haircut vs the full-wei debit (the SOLVENCY-01 ETH debit at `:709-710` uses the full `ethValue` and stays byte-unchanged — the rounding is on the *stamp's* recorded `amount`, the EV/seed input, not on the ETH cut).
   - `validThroughLevel` uint32 → **uint24** (USER: levels never approach 16.7M; uint24 = 16,777,215 levels of headroom).
   - `lastAutoBoughtDay` / `lastOpenedDay` uint32 → **uint24** (45,000-year day-index headroom).

   This reclaims **well over the ~64 bits** the accumulator needs — a comfortable margin, NOT a tight fit.

4. **The accumulator lives in the SAME single re-packed Sub slot.** The accumulator = `affiliateBase` (uint32, whole-BURNIE, 100M-clamped) + `lastSettledDay` (uint24) + `questProgress` (uint8). It co-resides with the re-packed config/stamp/markers in the **one** Sub slot → **NO new cold slot**. The per-buy accrue stays **ONE warm SSTORE** into the Sub slot (the slot is already warm after the stamp read at `:552`). `windowStartDay` is **DROPPED** — the window boundary is derived from a global ~10-day epoch (`currentDay - lastSettledDay >= 10`).

### Documented magnitudes + immateriality

- **Starting occupancy:** 232/256 (24 spare) — the attested figure, superseding the "176/256" premise.
- **Whale-magnitude math:** `≈ qty × 2000` whole BURNIE accrued per ~10-day window (well within the 100M clamp for any realistic per-window `qty`; the clamp only bites the pathological reinvest-whale edge, where under-crediting is acceptable).
- **Per-buy round-downs (immaterial, off the solvency path):** the affiliate-base whole-BURNIE round-down (<1 BURNIE/buy) and the `amount` milli-ETH round-down (sub-min-box-size) are both reward/EV-input roundings, NOT solvency-ledger roundings — the ETH/`claimablePool` debit (`GameAfkingModule.sol:709-710`) consumes the full `ethValue` and is byte-unchanged.

**Exact final field widths are confirmed at IMPL 354.** This SPEC locks the **principles** — whole-BURNIE + 100M clamp + amount→milli-ETH rounding + narrowed `validThroughLevel`/day-marker fields + the in-slot accumulator + the global ~10-day epoch — not the precise bit allocation. **GAS-02 is re-framed:** "one warm per-buy SSTORE into the re-packed Sub slot — NO new cold SSTORE." Note: the accumulator fields and the open-end markers (`lastOpenedDay`, etc.) co-reside in the one slot — they are written on different paths (buy-accrue vs open) but that is the **same warm slot**, no extra cold cost and no collision (the open advances `lastOpenedDay`; the accrue advances `affiliateBase`/`lastSettledDay`/`questProgress`; they are disjoint fields in the shared slot).

---

## Threat Model Re-Attestation (SEC design feed) (LOCKED)

The design-level **unmanipulable / SOLVENCY-01-untouched / RNG-freeze-intact** assertions (per RESEARCH §8.1). One row per invariant with its source anchor and its TST-356 proof obligation. **SEC-01 / SEC-02 are OWNED (proven empirically + adversarially) at TST 356** — this SPEC is the **design gate** (any hole the SPEC cannot close on paper is a blocking design threat; none remains open at lock).

| Invariant | Source anchor | TST-356 proof obligation |
|-----------|---------------|--------------------------|
| **SEC-01 — strategic sub/unsub yields no positive EV** | roll `DegenerusAffiliate.sol:558-567` / buyer-never-wins `:579`; taper `:787-795`; double-settle gate `lastSettledDay` (in-slot accumulator) | a churn loop (subscribe→accrue→unsub-flush→re-subscribe) cannot beat a steady sub: total BURNIE credited via churn ≤ steady; the player-flush uses the deterministic 75/20/5 split at locked params (mutator pays settle gas → churn self-limits) |
| **SEC-01 — no settle-timing edge** | `currentDayIndex()` pure-of-`block.timestamp` (`GameTimeLib.sol:21-34`); buyer-never-wins `:579` | flush at day N vs N+1 yields identical buyer EV (zero — the buyer never receives the roll); the scheduled-flush roll seeds on the window-boundary day, not the live call day |
| **SEC-01 — no double-settle** | `lastSettledDay` (in-slot, global ~10-day epoch); player-flush window reset | a second scheduled flush in the same window is a no-op; a player-flush resets the window |
| **SEC-01 — no pre-credit-EV inflation** | confirmed streak read from `state.streak`, advanced only at settle for delivered days; `awardQuestStreakBonus` `onlyGame` (`DegenerusQuests.sol:365-384`) | the +10-at-subscribe is provisional (accumulator only); `state.streak` advances only as days deliver; no player path adds to `state.streak` ahead of delivery |
| **SEC-01 — no double-credit (O1)** | drop `DegenerusQuests.sol:890`; settle credits the lootbox reward once | a completed lootbox quest credits exactly once on BOTH the manual + the afking-settle paths |
| **SEC-02 — SOLVENCY-01 untouched** | ETH/pool debit `GameAfkingModule.sol:709-710` (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`); affiliate/quest are BURNIE `creditFlip` only (`:831` today, settle-batched in v56) | **delta-audit:** the ETH/`claimablePool` debit is **BYTE-UNCHANGED** vs `453f8073`; affiliate/quest never touch the ETH path (a BURNIE-emission-**timing** change only — not an ETH-cut change) |
| **SEC-02 — RNG-freeze intact** | open seed frozen at the stamp day (`resolveAfkingBox`, `DegenerusGameLootboxModule.sol:889`/`:904`-`:905`); the accrue/settle touch no `rngWordByDay` / frozen-window slot | the **accumulator slot is disjoint from RNG-window state**; the open still uses the frozen stamp-day word + day (the in-slot accumulator fields do not overlap the open's seed-source) |
| **QST-04 — quest-core non-perturbation** | `onlyGame` settle entrypoint touches only `questPlayerState` / `questStreakShieldCount`, slot-0 only | the manual/bingo/degenerette/boon callers produce **byte-identical** `PlayerQuestState` with the entrypoint present vs absent (OWNED at IMPL 354, PROVEN at TST 356) |
| **OPEN-02 — two-path open coexistence** | disjoint materialization storage; shared EV-cap exactly-once (`[player][currentLevel]`, `DegenerusGameLootboxModule.sol:902`) | a human + an afking open at the same level share the one EV-cap budget, no double-draw, no shared-state corruption |

**SOLVENCY-01 assertion (LOCKED):** v56 is a **BURNIE-emission-timing + gas change only**. The ETH/`claimablePool` debit (`GameAfkingModule.sol:709-710`) stays **byte-unchanged**; affiliate + quest credits are BURNIE `creditFlip` only, OFF the solvency path (the 349.2 invariant), so SOLVENCY-01 is **not in v56 scope** beyond proving the debit byte-unchanged at TST 356 (SEC-02 delta-audit).

**RNG-freeze assertion (LOCKED):** the in-slot accumulator (`affiliateBase`/`lastSettledDay`/`questProgress`) is **disjoint** from the RNG-window state; the afking open keeps the **frozen stamp-day seed + word** (`rngWordByDay[lastAutoBoughtDay]`, day-frozen at the stamp). The accrue/settle never read or write `rngWordByDay` or any frozen-window slot.

**Block-on-HIGH (design gate):** no HIGH design hole remains open at lock. T-353-01/02/03/04/06 (the STRIDE register) are all mitigated by named design assertions above; T-353-05 (open-timing) is re-verified post-refactor at TST 356 (OPEN-02). The block-on-HIGH gate for this paper-only phase is the DESIGN gate — every unmanipulability/solvency/freeze hole is closed on paper with a named anchor + a TST-356 proof obligation.

---

> **The five sections below are DESIGN FEEDS for the requirements built/proven downstream.** They are flagged **owned at IMPL 354 — design fixed here**. The requirement IDs AGG-01..05 / TKT-01/02 / QST-01..05 / OPEN-01/02 are **NOT** in this plan's `requirements` (which is AFF-01/AFF-02 only) — the design is locked here, the code is owned at 354, the proofs at 356.

## AGG — Mode-Agnostic Aggregator (design feed) (LOCKED — owned at IMPL 354)

**Shape:** accrue-cheap-per-buy → settle-once. The per-buy path does ONE warm SSTORE into the re-packed Sub accumulator slot (`affiliateBase` += tapered whole-BURNIE base; `questProgress`/delivered-day markers advanced; `lastSettledDay` window epoch checked) and NOTHING cross-contract. The cross-contract storm defers to a uniform **settle** leg.

- **Scheduled ~10-day flush ("settlement-due"):** a `mintBurnie`-driven settle leg fires when the global ~10-day epoch elapses (`currentDay - lastSettledDay >= 10`). It runs the deferred affiliate distribution (AFF-01: the winner-takes-all roll seeded by the **fixed window-boundary day**) + the deferred quest credit + the one batched leaderboard write (AFF-02 option A), then advances `lastSettledDay`.
- **Player-triggered-mutation flush BEFORE applying the change:** any sub/unsub/param-change first flushes the pending window via the **deterministic 75/20/5 split (NO roll)** at the locked params, THEN applies the mutation. The mutator pays the settle gas → churn self-limits (SEC-01).
- **Uniform mode-agnostic settle:** the SAME settle path handles BOTH ticket-mode and lootbox-mode accruals (the accumulator is mode-agnostic — it holds whole-BURNIE affiliate base + quest progress regardless of how the per-buy stamp was written).
- **Double-settle gates (AGG-05):** `lastSettledDay` (in-slot) gates a second scheduled flush in the same window to a no-op; the player-flush resets the window. This mirrors the existing `lastAutoBoughtDay` / `lastOpenedDay` monotone-idempotency-marker shape (the established template).

**Gas substrate (grounded in `353-AFKING-READS-WRITES.md`):** the irreducible per-buy accesses that MUST stay on the hot path are — **R1** `_subscribers[cursor]→player` (`:551`), **R2** `_subOf[player]` (one warm slot, `:552`), **R3** `_goRead(swept)` (`:461`), **R5** `afkingFunding[player]` (`:464`); the **W1/W2 solvency debit** `afkingFunding[src] -= ethValue` (`:709`) + `claimablePool -= uint128(ethValue)` (`:710`) [💰 byte-unchanged]; the **W3/W4 stamp** `scorePlus1`+`amount` (lootbox `:793-794`) or the minimal ticket-queue write; **+ ONE accrue SSTORE** into the re-packed Sub slot. The **deferrable cross-contract storm** that v56 moves to the settle is: `quests.handlePurchase` (`:760`) + `affiliate.payAffiliate` ×2 (`:806`/`:816`) + per-buy `coinflip.creditFlip` (`:831`) → all collapse into the once-per-window settle. **The OPEN path is already lean** (per `353-AFKING-READS-WRITES.md` §2: no cold ledger, one marker write + the EV-cap RMW that *is* the box + one cursor write + one bounty) — OPEN is a **re-verification target, not an optimization target**; all v56 everyday-gas savings live on the **buy** side. Cross-reference: the accumulator slot is the re-packed in-slot layout locked in `## Accumulator Layout`.

## TKT — Ticket-Mode Minimal-Write Primitive (design feed) (LOCKED — owned at IMPL 354)

**Replace** the per-day `purchaseWith` heavyweight delegatecall (`contracts/modules/GameAfkingModule.sol:713-731`, ~262k) with a custom `_queueTicketsScaled`-equivalent **minimal-write primitive** that mirrors the lootbox box-stamp: a resolution-equivalent placement/trait/quantity write, with affiliate + quest **deferred to the aggregator settle** (no per-buy `payAffiliate`/`handlePurchase`/`creditFlip`).

**Century/x00 parity — KEEP (D-10, flipped 2026-06-01):** afking-ticket buyers **GET** the century bonus at **parity** with manual ticket buyers. The primitive replicates the `targetLevel % 100 == 0` quantity bonus (`contracts/modules/DegenerusGameMintModule.sol:1243-1259`) **before queuing**, REUSING the existing `centuryBonusLevel` (uint24, `DegenerusGameStorage.sol:1563`) + `centuryBonusUsed` (mapping, `:1567`) storage — **NO new slot** — and reusing the per-buy activity score already computed for the AFF-02 affiliate taper (so **no extra `_playerActivityScore` call**).

**Gas analysis (why KEEP is amortized-free):** the bonus is gated by the every-100th-level check (`targetLevel % 100 == 0`) → it fires only on the rare century-level buy; the only real cost (~7–31k, the `centuryBonusUsed[buyer]` zero→nonzero write) lands on that rare buy and amortizes to negligible. The SPEC documents this is **parity-by-choice** — the original "drop for simplicity" (D-10 first pass) was about primitive-simplicity, NOT gas; with the cost shown trivial, parity is the fairer choice.

## QST — Shared DegenerusQuests Core (design feed) (LOCKED — owned at IMPL 354)

**Batched-settle entrypoint shape:** a NEW `onlyGame`-gated entrypoint (`onlyGame` admits GAME only — `DegenerusQuests.sol:321-324`) invoked from the GAME-context settle leg. It touches **`questPlayerState[player]` (slot-0)** + **`questStreakShieldCount[player]`** only, mirrors `awardQuestStreakBonus` (`:365-384`) semantics for the streak, **MUST call `_questSyncState` first** (like `awardQuestStreakBonus:369`, so it respects the same day-reset / anchor logic, `_questSyncState` `:1285-1318`), and **MUST NOT touch slot-1** (`progress[1]`, `lastProgressDay[1]`, `lastQuestVersion[1]` — the player's manual quest, QST-01).

**Non-perturbation approach (QST-04, RESEARCH §4.2 — OWNED at IMPL, PROVEN at TST 356):** the manual/bingo/degenerette/boon callers produce **byte-identical `PlayerQuestState`** with the entrypoint present vs absent, for any interleaving. The entrypoint adds writes only to `streak`/`lastActiveDay`/`lastCompletedDay`/`lastSyncDay` — the SAME fields `awardQuestStreakBonus` + `_questSyncState` already write — so the proof reduces to: the entrypoint's writes are commutative-or-ordered-identically with the existing handlers' for the afk-covered days (the `lastSyncDay`/`completionMask` reset logic `:1312-1317` already serializes by day; the entrypoint's mandatory `_questSyncState`-first respects the same day-reset).

**±10-streak / confirmed-vs-provisional derivation (QST-02/QST-03, RESEARCH §4.3):**
- **+10-at-subscribe is PROVISIONAL** — applied only to the accumulator counter (the in-slot `questProgress`), NEVER directly to `state.streak`. (No injectable player add-lever: `awardQuestStreakBonus` is `onlyGame` — there is no player-callable path that adds to `state.streak` ahead of delivery → no pre-credit-EV inflation, QST-02.)
- **`state.streak` advances ONLY at settle** for **delivered days** `(afkCoveredThroughDay, settleDay]`, with `afkCoveredThroughDay` **monotone-advanced** in the same write (debit-gated: each day credited exactly once; the marker is monotone like `lastOpenedDay`/`lastAutoBoughtDay`).
- **Double-credit guard (QST-03):** the `lastCompletedDay` / `afkCoveredThroughDay` guard gates **`state.streak` advancement** — NEVER the slot-0 reward accrual. A manual completion on an afk-covered day must not double-credit the streak (credit the streak once per day, whichever path reaches it first); slot rewards are never suppressed.
- **Active-pass anti-reset (QST-03):** suppress `_questSyncState`'s gap-reset (`:1306`, which zeroes `state.streak` when `currentDay > anchorDay + 1` unless `questStreakShieldCount` covers the gap) **without a daily write** — via the marker-update approach: on settle, advance `lastActiveDay`/`lastCompletedDay` to the last afk-covered delivered day so `anchorDay` stays current (no shield-balance accounting).

## QST-05 O1 Fix + Dead-Code Removal (design feed) (LOCKED — owned at IMPL 354)

**O1 fix (D-01/D-03):** **DROP** the internal `coinflip.creditFlip(player, lootboxReward)` at `contracts/DegenerusQuests.sol:890` (inside the `if (lootboxReward != 0)` at `:889`); **KEEP** `lootboxReward` in the return `totalReturned = ethMintReward + lootboxReward` at `:893` so the caller's single batched `creditFlip` pays it **exactly once**. KEEP the burnie credit at `:887` (always internal-only, correct). **Non-perturbing to the MintModule caller:** it already re-credits the return (`lootboxFlipCredit += questReward` `:1232` → batched `coinflip.creditFlip(buyer, lootboxFlipCredit)` `:1366-1367`); dropping `:890` removes the duplicate, leaving the lootbox reward credited once via `:1367` (the eth-mint leg was always return-only; the burnie-mint leg `:887` was always internal-only).

**The KEY v56 nuance (RESEARCH §5.3):** under the aggregator, the afking per-buy `handlePurchase` call (`GameAfkingModule.sol:760`) **DISAPPEARS** (deferred to settle) → the afking per-buy path no longer calls `handlePurchase` at all. So the O1 fix is **two halves**: (a) drop `:890` at the source (fixes the manual `purchaseWith` path's double-credit); AND (b) the v56 afking **SETTLE** must route the deferred lootbox-quest reward through **exactly ONE `creditFlip`** (the settle's single batched credit, never an internal one) — inheriting the post-fix invariant. TST 356 + TERMINAL 357 verify the afking settle credits once.

**Dead-code removal (D-05):** remove `handleLootBox` (`contracts/DegenerusQuests.sol:698-741`; its internal `creditFlip` `:739` is unreachable) + the interface entry (`contracts/interfaces/IDegenerusQuests.sol:107`) + the access-control tests. **Zero production callers** (RESEARCH §5.2 grep: only comment refs at `:746` / `IDegenerusQuests:126`; test refs in `test/fuzz/CoverageGap222.t.sol` + `test/unit/DegenerusQuests.test.js`). Pre-launch redeploy-fresh accepts the interface break; removing it drops bytecode + a latent double-credit footgun while we are already in the shared core.

## OPEN — Afking Open-End Re-Verification (design feed) (LOCKED — owned at IMPL 354)

**OPEN-01 (cheapest viable shared materialization):** the afking open path (`_openAfkingBox` `GameAfkingModule.sol:888-910` → `resolveAfkingBox` `DegenerusGameLootboxModule.sol:877-...`, driven by `mintBurnie` `:985` / `_autoOpen` `:938-966` / `OPEN_BATCH` `:191`) already shares `_resolveLootboxCommon` with the human `openLootBox` path — that **IS** the cheapest viable shared materialization (one resolve function; only the seed-source + day-freeze differ). v56 must **NOT** touch the open's freeze/parity guarantees (per `353-AFKING-READS-WRITES.md` §2: the OPEN path is already lean — no fat to cut).

**OPEN-02 (re-verify AFTER the accrual/settle refactor):**
- **Live-level parity:** `resolveAfkingBox` rolls `currentLevel = level + 1` LIVE (`DegenerusGameLootboxModule.sol:894`), exactly like `resolveLootboxDirect` — parity with the human box.
- **Frozen stamp-day seed + word:** the box word is the caller-passed `rngWordByDay[lastAutoBoughtDay]` (the FROZEN stamp-day word, `:905`) and the seed `day` is the FROZEN stamp day (`:904`/`:889`), NOT the live day — the freeze prevents seed-grinding by open-timing.
- **No double-open:** `lastOpenedDay` advances BEFORE the resolve (`_openAfkingBox:892`, effects-first); `_afkingBoxReady` gates on `lastOpenedDay < lastAutoBoughtDay` (`:918-922`); `lastOpenedDay` is monotone → a re-walked open is a no-op.
- **EV-cap exactly-once:** the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, ...)` RMW (`:902`), keyed `[player][currentLevel]` (`currentLevel = level + 1`) on the SAME `lootboxEvBenefitUsedByLevel` map the human path uses; the afking buy-time EV write is bypassed → the open is the single draw, no double-draw.
- **No shared-state hazard:** the in-slot accumulator fields (`affiliateBase`/`lastSettledDay`/`questProgress`) are **disjoint** from the open's `lastOpenedDay`/`lastAutoBoughtDay` markers within the shared Sub slot (different fields, different write paths) → no collision. The human + afking routes share only the intended per-`(player,level)` EV-cap budget.

---

## XMODEL-01 Cross-Model Design-Input (PENDING — Plan 02)

> **PLACEHOLDER — filled by Plan 02 (the XMODEL cross-model design-input pass).** This section will hold the per-concern bespoke prompts fed to BOTH `codex` + `gemini` (D-11) and the disposition table folded into the design-lock BEFORE IMPL 354. XMODEL-01 is OWNED by Phase 353 (this SPEC is its home); the TERMINAL close-augmentation half is reflected in AUDIT-01 at Phase 357.

The FIVE concerns (C1–C5) Plan 02 runs (RESEARCH §7.3):

| # | Concern | Prompt focus |
|---|---------|--------------|
| C1 | Strategic sub/unsub edge | Can a player extract more value than a steady subscriber by subscribe→accrue→unsub-flush (deterministic 75/20/5 at locked params)→re-subscribe? (roll buyer-never-wins `:579`; per-buy immutable taper; double-settle gated by `lastSettledDay`.) Find any positive-EV churn vector. |
| C2 | Settle-timing / roll-seed | Can a player select a favorable roll seed by timing the flush? The scheduled flush rolls `keccak256(TAG, windowBoundaryDay, sender, code) % 20`; the player-flush is a deterministic split (no roll); the buyer never receives the roll. |
| C3 | Ticket-mode primitive parity | Does KEEPING the century bonus at parity (reusing `centuryBonusLevel`/`centuryBonusUsed` + the per-buy score) while deferring affiliate/quest to the settle create any exploit or resolution mismatch vs the manual ticket leg? |
| C4 | Open-end unmanipulability | After moving affiliate/quest to a deferred settle, is the open still unmanipulable (no double-open, no EV double-draw, no level/seed timing edge)? (live level, frozen stamp-day seed+word, shared per-(player,level) EV-cap, `lastOpenedDay` monotone.) |
| C5 | Long-run gas | Suggest gas optimizations for the per-buy accrue (one warm SSTORE into the re-packed Sub slot — whole-BURNIE affiliate base + 100M clamp + milli-ETH amount + narrowed day/level fields, NO new cold slot), the ~10-day settle leg, and the `OPEN_BATCH` open walk — without weakening any unmanipulability invariant. |

**Disposition table (Plan 02 produces, folds BEFORE IMPL 354):**

| Concern | Codex verdict | Gemini verdict | Disposition (FOLD / REJECT-with-reason / NEEDS-DESIGN-CHANGE) |
|---------|---------------|----------------|----------------------------------------------------------------|
| C1 | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ |
| C2 | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ |
| C3 | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ |
| C4 | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ |
| C5 | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ | _(PENDING — Plan 02)_ |

---

## SPEC Lock (PENDING — flipped by Plan 02 after the XMODEL fold-in)

> **PLACEHOLDER — flipped by Plan 02.** The SPEC is DRAFT until Plan 02 runs the XMODEL cross-model design-input pass, folds the C1–C5 disposition table above, applies any NEEDS-DESIGN-CHANGE adjustments to the locked sections, and then flips this status to **LOCKED** with the lock attestation (date, the disposition summary, the confirmation that no XMODEL concern reopened a HIGH design hole, and the re-confirmation that `git diff --quiet 453f8073 HEAD -- contracts/` is still clean — paper-only). Until then: **STATUS = DRAFT.**
