# Phase 195: Jackpot Two-Call Split - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Split daily jackpot and early-burn ETH distribution across two advanceGame calls so no single call exceeds 16M gas under worst-case conditions. The split is bucket-based, achieved by lowering the scaling constants so the natural bucket counts fit within two-call boundaries.

</domain>

<decisions>
## Implementation Decisions

### Split Boundary
- **D-01:** Call 1 processes the largest bucket + solo bucket. Call 2 processes the two mid buckets.
- **D-02:** Bucket iteration order remains largest-first (`bucketOrderLargestFirst`). Call 1 takes order[0] (largest) + the solo/remainder bucket. Call 2 takes the remaining 2 buckets.

### Scaling Constants (replaces per-bucket hard caps)
- **D-03:** Lower `DAILY_JACKPOT_SCALE_MAX_BPS` from 66_667 (6.67x) to 63_600 (6.36x). This makes the largest bucket scale to 159 instead of 167 at max pool (200+ ETH). No per-bucket hard caps needed — the scaling naturally produces safe counts.
- **D-04:** Lower `DAILY_ETH_MAX_WINNERS` from 321 to 305 to match the new max total (159+95+50+1=305).
- **D-05 (supersedes old D-04):** At max scale, call 1 processes 159+1=160 winners, call 2 processes 95+50=145 winners. Both under 160. At lower pools, counts are much smaller (e.g., 49 total at base, 97 at 50 ETH). `MAX_BUCKET_WINNERS=250` becomes a safety net that never triggers.

### Inter-Call State
- **D-06:** Store original ethPool as uint128 in a single storage slot. Non-zero value = resume pending (call 2 needed). Call 2 reads it to recompute identical bucket shares from RNG word + stored ethPool, processes mid buckets, then clears the slot.
- **D-07:** No paidEthSoFar needed — per-winner payouts update claimable balances inline during each call. The stored ethPool snapshot ensures call 2 computes the same bucket shares as call 1.

### Stage Design
- **D-08:** New STAGE_JACKPOT_ETH_RESUME = 8 (currently unused gap between STAGE_ENTERED_JACKPOT=7 and STAGE_JACKPOT_COIN_TICKETS=9). Call 2 enters via this stage.
- **D-09:** Both `_processDailyEth` and `_distributeJackpotEth` use the same resume pattern and stage 8.

### Claude's Discretion
- Exact implementation of how the solo bucket is identified in the split (it may or may not be the smallest — it's RNG-determined)
- Whether to create a shared helper for the resume check or inline it
- How to handle the edge case where ethPool stored value is legitimately 0 (no jackpot) vs cleared-after-resume

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Jackpot Distribution
- `contracts/modules/DegenerusGameJackpotModule.sol` lines 1128-1230 — `_processDailyEth` (daily path, 4-bucket iteration with largest-first ordering)
- `contracts/modules/DegenerusGameJackpotModule.sol` lines 1230-1270 — `_distributeJackpotEth` (early-burn path, sequential 4-bucket iteration)
- `contracts/modules/DegenerusGameJackpotModule.sol` line 193 — `MAX_BUCKET_WINNERS = 250` (to be replaced with per-bucket caps)

### AdvanceGame Stage Machine
- `contracts/modules/DegenerusGameAdvanceModule.sol` lines 59-69 — Stage constants (stage 8 is free)
- `contracts/modules/DegenerusGameAdvanceModule.sol` lines 404-427 — Jackpot phase flow (STAGE_ENTERED_JACKPOT through STAGE_JACKPOT_DAILY_STARTED)

### Bucket Library
- `contracts/libraries/JackpotBucketLib.sol` — `bucketShares`, `bucketOrderLargestFirst`, `soloBucketIndex`
- `contracts/libraries/JackpotBucketLib.sol` lines 16-22 — Scaling constants (`JACKPOT_SCALE_MIN_WEI=10 ETH`, `FIRST_WEI=50 ETH`, `SECOND_WEI=200 ETH`)
- `contracts/libraries/JackpotBucketLib.sol` lines 36-51 — `traitBucketCounts` base values (25/15/8/1)
- `contracts/libraries/JackpotBucketLib.sol` lines 55-95 — `scaleTraitBucketCountsWithCap` scaling logic
- `contracts/modules/DegenerusGameJackpotModule.sol` line 203 — `DAILY_ETH_MAX_WINNERS = 321` (to become 305)
- `contracts/modules/DegenerusGameJackpotModule.sol` line 228 — `DAILY_JACKPOT_SCALE_MAX_BPS = 66_667` (to become 63_600)

### Prior Audit
- `.planning/milestones/v23.0-phases/193-gas-ceiling-test-regression/WORST-CASE-ANALYSIS.md` — Worst-case gas derivation (321 autorebuy winners, ~25M gas)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `JackpotBucketLib.bucketOrderLargestFirst` — already returns 4-element order array, can be used to identify which buckets go in call 1 vs call 2
- `JackpotBucketLib.soloBucketIndex(entropy)` — identifies which bucket is the solo/remainder bucket
- `JackpotBucketLib.bucketShares` — pure computation from ethPool, shareBps, bucketCounts — safe to call twice with same inputs

### Established Patterns
- Stage machine in AdvanceModule uses break/fall-through with `do { ... } while (false)` pattern
- JackpotModule stores persistent state in storage variables at contract level (e.g., `claimablePool`, `traitBurnTicket`)
- RNG word is stored on-chain and reusable across calls

### Integration Points
- `payDailyJackpot` in JackpotModule is the entry point called from AdvanceModule — this needs to be aware of the split
- `runBafJackpot` (early-burn path) via delegatecall — also needs the split for `_distributeJackpotEth`
- AdvanceModule stage routing needs new case for STAGE_JACKPOT_ETH_RESUME

</code_context>

<specifics>
## Specific Ideas

- User chose lowering scaling constants over per-bucket hard caps — cleaner, no winners ever excluded by a cap that fights the scaling curve
- Scaling analysis: base counts 25/15/8/1, at 6.36x max → 159/95/50/1 = 305 total. Under 10 ETH: 49 total (no scaling). At 50 ETH: ~97 total. Caps only matter at 200+ ETH.
- User prefers storing original ethPool (uint128) over pre-computed shares — less storage, recomputation is cheap

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 195-jackpot-two-call-split*
*Context gathered: 2026-04-06*
