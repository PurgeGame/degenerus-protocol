---
phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec
plan: 01
subsystem: spec
tags: [solidity, design-lock, crank, subscription, afking, vrf-freeze, proto, batchpurchase]

# Dependency graph
requires:
  - phase: 316-RESEARCH
    provides: grep/forge-verified call-graph substrate (§1.10/§1.11/§1.12 anchors, §2 reader-set, §5 open-item facts)
provides:
  - "ADD-half design lock — do-work crank entry encoding (caller-list bets w/ BatchAlreadyTaken short-circuit, parameterless box cursor per OPEN-D, WWXRP zero reward)"
  - "Reward/charge model lock — gasUnits·0.5gwei via guarded _ethToBurnieValue, one creditFlip/cranker/tx, fixed gasUnits never measured gas, OPEN-B reward-0-never-revert"
  - "batchPurchase(players[],amounts[],modes[]) shape — keeper-gated try/catch + slice-refund + one batch value transfer + batch-level rngLocked/game-over precheck; OPEN-C = CEI-proof + guard-fallback note"
  - "Subscription cursor-sweep design — sweep(maxCount) + daily sweepCursor self-partition + stall-escalating bounty + tombstone-on-cancel + swap-pop + windowPaid bit + transient-skip retry"
  - "Authorization model — subscribe-time self-or-operator consent checked once never at sweep; pass-OR-pay via hasAnyLazyPass at monthly renewal only"
  - "5 PROTO signatures gating on pinned AF_KING — PROTO-01 rename _hasAnyLazyPass to external view (no body change), PROTO-02 burnForKeeper all-or-nothing, PROTO-03 keeper into onlyFlipCreditors, PROTO-04 batchPurchase, PROTO-05 pin AF_KING"
affects: [316-02-REMOVE-footprint, 316-03-open-items, 316-04-attestation, 317-IMPL, 318-TST, 319-GAS, 320-AUDIT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Design-lock prose-only SPEC sections (signatures/identifiers/encoding named, no fenced solidity bodies)"
    - "Re-grep every cited file:line against HEAD before authoring (SC#5 zero unverified by-construction claims)"

key-files:
  created:
    - .planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md
  modified: []

key-decisions:
  - "OPEN-B locked = guarded _ethToBurnieValue zero-guard (reward 0, never revert); priceForLevel non-zero invariant as secondary backstop"
  - "OPEN-C locked = CEI-proof (no ReentrancyGuard; CEI throughout per DegenerusGame.sol:1408) WITH guard-fallback note routed to contract-auditor skill at IMPL"
  - "OPEN-D box resolution = parameterless cursor (collision-free), MUST follow v45 a303ae18 VRF-rotation orphan-index re-issue path (Pitfall 3 landmine)"
  - "PROTO-01 = rename _hasAnyLazyPass private->external view, NO body change; reader-set verified exactly 3 grep matches (decl :1610 + readers :1580/:1660)"
  - "Keeper transitional-state caveat recorded: SPEC locks INTENDED end-state not live source; PLAN-CRANK §9 'done this session' is FALSE vs §1.12 drift"

patterns-established:
  - "Pattern: per-item onlySelf self-call + try/catch is the only Solidity in-context per-item revert isolation (covers both cranks AND batchPurchase)"
  - "Pattern: one creditFlip per cranker per tx (memory-accumulated), never per-item — REW-02 faucet lock"

requirements-completed: [PROTO-01]

# Metrics
duration: 6min
completed: 2026-05-23
---

# Phase 316 Plan 01: ADD-Half Design Lock Summary

**Locked the do-work crank entry encoding + gas-pegged coinflip-credit reward + batchPurchase try/catch shape + subscription cursor-sweep + authorization/pass-gate + 5 PROTO signatures into `316-SPEC.md`, every cited file:line re-grep-verified against HEAD.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-23T15:39:17Z (phase execution start)
- **Completed:** 2026-05-23T15:44:32Z
- **Tasks:** 2
- **Files modified:** 1 (created `316-SPEC.md`)

## Accomplishments

- Authored `## ADD Design — Do-Work Crank`: caller-list bets with `BatchAlreadyTaken` collision short-circuit (CRANK-02), parameterless box cursor per OPEN-D (CRANK-03), WWXRP `currency==3` zero reward (CRANK-04); reward = `gasUnits(workType)·0.5 gwei → BURNIE` via the guarded `_ethToBurnieValue` idiom (MintModule:1412) with reserved per-work-type gas-peg constants (values deferred to Phase 319/OPEN-A); one `creditFlip`/cranker/tx (REW-02), fixed `gasUnits` never measured gas (REW-03), no caller restriction (REW-04); `batchPurchase` shape with try/catch + slice-refund + one batch value transfer + batch-level precheck and OPEN-C CEI-proof + guard-fallback note; per-item `onlySelf`+try/catch isolation (SAFE-02); the OPEN-D box-cursor VRF-rotation `a303ae18` re-issue coupling (Pitfall 3 landmine).
- Authored `## ADD Design — Subscription Sweep & Authorization`: `sweep(maxCount)` + daily `sweepCursor` self-partition + stall-escalating bounty + `lastSweptDay` backstop (SUB-03); tombstone-on-cancel + in-sweep swap-pop + `windowPaid` bit + transient-skip retry + withdrawable stranded `_poolOf` ETH (SUB-07); subscribe-time self-or-operator consent checked once, never at sweep (SUB-02); pass-OR-pay via `hasAnyLazyPass` at monthly renewal only (SUB-01); charge = `burnForKeeper` all-or-nothing, bounty = `creditFlip` gas-pegged (SUB-08). Recorded the keeper transitional-state caveat (Pitfall 1).
- Authored `## PROTO Additions`: all 5 PROTO signatures gating on the pinned `AF_KING` constant; PROTO-01 = rename `_hasAnyLazyPass` private→external view (no body change, 3-match reader-set); PROTO-02 `burnForKeeper` all-or-nothing `onlyAfKing`; PROTO-03 only adds the keeper to `onlyFlipCreditors` (creditFlip decl already at `IBurnieCoinflip:115`); PROTO-04 `batchPurchase` (points to the Task-1 lock); PROTO-05 pin `AF_KING`.
- Satisfied SC#5: re-grep-verified every `<interfaces>` anchor against HEAD before writing (reward idiom, advanceGame bounty, resolve/placement gates, pass gate, ContractAddresses, PROTO-side interface facts, CEI convention).

## Task Commits

Each task was committed atomically (force-added `.planning/` is gitignored):

1. **Task 1: do-work crank ADD-design + reward/charge + batchPurchase** - `49b9e8c1` (docs)
2. **Task 2: subscription cursor-sweep + authorization + pass-gate + 5 PROTO signatures** - `9da3d43a` (docs)

## Files Created/Modified

- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` - Created; contains the three ADD-half design-lock sections (`## ADD Design — Do-Work Crank`, `## ADD Design — Subscription Sweep & Authorization`, `## PROTO Additions`). Sections owned by Plans 316-02/03/04 (REMOVE footprint, open-item resolution, attestation) are appended by those plans.

## Decisions Made

- **OPEN-B** locked as the guarded `_ethToBurnieValue` form (reward → 0 on zero/bad price, never revert), with the non-zero `priceForLevel` invariant as the secondary structural backstop. Final OPEN-B prose is co-owned by Plan 316-03.
- **OPEN-C** locked as CEI-proof (the game has no ReentrancyGuard; CEI throughout, cited at `DegenerusGame.sol:1408`) WITH a mandatory guard-fallback note: the IMPL traces the mint→lootbox→prize-pool→EV-cap→quest chain and adds a guard only if a re-entrant path is found; proof routed to the `contract-auditor` skill at IMPL/TST (named, not run here).
- **OPEN-D** box resolution locked as a parameterless cursor that MUST follow the v45 `a303ae18` detect-preserve-re-issue path; flagged as the milestone's single biggest design landmine (Pitfall 3).
- Recorded a citation drift note in the SPEC header: the Degenerette module's canonical filename is `DegenerusGameDegeneretteModule.sol` (research short-hands `DegeneretteModule.sol`); `_distributePayout` solvency check is at `~738` (decl `:705`), not the interior offset `742` PLAN-CRANK §8 cites.

## Deviations from Plan

None - plan executed exactly as written. No auto-fixes needed (Rules 1-4 not triggered): every cited anchor grep-confirmed against HEAD on first pass; zero `contracts/`/`test/` mutations; no architectural questions arose.

## Issues Encountered

None. The only adjustment was a documentation note (not a deviation): the plan's `<interfaces>` block uses `DegeneretteModule.sol` as a short-hand for the canonical `contracts/modules/DegenerusGameDegeneretteModule.sol`; verified all module anchors against the real filename and recorded the short-hand in the SPEC's citation-discipline header. This matches what `316-RESEARCH.md` already flagged.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The ADD-half design substrate (crank entry encoding, reward/charge, `batchPurchase`, sweep, authorization, 5 PROTO signatures) is locked for Phase 317 IMPL to build from.
- Plans 316-02 (REMOVE footprint + JGAS), 316-03 (open-item resolution incl. final OPEN-B/OPEN-C prose + whale-expiry user decision), and 316-04 (call-graph attestation) append their sections to the same `316-SPEC.md`.
- Open dependencies for downstream phases: OPEN-A gas-peg numeric values (Phase 319), the OPEN-C CEI-vs-guard proof (contract-auditor at Phase 317/318), and the whale-pass-expiry renewal funding decision for protocol subs (genuine user-OPEN, owned by Plan 316-03).

## Self-Check: PASSED

- FOUND: `316-SPEC.md`
- FOUND: `316-01-SUMMARY.md`
- FOUND commit: `49b9e8c1` (Task 1)
- FOUND commit: `9da3d43a` (Task 2)

---
*Phase: 316-spec-crank-subscription-legacy-removal-design-lock-spec*
*Completed: 2026-05-23*
