---
phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
plan: 03
subsystem: testing
tags: [gas, seed1, seed2, keeper-batch, affiliate, batchPurchase, no-brick, delta-audit, foundry, security-floor]

# Dependency graph
requires:
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "331-01 router-marginal harness + the 331-PATTERNS Seed 1/Seed 2 SSTORE-count table this design confirms against source"
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the committed 63bc16ca batchPurchase / _batchPurchaseUnit / _purchaseFor / payAffiliate keeper-buy surface this plan designs the Seed 1+2 diff against"
provides:
  - "331-SEEDS-DESIGN.md — the Seed 1 (shared-slot DGNRS affiliate aggregation) + Seed 2 (pre-validated keeper batch path) contract blueprint: every _batchPurchaseUnit -> _purchaseFor -> MintModule.purchase revert source (R1-R10) dispositioned, the coalescible/non-coalescible SSTORE table confirmed, and the chosen path shape (new batchPurchaseForKeeper + internal _keeperBuyUnit) justified"
  - "test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol — the money-path delta-audit baseline (current path) + the _drive(useKeeperPath) / KEEPER_PATH_LANDED-gated byte-identical path-equivalence proof for 331-05"
  - "test/fuzz/CrankNonBrick.t.sol Seed 2 extension — the keeper-batch poisoned-player no-brick proof (the feedback_security_over_gas HARD CONSTRAINT), parameterized for the gated 331-05 path"
affects: [331-05-contract-gate, 332-TST, 333-TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "money-path delta-audit: snapshot every accumulator (coalescible via public getters affiliateScore/totalAffiliateScore/coinflipAmount; the SOLE non-coalescible affiliateCommissionFromSender via vm.load of slot 5) + assert aggregate==sum-of-successful + poisoned==zero+refunded"
    - "_drive(useKeeperPath) toggle + a KEEPER_PATH_LANDED bool gate so a single harness baselines the current path now and re-runs byte-identical against the not-yet-landed function once the gated diff flips the flag"
    - "vm.snapshotState/revertToState two-run equivalence (Run A current path, revert, Run B proposed path, assert identical deltas)"

key-files:
  created:
    - ".planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/331-SEEDS-DESIGN.md"
    - "test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol"
  modified:
    - "test/fuzz/CrankNonBrick.t.sol (+117 lines, purely additive — the Seed 2 no-brick section)"
    - ".planning/phases/331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca/deferred-items.md (appended the 331-03 pre-existing-failures entry)"

key-decisions:
  - "Seed 2 path shape = a NEW batchPurchaseForKeeper external + an internal _keeperBuyUnit (returns the affiliate contribution), NOT an in-place branch of batchPurchase — justified from the R6 per-player claimable-shortfall pre-check + the Seed 1 return-value need + the scope-fence (leave the player-facing path untouched)"
  - "Keeper buy is LOOTBOX-ONLY (_batchPurchaseUnit passes ticketQuantity=0, the slice IS the lootBoxAmount), which narrows the reachable MintModule.purchase revert set materially (the ticket-cost/ENF-01/presale branches are NOT reached)"
  - "affiliateCommissionFromSender (:527) confirmed as the SOLE non-coalescible write (keyed on sender); affiliateCoinEarned/_totalAffiliateScore/leaderboard/creditFlip coalesce to fixed slots (affiliateAddr==SDGNRS constant across a DGNRS batch); the per-referrer commission CAP must be applied per-sender INSIDE the unit before summing the post-cap scaledAmount"
  - "Read affiliateCommissionFromSender via vm.load of slot 5 (it is private, no public getter); re-attested the affiliate slots (coinEarned=1, totalScore=4, commissionFromSender=5) via forge inspect storage on 63bc16ca"

patterns-established:
  - "Seed-money-path delta-audit + no-brick proof pair, both parameterized via the same KEEPER_PATH_LANDED gate so the gated contract diff activates the equivalence/liveness assertions by flipping one bool"

requirements-completed: [GAS-02]

# Metrics
duration: ~50min
completed: 2026-05-27
---

# Phase 331 Plan 03: Seed 1 (shared-slot DGNRS affiliate aggregation) + Seed 2 (pre-validated keeper batch path) — design + money-path delta-audit + no-brick liveness tests Summary

**Enumerated the full Seed 1+2 contract blueprint (every keeper-buy revert source dispositioned, the coalescible/non-coalescible SSTORE table confirmed against `63bc16ca`, the new `batchPurchaseForKeeper` + `_keeperBuyUnit` path shape chosen) and authored the money-path delta-audit harness + the keeper-batch no-brick proof the gated 331-05 contract diff must pass — all GREEN against the current path and parameterized via a `KEEPER_PATH_LANDED` gate so the byte-identical + un-brickable assertions activate the moment 331-05 lands the function.**

## Performance

- **Duration:** ~50 min
- **Started:** 2026-05-27 (Phase 331 wave 2)
- **Completed:** 2026-05-27
- **Tasks:** 3
- **Files modified:** 4 (2 created, 2 modified; zero `contracts/*.sol`)

## Accomplishments
- Authored `331-SEEDS-DESIGN.md`: the SEED 2 revert-source enumeration (R1-R10) — each `_batchPurchaseUnit -> _purchaseFor -> MintModule.purchase` revert mapped to a pre-validate-or-cheap-skip disposition, with R1/R2 (gameOver/liveness) moved to whole-batch pre-loop gates and R3/R5/R6/R7 becoming cheap per-player skips (the `autoOpen` RD-5 entry-gate technique). The keeper buy is lootbox-only (ticketQuantity hard-zero), which removes the ticket-cost / ENF-01 / presale branches from the reachable set. The SEED 1 coalescible/non-coalescible SSTORE table confirmed `affiliateCommissionFromSender` (`:527`) is the SOLE non-coalescible write; the acc-flush shape mirrors the degenerette `resolveBets` precedent (`:407-426`). The chosen path shape — a NEW `batchPurchaseForKeeper` + internal `_keeperBuyUnit` — is justified from the revert-source count.
- Built `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol`: drives an N-player DGNRS keeper batch (fundable + poisoned mix) through the CURRENT `batchPurchase` path and snapshots every money outcome, asserting the aggregate==sum-of-successful (no double-credit), poisoned==zero-contribution+slice-refunded (no skipped-player drain), and per-sender commission keyed-correctly invariants. A `_drive(useKeeperPath)` toggle + `KEEPER_PATH_LANDED` gate + a two-run `vm.snapshotState`/`revertToState` equivalence test (`testPathEquivalence_*`, SKIPs today) activate the byte-identical path-equivalence proof once 331-05 lands. 2 PASS / 1 SKIP.
- Extended `test/fuzz/CrankNonBrick.t.sol` (+117 lines, purely additive): `testKeeperBatchSkipsPoisonedMiddlePlayer` + the fuzzed poison-position variant prove a poisoned (sub-LOOTBOX_MIN) player is skipped + refunded while the healthy players purchase and the batch never reverts — the `feedback_security_over_gas` HARD CONSTRAINT liveness floor (T-331-06). Parameterized via the same `_driveKeeperBatch(useKeeperPath)` toggle + `KEEPER_PATH_LANDED` gate. Both new tests GREEN (fuzz 1000 runs across all poison positions).
- Re-attested the DegenerusAffiliate storage slots (`affiliateCoinEarned=1`, `_totalAffiliateScore=4`, `affiliateCommissionFromSender=5`) via `forge inspect ... storage` against the `63bc16ca` layout (the private triple-mapping commission slot is read via `vm.load`; the two coalescible accumulators via the public `affiliateScore`/`totalAffiliateScore` getters).

## Task Commits

Each task was committed atomically:

1. **Task 1: Enumerate Seed 1+2 revert sources + coalescible writes + choose the path shape** — `d13894c0` (docs)
2. **Task 2: Money-path delta-audit harness (current path vs the proposed keeper-batch path)** — `648783e2` (test)
3. **Task 3: Extend CrankNonBrick — poisoned-player no-brick under the pre-validated path** — `46f30546` (test)

## Files Created/Modified
- `.planning/phases/331-.../331-SEEDS-DESIGN.md` — the Seed 1+2 contract blueprint (revert-source enumeration R1-R10, the coalescible/non-coalescible SSTORE table, the chosen `batchPurchaseForKeeper`+`_keeperBuyUnit` shape, the acc-flush shape, the 5 no-brick/money-path invariants 331-05 must satisfy).
- `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` — the money-path delta-audit baseline + the gated byte-identical path-equivalence proof.
- `test/fuzz/CrankNonBrick.t.sol` — the Seed 2 keeper-batch no-brick proof (additive).
- `.planning/phases/331-.../deferred-items.md` — appended the 331-03 pre-existing-failures entry.

## Decisions Made
- **Seed 2 path shape = new function + internal helper.** A new `batchPurchaseForKeeper` (AF_KING-gated) + an internal `_keeperBuyUnit(player, payKind)` that RETURNS the per-unit affiliate contribution. Justified: (a) R6 (per-player claimable shortfall) forces a per-player view check the player path never needs, so an in-place conversion would entangle keeper-only logic with the kept-for-safety player path; (b) Seed 1's "return-then-aggregate" needs the unit to return a value (today's `_batchPurchaseUnit` is `external onlySelf` returning void); (c) once every revert is pre-gated the external self-call is pointless (its only job was the try/catch revert-isolation) — a plain internal call saves the CALL overhead on top of the SSTORE savings.
- **The keeper buy is lootbox-only.** `_batchPurchaseUnit` calls `_purchaseFor(player, 0, msg.value, "DGNRS", payKind)` — ticketQuantity is hard-zero, the slice IS the lootBoxAmount. This narrows the reachable `MintModule.purchase` revert set: the ticket-cost / `_callTicketPurchase` / ENF-01 / presale-box branches are NOT reached. The reachable revert set is `_livenessTriggered` (whole-batch), `lootBoxAmount < LOOTBOX_MIN` / `totalCost==0` (cheap-skip), the DirectEth `remainingEth < lootBoxAmount` (per-player pre-validate), the Combined/Claimable shortfall underflow (per-player claimable pre-check — the one source that is per-player mutable state, NOT a global flag, so a per-player cheap-skip is MANDATORY), and the same-day re-deposit `storedDay != lbDay` (defensive cheap-skip, unreachable on a fresh keeper buy).
- **`affiliateCommissionFromSender` is the SOLE non-coalescible write + read via `vm.load`.** It is keyed on `sender` (the player) and `private` (no public getter). Read via the slot-5 triple-mapping leaf (`keccak(sender . keccak(affiliateAddr . keccak(lvl . 5)))`). The per-referrer commission CAP is keyed on `sender` too, so each unit must apply its cap and compute its post-cap `scaledAmount` INSIDE the unit before summing into the coalescible accumulators — aggregating before the cap would change the money outcome (documented in 331-SEEDS-DESIGN.md §1.1).

## Deviations from Plan

None — plan executed exactly as written. Three in-line reconciliations (not behavior deviations):
- **[Rule 3 — blocking] `forge inspect ... storage` returned "storage layout missing from artifact".** The repo's `foundry.toml` does not set `extra_output = ["storageLayout"]`, so the cached artifact lacks the layout. Resolved by a one-shot `FOUNDRY_EXTRA_OUTPUT='["storageLayout"]' forge build` of `DegenerusAffiliate.sol` (forced via a temporary probe comment), read the slots (coinEarned=1, totalScore=4, commissionFromSender=5), then **reverted the probe comment immediately** (`git checkout -- contracts/DegenerusAffiliate.sol`) so `contracts/*.sol` stays byte-clean. No contract mutation persisted.
- **[Rule 1 — bug in the harness] keeper-balance underflow in the delta-audit.** The first run reverted with `arithmetic underflow` because `vm.deal` SETS (not adds) the keeper balance and the `_drive` helper re-dealt the keeper between the pre-snapshot and the call. Fixed by funding the keeper ONCE in `setUp` and removing the re-deal from `_drive` so `pre.keeperBalance - post.keeperBalance` is a clean net successful-spend. Tests GREEN after the fix.
- **Plan named `affiliate.affiliateCommissionFromSender(...)` as a getter.** That accessor does not exist (the mapping is `private`); switched to a `vm.load` slot-5 read (above). The two coalescible accumulators DO have public getters (`affiliateScore` / `totalAffiliateScore`), which the harness uses directly.

## Deferred Issues
- **4 PRE-EXISTING failures in the untouched part of `CrankNonBrick.t.sol`** (`testCrankBetsSkipsPoisonedMiddleItem`, `testFuzz_CrankBetsPoisonPositionNeverBricks`, `testCrankBoxesSkipsPoisonedEntryViaTryCatch`, `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry`) — verified IDENTICAL-fail with my change stashed (my 117-line addition is purely additive, 0 deletions). These are the known 58-failure baseline (v48-reward-model assertions + 330 slot-drift), DEFERRED to Phase 332 TST. Logged in `deferred-items.md` under the 331-03 entry. NOT fixed here (scope-boundary rule: out-of-scope, not caused by this task).

## Threat Surface
The Seed 1+2 design touches the affiliate MONEY path and a trust boundary (keeper batch → shared DGNRS affiliate slot; keeper batch → per-player mint). All three threat-register mitigations are covered by the tests authored here (no new un-modelled surface introduced — this plan adds tests + a design doc, no contract code):
- **T-331-06 (DoS, poisoned player bricks the batch)** — `CrankNonBrick.testKeeperBatchSkipsPoisonedMiddlePlayer` + fuzz variant (no-brick liveness, parameterized for the gated path).
- **T-331-07 (Tampering, aggregation double-credits/leaks)** — `KeeperBatchAffiliateDeltaAudit`: aggregate == sum-of-successful + per-sender commission stays per-player.
- **T-331-08 (Repudiation, skipped-player slice drain)** — `KeeperBatchAffiliateDeltaAudit`: poisoned player == zero contribution AND slice refunded.

## User Setup Required
None — test + doc only; no `contracts/*.sol` touched and no constant landed. The Seed 1+2 contract code is the GATED 331-05 plan (`autonomous: false`, the SECOND USER-approved contract gate).

## Next Phase Readiness
- The gated 331-05 implementer has a concrete blueprint (`331-SEEDS-DESIGN.md`) with no open revert source + the two passing test scaffolds it must satisfy: flip `KEEPER_PATH_LANDED` to `true` and wire `_drive(true,...)` / `_driveKeeperBatch(true,...)` to call `batchPurchaseForKeeper`, and the byte-identical money-equivalence + no-brick liveness assertions activate.
- **Contract-boundary HARD STOP reminder:** the Seed 1+2 contract code lands in 331-05 (`autonomous: false`, USER-approved gate), NOT this plan.
- No blockers.

## Self-Check: PASSED

- `.planning/phases/331-.../331-SEEDS-DESIGN.md` — FOUND
- `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` — FOUND
- `test/fuzz/CrankNonBrick.t.sol` (extended) — FOUND
- `331-03-SUMMARY.md` — FOUND
- Commit `d13894c0` (Task 1 docs) — FOUND
- Commit `648783e2` (Task 2 test) — FOUND
- Commit `46f30546` (Task 3 test) — FOUND
- `forge test --match-path test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` — 2 PASS / 1 SKIP (gated)
- `forge test --match-path test/fuzz/CrankNonBrick.t.sol --match-test testKeeperBatch...` — 2/2 PASS (the new no-brick tests)
- `git diff --name-only -- contracts/` for this plan's changes — EMPTY (no contract mutation)

---
*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca · plan 03*
*Completed: 2026-05-27*
