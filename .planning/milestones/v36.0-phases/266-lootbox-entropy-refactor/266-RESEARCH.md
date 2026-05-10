# Phase 266: Lootbox-Path Entropy Refactor — Research

**Researched:** 2026-05-10
**Domain:** Solidity 0.8.34 PRNG refactor (XOR-shift → bit-sliced keccak) + chi² statistical validation + gas regression + 9-section delta-audit deliverable
**Confidence:** HIGH (locked CONTEXT.md decisions; all references VERIFIED via repo grep; precedent shape proven across v33/v34/v35)

---

## Summary

Phase 266 is a single-phase patch that closes v36.0 with one batched contract commit (lootbox-path xorshift → bit-sliced keccak refactor in `DegenerusGameLootboxModule.sol`), N batched test commits (chi² + gas + cross-surface byte-identity), and an agent-authored 9-section `audit/FINDINGS-v36.0.md` deliverable. The deliverable shape is locked verbatim from v33/v34/v35 precedent (D-265 carry chain). The contract scope is narrow and surgical: 7 named `EntropyLib.entropyStep` callsites in one file; everything else byte-identical (verified by SURF-01..04 grep-proof). All locked decisions live in `266-CONTEXT.md` — research role here is to surface concrete bit-budget arithmetic, chi² sample-budget calibration, gas snapshot mechanics, surface-preservation methodology, and audit deliverable scaffolding the planner needs to author atomic-commit task ordering.

**Primary recommendation:** Single multi-task plan with ~12-14 atomic-commit-per-task ordering (mirrors v35 Phase 265's 14-task / v34 Phase 262's pattern), grouped into 5 sequential waves: (1) contract refactor [batched, USER-APPROVED at end], (2) chi² + gas + surface tests [batched, USER-APPROVED at end], (3) §1-§4 audit deliverable [AGENT-COMMITTED atomic per task], (4) §5-§8 audit deliverable + adversarial-pass [AGENT-COMMITTED], (5) §9 closure attestation + KNOWN-ISSUES.md edit + ROADMAP/STATE/MILESTONES flips + final user-review gate + READ-only flip [AGENT-COMMITTED].

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Refactor pattern:**
- **D-266-API-01** (no EntropyLib helper additions): `EntropyLib.entropyStep` and `EntropyLib.hash2` bodies stay byte-identical; no `byteAt` / `uint16At` / `uint24At` style helpers added. Each consumer in `DegenerusGameLootboxModule.sol` uses inline `uint8(seed)`, `uint16(seed)`, `uint24(seed)`, `uint8(seed >> 8)`, etc.
- **D-266-SEED-01** (single-keccak-per-resolution + overflow fallback): Each lootbox-resolution invocation derives ONE 256-bit seed at the entry point of `_resolveLootboxCommon` via `EntropyLib.hash2(rngWord, structured-input)`. Threaded as a function parameter. Falls back to second 256-bit chunk via `EntropyLib.hash2(seed, 1)` ONLY if a single resolution exceeds the per-call bit budget (~80-128 bits typical; 256-bit headroom is ample).
- **D-266-BIT-BUDGET-01** (per-consumer bit-budget targets — ≤ 1% modulo bias): `% 5` → 8 bits (bias 0.39%); `% 100` → 16 bits (bias 0.05%); `% 46` → 16 bits (bias 0.05%); `% 20` → 16 bits (bias 0.02%); `% 10000` → 24 bits (bias 0.045%); `% 4` → 8 bits.
- **D-266-CONSUMER-LIST-01**: Exact 7 callsites in scope at L813, L817, L1548, L1569, L1585, L1599, L1635 of `DegenerusGameLootboxModule.sol` (HEAD `5db8682b`). Plus enumeration of any sub-call paths inside `_resolveLootboxCommon` that consume `entropy` and chain (boon roll, whale-pass roll, lazy-pass roll, presale BURNIE multiplier roll) — planner enumerates by reading L847-1000+.

**Out-of-scope:**
- **D-266-SCOPE-OUT-01** BAF jackpot `_jackpotTicketRoll` (JackpotModule:2186-2229) deferred (ENT-05). SURF-02 verifies byte-identity at v36.0 close.
- **D-266-SCOPE-OUT-02** No EntropyLib API additions (D-266-API-01).
- **D-266-SCOPE-OUT-03** No behavioral-replay tests; uniformity-equivalence only (per user disposition).
- **D-266-SCOPE-OUT-04** KNOWN-ISSUES.md "Lootbox RNG uses index advance" entry — planner's call whether to address inside Phase 266 or as standalone post-v36 cleanup.

**Adversarial pass:**
- **D-266-ADVERSARIAL-01** `/contract-auditor` + `/zero-day-hunter` only. NOT spawning `/economic-analyst` or `/degen-skeptic`.
- **D-266-ADVERSARIAL-02** Sequential after full §4 draft. Spawn parallel as single message; both red-team the FINISHED §4 draft.
- **D-266-ADVERSARIAL-03** Disagreement disposition: surface to user inline; user decides verdict before READ-only flip.

**Deliverable shape:**
- **D-266-FILES-01** Single canonical `audit/FINDINGS-v36.0.md` with all 9 sections embedded. No per-AUDIT-NN working files.
- **D-266-CLOSURE-01** Closure signal SHA = `git rev-parse HEAD` at audit-pass-close commit (mutation-inclusive HEAD).
- **D-266-CLOSURE-02** TWO-subsection §9.NN format: §9.NN.i USER-APPROVED contracts (1 batched commit) + §9.NN.ii USER-APPROVED tests (N test commits) + §9.NN.iii AGENT-COMMITTED audit artifacts. NO §9.NN.iv awaiting-approval subsection.
- **D-266-PLAN-01** Single multi-task plan (mirrors v33/v34/v35).

**Approval posture:**
- **D-266-APPROVAL-01** `audit/` + `.planning/` + ROADMAP/STATE/MILESTONES land in atomic-commit chain by agent. User reviews `audit/FINDINGS-v36.0.md` before push per `feedback_manual_review_before_push.md`.
- **D-266-APPROVAL-02** Contract + test commits USER-APPROVED batched. Agent does NOT pre-approve any contract change. Present batched diff at end of impl-task block; wait for explicit user "approved" before commit.

**Severity rubric:** D-266-SEV-01 carry-forward of D-08 5-bucket rubric.

### Claude's Discretion

- Test file structure: `test/stat/LootboxEntropyDistribution.test.js` (NEW) for chi² + gas test extension or new file. Planner picks single vs split.
- Bit-slice ordering convention (low-to-high vs grouped by sub-function). Consumer-side comments document mapping.
- `hash2(seed, N)` chunk indexing scheme (counter-tagged or string-tagged). AUDIT-02 surface (c) verifies collision-free across consumers.
- NatSpec depth on refactored functions.
- §3 per-phase section structure (Phase 266 is its own only-phase; single §3a section covering implementation + tests + KNOWN-ISSUES.md edit; §3d AUDIT-01 delta-surface table; §3e AUDIT-03 conservation re-proof; §3c likely not needed).
- REG-04 row count (defensive grep across audit/FINDINGS-v25..v35).

### Deferred Ideas (OUT OF SCOPE)

- BAF jackpot `_jackpotTicketRoll` xorshift refactor (ENT-05; future-phase candidate).
- KNOWN-ISSUES.md "Lootbox RNG uses index advance isolation" entry rephrase (separate cleanup; planner's call whether in Phase 266 or post).
- v35.0 milestone archive rotation (`v35.0-ROADMAP.md` + `v35.0-phases/` directory rotation deferred).
- Audit of post-v32.0 unaudited commits `002bde55`, `2713ce61` (carry-forward deferral v33→v34→v35→v36 close).
- `/economic-analyst` + `/degen-skeptic` adversarial-skill expansion.
- Behavioral-replay tests.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENT-01 | `_rollTargetLevel` (L809-827) replace L813 + L817 `entropyStep` calls with bit-sliced reads from a single keccak seed | Bit-budget table below: rangeRoll → bits[0..15] (% 100); near-offset → bits[16..23] (% 5); far-offset → bits[24..39] (% 46) — 40 bits total |
| ENT-02 | `_resolveLootboxRoll` (L1530-1616) replace L1548 + L1569 + L1585 + L1599 with bit-sliced reads from threaded seed | Bit-budget table: pathRoll → 16 bits (% 20); DGNRS path → 10 bits (% 1000 — see L1680); WWXRP path → unused (literal LOOTBOX_WWXRP_PRIZE); large-BURNIE varianceRoll → 16 bits (% 20); presale-multiplier flag — no entropy |
| ENT-03 | `_lootboxTicketCount` (L1626-1669) replace L1635 with `uint24(seed >> N) % 10_000` slice | Bit-budget: 24 bits (bias 0.045%) |
| ENT-04 | EntropyLib API stable; no new helpers | Verified via grep — `entropyStep` + `hash2` are the only two functions; both bodies are 7 lines + 7 lines respectively |
| ENT-05 | BAF jackpot `_jackpotTicketRoll` OUT of scope | Verified at JackpotModule:2186-2229; single `entropyStep` at L2192 + `% 100` + `% 4` / `% 46` |
| ENT-06 | Bit-budget per consumer documented inline (NatSpec) | Pattern in CONTEXT.md `<specifics>` block |
| STAT-01 | Per-sub-roll uniformity chi² confirms uniform draws | Existing chi² infra at `test/stat/PerPullLevelDistribution.test.js` (L78-102): `makeRng` + `CHI2_CRIT_05[1..7]` + `wilsonHilfertyZ` — see Validation Architecture below |
| STAT-02 | Pre-/post distribution shape preserved | Light JS-replica chi² (no on-chain replay against v35 baseline) |
| STAT-03 | Reuse Phase 261/264 chi² infrastructure | `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim in new test file header per established pattern |
| GAS-01 | `openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` per-open ±300 g | New test file or extend `test/gas/Phase264GasRegression.test.js` pattern: REF-CAPTURE + ENTRY_POINT_DELTA_TOLERANCE + theoretical-worst-case opcode walk first |
| GAS-02 | `advanceGame` ±2K, 1.99× margin preserved | Extend `test/gas/AdvanceGameGas.test.js` (already carries v34/v35 1.99× margin assertion per Phase 264 SURF-05) |
| SURF-01 | `EntropyLib.sol` body byte-identical | `git diff <baseline>..HEAD -- contracts/libraries/EntropyLib.sol` returns empty — methodology proven at v33 §5b GNRUS / v34 §6b row 4 / v35 SURF-01 |
| SURF-02 | BAF jackpot `_jackpotTicketRoll` byte-identical (ENT-05 deferral discipline) | Per-line modified-set walk vs `git diff` for line range [2186, 2229] inside `DegenerusGameJackpotModule.sol` — methodology in `test/stat/SurfaceRegression.test.js` v35.0 describe block (PROTECTED_RANGES array pattern) |
| SURF-03 | MintModule L652 byte-identical | Per-line walk for L652 (`EntropyLib.hash2(entropy, rollSalt)` callsite) |
| SURF-04 | Non-lootbox JackpotModule callsites byte-identical (L285, L453, L532, L610, L612, L886, L1176, L1873, L2192) | Per-line walk for the 9 lines |
| AUDIT-01 | Delta-surface table | Mirror v35 §3d Part A table (10 rows) — each modified declaration in `DegenerusGameLootboxModule.sol` classified {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED} |
| AUDIT-02 | Adversarial sweep verdicts every refactor surface | Mirror v35 §4 6-surface table — surfaces: (a) bit-slice modulo-bias bound, (b) seed-reuse cross-correlation, (c) `hash2(seed, N)` chunk-collision-free, (d) gas-griefing delta bounded, (e) BAF byte-identity (ENT-05 verification), (f) commitment-window check |
| AUDIT-03 | Conservation re-proof | Mirror v35 §3e — lootbox payouts (BURNIE / DGNRS / WWXRP / tickets) preserved within statistical uniformity vs xorshift baseline; no new mint sites; solvency invariant unchanged |
| AUDIT-04 | Zero-new-state scan | 5 grep-reproducible checks per v35 §3d Part C: storage slots / public-fn entry points / admin functions / modifiers / EntropyLib API stable |
| AUDIT-05 | `audit/FINDINGS-v36.0.md` published; `MILESTONE_V36_AT_HEAD_<sha>` emitted §9c; KNOWN-ISSUES.md EntropyLib XOR-shift entry rephrased to BAF-only scope | Proposed rephrasing prose in CONTEXT.md `<specifics>` |
| REG-01 | v35.0 closure signal `MILESTONE_V35_AT_HEAD_5db8682b` non-widening at v36 HEAD | Mirror v35 §5a single-row PASS table — verify v35 surfaces (per-pull-level resample helper + `_awardDailyCoinToTraitWinners` + 2 callsites + `COIN_LEVEL_TAG`) byte-identical at v36 HEAD |
| REG-02 | v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` non-widening | Mirror v35 §5b single-row PASS — verify TraitUtils + `_pickSoloQuadrant` injection sites + JackpotBucketLib byte-identical at v36 HEAD |
| REG-03 | KI envelope re-verifications. EXC-04 NARROWS to BAF-only | Mirror v35 §6b — EXC-01..03 NEGATIVE-scope; EXC-04 NARROWS (lootbox-path xorshift removed; remaining consumer is BAF jackpot only) |
| REG-04 | Prior-finding spot-check | Mirror v35 §5c — defensive grep walk across audit/FINDINGS-v25..v35 for findings referencing v36-touched function set |

</phase_requirements>

---

## Architectural Responsibility Map

Single-tier on-chain solidity (no client/server tiers). Capability-to-module map:

| Capability | Primary Surface | Secondary Surface | Rationale |
|------------|-----------------|-------------------|-----------|
| Lootbox entropy generation (refactor target) | `DegenerusGameLootboxModule.sol` 7 callsites | — | Sole site of xorshift consumption that ENT-01..03 modifies |
| Per-resolution seed derivation | `EntropyLib.hash2` (existing keccak primitive) | `DegenerusGameLootboxModule.sol` (caller) | Library API stable per ENT-04 |
| BAF jackpot ticket entropy (ENT-05 deferral) | `DegenerusGameJackpotModule.sol` `_jackpotTicketRoll` (L2186-2229) | — | Same xorshift pattern; explicitly out-of-scope |
| Statistical validation | `test/stat/LootboxEntropyDistribution.test.js` (NEW) | Reuse `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` from `test/stat/TraitDistribution.test.js` (Phase 261 origin) | STAT-03 reuse-existing-tooling discipline |
| Gas regression | `test/gas/LootboxOpenGas.test.js` (NEW) OR extension of `Phase264GasRegression.test.js` | `test/gas/AdvanceGameGas.test.js` (already carries 1.99× margin — extend with v36.0 row) | GAS-01 + GAS-02 |
| Cross-surface byte-identity grep-proof | `test/stat/SurfaceRegression.test.js` (extend with v36.0 describe block) | — | SURF-01..04 |
| Audit deliverable | `audit/FINDINGS-v36.0.md` (single canonical, 9 sections) | — | D-266-FILES-01 |
| Closure flips | `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` + `KNOWN-ISSUES.md` | — | AUDIT-05 + Phase-close discipline |

---

## Standard Stack

### Core (verified at HEAD `5db8682b` via repo grep)

| Component | Version / Path | Purpose | Verification |
|-----------|----------------|---------|--------------|
| Solidity compiler | 0.8.34 | Contract language | `[VERIFIED: contracts/libraries/EntropyLib.sol L2 `pragma solidity 0.8.34`]` |
| Foundry | (lockfile present) | Forge testing + gas snapshots | `[VERIFIED: foundry.lock present at repo root]` |
| Hardhat | (`hardhat.config.js`) | Primary test runner (existing `.test.js` files) | `[VERIFIED: all `test/**/*.test.js` use `import hre from 'hardhat'`]` |
| Mocha + Chai | via Hardhat toolbox | JS test framework | `[VERIFIED: `import { expect } from 'chai';` in test files]` |
| Ethers v6 | via `hre.ethers` | Keccak helpers, ABI coding | `[VERIFIED: `hre.ethers.keccak256(...)` in chi² helpers]` |
| `@nomicfoundation/hardhat-toolbox/network-helpers.js` | bundled | `loadFixture` + `restoreAddresses` pattern | `[VERIFIED: import in `test/stat/PerPullLevelDistribution.test.js` L45-51]` |

### Supporting (already wired into existing test infrastructure)

| Component | Location | Purpose |
|-----------|----------|---------|
| `makeRng(seed)` deterministic PRNG | `test/stat/TraitDistribution.test.js` L48-56 (origin); re-declared verbatim in `test/stat/PerPullLevelDistribution.test.js` L78-87 | Cryptographically-uniform `keccak256(seed||counter)` PRNG for chi² bucketing |
| `CHI2_CRIT_05` table df=1..7 | `test/stat/TraitDistribution.test.js` L87-90 | Critical values at α=0.05 for low-df chi² tests |
| `wilsonHilfertyZ(chi2, df)` | `test/stat/TraitDistribution.test.js` L97-100 | One-sided right-tail Wilson-Hilferty Z approximation for HIGH-df chi² (df > 7) — REQUIRED for `% 100` (df=99), `% 46` (df=45), `% 10000` (df=9999) buckets |
| `deployFullProtocol` fixture | `test/helpers/deployFixture.js` | Full-protocol deployment + RNG simulation |
| `MockVRFCoordinator` | `contracts/mocks/MockVRFCoordinator.sol` | VRF fulfillment with deterministic seed |
| `getEvents(tx, contract, name)` | `test/helpers/testUtils.js` | Event harvest for boundary-harness validation |
| `git diff <baseline>..HEAD -- <file>` | bash | Per-line modified-set walk for SURF-01..04 byte-identity grep-proof |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JS-replica chi² | On-chain Forge invariant testing | JS-replica is faster (sub-second per 10K samples), reproducible via fixed seed, and aligns with established Phase 261/264 precedent. Forge invariant testing would add tooling overhead with no correctness benefit. **REJECTED — use JS-replica per STAT-03.** |
| New EntropyLib helpers (`byteAt` / `uint16At` / `uint24At`) | Inline `uint8(seed)`, `uint16(seed)`, `uint24(seed)` shifts | Helpers cost function-dispatch overhead (~24 g per call × 5-7 draws = 120-170 g per resolution = ~50% of the ±300 g GAS-01 budget). Inline is cheaper. **LOCKED OUT per D-266-API-01.** |
| Behavioral-replay test (specific-outcome equivalence to v35) | Light statistical chi² only | Replay would require pre-refactor binary resurrection + matching VRF replay infrastructure. Per user disposition: not required. **LOCKED OUT per D-266-SCOPE-OUT-03.** |
| Multi-plan split (266-01 contract + 266-02 audit) | Single multi-task plan | Cleaner ownership boundaries; costs N× plan-creation overhead. **NOT RECOMMENDED per D-266-PLAN-01 single-plan precedent.** |

---

## Bit-Budget Worked Table (the centerpiece of the refactor)

This table enumerates every entropy consumer in scope; each row pins the minimum bit budget, the proposed slice, the domain-separation tag (if any), and overlap-safety with sibling consumers.

**Conventions:**
- `seed = EntropyLib.hash2(rngWord, structured-input)` — single 256-bit per-resolution seed derived in `_resolveLootboxCommon` from `(rngWord, player, day, amount)` (mirrors L554/L628/L673/L708 entry-point pattern).
- `seed2 = EntropyLib.hash2(seed, 1)` — overflow chunk if budget exceeded (only invoked when `_resolveLootboxRoll` ETH-amount-second branch needs separate sub-seed; counter `1` for distinct chunk).
- Sub-roll bit ranges chosen to be DISJOINT within the same logical chunk (no slice overlap within one resolution path).

### ENT-01 — `_rollTargetLevel` (DegenerusGameLootboxModule.sol:809-827)

| Sub-roll | Modulus | Min bits | Bit slice | Modulo bias | Notes |
|----------|---------|----------|-----------|-------------|-------|
| `rangeRoll` (90/10 near/far branch) | `% 100` | 7 | `bits[0..15]` via `uint16(seed)` | `65536 mod 100 / 65536 = 0.05%` | Locked per D-266-BIT-BUDGET-01; example in CONTEXT.md `<specifics>` |
| Near-level offset (90% branch) | `% 5` | 3 | `bits[16..23]` via `uint8(seed >> 16)` | `256 mod 5 / 256 = 0.39%` | Locked |
| Far-level offset (10% branch) | `% 46` | 6 | `bits[24..39]` via `uint16(seed >> 24)` | `65536 mod 46 / 65536 = 0.05%` | Locked |
| **Sub-total bits consumed** | — | — | **40 bits** | — | One-chunk-fits-all; no `seed2` needed |

**Signature change:** drops `nextEntropy` return; seed owned by caller. Caller pattern (L555/L629/L674/L709) shifts from `(targetLevel, nextEntropy)` to `targetLevel` only; nextEntropy plumbing replaced by passing the pre-derived 256-bit `seed` through.

### ENT-02 — `_resolveLootboxRoll` (DegenerusGameLootboxModule.sol:1530-1616)

| Sub-roll | Modulus | Min bits | Bit slice | Modulo bias | Notes |
|----------|---------|----------|-----------|-------------|-------|
| `roll` (path selector: 55%/10%/10%/25%) | `% 20` | 5 | `bits[40..55]` via `uint16(seed >> 40)` | `65536 mod 20 / 65536 = 0.02%` | Slice continues from ENT-01's 40-bit consumption |
| DGNRS path `tierRoll` (in `_lootboxDgnrsReward` at L1680) | `% 1000` | 10 | `bits[56..71]` via `uint16(seed >> 56)` | `65536 mod 1000 / 65536 = 0.86%` | **NOTE:** This is a sub-call entropy consumer NOT enumerated in CONTEXT.md D-266-CONSUMER-LIST-01. The L1569 `entropyStep` advance feeds `_lootboxDgnrsReward` which slices `% 1000` at L1680. Planner must wire this. Bit budget marginal at 16 bits → bias 0.86% (under 1% per D-266-BIT-BUDGET-01); use 24 bits for safety → bias 0.0024%. |
| WWXRP path | (none — L1586 uses literal `LOOTBOX_WWXRP_PRIZE`) | 0 | — | — | L1585 `entropyStep` advance is DEAD (no entropy consumer in this branch). Refactored away — saves a call. |
| Large-BURNIE `varianceRoll` (low/high split) | `% 20` | 5 | `bits[80..95]` via `uint16(seed >> 80)` | `65536 mod 20 / 65536 = 0.02%` | Slice continues |
| **Sub-total bits consumed** | — | — | **96 bits** | — | Plus ENT-01's 40 = 136 bits cumulative. Still under 256 — no `seed2` needed for one path. |

**ETH-amount-second branch (`amountSecond != 0` at L922-946):** the second `_resolveLootboxRoll` invocation consumes SAME bit budget. To avoid slice-overlap with first invocation, plan TWO options (planner picks one):
- **Option A (counter-tagged second seed):** `seed2 = EntropyLib.hash2(seed, 1)` derived once; second invocation slices from `seed2` using identical bit-offsets. Adds 1 keccak (~80 g). AUDIT-02 surface (c) trivially safe (counter `1` distinct from `0`).
- **Option B (offset-shifted slices in same seed):** First invocation uses bits[0..127]; second uses bits[128..255]. Saves the keccak. Requires BOTH invocations to fit within ~128 bits each — verify against the full sub-call enumeration (boon roll, presale-multiplier, whale-pass, lazy-pass eligibility) before locking.

**Recommendation:** Option A for clarity + slice-safety + audit-narrative simplicity. Cost is ~80 g × 1 call = 80 g per double-resolution lootbox; comfortably under the ±300 g GAS-01 budget. Document the chunk-counter convention inline (NatSpec) so AUDIT-02 surface (c) `hash2(seed, N)` chunk-collision-free analysis is one-liner.

### ENT-03 — `_lootboxTicketCount` (DegenerusGameLootboxModule.sol:1626-1669)

| Sub-roll | Modulus | Min bits | Bit slice | Modulo bias | Notes |
|----------|---------|----------|-----------|-------------|-------|
| `varianceRoll` (5-tier ticket multiplier) | `% 10000` | 14 | `bits[96..119]` via `uint24(seed >> 96)` | `16777216 mod 10000 / 16777216 = 0.045%` | Locked per D-266-BIT-BUDGET-01 |

This consumer is INSIDE the `_resolveLootboxRoll` 55% tickets branch (called at L1556). Slice continues the cumulative bit budget.

### Sub-call entropy consumers within `_resolveLootboxCommon` (L847-1000) — planner must enumerate during execute-phase

| Function | Line | Modulus | Min bits | Bit slice (proposed) | Notes |
|----------|------|---------|----------|----------------------|-------|
| `_rollLootboxBoons` (L1013-1071) | L1059 | `% BOON_PPM_SCALE` (1,000,000) | 20 | `bits[120..151]` via `uint32(seed >> 120) % BOON_PPM_SCALE` | Bias `(2^32 mod 1000000) / 2^32 = 0.022%`; consumes `entropy` parameter at L1059 |
| `_boonFromRoll` interior selection (L1062) | L1062 | weighted per `totalWeight` (variable, ~100-300 typical) | 16 | (deterministic conditional — derived from `roll * totalWeight / totalChance` arithmetic, no fresh slice) | Consumes the same `roll` value |
| `_deityBoonForSlot` at L1746-1760 | L1758 | `% total` (BOON_WEIGHT_TOTAL ≈ small) | 8-16 | (uses fresh `keccak256(rngWordByDay[day], deity, day, slot)` — independent seed; orthogonal to lootbox-path refactor) | NOT in scope (already keccak-derived; not xorshift) |

**Total cumulative bit budget for one resolution + double-amount branch:** ~156 bits in primary `seed` + ~156 bits in `seed2` = comfortable under 2 × 256 bits.

**Slice-overlap audit:** within a single `seed` chunk, every consumer above has a DISJOINT bit range (40 + 16 + 16 + 16 + 16 + 24 + 32 = 160 bits across 7 consumers; rest reserved for future expansion). Documented inline as the bit-allocation NatSpec block per ENT-06.

---

## Architecture Patterns

### Refactor Pattern: Single-Keccak-Per-Resolution + Bit-Sliced Consumers

**What:** One `EntropyLib.hash2(rngWord, structured-input)` call at the entry of `_resolveLootboxCommon` derives a 256-bit seed; consumers slice disjoint bit-ranges from the seed via inline shifts. Optional second chunk via `EntropyLib.hash2(seed, 1)` for overflow.

**When:** Whenever multiple sub-rolls in a single resolution need entropy and (a) bit budget per sub-roll is small, (b) total budget fits within 256 bits (typical) or 512 bits (overflow).

**Example (from CONTEXT.md `<specifics>` — pattern locked):**

```solidity
// Source: 266-CONTEXT.md <specifics>; pattern proven at v35 _awardDailyCoinToTraitWinners
// (DegenerusGameJackpotModule.sol _awardDailyCoinToTraitWinners — though that variant
// derives a fresh per-pull keccak; lootbox-path uses one seed for the whole resolution).

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
```

### Surface-Preservation Pattern: Per-Line Modified-Set Walk via `git diff`

**What:** SURF-01..04 byte-identity grep-proof uses `git diff <baseline>..HEAD -- <file>` and asserts ZERO `-` deletions inside protected line ranges.

**When:** Every audit deliverable's regression appendix needs cross-surface preservation evidence.

**Example (from `test/stat/SurfaceRegression.test.js` v35.0 describe block):**

```javascript
// Source: test/stat/SurfaceRegression.test.js (Phase 264 SURF-01..04)
const PROTECTED_RANGES = [
  // [start, end, label]
  [1653, 1703, "_randTraitTicket body (SURF-01)"],
  // ... 13 ranges total at v35
];

// Per-line modified-set walk vs git diff
const diff = execSync(`git diff ${V34_BASELINE}..HEAD -- ${PATH}`).toString();
const modifiedLines = parseHunkOldSideLineNumbers(diff);
for (const [start, end, label] of PROTECTED_RANGES) {
  const intersection = modifiedLines.filter(l => l >= start && l <= end);
  expect(intersection.length, `${label}: hunk intersection at lines ${intersection.join(",")}`)
    .to.equal(0);
}
```

### Test Pattern: Reuse Existing Phase 261 chi² Infrastructure (STAT-03 discipline)

**What:** New chi² tests re-declare `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` verbatim in the file header (NOT imported — STAT-03 reuse-existing-tooling discipline that proves no fresh statistical tooling).

**When:** Any new statistical test in `test/stat/`.

**Example (verbatim re-declaration from `test/stat/PerPullLevelDistribution.test.js` L78-102):**

```javascript
function makeRng(seed) {
  const seedHex = "0x" + BigInt.asUintN(256, BigInt(seed)).toString(16).padStart(64, "0");
  let counter = 0n;
  return function next256() {
    const counterHex = counter.toString(16).padStart(64, "0");
    counter++;
    return BigInt(hre.ethers.keccak256(seedHex + counterHex));
  };
}

const CHI2_CRIT_05 = { 1: 3.841, 2: 5.991, 3: 7.815, 4: 9.488, 5: 11.070, 6: 12.592, 7: 14.067 };

function wilsonHilfertyZ(chi2, df) {
  const term = Math.cbrt(chi2 / df) - (1 - 2 / (9 * df));
  return term / Math.sqrt(2 / (9 * df));
}
```

### Anti-Patterns to Avoid

- **Importing chi² helpers from a shared module.** Phase 261/263/264 precedent re-declares verbatim per STAT-03 discipline. Importing creates an audit-narrative friction point ("did this helper drift since v35?") whereas verbatim re-declaration is self-evident and grep-comparable to source. **Don't deviate.**
- **Single-resolution-per-keccak with overlapping bit slices.** Two sub-rolls reading the same bit range from the same seed are statistically dependent (they read the same bits) — that's a finding-candidate at AUDIT-02 surface (b). **Always document disjoint bit ranges in inline NatSpec.**
- **`hash2(seed, N)` chunk reuse across consumers without distinct N.** Two consumers calling `hash2(seed, 1)` would collide on the second-chunk derivation. **Use distinct counter or string-tag per chunk; document AUDIT-02 surface (c) chunk collision-free check.**
- **Touching `EntropyLib.sol` body.** ENT-04 mandates byte-identical at v36.0 close. **Zero changes; verify SURF-01 via empty `git diff`.**
- **Forgetting the L1585 `entropyStep` is dead in WWXRP path.** L1586 uses literal `LOOTBOX_WWXRP_PRIZE`. The L1585 advance is consumed by no downstream sub-roll in the WWXRP branch (`applyPresaleMultiplier = false` is non-RNG). **Refactored-away surface — explicit DELETED row in §3d AUDIT-01 table.**
- **Breaking the `nextEntropy` return contract without updating ALL callsites.** `_rollTargetLevel` returns `(targetLevel, nextEntropy)` consumed at L555/L629/L674/L709. Refactor must update all 4 callers atomically in the batched contract commit; otherwise compile fails. **Single-batched-commit discipline catches this.**

### Recommended Project Structure (post-refactor file layout — no new directories)

```
contracts/
├── modules/
│   └── DegenerusGameLootboxModule.sol  # MODIFIED: 7 callsites refactored + entry-point seed derivation
├── libraries/
│   └── EntropyLib.sol                  # UNCHANGED (ENT-04 / SURF-01)
└── modules/
    ├── DegenerusGameJackpotModule.sol  # UNCHANGED (SURF-02 + SURF-04)
    └── DegenerusGameMintModule.sol     # UNCHANGED (SURF-03)

test/
├── stat/
│   ├── LootboxEntropyDistribution.test.js  # NEW: chi² uniformity per sub-roll bucket (STAT-01..03)
│   └── SurfaceRegression.test.js           # EXTENDED: v36.0 SURF-01..04 describe block + PROTECTED_RANGES
└── gas/
    ├── LootboxOpenGas.test.js              # NEW (or extend Phase264GasRegression): GAS-01 per-open ±300 g
    └── AdvanceGameGas.test.js              # EXTENDED: v36.0 1.99× margin assertion (GAS-02)

audit/
└── FINDINGS-v36.0.md  # NEW: 9-section single canonical deliverable

KNOWN-ISSUES.md        # MODIFIED: 1 entry (EntropyLib XOR-shift) rephrased to BAF-only scope (AUDIT-05)

.planning/
├── ROADMAP.md         # UPDATED: v36.0 SHIPPED + closure-signal emission paragraph
├── STATE.md           # UPDATED: v36.0 closed; Last Shipped Milestone updated
├── MILESTONES.md      # UPDATED: v36.0 entry prepended
└── phases/266-lootbox-entropy-refactor/
    ├── 266-CONTEXT.md            # EXISTING (locked decisions)
    ├── 266-RESEARCH.md           # THIS FILE
    ├── 266-01-PLAN.md            # planner output
    ├── 266-01-SUMMARY.md         # executor output
    └── 266-01-ADVERSARIAL-LOG.md # executor output (D-266-ADVERSARIAL-02)
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Statistical chi² helpers | Custom chi² implementation | Verbatim re-declared `makeRng` + `CHI2_CRIT_05` + `wilsonHilfertyZ` from `test/stat/TraitDistribution.test.js` L48-100 | Phase 261/263/264 precedent locked; STAT-03 reuse-existing-tooling discipline; tooling drift would invalidate cross-cite |
| Cross-surface byte-identity verification | Custom AST diff or bytecode comparison | `git diff <baseline>..HEAD -- <file>` + per-line modified-set walk vs PROTECTED_RANGES array | Phase 261 SURF-04 + Phase 264 v35.0 SURF-01..04 precedent; reproducible via grep recipe; included in `test/stat/SurfaceRegression.test.js` |
| Gas regression with theoretical worst-case | Inline gas bound guesses | REF-CAPTURE protocol + `feedback_gas_worst_case.md` opcode walk first | `feedback_gas_worst_case.md` mandates derive-worst-case-FIRST then test; `Phase264GasRegression.test.js` L18-50 demonstrates the pattern (per-pull body opcode walk before bound assertion) |
| Audit deliverable scaffolding | Free-form prose | Copy-paste 9-section structural skeleton from `audit/FINDINGS-v35.0.md` (L1-563) | D-266-FILES-01 + D-265-FILES-01 carry; v33/v34/v35 precedent locks the section ordering; regression-appendix + KI-gating-walk + closure-attestation conventions are battle-tested |
| 9-section closure-attestation TWO-subsection format | New §9.NN format | Copy from `FINDINGS-v35.0.md` §9.NN (L519-560) | D-266-CLOSURE-02 carry of v34 D-262 / v35 D-265; differs from v32 Phase 253 three-subsection (which had awaiting-approval) |
| Forward-cite zero-emission verification | Custom static analysis | `grep -rE 'forward-cite\|defer-to-Phase-267\|TBD-post-milestone' <phase-dir>` recipe | Mirror v35 §8a (L441-446) + §8b (L460-462) grep recipes — distinguishes domain-specific cite tokens from meta-prose discussing the invariant itself |
| Adversarial-pass logging format | Free-form log | Copy from `265-01-ADVERSARIAL-LOG.md` skeleton | D-266-ADVERSARIAL-02 carry; structured by surface row × adversarial-skill (auditor / zero-day-hunter) × disposition |
| RNG backward-trace methodology for EXC-04 NARROWS proof | Custom commitment-window analysis | Cite `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` inline per v35 §6b row 4 (EXC-04) prose | EXC-04 rephrasing inherits the methodology; only the scope changes (lootbox path removed; BAF-only remains) |

**Key insight:** Phase 266 is heavily PRECEDENT-DRIVEN. The deliverable shape, methodology, and conventions are all locked from v33 Phase 257 → v34 Phase 262 → v35 Phase 265. Every section, every grep recipe, every verdict format is a direct copy-with-substitution. Spending planning effort on novelty is wasted; the value is in (a) the bit-budget arithmetic correctness and (b) the chi² + gas + surface-preservation harness implementation. The audit deliverable section structure is mostly copy-paste from FINDINGS-v35.0.md.

---

## Common Pitfalls

### Pitfall 1: chi² with high df (`% 100`, `% 46`, `% 10000`) requires Wilson-Hilferty Z, not the `CHI2_CRIT_05` table

**What goes wrong:** The existing `CHI2_CRIT_05` table only goes to df=7. Naive use of the table for df=99 (`% 100` bucket) or df=9999 (`% 10000` bucket) silently fails.

**Why it happens:** Phase 261/264 chi² tests covered df ≤ 7. STAT-03 specifies reuse — but reuse correctly means using `wilsonHilfertyZ(chi2, df)` for high-df cases (already in the existing helpers, just less commonly invoked).

**How to avoid:** For each chi² test, decide explicitly:
- **df ∈ {1..7}:** assert `chi2 < CHI2_CRIT_05[df]`.
- **df > 7:** compute `z = wilsonHilfertyZ(chi2, df)`; assert `z < 1.645` (one-sided right-tail at α=0.05).

Per-bucket df assignments for Phase 266:

| Sub-roll bucket | df | Critical-value source | Sample budget | Expected per-bucket count |
|-----------------|----|-----------------------|---------------|---------------------------|
| `% 100` (rangeRoll) | 99 | `wilsonHilfertyZ(chi2, 99) < 1.645` | 10K (recommend 100 expected per bucket; 5K → 50/bucket marginal — STAT-01 says ≥ 5K but ≥ 10K cleaner) | 10000/100 = 100 |
| `% 5` (near-level offset) | 4 | `chi2 < CHI2_CRIT_05[4] = 9.488` | 5K (the 90% near-branch path; 4500 effective samples) | 4500/5 = 900 |
| `% 46` (far-level offset) | 45 | `wilsonHilfertyZ(chi2, 45) < 1.645` | 10K (the 10% far-branch path; 1000 effective samples — marginal, recommend 50K total resolutions for 5K far-branch hits) | 5000/46 ≈ 109 |
| `% 20` (path-roll) | 19 | `wilsonHilfertyZ(chi2, 19) < 1.645` | 10K | 10000/20 = 500 |
| `% 20` (large-BURNIE varianceRoll) | 19 | `wilsonHilfertyZ(chi2, 19) < 1.645` | 5K (only 25% of resolutions hit large-BURNIE branch; 20K total resolutions for 5K varianceRoll hits) | 5000/20 = 250 |
| `% 10000` (ticket varianceRoll) | 9999 | `wilsonHilfertyZ(chi2, 9999) < 1.645` | 10K — but with 10K samples and 10K buckets, expected per bucket = 1, which makes chi² convergence problematic. **Recommend 100K samples → 10/bucket.** Even 10/bucket is on the marginal end for chi²; 1M samples → 100/bucket would be ideal. | Marginal — see warning below |

**Warning sign:** `% 10000` bucket with N=10000 expected count of 1 per bucket fails the chi² rule of thumb (expected ≥ 5 per bucket). Either (a) bump samples to 100K+ for 10/bucket, or (b) use the Kolmogorov-Smirnov uniform-test as an alternative to chi² for this specific bucket. Phase 264 STAT-01 used 10K total samples for df=7 (`range=8`) which was generous; the same 10K applied to df=9999 is undersampled.

**Recommendation:** Plan should pre-commit to a sample budget per bucket BEFORE writing the test, justified inline:

```javascript
// Source: STAT-01 sample budget per bucket — modulus → sample count → expected per bucket
// Bucket          Samples  Expected/bucket  df    Critical
// % 100           10_000   100              99    wilsonHilfertyZ < 1.645
// % 5             5_000    1_000            4     CHI2_CRIT_05[4] = 9.488
// % 46            10_000   217              45    wilsonHilfertyZ < 1.645
// % 20 (path)     10_000   500              19    wilsonHilfertyZ < 1.645
// % 20 (variance) 5_000    250              19    wilsonHilfertyZ < 1.645
// % 10000         100_000  10               9999  wilsonHilfertyZ < 1.645  -- FLAGGED: marginal expected/bucket
//                                                                            cf. (10/bucket below ideal 100)
```

### Pitfall 2: `_resolveLootboxRoll` ETH-amount-second branch slice-overlap

**What goes wrong:** The first invocation at L898-907 and the second at L922-933 both consume bits[0..127] of the same `seed`. This makes second-call sub-rolls deterministic functions of first-call sub-rolls — finding-candidate at AUDIT-02 surface (b) "seed-reuse cross-correlation".

**Why it happens:** Naive refactor passes the same `seed` through both branches without distinct chunk derivation.

**How to avoid:** Use Option A (counter-tagged second seed): `seed2 = EntropyLib.hash2(seed, 1)` for the second invocation. Document the chunk convention inline. AUDIT-02 surface (c) `hash2(seed, N)` chunk-collision-free check is one-line ("counter `1` distinct from `0`").

**Warning sign:** if the planner writes `_resolveLootboxRoll(..., seed)` twice in `_resolveLootboxCommon`, that's the bug. Should be `_resolveLootboxRoll(..., seed)` then `_resolveLootboxRoll(..., seed2)` where `seed2 = EntropyLib.hash2(seed, 1)`.

### Pitfall 3: Forgetting `_lootboxDgnrsReward` is a sub-call entropy consumer

**What goes wrong:** CONTEXT.md D-266-CONSUMER-LIST-01 lists 7 callsites. But `_lootboxDgnrsReward` (called at L1570 inside the DGNRS-path branch of `_resolveLootboxRoll`) consumes `entropy % 1000` at L1680. The L1569 `entropyStep` advance feeds it. If the planner refactors only the 7 named callsites but ignores the L1680 sub-call, the DGNRS tier roll consumes whatever bits the planner happens to pass — could be predictable (= same as `roll` from L1551) or could be the entire 256-bit seed reused.

**Why it happens:** The 7-callsite list in CONTEXT.md is an `entropyStep` callsite list, NOT an `entropy %` consumer list. Sub-calls that consume `entropy` directly (without their own `entropyStep`) are missed.

**How to avoid:** During execute-phase, planner enumerates ALL `entropy %` consumers in the lootbox-resolution call graph: grep `entropy %\|entropy /` in `DegenerusGameLootboxModule.sol` body. Confirmed inventory:

```bash
grep -n "entropy %\|entropy /\|nextEntropy %\|levelEntropy %\|farEntropy %" \
  contracts/modules/DegenerusGameLootboxModule.sol
```

Expected hits:
- L814 `levelEntropy % 100` (rangeRoll)
- L818 `farEntropy % 46` (far offset)
- L823 `levelEntropy % 5` (near offset)
- L1551 `nextEntropy % 20` (path roll)
- L1600 `nextEntropy % 20` (variance roll)
- L1636 `nextEntropy % 10000` (ticket variance)
- L1680 `entropy % 1000` (DGNRS tier — sub-call to `_lootboxDgnrsReward`)
- L1059 `entropy % BOON_PPM_SCALE` (boon roll — sub-call to `_rollLootboxBoons`)

**Warning sign:** if the planner's bit-budget table only lists 6-7 consumers, they missed L1680 + L1059 sub-call consumers. Should be 8 consumers total.

### Pitfall 4: Closure signal SHA captured BEFORE final §9 commit

**What goes wrong:** Closure signal embedded in §9c is `MILESTONE_V36_AT_HEAD_<sha>` where `<sha>` should reference the post-Phase-266 contract-tree HEAD. If captured too early (before all §9 commits land), the signal references a stale SHA.

**Why it happens:** Plan author writes §9c paragraph during early task; signal SHA is a post-condition.

**How to avoid:** Plan §9 commits in the order: (1) §9a verdict-distribution table + §9b attestation block + §9.NN.i/ii/iii commit-readiness register PLACEHOLDER (with `<sha>` literal as placeholder); (2) commit and capture HEAD; (3) `git rev-parse HEAD` becomes the closure signal SHA; (4) atomic-update task replaces the placeholder with the resolved SHA in §9c + ROADMAP/STATE/MILESTONES + 266-01-SUMMARY.md; (5) final commit lands. Mirrors v35 D-265-CLOSURE-01 pattern (the `5db8682b` SHA in v35 references the §9 closure-attestation commit itself).

**Warning sign:** if the plan has only one §9 commit, the SHA capture is awkward. Should be ≥ 2 commits in the §9 cluster.

### Pitfall 5: Adversarial-pass spawning before §4 draft is complete

**What goes wrong:** `/contract-auditor` + `/zero-day-hunter` spawned mid-§4 draft re-derive surfaces from scratch instead of red-teaming a finished §4. Wastes the adversarial pass's value.

**Why it happens:** Plan author over-eagerly parallelizes.

**How to avoid:** D-266-ADVERSARIAL-02 mandates sequential: full §4 inline draft FIRST (all surfaces verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / FINDING_CANDIDATE with grep-cited evidence). THEN spawn `/contract-auditor` + `/zero-day-hunter` in parallel as a single message; both red-team the FINISHED draft. Document the spawn message + their responses in `266-01-ADVERSARIAL-LOG.md`.

**Warning sign:** if the plan has the adversarial-pass task before the §4 inline-draft task, that's the bug. Reorder.

### Pitfall 6: `entropyStep` non-lootbox callsite count miscounted

**What goes wrong:** SURF-04 byte-identity covers 9 specific lines: `L285, L453, L532, L610, L612, L886, L1176, L1873, L2192` in `DegenerusGameJackpotModule.sol`. If the planner protects only L2192 (the `entropyStep` BAF site) but forgets the 8 `hash2` sites at L285/L453/L532/L610/L612/L886/L1176/L1873, regression coverage is incomplete.

**Why it happens:** ENT-04 describes EntropyLib API stability; SURF-04 describes JackpotModule surface stability. Conflating them.

**How to avoid:** Two distinct surface preservations:
- **EntropyLib body byte-identical** (SURF-01) — file-level grep, empty `git diff`.
- **JackpotModule non-lootbox callsites byte-identical** (SURF-04) — line-level grep over 9 specific lines.

Verified inventory at HEAD `5db8682b` via `grep -n "EntropyLib\." contracts/modules/DegenerusGameJackpotModule.sol`:

```
L12:  import {EntropyLib} from "../libraries/EntropyLib.sol";
L43:  comment (NatSpec)
L285: uint256 entropy = EntropyLib.hash2(rngWord, targetLvl);
L453: uint256 entropyDaily = EntropyLib.hash2(randWord, lvl);
L532: uint256 entropy = EntropyLib.hash2(randWord, lvl);
L610: uint256 entropyDaily = EntropyLib.hash2(randWord, lvl);
L612: uint256 entropyNext = EntropyLib.hash2(randWord, sourceLevel);
L886: EntropyLib.hash2(randWord, lvl),
L1176: uint256 entropy = EntropyLib.hash2(randWord, lvl);
L1873: entropy = EntropyLib.hash2(entropy, s);
L2192: entropy = EntropyLib.entropyStep(entropy);
```

Total: 9 lines. SURF-04 PROTECTED_RANGES array gets these 9 single-line entries (or one merged range if they fall inside `_jackpotTicketRoll`'s 2186-2229 SURF-02 range — they don't; SURF-02 covers only L2192).

**Warning sign:** if the planner's SURF-04 PROTECTED_RANGES array has fewer than 9 entries, that's the bug.

---

## Code Examples

### Refactor reference: `_rollTargetLevel` post-refactor (CONTEXT.md `<specifics>`)

```solidity
// Source: 266-CONTEXT.md <specifics> bit-slice convention example
// Bit budget: rangeRoll uses bits[0..15] (% 100, bias 0.05%); near-level offset
// uses bits[16..23] (% 5, bias 0.39%); far-level offset uses bits[24..39] (% 46, bias 0.05%).
function _rollTargetLevel(uint24 baseLevel, uint256 seed)
    private pure returns (uint24 targetLevel)
{
    uint256 rangeRoll = uint16(seed) % 100;        // bits[0..15]
    if (rangeRoll < 10) {
        uint256 farOffset = uint16(seed >> 24) % 46;   // bits[24..39]
        targetLevel = baseLevel + uint24(farOffset + 5);
    } else {
        uint256 nearOffset = uint8(seed >> 16) % 5;   // bits[16..23]
        targetLevel = baseLevel + uint24(nearOffset);
    }
}
```

### Caller pattern: `openLootBox` post-refactor (proposed for L548-555)

```solidity
// Source: refactored from contracts/modules/DegenerusGameLootboxModule.sol:548-555
// Single-keccak-per-resolution: derive seed at entry, thread through.
uint24 baseLevel = withinGracePeriod ? graceLevel : purchaseLevel;
uint256 seed = EntropyLib.hash2(rngWord, uint256(uint160(player)) ^ (uint256(day) << 160) ^ amount);
// (Or preserve existing keccak: uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));
//  — bit-identical to a hash2-equivalent provided structured-input encoding stays the same; planner's call
//  whether to keep current `keccak256(abi.encode(...))` or switch to `EntropyLib.hash2(...)`. Either is
//  byte-identical at the consumer level since both produce a uniform 256-bit output.)
uint24 targetLevel = _rollTargetLevel(baseLevel, seed);
// ... seed threaded into _resolveLootboxCommon
```

**Note:** L554 currently uses `uint256(keccak256(abi.encode(rngWord, player, day, amount)))`. This is functionally equivalent to `EntropyLib.hash2(rngWord, structured-input)` for a single keccak; the existing pattern can be preserved or migrated. **Recommend preserve** to minimize SURF-01 hunk noise — `EntropyLib.hash2` body stays untouched per ENT-04, and the entry-point keccak is a caller-side detail not a library-call signature.

### Statistical validation reference: chi² over `% 100` bucket with Wilson-Hilferty

```javascript
// Source: pattern adapted from test/stat/PerPullLevelDistribution.test.js L248-282
// for high-df chi² (df=99) using wilsonHilfertyZ.
describe("STAT-01 — _rollTargetLevel rangeRoll % 100 chi² uniformity", function () {
  it("rangeRoll over N=10000 has wilsonHilfertyZ < 1.645 (df=99)", function () {
    const N = 10_000;
    const range = 100;
    const observed = new Array(range).fill(0);
    const rng = makeRng(0xC036_0001);  // Phase 266 seed convention
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

### Surface preservation reference: SURF-04 PROTECTED_RANGES grep-proof

```javascript
// Source: pattern adapted from test/stat/SurfaceRegression.test.js v35.0 describe block
const V35_BASELINE = "5db8682bd7b811437f0c1cf47e832619d1478ac6";
const JACKPOT_PATH = "contracts/modules/DegenerusGameJackpotModule.sol";

const SURF_04_PROTECTED_LINES = [
  [285, 285, "L285 EntropyLib.hash2(rngWord, targetLvl) — non-lootbox JackpotModule callsite"],
  [453, 453, "L453 EntropyLib.hash2(randWord, lvl)"],
  [532, 532, "L532 EntropyLib.hash2(randWord, lvl)"],
  [610, 610, "L610 EntropyLib.hash2(randWord, lvl)"],
  [612, 612, "L612 EntropyLib.hash2(randWord, sourceLevel)"],
  [886, 886, "L886 EntropyLib.hash2(randWord, lvl) (in arg position)"],
  [1176, 1176, "L1176 EntropyLib.hash2(randWord, lvl)"],
  [1873, 1873, "L1873 entropy = EntropyLib.hash2(entropy, s)"],
  [2192, 2192, "L2192 entropy = EntropyLib.entropyStep(entropy) (BAF jackpot — ENT-05 deferral; SURF-02 sub-range covers L2186-2229 SURF-04 entry is the entropyStep line specifically)"],
];

// Per-line modified-set walk vs git diff — ZERO `-` deletions inside protected lines.
const diff = execSync(`git diff ${V35_BASELINE}..HEAD -- ${JACKPOT_PATH}`).toString();
// (Soft-skip if baseline unreachable — shallow clone safety, mirrors v33/v34/v35 SURF harness.)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `EntropyLib.entropyStep` chained xorshift in lootbox path | Inline bit-sliced `EntropyLib.hash2(rngWord, structured-input)` | v36.0 Phase 266 (this phase) | Removes the EntropyLib XOR-shift weak-PRNG warden surface in the lootbox path. KNOWN-ISSUES.md EntropyLib XOR-shift entry NARROWS to BAF-only scope. Behavioral change: pre-/post-refactor specific outcomes diverge for same VRF word; uniform-distribution preserved. |
| 5K total chi² samples (Phase 261/264 STAT-01..02 origin) | 10K aggregated samples per regime (Phase 264 STAT-01 actual) | v35.0 Phase 264 | Baseline for Phase 266: ≥ 10K per low-df bucket; ≥ 100K for `% 10000` due to 1-per-bucket rule of thumb |
| `KNOWN-ISSUES.md` listed lootbox EntropyLib XOR-shift as primary scope | `KNOWN-ISSUES.md` rephrased to BAF-jackpot-only at v36.0 | v36.0 Phase 266 close (AUDIT-05) | Single entry rephrased; entry not removed (BAF still uses xorshift per ENT-05 deferral) |
| Three-subsection §9.NN format with §9.NN.iv awaiting-approval | TWO-subsection §9.NN format (no awaiting-approval) | v34.0 Phase 262 (D-262-CLOSURE-02) | All test commits batched USER-APPROVED at end-of-phase; mirrors v33/v34/v35 |
| Multi-phase milestone shape (impl + test + audit phases separate) | Single-phase patch (Phase 266 covers impl + test + audit) | v36.0 (Path 2 user disposition) | Mirrors lightweight v3.x post-closure-patch pattern; not v34/v35 multi-phase |

**Deprecated/outdated:**

- `xorshift-as-primary-RNG-mechanism` for lootbox outcome derivation — replaced by `bit-sliced-keccak-from-VRF-word` at v36.0. The xorshift path remains for BAF jackpot per ENT-05 deferral.
- Pre-Phase-264 chi² CHI2_CRIT_05 table df ≤ 3 only (origin at `test/unit/JackpotSoloPicker.test.js`) — extended to df ≤ 7 at Phase 261 (STAT-04 reuse target). Wilson-Hilferty Z added for df > 7.
- `audit/v33.0-MILESTONE-AUDIT.md` flat-document audit format — replaced by `audit/FINDINGS-vNN.md` 9-section format from v33.0 onward.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `% 10000` chi² with 10K samples (1 expected per bucket) is undersampled — recommend 100K+ for 10/bucket | Pitfall 1 | **MEDIUM:** if planner uses 10K samples per CONTEXT.md "5K-10K samples per bucket" without bumping for the `% 10000` case, chi² may be underpowered or overshoot critical-value at random. Mitigation: pre-commit sample budget per bucket inline in test; flag the 10K-bucket case explicitly. `[VERIFIED: chi² rule of thumb expected ≥ 5/bucket — standard statistics; CITED: NIST/SEMATECH e-Handbook of Statistical Methods, Section 7.2.4]` |
| A2 | `_lootboxDgnrsReward` at L1680 (`entropy % 1000`) is a sub-call entropy consumer NOT in CONTEXT.md D-266-CONSUMER-LIST-01 — planner must enumerate during execute-phase | Pitfall 3 + Bit-Budget Worked Table | **LOW:** verified by grep `entropy %\|entropy /` in DegenerusGameLootboxModule.sol. CONTEXT.md says "planner must enumerate during planning by reading `_resolveLootboxCommon` body L847-1000+ in detail" — this research call surfaces the L1680 + L1059 sub-call consumers; planner inherits the discovery. If missed, AUDIT-02 surface (b) seed-reuse cross-correlation could flag at adversarial pass. `[VERIFIED: grep across DegenerusGameLootboxModule.sol]` |
| A3 | L1585 `entropyStep` advance is dead in WWXRP path (no downstream entropy consumer) | Bit-Budget Worked Table + Common Pitfalls | **LOW:** verified by reading L1583-1596 — WWXRP path uses literal `LOOTBOX_WWXRP_PRIZE` for amount and `applyPresaleMultiplier = false` (deterministic). Refactor opportunity: drop the entropy advance entirely in WWXRP branch. If planner refactors mechanically without spotting the dead step, gas savings missed (~40 g per WWXRP-path lootbox). `[VERIFIED: read of L1583-1596]` |
| A4 | Option A (counter-tagged second seed `EntropyLib.hash2(seed, 1)`) is preferred over Option B (offset-shifted slices) for `_resolveLootboxRoll` ETH-amount-second branch | Bit-Budget Worked Table + Common Pitfalls 2 | **LOW:** ~80 g cost is comfortably under ±300 g GAS-01 budget; AUDIT-02 surface (c) chunk-collision-free analysis is one-liner. Option B saves ~80 g but requires careful 128-bit slice budget; tradeoff favors clarity. Planner's discretion per CONTEXT.md `<decisions>` — Claude's Discretion section. `[ASSUMED: based on gas + audit-narrative tradeoff]` |
| A5 | `% 1000` (DGNRS tier roll at L1680) requires 24 bits (not 16) for ≤ 1% bias per D-266-BIT-BUDGET-01 | Bit-Budget Worked Table | **LOW:** at 16 bits → bias 0.86% (under 1%); at 24 bits → bias 0.0024%. Either complies with D-266-BIT-BUDGET-01 ("≤ 1% bias for any draw"). 24 bits is generous; planner picks. Wider slice slightly improves the AUDIT-02 surface (a) modulo-bias bound argument. `[VERIFIED: bit-bias arithmetic; CITED: D-266-BIT-BUDGET-01]` |
| A6 | Phase 266 `audit/FINDINGS-v36.0.md` will use ~5-7 §4 surface rows (vs v35's 6 surfaces + STAT-03 reframe) | Phase Requirements + AUDIT-02 mapping | **LOW:** surfaces enumerated in REQUIREMENTS.md AUDIT-02: (a) bit-slice modulo-bias per draw within documented bound; (b) seed-reuse across sub-rolls within same resolution doesn't introduce predictable cross-correlation; (c) `hash2(seed, N)` chunk indexing collision-free across consumers; (d) gas-griefing delta bounded; (e) byte-identity preserved on the deferred BAF jackpot xorshift path (ENT-05 verification). Plus likely (f) commitment-window check (per `feedback_rng_commitment_window.md` — required for all RNG audits). 5-6 rows expected; planner adds (f) + any inline-discovered surfaces. `[ASSUMED: based on REQUIREMENTS.md AUDIT-02 enumeration + v35 §4 row count]` |
| A7 | EXC-04 NARROWS rephrasing follows v35 §6b row 4 prose template (backward-trace methodology + commitment-window cite + chi² empirical cross-cite) | Phase Requirements + REG-03 mapping | **LOW:** mirrors locked v35 D-265 carry. EXC-04 entry text proposed in CONTEXT.md `<specifics>` block. Backward-trace per `feedback_rng_backward_trace.md` confirms BAF-jackpot-path xorshift consumer remains; lootbox consumer removed. `[VERIFIED: cross-reference to FINDINGS-v35.0.md L394-397 + FINDINGS-v34.0.md L457]` |
| A8 | Foundry gas-snapshot files (`.gas-snapshot`) are not in use; existing gas tests use inline-pinned REF-CAPTURE constants | Standard Stack + GAS-01 mapping | **LOW:** verified by absence of `.gas-snapshot` files in repo + existence of `PAY_DAILY_COIN_JACKPOT_GAS_REF = 2_860_535` literal pinning in `test/gas/Phase264GasRegression.test.js` L108. Pattern: REF-CAPTURE protocol writes diagnostic on first run, executor pins the captured value into the literal constant. `[VERIFIED: ls .gas-snapshot returns no results; grep _GAS_REF in test/gas/]` |

**These assumptions need user confirmation if the planner deviates from the recommendations.** Specifically: A1 (sample budget for `% 10000`), A4 (Option A vs B for second seed), A5 (24 bits vs 16 for `% 1000`), and A6 (§4 surface row count) are user-discretion-eligible per CONTEXT.md `<decisions>` Claude's Discretion section.

---

## Open Questions

1. **`% 10000` chi² sample budget — 10K (per CONTEXT.md "5K-10K") or 100K+ (per chi² rule of thumb)?**
   - What we know: CONTEXT.md STAT-01 specifies "≥ 5K samples per bucket"; chi² rule of thumb requires ≥ 5 expected per bucket. With 10K samples and 10K buckets, expected = 1 per bucket — undersampled.
   - What's unclear: whether "5K-10K samples per bucket" in CONTEXT.md means 5K-10K total samples OR 5K-10K per bucket (which would be 50M+ for `% 10000`).
   - Recommendation: **Plan for 100K samples on the `% 10000` bucket** (10/bucket, marginal but viable). If chi² fails reproducibly, escalate to user inline (per D-266-ADVERSARIAL-03 disagreement-disposition rule). Pre-commit the sample budget inline in the test header with explicit justification.

2. **Should `_resolveLootboxCommon` entry-point keccak use `EntropyLib.hash2` or preserve existing `keccak256(abi.encode(...))`?**
   - What we know: L554/L628/L673/L708 currently use `uint256(keccak256(abi.encode(rngWord, player, day, amount)))`. EntropyLib.hash2 takes `(uint256, uint256)` so `(rngWord, structured-input)` requires reducing the 4-tuple to 2 inputs.
   - What's unclear: whether refactor preserves the existing keccak (cleaner SURF diff) or migrates to `hash2` (uniformity with the call-site convention).
   - Recommendation: **Preserve the existing `keccak256(abi.encode(rngWord, player, day, amount))`** for the entry-point seed derivation. Both produce uniform 256-bit output; preservation minimizes SURF-04-equivalent regression noise on the entry-point lines. If migration is wanted for stylistic consistency, it's an independent cleanup; document the choice inline.

3. **Should the WWXRP path's L1585 `entropyStep` advance be removed entirely (it's dead in the post-refactor design)?**
   - What we know: WWXRP path uses literal `LOOTBOX_WWXRP_PRIZE`; `applyPresaleMultiplier = false` is deterministic. No downstream entropy consumer reads bits sourced from this advance.
   - What's unclear: whether removing the dead advance creates AUDIT-01 §3d table noise (a "DELETED row" classification) and whether SURF-XX considerations change.
   - Recommendation: **Remove it.** Document as a DELETED row in §3d AUDIT-01. Saves ~40 g per WWXRP-path lootbox; matches the spirit of `feedback_no_dead_guards.md` (don't waste gas on dead branches).

4. **Should KNOWN-ISSUES.md "Lootbox RNG uses index advance isolation" entry be addressed in Phase 266 or deferred?**
   - What we know: D-266-SCOPE-OUT-04 says "planner's call". Per inline conversation in CONTEXT.md, the entry framing is "backwards" — index-advance is the standard idiom, rngLockedFlag is the special case.
   - What's unclear: whether removing/rephrasing this entry inside Phase 266 expands AUDIT-05 scope (now 2 entries modified, not 1) and adds friction to the §6 KI gating walk.
   - Recommendation: **Defer.** Phase 266 modifies 1 KNOWN-ISSUES.md entry (EntropyLib XOR-shift rephrasing). Scope discipline favors single-entry modification. Address the index-advance entry as a separate post-v36 maintenance task.

5. **Should Phase 266 use `test/stat/LootboxEntropyDistribution.test.js` (NEW) or extend an existing file?**
   - What we know: NEW file is cleaner; extension is more compact. Existing files are Phase 264-tagged and v35-frozen.
   - What's unclear: whether the planner's preference is for one file with all chi² regimes vs multiple smaller test files per sub-roll.
   - Recommendation: **Single new file `test/stat/LootboxEntropyDistribution.test.js`** with 6 describe blocks (one per chi² bucket: `% 100`, `% 5`, `% 46`, `% 20 path`, `% 20 variance`, `% 10000`). Mirrors `PerPullLevelDistribution.test.js` shape with multiple regimes in one file. Plus 1 STAT-04-equivalent describe block confirming chi² infra reuse.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Solidity 0.8.34 compiler | All contract files | ✓ | (via Hardhat config) | — |
| Foundry / `forge` | Optional gas profiling | ✓ | (foundry.lock present) | Hardhat-only path also works |
| Hardhat + Mocha + Chai | All `.test.js` files | ✓ | (via package.json + node_modules) | — |
| `@nomicfoundation/hardhat-toolbox/network-helpers.js` | `loadFixture` pattern | ✓ | bundled | — |
| Ethers v6 | `hre.ethers.keccak256` etc. | ✓ | bundled | — |
| Git baseline `5db8682b` reachable | SURF-01..04 + REG-01 byte-identity grep-proof | ✓ | latest commit (v35.0 closure HEAD) | Soft-skip pattern in `SurfaceRegression.test.js` (mirrors v33/v34/v35 — `if (!gitRevParseSucceeds(BASELINE)) this.skip();`) |
| Git baseline `6b63f6d4` reachable (v34.0) | REG-02 byte-identity grep-proof | ✓ | reachable | Soft-skip — same pattern |
| Git baselines `4ce3703d` (v33.0) etc. | REG-04 prior-finding spot-check sweep | ✓ | reachable | Soft-skip; spot-check is grep-only (doesn't require git diff) |
| `audit/FINDINGS-v25..v35.0.md` files | REG-04 grep walk | ✓ | files present in repo | — |
| `KNOWN-ISSUES.md` | AUDIT-05 entry rephrasing | ✓ | present | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None — soft-skip patterns handle baseline-unreachable in shallow-clone scenarios.

---

## Validation Architecture

> Project config has `workflow.nyquist_validation: false` — section nominally optional. Including for Phase 266 because the test commits ARE the validation evidence (chi² + gas + surface-preservation).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Hardhat (primary) + Mocha + Chai; Foundry available (forge) for gas profiling |
| Config file | `hardhat.config.js` + `foundry.toml` |
| Quick run command | `npx hardhat test test/stat/LootboxEntropyDistribution.test.js test/gas/LootboxOpenGas.test.js` |
| Full suite command | `npm test` (or `npx hardhat test`); chi² heavy MC under `npm run test:stat` per existing convention |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Status |
|--------|----------|-----------|-------------------|-------------|
| ENT-01 | `_rollTargetLevel` bit-sliced refactor | Unit (compile + integration via lootbox open) | `npx hardhat compile` + existing lootbox unit tests pass at `test/unit/DistressLootbox.test.js` etc. | Existing tests pass without modification (uniform-equivalence is preserved per STAT-02; specific outcomes diverge but test assertions are distribution-shape) |
| ENT-02 | `_resolveLootboxRoll` 4 callsites refactored | Unit | Same as ENT-01 | Same |
| ENT-03 | `_lootboxTicketCount` 1 callsite refactored | Unit | Same | Same |
| ENT-04 | EntropyLib API stable | Unit (SURF-01) | `git diff <baseline>..HEAD -- contracts/libraries/EntropyLib.sol` returns empty | Wave 0: extend `test/stat/SurfaceRegression.test.js` |
| ENT-05 | BAF jackpot OUT-of-scope | Unit (SURF-02) | Per-line modified-set walk over JackpotModule.sol L2186-2229 | Wave 0: extend SurfaceRegression.test.js |
| ENT-06 | Bit-budget NatSpec inline | Manual review (planner inspects diff) | `grep "bits\[" contracts/modules/DegenerusGameLootboxModule.sol` returns ≥ 8 NatSpec hits | — |
| STAT-01 | Per-sub-roll chi² uniformity | Heavy MC (JS-replica) | `npx hardhat test test/stat/LootboxEntropyDistribution.test.js` | NEW: `test/stat/LootboxEntropyDistribution.test.js` |
| STAT-02 | Pre-/post distribution shape preserved | Heavy MC (in same file as STAT-01) | Same | Same NEW file |
| STAT-03 | Reuse Phase 261/264 chi² infra | Sanity assertion (in same file) | Same; describe block "STAT-04 — Phase 261 infrastructure reuse" pattern | Same NEW file |
| GAS-01 | Per-open ±300 g | Heavy MC (entry-point measurement) | `npx hardhat test test/gas/LootboxOpenGas.test.js` | NEW: `test/gas/LootboxOpenGas.test.js` (or extend Phase264GasRegression.test.js) |
| GAS-02 | advanceGame ±2K, 1.99× margin | Heavy MC | `npx hardhat test test/gas/AdvanceGameGas.test.js` | EXTEND existing |
| SURF-01..04 | Cross-surface byte-identity | Unit (grep-proof) | `npx hardhat test test/stat/SurfaceRegression.test.js` | EXTEND existing with v36.0 describe block |
| AUDIT-01..05 | Audit deliverable | Manual (review) | `audit/FINDINGS-v36.0.md` published; manual review per `feedback_manual_review_before_push.md` | NEW |
| REG-01..04 | Regression checks | Manual + grep-recipe-driven (in audit deliverable §5) | Inline in `audit/FINDINGS-v36.0.md` §5a/b/c | NEW |

### Sampling Rate

- **Per task commit:** existing test suite must compile + pass (`npx hardhat compile`; `npx hardhat test test/unit`). Heavy MC (`npm run test:stat`, `test/gas/`) runs at end-of-wave, not per-task.
- **Per wave merge:** full `npm test` + `npm run test:stat` + `npm run test:gas` green.
- **Phase gate:** all three green before final user-review gate at Task N (per `feedback_manual_review_before_push.md`); then READ-only flip on FINDINGS-v36.0.md.

### Wave 0 Gaps

- [ ] `test/stat/LootboxEntropyDistribution.test.js` — covers STAT-01..03 (NEW file)
- [ ] `test/gas/LootboxOpenGas.test.js` — covers GAS-01 (NEW file; or extend `Phase264GasRegression.test.js`)
- [ ] `test/gas/AdvanceGameGas.test.js` — extend with v36.0 1.99× margin row (EXISTING file)
- [ ] `test/stat/SurfaceRegression.test.js` — extend with v36.0 SURF-01..04 describe block + PROTECTED_RANGES array (EXISTING file)
- [ ] `package.json` — wire any NEW test files into `npm run test:stat` / `npm run test:gas` scripts (mirror `833b341d  chore(264-02): wire Phase 264 test files into npm scripts` pattern)

*(No framework install gaps — all required tooling is already wired into the repo.)*

---

## Project Constraints (from CLAUDE.md / MEMORY.md feedback artifacts)

This phase is governed by an unusually rich set of project-specific feedback constraints. The planner MUST honor each:

### Contract & Test Approval Discipline

- **`feedback_no_contract_commits.md`** — NEVER commit `contracts/` or `test/` changes without explicit user approval. Phase 266 has 1 batched contract commit (LootboxModule refactor) + N batched test commits (chi² + gas + surface) — all USER-APPROVED batched.
- **`feedback_batch_contract_approval.md`** — Batch ALL phase contract edits, present ONE diff at end, get ONE approval. The LootboxModule refactor IS one batched commit per this discipline.
- **`feedback_never_preapprove_contracts.md`** — Orchestrator/agent must NEVER pre-approve any contract change. Vacuous unless agent attempts it; just don't.
- **`feedback_wait_for_approval.md`** — Present fix and wait for explicit approval before editing. Adversarial-pass disagreements escalate to user inline (D-266-ADVERSARIAL-03).
- **`feedback_manual_review_before_push.md`** — User reviews `audit/FINDINGS-v36.0.md` diff before any push. NO `git push` by agent.
- **`feedback_contract_locations.md`** — Read contracts ONLY from `contracts/` directory; stale copies exist elsewhere.

### Code & Comment Quality

- **`feedback_no_history_in_comments.md`** — Comments describe what IS, never what changed or what it used to be. NatSpec on refactored functions describes the CURRENT bit-slice scheme (not "this was xorshift before").
- **`feedback_no_dead_guards.md`** — Remove unreachable safety caps; don't waste gas on dead branches. Applies to L1585 WWXRP-path entropyStep dead advance (Open Question 3).

### RNG Audit Methodology (load-bearing for AUDIT-02 surfaces)

- **`feedback_rng_backward_trace.md`** — Every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time. Applies to EXC-04 NARROWS proof at §6b (REG-03) and AUDIT-02 surface (a) modulo-bias bound argument.
- **`feedback_rng_commitment_window.md`** — Every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Applies to AUDIT-02 surface (f) commitment-window check.

### Gas Audit Methodology (load-bearing for GAS-01..02)

- **`feedback_gas_worst_case.md`** — Gas analysis must derive theoretical worst case FIRST, then test it. Applies to GAS-01 per-open envelope: derive bit-slice + keccak overhead opcode-by-opcode in test header (mirror `Phase264GasRegression.test.js` L18-50 pattern), THEN assert measured against pinned bound.
- **`feedback_test_rnglock.md`** — Test rngLocked removal from coinflip claim paths before deploy. Vacuous for Phase 266 (lootbox path doesn't touch rngLocked state machine; orthogonal).

### Workflow & Phase Discipline

- **`feedback_skip_research_test_phases.md`** — Skip research for obvious/mechanical phases. Inverse here: this IS the research phase, but CONTEXT.md captured all locked decisions inline; this RESEARCH.md surfaces the bit-budget arithmetic + chi² calibration the planner needs but didn't have.
- **`feedback_contractaddresses_policy.md`** — `ContractAddresses.sol` is modifiable; every other `contracts/*.sol` still needs explicit approval. Vacuous for Phase 266 (no `ContractAddresses.sol` changes).

### Project Structure (from MEMORY.md `project_basics.md`)

- Solidity 0.8.34, Foundry + Hardhat
- Game modules via delegatecall in `contracts/modules/`
- Storage layout: `contracts/storage/DegenerusGameStorage.sol`
- Addresses: `contracts/ContractAddresses.sol`

---

## Plan Decomposition Recommendation

**Single multi-task plan** per D-266-PLAN-01. Mirror v35 Phase 265's 14-task ordering (or v34 Phase 262's similar) with task ordering grouped into 5 sequential waves:

### Wave 1 — Contract refactor (BATCHED, USER-APPROVED at end)

1. **Task 1:** `_rollTargetLevel` refactor (L809-827) — bit-slice convention; signature drops `nextEntropy` return; update 4 callers (L555, L629, L674, L709). NatSpec inline bit-budget block.
2. **Task 2:** `_resolveLootboxRoll` refactor (L1530-1616) — 4 callsites (L1548/L1569/L1585/L1599); plumb `seed` parameter from `_resolveLootboxCommon`; counter-tagged `seed2` for ETH-amount-second branch (Option A); drop dead L1585 advance in WWXRP path. NatSpec inline.
3. **Task 3:** `_lootboxTicketCount` refactor (L1626-1669) — 1 callsite (L1635); 24-bit slice for `% 10000`. NatSpec inline.
4. **Task 4:** `_resolveLootboxCommon` + entry-point seed plumbing — derive seed at L554/L628/L673/L708 (preserve existing `keccak256(abi.encode(...))`); thread `seed` parameter through `_rollTargetLevel` + `_resolveLootboxRoll` + `_lootboxTicketCount` + `_lootboxDgnrsReward` + `_rollLootboxBoons`. Update 4 entry points (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`).
5. **Task 5:** Compile + run existing test suite green; **PRESENT BATCHED DIFF TO USER**; commit `feat(266): lootbox-path entropy refactor [ENT-01..06]` AFTER explicit "approved".

### Wave 2 — Statistical + gas + surface tests (BATCHED, USER-APPROVED at end)

6. **Task 6:** `test/stat/LootboxEntropyDistribution.test.js` — chi² across 6 buckets (% 100, % 5, % 46, % 20 path, % 20 variance, % 10000) with sample budget per Pitfall 1 table. STAT-01..03.
7. **Task 7:** `test/gas/LootboxOpenGas.test.js` (or extend `Phase264GasRegression.test.js`) — REF-CAPTURE + theoretical-worst-case opcode walk header + per-open ±300 g assertion. GAS-01.
8. **Task 8:** `test/gas/AdvanceGameGas.test.js` extension — v36.0 1.99× margin describe block. GAS-02.
9. **Task 9:** `test/stat/SurfaceRegression.test.js` extension — v36.0 SURF-01..04 describe block + PROTECTED_RANGES array (EntropyLib body + JackpotModule 9-line + MintModule L652 + JackpotModule BAF 2186-2229). SURF-01..04.
10. **Task 10:** `package.json` — wire NEW test files into `npm run test:stat` / `npm run test:gas` scripts. Run full suite green; **PRESENT BATCHED TESTS DIFF TO USER**; commit `test(266): chi² + gas + surface preservation [STAT-01..03 + GAS-01..02 + SURF-01..04]` AFTER "approved".

### Wave 3 — Audit deliverable §1-§4 (AGENT-COMMITTED atomic per task)

11. **Task 11:** `audit/FINDINGS-v36.0.md` §1 frontmatter + §2 Executive Summary skeleton (verdict-summary placeholders; D-08 + D-09 rubric refs).
12. **Task 12:** §3a Phase 266 per-phase section + §3d AUDIT-01 delta-surface table + §3d Part C AUDIT-04 zero-new-state attestation + §3e AUDIT-03 conservation re-proof.
13. **Task 13:** §4 inline draft — surface (a) modulo-bias / (b) seed-reuse cross-correlation / (c) hash2 chunk-collision-free / (d) gas-griefing / (e) BAF byte-identity / (f) commitment-window. AUDIT-02 pre-adversarial-pass.
14. **Task 14:** Adversarial-pass log skeleton at `266-01-ADVERSARIAL-LOG.md`; spawn `/contract-auditor` + `/zero-day-hunter` in parallel as ONE message; both red-team finished §4 draft. Disagreement disposition per D-266-ADVERSARIAL-03 (escalate to user inline if any).

### Wave 4 — Audit deliverable §5-§8 (AGENT-COMMITTED atomic per task)

15. **Task 15:** §5 regression appendix — REG-01 v35.0 closure-signal carry-forward (1-row PASS) + REG-02 v34.0 closure-signal carry-forward (1-row PASS) + REG-04 prior-finding spot-check sweep (defensive grep walk; expected ALL PASS).
16. **Task 16:** §6 KI gating walk — §6a Non-Promotion Ledger (default zero rows) + §6b 4-row KI envelope re-verifications (EXC-01..03 NEGATIVE-scope; EXC-04 NARROWS to BAF-only with backward-trace cite + chi² empirical cross-cite to STAT-01) + §6c verdict summary "0 of 0 KI_ELIGIBLE_PROMOTED; KNOWN_ISSUES_REPHRASED (1 entry rephrased to BAF-only scope under Design Decisions)".
17. **Task 17:** `KNOWN-ISSUES.md` modification — EntropyLib XOR-shift entry rephrased to BAF-jackpot-only scope per AUDIT-05 (proposed prose in CONTEXT.md `<specifics>`).
18. **Task 18:** §7 prior-artifact cross-cites table + §8 forward-cite closure (8a + 8b + 8c — zero forward-cite emission per terminal-phase invariant; D-266-FCITE carry of D-265-FCITE-01).

### Wave 5 — Closure attestation + flips + final review (AGENT-COMMITTED atomic per task)

19. **Task 19:** §9 milestone closure attestation — §9a verdict distribution + §9b attestation block + §9c closure signal (placeholder `MILESTONE_V36_AT_HEAD_<sha>`) + §9.NN.i USER-APPROVED contracts (Wave 1 commit) + §9.NN.ii USER-APPROVED tests (Wave 2 commit) + §9.NN.iii AGENT-COMMITTED audit artifacts (Tasks 11-19 chain).
20. **Task 20:** Resolve closure-signal SHA — `git rev-parse HEAD` after Task 19 lands; atomic-update §9c + ROADMAP.md (closure-signal emission paragraph) + STATE.md (milestone closed; Last Shipped Milestone updated) + MILESTONES.md (v36.0 entry prepended) + 266-01-SUMMARY.md (Phase 266 SHIPPED).
21. **Task 21:** **PRESENT FINAL DIFF TO USER** for review per `feedback_manual_review_before_push.md` (audit deliverable + KNOWN-ISSUES.md + ROADMAP/STATE/MILESTONES + SUMMARY). After "approved": READ-only flip on `audit/FINDINGS-v36.0.md` (`status: FINAL — READ-ONLY` + `read_only: true` in frontmatter) + final closure-attestation commit + Phase 266 task 21 close.

### Wave Dependency Graph

```
Wave 1 (contract refactor)
    ↓ [USER APPROVAL gate]
    ↓ commit cf-266-01 lands
Wave 2 (tests — chi² + gas + surface)
    ↓ [USER APPROVAL gate]
    ↓ N test commits land
Wave 3 (audit §1-§4)
    ↓ [adversarial pass at end of Wave 3 — Task 14]
Wave 4 (audit §5-§8)
    ↓
Wave 5 (closure §9 + flips + READ-only)
    ↓ [USER REVIEW gate]
    ↓ Phase 266 SHIPPED + v36.0 closed
```

### Total task estimate

**~21 tasks** distributed across 5 waves. Slightly larger than v35 Phase 265's 14 tasks because Phase 266 includes Wave 1 (contract refactor) + Wave 2 (tests) which v35 didn't have (v35 was pure consolidation). v34 Phase 262 had a similar shape; ~20 tasks is a reasonable target.

**Multi-plan alternative (rejected per D-266-PLAN-01):** split into 266-01 (Waves 1-2 contracts + tests) + 266-02 (Waves 3-5 audit deliverable). Cleaner ownership boundaries; costs N× plan-creation overhead. Single-plan precedent locked.

---

## Sources

### Primary (HIGH confidence)

- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/phases/266-lootbox-entropy-refactor/266-CONTEXT.md` — locked decisions for this phase
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/REQUIREMENTS.md` — 24 v36.0 requirement IDs
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/ROADMAP.md` lines 19, 123-135 — Phase 266 success criteria
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/STATE.md` lines 3-30, 111-122 — milestone state
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameLootboxModule.sol` lines 540-1762 — refactor subject (verified 7 callsites + sub-call inventory)
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/libraries/EntropyLib.sol` — API stable (43 lines total)
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameJackpotModule.sol` lines 2180-2231 — BAF deferral subject (SURF-02); plus EntropyLib callsite inventory at L285/L453/L532/L610/L612/L886/L1176/L1873/L2192 (SURF-04)
- `/home/zak/Dev/PurgeGame/degenerus-audit/contracts/modules/DegenerusGameMintModule.sol` line 652 — SURF-03 subject
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/FINDINGS-v35.0.md` lines 1-563 — primary template for Phase 266 deliverable shape
- `/home/zak/Dev/PurgeGame/degenerus-audit/audit/FINDINGS-v34.0.md` lines 43, 138-579 — secondary template + EXC-04 v34 prose precedent
- `/home/zak/Dev/PurgeGame/degenerus-audit/KNOWN-ISSUES.md` — current state at HEAD `5db8682b` (UNMODIFIED at v35.0 close); EntropyLib XOR-shift entry at L31
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/stat/PerPullLevelDistribution.test.js` — chi² infrastructure source (Phase 261/264 STAT-04 pattern; `makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` at L78-102)
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/stat/TraitDistribution.test.js` — chi² infrastructure origin (L48-100)
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/stat/SurfaceRegression.test.js` — SURF cross-surface preservation pattern (PROTECTED_RANGES + git-diff hunk-intersection harness)
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/gas/Phase264GasRegression.test.js` — GAS regression pattern (REF-CAPTURE + theoretical-worst-case opcode walk header at L18-100)
- `/home/zak/Dev/PurgeGame/degenerus-audit/test/gas/AdvanceGameGas.test.js` — GAS-02 1.99× margin extension target
- `/home/zak/Dev/PurgeGame/degenerus-audit/.planning/config.json` — `commit_docs: true`; `nyquist_validation: false` (validation section optional but useful)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/MEMORY.md` + `feedback_*.md` artifacts — project-specific approval/methodology constraints

### Secondary (MEDIUM confidence — derived from primary)

- Bit-bias arithmetic table (Bit-Budget Worked Table section) — derived from D-266-BIT-BUDGET-01 + standard `2^N mod K / 2^N` modulo-bias formula
- Sample-budget calibration (Pitfall 1 table) — derived from chi² rule-of-thumb (expected ≥ 5/bucket) + Phase 264 STAT-01 precedent (10K aggregated samples for df=7)
- Sub-call entropy consumer enumeration (`_lootboxDgnrsReward` L1680, `_rollLootboxBoons` L1059) — discovered via grep `entropy %\|entropy /` in `DegenerusGameLootboxModule.sol`
- 5-wave plan decomposition recommendation — derived from v34 Phase 262 / v35 Phase 265 single-plan multi-task atomic-commit-per-task pattern

### Tertiary (LOW confidence — none)

No findings rest on training-data hypothesis only. All recommendations are grounded in `[VERIFIED]` repo grep, `[CITED]` precedent prose from FINDINGS-v34.0/v35.0, or arithmetic derivable from locked CONTEXT.md decisions.

---

## Metadata

**Confidence breakdown:**

- Standard stack: **HIGH** — verified via repo grep + project_basics.md
- Refactor architecture: **HIGH** — locked decisions in CONTEXT.md + worked bit-budget table grounded in arithmetic
- Statistical validation: **HIGH** — chi² infrastructure already in repo at known locations; sample-budget calibration is standard
- Gas regression: **HIGH** — REF-CAPTURE + theoretical-worst-case pattern proven at Phase 264
- Cross-surface preservation: **HIGH** — methodology proven across v33/v34/v35; PROTECTED_RANGES grep-proof pattern
- Audit deliverable: **HIGH** — 9-section template fully locked from v33/v34/v35 carry chain
- Pitfalls: **HIGH** — derived from concrete file reads (L1585 dead step, L1680 sub-call, etc.) and chi² rule of thumb
- Plan decomposition: **MEDIUM** — single-plan precedent locked; task count is estimate (±3 tasks)

**Research date:** 2026-05-10
**Valid until:** 2026-06-10 (30-day window for stable contract-tree state; if Phase 266 execution slips past 2026-06-10, re-verify v35.0 baseline `5db8682b` is still accurate)
