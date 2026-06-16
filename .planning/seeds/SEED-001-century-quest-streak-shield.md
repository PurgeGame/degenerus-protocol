---
id: SEED-001
status: dormant
planted: 2026-06-15
planted_during: v64.0 Phase 399 (REWARD-MECHANICS)
trigger_when: after the v64.0 audit milestone ships (post-audit feature — contract change; needs contract-commit approval + a re-audit of the activity-score interaction)
scope: Small–Medium
---

# SEED-001: Century quest-streak shield grant

Award the player a **bonus quest-streak shield each time their quest streak reaches a new
hundred-mark** (100, 200, 300, …). A loyalty reward that lets relentless questers bank a small
buffer of missed-day protection.

## The locked design (USER, 2026-06-15)

- **Trigger:** each time quest streak crosses a new century (100, 200, 300, …) → grant **+1** shield.
- **Flat 1 per century**, no scaling by tier.
- **Idempotent:** keyed to the highest century already rewarded (a high-water marker), so dropping
  to 99 and re-crossing 100 cannot re-farm a shield.
- **Held balance capped at 10** (a player tops out at 10 banked shields = up to 10 missed days
  absorbed). _Open planning detail:_ the existing `streakShield` counter is shared with the lootbox
  quest-shield boon + the deity boon — decide whether the 10-cap is on the century contribution only
  or on the total held balance, and how it composes with those other sources.

> Design evolution this session: "per 50" → "per 100" → "+1 at each century" → "uncapped, stacking
> is fine, it's just a few days" → **final: cap held at 10.**

## Reuses the existing primitive (no new mechanic)

`DegenerusQuests.sol` already implements streak protection — this seed only adds a **new earn
trigger**, not a new system:

- `streakShield` — `uint8` per player, stackable, saturates at 255 (`DegenerusQuests.sol:280`).
- `awardQuestStreakShield(player, amount)` — GAME-only granter (`:439`).
- Consumed in `_questSyncState` on missed days — "each shield absorbs one missed day, preserving the
  streak instead of resetting it" (`:430`).
- `QuestStreakShieldGranted` / `StreakShieldsConsumed` events; `DEITY_BOON_QUEST_SHIELD = 4`
  (`DeityBoonViewer.sol:34`).
- Today shields are earned via the **lootbox quest-shield boon** and the **deity boon**. This seed
  fires the grant from the **streak-increment path** when a new century is reached.

## Open at planning

- **Channel:** does the century grant fire on the **afking** streak channel too, or **manual only**?
  (streak is afking-XOR-manual via `_effectiveQuestStreak`.)
- **Cap composition:** the 10-cap vs the lootbox/deity shield sources sharing the same counter.

## Security / economics re-audit flag (must clear before ship)

Shields **decouple the activity score from _recent_ engagement** — the exact property the reward-EV
reasoning leans on. Quest streak feeds activity score at **50 bps/level** (`MintStreakUtils.sol:327`),
which drives:

- the **lootbox EV multiplier** (→ 145% at score 40,000 bps), and
- the **Degenerette ROI** (→ 99.9% at 30,500 bps).

So streak **800** saturates the lootbox EV ceiling and (under per-century) banks **8** shields →
a flawless long-streak player could coast through ~8 missed days at max RTP. The 10-cap bounds this to
≤10 missed-day passes. Before building:

1. Re-run the **v63 "streak-pump REFUTED"** reasoning (completionMask dedup, slot-0 skip, ≤3/day,
   afking-XOR-manual) under the new persistence.
2. Apply the **economic-analyst** + **contract-auditor** lenses to the coast-at-max-EV scenario.
3. **Idempotency** (high-water marker) and the **activity-score interaction** are the two correctness
   anchors.

This is a contract change on a byte-frozen audit subject (`402855e1`) → a post-audit **feature**
milestone with its own contract-commit approval gate and re-audit. **Not** part of v64.0 (audit-only).

## Breadcrumbs

- `contracts/DegenerusQuests.sol:280` — `streakShield` storage field
- `contracts/DegenerusQuests.sol:439` — `awardQuestStreakShield` (the granter to call)
- `contracts/DegenerusQuests.sol:430` / `_questSyncState` — shield consumption on missed days
- `contracts/modules/DegenerusGameMintStreakUtils.sol:327` — quest streak → activity score (50 bps/level)
- `contracts/DeityBoonViewer.sol:34` — `DEITY_BOON_QUEST_SHIELD` (existing shield earn path)
- Activity-score saturations: lootbox 40,000 → 145%; Degenerette `ACTIVITY_SCORE_MAX_BPS` 30,500 → 99.9%; Decimator 23,500
