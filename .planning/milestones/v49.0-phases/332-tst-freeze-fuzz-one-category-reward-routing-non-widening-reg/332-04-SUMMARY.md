---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 04
subsystem: testing
tags: [foundry, hardhat, degeneretteResolve, autoResolve-rename, RESOLVE_FLAT_BURNIE, flat-per-tx, ge3-gate, NoWork, WWXRP-exclusion, AUTO-04, results-equality, value-invariance, recipient-isolation, degenerette-stat-gate, frozen-subject]

# Dependency graph
requires:
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 autoResolve -> degeneretteResolve rename + the unchanged _degeneretteResolveBet -> delegatecall GAME_DEGENERETTE_MODULE.resolveBets per-item resolution machinery (only the bounty wrapper + >=3 gate changed)"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "RESOLVE_FLAT_BURNIE = 1e18 (the flat ~1-BURNIE lose re-peg landed at GAS-06) + the >=3 non-WWXRP pay-gate / revert-on-no-work / WWXRP-excluded shape"
provides:
  - "TST-05 empirical proof: degeneretteResolve pays exactly ONE flat RESOLVE_FLAT_BURNIE (1e18) per tx at >=3 successfully-resolved non-WWXRP bets — proven by recipient-isolated COUNT==1 AND amount==1e18, never a per-item summed reward (the retired 3*peg premise)"
  - "1-2 non-WWXRP resolved -> committed UNPAID (count==0), NO revert (the trailing tail is never stranded); 0 resolved -> reverts NoWork(); WWXRP (currency==3) excluded from BOTH the >=3 gate count AND the reward (3 WWXRP-only -> resolved, UNPAID, no revert; mixed 2 WWXRP + 3 non-WWXRP -> PAID once)"
  - "RESULTS-equality proven by VALUE-INVARIANCE (Open Question 1 route b): the BURNIE/WWXRP mint + ETH claimable + claimablePool deltas equal the per-spin-derived expected sums, and a per-bet resolution delta is byte-identical whether or not the >=3 reward fired — the bounty wrapper provably never touches the resolution math; no deleted autoResolve source resurrected"
  - "the Hardhat Degenerette stat tree (DegenerettePerNEvExactness / DegeneretteBonusEv / DegeneretteProducerChi2) stays GREEN at v48 parity after the rename (chi2/EV-exactness distribution invariance): 24 passing / 1 pending (the STAT-02 round-trip lifecycle soft-skip, by design)"
affects: [333-terminal-delta-audit-3-skill-adversarial-sweep-closure, TST-04-non-widening-ledger]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Recipient-isolated single-pass creditFlip COUNT + AMOUNT oracle (_keeperCredit) deriving BOTH from one vm.getRecordedLogs() — the buffer DRAINS on read, so a separate count-then-amount pair would see an empty array on the second call. The flat-ONE proof asserts count==1 AND amount==RESOLVE_FLAT_BURNIE, never the retired per-item *summed* premise (3*peg)"
    - "The documented crank-resolve operator relaxation: degeneretteResolve -> try this._degeneretteResolveBet (external self-call, msg.sender==address(game)) -> delegatecall resolveBets runs with msg.sender==address(game), so resolveBets's _resolvePlayer requires the bet owner to have approved the GAME as operator (game.setOperatorApproval(address(game), true)). Placement stays gated; the keeper resolve path opts the player in the same way the AfKing subscription flow does. Without it every _degeneretteResolveBet reverts NotApproved (caught) -> totalResolved==0 -> NoWork()"
    - "Value-invariance over the bounty gate via snapshot/revert: resolve the SAME 3 non-WWXRP bets gate-FIRES (one degeneretteResolve call -> keeper paid once) vs gate-NEVER-FIRES (three single-bet calls, each 1 non-WWXRP < 3 -> unpaid, no revert); assert the player's BURNIE/claimable/claimablePool deltas are byte-identical between the two runs while the keeper creditFlip count differs (1 vs 0) — the bounty wrapper is provably orthogonal to the resolution payout"
    - "RESULTS-equality replay reusing the DegeneretteFreezeResolution per-spin FullTicketResult-event baseline idiom (3-tier ETH split _ethShareOf + additive BURNIE/WWXRP sums), extended to fold a trailing-ETH 4th phase into the ETH sum AND count the keeper's CoinflipStakeUpdated in the SAME single log pass (so the paid-path firing is observed alongside the value-invariant deltas)"
    - "WWXRP gate exclusion proven via currency-typed bet placement (the place currency 0/1/3 lands in packed bits [42..43]; WWXRP==3 is read by degeneretteResolve at :1612-1619): 3 WWXRP-only resolves -> totalResolved==3 (no NoWork) but successCount==0 (no creditFlip); mixed batch -> the 3 non-WWXRP trip the gate, the 2 WWXRP do not count"

key-files:
  created:
    - "test/fuzz/DegeneretteResolveRepeg.t.sol — 7 GREEN proofs (742 lines): TST-05 the 5 re-peg/gate/WWXRP-exclusion cases (a-e: flat ONE 1e18 / 1-2 unpaid-no-strand / 0 NoWork / 3 WWXRP-only unpaid / mixed paid) + RESULTS-equality value-invariant (mixed-currency delta == per-spin baseline, non-vacuous) + resolution-deltas-independent-of-reward-gate (snapshot/revert, gate-fires vs never-fires byte-identical)"
  modified: []

key-decisions:
  - "RESULTS-equality is proven by VALUE-INVARIANCE (Open Question 1 route b), NOT by checking out / mocking the deleted autoResolve source. The per-item resolution math is produced by the UNCHANGED _degeneretteResolveBet -> delegatecall GAME_DEGENERETTE_MODULE.resolveBets (the rename touched only names + the bounty wrapper + the >=3 gate). Two complementary directions establish it: (1) the resolution deltas equal the per-spin-derived expected sums (the math is byte-identical to the per-item baseline replayed from the contract's own FullTicketResult events); (2) a per-bet resolution delta is identical whether or not the >=3 reward fired (snapshot/revert). No resurrected source."
  - "The flat-ONE reward is asserted as COUNT==1 AND amount==RESOLVE_FLAT_BURNIE (1e18), NEVER a per-item *summed* assertion (the retired 3*CRANK_RESOLVE_BET_GAS_UNITS*... premise that CrankLeversAndPacking::testCrankBetsEmitsExactlyOneCreditFlipForManyItems carried — one of the 17 reds TST-04 deletes). The amount equality is the load-bearing T-332-04-SUM mitigation."
  - "WWXRP exclusion (AUTO-04, T-332-04-WWXRP) is proven on BOTH dimensions in two cases: case (d) 3 WWXRP-only -> totalResolved==3 (no NoWork, revert-on-no-work keys on totalResolved=ANY currency) but successCount==0 -> UNPAID (excluded from the reward); case (e) mixed -> the 3 non-WWXRP trip the gate while the 2 WWXRP resolve alongside without counting (excluded from the >=3 count). A WWXRP-spam faucet is impossible."
  - "Non-vacuity guards (T-332-04-VAC) are explicit: the RESULTS-equality asserts assertGt(expectedBurnie/Wwxrp/EthShare, 0) so the byte-identical equality cannot pass against an empty/zero baseline, and the gate-independence test asserts assertGt(claimableDeltaA, 0) + assertGt(burnieDeltaA, 0) so the A==B equality is not a vacuous 0==0."
  - "The keeper-router resolve requires the bet owner to approve the GAME as operator (game.setOperatorApproval(address(game), true) in setUp) — the documented crank-resolve relaxation, byte-identical to how CrankFaucetResistance / CrankNonBrick exercise the resolve path. This is the resolve-path opt-in the AfKing subscription performs; placement stays gated. It is NOT a contract change."
  - "The Hardhat stat secondary gate (A2) is recorded GREEN at v48 parity: 24 passing / 1 pending. The 1 pending is the STAT-02 D-IMPL-01 on-chain producer round-trip drift guard, which self-soft-skips on a lifecycle gas budget ('Transaction ran out of gas — soft-skip') BY DESIGN — it is a pending (not a failure) and is the v48-parity baseline, not a regression. The post-run Mocha MODULE_NOT_FOUND is a teardown file-unloader artifact (relative-path unload after all tests passed); the background exit code was 0."

patterns-established:
  - "Pattern 1: flat-per-tx re-peg proof via recipient-isolated COUNT==1 AND amount==flat-literal — the v49 successor to the retired per-item *summed* reward premise. The reward count oracle isolates the keeper (topics[1]==keeper) so a player's resolution winnings can never inflate/mask the bounty count, and the amount equality kills the summed-premise."
  - "Pattern 2: RESULTS value-invariance over a bounty/gate wrapper via snapshot/revert + per-spin event replay — resolve the SAME bets two ways differing ONLY in whether the gate fired, assert the resolution deltas are byte-identical while the keeper credit differs. The clean route for a FROZEN renamed subject (no pre-rename source to diff against)."

requirements-completed: [TST-05]

# Metrics
duration: 6min
completed: 2026-05-27
---

# Phase 332 Plan 04: TST-05 `degeneretteResolve` Rename + Flat ~1-BURNIE Re-Peg (Flat-Per-Tx / >=3-Gate / NoWork / WWXRP-Excluded / RESULTS-Equality) Summary

**Proved the v49 `autoResolve` -> `degeneretteResolve` rename + flat ~1-BURNIE "lose" re-peg (GAS-06 / TST-05) EMPIRICALLY: the bounty is a FLAT literal ~1 BURNIE (`RESOLVE_FLAT_BURNIE = 1e18`) paid ONCE per tx (recipient-isolated COUNT==1 AND amount==1e18, NEVER a per-item summed reward) gated at >=3 successfully-resolved NON-WWXRP bets; 1-2 resolved commit UNPAID with NO revert (the trailing tail is never stranded); 0 resolved reverts `NoWork()`; WWXRP (currency==3) is excluded from BOTH the >=3 gate count AND the reward (3 WWXRP-only resolve UNPAID; a mixed 2 WWXRP + 3 non-WWXRP batch pays once at the gate); and the per-item resolution RESULTS are byte-identical to the per-spin baseline and provably independent of whether the >=3 reward fired (VALUE-INVARIANCE, Open Question 1 route b — no deleted `autoResolve` source resurrected). The Hardhat Degenerette stat tree stays GREEN at v48 parity (24 passing / 1 pending). ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~6 min (Foundry authoring); + a ~2 min Hardhat stat-gate run
- **Started:** 2026-05-27T12:36 (local) — Task 1 first run
- **Completed:** 2026-05-27T12:43 (local) — Task 2 committed `75284aac`
- **Tasks:** 2 (both `tdd="true"`)
- **Files created:** 1 (`test/fuzz/DegeneretteResolveRepeg.t.sol`, 742 lines, 7 tests)

## Accomplishments

- **Task 1 — the 5 re-peg / gate / WWXRP-exclusion cases (flat ONE credit, never the sum):**
  - `testGteThreeNonWwxrpPaysExactlyOneFlat` (case a): 3 non-WWXRP bets (ETH + BURNIE + ETH) resolve -> exactly ONE keeper `creditFlip` (`_keeperCredit(keeper)` count==1) AND credited amount == `RESOLVE_FLAT_BURNIE` (1e18) — the FLAT literal, asserted directly, NEVER `3 * peg`.
  - `testOneOrTwoNonWwxrpCommittedUnpaidNoRevert` (case b): 2 non-WWXRP resolve -> committed (both bet slots zeroed) but UNPAID (count==0), NO revert — `successCount==2 < 3` skips the reward yet commits the resolutions (the tail is not stranded).
  - `testZeroResolvedRevertsNoWork` (case c): a real placed bet (slot non-zero, AUTO-02 probe passes) with NO RNG word injected -> `_degeneretteResolveBet` reverts (caught per-item), `totalResolved==0` -> the call reverts `NoWork()`; the bet stays unresolved.
  - `testThreeWwxrpOnlyResolvedUnpaidNoRevert` (case d): 3 WWXRP bets resolve -> `totalResolved==3` (no `NoWork`, the revert-on-no-work keys on totalResolved=ANY currency) but `successCount==0` -> UNPAID (count==0). WWXRP excluded from the reward — a WWXRP-spam faucet is impossible.
  - `testMixedWwxrpAndNonWwxrpPaysAtGate` (case e): a 5-item batch (3 non-WWXRP + 2 WWXRP, item 0 the non-WWXRP probe) -> PAID exactly once (count==1, amount==1e18) because the 3 non-WWXRP trip the gate while the 2 WWXRP resolve alongside without counting. All 5 bets resolved.
- **Task 2 — RESULTS-equality (value-invariant to the bounty wrapper) + Hardhat stat re-confirm:**
  - `testResultsEqualityValueInvariant`: a >=3 non-WWXRP mixed-currency batch (ETH 4-spin + BURNIE 3-spin + WWXRP 2-spin + trailing ETH 1-spin) resolved via `degeneretteResolve` (the >=3 gate FIRES — keeper credit count==1) -> the BURNIE mint, WWXRP mint, ETH claimable, and claimablePool deltas each equal the per-spin-derived expected sums (cap-free large pool; replayed from the contract's own `FullTicketResult` events), with `assertGt(...,0)` non-vacuity on each currency. The resolution RESULTS are byte-identical to the per-item baseline — value-invariant to the bounty wrapper.
  - `testResolutionDeltasIndependentOfRewardGate`: the SAME 3 non-WWXRP bets resolved two ways against a snapshot — Run A (all 3 in ONE call, gate FIRES, keeper paid once) vs Run B (revert, 3 single-bet calls, gate NEVER fires, keeper unpaid). The player's BURNIE/claimable/claimablePool deltas are byte-identical between A and B (with `assertGt` non-vacuity) while the keeper creditFlip count differs (1 vs 0) — the bounty wrapper provably never touches the resolution math.
  - Hardhat Degenerette stat secondary gate re-confirmed GREEN at v48 parity: **24 passing / 1 pending** (the STAT-02 round-trip lifecycle soft-skip, by design — chi2/EV-exactness unchanged by the rename).
- All 7 Foundry tests GREEN; zero `contracts/*.sol` mutation.

## Task Commits

1. **Task 1 — the 5 re-peg / gate / WWXRP-exclusion cases** — `6f8bd35a` (test)
2. **Task 2 — RESULTS-equality value-invariant + Hardhat stat re-confirm** — `75284aac` (test)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — see the final docs commit.

## Files Created/Modified

- `test/fuzz/DegeneretteResolveRepeg.t.sol` — TST-05 proof file (`contract DegeneretteResolveRepeg is DeployProtocol`). Ports the recipient-isolated `CoinflipStakeUpdated` count oracle from `CrankLeversAndPacking.t.sol` (extended to `_keeperCredit` deriving COUNT + AMOUNT in one log pass) and the bet-placement / RNG-injection / winning-combo / `_ethShareOf` / per-spin `FullTicketResult` replay scaffold from `DegeneretteFreezeResolution.t.sol`. Adds the documented crank-resolve operator-approval relaxation in `setUp` (`game.setOperatorApproval(address(game), true)`), the `_betSlot` reader (degeneretteBets slot 45 double-keccak), and the `_replayPerSpinBaselineAndKeeperCredit` single-pass helper.

## Verification

- `forge test --match-contract DegeneretteResolveRepeg` -> **7 passed / 0 failed**.
- The reward count oracle asserts a FLAT one credit (count==1 AND amount==1e18), never a per-item sum.
- WWXRP excluded from both the gate and the reward (cases d/e GREEN).
- RESULTS-equality is value-invariant + non-vacuous (`assertGt` on each expected sum and on the A==B deltas); no deleted `autoResolve` source resurrected (Open Question 1 route b).
- Hardhat stat gate: `npx hardhat test test/stat/DegenerettePerNEvExactness.test.js test/stat/DegeneretteBonusEv.test.js test/stat/DegeneretteProducerChi2.test.js` -> 24 passing / 1 pending (v48 parity GREEN; the 1 pending = STAT-02 round-trip lifecycle soft-skip by design).
- `git diff --name-only contracts/` -> empty (ZERO mainnet mutation, FROZEN subject honored). The Hardhat `DeployProtocol` fixture rewrote `contracts/ContractAddresses.sol` with fresh deploy addresses (and zeroed `AF_KING`) as a run side effect; this unintended churn was reverted via `git checkout -- contracts/ContractAddresses.sol` and the Foundry suite re-confirmed GREEN with the canonical addresses restored.

## Deviations from Plan

None affecting scope. Two execution refinements (no contract change, no scope change), both required to make the locked re-peg dispositions exercisable against the FROZEN subject:

1. **[Rule 3 — blocking issue: operator-approval relaxation] Added `game.setOperatorApproval(address(game), true)` for the bet owner in `setUp`.** The keeper-router resolve path (`degeneretteResolve` -> `try this._degeneretteResolveBet` -> delegatecall `resolveBets`) runs `resolveBets` with `msg.sender == address(game)`; `resolveBets`'s `_resolvePlayer(player)` calls `_requireApproved(player)` when `player != msg.sender`, which reverts `NotApproved` unless the bet owner approved the GAME as operator. Without the approval, every `_degeneretteResolveBet` reverts (caught per-item) -> `totalResolved==0` -> `NoWork()`, masking the entire re-peg behavior. This is the DOCUMENTED crank-resolve relaxation (DegenerusGame.sol:1738 "the approval gate relaxed for the resolve path only") and is byte-identical to how `CrankFaucetResistance` / `CrankNonBrick` already exercise the resolve path — NOT a contract change.
2. **[Rule 1 — bug in the test's own log oracle] Merged the count + amount oracle into a single `_keeperCredit` log pass.** The initial draft called `_countCoinflipStakeUpdatedFor(keeper)` (which calls `vm.getRecordedLogs()`, DRAINING the buffer) then `_keeperCreditFlipAmount(keeper)` (a second `getRecordedLogs()` seeing an empty array -> "no keeper creditFlip emission found"). Combined into `_keeperCredit(who)` returning `(count, amount)` from one buffer read; the count-only `_countCoinflipStakeUpdatedFor` now delegates to it. Test-only fix.

No CLAUDE.md present in the project root (global instructions only).

## Contract Defects Surfaced

None. Every proof passed against the FROZEN v49 source. The `degeneretteResolve` structure (DegenerusGame.sol:1595-1631) behaves exactly as the locked TST-05 design specifies: flat `RESOLVE_FLAT_BURNIE` once at `successCount >= 3`, `revert NoWork()` at `totalResolved == 0`, WWXRP (currency==3) excluded from `successCount` only, and the per-item resolution math untouched by the bounty wrapper.

## Known Stubs

None — no hardcoded empty values, placeholders, or unwired data sources. Every assertion drives real protocol state (real Degenerette bets placed via the public `placeDegeneretteBet` API across ETH/BURNIE/WWXRP currencies, a real lootbox RNG word injected at the bet's bound index, real resolution via `degeneretteResolve`) and reads it back via the contract's own view (`claimableWinningsOf`), the token `balanceOf` (BURNIE/WWXRP), the authoritative storage slots (`degeneretteBets` slot 45, `claimablePool` slot 1 byte 16), and the contract's own `CoinflipStakeUpdated` / `FullTicketResult` events. The winning ticket is the on-chain spin-0 result ticket (8/8 self-match), not a mock.

## Self-Check: PASSED

- `test/fuzz/DegeneretteResolveRepeg.t.sol` — FOUND
- commit `6f8bd35a` (Task 1) — FOUND
- commit `75284aac` (Task 2) — FOUND
- `forge test --match-contract DegeneretteResolveRepeg` — 7 passed / 0 failed
- Hardhat stat gate — 24 passing / 1 pending (v48 parity GREEN)
- `git diff --name-only contracts/` — empty (zero mainnet mutation)
