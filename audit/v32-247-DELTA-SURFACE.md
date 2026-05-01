---
status: IN_PROGRESS — Plan 247-01 single-plan multi-task
phase: 247 — Delta Extraction & Classification
milestone: v32.0 Backfill Idempotency + purchaseLevel Underflow Audit
baseline: cc68bfc7
head: acd88512
plan: 247-01
---

# v32.0 Phase 247 — Delta Surface Catalog

**Audit baseline:** `cc68bfc7` (v31.0 milestone HEAD; tag `v31.0`).
**Audit head:** `acd88512` (current contract-tree HEAD; latest contract-touching commit at planning time 2026-04-30).
**Phase:** 247 — Delta Extraction & Classification (DELTA-01 / DELTA-02 / DELTA-03).
**Scope:** READ-only-LIFTED at milestone level but Phase 247 is pure-catalog per D-247-05; zero `contracts/` or `test/` writes.
**Status:** IN PROGRESS — Plan 247-01 Task 1 populates Sections 0 / 1 / 4 / 5 / 7.1. Sections 2 / 3 / 6 are placeholder stubs reserved for Tasks 2 / 3 / 4 of the same plan. Task 5 flips this file to FINAL READ-only.

## Section 0 — Overview & Row-ID Legend

### 0.1 Overview

This file is the authoritative v32.0 audit-surface catalog covering the 4 post-v31.0 contract-touching commits between baseline `cc68bfc7` and head `acd88512`, plus 1 enumerated-but-out-of-scope test-only commit `ad41973c`. It is the SOLE scope input for Phases 248 (BFL Backfill Idempotency Proof), 249 (PLV purchaseLevel Correctness Proof), 250 (SIB Sibling-Pattern Sweep), 251 (TST Reproduction Tests — owns test/ but consumes Phase 247 contract classification), 252 (POST31 Landed-Commit Sanity), and 253 (FIND Findings Consolidation + REG Lean Regression), per ROADMAP Phase 247 Success Criterion 4.

**4-commit aggregate (from `git diff --stat cc68bfc7..acd88512 -- contracts/`):** 4 files changed, 47 insertions(+), 77 deletions(-). Net trim of 30 lines driven by the `48554f8f` Vault refactor (`+17 / -66`).

**Reproducibility:** Every row in this file is derived from a documented `git diff` / `git show` / `forge inspect` / `grep` command. All commands are consolidated in Section 7 for reviewer replay using portable POSIX syntax.

### 0.2 Row-ID Legend (per CONTEXT.md D-247-11)

| Prefix | Section | Purpose | Owning Task |
|---|---|---|---|
| `D-247-C###` | Section 1 (per-source changelog) + Section 4 (state/event/interface/error inventory) | One row per changed symbol (function / state-var / event / error / interface method) across the 4 in-scope SHAs | Task 1 |
| `D-247-F###` | Section 2 (aggregate function classification) | One row per changed function with D-247-06 5-bucket classification + hunk citation + rationale | Task 2 |
| `D-247-S###` | Section 5 (storage slot layout diff) | One row per `DegenerusGameStorage.sol` slot that changed label / offset / type / size between baseline and head | Task 1 |
| `D-247-X###` | Section 3 (downstream call-site catalog) | One row per call site of each changed function / changed interface method discovered via `grep` across `contracts/` | Task 3 |
| `D-247-I###` | Section 6 (Consumer Index) | One row per Phase 248..253 REQ-ID mapping to the subset of 247 Row IDs scoped under it | Task 4 |

Row IDs are monotonic zero-padded three-digit integers within each prefix. `D-247-C###` numbering crosses Sections 1 → 4 contiguously (Section 1 first, then Section 4 continues the sequence).

### 0.3 Source Inventory

Per-commit file attribution VERIFIED via `git show {sha} --stat -- contracts/` at planning time 2026-04-30. Per-commit file targets are git ground truth; the function-scope semantic impact may span more files than the diff itself touches (e.g., `8bdeabc2`'s `_livenessTriggered` modification lives in `contracts/storage/DegenerusGameStorage.sol` — the diff target — even though it gates execution paths inside several modules at call-time).

| Chrono Order | SHA (full) | Subject | Files Touched in contracts/ | Insertions | Deletions | In-Scope? | Role |
|---|---|---|---|---|---|---|---|
| 1 | `8bdeabc2599c889c849c0fbd3e816cd42f08763e` | fix(liveness): pause death clock during productive multi-call window | 1 (DegenerusGameStorage.sol) | 12 | 0 | YES | POST31-02 RE_VERIFY anchor |
| 2 | `ad41973ca6ffc7447aeb1cf44e8098145dfb78ae` | test(liveness): cover productive-phase pause regression at unit + integration | 0 (test/ only) | 0 | 0 | NO (D-247-02; Phase 251) | Phase 251 TST scope handoff |
| 3 | `6a63705b196cb94967c05a2b67b12f57584ed99c` | fix(mint): charge buyer not operator for purchaseCoin tickets | 1 (DegenerusGameMintModule.sol) | 3 | 6 | YES | POST31-01 sanity-anchor |
| 4 | `48554f8f350a5c10cbb4954a41eda652dff9253c` | refactor(vault): decouple share redemption from game operator approval | 1 (DegenerusVault.sol) | 17 | 66 | YES | POST31-01 sanity-anchor |
| 5 | `acd88512c516bef51981d8b6f49de9878aba9159` | fix(advance): guard turbo block + make _backfillGapDays idempotent | 1 (DegenerusGameAdvanceModule.sol) | 15 | 5 | YES | BFL-01..06 + PLV-01..06 + SIB-01..05 anchor |
| **In-scope total** | — | 4 commits | **4 distinct files (union)** | **47** | **77** | — | — |

Note: `b02078d8` (`chore: remove REQUIREMENTS.md for v31.0 milestone`), `1ef9d846` (`chore: archive v31.0 milestone files`), and the v32.0-startup docs commits `e5baa881` / `15b075b5` / `0b3b4951` sit between `cc68bfc7` and `acd88512` but touch only `.planning/` — invisible to `git diff cc68bfc7..acd88512 -- contracts/`. NOT enumerated here per D-247-02 contracts/-only scope. The `036e920a` docs HEAD above `acd88512` similarly touches only `.planning/STATE.md` and is invisible to the contracts/-filtered diff.

## Section 1 — Per-Source Changelog

Per CONTEXT.md D-247-10 columns: `Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note`.

- **Row ID:** `D-247-C###` zero-padded, monotonic across Section 1 → Section 4.
- **Commit SHA:** short 8-char prefix.
- **File:Line-Range:** `contracts/<path>:<start>-<end>` at HEAD for MODIFIED/NEW rows; baseline range for DELETED rows.
- **Symbol Kind:** one of `func`, `modifier`, `state`, `event`, `error`, `interface-method`, `constant`, `import`, `none (test-only)`.
- **Symbol Name:** function/state-var/event/interface-method identifier (NOT full signature — full signature goes in Section 2 / Section 4 columns).
- **Change Type (per-source scope — coarser than D-247-06 classification):** one of `ADDED`, `REMOVED`, `MODIFIED`, `SIGNATURE-CHANGED`, `NATSPEC-ONLY`, `NO_CHANGE (test-only)`. The fine-grained D-247-06 5-bucket verdict (NEW / MODIFIED_LOGIC / REFACTOR_ONLY / DELETED / RENAMED) is Task 2's job in Section 2.
- **One-Line Semantic Note:** ≤ 12 words — names the specific element that drives the row.

### 1.1 Commit 8bdeabc2 — fix(liveness): pause death clock during productive multi-call window

**Change count card:** functions: 1 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: TBD-Task-3.

Source command: `git show 8bdeabc2 -- contracts/storage/DegenerusGameStorage.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C001 | 8bdeabc2 | contracts/storage/DegenerusGameStorage.sol:1246-1255 | func | `_livenessTriggered` | MODIFIED | early-return short-circuit when lastPurchaseDay or jackpotPhaseFlag set |
| D-247-C002 | 8bdeabc2 | contracts/storage/DegenerusGameStorage.sol:1225-1234 | func | `_livenessTriggered` (NatSpec block above) | NATSPEC-ONLY | productive-phase pause NatSpec block expanded above _livenessTriggered |

### 1.2 Commit 6a63705b — fix(mint): charge buyer not operator for purchaseCoin tickets

**Change count card:** functions: 3 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: TBD-Task-3.

Source command: `git show 6a63705b -- contracts/modules/DegenerusGameMintModule.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C003 | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:1204-1370 | func | `_callTicketPurchase` | SIGNATURE-CHANGED | payer parameter dropped + 4 internal sites switch to buyer |
| D-247-C004 | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:885-910 | func | `_purchaseCoinFor` | MODIFIED | call-site at L895 drops `msg.sender,` payer arg |
| D-247-C005 | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:912-1196 | func | `_purchaseFor` | MODIFIED | call-site at L977 drops duplicate `buyer,` payer arg |

### 1.3 Commit 48554f8f — refactor(vault): decouple share redemption from game operator approval

**Change count card:** functions: 4 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 1 (REMOVED — `NotApproved`) / constants: 1 (REMOVED — `game`) / imports: 1 (MODIFIED — `IDegenerusGame` symbol dropped from import statement) / call-sites-changed: TBD-Task-3.

Source command: `git show 48554f8f -- contracts/DegenerusVault.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C006 | 48554f8f | contracts/DegenerusVault.sol:750-790 | func | `burnCoin` | SIGNATURE-CHANGED | address player param dropped; only redeems msg.sender shares |
| D-247-C007 | 48554f8f | contracts/DegenerusVault.sol:802-842 | func | `burnEth` | SIGNATURE-CHANGED | address player param dropped; only redeems msg.sender shares |
| D-247-C008 | 48554f8f | contracts/DegenerusVault.sol:777-817@cc68bfc7 | func | `_burnCoinFor` | REMOVED | private helper inlined into burnCoin (approval-check no longer needed) |
| D-247-C009 | 48554f8f | contracts/DegenerusVault.sol:848-891@cc68bfc7 | func | `_burnEthFor` | REMOVED | private helper inlined into burnEth (approval-check no longer needed) |
| D-247-C010 | 48554f8f | contracts/DegenerusVault.sol:444-448@cc68bfc7 | func | `_requireApproved` | REMOVED | game-operator approval helper no longer used |

### 1.4 Commit acd88512 — fix(advance): guard turbo block + make _backfillGapDays idempotent

**Change count card:** functions: 2 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: TBD-Task-3.

Source command: `git show acd88512 -- contracts/modules/DegenerusGameAdvanceModule.sol`.

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C011 | acd88512 | contracts/modules/DegenerusGameAdvanceModule.sol:160-488 | func | `advanceGame` | MODIFIED | turbo block at L173 gains `&& !rngLockedFlag` conjunctive guard + NatSpec |
| D-247-C012 | acd88512 | contracts/modules/DegenerusGameAdvanceModule.sol:1152-1224 | func | `rngGate` | MODIFIED | backfill branch at L1173 gains `&& rngWordByDay[idx + 1] == 0` conjunctive guard + NatSpec |

### 1.5 Commit ad41973c — test(liveness): cover productive-phase pause regression (test/ only — out of scope per D-247-02)

**Change count card:** functions: 0 / state-vars: 0 / events: 0 / interfaces: 0 / errors: 0 / call-sites-changed: 0.

Source command: `git show ad41973c --stat` (touches `test/edge/LivenessMidJackpot.test.js` +225 and `test/edge/LivenessProductivePause.test.js` +132 only; zero files in `contracts/`).

| Row ID | Commit SHA | File:Line-Range | Symbol Kind | Symbol Name | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C013 | ad41973c | (none — test/ only) | none (test-only) | (none) | NO_CHANGE (test-only) | Phase 251 TST scope; enumerated for completeness per D-247-02 |

### 1.6 Finding Candidates (fresh-eyes)

Per CONTEXT.md D-247-21: any symbol discovered during the fresh enumeration pass that looks potentially worth a Phase 253 finding gets flagged here. Zero finding IDs are emitted by this phase — Phase 253 owns ID assignment.

Format: bullet list — `- contracts/<path>:<line> — <symbol> — <rationale> — suggested severity: <INFO|LOW|MEDIUM|HIGH>`.

- contracts/storage/DegenerusGameStorage.sol:1246 — `_livenessTriggered` — early-return short-circuit when `lastPurchaseDay || jackpotPhaseFlag` returns false unconditionally during the productive window. The two flags clear at AdvanceModule:328-331 (per commit message). If those clears do not always happen on the same tick that the productive window ends, liveness gating could remain artificially suppressed for one extra tick. Phase 252 POST31-02 should sweep every code path that clears either flag and confirm pause/resume composition with the new `acd88512` `!rngLockedFlag` turbo guard — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:177 — `advanceGame` (turbo guard) — `!rngLockedFlag` conjunctive guard added so turbo no longer fires while the VRF lock is held. The fix closes the testnet `purchaseLevel = 0` panic (blocks 10759449 + 10761786) by routing through `_requestRng`'s level pre-increment in those windows. Phase 249 PLV-03 / PLV-05 should symbolically reproduce the panic against pre-fix code and confirm the new guard short-circuits the binding ternary at L185 — suggested severity: INFO
- contracts/modules/DegenerusGameAdvanceModule.sol:1173 — `rngGate` (backfill guard) — `rngWordByDay[idx + 1] == 0` conjunctive guard added so `_backfillGapDays` runs at most once per VRF lock window. The chosen sentinel index is `idx + 1`; off-by-one risk if `dailyIdx` and `day` ever go out of sync vs. expected invariant. Phase 248 BFL-02 / BFL-04 should prove `rngWordByDay[idx + 1]` is the correct sentinel and that `dailyIdx` only advances inside `_unlockRng` — suggested severity: INFO
- contracts/modules/DegenerusGameMintModule.sol:1204 — `_callTicketPurchase` — `payer` parameter dropped; the 4 internal call-sites (`consumePurchaseBoost(buyer)`, `_coinReceive(buyer, ...)`, `recordMint(buyer, ...)` x2) now charge `buyer` instead of `msg.sender`. The 2 callers (`_purchaseCoinFor` at L895 and `_purchaseFor` at L977) drop their `msg.sender` / duplicate `buyer` arg accordingly. Phase 250 SIB-03 should confirm no remaining `msg.sender` charge in any other BURNIE-spending site — suggested severity: INFO
- contracts/DegenerusVault.sol:750 / :802 — `burnCoin` / `burnEth` — operator-approval gate removed; redemption now only redeems `msg.sender`'s own shares. Vault holders are now insulated from any game-side operator delegation grief. Confirm via Phase 252 POST31-01 that no game-side caller (e.g., a future module) was relying on the cross-contract approval system to liquidate vault positions on behalf of others — none expected per commit message but Phase 250 SIB-03 cross-module sweep should verify — suggested severity: INFO
- contracts/DegenerusVault.sol — `IDegenerusGame` import drop + `game` constant removal — the only consumer of the `game` constant was `_requireApproved` (now deleted). If any other Vault function transitively consumed any `game.NAME(...)` method via inheritance or unrelated call paths, removing the import would break compilation; the fact that the commit lands cleanly indicates `_requireApproved` was the sole consumer. Phase 252 POST31-01 should confirm via grep that zero remaining `game.` references exist in `contracts/DegenerusVault.sol` at HEAD — suggested severity: INFO

### 1.7 Light Reconciliation Against audit/v31-243-DELTA-SURFACE.md

Per CONTEXT.md D-247-18: cross-check any v31 row whose underlying function is touched by v32 deltas. Narrower than Phase 237's full prior-artifact cross-check because v31.0 was already a complete delta audit at `cc68bfc7`.

| v31 Row ID (D-243-C###) | v31 Function | v32 Touched-By Commit | v32 Section 1 Row(s) | Reconciliation Verdict |
|---|---|---|---|---|
| D-243-C026 | `_livenessTriggered` (DegenerusGameStorage.sol:1235-1243@v31) | 8bdeabc2 | D-247-C001 + D-247-C002 | confirmed-delta-touches-v31-row — productive-phase early-return added on top of v31 D-243-C026's day-math-first reorder + 14-day VRF-dead grace fallback. Phase 252 POST31-02 composes both verdicts (productive-pause pre-empts day-math/grace fallback when either productive-flag is set). |
| D-243-C007 | `advanceGame` (AdvanceModule:156-480@v31) | acd88512 | D-247-C011 | confirmed-delta-touches-v31-row — `acd88512` adds `&& !rngLockedFlag` to turbo guard at L173 on top of v31 D-243-C007's `_unlockRng(day)` removal hunk + multi-line preIdx reformat. Different hunks (turbo at L164-176 vs preIdx at v31 L257-260 / unlock at v31 L450), but same function. Phase 248 BFL-01..06 + Phase 249 PLV-01..06 inherit both v31 + v32 verdicts. |
| D-243-C011 | `_callTicketPurchase` (MintModule:1206-1373@v31) | 6a63705b | D-247-C003 | confirmed-delta-touches-v31-row — `6a63705b` drops the `payer` parameter (signature change) and switches 4 internal call-sites from `payer` to `buyer` on top of v31 D-243-C011's freshEth return-tuple shrink (5-tuple → 4-tuple) and v31 D-243-C020's gameOver→_livenessTriggered gate swap. Three independent hunks across two milestones; Phase 250 SIB-04 should compose all three. |
| D-243-C010 | `_purchaseFor` (MintModule:913-1198@v31) | 6a63705b | D-247-C005 | confirmed-delta-touches-v31-row — `6a63705b` drops the duplicate `buyer,` arg at the `_callTicketPurchase` call-site (L977) on top of v31 D-243-C010's MINT_ETH gross-spend value-semantics shift + v31 D-243-C019's gameOver→_livenessTriggered gate swap at function prologue. Phase 250 SIB-04 inherits the call-site-vs-function-prologue interaction. |
| D-243-C018 | `_purchaseCoinFor` (MintModule:885-911@v31) | 6a63705b | D-247-C004 | confirmed-delta-touches-v31-row — `6a63705b` drops the `msg.sender,` arg at the `_callTicketPurchase` call-site (L895) on top of v31 D-243-C018's gameOver→_livenessTriggered gate swap (1 of 8 paths). Phase 250 SIB-04 should verify the buyer-vs-operator semantics now consistently apply across the gate-swap path. |
| (no v31 row) | `burnCoin` / `burnEth` / `_burnCoinFor` / `_burnEthFor` / `_requireApproved` (DegenerusVault.sol) | 48554f8f | D-247-C006..C010 | no-overlap — `DegenerusVault.sol` was NOT in v31's 12-file delta surface (v31 §1.4 `771893d1` touched `StakedDegenerusStonk.sol` for sDGNRS-redemption protection but not `DegenerusVault.sol` directly). `48554f8f` is the FIRST v31-baseline-relative touch of Vault. Phase 250 SIB-03 / Phase 252 POST31-01 establish the v32-only baseline. |
| (no v31 row) | `rngGate` / `_backfillGapDays` (AdvanceModule) | acd88512 | D-247-C012 | no-overlap — `rngGate` body was NOT delta-touched in v31 (v31 D-243-C007 only touched `advanceGame`); `_backfillGapDays` was never delta-touched in any prior milestone. `acd88512` is the FIRST delta against `rngGate`'s backfill branch and the first cross-cite to `_backfillGapDays` since the v3.6 VRF-stall-resilience milestone (Phases 59-62). Phase 248 BFL-01..06 establishes the v32-only baseline. |

5 confirmed-delta-touches-v31-row entries (4 unique v31 row IDs spanning 5 v32 row mappings — `_callTicketPurchase` overlaps v31 in two distinct rows D-243-C011 and D-243-C020 but maps to a single v32 row D-247-C003). 2 no-overlap clusters covering Vault redemption (5 v32 rows) and `rngGate`/`_backfillGapDays` (1 v32 row).

## Section 2 — Aggregate Function Classification

Per CONTEXT.md D-247-06 5-bucket rubric: every `func` row in Section 1 receives one of {NEW / MODIFIED_LOGIC / REFACTOR_ONLY / DELETED / RENAMED}. Per D-247-08, every row cites a real diff hunk via `file:line-range` AND a one-line rationale per D-247-20 naming the specific execution-trace-changing element (SSTORE / external call / branch / emit / return-path / arithmetic operand) OR the specific non-execution-changing element (whitespace / rename / multi-line split). Pre-locked verdicts from D-247-07 are honored as floor.

**Universe size:** 11 func rows from Section 1 (§1.1 = 1, §1.2 = 3, §1.3 = 5, §1.4 = 2; §1.5 ad41973c emits zero func rows; Section 1's NATSPEC-ONLY row D-247-C002 is not a separate function — it is the same `_livenessTriggered` symbol carrying the NatSpec block, classified once under D-247-F001 and not double-counted here).

Columns per CONTEXT.md D-247-10: `Row ID | Section 1 Row | Function Signature | Commit | File:Line (at HEAD) | Classification | Hunk Ref | One-Line Rationale`. Hunk Ref column embeds the HEAD anchor as an `@sha` suffix (using either `@acd88512` for HEAD-side rows or `@cc68bfc7` for DELETED rows whose body lives only at baseline) so reviewers can replay `git show <sha> -L <start>,<end>:<path>` directly per D-247-20.

| Row ID | Section 1 Row | Function Signature | Commit | File:Line (at HEAD) | Classification | Hunk Ref | One-Line Rationale |
|---|---|---|---|---|---|---|---|
| D-247-F001 | D-247-C001 + D-247-C002 | `function _livenessTriggered() internal view returns (bool)` (DegenerusGameStorage) | 8bdeabc2 | contracts/storage/DegenerusGameStorage.sol:1246-1255 | MODIFIED_LOGIC | contracts/storage/DegenerusGameStorage.sol:1246-1247@acd88512 (`git show 8bdeabc2 -L 1246,1247:contracts/storage/DegenerusGameStorage.sol`) | D-247-07 floor: new early-return branch `if (lastPurchaseDay \|\| jackpotPhaseFlag) return false;` short-circuits the death clock during the productive multi-call window — control-flow branch added (D-247-20 branch + return-path elements) |
| D-247-F002 | D-247-C003 | `function _callTicketPurchase(address buyer, uint256 quantity, MintPaymentKind payKind, bool payInCoin, ...) private returns (uint256, uint256, uint32, uint24, uint32)` (DegenerusGameMintModule) | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:1204-1370 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:1206,1252,1268,1279@acd88512 (`git show 6a63705b -L 1200,1290:contracts/modules/DegenerusGameMintModule.sol`) | D-247-07 floor: signature change drops `address payer` parameter (5-arg → 4-arg); 4 internal call-site arg swaps — `consumePurchaseBoost(payer→buyer)` at L1252, `_coinReceive(payer→buyer)` at L1268, `recordMint(payer→buyer)` at L1279 — all charge `buyer` instead of operator (D-247-20 external-call target element) |
| D-247-F003 | D-247-C004 | `function _purchaseCoinFor(address buyer, uint256 ticketQuantity, ...) private` (DegenerusGameMintModule) | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:885-910 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:894-902@acd88512 (`git show 6a63705b -L 894,902:contracts/modules/DegenerusGameMintModule.sol`) | D-247-07 floor: argument-list change at `_callTicketPurchase` call site — `msg.sender,` payer arg dropped at L897 (was line 897 pre-fix) so the BURNIE/quest charge target swaps from operator to buyer (D-247-20 external-call/internal-call argument-list element) |
| D-247-F004 | D-247-C005 | `function _purchaseFor(address buyer, address ticketRecipient, uint256 ticketQuantity, ...) private` (DegenerusGameMintModule) | 6a63705b | contracts/modules/DegenerusGameMintModule.sol:912-1196 | MODIFIED_LOGIC | contracts/modules/DegenerusGameMintModule.sol:975-983@acd88512 (`git show 6a63705b -L 975,983:contracts/modules/DegenerusGameMintModule.sol`) | D-247-07 floor: argument-list change at `_callTicketPurchase` call site — duplicate `buyer,` payer arg dropped (the call now passes `buyer` exactly once) so the destructured 5-tuple `(..., burnieMintUnits) = _callTicketPurchase(buyer, ticketQuantity, payKind, ...)` has its arity reduced 1 (D-247-20 internal-call argument-list element) |
| D-247-F005 | D-247-C006 | `function burnCoin(uint256 amount) external returns (uint256 coinOut)` (DegenerusVault) | 48554f8f | contracts/DegenerusVault.sol:750-790 | MODIFIED_LOGIC | contracts/DegenerusVault.sol:750-790@acd88512 vs contracts/DegenerusVault.sol:764-817@cc68bfc7 (`git show 48554f8f -L 750,790:contracts/DegenerusVault.sol`) | D-247-07 floor: signature change drops `address player` param (1-arg now); the public wrapper's `if (player == address(0)) ... else if (player != msg.sender) _requireApproved(player); return _burnCoinFor(player, amount);` 4-line dispatch is removed and the helper body is inlined with `player` → `msg.sender` substitution. Operator-approval `_requireApproved` revert path removed; emit and 4 transfer call sites all retarget from `player` to `msg.sender` (D-247-20 control-flow branch + external-call target elements) |
| D-247-F006 | D-247-C007 | `function burnEth(uint256 amount) external returns (uint256 ethOut, uint256 stEthOut)` (DegenerusVault) | 48554f8f | contracts/DegenerusVault.sol:802-842 | MODIFIED_LOGIC | contracts/DegenerusVault.sol:802-842@acd88512 vs contracts/DegenerusVault.sol:831-891@cc68bfc7 (`git show 48554f8f -L 802,842:contracts/DegenerusVault.sol`) | D-247-07 floor: same shape as F005 — signature drops `address player`, 4-line public wrapper dispatch + `_requireApproved(player)` gate removed, helper body inlined with `player` → `msg.sender`. `_paySteth(player, ...)` and `_payEth(player, ...)` both retarget to `msg.sender` (D-247-20 control-flow branch + external-call target elements) |
| D-247-F007 | D-247-C008 | `function _burnCoinFor(address player, uint256 amount) private returns (uint256 coinOut)` (DegenerusVault — baseline-only) | 48554f8f | (none — absent at HEAD; lived at contracts/DegenerusVault.sol:777-817@cc68bfc7) | DELETED | contracts/DegenerusVault.sol:777-817@cc68bfc7 (`git show cc68bfc7 -L 777,817:contracts/DegenerusVault.sol`) | D-247-07 floor: helper existed at baseline as a private function with its own header/closing-brace; absent at HEAD. The body content is preserved inside `burnCoin` at HEAD (with `player` → `msg.sender` substitution), but the function-as-symbol is gone — `git show acd88512:contracts/DegenerusVault.sol \| grep -c '^\s*function _burnCoinFor'` returns 0. Per D-247-06 the function-level verdict is DELETED; the body-preservation fact is captured in F005's rationale. |
| D-247-F008 | D-247-C009 | `function _burnEthFor(address player, uint256 amount) private returns (uint256 ethOut, uint256 stEthOut)` (DegenerusVault — baseline-only) | 48554f8f | (none — absent at HEAD; lived at contracts/DegenerusVault.sol:848-891@cc68bfc7) | DELETED | contracts/DegenerusVault.sol:848-891@cc68bfc7 (`git show cc68bfc7 -L 848,891:contracts/DegenerusVault.sol`) | D-247-07 floor: same shape as F007 — helper existed at baseline as a private function with its own header/closing-brace; absent at HEAD; body-preserved inside `burnEth` with `player` → `msg.sender` substitution. `git show acd88512:contracts/DegenerusVault.sol \| grep -c '^\s*function _burnEthFor'` returns 0 — function-as-symbol DELETED. |
| D-247-F009 | D-247-C010 | `function _requireApproved(address player) private view` (DegenerusVault — baseline-only) | 48554f8f | (none — absent at HEAD; lived at contracts/DegenerusVault.sol:444-448@cc68bfc7) | DELETED | contracts/DegenerusVault.sol:444-448@cc68bfc7 (`git show cc68bfc7 -L 444,448:contracts/DegenerusVault.sol`) | D-247-07 floor: helper removed; no caller at HEAD (the 2 baseline call sites at burnCoin / burnEth public-wrapper dispatch were removed alongside in F005 / F006). `git show acd88512:contracts/DegenerusVault.sol \| grep -c '^\s*function _requireApproved'` returns 0 — function fully eliminated. |
| D-247-F010 | D-247-C011 | `function advanceGame() external` (DegenerusGameAdvanceModule) | acd88512 | contracts/modules/DegenerusGameAdvanceModule.sol:160-488 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:167-176@acd88512 (`git show acd88512 -L 160,180:contracts/modules/DegenerusGameAdvanceModule.sol`) | D-247-07 floor: turbo block `if (!inJackpot && !lastPurchaseDay)` gains conjunctive guard `&& !rngLockedFlag` at L173 — new control-flow branch (turbo no longer fires when VRF lock is held, preventing the missed level pre-increment that triggered testnet panic 0x11 at blocks 10759449 + 10761786). NatSpec block at L167-172 expanded to document the rationale (D-247-20 branch element) |
| D-247-F011 | D-247-C012 | `function rngGate(uint256 currentWord, bool bonusFlip) internal returns (...)` (DegenerusGameAdvanceModule) | acd88512 | contracts/modules/DegenerusGameAdvanceModule.sol:1152-1224 | MODIFIED_LOGIC | contracts/modules/DegenerusGameAdvanceModule.sol:1166-1175@acd88512 (`git show acd88512 -L 1160,1180:contracts/modules/DegenerusGameAdvanceModule.sol`) | D-247-07 floor: backfill branch entry guard `if (day > idx + 1)` gains conjunctive guard `&& rngWordByDay[idx + 1] == 0` at L1173 — new control-flow branch (the `_backfillGapDays` call now runs at most once per VRF lock window since `dailyIdx` only advances inside `_unlockRng`; multi-day stalls no longer doubly-credit `purchaseStartDay` or re-run resolved coinflip payouts). NatSpec block at L1166-1172 expanded to document the rationale (D-247-20 branch element + new SLOAD on rngWordByDay[idx + 1]) |

### 2.1 Classification distribution (count card)

| Verdict | Count | Function List |
|---|---|---|
| NEW | 0 | — (no Section 1 row is absent at baseline; every changed function existed at `cc68bfc7`) |
| MODIFIED_LOGIC | 8 | D-247-F001 (`_livenessTriggered`), D-247-F002 (`_callTicketPurchase`), D-247-F003 (`_purchaseCoinFor`), D-247-F004 (`_purchaseFor`), D-247-F005 (`burnCoin`), D-247-F006 (`burnEth`), D-247-F010 (`advanceGame`), D-247-F011 (`rngGate`) |
| REFACTOR_ONLY | 0 | — (no func row classified as pure non-execution-trace-changing; the 11 NatSpec lines from `8bdeabc2` and the NatSpec expansions from `acd88512` are subordinate to the in-same-function MODIFIED_LOGIC verdicts and not counted as separate REFACTOR_ONLY rows per D-247-06) |
| DELETED | 3 | D-247-F007 (`_burnCoinFor`), D-247-F008 (`_burnEthFor`), D-247-F009 (`_requireApproved`) |
| RENAMED | 0 | — (no Section 1 func row identified as a pure rename; the closest candidate is the `_burnCoinFor` body re-appearing as `burnCoin` body, but the rename is paired with a signature change AND a control-flow gate removal, so per D-247-06 burden of proof the verdict for the disappearing helper is DELETED and for the public wrapper is MODIFIED_LOGIC) |
| **Total** | **11** | matches universe size of 11 func rows from Section 1 (1.1 = 1 / 1.2 = 3 / 1.3 = 5 / 1.4 = 2). NatSpec-only row D-247-C002 collapsed into D-247-F001 per Section 2 universe-construction note above. |

**Sanity:** MODIFIED_LOGIC count = 8 (recount: F001, F002, F003, F004, F005, F006, F010, F011 = 8) + DELETED count = 3 (F007, F008, F009) = 11 = Section 1 func universe size. NEW = REFACTOR_ONLY = RENAMED = 0.

### 2.2 D-247-07 Pre-Locked Floor Compliance Attestation

All 7 pre-locked CONTEXT.md D-247-07 verdicts were applied verbatim with zero deviations:

| D-247-07 Floor | Applied In Row | Floor Verdict | Applied Verdict | Match |
|---|---|---|---|---|
| acd88512 turbo guard at L173 (inside `advanceGame`) | D-247-F010 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| acd88512 backfill guard at L1173 (inside `rngGate`) | D-247-F011 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| 8bdeabc2 `_livenessTriggered` productive-pause | D-247-F001 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| 6a63705b `_callTicketPurchase` charge swap | D-247-F002 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| 6a63705b callers of `_callTicketPurchase` (the 2 sites that drop the duplicate arg) | D-247-F003 + D-247-F004 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| 48554f8f Vault `burnCoin` / `burnEth` operator-approval gate removal | D-247-F005 + D-247-F006 | MODIFIED_LOGIC | MODIFIED_LOGIC | ✓ |
| 48554f8f Vault `_burnCoinFor` / `_burnEthFor` (per-row) | D-247-F007 + D-247-F008 | DELETED (or REFACTOR_ONLY for inline relocation IF body byte-equivalent in caller) | DELETED | ✓ — function-as-symbol gone at HEAD; body-preservation captured in F005/F006 rationale rather than as a separate REFACTOR_ONLY row, per D-247-06 burden of proof (the body is paired with both a signature change and a control-flow gate removal, so the helper-as-function classification is unambiguously DELETED) |
| 48554f8f Vault `_requireApproved` | D-247-F009 | DELETED | DELETED | ✓ |

Zero deviations. No `OVERRIDE RATIONALE` blocks required.

## Section 3 — Downstream Call-Site Catalog (RESERVED FOR TASK 3)

This section is reserved for Task 3 of this plan to populate the grep-reproducible call-site inventory for every changed function and interface method. Row IDs `D-247-X###`. DO NOT edit this section in Tasks 1-2 — Task 3 replaces this stub in place.

## Section 4 — State Variable / Event / Interface / Error / Constant Inventory

Scope per CONTEXT.md D-247-09 item 4: all added/removed/signature-modified state variables (including any `DegenerusGameStorage.sol` deltas), every new `event` declaration, every changed interface method signature, every added/removed custom `error`, every added/removed top-level constant.

Row IDs continue `D-247-C###` sequence from Section 1 (do not restart numbering).

### 4.1 State Variables

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Type Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|

None — no state variables added, removed, or signature-changed across the 4 in-scope SHAs. `8bdeabc2`'s +12 lines are 11 lines of NatSpec + 1 line of executable code (`if (lastPurchaseDay || jackpotPhaseFlag) return false;`) inside an existing `internal view` function (`_livenessTriggered`) — no new state-variable declarations. Confirmed by Section 5 storage-layout diff returning byte-identical output at both SHAs.

### 4.2 Events

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Event Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|

None — no events added, removed, or signature-changed across the 4 in-scope SHAs.

### 4.3 Interface Methods

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Method Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|

None — `git diff cc68bfc7..acd88512 -- contracts/interfaces/` returns empty output. None of the 4 in-scope commits modify any interface file:

- `48554f8f` changes `burnCoin` / `burnEth` signatures on `DegenerusVault.sol` directly but does NOT propagate the change to any interface declaration (no `IDegenerusVault.sol` interface file exists in `contracts/interfaces/`; Vault is consumed by direct external calls without a separately-versioned interface).
- `6a63705b` changes `_callTicketPurchase` private function signature; private functions are not declared on any interface.
- `8bdeabc2` modifies internal `_livenessTriggered`; internal/private functions are not declared on any interface.
- `acd88512` modifies internal-to-module guards inside `advanceGame` and `rngGate`; neither function changes its own external signature.

### 4.4 Errors / Custom Reverts

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Error Signature | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C014 | 48554f8f | contracts/DegenerusVault.sol:357@cc68bfc7 | `NotApproved` | `error NotApproved()` | REMOVED | game-operator approval-check error no longer raised after Vault redemption decoupling |

### 4.5 Constants / Imports (REMOVED via 48554f8f)

| Row ID | Commit SHA | File:Line-Range | Symbol Name | Type/Source | Change Type | One-Line Semantic Note |
|---|---|---|---|---|---|---|
| D-247-C015 | 48554f8f | contracts/DegenerusVault.sol:5@cc68bfc7 | `IDegenerusGame` (named import) | `import {IDegenerusGame, MintPaymentKind} from "./interfaces/IDegenerusGame.sol";` → `import {MintPaymentKind} from "./interfaces/IDegenerusGame.sol";` | MODIFIED | named import slimmed; only MintPaymentKind retained; IDegenerusGame symbol no longer needed after approval helper removed |
| D-247-C016 | 48554f8f | contracts/DegenerusVault.sol:400@cc68bfc7 | `game` | `IDegenerusGame internal constant game = IDegenerusGame(ContractAddresses.GAME);` | REMOVED | constant referenced only by `_requireApproved`; removed alongside helper |

## Section 5 — Storage Slot Layout Diff (DegenerusGameStorage.sol)

Sole scope input for Phase 250 SIB-04 + Phase 252 POST31-01 per CONTEXT.md D-247-16. Verifies every slot that changed label / offset / type / size between baseline `cc68bfc7` and head `acd88512`. Among the 4 in-scope commits, only `8bdeabc2` touches `contracts/storage/DegenerusGameStorage.sol` (+12/-0); rows in this section, if any, are 100% attributed to `8bdeabc2`.

**Source command (reproducible):** `forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout` run at both SHAs. Baseline captured via `git worktree add --detach <tmp> cc68bfc7` to avoid touching the main working tree (per Section 7.1 recipe). Foundry stderr warning lines (`Warning: This is a nightly build...` and the YAML-cache warning) are stripped before diffing — they are noise from the toolchain, not part of the storage layout output.

### 5.1 Baseline storage layout (at cc68bfc7)

<details><summary>Raw `forge inspect` output (baseline cc68bfc7), warnings stripped</summary>

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

### 5.2 Head storage layout (at acd88512)

Identical to §5.1 baseline output (verified via `diff` returning empty after warnings stripped). Re-emitting the table in full would be redundant; the byte-equivalence between baseline and head is the load-bearing fact for §5.3 and §5.4 verdicts. The full HEAD-side output is reproducible at any time via the §7.1 commands.

### 5.3 Slot-by-slot diff

| Row ID | Slot | Baseline (label / type / offset / bytes) | Head (label / type / offset / bytes) | Change Type | One-Line Note |
|---|---|---|---|---|---|
| D-247-S001 | (n/a — entire 65-slot layout) | (identical) | (identical) | UNCHANGED | Storage layout byte-identical between baseline cc68bfc7 and head acd88512. `diff /tmp/v32-247-storage-layout-baseline-clean.txt /tmp/v32-247-storage-layout-head-clean.txt` returns empty (Foundry stderr warning lines stripped before diff). Confirms 8bdeabc2 introduces zero new state slots — the +12 lines are NatSpec (lines 1225-1234) plus a single `if (lastPurchaseDay || jackpotPhaseFlag) return false;` statement (line 1246) inside the existing `_livenessTriggered` internal view function body, none of which declare storage. |

Change Type vocabulary:
- `APPENDED` — new slot at end; no prior slot displaced (backwards-compatible)
- `MOVED` — existing label moved to a different slot number (LAYOUT-BREAK candidate)
- `TYPE-CHANGED` — same slot number, same label (or renamed), different solidity type/size (SEMANTIC-BREAK candidate)
- `INSERTED` — new slot inserted mid-layout displacing subsequent slots (LAYOUT-BREAK candidate)
- `REMOVED` — baseline slot absent at head (LAYOUT-BREAK candidate)
- `OFFSET-CHANGED` — packed slot where a neighbor changed size (within-slot layout shift; usually benign)
- `UNCHANGED` — slot byte-identical at both SHAs

### 5.4 Backwards-compatibility verdict (per-row)

| Row ID | Phase 250 SIB-04 / Phase 252 POST31-01 Expected Verdict | Rationale |
|---|---|---|
| D-247-S001 | SAFE / NON-WIDENING | No slot changes; backwards-compatible by construction. Phase 250 SIB-04 inherits a zero-row storage-delta scope. Phase 252 POST31-01 RE_VERIFIES that `8bdeabc2`'s function-body change does not depend on any new storage state — confirmed by §1.1 row D-247-C001 (the new statement reads only existing slot-0 fields `lastPurchaseDay` and `jackpotPhaseFlag`, both already declared at baseline). |

## Section 6 — Consumer Index (RESERVED FOR TASK 4)

This section is reserved for Task 4 of this plan to populate the v32.0 requirement (BFL/PLV/SIB/TST/POST31/FIND/REG) → 247 Row-ID mapping. Row IDs `D-247-I###`. DO NOT edit this section in Tasks 1-3 — Task 4 replaces this stub in place.

## Section 7 — Reproduction Recipe Appendix

Per CONTEXT.md D-247-19: every command used by Phase 247 Plan 247-01 preserved here so a reviewer can replay the entire DELTA-01 / DELTA-02 / DELTA-03 enumeration from shell. Portable POSIX syntax only.

### 7.1 Task 1 commands (DELTA-01 enumeration + storage layout)

**Baseline sanity gate:**

```bash
git rev-parse cc68bfc7
git rev-parse acd88512
git rev-parse HEAD
git diff --stat cc68bfc7..acd88512 -- contracts/
git log --format='%H %s' cc68bfc7..acd88512
git diff --name-status cc68bfc7..acd88512 -- contracts/
git status --porcelain contracts/ test/
```

Expected: `git diff --stat` reports `4 files changed, 47 insertions(+), 77 deletions(-)`; `git status --porcelain contracts/ test/` returns exactly 2 lines (` M contracts/ContractAddresses.sol` + `?? test/edge/LastPurchaseDayRace.test.js`) — both untouched by this plan per D-247-03 / D-247-17. Verified at Plan 247-01 Task 1 execution time (2026-04-30 / 2026-05-01).

**Per-source diff enumeration (Section 1):**

```bash
# In-scope commits (4 contract-touching SHAs)
git show 8bdeabc2 -- contracts/storage/DegenerusGameStorage.sol
git show 6a63705b -- contracts/modules/DegenerusGameMintModule.sol
git show 48554f8f -- contracts/DegenerusVault.sol
git show acd88512 -- contracts/modules/DegenerusGameAdvanceModule.sol

# Out-of-scope commit (test-only confirmation)
git show ad41973c --stat

# Interface drift sanity (expected: empty output — no interface deltas in v32 scope)
git diff cc68bfc7..acd88512 -- contracts/interfaces/
```

**Per-function line-range read (for File:Line-Range column resolution):**

```bash
# _livenessTriggered at HEAD (GameStorage)
git show acd88512:contracts/storage/DegenerusGameStorage.sol | grep -n -E '^\s*function _livenessTriggered'

# advanceGame / rngGate / _backfillGapDays at HEAD (AdvanceModule)
git show acd88512:contracts/modules/DegenerusGameAdvanceModule.sol | grep -n -E '^\s*function (advanceGame|rngGate|_backfillGapDays)'

# burnCoin / burnEth / _burnCoinFor / _burnEthFor / _requireApproved at HEAD vs baseline (Vault)
git show acd88512:contracts/DegenerusVault.sol  | grep -n -E '^\s*function (burnCoin|burnEth|_burnCoinFor|_burnEthFor|_requireApproved)'
git show cc68bfc7:contracts/DegenerusVault.sol  | grep -n -E '^\s*function (burnCoin|burnEth|_burnCoinFor|_burnEthFor|_requireApproved)'

# _callTicketPurchase / _purchaseFor / _purchaseCoinFor / purchaseCoin at HEAD (MintModule)
git show acd88512:contracts/modules/DegenerusGameMintModule.sol | grep -n -E '^\s*function (_callTicketPurchase|_purchaseFor|_purchaseCoinFor|purchaseCoin)'
```

**Baseline-side source reads (for DELETED detection — 48554f8f Vault helpers):**

```bash
git show cc68bfc7:contracts/DegenerusVault.sol > /tmp/v32-247-baseline-DegenerusVault.sol
git show cc68bfc7:contracts/storage/DegenerusGameStorage.sol > /tmp/v32-247-baseline-DegenerusGameStorage.sol
git show cc68bfc7:contracts/modules/DegenerusGameMintModule.sol > /tmp/v32-247-baseline-DegenerusGameMintModule.sol
git show cc68bfc7:contracts/modules/DegenerusGameAdvanceModule.sol > /tmp/v32-247-baseline-DegenerusGameAdvanceModule.sol
```

**Storage slot layout diff (Section 5):**

```bash
# Head-side layout
forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout > /tmp/v32-247-storage-layout-head.txt 2>&1

# Baseline-side layout via temporary worktree (avoids touching main working tree)
WORKTREE_DIR=$(mktemp -d -t v32-247-baseline-XXXXXX)
git worktree add --detach "$WORKTREE_DIR" cc68bfc7
( cd "$WORKTREE_DIR" && forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storage-layout ) > /tmp/v32-247-storage-layout-baseline.txt 2>&1
git worktree remove --force "$WORKTREE_DIR"

# Strip Foundry stderr warning + ANSI noise from both before diffing
sed -E -e 's/\x1b\[[0-9;]*[mGKHJ]//g' -e '/^Warning:/d' -e '/^$/d' -e '/foundry_compilers::cache/d' \
  /tmp/v32-247-storage-layout-baseline.txt > /tmp/v32-247-storage-layout-baseline-clean.txt
sed -E -e 's/\x1b\[[0-9;]*[mGKHJ]//g' -e '/^Warning:/d' -e '/^$/d' -e '/foundry_compilers::cache/d' \
  /tmp/v32-247-storage-layout-head.txt     > /tmp/v32-247-storage-layout-head-clean.txt

# Diff (expected: empty — byte-identical layout)
diff /tmp/v32-247-storage-layout-baseline-clean.txt /tmp/v32-247-storage-layout-head-clean.txt
```

**Light v31-243 reconciliation (Section 1.7):**

```bash
# Look for v31 rows whose function name matches a v32 in-scope function
for fn in _livenessTriggered advanceGame rngGate _backfillGapDays _callTicketPurchase _purchaseCoinFor _purchaseFor purchaseCoin burnCoin burnEth _burnCoinFor _burnEthFor _requireApproved; do
  echo "=== $fn ==="
  grep -n "$fn" audit/v31-243-DELTA-SURFACE.md || true
done
```

### 7.2 Task 2 commands (DELTA-02 classification)

Per CONTEXT.md D-247-08 / D-247-20: every classification verdict cites a hunk reproducible via `git show -L`. Commands are grouped by source SHA. Line ranges in the `git show -L` flag use the head-side range from the hunk reference column of Section 2 (or the cc68bfc7 baseline range for the 3 DELETED rows F007 / F008 / F009 whose body lives only at baseline).

**Per-row hunk extraction:**

```bash
# F001 — 8bdeabc2 _livenessTriggered productive-pause early-return (single-line addition + 11-line NatSpec block)
git show 8bdeabc2 -L 1246,1247:contracts/storage/DegenerusGameStorage.sol
git show 8bdeabc2 -L 1225,1235:contracts/storage/DegenerusGameStorage.sol   # NatSpec block context

# F002 — 6a63705b _callTicketPurchase signature change + 4 internal call-site charge swaps
git show 6a63705b -L 1200,1290:contracts/modules/DegenerusGameMintModule.sol

# F003 — 6a63705b _purchaseCoinFor caller-side arg drop (msg.sender,)
git show 6a63705b -L 894,902:contracts/modules/DegenerusGameMintModule.sol

# F004 — 6a63705b _purchaseFor caller-side arg drop (duplicate buyer,)
git show 6a63705b -L 975,983:contracts/modules/DegenerusGameMintModule.sol

# F005 — 48554f8f burnCoin signature change + operator-approval gate removal + body inline
git show 48554f8f -L 750,790:contracts/DegenerusVault.sol
git show cc68bfc7 -L 764,776:contracts/DegenerusVault.sol  # baseline-side public-wrapper dispatch

# F006 — 48554f8f burnEth signature change + operator-approval gate removal + body inline
git show 48554f8f -L 802,842:contracts/DegenerusVault.sol
git show cc68bfc7 -L 831,847:contracts/DegenerusVault.sol  # baseline-side public-wrapper dispatch

# F007 — 48554f8f _burnCoinFor DELETED helper (baseline-side read for body preservation cross-cite)
git show cc68bfc7 -L 777,817:contracts/DegenerusVault.sol

# F008 — 48554f8f _burnEthFor DELETED helper (baseline-side read for body preservation cross-cite)
git show cc68bfc7 -L 848,891:contracts/DegenerusVault.sol

# F009 — 48554f8f _requireApproved DELETED helper (baseline-side read for confirmation; 5-line body)
git show cc68bfc7 -L 444,448:contracts/DegenerusVault.sol

# F010 — acd88512 advanceGame turbo guard at L173 (3-line body diff + 6-line NatSpec expansion)
git show acd88512 -L 160,180:contracts/modules/DegenerusGameAdvanceModule.sol

# F011 — acd88512 rngGate backfill guard at L1173 (1-line body diff + 6-line NatSpec expansion)
git show acd88512 -L 1160,1180:contracts/modules/DegenerusGameAdvanceModule.sol
```

**DELETED-helper sanity (zero-callers-at-HEAD verification — referenced by F007 / F008 / F009 rationales):**

```bash
# Confirm function-as-symbol absence at HEAD
git show acd88512:contracts/DegenerusVault.sol | grep -c '^\s*function _burnCoinFor'        # expected: 0
git show acd88512:contracts/DegenerusVault.sol | grep -c '^\s*function _burnEthFor'         # expected: 0
git show acd88512:contracts/DegenerusVault.sol | grep -c '^\s*function _requireApproved'    # expected: 0

# Confirm function-as-symbol presence at baseline
git show cc68bfc7:contracts/DegenerusVault.sol | grep -c '^\s*function _burnCoinFor'        # expected: 1
git show cc68bfc7:contracts/DegenerusVault.sol | grep -c '^\s*function _burnEthFor'         # expected: 1
git show cc68bfc7:contracts/DegenerusVault.sol | grep -c '^\s*function _requireApproved'    # expected: 1
```

**REFACTOR_ONLY-vs-DELETED body-equivalence check (F007 / F008 rationale support — body-preservation fact):**

```bash
# Pattern: extract baseline helper body + head burnCoin body via sed, normalize player→msg.sender, diff
git show cc68bfc7:contracts/DegenerusVault.sol | sed -n '778,816p' \
  | sed -E 's/\bplayer\b/msg.sender/g' > /tmp/v32-247-baseline-burnCoinFor-body.sol
git show acd88512:contracts/DegenerusVault.sol | sed -n '751,789p'   > /tmp/v32-247-head-burnCoin-body.sol
diff /tmp/v32-247-baseline-burnCoinFor-body.sol /tmp/v32-247-head-burnCoin-body.sol
# Expected: empty diff after the player→msg.sender normalization, confirming the baseline _burnCoinFor body
# byte-equivalently appears inside HEAD's burnCoin. Per D-247-06 burden of proof the helper-as-function
# verdict is still DELETED (function-symbol gone) and the public wrapper is MODIFIED_LOGIC because the
# operator-approval branch + 4-line dispatch wrapper were removed alongside.

git show cc68bfc7:contracts/DegenerusVault.sol | sed -n '849,890p' \
  | sed -E 's/\bplayer\b/msg.sender/g' > /tmp/v32-247-baseline-burnEthFor-body.sol
git show acd88512:contracts/DegenerusVault.sol | sed -n '803,841p'   > /tmp/v32-247-head-burnEth-body.sol
diff /tmp/v32-247-baseline-burnEthFor-body.sol /tmp/v32-247-head-burnEth-body.sol
# Expected: empty diff modulo the player→msg.sender normalization (same conclusion as burnCoin).
```

### 7.3 Task 3 commands (DELTA-03 call-site catalog) — RESERVED FOR TASK 3

This subsection is appended by Task 3 of this plan during its execution per CONTEXT.md D-247-19 (every call-site row carries the exact `grep` command that found it).
