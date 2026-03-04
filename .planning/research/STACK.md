# Stack Research

**Domain:** Smart Contract Security Audit — Adversarial Phase (v2.0)
**Researched:** 2026-03-04
**Confidence:** HIGH (static analysis tools); HIGH (fuzzer tooling — Trail of Bits blog confirmed); MEDIUM (Halmos version — GitHub releases page confirmed v0.3.3 Jul 2024, no newer release found)

---

## Context

This is the v2.0 adversarial audit of the Degenerus Protocol — 22 contracts, 10 delegatecall modules, Chainlink VRF V2.5, Hardhat + ESM. The v1.0 audit (Slither, Aderyn, forge inspect, manual analysis) is complete. This document covers ONLY what is NEW for v2.0.

**What v1.0 already covered (do not re-purchase):**
- Slither 0.11.5 — 319+ detections classified
- Aderyn — run, findings classified
- forge inspect storage layout — 135 variables, zero slot collisions confirmed
- Slither printers: `variable-order`, `vars-and-auth`, `call-graph`, `data-dependency`
- VRF lifecycle audit — rngLockedFlag, callback gas, requestId matching, entropy derivation confirmed safe
- Access control matrix — all 22 contracts privilege-mapped
- DoS resistance — all loops bounded

**What v2.0 adds (this document):**
- Medusa coverage-guided fuzzing (was "deferred to v2" in PROJECT.md)
- Halmos bounded symbolic execution (was "deferred to v2" in PROJECT.md)
- Foundry forge gas profiling for `advanceGame()` 16M hard limit
- VRF re-entrancy, griefing, retry-window attack vector coverage
- Sybil bloat storage analysis
- Admin rug-vector enumeration methodology

**Threat model for v2.0:** well-funded attacker (~1000 ETH), coordinated Sybil group, block proposer/validator.

---

## Recommended Stack

### Core Static Analysis (carried from v1.0 — verify still current)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Slither | latest (`pip install slither-analyzer`) | Primary static analysis — 100+ detectors, printer suite | Already installed. Re-run `--print call-graph` specifically targeting `advanceGame()` to build the call tree needed for gas path analysis. |
| Aderyn | 0.6.8+ (`cargo install aderyn`) | Secondary static analysis — Rust AST-based, low false-positive rate | Already installed. Re-run after any code changes. Active development (Cyfrin 2025 wrap-up confirms ongoing releases). |
| Semgrep (Decurity rules) | latest | Pattern-matching for DeFi exploit patterns including proxy-storage-collision | Already cloned. No re-install needed. |

### Fuzzing — NEW for v2.0

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Medusa | v1.5.0 (Feb 2025) | PRIMARY fuzzer for v2.0 — coverage-guided, parallelized, Slither-enhanced mutation | Trail of Bits' next-gen fuzzer. v1 announced Feb 2025. Runs parallel fuzzing scaled to CPU cores. "Smart mutational value generation leverages runtime values and insights from Slither." On-chain fuzzing seeds state from mainnet. Built on Geth (strong EVM equivalence). This is the tool for accounting invariants: total ETH in == total ETH out, BPS splits sum to 10000, prize pool never exceeds deposit balance. |
| Echidna | 2.3.1 (Jan 2025) | SECONDARY fuzzer — validation and cross-check of Medusa finds | Mature, battle-tested, extensive docs. 2.3.1 adds symbolic execution verification modes and Foundry reproducer generation. Use to cross-validate Medusa findings. Well-documented Hardhat support via crytic-compile. |

**Why two fuzzers:** Medusa and Echidna use different mutation strategies and corpus management. Bugs that Medusa's coverage guidance misses (e.g., narrow state-transition windows in the FSM) may surface from Echidna's corpus-based approach. The Trail of Bits comparison shows Medusa wins on invariant discovery speed but recommends using both for stateful fuzzing depth.

**What to fuzz (priority order):**
1. ETH accounting invariant: `sum(deposits) == prizePool + futurePool + vault + claimable + fees` across all game states
2. BPS fee splits: assert they sum to 10000 on every code path including game-over settlement
3. Price escalation: fuzz ticket quantity/price combos for overflow or division edge cases
4. Lootbox EV: fuzz activity score boundaries and multiplier ceiling for precision loss
5. Deity pass pricing: `24 + T(n)` where `T(n) = n*(n+1)/2` — verify no integer overflow at high n
6. Coinflip range: all MintPaymentKind variants with adversarial input combinations

### Formal Verification — ACTIVATED for v2.0 (was deferred)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Halmos | v0.3.3 (Jul 2024 — latest confirmed) | Bounded symbolic execution for critical math properties | Open-source from a16z. Used to formally verify Ethereum Pectra system contracts in 2025. Works with Foundry test syntax — no new DSL. Use narrowly: deity pass triangular number formula, ticket cost formula `(priceWei * qty) / 400`, EV multiplier arithmetic bounds. NOT recommended for full protocol — path explosion on complex FSM state. |

**Halmos integration:** Write standalone Foundry test files importing the compiled Solidity source directly. Halmos operates on the test harness, not the Hardhat build system. Place harnesses in a separate `audit-harnesses/` directory with their own `foundry.toml`.

### Gas Profiling — NEW for v2.0

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Foundry forge `--gas-report` | v1.0+ (Feb 2025) | Function-level gas measurement across all `advanceGame()` code paths | The `advanceGame()` 16M gas hard limit is the primary DoS surface. Foundry v1.0 is 2x faster than v0.2. Write a Foundry test harness with isolated `advanceGame()` scenarios (worst-case Sybil bloat, maximum bucket counts, all module delegatecalls active). Run `forge test --match-test advanceGame --gas-report`. |
| Hardhat `REPORT_GAS=true` | existing (hardhat-gas-reporter 2.2.x) | Method-level gas within existing 884-test suite | Already available in project. Use `REPORT_GAS=true npx hardhat test` to measure gas across all existing test scenarios. Provides baseline before Foundry targeted worst-case measurement. Note: v2.x migrated to Etherscan V2 API — configure or disable ETH price reporting if API key not set. |
| Slither `call-graph` printer | built into Slither | Generate `advanceGame()` call tree for path enumeration | `slither . --print call-graph` outputs dot graph. Feed into `dot -Tpng` to visualize the full call tree. Enumerate all paths through `advanceGame()` — each path is a potential gas worst-case that must be measured. |

**Gas audit methodology for `advanceGame()`:**
1. Run `slither . --print call-graph` → enumerate every function `advanceGame()` can call
2. Identify all branch conditions in each called function
3. Write Foundry worst-case scenarios: maximum `bucketCount`, maximum `playerCount`, all delegatecall modules active
4. Measure with `forge test --gas-report`
5. Compare measured worst-case against 16,000,000 gas hard limit with 20% safety margin
6. Flag any code path >12,800,000 gas as HIGH severity DoS risk

### VRF-Specific Attack Surface — DEEPENED for v2.0

| Tool / Method | Purpose | What It Adds Over v1.0 |
|---------------|---------|------------------------|
| Chainlink VRF V2.5 Security Checklist (official docs) | Verify all 8 mandatory security properties | v1.0 confirmed the lifecycle is correct. v2.0 focuses on GRIEFING vectors: retry window exploitation, fulfillment reversion, subscription draining. |
| Slither `data-dependency` re-run with attacker focus | Trace VRF output to outcome state, find pollution vectors | v1.0 confirmed entropy derivation. v2.0 asks: can an attacker influence the seed by controlling which block the request lands in? |
| Manual re-entrancy review on `fulfillRandomWords` | VRF callback as re-entrancy entry point | v2.0 explicitly checks: does `fulfillRandomWords` make any external calls or ETH transfers before updating state? If so, reentrancy is possible through the VRF callback. |

**VRF v2.0 attack vectors to cover (from official Chainlink documentation):**

1. **Re-requesting griefing** — If any path exists to cancel and re-request randomness, a VRF subscription owner can discard unfavorable results. Verify the Degenerus RNG lock state machine makes re-requesting impossible once `rngLockedFlag` is set.

2. **User inputs after request** — No user action (purchase, bet, claim) should be accepted during the 18-hour RNG lock window. If any function is callable during the lock that affects outcome determination, it violates VRF security properties.

3. **Fulfillment reversion** — `fulfillRandomWords` MUST NOT revert. If it reverts, VRF service does not retry and the game is permanently stuck. Verify: no `require` that could fail, no OOG (out-of-gas) on complex operations inside the callback, all state transitions pre-validated.

4. **Multiple requests in flight** — Verify only one VRF request can be in flight at a time. If two requests could be in flight simultaneously, validator-controlled ordering becomes an attack surface.

5. **Block proposer rewrite** — A validator can rewrite chain history to place the VRF request in a different block (different seed) but CANNOT predict the output. Risk: validator chooses seed by selecting which block the request lands in. Mitigated by `requestConfirmations >= 3`. Verify the actual `requestConfirmations` value in the implementation.

6. **Subscription draining** — An attacker who can trigger VRF requests (if any unpermissioned path exists) can drain the LINK subscription. Verify VRF request initiation is admin-only or game-state-gated.

7. **Coordinator spoofing** — `fulfillRandomWords` must only be callable by the legitimate VRF coordinator. Degenerus uses direct coordinator interface (not VRFConsumerBaseV2Plus) — verify the caller check is correct and cannot be spoofed.

### Sybil Bloat Analysis — NEW for v2.0

| Method | Purpose | Tools |
|--------|---------|-------|
| Storage growth calculation | Quantify per-player storage footprint and maximum possible state size | Manual: count storage writes per `purchase()` call × max possible player count; estimate worst-case gas for `advanceGame()` bucket iteration |
| Bucket cursor analysis | Verify bucket cursor pattern is Sybil-resistant | Slither `call-graph` + manual review of bucket data structure mutation pattern |
| Player data structure O(n) audit | Identify any O(n) loops over player arrays in `advanceGame()` | Manual code review of all loops with explicit player/bucket counting |

**Sybil bloat methodology:**
1. Identify maximum per-player storage written per `purchase()` call
2. Calculate storage cost at 1000 Sybil accounts × 10 tickets each
3. Calculate `advanceGame()` gas at 1000 players (bucket iteration)
4. Find the player count N where `advanceGame()` hits 16M gas
5. Calculate ETH cost to reach N players at minimum ticket price
6. If cost < 1000 ETH (threat model budget), flag as exploitable DoS

### Admin Rug Vector Enumeration — NEW for v2.0

| Method | Purpose | Tools |
|--------|---------|-------|
| `vars-and-auth` printer | Map every state variable to its controlling auth condition | `slither . --print vars-and-auth` |
| Admin power inventory | Enumerate every admin-callable function and its worst-case effect | Manual review of all functions guarded by `onlyAdmin` or equivalent |
| Emergency halt analysis | Assess 3-day emergency stall trigger for abuse | Manual: what conditions allow admin to halt game? what funds are accessible during halt? |
| Withdrawal path analysis | Confirm no admin-only ETH drain path exists | Manual CEI review of all ETH transfer functions |

**Admin rug vectors to enumerate:**
1. Can admin halt the game indefinitely? What happens to player ETH during halt?
2. Can admin modify prize pool percentages mid-game in their favor?
3. Can admin trigger game-over prematurely before players can react?
4. Can admin change VRF subscription (coordinator spoofing via admin)?
5. Can admin drain the vault via `vaultMintAllowance` manipulation?
6. Can admin grief specific players via access control manipulation?

---

## Installation

```bash
# Medusa fuzzer (Go) — NEW for v2.0
go install github.com/crytic/medusa/cmd/medusa@v1.5.0

# Echidna — via Docker for reproducible environment
docker pull ghcr.io/crytic/echidna/echidna:latest
# Or binary: https://github.com/crytic/echidna/releases/tag/v2.3.1

# Halmos (formal verification) — NEW for v2.0
pip install halmos
# Verify: halmos --version  (expect v0.3.3 or higher)

# Foundry — for gas profiling harnesses
curl -L https://foundry.paradigm.xyz | bash
foundryup
# Verify: forge --version (expect v1.0+, Feb 2025 release)

# Hardhat gas reporter — already in project, enable with:
REPORT_GAS=true npx hardhat test

# Slither (already installed — verify version)
slither --version  # Should be 0.11.5+

# Slither gas/call analysis commands:
slither . --print call-graph          # Build advanceGame() call tree
slither . --print vars-and-auth       # Admin power map
slither . --print data-dependency     # VRF data flow tracing
```

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Mythril | SMT solver times out on contracts >300 lines in practical use; `DegenerusGame` is 19KB compiled. Analysis would run hours and produce stale results. GitHub issues document stalls at 20+ seconds for individual instruction sequences. Default max recursion depth of 22 is insufficient for multi-step FSM state exploration. | Medusa + Halmos: Medusa finds behavioral bugs Mythril would timeout on; Halmos provides bounded symbolic proofs for critical math |
| MythX | Commercial SaaS wrapper around Mythril; same underlying limitations with added cost and API rate limits | Slither + Medusa |
| Securify2 | Effectively unmaintained; last meaningful update 2020; does not understand Solidity 0.8.x patterns | Slither (actively maintained, 100+ detectors for 0.8.x) |
| Certora Prover (for this audit) | Now open-source (confirmed 2025) but requires learning CVL specification language and significant setup time. The ROI is low for a time-boxed adversarial audit — Halmos + Medusa together cover the critical math and behavioral properties. Certora is worth considering for a long-form formal verification engagement after the audit. | Halmos for math properties; Medusa for behavioral invariants |
| AI-only audit tools | LLM analysis without execution semantics cannot reason about state-dependent bugs, reentrancy across delegatecall, or gas path worst-cases. High false-positive rate. Use LLM as a reasoning layer ON TOP of tool outputs, not as a primary tool. | Use Claude/GPT to reason about Slither findings and Medusa counterexamples, not as primary scanner |
| Foundry as primary test environment | The protocol is a Hardhat ESM project with 884 existing tests. Do not migrate. Use Foundry ONLY for standalone audit harnesses (gas profiling, Halmos, invariant harnesses) that compile independently. | Hardhat for all regression testing; Foundry for targeted audit harnesses only |

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Medusa v1.5.0 | Echidna 2.3.1 | Use Echidna when Medusa's crytic-compile Hardhat integration causes issues with the ESM project; Echidna has more mature documentation and broader community examples for Hardhat. Use both in parallel for cross-validation. |
| Halmos v0.3.3 | Certora Prover | Use Certora if Halmos hits path explosion on a specific property (most likely on FSM state machine verification). Certora's unbounded verification handles loop-heavy contracts better. Trade-off: CVL learning curve and longer setup. |
| forge `--gas-report` | Hardhat gas reporter only | Hardhat gas reporter measures existing test paths. For worst-case adversarial gas paths not covered by the existing test suite, Foundry test harnesses allow custom scenario construction. Use both together. |
| Slither `call-graph` + manual | Automated call tree tool | No better alternative for Solidity call graph analysis. Slither's printer output is reliable. `dot` converts to PNG for human analysis. |

---

## Stack Patterns by v2.0 Attack Surface

**`advanceGame()` gas profiling (16M hard limit):**
1. `slither . --print call-graph` → enumerate all functions `advanceGame()` can call
2. Map all branch conditions in each callee → identify worst-case code paths
3. Write Foundry test harnesses with maximum plausible state (1000 players, full buckets, all modules active)
4. `forge test --match-test testAdvanceGameWorstCase --gas-report` → measure gas
5. `REPORT_GAS=true npx hardhat test` → baseline from existing suite
6. Any path >12.8M gas (80% of limit) = flag as HIGH severity DoS risk

**Sybil bloat analysis:**
1. Count storage writes per `purchase()` call — estimate per-player footprint
2. Find minimum ETH cost to add one player
3. Calculate N players where `advanceGame()` hits 16M gas
4. If N × minimum_ticket_cost < 1000 ETH → exploitable DoS, flag CRITICAL

**VRF griefing and re-entrancy:**
1. Verify `rngLockedFlag` prevents all state-changing user calls during 18-hour window
2. Verify `fulfillRandomWords` cannot revert under any condition (check all code paths inside callback)
3. Verify no external calls or ETH transfers in `fulfillRandomWords` before state update (CEI)
4. Check if any unpermissioned path can trigger a new VRF request (subscription drain)
5. Verify `requestConfirmations` value — minimum 3 for mainnet validator-rewrite resistance
6. Confirm caller check on `fulfillRandomWords` cannot be bypassed

**Accounting invariants (Medusa):**
1. Write Medusa property harness: `property_ethBalance() returns bool`
2. Assert: `address(game).balance == prizePool + futurePool + claimableTotal + fees`
3. Assert: BPS splits sum to exactly 10000 on all code paths
4. Assert: claimWinnings() cannot be called twice for the same winner
5. Assert: game ETH balance reaches exactly 0 after all claims are processed

**Admin rug vectors:**
1. `slither . --print vars-and-auth` → enumerate all admin-controlled state
2. For each admin function: simulate worst-case from player perspective
3. Check: can any admin action cause irreversible loss of player ETH?
4. Check: is there a time-lock or multi-sig on critical admin functions?
5. Flag any single-admin function with irreversible financial consequence as MEDIUM or higher

---

## VRF V2.5 Audit Checklist — Adversarial Expansion

From the [official Chainlink VRF V2.5 security documentation](https://docs.chain.link/vrf/v2-5/security):

| Check | v1.0 Status | v2.0 Focus |
|-------|-------------|------------|
| requestId matching | CONFIRMED safe | No re-audit needed |
| Block confirmation time | CONFIRMED | Verify `requestConfirmations` value is >=3 for mainnet |
| No re-requesting | CONFIRMED by RNG lock | Adversarially: find ANY path to cancel/re-request |
| Input cutoff after request | CONFIRMED by RNG lock | Adversarially: find ANY state-changing call possible during lock |
| Non-reverting fulfillment | CONFIRMED | Adversarially: fuzz the callback with out-of-gas scenarios |
| Coordinator caller check | CONFIRMED | Verify exact check — direct interface not VRFConsumerBaseV2Plus |
| Subscription funding | n/a (operational) | Flag underfunding risk at multiple concurrent request capacity |
| Validator rewrite risk | ASSESSED | Confirm requestConfirmations mitigates at protocol's economic stakes |
| Subscription owner malice | NEW | Can subscription owner (admin?) withhold/reroll randomness? |

---

## Version Compatibility

| Package | Version | Compatible With | Notes |
|---------|---------|-----------------|-------|
| Medusa | v1.5.0 | Hardhat via crytic-compile | ESM projects may need `--build-system hardhat` flag. Verify with `medusa fuzz --config medusa.json` where config specifies `buildSystem: "hardhat"`. Requires Go 1.21+. |
| Echidna | 2.3.1 | Hardhat via crytic-compile | Mature Hardhat support. 2.3.1 adds Foundry reproducer generation — useful for converting Echidna finds into Foundry PoC tests. |
| Halmos | v0.3.3 | Foundry test harnesses only | Does NOT integrate with Hardhat directly. Write standalone Foundry test files in `audit-harnesses/` with `foundry.toml`. Halmos runs on these harnesses independently. |
| Foundry forge | v1.0+ (Feb 2025) | Standalone — no Hardhat dependency | Install alongside Hardhat project. Use only for audit harnesses in `audit-harnesses/` directory. Do not touch existing Hardhat config. |
| Slither | 0.11.5+ | Solidity 0.8.26 + 0.8.28 | Both compiler versions in the project are fully supported. Use `--hardhat-ignore-compile` if compilation conflicts arise with ESM config. |
| hardhat-gas-reporter | 2.2.x | ESM Hardhat project | v2.x migrated to Etherscan V2 API (V1 stopped working Jun 2025). Set `COINMARKETCAP_API_KEY=` empty or `currency: "none"` to suppress USD pricing if API key unavailable. |

---

## Sources

- [Medusa v1 announcement — Trail of Bits Blog (Feb 14, 2025)](https://blog.trailofbits.com/2025/02/14/unleashing-medusa-fast-and-scalable-smart-contract-fuzzing/) — capabilities, Slither integration, on-chain fuzzing, Echidna comparison (HIGH confidence — primary source)
- [Medusa GitHub releases (crytic/medusa)](https://github.com/crytic/medusa/releases) — v1.5.0 released Feb 6, 2025 (HIGH confidence — direct)
- [Echidna GitHub releases (crytic/echidna)](https://github.com/crytic/echidna/releases) — v2.3.1 released Jan 16, 2025, Foundry reproducer generation (HIGH confidence — direct)
- [Halmos GitHub releases (a16z/halmos)](https://github.com/a16z/halmos/releases) — v0.3.3 latest release confirmed (MEDIUM confidence — no date visible, could be 2024)
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — all 8 VRF security properties, griefing vectors, validator rewrite, subscription owner malice (HIGH confidence — official Chainlink documentation)
- [Foundry v1.0 Announcement (Paradigm, Feb 2025)](https://www.paradigm.xyz/2025/02/announcing-foundry-v1-0) — 2x faster invariant testing, gas-report improvements (HIGH confidence)
- [Forge Gas Reports (getfoundry.sh)](https://getfoundry.sh/forge/gas-reports) — `--gas-report` flags, function-level measurement, gas snapshot methodology (HIGH confidence — official docs)
- [Fuzzing comparison: Foundry vs Echidna vs Medusa (devdacian)](https://github.com/devdacian/solidity-fuzzing-comparison) — Medusa breaks 2 invariants where Echidna breaks 1 within 5 min (MEDIUM confidence — community benchmark)
- [Halmos for Pectra formal verification (a16z, 2025)](https://a16zcrypto.com/posts/article/formal-verification-of-pectra-system-contracts-with-halmos/) — Halmos used on production Ethereum system contracts (HIGH confidence — primary source)
- [Mythril GitHub (ConsenSysDiligence/mythril)](https://github.com/ConsenSysDiligence/mythril) — symbolic execution stalls documented in issue #857, default --max-depth 22 limitation (HIGH confidence)
- [Certora Prover Goes Open Source (certora.com)](https://www.certora.com/blog/certora-goes-open-source) — confirmed free and open-source as of 2025 (HIGH confidence — primary source)
- [Slither check-upgradeability (secure-contracts.com)](https://secure-contracts.com/program-analysis/slither/docs/src/tools/Upgradeability-Checks.html) — storage layout collision detection via `slither-check-upgradeability` (HIGH confidence)
- [hardhat-gas-reporter npm / GitHub (cgewecke)](https://github.com/cgewecke/hardhat-gas-reporter) — v2.x Etherscan V2 API migration, ESM Hardhat 2 compatibility (MEDIUM confidence — Hardhat 3 ESM status not explicitly confirmed for plugin)
- [Aderyn GitHub releases (Cyfrin/aderyn)](https://github.com/Cyfrin/aderyn/releases) — v0.6.8 latest (MEDIUM confidence — exact release date not confirmed in search)

---

*Stack research for: Smart Contract Security Audit — Degenerus Protocol v2.0 Adversarial Audit*
*Researched: 2026-03-04*
*Supersedes: previous STACK.md dated 2026-02-28 (v1.0 audit)*
