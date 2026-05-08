---
phase: 259-trait-distribution-split
plan: 02
subsystem: trait-utils-test-harness
tags: [solidity, test-harness, trait-distribution, hardhat]
requirements-completed: [TRAIT-05, TRAIT-06]
dependency-graph:
  requires:
    - "contracts/DegenerusTraitUtils.sol post-Plan-01 signatures (working-tree, uncommitted)"
    - "contracts/test/PriceLookupTester.sol reference pattern"
  provides:
    - "External-pure entry points for the three internal-pure DegenerusTraitUtils functions"
    - "Hardhat-deployable harness for Plan 03 boundary + composition + byte-layout tests"
  affects:
    - "test/unit/DegenerusTraitUtils.test.js (Plan 03; consumes via getContractFactory('TraitUtilsTester'))"
tech-stack:
  added: []
  patterns:
    - "PriceLookupTester pattern (internal-pure library passthrough harness in contracts/test/)"
key-files:
  created:
    - "contracts/test/TraitUtilsTester.sol"
  modified: []
decisions:
  - "Mirror PriceLookupTester verbatim minus the lazyPassCost aggregate (D-01) — three plain external-pure passthroughs, no helpers, no state"
  - "Diff staged but UN-COMMITTED — awaiting batched approval at phase close (D-10)"
metrics:
  duration: "~5 minutes"
  completed: "2026-05-08"
  tasks: 1
  files: 1
---

# Phase 259 Plan 02: TraitUtilsTester Harness Summary

**STATUS: contract diff staged but UN-COMMITTED — awaiting batched approval at phase close per D-10.**

One-liner: External-pure passthrough harness exposing `DegenerusTraitUtils.{weightedColorBucket, traitFromWord, packedTraitsFromSeed}` so Hardhat JS tests in Plan 03 can invoke the otherwise-internal library functions directly.

## What Was Built

Single new file: `contracts/test/TraitUtilsTester.sol`. Mirrors `contracts/test/PriceLookupTester.sol` verbatim minus its `lazyPassCost` aggregate (per D-01 — Plan 03 does all aggregation in JS). No state, no helpers, no aggregates — three plain `external pure` passthroughs.

### Exposed signatures

```solidity
function weightedColorBucket(uint32 rnd) external pure returns (uint8);
function traitFromWord(uint64 rnd)       external pure returns (uint8);
function packedTraitsFromSeed(uint256 rand) external pure returns (uint32);
```

Each body is a single-line `return DegenerusTraitUtils.{name}(args);`. The library is imported via `import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";` (the `contracts/test/` subfolder is one level below `contracts/`, identical to how `PriceLookupTester.sol` reaches `../libraries/PriceLookupLib.sol`).

## Verification Gates (all passed)

- `npx hardhat compile` → exit 0; "Compiled 1 Solidity file successfully (evm target: paris)" — compiles cleanly against the post-Plan-01 library in the working tree.
- `grep -c 'contract TraitUtilsTester' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c 'function weightedColorBucket(uint32 rnd) external pure returns (uint8)' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c 'function traitFromWord(uint64 rnd) external pure returns (uint8)' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c 'function packedTraitsFromSeed(uint256 rand) external pure returns (uint32)' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c 'import {DegenerusTraitUtils} from "../DegenerusTraitUtils.sol";' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c 'pragma solidity 0.8.34;' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -c '// SPDX-License-Identifier: AGPL-3.0-only' contracts/test/TraitUtilsTester.sol` → 1.
- `grep -nE '(state |mapping|storage|private )' contracts/test/TraitUtilsTester.sol` → 0 hits (statelessness confirmed; harness is purely a passthrough).
- `git status --short` shows `contracts/test/TraitUtilsTester.sol` as a new untracked (`??`) file alongside `contracts/DegenerusTraitUtils.sol` (Plan 01) as modified (` M`); both UN-staged, UN-committed, ready for the orchestrator's phase-close batched approval (D-10).

## Acceptance Criteria — ALL MET

- [x] `contracts/test/TraitUtilsTester.sol` exists and compiles under `pragma solidity 0.8.34`.
- [x] Three external-pure passthroughs with the exact signatures from D-01 — no transformation, no clamping, no caching.
- [x] No state, no mapping, no storage references, no private helpers — verified by negative grep.
- [x] No aggregate function (the `PriceLookupTester.lazyPassCost` analogue is intentionally NOT replicated per D-01).
- [x] Mirror of `PriceLookupTester.sol` style — same SPDX header, same pragma, same natspec shape.
- [x] Diff staged but UN-COMMITTED for D-10 batched approval. `git status` reflects untracked posture.

## Deviations from Plan

None — plan executed exactly as written. The harness file matches the verbatim form in `<task type="auto">` `<action>` block character-for-character.

## Threat Model Disposition

All three threats from Plan 259-02 `<threat_model>` addressed:

- **T-259-02-01 (Tampering, mitigate):** Harness signatures match the library signatures byte-for-byte (`weightedColorBucket(uint32) → uint8`, `traitFromWord(uint64) → uint8`, `packedTraitsFromSeed(uint256) → uint32`). Acceptance-criteria literal greps enforce this; any drift would fail Plan 03 chai assertions immediately.
- **T-259-02-02 (Elevation of Privilege, accept):** File lives under `contracts/test/`. No script in `script/` references `TraitUtilsTester`. No state, no funds, no admin functions — only pure passthroughs to a public-domain library. Zero attack surface even if accidentally deployed.
- **T-259-02-03 (Information Disclosure, mitigate):** Each passthrough is a single `return DegenerusTraitUtils.foo(args);` call. The `(state |mapping|storage|private )` grep returns zero hits — statelessness confirmed.

## Threat Flags

None — the harness exposes only pre-existing internal-pure library logic. Adds no new on-chain trust boundary, no new auth path, no new file I/O, no schema change. Test-only contract under `contracts/test/`.

## Known Stubs

None. The contract is feature-complete for its purpose (Plan 03 consumption); no placeholder data, no TODO markers, no empty-default returns flowing to UI.

## Commit Posture

- **`contracts/test/TraitUtilsTester.sol`:** untracked, NOT committed — awaiting Phase 259 close batched approval per D-10.
- **`contracts/DegenerusTraitUtils.sol`:** modified-but-unstaged from Plan 01, NOT committed — awaiting same Phase 259 close batched approval per D-10.
- **This SUMMARY + STATE.md + ROADMAP.md:** committed as the per-plan documentation commit (no `contracts/` or `test/` content in the commit).

The orchestrator collects all Phase 259 contract diffs at phase close, presents them as one diff for explicit user review, and commits only after explicit user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`.

## Self-Check: PASSED

- Created file present: `contracts/test/TraitUtilsTester.sol` — confirmed via `test -f` and `git status` showing `??` (untracked).
- All eight grep gates from `<verify>` returned the expected counts (1, 1, 1, 1, 1, 1, 1, 1) plus statelessness gate returned 0 hits.
- `npx hardhat compile` exit 0 confirmed (compiled 1 Solidity file successfully against the working-tree post-Plan-01 library).
- Plan 01 file (`contracts/DegenerusTraitUtils.sol`) intentionally untouched — `git diff` shows it identical to its pre-Plan-02 state, modified-but-unstaged.
- Documentation commit will include only `.planning/` files, never `contracts/test/TraitUtilsTester.sol` or `contracts/DegenerusTraitUtils.sol`.
