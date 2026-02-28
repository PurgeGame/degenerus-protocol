# Technology Stack

**Analysis Date:** 2026-02-28

## Languages

**Primary:**
- Solidity 0.8.26 - Smart contracts (majority of contracts)
- Solidity 0.8.28 - Smart contracts (alternative compiler version for optimization)
- JavaScript (ES modules) - Scripts, tests, and CLI tools

**Secondary:**
- None

## Runtime

**Environment:**
- Node.js v22.22.0+ (runtime)
- Hardhat 2.28.3 - Ethereum development framework and testing environment

**Package Manager:**
- npm 10.9.4+
- Lockfile: `package-lock.json` (present)

## Frameworks

**Core Smart Contract Framework:**
- Hardhat ^2.28.3 - Compilation, testing, deployment orchestration
- @nomicfoundation/hardhat-toolbox ^6.1.0 - Integrated toolchain (ethers.js, chai, etc.)

**Smart Contract Libraries:**
- OpenZeppelin Contracts ^5.4.0 - Standard ERC token implementations and utilities
  - Used for: ERC20, ERC721, ERC1155, AccessControl, ECDSA, etc.
  - Provides base classes for BURNIE coin, NFTs, and access patterns

**Testing:**
- Mocha - Test runner (via Hardhat)
- Chai - Assertion library (via hardhat-toolbox)
- Ethers.js v6 - Contract interaction and signing (via hardhat-toolbox)

**Build/Dev:**
- Hardhat Compiler with viaIR optimization enabled
  - viaIR: true (uses intermediate representation for better optimization)
  - optimizer runs: 2 (aggressive optimization for bytecode size)
- dotenv ^17.3.1 - Environment variable management

**Database:**
- better-sqlite3 ^12.6.2 - Synchronous SQLite3 for event indexing and analysis
  - Used for: Event logs, ticket tracking, analysis database generation
  - Supports WAL mode for concurrent reads

**Server/Networking:**
- express ^5.2.1 - Web framework for dashboard and simulation API
- socket.io ^4.8.3 - WebSocket for real-time simulation stats broadcasting

**Utilities:**
- ethers ^6.x (via hardhat-toolbox) - Blockchain interaction library
- marked ^17.0.3 - Markdown parsing (for documentation generation)

## Key Dependencies

**Critical:**
- Hardhat ^2.28.3 - Required for development, testing, compilation, and deployment
- OpenZeppelin Contracts ^5.4.0 - Provides essential token and access control patterns
- ethers.js v6 - Required for contract deployment and interaction scripts
- better-sqlite3 ^12.6.2 - Required for event indexing and simulation analysis

**Infrastructure:**
- @nomicfoundation/hardhat-toolbox ^6.1.0 - Bundled test and development utilities
- express ^5.2.1 - Required for testnet dashboard and simulation server
- socket.io ^4.8.3 - Required for real-time simulation UI updates
- dotenv ^17.3.1 - Required for environment configuration loading

## Configuration

**Environment:**
Configuration via `.env` file (see `.env.example` for template).

**Key Configuration Variables:**
- `DEPLOYER_PRIVATE_KEY` - EOA private key for contract deployment
- `RPC_URL` - Ethereum mainnet RPC endpoint
- `SEPOLIA_RPC_URL` - Sepolia testnet RPC endpoint (overridable via PURGE_RPC_URL)
- `ETHERSCAN_API_KEY` - Block explorer verification key
- `STETH_TOKEN` - Lido stETH token address (default: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84)
- `LINK_TOKEN` - Chainlink LINK token address (default: 0x514910771AF9Ca656af840dff83E8264EcF986CA)
- `VRF_COORDINATOR` - Chainlink VRF V2.5 coordinator address (default: 0x271682DEB8C4E0901D1a1550aD2e64D568E69909)
- `VRF_KEY_HASH` - VRF keyhash for randomness (mainnet default: 0x8af398995b04c28e9951adb9721ef74c74f93e6a478f39e7e0777be13527e7ef)
- `WXRP` - Wrapped XRP token address (optional, defaults to zero address)
- `AFFILIATE_BOOTSTRAP_JSON` - Pre-seed affiliate codes at deployment
- `AFFILIATE_PREFERRALS_JSON` - Pre-seed player referral mappings

**Hardhat Configuration:**
- File: `hardhat.config.js` (ESM)
- Compiler versions: 0.8.26, 0.8.28
- Optimizer: enabled, runs=2, viaIR=true
- Networks: hardhat (local), localhost (forked), mainnet, sepolia
- Mocha timeout: 120 seconds

**Testnet Build:**
- `TESTNET_BUILD=1` - Environment flag to use testnet-specific contracts
  - Changes build paths: `contracts-testnet/` instead of `contracts/`
  - Separate cache/artifacts directories for test builds

## Platform Requirements

**Development:**
- Linux/macOS/Windows environment
- Node.js v22+ with npm v10+
- Hardhat local test node (ganache-compatible)
- RPC endpoint access for mainnet/testnet deployments
- Private key with sufficient gas for mainnet deployments

**Production (Mainnet):**
- Deployed to Ethereum mainnet via RPC
- Requires 22 sequentially deployed contracts (CREATE2-based nonce prediction)
- VRF V2.5 subscription with LINK funding on Chainlink
- Lido stETH smart contract integration for yield strategies
- Block explorer verification via Etherscan API

**Testnet (Sepolia):**
- Sepolia testnet RPC endpoint
- Chainlink VRF V2.5 on Sepolia (testnet coordinator)
- Test LINK and ETH funding
- Dynamic contract size scaling (TESTNET_BUILD flag)
- SQLite event database in `runs/` directory

---

*Stack analysis: 2026-02-28*
