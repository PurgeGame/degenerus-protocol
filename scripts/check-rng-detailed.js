import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  DETAILED RNG STATUS                                           ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  try {
    const rngFulfilled = await game.isRngFulfilled();
    console.log("RNG Fulfilled:", rngFulfilled);
  } catch (e) {
    console.log("RNG Fulfilled: (error)");
  }

  try {
    const pendingRngId = await game.pendingRngId();
    console.log("Pending RNG ID:", pendingRngId.toString());
  } catch (e) {
    console.log("Pending RNG ID: (error)");
  }

  try {
    const rngRequestTime = await game.rngRequestTime();
    console.log("RNG Request Time:", rngRequestTime.toString());
    if (rngRequestTime > 0) {
      const now = Math.floor(Date.now() / 1000);
      const elapsed = now - Number(rngRequestTime);
      console.log("  Elapsed:", elapsed, "seconds (", Math.floor(elapsed / 60), "minutes )");
      console.log("  18-hour timeout:", elapsed >= 18 * 3600 ? "EXCEEDED" : "not yet");
    }
  } catch (e) {
    console.log("RNG Request Time: (error)");
  }

  try {
    const rngLockedFlag = await game.rngLockedFlag();
    console.log("RNG Locked Flag:", rngLockedFlag);
  } catch (e) {
    console.log("RNG Locked Flag: (error)");
  }

  try {
    const dailyIdx = await game.dailyIdx();
    console.log("\nDaily Index (stored):", dailyIdx.toString());
  } catch (e) {
    console.log("\nDaily Index: (error)");
  }

  try {
    const level = await game.level();
    const gameState = await game.gameState();
    console.log("\nLevel:", level.toString());
    console.log("Game State:", gameState.toString());
  } catch (e) {
    console.log("\nLevel/State: (error)");
  }
}

main().catch(console.error);
