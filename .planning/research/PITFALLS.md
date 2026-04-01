# Domain Pitfalls: C4A Contest Dry Run for Heavily Self-Audited Protocol

**Domain:** Competitive audit readiness for on-chain ETH game (24 contracts, ~25K lines Solidity, 25+ internal audit milestones)
**Researched:** 2026-03-28
**Overall confidence:** HIGH (patterns drawn from real C4A contest outcomes, post-audit exploits, and cognitive bias research)

---

## Critical Pitfalls

Mistakes that produce payable Medium+ findings despite extensive internal review. Ranked by likelihood of producing a payable finding in this specific protocol.

---

### Pitfall 1: Monoculture Analytical Bias (RANK: 1 -- HIGHEST RISK)

**What goes wrong:** All 25+ audit milestones used the same analytical framework: Claude agents with the same system prompts, same reasoning patterns, same investigation methodology. This creates a systematic blind spot -- every pass reinforces the same mental model of the code rather than challenging it. If the model has a fundamental misunderstanding of how a subsystem works, 50 passes will reproduce that misunderstanding 50 times.

**Why it happens:** Confirmation bias is the most prevalent cognitive bias in audit practice. Auditors favor information that supports preconceived notions while disregarding contradictory evidence. When the same tool says "SAFE" 25 times, the team internalizes "SAFE" as fact rather than "one analytical perspective says SAFE." Overconfidence bias compounds this: auditors develop a mistaken sense of conviction about the correctness of their findings after repeated review.

**Consequences:** A C4A warden using a completely different analytical approach (manual line-by-line, Echidna/Medusa stateful fuzzing, economic modeling, or reading the code from a different entry point) discovers a vulnerability class the monoculture never tested.

**Specific risk for this protocol:**
- All RNG proofs trace the same forward path (request -> fulfillment -> usage). A warden tracing backward from each consumer function may find an unconsidered path.
- All economic analysis used the same rational-actor model. A warden using mechanism design theory or adversarial game theory may find extraction vectors the model never constructed.
- The delegatecall module architecture (10 modules sharing DegenerusGameStorage) was audited module-by-module. A warden examining cross-module state transitions during a single transaction may find inconsistencies in the shared storage mental model.
- Every milestone's agent started with the accumulated context of all prior milestones. No agent started truly fresh. The entire audit corpus is tainted by shared priors.

**Prevention:**
1. Each dry-run warden MUST start from zero context -- no access to prior audit findings, no prior "SAFE" conclusions. Give them only the contracts and the C4A README.
2. Mandate at least one warden who reads the code backward: start from ETH outflows and trace back to what controls them.
3. Use a different fuzzing tool (Echidna or Medusa) rather than only Foundry fuzz, specifically for stateful sequence testing.
4. Explicitly instruct wardens: "Assume every prior SAFE verdict is wrong. Your job is to disprove it."

**Detection:** If a dry-run warden's investigation path mirrors prior audit phases (same functions, same order, same conclusions), the monoculture has infected the fresh-eyes pass.

---

### Pitfall 2: Cross-Module State Transition Seams (RANK: 2)

**What goes wrong:** The 10 delegatecall modules all execute in DegenerusGame's storage context. Internal audits verified each module's correctness in isolation and verified 13 composability sequences as SAFE (v5.0). But the real attack surface is the state transitions BETWEEN modules during complex multi-step operations (advanceGame touching AdvanceModule -> JackpotModule -> EndgameModule -> GameOverModule in sequence). A state assumption made by module B about what module A left in storage may be violated under specific edge-case orderings.

**Why it happens:** Delegatecall shared storage is audited by verifying storage layout compatibility (forge inspect) and individual module correctness. But the SEMANTIC meaning of storage values can differ between modules' assumptions. Module A writes a value meaning "in progress," module B reads it meaning "completed." This class of bug is invisible to storage layout verification and to module-by-module correctness proofs.

**Consequences:** GMX lost $42M to exactly this pattern -- vulnerability existed at boundaries between oracles, margin calculations, and liquidation logic, not in any single component. The 2025 post-mortem specifically noted: "Traditional audit processes typically focus heavily on components in isolation."

**Specific risk for this protocol:**
- `advanceGame` dispatches through multiple modules sequentially via delegatecall. If any module's intermediate state is observable or manipulable between delegatecalls (e.g., through a callback during ETH transfer), a reentrancy vector may exist that crosses module boundaries.
- The rngLocked flag, prizePoolsPacked variables, and daily jackpot state are all written by multiple modules. If two modules have subtly different invariant assumptions about these shared variables, the seam is exploitable.
- The BAF cache-overwrite bug (v4.4) was exactly this class: one module read futurePrizePool into a local, another module modified the underlying storage, and the first module's write-back clobbered the change. This pattern could recur in any module pair that shares mutable state.

**Prevention:**
1. Map every advanceGame execution path as a COMPLETE state machine, not module-by-module. Document the exact storage state at each module transition boundary.
2. Write Foundry invariant tests that fuzz the MODULE TRANSITION points, not just individual module functions.
3. Verify no external calls (ETH transfers, token transfers) occur between module delegatecalls within a single top-level transaction where the intermediate state could be observed.
4. For each storage variable written by multiple modules, document which modules may write it and verify no write can clobber another module's in-progress work.

**Detection:** Search for any storage variable written by module A and read by module B where the write and read happen in different delegatecall frames within the same transaction.

---

### Pitfall 3: Rounding Error Accumulation in Multi-Step Operations (RANK: 3)

**What goes wrong:** Individual BPS calculations are verified correct (round down on payouts, up on burns). But when multiple BPS calculations chain together in a single transaction (ETH split across 5+ pools, each with its own BPS calculation), the accumulated rounding errors can create a deficit or surplus that violates the solvency invariant under specific input amounts.

**Why it happens:** Auditors test each BPS calculation independently and verify the invariant "balance >= claimablePool" holds. But they test with typical values, not adversarial values chosen to maximize rounding error accumulation. Balancer lost $70-128M to exactly this: "Standard audit processes tested individual swaps, not sequences of hundreds or thousands. Rounding errors were measured as less than 1 wei per swap and treated as negligible."

**Specific risk for this protocol:**
- ETH from ticket purchases splits across current pool, future pool, whale pool, affiliate pool, lootbox pool, reward pool, earlybird pool. Each split is a separate BPS division. The sum of distributed amounts may not equal the input amount, leaving wei dust that either accumulates (solvency surplus, benign) or is over-distributed (solvency deficit, critical).
- stETH transfers lose 1-2 wei per operation due to shares-to-balance rounding (documented Lido behavior). Combined with BPS rounding in the same payout path, the compound effect may exceed documented bounds.
- The coinflip system with variable payout ratios (25-175 range from RNG) multiplied against burned amounts introduces another rounding surface.
- Cork Protocol lost $12M because they "assumed 1:1 wstETH-to-ETH relationship" and auditors treated all ERC-20 tokens identically despite LSTs' hidden state changes.

**Prevention:**
1. Write a Foundry fuzz test that calls the FULL purchase-to-payout cycle with adversarially chosen ETH amounts (1 wei, 2 wei, max uint128, prime numbers near BPS boundaries) and checks that total distributed == total received, with explicit accounting for documented rounding.
2. Verify the "total distributed <= total received" invariant across ALL multi-step operations, not just individual calculations.
3. Specifically test stETH conversion paths with amounts that maximize the shares-to-balance rounding error.
4. Test cumulative rounding over hundreds of sequential operations, not just individual operations.

**Detection:** Compare `address(this).balance` before and after a complete transaction cycle. Any unexpected delta beyond documented rounding bounds is a finding.

---

### Pitfall 4: Game-Over Boundary State Machine Violations (RANK: 4)

**What goes wrong:** The transition from "game active" to "game over" is a state machine change that affects EVERY subsystem simultaneously. Internal audits verified each subsystem's game-over behavior independently (coinflip claims resolve, pools distribute, passes refund). But the state machine transition itself -- the exact block/transaction where game-over triggers -- creates a window where some subsystems believe the game is active and others believe it is over.

**Why it happens:** The game-over condition is checked within advanceGame. Between the point where game-over is detected and the point where ALL subsystems are notified, there may be functions callable by external actors that operate under stale "game active" assumptions. This was partially addressed (CP-06, Seam-1 fixes), but the general pattern -- state transition window between detection and full propagation -- is a category that benefits from fresh eyes because the internal team has already classified it as "fixed."

**Specific risk for this protocol:**
- Degenerette bets placed in the same block as game-over may resolve differently depending on transaction ordering.
- Lootbox RNG requests pending at game-over may have fulfillment paths that assume game-active state.
- Deity pass refund calculations at game-over may use pool values that have already been partially distributed.
- The 120-day inactivity timeout is a separate game-over trigger with potentially different propagation characteristics than the normal endgame trigger.

**Prevention:**
1. List EVERY external function that reads game state. For each, verify behavior is correct during the game-over transition block -- not just before and after, but DURING.
2. Write a Foundry test that triggers game-over in the middle of a multi-transaction block and verifies no function can be called that produces incorrect results in the same block.
3. Map the exact ordering of game-over state changes and verify no observable intermediate state allows exploitation.
4. Verify both game-over triggers (endgame and inactivity timeout) have identical propagation behavior.

**Detection:** Grep for all reads of game-over state flags and verify each caller handles the transition edge case.

---

### Pitfall 5: VRF Fulfillment Timing Assumptions (RANK: 5)

**What goes wrong:** The protocol assumes VRF fulfillment arrives "eventually" and handles stalls with a 12h timeout. The window between VRF request and fulfillment is a period where player-controllable state may change in ways that influence the RNG outcome. Internal audits proved 51/51 general paths SAFE and 9/9 specific paths SAFE. But these proofs all used the same analytical model of what "influence" means.

**Why it happens:** The Chainlink VRF $300K bounty demonstrated that "a malicious VRF subscription owner could prevent users from getting neutral randomness by blocking and rerolling randomness until they received a desired value." While this specific vector does not apply here, the interaction between VRF timing and on-chain state changes is exactly the class of vulnerability where fresh-eyes analysis adds value because the internal team's definition of "safe" may be narrower than a warden's.

**Specific risk for this protocol:**
- The rngLocked flag provides mutual exclusion. But if there are ANY code paths where rngLocked can be bypassed or where state changes are made that do not check rngLocked, the commitment window proofs are invalidated.
- The phaseTransitionActive exemption to rngLocked (allowing advanceGame-origin writes) is an intentional hole in the lock. If this exemption can be exploited by an attacker who controls transaction ordering within the same block, the lock is weakened.
- Gap day backfill uses keccak256(vrfWord, gapDay) for entropy. If an attacker can influence which days become "gap days" (by timing VRF stalls or strategic subscription management), they may gain information about backfill entropy before it is used.
- The prevrandao fallback at game-over gives block proposers 1-bit bias on binary outcomes. A warden may argue this extends to multi-bit bias when the proposer controls transaction ordering within their block.

**Prevention:**
1. Have the VRF warden trace BACKWARD from every RNG consumer, not forward from VRF fulfillment. The question is: "At the moment this random word is used to determine an outcome, could any input to the outcome calculation have been influenced after the VRF request?"
2. Enumerate every state-changing function callable during the rngLocked window. For each, verify it cannot influence any RNG-dependent calculation.
3. Test the phaseTransitionActive exemption with adversarial transaction ordering: can a player submit transactions that are processed WITHIN the advanceGame call via callbacks during ETH transfers?
4. Verify VRF retry (12h timeout) cannot be weaponized to select a favorable random word by strategically triggering retries.

**Detection:** Any function that (a) can be called while rngLocked is true AND (b) writes to storage that is read by any RNG-dependent calculation is a potential finding.

---

### Pitfall 6: stETH Integration Accounting Gaps (RANK: 6)

**What goes wrong:** The protocol uses stETH for yield via DegenerusVault. stETH is a rebasing token where transfers lose 1-2 wei due to shares-to-balance integer division. The KNOWN-ISSUES.md documents this, but documentation alone does not prevent a finding. If a warden can demonstrate that accumulated stETH rounding losses exceed the documented bounds or create an exploitable accounting discrepancy under specific conditions, it is payable regardless of documentation.

**Why it happens:** The 1-2 wei loss per transfer is well-documented by Lido. But the actual loss depends on the stETH/share exchange rate, which increases over time. As the rate grows, the rounding error per operation can exceed 2 wei. The Renzo C4A audit (2024) produced a valid finding about exactly this: "after rebasing happens and increases the balance, instead of receiving equal amounts, users will get 20 stETH and 4 stETH will be left inside the protocol."

**Specific risk for this protocol:**
- The DegenerusVault handles stETH. If the vault's accounting uses `balanceOf` (which reflects rebased amounts) but internal tracking uses pre-rebase values, a discrepancy accumulates.
- Payout functions that fall back to stETH when ETH transfer fails may transfer slightly less than the recorded payout amount, creating a deficit in the claiming system.
- The solvency invariant (`balance >= claimablePool`) may technically hold for ETH but not for stETH if the stETH balance drifts below the claimed amount due to accumulated rounding.

**Prevention:**
1. Verify the vault's stETH accounting uses shares (not balance) for all internal tracking. If it uses balance, verify the rounding loss is absorbed correctly.
2. Test stETH payouts at extreme stETH/share rates (2x, 5x, 10x current) and verify the rounding loss stays within documented bounds.
3. Verify that the solvency invariant accounts for cumulative stETH rounding loss, not just per-operation loss.
4. Quantify the worst-case cumulative stETH rounding loss over a maximum game duration and add this number to KNOWN-ISSUES.md.

**Detection:** Compare total stETH distributed to players against total stETH received by the vault. The delta should be non-negative (vault retains dust) and bounded.

---

### Pitfall 7: Known Issues Documentation Gaps (RANK: 7)

**What goes wrong:** The KNOWN-ISSUES.md is comprehensive (34+ entries), but C4A wardens are financially incentivized to find gaps in the documentation. If a known issue is documented but the documentation is imprecise, ambiguous, or does not cover a specific edge case, a warden can submit a finding that technically falls outside the documented known issue. Judges will rule it valid if the documentation does not clearly cover the specific attack vector.

**Why it happens:** Internal teams document the CATEGORY of the issue but not every specific manifestation. "Admin functions gated by onlyOwner" is documented, but a specific sequence where an admin action combined with a timing window creates an undocumented exploit would be payable as a distinct finding.

**Specific risk for this protocol:**
- "All rounding favors solvency" is documented, but does not specify the exact worst-case cumulative rounding loss. A warden who calculates the theoretical maximum loss over a game's lifetime and shows it exceeds "negligible" may argue this is a distinct finding from the generic documentation.
- "Non-VRF entropy for affiliate winner roll" is documented as "deterministic seed (gas optimization)." A warden who demonstrates a specific MEV extraction technique using this deterministic seed may argue the documentation does not cover their specific attack vector.
- "Gameover prevrandao fallback" documents 1-bit bias. If a warden shows a multi-bit bias scenario (e.g., proposer controls both prevrandao AND transaction ordering within their block), they may argue the documentation understates the risk.
- "BURNIE game contract bypasses transferFrom allowance" is documented, but a composability scenario (BURNIE in a lending protocol or aggregator) may produce a distinct finding.

**Prevention:**
1. Review EVERY known issue entry. For each, ask: "What specific attack could a warden construct that is related to but not exactly equal to this documented issue?"
2. Add explicit bounds to fuzzy claims. Replace "rounding favors solvency" with "rounding favors solvency; worst-case cumulative loss over maximum game duration is X wei."
3. Add explicit attack vector descriptions with maximum extractable value, not just category descriptions.
4. For each ERC-20 deviation, add composability warnings: "BURNIE should NOT be used in protocol X because behavior Y will cause Z."

**Detection:** Have a fresh-eyes reviewer read EACH known issue entry and attempt to construct a related but technically distinct attack. If they succeed, the documentation has a gap.

---

### Pitfall 8: Overconfidence in Invariant Test Coverage (RANK: 8)

**What goes wrong:** The protocol has Foundry invariant tests (7 core invariants, 22+ fuzz tests, 4 Halmos proofs). The internal team's confidence is calibrated to these test results. But invariant tests only verify the invariants they are written to check, and fuzzing only explores state sequences the fuzzer discovers. A warden who identifies an invariant that SHOULD hold but IS NOT tested can submit a finding if they can break that untested invariant.

**Why it happens:** Bunni lost $2.4-8.3M to rounding bugs that only manifested across deposit/withdrawal SEQUENCES, not individual operations. "Most test suites model single operations, not operation sequences. Fuzzers that don't model stateful sequences miss these issues."

**Specific risk for this protocol:**
- The solvency invariant is tested: `balance >= claimablePool`. But is the invariant `sum(all individual player claims) == claimablePool` also tested? If individual claim amounts are calculated independently and do not sum correctly, the solvency invariant holds but individual players get incorrect amounts.
- The ticket supply invariant is tested, but is the invariant "no ticket can win two jackpots" tested? The multi-key-space design (write key, read key, far-future key with bit 22) creates complexity that could allow a ticket to be sampled from two different key spaces.
- The RNG roll bounds are tested ([25, 175]), but is the invariant "each player's RNG outcome is independent of other players' outcomes" tested?
- Are the invariants tested under adversarial operation SEQUENCES (buy-claim-buy-claim-burn-claim repeated) or only under individual operations?

**Prevention:**
1. List every invariant that SHOULD hold (not just the ones currently tested). Compare against the test suite. Any gap is a candidate for a warden finding.
2. Add stateful sequence invariant tests that perform random sequences of user operations (buy, claim, burn, open lootbox, advance) and verify invariants after each operation.
3. Specifically test the "no double-counting" invariant: can the same ETH appear in two different pools or be claimed by two different paths?

**Detection:** If a warden can state an invariant that sounds obviously correct ("total prizes paid cannot exceed total ETH deposited") and demonstrate it is not explicitly tested, the team needs to either prove it analytically or add the test.

---

## Moderate Pitfalls

### Pitfall 9: Gas Griefing via Attacker-Forceable State Growth (RANK: 9)

**What goes wrong:** advanceGame gas ceiling is profiled as SAFE (34.9-42.3% headroom). But gas profiling uses the current state. An attacker who grows specific storage structures (by purchasing maximum tickets in maximum key spaces, opening maximum lootboxes, or accumulating maximum pending coinflips) before triggering advanceGame may push the gas ceiling beyond profiled bounds.

**Prevention:** Fuzz test advanceGame with adversarially grown state: maximum tickets per level, maximum concurrent lootbox requests, maximum pending coinflips, maximum active deity boons. Profile gas at these state-growth extremes, not just typical state. Verify the headroom still holds when ALL growth vectors are maximized simultaneously.

**Detection:** If advanceGame gas exceeds 80% of block gas limit under any achievable state, the headroom claim is incorrect.

---

### Pitfall 10: Front-Running and MEV Extraction on Permissionless Functions (RANK: 10)

**What goes wrong:** The 87 permissionless paths were verified for commitment window safety, but MEV extraction (sandwich attacks on purchase functions, front-running jackpot claims) is a distinct attack class from RNG manipulation. A warden may demonstrate that a mempool observer can extract value without manipulating randomness.

**Prevention:** For each permissionless function that involves ETH value, determine if a mempool observer can extract value by front-running, back-running, or sandwiching the call. Document which functions are MEV-sensitive and whether the protocol design accepts this risk. Add MEV-sensitive functions to KNOWN-ISSUES.md if applicable.

---

### Pitfall 11: Integer Overflow in Unchecked Blocks (RANK: 11)

**What goes wrong:** The protocol uses unchecked blocks strategically (1,054 instances flagged by Slither). Solidity 0.8.34's built-in overflow protection is disabled in these blocks. If ANY unchecked arithmetic can overflow under achievable on-chain conditions, it is a High finding regardless of how unlikely the condition seems.

**Prevention:** For each unchecked block, verify the mathematical proof that overflow is impossible -- not "unlikely," but impossible. If the proof depends on an assumption about input ranges, verify that assumption is enforced by a require/revert, not just a convention or NatSpec comment. A warden will look for the weakest link in the assumption chain.

---

### Pitfall 12: ERC-20 Deviation Composability Disputes (RANK: 12)

**What goes wrong:** The 4 documented ERC-20 deviations are documented as design decisions. But C4A judges may disagree on severity classification if a warden demonstrates composability impact. BURNIE auto-claiming coinflip winnings during a standard transfer() call means any contract that holds BURNIE may have its balance unexpectedly change during an outbound transfer. If a yield aggregator, multisig, or lending protocol holds BURNIE, this side effect could cause accounting errors in that protocol.

**Prevention:** For each ERC-20 deviation, explicitly document the composability impact and add warnings to KNOWN-ISSUES.md: "BURNIE is not designed for integration with external DeFi protocols. The auto-claim behavior makes it incompatible with protocols that assume transfer() only decreases sender balance and increases recipient balance by the same amount."

---

### Pitfall 13: Uncovered Contract Files (RANK: 13)

**What goes wrong:** The documentation and audit corpus collectively tell wardens exactly where the team spent the most effort. Paradoxically, this creates a roadmap: areas NOT mentioned in any audit document are areas the team may not have examined carefully. Wardens will look for contracts that appear in no audit finding, no verification document, and no invariant test.

**Prevention:** Review the audit corpus from a warden's perspective. Which contract files are NOT referenced in any audit finding or verification? Common candidates: utility libraries (BitPackingLib, PriceLookupLib, DegenerusTraitUtils), the SVG data contract (Icons32Data), and wrapper tokens (WrappedWrappedXRP). Verify each has been examined. Even if they contain no vulnerabilities, their absence from audit documentation makes them targets.

---

## Minor Pitfalls

### Pitfall 14: Bot Race Findings Escalation (RANK: 14)

**What goes wrong:** Bot race findings (Slither + 4naly3er) are documented as triaged. But wardens may submit the same findings with a more detailed impact analysis and argue for higher severity than the triage assigned. A finding labeled "informational" during triage that a warden demonstrates has Medium impact is payable.

**Prevention:** Ensure KNOWN-ISSUES.md covers not just the category but the maximum achievable impact for each bot finding. If a bot finding can be escalated with sufficient impact analysis, pre-empt the escalation by documenting the maximum impact yourself.

### Pitfall 15: Test Coverage False Confidence (RANK: 15)

**What goes wrong:** 1,351 Hardhat tests + Foundry tests create an impression of complete coverage. But line coverage and branch coverage are different. A function with 100% line coverage but 0% branch coverage on error paths has untested revert behavior.

**Prevention:** Run `forge coverage --report lcov` and identify any function with < 100% branch coverage that handles ETH or tokens. These are the functions wardens will target for unexpected behavior on error paths.

---

## Phase-Specific Warnings for Contest Dry Run

| Warden Specialty | Likely Pitfall | Mitigation |
|------------------|---------------|------------|
| RNG/VRF Specialist | Pitfall 5 (VRF timing assumptions) + Pitfall 1 (monoculture) | Backward-trace methodology from consumers to commitments. Question every "SAFE" conclusion from prior proofs. |
| Gas Specialist | Pitfall 9 (attacker-forceable state growth) + Pitfall 11 (unchecked overflow) | Adversarial state growth before gas measurement. Verify every unchecked block proof. |
| Money/Accounting | Pitfall 3 (rounding accumulation) + Pitfall 6 (stETH) | End-to-end ETH conservation tests with adversarial amounts. stETH at extreme share rates. |
| Admin/Privilege | Pitfall 7 (documentation gaps) + Pitfall 12 (ERC-20 deviation disputes) | Admin action + timing window combinations. Composability impact analysis for each deviation. |
| Cross-Contract | Pitfall 2 (module transition seams) + Pitfall 4 (game-over boundary) | Full state machine mapping of advanceGame. Game-over transition block testing. |

---

## The Meta-Pitfall: "We Have Already Looked at Everything"

The single most dangerous belief after 25 audit milestones is "we have already looked at everything." This belief is precisely what makes fresh-eyes auditing valuable and precisely what makes it fail when the fresh eyes are contaminated by prior conclusions.

The things wardens find are NOT the things you did not look at. They are:

1. **Things you looked at and misunderstood** -- a fundamental assumption about how a subsystem works that was wrong from milestone 1 and never questioned again because every subsequent milestone built on the same assumption.

2. **Assumptions so obvious you did not question them** -- "of course BPS calculations cannot overflow" or "of course the game-over flag propagates atomically" or "of course stETH rounding is only 1-2 wei." These feel like axioms but may be false under specific conditions.

3. **Interactions between components that each seemed correct individually** -- the BAF cache-overwrite bug was exactly this. Each module was correct. The interaction was not. After fixing it, the team may have developed a false sense that "we caught the interaction bugs." The BAF pattern is one class of interaction bug. There are others.

4. **Economic incentive misalignments invisible to code review** -- Yearn lost $9M because "static analysis tools don't verify economic invariants. Fuzzers test code paths, not economic models." This protocol has economic invariants (EV calculations, house edge, solvency) that were verified analytically but may not hold under adversarial economic conditions not modeled.

**The concrete mitigation:** Every dry-run warden MUST receive ONLY the contract source code, the C4A README, and KNOWN-ISSUES.md. No prior audit findings. No SAFE verdicts. No accumulated context. If a warden reaches the same SAFE conclusion independently, confidence increases. If they reach a different conclusion, that difference is the value of the exercise.

---

## Sources

- [Audited, Tested, and Still Broken: Smart Contract Hacks of 2025](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Real exploit patterns in audited protocols (Yearn $9M, Balancer $70-128M, GMX $42M, Cork $12M, Bunni $2.4-8.3M)
- [The State of Web3 Security in 2025](https://olympix.security/blog/the-state-of-web3-security-in-2025-why-most-exploits-come-from-audited-contracts) -- Most exploits come from audited contracts
- [Chainlink VRF $300K Vulnerability](https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/) -- VRF subscription owner manipulation
- [Code4rena Submission Guidelines](https://docs.code4rena.com/competitions/submission-guidelines) -- Contest judging mechanics
- [Code4rena Renzo stETH Finding](https://github.com/code-423n4/2024-04-renzo-findings/issues/289) -- stETH rebasing vulnerability in competitive audit
- [Lido stETH Integration Guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) -- 1-2 wei rounding documentation, shares-based accounting
- [Sherlock: Understanding Insecure Randomness](https://sherlock.xyz/post/understanding-the-insecure-randomness-vulnerability) -- VRF security patterns
- [Chainlink VRF Security Considerations](https://docs.chain.link/vrf/v1/security) -- Official VRF security guidance, re-request risks
- [Psychology of Internal Audit: Navigating Bias](https://www.wolterskluwer.com/en/expert-insights/psychology-internal-audit-navigating-bias-behavior-decision-making) -- Cognitive bias in audit practice
- [Building a Better Auditor: Beating Behavioral Biases](https://internalauditor.theiia.org/en/voices/2024/august/building-a-better-auditor-beating-behavioral-biases/) -- Confirmation bias and overconfidence in repeated audits
- [Delegatecall Vulnerabilities in Solidity](https://www.halborn.com/blog/post/delegatecall-vulnerabilities-in-solidity) -- Storage collision patterns
- [2026 Software Security Report](https://www.prweb.com/releases/2026-software-security-report-audited-applications-account-for-only-10-8-of-exploit-losses---but-the-failures-reveal-a-systemic-blind-spot-302699518.html) -- Audited applications account for only 10.8% of exploit losses
- [Code4rena Awarding](https://docs.code4rena.com/awarding) -- How findings are compensated
- [Code4rena Competitions](https://docs.code4rena.com/competitions) -- Contest structure and sponsor guidance

---
*Pitfalls research for: Degenerus Protocol v9.0 -- C4A Contest Dry Run*
*Researched: 2026-03-28*
