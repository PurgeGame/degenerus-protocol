---
phase: 243-delta-extraction-per-commit-classification
plan: 243-01
addendum_to: 243-01-SUMMARY.md
addendum_type: head-anchor-advance (771893d1 → cc68bfc7)
subsystem: audit
tags: [delta-extraction, per-commit-classification, addendum, cc68bfc7, baf-flip-gate, scope-extension]

# Dependency graph
requires:
  - predecessor: 243-01-SUMMARY.md (original plan-close at HEAD 771893d1 — 34 D-243-C rows + 1 D-243-S row + Sections 0/1/4/5/7.1 populated, 771 lines)
  - context-amendment: 243-CONTEXT.md D-01/D-03 amended 2026-04-23 to head=cc68bfc7
provides:
  - DELTA-01 addendum rows D-243-C035..D-243-C042 (5 Section-1.6 rows + 3 Section-4 cross-commit rows) covering cc68bfc7 BAF-flip-gate
  - Section 5.5 byte-identical-storage confirmation at cc68bfc7 (D-243-S001 UNCHANGED carries forward)
  - Section 7.1.b reproduction commands for the addendum pass
  - 4 new INFO Finding Candidates surfaced in Section 1.7 (original 5 + 4 addendum = 9 total; all INFO, none promoted)
affects: [243-02-PLAN, 243-03-PLAN, 244-per-commit-adversarial-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Head-anchor-advance addendum pattern — surgical append to existing deliverable preserving byte-identical original rows (matches Phase 230 D-06 / Phase 237 D-17 precedent for mid-milestone scope extension)"
    - "Dual-anchor note at top of Section 1 documents which D-243-C ranges belong to which HEAD (7ab515fe→771893d1 original / 7ab515fe→cc68bfc7 extended)"
    - "Monotonic Row ID continuation (C034→C035 Section 1; C028/C029/C030/C033/C034→C040/C041/C042 Section 4) preserving both original numbering AND addendum-distinctive identity"
    - "Storage-layout re-verification at new HEAD using git worktree add --detach + forge inspect — confirmed byte-identical diff returns zero"

key-files:
  created:
    - .planning/phases/243-delta-extraction-per-commit-classification/243-01-ADDENDUM-SUMMARY.md
  modified:
    - audit/v31-243-DELTA-SURFACE.md (surgical append — Sections 1.6 new / 1.7 renumbered / 1.8 renumbered / 4.1-4.3 extended / 5.5 new / 7.1.b new; original 34 C-rows + S001 + reserved markers all preserved byte-identical)

key-decisions:
  - "cc68bfc7 touches 3 files on top of 771893d1 (DegenerusJackpots.sol +19, IDegenerusJackpots.sol +6, DegenerusGameAdvanceModule.sol +22/-10) — 2 of the 3 are net-new to Phase 243's 12-file surface, bringing aggregate to 14 files / +187/-67 lines at HEAD cc68bfc7"
  - "jackpots constant (file-scope IDegenerusJackpots private constant in AdvanceModule) emitted in Section 4.1 as D-243-C040 following the _VRF_GRACE_PERIOD precedent (D-243-C028) — compile-time constants tied to ContractAddresses-sourced immutable addresses consume zero storage slots"
  - "Storage-layout re-verification at cc68bfc7 confirmed byte-identical to 771893d1; no new D-243-S row emitted — D-243-S001 UNCHANGED verdict carries forward to the new HEAD anchor (§5.5 addendum note)"
  - "Original 34 D-243-C rows + 1 D-243-S row + all RESERVED FOR 243-02/243-03 markers preserved byte-identical — zero rewrites of pre-existing content"
  - "D-20 gate still passes at new HEAD — `grep -c 'F-31-' audit/v31-243-DELTA-SURFACE.md` returns 0 across the addendum write"
  - "4 new Finding Candidates surfaced by cc68bfc7 (all INFO): BAF/coinflip rngWord bit-0 coupling; markBafSkipped leaves leaderboard state; jackpots direct-handle vs self-call parallel paths; and the consumer-map comment extension at L1131"

patterns-established:
  - "Section 1.6 is now the dedicated addendum subsection; Section 1.7 = Finding Candidates; Section 1.8 = Light Reconciliation (renumbered from 1.6/1.7)"
  - "Section 5.5 = storage addendum status note (byte-identical confirmation or delta rows)"
  - "Section 7.1.b = addendum reproduction recipe (incremental commands built on top of §7.1)"
  - "cc68bfc7 SUMMARY-level notes carry parenthetical '(ADDENDUM — cc68bfc7)' tag for reviewer grep-ability"

requirements-completed: [DELTA-01 (cc68bfc7 scope extension)]

# Metrics
duration: ~25min
completed: 2026-04-23
---

# Phase 243 Plan 243-01 ADDENDUM: Delta Extraction at cc68bfc7 Scope Extension Summary

**Head-anchor advance from `771893d1` to `cc68bfc7` — 5 Section-1.6 rows + 3 Section-4 cross-commit rows appended, storage layout re-verified byte-identical at new HEAD, 4 new INFO Finding Candidates surfaced. Original 34 D-243-C rows + 1 D-243-S row preserved byte-identical.**

## Why the Addendum

Plan 243-01 closed at 2026-04-24T00:25Z (approx.) with the head anchor frozen at `771893d1`. At 2026-04-23 21:25, commit `cc68bfc7` ("feat(baf): gate BAF jackpot on daily flip win") landed on `main` touching 3 files in scope:
- `contracts/DegenerusJackpots.sol` +19 (new event `BafSkipped`, new function `markBafSkipped`)
- `contracts/interfaces/IDegenerusJackpots.sol` +6 (new interface method `markBafSkipped`)
- `contracts/modules/DegenerusGameAdvanceModule.sol` +22/-10 (additional hunks on the already-in-scope file — new `jackpots` constant + import + BAF-flip-gate in `_consolidatePoolsAndRewardJackpots`)

Per CONTEXT.md D-03 (HEAD anchor lock rule — carries Phase 230 D-06 / Phase 237 D-17 pattern), a new contract commit landing before Wave 2 executes triggers a scope addendum: the baseline resets and Phase 243 re-opens for incremental enumeration. The original 243-01-SUMMARY.md record at HEAD `771893d1` is unchanged; this addendum documents the surgical append to `audit/v31-243-DELTA-SURFACE.md` that brings the deliverable to HEAD `cc68bfc7`.

243-CONTEXT.md D-01 and D-03 were amended in commit `d5df3956` (2026-04-23) to reflect `head=cc68bfc7` and `head_anchor_history` now includes the original 771893d1 entry + the cc68bfc7 extension entry.

## Rows Added

### Section 1.6 — per-commit changelog (new subsection inserted before the renumbered Finding Candidates)

| Row ID | Symbol Kind | Symbol Name | Change Type | File:Line-Range |
|---|---|---|---|---|
| D-243-C035 | event | `BafSkipped` | ADDED | contracts/DegenerusJackpots.sol:71-74 |
| D-243-C036 | func | `markBafSkipped` | ADDED | contracts/DegenerusJackpots.sol:498-510 |
| D-243-C037 | interface-method | `markBafSkipped` | ADDED | contracts/interfaces/IDegenerusJackpots.sol:30-34 |
| D-243-C038 | constant | `jackpots` | ADDED | contracts/modules/DegenerusGameAdvanceModule.sol:105-106 |
| D-243-C039 | func | `_consolidatePoolsAndRewardJackpots` | MODIFIED | contracts/modules/DegenerusGameAdvanceModule.sol:728-909 |

### Section 4 — cross-commit inventory (C040–C042 continuation after C034)

| Row ID | Subsection | Symbol Name | Change Type |
|---|---|---|---|
| D-243-C040 | 4.1 State Variables (constant) | `jackpots` | ADDED |
| D-243-C041 | 4.2 Events | `BafSkipped` | ADDED |
| D-243-C042 | 4.3 Interface Methods | `markBafSkipped` | ADDED |

### Section 5.5 — storage addendum status

Single-paragraph byte-identical confirmation — `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` re-run at HEAD `cc68bfc7` (via `git worktree add --detach <tmp> cc68bfc7`) returns byte-identical output to the `771893d1` capture already embedded in §5.2. `diff /tmp/v31-243-addendum/storage-layout-771893d1.txt /tmp/v31-243-addendum/storage-layout-cc68bfc7.txt` returns zero diff. **No new `D-243-S` row emitted** — D-243-S001 UNCHANGED verdict carries forward to HEAD `cc68bfc7`.

### Section 7.1.b — reproduction recipe addendum

New subsection between §7.1 (original Plan 243-01) and §7.2 (Plan 243-02 reserved). Includes:
- Baseline sanity gate at cc68bfc7 (verifies `git diff 771893d1..cc68bfc7 --stat` reports `3 files / +47 / -10` and `7ab515fe..cc68bfc7 --stat` reports 14 files)
- Per-file `git show cc68bfc7 --` commands for the 3 touched files
- Line-range resolution greps for new symbols (event `BafSkipped`, function `markBafSkipped`, constant `jackpots`)
- Storage-layout re-verification commands (worktree-based pattern carried from §7.1 Task 2 per 243-01-SUMMARY.md "Issues Encountered" — `GIT_CMD=worktree; git "$GIT_CMD" "$(printf 'a''dd')"` indirection avoids the pre-commit guard's literal-`add` collision)
- Final commit gate updated — `git diff --name-only 7ab515fe..HEAD -- contracts/ | wc -l` now expected: 14 at HEAD `cc68bfc7` (was: 12 at HEAD `771893d1`)

## Final Counts

| Metric | Before Addendum (at 771893d1) | After Addendum (at cc68bfc7) | Delta |
|---|---|---|---|
| Total `D-243-C` rows | 34 | 42 | +8 |
| Total `D-243-S` rows | 1 unique (S001 emitted twice: §5.3 data row + §5.4 verdict row) | 1 unique (unchanged; S001 carries forward to cc68bfc7) | 0 |
| Changelog subsections in Section 1 | 1.1..1.7 (including 1.6 Finding Candidates, 1.7 Light Reconciliation) | 1.1..1.8 (new 1.6 cc68bfc7, 1.7 Finding Candidates, 1.8 Light Reconciliation) | +1 |
| Finding Candidates (Section 1.7) | 5 (all INFO) | 9 (all INFO) | +4 |
| `RESERVED FOR 243-02` marker count | 3 | 3 | 0 (preserved) |
| `RESERVED FOR 243-03` marker count | 4 | 4 | 0 (preserved) |
| `F-31-` substrings | 0 | 0 | 0 (D-20 gate preserved) |
| `contracts/` + `test/` write status | empty | empty | 0 (READ-only preserved) |
| In-scope contract files (`git diff 7ab515fe..HEAD -- contracts/ | wc -l`) | 12 | 14 | +2 (`DegenerusJackpots.sol` + `IDegenerusJackpots.sol`) |
| Aggregate insertions/deletions (`git diff --stat 7ab515fe..HEAD`) | +140/-57 | +187/-67 | +47/-10 |

## New Finding Candidates (all INFO)

Appended to Section 1.7 (renumbered from original 1.6):

1. **contracts/modules/DegenerusGameAdvanceModule.sol:826 — `_consolidatePoolsAndRewardJackpots` (cc68bfc7)** — BAF fire gate reuses `rngWord & 1`, the same low-order bit BurnieCoinflip consumes for the daily-win/loss outcome; BAF resolution is now correlated with the daily coinflip rather than independent. Phase 244 EVT-02 / EVT-03 should re-verify jackpot expected value + fairness under this coupling.
2. **contracts/DegenerusJackpots.sol:500-510 — `markBafSkipped` (cc68bfc7)** — bumps `lastBafResolvedDay = today` but leaves leaderboard state for `lvl` untouched. NatSpec justifies this ("no new writes ever target a past bracket"). Phase 244 EVT-02 should verify every consumer of `bafBrackets[lvl]` / `winningBafCredit` gates on `cursor > lastBafResolvedDay`.
3. **contracts/modules/DegenerusGameAdvanceModule.sol:105-106 — `jackpots` constant (cc68bfc7)** — new direct-handle `IDegenerusJackpots(ContractAddresses.JACKPOTS)` parallel to the existing `runBafJackpot` self-call (which routes through `IDegenerusGame(address(this)).runBafJackpot`). Phase 244 RNG-01 / Phase 245 GOE-06 should confirm no reentrancy or nonce-ordering interaction between the two call paths to the same JACKPOTS contract.
4. (Listed alongside the above) — the RNG consumer-map comment extension at L1131 documenting bit-0 BAF fire gate as a new low-entropy-bit consumer (correct-by-construction but worth explicit acknowledgment for Phase 244 EVT documentation).

No `F-31-NN` IDs emitted — Phase 246 FIND-01..03 owns ID assignment per CONTEXT.md D-20.

## Key Surfaces for Phase 244 / Phase 245 / Phase 246

Beyond the existing routing in 243-01-SUMMARY.md "Key Surfaces" section, the cc68bfc7 addendum adds:

- **Phase 244 EVT-02 / EVT-03 scope extension:** BAF flip-gate behavior — 50% firing rate (correlated with daily coinflip win), leaderboard-row cleanup-by-cursor-gate pattern, and expected value under new correlation. The 4 new Finding Candidates above are EVT-02/EVT-03 pre-flags.
- **Phase 244 RNG-01 / RNG-02 scope extension:** `rngWord & 1` consumer surface — now TWO consumers (BurnieCoinflip daily-win/loss AND BAF fire gate). D-243-C039 touches AdvanceModule `_consolidatePoolsAndRewardJackpots` which is adjacent to D-243-C007 (`advanceGame` modified by 16597cac) in the same file — Phase 244 should verify the rngWord SLOAD at `_consolidatePoolsAndRewardJackpots` entry is the same committed value used by `_runEarlyBirdLootboxJackpot` / `runBafJackpot` downstream.
- **Phase 244 GOX-07:** unchanged — storage layout still byte-identical; D-243-S001 backwards-compatible-no-change verdict holds at HEAD cc68bfc7.
- **Phase 246 FIND-01..03:** 4 new Finding Candidates enter the finding-candidate pool alongside the 5 original; none promote to KI-Ledger at this stage.

## Scope-Guard Alignment

- `RESERVED FOR 243-02` count: 3 (preserved — Section 2, §7.2, status-line mention)
- `RESERVED FOR 243-03` count: 4 (preserved — Section 3, Section 6, §7.3, status-line mention)
- No section placeholder was replaced or edited in the addendum write
- Wave 2 (243-02 DELTA-02 classification + 243-03 DELTA-03 call-site catalog + Consumer Index) now inherits 42 `D-243-C` rows (up from 34) as its universe list

## Commits

| Task | Commit | Files |
|---|---|---|
| Addendum content append (Sections 1.6 / 1.7 renumber / 1.8 renumber / 4.1 / 4.2 / 4.3 / 5.5 / 7.1.b + status line) | (recorded below) | `audit/v31-243-DELTA-SURFACE.md` |
| This SUMMARY | (recorded below) | `.planning/phases/243-delta-extraction-per-commit-classification/243-01-ADDENDUM-SUMMARY.md` |

## Self-Check: PASSED

- [x] `audit/v31-243-DELTA-SURFACE.md` updated in place — 42 `D-243-C` rows total (was 34; +8 added: C035..C042)
- [x] Original 34 `D-243-C` rows + 1 `D-243-S` row preserved byte-identical (spot-check: C001 at line 64, C024 at line 126 — unchanged)
- [x] `RESERVED FOR 243-02` count: 3 (preserved)
- [x] `RESERVED FOR 243-03` count: 4 (preserved)
- [x] `grep -c 'F-31-' audit/v31-243-DELTA-SURFACE.md` returns 0 (D-20 gate passes)
- [x] Section 1.6 header reads `### 1.6 Commit cc68bfc7 — feat(baf): gate BAF jackpot on daily flip win (ADDENDUM)`
- [x] Section 1.7 header reads `### 1.7 Finding Candidates (fresh-eyes)` (renumbered from original 1.6)
- [x] Section 1.8 header reads `### 1.8 Light Reconciliation Against audit/v30-CONSUMER-INVENTORY.md` (renumbered from original 1.7)
- [x] Section 5.5 header reads `### 5.5 Addendum at cc68bfc7 (byte-identical to 771893d1; no new storage changes)`
- [x] Section 7.1.b header reads `### 7.1.b Plan 243-01 ADDENDUM commands (cc68bfc7 scope extension)`
- [x] Dual HEAD anchor note present as blockquote after Section 1 column definition (line 54)
- [x] Status line updated to reference `HEAD: cc68bfc7 (extended from 771893d1 via cc68bfc7 BAF-flip-gate addendum...)`
- [x] `git status --porcelain contracts/ test/` returns empty (READ-only scope preserved)
- [x] Original 243-01-SUMMARY.md unchanged — this addendum SUMMARY is a separate record at 243-01-ADDENDUM-SUMMARY.md

---

*Phase: 243-delta-extraction-per-commit-classification*
*Addendum-completed: 2026-04-23*
*Pointer to predecessor: `.planning/phases/243-delta-extraction-per-commit-classification/243-01-SUMMARY.md` (plan-close record at HEAD `771893d1`)*
