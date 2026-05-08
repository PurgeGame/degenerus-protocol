# Requirements: Degenerus Protocol — Trait Rarity Rework + Gold Solo Priority (v34.0)

**Defined:** 2026-05-08
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

**Goal:** Convert the trait system from its legacy flat distribution (designed for the original PurgeGame's strategic-trait gameplay) into a heavy-tail rarity system suited to a pure-chance jackpot product, and add a gold-trait priority rule so legendary winning traits always claim the 60% solo bucket at every ETH-distribution site.

**Audit baseline:** v33.0 contract HEAD `4ce3703d740d3707c88a1af595618120a8168399` (closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` supersedes `MILESTONE_V33_AT_HEAD_dcb70941`).

**Mixed-shape milestone:** Modifies `contracts/DegenerusTraitUtils.sol` + `contracts/modules/DegenerusGameJackpotModule.sol`; adds Hardhat statistical-validation tests under `test/stat/` (or equivalent); produces a delta-audit deliverable `audit/FINDINGS-v34.0.md`.

**Write policy:** READ-only LIFTED for v34.0 (consistent with v32.0/v33.0 audit posture). All `contracts/` + `test/` changes require explicit per-commit user approval per `feedback_no_contract_commits.md`. Phases that batch multiple contract edits use the batched approval pattern per `feedback_batch_contract_approval.md`.

**Deliverable:** `audit/FINDINGS-v34.0.md` (single canonical 9-section deliverable, FINAL READ-only at HEAD, with regression appendix re-verifying v33.0 + v32.0 closure signals non-widening).

**Accepted RNG exceptions** (re-verify scope at v34):

1. EXC-01 — Non-VRF entropy for affiliate winner roll (KNOWN-ISSUES.md).
2. EXC-02 — Gameover prevrandao fallback (`_getHistoricalRngFallback`; KNOWN-ISSUES.md).
3. EXC-03 — Gameover RNG substitution for mid-cycle write-buffer tickets / F-29-04 class (KNOWN-ISSUES.md).
4. EXC-04 — EntropyLib XOR-shift PRNG (KNOWN-ISSUES.md). **Potentially in scope** — `_pickSoloQuadrant` tie-break uses `entropy >> 4` bits which may be XOR-shift-derived in some upstream paths; verify entropy-quality envelope.

**Reference artifacts (v34 design constants):**

- Bit layout: `[QQ][CCC][SSS]` — quadrant 2 bits, color 3 bits, symbol 3 bits (UNCHANGED)
- Bucket share BPS UNCHANGED: `[6000, 1333, 1333, 1334]` (final-day) / `[2000, 2000, 2000, 2000]` (daily/purchase)
- Bucket counts UNCHANGED: `[25, 15, 8, 1]` (daily) / `[20, 12, 6, 1]` (purchase) rotated by entropy
- Hero override: writes `(quadrant << 6) | (color << 3) | symbol` — color from RNG, symbol from highest-wagered (q,s) pair (UNCHANGED behavior; new color distribution applies)

**Color tier frequencies (target):**

| Color | Threshold range (256-bucket) | Frequency | Per-trait freq (× flat 12.5% symbol) |
|-------|------------------------------|-----------|--------------------------------------|
| 0     | `[0, 64)`                    | 25.000%   | 3.125% (1-in-32)                     |
| 1     | `[64, 128)`                  | 25.000%   | 3.125%                               |
| 2     | `[128, 192)`                 | 25.000%   | 3.125%                               |
| 3     | `[192, 224)`                 | 12.500%   | 1.5625%                              |
| 4     | `[224, 240)`                 | 6.250%    | 0.781%                               |
| 5     | `[240, 248)`                 | 3.125%    | 0.391%                               |
| 6     | `[248, 254)`                 | 2.344%    | 0.293%                               |
| 7     | `[254, 256)`                 | 0.781%    | **0.0977% (1-in-1024) — gold tier**  |

**Rarity ratio:** 32× between rarest color (7, 0.781%) and most-common color (0/1/2, 25.000%).

---

## v34.0 Requirements

### TRAIT — Color/Symbol Distribution Split (DegenerusTraitUtils.sol)

- [ ] **TRAIT-01**: `weightedBucket(uint32)` replaced by `weightedColorBucket(uint32 rnd) internal pure returns (uint8)` — 256-resolution thresholds via `uint32 scaled = uint32((uint64(rnd) * 256) >> 32)`, 8 branches matching the color-tier table (`< 64 → 0`, `< 128 → 1`, `< 192 → 2`, `< 224 → 3`, `< 240 → 4`, `< 248 → 5`, `< 254 → 6`, else `7`). Function is deleted, not commented-out, per `feedback_no_history_in_comments.md`.
- [ ] **TRAIT-02**: `traitFromWord(uint64 rnd) internal pure returns (uint8)` rewritten — `color = weightedColorBucket(uint32(rnd))`, `symbol = uint8(rnd >> 32) & 7`, return `(color << 3) | symbol`. Replaces the previous two-`weightedBucket`-call composition.
- [ ] **TRAIT-03**: `packedTraitsFromSeed(uint256 rand)` and the `[QQ][CCC][SSS]` byte layout PRESERVED — quadrant tagging (`| 64`, `| 128`, `| 192`) unchanged; quadrant 2 bits, color 3 bits, symbol 3 bits.
- [ ] **TRAIT-04**: No callers of the removed `weightedBucket` remain anywhere in `contracts/` (grep-reproducible: `grep -rn "weightedBucket" contracts/`). The function is fully removed; if any external caller is discovered (e.g. test file, off-chain script), classify and either refactor to call `weightedColorBucket` or document why preserving the old behavior is correct.
- [ ] **TRAIT-05**: Unit tests for `weightedColorBucket` — boundary cases at every threshold (`scaled = 0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255`) return the expected color tier. Covers all 8 buckets.
- [ ] **TRAIT-06**: Unit tests for `traitFromWord` — verify `[CCC][SSS]` composition: bottom 32 bits drive color via `weightedColorBucket`, top 32 bits drive symbol via `& 7`. Verify byte layout unchanged for `packedTraitsFromSeed` (quadrant flags `0/64/128/192`).

### SOLO — Gold-Solo Priority (DegenerusGameJackpotModule.sol)

- [ ] **SOLO-01**: New private helper `_pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) private pure returns (uint8)` added to `DegenerusGameJackpotModule.sol`. Logic: count quadrants with color==7 (`(traits[i] >> 3) & 7 == 7`); if count > 0, return uniformly-random gold quadrant via `goldQuads[uint8((entropy >> 4) & 3) % goldCount]`; else return existing rotation index `uint8((3 - (entropy & 3)) & 3)`. Tie-break decision: random-among-gold (option B) — preserves quadrant symmetry, no permanent bias toward q0.
- [ ] **SOLO-02**: Injected at line 282 (`runTerminalJackpot`) — solo quadrant computed BEFORE `JackpotBucketLib.shareBpsByBucket`/`bucketCountsForPoolCap` calls; substitute `effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` for downstream rotation. Pass `effectiveEntropy` to all bucket-count and share-rotation reads.
- [ ] **SOLO-03**: Injected at line 349 (`payDailyJackpot` jackpot-phase main path) — same effectiveEntropy substitution before `_processDailyEth`. Final-day path (FINAL_DAY_SHARES_PACKED 60/13/13/13) gets full 60% routing to gold; days 1-4 (DAILY_JACKPOT_SHARES_PACKED 20/20/20/20 with [25,15,8,1] rotation) get 20%-to-1-winner concentration on gold quadrant.
- [ ] **SOLO-04**: Injected at line 524 (`payDailyJackpot` purchase-phase main path) — effectiveEntropy substitution before `_executeJackpot` → `_runJackpotEthFlow`. Both bucket-count rotation (line 1110 `uint8(jp.entropy & 3)`) AND `shareBpsByBucket` offset (line 1095 `uint8(jp.entropy & 3)`) read identical low-2-bits — both consistent under the new entropy.
- [ ] **SOLO-05**: Injected at line 1147 (`_resumeDailyEth` call 2 of two-call split) — produces IDENTICAL effectiveEntropy as line 349 (same `randWord`, same `lvl`, same `EntropyLib.hash2` inputs, same trait roll, same `_pickSoloQuadrant` output). Critical: `resumeEthPool` written by call 1 is consumed by call 2; the bucket structure (`[25,15,8,1]` rotation, share-bps rotation) MUST be identical or split-mode SPLIT_CALL2 reads stale assumptions. Verified via test that exercises the two-call path with golden traits in the winning set.
- [ ] **SOLO-06**: NO injection at lines 513, 527, 598, 599, 683, 1687, 1713, 1715 — verified to have no solo bucket structure and intentionally not modified. Each non-injection site documented with rationale: 513/527/1713/1715 emit-only `DailyWinningTraits`; 598/599/1687 use `_computeBucketCounts` equal-active-bucket split via `_distributeTicketJackpot` or `_awardDailyCoinToTraitWinners`; 683 uses literal `[25,25,25,25]` flat distribution in `_runEarlyBirdLootboxJackpot`.
- [ ] **SOLO-07**: `JackpotBucketLib` UNCHANGED — gold-priority works exclusively via the low-2-bits-of-entropy convention; existing rotation logic (`traitBucketCounts`, `soloBucketIndex`, `shareBpsByBucket`, `rotatedShareBps`) untouched. `soloBucketIndex(entropy) = (3 - (entropy & 3)) & 3` formula preserved.
- [ ] **SOLO-08**: Unit tests for `_pickSoloQuadrant` — (a) zero gold traits → returns `(3 - (entropy & 3)) & 3` matching old behavior; (b) one gold trait → always returns that quadrant index regardless of `entropy >> 4`; (c) two/three/four gold traits → uniform distribution across gold quadrants verified across 100K random entropies (chi-squared p > 0.05); (d) tie-break is `entropy >> 4 & 3 mod goldCount` (not `entropy & 3`) — verify the entropy bit-shift is correct so gold-priority does not collide with the bucket-rotation bits at `entropy & 3`.
- [ ] **SOLO-09**: Integration test exercising the line-349 → line-1147 split: construct a daily jackpot with at least one gold-color winning trait, drive the two-call SPLIT_CALL1 → SPLIT_CALL2 path, verify both calls compute identical `effectiveEntropy` and pay the correct bucket structure (solo bucket → gold quadrant in both calls).

### STAT — Statistical Validation (Monte Carlo + Chi-Squared)

- [ ] **STAT-01**: 1M-sample empirical frequency test for `weightedColorBucket` — every color bucket within 3-sigma binomial bounds of expected frequency. Targets: 25.000% / 25.000% / 25.000% / 12.500% / 6.250% / 3.125% / 2.344% / 0.781%, tolerance 0.1% per success criterion #1.
- [ ] **STAT-02**: Color/symbol independence chi-squared test — over 1M samples, joint (color, symbol) distribution does not reject the null that the two axes are statistically independent (p > 0.05). Confirms the bit-slice composition `(color << 3) | symbol` does not introduce coupling.
- [ ] **STAT-03**: Symbol uniformity chi-squared — symbol distribution alone is uniform across 8 values (chi-squared p > 0.05 over 1M samples per success criterion #2).
- [ ] **STAT-04**: Gold-solo coverage simulation — over 100K simulated draws where ANY of the 4 winning traits has color 7, the solo bucket lands on a color-7 quadrant in 100% of cases (success criterion #3). Test uses `_pickSoloQuadrant` directly with constructed trait inputs.
- [ ] **STAT-05**: Gold-solo tie-break uniformity — across 100K simulated multi-gold draws (≥2 winning traits with color 7), solo bucket assignment among gold quadrants is uniform (chi-squared p > 0.05 per success criterion #4).
- [ ] **STAT-06**: Solo-EV uplift simulation — gold-trait holders see ~3.3× solo-bucket EV uplift vs uniform-rotation baseline across 100K random-trait jackpot draws. Simulation uses realistic player-trait distributions (Monte Carlo over the new color distribution) and the production share BPS / bucket count tables.
- [ ] **STAT-07**: Pack-feel CIs — over 10-ticket packs (40 quadrant rolls each): ≥1 notable-tier (color≥3) trait in 99.5% of packs; ≥1 rare-tier (color≥4) in 92.3%; ≥1 epic-tier (color≥5) in 71.7%; ≥1 legendary (color==7) in 27.0%. All targets within Monte Carlo 99% confidence intervals over ≥100K sampled packs.

### SURF — Cross-Surface Verification

- [ ] **SURF-01**: Hero override (`_applyHeroOverride`) — writes `(quadrant << 6) | (color << 3) | symbol` where color is RNG-derived (3-bit slice from random word) and symbol is `dailyHeroWagers`-derived. Color writeback path preserved with new distribution; existing hero override tests pass unchanged. NOTE: hero override writes color using a 3-bit literal slice, NOT through `weightedColorBucket`, so hero color is uniform 12.5% per value — intentional (override is a special-cased manual color injection).
- [ ] **SURF-02**: Deity-pass virtual entries — `floor(2% of bucket tickets)` per symbol now operates on uniform 12.5% symbol distribution; verify `_distributeTicketsToBucket` / `_computeBucketCounts` paths produce expected virtual-entry counts and no deity-symbol-specific edge cases break.
- [ ] **SURF-03**: Degenerette match payouts — color-and-symbol matching against player tickets (`DegenerusGameDegenetteModule`) unaffected by byte-layout-preserving changes; existing Degenerette test suite passes without modification.
- [ ] **SURF-04**: Bonus jackpot draws — `_rollWinningTraits(_, true)` calls (lines 513, 527, 599, 683, 1687, 1713, 1715) verified unaffected by the gold-solo injection. Each downstream consumer documented as either event-emit-only or equal-split bucket distribution; no change in behavior.
- [ ] **SURF-05**: Gas regression — pre/post-change comparison for `weightedColorBucket(uint32) → uint8` vs prior `weightedBucket(uint32) → uint8`; per-trait-roll gas delta within ±100 gas budget. `_pickSoloQuadrant` per-call gas overhead < 500 gas. Total delta on `runTerminalJackpot`/`payDailyJackpot`/`_resumeDailyEth` < 2000 gas per success-criterion preservation. Memory feedback `feedback_gas_worst_case.md` — derive theoretical worst case (max gold count = 4) FIRST, then test.

### AUDIT — Delta Audit + Findings Deliverable

- [ ] **AUDIT-01**: `audit/FINDINGS-v34.0.md` published as FINAL READ-only at HEAD — 9-section shape consistent with v32.0 + v33.0 deliverables (executive summary, per-phase sections, F-34-NN finding blocks under D-08 5-bucket severity rubric, regression appendix, KI gating walk, closure attestation). Every changed function / state variable / event in `DegenerusTraitUtils.sol` + `DegenerusGameJackpotModule.sol` vs v33.0 baseline `4ce3703d` enumerated with hunk-level evidence and classified as {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}. Every downstream caller of changed functions inventoried across `contracts/` (grep-reproducible commands documented).
- [ ] **AUDIT-02**: Adversarial sweep — color/symbol entropy independence proven; gold-solo routing cannot be gamed (entropy bits driving tie-break are derived from VRF, not player-controllable); no new attack surface introduced by the gold-priority injection. Specific surfaces verdicted SAFE or FINDING_CANDIDATE: (a) entropy-bit-collision between gold tie-break (`entropy >> 4`) and bucket rotation (`entropy & 3`); (b) `_pickSoloQuadrant` deterministic for identical inputs across line 349 ↔ 1147 split; (c) gold trait population manipulation via player ticket purchases (player cannot bias the VRF roll); (d) heuristic gas-griefing of `_pickSoloQuadrant` (4-iteration loop, constant cost); (e) overflow / signed-vs-unsigned in entropy XOR mask `~uint256(3)`.
- [ ] **AUDIT-03**: Conservation invariants — solvency (`claimablePool ≤ ETH balance + stETH balance`) PRESERVED across the trait/solo changes (success criterion #6). Pool-balance algebra unchanged because share BPS and bucket counts unchanged; only the *which-bucket-is-solo* assignment changes, and total ETH distributed per call is bucket-share-sum × pool, which is invariant under bucket index rotation.
- [ ] **AUDIT-04**: NO new external state, NO new admin functions, NO new upgrade hooks introduced (success criterion #7). Verified via grep — diff between v33.0 baseline `4ce3703d` and v34.0 HEAD shows zero new public/external mutation entry points and zero new storage slots in `GameStorage`, `DegenerusGameJackpotModule`, or `DegenerusTraitUtils`.
- [ ] **AUDIT-05**: Closure signal `MILESTONE_V34_AT_HEAD_<sha>` emitted in §9c. v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` re-verified non-widening in regression appendix.

### REG — Prior-Finding Regression

- [ ] **REG-01**: Re-verify v33.0 closure signal `MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399` non-widening — charity governance (GNRUS.sol) not touched in v34.0; FIX-01 (pickCharity flush-after-payout reorder) and FIX-02 (`lastWinningRecipient` + `PreviousWinnerNotVotable()` vote-guard) invariants preserved. Verdict PASS / REGRESSED / SUPERSEDED.
- [ ] **REG-02**: Re-verify v32.0 closure signal `MILESTONE_V32_AT_HEAD_acd88512` non-widening — backfill guard (L1174 `rngWordByDay[idx + 1] == 0` sentinel), purchaseLevel underflow guard (L173 `!inJackpot && !lastPurchaseDay && !rngLockedFlag` turbo-block), GameStorage `_livenessTriggered` body all not touched in v34.0. Verdict PASS / REGRESSED / SUPERSEDED.
- [ ] **REG-03**: KI envelopes EXC-01..04 RE_VERIFIED. EXC-04 (EntropyLib XOR-shift PRNG) requires extra attention — `_pickSoloQuadrant` tie-break uses `entropy >> 4` bits which may be XOR-shift-derived in some upstream paths; verify XOR-shift entropy quality is sufficient for uniform tie-break across multiple gold quadrants (chi-squared test at STAT-05 covers this empirically). Other 3 KI items (EXC-01..03) NEGATIVE-scope (no RNG touched besides `_pickSoloQuadrant` and the unchanged `_rollWinningTraits` / `traitFromWord` flow). KNOWN-ISSUES.md updated only if D-09 3-predicate gating passes (accepted-design + non-exploitable + sticky); otherwise UNMODIFIED with Non-Promotion Ledger.
- [ ] **REG-04**: Spot-check regression — re-verify any prior finding (v25 / v27 / v28 / v29 / v30 / v31 / v32 / v33) that referenced `weightedBucket`, `traitFromWord`, `packedTraitsFromSeed`, `JackpotBucketLib`, `_rollWinningTraits`, `_executeJackpot`, `_processDailyEth`, `_runJackpotEthFlow`, `runTerminalJackpot`, `payDailyJackpot`, `_resumeDailyEth`, or any solo-bucket-adjacent path. Verdicts: PASS / REGRESSED / SUPERSEDED with grep-cited evidence.

---

## Future Requirements (Deferred to Later Milestones)

- Hero override extension to color (currently color is RNG-only; could allow `dailyHeroWagers`-driven color override). Out of v34.0 scope per user spec.
- Solo-bucket cap or floor mechanisms (e.g. cap solo payout at a fraction of pool when gold rare events stack). Explicitly OUT OF SCOPE per user — variance is the product.
- Audit of post-v32.0 commits `002bde55` (presale auto-deactivate) + `2713ce61` (setDecimatorAutoRebuy removal) — carried forward from v33.0 archive.
- Re-execute Phase 257 Task 7 manual red-team with `/contract-auditor` + `/zero-day-hunter` skill-spawn enabled — required for C4A warden contest submission (carried forward from v33.0 archive).

## Out of Scope

- **UI/UX rarity treatments** (sparkle, foil, tier badges, animated reveals). Separate UI phase once on-chain math ships and tier names are locked.
- **Rarity tier names** (Common / Notable / Rare / Epic / Legendary etc.) — design decision pending; will be locked in a follow-on writing pass.
- **Whitepaper / game theory paper updates** describing the new tier structure — separate writing pass after on-chain change ships.
- **Hero override extension to color** (currently color is RNG-only; possibly a future milestone).
- **Solo-bucket cap or floor mechanisms** — explicitly decided against. Variance is the product.
- **Off-chain code that hard-codes the legacy 13.3/12.0/10.7 distribution numbers** (per user's scope #6 "Files To Audit For Hidden Coupling"). Surfaced if found, but remediation deferred to off-chain repos unless coupling breaks an on-chain invariant.
- **`weightedBucket` retention** (legacy two-call composition for symbol). Removed entirely per `feedback_no_history_in_comments.md` and `feedback_no_dead_guards.md`.

---

## Traceability

Each REQ-ID mapped to exactly one phase. 36 of 36 v34.0 requirements covered (100%).

| REQ-ID | Phase | Plan |
|--------|-------|------|
| TRAIT-01 | Phase 259 | TBD |
| TRAIT-02 | Phase 259 | TBD |
| TRAIT-03 | Phase 259 | TBD |
| TRAIT-04 | Phase 259 | TBD |
| TRAIT-05 | Phase 259 | TBD |
| TRAIT-06 | Phase 259 | TBD |
| SOLO-01 | Phase 260 | TBD |
| SOLO-02 | Phase 260 | TBD |
| SOLO-03 | Phase 260 | TBD |
| SOLO-04 | Phase 260 | TBD |
| SOLO-05 | Phase 260 | TBD |
| SOLO-06 | Phase 260 | TBD |
| SOLO-07 | Phase 260 | TBD |
| SOLO-08 | Phase 260 | TBD |
| SOLO-09 | Phase 260 | TBD |
| STAT-01 | Phase 261 | TBD |
| STAT-02 | Phase 261 | TBD |
| STAT-03 | Phase 261 | TBD |
| STAT-04 | Phase 261 | TBD |
| STAT-05 | Phase 261 | TBD |
| STAT-06 | Phase 261 | TBD |
| STAT-07 | Phase 261 | TBD |
| SURF-01 | Phase 261 | TBD |
| SURF-02 | Phase 261 | TBD |
| SURF-03 | Phase 261 | TBD |
| SURF-04 | Phase 261 | TBD |
| SURF-05 | Phase 261 | TBD |
| AUDIT-01 | Phase 262 | TBD |
| AUDIT-02 | Phase 262 | TBD |
| AUDIT-03 | Phase 262 | TBD |
| AUDIT-04 | Phase 262 | TBD |
| AUDIT-05 | Phase 262 | TBD |
| REG-01 | Phase 262 | TBD |
| REG-02 | Phase 262 | TBD |
| REG-03 | Phase 262 | TBD |
| REG-04 | Phase 262 | TBD |
