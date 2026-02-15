import "@nomicfoundation/hardhat-toolbox";

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
    sources: "./contracts",
    cache: "cache",
    artifacts: "artifacts"
  }
};

export default config;
