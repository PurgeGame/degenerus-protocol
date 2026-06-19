---
phase: 440
phase_name: "VERIFY — Review the Working-Tree Reshape Against the Locked Design"
milestone: v70.0
status: passed
verified: 2026-06-19
method: "Claude adversarial workflow (8 independent dimension verifiers + completeness critic + per-gap adversarial confirmation) + empirical forge build/sizes + targeted equivalence suites"
subject: "working tree (uncommitted) — contracts reshape vs locked design .planning/PLAN-ACTIVITY-CURVE-RESHAPE.md"
contract_commit: none (gate is phase 441 FREEZE)
---

# Phase 440 VERIFY — Verification Report

**Verdict: PASSED — 0 confirmed defects.** The already-written consumer-curve reshape
(`ActivityCurveLib` + 6 modified contracts) is confirmed correct against the locked design on every
axis the phase required: the five value curves, the bucket ladder + exact inverse, the pre-clamp
removal + full consumer migration, and the build/bounds/solvency envelope.

## Method

- **Adversarial verification workflow** (`.planning/wf-verify-v70.mjs`, run `wf_2b344f47-da6`): 8 independent
  verifiers (one per curve / ladder+inverse+delegation / migration-sweep / bounds), each re-deriving the locked
  numbers from scratch and recomputing the code with Solidity truncating integer arithmetic; a completeness critic
  that independently re-ran every check and swept for missed read-sites; adversarial confirmation of every flagged
  item. Result: **8/8 dimensions MATCHES, critic any_uncovered=false, 0 confirmed defects.**
- **Empirical ground truth** (orchestrator): `forge clean && forge build --sizes` (via_ir) exit 0; the three dirty
  oracle suites re-run.

## Requirement-by-requirement

### VERIFY-01 — value curves ✅
All five 3-segment piecewise curves match the locked formulas, knees (K, seg-B 500, cap 30000) and waypoints, are
monotonic non-decreasing over the full hard-cap domain, continuous at every knee, and byte-identical to the prior
MAX at the cap:
- **decimator/terminal multiplier** `ActivityCurveLib.decMultBps` — 0→10000 (s==0 1.0x no-op preserved + honored
  downstream by the `multBps <= BPS_DENOMINATOR` short-circuit), 235→17049, 305→17214, 500→17676, 30000→17833.
  MAX 17833 is byte-identical to the OLD saturated max (`10000 + 235*100/3`).
- **Degenerette ROI** `_roiBpsFromScore` — 0→9000, 305→9891, 500→9970, 30000→9990. **Solvency invariant: strictly
  < 10000 globally** (max 9990).
- **WWXRP high ROI** `_wwxrpHighValueRoi` — 0→9000, 305→10791, 500→10950, 30000→10990.
- **century** `ActivityCurveLib.centuryBps` — 0→0, 305→9000, 500→9800, 30000→10000.
- **lootbox EV** `_lootboxEvMultiplierFromScore` — 0→9000, 60→10000 (0..60 neutral anchor byte-identical to HEAD),
  400→13950, 500→14390, 30000→14500; vA/vB derived from the full (9000,14500) range (USER decision #4).

### VERIFY-02 — bucket ladder + inverse + no-drift wiring ✅
- `decBucket` implements the absolute ladder `12@0 … 2@1000` (all 11 rungs match); per-path floor clamp correct
  (normal 5 / century 2 / terminal-dec 2).
- `minScoreForBucket` is the exact band-floor inverse (`2→1000 … 12→0`); round-trip `decBucket(minScoreForBucket(b))==b`
  for b in 2..12, and `decBucket(T-1)` lands one bucket worse at every threshold T. It seals the decimator-claim
  lootbox EV score (DecimatorModule `_minScoreForBucket` wrapper → `minScoreForBucket`, call site :412).
- FLIP and DecimatorModule both delegate to the single lib (`decMultBps`/`decBucket`); the old local bodies
  (`_decimatorBurnMultiplier`, `_adjustDecimatorBucket`, old `_minScoreForBucket` arithmetic) are deleted — no
  drift-prone duplicated body.

### VERIFY-03 — pre-clamp removal + full consumer migration (the v69 failure class) ✅
- All six §1 pre-clamp sites removed (FLIP, Decimator ×2, Degenerette ×2, Mint, Afking) so the s≥30000 MAX branch
  is reachable; the raw score (bounded by the 65534 hard cap) flows straight into the curves.
- `git grep` confirms **zero** residual references to the removed stale constants (`ACTIVITY_SCORE_MID_POINTS`,
  `ACTIVITY_SCORE_HIGH_POINTS`, `ROI_MID_BPS`, `ROI_HIGH_BPS`), **zero** orphaned per-site cap/base constants, and
  **zero** old saturated arithmetic (`*100/3`, `/235`, `/305`, `>235`, `>305`).
- Full read-site sweep clean. The completeness critic additionally verified **4 lootbox-EV call sites the first
  sweep under-counted** (Lootbox:566, Mint:1785, Whale:893, Afking:1018 — the frozen-prior-score subsequent-deposit
  paths) all route through the reshaped `_lootboxEvMultiplierFromScore` with `LOOTBOX_EV_BENEFIT_CAP` intact. The
  v69 incomplete-migration class is swept clean.

### VERIFY-04 — build + bounds ✅
- `forge build` exit 0, 0 hard errors (only pre-existing forge-lint advisories at unrelated unpack/typecast sites).
- `ActivityCurveLib` storageless — only `internal constant` + `internal pure`; 57-byte stub (fully inlined, not
  separately deployed).
- **EIP-170:** DegenerusGame 20,388 (4,188 headroom — identical to the v69 baseline; Game did not grow), FLIP 7,668
  (16,908 headroom); every changed module under the 24,576 ceiling (tightest = MintModule 23,460 / 1,116).
- Read-side gas: the curves are straight-line branch ladders — no loops, no new SLOADs in the hot paths.
- `advanceGame` 16.7M ceiling NOT implicated: no curve fn is invoked inside the advance loop (the reshape is
  read-side, settled on player actions).
- Solvency caps unchanged vs old: ROI < 10000, lootbox EV ≤ 14500 gated by `LOOTBOX_EV_BENEFIT_CAP`, century ≤ 100%
  ETH-capped (20-ETH maxBonus at both Mint and Afking), multiplier ≤ 17833.

## Empirical test evidence

Three dirty oracle suites re-run: **16/16 PASS** — `ConsumerPointEquivalence` 9/9, `DegeneretteHeroScore` 6/6,
`V69ConsumerMigrationFixes` 1/1. The golden mult/century arrays assert directly against `ActivityCurveLib` and match
the recomputation; the V69 migration suite correctly **dropped its 4 old-shape oracle tests** (which asserted the
pre-reshape curves and would now be false) while keeping the unrelated affiliate-taper test.

## Gap-fix applied to the working tree (autonomous; no commit)

- **Two stale NatSpec comments** in `DegenerusGameDecimatorModule.sol` (:157, :627) named the deleted
  `FLIP._adjustDecimatorBucket` helper → updated to reference `ActivityCurveLib.decBucket`. Comment-only, no
  bytecode change. This is the only orchestrator edit on top of the original reshape.

## INFO / carries (none blocking)

- **Test-oracle strength (→ TST phase 442):** the roi/wwxrp/lootbox-EV golden waypoints assert against the test's
  own local re-implementation rather than calling the (private) module bodies directly. The critic verified the
  re-impls are byte-faithful, so the oracle is sound today, but a future divergence in a module body would not be
  caught. 442 should add direct-call coverage for these three curves.
- **Event value-shift (indexer / off-chain parity):** by design (locked-design §7), the VALUES carried by
  `DecimatorBurn.bucketUsed`, `DecBurnRecorded.{bucket,effectiveAmount}`, `TerminalDec*.bucket`, `BetPlaced`→settled
  ROI/WWXRP, `FullTicketResolved` payouts, and `LootBoxOpened.{futureTickets,flip}` shift; no signature/storage
  change. Indexer reconstruction tables must be re-vendored. Record in the TERMINAL evidence pack (444).
- forge-lint advisories (incorrect-shift / unsafe-typecast / divide-before-multiply) are all pre-existing, at sites
  unrelated to the reshape; build is clean.

## Disposition

The reshape is correct and within bounds. **No contract commit happens in this phase** — the sole gate is phase
441 FREEZE (the one batched `contracts/*.sol` diff for USER approval). The working tree (6 modified `.sol` + the new
`ActivityCurveLib.sol` + the 2 comment fixes) is ready to present for that approval.
