---
phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i
plan: 06
subsystem: testing
tags: [forge-build, storage-slot-rederivation, batchPurchase-reconciliation, d-01b-single-source, compile-fixes, vrf-freeze-slots]

# Dependency graph
requires:
  - phase: 317-01
    provides: "Pre-Deletion Test Baseline (71 failing / 446 passing / 16 skipped); slot-≥34 −2 family table; LootboxBoonCoexistence already-+1-stale flag; D-01b single-source reconciliation finding"
  - phase: 317-03
    provides: "DegenerusGame.batchPurchase(address[],uint256[],uint8[]) declaration + the new DegenerusGame-local box-cursor slots (boxCursor/boxCursorIndex slot 60, boxPlayers slot 61)"
  - phase: 317-04
    provides: "contracts/AfKing.sol canonical keeper with the batchPurchase call site (:738) + subscribe(address,bool,bool,uint8,uint8) + sweep(uint256 maxCount)"
  - phase: 317-05
    provides: "RM-02 (autoRebuyState slot 19 deleted) + JGAS-02 (resumeEthPool slot 33 deleted) — the −2 compounded shift input to the combined forge inspect"
provides:
  - "Re-derived test-side SLOT_* constants across the SLOT-bearing test files, all matching ONE authoritative post-deletion forge inspect (−2 vrf/lootboxRng family, −1 [20,33) region, new box-cursor slots accounted for)"
  - "PROTO-04 batchPurchase cross-repo signature reconciliation: MATCHED element-by-element (game decl :1687 vs keeper IGame decl :26 / call site :738) — no arg-order swap, no type divergence"
  - "Compile-fixes (D-03) confined to test/ — forge build PASS on the full patched degenerus-audit tree; zero contracts/ (production or test/mocks) mutation by this plan"
  - "D-01b reconciliation analysis: keeper SOURCE compiles; the architectural single-source choice + the test-harness rewrite are recorded as TWO options for the Wave-5 USER decision (NOT guessed destructively)"
affects: [317-07, 318, 320, vrf-freeze-invariant, slot-re-derivation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Re-derive SLOT_* from ONE authoritative post-deletion forge inspect, never patch-by-arithmetic / never blind −1"
    - "D-03 compile-fix discipline: drop test fns / branches that exercise deleted production surface; never rework assertions on surviving behavior (318 owns coverage)"
    - "Cross-repo signature reconciliation BEFORE the build gate (forge build cannot catch a same-type arg-order swap across two repos)"

key-files:
  created:
    - ".planning/phases/317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i/317-06-SUMMARY.md"
  modified:
    - "test/edge/MintCleanupRegression.test.js (slot-37→35 comment alignment; constants were already re-derived by a prior session)"
    - "test/fuzz/CoverageGap222.t.sol (removed test_gap_setAutoRebuy_observable — exercised deleted setAutoRebuy/setAutoRebuyTakeProfit/autoRebuyTakeProfitFor)"
    - "test/fuzz/RngLockDeterminism.t.sol (fuzz actions 12/13/14 → no-op slots; called deleted vault.gameSetAutoRebuy/gameSetAutoRebuyTakeProfit/gameSetAfKingMode)"
    - "test/fuzz/helpers/DeployProtocol.sol (stale comment: GAME.setAfKingMode() → AfKing.subscribe() SUB-09)"

key-decisions:
  - "The bulk of the SLOT_* re-derivation (8 SLOT-bearing files + AffiliateDgnrsClaim + BafRebuyReconciliation) was ALREADY applied by a prior session in the dirty working tree; this plan VERIFIED every value against the authoritative post-deletion forge inspect (all matched) and only added the one stale-comment slot-37→35 fix in the JS file."
  - "batchPurchase reconciled element-by-element and MATCHED — no escalation to Plan 03/04 needed."
  - "D-01b is genuinely AMBIGUOUS (pre-existing partial StreakKeeperV2 hand-rework vs the deeper canonical AfKing surface). Per the plan's anti-destructive-guess mandate, recorded BOTH reconciliation options + a recommendation for the Wave-5 USER decision rather than deleting the user's partial work or doing a large architectural rewrite. Keeper SOURCE compiles; the full keeper build fails ONLY on stale test-harness pull/mintForKeeper refs that are downstream of the unresolved architectural choice."

patterns-established:
  - "Slot-re-derivation verification: re-run forge inspect on the post-deletion tree and assert each test SLOT_* equals the live slot (the −2 family lands at vrfCoordinator 32 / lootboxRngPacked 35 / lootboxRngWordByIndex 36 / lootboxDay 37 / degeneretteBets 43 / boonPacked 59; lootboxEthBase 19 at −1)."

requirements-completed: [RM-06, JGAS-02, RM-05, PROTO-04]

# Metrics
duration: ~45min
completed: 2026-05-23
---

# Phase 317 Plan 06: Slot Re-Derivation + batchPurchase Reconciliation + D-01b Keeper Reconciliation Summary

**Verified the post-deletion test SLOT_* re-derivation against ONE authoritative `forge inspect` (the −2 vrf/lootboxRng family + new box-cursor slots), reconciled the cross-repo `batchPurchase` signature element-by-element (MATCHED), applied D-03 compile-fixes confined to `test/` so `forge build` PASSES on the patched degenerus-audit tree, and characterized the genuinely-ambiguous D-01b keeper reconciliation as TWO options for the Wave-5 USER decision (keeper SOURCE compiles; the user's pre-existing partial StreakKeeperV2 rework was preserved untouched). All commits DEFERRED to Plan 07.**

## Performance

- **Duration:** ~45 min
- **Tasks:** 3 of 3 completed
- **Files modified (this plan):** 4 test files in degenerus-audit; ZERO files in ../degenerus-utilities (the partial hand-rework was read + preserved, not mutated)
- **Build:** `forge build` exit 0 on the full patched degenerus-audit tree (SC#1 part 1 met); ../degenerus-utilities keeper SOURCE compiles (`forge build --skip test`), full keeper build blocked on stale test-harness refs (SC#1 part 2 — see Task 3 / Deviations)

## Accomplishments

### Task 1 — Combined forge inspect → SLOT_* re-derivation (RM-06)

Ran `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout --json` ONCE on the POST-(RM-02+JGAS) tree (both `autoRebuyState` slot 19 and `resumeEthPool` slot 33 deleted by Plan 05). The authoritative post-deletion layout confirmed the LEDGER predictions exactly:

| Var | Pre-deletion slot | Post-deletion slot (live) | Shift | Region |
|-----|------------------:|--------------------------:|-------|--------|
| `lootboxEthBase` | 20 | **19** | −1 | [20,33) |
| `operatorApprovals` | 21 | 20 | −1 | [20,33) |
| `levelDgnrsAllocation` | 25 | **23** | (test was stale) | [20,33) |
| `levelDgnrsClaimed` | 26 | **24** | (test was stale) | [20,33) |
| `vrfCoordinator` | 34 | **32** | −2 | ≥34 |
| `lootboxRngPacked` | 37 | **35** | −2 | ≥34 |
| `lootboxRngWordByIndex` | 38 | **36** | −2 | ≥34 |
| `lootboxDay` | 39 | **37** | −2 | ≥34 |
| `degeneretteBets` | 45 | **43** | −2 | ≥34 |
| `boonPacked` | 61 | **59** | −2 | ≥34 |
| `boxCursor` / `boxCursorIndex` | (new, 317-03) | **60** | new | DegenerusGame-local |
| `boxPlayers` | (new, 317-03) | **61** | new | DegenerusGame-local |

**The bulk of the SLOT_* re-derivation was ALREADY applied by a prior session** in the dirty working tree (the files showed up `M` in `git status` before this plan ran). This plan's RM-06 work was therefore primarily VERIFICATION: every re-derived constant in the modified test files was checked against the live forge-inspect output and **all matched**:

- `LootboxBoonCoexistence.t.sol` — SLOT_BOON_PACKED 65→**59**, SLOT_LOOTBOX_RNG_IDX 38→**35**, SLOT_LOOTBOX_WORD 39→**36**, SLOT_LOOTBOX_DAY 40→**37**, SLOT_LOOTBOX_BASE 21→**19**, SLOT_LOOTBOX_EV 42→**45**. These were the SPEC-flagged ALREADY-+1-STALE constants; they were set to the ABSOLUTE forge-inspect values (not a relative shift), exactly as mandated. (SLOT_LOOTBOX_EV moved UP 42→45 — confirming the "already off in the WRONG direction" hazard the LEDGER warned about; absolute re-derivation handled it correctly.)
- `RngIndexDrainBinding.t.sol` + `handlers/RngIndexDrainHandler.sol` — SLOT_LOOTBOX_MAPPING 38→**36**, SLOT_LR_INDEX 37→**35**.
- `RngLockDeterminism.t.sol` + `RngLockRotationDeterminism.t.sol` — SLOT_LOOTBOX_RNG_INDEX 37→**35**, SLOT_LOOTBOX_RNG_WORD_BY_INDEX 38→**36**.
- `VRFStallEdgeCases.t.sol` — SLOT_LOOTBOX_RNG_PACKED 37→**35**.
- `VrfRotationLiveness.t.sol` + `VrfRotationOrphanIndex.t.sol` — SLOT_LOOTBOX_PACKED 37→**35**, SLOT_LOOTBOX_WORD_MAP 38→**36**.
- `AffiliateDgnrsClaim.t.sol` — SLOT_LEVEL_DGNRS_ALLOCATION 25→**23**, SLOT_LEVEL_DGNRS_CLAIMED 26→**24**.
- `MintCleanupRegression.test.js` (JS) — LOOTBOX_RNG_PACKED_SLOT 37n→**35n**, LOOTBOX_RNG_WORD_BY_INDEX_BASE_SLOT 38n→**36n** (prior session) + **this plan fixed the stale narrative comment** "storage slot 37" → "storage slot 35" (no-history / describe-what-IS rule).

**Slots NOT affected (correctly untouched):** the Redemption-family SLOT_* (`StakedStonkRedemption.t.sol`, `handlers/RedemptionHandler.sol`, `RedemptionInvariants.inv.t.sol`, `RedemptionEdgeCases.t.sol` — slots 7-15) target `StakedDegenerusStonk` storage, NOT `DegenerusGame`. Confirmed `StakedDegenerusStonk` layout intact (Plan 05's RM-05/SUB-09 edits added interfaces/constants, not storage vars; `pendingRedemptions`=7 / `pendingByDay`=11 / `pendingResolveDay`=12 still live). VRFCore/LootboxRngLifecycle low-slot constants (RNG_WORD_CURRENT=3, VRF_REQUEST_ID=4) are < 19 and do not shift. `CrossSurfaceTicketMixing.test.js` reads `ticketsOwedPacked` (slot 13, unaffected) — no DegenerusGame −2-family ref.

**D-04 review artifact #3 (before/after layout) recorded above** + raw post-deletion JSON at `/tmp/317-post-layout.json` and table at `/tmp/317-post-layout-table.txt`.

### Task 2 — batchPurchase reconciliation (PROTO-04) + compile-fixes (D-03) → forge build PASS

**PROTO-04 cross-repo signature reconciliation (BLOCKER guard, before the build gate) — MATCHED:**

| Idx | Game decl (`DegenerusGame.sol:1687`) | Keeper `IGame` decl + call (`AfKing.sol:26` / `:738`) | Verdict |
|-----|--------------------------------------|-------------------------------------------------------|---------|
| 0 | `address[] calldata players` | `address[] calldata players` ← `players[batchLen] = player` | MATCH (type + order) |
| 1 | `uint256[] calldata amounts` | `uint256[] calldata amounts` ← `amounts[batchLen] = msgValue` (per-player wei slice) | MATCH (type + order + semantics) |
| 2 | `uint8[] calldata modes` | `uint8[] calldata modes` ← `modes[batchLen] = uint8(payKind)` | MATCH (type + order) |
| ret | `external payable` (no return) | `external payable` (no return) | MATCH |

Semantic cross-check: the game consumes `amounts[i]` as the per-player value slice (`this._batchPurchaseUnit{value: slice}(players[i], MintPaymentKind(modes[i]))` → `_purchaseFor(player, 0, msg.value, bytes32(0), payKind)`); the keeper fills `amounts[batchLen] = msgValue` (the per-player cost) and casts `uint8(payKind)` into `modes`. **No arg-order swap, no type divergence — the exact silent-compile hazard the plan flagged is absent.** No escalation to Plan 03/04 needed. `ContractAddresses.AF_KING` exists game-side (`:53`).

**D-03 compile-fixes (confined to test/, compile-fixes ONLY — no new coverage, no behavioral assertion rework):**
- `CoverageGap222.t.sol` — removed `test_gap_setAutoRebuy_observable()`: it made hard-bound direct calls to the DELETED `game.autoRebuyTakeProfitFor` / `game.setAutoRebuy` / `game.setAutoRebuyTakeProfit` (RM-01/RM-02 deleted these from `DegenerusGame` + `IDegenerusGame`). The other afKing/settleFlipModeChange references in this file use `.call(abi.encodeWithSignature(...))` string-selector form — they COMPILE fine (a removed selector simply returns `false`, which the existing `assertFalse(ok, ...)` already expects), so they were LEFT untouched (editing them would be behavioral rework outside D-03).
- `RngLockDeterminism.t.sol` — fuzz dispatcher actions 12/13/14 called the DELETED Vault wrappers `vault.gameSetAutoRebuy` / `gameSetAutoRebuyTakeProfit` / `gameSetAfKingMode` (RM-05 removed these). Converted the three branches to no-op `return` slots to keep the `seed % 22` action-space intact (no renumber, no `% N` change, zero new coverage).
- `helpers/DeployProtocol.sol` — stale comment "Stonk constructor calls GAME.claimWhalePass() + GAME.setAfKingMode()" → "GAME.claimWhalePass() + AfKing.subscribe() (SUB-09 self-subscribe)" (Plan 05 replaced the `setAfKingMode` init with the AfKing SUB-09 self-subscribe).

`contracts/test` + `contracts/mocks` are CLEAN of all deleted-symbol references (grep confirmed zero) — no compile-fix needed there.

**Result:** `forge build` exit 0 on the full patched degenerus-audit tree (compiles test/ too). Zero `Error (` lines; only pre-existing `forge-lint` advisory warnings (unsafe-typecast, variable shadowing — house style).

### Task 3 — D-01b ../degenerus-utilities reconciliation (recorded as a Wave-5 USER decision; keeper SOURCE compiles)

**Pre-existing dirty state read FIRST (per the IMPORTANT CONTEXT note — NOT assumed clean):** `git -C ../degenerus-utilities diff` shows a PARTIAL hand-rework predating this session on 4 files:
- `contracts/interfaces/IBurnie.sol` — `pullForKeeper`/`mintForKeeper` → `burnForKeeper(address,uint256) returns (uint256)`. **MATCHES canonical `contracts/AfKing.sol`'s local `IBurnie.burnForKeeper` verbatim.**
- `contracts/interfaces/ICoinflip.sol` — added `creditFlip(address,uint256)`. **MATCHES canonical `AfKing.sol`'s local `ICoinflip.creditFlip`.**
- `contracts/StreakKeeperV2.sol` — switched the day-31 charge from `pullForKeeper`→`burnForKeeper`, the bounty from the BURNIE-pool-drain+`mintForKeeper` model to `creditFlip`-only, and added the `ICoinflip` import.
- `.planning/config.json` — `_auto_chain_active: true → false` (unrelated to D-01b).

**The partial rework is GENUINELY INCOMPLETE relative to canonical `contracts/AfKing.sol`.** It aligned the BURNIE/Coinflip surface but did NOT carry the deeper Phase-317 reworks that landed in AfKing:
- AfKing has `subscribe(address player, bool, bool useTickets, uint8, uint8 reinvestPct)` (5-arg, SUB-02/SUB-04); the utilities keeper still has `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` (2-arg, OLD).
- AfKing has the parameterless `sweep(uint256 maxCount)` daily-reset cursor (SUB-03); the utilities keeper still has `sweep(uint256 startIdx, uint256 count)` (OLD caller-supplied range).
- AfKing uses the PROTO-04 `batchPurchase(address[],uint256[],uint8[])`; the utilities keeper still calls the per-player `IGame.purchase{value}(...)` (`StreakKeeperV2.sol:1110`) and its local `IGame` interface declares `purchase`, not `batchPurchase`.
- AfKing packs `reinvestPct`/`windowPaid` into the `Sub` free bytes + has the two-tier pinned-identity skip-kill; the utilities keeper has none of these.

**AF_KING pinned-address alignment:** game-side `contracts/ContractAddresses.sol` pins `AF_KING = address(0)` (deploy-script-populated placeholder); utilities `ContractAddresses.sol` pins `STREAK_KEEPER_V2 = address(0)` (release/sepolia-patched placeholder). **Both are `address(0)` and both are deploy-time-patched to the same predicted keeper address via the existing `script/PatchAddressesForFork.sh` pipeline — they ALIGN at the current value; there is no divergent non-zero literal to reconcile now.** The alignment MECHANISM (deploy predicts → patches both repos to the same literal) is intact.

**Build status:** the keeper SOURCE compiles (`forge build --skip "test/**"` → `KEEPER_SOURCE_BUILD_PASS`; the deploy script `DeployStreakKeeperV2.s.sol` deploying `new StreakKeeperV2(cost, bounty, lootbox)` compiles). The FULL keeper build FAILS (`KEEPER_FULL_BUILD_FAIL`) ONLY on ~76 test-harness references to the now-removed `IBurnie.pullForKeeper` / `mintForKeeper` selectors (61 in `StreakKeeperV2.unit.t.sol`, 11 in `StreakKeeperV2.fork.t.sol`, 4 in `Readme.t.sol`) — these are coupled to the OLD pool-bounty model the partial rework deleted.

**This is the genuine D-01b ambiguity the plan flagged. Per the explicit anti-destructive-guess mandate, the architectural choice + the test-harness rewrite are recorded as TWO options for the Wave-5 USER decision (see "D-01b Reconciliation Options" below) — the user's partial work was PRESERVED untouched (zero utilities files mutated by this plan).**

## D-01b Reconciliation Options (Wave-5 USER decision)

The single-source-of-truth path is genuinely ambiguous because the utilities `StreakKeeperV2.sol` is mid-rework AND diverges from canonical `contracts/AfKing.sol` on the core sweep/subscribe/purchase model. Two non-destructive paths:

**Option A — Replace the divergent keeper with the canonical AfKing (true D-01 single-source, RECOMMENDED).**
- Retire `../degenerus-utilities/contracts/StreakKeeperV2.sol` as the canonical logic; consume `degenerus-audit/contracts/AfKing.sol` via a foundry remapping (e.g. `degenerus-audit/=../degenerus-audit/`) OR repoint `DeployStreakKeeperV2.s.sol` to `import {AfKing} from "<canonical path>"` and `new AfKing(...)`.
- Rewrite the keeper test harness (`StreakKeeperV2.unit.t.sol` / `.fork.t.sol` / `Readme.t.sol`) against the reworked AfKing surface (`subscribe(address,bool,bool,uint8,uint8)`, `sweep(uint256 maxCount)`, `burnForKeeper`, `creditFlip`, `batchPurchase`).
- **Pro:** fully satisfies D-01b — logic lives ONCE in `degenerus-audit/contracts/AfKing.sol`; no divergent copy to drift. **Con:** discards the user's partial StreakKeeperV2 source rework + requires the largest test-harness rewrite.

**Option B — Finish the partial StreakKeeperV2 rework in-place.**
- Carry the remaining Phase-317 reworks (5-arg `subscribe`, parameterless `sweep(maxCount)` cursor, `reinvestPct`/`windowPaid` packing, two-tier pinned-identity skip-kill, `batchPurchase` switch + the `IGame.batchPurchase` decl) into the already-partially-reworked `StreakKeeperV2.sol`, keeping bodies byte-faithful to canonical AfKing.
- Then fix the test harness (re-point the ~76 `pull/mintForKeeper` refs to `burnForKeeper`/`creditFlip` + the new sweep/subscribe shapes).
- **Pro:** preserves the user's partial source work; the keeper stays a utilities-local deployable. **Con:** maintains a divergent copy (violates D-01 single-source unless bodies are kept byte-identical to AfKing and re-synced every milestone) — drift risk.

**Recommendation:** **Option A** — it is the only path that fully honors the D-01 "single source of truth = `degenerus-audit/contracts/AfKing.sol`" finding from the 317-LEDGER, and the test-harness rewrite is unavoidable either way (Option B also requires re-pointing the same ~76 refs). The partial source rework is preserved in the dirty tree for the user to evaluate before discarding.

## Threat-Register Outcomes (this plan's `<threat_model>`)

| Threat ID | Outcome |
|-----------|---------|
| T-317-06-00 (batchPurchase arg-order/type silent divergence) | MITIGATED — element-by-element diff performed BEFORE the build gate; MATCHED (no swap, no type divergence). |
| T-317-06-01 (blind −1 mis-deriving the vrf/lootboxRng family) | MITIGATED — every SLOT_* verified against ONE authoritative forge inspect; LootboxBoonCoexistence set to ABSOLUTE values (caught the SLOT_LOOTBOX_EV wrong-direction case). |
| T-317-06-02 (compile-fix masking a real contract defect) | MITIGATED — compile-fixes confined to test/ removed/no-op'd tests that exercise DELETED production surface; no surviving-behavior assertion was reworked; build green proves the production tree's call sites resolve. |
| T-317-06-03 (utilities pinning a different AF_KING) | MITIGATED — both repos pin `address(0)` placeholders patched to the same deploy-predicted address; alignment mechanism intact; the keeper diff is the Wave-5 D-02 USER review. |
| T-317-06-SC (package installs) | N/A — no installs; existing forge toolchain only. |

## Deviations from Plan

### Auto-fixed / boundary items

**1. [Rule 3 - Blocking] Deleted Vault-wrapper + game-fn references in test/ broke `forge build`**
- **Found during:** Task 2 (build gate).
- **Issue:** `RngLockDeterminism.t.sol` (actions 12/13/14) called the RM-05-deleted `vault.gameSetAutoRebuy`/`gameSetAutoRebuyTakeProfit`/`gameSetAfKingMode`; `CoverageGap222.t.sol::test_gap_setAutoRebuy_observable` called the RM-01/RM-02-deleted `game.setAutoRebuy`/`setAutoRebuyTakeProfit`/`autoRebuyTakeProfitFor`. Both are hard-bound (non-`.call`) → compile-break.
- **Fix:** removed the single uncompilable test function; converted the three fuzz action branches to no-op slots (preserving the `% 22` dispatch space). D-03 compile-fix only — the exercised behavior was DELETED, so this is not removing coverage of surviving behavior.
- **Files modified:** `test/fuzz/CoverageGap222.t.sol`, `test/fuzz/RngLockDeterminism.t.sol`.

**2. [Rule 3 - Documentation hygiene] Stale narrative comments referencing deleted surface / old slot**
- **Found during:** Tasks 1 + 2.
- **Issue:** `MintCleanupRegression.test.js` narrative comment cited "storage slot 37" (the constant below it was already re-derived to 35n by the prior session); `DeployProtocol.sol` comment said the Stonk ctor calls `GAME.setAfKingMode()` (deleted by RM-05).
- **Fix:** comment slot-37→35; comment `GAME.setAfKingMode()` → `AfKing.subscribe() (SUB-09 self-subscribe)`. Describe-what-IS / no-history rule.
- **Files modified:** `test/edge/MintCleanupRegression.test.js`, `test/fuzz/helpers/DeployProtocol.sol`.

**3. [Rule 4 - Architectural, recorded not actioned] D-01b single-source path is genuinely ambiguous**
- **Found during:** Task 3.
- **Issue:** the utilities keeper is a mid-flight partial rework diverging from canonical AfKing on the core sweep/subscribe/purchase model; resolving it requires an architectural choice (replace-with-AfKing vs finish-in-place) + a ~76-ref test-harness rewrite.
- **Action:** per the plan's explicit anti-destructive-guess mandate, recorded BOTH options + a recommendation (Option A) for the Wave-5 USER decision rather than guessing destructively. Zero utilities files mutated. Keeper SOURCE confirmed compiling.

### No-prior-session-credit note
A prior session had already re-derived most SLOT_* constants in the dirty tree (8 .sol files + AffiliateDgnrsClaim + the JS constants + BafRebuyReconciliation's deleted `game.setAutoRebuy` call). This plan VERIFIED all of them against the authoritative forge inspect (all matched) and added only the residual stale-comment + compile-fix edits above. The verification IS the RM-06 acceptance — the constants are now provably correct against the post-deletion layout.

## Post-Deletion Test Delta Attribution (T-317-06-02 / Phase 318 input)

The pre-deletion baseline (317-01) = 71 failing / 446 passing / 16 skipped. The `LootboxBoonCoexistence.t.sol::test_lootboxBoonAppliedDespiteExistingCoinflipBoon` failure is PRE-EXISTING (SPEC-flagged) AND its SLOT_* were already +1/+4 stale at HEAD — its re-derivation to ABSOLUTE forge-inspect values is correct and **must NOT be blamed on the slot re-derivation**. Per the plan, the "no NEW failures vs the 71-count baseline" assertion is left for **Phase 318** to run on the green-build tree (this plan only re-derives the constants so the suite recompiles with correct slots; SC#1 targets COMPILE, not a green suite).

## Known Stubs

None introduced. The no-op fuzz-action slots (RngLockDeterminism actions 12/13/14) are intentional compile-fix placeholders for deleted surface, documented in-line; they add no coverage and are not data stubs.

## Commit Status

**NO COMMIT — both repos.** The degenerus-audit PreToolUse commit-guard hook blocks all commits while any `contracts/*.sol` is dirty (14 production files + untracked `AfKing.sol` from Waves 2-3). This plan's `test/` re-derivation + compile-fixes are AGENT-COMPLETE but DEFERRED to Wave-5 Plan 317-07 (commits them AFTER the approved batched contract commit). The ../degenerus-utilities keeper diff (D-02) is presented for explicit USER review at Wave 5; its commit gate is the human pause at Plan 07 (the commit-guard hook does not watch that repo). `STATE.md` / `ROADMAP.md` untouched. HEADs unchanged: audit `471cb4ac`, utilities `4647294`.

## Self-Check: PASSED

- `317-06-SUMMARY.md` present on disk (uncommitted; `.planning/` is gitignored) — FOUND.
- `forge build` exit 0 on the patched degenerus-audit tree — `AUDIT_FORGE_BUILD_PASS` (SC#1 part 1).
- `forge inspect` post-deletion layout captured (`/tmp/317-post-layout.json`); every modified test SLOT_* verified == live slot (−2 family + box-cursor slots correct).
- batchPurchase reconciled element-by-element — MATCHED (game `:1687` vs keeper `:26`/`:738`).
- Compile-fixes confined to `test/` (4 files); `contracts/test` + `contracts/mocks` untouched (clean of deleted symbols); ZERO contracts/ production mutation by this plan.
- ../degenerus-utilities keeper SOURCE compiles — `KEEPER_SOURCE_BUILD_PASS`; full keeper build blocked only on stale test-harness refs downstream of the unresolved D-01b architectural choice (recorded as 2 options for Wave-5); user's partial rework PRESERVED (0 utilities files mutated).
- AF_KING pinned-address alignment confirmed (both repos `address(0)` deploy-time-patched placeholders).
- No `git commit` in either repo; commit-guard not bypassed; `STATE.md`/`ROADMAP.md` untouched; contracts/ left dirty.

---
*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Plan: 06*
*Completed: 2026-05-23*
