# Stack Research

**Domain:** Smart Contract Security Audit (Existing Solidity Protocol)
**Researched:** 2026-02-28
**Confidence:** MEDIUM-HIGH (static analysis tools HIGH; fuzzer tooling MEDIUM; formal verification LOW for this protocol's specific needs)

---

## Context

This is an audit of an existing 22-contract Solidity 0.8.x protocol — not building new contracts. The stack is the auditor's toolchain, not the protocol stack. Degenerus Protocol has specific threat surfaces that drive tool selection:

- **Delegatecall module pattern** with shared `DegenerusGameStorage` across 10 modules — requires storage layout analysis
- **Chainlink VRF V2.5 integration** with a multi-step RNG state machine — requires VRF-specific review checklist
- **Complex accounting** (prize pool splits, EV multipliers, fee distributions) — requires invariant testing
- **Custom errors throughout** with generic `E()` guards — requires understanding of access control boundary
- **Hardhat project** (ESM, not Foundry) — limits some tool integration but not blocking

---

## Recommended Stack

### Core Static Analysis

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Slither | Latest (pip install slither-analyzer) | Primary static analysis — 100+ detectors, printer suite for storage/call graph visualization | Industry standard from Trail of Bits. Runs in <1s per contract. Has `variable-order` printer for storage layout verification across delegatecall modules. Detects controlled delegatecall destinations, reentrancy, weak PRNG, locked ETH. Outputs CI-compatible JSON. Hardhat integration via `crytic-compile`. |
| Aderyn | Latest (cargo install aderyn) | Secondary static analysis — fast AST-based Rust analyzer, low false-positive rate | Complementary to Slither — catches different pattern classes. Runs in <1s per codebase. Generates markdown report format ideal for findings documentation. Official tool run before CodeHawks competitions. Integrates with VS Code/Claude Code via MCP. |
| Semgrep (Decurity rules) | Latest | Pattern-matching for DeFi-specific exploit patterns | Decurity's `semgrep-smart-contracts` ruleset encodes real DeFi exploit patterns as Semgrep YAML rules. Includes a proxy-storage-collision rule directly relevant to delegatecall pattern. Catches things Slither misses via custom pattern logic. |

### Fuzzing / Dynamic Analysis

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Medusa | Latest (go install) | Primary fuzzer — coverage-guided, parallelized, EVM-equivalent | Trail of Bits' next-generation fuzzer (announced Feb 2025). Faster than Echidna for coverage discovery. Parallel execution scales with CPU cores. Built on Geth for strong EVM equivalence. Best for finding accounting invariant violations in prize pool splits and EV multiplier math. Uses same property syntax as Echidna (`echidna_` prefix functions). |
| Echidna | Latest (via crytic-compile) | Fallback fuzzer / validation | Mature, battle-tested, extensive documentation. Use Echidna to cross-validate Medusa findings and when Medusa's Hardhat crytic-compile integration causes issues. Well-documented Hardhat support via `crytic-compile`. |
| Foundry Forge (fuzz + invariant) | v1.3.0+ | Stateful invariant testing via handler pattern | Foundry v1.0 (Feb 2025) is 2x faster; v1.3.0 adds coverage-guided fuzzing for invariant tests. Even though the protocol is a Hardhat project, Foundry can be installed separately and used to write standalone invariant test harnesses that import the compiled artifacts. Use for high-priority accounting invariants: total ETH in == total ETH out across prize pool distributions. |

### Formal Verification (Targeted Use Only)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Halmos | Latest (pip install halmos) | Symbolic execution for bounded property verification | Open-source, free, used by a16z to verify Pectra system contracts. Works with existing Foundry test syntax — no new DSL to learn. Use narrowly for critical math: deity pass pricing formula `24 + T(n)` where T(n) = n*(n+1)/2, ticket cost formula `(priceWei * qty) / 400`. NOT recommended for full protocol verification — too complex. |
| Certora Prover | Latest (now open-source) | Industrial-grade formal verification | Certora went open-source in 2025. More powerful than Halmos but requires learning CVL specification language. Reserve for phase 2 if Halmos hits limits on specific invariants. Out of scope for initial audit pass. |

### Chainlink VRF-Specific Analysis

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Chainlink VRF V2.5 Security Checklist | n/a (manual) | Systematic VRF vulnerability class coverage | Official Chainlink docs define 8 mandatory security checks for VRF V2.5 consumers. Must verify: requestId matching, block confirmation time, no re-requesting, input cutoff after request, non-reverting fulfillment, correct base contract inheritance, subscription funding adequacy. |
| Slither `data-dependency` printer | Built into Slither | Map data flow from VRF callback to game state | Run `slither . --print data-dependency` to trace how VRF output flows into game outcome decisions and identify if any user-controlled inputs can pollute the flow. |

### Development Environment & Utilities

| Tool | Purpose | Notes |
|------|---------|-------|
| Hardhat (existing) | Compile, test, fork — the existing project environment | Protocol already uses Hardhat. Don't try to migrate to Foundry. Use existing 884-test suite as regression baseline. |
| Anvil (Foundry) | Mainnet fork for transaction-level debugging | Install Foundry standalone for Anvil. Fork mainnet at specific blocks to reproduce edge cases without affecting the Hardhat setup. |
| Tenderly | Transaction simulation and step-by-step execution tracing | Fork mainnet state and simulate complex multi-step interactions (whale attacks, Sybil sequences, game-over edge cases). Visualizes state changes across all 22 contracts in a single transaction chain. Free tier sufficient for audit scope. |
| Solodit Checklist | Canonical community-sourced audit checklist (~380 checks) | `solodit.cyfrin.io/checklist` — aggregate of 15,000+ real audit findings. Use as systematic coverage checklist. VRF randomness, reentrancy, access control, and accounting sections are all directly relevant. |
| Slither `vars-and-auth` printer | Authorization boundary mapping | `slither . --print vars-and-auth` — lists every state variable and which msg.sender conditions gate its modification. Use to build the access control matrix for all 22 contracts. |
| Slither `variable-order` printer | Delegatecall storage safety | `slither . --print variable-order` — shows slot positions for all storage variables. Compare output between `DegenerusGame` and each of the 10 delegatecall modules to detect slot collisions in shared `DegenerusGameStorage`. |
| Slither `call-graph` printer | Cross-contract call surface | `slither . --print call-graph` — generates dot graph of all inter-contract calls. Use to identify reentrancy entry points and callback manipulation vectors. |

---

## Installation

```bash
# Static analysis (Python)
pip install slither-analyzer
pip install semgrep

# Aderyn (Rust)
cargo install aderyn

# Decurity semgrep rules
git clone https://github.com/Decurity/semgrep-smart-contracts
semgrep --config ./semgrep-smart-contracts/solidity/security/ contracts/

# Medusa fuzzer (Go)
go install github.com/crytic/medusa/cmd/medusa@latest

# Echidna (via Docker or binary)
docker pull trailofbits/echidna

# Foundry (for Anvil + Forge invariant harnesses)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Halmos (formal verification)
pip install halmos

# Slither on Hardhat project
slither . --hardhat-ignore-compile  # Uses pre-compiled artifacts
# Or with compilation:
slither .  # Triggers hardhat compile via crytic-compile
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Medusa | Echidna | Use Echidna when crytic-compile Hardhat integration has issues with Medusa; for simpler property sets; for documentation-heavy campaigns where Echidna's mature docs matter |
| Medusa | Foundry invariant only | Foundry invariant testing is excellent for property declaration but Medusa/Echidna find more corpus-driven bugs; use Foundry for protocol-owned tests, Medusa for security-researcher fuzzing |
| Halmos | Certora Prover | Use Certora if bounded symbolic execution with Halmos can't prove a critical property due to path explosion; Certora's CVL allows contract invariants; trade-off is learning CVL and more setup time |
| Aderyn | 4naly3er | 4naly3er is older, less maintained, Code4rena-specific tooling. Aderyn is its modern successor with active development, VS Code integration, and MCP server support. |
| Tenderly | Hardhat console.log debugging | Tenderly gives full execution trace across all contracts in a call chain; Hardhat console.log only works for locally compiled contracts; Tenderly wins for multi-contract state inspection |
| Semgrep (Decurity) | MythX / Mythril | Mythril uses symbolic execution which has SMT solver timeout issues at scale; can't complete analysis on larger contracts. Semgrep pattern rules are deterministic and fast. Mythril takes 125+ seconds per contract and is not customizable. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Mythril | SMT solver timeout on contracts >300 lines; 125s+ analysis time; non-customizable detectors; 6/10 detection rate in comparative testing | Slither + Semgrep for pattern coverage; Medusa for deep behavioral bugs |
| MythX | Commercial SaaS version of Mythril; same underlying limitations; adds cost without meaningful benefit over Slither + Echidna/Medusa | Slither + Medusa |
| Securify / Securify2 | Effectively unmaintained; limited to basic vulnerability classes; not updated for modern Solidity patterns | Slither (actively maintained, 100 detectors) |
| AI-only audit tools (Audit Wizard AI-only mode, etc.) | LLM analysis without execution semantics produces high false-positive rates; misses state-dependent bugs entirely; never use as primary analysis | Use LLM as reasoning layer ON TOP of Slither/Medusa findings, not as replacement |
| Truffle | Deprecated development framework; Degenerus is already Hardhat; avoid introducing another framework | Stay on Hardhat for development; use Foundry tooling only for Anvil/Forge audit harnesses |
| Remix IDE audit plugins | Not suitable for 22-contract protocol of this complexity; browser-based, limited analysis depth | CLI-based Slither + Aderyn |

---

## Stack Patterns by Audit Phase

**For storage layout / delegatecall safety analysis:**
- Run Slither `variable-order` and `inheritance-graph` printers across all 10 module contracts and `DegenerusGame`
- Manually diff slot assignments between `DegenerusGameStorage` and each module's inherited layout
- Check Semgrep `proxy-storage-collision` rule across the codebase

**For VRF security:**
- Walk Chainlink's official 8-point VRF V2.5 security checklist against the implementation
- Run Slither `data-dependency` to trace VRF randomness output to outcome-determining state
- Check that `fulfillRandomWords` cannot revert (VRF service does not retry failed callbacks)
- Verify RNG lock state machine: no state changes possible during the 18-hour VRF callback window

**For accounting / economic invariants:**
- Write Foundry/Medusa invariant harnesses asserting: total ETH deposited == prize pools + fees + vault allocations
- Assert fee splits sum to 100% across all code paths (including game-over edge cases)
- Fuzz price escalation curves and EV multiplier arithmetic for precision loss or overflow conditions
- Test lootbox EV score boundaries and activity-score multiplier ceilings

**For access control:**
- Run Slither `vars-and-auth` to generate the full authorization matrix
- Cross-check against expected operator/admin privilege boundaries
- Test all privileged functions for missing guards and role confusion

**For reentrancy:**
- Focus on ETH transfer paths: pull-pattern withdrawals, game-over settlement distributions
- Check stETH callback patterns (Lido integration)
- Verify checks-effects-interactions ordering on all external call sites

---

## VRF V2.5 Audit Checklist (Protocol-Specific)

Based on Chainlink's official security documentation:

1. **requestId matching** — `fulfillRandomWords` uses `requestId` to route to the correct pending request
2. **Block confirmation time** — `requestConfirmations` set appropriately for the game's economic stakes
3. **No re-requesting** — protocol cannot discard an unfavorable VRF result and re-request
4. **Input cutoff** — no user inputs accepted after a VRF request is submitted (the 18-hour RNG lock)
5. **Non-reverting fulfillment** — `fulfillRandomWords` must not revert under any condition; VRF service will not retry
6. **Base contract inheritance** — inherits `VRFConsumerBaseV2Plus`, does not override `rawFulfillRandomness`
7. **Subscription funding** — LINK subscription balance maintained above minimum for concurrent request capacity
8. **Validator rewrite risk** — block proposer can reorder transactions to change which block the VRF request lands in (different seed) but cannot predict the VRF output in advance — LOW risk for most uses but HIGH risk if game outcome resolves in same block as fulfillment

---

## Delegatecall Storage Safety Checklist

Critical for the 10-module pattern used in Degenerus:

1. **Slot position alignment** — every storage variable in modules must occupy the same slot as in `DegenerusGameStorage`
2. **No module-local state** — modules must not declare storage variables not in the shared layout
3. **Inheritance ordering** — if any contract uses multiple inheritance, linearization order must match across caller and callee
4. **No `msg.value` in delegatecall** — if any module handles ETH via `msg.value`, verify it cannot be re-used across recursive calls
5. **EIP-1967 slots** — check if admin/implementation pointer slots use standard EIP-1967 patterns to avoid collision with domain state

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Slither (latest) | Solidity 0.8.26 + 0.8.28 | Full support; Slither supports Solidity >=0.4. The two compiler versions in Degenerus (0.8.26 main, 0.8.28 some contracts) are both supported without configuration changes. |
| Slither (latest) | Hardhat via crytic-compile | crytic-compile handles Hardhat ESM projects; may need `--hardhat-ignore-compile` if compilation conflicts arise |
| Medusa (latest) | crytic-compile (Hardhat) | Medusa uses crytic-compile for build system abstraction; Hardhat support is available but ESM project may need `--build-system hardhat` flag |
| Echidna (latest) | crytic-compile (Hardhat) | Battle-tested Hardhat support; mature documentation for Hardhat configuration |
| Halmos (latest) | Foundry test format | Halmos requires Foundry-style test contracts; write audit harnesses in Foundry syntax even if deploying to separate test directory |
| Foundry v1.3.0+ | Standalone (no Hardhat dependency) | Install Foundry alongside the Hardhat project; write audit harnesses that compile independently using raw contract source files |
| Aderyn (latest) | Any project with compiled AST | Works with Hardhat, Foundry, Truffle; generates AST from source; no compilation step required |

---

## Sources

- [Slither GitHub (crytic/slither)](https://github.com/crytic/slither) — 100 detectors, printer commands, Hardhat integration (HIGH confidence)
- [Slither Printer Documentation (secure-contracts.com)](https://secure-contracts.com/program-analysis/slither/docs/src/printers/Printer-documentation.html) — `variable-order`, `vars-and-auth`, `call-graph`, `data-dependency` printer commands (HIGH confidence)
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — official 8-point audit checklist for VRF consumers (HIGH confidence)
- [Medusa: Trail of Bits Blog (Feb 2025)](https://blog.trailofbits.com/2025/02/14/unleashing-medusa-fast-and-scalable-smart-contract-fuzzing/) — Medusa v1 announcement, capabilities, Echidna comparison (HIGH confidence, current)
- [Echidna GitHub (crytic/echidna)](https://github.com/crytic/echidna) — Hardhat support via crytic-compile, property testing modes (HIGH confidence)
- [Foundry v1.0 Announcement (Paradigm)](https://www.paradigm.xyz/2025/02/announcing-foundry-v1-0) — 2x performance improvement, invariant test shrinking improvements (HIGH confidence, Feb 2025)
- [Aderyn GitHub (Cyfrin/aderyn)](https://github.com/Cyfrin/aderyn) — Rust-based static analyzer, MCP server, custom detectors (HIGH confidence)
- [Decurity semgrep-smart-contracts](https://github.com/Decurity/semgrep-smart-contracts) — DeFi exploit pattern rules including proxy-storage-collision.yaml (MEDIUM confidence — verify rule is current)
- [Halmos formal verification (a16z)](https://a16zcrypto.com/posts/article/formal-verification-of-pectra-system-contracts-with-halmos/) — Halmos used to verify Pectra system contracts (HIGH confidence, 2025)
- [Certora Goes Open Source](https://www.certora.com/blog/certora-goes-open-source) — Certora Prover now free/open-source (MEDIUM confidence — verify current licensing status)
- [Cyfrin audit toolchain overview](https://www.cyfrin.io/blog/industry-leading-smart-contract-auditing-and-security-tools) — Medusa, Aderyn, Halmos, Foundry as standard stack (MEDIUM confidence — vendor-authored but accurate)
- [Solodit audit checklist](https://solodit.cyfrin.io/checklist) — ~380 community checks aggregated from real audits (MEDIUM confidence — evolving document)
- [Mythril limitations (Vultbase comparison)](https://www.vultbase.com/articles/smart-contract-security-tools-compared) — SMT timeout issues, non-customizability (MEDIUM confidence)
- [Delegatecall storage collision (MixBytes)](https://mixbytes.io/blog/collisions-solidity-storage-layouts) — Storage slot collision patterns and detection (MEDIUM confidence)
- [Fuzzing comparison: Foundry vs Echidna vs Medusa](https://github.com/devdacian/solidity-fuzzing-comparison) — Medusa breaks invariants Foundry never finds within 5 minutes (MEDIUM confidence)

---

*Stack research for: Smart Contract Security Audit — Degenerus Protocol*
*Researched: 2026-02-28*
