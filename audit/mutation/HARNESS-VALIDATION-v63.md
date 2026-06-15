# Mutation Harness Validation — v63 subject `a8b702a7`

**Subject (byte-frozen):** `a8b702a7` — contracts tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620`. Every contract edit in this note is a
TRANSIENT in-place mutation that is restored before the next step; `git diff a8b702a7 --
contracts/` is EMPTY at the end (see §C). Captured 2026-06-15.

Two demonstrations prove the corrected harness is sound:
- **(A)** the COMPREHENSIVE oracle EXECUTES the mutated code and KILLS an injected
  packing-helper defect — the prior narrow per-file oracle would have let it survive.
- **(B)** the kill-safe restore trap leaves `contracts/` byte-identical to `a8b702a7`
  after an interrupted (SIGINT) run with a mutant on disk.

---

## A. The comprehensive oracle exercises the mutated code (false-survivor collapse)

### A.0 The comprehensive oracle is GREEN at the subject

`bash audit/mutation/oracle-comprehensive.sh` under the bounded per-mutant env
(`FOUNDRY_FUZZ_RUNS=64 FOUNDRY_INVARIANT_RUNS=12 FOUNDRY_INVARIANT_DEPTH=48`, via_ir
inherited from `[profile.default]`):

```
Ran 12 test suites in 1.18s (6.50s CPU time): 113 tests passed, 0 failed, 0 skipped (113 total tests)
```

12/12 suites `ok`, 113/113 tests pass, exit 0. The union (`--match-contract` over the 12
EXERCISED oracle test contracts, `--no-match-contract VRFPath`) selects exactly the 12
intended suites.

### A.1 Injected mutation (a packing-helper masked-RMW defect)

Target: `DegenerusGameStorage._creditAfking` (Group 4 packing helper). It credits the
AFKING (high) half of the packed `balancesPacked[player]` word and MUST shift the value
into the high lane:

```solidity
// subject (correct)
balancesPacked[player] += weiAmount << 128;
// injected mutant (drops the lane shift → the afking credit lands in the CLAIMABLE low half)
balancesPacked[player] += weiAmount;
```

This is a representative masked-RMW/lane-shift defect: it silently corrupts a co-resident
field (the claimable low half), compiles green, and breaks the solvency identity
`claimablePool == Σ(claimable + afking)`.

### A.2 The comprehensive oracle KILLS the mutant

`bash audit/mutation/oracle-comprehensive.sh` against the mutant:

```
Ran 12 test suites in 1.23s: 107 tests passed, 6 failed, 0 skipped (113 total tests)
exit 1  (non-zero ⇒ mutant KILLED)
```

The killing suite is **`V61Pack`** (`test/fuzz/V61Pack.t.sol`), which asserts the exact
per-half round-trip the mutant violates. The named failures:

| Killing test | Asserted property the mutant broke |
|---|---|
| `testCreditAfkingRoundTripLowHalfUntouched` | `high half round-trips to the credited afking: 0 != 256e18` (afking credit landed in the low half) |
| `testCreditClaimableRoundTripHighHalfUntouched` | `seed: afking high half set: 0 != 123e18` |
| `testDebitTouchesCorrectHalfOnly` | `low half debited by exactly claimableUsed (sentinel remains): 3e19 != 1` |
| `testNoCrossHalfCarryAtSupplyBound` | `low half holds the max-realistic claimable exactly: 219e24 != 120e24` (afking bled into the low half) |
| `testGameOverZeroingPreservesInfraAfkingHalf` | `afking accessor still reads the prepaid principal: 0 != 91e18` |
| `testFuzzTwoMappingEquivalence` | packed vs plain-counter equivalence diverges (counterexample produced) |

The mutated line is therefore EXECUTED and the defect CAUGHT — the oracle is not vacuous.

### A.3 Narrow-vs-comprehensive contrast (why this is the fix)

The prior harness ran an ALL-FILES sweep under a NARROW per-file `--match-contract`
oracle, which produced FALSE survivors when the oracle never executed the mutated line:

- **The library helper itself survived under the narrow oracle.** Prior
  `audit/mutation/BitPackingLib.log` records
  `Line 114: 'return (data & ~(mask << shift)) | ((value & mask) << shift)' ==> 'revert()'
  --> UNCAUGHT`, plus a swarm of `MASK_16`/`MASK_24` `[CR]`/`[AOR]` constant-replacement
  survivors — `PROGRESS.log` logs `BitPackingLib DONE uncaught=63`. The narrow oracle
  (`StorageFoundation|V61Pack|PrecisionBoundary` scoped to ONE area) did not drive those
  masked-RMW constants to an asserted divergence.
- **The packing helper's HOME contract was never mutated at all.** `_creditAfking` lives
  in `DegenerusGameStorage`, and the prior campaign ran **0** `DegenerusGameStorage`
  mutation targets (`grep -c 'DegenerusGameStorage (MUTATE_START|DONE)' PROGRESS.log` = 0).
  The entire `balancesPacked` masked-RMW family was outside the prior harness's effective
  reach.

The corrected harness fixes BOTH halves of the mistake: (1) it scopes
`DegenerusGameStorage` (and the other packing helpers) as a NAMED fix-site target, and
(2) it drives every target through the COMPREHENSIVE union that includes `V61Pack` — the
suite that asserts the exact per-half round-trip — so the `_creditAfking` lane-shift
defect is KILLED instead of surviving as a false negative.

**Coverage note (recorded, not a defect):** during validation, two other candidate
mutations did NOT change an asserted value under this oracle — `BitPackingLib.setPacked`
dropping its clear-mask (the StorageFoundation/V61Pack pokes write into freshly-zeroed
words, so `data | x == (data & ~m) | x`), and `_debitClaimableAndAfking` dropping its
afking-leg `<<128` (the `V61Pack`/`SettleClaimableShortfallTester` path exercises the
SEPARATE `_debitClaimable`/`_debitAfking` accessors, not the combined helper). These are
the genuine residual blind spots the campaign is built to QUANTIFY — they are real
candidate survivors for Plan 02 to adjudicate (add an assertion on the combined helper /
on a non-zero-overlap packed write), NOT oracle artifacts. The point of demonstration (A)
is that where the oracle DOES exercise the mutated line, the kill is real; the campaign
then enumerates exactly which target lines the oracle does not yet pin.

---

## B. Restore-trap byte-freeze proof (interrupted run leaves the subject clean)

The runner installs `trap 'restore; ...' EXIT INT TERM` where
`restore() { cd "$REPO" && git checkout -- contracts/ ...; }`. Two interruption tests:

### B.1 SIGINT during a live `--single` run

`run-campaign-v63.sh --single BitPackingLib` was started detached and SIGINT'd. The trap
fired (`PROGRESS-v63.log` shows the `BASELINE_CHECK` then a `TRAP_EXIT`); no `.DONE` was
written, no slither log was produced (the run was cut short), and afterward
`git status --porcelain contracts/` was EMPTY with tree-hash `2934d3d8…`.

### B.2 SIGINT with a REAL mutant on disk (the faithful trap path)

To prove the trap restores even when a mutant is materialized, a mutant was injected
in-place and the SAME trap path (`trap 'restore' EXIT INT TERM`) was interrupted by
SIGINT while the mutant was confirmed on disk:

```
MUTANT_IN_PLACE=M contracts/storage/DegenerusGameStorage.sol
MUTANT_CONFIRMED_ON_DISK            # the un-shifted line 'balancesPacked[player] += weiAmount;' present
SENDING_SELF_SIGINT
TRAP_FIRED_RESTORED                 # the INT/EXIT trap ran `git checkout -- contracts/`
```

Post-interrupt assertion:

```
contracts CLEAN (trap restored the mutant-in-place after SIGINT)
tree-hash OK == 2934d3d8987a09c5f073549a0cb499f6c5f28620
git diff a8b702a7 EMPTY
```

The restore is idempotent (it ran on both INT and EXIT). An interrupted/killed run never
strands a mutant — the subject returns to byte-frozen `a8b702a7`.

---

## C. Byte-freeze attestation

At the end of this validation:

- `git status --porcelain contracts/` — EMPTY.
- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY.

No commit was ever made while a mutant was in place. Every injected mutation in §A/§B was
restored before proceeding.

**contracts/ byte-identical to a8b702a7 after validation.**
