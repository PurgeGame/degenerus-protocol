# Phase 351: TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas — Pattern Map

**Mapped:** 2026-05-31
**Files analyzed:** 18 (1 shared fixture · 15 AfKing/keeper corpus to adapt · 1 regression-baseline doc · the gas-harness instruments) + the NEW v55-proof targets
**Analogs found:** 18 / 18 (every target has a same-role in-repo analog)

> **Scope reminder (TST phase).** "Files created/modified" = `test/**/*.t.sol`, the shared fixture
> `test/fuzz/helpers/DeployProtocol.sol`, and `test/REGRESSION-BASELINE-v55.md`. **ZERO `contracts/*.sol`
> mutation** (`git diff 453f8073 HEAD -- contracts/` stays EMPTY throughout). All contract `file:line`
> below are READ-ONLY anchors for instrumentation, never edit sites.

---

## The five load-bearing call-site deltas (apply across the WHOLE adapted corpus)

These are the mechanical rewrites D-351-01 mandates. Every adapted file applies the subset it uses. The
old receiver was the standalone `AfKing` de-custody contract (`contracts/AfKing.sol`, **deleted**); the
new receiver is the game-resident path (delegatecall module `GameAfkingModule` reached through
`DegenerusGame`).

| # | OLD (deleted `AfKing` / keeper machinery) | NEW (game-resident `453f8073`) | Kind | Source anchor |
|---|-------------------------------------------|--------------------------------|------|---------------|
| Δ1 | `import {AfKing} from "../../contracts/AfKing.sol";` / `import {IGame} from ".../AfKing.sol";` | drop / repoint to the game type (`DegenerusGame`) + `IDegenerusGame*` interfaces | import | `DeployProtocol.sol:26`, `AfKingSubscription.t.sol:7`, `RedemptionStethFallback.t.sol:7` |
| Δ2 | `afKing.subscribe(player,drainFirst,useTickets,qty,reinvest,src)` | `game.subscribe(player,drainFirst,useTickets,qty,reinvest,src)` — **IDENTICAL 6-arg signature**, receiver-only swap | rename-receiver | new sig `GameAfkingModule.sol:234`, dispatch stub `DegenerusGame.sol:363` |
| Δ3 | `afKing.doWork()` (the rewarded router) | `game.mintBurnie()` | rename | `GameAfkingModule.sol:985`, stub `DegenerusGame.sol:390` |
| Δ4 | `afKing.autoBuy(N)` (the standalone buy clear) | **NO direct successor** — the per-sub buy folded into `advanceGame()`'s required-path STAGE (`processSubscriberStage` is internal, reached via a new-day `game.advanceGame()` or `mintBurnie()`'s advance leg). The open leg is `game.autoOpen(maxCount)`. | **SEMANTIC REMAP** | STAGE `DegenerusGameAdvanceModule.sol:305-312` → `_runSubscriberStage` `:754` → `processSubscriberStage(50)` `:759-761`; open `GameAfkingModule.sol:1023`/`DegenerusGame.sol:1787` |
| Δ5 | `afKing.poolOf(x)` / `afKing.withdraw(a)` / `afKing.subscriberCount()` / `afKing.subscriptionOf(x)` / `afKing.autoBuyProgress()` / `afKing.setDailyQuantity(0)` / `afKing.depositFor{v}(x)` / `afKing.unsubscribe()` | game-resident SLOADs / views — `game.afkingFundingOf(x)` (`DegenerusGame.sol:1579`), `game.withdrawAfkingFunding(a)` (`:1562`), `game.afkingSnapshot([..])` (`:2645`); **`subscriberCount`/`subscriptionOf`/`autoBuyProgress`/`setDailyQuantity`/`depositFor`/`unsubscribe` have NO game-exposed external view** → read `_subscribers.length` / `_subOf[x]` / cursors via `vm.load` pinned slots (the corpus already uses this idiom), or re-`subscribe(...,dailyQuantity=0)` to cancel | **REMAP + slot-read** | `_subscribers` `DegenerusGameStorage.sol:1914`, `_subOf` `:1902`, Sub struct `:1867`, cursors/`subsFullyProcessed` `:343` |

**Two runtime traps the compile-fix must also clear (not just the import):**
- `vm.readFile("contracts/AfKing.sol")` source-presence greps **throw at runtime** (file deleted). Repoint
  `AFKING_SRC` → `"contracts/modules/GameAfkingModule.sol"` in `KeeperRouterOneCategory.t.sol:88`,
  `KeeperLeversAndPacking.t.sol:88`. Re-derive every grepped token (the source moved + symbols renamed).
- The pinned-slot constants (`SUBOF_SLOT=1`, `SUBSCRIBER_INDEX_SLOT=3`, `AUTOBUY_SLOT=4`, the Sub byte
  offsets) are for the **standalone `AfKing` 4-slot layout** — they are WRONG for the game-resident `_subOf`
  on `DegenerusGameStorage`. **Re-derive every slot via `forge inspect storage` against `DegenerusGame`**
  before any `vm.store`/`vm.load` poke (the corpus's biggest silent-breakage risk).

---

## File Classification

| Target file | Role | Data Flow | Closest Analog | Match Quality | Adaptation load (dead refs) |
|-------------|------|-----------|----------------|---------------|------------------------------|
| `test/fuzz/helpers/DeployProtocol.sol` | test-fixture | deploy/wire | itself (in-place repair) + sibling module deploys | exact (self) | import + state var + deploy block (`:26`,`:70`,`:123-133`) |
| `test/fuzz/AfKingSubscription.t.sol` | test (fuzz) | event-driven / set-mutation | self → game-resident subscribe | role-match | import=1, afKing.=29, doWork=3, srcref=4 |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | test (fuzz) | CRUD (funding waterfall) | self → afkingFunding SLOAD | role-match | afKing.=39, srcref=2 |
| `test/fuzz/AfKingConcurrency.t.sol` | test (fuzz) | set-mutation (swap-pop) | self → STAGE/open cursor | role-match | afKing.=68, srcref=1 |
| `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` | test (fuzz) | differential (delta-audit) | self / KeeperRewardRouting | role-match | **subject = `batchPurchase`/`batchPurchaseForKeeper` (REMOVED) → D-351-02 candidate** |
| `test/fuzz/KeeperFaucetResistance.t.sol` | test (fuzz) | event-driven (bounty) | self → mintBurnie bounty | role-match | afKing.=11, doWork=19, srcref=8 |
| `test/fuzz/KeeperRewardRoutingSameResults.t.sol` | test (fuzz) | differential same-results | self → mintBurnie reward | role-match (PRIMARY differential template) | afKing.=11, doWork=5, srcref=2 |
| `test/fuzz/KeeperRouterOneCategory.t.sol` | test (fuzz) | event-driven (one-category) | self → mintBurnie router | role-match | afKing.=22, doWork=23, srcref=6 (+`vm.readFile`) |
| `test/fuzz/KeeperNonBrick.t.sol` | test (fuzz) | revert-free / non-brick | self → `_resolveBuy` REVERT-01 | role-match (PRIMARY revert-free template) | afKing.=35, srcref=2; **`batchPurchase` try/catch isolation = REMOVED surface** |
| `test/fuzz/RngLockDeterminism.t.sol` | test (fuzz) | freeze / determinism | self → stamped-day freeze | role-match (PRIMARY freeze template) | afKing.=4, doWork=4; has `vm.skip` blocks (17 skips) |
| `test/fuzz/RedemptionStethFallback.t.sol` | test (fuzz) | file-I/O / fallback | self → game-resident funding | partial | import=1, afKing.=1; **`AfKing.depositFor`/`poolOf`/`withdraw` custody-recovery = D-351-02 candidate** |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | test (gas) | gas marginal (per-open) | self → `_openAfkingBox` marginal | role-match (PRIMARY per-open gas template; has the CR-01 loop-N-divide) | (human box path → reframe) |
| `test/gas/KeeperLeversAndPacking.t.sol` | test (gas) | source-grep / packing | self → GameAfkingModule grep | role-match | doWork=1, srcref=5 (`vm.readFile`) |
| `test/gas/KeeperResolveBetWorstCaseGas.t.sol` | test (gas) | gas marginal (per-spin) | self (marginal idiom donor `:197-242`) | role-match | (degenerette path — light touch) |
| `test/gas/RouterWorstCaseGas.t.sol` | test (gas) | gas worst-case (router) | self → STAGE 16.7M ceiling | role-match (PRIMARY 16.7M-ceiling template) | afKing.=21, doWork=9, srcref=3 |
| `test/gas/SweepPerPlayerWorstCaseGas.t.sol` | test (gas) | gas per-player (sweep) | self → per-sub STAGE | role-match | afKing.=15, srcref=5 |
| `test/REGRESSION-BASELINE-v55.md` | doc (ledger) | record (BY-NAME) | `REGRESSION-BASELINE-v50.md` / `-v49.md` | exact (template) | new file |
| **NEW** TST-01..04 proof file(s) | test (fuzz+unit) | freeze / revert-free / set-mutation / differential | see §"NEW v55 Proofs" | role-match | new functions |
| **NEW** TST-06 gas-harness file | test (gas) | per-buy + per-open marginal | `KeeperOpenBoxWorstCaseGas` + `RouterWorstCaseGas` | role-match | new file (350 §6 gaps) |

---

## Pattern Assignments

### 1. `test/fuzz/helpers/DeployProtocol.sol` — Wave 0 (blocking; un-bricks the 64-file cascade)

**Analog:** itself (in-place repair) + the 10 sibling `new Degenerus*Module()` deploys already in the file.

**The break (lines 26 / 70 / 123-133):** imports + constructs the deleted standalone `AfKing`. `AfKing.sol`
no longer exists → the fixture (and via it, every dependent test) fails to compile.

**Current AfKing import (`:26`) — DELETE:**
```solidity
import {AfKing} from "../../../contracts/AfKing.sol";
```
**Current state var (`:70`) — DELETE (or replace with the module type):**
```solidity
AfKing public afKing;
```
**Current deploy block (`:123-133`) — DELETE the standalone deploy + the SUB-09 self-subscribe comments:**
```solidity
        // AfKing: 3-arg constructor (subCost, bounty, lootboxMin) ...
        afKing = new AfKing(5_000_000_000, 885_000_000, 10_000_000_000); // N+18 = nonce 23
        // Vault constructor calls COIN.vaultMintAllowance() + AfKing.subscribe() (SUB-09)
        vault = new DegenerusVault();                  // N+19 = nonce 24
        // Stonk constructor calls GAME.claimWhalePass() + AfKing.subscribe() (SUB-09 self-subscribe)
        sdgnrs = new StakedDegenerusStonk();           // N+20 = nonce 25
```

**The REPAIR — deploy `GameAfkingModule` as a delegatecall module (the EXACT shape the 10 siblings use,
`:92-101`):** the game-resident module takes **no constructor args** (like `mintModule`, `lootboxModule`,
…); it must land at the nonce that yields `ContractAddresses.GAME_AFKING_MODULE`
(`= 0xaf6109...`, `ContractAddresses.sol:35`). Mirror the sibling idiom:
```solidity
import {GameAfkingModule} from "../../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameBingoModule} from "../../../contracts/modules/DegenerusGameBingoModule.sol"; // also new slot (GAME_BINGO_MODULE :33)
// ...
GameAfkingModule public afkingModule;
DegenerusGameBingoModule public bingoModule;
// ...in _deployProtocol(), in DEPLOY_ORDER position:
afkingModule = new GameAfkingModule();   // no ctor args — a delegatecall module
bingoModule  = new DegenerusGameBingoModule();
```

**CRITICAL nonce-alignment work (the planner MUST reconcile):** the fixture deploys **10** game modules;
`ContractAddresses.sol` now lists **12** (`GAME_BINGO_MODULE` `:33` + `GAME_AFKING_MODULE` `:35` are NEW
slots). The live `scripts/lib/predictAddresses.js` `DEPLOY_ORDER` (`:21-45`) **still lists the old
standalone `AF_KING` at N+18** and has NO Bingo/Afking module entries — so the deploy-order script + the
fixture nonce sequence + `ContractAddresses.sol` must all be reconciled so `new GameAfkingModule()`'s
CREATE address equals `GAME_AFKING_MODULE`. (Comment at `DeployProtocol.sol:43`: "Address correctness
depends on patchForFoundry.js having patched ContractAddresses.sol before forge build." The
`scripts/lib/patchForFoundry.js` / `predictAddresses.js` pair is the source of truth the fixture mirrors —
the planner confirms whether the predicted-address tooling was already updated at `453f8073` or is part of
this repair.) **Precedent: v46 Phase 318 "fixture-repair un-bricked 533→532 tests" (CONTEXT D-351-03).**

**SUB-09 self-subscribe — ALREADY game-resident at `453f8073` (verified; do NOT re-wire):** the
Vault/SDGNRS constructors **already** call the game-resident path — `gamePlayer.subscribe(address(this),
true, false, 1, 0, address(0))` (`DegenerusVault.sol:481`) and `game.subscribe(address(this), true, false,
1, 2, address(0))` (`StakedDegenerusStonk.sol:382`) — and the off-path view is
`gamePlayer.withdrawAfkingFunding(gamePlayer.afkingFundingOf(address(this)))` (`DegenerusVault.sol:518`,
comment `:478` "v55.0 ARCH-03: the afking surface is GAME-resident; AfKing dissolved"). So the ONLY fixture
work is: (a) `new GameAfkingModule()` at the `GAME_AFKING_MODULE` nonce, (b) delete the standalone `AfKing`
deploy + state var + import, (c) fix the stale `:123-133` SUB-09 comments. The deploy ORDER must still place
the afking module + GAME **before** VAULT/SDGNRS so those constructor self-subscribes hit live code (they
pass `address(0)` per [[open-e-operator-approval-trust-boundary]]).

---

### 2. `test/fuzz/AfKingSubscription.t.sol` (test, set-mutation/event-driven)

**Analog:** self → game-resident subscribe path. **29 `afKing.` + 3 `doWork` + import + 4 srcref.**

**Imports (`:4-7`) — Δ1:** `import {IGame} from "../../contracts/AfKing.sol";` is a **compile break**
(deleted). Repoint to the game type / `IDegenerusGame` interface, OR drop (the file may not need `IGame`
once `afKing` views become `game` views).

**setUp (`:68-71`) — keep verbatim** (the deploy + `vm.warp` 1-day idiom is fixture-correct once Wave 0
lands):
```solidity
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }
```

**Call-site rewrites (the body):**
- `afKing.subscribe(address(0), false, true, 1, 0, address(0))` (`:157`,`:167`,`:326`,`:332`,`:351`) →
  `game.subscribe(...)` (Δ2, identical args).
- `afKing.autoBuy(50)` (`:94`,`:132`,`:193`,`:246`,`:292`,`:304`,`:364`) → **Δ4 SEMANTIC REMAP**: the buy
  now fires in `game.advanceGame()`'s STAGE. To drive the same per-sub buy, advance a new day (settle VRF as
  `KeeperRewardRoutingSameResults._settleGame` does) so `processSubscriberStage(50)` runs the funded subs.
- `afKing.doWork()` (`:269`) → `game.mintBurnie()` (Δ3).
- `afKing.subscriptionOf(pass).validThroughLevel` / `.dailyQuantity` / `.fundingSource` (`:105`,`:110`,
  `:137`,`:160`,`:171`,`:334`) → read `_subOf[pass]` via `vm.load` (re-derive slots) — there is **no
  game-exposed `subscriptionOf`**.
- `afKing.poolOf(s)` (`:355`,`:378`) → `game.afkingFundingOf(s)`; `afKing.withdraw(x)` (`:380`) →
  `game.withdrawAfkingFunding(x)` (Δ5).

**Property reframes (D-351-01, preserve coverage):**
- The per-day `_afkingEpoch` determinism asserts (already 0 in-repo — grep found no `_afkingEpoch` test
  refs) → **stamped-day determinism** (FREEZE-03: the box seeds from `sub.lastAutoBoughtDay`'s
  `rngWordByDay[day]`, frozen at stamp time).
- The event-signature asserts (`SubscriptionExtendedFree`/`SubscriptionExpired`/`CoinflipStakeUpdated`
  `:60-66`) — keep the `vm.recordLogs` + topic-decode idiom; re-confirm the event sigs still emit from the
  game-resident module (grep `GameAfkingModule.sol` for the events; rename if changed).
- The 336-04 green proof `testNonCrossingPathPerformsZeroLazyPassHorizonSloads` (per v50 ledger §5) lives
  here — its no-SLOAD oracle reframes to the GAS-02 no-STATICCALL trace (§3 of the 350 spec).

> **Note (already-deleted baseline test):** v50 deleted `testRenewalExactlyAtCostFullBurn` (B9 in
> `REGRESSION-BASELINE-v50.md:116`) — the v49 pass-OR-pay renewal premise. v55 carries that forward (it is
> already gone from the v54 `20ca1f79` baseline); the v55 ledger does not re-delete it.

---

### 3. `test/fuzz/AfKingConcurrency.t.sol` (test, set-mutation / swap-pop) — TST-04 set-mutation template

**Analog:** self → STAGE/open cursor self-partition. **68 `afKing.` refs — the heaviest adapt.**

This is the **PRIMARY set-mutation / swap-pop / tombstone analog for TST-04**. The whole file proves the
H-CANCEL-SWAP-MISS resolution (the in-place cancel-tombstone + deferred reclaim that advances no cursor),
which TST-04 regresses ([[afking-cancel-tombstone-streak-finding]]).

**The load-bearing property excerpt to PRESERVE (docstring `:23-34`):**
```
//   - In-place cancel-tombstone no-miss (TOMB-04 / Task 2, SUB-07): setDailyQuantity(0) is a
//     TRUE in-place tombstone -- it writes the dailyQuantity=0 sentinel and relocates NO ONE ...
//     The swap-pop is DEFERRED to a top-of-loop reclaim branch ... that does NOT advance the cursor,
//     so the swap-pop occupant is re-read at the freed index THIS [pass] -- no active sub is skipped.
```
**Reframe onto the v55 successor mechanism** (the swap-pop now lives in `processSubscriberStage` /
`_removeFromSet` on the game-resident set): `GameAfkingModule.sol:395-401`
```solidity
        uint256 last = _subscribers.length - 1;
        ... address mover = _subscribers[last]; _subscribers[idx] = mover; ...
        _subscribers.pop();
```
and the STAGE loop's "WITHOUT advancing the cursor" reclaim at `:582-587` (`delete _subOf[player]`). The
ORPHAN guard the redesign added (`:557` comment "removal from `_subscribers` between stamp and open ORPHANS
the box") is a NEW property TST-04 should also assert.

**Call-site rewrites:** `afKing.autoBuy(N)` (`:N`) → drive via `advanceGame()` STAGE (Δ4);
`afKing.setDailyQuantity(0)` (10 occurrences) → re-`game.subscribe(player,…,dailyQuantity=0,…)` (the cancel
path; **no `setDailyQuantity` external exists**); `afKing.subscriberCount()` →
`_subscribers.length` via `vm.load`; `afKing.autoBuyProgress()` → read `_subCursor`/`subsFullyProcessed`
(`DegenerusGameStorage.sol:343`) via `vm.load`. The pinned-slot constants (`:46-60`) are **AfKing-layout
and WRONG** — re-derive on `DegenerusGame`.

---

### 4. `test/fuzz/AfKingFundingWaterfall.t.sol` (test, CRUD funding waterfall) — TST-02 revert-free funding

**Analog:** self → game-resident `afkingFunding` SLOADs. **39 `afKing.` refs.**

The funding-waterfall corners (claimable-first vs funding-source vs pool, the LANDMINE-A exemption-spoof)
are exactly TST-02's "fuzz random *funded* well-formed slice inputs (amount / claimable-mix)" (CONTEXT
D-351-04). Reframe the cross-contract `afkingFundingOf`/`poolOf` STATICCALL plumbing → in-context
`afkingFunding[...]` SLOADs (`GameAfkingModule.sol:464`/`:662`/`:709`, the `claimablePool -=` `:710`).

**Call-site:** `afKing.poolOf(src)` (`:N`) → `game.afkingFundingOf(src)`; `afKing.autoBuy(50)` → STAGE-drive
(Δ4); `afKing.subscriberCount()` → slot-read.

> **Note (v50 flipped GREEN):** `testFundingSourceVaultDoesNotInheritExemption` (B10,
> `REGRESSION-BASELINE-v50.md:117`) went green at v50 IMPL (the `BurnieChargeFailed` shortfall path was
> deleted). Carried forward green in v55 — the test PRESENT, the LANDMINE-A assertion preserved.

---

### 5. `test/fuzz/KeeperRewardRoutingSameResults.t.sol` (test, differential same-results) — D-351-05 / TST-03 / TST-06 differential template

**Analog:** self. **THE PRIMARY differential same-results scaffolding** (the v49 reward-routing
"byte-identical RESULTS" proof; v48 "byte-reproduced" precedent — CONTEXT D-351-05).

**The recipient-isolated differential oracle to REUSE (`:62-70`, `:111-130`):** the
`CoinflipStakeUpdated` topic-decode + `_settleGame` VRF-drain are the exact instruments the v55 differential
needs.
```solidity
    bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)");
    // topics[1] == keeper recipient isolation; data[0:32] == amount
```
**The settle-to-clean-state helper (`:111-127`) — port verbatim** (every v55 proof needs a VRF-delivered
clean day before it can stamp/open):
```solidity
    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != _lastFulfilledReqId && reqId > 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) { mockVRF.fulfillRandomWords(reqId, vrfWord); _lastFulfilledReqId = reqId; }
```

**The TST-01 / TST-06 box-same-results DIFFERENTIAL (D-351-05) — the assertion shape to author:** run the
afking stamp→open AND a manual `openLootBox` for the **same** `(amount, level, rngWord, score)`; assert
byte-identical materialized traits. Both arms share ONE preimage (verified in
`DegenerusGameLootboxModule.sol`):
- afking arm — `resolveAfkingBox(player, amount, day, rngWord, activityScore)` `:877`, seed
  `keccak256(abi.encode(rngWord, player, day, amount))` `:889`, LIVE level `level + 1` `:892`.
- human arm — `openLootBox(player, index)` `:503`, reads `lootboxEth[index][player]` `:505`, same
  `abi.encode` preimage (the contract comment at `:887` states "Byte-identical to openLootBox(:534) /
  resolveLootboxDirect(:768)").
Assert `targetLevel` + materialized traits equal across the two arms for the same tuple — robust to any
future resolution refactor (NOT golden snapshots).

**Call-site:** `afKing.doWork()` (`:N`) → `game.mintBurnie()`; `afKing.subscriberCount()` → slot-read.

---

### 6. `test/fuzz/KeeperNonBrick.t.sol` (test, revert-free / non-brick) — TST-02 revert-free template

**Analog:** self. **THE PRIMARY revert-free / no-brick scaffolding for TST-02** (the preserved `_resolveBuy`
REVERT-01 invariants; D-348-04 NO try/catch; class-B fail-loud; class-C gameover-never-blocked).

**The box-enqueue + RNG-inject + poison-isolation helpers (`:38-69` + body) — port the harness, reframe the
subject.** The slot constants (`LOOTBOX_ETH_SLOT=15`, `RNG_LOCKED_SHIFT=168`, `GAME_OVER_SHIFT=184`,
`:48-61`) and the `0.5 gwei`/`66_528`/`71_203` reward-peg mirrors (`:66-69`) are reusable as-is (game
storage). The `_buyBox` real-deposit idiom (see `KeeperOpenBoxWorstCaseGas._buyBox` below) is shared.

**TST-02 reframe (D-351-04 fuzz the funded slice):**
- "funded process/open never reverts on well-formed slices" → fuzz amount / claimable-mix exercising
  `_resolveBuy` (`ev = cost − claimableUse`, the 1-wei sentinel, the `LOOTBOX_MIN` skip, `quantity ≥ 1` —
  per `PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §3, REVERT-01).
- "solvency violation fails loud (class B, never masked)" → assert a forced SOLVENCY-01 violation REVERTS
  (the checked `uint128 -=` at `GameAfkingModule.sol:710`; SOLVENCY-01 `DegenerusGameStorage.sol:358`).
- "gameover routing never blocked by the afking STAGE (class C)" → assert the gameover advance leg
  (`mult == 0`) still proceeds (the STAGE does not gate it).

> **D-351-02 removed-surface candidate:** the file's **`batchPurchase` per-slice try/catch isolation**
> (docstring `:18-28`, `vm.prank(AF_KING)` batch) tests a surface the redesign REMOVED (the v49
> keeper-`batchPurchase`; v55 P5 dead-code `AF_KING.batchPurchase`/`BatchBuy`). Those specific functions
> drop with a BY-NAME entry + removal reason in the v55 ledger (D-351-02). The reentrancy-rollback +
> un-brickable-cancel properties (`:29-36`) **reframe** onto the game-resident withdraw/cancel — keep them.

---

### 7. `test/fuzz/RngLockDeterminism.t.sol` (test, freeze/determinism) — TST-01 freeze template

**Analog:** self (2,272 lines — the largest; the canonical freeze/determinism corpus). **4 `afKing.` + 4
`doWork`.** Houses the v50 green `testFuzz_RngLockDeterminism_ClaimWhalePassDuringLockSafe` (ledger §5) and
the A7 `vm.assume`-exhaustion baseline red (carried forward).

**TST-01 reframe (D-351-04, fuzz is most valuable here):** the headline freeze property — "the stamp+open
yields a byte-identical box independent of open timing/block (seed uses the STAMPED day, never open-time
`_simulatedDayIndex()`); index-binding holds across a mid-day `requestLootboxRng` index advance":
- fuzz random open-timing/block, hold the stamp fixed, assert byte-identical box (the freeze).
- fuzz a mid-day `requestLootboxRng` index advance (`DegenerusGameAdvanceModule.sol:1016` + index advance
  `:1089`/`:1629`) between stamp and open; assert the box still binds to the stamped day's word
  (`rngWordByDay[lastAutoBoughtDay]`, `GameAfkingModule.sol:905`/`:921`).

**Freeze target = the ACTUALLY-stamped fields.** ⚠ **Design-vs-IMPL divergence the planner must
reconcile:** CONTEXT/350-SPEC describe a **5-field** stamp `(index, amount, day, scorePlus1,
baseLevelPlus1)`, but the committed `453f8073` Sub struct stamps **4** (`scorePlus1`, `amount`,
`lastAutoBoughtDay`, `lastOpenedDay`) and resolves at the **LIVE** level — `DegenerusGameStorage.sol:1867`
comments "no stored baseLevelPlus1 roll floor … sources its RNG word from rngWordByDay[lastAutoBoughtDay]";
`GameAfkingModule.sol:896` "No index, no baseLevel." The freeze test asserts the **stamped `amount` +
`scorePlus1` + `day`** are frozen (per-sub stamp), and the EV-cap clamp is the SOLE live-read (TST-03, not a
freeze target — CONTEXT carried-LOCKED posture). **Do NOT write a freeze test trying to prove
score/baseLevel unmanipulable** — score is stamped-frozen; baseLevel is intentionally live (no floor).

**Call-site:** `afKing.doWork()` → `game.mintBurnie()`. Preserve the existing `vm.skip` blocks (17 skips in
the baseline — orthogonal to the gate).

---

### 8. `test/fuzz/KeeperFaucetResistance.t.sol` / `KeeperRouterOneCategory.t.sol` (test, bounty / one-category)

**Analog:** self → `mintBurnie` bounty. Faucet: 11 `afKing.` + 19 `doWork` + 8 srcref; Router: 22 `afKing.`
+ 23 `doWork` + 6 srcref. Both have the heaviest `doWork` density.

- `afKing.doWork()` → `game.mintBurnie()` (Δ3, ~42 sites combined).
- The bounty-math comment anchors (`AfKing.sol:851/854/870/878/890`) → repoint to `GameAfkingModule.sol`
  bounty constants (`BOUNTY_ETH_TARGET`/`ADVANCE_RATIO_NUM`/`OPEN_KNEE`, `:987`/`:995`/`:1003`).
- `KeeperRouterOneCategory.t.sol:88` + `:286` **`vm.readFile("contracts/AfKing.sol")`** → repoint
  `AFKING_SRC = "contracts/modules/GameAfkingModule.sol"` and re-derive the grepped tokens (the
  one-category structural early-return + single CEI-last `creditFlip` now live at `GameAfkingModule.sol`
  `mintBurnie` `:985-1014` / the `_autoOpen` one-category split `:993-1009`).

The one-category-no-stack property (no advance+open bounty in one tx) reframes directly onto
`mintBurnie`'s `if (advanceDue) {...} else {...}` structural early-return (`:993`/`:1000`).

---

### 9. `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (test, delta-audit) — D-351-02 candidate

**Analog:** self / KeeperRewardRouting. **0 `afKing.`/`doWork`** but its entire subject is
`batchPurchase` / the proposed `batchPurchaseForKeeper` (`:11-42`, a v49/331 path) — a **gated diff that
NEVER LANDED** (`:40` `TODO-331-05: flip to true once batchPurchaseForKeeper lands`) and a surface the v55
redesign removed. **Strong D-351-02 removed-surface candidate** — the affiliate delta-audit it performs is
re-homed by 349.2's restored BURNIE affiliate (the per-buy `affiliate.payAffiliate` at
`GameAfkingModule.sol:806`/`:816`). The planner decides: (a) DROP with a BY-NAME + reason ledger entry
(`batchPurchase` removed), or (b) reframe the affiliate-conservation delta-audit onto the 349.2 per-buy
affiliate path. Bias = adapt; but if `batchPurchase` is its sole subject, removal is the D-351-02 exception.

---

### 10. `test/fuzz/RedemptionStethFallback.t.sol` (test, fallback) — D-351-02 candidate (custody recovery)

**Analog:** self. **import=1 (`AfKing.sol:7` — compile break) + 1 `afKing.` + uses
`AfKing(payable(AF_KING)).depositFor{value}(...)`/`.poolOf(...)`/`.withdraw(...)`** (`:571-587`) for the
POOL-04 sDGNRS `burnAtGameOver` AfKing-prepaid-pool recovery test (`:564-589`).

The de-custody `depositFor`/`poolOf`/`withdraw` external API **no longer exists** (the standalone custody
contract is gone; funding is game-resident `afkingFunding`). The `burnAtGameOver` recovery-of-prepaid-pool
flow (`:580` "folds afKing.withdraw(afKing.poolOf(this)) BEFORE the bal==0 early-return") is **the v54
de-custody machinery v55 replaced** — a clean D-351-02 removed-surface candidate. The pure
ETH-vs-stETH redemption-fallback core (the file's main subject, the POOL-04a/b ETH-segregation asserts)
**stays and adapts** (drop only the AfKing-custody-recovery leg, or reframe it onto the game-resident
`afkingFunding` recovery if one exists). Repoint the `:7` import regardless.

---

### 11. `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (test, gas per-open marginal) — TST-06 per-open template

**Analog:** self. **THE PRIMARY per-open marginal scaffolding** — it already embeds the CR-01
loop-N-divide MARGINAL idiom (Test D, `:163-217`), the worst-case preconditions, the `vm.store` slot-forcing
helpers, and the `log_named_uint` emission. (Currently instruments the HUMAN `boxPlayers`/`autoOpen` path →
**reframe onto the afking open**: `_openAfkingBox` `GameAfkingModule.sol:888` → `resolveAfkingBox`
`:877`, driven by `autoOpen(count)` `:1023` over N ready stamped boxes after `rngWordByDay[stampDay]`
lands — per 350-SPEC §2.)

**The MARGINAL idiom to PRESERVE verbatim (the load-bearing 350-SPEC §0 / CR-01 rule), `:184-217`:**
```solidity
        vm.prank(cranker);
        uint256 gasBefore = gasleft();
        game.autoOpen(nBoxes * 64);              // reframe: open N ready afking stamped boxes
        uint256 totalGas = gasBefore - gasleft();
        uint256 perBoxMarginal = totalGas / nBoxes;   // loop-N-divide — never a single-box total
        // non-vacuity: assert each box actually opened (signal zeroed) before trusting the marginal
        assertLt(perBoxMarginal, SINGLE_BOX_TOTAL_REF_GAS, "...mis-attributed fixed overhead (CR-01)");
```
**The worst-case-precondition + non-vacuity gate to PRESERVE (`:97-112`):** assert each box is queued +
RNG-ready + un-opened BEFORE the measurement, and zeroed/opened AFTER (so the marginal is a real
materialization, not a skip).

**The `_buyBox` real-deposit helper (`:343-348`) — shared idiom (reframe to a funded LOOTBOX-mode SUB for
the per-buy leg):**
```solidity
    function _buyBox(address buyer, uint256 lootboxAmount) internal {
        vm.prank(buyer);
        game.purchase{value: lootboxAmount + 0.01 ether}(buyer, 400, lootboxAmount, bytes32(0), MintPaymentKind.DirectEth);
    }
```
**The RNG-word-inject + slot-read helpers (`:357-373`) — port for the open-readiness setup** (`vm.store`
the index's word; the afking open gates on `rngWordByDay[day]` instead, re-derive that map's slot).

**TST-06 per-BUY marginal (350-SPEC §1)** — the new leg this file currently lacks: instrument
`processSubscriberStage` via a new-day `game.advanceGame()` with N vs N−1 funded LOOTBOX-mode subs;
report the per-sub marginal vs the v54 cold-ledger ~120–130k oracle; **INCLUDE** the 349.2-restored BURNIE
side-effects (do NOT subtract — 350-SPEC §1 ⚠-note + CONTEXT specifics).

---

### 12. `test/gas/RouterWorstCaseGas.t.sol` (test, gas worst-case) — TST-06 16.7M-ceiling template

**Analog:** self. **21 `afKing.` + 9 `doWork` + 3 srcref.** The PRIMARY 16.7M-per-tx-ceiling worst-case
scaffolding (the `AfKing.doWork()` router worst case). Reframe onto the STAGE: assert a 50-chunk
`processSubscriberStage(50)` (via `advanceGame()`) AND the open leg each stay **under 16.7M** on the
worst-case funded-lootbox-sub mix (post-349.2). `SUB_STAGE_BATCH = 50`
(`DegenerusGameAdvanceModule.sol:149`); a landed buy ≈ 262k → 50 ≈ 13.1M (350-SPEC §5). Repoint the
`AfKing.sol:868/850` mirrors → `GameAfkingModule.sol`. `afKing.doWork()`/`afKing.autoBuy(total)` →
`mintBurnie()`/STAGE-drive.

---

### 13. `test/gas/KeeperLeversAndPacking.t.sol` / `KeeperResolveBetWorstCaseGas.t.sol` / `SweepPerPlayerWorstCaseGas.t.sol`

**Analogs:** self.
- **KeeperLeversAndPacking** (`vm.readFile`, source-grep/packing): repoint `AFKING_SRC`
  (`:88`,`:127`,`:222`,`:268`) → `GameAfkingModule.sol`; re-derive the packed-Sub layout asserts against the
  game-resident Sub (`DegenerusGameStorage.sol:1867`). The `:299` comment "Plan 335-04 deleted the
  keeper-burn function from both AfKing.sol and …" anchors a removed surface — update to the v55 fold.
- **KeeperResolveBetWorstCaseGas** (the marginal-idiom DONOR `:197-242`, cited by KeeperOpenBox): light
  touch — it's the degenerette resolve-bet per-spin marginal; keep the idiom, confirm no `afKing` coupling.
- **SweepPerPlayerWorstCaseGas** (15 `afKing.` + 5 srcref): the per-player sweep worst case → reframe onto
  the per-sub STAGE marginal; `afKing.subscriberCount()`/`autoBuy(total)` → slot-read / STAGE-drive; the
  `BOUNTY_ETH_TARGET` immutable + SUB-04 reinvest comments (`:50`,`:150`,`:172`,`:196`) repoint to
  `GameAfkingModule.sol`.

---

### 14. `test/REGRESSION-BASELINE-v55.md` (doc, BY-NAME ledger) — TST-05

**Analog:** `test/REGRESSION-BASELINE-v50.md` (301 lines) + `-v49.md` (358 lines). **Mirror the structure
EXACTLY.** The 7-section format:
1. **TST-HEAD arithmetic + reconciliation** (passed/failed/skipped table; `IMPL HEAD → TST HEAD delta`).
2. **The carried-forward union BY NAME** — bucketed (A = VRF/RNG-window baseline reds, B = stale-harness/
   behavioral, C = HERO-deferred), every red `(suite-basename, testName)`.
3. **NEW vs the prior baseline — the deltas with provenance** (the `union = prior − {OUT} + {IN}` delta-math;
   v50 §3 is the model: `42 − 2 + 2 = 42`).
4. **Flaky-cluster non-determinism analysis** (the unseeded `[invariant]` `DegeneretteBet.inv` cluster ⊆-gate
   rationale — carry forward; `foundry.toml` `[fuzz] seed=0xdeadbeef` but no `[invariant] seed`).
5. **NEW green proof files** (the v55 TST-01..06 additive-green table).
6. **Net-zero-new-regression PROOF** (`live − union == ∅` binding ⊆-gate + the FC1-FC5 false-confidence
   guards).
7. **Scope attestation** (`git diff 453f8073 HEAD -- contracts/` EMPTY; full-tree run, not `--match-path`).

**The binding headline format (v50 `:21-33`) to mirror:**
> at the v55 TST HEAD, every `forge test` failing test **∈** the v55.0 §2 enumerated union **BY NAME** —
> `live failing set − the §2 union == ∅` — **net-zero new regression**.

**v55-SPECIFIC reconciliation (CONTEXT D-351-01 / §117 carried-LOCKED):** because the afking corpus is
**rewritten wholesale** (not extended like v50), §2/§3 must additionally reconcile **which v54
`20ca1f79` baseline test became which adapted test** (the rewrite map), and list every D-351-02
removed-surface drop (`batchPurchase`/`BatchBuy`/`Af_King.depositFor`-custody) BY NAME + reason. **Baseline
carried forward against `20ca1f79` (v54), NOT v49/v50** (there is no `REGRESSION-BASELINE-v54.md` — v55 is
the first ledger off the v54 baseline). Confirm placement in `test/` (alongside v48/v49/v50 — yes by
precedent, CONTEXT Discretion).

---

## Shared Patterns

### Fixture-first un-bricking (Wave 0)
**Source:** v46 Phase 318 precedent + `DeployProtocol.sol` itself.
**Apply to:** ALL test files (nothing compiles until `DeployProtocol.sol:26/70/123-133` is repaired to deploy
`GameAfkingModule` + reconcile the nonce/DEPLOY_ORDER for `GAME_AFKING_MODULE` + `GAME_BINGO_MODULE`).

### Pinned-slot re-derivation (the silent-breakage guard)
**Source:** every adapted file's slot-constant block (e.g. `AfKingConcurrency.t.sol:46-60`,
`KeeperRewardRoutingSameResults.t.sol:73-88`).
**Apply to:** every `vm.store`/`vm.load` poke. The `SUBOF_SLOT`/`SUBSCRIBER_INDEX_SLOT`/`AUTOBUY_SLOT` +
Sub byte-offsets are **AfKing-standalone-layout** and WRONG for the game-resident `_subOf`/`_subscribers` on
`DegenerusGameStorage`. Re-derive ALL via `forge inspect storage DegenerusGame` (`_subOf`
`:1902`, `_subscribers` `:1914`, Sub `:1867`, cursors/`subsFullyProcessed` `:343`).

### `vm.readFile` source-grep repointing
**Source:** `KeeperRouterOneCategory.t.sol:88/286`, `KeeperLeversAndPacking.t.sol:88/127/222/268`.
**Apply to:** the 2 files with `AFKING_SRC = "contracts/AfKing.sol"` — repoint to
`"contracts/modules/GameAfkingModule.sol"` (else `vm.readFile` THROWS at runtime) + re-derive every grepped
token for the renamed/relocated symbols.

### Differential same-results oracle (D-351-05)
**Source:** `KeeperRewardRoutingSameResults.t.sol` (recipient-isolated topic-decode `:62-70` + `_settleGame`
`:111-127`); the contract guarantees the two arms share a preimage
(`DegenerusGameLootboxModule.sol:877` `resolveAfkingBox` ≡ `:503` `openLootBox`, comment `:887`).
**Apply to:** TST-01 + TST-06 box-same-results (afking stamp→open vs manual `openLootBox`, byte-identical
materialized traits for the same `(amount, level, rngWord, score)`).

### Marginal gas peg (loop-N-divide, CR-01 / 350-SPEC §0)
**Source:** `KeeperOpenBoxWorstCaseGas.t.sol:163-217` (Test D) + the donor
`KeeperResolveBetWorstCaseGas.t.sol:197-242`.
**Apply to:** TST-06 per-buy AND per-open marginals. **(gas for N − gas for N−1) / 1, NEVER a single-item
total.** Gate every marginal with worst-case preconditions + non-vacuity (the box actually opened / the sub
actually bought) so the number is real.

### Settle-to-clean-state VRF drain
**Source:** `KeeperRewardRoutingSameResults._settleGame:111-127` (mirrors
`RngLockDeterminism._completeDay`).
**Apply to:** every proof needing a VRF-delivered day before stamping/opening (mock VRF
`fulfillRandomWords` + `advanceGame` loop until `!advanceDue && !rngLocked`).

### NO-STATICCALL trace assertion (GAS-02, 350-SPEC §3)
**Source:** new (the 336-04 no-SLOAD oracle in `AfKingSubscription.t.sol` is the closest idiom).
**Apply to:** the process STAGE + open leg — assert NO `STATICCALL` targets a DIFFERENT address (the
in-context `afkingFunding[*]` SLOADs `GameAfkingModule.sol:464`/`:662`/`:709` replaced the old cross-contract
`GAME.afkingSnapshot`/`afkingFundingOf` STATICCALLs). **Carve-out (do NOT flag):** same-contract
DELEGATECALLs (`resolveAfkingBox` `:901`, the 349.2 `quests`/`affiliate`/`coinflip` calls
`:760`/`:806`/`:816`/`:831`) + the off-path `afkingFundingOf`/`afkingSnapshot` Game views
(`DegenerusGame.sol:1579`/`:2645`, called only by `DegenerusVault.sol:518`).

---

## No Analog Found

None. Every target maps to an in-repo analog. **The two HARDEST adaptations are not "no analog" — they are
"analog whose subject was REMOVED" (D-351-02 candidates), routed to the planner for adapt-vs-drop:**

| File | Role | Data Flow | D-351-02 status |
|------|------|-----------|-----------------|
| `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` | test | differential | Subject = `batchPurchase`/never-landed `batchPurchaseForKeeper`. The affiliate-conservation delta-audit may reframe onto the 349.2 per-buy `affiliate.payAffiliate` (`GameAfkingModule.sol:806`/`:816`); if `batchPurchase` is its sole subject → DROP with BY-NAME + reason. |
| `test/fuzz/RedemptionStethFallback.t.sol` (custody-recovery leg only) | test | fallback | The `AfKing.depositFor`/`poolOf`/`withdraw` `burnAtGameOver` prepaid-pool recovery (`:571-587`) = v54 de-custody machinery v55 replaced → DROP that leg with BY-NAME + reason; the ETH-vs-stETH redemption core STAYS + adapts. |
| `test/fuzz/KeeperNonBrick.t.sol` (`batchPurchase` isolation leg only) | test | revert-free | The keeper-`batchPurchase` per-slice try/catch isolation (`:18-28`) = removed surface (v55 P5 dead-code `AF_KING.batchPurchase`/`BatchBuy`) → DROP that leg; the reentrancy-rollback + un-brickable-cancel properties reframe + stay. |

---

## Metadata

**Analog search scope:** `test/fuzz/`, `test/fuzz/helpers/`, `test/gas/`, `test/` (regression docs);
`contracts/modules/GameAfkingModule.sol`, `DegenerusGameAdvanceModule.sol`, `DegenerusGameLootboxModule.sol`,
`DegenerusGame.sol`, `DegenerusGameStorage.sol`, `ContractAddresses.sol`, `scripts/lib/predictAddresses.js`.
**Files scanned:** 18 test/doc analogs + 6 contract anchors.
**Pattern extraction date:** 2026-05-31.
**Subject:** FROZEN at `453f8073` (HEAD `902f3fbf`); `git diff 453f8073 HEAD -- contracts/` EMPTY throughout
TST.
**Key divergence flagged for planner:** the committed Sub stamp is **4-field** (live-level resolve, no
`index`/`baseLevelPlus1`) vs the SPEC's "5-field stamp" prose — `DegenerusGameStorage.sol:1867` +
`GameAfkingModule.sol:896` are authoritative; the freeze test targets the stamped `amount`/`scorePlus1`/`day`.
