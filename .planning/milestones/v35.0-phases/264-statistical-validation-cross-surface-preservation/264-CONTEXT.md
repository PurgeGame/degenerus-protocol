# Phase 264: Statistical Validation + Cross-Surface Preservation - Context

**Gathered:** 2026-05-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Empirical proof that Phase 263's per-pull-level resample (HEAD `cf564816`) is statistically uniform, byte-identical preserving for every unmodified `_randTraitTicket` other caller + `DailyWinningTraits` emit blocks + `_pickSoloQuadrant` injection sites + `_distributeTicketJackpot` + `_awardFarFutureCoinJackpot`, and inside the disclosed ~70K–110K gas envelope. Test-only phase: zero `contracts/*.sol` writes, zero new tester contracts (Phase 263 emits enough through `JackpotBurnieWin` for entry-point event harvesting).

In scope:
- New `test/stat/PerPullLevelDistribution.test.js` (or planner-chosen consolidation): STAT-01 chi² uniformity over `[minLevel, maxLevel]` (p > 0.05 at α=0.05) + STAT-02 per-trait share chi² (`< 7.815` at df=3 / α=0.05) under `i % 4` rotation. N ≥ 10K aggregated samples per the seed note + REQUIREMENTS.md.
- New `test/stat/PerPullEmptyBucketSkip.test.js` (or fold into the level-distribution file): STAT-03 empty-bucket skip-rate measurement vs analytical bound; cumulative monetary underspend bounded and disclosed in test header comment + Phase 265 §3.
- Extension of `test/stat/SurfaceRegression.test.js` (Phase 261 D-09 pattern): add `describe` blocks for SURF-01 `_randTraitTicket` other-caller byte-identity full-sweep + SURF-02 `_awardFarFutureCoinJackpot` byte-identity + SURF-03 `_pickSoloQuadrant` injection-site byte-identity (L282/L349/L524/L1147) + SURF-04 `_distributeTicketJackpot` byte-identity + `DailyWinningTraits` emit-block byte-identity + `_computeBucketCounts` definition byte-identity (D-INDEXER-01 + Phase 263 SUMMARY.md protected-range list). Single grep-proof harness via `child_process.execSync('git diff 6b63f6d4 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol')`.
- New `test/gas/Phase264GasRegression.test.js`: SURF-05 entry-point gas delta on `payDailyCoinJackpot` + `payDailyJackpotCoinAndTickets` with theoretical worst-case derivation in test header comment + HEAD-only measurement asserting against the disclosed 70K–110K envelope.
- Extension of `test/gas/AdvanceGameGas.test.js`: HEAD-only assertion that the 1.99× `advanceGame` ceiling margin is preserved at v35.0 HEAD (Success Criterion 5 in ROADMAP).
- Update `package.json` `scripts.test:stat` to include the new `test/stat/` files; the new gas test joins the default `npm test` invocation (matches Phase 261's `test/gas/AdvanceGameGas.test.js` placement at `package.json:8`).

Out of scope (deferred to Phase 265 — `audit/FINDINGS-v35.0.md`):
- Adversarial sweep + findings classification (AUDIT-01..06 + REG-01..04).
- KI envelope EXC-04 EntropyLib XOR-shift re-verification (gets explicit attention because per-pull-level keccak consumes high-entropy bits — empirical chi-squared evidence at STAT-01 + STAT-02 is cited end-to-end).
- KNOWN-ISSUES.md updates (only via D-09 gating decision).
- v34.0 + v33.0 closure-signal re-verification.
- `JackpotBurnieWin.lvl` + `DailyWinningTraits.bonusTargetLevel` semantic-shift surface in §3 of `audit/FINDINGS-v35.0.md` (carries forward from AUDIT-06 widening landed in Phase 263 REQUIREMENTS.md).

Out of scope (carried forward):
- Any `contracts/` source-file edits — Phase 264 is test-only. `_randTraitTicket` body BYTE-IDENTICAL per Phase 263 SURF-01; `_awardDailyCoinToTraitWinners` rewrite ALREADY landed at `cf564816` and is the unit under empirical test, not the unit being modified.
- Any new tester contract — see D-IMPL-01 below.
- Cross-validation of Phase 261's TRAIT-01..02 / SOLO-01..06 + STAT-01..07 / SURF-01..05 — those locked at v34.0 closure HEAD `6b63f6d4` and are not re-litigated.

</domain>

<decisions>
## Implementation Decisions

### Sampling oracle (STAT-01 + STAT-02)
- **D-IMPL-01:** Hybrid JS-replica + on-chain boundary harness, mirroring Phase 261 D-03. JS replica computes `lvlPrime = minLevel + ((BigInt(keccak256(abiEncode([randomWord, COIN_LEVEL_TAG, i]))) % BigInt(range))` for bulk N ≥ 10K aggregated samples (microseconds per sample; tester calls would push the suite from minutes into hours). Drift guard: at fixed seeds, the boundary harness invokes `payDailyCoinJackpot` (or `payDailyJackpotCoinAndTickets`) via the existing `GameLifecycle.test.js` fixture, harvests emitted `JackpotBurnieWin.lvl` values across all 50 pulls, and asserts the JS-replica `lvlPrime` series exactly matches the on-chain emitted values for that seed. JS-replica drift is structurally impossible without the boundary harness failing first.
- **D-IMPL-02:** No new tester contract. The helper `_awardDailyCoinToTraitWinners` is `private`, but everything observable per pull (winner, `lvlPrime`, `traitId`, amount, ticketIdx) is emitted via `JackpotBurnieWin`. Hardhat event harvest via `contract.queryFilter(contract.filters.JackpotBurnieWin())` after each call returns the per-pull `lvl` array directly. A `JackpotCoinPullTester.sol` analog to Phase 260's `JackpotSoloTester.sol` is NOT needed and would add a new `contracts/test/*.sol` surface (which would require D-APPROVAL-class explicit user approval per `feedback_no_contract_commits.md`). Carry-forward decision: NO new tester for Phase 264.
- **D-IMPL-03:** Sample shape — N ≥ 10K aggregated. Default branch: 200 calls × 50 pulls/call = 10,000 aggregated `lvlPrime` values. Each call uses a distinct deterministic seed via `makeRng(seed)` (Phase 261 reuse). Range varies — purchase-phase (`payDailyCoinJackpot`) range may be 1..N (caller-determined `minLevel`/`maxLevel`); jackpot-phase (`payDailyJackpotCoinAndTickets`) range is always 4 (`lvl + 1` to `lvl + 4`). Bulk loop runs the JS replica directly (no per-call EVM cost). Boundary harness runs ~10–20 on-chain calls to lock the JS-replica drift guard.

### Gas regression methodology (SURF-05)
- **D-IMPL-04:** Entry-point delta measurement, NOT paired-empty-wrapper. Phase 261's paired-empty-wrapper made sense for `_pickSoloQuadrant` (pure-stack 4-iter loop, no state effects). The PPL helper has 50 cold/warm length SLOADs (`traitBurnTicket[lvlPrime][trait_i].length`) + 50 deity-cache hits (4 SLOADs once at loop entry, then memory reads) + 50 keccak256(abi.encode(...)) inside the loop body + 50 `JackpotBurnieWin` emits + 50 `coinflip.creditFlip(winner, amount)` cross-contract calls. None can cleanly noOp in a wrapper without distorting the measurement. Use the existing `test/integration/GameLifecycle.test.js` fixture pattern: deploy, set up holder fixture, advance game to a state where `payDailyCoinJackpot` (or `payDailyJackpotCoinAndTickets`) fires, capture gas via `tx.gasUsed`. Measure HEAD-only — no v34.0 binary resurrection. Reference value pinned in the test file header comment from a 1-time HEAD measurement.
- **D-IMPL-05:** Theoretical worst-case derivation FIRST per `feedback_gas_worst_case.md`. Per-pull body opcode walk (under `unchecked` where possible):
  - `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))` (per-pull lvlPrime sample): MSTORE + MSTORE + MSTORE + KECCAK256(96 bytes) ≈ 60 gas
  - `% range` modulo: ≈ 8 gas
  - `traitBurnTicket[lvlPrime][trait_i].length` SLOAD: cold 2100 gas / warm 100 gas (EIP-2929)
  - `deityCache[traitIdx]` memory read: ≈ 12 gas
  - virtual-count branch + `effectiveLen` add: ≈ 30 gas
  - `keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))` (per-pull holder-index): MSTOREs + KECCAK256(128 bytes) ≈ 80 gas
  - `% effectiveLen`: ≈ 8 gas
  - `holders[idx]` cold/warm SLOAD on the holders array slot: cold 2100 / warm 100 — but the slot is per-(lvlPrime, trait_i, idx), distinct from the length slot. Cold cost = 2100 gas first read; warm = 100.
  - `JackpotBurnieWin` emit (5 fields, no indexed): ≈ 1500–1900 gas
  - `coinflip.creditFlip(winner, amount)` cross-contract: ≈ 700–2000 gas depending on coinflip body
  - cursor advance + loop overhead: ≈ 50 gas

  Cold-dominated worst case (all 50 distinct `(lvlPrime, trait_i)` slots cold + all 50 holder reads cold): ~50 × (2100 + 2100 + body ≈ 2500–3000) ≈ 235K — ABOVE the disclosed 110K envelope.

  Realistic worst case (EIP-2929 access list warming after ~16 distinct slots): 16 cold + 34 warm length SLOADs = 16×2100 + 34×100 = 33,600 + 3,400 = ~37K. 50 × per-pull body (sans length-SLOAD) ≈ 50 × 1.5–2.2K = 75–110K. Net per-call delta: ~75–110K matches the seed-note + REQUIREMENTS.md SURF-05 envelope.

  Worst-case bound asserted in test: **`PER_CALL_GAS_DELTA <= 120_000` gas** (10% headroom over the disclosed 110K upper bound, accounting for compiler-version codegen drift). Below the disclosed bound triggers no assertion; above 120K triggers test failure with a re-derivation note. The 120K hard bound is the test-level cap.
- **D-IMPL-06:** `advanceGame` ceiling check (Success Criterion 5). Extend `test/gas/AdvanceGameGas.test.js` (existing harness — not a new file) with a HEAD-only `it` block asserting that the worst-case `advanceGame` invocation across the v35.0 HEAD is below the existing block-gas-limit ceiling × (1 / 1.99). The "1.99× margin" anchor is the existing `MAX_BLOCK_GAS / WORST_CASE_ADVANCE_GAS ≥ 1.99` invariant from the v33.0 / v34.0 closure signals (re-verified at v35.0 HEAD). No `git blame` archaeology — read the current test file's existing margin assertion and re-run at HEAD.

### Empty-bucket skip rate (STAT-03)
- **D-IMPL-07:** Analytical bound. For a sampled `(lvl', trait_i)` slot, `effectiveLen == 0` requires:
  - `traitBurnTicket[lvl'][trait_i].length == 0` (no real holders), AND
  - `deityCache[traitIdx] == address(0)` (no deity for that symbol — `fullSymId >= 32` OR `deityBySymbol[fullSymId] == address(0)`).
  In a realistic late-game state, most `(lvl', trait_i)` slots have ≥1 holder, AND most traits have a deity. Empty slots are a function of game state (level distribution + trait distribution + deity assignment). Test fixture: deploy + advance to a mid/late-game state via the existing `GameLifecycle.test.js` lifecycle (~N tickets burned across ~M levels and 4 traits) where holder coverage is dense.
- **D-IMPL-08:** Test-failure threshold = empirical skip rate **> 10% per call** (averaged across N ≥ 50 calls in the fixture). Promotion above INFO per D-09 gating in Phase 265 AUDIT-06 §3:
  - skip rate ≤ 5%: plain INFO disclosure
  - 5% < skip rate ≤ 10%: INFO with warning paragraph
  - skip rate > 10%: test fails; promotion to LOW or higher per D-09 gating; trigger explicit author review
- **D-IMPL-09:** Cumulative monetary underspend disclosure. `Σ skip_amount` over the fixture run; assert `Σ skip_amount < 0.01 × Σ coinBudget` (1% bounded underspend). The exact numerator/denominator are recorded in the test artifact and surface in the test header comment for Phase 265 §3 carry-forward (AUDIT-06 disclosure paragraph). The disclosure prose, not the exact numbers, is the Phase 265 deliverable; Phase 264 produces both.

### SURF-01..04 cross-surface preservation harness shape
- **D-IMPL-10:** Single `test/stat/SurfaceRegression.test.js` extension (mirrors Phase 261 D-09 pattern). Add new `describe` blocks for the v35.0-specific protected ranges:
  - `_randTraitTicket` body L1650-1700 (post-Phase-263 line numbers; from Phase 263 SUMMARY.md byte-identity sweep — function definition unchanged)
  - 4 other `_randTraitTicket` callers at L697, L986, L1293, L1396 (post-Phase-263 line numbers)
  - `coinEntropy` derivation + `DailyWinningTraits` emit blocks at L518-520, L536-538, L1750-1756 (D-INDEXER-01)
  - `_pickSoloQuadrant` injection sites L282, L349, L524, L1147 (SURF-03)
  - `_awardFarFutureCoinJackpot` body (SURF-02)
  - `_distributeTicketJackpot` body (SURF-04)
  - `_computeBucketCounts` definition L1027 (post-Phase-263; SURF-04-adjacent — body unchanged, only the `_awardDailyCoinToTraitWinners` caller removed)

  Harness shape: `child_process.execSync('git diff 6b63f6d4 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol')` parsed for hunk header lines (`^@@ -<start>,<count> +<start>,<count> @@`). For each protected range `[lo, hi]`, assert no hunk's baseline-side line range `[start, start+count-1]` intersects `[lo, hi]`. Phase 261's D-09 SURF-04 grep-proof is the reference shape (`test/stat/SurfaceRegression.test.js`).
- **D-IMPL-11:** Protected ranges are recorded in a JS constant at the top of the SURF describe block — the Phase 263 SUMMARY.md byte-identity sweep is the source of truth. The harness fails-loudly if `git diff` returns no output (means baseline `6b63f6d4` is not in the local git history; CI / fresh-clone hint required). Reuse `child_process.execSync` not `simple-git` to keep the dependency surface minimal (matches Phase 261 D-09).

### Approval & commit posture (carried forward via memory)
- **D-APPROVAL-01:** All `test/`, `package.json`, and any other in-scope edits in this phase are batched and presented as one diff at the end of the phase per `feedback_batch_contract_approval.md`; user approval is explicit per commit (no orchestrator pre-approval) per `feedback_no_contract_commits.md` and `feedback_never_preapprove_contracts.md`. NO `contracts/*.sol` writes in this phase.
- **D-APPROVAL-02:** Skip research-agent dispatch per `feedback_skip_research_test_phases.md` — phase is fully specified in REQUIREMENTS.md (STAT-01..04 + SURF-01..05) with explicit thresholds, sample sizes, and gas envelope. The reusable Phase 261 chi² infra + Phase 263 SUMMARY.md protected-range list make this a mechanical phase. Plan directly. Mirrors Phase 259 D-11 + Phase 260 D-11 + Phase 261 D-13 + Phase 263 D-APPROVAL-02 mechanical-phase posture.
- **D-APPROVAL-03:** No history comments per `feedback_no_history_in_comments.md` — applies to test file comments too. Test header comments describe what IS (the assertion + analytical derivation) — not "previously was" / "v34.0 used to". Phase 261's `test/stat/TraitDistribution.test.js` header is the model.
- **D-APPROVAL-04:** No dead guards per `feedback_no_dead_guards.md` — applies to test code too. No commented-out test fixtures, no `it.skip`'d placeholders, no unreachable `if (process.env.SKIP_HEAVY)` branches without a real path.
- **D-APPROVAL-05:** Theoretical worst-case derivation FIRST per `feedback_gas_worst_case.md` (D-IMPL-05 above). The derivation lives in the test file header comment as authoritative source — the asserted bound is the literal pinned number derived in step (1).

### Plan slicing
- **D-PLAN-01:** Defer plan slicing decision to the planner (mirrors Phase 261 D-14 + Phase 263 D-PLAN-01). Reference shape (2-plan packing): P1 = STAT-01..04 (`PerPullLevelDistribution.test.js` + boundary cross-validation harness + STAT-04 infra-reuse confirmation) + STAT-03 (empty-bucket skip rate); P2 = SURF-01..04 (`SurfaceRegression.test.js` extension) + SURF-05 gas regression (`Phase264GasRegression.test.js` + `AdvanceGameGas.test.js` ceiling assertion). Single-plan packing also acceptable. Three-plan packing (STAT, SURF-byte-identity, SURF-gas) is acceptable; planner picks final shape. Every plan ends at the same end-of-phase batched approval gate per D-APPROVAL-01.

### Claude's Discretion
- Test-file consolidation within `test/stat/` (one file per success-criterion family vs single mega-file). Planner default: per-family file, mirroring Phase 261 (`TraitDistribution.test.js` etc.).
- JS chi² critical-value table extension — extend `CHI2_CRIT_05` from `test/unit/JackpotSoloPicker.test.js` (df 1..3) and `test/stat/TraitDistribution.test.js` (df 1..7) to include df = `range - 1` for whatever the test range is. STAT-01 chi² df depends on `range`; STAT-02 chi² df = 3 (4 traits − 1).
- Seeded-keccak PRNG seed values per test (each test gets a distinct integer seed; reproducibility = exact-replay on failure). Mirrors `makeRng(seed)` from Phase 261.
- Hardhat fixture composition for the SURF-05 entry-point gas measurement — `GameLifecycle.test.js` is the closest reference; planner picks fixture.
- Whether STAT-03's empty-bucket skip-rate test runs as part of `STAT-01..02` chi² file or as its own `PerPullEmptyBucketSkip.test.js`. Default: separate file (skip rate is its own concern; the chi² file should stay focused on uniformity).
- Whether SURF-01..04's grep-proof extends `test/stat/SurfaceRegression.test.js` (Phase 261 file) or lands as `test/stat/v35SurfaceRegression.test.js`. Default: extend the existing file with new `describe` blocks (single source of truth for the milestone; tag describe blocks with v35.0 marker).
- Exact prose of the Phase 265 §3 disclosure paragraph (AUDIT-06 carry-forward) — the test header comment captures the analytical formula + measured numbers; Phase 265 is the editorial pass.
- Whether `Phase264GasRegression.test.js` is merged into `Phase261GasRegression.test.js` (rename to `MilestoneGasRegression.test.js`) or kept separate. Default: separate file (per-milestone discipline; matches `Phase261GasRegression.test.js` precedent).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — STAT-01..04 (per-pull level chi² uniformity, per-trait share chi², empty-bucket skip rate measurement, Phase 261 infra reuse) + SURF-01..05 (`_randTraitTicket` other-callers byte-identity, far-future BURNIE byte-identity, ETH daily jackpot byte-identity, ticket distribution byte-identity, gas regression envelope).
- `.planning/ROADMAP.md` §"Phase 264: Statistical Validation + Cross-Surface Preservation" — Goal statement, Success Criteria 1-5, Depends-on (Phase 263). Note SC5 explicit `feedback_gas_worst_case.md` reference.
- `.planning/notes/2026-05-08-burnie-near-future-per-pull-level.md` — **Seed note with all locked decisions** (gas envelope ~70K–110K, cold SLOAD warming after ~16 slots, JS-replica reuse, infra reuse from Phase 261, indexer flag for `JackpotBurnieWin.lvl`).

### Contracts under empirical test (READ-only — no edits in Phase 264)
- `contracts/modules/DegenerusGameJackpotModule.sol` — Phase 263 HEAD `cf564816`. New helper body at the formerly-L1758-1834 range (post-rewrite line numbers vary by ~+5 LOC). `_randTraitTicket` body BYTE-IDENTICAL at the post-Phase-263 line range (was L1653-1703 baseline → ~L1650-1700 post-Phase-263 due to the `+5` LOC for `COIN_LEVEL_TAG` constant). Helper's `JackpotBurnieWin` emit is the observation point for STAT-01..02 sampling.
- `contracts/libraries/JackpotBucketLib.sol` — UNCHANGED (carry-forward from Phase 261). `unpackWinningTraits(uint32) → uint8[4]` consumed unchanged inside the new helper body.
- `contracts/libraries/EntropyLib.sol` — UNCHANGED. KI EXC-04 XOR-shift envelope is Phase 265 REG-03's explicit-attention re-verification, not Phase 264. The new per-pull-level keccak `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i)) % range` consumes high-entropy bits — Phase 264's STAT-01 chi² is the empirical evidence cited end-to-end at Phase 265.

### Phase 263 deliverables (the unit under test)
- `.planning/phases/263-per-pull-level-resample-implementation/263-01-PLAN.md` — Phase 263 plan. The 6 tasks + grep gauntlet are the implementation surface Phase 264 empirically validates.
- `.planning/phases/263-per-pull-level-resample-implementation/263-01-SUMMARY.md` — **Source of truth for Phase 264 protected line ranges** (byte-identity sweep results, post-Phase-263 line numbers for SURF-01..04, grep gauntlet outputs). The 7 protected ranges in §"Byte-Identity Sweep" are the SURF-01..04 anchors.
- `.planning/phases/263-per-pull-level-resample-implementation/263-CONTEXT.md` — Phase 263 locked decisions. D-IMPL-01 (inline holder-keccak, _randTraitTicket BYTE-IDENTICAL), D-INDEXER-01 (emit blocks BYTE-IDENTICAL), D-SHAPE-01..06 (helper signature, deity cache, share-math, range collapse, COIN_LEVEL_TAG, dead-derivation removal). Phase 264 SURF-01..04 sweep validates D-INDEXER-01 + D-IMPL-01 are honored at HEAD.
- Git commit `cf564816 feat(263): per-pull level resample for daily coin jackpot [PPL-01..PPL-08]` — the v35.0 baseline for Phase 264 measurement.
- Git commit `6b63f6d4daf346a53a1d463790f637308ea8d555` — v34.0 source-tree HEAD baseline (audit baseline). The SURF-01..04 grep-proof asserts no protected-range hunks between `6b63f6d4` and HEAD.

### Test surfaces being added (NEW — Phase 264)
- `test/stat/PerPullLevelDistribution.test.js` (NEW, planner-named) — STAT-01 + STAT-02 chi² uniformity + per-trait share, ≥10K samples.
- `test/stat/PerPullEmptyBucketSkip.test.js` (NEW, planner-named — may fold into PerPullLevelDistribution.test.js per Claude's Discretion) — STAT-03 empty-bucket skip rate measurement.
- `test/stat/SurfaceRegression.test.js` (EXTENSION — Phase 261 file extended with v35.0 protected-range describe blocks) — SURF-01..04 grep-proof.
- `test/gas/Phase264GasRegression.test.js` (NEW) — SURF-05 entry-point gas delta with theoretical worst-case derivation in test header comment.
- `test/gas/AdvanceGameGas.test.js` (EXTENSION — existing file extended with HEAD-only 1.99× margin assertion) — Success Criterion 5 explicit.
- `package.json` `scripts.test:stat` (UPDATE entry) — add new `test/stat/*.test.js` files. `scripts.test` (UPDATE) — add `test/gas/Phase264GasRegression.test.js` to the default suite (matches Phase 261 placement of `AdvanceGameGas.test.js`).

### Test surfaces reused (NO edits — read-only inputs)
- `test/stat/TraitDistribution.test.js` (Phase 261) — `makeRng(seed)`, `CHI2_CRIT_05`, JS-replica + boundary harness pattern. `rndForScaled(scaled)` reverse-mapping helper if STAT-01 boundary harness needs it.
- `test/stat/GoldSoloCoverage.test.js` + `test/stat/SoloEvUplift.test.js` + `test/stat/PackFeel.test.js` (Phase 261) — chi² critical-value reuse + Monte Carlo loop pattern.
- `test/gas/Phase261GasRegression.test.js` (Phase 261) — paired-empty-wrapper methodology REJECTED for SURF-05 (see D-IMPL-04). Header-comment theoretical derivation pattern REUSED.
- `test/integration/GameLifecycle.test.js` — entry-point fixture pattern for SURF-05 + STAT-03 fixture (mid/late-game state with holder density). The 3 entry points relevant: `payDailyCoinJackpot`, `payDailyJackpotCoinAndTickets`. The `_resumeDailyEth` and `runTerminalJackpot` paths are SURF-03 (BYTE-IDENTICAL — out of scope for Phase 264 empirical, in scope for grep-proof).
- `test/helpers/deployFixture.js` + `test/helpers/testUtils.js` + `test/helpers/invariantUtils.js` + `test/helpers/charityFixture.js` — reuse for fixture composition.
- `contracts/test/TraitUtilsTester.sol` (Phase 259) + `contracts/test/JackpotSoloTester.sol` (Phase 260) — NOT consumed by Phase 264 (no analog tester for `_awardDailyCoinToTraitWinners` per D-IMPL-02). Listed for completeness.

### Memory / feedback governing this phase
- `feedback_no_contract_commits.md` — explicit per-commit user approval for all `contracts/` + `test/` changes. Phase 264 has zero `contracts/*.sol` writes; `test/`+`package.json` writes still gated through batched approval (D-APPROVAL-01).
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end (D-APPROVAL-01).
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved.
- `feedback_no_history_in_comments.md` — test file comments describe what IS (D-APPROVAL-03).
- `feedback_no_dead_guards.md` — no commented-out fixtures, no skip'd tests, no unreachable branches (D-APPROVAL-04).
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch (D-APPROVAL-02).
- `feedback_gas_worst_case.md` — theoretical worst-case derivation FIRST, then HEAD-only measurement (D-IMPL-05 + D-APPROVAL-05).
- `feedback_wait_for_approval.md` — present diff and wait for explicit approval before any commit.
- `feedback_manual_review_before_push.md` — never push test changes without diff review.
- `feedback_rng_backward_trace.md` — Phase 265 RNG audit cites STAT-01 + STAT-02 evidence; Phase 264 produces the chi² test fixtures + p-values.
- `feedback_rng_commitment_window.md` — Phase 265 commitment-window check; Phase 264 produces no new commitment-window state (test-only phase).

### Prior-phase context
- `.planning/milestones/v34.0-phases/261-statistical-validation-cross-surface-verification/261-CONTEXT.md` — **Reference pattern phase.** D-01 (test/stat/ directory + opt-in npm script), D-03 (hybrid JS-replica + boundary harness), D-09 (single `SurfaceRegression.test.js` with grep-proof harness), D-11 (theoretical worst-case derivation FIRST), D-12 (batched test approval), D-13 (skip research for mechanical phase), D-14 (planner picks slicing). Mirror its plan shape.
- `.planning/milestones/v34.0-phases/261-statistical-validation-cross-surface-verification/261-01-PLAN.md` (and any 261-02/03 plans) — Phase 261 plan shape; planner reads as Phase 264 template.
- `.planning/milestones/v34.0-phases/260-gold-solo-priority-injection/260-CONTEXT.md` — Phase 260 D-13/D-14 spec-amendment-with-implementation pattern (Phase 263 D-AUDIT06-AMEND-01 mirrored this; Phase 264 inherits the discipline for any STAT-NN amendments if the planner finds REQUIREMENTS.md drift).
- `.planning/milestones/v34.0-phases/259-trait-distribution-split/259-CONTEXT.md` — D-11 mechanical-phase posture (skip research). Carried forward.

### Milestone & state
- `.planning/PROJECT.md` — v35.0 milestone goal. Anchor for the 70K–110K gas envelope (seed note + REQUIREMENTS.md SURF-05).
- `.planning/STATE.md` — current focus (planning Phase 264 after Phase 263 close at `cf564816`).
- `KNOWN-ISSUES.md` — UNMODIFIED at Phase 264 close (any modifications gate through D-09 in Phase 265).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`makeRng(seed)` (Phase 261, `test/stat/TraitDistribution.test.js` L48-56)** — deterministic 256-bit PRNG via keccak256(seed || counter). Reused unchanged for all Phase 264 chi² loops. Distinct seed per test for reproducibility.
- **`CHI2_CRIT_05` table (Phase 261, `test/stat/TraitDistribution.test.js` + `test/unit/JackpotSoloPicker.test.js`)** — df 1..3 critical values at α=0.05. Phase 264 needs df=3 (per-trait share chi²) — already covered. STAT-01 needs df = range-1 (variable) — extend to df=7 if the broadest range is 8 levels; the planner extends as needed.
- **`rndForScaled(scaled)` (Phase 261, `test/stat/TraitDistribution.test.js` L40-43)** — boundary-edge reverse-map helper. May not be needed for Phase 264 (per-pull keccak doesn't have edge thresholds the way `weightedColorBucket` does).
- **`test/integration/GameLifecycle.test.js` lifecycle fixture** — drives `advanceGame` to a state where `payDailyCoinJackpot` and `payDailyJackpotCoinAndTickets` fire. Reference for STAT-03 fixture (mid/late-game holder density) and SURF-05 entry-point gas measurement.
- **`test/gas/Phase261GasRegression.test.js` header-comment theoretical derivation pattern** — multi-paragraph derivation walks opcode-by-opcode, then asserts measured value within disclosed bound. Reuse the structure verbatim (different opcodes for the PPL helper).
- **`test/gas/AdvanceGameGas.test.js`** — existing 1.99× margin assertion. Phase 264 extends with HEAD-only re-assertion at v35.0 HEAD.
- **`hre.ethers.AbiCoder.defaultAbiCoder()` for `abi.encode` replication** — JS-side replication of `abi.encode(randomWord, COIN_LEVEL_TAG, i)` requires matching the on-chain ABI encoding byte-for-byte. Use `hre.ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32', 'uint256'], [randomWord, COIN_LEVEL_TAG, BigInt(i)])`. Boundary harness asserts JS encoding == on-chain encoding implicitly via the emitted-event lvlPrime match.
- **`contract.queryFilter(contract.filters.JackpotBurnieWin())`** — Hardhat event harvest pattern. Returns array of `{args: {winner, lvl, traitId, amount, ticketIndex}}`. Bulk-harvest after each call gives the 50-pull `lvl` series for that call.
- **Phase 263 SUMMARY.md byte-identity sweep §"Byte-Identity Sweep"** — authoritative protected-range list for SURF-01..04 grep-proof.

### Established Patterns
- **Site-local block discipline** — Phase 261's `describe('SURF-04', ...)` block in `SurfaceRegression.test.js` is the canonical SURF-style block shape: theoretical claim in describe-name, grep-proof in the assertion, line-number hardcoded in a JS constant at top of describe.
- **Internal-pure / private helper convention** — `_awardDailyCoinToTraitWinners` is `private`. Phase 264 observes via the public entry points + `JackpotBurnieWin` emit (no tester contract — D-IMPL-02). Phase 261's tester reuse pattern (`TraitUtilsTester` + `JackpotSoloTester`) is NOT applicable here.
- **Empty-bucket silent-skip discipline** — matches the existing `if (effectiveLen == 0) continue;` shape in the new helper body (Phase 263 D-IMPL-01). Phase 264 STAT-03 measures the rate of this `continue;` path.
- **Cursor remainder distribution** — Phase 263 preserved the L1804-1827 cursor pattern byte-identically (PPL-04). STAT-03's monetary-underspend bound math accounts for the cursor's `+1` extra being structurally lost on a skipped pull (the seed note's "structurally lost +1 extra for that cursor slot is accepted underspend per PPL-05").
- **Tag constant convention** — `COIN_LEVEL_TAG` is consumed by Phase 264's JS replica via `abi.encode(['uint256', 'bytes32', 'uint256'], [randomWord, '0x' + keccak256AsHex('coin-level'), i])`. Hardcode the bytes32 value in the test file (computed once via `hre.ethers.keccak256(hre.ethers.toUtf8Bytes('coin-level'))`).

### Integration Points
- **`test/stat/SurfaceRegression.test.js` (Phase 261, EXTENSION)** — SURF-01..04 grep-proof. Add new `describe` blocks for v35.0 protected ranges; reuse the `child_process.execSync('git diff 6b63f6d4 HEAD -- ...')` harness shape from Phase 261 D-09. Tag describe-block names with `v35.0` to distinguish from Phase 261's v34.0 SURF blocks.
- **`test/gas/AdvanceGameGas.test.js` (EXTENSION)** — Add `it('preserves 1.99× margin at v35.0 HEAD', ...)` that re-runs the existing margin computation against the v35.0 HEAD `advanceGame` worst-case path and asserts the margin is ≥ 1.99×.
- **`package.json` `scripts.test:stat`** (CURRENT: `test/gas/Phase261GasRegression.test.js test/stat/TraitDistribution.test.js test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js test/stat/SurfaceRegression.test.js`) — append the new `test/stat/PerPullLevelDistribution.test.js` (and `test/stat/PerPullEmptyBucketSkip.test.js` if separated). The `Phase264GasRegression.test.js` joins `scripts.test` (default suite) per `Phase261GasRegression.test.js` precedent at `package.json:9` (current placement).
- **`hre.ethers.keccak256(hre.ethers.toUtf8Bytes('coin-level'))` value** — `0x` followed by the 32-byte keccak digest of `"coin-level"`. Hardcode in the test file as `const COIN_LEVEL_TAG = '0x...';` to avoid recomputing per test run.

</code_context>

<specifics>
## Specific Ideas

- **JS replica of per-pull-level keccak (D-IMPL-01 reference shape):**
  ```javascript
  const COIN_LEVEL_TAG = hre.ethers.keccak256(hre.ethers.toUtf8Bytes('coin-level'));
  // const COIN_LEVEL_TAG = '0x...'; // can be hardcoded after one-time computation

  function jsLvlPrime(randomWord, minLevel, maxLevel, i) {
    const range = BigInt(maxLevel) - BigInt(minLevel) + 1n;
    const encoded = hre.ethers.AbiCoder.defaultAbiCoder().encode(
      ['uint256', 'bytes32', 'uint256'],
      [BigInt(randomWord), COIN_LEVEL_TAG, BigInt(i)]
    );
    const digest = BigInt(hre.ethers.keccak256(encoded));
    return Number(BigInt(minLevel) + (digest % range));
  }
  ```

- **STAT-01 chi² assertion shape:**
  ```javascript
  // N ≥ 10K aggregated samples across distinct seeds.
  const N_CALLS = 200;
  const PULLS_PER_CALL = 50; // DAILY_COIN_MAX_WINNERS
  const range = 4; // jackpot-phase: lvl+1..lvl+4
  const observed = new Array(range).fill(0);
  const rng = makeRng(0xCAFE0001);

  for (let call = 0; call < N_CALLS; call++) {
    const randomWord = rng();
    const minLevel = 100; // arbitrary fixed level
    const maxLevel = minLevel + range - 1;
    for (let i = 0; i < PULLS_PER_CALL; i++) {
      const lvl = jsLvlPrime(randomWord, minLevel, maxLevel, i);
      observed[lvl - minLevel]++;
    }
  }

  const total = N_CALLS * PULLS_PER_CALL; // 10,000
  const expected = total / range;
  const chi2 = observed.reduce((s, o) => s + Math.pow(o - expected, 2) / expected, 0);
  // df = range - 1 = 3; CHI2_CRIT_05[3] = 7.815
  expect(chi2).to.be.below(CHI2_CRIT_05[range - 1]);
  ```

- **STAT-02 per-trait share chi² assertion shape:**
  ```javascript
  // i % 4 rotation guarantees exactly cap/4 = 12.5 expected per trait per call.
  // Across N calls, each trait gets exactly N * 12 + ε pulls (ε from cap % 4).
  // Chi² is degenerate (deterministic) UNLESS we measure observed trait
  // distribution via emitted JackpotBurnieWin.traitId across the boundary
  // harness on-chain calls (where empty-bucket skips reduce some trait counts).
  // For the JS-replica chi², the assertion is trivially `chi² ≈ 0`.
  // For the boundary-harness chi² (real holder fixture), assert chi² < 7.815 (df=3).
  ```

- **Boundary cross-validation harness shape (D-IMPL-01 drift guard):**
  ```javascript
  // 10–20 on-chain calls at fixed seeds. Harvest emitted JackpotBurnieWin.lvl
  // and assert the JS replica produces the identical 50-pull lvl series.
  const seeds = [0xCAFE0001, 0xCAFE0002, /* ... */];
  for (const seed of seeds) {
    const randomWord = /* derive from seed */;
    const tx = await game.payDailyCoinJackpot(/* args */);
    const events = await game.queryFilter(game.filters.JackpotBurnieWin(), tx.blockNumber, tx.blockNumber);
    const onChainLvls = events.map(e => Number(e.args.lvl));
    const jsLvls = [];
    for (let i = 0; i < onChainLvls.length; i++) {
      jsLvls.push(jsLvlPrime(randomWord, minLevel, maxLevel, i));
    }
    expect(jsLvls).to.deep.equal(onChainLvls);
  }
  ```

- **STAT-03 empty-bucket skip rate test shape:**
  ```javascript
  const N_CALLS = 50;
  let totalPulls = 0;
  let skippedPulls = 0;
  let totalCoinBudget = 0n;
  let totalUnderspend = 0n;
  for (let i = 0; i < N_CALLS; i++) {
    const tx = await advanceToCoinJackpotCall(/* fixture */);
    const callBudget = /* compute from tx state */;
    totalCoinBudget += callBudget;
    const events = await game.queryFilter(game.filters.JackpotBurnieWin(), tx.blockNumber, tx.blockNumber);
    const emittedCount = events.length;
    totalPulls += 50;
    skippedPulls += (50 - emittedCount);
    const totalPaid = events.reduce((s, e) => s + e.args.amount, 0n);
    totalUnderspend += (callBudget - totalPaid);
  }
  const skipRate = skippedPulls / totalPulls;
  const underspendRatio = Number(totalUnderspend * 10000n / totalCoinBudget) / 10000;

  expect(skipRate).to.be.at.most(0.10, `Skip rate ${skipRate} > 10% — promote above INFO`);
  expect(underspendRatio).to.be.at.most(0.01, `Underspend ${underspendRatio*100}% > 1% — bound violated`);
  ```

- **SURF-01..04 grep-proof harness shape (D-IMPL-10):**
  ```javascript
  const { execSync } = require('child_process');
  const BASELINE = '6b63f6d4daf346a53a1d463790f637308ea8d555';
  const FILE = 'contracts/modules/DegenerusGameJackpotModule.sol';

  // Protected ranges from Phase 263 SUMMARY.md byte-identity sweep
  // (baseline-side line numbers; planner verifies post-Phase-263 numbers via grep at write time).
  const PROTECTED_RANGES = [
    { name: '_randTraitTicket body (SURF-01)',                  lo: 1653, hi: 1703 },
    { name: '_randTraitTicket caller L700 (SURF-01)',           lo: 700,  hi: 700  },
    { name: '_randTraitTicket caller L989 (SURF-01)',           lo: 989,  hi: 989  },
    { name: '_randTraitTicket caller L1296 (SURF-01)',          lo: 1296, hi: 1296 },
    { name: '_randTraitTicket caller L1399 (SURF-01)',          lo: 1399, hi: 1399 },
    { name: 'DailyWinningTraits emit L518-520 (D-INDEXER-01)',  lo: 518,  hi: 520  },
    { name: 'DailyWinningTraits emit L536-538 (D-INDEXER-01)',  lo: 536,  hi: 538  },
    { name: 'DailyWinningTraits emit L1750-1756 (D-INDEXER-01)',lo: 1750, hi: 1756 },
    { name: '_pickSoloQuadrant L282 (SURF-03)',                 lo: 282,  hi: 282  },
    { name: '_pickSoloQuadrant L349 (SURF-03)',                 lo: 349,  hi: 349  },
    { name: '_pickSoloQuadrant L524 (SURF-03)',                 lo: 524,  hi: 524  },
    { name: '_pickSoloQuadrant L1147 (SURF-03)',                lo: 1147, hi: 1147 },
    { name: '_awardFarFutureCoinJackpot (SURF-02)',             lo: 1839, hi: 1900 }, // planner refines
    { name: '_distributeTicketJackpot (SURF-04)',               lo: -1,   hi: -1   }, // planner fills via grep
    { name: '_computeBucketCounts def L1030',                   lo: 1030, hi: 1100 }, // planner refines
  ];

  const diff = execSync(`git diff ${BASELINE} HEAD -- ${FILE}`, { encoding: 'utf8' });
  const hunkRe = /^@@ -(\d+),(\d+) \+(\d+),(\d+) @@/gm;
  let match;
  const hunks = [];
  while ((match = hunkRe.exec(diff)) !== null) {
    hunks.push({ baseStart: +match[1], baseCount: +match[2] });
  }

  for (const range of PROTECTED_RANGES) {
    for (const hunk of hunks) {
      const hunkLo = hunk.baseStart;
      const hunkHi = hunk.baseStart + hunk.baseCount - 1;
      if (!(hunkHi < range.lo || hunkLo > range.hi)) {
        throw new Error(`Hunk [${hunkLo}-${hunkHi}] intersects protected range "${range.name}" [${range.lo}-${range.hi}]`);
      }
    }
  }
  ```

- **Phase264GasRegression.test.js header derivation shape (D-IMPL-05):**
  ```javascript
  // ============================================================================
  // THEORETICAL WORST-CASE DERIVATION (per feedback_gas_worst_case.md)
  // ============================================================================
  //
  // Per-pull body opcode walk (under unchecked where possible):
  //   - keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))     ~  60 gas
  //   - % range modulo                                           ~   8 gas
  //   - traitBurnTicket[lvlPrime][trait_i].length SLOAD          : cold 2100 / warm 100 (EIP-2929)
  //   - deityCache[traitIdx] memory read                         ~  12 gas
  //   - virtual-count branch                                     ~  30 gas
  //   - keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))  ~  80 gas
  //   - % effectiveLen modulo                                    ~   8 gas
  //   - holders[idx] cold/warm SLOAD                             : cold 2100 / warm 100
  //   - JackpotBurnieWin emit (5 fields, no indexed)             ~ 1500-1900 gas
  //   - coinflip.creditFlip(winner, amount) cross-contract       ~  700-2000 gas
  //   - cursor advance + loop overhead                           ~  50 gas
  //
  // Realistic worst case (EIP-2929 access list warming after ~16 distinct slots):
  //   16 cold + 34 warm length SLOADs ≈ 33,600 + 3,400 = 37K
  //   50 × per-pull body (sans length SLOAD) ≈ 50 × 1.5–2.2K = 75–110K
  //   Net per-call delta: ~75–110K
  //
  // Asserted bound: PER_CALL_GAS_DELTA <= 120_000 gas (10% headroom over the
  // disclosed 110K upper bound, accounting for compiler-version codegen drift).
  // ============================================================================

  const PER_CALL_GAS_DELTA_BOUND = 120_000;
  ```

- **`package.json` script update (planner-final shape):**
  ```diff
   "test": "hardhat test test/unit/*.test.js test/integration/*.test.js test/deploy/*.test.js test/access/*.test.js test/edge/*.test.js test/gas/AdvanceGameGas.test.js test/adversarial/*.test.js"
  +# (above unchanged)
  -"test:stat": "hardhat test test/gas/Phase261GasRegression.test.js test/stat/TraitDistribution.test.js test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js test/stat/SurfaceRegression.test.js",
  +"test:stat": "hardhat test test/gas/Phase261GasRegression.test.js test/gas/Phase264GasRegression.test.js test/stat/TraitDistribution.test.js test/stat/GoldSoloCoverage.test.js test/stat/SoloEvUplift.test.js test/stat/PackFeel.test.js test/stat/SurfaceRegression.test.js test/stat/PerPullLevelDistribution.test.js test/stat/PerPullEmptyBucketSkip.test.js",
  ```
  (Final ordering + filenames are planner-discretion per Claude's Discretion above.)

</specifics>

<deferred>
## Deferred Ideas

- **`audit/FINDINGS-v35.0.md` §3 disclosure paragraph (AUDIT-06 carry-forward)** — Phase 264 produces the analytical bound + measured numbers in the test header comment + test artifact; the editorial pass on the disclosure prose lands in Phase 265. Phase 264 does NOT write to `audit/FINDINGS-v35.0.md` directly.
- **KI EXC-04 EntropyLib XOR-shift re-verification** — Phase 265 REG-03 explicit-attention re-verification, cross-cited with Phase 264 STAT-01 chi² evidence. Phase 264 produces the empirical evidence; Phase 265 reads + cites.
- **v34.0 + v33.0 closure-signal re-verification** — Phase 265 REG-01..02. Phase 264 is silent on prior-milestone closure signals.
- **Adversarial sweep over PPL deltas (predictability, trait-stacking pre-call, level-salt collision, deity-cache staleness, cross-caller `_randTraitTicket` salt collision, off-chain indexer semantic-shift attack surface, gas-griefing via repeated cold SLOAD)** — Phase 265 AUDIT-02. Phase 264 produces the chi² + skip-rate + gas evidence that Phase 265 cites SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE.
- **Conservation re-proof (`coinBudget` non-overspend, solvency, BURNIE mint-supply)** — Phase 265 AUDIT-03. Phase 264's STAT-03 underspend bound is the empirical input.
- **Zero-new-state scan** — Phase 265 AUDIT-04. Trivially true at Phase 264 close (zero `contracts/*.sol` writes since Phase 263).
- **Mid-pool / max-cap bucket-count regimes** — Phase 261 deferred these; Phase 264 inherits the deferral. The new chi² tests run at base bucket counts (low-pool, no scaling) to match Phase 261 D-05.
- **`JackpotCoinPullTester.sol` analog** — explicitly NOT created per D-IMPL-02. If a future phase needs internal-state observation beyond emitted events, that phase creates the tester.
- **A/B harness against Phase 261 baseline (pre-PPL gas measurement)** — explicitly out of scope per D-IMPL-04 + carry-forward from Phase 261 D-11 ("we don't resurrect the v33.0 binary"). Phase 264 measures HEAD-only against the disclosed envelope; the v34.0 baseline gas numbers are NOT re-measured.
- **Indexer team kickoff communication for AUDIT-06 widening** — operational task at v35.0 milestone state publication; not a Phase 264 deliverable. Phase 263 SUMMARY.md notes the local-only AUDIT-06 widening on REQUIREMENTS.md.

</deferred>

---

*Phase: 264-statistical-validation-cross-surface-preservation*
*Context gathered: 2026-05-09*
