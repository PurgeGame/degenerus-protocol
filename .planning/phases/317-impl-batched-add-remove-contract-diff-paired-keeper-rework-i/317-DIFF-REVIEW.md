# Phase 317 — Batched ADD+REMOVE Contract Diff Review (D-04 Package)

**Assembled:** 2026-05-23 (Plan 317-07, Task 1)
**Status:** AWAITING USER REVIEW — no commit made; every edit requires explicit USER approval below.
**Baseline:** audit-repo HEAD `471cb4ac`; keeper-repo HEAD `4647294`.

This is the single review artifact for the milestone's ONE explicit USER approval of the batched
`degenerus-audit/contracts/` diff (now including the new `contracts/AfKing.sol`) plus the paired
`../degenerus-utilities` keeper diff (D-02). It contains, per D-04:
1. a `## Requirement-Mapped Summary` (every Phase-317 requirement → file:hunk),
2. a pointer to the full `git diff -- contracts/`,
3. the `forge inspect` storage-layout BEFORE/AFTER (the re-derived −2 slot family).

Plus, beyond D-04: a `## Out-of-Scope Edits Folded Into This Batch` section (so every contracts/ hunk
is accounted for) and a `## D-01b Keeper Decision (REQUIRED before keeper commit)` section.

---

## Dirty Contract Surface (what is in the batch)

**Audit repo — 14 dirty `contracts/` files** (13 modified + 1 untracked new file):

```
?? contracts/AfKing.sol                                   (NEW — canonical keeper, D-01)
 M contracts/BurnieCoin.sol
 M contracts/BurnieCoinflip.sol
 M contracts/ContractAddresses.sol
 M contracts/DegenerusGame.sol
 M contracts/DegenerusVault.sol
 M contracts/StakedDegenerusStonk.sol
 M contracts/interfaces/IBurnieCoinflip.sol
 M contracts/interfaces/IDegenerusGame.sol
 M contracts/modules/DegenerusGameAdvanceModule.sol
 M contracts/modules/DegenerusGameJackpotModule.sol
 M contracts/modules/DegenerusGameMintModule.sol
 M contracts/modules/DegenerusGamePayoutUtils.sol
 M contracts/storage/DegenerusGameStorage.sol
```

`git diff --stat -- contracts/` (modified files only): **+495 / −751** across the 13 modified files;
`AfKing.sol` is a NEW file (untracked, not in `--stat`).

**Keeper repo `../degenerus-utilities` — dirty (the PARTIAL, INCOMPLETE hand-rework — see D-01b):**

```
 M contracts/StreakKeeperV2.sol        (88 changed:  +/- )
 M contracts/interfaces/IBurnie.sol    (pull/mintForKeeper → burnForKeeper)
 M contracts/interfaces/ICoinflip.sol  (added creditFlip)
 M .planning/config.json               (unrelated: _auto_chain_active true→false)
```

---

## Requirement-Mapped Summary

All 26 Phase-317-owned requirements (24 primary-owned by 317 + PROTO-01 / SUB-09 which are 316-SPEC-owned
but IMPL-wired here) mapped to their file:hunk in the batched diff. Source: the sibling SUMMARYs
(317-02 / -03 / -03b / -04 / -05 / -06) + 316-SPEC `## Requirement Design Coverage`.

### ADD — PROTO additions (5)

| Req | Surface | File:hunk |
|-----|---------|-----------|
| PROTO-01 | `_hasAnyLazyPass` private view → `hasAnyLazyPass` external view, body byte-identical (KEEP+EXPOSE; the keeper's sole pass gate) + `IDegenerusGame` mirror | `DegenerusGame.sol:1472` · `interfaces/IDegenerusGame.sol:370` |
| PROTO-02 | `burnForKeeper(user, amount) returns (uint256 burned)` all-or-nothing keeper charge, `onlyAfKing` modifier + `OnlyAfKing` error + `KeeperBurn` event | `BurnieCoin.sol:456` (`:533` modifier, `:108` error, `:80` event) |
| PROTO-03 | `onlyFlipCreditors` extended with the `sender != ContractAddresses.AF_KING` clause (no new interface decl; bounty flows through existing `creditFlip`) | `BurnieCoinflip.sol:191` (`:198` AF_KING clause) |
| PROTO-04 | `batchPurchase(address[],uint256[],uint8[]) payable` keeper-gated on AF_KING + per-player `_batchPurchaseUnit` (onlySelf) try/catch slice-refund, ONE batch value transfer | `DegenerusGame.sol:1687` (`:1729` `_batchPurchaseUnit`) |
| PROTO-05 | `AF_KING` pinned constant (deploy-script-patched `address(0)` placeholder) | `ContractAddresses.sol:53` |

### ADD — Do-Work Crank (CRANK-01..04 + REW-01..04)

| Req | Surface | File:hunk |
|-----|---------|-----------|
| CRANK-01 | `crankBets(address[],uint64[])` parallel-array caller-list + `crankBoxes(uint256 maxCount)` (do-work entries + work-type encoding) | `DegenerusGame.sol:1543` · `:1592` |
| CRANK-02 | `BatchAlreadyTaken` short-circuit (probes item 0: `degeneretteBets[players[0]][betIds[0]] == 0`) | `DegenerusGame.sol:1552` (`:95` error) |
| CRANK-03 | parameterless box cursor (`boxCursor`/`boxCursorIndex`/`boxPlayers`) following the a303ae18 re-issue coupling; PRODUCER `enqueueBoxForCrank` wired into the MintModule first-deposit branch | `DegenerusGame.sol:1526` / `:1603` (orphan-index gate `lootboxRngWordByIndex[index] == 0`) · `modules/DegenerusGameMintModule.sol:999` (producer) |
| CRANK-04 | WWXRP `currency == 3` explicit zero-reward branch | `DegenerusGame.sol:1564` |
| REW-01 | reward formula = fixed gasUnits · gas-price-ref → BURNIE via zero-guarded `_ethToBurnieValue` (OPEN-B: price-unavailable → 0, never revert) | `DegenerusGame.sol:1568` / `:1622` |
| REW-02 | ONE `creditFlip(msg.sender, sum)` per tx (deferred mint, never per-item) | `DegenerusGame.sol` crank tail (creditFlip after the loop) |
| REW-03 | fixed RESERVED `CRANK_RESOLVE_BET_GAS_UNITS` / `CRANK_OPEN_BOX_GAS_UNITS` · `CRANK_GAS_PRICE_REF = 0.5 gwei` — NEVER `gasleft()`/`tx.gasprice` | `DegenerusGame.sol:1495` (`CRANK_GAS_PRICE_REF`) / `:1501` (gas-units consts) |
| REW-04 | no caller restriction on the crank entries (permissionless) | `DegenerusGame.sol:1543` / `:1592` (no `_requireApproved` gate) |

### ADD — Subscription Sweep & Authorization (SUB-01..09) — keeper-side `contracts/AfKing.sol` + the SUB-09 protocol self-subscribes

| Req | Surface | File:hunk |
|-----|---------|-----------|
| SUB-01 | pass-OR-pay at the day-31 renewal branch: `hasAnyLazyPass(player)` → free extend, else `burnForKeeper` or skip-with-emit | `AfKing.sol:578` |
| SUB-02 | authorization checked ONCE at `subscribe` (self-consent `player==0||msg.sender`, else operator-approved), never at sweep | `AfKing.sol:348` (`subscribe`) |
| SUB-03 | parameterless `sweep(uint256 maxCount)` daily-reset cursor (`_sweepDay`/`_sweepCursor` packed slot 4) | `AfKing.sol:522` (`:212`/`:213` cursor slot) |
| SUB-04 | flat + reinvest% COEXIST max-semantics: `effectiveQty = max(dailyQuantity, floor(claimable·reinvestPct/100/mp))`, dailyQuantity min 1 | `AfKing.sol` quantity path (`reinvestPct` offset 11 `:86`) |
| SUB-05 | funding waterfall (`drainGameCreditFirst`: claimable→pool→`InsufficientPool`-skip) byte-faithful | `AfKing.sol` funding path |
| SUB-06 | two-tier skip-kill by un-spoofable pinned `ContractAddresses.VAULT`/`SDGNRS` identity — NO settable exemption flag (grep: 0 matches) | `AfKing.sol:673` |
| SUB-07 | lapsed/cancelled lifecycle (tombstone-on-cancel; in-sweep swap-pop reclaim WITHOUT cursor-advance; windowPaid-gated `_subOf` reclaim) | `AfKing.sol:594` (`_removeFromSet`) / `:84` (`lastSweptDay`) |
| SUB-08 | bounty = `creditFlip(msg.sender, …)`, charge = `burnForKeeper(player, cost)` | `AfKing.sol` charge/bounty (`:50` burnForKeeper decl, `:63` creditFlip decl) |
| SUB-09 | sDGNRS + Vault protocol self-subscribe at init via the SUB-02 self-consent path; permanent-deity free-renew relies on the EXISTING `DegenerusGame` ctor grant (preserved byte-unmodified) | `StakedDegenerusStonk.sol:317`/`:379` · `DegenerusVault.sol:406`/`:473` · ctor grant preserved `DegenerusGame.sol:213`/`:214` |

### REMOVE (RM-01..06) + JGAS-02

| Req | Surface | File:hunk |
|-----|---------|-----------|
| RM-01 | AFKing-mode surface deletion (13 fns keeping only `hasAnyLazyPass`; 3 events; `AfKingLockActive` error; 3 consts; 2 `settleFlipModeChange` cross-calls) | `DegenerusGame.sol` (RM-01 deletions) · `interfaces/IDegenerusGame.sol:32`-stat (4 afKing decls removed) |
| RM-02 | free ETH auto-rebuy removed: `AutoRebuyState` struct + `autoRebuyState` mapping (slot 19); `_processAutoRebuy` + `_calcAutoRebuy` + `AutoRebuyCalc`; entropy arg dropped from `_addClaimableEth` (8 sites); ETH always credits to claimable | `storage/DegenerusGameStorage.sol` (struct+mapping deleted) · `modules/DegenerusGameJackpotModule.sol` · `modules/DegenerusGamePayoutUtils.sol` |
| RM-03 | BURNIE flip recycle collapsed to flat `RECYCLE_BONUS_BPS = 75`; afKing/deity tier removed; win/loss RNG path byte-unmodified | `BurnieCoinflip.sol:130` (`RECYCLE_BONUS_BPS = 75`), `:1002` (`_recyclingBonus` KEPT) · `interfaces/IBurnieCoinflip.sol` (`settleFlipModeChange` decl removed) |
| RM-04 | the KEPT `hasAnyLazyPass` (reconciled with PROTO-01 — see above; KEEP+EXPOSE) | `DegenerusGame.sol:1472` |
| RM-05 | cross-contract cascade: Vault `gameSet*` wrappers + decls removed (`coinSet*` KEPT); sStonk `setAfKingMode` decl + ctor init removed (`:417` whale-pass re-claim preserved) | `DegenerusVault.sol` · `StakedDegenerusStonk.sol` · `interfaces/IDegenerusGame.sol` |
| RM-06 | storage slot re-derivation (combined −2 family) — test-side `SLOT_*` re-derived from ONE authoritative post-deletion `forge inspect` (the test/ side is committed AFTER the contract commit) | test-side (see BEFORE/AFTER below); source carries zero numeric slot literals |
| JGAS-02 | daily-ETH two-call split removed: `SPLIT_NONE/CALL1/CALL2`, `resumeEthPool` (slot 33), `_resumeDailyEth`, `splitMode` routing, `call1Bucket`, `STAGE_JACKPOT_ETH_RESUME`; daily ETH jackpot completes in ONE call at the preserved 305 ceiling | `modules/DegenerusGameJackpotModule.sol` · `modules/DegenerusGameAdvanceModule.sol` (305 preserved `:210`) · `storage/DegenerusGameStorage.sol` (`resumeEthPool` deleted) |

**Coverage: 26/26 mapped, zero gaps.** (PROTO-01 + SUB-09 are 316-SPEC-owned by design but their IMPL wiring lands in this batch, hence their inclusion in the plan's `requirements` list.)

---

## Full Diff Pointer

The complete batched contract diff is NOT inlined here (it is large: ~495 insertions / 751 deletions
across 13 modified files + the new `AfKing.sol`). Review it directly:

```
# Audit repo — all modified contracts/ files:
git -C /home/zak/Dev/PurgeGame/degenerus-audit diff -- contracts/

# The new (untracked) canonical keeper file — review in full:
cat /home/zak/Dev/PurgeGame/degenerus-audit/contracts/AfKing.sol

# Per-file, if preferred:
git -C /home/zak/Dev/PurgeGame/degenerus-audit diff -- contracts/DegenerusGame.sol
git -C /home/zak/Dev/PurgeGame/degenerus-audit diff -- contracts/modules/DegenerusGameJackpotModule.sol
#   ... etc per the 13-file list above.

# Paired keeper repo (D-02):
git -C /home/zak/Dev/PurgeGame/degenerus-utilities diff
```

---

## Storage-Layout BEFORE / AFTER (re-derived −2 slot family)

**BEFORE (baseline, from 317-LEDGER §"Slot-≥34 family — current canonical"):** the two deletions
that drive the shift are `autoRebuyState`@slot 19 (RM-02) and `resumeEthPool`@slot 33 (JGAS-02). A
slot-≥34 var shifts −2 (compounded); a var in [20,33) shifts −1.

**AFTER (live `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout --json` on the
patched tree, run 2026-05-23):**

| Var | BEFORE slot (baseline) | AFTER slot (live forge inspect) | Shift | Region |
|-----|----------------------:|--------------------------------:|-------|--------|
| `lootboxEthBase` | 20 | **19** | −1 | [20,33) |
| `operatorApprovals` | 21 | **20** | −1 | [20,33) |
| `vrfCoordinator` | 34 | **32** | −2 | ≥34 |
| `lootboxRngPacked` | 37 | **35** | −2 | ≥34 |
| `lootboxRngWordByIndex` | 38 | **36** | −2 | ≥34 |
| `lootboxDay` | 39 | **37** | −2 | ≥34 |
| `degeneretteBets` | 45 | **43** | −2 | ≥34 |
| `boonPacked` | 61 | **59** | −2 | ≥34 |
| `boxCursor` / `boxCursorIndex` | (new) | **60** | new | DegenerusGame-local (317-03) |
| `boxPlayers` | (new) | **61** | new | DegenerusGame-local (317-03) |

The live AFTER values match the LEDGER predictions and the 317-06 re-derivation exactly. The re-derived
test-side `SLOT_*` constants (verified in 317-06 against this layout) are therefore correct against the
post-deletion contract. Raw JSON: `/tmp/317-after-layout.json`.

---

## Acceptance-Gate Results (run 2026-05-23 on the patched tree)

| Gate | Result | Detail |
|------|--------|--------|
| `forge build` (full patched tree) | **PASS** | exit 0; output is only pre-existing `forge-lint` advisory warnings (unsafe-typecast / shadow) — zero `Error (` lines. |
| SC#4 RM grep set (non-comment, outside `contracts/test`+`contracts/mocks`) | **4 matches — ALL net-new SUB-09 keeper-reference surface** (see note) | The 4 are the `afKing` keeper-handle constant + `afKing.subscribe(...)` self-subscribe in `DegenerusVault.sol` (`:406`/`:473`) and `StakedDegenerusStonk.sol` (`:317`/`:379`). The LEGACY afKing-MODE / autoRebuyState surface is fully gone (0 non-comment matches for the deep legacy set). The kept `hasAnyLazyPass` does NOT match the RM tokens. |
| JGAS-02 grep set (non-comment, outside test/mocks) | **PASS (0 matches)** | `resumeEthPool\|SPLIT_CALL1\|SPLIT_CALL2\|_resumeDailyEth\|STAGE_JACKPOT_ETH_RESUME\|call1Bucket` = 0. |
| BURNIE win/loss RNG path byte-unmodified vs baseline | **PASS** | zero `+`/`−` diff lines touch `processCoinflipPayouts` / `(rngWord & 1)` / `bool win`; path survives at `BurnieCoinflip.sol:756`/`:788`, `RECYCLE_BONUS_BPS = 75` at `:130`. |
| KNOWN_ISSUES vs baseline | **No NEW failures asserted here** | Pre-deletion baseline = 71 failing / 446 passing / 16 skipped (317-LEDGER). The "no NEW failures vs the 71-count" gate is Phase 318's (it runs on the green-build tree). 317 targets COMPILE (forge build PASS), not a green suite. |

### IMPORTANT — the 4 RM-grep matches are EXPECTED net-new surface, NOT a removal failure

The objective's RM token set includes the bare substring `afKing`. The SUB-09 self-subscribe code
legitimately NAMES its handle to the NEW canonical keeper `afKing` (e.g. `IAfKingSubscribe ... constant
afKing` + `afKing.subscribe(address(this), ...)`). The bare token therefore matches the NEW keeper
reference. These are net-new ADD surface (the SUB-09 protocol self-subscribe), not survivors of the
RM-01 legacy afKing-MODE deletion. Removing them would BREAK SUB-09. They are surfaced here for the
USER to accept as net-new naming. The narrower plan `<verify>` token set (which does not include
`setAutoRebuy`/`_afKing*`/`deactivate*`/`sync*`) yields the same 4 net-new matches.

A genuine STALE doc-comment match (`BurnieCoinflip.sol:11` "...optional afKing mode bonuses" + line 13
"Handles auto-rebuy...") describing the RM-03-deleted surface was found during this gate and fixed
(rewritten to describe what the file IS now — flat recycle bonus + bounty/quest rewards) per the
no-history / describe-what-IS rule.

---

## Out-of-Scope Edits Folded Into This Batch

Beyond the 26 planned Phase-317 requirements, the working tree contains ONE extra, user-requested,
OUT-OF-SCOPE contract edit folded into the same batch. It is presented here so the USER sees that every
`contracts/` hunk in the batch is accounted for — not only the 26 requirements. It is a user-requested
addition that awaits the same explicit USER approval as the 26 requirement hunks.

| Edit | File:hunk | Rationale |
|------|-----------|-----------|
| `_targetFlipDay()` inlined to a local time-only call | `BurnieCoinflip.sol:1016` (`return GameTimeLib.currentDayIndex() + 1;` replacing `degenerusGame.currentDayView() + 1`) + new import `BurnieCoinflip.sol:26` (`import {GameTimeLib} from "./libraries/GameTimeLib.sol";`) | Gas micro-opt: drops one cross-contract STATICCALL. Behavior is identical — `currentDayView()` → `_simulatedDayIndex()` → `GameTimeLib.currentDayIndex()` (verified: `DegenerusGameStorage.sol:1174-1176`), so both resolve to the same time-only library computation + the same `JACKPOT_RESET_TIME` / `DEPLOY_DAY_BOUNDARY` constants. NOT mapped to any Phase-317 requirement. |

---

## D-01b Keeper Decision (REQUIRED before keeper commit)

The keeper-side D-01b reconciliation is a GENUINE Wave-5 USER decision (sourced verbatim from
317-06-SUMMARY "D-01b Reconciliation Options"). The `../degenerus-utilities` keeper is an INCOMPLETE
partial hand-rework: the BURNIE/Coinflip surface is aligned (`burnForKeeper` / `creditFlip`) but the
deeper canonical AfKing reworks are NOT carried — it still has the 2-arg `subscribe(bool,uint8)`, the
range-based `sweep(startIdx,count)`, the per-player `IGame.purchase{value}` (NOT `batchPurchase`), no
`reinvestPct`/`windowPaid` packing, and no two-tier skip-kill. The keeper SOURCE compiles
(`forge build --skip test`); the FULL keeper build fails ONLY on ~76 stale test-harness
`pull/mintForKeeper` references downstream of the unresolved architectural choice. Both repos pin the
keeper address as `address(0)` placeholders (audit `AF_KING`, utilities `STREAK_KEEPER_V2`) patched to
the same deploy-predicted address — they align at the current value.

**Option A — Replace the divergent keeper with the canonical AfKing (true D-01 single-source, RECOMMENDED).**
- Retire `../degenerus-utilities/contracts/StreakKeeperV2.sol` as the canonical logic; consume
  `degenerus-audit/contracts/AfKing.sol` via a foundry remapping OR repoint `DeployStreakKeeperV2.s.sol`
  to `import {AfKing}` + `new AfKing(...)`.
- Rewrite the keeper test harness against the reworked AfKing surface (`subscribe(address,bool,bool,uint8,uint8)`,
  `sweep(uint256 maxCount)`, `burnForKeeper`, `creditFlip`, `batchPurchase`).
- **Pro:** fully satisfies D-01b — logic lives ONCE in `degenerus-audit/contracts/AfKing.sol`; no divergent
  copy to drift. **Con:** discards the user's partial StreakKeeperV2 source rework + the largest test-harness rewrite.

**Option B — Finish the partial StreakKeeperV2 rework in-place.**
- Carry the remaining Phase-317 reworks (5-arg `subscribe`, parameterless `sweep(maxCount)` cursor,
  `reinvestPct`/`windowPaid` packing, two-tier pinned-identity skip-kill, `batchPurchase` switch + the
  `IGame.batchPurchase` decl) into the partially-reworked `StreakKeeperV2.sol`, keeping bodies byte-faithful
  to canonical AfKing. Then fix the ~76 test-harness refs.
- **Pro:** preserves the user's partial source work; the keeper stays a utilities-local deployable.
  **Con:** maintains a divergent copy (violates D-01 single-source unless re-synced every milestone) — drift risk.

**Recommendation: Option A** — the only path that fully honors the D-01 single-source finding; the
test-harness rewrite is unavoidable either way (Option B also re-points the same ~76 refs). The partial
source rework is preserved untouched in the dirty utilities tree for the USER to evaluate before discarding.

**The keeper (D-02) diff cannot be committed until this is resolved + implemented + reviewed.** The
orchestrator routes the USER's A-vs-B choice; the executor implements neither here.

---

## What Is Awaited From the Human

1. **Review** the requirement-mapped summary above + the full `git diff -- contracts/` (13 files) + the
   new `contracts/AfKing.sol` + the `forge inspect` BEFORE/AFTER.
2. **Accept or reject** the 4 net-new SUB-09 `afKing` keeper-reference matches (expected ADD surface) and
   the out-of-scope `BurnieCoinflip._targetFlipDay` gas micro-opt.
3. **Pick D-01b Option A or B** for the keeper reconciliation (recommendation: A).
4. On **approve + D-01b choice** → the executor makes ONE batched `contracts/` commit
   (`CONTRACTS_COMMIT_APPROVED=1`) + implements/commits the keeper per the chosen option, then the deferred
   docs/test commits. On **issues** → describe them and the executor routes them to the revising waves
   before any commit.
