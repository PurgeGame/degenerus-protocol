import "@nomicfoundation/hardhat-toolbox";
import "dotenv/config";
import { TASK_TEST_GET_TEST_FILES } from "hardhat/builtin-tasks/task-names.js";
import { subtask } from "hardhat/config.js";
import { glob } from "hardhat/internal/util/glob.js";
import path from "node:path";

// Override default test file discovery to control ordering.
const TEST_DIR_ORDER = [
  "access",
  "deploy",
  "unit",
  "integration",
  "edge",
  "validation",
  "gas",
];

subtask(TASK_TEST_GET_TEST_FILES).setAction(async (args, hre) => {
  if (args.testFiles && args.testFiles.length > 0) {
    return args.testFiles; // explicit files passed on CLI — honour as-is
  }
  const testDir = hre.config.paths.tests;
  const ordered = [];
  for (const dir of TEST_DIR_ORDER) {
    const files = await glob(path.join(testDir, dir, "**", "*.test.js"));
    ordered.push(...files.sort());
  }
  return ordered;
});

/** @type import("hardhat/config").HardhatUserConfig */
const config = {
  solidity: {
    compilers: [
      {
        version: "0.8.34",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 200
          },
          outputSelection: {
            "*": {
              "*": ["storageLayout"]
            }
          }
        }
      }
    ]
  },
  paths: {
    sources: "./contracts",
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
