# Technology Stack

**Project:** Degenerus Protocol v5.0 -- Novel Zero-Day Attack Surface Audit
**Researched:** 2026-03-05
**Mode:** Additive (alongside existing Hardhat + Foundry infrastructure -- DO NOT replace)
**Supersedes:** previous STACK.md dated 2026-03-05 (v4.0 adversarial stress test)

---

## Scope: What This File Covers (and Does NOT Cover)

This STACK.md covers ONLY configuration changes and minor additions needed for v5.0's zero-day hunting. The milestone context is narrow: increased Foundry fuzz runs, Slither full triage, and Halmos symbolic verification of pure math invariants. No new tools need to be installed.

**Already validated (DO NOT re-research, reinstall, or upgrade):**
- Hardhat 2.28.6 + 884 tests
- Foundry 1.5.1-stable + 68 invariant tests across 9 harnesses (4 original + 4 v4.0 additions + 1 deploy canary)
- Halmos 0.3.3 + 10 symbolic properties verified
- Slither 0.11.5 (latest as of Jan 2026)
- forge-std 1.15.0
- Local solc 0.8.34 (hardhat config + foundry.toml both point to same binary)

**v4.0 tools NOT needed for v5.0 (skip):**
- Certora Prover -- v5.0 scope is Halmos-only for math invariants, not unbounded formal verification
- Echidna / Medusa -- v5.0 uses Foundry deep runs, not additional fuzzers
- nashpy / game theory modeling -- v4.0 completed game theory analysis
- SWC registry -- v4.0 white hat agent completed SWC cross-reference

---

## Recommended Stack Changes

### 1. Foundry Config: Deep Fuzz Runs (foundry.toml changes only)

| Setting | Current | Recommended | Why |
|---------|---------|-------------|-----|
| `[fuzz] runs` | 1000 | 10000 | 10x increase exposes edge-case inputs that 1K runs miss. Standard for pre-audit deep runs. |
| `[invariant] runs` | 256 | 1000 | 4x increase. Each run explores a different random call sequence. |
| `[invariant] depth` | 128 | 256 | 2x increase. Deeper call sequences find composition bugs requiring more state transitions. |
| `[invariant] shrink_run_limit` | 5000 | 10000 | Better counterexample minimization at deeper depths. |

**New profile for deep runs:**

```toml
# Add to foundry.toml -- keeps default profile fast for development
[profile.deep]
fuzz.runs = 10000
fuzz.max_test_rejects = 131072
invariant.runs = 1000
invariant.depth = 256
invariant.shrink_run_limit = 10000

[profile.ci]
fuzz.runs = 50000
invariant.runs = 5000
invariant.depth = 512
invariant.shrink_run_limit = 20000
```

**Usage:**
```bash
# Quick iteration (default profile, unchanged)
forge test

# v5.0 deep zero-day hunting
FOUNDRY_PROFILE=deep forge test

# Overnight CI-level exhaustive run
FOUNDRY_PROFILE=ci forge test
```

**Per-test overrides** for specific high-value invariants (Foundry supports inline config via `/// forge-config:`):
```solidity
/// forge-config: default.invariant.runs = 2000
/// forge-config: default.invariant.depth = 512
function invariant_ethSolvency() public {
    // Critical invariant gets extra coverage even in default profile
}
```

**Confidence:** HIGH -- Foundry profiles and inline config are stable, well-documented features. No version upgrade needed.

---

### 2. Halmos: Pure Math Invariant Verification (no upgrade, usage guidance)

| Item | Detail |
|------|--------|
| Version | 0.3.3 (latest, released July 2024 -- no newer version exists) |
| Upgrade needed | NO |
| New capability | Write new test files targeting pure math functions |

**What to verify with Halmos for v5.0:**

The v5.0 scope calls for symbolic verification of pure math invariants -- precision/rounding exploitation and division-before-multiplication chains. Target functions:

| Function/Library | Property to Verify | Halmos Approach |
|------------------|-------------------|-----------------|
| `PriceLookupLib` | Price monotonicity: `price(level+1) >= price(level)` for all levels | Bounded symbolic over level range |
| `PriceLookupLib` | No zero-price: `price(level) > 0` for all valid levels | Exhaustive (finite domain) |
| Deity pass T(n) | `T(n) = n*(n+1)/2` -- no overflow for valid n range | Bounded symbolic, check against reference |
| Lazy pass pricing | Sum-of-10 calculation correctness at level boundaries | Boundary testing with symbolic level |
| Lootbox EV | `EV <= 1.0` for all activity scores (no positive-EV exploitation) | Symbolic over activity score range |
| `BitPackingLib` | Pack/unpack roundtrip: `unpack(pack(x)) == x` for all valid x | Full symbolic verification |
| Vault share math | `shares * totalAssets / totalShares` -- floor division does not create extraction | Symbolic with edge values |
| Coinflip range | Win probability matches documented odds for all bet sizes | Symbolic over bet parameters |

**Critical Halmos limitation for this project:**
Halmos uses SMT solvers that struggle with nonlinear arithmetic (multiplication, division, modulo). The protocol's math is heavy on these operations. Mitigation:
- Use `--solver-timeout-assertion 300000` (5 min per assertion) for complex math
- Use `--loop 0` for pure functions with no loops
- Break complex properties into smaller, isolated assertions
- If a property times out, document it as "needs manual proof" rather than removing it

**New test file structure:**
```
test/fuzz/halmos/
  PriceLookupSymbolic.t.sol    # Price curve properties
  BitPackingSymbolic.t.sol     # Pack/unpack roundtrip
  ShareMathSymbolic.t.sol      # Vault share math
  DeityPricingSymbolic.t.sol   # T(n) pricing formula
  LootboxEVSymbolic.t.sol      # EV <= 1.0 invariant
```

**Running:**
```bash
# Verify all symbolic properties
halmos --contract PriceLookupSymbolicTest --solver-timeout-assertion 300000

# Verify specific property
halmos --contract BitPackingSymbolicTest --function check_roundtrip
```

**Confidence:** HIGH -- Halmos 0.3.3 is stable, pure math verification is its strongest use case. The nonlinear arithmetic limitation is well-documented and manageable for bounded domains.

---

### 3. Slither: Full Triage and Custom Detectors (no upgrade, usage guidance)

| Item | Detail |
|------|--------|
| Version | 0.11.5 (latest, released Jan 2026) |
| Upgrade needed | NO |
| New capability | Full triage methodology + optional custom detectors |

**v5.0 Slither triage approach:**

Previous audits ran Slither and triaged the results (636 findings). v5.0 requires a FULL re-triage with zero-day hunting lens -- not just dismissing known false positives, but examining each finding for composition-based exploitability.

**Run configuration:**
```bash
# Full analysis with all detectors, JSON output for structured triage
slither . --json slither-v5.json --solc-remaps "@openzeppelin/=node_modules/@openzeppelin/" \
  --filter-paths "node_modules|lib|test" \
  --compile-force-framework hardhat

# Focus on specific detector categories for zero-day hunting
slither . --detect reentrancy-eth,reentrancy-no-eth,reentrancy-benign,reentrancy-events \
  --json slither-v5-reentrancy.json

# Delegatecall-specific analysis
slither . --detect delegatecall-loop,controlled-delegatecall \
  --json slither-v5-delegatecall.json

# Arithmetic-focused detectors
slither . --detect divide-before-multiply,tautology,incorrect-equality \
  --json slither-v5-arithmetic.json
```

**Optional: Pessimistic.io slitherin detectors:**

The `slitherin` package (by Pessimistic.io) adds 20+ custom detectors on top of Slither, including read-only reentrancy detection, unprotected setter detection, and token fallback handling. Worth running as a one-time sweep.

```bash
pip install slitherin
slitherin . --pess --json slitherin-v5.json
```

**Confidence:** HIGH for Slither core. MEDIUM for slitherin (third-party detectors, may produce noise, but low-risk to run).

---

### 4. Foundry: Custom Invariant Handlers for Composition Bugs

No new tools needed. The existing handler pattern (`test/fuzz/handlers/`) should be extended with composition-focused handlers:

| New Handler | What It Tests | Why |
|-------------|---------------|-----|
| `CompositionHandler.sol` | Cross-module delegatecall sequences that exercise shared storage | v5.0 targets composition bugs -- random interleaving of module calls through DegenerusGame |
| `PrecisionHandler.sol` | Sequences of small-value operations that accumulate rounding errors | Dust attack detection -- many small purchases/claims that exploit floor division |
| `TemporalHandler.sol` | Time-warped sequences with `vm.warp` at boundary timestamps | Level transition + VRF timeout + game-over boundaries |
| `LifecycleHandler.sol` | Full lifecycle from pre-purchase through game-over to post-game claims | Edge-of-lifecycle states -- the pre-first-purchase and post-gameover residual attack surface |

**New invariant test files:**
```
test/fuzz/invariant/
  Composition.inv.t.sol     # Cross-module shared storage invariants
  Precision.inv.t.sol       # Accumulated rounding never exceeds dust threshold
  Temporal.inv.t.sol        # Timestamp boundary invariants
  Lifecycle.inv.t.sol       # Full lifecycle state invariants
```

**Confidence:** HIGH -- extends existing proven pattern, no new dependencies.

---

## What NOT to Add

| Tool | Why Skip |
|------|----------|
| Foundry upgrade to nightly | v1.5.1-stable is sufficient. Nightly builds risk breaking existing 68 tests for marginal gain. |
| Halmos upgrade | 0.3.3 IS the latest. No newer version exists. |
| Slither upgrade | 0.11.5 IS the latest (Jan 2026). Already installed. |
| Certora Prover | v5.0 scope is bounded math verification (Halmos handles this). Unbounded proofs are out of scope. |
| Echidna / Medusa | Foundry deep profiles (10K-50K runs) provide sufficient coverage. Adding fuzzers adds complexity without proportional value for the v5.0 scope. |
| Mythril | Redundant with Halmos for symbolic execution. |
| forge-coverage (lcov) | Nice-to-have but not needed for zero-day hunting. Coverage tells you what you TESTED, not what is VULNERABLE. |
| New Solidity version | Compiler is pinned at 0.8.34. Changing it would invalidate all prior audit work. |
| Hardhat plugins | No new Hardhat plugins needed. The 884-test suite is stable. |

---

## Full Change Summary

```bash
# No installations needed. Only config changes.

# 1. Update foundry.toml with deep/ci profiles (see section 1)
# 2. Write new Halmos symbolic test files (see section 2)
# 3. Run Slither full triage with structured output (see section 3)
# 4. Write new composition-focused handlers and invariants (see section 4)

# Optional: one-time slitherin sweep
pip install slitherin
```

**Total new dependencies: ZERO (or 1 optional: slitherin pip package)**

---

## Directory Structure Changes

```
degenerus-contracts/
  # MODIFIED
  foundry.toml                          # Add [profile.deep] and [profile.ci]

  # NEW: Halmos symbolic math tests
  test/fuzz/halmos/
    PriceLookupSymbolic.t.sol
    BitPackingSymbolic.t.sol
    ShareMathSymbolic.t.sol
    DeityPricingSymbolic.t.sol
    LootboxEVSymbolic.t.sol

  # NEW: Composition-focused handlers
  test/fuzz/handlers/
    CompositionHandler.sol
    PrecisionHandler.sol
    TemporalHandler.sol
    LifecycleHandler.sol

  # NEW: Composition-focused invariant tests
  test/fuzz/invariant/
    Composition.inv.t.sol
    Precision.inv.t.sol
    Temporal.inv.t.sol
    Lifecycle.inv.t.sol

  # NEW: Slither triage output
  slither-v5.json                       # Full analysis output
  slither-v5-reentrancy.json            # Reentrancy-focused
  slither-v5-delegatecall.json          # Delegatecall-focused
  slither-v5-arithmetic.json            # Arithmetic-focused
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Deep fuzzing | Foundry profile `deep` (10K runs) | Echidna + Medusa | Adding 2 fuzzers increases complexity; Foundry 10K runs with better handlers is more targeted for v5.0 scope |
| Math verification | Halmos 0.3.3 bounded symbolic | Certora unbounded | Overkill for pure math on finite domains; Halmos already installed and proven |
| Static analysis | Slither 0.11.5 + slitherin | Custom Slither plugins | Writing custom detectors is time-expensive; slitherin provides 20+ ready-made detectors for common patterns |
| Composition testing | Custom Foundry handlers | Echidna multi-contract | Foundry handlers integrate with existing test infrastructure; Echidna would require parallel harness maintenance |

---

## Confidence Assessment

| Item | Confidence | Rationale |
|------|------------|-----------|
| Foundry profile config | HIGH | Stable feature, well-documented, no version change needed |
| Foundry inline test config | HIGH | Supported since Foundry v0.2.0, documented in official book |
| Halmos 0.3.3 math verification | HIGH | Proven in v3.0 (10 properties verified), pure math is ideal use case |
| Halmos nonlinear arithmetic limits | HIGH | Documented limitation, mitigations well-understood |
| Slither 0.11.5 full triage | HIGH | Already installed, latest version, proven in prior audits |
| slitherin third-party detectors | MEDIUM | Third-party, may produce noise, but low-risk optional addition |
| No new tools needed | HIGH | All 3 tools (Foundry, Halmos, Slither) are at latest versions and sufficient for v5.0 scope |

---

## Sources

- [Foundry Invariant Testing Docs](https://getfoundry.sh/forge/invariant-testing) -- configuration, handler patterns
- [Foundry Config Reference](https://www.getfoundry.sh/config/reference/overview) -- profile system, fuzz/invariant settings
- [Foundry Inline Test Config](https://book.getfoundry.sh/reference/config/inline-test-config) -- per-test overrides with `/// forge-config:`
- [Halmos GitHub](https://github.com/a16z/halmos) -- v0.3.3 is latest (July 2024), no newer release
- [Halmos: Symbolic Testing for Formal Verification](https://a16zcrypto.com/posts/article/symbolic-testing-with-halmos-leveraging-existing-tests-for-formal-verification/) -- usage patterns, math verification examples
- [Halmos Warnings Wiki](https://github.com/a16z/halmos/wiki/warnings) -- nonlinear arithmetic limitations
- [slither-analyzer on PyPI](https://pypi.org/project/slither-analyzer/) -- v0.11.5, released Jan 16 2026
- [Slither Detector Documentation](https://github.com/crytic/slither/wiki/Detector-Documentation) -- 90+ built-in detectors
- [Slither Custom Detectors](https://github.com/crytic/slither/wiki/Adding-a-new-detector) -- plugin architecture
- [Pessimistic.io slitherin](https://github.com/pessimistic-io/slitherin) -- 20+ additional detectors including read-only reentrancy
- [Foundry GitHub Releases](https://github.com/foundry-rs/foundry/releases) -- v1.5.1-stable confirmed current stable

---

*Stack research for: Degenerus Protocol v5.0 -- Novel Zero-Day Attack Surface Audit*
*Researched: 2026-03-05*
