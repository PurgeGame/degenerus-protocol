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

The 10M gas figure is a sizing and benchmark guideline for indivisible work, not a
runtime chunk or transaction cap. Each checkpoint admits the next chunk only when
its conservative worst-case cost, complete call/return/flush overhead and safety
margin fit both the remaining worker allowance and actual available gas. A larger
supplied budget may admit a chunk above 10M. Network transaction/block limits remain
separate. Fixture gas limits do not establish cold bounds. Gas may only select safe
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

Ticket header-tail pricing (latest user direction, 2026-10-01): require at least
99% of normal keeper calls at 10M or less. The uniform-650 trial is superseded.
Use 900 units at 10k gas, charging physical zero-valued slot writes three units
and nonzero writes one; remove the first-chunk derate. With 1M fixed overhead,
the drain envelope is 10M even during startup and record-volume backing growth.
Existing stricter measured fixture limits remain in place. See
`test/gas/TicketDrainWorstCaseBound.t.sol`, `RoundDrainChunkGas.t.sol` and
`KeeperGasProfile.t.sol`.

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
