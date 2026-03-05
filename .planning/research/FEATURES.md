# Feature Landscape

**Domain:** Novel Zero-Day Attack Surface Audit (v5.0) -- Composition, Precision, Temporal, EVM, and Economic Vulnerability Hunting
**Researched:** 2026-03-05
**Overall confidence:** MEDIUM (techniques based on real C4A warden patterns, post-audit exploit data, and OWASP SC 2026; specific yield for this protocol uncertain given v1-v4 clean results)

## Table Stakes

Features the zero-day hunt MUST include. Missing = the audit has gaps that a skilled C4A warden could exploit for a paid finding.

### Cross-Contract State Composition Analysis

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| Delegatecall shared storage re-derivation | v1.0 verified zero slot collisions, but composition bugs hide in SEQUENCES of storage mutations across modules, not static layout | High | v1.0 Phase 1 storage layout verification -- this goes deeper into dynamic interaction patterns |
| Cross-module state corruption via ordering | Module A writes slot X, Module B reads slot X -- what if A+B ordering assumptions break under edge conditions (level transitions, gameOver mid-step)? | High | v1.0 confirmed 30 delegatecall sites use uniform pattern; this questions the ASSUMPTIONS behind those patterns |
| Multi-module transaction atomicity | A single user tx can trigger delegatecall to Module A which modifies state, then reverts partially -- does the Game contract handle partial-revert states correctly? | Med | v2.0 Phase 12 CEI analysis covers reentrancy but not partial-completion composition |
| View function state dependency analysis | View functions that read from storage modified by delegatecall modules may return stale or inconsistent data if called mid-transaction by another contract | Med | Not previously analyzed; view functions were treated as read-only safe |
| Storage slot overlap in BitPackingLib | BitPackingLib packs multiple values into single uint256 slots; verify that adjacent packed fields cannot corrupt each other through overflow/underflow in unchecked blocks | Med | v1.0 verified BitPackingLib math; v2.0 verified unchecked blocks -- this checks their INTERSECTION |

### Precision and Rounding Exploitation

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| Division-before-multiplication chain analysis | Map every division operation and check if any feeds into a subsequent multiplication before the result is used -- the classic "precision loss amplification" pattern | High | v1.0 verified PriceLookupLib and token math; this is a SYSTEMATIC sweep across ALL contracts |
| Zero-rounding free action detection | When amount * rate / divisor rounds to zero, the caller pays nothing but may still receive state changes (points, tickets, streak credit) -- find all such paths | High | Not previously analyzed as a class; individual formulas verified but not the "what rounds to zero" question |
| Dust accumulation in prize pool splits | 90/10 prize split truncation over thousands of transactions -- does dust accumulate in an unclaimable state? Can it be drained? | Med | v2.0 ACCT-01 through ACCT-10 proved ETH solvency but did not model dust accumulation over many rounds |
| Lootbox EV multiplier precision | Lootbox EV is calculated from activity score; verify the multiplication chain preserves enough precision that edge-case activity scores don't create EV > 1.0 (profitable farming) | Med | v2.0 Phase 11 confirmed no EV > 1.0; this rechecks with adversarial precision analysis |
| Coinflip range boundary precision | BurnieCoinflip uses VRF entropy for range calculations; verify no off-by-one or rounding in range boundaries that shifts house edge | Med | v1.0 verified coinflip range; this specifically targets the boundary precision question |
| Deity pass T(n) pricing precision | T(n) = n*(n+1)/2 in ETH with 18 decimals; verify no precision loss at high n values that creates underpricing | Low | v1.0 verified formula; T(n) is simple enough that precision issues are unlikely but must be checked |

### Temporal Edge Case Detection

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| Timestamp boundary condition analysis | 912-day, 365-day, 18-hour, 3-day, 30-day timeouts -- what happens at EXACTLY the boundary? Off-by-one in >= vs > comparisons? | Med | v2.0 confirmed timestamp +/-900s tolerance is safe; this checks the comparison OPERATORS at exact boundaries |
| Multi-step gameOver race condition | gameOver is multi-step (advanceGame -> VRF request -> fulfill -> advanceGame -> gameOver=true); what if a user calls purchase() between steps? | High | v1.0/v2.0 documented multi-step gameOver; not adversarially tested for interleaving attacks |
| VRF callback timing exploitation | VRF fulfillment arrives in a future block; state changes between request and fulfillment may create exploitable windows | High | v1.0 confirmed rngLockedFlag prevents actions during VRF wait; this checks for ANY state mutation paths that bypass the lock |
| Level transition boundary states | At exact level boundary (level N -> N+1), pricing, ticket counts, prize pools all change -- can a transaction straddle the boundary to get old prices with new rewards? | Med | v1.0 covered level transitions; this specifically targets the ATOMIC transition question |
| Block timestamp manipulation at game milestones | Validators can manipulate block.timestamp by +/-15 seconds; does this create exploitable conditions at any of the 5 timeout boundaries? | Med | v2.0 analyzed +/-900s tolerance (generous); this narrows to the actual +/-15s validator capability at specific milestones |
| Pre-first-purchase edge state | Protocol state before any ticket is purchased -- are all view functions, price lookups, and module calls safe with zero-state storage? | Low | Partially covered by v1.0 module audits; needs systematic zero-state verification |

### EVM-Level Attack Vectors

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| Forced ETH via selfdestruct/coinbase | Post-Cancun, selfdestruct only sends ETH (no code deletion) unless same-tx creation; verify protocol does NOT rely on address(this).balance for logic decisions | Med | v1.0 confirmed pull-pattern withdrawals; this checks if ANY code path uses address(this).balance instead of internal accounting |
| Function selector collision check | All 22 contracts + 10 modules -- verify no accidental 4-byte selector collision that could route calls to wrong functions | Med | Never systematically checked; compiler prevents collisions WITHIN a contract but not across delegatecall targets |
| ABI encoding edge cases | Non-standard but valid ABI encoding (offset manipulation) in external calls -- does any calldata validation assume standard encoding positions? | Med | Not previously analyzed; relevant for any contract accepting arbitrary calldata |
| Assembly SSTORE/SLOAD safety re-audit | JackpotModule and MintModule use inline assembly for storage; re-verify slot calculations are correct and cannot be manipulated via crafted inputs | Med | v2.0 Phase 12 verified assembly slot calculations; this is the "what if auditors were wrong" re-examination |
| CREATE2/address prediction attacks | ContractAddresses uses compile-time constants predicted from nonces; can an attacker deploy a contract at a predicted address before the protocol? | Med | Deploy pipeline uses nonce-based prediction; if deployer nonce changes between prediction and deployment, addresses shift |
| Packed storage field boundary corruption | BitPackingLib stores multiple values in single slots; verify mask/shift operations cannot bleed bits across field boundaries under edge-case values (max uint, zero, overflow-adjacent) | Med | v1.0 verified BitPackingLib; this specifically tests boundary values at bit field edges |

### Cross-System Economic Composition

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| Circular affiliate reward farming | Can player A refer player B who refers player A, creating a closed loop that extracts affiliate bonuses from both sides? | Med | v1.0 covered affiliate system; this tests the specific CIRCULAR reference case |
| Vault share inflation/donation attack | DegenerusVault holds stETH; can an attacker donate stETH directly to inflate share price, then redeem at inflated value? (Classic ERC4626 first-depositor attack) | High | v2.0 confirmed no donation attack; "what if auditors were wrong" re-examination specifically for this high-value vector |
| Price curve manipulation via purchase timing | Ticket prices escalate per level; can an attacker time purchases to exploit the transition from one price tier to the next? | Med | v1.0 Phase 5 covered pricing; this focuses on the tier-transition atomic moment |
| Whale bundle + lootbox interaction | Whale bundles (2.4-24 ETH) grant tickets AND lootbox access; does the lootbox EV calculation account for whale-sourced tickets differently than normal purchases? | Med | v1.0 covered whale and lootbox separately; this tests their COMPOSITION |
| BurnieCoin supply manipulation via coinflip | Coinflip burns/mints BURNIE; can a sequence of strategic coinflips manipulate the supply to affect other protocol mechanics (if any depend on BURNIE supply)? | Med | v2.0 Phase 11 token security confirmed; this checks if BURNIE supply is a state variable that other contracts read |
| Quest streak + activity score farming | Quest streak system awards activity score which affects lootbox EV; can a player farm minimal-cost actions to inflate activity score beyond intended bounds? | Med | v1.0 covered quest system; this tests the economic efficiency of minimal-cost farming |
| stETH rebasing during multi-step operations | stETH balance changes between blocks due to rebasing; if a multi-step operation spans blocks, can the rebasing create an exploitable discrepancy? | Med | v1.0 confirmed no cached stETH balance; this checks multi-block operations specifically |

### "What If Auditors Were Wrong" Re-Examination

| Feature | Why Expected | Complexity | Dependencies on v1-v4 |
|---------|-------------|------------|----------------------|
| ETH solvency invariant re-derivation | v2.0 proved ACCT-01 through ACCT-10; independently re-derive the invariant and check if any new code paths (post-v2.0 fixes) violate it | High | v2.0 ACCT invariants are the foundation; this is an independent verification |
| CEI pattern re-verification | v2.0 confirmed 8 ETH-transfer sites are CEI-safe; re-verify each site independently, checking for cross-function reentrancy paths the matrix may have missed | Med | v2.0 Phase 12 CEI matrix; v3.0 ADVR-04 reentrancy session |
| VRF entropy derivation independence | v1.0 confirmed VRF entropy is used correctly; re-verify that no code path allows entropy reuse, predictability, or selective application | Med | v1.0 Phase 2 VRF lifecycle; this questions the completeness of that analysis |
| Access control privilege escalation paths | v1.0 Phase 6 mapped all access control; re-check for privilege escalation through INDIRECT paths (contract A calls contract B which calls contract C with elevated permissions) | Med | v1.0 access control matrix; this checks TRANSITIVE privilege, not direct |
| Unchecked block safety re-verification | v2.0 verified 40 unchecked blocks in JackpotModule; extend to ALL unchecked blocks across ALL contracts | Med | v2.0 Phase 12 covered JackpotModule specifically; other contracts may have unchecked blocks too |

## Differentiators

Features that go beyond standard audit re-examination. These are what separate "we double-checked" from "we found what 10 prior agents missed."

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Foundry fuzz campaigns (10K+ runs)** targeting composition | Standard fuzzing tests individual functions; composition fuzzing tests SEQUENCES of cross-module calls with varying parameters | High | v3.0 had 48 invariant tests; v5.0 fuzzes the INTERACTION SPACE between modules |
| **Slither custom detectors for protocol-specific patterns** | Generic Slither detectors miss protocol-specific logic; custom detectors can check Degenerus-specific invariants (e.g., "no module writes to slot X after Y") | High | Slither was used in v1.0 for standard checks; custom detectors are a force multiplier |
| **Halmos symbolic verification of pure math invariants** | Prove mathematically that no input can violate pricing formulas, split ratios, or accounting identities -- covers the ENTIRE input space, not just fuzz samples | High | v3.0 verified 10 Halmos properties; v5.0 targets the precision/rounding domain specifically |
| **Cross-contract state graph construction** | Build a directed graph of all storage writes and reads across all 22 contracts + 10 modules; find paths where Module A's write can corrupt Module B's assumption | High | No prior phase built this artifact; it's the foundation for systematic composition analysis |
| **Formal taint tracking for msg.value flows** | Every wei from msg.value entry through internal accounting to .call{value:} exit -- formal proof that no wei is lost, duplicated, or misdirected | High | v2.0 ACCT analysis was manual; formal taint tracking provides mathematical completeness |
| **Adversarial input crafting for packed storage** | Generate inputs that exercise BitPackingLib at exact bit boundaries (2^8-1, 2^16-1, 2^32-1, etc.) to detect field overflow/corruption | Med | Standard testing uses random or typical values; boundary inputs are where packed storage breaks |
| **Multi-tool convergence** (Foundry + Slither + Halmos) | When all three tools agree a property holds, confidence is HIGH; when they disagree, the disagreement IS the finding | Med | No prior phase used all three tools convergently on the same properties |

## Anti-Features

Features to explicitly NOT build in v5.0.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Re-running the 10-agent blind adversarial analysis** | v4.0 delivered 10 unanimous zero-Medium+ attestations; repeating the same methodology yields same results | Focus on NOVEL attack surfaces and automated tooling that agents could not do |
| **Standard vulnerability checklist sweeps** | OWASP SC Top 10, SWC Registry already swept in v4.0 by White Hat agent; no new categories since | Only revisit if a specific zero-day hunt surface maps to a checklist item |
| **Gas optimization** | Out of scope per PROJECT.md; not security-relevant unless it enables DoS | Note gas-related findings only if they have security implications |
| **Governance/upgrade attack analysis** | Protocol has no governance mechanism and no upgrade pattern; these attack surfaces do not exist | Focus on actual deployed contract capabilities |
| **Flash loan attack modeling** | v1.0 confirmed exact-value validation blocks flash loan amplification; protocol does not interact with DEXes or lending protocols | Only revisit if a new code path is discovered that accepts arbitrary amounts |
| **Frontend/off-chain integration testing** | Contracts-only scope per PROJECT.md | Note off-chain assumptions where relevant but do not audit off-chain code |
| **Generating AI-automated vulnerability reports** | C4A penalizes automated tool output dumps; findings must be manually reasoned and verified | Use tools (Slither, Halmos, Foundry) for DETECTION, write findings with manual analysis |
| **Mock contract auditing** | Test infrastructure only; not deployed to mainnet | Only relevant if mock behavior reveals incorrect mainnet assumptions |
| **Deployment script security** | Operational concern, not attack surface; deploy pipeline is one-time | Note if deployment ordering creates a window of vulnerability but do not audit scripts |
| **Repeating individual module line-by-line review** | v1.0 did 10 module-by-module reviews; v4.0 had 10 agents independently review | Focus on CROSS-module interactions and COMPOSITION, not individual module correctness |

## Feature Dependencies

```
                     AUTOMATED TOOLING
                     =================
Slither static analysis ----+
Foundry fuzz campaigns -----+--> Tool convergence analysis
Halmos symbolic verify -----+         |
                                      v
                     MANUAL ANALYSIS PHASES
                     ======================
Cross-contract state graph ----> Composition vulnerability identification
        |                                    |
        v                                    v
Precision/rounding sweep ----> Zero-rounding free action detection
        |                                    |
        v                                    v
Temporal edge case analysis --> Race condition / boundary verification
        |                                    |
        v                                    v
EVM-level weirdness check ---> selfdestruct/selector/assembly findings
        |                                    |
        v                                    v
Economic composition ---------> Circular rewards / vault / pricing
        |                                    |
        v                                    v
"Auditors were wrong" --------> Re-derive key invariants independently
                                      |
                                      v
                            SYNTHESIS + REPORT
```

### Critical Path
- **Automated tooling can run in parallel** with each other (Slither, Foundry, Halmos are independent)
- **Cross-contract state graph** should be built FIRST -- it informs all other manual analysis phases
- **Precision/rounding sweep** is independent of temporal and EVM analysis
- **Economic composition** depends on understanding the state graph (from step 1)
- **"Auditors were wrong"** can run in parallel with everything else (it re-derives independently)
- **Synthesis** requires all phases complete

### Infrastructure Dependencies (from v1-v4)

- Hardhat test suite (884 tests) -- PoC tests for any findings
- Foundry infrastructure (48 invariant tests) -- extend with composition fuzz harnesses
- Halmos infrastructure (10 symbolic properties) -- extend with precision/rounding properties
- Slither configuration -- v1.0 Slither run exists; needs re-run with custom detectors
- deployFixture.js -- full protocol deployment for testing
- v4.0 synthesis report (29-01) -- baseline of "what was confirmed safe" to challenge

## Complexity Budget

| Analysis Area | Estimated Complexity | Rationale |
|---------------|---------------------|-----------|
| Cross-contract state composition | HIGH | 22 contracts x 10 modules = 220 potential interaction pairs; state graph construction is the bottleneck |
| Precision/rounding exploitation | HIGH | Every arithmetic operation across ~85K lines; systematic sweep is labor-intensive |
| Temporal edge cases | MEDIUM | 5 known timeout boundaries + level transitions + multi-step gameOver; bounded attack surface |
| EVM-level weirdness | MEDIUM | selfdestruct post-Cancun is limited; selector collisions are mechanical to check; assembly sites already partially verified |
| Economic composition | MEDIUM | Bounded by number of economic mechanisms (affiliate, vault, pricing, lootbox, whale, coinflip) |
| "Auditors were wrong" | MEDIUM | Re-derive 5-6 key invariants; bounded scope but requires independent reasoning |
| Foundry fuzzing | HIGH | Writing composition-aware fuzz harnesses that test SEQUENCES is significantly harder than single-function fuzzing |
| Slither custom detectors | MEDIUM | Slither detector API is well-documented; challenge is defining protocol-specific patterns |
| Halmos symbolic verification | HIGH | Halmos has timeouts on complex properties; precision math with 18-decimal fixed-point may be slow to solve |

## MVP Recommendation

### Must Have (minimum viable zero-day hunt):

1. **Cross-contract state composition graph** -- the foundation for finding composition bugs; without this, the hunt is just another line-by-line review
2. **Precision/rounding systematic sweep** -- division-before-multiplication and zero-rounding are the #1 class of bugs that survive multiple audits per industry data
3. **Forced ETH (selfdestruct/coinbase) balance check** -- simple to verify, catastrophic if missed; confirm no address(this).balance reliance
4. **Vault share inflation re-examination** -- highest-value single vector; first-depositor/donation attacks are the most commonly found post-audit bug in vault contracts
5. **Multi-step gameOver interleaving test** -- protocol-specific high-value race condition that prior audits documented but may not have adversarially tested
6. **Foundry fuzz campaigns at 10K+ runs** -- extends v3.0 fuzzing with higher run counts and composition-aware harnesses

### Should Have:

7. **Slither full triage with custom detectors** -- systematic coverage that catches what manual review misses
8. **Halmos symbolic verification of pricing math** -- proves no input can violate pricing invariants across the entire input space
9. **Timestamp boundary off-by-one analysis** -- mechanical but important; >= vs > at exact timeout boundaries
10. **Packed storage boundary value testing** -- BitPackingLib at exact bit boundaries (2^N-1 values)

### Defer (diminishing returns given v1-v4 clean results):

- **Full ABI encoding edge case analysis** -- relevant for protocols accepting arbitrary calldata from untrusted sources; Degenerus has well-typed entry points
- **CREATE2/address prediction attacks** -- deploy pipeline is one-time; attacker would need to front-run the deployer's entire nonce sequence
- **Circular affiliate reward analysis** -- low expected yield; affiliate system was reviewed in v1.0 and v4.0
- **stETH rebasing during multi-step operations** -- v1.0 confirmed no cached balance; multi-block stETH discrepancy is bounded by daily rebasing rate (~0.01%)
- **Formal ETH taint tracking** -- v2.0 manual ACCT analysis was comprehensive; formal treatment adds rigor but v4.0 confirmed with 10 agents

## Sources

- [OWASP Smart Contract Top 10 2026](https://owasp.org/www-project-smart-contract-top-10/) -- SC-01 through SC-10 categories; Access Control ($953.2M), Logic Errors ($63.8M), Reentrancy ($35.7M) leading loss categories
- [Hacken: Top 10 Smart Contract Vulnerabilities 2025](https://hacken.io/discover/smart-contract-vulnerabilities/) -- emerging attack vectors, cross-contract composition risks
- [Guardian Audits: Division Precision Loss](https://lab.guardianaudits.com/encyclopedia-of-common-solidity-bugs/division-precision-loss) -- division-before-multiplication patterns and mitigation
- [ImmuneBytes: Precision Loss Deep Dive](https://immunebytes.com/blog/precision-loss-vulnerability-in-solidity-a-deep-technical-dive/) -- systematic precision loss analysis methodology
- [Dacian: Precision Loss Errors](https://dacian.me/precision-loss-errors) -- categorized precision loss patterns from real C4A findings
- [Verichains: ABI Encoding Exploit](https://blog.verichains.io/p/soliditys-hidden-flexibility-how) -- non-standard ABI encoding attack vectors
- [Smart Contract Security Field Guide: ABI Hash Collisions](https://scsfg.io/hackers/abi-hash-collisions/) -- selector collision attack patterns
- [Olympix: State of Web3 Security 2025](https://olympix.security/blog/the-state-of-web3-security-in-2025-why-most-exploits-come-from-audited-contracts) -- 70% of major exploits from audited contracts; median 47 days post-audit to exploit
- [SmartState: State-Reverting Vulnerabilities](https://arxiv.org/html/2406.15988v1) -- temporal-order state dependency analysis methodology
- [HackMD: Pragmatic Selfdestruct](https://hackmd.io/@vbuterin/selfdestruct) -- post-Cancun EIP-6780 selfdestruct behavior changes
- [Coinlaw: Smart Contract Security Statistics 2025](https://coinlaw.io/smart-contract-security-risks-and-audits-statistics/) -- $263M H1 2025 losses, 59% multi-contract transactions
- [Awesome Audit Checklists](https://github.com/TradMod/awesome-audits-checklists) -- ERC4626 vault checklist (350+ vulnerabilities), ERC20/ERC721 edge cases
- v4.0 29-01 Synthesis Report -- 10/10 agents unanimous zero Medium+; baseline for "what if they were wrong"
- v2.0 ACCT-01 through ACCT-10 -- ETH solvency invariants to re-derive independently
- v2.0 Phase 12 -- CEI matrix, unchecked block verification (JackpotModule 40 blocks)
