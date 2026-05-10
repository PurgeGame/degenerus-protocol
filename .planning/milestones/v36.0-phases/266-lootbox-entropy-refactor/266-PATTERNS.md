# Phase 266: Lootbox-Path Entropy Refactor — Pattern Map

**Mapped:** 2026-05-10
**Files analyzed:** 11 (2 contract scopes — modify + protect; 4 test scopes; 1 audit deliverable; 1 KI doc; 3 state docs)
**Analogs found:** 11 / 11 (every in-scope file has a concrete in-repo analog at HEAD `5db8682b`)

> Pattern source-of-truth: `audit/FINDINGS-v35.0.md` (deliverable shape) + `test/stat/PerPullLevelDistribution.test.js` (chi² infra) + `test/stat/SurfaceRegression.test.js` (PROTECTED_RANGES per-line walk) + `test/gas/Phase264GasRegression.test.js` (REF-CAPTURE + theoretical-worst-case derivation) + `.planning/phases/265-delta-audit-findings-consolidation/*` (single-plan multi-task atomic-commit precedent + adversarial-log shape) + `KNOWN-ISSUES.md` L31 (entry to rephrase). All analogs already verified at v35.0 closure HEAD per `266-RESEARCH.md` Sources block.

---

## Project Guardrails (apply to ALL plan tasks)

These ride above every per-file pattern. The planner MUST surface them in plan task NatSpec / per-commit checklists / agent-spawn directives:

- **`feedback_no_contract_commits.md`** — `contracts/` AND `test/` edits require explicit user approval. Phase 266 = 1 batched contract commit (LootboxModule) + N batched test commits, each USER-APPROVED.
- **`feedback_batch_contract_approval.md`** — Batch ALL phase contract edits, present ONE diff at end of impl-task block, get ONE explicit "approved" string before commit. Same for tests batched per-wave.
- **`feedback_never_preapprove_contracts.md`** — Agent MUST NOT pre-approve any contract change. Plan tasks must NOT contain language like "pre-approved" or "auto-approved" for contract or test edits.
- **`feedback_contractaddresses_policy.md`** — `ContractAddresses.sol` is the only contract pre-approved for modification. Vacuous this phase (no `ContractAddresses.sol` changes in scope).
- **`feedback_no_history_in_comments.md`** — Refactored LootboxModule NatSpec describes what IS, never what changed or what it used to be ("bit-slice scheme" not "this was xorshift before").
- **`feedback_no_dead_guards.md`** — Remove L1585 WWXRP-path entropyStep dead advance entirely (no dead branches; ~40 g savings per WWXRP-path lootbox).
- **`feedback_gas_worst_case.md`** — Derive theoretical worst-case bit-slice + keccak overhead opcode-by-opcode FIRST (in test header, mirroring `Phase264GasRegression.test.js` L18-50), THEN assert measured-vs-pinned-REF.
- **`feedback_rng_backward_trace.md`** — RNG audits trace BACKWARD from each consumer to verify word was unknown at input commitment time. Applies to AUDIT-02 surface (a) modulo-bias bound + EXC-04 NARROWS prose.
- **`feedback_rng_commitment_window.md`** — RNG audits check what player-controllable state can change between VRF request and fulfillment. Applies to AUDIT-02 surface (f) commitment-window check.
- **`feedback_manual_review_before_push.md`** — Final user-review gate on `audit/FINDINGS-v36.0.md` + KNOWN-ISSUES.md + ROADMAP/STATE/MILESTONES diffs BEFORE any push. Agent does not `git push`.
- **`feedback_wait_for_approval.md`** — Adversarial-pass disagreements (auditor / zero-day-hunter flagging a SAFE verdict, or surfacing novel composition) escalate to user inline before READ-only flip on the deliverable.

---

## File Classification (Wave-Ordered: Wave 1 contracts ⇒ Wave 2 tests ⇒ Wave 3-5 audit)

| Wave | New / Modified File                                                | Role                       | Data Flow                                | Closest Analog                                                                                                                                  | Match Quality |
|------|--------------------------------------------------------------------|----------------------------|------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|---------------|
| 1    | `contracts/modules/DegenerusGameLootboxModule.sol` (MODIFY 7 callsites + sub-call slicing)  | contract module — RNG consumer   | request-response (VRF-callback inside `advanceGame` for direct path; entry-point invocations for `openLootBox` / `openBurnieLootBox`) | Self at HEAD `5db8682b`, lines 800-1700 (refactor target body) — caller pattern from existing `EntropyLib.hash2` consumers in `DegenerusGameJackpotModule.sol` (L285/L453/L532/L610/L612/L886/L1176/L1873) | exact-self (refactor in place) |
| 1    | `contracts/libraries/EntropyLib.sol` (READ-ONLY — protect SURF-01) | library — keccak primitive | pure (no state)                          | Self (43 lines; `entropyStep` L16-23 + `hash2` L36-42)                                                                                          | exact-self    |
| 1    | `contracts/modules/DegenerusGameJackpotModule.sol` (READ-ONLY — protect SURF-02 BAF + SURF-04 9 callsites) | contract module — RNG consumer   | (no change)                              | Self at HEAD `5db8682b`                                                                                                                          | exact-self    |
| 1    | `contracts/modules/DegenerusGameMintModule.sol` (READ-ONLY — protect SURF-03 L652) | contract module — RNG consumer   | (no change)                              | Self at HEAD `5db8682b`                                                                                                                          | exact-self    |
| 2    | `test/stat/LootboxEntropyDistribution.test.js` (NEW)               | test — chi² statistical    | batch (10K-100K JS-replica samples per bucket; deterministic seeded keccak-counter PRNG)        | `test/stat/PerPullLevelDistribution.test.js` (chi² + Wilson-Hilferty + REGIMES table)                                                            | exact (same role + data flow + STAT-03 reuse-existing-tooling discipline) |
| 2    | `test/gas/LootboxOpenGas.test.js` (NEW) — OR extend `Phase264GasRegression.test.js` | test — gas regression      | request-response (entry-point measurement via deployFullProtocol fixture)        | `test/gas/Phase264GasRegression.test.js` (REF-CAPTURE + ENTRY_POINT_DELTA_TOLERANCE + theoretical-worst-case opcode walk)                       | exact (same role + per `feedback_gas_worst_case.md`) |
| 2    | `test/gas/AdvanceGameGas.test.js` (EXTEND — add v36.0 1.99× margin describe block) | test — gas benchmark       | request-response (advanceGame stage measurement)        | Self (existing `describe("AdvanceGame Gas Benchmarks")` block; v35.0 1.99× margin assertion already wired)                                       | exact-self extension |
| 2    | `test/stat/SurfaceRegression.test.js` (EXTEND — add v36.0 SURF-01..04 describe block + PROTECTED_RANGES) | test — surface preservation        | batch (per-line modified-set walk vs `git diff <V35_BASELINE> HEAD`)        | Self (existing `describe("v35.0 SURF-01..04 ...")` block at L249-405)                                                                            | exact-self extension |
| 3-5  | `audit/FINDINGS-v36.0.md` (NEW)                                    | audit deliverable — milestone closure | document (9-section prose)        | `audit/FINDINGS-v35.0.md` (most recent precedent; 562 lines; 9 sections; same closure-attestation TWO-subsection format)                         | exact-template |
| 4    | `KNOWN-ISSUES.md` (MODIFY 1 entry — EntropyLib XOR-shift to BAF-only) | KI document — entry edit | document (rephrase one entry)        | Self at HEAD `5db8682b`, L31 (current entry text — "lootbox outcome rolls" scope)                                                                | exact-self    |
| 5    | `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` (UPDATE — v36.0 SHIPPED + closure-signal) | state docs — milestone bookkeeping | document        | `.planning/phases/265-delta-audit-findings-consolidation/265-01-SUMMARY.md` (Phase 265 closure-flip pattern; same ROADMAP/STATE/MILESTONES update set) | exact-template |
| 5    | `.planning/phases/266-*/266-01-SUMMARY.md` + `.planning/phases/266-*/266-01-ADVERSARIAL-LOG.md` (NEW)  | phase artifacts — closure summary + adversarial log | document        | `.planning/phases/265-*/265-01-SUMMARY.md` + `.planning/phases/265-*/265-01-ADVERSARIAL-LOG.md`                                                  | exact-template |

---

## Pattern Assignments

### Wave 1 — Contract Refactor

#### `contracts/modules/DegenerusGameLootboxModule.sol` (contract, RNG consumer — refactor target)

**Analog:** Self at HEAD `5db8682b` (refactor in place); caller-shape pattern for inline-shift bit-slicing has NO direct analog (this phase introduces the pattern). Closest semantic precedent for "single keccak entry-point + slice downstream" is the v35 helper `_awardDailyCoinToTraitWinners` per-pull `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))` derivation — but that pattern derives a fresh per-iteration keccak, while Phase 266 derives ONE seed at resolution entry and slices. Therefore the locked source for the refactor pattern is `266-CONTEXT.md <specifics>` block + `266-RESEARCH.md` Bit-Budget Worked Table.

**Pre-refactor state at HEAD `5db8682b` — `_rollTargetLevel` body (lines 803-827):**

```solidity
/// @dev Roll a target level for lootbox resolution.
///      90% chance: 0-4 levels above base. 10% chance: 5-50 levels above base.
/// @param baseLevel The base level to roll from
/// @param entropy Starting entropy value
/// @return targetLevel The rolled target level
/// @return nextEntropy Updated entropy for subsequent rolls
function _rollTargetLevel(
    uint24 baseLevel,
    uint256 entropy
) private pure returns (uint24 targetLevel, uint256 nextEntropy) {
    uint256 levelEntropy = EntropyLib.entropyStep(entropy);   // L813 — REPLACE
    uint256 rangeRoll = levelEntropy % 100;
    if (rangeRoll < 10) {
        // 10% chance: far future (5-50 levels ahead)
        uint256 farEntropy = EntropyLib.entropyStep(levelEntropy);  // L817 — REPLACE
        uint256 levelOffset = (farEntropy % 46) + 5;
        targetLevel = baseLevel + uint24(levelOffset);
        nextEntropy = farEntropy;
    } else {
        // 90% chance: near future (0-4 levels ahead)
        uint256 levelOffset = levelEntropy % 5;
        targetLevel = baseLevel + uint24(levelOffset);
        nextEntropy = levelEntropy;
    }
}
```

**Pre-refactor state at HEAD `5db8682b` — `_resolveLootboxRoll` 4 entropyStep callsites (lines 1530-1616):**

```solidity
function _resolveLootboxRoll(
    address player, uint256 amount, uint256 lootboxAmount,
    uint24 targetLevel, uint256 targetPrice, uint24 currentLevel,
    uint32 day, uint256 entropy
) private returns (uint256 burnieOut, uint32 ticketsOut, uint256 nextEntropy, bool applyPresaleMultiplier)
{
    nextEntropy = EntropyLib.entropyStep(entropy);   // L1548 — REPLACE
    if (amount == 0) return (0, 0, nextEntropy, false);

    uint256 roll = nextEntropy % 20;                  // 16-bit slice in refactor
    if (roll < 11) { /* tickets path — calls _lootboxTicketCount(L1556) */ }
    else if (roll < 13) {
        nextEntropy = EntropyLib.entropyStep(nextEntropy);   // L1569 — REPLACE
        uint256 dgnrsAmount = _lootboxDgnrsReward(amount, nextEntropy);  // sub-call consumes entropy at L1680
        // ...
    } else if (roll < 15) {
        nextEntropy = EntropyLib.entropyStep(nextEntropy);   // L1585 — DEAD ADVANCE (WWXRP path uses literal LOOTBOX_WWXRP_PRIZE; no consumer downstream) → remove per feedback_no_dead_guards
        // ...
    } else {
        nextEntropy = EntropyLib.entropyStep(nextEntropy);   // L1599 — REPLACE
        uint256 varianceRoll = nextEntropy % 20;             // 16-bit slice
        // ...
    }
}
```

**Pre-refactor state at HEAD `5db8682b` — `_lootboxTicketCount` L1635 + sub-call at `_lootboxDgnrsReward` L1680 + `_rollLootboxBoons` L1059 (sub-call entropy consumers):**

```solidity
// L1635 — _lootboxTicketCount entry-point advance (REPLACE)
nextEntropy = EntropyLib.entropyStep(entropy);
uint256 varianceRoll = nextEntropy % 10_000;   // 24-bit slice in refactor (bias 0.045%)

// L1680 — _lootboxDgnrsReward direct entropy consumer (sub-call; NOT in CONTEXT.md
// D-266-CONSUMER-LIST-01 — planner MUST enumerate per RESEARCH.md Pitfall 3)
function _lootboxDgnrsReward(uint256 amount, uint256 entropy) private view returns (uint256 dgnrsAmount) {
    uint256 tierRoll = entropy % 1000;   // 24-bit slice in refactor (bias 0.0024%)
    // ...
}

// L1059 — _rollLootboxBoons direct entropy consumer (sub-call; NOT in D-266-CONSUMER-LIST-01)
uint256 roll = entropy % BOON_PPM_SCALE;   // 32-bit slice in refactor (bias 0.022%)
```

**Refactor pattern — locked from `266-CONTEXT.md <specifics>` + `266-RESEARCH.md` Code Examples (single-keccak-per-resolution + inline bit-slice):**

```solidity
// Caller derives ONE 256-bit seed at the entry of _resolveLootboxCommon (L554/L628/L673/L708);
// preserve existing keccak256(abi.encode(rngWord, player, day, amount)) per RESEARCH.md Open Question 2.
// Thread `seed` through downstream sub-rolls.
function _rollTargetLevel(uint24 baseLevel, uint256 seed)
    private pure returns (uint24 targetLevel)
{
    // Bit budget: rangeRoll bits[0..15] (% 100, bias 0.05%);
    //             near-level offset bits[16..23] (% 5, bias 0.39%);
    //             far-level offset bits[24..39] (% 46, bias 0.05%).
    uint256 rangeRoll = uint16(seed) % 100;
    if (rangeRoll < 10) {
        uint256 farOffset = uint16(seed >> 24) % 46;
        targetLevel = baseLevel + uint24(farOffset + 5);
    } else {
        uint256 nearOffset = uint8(seed >> 16) % 5;
        targetLevel = baseLevel + uint24(nearOffset);
    }
}

// ETH-amount-second branch overflow chunk (Option A from RESEARCH.md Pitfall 2):
//   uint256 seed2 = EntropyLib.hash2(seed, 1);   // counter-tagged second seed
// Document chunk-counter convention inline so AUDIT-02 surface (c) chunk-collision-free
// analysis is one-liner.
```

**NatSpec bit-budget block pattern (ENT-06 — minimum required documentation):**

Each refactored function MUST contain an inline NatSpec comment block enumerating which bits each `% small` consumes + any `hash2(seed, N)` chunk usage. Pattern: see `_rollTargetLevel` example above (3-line `// Bit budget:` comment naming each sub-roll's bit slice + bias).

**Cumulative bit budget per resolution (from `266-RESEARCH.md` Bit-Budget Worked Table):**

| Sub-roll                          | Slice            | Modulus    | Bias    |
|-----------------------------------|------------------|------------|---------|
| `rangeRoll` (`_rollTargetLevel`)  | bits[0..15]      | `% 100`    | 0.05%   |
| Near-level offset                 | bits[16..23]     | `% 5`      | 0.39%   |
| Far-level offset                  | bits[24..39]     | `% 46`     | 0.05%   |
| Path-roll (`_resolveLootboxRoll`) | bits[40..55]     | `% 20`     | 0.02%   |
| DGNRS tier (`_lootboxDgnrsReward`) | bits[56..79]    | `% 1000`   | 0.0024% |
| Large-BURNIE varianceRoll         | bits[80..95]     | `% 20`     | 0.02%   |
| Ticket varianceRoll (`_lootboxTicketCount`) | bits[96..119] | `% 10000` | 0.045%  |
| Boon roll (`_rollLootboxBoons`)   | bits[120..151]   | `% BOON_PPM_SCALE (1e6)` | 0.022% |
| **Cumulative**                    | **152 bits used / 256 available** | — | All ≤ 1% per D-266-BIT-BUDGET-01 |

ETH-amount-second branch uses `seed2 = EntropyLib.hash2(seed, 1)` for a fresh 256-bit chunk (Option A — counter-tagged; ~80 g; comfortably under ±300 g GAS-01 budget).

**Caller pattern for entry-point seed (preserve existing keccak; do NOT migrate to `EntropyLib.hash2` per RESEARCH.md Open Question 2 recommendation):**

```solidity
// At L554/L628/L673/L708 callsites (existing line):
uint256 entropy = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
// (keep as-is; rename to `seed`; thread into _resolveLootboxCommon as the new
//  single-source-of-entropy parameter.)
```

**Update points (all 4 resolution entry points must update atomically in the batched commit per RESEARCH.md Anti-Pattern "Breaking nextEntropy without updating ALL callsites"):**

- `openLootBox` callsite block (~L548-555)
- `openBurnieLootBox` callsite block (~L622-629)
- `resolveLootboxDirect` callsite block (~L668-675)
- `resolveRedemptionLootbox` callsite block (~L703-710)

(Live HEAD line numbers may have drifted by ±5 — planner verifies in execute-phase.)

---

#### `contracts/libraries/EntropyLib.sol` (READ-ONLY — SURF-01 byte-identity)

**Analog:** Self. ZERO modifications per ENT-04 / D-266-API-01.

**Verification recipe** (SURF-01 grep-proof — extends `test/stat/SurfaceRegression.test.js`):

```bash
git diff 5db8682bd7b811437f0c1cf47e832619d1478ac6..HEAD -- contracts/libraries/EntropyLib.sol
# Expected: empty output (zero hunks).
```

#### `contracts/modules/DegenerusGameJackpotModule.sol` (READ-ONLY — SURF-02 + SURF-04)

**Analog:** Self. ZERO modifications.

**SURF-02 protected range** (BAF jackpot `_jackpotTicketRoll` — ENT-05 deferral target): lines 2186-2229.

**SURF-04 protected lines** (9 EntropyLib callsites; verified inventory at HEAD `5db8682b` per `266-RESEARCH.md` Pitfall 6):

```
L285:  uint256 entropy = EntropyLib.hash2(rngWord, targetLvl);
L453:  uint256 entropyDaily = EntropyLib.hash2(randWord, lvl);
L532:  uint256 entropy = EntropyLib.hash2(randWord, lvl);
L610:  uint256 entropyDaily = EntropyLib.hash2(randWord, lvl);
L612:  uint256 entropyNext = EntropyLib.hash2(randWord, sourceLevel);
L886:  EntropyLib.hash2(randWord, lvl),
L1176: uint256 entropy = EntropyLib.hash2(randWord, lvl);
L1873: entropy = EntropyLib.hash2(entropy, s);
L2192: entropy = EntropyLib.entropyStep(entropy);   // BAF — covered by SURF-02 range
```

#### `contracts/modules/DegenerusGameMintModule.sol` (READ-ONLY — SURF-03 L652)

**Analog:** Self. ZERO modifications. Single protected line: L652 (`EntropyLib.hash2(entropy, rollSalt)` callsite).

---

### Wave 2 — Tests (chi² + gas + surface preservation)

#### `test/stat/LootboxEntropyDistribution.test.js` (NEW — STAT-01..03)

**Analog:** `test/stat/PerPullLevelDistribution.test.js` (Phase 264 STAT-01..04 origin).

**Imports + chi² infrastructure pattern** (STAT-03 reuse-existing-tooling discipline — re-declare verbatim, do NOT import from a shared module — per `266-RESEARCH.md` Anti-Patterns "Importing chi² helpers"):

```javascript
// Source: test/stat/PerPullLevelDistribution.test.js L45-58 (imports)
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
```

**Chi² helpers — verbatim re-declaration** (Source: `test/stat/PerPullLevelDistribution.test.js` L78-102):

```javascript
function makeRng(seed) {
  const seedHex =
    "0x" + BigInt.asUintN(256, BigInt(seed)).toString(16).padStart(64, "0");
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

const CHI2_CRIT_05 = {
  1: 3.841,
  2: 5.991,
  3: 7.815,
  4: 9.488,
  5: 11.070,
  6: 12.592,
  7: 14.067,
};

function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}
```

**REGIMES table pattern** (Source: `test/stat/PerPullLevelDistribution.test.js` L222-282 — multiple-bucket-per-file shape; choose Wilson-Hilferty for df>7 per `266-RESEARCH.md` Pitfall 1):

```javascript
// Source: pattern adapted from PerPullLevelDistribution.test.js for Phase 266
// 6 sub-roll regimes — pin sample budget per bucket inline to satisfy chi² rule of thumb (≥ 5 expected/bucket).
//
// Bucket          Samples  Expected/bucket  df    Critical
// % 100           10_000   100              99    wilsonHilfertyZ < 1.645
// % 5             5_000    1_000            4     CHI2_CRIT_05[4] = 9.488
// % 46            10_000   217              45    wilsonHilfertyZ < 1.645
// % 20 (path)     10_000   500              19    wilsonHilfertyZ < 1.645
// % 20 (variance) 5_000    250              19    wilsonHilfertyZ < 1.645
// % 10000         100_000  10               9999  wilsonHilfertyZ < 1.645  -- FLAGGED: marginal expected/bucket
const REGIMES = [
  { name: "rangeRoll % 100",       modulus: 100,   samples: 10_000,  highDf: true,  seed: 0xC036_0001 },
  { name: "near-offset % 5",       modulus: 5,     samples: 5_000,   highDf: false, seed: 0xC036_0002 },
  { name: "far-offset % 46",       modulus: 46,    samples: 10_000,  highDf: true,  seed: 0xC036_0003 },
  { name: "pathRoll % 20",         modulus: 20,    samples: 10_000,  highDf: true,  seed: 0xC036_0004 },
  { name: "varianceRoll % 20",     modulus: 20,    samples: 5_000,   highDf: true,  seed: 0xC036_0005 },
  { name: "ticketVariance % 10000",modulus: 10000, samples: 100_000, highDf: true,  seed: 0xC036_0006 },
];
```

**Per-regime test body pattern** (chi² over `% N` bucket via JS-replica RNG + Wilson-Hilferty for high-df; Source: `266-RESEARCH.md` Code Examples L536-557):

```javascript
// Source: pattern adapted from PerPullLevelDistribution.test.js L248-282 for high-df chi² (df=99) using wilsonHilfertyZ.
describe("STAT-01 — _rollTargetLevel rangeRoll % 100 chi² uniformity", function () {
  it("rangeRoll over N=10000 has wilsonHilfertyZ < 1.645 (df=99)", function () {
    const N = 10_000;
    const range = 100;
    const observed = new Array(range).fill(0);
    const rng = makeRng(0xC036_0001);  // Phase 266 seed convention (0xC036_NNNN)
    for (let i = 0; i < N; i++) {
      const seed = rng();
      const rangeRoll = Number(seed & 0xFFFFn) % range;  // bits[0..15] % 100
      observed[rangeRoll]++;
    }
    const expectedPerBucket = N / range;  // 100
    let chi2 = 0;
    for (let k = 0; k < range; k++) {
      const diff = observed[k] - expectedPerBucket;
      chi2 += (diff * diff) / expectedPerBucket;
    }
    const df = range - 1;  // 99
    const z = wilsonHilfertyZ(chi2, df);
    expect(z, `chi² = ${chi2.toFixed(2)} → Z = ${z.toFixed(3)} (df=${df})`).to.be.lt(1.645);
  });
});
```

**STAT-04-equivalent infra-reuse sanity assertion** (Source: `test/stat/PerPullLevelDistribution.test.js` describe block "STAT-04 — Phase 261 infrastructure reuse"):

Add a final describe block confirming chi² helpers re-declared verbatim from origin `test/stat/TraitDistribution.test.js` L48-100. Pattern: cross-cite the origin file path + assert structural equality of the re-declaration via comment block (no runtime check needed; STAT-04 is a documentation-only structural pin).

---

#### `test/gas/LootboxOpenGas.test.js` (NEW — GAS-01) OR extend `Phase264GasRegression.test.js`

**Analog:** `test/gas/Phase264GasRegression.test.js` (REF-CAPTURE + ENTRY_POINT_DELTA_TOLERANCE pattern).

**Theoretical worst-case derivation header pattern** (per `feedback_gas_worst_case.md` — derive worst case FIRST in test header, THEN test). Source: `test/gas/Phase264GasRegression.test.js` L18-50:

```javascript
// ============================================================================
// THEORETICAL WORST-CASE DERIVATION (Phase 266 lootbox-open envelope)
// ============================================================================
//
// Per-open seed-derivation cost (single-keccak-per-resolution + inline bit-slice):
//   - keccak256(abi.encode(rngWord, player, day, amount))     ~  80 gas
//     (entry-point keccak; MSTORE × 4 + KECCAK256(128 bytes) — preserve existing
//      pattern per RESEARCH.md Open Question 2)
//   - per-consumer inline shifts (uint8/uint16/uint24 + masks) ~ 6-12 gas each × 7 consumers ≈ 70-90 gas
//   - per-consumer % small modulo                              ~ 8 gas each × 7 consumers ≈ 56 gas
//   - SAVED: 5 entropyStep calls × ~20-30 g each = ~100-150 g per resolution
//   - SAVED: 1 dead L1585 entropyStep advance × ~20-30 g = ~25 g (WWXRP path)
//   - ETH-amount-second branch: + 1 hash2 keccak (~80 g) for seed2 chunk
//
// Net per-open delta: -(100-150) + (80 + 90 + 56) = +20 to +80 g per resolution
//                     (large-amount split branch: +20 to +80 g + 80 g seed2 = +100 to +160 g)
// GAS-01 envelope: ±300 g per-open. Headroom 2× over theoretical worst case.
//
// ============================================================================
// REFERENCE-CAPTURE PROTOCOL (HEAD-only per Phase 264 D-IMPL-04)
// ============================================================================

const PER_OPEN_GAS_DELTA_BOUND        = 300;       // GAS-01 ±300 g per-open
const ENTRY_POINT_DELTA_TOLERANCE     = 2000;      // ±2000 gas per-site tolerance vs pinned REF (compiler-codegen variance)
const OPEN_LOOTBOX_GAS_REF             = 0;        // executor-pinned post REF-CAPTURE first run
const OPEN_BURNIE_LOOTBOX_GAS_REF      = 0;
const RESOLVE_LOOTBOX_DIRECT_GAS_REF   = 0;
```

**Pinning protocol pattern** (Source: `Phase264GasRegression.test.js` L60-110): on first run, test prints `[REF-CAPTURE] OPEN_LOOTBOX_GAS_REF = <gasNumber>`; executor pins captured value into the literal constant; subsequent runs assert `|measured - REF| <= ENTRY_POINT_DELTA_TOLERANCE` AND `(measured - REF) <= PER_OPEN_GAS_DELTA_BOUND`.

**Imports + fixture pattern** (Source: `Phase264GasRegression.test.js` L112-120):

```javascript
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { eth, advanceToNextDay, getEvents, getLastVRFRequestId } from "../helpers/testUtils.js";
```

---

#### `test/gas/AdvanceGameGas.test.js` (EXTEND — GAS-02 v36.0 1.99× margin describe block)

**Analog:** Self. Add a v36.0-tagged describe block alongside the existing Phase 264 v35.0 block.

**Existing test structure pattern** (Source: `test/gas/AdvanceGameGas.test.js` L44-80):

```javascript
describe("AdvanceGame Gas Benchmarks", function () {
  this.timeout(600_000);
  const gasResults = [];
  after(function () {
    // Summary table emission with peak detection + 15M / 30M warnings
    // Pattern: collect (name, gasUsed) tuples; sorted descending; flag entries > 15M
    const sorted = [...gasResults].sort((a, b) => Number(b.gasUsed - a.gasUsed));
    // ...
  });
  // 9 stage-specific describe blocks (1 = STAGE_RNG_REQUESTED, 6 = STAGE_PURCHASE_DAILY,
  // 9 = STAGE_JACKPOT_COIN_TICKETS, etc.)
});
```

**v36.0 1.99× margin assertion pattern** — extend the existing v35.0 block (Phase 264 SURF-05 measured 9.42× margin at HEAD `cf564816`). Phase 266 adds a parallel describe block asserting the lootbox-resolution per-day envelope still ≥ 1.99× margin at HEAD `<266-close-sha>`. Decimator settlement is the one advanceGame-resident lootbox-resolution caller; envelope ±2K per GAS-02.

---

#### `test/stat/SurfaceRegression.test.js` (EXTEND — v36.0 SURF-01..04 describe block)

**Analog:** Self at L249-405 (existing `describe("v35.0 SURF-01..04 — protected ranges byte-identical vs v34.0 baseline 6b63f6d4")` block).

**Imports + per-line modified-set walk pattern** (Source: `test/stat/SurfaceRegression.test.js` L12-16, L260-405):

```javascript
import { expect } from "chai";
import { execSync } from "node:child_process";
import fs from "node:fs";

const V35_BASELINE = "5db8682bd7b811437f0c1cf47e832619d1478ac6";   // Phase 266 audit baseline
const LOOTBOX_PATH = "contracts/modules/DegenerusGameLootboxModule.sol";
const ENTROPY_PATH = "contracts/libraries/EntropyLib.sol";
const JACKPOT_PATH = "contracts/modules/DegenerusGameJackpotModule.sol";
const MINT_PATH    = "contracts/modules/DegenerusGameMintModule.sol";
```

**PROTECTED_RANGES array pattern** (Source: `SurfaceRegression.test.js` L260-297 — `{name, lo, hi}` object shape with baseline-side line numbers):

```javascript
// Phase 266 v36.0 SURF-01..04 PROTECTED_RANGES — baseline-side (`5db8682b`) line numbers.
// SURF-01: EntropyLib.sol body BYTE-IDENTICAL (whole file).
// SURF-02: BAF jackpot _jackpotTicketRoll body L2186-2229.
// SURF-03: MintModule L652 single-line callsite.
// SURF-04: 9 non-lootbox JackpotModule EntropyLib callsites (single-line each).
const SURF_01_PROTECTED_RANGES = [
  { name: "EntropyLib.sol body L1-43 (SURF-01 — ENT-04 stable API)", lo: 1, hi: 43 },
];
const SURF_02_PROTECTED_RANGES = [
  { name: "_jackpotTicketRoll body L2186-2229 (SURF-02 — ENT-05 deferral)", lo: 2186, hi: 2229 },
];
const SURF_03_PROTECTED_RANGES = [
  { name: "MintModule L652 EntropyLib.hash2(entropy, rollSalt) (SURF-03)", lo: 652, hi: 652 },
];
const SURF_04_PROTECTED_RANGES = [
  { name: "L285 EntropyLib.hash2(rngWord, targetLvl) (SURF-04)", lo: 285, hi: 285 },
  { name: "L453 EntropyLib.hash2(randWord, lvl) (SURF-04)",      lo: 453, hi: 453 },
  { name: "L532 EntropyLib.hash2(randWord, lvl) (SURF-04)",      lo: 532, hi: 532 },
  { name: "L610 EntropyLib.hash2(randWord, lvl) (SURF-04)",      lo: 610, hi: 610 },
  { name: "L612 EntropyLib.hash2(randWord, sourceLevel) (SURF-04)", lo: 612, hi: 612 },
  { name: "L886 EntropyLib.hash2(randWord, lvl) (SURF-04)",      lo: 886, hi: 886 },
  { name: "L1176 EntropyLib.hash2(randWord, lvl) (SURF-04)",     lo: 1176, hi: 1176 },
  { name: "L1873 entropy = EntropyLib.hash2(entropy, s) (SURF-04)", lo: 1873, hi: 1873 },
  { name: "L2192 entropy = EntropyLib.entropyStep(entropy) — BAF (SURF-04 entry inside SURF-02 range)", lo: 2192, hi: 2192 },
];
```

**Per-line modified-set walk pattern** (Source: `SurfaceRegression.test.js` L320-404 — single canonical algorithm):

```javascript
// D-IMPL-11 soft-skip on unreachable baseline + fail-loud-on-empty-diff guard.
let baselineReachable = false;
try {
  execSync(`git rev-parse --verify ${V35_BASELINE}^{commit}`, { stdio: "pipe" });
  baselineReachable = true;
} catch (_) {
  console.warn(`[v36.0 SURF] v35.0 baseline ${V35_BASELINE} not reachable — soft-skipping.`);
  this.skip();
  return;
}

const headSha = execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
if (headSha === V35_BASELINE) {
  console.log(`[v36.0 SURF] HEAD == V35_BASELINE — protected ranges trivially preserved.`);
  return;
}

const diff = execSync(`git diff ${V35_BASELINE} HEAD -- ${PATH}`, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
expect(diff.length > 0, `[v36.0 SURF] empty diff with HEAD ≠ baseline — D-IMPL-11 fail-loud.`).to.equal(true);

// Walk diff: parse hunk headers `@@ -<oldStart>,<oldLen> +<newStart>,<newLen> @@`;
// advance OLD cursor by 1 for ` ` (context) and `-` (deletion); record `-` lines as "modified OLD lines".
const hunkHeaderRe = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/;
const lines = diff.split("\n");
const modifiedOldLines = new Set();
let oldCursor = -1;
let inHunk = false;
for (const ln of lines) {
  const headerMatch = hunkHeaderRe.exec(ln);
  if (headerMatch) { oldCursor = Number(headerMatch[1]); inHunk = true; continue; }
  if (!inHunk) continue;
  if (ln.startsWith("\\")) continue;
  const tag = ln.length > 0 ? ln[0] : " ";
  if (tag === " ")       { oldCursor += 1; }
  else if (tag === "-")  { modifiedOldLines.add(oldCursor); oldCursor += 1; }
  else if (tag === "+")  { /* insertion only — OLD cursor does not advance */ }
  else                   { inHunk = false; }
}

for (const range of PROTECTED_RANGES) {
  for (let line = range.lo; line <= range.hi; line++) {
    expect(modifiedOldLines.has(line),
      `Baseline line ${line} (inside "${range.name}" [${range.lo}-${range.hi}]) was modified vs ${V35_BASELINE}`)
      .to.equal(false);
  }
}
```

---

### Wave 3-5 — Audit Deliverable + KI Edit + Closure Flips

#### `audit/FINDINGS-v36.0.md` (NEW — 9-section single canonical deliverable)

**Analog:** `audit/FINDINGS-v35.0.md` (562 lines; identical 9-section template per D-266-FILES-01 / D-265-FILES-01 carry).

**Frontmatter pattern** (Source: `audit/FINDINGS-v35.0.md` L1-20):

```yaml
---
phase: 266-lootbox-entropy-refactor
plan: 01
milestone: v36.0
milestone_name: Lootbox-Path Entropy Refactor
head_anchor: <266-close-sha>
audit_baseline: 5db8682bd7b811437f0c1cf47e832619d1478ac6
audit_baseline_signal: MILESTONE_V35_AT_HEAD_5db8682bd7b811437f0c1cf47e832619d1478ac6
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
deliverable: audit/FINDINGS-v36.0.md
requirements: [ENT-01, ENT-02, ENT-03, ENT-04, ENT-05, ENT-06,
               STAT-01, STAT-02, STAT-03,
               GAS-01, GAS-02,
               SURF-01, SURF-02, SURF-03, SURF-04,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Phase 266 introduces 1 batched contract commit + N batched test commits, all USER-APPROVED per feedback_no_contract_commits.md + feedback_batch_contract_approval.md. KNOWN-ISSUES.md modified by 1 entry per AUDIT-05 (EntropyLib XOR-shift entry rephrased to BAF-only scope)."
supersedes: none
status: FINAL — READ-ONLY
read_only: true
closure_signal: MILESTONE_V36_AT_HEAD_<266-close-sha>
generated_at: 2026-05-10T..:..:..Z
---
```

**Section structure pattern** — 9 sections per `audit/FINDINGS-v35.0.md` (line ranges to copy structural skeleton from):

| § | Title                                                       | v35 Source Lines | Phase 266 Adaptation |
|---|-------------------------------------------------------------|------------------|----------------------|
| 1 | Frontmatter + Audit Baseline + Scope + Write Policy         | L1-30            | Substitute v35→v36 milestone IDs; enumerate Phase 266 commits (1 contract + N tests) |
| 2 | Executive Summary (Closure Verdict + Severity Counts + D-08 + D-09 + Forward-Cite + Attestation Anchor) | L32-91 | Default zero F-36-NN per D-265-FIND-01 carry; AUDIT-05 swap for v35's AUDIT-06 row |
| 3 | Per-Phase Sections (3a 263 + 3b 264 + 3c AUDIT-06 + 3d AUDIT-01 delta-surface + 3e AUDIT-03 conservation) | L93-261 | §3a Phase 266 only (single phase); §3d AUDIT-01 delta-surface table for LootboxModule; §3e AUDIT-03 lootbox payouts conservation re-proof; §3c likely UNNEEDED (no v34→v35-style indexer semantic-shift) |
| 4 | F-36-NN Finding Blocks + 4.1 Adversarial Sweep 6-Surface Table + 4.2 Verdict Roll-Up | L264-318 | Surfaces (a) modulo-bias / (b) seed-reuse cross-correlation / (c) hash2 chunk-collision-free / (d) gas-griefing / (e) BAF byte-identity (ENT-05 verification) / (f) commitment-window check |
| 5 | Regression Appendix (5a REG-01 v34→v35 + 5b REG-02 v33 + 5c REG-04 spot-check + 5d distribution summary) | L322-367 | 5a REG-01 v35.0 carry-forward; 5b REG-02 v34.0 carry-forward; 5c REG-04 spot-check across v25..v35 |
| 6 | KI Gating Walk (6a Non-Promotion Ledger + 6b 4-row KI envelope + 6c verdict summary) | L371-403 | EXC-04 NARROWS to BAF-only at v36 (lootbox path no longer xorshift) |
| 7 | Prior-Artifact Cross-Cites table                            | L407-429         | Substitute Phase 263/264/265 → Phase 266 + cite 266-CONTEXT.md, 266-RESEARCH.md, 266-01-PLAN.md, 266-01-SUMMARY.md, 266-01-ADVERSARIAL-LOG.md |
| 8 | Forward-Cite Closure (8a residual + 8b emission + 8c combined verdict) | L433-475 | Phase 266 = terminal v36.0 phase; zero forward-cite emission per D-266-FCITE carry |
| 9 | Milestone Closure Attestation (9a verdict distribution + 9b attestation block + 9c closure signal + §9.NN commit-readiness register) | L479-560 | TWO-subsection §9.NN per D-266-CLOSURE-02: §9.NN.i USER-APPROVED contracts (Wave 1 commit) + §9.NN.ii USER-APPROVED tests (Wave 2 commits) + §9.NN.iii AGENT-COMMITTED audit artifacts |

**§3d AUDIT-01 delta-surface table pattern** (Source: `FINDINGS-v35.0.md` L202-248):

```markdown
| Declaration | Classification | Live Line(s) at HEAD | Hunk Evidence | Phase 266 REQ |
|---|---|---|---|---|
| `_rollTargetLevel(uint24 baseLevel, uint256 seed)` | MODIFIED_LOGIC (signature change: drop `nextEntropy` return) | live L<NEW>-<NEW> | `git diff 5db8682b..HEAD ...` shows L809-827 hunk | ENT-01 |
| `_resolveLootboxRoll(... uint256 seed)` | MODIFIED_LOGIC (4 entropyStep callsites replaced; L1585 dead advance DELETED) | live L<NEW>-<NEW> | hunk evidence | ENT-02 |
| `_lootboxTicketCount(... uint256 seed)` | MODIFIED_LOGIC (L1635 entropyStep replaced) | live L<NEW>-<NEW> | hunk evidence | ENT-03 |
| Inline NatSpec bit-budget block (per refactored function) | NEW | live (NatSpec) | hunk evidence | ENT-06 |
| `EntropyLib.sol` body | REFACTOR_ONLY (zero changes) | L1-43 | `git diff` returns empty per SURF-01 | ENT-04 |
```

Plus Part B grep recipe + Part C AUDIT-04 zero-new-state attestation (5 orthogonal grep-reproducible checks per `FINDINGS-v35.0.md` L236-247).

**§4 6-surface table pattern** (Source: `FINDINGS-v35.0.md` L270-313 — surface (a)..(f) verdict + grep-recipe + prose justification per row):

```markdown
**Surface (a) — Bit-slice modulo-bias bound per draw within documented bound.**

- **Verdict:** SAFE_BY_DESIGN
- **Grep recipe / line cite:** Bit-budget table at §3a; per-consumer slice + bias documented inline (NatSpec) per ENT-06; STAT-01 chi² cross-cite at `test/stat/LootboxEntropyDistribution.test.js`.
- **Prose justification:** Per D-266-BIT-BUDGET-01: every `% small` slice has documented bias ≤ 1%. ... [STAT-01 empirical proof] ... [feedback_rng_backward_trace cite].

**Surface (b) — Seed-reuse cross-correlation across sub-rolls within same resolution.**
... 6 rows total (a)..(f) per RESEARCH.md AUDIT-02 surface enumeration.
```

**§9.NN commit-readiness register TWO-subsection pattern** (Source: `FINDINGS-v35.0.md` L517-559):

```markdown
### 9.NN Commit-Readiness Register

#### 9.NN.i USER-APPROVED contracts (1 commit)

\`\`\`
<sha>  feat(266): lootbox-path entropy refactor [ENT-01..06]
\`\`\`

User-approval audit trail per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`: Phase 266 single batched contract-tree commit, user explicitly approved diff before commit ran.

#### 9.NN.ii USER-APPROVED tests (N commits — re-enumerated via `git log --oneline 5db8682b..HEAD -- test/ package.json`)

\`\`\`
<sha>  test(266): chi² + gas + surface preservation [STAT-01..03 + GAS-01..02 + SURF-01..04]
... (additional test commits if split by file)
\`\`\`

#### 9.NN.iii AGENT-COMMITTED audit artifacts

\`\`\`
... (Phase 266 plan-close commits — atomic-commit-per-task chain for §1-§9 deliverable + KNOWN-ISSUES.md edit + ROADMAP/STATE/MILESTONES flips + 266-01-SUMMARY.md)
\`\`\`
```

---

#### `KNOWN-ISSUES.md` (MODIFY 1 entry — EntropyLib XOR-shift to BAF-only)

**Analog:** Self at HEAD `5db8682b`, L31 (current entry).

**Current entry text** (Source: `KNOWN-ISSUES.md` L31):

```
**EntropyLib XOR-shift PRNG for lootbox outcome rolls.** `EntropyLib.entropyStep()` uses a 256-bit XOR-shift PRNG (shifts 7/9/8) for lootbox outcome derivation (target level, ticket counts, BURNIE amounts, boons). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded per-player, per-day, per-amount via `keccak256(rngWord, player, day, amount)` where `rngWord` is VRF-derived. The small number of entropy steps per resolution (5-10) and modular arithmetic over small ranges further mask any non-uniformity.
```

**Proposed v36-close prose** (Source: `266-CONTEXT.md <specifics>` block — planner refines):

```
**EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls.** `EntropyLib.entropyStep()` (256-bit XOR-shift, shifts 7/9/8) is consumed by `_jackpotTicketRoll` (`DegenerusGameJackpotModule.sol:2186-2229`) for BAF jackpot ticket-distribution path (target level + offset selection per ticket). XOR-shift has known theoretical weaknesses (cannot produce zero state, fixed cycle, correlated consecutive outputs). Exploitation is infeasible: the PRNG is seeded by VRF-derived `keccak256` mix at the upstream call boundary; the single per-ticket step + modular arithmetic over small ranges (`% 100` + `% 4` / `% 46`) mask any non-uniformity. Lootbox-path consumption was removed at v36.0 per Phase 266 refactor (now uses bit-sliced `EntropyLib.hash2` keccak draws); remaining xorshift consumer is BAF jackpot only — candidate for future-phase refactor following the same bit-sliced keccak pattern.
```

**Edit discipline:** ONE entry rephrased; entry not removed (BAF still uses xorshift per ENT-05 deferral). Per `feedback_no_history_in_comments.md` — describes what IS at v36.0 close, not "this used to scope lootbox before v36". The "Lootbox-path consumption was removed at v36.0" sentence is a forward-disclosure (current scope clarification + future-phase pointer), not a code-history annotation.

---

#### `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` (UPDATE — v36.0 SHIPPED)

**Analog:** `.planning/phases/265-delta-audit-findings-consolidation/265-01-SUMMARY.md` + the v35.0 closure-flip commit pattern visible in `git log` (commit `85539a0f docs(265): Task 14 — close v35.0 — READ-only FINDINGS + ROADMAP/STATE/MILESTONES flips + 265-01-SUMMARY [MILESTONE_V35_AT_HEAD_5db8682b]`).

**Closure-flip pattern** (per the v35.0 close commit):

- ROADMAP.md: flip Phase 266 status to SHIPPED; emit closure-signal paragraph `MILESTONE_V36_AT_HEAD_<sha>`; demote v35.0 from "current milestone" to "prior shipped milestone".
- STATE.md: update `Last Shipped Milestone = v36.0`; demote v35.0 entry; update STATUS / Last Activity; reset to next-phase-ready state.
- MILESTONES.md: prepend v36.0 entry to top with closure-signal recorded.
- Closure-signal SHA captured AT FINAL §9 commit per RESEARCH.md Pitfall 4 (use placeholder `<sha>` literal during early §9 task drafting; resolve via `git rev-parse HEAD` after the §9b/§9c attestation commit lands; atomic-update task replaces all 5 occurrences across §9c + ROADMAP + STATE + MILESTONES + 266-01-SUMMARY).

---

#### `.planning/phases/266-*/266-01-SUMMARY.md` + `266-01-ADVERSARIAL-LOG.md` (NEW phase artifacts)

**Analogs:**
- `266-01-SUMMARY.md` ← `.planning/phases/265-delta-audit-findings-consolidation/265-01-SUMMARY.md`
- `266-01-ADVERSARIAL-LOG.md` ← `.planning/phases/265-delta-audit-findings-consolidation/265-01-ADVERSARIAL-LOG.md`

**Adversarial-log shape pattern** (Source: `265-01-ADVERSARIAL-LOG.md` L1-80; full file is the canonical template):

```markdown
# Phase 266 Plan 01 — Adversarial Validation Log

**Phase:** 266-lootbox-entropy-refactor
**Plan:** 266-01
**Target:** `audit/FINDINGS-v36.0.md` §4 6-surface draft (a-f)
**Methodology:** D-266-ADVERSARIAL-01..03 (parallel `/contract-auditor` + `/zero-day-hunter` spawn AFTER finished §4 draft; NOT `/economic-analyst`, NOT `/degen-skeptic`)
**Spawned:** <date>

## /contract-auditor

[Per-row verdicts — surfaces (a) through (f); pattern per 265-01-ADVERSARIAL-LOG L13-34: AGREE / DISAGREE + verdict + concrete code-path citation + counterexample-attempt evidence]

### 7th-surface novel composition candidates investigated

[Pattern per 265-01-ADVERSARIAL-LOG L36-45: hypothesis name + investigation + why-it-fails + mechanism-strength]

### Concrete code-path counterexample audit

[Pattern per 265-01-ADVERSARIAL-LOG L46-48: line-by-line re-derivation of refactored helper; map every if/branch; assert no silent miscount, no off-by-one]

### Final verdict

[Pattern per 265-01-ADVERSARIAL-LOG L50-52: "X of X row verdicts AGREE. Zero F-36-NN finding-candidates. ..."]

## /zero-day-hunter

[Pattern per 265-01-ADVERSARIAL-LOG L54-80+: hypothesis-driven novel-surface hunt; investigation + why-it-fails + mechanism-strength per hypothesis]
```

**Disagreement-disposition rule** (per D-266-ADVERSARIAL-03 / `feedback_wait_for_approval.md`): if either skill flags a SAFE verdict OR `/zero-day-hunter` surfaces a novel composition, escalate to user inline BEFORE READ-only flip on `audit/FINDINGS-v36.0.md`. Do not silently override.

---

## Shared Patterns

### Authentication / Authorization
**N/A.** Phase 266 does not introduce new public/external mutation entry points. AUDIT-04 zero-new-state grep-recipe attestation per §3d Part C confirms zero new admin functions, zero new modifiers, zero new public/external entry points. (Vacuous since the refactor is private-helper-internal.)

### Error Handling
**Source:** `contracts/modules/DegenerusGameLootboxModule.sol` (existing patterns at HEAD `5db8682b`).
**Apply to:** Refactored `_rollTargetLevel` / `_resolveLootboxRoll` / `_lootboxTicketCount` bodies (same error patterns as pre-refactor — refactor preserves all `revert` sites byte-identically; only the entropy-derivation lines change).

### Validation
**Source:** RESEARCH.md Bit-Budget Worked Table (slice-overlap audit + cumulative bit-budget verification).
**Apply to:** Every refactored function. NatSpec bit-budget block (ENT-06) is the inline validation evidence. Test-side STAT-01 chi² uniformity per bucket is the empirical validation.

### Surface Preservation
**Source:** `test/stat/SurfaceRegression.test.js` per-line modified-set walk algorithm (single canonical pattern; reused across SURF-01..04 describe blocks at v33.0 + v34.0 + v35.0 — and now v36.0).
**Apply to:** All v36.0-closure SURF-01..04 byte-identity proofs. ZERO `-` deletions inside any PROTECTED_RANGES range vs `5db8682b` baseline.

### Closure-Signal SHA Capture
**Source:** `audit/FINDINGS-v35.0.md` §9c (Source L509-515) + RESEARCH.md Pitfall 4.
**Apply to:** All §9 tasks. Use placeholder `<sha>` literal during early §9 drafting; resolve via `git rev-parse HEAD` AFTER the final §9 commit lands; atomic-update task replaces all 5 occurrences (§9c + ROADMAP + STATE + MILESTONES + 266-01-SUMMARY).

### Adversarial-Pass Spawn Timing
**Source:** D-266-ADVERSARIAL-02 / RESEARCH.md Pitfall 5.
**Apply to:** Adversarial-pass task. Spawn `/contract-auditor` + `/zero-day-hunter` in parallel as a SINGLE message, AFTER the full §4 inline draft is complete. Both red-team the FINISHED §4 draft (do not re-derive from scratch). Log spawn message + responses in `266-01-ADVERSARIAL-LOG.md`.

### Forward-Cite Zero-Emission
**Source:** `audit/FINDINGS-v35.0.md` §8a + §8b grep recipes (Source L441-469) + D-266-FCITE carry of D-265-FCITE-01.
**Apply to:** §8 tasks. Verification recipe:

```bash
grep -rE 'forward-cite|defer-to-Phase-267|TBD-post-milestone' \
  audit/FINDINGS-v36.0.md \
  .planning/phases/266-lootbox-entropy-refactor/
# Expected: zero matches qualifying as Phase-266-emitted forward-cites.
```

Note: literal "v37.0+" string occurrences in §1 / §2 / §8 meta-prose discussing the terminal-phase invariant are NOT forward-cites — they are self-referential to the closure-invariant discipline. Domain-specific token grep is the load-bearing audit invariant.

### Bit-Budget NatSpec (ENT-06 — inline documentation)
**Source:** RESEARCH.md Code Examples + `266-CONTEXT.md <specifics>`.
**Apply to:** Every refactored function in `DegenerusGameLootboxModule.sol`. Minimum: which bits each `% small` consumes + any `hash2(seed, N)` chunk usage. Pattern: 3-line `// Bit budget:` comment naming each sub-roll's bit slice + bias.

### REF-CAPTURE + ENTRY_POINT_DELTA_TOLERANCE Protocol
**Source:** `test/gas/Phase264GasRegression.test.js` L99-110 (constants) + L60-110 (header documentation).
**Apply to:** GAS-01 entry-point assertion in `LootboxOpenGas.test.js`. Theoretical worst-case derivation FIRST (header comment block, opcode-by-opcode); REF placeholder `0` until first run; executor pins captured value; subsequent runs assert `|measured - REF| <= ENTRY_POINT_DELTA_TOLERANCE = 2000` AND `(measured - REF) <= PER_OPEN_GAS_DELTA_BOUND = 300`.

### Single-Plan Multi-Task Atomic-Commit-Per-Task
**Source:** D-266-PLAN-01 carry of v33 Phase 257 / v34 Phase 262 / v35 Phase 265.
**Apply to:** `266-01-PLAN.md` task ordering. ~21 tasks across 5 sequential waves per RESEARCH.md Plan Decomposition Recommendation (Wave 1 contracts ⇒ Wave 2 tests ⇒ Wave 3 audit §1-§4 ⇒ Wave 4 audit §5-§8 ⇒ Wave 5 §9 closure + flips). USER-APPROVAL gates at end of Wave 1 (contract diff) + end of Wave 2 (test diff) + end of Wave 5 (final review per `feedback_manual_review_before_push.md`). Wave 3 ends with adversarial-pass at Task 14 (full §4 draft FIRST, then parallel skill spawn).

---

## No Analog Found

**None.** Every in-scope file has a concrete in-repo analog at HEAD `5db8682b`. The only "no-direct-analog" surface is the bit-slice refactor pattern itself (`uint16(seed) % 100` etc. is novel to Phase 266 in this repo) — but this surface is fully specified by `266-CONTEXT.md <specifics>` block + `266-RESEARCH.md` Bit-Budget Worked Table + Code Examples (a Solidity-level pattern with no library precedent in the repo since EntropyLib is the abstraction layer being bypassed).

---

## Metadata

**Analog search scope:**
- `contracts/modules/DegenerusGameLootboxModule.sol` (refactor subject — read L800-1700 for sub-call enumeration)
- `contracts/libraries/EntropyLib.sol` (full file, 43 lines — SURF-01 protected)
- `contracts/modules/DegenerusGameJackpotModule.sol` (read SURF-02 + SURF-04 line ranges)
- `contracts/modules/DegenerusGameMintModule.sol` (read L652 — SURF-03)
- `test/stat/PerPullLevelDistribution.test.js` (chi² infra origin)
- `test/stat/SurfaceRegression.test.js` (per-line modified-set walk)
- `test/gas/Phase264GasRegression.test.js` (REF-CAPTURE + theoretical worst case)
- `test/gas/AdvanceGameGas.test.js` (advanceGame stage benchmarks)
- `audit/FINDINGS-v35.0.md` (deliverable shape — 9 sections; primary template)
- `audit/FINDINGS-v34.0.md` (secondary template)
- `KNOWN-ISSUES.md` (entry-edit subject)
- `.planning/phases/265-delta-audit-findings-consolidation/265-01-ADVERSARIAL-LOG.md` (adversarial-log template)
- `.planning/phases/265-delta-audit-findings-consolidation/265-01-SUMMARY.md` (closure-summary template)

**Files scanned:** 13 (10 read directly into context; 3 via `git log` and `grep` recipes referenced in RESEARCH.md).

**Pattern extraction date:** 2026-05-10.

**Valid until:** Phase 266 execute-phase close. Re-verify analogs against HEAD if execution slips past 2026-06-10 (30-day window — same as RESEARCH.md validity).
