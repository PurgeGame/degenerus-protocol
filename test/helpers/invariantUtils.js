/**
 * @file invariantUtils.js
 * @description ETH solvency invariant helpers for Degenerus protocol audit (Phase 08).
 *
 * The core solvency invariant is:
 *   game.balance + steth.balanceOf(game) >= currentPrizePool + nextPrizePool + futurePrizePool + claimablePool
 *
 * This mirrors the yieldPoolView() internal calculation in DegenerusGame.
 *
 * IMPORTANT: Only public view getters are used — no raw storage reads.
 * This ensures the invariant reflects the same values the contract operates on.
 *
 * NOTE on 1-wei sentinel: After claimWinnings(), claimablePool is NOT zero.
 * Each claim leaves a 1 wei sentinel in claimableWinnings[player] which is
 * included in claimablePool accounting. Do NOT assert claimablePool == 0 after claiming.
 */

import hre from "hardhat";
import { expect } from "chai";

/**
 * Assert the ETH solvency invariant for the DegenerusGame contract.
 *
 * Checks: balance(game) + stethBalance(game) >= currentPool + nextPool + futurePool + claimablePool
 *
 * @param {Contract} game - DegenerusGame contract instance
 * @param {Contract} steth - stETH contract (MockStETH or real stETH)
 */
export async function assertSolvencyInvariant(game, steth) {
  const gameAddr = await game.getAddress();
  const ethBal = await hre.ethers.provider.getBalance(gameAddr);
  const stethBal = await steth.balanceOf(gameAddr);
  const total = ethBal + stethBal;

  const current = await game.currentPrizePoolView();
  const next = await game.nextPrizePoolView();
  const future = await game.futurePrizePoolView(0n); // 0n = current future pool (BigInt required for uint24)
  const claimable = await game.claimablePoolView();
  const obligations = current + next + future + claimable;

  expect(total).to.be.gte(
    obligations,
    [
      `Solvency invariant violated!`,
      `  balance:      ${total}`,
      `  obligations:  ${obligations}`,
      `  deficit:      ${obligations - total}`,
      `  current:      ${current}`,
      `  next:         ${next}`,
      `  future:       ${future}`,
      `  claimable:    ${claimable}`,
    ].join("\n")
  );
}

/**
 * Assert that claimablePool >= sum of individual claimableWinnings for given players.
 *
 * Used to verify the aggregate pool is at least as large as the sum of per-player
 * credits (it may be larger due to 1-wei sentinels).
 *
 * @param {Contract} game - DegenerusGame contract instance
 * @param {string[]} players - Array of player addresses to check
 */
export async function assertClaimablePoolConsistency(game, players) {
  const claimablePool = await game.claimablePoolView();
  let sumWinnings = 0n;
  for (const p of players) {
    const w = await game.claimableWinningsOf(p);
    sumWinnings += w;
  }
  expect(claimablePool).to.be.gte(
    sumWinnings,
    `claimablePool ${claimablePool} < sum(claimableWinnings) ${sumWinnings}`
  );
}
