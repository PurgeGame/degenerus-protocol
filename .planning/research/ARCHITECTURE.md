# Architecture Patterns

**Domain:** Foundry invariant fuzzing harnesses for delegatecall-based multi-contract protocol
**Researched:** 2026-03-05

## Recommended Architecture

### The Central Challenge: Compile-Time Address Constants

The Degenerus protocol uses `ContractAddresses.sol` with `internal constant` addresses. These are **not** storage variables and **not** immutables -- they are compile-time constants inlined directly into the bytecode of every contract that imports them. This means:

1. You cannot use `vm.store()` to change them (they are not in storage slots).
2. You cannot change them per-contract after deployment.
3. Every contract that references `ContractAddresses.GAME`, `ContractAddresses.COIN`, etc. has those addresses baked into its compiled bytecode.

**The existing Hardhat test suite solves this** with `patchContractAddresses.js`: predict nonce-based addresses, regex-replace the constants in the Solidity source, recompile, then deploy. The addresses match because the nonce prediction is deterministic.

**For Foundry invariant tests, use the same patch-compile-deploy strategy.** The project already has the infrastructure; Foundry just needs a thin wrapper.

### Strategy: Shared Patch-Compile Pipeline (Recommended)

The existing `patchContractAddresses.js` and `predictAddresses.js` work for both Hardhat and Foundry because both compile the same `contracts/` source directory. The approach:

1. **Create `scripts/lib/patchForFoundry.js`** that predicts addresses using Foundry's deployer address and nonce sequence within `setUp()`, then calls the existing `patchContractAddresses()` function.
2. **Write `DeployProtocol.sol`** (abstract Solidity contract) that deploys all 22 contracts in DEPLOY_ORDER within `setUp()`. Because Foundry's test EVM is deterministic, the deployer address and starting nonce are known, making address prediction reliable.
3. **Use a Makefile target** that: runs the patch script, runs `forge build`, runs `forge test`, then restores ContractAddresses.sol.

```makefile
invariant-test:
	node scripts/lib/patchForFoundry.js
	forge build --force
	forge test --match-path "test/fuzz/**" -vvv
	node -e "import('./scripts/lib/patchContractAddresses.js').then(m => m.restoreContractAddresses())"
```

This mirrors the Hardhat pattern exactly. Both test suites share the same patched source, compiled once.

**Why not `vm.etch`?** The `vm.etch` approach (deploy to temp address, copy bytecode to expected address) does not transfer constructor-time storage writes. With 22 contracts that perform constructor-time wiring (ADMIN calls `GAME.wireVrf()`, VAULT calls `COIN.vaultMintAllowance()`, DGNRS calls `GAME.claimWhalePass()`), vm.etch would produce a broken protocol with missing state. The patch-compile approach is the only reliable strategy for this architecture.

### Component Diagram

```
                    Foundry Test Runner (forge test)
                          |
              +-----------+-----------+
              |                       |
    Invariant Test Suite        Stateless Fuzz Tests
    (test/fuzz/invariant/)     (test/fuzz/*.t.sol)
       [NEW]                     [existing: 3 files]
              |
    +----+----+----+----+----+
    |    |    |    |    |    |
   ETH  COIN  FSM VAULT QUEUE    <-- Invariant Harnesses (5 test contracts)
    |    |    |    |    |
    +----+----+----+----+
              |
        Handler Contracts         <-- Action wrappers with ghost variables
    (GameHandler, VRFHandler,
     WhaleHandler, CoinHandler)
              |
        DeployProtocol.sol        <-- Shared setUp() base (abstract contract)
              |
    +----+----+----+----+
    |    |    |    |    |
  GAME COIN VAULT VRF  ...       <-- Real contracts (compiled with patched addresses)
         MOCKS
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `DeployProtocol.sol` | Deploy all 22 contracts + 5 mocks in Foundry setUp() | All contracts, mocks |
| `GameHandler.sol` | Wrap purchase/advance/claim actions, track ETH ghost vars | DegenerusGame, actors |
| `VRFHandler.sol` | Simulate VRF request/fulfill lifecycle, time warping | MockVRFCoordinator, DegenerusGame |
| `WhaleHandler.sol` | Wrap whale bundle/lazy/deity pass purchases | DegenerusGame, actors |
| `CoinHandler.sol` | Wrap BURNIE mint/burn/transfer/coinflip actions | BurnieCoin, BurnieCoinflip |
| `ActorManager.sol` | Shared actor set, selection modifier, ETH funding | All handlers |
| `EthSolvency.inv.t.sol` | Assert `address(game).balance + steth.balanceOf(game) >= claimablePool` | All handlers |
| `CoinSupply.inv.t.sol` | Assert BURNIE `totalSupply + vaultAllowance == constant` | CoinHandler |
| `GameFSM.inv.t.sol` | Assert valid state transitions, no illegal phase changes | GameHandler, VRFHandler |
| `VaultShares.inv.t.sol` | Assert vault share math: `totalShares * price >= deposits` | DegenerusVault |
| `TicketQueue.inv.t.sol` | Assert queue ordering, cursor bounds, no corruption | GameHandler |

### Data Flow: Invariant Test Execution

```
1. Pre-build: patchForFoundry.js
   -> Computes Foundry deployer address + nonce sequence
   -> Calls patchContractAddresses(predicted, external, dayBoundary, keyHash)
   -> forge build compiles contracts with correct inlined addresses

2. setUp() calls DeployProtocol._deployProtocol()
   -> Deploys 5 mocks (VRF, stETH, LINK, wXRP, LinkEthFeed)
   -> Deploys 22 protocol contracts in DEPLOY_ORDER
   -> Wires VRF subscription (createSubscription, addConsumer, wireVrf)
   -> Creates handler contracts pointing at deployed protocol
   -> Registers handlers as targetContracts via targetContract()

3. Foundry fuzzer selects random handler function with random inputs
   -> Handler bounds inputs to valid ranges (bound())
   -> Handler selects actor via useActor modifier (vm.prank)
   -> Handler calls protocol function
   -> Handler updates ghost variables on success
   -> try/catch swallows expected reverts

4. After EACH call, all invariant_*() functions assert:
   -> ETH solvency: balance >= claimable pool
   -> BURNIE conservation: totalSupply + vaultAllowance == initial
   -> FSM validity: no illegal transitions occurred
   -> Vault correctness: shares * price >= deposits
   -> Queue bounds: cursors within array lengths

5. Repeat steps 3-4 for [depth] calls per [run] (256 runs x 64 depth default)
```

## Handler Contract Architecture for Delegatecall Protocols

### The Delegatecall Transparency Principle

DegenerusGame uses delegatecall to 10 modules (MintModule, AdvanceModule, JackpotModule, WhaleModule, EndgameModule, GameOverModule, LootboxModule, BoonModule, DecimatorModule, DegeneretteModule). But **handlers should not care about this internal routing**. From the external API, all functions are called on DegenerusGame. The delegatecall is transparent.

Handlers call `game.purchase(...)`, `game.advanceGame()`, `game.claimWinnings(...)` -- they never call modules directly. Calling a module at its standalone address would give it its own empty storage, producing meaningless results.

### Handler Pattern: GameHandler

The canonical handler pattern (based on the horsefacts WETH invariant testing approach) uses ghost variables for accounting, bounded inputs for coverage, and actor management for multi-user simulation.

```solidity
// test/fuzz/handlers/GameHandler.sol
contract GameHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // Ghost variables for ETH solvency invariant
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalClaimed;

    // Ghost variables for ticket tracking
    uint256 public ghost_ticketsPurchased;

    // Actor management
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    // Call counting for coverage analysis
    mapping(string => uint256) public calls;
    modifier countCall(string memory name) {
        calls[name]++;
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xA0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) countCall("purchase") {
        // Bound to valid ticket quantities (0.25 to 10 tickets)
        qty = bound(qty, 100, 4000);
        lootboxAmt = bound(lootboxAmt, 0, 5);

        // Query current price to compute cost
        (, , , uint256 priceWei, , , ) = game.purchaseInfo();
        uint256 costWei = (priceWei * qty) / 400;
        if (costWei == 0 || costWei > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: costWei}(
            currentActor, uint16(qty), uint16(lootboxAmt), 0,
            MintPaymentKind.DirectEth
        ) {
            ghost_totalDeposited += costWei;
            ghost_ticketsPurchased += qty;
        } catch {}
    }

    function advanceGame(uint256 actorSeed)
        external useActor(actorSeed) countCall("advanceGame")
    {
        vm.prank(currentActor);
        try game.advanceGame() {} catch {}
    }

    function claimWinnings(uint256 actorSeed)
        external useActor(actorSeed) countCall("claimWinnings")
    {
        uint256 balBefore = currentActor.balance;
        vm.prank(currentActor);
        try game.claimWinnings(currentActor) {
            ghost_totalClaimed += currentActor.balance - balBefore;
        } catch {}
    }
}
```

### VRF Handler: Simulating Callbacks in Invariant Runs

The VRF lifecycle is the most critical handler challenge. The game state machine follows: `advanceGame() -> requestRandomWords() -> [wait] -> rawFulfillRandomWords() -> advanceGame()`. Without a VRFHandler, the fuzzer never fulfills VRF requests, and the game gets permanently stuck in RNG-locked state after the first advance.

The existing `MockVRFCoordinator.sol` already has `fulfillRandomWords(requestId, randomWord)` and `lastRequestId()`. The VRFHandler wraps these for the fuzzer:

```solidity
// test/fuzz/handlers/VRFHandler.sol
contract VRFHandler is Test {
    MockVRFCoordinator public vrf;
    DegenerusGame public game;

    uint256 public ghost_vrfFulfillments;

    constructor(MockVRFCoordinator vrf_, DegenerusGame game_) {
        vrf = vrf_;
        game = game_;
    }

    /// @notice Fulfill the most recent pending VRF request.
    /// @dev The fuzzer calls this to simulate Chainlink delivering randomness.
    function fulfillVrf(uint256 randomWord) external {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {
            ghost_vrfFulfillments++;
        } catch {}
    }

    /// @notice Advance time past VRF timeout so retry path is reachable.
    function warpPastVrfTimeout() external {
        vm.warp(block.timestamp + 18 hours + 1);
    }

    /// @notice Advance time by a bounded delta for general time-dependent logic.
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
    }
}
```

**Design rationale for separate VRFHandler:**
- If VRF fulfillment were inside GameHandler, it would share the fuzzing budget with purchase/advance/claim. With 4 functions in GameHandler, VRF fulfill gets ~25% of calls -- but it only needs to fire after an advance that requests RNG.
- A separate VRFHandler as a targetContract means the fuzzer independently decides when to fulfill. This naturally creates realistic interleaving: purchase -> advance -> [VRF fulfill] -> advance -> purchase.
- Time warping (`warpTime`, `warpPastVrfTimeout`) belongs in VRFHandler because VRF timeout is the primary time-sensitive mechanic.

### WhaleHandler

Whale mechanics (bundles at 2.4 ETH, lazy passes at 0.24 ETH, deity passes at 24 + T(n) ETH) have distinct pricing and represent high-value attack vectors. A separate handler ensures the fuzzer exercises these less-common code paths with appropriate frequency:

```solidity
contract WhaleHandler is Test {
    DegenerusGame public game;
    address[] public actors;
    address internal currentActor;
    uint256 public ghost_whaleBundleSpend;
    uint256 public ghost_deityPassSpend;

    // Similar actor management as GameHandler...

    function purchaseWhaleBundle(uint256 actorSeed, uint256 qty)
        external useActor(actorSeed)
    {
        qty = bound(qty, 1, 10); // 1-10 bundles
        uint256 cost = 2.4 ether * qty;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseWhaleBundle{value: cost}(currentActor, uint16(qty)) {
            ghost_whaleBundleSpend += cost;
        } catch {}
    }

    function purchaseLazyPass(uint256 actorSeed) external useActor(actorSeed) {
        uint256 cost = 0.24 ether;
        if (cost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchaseLazyPass{value: cost}(currentActor) {} catch {}
    }
}
```

## Invariant Test Contract Structure

Each invariant test contract inherits `DeployProtocol`, sets up handlers in `setUp()`, registers them as target contracts, and defines `invariant_*` functions:

```solidity
// test/fuzz/invariant/EthSolvency.inv.t.sol
contract EthSolvencyInvariant is DeployProtocol {
    GameHandler public gameHandler;
    VRFHandler public vrfHandler;
    WhaleHandler public whaleHandler;

    function setUp() public {
        _deployProtocol();

        gameHandler = new GameHandler(game, vrfCoord, 10);
        vrfHandler = new VRFHandler(vrfCoord, game);
        whaleHandler = new WhaleHandler(game, 5);

        targetContract(address(gameHandler));
        targetContract(address(vrfHandler));
        targetContract(address(whaleHandler));
    }

    /// @notice ETH solvency: game balance >= claimable pool always
    function invariant_ethSolvency() public view {
        uint256 gameBalance = address(game).balance;
        uint256 stethBalance = steth.balanceOf(address(game));
        uint256 claimablePool = game.claimablePool();
        assertGe(
            gameBalance + stethBalance,
            claimablePool,
            "ETH solvency violated: balance < claimable"
        );
    }

    /// @notice Ghost accounting: deposits >= claims + current balance change
    function invariant_ghostAccounting() public view {
        uint256 totalIn = gameHandler.ghost_totalDeposited()
            + whaleHandler.ghost_whaleBundleSpend()
            + whaleHandler.ghost_deityPassSpend();
        uint256 totalOut = gameHandler.ghost_totalClaimed();
        // Total deposited must be >= total claimed
        assertGe(totalIn, totalOut, "More ETH claimed than deposited");
    }
}
```

## Integration: Foundry + Hardhat Coexistence

### Current State

The project already has a working hybrid setup:

| Concern | Hardhat | Foundry |
|---------|---------|---------|
| Source directory | `contracts/` | `contracts/` (same) |
| Test directory | `test/` (JS, 884 tests) | `test/fuzz/` (Solidity, 3 files) |
| Build output | `artifacts/` | `forge-out/` |
| Dependencies | `node_modules/` (OpenZeppelin) | `lib/` (forge-std) + `node_modules/` remapped |
| Compiler | 0.8.26, viaIR, optimizer 2 | 0.8.26, viaIR, optimizer 2 (matched) |
| VRF mock | `contracts/mocks/MockVRFCoordinator.sol` | Same file (shared) |

Both frameworks compile the same source. The `foundry.toml` already has correct remappings for OpenZeppelin and matching compiler settings. No changes needed to the existing configuration.

### Directory Structure

```
test/fuzz/
  BurnieCoinInvariants.t.sol       # [existing] Stateless fuzz - supply math
  PriceLookupInvariants.t.sol      # [existing] Stateless fuzz - price bounds
  ShareMathInvariants.t.sol        # [existing] Stateless fuzz - vault shares
  invariant/                        # [NEW] Stateful invariant harnesses
    EthSolvency.inv.t.sol           #   ETH balance >= claimable pool
    CoinSupply.inv.t.sol            #   BURNIE supply conservation
    GameFSM.inv.t.sol               #   Valid state machine transitions
    VaultShares.inv.t.sol           #   Vault share math correctness
    TicketQueue.inv.t.sol           #   Queue ordering and cursor bounds
  handlers/                         # [NEW] Handler contracts
    GameHandler.sol                 #   Purchase/advance/claim wrappers
    VRFHandler.sol                  #   VRF fulfill + time warp
    WhaleHandler.sol                #   Whale bundle/lazy/deity pass
    CoinHandler.sol                 #   BURNIE token operations
    ActorManager.sol                #   Shared actor utilities
  helpers/                          # [NEW] Foundry deploy infrastructure
    DeployProtocol.sol              #   Full 22-contract deploy in setUp()
scripts/lib/
    patchForFoundry.js              # [NEW] Address prediction for Foundry deployer
```

### New vs Modified vs Unchanged Components

**New components (12 files):**

| File | Type | Purpose |
|------|------|---------|
| `test/fuzz/helpers/DeployProtocol.sol` | Abstract Solidity contract | Replicate Hardhat deployFixture in pure Solidity |
| `test/fuzz/handlers/GameHandler.sol` | Solidity contract | Purchase/advance/claim with ghost variables |
| `test/fuzz/handlers/VRFHandler.sol` | Solidity contract | VRF fulfill lifecycle + time warping |
| `test/fuzz/handlers/WhaleHandler.sol` | Solidity contract | Whale bundle/lazy/deity pass actions |
| `test/fuzz/handlers/CoinHandler.sol` | Solidity contract | BURNIE mint/burn/transfer/coinflip |
| `test/fuzz/handlers/ActorManager.sol` | Solidity library | Actor set management, selection modifier |
| `test/fuzz/invariant/EthSolvency.inv.t.sol` | Test contract | ETH solvency invariant |
| `test/fuzz/invariant/CoinSupply.inv.t.sol` | Test contract | BURNIE supply invariant |
| `test/fuzz/invariant/GameFSM.inv.t.sol` | Test contract | State machine invariant |
| `test/fuzz/invariant/VaultShares.inv.t.sol` | Test contract | Vault math invariant |
| `test/fuzz/invariant/TicketQueue.inv.t.sol` | Test contract | Queue ordering invariant |
| `scripts/lib/patchForFoundry.js` | Node.js script | Address prediction + patch for Foundry |

**Modified components (1 file):**

| File | Change | Why |
|------|--------|-----|
| `Makefile` or `package.json` | Add `invariant-test` target | Automate patch-build-test-restore pipeline |

**Unchanged components:**

| Component | Why No Change |
|-----------|---------------|
| All 22 production contracts | Testing as-is, no modifications |
| All 10 delegatecall modules | Tested indirectly through DegenerusGame |
| `contracts/mocks/*.sol` | MockVRFCoordinator already has required test helpers |
| `test/fuzz/*.t.sol` (3 existing) | Stateless fuzz tests unaffected |
| `test/` (Hardhat, 884 tests) | Completely independent |
| `foundry.toml` | Current config is sufficient |

## Patterns to Follow

### Pattern 1: Bounded Handler Inputs

**What:** Every handler function must `bound()` all fuzzed parameters to valid ranges before calling the protocol.
**When:** Always. Without bounding, 99%+ of fuzz calls revert with `fail_on_revert = false`, wasting the invariant test budget on no-ops.
**Why critical here:** DegenerusGame has strict input validation (ticket qty must be multiple of 100, price depends on level, whale bundles require specific ETH amounts). Unbounded inputs almost never produce valid calls.

### Pattern 2: Ghost Variable Double-Entry Accounting

**What:** Track cumulative ETH flows in handler ghost variables. Every deposit increments `ghost_totalDeposited`, every claim increments `ghost_totalClaimed`. Invariants assert `ghost_totalDeposited >= ghost_totalClaimed`.
**When:** For every invariant that checks ETH solvency or token supply conservation.
**Warning:** Ghost variables must faithfully mirror the protocol's accounting. If the ghost logic has a bug that matches a protocol bug, the invariant test gives a false pass. Keep ghost logic trivially simple (just accumulate amounts).

### Pattern 3: Multi-Handler Target Registration

**What:** Register multiple handlers as `targetContract()`. Each covers a distinct action domain.
**When:** Always for multi-contract protocols. Foundry distributes calls uniformly across all handler functions. Separate handlers ensure each domain gets adequate coverage.

### Pattern 4: VRF as Independent Handler

**What:** VRF fulfillment and time warping live in a separate `VRFHandler`, registered as its own targetContract.
**When:** Any protocol with async callbacks (VRF, oracle updates, keeper triggers).
**Why:** The fuzzer independently decides when to fulfill VRF requests, naturally creating realistic interleaving of game actions and oracle responses. If VRF fulfill were buried inside GameHandler, it would compete with purchase/advance/claim for call budget.

### Pattern 5: Graceful Skip on Impossible State

**What:** Handlers check preconditions and `return` early instead of letting calls revert.
**When:** When protocol state makes a call impossible (actor has no balance, game is over, RNG is locked).
**Why:** Even with `fail_on_revert = false`, reverts waste gas and depth budget. Early returns let the fuzzer try another function instead.

```solidity
function purchase(...) external {
    uint256 cost = ...;
    if (cost > currentActor.balance) return; // Skip, don't revert
    if (game.gameOver()) return;             // Skip, game is done
    // ... proceed
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Testing Modules Directly

**What:** Creating handlers that call delegatecall modules at their standalone addresses.
**Why bad:** Modules execute in DegenerusGame's storage context via delegatecall. Calling a module directly gives it its own (empty) storage, producing meaningless test results. MintModule at its own address has no ticket queue, no price state, no pools.
**Instead:** Always call through DegenerusGame's external functions. The delegatecall routing is an internal implementation detail.

### Anti-Pattern 2: Using vm.etch for Full Protocol Deployment

**What:** Deploy contracts normally, then `vm.etch` their bytecode to ContractAddresses constants.
**Why bad:** Constructor side effects (storage writes, cross-contract calls) happen at the temporary address. State does not transfer with `vm.etch`. For this protocol, ADMIN's constructor calls `GAME.wireVrf()`, VAULT calls `COIN.vaultMintAllowance()`, DGNRS calls `GAME.claimWhalePass()` -- all of which write state that would be lost.
**Instead:** Use patch-compile-deploy (Strategy A) where addresses are correct at compile time.

### Anti-Pattern 3: Single Monolithic Handler

**What:** One handler with all 30+ protocol functions.
**Why bad:** Foundry distributes calls uniformly. With 30 functions, each gets ~3% of the budget. Rare but critical actions (VRF fulfill, deity pass, game over drain) never get enough coverage.
**Instead:** 4-5 focused handlers. The fuzzer picks a handler, then a function within it, giving each domain roughly equal coverage.

### Anti-Pattern 4: Omitting VRF Fulfillment Handler

**What:** Only testing purchase flows without VRF callbacks.
**Why bad:** The game gets stuck in RNG-locked state after the first `advanceGame()`. All subsequent advances revert with `RngNotReady`. The fuzzer only ever exercises the purchase phase, missing jackpot distribution, level transitions, endgame, and game over.
**Instead:** Dedicated VRFHandler that the fuzzer calls to fulfill pending requests and advance the state machine.

### Anti-Pattern 5: Overly Restrictive Input Bounds

**What:** Bounding inputs so tightly that only "happy path" scenarios are tested.
**Why bad:** Invariant tests should find edge cases. If qty is always exactly 400 (one full ticket), you miss boundary behavior at qty=100 (minimum) or qty=4000 (10 tickets).
**Instead:** Bound to the full valid range. Let the fuzzer explore the extremes.

## Scalability Considerations

| Concern | Initial (5 invariants) | Production (10+ invariants) | Mitigation |
|---------|------------------------|----------------------------|------------|
| Compile time | ~45s (viaIR, 22 contracts) | Same (same contracts) | Cache `forge-out/` in CI |
| Test runtime | ~3min (256 runs x 64 depth) | ~8min (more assertions per call) | Parallelize invariant files |
| Address patching | Once per build | Once per build | Makefile automates patch/restore |
| Handler gas per call | ~200K avg | Same | Bound inputs to reduce wasted gas |
| Ghost variable storage | Negligible (6-10 uint256s) | Negligible | N/A |

### Foundry Configuration (already in foundry.toml)

```toml
[invariant]
runs = 256        # Sequences to generate
depth = 64        # Calls per sequence
fail_on_revert = false  # Expected: bounded handlers still hit some reverts
```

For CI hardening, consider increasing:
```toml
runs = 1024
depth = 128
```

## Build Order

Considering the ContractAddresses challenge and dependencies between components:

### Phase 1: Deploy Infrastructure (must be first)

1. **`patchForFoundry.js`** -- Predict addresses for Foundry's deployer, call existing patch function.
2. **`DeployProtocol.sol`** -- Translate `deployFixture.js` to Solidity. Deploy mocks, then 22 contracts in DEPLOY_ORDER, wire VRF.
3. **Validate**: Write a minimal test that deploys and asserts all addresses match ContractAddresses constants.

This is the hardest piece. Until addresses are correct, nothing else works.

### Phase 2: First Invariant + Core Handler (validates infrastructure)

4. **`ActorManager.sol`** -- Shared actor creation and selection.
5. **`GameHandler.sol`** -- Purchase + advance + claim with ghost ETH tracking.
6. **`VRFHandler.sol`** -- VRF fulfill + time warp (required for state machine progression).
7. **`EthSolvency.inv.t.sol`** -- The most critical invariant: `balance >= claimablePool`.

This validates the entire pipeline end-to-end: patch -> compile -> deploy -> fuzz -> assert.

### Phase 3: Remaining Handlers

8. **`WhaleHandler.sol`** -- Whale bundle, lazy pass, deity pass.
9. **`CoinHandler.sol`** -- BURNIE operations.

### Phase 4: Remaining Invariants

10. **`CoinSupply.inv.t.sol`** -- BURNIE supply conservation.
11. **`GameFSM.inv.t.sol`** -- State machine transitions.
12. **`VaultShares.inv.t.sol`** -- Vault share math.
13. **`TicketQueue.inv.t.sol`** -- Queue ordering and cursor bounds.

### Phase 5: Tuning and Hardening

14. Adjust `bound()` ranges based on coverage analysis.
15. Add `targetSelector()` weighting if critical functions are under-covered.
16. Increase runs/depth for CI.

## Sources

- [Foundry Invariant Testing Documentation](https://getfoundry.sh/forge/invariant-testing) -- HIGH confidence, official docs
- [horsefacts WETH Invariant Testing (GitHub)](https://github.com/horsefacts/weth-invariant-testing) -- HIGH confidence, canonical handler pattern
- [Cyfrin: Invariant Testing -- Enter the Matrix](https://medium.com/cyfrin/invariant-testing-enter-the-matrix-c71363dea37e) -- MEDIUM confidence, pattern guide
- [RareSkills: Invariant Testing in Foundry](https://rareskills.io/post/invariant-testing-solidity) -- MEDIUM confidence, educational
- [ThreeSigma: Foundry Cheatcodes Invariant Testing](https://threesigma.xyz/blog/foundry/foundry-cheatcodes-invariant-testing) -- MEDIUM confidence
- [Hardhat + Foundry Integration](https://v2.hardhat.org/hardhat-runner/docs/advanced/hardhat-and-foundry) -- HIGH confidence, official docs
- [vm.etch setUp issue (resolved)](https://github.com/foundry-rs/foundry/issues/4707) -- HIGH confidence, confirmed fixed
- Existing project files: `foundry.toml`, `ContractAddresses.sol`, `patchContractAddresses.js`, `deployFixture.js`, `MockVRFCoordinator.sol`, `BurnieCoinInvariants.t.sol`, `DegenerusGame.sol`, `DegenerusGameStorage.sol` -- HIGH confidence, direct source inspection
