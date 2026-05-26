---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 01
subsystem: spec-attestation
tags: [keeper-router, redesign, call-graph-attestation, paper-only, BATCH-01, ROUTER-07, ADV-04, GAS-03]
requires:
  - frozen v48.0-closure HEAD 0cc5d10f (the audit baseline)
  - 330-ROUTER-REDESIGN-INTENT.md (the 5 locked changes + Q1/Q2/Q5 + GASOPT source)
  - 329-CONTEXT.md (RD-1..RD-5, D-07, D-08, D-01a, D-04a)
provides:
  - 329-ATTEST-ROUTER-ADVANCE.md (per-anchor grep tables for the REDESIGNED router + advance surface)
  - Q5 dependent-grep verdict (no other batchPurchase dependent)
  - ROUTER-07 / GAS-03 / ADV-04 / invariant-(c)-D-04a / RD-5-entry-gate verdicts
  - design-1 / discovery-view / KEEP-04 / GASOPT-01 / GASOPT-03/04/05 baseline resolutions
affects:
  - 329-03 (reconciliation + edit-order map consumes these anchors)
  - 330 re-IMPL (the survivors-vs-reworked batched diff applies the attested anchors)
tech-stack:
  added: []
  patterns: [grep-against-frozen-blob, per-anchor-MATCH-SHIFTED-ABSENT, baseline-anchored-attestation]
key-files:
  created:
    - .planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md
  modified: []
decisions:
  - "Every line verdict resolved via git show 0cc5d10f:contracts/<path> (NOT the dirty held-330 tree)"
  - "Q5: batchPurchase is AF_KING-gated with a single external caller (AfKing:821) -> RD-2 :1737 removal affects only the keeper"
  - "GAS-03 SATISFIED BY DELETION: advance (AdvanceModule:241-253) is the SOLE stall epoch after D-07 drops AfKing :823-838/:829"
  - "ROUTER-07 no-guard basis HOLDS: keeper-never-a-payee + no untrusted ETH send + one-category early-return + single-creditFlip-last CEI"
metrics:
  duration: ~25m
  completed: 2026-05-26
  tasks: 2
  files: 1
  blockers: 0
---

# Phase 329 Plan 01: REDESIGNED Router + Advance Call-Graph Attestation Summary

Grep-attested every cited `file:line` anchor on the v49.0 keeper-router REDESIGN surface (RD-1..RD-5,
D-07 flat-per-tx, GAS-03 satisfied-by-deletion, ROUTER-07/D-01a, ADV-04, invariant-(c)/D-04a, D-08
GASOPT-03/04/05) against the FROZEN v48.0-closure HEAD `0cc5d10f`, regenerating the stale
pre-redesign ATTEST doc. **0 IMPL blockers** — every anchor is MATCH or immaterial line-shift.

## What was produced

`.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md`
(7 sections A-G + a Roll-up), fully OVERWRITING the stale pre-redesign output:

- **Section A** — 14 AfKing router anchors (CEI `:100`, `AutoBought` `:171`/`:785`, `lastAutoBoughtDay`
  `:81`/`:784`, `BOUNTY_ETH_TARGET` `:263`, subscribe-time `isOperatorApproved` `:401` KEEP, `autoBuy`
  `:567` + the RD-2 entry rngLock guard `:568` REMOVE, per-iteration `isOperatorApproved` `:676`
  GASOPT-05 REMOVE, `claimableWinningsOf` `:691`/`:722`, the D-07 dead stall ladder + absolute-day
  epoch `:823-838`/`:829`, bounty `:845` + creditFlip `:846` RD-4 PULL-OUT, `_currentDay` `:886`) +
  the KEEP-04 affiliate-passthrough-survives-the-`_autoBuy`-refactor verdict. **12 MATCH / 2 SHIFTED
  / 0 ABSENT** with every held-tree drift recorded.
- **Section B** — RD-2 game-side guard (`:1737` remove / `:1738` keep); the **Q5 dependent grep
  PERFORMED**; the per-leg + single-unified-`creditFlip` no-untrusted-ETH-send rows; the formal
  no-guard basis recorded verbatim.
- **Section C** — D-07 dead surface + **GAS-03 SATISFIED-BY-DELETION** + GASOPT-03/04/05 baselines
  (with the GASOPT-04 4-file test-oracle list + the no-double-buy hardest case + the GASOPT-05
  333-SWEEP blocking-condition) + the two GASOPT-01 hoist rows.
- **Section D** — advance anchors (`:155`/`:147`/`:241-253`/wrapper `:275`) + the RD-4 **6-site →
  1 creditFlip** unification (5 pull-out U1-U5 + the SDGNRS gameover-RNG U6 stays) + the design-1
  `(uint8 mult, bool rewardable)` decode verdict + mid-day `mult=1`.
- **Section E** — autoOpen `++cursor`-before-try/catch hazard (`:1659`/`:1664`/`:1672`/`:1675`/`:1676`)
  + `_autoOpenBox` onlySelf `:1705`; the **EXACTLY-TWO revert sources** (rngLock + the deliberate
  `storage/DegenerusGameStorage.sol:571` `_livenessTriggered` `:1213`); the RD-5 entry-gate-replicates-both
  verdict + boxesPending rngLock-aware (RD-3).
- **Section F** — ADV-04 `totalFlipReversals` freeze (`:270`/`:1838` reads, `:1844` reset inside
  `_applyDailyRng :1834`); the autoBuy-runs-pre-entropy-at-day-open / no-new-in-window-SLOAD verdict
  (TST-01 handoff); the 3 O(1) discovery views.
- **Section G** — invariant-(c) free-fallback callers (30-min `:1012` / Vault `:527` / sStonk `:421`
  / death-clock `:109`) + the **D-04a** autoBuy-first amendment.

## Headline verdicts (for Plan 03)

- **Aggregate IMPL-blocker count: 0.** No ABSENT anchor; only immaterial line-shifts (A13 `_currentDay`
  `-1`, A14 `bytes32("DGNRS")` wiring `+3` [v48 KEEP-04 already landed at baseline], G4 death-clock
  cited `:1233/:1296` → actual `:109`/`:1199-1200`/`:1898`).
- **Q5: NO OTHER DEPENDENT.** `batchPurchase` is defined once (`DegenerusGame:1731`), AF_KING-gated
  (`:1736`), sole external caller `AfKing.sol:821` → removing the `:1737` rngLock pre-check (RD-2)
  affects only the keeper path; normal-player mint uses a different entrypoint.
- **ROUTER-07 (D-01a): NO-GUARD BASIS HOLDS.** Per-leg (advance/autoOpen/`_autoBuy`) + the single
  unified `doWork` `creditFlip` all send ETH only to pinned `ContractAddresses.*` (GAME/COINFLIP) and
  route player value through `claimableWinnings`; keeper-never-a-payee; exactly one CEI-last
  `creditFlip`. 0 untrusted-push legs → NO `nonReentrant` guard, 0 blocker.
- **GAS-03 / D-03: SATISFIED BY DELETION.** Advance (`AdvanceModule:241-253` game-day epoch) is the
  SOLE stall epoch after D-07 drops AfKing's autoBuy stall ladder + absolute-day epoch — no dual
  epoch to collapse.
- **ADV-04 (invariant b): NO NEW IN-WINDOW READ.** `totalFlipReversals` frozen request→consume; under
  RD-1 autoBuy runs pre-entropy at day-open → the redesigned router adds no new mutable in-window
  SLOAD into the advance-consume. (Empirical proof: TST-01.)
- **RD-5 entry-gate: REPLICATES BOTH REVERT SOURCES.** The exactly-two open-path revert sources
  (rngLock + `storage/DegenerusGameStorage.sol:571`) are both excluded pre-loop → brick-proof,
  terminal-jackpot guard intact for direct opens. USER-accepted frozen-contract trade.
- **Invariant (c) / D-04a: FALLBACK CALLERS INTACT.** 30-min bypass + Vault + sStonk + death-clock all
  present; under autoBuy-first the rewarded advance leg is blocked while buys pend → these tiers cover
  first-30-min, not the bounty. No structural caller removed by re-homing the bounty.

## Discretion-item resolutions

- **design-1 return:** `(uint8 mult, bool rewardable)` decode at `DegenerusGame.advanceGame` wrapper
  (`:275`/`:283`, currently discards `data`); new-day `mult` = stall ladder (1/2/4/6), mid-day +
  gameover partial-drains `mult=1`.
- **discovery views:** `advanceDue()` (`currentDayView():462 != dailyIdx` OR mid-day partial-drain),
  `boxesPending()` (rngLock-aware per RD-3, covers mid-day-resolved rounds), buys-pending (AfKing-local
  cursor, TRUE during rngLock per RD-2) — all O(1).
- **KEEP-04 affiliate (ROUTER-05): SURVIVES.** `bytes32("DGNRS")` at `DegenerusGame:1781` (game-side
  `_batchPurchaseUnit`, the v48 KEEP-04 wiring already landed; held-claim `:1778` → actual `:1781`),
  independent of the AfKing `_autoBuy` refactor; two-tier 75/20/5 preserved.
- **GASOPT-01 hoist sites:** `processFutureTicketBatch` (`:393`/`rk:398`) + `processTicketBatch`
  (`:670`/`rk:671`) — `[rk]` loop-invariant, behavior-identical gas-only.
- **GASOPT-03/04/05 baselines:** GASOPT-03 batched read (`claimableWinningsOf :691/:722` →
  `keeperSnapshot`/`batchPurchaseForKeeper`, SUBSUMES GASOPT-02); GASOPT-04 drop `AutoBought`
  (`:171`/`:785` → `lastAutoBoughtDay` `:81`/`:784`; 4-file test-oracle migration —
  `AfKingConcurrency.t.sol:62`, `AfKingSubscription.t.sol`, `AfKingFundingWaterfall.t.sol:63`,
  `SweepPerPlayerWorstCaseGas.t.sol:73`; hardest case = the no-double-buy `_countAutoBoughtFor(sub)==1`
  invariant); GASOPT-05 drop per-iteration `isOperatorApproved` (`:676`), KEEP subscribe-time (`:401`),
  333-SWEEP-re-attests-4-OPEN-E-protections BLOCKING-CONDITION.

## Deviations from Plan

None — plan executed exactly as written. Two minor anchor corrections recorded in-doc (not deviations):
the v48 KEEP-04 `bytes32("DGNRS")` wiring already landed at baseline `0cc5d10f` (so the affiliate
anchor reads MATCH+SHIFTED `:1778→:1781`, not a future wiring target), and the G4 death-clock
held-cited lines `:1233/:1296` resolve to the actual death-clock constant/extend at
`:109`/`:1199-1200`/`:1898` (mechanism intact, line-cited drift recorded).

## Known Stubs

None. This is a paper-only attestation plan — ZERO `contracts/*.sol` mutation. The pre-existing
held-330 diff on the working tree (6 `.sol` + 7 test files) was NOT touched, staged, or committed by
this plan; only the `.planning/` ATTEST doc was written and committed (with explicit file paths under
`CONTRACTS_COMMIT_APPROVED=1`).

## Commits

- `84fbb073` docs(329-01): attest AfKing router surface vs 0cc5d10f (sections A/B/C)
- `79086b3b` docs(329-01): attest advance/autoOpen redesign vs 0cc5d10f (sections D/E/F/G + Roll-up)
- `09baeb71` docs(329-01): complete REDESIGNED router/advance attestation plan (SUMMARY)

## Self-Check: PASSED

- FOUND: `329-ATTEST-ROUTER-ADVANCE.md` (regenerated, 7 sections + Roll-up)
- FOUND: `329-01-SUMMARY.md`
- FOUND commits: `84fbb073`, `79086b3b`, `09baeb71`
- VERIFIED: STATE.md, ROADMAP.md, REQUIREMENTS.md, and every `contracts/`/`test/` file are NOT in
  any of this plan's commits and were NOT staged. The pre-existing held-330 diff (6 `.sol` + 7 test
  files) and the orchestrator-owned `STATE.md` working change + the stale 329-02/03-SUMMARY deletions
  are all untouched by this plan (confirmed not in commits `84fbb073`/`79086b3b`/`09baeb71`).
