---
phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code-
plan: 04
subsystem: game-resident-logic (ARCH-02 Step 3 part B of the single batched v55.0 fold diff — the STAMP CONSUMER: open-pass + router + PLACE-02 bounty)
tags: [arch-02, afking-relocate, box-01, box-04, box-05, evcap-01, freeze-03, place-02, d-348-07, no-valve, frozen-input-twin, user-option-a-scope-expansion]
requires:
  - "349-01 applied (DegenerusGame.sol / DegenerusGameBingoModule.sol / IDegenerusGameModules.sol uncommitted)"
  - "349-02 applied (the REVISED DegenerusGameStorage.sol: Sub struct with the 5-field stamp + uint96 amount, _subOf/_subscribers/_subscriberIndex, uint16 _subCursor/_subOpenCursor, subsFullyProcessed — uncommitted; SOURCE authoritative)"
  - "349-03 applied (GameAfkingModule.sol part A: subscribe/setters + processSubscriberStage producing the D-348-07 5-field stamp + lastAutoBoughtDay marker — uncommitted; THIS plan EXTENDS the same file)"
provides:
  - "NEW external entrypoint resolveAfkingBox(player,index,amount,day,baseLevel,activityScore) in DegenerusGameLootboxModule.sol — the FROZEN-INPUT twin of resolveLootboxDirect (the one freeze-correct box-materialization seam for afking boxes; box materialization is otherwise private to the LootboxModule)"
  - "resolveAfkingBox selector added to IDegenerusGameLootboxModule in IDegenerusGameModules.sol (so GameAfkingModule's delegatecall resolves)"
  - "GameAfkingModule part B (same file): the post-RNG OPEN-PASS (thin: monotonic lastOpenedIndex guard + delegatecall to resolveAfkingBox, driven by _subOpenCursor) + the ROUTER (doWork/autoBuy/autoOpen one-category early-return) + the PLACE-02 bounty (advance leg 2x*mult carries the process bounty; open leg OPEN_KNEE work-scaled pro-rate; creditFlip payment)"
affects:
  - contracts/modules/DegenerusGameLootboxModule.sol
  - contracts/interfaces/IDegenerusGameModules.sol
  - contracts/modules/GameAfkingModule.sol
  - "349-05 (the AdvanceModule STAGE calls processSubscriberStage; doWork's advance leg re-enters advanceGame which will run that STAGE — the process bounty rides the advance bounty)"
  - "350 GAS (owns the BOUNTY_ETH_TARGET deploy-param + OPEN_BATCH flat-budget re-measurement carried-unchanged here)"
  - "351 TST (owns the test-ABI migration incl. the standalone AfKing surface)"
tech-stack:
  added: []
  patterns:
    - "FROZEN-INPUT twin entrypoint: resolveAfkingBox = resolveLootboxDirect's resolution SHAPE with every seed/roll/multiplier input read from the caller-supplied stamp (frozen day/baseLevel/score) instead of a live value — the seam that makes the afking box freeze-correct (FREEZE-03) while sharing _resolveLootboxCommon / _applyEvMultiplierWithCap / _rollTargetLevel one-source-of-truth with the human path"
    - "thin open-leg + draw-in-the-module: GameAfkingModule's open-pass is a cursor/marker/dispatch shell; the byte-identical draw math lives in resolveAfkingBox (LootboxModule) — the USER-approved Option A architectural fix (see Deviations)"
    - "shared per-level EV-cap budget across two open routes (BOX-05): resolveAfkingBox calls _applyEvMultiplierWithCap(player, level+1, amount, mult) — the SAME [player][level+1] map + helper the human openLootBox/resolveLootboxDirect/resolveRedemption use and MintModule's buy-time write keys; one RMW per route, the buy-time write bypassed for afking (process stamps only) ⇒ single draw, no double-draw"
    - "router self-call fold: doWork re-enters the Game's own advanceGame via IGameRouter(address(this)).advanceGame() (post-fold address(this) IS the Game); the advance leg's 2x*mult bounty IS the process bounty (PLACE-02 §6 — the process STAGE runs inside advance); the open leg is a separate post-RNG category"
key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameLootboxModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/modules/GameAfkingModule.sol
key-decisions:
  - "USER-approved Option A scope expansion: the open-pass needs the lootbox distribution (private to DegenerusGameLootboxModule); the one public seam resolveLootboxDirect is freeze-INCOMPATIBLE (derives seed from LIVE day/level). RESOLUTION: add a NEW external resolveAfkingBox (FROZEN-INPUT twin) in the LootboxModule + its selector in the interface, and make GameAfkingModule's open-pass a THIN delegatecall to it. THREE files this wave (the plan's original files_modified was GameAfkingModule.sol only)."
  - "resolveAfkingBox mirrors resolveLootboxDirect's tail for a boons-OFF auto-resolve box: _resolveLootboxCommon(..., emitLootboxEvent=false, payColdBustConsolation=false, distressEth=0, totalPackedEth=0). The two bool flags govern ONLY event-emit + cold-bust WWXRP consolation (NOT the draw/outcome); the boon/pass ROLL still runs on every ETH-lootbox path (gated by real game-state) identical to the auto-resolve callers — BOX-01 'boons OFF' governs the AMOUNT field (amount==spend, no boosted-amount freeze field), not the roll."
  - "Only TWO live reads in resolveAfkingBox: (1) currentLevel = level + 1 (the benign open-time level dependence kept byte-identical to openLootBox:524 / resolveLootboxDirect:767 so ticket placement does not drift — BOX-04), and (2) the EV-cap RMW (the sole residual live-read, a benign monotonic down-clamp — FREEZE-01b). day/baseLevel/score/amount/seed are all FROZEN from the stamp. ZERO block.* entropy in the seed."
  - "targetLevel rolls from the FROZEN stamped baseLevel (_rollTargetLevel(baseLevel, seed)) like openLootBox:535 — NOT from the live currentLevel as resolveLootboxDirect does. baseLevel = stamped baseLevelPlus1 - 1; activityScore = stamped scorePlus1 - 1 (both D-348-07 frozen)."
  - "PLACE-02 bounty model (DECIDED here, reconciled with 348-PLACEMENT-DECISION §6): the buy/process bounty FOLDS INTO the advance bounty — doWork's advance leg pays unit*2*mult, and the process STAGE runs INSIDE advanceGame (349-05) so this IS the process bounty, scaled by the AdvanceModule stall mult (1/2/4/6). The OPEN leg is a separate post-RNG router category paying the OPEN_KNEE work-scaled pro-rate (single-box open earns 0.2x, below gas — farm-by-splitting resistant). Payment = deferred creditFlip BURNIE flip-credit (never a transfer / mintForGame)."
  - "Router post-fold mapping: doWork() = rewarded one-category dispatch (advance -> afking-box open -> NoWork); autoBuy(count) = standalone UNREWARDED advance trigger (post-fold the subscriber 'buy' IS the required-path process STAGE that runs inside advanceGame, so the manual buy-clear drives advance — count inert, ABI-parity only); autoOpen(count) = standalone UNREWARDED afking-box open clear (walks _subOpenCursor)."
  - "BOUNTY_ETH_TARGET = 885_000_000 carried as a module internal constant (the deployed AfKing _bountyEthTarget, DeployProtocol.sol:126 arg 2) — a delegatecall module cannot hold a deploy-time immutable in the Game's storage context. OPEN_BATCH=200 / OPEN_KNEE=5 / ADVANCE_RATIO_NUM=2 folded from AfKing. The deploy-param/flat-budget tune is 350's charge; carried unchanged (no GAS work pulled forward)."
  - "_mintPriceInContext() = PriceLookupLib.priceForLevel(_activeTicketLevel()) — byte-identical to the Game's mintPrice() (:2502); the bounty's ETH->BURNIE divisor read in-context (no external/self call), so unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp matches the standalone AfKing exactly."
  - "_subOpenCursor wrap-reset (no extra index-key storage): the open leg walks _subscribers from _subOpenCursor and wraps to 0 at the set end; the per-sub monotonic lastOpenedIndex marker makes the re-walk idempotent (already-opened subs skip), so no _subOpenCursorIndex companion (the human autoOpen's boxCursorIndex analog) is needed — the storage layout is locked by 349-02."
patterns-established:
  - "resolveAfkingBox(address player, uint48 index, uint256 amount, uint32 day, uint24 baseLevel, uint16 activityScore) external — the afking open-route entrypoint; the GameAfkingModule open-leg delegatecalls it with (player, sub.index, uint256(sub.amount), sub.day, sub.baseLevelPlus1-1, sub.scorePlus1-1)"
  - "open-leg ladder: rngLock/liveness entry-gate (no-op in freeze, RD-3/RD-5) -> walk _subscribers from _subOpenCursor (wrap-reset at end) -> _afkingBoxReady(sub) pre-gate (stampIndex > lastOpenedIndex AND lootboxRngWordByIndex[stampIndex] != 0, the orphan-index re-issue coupling) -> _openAfkingBox (marker-first effects, then delegatecall) -> persist _subOpenCursor"
requirements-completed: [BOX-01, BOX-04, BOX-05, EVCAP-01, PLACE-02]
duration: ~55min
completed: 2026-05-31
---

# Phase 349 Plan 04: STAMP CONSUMER (GameAfkingModule part B — the open-pass + router + PLACE-02 bounty, via the USER-approved resolveAfkingBox frozen-input twin) Summary

**Resolved the architectural blocker the prior attempt correctly STOPPED at (the afking open needs the lootbox distribution, private to `DegenerusGameLootboxModule`; the one public seam `resolveLootboxDirect` is freeze-incompatible) via the USER-approved Option A: added a NEW external `resolveAfkingBox` (the FROZEN-INPUT twin of `resolveLootboxDirect` — `keccak256(abi.encode(rngWord,player,day,amount))` from the FROZEN stamped day [FREEZE-03], `_rollTargetLevel` from the FROZEN stamped baseLevel, exactly ONE `_applyEvMultiplierWithCap(player, level+1, …)` RMW from the FROZEN stamped score [EVCAP-01], then `_resolveLootboxCommon` — the ONLY live reads being `currentLevel = level+1` [benign BOX-04] and the EV-cap clamp [FREEZE-01b]) to the LootboxModule, declared its selector in `IDegenerusGameLootboxModule`, and authored the GameAfkingModule part-B: the THIN `_subOpenCursor`-driven open-pass (monotonic `lastOpenedIndex` no-double-open, boons-OFF `amount=spend` [BOX-01], delegatecall to `resolveAfkingBox`) + the `doWork`/`autoBuy`/`autoOpen` router with the PLACE-02 bounty (advance leg `2×·mult` carrying the process bounty; open leg `OPEN_KNEE` work-scaled pro-rate; `creditFlip` payment). All three files compile (`forge build --skip "test/**"` → Compiler run successful). NOTHING COMMITTED.**

---

## ⛔ Git posture — NOTHING COMMITTED (mandatory; the executor's hard constraint)

**NO git mutation ran** — no `git commit`, `git add`, `git rm`, `git stash`, `git reset`, `git checkout -- <file>`, or `git restore`. The single batched 349 contract diff is HELD for explicit USER approval; the ORCHESTRATOR owns that commit gate (deferred past the single user-approval gate at 349-05). Per the project #1 rule, the ONLY action needing approval is committing `contracts/*.sol`. Only read-only `git diff`/`git status`/`git log` + `grep`/read/`awk` + `forge build --skip "test/**" --skip "*.t.sol"` (self-check) were used. This SUMMARY is written with the Write tool and left **uncommitted** (`.planning/phases/` is gitignored, consistent with 349-01/02/03).

`git status --short` (read-only, end of plan):
```
 M .planning/STATE.md                                  (orchestrator-owned — UNTOUCHED by me)
 M contracts/DegenerusGame.sol                          (Wave 1 — UNTOUCHED)
 M contracts/interfaces/IDegenerusGameModules.sol       (Wave 1 + MY resolveAfkingBox selector)
 M contracts/modules/DegenerusGameBingoModule.sol       (Wave 1 — UNTOUCHED)
 M contracts/modules/DegenerusGameLootboxModule.sol     (THIS plan — NEW resolveAfkingBox entrypoint)
 M contracts/storage/DegenerusGameStorage.sol           (Wave 2, REVISED — UNTOUCHED; SOURCE authoritative)
 M scope.txt                                            (pre-existing — UNTOUCHED)
?? contracts/modules/GameAfkingModule.sol               (349-03 part A + THIS plan's part B, uncommitted)
```
`AfKing.sol` + `DegenerusGameAdvanceModule.sol` are byte-untouched (349-05/06 scope). HEAD unchanged (`60a4b5b5`). The `autonomous: false` checkpoint ran **hands-off** (per the project rule — only a `contracts/*.sol` commit needs approval, and the orchestrator owns it): all 3 tasks executed straight through, no pause.

---

## ⚠ THE AUTHORIZED ARCHITECTURAL FIX (USER Option A) — why THREE files this wave

The 349-04 plan's `files_modified` was `GameAfkingModule.sol` only, and Tasks 1/2 are written as if the box draw (`keccak256(abi.encode(...))` seed + `_applyEvMultiplierWithCap` RMW) lives IN `GameAfkingModule`. The prior attempt correctly STOPPED: the lootbox distribution (`_resolveLootboxCommon`, `_rollTargetLevel`, `_applyEvMultiplierWithCap`, `_accumulateLootboxRolls`, `_rollLootboxBoons`, …) is **`private` to `DegenerusGameLootboxModule`**, and the one PUBLIC seam, `resolveLootboxDirect` (`:763`), is **freeze-INCOMPATIBLE** — it derives the seed from the LIVE `day = _simulatedDayIndex()` and rolls from the LIVE `currentLevel`, which would let a player steer the afking box outcome at open time (the exact T-349-04-SEED spoof the threat model mitigates).

**The USER authorized Option A:** add a NEW external `resolveAfkingBox` — a FROZEN-INPUT twin of `resolveLootboxDirect` — to the LootboxModule (where the draw is byte-identical to the human `openLootBox` and shares the one private distribution), declare its selector in `IDegenerusGameLootboxModule`, and make `GameAfkingModule`'s open-pass a THIN delegatecall to it. This puts the freeze-critical draw where it is **correct and a single source of truth**, not contorted into `GameAfkingModule` to satisfy a literal grep.

**THREE files edited this wave (all within the USER-approved scope):**
1. `contracts/modules/DegenerusGameLootboxModule.sol` — NEW `resolveAfkingBox(...)`.
2. `contracts/interfaces/IDegenerusGameModules.sol` — `resolveAfkingBox` selector in `IDegenerusGameLootboxModule`.
3. `contracts/modules/GameAfkingModule.sol` — the open-pass (thin) + router + PLACE-02 bounty.

The OTHER already-modified files (`DegenerusGame.sol`, `DegenerusGameStorage.sol`, `DegenerusGameBingoModule.sol`) and `AfKing.sol`/`DegenerusGameAdvanceModule.sol` were NOT touched.

---

## Task 1 — the afking open-pass: byte-identical materialization (BOX-04), abi.encode stamped-day seed (FREEZE-03), boons-OFF amount=spend (BOX-01), monotonic lastOpenedIndex — DONE (via resolveAfkingBox + the thin open-leg)

**`resolveAfkingBox(address player, uint48 index, uint256 amount, uint32 day, uint24 baseLevel, uint16 activityScore)`** in `DegenerusGameLootboxModule.sol` (inserted after `resolveRedemptionLootbox` `:820`). Body (the substantive acceptance — confirmed by isolated grep of the function body):
- `uint256 rngWord = lootboxRngWordByIndex[index];` (write-once by `_finalizeLootboxRng`, read-only at open) `if (rngWord == 0) revert RngNotReady();`
- `uint256 seed = uint256(keccak256(abi.encode(rngWord, player, day, amount)));` — the **`abi.encode`** form at `LB:534`/`resolveLootboxDirect:768` (NOT the PRESALE `:644` `abi.encodePacked`), seeded from the **FROZEN `day` param** (FREEZE-03), never open-time `_simulatedDayIndex()`. ZERO `block.*` entropy.
- `uint24 currentLevel = level + 1;` — the benign live open-time level dependence kept byte-identical to `openLootBox:524` / `resolveLootboxDirect:767` (BOX-04).
- `uint24 targetLevel = _rollTargetLevel(baseLevel, seed);` — rolls from the **FROZEN stamped `baseLevel`** (like `openLootBox:535`'s frozen-snapshot baseLevel), NOT the live `currentLevel`.
- `evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(activityScore));` — from the **FROZEN stamped `activityScore`** (D-348-07).
- `scaledAmount = _applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps);` — the SINGLE EV-cap RMW (Task 2).
- `_resolveLootboxCommon(player, day, index, scaledAmount, targetLevel, currentLevel, seed, false, false, 0, 0);` — matches `resolveLootboxDirect`'s boons-OFF auto-resolve tail.

**The thin open-leg in `GameAfkingModule` (`_openAfkingBox` + `_afkingBoxReady` + `_autoOpen`):**
- `_openAfkingBox(player, sub)` — **BOX-04 monotonic guard**: `if (sub.index <= sub.lastOpenedIndex) return;` then advance `sub.lastOpenedIndex = sub.index` **BEFORE** the resolve (effects-before-interaction; a re-entrant open re-checks the advanced marker and no-ops), then delegatecall `IDegenerusGameLootboxModule.resolveAfkingBox.selector` with `(player, stampIndex, uint256(sub.amount), sub.day, sub.baseLevelPlus1 - 1, sub.scorePlus1 - 1)` — **boons OFF ⇒ `amount = sub.amount` widened uint96→uint256 (BOX-01)**. Tail = `if (!ok) _revertDelegate(data);` (the canonical module assembly-revert, folded as a `private pure` helper — cf. DegeneretteModule:123).
- `_autoOpen(maxCount)` — walks `_subscribers` from `_subOpenCursor` (uint16), `rngLock`/`_livenessTriggered()` entry-gate (no-op in freeze, RD-3/RD-5), `_afkingBoxReady` pre-gate (orphan-index re-issue coupling), cursor wrap-reset at the set end, persists `_subOpenCursor`.

**Verify-deviation (EXPECTED — documented per the prompt):** the plan's Task-1 `<verify>` greps for `keccak256(abi.encode(` / `_rollTargetLevel` IN `GameAfkingModule.sol`; under the USER-approved design those live in `resolveAfkingBox` (LootboxModule, byte-identical to openLootBox — one source of truth). In `GameAfkingModule.sol`: `abi.encodePacked`=0 ✓, `lootboxRngWordByIndex`=1 ✓ (the `_afkingBoxReady` readiness gate), `lastOpenedIndex`=5 ✓ (the monotonic guard), **`_simulatedDayIndex`=0 in CODE** ✓ (the lone grep hit is a comment). Substantive acceptance MET in `resolveAfkingBox` (isolated-body grep): `keccak256(abi.encode(rngWord,player,day,amount))`=1, `abi.encodePacked`=0 (CODE), `_simulatedDayIndex`=0 (CODE), `_rollTargetLevel(baseLevel,seed)`=1.

## Task 2 — EV-cap-at-open via _applyEvMultiplierWithCap once, buy-time write bypassed, frozen evMultiplierBps (EVCAP-01); two routes hazard-free (BOX-05) — DONE (in resolveAfkingBox)

`resolveAfkingBox` calls **`_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)` exactly ONCE** (`currentLevel = level + 1`), keyed on the SAME `lootboxEvBenefitUsedByLevel[player][lvl]` map (`Storage:1469`, `lvl = currentLevel = level+1`) — confirmed byte-identical to `resolveLootboxDirect:772` / `resolveRedemptionLootbox:805` (all `_applyEvMultiplierWithCap(player, currentLevel, ...)`), and the same `[player][level+1]` key MintModule's buy-time write (`:1303`/`:1327`, `[buyer][cachedLevel+1]`) uses. Fed the **FROZEN `evMultiplierBps`** from the stamped `activityScore` (NOT a live score recompute). The helper hard-clamps at `LOOTBOX_EV_BENEFIT_CAP = 10 ether` with the no-write 100%-EV short-circuit once exhausted (`:478-481`) ⇒ **NO revert** (the sole residual live-read, a benign monotonic down-clamp — FREEZE-01b; not a class-B solvency site).

**Buy-time write bypassed (no double-draw, §3-iii):** the 349-03 process pass STAMPS only — it does NOT route through `_callTicketPurchase` (MintModule:1496) nor touch the buy-time EV writes (`GameAfkingModule.sol` has `_callTicketPurchase`=0 in CODE; the 7 `MintModule` hits are all comment-prose). So the single EV RMW for an afking box is here at open — exactly one per open, equivalent to the v54 per-(sub,level) accumulator.

### BOX-05 two-route hazard-free reconciliation (recorded per the plan output requirement)

The afking open route and the human `openLootBox` route share NO mutable-state hazard:

1. **The EV-cap map is the one intended per-level 10-ETH budget.** Both routes do **exactly one RMW** via the SAME `_applyEvMultiplierWithCap` helper keyed `[player][level+1]`. The human buy-time write (MintModule) draws the cap at buy; the human `openLootBox` then reads the frozen snapshot (no second draw). The afking process pass BYPASSES the buy-time write (stamps only), so the afking box's single RMW is at open. Net: every box — human or afking — draws the shared `[player][level+1]` 10-ETH budget exactly once. Sharing the budget is **intended** (a player's afking + manual boxes at the same level compete for the same 10-ETH EV cap), not a hazard.
2. **`lootboxRngWordByIndex` is read-only / write-once.** Written once per index by `_finalizeLootboxRng` (`:1231`); both routes only READ it at open. No contention.
3. **The afking stamp is producer→consumer ordered.** `processSubscriberStage` (the pre-RNG STAGE, 349-03/05) PRODUCES the stamp + `lastAutoBoughtDay`; the open-leg CONSUMES it post-RNG, gated by `subsFullyProcessed` (the no-interleave chunk gate) + the per-sub monotonic `lastOpenedIndex`. The `_subOpenCursor` open never runs before the stamp is committed for the cycle (post-RNG sequencing), and `_afkingBoxReady` requires the stamp's index to have a landed word.
4. **The human route is disjoint per-index state.** `openLootBox` keys on `lootboxEth[index][player]` / `lootboxPurchasePacked[index][player]` / `lootboxDay[index][player]` / `boxPlayers[index]` — NONE of which the afking route reads or writes (the afking box is a warm Sub-stamp, no cold ledger). The two routes touch only the (intentionally) shared EV-cap budget and the write-once word.

**Verify-deviation (EXPECTED):** the plan's Task-2 `<verify>` greps for `_applyEvMultiplierWithCap` + `level+1` IN `GameAfkingModule.sol`; it lives in `resolveAfkingBox` (the byte-identical draw, one source of truth). In `GameAfkingModule.sol`: `_callTicketPurchase`=0 ✓, `MintModule`=0 in CODE ✓ (7 comment hits). In `resolveAfkingBox` body: `_applyEvMultiplierWithCap(player, currentLevel, amount, evMultiplierBps)`=1, `currentLevel = level + 1`=1.

## Task 3 — the router (doWork/autoBuy/autoOpen) + the PLACE-02 bounty (work-scaled, post-RNG open category, creditFlip) — DONE

**`doWork()`** — the unified permissionless router (one-category STRUCTURAL early-return, NO `nonReentrant` guard — ROUTER-07 afking-never-a-payee):
- `unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / _mintPriceInContext()` (`_mintPriceInContext` is byte-identical to the Game's `mintPrice()`).
- **(1) advance** (priority, liveness-critical): `if (IGameRouter(address(this)).advanceDue())` → `uint8 mult = IGameRouter(address(this)).advanceGame();` → `if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;` (the self-call re-enters the Game's `advanceGame`, which runs the required-path process STAGE in-context at 349-05 — **the process bounty rides this `2×·mult`**; `mult==0` gameover pays nothing).
- **(2) afking-box open** (else): `uint256 opened = _autoOpen(OPEN_BATCH);` → `if (opened > 0) { k = min(opened, OPEN_KNEE); bountyEarned = (unit * k) / OPEN_KNEE; }` (the **`OPEN_KNEE` work-scaled pro-rate** — a single-box open earns 0.2×, below gas; farm-by-splitting resistant) `else revert NoWork();`.
- The single unified bounty: ONE `coinflip.creditFlip(msg.sender, bountyEarned)`, **CEI-LAST**, skipped at 0.

**`autoBuy(uint256 count)`** — standalone UNREWARDED manual advance trigger (post-fold the subscriber "buy" IS the required-path process STAGE that runs inside `advanceGame`, so the manual buy-clear drives advance; `count` is inert ABI-parity per the relocated AfKing surface, the STAGE's chunk budget lives in the AdvanceModule). **`autoOpen(uint256 count)`** — standalone UNREWARDED afking-box open clear (`_autoOpen(count)`, walks `_subOpenCursor`). Only `doWork` credits.

**PLACE-02 (reconciled with 348-PLACEMENT-DECISION §6):** §6 says the buy/process bounty FOLDS INTO the advance bounty (`2×·mult`); the OPEN keeps its own separate post-RNG `OPEN_BATCH`-style category with the `OPEN_KNEE` pro-rate. Landed exactly: the process STAGE (inside advance) rides the `2×·mult` advance bounty; the open leg is a separate category paying `OPEN_KNEE`. Payment is the deferred `creditFlip` BURNIE flip-credit (NOT a transfer / NOT `mintForGame`). **No GAS-01/02/03 work pulled in** (`GAS-0*`=0 in the module; `BOUNTY_ETH_TARGET`/`OPEN_BATCH` carried unchanged — 350's charge). **No try/catch** (D-348-04 no-valve — definitive grep: zero real try-statement / catch clause in CODE).

**Verify:** Plan Task-3 `<verify>` — `function doWork|autoBuy|autoOpen`=3 ✓, `creditFlip`=3 ✓ → **ROUTER+BOUNTY-CREDITFLIP**.

---

## Self-build (read-only — the orchestrator's exact command, run as a self-check)

`forge clean && forge build --skip "test/**" --skip "*.t.sol"` → **`Compiling 67 files with Solc 0.8.34` / `Compiler run successful with warnings`** — all three authorized files compile, **0 errors**. The only warnings touching my new code are **5 advisory `unsafe-typecast` lints** in `GameAfkingModule.sol` (the project's accepted repo-wide convention, 1068+ across the codebase):
- L745 `uint16(activityScore + 1)` (PART A — guarded by the explicit `> type(uint16).max ?` clamp).
- L748 `uint96(amount)` (PART A — revised-layout cast, SAFE: uint96 max ≈ 79e9 ETH).
- L764 `uint128(ethValue)` (PART A — SOLVENCY-01 tandem-move, matches batchPurchase:1866).
- L780 `uint16(cursor)` (PART A — `_subCursor` persist, bounded by SUBSCRIBER_CAP).
- **L903 `uint16(cursor)` (PART B — MY new `_subOpenCursor` persist; SAFE: identical invariant — `cursor ≤ _subscribers.length ≤ SUBSCRIBER_CAP = type(uint16).max`).**

`resolveAfkingBox` adds no new warnings (its casts mirror `resolveLootboxDirect`). The authoritative whole-diff `forge build --sizes` is the orchestrator's; LootboxModule has ~6,950 B headroom and `resolveAfkingBox` is small (one new external function reusing the existing private distribution), so the EIP-170 budget is unaffected materially.

---

## Deviations from Plan

**One AUTHORIZED scope expansion (USER Option A) + one expected verify-deviation. Zero unauthorized behavior changes.**

1. **[USER-AUTHORIZED Option A — architectural fix, NOT a Rule-1/2/3 auto-fix] Three files instead of one; the box draw lives in a NEW `resolveAfkingBox` (LootboxModule), not in `GameAfkingModule`.** The plan's `files_modified` was `GameAfkingModule.sol` only and Tasks 1/2 placed the draw there. The lootbox distribution is `private` to the LootboxModule and the one public seam (`resolveLootboxDirect`) is freeze-incompatible. The USER authorized adding the FROZEN-INPUT twin `resolveAfkingBox` + its interface selector + a thin open-leg delegatecall. **Impact:** the freeze-critical draw is where it is correct (byte-identical to `openLootBox`, one source of truth); the substantive acceptance (FREEZE-03 abi.encode stamped-day seed, single EV RMW at open, BOX-04 byte-identical, BOX-05 hazard-free) is fully MET. Files touched are exactly the three the USER authorized.
2. **[Expected verify-deviation — documented, NOT a contortion] The plan's Task-1/Task-2 literal `<verify>` greps expect the draw (`keccak256(abi.encode(` / `_applyEvMultiplierWithCap`) IN `GameAfkingModule.sol`.** Under Option A those live in `resolveAfkingBox` (LootboxModule). Per the prompt's explicit instruction, I did NOT contort `GameAfkingModule` to satisfy the grep — the draw is in the correct place. The substantive properties are proven by isolated-body grep of `resolveAfkingBox` (above). The negative-assertion greps that DO matter for `GameAfkingModule` pass cleanly: `abi.encodePacked`=0, `_callTicketPurchase`=0, `_simulatedDayIndex`=0 in CODE, `MintModule`=0 in CODE, no real try/catch.

### Authentication gates
None.

---

## Issues Encountered

- **The architectural blocker (resolved via USER Option A):** documented above — the prior attempt correctly STOPPED; this wave starts clean and implements the authorized fix.
- **`PRICE_COIN_UNIT` duplicate-declaration compile error (resolved):** my first draft redeclared `PRICE_COIN_UNIT` as a module constant; it is already inherited from `DegenerusGameStorage:162` (`Identifier already declared`). Removed the local redeclaration — the bounty math uses the inherited constant (1000 ether), exactly as the standalone AfKing did. Clean compile after.
- **Standing mint-gate dependency on the advance self-call (ACCEPTED, not new):** `doWork`'s advance leg self-calls `advanceGame()` with `msg.sender == address(this)` (the Game), which has no mint history. The `_enforceDailyMintGate` (AdvanceModule:973) has the time-laddered bypass (**anyone after 30 min**), so the self-call passes after the daily 30-min window — exactly how the standalone AfKing's `GAME.advanceGame()` worked (msg.sender = AfKing, non-participant). 348-PLACEMENT-DECISION §5 ACCEPTED this standing dependency with ZERO new gate code. Unchanged by this wave.

## Known Stubs

None. The open-pass, the `resolveAfkingBox` entrypoint, and the router are live logic. `autoBuy(count)`'s `count` is intentionally inert (ABI-parity with the relocated AfKing surface; the process chunk budget lives in the AdvanceModule STAGE per 349-05) — documented, not a stub.

## Threat Flags

None new. The wave stays within the plan's threat register:
- **T-349-04-SEED** (outcome steer): mitigated — `resolveAfkingBox` seed is `abi.encode` (NOT the PRESALE `abi.encodePacked`) from the FROZEN stamped `day` (FREEZE-03); no open-time day lever, no `_simulatedDayIndex` in the seed.
- **T-349-04-FRZ** (score/baseLevel manipulation): mitigated — `baseLevel`/`activityScore` are the stamped (FROZEN) `baseLevelPlus1-1`/`scorePlus1-1` (D-348-07); the sole residual live-read is the EV-cap clamp.
- **T-349-04-DBL** (double EV draw): mitigated — exactly one `_applyEvMultiplierWithCap` RMW at open keyed `[player][level+1]`; the buy-time write is bypassed (process stamps only); no `_callTicketPurchase`/MintModule path in the module.
- **T-349-04-DOPEN** (double-open): mitigated — monotonic `lastOpenedIndex` (open only if `stampIndex > lastOpenedIndex`, marker advanced effects-first).
- **T-349-04-HAZ** (two-route contention): mitigated — the BOX-05 reconciliation above (shared 10-ETH budget = one intended per-level cap with one RMW each; write-once word; producer→consumer stamp; disjoint human per-index state).
- **T-349-04-FARM** (bounty farming): mitigated — the OPEN leg's `OPEN_KNEE` work-scaled pro-rate (single-box = 0.2×, below gas); the advance/process bounty is `2×·mult` once-per-day-advance (gated by `advanceDue` + the day marker; `mult` only rewards genuine stall); payment is deferred `creditFlip` (flip-credit, not `mintForGame`).
- **T-349-04-SC** (package installs): N/A — Solidity edits only, no package-manager installs.

## Next Phase Readiness

- **349-05 (AdvanceModule STAGE)** is unblocked: the open-pass + router consume the stamp `processSubscriberStage` produces; `doWork`'s advance leg re-enters `advanceGame`, which 349-05 will extend with the STAGE call (`processSubscriberStage(epochIndex, processDay, maxCount)`) + the `subsFullyProcessed`/`_subCursor` no-interleave gate + the `requestLootboxRng` no-interleave guard. The PLACE-02 process bounty rides the advance bounty `2×·mult` already wired in `doWork`.
- **350 GAS** owns the `BOUNTY_ETH_TARGET` deploy-param + the `OPEN_BATCH` flat-budget re-measurement (both carried-unchanged here; the in-context SLOADs from the relocation are a natural consequence, no dedicated gas pass pulled forward).
- **351 TST** owns the test-ABI migration (incl. the standalone AfKing surface + the new `resolveAfkingBox`).
- **Contract-commit gate:** all edits UNCOMMITTED — the orchestrator owns the single batched-diff commit after the USER approval. The authoritative whole-diff `forge build --sizes` is the orchestrator's.

## Self-Check: PASSED

- `contracts/modules/DegenerusGameLootboxModule.sol` — `resolveAfkingBox` present (external; `abi.encode` stamped-day seed; `_rollTargetLevel(baseLevel,seed)` from the frozen baseLevel; exactly one `_applyEvMultiplierWithCap(player, currentLevel, ...)`; `_resolveLootboxCommon(...false,false,0,0)`). ✓
- `contracts/interfaces/IDegenerusGameModules.sol` — `resolveAfkingBox` selector declared in `IDegenerusGameLootboxModule` (matching signature). ✓
- `contracts/modules/GameAfkingModule.sol` — part-B present: `_openAfkingBox` (monotonic `lastOpenedIndex` guard + delegatecall to `resolveAfkingBox` with the stamped fields, `amount` widened) + `_afkingBoxReady` + `_autoOpen` (`_subOpenCursor` walk, rngLock/liveness entry-gate, wrap-reset) + `doWork`/`autoBuy`/`autoOpen` + the PLACE-02 bounty (advance `2×·mult`, open `OPEN_KNEE` pro-rate, `creditFlip`). ✓
- Plan `<verify>` sentinels: Task-3 **ROUTER+BOUNTY-CREDITFLIP** ✓; Task-1/Task-2 substantive acceptance MET in `resolveAfkingBox` (the documented verify-deviation — draw in the LootboxModule, one source of truth). ✓
- No real try/catch (D-348-04 no-valve) ✓; no GAS-01/02/03 work pulled ✓; `_callTicketPurchase`/`MintModule`/`_simulatedDayIndex` = 0 in CODE ✓.
- Self-build `forge clean && forge build --skip "test/**" --skip "*.t.sol"` → **Compiler run successful** (0 errors; 5 advisory `unsafe-typecast` lints = accepted repo convention, 1 new at L903 = the SAFE `_subOpenCursor` cast). ✓
- `.planning/phases/349-…/349-04-SUMMARY.md` — this file (written, exists on disk; `.planning/phases/` is gitignored, consistent with 349-01/02/03). ✓
- **No commit hashes** — by design (contract-boundary hold; the orchestrator owns the single batched-diff commit gate after the USER approval). HEAD unchanged (`60a4b5b5`). **NO git mutation ran** (no commit/add/rm/stash/reset/checkout/restore). `AfKing.sol` + `DegenerusGameAdvanceModule.sol` byte-untouched (349-05/06 scope). STATE.md / ROADMAP.md NOT updated by me (per `<sequential_execution>`; the pre-existing STATE.md `M` is the orchestrator's). ✓

---
*Phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code-*
*Plan: 04 · Completed: 2026-05-31*
