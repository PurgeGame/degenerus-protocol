---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: 04
subsystem: gas-calibration
tags: [gas, keeper-router, break-even-peg, CR-01, faucet-floor, level-invariance, stall-ladder, BOUNTY_ETH_TARGET, RESOLVE_FLAT_BURNIE, doc-only]

# Dependency graph
requires:
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    plan: 01
    provides: "the four measured N>=32 worst-case marginals (buy 40,224 / open 89,287 / advance 210,689 / dispatch 228,084 gas) — the calibration input"
  - phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
    provides: "the D-07 flat-per-tx model + ratios + OPEN_KNEE + the >=3 non-WWXRP resolve gate this plan calibrates"
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the committed 63bc16ca tree — the file:lines (AfKing.sol:847-854 + DegenerusGame.sol:1543) re-verified this plan"
provides:
  - "331-CALIBRATION.md — the proposed exact values for the 5 frozen AfKing constants + RESOLVE_FLAT_BURNIE (all CONFIRMED at placeholder) + the BOUNTY_ETH_TARGET deploy-param ceiling recommendation"
  - "the per-leg faucet-floor round-trip <= 0 proof at 0.5 gwei ref + real gas; the arithmetic level-invariance proof; the GAS-04 NO-EXTENSION stall-ceiling decision"
  - "the exact (comment-only / NO-OP) 331-05 frozen-contract diff"
affects: [331-05-contract-gate, 332-TST, 333-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "break-even peg = marginal_gas * 0.5gwei / reward_ratio (per-leg ceiling on the shared deploy-param)"
    - "single shared `unit` + per-category ratios: reimburse one leg at break-even, others deliberately under-reimbursed (anti-faucet)"
    - "stall-multiplier one-shot test: advance is one rewardable call per day-move => 6x is not a loopable self-crank faucet"

key-files:
  created:
    - ".planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/331-CALIBRATION.md"
  modified: []

key-decisions:
  - "All 5 frozen AfKing constants (DOWORK_BATCH=100 / ADVANCE_RATIO_NUM=2 / BUY_RATIO 3,2 / OPEN_KNEE=5) + RESOLVE_FLAT_BURNIE=1e18 CONFIRMED at their placeholder values — the measured N>=32 marginals support them; the 331-05 frozen-contract diff is comment-only (values byte-identical) or a clean NO-OP"
  - "BOUNTY_ETH_TARGET (deploy-param immutable, NOT a frozen constant) SURFACED-NOT-GATED: recommended production ceiling <= 8,778,708,333,333 wei (the advance-6x @0.5gwei-ref round-trip <= 0 bind); current fixture 885,000,000 is ~14,000x below (under-incentivizes, NOT a faucet) — identical disposition to the 319 precedent"
  - "GAS-04 stall ceiling: NO EXTENSION above the 2h tier — the 6x reference-price over-reimbursement (1.53x at 0.5 gwei) is a ONE-SHOT (one rewardable advance per day-move, un-fakeable, round-trip <= 0 at >=1 gwei market), so a higher tier adds no liveness benefit; 1/2/4/6 confirmed ADVANCE-ONLY, thresholds never lowered"
  - "RESOLVE_FLAT_BURNIE anti-exploit basis is the BET-STAKE GATE (not the resolve gas): a self-resolver must first place >=3 losing Degenerette bets (real -EV stake) to harvest 1 BURNIE; the narrow milestone+sub-2gwei reference corner is structurally dominated by the stake and WWXRP gate-exclusion (AUTO-04)"
  - "Exploitability judged vs REAL prevailing gas (5-50+ gwei) + flip-credit illiquidity, NOT the 0.5 gwei reference (feedback_bounty_exploit_uses_real_gas_not_peg_ref — USER-corrected twice in Phase 329)"

patterns-established:
  - "Calibration-record analog to 319-GAS-06-CALIBRATION.md, one phase up for the v49 router (derive -> per-leg faucet floor -> per-constant decision table -> surfaced deploy-param ceiling -> exact gated diff)"

requirements-completed: [GAS-02, GAS-04]

# Metrics
duration: ~30min
completed: 2026-05-27
---

# Phase 331 Plan 04: Break-Even @0.5gwei Peg Calibration Summary

**Converted the 331-01 measured N>=32 worst-case marginals (buy 40,224 / open 89,287 / advance 210,689 gas) into the proposed exact values for the five frozen AfKing peg constants + RESOLVE_FLAT_BURNIE — all CONFIRMED at their placeholder literals (`100` / `2` / `3,2` / `5` / `1e18`) by the per-item MARGINAL faucet-floor proof — plus the BOUNTY_ETH_TARGET deploy-param ceiling recommendation (`<= 8.78e12` wei), the arithmetic level-invariance proof, and the GAS-04 NO-EXTENSION stall-ceiling decision; the exact 331-05 diff is comment-only / NO-OP.**

## Performance

- **Duration:** ~30 min
- **Started:** 2026-05-27
- **Completed:** 2026-05-27
- **Tasks:** 2
- **Files modified:** 1 (created; zero `contracts/*.sol`)

## Accomplishments

- **Re-verified every calibration target's file:line against the live `63bc16ca` tree** (the 330 IMPL shifted lines/slots — the planning frontmatter's `AfKing.sol:847-854` + `DegenerusGame.sol:1543` are correct against current source: `DOWORK_BATCH` @847, `ADVANCE_RATIO_NUM` @849, `BUY_RATIO_NUM/DEN` @851-852, `OPEN_KNEE` @854, `RESOLVE_FLAT_BURNIE` @1543, `BOUNTY_ETH_TARGET` immutable @261 set @277, conversion @870).
- **Derived the per-leg break-even ceiling** on `BOUNTY_ETH_TARGET` from the N>=32 marginals at the 0.5 gwei reference (`marginal_gas * 0.5gwei / reward_ratio`): buy 12.66e12 (binding non-escalated), open 44.64e12, advance-1x 52.67e12, advance-6x 8.78e12 (the overall bind). Proved round-trip <= 0 on every leg at the 0.5 gwei reference AND at real 1/5/50 gwei market gas.
- **Confirmed all 5 frozen AfKing constants + RESOLVE_FLAT_BURNIE at their placeholder values** — the measured relative marginals (buy:open:advance = 1.0:2.2:5.2) support the 1.5/1.0/2.0 reward ratios + OPEN_KNEE=5, and the bet-stake gate supports `RESOLVE_FLAT_BURNIE=1e18`. The 331-05 frozen-contract diff is therefore comment-only (strike the `GAS-331 PLACEHOLDER` markers, values byte-identical) or a clean NO-OP.
- **Surfaced `BOUNTY_ETH_TARGET` (deploy-param, NOT gated):** recommended production ceiling `<= 8,778,708,333,333 wei`; flagged the fixture `885,000,000` as ~14,000x below the ceiling (under-incentivizes the keeper, not a faucet risk) — the identical disposition to the 319 precedent.
- **Proved level-invariance arithmetically (GAS-04):** `mp` cancels in `ratio*unit*mp/PRICE_COIN_UNIT = ratio*BOUNTY_ETH_TARGET`, worked across 3 levels (0.01 / 0.08 / 0.24 ETH), all recovering `B` exactly under EVM floor-division.
- **Made the GAS-04 stall-ceiling decision from the GAS data: NO EXTENSION** — the 6x peak's 1.53x reference-price over-reimbursement is a ONE-SHOT (one rewardable advance per day-move, un-fakeable on demand, round-trip <= 0 at >=1 gwei market gas), so a higher tier adds no liveness benefit. 1/2/4/6 confirmed ADVANCE-ONLY; thresholds never lowered; any future tier faucet-pool-capped.

## Task Commits

1. **Task 1: Derive the proposed constants + break-even unit from the measured marginals** — `def382f0` (docs)
2. **Task 2: Prove level-invariance + decide the stall ceiling (GAS-04)** — `730f18f8` (docs)

## Files Created/Modified

- `.planning/phases/331-.../331-CALIBRATION.md` — the calibration decision record: the conversion + CR-01 rule (§0), the gated-vs-surfaced distinction (§1), the ratio-vs-relative-marginal analysis (§2), the per-leg faucet-floor round-trip <= 0 proof (§3), the 6x one-shot / stall-ceiling decision (§4), the BOUNTY_ETH_TARGET ceiling recommendation (§5), the arithmetic level-invariance proof (§6), the RESOLVE_FLAT_BURNIE bet-stake-gate analysis (§7), the per-constant decision table + exact 331-05 diff (§8), the 331-05 gate summary (§9), and the Task-2 GAS-04 attestation (§10).

## Decisions Made

- **All gated constants CONFIRMED, not re-proposed.** Unlike 319 (which moved both `*_GAS_UNITS` to OUTCOME B), the 330 IMPL placeholders were chosen correctly: the measured marginals support `100/2/3,2/5/1e18`. The 331-05 frozen-contract diff is comment-only or NO-OP — NO value change → NO test-mirror sync needed (the 4 mirror files stay green).
- **BOUNTY_ETH_TARGET surfaced, not autonomously tuned** — it is an economic/keeper-incentive deploy-param (the faucet ceiling is the GAS deliverable; the incentive target is the USER's choice), and the production deploy lives in the paired `degenerus-utilities` repo, not the test fixture.
- **The binding ceiling is the advance-6x leg** (8.78e12 wei), tighter than the buy leg (12.66e12), because the 12x multiplier stacks on the advance ratio — but the 6x is a one-shot, not a loopable faucet (§4).
- **RESOLVE_FLAT_BURNIE's anti-exploit floor is the bet-stake gate, not the resolve gas** — every self-resolve farm is net-negative because the farmer first pays >=3 losing-bet stakes; the narrow milestone+sub-2gwei reference corner is structurally dominated.

## Deviations from Plan

None - plan executed exactly as written. The plan anticipated "validate or re-propose the current placeholders"; the validation outcome is CONFIRM-all (the placeholders are correct), which the plan explicitly permits ("if the measured marginals support them, confirm").

## Issues Encountered

- The plan/PATTERNS frontmatter cited `AfKing.sol:847-854` + `DegenerusGame.sol:1543`; these were re-verified against the live `63bc16ca` source (not trusted from stale planning) and confirmed correct. No line-drift correction needed this plan.

## User Setup Required

None - doc-only plan; no external service configuration; no `contracts/*.sol` touched; no forge build needed (no code edited). The arithmetic was sanity-checked step-by-step against the source conversion formula.

## Next Phase Readiness

- **331-05 (the `autonomous: false` USER gate):** the exact diff is specified in 331-CALIBRATION.md §8 — comment-only (strike `GAS-331 PLACEHOLDER` markers, values byte-identical) or a clean NO-OP on `contracts/*.sol`. The five frozen constants + `RESOLVE_FLAT_BURNIE` keep their literal values, so no test-mirror sync is required. `BOUNTY_ETH_TARGET` is surfaced for the USER as a deploy-param economic choice (recommended ceiling `<= 8.78e12` wei).
- **Contract-boundary HARD STOP reminder:** 331-05 is the SECOND v49 USER-approval gate; this plan touched NO `contracts/*.sol` (`git diff --name-only -- contracts/` empty). Per `feedback_pause_at_contract_phase_boundaries`, hold for USER direction before 331-05 even though it is comment-only.
- **TST 332 readiness:** the empirical level-invariance assertion (the `SweepPerPlayerWorstCaseGas.t.sol:188-211` shape-insensitivity idiom) + the WR-01 round-trip faucet guard (`CrankFaucetResistance`) are owned by 332/the separate GAS-05 plan, not here.
- No blockers.

## Self-Check: PASSED

- `.planning/phases/331-.../331-CALIBRATION.md` — FOUND
- `.planning/phases/331-.../331-04-SUMMARY.md` — FOUND
- Commit `def382f0` (Task 1 docs) — FOUND
- Commit `730f18f8` (Task 2 docs) — FOUND
- Task 1 verify grep (DOWORK_BATCH|ADVANCE_RATIO_NUM|OPEN_KNEE|RESOLVE_FLAT_BURNIE|BOUNTY_ETH_TARGET) — PASS
- Task 2 verify grep (level-invarian|stall|1/2/4/6|ceiling) — PASS
- `git diff --name-only -- contracts/` for this plan's changes — EMPTY (no contract mutation)

---
*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca*
*Completed: 2026-05-27*
