# RNG and gas review since the last push — 2026-09-20

> Historical review of the pre-cleanup sources. The 2026-09-21 seed cleanup removes
> the payout amount from jackpot winner seeds and converts the terminal witness
> into `test_KnownDailyWordAffiliateDeductionPreservesWinners`. The recipient-reroll
> finding below is superseded; the allocation timing exception remains. These gas,
> size and test results belong to the older sources, not the current snapshot.
> See `RNG-DOMAINS.md` and `../VERIFICATION.md` for the current handoff.

## Scope and conclusion

Compared the fetched `origin/main` (`8330d94dbfd0cb946131f39cc90c56ee2784cdda`)
with local HEAD (`1a4d06d08aa1c5e2a15575039dd66e9c8cc1e0b3`), including the
pre-existing working-tree changes in `KNOWN-ISSUES.md`,
`test/fuzz/TerminalAffiliatePayout.t.sol` and `test/gas/AdvanceColdTransactions.t.sol`.
The range contains 26 commits. Reviewed executable Solidity changes separately
from the large comment/NatSpec changes.

The gas checks passed. An unconditional RNG clearance is **not** justified:
the disclosed terminal affiliate/known-word window is reproducible and changes
the selected jackpot recipients. This is already disclosed in the working tree;
it is not an additional finding beyond that disclosure. Its affiliate payout
mechanism was introduced after the pushed baseline.

No production contracts or gas caps were changed by this review. Added a
production-path witness in `test/repro/TerminalAffiliateKnownWord.t.sol`.

## [MEDIUM — already disclosed] A public daily word can precede the terminal affiliate latch

**Location:**

- `contracts/modules/DegenerusGameAdvanceModule.sol:952`: `_handleGameOverPath`,
  affiliate latch; line 1831, `_gameOverEntropy`, delivered-word reuse.
- `contracts/modules/DegenerusGameGameOverModule.sol:249`: `handleGameOverDrain`,
  optional 2% affiliate allocation.
- `contracts/modules/DegenerusGameJackpotModule.sol:1509`: `_processDailyEth`,
  the per-bucket ETH share is included in winner-selection entropy.

**Description:** The new latch protects a terminal request made after the latch.
It does not retroactively freeze affiliate inputs for a previously delivered
ordinary daily word that the terminal path reuses. An empty affiliate board can
be populated by claiming already-accrued referral credit before the first terminal
advance. The resulting 2% deduction changes both the pool and the selection seed.

**Attack scenario:**

1. The game requests an ordinary daily word on its last permitted purchase day.
2. VRF delivers the word, making it public, but nobody advances to consume it.
3. The 14-day grace expires. The game is terminal, with an empty leaderboard at
   the terminal ticket level and existing unclaimed affiliate credit.
4. A caller can simulate terminal settlement with and without the permissionless
   affiliate claim, and choose whether to submit the claim before advancing.

**Impact:** A conditional two-outcome choice over terminal jackpot recipients
using an already-public word. The witness changes a 100 ETH ticket jackpot into
a 98 ETH ticket jackpot plus a 2 ETH affiliate award, and verifies that the
ordered recipient addresses differ. This does not establish arbitrary winner
selection or a live-game VRF exploit. The long inactivity window, empty board and
unclaimed referral credit are material prerequisites.

**Proof of concept:**
`TerminalAffiliateKnownWordTest.test_KnownDailyWordCanPrecedeTerminalAffiliateChoice`.
Only the initial mature-game state and accrued referral credit are seeded. The
request, coordinator callback, permissionless claim, bounded terminal advances
and payouts execute production code. Two branches start from the same snapshot
after fulfillment. The test verifies the same request ID/word in both branches,
100 ETH versus 98 ETH terminal calls, the affiliate credit, and different emitted
winner addresses. A passing result is a witness of this behavior, not a fix.

**Recommendation:** If this exception is to be closed, either commit the relevant
affiliate input before every request whose word may later be reused at termination,
or obtain fresh terminal entropy after the terminal latch. The latter requires
careful handling of pending ticket/lootbox commitments and fallback liveness.
Retaining the current behavior requires retaining this explicit RNG exception.

**Gas impact:** No production change proposed or measured as part of this finding.

## Gas evidence

Solc 0.8.34, optimizer 1,000 runs, via IR, Osaka; Foundry
`1.6.0-nightly`, commit `c07d504b4ae67754584f4e05ff0c547a43c50f7b`;
Node `v24.18.0`. Measurements below are emitted call measurements, not the
outer test's total gas including its setup. Cold transaction figures include
21,064 intrinsic gas where identified by the fixture.

| Path | Gas measured | Evidence |
| --- | ---: | --- |
| Cold century consolidation with rolled-back 365-day vault claim | 13,197,627 | `AdvanceCenturyVaultHistoryFailed` |
| Cold terminal payout, fresh word and all deity refunds | 10,419,714 | `AdvanceColdTerminalFresh` |
| Cold terminal payout, recorded word and all deity refunds | 10,331,026 | `AdvanceColdTerminalRecorded` |
| Cold full subscriber eviction chunk | 10,336,645 | `AdvanceColdEvictions` |
| Cold daily ticket stage, 96 ticket awards and 58 FLIP awards | 7,939,460 | `DailyTicketStageGas` |
| Cold carryover stage, 96 distinct ticket recipients | 5,871,232 | `CarryoverTicketStageGas` |
| Daily RNG settlement with six maximum-depth boon searches | 1,794,760 | `ProtocolBoonAdvanceGasTest` |
| Incremental automatic 100-pass sDGNRS purchase | 1,907,403 | `SdgnrsWhaleBuyStageGas`; below its 2,380,000 charged-weight allowance |
| Cold genesis initialization of both protocol deities | 16,378,197 | `DeityGenesisBatchGasTest`; initialization, not an advance |

The largest measured cold advance has 1,802,373 gas of headroom below the
15,000,000 review target and 3,579,589 below the
[EIP-7825 transaction limit](https://eips.ethereum.org/EIPS/eip-7825) of 16,777,216.
Genesis initialization has only 399,019 gas of headroom below that transaction
limit. Its fixture executes the initialization with an explicit capped call.
These are measured stress cases, not a mathematical maximum over all states.

Checked bounded ticket drains and O(1) packed queue release, separate purchase,
early-bird and carryover stages, subscriber/whale shared work budgeting,
120-day gap handling, maximum-depth boon searches, terminal refund composition,
and nested vault settlement. No test gas cap was raised.

## Verification results

| Check | Passed | Failed after reruns | Skipped/pending |
| --- | ---: | ---: | ---: |
| All Foundry gas suites | 149 | 0 | 13 |
| RNG, freeze, queues, boons, sampling and stall suites, first group | 228 | 0 | 1 |
| RNG, VRF, automatic actions and terminal suites, second group | 157 | 0 | 23 |
| Relevant reproduction and craps suites, including the new witness | 87 | 0 | 0 |
| Stateful RNG/queue/craps invariants and their imported tests | 41 | 0 | 0 |
| Full default Hardhat suite, including the successful rerun of two environment failures | 1,658 | 0 | 23 |

The Foundry groups total **662 passing test executions and 37 skips**. Fuzz tests
used the configured 1,000 runs and `0xdeadbeef` seed; stateful invariants used
256 runs at depth 128. The invariant selection was `RngWindowFreeze`,
`RngIndexDrainOrdering`, `CrapsRngSeal`, `VRFPathInvariants` and `TicketQueue`;
their non-vacuity checks passed. Existing skips include obsolete synthetic-state
fixtures and superseded paths; they are not evidence of passing coverage.

The initial full Hardhat run had 1,656 passes, 23 pending and two failures:
the isolated archive lacked Git metadata required by source-identity assertions.
After restoring that metadata, the complete affected test file and
`JackpotCompAdvanceGas.test.js` passed, 10/10. A missing `forge-std/src` link in
that isolated copy was also repaired. The repeated comp-mode advance measured
2,201,013 transaction gas. The new Foundry witness initially assumed a one-call
terminal settlement; after accounting for the bounded drain calls, all 87 tests
in its group passed. No contract changes or relaxed assertions resolved these
harness issues.

All 11 source/interface gates passed: delegatecall alignment, raw selectors,
RNG windows, RNG taint, advance external calls, unchecked blocks, shared-storage
writers, pool writes, array deletion/packed queue operations, gas-independent
drains, and interface coverage. In particular, the registries match all 91
VRF-word accesses, 237 taint sites and 223 external-call sites. These gates check
inventory and structure; they do not prove semantic RNG safety on their own.

All 27 storage-layout goldens and delegatecall shared-slot checks passed. The
reviewed artifacts' source hashes matched the tested source. The closest runtime
bytecode margins in the Foundry address configuration were:

| Contract | Runtime bytes | Remaining below 24,576 bytes |
| --- | ---: | ---: |
| Mint module | 24,546 | 30 |
| Advance module | 24,458 | 118 |
| Game | 24,220 | 356 |
| CrapsBattle | 23,993 | 583 |
| Jackpot module | 23,694 | 882 |

The Hardhat deployment tests also ran with contract-size enforcement enabled.
These sizes are specific to the tested compiler settings and address pins;
Mint and Advance have very little room for further code growth.

Raw logs, the exact selected-file manifests, the grouped Foundry runner and
artifact checks are retained locally in `/tmp/degenerus-rng-gas-review/`:
`gas.log`, `rng-first.log`, `rng-second.log`, `repro-craps-final.log`,
`rng-invariants.log`, `hardhat.log`, `hardhat-rerun.log`, `gates-final.log`,
`interfaces.log`, `layout.log`, `*-files.txt`, `run-rng.py` and
`artifact-review.json`. Foundry used `scripts/lib/patchForFoundry.js` and skipped
unselected Solidity test sources to keep compilation bounded. Hardhat ran in
an isolated copy so its address rewriting could not interfere with Foundry.
The original working-tree address file was restored byte-for-byte afterward.

## Review coverage and limits

Traced request/fulfill/use boundaries, retries, day clamps and stall recovery;
ordinary and far-future ticket commitments; packed queue owner/index isolation;
sampler full-word and padded-tail behavior; frozen budgets across split payouts;
protocol boon entry-day closure and domain separation; tomorrow-only foil
resolution; automatic decimator and whale actions; craps donation/arm gates;
and terminal cohort/affiliate ordering.

The new sampler intentionally groups draws from the same packed word. Equal
marginal selection probability does not mean independent winners or unchanged
variance compared with the pushed implementation.

This is a source review plus targeted Foundry tests, stateful invariants and the
full default Hardhat suite. It is not a whole-tree Foundry run, a new symbolic
proof, or a guarantee about every reachable state. Existing skipped tests are
reported separately and are not counted as passes. Existing scheduled-resolution,
VRF retry, terminal fallback and lootbox-boon timing assumptions in
`KNOWN-ISSUES.md` remain relevant.
