# Codebase Structure

**Analysis Date:** 2025-02-28

## Directory Layout

```
degenerus-contracts/
├── contracts/                   # Solidity source (49 files)
│   ├── *.sol                    # Core + token contracts (13 files)
│   ├── interfaces/              # External and protocol interfaces (11 files)
│   ├── modules/                 # Delegatecall modules (12 files)
│   ├── libraries/               # Reusable algorithms (5 files)
│   ├── mocks/                   # Test mock contracts (5 files)
│   └── storage/                 # Shared storage layout (1 file)
├── contracts-testnet/           # Testnet-specific builds (D-scaled versions)
├── scripts/                     # Deployment and test utilities (25+ files)
│   ├── lib/                     # Deployment helpers
│   ├── testnet/                 # Sepolia testnet scripts
│   └── simulation/              # Game simulation scripts
├── test/                        # Test suites (30 files)
│   ├── unit/                    # Unit tests (12 files)
│   ├── integration/             # Integration tests (2 files)
│   ├── deploy/                  # Deployment validation (1 file)
│   ├── access/                  # Access control tests (1 file)
│   ├── edge/                    # Edge case tests (4 files)
│   ├── adversarial/             # Attack simulation (2 files)
│   ├── simulation/              # Game lifecycle simulation (3 files)
│   ├── gas/                     # Gas benchmarks (1 file)
│   └── helpers/                 # Test fixtures and utilities (4 files)
├── artifacts/                   # Compiled contracts (mainnet)
├── artifacts-testnet/           # Compiled testnet contracts
├── deployments/                 # Deployment records
├── docs/                        # Documentation
├── runs/                        # Test run outputs and analysis
├── hardhat.config.js            # Hardhat configuration
├── package.json                 # NPM dependencies and scripts
└── .planning/                   # GSD codebase analysis
```

## Directory Purposes

**contracts/:**
- Purpose: All Solidity smart contract source code
- Contains: Core game contract, token contracts, modules, libraries, interfaces, mocks
- Key files: `DegenerusGame.sol`, `BurnieCoin.sol`, `DegenerusAdmin.sol`

**contracts/interfaces/:**
- Purpose: External contract interfaces and protocol boundaries
- Contains: Minimal interface definitions to avoid circular imports
- Key files:
  - `IDegenerusGame.sol`: Player-facing game interface
  - `IDegenerusGameModules.sol`: Module interface definitions
  - `IStETH.sol`, `IVRFCoordinator.sol`: External dependencies
  - `IBurnieCoinflip.sol`, `IDegenerusCoin.sol`: Token interfaces

**contracts/modules/:**
- Purpose: Delegatecall modules for complex game logic (manage bytecode size)
- Contains: 10 game modules + 2 utility modules
- All inherit `DegenerusGameStorage` for layout alignment
- Key files:
  - `DegenerusGameMintModule.sol`: Player mint history, activity score
  - `DegenerusGameAdvanceModule.sol`: Phase transitions, price curves
  - `DegenerusGameJackpotModule.sol`: Winner selection, payouts
  - `DegenerusGameWhaleModule.sol`: Bundle purchases, freezes
  - `DegenerusGameLootboxModule.sol`: Lootbox opening with EV multipliers

**contracts/libraries/:**
- Purpose: Pure utility functions for bit manipulation, algorithms, calculations
- Contains: 5 standalone libraries (no state, no side effects)
- Key files:
  - `BitPackingLib.sol`: Bit field extraction/insertion (mint data)
  - `EntropyLib.sol`: Deterministic trait generation from tokenId
  - `GameTimeLib.sol`: Day boundary calculations (22:57 UTC)
  - `JackpotBucketLib.sol`: Weighted bucket distribution
  - `PriceLookupLib.sol`: Price escalation curves

**contracts/mocks/:**
- Purpose: Test-only mock implementations for external dependencies
- Contains: Mock contracts for VRF coordinator, stETH, LINK, WXRP
- Used by: All test suites via deployFixture
- Key files:
  - `MockVRFCoordinator.sol`: Simulates Chainlink VRF V2.5
  - `MockStETH.sol`: Simulates Lido stETH yield token
  - `MockLinkToken.sol`: Simulates LINK ERC677

**contracts/storage/:**
- Purpose: Canonical storage layout definition for main contract + all modules
- Contains: Single file defining all storage slots with detailed byte-layout comments
- Key file: `DegenerusGameStorage.sol`
- Why separate: Inherited by DegenerusGame and 10 delegatecall modules; ensures slot alignment

**scripts/:**
- Purpose: Deployment, testing, and game simulation orchestration
- Contains: Hardhat task runners, testnet helpers, analysis tools
- Key files:
  - `deploy.js`: Main deployment script (generates ContractAddresses.sol)
  - `deploy-local.js`: Local Hardhat deployment
  - `deploy-sepolia-testnet.js`: Sepolia testnet deployment with D-scaling

**scripts/lib/:**
- Purpose: Deployment helper utilities
- Key files:
  - `predictAddresses.js`: Nonce-based address prediction + DEPLOY_ORDER
  - `patchContractAddresses.js`: Modifies ContractAddresses.sol before compilation

**test/unit/:**
- Purpose: Individual contract unit tests (isolated functionality)
- Contains: 12 test files, one per major contract
- Structure: `describe()` → `it()` with arrange/act/assert pattern
- Key files: `DegenerusGame.test.js` (largest), `BurnieCoin.test.js`, `BurnieCoinflip.test.js`

**test/integration/:**
- Purpose: Multi-contract interaction tests (workflows across contracts)
- Contains: `GameLifecycle.test.js` (full purchase→phase→jackpot cycle), `VRFIntegration.test.js`

**test/edge/:**
- Purpose: Edge case and boundary condition testing (game over, RNG stall, whale bundles, price escalation)
- Contains: 4 test files covering critical stress points
- Key files: `GameOver.test.js`, `RngStall.test.js`, `WhaleBundle.test.js`

**test/access/:**
- Purpose: Access control and permission tests
- Contains: `AccessControl.test.js` (49 tests for auth patterns)

**test/adversarial/:**
- Purpose: Attack simulation and economic adversary testing
- Contains: Tests for technical attacks, economic exploits, edge cases
- Key files: `TechnicalAdversarial.test.js`, `EconomicAdversarial.test.js`

**test/simulation/:**
- Purpose: Full game lifecycle simulation for data analysis
- Contains: Multi-level game runs (2-level, 5-level, 101-level) generating event logs
- Used for: UI database generation, behavior analysis
- Key files: `simulation-5-levels.test.js`, `generate-ui-db.test.js`

**test/helpers/:**
- Purpose: Shared test utilities and fixtures
- Key files:
  - `deployFixture.js`: Full protocol deployment (mocks + 22 contracts)
  - `testUtils.js`: Common assertion helpers
  - `player-manager.js`: Multi-player orchestration
  - `stats-tracker.js`: Event analysis and statistics

## Key File Locations

**Entry Points:**
- `contracts/DegenerusGame.sol`: Core orchestrator (main contract)
- `contracts/DegenerusAdmin.sol`: VRF admin control
- `scripts/deploy.js`: Deployment entry point (generates ContractAddresses.sol)

**Configuration:**
- `contracts/ContractAddresses.sol`: All 22 contract addresses + VRF config (compile-time constants, zeroed in source)
- `hardhat.config.js`: Hardhat settings (viaIR optimizer, testnet build flag)
- `package.json`: NPM scripts (test, deploy, simulate)

**Core Logic:**
- `contracts/DegenerusGame.sol`: State machine, purchase routing, access control
- `contracts/modules/DegenerusGameAdvanceModule.sol`: Phase transitions + RNG locking
- `contracts/modules/DegenerusGameMintModule.sol`: Activity score, mint data packing
- `contracts/modules/DegenerusGameJackpotModule.sol`: Winner selection, payouts
- `contracts/BurnieCoin.sol`: BURNIE token with coinflip integration
- `contracts/BurnieCoinflip.sol`: Daily 50/50 staking + auto-rebuy
- `contracts/storage/DegenerusGameStorage.sol`: Shared storage layout (32 bytes slot 0, 32 bytes slot 1, etc.)

**Testing:**
- `test/unit/DegenerusGame.test.js`: Game state machine tests (largest unit test)
- `test/integration/GameLifecycle.test.js`: Full cycle tests
- `test/helpers/deployFixture.js`: Protocol deployment fixture (used by all tests)
- `test/helpers/testUtils.js`: Common test utilities

**Libraries:**
- `contracts/libraries/BitPackingLib.sol`: Bit field manipulation
- `contracts/libraries/EntropyLib.sol`: Deterministic trait generation
- `contracts/libraries/GameTimeLib.sol`: Time calculations

## Naming Conventions

**Files:**
- Core contracts: `Degenerus{Feature}.sol` (e.g., DegenerusGame, DegenerusVault)
- Token contracts: `Burnie{Token}.sol` (e.g., BurnieCoin, BurnieCoinflip)
- Modules: `DegenerusGame{Module}.sol` (e.g., DegenerusGameMintModule, DegenerusGameAdvanceModule)
- Interfaces: `I{ContractName}.sol` or `{ContractName}Interfaces.sol` (e.g., IDegenerusGame, DegenerusGameModuleInterfaces)
- Libraries: `{Name}Lib.sol` (e.g., BitPackingLib, GameTimeLib)
- Mocks: `Mock{Service}.sol` (e.g., MockVRFCoordinator, MockStETH)
- Test files: `{ContractName}.test.js` or `{Feature}.test.js`

**Directories:**
- Core: lowercase, purpose-based (`modules/`, `libraries/`, `interfaces/`, `mocks/`, `storage/`)
- Test suite: purpose-based, all lowercase (`unit/`, `integration/`, `edge/`, `adversarial/`, `deployment/`, `helpers/`)
- Build artifacts: singular nouns (`artifacts/`, `cache/`, `deployments/`)

**Solidity Conventions:**
- Contract names: PascalCase (e.g., DegenerusGame, BurnieCoin)
- Functions: camelCase, clear intent
  - External: `purchase`, `advanceGame`, `claimWinnings`
  - Internal: `_resolvePlayer`, `_purchaseFor`, `_openLootBoxFor`
  - View: `level`, `jackpotPhase`, `purchaseInfo` (no prefix)
- State variables: camelCase, lowercase (e.g., `levelStartTime`, `mintPacked_`, arrays use `s_` prefix where convention applies)
- Errors: PascalCase prefixed with `E` (e.g., `E()`, `RngLocked()`, `NotApproved()`)
- Events: PascalCase (e.g., `LootBoxPresaleStatus`, `OperatorApproval`)
- Constants: UPPER_CASE (e.g., `DEPLOY_IDLE_TIMEOUT_DAYS`, `PURCHASE_TO_FUTURE_BPS`)

## Where to Add New Code

**New Gameplay Feature:**
1. Primary implementation: Determine if it fits in existing module or create new module file
   - If modular (delegatecall): Create `contracts/modules/DegenerusGame{Feature}Module.sol`, inherit `DegenerusGameStorage`
   - If core logic: Add to `contracts/DegenerusGame.sol` (if bytecode permits) or route via module
   - If token-related: Add to respective token contract (`BurnieCoin.sol`, `BurnieCoinflip.sol`)
2. Interface definition: Add to `contracts/interfaces/IDegenerusGame.sol` or create `IDegenerusGame{Feature}.sol`
3. Tests:
   - Unit test: `test/unit/Degenerus{Feature}.test.js` or add to existing contract test
   - Integration: Add to `test/integration/GameLifecycle.test.js` if part of main flow
   - Edge cases: Create `test/edge/{Feature}.test.js` if boundary conditions exist
4. Storage (if needed): Extend `contracts/storage/DegenerusGameStorage.sol` with new slots

**New Contract Module:**
1. Create `contracts/modules/DegenerusGame{ModuleName}Module.sol`
2. Inherit `DegenerusGameStorage` to ensure storage alignment
3. Define module interface in `contracts/interfaces/IDegenerusGameModules.sol`
4. Register call site in `DegenerusGame.sol` via delegatecall pattern
5. Add constructor argument to `getConstructorArgs()` in `test/helpers/deployFixture.js`
6. Add to `DEPLOY_ORDER` in `scripts/lib/predictAddresses.js` if pre-deployed
7. Create unit test: `test/unit/Degenerus{ModuleName}.test.js`

**Utilities & Helpers:**
- Pure utility functions: `contracts/libraries/{Name}Lib.sol`
- Test helpers: `test/helpers/{feature}-helper.js` or add to `test/helpers/testUtils.js`

**External Integration:**
- New external contract calls: Add minimal interface to `contracts/interfaces/` (avoid circular imports)
- Mock implementation: Add to `contracts/mocks/Mock{Service}.sol` for testing
- Contract reference: Add address constant to `ContractAddresses.sol` + deployment arg

## Special Directories

**contracts-testnet/:**
- Purpose: Testnet-specific contract builds with D-scaling (prices, bundles, deposits divided by 1,000,000)
- Generated: Yes (copied from contracts/ with modifications)
- Committed: No (gitignored; generated before testnet builds)
- Build command: `TESTNET_BUILD=1 hardhat compile`

**cache/ & artifacts/:**
- Purpose: Hardhat compilation output
- Generated: Yes (hardhat compile)
- Committed: No (gitignored)

**deployments/:**
- Purpose: Deployment records (contract addresses, ABIs, transaction receipts)
- Generated: Yes (created by deploy scripts)
- Committed: Yes (for historical reference)

**runs/:**
- Purpose: Test simulation output (event logs, game state snapshots, analysis data)
- Generated: Yes (created by simulation tests)
- Committed: Selectively (important runs for analysis)

**ContractAddresses.sol Structure:**
- All addresses are compile-time constants (`internal constant address`)
- Source file contains all address(0) placeholder values
- Deploy script (`scripts/lib/patchContractAddresses.js`) modifies source before compilation
- After deployment, actual addresses baked into bytecode
- Never modify manually; use deploy script

**Deployment Pipeline:**
1. `scripts/lib/predictAddresses.js`: Predict nonce-based addresses for 22 contracts
2. `scripts/lib/patchContractAddresses.js`: Write predicted addresses + VRF config to `ContractAddresses.sol`
3. `hardhat compile`: Compile with patched addresses baked into bytecode
4. Deploy contracts in `DEPLOY_ORDER` sequence (modules first, then core, then tokens, then aux, then admin)
5. Verify: Check deployed addresses match predictions
6. Record: Save to `deployments/` for future reference

---

*Structure analysis: 2025-02-28*
