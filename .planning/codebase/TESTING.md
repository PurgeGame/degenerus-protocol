# Testing Patterns

**Analysis Date:** 2026-02-28

## Test Framework

### Runner

**Framework:** Mocha
- Configured in `hardhat.config.js`: timeout = 120,000ms (2 minutes per test)
- Run command: `npm test` (runs all test suites)
- Runs through Hardhat's integrated Mocha runner

### Assertion Library

**Library:** Chai with extended matchers from `@nomicfoundation/hardhat-chai-matchers`

**Key assertion methods:**
- `.to.equal(value)` - Equality check
- `.to.be.true` / `.to.be.false` - Boolean assertions
- `.to.be.gt(value)` / `.to.be.lt(value)` - Comparison operators
- `.to.be.reverted` - Generic revert check
- `.to.be.revertedWithCustomError(contract, "ErrorName")` - Custom error matching
- `.to.not.be.reverted` - Expect success

**Example:**
```javascript
expect(await game.level()).to.equal(0n);
expect(await game.jackpotPhase()).to.be.false;
await expect(
    game.connect(alice).setOperatorApproval(ZERO_ADDRESS, true)
).to.be.reverted;
```

### Run Commands

```bash
npm test                              # Run all tests (unit, integration, deploy, access, edge, simulation, adversarial)
npm test:unit                         # Run unit tests only
npm test:integration                  # Run integration tests only
npm test:deploy                       # Run deployment script tests
npm test:access                       # Run access control tests
npm test:edge                         # Run edge case tests
npm test:adversarial                  # Run adversarial tests
RUN_SEPOLIA_ACTOR_TESTS=1 npm test    # Run Sepolia-specific adversarial tests
```

**Current status (as of test run):**
- 907 passing tests
- 3 failing tests
- ~37s total runtime
- Gas profiling enabled (hardhat-gas-reporter in toolbox)

## Test File Organization

### Location

**Pattern:** Co-located with test category.

**Structure:**
```
test/
├── unit/                    # Unit tests for individual contracts
│   ├── DegenerusGame.test.js
│   ├── BurnieCoin.test.js
│   ├── DegenerusAdmin.test.js
│   └── ... (12 contracts)
├── integration/             # Integration tests for multi-contract flows
│   ├── GameLifecycle.test.js
│   └── VRFIntegration.test.js
├── deploy/                  # Deployment script tests
│   └── DeployScript.test.js
├── access/                  # Access control tests
│   └── AccessControl.test.js
├── edge/                    # Edge case and boundary condition tests
│   ├── GameOver.test.js
│   ├── RngStall.test.js
│   ├── WhaleBundle.test.js
│   └── PriceEscalation.test.js
├── simulation/              # Simulation and scenario tests
│   ├── simulation-2-levels.test.js
│   ├── simulation-5-levels.test.js
│   └── generate-ui-db.test.js
├── adversarial/             # Adversarial/economic attack tests
│   ├── TechnicalAdversarial.test.js
│   ├── EconomicAdversarial.test.js
│   └── SepoliaActorAdversarial.test.js
├── gas/                     # Gas profiling tests
│   └── AdvanceGameGas.test.js
└── helpers/                 # Test utilities (NOT test suites)
    ├── deployFixture.js     # Full protocol deployment fixture
    └── testUtils.js         # Helper functions (eth, events, time, etc.)
```

### Naming

**Pattern:** `{ContractName}.test.js` for unit tests, descriptive names for integration/edge/simulation tests.

**Examples:**
- `DegenerusGame.test.js` - Tests the DegenerusGame contract
- `GameLifecycle.test.js` - Integration test for full game cycle
- `RngStall.test.js` - Edge case tests for RNG stall scenarios
- `AccessControl.test.js` - Systematic access control verification

### File Structure

**Pattern:** describe blocks organized by feature/function group, with setup/teardown hooks.

**Example structure from DegenerusGame.test.js:**
```javascript
describe("DegenerusGame", function () {
  after(() => restoreAddresses());  // Global cleanup after all tests

  describe("Initial state", function () {
    it("starts at level 0", async function () { ... });
    it("starts in purchase phase", async function () { ... });
  });

  describe("setOperatorApproval", function () {
    it("approves an operator and emits event", async function () { ... });
    it("revokes an operator", async function () { ... });
  });

  describe("purchase (ETH)", function () {
    it("allows purchasing tickets with DirectEth", async function () { ... });
    it("reverts when underpaying", async function () { ... });
  });
});
```

## Test Structure

### Suite Organization

**Describe blocks:**
- Top level: Contract or feature name (e.g., `describe("DegenerusGame", ...)`)
- Sub-levels: Feature groups or test categories (e.g., `describe("Initial state", ...)`)
- Typically 2-3 levels deep

**Test cases (it blocks):**
- Named descriptively with "should/does X" language
- Single responsibility per test
- Synchronous setup; async test body

**Example from BurnieCoin.test.js:**
```javascript
describe("BurnieCoin", function () {
  after(function () {
    restoreAddresses();  // Cleanup after all tests in suite
  });

  async function getFixture() {
    return loadFixture(deployFullProtocol);
  }

  describe("initial state", function () {
    it("name is 'Burnies'", async function () {
      const { coin } = await getFixture();
      expect(await coin.name()).to.equal("Burnies");
    });
  });
});
```

### Patterns

**Setup pattern (Hardhat fixture):**
```javascript
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";

describe("MyContract", function () {
  async function deployTestFixture() {
    return loadFixture(deployFullProtocol);  // Cached between tests in same block
  }

  it("test name", async function () {
    const { game, alice, deployer, mockVRF } = await deployTestFixture();
    // ... test body
  });
});
```

**Teardown pattern:**
- Global `after()` hook in each test file that calls `restoreAddresses()` (cleanup for patch/compile cycle)

**Example from GameLifecycle.test.js:**
```javascript
describe("GameLifecycle", function () {
  after(function () {
    restoreAddresses();  // Restore patched ContractAddresses.sol
  });
});
```

**Assertion pattern:**
```javascript
// Simple assertions
expect(await game.level()).to.equal(0n);

// Custom error assertions (direct contract error):
await expect(
    game.connect(alice).setOperatorApproval(ZERO_ADDRESS, true)
).to.be.revertedWithCustomError(game, "E");

// Delegatecall error assertions (error from module):
await expect(
    game.connect(player).reverseFlip(player.address)
).to.be.revertedWithCustomError(advanceModule, "RngLocked");

// Generic revert (error name not known or not important):
await expect(
    game.connect(deployer).advanceGame()
).to.be.reverted;
```

## Mocking

### Framework

**Framework:** Native Hardhat provider with `hardhat_impersonateAccount`, `hardhat_setBalance`, `evm_*` methods for state manipulation.

**Mock contracts:**
- `MockVRFCoordinator` - Simulates Chainlink VRF with manual `fulfillRandomWords()` call
- `MockStETH` - Simulates Lido stETH token
- `MockLinkToken` - Simulates Chainlink LINK token
- `MockWXRP` - Simulates wrapped XRP
- `MockLinkEthFeed` - Simulates Chainlink price feed (LINK/ETH)

**Mock deployment in deployFixture.js:**
```javascript
const mockVRF = await deploy("MockVRFCoordinator");
const mockStETH = await deploy("MockStETH");
const mockLINK = await deploy("MockLinkToken");
const mockWXRP = await deploy("MockWXRP");
const mockFeed = await deploy("MockLinkEthFeed", [
  hre.ethers.parseEther("0.004"),  // ~0.004 ETH per LINK
]);
```

### Patterns

**VRF fulfillment flow:**
```javascript
// Step 1: Trigger VRF request
await game.connect(deployer).advanceGame();
expect(await game.rngLocked()).to.equal(true);

// Step 2: Get request ID and fulfill
const requestId = await getLastVRFRequestId(mockVRF);
await mockVRF.fulfillRandomWords(requestId, 42n);
expect(await game.isRngFulfilled()).to.equal(true);

// Step 3: Process VRF word (multiple calls to drain tickets)
for (let i = 0; i < 30; i++) {
  if (!(await game.rngLocked())) break;
  await game.connect(deployer).advanceGame();
}
```

**Account impersonation (for privileged calls):**
```javascript
async function impersonate(address) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x56BC75E2D63100000",  // 100 ETH
  ]);
  return hre.ethers.getSigner(address);
}

// Use:
const gameSigner = await impersonate(gameAddr);
await coin.connect(gameSigner).rollDailyQuest(day, entropy);
```

### What to Mock

**Mock external dependencies:**
- Chainlink VRF Coordinator → `MockVRFCoordinator`
- Lido stETH → `MockStETH`
- Chainlink LINK token → `MockLinkToken`
- Other ERC20 tokens → `MockWXRP`
- Price feeds → `MockLinkEthFeed`

**What NOT to mock:**
- Protocol contracts (22 contracts deployed in full fixture)
- Game logic (tested as-is; no mocking of DegenerusGame internals)
- Internal contract calls (e.g., Game calling Coin is NOT mocked)

## Fixtures and Factories

### Test Data

**Main fixture:** `deployFullProtocol()` from `test/helpers/deployFixture.js`

**Returns object:**
```javascript
{
  // Signers
  deployer,      // Account [0]
  alice,         // Account [1]
  bob,           // Account [2]
  carol,         // Account [3]
  dan,           // Account [4]
  eve,           // Account [5]
  others,        // Accounts [6+]

  // Mock external contracts
  mockVRF,
  mockStETH,
  mockLINK,
  mockWXRP,
  mockFeed,

  // Protocol contracts (22 total)
  icons32,       // Icons32Data
  coin,          // BurnieCoin
  coinflip,      // BurnieCoinflip
  game,          // DegenerusGame
  // ... (18 more contracts)

  // Module instances for testing delegatecall errors
  advanceModule,
  endgameModule,
  // ... (8 more modules)
}
```

**Fixture execution:**
```javascript
const { game, alice, deployer, mockVRF } = await loadFixture(deployFullProtocol);
```

**Lifecycle:**
- `loadFixture()` caches results within a describe block
- Re-run on new describe block
- `restoreAddresses()` called in `after()` hook to clean up patch/compile side effects

### Factories

**No test data factories in use.** All test scenarios manually construct parameters:

**Example from GameOver.test.js:**
```javascript
async function buyTickets(game, buyer, qty, valueEth) {
  await game
    .connect(buyer)
    .purchase(
      ZERO_ADDRESS,
      BigInt(qty) * 100n,    // Manually scaled
      0n,
      ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth(valueEth) }
    );
}
```

**Constants reused across tests:**
```javascript
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
const ZERO_ADDRESS = "0x" + "0".repeat(40);
const ZERO_BYTES32 = "0x" + "0".repeat(64);
```

## Coverage

### Requirements

**Coverage target:** No formal enforced requirement detected.

**Test organization:** Tests emphasize behavior coverage over line coverage:
- Unit tests: Contract state and function logic
- Integration tests: Multi-contract workflows (GameLifecycle, VRFIntegration)
- Edge case tests: Boundary conditions (GameOver at 912 days, RNG stall, whale bundles, price escalation)
- Access control tests: All restricted functions tested against unauthorized callers
- Adversarial tests: Economic attack scenarios and chain-specific vulnerabilities

### View Coverage

**No coverage report configured.** Gas reporter output shows function call metrics but not line coverage.

**Run gas profiling:**
```bash
npm test  # Outputs gas table with function costs
```

## Test Types

### Unit Tests

**Scope:** Individual contract functionality

**Approach:**
- Test contract directly via loadFixture
- Verify state changes and event emissions
- Test access control and error conditions
- Location: `test/unit/*.test.js`

**Example from DegenerusGame.test.js:**
```javascript
describe("Initial state", function () {
  it("starts at level 0", async function () {
    const { game } = await loadFixture(deployFullProtocol);
    expect(await game.level()).to.equal(0n);
  });
});
```

### Integration Tests

**Scope:** Multi-contract workflows

**Approach:**
- Test game lifecycle: purchase → advance → VRF cycle
- Test VRF integration with full state machine
- Verify contract interactions and state consistency
- Location: `test/integration/*.test.js`

**Example from GameLifecycle.test.js (simplified):**
```javascript
async function driveFullVRFCycle(game, mockVRF, advanceModule, caller) {
  await game.connect(caller).advanceGame();  // Request VRF
  expect(await game.rngLocked()).to.equal(true);

  const requestId = await getLastVRFRequestId(mockVRF);
  await mockVRF.fulfillRandomWords(requestId, 123n);  // Fulfill

  // Drain tickets
  for (let i = 0; i < 30; i++) {
    if (!(await game.rngLocked())) break;
    await game.connect(caller).advanceGame();
  }
}
```

### E2E / Edge Case Tests

**Framework:** Mocha (same as unit/integration; no separate E2E framework)

**Scope:** Complex state machine scenarios and boundary conditions

**Approach:**
- GameOver edge cases: pre-game 912-day timeout, post-game inactivity
- RNG stall scenarios: VRF timeout, retry logic
- Whale bundle pricing and freezing
- Price escalation and ticket cost calculations
- Location: `test/edge/*.test.js`

**Example from GameOver.test.js:**
```javascript
describe("pre-game 912-day timeout (level 0)", function () {
  it("gameOver becomes true after 912+ days at level 0", async function () {
    const { game, deployer, mockVRF } = await loadFixture(deployFullProtocol);

    expect(await game.level()).to.equal(0n);
    expect(await game.gameOver()).to.equal(false);

    await advanceTime(912 * 86400 + 86400);  // 912 days + buffer

    // Multi-step VRF flow
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    await mockVRF.fulfillRandomWords(requestId, 42n);
    await game.connect(deployer).advanceGame();

    expect(await game.gameOver()).to.equal(true);
  });
});
```

## Common Patterns

### Async Testing

**Pattern:** All tests are async; use `await` for contract calls and state checks.

**Time advancement:**
```javascript
import { advanceTime, advanceToNextDay } from "../helpers/testUtils.js";

// Advance time by seconds
await advanceTime(86400);  // 1 day

// Advance to next day boundary (helper)
await advanceToNextDay();
```

**Block advancement:**
```javascript
async function advanceBlocks(n) {
  for (let i = 0; i < n; i++) {
    await hre.ethers.provider.send("evm_mine");
  }
}
```

### Error Testing

**Pattern:** Expect custom errors for specific failures; generic revert for others.

**Custom error (contract error):**
```javascript
await expect(
    coin.connect(alice).creditFlip(bob.address, eth("100"))
).to.be.revertedWithCustomError(coin, "OnlyFlipCreditors");
```

**Delegatecall error (module error, re-thrown):**
```javascript
await expect(
    game.connect(player).reverseFlip(player.address)
).to.be.revertedWithCustomError(advanceModule, "RngLocked");
```

**Generic revert (error name not checked):**
```javascript
await expect(
    game.connect(deployer).advanceGame()
).to.be.reverted;
```

**Verification of non-revert:**
```javascript
await expect(
    game.connect(alice).purchase(...)
).to.not.be.reverted;
```

### Event Verification

**Pattern:** Parse events from transaction receipt; assert event args.

**Single event:**
```javascript
import { getEvent } from "../helpers/testUtils.js";

const tx = await game.connect(alice).setOperatorApproval(bob.address, true);
const ev = await getEvent(tx, game, "OperatorApproval");

expect(ev.args.owner).to.equal(alice.address);
expect(ev.args.operator).to.equal(bob.address);
expect(ev.args.approved).to.be.true;
```

**Multiple events:**
```javascript
import { getEvents } from "../helpers/testUtils.js";

const tx = await advanceGame();
const events = await getEvents(tx, advanceModule, "Advance");

expect(events.length).to.be.gt(0);
expect(events[0].args.stage).to.equal(1);  // STAGE_RNG_REQUESTED
```

**Delegatecall events:**
```javascript
// Event emitted inside delegatecall; parse with module interface:
const tx = await game.connect(deployer).advanceGame();
const advanceEvents = await getEvents(tx, advanceModule, "Advance");
```

## Test Execution Strategy

### Test Phases

**Phase 1: Deploy** (`npm test:deploy`)
- Verify deployment script nonce prediction
- Verify address patching and contract creation order
- Quick validation (~12 tests)

**Phase 2: Unit** (`npm test:unit`)
- Test each contract in isolation
- ~670 tests across 12 contracts
- 10-20s runtime

**Phase 3: Integration** (`npm test:integration`)
- GameLifecycle: purchase → advance → VRF cycle
- VRFIntegration: VRF request/fulfill/processing
- ~50 tests
- 5-10s runtime

**Phase 4: Access Control** (`npm test:access`)
- Systematic unauthorized caller checks
- All restricted functions tested
- ~49 tests
- 5s runtime

**Phase 5: Edge Cases** (`npm test:edge`)
- GameOver scenarios (912 days, inactivity)
- RNG stall and retry timeout
- Whale bundles and pricing
- Price escalation
- ~102 tests across 4 files
- 10s runtime

**Phase 6: Simulation** (`npm test:simulation`)
- Play-through scenarios (2-5 levels)
- Generate UI data for analysis
- ~50 tests

**Phase 7: Adversarial** (`npm test:adversarial`)
- Technical attack vectors (flash loans, reentrancy, etc.)
- Economic attack scenarios
- Sepolia-specific actor tests (optional flag)
- ~20 tests

### Dependencies

**Test isolation:** Each test file calls `loadFixture(deployFullProtocol)` independently; no cross-file state.

**Fixture caching:** Within a describe block, `loadFixture` returns cached result (same state for all tests in block).

**Cleanup:** `restoreAddresses()` called in `after()` hook after all tests in a file complete; restores patched ContractAddresses.sol.

---

*Testing analysis: 2026-02-28*
