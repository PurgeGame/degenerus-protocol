# Audit readiness — 2026-10-08

## Freeze verification in progress

The current candidate starts at `68c189cd6433d9de31ff42fb1eb4fb1be60c1567`,
including the BAF main-board sampling and ID-keyed smurf allowance changes. A new
complete regression, cold-gas, Hardhat and deep-invariant campaign is running in
isolated checkouts. The results below belong to the earlier campaign and do not
certify these later changes. No freeze tag has been created for this candidate.

The complete 96-file Hardhat selection has passed (1,651 tests), as have all
56 Halmos properties, the 24 split-arithmetic checks and the production/layout
gates. The warm Foundry campaign is closed; cold-gas and deep-invariant campaigns
remain in progress.
Two stale test oracles now include the smurf quota lanes and exclude them from
gameplay eligibility. A third fixture used the retired two-argument BAF draw-module
selector; typed calls now preserve its no-work assertions against both module
interfaces. The three-file rerun passes 95 tests. One optional foil comparison is
skipped because no archived runtime was supplied. Production Solidity is unchanged
by these verification repairs.

The complete warm selection covered all 410 roots: 3,481 initial passes, the
repaired BAF selector failure, and ten invariant setup errors. Those ten cases
made zero handler calls because cached test bytecode embedded a different handler
runtime from the current compiler artifact. Clean compilation restores matching
runtimes; the full-budget rerun passes all ten invariants (23 total tests).
All original warm failures have passing closures. The runner now rebuilds each batch
as one artifact set. Dependency fingerprints also follow nested library symlinks
and stop directory cycles; two regression tests failed before that repair and pass
after it. All 59 assurance unit tests and six partition tests pass. Saved compiler
metadata independently matches all 19 compiled forge-std sources to the clean,
locked library revision in all nine Foundry checkouts.

The first remote run passed production assurance and Slither, but several Foundry
runners received shutdown signals. Its Aderyn installer selected crates.io 0.1.9,
which cannot parse Osaka; the next remote run passes with npm release 0.6.8.
Further Foundry runner interruptions remain unresolved: they recurred with the
local Foundry release pinned and batches capped at five roots. CI now prints
memory, process, disk and cgroup information every minute to diagnose termination.
Remote interruption logs are retained; they are not counted as passing test runs.

The audit gas policy follows available-gas admission at deterministic checkpoints.
The 10M figure guides operation sizing; it is not a fixed transaction cap. Each
declared cold-path bound and complete call/return/flush tail must fit the worker's
remaining allowance and actual available gas. The old 13M absolute-ceiling wording
has been removed from the active handoff and verification instructions. Gas can
choose a safe continuation checkpoint, never a committed outcome or fallback.

## Earlier campaign: review subject and status

Base revision: `98cd2a781c1ce328362351ca9a0761e41e50eea1`, plus the verification
repairs recorded in that campaign's local input manifests. The current snapshot
manifest has since advanced and must not be used to identify this earlier run.
Priorities are RNG commitment integrity, continued progress without an
attacker-induced permanent revert, and protection of ETH/stETH and account data.

**Local campaign complete — 2026-10-08.** The configured selections and repaired
fixtures have completed, including all 24 deep invariant roots. No selected-test
failure remains unresolved. This is a bounded internal review; remote CI,
production deployment and an unconditional security guarantee are not established.

**Two WhaleSybil counterexamples classified as test-oracle errors:** the original campaign saved
47-call `invariant_obligationRatioHealthy` and 51-call
`invariant_solvencyUnderPressure` sequences. Exact finite replays first fail the
ETH-only check at actions 45 and 50 (zero-based), respectively, after automatic
staking. In each state, Game-held ETH plus stETH equals the unchanged 168 ETH of
obligations exactly. The test omitted stETH backing; production surplus accounting
already includes it. Both exact replays now pass, including independent one-wei
ETH and stETH shortfall controls. All five repaired WhaleSybil invariants pass
1,000 runs and 256,000 handler calls each, with zero handler reverts reported.
Preserved inputs and SHA-256 hashes remain recorded in
`.audit-test-logs/readiness-2026-10-08/provider-checkpoint.json`; baseline replay
evidence is under `whale-counterexample-replay/20261008T102434.557048Z-d494e69c/`.
The passing closure run is
`whale-final-deep/20261008T105734.694153Z-33d9fee3/` (13 executions, zero failures).

## Security conclusions

The source review and focused adversarial reviews found no confirmed ordinary-player
exploit that rerolls a committed result, permanently bricks `mineFlip`, steals
backing, or obtains another account's authority. This is a bounded review conclusion,
not a proof of absence. The additional broad campaigns below test that conclusion
against the repository's complete configured selections. The detailed RNG/mineFlip
review remains local at `docs/audit/rng-mineflip-2026-10-07/REVIEW.md`; this public
handoff summarizes its conclusions and executable coverage below.

| Property | Protection reviewed | Relevant executable coverage |
| --- | --- | --- |
| RNG commitment | Seal cohorts before requesting; authenticate coordinator and active request ID; retain an accepted word; drain read consumers before admitting another request. Seeds use committed IDs/positions, not the settling caller or remaining work. | RngStructuralLivenessReview, RngWindowFreeze, RngIndexDrainOrdering, CrapsRngSeal, PostRequestOutcomeControls, ticket schedule differential tests. |
| Progress | Persist cursors and bound atomic work; reserve nested-call and return gas; keep gas failure distinct from semantic failure; use terminal recovery for unavailable entropy. Ordinary mandatory prize credits do not call arbitrary player receivers. | AdvanceLiveness, AnyInputSafety, NativeAtomicWork, MineFlipWorkerBudget, cold integration/gas selection and terminal regressions. |
| Backing and exactly-once payment | Debit liabilities before transfers, preserve closed/parked redemption reserves, fix redemption payees, isolate failed individual redemptions, and transfer stETH before an untrusted ETH callback. | EthSolvency, PoolConservation, RedemptionInvariants, VaultShareMath, redemption ordering/reentrancy and reserve regressions. |
| Account isolation | Resolve and authorize the selected ID; retain root/child identity on acquisition; revoke former authority through ownership checks; authenticate reused packed records and clear only intended lanes. | WalletIdTruth, IdAuthorizationReview, AccountLiquidation, IdEntryPacking, CrapsAccountsProtocol and recursive storage-layout comparisons. |

The RNG comparison follows the owner's requested equivalence: ETH and equal-value
lootbox compensation count as the same outcome; an unchanged percentage entitlement
counts as unchanged when its pool balance moves. Winners, spins, traits and payout
percentages/multipliers must still respect their commitments. Previously accepted
soft EV-allowance timing remains a gameplay rule. These exceptions do not authorize
arbitrary post-request selection or diversion of payment.

## Repairs made during verification

All changes so far concern tests, assurance gates, scope or documentation; no
production Solidity behavior has been changed by this readiness pass.

| Gap | Correction and reason |
| --- | --- |
| Scope manifest omitted `ILiquidation.sol` | Include the production interface so a clean snapshot covers all 84 production Solidity sources. |
| Seven JavaScript redemption tests burned below the current 0.01 ETH admission minimum | Use funded, admissible burns, assert the preview meets the minimum, and retain the balance/supply checks. Seed Game claimable through its authenticated payable hook instead of manually writing liabilities. Both affected files pass: 79 tests. |
| AnyInputSafety setup lost its simulated sDGNRS caller | Resolve the wallet ID before the one-shot prank; assert that the backed bystander claim exists. Previously the view lookup consumed the prank and the authenticated funding hook correctly reverted. |
| Shared ticket-queue oracle rejected valid acquired accounts | Recognize a sold root and children that retain their original parent, validate the reserved buyer and its registry, and follow both payee links. Keep malformed-owner detection with seven explicit sensitivity controls and a real-liquidation regression. The repaired AnyInputSafety campaign passes 64 runs × 100 calls. |
| WhaleSybil solvency checks omitted stETH backing | Count only Game-held ETH plus configured stETH in current solvency, historical coverage and terminal claimable checks. Preserve every obligation term and queue assertion. Both exact saved replays pass; each independently removes one wei of ETH and one wei of stETH to verify that the exact oracle and handler ratio detect a real deficit. All five invariants pass their full deep budgets. |
| NativeAtomicWork used obsolete FLIP units | Mint and compare whole FLIP units. The old ether-scaled subtraction could make the surviving-payout assertion pass without a payout. |
| Jackpot gas witness decoded the retired per-seat storage format | Read the correct recycled key and 72-bit seat lane; authenticate the full day and compare the 32-bit owner. All three cases pass with unchanged payout/order/completion checks and 10M allowances; the largest measured call is 6,276,417 gas for the 500-seat field. |
| BAF test books still wrote one interval per storage word | Pack both 128-bit lanes and validate every seeded entry through the production getter. Keep the requirements that every intended award is filled and that allowance partitions preserve the full payout transcript. All seven affected roots pass warm (120 executions). All three gas roots pass cold: century consolidation (28), BAF award groups (14), and pool consolidation (7). Exact-path reruns avoid repeating imported suites. |
| Craps gas sample mixed warm and cold execution | Retain the 212,000 warm regression bound. In both modes require the measured seat to fit the unchanged production reserve with a 20% margin. The cold witness was about 244,500 gas. Both modes now pass. |
| Isolated constructor test collided with an etched contract address | Deploy the production constructor at a distinct CREATE2 address, then install the read-only test surface. The constructor assertion passes warm and cold without changing code-size or gas ceilings. |
| Symbolic checks omitted non-assertion Solidity panics and had stale whole-FLIP assumptions | Check all panic codes, correct the boon-cap units, and use solver-specific arithmetic proofs, an asserted multiplication lemma and exhaustive production-price cases. No input domain is reduced. The complete final Halmos selection passes: all 56 properties, with every panic code checked. |
| Symbolic storage proofs used a layout model that rejected parity-selected Yul slots | Use Halmos's generic storage model for this suite and construct the reference owner's eight lanes with disjoint shifts. All 16 properties pass over their original domains with all panic codes enabled. |
| Earlier focused reviews exposed stale redemption/packed-field fixtures | Bring burns above the admission minimum; read Craps flags from their current position and assert that the owner ID survives the packed update. Preserve the added RNG and unauthorized-ID regressions. |
| Symbolic FSM exploration invented impossible gas readings | Halmos 0.3.3 represents each GAS opcode as an unconstrained `f_gas` value. Saved counterexamples include 2²⁵⁵ gas and nonphysical changes between reads. Retain all three production carriers as real-EVM fuzz checks and add all 16 explicit day/gap boundary cases; they pass with 1,000 fuzz cases each. The separate arithmetic model contract remains symbolic. This removes an unsupported proof claim, not the executable transitions; formal gas/liveness verification remains a limitation. |
| Sentinel accounting model could panic in its assertion | Reconstruct the original pool with `poolAfter + (amount - 1)` instead of subtracting `amount` before adding the sentinel. Replay the reported boundary and retain all valid inputs. Express the Decimator partition guard without an overflowing addition. Production accounting is unchanged. |
| Quadrant payout oracle omitted gold-six solo priority | Apply the existing production rule before the ordinary gold-quadrant tie-break and preserve the saved fuzz counterexample as a regression. The corrected reference still checks every recipient count, ETH/pass allocation and pool-conservation equation; the full affected file passes. |
| Additional century/wrapper burns were below admission value | Fund admissible burns while retaining odd raw units, pool-refill conservation, wrapper equality and pending/settled redemption assertions. Century cases pass warm and cold; the raw-unit wrapper case also passes. |
| Empty advance became too cheap to test a positive keeper reward | Queue four real purchases before requesting the day. Retain the assertions that work exceeds the unpaid first million gas, the reward is positive and exactly one keeper credit is emitted. All 11 file tests pass. |
| Century seed microbenchmark used its warm cap for isolated transactions | Retain the 15,000 warm cap and bound isolated calls at 40,000 including transaction/cold-access overhead; the failure measured 34,680. Record storage accesses and require every write to be the packed seed word. All file tests pass warm and cold; the production transition reserve is unchanged. |
| Jackpot draw tests assumed one checkpoint per transaction | Keep the existing gas and no-settlement guards, allow multiple admitted 50-entry checkpoints, and assert per-call progress, whole-group increments and target limits. Stop precisely when the field seals before testing settlement replay. All 11 cases pass warm and cold. |
| Automatic whale-purchase fixture treated the packed registry as one ID | Decode its low 32-bit gameplay ID; the upper identity field is not part of the mapping key. All 15 automatic-purchase tests now reach their intended budget, boon, ticket and reward assertions. Production decoding was already correct. |
| Banked-FLIP gas fixture keyed state by address | Seed the registered wallet ID and assert the bank is visible through the production getter. All 24 customer-followup tests pass cold. |
| Redemption determinism fixture discarded every burn input | Transfer existing pool tokens, fund admissible burns over the original range and assert admission. Compare the original batch's resolved roll, payout and exactly-once claim after consumers drain; a later batch can change global reserves after a day warp. Preserve the saved day-warp counterexample. The affected file passes, including the full fuzz campaign. |
| Terminal redemption fixture burned below admission value | Raise the seeded and burned amount together, assert its backing preview, and retain the pending-ending and terminal-payment checks. |
| Multiway split bit-vector proofs exceeded solver budgets | Retain the Solidity formulas and production bucket library as bounded fuzz carriers, and prove their integer arithmetic with explicit checked-overflow bounds in a separate fail-closed Z3 gate. Authenticate the production library and Solidity carrier source files so code changes require model review. All original admitted amounts, BPS splits, counts and remainder indices remain in the proof domain. |
| Three redemption gas cohorts used an obsolete token-unit minimum | Derive the minimum burn from current backing with the existing fixture helper and assert admission. Retain the 45-beneficiary drain, a maximum beneficiary in the middle of a mixed cohort, and the unchanged 500,000 / +5,000-gas checks comparing 2 versus 2,000 claims. All 17 affected-file tests pass cold. |
| Redemption accounting's random seed never admitted its intended claim | Give handler actors useful balances above the admission boundary, choose an admissible initial burn, and require a successful submission and tracked batch. Also fund and register the shared handler's actors in RedemptionInvariants. Both suites now start with a real claim; explicit lifecycle tests require settlement, alongside the existing supply/reserve checks. All 22 cold executions pass, as do both repaired suites at the deep 1,000-run × 256-call budget. |
| Build cache could regard fixture-pinned default artifacts as current | Use separate production artifacts and cache in the documented build and CI. Keep the strict metadata/source check; it rejected the stale local artifact before the fresh production build passed. |
| CI only checked shallow storage goldens | Also compare full recursive compiler layouts for all 16 Game modules and the CrapsBattle/JackpotBattle pair. |
| Serial CI campaigns placed unrelated properties behind one timeout | Run the seven Foundry groups separately and dynamically enumerate every deep invariant root. Split the three expensive Craps suites by named property, with a complementary job retaining every other or inherited test. Preserve budgets and require both production gates and every ordinary test group through the original aggregate check name. Local validation covers all seven groups and an exhaustive 41-job deep partition over 24 roots, with six partition unit tests. Remote CI is not yet evidenced. |
| Audit documentation omitted delayed RNG retry authority | Document the 20-hour owner retry and its trust limitation. The subsequent freeze pass also reconciles gas wording with available-gas admission; production reserves and fixture bounds are retained. |

## Earlier campaign evidence

Local logs, source identities, exact commands and tool versions are generated under
`.audit-test-logs/readiness-2026-10-08/`. Runners use isolated checkouts, authenticate
the compiled inputs, retain failed batches and restore address pins. Repeat the
commands in [VERIFICATION.md](VERIFICATION.md); generated local logs are not shipped
as a substitute for reproducible tests.

| Check | Earlier campaign result |
| --- | --- |
| Assurance-tool unit tests | 67 passed: 57 runner/snapshot tests, six deep-partition tests and four split-proof gate failure-mode tests. |
| Ten source-drift gates plus interface coverage | Passed. |
| Production build and deployment sizes | Passed for all 37 deployment entries. Game: 24,532 bytes (44 bytes spare); Whale: 24,504 (72 spare). |
| Storage goldens and recursive delegate layouts | Passed, including all 16 modules and CrapsBattle/JackpotBattle. |
| Complete Hardhat selection | All 95 files covered; latest results total 1,650 passed, zero failed/pending. Initial ten fixture failures are retained in the logs and superseded by passing reruns of the three corrected files. |
| Complete Foundry regression selection | All 20 regression batches completed: 3,327 initial passes and 24 fixture/model failures, each repaired with passing affected-file reruns. The stronger deep campaign is also complete. |
| Complete cold integration/gas selection | All seven batches completed: 1,452 initial passes and 24 fixture failures, each superseded by passing affected-file reruns. The 2-claim and 2,000-claim cleanup witnesses both measured 182,051 gas with the original limits retained. Counts are test executions; imported suites can repeat. |
| Symbolic arithmetic | All 56 Halmos properties pass in one complete run, checking every Solidity panic code. Two multiway split models use a separate exact-integer gate: 24 proof/non-vacuity/sensitivity checks passed, including uint256 bounds, all four remainder positions and empty-bucket refunds. Four gate failure-mode tests and the retained Solidity fuzz carriers pass. These are arithmetic model proofs, not bytecode equivalence. |
| Slither | Completed against a separate production build with full build information and ASTs; 327 contracts, 75 detectors, 1,343 alerts including inherited and supporting-code duplicates. Security-relevant alert classes are discussed below; this is not a zero-alert claim. |
| Deep invariants | All 24 configured roots covered at 1,000 × 256, with existing suite overrides retained. First five roots: 30 passes. Tail 19 roots: 119 passes and the two now-resolved WhaleSybil oracle failures. Repaired redemption and WhaleSybil/replay batches: 22 and 13 passes. Latest results across these batches: 154 distinct suite/test identities, all PASS, including 87 invariant functions and supplemental regression/helper tests. No configured root is missing. |
| Current source snapshot | Passed: all 84 production Solidity sources and current verification inputs match the refreshed manifest. Recheck after any further repairs. |

### Closure evidence and source currentness

`deep-closure.json` reconciles every deep suite/test result, including Forge's
multiline invariant failures, with the completed reruns. It preserves the two
original failures and links each to its passing result. The deliberate interruption
of the original driver's second batch occurred during compilation; the independent
tail campaign covered those roots. `failure-resolution-current.json` separately
maps all 48 initial ordinary/cold failures to passing affected-suite reruns.
`replay-authentication.json` verifies all 98 saved actions against the regression
source: identical senders, calldata and order, with no warp/roll metadata omitted.

All production Solidity remains identical to the reviewed revision. The final
WhaleSybil repair adds a backing accessor to the shared solvency test helper;
its pre-existing obligation, pending-pool and queue checks are unchanged. Seven
previously completed deep roots import that helper but do not call the new
accessor. Their evidence is retained with this reviewed source difference,
recorded in `deep-input-currentness.json`, rather than described as a fresh run
of identical compiler inputs. Changed redemption and WhaleSybil behavior has
dedicated passing deep reruns.

The final source gates again passed for all 137 registered VRF-word accesses,
325 taint sites, delegatecall/selector alignment and gas-read rules. The restored
production artifacts also pass all 37 deployment size/source checks. Exact commands
and outputs are retained in `closure-gates/`. No production source change,
commit, push or deployment was made to close this audit.

### Static-analysis triage

Slither is supporting evidence, not the acceptance oracle. Its input includes
imported test helpers; it reported an IR-generation warning for the test-only
`activityScoreOf` helper and completed successfully. The warnings and raw JSON
remain in the local evidence. No detector or source warning was suppressed in
production code to obtain a clean-looking report.

| Alert class reviewed | Disposition / verification boundary |
| --- | --- |
| Uninitialized state | The 177 alerts concern 73 declarations in the two shared storage bases. The analyzer treats delegate modules separately; initialization and writers live in Game/CrapsBattle or other modules, and some writes use assembly. Check the layout and writer gates plus runtime lifecycle tests, not module-local absence of an assignment. |
| Weak PRNG | Reported uses are timestamp window selection, packed lane/period indexing and arithmetic remainders. They do not replace committed VRF entropy. The separate request/consumer review is still required. |
| Incorrect shifts/exponentiation | Yul masks deliberately shift constant payloads; XOR selects the other binary slot. Packed-lane and recycling regressions exercise boundaries and neighboring-record preservation. Library/test-support alerts are distinguished from production. |
| ETH reentrancy and stale balance | Request/advance callbacks go to fixed modules, sDGNRS, stETH or the configured coordinator. User withdrawals debit/burn first and put the untrusted ETH callback after stETH delivery. Vault refreshes reserves after Game withdrawals. These conclusions retain the stated external-dependency trust assumptions. |
| Arbitrary ETH send | Private payment helpers receive authenticated/fixed payees from claims or share redemption. Permissionless settlement cannot substitute the caller's recipient. Reentrancy and liquidation tests cover the account/recipient transitions. |
| Delegatecall inside payable loops | Lootbox spin helpers target the fixed Degenerette module with explicit stake parameters. Funding is booked once at the authenticated outer redemption door; the nested helpers do not re-credit `msg.value`. |
| Packed encoding collision | The reported dynamic concatenation constructs an SVG, not an authorization or entropy commitment. |
| Assembly return / module-locked ETH | The jackpot facade intentionally returns its delegate's data; modules execute in the host's storage/custody context. Directly sending ETH to a module is not a supported deposit flow. |
| ERC20 interface | Reported `transferFrom` declarations are ERC721/seat interfaces and deliberately have no ERC20 Boolean return. |

The symbolic gas limitation is visible in Halmos's [GAS implementation](https://github.com/a16z/halmos/blob/v0.3.3/src/halmos/sevm.py);
the installed 0.3.3 source and saved SMT/model evidence were inspected directly.

Other alerts include event ordering, timestamps, zero-initialized accumulators,
integer rounding and fixed dependency calls in loops. The report is retained for
independent audit; detector severity alone is not evidence of an exploitable path.

## Trust boundaries and release constraints

- **Unanswered VRF requests:** the vault owner may retry once after 20 hours;
  governance can replace a stalled coordinator under its voting rules. Accepted
  on-chain answers cannot be replaced. These powers do not prove resistance to a
  privileged party selectively rejecting an answer known before on-chain acceptance.
- **External asset availability:** required stETH transfers and VRF/LINK service
  availability remain dependencies. Optional funding/individual redemption failure
  isolation does not make every protocol-level transfer failure ignorable.
- **Terminal treatment:** unfinished game entropy consumers have the ending treatment
  disclosed in [Known Issues](../KNOWN-ISSUES.md). Earned claims and paid terminal
  ticket obligations must retain their specified protections.
- **Deployment headroom:** Game and Whale are close to EIP-170. Any source, compiler,
  optimizer or address-pin change requires the production size and metadata gate
  again; test deployments with relaxed limits are not deployment evidence.
- **Evidence scope:** mock-based tests, bounded invariant campaigns and arithmetic
  models do not prove the behavior of external services or every possible state.
  Halmos does not establish production gas-metered FSM liveness: its unconstrained
  GAS model is unsuitable for that claim; the retained transition tests run in Foundry.
  Local results do not establish that remote CI ran successfully.

Review findings against [AUDIT.md](AUDIT.md), [SECURITY.md](../SECURITY.md) and
[Known Issues](../KNOWN-ISSUES.md). Accepted governance powers and the explicit RNG
equivalences above are distinct from authorization bypasses or unbounded payouts.
