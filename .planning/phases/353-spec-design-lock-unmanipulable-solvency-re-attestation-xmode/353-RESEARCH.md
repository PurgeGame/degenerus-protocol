# Phase 353: SPEC — Design-Lock + Unmanipulable/Solvency Re-Attestation + XMODEL Design-Input + Call-Graph Attestation - Research

**Researched:** 2026-06-01
**Domain:** Solidity smart-contract design-lock (afking aggregator + affiliate/quest batching + cross-model design-input); paper-only SPEC, ZERO `contracts/*.sol` mutation
**Confidence:** HIGH (every anchor grep-verified against the frozen subject; both XMODEL CLIs smoke-tested live)

**Frozen subject guard:** Working-tree `contracts/` is **byte-identical** to the frozen subject `453f8073` — `git diff --quiet 453f8073 HEAD -- contracts/` returns clean (HEAD `51f47da6` is `453f8073` + docs-only commits, and `453f8073` is an ancestor). Therefore every `file:line` below was read from the live working tree and **equals the frozen subject** — no `git show 453f8073:<path>` indirection was needed. [VERIFIED: git diff]

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (D-01 .. D-11)
- **D-01/D-02/D-03/D-04 (O1 / QST-05):** O1 is a genuine isolated double-credit (a single LOOTBOX-quest reward credited twice: internally at `DegenerusQuests.sol:890` AND via the return re-credited by the caller at `DegenerusGameMintModule.sol:1232`→`:1367`). **Fix mechanic (USER-chosen):** DROP the internal `creditFlip` at `DegenerusQuests.sol:890`; keep `lootboxReward` in the return so the caller's single batched `creditFlip` pays once. The pattern is ISOLATED — all 7 handlers + every caller audited clean. NOT the "two different quests each pay" case (that is correct).
- **D-05 (dead code):** `handleLootBox` (`DegenerusQuests.sol:698-741`) has no production caller — REMOVE the function + the interface entry (`IDegenerusQuests.sol:107`) + the access-control tests. Pre-launch redeploy-fresh makes the interface break fine.
- **D-06 (leaderboard KEPT):** the affiliate leaderboard is NOT deletable — it pays 1%-top-affiliate (`_rewardTopAffiliate`, `DegenerusGameAdvanceModule.sol:700`) + 5%-score-proportional (`claimAffiliateDgnrs`, `DegenerusGameBingoModule.sol:216`) DGNRS.
- **D-07 (option A):** the afking affiliate slice DOES feed the leaderboard, via option A — at settle, ONE batched leaderboard write lumped into the settle-level; accept the minor cross-level ranking lag; NO force-flush before the level-transition snapshot.
- **D-08 (gas):** `_updateTopAffiliate` (`DegenerusAffiliate.sol:776-783`) is read-once-compare → keeping the leaderboard is cheap.
- **D-09 (AFF-01/AFF-02, locked):** scheduled ~10-day flush KEEPS the winner-takes-all daily-seeded roll (fixed window-boundary day, NOT player-chosen); deterministic 75/20/5 split ONLY on the player-triggered-alteration path; roll is EV-neutral + intra-upline-redistributive + buyer-never-wins (`winner != sender`, `:579`); taper applied per-buy at accrue (`_applyLootboxTaper`, `:787`, taper-only-reduces).
- **D-10 (TKT-02): SUPERSEDED 2026-06-01 → KEEP at parity** (was: drop for simplicity). A gas analysis showed the afking-ticket century/x00 quantity-bonus (`DegenerusGameMintModule.sol:1243-1259`) is amortized-negligible — gated by the every-100th-level check, reuses the existing `centuryBonusLevel`/`centuryBonusUsed` storage (`DegenerusGameStorage.sol:1563`/`:1567`) + the per-buy activity score already computed for the affiliate taper. So afking-ticket buyers GET the century bonus at parity with manual buyers (the primitive applies it before queuing). See CONTEXT D-10.
- **D-11 (XMODEL-01):** run focused per-concern bespoke prompts fed to BOTH `codex` + `gemini` (NOT the v52 `coordinator.sh` harness). Concerns: strategic sub/unsub edge, settle-timing/roll-seed non-exploitability, ticket-mode primitive parity, open-end unmanipulability, long-run gas. Fold each model's findings into the design-lock via a disposition table BEFORE IMPL.

### Claude's Discretion (technical, resolved by researcher/planner)
- The per-sub accumulator storage layout (GAS-02 feed): spare-bits vs new cold slot; field widths. **See §3 — the "176/256" premise is DRIFTED; the slot is at 232/256.**
- The precise ±10-streak / confirmed-vs-provisional derivation (immutable debit-gated delivered-day markers; the `lastCompletedDay`/`afkCoveredThroughDay` double-credit guard; active-pass anti-reset). **See §4.**

### Deferred Ideas (research items resolved here, NOT new scope)
- Whether the afking path still calls `handlePurchase` per-buy under the v56 aggregator → **ANSWERED in §5: today it DOES (`:760`); the v56 aggregator REMOVES it from the per-buy path.**
- The accumulator field-width packing + the exact ±10 marker derivation → §3 + §4.
- No scope creep surfaced.
</user_constraints>

<phase_requirements>
## Phase Requirements (OWNED by 353)

| ID | Description | Research Support |
|----|-------------|------------------|
| AFF-01 | Scheduled flush keeps the winner-takes-all daily-seeded roll (fixed window-boundary day); deterministic 75/20/5 split only on player-triggered alteration | §2 — roll seed `keccak256(TAG, currentDayIndex(), sender, code) % 20` (`DegenerusAffiliate.sol:558-567`); `currentDayIndex()` is a pure fn of `block.timestamp` (un-choosable within a tx); buyer-never-wins (`:579`); both attested |
| AFF-02 | Taper applied per-buy at accrue (immutable); leaderboard credit lumps into settle-level (option A); force-flush-before-jackpot path designed if ranking needs exactness | §2 — `_applyLootboxTaper` (`:787`) taper-only-reduces; leaderboard write set `:510`/`:511`/`:521`; option-A cross-level-lag root at `DegenerusGameAdvanceModule.sol:695-696`; force-flush UNNEEDED (snapshot uses `affiliateScore`/`totalAffiliateScore`, not the live `affiliateTop`) — see §2.4 |
| XMODEL-01 | Cross-model (Codex + Gemini) design-input pass via bespoke focused prompts; fold findings into design-lock before IMPL | §7 — both CLIs smoke-tested live; ready-to-use invocation templates + per-concern prompt skeletons |
</phase_requirements>

## Summary

Phase 353 is a paper-only design-lock. The v56 mechanism is USER-converged; this research's job is to ATTEST every cited anchor against the frozen subject `453f8073`, surface the drift the SPEC author must reconcile, and answer the deferred research questions. **All cited anchors exist and resolve correctly**, with three substantive reconciliations the SPEC must record:

1. **Accumulator-layout premise is DRIFTED.** CONTEXT/PLAN assume the `Sub` slot "4-field stamp uses 176/256 → ~80 spare bits." The actual `Sub` struct (`DegenerusGameStorage.sol:1867-1899`) packs **232 of 256 bits** (config 56b + stamp 112b + markers 64b), leaving only **24 spare bits** in the slot. The affiliate base + `windowStartDay` + quest progress + `lastSettledDay` will **NOT** fit in 24 bits → a new cold slot (or a re-pack) is effectively unavoidable. This is the single most important fact for the SPEC's accumulator-layout decision (§3). Pre-launch redeploy-fresh makes a second slot low-stakes.

2. **The afking-handlePurchase-per-buy answer (deferred from discuss):** today the afking LOOTBOX path **DOES** call `quests.handlePurchase` per-buy at `GameAfkingModule.sol:760`, plus BOTH `affiliate.payAffiliate` calls (`:806`/`:816`) and a per-buy `creditFlip` (`:831`) — this IS the "per-buy cross-contract storm." Under the v56 aggregator these calls are **removed from the per-buy path** (deferred to the settle). Therefore the O1 fix's coverage of the afking caller becomes moot for the per-buy path — but the SPEC must lock that the **settle** path (which now performs the deferred quest credit) routes the lootbox reward through exactly ONE `creditFlip`, inheriting the same invariant (§5).

3. **Bare-name anchor reconciliations:** ROADMAP's `MintModule:1243` = `contracts/modules/DegenerusGameMintModule.sol:1243`; `GameAfkingModule.sol:760-831` = `contracts/modules/GameAfkingModule.sol`; the per-buy storm is actually `:708-833` (the cited `:760-831` is the inner storm); the EV-cap `[player][level+1]` = `lootboxEvBenefitUsedByLevel[player][currentLevel]` where `currentLevel = level + 1` (`DegenerusGameLootboxModule.sol:902`/`:894`).

**Primary recommendation:** Lock the design as USER-converged, but record (a) the accumulator goes in a NEW packed slot (not the `Sub` spare bits) with the field widths in §3; (b) the O1 fix + the afking-per-buy-storm removal are the SAME change for the afking path (the storm goes away; the settle inherits the one-creditFlip invariant); (c) the force-flush-before-jackpot path is NOT needed (the DGNRS claim reads `affiliateScore`/`totalAffiliateScore`, not the live `affiliateTop` ranking, so option-A's lag does not corrupt the proportional claim); (d) run XMODEL via the §7 templates.

---

## 1. Anchor Attestation Table (vs frozen subject `453f8073`)

| # | Anchor (as cited) | Verified location | Status |
|---|-------------------|-------------------|--------|
| A1 | afking per-buy cross-contract storm `GameAfkingModule.sol:760-831` | `contracts/modules/GameAfkingModule.sol` — the **storm spans `:708-833`**; `handlePurchase` call `:760`, affiliate calls `:806`+`:816`, per-buy `creditFlip` `:831` | OK (storm range is `:708-833`; cited `:760-831` is the inner span — SPEC should widen the citation) |
| A2 | lootbox stamp branch `:735-749` | `GameAfkingModule.sol:735-833` (the `else` lootbox-stamp branch; the comment header is `:735-746`, the stamp body runs to `:833`) | OK (`:735` is the branch open; the stamp work extends to `:833`) |
| A3 | ticket-mode `purchaseWith` route `:713-731` | `GameAfkingModule.sol:713-731` (the `if (isTicket)` delegatecall to `IDegenerusGameMintModule.purchaseWith`) | EXACT |
| A4 | affiliate daily-seeded roll `DegenerusAffiliate.sol:558` | `DegenerusAffiliate.sol:558-567` — `keccak256(abi.encodePacked(AFFILIATE_ROLL_TAG, GameTimeLib.currentDayIndex(), sender, storedCode)) % 20` | EXACT |
| A5 | buyer-never-wins `:579` | `DegenerusAffiliate.sol:579` — `if (winner != sender) { ... _routeAffiliateReward(...) }` (when buyer would win → reward + quest credit **skipped entirely**) | EXACT |
| A6 | leaderboard writes `:510`/`:511`/`:521` | `DegenerusAffiliate.sol:510` (`earned[affiliateAddr] = newTotal`), `:511` (`_totalAffiliateScore[lvl] += scaledAmount`), `:521` (`_updateTopAffiliate(...)`) | EXACT |
| A7 | `_updateTopAffiliate:776` (read-once-compare) | `DegenerusAffiliate.sol:776-783` — 1 SLOAD (`:778`) + conditional SSTORE (`:780`) only when `score > current.score` | EXACT (D-08 confirmed) |
| A8 | taper `:504`/`:787` (`_applyLootboxTaper`) | call site `:504-506`; impl `_applyLootboxTaper` `:787-795`; monotone-down (returns `amt * factor`, factor ≤ `BPS_DENOMINATOR`) | EXACT (taper-only-reduces confirmed) |
| A9 | 1%-top consumer `DegenerusGameAdvanceModule.sol:700` (`_rewardTopAffiliate`) | `_rewardTopAffiliate(uint24 lvl)` at `:700-...`, reads `affiliate.affiliateTop(lvl)` (`:701`); invoked on transition at `:1727` | EXACT |
| A10 | 5%-proportional consumer `DegenerusGameBingoModule.sol:217` (`claimAffiliateDgnrs`) | `claimAffiliateDgnrs(address player)` at **`:216`** (1-line drift), reads `affiliate.affiliateScore` (`:224`) + `affiliate.totalAffiliateScore` (`:228`); `reward = allocation * score / denominator` (`:233`) | OK (`:216`, not `:217`) |
| A11 | `DegenerusQuests.sol` `handlePurchase` `:763-898`; O1 at `:887`/`:890`/`:893` | `handlePurchase` `:763-898`; burnie credit (keep) `:887`; **lootbox credit (DROP) `:889-891`** (the `if` is `:889`, the `creditFlip` is `:890`); `totalReturned` `:893` | EXACT |
| A12 | `awardQuestStreakBonus:365` | `DegenerusQuests.sol:365-384` (`onlyGame`; adds streak days; clamps uint24; `:372`) | EXACT |
| A13 | afking open path `_openAfkingBox`→`resolveAfkingBox` + `mintBurnie`/`autoOpen`/`OPEN_BATCH` | `GameAfkingModule.sol`: `_openAfkingBox` `:888-910`, `_afkingBoxReady` `:918-922`, `_autoOpen` `:938-966`, `mintBurnie` `:985-...`, `OPEN_BATCH` const `:191` (=200), `SUBSCRIBER_CAP` `:164` (=500); `resolveAfkingBox` in `DegenerusGameLootboxModule.sol:877-...` | EXACT |
| A14 | `Sub` 4-field stamp + `lastOpenedDay` in `DegenerusGameStorage.sol` | `struct Sub` `:1867-1899`; fields: `dailyQuantity`(8)+`validThroughLevel`(32)+`reinvestPct`(8)+`flags`(8)+`scorePlus1`(16)+`amount`(96)+`lastAutoBoughtDay`(32)+`lastOpenedDay`(32) = **232 bits**; `mapping(address=>Sub) _subOf` `:1902` | OK but **DRIFT vs "176/256" premise** — see §3 |
| A15 | EV-cap `lootboxEvBenefitUsedByLevel[player][level+1]` | `DegenerusGameLootboxModule.sol` — `_applyEvMultiplierWithCap` `:459-495` (RMW at `:473`/`:488`); afking call `:902` with `currentLevel = level + 1` (`:894`); shared with human `openLootBox` `:503` / `resolveLootboxDirect` `:763` | EXACT (key is `[player][currentLevel]`, `currentLevel == level+1`) |
| A16 | STAGE placement in `DegenerusGameAdvanceModule.sol` | `SUB_STAGE_BATCH` const `:149` (=50); STAGE driver delegatecall to `processSubscriberStage` `:743-761`; drain gate `subsFullyProcessed` `:307`/`:310`/`:325`; `processSubscriberStage` defined `GameAfkingModule.sol:539` | EXACT |
| A17 | `MintModule:1243` century bonus (ROADMAP bare name) | `contracts/modules/DegenerusGameMintModule.sol:1243` — `if (ticketCost != 0 && targetLevel % 100 == 0 && cachedScore != 0)` (ticket-mode only) | EXACT (bare-name reconciled) |
| A18 | MintModule O1 re-credit (`:1222-1232`, `:1366-1367`) | `DegenerusGameMintModule.sol:1222` (`handlePurchase` call), `:1232` (`lootboxFlipCredit += questReward`), `:1366-1367` (batched `creditFlip`) | EXACT |
| A19 | `handleLootBox` dead `:698-742` + interface `:107` | `DegenerusQuests.sol:698-741` (the fn); internal `creditFlip` `:739`; interface decl `IDegenerusQuests.sol:107`; **NO production caller** (grep: only comment refs at `:746`/`IDegenerusQuests:126`); test refs `test/fuzz/CoverageGap222.t.sol` + `test/unit/DegenerusQuests.test.js` | EXACT (D-05 confirmed) |
| A20 | clean handlers — `handleMint` guard `:513`, `handleFlip` `:533`, `handleDecimator` credit `:629`, `handleAffiliate` `:644`, `handleDegenerette` credit `:954` | `handleMint` guard `:513` (`if (!paidWithEth && totalReward != 0)`); `handleFlip` `:533`; `handleDecimator` `:589`, internal credit `:629`; `handleAffiliate` `:644`; `handleDegenerette` `:913`, internal credit `:954` | EXACT (D-04 confirmed) |
| A21 | external clean callers — `BurnieCoin:613` (decimator weight-boost), `BurnieCoinflip:275` (flip), `DegeneretteModule:467` (return ignored) | `BurnieCoin.sol:613` (`handleDecimator`); `BurnieCoinflip.sol:275` (`handleFlip`); `DegenerusGameDegeneretteModule.sol:467` (`handleDegenerette`, return ignored) | EXACT |

**Net drift to record in the SPEC:** (1) the storm range is `:708-833` not `:760-831`; (2) `claimAffiliateDgnrs` is `:216` not `:217`; (3) `handleLootBox` is `:698-741` not `:698-742`; (4) the O1-drop `creditFlip` is line `:890` inside the `if` at `:889`; (5) the accumulator-layout premise (§3); (6) the EV-cap key is `[player][currentLevel]` where `currentLevel = level + 1`. Everything else is exact.

---

## 2. AFF-01 / AFF-02 Design Facts

### 2.1 The roll IS non-gameable by settle-timing (AFF-01) [VERIFIED: source read]

`DegenerusAffiliate.payAffiliate` (`:380-588`), the winner-takes-all branch (`:556-582`):

```solidity
// DegenerusAffiliate.sol:558-567
uint256 roll = uint256(keccak256(abi.encodePacked(
    AFFILIATE_ROLL_TAG,
    GameTimeLib.currentDayIndex(),   // ← the ONLY entropy beyond sender+code
    sender,
    storedCode
))) % 20;
// :569-576  0-14 = affiliate (75%), 15-18 = upline1 (20%), 19 = upline2 (5%)
// :579      if (winner != sender) { (uint256 questReward,,,) = quests.handleAffiliate(winner, ...); _routeAffiliateReward(winner, base + questReward); }
```

Three load-bearing facts, all attested:
- **The seed's only mutable input is `currentDayIndex()`**, a pure fn of `block.timestamp` (`GameTimeLib.sol:21-23` → `currentDayIndexAt`, `:31-34`). A player cannot select a day index within a transaction; it advances once per ~24h at the 22:57-UTC boundary. So "choosing a favorable roll" requires waiting a full wall-clock day, over which the roll is EV-neutral anyway.
- **The buyer can never receive the roll** — `if (winner != sender)` (`:579`); when the roll would pay the buyer, the entire reward (including the quest credit) is **skipped**, not redirected. So `sender` (the afking subscriber / their funding wallet) has **zero EV** from the roll outcome regardless of timing.
- **Redistribution is intra-upline-chain only** (`:572-575` — affiliate, then `_referrerAddress` upline1/upline2). Manipulation only moves value among the buyer's own affiliate chain; it never creates or destroys protocol value.

**SPEC design-lock for AFF-01:** the scheduled ~10-day flush re-runs this same roll **seeded by the fixed window-boundary day** (the keeper cannot choose the boundary day — it is `windowStartDay + WINDOW_LEN`, a deterministic function of the sub's own subscribe day). The player-triggered alteration path uses the **deterministic 75/20/5 split (NO roll)** — so a player who flushes early cannot select a seed at all. Both paths are timing-immune by the above. **No "by construction" survives: the SPEC must assert (and TST 356 must prove) that the settle-leg roll uses the window-boundary `currentDayIndex`-equivalent, NOT the live settle-call day.**

### 2.2 The taper is immutable-at-accrue (AFF-02) [VERIFIED: source read]

`_applyLootboxTaper` (`:787-795`): linear taper 100%→25% as score rises from `LOOTBOX_TAPER_START_SCORE` to `LOOTBOX_TAPER_END_SCORE`; it only **reduces** (`return (amt * (BPS_DENOMINATOR - reductionBps)) / BPS_DENOMINATOR`, reductionBps ≥ 0). Applied at `:504-506` BEFORE the leaderboard write. **SPEC lock:** the v56 accrue path applies the taper **per-buy on the activity score read at the box stamp** (the same `activityScore` the stamp computes at `GameAfkingModule.sol:785-789`), storing the **already-tapered base** in the accumulator. Because the taper is monotone-down and applied per-buy, clustering buys into one settle cannot dodge a higher-score taper — each buy is tapered at its own score.

### 2.3 The leaderboard write set option-A must perform (D-07) [VERIFIED: source read]

At settle, the lumped leaderboard write reproduces `payAffiliate`'s `:508-521` for the accumulated base:
1. `earned[affiliateAddr] += accumulatedBase` (`:510` analog) — warm SSTORE.
2. `_totalAffiliateScore[lvl] += accumulatedBase` (`:511` analog) — warm SSTORE.
3. `_updateTopAffiliate(affiliateAddr, newTotal, lvl)` (`:521` analog) — the read-once-compare (`:776-783`): 1 SLOAD + conditional SSTORE.

`lvl` for option A = the **settle-level** (the live `level + 1` at settle time), NOT the buy-time level. This is the source of the accepted cross-level lag (§2.5).

### 2.4 Force-flush-before-jackpot — NOT needed (resolves PLAN "Open SPEC decision #4") [VERIFIED: source read]

The SPEC should record: the 5%-proportional DGNRS claim (`claimAffiliateDgnrs`, `DegenerusGameBingoModule.sol:216-233`) reads `affiliate.affiliateScore(currLevel, player)` (`:224`, = `affiliateCoinEarned[lvl][player]`) and `affiliate.totalAffiliateScore(currLevel)` (`:228`, = `_totalAffiliateScore[lvl]`) — the **cumulative score**, not the live `affiliateTop` ranking. Option A's lag affects WHICH level the afking slice lands in, but the proportional claim is exact for whatever lands at that level (numerator and denominator move together). The only consumer sensitive to ranking is `_rewardTopAffiliate` (`:700`, the 1%-top), which is a single-winner snapshot at transition — the afking slice landing a level late simply competes in the next level's ranking. Since the afking slice is tapered + a minority of the pool, the SPEC can **decline the force-flush path** (option A as-is). Record this as a SPEC decision with the rationale; TST 356 verifies the proportional claim is exact.

### 2.5 Affiliate-score level-routing + the cross-level lag [VERIFIED: source read]

`DegenerusGameAdvanceModule.sol:695-696` (comment in `_rewardTopAffiliate`): *"…scores route to level + 1 during gameplay, so at transition time (when level becomes lvl), all scores at index lvl are frozen — new scores go to lvl + 1."* Confirmed: the per-buy affiliate calls pass `currentLevel + 1` (`GameAfkingModule.sol:810`/`:820`; `DegenerusGameMintModule.sol:1273`). Under option A, a scheduled settle that fires after an L→L+1 transition writes the accumulated base to the **settle-time level**, so buys made during level L that settle during level L+1 land their leaderboard credit at index L+1 (one level late). **This is the accepted lag.** The SPEC must state it explicitly so TST/TERMINAL do not flag it as a finding.

---

## 3. Accumulator Layout Options (GAS-02 design feed) — **PREMISE DRIFTED**

### 3.1 The drift [VERIFIED: source read — `DegenerusGameStorage.sol:1867-1899`]

The `Sub` struct already uses **232 of 256 bits** in its single slot (the doc comment at `:1848-1851` and `:1867-1898` confirm):

| Group | Field | Bits | Running total |
|-------|-------|------|---------------|
| config | `dailyQuantity` uint8 | 8 | 8 |
| config | `validThroughLevel` uint32 | 32 | 40 |
| config | `reinvestPct` uint8 | 8 | 48 |
| config | `flags` uint8 | 8 | 56 |
| stamp | `scorePlus1` uint16 | 16 | 72 |
| stamp | `amount` uint96 | 96 | 168 |
| markers | `lastAutoBoughtDay` uint32 | 32 | 200 |
| markers | `lastOpenedDay` uint32 | 32 | **232** |

**Spare bits in the existing slot: 24** (not ~80). CONTEXT's "the 4-field stamp uses 176/256" is inaccurate — there is no 176-bit "4-field stamp"; the stamp proper is `scorePlus1`(16) + `amount`(96) = 112 bits, but the slot also carries 56 bits of config + 64 bits of markers.

### 3.2 Field widths the accumulator needs

| Field | Purpose | Min width | Rationale |
|-------|---------|-----------|-----------|
| affiliate base (accumulated, tapered, BURNIE-valuation wei) | sum of per-buy tapered affiliate bases over the window | ~96 bits | a single `amount` is uint96; a 10-day sum of affiliate bases (a fraction of spend × 5-25% rate) fits comfortably in 96 (could squeeze to ~80, but no payoff if a new slot is used) |
| `windowStartDay` | scheduled-flush window anchor (idempotency, AGG-05) | 32 bits | day index, same width as `lastAutoBoughtDay` |
| quest progress (slot-0 accumulated delivered-day count or accrued reward) | the deferred quest credit; ±10-streak window count | ~32 bits | delivered-day count over a window ≤ a few; even accrued BURNIE reward (flat 100/day) ≤ ~16 bits over 10 days |
| `lastSettledDay` | double-settle gate (AGG-05) | 32 bits | day index |

Sum ≈ **96 + 32 + 32 + 32 = 192 bits** → **does NOT fit in the 24 spare bits.**

### 3.3 The three viable options (SPEC must choose; recommend Option B)

- **Option A — squeeze into the existing slot.** Infeasible without shrinking existing fields. `validThroughLevel` is uint32 but only needs to span game levels (could be uint24 → +8 bits) and `scorePlus1` could narrow, but you cannot free 192 bits. **REJECT.**
- **Option B (RECOMMENDED) — one NEW packed cold slot per sub.** Append a second 256-bit field to `Sub` (or a parallel `mapping(address => uint256) _subAccrual`) packing `affiliateBase`(96) + `questProgress`(32) + `windowStartDay`(32) + `lastSettledDay`(32) = 192 bits (64 spare for future). Pre-launch redeploy-fresh makes the extra slot free of migration cost. The per-buy hot path then does ONE warm SSTORE to this slot (after the first touch in a window it is warm) — the GAS-02 "no NEW cold per-buy SSTORE" goal is met **within a window** (the first buy of a window is cold; subsequent buys warm-write). Net: cheaper than the per-buy cross-contract storm by a wide margin regardless.
- **Option C — re-pack `Sub` to make room.** Narrow `validThroughLevel`→uint24, drop `reinvestPct` if v56 removes reinvest, etc. High-risk (touches CONSENT-01 pass-gating + reinvest semantics) for a 24→~40 bit gain that still doesn't reach 192. **REJECT — invariant-trading for no real win.**

**SPEC decision to lock:** Option B — a new packed accumulator slot, with the §3.2 field widths. Record that GAS-02's "Sub spare-bits" framing is superseded by the attested 232/256 occupancy; GAS-02 is satisfied by "one warm per-buy SSTORE into a dedicated accumulator slot, cold only on the window's first buy."

---

## 4. Quest-Core Non-Perturbation Surface + ±10 Derivation (QST design feed)

### 4.1 The shared `DegenerusQuests` core: callers + access [VERIFIED: source read]

| Caller | Entry | Access context | Return handling |
|--------|-------|----------------|-----------------|
| `DegenerusGameMintModule.sol:1222` | `handlePurchase` (manual buy) | GAME (delegatecall) → `onlyCoin` allows GAME | `:1232` re-credit (O1) |
| `GameAfkingModule.sol:760` | `handlePurchase` (afking buy) | GAME (delegatecall) → `onlyCoin` allows GAME | `:770` re-credit (O1 mirror) |
| `DegenerusAffiliate.sol:580` | `handleAffiliate` | AFFILIATE → `onlyCoin` allows AFFILIATE | routed once |
| `BurnieCoin.sol:613` | `handleDecimator` | COIN → `onlyCoin` | weight-boost dual-use (intended) |
| `BurnieCoinflip.sol:275` | `handleFlip` | COINFLIP → `onlyCoin` | credited once via caller |
| `DegenerusGameDegeneretteModule.sol:467` | `handleDegenerette` | GAME (delegatecall) → `onlyCoin` | return ignored (internal credit) |
| `DegenerusGameBoonModule.sol:325` | `awardQuestStreakBonus` | GAME → `onlyGame` | — |
| `DegenerusGameAdvanceModule` | `rollDailyQuest`/`rollLevelQuest` | GAME → `onlyGame` | — |

The `onlyCoin` modifier (`:310-319`) admits **COIN, COINFLIP, GAME, AFFILIATE**; `onlyGame` (`:321-324`) admits GAME only. A new **batched-settle entrypoint** added to the core must be `onlyGame`-gated (it is invoked from the GAME-context settle leg) and must operate on **`questPlayerState[player]`** + **`questStreakShieldCount[player]`** only.

### 4.2 What the entrypoint reads/writes + how to prove non-perturbation [VERIFIED: struct read]

`PlayerQuestState` (`DegenerusQuests.sol:264-...`): `lastCompletedDay`(uint24), `lastActiveDay`(uint24), `streak`(uint24), `baseStreak`(uint24), `lastSyncDay`(uint24), `lastProgressDay[2]`, `lastQuestVersion[2]`, `progress[2]`(uint128), `completionMask`(uint8; bit7 = `QUEST_STATE_STREAK_CREDITED`, `:185`).

**Non-perturbation proof strategy (the SPEC must lock; TST 356 proves):**
- The batched-settle entrypoint MUST mirror `awardQuestStreakBonus` (`:365-384`) semantics for the streak (it calls `_questSyncState` then mutates `state.streak` + `state.lastActiveDay`) and MUST NOT touch slot-1 (`progress[1]`, `lastProgressDay[1]`, `lastQuestVersion[1]`) — slot-1 is the player's manual quest (QST-01). It touches slot-0 accrual only.
- **Non-perturbation = the manual/bingo/degenerette/boon callers produce byte-identical `PlayerQuestState` with the entrypoint present vs absent**, for any interleaving. The entrypoint adds writes to `streak`/`lastActiveDay`/`lastCompletedDay`/`lastSyncDay` (the same fields `awardQuestStreakBonus` + `_questSyncState` already write) — so the proof reduces to: the entrypoint's writes are **commutative-or-ordered-identically** with the existing handlers' writes for the afk-covered days. The `lastSyncDay`/`completionMask` reset logic (`:1312-1317`) already serializes by day; the entrypoint must call `_questSyncState` first (like `awardQuestStreakBonus:369`) so it respects the same day-reset.

### 4.3 The ±10-streak / confirmed-vs-provisional derivation (QST-02/QST-03) [VERIFIED: source read]

The existing machinery the SPEC reuses:
- **Streak add lever:** `awardQuestStreakBonus` (`:365`) is the ONLY add-streak path; it is `onlyGame` and adds `amount` days. **The footgun the SPEC must avoid:** if the +10 pre-credit went through an injectable player-controllable add, a player could inflate the streak before the confirmed delivery. The lock: the +10 is applied to a **provisional** counter in the accumulator (the new slot, §3), and the **confirmed** streak (`state.streak`) is only advanced at settle for **delivered days** — gated by an immutable marker.
- **Gap-reset:** `_questSyncState` (`:1285-1318`) zeroes `state.streak` when `currentDay > anchorDay + 1` (`:1306`), UNLESS `questStreakShieldCount[player]` covers the gap (`:1290-1304`). **The active-pass anti-reset (QST-03):** an active afking pass should suppress the gap-reset without a daily write. The existing `questStreakShieldCount` is the precise mechanism — the SPEC should lock that an active afking sub credits shields (or the entrypoint sets `lastActiveDay`/`lastCompletedDay` to the afk-covered day so `anchorDay` stays current, suppressing the reset). Recommend the marker-update approach (no shield-balance accounting): on settle, advance `lastActiveDay`/`lastCompletedDay` to the last afk-covered delivered day.
- **Double-credit guard (QST-03):** `lastCompletedDay` (`:265`) + `QUEST_STATE_STREAK_CREDITED` (`:185`, set at `:1590-1596`) already prevent crediting the same day twice. The SPEC introduces `afkCoveredThroughDay` (in the new slot) as the afk-side analog: the entrypoint credits streak ONLY for days in `(afkCoveredThroughDay, settleDay]` and advances `afkCoveredThroughDay = settleDay`. A manual completion on an afk-covered day must not double-credit — keyed on `lastCompletedDay` vs `afkCoveredThroughDay` (credit the streak once per day, whichever path reaches it first). **Slot rewards are NEVER suppressed** (only the duplicate streak credit) — the SPEC locks that the guard gates `state.streak` advancement, never the slot-0 reward accrual.

**The immutable debit-gated marker shape to lock:** the confirmed streak reads ONLY from `state.streak`, which is advanced ONLY by the settle entrypoint for delivered days `(afkCoveredThroughDay, settleDay]`, with `afkCoveredThroughDay` monotone-advanced in the same write (debit-gated: each day credited exactly once, the marker is monotone like `lastOpenedDay`/`lastAutoBoughtDay`). No player-callable path can add to `state.streak` ahead of delivery → no pre-credit-EV inflation (QST-02). The +10-at-subscribe is provisional (accumulator only); it converts to confirmed streak only as days are delivered.

---

## 5. O1 Fix + Dead-Code Verification + the afking-handlePurchase-per-buy ANSWER

### 5.1 O1 fix is non-perturbing to BOTH callers [VERIFIED: source read]

The fix (D-03): drop `DegenerusQuests.sol:890` (`coinflip.creditFlip(player, lootboxReward)`), keep `lootboxReward` in `totalReturned` (`:893`).

- **MintModule caller (`:1222-1232`/`:1367`):** today receives `questReward` (= `totalReturned` = `ethMintReward + lootboxReward`), adds to `lootboxFlipCredit` (`:1232`), credits once at `:1367`. After the fix, the return is unchanged (still includes `lootboxReward`) and `:890` no longer fires → the lootbox reward is credited EXACTLY ONCE (via `:1367`). The eth-mint leg was always return-only; the burnie-mint leg (`:887`, kept) was always internal-only. **Non-perturbing to MintModule: confirmed — it already re-credits the return; dropping `:890` removes the duplicate.**
- **Afking caller (`:760-770`):** today receives the same return, adds to `flipCredit` (`:770`), credits once at `:831`. Same logic — dropping `:890` removes the duplicate for the afking per-buy path too. **BUT see §5.3 — under v56 this caller is removed from the per-buy path.**

### 5.2 `handleLootBox` dead-code removal is safe [VERIFIED: grep]

`handleLootBox` (`:698-741`) has **zero production callers** (grep across `contracts/` finds only the comment refs at `:746` and `IDegenerusQuests.sol:126`, plus the interface decl `:107`). References live only in tests: `test/fuzz/CoverageGap222.t.sol` + `test/unit/DegenerusQuests.test.js` (D-05 names the access-control tests to remove). Removing the function + interface entry `:107` + those tests is safe; pre-launch redeploy-fresh accepts the interface break.

### 5.3 **THE KEY OPEN QUESTION (deferred from discuss) — ANSWERED**

> *Does the AFKING path (`GameAfkingModule:760`) still call `handlePurchase` per-buy under the v56 aggregator, or is that call removed when quest work defers to the settle?*

**Today (v55, frozen `453f8073`):** the afking LOOTBOX path **DOES** call `quests.handlePurchase` per-buy at `GameAfkingModule.sol:760`, AND both `affiliate.payAffiliate` calls (`:806`, `:816`), AND a per-buy `coinflip.creditFlip` (`:831`). The comment at `:736-746` explicitly says this branch "RESTORES the manual-lootbox BURNIE side-effects (v55 box-redesign regression fix, 349.2)" — i.e. the per-buy storm IS the 349.2-restored quest+affiliate work. The ticket path (`:713-731`) routes through `MintModule.purchaseWith`, which does its OWN inline `handlePurchase`+`payAffiliate` (`:1222`/`:1269`).

**Under v56 (the aggregator, AGG-01/TKT-01):** these per-buy cross-contract calls are **REMOVED from the per-buy path** — the lootbox stamp branch keeps only the cheap stamp (`:793-794`) + the cheap accrual into the new accumulator slot; the ticket branch is replaced by the minimal `_queueTicketsScaled`-equivalent write (no `purchaseWith`). The `handlePurchase`/`payAffiliate`/`creditFlip` work moves to the **settle leg**.

**Implication for the O1 fix:** because the afking per-buy `handlePurchase` call disappears, the O1 fix's coverage of the afking caller is moot **for the per-buy path**. What matters instead: the **settle leg** now performs the deferred lootbox-quest credit, and the SPEC must lock that **the settle credits the lootbox-quest reward through exactly ONE `creditFlip`** (inheriting the post-fix invariant — the settle's quest call returns the reward, the settle batches it into its single `creditFlip`, and the dropped `:890` means no internal double-credit). **The SPEC must record:** O1 is fixed at the source (`:890` dropped) AND the v56 afking settle must not re-introduce a double-credit (route the deferred lootbox reward through the settle's single batched `creditFlip`, never an internal one). TST 356 + TERMINAL 357 verify the afking settle credits once.

---

## 6. Afking OPEN-end Review (OPEN design feed) [VERIFIED: source read]

### 6.1 The path

`mintBurnie` (`GameAfkingModule.sol:985`) is the permissionless router: priority (1) `advanceGame` (`:993-996`), else (2) `_autoOpen(OPEN_BATCH)` (`:1001`). `_autoOpen` (`:938-966`) walks `_subscribers` from `_subOpenCursor`, opening up to `maxCount` (=`OPEN_BATCH`=200, `:191`/`:939`) materializable boxes; per-sub `_openAfkingBox` (`:888-910`) advances `lastOpenedDay = lastAutoBoughtDay` BEFORE the resolve (`:892`, effects-first) and delegatecalls `resolveAfkingBox` (`:897-908`).

### 6.2 Live-level parity with human `openLootBox` [VERIFIED]

`resolveAfkingBox` (`DegenerusGameLootboxModule.sol:877-...`) is the LIVE-LEVEL twin of `resolveLootboxDirect` (`:763`). It rolls `currentLevel = level + 1` LIVE (`:894`), exactly like `resolveLootboxDirect:767`. The TWO deviations (documented `:828-835`): (1) the RNG word is caller-passed `rngWordByDay[lastAutoBoughtDay]` (the frozen stamp-day word, `:905`), and (2) the seed `day` is the FROZEN stamp day (`:904`/`:889`), NOT the live day — the freeze prevents seed-grinding by open-timing. Tail flags match the human box (`emitLootboxEvent = true`, `payColdBustConsolation = true`, `:912-913`); the one intentional non-parity is the distress bonus (`distressEth = 0`, `:862`, a mega-niche final-day feature the stamp-only box deliberately omits, BOX-02).

### 6.3 No double-open / EV-cap exactly-once / no shared-state hazard [VERIFIED]

- **No double-open:** `_afkingBoxReady` (`:918-922`) gates on `lastOpenedDay < lastAutoBoughtDay && rngWordByDay[...] != 0`; `_openAfkingBox` advances `lastOpenedDay` BEFORE the resolve (`:892`), so a re-entrant or re-walked open sees the predicate false → no-op. `lastOpenedDay` is monotone (OPEN-02). Confirmed.
- **EV-cap shared exactly-once:** `resolveAfkingBox` does the SINGLE `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` RMW (`:902`), keyed `[player][currentLevel]` on the SAME `lootboxEvBenefitUsedByLevel` map (`:473`/`:488`) the human buy-time write uses (BOX-05). The afking buy-time EV write is BYPASSED (the stamp-only process never reaches `DegenerusGameMintModule:1303`/`:1327`, per the `resolveAfkingBox` doc `:846-848`) → the open is the single draw, no double-draw. Confirmed.
- **No shared-mutable-state hazard:** the human route (`openLootBox`, `:503`, keyed `lootboxEth[index][player]` cold ledger) and the afking route (stamp in `Sub`, no cold ledger) are disjoint in their materialization storage; they SHARE only the per-`(player,level)` EV-cap budget, which is the intended single shared 10-ETH budget (BOX-05). Confirmed.

### 6.4 Cheapest viable shared materialization

The afking open already shares `_resolveLootboxCommon` (`:904`) with the human path — that IS the cheapest viable shared materialization (the resolve logic is one function; only the seed-source + day-freeze differ). The v56 OPEN-01 optimization target is the per-open marginal (~74-78k, v55 351 measurement) + the `OPEN_BATCH`/`_autoOpen` walk cost. **SPEC lock for OPEN:** the v56 accrual/settle refactor must NOT touch the open path's freeze/parity guarantees — re-verify after the refactor that `resolveAfkingBox` still reads `level + 1` live and the frozen seed-day, and that the accumulator slot does not collide with the open's `lastOpenedDay`/`lastAutoBoughtDay` markers (they stay in the original `Sub` slot; the accumulator is a separate slot per §3 → no collision).

---

## 7. XMODEL-01 CLI Invocation Templates [VERIFIED: both CLIs smoke-tested live, 2026-06-01]

Both CLIs are installed at `/home/zak/.local/bin/` and authenticated:
- `codex` → `@openai/codex` (model **gpt-5.5**, confirmed by smoke test `CODEX_OK`, exit 0).
- `gemini` → `@google/gemini-cli` (smoke test `GEMINI_OK`, exit 0).

**Do NOT use the v52 `coordinator.sh`** — it is a Claude-only harness (`claude -p`, `.planning/audit-v52/bin/coordinator.sh:200`); it never invokes codex/gemini. Use the bespoke per-concern templates below (D-11).

### 7.1 Codex — headless single-shot, read-only sandbox

```bash
# Prompt as argument (read-only — design review never edits):
codex exec --sandbox read-only --skip-git-repo-check \
  -o /tmp/xmodel-codex-<concern>.txt \
  "$(cat /path/to/prompt-<concern>.md)"

# Or pipe the prompt on stdin (use "-" or omit the positional):
cat /path/to/prompt-<concern>.md | codex exec --sandbox read-only --skip-git-repo-check -

# Pin a model explicitly if desired:
codex exec --sandbox read-only --skip-git-repo-check -m gpt-5.5 "<prompt>"
```
- `exec` = non-interactive (`codex exec --help`). Prompt from arg, or stdin if `-`/omitted.
- `--sandbox read-only` = no writes (design input, not a code change). `-C <dir>` sets the workdir if not cwd.
- `-o, --output-last-message <FILE>` captures the final answer to a file; `--json` for structured streaming if needed.
- `--skip-git-repo-check` avoids the in-repo prompt friction.

### 7.2 Gemini — headless single-shot, plan (read-only) mode

```bash
# Prompt via -p (headless); plan mode = read-only:
gemini -p "$(cat /path/to/prompt-<concern>.md)" \
  --approval-mode plan -o text > /tmp/xmodel-gemini-<concern>.txt

# Pin a model + include the contracts dir for grounding:
gemini -p "<prompt>" --approval-mode plan -m gemini-2.5-pro \
  --include-directories contracts -o text
```
- `-p, --prompt` = non-interactive headless mode (`gemini --help`). Stdin is appended to `-p` if piped.
- `--approval-mode plan` = read-only (no edits). `-y/--yolo` is the opposite — do NOT use for a review pass.
- `-o text` (or `json`) sets the output format. `--include-directories contracts` grounds it on the source.

### 7.3 Per-concern prompt skeleton (feed both models the SAME bespoke prompt per concern)

Run FIVE concerns (D-11), each as its own prompt to BOTH models, then fold into a disposition table:

| # | Concern | Prompt focus |
|---|---------|--------------|
| C1 | Strategic sub/unsub edge | "A player subscribes, accrues affiliate+quest into a per-sub accumulator, then unsubscribes (triggering a deterministic-75/20/5 flush at locked params) and re-subscribes. Can they extract more value than a steady subscriber? The roll buyer-never-wins (`winner != sender`), the taper is per-buy immutable, double-settle is gated by `windowStartDay`/`lastSettledDay`. Find any positive-EV churn vector." |
| C2 | Settle-timing / roll-seed | "The scheduled flush rolls a winner-takes-all affiliate payout seeded by `keccak256(TAG, windowBoundaryDay, sender, code) % 20`. The player-triggered flush uses a deterministic split (no roll). Can a player select a favorable seed by timing the flush? The buyer never receives the roll." |
| C3 | Ticket-mode primitive parity | "Afking ticket subs will use a minimal `_queueTicketsScaled`-equivalent write (no `purchaseWith`), KEEPING the century/x00 bonus at parity (reusing the existing `centuryBonusLevel`/`centuryBonusUsed` storage + the per-buy activity score) while deferring affiliate/quest to the settle. Does keeping the century bonus at parity or deferring affiliate/quest to the settle create any exploit or resolution mismatch vs the manual ticket leg?" |
| C4 | Open-end unmanipulability | "The afking box opens at the LIVE level from a FROZEN stamp-day seed + frozen word, sharing the per-(player,level) EV-cap with the human path, `lastOpenedDay` monotone. After moving affiliate/quest to a deferred settle, is the open still unmanipulable (no double-open, no EV double-draw, no level/seed timing edge)?" |
| C5 | Long-run gas | "Suggest gas optimizations for the per-buy accrue (one warm SSTORE into the RE-PACKED Sub slot — whole-BURNIE affiliate base + 100M clamp + milli-ETH amount + narrowed day/level fields, NO new cold slot), the ~10-day settle leg, and the `OPEN_BATCH` open walk — without weakening any unmanipulability invariant." |

**Disposition table to produce (folded into the design-lock BEFORE IMPL):**

| Concern | Codex verdict | Gemini verdict | Disposition (FOLD / REJECT-with-reason / NEEDS-DESIGN-CHANGE) |
|---------|---------------|----------------|----------------------------------------------------------------|
| C1..C5 | … | … | … |

---

## 8. Threat-Model Invariants + How TST 356 Proves Them (SEC design feed)

> `security_enforcement` is ON. This is a Solidity protocol-internal phase; the standard "ASVS web categories" map onto the protocol's own invariant set. The threat model IS the unmanipulable + SOLVENCY-01-untouched + RNG-freeze-intact re-attestation.

### 8.1 The invariants the SPEC must assert

| Invariant | Source anchor | How TST 356 proves it |
|-----------|---------------|------------------------|
| **SEC-01 strategic sub/unsub yields no positive EV** | roll `:558`/buyer-never-wins `:579`; taper `:787`; double-settle markers (new slot) | a churn loop (subscribe→accrue→unsub-flush→re-subscribe) cannot beat a steady sub: assert total BURNIE credited via churn ≤ steady; the player-triggered flush uses the deterministic split at locked params |
| **SEC-01 no settle-timing edge** | `currentDayIndex()` pure-of-`block.timestamp` (`GameTimeLib.sol:21`); buyer-never-wins | assert flush at day N vs N+1 yields identical buyer EV (zero — buyer never receives the roll) |
| **SEC-01 no double-settle** | `windowStartDay`/`lastSettledDay` (new slot, AGG-05) | assert a second scheduled flush in the same window is a no-op; a player-flush resets the window |
| **SEC-01 no pre-credit-EV inflation** | confirmed streak read from `state.streak`, advanced only at settle for delivered days; `awardQuestStreakBonus` `onlyGame` | assert the +10-at-subscribe is provisional; `state.streak` advances only as days deliver; no player path adds to `state.streak` |
| **SEC-01 no double-credit (O1)** | `:890` dropped; settle credits lootbox reward once | assert a completed lootbox quest credits exactly once on both manual + afking-settle paths |
| **SEC-02 SOLVENCY-01 untouched** | ETH/pool debit `GameAfkingModule.sol:709-710` (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`); affiliate/quest are BURNIE `creditFlip` only (`:831`) | delta-audit: the ETH/`claimablePool` debit is **byte-unchanged** vs `453f8073`; affiliate/quest never touch the ETH path (BURNIE-emission-timing change only) |
| **SEC-02 RNG-freeze intact** | open seed frozen at stamp day (`resolveAfkingBox:889`/`:904`); accrue/settle touch no `rngWordByDay`/frozen-window slot | assert the accumulator slot is disjoint from RNG-window state; the open still uses the frozen stamp-day word + day |
| **QST-04 quest-core non-perturbation** | `onlyGame` entrypoint touches only `questPlayerState`/`questStreakShieldCount`, slot-0 only | assert manual/bingo/degenerette/boon callers produce byte-identical `PlayerQuestState` with the entrypoint present vs absent |
| **OPEN-02 two-path coexistence** | disjoint materialization storage; shared EV-cap exactly-once (§6.3) | assert human + afking opens at the same level share the one EV-cap budget, no double-draw, no shared-state corruption |

### 8.2 STRIDE-style protocol threat patterns

| Pattern | Category | Standard mitigation (attested) |
|---------|----------|--------------------------------|
| Settle-timing to select a favorable affiliate roll | Tampering / EV-manipulation | roll seeded by un-choosable wall-clock day; buyer never wins; deterministic split on player-flush |
| Churn to re-rate / re-roll / dodge a streak penalty / harvest a settlement | Elevation-of-privilege (EV) | player-flush at locked params (mutator pays gas → churn self-limits); double-settle markers; immutable per-buy taper |
| Pre-credit streak inflation | Tampering | confirmed-streak read from debit-gated monotone marker; no injectable player add-lever |
| Lootbox-quest double-credit (O1) | Repudiation / over-mint | drop `:890`; single batched `creditFlip` |
| Open-timing to grind the box seed/level | Tampering (RNG) | frozen stamp-day seed + word; live-level open is auto-opened (player can't time it) |
| Solvency drain via affiliate/quest | Tampering (funds) | affiliate/quest are BURNIE flip-credit OFF the ETH/`claimablePool` path; ETH debit byte-unchanged |

---

## 9. Open Risks / Drift the SPEC Must Reconcile

1. **[HIGH] Accumulator slot premise.** The "Sub spare-bits (176/256)" framing in CONTEXT/PLAN/ROADMAP is inaccurate — the slot is at **232/256 (24 spare)**. The accumulator needs ~192 bits → a **new dedicated slot** (Option B, §3). The SPEC must record this and re-frame GAS-02 as "one warm per-buy SSTORE into a dedicated accumulator slot (cold only on the window's first buy)." [VERIFIED: `DegenerusGameStorage.sol:1867-1899`]

2. **[MEDIUM] The afking per-buy storm IS the 349.2 restoration.** The afking lootbox branch's per-buy `handlePurchase`+`payAffiliate`+`creditFlip` (`:760`/`:806`/`:816`/`:831`) was deliberately restored in v55 349.2 to fix a regression. The v56 aggregator REMOVES it from the per-buy path (deferring to settle) — the SPEC must confirm the **eventual** affiliate/quest credit at settle is equivalent to the per-buy storm's credit (modulo the accepted settle-timing/option-A simplifications), so v56 does not re-introduce the 349.2 regression in a new form. [VERIFIED: `GameAfkingModule.sol:736-746`]

3. **[MEDIUM] O1 fix scope under v56.** Because the afking per-buy `handlePurchase` disappears (risk #2), the O1 fix is (a) drop `DegenerusQuests:890` at the source, AND (b) ensure the v56 afking **settle** routes the deferred lootbox-quest reward through exactly ONE `creditFlip` (never an internal one). The SPEC must lock both halves. [VERIFIED: §5]

4. **[LOW] Force-flush-before-jackpot decision.** Resolved: NOT needed — the 5%-proportional claim reads cumulative `affiliateScore`/`totalAffiliateScore` (exact regardless of option-A lag), and the 1%-top is a minority-slice ranking the SPEC accepts the lag on. The SPEC should DECLINE the force-flush path with this rationale. [VERIFIED: §2.4]

5. **[LOW] Bare-name + off-by-one anchor citations.** `MintModule:1243`→`DegenerusGameMintModule.sol:1243`; storm `:760-831`→`:708-833`; `claimAffiliateDgnrs` `:217`→`:216`; `handleLootBox` `:698-742`→`:698-741`. The SPEC should cite the corrected paths/lines.

6. **[LOW] `currentDayIndex()` in the settle roll.** The SPEC must lock that the scheduled-flush roll seeds on the **window-boundary day** (a deterministic function of the sub's subscribe day), NOT the live settle-call `currentDayIndex()` — otherwise a keeper could nudge the seed by choosing WHEN to call the flush within a day-boundary. `currentDayIndex()` only changes at the 22:57-UTC boundary, so the risk is small, but the SPEC must assert the seed is the boundary day to keep "no by-construction" honest. [VERIFIED: `GameTimeLib.sol:21-34`]

## Open Questions

None blocking. All deferred-from-discuss research items are resolved above (the afking-per-buy answer §5.3, the accumulator layout §3, the ±10 derivation §4, the force-flush decision §2.4).

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `codex` CLI | XMODEL-01 design-input pass | ✓ | `@openai/codex` (gpt-5.5) | — |
| `gemini` CLI | XMODEL-01 design-input pass | ✓ | `@google/gemini-cli` | — |
| `git` (frozen-subject attestation) | SC5 anchor re-attestation | ✓ | (repo) | — |
| `forge` | NOT needed at SPEC (paper-only) | n/a | — | — |
| ripgrep | gemini grep grounding (optional) | ✗ | — | gemini falls back to GrepTool (smoke test confirmed) |

**Missing with no fallback:** none. **Missing with fallback:** ripgrep (gemini auto-falls-back to GrepTool — observed in the smoke test, non-blocking).

## Validation Architecture

> The empirical proofs are owned by TST 356 (SEC-01/SEC-02); this SPEC phase is paper-only. §8 maps each invariant to the TST proof obligation. No test files are authored at 353. Wave-0 test gaps belong to 354/356, not here.

## Sources

### Primary (HIGH confidence)
- Frozen subject `453f8073` (== working tree `contracts/`, verified by `git diff --quiet`) — all `file:line` anchors read directly.
- `codex exec --help` / `gemini --help` + live smoke tests (both exit 0) — XMODEL-01 invocation.

### Secondary
- `.planning/PLAN-V56-AFKING-BATCHING-GAS.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `353-CONTEXT.md` — the USER-converged design + the locked decisions.

## Metadata

**Confidence breakdown:**
- Anchor attestation: HIGH — every cited anchor read from the frozen subject; drifts enumerated.
- AFF-01/AFF-02 + threat model: HIGH — roll/taper/buyer-never-wins/leaderboard all source-read.
- Accumulator layout: HIGH — the 232/256 occupancy is directly counted from the struct.
- O1 + afking-per-buy answer: HIGH — both callers + the storm + the removal semantics source-read.
- XMODEL CLIs: HIGH — both smoke-tested live with confirmed output + exit 0.

**Research date:** 2026-06-01
**Valid until:** stable while the subject stays frozen at `453f8073` (re-attest if the baseline moves). CLI flags valid until codex/gemini are upgraded.

## RESEARCH COMPLETE
