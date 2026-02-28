# Coding Conventions

**Analysis Date:** 2026-02-28

## Naming Patterns

### Files

**Solidity contracts (.sol):**
- Pattern: PascalCase matching contract name
- Examples: `DegenerusGame.sol`, `BurnieCoin.sol`, `DegenerusGameAdvanceModule.sol`
- Interface files: Prefix with `I` (e.g., `IDegenerusGame.sol`)
- Libraries: Suffix with `Lib` (e.g., `BitPackingLib.sol`)
- Storage files: Suffix with `Storage` (e.g., `DegenerusGameStorage.sol`)

**JavaScript/Node files (.js):**
- Pattern: camelCase or kebab-case for scripts, camelCase for modules
- Test files: Suffix with `.test.js` (e.g., `DegenerusGame.test.js`)
- Helper modules: descriptive camelCase (e.g., `deployFixture.js`, `testUtils.js`)
- Deployment scripts: descriptive kebab-case (e.g., `deploy-local.js`, `deploy-sepolia-testnet.js`)

### Functions

**Solidity (public/external):**
- Pattern: camelCase for all functions
- Action verbs when applicable: `purchase()`, `advanceGame()`, `claimWinnings()`
- Boolean getters: prefix with `is` or omit (e.g., `isOperatorApproved()`, `rngLocked()`)
- View functions: descriptive with `View` suffix when returning computed data (e.g., `ticketsOwedView()`, `purchaseInfo()`)
- Private/internal: camelCase, often with leading underscore convention NOT used (direct `camelCase`)

**JavaScript (test/helpers):**
- Pattern: camelCase for all functions
- Helper functions: descriptive (e.g., `deployFullProtocol()`, `purchaseTickets()`)
- Getter/parser functions: descriptive with action verb (e.g., `getAdvanceEvents()`, `getLastVRFRequestId()`)
- Async functions: no special naming convention; rely on `async` keyword

### Variables

**Solidity (storage):**
- Pattern: camelCase
- Capitalized constants (immutable, private constant): UPPER_SNAKE_CASE
- Examples:
  - Storage: `mintPrice`, `levelPrizePool`, `coinflipBalance`
  - Immutable (contract references): `coin`, `coinflip`, `steth`
  - Constants: `PURCHASE_TO_FUTURE_BPS`, `DEPLOY_IDLE_TIMEOUT_DAYS`, `ZERO_ADDRESS`

**Solidity (local/function parameters):**
- Pattern: camelCase
- Temp variables: short descriptive names (e.g., `requestId`, `addr`, `amount`)
- Type hints in variable names when clarifying (e.g., `priceWei`, `tokenId`, `amountBurned`)

**JavaScript:**
- Pattern: camelCase for variables
- Constants: UPPER_SNAKE_CASE (e.g., `ZERO_ADDRESS`, `MintPaymentKind`)
- Enum-like objects: PascalCase for object name, UPPER_SNAKE_CASE or camelCase for properties (e.g., `MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 }`)

### Types

**Solidity:**
- Pattern: PascalCase for all types
- Contract names: `DegenerusGame`, `BurnieCoin`, `DegenerusGameAdvanceModule`
- Interface names: Prefix with `I` (e.g., `IDegenerusGame`)
- Enums (if used): PascalCase (not commonly used in this codebase; bit-packing preferred)
- Structs: PascalCase (minimal use; prefer bit-packing or direct storage)

**JavaScript:**
- Pattern: PascalCase for class/object type names
- Imported contract types: match Solidity names

## Code Style

### Formatting

**Solidity:**
- Indentation: 4 spaces (viaIR=true, optimizer runs=2 for mainnet)
- Line length: No strict limit observed; pragmatic breaks for readability
- Spacing: Blank lines between logical sections; comments delineate major blocks
- Bracket style: Opening bracket on same line (Allman-style functions are NOT used)

**JavaScript:**
- Indentation: 2 spaces (standard Node.js/ES6)
- Line length: Flexible; breaks for readability
- Spacing: Standard ES6 conventions
- Semicolons: Present (explicit; not optional)

### Linting

**Solidity:**
- No `.solhint` or formal linter config detected
- Conventions followed manually by convention:
  - SPDX header required: `// SPDX-License-Identifier: AGPL-3.0-only`
  - Pragma statement: `pragma solidity ^0.8.26;` or `^0.8.28`
  - Order: imports → interfaces → contract declaration
  - Internal/library organization: constants first, then storage, then functions

**JavaScript:**
- No `.eslintrc` or `.prettierrc` detected in project root
- Hardhat toolbox includes standard ESLint, but not explicitly configured
- Code follows ES6 module conventions (see Import Organization below)

## Import Organization

### Solidity

**Order:**
1. SPDX and pragma
2. Contract imports (interfaces and libraries)
3. Internal local interfaces (if large/complex)
4. Constants section
5. Contract declaration

**Example from DegenerusGame.sol:**
```solidity
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {IDegenerusCoin} from "./interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "./interfaces/IBurnieCoinflip.sol";
// ... more imports
import {ContractAddresses} from "./ContractAddresses.sol";

interface IDegenerusDeityPassBurn {
    function burn(uint256 tokenId) external;
}

contract DegenerusGame {
    // ... code
}
```

### JavaScript

**Order:**
1. External library imports (`hardhat`, `ethers`, etc.)
2. Internal helper imports (test utilities, deployment helpers)
3. Constants/enums defined locally

**Example from test files:**
```javascript
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { eth, advanceTime, getEvents, ZERO_ADDRESS } from "../helpers/testUtils.js";

const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
```

### Path Aliases

**No path aliases in use.** Imports use relative paths throughout:
- Test imports: relative paths like `../helpers/deployFixture.js`
- Script imports: relative paths like `../../scripts/lib/predictAddresses.js`

## Error Handling

### Solidity Custom Errors

**Pattern:** Custom errors over require strings for gas efficiency.

**Naming:** Descriptive, often single words or short phrases.

**Examples:**
- `error E();` - Generic validation guard error
- `error RngLocked();` - RNG is locked, operation blocked
- `error NotApproved();` - Caller not approved for action
- `error OnlyGame();` - Caller must be game contract
- `error OnlyVault();` - Caller must be vault
- `error OnlyFlipCreditors();` - Caller not flip creditor
- `error Insufficient();` - Balance/allowance too low
- `error AmountLTMin();` - Amount below minimum threshold
- `error ZeroAddress();` - Zero address not allowed
- `error NotDecimatorWindow();` - Outside decimator active period
- `error SupplyOverflow();` - Numeric overflow

**Location in contract:** Defined at top after opening, grouped by type (access control, validation, state).

### JavaScript Error Handling

**Pattern:** Promise-based with expect/chai assertions for test failures.

**Access control errors:** Checked with `revertedWithCustomError(contract, "ErrorName")` or generic `.to.be.reverted`.

**Example:**
```javascript
await expect(
    coin.connect(alice).creditFlip(bob.address, eth("100"))
).to.be.revertedWithCustomError(coin, "OnlyFlipCreditors");
```

**Delegatecall errors:** Must use module contract interface for custom error assertions (error is re-thrown via delegatecall):
```javascript
// Error defined in DegenerusGameAdvanceModule, so assert against advanceModule:
await expect(
    game.connect(player).reverseFlip(player.address)
).to.be.revertedWithCustomError(advanceModule, "RngLocked");
```

## Logging

### Solidity

**Pattern:** Events are the primary logging mechanism; no console.log equivalent.

**Event emissions:**
- Emitted on state changes (transfers, balance updates, approvals)
- Emitted on access control events (OperatorApproval, admin actions)
- Emitted on game state changes (level changes, phase transitions, RNG events)
- Emitted on financial events (escrow, bounties, winnings claims)

**Example:**
```solidity
event OperatorApproval(
    address indexed owner,
    address indexed operator,
    bool approved
);

// Emitted when operator status changes:
emit OperatorApproval(alice.address, bob.address, true);
```

### JavaScript

**Pattern:** Console logging in scripts; no formal logging framework in tests.

**Test logs:** Minimal logging; assertions and error messages provide context.

**Script logging:** Direct `console.log()` for informational output during deployment/simulation.

## Comments

### When to Comment

**Solidity:**
- Natspec (`@notice`, `@dev`, `@param`, `@return`) for all public/external functions
- Inline comments for complex bit-packing, loops, or non-obvious logic
- Block comments for major sections (using `+==...==+` ASCII delimiters)
- Critical invariants and security notes in contract-level docstring

**JavaScript:**
- JSDoc-style comments for exported helper functions
- Inline comments for non-obvious test flow or complex setup
- Block comments at test section beginnings explaining state machine or expected behavior

### JSDoc/TSDoc

**Solidity (Natspec):**
- Format: `/** @notice ... **/` for single-line; multi-line for detailed
- Required on all public/external functions
- `@param name description` for each parameter
- `@return name description` for return values
- `@dev` for implementation details, security notes, or caveats

**Example from BurnieCoin:**
```solidity
/**
 * @notice Standard ERC20 transfer event.
 * @dev Emitted on transfer, mint (from=0), and burn (to=0).
 */
event Transfer(address indexed from, address indexed to, uint256 amount);
```

**JavaScript:**
- Format: `/** description */` for functions
- `@param {type} name - description`
- `@returns {type} description`
- Minimal use in test files; more in helper modules like `deployFixture.js`

**Example from deployHelpers.js:**
```javascript
/**
 * Deploy a contract and wait for it to be mined.
 * @param {import("hardhat")} hre - Hardhat Runtime Environment
 * @param {string} contractName - Solidity contract name
 * @param {any[]} [args=[]] - Constructor arguments
 * @returns {Promise<import("ethers").Contract>} Deployed contract instance
 */
export async function deployContract(hre, contractName, args = []) {
```

## Function Design

### Size

**Solidity:**
- Functions range from single-line getters to multi-hundred-line orchestration methods
- Largest functions: `advanceGame()` (delegatecall dispatch logic)
- Module functions (delegatecall targets): 50-200 lines for complex operations
- Acceptable pattern: Tight coupling to storage; modularity via delegatecall, not extraction

**JavaScript:**
- Test cases: typically 5-30 lines per test
- Helper functions: 10-50 lines
- Fixture (`deployFullProtocol`): 150+ lines but well-commented phases

### Parameters

**Solidity:**
- Explicit parameter lists; no struct unpacking in function signature (use direct params)
- Mix of elementary types (`address`, `uint256`, `uint16`, `bool`) and occasionally arrays
- No named tuples in signatures; return tuples when multiple values needed

**Example:**
```solidity
function purchase(
    address buyer,
    uint256 ticketQuantity,
    uint256 lootBoxAmount,
    bytes32 affiliateCode,
    uint8 payKind
) public payable {
```

**JavaScript:**
- Destructuring commonly used for fixture returns
- Helper functions accept explicit parameters (not options objects)

**Example:**
```javascript
export async function deployContract(hre, contractName, args = []) {
```

### Return Values

**Solidity:**
- Single return: direct value (e.g., `returns (bool)`)
- Multiple returns: tuple unpacking (e.g., `returns (uint256 lvl, bool inJackpot, ...)`)
- Complex data: return struct (rare in this codebase; prefer tuple)

**Example:**
```solidity
function purchaseInfo() public view returns (
    uint256 lvl,
    bool jackpotPhase,
    uint48 lastPurchaseDay,
    bool rngLocked,
    uint256 priceWei
) {
```

**JavaScript:**
- Fixture functions return object with all contracts and signers
- Helper functions return expected values or throw on error

## Module Design

### Exports

**Solidity:**
- All public/external functions are callable entry points
- No module pattern (contracts are not functionally isolated)
- Delegation via delegatecall for large modules (e.g., `DegenerusGameAdvanceModule`)

**JavaScript:**
- Helper modules export named functions (no default exports)
- Fixture exports `deployFullProtocol()` and `restoreAddresses()`
- Test utilities export individual helper functions and constants

**Example from testUtils.js:**
```javascript
export const ZERO_ADDRESS = "0x" + "0".repeat(40);
export const ZERO_BYTES32 = "0x" + "0".repeat(64);
export async function advanceTime(seconds) { ... }
export async function eth(n) { ... }
```

### Barrel Files

**Not used.** Each test imports directly from `../helpers/deployFixture.js` and `../helpers/testUtils.js` without intermediate barrel exports.

## Storage Layout

### Solidity

**Pattern:** Direct storage variables with camelCase names, no getter/setter abstraction.

**Structure:**
```solidity
// Immutable contract references (inherited or baked constants):
IDegenerusCoin internal constant coin = IDegenerusCoin(ContractAddresses.COIN);

// Storage variables (mutable):
mapping(address => uint256) public balanceOf;
mapping(address => bool) public isOperatorApproved;
uint48 public level;
bool public gameOver;

// Complex packed data:
mapping(address => uint256) private mintData; // bit-packed mint history
```

**Conventions:**
- No underscore prefix for private variables (not followed)
- Storage variables directly public when read-only from external callers
- Complex packed data kept as `uint256` for efficiency (unpacked in view functions)

## Documentation Structure

### Contract-Level

**Pattern:** Multi-line Natspec at contract top with:
- `@title` - Contract name
- `@author` - "Burnie Degenerus" (consistent)
- `@notice` - High-level purpose
- `@dev` - Architecture notes, critical invariants, security patterns

**Example from DegenerusGame.sol:**
```solidity
/**
 * @title DegenerusGame
 * @author Burnie Degenerus
 * @notice Core game contract managing state machine, VRF integration, jackpots, and prize pools.
 *
 * @dev ARCHITECTURE:
 *      - 2-state FSM: PURCHASE(false) ↔ JACKPOT(true) → (cycle)
 *      - ...
 *
 * @dev CRITICAL INVARIANTS:
 *      - address(this).balance + steth.balanceOf(this) >= claimablePool
 *      - ...
 */
```

### Block Comments

**Pattern:** ASCII-delimited blocks for major sections:
```solidity
/*+======================================================================+
  |                       SECTION NAME                                   |
  +======================================================================+
  |  Description of section contents and purpose.                        |
  +======================================================================+*/
```

Used to delineate:
- ERRORS
- EVENTS
- CONSTANTS
- STORAGE
- CONSTRUCTOR
- FUNCTIONS (grouped by purpose)

---

*Convention analysis: 2026-02-28*
