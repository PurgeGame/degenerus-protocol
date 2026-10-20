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
 *   must match the immutable constructor option; completion finalizes automatically.
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
  if ([...iconsData.paths, ...iconsData.symQ1, ...iconsData.symQ2, ...iconsData.symQ3].some(s => typeof s !== "string" || s.length === 0)) {
    throw new Error("Initial icon entries must be nonempty strings");
  }
  if (await icons32.finalizeOnBootstrap() !== finalize) {
    throw new Error("Finalization option differs from the deployed immutable option");
  }
  let mask = await icons32.initializedMask();
  const complete = (1n << 36n) - 1n;
  // Validate every existing entry before sending any transaction (especially the final upload).
  for (let i = 0; i < 33; ++i) {
    if ((mask & (1n << BigInt(i))) !== 0n && await icons32.data(i) !== iconsData.paths[i]) {
      throw new Error(`Existing icon path ${i} differs from dataset; correction requires governance`);
    }
  }
  for (let q = 0; q < 3; ++q) {
    if ((mask & (1n << BigInt(33 + q))) !== 0n) {
      for (let i = 0; i < 8; ++i) {
        if (await icons32.symbol(q, i) !== iconsData[`symQ${q + 1}`][i]) {
          throw new Error(`Existing symbol ${q}/${i} differs from dataset; correction requires governance`);
        }
      }
    }
  }
  if (await icons32.bootstrapClosed() && mask !== complete) {
    throw new Error("Icon bootstrap was closed before completion; remaining setup requires governance");
  }
  for (let start = 0; start < 33;) {
    if ((mask & (1n << BigInt(start))) !== 0n) { ++start; continue; }
    let end = start + 1;
    while (end < 33 && end - start < 10 && (mask & (1n << BigInt(end))) === 0n) ++end;
    await (await icons32.setPaths(start, iconsData.paths.slice(start, end))).wait();
    start = end;
  }
  for (let q = 0; q < 3; ++q) {
    if ((mask & (1n << BigInt(33 + q))) === 0n) {
      await (await icons32.setSymbols(q, iconsData[`symQ${q + 1}`])).wait();
    }
  }
  for (let i = 0; i < 33; ++i) {
    if (await icons32.data(i) !== iconsData.paths[i]) throw new Error(`Icon path ${i} readback failed`);
  }
  for (let q = 0; q < 3; ++q) {
    for (let i = 0; i < 8; ++i) {
      if (await icons32.symbol(q, i) !== iconsData[`symQ${q + 1}`][i]) throw new Error(`Symbol ${q}/${i} readback failed`);
    }
  }
  if (!await icons32.bootstrapClosed() || (finalize && !await icons32.finalized())) {
    throw new Error("Icon setup did not close/finalize as requested");
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
