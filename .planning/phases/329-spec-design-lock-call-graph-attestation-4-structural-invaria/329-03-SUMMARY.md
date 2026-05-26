---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 03
subsystem: keeper-router-advance-spec-reconciliation
tags: [spec, design-lock, reconciliation, router, advance, degeneretteResolve, BATCH-01, ROUTER-07, ADV-04, GAS-03, paper-only]

# Dependency graph
requires:
  - "329-01 (329-ATTEST-ROUTER-ADVANCE.md — the router/advance attestation half, 34 anchors / 0 blockers)"
  - "329-02 (329-ATTEST-DEGENERETTE-RESOLVE.md — the D-05 family attestation half, 0 blockers + the interface-ABSENT Rule-1 correction + the D-05f INERT-SAFE finding)"
  - "v48.0-closure HEAD 0cc5d10f (the byte-identical baseline both ATTEST docs grep against)"
provides:
  - "329-SPEC.md — the reconciled v49.0 design-lock blueprint (§0 attestation roll-up, §1 settled shared signatures, §2 the 4 structural invariants + ROUTER-07/GAS-03 dispositions + the D-05 design-lock, §3 per-item IMPL blueprint + producer-before-consumer edit-order map)"
  - "The 4 structural invariants locked in writing (BATCH-01): (a) one-category early-return, (b) frozen advance-consume ADV-04, (c) free-fallback caller D-04, (d) single day-start epoch GAS-03"
  - "The settled shared signatures R1-R4: advanceGame (uint8 mult, bool rewardable) + :275 decode / doWork(maxCount)+NoWork()+D-06 default / 3 O(1) discovery views / one-creditFlip bounty composition"
  - "ROUTER-07 NO-guard disposition (D-01a per-leg no-untrusted-ETH-send basis + D-01b TST-02 backstop); GAS-03 design-1-satisfies"
  - "The D-05 degeneretteResolve design-lock (rename + flat ~1-BURNIE re-peg + D-05c real-gas basis + D-05f INERT-SAFE + router-fold OUT)"
  - "The producer-before-consumer edit-order map (AdvanceModule → Game wrapper/views → interfaces → AfKing router/_autoBuy/micro-opts) for Phase 330"
affects:
  - "Phase 330 IMPL (BATCH-01 + BATCH-02 — applies the ONE batched diff against the settled signatures + edit-order, zero by-construction assumptions)"
  - "Phase 331 GAS (calibrates the break-even peg / ~1-BURNIE / D-06 default-count SPEC placeholders; GAS-06 sanity-check)"
  - "Phase 332 TST (TST-01 freeze fuzz / TST-02 router double-pay backstop / TST-05 rename + flat-not-per-item)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "v48 325-SPEC.md reconciliation format mirrored: §0 attestation roll-up + carried corrections / §1 R-row shared signatures w/ apply-order / §2 invariants + dispositions + design-lock / §3 IMPL blueprint + producer-before-consumer edit-order map + SC1..SC4 checklist"
    - "Each structural invariant locked as a CODE invariant (not a comment) + mapped to the named pitfall it closes"

key-files:
  created:
    - ".planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md"
  modified: []

key-decisions:
  - "ROUTER-07 = NO nonReentrant guard (D-01) on the per-leg no-untrusted-ETH-send basis (D-01a) + the D-01b TST-02 empirical backstop scoped to PROVE it"
  - "GAS-03 = design-1-satisfies — the two epochs (AfKing absolute-day :829 vs AdvanceModule game-day :243-246) intentionally distinct, NOT physically merged (D-03a)"
  - "D-06 maxCount==0 = a FIXED gas-budget-sized per-leg default count (NOT gasleft loop); EmptyAutoBuy removed/repurposed (default lives in shared _autoBuy); refines ROUTER-01/GAS-01/TST-02, no new REQ-IDs"
  - "D-05f losing-bet liveness = INERT-SAFE recorded (SURFACE-TO-USER: NONE) — carried from 329-02, NOT softened, NOT invented as a SURFACE-TO-USER block"
  - "Rule-1 correction carried from 329-02 (C6): the degeneretteResolve interface-file rename rows are ABSENT/no-op (defined directly on DegenerusGame.sol); KEEP-04 line-drift carried from 329-01 (C1: :1781, +3)"

requirements-completed: [BATCH-01, ROUTER-07, ADV-04, GAS-03]

# Metrics
metrics:
  duration: "~18 min"
  completed: 2026-05-26
  tasks: 2
  files_created: 1
  commits: 2
---

# Phase 329 Plan 03: v49.0 Design-Lock + Shared-Surface Reconciliation Summary

**Authored `329-SPEC.md` — the reconciled v49.0 design-lock blueprint (the direct analog of v48's 325-SPEC.md) — folding the two Wave-1 ATTEST docs into one document that LOCKS the 4 structural invariants, settles the shared signatures (advanceGame return / doWork+NoWork / O(1) discovery views), resolves the two flagged dispositions (ROUTER-07 no-guard + GAS-03 design-1-satisfies), and locks the D-05 `degeneretteResolve` design item (rename + flat ~1-BURNIE re-peg + the INERT-SAFE D-05f finding + router-fold OUT), with a producer-before-consumer edit-order map as the load-bearing input to Phase 330 — zero `contracts/*.sol` mutation.**

## 329-SPEC.md sections

- **§0 Attestation verdict roll-up (BATCH-01, Wave-1 fold-in):** 0 IMPL blockers across both attestation surfaces (Plan 01: 34 anchors / 34 MATCH; Plan 02: rename surface + B/C/D/E re-derivations / 0 blockers); the aggregate verdict table; the carried corrections C1-C6 (KEEP-04 :1781 +3 / 30-min bypass :1012 +4 / death-clock :1200 +2 / GASOPT-01 sites / gas-peg :1539-1546 / the interface-file rename rows ABSENT/no-op Rule-1 correction); the 5 load-bearing decision verdicts (ROUTER-07 no-guard-basis-holds / GAS-03 epochs-distinct / ADV-04 no-new-in-window-read / invariant-(c) fallbacks-intact / D-05f INERT-SAFE SURFACE-TO-USER-NONE).
- **§1 Shared Signatures (R1-R4, ROADMAP SC2):** R1 the `advanceGame` `(uint8 mult, bool rewardable)` design-1 return + the `:275` wrapper decode (rewardable a DISTINCT bool); R2 `doWork(maxCount)` + the ROUTER-06 `NoWork()` revert + per-leg maxCount + the LOCKED D-06 `maxCount==0` fixed gas-budget-sized default count; R3 the 3 O(1) discovery views (advanceDue covering new-day AND mid-day, boxesPending, buys-pending AfKing-local) + their locations; R4 the one-creditFlip router-pays-only-advance bounty composition + KEEP-04 affiliate survival. Each R-row names producer + consumer files + apply-order.
- **§2 Structural invariants + dispositions + the D-05 design-lock (ROADMAP SC1 + SC3):** the 4 invariants each as a labeled subsection citing the decision id + ATTEST verdict + the IMPL instruction + the pitfall it closes; the ROUTER-07 NO-guard + GAS-03 design-1-satisfies dispositions; the D-05a-g design-lock.
- **§3 Per-item IMPL blueprint + producer-before-consumer edit-order map (the load-bearing Phase 330 input):** the "Files in the diff" list + the 5-step producer-before-consumer edit-order (AdvanceModule → Game wrapper/views → interfaces → AfKing router/_autoBuy → MintModule micro-opt); one blueprint paragraph per work-area; the SPEC placeholders flagged; the SC1..SC4 checklist mapped 1:1.

## The 4 locked structural invariants (SC1 / BATCH-01)

- **(a) ONE-CATEGORY STRUCTURAL EARLY-RETURN** — `doWork` routes advance→autoOpen→autoBuy and RETURNS after the first rewarded category (a CODE invariant, explicit `return`, not a comment); preserves the one-`creditFlip`-per-tx faucet bound. Closes Pitfall 4 (bounty-stacking / reward fall-through).
- **(b) FROZEN ADVANCE-CONSUME (ADV-04)** — the `totalFlipReversals` nudge (`AdvanceModule:1838`/reset :1844 in `_applyDailyRng` :1834) is frozen request→consume; the router consumes via the design-1 RETURN and adds NO new mutable in-window SLOAD. TST-01 empirical freeze-fuzz handoff. Closes Pitfall 3 + the v45 VRF-freeze floor.
- **(c) GUARANTEED FREE-FALLBACK CALLER (D-04)** — EXISTING paths only, no new mechanism: PRIMARY the router's advance leg (re-homed bounty) / SECONDARY the 30-min universal bypass (:1012) + Vault/sStonk `gameAdvance()` wrappers (:527-528 / :421-422) / TERTIARY the 120-day death-clock (:109/:1200). Re-homing removes no structural caller. Closes Pitfall 8.
- **(d) SINGLE DAY-START EPOCH (GAS-03/D-03)** — design-1 single-sources the advance multiplier (computed once :243-254, returned, consumed without recompute); the two intentionally-distinct epochs (AfKing absolute-day :829 vs AdvanceModule game-day :243-246) NOT physically merged (D-03a) + the WHY-they-differ rationale documented. Closes Pitfall 7.

## The settled shared signatures (SC2)

- **advanceGame return** = `(uint8 mult, bool rewardable)` (design-1; `rewardable` a DISTINCT bool, not implied by `mult>0`); decoded in the `DegenerusGame.advanceGame` wrapper at `:275` (delegatecall `data` success-branch decode).
- **doWork(maxCount)** + the ROUTER-06 `NoWork()` revert (fires only when all 3 O(1) predicates empty); per-leg maxCount = autoOpen + _autoBuy only (advance no-count, D-06c); the LOCKED D-06 `maxCount==0` fixed default count (NOT gasleft; EmptyAutoBuy removed/repurposed with the default living in the shared `_autoBuy`, D-06e; OOG = clean revert + manual smaller-maxCount retry, D-06d; faucet-neutral, D-06f; ~10M/DEFAULT_*_COUNT GAS-331 placeholders; refines ROUTER-01/GAS-01/TST-02, no new REQ-IDs, D-06g).
- **3 O(1) discovery views (ROUTER-04, no unbounded scans)** = advanceDue() (new-day `currentDayView()!=dailyIdx` OR mid-day `LR_MID_DAY!=0`) + boxesPending() (`boxPlayers[idx].length > boxCursor` AND `lootboxRngWordByIndex[idx]!=0`) — both on DegenerusGame; buys-pending via the AfKing-local cursor (:577).
- **bounty composition (R4)** = the router pays ONLY the re-homed advance bounty (one creditFlip, last/CEI, gated on rewardable × mult); autoOpen/autoBuy keep their own in-callee bounty; no double-pay; KEEP-04 `bytes32("DGNRS")` affiliate passthrough survives the `_autoBuy` refactor (game-side at :1781, C1).

## The two dispositions resolved (SC3)

- **ROUTER-07 = NO `nonReentrant` guard (D-01)** on the grep-checked per-leg no-untrusted-ETH-send basis (D-01a): advance sends ZERO ETH; autoOpen/_autoBuy route player value through the `claimableWinnings` pull ledger + send ETH only to pinned `ContractAddresses.*`/the keeper-contract; bounty pays as `creditFlip` flip-credit (keeper-never-a-payee) fired LAST (CEI). Formal basis recorded verbatim. D-01b: the TST-02 router→game→creditFlip double-pay regression stays as the empirical backstop scoped to PROVE the no-guard disposition.
- **GAS-03 = design-1-satisfies** (cross-referenced to invariant d, no duplicate decision; the two epochs intentionally distinct, no physical merge, D-03/D-03a).

## The D-05 design-lock + the D-05f finding

- **D-05 LOCKED as a v49.0 design item** (code at Phase 330/BATCH-02, REQ-IDs GAS-06/TST-05 at 331/332): D-05a rename (`autoResolve`→`degeneretteResolve` + `_autoResolveBet`→`_degeneretteResolveBet` + the :1606 self-call site; NO interface edit — C6/Plan-02 §A.2 ABSENT correction; the 5 test files / 57 refs incl. the CrankLeversAndPacking literal source-string assertions update atomically) + D-05b the FEASIBLE flat ~1-BURNIE-once/≥3-NON-WWXRP-gate/revert-NoWork()-at-0/resolve-always-pay-at-≥3-revert-only-at-0 shape (edit targets :1611-1614 remove peg → ++successCount, :1622 swap to flat+gate+revert, add RESOLVE_FLAT_BURNIE) + D-05c the REAL-gas net-loss basis (1 BURNIE ≤ 0.00024 ETH + illiquid vs ≥220k gas × 5-50+ gwei = ~4.6-46× the peg; explicitly NOT the 0.5-gwei AUTO_GAS_PRICE_REF) + D-05d WWXRP-excluded/AUTO-02/REW-04 preserved + D-05e the GAS-06 sanity-check handoff + the ROUTER-05 router-fold-OUT (degeneretteBets nested mapping, no O(1) enumeration).
- **D-05f finding = INERT-SAFE; SURFACE-TO-USER: NONE.** Carried from 329-02 verbatim and NOT softened: all 8 `degeneretteBets` consumers treat an unresolved losing bet as inert cruft; the `delete` :634 is local-idempotency-only; GameOver/Jackpot/Advance modules grep-CLEAN (0 hits each); no counter/tally/require-empty anywhere → no path requires losing bets resolved. The flat reward mildly IMPROVES backlog liveness. **No SURFACE-TO-USER block was invented** (none warranted at `0cc5d10f`).

## SC1..SC4 coverage for the Phase 329 verification

| Criterion | Status | Where |
|-----------|--------|-------|
| SC1 — 4 structural invariants locked in writing (BATCH-01) | ✅ | §2 invariants (a)/(b)/(c)/(d) |
| SC2 — shared signatures settled (advanceGame return / doWork+NoWork / O(1) views) | ✅ | §1 R1-R4 |
| SC3 — two dispositions resolved (ROUTER-07 no-guard + GAS-03 design-1-satisfies) | ✅ | §2 ROUTER-07 (D-01a/b) + GAS-03 |
| SC4 — every file:line verdict folded, no un-grepped by-construction, producer-before-consumer edit-order map | ✅ | §0 (C1-C6, 0 blockers) + §3 edit-order map |
| D-05 design item locked + D-05f carried (not softened) | ✅ | §2 D-05a-g + the INERT-SAFE D-05f |

## Deviations from Plan

None — plan executed exactly as written. Both tasks committed atomically; zero `contracts/*.sol` mutation (paper-only phase, confirmed via `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` empty + the working-tree `contracts/` clean after both commits). The two Wave-1 inputs were consumed as directed: the 329-02 Rule-1 correction (interface-file rename rows ABSENT) is carried as §0 C6, the 329-01 KEEP-04 line-drift (:1781, +3) as §0 C1, and the D-05f INERT-SAFE finding is recorded with SURFACE-TO-USER: NONE (NOT invented as a block).

## Known Stubs

None — this is a paper-only design-lock/reconciliation deliverable; no code, no UI data sources, no placeholders in the deliverable itself. (The SPEC explicitly FLAGS the break-even peg / ~1-BURNIE / D-06 default-count constants as SPEC PLACEHOLDERS calibrated at the GAS phase 331 — these are deliberate, traceability-tracked design deferrals owned by Phase 331, not stubs in this deliverable.)

## Threat Flags

None — paper-only reconciliation, ZERO code mutation. No new network endpoint / auth path / file-access pattern / schema change introduced. The threat boundary is the SPEC itself (T-329-R1..R5): all five mitigations are addressed — §1 R-rows name producer+consumer+apply-order and §3 enforces producer-before-consumer (T-329-R1); §2 carries the per-leg no-untrusted-ETH-send basis (T-329-R2); §2 invariant (b) locks the router ordering + TST-01 handoff (T-329-R3); §0+§2 carry the D-05f finding as INERT-SAFE without softening/burying (T-329-R4); §2 locks each invariant/disposition with the SC1..SC4 1:1 map (T-329-R5). T-329-SC (package installs) N/A — no installs in this paper-only plan.

## Self-Check: PASSED

- FOUND: `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md` (194 lines, §0/§1/§2/§3 all present)
- FOUND commit `1db8b5c9` (Task 1 — §0 + §1)
- FOUND commit `791d4d4b` (Task 2 — §2 + §3)
- All 4 SPEC-owned requirements present in the doc (BATCH-01 / ROUTER-07 / ADV-04 / GAS-03)
- `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` → EMPTY (zero contracts mutation); working-tree `contracts/` clean

---
*Phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria*
*Completed: 2026-05-26*
