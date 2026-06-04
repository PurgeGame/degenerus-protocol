---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 01
subsystem: infra
tags: [solidity, storage-layout, struct-packing, afking, aggregator, accumulator, gas-02]

# Dependency graph
requires:
  - phase: 353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode
    provides: "The LOCKED Accumulator Layout (whole-BURNIE + 100M clamp + milli-ETH amount + narrowed day-markers + in-slot accumulator, NO new cold slot) + the QST-03 afkCoveredThroughDay delivered-day marker design + the pendingClaim cross-contract ownership boundary"
provides:
  - "Re-packed single-slot Sub struct (241/256 bits) carrying the v56 in-slot accumulator: affiliateBase (uint32 whole-BURNIE) + questProgress (uint8) + buyerOwedBurnie (uint32 whole-BURNIE) + hasEverSubscribed (1-bit latch)"
  - "afkCoveredThroughDay (uint24) monotone debit-gated delivered-day high-water marker — the QST-03 double-credit / streak-dodge guard substrate (DECLARED here; ADVANCED in 354-03)"
  - "amount re-denominated uint96 wei → uint32 milli-ETH (reusing the existing _packEthToMilliEth/_unpackMilliEthToWei helpers); validThroughLevel/lastAutoBoughtDay/lastOpenedDay uint32→uint24"
  - "Locked pendingClaim cross-contract ownership boundary (declared in DegenerusAffiliate.sol by 354-04, NOT game storage) in the Sub NatSpec"
affects: [354-03, 354-04, 354-05, 355, 356, GameAfkingModule, DegenerusAffiliate, DegenerusQuests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "In-slot self-marking running-balance accumulator (running balances zeroed at settle → no settle-day marker needed; AGG-05)"
    - "Milli-ETH (0.001-ETH) struct-field re-denomination reusing the established LR_ETH_SCALE=1e15 packing helpers — EV/seed-input rounding only, SOLVENCY-01 ETH cut byte-unchanged"

key-files:
  created:
    - .planning/phases/354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre/354-01-SUMMARY.md
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/GameAfkingModule.sol

key-decisions:
  - "Reused the existing in-file _packEthToMilliEth/_unpackMilliEthToWei (LR_ETH_SCALE=1e15) helpers for the amount milli-ETH re-denomination rather than introducing a new constant — same 0.001-ETH resolution the lootbox RNG slot already uses"
  - "pendingClaim is NOT declared in game storage — locked to DegenerusAffiliate.sol (354-04) via NatSpec; affiliateBase PULLed via DegenerusAffiliate.claim (drained by the 354-03 drainAffiliateBase accessor), buyerOwedBurnie PUSHed to the sub (no pendingClaim entry)"
  - "Final slot occupancy 241/256 (15 spare) — comfortable, not a tight fit, exactly as the plan/SPEC predicted"

patterns-established:
  - "Day-index markers carried as uint24 (~45,000-year headroom) across the Sub record"
  - "100M-whole-BURNIE saturating clamp is applied at the 354-03 accrue write, NOT at the storage declaration (uint32 ~4.29e9 > 100M binds first; under-credit-only, off the solvency path)"

requirements-completed: [AGG-05]

# Metrics
duration: 16min
completed: 2026-06-01
---

# Phase 354 Plan 01: Re-pack the Sub Struct + In-Slot Accumulator Summary

**Re-packed the `Sub` record into a single 256-bit slot (241/256, 15 spare) carrying the v56 in-slot aggregator accumulator (`affiliateBase`/`questProgress`/`buyerOwedBurnie`/`hasEverSubscribed`) plus the `afkCoveredThroughDay` delivered-day high-water marker — by narrowing `amount` (uint96 wei → uint32 milli-ETH) and `validThroughLevel`/`lastAutoBoughtDay`/`lastOpenedDay` (uint32 → uint24), with NO new cold slot; the three dropped settle markers were never introduced.**

## Performance

- **Duration:** 16 min
- **Started:** 2026-06-01T17:11:44Z
- **Completed:** 2026-06-01T17:26:49Z
- **Tasks:** 2
- **Files modified:** 2 (contracts — left UNCOMMITTED for the 354-06 batch gate)

## Accomplishments
- Re-packed `struct Sub` in `DegenerusGameStorage.sol`: added the four accumulator fields (`affiliateBase` uint32, `questProgress` uint8, `buyerOwedBurnie` uint32, `hasEverSubscribed` bool) + the `afkCoveredThroughDay` uint24 marker, all fitting the one existing 256-bit slot.
- Narrowed the wastefully-wide fields to reclaim the bits: `amount` uint96 wei → uint32 milli-ETH; `validThroughLevel`/`lastAutoBoughtDay`/`lastOpenedDay` uint32 → uint24.
- Deliberately did NOT introduce `windowStartDay`/`settledThroughDay`/`lastSettledDay` (AGG-05 — the running balances self-mark); `afkCoveredThroughDay` is a delivered-day high-water mark, NOT a settle marker.
- Locked the cross-contract `pendingClaim` ownership boundary in the Sub NatSpec (reserved for `DegenerusAffiliate.sol` per 354-04; `affiliateBase` PULL via `DegenerusAffiliate.claim`/the 354-03 `drainAffiliateBase` accessor; `buyerOwedBurnie` PUSH to the sub).
- `forge build` exits 0 across the working tree.

## Task Commits

**No production-code commits** — per the Phase 354 contract-commit override, all `contracts/*.sol` edits are left as UNCOMMITTED working-tree changes to accumulate for the single USER-approved batched commit at the 354-06 hand-review gate. The only commit this plan makes is the docs/tracking commit below.

1. **Task 1: Re-pack the Sub struct + accumulator + hasEverSubscribed + afkCoveredThroughDay** — UNCOMMITTED (contracts/storage/DegenerusGameStorage.sol)
2. **Task 2: Lock the cross-contract pendingClaim ownership boundary (comment-only)** — UNCOMMITTED (folded into the Task 1 struct NatSpec)

**Plan metadata:** see the final `docs(354-01)` commit hash reported to the orchestrator.

## Files Created/Modified
- `contracts/storage/DegenerusGameStorage.sol` — re-packed `struct Sub` (single slot, 241/256): added accumulator + `afkCoveredThroughDay`; narrowed `amount`→uint32 milli-ETH + `validThroughLevel`/`lastAutoBoughtDay`/`lastOpenedDay`→uint24; updated the struct/`_subOf` NatSpec (milli-ETH semantics, SOLVENCY-01 stamp-only rounding note, accumulator ownership, dropped-settle-marker note, pendingClaim cross-contract boundary). **UNCOMMITTED.**
- `contracts/modules/GameAfkingModule.sol` — build-preserving consumer-cast adjustments at the stamp write/read + the two `validThroughLevel` writes + the three day-marker writes (see Deviations Rule 3). **UNCOMMITTED.**
- `.planning/phases/354-.../354-01-SUMMARY.md` — this summary (committed).

## Decisions Made
- **Reused existing milli-ETH helpers.** The SPEC's "round amount to .001 eth" maps exactly to the already-present `LR_ETH_SCALE = 1e15` + `_packEthToMilliEth`/`_unpackMilliEthToWei` helpers (the same 0.001-ETH resolution the lootbox RNG slot uses). No new constant introduced. These `internal` helpers live on `DegenerusGameStorage` and are in scope at the `GameAfkingModule` delegatecall consumer sites.
- **pendingClaim stays out of game storage.** Per Task 2's locked decision, `pendingClaim` belongs to `DegenerusAffiliate.sol` (its own contract/storage, 354-04). This plan only documents the boundary; the verification grep confirms zero `mapping.*pendingClaim` in game storage.
- **Slot bit-allocation confirmed:** config 48 + stamp 48 + markers 72 + accumulator 73 = 241/256 (15 spare).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Adjusted consumer casts in GameAfkingModule.sol so the working tree compiles**
- **Found during:** Task 1 (verification — `forge build`)
- **Issue:** Narrowing the `Sub` struct fields in 354-01 while the consuming-site casts in `GameAfkingModule.sol` still used the old widths is a type mismatch that breaks `forge build` (the hard success criterion). The wave order places the GameAfkingModule accrue/open authoring in 354-03 (Wave 2), but the struct narrowing here makes those sites non-compiling immediately: `sub.amount = uint96(amount)` into a uint32 field; `uint256(sub.amount)` (now milli-ETH) fed to the box seed; `uint32(...)`/`processDay`/`day` (uint32) assigned into the now-uint24 day/level fields.
- **Fix:** Minimal, build-preserving edits — (a) stamp write `sub.amount = uint32(_packEthToMilliEth(amount))`; (b) open read `_unpackMilliEthToWei(uint64(sub.amount))` for the box seed/EV-cap; (c) `validThroughLevel` writes at the two sites drop the now-redundant uint32 cast (`_passHorizonOf` already returns uint24); (d) the three day-marker stores (`lastOpenedDay`/`lastAutoBoughtDay` from `processDay`, `lastOpenedDay` from the open's `day`) cast to uint24 (day indices fit by construction; the open's seed/word-key local stays uint32 to feed the uint32-keyed `rngWordByDay`). These reuse the existing milli-ETH helpers and preserve the SOLVENCY-01 byte-unchanged ETH debit (the rounding is on the stamp's EV/seed input only).
- **Files modified:** `contracts/modules/GameAfkingModule.sol` (UNCOMMITTED, accumulates for the 354-06 batch)
- **Verification:** `forge build` exits 0.
- **Committed in:** NOT committed — left in the working tree per the Phase 354 contract-commit override (single USER-approved batched contract commit at 354-06).

---

**Total deviations:** 1 auto-fixed (1 blocking). **Impact on plan:** Necessary to satisfy the plan's `forge build` exit-0 success criterion given the producer-before-consumer wave order; semantically aligned with the LOCKED milli-ETH/uint24 design (no scope creep, no behavior change beyond the storage re-denomination this plan owns). The deeper accrue/settle logic on these fields remains owned by 354-03/04/05.

## Issues Encountered
None beyond the Rule-3 build-preserving cast adjustment documented above. The pre-existing `unsafe-typecast` forge-lint warnings (e.g. `DegenerusGameLootboxModule.sol:1895/1909`) are baseline/out-of-scope and were not introduced by this plan — not touched.

## Known Stubs
None. The accumulator fields are storage declarations with locked semantics; their accrue/settle WRITERS are authored in 354-03/04/05 (per the producer-before-consumer wave plan) — this is the intended declared-here / advanced-later split, not a stub.

## User Setup Required
None.

## Next Phase Readiness
- The re-packed slot is the substrate Wave 2+ consumers compile against: `GameAfkingModule` per-buy accrue + `_settleQuest` (354-03), the affiliate PULL `claim`/`withdraw` + `pendingClaim` declaration (354-04), the ticket buyer-bonus accrue (354-05).
- `drainAffiliateBase` accessor and the debit-gated `afkCoveredThroughDay` advance are NOT yet authored (354-03 owns them) — expected and documented in the NatSpec.
- Contract edits are UNCOMMITTED and will accumulate through Wave 2-4 for the single USER hand-review commit at 354-06. No `contracts/` path has been staged.

## Self-Check: PASSED

- FOUND: `.planning/phases/354-.../354-01-SUMMARY.md`
- MODIFIED (uncommitted, per Phase 354 override): `contracts/storage/DegenerusGameStorage.sol`, `contracts/modules/GameAfkingModule.sol`
- All 5 accumulator/marker fields present in `struct Sub`; 3 dropped settle markers absent; `forge build` exit 0.

---
*Phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre*
*Completed: 2026-06-01*
