# Phase 323 — Deferred Items (out-of-scope, pre-existing v46)

Discovered while running the hardhat suite for 323-02. These are PRE-EXISTING v46-baseline
test-vs-contract mismatches (verified by running the same file at the v46 closure HEAD
`16e9668a` in a throwaway worktree). They are NOT v47-deltas and are out of 323-02's
non-widening repair scope. Logged, not fixed.

## test/unit/DegenerusVault.test.js — 2 pre-existing failures

- `gameSetAutoRebuy reverts when caller is not vault owner` — `vault.gameSetAutoRebuy is not a function`
- `gameSetAutoRebuyTakeProfit accessible by vault owner` — `vault.gameSetAutoRebuyTakeProfit is not a function`

Both functions exist in NEITHER the v46 nor the v47 `DegenerusVault.sol` (the legacy
ETH-auto-rebuy surface was removed in v46.0's "Legacy AFKing/ETH-Auto-Rebuy Removal"),
but the test still references them. Confirmed FAILING at v46 closure HEAD (47 pass / 2 fail
there; the same 2 failures). Non-widening at v47. A future test-hygiene pass should remove
or retarget these 2 `it()` blocks; out of scope for the v47-delta repair.

## test/gas/Phase268GasRegression.test.js — 1 pre-existing failure

- `v37.0 SURF-06 — advanceGame STAGE_PURCHASE_DAILY gas within ±2K of v36.0 baseline`:
  measured ~693_858 gas vs the stale pinned `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320`
  (a v36.0 baseline). Drift ~214K.

Confirmed FAILING at v46 closure HEAD with a near-identical measurement (693_459 vs the same
908_320 REF, drift 214_861). The v47 vs v46 measurement differs by ~400 gas (codegen noise),
so this is NOT a v47 regression — it is a stale gas-baseline pin that was already drifting at
v46, on the `advanceGame` stage-6 path (NOT the Degenerette spin-cap path 323-02 edited). A
future gas-hygiene pass should re-pin or retire the v36.0 baseline; out of scope here.

(The file's 1 `pending` is the SURF-06 worst-case Degenerette spin test soft-skipping because
`WORST_CASE_RNG_WORDS` is unpinned and the inline brute-force budget is exhausted — the
documented REF-CAPTURE soft-skip, expected, not a failure.)

## Shared-fixture note (FIXED in 323-02, recorded for traceability)

`test/helpers/deployFixture.js` `getConstructorArgs` returned `[]` for the `AF_KING` key
even though `AfKing` has a 3-arg constructor (inserted into DEPLOY_ORDER at Phase 318,
v46). This bricked EVERY fixture-based hardhat test (deploy threw "incorrect number of
arguments to constructor") at BOTH v46 and v47 — a pre-existing v46 break. Because it blocks
the entire in-scope hardhat suite from running, 323-02 applied the one-line fix (supply the
same 3 args the foundry helper `test/fuzz/helpers/DeployProtocol.sol:126` uses). This is a
test-helper-only repair; no contract change.

## 323-04 OWNERSHIP RE-CLASSIFICATION — 7 failures 323-01 tagged "DGAS/DSPIN (323-04)"

323-01's failure table speculatively assigned 7 new-vs-v46 failures to "DGAS/DSPIN (323-04)".
On inspection during 323-04, the root cause of these is the v47 **rake-removal / presale-box
prize-pool economics** (and one is **redemption**), NOT the Degenerette `resolveBets`
write-batching (R5). They are OUTSIDE 323-04's `files_modified`
(`DegeneretteFreezeResolution.t.sol` + `CrankResolveBetWorstCaseGas.t.sol`) and outside R5's
domain. Per the SCOPE BOUNDARY rule (only auto-fix issues directly caused by the current
task's changes), 323-04 does NOT touch them. Grep-verified re-classification:

| Failure | Degenerette refs | Real root cause | Re-assigned owner |
|---------|------------------|-----------------|-------------------|
| `EthSolvency.inv.t.sol` (solvency inv) | **0** | rake-removal/presale prize-pool obligations vs balance (driver = `GameHandler.advanceGame` + purchase) | PRESALE economics re-verify |
| `MultiLevel.inv.t.sol` (solvency inv) | **0** | same (rake/presale economic drift) | PRESALE economics re-verify |
| `VaultShareMath.inv.t.sol` (solvency inv) | **0** | same | PRESALE economics re-verify |
| `WhaleSybil.inv.t.sol` (solvency inv) | **0** | same | PRESALE economics re-verify |
| `DegeneretteBet.inv.t.sol::invariant_solvencyUnderDegenerette` | targets Degenerette, but fail driver is `GameHandler::advanceGame` (rake economics under Degenerette pressure) — `balance < obligations` after advanceGame, NOT a payout-batching divergence | rake/presale prize-pool economics | PRESALE economics re-verify |
| `RngLockDeterminism.t.sol::testFuzz_RngLockDeterminism_StakedStonkRedemption` | **0** | sDGNRS-redemption interaction narrows the `vm.assume` window (the `sdgnrs.burn` path) | **REDEEM-08 / 323-03** |
| `VRFLifecycle.t.sol::test_vrfLifecycle_levelAdvancement` | **0** (7 presale/prizePool refs) | "Game should advance past level 0" — presale lootbox-split prize-pool accumulation (rake economics) | PRESALE economics re-verify |

Evidence: `grep -c "Degenerette\|resolveBets\|placeDegenerette"` returns 0 for all six non-
DegeneretteBet files; `VRFLifecycle` returns 7 presale/prizePool/bootstrap refs. The DGAS-05
same-results proof (323-04) is byte-identical, so the Degenerette write-batching itself does
NOT change any payout — these solvency/economic failures cannot stem from it. They require
re-deriving the v47 rake-free / presale-box prize-pool model (PRESALE family) or the redemption
assume window (323-03), neither of which is 323-04's charter. None is a contract defect (322's
diff behaves as the v47 SPEC intends). Logged here for the Phase 324 TERMINAL economic
re-verification sweep + the PRESALE/REDEEM owners to pick up.

### 323-09 CORRECTION — the 5 solvency invariants were STALE-HARNESS, not rake economics

323-04's row above re-assigned the 5 solvency-invariant failures to "PRESALE rake economics".
On inspection during 323-09 that diagnosis was WRONG: the real root cause is the stale obligation
set documented in `323-SOLVENCY-FINDING.md` §3 (the `obligations` sum omitted the freeze-window
pending buffer `prizePoolPendingPacked` @slot 11 — the very set `distributeYieldSurplus` itself
counts — and double-counted the dead post-game-over `futurePrizePool`). 323-09 re-greened ALL FIVE
(`EthSolvency` / `MultiLevel` / `WhaleSybil` / `VaultShareMath` / `DegeneretteBet`) with a PRINCIPLED
obligation-formula correction (`SolvencyObligations` helper), 256 runs each, zero contract edits —
NO rake/presale re-derivation was needed. The shrunk EthSolvency counterexample was a freeze-window
state (`advanceGame`+`fulfillVrf`), confirming the pending-buffer omission, not presale economics.
These five are now GREEN and OFF the residual list.

## 323-09 DISPOSITION — the "0x11 ticket-queue + pending-pool cluster" is PRE-EXISTING v46

323's Task-3 charter assumed the `0x11` panics in the ticket-queue routing suites were "stale
hardcoded `vm.store`/`vm.load` storage slots shifted by the v47 `pendingRedemptionBurnie` deletion
+ presale-var additions". On inspection (323-09) that premise is FACTUALLY WRONG, proven three ways:

1. **These files have NO hardcoded slot constants.** `TicketRouting.t.sol`, `QueueDoubleBuffer.t.sol`,
   `TicketEdgeCases.t.sol` all use a `DegenerusGameStorage`-INHERITING harness that calls the internal
   queue functions directly (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) — there is no
   `vm.store`/`vm.load` to be slot-shifted. `PrizePoolFreeze.t.sol` likewise uses `exposed_*` harness
   wrappers, no raw slots.

2. **The `0x11` root cause is a harness-time `block.timestamp` underflow, not a slot.** `_queueTickets`
   (and the scaled/range variants) calls `if (_livenessTriggered()) revert E();` →
   `_simulatedDayIndex()` → `GameTimeLib.currentDayIndexAt(block.timestamp)` =
   `(ts - JACKPOT_RESET_TIME=82620) / 1 days`. These standalone harness `setUp()`s never `vm.warp`,
   so `block.timestamp` is the foundry default (1) → `1 - 82620` underflows → panic `0x11`. (The full
   `DeployProtocol` invariant suites warp `+1 days` in setUp and a real deploy sets timestamps, which
   is why they don't hit this.)

3. **Byte-identical at the v46 closure HEAD (`16e9668a`), confirmed in a worktree.** Every panic
   reproduces with the SAME gas at v46:

   | Suite::test | HEAD | v46 (`16e9668a` worktree) | Gas (both) |
   |-------------|------|---------------------------|------------|
   | `TicketRouting` (12 tests) | 0x11 | 0x11 | e.g. `testFarFutureRoutesToFFKey` 11865 |
   | `QueueDoubleBuffer` (9 tests) | 0x11 | 0x11 | identical |
   | `TicketEdgeCases::testEdge01/02` | 0x11 | 0x11 | 9925 / 13786 |
   | `PrizePoolFreeze::testFreezeUnfreezeRoundTrip` | `88 != 0` | `88 != 0` | 81194 |
   | `PrizePoolFreeze::testMultiDayAccumulatorPersistence` | `400 != 200` | `400 != 200` | 84968 |
   | `RngIndexDrainBinding::testBindingConsistencyDailyDrain` | `AC-3 0<=0` | `AC-3 0<=0` | ~9.1M |

   The contract path is unchanged too: `_queueTickets`'s `_livenessTriggered()` call, the
   `_livenessTriggered`/`_simulatedDayIndex` bodies, `GameTimeLib` (LINES=0 diff), and
   `DEPLOY_DAY_BOUNDARY=0` are ALL byte-identical v46↔HEAD. The two `PrizePoolFreeze` assertion
   failures are a separate pre-existing test-vs-contract mismatch: `_swapAndFreeze` PRE-SEEDS 1% of
   `futurePool` into pending (`futureBal/100`; 8888/100=88, 20000/100=200), which is also byte-identical
   at v46 — the tests assert "freeze zeros pending" and don't account for the pre-seed.

The relevant test files (`TicketRouting`, `QueueDoubleBuffer`, `TicketEdgeCases`, `PrizePoolFreeze`)
are themselves byte-identical v46↔HEAD (`git diff 16e9668a HEAD` LINES=0 for each), so the v47 diff
could not have introduced these.

**Disposition: NOT a v47 slot-shift; PRE-EXISTING v46; DEFERRED (not fixed).** Per the hard
constraint "do NOT touch [pre-existing v46]" + the non-widening rule (every change attributable to a
v47 storage-layout delta), 323-09 does NOT repair these — fixing pre-existing-v46 harness bugs inside
a v47-delta phase would widen scope and is exactly what this file defers. The fixes are trivial for a
future test-hygiene pass: (a) add `vm.warp(block.timestamp + 366 days)` … actually a SMALL forward
warp to any `ts >= 82620 + 1 days` in the four harness `setUp()`s clears the `0x11` (and then assert
`!_livenessTriggered()` by keeping `currentDay - psd <= 365` — note psd defaults to 0 in the bare
harness, so a warp just past `JACKPOT_RESET_TIME` but under 365 days is the safe window); (b) update
`PrizePoolFreeze`'s two pending-pool assertions to add the documented 1% `_swapAndFreeze` pre-seed.
None masks any v47 behavior. Logged for the Phase 324 TERMINAL hygiene pass alongside the v46 items
above.
