# Build, tests and gates

Run commands from the repository root. [AUDIT.md](AUDIT.md) defines the EIP-170 audit target;
[source-sha256.txt](audit/source-sha256.txt) authenticates inputs, not test outcomes.

## Setup and sliced build

CI uses Node.js 20 and Python 3.12 and pins Foundry
`nightly-c07d504b4ae67754584f4e05ff0c547a43c50f7b`; the compiler is Solidity 0.8.38 with via IR,
1,000 optimizer runs and Osaka. The lockfile selects Hardhat 2.29.1, Handlebars 4.7.10 and
OpenZeppelin 5.4.0. Install `safe-pysha3` for the independent wild-color vectors.

```sh
npm ci
git submodule update --init --recursive
python3 -m pip install safe-pysha3==1.0.5
export AUDIT_SCRATCH="${TMPDIR:-/tmp}/degenerus-audit-build"
mkdir -p "$AUDIT_SCRATCH"
export FOUNDRY_CACHE_PATH="$AUDIT_SCRATCH/cache"
export FOUNDRY_OUT="$AUDIT_SCRATCH/out"
export AUDIT_LOG_DIR="$AUDIT_SCRATCH/logs"
PROFILE=eip170 node scripts/select-profile.js --no-pins
node scripts/select-profile.js --check
python3 scripts/test-foundry-groups.py --file test/unit/EthLedgerProductionReplay.t.sol \
  --log-dir "$AUDIT_SCRATCH/logs/smoke" --threads 1
```

The Foundry runner compiles slices to bound memory. Both runners reject empty selections and restore
original address pins and generated profile sources on completion, failure or handled interruption.
Use one compiler at a time in a checkout. Raw Forge/Hardhat commands do not provide the runner's
address-patching lifecycle. `--no-pins` selects the profile without changing deployment addresses.

## Production build and artifact gates

Use the sliced test above for an initial smoke check.
Artifact gates require a complete production build, with a separate output/cache pair from fixture
builds. Choose an empty pair if these paths contain unrelated artifacts. Exported `FOUNDRY_OUT` and
`FOUNDRY_CACHE_PATH` take precedence over `--out` and `--cache-path`, so the production build and
the peripheral check's probe build below unset them.

```sh
env -u FOUNDRY_OUT -u FOUNDRY_CACHE_PATH forge build --skip test --threads 1 \
  --out "$AUDIT_SCRATCH/production-out" --cache-path "$AUDIT_SCRATCH/production-cache"
node scripts/check-deployment-sizes.js "$AUDIT_SCRATCH/production-out"
CHECK_ARTIFACTS="$AUDIT_SCRATCH/production-out" bash scripts/layout/storage_layout_oracle.sh
python3 scripts/layout/check_recursive_layout.py --out "$AUDIT_SCRATCH/production-out" \
  --report "$AUDIT_SCRATCH/recursive-layout.json"
XA_PROBE_OUT="$AUDIT_SCRATCH/xa-probe-out" env -u FOUNDRY_OUT -u FOUNDRY_CACHE_PATH \
  python3 scripts/layout/check_peripheral_layouts.py "$AUDIT_SCRATCH/production-out"
node scripts/check-owner-actions.js "$AUDIT_SCRATCH/production-out"
node scripts/check-owner-governance-layout.js "$AUDIT_SCRATCH/production-out"
node scripts/check-vault-player-actions.js "$AUDIT_SCRATCH/production-out"
make CHECK_ARTIFACTS="$AUDIT_SCRATCH/production-out" check-interfaces check-memory-guard
```

The size gate checks selected deployment hosts, share tokens and lenses, rejects stale/unlinked
artifacts and invokes the memory-guard gate. Storage checks compare top-level slots and recursively
compare Game delegates and Craps lifecycle delegates with their respective storage hosts. Repeat
deployment checks with the intended production addresses; fixture pins are not deployment addresses.
The retained Glamsterdam files remain outside the contest target.

## Source and tooling gates

```sh
python3 scripts/check-docs.py
make check-audit-snapshot
make check-delegatecall check-raw-selectors check-rng-window check-pool-writes \
  check-array-delete check-advance-calls check-rng-taint check-rng-shape \
  check-unchecked check-write-owners check-gasleft check-recipient-calls
make test-assurance-tools
python3 scripts/check-eth-loan-bootstrap.py --json-output "$AUDIT_SCRATCH/loan-bootstrap.json"
```

Compiler-AST gates need the pinned compiler installed. Manifests detect unclassified or changed
sites; passing a classification gate does not prove its annotations correct. Documentation
references can be regenerated and checked with `scripts/generate-audit-references.py` as described
in [Module map](MODULE-MAP.md) and [Storage packing](STORAGE-PACKING.md).

## Test selection

```sh
python3 scripts/test-foundry-groups.py --list
python3 scripts/test-hardhat-groups.py --list
python3 scripts/test-foundry-groups.py --max-files 5 --threads 1 \
  --log-dir "$AUDIT_SCRATCH/logs/foundry"
python3 scripts/test-hardhat-groups.py --log-dir "$AUDIT_SCRATCH/logs/hardhat"
```

Foundry's default groups are `integration-gas`, `repro-symbolic`, `census`, `fuzz-1` through
`fuzz-4`, and `invariants`; CI runs `invariants` as `invariants-1` through `invariants-6` and
`integration-gas` as `integration-gas-1` and `integration-gas-2`. Forks are opt-in. The runner
selects CI's isolation mode per source, including the two cold fork suites, and splits mixed
selections into separate batches. `FOUNDRY_ISOLATE` or Forge's `--isolate` explicitly overrides that
choice; run metadata records the effective settings. `--file` selects a source and is repeatable.
Hardhat defaults to one file per process; its runner includes statistical suites and rejects
unassigned test files. Run artifact/source gates as well; `make test-foundry` and `make
test-hardhat` include the structural prerequisites.

| Review area | Focused input |
| --- | --- |
| Ledger helpers | `test/unit/EthLedgerProductionReplay.t.sol` |
| Immediate pass-backed loan bound | `test/unit/EthLoanBootstrap.t.sol` |
| Full-width quest version and 256-level stale-state regressions | `test/fuzz/QuestActivePacking.t.sol`, `test/fuzz/QuestsWalletIds.t.sol` |
| Mature loans, redemption and terminal composition | `test/repro/MatureComposition.t.sol` |
| Terminal checkpoints | `test/repro/TerminalPayoutCheckpoints.t.sol` |
| Paid mining through level 31 | `test/gas/NativePaidLifecycle.t.sol` |
| Subscriber gas/refusal recovery | `test/gas/SubscriberAdmissionRecovery.t.sol` |
| Solvency, RNG freeze and liveness | `test/fuzz/invariant/` |
| Coinflip bank, carry and ride-bonus ledger | `test/fuzz/invariant/FlipCarryAccounting.inv.t.sol`, `test/fuzz/invariant/FlipCarryDegenesis.inv.t.sol`, `test/fuzz/invariant/FlipCarryWidths.inv.t.sol` |
| Mining-call judge and first-unit admission gas | `test/fuzz/helpers/ChainCallJudge.sol`, `test/fuzz/ChainCallJudge.t.sol` |
| Unjustified endings | `test/fuzz/helpers/EndingWitness.sol`, `test/fuzz/EndingWitnessTarget.t.sol`, `test/fuzz/invariant/AdvanceLiveness.inv.t.sol`, `test/fuzz/invariant/AnyInputSafety.inv.t.sol` |
| 100-box human order inside one transaction | `test/gas/HumanOrderNativeGas.t.sol` |
| DGVE governance | `test/governance/` |

A bounded test run does not establish a universal proof. Imported helper suites may execute in
multiple batches, so execution totals are not distinct-property counts. Arithmetic models, source
guards and printed gas measurements need corresponding production-path assertions. Ordinary Forge
execution does not prove Halmos `check_*` properties.

Quest packing tests inspect the 24-bit version in bits 136–159 of `activeQuestsPacked` and
bits 0–23 of the player word. Player progress occupies bits 24–151; completion and growth flags
occupy bits 152 and 153. Actual level rolls check that 256 transitions neither revive old completion
nor prevent a fresh growth reward. See [Storage packing](STORAGE-PACKING.md).

The four Degenerette math suites use `test/helpers/degeneretteMathFixture.js` to install the compiled
pure-math wrapper runtime at a synthetic address. The wrapper inherits a complete production module.
These tests exercise its pure functions without constructor state; they do not test wrapper
deployability. Production size gates still apply. Both the source manifest and Hardhat runner
authenticate test vectors, tables and module helpers; the runner rejects their creation, removal or
modification during a run.

## Mainnet forks and deep invariants

Set `MAINNET_RPC_URL` to an archive endpoint with state at the block in `test/fork/ForkPins.sol`.
Keep credentials out of shared logs.

```sh
python3 scripts/test-foundry-groups.py --group fork --threads 1 \
  --log-dir "$AUDIT_SCRATCH/logs/fork"
FOUNDRY_PROFILE=deep python3 scripts/test-foundry-groups.py --group invariants \
  --max-files 5 --threads 1 --log-dir "$AUDIT_SCRATCH/logs/deep"
```

The fork runner applies real dependency addresses and selects isolation by suite.
`test/fork/ForkStethRedemptions.t.sol` covers full and partial Vault exits, native sDGNRS exits,
both wrapped exit entry points, open/closed redemption claims and GNRUS exits against Lido share
rounding. It bounds rounding loss using real Lido shares with seeded protocol boundary state.
GNRUS coverage does not establish that GNRUS shares the Vault/sDGNRS failure mode. These fixtures
do not prove a complete lifecycle or resilience to arbitrary external asset failure. The fork's
stand-in VRF delivery calls back with exactly the request's own callback gas limit, recovered from
the real coordinator's commitment for that request.

Defaults are 1,000 fuzz cases and 256 invariant runs at depth 128. `deep` defaults to 1,000
invariant runs at depth 256; explicit per-test overrides apply. CI partitions expensive suites with
`scripts/deep-invariant-matrix.py`, including twenty independently seeded AdvanceLiveness partitions
of 50 runs each.
Coverage guards and actual run/call counts matter as well as pass counts.

Except in AnyInputSafety (with its Degenesis variant), AdvanceLiveness and DegenesisLiveness,
stateful handlers route every `mineRun` they would otherwise swallow through `ChainCallJudge`, and
those suites assert `judgeCheck` and run `ChainStallProbe`. AnyInputSafety does not judge mining
reverts; it judges terminal latches (below). AdvanceLiveness applies its own liveness and quiescence
checks, and DegenesisLiveness judges each mining call inline against the selected action and its
`MineFlipAdmission.minGas`. Where a site does not cap gas itself, `ChainCallJudge` reads
`minerAction()` as the same caller and calls with gas drawn from that action's
`MineFlipAdmission.minGas` up to 2^24 − 21,000 (a quarter at the minimum, a quarter within 300,000
above it, the rest up to the cap). Idle must answer `NoWork` and Wait `RngNotReady`; any other
selected action must make progress, so a gas refusal at or above the minimum is a violation. Every
successful judged or capped call (at most a transaction's gas) is recorded with Foundry's state-diff
recording and must commit work: some storage slot must end the call with a value different from the
one it started with, outside the caller's FLIP reward credit. The one success that may commit
nothing is a refused request or terminal attempt (the selected action is a request or Terminal, and
an inner call reverted). An action whose declared minimum exceeds the cap, the 100-box human order,
is drawn at the cap; `HumanOrderNativeGas` separately completes a maximum order cold inside one
transaction. Half the judged calls draw a calibration (0.25x, below 1x, above 1x or 4x): below 1x a
gas refusal is accepted, since a continuation admitted on a scaled estimate may overrun and roll
back its worker, and at 1x and above the rule is unchanged. `judgeCheck` also fails when a
dependency mock records a call that arrived below the protocol's admission. While work remains, an
ample call of 2^32 gas follows, so handlers keep their pace; that pacing call is counted and must
not revert, but is not checked for committed work. Once a run records a call, Foundry records every
storage access until the run ends, so the judge switches off the mapping-slot recording that
state-diff recording also starts and drops each call's record after it. At the end of every run
`ChainStallProbe` drives the engine to quiescence on a snapshot in transaction-sized calls,
delivering outstanding VRF words; every success must commit work, a ticket call that strictly lowers
the active read queue's owed total is ranked, and any other call spends a 1,000-call budget, so work
that changes state without finishing is flagged. The drain is one transaction, whose writes Foundry
holds until it ends, so a ranked drain stops, accepted, once it has spent 100 billion gas or the
test's gas runs short; AdvanceLiveness's deep replays drain the largest known backlog in full.
`EndingWitness` re-derives the 14-day deadman, the 14-day unpublished request and the 30-day
purchase timeout, including the next-pool target and its century floor, from raw storage:
AdvanceLiveness and AnyInputSafety fail when terminal state latches with no ending due, and
AdvanceLiveness also requires an idle, sealed day to have requested its wall day and stamped its
completion. AnyInputSafety's guided claim doors steer claims that random input does not reach to
acceptance and check each accepted claim's effect. The FlipCarry suites hold an independent model of
each tracked player's wallet, bank, carry, cursor and auto-rebuy settings; after every action raw
storage must equal the model and the tracked ledger must balance.

AdvanceLiveness allows 500 mining calls per cycle; a cycle restarts when the logical day advances.
Past that budget, with an active ticket queue of 1–4,096 holders, it requires a ranking function
instead of a count: for 100 calls the queue's owed total must fall on every ticket call and rise on
none (at most four other calls), and only then is each holder cut to 1,024 entries inside the check's
snapshot, verified through `entriesOwedView`, and a new cycle granted so the rest of the judgment
runs. Two typed replays of persisted deep
failures pin this: a Degenerette-jackpot backlog that is compressed, and a far-future backlog that
drains inside the window. The cut leaves the campaign a smaller tail than the one it ranked, so the
deep profile also replays the jackpot backlog without it: about 25,900 calls drain the real queue
with every ticket call ranked, and a self-check that stalls only after 23,000 honest calls (about
90% of the drain) must be flagged; the cut drain never reaches that stall. Non-vacuity floors that
a single run can legitimately miss (for example a run that reaches the dead-VRF ending before any
Degenesis cohort is priced) accumulate across runs.

The Degenesis completion driver drains at the same timestamp when a 300-call chunk fills with work
still ready. Its healthy completion path is bounded by 40 chunks / 12,000 calls, with independent
deadline and terminal-retirement assertions. `test/helpers/DegenesisCompletionReplay.sol` supplies a
preserved 121-call trace to `test/fuzz/invariant/DegenesisLiveness.inv.t.sol`; the regression checks
that draining ready work does not manufacture a deadline by advancing the clock. Ordinary unit-test
call boundaries do not reproduce every invariant-executor warmth property. Fixed-time draining models
cooperating callers, not transaction throughput.

Results apply to their captured inputs and configured limits. The complete 116-partition deep
invariant matrix and hosted CI must be assessed on the final handoff inputs; a focused pass or a
collection of per-file passes on different revisions is not a full-matrix result. Local toolchain
versions that differ from CI also require separate validation. Parser/IR integrity checks do not
establish that detector findings have been rerun or triaged.

## Symbolic and arithmetic checks

```sh
python3 -m pip install halmos==0.3.3
python3 scripts/prove-eth-ledgers.py --output "$AUDIT_SCRATCH/eth-ledger-proof"
python3 scripts/test-split-arithmetic.py
python3 scripts/check-split-arithmetic.py --json-output "$AUDIT_SCRATCH/split-arithmetic.json"
```

The helper-proof output directory must not already exist. The script retains a separate project with
copied production sources, concrete harnesses and symbolic results; it needs Halmos's Yices solver.
[ETH exit assurance](audit/ETH-EXIT-ASSURANCE.md) states the exact proof domain and limits. Split
arithmetic is a source-pinned mathematical model, not bytecode equivalence of every caller. A
timeout or unresolved query proves nothing. Halmos's unconstrained GAS model does not establish
liveness of the gas-metered state machine. The complete symbolic campaign and its flags are in
[CI](../.github/workflows/ci.yml).

## Static analysis

```sh
python3 -m pip install slither-analyzer==0.11.5
env -u FOUNDRY_OUT -u FOUNDRY_CACHE_PATH forge build --skip test --build-info --force --threads 1 \
  --out "$AUDIT_SCRATCH/slither-out" --cache-path "$AUDIT_SCRATCH/slither-cache"
python3 scripts/check-slither.py "$AUDIT_SCRATCH/slither-out"
slither . --compile-force-framework foundry --ignore-compile \
  --foundry-out-directory "$AUDIT_SCRATCH/slither-out" --fail-none \
  --exclude-informational --exclude-optimization --json "$AUDIT_SCRATCH/slither.json"
```

The integrity check rejects stale compiler inputs, missing scoped ASTs and partial IR construction.
Detector output requires review; a clean parser exit is not a clean security report. CI also runs
Aderyn as a non-blocking report.
