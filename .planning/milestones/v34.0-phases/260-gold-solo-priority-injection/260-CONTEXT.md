# Phase 260: Gold Solo Priority Injection - Context

**Gathered:** 2026-05-08
**Status:** Ready for planning

<domain>
## Phase Boundary

`contracts/modules/DegenerusGameJackpotModule.sol` exposes a new `_pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8)` helper that returns a uniformly-random gold-color (color==7) quadrant when any winning trait is gold (option B random-among-gold tie-break), else the existing rotation index `uint8((3 - (entropy & 3)) & 3)`. The four ETH-distribution call sites at lines 282 (`runTerminalJackpot`), 349 (`payDailyJackpot` jackpot-phase main), 524 (`payDailyJackpot` purchase-phase main), and 1147 (`_resumeDailyEth` SPLIT_CALL2) substitute `effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` BEFORE every `JackpotBucketLib.shareBpsByBucket` / `bucketCountsForPoolCap` / `_processDailyEth` / `_executeJackpot` read. The 8 documented non-injection sites (513, 527, 598, 599, 683, 1687, 1713, 1715) remain byte-identical to v33.0 baseline `4ce3703d`. `JackpotBucketLib` is UNCHANGED.

In scope:
- Add `_pickSoloQuadrant(uint8[4], uint256) internal pure returns (uint8)` helper to `DegenerusGameJackpotModule.sol`.
- Substitute `effectiveEntropy` at exactly 4 sites: lines 282 / 349 / 524 / 1147. L349 and L1147 MUST produce identical `effectiveEntropy` from identical `(randWord, lvl, traits, entropy)` inputs (split-mode SPLIT_CALL1 → SPLIT_CALL2 coherence — `resumeEthPool` written by call 1 is consumed by call 2 against the same bucket structure).
- Add `contracts/test/JackpotSoloTester.sol` (inherits `DegenerusGameJackpotModule`; `external pure` passthrough for `_pickSoloQuadrant`).
- Add Hardhat unit tests (0 / 1 / 2 / 3 / 4-gold cases + 100K-entropy uniformity sanity at goldCount ∈ {2, 3, 4}).
- Add SOLO-09 integration test exercising the L349 → L1147 SPLIT_CALL1 → SPLIT_CALL2 path with at least one gold winning trait, asserting `effectiveEntropy` parity across the two calls and correct bucket reconstruction.
- Verify the 8 non-injection sites byte-identical via `git diff` vs v33.0 baseline `4ce3703d`.

Out of scope (deferred):
- 1M-sample empirical color/symbol distribution + chi-squared independence — Phase 261.
- Gold-solo coverage simulation over 100K gold-present draws — Phase 261.
- Pack-feel CIs — Phase 261.
- Cross-surface preservation (hero override, deity-pass, Degenerette, the 8 non-injection bonus-jackpot bucket-distribution byte-identity beyond simple grep) — Phase 261.
- Gas regression vs v33.0 — Phase 261 (worst-case 4-gold theoretical derivation FIRST per `feedback_gas_worst_case.md`, then test).
- Findings consolidation — Phase 262.

</domain>

<decisions>
## Implementation Decisions

### Helper visibility & test access
- **D-01:** SOLO-01 is amended: `_pickSoloQuadrant` declared `internal pure` (not `private pure`) so a tester contract can wrap it without reimplementing the body. The substitution formula and tie-break semantics are unchanged from SOLO-01.
- **D-02:** New `contracts/test/JackpotSoloTester.sol` is `contract JackpotSoloTester is DegenerusGameJackpotModule { function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) { return _pickSoloQuadrant(traits, entropy); } }`. No constructor; storage layout is inherited but never touched in the pure call path. Same compiled bytes for `_pickSoloQuadrant` as the production module.
- **D-03:** Mirrors the Phase 259 pattern (`contracts/test/TraitUtilsTester.sol` wrapping `DegenerusTraitUtils` `internal pure` library functions). The only structural difference is inheritance vs. direct library call — required because `_pickSoloQuadrant` lives on a contract, not a library.

### Tie-break uniformity (modulo bias fix)
- **D-04:** SOLO-01 formula amended: tie-break index is `goldQuads[uint8((entropy >> 4) % goldCount)]` (drops the `& 3` mask). Rationale: the previous formula `((entropy >> 4) & 3) % goldCount` consumed only 2 entropy bits, yielding `{0,1,2,3} % 3 = {0,1,2,0}` → 50/25/25 distribution for goldCount=3 (will reject chi-squared p > 0.05 in SOLO-08(c) / Phase 261 STAT-04).
- **D-05:** SOLO-08(d) wording amended to cite the new formula (`(entropy >> 4) % goldCount` — drop the `& 3`). The "tie-break uses bits disjoint from bucket-rotation low-2-bits" property is preserved: bucket rotation reads `entropy & 3` (bits 0–1); the tie-break shifts past those bits and consumes bits 4–255 directly. Bits 2–3 are unused by either path.
- **D-06:** Bias bound after D-04: max bias < 2^-250 per goldCount across goldCount ∈ {2, 3, 4} — statistically indistinguishable from uniform across any feasible Monte Carlo sample. Phase 261 STAT-04 chi-squared p > 0.05 trivially holds for all goldCount cases.

### effectiveEntropy substitution shape
- **D-07:** At each of the 4 sites, extract `effectiveEntropy` once as a local `uint256` and pass it everywhere downstream (`JackpotBucketLib.bucketCountsForPoolCap`, `JackpotBucketLib.shareBpsByBucket`, `_processDailyEth`, `_executeJackpot`). Single source of truth per site. SOLO-09 split-mode coherence proof reads as line-for-line identical declarations at L349 and L1147.
- **D-08:** Canonical site-local block shape:
  ```solidity
  uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(_rollWinningTraits(randWord, false));
  uint256 entropy = EntropyLib.hash2(randWord, lvl);
  uint8 soloQuadrant = _pickSoloQuadrant(traitIds, entropy);
  uint256 effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3);
  ```
  The exact local-variable names are reviewer-facing — `effectiveEntropy` is canonical (used in the success-criterion text; do not rename). `traitIds` mirrors existing `traitIdsDaily` / `traitIds` usage at the surrounding sites.
- **D-09:** Substitution-correctness reasoning recorded for the planner: `_processDailyEth` reads `entropy` (now `effectiveEntropy`) only via (a) `JackpotBucketLib.soloBucketIndex(entropy)` — bits 0–1, intentionally substituted — and (b) `entropyState = entropy` then chained `entropyState = keccak256(entropyState, traitIdx, share)` — upper bits preserved across the substitution → winner-selection randomness statistically identical to v33.0. Same property holds for `_executeJackpot` → `_runJackpotEthFlow` (offset = `jp.entropy & 3`) and `JackpotBucketLib.shareBpsByBucket(_, uint8(entropy & 3))`.

### Approval & commit posture (carried forward)
- **D-10:** All `contracts/` and `test/` edits in this phase are batched and presented as one diff at the end of the phase per `feedback_batch_contract_approval.md`; user approval is explicit per commit (no orchestrator pre-approval) per `feedback_no_contract_commits.md` and `feedback_never_preapprove_contracts.md`.
- **D-11:** Skip research-agent dispatch per `feedback_skip_research_test_phases.md` — phase is fully specified in REQUIREMENTS.md (SOLO-01..09) with exact line numbers, exact substitution formula, exact tie-break formula (with D-04 amendment), and exact 8 non-injection sites. Plan directly.
- **D-12:** Plan slicing left to the planner (mirrors Phase 259 D-11 mechanical-phase posture). Reference shape: P1 = helper + 4 site injections + 8 non-injection grep proof; P2 = `JackpotSoloTester.sol` + unit tests (SOLO-08 a/b/c/d); P3 = SOLO-09 integration test (L349 → L1147 split-mode coherence). Single-plan or 2-plan packings also acceptable so long as all 4 injection sites land in one commit (SPLIT_CALL1 / SPLIT_CALL2 atomicity).

### Spec amendments (recorded for REQUIREMENTS.md update)
- **D-13:** SOLO-01 needs two text edits when REQUIREMENTS.md is updated alongside the implementation: (1) `private pure` → `internal pure`; (2) `goldQuads[uint8((entropy >> 4) & 3) % goldCount]` → `goldQuads[uint8((entropy >> 4) % goldCount)]`.
- **D-14:** SOLO-08(d) needs the same formula edit — drop the `& 3`. The "verify the entropy bit-shift is correct so gold-priority does not collide with the bucket-rotation bits at `entropy & 3`" rationale stays — it's still satisfied (rotation reads bits 0–1; tie-break reads bits 4+).

### Claude's Discretion
- Local-variable naming inside the 4 site blocks beyond the canonical `traitIds` / `entropy` / `soloQuadrant` / `effectiveEntropy` quartet (D-08).
- Helper placement within `DegenerusGameJackpotModule.sol` — planner default: place `_pickSoloQuadrant` adjacent to the existing `_processDailyEth` / `_runJackpotEthFlow` ETH-distribution helpers (current cluster around lines 1090–1190), not at top of file.
- Hardhat fixture pattern for the SOLO-09 integration test (existing `test/integration/GameLifecycle.test.js` is the closest reference; planner picks fixture composition).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — SOLO-01..09 (helper signature, substitution formula, all 4 injection-site line numbers, all 8 non-injection-site line numbers, tie-break decision and formula, unit + integration test surface). **Note D-13 + D-14 amendments above** — REQUIREMENTS.md text predates this discussion; the planner reconciles wording during the requirement-rewrite step (SOLO-01 visibility + tie-break formula).
- `.planning/ROADMAP.md` §"Phase 260: Gold Solo Priority Injection" — Goal, Success Criteria 1-5, Depends-on (Phase 259 — gold color tier 7 must exist before `_pickSoloQuadrant` can ever fire on non-empty gold set), Atomicity note (all 4 sites ship in one phase).
- `.planning/PROJECT.md` §"Current Milestone: v34.0" — Tie-break decision (random-among-gold, option B); `JackpotBucketLib` UNCHANGED constraint; bucket share BPS UNCHANGED constraint; bucket counts UNCHANGED constraint.

### Contracts under change
- `contracts/modules/DegenerusGameJackpotModule.sol` — Module being modified (helper added + 4 sites injected). Production v33.0 baseline at HEAD `4ce3703d`.
- `contracts/test/JackpotSoloTester.sol` — NEW file (inherits `DegenerusGameJackpotModule`, `external pure` passthrough; D-02).
- `contracts/test/TraitUtilsTester.sol` — Reference pattern (Phase 259) for the tester. Same passthrough idiom; the difference is inheritance vs. direct library call.

### Surfaces preserved (byte-identical, no edits)
- `contracts/libraries/JackpotBucketLib.sol` — UNCHANGED (SOLO-07). `soloBucketIndex(entropy) = (3 - (entropy & 3)) & 3` formula preserved; `traitBucketCounts` / `shareBpsByBucket` / `bucketCountsForPoolCap` / `rotatedShareBps` rotation logic untouched. Verified by `git diff` against v33.0 baseline `4ce3703d`.
- 8 non-injection sites in `contracts/modules/DegenerusGameJackpotModule.sol` — lines 513, 527 (emit-only `DailyWinningTraits`), 598, 599 (`_distributeTicketJackpot` equal-active-bucket via `_computeBucketCounts`), 683 (`_runEarlyBirdLootboxJackpot` literal `[25,25,25,25]`), 1687 (`_awardDailyCoinToTraitWinners`), 1713, 1715 (`emitDailyWinningTraits` no distribution). Verified byte-identical via `git diff` vs v33.0 `4ce3703d`.

### Caller surfaces (no change required, behavior verification only)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — calls `payDailyJackpot` / `runTerminalJackpot` / `_resumeDailyEth` chain. No edits; effectiveEntropy substitution is internal to the jackpot module.

### Memory / feedback governing this phase
- `feedback_no_contract_commits.md` — explicit per-commit user approval for all `contracts/` + `test/` changes.
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end (D-10).
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved.
- `feedback_no_history_in_comments.md` — comments describe what IS; no "previously was" or "changed from".
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch for mechanical phases (D-11).
- `feedback_no_dead_guards.md` — no unreachable safety caps in the new helper or substitution paths.
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push contract changes without diff review.
- `feedback_rng_backward_trace.md` — every RNG audit traces backward from each consumer; here, `effectiveEntropy` consumers are the 4 ETH-distribution sites + `_processDailyEth` chained-keccak winner selection.
- `feedback_rng_commitment_window.md` — what player-controllable state can change between VRF request and fulfillment for these consumers (planner notes: trait packing is consumed AFTER VRF fulfillment via `_rollWinningTraits(randWord, false)` — same window as v33.0; the new helper reads only locally-derived `traitIds` from that roll).

### Prior-phase context
- `.planning/phases/259-trait-distribution-split/259-CONTEXT.md` — Phase 259 introduces color==7 (gold) tier; the new distribution is the precondition for `_pickSoloQuadrant` ever firing on a non-empty gold set.
- `.planning/phases/259-trait-distribution-split/259-VERIFICATION.md` — Phase 259 closure evidence (TRAIT-01..06 satisfied; weightedColorBucket / traitFromWord / packedTraitsFromSeed live).

### Milestone & state
- `.planning/PROJECT.md` — v34.0 milestone goal (trait rarity rework + gold solo priority); contract HEAD anchor `4ce3703d740d3707c88a1af595618120a8168399`.
- `.planning/STATE.md` — Phase 260 transition; Phase 259 batched diff resume signal.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`contracts/test/TraitUtilsTester.sol`** — Phase 259 reference for the tester. Different in one structural respect: TraitUtilsTester wraps a library (direct call); JackpotSoloTester inherits a contract (member access). Pattern (single tiny tester contract per testable internal-pure surface) is identical.
- **`JackpotBucketLib.unpackWinningTraits(uint32) → uint8[4]`** — Already present and used at all 4 injection sites. The new helper takes the resulting `uint8[4]` directly; no signature change to the library function.
- **`EntropyLib.hash2(randWord, lvl)`** — Already used at sites 282 / 349 / 524 / 1147. The new `effectiveEntropy` derivation is downstream of this; `entropy` input is the same object as v33.0.
- **`_processDailyEth` / `_executeJackpot` / `_runJackpotEthFlow`** — Existing distribution pipelines. Each consumes `entropy` in two ways: (a) low 2 bits for solo bucket / rotation; (b) chained keccak for winner selection. The substitution affects only (a) — by design.
- **No constructor in the inheritance chain** (`DegenerusGameStorage` → `DegenerusGamePayoutUtils` → `DegenerusGameJackpotModule`) → `JackpotSoloTester` deploys without arguments.

### Established Patterns
- **Inline trait unpacking + entropy derivation per site** — Each of the 4 injection sites already has its own `(traitIds, entropy)` derivation block; the new substitution slots in immediately after, before any `JackpotBucketLib` read.
- **Site-local block discipline** — The four sites currently have site-local locals (`traitIds`, `traitIdsDaily`, `entropy`, `entropyDaily`); the new `soloQuadrant` and `effectiveEntropy` follow the same convention. Site naming variants (`Daily` suffix at L349, no suffix at L282/L524/L1147) preserved.
- **Internal-pure test exposure** — `contracts/test/` is the dedicated home for test-only wrappers; do NOT add public/external functions to the production module itself. JackpotSoloTester continues this convention.
- **Substitution formula sourced from REQUIREMENTS.md** — `(entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3)` exactly as specified in SOLO-02..05. The `(3 - soloQuadrant)` term inverts to match the existing `JackpotBucketLib.soloBucketIndex(entropy) = (3 - (entropy & 3)) & 3` rotation convention so that downstream rotation lands on `soloQuadrant`.

### Integration Points
- **L282 (`runTerminalJackpot`):** entropy = `EntropyLib.hash2(rngWord, targetLvl)`. Substitute before `bucketCountsForPoolCap` (L289) AND `shareBpsByBucket` (L294). Pass `effectiveEntropy` into `_processDailyEth` (called at L300).
- **L349 (`payDailyJackpot` jackpot-phase main):** entropy = `EntropyLib.hash2(randWord, lvl)`. Substitute before `bucketCountsForPoolCap` (L460-466) AND `shareBpsByBucket` (L484-485). Pass `effectiveEntropy` into `_processDailyEth` (L487).
- **L524 (`payDailyJackpot` purchase-phase main):** entropy = `EntropyLib.hash2(randWord, lvl)`. Substitute before constructing `JackpotParams` at L526-533; field `entropy: effectiveEntropy`. `_executeJackpot` reads `jp.entropy` for both bucket-count rotation AND `shareBpsByBucket` offset — both consume identical low 2 bits under the new entropy.
- **L1147 (`_resumeDailyEth` SPLIT_CALL2):** entropy = `EntropyLib.hash2(randWord, lvl)`. MUST produce identical `effectiveEntropy` as L349 (same `randWord`, same `lvl`, same `_rollWinningTraits` result, same `_pickSoloQuadrant` output, same substitution formula). The current body re-derives `entropy` and `traitIds` inline; new substitution slots in identically.
- **8 non-injection sites:** `git diff` proof at phase close — none of the 8 lines (513, 527, 598, 599, 683, 1687, 1713, 1715) appears in the patch hunk.

</code_context>

<specifics>
## Specific Ideas

- Helper body shape (locked by SOLO-01 + D-04):
  ```solidity
  function _pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) internal pure returns (uint8) {
      uint8[4] memory goldQuads;
      uint8 goldCount;
      for (uint8 i; i < 4; ++i) {
          if (((traits[i] >> 3) & 7) == 7) {
              goldQuads[goldCount++] = i;
          }
      }
      if (goldCount == 0) {
          return uint8((3 - (entropy & 3)) & 3);
      }
      return goldQuads[uint8((entropy >> 4) % goldCount)];
  }
  ```
  The exact body is the planner's call (loop unroll vs. bounded for-loop); semantics locked. No `unchecked` block needed (all uint8 arithmetic on bounded values; `goldCount++` cannot overflow given the 4-bound).
- Substitution formula at every injection site (locked by SOLO-02..05):
  ```solidity
  uint8 soloQuadrant = _pickSoloQuadrant(traitIds, entropy);
  uint256 effectiveEntropy = (entropy & ~uint256(3)) | uint256((3 - soloQuadrant) & 3);
  ```
- `JackpotSoloTester.sol` exact content:
  ```solidity
  // SPDX-License-Identifier: AGPL-3.0-only
  pragma solidity 0.8.34;

  import {DegenerusGameJackpotModule} from "../modules/DegenerusGameJackpotModule.sol";

  /// @title JackpotSoloTester
  /// @notice Test helper that exposes _pickSoloQuadrant as an external-pure passthrough
  ///         so Hardhat JS tests can invoke the real production bytes directly.
  /// @dev Deploy in tests to verify gold-priority tie-break and zero-gold rotation fallback.
  contract JackpotSoloTester is DegenerusGameJackpotModule {
      function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
          return _pickSoloQuadrant(traits, entropy);
      }
  }
  ```
- Unit-test bucket plan (SOLO-08):
  - (a) zero gold → `_pickSoloQuadrant([0,8,16,24], entropy)` returns `(3 - (entropy & 3)) & 3` for a sweep of entropy values.
  - (b) one gold → for each i ∈ {0,1,2,3}, build `traits` with color==7 only at index i; assert helper returns i for any entropy.
  - (c) 2 / 3 / 4 gold → for each goldCount ∈ {2, 3, 4}, sample 100K random entropies, bucket the returned indices, run chi-squared against uniform across gold positions; expect p > 0.05.
  - (d) tie-break independence — verify entropy bits used by tie-break (bits 4+) are disjoint from bits 0–1 used by `JackpotBucketLib.soloBucketIndex` rotation.
- Integration test plan (SOLO-09): construct a daily jackpot with at least one gold-color winning trait; drive the two-call SPLIT_CALL1 → SPLIT_CALL2 path through `payDailyJackpot` (jackpot-phase) → `_resumeDailyEth`; capture `effectiveEntropy` indirectly via the bucket selection observed at both calls (e.g., assert solo bucket lands on the same gold quadrant in both phases; assert `bucketTotals` reconstruct end-to-end).

</specifics>

<deferred>
## Deferred Ideas

- **Plan slicing decision** — defer to the planner; reference shape in D-12 (3 plans: helper+injections, tester+unit tests, integration test). Single-plan packing acceptable so long as all 4 injection sites land in one commit.
- **Helper location within the file** — defer to the planner; default placement: adjacent to `_executeJackpot` / `_processDailyEth` / `_runJackpotEthFlow` cluster (~lines 1080–1190).
- **REQUIREMENTS.md text edits for SOLO-01 + SOLO-08(d)** (D-13, D-14) — defer to the same plan that introduces the helper. The wording amendment is mechanical; landing it alongside the implementation keeps the spec ↔ code in lockstep.
- 1M-sample empirical color/symbol distribution + chi-squared independence — Phase 261.
- Gold-solo coverage simulation (100% of gold-present draws land on a gold quadrant) — Phase 261.
- Pack-feel CIs (≥1 legendary in 27.0% of 10-packs etc.) — Phase 261.
- Cross-surface preservation (hero override `_applyHeroOverride`, deity-pass virtual entries, Degenerette match payouts, full byte-equivalence sweep of the 8 non-injection bonus-jackpot sites' bucket distributions) — Phase 261.
- Gas regression vs v33.0 baseline (`_pickSoloQuadrant` < 500 gas worst-case 4-gold; per-call delta on `runTerminalJackpot` / `payDailyJackpot` / `_resumeDailyEth` < 2000 gas; `weightedColorBucket` ±100 gas) — Phase 261. Per `feedback_gas_worst_case.md`, derive theoretical worst case FIRST, then test.
- Delta audit / findings consolidation (`audit/FINDINGS-v34.0.md`) — Phase 262.

</deferred>

---

*Phase: 260-gold-solo-priority-injection*
*Context gathered: 2026-05-08*
