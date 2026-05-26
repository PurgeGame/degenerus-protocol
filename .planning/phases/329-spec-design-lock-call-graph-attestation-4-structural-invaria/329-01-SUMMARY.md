---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 01
subsystem: keeper-router-advance-attestation
tags: [spec, attestation, call-graph, router, advance, ROUTER-07, ADV-04, GAS-03, BATCH-01, paper-only]
requires:
  - "v48.0-closure HEAD 0cc5d10f (the byte-identical baseline all anchors grep against)"
provides:
  - "329-ATTEST-ROUTER-ADVANCE.md — the BATCH-01 attestation half for the router/advance surface"
  - "ROUTER-07 / D-01a no-guard basis (per-leg no-untrusted-ETH-send grep proof)"
  - "GAS-03 / D-03 dual-epoch intentionally-distinct verdict (no physical merge)"
  - "ADV-04 totalFlipReversals freeze attestation (no new in-window SLOAD)"
  - "invariant-(c) / D-04 free-fallback caller attestation"
  - "design-1 (uint8 mult, bool rewardable) distinct-bool tuple + decode site"
  - "3 caller-reward creditFlip site classifications (:189/:225/:468)"
  - "3 O(1) discovery-view predicates + locations + maxCount per-leg + D-06 baseline"
  - "KEEP-04 bytes32(DGNRS) affiliate passthrough survival; GASOPT-01 hoist sites"
affects:
  - "Plan 03 reconciliation + 329-SPEC.md blueprint (consumes these grep-verified verdicts)"
  - "Phase 330 IMPL batched diff (re-anchors at the recorded line-drifts; carries zero un-grepped claims)"
tech-stack:
  added: []
  patterns:
    - "per-anchor grep-table attestation mirroring v48 325-ATTEST-KEEP-POOL.md (Verdict legend MATCH/SHIFTED/ABSENT)"
    - "per-leg no-untrusted-ETH-send decomposition (no by-construction claims)"
key-files:
  created:
    - ".planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md"
  modified: []
decisions:
  - "ROUTER-07 no-guard basis HOLDS — 0 untrusted-push legs (advance sends ZERO ETH; autoOpen/_autoBuy use claimableWinnings pull + pinned sends; creditFlip-last CEI)"
  - "GAS-03 epochs intentionally distinct (AfKing absolute-day :829 vs AdvanceModule game-day :243-246) → design-1 single-sources advance multiplier, NO physical merge (D-03a)"
  - "ADV-04 — router introduces NO new mutable in-window SLOAD (consumes via design-1 return); empirical freeze fuzz handed to TST-01"
  - "invariant-(c) fallback callers intact — re-homing the bounty removes no structural advanceGame() caller"
  - "design-1 rewardable is a DISTINCT bool (not implied by mult>0); decoded at DegenerusGame.advanceGame wrapper :275"
metrics:
  duration: "~25 min"
  completed: 2026-05-26
  tasks: 2
  files_created: 1
  commits: 3
  anchors_attested: 34
  impl_blockers: 0
---

# Phase 329 Plan 01: Router + Advance Call-Graph Attestation Summary

Grep-attested all 34 cited `file:line` anchors on the v49.0 unified keeper "do-work" router + advance-bounty
rework surface against the v48.0-closure baseline `0cc5d10f` (byte-identical live tree), resolving the four
load-bearing decision attestations (ROUTER-07/D-01a no-guard, GAS-03/D-03 dual-epoch, ADV-04 freeze,
invariant-(c)/D-04 fallbacks) plus every Claude's-Discretion grep fact — **34 MATCH / 0 ABSENT / 0 IMPL
blockers**, the BATCH-01 attestation half for the core router/advance surface.

## What Was Built

`329-ATTEST-ROUTER-ADVANCE.md` (347 lines), mirroring the v48 `325-ATTEST-KEEP-POOL.md` format (Scope +
Sources-of-truth + byte-identical-to-`0cc5d10f` method note + Verdict legend + per-anchor tables + Roll-up):

- **Section A** — 13 AfKing router anchors (CEI block :99-106, BOUNTY_ETH_TARGET :263, depositFor :304,
  withdraw :318, autoBuy :567 + EmptyAutoBuy :569, cursor :577, the two claimableWinningsOf hoist sites
  :691/:722, stall ladder :829, bounty :845 + creditFlip :846, _currentDay :886-888, anti-spam reverts
  :143/:146, the batchPurchase call site :821). **13 MATCH.** KEEP-04 confirmed: the `bytes32("DGNRS")`
  two-tier 75/20/5 affiliate code is wired game-side at `DegenerusGame.sol:1781` (NOT AfKing), so the
  `_autoBuy` refactor does not touch it — passthrough survives.
- **Section B** — ROUTER-07/D-01a per-leg no-untrusted-ETH-send: the **advance** leg makes ZERO direct ETH
  sends (grep returns no `.call{value}` in AdvanceModule); **autoOpen** and **_autoBuy** route player value
  through the `claimableWinnings` pull ledger and send ETH only to pinned `ContractAddresses.*` / the
  keeper-contract; the bounty pays as `creditFlip` flip-credit (keeper-never-a-payee) fired LAST (CEI). The
  out-of-leg redemption sends (:1907/:2213/:2230/:2251) are confirmed NOT reachable from the doWork legs.
  **0 ROUTER-07 blockers.**
- **Section C** — GAS-03/D-03 dual-epoch (AfKing absolute-day `today*1days+82_620` :829 vs AdvanceModule
  game-day `(day-1+DEPLOY_DAY_BOUNDARY)*1days+82_620` :243-246) attested intentionally-distinct → no
  physical merge; GASOPT-01 `rk`-loop-invariant hoist confirmed gas-only at MintModule :393 + :670.
- **Section D** — AdvanceModule advanceGame :155 (currently void — the design-1 tuple is the IMPL producer
  edit) + the DegenerusGame wrapper :275 decode site + the 3 caller-reward creditFlip classifications; the
  design-1 `(uint8 mult, bool rewardable)` `rewardable` flag is a DISTINCT bool.
- **Section E** — ADV-04: `totalFlipReversals` read :1838 + reset :1844 in `_applyDailyRng` :1834; the
  request→consume freeze window is intact and the router adds NO new mutable in-window SLOAD.
- **Section F** — the 3 O(1) discovery views (advanceDue covering new-day `currentDayView()!=dailyIdx` AND
  mid-day `LR_MID_DAY!=0`; boxesPending; buys-pending via AfKing-local cursor), `maxCount` per-leg mapping
  (autoOpen + _autoBuy only), and the D-06 clean baseline (autoBuy(0) revert / autoOpen(0) no-op / no
  count on advance; no existing fixed-default-or-gasleft pattern).
- **Section G** — invariant-(c) free-fallback callers: 30-min universal bypass :1012, Vault gameAdvance
  :527-528, sStonk gameAdvance :421-422, 120-day death-clock :109/:1200.
- **D-05f liveness note** — grep-confirmed NO invariant/accounting/RNG-slot/cleanup requires losing
  Degenerette bets to be resolved (inert mapping cruft) → the flat-"lose" re-peg is SAFE.

## Aggregate Verdicts (for Plan 03 to consume)

- **Aggregate IMPL-blocker count: 0** (34 anchors attested, all MATCH or content-present-SHIFTED, 0 ABSENT).
- **ROUTER-07 / D-01a: NO-GUARD BASIS HOLDS** — formal basis *keeper-never-a-payee + no untrusted ETH send
  + one-category structural early-return + creditFlip-last CEI ordering*. (Empirical double-pay backstop =
  TST-02.)
- **GAS-03 / D-03: EPOCHS INTENTIONALLY DISTINCT** — design-1 single-sources the advance multiplier via the
  `(uint8,bool)` return; AfKing's autoBuy epoch untouched; no physical merge (D-03a).
- **ADV-04: NO NEW IN-WINDOW READ** — request→consume freeze window intact; router consumes via the design-1
  return. (Empirical freeze fuzz = TST-01.)
- **Invariant (c) / D-04: FALLBACK CALLERS INTACT** — re-homing the bounty removes no structural caller.

### Discretion resolutions
- **design-1 return:** `(uint8 mult, bool rewardable)` — `rewardable` a DISTINCT bool; decode site =
  `DegenerusGame.advanceGame` wrapper :275 (success-branch decode of `data` at :283-284).
- **3 creditFlip classifications:** :189 new-day REWARDABLE / :225 mid-day partial-drain REWARDABLE (ADV-05)
  / :468 main new-day REWARDABLE; the :876 SDGNRS merge-credit is NOT router-rewardable.
- **discovery views:** advance + boxes on `DegenerusGame`, buys-pending on `AfKing`-local; all O(1).
- **maxCount:** autoOpen(maxCount) + _autoBuy(maxCount) only; advance has no count arg (D-06c).
- **KEEP-04:** `bytes32("DGNRS")` affiliate passthrough LIVE at v49 baseline, survives the `_autoBuy`
  refactor.
- **GASOPT-01:** `rk`-loop-invariant storage-pointer hoist gas-only at both MintModule sites.

## Recorded line-drifts (re-anchor at Phase 330 IMPL)

- KEEP-04 affiliate wiring: `DegenerusGame.sol:1781` (v48 ATTEST cited :1778 → SHIFTED +3).
- 30-min universal bypass: `AdvanceModule.sol:1012` (CONTEXT cited ~:1008 → SHIFTED +4).
- death-clock extend: `AdvanceModule.sol:1200` (CONTEXT cited :1198 → SHIFTED +2).

## Deviations from Plan

None — plan executed exactly as written. All anchors resolved MATCH (with three documented CONTEXT/v48-ATTEST
citation line-drifts, all content-present, none ABSENT). Zero `contracts/*.sol` mutation (paper-only phase,
confirmed via `git diff --name-only -- 'contracts/*.sol'` returning empty after both task commits).

## Known Stubs

None — this is a paper-only attestation deliverable; no code, no UI data sources, no placeholders.

## Self-Check: PASSED

- `329-ATTEST-ROUTER-ADVANCE.md` exists (347 lines).
- Commit `a39d8a4d` (Task 1, sections A/B/C) exists.
- Commit `e33249da` (Task 2, sections D/E/F/G + Roll-up) exists.
- `git diff --name-only -- 'contracts/*.sol'` is empty (zero .sol mutation).
