# Phase 117: Libraries - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for execution

<domain>
## Phase Boundary

Adversarial audit of the five shared library contracts used across the Degenerus protocol: EntropyLib.sol, BitPackingLib.sol, GameTimeLib.sol, JackpotBucketLib.sol, and PriceLookupLib.sol. This phase examines every function in these libraries using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The libraries handle:

**EntropyLib (24 lines, 1 function):**
- XOR-shift PRNG step for deterministic entropy derivation from VRF seeds
- Used by: JackpotModule, EndgameModule, LootboxModule, PayoutUtils, MintModule (20+ call sites)

**BitPackingLib (88 lines, 1 function + 10 constants):**
- Bit-packed storage field operations for mintPacked_ player data
- 256-bit layout: lastLevel[0-23], levelCount[24-47], levelStreak[48-71], day[72-103], unitsLevel[104-127], frozenUntilLevel[128-151], bundleType[152-153], streakLastCompleted[160-183], levelUnits[228-243]
- Used by: DegenerusGame, GameStorage, MintModule, WhaleModule, AdvanceModule, BoonModule, DegeneretteModule, MintStreakUtils (50+ call sites)

**GameTimeLib (35 lines, 2 functions):**
- Day index calculation relative to deploy time with 22:57 UTC reset boundary
- Used by: DegenerusAffiliate, DegenerusGameStorage (game-wide day tracking)

**JackpotBucketLib (307 lines, 14 functions):**
- Trait bucket count computation with entropy-based rotation for fairness
- Jackpot scaling by pool size (1x under 10 ETH, linear to 2x at 50 ETH, linear to maxScaleBps at 200 ETH)
- Bucket capping with solo bucket preservation
- ETH/COIN share computation with unit-rounded distribution and remainder handling
- Share BPS rotation and unpacking
- Winning trait packing/unpacking (4 traits in uint32)
- Random trait derivation from entropy (4 quadrants, 6 bits each)
- Used by: JackpotModule (25+ call sites -- the primary consumer)

**PriceLookupLib (47 lines, 1 function):**
- Level-based pricing tiers: intro (0.01-0.02 ETH for levels 0-9), standard cycle (0.04-0.16 ETH), milestone (0.24 ETH at x00)
- Used by: EndgameModule, WhaleModule, JackpotModule, PayoutUtils, LootboxModule (12+ call sites)

**CRITICAL PROPERTY:** All five libraries are STATELESS -- they contain only internal pure/view functions with ZERO storage writes. This means:
- No BAF-class cache-overwrite bugs are possible within the libraries themselves
- The attack surface shifts to: (1) correctness of pure computation, (2) entropy bias, (3) boundary conditions, (4) caller misuse of return values

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Category D only for all library functions -- every function is internal pure or internal view. There are no state-changing functions (Category B/C). However, every function STILL gets full analysis: call tree, correctness proof, boundary analysis, and attack angles relevant to pure functions.
- **D-02:** Despite being "only" Category D, these libraries get full Mad Genius treatment because library bugs cascade into every caller. A biased entropy extraction or incorrect bit pack/unpack affects the entire protocol.
- **D-03:** MULTI-PARENT standalone analysis -- all five libraries audited as a single unit. Cross-library interactions are first-class audit targets (e.g., EntropyLib entropy feeding into JackpotBucketLib rotation).

### Library-Specific Attack Angles
- **D-04:** Entropy bias analysis is the #1 priority for EntropyLib and JackpotBucketLib. The XOR-shift step must produce uniform distribution. Bucket rotation and trait selection must not favor any outcome.
- **D-05:** Bit packing correctness is critical for BitPackingLib. Field overlaps, off-by-one in shift positions, and mask width mismatches can corrupt adjacent fields silently.
- **D-06:** Time boundary correctness for GameTimeLib. Underflow risk when timestamp < JACKPOT_RESET_TIME (early UTC hours), DEPLOY_DAY_BOUNDARY edge cases, day 0 vs day 1 semantics.
- **D-07:** Bucket math for JackpotBucketLib. Rounding in scaling, cap enforcement correctness, share distribution summing to pool (no dust leak or over-distribution), solo bucket preservation under all cap scenarios.
- **D-08:** Price tier boundary correctness for PriceLookupLib. Off-by-one at tier boundaries (level 4/5, 9/10, 29/30, 99/100), cycleOffset == 0 handling, uint24 max value behavior.

### Fresh Analysis
- **D-09:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. Every function is guilty until proven innocent.
- **D-10:** Prior audit results are not input to this phase.

### Caller Misuse Patterns
- **D-11:** For each library function, identify how callers use it and whether any caller makes incorrect assumptions about the return value, range, or behavior. Library bugs include not just wrong implementation but misleading interfaces.
- **D-12:** Specifically trace: Does any caller pass untrusted input directly to a library function without range checking? Can a caller-provided entropy value produce degenerate output (e.g., entropyStep(0) = 0)?

### Report Format
- **D-13:** Follow ULTIMATE-AUDIT-DESIGN.md format adapted for pure/view functions: per-function sections with Implementation Analysis, Boundary Analysis, Entropy/Bias Analysis (where applicable), Caller Misuse Analysis, and Attack verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest by library, risk-ordered within each)
- Level of caller-site analysis depth (enough to verify no misuse, no more)
- Whether to split the attack report into multiple sections per library

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/libraries/EntropyLib.sol` -- XOR-shift PRNG (24 lines)
- `contracts/libraries/BitPackingLib.sol` -- Bit-packed field operations (88 lines)
- `contracts/libraries/GameTimeLib.sol` -- Day index calculation (35 lines)
- `contracts/libraries/JackpotBucketLib.sol` -- Jackpot bucket sizing and shares (307 lines)
- `contracts/libraries/PriceLookupLib.sol` -- Level pricing tiers (47 lines)

### Dependency
- `contracts/ContractAddresses.sol` -- Compile-time constants (DEPLOY_DAY_BOUNDARY used by GameTimeLib)

### Key Callers (for misuse analysis)
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Primary JackpotBucketLib + EntropyLib consumer
- `contracts/modules/DegenerusGameLootboxModule.sol` -- EntropyLib consumer
- `contracts/modules/DegenerusGameEndgameModule.sol` -- EntropyLib + PriceLookupLib consumer
- `contracts/modules/DegenerusGameMintModule.sol` -- BitPackingLib + EntropyLib consumer
- `contracts/modules/DegenerusGameWhaleModule.sol` -- BitPackingLib + PriceLookupLib consumer
- `contracts/storage/DegenerusGameStorage.sol` -- BitPackingLib + GameTimeLib consumer
- `contracts/DegenerusGame.sol` -- BitPackingLib constant consumer
- `contracts/DegenerusAffiliate.sol` -- GameTimeLib consumer
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- EntropyLib + PriceLookupLib consumer

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (format reference)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-01/ATTACK-REPORT.md` -- Phase 103 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### EntropyLib Functions
- `entropyStep(state)` (L16) -- XOR-shift: state ^= state<<7; state ^= state>>9; state ^= state<<8. Pure, unchecked.

### BitPackingLib Functions
- `setPacked(data, shift, mask, value)` (L79) -- Generic packed field setter: (data & ~(mask << shift)) | ((value & mask) << shift). Pure.
- Constants: MASK_16, MASK_24, MASK_32 + 8 shift position constants for mintPacked_ layout.

### GameTimeLib Functions
- `currentDayIndex()` (L21) -- Returns currentDayIndexAt(uint48(block.timestamp)). View.
- `currentDayIndexAt(ts)` (L31) -- (ts - JACKPOT_RESET_TIME) / 1 days - DEPLOY_DAY_BOUNDARY + 1. Pure.

### JackpotBucketLib Functions (14 total)
- `traitBucketCounts(entropy)` (L36) -- Base counts [25,15,8,1] rotated by entropy & 3
- `scaleTraitBucketCountsWithCap(baseCounts, ethPool, entropy, maxTotal, maxScaleBps)` (L55) -- Scale + cap
- `bucketCountsForPoolCap(ethPool, entropy, maxTotal, maxScaleBps)` (L98) -- Convenience wrapper
- `sumBucketCounts(counts)` (L110) -- Sum 4 buckets
- `capBucketCounts(counts, maxTotal, entropy)` (L115) -- Cap total preserving solo bucket
- `bucketShares(pool, shareBps, bucketCounts, remainderIdx, unit)` (L211) -- ETH/COIN share distribution
- `soloBucketIndex(entropy)` (L240) -- Solo bucket index from entropy rotation
- `rotatedShareBps(packed, offset, traitIdx)` (L245) -- Single rotated share BPS
- `shareBpsByBucket(packed, offset)` (L251) -- Unpack all 4 share BPS
- `packWinningTraits(traits)` (L264) -- Pack 4 uint8 into uint32
- `unpackWinningTraits(packed)` (L269) -- Unpack uint32 into 4 uint8
- `getRandomTraits(rw)` (L278) -- 4 quadrant trait derivation (6 bits each)
- `bucketOrderLargestFirst(counts)` (L290) -- Sort buckets by count descending
- (capBucketCounts is the most complex at ~80 lines with trim/remainder logic)

### PriceLookupLib Functions
- `priceForLevel(targetLevel)` (L21) -- Level-to-price lookup with intro tiers + 100-level cycle. Pure.

### Established Pattern (from prior phases)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-15/` directory

</code_context>

<specifics>
## Specific Ideas

Key areas of focus for this unit:

1. **EntropyLib XOR-shift quality:** The shift constants (7, 9, 8) must produce a full-period or near-full-period generator. Known-bad XOR-shift parameters produce short cycles or degenerate fixed points (e.g., state=0 -> state=0). Verify the specific triple (7, 9, 8) on uint256.

2. **BitPackingLib field overlap:** The mint data layout has gaps ([154-159], [184-227], [244-255]). Verify no caller writes to a position that bleeds into an adjacent field. Verify MASK_16 at shift 228 doesn't overflow uint256.

3. **GameTimeLib underflow:** If block.timestamp (cast to uint48) is less than JACKPOT_RESET_TIME (82620 = ~22.95 hours), the subtraction `ts - JACKPOT_RESET_TIME` underflows in uint48 space. Since this is `uint48` arithmetic in Solidity 0.8.34 (checked by default), this would revert. Is this intentional? What happens during the first ~23 hours of each UTC day?

4. **JackpotBucketLib scaling precision:** Linear interpolation between scale tiers uses integer division. At boundary values (exactly 10 ETH, 50 ETH, 200 ETH), verify smooth transitions without jumps or off-by-one.

5. **JackpotBucketLib cap trimming:** When scaled total exceeds nonSoloCap, the trim loop uses entropy bits to choose which buckets to zero. Verify this can't leave scaledTotal > nonSoloCap (insufficient trim iterations).

6. **PriceLookupLib boundary:** Level 99 returns 0.16 ETH, level 100 returns 0.24 ETH. Verify the first-cycle overrides (levels 0-9) don't interfere with levels 10-29 which should use standard 0.04 ETH pricing.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 118 coordination**: Full cross-module state coherence verification including library call-site analysis is deferred to the integration sweep.
- **Entropy quality deep-dive**: Statistical testing of the XOR-shift generator (chi-square, serial correlation) is out of scope for this audit. We verify the mathematical properties of the shift triple, not empirical distribution.

</deferred>

---

*Phase: 117-libraries*
*Context gathered: 2026-03-25*
