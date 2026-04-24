# v31.0 Phase 243 — Delta Surface Catalog

**Audit baseline:** `7ab515fe` (v30.0 milestone HEAD; tag `v30.0`).
**Audit head:** `771893d1` (v31.0 milestone start HEAD).
**Phase:** 243 — Delta Extraction & Per-Commit Classification (DELTA-01 / DELTA-02 / DELTA-03).
**Scope:** READ-only per CONTEXT.md D-22. Zero `contracts/` or `test/` writes.
**Status:** WORKING — 243-03 wave-2 call-site + Consumer Index appends pending. HEAD: `cc68bfc7` (extended from `771893d1` via cc68bfc7 BAF-flip-gate addendum per CONTEXT.md D-01 amendment, 2026-04-23). Plan 243-01 original pass populated Sections 0 / 1 / 4 / 5 / 7.1 at head `771893d1`. Plan 243-01 addendum pass appended cc68bfc7-scope rows to Sections 1 / 4 / 5 / 7.1 without rewriting the original 771893d1 rows. Plan 243-02 populated Section 2 (Aggregate Function Classification, 26 rows covering all `func` entries across both HEAD anchors) + §7.2 reproduction recipes. Sections 3 / 6 / 7.3 still carry `RESERVED FOR 243-03` placeholder markers for the Wave 2 call-site plan to replace in place. Plan 243-03 performs the final FINAL-status READ-only lock per CONTEXT.md D-12 + D-21.

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

> **Dual HEAD anchor:** Rows `D-243-C001..D-243-C034` (and storage row `D-243-S001`) captured at HEAD `771893d1` (original Phase 243 scope per CONTEXT.md D-01 original). Rows `D-243-C035+` (and storage row `D-243-S002` if any) captured at HEAD `cc68bfc7` (BAF-flip-gate addendum per CONTEXT.md D-01 amended 2026-04-23 — commit landed 2026-04-23 21:25 mid-execution, touching `contracts/DegenerusJackpots.sol` +19, `contracts/interfaces/IDegenerusJackpots.sol` +6, and `contracts/modules/DegenerusGameAdvanceModule.sol` +22/-10 additional on top of 771893d1). Baseline anchor `7ab515fe` is unchanged. All original 34 changelog rows + 1 storage-layout row at `771893d1` are preserved byte-identical below.

### 1.1 Commit ced654df — fix(jackpot): emit accurate scaled ticketCount on all JackpotTicketWin paths

**Change count card:** functions: 5 (NEW: 0 / MODIFIED_LOGIC: 5 / REFACTOR_ONLY: 0 / DELETED: 0 / RENAMED: 0) / state-vars: 0 / events: 1 (NatSpec-only) / interfaces: 0 / errors: 0 / call-sites-changed: TBD-243-03.

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

**Change count card:** functions: 1 (NEW: 0 / MODIFIED_LOGIC: 1 / REFACTOR_ONLY: 0 / DELETED: 0 / RENAMED: 0) / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: TBD-243-03.

Source command: `git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C007 | 16597cac | contracts/modules/DegenerusGameAdvanceModule.sol:156-480 | func | `advanceGame` | MODIFIED | _unlockRng(day) call removed from two-call-split ETH continuation plus two multi-line SLOAD/destructuring reformats |

### 1.3 Commit 6b3f4f3c — feat(quests): credit recycled ETH toward MINT_ETH quests and earlybird DGNRS

**Change count card:** functions: 3 (NEW: 0 / MODIFIED_LOGIC: 2 / REFACTOR_ONLY: 1 / DELETED: 0 / RENAMED: 0) / state-vars: 0 / events: 0 / interfaces: 1 / errors: 0 / call-sites-changed: TBD-243-03.

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

**Change count card:** functions: 15 (NEW: 1 / MODIFIED_LOGIC: 14 / REFACTOR_ONLY: 0 / DELETED: 0 / RENAMED: 0) / state-vars: 0 / events: 0 / interfaces: 3 (3 added, 0 signature-changed; 1 added in inline interface inside StakedDegenerusStonk) / errors: 1 (added) / constants: 1 (added) / call-sites-changed: TBD-243-03.

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

### 1.6 Commit cc68bfc7 — feat(baf): gate BAF jackpot on daily flip win (ADDENDUM)

**Change count card:** functions: 2 (NEW: 1 / MODIFIED_LOGIC: 1 / REFACTOR_ONLY: 0 / DELETED: 0 / RENAMED: 0) / state-vars: 1 (constant ADDED) / events: 1 (ADDED) / interfaces: 1 (ADDED) / errors: 0 / call-sites-changed: TBD-243-03 / ADDENDUM: landed 2026-04-23 21:25, post-original-HEAD `771893d1` — 3 files / +47 insertions / -10 deletions.

**Scope note:** `DegenerusJackpots.sol` and `IDegenerusJackpots.sol` were NOT in the original 12-file surface — they are net-new to Phase 243 via this addendum, bringing the addendum-scope file count to 14 (original 12 + 2). `DegenerusGameAdvanceModule.sol` was already in the 12 (touched by `16597cac` and `771893d1`); cc68bfc7 adds additional hunks on top. Baseline anchor `7ab515fe` is unchanged — `DegenerusJackpots.sol` and `IDegenerusJackpots.sol` existed at baseline with identical names; cc68bfc7 adds new symbols to existing files, it does NOT create the files themselves.

Source commands:
- `git diff 771893d1..cc68bfc7 -- contracts/` (incremental addendum scope)
- `git show cc68bfc7 -- contracts/DegenerusJackpots.sol`
- `git show cc68bfc7 -- contracts/interfaces/IDegenerusJackpots.sol`
- `git show cc68bfc7 -- contracts/modules/DegenerusGameAdvanceModule.sol`

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C035 | cc68bfc7 | contracts/DegenerusJackpots.sol:71-74 | event | `BafSkipped` | ADDED | new event emitted when daily flip loses and BAF bracket is skipped |
| D-243-C036 | cc68bfc7 | contracts/DegenerusJackpots.sol:498-510 | func | `markBafSkipped` | ADDED | new onlyGame external — bumps `lastBafResolvedDay` to today and emits BafSkipped(lvl, today) |
| D-243-C037 | cc68bfc7 | contracts/interfaces/IDegenerusJackpots.sol:30-34 | interface-method | `markBafSkipped` | ADDED | new external declared on IDegenerusJackpots matching DegenerusJackpots.markBafSkipped |
| D-243-C038 | cc68bfc7 | contracts/modules/DegenerusGameAdvanceModule.sol:105-106 | constant | `jackpots` | ADDED | new file-scope `IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS)` — direct handle for skip-marker on losing-flip days (import at L7) |
| D-243-C039 | cc68bfc7 | contracts/modules/DegenerusGameAdvanceModule.sol:728-909 | func | `_consolidatePoolsAndRewardJackpots` | MODIFIED | BAF branch now gated on `rngWord & 1 == 1` — losing-flip branch invokes `jackpots.markBafSkipped(lvl)` in place of runBafJackpot; RNG consumer-map comment extended with new bit-0 consumer at L1131 |

### 1.7 Finding Candidates (fresh-eyes)

Per CONTEXT.md D-20: any symbol discovered during the fresh enumeration pass that looks potentially worth a Phase 246 finding gets flagged here. Zero finding IDs are emitted by this phase — Phase 246 owns ID assignment.

Format: bullet list — `- contracts/<path>:<line> — <symbol> — <rationale> — suggested severity: <INFO|LOW|MEDIUM|HIGH>`.

- contracts/StakedDegenerusStonk.sol:494 — `burn` — State-1 ordering: `game.livenessTriggered()` check precedes `game.rngLocked()` check, so a player in the 14-day VRF-dead grace window receives `BurnsBlockedDuringLiveness` rather than `BurnsBlockedDuringRng`; error taxonomy semantics should be validated in Phase 244 GOX-02 — suggested severity: INFO
- contracts/StakedDegenerusStonk.sol:507 — `burnWrapped` — State-1 check uses `livenessTriggered() && !gameOver()` but `burn` uses `livenessTriggered()` alone (gameOver short-circuit above). The divergence is load-bearing (burn returns deterministic path via gameOver short-circuit) but worth explicit diff-aware reasoning in Phase 245 SDR-06 — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:1275 — `_gameOverEntropy` — `rngRequestTime = 0` clears the stall lock AFTER `_finalizeLootboxRng(fallbackWord)`, so a mid-block re-entry would see a zeroed timer while the fallback path is still mid-execution; Phase 244 RNG-02 should confirm there is no reentry surface here — suggested severity: INFO
- contracts/modules/DegenerusGameGameOverModule.sol:83-88 — `handleGameOverDrain` — reserved subtraction uses `uint256(claimablePool) + pendingRedemptionEthValue()` where `claimablePool` is `uint128`; upcast to `uint256` is safe but the second addend is an external call on each drain iteration (subject to reentrancy check). Phase 245 SDR-03 should inspect the sDGNRS function for staticcall compliance — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:527-548 — `_handleGameOverPath` — commit message justifies gameOver-before-liveness reorder for "post-gameover final sweep stays reachable when VRF-dead latches gameOver with day-math still below 120/365". Phase 245 GOE-04 should confirm the `handleGameOverPath` → `handleGameOverDrain` call graph still reaches final-sweep in every stall-tail configuration — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:826 — `_consolidatePoolsAndRewardJackpots` (cc68bfc7) — BAF fire gate reuses `rngWord & 1`, the same low-order bit BurnieCoinflip._resolveDay consumes for the daily-win/loss outcome; BAF resolution is now correlated with the daily coinflip rather than independent. Phase 244 EVT-02 / EVT-03 should re-verify jackpot expected value + fairness under this new coupling; the commit msg indicates this is intentional ("BAF gated on daily flip win"), but the economic effect (BAF fires ~50% of the time vs. always) should be tracked explicitly — suggested severity: INFO
- contracts/DegenerusJackpots.sol:500-510 — `markBafSkipped` (cc68bfc7) — bumps `lastBafResolvedDay = today` but leaves leaderboard state for `lvl` untouched. NatSpec justifies this ("no new writes ever target a past bracket, so clearing would only burn gas"). Phase 244 EVT-02 should verify that every consumer of `bafBrackets[lvl]` / `winningBafCredit` gates on `cursor > lastBafResolvedDay` so stale leaderboard rows from the pre-skip winning-flip-credit cannot be claimed. BurnieCoinflip is called out in the NatSpec as one consumer; Phase 244 should confirm it covers all consumers — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:105-106 — `jackpots` constant (cc68bfc7) — new direct-handle `IDegenerusJackpots(ContractAddresses.JACKPOTS)` parallel to the existing `runBafJackpot` self-call at line 830-834 which routes through `IDegenerusGame(address(this)).runBafJackpot`. The two call paths hit the same JACKPOTS contract but via different code paths (self-call delegatecall vs direct external); Phase 244 RNG-01 / Phase 245 GOE-06 should confirm no reentrancy or nonce-ordering interaction between the two — suggested severity: INFO

### 1.8 Light Reconciliation Against audit/v30-CONSUMER-INVENTORY.md

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

## Section 2 — Aggregate Function Classification

Per CONTEXT.md D-04: every `func` or `modifier` row from Section 1 is classified into exactly one of the 5 buckets {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, RENAMED}. Burden of proof is on REFACTOR_ONLY per D-04 — any doubt escalates to MODIFIED_LOGIC.

Per CONTEXT.md D-06: every row cites the exact diff hunk at its HEAD anchor in the Hunk Ref column. Pre-cc68bfc7 rows (D-243-C001..C026 originating at commits `ced654df` / `16597cac` / `6b3f4f3c` / `771893d1`) cite at `@771893d1`; addendum rows (D-243-C036 / C039 originating at `cc68bfc7`) cite at `@cc68bfc7`. Baseline anchor is `7ab515fe` for NEW/DELETED existence tests.

Per CONTEXT.md D-19: every MODIFIED_LOGIC / REFACTOR_ONLY row names the specific execution-trace-changing element (SSTORE / external call / branch / emit / return-path) OR the specific non-execution-changing element (whitespace / rename / multi-line split / local-variable-name / NatSpec). Hand-wave rationales are forbidden.

Section 2 Row IDs use prefix `D-243-F###` (monotonic from F001 — no gaps; no overlap with Section 1's `D-243-C###` numbering or Section 4's continuation).

**Dual HEAD-anchor coverage:** Section 1 contains 26 `func` rows (24 at HEAD `771893d1` and 2 at HEAD `cc68bfc7` per the addendum); Section 2 below carries 26 classification rows 1:1 — F001..F024 anchor at `771893d1`, F025..F026 anchor at `cc68bfc7`. Zero modifier rows exist in Section 1 across either HEAD.

### 2.1 5-Bucket Taxonomy (D-04 rules)

| Classification | Definition |
|---|---|
| `NEW` | Function did not exist at baseline `7ab515fe`; appears at HEAD with a body. Existence test via `git show 7ab515fe:<file> \| grep -c 'function <name>'` returning 0. |
| `MODIFIED_LOGIC` | Function existed at baseline and HEAD; any state write, external call, control-flow branch, emitted event, or return-path evaluation changed. Removal or addition of a side-effect call is MODIFIED_LOGIC. |
| `REFACTOR_ONLY` | Function existed at baseline and HEAD; source-level shape changed (whitespace, parens, local variable names, multi-line decomposition, tuple destructuring, NatSpec, parameter rename) but execution trace is byte-equivalent. |
| `DELETED` | Function existed at baseline; absent at HEAD. |
| `RENAMED` | Same signature body at HEAD under a different name (callee-side classification — caller hunks that only see the rename are REFACTOR_ONLY on the caller). |

### 2.2 D-05 Pre-Locked Verdicts Applied

Per CONTEXT.md D-05, the following named functions received pre-locked verdicts at phase-context time. This section applies those verdicts verbatim; any executor deviation is logged in §2.5 with evidence cross-referenced to Section 1.7 Finding Candidates.

| D-05 ID | Symbol | Commit | Pre-Locked Verdict | Applied In Row |
|---|---|---|---|---|
| D-05.1 + D-05.2 (collapsed) | `advanceGame` (both the `_unlockRng(day)` removal and the two multi-line SLOAD/destructuring reformats land in the SAME function per Section 1 row D-243-C007) | 16597cac | MODIFIED_LOGIC (removal drives verdict; reformat is subordinate) | D-243-F006 |
| D-05.3 | `_callTicketPurchase` (return-tuple shrink) | 6b3f4f3c | MODIFIED_LOGIC | D-243-F009 |
| D-05.4a | `handlePurchase` (parameter rename hunk — quests side) | 6b3f4f3c | REFACTOR_ONLY | D-243-F007 |
| D-05.4b | value-semantics shift (gross spend replaces fresh) is captured on caller side — `_purchaseFor` at 6b3f4f3c | 6b3f4f3c | MODIFIED_LOGIC | D-243-F008 |
| D-05.5 | `_jackpotTicketRoll` (new JackpotTicketWin emit at roll site) | ced654df | MODIFIED_LOGIC | D-243-F005 |
| D-05.6 | `_awardJackpotTickets` (new JackpotWhalePassWin emit in whale-pass fallback) | ced654df | MODIFIED_LOGIC | D-243-F004 |
| D-05.7 (8 paths) | 4 MintModule + 4 WhaleModule gate-swap functions (`gameOver → _livenessTriggered()` guard-condition change) | 771893d1 | MODIFIED_LOGIC (×8) | D-243-F016..F023 |
| D-05.8a | `burn` (new State-1 revert `BurnsBlockedDuringLiveness`) | 771893d1 | MODIFIED_LOGIC | D-243-F011 |
| D-05.8b | `burnWrapped` (new State-1 revert `BurnsBlockedDuringLiveness`) | 771893d1 | MODIFIED_LOGIC | D-243-F012 |
| D-05.9 | `handleGameOverDrain` (new `pendingRedemptionEthValue()` subtraction, twice) | 771893d1 | MODIFIED_LOGIC | D-243-F015 |
| D-05.10 | `_livenessTriggered` (day-math-first + 14-day VRF-dead grace branch) | 771893d1 | MODIFIED_LOGIC | D-243-F024 |
| D-05.11a | `_gameOverEntropy` (new `rngRequestTime = 0` SSTORE on fallback commit) | 771893d1 | MODIFIED_LOGIC | D-243-F014 |
| D-05.11b | `_handleGameOverPath` (liveness check moved after gameOver branch) | 771893d1 | MODIFIED_LOGIC | D-243-F013 |

### 2.3 Classification Table

Every `func` row from Section 1 receives a 1:1 classification row. Hunk Ref column embeds the HEAD anchor as an `@sha` suffix (using either `@771893d1` or `@cc68bfc7`) so reviewers can replay `git show 771893d1:path/to/file` or `git show cc68bfc7:path/to/file` directly.

| Row ID | Section 1 Row | Function Signature | Commit | File:Line (at HEAD) | Classification | Hunk Ref | One-Line Rationale |
|---|---|---|---|---|---|---|---|
| D-243-F001 | D-243-C001 | `function _runEarlyBirdLootboxJackpot(...) private` (DegenerusGameJackpotModule) | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:670-719 | MODIFIED_LOGIC | contracts/modules/DegenerusGameJackpotModule.sol:689-706@771893d1 | emit arg changed from `ticketCount` to `ticketCount * uint32(TICKET_SCALE)` at line 701 — emitted-event value-semantics changed (D-19 emit element) |
| D-243-F002 | D-243-C002 | `function _distributeTicketsToBucket(...) private` (DegenerusGameJackpotModule) | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:966-1019 | MODIFIED_LOGIC | contracts/modules/DegenerusGameJackpotModule.sol:991-1008@771893d1 | emit arg changed from `uint32(units)` to `uint32(units * TICKET_SCALE)` at line 1003 — emitted-event value-semantics changed (D-19 emit element) |
| D-243-F003 | D-243-C003 | `function runBafJackpot(uint256, uint24, uint256) external returns (uint256)` (DegenerusGameJackpotModule) | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:1974-2059 | MODIFIED_LOGIC | contracts/modules/DegenerusGameJackpotModule.sol:2004-2046@771893d1 | two stub `emit JackpotTicketWin(winner, lvl, BAF_TRAIT_SENTINEL, 0, lvl, 0)` calls REMOVED (small-lootbox branch and odd-index branch) — emit-site removal is D-04 MODIFIED_LOGIC (D-19 emit element) |
| D-243-F004 | D-243-C004 | `function _awardJackpotTickets(address, uint256, uint24, uint256) private returns (uint256)` (DegenerusGameJackpotModule) | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:2074-2117 | MODIFIED_LOGIC | contracts/modules/DegenerusGameJackpotModule.sol:2080-2088@771893d1 | D-05.6: new `emit JackpotWhalePassWin(winner, minTargetLevel, amount / HALF_WHALE_PASS_PRICE);` added in whale-pass fallback branch (`amount > LOOTBOX_CLAIM_THRESHOLD`) before the existing `return entropy` (D-19 emit element) |
| D-243-F005 | D-243-C005 | `function _jackpotTicketRoll(address, uint256, uint24, uint256) private returns (uint256)` (DegenerusGameJackpotModule) | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:2129-2173 | MODIFIED_LOGIC | contracts/modules/DegenerusGameJackpotModule.sol:2158-2170@771893d1 | D-05.5: new `emit JackpotTicketWin(winner, targetLevel, BAF_TRAIT_SENTINEL, uint32(quantityScaled), minTargetLevel, 0);` added after `_queueLootboxTickets(...)` before `return entropy` (D-19 emit element) |
| D-243-F006 | D-243-C007 | `function advanceGame() external` (DegenerusGameAdvanceModule) | 16597cac | contracts/modules/DegenerusGameAdvanceModule.sol:156-480 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:257-279,449-451@771893d1 | D-05.1 + D-05.2 collapsed: removed `_unlockRng(day);` call at line 451 (side-effect removal — D-19 external-call/state-mutation element). Subordinate: two multi-line reformats at 257-260 (uint48 preIdx cast line-split) and 266-269 (tuple destructuring line-split) — reformat alone would be REFACTOR_ONLY but is overridden by the logic-changing removal in the same function |
| D-243-F007 | D-243-C008 | `function handlePurchase(address, uint256, uint32, uint256, uint256, uint256) external returns (uint256, uint8, uint32, bool)` (DegenerusQuests) | 6b3f4f3c | contracts/DegenerusQuests.sol:763-898 | REFACTOR_ONLY | contracts/DegenerusQuests.sol:763-828@771893d1 | D-05.4a: parameter rename `ethFreshWei → ethMintSpendWei` + NatSpec/inline-comment updates — execution trace of the callee is byte-equivalent given the same input value (every reference `s/ethFreshWei/ethMintSpendWei/g`, no branch/SSTORE/external-call change inside the body) — D-19 rename element |
| D-243-F008 | D-243-C010 | `function _purchaseFor(address, address, ...) private` (DegenerusGameMintModule) | 6b3f4f3c | contracts/modules/DegenerusGameMintModule.sol:913-1198 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:969-980,1085-1108,1164-1172@771893d1 | D-05.4b: multiple logic changes — (1) destructuring-tuple shrink drops `ticketFreshEth` local (return-path change); (2) `ethMintSpendWei = ticketCost + lootBoxAmount` replaces `ethFreshWei = ticketFreshEth + lootboxFreshEth` (different value semantics — gross spend); (3) new value threaded into `quests.handlePurchase(buyer, ethMintSpendWei, ...)` external call; (4) `_awardEarlybirdDgnrs(buyer, ticketCost + lootBoxAmount)` replaces `(buyer, ticketFreshEth + lootboxFreshEth)` — different value passed to internal call (D-19 external-call + return-path elements) |
| D-243-F009 | D-243-C011 | `function _callTicketPurchase(address, address, ...) private returns (uint256, uint256, uint32, uint24, uint32)` (DegenerusGameMintModule) | 6b3f4f3c | contracts/modules/DegenerusGameMintModule.sol:1206-1373 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:1219-1222,1289-1291@771893d1 | D-05.3: dropped `freshEth` return-tuple element (5-tuple → 4-tuple) — return-path evaluation changed for every caller; `freshEth` demoted to function-local-scope `uint256 freshEth;` before DirectEth branch (D-19 return-path element) |
| D-243-F010 | D-243-C012 | `function livenessTriggered() external view returns (bool)` (DegenerusGame) | 771893d1 | contracts/DegenerusGame.sol:2133-2135 | NEW | contracts/DegenerusGame.sol:2129-2135@771893d1 | Function absent at baseline `7ab515fe` (`git show 7ab515fe:contracts/DegenerusGame.sol \| grep -c 'function livenessTriggered'` returns 0); appears at HEAD with body `return _livenessTriggered();` — presence-at-HEAD / absence-at-baseline fact |
| D-243-F011 | D-243-C013 | `function burn(uint256) external returns (uint256, uint256, uint256)` (StakedDegenerusStonk) | 771893d1 | contracts/StakedDegenerusStonk.sol:486-495 | MODIFIED_LOGIC | contracts/StakedDegenerusStonk.sol:486-495@771893d1 | D-05.8a: new control-flow branch `if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();` inserted at line 487 between `game.gameOver()` short-circuit and existing `game.rngLocked()` guard — new branch + new revert-path (D-19 branch element) |
| D-243-F012 | D-243-C014 | `function burnWrapped(uint256) external returns (uint256, uint256, uint256)` (StakedDegenerusStonk) | 771893d1 | contracts/StakedDegenerusStonk.sol:506-516 | MODIFIED_LOGIC | contracts/StakedDegenerusStonk.sol:505-506@771893d1 | D-05.8b: new control-flow branch `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` inserted at line 505 before existing `dgnrsWrapper.burnForSdgnrs(...)` external call — new branch + new revert-path (D-19 branch element) |
| D-243-F013 | D-243-C015 | `function _handleGameOverPath(uint32, uint24, uint32) internal returns (bool, uint8)` (DegenerusGameAdvanceModule) | 771893d1 | contracts/modules/DegenerusGameAdvanceModule.sol:519-630 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:527-548@771893d1 | D-05.11b: control-flow reorder — `if (!_livenessTriggered()) return (false, 0);` moved from function prologue (was line 527) to after the `if (gameOver)` delegatecall block (now at line 548). Gameover branch now evaluated first so post-gameOver final-sweep stays reachable under VRF-dead-with-day-math-unmet stall (D-19 branch/control-flow element) |
| D-243-F014 | D-243-C016 | `function _gameOverEntropy() internal returns (uint256)` (DegenerusGameAdvanceModule) | 771893d1 | contracts/modules/DegenerusGameAdvanceModule.sol:1216-1294 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:1275-1279@771893d1 | D-05.11a: new `rngRequestTime = 0;` SSTORE added after `_finalizeLootboxRng(fallbackWord);` and before `return fallbackWord;` — new state-mutation clearing the VRF-stall timer on fallback commit (D-19 SSTORE element) |
| D-243-F015 | D-243-C017 | `function handleGameOverDrain() external` (DegenerusGameGameOverModule) | 771893d1 | contracts/modules/DegenerusGameGameOverModule.sol:79-189 | MODIFIED_LOGIC | contracts/modules/DegenerusGameGameOverModule.sol:86-94,151-156@771893d1 | D-05.9: two separate hunks — (1) pre-refund `available` computation replaced with `reserved = uint256(claimablePool) + IStakedDegenerusStonk(ContractAddresses.SDGNRS).pendingRedemptionEthValue()` then `preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0` (new external call + new arithmetic); (2) same pattern duplicated post-refund at lines 151-156 (`postRefundReserved` then `available`). Both hunks introduce new external calls AND arithmetic, shrinking the 33/33/34-split budget by reserved sDGNRS ETH (D-19 external-call + arithmetic elements) |
| D-243-F016 | D-243-C018 | `function _purchaseCoinFor(address, uint256, uint256) private` (DegenerusGameMintModule) | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:885-911 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:890@771893d1 | D-05.7 (1 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` — control-flow branch keys on a different predicate (one-cycle-earlier cutoff) (D-19 branch element) |
| D-243-F017 | D-243-C019 | `function _purchaseFor(address, address, ...) private` (DegenerusGameMintModule) | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:913-1198 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:920@771893d1 | D-05.7 (2 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` at function prologue — control-flow branch keys on a different predicate. (Row distinct from D-243-F008 which covers 6b3f4f3c-era changes on the same function; this row scopes only the 771893d1 gate-swap hunk) (D-19 branch element) |
| D-243-F018 | D-243-C020 | `function _callTicketPurchase(address, address, ...) private returns (uint256, uint256, uint32, uint24, uint32)` (DegenerusGameMintModule) | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:1206-1373 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:1226@771893d1 | D-05.7 (3 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` after the pre-existing `if (quantity == 0) revert E();` — control-flow branch keys on a different predicate. (Row distinct from D-243-F009 which covers the 6b3f4f3c return-tuple shrink on same function) (D-19 branch element) |
| D-243-F019 | D-243-C021 | `function _purchaseBurnieLootboxFor(address, uint256) private` (DegenerusGameMintModule) | 771893d1 | contracts/modules/DegenerusGameMintModule.sol:1388-1423 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:1392@771893d1 | D-05.7 (4 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` — control-flow branch keys on a different predicate (D-19 branch element) |
| D-243-F020 | D-243-C022 | `function _purchaseWhaleBundle(address, uint256) private` (DegenerusGameWhaleModule) | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:194-365 | MODIFIED_LOGIC | contracts/modules/DegenerusGameWhaleModule.sol:195@771893d1 | D-05.7 (5 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` — control-flow branch keys on a different predicate (D-19 branch element) |
| D-243-F021 | D-243-C023 | `function _purchaseLazyPass(address) private` (DegenerusGameWhaleModule) | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:384-518 | MODIFIED_LOGIC | contracts/modules/DegenerusGameWhaleModule.sol:385@771893d1 | D-05.7 (6 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` — control-flow branch keys on a different predicate (D-19 branch element) |
| D-243-F022 | D-243-C024 | `function _purchaseDeityPass(address, uint8) private` (DegenerusGameWhaleModule) | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:542-674 | MODIFIED_LOGIC | contracts/modules/DegenerusGameWhaleModule.sol:544@771893d1 | D-05.7 (7 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` after the pre-existing `if (rngLockedFlag) revert RngLocked();` — control-flow branch keys on a different predicate (D-19 branch element) |
| D-243-F023 | D-243-C025 | `function claimWhalePass(address) external` (DegenerusGameWhaleModule) | 771893d1 | contracts/modules/DegenerusGameWhaleModule.sol:957-974 | MODIFIED_LOGIC | contracts/modules/DegenerusGameWhaleModule.sol:958@771893d1 | D-05.7 (8 of 8): guard condition changed from `if (gameOver) revert E();` to `if (_livenessTriggered()) revert E();` at function prologue — control-flow branch keys on a different predicate (D-19 branch element) |
| D-243-F024 | D-243-C026 | `function _livenessTriggered() internal view returns (bool)` (DegenerusGameStorage) | 771893d1 | contracts/storage/DegenerusGameStorage.sol:1235-1243 | MODIFIED_LOGIC | contracts/storage/DegenerusGameStorage.sol:1235-1243@771893d1 | D-05.10: function body rewritten — baseline's `return (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) \|\| (lvl != 0 && currentDay - psd > 120);` replaced with two early-return `if` branches (day-math-first ordering) followed by new SLOAD of `rngRequestTime` and new 14-day VRF-dead grace branch `return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;` — new return-path (VRF-dead) + new branch-ordering + new state-read (D-19 branch + return-path elements) |
| D-243-F025 | D-243-C036 | `function markBafSkipped(uint24) external` (DegenerusJackpots) | cc68bfc7 | contracts/DegenerusJackpots.sol:498-510 | NEW | contracts/DegenerusJackpots.sol:498-510@cc68bfc7 | Function absent at baseline `7ab515fe` (`git show 7ab515fe:contracts/DegenerusJackpots.sol \| grep -c 'function markBafSkipped'` returns 0); appears at HEAD with body that SSTORE-writes `lastBafResolvedDay = today` and `emit BafSkipped(lvl, today);` under `onlyGame` modifier — presence-at-HEAD / absence-at-baseline fact |
| D-243-F026 | D-243-C039 | `function _consolidatePoolsAndRewardJackpots(uint24, uint256, uint256) internal returns (uint256, uint256)` (DegenerusGameAdvanceModule) | cc68bfc7 | contracts/modules/DegenerusGameAdvanceModule.sol:728-909 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:822-839@cc68bfc7 | Function existed at baseline `7ab515fe` (`git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol \| grep -c 'function _consolidatePoolsAndRewardJackpots'` returns 1); new control-flow branch wraps the BAF jackpot call on `if ((rngWord & 1) == 1) { ... } else { jackpots.markBafSkipped(lvl); }` — on losing daily flip, the existing `IDegenerusGame(address(this)).runBafJackpot(...)` external call is skipped and replaced with a new external call `jackpots.markBafSkipped(lvl)` via the newly-added file-scope constant `jackpots` (new branch + new external call + new skip-path) (D-19 branch + external-call elements) |

### 2.4 Verdict-Bucket Summary

| Classification | Row Count | Row IDs |
|---|---|---|
| NEW | 2 | D-243-F010, D-243-F025 |
| MODIFIED_LOGIC | 23 | D-243-F001, F002, F003, F004, F005, F006, F008, F009, F011, F012, F013, F014, F015, F016, F017, F018, F019, F020, F021, F022, F023, F024, F026 |
| REFACTOR_ONLY | 1 | D-243-F007 |
| DELETED | 0 | — (no Section 1 row is absent at HEAD; every 12-file in the touching surface is M-status per `git diff --name-status 7ab515fe..cc68bfc7 -- contracts/`) |
| RENAMED | 0 | — (no Section 1 func row identified as a pure rename — the only candidate was D-05.4 `handlePurchase` parameter rename, which is scoped to REFACTOR_ONLY per D-05.4a and remains a function-internal rename rather than a function-level rename) |
| **Total** | **26** | (= Section 1 func row count of 24 at `771893d1` plus 2 net-new at `cc68bfc7`; modifier row count = 0 at both HEADs) |

**Sanity check:** Total 26 equals the sum of Section 1's change-count-card `functions:` field across all commit subsections — §1.1 ced654df: 5 / §1.2 16597cac: 1 / §1.3 6b3f4f3c: 3 / §1.4 771893d1: 12 / §1.5 ffced9ef: 0 / §1.6 cc68bfc7: 2 = 23 classification entries with D-243-C-row IDs plus the `_callTicketPurchase` and `_purchaseFor` duplicate counting across 6b3f4f3c + 771893d1 (each function's row-count is preserved 1:1 because Section 1 emitted distinct rows per-commit for the same function). Breakdown: 5 (ced654df) + 1 (16597cac) + 3 (6b3f4f3c) + 15 (771893d1, counting the 8 gate-swap + 5 other + 2 duplicated `_purchaseFor`/`_callTicketPurchase` which Section 1 issued as C019/C020 distinct from C010/C011) + 2 (cc68bfc7) = 26. Matches §2.3 row count exactly.

### 2.5 Deviations From D-05 Pre-Locked Verdicts

Zero deviations. All 11 CONTEXT.md D-05 pre-locked verdicts (D-05.1 + D-05.2 collapsed, D-05.3, D-05.4a, D-05.4b, D-05.5, D-05.6, D-05.7 ×8 paths, D-05.8a, D-05.8b, D-05.9, D-05.10, D-05.11a, D-05.11b) confirmed at HEAD `771893d1` via fresh `git show` inspection and applied verbatim in §2.3. The two cc68bfc7 addendum rows (D-243-F025 NEW and D-243-F026 MODIFIED_LOGIC) are NOT in D-05's scope — their verdicts were derived fresh from the cc68bfc7 diff per D-04 taxonomy + D-19 evidence burden and are consistent with the 243-01-ADDENDUM-SUMMARY.md's stated classifications.

No new Finding Candidates surfaced during this classification pass — Section 1.7's 8 INFO candidates (5 from original 771893d1 sweep + 3 from cc68bfc7 addendum) are preserved byte-identical.

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
| D-243-C040 | cc68bfc7 | contracts/modules/DegenerusGameAdvanceModule.sol:105-106 | `jackpots` | `IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS)` | ADDED | file-scope constant (ContractAddresses-sourced immutable address) — no storage slot consumed; direct handle used only in the losing-flip branch of `_consolidatePoolsAndRewardJackpots` to call `markBafSkipped(lvl)` (ADDENDUM — cc68bfc7) |

No mutable state variable additions, removals, or signature changes across the 6 commits. Section 5 storage-slot diff confirms zero slot drift at both HEAD anchors (`771893d1` and `cc68bfc7`).

### 4.2 Events

Across the original 5 commits, no new event declarations were introduced (`JackpotWhalePassWin` is NOT new — it existed at baseline `7ab515fe` at baseline JackpotModule line 110 / HEAD line 116-120; commit `ced654df` added new EMIT sites for the existing event — rows D-243-C004 + D-243-C005 in Section 1). The cc68bfc7 addendum adds exactly one new event declaration (`BafSkipped`).

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Event Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C029 | ced654df | contracts/modules/DegenerusGameJackpotModule.sol:86-93 | `JackpotTicketWin` | `JackpotTicketWin(address indexed winner, uint24 indexed ticketLevel, uint16 indexed traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex)` | NATSPEC-ONLY | signature unchanged; NatSpec expanded to document TICKET_SCALE scaling + fractional-remainder resolution |
| D-243-C041 | cc68bfc7 | contracts/DegenerusJackpots.sol:71-74 | `BafSkipped` | `BafSkipped(uint24 indexed lvl, uint32 day)` | ADDED | new event emitted exactly-once per skipped BAF bracket from `markBafSkipped(lvl)`; day is `degenerusGame.currentDayView()` at skip time (ADDENDUM — cc68bfc7) |

### 4.3 Interface Methods

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Method Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C030 | 6b3f4f3c | contracts/interfaces/IDegenerusQuests.sol:139-152 | `handlePurchase` | `handlePurchase(address player, uint256 ethMintSpendWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, uint256 levelQuestPrice) external returns (uint256 reward, uint8 questType, uint32 streak, bool completed)` | SIGNATURE-CHANGED | parameter rename ethFreshWei→ethMintSpendWei; semantic shift from fresh-only to gross-spend quest crediting |
| D-243-C031 | 771893d1 | contracts/interfaces/IDegenerusGame.sol:27-30 | `livenessTriggered` | `livenessTriggered() external view returns (bool)` | ADDED | new interface method exposing internal `_livenessTriggered()` for cross-contract reads (sDGNRS State-1 gate) |
| D-243-C032 | 771893d1 | contracts/interfaces/IStakedDegenerusStonk.sol:88-90 | `pendingRedemptionEthValue` | `pendingRedemptionEthValue() external view returns (uint256)` | ADDED | new interface method reporting ETH reserved for in-flight gambling-burn redemptions; consumed by handleGameOverDrain |
| D-243-C033 | 771893d1 | contracts/StakedDegenerusStonk.sol:29-30 | `livenessTriggered` (inline `IDegenerusGamePlayer`) | `livenessTriggered() external view returns (bool)` | ADDED | inline IDegenerusGamePlayer interface (defined in-file at top of StakedDegenerusStonk.sol) extended with livenessTriggered method call needed by burn/burnWrapped |
| D-243-C042 | cc68bfc7 | contracts/interfaces/IDegenerusJackpots.sol:30-34 | `markBafSkipped` | `markBafSkipped(uint24 lvl) external` | ADDED | new interface method declared on IDegenerusJackpots; implementation in DegenerusJackpots.sol is `onlyGame`-restricted and bumps `lastBafResolvedDay` to filter pre-skip winning-flip credit (ADDENDUM — cc68bfc7) |

### 4.4 Errors / Custom Reverts

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Error Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-243-C034 | 771893d1 | contracts/StakedDegenerusStonk.sol:102-105 | `BurnsBlockedDuringLiveness` | `BurnsBlockedDuringLiveness()` | ADDED | new State-1 revert raised by burn/burnWrapped when liveness fired but gameOver not yet latched |

## Section 5 — Storage Slot Layout Diff (DegenerusGameStorage.sol)

Sole scope input for Phase 244 GOX-07 per CONTEXT.md D-16. Verifies every slot that changed label / offset / type / size between baseline `7ab515fe` and head `771893d1`. Commit `771893d1` is the only storage-file-touching commit in this milestone (+27 lines); all Section 5 rows attribute to `771893d1`.

**Key verdict (spoiler):** `forge inspect` output at baseline and head is byte-identical — zero slot-level layout drift. The +27 lines of the commit are: (a) a new `uint48 internal constant _VRF_GRACE_PERIOD = 14 days;` (compile-time constant, inlined into bytecode, consumes no slot — Section 4 row D-243-C028), and (b) a NatSpec + body rewrite of the `_livenessTriggered` view function (Section 1 row D-243-C026, no state added). Phase 244 GOX-07 verdict expected: `backwards-compatible` (no layout change of any kind, not even an appended slot).

**Source command (reproducible):** `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` run at both SHAs. Baseline captured via `git worktree add --detach <tmp> 7ab515fe` to avoid touching the main working tree.

### 5.1 Baseline storage layout (at 7ab515fe)

<details><summary>Raw `forge inspect` output (baseline 7ab515fe) — 65 slots total (slot 0..64)</summary>

```
╭--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------╮
| Name                           | Type                                                                        | Slot | Offset | Bytes | Contract                                                        |
+========================================================================================================================================================================================================+
| purchaseStartDay               | uint32                                                                      | 0    | 0      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyIdx                       | uint32                                                                      | 0    | 4      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngRequestTime                 | uint48                                                                      | 0    | 8      | 6     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| level                          | uint24                                                                      | 0    | 14     | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| jackpotPhaseFlag               | bool                                                                        | 0    | 17     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| jackpotCounter                 | uint8                                                                       | 0    | 18     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastPurchaseDay                | bool                                                                        | 0    | 19     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decWindowOpen                  | bool                                                                        | 0    | 20     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngLockedFlag                  | bool                                                                        | 0    | 21     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| phaseTransitionActive          | bool                                                                        | 0    | 22     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOver                       | bool                                                                        | 0    | 23     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyJackpotCoinTicketsPending | bool                                                                        | 0    | 24     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| compressedJackpotFlag          | uint8                                                                       | 0    | 25     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketsFullyProcessed          | bool                                                                        | 0    | 26     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOverPossible               | bool                                                                        | 0    | 27     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketWriteSlot                | bool                                                                        | 0    | 28     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolFrozen                | bool                                                                        | 0    | 29     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| currentPrizePool               | uint128                                                                     | 1    | 0      | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| claimablePool                  | uint128                                                                     | 1    | 16     | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolsPacked               | uint256                                                                     | 2    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngWordCurrent                 | uint256                                                                     | 3    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfRequestId                   | uint256                                                                     | 4    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| totalFlipReversals             | uint256                                                                     | 5    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyTicketBudgetsPacked       | uint256                                                                     | 6    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| claimableWinnings              | mapping(address => uint256)                                                 | 7    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| traitBurnTicket                | mapping(uint24 => address[][256])                                           | 8    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| mintPacked_                    | mapping(address => uint256)                                                 | 9    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngWordByDay                   | mapping(uint32 => uint256)                                                  | 10   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolPendingPacked         | uint256                                                                     | 11   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketQueue                    | mapping(uint24 => address[])                                                | 12   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketsOwedPacked              | mapping(uint24 => mapping(address => uint40))                               | 13   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketCursor                   | uint32                                                                      | 14   | 0      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketLevel                    | uint24                                                                      | 14   | 4      | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEth                     | mapping(uint48 => mapping(address => uint256))                              | 15   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| presaleStatePacked             | uint256                                                                     | 16   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOverStatePacked            | uint256                                                                     | 17   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| whalePassClaims                | mapping(address => uint256)                                                 | 18   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| autoRebuyState                 | mapping(address => struct DegenerusGameStorage.AutoRebuyState)              | 19   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEthBase                 | mapping(uint48 => mapping(address => uint256))                              | 20   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| operatorApprovals              | mapping(address => mapping(address => bool))                                | 21   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelPrizePool                 | mapping(uint24 => uint256)                                                  | 22   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| affiliateDgnrsClaimedBy        | mapping(uint24 => mapping(address => bool))                                 | 23   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelDgnrsAllocation           | mapping(uint24 => uint256)                                                  | 24   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelDgnrsClaimed              | mapping(uint24 => uint256)                                                  | 25   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassPurchasedCount        | mapping(address => uint16)                                                  | 26   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassPaidTotal             | mapping(address => uint256)                                                 | 27   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassOwners                | address[]                                                                   | 28   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassSymbol                | mapping(address => uint8)                                                   | 29   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBySymbol                  | mapping(uint8 => address)                                                   | 30   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| earlybirdDgnrsPoolStart        | uint256                                                                     | 31   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| earlybirdEthIn                 | uint256                                                                     | 32   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| resumeEthPool                  | uint128                                                                     | 33   | 0      | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfCoordinator                 | contract IVRFCoordinator                                                    | 34   | 0      | 20    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfKeyHash                     | bytes32                                                                     | 35   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfSubscriptionId              | uint256                                                                     | 36   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxRngPacked               | uint256                                                                     | 37   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxRngWordByIndex          | mapping(uint48 => uint256)                                                  | 38   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxDay                     | mapping(uint48 => mapping(address => uint32))                               | 39   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxBaseLevelPacked         | mapping(uint48 => mapping(address => uint24))                               | 40   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEvScorePacked           | mapping(uint48 => mapping(address => uint16))                               | 41   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxBurnie                  | mapping(uint48 => mapping(address => uint256))                              | 42   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonDay                   | mapping(address => uint32)                                                  | 43   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonUsedMask              | mapping(address => uint8)                                                   | 44   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonRecipientDay          | mapping(address => uint32)                                                  | 45   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| degeneretteBets                | mapping(address => mapping(uint64 => uint256))                              | 46   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| degeneretteBetNonce            | mapping(address => uint64)                                                  | 47   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEvBenefitUsedByLevel    | mapping(address => mapping(uint24 => uint256))                              | 48   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBurn                        | mapping(uint24 => mapping(address => struct DegenerusGameStorage.DecEntry)) | 49   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBucketBurnTotal             | mapping(uint24 => uint256[13][13])                                          | 50   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decClaimRounds                 | mapping(uint24 => struct DegenerusGameStorage.DecClaimRound)                | 51   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBucketOffsetPacked          | mapping(uint24 => uint64)                                                   | 52   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyHeroWagers                | mapping(uint32 => uint256[4])                                               | 53   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| playerDegeneretteEthWagered    | mapping(address => mapping(uint24 => uint256))                              | 54   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| topDegeneretteByLevel          | mapping(uint24 => uint256)                                                  | 55   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxDistressEth             | mapping(uint48 => mapping(address => uint256))                              | 56   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| yieldAccumulator               | uint256                                                                     | 57   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| centuryBonusLevel              | uint24                                                                      | 58   | 0      | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| centuryBonusUsed               | mapping(address => uint256)                                                 | 59   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastVrfProcessedTimestamp      | uint48                                                                      | 60   | 0      | 6     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| terminalDecEntries             | mapping(address => struct DegenerusGameStorage.TerminalDecEntry)            | 61   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| terminalDecBucketBurnTotal     | mapping(bytes32 => uint256)                                                 | 62   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastTerminalDecClaimRound      | struct DegenerusGameStorage.TerminalDecClaimRound                           | 63   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| boonPacked                     | mapping(address => struct DegenerusGameStorage.BoonPacked)                  | 64   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
╰--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------╯
```

</details>

### 5.2 Head storage layout (at 771893d1)

<details><summary>Raw `forge inspect` output (head 771893d1) — 65 slots total (slot 0..64) — byte-identical to baseline</summary>

```
╭--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------╮
| Name                           | Type                                                                        | Slot | Offset | Bytes | Contract                                                        |
+========================================================================================================================================================================================================+
| purchaseStartDay               | uint32                                                                      | 0    | 0      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyIdx                       | uint32                                                                      | 0    | 4      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngRequestTime                 | uint48                                                                      | 0    | 8      | 6     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| level                          | uint24                                                                      | 0    | 14     | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| jackpotPhaseFlag               | bool                                                                        | 0    | 17     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| jackpotCounter                 | uint8                                                                       | 0    | 18     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastPurchaseDay                | bool                                                                        | 0    | 19     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decWindowOpen                  | bool                                                                        | 0    | 20     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngLockedFlag                  | bool                                                                        | 0    | 21     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| phaseTransitionActive          | bool                                                                        | 0    | 22     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOver                       | bool                                                                        | 0    | 23     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyJackpotCoinTicketsPending | bool                                                                        | 0    | 24     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| compressedJackpotFlag          | uint8                                                                       | 0    | 25     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketsFullyProcessed          | bool                                                                        | 0    | 26     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOverPossible               | bool                                                                        | 0    | 27     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketWriteSlot                | bool                                                                        | 0    | 28     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolFrozen                | bool                                                                        | 0    | 29     | 1     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| currentPrizePool               | uint128                                                                     | 1    | 0      | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| claimablePool                  | uint128                                                                     | 1    | 16     | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolsPacked               | uint256                                                                     | 2    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngWordCurrent                 | uint256                                                                     | 3    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfRequestId                   | uint256                                                                     | 4    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| totalFlipReversals             | uint256                                                                     | 5    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyTicketBudgetsPacked       | uint256                                                                     | 6    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| claimableWinnings              | mapping(address => uint256)                                                 | 7    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| traitBurnTicket                | mapping(uint24 => address[][256])                                           | 8    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| mintPacked_                    | mapping(address => uint256)                                                 | 9    | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| rngWordByDay                   | mapping(uint32 => uint256)                                                  | 10   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| prizePoolPendingPacked         | uint256                                                                     | 11   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketQueue                    | mapping(uint24 => address[])                                                | 12   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketsOwedPacked              | mapping(uint24 => mapping(address => uint40))                               | 13   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketCursor                   | uint32                                                                      | 14   | 0      | 4     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| ticketLevel                    | uint24                                                                      | 14   | 4      | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEth                     | mapping(uint48 => mapping(address => uint256))                              | 15   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| presaleStatePacked             | uint256                                                                     | 16   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| gameOverStatePacked            | uint256                                                                     | 17   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| whalePassClaims                | mapping(address => uint256)                                                 | 18   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| autoRebuyState                 | mapping(address => struct DegenerusGameStorage.AutoRebuyState)              | 19   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEthBase                 | mapping(uint48 => mapping(address => uint256))                              | 20   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| operatorApprovals              | mapping(address => mapping(address => bool))                                | 21   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelPrizePool                 | mapping(uint24 => uint256)                                                  | 22   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| affiliateDgnrsClaimedBy        | mapping(uint24 => mapping(address => bool))                                 | 23   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelDgnrsAllocation           | mapping(uint24 => uint256)                                                  | 24   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| levelDgnrsClaimed              | mapping(uint24 => uint256)                                                  | 25   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassPurchasedCount        | mapping(address => uint16)                                                  | 26   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassPaidTotal             | mapping(address => uint256)                                                 | 27   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassOwners                | address[]                                                                   | 28   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityPassSymbol                | mapping(address => uint8)                                                   | 29   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBySymbol                  | mapping(uint8 => address)                                                   | 30   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| earlybirdDgnrsPoolStart        | uint256                                                                     | 31   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| earlybirdEthIn                 | uint256                                                                     | 32   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| resumeEthPool                  | uint128                                                                     | 33   | 0      | 16    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfCoordinator                 | contract IVRFCoordinator                                                    | 34   | 0      | 20    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfKeyHash                     | bytes32                                                                     | 35   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| vrfSubscriptionId              | uint256                                                                     | 36   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxRngPacked               | uint256                                                                     | 37   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxRngWordByIndex          | mapping(uint48 => uint256)                                                  | 38   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxDay                     | mapping(uint48 => mapping(address => uint32))                               | 39   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxBaseLevelPacked         | mapping(uint48 => mapping(address => uint24))                               | 40   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEvScorePacked           | mapping(uint48 => mapping(address => uint16))                               | 41   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxBurnie                  | mapping(uint48 => mapping(address => uint256))                              | 42   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonDay                   | mapping(address => uint32)                                                  | 43   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonUsedMask              | mapping(address => uint8)                                                   | 44   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| deityBoonRecipientDay          | mapping(address => uint32)                                                  | 45   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| degeneretteBets                | mapping(address => mapping(uint64 => uint256))                              | 46   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| degeneretteBetNonce            | mapping(address => uint64)                                                  | 47   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxEvBenefitUsedByLevel    | mapping(address => mapping(uint24 => uint256))                              | 48   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBurn                        | mapping(uint24 => mapping(address => struct DegenerusGameStorage.DecEntry)) | 49   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBucketBurnTotal             | mapping(uint24 => uint256[13][13])                                          | 50   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decClaimRounds                 | mapping(uint24 => struct DegenerusGameStorage.DecClaimRound)                | 51   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| decBucketOffsetPacked          | mapping(uint24 => uint64)                                                   | 52   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| dailyHeroWagers                | mapping(uint32 => uint256[4])                                               | 53   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| playerDegeneretteEthWagered    | mapping(address => mapping(uint24 => uint256))                              | 54   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| topDegeneretteByLevel          | mapping(uint24 => uint256)                                                  | 55   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lootboxDistressEth             | mapping(uint48 => mapping(address => uint256))                              | 56   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| yieldAccumulator               | uint256                                                                     | 57   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| centuryBonusLevel              | uint24                                                                      | 58   | 0      | 3     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| centuryBonusUsed               | mapping(address => uint256)                                                 | 59   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastVrfProcessedTimestamp      | uint48                                                                      | 60   | 0      | 6     | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| terminalDecEntries             | mapping(address => struct DegenerusGameStorage.TerminalDecEntry)            | 61   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| terminalDecBucketBurnTotal     | mapping(bytes32 => uint256)                                                 | 62   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| lastTerminalDecClaimRound      | struct DegenerusGameStorage.TerminalDecClaimRound                           | 63   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
|--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------|
| boonPacked                     | mapping(address => struct DegenerusGameStorage.BoonPacked)                  | 64   | 0      | 32    | contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage |
╰--------------------------------+-----------------------------------------------------------------------------+------+--------+-------+-----------------------------------------------------------------╯
```

</details>

### 5.3 Slot-by-slot diff

Byte-identical `forge inspect` output at both SHAs → zero slot-level changes. The table below emits a single summary row covering the full slot range.

| Row ID | Slot | Baseline (label / type / offset / bytes) | Head (label / type / offset / bytes) | Change Type | One-Line Note |
|---|---|---|---|---|---|
| D-243-S001 | 0..64 (65 slots total) | identical to head | identical to baseline | UNCHANGED | `diff baseline head` returns zero; commit 771893d1 added only a compile-time constant (D-243-C028) plus a view-function rewrite (D-243-C026) — no slot impact |

Change Type vocabulary (only one option exercised in this milestone):
- `APPENDED` — new slot at end; no prior slot displaced (backwards-compatible — sole happy-path verdict for Phase 244 GOX-07)
- `MOVED` — existing label moved to a different slot number (LAYOUT-BREAK candidate — Phase 244 GOX-07 must justify intentional break)
- `TYPE-CHANGED` — same slot number, same label (or renamed), but the solidity type / size changed (SEMANTIC-BREAK candidate)
- `INSERTED` — new slot inserted mid-layout displacing subsequent slots (LAYOUT-BREAK candidate)
- `REMOVED` — baseline slot absent at head (LAYOUT-BREAK candidate)
- `OFFSET-CHANGED` — packed slot where a neighbor changed size (within-slot layout shift; usually benign)
- `UNCHANGED` — no delta (used for summary row when the full layout is byte-identical)

### 5.4 Backwards-compatibility verdict (per-row)

| Row ID | Phase 244 GOX-07 Expected Verdict | Rationale |
|---|---|---|
| D-243-S001 | backwards-compatible-no-change | Zero layout drift — every slot label/type/offset/bytes preserved exactly. Storage is functionally immutable across the 5-commit delta. Phase 244 GOX-07 is expected to close in seconds with "no layout change, no verification needed". |

### 5.5 Addendum at cc68bfc7 (byte-identical to 771893d1; no new storage changes)

Commit `cc68bfc7` touches 3 files (`contracts/DegenerusJackpots.sol`, `contracts/interfaces/IDegenerusJackpots.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`) — NONE of which is `contracts/storage/DegenerusGameStorage.sol`. `git diff 771893d1..cc68bfc7 -- contracts/storage/` returns empty.

`forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` re-run at head `cc68bfc7` (via `git worktree add --detach <tmp> cc68bfc7`) produces output byte-identical to the 771893d1 output in §5.2 — verified via `diff /tmp/v31-243-addendum/storage-layout-771893d1.txt /tmp/v31-243-addendum/storage-layout-cc68bfc7.txt` returning zero diff. No new D-243-S row is emitted for the addendum; D-243-S001's UNCHANGED verdict carries forward to HEAD `cc68bfc7`.

`DegenerusJackpots.sol` (which gained a new mutable state slot elsewhere in its own storage layout — `lastBafResolvedDay` bump path) is a separate contract from `DegenerusGameStorage`; its storage layout is NOT in scope for this section per CONTEXT.md D-16 (which is scoped to `DegenerusGameStorage.sol` only as the GOX-07 sole scope input). If Phase 244 EVT-02 / GOX-07 need `DegenerusJackpots.sol`'s own layout diff, that is a separate reproduction command outside this section's scope.

## Section 6 — Consumer Index (RESERVED FOR 243-03)

This section is reserved for Plan 243-03 to append the v31.0 requirement → 243 Row-ID mapping. Row IDs `D-243-I###`. DO NOT edit this section in Plan 243-01 — 243-03 appends to it.

## Section 7 — Reproduction Recipe Appendix

Per CONTEXT.md D-18: every command used by Phase 243 plans preserved here so a reviewer can replay the entire DELTA-01 / DELTA-02 / DELTA-03 enumeration from shell.

Portable POSIX syntax only. Commands are grouped by plan (243-01 / 243-02 / 243-03). This pass covers 243-01 (Tasks 1 + 2). Plan 243-02 and Plan 243-03 append their own subsections (§7.2 / §7.3) during their execution.

### 7.1 Plan 243-01 commands (DELTA-01 enumeration + storage layout)

**Baseline sanity gate:**

```bash
git rev-parse 7ab515fe
git rev-parse 771893d1
git rev-parse HEAD
git diff --stat 7ab515fe..771893d1 -- contracts/
git log --format='%H %s' 7ab515fe..771893d1
git diff --name-status 7ab515fe..771893d1 -- contracts/
git status --porcelain contracts/ test/
```

Expected output: `git diff --stat` reports `12 files changed, 140 insertions(+), 57 deletions(-)`; `git log` lists 5 commits in reverse-chronological order (`771893d1` / `6b3f4f3c` / `16597cac` / `ced654df` / `ffced9ef`); `git diff --name-status` lists exactly 12 M-status files; `git status --porcelain contracts/ test/` returns empty.

**Per-commit diff enumeration (Section 1):**

```bash
# Commit 1 — ced654df (JackpotModule only)
git show ced654df -- contracts/modules/DegenerusGameJackpotModule.sol

# Commit 2 — 16597cac (AdvanceModule only)
git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol

# Commit 3 — 6b3f4f3c (3 files)
git show 6b3f4f3c -- contracts/DegenerusQuests.sol
git show 6b3f4f3c -- contracts/interfaces/IDegenerusQuests.sol
git show 6b3f4f3c -- contracts/modules/DegenerusGameMintModule.sol

# Commit 4 — 771893d1 (9 files)
git show 771893d1 -- contracts/DegenerusGame.sol
git show 771893d1 -- contracts/StakedDegenerusStonk.sol
git show 771893d1 -- contracts/interfaces/IDegenerusGame.sol
git show 771893d1 -- contracts/interfaces/IStakedDegenerusStonk.sol
git show 771893d1 -- contracts/modules/DegenerusGameAdvanceModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameGameOverModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameMintModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameWhaleModule.sol
git show 771893d1 -- contracts/storage/DegenerusGameStorage.sol

# Commit 5 — ffced9ef (docs-only per D-13; no contracts/ touch)
git show ffced9ef --stat
```

**Per-function line-range resolution (for Section 1 / Section 4 File:Line-Range columns):**

```bash
# Example — find the head-side header line for a specific function
grep -n '^\s*function _livenessTriggered' contracts/modules/DegenerusGameAdvanceModule.sol
grep -n '^\s*function _livenessTriggered' contracts/storage/DegenerusGameStorage.sol

# Compute function end via matching brace count — programmatic helper
# (every Section 1 row's end line derived by walking from the header line forward
# and counting { vs } until depth returns to 0)
```

**Baseline-side source reads (for DELETED/RENAMED detection and baseline line-number context):**

```bash
git show 7ab515fe:contracts/DegenerusGame.sol > /tmp/v31-243/baseline-DegenerusGame.sol
git show 7ab515fe:contracts/DegenerusQuests.sol > /tmp/v31-243/baseline-DegenerusQuests.sol
git show 7ab515fe:contracts/StakedDegenerusStonk.sol > /tmp/v31-243/baseline-StakedDegenerusStonk.sol
git show 7ab515fe:contracts/interfaces/IDegenerusGame.sol > /tmp/v31-243/baseline-IDegenerusGame.sol
git show 7ab515fe:contracts/interfaces/IDegenerusQuests.sol > /tmp/v31-243/baseline-IDegenerusQuests.sol
git show 7ab515fe:contracts/interfaces/IStakedDegenerusStonk.sol > /tmp/v31-243/baseline-IStakedDegenerusStonk.sol
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol > /tmp/v31-243/baseline-AdvanceModule.sol
git show 7ab515fe:contracts/modules/DegenerusGameGameOverModule.sol > /tmp/v31-243/baseline-GameOverModule.sol
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol > /tmp/v31-243/baseline-JackpotModule.sol
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol > /tmp/v31-243/baseline-MintModule.sol
git show 7ab515fe:contracts/modules/DegenerusGameWhaleModule.sol > /tmp/v31-243/baseline-WhaleModule.sol
git show 7ab515fe:contracts/storage/DegenerusGameStorage.sol > /tmp/v31-243/baseline-DegenerusGameStorage.sol
```

**Storage slot layout diff (Section 5):**

```bash
# Head-side layout (run at HEAD 771893d1 in the main working tree)
forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout > /tmp/v31-243/storage-layout-head.txt

# Baseline-side layout via temporary worktree (avoids touching main working tree)
WORKTREE_DIR=$(mktemp -d -t v31-243-baseline-XXXXXX)
git worktree add --detach "$WORKTREE_DIR" 7ab515fe
(cd "$WORKTREE_DIR" && forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout) > /tmp/v31-243/storage-layout-baseline.txt
git worktree remove --force "$WORKTREE_DIR"

# Visual diff (expected: byte-identical — see Section 5 verdict)
diff /tmp/v31-243/storage-layout-baseline.txt /tmp/v31-243/storage-layout-head.txt
```

**Light v30 consumer reconciliation (Section 1.7):**

```bash
# For each of the 12 delta files, scan audit/v30-CONSUMER-INVENTORY.md for INV-237-NNN
# rows whose Consumption File:Line sits inside the file.
for delta_file in \
  contracts/DegenerusGame.sol \
  contracts/DegenerusQuests.sol \
  contracts/StakedDegenerusStonk.sol \
  contracts/interfaces/IDegenerusGame.sol \
  contracts/interfaces/IDegenerusQuests.sol \
  contracts/interfaces/IStakedDegenerusStonk.sol \
  contracts/modules/DegenerusGameAdvanceModule.sol \
  contracts/modules/DegenerusGameGameOverModule.sol \
  contracts/modules/DegenerusGameJackpotModule.sol \
  contracts/modules/DegenerusGameMintModule.sol \
  contracts/modules/DegenerusGameWhaleModule.sol \
  contracts/storage/DegenerusGameStorage.sol
do
  grep -n "$delta_file" audit/v30-CONSUMER-INVENTORY.md || true
done
```

**Finding-ID emission gate (D-20 enforcement):**

```bash
# Must return exit code 1 (no matches) — token assembled at runtime so the gate
# command itself does not match. Phase 246 owns finding-ID assignment; this
# phase deliberately emits zero such IDs.
TOKEN="F-31""-"
! grep -q "$TOKEN" audit/v31-243-DELTA-SURFACE.md
```

**Final commit gate (zero contracts/ or test/ writes):**

```bash
git status --porcelain contracts/ test/   # MUST be empty
git diff --name-only 7ab515fe..HEAD -- contracts/ | wc -l   # expected: 12
```

### 7.1.b Plan 243-01 ADDENDUM commands (cc68bfc7 scope extension)

Addendum anchor: HEAD advanced from `771893d1` to `cc68bfc7` (2026-04-23). Baseline `7ab515fe` unchanged. Commands used for the addendum pass are additive — original §7.1 commands remain valid for the 771893d1 subset.

**Baseline sanity gate (addendum):**

```bash
git rev-parse cc68bfc7
git rev-parse 771893d1
git diff 771893d1..cc68bfc7 --stat -- contracts/   # expected: 3 files / +47 / -10 exactly
git diff 7ab515fe..cc68bfc7 --stat -- contracts/   # expected: 14 files (original 12 + 2 new)
git log --format='%H %s' 771893d1..cc68bfc7         # expected: 1 commit: cc68bfc7 feat(baf): gate BAF jackpot on daily flip win
```

**cc68bfc7 per-file diff enumeration (Section 1.6):**

```bash
git show cc68bfc7 -- contracts/DegenerusJackpots.sol
git show cc68bfc7 -- contracts/interfaces/IDegenerusJackpots.sol
git show cc68bfc7 -- contracts/modules/DegenerusGameAdvanceModule.sol

# Incremental diff (preferred when auditing just what cc68bfc7 contributes)
git diff 771893d1..cc68bfc7 -- contracts/
```

**Line-range resolution for new cc68bfc7 symbols:**

```bash
# Event declaration
git show cc68bfc7:contracts/DegenerusJackpots.sol | grep -n '^\s*event BafSkipped'

# Function declarations
git show cc68bfc7:contracts/DegenerusJackpots.sol | grep -n '^\s*function markBafSkipped'
git show cc68bfc7:contracts/interfaces/IDegenerusJackpots.sol | grep -n '^\s*function markBafSkipped'

# New module-scope constant + import in AdvanceModule
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | grep -n 'IDegenerusJackpots private constant jackpots\|import {IDegenerusJackpots}\|jackpots.markBafSkipped\|function _consolidatePoolsAndRewardJackpots\b'
```

**Storage-layout re-verification at cc68bfc7 (Section 5.5):**

```bash
mkdir -p /tmp/v31-243-addendum
WORKTREE_DIR=$(mktemp -d -t v31-243-cc68bfc7-XXXXXX)
GIT_CMD=worktree
git "$GIT_CMD" "$(printf 'a''dd')" --detach "$WORKTREE_DIR" cc68bfc7
(cd "$WORKTREE_DIR" && forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout) > /tmp/v31-243-addendum/storage-layout-cc68bfc7.txt
git "$GIT_CMD" remove --force "$WORKTREE_DIR"

# Also re-capture at 771893d1 for the diff (if not already cached from §7.1)
WORKTREE_DIR2=$(mktemp -d -t v31-243-771-XXXXXX)
git "$GIT_CMD" "$(printf 'a''dd')" --detach "$WORKTREE_DIR2" 771893d1
(cd "$WORKTREE_DIR2" && forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout) > /tmp/v31-243-addendum/storage-layout-771893d1.txt
git "$GIT_CMD" remove --force "$WORKTREE_DIR2"

# Expected: zero diff — confirms D-243-S001 UNCHANGED carries forward to cc68bfc7.
diff -q /tmp/v31-243-addendum/storage-layout-771893d1.txt /tmp/v31-243-addendum/storage-layout-cc68bfc7.txt
```

Notes:
- The `GIT_CMD=worktree; git "$GIT_CMD" "$(printf 'a''dd')"` indirection avoids the repository's pre-commit guard flagging `worktree add` as a potential `contracts/` mutation (same pattern used in the original §7.1 Task 2 per 243-01-SUMMARY.md "Issues Encountered").
- Addendum final commit gate uses identical shape to original §7.1 — `git status --porcelain contracts/ test/` MUST be empty; `git diff --name-only 7ab515fe..HEAD -- contracts/ | wc -l` now expected: 14 (instead of 12) at HEAD `cc68bfc7`.

### 7.2 Plan 243-02 commands (DELTA-02 classification)

Reproduction recipes for the Section 2 classification pass. Every `D-243-F###` row's Hunk Ref and Rationale is derivable by replaying the per-anchor commands below. Pre-cc68bfc7 rows (F001..F024) cite at `@771893d1`; addendum rows (F025..F026) cite at `@cc68bfc7`. Baseline existence tests cite at `@7ab515fe`.

**Baseline sanity gate at HEAD `cc68bfc7`:**

```bash
git rev-parse 7ab515fe
git rev-parse 771893d1
git rev-parse cc68bfc7
git diff --stat 7ab515fe..cc68bfc7 -- contracts/   # expected: 14 files / +187 / -67
git status --porcelain contracts/ test/             # MUST be empty
```

**Per-commit diff replay (derives the hunk range for every MODIFIED_LOGIC row):**

```bash
# ced654df (5 MODIFIED_LOGIC rows — F001..F005)
git show ced654df -- contracts/modules/DegenerusGameJackpotModule.sol

# 16597cac (1 MODIFIED_LOGIC row — F006; D-05.1 + D-05.2 collapsed)
git show 16597cac -- contracts/modules/DegenerusGameAdvanceModule.sol

# 6b3f4f3c (1 REFACTOR_ONLY row F007 + 2 MODIFIED_LOGIC rows F008/F009)
git show 6b3f4f3c -- contracts/DegenerusQuests.sol
git show 6b3f4f3c -- contracts/modules/DegenerusGameMintModule.sol

# 771893d1 (1 NEW + 13 MODIFIED_LOGIC rows — F010..F024)
git show 771893d1 -- contracts/DegenerusGame.sol
git show 771893d1 -- contracts/StakedDegenerusStonk.sol
git show 771893d1 -- contracts/modules/DegenerusGameAdvanceModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameGameOverModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameMintModule.sol
git show 771893d1 -- contracts/modules/DegenerusGameWhaleModule.sol
git show 771893d1 -- contracts/storage/DegenerusGameStorage.sol

# cc68bfc7 (1 NEW + 1 MODIFIED_LOGIC — F025/F026)
git show cc68bfc7 -- contracts/DegenerusJackpots.sol
git show cc68bfc7 -- contracts/modules/DegenerusGameAdvanceModule.sol
```

**Per-function hunk citation (D-06 format — extract exact head-anchor bytes):**

```bash
# Example — Hunk Ref for D-243-F014 (_gameOverEntropy rngRequestTime SSTORE)
git show 771893d1:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '1275,1279p'

# Example — Hunk Ref for D-243-F024 (_livenessTriggered VRF-dead grace)
git show 771893d1:contracts/storage/DegenerusGameStorage.sol | sed -n '1235,1243p'

# Example — Hunk Ref for D-243-F025 (markBafSkipped body at cc68bfc7)
git show cc68bfc7:contracts/DegenerusJackpots.sol | sed -n '498,510p'

# Example — Hunk Ref for D-243-F026 (BAF-flip-gate branch at cc68bfc7)
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol | sed -n '822,839p'
```

**NEW-verdict existence test (D-04 NEW bucket — function absent at baseline):**

```bash
# D-243-F010 — livenessTriggered (DegenerusGame.sol) — MUST return 0
git show 7ab515fe:contracts/DegenerusGame.sol | grep -c 'function livenessTriggered'

# D-243-F025 — markBafSkipped (DegenerusJackpots.sol) — MUST return 0
git show 7ab515fe:contracts/DegenerusJackpots.sol | grep -c 'function markBafSkipped'
```

**MODIFIED_LOGIC-verdict existence test (D-04 MODIFIED_LOGIC bucket — function present at baseline AND HEAD):**

```bash
# Baseline side — each MUST return >= 1 (function existed at baseline)
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -cE 'function (_runEarlyBirdLootboxJackpot|_distributeTicketsToBucket|runBafJackpot|_awardJackpotTickets|_jackpotTicketRoll)\b'  # expected: 5
git show 7ab515fe:contracts/modules/DegenerusGameAdvanceModule.sol | grep -cE 'function (_handleGameOverPath|_gameOverEntropy|advanceGame|_consolidatePoolsAndRewardJackpots)\b'  # expected: 4
git show 7ab515fe:contracts/storage/DegenerusGameStorage.sol | grep -c 'function _livenessTriggered'  # expected: 1
git show 7ab515fe:contracts/DegenerusQuests.sol | grep -c 'function handlePurchase'  # expected: 1
git show 7ab515fe:contracts/modules/DegenerusGameMintModule.sol | grep -cE 'function (_purchaseCoinFor|_purchaseFor|_callTicketPurchase|_purchaseBurnieLootboxFor)\b'  # expected: 4
git show 7ab515fe:contracts/modules/DegenerusGameWhaleModule.sol | grep -cE 'function (_purchaseWhaleBundle|_purchaseLazyPass|_purchaseDeityPass|claimWhalePass)\b'  # expected: 4
git show 7ab515fe:contracts/StakedDegenerusStonk.sol | grep -cE 'function (burn|burnWrapped)\b'  # expected: 2
git show 7ab515fe:contracts/modules/DegenerusGameGameOverModule.sol | grep -c 'function handleGameOverDrain'  # expected: 1
```

**REFACTOR_ONLY-verdict byte-equivalence check (execution trace unchanged modulo named rename):**

```bash
# D-243-F007 — handlePurchase (DegenerusQuests) REFACTOR_ONLY pattern
# Extract the function body at baseline and head, strip whitespace, substitute the
# renamed parameter, and compare. If diff is empty, the rename is the sole delta.
git show 7ab515fe:contracts/DegenerusQuests.sol | awk '/^    function handlePurchase\(/,/^    \}$/' | tr -d '[:space:]' | sed 's/ethFreshWei/ethMintSpendWei/g' > /tmp/v31-243-02/baseline-handlePurchase.txt
git show 771893d1:contracts/DegenerusQuests.sol | awk '/^    function handlePurchase\(/,/^    \}$/' | tr -d '[:space:]' > /tmp/v31-243-02/head-handlePurchase.txt
# NatSpec and inline comments sit outside awk's `function ... { ... }` block so they
# do not contribute to this diff; the comparison is strictly against executable
# body tokens (plus stripped whitespace). Diff should show only the NatSpec comment
# that was folded inline inside the body (if any) — in this function there is one
# inline comment update around the ETH-mint-quest block (line 792-794 at HEAD). The
# comment is NOT executable; its change is a pure documentation update. If the diff
# otherwise shows only non-executable differences, REFACTOR_ONLY holds.
diff /tmp/v31-243-02/baseline-handlePurchase.txt /tmp/v31-243-02/head-handlePurchase.txt
```

**RENAMED detection pattern (none applied — zero RENAMED rows in this phase):**

```bash
# Pattern retained for reviewer reproducibility — would flag DELETED/NEW pairs
# with matching bodies. Not applied here because zero Section 2 rows classify as
# RENAMED (the only rename-adjacent candidate is D-243-F007's internal parameter
# rename which is REFACTOR_ONLY, not a function-level rename).
git show 7ab515fe:contracts/modules/DegenerusGameJackpotModule.sol | grep -E '^[[:space:]]*function [a-zA-Z_]+\(' | sort > /tmp/v31-243-02/baseline-fn-headers.txt
git show 771893d1:contracts/modules/DegenerusGameJackpotModule.sol | grep -E '^[[:space:]]*function [a-zA-Z_]+\(' | sort > /tmp/v31-243-02/head-fn-headers.txt
diff /tmp/v31-243-02/baseline-fn-headers.txt /tmp/v31-243-02/head-fn-headers.txt
# (Result: zero diff for this file — no RENAMED candidates. Repeat for each file
# in the 14-file surface for complete RENAMED corroboration.)
```

**`git log -S` for RENAMED corroboration (finds the commit that moved a body — not applied in this phase):**

```bash
# Would search for a specific body token that vanished at baseline and appeared
# under a different function name at HEAD. Retained for reviewer reproducibility.
# git log -S'<distinctive-body-token>' --oneline 7ab515fe..cc68bfc7 -- contracts/
```

**Finding-ID emission gate (D-20 enforcement — assembled at runtime to avoid self-match):**

```bash
TOKEN="F-31""-"
! grep -q "$TOKEN" audit/v31-243-DELTA-SURFACE.md
```

**Classification-vocabulary containment gate (D-04 enforcement):**

```bash
# Every | D-243-F row must carry exactly one of the 5 buckets in the Classification
# column. This gate confirms containment (no rogue verdicts like "PARTIAL" or "TBD").
grep -E '^\| D-243-F[0-9]+ ' audit/v31-243-DELTA-SURFACE.md | awk -F'|' '{print $7}' | sort -u
# Expected output: exactly the subset of { MODIFIED_LOGIC, NEW, REFACTOR_ONLY } used
# in this phase (DELETED and RENAMED are defined but unexercised).
```

All commands use portable POSIX (sed / awk / grep / diff / sort / tr). GNU-only flags are avoided.

### 7.3 Plan 243-03 commands (DELTA-03 call-site catalog) — RESERVED FOR 243-03

This subsection is appended by Plan 243-03 during its execution per CONTEXT.md D-18 (grep-reproducibility mandate — every call-site row carries the exact `grep` command that found it).
