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
 * Wire Icons32Data with the production icon set and lock it.
 *
 * Loads all 33 SVG paths (32 quadrant symbols + the affiliate badge at
 * index 32) in batches of 10 (the contract's MaxBatch), then the three
 * stored name arrays. Quadrants are 0-based on this contract:
 * setSymbols(0) = crypto (symQ1), 1 = zodiac (symQ2), 2 = cards (symQ3);
 * quadrant 3 (dice) stores no names — renderers generate "Dice N".
 * Ends with finalize(), locking the data permanently, so the caller must
 * be CREATOR and the icon JSON must be final before this runs.
 *
 * @param {import("ethers").Contract} icons32 - Icons32Data connected as CREATOR
 * @param {{paths: string[], symQ1: string[], symQ2: string[], symQ3: string[]}} iconsData
 *   Parsed scripts/data/icons32Data.json (its legacy `diamond` key is unused —
 *   the current contract folds that icon into the 33-slot path array)
 */
export async function wireIcons32(icons32, iconsData) {
  if (iconsData.paths.length !== 33) {
    throw new Error(
      `icons32Data.json must hold exactly 33 paths, got ${iconsData.paths.length}`
    );
  }
  for (const q of ["symQ1", "symQ2", "symQ3"]) {
    if (!Array.isArray(iconsData[q]) || iconsData[q].length !== 8) {
      throw new Error(`icons32Data.json ${q} must hold exactly 8 names`);
    }
  }
  for (let start = 0; start < 33; start += 10) {
    const batch = iconsData.paths.slice(start, Math.min(start + 10, 33));
    await (await icons32.setPaths(start, batch)).wait();
  }
  await (await icons32.setSymbols(0, iconsData.symQ1)).wait();
  await (await icons32.setSymbols(1, iconsData.symQ2)).wait();
  await (await icons32.setSymbols(2, iconsData.symQ3)).wait();
  await (await icons32.finalize()).wait();
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
