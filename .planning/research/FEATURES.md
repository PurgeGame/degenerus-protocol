# Feature Landscape: Invariant Fuzzing & Blind Adversarial Testing

**Domain:** Foundry invariant test harnesses, handler design, and blind adversarial attack sessions for a 22-contract DeFi/game protocol with delegatecall modules
**Researched:** 2026-03-05
**Confidence:** HIGH (Foundry official docs, established community patterns, existing codebase analysis)

---

## Table Stakes

Features that a credible invariant fuzzing + adversarial campaign must include. Missing any of these means the v3.0 milestone fails to add meaningful security assurance beyond v2.0's static analysis.

### Invariant Test Harnesses

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| ETH solvency invariant harness | Core protocol invariant: sum of all claimable balances + prize pools <= contract ETH balance. This is THE invariant for any ETH-holding protocol. | High | Requires ghost variables tracking every ETH inflow (purchases, whale bundles, deity passes) and outflow (claims, jackpots, lootbox payouts, game-over distribution). Must deploy full protocol in Foundry which means solving the ContractAddresses compile-time constant problem. |
| BurnieCoin supply conservation invariant | totalSupply + vaultAllowance must equal sum of all balance changes. Already have standalone math fuzz (BurnieCoinInvariants.t.sol) but need stateful multi-actor version. | Medium | Existing mock-based fuzz tests validate the math. Upgrade to handler-based invariant test with multiple actors doing mint/burn/transfer/vaultMintTo sequences. |
| Game FSM transition invariant | Game state machine must never reach illegal states: level must only increase, gameOver must be terminal, rngLocked must follow request-fulfill-unlock cycle. | High | Requires handler that drives purchase/advanceGame/VRF-fulfill sequences. Must mock VRF coordinator in Foundry (vm.prank the callback). |
| Handler contracts (not raw target fuzzing) | Handler-based setup is the standard for complex protocols. Raw contract fuzzing produces >99% reverts and finds nothing useful. | Medium | One handler per logical domain (MintHandler, AdvanceHandler, WhaleHandler, ClaimHandler). Each handler bounds inputs to valid ranges and manages actor state. |
| Ghost variable tracking | Handler-side accounting that shadows protocol state. Required to assert invariants the protocol doesn't expose as view functions. | Medium | ghost_ethIn, ghost_ethOut, ghost_ticketsMinted, ghost_levelAdvances minimum. Updated in every handler function. |
| Multi-actor support | Fuzzer must call from multiple addresses to test access control and cross-user interactions. | Low | Standard pattern: handler maintains address[] actors, uses modifiers to cycle through them with vm.prank. |
| Bounded input generation | All handler functions must use bound() to constrain fuzzed inputs to valid ranges. | Low | Without bounding, >95% of calls revert on basic validation (zero amount, insufficient ETH). Wasted fuzzer cycles. |

### Blind Adversarial Attack Sessions

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Independent attack briefs (4 sessions) | Each session targets a distinct attack surface with a focused scope document. Independence prevents groupthink and ensures broad coverage. | Low | Brief writing is low complexity; the value is in scoping distinct, non-overlapping attack surfaces. |
| ETH extraction attack session | Primary threat: can an attacker drain ETH beyond their entitlement? Covers reentrancy, rounding exploits, claim-replay, prize pool manipulation. | High | Must exercise all 8 ETH transfer sites identified in v2.0 cross-function reentrancy matrix. |
| advanceGame bricking attack session | Can an attacker permanently brick the game state machine? Covers VRF griefing, gas exhaustion in advanceGame, level-skip attacks. | Medium | v2.0 confirmed 39.3% gas bound, but fuzzer may find sequences that push it higher or stall VRF permanently. |
| Delegatecall reentrancy attack session | Can a malicious callback during delegatecall module execution corrupt shared storage? | Medium | 10 modules share DegenerusGameStorage. v2.0 verified CEI pattern but a fuzzer can test sequences v2.0 couldn't enumerate. |
| PoC test for each Medium+ finding | Any finding rated Medium or above must have a reproducible proof-of-concept. Standard for C4 submissions. | Low-High | Complexity depends on what's found. Writing the PoC is the easy part; finding the bug is the hard part. |
| C4-format findings report | Consolidated report from all attack sessions in Code4rena severity format. | Low | Template exists from v2.0 Phase 13. |

---

## Differentiators

Features that go beyond the minimum and materially increase the chance of finding bugs that a C4 contest would surface.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Vault share accounting invariant | DegenerusVault and DegenerusStonk use share-based math. Invariant: no user can extract more ETH than their proportional share. Existing ShareMathInvariants.t.sol tests the formula; upgrade to stateful multi-deposit-multi-withdraw handler. | Medium | High-value because share math bugs are a top C4 finding category (Yearn yETH exploit Dec 2025). |
| Ticket queue ordering invariant | Ticket purchase queue must maintain FIFO ordering and never skip entries during advanceGame processing. | Medium | Requires handler that interleaves purchases and advances, checking queue consistency after each. |
| Cross-handler sequencing | Multiple handlers calling different protocol entry points in the same invariant campaign. Tests cross-function interaction sequences. | Medium | Foundry supports multiple targetContract entries. Key for finding bugs at module boundaries. |
| Conditional invariants (phase-aware) | Invariants that apply only in certain game states (e.g., "no claims possible before gameOver" or "prize pool only decreases after gameOver"). | Low | Use if/else in invariant_ functions to check game.gameOver() and assert different properties per phase. |
| Attack brief with threat model persona | Each blind adversarial session assumes a specific attacker capability (whale, Sybil, block proposer, insider). More realistic than generic "find bugs." | Low | Aligns with v2.0 threat model: 1000 ETH whale + coordinated Sybil + validator. |
| Differential testing against v2.0 manual proofs | Fuzzer attempts to violate the specific claims made in v2.0 audit (e.g., "ACCT-01: purchase ETH fully accounted"). Turns static proofs into dynamic verification. | Medium | High confidence boost: if the fuzzer can't break v2.0's claims after 256 runs x 64 depth, those claims are battle-tested. |
| Lootbox EV invariant | Expected value of lootbox payouts must never exceed 1.0x deposit over sufficient samples. | Medium | Statistical invariant -- harder to assert per-call. Use ghost variables to track cumulative lootbox deposits vs payouts, assert ratio <= 1.0 + epsilon. |

---

## Anti-Features

Features to explicitly NOT build for this milestone.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full protocol deployment in Foundry | ContractAddresses.sol uses compile-time constants. Deploying the real 22-contract suite in Foundry requires solving the address-patching problem (predict nonces, patch, recompile). This is a massive yak-shave for v3.0. | Use mock contracts that mirror the real contracts' storage layout and key functions, exactly as the existing BurnieCoinInvariants.t.sol already does. Test the MATH and STATE TRANSITIONS, not the deployment pipeline. |
| Migrating 884 Hardhat tests to Foundry | Existing Hardhat tests are comprehensive and passing. Rewriting them in Solidity adds zero security value. | Keep Hardhat tests as-is. Foundry invariant tests are ADDITIVE -- they test properties Hardhat unit tests structurally cannot (random sequences of operations). |
| Gas optimization invariants | v3.0 is about security, not gas. Gas was already analyzed in v2.0 Phase 9. | Out of scope per PROJECT.md. |
| Formal verification | Tools like Certora or Halmos are valuable but represent a different methodology than fuzzing. Would require learning a new specification language and tool. | Fuzzing is the right tool for this milestone. Formal verification could be a v4.0 milestone. |
| Automated vulnerability scanners (Slither/Aderyn re-run) | Already run in v1.0 with all findings triaged. Re-running adds no value unless contracts changed. | Contracts haven't changed since v2.0. Static analysis is complete. |
| Frontend/off-chain attack vectors | Out of scope per PROJECT.md. | Contracts only. |
| Cross-chain bridge testing | Protocol is single-chain (mainnet). No bridge exists. | N/A. |

---

## Feature Dependencies

```
Foundry config (foundry.toml) ── already exists
    |
    v
Mock contracts for Foundry ── mirrors of real contracts with same storage layout
    |
    +---> ETH Solvency Handler ──> ETH Solvency Invariant Test
    |
    +---> BurnieCoin Handler ──> BurnieCoin Supply Invariant Test (upgrade from existing)
    |
    +---> Game FSM Handler ──> Game FSM Invariant Test
    |         |
    |         +---> VRF Mock (Foundry-native) ── must fulfill random words on demand
    |
    +---> Vault/Stonk Share Handler ──> Share Accounting Invariant Test (upgrade from existing)
    |
    +---> Multi-handler campaign ──> Cross-handler invariant test (all handlers as targets)

Attack Brief 1 (ETH extraction) ──> Independent adversarial session ──> PoCs + findings
Attack Brief 2 (advanceGame bricking) ──> Independent adversarial session ──> PoCs + findings
Attack Brief 3 (delegatecall reentrancy) ──> Independent adversarial session ──> PoCs + findings
Attack Brief 4 (claimWinnings overflow) ──> Independent adversarial session ──> PoCs + findings
    |
    v
Consolidated C4-format findings report
```

Key dependency: The mock contract approach (anti-feature: no full deployment) means handlers interact with simplified mocks. This is a deliberate tradeoff -- the existing BurnieCoinInvariants.t.sol and ShareMathInvariants.t.sol already demonstrate this pattern successfully.

---

## Handler Design Patterns for Delegatecall Architecture

The protocol's delegatecall module pattern creates a specific challenge: the Game contract delegates to 10 modules that share DegenerusGameStorage. A handler must:

1. **Wrap the Game contract, not individual modules.** In production, users call Game which delegates. The handler should mirror this by calling Game's external functions.
2. **Manage VRF lifecycle.** Many operations require VRF fulfillment (advanceGame, lootbox, coinflip). The handler must include a `fulfillVRF()` action that the fuzzer can call, simulating Chainlink callback.
3. **Track shared storage via ghost variables.** Since delegatecall modules write to Game's storage, the handler must track expected state changes at the Game level, not per-module.
4. **Bound inputs per function.** Each handler function needs specific bounds:
   - `purchase()`: ticketQuantity in [100, 40000], payKind in [0,2], msg.value matching cost
   - `advanceGame()`: only callable when !rngLocked
   - `claimWinnings()`: only callable when gameOver && hasClaim
   - Whale/deity: msg.value matching required price

---

## Attack Brief Structure

Each blind adversarial session needs a focused brief. Effective brief structure:

### Template
```
ATTACK BRIEF: [Session Name]
TARGET: [Specific contracts/modules in scope]
ATTACKER PERSONA: [Capabilities -- e.g., 1000 ETH whale, block proposer, Sybil group]
ATTACK SURFACE: [Entry points to probe]
INVARIANTS TO BREAK: [Specific properties the attacker tries to violate]
KNOWN DEFENSES: [What v2.0 verified -- attacker must get past these]
OUT OF SCOPE: [What not to waste time on]
SUCCESS CRITERIA: [What constitutes a finding at each severity level]
```

### What Makes a Good Brief
- **Focused scope**: 2-4 contracts, not the whole protocol. Depth over breadth.
- **Clear attacker model**: What resources and capabilities the attacker has.
- **Falsifiable claims**: "v2.0 proved X. Can you disprove it?" gives the adversarial session a concrete target.
- **Independence**: Each session should not see findings from other sessions until consolidation. Prevents anchoring bias.

### Proposed 4 Sessions

| Session | Target Contracts | Attacker Persona | Key Invariant to Break |
|---------|-----------------|-------------------|----------------------|
| ETH Extraction | Game, Jackpots, Vault, Stonk | 1000 ETH whale + reentrancy callback contract | Extract more ETH than deposited + entitled winnings |
| advanceGame Bricking | Game, AdvanceModule, JackpotModule | Block proposer with censorship power | Permanently prevent game from advancing past a level |
| Claim Overflow | Game, GameOverModule, EndgameModule, PayoutUtils | Sybil group (100 addresses) | Claim total > prize pool, or claim someone else's winnings |
| Delegatecall Storage | Game, all 10 modules | Attacker with deep protocol knowledge | Corrupt shared storage via cross-module call sequence |

---

## MVP Recommendation

Prioritize for maximum security value per effort:

1. **ETH solvency invariant harness** -- THE critical invariant. If the fuzzer can't break it after 256 runs x 64 depth, it's a powerful complement to v2.0's manual ACCT proofs.
2. **Game FSM invariant harness** -- Second most critical. State machine bugs are notoriously hard to find with unit tests.
3. **ETH extraction attack brief** -- Highest-severity attack surface. If there's a way to drain ETH, this session finds it.
4. **BurnieCoin supply invariant** (upgrade existing) -- Low marginal effort since BurnieCoinInvariants.t.sol already exists as a foundation.

**Defer:**
- Lootbox EV invariant: Statistical property, harder to assert deterministically, lower severity than solvency.
- Ticket queue ordering: Important but lower priority than solvency and FSM.
- Differential testing against v2.0 proofs: Valuable but can be folded into the main invariant harnesses rather than being a separate feature.

---

## Complexity Budget

For a protocol of this size (22 contracts, 10 modules, ~113K lines), realistic scope:

| Component | Estimated Plans | Rationale |
|-----------|----------------|-----------|
| Mock contracts for Foundry | 1-2 | Mirror key contracts' interfaces and storage; existing pattern in test/fuzz/ |
| ETH solvency handler + invariant | 2-3 | Most complex handler (many entry points for ETH flow) |
| BurnieCoin handler + invariant | 1 | Upgrade existing BurnieCoinInvariants.t.sol to stateful handler |
| Game FSM handler + invariant | 2 | VRF mock + state machine tracking |
| Vault/Stonk share handler + invariant | 1 | Upgrade existing ShareMathInvariants.t.sol |
| Attack briefs (4x) | 1 | Write all 4 briefs in one plan |
| Adversarial sessions (4x) | 4 | One plan per independent session |
| PoC tests for findings | 1-2 | Depends on what's found |
| Consolidated findings report | 1 | Template from v2.0 |
| **Total** | **14-17 plans** | |

---

## Sources

- [Foundry Invariant Testing Official Docs](https://getfoundry.sh/forge/invariant-testing) -- handler pattern, targetContract, ghost variables, configuration
- [RareSkills Invariant Testing Guide](https://rareskills.io/post/invariant-testing-solidity) -- handler examples, actor management, DeFi invariant categories
- [horsefacts WETH Invariant Testing](https://github.com/horsefacts/weth-invariant-testing) -- ETH solvency ghost variable pattern, bounded fuzzing
- [Cyfrin Invariant Testing Guide](https://medium.com/cyfrin/invariant-testing-enter-the-matrix-c71363dea37e) -- multi-handler campaigns
- [Audited, Tested, and Still Broken (2025 Hacks)](https://medium.com/coinmonks/audited-tested-and-still-broken-smart-contract-hacks-of-2025-a76c94e203d1) -- Yearn yETH share math exploit as motivation for vault invariants
- Existing codebase: test/fuzz/BurnieCoinInvariants.t.sol, test/fuzz/ShareMathInvariants.t.sol, test/fuzz/PriceLookupInvariants.t.sol -- established mock-based fuzz pattern
- Existing codebase: foundry.toml -- already configured with invariant runs=256, depth=64
