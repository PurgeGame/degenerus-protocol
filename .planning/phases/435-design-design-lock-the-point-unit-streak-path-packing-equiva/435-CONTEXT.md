# Phase 435: DESIGN — Design-Lock the Point Unit, Streak Path, Packing & Equivalence - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Design-lock (NO `contracts/*.sol` change) the four inputs the 436 IMPL diff will implement:
1. The activity-score point unit + the quest-streak floor rule (DESIGN-01).
2. The single exact integer streak-base path + the reworked carried-in pre-streak handling (DESIGN-02).
3. The `Sub.pendingFlip` width + the 72-bit accumulator-slot repack (DESIGN-03).
4. The consumer-threshold re-derivation in points + a behaviour-equivalence analysis (DESIGN-04).

This phase produces the load-bearing design document. The contract edit happens in 436 (the sole approval gate). Baseline = the v68.0 closure subject `3cc51d00` / `contracts/` tree `e9a5fc24` (logic-byte-frozen at milestone start).
</domain>

<decisions>
## Implementation Decisions

### DESIGN-01 — Point unit & quest-streak floor
- **D-01 (point unit):** Activity score is represented in **whole points**, 1 pt = 100 bps. In `_playerActivityScoreAt` (`MintStreakUtils`) every contributor is already a clean multiple of 100 bps — mint streak (`×100`), mint count (`×100`), affiliate (`affPoints×100`), deity/whale passes, curse penalty (`curse×100`) — **except** the quest-streak leg.
- **D-02 (floor rule = `floor(questStreak / 2)`):** Quest streak is the **sole sub-point contributor** (`questStreak × 50` bps = 0.5 pt each). It converts via **`floor(questStreak / 2)`** — 1 pt per 2 quests, dropping the trailing 0.5 pt at odd streak counts. Chosen over round-half-up and over keeping a half-point internal unit (USER selected; matches the design seed's "floor the streak contribution"). This is the only place precision is intentionally lost.
- **D-03 (point cap = 655):** The hard cap `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` becomes a point cap of **`floor(65534/100) = 655` points** (the old 65534 was the uint16-exact bps ceiling; 655 is the natural point ceiling). The frozen stamp field `Sub.score` stays **uint16** (655 fits with headroom; the slot is otherwise exactly packed so there is no benefit to narrowing it).

### DESIGN-02 — Exact integer streak path + pre-streak rework
- **D-04 (widen the latch, drop both band-aids):** Today the manual quest streak (`PlayerQuestState.streak`, **uint16**) is snapshotted into `Sub.subStreakLatch` (**uint8**) at run start via `_setStreakBase`, which **clamps to 255** — silently truncating a high-streak player's carried-in streak for the afking run's activity score. A compensating **finalize floor-hack** (`DegenerusQuests.sol:546-551`) reaches back into the dormant uint16 `state.streak` to restore it on exit. **Decision:** widen `subStreakLatch` `uint8 → uint16` (using the 8 bits freed by D-06), making it symmetric with the manual streak. The carried-in pre-streak then snapshots **exactly** — the 255 clamp is removed and the finalize floor-hack is deleted. The afking-run effective streak stays `latch + (afkCoveredThroughDay − afkingStartDay)`; the afking-XOR-manual `_effectiveQuestStreak` semantics are preserved.
- **D-05 (single exact path):** With the latch full-width, the manual + afking streak base feeds `_playerActivityScore` through one exact integer path with no fractional/bps intermediate. `DegenerusQuests` streak source + the `pendingFlip` accrual (`~:1779`) stay consistent with the new path.

### DESIGN-03 — pendingFlip narrowing + accumulator repack
- **D-06 (`pendingFlip` → uint24, clamp ~16.7M):** `Sub.pendingFlip` narrows **uint32 → uint24** with its saturating clamp re-pinned to **~16.7M whole FLIP** (the uint24 ceiling) — far above any realistic per-sub claimable bank, and freeing **exactly 8 bits** for the D-04 latch widening (USER selected uint24 over tighter widths).
- **D-07 (repacked accumulator, still 72 bits / slot still 256-exact):** The 72-bit accumulator becomes `affiliateBase(32) + pendingFlip(24) + subStreakLatch(16) = 72` — net-zero, so the `Sub` struct stays **exactly one 256-bit slot, 0 free**. No new cold slot, no field value-range violated, no slot collision. EIP-170 re-checked in 436.
- **D-08 (`lootboxRngPendingFlip` is out of scope):** Confirmed a **separate** field — `lootboxRngPendingFlip` uint40 at `DegenerusGameStorage:1525` (`bits 184:223`, scaled /1e18), unrelated to `Sub.pendingFlip`. Not narrowed.

### DESIGN-04 — Consumer-threshold equivalence
- **D-09 (accept + document the de-minimis boundary shift):** Flooring can change a consumer outcome **only** at the exact boundary where one odd quest's 0.5 pt used to tip a player over a threshold. Decision: **accept** that single-tip loss and **document** it in the equivalence analysis (USER selected, over nudging thresholds or requiring strict exact-equivalence). No threshold nudging.
- **D-10 (scale-invariance is the equivalence argument):** The activity-score consumers that interpolate (lootbox EV multiplier `_lootboxEvMultiplierFromScore`, decimator, Degenerette) compute `score · Δ / range`. Converting score **and** the range anchors by ÷100 leaves the ratio unchanged; for clean-multiple scores the integer result is **identical**, and the only divergence is the documented de-minimis case at odd-half-point inputs (D-09). The DESIGN-04 analysis is built on proving this scale-invariance per consumer + bounding the odd-half-point divergence.

### Claude's Discretion
- Exact constant naming / where the floor + point cap live in source — IMPL detail for 436.
- The precise uint24 clamp constant value (the exact uint24 ceiling vs a rounded ~16.7M) — pick the cleanest in 436, justified against the realistic bank.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone design inputs
- `.planning/PLAN-V69-ACTIVITY-SCORE-POINTS.md` — the USER design seed (the three asks + the touch-surface scan + the "resets the v68 subject" implications).
- `.planning/REQUIREMENTS.md` — the 16 v69 REQ-IDs (DESIGN-01..04 map to this phase) + Out-of-Scope table.
- `.planning/ROADMAP.md` §"Phase Details (v69.0)" → Phase 435 — goal + success criteria.

### Source files in the touch-surface (read at design-lock)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` — `_playerActivityScoreAt` (`:282-372`), `_playerActivityScore` (`:380`), `ACTIVITY_SCORE_HARD_CAP_BPS`, the quest-streak `×50` leg (`:335`), `PASS_STREAK_FLOOR_POINTS` / `DEITY_PASS_ACTIVITY_BONUS_BPS`.
- `contracts/storage/DegenerusGameStorage.sol` — the `Sub` struct (`:2169-2245`), the accumulator-slot doc (`:2126-2168`), `_setStreakBase` / `_streakBaseOf` (`:2253-2261`), `_afkingStreak` / `_effectiveQuestStreak` (`:2268-2304`), `_lootboxEvMultiplierFromScore` (`:1633`), `lootboxRngPendingFlip` (`:1525`).
- `contracts/modules/GameAfkingModule.sol` — the run-start snapshot `_setStreakBase(s, snap)` (`:500-573`), the `pendingFlip` accrual (`:861-928`, `:1098-1100`).
- `contracts/DegenerusQuests.sol` — `beginAfking` (`:501-511`), `finalizeAfking` + the floor-hack to delete (`:532-558`), the `pendingFlip` accrual note (`:1779`).
- Consumer thresholds: `contracts/modules/DegenerusGameDegeneretteModule.sol` (`ACTIVITY_SCORE_MID/HIGH/MAX_BPS = 7500/25500/30500`, `:188-194`), `contracts/modules/DegenerusGameDecimatorModule.sol` (`TERMINAL_DEC_ACTIVITY_CAP_BPS = 23_500`, `:772`; reads `playerActivityScore` `:793`), lootbox EV anchors (`LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS`, `LOOTBOX_EV_ACTIVITY_MAX_BPS = 40000`).
- Cross-contract consumer: `contracts/interfaces/IDegenerusGame.sol:65` + `contracts/sDGNRS.sol:47` (`playerActivityScore` external), surfaced from `contracts/DegenerusGame.sol:2210`.
</canonical_refs>

<code_context>
## Existing Code Insights

### Design-lock must resolve precisely (executor checklist)
- **Separate score-INPUT thresholds (convert ÷100) from same-named OUTPUT bps that must NOT convert.** Activity-score input thresholds: Degenerette MID/HIGH/MAX (7500/25500/30500 → 75/255/305), Lootbox `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS`/`_MAX_BPS` (6000/40000 → 60/400), Decimator `TERMINAL_DEC_ACTIVITY_CAP_BPS` (23500 → 235). Do **NOT** convert output bps in other domains: ROI bps (`ROI_MIN/MID/HIGH/MAX 9000-9990`), the EV-multiplier *output* bps (`LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS`), DGNRS reward bps (`DEGEN_DGNRS_*_BPS`). The roadmap's "Lootbox EV-cap 40000" = the score-input anchor `LOOTBOX_EV_ACTIVITY_MAX_BPS`, confirmed (a coincidentally-equal "40000" comment at LootboxModule:304 is the derived EV mean — different value, ignore).
- **Verify every additive bps constant in `_playerActivityScoreAt` is a multiple of 100** so ÷100 is exact: mint streak `×100`, mint count `×100`, affiliate `×100`, curse `×100`, deity `50×100 + 25×100 + DEITY_PASS_ACTIVITY_BONUS_BPS`, whale `+1000/+4000`. The **only** 50-multiple is the quest-streak leg (`:335`, the one floored). Explicitly confirm `DEITY_PASS_ACTIVITY_BONUS_BPS` is a multiple of 100; if not, it needs its own conversion rule.
- **External `playerActivityScore` return-semantics change bps→points** crosses the contract boundary: `IDegenerusGame.playerActivityScore` (`:65`) → consumed by `sDGNRS.sol:47` and the decimator self-call (`DecimatorModule:793`). Re-verify sDGNRS's use is point-domain-correct and re-attest in the RNG-freeze re-audit (REAUDIT-02); flag indexer/off-chain parity.
- **The frozen-at-commitment score crosses module calls as `uint16 activityScore`** (`resolveLootboxDirect`/`resolveRedemptionLootbox`/`_resolveRedemptionChunk`, and the `Sub.score` stamp) — "the anti-gaming knob, FROZEN at deposit" (LootboxModule:551). Point-domain max 655 fits uint16; re-confirm the snapshot-at-deposit freeze in the point domain (REAUDIT-02).

### Reusable assets / established patterns
- The accumulator slot is **exactly 256 bits, 0 free** — the repack (D-07) is net-zero by construction, so it stays one slot. The `forge inspect` storage-layout golden (v68 MECH-02 oracle) **will** flag the field-width move; that recapture is the expected new golden, handled in 438 REAUDIT (REAUDIT-01), not a drift.
- The decay-on-read afking-streak model (`_afkingStreak`) and the afking-XOR-manual unification (`_effectiveQuestStreak`) are preserved unchanged — only the latch width + the snapshot precision change.

### Integration points
- Activity score feeds RNG consumers (lootbox EV, Degenerette, decimator) → resets the v68 RNG-freeze proof + layout golden + mutation, all re-run on the new subject in 438 REAUDIT (v68 methodology carries forward).
</code_context>

<specifics>
## Specific Ideas

- USER's framing of the pre-streak grievance (DESIGN-02): the dislike is the **uint8/255 clamp + the compensating finalize floor-hack** — a width mismatch papered over twice. The locked fix removes both by matching the latch width to the manual streak.
- The equivalence story rests on **scale-invariance of linear interpolation** (D-10), not on hand-checking every grid point: ÷100 of score and range anchors preserves the ratio; integer results match for clean scores; the only divergence is the accepted odd-half-point de-minimis case.
</specifics>

<deferred>
## Deferred Ideas

- `:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard + the 423 rotation-timer hardening — USER-deferred LOW defense-in-depth (v2 in REQUIREMENTS.md). Out of scope unless the USER folds them into the 436 IMPL diff; bundling would widen the equivalence/re-audit story.
- None other — discussion stayed within phase scope.
</deferred>

---

*Phase: 435-DESIGN — Design-Lock the Point Unit, Streak Path, Packing & Equivalence*
*Context gathered: 2026-06-18*
