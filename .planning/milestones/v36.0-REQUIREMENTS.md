# Requirements: Degenerus Protocol — v36.0 Lootbox-Path Entropy Refactor

**Defined:** 2026-05-09
**Milestone:** v36.0
**Goal:** Replace `EntropyLib.entropyStep` (XOR-shift PRNG) chains in the lootbox-resolution code path with bit-sliced `EntropyLib.hash2` keccak draws. Removes the known-weak-PRNG-construction warden surface in the lootbox path; preserves uniformity at slightly-better-than-equivalent statistical quality; gas delta within ±300 gas per lootbox open. BAF jackpot `_jackpotTicketRoll` (`JackpotModule:2192`) is the same xorshift pattern but explicitly OUT of scope this milestone (deferred to a future phase).
**Audit baseline:** v35.0 audit-subject HEAD `5db8682bd7b811437f0c1cf47e832619d1478ac6`
**Audit baseline signal:** `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6`
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**READ-only audit posture:** LIFTED — audit-then-commit (or impl-then-audit) with per-commit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`.
**Phase shape:** Single-phase patch (Path 2 user-disposition: open v36.0 milestone with single Phase 266 covering implementation + tests + audit deliverable + closure signal). Mirrors lightweight v3.x post-closure-patch pattern, NOT the full v34/v35 multi-phase milestone shape.

## v36.0 Requirements

### ENT — Lootbox-Path Entropy Refactor (Core Implementation)

- [ ] **ENT-01**: `_rollTargetLevel(uint24, uint256)` (`DegenerusGameLootboxModule.sol:809-827`) replaces both `entropyStep(prev)` calls (L813, L817) with bit-sliced reads from a single keccak-derived seed (or `hash2(seed, 1)` for the rare 10% far-level branch if same-seed bit budget exceeded). Inline `uint16(seed) % 100`, `uint8(seed >> 16) % 5`, `uint16(seed >> 24) % 46` style shifts; no new helper functions added to `EntropyLib`.
- [ ] **ENT-02**: `_resolveLootboxRoll(...)` (`DegenerusGameLootboxModule.sol:1530-1616`) replaces all 4 `entropyStep` calls (L1548, L1569, L1585, L1599) with inline bit-sliced reads from a single keccak-derived seed threaded from `_resolveLootboxCommon`. The `% 20` path-roll (L1551) + `% 20` variance-roll (L1600) + sub-path entropy needs (DGNRS amount, WWXRP soft-cap, large-BURNIE variance) all served from one 256-bit seed via documented bit-offset slicing; falls back to `hash2(seed, 1)` second-chunk if any single resolution exceeds the bit budget.
- [ ] **ENT-03**: `_lootboxTicketCount(uint256, uint256, uint256)` (`DegenerusGameLootboxModule.sol:1626-1635`) replaces its 1 `entropyStep` call (L1635) with a `uint24(seed >> N) % 10_000` slice (or `hash2(seed, 2)` if upstream bit budget exhausted). The `% 10_000` variance-roll needs ≥ 24 bits to keep modulo bias under 0.6%.
- [ ] **ENT-04**: `EntropyLib` API stable — `entropyStep` and `hash2` both retained unchanged; NO new helper functions added (per user disposition: inline shifts only). Other consumers of `entropyStep` (BAF jackpot `_jackpotTicketRoll` in JackpotModule, MintModule, etc.) UNTOUCHED.
- [ ] **ENT-05**: BAF jackpot `_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) explicitly OUT of scope. Same xorshift pattern, would benefit from same refactor — captured as future-phase candidate; no v36.0 change.
- [ ] **ENT-06**: Bit-budget per consumer documented inline (NatSpec or comment block on each refactored function): which bit ranges of the seed each sub-roll consumes + which `hash2(seed, N)` chunk is used if the per-call budget exceeds 256 bits.

### STAT — Light Statistical Validation

- [ ] **STAT-01**: Per-sub-roll uniformity chi-squared confirms each refactored draw is statistically uniform within its modulus. Buckets covered: `_rollTargetLevel %100` + `%5` + `%46`; `_resolveLootboxRoll %20` (path-roll) + `%20` (variance-roll); `_lootboxTicketCount %10000`. ≥ 5K samples per bucket, chi² < critical at α=0.05 / df = bucket-count - 1.
- [ ] **STAT-02**: Pre-/post-refactor distribution shape preserved — both produce uniform draws within expected statistical tolerance (no requirement that specific outcomes match given a fixed VRF word; behavioral change is acceptable per user disposition).
- [ ] **STAT-03**: Test suite reuses Phase 261 / Phase 264 chi² infrastructure (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ`) — no fresh statistical tooling introduced.

### GAS — Gas Regression

- [ ] **GAS-01**: `openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect` per-open gas delta within ±300 gas of pre-refactor baseline. Direction expected: ~150-200 gas DELTA-POSITIVE per open (keccak ~70 g vs xorshift ~40 g per draw × 5-7 draws per resolution); test allows ±300 gas headroom.
- [ ] **GAS-02**: `advanceGame` per-day gas envelope unchanged within ±2K (Decimator settlement is the one advanceGame-resident lootbox-resolution caller; bounded impact). 1.99× margin from v34/v35 SURF-05 baseline preserved.

### SURF — Cross-Surface Preservation

- [ ] **SURF-01**: `EntropyLib.sol` `hash2` body byte-identical (no signature change, no behavior change). `entropyStep` body byte-identical.
- [ ] **SURF-02**: BAF jackpot `_jackpotTicketRoll` (JackpotModule:2186-2229) byte-identical — confirms ENT-05 deferral discipline.
- [ ] **SURF-03**: MintModule `EntropyLib.hash2(entropy, rollSalt)` callsite (L652) byte-identical.
- [ ] **SURF-04**: All non-lootbox `EntropyLib.entropyStep` and `EntropyLib.hash2` callsites in `DegenerusGameJackpotModule.sol` (L285, L453, L532, L610, L612, L886, L1176, L1873, L2192) byte-identical — only LootboxModule callsites change.

### AUDIT — Adversarial Audit + Findings Consolidation

- [ ] **AUDIT-01**: Delta-surface table covering all source-tree changes v35.0 audit-subject HEAD `5db8682b` → v36.0 closure HEAD. Modified declarations in `DegenerusGameLootboxModule.sol` enumerated with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED} classification.
- [ ] **AUDIT-02**: Adversarial sweep verdicts every lootbox-entropy refactor surface SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence. Surfaces minimum: (a) bit-slice modulo-bias per draw within documented bound; (b) seed-reuse across sub-rolls within same resolution doesn't introduce predictable cross-correlation; (c) `hash2(seed, N)` chunk indexing collision-free across consumers; (d) gas-griefing delta bounded; (e) byte-identity preserved on the deferred BAF jackpot xorshift path (ENT-05 verification).
- [ ] **AUDIT-03**: Conservation re-proof — lootbox payouts (BURNIE / DGNRS / WWXRP / tickets) preserved within statistical uniformity vs xorshift baseline; no new mint sites; solvency invariant unchanged (no ETH/stETH balance interactions in the refactored code).
- [ ] **AUDIT-04**: Zero-new-state scan — zero new storage slots; zero new public/external mutation entry points; zero new admin functions; zero new modifiers; `EntropyLib` API stable (ENT-04).
- [ ] **AUDIT-05**: `audit/FINDINGS-v36.0.md` published as milestone deliverable; FINAL READ-only at v36.0 closure HEAD; closure signal `MILESTONE_V36_AT_HEAD_<sha>` emitted in §9c. KNOWN-ISSUES.md `**EntropyLib XOR-shift PRNG for lootbox outcome rolls.**` entry rephrased to BAF-only scope (since the lootbox path no longer uses xorshift; remaining xorshift consumer is BAF jackpot per ENT-05 deferral).

### REG — Regression Checks

- [ ] **REG-01**: v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6` re-verified non-widening at v36.0 HEAD (per-pull-level resample helper byte-identical; `_awardDailyCoinToTraitWinners` body + 2 callsites + `COIN_LEVEL_TAG` constant unchanged).
- [ ] **REG-02**: v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified non-widening at v36.0 HEAD (TraitUtils + `_pickSoloQuadrant` injection sites + JackpotBucketLib byte-identical).
- [ ] **REG-03**: KI envelope re-verifications. EXC-04 (EntropyLib XOR-shift PRNG) scope NARROWS at v36 — lootbox-path xorshift removed, BAF-jackpot-path xorshift retained; entry rephrased per AUDIT-05. EXC-01..03 NEGATIVE-scope at v36 (lootbox-entropy refactor has zero affiliate-roll / AdvanceModule / gameover-RNG-substitution interaction).
- [ ] **REG-04**: Prior-finding spot-check. Walk every prior `audit/FINDINGS-v25..v35.0.md` for findings referencing the v36-touched function set: `EntropyLib.entropyStep`, `_rollTargetLevel`, `_resolveLootboxRoll`, `_lootboxTicketCount`, `openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`. Default expectation: ALL rows PASS.

## Out of Scope

| Feature | Reason |
|---------|--------|
| BAF jackpot `_jackpotTicketRoll` xorshift refactor | ENT-05 explicit deferral per user disposition; same pattern would apply but separate phase |
| MintModule `EntropyLib.hash2` callsite | Already keccak; no change needed (SURF-03) |
| All JackpotModule `EntropyLib.hash2` callsites | Used for upstream entropy mixing (single keccak per call); not chained xorshift; no change needed (SURF-04) |
| `EntropyLib` API additions | User disposition: inline shifts only; no helper functions (ENT-04) |
| Behavioral equivalence (specific-outcome replay) | Not required per user disposition; uniform-distribution equivalence sufficient (STAT-02) |
| Audit of post-v32.0 unaudited commits (`002bde55`, `2713ce61`) | Carry-forward deferral from v33.0 → v34.0 → v35.0 → v36.0 close per repeated user disposition |
| Coinflip / redemption / charity / governance / VRF reconfig | Untouched paths |
| Storage layout changes | Constraint: zero new storage |
| New admin / upgrade hooks | Constraint: zero new external mutation entry points |
| UI / off-chain indexer code | Audit scope is on-chain |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENT-01 | Phase 266 | Pending |
| ENT-02 | Phase 266 | Pending |
| ENT-03 | Phase 266 | Pending |
| ENT-04 | Phase 266 | Pending |
| ENT-05 | Phase 266 | Pending |
| ENT-06 | Phase 266 | Pending |
| STAT-01 | Phase 266 | Pending |
| STAT-02 | Phase 266 | Pending |
| STAT-03 | Phase 266 | Pending |
| GAS-01 | Phase 266 | Pending |
| GAS-02 | Phase 266 | Pending |
| SURF-01 | Phase 266 | Pending |
| SURF-02 | Phase 266 | Pending |
| SURF-03 | Phase 266 | Pending |
| SURF-04 | Phase 266 | Pending |
| AUDIT-01 | Phase 266 | Pending |
| AUDIT-02 | Phase 266 | Pending |
| AUDIT-03 | Phase 266 | Pending |
| AUDIT-04 | Phase 266 | Pending |
| AUDIT-05 | Phase 266 | Pending |
| REG-01 | Phase 266 | Pending |
| REG-02 | Phase 266 | Pending |
| REG-03 | Phase 266 | Pending |
| REG-04 | Phase 266 | Pending |

**Coverage:**
- v36.0 requirements: 24 total (6 ENT + 3 STAT + 2 GAS + 4 SURF + 5 AUDIT + 4 REG)
- Mapped to phases: 24 (24 → Phase 266 single-phase patch shape per user disposition)
- Unmapped: 0
- Orphans: 0
- Duplicates: 0

---
*Requirements defined: 2026-05-09*
*Predecessor v35.0 REQUIREMENTS archived to `.planning/milestones/v35.0-REQUIREMENTS.md`*
