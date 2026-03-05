# Technology Stack

**Project:** Degenerus Protocol v3.0 -- Invariant Fuzzing and Blind Adversarial Hardening
**Researched:** 2026-03-05
**Mode:** Additive (alongside existing Hardhat project -- DO NOT replace or migrate)
**Supersedes:** previous STACK.md dated 2026-03-04 (v2.0 audit)

---

## Critical Blocker: Solidity 0.8.34 vs Foundry solc Support

**Severity:** BLOCKING -- must resolve before any invariant test can import production contracts.

The production contracts use `pragma solidity 0.8.34` (released Feb 18, 2026). Foundry stable (v1.5.1, Dec 2025) and nightly (v1.6.0-nightly, Mar 2026) both fail to resolve solc 0.8.34 from their built-in version lists. Hardhat compiles fine because it downloads solc binaries independently.

**Verified workaround:** Hardhat caches the solc 0.8.34 binary at:
```
~/.cache/hardhat-nodejs/compilers-v2/linux-amd64/solc-linux-amd64-v0.8.34+commit.80d5c536
```

Forge accepts this binary via the `solc` config option in `foundry.toml`:
```toml
solc = "/home/zak/.cache/hardhat-nodejs/compilers-v2/linux-amd64/solc-linux-amd64-v0.8.34+commit.80d5c536"
auto_detect_solc = false
```

**Additional requirement:** All fuzz test files must use `pragma solidity ^0.8.26` (caret range), NOT `0.8.26` (exact). The existing 3 fuzz tests in `test/fuzz/` use exact `0.8.26` and will fail under the forced 0.8.34 compiler. This is a one-line fix per file.

**Confidence:** HIGH -- verified locally that `forge build --use <path>` compiles 0.8.34 contracts successfully when test files use caret pragmas.

---

## Existing Foundry Setup (Already in Place)

The project already has a partial Foundry setup. DO NOT reinstall or reconfigure from scratch.

| Component | Current State | Action Needed |
|-----------|--------------|---------------|
| `foundry.toml` | Exists, basic config | Update solc path + invariant config |
| `lib/forge-std` | v1.15.0 (latest tag) | None -- already current |
| `test/fuzz/` | 3 property-based fuzz tests | Extend with invariant harnesses |
| `forge-out/` | Build output directory | Already configured |
| Remappings | `@openzeppelin/=node_modules/@openzeppelin/` | Already correct |

### Existing Fuzz Tests (preserve, do not rewrite)

| File | What It Tests | Pattern |
|------|---------------|---------|
| `BurnieCoinInvariants.t.sol` | ERC20 supply math (mint/burn/transfer/vault) | Standalone mock `MockBurnieSupply`, no real contracts |
| `PriceLookupInvariants.t.sol` | Price curve: bounded, deterministic, cyclic, monotonic | Direct library import of `PriceLookupLib` |
| `ShareMathInvariants.t.sol` | Vault/Stonk `(reserve * amount) / supply` formula | Standalone math, no contract dependencies |

These use standalone mocks because `ContractAddresses.sol` uses compile-time `address(0)` constants, making real contract deployment in Forge impossible without the Hardhat nonce-prediction + patching pipeline. New invariant harnesses follow the same pattern.

---

## Recommended Stack

### Core Tools (Already Installed)

| Technology | Version | Purpose | Status |
|------------|---------|---------|--------|
| Foundry (forge) | 1.5.1-stable (Dec 2025) | Invariant fuzzer, property testing | Installed, needs solc config update |
| forge-std | 1.15.0 | Test utilities, cheatcodes, `bound()`, `CommonBase`, `StdCheats`, `StdUtils` | Installed at `lib/forge-std`, current |
| Hardhat | 2.28.6 | Existing test suite (884 tests) | DO NOT TOUCH |

### No Additional Libraries Needed

The project does NOT need:
- `solmate` -- not testing ERC implementations, testing protocol invariants
- `openzeppelin-contracts` for Forge -- already available via `node_modules` remapping
- `PRBMath` -- protocol uses its own math; testing existing math, not adding new
- `halmos` -- symbolic execution is overkill for this scope; protocol math was formally verified in v1.0/v2.0
- `echidna` / `medusa` -- Foundry invariant testing is sufficient and already set up; adding a second fuzzer adds complexity without proportional value for 5 targeted invariants

---

## Required Configuration Changes

### Updated `foundry.toml`

```toml
[profile.default]
src = "contracts"
test = "test/fuzz"
out = "forge-out"
libs = ["node_modules", "lib"]

# CRITICAL: Use local solc binary because Foundry cannot resolve 0.8.34
solc = "/home/zak/.cache/hardhat-nodejs/compilers-v2/linux-amd64/solc-linux-amd64-v0.8.34+commit.80d5c536"
auto_detect_solc = false
via_ir = true
optimizer = true
optimizer_runs = 2
evm_version = "paris"

remappings = [
    "@openzeppelin/=node_modules/@openzeppelin/",
    "forge-std/=lib/forge-std/src/",
]

# Fuzz testing config (property-based tests -- existing)
[fuzz]
runs = 1000
max_test_rejects = 65536
seed = "0xdeadbeef"

# Invariant testing config (stateful sequence-based tests -- NEW)
[invariant]
runs = 256             # Number of random call sequences
depth = 128            # Calls per sequence (up from 64)
fail_on_revert = false # Handlers bound inputs; some reverts are expected
shrink_run_limit = 5000 # More shrink attempts for complex sequences
show_metrics = true    # Show handler function call breakdown
dictionary_weight = 80 # Favor dictionary values from storage/bytecode
include_storage = true # Seed fuzzer dictionary from contract storage
include_push_bytes = true # Seed from PUSH bytecodes
```

**Key config rationale:**

| Setting | Value | Why |
|---------|-------|-----|
| `depth = 128` | Up from 64 | Protocol has multi-step state machines (purchase -> VRF request -> fulfill -> advance -> game over). 64 may not reach interesting deep states. 128 gives headroom for multi-level game progression. |
| `fail_on_revert = false` | Default behavior | Handler contracts bound inputs, but some paths (VRF not ready, RNG locked) naturally revert. We want the fuzzer to keep exploring, not abort on first revert. |
| `shrink_run_limit = 5000` | Up from 2000 | Complex delegatecall sequences benefit from more shrink attempts to find minimal failing cases. |
| `show_metrics = true` | Off by default | Essential for debugging handler coverage -- shows which functions the fuzzer calls and revert rates per function. |
| `dictionary_weight = 80` | Up from default 40 | Protocol uses many magic numbers (price tiers, quantities, level thresholds). Higher dictionary weight helps fuzzer find meaningful values faster. |
| `auto_detect_solc = false` | Off | Prevents Foundry from trying to download solc 0.8.34 (which it cannot resolve). Forces use of the local binary. |

### Pragma Fix for Existing Test Files

Change in all 3 files (`BurnieCoinInvariants.t.sol`, `PriceLookupInvariants.t.sol`, `ShareMathInvariants.t.sol`):

```diff
-pragma solidity 0.8.26;
+pragma solidity ^0.8.26;
```

This allows the files to compile under solc 0.8.34 while remaining compatible with 0.8.26+.

---

## Handler Architecture for Invariant Tests

### The ContractAddresses Problem

`ContractAddresses.sol` compiles all 22 contract addresses as `constant` (compile-time). In source they are `address(0)`. The Hardhat deploy pipeline predicts nonce-based addresses, patches the file, recompiles, and deploys. Forge cannot replicate this without FFI.

**Decision: Use mock-based handlers.** This is the same pattern the existing 3 fuzz tests already use successfully.

### Handler Design Pattern

Handlers wrap mock contracts to govern fuzzer input. The pattern from forge-std:

```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

contract EthSolvencyHandler is CommonBase, StdCheats, StdUtils {
    MockGameAccounting public protocol;

    // Ghost variables -- track aggregate state across calls
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalFees;

    // Actor pool for multi-user testing
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(MockGameAccounting _protocol) {
        protocol = _protocol;
        for (uint256 i = 0; i < 10; i++) {
            actors.push(address(uint160(0x1000 + i)));
        }
    }

    function purchase(uint256 actorSeed, uint256 amount) external useActor(actorSeed) {
        amount = bound(amount, 0.01 ether, 10 ether);
        deal(currentActor, amount);
        protocol.purchase{value: amount}();
        ghost_totalDeposited += amount;
    }

    receive() external payable {}
}
```

**Key handler principles:**
1. **Bound all inputs** with `bound()` to prevent meaningless reverts
2. **Track ghost variables** for aggregate invariant assertions (sums, counts, deltas)
3. **Multi-actor support** via `useActor` modifier with `vm.prank`
4. **Skip no-ops** -- if bound produces zero, return early instead of reverting
5. **`targetContract(address(handler))`** in setUp -- CRITICAL to restrict fuzzing to handler only

### Invariant Test Template

```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "./handlers/EthSolvencyHandler.sol";

contract EthSolvencyInvariantTest is Test {
    MockGameAccounting protocol;
    EthSolvencyHandler handler;

    function setUp() public {
        protocol = new MockGameAccounting();
        handler = new EthSolvencyHandler(protocol);
        targetContract(address(handler));
    }

    /// @notice ETH solvency: contract balance >= total claimable
    function invariant_ethSolvency() external view {
        assertGe(
            address(protocol).balance,
            protocol.totalClaimable(),
            "ETH solvency violated"
        );
    }

    /// @notice Conservation: deposits - withdrawals == contract balance
    function invariant_conservation() external view {
        assertEq(
            handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn(),
            address(protocol).balance,
            "Conservation violated"
        );
    }
}
```

---

## File Organization

```
test/fuzz/
  # Existing (update pragma only)
  BurnieCoinInvariants.t.sol
  PriceLookupInvariants.t.sol
  ShareMathInvariants.t.sol

  # NEW: Invariant test suites
  EthSolvencyInvariants.t.sol       # ETH accounting invariant
  TicketQueueInvariants.t.sol       # Ticket queue state machine
  VaultSharesInvariants.t.sol       # Vault share math invariant
  GameFsmInvariants.t.sol           # Game FSM transition invariant
  BurnieSupplyInvariants.t.sol      # BurnieCoin supply conservation (stateful)

  # NEW: Handler contracts
  handlers/
    EthSolvencyHandler.sol
    TicketQueueHandler.sol
    VaultSharesHandler.sol
    GameFsmHandler.sol
    BurnieSupplyHandler.sol

  # NEW: Mock contracts for handlers
  mocks/
    MockGameAccounting.sol          # Simplified ETH flow model
    MockTicketQueue.sol             # Level/ticket state machine
    MockVaultAccounting.sol         # Vault deposit/burn/refill model
    MockGameFsm.sol                 # PURCHASE/JACKPOT/GAMEOVER FSM
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Fuzzer | Foundry invariant | Echidna | Already have Foundry setup; Echidna requires Haskell toolchain; Foundry invariant testing is mature since v1.0 |
| Fuzzer | Foundry invariant | Medusa | Medusa is powerful but adds Go dependency; 5 targeted invariants do not justify second fuzzer |
| Deploy strategy | Mock handlers | FFI full deploy | ContractAddresses blocker; FFI is slow and fragile; mocks are sufficient for invariant properties |
| Deploy strategy | Mock handlers | hardhat-foundry plugin | Plugin syncs artifacts but does not help with compile-time address constants |
| Symbolic | Skip | Halmos | Protocol math already verified in v1.0/v2.0; fuzzing finds sequence-dependent bugs that symbolic execution misses |
| Coverage | forge coverage | - | Run after invariant tests to verify handler coverage; no additional tool needed |

---

## What NOT to Add

| Avoid | Why |
|-------|-----|
| `@nomicfoundation/hardhat-foundry` plugin | Does not solve `ContractAddresses.sol` compile-time constant problem. Separate `forge-out` directory already works. |
| Migrating Hardhat tests to Foundry | 884 tests work. Foundry is additive for invariant/fuzz testing only. |
| `forge script` for deployment | Nonce-prediction + patching pipeline is Hardhat-specific. |
| `forge snapshot` | Gas optimization is out of scope for security milestone. |
| Echidna / Medusa alongside Foundry | Diminishing returns for 5 targeted invariants. Use Foundry exclusively. |
| Halmos | Math properties already verified. FSM state machine would hit path explosion. |

---

## Setup Commands

```bash
# 1. Update foundry.toml (see config above)
# Key changes: solc path, auto_detect_solc=false, invariant section

# 2. Fix existing fuzz test pragmas
sed -i 's/pragma solidity 0.8.26;/pragma solidity ^0.8.26;/' test/fuzz/*.t.sol

# 3. Verify build works
forge build --force

# 4. Run existing fuzz tests
forge test --match-path "test/fuzz/*.t.sol" -vv

# 5. Run invariant tests specifically (after they are written)
forge test --match-path "test/fuzz/*Invariants.t.sol" -vv

# 6. Run with full metrics for handler debugging
forge test --match-path "test/fuzz/*Invariants.t.sol" -vvvv
```

---

## Confidence Assessment

| Item | Confidence | Rationale |
|------|------------|-----------|
| Foundry 1.5.1 + forge-std 1.15.0 | HIGH | Already installed, verified working for fuzz tests |
| Local solc 0.8.34 workaround | HIGH | Verified locally -- forge compiles 0.8.34 contracts with `--use <path>` |
| Caret pragma fix for test files | HIGH | Standard Solidity pragma semantics, trivial change |
| Mock handler pattern | HIGH | 3 existing tests validate the pattern; ContractAddresses blocker is real |
| Invariant config values | MEDIUM | Reasonable for protocol complexity but may need tuning after first runs |
| No additional libraries needed | HIGH | forge-std 1.15.0 covers all handler/cheatcode needs |
| `depth=128` sufficient | MEDIUM | May need 256 for deep FSM exploration; start at 128 and increase if metrics show shallow coverage |

---

## Sources

- [Foundry Invariant Testing docs](https://getfoundry.sh/forge/invariant-testing) -- handler patterns, targetContract, ghost variables
- [Foundry Config Reference: Testing](https://getfoundry.sh/reference/config/testing) -- all [invariant] config options
- [Foundry Config Reference: Solidity Compiler](https://www.getfoundry.sh/config/reference/solidity-compiler) -- `solc` path, `auto_detect_solc`
- [horsefacts/weth-invariant-testing](https://github.com/horsefacts/weth-invariant-testing) -- canonical handler pattern example
- [RareSkills Invariant Testing Guide](https://rareskills.io/post/invariant-testing-solidity) -- ghost variables, multi-actor patterns
- [Cyfrin Invariant Testing Guide](https://medium.com/cyfrin/invariant-testing-enter-the-matrix-c71363dea37e) -- handler design principles
- [Solidity 0.8.34 Release](https://www.soliditylang.org/blog/2026/02/18/solidity-0.8.34-release-announcement/) -- confirms release date Feb 18, 2026
- [forge-std releases](https://github.com/foundry-rs/forge-std/releases) -- v1.15.0 is latest
- Local verification: `forge build --use <solc-0.8.34-path>` confirmed working on this project

---

*Stack research for: Degenerus Protocol v3.0 -- Invariant Fuzzing and Blind Adversarial Hardening*
*Researched: 2026-03-05*
