# Phase 398 — LEVEL-SEMANTICS: dual-net findings (v64.0)

**Status:** ✅ COMPLETE — both nets on record, adjudicated vs frozen source.
**Requirements:** LVL-01..07 · **Census:** 199–207 level/level+1 sites (mint 35 · lootbox 32 · jackpot 23 · advance 21 · storage 19 · afking 17 · whale/dec/degen 22 · affiliate/quests/Game/PriceLookup 30+).
**Nets:** NET-1 council (gemini + codex, 0 skipped) · NET-2 Claude Workflow (7 subsystem analyzers + adversarial-verify). Subject frozen `de0e03d5` at sweep time (fix moved it to `402855e1`).

## Outcome: 0 HIGH / 0 MED in the level-semantics class. 1 CONFIRMED LOW (FIXED). 

| # | Site | Disposition | Detail |
|---|------|-------------|--------|
| LVL-A | `GameAfkingModule.sol:877` lootbox streak-basis | ✅ **CONFIRMED LOW → FIXED `891f7a8f`** | **Convergent** (NET-2 + gemini). Lootbox-mode `_playerActivityScore` passed `currentLevel + 1` as streakBaseLevel instead of `_activeTicketLevel()` (== `ticketTargetLevel`, in scope; == the level the streak is recorded against at MintModule:1698). In jackpot phase these differ → silently zeroes an afker's manual streak whose `lastCompleted == level-1` → up to ~6–8% lower-EV capped box vs an equal manual buyer. Player-disadvantaging, no attacker gain. Fix = pass `ticketTargetLevel`; EV-cap key + resolver open level stay `currentLevel+1` (correctly future-keyed). |
| LVL-B | Affiliate leaderboard freshest-bucket exclusion | **USER BY-DESIGN** | gemini called it a 1-level producer/consumer gap (producers write `L+1`: `payAffiliate(cachedLevel+1)` + `claim()` `level()+1`; consumer `affiliateBonusPointsBest(currLevel)` reads `currLevel-1..-5`, missing bucket `currLevel`). codex ruled it intentional. **USER 2026-06-15: BY-DESIGN — "missing the freshest bucket is by design so there is no inter-level bullshit"** (the just-completed level's affiliate earnings don't bleed into the activity-score bonus while that level is still live). This is the long-carried affiliate-score asymmetry — now formally dispositioned, do not re-flag. |
| LVL-C | `DegenerusQuests._isLevelQuestEligible:1984` `unitsLvl == lvl+1` | **REFUTED (correct-by-design)** | codex-only ("a player who bought into the resolving level fails"). REFUTED by a dedicated trace + verify-agent: the level quest targets `level+1` (the level being FILLED — matching the `level+1 price` at MintModule:1682-1688 / natspec :791/:1378), NOT the jackpot level being resolved. The quest version is live across the jackpot phase of L AND the following purchase phase building L+1 (`level` stays L the whole lifespan; re-rolled only at the next jackpot entry). The gate is satisfiable in that purchase phase (buys target `level+1` → `unitsLvl = L+1 == lvl+1`), so a genuine participant who mints 4+ into L+1 completes it (`creditFlip 800 BURNIE`). codex mis-identified the target level; gemini + NET-2 found the path clean. **Routed test-hardening:** no test covers level-quest completion (coverage gap, not a contract defect). |
| LVL-D | `DegenerusGame.getPlayerPurchases:2424` | **INFO (no on-chain consumers)** | NET-2. Reads `_tqWriteKey(level)` instead of `_tqWriteKey(_activeTicketLevel())`; during purchase phase shows a stale/empty count for tickets just bought into level+1. Frontend convenience getter, **zero on-chain callers**, no security/solvency/streak/leaderboard impact; `purchaseInfo().lvl` + `ticketsOwedView(lvl,…)` already give a correct frontend the right data. INFO. |
| LVL-E | Whale/pass buys target `level+1` unconditionally (`WhaleModule` bundle/lazy/deity/claim) | **BY-DESIGN** | Both council models flagged the unconditional `level+1` (not phase-gated), both noted passes are future-only products by design (a pass front-loads the upcoming levels; it is not meant to buy the jackpot-phase current level). Documented exception, not a bug. |

## Level-semantics map (the correct site classes — both nets clean)

- **Purchase target:** direct (`MintModule:2040` `jackpotPhaseFlag?cachedLevel:cachedLevel+1`) + afking (`GameAfkingModule:1148` same) use `_activeTicketLevel()`. ✅ Final-jackpot-day locked reroute to `level+1` (MintModule:2043) intentional.
- **Mint-streak basis (manual):** recorded at `_activeTicketLevel()` (MintModule:1698), read at `jackpotPhaseFlag?currLevel:currLevel+1` (MintStreakUtils:372) — agree. ✅ (the afking lootbox read was the LVL-A divergence, now fixed.)
- **Jackpot accrual:** resolves current `lvl`; next-level pool `levelPrizePool[newLevel-1]` aligns with the `lvl-1` reader. ✅
- **Lootbox EV-cap / resolve key:** `currentLevel+1` across direct/redemption/afking — the future open level. ✅ (intentionally distinct from the streak basis).
- **Far-future salvage:** distance `d = L - _activeTicketLevel()` (cl). ✅
- **Boundaries:** level 0 (affiliate bonus + streak-effective early-return 0; afking passless level-0 slip blocked); century x00 (target/current per role); gameover terminal (decimator `decBucketOffsetPacked[lvl+1]` written/read consistently; terminal decimator pays `lvl`, terminal ticket jackpot `lvl+1`). ✅

## Verdict
The whole-codebase `lvl` vs `lvl+1` examination (USER's headline ask) is **clean except one LOW off-by-one (afking lootbox streak-basis), now fixed `891f7a8f`.** The affiliate-score asymmetry is USER BY-DESIGN; the codex quest lead is REFUTED; the getter is INFO; whale/pass `level+1` is by-design. Both nets on record. LVL-01..07 attested.
