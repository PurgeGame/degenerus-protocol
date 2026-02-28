# Architecture

**Analysis Date:** 2025-02-28

## Pattern Overview

**Overall:** Delegatecall-based modular state machine with compile-time address wiring

**Key Characteristics:**
- 2-state finite state machine: PURCHASE phase (false) ↔ JACKPOT phase (true), with terminal gameOver state
- Core orchestrator (`DegenerusGame`) delegates complex operations to 10 specialized modules
- All contract addresses baked into bytecode via `ContractAddresses.sol` (compile-time constants, all address(0) in source)
- Storage layout unified across main contract and all delegatecall modules to prevent slot collisions
- Pull-pattern for ETH/stETH withdrawals; state transitions trigger complex module chains
- VRF integration with RNG locking to prevent state manipulation during callback window

## Layers

**Orchestration Layer:**
- Purpose: Core game state machine and operational entry points
- Location: `contracts/DegenerusGame.sol`
- Contains: Phase transitions, purchase routing, prize pool management, access control
- Depends on: 10 delegatecall modules, external contracts (COIN, COINFLIP, stETH, VRF), interfaces for affiliate/quest lookups
- Used by: All game interactions; external callers (players, admin)

**Delegatecall Module Layer:**
- Purpose: Encapsulate complex business logic outside main contract to manage bytecode size (<24KB limit)
- Location: `contracts/modules/` (11 module files + 2 utility modules)
- Contains:
  - `DegenerusGameMintModule`: Player mint history tracking, activity score calculation, trait generation
  - `DegenerusGameAdvanceModule`: Phase transition logic, price escalation, treasury management
  - `DegenerusGameJackpotModule`: Jackpot round execution, winner selection, payouts
  - `DegenerusGameEndgameModule`: Terminal state handling, final prize distributions
  - `DegenerusGameGameOverModule`: Game termination and settlement
  - `DegenerusGameWhaleModule`: Whale bundle purchases, lazy passes, freeze mechanics
  - `DegenerusGameLootboxModule`: Lootbox purchase and opening with EV multipliers
  - `DegenerusGameBoonModule`: Deity pass boons (special powers), boon issuing
  - `DegenerusGameDecimatorModule`: Decimator window burns and treasure distribution
  - `DegenerusGameDegeneretteModule`: Degenerette betting and resolution
  - Utilities: `DegenerusGameMintStreakUtils`, `DegenerusGamePayoutUtils`, `DegenerusGameMintStreakUtils`
- Depends on: Shared `DegenerusGameStorage`, external contracts
- Used by: DegenerusGame via delegatecall

**Storage Layer:**
- Purpose: Canonical storage layout definition and alignment
- Location: `contracts/storage/DegenerusGameStorage.sol`
- Contains: Storage slot definitions with detailed byte-layout comments, shared by main contract and all modules
- Depends on: External interfaces (VRF, Stonk for time lookups)
- Used by: DegenerusGame (inherits), all 10 delegatecall modules (must match storage layout)

**Library Layer:**
- Purpose: Reusable algorithms and bit manipulation utilities
- Location: `contracts/libraries/`
- Contains:
  - `BitPackingLib`: Mint data packing (24-bit fields: lastLevel, levelCount, levelStreak, day, frozen-until, bundle-type, units)
  - `EntropyLib`: Deterministic trait generation from tokenId via keccak256
  - `GameTimeLib`: Day boundary calculations based on 22:57 UTC reset
  - `JackpotBucketLib`: Weighted bucket distribution for decimator treasury
  - `PriceLookupLib`: Price escalation curves
- Depends on: None (pure utilities)
- Used by: DegenerusGame, modules, external contracts (DegenerusAffiliate, DegenerusJackpots)

**Token/Economic Layer:**
- Purpose: Implement token contracts and game economic mechanics
- Location: `contracts/BurnieCoin.sol`, `contracts/BurnieCoinflip.sol`, `contracts/DegenerusVault.sol`, `contracts/DegenerusJackpots.sol`
- Contains:
  - **BurnieCoin**: ERC20 (18 decimals) with game transfer bypass, coinflip integration, vault escrow (2M supply)
  - **BurnieCoinflip**: Daily 50/50 stake wagering with VRF-based 50-150% bonuses; auto-rebuy ("afKing") mode; quest credits
  - **DegenerusVault**: Perpetual vault contract holding stETH yield; mints COIN on withdrawal
  - **DegenerusJackpots**: Jackpot storage and payout tracking
- Depends on: DegenerusGame (for VRF, write control), stETH, VRF coordinator
- Used by: DegenerusGame, players

**Auxiliary Contracts:**
- Purpose: Support game mechanics and meta features
- Location: `contracts/DegenerusDeityPass.sol`, `contracts/DegenerusStonk.sol`, `contracts/DegenerusQuests.sol`, `contracts/DegenerusAffiliate.sol`, `contracts/WrappedWrappedXRP.sol`
- Contains:
  - **DegenerusDeityPass**: ERC721 with refund window; grants activity score boost; symbol-based trait rendering
  - **DegenerusStonk**: DGNRS token; claimable balance from affiliate/whale pools; emits claim signals
  - **DegenerusQuests**: Daily quest tracking; quest streak counter; activity score component
  - **DegenerusAffiliate**: Referral tracking, affiliate bonus point accumulation, pool weight calculation
  - **WrappedWrappedXRP**: WXRP2 wrapper for internal use
- Depends on: DegenerusGame (for state reads), external tokens (if applicable)
- Used by: Players, game orchestrator

**Admin & Deployment Layer:**
- Purpose: VRF subscription management, deployment setup
- Location: `contracts/DegenerusAdmin.sol`, `ContractAddresses.sol`
- Contains:
  - **DegenerusAdmin**: Single-owner VRF subscription creation and management; LINK donation handling with reward multipliers; emergency recovery
  - **ContractAddresses**: Compile-time constants for all 22 contract addresses + VRF config (all zeroed in source)
- Depends on: VRF coordinator, DegenerusGame
- Used by: Deployer, game contract

**Interface Layer:**
- Purpose: Define contract interaction boundaries and external dependencies
- Location: `contracts/interfaces/`
- Contains: Minimal external interfaces (VRF, stETH, LINK, ERC20) and protocol interfaces (IDegenerusGame, IDegenerusGameModules, module-specific interfaces)
- Depends on: None
- Used by: All contracts

## Data Flow

**Purchase Flow:**
1. Player calls `purchase(buyer, ticketQuantity, lootboxAmount, affiliateCode, paymentKind)`
2. DegenerusGame routes to module based on `paymentKind` (DirectEth, Claimable, Combined)
3. MintModule via delegatecall: Records mint data (bit-packed), calculates activity score, emits trait generation seed
4. Funds flow: ETH → futurePrizePool (10%) + currentPrizePool (90%) OR stETH if claimable used
5. Affiliate tracking: Updates referral bonus points if `affiliateCode` provided
6. Return: Player receives tickets with deterministic tokenId-based traits

**Mint → Level Progression Flow:**
1. Players purchase tickets within PURCHASE phase
2. Price escalates based on level participation curve
3. Phase transition triggered by purchase threshold or timeout
4. AdvanceModule via delegatecall:
   - Flip RNG request (triggers VRF)
   - Lock game state (RngLockedFlag=true)
   - On VRF fulfillment: Settle coinflips, distribute bounties, move to JACKPOT phase
5. JackpotModule via delegatecall: Execute winner selection and payouts
6. Return to PURCHASE phase for next level

**Lootbox EV Multiplier Flow:**
1. Player opens lootbox during PURCHASE phase
2. LootboxModule via delegatecall:
   - Calculate player activity score: `(levelCount + levelStreak + questStreak + affiliatePoints + deityPass) * baseScore`
   - Apply EV multiplier to payout if score ≥ threshold
   - Request VRF for lootbox trait if futurePrizePool ≥ threshold
3. On VRF fulfillment: Assign trait and settle payout

**Prize Pool Flow:**
1. Ticket purchases → 90% currentPrizePool + 10% futurePrizePool
2. Each level: currentPrizePool → (a) coinflip bounty, (b) last-day deposits, (c) carry-forward to next level
3. Endgame: futurePrizePool → terminal distribution + vault top-up
4. Withdrawal: Players call `claimWinnings()` with pull pattern (checks balance ≥ claimablePool)

**State Management:**
- **Storage:** All game state in DegenerusGame + shared slot layout (DegenerusGameStorage)
- **Immutable Config:** ContractAddresses constants (baked into bytecode)
- **Daily Boundaries:** GameTimeLib determines calendar day from timestamp (22:57 UTC offset)
- **RNG Lock:** Prevents state changes during VRF request→fulfillment window (18h timeout on mainnet)

## Key Abstractions

**Activity Score Multiplier:**
- Purpose: Quantify player engagement across multiple loyalty metrics
- Examples: `playerActivityScore(address)`, `activityScoreFor(address)` in DegenerusGame
- Pattern: Aggregates levelCount + levelStreak + questStreak + affiliatePoints + deityPass state
- Used for: Lootbox EV multipliers, deity pass activity bonuses, purchase multipliers

**Delegatecall Module Pattern:**
- Purpose: Extend DegenerusGame beyond 24KB bytecode limit while sharing storage
- Examples: All contracts in `contracts/modules/`
- Pattern: Module inherits DegenerusGameStorage; DegenerusGame calls via delegatecall; module executes in game context
- Constraints: Storage layout MUST match exactly; no new state vars in modules

**Bit-Packed Mint Data:**
- Purpose: Store 5 activity metrics in single uint256 for gas efficiency
- Pattern: 24-bit fields (lastLevel, levelCount, levelStreak, day, frozen-until), 3-bit bundle-type, 16-bit units
- Used for: Activity score calculation, streak tracking, whale bundle freeze mechanics

**Trait Determinism:**
- Purpose: Generate consistent traits from tokenId without external RNG
- Pattern: `keccak256(tokenId)` → 4 traits (quadrant-split); 8×8 weighted grid per trait
- Used for: NFT rendering, decorrelation from RNG manipulation

**Phase Transition with RNG Lock:**
- Purpose: Ensure VRF callback safety during state machine transitions
- Pattern: `advanceGame()` sets RngLockedFlag=true on VRF request; unlock after fulfillment
- Used for: Prevent re-entrance during jackpot phase, block nudge operations

## Entry Points

**Player Transactions:**
- Location: `contracts/DegenerusGame.sol`
- `purchase(buyer, qty, lootboxQty, affiliateCode, paymentKind)`: Mint tickets (delegates to MintModule)
- `purchaseCoin(amount)`: Direct BURNIE spending
- `purchaseWhaleBundle(quantity)`: Buy 10-level or 100-level subscription
- `purchaseLazyPass(buyer)`: One-level subscription
- `purchaseDeityPass(buyer, symbolId)`: Special ERC721 with refund window
- `openLootBox(player, index)`: Open lootbox with EV multiplier (delegates to LootboxModule)
- `placeFullTicketBets(ticketIds, betAmounts)`: Degenerette betting
- `resolveDegeneretteBets(ticketIds)`: Settle Degenerette outcomes
- `claimWinnings()`: Pull pattern withdrawal of ETH/stETH winnings

**Admin/Operator Transactions:**
- Location: `contracts/DegenerusAdmin.sol`, `contracts/DegenerusGame.sol`
- `advanceGame()`: Phase transition (delegatecall chain: Advance → Jackpot/Endgame → GameOver)
- `wireVrf(subscriptionId)`: One-time VRF setup (called by Admin on deployment)
- `setOperatorApproval(operator, approved)`: Allow operator to act for player

**VRF Callbacks:**
- Location: `contracts/modules/DegenerusGameAdvanceModule.sol`
- Triggers: On VRF fulfillment, coordinator calls back to game
- Flow: Update RNG words, unlock RNG lock, allow phase progression

**Mocks (Local Testing):**
- Location: `contracts/mocks/`
- `MockVRFCoordinator`: Simulates Chainlink VRF V2.5 with manual fulfillment
- `MockStETH`: Simulates Lido stETH yield
- `MockLinkToken`: Simulates LINK ERC677
- `MockWXRP`: Simulates Wrapped XRP

## Error Handling

**Strategy:** Custom errors (gas-efficient reverts) with minimal context

**Patterns:**
- Generic `E()` error for guard conditions (most common)
- Named errors for state machine constraints:
  - `RngLocked()`: RNG is pending (VRF callback window)
  - `AfKingLockActive()`: afKing mode still in lock period
  - `NotApproved()`: Operator approval check failed
- Module-specific errors (e.g., `RngStall` in AdvanceModule)
- No reverting with reason strings (all custom errors)

**Access Control:**
- `msg.sender == ContractAddresses.CREATOR`: Admin-only (VRF config)
- `isOperatorApproved(owner, operator)`: Operator delegation for player actions
- No other complex access lists; game-contract checks happen at call sites

## Cross-Cutting Concerns

**Logging:** Event-driven. All state changes emit events for off-chain indexing:
- `LootBoxPresaleStatus(active)`: Presale phase changes
- `OperatorApproval(owner, operator, approved)`: Delegation changes
- Game events via modules: `PrizeMoved`, `LevelAdvanced`, `JackpotWinner`, etc.

**Validation:** Inline checks at function entry:
- Address zero checks on player inputs
- Quantity/amount sanity checks (prevent overflow)
- Phase guards (e.g., can't open lootbox during jackpot phase)
- RNG lock checks on state-changing operations

**Authentication:** Fixed address-based (no upgradeable proxies):
- External calls use compile-time constants from `ContractAddresses`
- No role-based access beyond operator approval
- Single CREATOR for admin functions

---

*Architecture analysis: 2025-02-28*
