# Requirements: Degenerus Protocol — v37.0 Degenerette Recalibration + Maintenance Bundle

**Defined:** 2026-05-10
**Milestone:** v37.0
**Goal:** Reconcile Degenerette payout calibration with the v34.0 heavy-tail trait producer (pre-launch fix), execute deferred maintenance (lootbox dead-branch cleanup + SURF-05 gas-pin re-pinning), and clear the long-deferred adversarial audit of post-v32.0 commits — all closed under a single `audit/FINDINGS-v37.0.md` deliverable.
**Audit baseline:** v36.0 audit-subject HEAD `1c0f09132d7439af9881c56fe197f81757f8164a`
**Audit baseline signal:** `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a`
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**READ-only audit posture:** LIFTED — audit-then-commit (or impl-then-audit) with per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Audit deliverable + planning docs AGENT-COMMITTED.
**Phase shape:** 5-phase bundled milestone. Phase 267 Degenerette contracts (1 batched commit) → Phase 268 Degenerette stat + cross-surface tests → Phase 269 lootbox dead-branch cleanup + SURF-05 re-pin → Phase 270 post-v32.0 deferred-commit adversarial sub-audit → Phase 271 delta audit + FINDINGS-v37.0.md (terminal).

## v37.0 Requirements

### DGN — Degenerette Producer + 5-Table Payout Rewrite (Core Implementation, Phase 267)

- [ ] **DGN-01**: New `packedTraitsDegenerette(uint256 seed) external pure returns (uint32)` helper added to `contracts/DegenerusTraitUtils.sol` with per-quadrant producer `[16,16,16,16,16,16,16,8]/120` (commons 13.33%, gold 6.67%) and uniform symbol distribution `1/8`. `[QQ][CCC][SSS]` byte layout preserved. Existing `packedTraitsFromSeed` byte-identical (Mint + Jackpot paths UNCHANGED).
- [ ] **DGN-02**: `_evNormalizationRatio(...)` (`DegenerusGameDegeneretteModule.sol` L808-851) DELETED. Single call site at L965-969 also DELETED. No runtime EV correction; payout schedule fully visible in storage.
- [ ] **DGN-03**: `_countGoldQuadrants(uint8[4]) internal pure returns (uint8)` helper added to `DegenerusGameDegeneretteModule.sol` — counts color==7 across 4 player-pick quadrants. Returns N ∈ {0..4} for table dispatch.
- [ ] **DGN-04**: `_getBasePayoutBps(uint256 matchCount, uint8 N)` REWRITTEN to dispatch across 5 per-N payout tables. Each table calibrated so basePayoutEV = exactly 100 centi-x against THAT N-value's match-count distribution (verified 0.00 bps drift across all N).
- [ ] **DGN-05**: 5 packed payout constants added: `QUICK_PLAY_PAYOUTS_N0_PACKED`, `..._N1_PACKED`, `..._N2_PACKED`, `..._N3_PACKED`, `..._N4_PACKED`. Per-table 8-payout schedule encoded; constants derived via `.planning/notes/degenerette-recalibration/derive_5_tables.py` (Fraction-exact).
- [ ] **DGN-06**: 5 per-N M8 single-payout constants added: `QUICK_PLAY_PAYOUT_N0_M8`, `..._N1_M8`, `..._N2_M8`, `..._N3_M8`, `..._N4_M8` (all-8-match jackpot tier per N).
- [ ] **DGN-07**: `_applyHeroMultiplier(...)` REWRITTEN — hero match becomes **symbol-only** (color of hero quadrant ignored). P(hero match) = 1/8 uniform per quadrant.
- [ ] **DGN-08**: 5 packed hero boost constants added: `HERO_BOOST_N0_PACKED`, `..._N1_PACKED`, `..._N2_PACKED`, `..._N3_PACKED`, `..._N4_PACKED`. Per-N hero boost dispatch from `_applyHeroMultiplier`.
- [ ] **DGN-09**: `_wwxrpBonusRoiForBucket(...)` REWRITTEN to dispatch across 5 per-N factor tables.
- [ ] **DGN-10**: 5 packed WWXRP factor constants added: `WWXRP_FACTORS_N0_PACKED`, `..._N1_PACKED`, `..._N2_PACKED`, `..._N3_PACKED`, `..._N4_PACKED`.
- [ ] **DGN-11**: Old single-table constants DELETED (4 entries: `QUICK_PLAY_BASE_PAYOUTS_PACKED`, `WWXRP_BONUS_FACTOR_BUCKET5..8` block, `HERO_BOOST_PACKED`, plus 2 normalizer constants `_evNormalizationRatio`-related). Net constant count: 11 → 24 (-4 + 5 payout + 5 jackpot + 5 hero + 5 WWXRP, -2 normalizer).
- [ ] **DGN-12**: `packedTraitsFromSeed` callsite at L607 in `DegenerusGameDegeneretteModule.sol` SWAPPED to `packedTraitsDegenerette` (new helper). Producer now per-quadrant uniform-with-rare-gold; consumer math reconciled via 5-table dispatch.
- [ ] **DGN-13**: 4 stale comments rewritten: L239 ("99.99% RTP" → updated EV statement), L262 ("all weights=10" → 5-table per-N statement), L287-298 (equal-EV invariant prose updated to per-N basis), L316 (HERO_BOOST_PACKED reference replaced with per-N reference). No prose drift between code and comments.
- [ ] **DGN-14**: `DegenerusTraitUtils` other-function byte-identity preserved — `weightedColorBucket`, `traitFromWord`, `packedTraitsFromSeed` UNCHANGED. New helper additive only.
- [ ] **DGN-15**: Zero new storage slots; zero new public/external mutation entry points; zero new admin functions; zero new modifiers; existing storage layout byte-identical (no slot shifts).

### STAT — Statistical Validation + Cross-Surface Preservation (Phase 268)

- [ ] **STAT-01**: Per-N basePayoutEV exactness — for each N ∈ {0..4}, simulate ≥ 1M draws against the N-table dispatch, assert measured payoutEV = 100.00 ± 0.50 centi-x (±0.5%). Equal-EV invariant satisfied across all 16,384 player-pick configurations within statistical tolerance.
- [ ] **STAT-02**: Producer chi² uniformity — `packedTraitsDegenerette` empirical distribution matches `[16,16,16,16,16,16,16,8]/120` color distribution within Wilson-Hilferty Z<1.645 / `CHI2_CRIT_05[7]=14.067` at α=0.05; symbol distribution chi² < `CHI2_CRIT_05[7]=14.067` at α=0.05. ≥ 1M samples.
- [ ] **STAT-03**: Hero bonus EV (per-N) — for each N ∈ {0..4}, simulate ≥ 100K draws with hero quadrant active, assert measured hero-boost EV matches per-N target within ±1% (tighter rounding given lower sample count).
- [ ] **STAT-04**: WWXRP bonus EV (per-N) — for each N ∈ {0..4}, simulate ≥ 100K draws with WWXRP active, assert measured WWXRP factor EV matches per-N target within ±1%.
- [ ] **STAT-05**: Match-count distribution per N — for each N ∈ {0..4}, verify the 0..8-match histogram matches the analytical per-N reference within ±0.5% bin frequencies (proves 5-table calibration assumptions).
- [ ] **STAT-06**: Test suite reuses Phase 261 / Phase 264 / Phase 266 chi² infrastructure (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ`) — no fresh statistical tooling introduced. New files: `test/stat/DegenerettePerNEvExactness.test.js`, `test/stat/DegeneretteProducerChi2.test.js`, `test/stat/DegeneretteBonusEv.test.js`.

### SURF — Cross-Surface Preservation (Phase 268, audit-verified Phase 271)

- [ ] **SURF-01**: `DegenerusTraitUtils.sol` Mint/Jackpot consumer paths byte-identical — `packedTraitsFromSeed` body + `weightedColorBucket` body + `traitFromWord` body UNCHANGED. Only additive change is `packedTraitsDegenerette` helper.
- [ ] **SURF-02**: `DegenerusGameJackpotModule.sol` byte-identical — v34.0 gold-solo `_pickSoloQuadrant` + 4 ETH-distribution injection sites + `JackpotBucketLib` UNCHANGED.
- [ ] **SURF-03**: `DegenerusGameLootboxModule.sol` v36.0 entropy refactor surfaces byte-identical — `_rollTargetLevel`, `_lootboxTicketCount`, `_resolveLootboxRoll` (post-cleanup) hash2/bit-slice patterns preserved.
- [ ] **SURF-04**: `EntropyLib.sol` byte-identical (`hash2` + `entropyStep` bodies UNCHANGED; ENT-04 v36.0 carry).
- [ ] **SURF-05**: `SurfaceRegression.test.js` extended with v37.0 describe — assert byte-identity of all SURF-01..04 surfaces via codehash comparison or selector enumeration. Mirrors v34/v35/v36 SURF preservation pattern.
- [ ] **SURF-06**: `advanceGame` per-day gas envelope unchanged within ±2K vs v36.0 baseline; Degenerette path is OFF the advanceGame hot path (called via separate entry points), so impact bounded to `quickPlay` + related entry-point gas regressions.

### LBX — Lootbox Dead BURNIE-Conversion Branch Cleanup (Phase 269)

- [ ] **LBX-01**: `_resolveLootboxRoll(...)` (`contracts/modules/DegenerusGameLootboxModule.sol` ~L1568-1581 at v36.0 HEAD) — unreachable `if (targetLevel < currentLevel) { burnieOut = ... }` branch DELETED. Caller `_resolveLootboxCommon` at L882-884 already clamps `targetLevel = max(targetLevel, currentLevel)` before invocation; the inner check is structurally dead. Replace with direct `ticketsOut = ticketsScaled;` assignment.
- [ ] **LBX-02**: Bytecode shrink + ~50g/open savings verified via dedicated gas test (`test/gas/LootboxOpenGas.test.js` extension). Audit-trail comment added at deletion site (or per `feedback_no_history_in_comments.md`, no trace comment if delta is self-explanatory from caller-clamp invariant).
- [ ] **LBX-03**: Audit-trail row added to FINDINGS-v37.0.md §3.A delta-surface confirming ENT-02 (v36.0 Phase 266 entropy refactor) callsite numbering still consistent post-deletion (line numbers may shift; bit-slice budget UNAFFECTED).

### GASPIN — SURF-05 Gas-Pin Re-Pinning Fix (Phase 269)

- [ ] **GASPIN-01**: Root-cause investigation — identify why Phase 261/264 SURF-05 gas-pin tests drift ~120K under `npm run test:stat` ordering but pass standalone. Hypotheses to investigate: state pollution from prior test files, gas-meter snapshot ordering, fixture-loader caching, hardhat node restart timing.
- [ ] **GASPIN-02**: Stabilize affected tests. Either: (a) re-pin gas snapshots to combined-suite-stable values + document the offset rationale, OR (b) fix ordering dependency (e.g., `before(()=>vm.reset())` injection, or test-file isolation), OR (c) split the affected describes across separate test files. Choose the least-invasive path; document decision inline.
- [ ] **GASPIN-03**: `npm run test:stat` runs cleanly start-to-finish in CI-equivalent fresh-checkout. No flaky failures. Both standalone and combined-suite gas pins agree.

### DELTA — Post-v32.0 Deferred-Commit Adversarial Sub-Audit (Phase 270)

- [ ] **DELTA-01**: Adversarial coverage of commit `002bde55` (presale auto-deactivate) — read full diff, classify per `audit/FINDINGS-v33.0..v36.0.md` delta-surface taxonomy {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED}; sweep adversarial surfaces (state-machine ordering, presale-flag timing, downstream consumer assumptions, MintModule interaction).
- [ ] **DELTA-02**: Adversarial coverage of commit `2713ce61` (setDecimatorAutoRebuy removal) — read full diff, classify, sweep adversarial surfaces (admin-entry-point-removal blast radius, downstream gating assumptions, Decimator state-machine implications, BURNIE auto-rebuy path closure).
- [ ] **DELTA-03**: Verdict per surface — SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence. FINDING_CANDIDATE rows escalate to §3.A finding blocks in Phase 271 deliverable.
- [ ] **DELTA-04**: KI envelope check — confirm `002bde55` + `2713ce61` neither widen EXC-01..04 nor introduce new accepted-design entries warranting KI promotion.

### AUDIT — Adversarial Audit + Findings Consolidation (Phase 271, Terminal)

- [ ] **AUDIT-01**: Delta-surface table covering all source-tree changes v36.0 audit-subject HEAD `1c0f0913` → v37.0 closure HEAD. All Phase 267 (Degenerette contract changes) + Phase 269 (lootbox dead-branch deletion) + Phase 270-discovered carry-forward declarations enumerated with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification.
- [ ] **AUDIT-02**: Adversarial sweep verdicts every Degenerette + lootbox-cleanup + post-v32.0-pickup surface SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence. Surfaces minimum: (a) per-N table dispatch correctness vs match-count distribution; (b) symbol-only hero match — preserves uniformity, no color-channel info leak; (c) `_countGoldQuadrants` boundary (color==7 only, not >=7); (d) producer `[16×7, 8]/120` byte-layout consistency with downstream consumers; (e) WWXRP factor table-dispatch composition with hero boost (no double-counting); (f) lootbox dead-branch removal byte-equivalence (caller-clamp invariant); (g) hero × per-N composition skill-expression channel preserved (v34.0 surface (f) carry).
- [ ] **AUDIT-03**: Conservation re-proof — Degenerette payout flow preserves coin/BURNIE conservation invariants; per-N table calibration math algebraically verified to hold basePayoutEV = 100 centi-x ± rounding; no new mint sites; solvency invariant unchanged.
- [ ] **AUDIT-04**: Zero-new-state scan — zero new storage slots; zero new public/external mutation entry points (NEW: `packedTraitsDegenerette` external pure helper IS a new entry point but pure-function-only with zero state interaction; documented as ALLOWED-NEW-STATELESS-ENTRY); zero new admin functions; zero new modifiers; existing storage layout byte-identical.
- [ ] **AUDIT-05**: `audit/FINDINGS-v37.0.md` published as milestone deliverable; FINAL READ-only at v37.0 closure HEAD; closure signal `MILESTONE_V37_AT_HEAD_<sha>` emitted in §9c. KNOWN-ISSUES.md walkthrough — assess whether Degenerette payout-recalibration warrants any new KI entries (default zero-promotion path per D-262-KI-01 carry; deviation requires user disposition).
- [ ] **AUDIT-06**: Adversarial pass via `/contract-auditor` + `/zero-day-hunter` SEQUENTIAL after full §4 draft per D-NN-ADVERSARIAL-02 carry. Real captured output logged in `271-NN-ADVERSARIAL-LOG.md`; any surfaced novel-composition surfaces folded into §4 prose or §3.A finding blocks per user disposition. `/economic-analyst` + `/degen-skeptic` inclusion deferred to Phase 271 discuss-phase decision.

### REG — Regression Checks (Phase 271)

- [ ] **REG-01**: v36.0 closure signal `MILESTONE_V36_AT_HEAD_1c0f09132d7439af9881c56fe197f81757f8164a` re-verified non-widening at v37.0 HEAD. `EntropyLib` byte-identical; `_rollTargetLevel`/`_resolveLootboxRoll`/`_lootboxTicketCount` v36.0-refactored bodies byte-identical EXCEPT for LBX-01 dead-branch deletion (which is a no-behavior-change cleanup, audit-trail row at AUDIT-01 §3.A).
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening at v37.0 HEAD. `_pickSoloQuadrant` injection sites + `JackpotBucketLib` + `weightedColorBucket` byte-identical (Degenerette path uses NEW `packedTraitsDegenerette`; gold-solo Mint/Jackpot path uses unchanged `packedTraitsFromSeed`; surfaces strictly disjoint).
- [ ] **REG-03**: KI envelope re-verifications. EXC-04 (EntropyLib XOR-shift PRNG, NARROWED to BAF-jackpot-only at v36) RE_VERIFIED — no further narrowing or widening. EXC-01..03 NEGATIVE-scope at v37 (Degenerette + lootbox-cleanup + post-v32 commits have zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction).
- [ ] **REG-04**: Prior-finding spot-check. Walk every prior `audit/FINDINGS-v25..v36.0.md` for findings referencing the v37-touched function set: `DegenerusGameDegeneretteModule` (`_evNormalizationRatio`, `_getBasePayoutBps`, `_applyHeroMultiplier`, `_wwxrpBonusRoiForBucket`), `DegenerusTraitUtils.packedTraitsFromSeed`, `DegenerusGameLootboxModule._resolveLootboxRoll`, presale-flag handling, `setDecimatorAutoRebuy`. Default expectation: ALL rows PASS. SUPERSEDED rows allowed with explicit successor cite (e.g., F-25-NN normalization-related rows replaced by 5-table design).

## Out of Scope

| Feature | Reason |
|---------|--------|
| ETH daily jackpot recalibration | Already drawn at `lvl` not near-future; no per-N math; outside Degenerette path |
| Far-future BURNIE portion | Already per-pull random level (v35.0 PPL-01..08); outside Degenerette path |
| Purchase-phase ticket distributions (`_distributeTicketJackpot`) | Outside Degenerette path; no per-N coupling |
| Trait-roll logic outside Degenerette path | Mint + Jackpot paths use unchanged `packedTraitsFromSeed`; explicitly NOT modified |
| `EntropyLib` API additions | Carry-forward from v36.0 ENT-04 — inline shifts only; no helper functions |
| BAF jackpot `_jackpotTicketRoll` xorshift refactor | v36.0 ENT-05 explicit deferral; out of v37.0 scope |
| Storage layout changes | Constraint: zero new storage |
| New admin / upgrade hooks | Constraint: zero new external mutation entry points (`packedTraitsDegenerette` is pure, exempt) |
| UI / off-chain indexer code | Audit scope is on-chain |
| `runrewardjackpots` module-misplacement (2026-04-02 note) | Stale backlog note, not v37.0-tagged |
| `gameover-thorough-test.md` backlog | Out of v37.0 scope; defer to dedicated game-over hardening milestone |
| Coinflip / redemption / charity / governance / VRF reconfig | Untouched paths |
| Single-normalizer alternative design | Rejected per user disposition; supersedes by 5-table design (`derive_constants.py` retained for reference only) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DGN-01 | Phase 267 | Pending |
| DGN-02 | Phase 267 | Pending |
| DGN-03 | Phase 267 | Pending |
| DGN-04 | Phase 267 | Pending |
| DGN-05 | Phase 267 | Pending |
| DGN-06 | Phase 267 | Pending |
| DGN-07 | Phase 267 | Pending |
| DGN-08 | Phase 267 | Pending |
| DGN-09 | Phase 267 | Pending |
| DGN-10 | Phase 267 | Pending |
| DGN-11 | Phase 267 | Pending |
| DGN-12 | Phase 267 | Pending |
| DGN-13 | Phase 267 | Pending |
| DGN-14 | Phase 267 | Pending |
| DGN-15 | Phase 267 | Pending |
| STAT-01 | Phase 268 | Pending |
| STAT-02 | Phase 268 | Pending |
| STAT-03 | Phase 268 | Pending |
| STAT-04 | Phase 268 | Pending |
| STAT-05 | Phase 268 | Pending |
| STAT-06 | Phase 268 | Pending |
| SURF-01 | Phase 268 | Pending |
| SURF-02 | Phase 268 | Pending |
| SURF-03 | Phase 268 | Pending |
| SURF-04 | Phase 268 | Pending |
| SURF-05 | Phase 268 | Pending |
| SURF-06 | Phase 268 | Pending |
| LBX-01 | Phase 269 | Pending |
| LBX-02 | Phase 269 | Pending |
| LBX-03 | Phase 269 | Pending |
| GASPIN-01 | Phase 269 | Pending |
| GASPIN-02 | Phase 269 | Pending |
| GASPIN-03 | Phase 269 | Pending |
| DELTA-01 | Phase 270 | Pending |
| DELTA-02 | Phase 270 | Pending |
| DELTA-03 | Phase 270 | Pending |
| DELTA-04 | Phase 270 | Pending |
| AUDIT-01 | Phase 271 | Pending |
| AUDIT-02 | Phase 271 | Pending |
| AUDIT-03 | Phase 271 | Pending |
| AUDIT-04 | Phase 271 | Pending |
| AUDIT-05 | Phase 271 | Pending |
| AUDIT-06 | Phase 271 | Pending |
| REG-01 | Phase 271 | Pending |
| REG-02 | Phase 271 | Pending |
| REG-03 | Phase 271 | Pending |
| REG-04 | Phase 271 | Pending |

**Coverage:**
- v37.0 requirements: 47 total (15 DGN + 6 STAT + 6 SURF + 3 LBX + 3 GASPIN + 4 DELTA + 6 AUDIT + 4 REG)
- Mapped to phases: 47 (15 → Phase 267, 12 → Phase 268, 6 → Phase 269, 4 → Phase 270, 10 → Phase 271)
- Unmapped: 0
- Orphans: 0
- Duplicates: 0
- Phase mapping LOCKED via .planning/ROADMAP.md authored 2026-05-10 (gsd-roadmapper honored the provisional split exactly; no rebalance applied).

---
*Requirements defined: 2026-05-10*
*Predecessor v36.0 REQUIREMENTS archived to `.planning/milestones/v36.0-REQUIREMENTS.md`*
