# Phase 436: IMPL — Batched Contract Diff (POINTS + STREAK + PACK) [contract-commit gate] - Context

**Gathered:** 2026-06-18
**Status:** Ready for planning

<domain>
## Phase Boundary

Land the v69 activity-score change as **ONE batched, USER-approved `contracts/*.sol` diff** — the sole approval gate of the milestone. The diff implements three locked tracks from the 435 DESIGN-LOCK:
- **POINTS** — activity score moves bps→whole points (floor the only sub-point leg, the quest streak, per `floor(questStreak/2)`); every consumer threshold migrates to the point domain (Degenerette MID/HIGH/MAX + ROI anchors, Lootbox EV-cap, Decimator threshold incl. the non-trivial `×100` multiplier re-scale).
- **STREAK** — the manual + afking `subStreakLatch` streak base collapses into a single exact integer path; the carried-in pre-streak cap is reworked (widen latch uint8→uint16, drop the 255 clamp, delete the finalize floor-hack).
- **PACK** — `Sub.pendingFlip` narrows uint32→uint24, the 72-bit accumulator slot repacks net-zero (`affiliateBase(32)+pendingFlip(24)+subStreakLatch(16)`), EIP-170 re-checked, no slot collision.

This is a mechanical batched diff from the consolidated 436 edit surface in `435-DESIGN-LOCK.md`. The substance is design-locked; this phase decides only the IMPL-discretion residue. Baseline = the v68.0 closure subject `3cc51d00` / `contracts/` tree `e9a5fc24`. Proving (437 TST) and re-auditing (438 REAUDIT) are separate phases.

</domain>

<decisions>
## Implementation Decisions

The 435 DESIGN-LOCK (DESIGN-01..04 + the consolidated 436 edit surface + the DO-NOT-TOUCH list) is the load-bearing spec — all substantive decisions (floor rule, threshold conversions, latch widening, accumulator repack, the Decimator `×100` re-scale, scale-invariance equivalence) are already locked there and are NOT re-litigated here. The decisions below are the IMPL-discretion knobs the design-lock deferred to 436, plus one amendment to D-03.

### Constant naming (`_BPS` → `_POINTS`)
- **D-436-01 (rename all score-INPUT anchors to `_POINTS`):** Every score-*input* constant whose value becomes a point value is renamed `_BPS`→`_POINTS`, matching the existing in-file convention (`PASS_STREAK_FLOOR_POINTS`, `PASS_MINT_COUNT_FLOOR_POINTS`). Rename set: `ACTIVITY_SCORE_HARD_CAP_BPS`, `DEITY_PASS_ACTIVITY_BONUS_BPS`, `LOOTBOX_EV_ACTIVITY_NEUTRAL_BPS`, `LOOTBOX_EV_ACTIVITY_MAX_BPS`, Degenerette `ACTIVITY_SCORE_MID/HIGH/MAX_BPS`, Decimator `TERMINAL_DEC_ACTIVITY_CAP_BPS`. Rationale: the identifier must match the domain (contracts are frozen at deploy; a `_BPS`-named point value is a stale name). Cost accepted: every reference site changes (bigger diff) and the audit anchors shift — 438 REAUDIT recaptures the layout/freeze golden regardless.
- **D-436-02 (genuine output-bps constants keep `_BPS`):** The TABLE-B output / out-of-domain bps constants are NOT renamed and NOT converted: ROI `*_BPS`, WWXRP ROI `*_BPS`, the EV-multiplier *output* `LOOTBOX_EV_MIN/NEUTRAL/MAX_BPS`, `DEGEN_DGNRS_*_BPS`, `BPS_DENOMINATOR`, and the quadratic shape coefficients `1000`/`500`. (Reinforces the existing DO-NOT-TOUCH list.)
- **D-436-03 (comment rule):** Reword unit tokens (`bps` / `basis points` → `points`) on the renamed constants and the `@param score ... in basis points` natspecs. **Keep** any rationale that stays true; **drop** rationales that go false. (See D-436-04 — the hard-cap overflow rationale becomes true verbatim, so it stays.)

### Score cap — AMENDS design-lock D-03 ⚠
- **D-436-04 (cap stays `65_534` points, NOT floored to 655):** Source-traced finding: the activity-score hard cap is **gameplay-inert** — every consumer clamps the score below it (Lootbox EV `>= MAX → MAX` at 400 pts; Degenerette ROI/WWXRP `> MAX → MAX` at 305 pts; Decimator `bonusBps > CAP → CAP` at 235 pts). The cap's only real job is bounding the value stored frozen as `uint16` (the `Sub.score` lootbox stamp + sDGNRS `claim.activityScore = uint16(score)+1`, 0 = unset sentinel). Flooring `65_534`→`655` (D-03) wrongly treated a uint16-storage constant as a score-scaled value and would impose a new artificial 655-pt ceiling that clamps real players (streak alone reaches `floor(65535/2)=32767` pts) for zero gameplay benefit. **Decision (USER "uncap score"):** keep the numeral `65_534` (now `ACTIVITY_SCORE_HARD_CAP_POINTS = 65_534`) — the uint16 storage limit, one below max for the `+1` sentinel. Behaviourally equivalent on-chain (consumers clamp ≤400 either way), storage-safe (`65534+1=65535` fits uint16), and the original overflow comment becomes true verbatim (D-436-03 keeps it). `Sub.score` stays uint16 (now fits exactly: `65534+1=65535`).
- **D-436-05 (streak is uncapped to the packing limit):** Streak is already effectively uncapped by the locked `subStreakLatch` uint8→uint16 widening — bounded only by the uint16 streak source (`PlayerQuestState.streak`). `floor(65535/2)=32767` pts is far above the 400-pt consumer clamp, so this is effectively uncapped for gameplay. Going beyond uint16 would need a uint24+ source/latch, which collides with the 0-free PACK repack — out of scope (see Deferred).

### Defensive clamps after widening
- **D-436-06 (`_setStreakBase` keeps a saturating clamp at uint16 max):** Re-pin the clamp `value > 255 ? 255` → `value > type(uint16).max ? type(uint16).max`. NOT dead code — `recordAfkingSecondary` does `_setStreakBase(s, _streakBaseOf(s) + 1)`, so a read at the 65535 ceiling + 1 = 65536 and a bare `uint16(65536)` cast wraps to 0 (silent streak reset). The clamp guards that live +1 increment path. (`SUB_STREAK_MASK` `0xff`→`0xffff` per the design-lock.)
- **D-436-07 (`pendingFlip` clamp = `type(uint24).max`):** Re-pin both accrue-site clamps (`GameAfkingModule` ticket buyer-bonus block + slot-0 quest-reward block) from `> 100_000_000` to the exact uint24 ceiling `type(uint24).max` (16_777_215), with `uint24(newOwed)` casts. The cast is lossless by construction (the clamped value always fits). ~16.7M whole FLIP, far above any realistic per-sub bank.
- **D-436-08 (`affiliateBase` untouched):** `affiliateBase` stays uint32 with its own `100_000_000` clamp (DO-NOT-TOUCH) — only `pendingFlip` narrows.

### Design-lock reconciliation (planner action)
- **D-436-09:** D-436-04 amends design-lock D-03. The planner/executor MUST reconcile the "655" appearing in `435-DESIGN-LOCK.md` (DESIGN-01 §D-03, the locked-outputs block) and in the consolidated **436 Edit Surface** (the `MintStreakUtils` point-cap line + the `DegenerusGameStorage` `ACTIVITY_SCORE_HARD_CAP_BPS → 655` line) to **`65_534`** (rename-only, value unchanged), and the 438 REAUDIT-02 freeze note from "656 fits with headroom" to "65534+1=65535 fits exactly (the original tight uint16 bound restored)". Everything else in the edit surface stands as written.

### Claude's Discretion
- **Pre-approval empirical gate (taken at discretion):** before presenting the diff for the single hand-review, run `forge build` clean + the EIP-170 deployed-bytecode ceiling check (PACK-01 requires it) + a storage-layout-slot sanity (`Sub` stays one 256-bit slot, 0 free — the repack is intentional, the new golden lands in 438) + a baseline-parity smoke. Full behavioural proof stays in 437 TST / 438 REAUDIT.
- **Diff presentation (taken at discretion):** present the batched diff grouped by the three tracks (POINTS / STREAK / PACK) with a per-file change map and TABLE-A-convert / TABLE-B-do-not-convert annotations, so the one hand-review is auditable. One atomic contract commit (per the batch-approval rule).
- Exact constant placement / helper naming for the `floor(questStreak/2)` leg — IMPL detail.
- Whether to use `type(uint16).max` / `type(uint24).max` literals vs the mask constants where equivalent — pick the most self-documenting.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### The load-bearing design-lock (read FIRST)
- `.planning/phases/435-design-design-lock-the-point-unit-streak-path-packing-equiva/435-DESIGN-LOCK.md` — DESIGN-01..04 + the consolidated **436 Edit Surface** (per-file/per-symbol) + the **DO-NOT-TOUCH list** + the 438 RNG-freeze re-audit checklist. This is the spec for the 436 diff. ⚠ Apply D-436-09: its "655" reconciles to `65_534`.
- `.planning/phases/435-.../435-CONTEXT.md` — the locked DESIGN-01..04 decisions (D-01..D-10) carried forward.

### Milestone inputs
- `.planning/PLAN-V69-ACTIVITY-SCORE-POINTS.md` — the USER design seed (the three asks + touch-surface scan + "resets the v68 subject" implications).
- `.planning/REQUIREMENTS.md` — the 436 REQ-IDs (POINTS-01, POINTS-02, STREAK-01, STREAK-02, PACK-01) + the Out-of-Scope table.
- `.planning/ROADMAP.md` §"Phase Details (v69.0)" → Phase 436 — goal + success criteria + the contract-commit gate posture.

### Source files in the 436 edit surface (anchored at `e9a5fc24`)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` — `_playerActivityScoreAt` (`:282-372`, the `×100`-leg collapse + the quest-streak floor at `:335`), the point cap, `_playerActivityScore` (`:380`).
- `contracts/storage/DegenerusGameStorage.sol` — `ACTIVITY_SCORE_HARD_CAP_BPS` (`:141`, → `_POINTS = 65_534`), the `Sub` struct + accumulator slot (`:2126-2245`), `SUB_STREAK_MASK`/`_streakBaseOf`/`_setStreakBase` (`:2251-2261`), `_lootboxEvMultiplierFromScore` (`:1633-1654`), the Lootbox EV input anchors (`:1553/:1555`), `lootboxRngPendingFlip` (`:1525`, OUT OF SCOPE).
- `contracts/modules/GameAfkingModule.sol` — the `pendingFlip` accrue clamps (`:861-863`, `:925-928`), `_settlePendingFlip` (`:1097-1100`), the `_setStreakBase` follow-through (`:521/523/533/555/573`), `recordAfkingSecondary` +1 bump (`:1734`).
- `contracts/DegenerusQuests.sol` — DELETE the finalize floor-hack (`:546-550`), the streak source (`:281`), `beginAfking` (`:501-511`).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `ACTIVITY_SCORE_MID/HIGH/MAX_BPS` (`:188/:191/:194`), `_roiBpsFromScore` (`:1141-1170`), `_wwxrpHighValueRoi` (`:1179-1190`).
- `contracts/modules/DegenerusGameDecimatorModule.sol` — `TERMINAL_DEC_ACTIVITY_CAP_BPS` (`:772`), the clamps (`:796-797`, `:916-917`), the multiplier re-scale `BPS_DENOMINATOR + (points·100)/3` (`:799-801`, `:913-919`), `_terminalDecBucket` (`:1133-1144`).
- `contracts/interfaces/IDegenerusGame.sol:65` + `contracts/DegenerusGame.sol:2210-2218` + `contracts/sDGNRS.sol:47,:1139-1140` — the external `playerActivityScore` bps→points boundary (re-attested in 438 REAUDIT-02).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- The in-file `PASS_STREAK_FLOOR_POINTS` / `PASS_MINT_COUNT_FLOOR_POINTS` constants establish the `_POINTS` naming convention the rename adopts (D-436-01). These are already point-domain — NOT converted.
- The accrue-site clamp pattern `if (newOwed > X) newOwed = X; field = uintN(newOwed);` is reused for the re-pinned `pendingFlip` clamp (D-436-07) — same shape, new ceiling + cast width.

### Established Patterns
- Every additive leg in `_playerActivityScoreAt` is a clean `×100` multiple except the quest-streak `×50` leg — that single leg is the only place precision is intentionally lost (the floor), confirmed in DESIGN-01.
- All activity-score consumers clamp the score to their own thresholds before using it (EV ≤400, ROI/WWXRP ≤305, decimator ≤235) — this is WHY the hard cap is gameplay-inert and can stay at the uint16 storage limit (D-436-04).
- The accumulator slot is exactly 256 bits, 0 free; the repack (D-07) is net-zero so the slot index is unchanged — the `forge inspect` layout golden flags the intra-slot field move as the EXPECTED new golden in 438 (REAUDIT-01), not a drift.

### Integration Points
- `playerActivityScore` crosses the contract boundary (bps→points return-semantics change) → sDGNRS snapshot + decimator self-call + any off-chain indexer. On-chain consumers all clamp (no behavioural change); the off-chain indexer sees points now (incl. the higher raw values for >655-pt players unlocked by D-436-04) → flagged for re-vendor in 438 REAUDIT-02.
- Activity score feeds the RNG consumers (lootbox EV, Degenerette, decimator) → the IMPL diff RESETS the v68 RNG-freeze proof + layout golden + mutation, all re-run on the new subject in 438 (v68 methodology carries forward).

</code_context>

<specifics>
## Specific Ideas

- USER's "uncap score" (D-436-04): the intent is that the activity score / streak shouldn't carry an artificial low ceiling when the consumers already clamp. Resolved cleanly to "keep the cap at the uint16 storage limit (65_534), don't floor it to 655" — equivalent on-chain, removes the artificial ceiling, and restores the constant's true (storage-guard) meaning.
- The naming change follows the USER's standing rule that identifiers/comments describe what IS (no stale `_BPS` on a point value), applied at the frozen-at-deploy boundary.

</specifics>

<deferred>
## Deferred Ideas

- **Truly uncapping streak/score beyond uint16** — would require widening the streak source (`PlayerQuestState.streak`) + latch beyond 16 bits and the `Sub.score` stamp + sDGNRS `claim.activityScore` field beyond uint16, breaking the net-zero 0-free accumulator repack and the +1 sentinel. Out of scope for v69; no gameplay benefit (consumers clamp at ≤400). Note for the roadmap backlog only.
- `:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard + the 423 rotation-timer hardening — USER-deferred LOW defense-in-depth (v2 in REQUIREMENTS.md). Out of scope unless USER folds into the 436 diff; bundling would widen the equivalence/re-audit story (carried from 435).
- None other — discussion stayed within phase scope.

</deferred>

---

*Phase: 436-IMPL — Batched Contract Diff (POINTS + STREAK + PACK) [contract-commit gate]*
*Context gathered: 2026-06-18*
