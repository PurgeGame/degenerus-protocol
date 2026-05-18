# Phase 293: HRROLL Regression Fixture (TST-HRROLL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-17
**Phase:** 293-hrroll-regression-fixture-tst-hrroll
**Areas discussed:** Gray-area selection (multi-select), Stale `getDailyHeroWinner` view disposition

---

## Gray-Area Selection (multi-select)

Presented four candidate gray areas for user disposition; user selected only one.

| Option | Description | Selected |
|--------|-------------|----------|
| Test-invocation strategy for `_rollHeroSymbol` (private view) | JS-replay only (Phase 282 + 291 precedent) vs visibility-flip + harness (reopens Phase 292 contract for `private`→`internal` flip + `contracts/test/HeroRollTester.sol`) | |
| TST-HRROLL-06 empirical-gas measurement methodology | Production-path delta (worst-case-seeded vs all-zero-seeded `payDailyJackpot` `gasUsed` delta) vs harness paired-call `noOp` isolation (depends on invocation strategy) | |
| Stale `getDailyHeroWinner` public view at DegenerusGame.sol:2545 | Leftover v41 deterministic-leader public view; semantically misleading post-HRROLL; locked under HRROLL-07 ABI byte-identity; needs disposition (TST file JSDoc note / Phase 296 SWEEP / Phase 297 finding-candidate / v43+ deferred) | ✓ |
| TST-HRROLL-03 RNG commitment-window proof technique at fixture level | Direct-storage-read assertion (`getStorageAt` on `dailyHeroWagers[D][q]` slots) vs behavioral-replay against `_rollHeroSymbol` (requires private-function exposure) | |

**User's choice:** Stale `getDailyHeroWinner` only.

**Notes:** User explicitly opted out of discussing the other three areas — strong signal that planner-discretion defaults are accepted for invocation strategy + empirical-gas methodology + commitment-window technique. Defaults captured in CONTEXT.md `<decisions>` Claude's Discretion subsection (D-293-INVOKE-01 JS-replay; D-293-GAS-01 production-path delta with escalation paths; TST-HRROLL-03 direct-storage-read).

---

## Stale `getDailyHeroWinner` View Disposition

Presented four dispositions for `contracts/DegenerusGame.sol:2545` (leftover v41 deterministic-leader public view; locked under HRROLL-07; `@notice` semantically misleading post-Phase 292).

| Option | Description | Selected |
|--------|-------------|----------|
| Document in TST-HRROLL test-file JSDoc header only (Recommended) | Note in new test file's path-of-investigation JSDoc: `getDailyHeroWinner` is v41-leftover indexer-helper; not used as TST-HRROLL assertion vehicle. Zero source-tree mutation. | |
| Surface to Phase 296 SWEEP for adversarial inclusion | Add to 293-CONTEXT.md `<deferred>` as a SWEEP-02 hypothesis candidate: front-running / MEV / coordinated-betting exposure from stale public projection. Hands to `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` at Phase 296. | |
| Promote to Phase 297 terminal-audit finding-candidate | Note in 293-CONTEXT.md that stale-semantic should land in `audit/FINDINGS-v42.0.md` §3.A delta-surface (or §3.B finding-block if SWEEP escalates) under F-42-NN candidate `stale view function semantic post-HRROLL`. Mirrors v41 row (F) `getDailyHeroWager` ACCEPTED_DESIGN pattern. | |
| Defer to v43+ explicit cleanup phase | Park as a v43+ backlog item: future milestone re-opens DegenerusGame.sol for NatSpec-only update OR full removal after indexer-team migration. No Phase 293 / 296 / 297 footprint; pure forward-cite per Phase 297 D-42N-FCITE-01 "Deferred to Future Milestones" register pattern. | ✓ |

**User's choice:** Defer to v43+ explicit cleanup phase.

**Notes:** User chose pure forward-cite with zero v42.0-milestone footprint — no JSDoc note, no Phase 296 SWEEP inclusion, no Phase 297 finding-candidate. The stale view is parked entirely outside the v42.0 audit-subject boundary; v43+ has the bandwidth to choose the right disposition shape (rewrite, remove, or formally accept-design with a F-43-NN block). Captured as D-293-STALE-VIEW-01 in CONTEXT.md `<decisions>` + forward-cite in `<deferred>`.

---

## Claude's Discretion

Planner & executor latitude granted (user opted-out of discussion, defaults apply per CONTEXT.md `<decisions>` Claude's Discretion subsection):

- **D-293-INVOKE-01** — Test-invocation strategy for `_rollHeroSymbol`. Default: JS-replay oracle ALGORITHM_VERIFIED per Phase 282 + 291 lineage. New helper `test/helpers/rollHeroSymbolRef.mjs` (mirror of `raritySymbolBatchRef.mjs` shape). Cross-attest JS↔EVM via small-N (16–64 iter) production-path replay parsing `DailyWinningTraits` event. Visibility-flip escalation path NOT pre-approved.
- **D-293-GAS-01** — TST-HRROLL-06 empirical-gas methodology. Default: production-path delta (worst-case-seeded vs all-zero-seeded `payDailyJackpot` `gasUsed` delta). Soft +500 / hard +750 vs v41 ~9494 baseline per Phase 292 §3.c lock. Noise-floor escalation path NOT pre-approved (visibility-flip OR relaxed bound + theoretical-cite).
- **TST-HRROLL-03 commitment-window technique** — Default: direct-storage-read via `ethers.provider.getStorageAt` on `dailyHeroWagers[D][q]` slots; replay JS-reference impl against captured byte set.
- **Test file shape & location** — Default: new file `test/edge/HeroOverrideWeightedRoll.test.js` (mirrors Phase 291 + 282 adjacency); single file all-6-assertions; do NOT extend frozen v41 `HeroOverrideDayIndex.test.js`.
- **Chi² implementation pattern** — Default: reuse inline `wilsonHilfertyZ` + `CHI2_CRIT_05` pattern from `test/stat/PerPullLevelDistribution.test.js`; no helper extraction for single new consumer.
- **JS-reference impl shape** — Default: pure-function bit-mirror of `_rollHeroSymbol` body (L1639-1700); `ethers.utils.defaultAbiCoder.encode(["uint256","uint32"], ...)` for the `abi.encode(entropy, day)` keccak input per D-42N-DETERMINISM-01.
- **Test fixture deployment shape** — Default: `loadFixture(deployFixture)` per Phase 291 + 282 pattern. `hardhat_setStorageAt` cheatcode acceptable for synthetic state seeding in the chi² loop; production `placeDegeneretteBet` path for TST-HRROLL-03 commitment-window proof.
- **Single USER-APPROVED batched test commit at phase close** — Default per `feedback_batch_contract_approval.md` (no `git push`).

## Deferred Ideas

- **Stale `getDailyHeroWinner` public view** — v43+ explicit cleanup phase per D-293-STALE-VIEW-01 (forward-cite into Phase 297 §9 "Deferred to Future Milestones" register pattern; no v42.0 footprint).
- **D-293-INVOKE-01 visibility-flip escalation** — Phase-292 contract amendment NOT pre-approved; planner surfaces only at the D-293-GAS-01 noise-floor escalation checkpoint.
- **D-293-GAS-01 noise-floor relaxation alternative** — relaxed bound + theoretical-cite fallback NOT pre-approved; surfaced at same escalation checkpoint as the visibility-flip alternative.
- **TST-HRROLL-02 roadmap-math reconciliation** — roadmap success criterion 2 expected leader pick-rate `(500 + 250) / 1250 = 60%` does NOT reconcile against `_rollHeroSymbol` arithmetic for seed `[500, 100, 100, 100]` (actual `(500+250)/(800+250) ≈ 71.4%`). Plan-phase surfaces and resolves at TST-HRROLL-02 implementation step.
- **Chi² helper extraction to `test/helpers/chiSquare.mjs`** — v43+ test-maintenance bundle if statistical tests proliferate.
- **`test/helpers/raritySymbolBatchRef.mjs` extension with HRROLL** — explicitly NOT done; new separate file `rollHeroSymbolRef.mjs` per file-per-audit-subject convention.
