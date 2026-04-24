# v31.0 Phase 243 — Delta Surface Catalog

**Audit baseline:** `7ab515fe` (v30.0 milestone HEAD; tag `v30.0`).
**Audit head:** `771893d1` (v31.0 milestone start HEAD).
**Phase:** 243 — Delta Extraction & Per-Commit Classification (DELTA-01 / DELTA-02 / DELTA-03).
**Scope:** READ-only per CONTEXT.md D-22. Zero `contracts/` or `test/` writes.
**Status:** IN PROGRESS — Plan 243-01 populates Sections 0 / 1 / 4 / 5 / 7. Sections 2 / 3 / 6 are placeholder stubs reserved for Plans 243-02 (classification) and 243-03 (call-site catalog + Consumer Index + final READ-only lock).

## Section 0 — Overview & Row-ID Legend

### 0.1 Overview

This file is the authoritative v31.0 audit-surface catalog covering the 5 post-v30.0 commits (4 code-touching: `ced654df`, `16597cac`, `6b3f4f3c`, `771893d1`; 1 docs-only: `ffced9ef`) between baseline `7ab515fe` and head `771893d1`. It is the SOLE scope input for Phase 244 (per-commit adversarial audit) and Phase 245 (sDGNRS + gameover safety), per CONTEXT.md D-07 + ROADMAP Phase 243 Success Criterion 4.

**5-commit aggregate (from `git diff --stat 7ab515fe..771893d1 -- contracts/`):** 12 files changed, 140 insertions(+), 57 deletions(-).

**Reproducibility:** Every row in this file is derived from a documented `git diff` / `git show` / `forge inspect` / `grep` command. All commands are consolidated in Section 7 for reviewer replay.

### 0.2 Row-ID Legend (per CONTEXT.md D-09)

| Prefix | Section | Purpose | Owning Plan |
|---|---|---|---|
| `D-243-C###` | Section 1 (per-commit changelog) + Section 4 (state/event/interface/error inventory) | One row per changed symbol (function / state-var / event / error / interface method) across the 5 commits | 243-01 |
| `D-243-F###` | Section 2 (aggregate function classification) | One row per changed function with D-04 5-bucket classification + hunk citation + rationale | 243-02 |
| `D-243-S###` | Section 5 (storage slot layout diff) | One row per `DegenerusGameStorage.sol` slot that changed label / offset / type / size between baseline and head | 243-01 |
| `D-243-X###` | Section 3 (downstream call-site catalog) | One row per call site of each changed function / changed interface method discovered via `grep` across `contracts/` | 243-03 |
| `D-243-I###` | Section 6 (Consumer Index) | One row per v31.0 requirement (DELTA / EVT / RNG / QST / GOX / SDR / GOE / FIND / REG) mapping to the subset of 243 Row IDs scoped under it | 243-03 |

Row IDs are monotonic zero-padded three-digit integers within each prefix. `D-243-C###` numbering crosses Sections 1 and 4 contiguously (Section 1 first, then Section 4 continues the sequence).

### 0.3 Commit Inventory

| Chrono Order | SHA (full) | Subject | Files Touched in contracts/ | Insertions | Deletions | Role |
|---|---|---|---|---|---|---|
| 1 | `ced654df09e06c21d0ad0821dabeec52b9fb416f` | fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths | 1 (DegenerusGameJackpotModule.sol) | 33 | 6 | EVT-01..EVT-04 scope anchor |
| 2 | `16597cac9033fc8eedca6d5bb0aa9f375757be7e` | rngunlock fix | 1 (DegenerusGameAdvanceModule.sol) | 6 | 6 | RNG-01..RNG-03 scope anchor |
| 3 | `6b3f4f3c94f46c4c5d36e9f9c94d1d53b627163e` | feat(quests): credit recycled ETH toward MINT_ETH quests and earlybird DGNRS | 3 (DegenerusQuests.sol, IDegenerusQuests.sol, DegenerusGameMintModule.sol) | 25 | 24 | QST-01..QST-05 scope anchor |
| 4 | `771893d12e381cc8dfcc94ea888961853f99fae2` | feat(gameover): shift purchase/claim gates to liveness and protect sDGNRS redemptions | 9 (DegenerusGame.sol, StakedDegenerusStonk.sol, IDegenerusGame.sol, IStakedDegenerusStonk.sol, AdvanceModule, GameOverModule, MintModule, WhaleModule, DegenerusGameStorage.sol) | 76 | 21 | GOX-01..GOX-07 + SDR-01..SDR-08 + GOE-01..GOE-06 scope anchor |
| 5 | `ffced9ef71ff059f70ff1e8dcce37df10739f9b7` | chore: remove REQUIREMENTS.md for v30.0 milestone | 0 (docs-only per CONTEXT.md D-13) | 0 | 0 | NO_CHANGE per D-13 — enumerated for completeness |
| **Total** | — | — | **12 distinct files (union)** | **140** | **57** | — |

## Section 1 — Per-Commit Changelog

Per CONTEXT.md D-08 columns: `Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note`.

- **Row ID:** `D-243-C###` zero-padded, monotonic across Section 1 → Section 4.
- **Commit SHA:** short 8-char prefix.
- **File:Line-Range:** `contracts/<path>:<start>-<end>` at HEAD for MODIFIED/NEW rows; baseline range for DELETED rows.
- **Symbol Kind:** one of `func`, `modifier`, `state`, `event`, `error`, `interface-method`, `constant`, `none (docs-only)`.
- **Symbol Name:** function/state-var/event/interface-method identifier (NOT signature — signature goes in Section 2 classification column for 243-02, and Section 4 for state/event/interface entries).
- **Change Type (per-commit scope — coarser than D-04 classification):** one of `ADDED`, `REMOVED`, `MODIFIED`, `SIGNATURE-CHANGED`, `NATSPEC-ONLY`, `NO_CHANGE (docs-only)`. The fine-grained D-04 5-bucket verdict (NEW / MODIFIED_LOGIC / REFACTOR_ONLY / DELETED / RENAMED) is 243-02's job in Section 2.
- **One-Line Semantic Note:** ≤ 12 words — names the specific element that drives the row (e.g., "new emit JackpotWhalePassWin at Whale-pass fallback").

### 1.1 Commit ced654df — fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths

**Change count card:** functions: 5 / state-vars: 0 / events: 1 (NatSpec-only) / interfaces: 0 / errors: 0 / call-sites-changed: TBD-243-03.

Source command: `git show ced654df -- contracts/modules/DegenerusGameJackpotModule.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C001 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:670-719 | func | `_runEarlyBirdLootboxJackpot` | MODIFIED | emit JackpotTicketWin ticketCount now multiplied by TICKET_SCALE |
| D-243-C002 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:966-1019 | func | `_distributeTicketsToBucket` | MODIFIED | emit JackpotTicketWin ticketCount multiplied by TICKET_SCALE (units * TICKET_SCALE cast) |
| D-243-C003 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:1974-2059 | func | `runBafJackpot` | MODIFIED | two stub JackpotTicketWin emits removed (BAF small + odd-index paths) |
| D-243-C004 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:2074-2117 | func | `_awardJackpotTickets` | MODIFIED | new emit JackpotWhalePassWin in whale-pass fallback branch (amount > LOOTBOX_CLAIM_THRESHOLD) |
| D-243-C005 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:2129-2173 | func | `_jackpotTicketRoll` | MODIFIED | new emit JackpotTicketWin at ticket-roll site with real targetLevel and scaled quantity |
| D-243-C006 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:86-93 | event | `JackpotTicketWin` | NATSPEC-ONLY | NatSpec expanded to document TICKET_SCALE scaling + fractional-remainder resolution |

### 1.2 Commit 16597cac — rngunlock fix

**Change count card:** functions: 1 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: TBD-243-03.

Source command: `git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C007 | 16597cac | contracts/modules/DegenerusGameAdvanceModule.sol:156-480 | func | `advanceGame` | MODIFIED | _unlockRng(day) call removed from two-call-split ETH continuation plus two multi-line SLOAD/destructuring reformats |

### 1.3 Commit 6b3f4f3c — feat(quests): credit recycled ETH toward MINT_ETH quests and earlybird DGNRS

**Change count card:** functions: 3 / state-vars: 0 / events: 0 / interfaces: 1 / errors: 0 / call-sites-changed: TBD-243-03.

Source commands:
- `git show 6b3f4f3c -- contracts/DegenerusQuests.sol`
- `git show 6b3f4f3c -- contracts/interfaces/IDegenerusQuests.sol`
- `git show 6b3f4f3c -- contracts/modules/DegenerusGameMintModule.sol`

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C008 | 6b3f4f3c | contracts/DegenerusQuests.sol:763-898 | func | `handlePurchase` | SIGNATURE-CHANGED | parameter rename ethFreshWei→ethMintSpendWei; MINT_ETH quest credits gross spend (fresh+recycled) |
| D-243-C009 | 6b3f4f3c | contracts/interfaces/IDegenerusQuests.sol:139-152 | interface-method | `handlePurchase` | SIGNATURE-CHANGED | interface parameter rename ethFreshWei→ethMintSpendWei matching implementation |
| D-243-C010 | 6b3f4f3c | contracts/modules/DegenerusGameMintModule.sol:913-1198 | func | `_purchaseFor` | MODIFIED | ticketFreshEth local removed; ethMintSpendWei computed from ticketCost+lootBoxAmount; earlybird uses same gross spend |
| D-243-C011 | 6b3f4f3c | contracts/modules/DegenerusGameMintModule.sol:1206-1373 | func | `_callTicketPurchase` | SIGNATURE-CHANGED | freshEth return tuple element dropped; freshEth demoted to internal local for _recordAffiliateStake |

### 1.4 Commit 771893d1 — feat(gameover): shift purchase/claim gates to liveness and protect sDGNRS redemptions

**Change count card:** functions: 12 / state-vars: 0 / events: 0 / interfaces: 3 (3 added, 0 signature-changed; 1 added in inline interface inside StakedDegenerusStonk) / errors: 1 (added) / constants: 1 (added) / call-sites-changed: TBD-243-03.

Source commands (one per touched file):
- `git show 771893d1 -- contracts/DegenerusGame.sol`
- `git show 771893d1 -- contracts/StakedDegenerusStonk.sol`
- `git show 771893d1 -- contracts/interfaces/IDegenerusGame.sol`
- `git show 771893d1 -- contracts/interfaces/IStakedDegenerusStonk.sol`
- `git show 771893d1 -- contracts/modules/DegenerusGameAdvanceModule.sol`
- `git show 771893d1 -- contracts/modules/DegenerusGameGameOverModule.sol`
- `git show 771893d1 -- contracts/modules/DegenerusGameMintModule.sol`
- `git show 771893d1 -- contracts/modules/DegenerusGameWhaleModule.sol`
- `git show 771893d1 -- contracts/storage/DegenerusGameStorage.sol`

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C012 | 771893d1 | contracts/DegenerusGame.sol:2133-2135 | func | `livenessTriggered` | ADDED | new external view wrapping internal `_livenessTriggered()` for cross-contract reads |
| D-243-C013 | 771893d1 | contracts/StakedDegenerusStonk.sol:486-495 | func | `burn` | MODIFIED | new State-1 revert `BurnsBlockedDuringLiveness` after game.livenessTriggered() check |
| D-243-C014 | 771893d1 | contracts/StakedDegenerusStonk.sol:506-516 | func | `burnWrapped` | MODIFIED | new State-1 revert when livenessTriggered() true and !gameOver() |
| D-243-C015 | 771893d1 | contracts/modules/DegenerusGameAdvanceModule.sol:519-630 | func | `_handleGameOverPath` | MODIFIED | check-ordering swap — gameOver branch evaluated before liveness gate |
| D-243-C016 | 771893d1 | contracts/modules/DegenerusGameAdvanceModule.sol:1216-1294 | func | `_gameOverEntropy` | MODIFIED | rngRequestTime cleared when prevrandao fallback word commits |
| D-243-C017 | 771893d1 | contracts/modules/DegenerusGameGameOverModule.sol:79-189 | func | `handleGameOverDrain` | MODIFIED | reserved = claimablePool + pendingRedemptionEthValue subtracted before 33/33/34 split |
| D-243-C018 | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:885-911 | func | `_purchaseCoinFor` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (1 of 8 paths per GOX-01) |
| D-243-C019 | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:913-1198 | func | `_purchaseFor` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (2 of 8 paths) |
| D-243-C020 | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:1206-1373 | func | `_callTicketPurchase` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (3 of 8 paths) |
| D-243-C021 | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:1388-1423 | func | `_purchaseBurnieLootboxFor` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (4 of 8 paths) |
| D-243-C022 | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:194-365 | func | `_purchaseWhaleBundle` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (5 of 8 paths) |
| D-243-C023 | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:384-518 | func | `_purchaseLazyPass` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (6 of 8 paths) |
| D-243-C024 | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:542-674 | func | `_purchaseDeityPass` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (7 of 8 paths) |
| D-243-C025 | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:957-974 | func | `claimWhalePass` | MODIFIED | guard flipped from `gameOver` to `_livenessTriggered()` (8 of 8 paths) |
| D-243-C026 | 771893d1 | contracts/storage/DegenerusGameStorage.sol:1235-1243 | func | `_livenessTriggered` | MODIFIED | day-math evaluated first; 14-day VRF-dead grace fallback added via rngRequestTime |

### 1.5 Commit ffced9ef — chore: remove REQUIREMENTS.md for v30.0 milestone (docs-only per D-13)

**Change count card:** functions: 0 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: 0.

Source command: `git show ffced9ef --stat` (touches `.planning/REQUIREMENTS.md` only; zero files in `contracts/`).

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C027 | ffced9ef | (none — docs-only) | none (docs-only) | (none) | NO_CHANGE (docs-only) | v30.0 REQUIREMENTS.md archival — zero contract symbols per D-13 |

### 1.6 Finding Candidates (fresh-eyes)

Per CONTEXT.md D-20: any symbol discovered during the fresh enumeration pass that looks potentially worth a Phase 246 finding gets flagged here. Zero finding IDs are emitted by this phase — Phase 246 owns ID assignment.

Format: bullet list — `- contracts/<path>:<line> — <symbol> — <rationale> — suggested severity: <INFO|LOW|MEDIUM|HIGH>`.

- contracts/StakedDegenerusStonk.sol:494 — `burn` — State-1 ordering: `game.livenessTriggered()` check precedes `game.rngLocked()` check, so a player in the 14-day VRF-dead grace window receives `BurnsBlockedDuringLiveness` rather than `BurnsBlockedDuringRng`; error taxonomy semantics should be validated in Phase 244 GOX-02 — suggested severity: INFO
- contracts/StakedDegenerusStonk.sol:507 — `burnWrapped` — State-1 check uses `livenessTriggered() && !gameOver()` but `burn` uses `livenessTriggered()` alone (gameOver short-circuit above). The divergence is load-bearing (burn returns deterministic path via gameOver short-circuit) but worth explicit diff-aware reasoning in Phase 245 SDR-06 — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:1275 — `_gameOverEntropy` — `rngRequestTime = 0` clears the stall lock AFTER `_finalizeLootboxRng(fallbackWord)`, so a mid-block re-entry would see a zeroed timer while the fallback path is still mid-execution; Phase 244 RNG-02 should confirm there is no reentry surface here — suggested severity: INFO
- contracts/modules/DegenerusGameGameOverModule.sol:83-88 — `handleGameOverDrain` — reserved subtraction uses `uint256(claimablePool) + pendingRedemptionEthValue()` where `claimablePool` is `uint128`; upcast to `uint256` is safe but the second addend is an external call on each drain iteration (subject to reentrancy check). Phase 245 SDR-03 should inspect the sDGNRS function for staticcall compliance — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:527-548 — `_handleGameOverPath` — commit message justifies gameOver-before-liveness reorder for "post-gameover final sweep stays reachable when VRF-dead latches gameOver with day-math still below 120/365". Phase 245 GOE-04 should confirm the `handleGameOverPath` → `handleGameOverDrain` call graph still reaches final-sweep in every stall-tail configuration — suggested severity: INFO

### 1.7 Light Reconciliation Against audit/v30-CONSUMER-INVENTORY.md

Per CONTEXT.md D-17: cross-check any RNG-consumer row in `audit/v30-CONSUMER-INVENTORY.md` whose underlying function is touched by the 5 deltas. Narrower than Phase 237's full prior-artifact cross-check (v30.0 is known-complete at `7ab515fe`, so only the delta's RNG surface needs re-examination).

30 INV-237 rows sit inside delta-touched functions. Most are "function-level overlap only" — the v30 consumer row references a line that the delta did NOT touch. The table below lists every overlap; Phase 244 RNG-02 is the verdict-locking phase.

| v30 Inventory Row ID | Consumer Function | Touched by Commit | Matched Section 1 Row | Reconciliation Verdict |
|---|---|---|---|---|
| INV-237-021 | advanceGame (mid-day lootbox gate check) | 16597cac | D-243-C007 | function-level-overlap — line 204 NOT in 16597cac hunk (257-279 / 449); no RNG consumer drift |
| INV-237-022 | advanceGame (daily-drain gate pre-check) | 16597cac | D-243-C007 | REFORMAT-TOUCHED — line 261 sits in 16597cac multi-line preIdx reformat (257-260); execution trace byte-equivalent per commit msg |
| INV-237-023 | advanceGame (daily-drain gate pre-check) | 16597cac | D-243-C007 | REFORMAT-TOUCHED — line 262 in 16597cac reformat (same hunk as INV-237-022) |
| INV-237-024 | advanceGame (ticket-buffer swap for daily RNG) | 16597cac | D-243-C007 | function-level-overlap — line 292 NOT in 16597cac hunk |
| INV-237-025 | advanceGame (FF drain processing) | 16597cac | D-243-C007 | function-level-overlap — line 317 NOT in 16597cac hunk |
| INV-237-026 | advanceGame (near-future ticket prep) | 16597cac | D-243-C007 | function-level-overlap — line 339 NOT in 16597cac hunk |
| INV-237-027 | advanceGame (L1 emitDailyWinningTraits) | 16597cac | D-243-C007 | function-level-overlap — line 364 NOT in 16597cac hunk |
| INV-237-028 | advanceGame (L1 main coin jackpot) | 16597cac | D-243-C007 | function-level-overlap — line 365 NOT in 16597cac hunk |
| INV-237-029 | advanceGame (L1 bonus coin jackpot) | 16597cac | D-243-C007 | function-level-overlap — lines 367-374 NOT in 16597cac hunk |
| INV-237-030 | advanceGame (purchase-phase daily jackpot) | 16597cac | D-243-C007 | function-level-overlap — line 376 NOT in 16597cac hunk |
| INV-237-031 | advanceGame (purchase-phase near-future coin jackpot) | 16597cac | D-243-C007 | function-level-overlap — lines 377-382 NOT in 16597cac hunk |
| INV-237-032 | advanceGame (purchase-phase consolidation yieldSurplus) | 16597cac | D-243-C007 | function-level-overlap — line 416 NOT in 16597cac hunk |
| INV-237-033 | advanceGame (purchase-phase pool consolidation) | 16597cac | D-243-C007 | function-level-overlap — lines 417-423 NOT in 16597cac hunk |
| INV-237-034 | advanceGame (rollLevelQuest call) | 16597cac | D-243-C007 | function-level-overlap — line 438 NOT in 16597cac hunk |
| INV-237-035 | advanceGame (jackpot-phase resume) | 16597cac | D-243-C007 | HUNK-ADJACENT — line 450 is exactly where `_unlockRng(day)` was removed; payDailyJackpot(true, lvl, rngWord) call itself unchanged, but the post-call unlock was dropped. Phase 244 RNG-01 must re-verify rngLocked-clear now happens elsewhere on the same tick |
| INV-237-036 | advanceGame (jackpot-phase coin+tickets) | 16597cac | D-243-C007 | function-level-overlap — line 458 NOT in 16597cac hunk |
| INV-237-037 | advanceGame (jackpot-phase fresh daily) | 16597cac | D-243-C007 | function-level-overlap — line 470 NOT in 16597cac hunk |
| INV-237-052 | _gameOverEntropy (short-circuit) | 771893d1 | D-243-C016 | function-level-overlap — line 1219 NOT in 771893d1 hunk (hunk at 1275-1279) |
| INV-237-053 | _gameOverEntropy (fresh VRF word) | 771893d1 | D-243-C016 | function-level-overlap — lines 1221-1223 NOT in 771893d1 hunk |
| INV-237-054 | _gameOverEntropy (consumer cluster) | 771893d1 | D-243-C016 | function-level-overlap — lines 1222-1246 NOT in 771893d1 hunk |
| INV-237-055 | _gameOverEntropy (historical fallback call) | 771893d1 | D-243-C016 | function-level-overlap — line 1252 NOT in 771893d1 hunk |
| INV-237-056 | _gameOverEntropy (fallback apply) | 771893d1 | D-243-C016 | function-level-overlap — line 1253 NOT in 771893d1 hunk |
| INV-237-057 | _gameOverEntropy (fallback coinflip) | 771893d1 | D-243-C016 | function-level-overlap — line 1257 NOT in 771893d1 hunk |
| INV-237-058 | _gameOverEntropy (fallback redemption roll) | 771893d1 | D-243-C016 | function-level-overlap — line 1268 NOT in 771893d1 hunk |
| INV-237-059 | _gameOverEntropy (fallback lootbox finalize) | 771893d1 | D-243-C016 | HUNK-ADJACENT — line 1274 sits just before the new `rngRequestTime = 0` SSTORE at line 1275-1279; the fallback finalize happens first, then the timer clear. Phase 244 RNG-02 must confirm KI prevrandao-fallback invariant unchanged |
| INV-237-077 | handleGameOverDrain (rngWord SLOAD) | 771893d1 | D-243-C017 | function-level-overlap — line 97 shifts inside the function after the +5-line reserved-subtraction hunk at 86-90, but the rngWord SLOAD itself unchanged |
| INV-237-078 | handleGameOverDrain (terminal decimator) | 771893d1 | D-243-C017 | HUNK-ADJACENT — line 162 adjacent to the 151-156 hunk where `reserved` recomputation now adds pendingRedemptionEthValue post-refund; terminal decimator call itself unchanged but `available` budget shrinks |
| INV-237-079 | handleGameOverDrain (terminal jackpot) | 771893d1 | D-243-C017 | HUNK-ADJACENT — line 175 downstream of the 151-156 `available` recomputation; terminal jackpot spend reduced by pendingRedemptionEthValue reservation |
| INV-237-101 | _distributeTicketsToBuckets | ced654df | (no Section 1 row) | DECOUPLED — INV-237-101 cites `_distributeTicketsToBuckets` at line 937; ced654df modifies the adjacent function `_distributeTicketsToBucket` (singular) at lines 1001-1008. Naming collision; no RNG consumer drift |
| INV-237-124 | _jackpotTicketRoll | ced654df | D-243-C005 | FUNCTION-MODIFIED — ced654df added an `emit JackpotTicketWin` at line 2163-2170 but did NOT alter any RNG consumer arithmetic (entropy step + modulo logic unchanged). Phase 244 EVT-01/EVT-03 verifies the emit scaling but RNG invariant preserved |

**Summary:** 30 overlaps total — 23 function-level-overlap (delta line does not intersect consumer line), 5 HUNK-ADJACENT (delta hunk sits next to or straddling consumer line; Phase 244 RNG-01/RNG-02/EVT-01 must re-verify), 1 REFORMAT-TOUCHED pair (INV-237-022/023 in 16597cac reformat-only hunk — REFACTOR_ONLY candidate for 243-02; F-29 rngLocked invariant unaffected by reformat), 1 DECOUPLED (INV-237-101 cites a differently-named function). Zero overlaps indicate RNG surface widening of an accepted KI exception. Phase 244 RNG-01 (16597cac RNG lock) and RNG-02 (v30 AIRTIGHT rngLocked re-verification) inherit the HUNK-ADJACENT flags as primary scope.

## Section 2 — Aggregate Function Classification (RESERVED FOR 243-02)

This section is reserved for Plan 243-02 to append the D-04 5-bucket classification table for every `func` or `modifier` row in Section 1. Row IDs `D-243-F###`. DO NOT edit this section in Plan 243-01 — 243-02 appends to it.

## Section 3 — Downstream Call-Site Catalog (RESERVED FOR 243-03)

This section is reserved for Plan 243-03 to append the grep-reproducible call-site inventory for every changed function and interface method. Row IDs `D-243-X###`. DO NOT edit this section in Plan 243-01 — 243-03 appends to it.

## Section 4 — State Variable / Event / Interface Inventory

Scope per CONTEXT.md D-07 item 4: all added/removed/signature-modified state variables (including every `DegenerusGameStorage.sol` addition), every new `event` declaration, every changed interface method signature in `IDegenerusGame.sol` / `IDegenerusQuests.sol` / `IStakedDegenerusStonk.sol`, every added/removed custom `error`.

Row IDs continue `D-243-C###` sequence from Section 1 (do not restart numbering).

### 4.1 State Variables

commit 771893d1 `DegenerusGameStorage.sol` (+27 lines) adds zero new storage slots. The only data-object-like addition is the compile-time constant `_VRF_GRACE_PERIOD`; the remainder of the +27 lines is NatSpec expansion of `_livenessTriggered` and the function body rewrite (Section 1 row D-243-C026). Constants do not consume storage slots in Solidity (value inlined into bytecode).

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Type Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C028 | 771893d1 | contracts/storage/DegenerusGameStorage.sol:200-203 | `_VRF_GRACE_PERIOD` | `uint48 internal constant _VRF_GRACE_PERIOD = 14 days` | ADDED | compile-time constant — no storage slot consumed; threshold used by _livenessTriggered VRF-dead branch |

No mutable state variable additions, removals, or signature changes across the 5 commits. Section 5 storage-slot diff confirms zero slot drift.

### 4.2 Events

No new event declarations introduced across the 5 commits. `JackpotWhalePassWin` is NOT new — it existed at baseline `7ab515fe` (baseline JackpotModule line 110; HEAD line 116-120); commit `ced654df` added new EMIT sites for the existing event (rows D-243-C004 + D-243-C005 in Section 1).

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Event Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C029 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:86-93 | `JackpotTicketWin` | `JackpotTicketWin(address indexed winner, uint24 indexed ticketLevel, uint16 indexed traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex)` | NATSPEC-ONLY | signature unchanged; NatSpec expanded to document TICKET_SCALE scaling + fractional-remainder resolution |

### 4.3 Interface Methods

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Method Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C030 | 6b3f4f3c | contracts/interfaces/IDegenerusQuests.sol:139-152 | `handlePurchase` | `handlePurchase(address player, uint256 ethMintSpendWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice) external returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | SIGNATURE-CHANGED | parameter rename ethFreshWei→ethMintSpendWei; semantic shift from fresh-only to gross-spend quest crediting |
| D-243-C031 | 771893d1 | contracts/interfaces/IDegenerusGame.sol:27-30 | `livenessTriggered` | `livenessTriggered() external view returns (bool)` | ADDED | new interface method exposing internal `_livenessTriggered()` for cross-contract reads (sDGNRS State-1 gate) |
| D-243-C032 | 771893d1 | contracts/interfaces/IStakedDegenerusStonk.sol:88-90 | `pendingRedemptionEthValue` | `pendingRedemptionEthValue() external view returns (uint256)` | ADDED | new interface method reporting ETH reserved for in-flight gambling-burn redemptions; consumed by handleGameOverDrain |
| D-243-C033 | 771893d1 | contracts/StakedDegenerusStonk.sol:29-30 | `livenessTriggered` (inline `IDegenerusGamePlayer`) | `livenessTriggered() external view returns (bool)` | ADDED | inline IDegenerusGamePlayer interface (defined in-file at top of StakedDegenerusStonk.sol) extended with livenessTriggered method call needed by burn/burnWrapped |

### 4.4 Errors / Custom Reverts

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Error Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C034 | 771893d1 | contracts/StakedDegenerusStonk.sol:102-105 | `BurnsBlockedDuringLiveness` | `BurnsBlockedDuringLiveness()` | ADDED | new State-1 revert raised by burn/burnWrapped when liveness fired but gameOver not yet latched |

## Section 5 — Storage Slot Layout Diff (DegenerusGameStorage.sol) — RESERVED FOR TASK 2

This section is written in Task 2 of this plan (Storage Layout Diff). Task 1 leaves a placeholder note here.

## Section 6 — Consumer Index (RESERVED FOR 243-03)

This section is reserved for Plan 243-03 to append the v31.0 requirement → 243 Row-ID mapping. Row IDs `D-243-I###`. DO NOT edit this section in Plan 243-01 — 243-03 appends to it.

## Section 7 — Reproduction Recipe Appendix — RESERVED FOR TASK 3

This section is written in Task 3 of this plan (Reproduction Recipes). Task 1 leaves a placeholder note here.
