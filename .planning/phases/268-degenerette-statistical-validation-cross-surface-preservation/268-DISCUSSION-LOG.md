# Phase 268: Degenerette Statistical Validation + Cross-Surface Preservation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-10
**Phase:** 268-degenerette-statistical-validation-cross-surface-preservation
**Areas discussed:** EV-exactness harness; STAT-07 thin-pool fixture; SURF-03 Phase 269 sequencing; SURF-06 worst-case gas construction

---

## EV-exactness harness — JS-replay vs on-chain dispatch

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid: JS-replay for the 1M-draw bulk + on-chain spot-checks at boundaries | Bulk Monte Carlo (1M draws) runs in pure JS replicating the per-N dispatch; small on-chain spot-check (5 deterministic ETH-currency calls, one per N) calls the actual deployed `_fullTicketPayout` and asserts payout equals JS-computed value. Catches dispatch-chain mis-routing without paying full Hardhat-call latency on 1M samples. | ✓ |
| Pure JS-replay only (Phase 264/266 precedent) | 1M draws in pure JS with replicated per-N dispatch. Fast (<10s). Defends on D-267-CONSTVERIFY-01. Risk: a mis-routed table assignment passes the constant-grep AND the JS-replay if the JS replica copies the same mistake. | |
| Pure on-chain dispatch via Hardhat call | Each draw triggers an actual contract call. Catches every contract-side mistake. Cost: 1M Hardhat calls is 10s of minutes-to-hours — likely infeasible. | |

**User's choice:** Hybrid: JS-replay for the 1M-draw bulk + on-chain spot-checks at boundaries
**Notes:** Locks D-268-HARNESS-01. Spot-check sample count is 5 (one per N ∈ {0..4}); payout assertion compares deployed-contract result to the JS-replay computation. The dispatch-chain mis-routing class of bug (e.g., `if (N == 2) packed = QUICK_PLAY_PAYOUTS_N3_PACKED;` swapped) is exactly what this catches above and beyond the constant-grep.

---

## STAT-07 thin-pool fixture for pool-cap excess flip

| Option | Description | Selected |
|--------|-------------|----------|
| Fresh deployment + small deterministic pool seed via existing admin entry | Hardhat `loadFixture` deployment with the existing pool-funding entry path. Pool seeded so a known tier-1 payout exceeds 10%. Single targeted on-chain quickPlay; assertions: PayoutCapped event + ethShare value + ethShare+lootboxShare=payout invariant. Pool-cap takes precedence even on tier-1 ≤3× bet payout. | ✓ |
| Hardhat `setStorageAt` to drain the pool storage slot directly | Bypass natural funding flow via `hardhat_setStorageAt`. Faster setup but tightly couples the test to the storage layout. Less idiomatic. | |
| Skip the thin-pool subcase — unit-test the formula instead | Pure-JS unit test of the `min(ethShare, pool * 1000 / 10000)` formula. Rejected — ROADMAP success criterion explicitly requires the path tested under a thin-pool fixture, not just formula-level. | |

**User's choice:** Fresh deployment + small deterministic pool seed via existing admin entry
**Notes:** Locks D-268-THINPOOL-01. Bulk 1M-draw STAT-07 distribution sweep runs against a normal/large pool fixture so cap-flip doesn't dominate distribution; thin-pool sub-case is a single targeted test. Conservation invariant `ethShare + lootboxShare == payout` asserted explicitly.

---

## SURF-03 — Phase 269 dead-branch sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Write SURF-03 at Phase 268 against v36.0 baseline (file-level zero-diff); let Phase 269 update SURF-03 | Phase 268 SURF-03 asserts `git diff 1c0f0913 HEAD -- contracts/modules/DegenerusGameLootboxModule.sol` is empty (TRUE at Phase 268 close because Phase 267 doesn't touch lootbox). Mirrors existing v36.0 describe pattern. Phase 269 LBX scope already extends test code; SURF-03 update lands in Phase 269 batched test commit. Each version honest at its HEAD. | ✓ |
| Defer SURF-03 entirely to Phase 269 | Phase 268 ships SURF-01/02/04 only. Phase 269 authors SURF-03 against post-cleanup HEAD. Adds chore task to update ROADMAP wording. | |
| Write SURF-03 as structural protected-ranges check (4 callsite line ranges, agnostic to dead branch) | Define protected ranges as the 4 hash2/bit-slice callsite line ranges at v36.0 baseline numbering. Survives Phase 269 cleanup. More elegant but L1569 callsite is in the cleanup region per Phase 269 ROADMAP — edge case. | |

**User's choice:** Write SURF-03 at Phase 268 against v36.0 baseline (file-level zero-diff); let Phase 269 update SURF-03
**Notes:** Locks D-268-SURF03-01. Each SURF-03 version is honest at its HEAD; no lying about state that hasn't shipped. Phase 269 either re-baselines SURF-03 to a Phase-268-close HEAD or adds an explicit allowed-hunk exception for the dead-branch L1568-1581 deletion.

---

## SURF-06 worst-case gas derivation construction

| Option | Description | Selected |
|--------|-------------|----------|
| Deterministic VRF override + crafted player pick + max numTickets | Engineer rngWord so `packedTraitsDegenerette(rngWord)` produces a result-ticket with 4 gold quadrants and all 4 symbols matching a crafted player-pick (player N=3, M=8 per ticket). ETH-currency tier 3. Max numTickets per call. Hardhat fixture exposes VRF override (mirrors `test/fuzz/DegeneretteFreezeResolution.t.sol` injection pattern). Per `feedback_gas_worst_case.md` letter — builds the exact state. | ✓ |
| Statistical reach via Monte Carlo + document gap to true worst case | Run ≥1000 randomly-seeded spins; record max observed gas; assert ≤ derived analytical ceiling. Cheaper to author; explicitly documents the gap. Risk: non-deterministic test (CI flakiness if max observed shifts). | |
| Hybrid — deterministic per-ticket + Monte Carlo full quickPlay | Two assertions: (a) deterministic single-ticket worst-case via thin harness; (b) Monte Carlo ≥1000 multi-ticket spins for full-path reach. More LOC. | |

**User's choice:** Deterministic VRF override + crafted player pick + max numTickets
**Notes:** Locks D-268-WORSTGAS-01. Worst-case dimensions (N=3 + M=8 + hero match + ETH tier 3 + max numTickets) derived in test-file NatSpec header FIRST per `feedback_gas_worst_case.md`. Foundry-side deterministic VRF injection at `test/fuzz/DegeneretteFreezeResolution.t.sol` L19-23 is the reference pattern; if Mocha-side fixtures lack a VRF-override helper, planner adds a minimal one.

---

## Claude's Discretion

The following items deferred to planner per Phase 268 CONTEXT.md `<decisions>` "Claude's Discretion" subsection:

- JS-replay style for STAT-01..05 (straight per-N dispatch tables in JS objects vs class wrapper vs imported module)
- Sample-budget upper bound (ROADMAP locks ≥1M / ≥100K floors; planner may go higher)
- `Phase268GasRegression.test.js` vs extending `AdvanceGameGas.test.js` (Phase 264 vs Phase 266 precedent — both valid)
- Per-N dispatch JS-replay table format (packed bigint vs unpacked array per N)
- VRF-override helper placement (inline per file vs `test/helpers/vrfOverride.js` shared module)

## Deferred Ideas

- Phase 269 lootbox dead-branch cleanup (LBX-01..03) — routed to Phase 269; Phase 268 SURF-03 needs Phase 269 update.
- Phase 269 SURF-05 gas-pin re-pinning (GASPIN-01..03) — routed to Phase 269.
- Phase 270 post-v32.0 deferred-commit adversarial sub-audit — routed to Phase 270.
- Phase 271 §4 surface (h) audit (boundary-gaming + composition) — Phase 268 STAT-07 provides empirical evidence; AUDIT-02 surface (h) is Phase 271 scope.
- `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion — resolve at Phase 271 discuss-phase.
- Optional `test/helpers/vrfOverride.js` shared module — planner picks if needed in 3+ places.
- Optional `derive_5_tables.json` sidecar for JS-replay table import — planner picks if it reduces drift risk.
- `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry) — out of v37.0 scope.
- `runrewardjackpots` module-misplacement — out of v37.0 scope.
- Game-over thorough hardening — out of v37.0 scope.
