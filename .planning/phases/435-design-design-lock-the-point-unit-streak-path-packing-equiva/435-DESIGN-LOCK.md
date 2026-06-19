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

## DESIGN-03 — pendingFlip Narrowing + Accumulator Repack

Records the USER-locked decisions **D-06** (`Sub.pendingFlip` uint32→uint24 + clamp re-pin), **D-07** (72-bit accumulator repack, `Sub` stays exactly one 256-bit slot, 0 free), and **D-08** (`lootboxRngPendingFlip` confirmed distinct/out of scope). Requirement: **DESIGN-03** (this plan locks the design; PACK-01 in 436 implements it, 437/438 verify EIP-170 + layout golden). This section owns the slot arithmetic, EIP-170 re-check flag, and the layout-golden recapture flag that DESIGN-02's latch widening cross-references for its 8 freed bits.

### D-06 — `Sub.pendingFlip` narrows uint32 → uint24, clamp re-pinned to the uint24 ceiling

**Decision:** `Sub.pendingFlip` (`DegenerusGameStorage.sol:2237`) narrows **uint32 → uint24**, and its saturating accrue-clamp is re-pinned from the current `100_000_000` (100M whole FLIP) constant to the **uint24 ceiling `16,777,215` (`2^24 − 1` ≈ 16.7M whole FLIP)**. The narrowing frees **exactly 8 bits** in the accumulator — the bits DESIGN-02 / D-04 consume for the `subStreakLatch` uint8→uint16 widening.

**`pendingFlip` semantics (re-confirmed at source):** it is the per-sub running CLAIMABLE FLIP balance, **whole FLIP** (the accrue divides by `1 ether` before the `+=`, `GameAfkingModule.sol:859, :926`), accrued per delivered day as the slot-0 quest reward (every mode) plus the ticket-mode 10%/20% buyer bonus. Paid out only by the player-pull `claimAfkingFlip` and zeroed at settle (`_settlePendingFlip:1100`). It is **not on the solvency path**: the clamp can only ever UNDER-credit, never mint excess backing.

**Why uint24 (~16.7M whole FLIP) is safe against the realistic per-sub bank.** The accrued value is whole FLIP per delivered day from two contributors:
- the slot-0 quest reward `QUEST_SLOT0_REWARD / 1 ether` (whole FLIP, every mode, per delivered day, `GameAfkingModule.sol:925-926`); and
- the ticket-mode buyer bonus `bonusWhole = bonusBase / 1 ether` (10%, doubling to 20% on ≥10-ticket buys, per buy, `:859-863`).

For the clamp to ever bind, a single sub's *unclaimed* `pendingFlip` would have to reach **16.7M whole FLIP** — i.e. the player accrues for years/decades of delivered days without ever calling the `claimAfkingFlip` pull, while running a reinvest-whale-sized daily buy. That is the same pathological reinvest-whale shape the current 100M clamp already exists to catch; the only change is the binding ceiling moves down from 100M to 16.7M, both far above any realistic per-sub claimable bank. The outcome at the (already pathological) clamp is identical in *kind*: a saturating UNDER-credit off the solvency path — **not** an overflow, and not a new failure mode. The 100M→16.7M move only changes *where* the already-benign saturation begins for a player who never claims; it cannot affect any sub whose unclaimed bank stays under 16.7M whole FLIP, which is every realistic sub.

**Saturation, not overflow (asserted; handed to 437 TST-02).** The clamp is a `min(newOwed, ceiling)` *before* the `uint24(...)` cast, so the cast input is provably ≤ `2^24 − 1` and the narrowed write never truncates/wraps. The accrue is `newOwed = uint256(sub.pendingFlip) + delta; if (newOwed > CEIL) newOwed = CEIL; sub.pendingFlip = uint24(newOwed);` — identical structure to today, only the type and the `CEIL` constant change. 437 TST-02 owns the property test that the clamp saturates (never wraps) at the new ceiling.

**Exact accrue/clamp/settle edit surface for 436 IMPL** (each a per-symbol edit on the frozen baseline):

| # | Edit | Symbol / site | Anchor | Change |
|---|------|---------------|--------|--------|
| (a) | Field declaration | `Sub.pendingFlip` | `DegenerusGameStorage.sol:2237` | `uint32` → `uint24` |
| (b) | Ticket buyer-bonus accrue clamp | the `newOwed`/`uint32(newOwed)` block | `GameAfkingModule.sol:861-863` | clamp constant `100_000_000` → uint24 ceiling `16_777_215`; cast `uint32(newOwed)` → `uint24(newOwed)` |
| (c) | Slot-0 quest-reward accrue clamp | the `newOwed`/`uint32(newOwed)` block | `GameAfkingModule.sol:925-928` | clamp constant `100_000_000` → uint24 ceiling `16_777_215`; cast `uint32(newOwed)` → `uint24(newOwed)` |
| (d) | Settle read/zero | `_settlePendingFlip` | `GameAfkingModule.sol:1097-1100` | `uint256(s.pendingFlip)` widen-back from uint24 holds unchanged (uint24 ⊂ uint256); the `s.pendingFlip = 0` zero-write still fits — **no logic change required beyond (a)'s type**; only the comment "Same uint32 + 100M…" needs the new width/ceiling |
| (e) | Slot doc-comment + field-section comments | accumulator doc | `DegenerusGameStorage.sol:2129, :2154-2162, :2230-2237` | update `pendingFlip(32)` → `pendingFlip(24)`, the `uint32 with a 100M-whole-FLIP` notes → `uint24 with a ~16.7M (2^24−1)` notes (comment-only, part of the same edit) |

**[ANCHOR NOTE]** The CONTEXT.md/plan interfaces cited the clamp sites as `sub.pendingFlip = uint32(newOwed)` at `:861-863` and `:925-928`; on the frozen `e9a5fc24` tree the actual blocks span `:861-863` (ticket buyer-bonus: `newOwed` at `:861`, the `> 100_000_000` clamp at `:862`, the `uint32(newOwed)` write at `:863`) and `:925-929` (slot-0 reward: `newOwed` at `:925-926`, the clamp at `:927`, the `uint32(newOwed)` write at `:928`). The settle is `_settlePendingFlip` (`:1097-1100`), reading `uint256(s.pendingFlip)` at `:1098` and zeroing at `:1100`. The cited ranges contain the true anchors; corrected for precision.

**[ANCHOR NOTE]** `affiliateBase` (the sibling uint32 accumulator field, `:2229`) shares the same 100M-whole-FLIP clamp idiom (`GameAfkingModule.sol:920-922`) but is **NOT** in scope for narrowing — D-06 narrows only `pendingFlip`. `affiliateBase` stays uint32 (its 32 bits are unchanged in the repack; see D-07). Its clamp constant is unaffected.

**D-06 — Claude's-discretion (deferred to 436 IMPL):** per CONTEXT.md, the precise uint24 clamp constant value — the exact `2^24 − 1 = 16,777,215` ceiling vs a rounded `16_700_000`/`~16.7M` — is a 436 pick, justified against the realistic bank. This design-lock locks the *width* (uint24) and the *rule* (the clamp re-pins to the uint24 ceiling so the cast never wraps); IMPL picks the exact constant value and its name. The recommended value is the exact `2^24 − 1 = 16,777,215` so the clamp ceiling is the type ceiling (the cast becomes provably lossless by construction), but any value ≤ `2^24 − 1` that is comfortably above the realistic bank satisfies the lock.

### D-07 — The repacked 72-bit accumulator; `Sub` stays exactly one 256-bit slot, 0 free

**Decision (the net-zero repack):**

```
CURRENT accumulator (72b):  affiliateBase(32) + pendingFlip(32) + subStreakLatch(8)   = 72
NEW     accumulator (72b):  affiliateBase(32) + pendingFlip(24) + subStreakLatch(16)  = 72
                                                          -8                  +8        net 0
```

`pendingFlip` gives up 8 bits (D-06: 32→24); `subStreakLatch` takes them (D-02/D-04: 8→16); `affiliateBase` is untouched (32). The accumulator stays **exactly 72 bits**, so the whole `Sub` record stays **exactly one 256-bit slot, 0 free** — no new cold slot, no field value-range violated (every narrowed/widened field's new width still holds its locked range: `pendingFlip` ≤ 16.7M < `2^24`, `subStreakLatch` ≤ 65,535 = `2^16 − 1`, comfortably above the streak values that matter under the 655-point activity cap), and no slot collision (the disjoint per-buy accrue write into the warm slot is unchanged in *which* fields it touches).

#### D-07 — Full `Sub`-struct field-width table (re-derived from source declarations, BEFORE + AFTER)

Re-derived by **totalling the actual field declarations** at `DegenerusGameStorage.sol:2169-2245` (not trusting the comments — see the reconciliation below). Each group's bit-sum is shown; the four groups total 256 in both states.

**BEFORE (frozen `e9a5fc24`):**

| Group | Fields (declared widths) | Bits |
|-------|--------------------------|------|
| config | `dailyQuantity` u8(8) + `validThroughLevel` u24(24) + `reinvestPct` u8(8) + `flags` u8(8) | **48** |
| per-sub stamp | `score` u16(16) + `amount` u24(24) | **40** |
| markers | `lastAutoBoughtDay` u24(24) + `lastOpenedDay` u24(24) + `afkCoveredThroughDay` u24(24) + `afkingStartDay` u24(24) | **96** |
| accumulator | `affiliateBase` u32(32) + `pendingFlip` u32(32) + `subStreakLatch` u8(8) | **72** |
| **TOTAL** | | **256 (0 free)** |

**AFTER (the 436 repack):**

| Group | Fields (declared widths) | Bits |
|-------|--------------------------|------|
| config | `dailyQuantity` u8(8) + `validThroughLevel` u24(24) + `reinvestPct` u8(8) + `flags` u8(8) | **48** |
| per-sub stamp | `score` u16(16) + `amount` u24(24) | **40** |
| markers | `lastAutoBoughtDay` u24(24) + `lastOpenedDay` u24(24) + `afkCoveredThroughDay` u24(24) + `afkingStartDay` u24(24) | **96** |
| accumulator | `affiliateBase` u32(32) + **`pendingFlip` u24(24)** + **`subStreakLatch` u16(16)** | **72** |
| **TOTAL** | | **256 (0 free)** |

`48 + 40 + 96 + 72 = 256` in **both** states. The only changed cells are the two bolded accumulator fields, whose widths sum unchanged (24 + 16 = 32 + 8 = 40 over the two fields). **The repack is net-zero by construction: no new slot, no shrink below 256, no collision.**

#### D-07 — [ANCHOR NOTE] Comment-vs-field-width reconciliations (source is ground truth)

Re-deriving the widths from the field declarations surfaced **three internal comment discrepancies** in the frozen source. The *field declarations* are ground truth and the *slot arithmetic above is computed from them*; the discrepancies are comment-only and the 436 edit should fix the ones it touches:

1. **Slot doc-comment `config (40b)` is wrong → should be `config (48b)`.** The doc-comment at `:2126` says `config (40b)` but the field section header at `:2170` says `--- config (48 bits) ---` and the declared fields sum `8+24+8+8 = 48`. **48 is correct.** (The CONTEXT.md/plan interfaces echoed the doc-comment's `config (40b)` — likewise imprecise; the declared sum is 48.)
2. **Field-section header `per-sub stamp (48 bits)` is wrong → should be `(40b)`.** The header at `:2182` says `--- per-sub stamp (48 bits) ---` but the declared fields sum `16+24 = 40`, and the slot doc-comment at `:2127` correctly says `per-sub stamp (40b)`. **40 is correct.**
3. **Field-section header `markers (72 bits)` is wrong → should be `(96b)`.** The header at `:2194` says `--- markers (72 bits) ---` but the four declared uint24 day markers sum `24×4 = 96`, and the slot doc-comment at `:2128` correctly says `markers (96b)`. **96 is correct.**

These three off-by comments happen to be *internally self-cancelling* in the doc-comment (40+40+96 ≠ 256 in the doc-comment's own group labels would be 248; but the doc-comment's own labels are config(40, wrong)+stamp(40, right)+markers(96, right)+accumulator(72, right) = 248, which is itself inconsistent — the **declared fields**, not either comment, are the only reliable total, and they sum to 256). The accumulator group is labelled correctly in both comment locations (`72b`). **The 256-bit-exact claim holds on the field declarations alone**; 436 should correct the `config (40b)` doc-comment to `(48b)` and the field-section `per-sub stamp (48 bits)`/`markers (72 bits)` headers to `(40b)`/`(96b)` while it is editing the struct (comment-only).

Also (already flagged in DESIGN-02): the `subStreakLatch` field comment (`:2238-2250`, `0..255` / `Clamped at 255` / `bits 0-6`) widens to uint16 in the same 436 edit.

#### D-07 — EIP-170 re-check + layout-golden recapture (flags, handled in 438)

- **EIP-170 deployed-bytecode ceiling.** The repack is a pure width swap inside one already-allocated slot; it does not add storage slots and is not expected to grow `DegenerusGame` deployed bytecode materially (the cast-width and clamp-constant changes are register-level). **EIP-170 is re-checked in 436/PACK-01** (the Game is perpetually near the 24,576-byte ceiling, so any IMPL diff re-measures). This design-lock asserts the *expectation* (net-neutral bytecode); 436 confirms it empirically and 438 re-attests.
- **Storage-layout golden (the v68 MECH-02 `forge inspect` oracle).** The field-width move WILL change the `forge inspect <c> storage-layout` snapshot for `Sub` (the `pendingFlip`/`subStreakLatch` offsets/widths shift within the slot). **That recapture is the EXPECTED NEW GOLDEN, handled in 438 REAUDIT-01 — NOT a layout drift.** The slot index of `Sub` is unchanged (still one slot); only the intra-slot field offsets/types update. 438 recaptures the golden against the repacked subject and re-attests it matches the locked D-07 layout.

### D-08 — `lootboxRngPendingFlip` (uint40) is a SEPARATE, out-of-scope field

**Confirmed distinct from `Sub.pendingFlip`.** `lootboxRngPendingFlip` is a field of the **global** `lootboxRngPacked` uint256 (`DegenerusGameStorage.sol:1530`), declared in its layout comment at **`:1525`** as `[bits 184:223] lootboxRngPendingFlip uint40 (scaled /1e18, 1 FLIP res, max ~1.1T FLIP)`. It is **NOT narrowed** (D-08).

Distinguishing facts (recorded so 436 cannot narrow the wrong field):

| Facet | `Sub.pendingFlip` (in scope, D-06) | `lootboxRngPendingFlip` (out of scope, D-08) |
|-------|-----------------------------------|----------------------------------------------|
| Container | per-sub `Sub` struct accumulator (`:2237`) | the global `lootboxRngPacked` uint256 (`:1530`), bits [184:223] |
| Type | uint32 → **uint24** (this plan) | **uint40** (unchanged) |
| Scaling | whole FLIP (divides by `1 ether` at accrue) | scaled **/1e18** (`max ~1.1T FLIP`) |
| Purpose | per-sub running CLAIMABLE FLIP bank (slot-0 reward + ticket buyer bonus) | the lootbox-RNG pending-FLIP payout state for the fulfill/threshold leg |
| Anchor | `:2237` (struct field) | `:1525` (layout comment) / `:1530` (packed var) |

They share only the substring `pendingFlip` in their names; they are different types, in different storage containers, with different scaling and different purposes. **D-08 = no change to `lootboxRngPendingFlip`.**

**[ANCHOR NOTE]** CONTEXT.md cited `lootboxRngPendingFlip` at `~Storage:1527`; on the frozen `e9a5fc24` tree the layout-comment line for it is `:1525` (the `lootboxRngPacked` var declaration begins at `:1530`). The `~`-prefixed CONTEXT.md anchor was approximate; corrected to the exact `:1525`.

### D-06/D-07/D-08 — Locked outputs (for 436 IMPL)

| Lock | Value / rule | Source anchor |
|------|--------------|---------------|
| `pendingFlip` width | uint32 → uint24 | `Storage:2237` |
| `pendingFlip` clamp | re-pin `100_000_000` → uint24 ceiling `16_777_215` (`2^24 − 1`, ~16.7M) | `GameAfkingModule.sol:862, :927` |
| Accrue/settle casts | `uint32(newOwed)` → `uint24(newOwed)` at `:863`/`:928`; settle read holds | `GameAfkingModule.sol:861-863, :925-928, :1097-1100` |
| New accumulator | `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72` | `Storage:2229-2244` |
| Slot total | exactly **256 bits, 0 free** BEFORE + AFTER (48 + 40 + 96 + 72) | `Storage:2169-2245` |
| Comment fixes | `config (40b)→(48b)`, `per-sub stamp (48 bits)→(40b)`, `markers (72 bits)→(96b)`, `pendingFlip(32)→(24)`, 100M→16.7M notes | `Storage:2126-2128, :2154-2162, :2170/2182/2194, :2230-2237` |
| EIP-170 | re-checked in 436/PACK-01 (expected net-neutral) | — |
| Layout golden | recaptured in 438 REAUDIT-01 as the expected new golden (not drift) | — |
| `lootboxRngPendingFlip` | SEPARATE uint40, **out of scope**, not narrowed (D-08) | `Storage:1525` |

---

## DESIGN-04 — Consumer-Threshold Behaviour-Equivalence

Records the USER-locked decisions **D-09** (accept + document the de-minimis odd-half-point boundary shift; no threshold nudging) and **D-10** (equivalence = scale-invariance of the consumer threshold/interpolation math under ÷100). Requirement: **DESIGN-04** (this section locks the load-bearing correctness argument; POINTS-02 in 436 migrates the thresholds, 438 REAUDIT re-attests).

This is the load-bearing correctness section: it proves that converting the activity score bps→points does not materially shift the Lootbox EV multiplier, the Degenerette ROI, or the Decimator outcome, separates the score-INPUT thresholds that convert from the OUTPUT bps that must NOT, and bounds the single accepted divergence.

### D-04.0 — The two pre-conditions the score guarantees

The proof rests on two facts established in DESIGN-01:

1. **The score is always a multiple of 50 bps** — every additive contributor to `bonusBps` in `_playerActivityScoreAt` is a multiple of 100 *except* the quest-streak leg (`MintStreakUtils:335`, `questStreak × 50`), which is a multiple of 50. So the sum is a multiple of `gcd(100, 50) = 50` bps = **0.5 pt**.
2. **Every contributor except quest-streak is a multiple of 100 bps** (= a whole point). The quest-streak leg is the sole sub-point (0.5-pt-granular) contributor.

Therefore the bps score that reaches every consumer is, before the floor (D-02), always one of `{whole-point, whole-point + 0.5 pt}` — and after the D-02 floor (`floor(questStreak/2)`) it is **always a clean whole point** (a multiple of 100 bps in the old domain). The point domain is exact for the floored score by construction; the only question DESIGN-04 answers is whether the floor of the odd-half-point can shift a consumer outcome (D-09) and whether the threshold/interpolation math is invariant under ÷100 (D-10).

### D-04.1 — Input-vs-output constant inventory

The single most important classification: a constant that the score is **compared against or fed through as a denominator (an input range/threshold anchor)** must convert ÷100 with the score; a constant in a **different output domain (an ROI / EV-multiplier / reward result value)** must NOT convert. Mis-classifying either way breaks the consumer. Re-derived from the frozen `e9a5fc24` source.

#### TABLE A — score-INPUT thresholds that CONVERT ÷100

| Constant | File:line | Current (bps) | New (points) | Role |
|----------|-----------|---------------|--------------|------|
| `ACTIVITY_SCORE_MID_BPS` | `DegenerusGameDegeneretteModule.sol:188` | 7_500 | **75** | Degenerette ROI mid-tier threshold + low-segment denominator |
| `ACTIVITY_SCORE_HIGH_BPS` | `DegenerusGameDegeneretteModule.sol:191` | 25_500 | **255** | Degenerette ROI high-tier threshold + span endpoint |
| `ACTIVITY_SCORE_MAX_BPS` | `DegenerusGameDegeneretteModule.sol:194` | 30_500 | **305** | Degenerette ROI clamp + max threshold + WWXRP denominator |
| `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS` | `DegenerusGameStorage.sol:1553` | 6_000 | **60** | Lootbox EV neutral threshold + low-leg denominator + high-leg pivot |
| `LOOTBOX_EV_ACTIVITY_MAX_BPS` | `DegenerusGameStorage.sol:1555` | 40_000 | **400** | Lootbox EV max threshold + high-leg span endpoint |
| `TERMINAL_DEC_ACTIVITY_CAP_BPS` | `DegenerusGameDecimatorModule.sol:772` | 23_500 | **235** | Decimator score clamp (`:796/:916`) + bucket-reduction denominator (`:1139-1140`) |

All six are the score's own grid — the score is compared to them (`<=`, `>=`, `>` clamps) or divided by them. They convert ÷100 **together with** the score, which is exactly what keeps the comparisons and ratios invariant (D-10).

#### TABLE B — OUTPUT / out-of-domain bps that MUST NOT convert

| Constant | File:line | Value (bps) | Why it is NOT a score input |
|----------|-----------|-------------|-----------------------------|
| `ROI_MIN_BPS` | `DegenerusGameDegeneretteModule.sol:197` | 9_000 | ROI *result* anchor (a return value in the ROI/10000 domain), never compared to the score |
| `ROI_MID_BPS` | `:200` | 9_500 | ROI result anchor |
| `ROI_HIGH_BPS` | `:203` | 9_950 | ROI result anchor |
| `ROI_MAX_BPS` | `:206` | 9_990 | ROI result anchor |
| `WWXRP_HIGH_ROI_BASE_BPS` | `:214` | 9_000 | WWXRP ROI result base anchor |
| `WWXRP_HIGH_ROI_MAX_BPS` | `:217` | 10_990 | WWXRP ROI result max anchor |
| `LOOTBOX_EV_MIN_BPS` | `DegenerusGameStorage.sol:1557` | 9_000 | EV-multiplier *output* anchor (a 0.9x..1.45x multiplier in the /10000 domain) |
| `LOOTBOX_EV_NEUTRAL_BPS` | `:1559` | 10_000 | EV-multiplier output anchor (1.0x) |
| `LOOTBOX_EV_MAX_BPS` | `:1561` | 14_500 | EV-multiplier output anchor (1.45x) |
| `DEGEN_DGNRS_7/8/9_BPS` | `DegenerusGameDegeneretteModule.sol` (`_awardDegeneretteDgnrs`) | (reward bps) | sDGNRS reward fraction in the reward/10000 domain; keyed on the score *tier* `s`, not the raw score; not a score input |
| `BPS_DENOMINATOR` | `DegenerusGameDecimatorModule.sol:104` | 10_000 | the multiplier denominator (`/10000`), an output-domain divisor, not a score range |

None of these is ever compared to the score or used as a *score* denominator; each lives in the ROI / EV-multiplier / reward / multiplier-base output domain. Converting any of them ÷100 would corrupt that output by 100×.

#### The "40000" disambiguation (carries threat-register item T-435-08)

The roadmap's success-criterion phrase **"Lootbox EV-cap 40000"** is the score-INPUT anchor `LOOTBOX_EV_ACTIVITY_MAX_BPS` (`DegenerusGameStorage.sol:1555`, TABLE A) → converts to **400**. A coincidentally-equal **"40000"** appears in a comment at `DegenerusGameLootboxModule.sol:304` (`E[largeFlipBps] = 0.8*lowMean + 0.2*highMean = 40000`) — that is the **derived presale-box FLIP-band EV mean** (a *different* quantity, in the box-payout-bps domain, with no relation to the activity score). **IGNORE it; do not convert it; it is not a score anchor.** Re-confirmed at source: `:304` is a `// E[largeFlipBps] = ... = 40000` band-recentering comment above `PRESALE_BOX_FLIP_LOW_BASE_BPS` — there is no constant named `40000` there and the comment must not be touched by the threshold migration.

### D-04.2 — Per-consumer scale-invariance proof (D-10)

The general argument: every score-driven threshold consumer computes either a **comparison** (`score </<=/>=/> anchor_in`) or a **ratio** of the form `(score − anchor_in_lo) · K / (anchor_in_hi − anchor_in_lo)` (or `score · K / anchor_in` for a single-anchor denominator), where `K` is built only from OUTPUT anchors (TABLE B). Define `s' = score/100`, `a' = anchor_in/100` (both exact integers because the score and TABLE-A anchors are all clean multiples of 100 — the anchors trivially, the floored score by D-02). Then:

- **Comparisons are invariant:** `score ⟂ anchor_in ⟺ s' ⟂ a'` for `⟂ ∈ {<, <=, >=, >}` because dividing both sides of an integer comparison by the same positive constant 100 preserves the order (and both sides are exact multiples of 100, so no rounding intervenes). Every clamp/branch select therefore picks the identical leg.
- **Ratios are invariant:** `(score − anchor_in_lo)·K / (anchor_in_hi − anchor_in_lo) = (100s' − 100a'_lo)·K / (100a'_hi − 100a'_lo) = (s' − a'_lo)·K / (a'_hi − a'_lo)` — the factor 100 cancels top and bottom *before* the integer division. The OUTPUT anchors `K` are untouched. For a score that is a clean whole point the numerator `(s' − a'_lo)·K` and denominator `(a'_hi − a'_lo)` are the same integers in both domains, so the floored integer quotient is **bit-identical**. (This is the cancellation that makes ÷100 free for clean scores; the sole exception — the half-point input — is D-04.3.)

Applied to each of the three consumers:

#### (1) Lootbox EV multiplier — `_lootboxEvMultiplierFromScore` (`DegenerusGameStorage.sol:1633-1654`)

Three branches, re-confirmed at source:

- **Low leg** (`score <= NEUTRAL`, `:1636-1640`): `EV_MIN + score·(EV_NEUTRAL − EV_MIN) / EV_ACTIVITY_NEUTRAL`. Here `K = EV_NEUTRAL − EV_MIN = 1000` (OUTPUT anchors, unchanged) and the denominator `EV_ACTIVITY_NEUTRAL` is the input anchor `6000→60`. Both `score` and `6000` divide by 100 → `score·1000/6000 = s'·1000/60`. **Invariant.** Worked: score 3000 bps (30 pt) → `9000 + 3000·1000/6000 = 9000 + 500 = 9500`; points → `9000 + 30·1000/60 = 9000 + 500 = 9500`. Identical.
- **Max clamp** (`score >= MAX`, `:1643-1644`): returns `EV_MAX` (output anchor, unchanged). The comparison `score >= 40000 ⟺ s' >= 400` is invariant. **Invariant.**
- **High leg** (`NEUTRAL < score < MAX`, `:1648-1653`): `excess = score − EV_ACTIVITY_NEUTRAL`; `maxExcess = EV_ACTIVITY_MAX − EV_ACTIVITY_NEUTRAL`; `EV_NEUTRAL + excess·(EV_MAX − EV_NEUTRAL)/maxExcess`. Both `excess` and `maxExcess` are differences of values that each divide by 100 → both divide by 100 → ratio invariant; `K = EV_MAX − EV_NEUTRAL = 4500` (output, unchanged). **Invariant.** Worked: score 23000 bps (230 pt): `excess = 23000−6000 = 17000`, `maxExcess = 40000−6000 = 34000` → `10000 + 17000·4500/34000 = 10000 + 2250 = 12250`; points: `excess = 230−60 = 170`, `maxExcess = 400−60 = 340` → `10000 + 170·4500/340 = 10000 + 2250 = 12250`. Identical.

#### (2) Degenerette ROI — `_roiBpsFromScore` (`DegenerusGameDegeneretteModule.sol:1141-1170`) + `_wwxrpHighRoiFromScore` (`:1179-1190`)

The clamp `if (score > MAX) score = MAX` (`:1144-1145`) and the branch selects on `<= MID` / `<= HIGH` (`:1148/:1155`) are comparisons against TABLE-A anchors → **invariant** by the comparison rule.

- **Low segment** (`score <= MID`, `:1148-1154`) — **[ANCHOR NOTE] this segment is QUADRATIC, not linear** (the CONTEXT/plan interfaces described all ROI legs as "linear"; the live low segment is a quadratic ease): `xNum = score`, `xDen = MID`; `term1 = 1000·xNum/xDen`; `term2 = 500·xNum²/xDen²`; `roi = ROI_MIN + term1 − term2`. Scale-invariance still holds, and is the stronger claim: `term1 = 1000·score/MID = 1000·s'/m'` (factor 100 cancels once); `term2 = 500·score²/MID² = 500·(100s')²/(100m')² = 500·s'²/m'²` (the 100² cancels in numerator and denominator). The literals `1000`/`500` are the quadratic's output-shape coefficients (the 90→95% curve), in the ROI output domain — they must **NOT** convert, exactly like the ROI anchors. `ROI_MIN` (output) unchanged. **Invariant for clean scores.** Worked: score 3000 bps (30 pt), MID 7500 (75): bps `term1 = 1000·3000/7500 = 400`, `term2 = 500·9_000_000/56_250_000 = 80` → `9000 + 400 − 80 = 9320`; points `term1 = 1000·30/75 = 400`, `term2 = 500·900/5625 = 80` → `9000 + 400 − 80 = 9320`. Identical.
- **Mid segment** (`MID < score <= HIGH`, `:1155-1160`): `delta = score − MID`; `span = HIGH − MID`; `ROI_MID + delta·(ROI_HIGH − ROI_MID)/span`. `K = ROI_HIGH − ROI_MID = 450` (output). `delta`/`span` both differences of ÷100 values → ratio invariant. **Invariant** by the ratio rule.
- **High segment** (`HIGH < score <= MAX`, `:1161-1166`): `delta = score − HIGH`; `span = MAX − HIGH`; `ROI_HIGH + delta·(ROI_MAX − ROI_HIGH)/span`. `K = ROI_MAX − ROI_HIGH = 40` (output). **Invariant.**
- **WWXRP high ROI** (`_wwxrpHighRoiFromScore`, `:1179-1190`): clamp `score > MAX → MAX` then `WWXRP_HIGH_ROI_BASE + score·(WWXRP_HIGH_ROI_MAX − WWXRP_HIGH_ROI_BASE)/MAX`. Single-anchor denominator `MAX` (input, `30500→305`); `K = 10990 − 9000 = 1990` (output). `score·K/MAX = s'·K/m'`. **Invariant.**

#### (3) Decimator — `recordTerminalDecBurn`/`recordTerminalDecKeepAlive` (`:793-801`, `:913-919`) + `_terminalDecBucket` (`:1133-1144`)

- **Clamp** `if (bonusBps > CAP) bonusBps = CAP` (`:796-797` and `:916-917`): comparison against the input anchor CAP `23500→235` → **invariant**. The clamped value flows on as the point-domain score.
- **Bucket reduction** `_terminalDecBucket` (`:1135-1141`): `range = BUCKET_BASE − MIN_BUCKET = 10` (a bucket count, dimensionless, NOT a score value → does NOT convert); `reduction = (range·bonusBps + CAP/2) / CAP`. This is `range·bonusBps/CAP` with a `+CAP/2` round-to-nearest. Both `bonusBps` and `CAP` (and so `CAP/2`) divide by 100 → `(range·bonusBps + CAP/2)/CAP = (range·s' + cap'/2)/cap'`. The score-ratio AND the rounding term are scale-invariant. **Invariant** (this is the `(CAP/2)/CAP` ratio the plan cited — confirmed for the bucket). Worked: bonusBps 11750 (CAP/2 case, 117.5 pt → floors to 117 pt under D-02 if it came from an odd half-point; here at a clean 11800/118 pt): `reduction = (10·11800 + 11750)/23500 = (118000+11750)/23500 = 129750/23500 = 5`; points `(10·118 + 117)/235 = (1180+117)/235 = 1297/235 = 5`. Identical.
- **Multiplier — [ANCHOR NOTE] NOT a CAP ratio; it is `bonusBps/3`** (`:799-801`, `:` mirror in keep-alive uses the same `BPS_DENOMINATOR + (bonusBps/3)` shape): `multBps = bonusBps == 0 ? 10000 : 10000 + (bonusBps/3)`. The plan's interface block said the decimator "uses CAP in (CAP/2)/CAP ratio" — that is the *bucket* leg; the **multiplier** leg is the bare integer division `bonusBps/3`, which is NOT scale-invariant under a naive ÷100: `(bonusBps/100)/3 ≠ (bonusBps/3)/100` as integers. To preserve the multiplier exactly, **436 POINTS-02 must re-express the multiplier so the divisor sees the bps-equivalent magnitude** — i.e. compute `10000 + (points·100)/3` (multiply the point score back up by 100 before the `/3`), NOT `10000 + (points/3)`. This is the one consumer leg where the point migration is NOT a literal ÷100 of a constant but a `×100` re-scale inside the expression. **This is recorded as a 436 edit-surface line item (D-04.4 / consolidated 436 surface) and a 438 re-attest item, NOT a behaviour change** — the re-scaled expression reproduces the bps result exactly for every score. (`BPS_DENOMINATOR = 10000` is an output divisor, TABLE B, unchanged.)

**Decimator multiplier worked check (the re-scale is exact):** bps score 11700 → `multBps = 10000 + 11700/3 = 10000 + 3900 = 13900`. Point score 117 with the re-scale `10000 + (117·100)/3 = 10000 + 11700/3 = 10000 + 3900 = 13900`. Identical. A naive `10000 + 117/3 = 10000 + 39 = 10039` would be catastrophically wrong (off by ~100×) — hence the re-scale requirement is mandatory, not optional.

### D-04.3 — The ONLY divergence: the odd-half-point threshold-tip (D-09)

Because the floored score is always a clean whole point (D-04.0), scale-invariance (D-04.2) makes every consumer **bit-identical** for the floored input — *except* where the D-02 floor itself drops a half-point that, in the un-floored bps domain, would have tipped the player across a TABLE-A threshold or shifted a ratio by one grid step. This is the sole, accepted divergence (D-09).

**Where it can occur:** only for a player whose pre-floor score lands on an **odd half-point** (i.e. an odd `questStreak`, contributing `…+50` bps so the score ends in `…+50` bps = `x.5` pt). The floor drops that trailing 0.5 pt. The drop can change a consumer outcome **only** if the half-point straddled a threshold/grid boundary — e.g. a bps score of `7550` (75.5 pt) sits *above* the Degenerette `ACTIVITY_SCORE_MID_BPS = 7500` boundary, so in the old domain it would take the *mid* segment; floored to `75` pt = `7500` bps-equivalent it sits *at* the boundary and takes the *low* (`<= MID`) segment. The magnitude of the resulting outcome shift is **at most one grid step at one boundary**, because the half-point is the smallest representable score increment and it moves the input by exactly one point-grid cell.

**Worked boundary example (bounded magnitude).** Take the Lootbox EV low/high boundary at `NEUTRAL = 6000` (60 pt). A player at bps score `6050` (60.5 pt, from an odd quest streak):
- Old (bps) domain: `6050 > 6000` → high leg: `excess = 50`, `maxExcess = 34000` → `EV = 10000 + 50·4500/34000 = 10000 + 6750/34000 = 10000 + 0 = 10000` (integer floor of 0.198). So the bps result is **10000** anyway.
- Point domain after D-02 floor (`60.5 → 60`): `score == 60 <= 60` → low leg: `EV = 9000 + 60·1000/60 = 9000 + 1000 = 10000`.
- **Both = 10000.** The boundary value happens to be continuous here (the legs meet at NEUTRAL by construction: low leg at NEUTRAL = `EV_MIN + NEUTRAL·(EV_NEUTRAL−EV_MIN)/NEUTRAL = EV_MIN + (EV_NEUTRAL−EV_MIN) = EV_NEUTRAL`, and the high leg at NEUTRAL+ε ≈ EV_NEUTRAL). The piecewise functions are **continuous at their join points**, so a one-grid-cell input shift at a join produces a sub-grid (≤1 ulp) output shift — typically zero.

The non-join case (a half-point straddling a *non-continuous* decision such as the Degenerette segment switch or a decimator bucket edge) is bounded the same way: the input moves by exactly one point cell, so the output moves by at most the consumer's per-cell sensitivity at that point — one ROI ulp / one EV ulp / at most one decimator bucket. Across the whole score range this is a **de-minimis** shift affecting only odd-half-point inputs sitting exactly on a boundary.

**Decision (D-09): ACCEPT + DOCUMENT.** The USER selected accepting this single-tip loss and documenting it here, over (a) nudging the thresholds to absorb the half-point or (b) requiring strict exact-equivalence (which would force keeping a half-point internal unit, contradicting D-02). **No threshold nudging is performed** — TABLE A converts by exact ÷100, the floored score is the input, and the bounded odd-half-point shift is the known, accepted residual. This carries threat-register item **T-435-07** to mitigated: the equivalence is proven scale-invariant for clean scores, and the sole divergence is bounded to one grid cell at one boundary for odd-half-point inputs only.

### DESIGN-04 — Locked outputs (for 436 IMPL / 438 REAUDIT)

| Lock | Value / rule | Source anchor |
|------|--------------|---------------|
| Equivalence basis | scale-invariance of comparisons + ratios under ÷100 (D-10) | this section |
| TABLE A (convert) | Degenerette MID/HIGH/MAX 7500/25500/30500→75/255/305; Lootbox NEUTRAL/MAX 6000/40000→60/400; Decimator CAP 23500→235 | TABLE A |
| TABLE B (do NOT convert) | ROI 9000-9990 + WWXRP 9000/10990; EV-mult 9000/10000/14500; quad coeffs 1000/500; DGNRS reward bps; BPS_DENOMINATOR 10000 | TABLE B |
| 40000 disambiguation | EV-cap = `LOOTBOX_EV_ACTIVITY_MAX_BPS` (convert→400); `LootboxModule:304` "40000" = EV mean (IGNORE) | `Storage:1555` / `LootboxModule:304` |
| Degenerette low leg | QUADRATIC (not linear); `term1/term2` invariant; coeffs 1000/500 stay | `DegeneretteModule:1148-1154` |
| Decimator multiplier | `bonusBps/3` re-expressed as `(points·100)/3` (×100 re-scale, NOT ÷100 of a constant) | `DecimatorModule:799-801, :913-919` |
| Decimator bucket | `(range·score + CAP/2)/CAP` scale-invariant; `range` is a bucket count (no convert) | `DecimatorModule:1135-1141` |
| Sole divergence | odd-half-point threshold-tip, ≤1 grid cell at one boundary, ACCEPTED + DOCUMENTED (D-09) | D-04.3 |

---

## 436 Edit Surface (consolidated)

The single per-file / per-symbol change list aggregating every edit locked across DESIGN-01..04, so 436 is a mechanical batched diff (the sole `.sol` change of the v69 milestone, the approval gate). Each line is anchored to the frozen `e9a5fc24` tree. **Comment-only edits are part of the same diff and are called out as `[comment]`.** This list folds in the seven `[ANCHOR NOTE]` corrections surfaced across plans 01-03 and the two new DESIGN-04 corrections.

### `contracts/modules/DegenerusGameMintStreakUtils.sol`

- `_playerActivityScoreAt` (`:282-372`): convert every additive leg to the point domain — the `×100` legs (mint streak `:329`, mint count `:330`, affiliate `:346`, deity base `:310-311`, deity pass `:350`, whale `:354/:356`, curse `:363-366`) collapse to their point form (drop the `×100`); the **quest-streak leg `:335` `questStreak × 50` → `floor(questStreak / 2)`** (D-02, the sole sub-point leg). [IMPL discretion: constant naming/placement of the floor.]
- The point cap **655** replaces the bps clamp (D-03): wherever `ACTIVITY_SCORE_HARD_CAP_BPS` is applied as the score ceiling, the value becomes the point cap `floor(65534/100) = 655`. `PASS_STREAK_FLOOR_POINTS = 50` / `PASS_MINT_COUNT_FLOOR_POINTS = 25` (`Storage:144/147`) are **already point-domain — NO conversion** (they floor the pre-`×100` point counts).
- `DEITY_PASS_ACTIVITY_BONUS_BPS = 8000` (`Storage:135`) → **80 pt** (multiple of 100, no special rule). [`Sub.score` semantics now point-domain; see Storage stamp note.]

### `contracts/storage/DegenerusGameStorage.sol`

- `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` (`:141`) → **point cap 655** (D-03). [`Sub.score` stamp (`:2127`, the `score(16)` field) **stays uint16** — 655 fits with headroom; the value it holds is now point-domain.]
- `Sub.subStreakLatch` (`:2244`) **uint8 → uint16** (D-04). `SUB_STREAK_MASK` (`:2251`) `0xff → 0xffff` (D-04). `_streakBaseOf` (`:2254-2256`) returns **uint16**, masking 16 bits (D-04). `_setStreakBase` (`:2259-2261`) **drop the `value > 255 ? 255 :` clamp** (D-04; a uint16-range clamp may stay for type safety — IMPL discretion). `_afkingStreak` (`:2271`) `uint32(_streakBaseOf(sub))` cast holds (uint16 ⊂ uint32, no change).
- `Sub.pendingFlip` (`:2237`) **uint32 → uint24** (D-06); its saturating accrue clamp re-pins `100_000_000 → 16_777_215` (`2^24−1`, ~16.7M whole FLIP) at the accrue sites (see GameAfkingModule). [IMPL discretion: exact constant value ≤ `2^24−1` + its name; recommend the exact type ceiling so the cast is lossless by construction.]
- Lootbox EV **score-INPUT** anchors (TABLE A): `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS = 6_000 → 60` (`:1553`); `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40_000 → 400` (`:1555`). **`LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS` (`:1557/:1559/:1561`) UNCHANGED** (output anchors, TABLE B). `_lootboxEvMultiplierFromScore` (`:1633-1654`): the formula is unchanged in shape (scale-invariant); only the two input-anchor constants change; the `@param score ... in basis points` natspec (`:1631`) → point-domain `[comment]`.
- **Accumulator repack** (D-07, net-zero): the slot now `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72`; `Sub` stays exactly one 256-bit slot, 0 free. `[comment]` fixes to the slot doc + field-section headers: slot doc-comment `config (40b) → (48b)` (`:2126`); the accumulator field comment `pendingFlip(32) → pendingFlip(24)` + `subStreakLatch(8) → (16)` and the `100M-whole-FLIP → ~16.7M (2^24−1)` notes (`:2129, :2154-2162, :2230-2237`); field-section header `per-sub stamp (48 bits) → (40b)` (`:2182`); field-section header `markers (72 bits) → (96b)` (`:2194`); the stale `streakAtAfkingStart (bits 0-6)` (`:2144`) and the `0..255` / `Clamped at 255` subStreakLatch comments (`:2238-2250`) → uint16 width.

### `contracts/modules/GameAfkingModule.sol`

- pendingFlip accrue casts/clamps (D-06): ticket buyer-bonus block `:861-863` (`newOwed` `:861`, clamp `> 100_000_000 → > 16_777_215` `:862`, cast `uint32(newOwed) → uint24(newOwed)` `:863`); slot-0 quest-reward block `:925-928` (clamp `:927`, cast `uint32 → uint24` `:928`). Settle read `_settlePendingFlip:1097-1100` — `uint256(s.pendingFlip)` widen-back holds, zero-write fits; **no logic change beyond the field type**; the `// Same uint32 + 100M…` comment → new width/ceiling `[comment]`.
- Streak-latch widening follow-through (D-04/D-05): the latch writes `_setStreakBase`/reads `_streakBaseOf` (run-start `:521/523/533/555`, `0`-on-lapse `:573`, the in-run `+1` secondary bump `recordAfkingSecondary:1734`) follow the uint16 widening — no behaviour change; the `+1` bump now saturates at 65535 instead of 255 (its `:1726` comment updated `[comment]`), far past where the 655-point activity cap matters.

### `contracts/DegenerusQuests.sol`

- **DELETE the finalize floor-hack** (D-04): the `uint16 preRun = state.streak; if (finalStreak != 0 && finalStreak < preRun) finalStreak = preRun;` block (`:549-550`) and its explanatory comment (`:546-548`). The decay logic (`:543-545`) and the final uint16 assignment (`:551`, kept as `state.streak = uint16(finalStreak)` with its safety clamp) **stay**.
- The streak source stays the uint16 `PlayerQuestState.streak` (`:281`), now symmetric with the uint16 latch; the `pendingFlip` accrual note (`~:1779`) stays consistent (streak-width change does not touch accrual semantics). [comment-only consistency; `beginAfking` return is `uint24 streak` `:504` sourced from the uint16 field — no change.]

### `contracts/modules/DegenerusGameDegeneretteModule.sol`

- Score-INPUT thresholds (TABLE A): `ACTIVITY_SCORE_MID_BPS = 7_500 → 75` (`:188`); `ACTIVITY_SCORE_HIGH_BPS = 25_500 → 255` (`:191`); `ACTIVITY_SCORE_MAX_BPS = 30_500 → 305` (`:194`).
- **DO NOT convert** (TABLE B): `ROI_MIN/MID/HIGH/MAX_BPS` (`:197-206`), `WWXRP_HIGH_ROI_BASE/MAX_BPS` (`:214/:217`), the low-leg quadratic coefficients `1000`/`500` (`:1152-1153`), `DEGEN_DGNRS_*_BPS`. The `_roiBpsFromScore` (`:1141-1170`), `_wwxrpHighRoiFromScore` (`:1179-1190`) formula shapes are unchanged (scale-invariant); only the three input-anchor constants change; the `@param score ... in basis points` natspecs → point-domain `[comment]`.

### `contracts/modules/DegenerusGameDecimatorModule.sol`

- Score-INPUT anchor (TABLE A): `TERMINAL_DEC_ACTIVITY_CAP_BPS = 23_500 → 235` (`:772`). The clamps `if (bonusBps > CAP) bonusBps = CAP` (`:796-797`, `:916-917`) compare against the converted CAP — formula shape unchanged.
- **Decimator multiplier re-scale (the one non-trivial migration, D-04.2):** `multBps = BPS_DENOMINATOR + (bonusBps / 3)` (`:799-801` and the keep-alive mirror `:913-919` region) must be re-expressed so the `/3` divisor sees the bps-equivalent magnitude: `BPS_DENOMINATOR + (points · 100) / 3` (multiply the point score back up by 100 before `/3`). A naive `points/3` is ~100× wrong. `BPS_DENOMINATOR = 10_000` (`:104`, TABLE B) **unchanged**.
- `_terminalDecBucket` (`:1133-1144`): `(range · score + CAP/2) / CAP` is scale-invariant; `range = BUCKET_BASE − MIN_BUCKET = 10` is a **bucket count, NOT a score value — do NOT convert** (`:770-771`). Only the CAP constant in the denominator follows TABLE A; formula shape unchanged.
- The two self-calls read the point-domain `playerActivityScore` (`:793`, `:913`) — re-confirm they consume points after the external return changes (no edit, attest in 438).

### DO-NOT-TOUCH list (must NOT be converted / narrowed / edited)

- **All TABLE B output bps** (these are NOT score inputs): Degenerette `ROI_MIN/MID/HIGH/MAX_BPS` + `WWXRP_HIGH_ROI_BASE/MAX_BPS`; the quadratic coefficients `1000`/`500`; `DEGEN_DGNRS_*_BPS`; Lootbox `LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS`; `BPS_DENOMINATOR = 10000`.
- **`lootboxRngPendingFlip`** (uint40, `Storage:1525`, bits [184:223], /1e18) — a SEPARATE field of the global `lootboxRngPacked`; **NOT narrowed** (D-08), distinct from `Sub.pendingFlip`.
- **The `LootboxModule:304` "40000" comment** — the derived presale-box FLIP-band EV mean, NOT the score anchor; do not convert or touch.
- **`Sub.score` stamp width** stays uint16 (D-03); **`affiliateBase`** stays uint32 with its own 100M clamp (`GameAfkingModule:920-922`) — only `pendingFlip` narrows (D-06).

---

## 438 RNG-Freeze Re-Audit Checklist (handoff to REAUDIT-02)

The cross-boundary / freeze / golden items 438 must re-attest on the repacked, point-domain subject. Activity score feeds the RNG consumers (lootbox EV, Degenerette, decimator), so the point migration **resets the v68 RNG-freeze proof + layout golden + mutation** — all re-run on the new subject in 438, carrying the v68 methodology forward.

### REAUDIT-02 — external `playerActivityScore` return-semantics change (bps → points)

The external return value changes domain (bps → points), crossing the contract boundary:

- **Boundary chain:** `IDegenerusGame.playerActivityScore` (`interfaces/IDegenerusGame.sol:65`, returns `uint256`; the `@dev ... basis points` / `@return Multiplier in bps (10000 = 1x)` natspec `:62-64` becomes point-domain) → `DegenerusGame.playerActivityScore` (`DegenerusGame.sol:2210-2218`, returns `_playerActivityScore(...)`, now point-domain; the `@return scoreBps ... in basis points` natspec `:2207-2209` becomes point-domain) → consumed by `sDGNRS.sol:47` (decl) + `sDGNRS.sol:1140` (snapshot) and the decimator self-call (`DecimatorModule:793`, `:913`).
- **sDGNRS point-domain correctness (re-verify + re-attest):** `sDGNRS.sol:1140` stores `claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1`, with `0` reserved as the unset sentinel (the `if (claim.activityScore == 0)` guard at `:1139`). Point-domain: max stored = `655 + 1 = 656`, fits uint16 (≪ 65535) with vast headroom; the `+1` `0=unset` sentinel still holds (min point score 0 → stored as 1, never 0). **Confirm point-domain-correct; no edit to sDGNRS required, but the snapshot now holds a point-domain score — re-attest in REAUDIT-02.** Where sDGNRS later *uses* `claim.activityScore − 1` as a score, confirm it feeds the point-domain consumers (no double-conversion).
- **Indexer / off-chain parity:** flag as a downstream consumer of the changed return semantics — any off-chain reader of `playerActivityScore` (the events emitting it, the indexer) now sees points, not bps. REAUDIT-02 flags the off-chain parity surface for the indexer re-vendor (out-of-contract, recorded for completeness).

### REAUDIT-02 — frozen-at-deposit anti-gaming knob, point-domain re-confirm

- The frozen-at-commitment score crosses module calls as **`uint16 activityScore`** — "the anti-gaming knob, FROZEN at deposit (`score`)" (`LootboxModule:551`). Confirmed it is taken by the four entrypoints: `resolveLootboxDirect` (`:873`), `resolveRedemptionLootbox` (`:928`), `_resolveRedemptionChunk` (`:967`), and the boon dispatch (`:1076`) — all `uint16 activityScore`.
- **Point-domain freeze re-confirm:** point-domain max 655 fits uint16 (65535) with vast headroom, so the snapshot-at-deposit value still rides as `uint16` unchanged. Re-confirm there is **no in-window score-bump bias** — the EV multiplier stays computed from the deposit-frozen `score` (not a re-read live score), so the point representation preserves the freeze exactly (a holder still cannot steer the box to a preferred level/score; auto-open removes timing). Re-attest the freeze in the point domain in REAUDIT-02.

### REAUDIT-01 — layout-golden recapture (EXPECTED new golden, NOT a drift)

- The accumulator repack (D-07: `pendingFlip` 32→24, `subStreakLatch` 8→16) WILL change the `forge inspect <c> storage-layout` snapshot for `Sub` — the intra-slot field offsets/widths shift. **This recapture is the EXPECTED NEW GOLDEN, handled in 438 REAUDIT-01 — NOT a layout drift.** The slot index of `Sub` is unchanged (still one 256-bit slot, 0 free); only the intra-slot offsets/types update. 438 recaptures the v68 MECH-02 `forge inspect` oracle against the repacked subject and re-attests it matches the locked D-07 layout. The ~30 slot-hardcoded test harnesses re-pin to the new golden there.
- **EIP-170:** the Game is perpetually near the 24,576-byte ceiling; the repack + threshold migration is register-level (width swaps, constant-value changes, one `×100` re-scale) and is expected net-neutral — but 436/PACK-01 measures it empirically and 438 re-attests.

### REAUDIT — mutation + invariant re-run on the changed modules

- The point migration touches `MintStreakUtils`, `DegenerusGameStorage`, `GameAfkingModule`, `DegenerusQuests`, `DegeneretteModule`, `DecimatorModule`, `LootboxModule` (input anchors). The v68 mutation campaign + invariant suite **re-run on the changed modules** against the new subject (v68 methodology carries forward); 437 TST owns the clamp-saturation property (TST-02) and the new-domain consumer tests, 438 REAUDIT re-runs the mutation/invariant attestation.

### Out-of-scope confirmation (so the re-audit does not chase it)

- `lootboxRngPendingFlip` (uint40, `Storage:1525`) is a **distinct out-of-scope field** (D-08, carried from DESIGN-03) — not narrowed, not part of the repack; the re-audit does not chase it.

---
