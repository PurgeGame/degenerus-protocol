# Phase 323: TST — Repro-First + Same-Results Gas + Behavior/EV + Cancel-Tombstone Proofs — Context

**Gathered:** 2026-05-25
**Status:** Ready for planning
**Source:** ROADMAP Phase 323 success criteria + the committed Phase 322 IMPL (`fb29ed51`) + its 322 SUMMARYs.

<domain>
## Phase Boundary

Prove the v47.0 contract diff (frozen at audit subject `fb29ed51`) empirically, and restore a
CLEAN v47.0 regression baseline. Two halves:

1. **Repair** every `test/` file the v47 contract changes broke (the suite currently does not
   compile → `forge test` can't run). Test code only — the contract subject is FROZEN (do NOT
   edit `contracts/` to make a test pass; if a test reveals a real contract defect, STOP and
   surface it, do not paper over it).
2. **Prove** the new behavior: REDEEM-08 (repro-first), DGAS-05 / DSPIN-02 (same-results gas),
   TOMB-04 / TOMB-05 (cancel-tombstone), + coverage for the 4 USER-directed refinements.

Test work is AGENT-committable (no approval gate; `test/` + `contracts/test/` are free to commit
per project policy). NO `contracts/*.sol` edits in this phase.
</domain>

<decisions>
## What changed in the subject (drives both repair + proofs) — from 322 SUMMARYs / 321-SPEC

- **REDEEM:** `resolveRedemptionLootbox` is now `external payable` (unchecked SDGNRS debit DELETED,
  `futurePrizePool` credited from `msg.value`); new CHECKED `pullRedemptionReserve`; BURNIE settled
  at submit via `redeemBurnieShare` → `burnForCoinflip` (net new BURNIE == 0); the BURNIE reserve
  apparatus (`pendingRedemptionBurnie`, `burnieOwed`, `RedemptionPeriod.flipDay`, day+1 lookup,
  `_payBurnie`) is DELETED; `resolveRedemptionPeriod` is now **2-arg** `(uint16 roll, uint32 dayToResolve)`
  (the `flipDay` param removed); `claimRedemption` is ETH-only.
- **LOOT:** the BURNIE-lootbox surface is GONE (`openBurnieLootBox`, `purchaseBurnieLootbox`,
  `_purchaseBurnieLootboxFor`, `gamePurchaseBurnieLootbox`, the `purchaseCoin` lootbox branch,
  `BurnieLootOpen`); `_resolveLootboxCommon` is 2-bool; BURNIE→tickets KEPT.
- **DGAS/DSPIN:** Degenerette `resolveBets` write-batched (same payouts); `MAX_SPINS_PER_BET`
  retired → per-currency caps `MAX_SPINS_ETH=25 / MAX_SPINS_BURNIE=15 / MAX_SPINS_WWXRP=5`.
- **PRESALE:** rake removed; `Pool.Earlybird`→`PresaleBox`; `_awardEarlybirdDgnrs`/`_finalizeEarlybird`/
  `EARLYBIRD_*` removed; new `buyPresaleBox`/`buyLootboxAndPresaleBox` + box resolution.
- **CPAY:** the strict-1-wei-sentinel + paired claimable/pool debit is now `_settleClaimableShortfall`.
- **TOMB:** AfKing `setDailyQuantity(0)` is an in-place tombstone; sweep has a top-of-loop reclaim
  branch + the `didWork` revert-fix (a reclaim/auto-pause/renewal-only chunk COMMITS instead of
  reverting → no tombstone-stranding griefing).

### Claude's Discretion
- Test decomposition, fixture/helper choices, exact assertion style — match existing patterns in
  the analog test files.
</decisions>

<canonical_refs>
## Canonical References (read before planning/implementing)
- `.planning/ROADMAP.md` — Phase 323 goal + the 5 success criteria (DGAS-05, DSPIN-02, REDEEM-08, TOMB-04, TOMB-05).
- `.planning/phases/322-.../322-08-SUMMARY.md` — the wave-8 verification + the 4 refinements (R1–R4) and their NEW test obligations.
- `.planning/phases/322-.../322-04-SUMMARY.md` (REDEEM), `322-05-SUMMARY.md` (DGAS+DSPIN), `322-07-SUMMARY.md` (TOMB) — the exact behavior to prove.
- `.planning/phases/321-.../321-SPEC.md` — R1–R7 / C1–C9 (the locked design the tests verify).
- Contract subject: git `fb29ed51` (frozen). Read the live `contracts/` for current signatures.
</canonical_refs>

<scope_fence>
## Hard Constraints
1. **NO `contracts/*.sol` edits.** The subject is frozen at `fb29ed51`. A failing test that reveals
   a real contract defect is a STOP-and-surface event, never a silent contract patch.
2. **Repro-first (REDEEM-08):** write the defect repro FIRST and demonstrate it fails against the
   PRE-fix contract (e.g. against `fb29ed51^` / by temporarily reverting only the specific fix in a
   scratch checkout), then passes post-fix. Record the pre-fix failure evidence.
3. **Same-results (DGAS-05/DSPIN-02) is the floor:** prove the Degenerette write-batching is
   payout-IDENTICAL to per-spin (Tier-1 additive; Tier-2 cap binds on the identical spin), and the
   25-spin ETH worst case is absorbed — derive the worst case FIRST, then measure.
4. **Both frameworks:** Foundry (`forge test`, `*.t.sol`) AND Hardhat (`*.test.js`). Repair both.
5. **Baseline:** v46 closure was ~565 pass / ~44-45 fail. Restore a clean v47 baseline — repairs must
   be NON-WIDENING (every change attributable to a v47 contract delta); report the final pass/fail.
</scope_fence>

<specifics>
## Repair inventory (the suite does not compile — solc caps errors, so iterate build→fix→build)
Test files referencing removed/changed v47 symbols (~20, both frameworks):
`test/fuzz/RedemptionEdgeCases.t.sol`, `test/fuzz/RedemptionGas.t.sol`, `test/fuzz/RngLockDeterminism.t.sol`,
`test/fuzz/StakedStonkRedemption.t.sol`, `test/fuzz/CoverageGap222.t.sol`, `test/fuzz/LockRemoval.t.sol`,
`test/fuzz/handlers/RedemptionHandler.sol`, `test/invariant/RedemptionAccounting.t.sol`,
`test/gas/CrankResolveBetWorstCaseGas.t.sol`, `contracts/test/LootboxBernoulliTester.sol`,
+ Hardhat: `test/gas/LootboxOpenGas.test.js`, `test/gas/Phase268GasRegression.test.js`,
`test/integration/CrossSurfaceTicketMixing.test.js`, `test/stat/DegenerettePerNEvExactness.test.js`,
`test/unit/DegenerusStonk.test.js`, `test/unit/DegenerusVault.test.js`, `test/unit/EventSurfaceUnification.test.js`,
`test/unit/LootboxAutoResolveSilentColdBust.test.js`, `test/unit/LootboxConsolation.test.js`, `test/unit/LootboxWholeTicket.test.js`.
(Confirm by `forge build` / hardhat compile; fix iteratively until clean.)

## Proof-test homes (extend existing analogs where possible)
- REDEEM-08 → `test/fuzz/StakedStonkRedemption.t.sol` / `test/invariant/RedemptionAccounting.t.sol` / `RedemptionEdgeCases.t.sol`.
- DGAS-05/DSPIN-02 → `test/gas/CrankResolveBetWorstCaseGas.t.sol` + a same-results behavior test (`DegeneretteFreezeResolution.t.sol` analog).
- TOMB-04/05 → `test/...AfKing*.t.sol` (`CrankNonBrick.t.sol`, `AfKingConcurrency.t.sol`); TOMB-05 = the `testGas04` stale-test repair (post-OPENE-01 `Sub` shape).
- Refinement coverage: `_settleClaimableShortfall` invariant across the 5 callers; `resolveRedemptionPeriod` 2-arg path; `burnForCoinflip` redemption-burn; the `didWork` reclaim/renewal-only-chunk-commits case.
</specifics>

<deferred>
## Deferred → Phase 324 (TERMINAL)
Delta-audit vs v46 baseline, the 3-skill adversarial sweep, the findings deliverable, and the
`MILESTONE_V47_AT_HEAD_<sha>` closure flip. Secure-phase re-verification of the presale-box RNG
freeze (R4) is a Phase 324 sweep concern (this phase may add a freeze-invariant test if convenient).
</deferred>

---
*Phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs*
*Context: 2026-05-25; subject frozen at fb29ed51*
