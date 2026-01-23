import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

console.log("Current game state:");
const level = await game.level();
const gameState = await game.gameState();
console.log("  Level:", level.toString());
console.log("  State:", gameState.toString());

// Try to get dailyIdx if we can
try {
  const dailyIdx = await game.dailyIdx();
  console.log("  DailyIdx:", dailyIdx.toString());
} catch (e) {
  console.log("  DailyIdx: (not accessible)");
}

console.log("\nTrying advanceGame to see error:");
try {
  await game.advanceGame.staticCall(100);
  console.log("  ✅ advanceGame would succeed!");
} catch (error) {
  console.log("  ❌ Error:", error.message.substring(0, 150));
}
