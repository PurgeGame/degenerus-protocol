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
