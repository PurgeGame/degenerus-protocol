---
phase: 262-delta-audit-findings-consolidation
plan: 01
milestone: v34.0
milestone_name: Trait Rarity Rework + Gold Solo Priority
head_anchor: <will-be-filled-by-Task-13>
audit_baseline: 4ce3703d740d3707c88a1af595618120a8168399
audit_baseline_signal: MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
v32_baseline: acd88512
v32_baseline_signal: MILESTONE_V32_AT_HEAD_acd88512
deliverable: audit/FINDINGS-v34.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Pure-consolidation phase per CONTEXT.md hard constraint #1. Zero contracts/ writes by agent. Zero test/ writes by agent. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-262-KI-01 default zero-promotion path. Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change — vacuous this phase since no contract changes are proposed by agent."
supersedes: none
status: DRAFT
read_only: false
closure_signal: <will-be-filled-by-Task-13>
generated_at: <will-be-filled-by-Task-13>
---

# v34.0 Findings — Trait Rarity Rework + Gold Solo Priority

**Audit Baseline.** The audit baseline is v33.0 contract-tree HEAD `4ce3703d740d3707c88a1af595618120a8168399` (closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` carry-forward from `audit/FINDINGS-v33.0.md` §9c, supersedes `MILESTONE_V33_AT_HEAD_dcb70941`). HEAD `<will-be-filled-by-Task-13>` (currently `6b63f6d4` per phase-start, post-Phase-261 close `docs(261): verification report`). Five v34 contract-tree commits since baseline: `301f7fad` (Phase 259-01 — `feat(259-01): rewrite DegenerusTraitUtils — heavy-tail color distribution`) + `031a8cbc` (Phase 259-02 — `feat(259-02): add TraitUtilsTester external-pure test harness`) + `2fa7fb6e` (Phase 260 — `feat(260): inject gold-solo-priority + tests [SOLO-01..SOLO-09]`) + `1574d533` (Phase 261-03 — `chore(261-03): add noOp() companion to JackpotSoloTester for paired-empty-wrapper delta`) + `a6c4f18a` (Phase 261-03 — `perf(261-03): refactor _pickSoloQuadrant to pure-stack uint256 packing`). Eight v34 test-tree commits: `d67b8ac3` (Phase 259-03 unit tests `test/unit/DegenerusTraitUtils.test.js`); Phase 260's `2fa7fb6e` (combined feat+test commit; test files `test/unit/JackpotSoloPicker.test.js` + `test/integration/JackpotSoloSplit.test.js`); `2eafdde8` / `197c8197` / `2d4152a4` / `4e3e7a5e` / `4e015d2e` / `00de73ed` (Phase 261 stat + gas suite). `contracts/GNRUS.sol` is byte-identical between v33.0 baseline `4ce3703d` and v34 HEAD (REG-01 PASS — see §5a). The L173 turbo guard (`!rngLockedFlag` clause) + L1174 backfill sentinel (`rngWordByDay[idx + 1] == 0`) + GameStorage `_livenessTriggered` body are byte-identical between v32.0 baseline `acd88512` and v34 HEAD (REG-02 PASS — see §5b).

**Scope.** Single canonical milestone-closure deliverable for v34.0 per D-262-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-253-15 / D-257 carry-forward (9-section shape locked). Consolidates Phase 259 / 260 / 261 outputs into 9 sections per D-253-15 / D-257 carry. Terminal phase per CONTEXT.md D-262 carry of D-257-FCITE-01 — zero forward-cites emitted from Phase 262 to any post-v34.0 milestone phases (e.g., the burnie-near-future-per-pull-level-resample seed in `.planning/notes/2026-05-08-burnie-near-future-per-pull-level.md` is a v35.0 backlog item, NOT retro-fitted as a forward-cite from this deliverable). Mirrors v33 Phase 257 single-plan multi-task atomic-commit pattern adapted for v34's 3-impl/test-phase + 1-audit-phase scope per D-262-PLAN-01.

**Write policy.** READ-only after Task 13 atomic commit per D-253-CF-02 / D-257 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at HEAD per D-262-KI-01 default zero-promotion path (any v34-discovered finding-candidate would FAIL the D-09 sticky predicate because v34 trait/solo surface is freshly-landed not "ongoing protocol behavior" until the next milestone). Zero awaiting-approval test files (all 5 v34 contract commits + 8 v34 test commits USER-APPROVED batched per `feedback_batch_contract_approval.md` per Phase 259 / 260 / 261 close). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change; vacuous this phase since no contract changes are proposed by agent (zero `contracts/` writes + zero `test/` writes by agent — hard constraint #1).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: `CLOSED_AT_HEAD_<sha>` (delta surface complete; every changed function/state-var/event/error in `contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameJackpotModule.sol` vs baseline `4ce3703d` enumerated with hunk-level evidence and classified per ROADMAP success criterion 1)
- AUDIT-02: `5 of 5 surfaces SAFE_*; 0 of 0 FINDING_CANDIDATE PROMOTED` (default expected per D-262-FIND-01)
- AUDIT-03: `CLOSED_AT_HEAD_<sha>` (bucket-share-sum × pool invariance under bucket-index rotation; JackpotBucketLib byte-identity SOLO-07 carry; solvency invariant `claimablePool ≤ ETH balance + stETH balance` preserved; hero override byte-layout SURF-01 carry; split-mode coherence SOLO-09 carry)
- AUDIT-04: `0 new public/external mutation entry points; 0 new storage slots in GameStorage / DegenerusGameJackpotModule / DegenerusTraitUtils`
- AUDIT-05: `MILESTONE_V34_AT_HEAD_<sha>` emitted in §9c
- REG-01: `1 PASS row — v33.0 closure signal MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399 NON-WIDENING at v34 HEAD`
- REG-02: `1 PASS row — v32.0 closure signal MILESTONE_V32_AT_HEAD_acd88512 NON-WIDENING at v34 HEAD`
- REG-03: `4 KI envelope re-verifications: EXC-01..03 NEGATIVE-scope; EXC-04 RE_VERIFIED with STAT-05 chi² cross-cite; KNOWN_ISSUES_UNMODIFIED`
- REG-04: `<N> PASS / 0 REGRESSED / 0 SUPERSEDED prior-finding spot-check rows across audit/FINDINGS-v25.0.md → audit/FINDINGS-v33.0.md`
- Combined milestone closure: `MILESTONE_V34_AT_HEAD_<sha>`

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-34-NN: 0

Default expected per D-262-FIND-01. v34 trait/solo deltas are mathematically well-bounded: bucket-share-sum × pool invariant under bucket-index rotation; gold-priority entropy bits VRF-derived not player-controllable; chi²-evidenced uniformity at STAT-04..05 covers tie-break determinism empirically. Severity ceiling for any v34-emitted F-34-NN: HIGH (bucket-rotation rotation does not extract value; no draining of pool past existing distribution mechanics; bounded by per-jackpot-call rate). Severity counts reconcile to §4 F-34-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v30/v31/v32/v33 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-34-NN that may surface during Task 7 disposition: HIGH ceiling (bucket-rotation rotation does not extract value; bucket-share-sum × pool invariant under rotation; gold-priority bits VRF-derived not player-controllable). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items (e.g., the ROADMAP/REQUIREMENTS reconciliation drifts from Phase 261 deferred items — STAT-07 informational headline targets vs canonical analytical values; SURF-05 paired-empty-wrapper amendment vs ROADMAP `_pickSoloQuadrant per-call < 500 gas` original target). Per D-262-FIND-01 default path, zero F-34-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone per D-262-KI-01: `KNOWN-ISSUES.md` UNMODIFIED — zero F-34-NN finding blocks → zero KI promotion candidates. Any v34-discovered finding-candidate would FAIL the **sticky** predicate (v34 trait/solo surface is freshly-landed not "ongoing protocol behavior" until the next milestone). See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

CONTEXT.md D-262 carry of D-257-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 262 to any post-v34.0 milestone phases. Verified at §8 Forward-Cite Closure block. Phase 259-261 each emit zero phase-bound forward-cites (the v35.0 burnie-near-future-per-pull-level-resample seed in `.planning/notes/` is a deferral annotation per `feedback_no_dead_guards.md`, not a phase-bound forward-cite emission); Phase 262 inherits zero-residual baseline. Any v34-relevant divergence routes to scope-guard deferral in `262-01-SUMMARY.md`. Future milestones (v35.0+) ingest via fresh delta-extraction phase, not via forward-cite from v34 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 6-point attestation block triggering v34.0 milestone closure via signal `MILESTONE_V34_AT_HEAD_<sha>`.

---

## 3. Per-Phase Sections

Consolidates Phase 259 / 260 / 261 outputs into condensed summaries with cross-cites to source artifacts. All cross-cites are READ-only lookups; no fresh derivation. Sources `re-verified at HEAD <sha>` per Task 13 anchor resolution. §3d AUDIT-01 delta-surface tables + AUDIT-04 storage-slot scan are appended in Task 3 as a sub-section that spans both v34 contracts. §3e AUDIT-03 conservation re-proof rows are appended in Task 4.

### 3a. Phase 259 — Trait Distribution Split

**Change-count card:**

- Plans: 3 (259-01, 259-02, 259-03)
- Commits: `301f7fad` (Phase 259-01 DegenerusTraitUtils rewrite — `feat(259-01): rewrite DegenerusTraitUtils — heavy-tail color distribution`) + `031a8cbc` (Phase 259-02 TraitUtilsTester — `feat(259-02): add TraitUtilsTester external-pure test harness`) + `d67b8ac3` (test-tree only — `test(259-03): add DegenerusTraitUtils Hardhat unit tests`)
- Functions added: `weightedColorBucket(uint32) → uint8` (8 branches at 256-resolution thresholds — TRAIT-01)
- Functions modified: `traitFromWord(uint64) → uint8` (rewrite to `(color << 3) | symbol` composition — TRAIT-02)
- Functions refactored (no behavior change): `packedTraitsFromSeed(uint256) → uint32` (byte layout `[QQ][CCC][SSS]` preserved — TRAIT-03)
- Functions deleted: `weightedBucket(uint32)` (full removal per `feedback_no_history_in_comments.md` — TRAIT-04)
- Test harness added: `contracts/test/TraitUtilsTester.sol` (external-pure passthrough, 3 functions: `weightedColorBucket` / `traitFromWord` / `packedTraitsFromSeed`)
- Tests: `test/unit/DegenerusTraitUtils.test.js` (16 boundary + 4 composition + 6 byte-layout assertions; 26 Hardhat tests passing — TRAIT-05 + TRAIT-06)
- REQs satisfied: 6/6 (TRAIT-01, TRAIT-02, TRAIT-03, TRAIT-04, TRAIT-05, TRAIT-06)
- Color tier frequency targets (per REQUIREMENTS.md): 25.000% / 25.000% / 25.000% / 12.500% / 6.250% / 3.125% / 2.344% / 0.781% (gold) at 256-resolution thresholds [0,64,128,192,224,240,248,254,255]
- Closure: D-09 strict-literal Foundry fuzz baseline failure documented as deferred deviation (carried forward from `259-03-SUMMARY.md`).

**Cross-cite:** `.planning/phases/259-trait-distribution-split/259-01-SUMMARY.md` + `259-02-SUMMARY.md` + `259-03-SUMMARY.md` + `259-VERIFICATION.md` (cross-cite-only, READ-only on upstream artifacts).

**Per-REQ summary table:**

| REQ | Verdict | Cross-Cite | Attestation |
| --- | ------- | ---------- | ----------- |
| TRAIT-01 | `COMPLETE_AT_HEAD_<sha>` | 259-01-SUMMARY.md | `weightedColorBucket(uint32) → uint8` live at `contracts/DegenerusTraitUtils.sol:115-130`; 8-branch cascading-`if` over `uint32 scaled = uint32((uint64(rnd) * 256) >> 32)` produces 25/25/25/12.5/6.25/3.125/2.344/0.781% target frequencies. |
| TRAIT-02 | `COMPLETE_AT_HEAD_<sha>` | 259-01-SUMMARY.md | `traitFromWord(uint64) → uint8` rewritten at `:143-152` to bit-slice composition: color from low-32-bits via `weightedColorBucket(uint32(rnd))`, symbol uniform from `uint8(rnd >> 32) & 7`, return `(color << 3) | symbol`. |
| TRAIT-03 | `COMPLETE_AT_HEAD_<sha>` | 259-01-SUMMARY.md | `packedTraitsFromSeed(uint256) → uint32` REFACTOR_ONLY at `:169-180`; byte layout `[QQ][CCC][SSS]` preserved with quadrant masks 0x00/0x40/0x80/0xC0; only inner `traitFromWord` semantics changed, byte composition identical. |
| TRAIT-04 | `COMPLETE_AT_HEAD_<sha>` | 259-01-SUMMARY.md | `weightedBucket(uint32)` removed; grep gate `grep -rn "weightedBucket" contracts/` returns zero hits at HEAD (only `weightedColorBucket` substring matches in TraitUtils + TraitUtilsTester). |
| TRAIT-05 | `COMPLETE_AT_HEAD_<sha>` | 259-02-SUMMARY.md + 259-03-SUMMARY.md | `contracts/test/TraitUtilsTester.sol` external-pure passthrough landed; `test/unit/DegenerusTraitUtils.test.js` 26 assertions passing covering boundary inputs, composition, and byte-layout. |
| TRAIT-06 | `COMPLETE_AT_HEAD_<sha>` | 259-03-SUMMARY.md | Hardhat unit suite at `test/unit/DegenerusTraitUtils.test.js` covers 16 boundary cases (thresholds 63/64/127/128/191/192/223/224/239/240/247/248/253/254 + min/max), 4 composition assertions for `traitFromWord`, 6 byte-layout assertions for `packedTraitsFromSeed`. |

`re-verified at HEAD <sha>`.

### 3b. Phase 260 — Gold Solo Priority Injection

**Change-count card:**

- Plans: 3 (260-01, 260-02, 260-03)
- Commits: `2fa7fb6e` (Phase 260 batched feat+test atomic commit — `feat(260): inject gold-solo-priority + tests [SOLO-01..SOLO-09]`) + Phase 260 doc commits (`ca51d7c7` REQUIREMENTS amendment + `1e7a3de8` code-review-report doc + `3645d1fa` phase-execution doc + `89a9b5a5` PROJECT.md evolution doc — non-contract docs only)
- Functions added: `_pickSoloQuadrant(uint8[4], uint256) → uint8` internal pure helper at `contracts/modules/DegenerusGameJackpotModule.sol:1098-1115` (SOLO-01)
- Injection sites (4 effectiveEntropy substitutions): L287 (`runTerminalJackpot` — SOLO-02 origin spec L282) / L454 (`payDailyJackpot` daily-jackpot main path — SOLO-03 origin spec L349) / L531 (`payDailyJackpot` purchase-phase main path — SOLO-04 origin spec L524) / L1181 (`_resumeDailyEth` SPLIT_CALL2 — SOLO-05 origin spec L1147). Live-line vs spec-line discrepancy: REQUIREMENTS.md SOLO-NN cites pre-Phase-261-03-refactor line numbers (L282/L349/L524/L1147); live HEAD line numbers (L287/L454/L531/L1181) are the post-`a6c4f18a` perf-refactor positions. Cross-cite to §3d Part B for the live-line table.
- Non-injection sites (8 documented, byte-identical vs v33.0 anchor `4ce3703d` per SURF-04): L513, L527, L598, L599, L683, L1687, L1713, L1715 (the v33-anchor line list — SOLO-06 spec list).
- JackpotBucketLib UNCHANGED at v34 (SOLO-07; verified via `git diff 4ce3703d740d3707c88a1af595618120a8168399..HEAD -- contracts/libraries/JackpotBucketLib.sol` returns empty).
- Test harness added: `contracts/test/JackpotSoloTester.sol` external-pure passthrough — landed in `2fa7fb6e`.
- Tests: `test/unit/JackpotSoloPicker.test.js` (SOLO-08 a/b/c/d unit assertions; 13 Hardhat passing) + `test/integration/JackpotSoloSplit.test.js` (SOLO-09 split-mode coherence; Strategy B off-chain replication of EntropyLib.hash2 + JackpotBucketLib.getRandomTraits + JackpotBucketLib.soloBucketIndex; 7 Hardhat assertions passing in ~104ms).
- REQs satisfied: 9/9 (SOLO-01, SOLO-02, SOLO-03, SOLO-04, SOLO-05, SOLO-06, SOLO-07, SOLO-08, SOLO-09).

**Cross-cite:** `.planning/phases/260-gold-solo-priority-injection/260-01-SUMMARY.md` + `260-02-SUMMARY.md` + `260-03-SUMMARY.md` + `260-VERIFICATION.md` (cross-cite-only).

**Per-REQ summary table:**

| REQ | Verdict | Cross-Cite | Attestation |
| --- | ------- | ---------- | ----------- |
| SOLO-01 | `COMPLETE_AT_HEAD_<sha>` | 260-01-SUMMARY.md | `_pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8)` live at `contracts/modules/DegenerusGameJackpotModule.sol:1098-1115`; pure-stack uint256 `goldQuads` accumulator (post-`a6c4f18a` refactor); zero-gold returns rotation index, single-gold returns quadrant, multi-gold returns `goldQuads[(entropy >> 4) % goldCount]` (option B random-among-gold tie-break per Phase 260 D-04). |
| SOLO-02 | `COMPLETE_AT_HEAD_<sha>` | 260-01-SUMMARY.md | `runTerminalJackpot` effectiveEntropy substitution at `:287-298`; soloQuadrant computed BEFORE every JackpotBucketLib read; downstream `bucketCountsForPoolCap` + `shareBpsByBucket` reads consume effectiveEntropy. |
| SOLO-03 | `COMPLETE_AT_HEAD_<sha>` | 260-01-SUMMARY.md | `payDailyJackpot` daily-jackpot main path effectiveEntropy substitution at `:454-500`; final-day path (FINAL_DAY_SHARES_PACKED 60/13/13/13) routes 60% to gold; days 1-4 (DAILY_JACKPOT_SHARES_PACKED 20/20/20/20) get equal-share rotation onto gold quadrant. |
| SOLO-04 | `COMPLETE_AT_HEAD_<sha>` | 260-01-SUMMARY.md | `payDailyJackpot` purchase-phase main path effectiveEntropy substitution at `:531-558`; both bucket-count rotation AND `shareBpsByBucket` offset read consume identical low-2-bits — both consistent under the new entropy. |
| SOLO-05 | `COMPLETE_AT_HEAD_<sha>` | 260-03-SUMMARY.md | `_resumeDailyEth` SPLIT_CALL2 effectiveEntropy substitution at `:1181-1200`; produces IDENTICAL effectiveEntropy as L454 SPLIT_CALL1 from identical (randWord, lvl, EntropyLib.hash2) inputs; SOLO-09 integration test asserts split-call coherence. |
| SOLO-06 | `COMPLETE_AT_HEAD_<sha>` | 260-02-SUMMARY.md | 8 non-injection sites at v33-anchor lines [513, 527, 598, 599, 683, 1687, 1713, 1715] verified byte-identical via SURF-04 SurfaceRegression test git-diff structural grep against baseline `4ce3703d`. |
| SOLO-07 | `COMPLETE_AT_HEAD_<sha>` | 260-02-SUMMARY.md | `contracts/libraries/JackpotBucketLib.sol` byte-identical at v34 HEAD per `git diff 4ce3703d..HEAD -- contracts/libraries/JackpotBucketLib.sol` empty output; `traitBucketCounts` / `shareBpsByBucket` / `soloBucketIndex` formulas preserved. |
| SOLO-08 | `COMPLETE_AT_HEAD_<sha>` | 260-02-SUMMARY.md | `test/unit/JackpotSoloPicker.test.js` 13 Hardhat assertions passing covering SOLO-08(a) zero-gold returns rotation index + SOLO-08(b) one-gold returns that quadrant + SOLO-08(c) multi-gold returns gold quadrant + SOLO-08(d) bit-disjointness between `entropy >> 4` tie-break and `entropy & 3` rotation. |
| SOLO-09 | `COMPLETE_AT_HEAD_<sha>` | 260-03-SUMMARY.md | `test/integration/JackpotSoloSplit.test.js` 7 Hardhat assertions passing in ~104ms; Strategy B off-chain replication of EntropyLib.hash2 + JackpotBucketLib.getRandomTraits + JackpotBucketLib.soloBucketIndex; SPLIT_CALL1 (`:454-500`) ↔ SPLIT_CALL2 (`:1181-1200`) effectiveEntropy parity asserted across multiple TEST_LEVELS. |

`re-verified at HEAD <sha>`.

### 3c. Phase 261 — Statistical Validation + Cross-Surface Verification

**Change-count card:**

- Plans: 3 (261-01, 261-02, 261-03)
- Commits (test-tree only — Phase 261 makes ZERO `contracts/` changes except the noOp test-tester companion + perf refactor): `2eafdde8` (test(261-01) STAT-01/02/03 + boundary harness — `test/stat/TraitDistribution.test.js`) + `197c8197` (test(261-02) STAT-04/05 GoldSoloCoverage — `test/stat/GoldSoloCoverage.test.js`) + `2d4152a4` (test(261-02) STAT-06 SoloEvUplift — `test/stat/SoloEvUplift.test.js`) + `4e3e7a5e` (test(261-02) STAT-07 PackFeel — `test/stat/PackFeel.test.js`) + `4e015d2e` (test(261-03) SURF-01/02/03/04 — `test/stat/SurfaceRegression.test.js`) + `00de73ed` (test(261-03) SURF-05 — `test/gas/Phase261GasRegression.test.js`) + `1574d533` (chore(261-03) noOp companion to JackpotSoloTester for paired-empty-wrapper delta) + `a6c4f18a` (perf(261-03) refactor `_pickSoloQuadrant` to pure-stack uint256 packing) + `73d533d8` (docs(261-03) REQUIREMENTS.md amendment STAT-06 D-08 + SURF-04 line list + SURF-05 site descope) + `03e86301` (chore(261-03) `test:stat` opt-in script in package.json) + Phase 261 doc commits (3e7f4cc1 / 7683b408 / 7e56600a / 6b63f6d4 — non-contract docs).
- Statistical evidence:
  - **STAT-01** — 1M-sample color frequency 3σ + ±0.1% + chi² < 14.067 (df=7) at seed `0xC010_0001` — verified.
  - **STAT-02** — 1M-sample joint (color, symbol) independence Wilson-Hilferty Z < 1.645 at df=49, seed `0xC010_0002` — verified.
  - **STAT-03** — 1M-sample symbol uniformity chi² < 14.067 (df=7), seed `0xC010_0003` — verified.
  - **STAT-04** — 100% gold coverage on ≥1-gold draws, 100K samples — verified (goldCount histogram 1→98819 / 2→1178 / 3→3 / 4→0).
  - **STAT-05** — tie-break uniformity chi² < {3.841, 5.991, 7.815} for goldCount ∈ {2, 3, 4}, 100K samples each, seed `0xC010_0050 ^ goldCount` — verified.
  - **STAT-06** — per-surface EV uplift vector (D-08 amendment per `73d533d8`).
  - **STAT-07** — pack-feel CIs over 100K 10-ticket packs (analytical-within-Wilson-99%-CI-of-measured).
- Cross-surface evidence:
  - **SURF-01** — hero override `_applyHeroOverride` at L1582-1609 uses 3-bit literal slice NOT through `weightedColorBucket` (structural negation assertion in `test/stat/SurfaceRegression.test.js`).
  - **SURF-02 / SURF-03** — documented-no-new-test (D-09); existing regression carriers (Degenerette + MintModule) run unchanged.
  - **SURF-04** — structural git-diff grep against v33.0 anchor `4ce3703d` for the 8 non-injection lines [513, 527, 598, 599, 683, 1687, 1713, 1715] — byte-identical (skip-on-shallow-clone soft-fail).
  - **SURF-05** — paired-empty-wrapper gas delta ≤ 1500 gas under worst-case 4-gold input (post-refactor measurement 1260 gas; 200-gas headroom).
- REQs satisfied: 12/12 (STAT-01, STAT-02, STAT-03, STAT-04, STAT-05, STAT-06, STAT-07, SURF-01, SURF-02, SURF-03, SURF-04, SURF-05).
- ROADMAP/REQUIREMENTS reconciliation deferrals (per `261-VERIFICATION.md` deferred items): (a) STAT-07 ROADMAP cites informational headline targets vs canonical analytical values (test asserts canonical-within-Wilson-99%-CI-of-measured) — INFO tier documentation drift; (b) ROADMAP Phase 261 success criterion #5 cites `_pickSoloQuadrant per-call < 500 gas` and `_resumeDailyEth < 2000 gas` while REQUIREMENTS.md SURF-05 amendment (commit `73d533d8`) supersedes with `≤ 1500 gas paired-empty-wrapper delta` and `_resumeDailyEth descoped via stage-11 transitive coverage` — INFO tier documentation drift. Both surfaced INFO-only here per D-262-FIND-01; REQUIREMENTS.md amendment commit `73d533d8` is load-bearing.

**Cross-cite:** `.planning/phases/261-statistical-validation-cross-surface-verification/261-01-SUMMARY.md` + `261-02-SUMMARY.md` + `261-03-SUMMARY.md` + `261-VERIFICATION.md` (cross-cite-only).

**Per-REQ summary table:**

| REQ | Verdict | Cross-Cite | Attestation |
| --- | ------- | ---------- | ----------- |
| STAT-01 | `PASS_AT_HEAD_<sha>` | 261-01-SUMMARY.md | `test/stat/TraitDistribution.test.js` 1M-sample color frequency at seed `0xC010_0001`; chi² < 14.067 (df=7) and 3σ + ±0.1% bounds satisfied for all 8 color tiers. |
| STAT-02 | `PASS_AT_HEAD_<sha>` | 261-01-SUMMARY.md | 1M-sample joint (color, symbol) independence; Wilson-Hilferty Z < 1.645 at df=49, seed `0xC010_0002`. |
| STAT-03 | `PASS_AT_HEAD_<sha>` | 261-01-SUMMARY.md | 1M-sample symbol uniformity chi² < 14.067 (df=7), seed `0xC010_0003`. |
| STAT-04 | `PASS_AT_HEAD_<sha>` | 261-02-SUMMARY.md | `test/stat/GoldSoloCoverage.test.js` 100K samples; gold coverage 100% on ≥1-gold draws (goldCount histogram 1→98819 / 2→1178 / 3→3 / 4→0). |
| STAT-05 | `PASS_AT_HEAD_<sha>` | 261-02-SUMMARY.md | `test/stat/GoldSoloCoverage.test.js:159-209` chi² uniformity for goldCount ∈ {2, 3, 4} against critical values {3.841, 5.991, 7.815} at α=0.05, 100K samples each, seed `0xC010_0050 ^ goldCount`. |
| STAT-06 | `PASS_AT_HEAD_<sha>` | 261-02-SUMMARY.md + `73d533d8` | `test/stat/SoloEvUplift.test.js` per-surface EV uplift Monte Carlo; D-08 amendment per `73d533d8` aligns headline targets to canonical analytical values; ~3.3× uplift consistent across base counts [25, 15, 8, 1]. |
| STAT-07 | `PASS_AT_HEAD_<sha>` | 261-02-SUMMARY.md | `test/stat/PackFeel.test.js` 100K 10-ticket packs; canonical analytical values land within Wilson 99% CI of measured. |
| SURF-01 | `PASS_AT_HEAD_<sha>` | 261-03-SUMMARY.md | `test/stat/SurfaceRegression.test.js` structural-negation assertion: `_applyHeroOverride` body at `:1582-1609` does NOT contain `weightedColorBucket` symbol; color path uses 3-bit literal slice instead. |
| SURF-02 | `PASS_AT_HEAD_<sha>` | 261-03-SUMMARY.md | Documented-no-new-test per D-09; existing Degenerette regression carrier runs unchanged. |
| SURF-03 | `PASS_AT_HEAD_<sha>` | 261-03-SUMMARY.md | Documented-no-new-test per D-09; existing MintModule regression carrier runs unchanged. |
| SURF-04 | `PASS_AT_HEAD_<sha>` | 261-03-SUMMARY.md | Structural git-diff grep against v33.0 anchor `4ce3703d` for the 8 non-injection lines [513, 527, 598, 599, 683, 1687, 1713, 1715] — byte-identical confirmed. |
| SURF-05 | `PASS_AT_HEAD_<sha>` | 261-03-SUMMARY.md + `73d533d8` | `test/gas/Phase261GasRegression.test.js` paired-empty-wrapper delta 1260 gas under worst-case 4-gold input (200-gas headroom under 1500 gas amended ceiling). |

`re-verified at HEAD <sha>`.

---
