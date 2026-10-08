# Build and verification

Run checks against the exact revision supplied for review. The repository contains
source, tests and reproduction tooling; generated logs and analyzer reports stay in
local output directories or CI artifacts.

[The current readiness review](AUDIT-READINESS.md) records the latest campaign.
The dated implementation sections below are historical, scoped evidence; their
pass counts do not certify later revisions.

### ID-keyed smurf allowance (2026-10-08)

The smurf feature follows baseline commit `1dcc578d0`. Quota belongs to the main
ID: bits 224–239 of its existing mint word count lifetime creations, and bits
240–255 hold the base allowance. Capacity is `min(65535, base + currentScore / 120)`.
The vault owner calls `Game.raiseSmurfBaseAllowance(uint32,uint16)` directly;
MintModule checks `isVaultOwner`, and Admin has no forwarding function. Children
refer directly to their main ID. Acquired accounts cannot create children or
receive grants, and replacement IDs do not inherit sold IDs' quota.

The precommit review found and fixed a packed-field regression in
`DegenerusQuests.marketBetGates`: a quota-only mint word could satisfy the existing
participation gate. The gate now ignores both quota lanes and the curse counter.
Two new regressions failed before the fix, then passed afterward; they cover real
grants, child creation, the child's own eligibility, main purchases, and arbitrary
quota/curse combinations. Older smurf fixtures now request explicit capacity. The
sale-callback regression first proves a replacement ID cannot reuse sold quota,
then earns fresh capacity through a real deity-pass purchase before creating a
child inside the callback.

Final selected verification passes:

- Foundry: **650 tests, 55 suites, 46 selected roots**, zero failures or
  skips, using fuzz seed `0xbadc0de`. Coverage includes smurf creation and referrals,
  packed-field preservation, liquidation and callback authorization, account doors,
  payouts, deity groups, lens/identity views, seats and identity gas fixtures, plus
  activity score/cache, quests, markets, affiliate and pass regressions. WalletIdTruth
  passes **256 × 128** invariant calls; SeatCap passes **64 × 64**. Quota ghosts
  derive counts and grants from events and detect corrupted count/base fields.
- Hardhat: **178 tests across five files**, zero failures or pending tests:
  `SmurfAllowance`, `DegenerusAdmin`, `AccessControl`, `DegenerusAffiliate` and
  `AffiliateHardening`. The grant test exercises bases 300 and 65,535 and a real
  DGVE transfer, proving authority follows the vault owner.
- Source guards pass for delegatecalls, raw selectors, RNG windows, pool writes,
  array deletes, advance calls, RNG taint, unchecked arithmetic, write ownership
  and gas reads. Fresh production artifacts match **33 storage goldens** and
  **303 methods across 27 interfaces**; all **16 Game modules** share the complete
  recursive Game layout, and JackpotBattle matches CrapsBattle.
- Fresh normal-pin production bytecode passes the deployment size gate with
  source hashes verified against the final checkout. Game is **24,454 bytes**
  (122 spare), MintModule **22,509 bytes**, Affiliate **9,830 bytes**, and Quests
  **21,749 bytes**. The identity gas fixture measures first-child creation at
  **389,915 gas** and subsequent creation at **352,417 gas** (fixture-specific).

Foundry evidence is under local run
`.audit-test-logs/smurf-precommit-final/20261008T153815.408009Z-d2759939/`; Hardhat
evidence is under
`.audit-test-logs/smurf-precommit-hardhat/20261008T154020.316706Z-51985005/`.
The two pre-fix failures are retained under
`.audit-test-logs/smurf-market-before/20261008T153427.202527Z-90ec946b/`, and build
and structural evidence is under `.audit-test-logs/smurf-precommit-checks/`.
The runners retain selected files, commands and source/compiler inputs, and report
no source drift. Hardhat and the normal-pin production build used an isolated
copy with matching production sources to avoid concurrent fixture pin changes.
Generated evidence remains local. These selected results do not represent a new
full-repository audit or certify the older readiness campaign against this feature.

### Pre-smurf checkpoint (2026-10-08)

This checkpoint combines the readiness changes with BAF sampling of the main
board's three non-solo traits, using prepared physical buffers. The BAF execution
record reports 47 passing direct-buffer follow-up tests and passing source,
interface, layout and deployment-size checks. Those are prior scoped results;
the complete combined tree was not rerun at this checkpoint.

Fresh checkpoint checks pass: six deep-partition tooling tests, four split-proof
tooling tests, 24 split arithmetic checks, and `git diff --check`. Source identity
hashes are refreshed to include the combined changes. These checks do not certify
the subsequent smurf feature, which has not started at this checkpoint.

## Setup

Use Node 20 (as in CI), Python 3, Bash, Git and Foundry. Solidity 0.8.34, via IR,
1,000 optimizer runs and EVM Osaka are set in both compiler configurations.
The npm dependencies and forge-std revision are locked in the repository. Foundry
CI pins `nightly-c07d504b4ae67754584f4e05ff0c547a43c50f7b`, the build used by
the audit campaign. Record the actual version when reproducing a run; use the
same release for comparable gas and invariant evidence.

The Foundry runner rebuilds a coherent artifact set for each physical batch.
Incremental artifacts from a different selection can otherwise disagree with the
handler runtime embedded in a cached invariant test. Both runners fingerprint
symlinked library directories, stop directory cycles and fail on dependency drift.
CI limits ordinary batches to five roots without reducing test or fuzz budgets.

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
forge build --skip test --out forge-out-production --cache-path .foundry-cache-production
node scripts/check-deployment-sizes.js forge-out-production
FOUNDRY_OUT=forge-out-production FOUNDRY_CACHE_PATH=.foundry-cache-production \
  bash scripts/layout/storage_layout_oracle.sh
python3 scripts/layout/check_recursive_layout.py --out forge-out-production \
  --report .audit-test-logs/recursive-layout.json
make check-interfaces check-delegatecall check-raw-selectors check-rng-window \
  check-rng-taint check-advance-calls check-unchecked check-write-owners \
  check-pool-writes check-array-delete check-gasleft
make test-assurance-tools
```

The size gate checks deployment entries against the 24,576-byte runtime limit and
rejects stale, missing or unlinked artifacts. Address pins affect compiled output;
repeat deployment checks with the intended production pins. Keep production artifacts
and their cache separate from test builds: a test runner may overwrite the default
artifacts with fixture pins while an unrelated build cache still considers them current.
The size gate rejects that mismatch. The storage oracle
compares top-level slots, offsets and types; it does not recursively verify nested
struct members. The additional recursive comparison checks all Game modules and the
CrapsBattle/JackpotBattle pair, including nested members. Source manifests are review
aids, not proofs of their annotations.

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
python3 scripts/test-foundry-groups.py --file test/repro/TerminalPayoutCheckpoints.t.sol
python3 scripts/test-hardhat-groups.py --file test/edge/BackfillIdempotency.test.js
```

For CI-equivalent cold integration and gas checks:

```sh
FOUNDRY_ISOLATE=true python3 scripts/test-foundry-groups.py \
  --group integration-gas --max-files 5 --threads 1
```

CI runs each of the seven Foundry groups in a separate job. The other six groups
use isolation disabled, at most ten roots per batch and one thread. The default fuzz campaign uses 1,000 runs; default
invariants use 256 runs at depth 128, with per-suite overrides visible in source.
`npm test` uses the maintained Hardhat runner, including all statistical files.
Discovery fails if a JavaScript test is outside the configured directories.
`npm run agent:test` runs the separate local agent unit suite when the ignored
`agent/` working tree is present; it is not part of the public checkout. Focused `npm run test:*`
commands use raw Hardhat and therefore bypass runner-level pin restoration.

See [the test usefulness review](TEST_REVIEW.md) for retired checks, repaired
fixtures and the distinction between model, structural and runtime coverage.

The 10M figure is an operation-sizing guideline, not a transaction ceiling or a
substitute for a proven cold-path admission bound; see [the audit scope](AUDIT.md).
A transaction may execute several admitted chunks. Each checkpoint admits the next
chunk only when its conservative worst-case cost and complete call/return/flush
tail fit both the remaining worker allowance and actual available gas.
A protocol path with no internal checkpoint is one indivisible chunk; caller-selected
batches do not establish a bound for protocol-selected work.
Fixture gas limits do not establish cold bounds. Gas may only select safe
continuation, never a semantic fallback or committed outcome.

## Deep and symbolic checks

```sh
FOUNDRY_PROFILE=deep FOUNDRY_ISOLATE=false python3 scripts/test-foundry-groups.py \
  --group invariants --max-files 5 --threads 1
```

The deep invariant profile uses 1,000 runs at depth 256. The separate Halmos job
uses version 0.3.3, the `halmos` Foundry profile and the bounds recorded in
[CI](../.github/workflows/ci.yml). Both campaigns run on scheduled or manual dispatch.
CI dynamically enumerates every invariant source, splitting the three expensive
Craps suites by named property. A complementary job retains all other tests,
including inherited properties and helpers, so discovery is only a scheduling hint
and cannot silently omit a test. All run/depth settings are preserved, and failed
results are retained (`fail-fast: false`). Run `python3 scripts/deep-invariant-matrix.py`
to inspect the exact partition. Use the symbolic job's command in a
disposable checkout to reproduce Halmos checks.

The two multiway split models use exact nonnegative integer arithmetic with separate
proofs that the admitted products, sums and subtractions fit checked `uint256`
semantics. Their Solidity fuzz carriers remain in the ordinary test selection, and
the bucket carrier calls the production library. A source fingerprint requires
reviewing the model when its production routine or carrier files change. This is
an arithmetic model proof, not a bytecode-equivalence claim.

```sh
pip install halmos==0.3.3
python3 scripts/test-split-arithmetic.py
python3 scripts/check-split-arithmetic.py --json-output .audit-test-logs/split-arithmetic.json
```

Known verification limits:

- Use the current readiness report for completion status. Earlier solver timeouts
  are preserved in local evidence; a timeout establishes neither a counterexample
  nor a proof.
- Halmos 0.3.3's unconstrained GAS model cannot establish production gas-metered
  FSM liveness. Those three production transition carriers remain real-EVM fuzz
  tests, with explicit boundary scenarios; the separate accounting models remain
  symbolic. Liveness evidence comes from the invariant and gas campaigns.
- Imported helper suites can repeat across batches, so execution totals are not
  counts of unique properties. Per-suite budgets and model domains are explicit
  in source; a bounded campaign does not cover every possible state.
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

CI pins Aderyn 0.6.8 through its npm distribution. The older crates.io 0.1.9
release rejects `evm_version = "osaka"` before analyzing any source. Reproduce
the supported analyzer in a disposable environment:

```sh
npm install --global @cyfrin/aderyn@0.6.8
aderyn --version
aderyn . -o aderyn-report.md
```

Analyzer output requires independent triage. Reports and test logs are generated
on demand and are not part of the source handoff.

The fixed 900-unit ticket budget is retired. Current ticket admission uses
`MineFlipGas` and `MineFlipGasBounds`; every atomic operation and complete accumulated
return tail needs a conservative cold bound. Admission uses the remaining worker
allowance and actual available gas, with no fixed transaction ceiling. The 10M
sizing guideline does not replace these checks (see `docs/AUDIT.md`). Historical
measurements and fixture gas limits remain scoped evidence, not universal bounds.

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

## Historical Decimator pack integration (2026-10-05)

Superseded by the single-entry revision below. Counts, storage shape, gas and bounty figures
in this section describe the earlier pack implementation, not the current working tree.

Ordinary x5 rounds (excluding x95) now use one jackpot day, pool eligible ETH/pass
budgets into generated average-stack entry packs, and route unused conversion budget
to solo. Originals plus generated copies determine the paid-place quota:
`min(200, floor(entries/2), max(20, ceil(entries/10)))`, further limited by eligible
copies. The minimum burn is 2,000 whole FLIP; automatic burns use four times the
previous nonempty round's average original stack, with an 8,000-FLIP bootstrap.
Generated packs read the saved board frozen by the existing RNG lock. GameOver
retains its existing behavior; there is no Decimator retirement, cancellation state,
or running uncredited-reserve counter. The generated plan occupies three words.

The final core campaign `20261005T192319.861644Z-75b1b25b` passes all 92 checks
across seven selected roots, with 1,000-run fuzz properties and cold isolation.
It covers tier and funding arithmetic, the half-entrant cap including a lone entrant,
expanded-copy heap and payout parity, tied identities, raw Lens packing, recipient
hash replay, actual board freezing, caller partitions, pool conservation, automatic
burns and degraded consumes. The earlier broader campaign
`20261005T190602.748234Z-15628fc5` passes 92 checks in adjacent jackpot, commitment,
consumer and century-consolidation suites; its three fixture failures (Lens units
and isolated-transaction basefee assumptions) are corrected and covered by the final
core run. Hardhat FLIP unit tests pass all 47 checks in
`20261005T192642.067879Z-539fcf74`. Maintained runners report no source drift and
restore production address pins.

The remaining worker/scheduling campaign `20261005T193113.258533Z-6825e042`
passes all 28 checks with cold isolation. It covers fast/slow x5 scheduling,
excluded levels, original-worker item admission and rollback, and RNG continuity
through all checkpoints. The conservative original-run witness (flat-engine heap
cost plus a 511-roll engine run) is 453,612 gas. Ranking including any admitted
payout tail uses at most 463,428 gas, and the single-payment witness uses 79,211.
All fit their declared admission bounds plus return tails.

The cold real-Miner fixture settles 8,000 originals plus 8,000 generated copies
(1,000 packs), retaining 200 places. With 10 million gas supplied per call, it needs
three calls starting locked (24,355,631 gas) and five starting unlocked (45,208,291
gas). Its largest external call, including the harness wrapper, uses 9,091,916 gas.
The generated real-engine fixture with eight displacements and all 200 owner slots
occupied uses 476,610 gas, below the 1,500,000 indivisible-item admission bound.
These are measured fixtures, not exhaustive maximum-gas proofs; total original
scanning remains proportional to the natural population.

Foundry isolation exposes zero basefee in the measured child transactions, so those
cold runs credit zero bounty. The separate non-isolated campaign
`20261005T193007.628635Z-2de4dcfe` passes both complete Miner campaigns at an actual
1-gwei basefee and 0.02-ETH ticket price. It checks emitted metering against the
production reward formula and the actual credited balance: 616 whole FLIP at the
initial rate without a pass, and 17,350 with an active pass after two hours.
Both take three locked and five unlocked calls. This includes the 1-million-gas
unpaid allowance per call, fee cap/time escalation, and pass/locked multipliers.
Its gas totals differ from the isolated run; reward evidence does not replace the
cold measurements.

The round's first-word packing changes and reference/plan/owner roots are appended.
This implementation requires a fresh deployment, not an in-place storage migration.
The final production build passes with restored production address pins (SHA-256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`).
All 37 deployment entries fit the runtime limit: Decimator is 18,981 bytes,
Jackpot is 23,643, and Game remains 24,539 (37 bytes of headroom). Existing
top-level roots retain their slots, offsets and types; six new roots occupy slots
82–85. The recursive comparison agrees across all 16 Game delegate modules and
the CrapsBattle/JackpotBattle pair. Compiler layouts confirm the two-word round
and three-word generated plan; Lens fuzz checks their packed decoding. The full
632-file Solidity source/test type check and 53 assurance-tool tests pass.
The exported Decimator ABI matches fresh artifacts.
The delegatecall alignment gate now recognizes explicit gas options; its new
positive/negative fixtures verify that a wrong target still fails validation.
The layout oracle, interface coverage and all ten other source gates pass.
Build, size, layout, gate and tooling-test evidence is saved under
`.audit-test-logs/decimator-ready/`; the maintained test campaigns retain their
source manifests and logs under their run IDs above. The audit snapshot records
the current inputs only and does not expand this verification scope.
This is focused implementation verification, not a whole-repository release audit.

## Decimator single-entry revision and Lens owners (2026-10-05)

This supersedes the pack design above. Generated entries are independent single places:
`M=min(N,1000,floor(B*N/P))`, with funding `ceil(M*P/N)`. IDs N+1 through N+M share the
original heap, tie domain and payment loop. The 20-place target, floor((N+M)/2) cap and
200-place ceiling remain. Above 1,000 originals funding tapers; there is no 8,001 cutoff.
Losing generated entries skip recipient, preference, engine and receipt work. The plan is
one storage word. `decWinnerAt` returns score, ordering key and owner for either entry type.

The final settlement campaign `20261005T202811.289538Z-8dc79b9c` passes **155 tests across
35 suites**, from 15 selected roots plus imported suites, with 1,000-run fuzz and cold
isolation. Coverage includes independent single-entry ranking/payment replay, common ties,
50% entrant cap, exact funding and pool conservation, fractional-wei prices, count-cap and
8000/8001 boundaries, mixed/empty cohorts and empty solo completion, frozen preferences,
caller/gas partitions, automatic burns, x00/consolidation, worker checkpoints and RNG
continuity. Both fast and slow closures run through the real public `mineFlip` flow with
actual burn/request/fulfillment/seal/generation/unlock/settlement, without setting the
one-day, daily-lock or final-day flags by hand.

The later Lens-only change passes **34 tests** in `20261005T203807.741544Z-40e0d13d`.
Its 1,000-case owner fuzz uses conflicting values in the unused original/generated owner
source, and integration checks the live retained owners. Settlement code is unchanged by
that follow-up. All **633 Solidity source/test roots** typecheck after the Lens change.

Cold generated gas calibration uses the real Craps preferred-board reader, both fresh heap
insertion and tied replacement, and a separate full 511-roll engine witness:

| Operation | Measured gas | Admission bound |
| --- | ---: | ---: |
| Four-cohort plan plus worker frame | 67,624 | 68,000 |
| Losing entry added to worker frame | 4,468 | 5,000 |
| Generated heap/recipient/board frame plus 511-roll engine | 141,266 + 327,033 = 468,299 | 469,000 |

The existing 80,000-gas checkpoint/return tail is separate. These are measured conservative
fixtures, not exhaustive maximum-gas proofs. Total original scanning still grows with N.
Admission reserves a bound; it charges elapsed gas, not that full bound per item.

The real Miner/engine/preference fixtures, with 10M gas supplied per call, measured:

| Original/generated entries | Calls starting locked / unlocked | Locked / unlocked total gas |
| --- | --- | --- |
| 1,000 / 1,000 | 8 / 5 | 68,664,102 / 36,907,444 |
| 8,000 / 1,000 | 3 / 10 | 23,616,702 / 82,712,372 |

The largest measured external call is 9,427,704 gas including the fixture wrapper. The
Miner fixtures use a Coinflip credit probe and check each emitted reward against the
production formula and the probe's credited balance. Isolation exposes zero transaction
basefee, so a separate non-isolated run `20261005T204101.044687Z-545186ae` passes all **three
reward checks** at a real 1-gwei transaction basefee and 0.02-ETH ticket price: 841 FLIP for
8,000 originals at the initial rate, 1,140 for the full 1,000-original match, and 23,789 for
8,000 originals with an active pass after two hours. Its gas totals differ from isolation.

Fresh production build and all **37 deployment-size checks** pass with restored address
pins (SHA-256 `007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`). Runtime
sizes are Decimator 13,286 bytes, Jackpot 23,646 and Game 24,539. The separately checked
Lens is 11,303 bytes. All 129 pre-existing top-level storage roots keep their positions
and types; four appended fields occupy slots 82–84. The compiler confirms a two-word round
and one-word plan. Intentional nested round-layout changes still require a fresh deployment.
The refreshed golden oracle and recursive layouts agree across all 16 Game delegates and
the CrapsBattle/JackpotBattle pair. The exported Decimator ABI includes winner owners and
matches fresh artifacts.

All eleven source/interface gates pass. The storage-writer extractor now recognizes local
mapping aliases, so the shared heap's actual writes remain registered after deleting the
direct copy-heap path. Three regression tests cover heap aliases, nested mapping deletion
and function-scoped/read-only exclusions; all **56 assurance-tool tests** pass. Evidence is
saved under `.audit-test-logs/decimator-single-entry/` and the maintained campaign IDs above.
The audit snapshot records current inputs only. This is focused integration verification,
not a whole-repository release audit. No deployment or commit was performed.

## Decimator solo whale budget retained (2026-10-05)

This supersedes the solo conversion policy in the earlier Decimator verification sections.
Only active non-solo shares form B; solo has no generated weight or ordinals. Its ordinary
cash and whale-pass award remain, with L=B-F added to cash and no duplicated non-solo dust.
The one-word plan/event/Lens field is now `unspentBudget` (L). No gas constants, RNG tags,
entry identities, eligibility or quota rules changed.

For a 1,000 ETH daily ETH leg and active cohorts: B=400 ETH, solo share=600 ETH,
normal solo cash=451.5 ETH, and whale-pass value=148.5 ETH (66 half-passes). With
N=2,000 and P=140 ETH: M=1,000, F=70 ETH, L=330 ETH; solo cash=781.5 ETH.
Conservation is 70+781.5+148.5=1,000 ETH. Empty cohorts' unpaid amounts use the
existing final-day sweep; empty solo leaves its share and L unpaid too.

Focused campaigns use `scripts/test-foundry-groups.py`, `--threads 1 --fuzz-runs 1000 -v`,
and cold isolation:

- `20261005T205942.437736Z-1ae1ffae`: five selected roots (Integration, AdvanceFlow,
  Gas, LensParity and JackpotCheckpoints), 49 pass and two new-fixture failures. Both
  public fast/slow lifecycle tests, all 11 Lens tests and five normal Jackpot checkpoint
  tests passed on the final contract code. A fuzz input used invalid RNG word zero and
  skipped sealing; the new gas check compared an entire daily frame against a payout-only
  bound. These were corrected in tests without changing contracts or gas bounds.
- `20261005T210243.833739Z-8b3c18c8`: Integration/Gas roots plus imported fixtures,
  **33 pass, zero failures**. Includes 1,000-case conservation over budgets, pot sizes,
  cohort masks and solo rotations; zero solo ordinals/receipts; below/at the solo pass
  threshold; real WhaleModule awards; empty solo; once-only funding; Lens packing;
  replay/payment parity; and atomic solo cash/pass/golden-ticket resume. Together with
  the 18 passing public-flow/Lens/checkpoint checks above, all 51 distinct focused checks
  have passing evidence for this contract version.

Cold gas calibration:

| Operation | Measured gas | Existing admission |
| --- | ---: | ---: |
| Three-cohort plan plus frame | 61,269 | 68,000 |
| Losing generated entry increment | 4,468 | 5,000 |
| Generated frame + full 511-roll engine | 141,350 + 327,033 = 468,383 | 469,000 |
| Solo cash/pass/gold plus completion beyond refused frame | 151,397 | 197,000 |

The cold solo whole frame is 197,365 gas and its identical refused-admission frame is
45,968 gas. The difference includes the award and subsequent daily accounting/completion,
so the existing payout allowance needs no increase. Binary search finds first admission
at 416,091 supplied allowance in this fixture; smaller calls preserve the unpaid checkpoint
and issue no pass. The separate Jackpot return tail remains 180,000; the Decimator tail
remains 80,000. These are measured witnesses, not exhaustive worst-case proofs.

Real Miner, real engine and preferred-board campaigns supply 10M gas per call. The
1,000/1,000 original/generated case takes 8 calls starting locked and 5 unlocked;
8,000/1,000 takes 3 and 10. Largest cold external call is 9,428,780 gas including its
wrapper. Non-isolated campaign `20261005T210444.487084Z-2da8bf89` passes **3/3** at
actual basefee 1 gwei: 844 FLIP for 8,000 originals at the initial rate, 1,141 for
1,000 originals, and 23,811 for 8,000 with an active pass after two hours. Each emitted
reward matches the production formula and Coinflip probe credit.

Fresh production build and all **37 deployment-size checks** pass: Decimator 13,201 bytes,
Jackpot 23,678, Game 24,539; Lens is separately 11,303. The storage oracle matches every
existing golden, and recursive layouts agree across all 16 Game delegates. Renaming
`soloEth` to `unspentBudget` changes no storage offset: it remains uint128 at offset zero
in the 32-byte plan. The exported client ABI reflects the new field/return/event name;
the event type signature and topic are unchanged. All **633 Solidity source/test roots**
typecheck and all **11 source/interface gates** pass.

Every maintained runner restored the production address pins, SHA-256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`. Logs and layout/size
reports are under `.audit-test-logs/decimator-solo-whale/`; the execution notes have the
handoff under **Solo whale budget retained**. The refreshed audit snapshot identifies
inputs only. This is focused verification of the revised integration, not a complete
repository release audit. No commit, push or deployment was performed.

## Decimator shared tags and engine helper (2026-10-05)

Original and generated IDs now share `decimator.battle.final-coin.v1` and
`decimator.battle.board.v1`. IDs remain disjoint, so the eligibility and scatter
probabilities are preserved. Generated outcomes for a given word change from the
previous separate-tag version; replay clients must use the updated domains.
Generated player and recipient domains remain separate. `DecimatorLib.sol` is removed:
quota/eligibility/constants live in DecimatorModule, and the shared terms struct lives
in `IDegenerusGameModules.sol`. Both entry paths use `_settleRun` for the engine call.
The solo whale-pass policy, funding rules, prize cap, storage and public ABI are retained.

Cold-isolated campaign `20261005T211457.876565Z-f69a6927` passes **91 tests across ten
suites**, with 1,000-run fuzz, from eight selected roots: DecimatorBattle,
DecimatorJackpotIntegration, DecimatorAdvanceFlow, LensParity, DecimatorJackpotGas,
DecimatorPricing, DecimatorBattleGas and JackpotCheckpoints. Coverage includes the
common-tag eligibility oracle, exact generated engine arguments, real-engine replay
across caller/gas partitions, both public closure paths, heap/payment parity, funding
and solo-pass conservation, and cold admission. Gas witnesses are:

| Operation | Measured gas | Existing admission |
| --- | ---: | ---: |
| Three-cohort plan plus worker frame | 61,399 | 68,000 |
| Losing generated entry increment | 4,534 | 5,000 |
| Generated frame plus full 511-roll engine | 141,788 + 327,033 = 468,821 | 469,000 |
| Solo award plus completion beyond refused frame | 151,397 | 197,000 |

No admission bound increased. These are measured fixtures, not exhaustive gas proofs.
With the changed deterministic draws, real Miner fixtures still need 8 locked/5 unlocked
calls for 1,000 originals plus 1,000 generated entries, and 3/10 for 8,000 plus 1,000;
10M gas is supplied per call. Their largest cold external call uses 9,422,086 gas.
Non-isolated campaign `20261005T211844.363617Z-563bbf80` passes **3/3** reward checks
at an actual 1-gwei basefee: 864 FLIP for 8,000 originals at the initial rate, 1,182 for
1,000 originals, and 24,373 for 8,000 with an active pass after two hours. Each reward
matches the production formula and credited Coinflip probe balance.

Fresh production build and all 37 deployment-size checks pass: Decimator 13,126 bytes,
Jackpot 23,695 and Game 24,539; Lens remains 11,303. The golden storage oracle matches,
and recursive layouts agree across all 16 Game delegates. Evidence is saved under
`.audit-test-logs/decimator-trims/` and the maintained campaign IDs above.

All eleven source/interface gates pass, and the Decimator client ABI matches the fresh
artifacts without an ABI change. Production address pins are restored (SHA-256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`). The audit snapshot
records the current inputs. This is focused verification; no commit or deployment was made.

## Decimator scale revision (2026-10-05)

This supersedes the capped-entry/coin/leftover-to-solo evidence above. The final field
T=N+M uses exactly min(1000,ceil(T/2)) rotated-stratum survivors. Generated entries are
uncapped up to N; available money is active non-solo shares plus solo's excess over
floor(35% E). Solo receives min(activeNonSolo+soloShare-F,soloShare), with normal passes
on that amount. Solo weight is zero; surplus and inactive shares use the existing sweep.

Maintained runner evidence (all address pins restored after each campaign):

| Campaign | Selection | Result |
| --- | --- | --- |
| `20261005T214804.237264Z-0d3c633c` | 17 focused roots: sampling, integration, gas, Battle, public Advance flow, Lens, pricing, references, schedules, auto-burn, worker/RNG regressions and pool consolidation | 179/179 across 43 suites; 1,000-case fuzz |
| `20261005T215745.527169Z-736bc006` | NativeAtomicDecimator only, cold isolation | 1/1; 424-roll run and heap cost 370,553 gas |
| `20261005T215902.683175Z-710fd1d4` | Three full-match real Miner campaigns, isolation disabled | 3/3 at actual 1-gwei basefee |

The broad run covers both real public fast/slow closing paths; no candidate before final
T/plan; transcript and final-state invariance across caller/gas splits in both phases;
exact W=K and heap/payout oracle; normal solo passes, clipping below the pass threshold,
empty solo and empty non-solo cohorts; P/E/N/activity conservation fuzzing; and uint40
plan/Lens owner ordinals. Conservation is F+solo cash+solo pass funding+unpaid sweep=E.
Solidity boundary sampling includes T=1,2,3,1999,2000,2001,2500 and 2*uint40.max.

The initial scale compile hit a Yul stack-depth error, fixed by caching entries/count/
rotation in a memory struct. The next campaign (`20261005T214432.999157Z-68395e81`)
passed 87/88; its new no-progress fixture supplied only 1,000 gas and triggered the existing
WorkGasBound guard. A 100,000 allowance tests the intended no-plan-progress case and passes
in the final 179-test campaign. No outstanding runtime failures remain.

### Settlement at scale

Cold-isolated real Miner/engine/saved-board fixtures, full match M=N, P=140 ETH,
E=1,000 ETH, sealed word 777. Each call supplies 10M gas. Counts and phase gas are grouped
by the lock state at call start; a call can cross a phase boundary. Setup directly seeds
count and aggregate and writes **only sampled natural entries**, bypassing N burns to
measure settlement rather than entry creation. Every sampled ID is independently checked,
visited exactly once and settled by production code. No generated population is materialized.

| N (and M) | Generated/natural runs | Locked calls | Unlocked calls | Locked gas | Unlocked gas | Total gas | Largest cold item+frame ceiling |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 500/500 | 8 | 5 | 70,619,003 | 37,744,035 | 108,363,038 | 470,854 |
| 10,000 | 501/499 | 8 | 5 | 70,272,429 | 38,173,969 | 108,446,398 | 470,847 |
| 100,000 | 500/500 | 8 | 5 | 70,698,001 | 38,186,372 | 108,884,373 | 470,847 |
| 1,000,000 | 501/499 | 8 | 5 | 70,208,269 | 38,514,487 | 108,722,756 | 470,847 |

The last column is a separately calibrated conservative generated-entry witness at each N:
maximum of a cold tied-heap replacement and fresh-slot insertion frame with a flat engine,
plus a full cold 511-roll engine call (327,033 gas). Keeping the flat call in the sum is
conservative. Subtracting the identical refused frame gives 456,226 gas for the admitted
item at every N, below the unchanged 469,000 bound; the 80,000 tail covers its worker frame.
Largest external campaign calls are 9,412,693/9,420,555/9,417,850/9,420,797 gas respectively.
These are measured fixtures, not exhaustive maxima over all random words.

Other cold witnesses: original run+engine 448,017; ranking frame (including any admitted
payment tail) 460,067; one payment 74,710; solo cash/pass/gold completion 198,378 total,
151,828 beyond its refused frame, below 197,000 admission. Plan/frame 59,983 and skip increment
4,973 reduce their bounds to 60,000 and 5,000. Original 550,000, generated 469,000, rank 500,000,
payment 100,000 and their existing tails are unchanged.

Actual-fee bounties match the production formula and credited balance: 1,171 FLIP for
N=1,000 at the initial rate; 1,170 for N=8,000; 32,911 for N=8,000 with an active pass
after two hours. The cold isolation campaigns correctly observe zero basefee.

### Sampling and build evidence

`python3 scripts/test-decimator-sampling.py` (PyCryptodome Keccak) independently checks
2,000 deterministic random words at each of the eight boundary fields, exact size and
distinctness, and exhaustive rotation symmetry for the small fields. Every ID appears
in exactly S of all T rotations of a fixed unrotated sample. Per-ID frequency deviations
stay below 3.8684 sigma; 100 position bins in the largest field stay below 0.4667 sigma.
The script's word 777 replay vectors match Solidity and Lens. Settlement is bounded by
1,000 strata per phase and at most 1,000 engine runs, through the existing uint40 count limit.

Production build and all 37 deployment sizes pass: Game 24,539 bytes, Jackpot 23,648,
Decimator 13,262; Lens 11,739. Golden layouts match and all 16 Game delegates have identical
recursive layouts. The plan is 32 bytes: soloAmount128@0, weights64@16, generatedEntries40@24,
cursor16@29, mode8@31 (offsets in bytes). The ABI export includes the widened plan/event,
soloAmount semantics and decSurvivorAt. All eleven source/interface gates and all 635 Solidity source/test typechecks pass.
The ABI export check passes; the final audit identity refresh/check records these inputs.

Logs, scale JSON, statistics and recursive layouts are under `.audit-test-logs/decimator-scale/`;
test transcripts are under the maintained campaign IDs above. Production pins use SHA256
`007af42d7a34fa7e9b612bccfeeb1844526d5a960d07d443f17f49554894dbe2`.

### Pre-commit verification (2026-10-05)

One integrated pass on the committed tree, every step under a 30 GB memory scope, logs under
`.audit-test-logs/decimator-commit/` (`summary.txt` holds each exit code). Production pins
were unchanged before, between and after the runners.

| Check | Result |
| --- | --- |
| `forge build --skip test`, `node scripts/check-deployment-sizes.js` | pass; 37 sizes; Game 24,539, Jackpot 23,648, Decimator 13,262 |
| `storage_layout_oracle.sh`, `check_recursive_layout.py` | pass; 16 delegates agree |
| Eleven `make check-*` source/interface gates, `make test-assurance-tools` | pass |
| `scripts/export-decimator-abi.py --check`, `scripts/test-decimator-sampling.py` | pass |
| Foundry campaign `20261005T221343.443306Z-30c002dd`, 18 roots (every new or edited test root: the eight Decimator/Lens/auto-burn fuzz roots, ReviewFixes0924, four repro and five gas roots incl. NativeAtomicWork), cold isolation, 1,000-case fuzz | 181/182 |
| Hardhat `test/unit/FLIP.test.js` (new `autoDecimatorBurn(lvl, cap)`) | 47/47 |

The one Foundry failure, `NativeAtomicDegeneretteTest.test_Max15FlipSpinsAndSurvivalMintFitOneStep`,
predates this change: its fixture bets `100 ether` of zero-decimal FLIP, so the stake units
exceed the 64-bit bound and the bet reverts `InvalidBet`. The Degenerette module and that
half of the test file are unchanged by this work; it is owed with the pre-push battery.
A final interface comment fix was followed by a fresh build, size, interface and ABI-export
check, all passing.
