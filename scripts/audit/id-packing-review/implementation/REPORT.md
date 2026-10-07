# ID entry packing implementation

Baseline: `4071c79cc`. Implementation and focused validation are complete.

The four entry layouts are implemented together with batched far-future owed writes. Degenerette resolution advances the queue cursor without writing to bet storage. A transient in-flight cursor blocks callback reentry and makes views hide the processed prefix before the persistent cursor commits; a reverting payment rolls everything back.

| Entry | Compact lane, low bits first | Entries per storage word |
| --- | --- | ---: |
| Degenerette | Account32, symbol5, spins5, currency1, record1, activity16, stake64; four reserved bits | 2 |
| Decimator | Account32, board30, stack66 | 2 |
| BAF | Cumulative weight96, account32 | 2 |
| Craps | Account32, board30, boon3, high7 | 3 |

There is no address-gap expansion in any of these codecs. Degenerette uses its compact lane in resolution, placement events, and public views. Decimator's lens decodes the compact lane and retains its existing decoded return values. Craps uses a derived awarded flag at bit72 in memory, above its compact 72-bit slip. Its independent placement-event format keeps its existing field offsets.

Each Craps storage word carries one uint24 day tag at bits216..239. Dense appends clear a word when writing its first lane, leaving unwritten tails zero. Subsequent appends and amendments preserve neighboring lanes. The full requested day is checked before reading a recycled scheduled word. Jackpot awarded seats derive their status from frozen paid/day boundaries. They retain separate scatter/survival salts, shared dice, and entry-specific rounding.

The far-future range writer keeps the existing eight-level owed encoding and caches one physical word at a time. It preserves per-level generation checks, queue registration order, RNG lock enforcement, saturation, and snap clearing. Crossing a word or wrapping a century flushes/reloads the cache. No empty-word retention optimization is included.

`minerMaintenanceDueAt()` had no production caller and was removed with its dedicated tests and stale mocks. The active miner reward clock is unchanged.

## Gas measurements

The lifecycle harness uses production calls with transaction isolation, Solidity 0.8.34, via-IR, optimizer 1000, and Osaka. The identical harness runs against the saved baseline and candidate. Setup, RNG delivery, and fixture-only window binding are outside the measurement. Intrinsic transaction gas is excluded. `Sample` events retain gross execution gas, the refund counter, charged execution gas after the refund cap, and the number of written slots in the target contract; those slot counts do not include every external callee.

Degenerette measures each placement separately followed by the real `mineFlip()` resolution, for fresh and reused buffers. Craps measures placements, one amendment, and all five ordinary window settlements, then repeats after the 64-day physical-book reuse interval. The daily jackpot construction is measured separately by the existing production keeper harness. Small savings, especially one-ticket Craps, are specific to the measured workload; they are not a claim that every isolated operation becomes cheaper.

Range benchmarks measure complete public award/purchase calls using `snapshotGasLastCall`, including all production queue registrations, rather than measuring a synthetic storage loop. The measured results are below. Negative savings indicate extra gas.

| Measured workload | Baseline | Candidate | Gas saved | Reduction |
| --- | ---: | ---: | ---: | ---: |
| Degenerette: one bet, fresh | 231,442 | 229,400 | 2,042 | 0.88% |
| Degenerette: one bet, reused | 194,008 | 189,166 | 4,842 | 2.50% |
| Degenerette: three bets, fresh | 450,614 | 424,868 | 25,746 | 5.71% |
| Degenerette: three bets, reused | 378,980 | 361,934 | 17,046 | 4.50% |
| Degenerette: 32 bets, fresh | 3,628,946 | 3,249,942 | 379,004 | 10.44% |
| Degenerette: 32 bets, reused | 3,061,412 | 2,866,408 | 195,004 | 6.37% |
| Craps: one day ticket, fresh | 1,934,753 | 1,934,103 | 650 | 0.03% |
| Craps: one day ticket, reused | 1,890,001 | 1,889,375 | 626 | 0.03% |
| Craps: three day tickets, fresh | 2,855,203 | 2,816,763 | 38,440 | 1.35% |
| Craps: three day tickets, reused | 2,665,011 | 2,660,771 | 4,240 | 0.16% |
| Decimator: new pair first entry | 158,501 | 158,752 | -251 | -0.16% |
| Decimator: second entry of pair | 158,501 | 141,652 | 16,849 | 10.63% |
| Decimator: existing entry top-up | 100,870 | 101,420 | -550 | -0.55% |
| Whale claim, 100 levels | 1,613,028 | 1,529,268 | 83,760 | 5.19% |
| Whale top-up, 100 levels | 502,353 | 419,620 | 82,733 | 16.47% |
| Deity purchase, 100 levels | 2,234,858 | 2,107,391 | 127,467 | 5.70% |
| Lazy purchase, 10 levels | 555,940 | 548,399 | 7,541 | 1.36% |
| One half-pass, stride 4 | 684,051 | 664,452 | 19,599 | 2.87% |
| Two half-passes, stride 2 | 992,409 | 948,635 | 43,774 | 4.41% |
| Three half-passes | 1,303,080 | 1,238,913 | 64,167 | 4.92% |
| Seven half-passes | 1,741,202 | 1,599,350 | 141,852 | 8.15% |

The 32-bet reused-buffer resolution itself falls from 503,044 to 391,976 gas. Its Game storage write footprint falls from 35 slots to 3; the dedicated access-recording assertion confirms that none of the remaining writes touch either bet lane. This is cursor-based retirement, with no per-bet processed write.

BAF armed-day deposits cost 208 more gas for the first entry and save 16,892 for the second entry of a pair. The 16/512/4,096-entry search measurements change by -1,205 / -395 / +120 gas respectively (negative means cheaper). See [BAF and Decimator measurements](final-decimator-baf-gas.json).

The regressions are small but real. Reused Craps placements add 507 gas for the first lane and 568 for later lanes; the measured five-window lifecycle recovers that overhead. Decimator top-ups add 550 gas, while creating a pair saves 16,598 before settlement: roughly 30 extra top-ups would consume that creation saving. Sampled Decimator settlement adds about 103,000–117,000 gas across full 1,000-to-1,000,000-original-entry stress fixtures (about 0.1%); the entry-allocation saving is separate and much larger for these populations. Do not quote settlement as a Decimator gas saving. Keeper admission bounds were not reduced.

[Full per-call gas/refund/write-slot data](final-gas-comparison.json), [gas comparison generator](compare.py), [baseline lifecycle log](baseline-lifecycle-final-lifecycle.log), and [final lifecycle log](final-c-lifecycle.log) retain the reproducible detail. The Decimator stress suites exercise sampled settlement and generated entries; the small full-protocol burn fixture measures admission and top-ups separately.


## Deployment sizes

| Contract | Runtime bytes | Headroom below 24,576 |
| --- | ---: | ---: |
| DegenerusGame | 24,423 | 153 |
| CrapsBattle | 24,332 | 244 |
| DegenerusGameWhaleModule | 24,312 | 264 |
| JackpotBattle | 23,093 | 1,483 |
| Coinflip | 22,582 | 1,994 |
| DegenerusGameDegeneretteModule | 21,376 | 3,200 |
| DegenerusGameDecimatorModule | 13,162 | 11,414 |
| CrapsEngine | 9,210 | 15,366 |

All production deployments pass the size gate. Game, CrapsBattle, and the Whale module have limited room for subsequent features; the size gate remains a release requirement. See [all deployment sizes](final-sizes.json).

## Verification and reproduction

`groups.json` lists the focused regression groups. `run.py WORKSPACE LABEL GROUP...` runs them sequentially in an explicit isolated source copy. Each copy includes the production contracts/tests, the production compiler settings with `src`/`test` restricted to `bench`, and symlinks to the repository's installed libraries. It patches Foundry deployment addresses inside the copy only. The checked-in deployment pins are unchanged. Saved text logs have terminal colors and trailing whitespace removed; test results and measurements are unchanged.

The baseline path and source hashes are in `workspace.txt` and `baseline.json`. Final snapshots are listed in `final-*-workspace.txt`; `final-contract-hashes.json` records the reviewed production sources. Snapshot production sources match the workspace except for the intentionally patched deployment pins. Interim `candidate*` logs are retained locally as development history; the commit includes the final acceptance evidence.

Coverage includes sibling-lane fuzzing, cursor-only storage-write assertions, malicious payment callbacks, payout rollback, partial/resumed resolution, compact-versus-frozen-legacy Craps engine parity, generation reuse, forged days, duplicate awarded recipients, full-width account IDs, range-write differential fuzzing, keeper bounds, RNG/terminal composition, and the wallet-ID invariant.

All final groups pass: **887 distinct tests**, 1007 test executions including repeated suites, 46 fuzz properties with 1,000 runs each, and the 256-run × 128-depth wallet-ID invariant. The final check is [recorded here](final-verification.json).

| Final group | Passing tests |
| --- | ---: |
| [degenerette](final-a-degenerette.log) | 127 |
| [packing](final-a-packing.log) | 7 |
| [degenerette-extra](final-a-degenerette-extra.log) | 84 |
| [composition](final-b-composition.log) | 150 |
| [rng-terminal](final-b-rng-terminal.log) | 22 |
| [wallet-invariant](final-b-wallet-invariant.log) | 15 |
| [decimator-baf](final-c-decimator-baf.log) | 97 |
| [range](final-c-range.log) | 32 |
| [lifecycle](final-c-lifecycle.log) | 14 |
| [craps](final-d-craps.log) | 262 |
| [craps-compact](final-d-craps-compact.log) | 197 |

All nine static gates pass: write owners, unchecked arithmetic, RNG taint/window, pool writes, advance calls, gas reads, interface coverage, and delegatecall alignment. The declared-storage oracle matches every golden and both delegate contexts. The fresh production build and every deployment-size check pass. `git diff --check` passes. No keeper gas admission bounds or payout expectations were relaxed. The checkpoint test's gas fixture was adjusted to retain one 50-entry draw group per call after packing made each group cheaper.

These are focused implementation gates, not a rerun of every unrelated repository test. Earlier snapshot failures from old test decoders, stale deployment pins, isolation-sensitive fixtures, and the superseded checkpoint gas fixture are retained locally as development history; the final named groups above are the acceptance evidence.

## Deployment compatibility

This is a fresh-deployment change. Existing populated mappings cannot be upgraded in place: physical keys and lane meanings changed even though declared storage roots remain fixed. Degenerette event/view decoders and direct Craps engine callers must use the documented compact layouts. Public function/event signatures are retained except for the intentionally removed unused maintenance view.
