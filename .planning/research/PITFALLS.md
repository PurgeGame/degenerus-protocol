# Domain Pitfalls

**Domain:** Adding novel zero-day attack surface hunting and automated tooling validation (Slither triage, Halmos symbolic verification, Foundry extended fuzzing) to a 22-contract GameFi protocol that has already passed 4 audit milestones with 0 Medium+ findings across 103 plans and 10 independent blind adversarial agents
**Researched:** 2026-03-05
**Confidence:** HIGH (project-specific analysis of v1-v4 audit history, documented v3 limitations, 2025-2026 post-audit exploit patterns, Halmos/Slither/Foundry tool-specific limitations, cognitive bias research in audit contexts)

---

## How to Read This File

Pitfalls are grouped by severity and tagged with which v5.0 phase should address them:
- **Cognitive** -- Biases specific to "5th pass" auditing after 4 clean milestones
- **Tooling** -- Halmos, Slither, Foundry failure modes and misinterpretation risks
- **Methodology** -- Scope creep, false novelty, anchoring on prior work
- **Composition** -- Cross-contract and cross-tool interaction pitfalls
- **Reporting** -- How to present v5.0 results without inflating or deflating confidence

---

## Critical Pitfalls

Mistakes that render the v5.0 milestone worthless or produce dangerous false confidence.

### Pitfall 1: "5th Pass Confirmation Bias" -- The Protocol-Is-Clean Anchor

**What goes wrong:** Four prior milestones, 103 plans, 10 blind adversarial agents, 1,029 tests -- ALL concluded zero Medium+ findings. The psychological anchor is overwhelming. Every analyst approaching this codebase now carries the implicit prior: "this code is clean." This prior corrupts the investigation. Instead of genuinely hunting zero-days, the analyst pattern-matches against known vulnerability classes, confirms the protocol handles each one correctly (as v1-v4 already showed), and concludes "still clean." The investigation becomes a confirmation exercise, not a discovery exercise.

**Why it happens:** Bayesian reasoning is correct here -- 4 clean passes SHOULD increase prior probability of safety. But the failure mode is treating high prior probability as certainty and adjusting investigation effort accordingly. The analyst unconsciously reduces scrutiny on areas already marked "safe" and increases scrutiny on areas already known to be safe (because those are the areas they understand). This is anchoring bias compounded by effort misallocation.

The 2025-2026 exploit data is clear: ~70% of major DeFi exploits came from protocols that had passed professional audits. The median time between audit completion and exploit is 47 days. "Audited and clean" is not "secure."

**Consequences:** v5.0 produces a report that says "automated tools confirm v1-v4 conclusions." The protocol goes to C4A with inflated confidence. Wardens find a composition bug or precision exploit in an area all 4 milestones glossed over because it "looked fine."

**Warning signs:**
- Analyst spends >60% of effort on areas v1-v4 already covered thoroughly
- Novel attack surface investigation feels like re-checking rather than discovering
- "No issues found" conclusions cite v1-v4 evidence rather than new independent analysis
- Temporal, composition, and EVM-level attack surfaces receive cursory treatment because "the code is simple there"

**Prevention:**
- Start every investigation from the hypothesis "v1-v4 were wrong about this area." Force the analyst to find the specific flaw in prior reasoning before accepting the prior conclusion.
- Allocate investigation time by INVERSE of prior coverage: areas with the most v1-v4 attention get the LEAST v5.0 attention. Areas v1-v4 barely touched (precision edge cases, temporal boundaries, EVM-level weirdness, cross-contract composition under stress) get the MOST attention.
- Use automated tools (Slither, Halmos, Foundry) as independent ORACLES that do not share the same-model bias. If Slither flags something v1-v4 dismissed, investigate it fully rather than reflexively dismissing it.
- Quantify the prior: "v1-v4 examined function X with Y amount of effort. The probability of a bug surviving Y effort is Z. Is Z low enough?" If Z is not quantifiable, the prior is not evidence.

**Detection:** Count the number of genuinely novel attack surfaces investigated (not re-checks of known surfaces). If novel surfaces < 50% of investigation effort, confirmation bias is dominating.

**Phase:** All phases -- this is the meta-pitfall of v5.0.

---

### Pitfall 2: Slither False Positive Fatigue from 636 Pre-Existing Results

**What goes wrong:** Running Slither on this 22-contract, 85K-line codebase produces hundreds of results. The prior milestones already triaged Slither results (v1.0 used two-pass methodology, v2.0 established false-positive classification). The analyst faces a wall of 636+ detector hits, the vast majority of which are known false positives or acknowledged informational findings. Fatigue sets in. The analyst begins bulk-dismissing results by category ("all reentrancy results are false positives because we verified CEI in v2.0 Phase 12"). Buried in the dismissed results is one genuine finding that was not present in prior triage because it involves a cross-detector pattern (e.g., a reentrancy result that is only exploitable BECAUSE of a separate unchecked-return result on the same code path).

**Why it happens:** Slither's false positive rate for reentrancy is ~10.9%, which is good relative to competitors (25-90%), but on 636 results that is still 60+ false positives in reentrancy alone. Triaging 636 results manually is cognitively exhausting. After the 100th false positive, the analyst's threshold for "investigate further" rises dramatically. Results that would have triggered investigation at position #10 get dismissed at position #500.

**Consequences:** A real finding is dismissed as a known false positive. The most dangerous outcome: an analyst creates a bulk exclusion rule (e.g., `--exclude reentrancy-eth`) that suppresses an entire detector category, including the one genuine hit.

**Warning signs:**
- Analyst creates broad exclusion rules (`detectors_to_exclude` by category) rather than per-finding suppression
- Triage rate accelerates as session progresses (spending 5 min per finding initially, 10 sec per finding after an hour)
- New Slither results (from detectors not run in v1.0) receive the same dismissal treatment as re-run detectors
- No cross-detector analysis (investigating whether finding A + finding B compose into a real vulnerability)

**Prevention:**
- NEVER bulk-exclude detector categories. Suppress individual findings with `slither.db.json` entries that include a reason string and the analyst's name/date.
- Triage in REVERSE priority order: start with the detectors NOT run in prior milestones. These are the highest-value results because they have zero prior coverage.
- Run Slither with `--exclude-informational --exclude-low` on first pass to reduce volume, then run full suite only on contracts/functions flagged as interesting.
- Cross-reference Slither results with Foundry fuzzing failures. A Slither reentrancy warning on a function that Foundry invariant testing also flags as boundary-sensitive is NOT a false positive -- it is a composition signal.
- Set a hard triage time limit (e.g., 2 hours). After the limit, STOP triaging and switch to targeted investigation of the 10 most interesting results rather than continuing to bulk-dismiss.
- Use Slither's `--triage-mode` if available, or create a structured triage spreadsheet with columns: detector, function, severity, prior-triage-status, v5.0-assessment, cross-reference.

**Detection:** Check the triage log timestamp deltas. If the last 200 results were triaged in under 30 minutes, fatigue is driving dismissal.

**Phase:** Slither triage phase (early, before manual analysis).

---

### Pitfall 3: Halmos Timeout/Memory Interpreted as "Verified Safe"

**What goes wrong:** v3.0 already encountered this: 7 of 12 Halmos arithmetic properties timed out. v5.0 attempts more ambitious symbolic verification -- cross-contract invariants, multi-step state transitions, precision proofs. Halmos hits path explosion on DegenerusGame (19KB, 100+ storage slots, dozens of branches in `advanceGame()` alone). The solver returns TIMEOUT after consuming gigabytes of memory. The analyst writes "no counterexample found" in the report. This is technically accurate but practically useless -- the solver did not explore enough state space to find a counterexample even if one exists.

**Why it happens:** Halmos performs bounded symbolic execution. Three fundamental limitations collide with this protocol:
1. **Path explosion:** Each branch doubles solver work. `advanceGame()` alone has dozens of branches. With 10 delegatecall modules, the branching factor is enormous.
2. **Nonlinear arithmetic:** Division, multiplication, and modulo operations (used extensively in `PriceLookupLib`, `JackpotModule`, whale pricing) are NP-hard for SMT solvers. Halmos disables nonlinear arithmetic reasoning by default, which means the solver may generate invalid counterexamples or miss real ones.
3. **Loop bounds:** Halmos unrolls loops up to a configurable bound (default: 2). The protocol has loops that iterate over ticket queues, player lists, and level ranges. With bound=2, the solver only checks the first 2 iterations, missing bugs that manifest at iteration 50 or at array boundary crossings.
4. **viaIR compilation:** The bytecode produced by viaIR with optimizer runs=200 may have different branching structure than the source code, further complicating symbolic analysis.

**Consequences:** The report claims "Halmos verified N properties" but the verification is meaningless for properties that timed out. Worse: if the analyst increases timeout to get a "pass" result, Halmos may return SAT (no counterexample) simply because it exhausted its search budget, not because no counterexample exists.

**Warning signs:**
- Halmos run times exceed 10 minutes per property
- Memory usage exceeds 4GB during verification
- Results contain "TIMEOUT" entries described as "likely safe"
- Loop bounds set to 2 (default) for properties that involve iteration over game levels or ticket arrays
- Properties involving division/multiplication report "no counterexample" but `--smt-exp-by-const` and nonlinear reasoning are disabled

**Prevention:**
- Scope Halmos to ISOLATED, PURE properties only: `PriceLookupLib` arithmetic, `BitPackingLib` pack/unpack roundtrip, `MintStreakUtils` calculations. These are small, loop-free, and have well-defined input/output contracts.
- Do NOT attempt full-contract symbolic verification of `DegenerusGame` or `JackpotModule`. It will timeout and produce no value.
- For every property, document: (a) loop bound used, (b) solver timeout, (c) memory peak, (d) result (SAT/UNSAT/TIMEOUT/UNKNOWN). TIMEOUT and UNKNOWN are NOT "verified."
- Use `vm.assume()` aggressively to constrain symbolic inputs to realistic ranges. A uint256 price that can be 0 to 2^256 will explode the solver; constraining to 0.001-100 ETH reduces state space dramatically.
- For properties that involve delegatecall, test the MODULE in isolation (not through DegenerusGame's delegatecall dispatch). This eliminates the branching in the dispatch logic.
- Complement Halmos with Foundry fuzz testing for the SAME properties. If Halmos times out but Foundry fuzz (10K runs) finds no violations, report "fuzz-tested (10K runs, no violations), symbolic verification inconclusive (timeout at Ns)."
- NEVER describe a TIMEOUT result as "verified." The honest language is: "symbolic verification attempted, solver timeout after N seconds with M GB memory at loop bound K. No counterexample found within these bounds. This does NOT constitute proof of correctness."

**Detection:** Any Halmos result described as "verified" that has a corresponding TIMEOUT or UNKNOWN status is misleading. Check the raw Halmos output, not just the summary.

**Phase:** Halmos verification phase (should follow manual analysis, not precede it).

---

### Pitfall 4: Foundry Fuzz Run Count Theater -- 10K Runs on Wrong Invariants

**What goes wrong:** The v5.0 scope calls for "10K+ fuzz runs, 1K+ invariant runs." The analyst increases `fuzz.runs` and `invariant.runs` in `foundry.toml`, runs the existing v3.0 harnesses, watches them pass, and reports "10K fuzz runs, all invariants hold." But the existing harnesses were designed for v3.0's scope -- ETH solvency, BurnieCoin supply, ticket queue integrity, vault shares, game FSM. They do NOT cover v5.0's target areas: precision/rounding exploitation, temporal edge cases, cross-contract state composition, or economic composition attacks.

Running 10K iterations of the WRONG invariants does not improve security confidence. It is run-count theater.

**Why it happens:** Writing new Foundry invariant harnesses is hard. Extending existing ones is easier. The analyst takes the path of least resistance: increase run count on existing tests. The existing tests pass (they passed at 256 runs too). The analyst reports higher numbers without higher coverage.

**Consequences:** v5.0 claims "Foundry fuzzing with 10K+ runs" but the actual NOVEL coverage (precision, temporal, composition) is zero. The run count increase provides logarithmic diminishing returns on already-passing invariants while the genuinely untested surfaces remain untested.

**Warning signs:**
- No new handler contracts or invariant functions are written for v5.0
- The only change to Foundry config is `runs = 10000` in `foundry.toml`
- All reported invariants were already passing at 256 runs in v3.0
- No invariants test precision/rounding, temporal boundaries, or cross-module state composition
- Test execution time increases 40x but coverage metrics do not change

**Prevention:**
- v5.0 MUST write NEW invariant harnesses targeting v5.0-specific attack surfaces:
  1. **Precision invariant:** For every division operation, the cumulative rounding error over N operations must be bounded. Handler: execute N sequential purchases with varying quantities, assert total ETH collected equals expected within epsilon.
  2. **Temporal invariant:** Advance block.timestamp in steps of 1, 899, 900, 901, and 1800 seconds between operations. Assert no state divergence from expected behavior at timestamp boundaries.
  3. **Composition invariant:** Execute sequences of operations across multiple modules (purchase + whale bundle + lootbox + claim) and assert no ETH is created or destroyed in aggregate.
  4. **Zero-rounding invariant:** For every path where division occurs, provide inputs that result in zero quotient (dust amounts). Assert the protocol handles zero-result divisions correctly (no free actions, no locked funds).
- Use Foundry's coverage-guided fuzzing (available since v1.3.0): set `corpus_dir` in `foundry.toml` to enable mutation-based sequence generation that targets new code paths.
- Track coverage metrics BEFORE and AFTER increasing runs. If coverage does not increase between 256 and 10,000 runs, the additional runs are pure waste.
- Use ghost variables in handlers to track cumulative state (total minted, total claimed, total rounding errors) that is not stored on-chain. These are the invariant surfaces that v3.0 handlers missed.

**Detection:** Compare code coverage at 256 runs vs 10,000 runs. If coverage is identical, the runs are not discovering new paths. Check whether any NEW invariant functions exist that were not in v3.0.

**Phase:** Foundry fuzzing phase (should include new harness development, not just run count increase).

---

### Pitfall 5: Anchoring on Known Vulnerability Classes Instead of Novel Surfaces

**What goes wrong:** v5.0 explicitly targets "novel zero-day attack surfaces" -- composition bugs, precision exploitation, temporal edge cases, EVM-level weirdness. But the analyst's mental model of "vulnerability" is trained on KNOWN classes: reentrancy, access control bypass, integer overflow, oracle manipulation. The analyst checks these known classes (which v1-v4 already thoroughly covered), finds nothing, and reports "no novel vulnerabilities found." The analyst never genuinely investigated novel surfaces because they do not have a mental checklist for them.

**Why it happens:** Known vulnerability classes are cognitive anchors. SWC registry, OWASP Smart Contract Top 10, Code4rena historical findings -- these provide checklists. Novel surfaces have no checklist. Investigating "cross-contract state composition bugs" requires creative reasoning about how modules interact in ways nobody has enumerated. This is fundamentally harder than checking against a list, and without a list, the analyst defaults to what they know.

Industry data confirms this: approximately half of high and critical vulnerabilities come from application-specific logic errors that do not map to any known vulnerability class. These are exactly the bugs that checklist-based auditing misses.

**Consequences:** v5.0 becomes "v1-v4 re-run with automated tools" instead of a genuinely novel investigation. The novel surfaces that justify v5.0's existence go unexplored.

**Warning signs:**
- Investigation report is organized by SWC categories or known vulnerability types
- All attack vectors tested are variations of: reentrancy, access control, overflow, oracle manipulation, frontrunning
- No investigation of: delegatecall storage composition under concurrent module calls, BitPackingLib field boundary corruption from adjacent field writes, rounding accumulation across purchase+claim+lootbox+whale paths, timestamp-boundary state divergence between modules
- The word "novel" appears in the report summary but not in the actual findings

**Prevention:**
- Structure v5.0 investigation by PROTOCOL-SPECIFIC SURFACES, not by vulnerability class:
  1. **Delegatecall composition:** What happens when Module A writes to storage slot S, then Module B reads slot S+1 in the same transaction? Are there any cross-module storage dependencies that create unexpected state?
  2. **Precision chains:** Trace a single wei through the entire purchase-to-claim lifecycle. At each division, track the remainder. Can an attacker construct inputs that maximize cumulative rounding in their favor?
  3. **Temporal boundaries:** What is the protocol's behavior at exactly `block.timestamp = deadline`? At `deadline - 1`? At `deadline + 1`? For every time-gated operation, test the boundary conditions.
  4. **EVM-level:** Can `selfdestruct` (or `SELFDESTRUCT` via legacy contracts) force ETH into contracts that do not expect it, breaking solvency invariants? Can ABI encoding produce selector collisions with existing functions? Can `DELEGATECALL` to a module that `SSTORE`s at a computed slot corrupt unrelated storage?
  5. **Economic composition:** Can an attacker profit by executing a sequence across multiple protocol contracts (buy tickets in Game, flip coins in Coinflip, claim vault shares in Vault, sell tokens on Uniswap) that no single contract would consider an exploit?
- For each surface, define what "novel" means operationally: a finding is novel if it cannot be described using any SWC ID, OWASP category, or prior audit finding. If it can be, it is a re-check, not discovery.
- Require at least 50% of investigation time on surfaces that have NO prior v1-v4 coverage whatsoever.

**Detection:** Map each v5.0 finding or investigation to a v1-v4 phase. If >70% of investigations map to prior phases, anchoring is dominating.

**Phase:** All manual analysis phases.

---

## Moderate Pitfalls

### Pitfall 6: Composition Analysis Scope Creep

**What goes wrong:** "Cross-contract state composition" sounds important but has unbounded scope. With 22 contracts and 10 modules, there are 22*21/2 = 231 pairwise contract interactions and 10*9/2 = 45 pairwise module interactions. Investigating all 276 pairs thoroughly is infeasible. The analyst either: (a) investigates a few pairs shallowly and declares "composition analysis complete," or (b) investigates deeply but runs out of time after 10 pairs, leaving 266 pairs unexplored and the other v5.0 targets (precision, temporal, EVM) unaddressed.

**Why it happens:** Composition analysis is inherently combinatorial. Without a principled scoping strategy, the analyst either drowns in combinations or cherry-picks the obvious ones (which v1-v4 already covered).

**Prevention:**
- Scope composition analysis to DELEGATECALL modules only (10 modules sharing DegenerusGameStorage). These are the only contracts that share state via delegatecall, making composition bugs possible. Regular inter-contract calls use message passing and do not share storage.
- Within delegatecall modules, prioritize pairs that WRITE to overlapping storage slots. Use `forge inspect` storage layout output to build a slot-ownership matrix. Module pairs with shared write slots are the composition risk.
- Time-box composition analysis to 30% of total v5.0 effort. If 30% is exhausted, stop and move to precision/temporal/EVM surfaces.
- The 22 non-module contracts interact via external calls with defined interfaces. These are lower composition risk because each contract validates its own state. Focus on the 10 delegatecall modules where the security boundary is fuzzy.

**Detection:** Composition analysis consuming >50% of total milestone effort with no clear stopping criterion.

**Phase:** Composition analysis phase (must have explicit scope boundaries).

---

### Pitfall 7: Slither Detector Version Mismatch

**What goes wrong:** Slither versions ship with different detectors. If v5.0 runs a different Slither version than v1.0's triage, results are not directly comparable. New detectors may produce findings that were not present in the v1.0 triage. Old detectors may have been fixed, making prior false-positive classifications invalid. The analyst compares v5.0 results against v1.0 triage entries without accounting for detector version changes.

**Why it happens:** Slither is actively maintained. Between v1.0 (early March 2026) and v5.0, Slither may have released updates with new or modified detectors. The `slither.db.json` from v1.0 may not apply to v5.0's Slither version.

**Prevention:**
- Document the exact Slither version and commit hash used in v5.0.
- If using a different version than v1.0, re-run ALL detectors and triage from scratch rather than relying on v1.0's `slither.db.json`.
- If using the same version, still check for detector configuration differences (hardhat vs foundry compilation, solc version passed to Slither).
- Note: Slither may struggle with viaIR compilation artifacts. If Slither produces unexpected errors or zero results on some contracts, check whether viaIR is causing compilation mismatches.

**Detection:** Slither result count differs significantly from v1.0 (e.g., 636 vs 400 or 636 vs 900) without explanation.

**Phase:** Slither setup and triage phase.

---

### Pitfall 8: Treating Foundry Invariant "Pass" as Proof When Handlers Are Too Constrained

**What goes wrong:** v3.0 already has 48 invariant tests. The handlers in v3.0 were designed to exercise specific state transitions. But handlers that are too constrained (e.g., only calling `purchase()` with quantity 100-400 and level 0-3) will never discover bugs that manifest at quantity=1 (minimum), quantity=40000 (maximum), or level=99 (cycle boundary). The invariants "pass" because the handler never generates the inputs that would violate them.

**Why it happens:** Handler design requires domain knowledge. The v3.0 handlers were good for their purpose but acknowledged limitations: "no Degenerette fuzzing, no vault deposit/withdraw fuzzing, limited deep-game-state coverage." These limitations mean the handlers are scoped to a fraction of the input space. Increasing run count does not fix handler scope -- it just runs the same constrained inputs more times.

**Prevention:**
- Audit the existing v3.0 handlers BEFORE increasing run count. For each handler:
  1. What is the range of each input parameter?
  2. Does the range cover all valid inputs, including boundary values?
  3. Are there protocol states the handler can never reach?
- Write adversarial handlers that specifically target boundaries:
  - `purchase()` with qty=1 (minimum), qty=40000 (100 full tickets, maximum reasonable), qty at exact price thresholds
  - Operations at level=0 (entry), level=99 (cycle boundary), level=100 (next cycle start)
  - Timestamps at exactly `18 hours` (VRF retry), `3 days` (emergency stall), `912 days` (pre-game timeout)
  - ETH amounts at 1 wei (dust), at exactly `priceWei` (exact match), at `priceWei - 1` (just under)
- Use Foundry's `bound()` helper to constrain fuzzer inputs to interesting ranges rather than uniform random.
- Add ghost variables to handlers tracking state that invariants should check but currently do not.

**Detection:** Compare handler input ranges to the valid input domain. If handler covers <50% of the valid domain, increasing run count is futile.

**Phase:** Foundry harness development phase.

---

### Pitfall 9: EVM-Level Investigation That Stays at Source Level

**What goes wrong:** v5.0 targets "EVM-level weirdness" -- selfdestruct ETH forcing, ABI encoding collisions, selector collisions, BitPackingLib corruption. But the analyst investigates these at the Solidity source level rather than the bytecode level. Source-level analysis misses compiler-introduced behaviors: viaIR stack management, optimizer-introduced jump patterns, and ABI encoder v2 edge cases that do not map to source constructs.

**Why it happens:** Reading EVM bytecode is hard. Reading Solidity source is easy. The analyst defaults to the easier task.

**Prevention:**
- For selector collision analysis: use `forge inspect [contract] methodIdentifiers` to get actual 4-byte selectors, not manual keccak256 computation from source.
- For ETH-forcing analysis: check whether any contract has a `receive()` or `fallback()` function and whether its solvency invariant accounts for ETH received outside normal paths.
- For BitPackingLib: verify pack/unpack roundtrip at the bytecode level using Halmos (this is a good Halmos target -- small, pure, bounded).
- For ABI encoding: check for `abi.encodePacked` with variable-length arguments (known collision risk). If found, construct concrete collision examples.
- Run `forge inspect DegenerusGame asm` on the two most critical functions (`advanceGame`, `claimWinnings`) and verify the assembly matches source-level expectations for: (a) storage reads/writes are to expected slots, (b) external calls have expected calldata, (c) no unexpected DELEGATECALL or STATICCALL.

**Detection:** EVM-level section of report contains zero bytecode references, zero `forge inspect` output, and zero analysis of compiled artifacts.

**Phase:** EVM-level investigation phase.

---

### Pitfall 10: Precision/Rounding Analysis That Checks Individual Operations Instead of Chains

**What goes wrong:** The analyst checks each division operation individually: "this division rounds down, losing at most 1 wei -- negligible." This per-operation analysis misses CUMULATIVE rounding across a chain of operations. Real-world exploits in 2025 demonstrated this: rounding errors measured as "less than 1 wei per swap" were "treated as negligible," but "no invariant was asserted over N repeated operations" and "fuzzers without stateful sequence modeling couldn't discover this."

In this protocol, a purchase involves: price lookup (division for level-based pricing) -> cost calculation (multiplication then division by 400) -> prize pool split (90/10 division) -> potential jackpot calculation (division) -> potential lootbox EV (division). Each step loses at most 1 wei, but 5 divisions in sequence could lose 5 wei per purchase. Over 10,000 purchases, the cumulative error is 50,000 wei -- still negligible in ETH terms. But if an attacker can construct inputs that maximize rounding in their favor at each step (e.g., purchasing exactly the quantity where division truncation gives them 1 extra wei of claim), the cumulative effect over many transactions could be meaningful.

**Why it happens:** Per-operation rounding analysis is the standard approach. Chain analysis requires tracing values through multiple function calls and tracking cumulative error bounds. This is tedious and protocol-specific. No automated tool does it well.

**Prevention:**
- Map the complete "wei lifecycle" through the protocol: ETH enters via `purchase()` or `purchaseWhaleBundle()`, flows through prize pool split, sits in `currentPrizePool`/`futurePrizePool`, exits via `claimWinnings()` or `claimLoot()`. At each transformation, note the rounding direction (floor vs ceil) and maximum error.
- Compute the worst-case cumulative rounding error over N transactions. If the error is always in the protocol's favor (floor rounding on payouts), this is safe. If the error can be in the user's favor (floor rounding on costs), an attacker can extract value.
- Write a Foundry invariant that tracks cumulative rounding: `sum_of_all_costs_paid >= sum_of_all_prizes_claimed + contract_balance_delta`. If this invariant fails under fuzzing, there is a rounding exploit.
- Check the specific formula: `costWei = (priceWei * ticketQuantity) / 400`. With `ticketQuantity = 1`, this gives `priceWei / 400`, which for `priceWei = 0.01 ether = 10^16 wei` gives `2.5 * 10^13 wei` -- no rounding. But for non-standard prices or quantities not divisible by 400, rounding occurs. Enumerate these cases.

**Detection:** Rounding analysis that uses the phrase "at most 1 wei" for each operation without computing the aggregate across the full transaction lifecycle.

**Phase:** Precision analysis phase.

---

### Pitfall 11: Temporal Analysis That Tests Minutes But Not Multi-Block Boundaries

**What goes wrong:** The analyst tests timestamp manipulation within the +/- 900 second tolerance (v2.0 already verified this). But temporal edge cases in this protocol span MUCH longer timescales: 18 hours (VRF retry), 3 days (emergency stall), 30 days (final sweep), 365 days (inactivity), 912 days (pre-game timeout). The analyst tests the well-understood 900-second boundary but misses the interaction between MULTIPLE time-gated mechanisms. Example: what happens when VRF retry timeout (18h) fires at the exact same timestamp as emergency stall (3 days)? Is there a race condition between these two recovery mechanisms?

**Why it happens:** Short-timescale temporal analysis (minutes/hours) is easy to test. Long-timescale interactions (days/years) require advancing the EVM timestamp significantly, which changes many protocol states simultaneously. The analyst tests each timeout in isolation rather than testing timeout INTERACTIONS.

**Prevention:**
- Map all time-gated state transitions in the protocol with their exact thresholds.
- For each PAIR of time gates, compute whether they can fire simultaneously or within the same block. If they can, write a test that triggers both in the same transaction and verify the protocol handles the composition correctly.
- Test the "time gap" attack: advance timestamp by exactly the difference between two timeouts in a single `vm.warp()` call. Does the protocol process both timeouts correctly when they overlap?
- Test the "stale state" attack: advance timestamp far beyond all timeouts (e.g., +1000 days). Does the protocol handle the case where ALL time-gated mechanisms have expired simultaneously?

**Detection:** Temporal analysis that tests each timeout in isolation but never tests timeout interactions or simultaneous expiration.

**Phase:** Temporal edge case phase.

---

## Minor Pitfalls

### Pitfall 12: Running All Three Tools Sequentially Instead of Cross-Referencing

**What goes wrong:** The analyst runs Slither, triages results, files report. Then runs Halmos, documents results, files report. Then runs Foundry fuzzing, documents results, files report. Each tool produces independent findings that are never cross-referenced. A Slither warning about "unprotected delegatecall" on the same function where Halmos times out on a storage invariant and Foundry fuzzing shows a boundary value anomaly -- these three signals together point to a real issue that none of them individually would surface.

**Prevention:**
- After each tool run, create a function-level signal matrix: which functions were flagged by which tools, at what severity.
- Functions flagged by 2+ tools are HIGHEST PRIORITY for manual investigation, regardless of individual tool severity.
- Functions flagged by zero tools are SECOND HIGHEST PRIORITY -- they may be blind spots shared by all three tools.
- Functions flagged by exactly one tool at low severity are lowest priority.

**Detection:** Final report has three separate tool sections with no cross-reference analysis.

**Phase:** Synthesis phase (after all tool runs complete).

---

### Pitfall 13: View Function Abuse Gets Skipped Because "Views Can't Change State"

**What goes wrong:** v5.0's scope includes "view function abuse." The analyst dismisses this because view functions are `view` or `pure` -- they cannot modify state by EVM rules. But view function abuse is about INFORMATION LEAKAGE and ORACLE MANIPULATION, not direct state changes. If a view function returns stale or manipulable data that other contracts or off-chain systems rely on, the view function is the attack vector even though it does not modify state.

In this protocol, view functions like `purchaseInfo()`, `priceForLevel()`, and pool balance queries may be called by off-chain systems (frontend, bots) or potentially by other protocols that integrate with Degenerus. If these views can return inconsistent data during multi-step operations (e.g., `purchaseInfo().priceWei` between VRF request and fulfillment), external systems may act on stale data.

**Prevention:**
- Enumerate all `view` and `pure` external functions.
- For each, determine: who calls this? If only the frontend, low risk. If other on-chain contracts could call this, medium risk.
- For view functions that read state modified by pending VRF callbacks, determine whether the return value is consistent before and after callback execution. Inconsistency is not a vulnerability in isolation but could be exploitable by flash bots or MEV searchers.
- Check whether any view function performs `staticcall` to external contracts (VRF coordinator, stETH). The external contract's behavior during `staticcall` may differ from expectations.

**Detection:** v5.0 report that does not mention view functions at all, or dismisses them with "cannot change state."

**Phase:** Manual analysis phase (novel surfaces).

---

### Pitfall 14: Reporting v5.0 Results Without Calibrating Against Prior Milestones

**What goes wrong:** v5.0 produces findings (or "no findings"). The report presents these in isolation without contextualizing against v1-v4. If v5.0 finds a Low issue, is it NEW (missed by 4 prior milestones and 10 blind agents) or is it a RE-DISCOVERY of a known acknowledged Low? If v5.0 finds nothing, is that because the protocol is genuinely secure, or because v5.0's investigation overlapped entirely with v1-v4's coverage?

**Prevention:**
- Every v5.0 finding must be cross-referenced against v1-v4's cumulative 6 Low and 44 QA/Info findings. Is this finding new or duplicative?
- "No findings" reports must include a coverage delta: what did v5.0 investigate that v1-v4 did NOT? If the coverage delta is empty, v5.0 added no value.
- The v5.0 report must explicitly answer: "What can v5.0's automated tools tell us that 4 milestones of manual analysis could not?"
- Calibrate confidence honestly: "v5.0 automated tooling covers X% of contract surface with Y% of input space. Combined with v1-v4 manual analysis, total coverage is estimated at Z%."

**Detection:** v5.0 report that does not reference any prior milestone or does not distinguish novel findings from re-discoveries.

**Phase:** Final reporting phase.

---

### Pitfall 15: Writing Halmos Properties That Are Trivially True

**What goes wrong:** The analyst writes Halmos properties like `assert(x + y >= x)` (trivially true in Solidity 0.8.x due to overflow protection) or `assert(balance >= 0)` (trivially true for uint256). These properties verify compiler guarantees, not protocol invariants. They always pass, producing "verified" results that inflate the report without testing anything meaningful.

**Prevention:**
- Every Halmos property must reference a protocol-specific invariant, not a language invariant. "Pack then unpack returns original value" is protocol-specific (tests BitPackingLib). "Addition does not overflow" is a language invariant (tested by the compiler).
- Before writing a Halmos property, ask: "Could this property fail if the CODE is wrong but the COMPILER is correct?" If the answer is no, the property is trivial.
- Focus Halmos on properties where the protocol deviates from standard patterns: custom bit packing, manual slot computation in assembly, unchecked blocks, division chains.

**Detection:** Halmos properties that do not reference any contract function or storage variable are testing the compiler, not the protocol.

**Phase:** Halmos property design phase.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Slither triage | False positive fatigue (#2) | Per-finding suppression, reverse priority order, time-box to 2 hours |
| Slither triage | Detector version mismatch (#7) | Document version, re-triage if version differs from v1.0 |
| Halmos verification | Timeout = "verified" (#3) | Scope to isolated pure functions, honest bounds reporting |
| Halmos verification | Trivially true properties (#15) | Protocol-specific invariants only, test the code not the compiler |
| Foundry fuzzing | Run count theater (#4) | New harnesses for v5.0 surfaces, coverage metrics before/after |
| Foundry fuzzing | Constrained handlers (#8) | Audit handler input ranges, write boundary-targeting handlers |
| Manual: Composition | Scope creep (#6) | Delegatecall modules only, time-box to 30% of effort |
| Manual: Composition | Source-only analysis (#9) | forge inspect, bytecode verification of critical functions |
| Manual: Precision | Per-operation not chain (#10) | Wei lifecycle tracing, cumulative rounding invariant |
| Manual: Temporal | Isolated timeout testing (#11) | Timeout interaction matrix, simultaneous expiration tests |
| Manual: EVM-level | Stays at source level (#9) | forge inspect, selector enumeration, ABI encoding review |
| Manual: View functions | Dismissed as non-writable (#13) | Information leakage analysis, staticcall edge cases |
| All phases | Confirmation bias (#1) | Inverse coverage allocation, hypothesis inversion |
| All phases | Anchoring on known classes (#5) | Protocol-specific surface structuring, 50% novel allocation |
| Cross-tool synthesis | Sequential not cross-referenced (#12) | Function-level signal matrix, multi-tool flag prioritization |
| Final report | Uncalibrated results (#14) | Coverage delta from v1-v4, novel vs duplicative finding classification |

## Sources

- [Audited, Tested, and Still Broken: Smart Contract Hacks of 2025](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Rounding exploit patterns, "no invariant over N operations," stateful sequence modeling gap (MEDIUM confidence)
- [The State of Web3 Security in 2025: Why Most Exploits Come From Audited Contracts](https://olympix.security/blog/the-state-of-web3-security-in-2025-why-most-exploits-come-from-audited-contracts) -- 70% of exploits from audited contracts, composition failures (MEDIUM confidence)
- [QuillAudits: Why Audited Contracts Still Get Hacked](https://www.quillaudits.com/blog/smart-contract/smart-contract-pass-audits-but-still-gets-hacked) -- External dependency blind spots, business logic errors, 47-day median exploit time (MEDIUM confidence)
- [Halmos GitHub Wiki: Errors](https://github.com/a16z/halmos/wiki/errors) -- Timeout handling, path explosion mitigation, loop bound configuration (HIGH confidence)
- [Halmos GitHub Wiki: Warnings](https://github.com/a16z/halmos/wiki/warnings) -- Bounded execution limitations, nonlinear arithmetic disabled by default (HIGH confidence)
- [a16z: Symbolic Testing with Halmos](https://a16zcrypto.com/posts/article/symbolic-testing-with-halmos-leveraging-existing-tests-for-formal-verification/) -- vm.assume() optimization, minimal test scope recommendation (HIGH confidence)
- [a16z: Formal Verification of Pectra System Contracts with Halmos](https://a16zcrypto.com/posts/article/formal-verification-of-pectra-system-contracts-with-halmos/) -- Practical Halmos usage on production contracts (HIGH confidence)
- [Slither GitHub](https://github.com/crytic/slither) -- 10.9% false positive rate for reentrancy, detector configuration, slither.db.json (HIGH confidence)
- [Trail of Bits: Slither Framework](https://blog.trailofbits.com/2018/10/19/slither-a-solidity-static-analysis-framework/) -- Triage methodology, detector architecture (HIGH confidence)
- [Foundry Book: Invariant Testing](https://book.getfoundry.sh/forge/invariant-testing) -- Handler-based approach, runs/depth configuration, coverage-guided fuzzing (HIGH confidence)
- [RareSkills: Invariant Testing in Foundry](https://rareskills.io/post/invariant-testing-solidity) -- Ghost variables, handler design patterns, bound() usage (HIGH confidence)
- [Cyfrin: Fuzz / Invariant Tests as Bare Minimum](https://patrickalphac.medium.com/fuzz-invariant-tests-the-new-bare-minimum-for-smart-contract-security-87ebe150e88c) -- Stateful sequence modeling, coverage vs run count tradeoff (MEDIUM confidence)
- [Smart Contract Security Risks and Audits Statistics 2026](https://coinlaw.io/smart-contract-security-risks-and-audits-statistics/) -- Industry audit failure rates (MEDIUM confidence)
- [Hacken: Top 10 Smart Contract Vulnerabilities in 2025](https://hacken.io/discover/smart-contract-vulnerabilities/) -- Application-specific logic errors as ~50% of high/critical findings (MEDIUM confidence)
- v3.0 Consolidated Report (18-REPORT.md) -- 7 documented coverage limitations, same-auditor bias acknowledgment (HIGH confidence, project source)
- v4.0 Synthesis Report (29-01-SUMMARY.md) -- 10/10 agents unanimous zero Medium+, 5 Low, 30 QA/Info (HIGH confidence, project source)
- PROJECT.md v5.0 milestone context -- Target areas, tooling scope, prior milestone results (HIGH confidence, project source)
