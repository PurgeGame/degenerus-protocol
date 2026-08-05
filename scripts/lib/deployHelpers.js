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
 *
 * ## ⛔ The ordering trap
 *
 * `_paths[i]` is indexed by tokenId (`quadrant*8 + symbolIdx`) and `_symQ3[idx]`
 * by symbolIdx, so slot 16+s must hold the icon for cards symbolIdx s. The
 * legacy fixture `data/icons32Data.json` is ordered by badge FILE index
 * instead: the two coincide for crypto and zodiac and DIVERGE for cards.
 * Wiring the raw fixture gives every cards pass the wrong name AND glyph.
 *
 * `data/icons32Data.symbolOrder.json` has `CARD_IDX=[3,4,5,6,0,2,1,7]` already
 * applied to `paths[16..23]` and `symQ3`, matching the order every consumer
 * encodes (database `src/api/routes/player.ts`, `app/app/dgn-traits.js`,
 * `beta/app/constants.js`). Quick tell: `symQ3[0]` must be `Club`.
 *
 * @param {import("ethers").Contract} icons32 - Icons32Data connected as CREATOR
 * @param {{paths: string[], symQ1: string[], symQ2: string[], symQ3: string[]}} iconsData
 *   Parsed scripts/data/icons32Data.symbolOrder.json (its legacy `diamond` key
 *   is unused — the current contract folds that icon into the 33-slot array)
 * @param {{finalize?: boolean}} [opts] - finalize() is IRREVERSIBLE and opt-in;
 *   verify the wired data on-chain first, then lock it as a deliberate step.
 */
export async function wireIcons32(icons32, iconsData, opts = {}) {
  const { finalize = false } = opts;
  if (iconsData.paths.length !== 33) {
    throw new Error(
      `icons32 dataset must hold exactly 33 paths, got ${iconsData.paths.length}`
    );
  }
  for (const q of ["symQ1", "symQ2", "symQ3"]) {
    if (!Array.isArray(iconsData[q]) || iconsData[q].length !== 8) {
      throw new Error(`icons32 dataset ${q} must hold exactly 8 names`);
    }
  }
  // Ordering guard: catches the file-ordered fixture being wired by mistake.
  if (iconsData.symQ3[0] !== "Club") {
    throw new Error(
      `icons32 dataset looks FILE-ordered, not symbol-ordered: symQ3[0] is ` +
        `${JSON.stringify(iconsData.symQ3[0])}, expected "Club". Apply ` +
        `CARD_IDX=[3,4,5,6,0,2,1,7] to paths[16..23] and symQ3 before wiring.`
    );
  }
  for (let start = 0; start < 33; start += 10) {
    const batch = iconsData.paths.slice(start, Math.min(start + 10, 33));
    await (await icons32.setPaths(start, batch)).wait();
  }
  await (await icons32.setSymbols(0, iconsData.symQ1)).wait();
  await (await icons32.setSymbols(1, iconsData.symQ2)).wait();
  await (await icons32.setSymbols(2, iconsData.symQ3)).wait();
  if (finalize) {
    await (await icons32.finalize()).wait();
  }
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
