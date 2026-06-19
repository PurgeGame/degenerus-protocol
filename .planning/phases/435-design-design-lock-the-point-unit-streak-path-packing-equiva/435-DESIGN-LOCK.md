# Phase 435 — Design-Lock: Point Unit · Streak Path · Packing · Equivalence

**Phase:** 435 DESIGN (v69.0)
**Baseline subject:** `contracts/` tree `e9a5fc24` (v68.0 closure subject `3cc51d00`, logic-byte-frozen at milestone start)
**Posture:** Design-lock only — **NO `contracts/*.sol` change in phase 435.** The sole contract edit of the v69 milestone is the separate 436 IMPL gate; this document is its load-bearing input. All source references below are read-only re-confirmations against the frozen baseline.
**Vocabulary:** neutral defensive-engineering terms throughout.

This document records the USER-locked decisions D-01..D-05 (DESIGN-01 + DESIGN-02) with source-anchored rationale and an executor-ready per-symbol edit surface for 436. The remaining decisions D-06..D-10 (DESIGN-03 packing + DESIGN-04 equivalence) are recorded in plan 02's sections of this same document.

**Anchor re-confirmation note:** Every file:line anchor cited here was re-read against the frozen `e9a5fc24` tree while authoring. Corrections to the CONTEXT.md anchors (where the source is ground truth) are flagged inline with **[ANCHOR NOTE]**.

---

## DESIGN-01 — Point Unit, Quest-Streak Floor, Point Cap

Records the USER-locked decisions **D-01** (point unit), **D-02** (quest-streak floor rule), and **D-03** (point cap + storage width). Requirement: **DESIGN-01**.

### D-01 — The point unit: 1 point = 100 bps

The activity score is defined in **whole points**, where **1 point = 100 bps**. The activity score is the bps representation ÷ 100. The score is produced by `MintStreakUtils._playerActivityScoreAt` (`contracts/modules/DegenerusGameMintStreakUtils.sol:282-372`) and wrapped by `_playerActivityScore` (`:380`).

The point unit is exact for the whole computation **iff every additive contributor to `bonusBps` is a multiple of 100 bps** — then ÷100 is a clean integer for every leg and for their sum. The single exception is the quest-streak leg, which contributes 50 bps per quest (0.5 pt); D-02 below locks how that sole sub-point leg is converted.

### D-01 — Additive-contributor inventory of `_playerActivityScoreAt`

Re-confirmed leg-by-leg against `contracts/modules/DegenerusGameMintStreakUtils.sol:282-372` on the `e9a5fc24` tree. Each leg's bps form is shown with its source line and whether it is a clean multiple of 100 (so ÷100 is exact).

| # | Contributor | Source line | Current bps form | Point value | Multiple of 100? |
|---|-------------|-------------|------------------|-------------|------------------|
| 1 | Mint streak | `:329` | `streakPoints * 100` (streakPoints capped at 50, `:314`) | streakPoints (0..50) | ✅ clean (`×100`) |
| 2 | Mint count | `:330` | `mintCountPoints * 100` | mintCountPoints | ✅ clean (`×100`) |
| 3 | **Quest streak** | **`:335`** | **`uint256(questStreak) * 50`** | **0.5 pt each** | ⚠️ **NO — the SOLE 50-multiple / sub-point leg** |
| 4 | Affiliate | `:346` | `affPoints * 100` | affPoints (0..MASK_6) | ✅ clean (`×100`) |
| 5 | Deity base | `:310-311` | `50 * 100` + `25 * 100` = 7500 bps | 75 pt | ✅ clean (`×100` each) |
| 6 | Deity pass bonus | `:350` | `DEITY_PASS_ACTIVITY_BONUS_BPS` = **8000** | 80 pt | ✅ clean — **8000 mod 100 == 0** |
| 7 | Whale pass (10-level bundle, type 1) | `:354` | `+ 1000` | 10 pt | ✅ clean |
| 8 | Whale pass (100-level bundle, type 3) | `:356` | `+ 4000` | 40 pt | ✅ clean |
| 9 | Curse penalty | `:363-366` | `- curse * 100` (floored at 0) | `- curse` pt | ✅ clean (`×100`) |

**Verdict: every additive bps contributor is a clean multiple of 100 EXCEPT the quest-streak leg (`:335`, `× 50`).** The quest-streak leg is the sole place ÷100 is not exact, and therefore the sole place the floor rule (D-02) applies.

**`DEITY_PASS_ACTIVITY_BONUS_BPS` explicit confirmation:** the constant is declared `uint16 internal constant DEITY_PASS_ACTIVITY_BONUS_BPS = 8000;` at `contracts/storage/DegenerusGameStorage.sol:135`. `8000 mod 100 == 0`, so it converts cleanly to **80 points** and needs no special conversion rule. (CONTEXT.md's executor checklist flagged "if not a multiple of 100, it needs its own conversion rule" — confirmed it IS a multiple of 100, so no special rule is required.)

**Pass floors are already point-domain (no conversion):** `PASS_STREAK_FLOOR_POINTS = 50` (`DegenerusGameStorage.sol:144`) and `PASS_MINT_COUNT_FLOOR_POINTS = 25` (`:147`) are floor values applied to `streakPoints` / `mintCountPoints` **before** the `× 100` (`:322-326`). They are already point-domain values (50 / 25), not bps. They require **NO conversion** — they continue to floor the point-domain `streakPoints` / `mintCountPoints` directly.

### D-02 — The quest-streak floor rule: `floor(questStreak / 2)`

The quest streak is the **sole sub-point contributor**: at `:335` it adds `questStreak × 50` bps = **0.5 pt per quest**. The locked conversion to the point domain is:

> **quest-streak point contribution = `floor(questStreak / 2)`**

That is: **1 point per 2 quests**, dropping the trailing 0.5 pt at odd streak counts (an odd `questStreak` loses its final half-point). This is the **only place precision is intentionally lost** in the whole-point representation.

**USER selection rationale (D-02):** `floor(questStreak / 2)` was chosen by the USER over (a) round-half-up and (b) keeping a half-point internal unit. It matches the design seed's "floor the streak contribution." The trailing half-point loss at odd streak counts is the documented, accepted boundary (its consumer-outcome impact is bounded in DESIGN-04 / D-09, proven in plan 03).

**Equivalence to the bps leg:** `floor(questStreak / 2) == floor((questStreak × 50) / 100)`. The point-domain floor is exactly the integer ÷100 of the bps leg — i.e. it is the natural point representation of the existing sub-point contribution, not a new rounding policy layered on top.

### D-03 — The point cap: 655 points

The hard cap `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` (`contracts/storage/DegenerusGameStorage.sol:141`) becomes a **point cap of `floor(65534 / 100) = 655` points**.

Arithmetic: `65534 / 100 = 655.34 → floor = 655`. (The old `65534` was the uint16-exact bps ceiling — see the sentinel justification below; `655` is the natural point ceiling.)

**`Sub.score` stamp stays `uint16`:** the frozen per-sub stamp field `Sub.score` (the activity score snapshotted at deposit, `DegenerusGameStorage.sol:2127` — `score(16)` in the 40-bit per-sub stamp) **stays uint16**. The point-cap maximum of 655 fits uint16 (max 65,535) with vast headroom. The 40-bit stamp slot (`score(16) + amount(24)`) is otherwise exactly packed, so narrowing `score` below uint16 nets nothing (no field can grow into the freed bits without re-derivation, and the IMPL repack — D-07 — is net-zero by construction). Lock: `Sub.score` remains uint16.

#### D-03 — sDGNRS sentinel headroom check (the old `65534` reason, re-checked in the point domain)

The old `65534` cap value existed for a specific cross-contract reason, re-confirmed at the frozen source:

- `sDGNRS.sol:1138-1141` snapshots the activity score as **`uint16(game.playerActivityScore(beneficiary)) + 1`**, storing it in `claim.activityScore`, with **`0` reserved as the unset sentinel** (`if (claim.activityScore == 0)` at `:1139` = "not yet set").
- Therefore the snapshot must satisfy `score + 1 ≤ uint16 max (65535)`, i.e. `score ≤ 65534`. That is exactly why the bps cap was set to `65534` (one below uint16 max), as documented at `DegenerusGameStorage.sol:137-140`.

**Point-domain re-check:** at the point cap, the maximum stored snapshot is `655 + 1 = 656`, which fits uint16 with enormous margin (656 ≪ 65535). **The point cap CANNOT collide with the unset-sentinel encoding** — the `+1` sentinel constraint that motivated `65534` is satisfied with vast headroom in the point domain. This carries threat-register item **T-435-02** (point cap vs sDGNRS sentinel) to a mitigated state: the cap derivation explicitly includes the `+1` sentinel check.

**[ANCHOR NOTE]** CONTEXT.md / plan cited the sentinel at `sDGNRS.sol:1135-1142`; the exact lines on the frozen tree are `:1138-1141` (the `if (claim.activityScore == 0)` guard at `:1139`, the `uint16(...) + 1` write at `:1140`). The cited range contains the true anchor; corrected for precision.

#### D-03 — Claude's-discretion (deferred to 436 IMPL)

Per CONTEXT.md, the exact constant naming and the precise source location where the floor + point cap live are **436 IMPL detail**, not locked here. This design-lock locks only the *values and the rule* (1 pt = 100 bps; `floor(questStreak / 2)`; cap = 655 pt; `Sub.score` stays uint16); IMPL picks the cleanest constant names and placement.

### D-01/D-02/D-03 — Locked outputs (for 436 IMPL)

| Lock | Value / rule | Source anchor |
|------|--------------|---------------|
| Point unit | 1 point = 100 bps; score = bps ÷ 100 | `MintStreakUtils:282-372` |
| Quest-streak floor | `floor(questStreak / 2)` (sole sub-point leg, `:335`) | `MintStreakUtils:335` |
| Point cap | `floor(65534 / 100) = 655` points | `Storage:141` |
| Sentinel headroom | `655 + 1 = 656` fits uint16 (no collision with `0` unset) | `sDGNRS.sol:1138-1141` |
| `Sub.score` width | stays uint16 | `Storage:2127` |
| Pass floors | already point-domain (50 / 25), no conversion | `Storage:144,147` |
| Deity pass bonus | 8000 bps → 80 pt (multiple of 100, no special rule) | `Storage:135` |

---

## DESIGN-02 — Single Exact Integer Streak Path + Pre-Streak-Cap Rework

Records the USER-locked decisions **D-04** (widen the latch, drop both band-aids) and **D-05** (single exact integer path). Requirements: **DESIGN-02** (this plan locks the design; STREAK-01/02 in 436 implement it).

### D-04 — The grievance: a width mismatch papered over twice

The carried-in pre-streak handling currently spans two widths and patches the mismatch in two places:

1. **Run-start snapshot truncation.** At afking run start, `beginAfking` returns the player's gap-synced manual quest streak (`DegenerusQuests.beginAfking:501-511`, returning `state.streak`, where `PlayerQuestState.streak` is **uint16**, `DegenerusQuests.sol:281`). The Game then snapshots it into `Sub.subStreakLatch` (**uint8**, `DegenerusGameStorage.sol:2244`) via `_setStreakBase`, which **clamps to 255** (`_setStreakBase:2259-2261`: `sub.subStreakLatch = value > 255 ? 255 : uint8(value)`). A high-streak player (manual streak > 255) is therefore **silently truncated** for the afking run's activity score — the run reads a 255-capped base instead of the true carried-in streak.

2. **Finalize floor-hack compensation.** On any sub-ending path, `_finalizeAfking` (`GameAfkingModule.sol:1066-1081`) computes `earned = _streakBaseOf(sub) + (afkCoveredThroughDay - afkingStartDay)` and hands it to `DegenerusQuests.finalizeAfking`. That function contains a **floor-hack** (`DegenerusQuests.sol:546-551`) that reaches back into the dormant uint16 `state.streak` (held untouched while afking) to restore it on exit:

   ```solidity
   // (DegenerusQuests.sol:546-551, frozen baseline)
   uint16 preRun = state.streak;
   if (finalStreak != 0 && finalStreak < preRun) finalStreak = preRun;
   state.streak = finalStreak > type(uint16).max ? type(uint16).max : uint16(finalStreak);
   ```

   The comment at `:546-548` states the reason explicitly: *"The afking run base is uint8-clamped at 255, so a short run can rebuild a streak below the pre-run snapshot still held in state.streak (dormant while afking). Floor a surviving streak at that snapshot so handing control back never lowers it."*

**The USER's framing:** the dislike is precisely this **uint8/255 clamp + the compensating finalize floor-hack** — a width mismatch (uint16 manual streak vs uint8 latch) papered over twice. The locked fix removes both by matching the latch width to the manual streak.

**[ANCHOR NOTE — frozen-source corrections vs CONTEXT.md / plan interfaces]:**
- `beginAfking` return **type** is `uint24 streak` (`DegenerusQuests.sol:504`), sourced from `state.streak` (the underlying **uint16** field at `:281`). The plan interfaces said "returns state.streak (uint16)" — the underlying field is uint16; the return cast is uint24. Either way the value originates from the uint16 manual streak, so the symmetry argument (match the latch to the manual uint16 streak) holds.
- The finalize floor-hack at `:546-551` guards `finalStreak != 0 && finalStreak < preRun` (the plan's interfaces abbreviated it to `if (finalStreak < preRun)`); the live code also requires `finalStreak != 0` so a genuine decay-to-0 is not floored back up. The block to DELETE is exactly `:549-550` (the `preRun` read + the `if (...) finalStreak = preRun;`); the type-clamp at `:551` is a separate concern (see the actor walk, point 6).
- `Sub.subStreakLatch` is the **full byte** (8 bits, `SUB_STREAK_MASK = 0xff` at `:2251`, mask op at `_streakBaseOf:2254-2256`). One stale comment at `Storage:2144` describes `streakAtAfkingStart (bits 0-6)` (7 bits) — the live code masks the full byte (8 bits), so 8 bits is the effective width. The widening edit must update that stale comment too.

### D-04 — The locked fix: widen the latch, drop the 255 clamp, delete the floor-hack

**Decision:** widen `Sub.subStreakLatch` **uint8 → uint16**, consuming the **8 bits freed by the DESIGN-03 `pendingFlip` narrowing** (uint32 → uint24; see plan 02 / D-06 / D-07 for the slot arithmetic). The latch then matches the manual `state.streak` width (uint16), the carried-in pre-streak snapshots **exactly** (no truncation), and the compensating floor-hack is no longer needed.

**Freed-bits cross-reference:** the 8 bits are NOT new slot space — they come from narrowing `Sub.pendingFlip` uint32 → uint24 (D-06), keeping the accumulator at exactly `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72` bits and the `Sub` struct at exactly one 256-bit slot, 0 free (D-07). **Plan 02 owns the slot arithmetic, EIP-170 re-check, and the layout-golden recapture.** This is recorded here only as the source of the latch's extra 8 bits (threat-register item **T-435-03**).

**Exact edit surface for 436 IMPL** (each a per-symbol edit on the frozen baseline):

| # | Edit | Symbol | Anchor | Change |
|---|------|--------|--------|--------|
| (a) | Field declaration | `Sub.subStreakLatch` | `DegenerusGameStorage.sol:2244` | `uint8` → `uint16` |
| (b) | Mask widening | `SUB_STREAK_MASK` | `:2251` | `0xff` → `0xffff` |
| (c) | Getter return type | `_streakBaseOf` | `:2254-2256` | returns `uint16` (was `uint8`); `& SUB_STREAK_MASK` now masks 16 bits |
| (d) | Setter clamp DROP | `_setStreakBase` | `:2259-2261` | drop the `value > 255 ? 255 :` clamp; snapshot exactly into the full uint16 (a uint16-range clamp may stay for type safety since `state.streak` is itself uint16 — IMPL discretion, but the **255** clamp is removed) |
| (e) | Cast holds | `_afkingStreak` | `:2271` | `uint32(_streakBaseOf(sub))` cast from uint16 → uint32 continues to hold (uint16 ⊂ uint32); no change required beyond (c)'s return type |
| (f) | Floor-hack DELETE | `finalizeAfking` floor-hack | `DegenerusQuests.sol:546-551` | **DELETE** the `uint16 preRun = state.streak; if (finalStreak != 0 && finalStreak < preRun) finalStreak = preRun;` block (`:549-550`) and its explanatory comment (`:546-548`); the latch now carries the pre-run snapshot exactly, so `finalStreak` (= true base + funded days) already reflects the real streak and needs no restore. The decay logic (`:543-545`) and the final uint16 assignment (`:551`, retained as plain `state.streak = uint16(finalStreak)` with its safety clamp) stay. |

Also update the stale `bits 0-6` comment at `Storage:2144` and the `0..255` / `Clamped at 255` comments at `:2238-2250` to the new uint16 width (comment-only, but part of the same edit).

### D-05 — The single exact integer path

With the full-width (uint16) latch, the manual quest streak **and** the afking-run streak base feed `_playerActivityScore` through **one exact integer path** — there is no fractional / bps intermediate anywhere in the streak combine. The quest-streak value that reaches `_playerActivityScoreAt` (`MintStreakUtils:335`) is a clean integer; the floor (D-02) is applied once, at the bps→point conversion of that single leg, not scattered across the streak combine.

Consistency confirmations (per CONTEXT.md D-05):
- **`DegenerusQuests` streak source** stays the uint16 `PlayerQuestState.streak` (`:281`), now symmetric with the uint16 latch — no width mismatch remains.
- **The `pendingFlip` accrual note** at `DegenerusQuests.sol:1779` (the per-delivered-day `pendingFlip` accrual; while afking, slot completions are streak-neutral and the slot-0 reward is the per-delivered-day accrual) stays consistent with the new path: the streak-width change does not touch the accrual semantics, and `pendingFlip`'s own narrowing (D-06) is a separate slot field in the same accumulator.

### D-04/D-05 — Actor / game-theory walk (semantics-preserving)

The walk below proves the rework changes **exactly one** observable behaviour — removing the prior silent 255-truncation (and its compensating restore) — and preserves all other streak semantics. This carries threat-register item **T-435-03** to mitigated.

1. **Non-afker.** `_effectiveQuestStreak` returns the manual streak unchanged: `(uint32 manualStreak, bool afking) = quests.effectiveBaseStreakAndAfking(player); if (!afking) return manualStreak;` (`DegenerusGameStorage.sol:2300-2301`). A non-afking player never touches the latch — **unchanged.**
2. **Live afking sub.** `_effectiveQuestStreak` reads the compute-on-read `_liveAfkingStreak` (`:2302`), which returns `_afkingStreak(sub, currentDay) = uint32(_streakBaseOf(sub)) + uint32(covered - afkingStartDay)` (`:2268-2271`). The base now comes from a uint16 latch instead of a uint8 latch, but the **formula is identical** — only the base can now exceed 255 (the truncation that used to happen no longer does). **Behaviour-preserving except the truncation removal.**
3. **afking-XOR-manual exclusivity.** `_effectiveQuestStreak` (`:2295-2304`) drives the score from exactly **one** source at a time: a non-afker (or a lapsed run) reads the manual streak; a live afking sub reads the compute-on-read. Only one source ever feeds the score. The XOR exclusivity is **preserved** — the latch widening does not add a second concurrent source.
4. **Decay-on-read.** `_afkingStreak` returns 0 when `currentDay == 0 || covered + 1 < currentDay` (`:2270`) — miss one full funded day and the afking streak is gone. This guard is **unchanged**; the latch width does not affect the decay condition.
5. **In-run `+1` secondary bump & run-start writes.** The in-run secondary bump `_setStreakBase(s, _streakBaseOf(s) + 1)` (`GameAfkingModule.sol:1734`, `recordAfkingSecondary`) and the run-start re-base / 0-on-lapse writes (`_setStreakBase(s, snap)` at `:521/523/533/555`, `_setStreakBase(s, 0)` at `:573`, and `_finalizeAfking`'s `_setStreakBase(sub, 0)` at `:1081`) are **unchanged in behaviour** — only the field width changes. The `+1` bump previously saturated at 255 (per its `:1726` comment); with the uint16 latch it saturates at 65535 instead, which is consistent with the wider carried-in base and far past where the activity-score point cap (655) makes any value matter.
6. **High-streak player (manual streak > 255) — the ONLY behaviour change.** Before: the run-start snapshot truncated the carried-in streak to 255 (`_setStreakBase:2260`), the activity score read a 255-capped base mid-run, and the finalize floor-hack (`DegenerusQuests.sol:549-550`) restored `state.streak` to the pre-run snapshot on exit so the manual streak was not permanently lowered. After: the snapshot carries the **exact** base into the run (no 255 cap), the activity score reads the true base mid-run, and on finalize `finalStreak` (= exact base + funded days) is handed back directly with **no floor-hack** — the restore is unnecessary because nothing was ever truncated. **Net: the only behaviour change is removing the prior silent 255-truncation (mid-run under-scoring) and its compensating exit-restore.** For any player with manual streak ≤ 255, the before/after behaviour is byte-identical (the clamp never bound, the floor-hack's `finalStreak < preRun` either never fired or fired identically). Note the activity-score point cap (655) already bounds the *score* contribution; this rework removes a *streak-base* truncation upstream of that cap, which only matters where the carried-in streak exceeds 255 — a high-engagement edge that the USER wants represented exactly rather than silently capped.

### D-04/D-05 — Locked outputs (for 436 IMPL)

| Lock | Value / rule | Source anchor |
|------|--------------|---------------|
| Latch width | `Sub.subStreakLatch` uint8 → uint16 | `Storage:2244` |
| Mask | `SUB_STREAK_MASK` 0xff → 0xffff | `Storage:2251` |
| Getter | `_streakBaseOf` returns uint16 | `Storage:2254-2256` |
| Setter | drop the `> 255 → 255` clamp | `Storage:2259-2261` |
| Floor-hack | DELETE the `preRun` restore block | `DegenerusQuests.sol:546-551` |
| Freed bits source | 8 bits from `pendingFlip` uint32 → uint24 (D-06/plan 02) | `Storage:2237` |
| `_effectiveQuestStreak` | afking-XOR-manual semantics PRESERVED | `Storage:2295-2304` |
| Behaviour delta | only the silent 255-truncation (+ its exit-restore) removed | walk point 6 |

---
