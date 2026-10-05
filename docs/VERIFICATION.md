# Build and verification

Run checks against the exact revision supplied for review. The repository contains
source, tests and reproduction tooling; generated logs and analyzer reports stay in
local output directories or CI artifacts.

## Setup

Use Node 20 (as in CI), Python 3, Bash, Git and Foundry. Solidity 0.8.34, via IR,
1,000 optimizer runs and EVM Osaka are set in both compiler configurations.
The npm dependencies and forge-std revision are locked in the repository. Foundry
CI currently follows nightly; record the actual version when reproducing a run.

```sh
git rev-parse HEAD
node --version
forge --version
python3 scripts/audit-snapshot.py
npm ci
git submodule update --init --recursive
```

The snapshot check verifies the scope and hashes of source, build and verification
inputs. It does not attest that tests pass. Maintainers refresh those hashes with
`python3 scripts/audit-snapshot.py --write` after finalizing changes.

Foundry and Hardhat fixtures patch `contracts/ContractAddresses.sol` to their
predicted deployment addresses. The maintained runners restore its original bytes
on completion, failure or handled interruption. Run concurrent campaigns in
separate disposable checkouts. Raw test commands bypass this restoration.

## Build and structural checks

```sh
forge build --skip test
node scripts/check-deployment-sizes.js
bash scripts/layout/storage_layout_oracle.sh
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-gasleft
make test-assurance-tools
```

The size gate checks deployment entries against the 24,576-byte runtime limit and
rejects stale, missing or unlinked artifacts. Address pins affect compiled output;
repeat deployment checks with the intended production pins. The storage oracle
compares top-level slots, offsets and types; it does not recursively verify nested
struct members. Source manifests are review aids, not proofs of their annotations.

## Tests

The grouped runners bound compilation memory, reject empty or failed batches and
record commands and inputs under the ignored `.audit-test-logs/` directory.
`--list` prints the selected files; `--file` selects a focused source root. Foundry
uses seven logical groups, while Hardhat defaults to one test file per process.

```sh
make test-foundry
make test-hardhat
# Inspect selections or run a focused regression:
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-hardhat-groups.py --list
python3 scripts/test-foundry-groups.py --file test/repro/TerminalAffiliateKnownWord.t.sol
python3 scripts/test-hardhat-groups.py --file test/edge/BackfillIdempotency.test.js
```

For CI-equivalent cold integration and gas checks:

```sh
FOUNDRY_ISOLATE=true python3 scripts/test-foundry-groups.py \
  --group integration-gas --max-files 5 --threads 1
```

CI runs the other six Foundry groups with isolation disabled, at most ten roots
per batch and one thread. The default fuzz campaign uses 1,000 runs; default
invariants use 256 runs at depth 128, with per-suite overrides visible in source.
`npm test` uses the maintained Hardhat runner, including all statistical files.
Discovery fails if a JavaScript test is outside the configured directories.
`npm run agent:test` runs the separate local agent unit suite when the ignored
`agent/` working tree is present; it is not part of the public checkout. Focused `npm run test:*`
commands use raw Hardhat and therefore bypass runner-level pin restoration.

See [the test usefulness review](TEST_REVIEW.md) for retired checks, repaired
fixtures and the distinction between model, structural and runtime coverage.

No chunk between two checkpoints may cost more than 10M gas in its worst case,
including its call/return/flush tail. A transaction may exceed 10M by running several
admitted chunks. Each checkpoint admits the next chunk only when its conservative
worst-case cost and tail fit both the remaining worker allowance and actual available
gas; a larger supplied budget runs more chunks, never a larger one. A protocol path
with no internal checkpoint (advance, terminal or keeper call) is one chunk and must
also stay within 10M; batches whose size the caller chooses are sized by that caller.
Fixture gas limits do not establish cold bounds. Gas may only select safe
continuation, never a semantic fallback or committed outcome.

## Deep and symbolic checks

```sh
FOUNDRY_PROFILE=deep FOUNDRY_ISOLATE=false python3 scripts/test-foundry-groups.py \
  --group invariants --max-files 5 --threads 1
```

The deep invariant profile uses 1,000 runs at depth 256. The separate Halmos job
uses version 0.3.3, the `halmos` Foundry profile and the bounds recorded in
[CI](../.github/workflows/ci.yml). Both jobs run on scheduled or manual dispatch.
Use that job's command in a disposable checkout to reproduce symbolic checks.

Known verification limits:

- The last local full Halmos campaign left five properties timed out. A timeout
  establishes neither a counterexample nor a proof; the campaign is not all green.
  These are `check_cost_no_overflow`, `check_autorebuy_ethspent_bounded` and
  `check_takeprofit_multiple` in `test/halmos/Arithmetic.t.sol`, plus
  `check_bps_split_exact` and `check_affiliate_reward_bounded` in
  `test/halmos/NewProperties.t.sol`.
- The last local deep invariant campaign did not finish. Ordinary test passes
  do not substitute for a completed deep run.
- Existing skipped/pending tests and harness assumptions remain visible in test
  source. Imported helper suites can repeat across batches, so execution totals
  are not counts of unique properties.
- A full remote CI run of the supplied revision has not been confirmed. Consult
  that revision's CI results rather than historical local pass counts.

## Static analysis

Optional Slither and Aderyn jobs are configured in CI and are non-blocking.
To run Slither against a fresh Hardhat build in a disposable checkout:

```sh
pip install slither-analyzer==0.11.5
npx hardhat compile
slither . --compile-force-framework hardhat --ignore-compile
```

Analyzer output requires independent triage. Reports and test logs are generated
on demand and are not part of the source handoff.

The fixed 900-unit ticket budget is retired. Current ticket admission uses
`MineFlipGas` and `MineFlipGasBounds`; every atomic operation and complete accumulated
return tail needs a cold bound. Chunks between checkpoints target 10M gas or less in
about 99% of realistic cases, with a 13M absolute worst case (see `docs/AUDIT.md`).
Historical measurements remain historical evidence.

## Daily RNG and foil implementation (2026-10-01)

The two tagged daily RNG slots, normal foil generation cohorts with stored lines,
D/D+1 foil and WWXRP claim windows (the foil-match deadline is superseded by
the persistent-seed change below), packed coinflip gap results, automatic live
sDGNRS settlement, and 250-day startup deadline are implemented. Terminal sDGNRS
redemptions have no expiry. Global level wrapping was superseded by ticket queue
reuse with absolute gameplay levels, described below.

The final focused Foundry campaign passed 133 tests with transaction isolation
and 1,000-run fuzz properties, across 12 selected roots (imported suites can repeat).
It includes all six frozen Craps window terms compared against the original RNG
decoder before and after word retirement, calendar expiry without slot overwrite,
stalled sessions, packed gap accounting, batch claims, maximum redemption work,
terminal claims after 2,000 days, and the freeze detector's mutation checks.
The RNG freeze invariant also passes all 256 runs at depth 128 (32,768 randomized
actions), with real daily/midday primer cycles and four focused mutation/coverage
checks. The six focused JavaScript files also pass (134 checks, with the gap fixture
rerun after adapting its event expectation to unlocked consumer work). The
maximum-size cold redemption settlement used 1,392,600 gas, including intrinsic
gas. Source manifests and the 43 assurance-tool tests pass. Reviewed storage changes
rename the reserved slot and foil fields in place, and append the sDGNRS queue;
no existing field moves. Production size and interface/layout checks pass against
restored production address pins. The narrowest runtime margin is 12 bytes
(Whale module: 24,564 of 24,576 bytes).

This focused work does not establish a full Foundry/Hardhat, deep invariant,
Halmos, or remote CI pass for the working tree. Keep the existing verification
limits above when reviewing or releasing this revision.

## Ticket queue reuse (2026-10-01)

Gameplay levels remain absolute. Ticket queue storage reuses slots 1–100 within
each existing near/far-future domain; level zero remains reserved. Absolute-level
tags authenticate reads, require an empty queue before reuse, and prevent stale
release calls from clearing newer tickets. Generated L inventory can retire while
L+100 remains queued. The Lens continues accepting absolute logical queue keys.
Permanent wallet IDs belong to a separate workstream: the existing absolute owner
registry and wallet-position cache retain their layouts. One queue-tag mapping is
appended at shared slot 78, with no existing field moves.

The latest focused results pass 216 Foundry checks across 31 suites, counting each
suite's latest result once rather than repeated imported executions. Default fuzz
properties use 1,000 runs, with source overrides retained. Coverage includes three
centuries of reuse, near/far coexistence, collision protection, stale releases,
packed-tail sampling, Lens authentication, purchases, mint drains, salvage,
jackpots and terminal settlement. Cold gas checks use transaction isolation; the
functional basefee-cheat fixture runs without isolation. The final five-file
JavaScript campaign passes 47 checks, and the assurance-tool suite passes 43.

Cold genesis initialization uses 16,338,028 gas including intrinsic gas, within
its existing dedicated 16,777,216 startup cap. Genesis initialization now requires
level zero and uses implicit first-century tags to avoid redundant cold accesses.
A transition with 32 fresh deity renewals uses 2,523,387 gas including intrinsic
gas; the frozen-pool chunk uses 5,125,018 gas excluding intrinsic gas. Existing
limits and compiler settings were not raised.

Production build, deployment-size, interface, source-manifest and storage-layout
checks pass with restored production address pins. Whale and Foil runtime sizes
are each 24,564 bytes (12 bytes below the limit); Game is 24,560 bytes. These narrow
margins require rechecking after integration with the permanent-ID workstream.
This is focused validation; it does not establish a full-suite, deep invariant,
Halmos or remote CI pass.

## Redemption batching integration (2026-10-01)

The subsequent redemption workstream batches whole FIFO claims within the existing
keeper work allowance, credits the keeper once per successful claim, and admits
box work only within the remaining allowance. Manual claims retain their existing
settlement behavior. The terminal foil-only cohort fix is also covered.

Its final accepted grouped run passes 146 test executions across 17 selected roots
(imported suites can repeat), including 1,000 whole-claim gas fuzz cases and the
existing 10,000-case reserve fuzz. Eleven source gates pass. Exact production-pin
and separate nonzero-pin compilations fit the deployment-size limit and match all
28 golden layouts. These are additional scoped results, not a full audit battery.

At the commit-readiness check, all 11 promoted files matched the workstream's
recorded hashes, and all 83 local contract sources matched its final exact-pin
compiler input, including the queue reuse changes. The only changes since the
prior audit snapshot were those promoted files. Verification evidence remains in
`.audit-test-logs/foil-redemption/change-b/`; the accepted run is
`foil-redemption-accepted/20261001T192221.151074Z-f7d2e221`. The audit snapshot was
refreshed after checking that correspondence. Deployment-size and whitespace
checks also pass on the combined checkout.


## Persistent foil match seed (2026-10-02)

The no-expiry policy and permanent record retention described in this historical
entry are superseded by the foil expiry and record reuse change below. The saved
payout seed and its domain separation are retained.

Implemented the packed 128-bit payout seed and format flag in `dailyFoilDraw`,
with no new storage field. Live-game match claims no longer expire by age or read
the two-slot daily RNG ring. Golden-ticket deadlines and the liveness/terminal
cutoff remain. Repeated sealing is a no-op: it preserves the first record without
a replacement event or a new revert in the advance chain. No emergency entrance,
ticket-round change, or dispatcher rewrite is included.

The final isolated Foundry campaign passed **84/84 tests** across eight selected
roots (ten suites including imported helpers). It covers all five match tiers and
three currencies, 400-day delays after both RNG slots are reused, single/batch
replay, century-crossing batch eligibility, zero versus unseeded records, invalid
domains/packs, logical-day versus wall-day sealing, unchanged golden expiry,
terminal rejection, and existing jackpot/foil/snap payout regressions. A separate
focused run passed the six generation-cohort tests and the five RNG-freeze checks,
including 256 invariant runs × 128 actions and seeded mutation detection. The
freeze handler now samples recent/logical and historical foil records in both
request windows. This is focused verification, not a full-suite audit.

The pool-change test preserves the primary ETH gross payout with historical level
pricing and saved activity, while an empty live pool converts the ETH share into
recirculation. The first synthetic century-jump version collided with an old
undrained recycled queue; the corrected pool-change fixture changes pricing within
the century, while the separate batch test checks old-claim eligibility at level
101. No production code was changed to bypass queue protection. Claim timing can
change the live ETH share, sDGNRS Reward-pool award, and recirculation results;
unclaimed matches are not funded reservations. No age limit expands this existing
timing option. See `docs/audit/RNG-DOMAINS.md` for the payout-state review.

A deterministic 40,000-sample seed smoke check produced currency counts
16,148 / 15,861 / 7,991 (ETH/FLIP/WWXRP) and hero-quadrant counts
9,760 / 10,146 / 10,088 / 10,006. This checks gross distribution drift, not a
cryptographic proof. Pack generation, matching tiers, and spin resolvers are
unchanged; the new domain-separated seed intentionally changes payout sequences.

An isolated storage/packing microbenchmark measured +247 gas for a fresh draw
record and −4,195 gas for the packed draw/entropy read versus the previous draw
plus tagged daily-word read. These are localized call measurements, not full
transaction gas deltas or worst-case payout bounds. The writer still performs one
SSTORE for a new record and none for an existing record.

A fresh production-pin build passed source-hash-validated size checks for every
deployable contract: FoilPack 24,524 bytes (52 spare), Jackpot 23,219 (1,357 spare),
and Game 24,560 (16 spare). All 28 emitted layouts match the checked-in normalized
goldens; build sources match the workspace exactly. RNG-window, RNG-taint,
shared-writer, advance-call, delegatecall, unchecked, and gasleft gates pass; the
RNG-window gate's four mutation self-tests also pass.

Evidence: `.audit-test-logs/foil-persistent-seed/`; final campaign
`20261002T053806.025136Z-7a5211ec`, cohort/invariant run
`20261002T052904.715785Z-953cdaa4`, and localized gas probe
`20261002T053705.473273Z-dbda1d4d`. The probe source, production sizes, layout result,
and distribution counts are saved there. Changes are uncommitted. Old unseeded
records intentionally fail claim validation; this is a predeployment format
change, not a deployed-state migration.

## Foil claim expiry and record reuse (2026-10-02)

Match claims now close at the start of D+2, where D is the logical draw day.
Expiry applies even if the draw slot remains intact, and a draw first published
after that deadline is already expired. Gold retains its actual-generation-day
and following-day window; terminal settlement still closes both claim paths.

The four ticket lines and pack metadata occupy four reusable level-tagged words
per player (`level & 3`), with the gold-paid flag in the same word. Reuse requires
completed materialization, an older level, a closed gold window, and no reference
from today's or yesterday's draw. A collision rejects only the new purchase.
The daily board and payout seed use two exact-day-tagged slots. Match replay
protection uses one word per player with two tagged daily ticket bitmaps. Every
lookup authenticates the full day or level; expiry is checked before claim bits
can roll over. Internal draw readers retain logical-day access for stalled
jackpot stages without granting expired player claims.

Production compilation and source-hash-validated size checks pass for all 33
deployment artifacts. FoilPack is 23,582 bytes, Jackpot 23,578, and Game 24,524.
All 28 normalized storage layouts were compared: only `foilMatchClaimed` changes
type to `mapping(address => uint256)` in the 13 shared layouts; no slot or offset
moves. This is a predeployment storage-format change with no legacy migration.

The final focused campaign covers 141 distinct passing test cases across its
selected roots, taking the latest execution of each case after fixture repairs.
The focused claim/reuse rerun passes 42/42 executions, including all 18 batch/claim
tests and seven storage-reuse tests. Coverage includes all match tiers/currencies
on D and D+1, D+2 rejection without overwrite, exact-tag rejection, bitmap rollover,
single/batch replay, independent ticket bits, and actual purchases preserving live
or pending records before replacing expired records and clearing old flags/lines.
Gold/snap payouts, cohort isolation, lens parity and ticket recycling regressions
pass. The RNG-freeze suite passes 256 invariant runs × 128 calls. Nine drain gas
tests pass: the empty foil-tail advance uses 1,688,075 gas including intrinsic;
the accompanying ticket stage uses 4,958,867, under the 10-million drain bound.

Evidence is under `.audit-test-logs/foil-record-reuse/`. Early fixture failures
(timestamp reads across `vm.warp`, obsolete cohort keys and historical public RNG
lookups) were corrected in tests; no payout or advance rule was relaxed for them.
Both stalled-request tests pass after restricting fixture box drains to unlocked
boundaries; the final trace and rerun are in
`.audit-test-logs/foil-record-reuse-stall-debug/20261002T061312.802123Z-e5dd0f9f/`.
The production source manifest, sizes, normalized-layout comparison and isolated
Foundry run manifests are retained there. These are focused checks, not a full
audit or a full-suite pass.

## Final Coinflip and Craps gas pass (2026-10-04)

Coinflip's claim loop now caches the current 32-day result word. Stake words still
load fresh, including after a clear; virtual seed stakes retain their existing
handling. Craps sums its ten validated chip counts with packed arithmetic and
writes the settlement cursor once after the admitted seats. A budget stop flushes
the last completed seat; no progress causes no cursor write. The masked write
preserves the field binding and precedes the accumulated Coinflip credit call.
The existing seat and flush-tail gas reservations are unchanged. These three
changes add no storage fields and change no external signatures.

The saved implementations in `test/helpers/reference/*BeforeFinalGas.sol` (archived with
their differential tests in `degenerus-audit-archive/2026-10-04-customer-gas-ab-evidence/`;
also committed on branch `opt/customer-gas-followups` at `72d5f2d6a`) capture
the combined main working tree immediately before these three changes, including
the earlier packing, whole-token, affiliate and storage-reuse work. Their only
reference adaptations are contract names and relative imports. Differential tests
replace runtime code at the same address and restore the same initial snapshot,
so calldata, dependencies, compiler settings and initial state agree.

Measured gas with transaction isolation enabled:

| Public call / fixture | Before | After | Gas saved |
| --- | ---: | ---: | ---: |
| Coinflip claim, one day | 173,855 | 174,034 | -179 |
| Coinflip claim, 32 days across words | 291,804 | 289,661 | 2,143 |
| Coinflip claim, 365 days | 981,151 | 960,903 | 20,248 |
| Coinflip auto-rebuy exit, 1,460 days | 3,934,334 | 3,851,408 | 82,926 |
| Craps preferred-board validation | 52,407 | 51,697 | 710 |
| Craps settlement, 40 ordinary seats | 1,996,965 | 1,985,500 | 11,465 |
| Craps settlement, 20 high-lane seats | 1,178,939 | 1,173,154 | 5,785 |

These are fixture measurements, not universal worst-case bounds. The cache has a
small one-day overhead. Craps differential settlement uses the real engine and
JackpotBattle with mocked satellite contracts; protocol wiring is checked
separately with the complete deployment fixture. Claim comparisons use the
complete deployment fixture, compare ordered events and affected balances/packed
words, and exercise mixed gaps, wins, losses, seed accounts and repeated claims.
Chip comparisons check both outputs and exact rejection data. Settlement
comparisons check ordered events, progress and all written storage keys on the
table and its mocked payout dependencies, plus no-progress and partial-resume cases.

Four existing Coinflip claim fixtures now use whole FLIP/WWXRP units, matching the
earlier token-unit change. The seed-window gas fixture measures a nested cold
protocol call so Foundry isolation does not add transaction intrinsic gas to its
execution-only ceilings. The original ceilings are retained.

Two combined-regression fixtures were also repaired: whole-token ticket rounding
now exercises `redeemFlip` after opening its prize-target gate, checks the exact
insufficient-FLIP error, and reads owed entries in whole-entry units. The keeper
reward fixture nests the fee cheat and protocol call in one execution frame so
the isolated runner retains its intended nonzero fee. The same measured work
(1,456,514 gas) now pays the independently calculated 6 FLIP; its original payout
equality and nonzero-reward assertions remain.

The accepted latest execution of each of 21 selected roots passes: 347 test
executions, zero failures and zero skips (imported helper checks repeat). Besides
the new differentials, these cover claim/carry/rebuy/seed/gap lifecycle, deep-claim
gas, Craps budgets/cursors/awards/reuse, real protocol wiring, whole-token payment
boundaries, spin precision, affiliate identity and packed sibling preservation.
The regression runs are `20261004T130218.838952Z-eec1bc2c` and
`20261004T130943.073895Z-a08ea120`; the two final fixture reruns are in
`20261004T131702.498811Z-5cee8b16`. Earlier failed fixture executions remain in the
logs. The accepted per-root index is `.planning/final-gas-accepted-tests.json` in
the validation checkout, with a copy under main's `.planning/final-gas-pass/`.

The final combined build passes all eleven source/interface gates and the
source-hash-validated size check for 37 deployment artifacts. Coinflip is 22,746
runtime bytes (1,830 spare); CrapsBattle is 24,207 (369 spare). All 32 normalized
golden layouts match, and the recursive comparison finds no mismatch across the
16 delegate modules. The 51 assurance-tool unit tests also pass. The integration
log is `.planning/final-gas-integration.log` in the validation checkout.

The build uses the checked-in address pins (SHA-256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`). At the final
comparison, all 95 Solidity contract sources and all eleven changed/new test and
reference files match the validated checkout, including the restored address
pins. Main remains at `764b4ab9c`, with the work uncommitted. The accepted-source
hashes are retained in `.planning/final-gas-pass/source.sha256.json`; the release
audit snapshot has not been refreshed or represented as a full audit pass.

The accepted differential runs are `20261004T125853.687939Z-523aff2d` (Coinflip)
and `20261004T130108.835329Z-3bcb07e1` (Craps), under
`/home/zak/.cache/degenerus-final-gas-pass/.audit-test-logs/foundry/`.
Both pass nine primary cases plus six imported helper checks, including 1,000-run
fuzz properties. All compilation/testing for this pass uses the fixed systemd
job with an 8 GiB memory cap, zero swap and two-core CPU quota, serially with one
Foundry source root and one thread per batch. Trait-bucket write coalescing remains
deferred. The larger bundle's full-suite release audit remains outstanding.

## WWXRP minimum positive award (2026-10-04)

Positive awards below one WWXRP now pay one whole token. Skipped-BAF consolation
uses the same minimum in its view and claim, and the shared WWXRP spin resolver
applies it before returning the award to lootbox/foil callers and emitting
`BoxSpin`. Zero scores, stale/claimed scores and losing spins still pay zero.
Larger awards retain their whole-token floor. The token's existing `gameMintScale`
still applies at mint time, including its zero-emission setting. Coinflip losses,
presale duds, golden-ticket consolation and lootbox cold-bust awards were already
whole-token amounts or had a one-token minimum.

The focused isolated run `20261004T141035.230963Z-178f5094` passes all 38 test
executions across `BafConsolationClaim`, `SpinPrecision` (archived with the reference
copies, see above) and `WwxrpGameMintScale`
(20 primary cases plus repeated imported helpers). This includes 1,000 randomized
BAF scores, live advance/VRF bracket skipping followed by claims, smallest-score
and whole-token boundaries, event/return agreement, replay rejection, mint-scale
0/7 cases, 128 randomized spin comparisons and 640 fixed WWXRP spin fixtures
against the preserved fractional-precision resolver. Fixed fixtures assert that
losing, positive sub-token and larger winning outcomes are all exercised. The
paired FLIP spin comparisons retain the prior floor rule.

Evidence is in `/home/zak/.cache/degenerus-wwxrp-minimum/`, with the accepted source
hashes under main's `.planning/wwxrp-minimum/`. Work remains uncommitted on main.

The combined build, all eleven source/interface gates, 37 deployment-size checks,
32 golden layouts, recursive alignment of 16 delegate modules and 51 assurance
tool tests pass. DegenerusJackpots is 5,364 runtime bytes and the Degenerette
module is 21,258. The accepted contract sources and changed tests match main
exactly. The larger release audit remains outside this focused verification.

## Forward redemption batches and bounded lootbox orders (2026-10-05)

Live burns now queue raw token weights and a frozen activity score. The next live
RNG request closes the batch, fixes its ETH/FLIP backing, and reserves the maximum
ETH outcome. Its response supplies the redemption roll (21–175%) and an independent
synthetic flip. Open escrow remains in the holder base until close. Terminal
resolution uses 100% for an unrolled closed batch; an open batch unwinds at terminal
backing value. A live lootbox leg becomes one custom-size order of at most 20 boxes,
using the shared human-order roller and no whale-pass overflow conversion.

The legacy redemption tests, public selectors, worker fixtures, gas admission
checks, source manifests and sDGNRS layout golden were migrated to that behavior.
This preparation changed verification code and records, not production contract
logic. See `TEST_REVIEW.md` for the coverage mapping and retired assumptions.

Production build and deployment-size validation pass for all 37 deployment
entries with the original address pins (SHA-256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`).
DegenerusGame is 24,539 runtime bytes, leaving **37 bytes**; the lootbox module is
20,436 bytes and sDGNRS is 18,525 bytes. All layout goldens match the reviewed
source, and the recursive delegate-layout comparison reports no mismatch across
16 modules. Interface coverage and all ten other source gates pass. The 51 Python
assurance-tool tests pass; the complete 622-file Solidity source/test type check
also passes.

The build, layout and interface checks ran in the disposable checkout
`/home/zak/.cache/purgegame-tmp/redemption-hardhat-ready-ztkhthk7`, with matching
contract-source hashes. Production build/size evidence is copied under
`.audit-test-logs/redemption-ready/`. Hardhat's DGNRS and Coinflip suites pass all
105 tests (`20261005T093914.162316Z-9bad1204`); the updated redemption seed model
passes five statistical checks (`20261005T095147.345703Z-239e0795`). Both maintained
runs report no compiler or source drift and their evidence is copied under
`.audit-test-logs/hardhat/`.

The accepted latest executions across 38 selected Foundry roots pass all 345
checks, with 1,000-run fuzz properties and default invariant settings (including
suite-specific overrides recorded in source). The combined run
`20261005T095320.358976Z-37d75683` passes 344 and exposes one terminal assertion
reading its expected value after claim deletion. The corrected file is rerun in
`20261005T100547.199651Z-4cf5185d`, passing all 17 checks, and that exact file is
copied back into the working tree. No other test or contract source changed after
the combined run. The per-test accepted-result index is
`.audit-test-logs/redemption-ready/accepted-tests.json`; earlier failures remain
in the logs. Coverage includes exact reserves/token accounting, arbitrary-input
safety, RNG freezing, delayed responses, and award equality across keeper gas
partitions while the next batch accepts burns.

The isolated cold campaign `20261005T095321.718553Z-e2ae7086` passes all 58 test
executions with 1,000-run fuzz properties and no input drift. It selects
`RedemptionBatchGas`, `AdvanceCenturyConsolidationGas`, `SdgnrsPendingReuseGas`
and `RedemptionForwardBatches`, with `FOUNDRY_ISOLATE=true --threads 1`.
It includes ETH and stETH funding, boxes up to 120 million ETH, real request and
settlement flows, and constant-time cleanup for 2 versus 2,000 beneficiaries.
The worst measured cold 20-box beneficiary uses 1,047,681 gas against the declared
2,430,000 allowance (including the return tail). The large-value order fuzz test
asserts the separate 1,850,000 order bound for every sampled amount and seed.
The century variants cover both a committing and a reverting 365-day vault claim;
their setup now uses whole FLIP/WWXRP units. These are measured bounds over the
specified fixtures and fuzz samples, not a proof over every possible EVM state.
Evidence is copied under `.audit-test-logs/foundry/`.

This is focused commit verification, not a completed whole-repository release
audit, deep invariant campaign, symbolic campaign or remote CI run. Historical
counts and source-pinned report drafts do not attest this revision. Refreshing the
audit snapshot authenticates the current inputs only; it does not expand that scope.

## Dead-code removal (2026-10-05)

The 10-05 dead-code review's findings are applied. Four external entry points with no
production caller are removed with their interface declarations: `FLIP.vaultEscrow`,
`JackpotBattle.completeRngSlot` and `payProgressive`, and `prepareTicketLevel` on the foil
pack module. Helpers with no caller are deleted, test-only helpers and the decoded `Bet` /
`Battle` structs move into test support, the always-false `rngBypass` argument leaves the
scaled, range and half-pass queue helpers, and unused constants are removed. The four craps
RNG domain tags that the engine and the hottest-shooter payout spelled as literals are named
in `Craps.sol` and used at those sites.

Compiled before and after on the same tree, 54 production contracts are byte-identical with
metadata stripped, including DegenerusGame and CrapsBattle. The removals shrink the foil pack
module by 242 bytes, FLIP by 184, JackpotBattle by 164, the whale module by 86, the AFKing
module by 84 and the mint module by 34. CrapsEngine (+32) and the jackpot module (+31) change
only through via-IR code ordering; a differential fuzz of the old and new CrapsEngine runtime
returned identical data for every sampled settlement and used 0.14% less gas.

The 94 affected Foundry roots ran 1,197 passing and 21 failing tests, and nine affected
Hardhat files 22 failing tests; every failure fails by the same name on the tree before the
removal (older suites not yet migrated to whole-token units). Rebased onto the redemption
commit, the complete Solidity source/test tree type-checks, all eleven source gates,
interface coverage and the storage-layout oracle pass, and the two test files edited by both
changes pass all 80 checks.
