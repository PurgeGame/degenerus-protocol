---
phase: 318-tst-subscription-crank-correctness-removal-proofs-tst
plan: 06
subsystem: testing
tags: [foundry, jgas-03, daily-eth-jackpot, single-call, 305-winner-ceiling, conservation, gas-worst-case, split-removal, grep-clean-attestation, harness-module]

# Dependency graph
requires:
  - phase: 318-01
    provides: "AfKing-aware DeployProtocol fixture (this plan does NOT use DeployProtocol — it drives the JackpotModule directly via a module-extending harness — but the fixture repair unblocked the phase's compile baseline)"
  - phase: 317-05
    provides: "JGAS-02 single-call _processDailyEth (split removed); the preserved 305 ceiling / 63_600 max scale / 159+95+50+1 bucket geometry; the 2-arg _addClaimableEth deterministic credit; the STAGE_JACKPOT_ETH_RESUME + resumeEthPool deletion"
provides:
  - "JGAS-03 correctness: the daily-ETH jackpot pays all 305 winners (buckets 159/95/50/1 at max scale) in ONE runTerminalJackpot call — exactly 305 JackpotEthWin emissions, each non-solo bucket's summed claimable == its unit-rounded share (perWinner*count), the solo bucket through the 75/25 whale-pass split"
  - "JGAS-03 conservation: total ETH that left the distributable pool (sum of per-winner claimable credits + the solo whale-pass spend routed to futurePrizePool) == the returned paidWei, paidWei <= pool (no leak, no overpay); claimablePool liability == the summed per-winner claimable"
  - "JGAS-03 gas-fits (worst-case-FIRST): the 305-winner max-scale single call IS the daily-ETH worst case (DAILY_ETH_MAX_WINNERS=305 hard cap, MAX_BUCKET_WINNERS=250 never clips a 159 bucket); measured 7,503,715 gas < the mainnet 30M block gas limit (~25%, ~22.5M margin)"
  - "JGAS-03 split behaviorally gone: the single call fully resolves (paidWei + in-bucket rounding dust == pool, no resume carry); STAGE_JACKPOT_ETH_RESUME absent from the AdvanceModule; the 7-symbol split kill set + splitMode are grep-clean (zero non-comment matches) across JackpotModule + AdvanceModule"
  - "JGAS-03 preserved ceiling: DAILY_ETH_MAX_WINNERS=305 and DAILY_JACKPOT_SCALE_MAX_BPS=63_600 byte-present in the JackpotModule (split removal changed routing only, not amounts/winner-counts)"
affects: [319, 320, jgas-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Module-extending harness: extend the production DegenerusGameJackpotModule directly so the inherited (external) runTerminalJackpot executes the live _processDailyEth -> _processBucket -> _addClaimableEth path in the harness's own storage — no delegatecall plumbing, no nested-array vm.store; the harness adds ONLY a traitBurnTicket seeder + read-only views, overrides no production logic"
    - "runTerminalJackpot as the 305-ceiling driver: the external runTerminalJackpot at poolWei >= 200 ETH feeds _processDailyEth the full max-scale bucket geometry (159/95/50/1) in one call — the cleanest reachable entry into the single-call surface (msg.sender==GAME guard satisfied via vm.prank(ContractAddresses.GAME))"
    - "Conservation by credit-sink summation: sum every distinct seeded holder's claimable delta + the futurePrizePool whale-pass spend and assert == the paidWei return; disjoint per-bucket address ranges (1e9 spacing) make each credit attributable to one bucket"
    - "Worst-case-FIRST gas (feedback_gas_worst_case): derive the theoretical worst case (305 = the DAILY_ETH_MAX_WINNERS hard cap) BEFORE measuring; assert the single call's gasleft-delta < the mainnet 30M (NOT the test config's inflated 30e9 block_gas_limit)"
    - "Comment-stripping source attestation for the split kill set (mirrors VrfWireOneShot / RngFreezeAndRemovalProofs): vm.readFile + a Solidity line/block-comment stripper so NatSpec prose mentioning a split symbol cannot self-invalidate the grep gate"

key-files:
  created:
    - test/fuzz/JackpotSingleCallCorrectness.t.sol
  modified: []

key-decisions:
  - "Drove the single call via a module-extending harness (JackpotSingleCallHarness) rather than the full DeployProtocol game + delegatecall: runTerminalJackpot is an external delegatecall target whose only blocker is the msg.sender==GAME guard (satisfied by pranking ContractAddresses.GAME); extending the module runs the IDENTICAL _processDailyEth code in the harness's storage, and a seedBucket setter sidesteps the otherwise error-prone vm.store of the nested mapping(uint24 => address[][256]) traitBurnTicket"
  - "Chose runTerminalJackpot (FINAL_DAY_SHARES_PACKED, the 60% solo via rotation) as the 305-ceiling entry over payDailyJackpot: payDailyJackpot's daily path is gated behind jackpotCounter / prize-pool snapshots / day-counter machinery, whereas runTerminalJackpot takes (poolWei, targetLvl, rngWord) directly and routes straight into _processDailyEth at the full DAILY_ETH_MAX_WINNERS ceiling — the cleanest deterministic reach of the worst case"
  - "Fixed VRF word keccak256(\"jgas03-single-call-fixed-word\") chosen so getRandomTraits yields 4 DISTINCT, gold-free trait IDs (45/107/140/239, all color != 7): gold-free means _pickSoloQuadrant takes the deterministic entropy-rotation branch (no deity virtual entries — deityBySymbol is empty in the harness anyway), and distinct IDs let each bucket be seeded on a disjoint address range for unambiguous per-bucket conservation"
  - "Conservation expressed as paidWei == sum(per-winner claimable) + whale-pass-spent(futurePrizePool), with the unit-rounding floor dust (pool - paidWei) returned to the caller's source pool — the solo (remainder) bucket gets pool - distributed, so the only un-paid ETH is the per-non-solo-bucket integer-division floor remainder; the no-resume test asserts paidWei + that derived dust == pool exactly"
  - "Restored ContractAddresses.sol via `git checkout` (NOT the stale restore script): the plan's verify gate runs restoreContractAddresses() which left ContractAddresses.sol dirty (6 address swaps); per the sequential-executor contract-cleanliness rule, git checkout returns the committed foundry-ready file so `git diff --name-only -- contracts/` is empty before commit"

patterns-established:
  - "To exercise a delegatecall-target module function at its full gas/winner ceiling without the full game + delegatecall harness, extend the module directly and prank the GAME address — the guarded external entry then runs the production logic in the test's storage, and a thin seeder writes the nested state the production path reads"

requirements-completed: [JGAS-03]

# Metrics
duration: ~12min
started: 2026-05-23T22:28:00Z
completed: 2026-05-23T22:40:00Z
tasks: 2
files-created: 1
---

# Phase 318 Plan 06: JGAS-03 Single-Call 305-Winner Daily-ETH Jackpot Correctness Summary

**Proved JGAS-03: after the JGAS-02 two-call-split removal, the daily ETH jackpot pays all 305 winners (buckets 159/95/50/1 at the DAILY_JACKPOT_SCALE_MAX_BPS=63_600 max scale) correctly in ONE call — exactly 305 JackpotEthWin emissions, each bucket's exact per-winner amount, none missed/double-paid, total credited (claimable + whale-pass spend) == the distributed pool — the 305-winner worst-case single call measures 7,503,715 gas (well under the 30M mainnet block gas limit), and the split path is behaviorally gone (single call fully resolves, no STAGE_JACKPOT_ETH_RESUME, the 7-symbol split kill set + splitMode grep-clean). 8/8 green; zero contracts/ mutation.**

## Performance

- **Duration:** ~12 min
- **Tasks:** 2 of 2 completed
- **Files created:** 1 (`test/fuzz/JackpotSingleCallCorrectness.t.sol`, 561 lines, 8 tests)
- **Suite:** `forge test --match-contract JackpotSingleCallCorrectness` → **8 passed / 0 failed / 0 skipped** (finished in 1.21s)

## Accomplishments

### Task 1 — 305-winner single-call correctness + conservation

- **`testSingleCallPaysAll305WithConservation`** — at max scale (POOL_WEI = 1000 ETH, well above the 200-ETH `JACKPOT_SCALE_SECOND_WEI` floor) the single `runTerminalJackpot` call emits **exactly 305 `JackpotEthWin` events** (`bucketCountsForPoolCap` pre-checked as the 159/95/50/1 multiset summing to 305). Conservation: `sum(per-winner claimable) + futurePrizePool whale-pass spend == paidWei`, `claimablePool == sum(per-winner claimable)`, `paidWei <= POOL_WEI` (no overpay), `paidWei > 0` (non-vacuous).
- **`testPerBucketExactShareNoDoublePay`** — for each of the 3 non-solo buckets, the summed claimable across that bucket's distinct seeded holders equals `perWinner * count` where `perWinner = share / count` (the contract's unit-rounded `bucketShares` value) — exact amounts, none missed, none over/under-paid. The solo bucket is handled separately (75/25 whale-pass split).
- **`testFuzz_SingleCall305AtMaxScale`** (1000 runs) — for any pool in `[200 ETH, 5200 ETH]` the call pays exactly 305 winners in one call and never overpays the pool.

### Task 2 — single call fits the block gas limit (worst-case-first) + split gone

- **`testWorstCaseSingleCallFitsBlockGasLimit`** — **worst-case-FIRST**: the daily-ETH worst case is the 305-winner max-scale single call (DAILY_ETH_MAX_WINNERS=305 is the hard cap; MAX_BUCKET_WINNERS=250 never clips a 159 bucket). The measured `gasleft`-delta around the single external call is **7,503,715 gas**, asserted `< 30_000_000` (the **mainnet** block gas limit — NOT the test config's inflated `block_gas_limit = 30_000_000_000`). It fits with ~22.5M (≈75%) margin. Full peg calibration + the margin attribution to the removed per-winner `autoRebuyState` SLOAD is **Phase 319 / JGAS-04**; this plan's bar is "fits."
- **`testNoResumeStageSingleCallFullyResolves`** — the single call fully resolves: `paidWei + in-bucket-rounding-dust == POOL_WEI` (the dust is the per-non-solo-bucket integer-division floor remainder; the solo/remainder bucket absorbs `pool - distributed`). There is no second-call carry — no `resumeEthPool` to read/write, no resume stage to enter.
- **`testSplitSymbolsGrepClean`** — the split kill set `{resumeEthPool, SPLIT_CALL1, SPLIT_CALL2, SPLIT_NONE, _resumeDailyEth, STAGE_JACKPOT_ETH_RESUME, call1Bucket}` + `splitMode` returns **ZERO non-comment matches** across `DegenerusGameJackpotModule.sol` + `DegenerusGameAdvanceModule.sol` (comment-stripped so NatSpec prose cannot self-invalidate the gate).
- **`testNoResumeStageConstantInAdvanceModule`** — `STAGE_JACKPOT_ETH_RESUME` is absent from the AdvanceModule; the single-call daily-ETH entry (`payDailyJackpot(`) is still dispatched.
- **`testPreservedCeilingAndScaleConstants`** — `DAILY_ETH_MAX_WINNERS = 305` and `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` are byte-present in the JackpotModule (the split removal changed routing only, not amounts/winner-counts).

## JGAS-03 Assertions (the proof set)

| Property | Test | Assertion |
|----------|------|-----------|
| 305 winners, one call | `testSingleCallPaysAll305WithConservation` | `ethWins == 305` JackpotEthWin emissions |
| 4 buckets paid (159/95/50/1) | same + `_assertCountMultiset` | bucket-count multiset == {159,95,50,1}, sum == 305 |
| Exact per-winner amount, no double-pay | `testPerBucketExactShareNoDoublePay` | each non-solo bucket: `sum(claimable) == perWinner * count` |
| Conservation (sum deltas == pool) | `testSingleCallPaysAll305WithConservation` | `sum(claimable) + whalePassSpend == paidWei`, `paidWei <= pool` |
| Gas fits (worst-case-first) | `testWorstCaseSingleCallFitsBlockGasLimit` | `gasUsed (7,503,715) < 30,000,000` mainnet limit |
| Single call fully resolves (no resume) | `testNoResumeStageSingleCallFullyResolves` | `paidWei + rounding-dust == pool` |
| Split grep-clean | `testSplitSymbolsGrepClean` | 0 matches of 8 split symbols |
| No resume stage constant | `testNoResumeStageConstantInAdvanceModule` | 0 matches `STAGE_JACKPOT_ETH_RESUME` |
| 305 ceiling + scale preserved | `testPreservedCeilingAndScaleConstants` | `DAILY_ETH_MAX_WINNERS = 305`, `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` present |

## Worst-Case Gas Derivation (feedback_gas_worst_case)

Derived the theoretical worst case BEFORE measuring: the daily-ETH path's maximum work is bounded by `DAILY_ETH_MAX_WINNERS = 305` — a hard cap applied via `bucketCountsForPoolCap(..., maxTotal=305, ...)`. The max-scale bucket geometry (159/95/50/1) is the only way to reach all 305 (`scaleBps` pins to `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` for any pool ≥ `JACKPOT_SCALE_SECOND_WEI = 200 ETH`), and `MAX_BUCKET_WINNERS = 250` never clips a 159-winner bucket. So 305 winners across all 4 buckets in one call IS the daily-ETH worst case. Measured: **7,503,715 gas** for the full max-scale single call → fits the 30M mainnet block gas limit with ~22.5M margin. The empirical peg calibration + the per-winner margin attribution is Phase 319 (JGAS-04); this plan's bar — "the single call FITS" — is met.

## Deviations from Plan

None — plan executed exactly as written. Both `tdd="true"` tasks were authored as live-behavior assertions over the already-shipped JGAS-02 single-call surface; the suite passed on first run (the production code under test already exists, so the RED→GREEN cycle collapses to a single GREEN — the behavior the tests assert is the post-317 reality, and any regression would flip them RED).

## Known Stubs

None. The harness adds only a real `traitBurnTicket` seeder + read-only accounting views; no empty-value / placeholder / TODO stubs. All assertions exercise live production logic (`runTerminalJackpot → _processDailyEth → _processBucket → _addClaimableEth`).

## Contract-Cleanliness Note

`git diff --name-only -- contracts/` is EMPTY. The plan's verify gate patches `ContractAddresses.sol` for the foundry build; the trailing `restoreContractAddresses()` left it dirty (6 address swaps), so it was restored via `git checkout -- contracts/ContractAddresses.sol` (NOT the stale restore script), returning the committed foundry-ready file. The only working-tree change is the new owned test file.

## Self-Check: PASSED

- `test/fuzz/JackpotSingleCallCorrectness.t.sol` exists on disk (561 lines, 8 tests).
- `forge test --match-contract JackpotSingleCallCorrectness` → 8 passed / 0 failed / 0 skipped.
- `git diff --name-only -- contracts/` is empty (zero production-contract mutation).
- The new suite is purely additive (a new file) so it introduces zero NEW failures in any other suite; the phase's 44 pre-existing failures (zero AfKing involvement) are unaffected.
- This SUMMARY exists on disk at the plan directory.
