import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("Testing advanceGame with VRF V2.5...\n");

  const level = await game.level();
  const gameState = await game.gameState();
  console.log("Current level:", level.toString());
  console.log("Current state:", gameState.toString());
  console.log();

  // Advance dailyIdx first (for testnet)
  console.log("Advancing dailyIdx...");
  try {
    const tx1 = await admin.connect(deployer).advanceDailyIdx(1, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx1.wait();
    console.log("✓ dailyIdx advanced\n");
  } catch (e) {
    console.log("⚠️  Could not advance dailyIdx\n");
  }

  // Try advanceGame
  console.log("Calling advanceGame(100)...");
  try {
    const tx2 = await game.connect(deployer).advanceGame(100, {
      gasLimit: 5000000,
      gasPrice: 1000000000
    });
    console.log("TX sent:", tx2.hash);
    const receipt = await tx2.wait();
    console.log("\n✅ SUCCESS!");
    console.log("Gas used:", receipt.gasUsed.toString());
    console.log("View TX: https://sepolia.etherscan.io/tx/" + receipt.hash);
    
    const newLevel = await game.level();
    const newState = await game.gameState();
    console.log("\nNew level:", newLevel.toString());
    console.log("New state:", newState.toString());
  } catch (error) {
    console.log("\n❌ FAILED");
    console.log("Error:", error.message.substring(0, 300));
    if (error.receipt) {
      console.log("View TX: https://sepolia.etherscan.io/tx/" + error.receipt.hash);
    }
  }
}

main().catch(console.error);
