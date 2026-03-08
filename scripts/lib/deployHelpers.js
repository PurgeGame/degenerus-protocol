/**
 * Deploy a contract and wait for it to be mined.
 * @param {import("hardhat")} hre - Hardhat Runtime Environment
 * @param {string} contractName - Solidity contract name
 * @param {any[]} [args=[]] - Constructor arguments
 * @returns {Promise<import("ethers").Contract>} Deployed contract instance
 */
export async function deployContract(hre, contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

/**
 * Assert all predicted addresses match deployed addresses.
 * @param {Map<string, string>} predicted - Predicted address map
 * @param {Map<string, string>} deployed - Deployed address map
 */
export function verifyAddresses(predicted, deployed) {
  const mismatches = [];
  for (const [key, expectedAddr] of predicted) {
    const actualAddr = deployed.get(key);
    if (!actualAddr) {
      mismatches.push(`${key}: not deployed`);
    } else if (actualAddr.toLowerCase() !== expectedAddr.toLowerCase()) {
      mismatches.push(
        `${key}: expected ${expectedAddr}, got ${actualAddr}`
      );
    }
  }
  if (mismatches.length > 0) {
    throw new Error(
      `Address verification failed:\n${mismatches.join("\n")}`
    );
  }
}
