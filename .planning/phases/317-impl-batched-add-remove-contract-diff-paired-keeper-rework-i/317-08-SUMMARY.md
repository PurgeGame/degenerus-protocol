---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 08
subsystem: testing
type: gap_closure
tags: [storage-slot-rederivation, inline-slot-literals, vrf-freeze-slots, lootboxRng-family, test-harness-only, 317-06-gap]

# Dependency graph
requires:
  - phase: 317-06
    provides: "Named SLOT_* constant re-derivation (incomplete — missed every INLINE slot literal in the lootboxRng family helpers + several stale doc comments + the JS BigInt literals)"
  - phase: 317-01
    provides: "Pre-deletion baseline (71/446/16) + the −2 slot-shift family table + LootboxBoonCoexistence already-stale flag"
provides:
  - "ALL stale lootboxRng-family test-side slot references re-derived to the authoritative post-deletion layout (lootboxRngPacked 35, lootboxRngWordByIndex 36) — named constants, INLINE uint256(N) keccak/vm.load literals, JS BigInt Nn literals, AND doc comments, disambiguated by target variable"
  - "Empirical no-new-failures proof: the post-fix Foundry per-TEST failing set == the current-HEAD per-TEST failing set (ZERO newly-failing tests; named-diff, not just counts)"
  - "Characterization of TWO pre-existing, out-of-scope environmental blockers at HEAD d6b79b3b (AF_KING=address(0) deploy-fixture revert + hardhat deploy-patch dropping AF_KING) that block empirical exercise of the slot-fixed suites — handed to Phase 318"
affects: [318, vrf-freeze-invariant, slot-re-derivation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Re-derive EVERY slot reference (named constant + INLINE literal + JS BigInt + comment) from ONE authoritative forge inspect, disambiguated by WHICH VARIABLE the site targets — never by bare numeric value, never patch-by-arithmetic"
    - "Establish the no-new-failures baseline against the CURRENT HEAD (post-contract-diff), not a stale pre-deletion snapshot, when the contract tree has changed since that snapshot"

key-files:
  created:
    - ".planning/phases/317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i/317-08-SUMMARY.md"
  modified:
    - "test/fuzz/DegeneretteFreezeResolution.t.sol"
    - "test/fuzz/TicketLifecycle.t.sol"
    - "test/fuzz/VRFCore.t.sol"
    - "test/fuzz/VRFPathCoverage.t.sol"
    - "test/fuzz/VRFStallEdgeCases.t.sol"
    - "test/fuzz/VrfRotationLiveness.t.sol"
    - "test/fuzz/VrfRotationOrphanIndex.t.sol"
    - "test/fuzz/LootboxRngLifecycle.t.sol"
    - "test/fuzz/StallResilience.t.sol"
    - "test/fuzz/RngIndexDrainBinding.t.sol"
    - "test/fuzz/handlers/VRFPathHandler.sol"
    - "test/fuzz/handlers/RngIndexDrainHandler.sol"
    - "test/gas/Phase268GasRegression.test.js"
    - "test/stat/DegenerettePerNEvExactness.test.js"
    - "test/edge/HeroOverrideDayIndex.test.js"
    - "test/edge/HeroOverrideWeightedRoll.test.js"

key-decisions:
  - "317-06 fixed named SLOT_* constants but left every INLINE slot literal (uint256(37)/uint256(38)/uint256(39) inside vm.load / keccak256(abi.encode(...)) helpers) and several stale doc comments + JS 38n/39n literals stale. This plan re-derived ALL of them, disambiguated by the variable each site reads (lootboxRngPacked→35, lootboxRngWordByIndex→36), NOT by the bare number."
  - "The 317-01 baseline (71/446/16, 533 total) is STALE — it predates the post-deletion contract diff (df4ef365). The current HEAD (d6b79b3b) deploy fixture reverts in setUp for ~half the suites (AF_KING=address(0)), so the no-new-failures gate was measured against a fresh CURRENT-HEAD baseline captured by stashing the slot edits, NOT the stale 71-count."
  - "Two pre-existing environmental blockers (AF_KING=0 Foundry setUp revert; hardhat deploy-patch dropping AF_KING) are OUT OF SCOPE (test-harness-only mandate forbids production-contract changes) and are recorded for Phase 318. The slot fixes are deterministically correct against forge inspect; they cannot be exercised through the affected suites until the fixture is repaired."

requirements-completed: [RM-06]

# Metrics
duration: ~50min
completed: 2026-05-23
---

# Phase 317 Plan 08: lootboxRng-Family Slot Re-Derivation Gap Closure Summary

**Closed the 317-06 gap: 317-06 updated only the named `SLOT_*` constants and missed every INLINE slot literal in the lootboxRng-family helpers (`uint256(37)`/`uint256(38)`/`uint256(39)` inside `vm.load` and `keccak256(abi.encode(...))`), plus several stale doc comments and the JS `38n`/`39n` BigInt literals. This plan comprehensively re-derived ALL stale lootboxRng-family test-side slot references against the authoritative post-deletion `forge inspect` layout (lootboxRngPacked → 35, lootboxRngWordByIndex → 36), disambiguated by the variable each site targets. `forge build` PASSES; the post-fix Foundry per-TEST failing set is byte-identical to the current-HEAD baseline — ZERO newly-failing tests. Two pre-existing, out-of-scope deploy-fixture blockers (AF_KING=address(0)) that prevent empirical exercise of the slot-fixed suites are handed to Phase 318. Test-harness-only; zero production-contract mutation.**

## Authoritative Post-Deletion Slot Map (confirmed this plan via `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout`)

| Var | Live slot | Pre-deletion | Net |
|-----|----------:|-------------:|-----|
| `lootboxEth` | 15 | 15 | 0 |
| `lootboxEthBase` | 19 | 20 | −1 |
| `vrfCoordinator` | 32 | 34 | −2 |
| `vrfKeyHash` | 33 | 35 | −2 |
| `vrfSubscriptionId` | 34 | 36 | −2 |
| `lootboxRngPacked` (low 48 bits = lootboxRngIndex) | **35** | 37 | −2 |
| `lootboxRngWordByIndex` (mapping; key = keccak256(abi.encode(index, 36))) | **36** | 38 | −2 |
| `lootboxDay` | 37 | 39 | −2 |
| `lootboxPurchasePacked` | 38 | 40 | −2 |
| `lootboxBurnie` | 39 | 41 | −2 |
| `degeneretteBets` | 43 | 45 | −2 |
| `lootboxEvBenefitUsedByLevel` | 45 | 47 | −2 |
| `boonPacked` | 59 | 61 | −2 |
| `boxCursor` / `boxCursorIndex` | 60 | (new) | new |
| `boxPlayers` | 61 | (new) | new |

Disambiguation rule applied at every site: `37` labelled `lootboxDay` is CORRECT (left untouched, e.g. `LootboxBoonCoexistence.t.sol:SLOT_LOOTBOX_DAY=37`); `37` labelled `lootboxRngPacked` is stale → 35; `38` labelled `lootboxPurchasePacked` is correct, `38` labelled lootboxRngPacked/word is stale; `39` labelled `lootboxBurnie` is correct, `39` labelled lootboxRngWordByIndex is stale → 36.

## Per-File Corrections (var → old→new slot)

| File | Site | Kind | Var | Old → New |
|------|------|------|-----|-----------|
| `test/fuzz/DegeneretteFreezeResolution.t.sol` | L37 | named const `LOOTBOX_RNG_WORD_SLOT` | lootboxRngWordByIndex | 39 → 36 |
| | L40 | named const `LOOTBOX_RNG_PACKED_SLOT` | lootboxRngPacked | 38 → 35 |
| | L39/L60/L337 | doc comments | both | 38/39 → 35/36 |
| `test/fuzz/TicketLifecycle.t.sol` | L2048 | INLINE `vm.load(uint256(38))` | lootboxRngIndex (lootboxRngPacked) | 38 → 35 |
| | L2053 | INLINE keccak `uint256(39)` | lootboxRngWordByIndex | 39 → 36 |
| | L2093 | named const `LOOTBOX_RNG_WORD_SLOT` | lootboxRngWordByIndex | 39 → 36 |
| | L2046/2051/2092/2139/2140 | doc comments | both | 38/39 → 35/36 |
| `test/fuzz/VRFCore.t.sol` | L54 | INLINE `vm.load(uint256(37))` | lootboxRngIndex | 37 → 35 |
| `test/fuzz/VRFPathCoverage.t.sol` | L57 | INLINE `vm.load(uint256(37))` | lootboxRngIndex | 37 → 35 |
| | L62 | INLINE keccak `uint256(38)` | lootboxRngWordByIndex | 38 → 36 |
| `test/fuzz/VRFStallEdgeCases.t.sol` | L80 | INLINE `vm.load(uint256(37))` | lootboxRngIndex | 37 → 35 |
| | L85 | INLINE keccak `uint256(38)` | lootboxRngWordByIndex | 38 → 36 |
| | L473/L483 | doc comments | lootboxRngPacked | 37 → 35 |
| `test/fuzz/VrfRotationLiveness.t.sol` | L31-33/L62 | doc comments | both | 37/38 → 35/36 |
| `test/fuzz/VrfRotationOrphanIndex.t.sol` | L15-17/L42 | doc comments | both | 37/38 → 35/36 |
| `test/fuzz/LootboxRngLifecycle.t.sol` | L105 | INLINE `vm.load(uint256(38))` | lootboxRngIndex | 38 → 35 |
| | L110 | INLINE keccak `uint256(39)` | lootboxRngWordByIndex | 39 → 36 |
| | L103/L108 | doc comments | both | 38/39 → 35/36 |
| `test/fuzz/StallResilience.t.sol` | L32 | INLINE `vm.load(uint256(37))` | lootboxRngIndex | 37 → 35 |
| | L37 | INLINE keccak `uint256(38)` | lootboxRngWordByIndex | 38 → 36 |
| `test/fuzz/RngIndexDrainBinding.t.sol` | L44 | doc comment | LR_INDEX (lootboxRngPacked) | 38 → 35 |
| `test/fuzz/handlers/VRFPathHandler.sol` | L50 | INLINE `vm.load(uint256(38))` | lootboxRngIndex | 38 → 35 |
| | L61 | INLINE keccak `uint256(39)` | lootboxRngWordByIndex | 39 → 36 |
| `test/fuzz/handlers/RngIndexDrainHandler.sol` | L114 | doc comment | LR_INDEX | 38 → 35 |
| `test/gas/Phase268GasRegression.test.js` | L148 | JS BigInt `LOOTBOX_RNG_WORD_SLOT=39n` | lootboxRngWordByIndex | 39n → 36n |
| | L149 | JS BigInt `LOOTBOX_RNG_PACKED_SLOT=38n` | lootboxRngPacked | 38n → 35n |
| | L146 | doc comment | word | 39 → 36 |
| `test/stat/DegenerettePerNEvExactness.test.js` | L352 | JS BigInt inline `39n` (keccak base) | lootboxRngWordByIndex | 39n → 36n |
| | L345 | doc comment | word | 39 → 36 |
| `test/edge/HeroOverrideDayIndex.test.js` | L62 | JS `(37).toString(16)` slot literal | lootboxRngPacked | 37 → 35 |
| | L60 | doc comment | lootboxRngPacked | 37 → 35 |
| `test/edge/HeroOverrideWeightedRoll.test.js` | L205 | JS `(37).toString(16)` slot literal | lootboxRngPacked | 37 → 35 |

**Left untouched (correct against the live layout — verified):** `LootboxBoonCoexistence.t.sol` (`SLOT_BOON_PACKED=59`, `SLOT_LOOTBOX_ETH=15`, `SLOT_LOOTBOX_RNG_IDX=35`, `SLOT_LOOTBOX_WORD=36`, `SLOT_LOOTBOX_DAY=37`, `SLOT_LOOTBOX_BASE=19`, `SLOT_LOOTBOX_EV=45`); `RngIndexDrainHandler.sol`/`RngIndexDrainBinding.t.sol` named constants (`SLOT_LR_INDEX=35`, `SLOT_LOOTBOX_MAPPING=36`); `RngLockDeterminism.t.sol`/`RngLockRotationDeterminism.t.sol` (`SLOT_LOOTBOX_RNG_INDEX=35`, `SLOT_LOOTBOX_RNG_WORD_BY_INDEX=36`); `VrfRotation*` named constants (`SLOT_LOOTBOX_PACKED=35`, `SLOT_LOOTBOX_WORD_MAP=36`); `VRFStallEdgeCases.t.sol:SLOT_LOOTBOX_RNG_PACKED=35`; `AffiliateDgnrsClaim.t.sol` (23/24); `MintCleanupRegression.test.js` (35n/36n) — all confirmed already correct from 317-06.

## Empirical Verification

### Foundry suite — command + counts

- **Command (the 317-01 baseline profile):** `FOUNDRY_PROFILE=default forge test --no-match-path "test/**/*.fork.t.sol"` (fast non-deep profile: fuzz `runs=1000`, invariant `runs=256`/`depth=128`; fork tests excluded).
- **317-01 baseline (STALE — pre-deletion tree, before contract diff `df4ef365`):** 71 failing / 446 passing / 16 skipped (533 total).
- **CURRENT-HEAD baseline (HEAD `d6b79b3b`, post-deletion contract diff + 317-06, slot edits stashed away):** **66 failing / 131 passing / 0 skipped (197 total)**, 41 failing suites.
- **POST-FIX (HEAD + this plan's slot edits):** **66 failing / 131 passing / 0 skipped (197 total)**, 41 failing suites.

The 197-vs-533 collapse is NOT caused by this plan — it is the pre-existing AF_KING=address(0) deploy-fixture revert at the current HEAD (see Blockers). The 317-01 baseline is stale relative to the current contract tree, so the no-new-failures gate is measured against the CURRENT-HEAD baseline (captured by `git stash`-ing the slot edits, running, then `stash pop`).

### Newly-failing-test list — EMPTY (named per-TEST diff, not counts)

```
$ comm -13 <prefix-current-HEAD failing tests> <postfix failing tests>
(empty)
```

The post-fix per-TEST failing set is **byte-identical** to the current-HEAD per-TEST failing set (27 distinct deduped failing-test signatures each; symmetric diff empty in both directions). **ZERO newly-failing tests attributable to the slot shift.** Representative pre-existing failures (all present pre- and post-fix): `setUp() [call to non-contract 0x0]` (82 occurrences — the AF_KING=0 deploy block), `panic 0x11` ticket-routing/queue tests (`testWriteReadIsolation`, `testFarFutureRoutesToFFKey`, …), `RngLocked()`-vs-`panic` guard mismatches, `testFreezeUnfreezeRoundTrip`/`testMultiDayAccumulatorPersistence` assertion failures. These match the 317-01 known-baseline failure families (panic 0x11, freeze assertions) plus the new AF_KING-deploy family introduced by the contract diff — none caused by the slot re-derivation.

### Build

`FOUNDRY_PROFILE=default forge build` → exit 0 (only advisory forge-lint warnings: unsafe-typecast, variable shadowing — house style; zero `Error (`).

### Hardhat (.test.js) targeted verification — DEFERRED to Phase 318 (blocked, see Blockers)

The four touched hardhat files (`Phase268GasRegression`, `DegenerettePerNEvExactness`, `HeroOverrideDayIndex`, `HeroOverrideWeightedRoll`) could NOT be run: `npx hardhat compile` fails with `TypeError: Member "AF_KING" not found ... type(library ContractAddresses)` at `BurnieCoin.sol:534`. Root cause: the hardhat compile step triggers a deploy-address-patch hook that **rewrites `contracts/ContractAddresses.sol` with deploy-predicted addresses and drops the `AF_KING` constant** (the deploy template predates the AF_KING addition). This is a pre-existing hardhat-fixture defect, NOT a slot issue. The slot fixes in these JS files are deterministic (verified against the same `forge inspect` layout: lootboxRngPacked=35, word mapping=36) and are applied; their full empirical run is **deferred to Phase 318** once the hardhat deploy template includes `AF_KING`.

> NOTE — recovery performed: the hardhat compile mutated `contracts/ContractAddresses.sol` in the working tree. This was immediately reverted with `git checkout -- contracts/ContractAddresses.sol`; `contracts/` is verified CLEAN at HEAD (AF_KING restored at `:53`). No production contract is left mutated.

## Blockers Handed to Phase 318 (pre-existing, OUT OF SCOPE here)

1. **Foundry: `DeployProtocol.setUp()` reverts "call to non-contract address 0x0"** (82 tests, ~41 suites — including ALL 10 slot-fixed VRF/lootbox suites: `VRFCore`, `VRFPathCoverage`, `VRFStallEdgeCases`, `VrfRotationLiveness`, `VrfRotationOrphanIndex`, `LootboxRngLifecycle`, `StallResilience`, `DegeneretteFreezeResolution`, `TicketLifecycle`, `RngIndexDrainBinding`). Root cause traced: `ContractAddresses.AF_KING == address(0)`; the SUB-09 self-subscribe added by the contract diff (`DegenerusVault.sol:473` and `StakedDegenerusStonk.sol:379`: `afKing.subscribe(...)` on `IAfKingSubscribe(ContractAddresses.AF_KING)`) calls into `address(0)`. Fix (Phase 318): deploy a mock AfKing in the fixture and patch `AF_KING`, or guard the self-subscribe when `AF_KING == address(0)`.
2. **Hardhat: deploy-patch hook drops `AF_KING`** from `contracts/ContractAddresses.sol` during compile → `BurnieCoin.sol:534` fails to compile. Fix (Phase 318): add `AF_KING` to the hardhat deploy address template.

Because every slot-fixed VRF/lootbox suite is in blocker #1's setUp-revert set, the slot reads in those helpers are not reached at the current HEAD — the slot fixes are proven correct by direct derivation against `forge inspect`, and will be exercised once Phase 318 repairs the fixture.

## Deviations from Plan

### Auto-fixed / boundary items

**1. [Rule 3 - Blocking, recovered] Hardhat compile mutated a production contract**
- **Found during:** hardhat-side targeted verification.
- **Issue:** `npx hardhat compile` ran a deploy-address-patch hook that overwrote `contracts/ContractAddresses.sol` (changed all module/component addresses + dropped `AF_KING`), leaving a production contract dirty.
- **Fix:** reverted with `git checkout -- contracts/ContractAddresses.sol`; verified `contracts/` clean and `AF_KING` restored at `:53`. No further hardhat compiles attempted; the JS slot fixes are applied deterministically and their full run deferred to Phase 318.

**2. [Rule 4 - Architectural, recorded not actioned] Deploy-fixture AF_KING=address(0) blockers**
- **Found during:** Foundry suite run + hardhat compile.
- **Issue:** the post-deletion contract diff wired SUB-09 self-subscribe to `ContractAddresses.AF_KING` which is still `address(0)`, breaking both the Foundry deploy fixture (setUp revert) and the hardhat deploy-patch template.
- **Action:** recorded for Phase 318 (test-harness-only mandate forbids production-contract changes; this requires either a fixture deploy of a mock AfKing or a production-side guard, both Phase-318 scope). Not actioned here.

### Baseline note
The 317-01 baseline (71/446/16, 533 total) is stale — captured pre-contract-diff. The no-new-failures gate was correctly measured against a freshly-captured CURRENT-HEAD baseline (66/131/0, 197 total) via stash-run-pop, and the named per-TEST diff is empty.

## Known Stubs

None introduced.

## Self-Check: PASSED

- `317-08-SUMMARY.md` present on disk (uncommitted; `.planning/` is gitignored) — FOUND.
- `forge inspect` confirmed the authoritative live layout (lootboxRngPacked=35, lootboxRngWordByIndex=36, lootboxDay=37, boonPacked=59, lootboxEthBase=19, vrfCoordinator=32) — matches the objective map exactly.
- `forge build` exit 0 on the patched tree.
- All 16 touched files are under `test/`; `contracts/`, `contracts/test/`, `contracts/mocks/` verified CLEAN (the inadvertent `ContractAddresses.sol` mutation was reverted).
- Foundry post-fix per-TEST failing set == current-HEAD per-TEST failing set; NEWLY-FAILING list EMPTY.
- `LootboxBoonCoexistence.t.sol:SLOT_LOOTBOX_DAY=37` correctly preserved (untouched); no `37→35` blind replacement performed — every site disambiguated by target variable.
- No production contract mutated; nothing pushed.

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Plan: 08 (gap closure)*
*Completed: 2026-05-23*
