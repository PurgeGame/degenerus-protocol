# Phase 410: FOUNDATION — Subject Freeze & Green Baseline

**Completed:** 2026-06-16
**Status:** PASSED — FOUND-01 + FOUND-02 satisfied.

## FOUND-01 — Frozen Subject Anchor

| Anchor | Value |
|--------|-------|
| Audit subject (contract commit) | `42c8e9c6` |
| `contracts/` tree hash (canonical freeze anchor) | `0dd445a64cfe7e096427d44f058c40abb1233b5f` |
| Relation to origin | `= origin/main bb0912a6` (v65 archive) `+ the additive CurseChanged indexer-parity emit` (committed pre-freeze; UNPUSHED) |
| Optimizer / EVM | `optimizer_runs = 1000`, via_ir (per v65) |

**Freeze rule:** the subject is the `contracts/` **tree** `0dd445a6…`, not a commit hash. Documentation
and test commits land on top during the milestone; freeze is verified by
`git rev-parse HEAD:contracts == 0dd445a64cfe7e096427d44f058c40abb1233b5f`, which must hold through close.
A non-empty `git diff 42c8e9c6 -- contracts/` at any later phase (other than an approved, gated fix) is a
freeze breach.

**The one pre-freeze contract change (CurseChanged emit):** USER-approved additive indexer-parity event
`CurseChanged(address indexed player, uint8 newCurseCount)` emitted from `_applyCurseStack` / `_clearCurse`
in `DegenerusGameMintStreakUtils` (commit `42c8e9c6`). Proven inert: packed-word bytes byte-identical,
emit-order tests pass, 42/42 curse suite green, EIP-170 OK (MintModule margin 1,377; Game margin 4,149
unchanged). Folded in BEFORE the freeze so the audit covers real shipping bytecode.

## FOUND-02 — Green Baseline Oracle

The regression floor every later v66 lead is reproduced against.

### Forge (primary net) — `forge test`

| Metric | Count |
|--------|-------|
| Passed | **889** |
| Failed | **0** |
| Skipped | **110** |
| Total | 999 (125 suites) |

**Identical to the v65 closure baseline (889/0/110)** → the CurseChanged emit introduced **zero** forge
regressions and **zero** new skips. Forge is fully green and is the authoritative regression net.

The 110 skips are carried `vm.skip` tests (unchanged count vs v65). Known among them: the mid-day cross-day
lootbox binding test (`RngIndexDrainBinding.t.sol::testBindingConsistencyMidDayCrossDay`), which **MECH-02**
(Phase 414) rewrites — its disabled state is a tracked v66 work item, not a baseline defect.

### Hardhat (parity net) — `npm test`

| Metric | Count |
|--------|-------|
| Passing | **1232** |
| Failing | **136** (all carried pre-existing) |
| Pending | 14 |

**The 136 failures are the known carried JS-test floor** (matches the documented pre-existing count). They are
test-model issues — NOT contract-logic defects — and **none are curse/smite/decurse/CurseChanged-related**, so
the emit added zero new hardhat reds. Carried groups (representative):

- Stale gas-pins to old HEADs: `Phase 264 SURF-05 … gas regression at v35.0 HEAD`, `v36.0 AdvanceGame Gas Envelope (Phase 266)`, Phase 282/288/293 gas/determinism fixtures.
- Known fixture reds: `DGNRS (DGNRS Liquid Token)` / `DGNRS` (pool-BPS + deployWithGameOver), `DegenerusVault`, `Coinflip`, `DegenerusAffiliate`/`AffiliateHardening`, `SecurityEconHardening`, `RngStall`, `BafCreditRouting`, `GameOver`, `Distress-Mode Lootboxes`, `WhaleBundle`, `CharityGameHooks`, `VRFIntegration`, `MintBatchDeterminism`, `HeroOverride*`, `LootboxAutoResolveRegression`, `LivenessMidJackpot`, `LastPurchaseDayRace`.

### Regression-detection rule for v66

A later phase's test run is a **regression** iff: (a) forge passes < 889 OR forge fails > 0 OR forge skips > 110
with a non-`vm.skip` cause, OR (b) a hardhat failure appears whose title is NOT in the carried set above
(i.e. failing count > 136 OR a new/curse/event/gas title). Otherwise the run is at parity with this baseline.

## Verification

- [x] **FOUND-01** — subject byte-frozen; commit `42c8e9c6` + tree `0dd445a6…` recorded; `git diff 42c8e9c6 -- contracts/` empty.
- [x] **FOUND-02** — green baseline captured (forge 889/0/110 + hardhat 1232/136/14); pre-existing reds catalogued as carried-not-new; emit proven inert across both nets.
