import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

console.log("\n🧪 Simple VRF Test\n");

const level = await game.level();
const gameState = await game.gameState();

console.log("Current state: Level", level.toString(), "State", gameState.toString());
console.log("");

console.log("Calling advanceGame(0)...");
try {
  const tx = await game.connect(deployer).advanceGame(0, {
    gasLimit: 5000000
  });

  console.log("TX hash:", tx.hash);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log("✅ Transaction confirmed");
  console.log("Gas used:", receipt.gasUsed.toString());
  console.log("");

  // Check if state changed
  const newLevel = await game.level();
  const newState = await game.gameState();
  console.log("New state: Level", newLevel.toString(), "State", newState.toString());

  if (newLevel !== level || newState !== gameState) {
    console.log("✅ State changed immediately (no VRF needed)");
  } else {
    console.log("⏳ Waiting for VRF fulfillment...");
    console.log("");

    // Wait up to 2 minutes
    for (let i = 0; i < 12; i++) {
      await new Promise(r => setTimeout(r, 10000));

      const checkLevel = await game.level();
      const checkState = await game.gameState();

      const elapsed = (i+1)*10;
      console.log("  " + elapsed + "s: Level " + checkLevel + " State " + checkState);

      if (checkLevel !== level || checkState !== gameState) {
        console.log("✅ VRF fulfilled!");
        break;
      }
    }
  }

} catch (error) {
  console.error("❌ Error:", error.message);
}
