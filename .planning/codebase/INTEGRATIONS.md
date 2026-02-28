# External Integrations

**Analysis Date:** 2026-02-28

## APIs & External Services

**Chainlink VRF V2.5 (Random Number Generation):**
- Service: Chainlink VRF V2.5 for verifiable randomness
  - SDK/Client: Direct contract interface `IVRFCoordinatorV2_5Owner`
  - Mainnet Coordinator: `0x271682DEB8C4E0901D1a1550aD2e64D568E69909`
  - Sepolia Coordinator: `0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B`
  - Key Hash (Mainnet): `0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef`
  - Configuration: VRF subscription ID and keyhash stored in `ContractAddresses.sol`
  - Admin Contract: `DegenerusAdmin.sol` owns VRF subscription
  - Game Contract: `DegenerusGame.sol` is consumer on VRF subscription

**Chainlink LINK Token:**
- Service: ERC-677 token for VRF subscription funding
  - SDK/Client: Direct contract interface `ILinkTokenLike`
  - Mainnet Address: `0x514910771AF9Ca656af840dff83E8264EcF986CA`
  - Sepolia Address: `0x779877A7B0D9E8603169DdbD7836e478b4624789`
  - Usage: Funded to VRF subscription via ERC-677 transferAndCall
  - Admin funding flow: LINK.transferAndCall(adminAddr, amount, "0x") → Admin.onTokenTransfer() → relays to subscription

**Chainlink LINK/ETH Price Feed:**
- Service: Price oracle for LINK donation valuation
  - SDK/Client: AggregatorV3 interface `IAggregatorV3`
  - Used for: Converting LINK donation amounts to BURNIE rewards
  - Configuration: Feed address stored in `DegenerusAdmin.linkEthPriceFeed`
  - Decimals: 18 decimals (Chainlink standard for LINK/ETH pair)
  - Max staleness: 1 day (feed considered unhealthy if older)
  - Validation: Feed can only be replaced if current feed is unhealthy (FeedHealthy guard)
  - Location: `DegenerusAdmin.sol` lines 324-338 (feed state and constants)

**Block Explorer (Etherscan):**
- Service: Contract verification and inspection
  - SDK/Client: Etherscan API via Hardhat etherscan plugin
  - Configuration: API key via `ETHERSCAN_API_KEY` env var
  - Used in: `hardhat.config.js` etherscan.apiKey

## Data Storage

**Databases:**
- **SQLite (better-sqlite3):** Local event database for off-chain analysis
  - Connection: File-based, no credentials required
  - Location: `runs/{timestamp}/events.db` for each local run
  - Client: better-sqlite3 native module
  - Usage: Event log ingestion, ticket tracking, level analysis
  - Modes: Read-only for events DB, write with WAL for analysis DB
  - Schema: Created dynamically in `scripts/testnet/build-analysis-db.js`
  - Tables: level_tickets, level_summary, jackpot_results, verification

**Blockchain State (Ethereum/Sepolia):**
- Primary data storage via smart contracts
- State persisted on-chain via Solidity storage
- No external database; all game state in ContractAddresses-referenced contracts

**File Storage:**
- Local filesystem only (SQLite databases in `runs/` directory)
- Deployment manifests saved to `deployments/{network}-{timestamp}.json`
- No cloud storage integration

**Caching:**
- None (application logic is stateless)

## Authentication & Identity

**Auth Provider:**
- Custom (on-chain verification)

**Implementation Approach:**
- Private key signing via ethers.js for transaction authorization
- On-chain access control via OpenZeppelin AccessControl patterns
- Owner verification: `DegenerusAdmin.onlyOwner()` checks CREATOR or VAULT holder (>30% DGVE)
- Vault ownership check: `IDegenerusVaultOwner.isVaultOwner(account)` for multi-sig approval
- No external OAuth or centralized auth service

## Monitoring & Observability

**Error Tracking:**
- None (errors logged to stdout/stderr)

**Logs:**
- Console logs (stdout) from test and deployment scripts
- Event logs indexed from contract emissions via event listeners
- Testnet event logger: `scripts/testnet/event-logger.js`
- Analysis: Built from events via `scripts/testnet/build-analysis-db.js`
- No centralized logging service

## CI/CD & Deployment

**Hosting:**
- Ethereum Mainnet (primary network)
- Sepolia Testnet (secondary network for testing)
- Local Hardhat node (development environment)

**CI Pipeline:**
- None detected (manual deployment via scripts)
- Deploy scripts: `scripts/deploy.js` (mainnet), `scripts/deploy-sepolia-testnet.js` (testnet)
- Testnet automation: `scripts/testnet/run-sepolia.js` for continuous bot simulation
- Local testing: `scripts/testnet/run-local.js` starts full node, deploys, bootstraps, and runs orchestrator

**Deployment Process:**
1. Predict nonce-based contract addresses via `predictAddresses.js`
2. Compute deploy day boundary from timestamp
3. Patch `ContractAddresses.sol` with predicted addresses and external configs
4. Recompile with patched constants
5. Deploy in order via `DEPLOY_ORDER` (22 contracts sequentially)
6. Verify addresses match predictions
7. Save deployment manifest to `deployments/` directory
8. Restore `ContractAddresses.sol` to zeroed state

## Environment Configuration

**Required env vars (with defaults where applicable):**
```
# Critical
DEPLOYER_PRIVATE_KEY          # Hex or raw (required for mainnet/testnet)
RPC_URL                        # Ethereum mainnet RPC (required for mainnet deploy)
SEPOLIA_RPC_URL               # Sepolia RPC (required for Sepolia deploy)
VRF_COORDINATOR               # Default: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909 (mainnet)
VRF_KEY_HASH                  # Default: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef
LINK_TOKEN                    # Default: 0x514910771AF9Ca656af840dff83E8264EcF986CA (mainnet)
STETH_TOKEN                   # Default: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 (Lido stETH)

# Optional
ETHERSCAN_API_KEY            # For contract verification
WXRP                          # Wrapped XRP token (optional)
AFFILIATE_BOOTSTRAP_JSON      # Pre-seed affiliate codes
AFFILIATE_PREFERRALS_JSON     # Pre-seed referrals
TESTNET_BUILD                 # Flag to use testnet-specific contracts

# Optional: Sepolia testing
HARDHAT_FORK_URL             # For forking tests
RUN_SEPOLIA_ACTOR_TESTS      # Enable adversarial actor tests
SEPOLIA_EVENTS_DB            # Path to events database
SEPOLIA_FORK_BLOCK           # Block number to fork from
```

**Secrets location:**
- `.env` file (Git-ignored, not committed)
- `.env.example` provided as template (secrets removed)

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- VRF callback: `DegenerusGame.fulfillRandomWords()` called by Chainlink VRF on randomness fulfillment
- Event emission callbacks: Hardhat event listeners in scripts consume contract events
- Socket.io broadcasts: `dashboard-server.js` emits stats to connected clients

## External Dependencies (Ethereum Mainnet)

| Service | Address | Purpose |
|---------|---------|---------|
| Chainlink VRF V2.5 | 0x271682DEB8C4E0901D1a1550aD2e64D568E69909 | Verifiable randomness |
| Chainlink LINK Token | 0x514910771AF9Ca656af840dff83E8264EcF986CA | VRF funding |
| Lido stETH | 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84 | Yield-bearing staked ETH |
| Chainlink LINK/ETH Feed | (configurable) | Price oracle for donations |

## External Dependencies (Sepolia Testnet)

| Service | Address | Purpose |
|---------|---------|---------|
| Chainlink VRF V2.5 | 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B | Verifiable randomness |
| Chainlink LINK Token | 0x779877A7B0D9E8603169DdbD7836e478b4624789 | VRF funding |

## Contract Integration Points

**DegenerusAdmin.sol:**
- Owns VRF subscription on Chainlink VRF V2.5
- Manages LINK donations and conversion to BURNIE rewards
- Configures LINK/ETH price feed for oracle valuation
- Wires VRF config to Game contract on initialization
- Location: `contracts/DegenerusAdmin.sol`

**DegenerusGame.sol:**
- Consumer on VRF subscription
- Requests randomness via VRF coordinator
- Implements `fulfillRandomWords()` callback for VRF responses
- Holds ETH and stETH for yield strategies
- Calls stETH for staking/unstaking
- Location: `contracts/DegenerusGame.sol`

**DegenerusVault.sol:**
- Stores and manages stETH yield
- Integrated with Lido for staking operations
- Checks vault ownership for access control (>30% DGVE)
- Location: `contracts/DegenerusVault.sol`

## Data Flow Examples

**VRF Random Request Flow:**
1. Game initiates randomness request to VRF coordinator
2. VRF coordinator generates random number
3. Chainlink node fulfills callback to `DegenerusGame.fulfillRandomWords()`
4. Game contract processes result (game advancement, level rewards, etc.)

**LINK Donation Flow:**
1. Player transfers LINK token with Admin address as recipient
2. LINK implements ERC-677 `transferAndCall()` callback
3. Admin.onTokenTransfer() is called with LINK amount
4. Admin converts LINK to ETH price using LINK/ETH feed
5. Admin credits Coin contract with BURNIE equivalent via creditLinkReward()
6. Player can use BURNIE credit for coinflip betting

**Staking Flow:**
1. Admin or authorized operator calls `adminStakeEthForStEth()`
2. Game contract deposits ETH with Lido staking contract
3. Lido returns stETH at 1:1 ratio
4. stETH held in Game for yield accumulation
5. Yield rewards accrue automatically via Lido

---

*Integration audit: 2026-02-28*
