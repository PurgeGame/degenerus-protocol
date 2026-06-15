# Mutation Findings — v63 subject `a8b702a7`

Per-GENUINE-survivor disposition ledger for the BOUNDED v63 mutation campaign. Every GENUINE
survivor from the triage (`SURVIVOR-TRIAGE-v63.md`) is dispositioned here as **KILLED-BY-TEST**
(closed by a new regression test in `test/mutation/MutationKills.t.sol`, validated
fail-with-mutation / pass-without) or **ROUTED-TO-FINDING** (a real contract defect carried to
the 396 TERMINAL gated USER-hand-review boundary, never fixed in-phase).

**Subject (byte-frozen):** `a8b702a7` — contracts tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620`. `git diff a8b702a7 -- contracts/` EMPTY.

---

## Headline result

**ZERO contract defects. ALL GENUINE survivors are TEST-coverage holes → ALL KILLED-BY-TEST.**

The bounded campaign scored three spine targets (`BitPackingLib` full, `DegenerusGameStorage`
full, `StakedDegenerusStonk` full) and produced **7 GENUINE survivors** (1 packing-identity +
6 solvency-spine oracle gaps). Every one is a regression-net coverage hole on a CORRECT subject
line — none exposes wrong contract behavior. All 7 are KILLED by deterministic regression tests.
This matches the dual-net result (389–394: 0 contract findings except the routed BURNIE-04) and
the triage pattern (all test-gaps, no defects). **Nothing routes to a fix.**

---

## Disposition ledger

| ID | Target | Line(s) | Threat class | Disposition | Evidence |
|---|---|---|---|---|---|
| G-BPL-01 | `BitPackingLib.setPacked` | 110 (+C1 masks 33/36/39/42/45) | PACKING IDENTITY | **KILLED-BY-TEST** | `test_kills_BitPackingLib_110_setPacked_roundTrip` — PASS clean; FAIL with CR-mutant (`LEVEL_UNITS 0 != 65535`) AND with C1 MASK_16 `-1→+1` mutant (`65537 != 65535`) |
| K1 | `StakedStonk` gameOver deterministic burn (`burn`/`_deterministicBurn`/`_deterministicBurnFrom`) | 624,625,659,678,679,681,684–693,707 | SOLVENCY SPINE | **KILLED-BY-TEST** | `test_kills_StakedStonk_deterministicBurn_gameOverPayout` (FAIL w/ 678 RR) + `test_kills_StakedStonk_deterministicBurn_stethFallbackSplit` (FAIL w/ 693 RR) |
| K2 | `StakedStonk.burnAtGameOver` | 602,603,605,606 | SOLVENCY SPINE | **KILLED-BY-TEST** | `test_kills_StakedStonk_burnAtGameOver_drainsLocalSupply` (FAIL w/ 602 RR) |
| K3 | `StakedStonk.transferFromPool` (regular leg) | 549,553,555,558,559,567,569,570 | SOLVENCY | **KILLED-BY-TEST** | `test_kills_StakedStonk_transferFromPool_creditsRecipient` (FAIL w/ 558 RR) |
| K4 | `StakedStonk.transferFromPool` (self-win burn) | 563,564 | SOLVENCY | **KILLED-BY-TEST** | `test_kills_StakedStonk_transferFromPool_selfWinBurns` (FAIL w/ 563 RR) |
| K5 | `StakedStonk.transferBetweenPools` | 580,584,586,589,591,592,593 | SOLVENCY | **KILLED-BY-TEST** | `test_kills_StakedStonk_transferBetweenPools_conserves` (FAIL w/ 591 RR) |
| K6 | `StakedStonk.wrapperTransferTo` | 456,457,459 | SOLVENCY | **KILLED-BY-TEST** | `test_kills_StakedStonk_wrapperTransferTo_movesBalance` (FAIL w/ 457 RR) |

**ROUTED-TO-FINDING: none.** No GENUINE survivor revealed wrong contract behavior; nothing is
carried to 396 TERMINAL as a gated fix from this plan.

---

## Why each GENUINE survivor is a TEST gap, not a defect

The dominant cause across all 7 is a single oracle shape: the comprehensive oracle (the 12
388-02 green-baseline suites) drives the **LIVE-game gambling-burn → `claimRedemption`** path
exhaustively (the live settle legs were all CAUGHT) but never drives the **post-gameOver
deterministic / pool-drain** paths, nor the `BitPackingLib.setPacked` mint-data round-trip. The
subject code on those paths is correct — the redemption suites simply lacked a gameOver-driving
fixture and a setPacked round-trip assertion. The kill-tests supply exactly those missing
assertions:

- **G-BPL-01** pins the masked-RMW round-trip (write a field, read it back, assert exact value +
  sibling preservation + over-wide-value masking). Kills both the body-removal CR mutant and the
  C1 mask-value mutants.
- **K1** drives `burn()` under a mocked `gameOver()==true` and asserts the exact post-gameOver
  payout identity: supply burned by the exact amount, burner balance debited exactly, a positive
  proportional ETH payout delivered, zero BURNIE; plus a stETH-fallback-split variant that forces
  `owed > on-hand ETH` and asserts both the ETH leg and the stETH remainder leg land.
- **K2** calls `burnAtGameOver()` as the game and asserts the local balance zeroes, supply drops
  by exactly the burned balance, and `delete poolBalances` cleared every pool slot.
- **K3/K4/K5/K6** pin the pool-transfer / self-win-burn / pool-rebalance / wrapper-transfer
  post-conditions (debit/credit/return-value/conservation) the oracle left unasserted.

Each kill-test was validated by re-applying its survivor's mutation IN PLACE, confirming the
test went RED, then `git checkout -- contracts/` restoring the byte-frozen subject and
confirming GREEN. No commit was made while a mutant was on disk.

---

## FALSE survivors (not killed — equivalent / unreachable / already-covered)

Recorded FALSE in `SURVIVOR-TRIAGE-v63.md`, NOT forced into tests (no-over-invest posture):

- **BitPackingLib C1/C2/C3** (54 survivors) — MASK_*/SHIFT constant mutations on a
  caller-pre-clamped width-bounding mask; equivalent under the subject's invariant (C1 also
  killed by G-BPL-01's over-wide assertion, but the survivors remain FALSE as the mask
  redundancy is by-design defense-in-depth).
- **DegenerusGameStorage S-DGS-01** (line 583 `_isDistressMode` live branch) — reachable but
  covered by the JS distress suites OUTSIDE the forge-oracle union; a gap in the narrow oracle
  subset, not the protocol's overall coverage.
- **StakedStonk F1–F6** — constructor (deploy-only one-shot), ERC20 metadata constants,
  keeper-crank pass-throughs, deposit event/ACL lines, pure view functions, and the gameOver
  settle branch / batch-loop plumbing (the live settle path is CAUGHT; the gameOver settle
  accounting identity is already pinned by K1/K2 on the burn side; the loop/skip lines are
  non-solvency-bearing keeper-bounty count plumbing).

---

## Bounded-campaign tail (CI-deferred targets)

Three targets were deliberately NOT run (bounded campaign — via_ir per-mutant cost, CI/overnight
scope): `BurnieCoinflip`, `DegenerusGameLootboxModule`, `DegenerusGameDecimatorModule`. The
BURNIE/redemption surface was already exhaustively covered by the 389–394 dual-net and the
BURNIE-04 fix-design workflows. CI-resume command + per-target notes are in
`CAMPAIGN-REPORT-v63.md` (§CI resume). Any GENUINE survivor they produce on resume will be
triaged into `SURVIVOR-TRIAGE-v63.md` and dispositioned here.

---

## Byte-freeze attestation

- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY.
- `forge test --match-path test/mutation/MutationKills.t.sol` — 8 passed, 0 failed, on the clean
  subject.

**contracts/ byte-identical to `a8b702a7`. Zero contract defects routed.**
