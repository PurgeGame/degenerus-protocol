# Build and verification

The storage-reuse implementation changes Coinflip to a 90-day retained-page ring, BAF to two
player records and affiliate history to one word. See [storage reuse](STORAGE-REUSE.md) for the
layouts. Results of the full battery on the revision under review: `[final battery]`. Partial
broad runs are not a complete release result.

Run checks against the exact revision supplied for review. The repository contains
source, tests and reproduction tooling; generated logs and analyzer reports stay in
local output directories or CI artifacts.

[The readiness review](AUDIT-READINESS.md) records the current revision. The dated feature
sections below describe how each feature was verified; their pass counts, sizes, gas figures and
storage slot numbers do not certify later revisions, and where one differs from
[the architecture](ARCHITECTURE.md) the architecture document governs.

### DGVE owner governance (2026-10-19)

The owner route now uses escrowed DGVE, revocable voting delegation, and same-block
exclusion. Proposals store a calldata hash and emit the complete action. A controlled
majority can use `directAction` for Vault `playerAction` and `spendDegenesis`; all other
owner actions require proposals. Positions occupy two slots and proposals four.

The focused Foundry run passes 56 tests, including the real-protocol purchase route
and the invariant handler (256 runs, 32,768 calls). The four Hardhat governance tests
pass, covering distinct transactions in the same block, verified event-based calldata
recovery, and CLI discovery of current delegates. The reference model passes 27 directed
scenarios and both randomized campaigns, with 230 proposal executions and 186 direct actions.
The complete default Hardhat selection passes: 97 files, 1,618 tests, no failures or
pending cases. The batched default Foundry selection covers all 623 selected source
roots: 5,434 distinct test cases pass, with two opt-in checks skipped (repricing fixture
export and archived growth/foil runtime comparison). Counts deduplicate imported suites;
passing reruns cover the corrected ownership fixtures. The gas selection also completes
with transaction isolation enabled across 85 files. Mainnet-fork, deep-profile and Halmos
symbolic lanes were not run for this change; these results are not a deployment
certification. Removing the Vault's private owner predicate produced identical
executable Vault and governance bytecode.

Measured on Hardhat with solc 0.8.34, via-IR, optimizer 1000 and Osaka: a repeated
Vault ticket purchase costs 175,887 gas through two delegated thirds, compared with
153,515 for the same underlying Vault call at the same state (22,372 gas overhead).
Initial approvals and delegated deposits total 301,368 gas. Without a common voting
controller, the repeated two-holder proposal cycle totals 429,836 gas. These figures
cover the specific 400-unit ticket purchase with 0.01 ETH of Vault funding; other
actions and owner-list sizes have different costs.

Reproduce the focused checks with `scripts/test-foundry-groups.py --file
test/governance/OwnerGovernance.t.sol --file test/governance/OwnerGovernanceInvariant.t.sol
--file test/governance/OwnerGovernanceProtocol.t.sol --file test/fuzz/DegenesisVaultSpend.t.sol`
and `scripts/test-hardhat-groups.py --file test/unit/OwnerGovernance.test.js`. Run these
in separate checkouts if concurrent. The production structural gates include
`check-owner-actions.js`, `check-owner-governance-layout.js`, the existing Vault player
allowlist, deployment-size checks and the storage-layout oracle.

### Compact lootbox orders (2026-10-17)

One box type per purchase; three 85-bit orders per queue word (see `docs/ARCHITECTURE.md`).
Gas measured in isolated transactions (`FOUNDRY_ISOLATE=true`, Osaka, solc 0.8.34 via-IR):

| Workload | Gas |
| --- | ---: |
| Box append, lane 0 of a fresh word (`LootboxQueueGas`) | 147,341 |
| Box append, lane 0 of a recycled word | 130,241 |
| Box append, lane 1 or 2 (fresh or recycled buffer) | 130,244 |
| One 100-small order, settled (`drain_one_entry_100_smalls`) | 1,245,027 |
| Cold atomic 100 × 10 ETH order, sweep peak (`HumanOrderNativeGas`) | 2,742,070 of 15,700,000 admitted |
| 100 × 2,000 ETH order at every modifier ceiling (`LootboxOpenBounds`) | 1,846,307 |
| Repriced fresh-cap peak including state gas (80 fixtures) | 7,318,463 |
| sDGNRS whale stage increment, 100 / 1,000 passes, with the top-up (`SdgnrsWhaleBuyStageGas`, cooled accounts in one test transaction; 726,951 / 802,539 Osaka when isolated) | 453,351 / 528,939 Osaka; 1,588,771 / 1,664,359 repriced with state gas |
| Player whale purchase, 1,000 passes, registered / fresh wallet | 1,799,231 / 1,950,919 |

A lane-1/2 append replaces a fresh-slot write with a warm read-modify-write of the word its
lane-0 order cleared, so growth past a buffer's high-water mark saves one new slot per two of
three orders; recycled appends cost the same as before. `LootboxEvLifecycleGas` slot counts
follow: four same-wallet or distinct-wallet orders create two fewer slots. Settlement reads
each order's word again (a warm slot); no word cache is kept. The admission constants are
unchanged: `SUBSCRIBER_WHALE_GAS` (2.8M) covers the 1,000-pass sDGNRS purchase, which shares
the 200-group cap with the player route.

### Degenesis sale verification

The Degenesis sale ([architecture](ARCHITECTURE.md#degenesis-sale)) is verified against the 21
acceptance checks of its design. Results are recorded with the battery that covers this source;
until then this section lists what each check must show, not pass counts.

| Area | Must show |
| --- | --- |
| Outcomes | Categories 50/40/10 from separate tags on `hash4(DEGENESIS_ORDER_DOMAIN, word, day << 32 \| index, walletId)`; independent FLIP and sDGNRS size rolls; an order never receives both; a FLIP result below one whole FLIP, a lost sub-pass fraction and a zero sDGNRS award pay the 1-WWXRP consolation |
| sDGNRS bound | For every cohort, awards never exceed `1.5Q <= pool`; `Q = min(2.5T, 2/3 pool)`; a 9 ETH and a 1 ETH order have a 9:1 expected ratio before rounding; reordering or partitioning settlement calls changes no reward |
| FLIP scale | Day schedule, early bonus (opening, three hours, six hours, day boundaries) and `K / (K + V)` volume factor match the formula; splitting or reordering purchases in a cohort leaves the scale unchanged; the nominal mean stays under `K x sum(base) x 1.05` |
| Credit | 25% of ETH, claimable and prepaid spend while the window is open, once per qualifying spend; none for FLIP-paid parts, AFKing deliveries, Degenesis purchases, the Vault or sDGNRS |
| Purchase | 0.01 ETH minimum, 0.0001 ETH units, the 38-bit per-order bound reverts rather than truncates; the Vault wallet ID cannot buy, including through an operator; no affiliate, quest, streak or activity credit |
| Accounting | `claimablePool` holds unsplit volume; the split is exact in wei (half to the future pool, quarters to the Vault budget and sDGNRS AFKing); fresh, claimable and prepaid funding conserve obligations |
| Pricing order | A cohort prices only after the previous one closed; a backlog delays the binding word and never lowers the rate; empty cohorts and zero inventory follow the stated rules; late keeper calls are replay-safe |
| Vault and sDGNRS | `spendDegenesis` is atomic, exact-cost and owner-only, leaves no withdrawable balance, handles the 1-wei sentinel, and reverts for a non-Vault caller or `maxCost` above the budget; the sDGNRS top-up conserves `claimablePool`, persists when no group is bought and runs before the whale attempt |
| Engine | Degenesis days unlock randomness only; neither `lastPurchaseDay` latch fires before day 9, however late the day is cranked; the day-9 request latches the early turbo only above the level-1 target; craps windows and battle locks start on day 2; day 7's battle awards no seats; foil is unchanged |
| Terminal | Both endings split every cohort and release the Vault budget and sDGNRS AFKing funding exactly once, before `gameOver`, with no loss of player claims; unresolved orders are forfeited |
| Burn | The seventh close burns the remaining `Pool.Degenesis` balance exactly once, after every reservation is released, including an empty final day and a sale with no orders |
| Gas | Per-branch admission and the flush reserve cover the measured worst case of each branch; the bounds are the constants in `contracts/libraries/MineFlipGasBounds.sol`. `test/gas/DegenesisGas.t.sol` must show each forced branch, flush, tail, request step, word copy, day close and terminal addition within its bound on Osaka and on the no-reservoir Glamsterdam total, and every checkpoint under 10M execution gas. Suite and test counts: `[final battery]` |

Suites (all under `test/fuzz/` unless noted): `DegenesisCohortMath`, `DegenesisSettlement`,
`DegenesisSettlementInventory`, `DegenesisDayMapping`, `DegenesisClosingBurn`, `DegenesisWordBinding`,
`DegenesisFlipSchedule`, `DegenesisLanes`, `DegenesisSmurfPayee`, `DegenesisCredit`,
`DegenesisAccounting`, `DegenesisVaultSpend`, `DegenesisSdgnrsTopUp`, `DegenesisTerminal`,
`DegenesisDailyEngine`, `DegenesisCraps`, `DegenesisFoil`, `CombinedDegenesisBoxFunding`, the
Degenesis variants in `invariant/V61SolvencyAfpay.inv.t.sol` and `invariant/WalletIdTruth.inv.t.sol`,
`test/craps/CrapsPasses.t.sol`, `test/craps/JackpotBattle.t.sol` and `test/gas/DegenesisGas.t.sol`.

Structural gates cover the new module's selectors and delegatecall pairs, the layout goldens in
`scripts/layout/golden` (the Game's `degenesis*` fields and CrapsBattle's `_firstWindowDay`), the
storage slot pins and the source manifests. Runtime sizes are checked by the deployment-size gate;
the margins for this revision are `[final battery]`.

### Lootbox EV allowance at opening (2026-10-15)

Baseline: `b80dab839`, rebuilt in a detached checkout. Ordinary purchases and pass/cover
grants now freeze score and modifiers without drawing allowance. Opening draws once per
order, before nested rewards, against the live opening level; sizes still use the stored
purchase level. Redemption uses the same order draw without a separate charge. Daily AFKing,
direct-box arithmetic, and the protocol-owned daily-box exemption retain their existing rules.
The queue's old EV-fraction lane is reserved zero; no storage fields or slots were added.

`LootboxEvLifecycleGas.t.sol` runs identical fixtures on both revisions with solc 0.8.34,
via-IR, optimizer 1000, Osaka and `FOUNDRY_ISOLATE=true`. Purchases and the opening call
are separate transactions; each uninstrumented measurement is replayed from the same snapshot
to collect accesses for `GlamsterdamReprice`. The table reports isolated call gas, excluding
fixture setup, RNG publication and transaction intrinsic gas. The opening fixture invokes
the production worker through `QueueHost`; ordinary buys use the real purchase entrypoint.
Pass/cover rows measure their shared production grant path. Four-order rows measure four
separate purchases followed by one opening call. Manual + AFK includes both settlements.

| Workload | Purchase before / after | Opening before / after | Combined before / after | Repriced combined delta, including state |
| --- | ---: | ---: | ---: | ---: |
| Fresh bonus | 367,267 / 342,989 | 92,887 / 115,086 | 460,154 / 458,075 | −2,079 |
| Existing allowance | 350,110 / 342,989 | 92,887 / 97,929 | 442,997 / 440,918 | −2,079 |
| Taper | 350,268 / 342,989 | 92,887 / 98,087 | 443,155 / 441,076 | −2,079 |
| Exhausted | 346,205 / 342,989 | 92,887 / 93,999 | 439,092 / 436,988 | −2,104 |
| Low score | 353,185 / 352,420 | 92,784 / 92,847 | 445,969 / 445,267 | −702 |
| Mixed tiers | 367,303 / 343,025 | 151,668 / 173,847 | 518,971 / 516,872 | −2,099 |
| 100 small boxes | 367,050 / 342,772 | 1,131,093 / 1,153,256 | 1,498,143 / 1,496,028 | −2,115 |
| Four orders, same wallet | 725,726 / 686,085 | 267,975 / 296,902 | 993,701 / 982,987 | −32,314 |
| Four distinct wallets | 1,171,166 / 1,080,054 | 234,372 / 323,170 | 1,405,538 / 1,403,224 | −2,314 |
| Cover grant | 87,014 / 63,064 | 91,916 / 113,595 | 178,930 / 176,659 | −2,271 |
| Three-box pass grant | 87,046 / 63,096 | 163,940 / 186,138 | 250,986 / 249,234 | −1,752 |
| Nested ETH spin | 367,267 / 342,989 | 93,441 / 115,640 | 460,708 / 458,629 | −2,079 |
| Manual + daily AFK | 367,267 / 342,989 | 117,873 / 137,245 | 485,140 / 480,234 | −12,106 |

The representative workloads total 8,023,484 → 7,986,191 Osaka gas (−0.465%) and
24,619,824 → 24,553,731 under the repository's repricing model including state gas
(−0.268%). Every workload creates the same number of storage slots as its baseline.
The test pins these baselines and enforces both ≤1,000 extra gas per order and ≤1% per
workload under each schedule, plus unchanged new-slot counts. These are measured samples,
not a claim that every entropy/outcome or economic interleaving has identical gas.

Opening admission is checked independently in `HumanOrderNativeGas.t.sol`: fresh allowance
slots, single and 100-box orders, maximum custom sizes and nested spins. The native
100 × 10 ETH sweep peaks at 2,746,022 gas against its 8,500,000 entry bound. The worker's
measured overhead outside the atomic entry peaks at 7,274 against its 80,000 tail reserve. `HUMAN_ENTRY_GAS`
remains 1,300,000. Repricing uses uninstrumented execution gas and a separately recorded
replay, with the fresh cap slot included. Across 80 repriced fixtures (five order shapes,
16 words each), peak execution is 2,032,581 gas; peak including state gas is 7,320,261.
The smallest measured headroom below an entry's execution admission bound is 1,263,734.

The Hardhat gas suite also passes through real `mineFlip` transactions: 203,226 gas for
one ordinary box; 1,252,577 and 1,194,862 for two 100-box orders opened in separate
transactions. Its old 4.85M fixture allowance was updated to 9M to admit the already-existing
8.5M maximum-entry bound. Production admission constants were not increased.

Fresh production builds pass EIP-170 for the entire deployment set. Changed runtime sizes:

| Module | Before | After | Remaining bytes |
| --- | ---: | ---: | ---: |
| Whale | 24,534 | 24,474 | 102 |
| AFKing | 24,201 | 24,172 | 404 |
| Mint | 23,651 | 23,620 | 956 |
| Lootbox | 18,098 | 18,000 | 6,576 |

The recursive layout comparison reports no baseline changes and all 16 Game modules match
Game storage. Interface coverage, delegatecall alignment, raw-selector, RNG-window,
pool-write, array-delete, advance-call, RNG-taint, unchecked-block, write-owner and gasleft
checks pass. Production size checks validate source hashes against artifact metadata.

The selected Foundry campaign and focused corrective reruns finish with 169 distinct tests
passing across 20 suites, plus the two Hardhat gas tests. This includes purchase/cover/boost
regressions, ordinary and redemption commitment binding, Degenerette allowance, nested DGNRS
ordering, subscriber/queue/native gas, resumption and the box-enqueue invariant suite. Each
of its three invariants ran 256 campaigns of depth 128 (32,768 handler calls, zero reverts).
The minimum-budget resumption fixture now re-measures each checkpoint instead of assuming
the first call's exact minimum applies to every later wallet and engine state.

Behavioral coverage includes buy-after-publication, opening-level allowance with stored prices,
one aggregate draw before nested rewards, 1,000 taper fuzz cases, neutral/exhausted no-write
paths, rollback/retry, grant rounding, and deterministic split processing. Grant dust can
change the rounded eligible fraction by a basis point; `LootboxEvAtOpen.t.sol` pins the
1 ETH + 1 wei boundary. AFK-first consumer ordering now allocates allowance before queued
human boxes. Immediate foil-recirculation interleavings remain possible; no claim lock or
parked-redemption behavior was changed.

Reproduce the lifecycle and opening checks with:

```sh
FOUNDRY_ISOLATE=true python3 scripts/test-foundry-groups.py \
  --file test/gas/LootboxEvLifecycleGas.t.sol \
  --file test/gas/HumanOrderNativeGas.t.sol \
  --file test/fuzz/LootboxEvAtOpen.t.sol \
  --file test/fuzz/LootboxBudgetResume.t.sol --threads 4 -vv
npx hardhat test --no-compile test/gas/LootboxOpenGas.test.js
forge build --skip test --out forge-out-production --cache-path .foundry-cache-production
node scripts/check-deployment-sizes.js forge-out-production
```

## Setup

Use Node 20 and Python 3.12 to match Hardhat CI, plus Bash, Git and Foundry.
Install local Python packages in a virtual environment. Solidity 0.8.38, via IR,
1,000 optimizer runs and EVM Osaka are set in both compiler configurations.
The npm dependencies and forge-std revision are locked in the repository. Foundry
CI pins `nightly-c07d504b4ae67754584f4e05ff0c547a43c50f7b`, the build used by
the audit campaign. Record the actual version when reproducing a run; use the
same release for comparable gas and invariant evidence.

Two deployment profiles exist. `eip170` is the default, the deployment target and the primary audit
target: 37 deployment entries, checked against the 24,576-byte runtime and 49,152-byte initcode limits
(`contracts/profiles/eip170/`, `deployments/eip170.json`). `glamsterdam` is the alternate: 21 entries
checked against 65,536 / 131,072 bytes with `--schedule glamsterdam` (`contracts/profiles/glamsterdam/`,
`deployments/glamsterdam.json`). The
`PROFILE` environment variable selects the profile (unset means `eip170`). `node scripts/select-profile.js`
regenerates the selected-profile sources (`contracts/profiles/Selected.sol`, `contracts/Coinflip.sol`),
both `deployments/<profile>.json` files and the profile deploy scripts, then writes fixture address pins;
`--no-pins` skips the pins and `--check` fails if a generated file is stale. The maintained Foundry and
Hardhat runners honor `PROFILE` and restore the generated files they touched. To run the alternate
profile, set `PROFILE=glamsterdam`; Hardhat additionally needs `CONSOLIDATION_CANDIDATE=true`
(`allowUnlimitedContractSize` in `hardhat.config.js`), and Foundry needs `FOUNDRY_PROFILE=consolidation`
so fixtures can embed the larger deployment code (see `scripts/consolidation/README.md`). The default
profile needs neither.

The Foundry runner rebuilds a coherent artifact set for each physical batch.
Incremental artifacts from a different selection can otherwise disagree with the
handler runtime embedded in a cached invariant test. Both runners fingerprint
symlinked library directories, stop directory cycles and fail on dependency drift.
CI limits ordinary batches to five roots without reducing test or fuzz budgets.
The runner defaults to `-vv`; an explicit verbosity flag replaces that default.
CI uses the default. Forge adds verbosity flags, so combining `-vv` and `-vvv`
would enable level-five traces and can exhaust memory on large suites. Rerun an
individual failing case with higher verbosity when a trace is needed.

```sh
git rev-parse HEAD
node --version
forge --version
python3 scripts/audit-snapshot.py
npm ci
python3 -m pip install safe-pysha3==1.0.5
git submodule update --init --recursive
```

The Python dependency supplies Keccak for the independent wild-color vector
generator. The Hardhat suite checks that the committed vectors match this generator.

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
node scripts/check-owner-actions.js forge-out-production
node scripts/check-owner-governance-layout.js forge-out-production
node scripts/check-vault-player-actions.js forge-out-production
make CHECK_ARTIFACTS=forge-out-production check-interfaces check-delegatecall \
  check-raw-selectors check-rng-window check-pool-writes check-array-delete \
  check-advance-calls check-rng-taint check-rng-shape check-unchecked \
  check-write-owners check-gasleft check-memory-guard check-recipient-calls
make check-audit-snapshot test-assurance-tools
```

The size gate checks every deployment entry of the selected profile (plus the vault share
tokens and the two lens contracts) against the runtime and initcode limits of its schedule
(`eip170`, the default: 24,576 / 49,152 bytes; `--schedule glamsterdam`: 65,536 / 131,072),
runs the memory-guard check, and rejects stale, missing or unlinked artifacts. Address pins affect compiled output;
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
uses eight logical groups (`integration-gas`, `repro-symbolic`, `census`, `fuzz-1` to `fuzz-4`,
`invariants`) plus the `fork` group, which runs only when named; Hardhat defaults to one test file
per process (`--max-files`).

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

CI runs seven of the Foundry groups (all but `census` and `fork`) in separate jobs; the fork suite has its own job. The other six groups
use isolation disabled, at most five roots per batch and one thread. The default fuzz campaign uses 1,000 runs; default
invariants use 256 runs at depth 128, with per-suite overrides visible in source.
`npm test` uses the maintained Hardhat runner, including all statistical files.
Discovery fails if a JavaScript test is outside the configured directories.
`npm run agent:test` runs the separate local agent unit suite when the ignored
`agent/` working tree is present; it is not part of the public checkout. Focused `npm run test:*`
commands use raw Hardhat and therefore bypass runner-level pin restoration.

See [the test usefulness review](TEST_REVIEW.md) for retired checks, repaired
fixtures and the distinction between model, structural and runtime coverage.

Gas admission rests on a proven cold-path bound for each operation, not on a fixed gas
figure or transaction ceiling; see [the audit scope](AUDIT.md).
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

Ticket admission uses `MineFlipGas` and `MineFlipGasBounds`; every atomic operation and
complete accumulated return tail needs a conservative cold bound. Admission uses the
remaining worker allowance and actual available gas, with no fixed transaction ceiling
(see `docs/AUDIT.md`). Historical measurements and fixture gas limits remain scoped
evidence, not universal bounds.
