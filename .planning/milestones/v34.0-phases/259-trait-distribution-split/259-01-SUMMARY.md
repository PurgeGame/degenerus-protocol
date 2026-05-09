---
phase: 259-trait-distribution-split
plan: 01
subsystem: trait-utils
tags: [trait-rarity, color-distribution, heavy-tail, bit-slice, library-rewrite]
requirements-completed: [TRAIT-01, TRAIT-02, TRAIT-03, TRAIT-04]
status: contract-diff-staged-uncommitted
provides:
  - "weightedColorBucket(uint32) -> uint8 (8-tier heavy-tail color distribution at 256-resolution thresholds)"
  - "traitFromWord(uint64) -> uint8 (bit-slice composition: weighted color + uniform symbol)"
  - "packedTraitsFromSeed(uint256) -> uint32 (byte layout preserved, natspec updated to color/symbol)"
requires:
  - "v33.0 audit baseline at HEAD 4ce3703d740d3707c88a1af595618120a8168399"
affects:
  - "contracts/modules/DegenerusGameMintModule.sol:581 (signature unchanged - byte-stable consumer)"
  - "contracts/modules/DegenerusGameDegeneretteModule.sol:607 (signature unchanged - byte-stable consumer)"
  - "test/fuzz/DegeneretteFreezeResolution.t.sol:354 (signature unchanged - byte-stable consumer)"
tech-stack:
  added: []
  patterns:
    - "Heavy-tail bucket distribution at 256-resolution thresholds via uint64 intermediate scaling"
    - "Bit-slice axis composition (weighted color from low 32, uniform symbol from high 32)"
key-files:
  created: []
  modified:
    - "contracts/DegenerusTraitUtils.sol (74 insertions, 77 deletions; net -3 lines)"
decisions:
  - "Followed CONTEXT.md D-01..D-06 + D-10 verbatim: locked function bodies, color/symbol terminology, no history comments, batched approval"
  - "Preserved file-header ASCII border style per planner-discretion default (visual consistency)"
  - "Preserved packedTraitsFromSeed body byte-for-byte; only the per-trait byte caption was updated to color/symbol"
metrics:
  duration: "~2 minutes (mechanical rewrite, no investigation needed)"
  completed: "2026-05-08"
  tasks_completed: 1
  files_modified: 1
  commits_for_contract: 0
  commits_for_planning: 1
---

# Phase 259 Plan 01: Trait Distribution Split (Library Rewrite) Summary

**STATUS: contract diff staged but UN-COMMITTED — awaiting batched approval at phase close per D-10.**

The single in-tree contract change (`contracts/DegenerusTraitUtils.sol`) sits modified in the working tree, never staged, never committed. Phase 259 will collect this diff together with Plan 02 (`contracts/test/TraitUtilsTester.sol` test harness) and Plan 03 (`test/unit/DegenerusTraitUtils.test.js`) and present a single combined diff to the user for explicit approval at the end of Wave 2 per `feedback_batch_contract_approval.md` and `feedback_no_contract_commits.md`.

## One-liner

`weightedBucket(uint32)` deleted; replaced by `weightedColorBucket(uint32) → uint8` (heavy-tail 8-tier color distribution at 256-resolution thresholds: 25/25/25/12.5/6.25/3.125/2.344/0.781%); `traitFromWord(uint64)` rewritten to compose `(weightedColorBucket(uint32(rnd)) << 3) | (uint8(rnd >> 32) & 7)`; `packedTraitsFromSeed(uint256)` byte layout preserved verbatim — `[QQ][CCC][SSS]` with quadrant tags `| 64`, `| 128`, `| 192` unchanged.

## What was done

### File modified

**`contracts/DegenerusTraitUtils.sol`** — single-file end-to-end rewrite:

- File-header ASCII block:
  - **TRAIT ID STRUCTURE** box: `Category bucket (0-7)` → `Color tier (0-7)`; `Sub-bucket (0-7)` → `Symbol (0-7)`. Bullet captions switched to color/symbol.
  - **PACKED TRAITS** box: trait-byte caption updated to `Each trait byte: [QQ][CCC][SSS] (quadrant, color, symbol)`.
  - **WEIGHTED DISTRIBUTION** table: rewritten from the legacy 75-bucket flat table (13.3% / 12.0% / 10.7%) to the new 256-resolution heavy-tail table at the locked thresholds. Includes the gold-tier annotation `<- gold tier (1-in-128)` and the 32× rarity-ratio total line.
  - **RANDOM SEED USAGE** box: per-trait captions switched to `(color from low 32, symbol from high 32)`.
  - **SECURITY CONSIDERATIONS** box: unchanged (3 numbered points still accurate).
- Library declaration + natspec preserved verbatim (`@title`, `@author`, `@notice`, `@dev`, `@custom:security-contact`).
- **Section comment for the bucket function** rewritten to `COLOR TIER DISTRIBUTION` with color/symbol terminology and the new percentage line.
- **`weightedBucket(uint32)`** STRUCTURALLY REMOVED. The legacy body (`uint32 scaled = uint32((uint64(rnd) * 75) >> 32)` + 8-branch chain at thresholds 10/20/30/40/49/58/67) is not preserved as a comment, not gated behind a flag, and not retained in any form per D-05 + `feedback_no_history_in_comments.md` + `feedback_no_dead_guards.md`.
- **`weightedColorBucket(uint32 rnd) internal pure returns (uint8)`** added with the locked body verbatim from CONTEXT.md `<specifics>`:
  ```solidity
  unchecked {
      uint32 scaled = uint32((uint64(rnd) * 256) >> 32);
      if (scaled < 64) return 0;
      if (scaled < 128) return 1;
      if (scaled < 192) return 2;
      if (scaled < 224) return 3;
      if (scaled < 240) return 4;
      if (scaled < 248) return 5;
      if (scaled < 254) return 6;
      return 7;
  }
  ```
- **`traitFromWord(uint64 rnd)`** body rewritten to the locked bit-slice composition:
  ```solidity
  uint8 color = weightedColorBucket(uint32(rnd));
  uint8 symbol = uint8(rnd >> 32) & 7;
  return (color << 3) | symbol;
  ```
  Local variables renamed `category` → `color` and `sub` → `symbol` (D-02). The double `weightedBucket` call collapsed to one `weightedColorBucket` call plus a uniform 3-bit slice.
- **`packedTraitsFromSeed(uint256 rand)`** body byte-identical — `traitFromWord(uint64(rand))`, `traitFromWord(uint64(rand >> 64)) | 64`, `traitFromWord(uint64(rand >> 128)) | 128`, `traitFromWord(uint64(rand >> 192)) | 192`, and the same 32-bit pack expression. Only the per-trait byte caption inside the natspec was updated to `(quadrant, color, symbol)`.

### Diff stats
- 74 insertions, 77 deletions (net `-3` lines)
- Single file: `contracts/DegenerusTraitUtils.sol`
- No other contract or test file modified

## Acceptance evidence

All grep gates from the plan's `<verify>` block executed successfully against the post-edit working tree:

| Gate | Command | Expected | Actual |
|------|---------|----------|--------|
| Hardhat compile | `npx hardhat compile` | exit 0, "Compiled" | exit 0, "Compiled 29 Solidity files successfully (evm target: paris)" |
| TRAIT-04 (D-06) | `grep -rwn 'weightedBucket' contracts/` | zero hits | zero hits (exit 1) |
| weightedColorBucket signature | `grep -c 'function weightedColorBucket(uint32 rnd) internal pure returns (uint8)' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| 256-multiplier line | `grep -c 'uint32 scaled = uint32((uint64(rnd) * 256) >> 32);' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| Symbol slice | `grep -c 'uint8 symbol = uint8(rnd >> 32) & 7;' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| Composition return | `grep -c 'return (color << 3) \| symbol;' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| Quadrant tag `\| 64` | `grep -c '\| 64' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| Quadrant tag `\| 128` | `grep -c '\| 128' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| Quadrant tag `\| 192` | `grep -c '\| 192' contracts/DegenerusTraitUtils.sol` | 1 | 1 |
| 8 threshold branches | `grep -nE 'if \(scaled < (64\|128\|192\|224\|240\|248\|254)\) return [0-6];' contracts/DegenerusTraitUtils.sol` | 7 lines | 7 lines (118-124); plus `return 7;` line 125 |
| History-comment ban (D-05) | `grep -nE '(previously\|formerly\|used to\|legacy 13\.3\|13\.3%)' contracts/DegenerusTraitUtils.sol` | zero hits | zero hits (exit 1) |
| Terminology cleanup (D-02) | `grep -winE '(category\|sub-bucket)' contracts/DegenerusTraitUtils.sol` | zero hits | zero hits (exit 1) |
| Standalone `sub` word | `grep -wn 'sub' contracts/DegenerusTraitUtils.sol` | zero hits | zero hits (exit 1) |
| Caller intactness (Mint) | `grep -n 'DegenerusTraitUtils\.' contracts/modules/DegenerusGameMintModule.sol` | line 581 hit on `traitFromWord` | line 15 import + line 581 `DegenerusTraitUtils.traitFromWord(s)` |
| Caller intactness (Degenerette) | `grep -n 'DegenerusTraitUtils\.' contracts/modules/DegenerusGameDegeneretteModule.sol` | line 607 hit on `packedTraitsFromSeed` | line 12 import + line 607 `DegenerusTraitUtils.packedTraitsFromSeed(` |

## Acceptance criteria mapping

| Criterion (from plan) | Status |
|-----------------------|--------|
| `npx hardhat compile` exits 0, no errors | PASS — "Compiled 29 Solidity files successfully" |
| `grep -rwn 'weightedBucket' contracts/` returns zero hits (TRAIT-04) | PASS — zero hits |
| Exactly one `function weightedColorBucket(uint32 rnd) internal pure returns (uint8)` | PASS — 1 |
| Literal line `uint32 scaled = uint32((uint64(rnd) * 256) >> 32);` present (NOT `* 75`) | PASS |
| 8 threshold branches at 64/128/192/224/240/248/254 + final `return 7;` | PASS (lines 118-125) |
| `traitFromWord` contains `uint8 color = weightedColorBucket(uint32(rnd));`, `uint8 symbol = uint8(rnd >> 32) & 7;`, `return (color << 3) \| symbol;` | PASS |
| `packedTraitsFromSeed` preserves `traitFromWord(uint64(rand >> N)) \| {64,128,192}` (TRAIT-03) | PASS |
| No history comments (`previously`/`formerly`/`used to`/`13.3%`) | PASS |
| `grep -wn 'category' ...` returns zero hits (D-02 terminology cleanup) | PASS |
| `git status` shows `contracts/DegenerusTraitUtils.sol` modified, NOT committed (D-10) | PASS |

## Requirements satisfied

- **TRAIT-01** ✅ — `weightedBucket(uint32)` replaced by `weightedColorBucket(uint32 rnd) internal pure returns (uint8)` with 256-resolution thresholds and 8 branches matching the locked color-tier table. Function deleted, not commented-out.
- **TRAIT-02** ✅ — `traitFromWord(uint64 rnd)` rewritten as `(weightedColorBucket(uint32(rnd)) << 3) | (uint8(rnd >> 32) & 7)`; replaces the previous two-`weightedBucket` composition.
- **TRAIT-03** ✅ — `packedTraitsFromSeed(uint256)` byte layout preserved verbatim; quadrant tags `| 64`, `| 128`, `| 192` present at the same locations; `[QQ][CCC][SSS]` 8-bit-per-trait shape unchanged.
- **TRAIT-04** ✅ — `grep -rwn 'weightedBucket' contracts/` returns zero hits; legacy function structurally absent (the `-w` word-boundary flag prevents `weightedColorBucket` false-match). No external caller of the removed function exists in `contracts/`.

TRAIT-05 (boundary unit tests) and TRAIT-06 (composition unit tests) are deferred to Plan 03 per the phase plan-decomposition (Wave 2).

## Decisions Made

- **Followed CONTEXT.md D-01..D-06 + D-10 verbatim.** All locked function bodies, terminology choices, ASCII table contents, and the no-history-comments rule are reflected in the rewrite as-specified.
- **Preserved file-header ASCII border style (`+==…==+`)** per planner-discretion default in CONTEXT.md (visual consistency with the rest of the file's header conventions and with `contracts/test/PriceLookupTester.sol` and other library headers in the tree).
- **`packedTraitsFromSeed` body kept byte-for-byte.** Only the per-trait-byte caption inside the natspec was updated (`(quadrant, category, sub-bucket)` → `(quadrant, color, symbol)`). The function body — including the four `traitFromWord` calls, the three quadrant tags, and the 32-bit pack expression — is verbatim. This matches TRAIT-03 (byte layout preserved) and the threat-register T-259-01-02 mitigation strategy.
- **No history comments anywhere in the file.** The legacy 13.3%/12.0%/10.7% table, the 75-bucket scale-down body, and all "previously was"/"changed from" annotations are absent. This satisfies D-05 and `feedback_no_history_in_comments.md`.
- **Used dash-style bullets (`-`) instead of bullet characters (`•`) in the natspec ASCII boxes.** The original file mixed both; the rewrite uses `-` consistently for portability and to avoid downstream tool issues with non-ASCII characters in source comments. No semantic change, no requirement impact.

## Deviations from Plan

None — plan executed exactly as written. All locked function bodies, terminology, and structural choices match CONTEXT.md `<specifics>` verbatim. No bug-fix or missing-functionality deviations were required.

The plan-prescribed batched-approval posture (D-10) was followed: the contract diff is staged in the working tree but not committed. Only this SUMMARY.md (and the housekeeping STATE.md/ROADMAP.md updates) will be committed under this plan-close commit.

## Threat surface scan

No new threat surface introduced beyond what is already enumerated in the plan's `<threat_model>`:

- **T-259-01-01** (threshold drift) — mitigated by Plan 03 boundary tests at every threshold (`scaled = 0, 63, 64, 127, 128, 191, 192, 223, 224, 239, 240, 247, 248, 253, 254, 255`).
- **T-259-01-02** (byte-layout regression) — mitigated by preserving the `packedTraitsFromSeed` body verbatim; existing Foundry fuzz test `test/fuzz/DegeneretteFreezeResolution.t.sol:354` is the implicit byte-layout regression test (D-09).
- **T-259-01-03** (axis coupling) — mitigated by deriving color from `uint32(rnd)` (low 32) and symbol from `uint8(rnd >> 32) & 7` (high 32); disjoint by construction, verified empirically in Plan 03 (TRAIT-06) and Phase 261 (STAT-02).
- **T-259-01-04** (stale `weightedBucket` reference) — TRAIT-04 grep gate executed (zero hits in `contracts/`); ACCEPTED as in-tree-only with no external upgrade hooks.

## Approval & commit posture (carried forward)

Per `feedback_no_contract_commits.md`, `feedback_batch_contract_approval.md`, `feedback_never_preapprove_contracts.md`, and `feedback_wait_for_approval.md`:

- **Contract diff is UN-COMMITTED.** `git status` after this plan close will show `contracts/DegenerusTraitUtils.sol` modified but not staged. The orchestrator must NOT auto-commit it.
- **No `git add contracts/DegenerusTraitUtils.sol` was attempted.** The PreToolUse hook at `~/.claude/hooks/contract-commit-guard.js` was not exercised by this plan.
- **Phase close (D-10):** Plan 02 (test harness) and Plan 03 (Hardhat tests + TRAIT-04 audit gate + Foundry fuzz regression) will accumulate their own diffs in the working tree. At end of Wave 2, the orchestrator will present the combined diff (`contracts/DegenerusTraitUtils.sol` + `contracts/test/TraitUtilsTester.sol` + `test/unit/DegenerusTraitUtils.test.js`) to the user for one batched explicit approval, then commit per `feedback_manual_review_before_push.md`.

## Self-Check: PASSED

Verified post-write:
- `[ -f contracts/DegenerusTraitUtils.sol ]` → FOUND (modified in working tree per `git status --short`)
- `npx hardhat compile` → exit 0
- All 9 plan-`<verify>` grep gates → PASS (counts match expected)
- All 10 plan-`<acceptance_criteria>` gates → PASS
- `git status` → `contracts/DegenerusTraitUtils.sol` shows as `M` (modified, unstaged) — correct posture for D-10
- Caller surfaces at `DegenerusGameMintModule.sol:581` and `DegenerusGameDegeneretteModule.sol:607` → grep-confirmed intact and binding to the byte-stable signatures

No commits for the contract file (intentional per D-10). The plan-close commit covers SUMMARY.md + STATE.md + ROADMAP.md only.
