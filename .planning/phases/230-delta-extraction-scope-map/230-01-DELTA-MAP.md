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

Organized by contract category per D-07 (modules → core → storage → interfaces). Every one of the 12 in-scope files has its own subsection. Private and internal functions are included whenever they appear in the delta per D-04. The per-file classification is corroborated by `git diff -w --ignore-blank-lines` to separate semantic changes from comment/NatSpec/whitespace noise (D-03).

### 1.1 modules/ — DegenerusGameAdvanceModule.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/modules/DegenerusGameAdvanceModule.sol` shows 108 insertions / 29 deletions. `git diff -w --ignore-blank-lines` output retains all four substantive hunks (advanceGame control flow, `_consolidatePoolsAndRewardJackpots` branch merge, `_processFutureTicketBatch` / `_prepareFutureTickets` signature bump, `_finalizeRngRequest` earlybird hook + `_finalizeEarlybird` new function). The `_payDailyCoinJackpot` and `_emitDailyWinningTraits` hunks are pure multi-line reformats from 2471f8e7 with zero token changes — UNCHANGED per D-03.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `advanceGame()` | `external` | MODIFIED | `2471f8e7`, `52242a10` | 2471f8e7 removed the `_unlockRng(day)` call in the `JACKPOT_LEVEL_CAP` branch (line 443 pre-HEAD) so housekeeping packs into the last jackpot physical day; 52242a10 threads `rngWord` through the `_processFutureTicketBatch` and `_prepareFutureTickets` call sites (FF promotion + near-future prep). |
| `_consolidatePoolsAndRewardJackpots(uint24 lvl, uint24 prevMod100, uint24 prevMod10, uint256 rngWord, uint256 baseMemFuture, uint256 memFuture)` | `private` | MODIFIED | `3ad0f8d3` | Consolidates the x00 and x5 decimator branches into a single tail body guarded by `decPoolWei != 0`. Mutually exclusive triggers preserved; no flow change, but the shared tail eliminates duplicate `runDecimatorJackpot` self-call + bookkeeping. |
| `_payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel)` | `private` | UNCHANGED | `2471f8e7` | Multi-line reformat of parameter list only (comment/NatSpec-only per D-03 — no runtime effect). |
| `_emitDailyWinningTraits(uint24 lvl, uint256 randWord, uint24 bonusTargetLevel)` | `private` | UNCHANGED | `2471f8e7` | Multi-line reformat of parameter list and self-call arguments only (comment/NatSpec-only per D-03 — no runtime effect). |
| `_processFutureTicketBatch(uint24 lvl, uint256 entropy) returns (bool worked, bool finished, uint32 writesUsed)` | `private` | MODIFIED | `52242a10` | Signature gained `uint256 entropy` parameter; forwarded through the `abi.encodeWithSelector(IDegenerusGameMintModule.processFutureTicketBatch.selector, lvl, entropy)` delegatecall payload. |
| `_prepareFutureTickets(uint24 lvl, uint256 entropy) returns (bool finished)` | `private` | MODIFIED | `52242a10` | Signature gained `uint256 entropy` parameter; both the in-flight-resume call and the per-target loop now forward entropy to `_processFutureTicketBatch`. |
| `_finalizeRngRequest(...)` | `private` | MODIFIED | `f20a2b5e` | On level transition to `EARLYBIRD_END_LEVEL` the new `_finalizeEarlybird()` hook is invoked once. Placement: after `_rewardTopAffiliate(lvl)` and `level = lvl`, before the decimator window logic. |
| `_finalizeEarlybird()` | `private` | NEW | `f20a2b5e` | Extracted from Storage. Idempotent via the `earlybirdDgnrsPoolStart == type(uint256).max` sentinel. Dumps the remaining Earlybird pool into Lootbox via `dgnrs.transferBetweenPools(...)` and flips the sentinel. |

Functions — NEW: 1, MODIFIED: 5, DELETED: 0, UNCHANGED (comment/NatSpec-only): 2

### 1.2 modules/ — DegenerusGameJackpotModule.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` shows 48 insertions / 65 deletions. `git diff -w --ignore-blank-lines` retains all hunks (two event signature widenings, one new file-scope constant, one function body rewrite, four `emit` call-site swaps inside `runBafJackpot`). No formatting-only hunks.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `_runEarlyBirdLootboxJackpot(uint24 lvl, uint256 rngWord)` | `private` | MODIFIED | `20a951df` | Rewritten to draw winners from the same 4 bonus traits rolled for the coin jackpot via `_rollWinningTraits(rngWord, true)` + `JackpotBucketLib.unpackWinningTraits`. 4 × 25 winners per trait (100 total) pulled by 4 `_randTraitTicket` calls (was 100 per-winner calls with per-winner `entropy = EntropyLib.entropyStep(entropy)`). All winners queued at `lvl` (= outer caller level + 1) instead of spreading across `baseLevel..baseLevel+4`. Budget source and `_setNextPrizePool(... + totalBudget)` residual flow unchanged. |
| `runBafJackpot(uint24 lvl, uint256 rngWord, uint24 winnerCount, ...)` | `external` | MODIFIED | `104b5d42` | Four `emit` sites (two `JackpotEthWin`, two `JackpotTicketWin`) now pass the new file-scope `BAF_TRAIT_SENTINEL = 420` constant instead of the literal `0` trait id, tagging BAF payouts so indexers can distinguish them from trait-0 wins. No CEI or payout-math change. |

**Non-function declarations in the delta (recorded for completeness per D-07, not counted in the function totals):**
- `event JackpotEthWin(address indexed winner, uint24 indexed level, uint16 indexed traitId, uint256 amount, uint256 ticketIndex, uint24 rebuyLevel, uint32 rebuyTickets)` — MODIFIED by `104b5d42`: third indexed field `traitId` widened `uint8 → uint16` so the 420 sentinel fits above the real 0-255 trait space. Topic encoding unchanged (32 bytes regardless of declared width), but the event signature hash changes — ABI consumers must regenerate.
- `event JackpotTicketWin(address indexed winner, uint24 indexed ticketLevel, uint16 indexed traitId, uint32 ticketCount, uint24 sourceLevel, uint256 ticketIndex)` — MODIFIED by `104b5d42`: same `uint8 → uint16` widening as above.
- `uint16 private constant BAF_TRAIT_SENTINEL = 420;` — NEW file-scope constant introduced by `104b5d42`.

Functions — NEW: 0, MODIFIED: 2, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.3 modules/ — DegenerusGameDecimatorModule.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/modules/DegenerusGameDecimatorModule.sol` shows 35 insertions / 2 deletions. All hunks are semantic (new events + new `emit` sites inside `claimDecimatorJackpot` and `claimTerminalDecimatorJackpot`). No formatting-only hunks.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `claimDecimatorJackpot(uint24 lvl)` | `external` | MODIFIED | `67031e7d` | Added two new `emit DecimatorClaimed(...)` calls — one in the `gameOver` fast path (post `_creditClaimable`), one after the normal ETH/lootbox split (post `_setFuturePrizePool`). Arguments: claimer, lvl, `amountWei`, ETH portion, lootbox portion. No change to payout math or CEI ordering. |
| `claimTerminalDecimatorJackpot()` | `external` | MODIFIED | `67031e7d` | Added `emit TerminalDecimatorClaimed(msg.sender, lastTerminalDecClaimRound.lvl, amountWei)` immediately after `_creditClaimable(msg.sender, amountWei)` — at the correct CEI position (state mutation in `_consumeTerminalDecClaim` already complete, credit applied, event emitted last). |

**Non-function declarations in the delta:**
- `event DecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei, uint256 ethPortion, uint256 lootboxPortion)` — NEW, introduced by `67031e7d`.
- `event TerminalDecimatorClaimed(address indexed player, uint24 indexed lvl, uint256 amountWei)` — NEW, introduced by `67031e7d`.

Functions — NEW: 0, MODIFIED: 2, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.4 modules/ — DegenerusGameMintModule.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/modules/DegenerusGameMintModule.sol` shows 23 insertions / 29 deletions. `git diff -w --ignore-blank-lines` retains all three substantive hunks (`processFutureTicketBatch` sig bump + `rngWordCurrent` SLOAD removal; `_purchaseFor` restructure; `_callTicketPurchase` return-tuple restructure). No formatting-only hunks.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `processFutureTicketBatch(uint24 lvl, uint256 entropy) returns (bool worked, bool finished, uint32 writesUsed)` | `external` | MODIFIED | `52242a10` | Signature gained `uint256 entropy` parameter; the internal `uint256 entropy = rngWordCurrent;` SLOAD was removed — entropy is now caller-provided (today's daily RNG word from `rngWordByDay[day]` threaded via `_processFutureTicketBatch` → delegatecall payload). Removes reliance on `rngWordCurrent` staying set across downstream state transitions. |
| `_purchaseFor(...)` | `private` | MODIFIED | `f20a2b5e`, `d5284be5` | (f20a2b5e) Replaces per-purchase two-call earlybird award pattern with a single unified `_awardEarlybirdDgnrs(buyer, ticketFreshEth + lootboxFreshEth)` call at the bottom of the function; the prior in-branch `_awardEarlybirdDgnrs(buyer, lootboxFreshEth, cachedLevel + 1)` call inside the lootbox-deposit block was removed (and the matching ticket-side call lived in `recordMint`, also removed — see §1.6). `_callTicketPurchase` tuple destructuring updated to consume `ticketFreshEth` (new return) and drop `ethMintUnits`. (d5284be5) Lootbox-side `ethMintUnits` accumulator block removed; quest handler call now passes `uint256 ethFreshWei = ticketFreshEth + lootboxFreshEth` (1:1 wei credit to MINT_ETH) instead of lossy `ethMintUnits` scaling; conditional `if (ethMintUnits > 0 && questType == 1)` becomes `if (ethFreshWei > 0 && questType == 1)`. |
| `_callTicketPurchase(address buyer, address payer, uint256 quantity, ...) returns (uint256 bonusCredit, uint32 adjustedQty32, uint24 targetLevel, uint32 burnieMintUnits, uint256 freshEth)` | `private` | MODIFIED | `f20a2b5e`, `d5284be5` | (f20a2b5e) Return tuple loses `uint32 ethMintUnits` and gains `uint256 freshEth` — fresh-ETH is now surfaced to the caller (for unified earlybird + quest credit). Local `uint256 freshEth` declaration is promoted to the return slot. (d5284be5) In-body ticket-side `ethMintUnits` scaling block (`questUnits * freshEth / costWei`) removed entirely since MINT_ETH quest credit is now wei-direct via `_purchaseFor`. |

Functions — NEW: 0, MODIFIED: 3, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.5 modules/ — DegenerusGameWhaleModule.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/modules/DegenerusGameWhaleModule.sol` shows 3 insertions / 3 deletions — three identical single-line call-site updates. All substantive per D-03.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `_purchaseWhaleBundle(address buyer, uint256 quantity)` | `private` | MODIFIED | `f20a2b5e` | Call site `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` → `_awardEarlybirdDgnrs(buyer, totalPrice)` (drops third `currentLevel` arg per the new storage signature). |
| `_purchaseLazyPass(address buyer)` | `private` | MODIFIED | `f20a2b5e` | Call site `_awardEarlybirdDgnrs(buyer, benefitValue, startLevel)` → `_awardEarlybirdDgnrs(buyer, benefitValue)` (drops third `currentLevel` arg). |
| `_purchaseDeityPass(address buyer, uint8 symbolId)` | `private` | MODIFIED | `f20a2b5e` | Call site `_awardEarlybirdDgnrs(buyer, totalPrice, passLevel)` → `_awardEarlybirdDgnrs(buyer, totalPrice)` (drops third `currentLevel` arg). |

Functions — NEW: 0, MODIFIED: 3, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.6 core — DegenerusGame.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/DegenerusGame.sol` shows 13 insertions / 9 deletions. Two substantive hunks (earlybird block removal in `recordMint`; new `claimTerminalDecimatorJackpot` wrapper). No formatting-only hunks.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `recordMint(address player, uint24 lvl, uint256 costWei, uint32 mintUnits, MintPaymentKind payKind) returns (uint256 newClaimableBalance)` | `external payable` | MODIFIED | `f20a2b5e` | Removed the trailing 7-line earlybird block that derived `earlybirdEth` from `msg.value`/`costWei`/`payKind` and invoked `_awardEarlybirdDgnrs(player, earlybirdEth, lvl)`. Earlybird is now awarded once centrally in `DegenerusGameMintModule._purchaseFor` after both ticket and lootbox fresh-ETH are known. `recordMint` now terminates at `_recordMintDataModule(player, lvl, mintUnits)`. |
| `claimTerminalDecimatorJackpot()` | `external` | NEW | `858d83e4` | New external wrapper — delegatecalls into `ContractAddresses.GAME_DECIMATOR_MODULE` via `IDegenerusGameDecimatorModule.claimTerminalDecimatorJackpot.selector` and forwards revert data through `_revertDelegate(data)`. Sibling to the pre-existing `claimDecimatorJackpot(uint24 lvl)` wrapper; placed directly after it in source order. |

Functions — NEW: 1, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.7 core — DegenerusQuests.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/DegenerusQuests.sol` shows 3 insertions / 13 deletions. One substantive hunk (`handlePurchase` signature change + in-body rename + accumulator removal). No formatting-only hunks.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `handlePurchase(address player, uint256 ethFreshWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, ...)` | `external` | MODIFIED | `d5284be5` | Parameter `uint32 ethMintQty` renamed and retyped to `uint256 ethFreshWei`; in-body `uint256 delta = uint256(ethMintQty) * mintPrice;` line removed — `ethFreshWei` is now passed directly as the MINT_ETH quest delta (1:1 wei credit). All four downstream references (zero-check, per-slot call, `_handleLevelQuestProgress` fallback) updated to use `ethFreshWei`. No CEI or side-effect change beyond the unit switch. |

Functions — NEW: 0, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.8 core — BurnieCoin.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/BurnieCoin.sol` shows 3 insertions / 1 deletion — one 3-line hunk (2 comment lines + 1 semantic line inside `decimatorBurn`). `git diff -w --ignore-blank-lines` output confirms the semantic line (`uint24 lvl = degenerusGame.level() + 1;`) is a real runtime change.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `decimatorBurn(address player, uint256 amount)` | `external` | MODIFIED | `3ad0f8d3` | Local `uint24 lvl = degenerusGame.level();` replaced with `uint24 lvl = degenerusGame.level() + 1;` so burns during window level N land in `decBurn[N+1]`, matching the jackpot-resolution read side (which runs after the N→N+1 bump). Two new comment lines document the rationale. Side effect: DECIMATOR_MIN_BUCKET_100 now activates at the L100 jackpot (the previous keying made the `lvl % 100 == 0` check dead code against `level()=99`). |

Functions — NEW: 0, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.9 storage — DegenerusGameStorage.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/storage/DegenerusGameStorage.sol` shows 21 insertions / 22 deletions. Two substantive hunks (`_awardEarlybirdDgnrs` signature + body simplification; `boonPacked` mapping visibility change). No formatting-only hunks. One incidental `IStakedDegenerusStonk(ContractAddresses.SDGNRS).transferFromPool(...)` → `dgnrs.transferFromPool(...)` rewrite is a pure alias swap to the inherited storage-level `dgnrs` getter; no behavior change but the AST changes so it counts as MODIFIED under D-03 (same call target, same args, same effect).

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `_awardEarlybirdDgnrs(address buyer, uint256 purchaseWei)` | `internal` | MODIFIED | `f20a2b5e` | Signature lost its third parameter `uint24 currentLevel`. Body lost the entire `if (currentLevel >= EARLYBIRD_END_LEVEL) { … dump-remaining-pool-into-Lootbox … }` finalization branch (that logic relocated to `DegenerusGameAdvanceModule._finalizeEarlybird` at level transition). Added a new early-return guard `if (poolStart == type(uint256).max) return;` so once the sentinel is flipped this function becomes a safe no-op. `IStakedDegenerusStonk(ContractAddresses.SDGNRS).poolBalance(...)` and `.transferFromPool(...)` call sites swapped to the inherited `dgnrs.*` alias (identical target + behavior). |

**Non-function declarations in the delta:**
- `mapping(address => BoonPacked) internal boonPacked;` → `mapping(address => BoonPacked) public boonPacked;` — MODIFIED by `e0a7f7bc`: visibility changed `internal → public`, which auto-generates an external getter `boonPacked(address) returns (uint256 slot0, uint256 slot1)`. Storage layout is unchanged; the existing slot placeholders (25-41, 72-82, 85-87, 93-95) are preserved.

Functions — NEW: 0, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.10 interfaces — IDegenerusGame.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/interfaces/IDegenerusGame.sol` shows 4 insertions / 0 deletions — one pure additive hunk (4 lines including NatSpec).

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `claimTerminalDecimatorJackpot() external` | `external` (interface declaration) | NEW | `858d83e4` | Interface-level declaration matching the new `DegenerusGame.claimTerminalDecimatorJackpot` wrapper. NatSpec notes post-GAMEOVER callability and that the level is read from the resolved claim round (not a caller arg). |

**Note on `boonPacked` exposure (e0a7f7bc):** The `public` mapping on `DegenerusGameStorage` auto-generates an external getter on `DegenerusGame`. This getter is NOT declared on `IDegenerusGame.sol` — the interface file remained untouched by `e0a7f7bc`. Drift catalog (§3.1) records `boonPacked(address)` as "implementer adds external getter not declared on interface" (non-required — UI reads the concrete `DegenerusGame` address directly).

Functions — NEW: 1, MODIFIED: 0, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.11 interfaces — IDegenerusGameModules.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/interfaces/IDegenerusGameModules.sol` shows 3 insertions / 1 deletion — one substantive hunk on `processFutureTicketBatch` declaration inside `interface IDegenerusGameMintModule`.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `IDegenerusGameMintModule.processFutureTicketBatch(uint24 lvl, uint256 entropy) external returns (bool worked, bool finished, uint32 writesUsed)` | `external` (interface declaration) | MODIFIED | `52242a10` | Parameter list gained `uint256 entropy`. NatSpec documents "caller passes today's daily RNG word". This declaration is the selector reference used by `DegenerusGameAdvanceModule._processFutureTicketBatch` delegatecall payload — must stay in lockstep with the implementer (§1.4). |

Functions — NEW: 0, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

### 1.12 interfaces — IDegenerusQuests.sol

Verification: `git diff 14cb45e1..HEAD -- contracts/interfaces/IDegenerusQuests.sol` shows 3 insertions / 1 deletion — one substantive hunk on `handlePurchase` declaration.

| Function Signature | Visibility | Verdict | Commit SHA(s) | What Changed |
|---|---|---|---|---|
| `handlePurchase(address player, uint256 ethFreshWei, uint32 burnieMintQty, uint256 lootBoxAmount, uint256 mintPrice, ...)` | `external` (interface declaration) | MODIFIED | `d5284be5` | Parameter 2 renamed and retyped `uint32 ethMintQty → uint256 ethFreshWei`. Matches the `DegenerusQuests.handlePurchase` implementer (§1.7). NatSpec updated to document wei-direct credit. |

Functions — NEW: 0, MODIFIED: 1, DELETED: 0, UNCHANGED (comment/NatSpec-only): 0

Changelog totals — NEW: 3, MODIFIED: 21, DELETED: 0, UNCHANGED: 2; files with at least one non-UNCHANGED function: 12

## 2. Cross-Module Interaction Map
<!-- DELTA-02 — populated in task 3 -->

## 3. Interface Drift Catalog
<!-- DELTA-03 — populated in task 4 -->

## 4. Consumer Index
<!-- D-11 — populated in task 6 -->
