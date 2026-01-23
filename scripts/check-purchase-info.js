import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);

  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();

  console.log("purchaseInfo() results:");
  console.log("  Level:", level.toString());
  console.log("  Game State:", gameState.toString());
  console.log("  Last Purchase Day:", lastPurchaseDay);
  console.log("  RNG Locked:", rngLocked);
  console.log("  Price (wei):", priceWei.toString());

  const actualLevel = await game.level();
  const actualState = await game.gameState();
  console.log("\nDirect state reads:");
  console.log("  game.level():", actualLevel.toString());
  console.log("  game.gameState():", actualState.toString());
}

main().catch(console.error);
