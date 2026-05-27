# Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression - Pattern Map

**Mapped:** 2026-05-27
**Files analyzed:** 8 author-targets (1 fuzz-extension, 3 new Foundry proof files, 17 red deletions, 5 `git mv` renames, 1 markdown ledger) + Hardhat stat re-confirm (no edit)
**Analogs found:** 8 / 8 (every author-target has a strong in-repo analog; no analog gap)

> POSTURE REMINDER (binding): this is a `test/` + `.planning/` phase. ZERO `contracts/*.sol`
> (mainnet) mutation. All contract `file:line` below are READ-ONLY anchors the tests key on.
> Tests are agent-committable; `.planning/` is gitignored (force-add). If a proof surfaces a
> CONTRACT defect, STOP and surface — do not patch the frozen subject.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `test/fuzz/RngLockDeterminism.t.sol` (EXTEND in place — locked by roadmap) | fuzz harness (freeze-determinism) | event-driven / transform (snapshot→perturb→deliver→assert byte-identity) | self (the file IS the template) + `test/fuzz/RngLockRotationDeterminism.t.sol` | exact |
| TST-02 NEW Foundry proof (one-category / no-stacking / escapes) | behavioral test | request-response (call/log-count oracle) | `test/gas/CrankLeversAndPacking.t.sol` (the `_countCoinflipStakeUpdated*` oracle) + `test/fuzz/AfKingConcurrency.t.sol` (escapes/default-batch) | role+flow match |
| TST-03 NEW Foundry proof (reward-routing + GASOPT-01/03 same-results) | behavioral-equality test | request-response / transform | `test/fuzz/AdvanceGameRewrite.t.sol` (advance harness) + `CrankLeversAndPacking` (`vm.recordLogs` creditFlip-presence) + `AfKingConcurrency` (`keeperSnapshot`-driven autoBuy) | role+flow match |
| TST-05 NEW Foundry proof (`degeneretteResolve` re-peg/gate/RESULTS-equality) | behavioral + RESULTS-equality test | transform (resolve N → capture mint/claimable/pool deltas) | `test/fuzz/DegeneretteFreezeResolution.t.sol` (`_replayPerSpinBaseline` capture+replay) + `test/fuzz/DegeneretteHeroScore.t.sol` | exact |
| The 17 premise-retired reds (DELETE + re-author fresh) | test (deletions + re-author) | n/a | each red's CURRENT body (read it to know the retired premise) + the re-author home below | per-row match |
| 5 `Crank*` → `Keeper*` files (`git mv` + symbol rename) | test (pure rename) | n/a (zero behavioral change) | `test/gas/RouterWorstCaseGas.t.sol` + `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (the keeper-* naming convention) | exact |
| `test/REGRESSION-BASELINE-v49.md` (NEW) | markdown ledger (NOT a `.sol` test) | n/a | `test/REGRESSION-BASELINE-v48.md` (the §1–§5 ledger shape) | exact |
| `test/stat/Degenerette{ProducerChi2,BonusEv,PerNEvExactness}.test.js` (re-confirm GREEN — NO edit) | Hardhat stat (secondary gate) | n/a | self (precedent-locked v48 parity) | exact |

---

## Pattern Assignments

### `test/fuzz/RngLockDeterminism.t.sol` — TST-01 freeze-fuzz EXTENSION (fuzz harness, transform)

**Analog:** self (extend in place — the roadmap LOCKS this as the TST-01 home). Secondary: `test/fuzz/RngLockRotationDeterminism.t.sol` (the rotation variant of the same 6-phase template).

**6-phase byte-identity template + helpers** (lines 73–144 — copy the call shape, do NOT re-implement):
```solidity
// _advanceToVrfRequestBoundary() (:105) → asserts rngLocked() true + a reqId pends
// _deliverMockVrf(reqId, word) (:115)   → fulfill + drain rngLock
// _snapshotPreLock() (:130) / _revertToPreLock(id) (:134) → vm.snapshot / vm.revertTo
// _readRngWordCurrent() (:86) / _readVrfRequestId() (:90) / _readLootboxRngIndex() (:94)
//   / _lootboxRngWord(index) (:98)  → the vm.load slot-digest reads (slots 3/4/37/38)
// _assertVrfOutputByteIdentity(perturbed, baseline, label) (:138) → assertEq
```
Each fuzz fn: snapshot → advance to VRF boundary → `_perturb(seed)` → deliver SAME word + digest VRF-derived outputs → revert → re-advance → re-deliver SAME word WITHOUT perturb → digest baseline → `assertEq`.

**Perturbation action library — the EXTENSION SITE** (lines 150–207). Currently `N_PERTURB_ACTIONS = 9` (`:150`), classes `0..8` dispatched off `seed % N_PERTURB_ACTIONS` (`:153`). Each action is a `vm.prank(actor); try …() {} catch { return; }` (e.g. cls 0 = `placeDegeneretteBet` `:165`, cls 1 = `purchase` `:173`). **ADD the router classes** (and bump `N_PERTURB_ACTIONS`):
```solidity
// NEW classes (append; bump N_PERTURB_ACTIONS to 11):
//   else if (cls == 9)  { vm.prank(actor); try IAfKing(AF_KING).doWork()    {} catch { return; } }
//   else if (cls == 10) { vm.prank(actor); try IAfKing(AF_KING).autoBuy(0)  {} catch { return; } }
// NOTE: autoOpen during rngLock MUST NO-OP (not revert) — see Pitfall below.
```

**Non-vacuity guard for the `totalFlipReversals` class** (RESEARCH Pitfall 4): the FROZEN advance-consume read is `cw += totalFlipReversals` at `contracts/modules/DegenerusGameAdvanceModule.sol:254-259`, INSIDE the daily drain. The perturbation must move `totalFlipReversals` (a flip-reversal-bearing buy/bet) BETWEEN the request boundary and the consume; add an assertion that the perturbation actually changed `totalFlipReversals` pre-revert, or byte-identity passes vacuously.

**no-marooned-boxes / autoOpen-blocked surface** (READ-ONLY anchors): `boxesPending()` is rngLock-aware (`contracts/DegenerusGame.sol:1655`), `autoOpen` entry-gate `if (rngLockedFlag || _livenessTriggered()) return 0;` (`contracts/DegenerusGame.sol:1692`). TST-01 asserts (a) `boxesPending()==false` during lock, (b) `autoOpen(N)` returns 0 / opens nothing during lock, (c) after the word lands the SAME boxes open with the cursor intact.

**Depth knobs** (CONTEXT discretion): routine under default profile (`[fuzz] runs=1000`); gate the deep freeze proof under `FOUNDRY_PROFILE=deep` (`runs=10000`) — `foundry.toml`. Start by extending the `_perturb` library; add a stateful invariant handler ONLY if the same-tx advance-consume + buy/open bundling can't be a single perturbation (RESEARCH Open Q2).

**DO NOT TOUCH** `testFuzz_RngLockDeterminism_StakedStonkRedemption` (`:1263`) — it is v48-baseline red A7 (`vm.assume` over-rejection) and MUST carry forward UNCHANGED (RESEARCH Pitfall 2). Extend, never refactor its `vm.assume` filters.

---

### TST-02 NEW proof file — one-category / no-stacking / escapes (behavioral, request-response)

**Analog:** `test/gas/CrankLeversAndPacking.t.sol` (the count oracle) + `test/fuzz/AfKingConcurrency.t.sol` (the default-batch/escape driving + storage-stamp helpers).

**The creditFlip-count oracle** (`CrankLeversAndPacking.t.sol:523-548` — copy verbatim):
```solidity
bytes32 private constant COINFLIP_STAKE_UPDATED_SIG =
    keccak256("CoinflipStakeUpdated(address,uint32,uint256,uint256)"); // :75
function _countCoinflipStakeUpdated() internal returns (uint256 count) {       // :523
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; i++)
        if (logs[i].emitter == address(coinflip) && logs[i].topics.length > 0
            && logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG) count++;
}
function _countCoinflipStakeUpdatedFor(address who) internal returns (uint256 count) { // :538
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; i++)
        if (logs[i].emitter == address(coinflip) && logs[i].topics.length > 1
            && logs[i].topics[0] == COINFLIP_STAKE_UPDATED_SIG
            && logs[i].topics[1] == bytes32(uint256(uint160(who)))) count++; // recipient-isolated
}
```
Usage idiom: `vm.recordLogs(); vm.prank(keeper); afKing.doWork(); assertEq(_countCoinflipStakeUpdatedFor(keeper), 1, "...");` (`CrankLeversAndPacking.t.sol:184-195`). Use `_countCoinflipStakeUpdatedFor(keeper)` to isolate the router credit from a box-owner's winnings credit (`LootboxModule:1036`).

**D-02 assertions** (count, NOT amount) — the `doWork` structure they key on (`contracts/AfKing.sol:883-919`, READ-ONLY):
- `else-if` chain: buy `:890` → advance `:896` → open `:902` → `revert NoWork()` `:910`.
- Single `creditFlip` CEI-last in the `bountyEarned > 0` block `:916-918`.
- **EXACTLY one** `creditFlip` per `doWork()` across all three branches; **ZERO** on the `bountyEarned==0` skip (a buy chunk walking only already-bought subs — `:914-915`, runs the category, credits nothing, NO revert).

**D-01 structural reentrancy attestation** (NO attacker harness). Use the comment-stripped grep idiom from `CrankLeversAndPacking.t.sol`: `_stripComments` (`:560`-ish, ends `:634`) + `_countOccurrences` + `vm.readFile("contracts/AfKing.sol")`. Assert (a) the only external calls in `doWork`/`_autoBuy`/`advanceGame`/`autoOpen` legs target pinned `ContractAddresses.GAME`/`COINFLIP` (no untrusted address), and (b) the single `creditFlip(msg.sender, bountyEarned)` is CEI-last. The `_countOccurrences(afking, "creditFlip(msg.sender, bountyEarned)")` gate already exists at `CrankLeversAndPacking.t.sol:257` — reuse that exact byte-grep.

**D-03 default-batch / remainder + standalone UNREWARDED escapes** (READ-ONLY anchors): parameterless `doWork()` uses `BUY_BATCH=50` (`AfKing.sol:850`) / `OPEN_BATCH=100` (`:856`); standalone `autoBuy(count)` (`:923`) and `autoOpen(count)` (`:929`) call the legs directly and credit NOTHING. Drive subs via `AfKingConcurrency`'s `_setupHealthyBuyingSubs(N, prefix)` (`:100`) + `afKing.autoBuyProgress()` cursor reads (`:103`).

---

### TST-03 NEW proof file — reward-routing + GASOPT-01/03 same-results (behavioral-equality, transform)

**Analog:** `test/fuzz/AdvanceGameRewrite.t.sol` (the `AdvanceHarness` drain-gate exposure, `:7-102`) + `CrankLeversAndPacking` (`vm.recordLogs` creditFlip-presence) + `AfKingConcurrency` (`keeperSnapshot`-driven autoBuy).

**advanceGame UNREWARDED-standalone vs REWARDED-via-doWork** (READ-ONLY anchors):
- Standalone `game.advanceGame()` pays NO bounty (the 3 in-callee `creditFlip` were removed at ADV-01; `AdvanceModule.sol:154` returns only `uint8 mult`). Assert via `_countCoinflipStakeUpdatedFor(caller) == 0`.
- Router `doWork` pays `unit * ADVANCE_RATIO_NUM * mult` (`AfKing.sol:899`); `mult>0` ⇒ exactly one creditFlip to the keeper.
- mult ladder: mid-day partial-drain `mult=1` (`AdvanceModule.sol:217-218`); new-day `1/2/4/6` (`:235-241`); gameover `mult=0` UNREWARDED (`:187`) ⇒ assert ZERO creditFlip on the gameover leg.

**GASOPT same-results methodology = Foundry behavioral-equality** (CONTEXT discretion; mirrors v48 327 same-results). Capture state deltas the two ways and `assertEq`:
- GASOPT-01 (MintModule `owedMap` pointer hoist, `DegenerusGameMintModule.sol:399`+`:673`): `processTicketBatch`/`processFutureTicketBatch` produce identical ticket-processing results.
- GASOPT-03 (`keeperSnapshot(address[])`, `DegenerusGame.sol:2628`, consumed by AfKing `:807`): assert the batched read returns the SAME `(mintPrice, rngLocked, claimables[])` as N individual `claimableWinningsOf` calls, and an autoBuy driven through it produces identical buy outcomes.
- **GASOPT-02 is SUBSUMED into GASOPT-03** (RESEARCH Pitfall 5) — there is NO separate AfKing per-iteration `claimableWinningsOf` hoist site (count 0). Do NOT search for one.

**Delta-capture idiom** (from `DegeneretteFreezeResolution._replayPerSpinBaseline`, see TST-05 below): snapshot pre-state, run path A, snapshot deltas, `vm.revertTo`, run path B, `assertEq` deltas.

---

### TST-05 NEW proof file — `degeneretteResolve` re-peg / gate / RESULTS-equality (behavioral + RESULTS-equality, transform)

**Analog:** `test/fuzz/DegeneretteFreezeResolution.t.sol` (the resolve/capture + per-spin-replay scaffold) + `test/fuzz/DegeneretteHeroScore.t.sol` (the placement helpers).

**The capture + replay RESULTS-equality pattern** (`DegeneretteFreezeResolution.t.sol:351-433`):
```solidity
// pre-resolve balances (:382-385): claimable, claimablePool (vm.load slot 1 byte 16), BURNIE, WWXRP
// resolve N bets in ONE call, vm.recordLogs() (:393-395)
// _replayPerSpinBaseline(...) (:406) re-derives expected sums FROM the contract's own per-spin events
// assertEq(burnieDelta, expectedBurnie) / wwxrpDelta / claimableDelta / claimablePoolDelta (:411-423)
// non-vacuity: assertGt(expectedBurnie, 0) etc. (:426-428)
```
RESEARCH Open Q1 recommends route (b): prove the per-item resolution math is VALUE-INVARIANT (RESULTS are produced by the unchanged `_degeneretteResolveBet → delegatecall GAME_DEGENERETTE_MODULE.resolveBets` at `DegenerusGame.sol:1741-1755`; only the bounty wrapper + ≥3 gate changed) — do NOT resurrect deleted `autoResolve` source.

**The re-peg / gate / WWXRP-exclusion assertions** — the `degeneretteResolve` structure they key on (`contracts/DegenerusGame.sol:1595-1631`, READ-ONLY):
```solidity
if (len == 0 || betIds.length != len) revert E();                         // :1600 input-validate
if (degeneretteBets[players[0]][betIds[0]] == 0) revert BatchAlreadyTaken(); // :1604 AUTO-02 probe
uint8 currency = uint8((betPacked >> 42) & 0x3);                          // :1612 currency bits
try this._degeneretteResolveBet(players[i], betIds[i]) {                  // :1614 per-item isolation
    ++totalResolved; if (currency != 3) ++successCount;                   // :1618-1619 WWXRP=3 excluded
} catch {}
if (totalResolved == 0) revert NoWork();                                  // :1629 revert-on-no-work
if (successCount >= 3) coinflip.creditFlip(msg.sender, RESOLVE_FLAT_BURNIE); // :1630 flat ≥3 gate
```
`RESOLVE_FLAT_BURNIE = 1e18` (`DegenerusGame.sol:1544`). The 5 cases (RESEARCH Pitfall 6): (a) ≥3 non-WWXRP → exactly one flat creditFlip; (b) 1-2 non-WWXRP → committed UNPAID, no revert; (c) 0 resolved → `revert NoWork()`; (d) 3 WWXRP-only → resolved, UNPAID, no revert; (e) 2 WWXRP + 3 non-WWXRP → paid. Count via the TST-02 `_countCoinflipStakeUpdated` oracle (flat ONE, never the retired `3 * peg` sum).

**Hardhat secondary gate** (CONTEXT discretion, NO edit): re-confirm `test/stat/Degenerette{ProducerChi2,BonusEv,PerNEvExactness}.test.js` stay GREEN (chi²/EV unchanged) — `npx hardhat test test/stat/Degenerette*.test.js`. (Assumption A2 — run once during execution to confirm.)

---

### The 17 premise-retired reds — DELETE + re-author fresh (D-04)

**Methodology:** for EACH red, Read its CURRENT body to confirm the retired premise, DELETE it, and re-author the v49 invariant in the home below. Re-express no-double-buy in storage-oracle terms (`lastAutoBoughtDay` / pool-balance-delta) using the migrated `AfKingConcurrency` helpers — NEVER the deleted `AutoBought` event. **SAFE-03 / H-CANCEL-SWAP MUST be PRESERVED** (hard constraint).

| # | File (current) | Test | Retired premise | Re-author home (analog) |
|---|----------------|------|-----------------|--------------------------|
| 1 | `CrankFaucetResistance` | `testBatchEmitsExactlyOneCreditFlipWithSum` | per-item *summed* creditFlip | TST-05 flat-per-tx one credit (`DegeneretteFreezeResolution` capture) |
| 2 | `CrankFaucetResistance` | `testCrankBeforeRngWordSkipsAndDoesNotReward` | per-leg skip-no-reward | TST-02: `doWork` routes past + `revert NoWork()` (`AfKing.sol:910`) |
| 3 | `CrankFaucetResistance` | `testDuplicateInBatchRewardsOnce` | per-item dup reward | TST-05 flat ≥3-gate shape |
| 4 | `CrankFaucetResistance` | `testFuzz_MultiBoxRoundTripNonPositiveAcrossGasPrices` | summed-box round-trip | TST-02/03 open pro-rate-below-knee round-trip ≤0 (`AfKing.sol:905-906`) |
| 5 | `CrankFaucetResistance` | `testFuzz_RoundTripNonPositiveAcrossGasPrices` | per-item round-trip | TST-02/03 flat-per-tx round-trip ≤0 |
| 6 | `CrankFaucetResistance` | `testMultiBoxSelfCrankRoundTripNonPositive` | summed-box self-crank ≤0 | TST-02/03 open-leg self-crank ≤0 under `doWork` |
| 7 | `CrankFaucetResistance` | `testSelfCrankRoundTripNonPositive` | per-leg self-crank ≤0 | TST-02/03 self-exclude + ETH-work-gate ≤0 |
| 8 | `CrankFaucetResistance` | `testWinningBetFullResolvePathStillPegsReward` | per-item peg + winnings | TST-05 flat ≥3 creditFlip alongside winnings |
| 9 | `CrankFaucetResistance` | `testZeroSuccessBatchEmitsNoCreditFlip` | zero-success no-credit (old path) | TST-05 `revert NoWork()` on 0 resolved (`:1629`) |
| 10 | `CrankLeversAndPacking` | `testCrankBetsEmitsExactlyOneCreditFlipForManyItems` (`:127`) | one creditFlip carrying the SUM of 3 item rewards (`:153` `3 * CRANK_RESOLVE_BET_GAS_UNITS * ...`) | TST-05 one flat `RESOLVE_FLAT_BURNIE` at ≥3 |
| 11 | `CrankLeversAndPacking` | `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` (`:167`) | an autoOpen-side creditFlip (= 1) | TST-02: autoOpen self-credits ZERO; `doWork` credits |
| 12 | `CrankNonBrick` | `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` (`:360`, `expectRevert RngLocked()` `:378`) | **RD-2 oracle-migration:** batchPurchase reverts under rngLock (guard DROPPED) | TST-01 autoBuy-during-rngLock SAFE; DELETE the revert assertion |
| 13 | `CrankNonBrick` | `testCrankBetsSkipsPoisonedMiddleItem` | one crank-reward (per-leg) | TST-05 per-item isolation + flat ≥3 shape |
| 14 | `CrankNonBrick` | `testCrankBoxesSkipsPoisonedEntryViaTryCatch` | autoOpen per-item try/catch (DROPPED at RD-5) | TST-01 entry-gate no-marooned-boxes (`DegenerusGame.sol:1692`) |
| 15 | `CrankNonBrick` | `testFuzz_CrankBetsPoisonPositionNeverBricks` | 2 healthy resolves at per-item peg | TST-05 per-item isolation + flat reward at ≥3 |
| 16 | `RngFreezeAndRemovalProofs` | `testCrankBetResolutionStaysPostUnlock` (`:129`) | resolution via old per-leg path | TST-05 `degeneretteResolve` post-unlock + ≥3/NoWork gate |
| 17 | `RngFreezeAndRemovalProofs` | `testFuzz_CrankResolvesIffWordLanded` (`:231`) | resolves-iff-word via old reward | TST-01/05 `boxesPending`/`autoOpen` rngLock-aware + NoWork |

**Anti-patterns the deletions remove** (RESEARCH §Anti-Patterns) — do NOT re-introduce: the retired per-item *summed* reward (`3 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF`, `CrankLeversAndPacking.t.sol:153`), any autoOpen/advance/autoBuy-side in-callee creditFlip assertion, the `batchPurchase`-reverts-under-rngLock assertion, and any `keccak256("AutoBought(...)")` topic-match.

> COUNT IS 17, NOT 16 (RESEARCH Pitfall 1). The 330-08 SUMMARY recorded +16; the live HEAD adds one
> (the 331 `CrankFaucetResistance`/`CrankNonBrick` extensions). **The planner MUST re-run `forge test`
> at the actual TST-execution HEAD and gate on the 42-name v48 union — not a bare count.** Any forge
> red NOT in the 42-union AND NOT in this 17-set = a NEW regression → STOP.

---

### 5 `Crank*` → `Keeper*` renames — `git mv` + symbol rename (D-07, pure rename)

**Analog (naming convention):** `test/gas/RouterWorstCaseGas.t.sol` (`contract RouterWorstCaseGas`, title `/// @title RouterWorstCaseGas -- GAS-01 (Phase 331) keeper-router worst-case...`) + `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (`contract KeeperBatchAffiliateDeltaAudit`). The convention: PascalCase, `Keeper*`-prefixed (or function-describing) contract name == file basename.

Rename surface (each = `git mv` + the `contract X is DeployProtocol {` decl + any in-repo cross-reference):

| Current file | Current `contract` decl | git mv target / contract |
|--------------|-------------------------|--------------------------|
| `test/fuzz/CrankFaucetResistance.t.sol` | `contract CrankFaucetResistance` (`:45`) | `Keeper*FaucetResistance` |
| `test/fuzz/CrankNonBrick.t.sol` | `contract CrankNonBrick` (`:48`) + helpers `ReentrantWithdrawer` (`:1020`) / `interface AfKingLike` (`:1062`) — leave helper names if not "crank" | `Keeper*NonBrick` |
| `test/gas/CrankLeversAndPacking.t.sol` | `contract CrankLeversAndPacking` (`:48`) | `Keeper*LeversAndPacking` |
| `test/gas/CrankOpenBoxWorstCaseGas.t.sol` | `contract CrankOpenBoxWorstCaseGas` (`:29`) | `Keeper*OpenBoxWorstCaseGas` |
| `test/gas/CrankResolveBetWorstCaseGas.t.sol` | `contract CrankResolveBetWorstCaseGas` (`:48`) | `Keeper*ResolveBetWorstCaseGas` |

**Zero-residual check** (RESEARCH Runtime State Inventory): after the rename, `grep -rn Crank test/` must return only (a) the v49 ledger's deliberate historical record and (b) comment prose documenting provenance. **DO NOT touch** `CrankLeversAndPacking::testGas02ReadOnceAndOneTransferSourcePresence` greps of `degeneretteResolve(` — that is a CONTRACT symbol (unchanged), not a test-file name. `forge build` recompiles renamed artifacts automatically (artifacts key on contract name). The planner decides the exact new prefix word (the user dislikes "crank"; "Keeper" matches the two precedent files).

---

### `test/REGRESSION-BASELINE-v49.md` — NEW markdown ledger (D-06, NOT a `.sol` test)

**Analog:** `test/REGRESSION-BASELINE-v48.md` — mirror its §1–§5 shape exactly:
- §1 — arithmetic table (`640 passed − 17 deleted = 623 baseline pass`, then `+ N` fresh green; `59 failed − 17 deleted = 42` = the v48 union). Mirror the v48 §1 "baseline / wave delta / actual" table.
- §2 — the AUTHORITATIVE 42-red expected union BY NAME (carry forward the v48 §2 Buckets A/B/C verbatim — they are UNCHANGED).
- §3 (NEW vs v48) — the 17 deletions with per-test re-homing justification (the table above), classified reward-shape vs oracle-migration (RD-2 guard-drop / no-double-buy).
- §4 (NEW vs v48) — the 5 `Crank*`→`Keeper*` renames (so file-path churn is attributable; NON-WIDENING is about the red-set/behavior, not file names).
- §5 — the new green proof files (TST-02/03/05) + the two 331-added green files (`test/gas/RouterWorstCaseGas.t.sol` 13 tests, `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` 3 tests) under "new green proof files."
- §6 (mirror v48 §4) — the net-zero PROOF + per-suite last-touching-commit membership table.

**Force-add** (`.planning/` is gitignored — but `test/` is NOT, so the ledger commits normally; it lives in `test/`). Use the Write tool, NOT heredoc.

---

## Shared Patterns

### The creditFlip-count oracle (the single most-reused asset)
**Source:** `test/gas/CrankLeversAndPacking.t.sol:75` (`COINFLIP_STAKE_UPDATED_SIG`) + `:523-548` (`_countCoinflipStakeUpdated` / `_countCoinflipStakeUpdatedFor`).
**Apply to:** TST-02 (one-per-tx), TST-03 (advance unrewarded==0 / rewarded==1), TST-05 (flat ≥3 == 1).
**Why shared:** `creditFlip` emits exactly one `CoinflipStakeUpdated`; counting topic-0 (and isolating by indexed `player` = topic[1]) is the project's canonical "how many bounty credits fired this tx" oracle. Recipient-isolation separates the keeper's bounty from a box-owner's winnings credit.

### The no-double-buy storage oracle (GASOPT-04 migration — DONE, reuse)
**Source:** `test/fuzz/AfKingConcurrency.t.sol:767` (`_lastAutoBoughtDayOf` via `vm.load` slot-1 packed `Sub`), `:848` (`_snapshotBought`), `:861` (`_countAutoBoughtFor` = stamp-vs-baseline). The deleted `AutoBought` event is replaced; `_captureAutoBought` (`:835`) is now an alias that only drains `SubscriptionExpired`.
**Apply to:** TST-04 re-authored no-double-buy invariants (rows tied to SAFE-03), TST-01/02 buy-side proofs.
**Why shared:** the contract's own skip is `lastAutoBoughtDay >= today` (`AfKing.sol:626`); the stamp is the authoritative oracle. SAFE-03 / H-CANCEL-SWAP must be PRESERVED — these helpers are how.

### The comment-stripped source-grep attestation (structural proofs)
**Source:** `test/gas/CrankLeversAndPacking.t.sol` `_stripComments` (ends `:634`) + `_countOccurrences` + `vm.readFile(AFKING_SRC)` (`:221`); `fs_permissions = [{access="read", path="./contracts"}]` (`foundry.toml`).
**Apply to:** TST-02 D-01 structural reentrancy attestation (no untrusted call + single CEI-last `creditFlip`); any "guard byte-present" pin.
**Why shared:** comment-stripping prevents NatSpec prose from self-satisfying a grep gate; every `>0`/`==N` gate runs over stripped source. The `creditFlip(msg.sender, bountyEarned)` gate already exists at `:257`.

### The snapshot → run-A → revert → run-B → assertEq deltas equality harness
**Source:** `test/fuzz/DegeneretteFreezeResolution.t.sol:351-433` (`_replayPerSpinBaseline` + delta `assertEq`); `vm.snapshot`/`vm.revertTo` from `RngLockDeterminism.t.sol:130-134`.
**Apply to:** TST-03 GASOPT-01/03 behavioral-equality, TST-05 RESULTS-equality (BURNIE/WWXRP mints + claimable/pool deltas + RNG draws).
**Why shared:** the project's same-results idiom (v48 Phase 327) is "capture deltas two ways against a snapshot, assert byte-equal" — never a bytecode diff, never resurrected old source.

### The DeployProtocol base + MockVRF drain
**Source:** every Foundry test `is DeployProtocol` (`test/fuzz/helpers/DeployProtocol.sol`); `VRFHandler` + `MockVRFCoordinator` (`contracts/mocks/MockVRFCoordinator.sol`); the `_completeDay` / `_deliverMockVrf` drain loop (`RngLockDeterminism.t.sol:73-128`).
**Apply to:** ALL new Foundry proof files (TST-02/03/05) and the TST-01 extension.
**Why shared:** uniform deploy + VRF-mock fulfillment is the precondition for every advance/resolve/open path; `game`, `coinflip`, `afKing`, `coin`, `wwxrp`, `vault`, `dgnrs`, `affiliate`, `admin`, `mockVRF` are all `DeployProtocol` members.

---

## No Analog Found

None. Every author-target maps to a strong in-repo analog (the freeze harness, the count oracle, the storage-stamp oracle, the same-results replay scaffold, the keeper-* naming precedent, the v48 ledger). The only genuinely NEW construction is the TST-01 router perturbation CLASSES (cls 9/10) — but those slot into the existing `_perturb` library, not a new harness.

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| (none) | — | — | — |

---

## Metadata

**Analog search scope:** `test/fuzz/`, `test/gas/`, `test/stat/`, `test/invariant/`, `test/REGRESSION-BASELINE-v48.md`; contract READ-ONLY anchors in `contracts/AfKing.sol`, `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/modules/DegenerusGameMintModule.sol`.
**Files scanned:** 9 analog test files read (RngLockDeterminism, CrankLeversAndPacking, AfKingConcurrency, DegeneretteFreezeResolution, AdvanceGameRewrite, CrankNonBrick, RngFreezeAndRemovalProofs, REGRESSION-BASELINE-v48, RouterWorstCaseGas/KeeperBatchAffiliateDeltaAudit headers) + 3 contract sources.
**No project CLAUDE.md or `.claude/skills`/`.agents/skills` present** — conventions sourced from the existing test tree + MEMORY feedback (hyphen-form commands, security-over-gas floor, tests agent-committable, read contracts from `contracts/` only).
**Pattern extraction date:** 2026-05-27
