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
