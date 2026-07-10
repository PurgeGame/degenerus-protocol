# Quests fable sweep — bucket-(a) candidate ledger (2026-07-10, tree 9777a3f7 / HEAD 30914a56)

Sweep: `fable-contract-review` run `wf_a419e4d2-2dd`, 24 chunks over `contracts/DegenerusQuests.sol` (2445 lines), neutral tactic T0, 0 balks. 19 clean / 5 concerns. Only bucket-(a) "definite inconsistencies" promoted here; (b) invariant-guarded and (c) cosmetic dropped. Council adversarial-verify pending (biased-to-refute, decorrelate Claude lenses + Codex).

## Family A — counter/version width overflow

### F1 — levelQuestVersion uint8 wrap defeats stale-progress invalidation (chunk 24)
- Site: `DegenerusQuests.sol:2291` `unchecked { ++levelQuestVersion; }`, field `uint8` at :331. `rollLevelQuest` called once per level transition (AdvanceModule:620); levels uint24 → 256+ rolls reachable in one game.
- Divergence 1 (player-adverse): completed at roll N, dormant 256 rolls; at N+256 `playerVersion==currentVersion` (:2375), :2380 short-circuits deltas → legit 800 FLIP (:2415) + streak bonus permanently unreachable that level.
- Divergence 2 (protocol-adverse, unearned payout): stale progress (bits 8-135, unitless; version is the only type discriminator) from a FLIP-denominated quest at roll N aliases at N+256 into an ETH-denominated target; large wei-scale stale value clears `progress>=target` (:2386) on first 1-wei delta → unearned 800 FLIP + LEVEL_QUEST_STREAK_BONUS(5). `getPlayerLevelQuestView` also reports stale as current.
- Reachability: needs 256 level rolls between a player's two level-quest state writes. Council Q: is a single game reaching 256+ levels realistic, and can a player be dormant-in-level-quest-paths across exactly a 256 window?

### F2 — shieldCenturyHighWater uint8 saturates → century-shield faucet (chunk 1)
- Site: `shieldCenturyHighWater` uint8 (:308) tracks `streak/CENTURY_SHIELD_INTERVAL`; `streak` uint16 (:299). At streak ≥ 25,600 (century ≥ 256) `_grantCenturyShield` (:554) stores high-water saturated 255 → every later streak write sees `century(256+) > highWater(255)` → re-grants `owed=century-255` shields. Idempotence claim (:167-168) breaks.
- Impact bounded: held shields still capped CENTURY_SHIELD_MAX_HELD=10 (:556-558); shields only preserve streaks.
- Reachability: streak ≥ 25,600 via `awardQuestStreakBonus` arbitrary uint16 boon credits (BoonModule:340), saturating not reverting. Council Q: can boon credits realistically push a live streak that high; is bounded-10 impact material?

## Family B — afking ↔ manual streak reconciliation / cross-day shield adjudication

### F3 — _questSyncState re-adjudicates the same missed-day gap across days (chunk 19 A1)
- Site: `DegenerusQuests.sol:1750-1764`. Gap measured from `anchorDay` (:1750) which only advances on slot-0 completion (:2067) / streak-bonus / foil-floor / afking-finalize — NEVER on shield-consume or streak-reset. `lastSyncDay` gate (:1748) only blocks WITHIN a day, not across. Doc (:1730-1733) claims shields can't be re-consumed for the same missed day; across days they are.
- Trace A: complete slot0 day10 (shield=2, days 11&12 rolled). Day12 non-completing action → missedDays=1, shield→1, streak kept, anchor stays 10. Day13 action → gap{11,12}, missedDays=2 > shields(1) → streak reset + last shield burned. Correct = 2 missed vs 2 shields → preserved. Triangular drain (1,2,3… per day) for a repeatedly-active non-completing player. Accounting-neutral partial action strictly worsens state.
- Trace B: retro-burn — shields granted day30 (no anchor/sync write) then action day31 → charged against historical already-punished gap, consumed with zero effect.
- Effect: streakShield ≠ granted−(distinct missed days); streak/baseStreak (:1787) diverge from doc (:1737-1738); QuestStreakShieldUsed over-reports.

### F4 — finalizeAfking rewrites state.streak mid-day without refreshing baseStreak/lastSyncDay (chunk 6 A1)
- Site: `:631-632`. If afker did any manual action earlier same day D, `_questSyncState` set `lastSyncDay=D`, `baseStreak=S` (dormant manual). Sub ends day D, finalize writes `state.streak=E`. Since `lastSyncDay==D`, `_effectiveBaseStreak` (:1441) returns stale S not E for rest of day; no later sync possible (:1748 early-return).
- Under-read: E>S when funded days delivered → decimator-weight/lootbox-EV/sDGNRS reads (:1345-1350) under-report until next quest day. Over-read: with missedDays!=0 (:631) streak zeroed while reads keep returning S>0 all day.

### F5 — finalizeAfking miss-adjudication double-charges a same-day shield-consumed miss (chunk 6 A2)
- Site: `:626-631`, `missLimit=1`, shield-blind. Afker shield=1, quest rolled D-1. Day D manual action → `_questSyncState` counts D-1 miss, burns shield, preserves streak. Same-day finalize recounts identical window (D-3,D) with missLimit=1 no shield check → missedDays=1 → zeroes everything (:631-632); shield-paid value overwritten. One missed day charged twice (shield + total loss). Corollary: :635 re-anchors lastValid=D-3 → next sync counts D-1 a third time.
- NOTE distinguish from documented-deliberate missLimit=1 for finalization (:1385-1391) — the DOUBLE-charge given a same-day consumed shield is the defect, not missLimit=1 itself.

### F6 — handleFoilPurchase snapshot uses manual streak, not afking-unified streak (chunk 12 A1)
- Site: `:1041-1044` `_effectiveBaseStreak(...)` for a buyer with `state.afkingActive` returns the manual decay-aware streak (already zeroed by missed-day decay for a mid-run afker), not the unified afking-aware streak every other activity-score consumer uses (`_effectiveQuestStreak` GameStorage:2399 "one unified value everywhere it is read"; mint path `_liveAfkingStreak` swap MintModule:1587-1588). Feeds FoilPackModule:292 `_playerActivityScore` → freezes `multBps` in `foilRecord` from ~0 streak while real reward streak is afking base + funded days. FoilPack:288-290 comment + `_foilStreakFloor` doc (~:495) both say afker reward streak = afking base. Player-adverse understatement typical; can overstate if a prior foil buy floored manual streak above a short run. EV-basis divergence only (no wrap/revert/pool imbalance).

## Cross-cutting context (verify in council)
- The quest rolled-day-BITMAP decay + afking streak logic was heavily reworked (3rd design; shield/banked-counter REJECTED) and shipped `b5b4f88f` — this is recently-rewritten code, high scrutiny warranted. F3/F4/F5/F6 all touch that reconciliation surface.
- Council must separate genuine accounting divergences from documented design-intent (esp. missLimit=1, bitmap decay intentional).

---

## COUNCIL DISPOSITIONS (run wf_9e1a0a96-465, 6×3 decorrelated refutation lenses, biased-to-refute)

| ID | Disposition | R/C/P | Net severity | Action |
|----|-------------|-------|--------------|--------|
| F3 | **STANDS** | 0R/3C/0P | LOW-MED correctness (real, reachable, breaks stated shield guarantee) | **PoC-gate → USER fix** |
| F1 | CONTESTED | 1R/0C/2P | LOW hardening (wrap real; theft severity collapsed) | widen counter / epoch guard — USER opt |
| F4 | CONTESTED | 1R/0C/2P | LOW / by-design-leaning (start-of-day pin is intended) | optional 1-line baseStreak refresh at finalize |
| F6 | CONTESTED | 0R/1C/2P | LOW correctness (self-adverse understatement) + stale comment | apply _liveAfkingStreak override like mint path; fix comment |
| F2 | DROPPED | 2R/0C/1P | — (bounded held-10 + unreachable streak≥25600) | none |
| F5 | DROPPED | 2R/0C/1P | — (refuted) | none |

**F3 confirmed mechanism (all 3 lenses, source-traced):** `_questSyncState` (:1747-1788) measures the missed-day gap from `anchorDay` (:1750), which advances ONLY on slot-0 completion (:2066-2067/:2089) / streak-bonus (:479-480) / foil-floor (:513-514) / afking-finalize (:635) — NEVER on shield-consume or streak-reset. `lastSyncDay` gate (:1748) blocks re-adjudication WITHIN a day only. `_missedQuestDays` (:1382-1420) is stateless — re-derives the whole gap from the stale anchor each call, with no memory of days already billed. `missLimit = streakShield+1` (:1755) means a decremented shield lowers BOTH the scan bound and the reset threshold next day.
- **Trace A (falsifiable, strictly-worse-than-idling):** slot-0 complete day10 (shield=2, days 11&12 rolled). Day12 partial (non-completing) FLIP/decimator → missedDays=1, shield→1, streak kept, anchor stays 10. Day13 action → gap{11,12}=2 > shields(1) → **streak reset to 0** (:1774). Idle counterfactual (no day12 action): day13 gap=2, shields=2, 2>2 false → **streak preserved**. Day11 charged twice (shield spent day12, re-counted day13).
- **Trace B:** shields granted after a lapse (`awardQuestStreakShield` :529-535 / `_grantCenturyShield` :546-561 write no anchor) are burned against the ancient already-punished gap on the next sync with zero benefit.
- Reachability: partial slot-0 progress (below-target FLIP stake / decimator burn / affiliate) on a rolled day inside an active gap; 2 shields reachable via century milestone (streak≥200) or shield boons (:529). Ordinary permissionless play.
- Breaks NatSpec :520-521 "Each shield absorbs one missed day, preserving the streak" and the spirit of :1737-1738; doc :1730-1733 idempotence is only intra-day.

**FIX DIRECTION (F3, for USER — contract edit, needs approval):** advance the gap anchor when a sync consumes shields / adjudicates a miss, so an already-billed day is not re-counted on a later day's gap. Candidate: after `_questSyncState` charges `used` shields for the `(anchorDay, currentDay)` window, move the effective gap base forward (e.g. set `lastSyncDay`-paired anchor to `currentDay-1`, or record a `lastAdjudicatedDay` the gap scan starts after) so subsequent syncs only bill NEW missed days. Must preserve: the reset-on-insufficient-shields path, the once-per-day gate, and level-quest-only streaks (both anchors 0) never decaying. Regression test = Trace A asserting partial-action outcome == idle-outcome (streak preserved when shields≥distinct-missed-days).
