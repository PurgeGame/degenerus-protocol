# Requirements: Degenerus Protocol — v70.0 Activity-Score Consumer-Curve & Bucket Reshape (Verify + Re-Audit)

**Defined:** 2026-06-19
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Milestone goal:** Reshape the *consumer mappings* of the player activity score so the high end is reserved for long quest streaks — steep early ramp, near-flat long tail, MAX outputs byte-identical to today (no payout change). The activity score (now whole points, v69) scales the lootbox EV multiplier, the Degenerette ROI / WWXRP curves, the decimator burn multiplier + bucket, and the century mint/afking bonus; this milestone moves all of them to a 3-segment piecewise value-curve family (`vA = MIN + 90%·(MAX−MIN)` at the old cap `K`, `vB = MIN + 98%` at score 500, `MAX` at score 30,000 / flat beyond) and replaces the linear bucket reduction with an absolute threshold ladder (`12@0 … 2@1000`, floor-clamped per path) plus its exact band-floor inverse. **The implementation is already written in the working tree** — a new shared pure lib `contracts/libraries/ActivityCurveLib.sol` (the duplicated dec/term multiplier + bucket ladder + inverse) plus inline reshapes in the Degenerette module (ROI/WWXRP) and Storage (lootbox EV), across 6 modified contracts. The milestone **verifies** that diff against the locked design, **freezes** it behind the contract-commit gate, **proves** it with tests, and **re-runs** the v68/v69 detection nets on the reset subject.
**Method:** VERIFY (review the working-tree diff against the locked design; build + EIP-170/gas; core equivalence checks; fix any gaps in-tree) → FREEZE (ONE batched contract diff, USER-approved, committed — the sole gate) → TST (curve/ladder/inverse/reachable-tail proof) → REAUDIT on the reset subject → TERMINAL. MAX outputs stay byte-identical; the only behavioural change is the *shape* of the ramp between MIN and MAX (the score-235 burner softens 1.783x→1.705x; the old MAX now requires score 30,000 — a near-maximal lifetime quest streak — which is the intended consequence of the locked MAX-at-30k design). Security / RNG-non-manipulability stays the hard floor.
**Subject:** Baseline = the v69.0 closure subject — `contracts/` tree `8a633d1d` at HEAD `3f024cc8` (closure `MILESTONE_V69_AT_HEAD_7d0fa2c6b16bf4b0291fe5b1edb7560cf7641d45`). The reshape sits **uncommitted in the working tree** at milestone start (6 modified `.sol` + the new `ActivityCurveLib.sol`); the FREEZE commit (441) produces the new v70 subject, byte-frozen for all re-audit work.
**Posture:** Contract LOGIC change (consumer-curve reshape). It **RESETS the v69 audit subject** — the RNG-freeze proof, the storage-layout golden, and the mutation results are pinned to `8a633d1d` and must be re-run on the new code (the v68/v69 methodology carries forward; the reshape is read-side / logic-only, so the storage layout is expected unchanged). The reshape ships as ONE batched diff behind the standard contract-commit approval gate (the sole gate); all verification / test / tooling / proof / re-audit additions commit autonomously. Leave `git push` to USER.
**Locked design (USER, 2026-06-19):** the 3-segment value curves with MIN/MAX byte-identical (no payout change); the absolute bucket ladder `12@0,11@10,10@30,9@55,8@85,7@120,6@180,5@250,4@300,3@500,2@1000` clamped up to each path's floor; the per-site 235/305 pre-clamps **removed** (curves self-saturate; the 65,534 hard cap is the only global bound); the dec/term multiplier + bucket ladder in **one shared pure lib** to guarantee FLIP↔Decimator parity; the bucket kink at 5↔4 **left** (bucket 5 is a natural plateau); lootbox `vA/vB` derived from the full `(9000,14500)` range; `_minScoreForBucket` inverse uses each band's floor `T(b)`.
**Assumptions:** Honest admin / governance (admin malice out of scope). Pre-launch, no live funds.

## v1 Requirements

Requirements for this milestone. Each maps to exactly one roadmap phase.

### VERIFY — Review the Working-Tree Reshape Against the Locked Design (no new design)

- [x] **VERIFY-01**: Every value curve matches the locked formula and endpoints — the five 3-segment piecewise value curves (decimator + terminal-dec multiplier [shared `ActivityCurveLib.decMultBps`], Degenerette ROI, WWXRP high ROI, century mint/afking bonus [shared `ActivityCurveLib.centuryBps`], lootbox EV [inline `DegenerusGameStorage`]) carry the locked constants/knees (`K`, seg-B knee 500, effective cap 30,000), each curve's value at its cap is byte-identical to the prior named MAX, each is monotonic non-decreasing over `[0, 30000]` and continuous at both knees, and the decimator `s==0 → 1.0x` no-op is preserved.
- [x] **VERIFY-02**: The bucket ladder + inverse + no-drift wiring match the locked tables — `ActivityCurveLib.decBucket` implements the absolute threshold ladder (`12@0 … 2@1000`) with the correct per-path floor clamp (normal decimator floor 5 / century floor 2, terminal-dec floor 2), `ActivityCurveLib.minScoreForBucket` is the exact band-floor inverse (`2→1000 … 12→0`) consistent with the forward ladder and feeds the decimator-claim lootbox EV correctly, and both FLIP.sol and DegenerusGameDecimatorModule.sol delegate to the single lib with no duplicated body that could drift.
- [x] **VERIFY-03**: Every §1 pre-clamp is removed and every consumer call-site is migrated — the six per-site 235/305 pre-clamp sites (FLIP, Decimator ×2, Degenerette ×2, Mint, Afking) are removed so the high end is reachable, no consumer still reads the score through the old saturated arithmetic, and there is no residual stale-constant or un-migrated consumer (the v69 incomplete-migration failure class is explicitly swept for across all activity-score read-sites).
- [x] **VERIFY-04**: The reshape builds and stays within bounds — `forge build` is clean, the new `ActivityCurveLib` carries no storage, the `DegenerusGame` (and `FLIP`) stay under the EIP-170 deployed-bytecode ceiling with the added piecewise branches, there is no gas regression on the read-side consumer paths (decimatorBurn / placeBet / lootbox-open / century), and the `advanceGame` 16.7M ceiling is confirmed not implicated (the reshape is read-side, not in the advance loop).

### FREEZE — Batched Contract Diff Approval + Commit (the sole gate)

- [x] **FREEZE-01**: The complete reshape (the new `ActivityCurveLib.sol` + the six modified contracts + any VERIFY in-tree gap-fixes) is presented as ONE consolidated diff for USER hand-review, approved, and committed as the single `contracts/*.sol` change of the milestone; the new v70 subject is byte-frozen at that commit for all downstream test + re-audit work, and the diff is confirmed to contain no edits outside the activity-score consumer-curve surface.

### TST — Prove the Curves, the Ladder, the Inverse & the Reachable Tail

- [x] **TST-01**: Tests prove each value curve's endpoints + shape — value-at-cap byte-identical to the old named MAX, the previously-uncovered seg-B (500) and seg-C (30,000) anchors, continuity at both knees, monotonic non-decreasing over `[0, 30000]`, and the decimator `s==0 → 1.0x` no-op; the prior equivalence oracle (`ConsumerPointEquivalence`, `V69ConsumerMigrationFixes`, `DegeneretteHeroScore` mirror) is rewritten from the OLD formulas to the new ones.
- [x] **TST-02**: Tests prove the bucket ladder + inverse — every threshold crossing (10/30/55/85/120/180/250/300/500/1000), the normal-decimator floor-5 and century floor-2 paths, the terminal-dec floor-2 path, and `minScoreForBucket` exactness checked against the forward `decBucket` ladder across the band boundaries.
- [x] **TST-03**: Tests prove the pre-clamp removal made the tail reachable + the shared-helper parity — score 1000 → bucket 2 (century/terminal) and score 30,000 → MAX for each value curve (the bug the read-only investigation caught: the tail was unreachable while the 235/305 clamps were in place), and Mint and Afking produce an identical century bonus for an identical score (single shared `centuryBps` helper, no divergence).

### REAUDIT — Re-Run the v68/v69 Detection Nets on the Reset Subject

- [x] **REAUDIT-01**: The storage-layout golden is recaptured for the new subject and the slot-hardcoded harnesses re-pinned, with the MECH-02 layout-diff oracle green on the new layout — the reshape is read-side / logic-only and the new `ActivityCurveLib` is a pure library carrying no storage, so the expectation is **no slot move**; any layout delta is investigated as an unexpected drift, not silently re-goldened.
- [x] **REAUDIT-02**: The RNG-freeze proof is re-attested on the new subject — every VRF/RNG consumer that reads the activity score (lootbox EV, Degenerette ROI/WWXRP spins, decimator claim) is re-confirmed frozen-at-commitment under the new curves, with the activity-score snapshot-at-deposit freeze (the anti-gaming knob) explicitly re-confirmed; any freeze-proof ledger anchor whose `file:line` moved with the reshape is updated.
- [x] **REAUDIT-03**: The mutation campaign is re-run / triaged on the changed modules + the new `ActivityCurveLib`, and the deep-invariant + Halmos nets are confirmed green on the new subject — the v68/v69 layout/CI/mutation harness is re-pinned to the new subject; survivors are triaged oracle-hole vs. robustness (a documented carry of the still-running mutation tail is an acceptable disposition, consistent with the v68/v69 close).

### TERMINAL — Evidence Pack + Closure

- [x] **TERMINAL-01**: A canonical evidence pack `audit/FINDINGS-v70.0.md` (+ an HTML report in the prior house style) records the VERIFY findings + dispositions, the curve / ladder / inverse / reachable-tail equivalence verdict, the TST results, and the re-audit outcomes (layout golden, RNG-freeze re-attest, mutation/invariant status); the closure signal `MILESTONE_V70_AT_HEAD_<sha>` is recorded, the consumer-curve re-audit is confirmed clean, and the subject is confirmed byte-frozen at the FREEZE diff (the only `contracts/*.sol` change in the milestone). chmod 444 the canonical findings doc (house convention).

## v2 Requirements

Deferred — not in this milestone's roadmap.

- **`:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard** + **423 rotation-timer hardening** — USER-deferred LOW defense-in-depth carried from v67/v68/v69 (recoverable under the honest-admin assumption, not a brick). Separate contract changes on an unrelated surface; bundling them into the v70 consumer-curve diff would widen the equivalence/re-audit story. Out of scope unless the USER opts to fold them into the FREEZE diff.

## Out of Scope

| Item | Reason |
|------|--------|
| Re-anchoring the value-curve multipliers to the bucket's 1000 floor | USER locked "keep the score the same as before" — all five value curves stay on the 90/98/30k knees; only the consumer *shape* changes, MIN/MAX endpoints byte-identical |
| The activity-score COMPUTATION (components, sub-caps, `ACTIVITY_SCORE_HARD_CAP_POINTS = 65,534`) | Untouched — v70 reshapes only the consumer *mappings* of the score, not how the score is produced (that was v69) |
| The affiliate taper | Separate mechanism on the raw score; explicitly not in scope (PLAN §7) |
| Any contract LOGIC change outside the activity-score consumer-curve surface | v70 is a bounded consumer-curve reshape; unrelated edits widen the re-audit blast radius |
| Re-running the full manual audit hunt | Saturated across v62–v67 (0 CAT / 0 HIGH); v70 re-audit re-runs the v68/v69 machine nets on the changed surface + the consumer-curve interaction, not a fresh manual sweep |
| The carried `:1843`/`:1850` `==0` guard + 423 rotation-timer hardening | LOW defense-in-depth, USER-deferred; → v2 unless the USER folds them in |
| New feature work / gas optimization beyond the reshape | Out; security is the hard floor and the curve reshape is the only contract change |
| Admin / governance malice | Honest-admin assumption stands; key-compromise out of scope |
| Pushing any contract change without review | Standing rule — manual diff review + approval before any `contracts/*.sol` commit/push |

## Traceability

Each requirement maps to exactly one phase. v70.0 phases continue 439 → 440. Not reset.

| Requirement | Phase | Status |
|-------------|-------|--------|
| VERIFY-01 | 440 VERIFY | Done |
| VERIFY-02 | 440 VERIFY | Done |
| VERIFY-03 | 440 VERIFY | Done |
| VERIFY-04 | 440 VERIFY | Done |
| FREEZE-01 | 441 FREEZE | Done |
| TST-01 | 442 TST | Done |
| TST-02 | 442 TST | Done |
| TST-03 | 442 TST | Done |
| REAUDIT-01 | 443 REAUDIT | Done |
| REAUDIT-02 | 443 REAUDIT | Done |
| REAUDIT-03 | 443 REAUDIT | Done |
| TERMINAL-01 | 444 TERMINAL | Done |

**Coverage:**
- v1 requirements: 12 total
- Mapped to phases: 12 ✓ (1 requirement → exactly 1 phase; no orphans, no duplicates)
- Unmapped: 0 ✓
- Phases: 5 (440 VERIFY · 441 FREEZE · 442 TST · 443 REAUDIT · 444 TERMINAL)

---
*Requirements defined: 2026-06-19 — grounded in `.planning/PLAN-ACTIVITY-CURVE-RESHAPE.md` (the read-only investigation `wf_58990975-709`, 5 agents) + the USER's 4 design rulings (remove pre-clamps · shared lib · leave the bucket kink · both mechanical defaults as recommended) and the v69.0 closure subject `8a633d1d` at HEAD `3f024cc8`. The reshape was implemented in the working tree before milestone definition; the FREEZE diff (441) is the sole `contracts/*.sol` change.*
