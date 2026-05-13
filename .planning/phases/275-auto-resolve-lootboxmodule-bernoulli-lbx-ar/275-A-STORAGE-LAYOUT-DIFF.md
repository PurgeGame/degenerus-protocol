# Phase 275 / Plan A — Storage-Layout Byte-Identity Proof

**Requirement:** LBX-AR-05 (storage layout byte-identical to v39 baseline).
**Decision:** D-275-NOOP-01 (no `_queueTicketsScaled` retirement; no new state); D-275-HOIST-01 (Bernoulli hoisted as function-scope locals, never contract-scope state).

## Baseline vs HEAD

| Side | Commit | File state |
|------|--------|------------|
| v39 baseline | `6a7455d1` (`audit(274): §9 closure attestation block + 274-01-SUMMARY.md`) | `contracts/modules/DegenerusGameLootboxModule.sol` at v39.0 close |
| Phase 275 pre-commit | `4c581222` working tree + Task 1 edits | Same file with Bernoulli hoist + auto-resolve `_queueTickets(whole)` swap + NatSpec update |

Phase 275 has shipped no contract commits between `6a7455d1` and the current Task 1 working-tree edits — the v39 baseline of `DegenerusGameLootboxModule.sol` is byte-identical to `HEAD:contracts/modules/DegenerusGameLootboxModule.sol` immediately before Task 1.

## Extraction Recipe (worktree-free per `feedback_no_contract_commits.md`)

1. Compile HEAD + Task 1 edits → extract storage-layout JSON from Hardhat build-info for `DegenerusGameLootboxModule` → `/tmp/275-A-layout-HEAD.json`.
2. `cp contracts/modules/DegenerusGameLootboxModule.sol /tmp/275-A-head.sol` (snapshot edits).
3. `git checkout 6a7455d1 -- contracts/modules/DegenerusGameLootboxModule.sol` (single-file rewind).
4. `npx hardhat compile --force` → extract layout → `/tmp/275-A-layout-v39.json`.
5. `cp /tmp/275-A-head.sol contracts/modules/DegenerusGameLootboxModule.sol` (restore Task 1 edits).
6. `npx hardhat compile --force` (re-prime artifacts for HEAD).
7. Strip `astId` (changes with recompile order) and diff on `{slot, offset, label, type}` + `types`.

Recipe uses only `cp` + `git checkout 6a7455d1 -- <single file>` + recompile (worktrees disabled per `feedback_no_contract_commits.md`). NO `git stash` was used — single-file rewind + restore via `cp` snapshot is simpler.

## Verdict

**PASS — storage byte-identical to v39 baseline `6a7455d1`.**

- `storage` array length: **v39 = 83**, **HEAD = 83**.
- Stripped-key diff (`{slot, offset, label, type}` per entry + `types` map): **empty**.
- Per-slot identity confirmed: 0..82 entries map slot/offset/label/type byte-for-byte.

```
$ diff /tmp/275-A-layout-v39-stripped.json /tmp/275-A-layout-HEAD-stripped.json
$ echo $?
0
```

## LBX-AR-05 Satisfaction Note

The Bernoulli hoist only moved local-variable declarations (`scaledPre`, `whole`, `frac`, `roundedUp`) within the body of `_resolveLootboxCommon` — no contract-level state variables added or moved. The auto-resolve branch swap (`_queueTicketsScaled(...)` → `_queueTickets(...)`) is a call-target change with no storage-layout implication. NatSpec edits at `:891-892` are comment-only and produce no codegen effect.
