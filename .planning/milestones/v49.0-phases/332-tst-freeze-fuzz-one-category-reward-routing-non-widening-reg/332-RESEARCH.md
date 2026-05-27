# Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression - Research

**Researched:** 2026-05-27
**Domain:** Foundry + Hardhat test authoring for a FROZEN smart-contract audit subject (v49 keeper-router). No mainnet `contracts/*.sol` mutation. Tests are agent-committable.
**Confidence:** HIGH (all claims grep-verified against the committed source + a live `forge test` run this session)

## Summary

Phase 332 proves the v49 unified keeper-router composition behaviorally correct **empirically** and restores a clean **NON-WIDENING** v49 regression ledger against the GAS-calibrated constants landed at Phase 331. Five proofs (TST-01..05). This is a `test/` + `.planning/` phase — the audit subject is frozen at commit `63bc16ca` (the 330 batched diff) + `4c9f9d9b` (the 331 GAS constants). The current live HEAD is `2b20f420`.

The single load-bearing empirical fact this session establishes: a live `forge test` (default profile) run yields **640 passed / 59 failed**. All **42** v48.0-baseline reds (enumerated by name in `test/REGRESSION-BASELINE-v48.md §2`) are STILL red — verified 42/42 present, 0 flipped. The remaining **17** reds (NOT 16 — see the correction below) are the reward-rehoming / premise-retired set that the 330 contract diff flipped from green-at-v48 to red-at-v49. They are exactly the tests TST-04 deletes-and-re-authors. The 330-08 SUMMARY recorded "+16" at the 616/58 HEAD; the count is **17** at the live HEAD because Phase 331's CrankFaucetResistance/CrankNonBrick extensions (commits `46f30546` / `4c9f9d9b`) added one more premise-retired case and re-exercised the round-trip fuzz set under the new model. **The v49 ledger MUST record 17, not 16** — this is the binding correction the planner must carry.

**Primary recommendation:** Build TST-04 first (it is the gate the other four feed into): delete the 17 enumerated premise-retired reds, re-author the v49 invariants fresh in storage-oracle terms, `git mv` the 5 `Crank*` files to `Keeper*`, and author `test/REGRESSION-BASELINE-v49.md` whose binding headline is "failing returns to exactly the 42 v48-baseline reds; passing = (640 − 17 deleted) + N fresh green proofs." TST-01 extends `RngLockDeterminism.t.sol` with a router same-tx perturbation action; TST-02/03/05 are new/extension files in storage-oracle + behavioral-equality + RESULTS-equality terms per the locked methodology.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**TST-02 — one-category / reentrancy disposition:**
- **D-01 (reentrancy is STRUCTURAL — no attacker harness):** `doWork` pays only minted FLIP CREDIT (`creditFlip`), makes NO ETH push, every external call targets a pinned `ContractAddresses.*` (GAME / COINFLIP). TST-02's "router→game→creditFlip double-pay regression" is satisfied by a **STRUCTURAL ATTESTATION** — grep-proven: (a) no untrusted external call in any leg (`_autoBuy` / `advanceGame` / `autoOpen`), and (b) the single `creditFlip` site is CEI-last after the one-category early-return (`AfKing.sol:913-918`). **NO attacker harness is built.** *(User verbatim: "reentrancy is not an issue, nothing here pays eth and this only interacts with trusted contracts.")*
- **D-02 (no-stacking proven by COUNTING `creditFlip` calls):** Assert **EXACTLY one** `COINFLIP.creditFlip` call per `doWork()` tx (via `vm.expectCall` / `vm.recordLogs`) across all three category branches (buy / advance / open), **including the `bountyEarned==0` skip path** (a buy chunk that walked only already-bought subs runs the category but credits zero — zero `creditFlip` calls, still no revert). NOT exact-amount assertions; NOT both.
- **D-03 (rest of TST-02 = planner territory):** parameterless-`doWork()` default-batch / remainder-for-next-call (no-OOG) proof per D-07; standalone parametered + UNREWARDED `autoBuy(count)` / `autoOpen(count)` emergency escapes — planner constructs.

**TST-04 — deferred-red disposition + NON-WIDENING ledger:**
- **D-04 (delete + re-author fresh — NOT repair-in-place, NOT hybrid):** DELETE all the reward-rehoming reds and RE-AUTHOR the v49 invariants fresh. No-double-buy re-expressed in storage-oracle terms (`lastAutoBoughtDay` storage / pool-balance-delta per GASOPT-04). **SAFE-03 / H-CANCEL-SWAP MUST be PRESERVED, not weakened** (hard constraint). The retired per-item *summed* reward premise is replaced by the flat-per-tx one-credit-per-tx proof (D-02).
- **D-05 (ledger arithmetic):** After deleting the premise-retired set, failing returns to **EXACTLY the 42 v48.0-baseline reds** — net-zero new regression. The 42-red union carries forward UNCHANGED; any forge red NOT in that union is a NEW regression → STOP. The deletions are recorded with a per-test re-homing justification.
- **D-06 (author `test/REGRESSION-BASELINE-v49.md`):** Mirror `test/REGRESSION-BASELINE-v48.md` — record (a) the 42-red carried-forward union by name, (b) the deletions with re-homing justification, (c) the new green proof files, (d) the `Crank*`→keeper-* file renames.
- **D-07 (de-crank the test tree):** Rename the 5 surviving `Crank*`-named files to keeper-* names + their internal contract/symbol names — pure rename (`git mv` + reference update), zero behavioral change, recorded in the v49 ledger. Files: `test/fuzz/CrankFaucetResistance.t.sol`, `test/fuzz/CrankNonBrick.t.sol`, `test/gas/CrankLeversAndPacking.t.sol`, `test/gas/CrankOpenBoxWorstCaseGas.t.sol`, `test/gas/CrankResolveBetWorstCaseGas.t.sol`.

### Claude's Discretion
- **Proof-file homes (TST-02/03/05):** planner picks closest-analog homes — some new files, some extensions (TST-01 extends `RngLockDeterminism.t.sol`, locked by the roadmap). *(User: "you decide.")*
- **Freeze-fuzz depth (TST-01):** routine suite under the **default** foundry profile (fuzz 1000 / invariant 256×128); gate the **deep** freeze proof under `FOUNDRY_PROFILE=deep` (fuzz 10000 / invariant 1000×256) — the v44 INV precedent. Add a dedicated stateful invariant handler if the extension needs one. *(User delegated "the rest I'll resolve by precedent.")*
- **Same-results methodology (TST-03 GASOPT + TST-05 byte-identical):** GASOPT micro-opts (MintModule pointer + AfKing claimable-hoist, gas-only) → prove via **Foundry behavioral-equality**. `degeneretteResolve` byte-identical RESULTS → prove via **Foundry RESULTS-equality** (BURNIE/WWXRP mints, claimable/pool deltas, RNG draws identical vs the pre-rename per-item logic) **plus** the existing Hardhat Degenerette stat tests (`DegeneretteProducerChi2` / `DegeneretteBonusEv` / `DegenerettePerNEvExactness`) stay green. Mirrors the v48 Phase 327 same-results approach.
- **Hardhat parity:** keep the Hardhat side green at its v48 last-known parity (precedent-locked); the Foundry NON-WIDENING ledger is the authoritative regression gate.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. (Note: `degeneretteResolve` FOLDED INTO the on-chain router is OUT per the milestone, but the rename + re-peg ARE in scope.)

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TST-01 | Freeze-invariant fuzz (extends `RngLockDeterminism`): router advance-consume reads only frozen state mid-tx (`totalFlipReversals` class) even fired in the same tx as `autoBuy`/`autoOpen`; ADDS autoBuy-during-rngLock SAFE / autoOpen-blocked + no-marooned-boxes / unified one-category no-double-pay | The harness 6-phase template (snapshot→perturb→deliver-VRF→capture, revert→re-deliver→capture, assertEq byte-identity) is in `test/fuzz/RngLockDeterminism.t.sol`. The frozen-consume site is `AdvanceModule.sol:254-259` (`cw += totalFlipReversals` inside the advance drain). The `_perturb()` action library (`:152`, 9 actions, `N_PERTURB_ACTIONS=9`) currently has NO router action — TST-01 adds a `doWork`/`autoBuy`/`autoOpen` same-tx perturbation class. `boxesPending()` rngLock-aware (`DegenerusGame.sol:1655-1661`) + `autoOpen` entry-gate (`:1692`) are the no-marooned-boxes proof surface. |
| TST-02 | One-rewarded-category-per-tx (no stacking) + router→game→creditFlip double-pay disposition (structural) + parameterless-`doWork()` default-batch/remainder + standalone UNREWARDED escapes | `doWork()` `else-if` chain `AfKing.sol:883-919`; single `creditFlip` CEI-last `:916-918`; `bountyEarned==0` skip path `:893`/`:916`. Default batches: `BUY_BATCH=50` (`:850`), `OPEN_BATCH=100` (`:856`). Standalone unrewarded escapes: `autoBuy(count)` `:923`, `autoOpen(count)` `:929`. `vm.expectCall`/`vm.recordLogs` count oracle on `COINFLIP.creditFlip`. |
| TST-03 | `advanceGame` UNREWARDED standalone vs REWARDED via `doWork` (mult honored, mid-day partial-drain rewarded) + the two GASOPT micro-opts same-results | Standalone `game.advanceGame()` pays no bounty (the 3 in-callee `creditFlip` removed at ADV-01; `AdvanceModule.sol:154` returns only `uint8 mult`, no credit). Router pays `unit * ADVANCE_RATIO_NUM * mult` (`AfKing.sol:899`). mid-day `mult=1` (`AdvanceModule.sol:217-218`); new-day ladder 1/2/4/6 (`:235-241`); gameover `mult=0` unrewarded (`:187`). GASOPT-01 MintModule hoist sites `:399` + `:673`. GASOPT-02 SUBSUMED into GASOPT-03 `keeperSnapshot` (`DegenerusGame.sol:2628`). |
| TST-04 | Full-suite NON-WIDENING regression vs v48.0 (632/42 → net-zero new); GASOPT-04 oracle migration; v49 ledger | Live run: **640 passed / 59 failed**. 42/42 v48 reds present; **17** premise-retired reds (enumerated below). `lastAutoBoughtDay` oracle migration already landed in `AfKingConcurrency.t.sol` (`_lastAutoBoughtDayOf` / `_countAutoBoughtFor` re-expressed as stamp-vs-baseline at `:69-73`). |
| TST-05 | `degeneretteResolve` rename+re-peg: flat ~1 BURNIE/tx (not per-item), ≥3 non-WWXRP gate, revert-on-no-work, WWXRP excluded from gate+reward, byte-identical RESULTS | `degeneretteResolve` `DegenerusGame.sol:1595-1631`: `successCount` counts non-WWXRP (`currency != 3`, `:1619`); `if (totalResolved == 0) revert NoWork()` (`:1629`); `if (successCount >= 3) creditFlip(msg.sender, RESOLVE_FLAT_BURNIE)` (`:1630`); `RESOLVE_FLAT_BURNIE = 1e18` (`:1544`). RESULTS produced by the unchanged `_degeneretteResolveBet` → delegatecall `GAME_DEGENERETTE_MODULE.resolveBets` (`:1741-1755`) — the per-item payout math is untouched, so RESULTS-equality is structurally clean. Existing harness `test/fuzz/DegeneretteFreezeResolution.t.sol`; Hardhat stat `test/stat/Degenerette{ProducerChi2,BonusEv,PerNEvExactness}.test.js`. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Freeze-determinism fuzz (TST-01) | Foundry fuzz/invariant harness | Storage-slot oracle (`vm.load`) | Byte-identity of VRF-derived outputs is an on-chain state property; only Foundry's snapshot/revert + slot reads can perturb mid-window and assert identity. |
| One-category / no-stacking (TST-02) | Foundry behavioral (call/log count) | — | `creditFlip`-call counting via `vm.expectCall`/`vm.recordLogs` is the only way to observe "exactly one bounty per tx" without exact-amount coupling. |
| Reward routing (TST-03) | Foundry behavioral-equality | — | Standalone-vs-router reward presence + GASOPT same-results are observable as state deltas; no new tier. |
| Non-widening regression (TST-04) | Full `forge test` + markdown ledger | `git mv` for de-crank | The ledger is a plain-markdown gate (NOT a `.sol` test) recording the named red-set; the de-crank is pure file-path churn. |
| RESULTS-equality (TST-05) | Foundry RESULTS-equality | Hardhat stat (chi²/EV) | Payout/mint/RNG byte-identity is Foundry; statistical distribution invariance is the existing Hardhat stat tree (precedent-locked green). |

## Standard Stack

This is a test-authoring phase against a frozen audit subject. **No new dependencies are installed.** The stack is the project's existing test toolchain.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry `forge` | solc 0.8.34, via_ir, paris EVM | Fuzz/invariant/behavioral test execution; the authoritative NON-WIDENING gate | The whole `test/fuzz`, `test/gas`, `test/invariant` tree is Foundry; the v48 ledger was a `forge test` whole-tree run. `[VERIFIED: foundry.toml]` |
| Hardhat | `^2.28.3` (`@nomicfoundation/hardhat-toolbox ^6.1.0`) | Degenerette stat tests (chi²/EV-exactness), the TST-05 secondary gate | The Degenerette statistical invariants live in `test/stat/*.test.js` and run under Hardhat. `[VERIFIED: package.json]` |

### Supporting
| Capability | Mechanism | When to Use |
|------------|-----------|-------------|
| Default fuzz/invariant depth | `[fuzz] runs=1000`, `[invariant] runs=256 depth=128` | Routine CI suite for all TST-01..05 proofs `[VERIFIED: foundry.toml]` |
| Deep fuzz/invariant depth | `FOUNDRY_PROFILE=deep` → `runs=10000`, invariant `runs=1000 depth=256` | The gated TST-01 deep freeze proof only (confirmed live: `FOUNDRY_PROFILE=deep forge config` reports runs=10000 / depth=256) `[VERIFIED: foundry.toml + live forge config]` |
| Filesystem read | `fs_permissions = [{access="read", path="./contracts"}]` | The source-presence / structural-attestation tests `vm.readFile` the contract source (e.g. `CrankLeversAndPacking::testGas02ReadOnceAndOneTransferSourcePresence` greps the stripped source) `[VERIFIED: foundry.toml + CrankLeversAndPacking.t.sol:219-225]` |

**Installation:** None. (`forge` and `hardhat` already present; `forge build` exits 0 this session.)

## Package Legitimacy Audit

> Not applicable — this phase installs zero external packages. All work is authoring `.sol` test files and `.md` ledger docs against the existing toolchain. No npm/PyPI/crates surface.

## Architecture Patterns

### System Diagram — the proof composition

```
                        FROZEN audit subject (63bc16ca + 4c9f9d9b)
                                       │
         ┌─────────────────────────────┼─────────────────────────────┐
         │                             │                             │
   AfKing.doWork()              DegenerusGame                 AdvanceModule
   (one-category router)        (autoOpen/views/resolve)      (advanceGame return)
         │                             │                             │
   priority: buy→advance→open    boxesPending() rngLock-aware   mult=1 mid-day / 1·2·4·6 new-day
   single creditFlip CEI-last    autoOpen entry-gate            cw += totalFlipReversals (FROZEN read)
         │                             │                             │
         └──────────────┬──────────────┴──────────────┬──────────────┘
                        │                             │
              ┌─────────▼─────────┐         ┌─────────▼──────────┐
              │ FOUNDRY proofs    │         │ HARDHAT proofs     │
              │ (authoritative)   │         │ (TST-05 secondary) │
              └─────────┬─────────┘         └─────────┬──────────┘
                        │                             │
   TST-01 RngLockDeterminism (extend)        DegenerettePerNEvExactness
   TST-02 creditFlip-count oracle             DegeneretteBonusEv
   TST-03 reward-routing + GASOPT equality    DegeneretteProducerChi2
   TST-04 forge test whole-tree → ledger      (stay GREEN, chi²/EV unchanged)
   TST-05 RESULTS-equality (Foundry)
                        │
                        ▼
          test/REGRESSION-BASELINE-v49.md  ← NON-WIDENING gate
          (42 carried-forward + 17 deletions + Crank→Keeper renames + N fresh green)
```

### Pattern 1: The RngLockDeterminism 6-phase byte-identity template (TST-01)
**What:** Each fuzz function: (1) `_snapshotPreLock()` (`vm.snapshot`), (2) advance to the VRF-request boundary so `rngLocked()` is true and a `reqId` pends, (3) `_perturb(seed)` mid-window, (4) `_deliverMockVrf(reqId, word)` + capture a digest of VRF-derived outputs (logs + slot reads via `vm.load`), (5) `_revertToPreLock`, re-advance, re-deliver the SAME word WITHOUT perturbation, capture the baseline digest, (6) `assertEq(perturbed, baseline)`.
**When to use:** TST-01 extension — the new router same-tx case fires `doWork`/`autoBuy`/`autoOpen` as the perturbation (or in the same tx as the advance-consume) and asserts the VRF-derived advance output is byte-identical.
**Example:**
```solidity
// Source: test/fuzz/RngLockDeterminism.t.sol:130-144 (snapshot/revert/assert helpers)
function _snapshotPreLock() internal returns (uint256) { return vm.snapshot(); }
function _revertToPreLock(uint256 id) internal { vm.revertTo(id); }
function _assertVrfOutputByteIdentity(bytes32 p, bytes32 b, string memory l) internal pure { assertEq(p, b, l); }
// Add a new _perturb class (the lib at :152 has N_PERTURB_ACTIONS=9, cls 0..8 — add cls 9/10 for router):
//   else if (cls == 9) { try IAfKing(AF_KING).doWork() {} catch { return; } }
//   else if (cls == 10){ try IAfKing(AF_KING).autoBuy(0) {} catch { return; } }
// NOTE: bump N_PERTURB_ACTIONS accordingly; autoOpen during rngLock must NO-OP (boxesPending()==false).
```

### Pattern 2: creditFlip-call counting oracle (TST-02 / D-02)
**What:** Wrap a `doWork()` call in `vm.recordLogs()` (or `vm.expectCall(COINFLIP, abi.encodeWithSelector(creditFlip.selector, ...))` with a count) and assert exactly ONE `creditFlip` per tx across all three branches, plus ZERO on the `bountyEarned==0` skip path.
**When to use:** TST-02 no-stacking. The existing `CrankLeversAndPacking` helpers `_countCoinflipStakeUpdated()` / `_countCoinflipStakeUpdatedFor(addr)` are the precedent log-counter (they isolate the cranker's creditFlip from a box-owner's winnings credit).
**Example:**
```solidity
// Source: test/gas/CrankLeversAndPacking.t.sol:191-195 (recipient-isolated count)
assertEq(_countCoinflipStakeUpdatedFor(cranker), 1, "exactly one router creditFlip per tx");
```

### Pattern 3: RESULTS-equality via the unchanged delegatecall (TST-05)
**What:** `degeneretteResolve` only changed the bounty wrapper + ≥3 gate; the per-item payout is produced by `_degeneretteResolveBet → delegatecall GAME_DEGENERETTE_MODULE.resolveBets` (unchanged). RESULTS-equality is therefore: resolve N bets via `degeneretteResolve` and capture BURNIE/WWXRP mints + claimable/pool deltas + RNG draws, and assert they match the per-item baseline. Because the resolution logic is byte-identical, the only observable deltas vs the old path are (a) bounty SHAPE (flat ~1 BURNIE once vs per-item) and (b) the ≥3 gate.
**When to use:** TST-05. The freeze harness `DegeneretteFreezeResolution.t.sol` is the closest analog for the resolve/capture scaffold.

### Pattern 4: The plain-markdown NON-WIDENING ledger (TST-04 / D-06)
**What:** `test/REGRESSION-BASELINE-v49.md` is NOT a `.sol` test — it is a markdown gate mirroring `test/REGRESSION-BASELINE-v48.md`: §1 arithmetic, §2 the AUTHORITATIVE expected-red union BY NAME (the 42 carried-forward), §3 the deletions + re-homing justification, §4 the Crank→Keeper renames, §5 the new green proof files, §6 the net-zero proof + membership table (last-touching commit per failing suite).
**When to use:** TST-04 final wave. The v48 ledger structure (§1-§5) is the exact template.

### Anti-Patterns to Avoid
- **Re-asserting the retired per-item *summed* reward** (e.g. `3 * CRANK_RESOLVE_BET_GAS_UNITS * CRANK_GAS_PRICE_REF`). The v49 model pays flat-per-tx; the re-authored proof asserts ONE flat credit (D-02), never the sum. `CrankLeversAndPacking::testCrankBetsEmitsExactlyOneCreditFlipForManyItems` is the canonical wrong-premise.
- **Asserting an autoOpen-side / advance-side / autoBuy-side in-callee creditFlip.** RD-4 unified the bounty into `doWork`; the legs return raw counts/mult and NEVER self-credit. `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` (asserts an autoOpen creditFlip = 1; now 0) is the canonical wrong-premise.
- **Asserting `batchPurchase` reverts under rngLock.** RD-2/ROUTER-08 deliberately dropped that guard; `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` asserts the now-absent behavior — DELETE it, do not repair.
- **Reading the retired `AutoBought` event.** GASOPT-04 removed it; the no-double-buy oracle is `lastAutoBoughtDay` + pool-balance-delta (already migrated in `AfKingConcurrency.t.sol`). Any test still doing `keccak256("AutoBought(...)")` topic-match would be a landmine.
- **Building a synthetic reentrant attacker for TST-02.** D-01 forbids it — reentrancy is a STRUCTURAL grep-attestation (no untrusted call + single CEI-last creditFlip).
- **Coupling TST-01 to exact reward amounts.** TST-01 asserts VRF-derived output byte-identity, not bounty values.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mid-window state perturbation + revert | A custom snapshot manager | The existing `_snapshotPreLock`/`_revertToPreLock`/`_perturb` library in `RngLockDeterminism.t.sol` | The 6-phase template + 9-action perturbation lib + VRF mock drain are already debugged across 18 fuzz functions. Extend, don't reinvent. |
| creditFlip-call counting | Manual log topic decoding inline | `_countCoinflipStakeUpdated()` / `_countCoinflipStakeUpdatedFor(addr)` from `CrankLeversAndPacking.t.sol` | Already handles isolating the cranker's credit from a box-owner's winnings credit (the LootboxModule:1036 credit). |
| No-double-buy oracle | A new event or counter | `_lastAutoBoughtDayOf` / `_countAutoBoughtFor` (stamp-vs-baseline) in `AfKingConcurrency.t.sol:69-73` | The GASOPT-04 migration is DONE; the stamp is the same `lastAutoBoughtDay >= today` skip the contract reads at `AfKing.sol:626`. |
| Degenerette statistical invariance | New chi²/EV harness | The existing `test/stat/Degenerette*.test.js` (Hardhat) | Precedent-locked green; TST-05 only re-confirms they stay green after the rename. |
| The regression ledger | A runnable `.sol` gate | A plain-markdown `REGRESSION-BASELINE-v49.md` | The v48 precedent is markdown; it records the named red-set, not an executable assertion (which would couple to the exact 42). |

**Key insight:** This entire phase is "extend the existing harnesses + delete-and-re-author the premise-retired set + write a markdown ledger." The hand-rolling risk is re-deriving the freeze template or the creditFlip counter — both exist and are battle-tested.

## Runtime State Inventory

> This is a rename/refactor-adjacent phase (D-07 de-crank). The Runtime State Inventory applies.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — tests use ephemeral Foundry/Hardhat in-memory state, no persistent datastore. Verified: no DB, no fixture file with embedded "crank". | None |
| Live service config | None — no external service holds a "Crank" identifier. The de-crank is internal test-tree only. | None |
| OS-registered state | None — no OS task/scheduler references these test files. | None |
| Secrets/env vars | `FOUNDRY_PROFILE=deep` is the only env var the phase relies on (selecting the deep fuzz profile); it is a foundry-builtin, not a project secret. `CONTRACTS_COMMIT_APPROVED` is irrelevant here (no `.sol` mainnet edits). | None |
| Build artifacts | `forge-out/` (the `out` dir) caches compiled artifacts; a `git mv` of a test file + symbol renames are picked up on the next `forge build` automatically. No stale-artifact hazard for test renames (artifacts key on contract name, recompiled on change). | None — `forge build` recompiles automatically |

**The de-crank rename surface (D-07):** 5 files to `git mv` + internal `contract`/symbol renames. The canonical question "after every file is updated, what still references the old name?" resolves to: ONLY in-repo test cross-references (e.g. `CrankNonBrick`'s contract name, any `is`/import of a renamed helper). Grep `Crank` across `test/` after the rename to confirm zero residual (excluding the v49 ledger's deliberate historical record + the `CrankFaucetResistance` etc. comment prose that documents provenance). Note the source-presence test `CrankLeversAndPacking::testGas02ReadOnceAndOneTransferSourcePresence` greps the CONTRACT source for `degeneretteResolve(` — that is a CONTRACT symbol (unchanged), not a test-file name, so the rename does not touch it.

## Common Pitfalls

### Pitfall 1: The count is 17, not 16
**What goes wrong:** The planner copies "16 reward-rehoming reds" from the 330-08 SUMMARY and the ledger arithmetic is off by one → the NON-WIDENING proof fails to reconcile.
**Why it happens:** The 330-08 SUMMARY recorded 616/58 = +16 at the 330 HEAD. Phase 331 then extended `CrankFaucetResistance.t.sol` / `CrankNonBrick.t.sol` (commits `46f30546`, `4c9f9d9b`) — the live HEAD `2b20f420` now reports **640/59**, and cross-referencing the 59 against the 42 v48 union leaves **17** premise-retired reds.
**How to avoid:** Use the 17-red enumeration below (verified this session). The arithmetic: `640 passed − 17 deleted = 623 baseline pass`, then `+ N` fresh green proofs; `59 failed − 17 deleted = 42` = exactly the v48 union. **The planner must re-run `forge test` at the actual TST-execution HEAD and re-confirm the count** — if 331 bookkeeping or another commit lands between now and execution, the number can shift again. The ledger's binding invariant is "failing red-set == the 42 v48 union by NAME," not a bare count.
**Warning signs:** A forge red whose name is not in the 42 v48 union AND not in the 17-deletion set → genuine NEW regression → STOP.

### Pitfall 2: The StakedStonk vm.assume over-rejection baseline red
**What goes wrong:** `testFuzz_RngLockDeterminism_StakedStonkRedemption` fails with "`vm.assume` rejected too many inputs (65536 allowed)" — a fuzzer-exhaustion red, NOT a logic failure. If TST-01 touches this file, the planner might "fix" it and accidentally change the v48-baseline red-set.
**Why it happens:** The test (`RngLockDeterminism.t.sol:1263`) is NOT `vm.skip`'d (it was flipped to strict assertion at v44 for V-184); its `bound` + multiple `try/catch{vm.assume(false)}` filters reject too many fuzz inputs at the default 1000 runs. It is a documented v48-baseline red (Bucket A7).
**How to avoid:** TST-01 EXTENDS this harness with NEW router functions — it must NOT alter the existing `StakedStonkRedemption` function. The v49 ledger carries A7 forward UNCHANGED. Do not refactor its vm.assume filters.
**Warning signs:** The StakedStonk red disappearing from the forge red-set (means the test was changed → red-set widened/narrowed, attribution broken).

### Pitfall 3: autoOpen during rngLock must be a NO-OP, not a revert
**What goes wrong:** A TST-01 same-tx test fires `autoOpen` during rngLock expecting a revert (the old pre-RD-3 behavior) and the test fails because the v49 `autoOpen` returns 0 silently.
**Why it happens:** RD-3/RD-5 changed `autoOpen` to an entry-gate `if (rngLockedFlag || _livenessTriggered()) return 0;` (`DegenerusGame.sol:1692`) — it no-ops, never reverts. `boxesPending()` returns false during rngLock (`:1656`), so `doWork` routes past the open leg.
**How to avoid:** TST-01's "autoOpen-blocked-during-rngLock + no-marooned-boxes" assertion checks (a) `boxesPending()==false` during lock, (b) `autoOpen(N)` returns 0 and opens nothing during lock, (c) after the word lands and lock clears, the SAME boxes open with the cursor intact (no marooning — the entry-gate makes the loop body non-reverting so the cursor never strands a tail).
**Warning signs:** An `expectRevert` on `autoOpen` during lock.

### Pitfall 4: The advance-consume frozen read is `cw += totalFlipReversals` inside the drain
**What goes wrong:** TST-01 perturbs `totalFlipReversals` AFTER the advance has already consumed it, missing the window, and the byte-identity holds vacuously.
**Why it happens:** The frozen read is at `AdvanceModule.sol:254-259` — inside the daily drain, `cw = rngWordCurrent; cw += totalFlipReversals; _finalizeLootboxRng(cw)`. The freeze invariant (ADV-04) is that `totalFlipReversals` is fixed between the VRF request and the consume. The perturbation must change `totalFlipReversals` (e.g. via a flip-reversal purchase) BETWEEN the request boundary and the advance-consume, in the same locked window.
**How to avoid:** Perturb in the snapshot→deliver window (the existing template already does this); ensure the perturbation action actually moves `totalFlipReversals` (the `placeDegeneretteBet` / `purchase` cls actions do). Capture the VRF-derived trait/word output (`_readRngWordCurrent()` / slot-0 / trait digest), not a value that's independent of the nudge.
**Warning signs:** Byte-identity passing even when the perturbation is a no-op (vacuous proof) — add a non-vacuity assertion that the perturbation actually changed `totalFlipReversals` pre-revert.

### Pitfall 5: GASOPT-03 SUBSUMED GASOPT-02 — there is no separate "claimable-hoist" site
**What goes wrong:** TST-03 looks for an AfKing per-iteration `claimableWinningsOf` hoist (the original GASOPT-02) and can't find it.
**Why it happens:** GASOPT-02 was SUBSUMED into GASOPT-03: the per-player `claimableWinningsOf` STATICCALLs were replaced by ONE batched `keeperSnapshot(address[])` read (`DegenerusGame.sol:2628`; AfKing consumes it at `:807`). The "two GASOPT micro-opts" the roadmap SC3 names are now (1) MintModule `owedMap` pointer hoist (GASOPT-01, sites `:399`+`:673`) and (2) the `keeperSnapshot` batched read (GASOPT-03). The CONTEXT's "AfKing claimable-hoist" phrasing refers to GASOPT-03's effect.
**How to avoid:** TST-03 same-results proves: (a) GASOPT-01 — `processTicketBatch`/`processFutureTicketBatch` produce identical ticket-processing results with the hoisted pointer; (b) GASOPT-03 — `keeperSnapshot` returns the SAME `(mintPrice, rngLocked, claimables[])` as N individual `claimableWinningsOf` calls, and an autoBuy driven through it produces identical buy outcomes. Behavioral-equality, not bytecode-diff.
**Warning signs:** Searching `AfKing.sol` for a per-iter `claimableWinningsOf` STATICCALL (it was eliminated — VERIFICATION confirms count 0).

### Pitfall 6: TST-05 must exclude WWXRP from BOTH the gate count AND the reward
**What goes wrong:** A TST-05 test resolves 3 WWXRP bets and expects a creditFlip (because 3 resolved), but the contract pays nothing (WWXRP excluded from the ≥3 count).
**Why it happens:** `degeneretteResolve` counts `successCount` only for `currency != 3` (WWXRP is currency 3) at `:1612-1619`; the ≥3 gate keys on `successCount` (non-WWXRP), but `totalResolved` (any) drives the revert-on-no-work. So: 3 WWXRP resolutions → `totalResolved=3` (no revert), `successCount=0` (no reward).
**How to avoid:** TST-05 cases: (a) ≥3 non-WWXRP → exactly one `RESOLVE_FLAT_BURNIE` creditFlip; (b) 1-2 non-WWXRP resolved → committed UNPAID, no revert (don't strand the tail); (c) 0 resolved → `revert NoWork()`; (d) 3 WWXRP-only → resolved, UNPAID, no revert; (e) mixed (e.g. 2 WWXRP + 3 non-WWXRP) → paid (3 non-WWXRP ≥ gate).

## Code Examples

### TST-02: the `doWork` one-category early-return + skip path
```solidity
// Source: contracts/AfKing.sol:883-919 (the structure the no-stacking proof keys on)
function doWork() external {
    uint256 mp = IGame(ContractAddresses.GAME).mintPrice();
    uint256 unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mp;
    uint256 bountyEarned;
    if (_autoBuyDay != _currentDay() || _autoBuyCursor < _subscribers.length) {
        uint256 bought = _autoBuy(BUY_BATCH);
        if (bought > 0) bountyEarned = (unit * BUY_RATIO_NUM) / BUY_RATIO_DEN; // flat, NOT count-scaled
    } else if (IGame(ContractAddresses.GAME).advanceDue()) {
        uint8 mult = IGame(ContractAddresses.GAME).advanceGame();
        if (mult > 0) bountyEarned = unit * ADVANCE_RATIO_NUM * mult; // mult==0 (gameover) pays nothing
    } else if (IGame(ContractAddresses.GAME).boxesPending()) {
        uint256 opened = IGame(ContractAddresses.GAME).autoOpen(OPEN_BATCH);
        uint256 k = opened < OPEN_KNEE ? opened : OPEN_KNEE;
        bountyEarned = (unit * k) / OPEN_KNEE; // pro-rated below the knee
    } else {
        revert NoWork(); // ROUTER-06: all 3 O(1) predicates empty
    }
    if (bountyEarned > 0) {                                    // the bountyEarned==0 SKIP path:
        ICoinflip(ContractAddresses.COINFLIP).creditFlip(msg.sender, bountyEarned); // ZERO creditFlip, no revert
    }
}
```

### TST-04: the live regression-gate command
```bash
# Source: the v48 ledger ran `forge test` whole-tree (NOT --match-path). Re-run at the TST HEAD:
forge test                                  # default profile — the authoritative NON-WIDENING gate
forge test --summary                        # for the pass/fail reconciliation (640/59 this session)
forge test --json > /tmp/forge.json         # for the per-suite::test red-set membership check
# Deep freeze proof (TST-01 only):
FOUNDRY_PROFILE=deep forge test --match-contract RngLockDeterminism
# Hardhat Degenerette stat secondary gate (TST-05):
npx hardhat test test/stat/DegenerettePerNEvExactness.test.js \
                 test/stat/DegeneretteBonusEv.test.js \
                 test/stat/DegeneretteProducerChi2.test.js
```

## The 17 premise-retired reds — the TST-04 delete-and-re-author set

> **VERIFIED this session** by cross-referencing the live 59-red set against the 42-name v48 union. Each is GREEN at v48.0 and flipped RED by the 330 contract diff `63bc16ca` (the unified-bounty / dropped-guard model). All introduced by v46 Phase 318/319 commits (the OLD per-leg/per-item crank model). **Classify each in the v49 ledger as reward-shape (premise retired) or oracle-migration (no-double-buy / RD-2 guard-drop).**

| # | File (→ keeper-* rename) | Test | Retired premise | Re-author target (v49) |
|---|--------------------------|------|-----------------|------------------------|
| 1 | CrankFaucetResistance | `testBatchEmitsExactlyOneCreditFlipWithSum` | per-item *summed* creditFlip amount | flat-per-tx one credit (D-02) |
| 2 | CrankFaucetResistance | `testCrankBeforeRngWordSkipsAndDoesNotReward` | old skip-and-no-reward via per-leg credit (now `NoWork()`) | `doWork` routes past + `NoWork()` when empty |
| 3 | CrankFaucetResistance | `testDuplicateInBatchRewardsOnce` | per-item dup reward = once at per-item peg | flat ≥3-gate reward shape |
| 4 | CrankFaucetResistance | `testFuzz_MultiBoxRoundTripNonPositiveAcrossGasPrices` | summed-box price-independent reward | open pro-rate-below-knee round-trip ≤0 (GAS-05) |
| 5 | CrankFaucetResistance | `testFuzz_RoundTripNonPositiveAcrossGasPrices` | per-item fixed reward round-trip | flat-per-tx round-trip ≤0 |
| 6 | CrankFaucetResistance | `testMultiBoxSelfCrankRoundTripNonPositive` | summed-box self-crank ≤0 | open-leg self-crank ≤0 under doWork |
| 7 | CrankFaucetResistance | `testSelfCrankRoundTripNonPositive` | per-leg self-crank ≤0 | doWork self-exclude + ETH-work-gate ≤0 |
| 8 | CrankFaucetResistance | `testWinningBetFullResolvePathStillPegsReward` | per-item peg alongside a winnings credit | flat ≥3-gate creditFlip alongside winnings |
| 9 | CrankFaucetResistance | `testZeroSuccessBatchEmitsNoCreditFlip` | zero-success → no credit via old path (now `NoWork()` on 0 resolved) | `degeneretteResolve` `revert NoWork()` on 0 |
| 10 | CrankLeversAndPacking | `testCrankBetsEmitsExactlyOneCreditFlipForManyItems` | one creditFlip carrying the SUM of 3 item rewards | one flat `RESOLVE_FLAT_BURNIE` at ≥3 |
| 11 | CrankLeversAndPacking | `testCrankBoxesEmitsExactlyOneCreditFlipForManyBoxes` | an autoOpen-side creditFlip (= 1) | autoOpen self-credits ZERO; doWork credits (TST-02) |
| 12 | CrankNonBrick | `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` | **RD-2 oracle-migration:** batchPurchase reverts under rngLock (guard now DROPPED) | autoBuy-during-rngLock SAFE (TST-01); DELETE the revert assertion |
| 13 | CrankNonBrick | `testCrankBetsSkipsPoisonedMiddleItem` | one crank-reward creditFlip for the batch (per-leg) | per-item isolation + flat ≥3 reward shape |
| 14 | CrankNonBrick | `testCrankBoxesSkipsPoisonedEntryViaTryCatch` | autoOpen per-item try/catch (DROPPED at RD-5 — entry-gate instead) | entry-gate no-marooned-boxes (TST-01) |
| 15 | CrankNonBrick | `testFuzz_CrankBetsPoisonPositionNeverBricks` | 2 healthy resolves rewarded at per-item peg | per-item isolation + flat reward at ≥3 |
| 16 | RngFreezeAndRemovalProofs | `testCrankBetResolutionStaysPostUnlock` | resolution via old per-leg path (now `NoWork()` shape) | degeneretteResolve post-unlock + ≥3/NoWork gate |
| 17 | RngFreezeAndRemovalProofs | `testFuzz_CrankResolvesIffWordLanded` | resolves-iff-word via old reward (now `NoWork()` on no word) | boxesPending/autoOpen rngLock-aware + NoWork |

**Provenance (all GREEN at v48, RED at v49 — verified):** rows 1-3,5-9 from `3afbf676` (318-02 SAFE-01); rows 4,6 from `795e679d` (319-05 CR-01 multi-box); rows 10-11 from `dfba3ac1` (319-04 GAS-02 levers); rows 12-15 from `47b9d031` (318-03 SAFE-02 non-brick); rows 16-17 from `b9bc5206` (318-05 SAFE-04). None last-touched by a 327/v48 wave commit → they were green in the v48 ledger.

**Two NEW green test files added since v48 baseline (Phase 331, contribute only PASSING tests):** `test/gas/RouterWorstCaseGas.t.sol` (13 tests) and `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (3 tests). The v49 ledger records these under "new green proof files."

## State of the Art

| Old Approach (v46-v48) | Current Approach (v49) | When Changed | Impact on TST |
|------------------------|------------------------|--------------|---------------|
| Per-leg in-callee `creditFlip` (advance ×3 + autoOpen + autoBuy) | ONE unified `creditFlip` CEI-last in `doWork` (RD-4) | 330 `63bc16ca` | Rows 1,3,5,8,10,11,13,15 retired |
| `doWork(maxCount)` + `maxCount==0` sentinel | parameterless `doWork()` + fixed per-leg defaults (`BUY_BATCH=50`/`OPEN_BATCH=100`) | 330 (D-07) | TST-02 default-batch/remainder proof |
| Per-item summed crank reward (`N × peg`) | flat-per-tx per-category (`advance 2×·mult / buy 1.5× / open 1×-pro-rated`) | 331 `4c9f9d9b` (GAS-02) | TST-02/03 assert flat shape; round-trip ≤0 |
| `batchPurchase` rngLock pre-check (`:1737`) + AfKing `_autoBuy` rngLock guard (`:568`) | both DROPPED; autoBuy = normal buy, queues pre-entropy (RD-2) | 330 | Row 12 retired; TST-01 autoBuy-during-lock SAFE |
| `autoOpen` per-item try/catch | entry-gate `if (rngLocked || liveness) return 0` + `_autoOpenBox` internal (RD-5) | 330 | Row 14 retired; TST-01 no-marooned-boxes |
| `AutoBought` event (no-double-buy oracle) | `lastAutoBoughtDay` storage stamp + pool-balance-delta (GASOPT-04) | 330 | Oracle MIGRATED (done in AfKingConcurrency); TST-04 keeps SAFE-03/H-CANCEL |
| `autoResolve` / `_autoResolveBet` (per-item break-even bounty) | `degeneretteResolve` / `_degeneretteResolveBet` (flat ~1 BURNIE, ≥3 non-WWXRP gate) | 330 rename + 331 re-peg | TST-05 rename + re-peg + RESULTS-equality |
| N per-player `claimableWinningsOf` STATICCALLs | ONE batched `keeperSnapshot(address[])` (GASOPT-03, SUBSUMES GASOPT-02) | 330 | TST-03 same-results (batched == individual) |

**Deprecated/outdated:**
- `AutoBought` event — removed; any test reading its topic is dead.
- Per-leg bounty model (old R4) — reversed by RD-4.
- `bountyMultiplier` / `rewardable` flag as separate return — collapsed into `mult` (`mult==0` = unrewarded sentinel) per the 330 USER deviation; `advanceGame` returns only `(uint8 mult)`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The live red count (640/59, 17 premise-retired) is stable through TST execution | Summary / Pitfall 1 | LOW — but if a commit lands between research and execution the count shifts; mitigated by the standing instruction to re-run `forge test` at the actual TST HEAD and gate on the 42-name union, not a bare count. |
| A2 | The Hardhat Degenerette stat tests are GREEN at the current HEAD (precedent-locked v48 parity) | Standard Stack / TST-05 | LOW — not re-run this session (Hardhat run is slow); CONTEXT locks "keep Hardhat green at its v48 last-known parity." Planner should run `npx hardhat test test/stat/Degenerette*.test.js` once during execution to confirm. |
| A3 | The de-crank rename has zero behavioral effect (pure `git mv` + symbol rename) | Runtime State Inventory | LOW — verified the only cross-file coupling is in-repo test symbols; the source-presence test greps a CONTRACT symbol (`degeneretteResolve(`), unchanged by file renames. |
| A4 | TST-05 RESULTS-equality is structurally clean because `_degeneretteResolveBet` delegatecalls the unchanged `resolveBets` | TST-05 / Pattern 3 | LOW — verified the delegatecall target is `GAME_DEGENERETTE_MODULE.resolveBets` (`:1741-1755`); only the wrapper + ≥3 gate changed. A "pre-rename baseline" for byte-comparison may need a git-checkout-of-old-source harness OR an assertion that the per-item math is value-invariant (the cleaner route given the frozen subject). |

## Open Questions

1. **How does TST-05 establish the "byte-identical vs the per-item path" baseline given the contract is frozen at the renamed source?**
   - What we know: the resolution RESULTS are produced by the unchanged `resolveBets` delegatecall; only the bounty wrapper + ≥3 gate changed.
   - What's unclear: whether to (a) check out the v48 `autoResolve` source into a mock for a side-by-side byte-diff, or (b) prove value-invariance directly (the payout/mint/RNG of a resolve is independent of the bounty wrapper).
   - Recommendation: route (b) — assert that resolving N bets via `degeneretteResolve` produces the SAME BURNIE/WWXRP/DGNRS/claimable/pool deltas + RNG draws regardless of whether the ≥3 reward fired, because the per-item resolution math never reads the bounty state. This is cleaner and avoids resurrecting deleted source. The CONTEXT's "vs the per-item logic" is satisfied by proving the per-item resolution is unchanged (the rename touched only names + the wrapper).

2. **Does TST-01's same-tx router perturbation need a stateful invariant handler, or do fuzz functions suffice?**
   - What we know: the CONTEXT delegates this ("Add a dedicated stateful invariant handler ... if the extension needs one").
   - What's unclear: whether firing `doWork`/`autoBuy` as a `_perturb` action inside the existing fuzz template is sufficient, or whether a same-tx bundling (advance-consume + buy/open in one tx) needs an invariant handler that drives the sequence.
   - Recommendation: start with extending the `_perturb` action library (lowest-friction, reuses the 6-phase template); add an invariant handler ONLY if the same-tx bundling can't be expressed as a single perturbation. The deep profile is the place to run any invariant extension.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `forge` (Foundry) | All TST proofs + the gate | ✓ | solc 0.8.34, via_ir | — |
| `FOUNDRY_PROFILE=deep` | TST-01 deep freeze proof | ✓ | runs=10000 / depth=256 (live-confirmed) | default profile (still valid for routine CI) |
| `hardhat` / `npx` | TST-05 Degenerette stat secondary gate | ✓ | `^2.28.3` | — (Foundry RESULTS-equality is the primary; Hardhat is the secondary) |
| MockVRFCoordinator | TST-01 freeze harness | ✓ | `contracts/mocks/MockVRFCoordinator.sol` (used by `VRFHandler`) | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None — deep profile gracefully degrades to default for routine runs.

## Validation Architecture

> `workflow.nyquist_validation` is not explicitly false in `.planning/config.json` → section included.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry `forge` (solc 0.8.34, via_ir, paris) + Hardhat `^2.28.3` (stat tree) |
| Config file | `foundry.toml` (default + `profile.deep`); `hardhat.config.js` + `package.json` scripts |
| Quick run command | `forge test --match-contract <NewProofContract>` |
| Full suite command | `forge test` (whole tree — the authoritative NON-WIDENING gate) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TST-01 | Freeze byte-identity under router same-tx perturbation | fuzz (default) + deep | `forge test --match-contract RngLockDeterminism` / `FOUNDRY_PROFILE=deep forge test --match-contract RngLockDeterminism` | ✅ extends `test/fuzz/RngLockDeterminism.t.sol` |
| TST-02 | Exactly one creditFlip/tx + structural reentrancy attest + default-batch + escapes | behavioral (call/log count) + grep attest | `forge test --match-contract <KeeperRouterOneCategory>` | ❌ Wave 0 (new file or extend a keeper-* file) |
| TST-03 | advance unrewarded-standalone/rewarded-via-doWork + GASOPT-01/03 same-results | behavioral-equality | `forge test --match-contract <RewardRoutingSameResults>` | ❌ Wave 0 |
| TST-04 | Whole-tree NON-WIDENING (42-name union); GASOPT-04 oracle | full suite + markdown ledger | `forge test` + author `test/REGRESSION-BASELINE-v49.md` | ✅ ledger template = `REGRESSION-BASELINE-v48.md`; reds enumerated above |
| TST-05 | flat ~1 BURNIE/≥3-gate/NoWork/WWXRP-excluded + RESULTS-equality | behavioral + RESULTS-equality + Hardhat stat | `forge test --match-contract <DegeneretteResolveRepeg>` + `npx hardhat test test/stat/Degenerette*.test.js` | ❌ Wave 0 (Foundry); ✅ Hardhat stat exists |

### Sampling Rate
- **Per task commit:** `forge test --match-contract <the-new-proof-contract>` (< 30s for a single contract at default fuzz).
- **Per wave merge:** `forge test` whole tree (the regression reconciliation).
- **Phase gate:** Full `forge test` green-minus-the-42-union + the Hardhat Degenerette stat green, ledger reconciled, before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] TST-01 router perturbation extension in `test/fuzz/RngLockDeterminism.t.sol` (add `_perturb` cls + bump `N_PERTURB_ACTIONS`; add the autoBuy-during-lock-SAFE / autoOpen-blocked-no-maroon / one-category-no-double-pay fuzz functions).
- [ ] TST-02 new proof file (creditFlip-count oracle + structural reentrancy grep-attest + default-batch/remainder + escapes).
- [ ] TST-03 new proof file (reward-routing + GASOPT-01/03 same-results).
- [ ] TST-05 new Foundry proof file (rename/re-peg/gate/WWXRP-exclusion/RESULTS-equality).
- [ ] DELETE the 17 enumerated premise-retired reds; re-author their v49 invariants fresh.
- [ ] `git mv` the 5 `Crank*` files → keeper-* + internal symbol renames.
- [ ] Author `test/REGRESSION-BASELINE-v49.md` (mirror v48 ledger).
- [ ] Framework install: none — `forge` + `hardhat` present.

## Security Domain

> `security_enforcement` is not explicitly `false` → section included. This is a no-mainnet-mutation test phase, so the security work is PROVING the existing structural invariants, not adding controls.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control (proven, not added) |
|---------------|---------|--------------------------------------|
| V2 Authentication | no | keeper is permissionless by design; no auth surface in scope |
| V3 Session Management | no | n/a (on-chain) |
| V4 Access Control | yes | `_degeneretteResolveBet` is `msg.sender != address(this)` self-call gated (`:1742`); `batchPurchase` AF_KING-gated; `keeperSnapshot` is a view. TST proves these are intact, no new control. |
| V5 Input Validation | yes | `degeneretteResolve` validates `len==0 || betIds.length != len → revert E()` (`:1600`); the AUTO-02 probe reverts `BatchAlreadyTaken()` (`:1604`). |
| V6 Cryptography | yes | VRF-freeze invariant (ADV-04) — TST-01 PROVES `totalFlipReversals` stays frozen request→consume. Never hand-roll RNG; the proof is the deliverable. |

### Known Threat Patterns for the v49 keeper surface
| Pattern | STRIDE | Standard Mitigation (proven at TST) |
|---------|--------|-------------------------------------|
| Bounty-stacking (earn >1 category/tx) | Elevation of Privilege (reward) | one-category structural early-return (TST-02 D-02 count==1) |
| Router→game→creditFlip reentrant double-pay | Tampering | structural: no untrusted call + single CEI-last creditFlip (TST-02 D-01 grep-attest, NO attacker harness) |
| Self-crank faucet drain | Repudiation / EV abuse | round-trip ≤0 under flat-per-tx + open knee pro-rate + self-exclude + ETH-work-gate (re-authored rows 4-7, GAS-05) |
| Mid-window state nudge (`totalFlipReversals`) | Tampering (RNG) | frozen advance-consume byte-identity (TST-01, ADV-04) |
| autoBuy/autoOpen bundled with advance-consume in one tx | Tampering (MEV) | autoBuy queues pre-entropy (rngLock-safe); autoOpen no-ops during lock; advance-consume reads frozen state (TST-01 same-tx) |
| Batch-brick via a poisoned item | Denial of Service | per-item try/catch isolation (degeneretteResolve) + autoOpen entry-gate non-reverting loop (re-authored rows 13-15) |

> **STOP rule (from CONTEXT):** if any TST proof surfaces a CONTRACT defect, STOP and surface it — do NOT patch a mainnet `contracts/*.sol` under a TST phase. The subject is frozen.

## Project Constraints (from global CLAUDE.md + MEMORY feedback)
- **Read contracts ONLY from `contracts/`** (stale copies exist elsewhere — `feedback_contract_locations`). All `file:line` in this doc are from `contracts/`.
- **Security/RNG-non-manipulability is a HARD FLOOR over gas** (`feedback_security_over_gas`) — TST-01 (freeze) and TST-02 (no-stacking/no-double-pay) are the load-bearing security proofs; never weaken them.
- **Tests are agent-committable** (`feedback_no_contract_commits` / `feedback_contract_commit_guard_hook`): `test/` + `.planning/` are free to commit autonomously. NO `contracts/*.sol` (mainnet) edit in this phase. `.planning/` is gitignored — force-add planning docs.
- **GSD commands use the HYPHEN form** (`/gsd-execute-phase`, not `/gsd:execute-phase`) — `feedback_slash_command_hyphen_form`.
- **De-crank matches the v48 contract rename** (user dislikes "crank") — D-07 completes it into `test/`.

## Sources

### Primary (HIGH confidence)
- `contracts/AfKing.sol` (`doWork:883-919`, `BUY_BATCH:850`, `OPEN_BATCH:856`, escapes `:923/:929`, `_autoBuy:561`, `keeperSnapshot` IGame row `:42`) — re-grepped this session.
- `contracts/DegenerusGame.sol` (`advanceGame` wrapper `:278-288`, `degeneretteResolve:1595-1631`, `RESOLVE_FLAT_BURNIE:1544`, `advanceDue:1637`, `boxesPending:1655`, `autoOpen:1687`, `keeperSnapshot:2628`, `_degeneretteResolveBet:1741`, `OPEN_NORMAL_GAS_UNIT:1561`).
- `contracts/modules/DegenerusGameAdvanceModule.sol` (`advanceGame:154`, mid-day `mult=1` `:217`, ladder `:235-241`, gameover `mult=0` `:187`, frozen consume `cw += totalFlipReversals` `:254-259`).
- `contracts/modules/DegenerusGameMintModule.sol` (GASOPT-01 `owedMap` hoist `:399` + `:673`).
- `test/fuzz/RngLockDeterminism.t.sol` (the 6-phase template + `_perturb` lib + `StakedStonkRedemption:1263`).
- `test/gas/CrankLeversAndPacking.t.sol:127-210` (the 2 canonical retired-premise reds + `_countCoinflipStakeUpdatedFor`).
- `test/fuzz/AfKingConcurrency.t.sol:69-228` (the migrated `lastAutoBoughtDay`/`_countAutoBoughtFor` oracle + SAFE-03 cases).
- `test/fuzz/CrankNonBrick.t.sol:360` (the RD-2 dropped-guard red).
- `test/REGRESSION-BASELINE-v48.md` (the 42-red union + the ledger template).
- `foundry.toml` (default + `profile.deep`; `fs_permissions`).
- `package.json` (Hardhat scripts; `test:stat`).
- Live `forge test --json` run this session → **640 passed / 59 failed**; 42/42 v48 reds present; 17 premise-retired enumerated.
- `git log -L` per failing test → provenance (`3afbf676` / `47b9d031` / `b9bc5206` / `dfba3ac1` / `795e679d`, all v46.0 318/319).

### Secondary (MEDIUM confidence)
- `.planning/phases/330-.../330-08-SUMMARY.md` + `330-VERIFICATION.md` — the "+16" deferral record (corrected to 17 here against the live HEAD).
- `.planning/phases/329-.../329-CONTEXT.md` — D-01/D-01a/D-01b reentrancy disposition; RD-1..RD-5; D-07.
- `.planning/REQUIREMENTS.md` + `.planning/ROADMAP.md` — TST-01..05 wording + the Phase 332 SCs.

### Tertiary (LOW confidence)
- Hardhat Degenerette stat green-state — assumed from CONTEXT precedent-lock, not re-run this session (A2).

## Metadata

**Confidence breakdown:**
- Test framework / stack: HIGH — verified against `foundry.toml` + `package.json` + a live `forge config`/`forge test` run.
- Red-set enumeration (the 17): HIGH — derived from a live `forge test --json` cross-referenced against the 42-name v48 union; provenance traced per-test via `git log -L`.
- Source `file:line` anchors: HIGH — re-grepped against the committed source this session.
- Proof-construction patterns: HIGH for the harness mechanics (read directly); MEDIUM for the exact TST-05 baseline route (Open Question 1) and TST-01 invariant-handler-vs-fuzz decision (Open Question 2).
- Hardhat stat green-state: MEDIUM (A2) — precedent-locked, not re-run.

**Research date:** 2026-05-27
**Valid until:** the next commit that touches `test/` or `contracts/` — re-run `forge test` and re-confirm the 640/59 + 17-red split at the actual TST-execution HEAD (Pitfall 1). For a stable HEAD, ~14 days.
