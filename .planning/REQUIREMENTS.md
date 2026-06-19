# Requirements: Degenerus Protocol — v69.0 Activity-Score Points + Streak/Sub Precision + pendingFlip Right-Size

**Defined:** 2026-06-19
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Milestone goal:** Represent the player activity score in whole points instead of bps, remove the integer-imprecision in the streak/sub path (including reworking how the carried-in pre-streak is capped/snapshotted into the afking run), and right-size the `pendingFlip` accumulator — then re-run the v68 detection nets on the resulting code. The activity score is the anti-gaming knob that scales the lootbox EV multiplier, the Degenerette ROI curve, and the decimator curve; its only sub-point contributor is the quest streak at 50 bps/level (0.5 pt). Whole points with a defined floor remove the sole source of fuzz; the same edit cleans the manual + afking streak-base combine and narrows the over-wide `pendingFlip`.
**Method:** DESIGN-LOCK → ONE batched contract diff → TST → RE-AUDIT on the reset subject → TERMINAL. The whole-point grid must be shown not to materially shift the EV / ROI / decimator outcomes; security / RNG-non-manipulability stays the hard floor.
**Subject:** Baseline = the v68.0 closure subject `3cc51d00` / `contracts/` tree `e9a5fc24` (logic-byte-frozen at milestone start). The IMPL diff (436) produces the new v69 subject; it is byte-frozen for all re-audit work after IMPL.
**Posture:** Contract LOGIC change. It **RESETS the v68 audit subject** — the RNG-freeze proof, the storage-layout golden, and the mutation results are pinned to `e9a5fc24` and must be re-run on the new code (the v68 methodology carries forward). The edit ships as ONE batched diff behind the standard contract-commit approval gate (the sole gate); all SPEC / test / tooling / proof / re-audit additions commit autonomously.
**Assumptions:** Honest admin / governance (admin malice out of scope). Pre-launch, no live funds.

## v1 Requirements

Requirements for this milestone. Each maps to exactly one roadmap phase.

### DESIGN — Design-Lock the Point Unit, Streak Path, Packing & Equivalence (no `.sol` change)

- [ ] **DESIGN-01**: The point unit and the quest-streak floor rule are locked — the activity score is defined in whole points (the bps representation ÷100), and the only sub-point contributor (quest streak at 50 bps/level = 0.5 pt, `MintStreakUtils` `_playerActivityScore`) is floored by an explicit, single integer rule (e.g. 1 pt per 2 streak levels, floored), removing the 0.5-pt granularity; the cap is restated in points (the current `ACTIVITY_SCORE_HARD_CAP_BPS = 65_534` lands exactly at the uint16 ceiling — the point-domain cap + its storage width are chosen and justified).
- [ ] **DESIGN-02**: The single exact integer streak-base path is designed — how the manual quest streak and the afking-run streak base (`Sub.subStreakLatch`, uint8) combine into `_playerActivityScore` is reduced to one exact integer path, AND how the carried-in pre-streak is capped/snapshotted into the afking run is **reworked** (the current cap shape is dropped per USER; the new handling is specified with its game-theory/actor walk, the afking-XOR-manual `_effectiveQuestStreak` interaction preserved).
- [ ] **DESIGN-03**: The `pendingFlip` width and the accumulator-slot repack are locked — `Sub.pendingFlip` (uint32 ~4.3B today, with the 100M-whole-FLIP saturating clamp) is narrowed to the realistic bank cap (uint24 ~16.7M or tighter, justified against the realistic maximum, not 100M), and the 72-bit accumulator slot (`affiliateBase(32) + pendingFlip(32) + subStreakLatch(8)`, `DegenerusGameStorage` ~`:2242`/`:2134`) is repacked to the new widths; the **separate** `lootboxRngPendingFlip` uint40 (`DegenerusGameStorage` ~`:1527`) is confirmed distinct and out of scope for the narrowing.
- [ ] **DESIGN-04**: Every consumer threshold is re-derived in points with a behaviour-equivalence analysis — the Degenerette anchors (MID 7500 / HIGH 25500 / MAX 30500 / the ROI-curve anchors), the Lootbox EV-multiplier cap (40000), and the Decimator threshold (23500) are restated in the point domain, and the EV / ROI / decimator curves are shown to be behaviour-equivalent on the coarser whole-point grid (the analysis identifies any grid point where an outcome would shift and confirms it does not materially change the result).

### POINTS — Activity Score bps → Whole Points (IMPL, batched diff)

- [x] **POINTS-01**: The activity score is represented and computed in whole points — `_playerActivityScore` (`MintStreakUtils`) returns the point-domain score with the quest-streak contribution floored per DESIGN-01; the hard cap is enforced in points at the chosen storage width.
- [x] **POINTS-02**: Every consumer threshold is migrated to the point domain per DESIGN-04 — `DegenerusGameDegeneretteModule` (MID/HIGH/MAX + ROI anchors), `DegenerusGameLootboxModule` (EV-multiplier cap), and `DegenerusGameDecimatorModule` (threshold) read the point-domain score and compare against point-domain constants, with the curves behaviour-equivalent to the bps version.

### STREAK — Exact Integer Streak Path + Pre-Streak-Cap Rework (IMPL, batched diff)

- [x] **STREAK-01**: The manual + afking `subStreakLatch` streak base feeds `_playerActivityScore` through a single exact integer path (no residual fractional/bps intermediate), preserving the afking-XOR-manual semantics of `_effectiveQuestStreak`.
- [x] **STREAK-02**: The way the carried-in pre-streak is capped/snapshotted into the afking run is reworked per DESIGN-02 — the current cap shape is replaced with the cleaner handling; the `DegenerusQuests` streak source and its `pendingFlip` accrual (`~:1779`) remain consistent with the new path.

### PACK — pendingFlip Narrowing + Accumulator Repack (IMPL, batched diff)

- [x] **PACK-01**: `Sub.pendingFlip` is narrowed to the DESIGN-03 width with its saturating clamp re-pinned to the new ceiling, the 72-bit accumulator slot is repacked, no other field's value-range is violated, and the Game stays under the EIP-170 deployed-bytecode ceiling (re-checked) with no unexpected storage-slot collision.

### TST — Prove the Floor, the Streak Path, the Clamp & the Equivalence

- [x] **TST-01**: Tests prove the quest-streak floor rule and the exact integer streak-base path — the floored point contribution matches DESIGN-01 at representative streak levels (incl. the boundaries where the old 0.5-pt granularity used to round), and the manual/afking combine is exact (fails-without / passes-with the new path).
- [x] **TST-02**: Tests prove the reworked pre-streak-cap-into-afking handling and the `pendingFlip` clamp — the carried-in pre-streak caps/snapshots per DESIGN-02, and `pendingFlip` saturates at the new ceiling (a value above the narrowed width clamps, not overflows).
- [x] **TST-03**: Tests prove the consumer behaviour-equivalence — the Degenerette ROI, the Lootbox EV multiplier, and the Decimator outcome at point-domain scores match the intended (pre-change) outcomes across the threshold anchors and the whole-point grid, confirming the coarser grid does not shift results.

### REAUDIT — Re-Run the v68 Detection Nets on the Reset Subject

- [x] **REAUDIT-01**: The storage-layout golden is recaptured for the new subject and the ~30 slot-hardcoded test harnesses are migrated/re-pinned, with the MECH-02 layout-diff oracle green on the new layout (the expected slot move from the accumulator repack is the new golden, not an unexpected drift).
- [x] **REAUDIT-02**: The RNG-freeze proof is re-run on the new subject — every VRF/RNG consumer that reads the activity score (lootbox EV / Degenerette / decimator) is re-attested frozen-at-commitment, with the activity-score snapshot-at-deposit freeze (the anti-gaming knob) explicitly re-confirmed under the point-domain representation; any ledger entry whose anchors moved is updated.
- [x] **REAUDIT-03**: The mutation campaign is re-run / triaged on the changed modules and the deep-invariant + Halmos nets are confirmed green on the new subject — the v68 layout/CI/mutation harness is re-pinned to the new subject; survivors are triaged oracle-hole vs. robustness (a documented carry of the still-running mutation tail is an acceptable disposition, consistent with the v68 close).

### TERMINAL — Evidence Pack + Closure

- [x] **TERMINAL-01**: A canonical evidence pack `audit/FINDINGS-v69.0.md` (+ HTML report in the prior house style) records the design-lock decisions, the equivalence analysis verdict, the TST results, and the re-audit outcomes (layout golden, RNG-freeze re-attest, mutation/invariant status); the closure signal `MILESTONE_V69_AT_HEAD_<sha>` is recorded, the activity-score interaction re-audit is confirmed clean, and the subject is confirmed byte-frozen at the IMPL diff (the only `contracts/*.sol` change in the milestone). chmod 444 the canonical findings doc (house convention).

## v2 Requirements

Deferred — not in this milestone's roadmap.

- **`:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard** + **423 rotation-timer hardening** — USER-deferred LOW defense-in-depth carried from v67/v68 (recoverable under the honest-admin assumption, not a brick). Separate contract changes on an unrelated surface; bundling them into the v69 activity-score diff would widen the equivalence/re-audit story. Out of scope unless the USER opts to fold them into the IMPL diff.

## Out of Scope

| Item | Reason |
|------|--------|
| Any contract LOGIC change outside the activity-score / streak / accumulator surface | v69 is a bounded precision/packing change; unrelated edits widen the re-audit blast radius |
| Narrowing `lootboxRngPendingFlip` (uint40, `~Storage:1527`) | Separate field from `Sub.pendingFlip`; DESIGN-03 only confirms it is distinct |
| Re-running the full manual audit hunt | Saturated across v62–v67 (0 CAT / 0 HIGH); v69 re-audit re-runs the v68 machine nets on the changed surface + the activity-score interaction, not a fresh manual sweep |
| The carried `:1843`/`:1850` `==0` guard + 423 rotation-timer hardening | LOW defense-in-depth, USER-deferred; → v2 unless the USER folds them in |
| SEED-001 century quest-streak shield | Already shipped in v64.0 (`682b6afa`); the stale seed file was deleted at v69 init |
| New feature work / gas optimization beyond the accumulator repack | Out; security is the hard floor and the repack is the only packing change |
| Admin / governance malice | Honest-admin assumption stands; key-compromise out of scope |
| Pushing any contract change without review | Standing rule — manual diff review + approval before any `contracts/*.sol` commit/push |

## Traceability

Each requirement maps to exactly one phase. v69.0 phases continue 434 → 435. Not reset.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DESIGN-01 | 435 DESIGN | Done (design-locked `435-DESIGN-LOCK.md`) |
| DESIGN-02 | 435 DESIGN | Done (design-locked `435-DESIGN-LOCK.md`) |
| DESIGN-03 | 435 DESIGN | Done (design-locked `435-DESIGN-LOCK.md`) |
| DESIGN-04 | 435 DESIGN | Done (design-locked `435-DESIGN-LOCK.md`) |
| POINTS-01 | 436 IMPL | Done (`c4b09267`) |
| POINTS-02 | 436 IMPL | Done (`c4b09267`) |
| STREAK-01 | 436 IMPL | Done (`c4b09267`) |
| STREAK-02 | 436 IMPL | Done (`c4b09267`) |
| PACK-01 | 436 IMPL | Done (`c4b09267`) |
| TST-01 | 437 TST | Done (`ActivityScorePointFloor.t.sol` 4/4) |
| TST-02 | 437 TST | Done (`StreakSnapshotAndPendingFlipClamp.t.sol` 5/5 + `testGas04` golden) |
| TST-03 | 437 TST | Done (`ConsumerPointEquivalence.t.sol` 5/5) |
| REAUDIT-01 | 438 REAUDIT | Done (layout oracle green; harnesses re-pinned) |
| REAUDIT-02 | 438 REAUDIT | Done (freeze re-attested; consumers point-domain) |
| REAUDIT-03 | 438 REAUDIT | Done (suite 934/0; mutation carry) |
| TERMINAL-01 | 439 TERMINAL | Done (FINDINGS-v69.0 + HTML + closure signal) |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16 ✓ (1 requirement → exactly 1 phase; no orphans, no duplicates)
- Unmapped: 0 ✓
- Phases: 5 (435 DESIGN · 436 IMPL · 437 TST · 438 REAUDIT · 439 TERMINAL)

---
*Requirements defined: 2026-06-19 — grounded in `.planning/PLAN-V69-ACTIVITY-SCORE-POINTS.md` (the USER design seed: the three asks + the touch-surface scan) and the v68 closure subject `3cc51d00` / `contracts/` tree `e9a5fc24`. The IMPL diff (436) bundles POINTS + STREAK + PACK as ONE batched, USER-approved contract change.*
