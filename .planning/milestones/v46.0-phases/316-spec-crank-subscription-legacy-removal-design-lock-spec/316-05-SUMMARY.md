---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
plan: 05
subsystem: spec
tags: [jgas, jackpot-eth-split, vrf-freeze, gas-worst-case, design-lock, design-intent]

# Dependency graph
requires:
  - phase: 316-02
    provides: "## Storage Slot-Shift Plan (resumeEthPool slot 33; combined RM-02+JGAS −2 shift for slot ≥ 34) — cross-referenced, not re-derived"
  - phase: 316-RESEARCH
    provides: "§J1 JGAS deletion-footprint verification table, §J2 stage-machine non-load-bearing proof, §J4 design-intent + worst-case-first gas, §J5 VRF/freeze-SAFE verdict"
provides:
  - "316-SPEC.md ## JGAS-01 Decision Gate section: design-intent → worst-case-first gas → locked decision → two-module deletion footprint → VRF/freeze-SAFE verdict"
  - "Locked JGAS-01 decision string verbatim: 'REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented' (305-winner ceiling PRESERVED; mechanism-only)"
  - "Grep-verified JGAS deletion footprint across DegenerusGameJackpotModule + DegenerusGameAdvanceModule (the JGAS-02 Phase-317 IMPL deletion surface)"
affects: [317-IMPL-JGAS-02, 318-TST-JGAS-03, 319-GAS-JGAS-04, 320-AUDIT-JGAS-re-attestation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Design-intent-before-deletion ordering (feedback_design_intent_before_deletion): trace the split's intent + actor game-theory BEFORE locking the deletion shape"
    - "Worst-case-first gas derivation (feedback_gas_worst_case): derive theoretical worst-case single-call 305-winner gas FIRST, then gate finality on empirical measurement"

key-files:
  created:
    - .planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-05-SUMMARY.md
  modified:
    - .planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md

key-decisions:
  - "JGAS-01 locked: 'REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented' — REMOVE makeable at SPEC with a Phase-319 empirical confirmation gate, NOT blocked-until-measurement"
  - "305-winner ceiling PRESERVED — mechanism-only removal; DAILY_ETH_MAX_WINNERS=305 / DAILY_JACKPOT_SCALE_MAX_BPS=63_600 / the 159/95/50/1 bucket derivation are NOT in the deletion set; zero winner-count/bucket-scaling/payout-EV change"
  - "JGAS is freeze-invariant-SAFE: the ETH-resume branch never calls _unlockRng (lock held across the split, same randWord re-consumed in call2); single-call collapses two same-word consumptions to one, _unlockRng placement unchanged, removes a cross-tx resumeEthPool carry (rotation-robustness improvement); residual risk = gas-fits/liveness only"
  - "Stage numbers NOT load-bearing (function-local stage, STAGE_JACKPOT_ETH_RESUME assign+emit only / zero comparisons, Advance event not consumed on-chain) → renumber 9/10/11→8/9/10 OPTIONAL/cosmetic"
  - "Slot-shift consequence cross-referenced to 316-02's ## Storage Slot-Shift Plan (combined −2), NOT re-derived here"

patterns-established:
  - "SPEC decision gate: design-intent → theoretical-worst-case → locked-decision → grep-verified footprint → security-floor verdict, in that load-bearing order"

requirements-completed: [JGAS-01]

# Metrics
duration: ~6min
completed: 2026-05-23
---

# Phase 316 Plan 05: JGAS-01 Decision Gate Summary

**Locked the daily-ETH two-call jackpot-split removal as a SPEC decision gate — design-intent trace, theoretical worst-case-first 305-winner gas (~9-12M vs ~30M, ~2.5-3.3× margin), the verbatim "REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented" decision (305 ceiling preserved, mechanism-only), the grep-verified two-module deletion footprint, and the freeze-invariant-SAFE verdict.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-23T15:56:04Z
- **Completed:** 2026-05-23T16:02:00Z (approx)
- **Tasks:** 1
- **Files modified:** 1 (`316-SPEC.md`)

## Accomplishments

- Appended the `## JGAS-01 Decision Gate` section to `316-SPEC.md` in the load-bearing order required by the project rules: **design intent → worst-case-first gas → locked decision → deletion footprint → VRF/freeze-SAFE verdict** (verified `design-intent line 275 < worst-case 287 < decision 298 < footprint 307 < vrf-verdict 335`).
- Traced the two-call split's design intent FIRST (`feedback_design_intent_before_deletion`): a pure block-gas-ceiling workaround forced by `DAILY_JACKPOT_SCALE_MAX_BPS=63_600 → DAILY_ETH_MAX_WINNERS=305` across buckets 159/95/50/1; threshold `JACKPOT_MAX_WINNERS=160` (`:480`); partition call1=159+1=160 / call2=95+50=145; `resumeEthPool` carries ONLY the `uint128` pool-remainder (everything else re-derived deterministically in call 2 from the held `randWord` via `_resumeDailyEth`); locked the clean precondition that NO correctness/fairness/EV/determinism property is carried by the split (observationally equivalent modulo gas).
- Derived the theoretical worst-case single-call 305-winner gas SECOND (`feedback_gas_worst_case`): ~25-30k per cold winner × 305 ≈ 7.6-9.2M + 1-3M fixed overhead ≈ **9-12M vs ~30M (~2.5-3.3× margin)**; cited the ~1.3M RM-02 frees (the unconditional cold `autoRebuyState` SLOAD ×305) + the observational-equivalence strengthener (single-call ≈ call1 + call2 work − the freed SLOADs); flagged the absolute figure as a ±30% structural estimate (not a measurement) — hence the JGAS-04 gate.
- Locked the decision string VERBATIM: **"REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented"** — 305 ceiling PRESERVED, NO winner-count/bucket-scaling/payout-EV change; REMOVE makeable at SPEC with finality gated on the Phase-319 empirical 305-winner single-call measurement.
- Enumerated + grep-verified the deletion footprint across BOTH modules with the two cosmetic `+1` resume-check drifts recorded (jackpot `:348→349`, advance `:452-455→453-456`); stated the stage numbers are NOT load-bearing.
- Stated the J5 VRF/freeze-SAFE verdict (STATED, not assumed): resume branch never calls `_unlockRng`; single-call collapses two same-word consumptions to one; `_unlockRng` unmoved; no new in-window player-mutable input; removes a cross-tx `resumeEthPool` carry (rotation-robustness improvement); residual risk = gas-fits/liveness only; AUDIT-320 re-attestation charge + `zero-day-hunter` routing.
- Cross-referenced 316-02's `## Storage Slot-Shift Plan` for the combined −2 slot consequence WITHOUT re-deriving any slot.

## Task Commits

1. **Task 1: Author the JGAS-01 Decision Gate section** - `be547e2d` (docs)

**Plan metadata:** committed with SUMMARY + STATE + ROADMAP + REQUIREMENTS in the final docs commit.

## Files Created/Modified

- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` - Appended the `## JGAS-01 Decision Gate` section (+82 lines).
- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-05-SUMMARY.md` - This summary.

## Grep-Verification Ledger (SC#5)

Every cited `file:line` was re-grep-verified against HEAD `MILESTONE_V45_AT_HEAD_62fb514b` on 2026-05-23 before authoring:

| Module | Symbol | Cited | Live | Verdict |
|--------|--------|-------|------|---------|
| JackpotModule | `SPLIT_NONE/CALL1/CALL2` | 197/199/201 | 197/199/201 | ✓ |
| JackpotModule | `JACKPOT_MAX_WINNERS=160` | 219 | 219 | ✓ (dead on removal) |
| JackpotModule | `DAILY_ETH_MAX_WINNERS=305` | 227 | 227 | ✓ (preserved) |
| JackpotModule | `DAILY_JACKPOT_SCALE_MAX_BPS=63_600` | 248 | 248 | ✓ (preserved) |
| JackpotModule | resume-check `if (resumeEthPool != 0)` | 348 | **349** | +1 drift (comment at 348) |
| JackpotModule | `_resumeDailyEth` decl | 1186 | 1186 (call 350) | ✓ |
| JackpotModule | `splitMode` param | 1248 | 1248 (routing 1251/476/480/501) | ✓ |
| JackpotModule | `call1Bucket` mask | 1270-1278 | decl 1270, build 1272/1274/1276, skip 1287-1288 | ✓ |
| JackpotModule | threshold branch | 476-483 | 476-483 (call 493-503) | ✓ |
| JackpotModule | `resumeEthPool` write | ~1347-1348 | 1348 (gated 1347) | ✓ |
| JackpotModule | `resumeEthPool` read+zero | 1252-1253 | 1252-1253 | ✓ |
| JackpotModule | `resumeEthPool` read (`_resumeDailyEth`) | 1201 | 1201 | ✓ |
| AdvanceModule | `STAGE_JACKPOT_ETH_RESUME=8` | 70 | 70 | ✓ |
| AdvanceModule | resume-check block | 452-455 | **453-456** | +1 drift (comment at 452); assign 455 |
| AdvanceModule | `_unlockRng` (resume branch contains none) | — | 467/331/402/629 | ✓ (none in 453-456) |
| Storage | `resumeEthPool` decl | 994 | 994 | ✓ |

Both `+1` drifts are cosmetic doc-vs-`if` offsets; all constants exact-match by value; no MISSING symbols.

## Decisions Made

None beyond the locked JGAS-01 design decisions captured in frontmatter — followed the plan and `316-RESEARCH.md §J1-§J6` substrate exactly.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Self-Check: PASSED

- `316-SPEC.md` exists and contains `## JGAS-01 Decision Gate` — FOUND.
- Commit `be547e2d` exists — FOUND.
- Plan automated verify (all 9 grep checks) — PASS.
- Ordering (intent < worst-case < decision < footprint < vrf) — CORRECT.
- No fenced solidity bodies in the section — CONFIRMED.
- Zero `contracts/` + zero `test/` mutations — CONFIRMED (`git diff --name-only` shows only the SPEC; zero `.sol`/`.t.sol`).

## Next Phase Readiness

- The JGAS-01 SPEC decision gate is locked; it authorizes the JGAS-02 IMPL deletion at Phase 317 (in the same batched USER-APPROVED diff as RM-01..06).
- Downstream owners (not run here): JGAS-02 = Phase 317 IMPL (delete the split); JGAS-03 = Phase 318 TST (305-winner single-call correctness + split grep-clean); JGAS-04 = Phase 319 GAS (empirical 305-winner single-call measurement — the finality gate); Phase 320 TERMINAL delta-audits the split removal + re-attests freeze under single-call + under VRF rotation (`zero-day-hunter`).
- No blockers. Phase 316 plan progress advances to 3/5 → 4/5 complete (316-01, 316-02, 316-05 done); 316-03 (open-item resolution) + 316-04 (call-graph attestation) remain.

---
*Phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec*
*Completed: 2026-05-23*
