# Phase 351 — Deferred Items (out of scope for the current plan, in scope for the phase)

> Logged by plan 351-01 (Wave 0 — fixture-repair / blocking-first). These are the AfKing/keeper
> corpus test files that still reference the dissolved standalone `AfKing` (the deleted
> `contracts/AfKing.sol`, the removed `ContractAddresses.AF_KING` constant, or the removed
> `afKing` fixture state var). Their **full property adaptation** to the game-resident
> `GameAfkingModule` path is the explicit charge of the DOWNSTREAM 351 plans per `351-PATTERNS.md`
> §2–§13 (the call-site rewrites: `afKing.subscribe`→`game.subscribe`, `doWork`→`mintBurnie`,
> cold-ledger→warm-stamp, slot re-derivation via `forge inspect storage DegenerusGame`, the
> differential box oracle, etc.). Plan 351-01's `files_modified` frontmatter is ONLY
> `test/fuzz/helpers/DeployProtocol.sol` + `scripts/lib/predictAddresses.js` (+ the in-idiom
> deploy canary `test/fuzz/DeployCanary.t.sol` for the Task-3 alignment guard). Rewriting these 13
> files here would steal downstream scope and risk colliding with later waves — so they are NOT
> touched by 351-01.

## Still-broken corpus (13 files) — DOWNSTREAM 351 plans own the adaptation

These fail full-tree `forge build` because each references the dissolved standalone AfKing. They
are NOT broken by plan 351-01's fixture edit — they were broken the moment `contracts/AfKing.sol`
was deleted at 349.1 (pre-existing). Each maps to a `351-PATTERNS.md` analog section.

| # | File | Break signature(s) | PATTERNS § (downstream owner) |
|---|------|--------------------|-------------------------------|
| 1 | `test/fuzz/AfKingSubscription.t.sol` | `import {IGame} from ".../AfKing.sol"`; 29 `afKing.`; `IGame` type | §2 (set-mutation/event) |
| 2 | `test/fuzz/AfKingConcurrency.t.sol` | 68 `afKing.`; `address(afKing)` slot pokes | §3 (TST-04 set-mutation/swap-pop) |
| 3 | `test/fuzz/AfKingFundingWaterfall.t.sol` | 39 `afKing.` | §4 (TST-02 revert-free funding) |
| 4 | `test/fuzz/KeeperRewardRoutingSameResults.t.sol` | `afKing.`; `address(afKing)` | §5 (D-351-05 differential template) |
| 5 | `test/fuzz/KeeperNonBrick.t.sol` | `afKing.`; `address(afKing)` | §6 (TST-02 revert-free template) |
| 6 | `test/fuzz/RngLockDeterminism.t.sol` | 4 `afKing.` + 4 `doWork` | §7 (TST-01 freeze template) |
| 7 | `test/fuzz/KeeperFaucetResistance.t.sol` | `afKing.`; `doWork` | §8 (bounty) |
| 8 | `test/fuzz/KeeperRouterOneCategory.t.sol` | 22 `afKing.`; `ContractAddresses.AF_KING`; `vm.readFile(AfKing.sol)` | §8 (one-category) |
| 9 | `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` | `ContractAddresses.AF_KING` (subject = removed `batchPurchase`) | §9 (D-351-02 candidate) |
| 10 | `test/fuzz/RedemptionStethFallback.t.sol` | `import {AfKing} from ".../AfKing.sol"`; `AfKing(payable(...)).depositFor/poolOf/withdraw` | §10 (D-351-02 candidate — custody-recovery leg) |
| 11 | `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | (human box path → reframe; not currently a hard import break, adapts in §11) | §11 (TST-06 per-open) — *not in the 13 hard-break set; reframe* |
| 12 | `test/gas/RouterWorstCaseGas.t.sol` | 21 `afKing.`; `doWork` | §12 (TST-06 16.7M ceiling) |
| 13 | `test/gas/KeeperLeversAndPacking.t.sol` | `ContractAddresses.AF_KING`; `vm.readFile(AfKing.sol)` | §13 (source-grep/packing) |
| 14 | `test/gas/SweepPerPlayerWorstCaseGas.t.sol` | 15 `afKing.`; `address(afKing)` | §13 (per-player sweep) |

(The 13 hard-break set proven by `grep -rln 'import.*AfKing\.sol\|address(afKing)\|afKing\.\|ContractAddresses\.AF_KING' test/`:
AfKingConcurrency, AfKingFundingWaterfall, AfKingSubscription, KeeperBatchAffiliateDeltaAudit,
KeeperFaucetResistance, KeeperNonBrick, KeeperRewardRoutingSameResults, KeeperRouterOneCategory,
RedemptionStethFallback, RngLockDeterminism, KeeperLeversAndPacking, RouterWorstCaseGas,
SweepPerPlayerWorstCaseGas. `KeeperOpenBoxWorstCaseGas` is a soft reframe per §11, not a hard import break.)

## Why these are NOT auto-fixed in plan 351-01

- **Scope boundary** (executor deviation rules): "Only auto-fix issues DIRECTLY caused by the
  current task's changes." These breaks are pre-existing (the 349.1 `AfKing.sol` deletion), not
  caused by the fixture/predictAddresses edits.
- **Downstream ownership:** `351-PATTERNS.md` assigns each file to a specific analog section with
  exact call-site rewrites + slot re-derivation. Doing that work in the Wave-0 plan would conflict
  with the per-file downstream plans.
- **Wave-0 contract is met:** the SHARED fixture (`DeployProtocol.sol`) + the deploy-order script
  (`predictAddresses.js`) are repaired, and the deploy-alignment canary (`DeployCanary.t.sol`)
  compiles + PASSES — proving the cascade *through the fixture* is cleared. Each downstream plan
  now adapts its own file against the game-resident model and compiles incrementally.

## Verification note for downstream plans

`forge build` / `forge test` require the manual patch first (no pretest hook):
`node scripts/lib/patchForFoundry.js` before `forge build`, then restore via
`restoreContractAddresses()` + `cleanupBackup()` to keep `contracts/ContractAddresses.sol` frozen
(the `.bak` round-trip keeps `git diff 453f8073 HEAD -- contracts/` EMPTY).
