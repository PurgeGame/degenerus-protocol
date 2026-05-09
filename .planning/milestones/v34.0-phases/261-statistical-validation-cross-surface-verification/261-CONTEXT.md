# Phase 261: Statistical Validation + Cross-Surface Verification - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

A new Hardhat statistical-validation surface (`test/stat/`) drives empirical proofs of the v34.0 trait + solo invariants:
- 1M-sample empirical color-frequency + chi-squared independence (color/symbol joint) + symbol uniformity over `weightedColorBucket(uint32)` / `traitFromWord(uint64)` (TRAIT-01..02 outputs).
- 100K-sample gold-solo coverage (100% on gold-present draws) + tie-break uniformity (chi² p > 0.05 across goldCount ∈ {2,3,4}) over `_pickSoloQuadrant(uint8[4], uint256)` (SOLO-01 helper).
- Per-surface ~3.3× solo-EV uplift simulation across the 3 ETH-distribution surfaces (final-day / daily / purchase).
- ≥100K-pack pack-feel CIs (≥1 notable in 99.5%, rare in 92.3%, epic in 71.7%, legendary in 27.0%).
- Cross-surface preservation evidence for hero override (SURF-01), deity-pass virtual entries (SURF-02), Degenerette match payouts (SURF-03), and the 8 non-injection bonus-jackpot sites (SURF-04).
- Gas regression evidence (SURF-05) — `weightedColorBucket` ±100 gas vs the v33.0 `weightedBucket(uint32)`; `_pickSoloQuadrant` < 500 gas worst-case (4-gold); per-call delta on `runTerminalJackpot` / `payDailyJackpot` / `_resumeDailyEth` < 2000 gas. Theoretical worst case derived FIRST (per `feedback_gas_worst_case.md`), then HEAD-only measured.

In scope:
- New `test/stat/` directory with one Hardhat ESM test file per success-criterion family (planner picks consolidation; reference shape: `TraitDistribution.test.js`, `GoldSoloCoverage.test.js`, `SoloEvUplift.test.js`, `PackFeel.test.js`).
- Reuse the existing testers `contracts/test/TraitUtilsTester.sol` (Phase 259) and `contracts/test/JackpotSoloTester.sol` (Phase 260) — no new tester contract.
- New `test/stat/` opt-in npm script (`npm run test:stat`) that is NOT triggered by default `npm test` so the 1M-sample tests stay out of the per-commit CI loop.
- New `test/stat/SurfaceRegression.test.js` (or split per SURF-NN) for SURF-01..04 (mostly behavioral spot-checks + structural grep for the 8 non-injection sites).
- New `test/gas/Phase261GasRegression.test.js` for SURF-05 — theoretical worst-case derivation in the test header comment, HEAD-only measurement asserting against the derived bound.
- Update `.planning/REQUIREMENTS.md` STAT-01..07 + SURF-01..05 with the per-surface analytical uplift numbers locked here (D-04) so the spec ↔ code stay in lockstep.

Out of scope (deferred to Phase 262):
- Delta audit + findings consolidation (`audit/FINDINGS-v34.0.md`).
- Re-verification of v33.0 + v32.0 closure signals (REG-01..04).
- KI envelopes EXC-01..04 re-verification at Phase-261-post HEAD.

Out of scope (carried forward, not Phase 261):
- Any `contracts/` source-file edits (Phase 261 is test-only — `contracts/test/*.sol` testers from Phase 259 + 260 are reused as-is, no module logic touched). Per `feedback_no_dead_guards.md` no new safety caps; per `feedback_no_history_in_comments.md` no comment churn; per `feedback_contract_locations.md` only contracts/ is canonical.

</domain>

<decisions>
## Implementation Decisions

### Test directory + CI integration (default applied — not discussed)
- **D-01:** New `test/stat/` directory holds the heavy Monte Carlo + chi² + per-surface-uplift suite. Naming mirrors the existing per-domain test directories (`test/unit/`, `test/integration/`, `test/gas/`, `test/edge/`, `test/governance/`, `test/access/`, `test/validation/`, `test/halmos/`). The roadmap goal text already calls out "a new Hardhat statistical-validation test directory (e.g. `test/stat/`)" — this locks that choice.
- **D-02:** Opt-in `npm run test:stat` script in `package.json`; default `npm test` does NOT invoke `test/stat/` so the 1M-sample tests stay out of the per-commit CI loop. Planner adds the `mocha --recursive test/stat/` (or equivalent) script entry. Default-CI runtime budget unchanged from v33.0.

### Sample generation oracle (default applied — not discussed)
- **D-03:** Hybrid oracle — JS-replicated `weightedColorBucket(uint32) → uint8` thresholds for the bulk 1M-sample MC tests (microseconds per sample) **paired with a tester-driven cross-validation harness** that calls `TraitUtilsTester.weightedColorBucket(rnd)` at every boundary value `scaled ∈ {0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255}` (the 16 cases from `test/unit/DegenerusTraitUtils.test.js` TRAIT-05) and asserts JS-replica = production-bytes for the full coverage of every threshold edge. JS replica drift is structurally impossible without the cross-validation harness failing first.
  - For STAT-04..06 (100K samples each, on `_pickSoloQuadrant`): tester-driven (call `JackpotSoloTester.pickSoloQuadrant(traits, entropy)` per sample — same pattern as `test/unit/JackpotSoloPicker.test.js` SOLO-08(c) which already runs 100K samples per goldCount via tester calls). Acceptable runtime (Phase 260 reference: ~104ms for the full 13-assertion suite covering 3 chi² runs at 100K each with smaller per-test counts; full 100K per-test takes seconds-to-tens-of-seconds on the local Hardhat node).

### STAT-06 EV-uplift simulation (discussed)
- **D-04:** Per-surface assertion model. Three independent 100K-sample MCs at base bucket counts:
  - **Final-day surface** (`runTerminalJackpot` L282; BPS `[6000, 1333, 1333, 1334]`; counts `[25, 15, 8, 1]`): asserted single-gold uplift **3.80×** (60% / 15.79%); avg over goldCount~Binomial(4, 1/128) | ≥1-gold ≈ **3.78×**.
  - **Daily jackpot surface** (`payDailyJackpot` L349 + `_resumeDailyEth` L1147; BPS `[2000, 2000, 2000, 2000]`; counts `[25, 15, 8, 1]`): asserted single-gold uplift **3.25×** (20% / 6.16%); goldCount-averaged ≈ **3.21×**.
  - **Purchase-phase surface** (`payDailyJackpot` L524; BPS `[2000, 2000, 2000, 2000]`; counts `[25, 15, 8, 1]`): asserted single-gold uplift **3.25×** at base counts. (PROJECT.md mention of `[20, 12, 6, 1]` is a post-cap approximation at moderate pool — under D-05 base counts the purchase surface is identical to daily.)
  - Headline "~3.3× solo-bucket EV uplift" preserved as the 3-surface average (final-day + daily + purchase ≈ 3.4× with goldCount-weighting). REQUIREMENTS.md STAT-06 amendment under D-08 below.
- **D-05:** Bucket-count assumption — **base counts `[25, 15, 8, 1]` (low-pool, no scaling)**. All 3 surface sims set `ethPool < JACKPOT_SCALE_MIN_WEI` (or call the uncapped path) so `JackpotBucketLib.traitBucketCounts(entropy)` returns base unchanged. No pool-scaling confound. Pool-dependent regimes (mid-pool / max-cap) deferred (see deferred list below).
- **D-06:** Tolerance — **±5% relative** on the measured uplift vs analytical expectation. At 100K samples, the standard error of the uplift ratio is ~0.5–1% relative (under multinomial sampling); a ±5% bound gives 5σ safety margin and absorbs any reasonable JS-replica precision drift.
- **D-07:** "Gold-trait holder" model — **owns-the-gold-quadrant-ticket** (Recommended). For each MC draw conditioned on ≥1 gold winning trait, pick the gold-color winning quadrant; compute the "EV-with-priority" payout share (1/goldCount × solo-bucket-payout + (goldCount-1)/goldCount × E[non-solo-bucket-payout]) and "EV-baseline" payout share (1/4 × solo + 3/4 × E[non-solo]); average ratio across all conditioned-on-≥1-gold draws.
- **D-08:** REQUIREMENTS.md STAT-06 wording amendment (recorded for the planner): replace the floating "~3.3×" with the per-surface vector `[final-day ≈ 3.78×, daily ≈ 3.21×, purchase ≈ 3.21×]` and the "averaged across surfaces ≈ 3.4×" note. Tolerance ±5% relative. The amendment is mechanical; landing it alongside the Phase 261 plan keeps the spec ↔ code in lockstep (mirrors Phase 260 D-13/D-14 amendment posture).

### SURF-01..04 cross-surface preservation method (default applied — not discussed)
- **D-09:** Mostly-structural with targeted behavioral spot-checks (matches roadmap text: "confirms hero override / deity-pass virtual entries / Degenerette match payouts / bonus-jackpot non-injection sites are unchanged in behavior"):
  - **SURF-01** (hero override): existing hero-override coverage in `test/integration/GameLifecycle.test.js` runs unchanged. Add ONE new spot-check: hero override with a color==7 (gold) byte input flows through `_applyHeroOverride` byte-identically (verifies the new color tier reaches the byte layout `(quadrant << 6) | (color << 3) | symbol` correctly). The 3-bit literal slice path (NOT through `weightedColorBucket`) is preserved per SURF-01 NOTE — verify no false-positive by injecting `weightedColorBucket` here.
  - **SURF-02** (deity-pass): existing `test/unit/DegenerusDeityPass.test.js` runs unchanged. Add no new test — deity-pass `floor(2% × bucketTickets)` math is symbol-distribution-agnostic at the integer level.
  - **SURF-03** (Degenerette match payouts): existing `test/unit/DegenerusGame.test.js` (Degenerette section) + `test/fuzz/DegeneretteFreezeResolution.t.sol` (Foundry, byte-layout regression) run unchanged. No new test (carrying forward Phase 259 D-09 — fuzz `packedTraitsFromSeed` consumer is the implicit byte-layout regression).
  - **SURF-04** (8 non-injection bonus-jackpot sites at lines 513, 527, 598, 599, 683, 1687, 1713, 1715): structural grep proof — JS test runs `git diff 4ce3703d HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` and asserts none of those 8 line-equivalent hunks appear in the patch (already informally checked at Phase 260 close; Phase 261 makes it a CI-enforced regression). Equivalent shape via `child_process.execSync` or `simple-git`. Planner picks the harness shape.
- **D-10:** No `contracts/` writes in Phase 261 — only `test/stat/`, `test/gas/`, possibly `test/unit/HeroOverrideColorTier.test.js`, and `package.json` (npm script entry). The two existing testers (`TraitUtilsTester.sol`, `JackpotSoloTester.sol`) are reused as-is. Per `feedback_no_contract_commits.md` the `package.json` script entry + every new test file still requires explicit user approval at the batched-diff phase close (D-12).

### Gas regression methodology (carried forward via memory)
- **D-11:** Theoretical worst-case derivation FIRST per `feedback_gas_worst_case.md`, then HEAD-only measurement. Specifically:
  - `_pickSoloQuadrant` worst case = 4-gold input (every loop iteration appends to `goldQuads`, then mod-4 fallthrough). Theoretical ceiling derived from opcode-by-opcode walk of the helper body (D-08 Phase 260): ~4 × (LT + AND + ADD + SSTORE-like-memory-write) ≈ 200–250 gas + final modulo + array index read ≈ 50 gas → < 350 gas estimated. Test asserts < 500 gas (memory-derived bound from REQUIREMENTS.md SURF-05) — the ~150-gas slack covers ABI calldata decoding overhead in the tester wrapper.
  - `weightedColorBucket(uint32) → uint8` ±100 gas vs the v33.0 `weightedBucket(uint32)` — both are 8-comparator `if` chains under `unchecked`. Theoretical delta is 0 (same opcode count, different threshold constants). Test asserts measured gas equals the v33.0 reference value within ±100 gas. Reference value: a single number recorded in the test file header comment from a 1-time v33.0 binary measurement (NOT a continuous A/B harness — per the carry-forward, we don't resurrect the v33.0 binary).
  - Per-call delta on `runTerminalJackpot` / `payDailyJackpot` / `_resumeDailyEth` < 2000 gas: theoretical delta = 1 helper call (`_pickSoloQuadrant`) + 1 `effectiveEntropy` derivation + 1 substitution = ≤ ~500 gas per site. Test measures HEAD-only via existing fixture from `test/integration/GameLifecycle.test.js` and asserts each entry-point call is below the 2000-gas absolute headroom.

### Approval & commit posture (carried forward)
- **D-12:** All `test/` + `package.json` edits in this phase are batched and presented as one diff at the end of the phase per `feedback_batch_contract_approval.md`; user approval is explicit per commit (no orchestrator pre-approval) per `feedback_no_contract_commits.md` and `feedback_never_preapprove_contracts.md`.
- **D-13:** Skip research-agent dispatch per `feedback_skip_research_test_phases.md` — phase is fully specified in REQUIREMENTS.md (STAT-01..07 + SURF-01..05) with explicit thresholds, sample sizes, p-value bounds, and surface-line numbers. Plan directly. Mirrors Phase 259 D-11 + Phase 260 D-11 mechanical-phase posture.
- **D-14:** Plan slicing left to the planner. Reference shape (3-plan packing): P1 = `test/stat/TraitDistribution.test.js` (STAT-01..03) + JS-replica + boundary cross-validation harness; P2 = `test/stat/GoldSoloCoverage.test.js` (STAT-04..05) + `test/stat/SoloEvUplift.test.js` (STAT-06) + `test/stat/PackFeel.test.js` (STAT-07); P3 = SURF-01..04 surface preservation (`test/stat/SurfaceRegression.test.js` or per-SURF split) + SURF-05 gas regression (`test/gas/Phase261GasRegression.test.js`) + REQUIREMENTS.md STAT-06 amendment (D-08). Single-plan or 2-plan packings also acceptable.

### Claude's Discretion
- Test-file consolidation within `test/stat/` (one file per success-criterion family vs single mega-file). Planner default: per-family file.
- Exact JS chi² critical-value table — extend `CHI2_CRIT_05` from `test/unit/JackpotSoloPicker.test.js` (df 1..3) to df 1..7 (color buckets minus 1 = 7) for STAT-01.
- Seeded-keccak PRNG seed values per test (each test gets a distinct integer seed; reproducibility = exact-replay on failure). Mirrors `makeRng(seed)` from `test/unit/JackpotSoloPicker.test.js`.
- Reverse-mapping helper `rndForScaled(scaled)` from `test/unit/DegenerusTraitUtils.test.js` reused / promoted to `test/helpers/`.
- Hardhat fixture composition for the SURF-01 hero-override spot-check (`GameLifecycle.test.js` is the closest reference; planner picks fixture).
- Whether SURF-04's grep proof is a Hardhat JS test (uses `child_process.execSync` for `git diff`) or a shell script invoked via `package.json` `prestat` hook. Default: Hardhat JS test for fail-fast in the same `test:stat` invocation.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — STAT-01..07 (1M-sample empirical color-frequency, color/symbol independence, symbol uniformity, gold-solo coverage, tie-break uniformity, EV uplift, pack-feel CIs) + SURF-01..05 (hero override, deity-pass, Degenerette, 8 non-injection sites, gas regression). **Note D-08 amendment** — STAT-06 wording amendment (per-surface vector + tolerance) lands alongside the implementation plan; the planner reconciles wording.
- `.planning/ROADMAP.md` §"Phase 261: Statistical Validation + Cross-Surface Verification" — Goal statement, Success Criteria 1-5, Depends-on (Phase 259 + Phase 260), per-surface tolerance (±0.1% on color frequency, p > 0.05 on chi², ≥99% MC CIs on pack-feel).
- `.planning/PROJECT.md` §"Current Milestone: v34.0" — Tie-break decision (random-among-gold, option B); `JackpotBucketLib` UNCHANGED; bucket share BPS UNCHANGED; bucket counts UNCHANGED at base. Note the PROJECT.md `[20, 12, 6, 1]` purchase-phase number is a post-cap approximation — D-05 explicitly anchors the simulation to the base `[25, 15, 8, 1]` counts (the only invariant the contract guarantees).

### Contracts under empirical test (READ-only — no edits in Phase 261)
- `contracts/DegenerusTraitUtils.sol` — `weightedColorBucket(uint32) → uint8` (TRAIT-01), `traitFromWord(uint64) → uint8` (TRAIT-02), `packedTraitsFromSeed(uint256) → uint32` (byte-layout-stable). Targets of STAT-01..03 + STAT-07.
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_pickSoloQuadrant(uint8[4], uint256) → uint8` (SOLO-01) helper. Target of STAT-04..06. The 4 ETH-distribution injection sites (282 / 349 / 524 / 1147) are surfaces under SURF-05 gas measurement; the 8 non-injection sites (513, 527, 598, 599, 683, 1687, 1713, 1715) are under SURF-04 grep proof.
- `contracts/libraries/JackpotBucketLib.sol` — UNCHANGED (SOLO-07 carry-forward). Source of truth for `traitBucketCounts(entropy) = base [25, 15, 8, 1] rotated by entropy & 3`, `shareBpsByBucket(packed, offset)`, `soloBucketIndex(entropy) = (3 - (entropy & 3)) & 3`. The base bucket counts are pinned here — STAT-06 simulation reads this as the analytical reference.

### Test surfaces being added (NEW — Phase 261)
- `test/stat/` (NEW directory) — Monte Carlo + chi² + per-surface uplift + pack-feel CIs.
- `test/stat/SurfaceRegression.test.js` (or per-SURF split) — SURF-01..04 cross-surface preservation evidence.
- `test/gas/Phase261GasRegression.test.js` (NEW) — SURF-05 gas regression with theoretical-worst-case derivation in the test header comment.
- `test/unit/HeroOverrideColorTier.test.js` (NEW, optional — planner may fold into `SurfaceRegression.test.js`) — SURF-01 spot-check for color==7 byte-layout.
- `package.json` `scripts.test:stat` (NEW entry) — opt-in heavy-test invocation.

### Test surfaces reused (NO edits)
- `contracts/test/TraitUtilsTester.sol` — Phase 259 tester. Reused for STAT-01..03 boundary cross-validation (D-03) + STAT-07 pack-feel sampling.
- `contracts/test/JackpotSoloTester.sol` — Phase 260 tester. Reused for STAT-04..06 (gold-coverage + tie-break + EV-uplift simulations).
- `test/unit/DegenerusTraitUtils.test.js` — Phase 259 boundary unit tests; `rndForScaled(scaled)` helper extracted/reused (Claude's Discretion above).
- `test/unit/JackpotSoloPicker.test.js` — Phase 260 chi² unit tests; `makeRng(seed)` deterministic PRNG + `CHI2_CRIT_05` table reused/extended.
- `test/integration/JackpotSoloSplit.test.js` — Phase 260 integration test; reference fixture pattern for SURF-01 hero-override spot-check.
- `test/integration/GameLifecycle.test.js` — Existing hero-override + lifecycle test surface; reference for SURF-01 fixture composition + SURF-05 entry-point gas measurement (3 entry points: `runTerminalJackpot`, `payDailyJackpot`, `_resumeDailyEth`).
- `test/unit/DegenerusGame.test.js` — Existing Degenerette section runs unchanged for SURF-03 (no new test added).
- `test/unit/DegenerusDeityPass.test.js` — Runs unchanged for SURF-02 (no new test added).
- `test/fuzz/DegeneretteFreezeResolution.t.sol` — Foundry fuzz consuming `packedTraitsFromSeed`; runs unchanged for SURF-03 byte-layout regression.

### Memory / feedback governing this phase
- `feedback_no_contract_commits.md` — explicit per-commit user approval for all `contracts/` + `test/` changes (Phase 261 has zero `contracts/` writes; `test/` + `package.json` writes still gated).
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end (D-12).
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved.
- `feedback_no_history_in_comments.md` — comments describe what IS; no "previously was" or "changed from".
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch for mechanical phases (D-13).
- `feedback_no_dead_guards.md` — no unreachable safety caps in any new test scaffolding.
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push test changes without diff review.
- `feedback_gas_worst_case.md` — derive theoretical worst case FIRST, then test (D-11).
- `feedback_rng_backward_trace.md` — every RNG audit traces backward from each consumer; here, SURF-04's 8 non-injection sites are RNG consumers — the grep proof confirms backward trace is preserved.
- `feedback_rng_commitment_window.md` — what player-controllable state can change between VRF request and fulfillment for these consumers; carried forward from Phase 260 (no new commitment-window paths introduced; tests are passive observers of the existing VRF window).
- `feedback_test_rnglock.md` — does not apply to Phase 261 (rngLocked-removal-from-coinflip-claim-paths is a separate workstream); noted for awareness only.
- `feedback_contract_locations.md` — only `contracts/` is canonical; tests reference `contracts/` only, never any stale copy.

### Prior-phase context
- `.planning/phases/259-trait-distribution-split/259-CONTEXT.md` — Phase 259 distribution-split decisions (color thresholds, byte-layout constants, tester pattern). D-07 single-file Hardhat layout pattern reused here.
- `.planning/phases/259-trait-distribution-split/259-VERIFICATION.md` — Phase 259 closure evidence (TRAIT-01..06 satisfied; `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed` live + byte-layout regression via the existing fuzz).
- `.planning/phases/260-gold-solo-priority-injection/260-CONTEXT.md` — Phase 260 helper + injection decisions (D-04 mod-bias fix, D-08 canonical site-local block shape). The chi² + 100K-sample tester pattern in `test/unit/JackpotSoloPicker.test.js` is the reference shape for STAT-04..06.
- `.planning/phases/260-gold-solo-priority-injection/260-VERIFICATION.md` — Phase 260 closure evidence (SOLO-01..09 satisfied; `_pickSoloQuadrant` live + 4 sites injected + 8 non-injection sites byte-identical).

### Milestone & state
- `.planning/PROJECT.md` — v34.0 milestone goal (trait rarity rework + gold solo priority); contract HEAD anchor `4ce3703d740d3707c88a1af595618120a8168399` (v33.0 baseline; v34.0 baseline-of-record for SURF-04 grep + SURF-05 gas-regression reference number).
- `.planning/STATE.md` — Phase 260 → Phase 261 transition; Phase 261 in planning.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`contracts/test/TraitUtilsTester.sol`** (Phase 259) — Already exposes `weightedColorBucket(uint32) → uint8`, `traitFromWord(uint64) → uint8`, `packedTraitsFromSeed(uint256) → uint32` as `external pure` passthroughs. Reused as-is for D-03 boundary cross-validation + STAT-07 pack-feel sampling. No new tester contract needed.
- **`contracts/test/JackpotSoloTester.sol`** (Phase 260) — Already exposes `pickSoloQuadrant(uint8[4], uint256) → uint8` as an `external pure` passthrough. Reused as-is for STAT-04..06. The 100K-sample chi² pattern at goldCount ∈ {2,3,4} is already proven in `test/unit/JackpotSoloPicker.test.js` SOLO-08(c).
- **`test/unit/DegenerusTraitUtils.test.js`** — Phase 259 boundary tests; `rndForScaled(scaled)` reverse-mapping helper (`rnd = scaled << 24`) is the canonical way to construct boundary inputs. Promoted/reused for the boundary cross-validation harness (D-03).
- **`test/unit/JackpotSoloPicker.test.js`** — Phase 260 chi² tests; `makeRng(seed)` deterministic keccak-counter PRNG + `CHI2_CRIT_05` (df 1..3) inline critical-value table + the `traitsByColors` helper. All reused/extended for STAT-01..06.
- **`test/integration/GameLifecycle.test.js`** — Existing fixture for full game-lifecycle integration; reference for SURF-01 hero-override fixture composition + SURF-05 entry-point gas measurement.
- **`test/integration/JackpotSoloSplit.test.js`** — Phase 260 SOLO-09 integration test (L349 → L1147 split-mode coherence). Reference fixture pattern for any SURF-NN integration spot-check.

### Established Patterns
- **Hardhat ESM + chai expect — no Foundry for the new stat suite.** All existing `test/unit/`, `test/integration/`, `test/gas/`, `test/edge/`, `test/governance/`, `test/access/`, `test/validation/` JS tests use `@nomicfoundation/hardhat-toolbox/network-helpers` `loadFixture`, `chai` `expect`, `hre.ethers.getContractFactory`. The new `test/stat/` follows the same convention.
- **Foundry fuzz used only for byte-layout regression** (`test/fuzz/DegeneretteFreezeResolution.t.sol`). The new statistical surface is JS-side because the Monte Carlo volume requires a JS RNG + JS-replica oracle.
- **Per-contract test file convention** (Phase 259 D-08 carry-forward) — one file per testable surface family. Phase 261's `test/stat/` follows this: per-success-criterion file (TRAIT distribution / gold-solo coverage / EV uplift / pack-feel). Compatible with mocha's `--recursive test/stat/`.
- **Inline chi² critical-value tables** (Phase 260 precedent) — no jstat or simple-statistics dependency. Extend `CHI2_CRIT_05` to df 1..7 for STAT-01 (8 color buckets minus 1).
- **Seeded keccak-counter PRNG** (Phase 260 precedent) — deterministic, reproducible, cryptographically-uniform; ethers' built-in `keccak256` keeps the dependency footprint zero. Distinct integer seed per test file = exact replay on CI failure.
- **Tester deploy via fixture** (`PriceLookupTester` → `TraitUtilsTester` → `JackpotSoloTester` carry-forward) — `getContractFactory` + `deploy()` + `waitForDeployment()` inside `loadFixture`; cached across `it` blocks in the same `describe`.

### Integration Points
- **STAT-01..03 sample loop**: JS-side `for (let i = 0; i < 1_000_000; i++) { rnd = rng() & 0xFFFFFFFFn; color = jsReplicatedWeightedColorBucket(rnd); buckets[color]++; }`. Then chi² over the 8-bucket frequency vector against the analytical [25, 25, 25, 12.5, 6.25, 3.125, 2.344, 0.781]% expectation. Boundary cross-validation in a separate `describe`: 16 boundary `it` blocks calling `tester.weightedColorBucket(rndForScaled(scaled))` and asserting against the JS replica.
- **STAT-04..05 sample loop**: tester-driven (precedent from `JackpotSoloPicker.test.js`). For STAT-04: `for (let i = 0; i < 100_000; i++) { entropy = rng(); traits = randomTraitsWithAtLeastOneGold(); result = await tester.pickSoloQuadrant(traits, entropy); assert traits[result].color === 7; }`. For STAT-05: same but with `goldCount ∈ {2, 3, 4}` traits + chi² over the gold-quadrant assignment frequency.
- **STAT-06 sample loop**: per-surface MC at base counts. JS-side payout-share computation (analytically deterministic given trait colors + entropy + base counts + share BPS); tester used only for the gold-quadrant pick. Compute (with-priority avg) and (baseline avg) over 100K conditioned-on-≥1-gold draws; assert ratio within ±5% of analytical expectation per surface.
- **STAT-07 sample loop**: pack = 10 tickets × 4 quadrants = 40 trait rolls. For each pack: sample 40 trait words, count notable/rare/epic/legendary occurrences. Over 100K packs, estimate (≥1 of tier in pack) frequency; compute Wilson 99% CI; assert each target frequency falls within the CI. Tester-driven via `tester.packedTraitsFromSeed(seed)` (4 quadrants per call → 10 calls per pack → 1M tester calls total — slow but acceptable for opt-in suite). Alternative: JS-replica with the boundary cross-validation harness already covering correctness. Planner picks.
- **SURF-01 hero-override spot-check**: build a fixture where `_applyHeroOverride` is invoked with a known random word that, under the new distribution, yields a `color == 7` literal-slice (3-bit slice from RNG bits, NOT through `weightedColorBucket`). Assert byte-layout `(quadrant << 6) | (color << 3) | symbol` is preserved.
- **SURF-04 grep proof**: `child_process.execSync('git diff 4ce3703d HEAD -- contracts/modules/DegenerusGameJackpotModule.sol')`; parse the diff hunks; assert no hunk straddles or contains lines 513, 527, 598, 599, 683, 1687, 1713, 1715. Soft-fail mode if `4ce3703d` is not reachable in the current repo (e.g., shallow clone) — pass with a CI warning.
- **SURF-05 gas measurement**: `_pickSoloQuadrant` direct via tester gas snapshot (`hre.network.provider.send("evm_setAutomine", [false])`-style is unnecessary; just `await tester.pickSoloQuadrant.estimateGas(traits, entropy)` minus the calldata + transaction overhead, plus a Hardhat-built-in gas-measurement helper if available). For the 3 entry points: existing fixture from `GameLifecycle.test.js`, `await tx.wait()`, read `gasUsed` from the receipt; assert each value is below the absolute headroom (entry-point gas reference < 2000-gas-delta vs the v33.0 number recorded in the test file header).

</code_context>

<specifics>
## Specific Ideas

- Test directory layout (D-01 + D-14 reference shape):
  ```
  test/stat/
    TraitDistribution.test.js     // STAT-01 / STAT-02 / STAT-03 + boundary cross-validation
    GoldSoloCoverage.test.js      // STAT-04 / STAT-05
    SoloEvUplift.test.js          // STAT-06 (per-surface, base counts)
    PackFeel.test.js              // STAT-07
    SurfaceRegression.test.js     // SURF-01 / SURF-02 / SURF-03 / SURF-04
  test/gas/
    Phase261GasRegression.test.js // SURF-05 (theoretical worst-case derivation in header comment)
  ```
  Planner consolidates / splits as needed. Single-file packing (`test/stat/Phase261.test.js`) acceptable if the per-`describe` boundaries stay clean.
- Per-surface analytical EV-uplift numbers (D-04 — locked at base counts `[25, 15, 8, 1]`):
  - Final-day BPS `[6000, 1333, 1333, 1334]`: solo payout 60% / 1 ticket; non-solo E[per-ticket] = (1/3)(13.33%/25 + 13.33%/15 + 13.34%/8) ≈ 1.05%; baseline E = 1/4 × 60% + 3/4 × 1.05% ≈ 15.79%; **single-gold uplift = 60 / 15.79 ≈ 3.80×**.
  - Daily / Purchase BPS `[2000, 2000, 2000, 2000]`: solo payout 20% / 1 ticket; non-solo E = (1/3)(20%/25 + 20%/15 + 20%/8) ≈ 1.55%; baseline E = 1/4 × 20% + 3/4 × 1.55% ≈ 6.16%; **single-gold uplift = 20 / 6.16 ≈ 3.25×**.
  - goldCount-averaged uplift via Binomial(4, 1/128) | ≥1 gold:
    - P(1 | ≥1) ≈ 0.9874, P(2 | ≥1) ≈ 0.0117, P(3 | ≥1) ≈ tiny, P(4 | ≥1) ≈ tiny
    - Final-day avg: 0.9874 × 3.80 + 0.0117 × 1.93 + ... ≈ 3.78×
    - Daily / purchase avg: 0.9874 × 3.25 + 0.0117 × 1.65 + ... ≈ 3.21×
  - REQUIREMENTS.md STAT-06 amendment (D-08): replace floating "~3.3×" with the per-surface vector + ±5% relative tolerance.
- Boundary cross-validation harness (D-03) — extension of `test/unit/DegenerusTraitUtils.test.js` TRAIT-05:
  ```javascript
  // For each boundary value, verify JS replica matches production tester
  for (const [scaled, expectedColor] of BOUNDARIES) {
    const rnd = rndForScaled(scaled);
    const jsResult = jsReplicatedWeightedColorBucket(rnd);
    const onChainResult = await tester.weightedColorBucket(rnd);
    expect(jsResult).to.equal(BigInt(expectedColor));
    expect(onChainResult).to.equal(BigInt(expectedColor));
  }
  ```
- chi² critical-value extension (Claude's Discretion):
  ```javascript
  const CHI2_CRIT_05 = {
    1: 3.841, 2: 5.991, 3: 7.815, 4: 9.488,
    5: 11.070, 6: 12.592, 7: 14.067,
  };
  ```
- SURF-04 grep harness (D-09 + Integration Points above):
  ```javascript
  const NON_INJECTION_LINES = [513, 527, 598, 599, 683, 1687, 1713, 1715];
  const diff = child_process.execSync(
    "git diff 4ce3703d740d3707c88a1af595618120a8168399 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol"
  ).toString();
  for (const line of NON_INJECTION_LINES) {
    expect(diffContainsLine(diff, line)).to.be.false;
  }
  ```

</specifics>

<deferred>
## Deferred Ideas

- **Mid-pool / max-cap regime EV-uplift simulation** — D-05 pins STAT-06 to base counts. Pool-scaled regimes (mid-pool, max-cap-binding) deferred — may surface as a sub-criterion in Phase 262 KI re-verification or in a future post-v34.0 milestone if production telemetry shows a regime-specific uplift drift.
- **Fuzz / property-based shape for STAT-01..03** — Foundry fuzz with the new threshold table is conceivable but adds toolchain weight. JS Monte Carlo at 1M samples is sufficient for the spec. Defer to a later hardening pass if needed.
- **A/B gas comparison harness for SURF-05** — D-11 records HEAD-only measurement vs theoretical-worst-case bound. A live A/B harness (deploy v33.0 binary + HEAD binary, measure both) is more rigorous but adds dev-time complexity (git checkout dance + dual-deploy fixture). Memory `feedback_gas_worst_case.md` says theoretical-first; live A/B deferred unless theoretical bounds are exceeded.
- **Statistical false-positive mitigation (run-N-take-majority)** — chi² p > 0.05 has 5% false-positive per test; Phase 261 has ~5 chi² tests; total false-positive risk ~25%. D-05 + D-06 use deterministic seeds → false-positive risk is exactly 0% on green CI runs (a fixed seed either passes or fails permanently). If a future fresh-seed sweep is desired, that's a follow-on hardening pass.
- **Cross-surface verification at the deity-pass token-economy level** (SURF-02 extension) — a deeper verification that `floor(2% × bucketTickets)` per symbol on a 12.5% uniform symbol distribution does not introduce edge cases at small bucket sizes. Deferred — the existing deity-pass test suite (`test/unit/DegenerusDeityPass.test.js`) is the reference; if its coverage gaps surface in Phase 262 audit, address there.
- **Delta audit + findings consolidation (`audit/FINDINGS-v34.0.md`)** — Phase 262.
- **REG-01..04 KI envelope re-verification at Phase-261-post HEAD** — Phase 262.
- **AUDIT-01..05 + REG-01..04 all** — Phase 262 (terminal milestone phase).

</deferred>

---

*Phase: 261-statistical-validation-cross-surface-verification*
*Context gathered: 2026-05-08*
