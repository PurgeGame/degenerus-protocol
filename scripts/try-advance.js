import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  ATTEMPTING advanceGame WITH 40 LINK IN SUBSCRIPTION          ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  console.log("Current state:");
  const level = await game.level();
  const gameState = await game.gameState();
  console.log("  Level:", level.toString());
  console.log("  Game State:", gameState.toString(), "(2=PURCHASE)");
  console.log();

  console.log("Calling advanceGame(100)...");

  try {
    const tx = await game.connect(deployer).advanceGame(100, {
      gasLimit: 5000000,
      gasPrice: 1000000000
    });
    console.log("TX sent:", tx.hash);
    console.log("Waiting for confirmation...");
    
    const receipt = await tx.wait();
    console.log("\n✅ SUCCESS!");
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("TX:", `https://sepolia.etherscan.io/tx/${receipt.hash}`);

    // Check new state
    const newLevel = await game.level();
    const newGameState = await game.gameState();
    console.log("\n📊 New state:");
    console.log("  Level:", newLevel.toString());
    console.log("  Game State:", newGameState.toString());

  } catch (error) {
    console.log("\n❌ Still failing");
    console.log("Error:", error.message.substring(0, 200));
    
    if (error.receipt) {
      console.log("\nView failed TX:", `https://sepolia.etherscan.io/tx/${error.receipt.hash}`);
    }
  }
}

main().catch(console.error);
