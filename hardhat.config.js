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
  "governance",
  "integration",
  "edge",
  "validation",
  "gas",
];

subtask(TASK_TEST_GET_TEST_FILES).setAction(async (args, hre) => {
  // Return ABSOLUTE paths: mocha's post-run dispose (unloadFiles) calls
  // require.resolve() on each spec, which throws MODULE_NOT_FOUND on a bare
  // relative path ("test/…") and fails the whole run at teardown even when
  // every test passed. path.resolve() is a no-op on already-absolute paths.
  if (args.testFiles && args.testFiles.length > 0) {
    return args.testFiles.map((f) => path.resolve(f)); // explicit CLI files
  }
  const testDir = hre.config.paths.tests;
  const ordered = [];
  for (const dir of TEST_DIR_ORDER) {
    const files = await glob(path.join(testDir, dir, "**", "*.test.js"));
    ordered.push(...files.sort());
  }
  return ordered.map((f) => path.resolve(f));
});

/** @type import("hardhat/config").HardhatUserConfig */
const config = {
  solidity: {
    compilers: [
      {
        version: "0.8.34",
        settings: {
          viaIR: true,
          // L1 mainnet deploy target. Must be explicit: hardhat falls back to
          // paris for solc versions it does not recognize.
          evmVersion: "osaka",
          optimizer: {
            enabled: true,
            runs: 1000
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
      accounts: { count: 310 },
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
