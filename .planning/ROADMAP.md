# Roadmap: Degenerus Protocol Audit

## Milestones

- ✅ **v1.0 Initial RNG Security Audit** — Phases 1-5 (shipped 2026-03-14)
- ✅ **v2.0 Adversarial Audit** — Phases 6-18 (shipped 2026-03-17)
- ✅ **v3.0-v24.1** — Phases 19-212 (shipped 2026-04-10)
- ✅ **v25.0 Full Audit (Post-v5.0 Delta + Fresh RNG)** — Phases 213-217 (shipped 2026-04-11)
- ✅ **v26.0 Bonus Jackpot Split** — Phases 218-219 (shipped 2026-04-12)
- ✅ **v27.0 Call-Site Integrity Audit** — Phases 220-223 (shipped 2026-04-13)
- ✅ **v28.0 Database & API Intent Alignment Audit** — Phases 224-229 (shipped 2026-04-15) — see [milestones/v28.0-ROADMAP.md](milestones/v28.0-ROADMAP.md)
- ✅ **v29.0 Post-v27 Contract Delta Audit** — Phases 230-236 (shipped 2026-04-18) — see [milestones/v29.0-ROADMAP.md](milestones/v29.0-ROADMAP.md)
- ✅ **v30.0 Full Fresh-Eyes VRF Consumer Determinism Audit** — Phases 237-242 (shipped 2026-04-20) — see [milestones/v30.0-ROADMAP.md](milestones/v30.0-ROADMAP.md)
- ✅ **v31.0 Post-v30 Delta Audit + Gameover Edge-Case Re-Audit** — Phases 243-246 (shipped 2026-04-24) — see [milestones/v31.0-ROADMAP.md](milestones/v31.0-ROADMAP.md)
- ✅ **v32.0 Backfill Idempotency + purchaseLevel Underflow Audit** — Phases 247-253 (shipped 2026-05-02) — see [milestones/v32.0-ROADMAP.md](milestones/v32.0-ROADMAP.md)
- ✅ **v33.0 Charity Allowlist Governance** — Phases 254-258 (shipped 2026-05-07; closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941`) — see [milestones/v33.0-ROADMAP.md](milestones/v33.0-ROADMAP.md)
- 🚧 **v34.0 Trait Rarity Rework + Gold Solo Priority** — Phases 259-262 (planning)

## Phases

<details>
<summary>✅ v33.0 Charity Allowlist Governance (Phases 254-258) — SHIPPED 2026-05-07</summary>

- [x] Phase 254: GNRUS Allowlist Storage, Admin Op & Storage Repack (3/3 plans) — completed 2026-05-06
- [x] Phase 255: Vote Rewrite, Resolve Flush & Event/Error Cleanup (3/3 plans) — completed 2026-05-06
- [x] Phase 256: Charity Allowlist Test Coverage (6/6 plans) — completed 2026-05-06
- [x] Phase 257: Delta Audit & Findings Consolidation (1/1 plans) — completed 2026-05-06 (closure signal `MILESTONE_V33_AT_HEAD_dcb70941`, superseded)
- [x] Phase 258: pickCharity Flush-Order Fix + Previous-Winner Vote Block (3/3 plans) — completed 2026-05-07 (closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `dcb70941`)

**Audit baseline:** v32.0 HEAD `acd88512` (closure signal `MILESTONE_V32_AT_HEAD_acd88512`) → v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Mixed shape — Phases 254-256 modify `contracts/GNRUS.sol` + add tests under `test/governance/`; Phase 257 delta-audits the result; Phase 258 patches the result post-closure (Phase 257 independent re-run surfaced a queue-branch redirect bug — Phase 258-01 reordered `pickCharity` flush-after-payout + added `lastWinningRecipient` + `PreviousWinnerNotVotable()` block; Phase 258-02 re-audited at the patched HEAD). Per `feedback_no_contract_commits.md`, all `contracts/` + `test/` changes require explicit per-commit user approval. 28/28 v33.0 requirements satisfied (ALW + VOTE + RES + CLEAN + TST + AUDIT-01..05 + FIX-01 + FIX-02). Result: 9 of 9 §4 adversarial surfaces SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_TRUST_ASYMMETRY (a..i, with surface (i) consecutive-recipient capture closure added by Phase 258 FIX-02); zero F-33-NN findings; 1 PASS REG-01; zero-row REG-02; 4 NEGATIVE-scope KI envelope re-verifications; KNOWN-ISSUES.md UNMODIFIED. Deliverable: `audit/FINDINGS-v33.0.md` (FINAL READ-only at HEAD `4ce3703d`). See [milestones/v33.0-ROADMAP.md](milestones/v33.0-ROADMAP.md) and [milestones/v33.0-REQUIREMENTS.md](milestones/v33.0-REQUIREMENTS.md).

</details>

### v34.0 Trait Rarity Rework + Gold Solo Priority (Phases 259-262) — PLANNING

- [x] **Phase 259: Trait Distribution Split** — Replace flat `weightedBucket` two-call composition with single 8-tier `weightedColorBucket` heavy-tail color distribution + uniform symbol; preserve `[QQ][CCC][SSS]` byte layout. (completed 2026-05-08)
- [ ] **Phase 260: Gold Solo Priority Injection** — Add `_pickSoloQuadrant` helper to `DegenerusGameJackpotModule.sol` and inject `effectiveEntropy` substitution at all 4 ETH-split sites (lines 282, 349, 524, 1147) atomically.
- [ ] **Phase 261: Statistical Validation + Cross-Surface Verification** — 1M-sample Monte Carlo + chi-squared infrastructure for color/symbol distributions; gold-solo coverage + tie-break uniformity simulations; pack-feel CIs; cross-surface preservation checks (hero override / deity-pass / Degenerette / bonus jackpot non-injection / gas regression).
- [ ] **Phase 262: Delta Audit + Findings Consolidation** — Author `audit/FINDINGS-v34.0.md` 9-section deliverable (FINAL READ-only at HEAD); adversarial sweep over the trait + solo deltas; v33.0 + v32.0 closure signal regression; KI envelope re-verifications; emit closure signal `MILESTONE_V34_AT_HEAD_<sha>`.

## Phase Details

### Phase 259: Trait Distribution Split

**Goal:** `DegenerusTraitUtils.sol` implements the heavy-tail color distribution (25/25/25/12.5/6.25/3.125/2.344/0.781 % over 256-resolution thresholds) via a single `weightedColorBucket(uint32) → uint8` while preserving the `[QQ][CCC][SSS]` byte layout and symbol slice. Legacy `weightedBucket` is fully removed; all callers in `contracts/` are migrated.
**Depends on:** Nothing (first impl phase; baseline v33.0 HEAD `4ce3703d740d3707c88a1af595618120a8168399`)
**Requirements:** TRAIT-01, TRAIT-02, TRAIT-03, TRAIT-04, TRAIT-05, TRAIT-06
**Success Criteria** (what must be TRUE):
  1. `weightedBucket(uint32)` is structurally absent from `contracts/` (grep `weightedBucket` returns zero hits); `weightedColorBucket(uint32) → uint8` returns the expected color tier on every threshold boundary (`scaled = 0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255`).
  2. `traitFromWord(uint64)` composes `(color << 3) | symbol` where `color = weightedColorBucket(uint32(rnd))` and `symbol = uint8(rnd >> 32) & 7`; bottom 32 bits and top 32 bits of `rnd` drive disjoint axes (verified by isolated-bit unit tests).
  3. `packedTraitsFromSeed(uint256)` produces byte-identical quadrant flags (`| 64`, `| 128`, `| 192`) under the new color/symbol composition; existing byte-layout tests pass without modification.
  4. Hardhat unit-test surface for `weightedColorBucket` covers all 8 buckets at every threshold (16 boundary cases) and for `traitFromWord` covers the bit-slice composition end-to-end; suite green at the phase-close HEAD.
**Plans:** 3/3 plans complete
- [x] 259-01-PLAN.md — Rewrite `contracts/DegenerusTraitUtils.sol` (weightedColorBucket + traitFromWord + terminology switch; legacy weightedBucket removed) [TRAIT-01..04] — staged uncommitted (D-10 batched approval)
- [x] 259-02-PLAN.md — Create `contracts/test/TraitUtilsTester.sol` external-pure harness exposing all 3 trait-utils functions [TRAIT-05, TRAIT-06] — staged uncommitted (D-10 batched approval)
- [x] 259-03-PLAN.md — Author `test/unit/DegenerusTraitUtils.test.js` (16 boundary + 4 composition + 6 byte-layout assertions); run TRAIT-04 grep gate; run unchanged Foundry fuzz regression; phase-end batched diff approval [TRAIT-04, TRAIT-05, TRAIT-06] — staged uncommitted (D-10 batched approval); 26 Hardhat tests passing; TRAIT-04 grep zero hits; D-09 fuzz strict-literal pre-existing baseline failure documented as deferred deviation

### Phase 260: Gold Solo Priority Injection

**Goal:** `DegenerusGameJackpotModule.sol` exposes a private `_pickSoloQuadrant(uint8[4], uint256) → uint8` helper that returns a uniformly-random gold-color (color==7) quadrant when any winning trait is gold (option B tie-break), else the existing rotation index. The four ETH-split sites at lines 282 / 349 / 524 / 1147 substitute `effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` BEFORE every `JackpotBucketLib.shareBpsByBucket` / `bucketCountsForPoolCap` read. The 8 documented non-injection sites (513, 527, 598, 599, 683, 1687, 1713, 1715) remain byte-identical. `JackpotBucketLib` is UNCHANGED.
**Depends on:** Phase 259 (gold color tier — color==7 — must exist in the distribution before `_pickSoloQuadrant` can ever fire on a non-empty gold set)
**Requirements:** SOLO-01, SOLO-02, SOLO-03, SOLO-04, SOLO-05, SOLO-06, SOLO-07, SOLO-08, SOLO-09
**Success Criteria** (what must be TRUE):
  1. `_pickSoloQuadrant(uint8[4], uint256) → uint8` private pure helper present in `DegenerusGameJackpotModule.sol`: zero-gold input returns existing rotation index `uint8((3 - (entropy & 3)) & 3)` (matches v33.0 behavior); single-gold input always returns that quadrant index regardless of `entropy >> 4`; multi-gold input distributes uniformly via `goldQuads[uint8((entropy >> 4) & 3) % goldCount]` and uses bits *disjoint* from the bucket-rotation low-2-bits.
  2. All 4 ETH-distribution call sites (lines 282, 349, 524, 1147) substitute `effectiveEntropy` BEFORE every `JackpotBucketLib.shareBpsByBucket` / `bucketCountsForPoolCap` / `_processDailyEth` / `_executeJackpot` read; line-349 and line-1147 produce IDENTICAL `effectiveEntropy` from identical `(randWord, lvl, EntropyLib.hash2)` inputs (split-mode coherence — `resumeEthPool` written by call 1 is consumed by call 2 against the same bucket structure).
  3. The 8 documented non-injection sites (lines 513, 527, 598, 599, 683, 1687, 1713, 1715) are byte-identical vs v33.0 baseline `4ce3703d` (grep + `git diff` verified) — events emit unchanged signatures and equal-split bucket distributions are unaffected.
  4. `JackpotBucketLib` is byte-identical vs v33.0 baseline; `soloBucketIndex(entropy) = (3 - (entropy & 3)) & 3` formula preserved; `traitBucketCounts` / `shareBpsByBucket` / `rotatedShareBps` rotation logic unchanged.
  5. Hardhat unit tests for `_pickSoloQuadrant` (0 / 1 / 2 / 3 / 4-gold cases plus 100K-entropy uniformity sanity) pass; SOLO-09 integration test exercising the line-349 → line-1147 SPLIT_CALL1 → SPLIT_CALL2 path with at least one gold winning trait passes (both calls land on the same gold quadrant; bucket totals reconstruct correctly across the split).
**Plans:** TBD

**Atomicity:** All 4 SOLO injection sites ship in one phase. Partial injection breaks split-mode coherence — line 349 (`payDailyJackpot` jackpot-phase) and line 1147 (`_resumeDailyEth` SPLIT_CALL2) MUST compute identical `effectiveEntropy` from identical `(randWord, lvl, EntropyLib.hash2)` inputs or `resumeEthPool` written by call 1 is consumed by call 2 against a stale bucket structure. Verified end-to-end via SOLO-09 integration test.

### Phase 261: Statistical Validation + Cross-Surface Verification

**Goal:** A new Hardhat statistical-validation test directory (e.g. `test/stat/`) drives 1M-sample empirical frequency + chi-squared independence proofs for the new color distribution, the bit-slice composition, gold-solo coverage (100% on gold-present draws), and gold-solo tie-break uniformity. Cross-surface verification confirms hero override / deity-pass virtual entries / Degenerette match payouts / bonus-jackpot non-injection sites are unchanged in behavior. Gas regression stays within ±100 gas per trait roll and < 2000 gas per top-level entry point under worst-case (4-gold) `_pickSoloQuadrant`.
**Depends on:** Phase 259 (`weightedColorBucket` + `traitFromWord` are the units under empirical test) AND Phase 260 (`_pickSoloQuadrant` is the unit under the gold-solo simulations + the gas-regression call envelope)
**Requirements:** STAT-01, STAT-02, STAT-03, STAT-04, STAT-05, STAT-06, STAT-07, SURF-01, SURF-02, SURF-03, SURF-04, SURF-05
**Success Criteria** (what must be TRUE):
  1. 1M-sample empirical color-frequency test: every bucket within 3-sigma binomial bounds of target (25.000% / 25.000% / 25.000% / 12.500% / 6.250% / 3.125% / 2.344% / 0.781%), tolerance ±0.1%; symbol uniformity chi-squared p > 0.05 over 1M samples; (color, symbol) joint independence chi-squared p > 0.05.
  2. Gold-solo coverage simulation: over 100K draws with ≥1 gold-color trait in the winning set, the solo bucket lands on a gold quadrant in 100% of cases; over 100K multi-gold draws, the gold-quadrant choice is uniform (chi-squared p > 0.05); EV uplift ≈ 3.3× for gold holders vs uniform baseline.
  3. Pack-feel CIs over ≥100K 10-ticket packs: ≥1 notable-tier (color≥3) trait in 99.5% of packs; ≥1 rare-tier (color≥4) in 92.3%; ≥1 epic-tier (color≥5) in 71.7%; ≥1 legendary (color==7) in 27.0% — all targets within 99% Monte Carlo CIs.
  4. Cross-surface preservation: hero override (`_applyHeroOverride`) writes `(quadrant << 6) | (color << 3) | symbol` byte-identically (color is RNG-derived 3-bit literal slice — intentionally NOT through `weightedColorBucket`); existing Degenerette test suite passes unchanged; the 8 non-injection bonus-jackpot call sites (513, 527, 598, 599, 683, 1687, 1713, 1715) emit byte-identical events / produce byte-identical bucket distributions vs v33.0 baseline.
  5. Gas regression: `weightedColorBucket(uint32) → uint8` per-call delta within ±100 gas vs prior `weightedBucket(uint32) → uint8`; `_pickSoloQuadrant` per-call < 500 gas under worst-case (4-gold) input (theoretical worst case derived FIRST per `feedback_gas_worst_case.md`, then tested); total delta on `runTerminalJackpot` / `payDailyJackpot` / `_resumeDailyEth` < 2000 gas each.
**Plans:** TBD

### Phase 262: Delta Audit + Findings Consolidation

**Goal:** Publish `audit/FINDINGS-v34.0.md` as the single canonical milestone-closure deliverable — 9-section shape consistent with v32.0 / v33.0; every changed function / state variable / event / error in `contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameJackpotModule.sol` enumerated and classified vs v33.0 baseline `4ce3703d`; adversarial sweep over the trait + solo deltas verdicts every surface SAFE or FINDING_CANDIDATE with grep-cited evidence; conservation invariants re-proven; v33.0 + v32.0 closure signals re-verified non-widening; KI envelopes EXC-01..04 re-verified (with extra attention to EXC-04 XOR-shift quality on `_pickSoloQuadrant` tie-break); KNOWN-ISSUES.md updated only via D-09 3-predicate gating; closure signal `MILESTONE_V34_AT_HEAD_<sha>` emitted in §9c.
**Depends on:** Phase 259, Phase 260, Phase 261 (audit baseline is the post-test HEAD with TRAIT + SOLO impl + STAT/SURF tests all landed)
**Requirements:** AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, REG-01, REG-02, REG-03, REG-04
**Success Criteria** (what must be TRUE):
  1. `audit/FINDINGS-v34.0.md` published FINAL READ-only at HEAD with 9 sections (executive summary, per-phase sections, F-34-NN finding blocks under D-08 5-bucket severity rubric, regression appendix, KI gating walk, closure attestation); §3a delta-surface table enumerates every changed declaration in the two contracts with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} classification; §3a downstream-caller inventory is grep-reproducible.
  2. §4 adversarial sweep verdicts every identified surface SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with explicit row-level evidence covering: (a) entropy-bit collision between gold tie-break (`entropy >> 4`) and bucket rotation (`entropy & 3`); (b) line-349 ↔ line-1147 split-call determinism; (c) gold-population manipulation via player ticket purchases; (d) gas-griefing of `_pickSoloQuadrant` 4-iteration loop; (e) overflow / signed-vs-unsigned in `~uint256(3)` mask.
  3. §3b conservation re-proof: solvency invariant (`claimablePool ≤ ETH balance + stETH balance`) PRESERVED across the trait/solo changes; pool-balance algebra unchanged because share BPS and bucket counts are unchanged — only the bucket-index assignment rotates.
  4. §5 regression: REG-01 PASS for v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` non-widening (charity governance / GNRUS.sol untouched in v34.0 — FIX-01 + FIX-02 invariants preserved); REG-02 PASS for v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` non-widening (L173 + L1174 + GameStorage `_livenessTriggered` body byte-identical); REG-04 spot-check re-verifies every prior finding referencing `weightedBucket` / `traitFromWord` / `packedTraitsFromSeed` / `JackpotBucketLib` / `_rollWinningTraits` / `_executeJackpot` / `_processDailyEth` / `_runJackpotEthFlow` / `runTerminalJackpot` / `payDailyJackpot` / `_resumeDailyEth` with PASS / REGRESSED / SUPERSEDED grep-cited verdicts.
  5. §6 KI gating walk: EXC-01..04 RE_VERIFIED with EXC-04 (EntropyLib XOR-shift) extra-attention attestation cross-citing the STAT-05 chi-squared empirical evidence; KNOWN-ISSUES.md UNMODIFIED unless a new candidate passes the D-09 3-predicate gate (accepted-design + non-exploitable + sticky); §9c emits `MILESTONE_V34_AT_HEAD_<sha>` closure signal.
**Plans:** TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 259. Trait Distribution Split | 3/3 | Complete    | 2026-05-08 |
| 260. Gold Solo Priority Injection | 0/0 | Not started | - |
| 261. Statistical Validation + Cross-Surface Verification | 0/0 | Not started | - |
| 262. Delta Audit + Findings Consolidation | 0/0 | Not started | - |

## Active Milestone

**v34.0 Trait Rarity Rework + Gold Solo Priority** — PLANNING (defined 2026-05-08). 4 phases (259-262), 36 requirements (TRAIT-01..06, SOLO-01..09, STAT-01..07, SURF-01..05, AUDIT-01..05, REG-01..04). Audit baseline v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Modifies `contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameJackpotModule.sol`; adds Hardhat statistical-validation tests under `test/stat/` (or equivalent); produces a 9-section delta-audit deliverable `audit/FINDINGS-v34.0.md`. **Write policy:** READ-only LIFTED for v34.0 (consistent with v32.0/v33.0 audit posture); all `contracts/` + `test/` changes require explicit per-commit user approval per `feedback_no_contract_commits.md`; phases that batch multiple contract edits use the batched approval pattern per `feedback_batch_contract_approval.md`. Closure signal target: `MILESTONE_V34_AT_HEAD_<sha>`. See [REQUIREMENTS.md](REQUIREMENTS.md) and [STATE.md](STATE.md).

## Last Shipped Milestone

**v33.0 Charity Allowlist Governance (post-closure patch)** — SHIPPED 2026-05-06; RE-SHIPPED 2026-05-07 via Phase 258. 5 phases (254-258), 28 requirements satisfied (ALW + VOTE + RES + CLEAN + TST + AUDIT-01..05 + FIX-01 + FIX-02). Audit baseline v32.0 HEAD `acd88512` → v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399`. Closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` (supersedes `MILESTONE_V33_AT_HEAD_dcb70941`). Deliverable: `audit/FINDINGS-v33.0.md` (FINAL READ-only at HEAD `4ce3703d`). See [milestones/v33.0-ROADMAP.md](milestones/v33.0-ROADMAP.md) and [milestones/v33.0-REQUIREMENTS.md](milestones/v33.0-REQUIREMENTS.md).
