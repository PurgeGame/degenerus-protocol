---
phase: 260-gold-solo-priority-injection
reviewed: 2026-05-08T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - contracts/modules/DegenerusGameJackpotModule.sol
  - contracts/test/JackpotSoloTester.sol
  - test/integration/JackpotSoloSplit.test.js
  - test/unit/JackpotSoloPicker.test.js
findings:
  blocker: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 260: Code Review Report

**Reviewed:** 2026-05-08
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found (no blockers)

## Summary

The Phase 260 hunks land cleanly. Four `effectiveEntropy` injection sites were verified
against the v33.0 baseline (`4ce3703d`):

- L286-288 `runTerminalJackpot` (INJ-A): hoists `traitIds` once, derives `effectiveEntropy`,
  feeds `bucketCountsForPoolCap` / `shareBpsByBucket` / `_processDailyEth`.
- L451-455 `payDailyJackpot` jackpot-phase (INJ-B): derives `effectiveEntropy` immediately
  after `_unpackDailyTicketBudgets` is computed; threads it through both
  `bucketCountsForPoolCap`, `shareBpsByBucket`, and `_processDailyEth`.
- L529-532 `payDailyJackpot` purchase-phase (INJ-C): derives `effectiveEntropy` from
  `winningTraitsPacked` and writes it into `JackpotParams.entropy`. The downstream
  `_executeJackpot → _runJackpotEthFlow` reads `jp.entropy & 3` for offset rotation —
  inheriting the substituted bits 0-1 correctly.
- L1174-1177 `_resumeDailyEth` (INJ-D / SPLIT_CALL2): site-local block matches the L451
  pattern line-for-line (entropy → traitIds → soloQuadrant → effectiveEntropy → all four
  consumer args).

The new `_pickSoloQuadrant` helper at L1098 is mathematically correct:

- Zero-gold branch returns `uint8((3 - (entropy & 3)) & 3)`, which is exactly
  `JackpotBucketLib.soloBucketIndex(entropy)`. The substitution mask `(entropy & ~3) |
  ((3 - soloBucketIndex(entropy)) & 3)` then collapses to `entropy` — i.e. zero-gold
  produces a no-op effectiveEntropy, byte-identical to v33.0 behavior.
- Multi-gold branch: `goldQuads[(entropy >> 4) % goldCount]` consumes bits 4+, disjoint
  from the bucket-rotation low 2 bits, so the substitution mask
  `(entropy & ~3) | ((3 - soloQuadrant) & 3)` produces an entropy whose
  `soloBucketIndex(effectiveEntropy) == soloQuadrant` (verified algebraically and by
  the SOLO-09 integration test).
- Loop bounds are safe (`i < 4` / `goldCount <= 4` / `goldCount > 0` precondition for
  modulo), no array overflow on `goldQuads[goldCount++]` (capped at 4 writes).
- Modulo by `goldCount` ∈ {2,4} is unbiased; modulo by 3 has cryptographically
  negligible bias from a 252-bit operand (not a finding).

The 8 documented non-injection sites in v33.0 (lines 513, 527, 598, 599, 683, 1687,
1713, 1715) were verified byte-identical at the corresponding lines in the new file
(521, 535, 606, 607, 691, 1722, 1748, 1750). All 8 are `_rollWinningTraits(_, true)`
or `EntropyLib.hash2`/`keccak256` calls used for trait-bonus or coin-jackpot paths
that do NOT route through the solo-bucket ETH rotation — correctly excluded.

The L286 ↔ L451 ↔ L529 ↔ L1174 site-local blocks are structurally identical (same
4-line shape: `unpackWinningTraits → hash2 → _pickSoloQuadrant → effectiveEntropy mask`).
The L451 ↔ L1174 parity (the SOLO-09 split-mode invariant) is by-construction
guaranteed: identical inputs (`randWord`, `lvl`) drive identical helper outputs
because `_pickSoloQuadrant` is `internal pure` and `_rollWinningTraits(_, false) →
unpackWinningTraits` is deterministic in `randWord` for empty hero state.

The `JackpotSoloTester` harness is minimal (14 lines, no constructor, no state) — an
external-pure passthrough that exposes the production helper bytes to JS tests.
Inheritance is sound: `_pickSoloQuadrant` is `internal pure`, the override is
`external pure`.

The `JackpotSoloPicker.test.js` unit suite is methodologically sound:
- SOLO-08(a) zero-gold parity: verified across all 4 rotation values × 3 upper-bit
  perturbations.
- SOLO-08(b) one-gold determinism: verified all 4 quadrants × 7 entropy patterns each.
- SOLO-08(c) chi-squared uniformity: 100K samples per goldCount with cryptographic
  RNG seeded deterministically (keccak256(seed||counter)); critical values
  3.841/5.991/7.815 are correct chi² alpha=0.05 critical values for df=1/2/3.
- SOLO-08(d) bit-disjointness: verified bits 0-1 don't affect tie-break, bits 2-3
  unused, bits 4+ drive tie-break across all 3 valid `(entropy >> 4) % 3` values.

No test stubs (no `inferSoloQuadrant`-style trivial-return helpers); every assertion
calls the deployed `JackpotSoloTester` bytes.

The `JackpotSoloSplit.test.js` Strategy-B integration test is non-vacuous:
- GOLD_RANDWORD craft is correct (low 24 bits = `0xFFFFFF` puts `0x3F` in each 6-bit
  quadrant lane → all 4 traits gold under `getRandomTraits`); pre-flight assertion
  catches future seed regressions.
- Off-chain `hash2` replication is correct (`abi.encode(uint256, uint256)` matches
  the inline-assembly `mstore(0x00, a); mstore(0x20, b); keccak256(0x00, 0x40)`).
- `soloBucketIndex` off-chain replication is the v33.0 rotation formula — pure,
  trivial.
- Asserts effectiveEntropy parity, mask-inversion identity, upper-bits preservation,
  and a non-triviality guard (mutatedCount ≥ 1) that prevents the test from
  vacuously passing if the gold-priority feature were silently neutered.

Per project policy, contract changes must NOT be committed in this review (orchestrator
handles commits). No source files were modified.

## Warnings

### WR-01: SPLIT_CALL1/SPLIT_CALL2 coherence is asserted only by Strategy B (off-chain replication), never end-to-end on the actual jackpot module

**File:** `test/integration/JackpotSoloSplit.test.js:260-432`
**Issue:** The SOLO-09 invariant (`effectiveEntropy_L286 == effectiveEntropy_L1174` for
the same `(randWord, lvl)`) is the *only* property keeping the daily ETH two-call split
internally consistent. If call 1 derives `effectiveEntropy_A` and writes
`resumeEthPool` from buckets shaped by `bucketCountsForPoolCap(_, effectiveEntropy_A,
…)`, but call 2 derives `effectiveEntropy_B != effectiveEntropy_A` (e.g. due to a
future change in `_pickSoloQuadrant` that subtly reads state, a future hero-override
becoming sensitive to mid-VRF state, or a divergence in how each site materializes
`traitIds`), `resumeEthPool` would be consumed against a different bucket structure.
The mid-bucket allocation in call 2 could overpay/underpay relative to what call 1
reserved.

The Strategy-B test proves "by construction" — it invokes the same `_pickSoloQuadrant`
twice with hand-built identical inputs and asserts identity. This is mathematically
airtight FOR THE CURRENT SHAPE of the two site-local blocks, but it does NOT exercise
the actual `payDailyJackpot → _resumeDailyEth` call sequence. Any future refactor that
diverges the two site-local blocks (e.g. one site starts using a salted randWord, or
one site applies hero override and the other doesn't) would silently break SOLO-09
without failing this test.

The Strategy-A end-to-end test (full VRF flow with SPLIT_CALL1 → SPLIT_CALL2 event
capture against the real `DegenerusGameJackpotModule`) was explicitly deferred per
260-03-PLAN.md citing the 30-minute investigation budget. That deferral is documented
and acceptable for this phase, but the gap remains: there is no end-to-end regression
catch for the L286 ↔ L1174 parity invariant.

**Fix:** Add a follow-up integration test (post-Phase-260) that:
1. Bootstraps the game into the jackpot phase with a prize pool large enough to force
   `splitMode == SPLIT_CALL1` (total scaled winners > `JACKPOT_MAX_WINNERS`).
2. Fulfills VRF with `GOLD_RANDWORD`.
3. Captures the SPLIT_CALL1 event/state, then waits for the second VRF and captures
   SPLIT_CALL2.
4. Asserts that `resumeEthPool` (between the two calls) plus call-2 paid eth equals
   `dailyEthBudget * (paid bps fraction)` — i.e. the split is internally consistent.

Until that test exists, any change touching either L286 or L1174 must be hand-audited
for site-local block parity; the existing Strategy-B test will silently pass if the
two sites drift.

## Info

### IN-01: Test-file comments contain extensive v33.0 historical references, violating the no-history-in-comments rule

**File:** `test/integration/JackpotSoloSplit.test.js:23, 88, 95, 132, 140, 168, 174, 366, 386` and `test/unit/JackpotSoloPicker.test.js:65-66, 196`
**Issue:** Per `feedback_no_history_in_comments.md`, the rule applies to "all contracts,
all files, all contexts" — including test files. The integration test references
"post-Plan-01", "Plan 01 SUMMARY confirms `_resumeDailyEth` was rewritten", "byte-identical
to v33.0", "the v33.0 rotation", "v33.0-equivalent", "statistically identical to v33.0",
"the gold-priority pick differs from the v33.0 rotation", and `getRandomTraits` is annotated
"On-chain (post-v33.0)". The picker test contains "same as v33.0
JackpotBucketLib.soloBucketIndex(entropy)" and "drops the `& 3` mask" (describes a change
from a prior implementation).

Strict reading of the rule: comments must read "as if the code was always this way."
These comments describe what changed and what the prior baseline was — they are git-blame
content, not current-state documentation.

**Fix:** Rewrite the affected comments to describe what IS without comparative language.
For example:
- "must match `JackpotBucketLib.soloBucketIndex(entropy)`" instead of "same as v33.0 …"
- "Off-chain replication of the on-chain rotation formula" instead of "This is the v33.0
  rotation formula"
- "Bits 4+ drive the tie-break formula `(entropy >> 4) % goldCount` (no `& 3` mask)"
  instead of "drops the `& 3` mask"
- The integration test's preamble can describe the SOLO-09 invariant directly without
  referencing "post-Plan-01" or "Plan 01 SUMMARY".

These are test-suite documentation comments, not contract NatSpec, but the rule is
explicit about applying universally.

### IN-02: `_pickSoloQuadrant` allocates a 4-slot `goldQuads` buffer unconditionally even when zero golds are present

**File:** `contracts/modules/DegenerusGameJackpotModule.sol:1099`
**Issue:** The helper allocates `uint8[4] memory goldQuads` before the gold-scan loop.
When `goldCount == 0` (the most common path — only ~6% of random traits are color 7
under uniform distribution × 4 quadrants ≈ 22% chance of any gold; majority of calls
are zero-gold), the buffer is allocated and never used.

This is not a "dead guard" violation per `feedback_no_dead_guards.md` — the buffer is
reachable on the gold-present paths and necessary for correctness there. It's a minor
gas footprint observation: the helper allocates 32 bytes of memory on every call
regardless of whether the gold path runs. Memory expansion in a leaf `pure` function
is very cheap (a few gas), but the symmetric optimization (count first, then allocate
only if `goldCount > 0`) would require two passes through the trait array.

Performance is out of scope for this v1 review per workflow instructions, so this is
flagged as informational only — not a recommended change. Documenting for future
reference if a gas-tightening pass revisits this helper.

**Fix:** No change recommended. Single-pass with eager allocation is a defensible
trade-off for code clarity vs. ~10 gas savings per call.

### IN-03: SOLO-08(c) chi-squared test for `goldCount=3` cannot detect modulo bias from `(entropy >> 4) % 3`

**File:** `test/unit/JackpotSoloPicker.test.js:137-174`
**Issue:** When `goldCount == 3`, the helper computes `(entropy >> 4) % 3`. Since
`entropy >> 4` is uniform over [0, 2^252), and 2^252 is not divisible by 3, there is a
small modulo bias: residues 0, 1, 2 are NOT exactly equiprobable. The bias magnitude
is `1 / 2^252` per outcome — cryptographically negligible, far below what a 100K-sample
chi-squared at alpha=0.05 can detect.

The test passing for goldCount=3 does NOT prove unbiasedness — it proves that any bias
present is below the test's statistical detection threshold (~ a few hundred excess
samples in any one bucket out of 33,333 expected per bucket). This is a known
limitation of statistical testing against pseudo-uniform distributions, not a bug.

If perfect uniformity for goldCount=3 were ever required (it is NOT in this protocol —
fairness within ULP-of-2^-252 is overkill for a four-quadrant gold lottery), the helper
would need rejection sampling, which is overkill for the use case.

**Fix:** No change recommended. Documenting for completeness — the chi-squared test
methodology is sound for the protocol's fairness requirements.

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
