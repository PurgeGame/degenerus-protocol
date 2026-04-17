# 230-01 Delta Map: v27.0 Baseline → HEAD

## Preamble

- **Phase:** 230 — Delta Extraction & Scope Map
- **Milestone:** v29.0 Post-v27 Contract Delta Audit
- **Requirements satisfied:** DELTA-01, DELTA-02, DELTA-03
- **Baseline commit:** `14cb45e1` (v27.0 phase execution complete, 2026-04-12 21:55) — per D-01
- **HEAD at generation:** `e5b4f97478f70c5a0b266429f03f5109078679ca` (captured via `git rev-parse HEAD`)
- **Diff command used:** `git diff 14cb45e1..HEAD -- contracts/` — per D-02 (single authoritative source; no synthesis of intermediate commit messages)
- **D-03 rule:** Comment-only, NatSpec-only, and pure-whitespace-formatting changes are classified UNCHANGED even when present in raw `git diff` output. Verification command: `git diff -w --ignore-blank-lines`.
- **D-04 rule:** `private` and `internal` functions are enumerated when they appear in the delta — they are part of the audit surface whenever called by external/public entry points.
- **D-05 section ordering (locked):**
  1. `§1` Function-Level Changelog
  2. `§2` Cross-Module Interaction Map
  3. `§3` Interface Drift Catalog
  4. `§4` Consumer Index
- **D-06 read-only policy:** Post-commit, this file is READ-only. Downstream phases (231-236) that discover a gap record a scope-guard deferral in their own SUMMARY rather than editing this file in place.
- **D-07 changelog format:** Each function row carries file path, full signature, visibility, change type, originating commit SHA(s), and a one-line semantic description.
- **D-08 interaction-map format:** Tabular, five columns — `Caller Function | Callee Function | Call Type | Commit SHA | What Changed`. Greppable; no mermaid diagrams.
- **D-09 scope:** Intra-module calls are implicit in §1 and NOT re-catalogued in §2. Only cross-module chains are tabulated.
- **D-10 interface-drift format:** Per-method PASS/FAIL rows across `IDegenerusGame`, `IDegenerusQuests`, and `IDegenerusGameModules` with columns `Interface | Method Signature | Implementer Contract | Verdict | Notes`.
- **D-11 consumer-index scope:** §4 maps every v29.0 requirement ID (all 25) to specific sections/rows of this document so downstream phases need zero additional discovery.

### Verdict Legend

| Artifact type | Values | Definition |
|---|---|---|
| Function change | `NEW` / `MODIFIED` / `DELETED` / `UNCHANGED` | `UNCHANGED` applies only to comment-only diffs per D-03. A function is `UNCHANGED` only if its body shows zero runtime-relevant change under `git diff -w --ignore-blank-lines`. |
| Interface drift | `PASS` / `FAIL` | `PASS` = implementer signature matches interface declaration at HEAD (identical name, param types, mutability, return types). `FAIL` = any mismatch. |
| Interaction call type | `direct` / `delegatecall` / `self-call` / `selector-call` | `direct` — Solidity `fn(...)` on an external address. `delegatecall` — `address.delegatecall(...)` executing callee code in caller's storage. `self-call` — `IDegenerusGame(address(this)).fn(...)` against Game from a module. `selector-call` — `abi.encodeWithSelector(IFACE.fn.selector, ...)` followed by a raw call/delegatecall. |

## 0. Per-File Delta Baseline

Raw detection commands (recorded verbatim so downstream auditors can reproduce):

```
git diff --name-status 14cb45e1..HEAD -- contracts/
git diff --stat 14cb45e1..HEAD -- contracts/
git log --oneline 14cb45e1..HEAD -- contracts/<path>   # per-file owning-commit attribution
```

| File | Status | Insertions | Deletions | Owning Commit SHAs | Change Category |
|---|---|---|---|---|---|
| `contracts/BurnieCoin.sol` | M | 3 | 1 | `3ad0f8d3` | `decimator-burn-key` |
| `contracts/DegenerusGame.sol` | M | 13 | 9 | `f20a2b5e`, `858d83e4` | `mixed` |
| `contracts/DegenerusQuests.sol` | M | 3 | 13 | `d5284be5` | `quest-weicredit` |
| `contracts/interfaces/IDegenerusGame.sol` | M | 4 | 0 | `858d83e4` | `terminal-decimator-passthrough` |
| `contracts/interfaces/IDegenerusGameModules.sol` | M | 3 | 1 | `52242a10` | `entropy-passthrough` |
| `contracts/interfaces/IDegenerusQuests.sol` | M | 3 | 1 | `d5284be5` | `quest-weicredit` |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | M | 79 | 29 | `2471f8e7`, `52242a10`, `f20a2b5e`, `3ad0f8d3` | `mixed` |
| `contracts/modules/DegenerusGameDecimatorModule.sol` | M | 35 | 2 | `67031e7d` | `decimator-events` |
| `contracts/modules/DegenerusGameJackpotModule.sol` | M | 48 | 65 | `104b5d42`, `20a951df` | `mixed` |
| `contracts/modules/DegenerusGameMintModule.sol` | M | 23 | 29 | `52242a10`, `f20a2b5e`, `d5284be5` | `mixed` |
| `contracts/modules/DegenerusGameWhaleModule.sol` | M | 3 | 3 | `f20a2b5e` | `earlybird-finalize` |
| `contracts/storage/DegenerusGameStorage.sol` | M | 21 | 22 | `f20a2b5e`, `e0a7f7bc` | `mixed` |

**Notes on Change Category assignment:**
- `mixed` is assigned whenever a file is touched by more than two of the 10 enumerated single-theme categories, per the Task-1 rule.
- `DegenerusGame.sol` is flagged `mixed` because it carries both `earlybird-finalize` (f20a2b5e) content and `terminal-decimator-passthrough` (858d83e4) content — two distinct themes.
- `DegenerusGameAdvanceModule.sol` is `mixed` across four SHAs spanning four themes (rnglock-removal, entropy-passthrough, earlybird-finalize, decimator-burn-key).
- `DegenerusGameJackpotModule.sol` is `mixed` across the baf-sentinel (104b5d42) + earlybird-trait-align (20a951df) themes.
- `DegenerusGameMintModule.sol` is `mixed` across entropy-passthrough, earlybird-finalize, and quest-weicredit themes.
- `DegenerusGameStorage.sol` is `mixed` across earlybird-finalize (f20a2b5e) and boon-expose (e0a7f7bc) themes.

Files in scope: 12
Commits in scope: 10 (14cb45e1..HEAD, computed via git log --oneline)

## 1. Function-Level Changelog
<!-- DELTA-01 — populated in task 2 -->

## 2. Cross-Module Interaction Map
<!-- DELTA-02 — populated in task 3 -->

## 3. Interface Drift Catalog
<!-- DELTA-03 — populated in task 4 -->

## 4. Consumer Index
<!-- D-11 — populated in task 6 -->
