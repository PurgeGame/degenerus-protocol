import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";

const isTestnetBuild = process.env.TESTNET_BUILD === "1";

/** @type import("hardhat/config").HardhatUserConfig */
const config = {
  solidity: {
    compilers: [
      {
        version: "0.8.26",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 2
          }
        }
      },
      {
        version: "0.8.28",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 2
          }
        }
      }
    ]
  },
  paths: {
    sources: isTestnetBuild ? "./contracts-testnet" : "./contracts",
    cache: isTestnetBuild ? "cache-testnet" : "cache",
    artifacts: isTestnetBuild ? "artifacts-testnet" : "artifacts",
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
    mainnet: {
      url: process.env.RPC_URL || "",
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || process.env.RPC_URL || "",
      accounts: process.env.DEPLOYER_PRIVATE_KEY
        ? [process.env.DEPLOYER_PRIVATE_KEY]
        : [],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY || "",
  },
  mocha: {
    timeout: 120_000,
  },
};

export default config;
