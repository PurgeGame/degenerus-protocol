# XCON-07: Constructor Deploy Order Verification

**Requirement:** XCON-07 -- Constructor-time cross-contract calls execute in correct order given the deploy sequence
**Date:** 2026-03-01
**Auditor:** Claude Opus 4.6 (automated)
**Scope:** All 22 deployable contracts in the Degenerus Protocol

---

## 1. Deploy Order Verification (Source of Truth)

Verified against `scripts/lib/predictAddresses.js` lines 16-39. The DEPLOY_ORDER array defines the nonce-based deployment sequence:

| Nonce Offset | Key | Contract | Category |
|:---:|------|----------|----------|
| N+0 | ICONS_32 | Icons32Data | Data |
| N+1 | GAME_MINT_MODULE | DegenerusGameMintModule | Module |
| N+2 | GAME_ADVANCE_MODULE | DegenerusGameAdvanceModule | Module |
| N+3 | GAME_WHALE_MODULE | DegenerusGameWhaleModule | Module |
| N+4 | GAME_JACKPOT_MODULE | DegenerusGameJackpotModule | Module |
| N+5 | GAME_DECIMATOR_MODULE | DegenerusGameDecimatorModule | Module |
| N+6 | GAME_ENDGAME_MODULE | DegenerusGameEndgameModule | Module |
| N+7 | GAME_GAMEOVER_MODULE | DegenerusGameGameOverModule | Module |
| N+8 | GAME_LOOTBOX_MODULE | DegenerusGameLootboxModule | Module |
| N+9 | GAME_BOON_MODULE | DegenerusGameBoonModule | Module |
| N+10 | GAME_DEGENERETTE_MODULE | DegenerusGameDegeneretteModule | Module |
| N+11 | COIN | BurnieCoin | Core |
| N+12 | COINFLIP | BurnieCoinflip | Core |
| N+13 | GAME | DegenerusGame | Core |
| N+14 | WWXRP | WrappedWrappedXRP | Token |
| N+15 | AFFILIATE | DegenerusAffiliate | Core |
| N+16 | JACKPOTS | DegenerusJackpots | Core |
| N+17 | QUESTS | DegenerusQuests | Core |
| N+18 | DEITY_PASS | DegenerusDeityPass | NFT |
| N+19 | VAULT | DegenerusVault | Core |
| N+20 | DGNRS | DegenerusStonk | Token |
| N+21 | ADMIN | DegenerusAdmin | Admin |

**Source match:** DEPLOY_ORDER array and KEY_TO_CONTRACT mapping in `predictAddresses.js` exactly match the above table. Confirmed 22 entries.

Documented constraints from source comments (lines 8-14):
- COIN (N+11) before VAULT (N+19): vault reads `vaultMintAllowance()`
- GAME (N+13) + modules (N+1..10) before DGNRS (N+20): stonk calls `claimWhalePass`/`setAfKingMode`
- GAME (N+13) before ADMIN (N+21): admin calls `wireVrf()`

---

## 2. Constructor Classification Table

For each of the 22 contracts, the constructor was read and classified as:
- **(a) No cross-contract calls** -- constructor only sets storage/immutables, no external function calls
- **(b) Cross-contract calls to lower-nonce or external contracts** -- SAFE
- **(c) Cross-contract calls to higher-nonce contracts** -- ORDERING BUG

| Nonce | Key | Contract | Constructor | Type | Cross-Contract Calls | Targets | Safe? |
|:---:|------|----------|:---:|:---:|------|------|:---:|
| N+0 | ICONS_32 | Icons32Data | `constructor() {}` (L139) | (a) | None | -- | SAFE |
| N+1 | GAME_MINT_MODULE | DegenerusGameMintModule | No constructor | (a) | None | -- | SAFE |
| N+2 | GAME_ADVANCE_MODULE | DegenerusGameAdvanceModule | No constructor | (a) | None | -- | SAFE |
| N+3 | GAME_WHALE_MODULE | DegenerusGameWhaleModule | No constructor | (a) | None | -- | SAFE |
| N+4 | GAME_JACKPOT_MODULE | DegenerusGameJackpotModule | No constructor | (a) | None | -- | SAFE |
| N+5 | GAME_DECIMATOR_MODULE | DegenerusGameDecimatorModule | No constructor | (a) | None | -- | SAFE |
| N+6 | GAME_ENDGAME_MODULE | DegenerusGameEndgameModule | No constructor | (a) | None | -- | SAFE |
| N+7 | GAME_GAMEOVER_MODULE | DegenerusGameGameOverModule | No constructor | (a) | None | -- | SAFE |
| N+8 | GAME_LOOTBOX_MODULE | DegenerusGameLootboxModule | No constructor | (a) | None | -- | SAFE |
| N+9 | GAME_BOON_MODULE | DegenerusGameBoonModule | No constructor | (a) | None | -- | SAFE |
| N+10 | GAME_DEGENERETTE_MODULE | DegenerusGameDegeneretteModule | No constructor | (a) | None | -- | SAFE |
| N+11 | COIN | BurnieCoin | No constructor | (a) | None | -- | SAFE |
| N+12 | COINFLIP | BurnieCoinflip | Has constructor (L185) | (a) | None (immutable args only) | -- | SAFE |
| N+13 | GAME | DegenerusGame | Has constructor (L255) | (a) | None (internal storage only) | -- | SAFE |
| N+14 | WWXRP | WrappedWrappedXRP | No constructor | (a) | None | -- | SAFE |
| N+15 | AFFILIATE | DegenerusAffiliate | Has constructor (L252) | (a) | None (private storage writes) | -- | SAFE |
| N+16 | JACKPOTS | DegenerusJackpots | No constructor | (a) | None | -- | SAFE |
| N+17 | QUESTS | DegenerusQuests | No constructor | (a) | None | -- | SAFE |
| N+18 | DEITY_PASS | DegenerusDeityPass | Has constructor (L78) | (a) | None (sets owner only) | -- | SAFE |
| N+19 | VAULT | DegenerusVault | Has constructor (L429) | (b) | `coinToken.vaultMintAllowance()` | COIN (N+11) | SAFE |
| N+20 | DGNRS | DegenerusStonk | Has constructor (L360) | (b) | `game.claimWhalePass()`, `game.setAfKingMode()` | GAME (N+13) | SAFE |
| N+21 | ADMIN | DegenerusAdmin | Has constructor (L366) | (b) | `vrfCoordinator.createSubscription()`, `vrfCoordinator.addConsumer()`, `gameAdmin.wireVrf()` | VRF (external), GAME (N+13) | SAFE |

**Result:** 18 contracts type (a), 3 contracts type (b), 0 contracts type (c). No ordering violations.

---

## 3. Open Question Resolution

### 3.1 BurnieCoin (N+11) -- RESOLVED: No Constructor

BurnieCoin has **no constructor** keyword anywhere in the file. Verified by searching `contracts/BurnieCoin.sol` for `constructor` -- zero matches.

The contract uses compile-time constants from `ContractAddresses` for all cross-contract references (stored as `constant` contract-level variables, e.g., `questModule = IDegenerusQuests(ContractAddresses.QUESTS)`) but these are address constants set at compile time, not runtime calls. No function is invoked on any external contract during construction.

**Evidence:** `grep -n "constructor" contracts/BurnieCoin.sol` returns zero results.

**Verdict:** BurnieCoin constructor makes NO cross-contract calls. SAFE at any nonce position.

### 3.2 WrappedWrappedXRP (N+14) -- RESOLVED: No Constructor

WrappedWrappedXRP has **no constructor**. Verified by searching `contracts/WrappedWrappedXRP.sol` for `constructor` -- zero matches.

The contract stores compile-time constant addresses (`wXRP`, `MINTER_GAME`, `MINTER_COIN`, `MINTER_COINFLIP`, `MINTER_VAULT`) but these are all `constant` declarations that do not invoke any functions during deployment.

State initialization uses Solidity default values and inline initializers:
- `uint256 public vaultAllowance = INITIAL_VAULT_ALLOWANCE;` (compile-time constant)

**Evidence:** `grep -n "constructor" contracts/WrappedWrappedXRP.sol` returns zero results.

**Verdict:** WrappedWrappedXRP constructor makes NO cross-contract calls. SAFE at any nonce position.

### 3.3 DegenerusJackpots (N+16) -- RESOLVED: No Constructor

DegenerusJackpots has **no constructor**. Verified by searching `contracts/DegenerusJackpots.sol` for `constructor` -- zero matches.

The contract stores compile-time constant references (`coin`, `degenerusGame`, `affiliate`) but these are `constant` declarations. All mappings (`bafTotals`, `bafTop`, `bafTopLen`) initialize to Solidity defaults (zero/empty).

**Evidence:** `grep -n "constructor" contracts/DegenerusJackpots.sol` returns zero results.

**Verdict:** DegenerusJackpots constructor makes NO cross-contract calls. SAFE at any nonce position.

### 3.4 DegenerusQuests (N+17) -- RESOLVED: No Constructor

DegenerusQuests has **no constructor**. Verified by searching `contracts/DegenerusQuests.sol` for `constructor` -- zero matches.

The contract references `ContractAddresses.GAME` and `ContractAddresses.COIN` as compile-time constants but does not call any functions on them during deployment.

**Evidence:** `grep -n "constructor" contracts/DegenerusQuests.sol` returns zero results.

**Verdict:** DegenerusQuests constructor makes NO cross-contract calls. SAFE at any nonce position.

---

## 4. Deep Analysis: DegenerusVault Constructor (N+19)

**Source:** `contracts/DegenerusVault.sol` lines 429-436

```solidity
constructor() {
    coinShare = new DegenerusVaultShare("Degenerus Vault Burnie", "DGVB");
    ethShare = new DegenerusVaultShare("Degenerus Vault Eth", "DGVE");
    uint256 coinAllowance = coinToken.vaultMintAllowance();
    coinTracked = coinAllowance;
}
```

### 4a. Sub-contract creation via `new`

`new DegenerusVaultShare(...)` uses the CREATE opcode. These sub-contracts are deployed by the Vault contract itself (not the deployer EOA), so they consume the Vault's nonces, NOT the deployer's nonce sequence. They do not interfere with the DEPLOY_ORDER nonce predictions.

The DegenerusVaultShare constructor (L196-202) only sets `name`, `symbol`, `totalSupply`, and `balanceOf[CREATOR]` -- no external calls.

**SAFE:** Sub-contract creation is internal to Vault deployment.

### 4b. `coinToken.vaultMintAllowance()` call

- `coinToken` is defined as `IVaultCoin(ContractAddresses.COIN)` (L372) -- points to COIN at N+11
- `vaultMintAllowance()` is defined in BurnieCoin at L328 as:
  ```solidity
  function vaultMintAllowance() external view returns (uint256) {
      return _supply.vaultAllowance;
  }
  ```
- This is a **view function** -- it only reads storage, no state changes
- COIN (N+11) is deployed 8 nonces before VAULT (N+19) -- already has code

**SAFE:** View call to already-deployed contract.

### 4c. No other cross-contract calls

The constructor body contains exactly 4 statements. After the two `new` operations and the `vaultMintAllowance()` call, only `coinTracked = coinAllowance` remains (a simple storage write).

**Verdict:** DegenerusVault constructor is SAFE. All cross-contract interactions target lower-nonce contracts.

---

## 5. Deep Analysis: DegenerusStonk Constructor (N+20)

**Source:** `contracts/DegenerusStonk.sol` lines 360-394

```solidity
constructor() {
    uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
    // ... pool allocation arithmetic ...
    _mint(ContractAddresses.CREATOR, creatorAmount);
    _mint(address(this), poolTotal);
    poolBalances[uint8(Pool.Whale)] = whaleAmount;
    // ... pool balance assignments ...
    game.claimWhalePass(address(0));
    game.setAfKingMode(address(0), true, 10 ether, 0);
}
```

### 5a. `game.claimWhalePass(address(0))`

- `game` is defined as `IDegenerusGamePlayer(ContractAddresses.GAME)` (L310) -- points to GAME at N+13
- GAME (N+13) is deployed 7 nonces before DGNRS (N+20) -- already has code
- `claimWhalePass(address(0))` is called with `address(0)` as the player parameter. When called from the DegenerusStonk constructor, `msg.sender` is the DegenerusStonk contract address (being deployed). The `address(0)` parameter indicates no specific player -- this is a protocol-level initialization claiming the whale pass for the DegenerusStonk contract itself.

**SAFE:** State-changing call to already-deployed contract.

### 5b. `game.setAfKingMode(address(0), true, 10 ether, 0)`

- Same `game` constant pointing to GAME (N+13) -- already deployed
- Enables afKing mode for the DegenerusStonk contract with 10 ETH take-profit and 0 coin take-profit
- The `address(0)` player parameter resolves to the calling contract (DegenerusStonk) via `_resolvePlayer`

**SAFE:** State-changing call to already-deployed contract.

### 5c. No calls to VAULT (N+19) or ADMIN (N+21)

The constructor does not reference `ContractAddresses.VAULT` or `ContractAddresses.ADMIN`. The only cross-contract calls are the two calls to GAME.

**IMPORTANT NOTE:** `_mint(ContractAddresses.CREATOR, creatorAmount)` is an internal function call that mints tokens within the DegenerusStonk ERC-20 -- it does NOT call the CREATOR address externally. Similarly, `_mint(address(this), poolTotal)` is internal.

**Verdict:** DegenerusStonk constructor is SAFE. Both cross-contract calls target GAME (N+13), deployed 7 nonces earlier.

---

## 6. Deep Analysis: DegenerusAdmin Constructor (N+21)

**Source:** `contracts/DegenerusAdmin.sol` lines 366-387

```solidity
constructor() {
    uint256 subId = vrfCoordinator.createSubscription();
    coordinator = ContractAddresses.VRF_COORDINATOR;
    subscriptionId = uint64(subId);
    vrfKeyHash = ContractAddresses.VRF_KEY_HASH;
    emit SubscriptionCreated(subId);
    emit CoordinatorUpdated(ContractAddresses.VRF_COORDINATOR, subId);
    vrfCoordinator.addConsumer(subId, ContractAddresses.GAME);
    emit ConsumerAdded(ContractAddresses.GAME);
    gameAdmin.wireVrf(
        ContractAddresses.VRF_COORDINATOR,
        subId,
        ContractAddresses.VRF_KEY_HASH
    );
}
```

### 6a. `vrfCoordinator.createSubscription()`

- `vrfCoordinator` is defined as `IVRFCoordinatorV2_5Owner(ContractAddresses.VRF_COORDINATOR)` (L294-295)
- VRF Coordinator is an external Chainlink contract (mainnet: `0x271682DEB8C4E0901D1a1550aD2e64D568E69909`, Sepolia: `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B`)
- External contracts are deployed independently, always have code at their address

**SAFE:** External protocol call (Chainlink VRF), independent of DEPLOY_ORDER.

### 6b. `vrfCoordinator.addConsumer(subId, ContractAddresses.GAME)`

- Same external VRF coordinator -- already deployed
- Passes `ContractAddresses.GAME` (N+13) as the consumer address -- note that addConsumer only registers the address, it does not call GAME. GAME (N+13) is already deployed at this point (N+21) regardless.

**SAFE:** External protocol call, GAME address used as data parameter (not called).

### 6c. `gameAdmin.wireVrf(...)`

- `gameAdmin` is defined as `IDegenerusGameAdmin(ContractAddresses.GAME)` (L296-297) -- points to GAME at N+13
- GAME (N+13) is deployed 8 nonces before ADMIN (N+21) -- already has code
- `wireVrf()` configures VRF coordinator address, subscription ID, and key hash in the GAME contract

**SAFE:** State-changing call to already-deployed contract.

### 6d. All addresses used

| Address | Source | Type | Available at N+21? |
|---------|--------|------|:---:|
| VRF_COORDINATOR | ContractAddresses (external) | External Chainlink | Yes (pre-deployed) |
| GAME (N+13) | ContractAddresses | Protocol | Yes (gap of 8) |
| LINK_TOKEN | ContractAddresses (external) | External Chainlink | Yes (pre-deployed) |
| COIN (N+11) | ContractAddresses | Protocol | Yes (gap of 10) |
| VAULT (N+19) | ContractAddresses | Protocol | Yes (gap of 2) |

Note: `COIN`, `LINK_TOKEN`, and `VAULT` constants are stored but NOT called in the constructor. They are only used in runtime functions (e.g., `onTokenTransfer`, `onlyOwner` modifier).

**Verdict:** DegenerusAdmin constructor is SAFE. All cross-contract calls target external Chainlink contracts or GAME (N+13).

---

## 7. ContractAddresses Constants vs. Function Calls

A critical distinction: storing a ContractAddresses constant as an address is SAFE regardless of deploy order. Only **calling a function** on a not-yet-deployed address is problematic (the call would target an address with no code).

### Patterns Found

**Pattern 1: Address stored as constant, no constructor call (SAFE)**

Many contracts store ContractAddresses constants as compile-time `constant` variables:
- BurnieCoin: `questModule = IDegenerusQuests(ContractAddresses.QUESTS)` -- no constructor call
- WrappedWrappedXRP: `wXRP = IERC20(ContractAddresses.WXRP)` -- no constructor call
- DegenerusJackpots: `degenerusGame = IDegenerusGame(ContractAddresses.GAME)` -- no constructor call
- DegenerusAdmin: `vault = IDegenerusVaultOwner(ContractAddresses.VAULT)` -- no constructor call

These are compile-time address casts. The addresses are embedded in the contract bytecode. No function is called during deployment.

**Pattern 2: Constructor calls function on stored address (must be lower nonce)**

Only 3 contracts make actual function calls during construction:
1. DegenerusVault (N+19): calls COIN (N+11) `vaultMintAllowance()` -- gap of 8
2. DegenerusStonk (N+20): calls GAME (N+13) `claimWhalePass()`, `setAfKingMode()` -- gap of 7
3. DegenerusAdmin (N+21): calls VRF (external) `createSubscription()`, `addConsumer()` and GAME (N+13) `wireVrf()` -- gap of 8

All targets are at lower nonce offsets or external (pre-deployed).

**Pattern 3: Constructor stores immutable from argument (no address call)**

BurnieCoinflip (N+12) takes constructor arguments and stores them as `immutable`:
```solidity
constructor(address _burnie, address _degenerusGame, address _jackpots, address _wwxrp) {
    burnie = IBurnieCoin(_burnie);         // just stores address
    degenerusGame = IDegenerusGame(_degenerusGame);  // just stores address
    jackpots = IDegenerusJackpots(_jackpots);        // just stores address
    wwxrp = IWrappedWrappedXRP(_wwxrp);              // just stores address
}
```

No functions are called on these addresses during construction. They are cast to interface types and stored as immutables, to be used at runtime only.

---

## 8. Module Constructor Verification

All 10 delegatecall game modules were searched for `constructor` keyword:

```
grep -rn "constructor" contracts/modules/ --include="*.sol"
```

**Result:** Zero matches. No module has a constructor.

Modules inherit from `DegenerusGameStorage` (or `DegenerusGamePayoutUtils`/`DegenerusGameMintStreakUtils` which extend it). The storage contract also has no constructor -- its state is initialized by the DegenerusGame constructor and shared via delegatecall.

Since modules are stateless libraries deployed independently, the absence of constructors means they cannot have cross-contract call ordering issues.

---

## 9. XCON-07 Verdict

### XCON-07: PASS

**All 22 contract constructors have been read and classified. No constructor ordering violation exists.**

Evidence summary:

| Category | Count | Details |
|----------|:---:|---------|
| No constructor at all | 15 | 10 modules, BurnieCoin, WrappedWrappedXRP, DegenerusJackpots, DegenerusQuests, plus 1 empty (Icons32Data) |
| Constructor with no cross-contract calls | 4 | Icons32Data (empty), BurnieCoinflip (immutable args), DegenerusGame (internal storage), DegenerusAffiliate (private storage), DegenerusDeityPass (sets owner) |
| Constructor with cross-contract calls (all SAFE) | 3 | DegenerusVault, DegenerusStonk, DegenerusAdmin |
| Constructor calling higher-nonce contract | 0 | -- |
| Constructor calling external (pre-deployed) | 1 | DegenerusAdmin (Chainlink VRF) |

### Cross-Contract Call Summary (constructors only)

| Caller | Nonce | Target | Target Nonce | Gap | Call | Mutating? | Safe? |
|--------|:---:|--------|:---:|:---:|------|:---:|:---:|
| DegenerusVault | N+19 | BurnieCoin | N+11 | 8 | `vaultMintAllowance()` | No (view) | SAFE |
| DegenerusStonk | N+20 | DegenerusGame | N+13 | 7 | `claimWhalePass(address(0))` | Yes | SAFE |
| DegenerusStonk | N+20 | DegenerusGame | N+13 | 7 | `setAfKingMode(address(0), true, 10 ether, 0)` | Yes | SAFE |
| DegenerusAdmin | N+21 | VRF Coordinator | External | -- | `createSubscription()` | Yes | SAFE |
| DegenerusAdmin | N+21 | VRF Coordinator | External | -- | `addConsumer(subId, GAME)` | Yes | SAFE |
| DegenerusAdmin | N+21 | DegenerusGame | N+13 | 8 | `wireVrf(...)` | Yes | SAFE |

### Open Questions Resolution

| Contract | Nonce | Question | Answer | Evidence |
|----------|:---:|---------|--------|----------|
| BurnieCoin | N+11 | Does constructor make external calls? | **No** -- no constructor exists | `grep` returns 0 matches |
| WrappedWrappedXRP | N+14 | Constructor calls? | **No** -- no constructor exists | `grep` returns 0 matches |
| DegenerusJackpots | N+16 | Constructor calls? | **No** -- no constructor exists | `grep` returns 0 matches |
| DegenerusQuests | N+17 | Constructor calls? | **No** -- no constructor exists | `grep` returns 0 matches |

### Conclusion

The DEPLOY_ORDER in `predictAddresses.js` correctly sequences all 22 contracts such that every constructor-time cross-contract call targets a contract that has already been deployed. The three contracts with constructor cross-contract calls (Vault, Stonk, Admin) are placed at the end of the sequence (N+19, N+20, N+21) with comfortable nonce gaps to their targets.

No contract constructor references a contract deployed at a higher nonce offset.

**XCON-07: PASS**

---

## Appendix: Files Examined (Read-Only)

| File | Purpose |
|------|---------|
| `scripts/lib/predictAddresses.js` | DEPLOY_ORDER source of truth |
| `contracts/Icons32Data.sol` | Constructor at L139 |
| `contracts/BurnieCoin.sol` | No constructor |
| `contracts/BurnieCoinflip.sol` | Constructor at L185 |
| `contracts/DegenerusGame.sol` | Constructor at L255 |
| `contracts/WrappedWrappedXRP.sol` | No constructor |
| `contracts/DegenerusAffiliate.sol` | Constructor at L252 |
| `contracts/DegenerusJackpots.sol` | No constructor |
| `contracts/DegenerusQuests.sol` | No constructor |
| `contracts/DegenerusDeityPass.sol` | Constructor at L78 |
| `contracts/DegenerusVault.sol` | Constructor at L429 |
| `contracts/DegenerusStonk.sol` | Constructor at L360 |
| `contracts/DegenerusAdmin.sol` | Constructor at L366 |
| `contracts/storage/DegenerusGameStorage.sol` | `_queueTickets` internal function |
| `contracts/modules/*.sol` (10 files) | No constructors |

**No contract files were modified during this audit.**
