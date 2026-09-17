> Historical document. Superseded by the [current audit handoff](../../AUDIT.md). Claims and test counts below apply only to their original revision.

# Defensive audit-readiness review — 2026-09-04

Status: defensive readiness pass complete, with two tooling issues fixed and documented verification exclusions. No test failures in the completed runs.

## Reviewed snapshot and scope

Starting HEAD: `8777c7d99`. Committed contracts tree:
`7df3d9feb72e1a1e70e428acb9be093bffc469db`.
The workspace already contained deployment/feed tests, simulation changes, and security-policy edits.
Those changes were preserved. This pass reviews deployment configuration, audit checks,
and the latest rotating-shooter contract change, and runs broader regression tests.
It does not replace an independent whole-protocol audit.

The published audit package still names contracts tree `8b3101b3` at `degenerus-c4a`.
That is a historical snapshot, not the current contracts tree. Existing audit results must
be read against their named snapshots; the tag was not moved by this review.

## [MEDIUM — deployment configuration] Optional addresses survived subsequent builds

**Location:** `scripts/lib/patchContractAddresses.js:patchContractAddresses`.

**Description:** The patcher only replaced supplied external-address keys. A build that
omitted LINK_ETH_FEED or ENS_REVERSE_REGISTRAR retained the preceding build's value.
The deployment script described omission as disabling the integration, so the resulting
bytecode could differ from the operator's intended configuration.

**Failure scenario:** Build once with optional integrations configured, then reuse the
checkout for another build without those settings. Previously configured addresses remain.

**Impact:** The administrator constructor can install an unintended donation-pricing feed;
constructor naming calls can reach an unintended registrar. This is a deployment integrity
issue, not evidence of an on-chain loss. Feed valuation retains its existing cap.

**Resolution:** The shared patcher explicitly writes zero for omitted or empty optional
integrations on every invocation. Explicit configurations remain supported. `.env.example` now documents the optional
LINK/ETH feed and its empty-setting behavior.

**Evidence:** `test/deploy/OptionalConfig.test.js`: configured values, omitted values on
subsequent builds, and a mixed configured/empty build. All three checks pass.

## [LOW — verification coverage] CI omitted newer source checks and feed setup

**Location:** `.github/workflows/ci.yml`.

**Description:** CI ran six source checks while the Makefile defined newer checks for crank
calls, RNG taint, unchecked arithmetic, shared-storage writers, deterministic drains,
and simulation parity. Foundry jobs also did not explicitly run the address patcher,
which now installs the genesis feed expected by the new tests.

**Resolution:** Both Foundry jobs now apply their deterministic address configuration.
The regular job includes all twelve source checks and the optional-configuration regression tests. YAML parsing and step presence were
verified locally; the hosted workflow has not been executed by this review.

## Verification

- Eleven source-only gates: PASS.
- Interface coverage: all 227 functions across the 20 mappings in the repository gate have
  matching implementation selectors in the current Hardhat artifacts.
- Storage layouts: all 27 current Hardhat compiler layouts match the committed goldens
  using the repository normalizer.
- Rotating-shooter suite: 25 passed, zero failures, zero skipped; includes the independent
  engine comparison, rounding, and preview/payment tests.
- Optional deployment configuration: 3 passed.
- Foundry genesis feed and mid-day RNG credit: 34 passed, zero failures or skips.
- Foundry advance-stage gas: 6 passed, zero failures or skips. The 305-winner jackpot
  measured 7,202,627 gas; warm ticket-batch resume measured 6,614,187 gas. These are
  the tested fixtures, not proof of a whole-protocol worst-case bound. The cross-stage
  rollup also includes historical reference numbers, which were not remeasured here.
- C++ simulation: built with its documented C++20 configuration; a two-day run with
  100 calibration and 100 schedule samples completed. This is a smoke test, not EV certification.
- Current Hardhat artifacts: all 30 contracts in DEPLOY_ORDER are under the repository runtime-size ceiling.
  Largest: CrapsBattle, 24,415 bytes (161 bytes of margin); mint module, 24,411 bytes.
  These figures apply to the test build, not a final network-specific deployment.
- Full configured `npm test` run: 1,465 passed, 19 pending, zero failures.
  Pending tests include jackpot-stage gas benchmarks, a direct lootbox gas path,
  older lifecycle regressions, and intentionally obsolete feature/baseline checks.
  They are not included in the passing count.
- Final-patch deployment and feed-governance rerun: 58 passed, zero failures.
- Foundry: **2,214 passed, 104 skipped, zero failed** across the focused runs and 23 batches.
  The batches account for 2,149 passes; four separately tested files account for 65 more.
  All 273 `.t.sol` paths were assigned to those runs. Proof-only files still require a
  separate Halmos solver run; compiling them under Foundry is not a symbolic proof.
- The initial five targeted invariant suites passed 32 checks; their subsequent results
  are already included in the batched total and are not counted twice.
- The original all-at-once Foundry compile was killed with SIGKILL. The successful
  twelve-file batches resolved that execution limitation while keeping the configured
  compiler, optimizer, fuzz seed, fuzz runs, and invariant depth.

Foundry used an isolated source copy at `/tmp/degenerus-readiness-mszou5ce`, patched
with its own predicted addresses. Hardhat's generated deployment-address changes were
restored after its runs; production Solidity files have no changes from this review.

Completed logs, per-batch results, skipped-test explanations, source SHA-256 hashes,
and tool versions are preserved under `audit/readiness-2026-09-04/` (local audit evidence,
intentionally excluded from Git by the repository's existing ignore rules).
`summary.json` records the totals and test-path inventory. The session runner is retained
as `run-slices-session.py`; its paths identify this session's isolated copy.

## Fresh static-analysis comparison

Slither completed on an isolated copy matching the current Hardhat build: 179 contracts,
75 detectors, 1,223 raw alerts after excluding informational/optimization categories and
mock/dependency/test paths. Raw severities are tool labels, not confirmed issue severities.
Output: `audit/readiness-2026-09-04/slither-current.json`; the three new signatures are
saved in `slither-new-signatures.json` beside it.

Comparison with `audit/automated/slither-8b3101b3.json`, canonicalizing element order and
ignoring source-line drift, found three distinct new alert signatures. The other signatures
were already present in that baseline; matching a baseline is not independent validation
of every prior disposition.

| New alert | Review disposition |
| --- | --- |
| `weak-prng` on the rotating-shooter offset | No new defect demonstrated: the input is the slot-keyed VRF seed, hashed with a separate rotation tag. `_armSlot` binds an unfilled RNG index and freezes the combined field count before requesting its word; `_joinableSlot` rejects armed/closed windows. The rotation and real-lifecycle RNG-seal suites pass. |
| `incorrect-equality` on the rotation hand | Intentional comparison of discrete one-based hand ordinals. Equality is required to apply the uplift exactly once; it is not a balance/threshold liveness condition. The turn and overlap tests pass. |
| `timestamp` propagation into settlement comparisons | Scheduling identifies the committed slot; settlement receives the slot, word, frozen field count and seat. `_settlementOf` is pure and reads no current timestamp. Clock-based entry closure precedes RNG selection. |

## Limits and remaining audit evidence

- The independent audit package still targets the historical `degenerus-c4a` snapshot.
  A release audit must identify the intended current source and deployment configuration.
- The 104 Foundry skips and 19 Hardhat pending tests are explicit exclusions. Foundry skip
  reasons identify superseded setups and replacement suites; Hardhat also has unresolved
  runtime gas-harness coverage, some of which is exercised by the separate Foundry tests.
  The passing count does not turn any skipped case into evidence.
- The separate `npm run test:stat` command, Halmos solver proofs, a fresh broad mutation
  campaign, and Aderyn were not rerun. Passing the existing mutation-detection tests is
  distinct from running a fresh mutation campaign.
- Prior audit dispositions were used as a baseline, not independently recertified in full.
  The manual code review in this pass focused on deployment configuration and the latest
  rotating-shooter change. Passing tests does not prove absence of defects.
