# Domain Pitfalls

**Domain:** Adding Foundry invariant fuzzing and blind adversarial testing to an existing Hardhat-based 22-contract DeFi/GameFi protocol
**Researched:** 2026-03-05
**Confidence:** HIGH (project-specific analysis of existing codebase + foundry.toml config, corroborated with official Foundry docs and community experience)

---

## How to Read This File

Pitfalls are grouped by severity and tagged with the phase where they must be addressed:
- **Setup** -- Foundry integration, compiler alignment, project structure
- **Harness writing** -- Handler design, invariant formulation, targeting configuration
- **Attack sessions** -- Adversarial brief design, bias mitigation, PoC methodology
- **Reporting** -- Findings synthesis, confidence claims

---

## Critical Pitfalls

Mistakes that cause wasted effort, false confidence, or invalidate the entire testing campaign.

### Pitfall 1: ContractAddresses Compile-Time Constants Block Real Invariant Testing

**What goes wrong:** ContractAddresses.sol uses `address(0)` compile-time constants. Foundry compiles contracts independently of the Hardhat patch-recompile pipeline. Every cross-contract call in a Foundry-deployed contract hits `address(0)` and silently fails or reverts, making multi-contract invariant tests meaningless.

**Why it happens:** The existing test infrastructure relies on `patchContractAddresses.js` to predict nonce-based addresses, rewrite the .sol file, and recompile before deployment. Foundry has no equivalent mechanism -- `forge test` compiles once and runs. The existing fuzz tests (BurnieCoinInvariants, PriceLookupInvariants, ShareMathInvariants) deliberately sidestep this by testing mock/standalone contracts, not the real protocol.

**Consequences:** Invariant tests that appear to deploy the full protocol actually deploy broken contracts. Tests pass because invariants hold trivially on contracts that cannot interact. Zero bugs found. False confidence going into C4 contest.

**Prevention:**
- For system-level invariants (ETH solvency, game FSM): build a Foundry `setUp()` that deploys all 22 contracts in the correct nonce order from the same deployer, then wires addresses via constructor args or a post-deploy initialization pattern.
- Alternative: use `vm.etch()` to place contract bytecode at expected addresses, bypassing ContractAddresses entirely.
- Alternative: create a Foundry-specific `ContractAddresses.sol` override using remappings that provides real deployed addresses from `setUp()`.
- Simplest and most practical: accept the existing pattern of isolated-math invariant tests (what the project already does) and reserve multi-contract integration testing for the Hardhat suite. The v3.0 milestone targets 5 specific invariants; decide per-invariant whether it needs full protocol or can use isolated mocks.

**Detection:** Check that `forge test --show-progress` actually executes transactions against real contract logic, not `address(0)`. Add a canary invariant: `assert(game.owner() != address(0))`.

**Phase:** Setup (must solve before writing any system-level harnesses).

---

### Pitfall 2: Invariant Tests with Poor State Coverage Produce False Confidence

**What goes wrong:** Invariant tests pass across hundreds of runs but the fuzzer never reaches interesting protocol states. For this protocol: the game never advances past level 0, VRF callbacks never fire, no whale bundles are purchased, no jackpots are triggered, no game-over is reached. The invariant `address(game).balance >= totalObligations` holds trivially because nothing happened.

**Why it happens:** Without guided handlers, Foundry's invariant fuzzer generates random call sequences where most calls revert (wrong phase, insufficient funds, RNG locked, unauthorized). The fuzzer wastes 90%+ of its depth on reverted calls. With `fail_on_revert = false` (current config in foundry.toml), these silent failures are invisible.

**Consequences:** Invariant suite reports green. Coverage is an illusion. The dangerous states -- mid-jackpot distribution, partial game-over with pending claims, concurrent whale+regular minting -- are never tested.

**Prevention:**
- Write handler contracts that guide the fuzzer through valid state transitions: fund actors with ETH via `vm.deal()`, purchase tickets at correct price, advance through VRF request/fulfill cycles, trigger jackpots at milestone levels.
- Use ghost variables to track cumulative ETH in/out and verify against contract balance.
- Set `show_metrics = true` in foundry.toml's `[invariant]` section to monitor call success rates. Target >60% non-reverting calls.
- Add phase-advancing helper functions in the handler (e.g., `advanceToLevel(n)` that does the full purchase+VRF+advance cycle).
- Log which game states are reached and assert that deep states are actually hit.

**Detection:** After running invariants, check metrics output. If a handler function like `handler_purchaseTicket` has 95% revert rate, the invariant is not testing purchase flows. Check if `game.currentLevel()` ever exceeds level 2.

**Phase:** Harness writing (most important phase for invariant quality).

---

### Pitfall 3: Foundry + Hardhat Compiler Version Mismatch

**What goes wrong:** foundry.toml currently specifies `solc_version = "0.8.26"` but hardhat.config.js specifies version `"0.8.34"`. Contracts compile differently under each compiler. `DegenerusGameStorage.sol` uses `pragma solidity 0.8.34` while other contracts use `0.8.26`. Foundry will fail to compile DegenerusGameStorage (and all contracts that import it) because 0.8.26 < 0.8.34.

**Why it happens:** The two config files evolve independently. The Hardhat config was updated to 0.8.34 but foundry.toml was never synchronized.

**Consequences:** Foundry cannot compile the protocol at all. Or if pragmas are loosened with `^`, subtle bytecode differences between compiler versions could mean Foundry validates different behavior than Hardhat. Storage layout could differ between versions, especially with `viaIR` enabled.

**Prevention:**
- Align foundry.toml `solc_version` to `"0.8.34"` to match hardhat.config.js. This is the immediate fix.
- Use the same optimizer settings in both: `optimizer_runs = 2`, `via_ir = true`.
- Add a CI check: `forge build` and `hardhat compile` must both succeed without errors.

**Detection:** Run `forge build` right now. If it fails on pragma version, this pitfall is already active.

**Phase:** Setup (must fix before any Foundry tests can compile).

---

### Pitfall 4: VRF Simulation Makes Invariants Vacuously True or Unreachable

**What goes wrong:** The protocol's state machine is gated by VRF: `advanceGame()` requests randomness, and nothing progresses until `rawFulfillRandomWords()` is called back by the coordinator. In Foundry invariant testing, either: (a) VRF is never fulfilled so the game is permanently locked at the RNG-pending state, or (b) VRF is fulfilled with deterministic/predictable values that don't exercise the full entropy space (jackpot-hit vs jackpot-miss branching).

**Why it happens:** Unlike Hardhat tests where `MockVRFCoordinator` can be called programmatically between test steps, Foundry invariant testing runs random call sequences. The fuzzer has no concept of "after requesting VRF, the coordinator must callback before the next advance." Without explicit handler logic, VRF fulfillment either never happens or happens at the wrong time.

**Consequences:** Option (a): game stuck at level 0 forever, all game-over/jackpot/endgame invariants are vacuously true. Option (b): VRF always returns the same entropy, so jackpot/no-jackpot branching is never explored.

**Prevention:**
- Handler must include a `fulfillVRF()` function that checks if a VRF request is pending and fulfills it with fuzzed randomness. This must be a targetable function in the invariant suite.
- Use `vm.prank(vrfCoordinator)` to impersonate the VRF coordinator when calling `rawFulfillRandomWords`.
- Track VRF fulfillment count in a ghost variable. Assert at end of campaign that VRF was fulfilled at least N times.
- Vary the random words to cover both jackpot-hit and jackpot-miss paths (use fuzzed uint256 values, not a fixed seed).

**Detection:** After invariant run, check if `game.currentLevel()` ever exceeds 0. If not, VRF fulfillment is broken.

**Phase:** Harness writing (handler must include VRF fulfillment logic).

---

### Pitfall 5: Adversarial Session Anchoring Bias (Auditor Already Knows the Code)

**What goes wrong:** The "blind" adversarial sessions are conducted by the same AI/auditor that performed v1.0 and v2.0 audits. The auditor has already formed mental models of the code, classified findings, and declared areas "safe." Adversarial sessions unconsciously skip areas previously reviewed, focus on the same attack vectors, and confirm prior conclusions rather than challenging them.

**Why it happens:** Anchoring bias: initial exposure to information (the prior audit) creates a mental anchor. A reviewer who already concluded "ETH accounting is sound" will unconsciously spend less effort attacking ETH accounting, even in a supposedly blind session. This is the single biggest risk to the adversarial testing value proposition.

**Consequences:** All 4 adversarial sessions find only the same class of issues already identified (or closely adjacent). Novel attack vectors -- especially cross-boundary attacks that span prior phase scoping -- remain undiscovered. The sessions produce a false sense of additional coverage.

**Prevention:**
- Each adversarial session must have a specific, narrow attack brief that forces focus on a single attack surface (e.g., "extract ETH beyond entitlement" vs "permanently brick advanceGame").
- Attack briefs should deliberately contradict prior conclusions: "Prove the ETH solvency invariant CAN be violated" rather than "verify it holds."
- Use different attack methodologies per session: one does pure code review from scratch, another writes PoC exploits top-down, another uses static analysis tools (Slither custom detectors), another fuzzes specific functions.
- Time-box sessions strictly. Anchoring worsens with open-ended scope.
- Include at least one session focused on cross-module interactions that were never tested in isolation (delegatecall module A calling through to module B's state).

**Detection:** If all 4 adversarial sessions produce zero Medium+ findings and the auditor says "confirms v2.0 conclusions," anchoring bias is the likely cause, not perfect code.

**Phase:** Attack sessions (brief design is critical -- do this before starting any session).

---

### Pitfall 6: Delegatecall Modules Create Invisible State Corruption in Fuzzing

**What goes wrong:** The 10 delegatecall modules share DegenerusGameStorage. If the invariant fuzzer targets module contracts directly (instead of through Game's delegatecall pattern), modules operate on their OWN empty storage, not Game's storage. Invariants that check Game storage see no corruption, but the fuzzer is testing nothing useful.

**Why it happens:** Foundry's `targetContract` mechanism calls functions on the contract address directly. If a module is listed as a target (or `targetInterfaces` is misconfigured), the fuzzer calls module functions with `address(this) = module`, reading/writing module storage instead of Game storage. The module's storage is uninitialized, so most calls revert silently.

**Consequences:** Two failure modes: (1) Module calls revert because module storage is uninitialized, silently wasting fuzzer depth (invisible with `fail_on_revert = false`). (2) In rare cases, module calls succeed on empty storage, creating impossible states that pass Game-storage invariant checks while masking real bugs.

**Prevention:**
- ONLY target the Game contract (or handler contracts that call through Game). Never add module addresses to `targetContracts`.
- Use `targetSelectors` to restrict which Game functions are called, ensuring only the public-facing ones that internally delegatecall to modules.
- Add a sanity invariant: for each module, assert module-local storage is zero (modules should have no local state).
- In handler contracts, always call `game.functionThatDelegatecalls()`, never `module.functionDirectly()`.

**Detection:** Run `forge test -vvv` and check call traces. If calls go directly to module addresses (0x... for MintModule etc.) instead of through Game, targeting is wrong.

**Phase:** Harness writing (targeting configuration must be correct from the start).

## Moderate Pitfalls

### Pitfall 7: Remapping and Import Path Conflicts Between Foundry and Hardhat

**What goes wrong:** Foundry and Hardhat resolve imports differently. Hardhat uses Node.js resolution (`@openzeppelin/contracts/...` via `node_modules/`). Foundry uses explicit remappings. The current foundry.toml has `@openzeppelin/=node_modules/@openzeppelin/` which should work, but additional imports needed for test harnesses (forge-std, Chainlink VRF interfaces, internal library paths) may fail.

**Prevention:**
- Verify all import paths compile under both `forge build` and `hardhat compile` before writing new tests.
- Keep Foundry test files (.t.sol) in `test/fuzz/` (already configured) separate from Hardhat test files.
- Keep `forge-out` as Foundry's output directory (already configured) to avoid artifact collision with Hardhat's `artifacts/`.
- If Chainlink VRF interfaces are imported in test harnesses, add remapping: `@chainlink/=node_modules/@chainlink/`.
- If `forge-std` is not installed, run `forge install foundry-rs/forge-std --no-commit`.

**Detection:** `forge build` fails with "file not found" or "source not found" on import paths.

**Phase:** Setup.

---

### Pitfall 8: Invariants That Are Too Weak (Tautological)

**What goes wrong:** Invariants like `totalSupply >= 0` (always true for uint256), `game.owner() != address(0)` (true by construction), or `address(game).balance >= 0` (always true) pass every time and catch nothing.

**Why it happens:** Writing strong invariants is hard. The temptation is to start with "obviously true" properties. For this protocol, weak invariants include:
- "ETH balance >= 0" (trivially true for uint)
- "Current level >= 0" (trivially true for uint)
- "totalTicketsSold >= 0" (trivially true for uint)

**Prevention:**
- Express invariants as equalities or tight bounds, not loose inequalities:
  - STRONG: `address(game).balance == sumOfClaimable + currentPrizePool + futurePrizePool + adminFees`
  - WEAK: `address(game).balance >= 0`
- Use ghost variables in handlers to track expected values and compare against actual contract state.
- For BurnieCoin: `totalSupply + vaultAllowance == INITIAL_SUPPLY + totalMinted - totalBurned` (partially covered by existing BurnieCoinInvariants.t.sol).
- For Game FSM: `if rngLockedFlag == true then pendingVRFRequestId != 0`.
- For ticket queue: `sum(all bucket ticket counts) == totalTicketsSold`.
- Mutation test each invariant: temporarily break the contract logic and confirm the invariant catches it. If it doesn't, the invariant is too weak.

**Detection:** Introduce a known bug (e.g., double-credit ETH in a handler) and run invariants. If they still pass, invariants are tautological.

**Phase:** Harness writing.

---

### Pitfall 9: Adversarial Sessions Drifting into Scope Creep

**What goes wrong:** An adversarial session briefed on "ETH extraction attacks" gradually drifts into reviewing gas efficiency, code style, documentation gaps, or previously-identified QA issues. The session produces a long list of informational findings but no Medium+ exploits. Time is wasted, and the session's focused adversarial value is lost.

**Prevention:**
- Each session brief must specify: (1) exact attack goal in one sentence, (2) in-scope contracts/functions (not the whole protocol), (3) what constitutes a valid finding (Medium+ severity threshold), (4) hard time limit.
- Session output must be structured: PoC exploit code with severity justification, or "unable to achieve attack goal despite [specific attempts listed]."
- Ban informational/QA findings from adversarial sessions. Those belong in static analysis.
- If a session discovers a potential issue outside its scope, log it as a one-line lead for a different session. Do not pursue it.

**Detection:** Session report contains >2 informational findings and zero Medium+ findings. The session drifted.

**Phase:** Attack sessions (brief template enforcement).

---

### Pitfall 10: Confirmation Bias in Adversarial PoC Writing

**What goes wrong:** The auditor writes a PoC that "almost" achieves the attack, then concludes the attack is infeasible based on the PoC failing. But the PoC failure is due to a mistake in the PoC itself (wrong function signature, missing prerequisite step, incorrect parameter encoding), not because the attack is actually blocked by the protocol.

**Why it happens:** When the auditor expects the attack to fail (because v2.0 said it was safe), a failing PoC confirms the expectation and investigation stops. A genuine adversary would debug the PoC, try variations, and escalate.

**Prevention:**
- Every "attack infeasible" conclusion must include: (1) the exact revert reason or logical impossibility, (2) the specific line of code that blocks the attack, (3) whether the blocker is a structural invariant or a specific value check that might not hold in all states.
- PoCs must be minimal and self-contained. If a PoC is >50 lines of setup, it probably has bugs of its own.
- Pair each "infeasible" conclusion with a mutation test: remove the suspected defensive code and confirm the attack then succeeds. If removing the defense doesn't enable the attack, the defense isn't what's actually blocking it -- further investigation needed.

**Detection:** "Attack infeasible" finding that doesn't cite a specific line of defense in the contract source code.

**Phase:** Attack sessions (PoC review methodology).

---

### Pitfall 11: `fail_on_revert = false` Hides Handler Bugs

**What goes wrong:** With `fail_on_revert = false` (current foundry.toml config), handler functions that revert due to bugs in the handler itself (not the protocol) are silently swallowed. The invariant suite appears healthy but is actually testing almost nothing because every handler call reverts.

**Prevention:**
- During development, temporarily set `fail_on_revert = true` to surface handler bugs. Fix all handler reverts that are handler bugs (vs. expected rejections of invalid fuzzed inputs).
- Then switch to `fail_on_revert = false` for production runs, but with `show_metrics = true` to monitor revert rates.
- Acceptable revert rate: 20-40%. If >60%, handlers need better input bounding via `vm.assume()` or `bound()`.
- In handler functions, use `bound(amount, minValid, maxValid)` instead of `vm.assume()` to avoid rejection-heavy runs.

**Detection:** `show_metrics` output shows >80% revert rate on handler functions.

**Phase:** Harness writing (iterative refinement during handler development).

---

### Pitfall 12: Insufficient Invariant Run Depth for Multi-Step Protocol States

**What goes wrong:** Current config: `runs = 256, depth = 64`. For a protocol where interesting states require 10+ sequential successful steps (purchase at each price tier, VRF fulfill between each, reach milestone level, trigger jackpot), depth=64 seems sufficient but is not. Many of those 64 calls will revert (wrong function, wrong parameters, wrong phase), leaving only 5-15 successful state transitions per run.

**Prevention:**
- For system-level invariants, increase depth to 128-256 and runs to 512-1024. This is a 4-16x increase in compute but worth it for system-level properties.
- Use handler functions that batch multiple protocol steps into a single call (e.g., `handler_advanceThroughLevel()` does purchase+VRF+advance as one atomic handler call). This compresses the effective depth needed.
- Monitor `show_metrics` to count successful state transitions per run. If average successful calls per run is <10, increase depth or improve handler input bounding.

**Detection:** Maximum game level reached across all invariant runs is <3. Increase depth or add batching handlers.

**Phase:** Harness writing (tuning after initial implementation).

## Minor Pitfalls

### Pitfall 13: Artifact Directory Collision Between Toolchains

**What goes wrong:** Foundry writes to `forge-out/` and Hardhat writes to `artifacts/`. Some IDE tools, linters, or scripts may accidentally read the wrong artifact directory, causing confusing ABI mismatches or stale compilation results.

**Prevention:** Keep the current separation (already configured correctly). Add `forge-out/` to `.gitignore` if not already present. Never reference `forge-out/` in Hardhat scripts or vice versa.

**Phase:** Setup.

---

### Pitfall 14: Invariant Testing Only Tests "Normal" Actors

**What goes wrong:** Handler functions use `vm.prank(actors[i])` with a small set of pre-configured actors (alice, bob, carol). The fuzzer never tests calls from unexpected addresses: the zero address, the contract itself, the VRF coordinator address, the deployer/owner, other protocol contracts. Edge-case access control bugs are missed.

**Prevention:**
- Include a mix of privileged and unprivileged actors: owner, random users, contract addresses (Game, Vault, Coin), the VRF coordinator.
- Add specific handler functions that attempt unauthorized actions (e.g., `handler_unauthorizedAdvance()` that pranks a random non-owner address and tries to call admin-only functions).
- Include the Game contract's own address as a potential msg.sender to test self-call/reentrancy scenarios.

**Detection:** Review handler actor list. If it only contains 3-5 regular user addresses, access control invariants are undertested.

**Phase:** Harness writing.

---

### Pitfall 15: Treating Passing Invariants as Proof of Correctness

**What goes wrong:** After the invariant suite passes with 256 runs x 64 depth, the team declares the protocol "fuzz-tested" and uses this as formal evidence in C4 documentation. But 256x64 = ~16K call sequences is a tiny fraction of the state space for 22 contracts with dozens of functions.

**Prevention:**
- Never describe invariant test results as "proving" anything. They increase confidence; they are not formal verification.
- Report invariant testing with honest metrics: runs, depth, revert rate, maximum game state depth reached, ghost variable value ranges observed.
- Pair invariant testing with targeted property-based tests that force specific dangerous states (the existing unit test suite already covers many of these).
- In C4 submission docs, describe invariant testing as "additional dynamic analysis assurance" not "formal verification of correctness."

**Detection:** Any documentation that says "fuzz testing proves X" instead of "fuzz testing found no violations of X across N call sequences."

**Phase:** Reporting.

---

### Pitfall 16: All Adversarial Sessions Share the Same Information Anchor

**What goes wrong:** All 4 adversarial sessions see the same prior audit reports, read the same v1.0/v2.0 findings, and start from the same mental model. They are "blind" in name only. Information overlap causes all sessions to explore the same attack surface and miss the same blind spots.

**Prevention:**
- Vary the information provided to each session:
  - Session 1: Contract source code only. No prior audit results. Fresh-eyes approach.
  - Session 2: Source code + architecture docs (storage layout, deploy order, module pattern). No findings.
  - Session 3: Source code + prior audit's QA/Low findings only (hints at weak spots without revealing the conclusion "safe").
  - Session 4: Full prior audit results, explicitly tasked with "find what v1.0 and v2.0 missed."
- Each session must produce findings independently before any cross-session synthesis.
- The consolidated report should note which sessions found overlapping issues vs. unique issues.

**Detection:** Session 2's findings are a subset of session 1's. Information isolation failed.

**Phase:** Attack sessions (brief design, before any session starts).

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Setup: Compiler alignment | Compiler version mismatch (#3) | Align foundry.toml solc to 0.8.34 immediately |
| Setup: Build verification | Remapping conflicts (#7) | Run `forge build` and fix all import errors before writing tests |
| Setup: Architecture decision | ContractAddresses blocking (#1) | Decide mock-only vs full-deploy strategy per invariant upfront |
| Setup: Artifact isolation | Directory collision (#13) | Verify forge-out/ in .gitignore, no cross-references |
| Harness: Handler design | Poor state coverage (#2) | Write VRF-aware handlers with ghost variables, monitor revert rates |
| Harness: Targeting | Delegatecall module targeting (#6) | ONLY target Game contract and handlers, never modules directly |
| Harness: Invariant strength | Tautological invariants (#8) | Use equalities not inequalities, mutation-test every invariant |
| Harness: Config tuning | fail_on_revert hiding bugs (#11) | Develop with fail_on_revert=true, run with false+show_metrics |
| Harness: Config tuning | Insufficient depth (#12) | Batch protocol steps in handlers, increase depth for system tests |
| Harness: VRF simulation | Game stuck at level 0 (#4) | Handler must include fulfillVRF() as targetable function |
| Harness: Actor diversity | Only normal actors tested (#14) | Include privileged, contract, and adversarial addresses |
| Attack sessions: Brief design | Anchoring bias (#5) | Contradiction-framed briefs, varied methodology per session |
| Attack sessions: Brief design | Information overlap (#16) | Vary information given to each session |
| Attack sessions: Execution | Scope creep (#9) | Strict scope + severity threshold + time box in briefs |
| Attack sessions: PoC quality | Confirmation bias in PoCs (#10) | Require specific defense citation, mutation-test "infeasible" claims |
| Reporting: Claims | False confidence (#15) | Report metrics honestly, never claim "proof" |

## Sources

- [Foundry Book: Invariant Testing](https://book.getfoundry.sh/forge/invariant-testing) -- official documentation on handler patterns, ghost variables, targeting, metrics (HIGH confidence)
- [RareSkills: Invariant Testing in Foundry](https://rareskills.io/post/invariant-testing-solidity) -- handler best practices, common mistakes (MEDIUM confidence)
- [Three Sigma: Foundry Cheatcodes Invariant Testing](https://threesigma.xyz/blog/foundry/foundry-cheatcodes-invariant-testing) -- revert handling, call distribution issues (MEDIUM confidence)
- [Patrick Collins: Fuzz/Invariant Tests as Bare Minimum](https://patrickalphac.medium.com/fuzz-invariant-tests-the-new-bare-minimum-for-smart-contract-security-87ebe150e88c) -- false sense of security from shallow coverage (MEDIUM confidence)
- [horsefacts/weth-invariant-testing](https://github.com/horsefacts/weth-invariant-testing) -- reference implementation of handler-based invariant testing (HIGH confidence)
- [Cyfrin: Smart Contract Fuzzing and Invariants](https://www.cyfrin.io/blog/smart-contract-fuzzing-and-invariants-testing-foundry) -- state coverage limitations (MEDIUM confidence)
- [Cyfrin: Foundry VRF Mock Guide](https://updraft.cyfrin.io/courses/foundry/smart-contract-lottery/deploy-mock-chainlink-vrf) -- deterministic VRF mock patterns (MEDIUM confidence)
- [Kurt Merbeth: Audited, Tested, Still Broken (2025)](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- post-audit failure patterns, economic attack blind spots (MEDIUM confidence)
- [Hardhat Issue #5561: hardhat-foundry compiler settings](https://github.com/NomicFoundation/hardhat/issues/5561) -- compiler config synchronization problems (HIGH confidence)
- [Sigma Prime: Forge Testing Leveling](https://blog.sigmaprime.io/forge-testing-leveling.html) -- progression from unit to invariant testing methodology (MEDIUM confidence)
- Project source: `foundry.toml`, `hardhat.config.js`, `ContractAddresses.sol`, `test/fuzz/*.t.sol`, `test/helpers/deployFixture.js` -- direct inspection (HIGH confidence)
