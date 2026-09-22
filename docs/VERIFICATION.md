# Build and verification

## Reproduce in a clean checkout

Use the lockfiles, pinned compiler configuration and submodules. CI pins Node 20
(`.github/workflows/ci.yml`); local recorded evidence ran on Node 24.18.0. Record
`node --version`, `forge --version` and `git rev-parse HEAD` with results. Verify the
snapshot hashes first, before anything patches addresses. The submodule step fetches
`lib/forge-std` from GitHub at the revision pinned in `foundry.lock`.

```sh
sha256sum -c docs/audit/source-sha256.txt
npm ci
git submodule update --init --recursive
```

Both test fixtures rewrite `contracts/ContractAddresses.sol`. The grouped Foundry
runner saves the exact original bytes and restores them in `finally`, including on
failure or Ctrl-C. Hardhat still requires a disposable checkout. Do not run both
runners against the same source directory or overwrite another runner's pins.

### Foundry

The full test tree exceeds the practical memory budget of a single compilation.
The committed runner discovers all Solidity tests, rejects unassigned test files,
and runs seven bounded compile units with a separate Foundry cache. Helper sources
remain available to every group. It preserves the configured 1,000 fuzz runs and
256 invariant runs at depth 128; splitting compilation does not lower those limits.

```sh
make test-foundry
# Inspect or select compile groups:
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-foundry-groups.py --group integration-gas
# A focused compile rather than just a post-compilation test filter:
python3 scripts/test-foundry-groups.py --file test/repro/TerminalAffiliateKnownWord.t.sol
```

Raw logs and exact file lists default to `.audit-test-logs/foundry`; `summary.json`
records each exit code and result. `--log-dir` changes the evidence directory.
Unknown options are forwarded to `forge test`. CI uses the same grouped runner.

### Hardhat

```sh
make test-hardhat
npm run test:stat
git checkout -- contracts/ContractAddresses.sol
```

`make test-hardhat` runs the eleven `check-*` gates and then `npx hardhat test` over the
whole tree; that is the figure in the evidence table. `npm test` runs only the
unit/integration/deploy/access/edge globs plus three gas files and reports fewer tests.
`npm run test:stat` needs `python3` on PATH: two of its suites spawn
`scripts/data/derive_5_tables.py` (stdlib-only) as the canonical generator of the
Degenerette payout constants. Its two expected reds are the `v36.0 SURF-01..04` protected-range
byte-identical baseline check and `STAT-03` (empty-bucket skip rate); both are accepted.

### Static analysis

Slither 0.11.5 and Aderyn 0.6.8 produced the evidence rows. Compile with Hardhat first so
Slither reuses that build:

```sh
pip install slither-analyzer==0.11.5
npx hardhat compile
npm run slither      # slither . --filter-paths 'node_modules|mocks' --exclude naming-convention,solc-version,low-level-calls,assembly,too-many-digits,similar-names,dead-code
cargo install aderyn   # or: npm install -g @cyfrin/aderyn
aderyn . -o aderyn-report.md
```

The current local Slither run explicitly selected `--compile-force-framework hardhat
--ignore-compile` after compilation; this avoids auto-selecting Foundry without its
required build-info output.

CI runs Slither through `crytic/slither-action` with `--exclude-informational
--exclude-optimization` and Aderyn with the same `aderyn . -o aderyn-report.md`; the evidence
row counts come from `npm run slither` with the flags above.

### Size table

```sh
forge build --skip test
node scripts/check-deployment-sizes.js
```

The size gate reads the exact `DEPLOY_ORDER` name map plus `DegenerusVaultShare`,
rejects missing/unlinked bytecode and stale source hashes, and requires every
runtime to fit 24,576 bytes. It does not classify deployments by test-helper name
suffixes. Build failures are fatal. `FOUNDRY_OUT` or a positional artifact directory
selects a nondefault output. Address pins affect optimizer output; check the actual
deployment pins as well as each test fixture.

## Structural and gas checks

```sh
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-gasleft
bash scripts/layout/storage_layout_oracle.sh
```

Inspect the runtime sizes for EVERY deployment entry, with actual deployment pins as
well as test pins; require <=24,576 bytes. `forge build --sizes` also reports test/utility
artifacts when included, so identify deployable code explicitly. Verify the engine pin
has code and is appended without shifting earlier addresses. Check initcode/deployment
gas independently of runtime size.

Use the `CrapsGasTest`, `CrapsKeeperBudgetGasTest`, `RoundDrainChunkGas` and
`test/gas/Advance*Gas` suites for reachable worst cases. Include finalizing seats, cold state and combined
advance calls. Test gas caps must not be raised simply to make a regression pass.

## Current evidence — 2026-09-22, single-symbol degenerette and century-recycle revision

The source is the committed revision `c374bfae8afe235f34ba57bc5ae04fb5deb7afba`. Commits after it
touch only `docs/`, so every hash and every run below describes this tree. It carries six
changes on top of the reveal and incinerator revision below.

`WWXRP.setTrustedMinter(address, bool)` lets the vault owner (more than 50.1% of DGVE) register
or revoke any address as a WWXRP minter and burner alongside the pinned game contracts, with no
cap, by design and as disclosed; one mapping is appended at WWXRP slot 9.

The decimator's activity multiplier now covers a player's first 500,000 FLIP of base burn at a
level (was: until 200,000 FLIP of multiplied weight), tracked in the free bits of the existing
per-level record. Two things moved at once, so the effect is larger than the cap ratio alone:
because the cap now measures base rather than weight, bonus weight above base at maximum
activity rises from 87,848 to 391,650 FLIP (106,538 to 569,950 on day one). The same commit
raises `SDGNRS_DECIMATOR_CAP` in `FLIP.sol` from 150,000 to 500,000 FLIP, so the sDGNRS auto
entry is now entirely multiplied and spends up to 3.33x more backing per opening.

Degenerette moves to single-symbol tickets: the player picks one hero symbol, everything else is
generated fresh from committed domain-separated draws, colors score independently, gold-on-gold
matches add 25% each, and one shared payout table (0.5x to 100,000x) replaces the eight
per-gold-count tables and the separate WWXRP rig family; the module shrinks by roughly a third.
The trait packer's colors become uniform 1/8 (gold was 1/15), and the WWXRP reel rig drops to a
5% gate. Return targets: FLIP equals the activity curve exactly, ETH adds five points, WWXRP
runs 70% to 130% with the surplus on scores 6-9, all reproduced by
`scripts/data/degenerette_single_symbol_math.py`.

The century incinerator now pays only against a book whose flip actually lost. It reads the
armed BAF day's stored result rather than assuming the transition word's low bit, because a VRF
stall can resolve the armed day from a backfilled derived word while the transition keeps a
later day's, leaving the two independent. A day that won, or never resolved, funds nothing.

And sDGNRS recycles: at the transition close after levels 100, 200 and so on, a random 25-75%
of the supply decrease since the previous such close is minted back into the Whale, Affiliate,
Lootbox and Reward pools in a 1:3:2:1 split, with Lootbox taking the allocation dust. The whole
percentage is drawn from the committed transition word under a mechanism- and level-specific
domain, so the burn delta sizes the mint but never selects the roll, and a completed century
cannot be rerolled. No backing moves, so a refill of fraction `r` after a century that burned
fraction `b` reduces each surviving token's share of the reserves by `r*b / (1 - b + r*b)`; at
50% burned that is 20%, 33.3% or 42.9% for a 25%, 50% or 75% refill. This is disclosed in
`ECONOMIC_DISCLOSURES.md`, mapped in [the RNG domain map](audit/RNG-DOMAINS.md) and analysed in
[the recycling note](audit/SDGNRS-CENTURY-RECYCLE-2026-09-22.md) as amended by
[the random-refill verification](audit/SDGNRS-CENTURY-RANDOM-2026-09-22.md). Three fields are
appended at sDGNRS slot 8 and recycling closes permanently at game over. Both the GAME-only
entry point `recycleCentury(uint24,uint256)` and the `CenturyRecycled` event change shape, so
each carries a new selector and topic0 rather than changing meaning silently. The same work adds
the two view-only ticket-lens search helpers.

No separate intermediate chain is supplied for `d3ddb0c0`; see the last row of the table.

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep at this revision | 2,711 passed, 0 failed, 104 skipped, run in a detached worktree at this exact revision with its own Foundry cache; all seven groups exit 0. Up 50 tests on the revision below (the single-symbol Degenerette, ticket-lens, entry-reveal, trusted-minter, century-recycle and random-refill suites). The one added skip is `LootboxNestedDgnrsOrdering`, which is LOST COVERAGE rather than a retirement — see KNOWN-ISSUES.md |
| Per-test gas, reveal/incinerator revision vs this revision, same fixture pins | 918 entries changed and 757 fixed-gas tests moved against the revision below, dominated by the Degenerette rewrite. The largest single line is the newly skipped nested-DGNRS ordering fixture (3,714,661 -> 0, i.e. not run). Among tests that still execute, the largest are `KeeperFaucetResistance:testReResolveResolvedBetRevertsNoSecondReward` +57.3% (196,806 -> 309,533, whose harness changed in this delta) and `DegeneretteFreezeResolutionTest:testResolveBatchTrailingAlreadyResolvedSkipped` -52.7% (636,018 -> 300,847) (`gas-delta-per-test.txt`) |
| Hardhat `make test-hardhat` | 1,659 passing, 22 pending, 0 failing — identical to the revision below |
| Hardhat `npm run test:stat` | 157 passing, 19 pending, 2 failing: the same two pre-disclosed reds, the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`. Nothing new is red. The passing count falls from 191 because the rewrite collapsed thirteen payout tables (eight honest (N, heroIsGold) plus five rigged WWXRP) into one shared table, so the per-N loops in `DegenerettePerNEvExactness`, `DegeneretteProducerChi2`, `DegeneretteBonusEv` and `DegeneretteV73Invariants` no longer parameterize; no stat file was deleted and declared `it()` blocks fall 24 -> 13 across those four |
| Eleven `make check-*` gates and the storage layout oracle | all pass; judged by exit code, including `check-rng-taint` after the `_rollSingleBoxBoons` manifest row was corrected back to `nonceBase = 0`. The oracle matches every golden and reports delegatecall shared-slot consistency between the modules and the Game |
| EIP-170 runtime size, checked-in pins | `DegenerusGameMintModule` 24,538 (38 spare), `DegenerusGameAdvanceModule` 24,518 (58 spare), `CrapsBattle` 24,331 (245 spare), `DegenerusGame` 24,192 (384 spare); all 32 entries fit. The advance module spent 120 bytes of headroom in this revision (was 24,398 / 178 spare) on the century-recycle hook and the refill word |
| EIP-170 runtime size, Hardhat-style fixture pins | `DegenerusGameMintModule` 24,543 (33 spare), `DegenerusGameAdvanceModule` 24,535 (41 spare), `CrapsBattle` 24,399 (177 spare), `DegenerusGame` 24,197 (379 spare); all 32 entries fit |
| Slither 0.11.5, same flags as below | 3,752 results over 185 contracts with 95 detectors: 202 High, 520 Medium, 556 Low, 2,418 Informational, 56 Optimization (exit 255 is Slither's normal found-issues status). High composition is unchanged except `uninitialized-state` 153 -> 155; both new rows (`DegenerusGameStorage.prizePoolFrozen`, `ticketQueue`) are the standing delegatecall-storage false-positive class — the Game writes them, the modules read them through the shared layout. 18 new entries, 167 gone; the Informational fall of 156 tracks the Degenerette module shrinking by roughly a third (`slither-delta-vs-reveal-incinerator-run.txt`) |
| Aderyn 0.6.8 | 10 High and 23 Low categories, 2,414 instances (41 fewer than the revision below, tracking the removed payout tables); no new category |
| Intermediate chain at `d3ddb0c0` | Not produced, and no such archive exists. The revision has advanced four commits past `d3ddb0c0` (single-symbol Degenerette, the incinerator armed-day guard, the century recycle and the random refill), so a chain at that midpoint would describe no shipped state; this revision's chain covers the whole tree instead. The 2026-09-21 and 2026-09-22 archives below remain supplied |

## Evidence — 2026-09-22, reveal and incinerator revision (base of the revision above)

The source is the committed revision `72325bd6404565308ed0adf1c90c214dcff7d930`, the merge of two changes on top
of the craps extsload revision below. First, the ticket drain's `RoundTraitsGenerated` is
replaced by the anonymous four-topic `EntryTraitsRevealed` (each topic `(level << 160) |
player`, one data word of sixteen trait bytes and their presence bits, two logs per
eight-seat round), and `ticketGenerationStartBlock[level]` is appended at slot 70 so an
indexer can bound the block range it scans per level; the round's work charge rises from
37 to 38 units. Second, the x00 century incinerator pays 10% of the FLIP the armed BAF
day's direct depositors burned and lost, as flip credit through WWXRP, instead of 25% of
the would-be BAF pool in ETH; the advance module shrinks by 160 bytes because the credit
moved into WWXRP and the crank no longer decodes a return value. The duplicate mint-layout
comment in the game facade is removed. Raw runs are in
[the supplementary archive](audit/evidence-2026-09-22-reveal-incinerator.tar.gz).

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep at this revision | 2,661 passed, 0 failed, 103 skipped, run in a detached worktree at this exact revision (7 new tests: the entry-reveal gas/parity suite and the generation-window cases) |
| Per-test gas, craps extsload revision vs this revision, same fixture pins | 389 fixed-gas tests moved, the largest by 5.5% on the driven century incinerator test (its armed day now carries a funded book) and otherwise within ±2.1%; drain-heavy tests fell up to 1.7% from the removed owner loop, purchase-heavy tests rose from the round's extra unit (`gas-delta-per-test.txt`) |
| Hardhat `make test-hardhat` | 1,659 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| EIP-170 runtime size, checked-in pins | `DegenerusGameMintModule` 24,538 (38 spare), `DegenerusGameAdvanceModule` 24,398 (178 spare), `CrapsBattle` 24,331 (245 spare), `DegenerusGame` 24,220 (356 spare); all 32 entries fit |
| EIP-170 runtime size, Hardhat-style fixture pins | `DegenerusGameMintModule` 24,543 (33 spare), `DegenerusGameAdvanceModule` 24,415 (161 spare), `CrapsBattle` 24,399 (177 spare), `DegenerusGame` 24,225 (351 spare); all 32 entries fit |
| Slither 0.11.5, same flags as below | 3,901 results over 183 contracts: 200 High, 517 Medium, 554 Low, 2,574 Informational, 56 Optimization; High composition identical to the extsload run. Attributable new entries: Medium `unused-return` (the advance crank deliberately omits the incinerator's return decode), Medium `uninitialized-local` in the foil round worker, Low `reentrancy-events` on `WWXRP.resolveIncinerator` (event after the flip credit), and 14 Informational `unused-state` rows for `ticketGenerationStartBlock` (written by the game, read only via `extsload`); the remainder are re-keyed counterparts (`slither-delta-vs-event-index-run.txt`) |
| Aderyn 0.6.8 | 10 High and 23 Low categories, 2,455 instances (+6 in the literal categories from the new constants, one fewer uninitialized-local); no new category |

## Evidence — 2026-09-22, craps extsload revision (base of the revision above)

The source is the committed revision `6d02e4bfa25157987159eee225e7c3673a384fd1`. It differs from the
event-index revision below by one view function: `CrapsBattle.extsload(bytes32)`, the
raw-slot reader `DegenerusGame` already exposes, so craps lens/viewer contracts and client
replay can read table state through `eth_call` without touching the contract again. It adds
no storage, no event and no runtime gas on any existing path; it adds 42 bytes of runtime.
The self-imposed headroom rail in `test/craps/CrapsGas.t.sol` moved from 24,300 to 24,400
bytes because it was calibrated to an older build; the EIP-170 limit is unchanged. Raw runs
are in [the supplementary archive](audit/evidence-2026-09-22-craps-extsload.tar.gz).

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep at this revision | 2,654 passed, 0 failed, 103 skipped, run in a detached worktree at this exact revision with its own build cache; the invariant that tripped its non-vacuity guard under the default seed on the two prior trees passed here |
| Per-test gas, event-index revision vs this revision, same fixture pins | +22 gas per external `CrapsBattle` call (one more selector compare in the dispatcher): 812 tests moved, 755 of them exact multiples of 22; largest +1.34% on a craps draw-rate test making thousands of table calls; 4 tests fell, at most 57,538 gas in tests that deploy a module (`gas-delta-per-test.txt`) |
| Hardhat `make test-hardhat` | 1,659 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| EIP-170 runtime size, checked-in pins | `DegenerusGameAdvanceModule` 24,543 (33 spare), `DegenerusGameMintModule` 24,538 (38 spare), `CrapsBattle` 24,331 (245 spare), `DegenerusGame` 24,220 (356 spare); all 32 entries fit |
| EIP-170 runtime size, Hardhat-style fixture pins | `DegenerusGameAdvanceModule` 24,560 (16 spare), `DegenerusGameMintModule` 24,543 (33 spare), `CrapsBattle` 24,399 (177 spare), `DegenerusGame` 24,225 (351 spare); all 32 entries fit |
| Slither 0.11.5, same flags as below | 3,889 results over 183 contracts: 200 High, 517 Medium, 555 Low, 2,561 Informational, 56 Optimization; High and Medium sets identical to the event-index run; the one new entry is Informational `missing-inheritance` (`CrapsBattle` now matches the slot-reader interface shape through `extsload`); 33 further Low/Medium/High entries re-keyed with cancelling counterparts in the same functions (`slither-delta-vs-event-index-run.txt`) |
| Aderyn 0.6.8 | 10 High and 23 Low categories, 2,449 instances; every category and per-category instance count identical to the event-index report |

## Evidence — 2026-09-21, event-index revision (base of the revision above)

The source is the committed revision `91cc40e39bb97ae1ab50e011ff54db92021033d2`. It differs from the
seed-domain snapshot below by one line: `EntryOwnerRegistered.owner` is now an indexed
topic (`contracts/storage/DegenerusGameStorage.sol`), so a wallet's registry positions
resolve from one `eth_getLogs` filter without an off-chain ticket index. The event
signature, and therefore `topic0`, is unchanged; `owner` moves from the second data word
to the third topic. No emit site, storage slot or other event changed. The addendum in
[the readiness review](audit/AUDIT-READINESS-2026-09-21.md) prices the change; raw runs
are in [the supplementary archive](audit/evidence-2026-09-21-event-index.tar.gz).

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep at this revision | 2,652 passed, 0 unresolved failures, 103 skipped; one invariant (`CrapsRealWiringConservation`) tripped its own non-vacuity guard under the runner's default seed on both the base and this revision and passes with seeds `0xdeadbeef` and `0x1` (logs in `invariant-reruns/`) |
| Per-test gas, base revision vs this revision, same fixture pins | +95 gas per owner registration on the canonical path, +104 on the foil-buy path; largest single-test change +0.31%; 14 tests fell by at most 1,600 gas (module deploy size); no test moved for any other reason (`gas-delta-per-test.txt`) |
| Hardhat `make test-hardhat` | 1,659 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| EIP-170 runtime size, checked-in pins | `DegenerusGameAdvanceModule` 24,543 (33 spare), `DegenerusGameMintModule` 24,538 (38 spare), `CrapsBattle` 24,289 (287 spare), `DegenerusGame` 24,220 (356 spare); `DegenerusGameWhaleModule` −90 bytes, `DegenerusGameFoilPackModule` +6, every other registry sink −8; all 32 entries fit |
| EIP-170 runtime size, Hardhat-style fixture pins | `DegenerusGameAdvanceModule` 24,560 (16 spare), `DegenerusGameMintModule` 24,543 (33 spare), `CrapsBattle` 24,357 (219 spare), `DegenerusGame` 24,225 (351 spare); all 32 entries fit; pins reproduced outside the fixture from the default Hardhat signer and mock nonces (`ContractAddresses-hardhat-style.sol` in the supplementary archive) |
| Slither 0.11.5, same flags as below | 3,888 results over 183 contracts: 200 High, 517 Medium, 555 Low, 2,560 Informational, 56 Optimization, identical totals and identical High composition to the seed-domain run; keyed line-insensitively, 8 Low/Informational entries re-keyed with 8 cancelling counterparts in the same functions (`slither-delta-vs-2026-09-21-baseline.txt`) |
| Aderyn 0.6.8 | 10 High and 23 Low categories, 2,449 instances; every category and per-category instance count identical to the seed-domain report |

## Evidence — 2026-09-21, seed-domain snapshot (base of the revision above)

The source is the working-tree snapshot based on `1a4d06d08aa1c5e2a15575039dd66e9c8cc1e0b3`.
See [the readiness review](audit/AUDIT-READINESS-2026-09-21.md) and
[the evidence archive](audit/evidence-2026-09-21.tar.gz). Exact test identities and
which rerun supplies each result are in `foundry-reconciliation.json` inside the archive.

| Check | Result |
| --- | --- |
| Foundry full seven-group sweep | 2,608 passes, 45 initial failures, 103 skips; every initial failure resolved by the affected-suite reruns |
| Reconciled Foundry identities, including new regressions | 2,550 unique passing tests, 0 unresolved failures, 103 skipped; duplicate imported test executions counted once |
| Final decimator/claim/freeze/golden/gas rerun | 58 passed, 0 failed, 7 skipped; includes 1,000 full-width entropy fuzz cases and the century stress variants |
| Final Hardhat full suite | 1,658 passed, 0 failed, 23 pending |
| Final statistical suite | 191 passed, 20 pending, 2 previously disclosed failures: obsolete v36 protected-source baseline and STAT-03 empty-bucket expectation |
| Eleven source/interface gates | All pass; 245 RNG taint sites, 91 registered RNG storage accesses and 223 advance external-call sites |
| Storage layout oracle | All 27 top-level goldens and delegatecall slot alignment pass; the packed one-slot decimator snapshot and its tagged claim seed are separately checked by `DecimatorEntropy.t.sol` |
| Runtime size | All 32 deployment entries fit EIP-170 with checked-in and test pins; smallest measured headroom is 16 bytes under Hardhat fixture pins |
| Static analysis | Current counts and triage context in the readiness review; analyzer output is not a clean-bill-of-health assertion |

Fuzz tests retain the configured 1,000 cases (some existing tests request 10,000);
invariants retain 256 runs at depth 128. The full sweep ran during fixture repairs.
The final decimator full-word storage change followed that sweep and was checked
with the 58-test affected suite, a fresh production build, layout/source gates,
full Hardhat rerun and refreshed analyzers. The archive preserves the earlier
contract hashes and initial failed logs; it does not present this as a single
uninterrupted green Foundry invocation. Current discovery splits 193 top-level
fuzz sources into 49/49/49/46 groups; the earlier sweep had 48 in each group.

Cold full-transaction gas measurements (including intrinsic gas where named):

| Path | Gas |
| --- | ---: |
| Century consolidation + failed/rolled-back 365-day vault settlement, final decimator storage | 13,339,416 |
| Same century case, successful vault settlement | 13,302,484 |
| Terminal fresh-word settlement + deity refunds | 10,418,873 |
| Terminal recorded-word settlement + deity refunds | 10,330,161 |
| Early-bird 128-recipient, hero and partial-source-word pressure (call gas, excluding intrinsic) | 7,895,877 |
| Genesis initialization, both protocol deities | 16,378,197 |

The largest measured cold advance has 1,660,584 gas below the 15M review target
and 3,437,800 below the 16,777,216 transaction cap. Genesis is a separate
initialization transaction with only 399,019 gas spare. Stress fixtures retain
explicit capped calls and their non-vacuity assertions. These measurements are
not a mathematical maximum over all reachable states. Summing two separate
advance stages does not describe a single transaction.

## Historical evidence — 2026-09-18

These results precede the current source snapshot and are retained as a baseline.
Recorded on 2026-09-18 (Node 24.18.0, Foundry 1.6.0-nightly, solc 0.8.34) at the manifest's
base revision `2d350e4f9`. The whole-tree Foundry rows were measured on that revision's
sources before they were committed; the far-future suites were re-run after the last
working-tree change to `DegenerusGameMintModule.sol` was reverted to the committed text.
Gates, oracle, sizes and the static-analysis rows were run at the committed revision.

| Check | Result |
| --- | --- |
| Foundry, whole `test/` tree in the seven compile units above | 2,460 passed, 0 failed, 104 skipped, 313 suites |
| Foundry unit 1 (craps, gas, economics, mutation) | 631 passed, 0 failed, 13 skipped |
| Hardhat `make test-hardhat` | 1,656 passing, 22 pending, 0 failing |
| Hardhat `npm run test:stat` | 191 passing, 20 pending, 2 failing: the `v36.0 SURF-01..04` byte-identical baseline check and `STAT-03`, both pre-disclosed reds |
| Eleven `make check-*` gates and the storage layout oracle | all pass |
| Slither 0.11.5, 182 contracts, rescanned at the base revision | 4,120 results, 187 High; High and Medium composition identical to the prior scan (one `uninitialized-state` key re-keyed by the new early-bird latch helper, the shared-storage class) |
| Aderyn 0.6.8 | 10 High, 22 Low, unchanged |
| Worst-case advance stages, cold state, word applied in the same transaction | jackpot-phase day one 10,424,211 (ETH leg) and 8,076,401 (early-bird leg, its own stage); purchase-phase daily 13,837,513; all under 16,777,216 (`test/gas/JackpotDayOneWorstCase.t.sol`, `PurchaseDailyWorstCase.t.sol`) |
| EIP-170 runtime size, checked-in pins | largest 24,559 bytes (`DegenerusGameAdvanceModule`, 17 spare); `DegenerusGameMintModule` 24,444 (132 spare); `CrapsBattle` 23,930 (646 spare); none over |


Some `test/repro` tests deliberately assert an undesirable current behavior: a passing
witness confirms the behavior, not a fix. Inspect test intent, skips and failures.
Slither/Aderyn output requires source-specific triage. The 187 Slither Highs by class, as
the project reads them; each remains open to the auditor's own judgment:

- 141 `uninitialized-state`: variables of the shared `DegenerusGameStorage` layout read in one
  module's compilation unit and written in another's. The modules delegatecall against one
  storage, so no unit is a deployment on its own.
- 21 `weak-prng`: day-index and time-of-day gates on `block.timestamp`, and a modulo over an
  already-hashed VRF word; nothing a caller can steer is drawn from them.
- 6 `arbitrary-send-eth`: two in mocks; the rest are the ETH/stETH payout doors of the Game,
  the Vault and sDGNRS paying a recipient computed from the contract's own claim state.
- 6 `reentrancy-balance` and 3 `reentrancy-eth`, all on the advance chain: external calls
  into protocol contracts pinned at deployment.
- 4 `delegatecall-loop`: the lootbox module's spin dispatch to pinned modules.
- 2 `encode-packed-collision`: SVG string assembly in the subscription token renderer.
- 2 `incorrect-exp`: `^` used as bitwise XOR, in OpenZeppelin `mulDiv` and a quest pairing hash.
- 2 `incorrect-shift`: Yul shifts in the bucket-lane packing whose operand order the detector
  misreads; the packing tests pin the layout.

Symbolic proofs and deep invariants are separate runs, not implied by `make test-hardhat` or an
ordinary Foundry pass.
