# Requirements: Degenerus Protocol Pre-C4A Adversarial Stress Test

**Defined:** 2026-03-05
**Core Value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.

## v4.0 Requirements

Requirements for v4.0 Pre-C4A Adversarial Stress Test. Each maps to roadmap phases.

### Nation-State Attacker

- [x] **NSTATE-01**: Blind adversarial analysis with 10,000 ETH budget, MEV infrastructure (Flashbots, private mempools), and ability to front-run/back-run/sandwich any protocol interaction
- [x] **NSTATE-02**: Validator/proposer ordering attack modeling — can block proposer reorder VRF fulfillment relative to game state for profitable manipulation?
- [x] **NSTATE-03**: Custom malicious contract deployment — attacker deploys contracts to interact with protocol via callbacks, fallbacks, and proxy patterns
- [x] **NSTATE-04**: Combined nation-state attack on Chainlink infrastructure/personnel AND admin key compromise — model the "compromised admin + VRF failure" theft path with realistic attack timeline (3-day stall → coordinator rotation → manipulated randomness), enumerate mitigations
- [x] **NSTATE-05**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Coercion Attacker

- [x] **COERC-01**: Complete admin key compromise damage map — every admin-callable function enumerated with maximum damage if hostile
- [x] **COERC-02**: Temporal classification of admin powers — instant vs time-locked vs constructor-only actions, with coercion risk per category
- [x] **COERC-03**: Fund extraction paths under hostile admin — can compromised admin drain vault, redirect VRF subscriptions, freeze funds permanently?
- [x] **COERC-04**: User recovery path analysis — what can users do if admin goes rogue? What's the worst-case outcome for locked funds?
- [x] **COERC-05**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Evil Genius Hacker

- [x] **EVIL-01**: Cross-function reentrancy analysis via delegatecall modules — independently re-derive all external call sites and reentrant paths without referencing v1-v3 findings
- [x] **EVIL-02**: Storage collision verification — independently derive shared storage layout across all 10 delegatecall modules and verify zero collision
- [x] **EVIL-03**: VRF manipulation via request ID prediction, fulfillment delay exploitation, and block proposer selective inclusion/exclusion
- [x] **EVIL-04**: Compiler-specific exploit analysis for viaIR + optimizer runs=200 on Solidity 0.8.26/0.8.28 — cross-reference against official bugs.json, check for known optimizer bugs
- [x] **EVIL-05**: Delegatecall return value manipulation — can a module return crafted bytes that cause DegenerusGame to misinterpret state?
- [x] **EVIL-06**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Sybil Whale Economist

- [ ] **SYBIL-01**: Pricing curve manipulation — can coordinated buying across unlimited wallets shift ticket pricing curves to extract net value?
- [ ] **SYBIL-02**: BURNIE token economy attacks — coinflip manipulation, mint/burn arbitrage, activity score gaming for disproportionate rewards
- [ ] **SYBIL-03**: Deity pass market cornering — can accumulated deity passes extract disproportionate value? Model T(n) pricing at scale
- [ ] **SYBIL-04**: Whale bundle mechanics exploitation — can whale bundles (2.4-4 ETH) be used to extract value beyond intended game mechanics?
- [ ] **SYBIL-05**: Multi-account coordination profit extraction — N accounts acting in concert to extract value exceeding N independent accounts
- [ ] **SYBIL-06**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Degenerate Fuzzer

- [ ] **FUZZ-01**: New Echidna/Medusa harnesses targeting v3.0 documented coverage gaps — Degenerette fuzzing, vault deposit/withdraw, deep-state level 10+ progression
- [ ] **FUZZ-02**: Multi-level game progression fuzzing — fuzz across level transitions (purchase → VRF → fulfill → advance → next level) with 1000+ runs
- [ ] **FUZZ-03**: Concurrent whale + Sybil pressure under fuzz — whale bundle purchases AND mass Sybil ticket buying simultaneously
- [ ] **FUZZ-04**: Edge-case state transition fuzzing — gameOver trigger, VRF timeout, coordinator rotation, deity pass accumulation at scale
- [ ] **FUZZ-05**: Coverage gap analysis documenting state space reached vs total reachable states
- [ ] **FUZZ-06**: Runnable PoC test for every Medium+ finding discovered by fuzzing

### Formal Methods Analyst

- [ ] **FORMAL-01**: Certora CVL specs for key protocol properties — ETH solvency invariant, token supply conservation, access control completeness
- [ ] **FORMAL-02**: Extended Halmos symbolic verification beyond v3.0's 10 properties — target arithmetic invariants and state transition validity at deeper bounds
- [ ] **FORMAL-03**: Abstract interpretation / taint analysis on ETH flows — track every wei from msg.value entry to .call{value:} exit across all 22 contracts
- [ ] **FORMAL-04**: Reachability analysis for dangerous states — can gameOver be triggered prematurely? Can claimablePool exceed ETH balance under any execution path?
- [ ] **FORMAL-05**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Dependency & Integration Attacker

- [x] **DEP-01**: VRF coordinator failure mode analysis — Chainlink VRF down, delayed, returns manipulated randomness, subscription exhausted, coordinator self-destructs
- [x] **DEP-02**: stETH depeg scenario modeling — compute exact solvency impact at 10%, 50%, 90% stETH depeg with concrete ETH numbers
- [x] **DEP-03**: LINK token depletion and onTokenTransfer abuse — VRF subscription runs dry, malicious data in ERC-677 callback
- [x] **DEP-04**: Dependency upgrade/deprecation risk — Chainlink VRF V2.5 deprecated, Lido stETH changes rebasing behavior, LINK token upgraded
- [x] **DEP-05**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Gas Griefing Specialist

- [x] **GAS-01**: Every function analyzed for attacker-controllable gas consumption — can any single transaction be forced above 10M gas under any circumstances? (tx limit 16.7M)
- [x] **GAS-02**: advanceGame and VRF callback gas recalculation against current Ethereum parameters (v2.0 used 16M block limit; needs update)
- [x] **GAS-03**: Storage slot bombing analysis — can attacker force expensive SSTORE operations by creating many entries in mappings/arrays (bucket cursor, ticket queue, player registry)?
- [x] **GAS-04**: OOG in callback/fallback patterns — can attacker cause out-of-gas in VRF callback or ETH receive callback that bricks game state?
- [x] **GAS-05**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### White Hat Completionist

- [ ] **WHTHAT-01**: OWASP Smart Contract Top 10 (2026) systematic checklist — SC-01 through SC-10, each verified against every contract with pass/fail/N-A
- [ ] **WHTHAT-02**: SWC Registry sweep for gaps not covered by OWASP — 37 weakness classifications checked against codebase
- [ ] **WHTHAT-03**: ERC20 (BurnieCoin) and ERC721 (DegenerusDeityPass, DegenerusNFT) full standards compliance including edge cases (zero transfer, self-transfer, max approval)
- [ ] **WHTHAT-04**: Fresh-eyes top-to-bottom code review of all 22 contracts + 10 modules — document anything that looks wrong without prior audit context
- [ ] **WHTHAT-05**: Event emission correctness — every state change has corresponding event, events match actual state changes
- [ ] **WHTHAT-06**: Runnable Hardhat/Foundry PoC test for every Medium+ finding

### Game Theory Attacker

- [ ] **GTHRY-01**: Adversarial attack on the resilience thesis (theory/index.html) — identify every claim that is wrong, understated, or unfalsifiable, with code evidence
- [ ] **GTHRY-02**: GAMEOVER path enumeration — every contract-level AND game-theoretic path that leads to game death, with probability estimates and capital requirements
- [ ] **GTHRY-03**: Cross-subsidy structure attack — find scenarios where the cross-subsidy breaks down and one player type can extract value at others' expense
- [ ] **GTHRY-04**: Death spiral scenario construction — construct the most realistic scenario where rational actors let the game die despite the paper's claims
- [ ] **GTHRY-05**: Commitment device failure analysis — under what conditions do quest streaks, future tickets, and auto-rebuy fail as retention mechanisms?
- [ ] **GTHRY-06**: Verify every formal proposition and theorem in the paper against actual contract code — Proposition 4.1 (Solvency), Corollary 4.4 (Positive-Sum), Observation 5.1 (Dominant Strategy), Design Property 8.4 (Game Death conditions)
- [ ] **GTHRY-07**: Runnable Hardhat/Foundry PoC test for every Medium+ finding (contract-level bugs discovered during theory verification)

### Synthesis & Contradiction Report

- [ ] **SYNTH-01**: Cross-reference all 10 agent reports — detect contradictions where Agent A says "X is safe" and Agent B says "X is exploitable"
- [ ] **SYNTH-02**: Coverage matrix mapping every contract function to which agents analyzed it — identify uncovered functions
- [ ] **SYNTH-03**: Deduplicated, severity-rated findings in C4A format with all PoC tests consolidated
- [ ] **SYNTH-04**: Honest confidence assessment — same-auditor bias limitations, coverage gaps, residual risk
- [ ] **SYNTH-05**: Final C4A-ready report with all 10 agent attestations (finding or no-finding with reasoning)

## Future Requirements

### Extended Capabilities

- **ECAP-01**: Multi-block MEV simulation with flashbots-style attack sequences
- **ECAP-02**: Echidna/Medusa parallel fuzzing campaign for cross-validation with Foundry
- **ECAP-03**: Automated mutation testing of security-critical functions
- **ECAP-04**: Formal game-theoretic simulation with Monte Carlo (beyond analytical reasoning)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Not security-relevant; separate concern |
| Frontend/off-chain code | Contracts only |
| Testnet-specific contracts | Mainnet deployment is the target |
| Deployment script auditing | Operational, not protocol attack surface |
| Code fixes during analysis | v4.0 is FIND-only; fixes would break blind methodology |
| Re-running Slither/Aderyn blanket scans | Already done exhaustively in v1.0; contracts unchanged |
| Automated AI vulnerability scanning output | C4A penalizes tool dumps; manual reasoned analysis required |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| NSTATE-01 | Phase 19 | Complete |
| NSTATE-02 | Phase 19 | Complete |
| NSTATE-03 | Phase 19 | Complete |
| NSTATE-04 | Phase 19 | Complete |
| NSTATE-05 | Phase 19 | Complete |
| COERC-01 | Phase 20 | Complete |
| COERC-02 | Phase 20 | Complete |
| COERC-03 | Phase 20 | Complete |
| COERC-04 | Phase 20 | Complete |
| COERC-05 | Phase 20 | Complete |
| EVIL-01 | Phase 21 | Complete |
| EVIL-02 | Phase 21 | Complete |
| EVIL-03 | Phase 21 | Complete |
| EVIL-04 | Phase 21 | Complete |
| EVIL-05 | Phase 21 | Complete |
| EVIL-06 | Phase 21 | Complete |
| SYBIL-01 | Phase 22 | Pending |
| SYBIL-02 | Phase 22 | Pending |
| SYBIL-03 | Phase 22 | Pending |
| SYBIL-04 | Phase 22 | Pending |
| SYBIL-05 | Phase 22 | Pending |
| SYBIL-06 | Phase 22 | Pending |
| FUZZ-01 | Phase 23 | Pending |
| FUZZ-02 | Phase 23 | Pending |
| FUZZ-03 | Phase 23 | Pending |
| FUZZ-04 | Phase 23 | Pending |
| FUZZ-05 | Phase 23 | Pending |
| FUZZ-06 | Phase 23 | Pending |
| FORMAL-01 | Phase 24 | Pending |
| FORMAL-02 | Phase 24 | Pending |
| FORMAL-03 | Phase 24 | Pending |
| FORMAL-04 | Phase 24 | Pending |
| FORMAL-05 | Phase 24 | Pending |
| DEP-01 | Phase 25 | Complete |
| DEP-02 | Phase 25 | Complete |
| DEP-03 | Phase 25 | Complete |
| DEP-04 | Phase 25 | Complete |
| DEP-05 | Phase 25 | Complete |
| GAS-01 | Phase 26 | Complete |
| GAS-02 | Phase 26 | Complete |
| GAS-03 | Phase 26 | Complete |
| GAS-04 | Phase 26 | Complete |
| GAS-05 | Phase 26 | Complete |
| WHTHAT-01 | Phase 27 | Pending |
| WHTHAT-02 | Phase 27 | Pending |
| WHTHAT-03 | Phase 27 | Pending |
| WHTHAT-04 | Phase 27 | Pending |
| WHTHAT-05 | Phase 27 | Pending |
| WHTHAT-06 | Phase 27 | Pending |
| GTHRY-01 | Phase 28 | Pending |
| GTHRY-02 | Phase 28 | Pending |
| GTHRY-03 | Phase 28 | Pending |
| GTHRY-04 | Phase 28 | Pending |
| GTHRY-05 | Phase 28 | Pending |
| GTHRY-06 | Phase 28 | Pending |
| GTHRY-07 | Phase 28 | Pending |
| SYNTH-01 | Phase 29 | Pending |
| SYNTH-02 | Phase 29 | Pending |
| SYNTH-03 | Phase 29 | Pending |
| SYNTH-04 | Phase 29 | Pending |
| SYNTH-05 | Phase 29 | Pending |

**Coverage:**
- v4.0 requirements: 55 total
- Mapped to phases: 55/55
- Unmapped: 0

---
*Requirements defined: 2026-03-05*
*Last updated: 2026-03-05 after roadmap creation*
