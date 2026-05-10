# Phase 268: Degenerette Statistical Validation + Cross-Surface Preservation - Context

**Gathered:** 2026-05-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Author 3 NEW `test/stat/` files + extend `test/stat/SurfaceRegression.test.js` with v37.0 byte-identity describe + 1 NEW `test/gas/` worst-case quickPlay regression test, all validating the Phase 267 5-table dispatch + producer + ETH-split rule against the live contract surfaces. Reuse-only of Phase 261/264/266 chi² tooling (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ`); zero new statistical primitives introduced.

**Audit baseline:** v36.0 closure HEAD `1c0f09132d7439af9881c56fe197f81757f8164a`. v37.0 source-tree HEAD at Phase 268 close = Phase 267 contract commit `e1136071` (TraitUtils + DegeneretteModule batched diff already shipped).

**Phase 268 boundary state at close:**

- 4 NEW test files + 1 EXTENDED test file landing under a single batched USER-APPROVED test-tree commit (per Phase 266 precedent `16ed452b` — single batched test commit covering all NEW + EXTENDED files; treats test-tree under `feedback_no_contract_commits.md` discipline batched per `feedback_batch_contract_approval.md`):
  - NEW `test/stat/DegenerettePerNEvExactness.test.js` — STAT-01 + STAT-05 + STAT-07 (per-N basePayoutEV exactness ≥1M draws; match-count histogram per N within ±0.5% bin; ETH payout-split 3-tier distribution + thin-pool cap-flip subcase)
  - NEW `test/stat/DegeneretteProducerChi2.test.js` — STAT-02 + STAT-06 (producer color [16,16,16,16,16,16,16,8]/120 chi² + symbol uniform 1/8 chi² ≥1M samples; α=0.05; reuse-only chi² tooling)
  - NEW `test/stat/DegeneretteBonusEv.test.js` — STAT-03 + STAT-04 (per-N hero-boost EV ±1% + per-N WWXRP factor EV ±1%, ≥100K draws each)
  - EXTENDED `test/stat/SurfaceRegression.test.js` — v37.0 describe block asserting SURF-01..04 byte-identity (TraitUtils existing functions + JackpotModule v34.0 surfaces + LootboxModule v36.0 surfaces + EntropyLib hash2/entropyStep)
  - NEW `test/gas/Phase268GasRegression.test.js` (or extend `AdvanceGameGas.test.js` with v37.0 describe — planner picks) — SURF-06 worst-case quickPlay gas envelope + advanceGame ±2K vs v36.0 baseline
- `package.json` `test:stat` script wiring: 3 new file-paths added to the existing space-separated list (matches Phase 266 wiring pattern).
- ZERO source-tree mutations (`contracts/**/*.sol` byte-identical at Phase 268 close vs Phase 267 close).
- 13 requirements (STAT-01..07 + SURF-01..06) flipped to PASS at Phase 268 close; PROGRESS table flipped 1/1 → 2/2 (single multi-task plan).
- Phase 269 lootbox dead-branch cleanup (LBX-01..03) + GASPIN-01..03 SURF-05 re-pinning OUT of Phase 268 scope.

</domain>

<decisions>
## Implementation Decisions

### Carry-forward (locked from prior milestones — not re-asked)

- **D-268-FILES-01 (single canonical audit deliverable, Phase 271):** Mirror v36 D-266-FILES-01 / v37 Phase 267 D-267-FILES-01. NOT a Phase 268 concern.
- **D-268-CLOSURE-01 (signal SHA = HEAD at audit-pass-close):** Mirror v36 D-266-CLOSURE-01. NOT a Phase 268 concern.
- **D-268-CLOSURE-02 (commit-readiness register §9.NN three-subsection):** Mirror v36 D-266-CLOSURE-02. Phase 268 SUMMARY contributes the §9.NN.ii USER-APPROVED tests row.
- **D-268-SEV-01 (D-08 5-bucket severity rubric):** NOT a Phase 268 concern.
- **D-268-APPROVAL-01 (audit/.planning writes agent-author):** Phase 268 SUMMARY + PLAN + DISCUSSION-LOG + CONTEXT all AGENT-COMMITTED.
- **D-268-APPROVAL-02 (test commits USER-APPROVED batched):** Per `feedback_no_contract_commits.md` (test-tree treated identically to contract-tree) + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Phase 268 has 1 batched test-tree commit (3 NEW stat + 1 EXTENDED surface + 1 NEW gas, plus `package.json` wiring); agent presents diff and waits for explicit user "approved" before committing. Mirrors Phase 266 `16ed452b` precedent.

### Carry-forward (locked from Phase 267)

- **D-268-CONSTVERIFY-CARRY-01 (constants byte-identity already proved):** D-267-CONSTVERIFY-01 grep-asserted all 25 packed constants (`QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 × `M8` + 5 × `HERO_BOOST_N{0..4}_PACKED` + 5 × `WWXRP_FACTORS_N{0..4}_PACKED`) match `derive_5_tables.py` Fraction-exact output byte-for-byte. Phase 268 STAT-01..05 verifies the dispatch *applies* the constants correctly (catches mis-routed table assignments in `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpFactor` per-N if/else legs that the constant-grep misses).
- **D-268-PRODUCER-API-CARRY-01 (existing TraitUtils functions byte-identical):** `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` UNCHANGED (D-267-PRODUCER-API-01); SURF-01 asserts this at the byte level via the v37.0 describe extension to `SurfaceRegression.test.js`.
- **D-268-NORM-DELETED-CARRY-01 (no runtime normalizer):** `_evNormalizationRatio` DELETED at Phase 267 (D-267-NORM-01); STAT-01 measures EV against the bare 5-table dispatch (no normalizer correction layer).
- **D-268-PAYSPLIT-CARRY-01 (3-tier ETH split rule shipped):** D-267-PAYSPLIT-01..05 shipped at Phase 267. STAT-07 empirically verifies tier behavior + thin-pool cap-flip path.

### Locked this discussion

- **D-268-HARNESS-01 (hybrid JS-replay + on-chain spot-check for STAT-01/03/04):** Bulk Monte Carlo (≥1M draws for STAT-01; ≥100K for STAT-03/04) runs in pure JS replicating the per-N dispatch tables — fast, deterministic, matches Phase 264 PerPullLevelDistribution + Phase 266 LootboxEntropyDistribution precedent. Then a small on-chain spot-check (5 ETH-currency `placeDegeneretteBet` calls with deterministic VRF, one per N ∈ {0..4}) calls the actual deployed contract path and asserts payout == JS-computed value. Catches dispatch-chain mis-routing (e.g., HERO_BOOST_N2 wired to N=3 leg) that the constant-grep AND pure-JS replay both miss because the JS replica copies the same mistake. Spot-check sample count is small (5 calls); does not blow Hardhat call latency budget.

- **D-268-THINPOOL-01 (pool-cap excess flip — fresh deployment + small pool seed via existing admin entry):** STAT-07 thin-pool subcase uses a Hardhat `loadFixture`-style fresh deployment with the pool seeded via the existing pool-funding entry (presale or admin seed — planner identifies exact path). Pool size chosen so a known tier-1 payout (e.g., 2× bet) exceeds 10% of `futurePool`. Single targeted on-chain `placeDegeneretteBet` call; assertions: (a) `PayoutCapped(player, ethShare, lootboxShare)` event fires; (b) `ethShare == pool * ETH_WIN_CAP_BPS / 10_000`; (c) `ethShare + lootboxShare == payout` (conservation invariant); (d) pool-cap precedence holds even on tier-1 ≤3× bet payout (overrides the all-ETH passthrough). Bulk 1M-draw STAT-07 distribution sweep runs against a normal/large pool fixture so cap-flip doesn't dominate distribution. Avoids `setStorageAt` brittleness.

- **D-268-SURF03-01 (lootbox SURF-03 file-level zero-diff at Phase 268 close; Phase 269 owns SURF-03 update):** Phase 268 SURF-03 asserts `git diff 1c0f0913 HEAD -- contracts/modules/DegenerusGameLootboxModule.sol` returns empty output (TRUE at Phase 268 close because Phase 267 doesn't touch lootbox). Mirrors the existing v36.0 describe pattern in `test/stat/SurfaceRegression.test.js` L408+ (file-level git-diff hunk-intersection harness). Phase 269 LBX scope already extends test code (LBX-02 extends `LootboxOpenGas.test.js`); SURF-03 update (re-baseline to Phase-268-close HEAD OR add explicit allowed-hunk exception for the dead-branch L1568-1581 deletion) lands in Phase 269's batched test commit. Each SURF-03 version is honest at its respective HEAD; no lying about state that hasn't shipped.

- **D-268-WORSTGAS-01 (SURF-06 deterministic VRF override + crafted player pick + max numTickets per `feedback_gas_worst_case.md` letter):** Theoretical worst-case quickPlay path derived FIRST in test-file header NatSpec:
  - **N = 3** — longest dispatch chain in `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpFactor` (hits `if N==0 / else if N==1 / else if N==2 / else if N==3 / [else N=4]`; N=4 fall-through saves one comparison so N=3 is worst).
  - **M = 8** per ticket — color+symbol full-match across all 4 quadrants; jackpot path takes separate per-N M=8 SLOAD.
  - **Hero quadrant active + match** — fires HERO_BOOST_N{N}_PACKED SLOAD + multiplication path (penalty branch is cheaper).
  - **ETH-currency tier 3** — `payout > 10 * betAmount` triggers the lootbox-conversion path via `_resolveLootboxDirect` (~50K extra gas per ticket vs tier 1 all-ETH).
  - **Max numTickets per call** — planner identifies exact cap from contract.
  - **Optional: pool-cap excess flip** — extra `PayoutCapped` event emit; tested as a separate sub-case (single-ticket flip vs ceiling) to keep the headline worst-case test pure.
  Test construction: deterministic VRF-word injection via the same pattern used in `test/fuzz/DegeneretteFreezeResolution.t.sol` L19-23 ("injects a lootbox RNG word"). Engineer rngWord so `packedTraitsDegenerette(rngWord)` produces a result-ticket with 4 gold-symbol-matching quadrants vs a crafted player-pick. ETH-currency at tier 3 by setting `betAmount` such that the resulting M=8 N=3 payout triggers `payout > 10 * betAmount`. Max-numTickets per call. Measure gas via Hardhat tx.gasUsed; assert ≤ derived analytical ceiling AND advanceGame envelope ±2K vs v36.0 baseline (`Phase264GasRegression.test.js` advance-gas pin baseline). If the existing Mocha-side fixtures lack a VRF-override helper, add a minimal Hardhat-side helper that mirrors the Foundry-side pattern (planner picks exact form). Per `feedback_gas_worst_case.md`: builds the exact state, doesn't statistically reach.

- **D-268-PLAN-01 (single multi-task plan):** Mirror v33/v34/v35/v36/v37-Phase-267 single-multi-task-atomic-commit-per-task precedent. `268-01-PLAN.md` ordering (planner refines exact decomposition):
  1. **Chore:** test-file authoring sketches + reusable-helper inventory (re-confirm Phase 261/264/266 chi² tooling reuse path; confirm VRF-override helper availability at Mocha side; identify pool-funding admin entry for D-268-THINPOOL-01; identify advanceGame baseline pin file for SURF-06).
  2. **Test impl + USER-APPROVED batched commit:** All 4 NEW + 1 EXTENDED test files authored — (a) `DegenerettePerNEvExactness.test.js` STAT-01 + STAT-05 + STAT-07 (incl. thin-pool fixture sub-case + on-chain spot-checks per D-268-HARNESS-01); (b) `DegeneretteProducerChi2.test.js` STAT-02 + STAT-06; (c) `DegeneretteBonusEv.test.js` STAT-03 + STAT-04 (incl. on-chain spot-checks per D-268-HARNESS-01); (d) `SurfaceRegression.test.js` v37.0 describe extension SURF-01..04 (file-level zero-diff per D-268-SURF03-01); (e) `Phase268GasRegression.test.js` (or extension) SURF-06 deterministic worst-case + advanceGame envelope (per D-268-WORSTGAS-01); (f) `package.json` `test:stat` script wiring for the 3 new stat files. One diff, one approval, one commit.
  3. **Phase-close:** `268-01-SUMMARY.md` + 13-requirement PASS table + STATE.md flip + commit-readiness register update (i USER-APPROVED contracts: 0 commits — Phase 268 owns no contract changes; ii USER-APPROVED tests: 1 commit; iii AGENT-COMMITTED planning artifacts: PLAN + SUMMARY).
  ~3 atomic commits total. Single-plan-multi-task discipline.

### Claude's Discretion (planner refines)

- **JS-replay style for STAT-01..05:** straight per-N dispatch tables in JS objects vs class wrapper vs imported module. Planner picks; minimal overhead is direct JS objects mirroring the contract constant layout.
- **Sample-budget upper bound:** ROADMAP locks ≥1M for STAT-01 + STAT-02 + STAT-05; ≥100K for STAT-03 + STAT-04. Planner may go higher if test-runtime budget allows; floor is ROADMAP-locked.
- **`Phase268GasRegression.test.js` vs extending `AdvanceGameGas.test.js`:** Phase 264 used `Phase264GasRegression.test.js`; Phase 266 extended `AdvanceGameGas.test.js` v36.0 describe. Planner picks per file-organization preference. Default: NEW `Phase268GasRegression.test.js` matches Phase 264 precedent and isolates the worst-case quickPlay test from advanceGame-focused test file.
- **Per-N dispatch JS-replay table format:** packed bigint constants (closer to contract layout) vs unpacked array per N. Planner picks; unpacked array is more readable, packed bigint matches contract byte-for-byte.
- **VRF-override helper placement:** inline in each test file vs new `test/helpers/vrfOverride.js` module. Planner picks; if reusable across SURF-06 + STAT-01 spot-checks + STAT-07 thin-pool, helper module is cleaner.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 268 Anchors

- `.planning/ROADMAP.md` §"Phase 268: Degenerette Statistical Validation + Cross-Surface Preservation" — 5 success criteria; depends-on = Phase 267 (the per-N dispatch + producer + payout-split rule is the unit under empirical test).
- `.planning/REQUIREMENTS.md` STAT-01..STAT-07 + SURF-01..SURF-06 — 13 v37.0 requirements all mapped to Phase 268.
- `.planning/STATE.md` — milestone v37.0 status; Phase 267 SHIPPED (`e1136071` contract commit + 3 AGENT-COMMITTED chore/planning); Phase 268 next.
- `.planning/PROJECT.md` — current focus banner.

### Phase 267 Source-of-Truth (locked decisions consumed by Phase 268)

- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-CONTEXT.md` — Phase 267 lock register. Phase 268 inherits D-267-CONSTVERIFY-01 (constant byte-identity proved); D-267-PRODUCER-API-01 (existing TraitUtils byte-identical → SURF-01); D-267-PAYSPLIT-01..05 (3-tier ETH rule → STAT-07); D-267-EV-TARGET-01 (per-N basePayoutEV = 100 centi-x exact → STAT-01).
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-CONSTANTS-VERIFY.md` — Phase 267 working file. Byte-identity grep proof for the 25 packed constants. Phase 268 STAT-01..05 catches dispatch-chain mistakes that this grep misses.
- `.planning/notes/2026-05-10-degenerette-payout-recalibration.md` — exhaustive ~540-line planning note. §"Locked decisions" + §"Concrete file changes" + §"Constants paste reference". Source-of-truth for the per-N table values and dispatch logic Phase 268 tests against.
- `.planning/notes/degenerette-recalibration/derive_5_tables.py` — `Fraction`-exact derivation of all 25 constants. Phase 268 STAT-01/03/04/05 may re-import the per-N table data from this script's stdout (or a small extracted JSON sidecar) for the JS-replay path.

### Live Contract State (test subject — Phase 267 close HEAD `e1136071`)

- `contracts/DegenerusTraitUtils.sol` — `packedTraitsDegenerette` (L201+) is the producer under STAT-02 chi² test. Existing `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` byte-identical → SURF-01 byte-identity assertion.
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — primary test subject:
  - `_countGoldQuadrants(uint32 ticket) → uint8` (L859) — input to per-N dispatch.
  - `_getBasePayoutBps(uint8 N, uint8 matches) → uint256` — per-N payout dispatch (5 if/else legs + M=8 separate SLOAD).
  - `_applyHeroMultiplier(uint256 payout, uint32 playerTicket, uint32 resultTicket, uint8 matches, uint8 heroQuadrant, uint8 N) → uint256` — symbol-only hero match + per-N HERO_BOOST dispatch.
  - `_wwxrpFactor(uint8 N, uint8 bucket)` (L923) — per-N WWXRP factor dispatch.
  - `_distributePayout(player, currency, betAmount, payout, rngWord)` — 3-tier ETH split rule + pool-cap precedence (STAT-07 + thin-pool sub-case).
  - 25 packed constants L254-258 (payouts) + L281-285 (WWXRP) + L337-341 (HERO) + 5 M=8 jackpots (separate uint256s) — JS-replay tables mirror these.
- `contracts/modules/DegenerusGameJackpotModule.sol` — UNTOUCHED at Phase 267 → SURF-02 byte-identity assertion. v34.0 `_pickSoloQuadrant` + 4 ETH-distribution injection sites + `JackpotBucketLib`.
- `contracts/modules/DegenerusGameLootboxModule.sol` — UNTOUCHED at Phase 267 → SURF-03 file-level zero-diff vs v36.0 baseline `1c0f0913` (per D-268-SURF03-01). Phase 269 will modify this file; SURF-03 updates land in Phase 269 batched test commit.
- `contracts/libraries/EntropyLib.sol` — UNTOUCHED → SURF-04 byte-identity (`hash2` + `entropyStep` carry v36.0 ENT-04).

### Existing Test Infrastructure (REUSE-ONLY per STAT-06)

- `test/stat/TraitDistribution.test.js` L48-56 / L87-90 / L97-100 — origin of `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` chi² primitives. Phase 268 re-declares verbatim per Phase 266 carry pattern.
- `test/stat/PerPullLevelDistribution.test.js` L78-102 — Phase 264 carry of the chi² primitives. Reference template for STAT-02 producer chi² shape.
- `test/stat/LootboxEntropyDistribution.test.js` L45-69 — Phase 266 carry of the chi² primitives. Reference template for `% small` slice uniformity tests.
- `test/stat/SurfaceRegression.test.js` L408+ — v36.0 SURF-01..04 describe block (`describe("v36.0 SURF-01..04 — protected ranges byte-identical vs v35.0 baseline 5db8682b")`). Phase 268 adds a parallel `describe("v37.0 SURF-01..04 — ...")` block with v36.0 baseline `1c0f0913`.
- `test/gas/Phase264GasRegression.test.js` — Phase 264 gas-pin file. Reference template for `Phase268GasRegression.test.js` shape.
- `test/gas/AdvanceGameGas.test.js` — advanceGame envelope baseline. Phase 268 reads the v36.0-pinned values from this file (or its v36.0 extension) and asserts ±2K under SURF-06.
- `test/fuzz/DegeneretteFreezeResolution.t.sol` L19-23 — Foundry-side deterministic VRF-word injection precedent ("injects a lootbox RNG word"). Phase 268 SURF-06 mirrors this pattern at the Mocha side (or via fork harness — planner picks).
- `package.json` `test:stat` script — Phase 266 added 3 new file-paths to the space-separated list (`16ed452b` test commit). Phase 268 adds 3 more (`DegenerettePerNEvExactness` + `DegeneretteProducerChi2` + `DegeneretteBonusEv`).

### v36.0 / v37-Phase-267 Precedent (test-batch commit discipline)

- `.planning/milestones/v36.0-phases/266-lootbox-entropy-refactor/266-01-PLAN.md` — single-multi-task atomic-commit-per-task precedent.
- Phase 266 `16ed452b` test-tree commit — single batched USER-APPROVED commit covering 2 NEW (`LootboxEntropyDistribution.test.js` + `LootboxOpenGas.test.js`) + 2 EXTENDED (`AdvanceGameGas.test.js` + `SurfaceRegression.test.js`) + `package.json` script wiring (+912/-2 LOC across 4 test files + script). Phase 268 mirrors this batching discipline.
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-PLAN.md` — Phase 267 single-multi-task plan precedent. Phase 268 mirrors structure.
- `.planning/phases/267-degenerette-producer-5-table-payout-rewrite/267-01-SUMMARY.md` — phase-closure SUMMARY format precedent.

### Memory / Feedback Governing This Phase

- `feedback_no_contract_commits.md` — explicit per-commit user approval for `contracts/` + `test/` changes. Phase 268 has 1 batched test commit covering all NEW + EXTENDED files + `package.json` wiring.
- `feedback_batch_contract_approval.md` — batch all phase test edits, present one diff at end. Phase 268 follows by combining 5 test files + `package.json` into a single diff/commit.
- `feedback_never_preapprove_contracts.md` — orchestrator/agent must NOT pre-approve any test commit. Vacuous unless agent attempts to claim pre-approval.
- `feedback_wait_for_approval.md` — D-268-APPROVAL-02 test-diff approval gate. Agent presents the batched diff, waits for explicit "approved" before committing.
- `feedback_manual_review_before_push.md` — final user-review gate before any push. NO `git push` by agent.
- `feedback_gas_worst_case.md` — D-268-WORSTGAS-01 derives theoretical worst case FIRST (N=3 + M=8 + hero match + ETH tier 3 + max numTickets), then constructs deterministic VRF-injection test that hits exactly that state. Per the rule's letter ("Build or modify a test that constructs that exact state").
- `feedback_skip_research_test_phases.md` — Phase 268 has clear, mechanical scope (test files with exact assertions specified in ROADMAP success criteria + locked decisions in this CONTEXT.md). Skip research-agent dispatch; jump straight to plan-phase.
- `feedback_test_rnglock.md` — N/A for Phase 268 (no rngLocked changes; Phase 267 didn't touch coinflip RNG locks).
- `feedback_rng_backward_trace.md` — N/A for Phase 268 (no RNG audit; Phase 271 owns AUDIT-02 surface (b) symbol-only hero RNG analysis).
- `feedback_no_history_in_comments.md` — Test-file NatSpec describes the per-N dispatch as the CURRENT design. NEVER reference "this used to be a normalizer" or "previous color distribution" anywhere in test source.
- `feedback_no_dead_guards.md` — N/A for Phase 268 (lootbox dead-branch cleanup is Phase 269).
- `feedback_contractaddresses_policy.md` — N/A; Phase 268 doesn't touch `ContractAddresses.sol`.

### Active KI Envelope

- `KNOWN-ISSUES.md` — current state at v36.0 close. EXC-04 NARROWED to BAF-jackpot-only scope at v36. Phase 268 makes no KI changes (KI walkthrough lives in Phase 271 AUDIT-05).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Chi² tooling (verbatim re-declaration per STAT-06):** `makeRng` + `CHI2_CRIT_05` + `wilsonHilfertyZ` from `test/stat/TraitDistribution.test.js` L48-56/L87-90/L97-100 (origin) → carried in Phase 264 + Phase 266. Phase 268 re-declares verbatim in each NEW stat test file (no shared helper module; matches existing precedent). REUSE-ONLY discipline per STAT-06 — zero new statistical primitives.
- **Per-N table data (paste-ready):** 25 packed constant byte-values already in `contracts/modules/DegenerusGameDegeneretteModule.sol` L254-341. Phase 268 JS-replay reads those values (or re-runs `derive_5_tables.py` and consumes the stdout) into JS bigint constants matching the contract layout. The Phase 267 D-267-CONSTVERIFY-01 grep already proved these match the script output byte-for-byte.
- **`SurfaceRegression.test.js` describe-block pattern:** L408+ v36.0 describe shows the `git diff baseline HEAD -- path` hunk-intersection check pattern. Phase 268 adds a parallel v37.0 describe with `1c0f0913` baseline.
- **Foundry deterministic VRF injection:** `test/fuzz/DegeneretteFreezeResolution.t.sol` L19-23 ("injects a lootbox RNG word") — Foundry-side pattern for the SURF-06 worst-case construction. May need a Mocha-side mirror helper; planner picks.
- **`Phase264GasRegression.test.js` shape:** Phase 264 gas-pin file as reference template for `Phase268GasRegression.test.js`.
- **`loadFixture` deployment pattern:** standard Hardhat test pattern for the STAT-07 thin-pool fixture (D-268-THINPOOL-01).
- **`derive_5_tables.py`:** Re-runnable Python `Fraction`-exact derivation. Phase 268 may extract a small JSON sidecar (e.g., `derive_5_tables.json` written alongside the script) to feed JS-side replay tables — keeps the Python source as single-source-of-truth.

### Established Patterns

- **Single batched test commit per phase** — Phase 266 `16ed452b` precedent (2 NEW + 2 EXTENDED + script wiring in one USER-APPROVED commit). Phase 268 inherits.
- **Atomic-commit per task** — v33/v34/v35/v36/v37-P267 single-plan multi-task pattern. Phase 268 inherits.
- **Chi² primitives re-declared verbatim per file** (not shared module) — Phase 264 + 266 precedent. Tests are self-contained; reduces inter-file coupling.
- **Seed convention `0xC037_NNNN`** — Phase 268 follows the per-milestone seed family pattern (Phase 261 `0xC033_*`, Phase 264 `0xC035_*`, Phase 266 `0xC036_*`). Distinct seed per test/bucket per cross-test isolation discipline.
- **Sample-budget calibration in test-file NatSpec header** — Phase 266 LootboxEntropyDistribution L1-34 documents per-bucket sample counts + α=0.05 chi² thresholds + sub-roll bit ranges. Phase 268 mirrors this NatSpec discipline.
- **Worst-case derivation in test-file NatSpec header** — `feedback_gas_worst_case.md` requires deriving the theoretical worst case in the test-file header before any measurement. SURF-06 follows.

### Integration Points

- **`test/stat/`** — 3 NEW files (`DegenerettePerNEvExactness.test.js`, `DegeneretteProducerChi2.test.js`, `DegeneretteBonusEv.test.js`) + 1 EXTENDED (`SurfaceRegression.test.js` v37.0 describe block).
- **`test/gas/`** — 1 NEW file (`Phase268GasRegression.test.js`) OR EXTENSION of `AdvanceGameGas.test.js` (planner picks per Claude's Discretion).
- **`package.json`** — `test:stat` script wiring: 3 new file-paths added to the existing space-separated list. `test` script wiring: add `Phase268GasRegression.test.js` if NEW (matches `Phase264GasRegression.test.js` + `LootboxOpenGas.test.js` precedent).
- **`.planning/phases/268-degenerette-statistical-validation-cross-surface-preservation/`** — phase artifacts: `268-CONTEXT.md` (this file), `268-01-PLAN.md` (planner output), `268-01-SUMMARY.md` (executor output), `268-DISCUSSION-LOG.md` (sibling to this file).
- **`audit/FINDINGS-v37.0.md`** — does NOT exist yet at Phase 268 close; authored in Phase 271. Phase 268 contributes the §3a per-phase summary content (test-tree only; zero source-tree mutations) and §4 surface (h) empirical evidence for the 3-tier ETH split rule.

</code_context>

<specifics>
## Specific Ideas

### Worst-case quickPlay derivation (SURF-06 — paste-ready NatSpec header sketch)

```javascript
// SURF-06 — worst-case quickPlay gas envelope (v37.0).
//
// Per `feedback_gas_worst_case.md`, the theoretical worst-case quickPlay path
// is derived FIRST, then constructed deterministically.
//
// Worst-case dimensions:
//   N = 3            — longest dispatch chain in _getBasePayoutBps /
//                      _applyHeroMultiplier / _wwxrpFactor; N=4 falls through
//                      the `else` saving one comparison.
//   M = 8            — full color+symbol match across all 4 quadrants;
//                      jackpot path takes separate per-N M=8 SLOAD.
//   hero match       — symbol matches the hero quadrant; HERO_BOOST_N3 SLOAD
//                      + multiplication path (penalty branch is cheaper).
//   ETH tier 3       — payout > 10 * betAmount; lootbox-conversion path via
//                      _resolveLootboxDirect (~50K extra gas per ticket).
//   numTickets = MAX — planner identifies exact contract cap.
//
// Construction: deterministic VRF-word injection (mirrors
// test/fuzz/DegeneretteFreezeResolution.t.sol). Engineer rngWord so
// packedTraitsDegenerette(rngWord) yields a result-ticket with exactly
// 4 gold-AND-symbol-matching quadrants vs a crafted player-pick (player
// has N=3 gold quadrants; result has 4 gold quadrants matching player's
// 3 + 1 non-gold matching player's 4th color; all 4 symbols match).
// betAmount sized so payout > 10 * betAmount (ETH tier 3).
//
// Assertion: gas <= analytical ceiling AND advanceGame envelope ±2K vs
// v36.0 baseline.
```

### STAT-07 thin-pool sub-case sketch

```javascript
// STAT-07 thin-pool sub-case — pool-cap excess flip path.
// Fresh deployment + small pool seed via existing admin entry.
// Pool: 1 ether (small).
// Bet: 0.01 ether (tier-1 candidate).
// Expected payout (deterministic VRF): ~0.02 ether (M=4 N=2 region; tier 1
// ≤3× bet path; would normally pay 100% ETH = 0.02 ether).
// 10% pool cap: 0.1 ether — exceeds 0.02 ether so cap doesn't bind...
// → instead engineer pool = 0.1 ether (so 10% cap = 0.01 ether) and payout
// = 0.02 ether → cap binds: ethShare = 0.01 ether, lootboxShare = 0.01 ether.
// Assert PayoutCapped event + ethShare/lootboxShare values + conservation.
```

### `package.json` `test:stat` wiring delta

```diff
-"test:stat": "hardhat test test/gas/Phase261GasRegression.test.js test/gas/Phase264GasRegression.test.js test/stat/TraitDistribution.test.js test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js test/stat/SurfaceRegression.test.js test/stat/PerPullLevelDistribution.test.js test/stat/PerPullEmptyBucketSkip.test.js test/stat/LootboxEntropyDistribution.test.js"
+"test:stat": "hardhat test test/gas/Phase261GasRegression.test.js test/gas/Phase264GasRegression.test.js test/gas/Phase268GasRegression.test.js test/stat/TraitDistribution.test.js test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js test/stat/SurfaceRegression.test.js test/stat/PerPullLevelDistribution.test.js test/stat/PerPullEmptyBucketSkip.test.js test/stat/LootboxEntropyDistribution.test.js test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteProducerChi2.test.js test/stat/DegeneretteBonusEv.test.js"
```

(Planner refines exact file ordering. `Phase268GasRegression.test.js` belongs in `test:stat` if it pins gas as a stat-suite expectation; alternatively in the `test` script if it's treated as a unit-test class. Phase 264/261 gas-regression files live in `test:stat`, so Phase 268 mirrors.)

### Hero-EV per-N analytical reference

For each N ∈ {0..4}, the per-N HERO_BOOST_N{N}_PACKED tables encode multipliers for matches M ∈ {2..7} (16 bits each, packed 6-wide into uint96). Hero-EV invariant: `P(symbol match | M, N) × boost_N(M) + (1 - P(...)) × HERO_PENALTY ≈ HERO_SCALE` within 0.05% tolerance per-N. STAT-03 measures empirically vs this analytical target ±1%.

</specifics>

<deferred>
## Deferred Ideas

### Phase 269 lootbox dead-branch cleanup (LBX-01..03)

`DegenerusGameLootboxModule.sol _resolveLootboxRoll` ~L1568-1581 dead `if (targetLevel < currentLevel)` branch. Routed to Phase 269. Phase 268 SURF-03 file-level zero-diff at Phase 268 close (per D-268-SURF03-01) means SURF-03 will need a Phase 269 update to either re-baseline or accept the dead-branch deletion hunk.

### Phase 269 SURF-05 gas-pin re-pinning (GASPIN-01..03)

Phase 261/264 SURF-05 ~120K gas-pin drift under `npm run test:stat` ordering. Routed to Phase 269. Phase 268 doesn't touch gas pins.

### Phase 270 post-v32.0 deferred-commit adversarial sub-audit (`002bde55` + `2713ce61`)

Carry-forward deferral. Phase 270 audit-only. NOT a Phase 268 concern.

### Phase 271 §4 surface (h) audit (boundary-gaming + composition correctness)

Phase 268 STAT-07 provides empirical evidence for the 3-tier ETH split rule. Phase 271 AUDIT-02 surface (h) consumes this evidence for the boundary-gaming + composition adversarial check. NOT a Phase 268 concern beyond surfacing the test data.

### `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion for Phase 271

Resolve at Phase 271 discuss-phase. NOT a Phase 268 concern.

### Optional `test/helpers/vrfOverride.js` shared module

If the deterministic VRF-override pattern is needed in 3+ places (SURF-06 + STAT-01 spot-checks + STAT-07 thin-pool), planner may extract a shared helper. Default: inline per file, mirrors verbatim chi²-tooling re-declaration discipline (STAT-06). Planner picks.

### Optional `derive_5_tables.json` sidecar for JS-replay

`derive_5_tables.py` could optionally write a JSON sidecar (`derive_5_tables.json`) alongside its stdout; Phase 268 JS-replay tests could `import` that JSON instead of hardcoding bigint constants. Default: hardcode bigints in JS (matches contract paste convention). Planner picks if JSON sidecar reduces drift risk.

### `_jackpotTicketRoll` BAF jackpot xorshift refactor (v36 ENT-05 carry)

Out of v37.0 scope per `.planning/REQUIREMENTS.md` Out of Scope table. Tracked for future milestone.

### `runrewardjackpots` module-misplacement (2026-04-02 stale backlog note)

Out of v37.0 scope.

### Game-over thorough hardening (`gameover-thorough-test.md`)

Out of v37.0 scope.

</deferred>

---

*Phase: 268-degenerette-statistical-validation-cross-surface-preservation*
*Context gathered: 2026-05-10*
