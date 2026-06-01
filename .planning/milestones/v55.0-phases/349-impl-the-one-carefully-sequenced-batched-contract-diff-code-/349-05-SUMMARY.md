---
phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code-
plan: 05
subsystem: game-resident-consumers (the TERMINAL wave — AdvanceModule STAGE + FREEZE-02 guards + interfaces + Game dispatch stubs + AfKing DISSOLVE + Vault/sDGNRS retarget + ARCH-04 build/size gate)
tags: [arch-03, arch-04, revert-02, freeze-02, place-01, d-348-01, d-348-02, d-348-03, d-348-04, no-valve, afking-dissolve, sub-02-self-consent, sub-09-retarget]
requires:
  - "349-01 applied (R1 claimAffiliateDgnrs → BingoModule reclaim + the thin Game stub — uncommitted)"
  - "349-02 applied (the REVISED DegenerusGameStorage.sol: Sub 5-field stamp + uint96 amount, _subOf/_subscribers/_subscriberIndex, uint16 _subCursor/_subOpenCursor, subsFullyProcessed — uncommitted)"
  - "349-03 applied (GameAfkingModule part A: subscribe/setters + processSubscriberStage(epochIndex,processDay,maxCount) — uncommitted)"
  - "349-04 applied (GameAfkingModule part B: open-pass + doWork/autoBuy/autoOpen router + resolveAfkingBox in the LootboxModule + its interface selector — uncommitted)"
provides:
  - "the afking process STAGE inserted in advanceGame immediately before rngGate (new-day path only, D-348-01 required-path) — drives GameAfkingModule.processSubscriberStage via GAME_AFKING_MODULE delegatecall across _subCursor (BUY_BATCH-style SUB_STAGE_BATCH=50), authoring the subsFullyProcessed/_subCursor uniform-epoch chunk gate (FREEZE-02b: LR_INDEX read ONCE at pass start)"
  - "the requestLootboxRng no-interleave guard (revert while !subsFullyProcessed, mirroring the :1093 reroll-block) — FREEZE-02c, the load-bearing D-348-02 obligation; the two index-advance sites now both sit OUTSIDE/AFTER the STAGE"
  - "the game-over-routing-unblocked VERIFICATION (REVERT-02 class C, no-valve): _handleGameOverPath runs+returns at :182/:187 BEFORE the do/while STAGE block — the STAGE is NOT on the game-over path (no edit needed)"
  - "the per-day reset of subsFullyProcessed/_subCursor in _swapTicketSlot (alongside ticketsFullyProcessed) — the canonical once-per-day reset cadence"
  - "the IGameAfkingModule interface (subscribe/4 setters/doWork/autoBuy/autoOpen/processSubscriberStage) so the Game stubs + the AdvanceModule STAGE call resolve against a real ABI"
  - "ContractAddresses.GAME_AFKING_MODULE (mirrors GAME_BINGO_MODULE — the delegatecall target)"
  - "7 Game-hosted afking dispatch stubs in DegenerusGame.sol (subscribe + 4 setters + doWork + autoBuy; claimBingo-shaped, delegatecall GAME_AFKING_MODULE, msg.sender preserved) — the canonical entrypoints"
  - "ARCH-04 FINAL verification: DegenerusGame runtime = 23,846 B < 24,576 (730 B margin) with all 7 stubs added — NO size levers (R2/R3/reserve) needed"
affects:
  - contracts/modules/DegenerusGameAdvanceModule.sol
  - contracts/storage/DegenerusGameStorage.sol
  - contracts/interfaces/IDegenerusGameModules.sol
  - contracts/ContractAddresses.sol
  - contracts/DegenerusGame.sol
  - "contracts/AfKing.sol (DISSOLVED → 58 B empty tombstone; the relocated mutating surface + state + helpers + events + errors + constants + imports DELETED — Task 3c, USER-decided option b)"
  - "contracts/DegenerusVault.sol (the SUB-09 self-subscriber retargeted afKing.subscribe → gamePlayer.subscribe; orphan IAfKingSubscribe interface + afKing handle removed; subscribe added to IDegenerusGamePlayerActions — Task 3c)"
  - "contracts/StakedDegenerusStonk.sol (the SUB-09 self-subscriber retargeted afKing.subscribe → game.subscribe; orphan IAfKingSubscribe interface + afKing handle removed; subscribe added to IDegenerusGamePlayer — Task 3c)"
tech-stack:
  added: []
  patterns:
    - "in-context required-path STAGE: the AdvanceModule delegatecalls GAME_AFKING_MODULE.processSubscriberStage so the module runs in the Game's storage (the relocated set / cursors / Sub stamps); mirrors the existing _distributeYieldSurplus delegatecall-helper shape"
    - "Game-hosted dispatch stubs preserve msg.sender via delegatecall — the consent gate (SUB-02/OPENE-04) + the doWork bounty payee read the REAL caller (the reason the body must run in the Game's context, identical to the claimBingo / claimAffiliateDgnrs stub rationale)"
    - "FREEZE-02 uniform-epoch: LR_INDEX read ONCE at STAGE pass start + passed as epochIndex; the no-interleave guard blocks the only mid-pass index-advance lever (requestLootboxRng) while !subsFullyProcessed"
decisions:
  - "STAGE positioned at the post-ticket-gate / pre-rngGate seam inside the new-day do/while (after :270 ticketsFullyProcessed close, before the bonusFlip/rngGate at :274+) — exactly the D-348-01 / PLACEMENT §3a insertion point"
  - "per-day reset of subsFullyProcessed/_subCursor lands in _swapTicketSlot (the SAME canonical per-day reset point as ticketsFullyProcessed) — fires once/day at the RNG request; same-cycle STAGE re-entry is a cheap skip-walk via the per-sub lastAutoBoughtDay >= processDay idempotency guard (built in 349-03), so no double-stamp / double-debit"
  - "drained-vs-partial decided by re-reading _subCursor >= _subscribers.length after processSubscriberStage (the callee persists _subCursor itself + shrinks the set via swap-pop, so this is the exact terminal test) — break STAGE_SUBS_WORKING + return mult on partial, set subsFullyProcessed=true at cursor end"
  - "SUB_STAGE_BATCH = 50 (matches the relocated AfKing BUY_BATCH; ≈262k gas/buy → ≈13.1M < 16.7M) — the BUY_BATCH-style per-call chunk budget the STAGE supplies to processSubscriberStage"
  - "the afking autoOpen is NOT re-exposed as a Game dispatch stub: the Game already has autoOpen(uint256) (the HUMAN box-open, :1737) and the selectors would COLLIDE — the afking box-open is reached through doWork's router (the module's standalone autoOpen remains module-internal)"
  - "ARCH-03 RESOLVED — option b (DISSOLVE): the USER decided the dissolve-vs-shim fork in favor of dissolution. AfKing's relocated mutating surface is DELETED (a forwarder hosted on AfKing is semantically broken — msg.sender would become AF_KING, breaking SUB-02 self-consent + mis-crediting the doWork bounty), and the two production self-subscribers (Vault/sDGNRS) retarget directly to GAME.subscribe (self-consent: subscriber == msg.sender). This matches PLAN-V55 §74 ('AF_KING address dissolves; the keeper calls game.doWork()')"
  - "AfKing.sol reduced to a 58 B empty tombstone (NOT deleted): keeps the pinned ContractAddresses.AF_KING resolving to a deployed artifact for the two now-dead-but-harmless historical references (the orphan batchPurchase gate at DegenerusGame.sol:1972 + the onlyFlipCreditors AF_KING allow-list entry at BurnieCoinflip.sol:201) — both unreachable in the live flow post-dissolve, both left UNTOUCHED (out of declared scope; churning them would touch unrelated mint/coinflip wiring)"
  - "AF_KING address constant + the two dead gates LEFT IN PLACE (harmless): the task permits leaving ContractAddresses.AF_KING since the live afking buy now runs in-context (GameAfkingModule's afkingFunding/claimablePool debit, NOT the external AF_KING-gated batchPurchase) and the bounty creditFlip runs with msg.sender == GAME (the module is GAME-resident), so neither dead gate is on a live path"
metrics:
  duration: ~95m
  completed: 2026-05-31
  tasks_completed: "4 of 4 (Tasks 1, 2, 3a, 3b, 3c, 4 ALL DONE — Task 3c completed via USER-decided dissolve)"
  files_modified: 8
---

# Phase 349 Plan 05: TERMINAL CONSUMER (AdvanceModule STAGE + FREEZE-02 guards + interfaces + Game dispatch stubs + ARCH-04 gate) Summary

**One-liner:** Inserted the D-348-01 required-path afking process STAGE in `advanceGame` immediately before `rngGate` (new-day path only) — authoring the `subsFullyProcessed`/`_subCursor` uniform-epoch chunk gate (FREEZE-02b: `LR_INDEX` read ONCE at pass start) driving `GameAfkingModule.processSubscriberStage` via a `GAME_AFKING_MODULE` delegatecall (BUY_BATCH-style) — plus the `requestLootboxRng` no-interleave guard (FREEZE-02c / D-348-02, mirroring the `:1093` reroll-block), the game-over-routing-unblocked verification (REVERT-02 class C, no-valve — `_handleGameOverPath` returns at `:187` before the STAGE), the `IGameAfkingModule` interface, `ContractAddresses.GAME_AFKING_MODULE`, and the 7 Game-hosted afking dispatch stubs (subscribe + 4 setters + doWork + autoBuy, claimBingo-shaped, msg.sender preserved). **Task 3c is now DONE via the USER-decided ARCH-03 fork — option b (DISSOLVE):** `AfKing.sol` is collapsed to a 58 B empty tombstone (the relocated subscribe/setters/`doWork`/`autoBuy`/`autoOpen`/`_resolveBuy`/open-logic + the standalone subscriber set/cursors + all now-dead state/events/errors/constants/imports DELETED), and the two production self-subscribers (`DegenerusVault` + `StakedDegenerusStonk`) are RETARGETED from `afKing.subscribe(...)` to the GAME directly (`gamePlayer.subscribe(...)` / `game.subscribe(...)`, same 6 args, self-consent intact: subscriber == address(this) == msg.sender). **`forge build` is CLEAN across the whole batched 349 diff (now incl. the dissolved AfKing + retargeted Vault/sDGNRS)** and **DegenerusGame = 23,846 B < 24,576 (730 B margin)** — ARCH-04 satisfied, NO size levers needed (AfKing dropped 9,780 → 58 B). All edits UNCOMMITTED; HELD at the contract-commit boundary.

---

## ⛔ Git posture — NOTHING COMMITTED (mandatory; the executor's hard constraint)

**NO git mutation ran** — no `git commit`, `git add`, `git rm`, `git stash`, `git reset`, `git checkout -- <file>`, or `git restore`. The single batched 349 contract diff is HELD for explicit USER approval; the ORCHESTRATOR owns that commit gate. Per the project #1 rule, the ONLY action needing approval is committing `contracts/*.sol`. Only read-only `git diff`/`git status`/`git log` + `grep`/read + `forge build` / `forge build --sizes` (the gate) were used. This SUMMARY is written with the Write tool and left **uncommitted**.

`git status --short` (read-only, end of plan):
```
 M .planning/STATE.md                                  (orchestrator-owned — UNTOUCHED by me)
 M contracts/AfKing.sol                                 (THIS plan, Task 3c — DISSOLVED to a 58 B tombstone)
 M contracts/ContractAddresses.sol                     (THIS plan — GAME_AFKING_MODULE)
 M contracts/DegenerusGame.sol                          (wave 1 R1 + THIS plan's 7 afking stubs + import)
 M contracts/DegenerusVault.sol                         (THIS plan, Task 3c — self-sub retarget → gamePlayer.subscribe)
 M contracts/StakedDegenerusStonk.sol                   (THIS plan, Task 3c — self-sub retarget → game.subscribe)
 M contracts/interfaces/IDegenerusGameModules.sol       (waves 1/4 + THIS plan's IGameAfkingModule)
 M contracts/modules/DegenerusGameAdvanceModule.sol     (THIS plan — STAGE + FREEZE-02 guards + helper)
 M contracts/modules/DegenerusGameBingoModule.sol       (wave 1 — UNTOUCHED)
 M contracts/modules/DegenerusGameLootboxModule.sol     (wave 4 — UNTOUCHED)
 M contracts/storage/DegenerusGameStorage.sol           (wave 2 + THIS plan's per-day reset)
 M scope.txt                                            (pre-existing — UNTOUCHED)
?? contracts/modules/GameAfkingModule.sol               (waves 3/4 — UNTOUCHED)
```
`contracts/AfKing.sol`, `contracts/DegenerusVault.sol`, `contracts/StakedDegenerusStonk.sol` are now `M` (Task 3c — the USER-decided dissolve + the two self-subscriber retargets). HEAD unchanged (`60a4b5b5`). **NO git mutation ran** — every change is via Edit/Write; only read-only `git status`/`git diff`/`git rev-parse` + `grep` + `forge clean`/`forge build`(`--sizes`) were used.

---

## Re-pin attestation (inherited; re-grepped live)

This plan touches `DegenerusGameAdvanceModule.sol` + `DegenerusGameStorage.sol` (both re-grepped live, post-wave) + the interfaces + `ContractAddresses.sol` + `DegenerusGame.sol`. The load-bearing AdvanceModule anchors were re-pinned LIVE this plan (line numbers below are the post-wave live lines, NOT the stale `20ca1f79`/SPEC lines):
- `_handleGameOverPath` call `:182`, `return 0` (gameover) `:187` — BEFORE the STAGE.
- `_enforceDailyMintGate(...)` call `:191` — inherited, ZERO new gate code.
- mid-day same-day path `:194-224` — returns before the do/while (the STAGE never runs mid-day).
- the do/while block start `:245`; the daily ticket-drain gate `:247-270`; `ticketsFullyProcessed = true` close `:269`.
- the STAGE insertion seam — between the ticket-gate close (`:270`) and the `bool bonusFlip` / `rngGate(` at the post-STAGE `:274`-equivalent.
- `requestLootboxRng()` def `:1089` (post-wave); the `LR_MID_DAY` reroll-block to mirror `:1093`; the mid-day index advance `:1162`; the daily advance (in `_finalizeRngRequest`) `:1702`.
- `_swapTicketSlot` (the per-day reset point) — `DegenerusGameStorage.sol`.
- `subsFullyProcessed` / `_subCursor` (uint16) — `DegenerusGameStorage.sol` (349-02).

---

## Task 1 — INSERT the process STAGE before rngGate + AUTHOR the subsFullyProcessed/_subCursor chunk gate (FREEZE-02b, D-348-01, D-348-03) — DONE

**Inserted** the chunked process STAGE in `DegenerusGameAdvanceModule.sol`, inside the new-day `do { … } while` block, **AFTER** the daily ticket-drain gate (`ticketsFullyProcessed = true; }`) and **BEFORE** the `bool bonusFlip` / `rngGate(` call — exactly the D-348-01 / PLACEMENT §3a `:272-273`-before-`:274` insertion point. New-day path ONLY (the mid-day same-day path `:194` returns earlier, so the STAGE never runs mid-day). It inherits `_enforceDailyMintGate` (`:191`) with **ZERO new gate code** (D-348-03).

**The STAGE (FREEZE-02b uniform epoch):**
```
if (!subsFullyProcessed) {
    if (_subscribers.length != 0) {
        uint48 epochIndex = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)); // read ONCE
        _runSubscriberStage(epochIndex, day);                              // delegatecall the module
        if (_subCursor < _subscribers.length) { stage = STAGE_SUBS_WORKING; break; } // partial drain
    }
    subsFullyProcessed = true;   // cursor at set end (or empty) → fall through to rngGate
}
```
- **Uniform epoch (FREEZE-02b):** `LR_INDEX` is read ONCE at pass start into `epochIndex` and passed to `processSubscriberStage`, which stamps every sub in the day's STAGE to that SAME value. The index only advances at the RNG request (inside `rngGate`, strictly AFTER this STAGE) and the no-interleave guard (Task 2) blocks the only mid-pass advance lever — so the stamped index has no committed word at process (the load-bearing freeze property).
- **Partial-drain discipline (mirrors `ticketsFullyProcessed` `:196/:247/:269` + `STAGE_TICKETS_WORKING` `:216-218/:264-266`):** `break` + return `mult` while `!subsFullyProcessed` (the new `STAGE_SUBS_WORKING = 11` partial-drain status), set `subsFullyProcessed = true` ONLY at cursor end, then fall through to `rngGate`.
- **Drained-vs-partial test:** `_subCursor < _subscribers.length` after the call. `processSubscriberStage` persists `_subCursor` itself and shrinks `_subscribers` via swap-pop, so this is the exact terminal condition.
- **The delegatecall** runs via a new private helper `_runSubscriberStage(epochIndex, processDay)` — mirrors the existing `_distributeYieldSurplus` delegatecall-helper shape (`abi.encodeWithSelector(IGameAfkingModule.processSubscriberStage.selector, epochIndex, processDay, SUB_STAGE_BATCH)` to `GAME_AFKING_MODULE`, `_revertDelegate` tail). The module runs IN the Game's storage (the relocated set / cursors / Sub stamps live in `DegenerusGameStorage`) — the same-context lesson.
- **SUB_STAGE_BATCH = 50** (BUY_BATCH-style; ≈262k gas/buy → ≈13.1M < 16.7M advance-chain ceiling).

**Per-day reset (the SPEC's "mirror ticketsFullyProcessed"):** `subsFullyProcessed = false; _subCursor = 0;` added to `_swapTicketSlot` (`DegenerusGameStorage.sol`), alongside `ticketsFullyProcessed = false`. `_swapTicketSlot` fires once per day at the RNG request (`_swapAndFreeze` → `:283` on the `rngWord == 1` branch) — the canonical per-day reset cadence. A same-cycle STAGE re-entry (the reset fires in the SAME call that the STAGE set `true`, so RNG-arrival calls re-enter the STAGE) is a cheap **skip-walk**: every already-stamped sub hits the per-sub `lastAutoBoughtDay >= processDay` idempotency guard (built into `processSubscriberStage` at 349-03) → skipped, no re-stamp / no re-debit. A wallet that subscribed mid-cycle binds to the (then-advanced) future index, which has no committed word → freeze-safe; the no-interleave guard still holds.

**Verify:** `subsFullyProcessed` + `_subCursor` present in the AdvanceModule and positioned BEFORE the first `rngGate(` call (new-day path), after the ticket gate + the inherited `_enforceDailyMintGate`. The STAGE reads `LR_INDEX` once and drives `processSubscriberStage` via the `GAME_AFKING_MODULE` delegatecall. ✅

## Task 2 — AUTHOR the requestLootboxRng no-interleave guard (FREEZE-02c, D-348-02) + VERIFY game-over routing unblocked (REVERT-02 class C, no-valve) — DONE

**(a) The no-interleave guard (FREEZE-02c — the load-bearing D-348-02 obligation):** added an early `if (!subsFullyProcessed) revert E();` to `requestLootboxRng` (`:1089`), placed immediately after the existing `LR_MID_DAY` reroll-block (`:1093`) it mirrors. While the afking process STAGE has not drained the set this cycle (`!subsFullyProcessed`), the mid-day index-advance (`:1162`) is blocked. This removes the only lever by which a separate-tx `requestLootboxRng` could advance `LR_INDEX` mid-STAGE (so a sub stamped after the advance would bind to an index whose word is requested in the same flow — collapsing the pre-RNG separation). With it, the two index-advance sites — `requestLootboxRng` `:1162` (mid-day) and `_finalizeRngRequest` `:1702` (daily) — both sit OUTSIDE/AFTER the STAGE: the daily advance fires downstream of `rngGate(:274)` after the STAGE; the mid-day advance is blocked for the pass duration. `subsFullyProcessed` was CONFIRMED-NEW (349 authors it).

**(b) Game-over routing VERIFIED unblocked (REVERT-02 class C, no-valve, D-348-04) — NO EDIT NEEDED:**
- `_handleGameOverPath` is called at `advanceGame:182` (inside the `if (!inJackpot && !lastPurchase)` block).
- When it returns `goReturn == true` (i.e. `gameOver` set, OR `_livenessTriggered()` — the ≥120-day-dead terminal state), `advanceGame` `emit Advance(goStage, lvl); return 0;` at **`:186-187`** — BEFORE the new-day `do { … } while` block (`:245`) where the STAGE lives (`~:272`).
- Therefore the STAGE is structurally OFF the game-over path: a ≥120-day-dead terminal state ALWAYS routes to game-over at `:182/:187` and never reaches the afking STAGE → the STAGE can NEVER block game-over routing. (Class C is absorbed by the game ending, NOT by catching per-sub.)

**⚠ NO try/catch valve added anywhere (D-348-04 no-valve):** my additions contain ZERO `try`/`catch`. The STAGE delegatecall propagates reverts via `_revertDelegate` (FAIL LOUD — a class-B `claimablePool -=` underflow in `processSubscriberStage` propagates, never masked); class C is terminal (verified above). See "Verify-deviation" below re: the two PRE-EXISTING infra `catch` sites.

## Task 3 — Interfaces (3a) + Game-hosted dispatch stubs (3b) + AfKing DISSOLVE & Vault/sDGNRS retarget (3c) — ALL DONE

### 3a — IGameAfkingModule interface (DONE)
Added `interface IGameAfkingModule` to `contracts/interfaces/IDegenerusGameModules.sol` (after the BingoModule interface) declaring the relocated mutating ABI: `subscribe` (payable, 6 params), `setDailyQuantity` / `setDrainGameCreditFirst` / `setMode` / `setReinvestPct`, `doWork` / `autoBuy(uint256)` / `autoOpen(uint256)`, and `processSubscriberStage(uint48 epochIndex, uint32 processDay, uint256 maxCount) returns (uint256 processed)`. Signatures matched VERBATIM against `GameAfkingModule.sol` (349-03/04). This resolves the AdvanceModule STAGE call (`IGameAfkingModule.processSubscriberStage.selector`) + the Game dispatch stubs.

### ContractAddresses.GAME_AFKING_MODULE (DONE)
Added `address internal constant GAME_AFKING_MODULE = address(0xaf6109dE6e7eC52e4eaE6Cbb1Feae8e4D4db1f61);` mirroring `GAME_BINGO_MODULE` (a deploy-patched placeholder, EIP-55 checksummed — the deploy pipeline predicts + patches these). This is the delegatecall target for both the AdvanceModule STAGE and the Game stubs.

### 3b — 7 Game-hosted afking dispatch stubs (DONE)
Added to `DegenerusGame.sol` (after the `claimBingo` stub), each shaped EXACTLY like `claimBingo` (`:323-339`) / `claimAffiliateDgnrs` (`:1540`): selector + `abi.encodeWithSelector(args)` + `GAME_AFKING_MODULE.delegatecall(...)` + `if (!ok) _revertDelegate(data);`:
- `subscribe(...)` **payable** (the consent gate + the msg.value → afkingFunding credit run in-context), `setDailyQuantity`, `setDrainGameCreditFirst`, `setMode`, `setReinvestPct`, `doWork()`, `autoBuy(uint256)` — **7 stubs**.
- **Why Game-hosted (carry #1):** the afking subscriber set / cursors / Sub stamps live in the GAME's storage (`DegenerusGameStorage`), so the module MUST run in the Game's context. `delegatecall` PRESERVES `msg.sender`, so the SUB-02/OPENE-04 consent gate (`operatorApprovals[subscriber][msg.sender]`) and the `doWork` bounty payee (`creditFlip(msg.sender, …)`) read the REAL caller. These are the canonical entrypoints (the exact rationale of the existing claimBingo/claimAffiliateDgnrs stubs). `IGameAfkingModule` added to the Game's import block.
- **⚠ The afking `autoOpen` is NOT re-exposed as a Game stub — SELECTOR COLLISION:** the Game already has `autoOpen(uint256) returns (uint256)` (the HUMAN box-open, `:1737`); the afking `autoOpen(uint256)` has the IDENTICAL selector → a duplicate definition. The afking box-open is reached through `doWork`'s router (the module's standalone `autoOpen` remains module-internal). Recorded for the verifier / 351 TST.

### 3c — AfKing.sol DISSOLVE + the two production self-subscriber retargets (USER-DECIDED option b) — DONE
The prior run SURFACED the dissolve-vs-shim fork as a Rule-4 checkpoint (recommending option b). **The USER decided: option b — DISSOLVE AfKing + retarget the callers.** Executed:

**(1) `contracts/AfKing.sol` — DISSOLVED to a 58 B empty tombstone.** DELETED the entire relocated mutating surface + all now-dead supporting code (each grep-confirmed unused before removal):
- **Functions:** `subscribe`, `setDailyQuantity`, `setDrainGameCreditFirst`, `setMode`, `setReinvestPct`, `doWork`, `autoBuy`, `autoOpen`, `_autoBuy`, `_resolveBuy`, and the open logic (all relocated to `GameAfkingModule`, GAME-resident). Plus the views (`subscriptionOf`/`subscriberCount`/`subscriberAt`/`autoBuyProgress`) and the hand-inlined set helpers (`_addToSet`/`_removeFromSet`/`_currentDay`) — all dead once the surface + state left.
- **State:** the standalone subscriber set (`_subOf`, `_subscribers`, `_subscriberIndex`) + the packed `_autoBuyDay`/`_autoBuyCursor` cursor — the canonical set now lives in `DegenerusGameStorage` (349-02).
- **File-scope types:** the `IGame` / `ICoinflip` interfaces, the `Sub` struct, the `BatchBuy` struct, the `MintPaymentKind` enum, and the `ContractAddresses` import — grep-confirmed NO other contract imports any AfKing-scoped type (the only match was a self-referential comment).
- **Events / errors / constants / immutables:** `SubscriptionUpdated`/`PlayerSkipped`/`AutoBuyCompleted`/`SubscriptionExtendedFree`/`SubscriptionExpired`; the 8 custom errors; `TICKET_SCALE`/`PRICE_COIN_UNIT`/`FLAG_*`/`BUY_BATCH`/`OPEN_BATCH`/the ratio+knee constants; the 3 economic immutables + the 3-arg constructor — all dead.
- **What REMAINS + why:** a minimal empty `contract AfKing {}` (58 B runtime). NOT deleted outright so the pinned `ContractAddresses.AF_KING` still resolves to a deployed artifact — two now-dead-but-harmless historical references name that address (the orphan `batchPurchase` gate at `DegenerusGame.sol:1972` and the `onlyFlipCreditors` AF_KING allow-list entry at `BurnieCoinflip.sol:201`). Both are unreachable in the live flow post-dissolve (see "AF_KING dead-surface analysis" below) and are LEFT UNTOUCHED — out of declared scope, and churning them would touch unrelated mint/coinflip wiring (no-churn discipline).

**(2) Retargeted the TWO production self-subscribers from AfKing → the GAME** (each self-subscribes: subscriber == address(this) == msg.sender to the Game ⇒ the SUB-02 self-consent path passes, NO operator approval needed):
- **`contracts/DegenerusVault.sol`** — retargeted `afKing.subscribe(address(this), true, false, 1, 0, address(0))` (was `:482`) → `gamePlayer.subscribe(address(this), true, false, 1, 0, address(0))` (now `:481`), reusing the Vault's existing `gamePlayer = IDegenerusGamePlayerActions(ContractAddresses.GAME)` handle (it already calls `gamePlayer.advanceGame()` / `openLootBox` / `withdrawAfkingFunding` directly). Added the 6-param `subscribe` to `IDegenerusGamePlayerActions` (after `advanceGame`). DELETED the orphan `IAfKingSubscribe` interface (was `:87-97`) + the `afKing` handle (was `:415-416`). SAME 6 args.
- **`contracts/StakedDegenerusStonk.sol`** — retargeted `afKing.subscribe(address(this), true, false, 1, 2, address(0))` (was `:384`) → `game.subscribe(address(this), true, false, 1, 2, address(0))` (now `:382`), reusing the existing `game = IDegenerusGamePlayer(ContractAddresses.GAME)` handle (it already calls `game.claimWhalePass(...)` in the same constructor). Added the 6-param `subscribe` to `IDegenerusGamePlayer` (after `advanceGame`). DELETED the orphan `IAfKingSubscribe` interface (was `:57-67`) + the `afKing` handle (was `:322-323`). SAME 6 args.

**Grep-confirmation of NO orphan callers:** post-edit `grep -rn "afKing\b\|IAfKingSubscribe" contracts/` returns EMPTY (exit 1); `grep -rn "\.subscribe(" contracts/` returns ONLY `DegenerusVault.sol:481` (`gamePlayer.subscribe`) + `StakedDegenerusStonk.sol:382` (`game.subscribe`) + the AfKing tombstone comment. NO contract imports an AfKing-scoped type. The two retargets are the sole live `subscribe` callers; the canonical entrypoint is now `GAME.subscribe` (the Task-3b dispatch stub → `GAME_AFKING_MODULE` delegatecall, msg.sender preserved).

**Why a forwarder hosted on AfKing was NOT used (confirms option b):** the relocated subscriber set / cursors / Sub stamps live in the GAME's storage. A normal `AfKing.subscribe(player,…) → GAME.subscribe(player,…)` external-call forwarder makes `msg.sender == AF_KING` inside the Game → the SUB-02 self-consent gate (`subscriber != msg.sender → require operatorApprovals[subscriber][msg.sender]`) would REVERT for any subscriber that has not operator-approved AF_KING, and `doWork`'s bounty would mis-credit AF_KING. So the surface is removed outright; the Game-hosted `delegatecall` stubs (Task 3b) are the msg.sender-correct canonical entrypoints.

### AF_KING dead-surface analysis (why the constant + the two gates are safe to leave)
Post-dissolve, the AF_KING address has NO live consumer:
- **The afking BUY** no longer flows through the external AF_KING-gated `GAME.batchPurchase` (the only caller of `batchPurchase` was `AfKing.sol:704`, now DELETED). The relocated `GameAfkingModule` does the buy IN-CONTEXT — `afkingFunding[funder] -= ev; claimablePool -= ev` directly (the "batchPurchase debit shape" as a pattern, GameAfkingModule:755), no external self-call. So the `if (msg.sender != ContractAddresses.AF_KING) revert E();` gate at `DegenerusGame.sol:1972` guards a now-unreachable external entrypoint (dead, harmless — left intact).
- **The afking BOUNTY** `creditFlip(msg.sender, …)` runs from the GAME-resident `GameAfkingModule` (`:953`) / `AdvanceModule` (`:933`), both inheriting `coinflip` from `DegenerusGameStorage` — so `msg.sender` at BurnieCoinflip is the **GAME** (already in `onlyFlipCreditors` via the `GAME` entry), NOT AF_KING. So the `sender != ContractAddresses.AF_KING` allow-list entry at `BurnieCoinflip.sol:201` is now dead (harmless — left intact).
The task explicitly permits leaving `ContractAddresses.AF_KING` in place (harmless); both dead gates are documented here and out of the declared edit scope (a later cleanup phase MAY prune them).

## Task 4 — BUILD GATE + SIZE + HOLD (ARCH-04 final) — DONE

**(a) BUILD GATE — CLEAN (re-run after the Task-3c dissolve).** `forge clean && forge build --skip "test/**" --skip "*.t.sol"` → **`Compiler run successful with warnings`**, exit 0 across the WHOLE batched 349 diff (waves 1–5, NOW INCLUDING the dissolved AfKing + the retargeted Vault/sDGNRS). The producer-before-consumer authoring held AND the dissolve introduced no dangling reference (the retargets resolve against `subscribe` newly declared on the Vault's `IDegenerusGamePlayerActions` + sDGNRS's `IDegenerusGamePlayer`; the orphan `IAfKingSubscribe`/`afKing` handles are gone). Zero hard errors (`grep -iE "^Error|Error \(|error\[[0-9]"` → NONE). The only warnings touching my new code are the accepted repo-wide `unsafe-typecast` convention; the `incorrect-shift` / `divide-before-multiply` / nightly-build advisories are ALL pre-existing (none point at my STAGE / guard / helper / stubs / dissolve / retargets — verified by line). `forge test` was NOT run; `test/` NOT touched (the test-ABI break — incl. `test/fuzz/AfKingSubscription.t.sol` + `test/gas/SweepPerPlayerWorstCaseGas.t.sol` which call the now-dissolved AfKing surface — is 351's charge).

**(b) ARCH-04 FINAL VERIFICATION — DegenerusGame < 24,576 with a comfortable margin, NO levers needed.** `forge build --sizes --skip "test/**" --skip "*.t.sol"` (authoritative, post-clean):

| Contract | Runtime (B) | Margin to 24,576 | < 24,576? |
|---|---|---|---|
| **DegenerusGame** | **23,846** | **730** | ✅ |
| **AfKing (DISSOLVED)** | **58** | **24,518** | ✅ (was 9,780 → −9,722 B) |
| GameAfkingModule | 7,706 | 16,870 | ✅ |
| DegenerusGameLootboxModule | 18,407 | 6,169 | ✅ |
| DegenerusGameAdvanceModule | 19,194 | 5,382 | ✅ |
| DegenerusGameBingoModule | 3,103 | 21,473 | ✅ |

- **DegenerusGame = 23,846 B (730 B margin)** with ALL 7 afking dispatch stubs added — UNCHANGED by the Task-3c dissolve (AfKing is a separate contract; collapsing it does not touch the Game's bytecode). The wave-1 R1 reclaim (`claimAffiliateDgnrs` → BingoModule) cleared the headroom exactly as planned (MEASURED baseline 24,358 / 218 B → R1 reclaim → + the 7 stubs → 23,846). This BEATS the SPEC's worst-case running-total (24,418).
- **AfKing collapsed 9,780 B → 58 B** (a 9,722 B reduction — the empty tombstone). Irrelevant to the EIP-170 gate (AfKing was never near 24,576), but confirms the dissolve removed the full relocated surface.
- **NO size levers pulled** — R2 (`previewSellFarFutureTickets`), the R3 wrapper (`playerActivityScore`), the reserve set (`decClaimable`/`getTickets`/`getDailyHeroWinner`), and the R3 caller-retarget are ALL untouched (not needed — the central-case headroom holds with margin to spare).

**(c) HOLD — NO COMMIT.** `forge build` clean + DegenerusGame 23,846 < 24,576. No `git commit` / `git add contracts/` was run. The diff is HELD at the contract-commit boundary; the orchestrator owns the single user-approval gate.

---

## ✅ ARCH-03 RESOLVED — Rule-4 architectural decision (the AfKing.sol dissolve-vs-shim fork)

**Type:** decision (architectural — Rule 4). **Outcome: option b — DISSOLVE (USER-DECIDED).**
The prior run SURFACED this fork as a Rule-4 checkpoint (recommending option b) because the SPEC self-contradicted (PLAN-V55 §74 "AF_KING dissolves" vs the 349-05 plan action "keep AfKing as a thin shim") AND a forwarder hosted on AfKing is semantically broken. **The USER chose option b — dissolve AfKing + retarget the callers.** The dissolve + the two retargets are now applied (Task 3c above); this section records the resolved decision rationale.

### The decision in one paragraph

The relocated subscriber set / cursors / Sub stamps live in the **GAME's** storage. A forwarder hosted on AfKing cannot reach that context correctly: a `delegatecall` would run the module in AfKing's storage (wrong context), and a normal external-call forwarder (`AfKing.subscribe(player,…) → GAME.subscribe(player,…)`) makes `msg.sender == AF_KING` inside the Game → the SUB-02 self-consent gate would REVERT for any subscriber that has not operator-approved AF_KING, and `doWork`'s bounty would mis-credit AF_KING. The **Game-hosted dispatch stubs (Task 3b)** ARE the msg.sender-correct canonical entrypoints (`delegatecall` preserves `msg.sender`). Once they exist, AfKing's surface is redundant, so option b dissolves it and moves the only two live external callers (the Vault/sDGNRS protocol-owned self-subs) directly to `GAME.subscribe(address(this),…)` — self-consent holds because `subscriber == address(this) == msg.sender`. This matches the design doc's stated intent (PLAN-V55 §74: *"AF_KING as a separate address: dissolves. The keeper calls game.doWork()"*).

### Why option b over the alternatives

- **(a) Thin external-call shim in AfKing** — REJECTED: semantically broken (msg.sender = AF_KING breaks the consent gate + the bounty payee). Would need a Game-side AF_KING trusted-forwarder special-case (new design, larger surface) to be correct.
- **(c) Game-side trusted forwarder** — REJECTED: new design (a Rule-4 in its own right), larger surface, not in the SPEC.
- **(d) Leave AfKing untouched** — REJECTED: compiles clean but leaves AfKing's surface redundant/orphaned (dead `_subOf` storage; two `subscribe` paths coexist), deferring ARCH-03's "resolve the dissolution question."

### What option b touched (vs. the originally-declared scope)

The dissolve necessarily edits TWO production contracts that were OUTSIDE the plan's declared `files_modified` (`DegenerusVault.sol`, `StakedDegenerusStonk.sol`) plus collapses `AfKing.sol`. This is tracked as the Rule-4 deviation below. **Consent semantics are UNCHANGED** — the Vault/sDGNRS self-subscriptions become direct `GAME.subscribe(address(this),…)` calls (self-consent, same 6 params), just retargeted. ZERO effect on DegenerusGame's size (23,846 B stays). See the "AF_KING dead-surface analysis" under Task 3c for why the residual `AF_KING` constant + the two now-dead gates are safe to leave intact.

---

## Deviations from Plan

**One Rule-4 architectural decision RESOLVED + applied (Task 3c — the AfKing dissolve + two out-of-scope retargets) + two expected verify-deviations + one collision-driven omission. Zero unauthorized behavior changes.**

1. **[Rule 4 — RESOLVED + APPLIED] The AfKing.sol dissolve (ARCH-03) + the two production self-subscriber retargets (OUT-OF-DECLARED-SCOPE edits, USER-authorized).** The dissolve-vs-shim fork (surfaced as a Rule-4 checkpoint by the prior run) was decided by the USER in favor of **option b — dissolve**. Applied: (i) `AfKing.sol` collapsed to a 58 B empty tombstone (the relocated mutating surface + standalone state + helpers + events + errors + constants + file-scope types + import DELETED); (ii) `DegenerusVault.sol` + `StakedDegenerusStonk.sol` — both OUTSIDE the plan's declared `files_modified` — retargeted from `afKing.subscribe(...)` to `gamePlayer.subscribe(...)` / `game.subscribe(...)` (same 6 args, self-consent intact), their orphan `IAfKingSubscribe` interfaces + `afKing` handles removed, `subscribe` added to the existing Game interfaces they already hold. The plan's original must_have "AfKing.sol collapses to ~8 thin delegatecall dispatch stubs" was NOT executed AS WRITTEN because that form is wrong (the relocated state lives in the GAME's storage, so an AfKing-hosted delegatecall/forwarder cannot preserve msg.sender) — the correct realization is the Game-hosted stubs (Task 3b) + this dissolve. The `AF_KING` constant + two now-dead gates (`DegenerusGame.sol:1972` batchPurchase, `BurnieCoinflip.sol:201` onlyFlipCreditors) are LEFT INTACT per the task's explicit permission (harmless; out of scope; a later cleanup MAY prune). Build re-verified clean + DegenerusGame still 23,846 B < 24,576.

2. **[Expected verify-deviation — the `} catch` count] Two PRE-EXISTING infra try/catch sites remain in the AdvanceModule** (`_stakeStEth` steth.submit resilience; `_tryRequestRng` VRF-rotation resilience) — both present at baseline `20ca1f79`. The plan's Task-2 verify greps `} catch` == 0; that would not match (2 pre-existing). These are UNRELATED to the D-348-04 no-valve concern (which is specifically NO try/catch around the afking process/open legs). My additions add ZERO try/catch — the `try {` count is 0, and the no-valve invariant for the afking STAGE holds (the STAGE delegatecall fails loud via `_revertDelegate`; class C is verified routing-unblocked). Documented, not a contortion (I did NOT remove the pre-existing infra try/catch).

3. **[Expected — selector collision] The afking `autoOpen` is not exposed as a Game stub** (only 7 of the ~8 surface functions become Game stubs) — the Game's existing human `autoOpen(uint256)` (`:1737`) has the identical selector. The afking box-open is reached through `doWork`'s router. The interface `IGameAfkingModule.autoOpen` is still declared (no collision in the interface). Documented for the verifier.

4. **[Mandated layout carry — already from prior waves] SUB_STAGE_BATCH=50, the uint16 cursors, the 5-field stamp** — folded as directed by the revised 349-02/03/04 layout, not discovered here.

### Authentication gates
None.

---

## Known Stubs

- The 7 Game-hosted afking dispatch stubs (`subscribe`/setters/`doWork`/`autoBuy`) are thin delegatecall dispatch stubs (the standard module-dispatch pattern, NOT placeholder/empty stubs) — they forward to the live `GameAfkingModule` body via the `GAME_AFKING_MODULE` delegatecall lane, msg.sender preserved. Live, reachable, behavior-preserving.
- **`AfKing.sol` is a deliberate 58 B empty tombstone** (post-dissolve) — it holds no logic and no state; it exists only so `ContractAddresses.AF_KING` resolves to a deployed artifact for two now-dead-but-harmless historical references (the orphan `batchPurchase` gate + the `onlyFlipCreditors` allow-list entry). This is intentional (the canonical afking surface is now `GAME.subscribe` / `GAME.doWork` etc. + the GAME-resident `GameAfkingModule`), NOT a placeholder awaiting wiring. The two dead gates are documented under Task 3c's "AF_KING dead-surface analysis" — a later cleanup phase MAY prune them + the constant.

---

## Threat Flags

None new. The wave stays within the plan's threat register:
- **T-349-05-FRZ** (reveal-then-steer): mitigated — FREEZE-02c no-interleave guard blocks the mid-day index advance while `!subsFullyProcessed`; the STAGE reads `LR_INDEX` once (uniform epoch); both advance sites sit AFTER the STAGE. (351 TST-01 proves it empirically.)
- **T-349-05-GO** (day-brick / no game-over): mitigated — REVERT-02 class C verified: `_handleGameOverPath` returns at `:187` before the STAGE block; the STAGE is off the game-over path; NO try/catch added (class B fails loud, class C terminal).
- **T-349-05-DANGLE** (broken build): mitigated — the whole batched 349 diff compiles clean (re-verified after the Task-3c dissolve); producer-before-consumer held AND the dissolve's retargets resolve (the orphan `IAfKingSubscribe`/`afKing` handles are gone, `subscribe` declared on the existing Game interfaces, no dangling reference; grep-confirmed no orphan AfKing callers).
- **T-349-05-CEIL** (deploy fails): mitigated — DegenerusGame 23,846 B < 24,576 (730 B margin) with all stubs added; ARCH-04 satisfied with NO levers.
- **T-349-05-SC** (package installs): N/A — Solidity edits + `forge build` only; no package-manager installs.

---

## Self-Check: PASSED (all 4 tasks DONE — Task 3c completed via the USER-decided dissolve)

- `contracts/modules/DegenerusGameAdvanceModule.sol` — exists; STAGE present (`subsFullyProcessed` + `_subCursor`) BEFORE `rngGate`, after the ticket gate + inherited mint-gate; `_runSubscriberStage` delegatecall helper; `requestLootboxRng` no-interleave guard (`if (!subsFullyProcessed) revert E();`); ZERO new try/catch; `STAGE_SUBS_WORKING` + `SUB_STAGE_BATCH` constants; `IGameAfkingModule` import. ✅
- `contracts/storage/DegenerusGameStorage.sol` — `subsFullyProcessed = false; _subCursor = 0;` per-day reset in `_swapTicketSlot`. ✅
- `contracts/interfaces/IDegenerusGameModules.sol` — `IGameAfkingModule` interface (subscribe/4 setters/doWork/autoBuy/autoOpen/processSubscriberStage) declared. ✅
- `contracts/ContractAddresses.sol` — `GAME_AFKING_MODULE` constant (EIP-55 checksummed). ✅
- `contracts/DegenerusGame.sol` — 7 afking dispatch stubs (subscribe + 4 setters + doWork + autoBuy), claimBingo-shaped, delegatecall `GAME_AFKING_MODULE`; `IGameAfkingModule` import. ✅
- `contracts/AfKing.sol` — DISSOLVED to a 58 B empty `contract AfKing {}` tombstone; the relocated mutating surface (subscribe/setters/`doWork`/`autoBuy`/`autoOpen`/`_autoBuy`/`_resolveBuy`/open-logic), the standalone subscriber set + cursor, all views/helpers, the file-scope `IGame`/`ICoinflip`/`Sub`/`BatchBuy`/`MintPaymentKind` types, the events/errors/constants/immutables/constructor, and the `ContractAddresses` import DELETED (each grep-confirmed unused). ✅
- `contracts/DegenerusVault.sol` — `afKing.subscribe(...)` retargeted → `gamePlayer.subscribe(...)` (same 6 args); orphan `IAfKingSubscribe` interface + `afKing` handle removed; 6-param `subscribe` added to `IDegenerusGamePlayerActions`. Self-consent intact (subscriber == address(this) == msg.sender). ✅
- `contracts/StakedDegenerusStonk.sol` — `afKing.subscribe(...)` retargeted → `game.subscribe(...)` (same 6 args); orphan `IAfKingSubscribe` interface + `afKing` handle removed; 6-param `subscribe` added to `IDegenerusGamePlayer`. Self-consent intact. ✅
- Orphan check: `grep -rn "afKing\b\|IAfKingSubscribe" contracts/` → EMPTY (exit 1); `grep -rn "\.subscribe(" contracts/` → ONLY `DegenerusVault.sol:481` + `StakedDegenerusStonk.sol:382` (the two retargets) + the AfKing tombstone comment. NO contract imports an AfKing-scoped type. ✅
- `forge build --skip "test/**" --skip "*.t.sol"` → **Compiler run successful** (exit 0, whole 349 diff INCL. the dissolved AfKing + retargets; zero hard errors); only accepted `unsafe-typecast` + pre-existing advisory warnings; none point at new code. ✅
- `forge build --sizes` → **DegenerusGame 23,846 B < 24,576 (730 B margin)** (unchanged by the dissolve); **AfKing 58 B** (was 9,780); touched modules (Lootbox 18,407 / GameAfking 7,706 / Advance 19,194) all < 24,576. ✅
- `forge test` NOT run; `test/` NOT touched (the AfKing-ABI test breaks are 351's charge). ✅
- **No commit hashes** — by design (contract-boundary hold; the orchestrator owns the single batched-diff commit gate after the USER approval). HEAD unchanged (`60a4b5b5`). **NO git mutation ran** (every change via Edit/Write; only read-only `git status`/`git diff`/`git rev-parse` + `grep` + `forge clean`/`forge build`). STATE.md / ROADMAP.md NOT updated by me (per `<sequential_execution>`; the pre-existing STATE.md `M` is the orchestrator's). ✅
- **Task 3c (AfKing dissolve + retargets)** — DONE via the USER-decided option b (dissolve). All 4 tasks complete; the whole batched 349 diff is applied, compiling, size-verified, and HELD at the contract-commit boundary. ✅

---
*Phase: 349-impl-the-one-carefully-sequenced-batched-contract-diff-code- · Plan: 05 · Completed (Tasks 1/2/3a/3b/3c/4): 2026-05-31 · Task 3c completed via the USER-decided ARCH-03 dissolve (option b).*
