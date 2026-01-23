import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  COMPREHENSIVE GAME STATE DIAGNOSIS                            ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  // Game state
  const level = await game.level();
  const gameState = await game.gameState();
  const mintPrice = await game.mintPrice();
  console.log("GAME STATE:");
  console.log("  Level:", level.toString());
  console.log("  GameState:", gameState.toString(), "(1=SETUP, 2=PURCHASE, 3=BURN)");
  console.log("  Mint Price:", ethers.formatEther(mintPrice), "ETH\n");

  // Time-related
  try {
    const dailyIdx = await admin.dailyIdx();
    console.log("TIME STATE:");
    console.log("  Daily Index:", dailyIdx.toString(), "\n");
  } catch (e) {
    console.log("TIME STATE: (error accessing dailyIdx)\n");
  }

  // Try staticCall on advanceGame
  console.log("TESTING advanceGame:");
  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  try {
    await game.connect(deployer).advanceGame.staticCall(100);
    console.log("  ✅ advanceGame staticCall succeeded - should work\n");
  } catch (error) {
    console.log("  ❌ advanceGame staticCall failed");
    console.log("  Error:", error.message.substring(0, 200));

    if (error.data) {
      console.log("  Error data:", error.data);

      // Try to decode custom errors
      try {
        const errorSig = error.data.slice(0, 10);
        console.log("  Error signature:", errorSig);

        // Common error signatures
        const errors = {
          "0x3f73cf47": "RngNotReady()",
          "0xb7b2409c": "NotTimeYet()",
          "0x82b42900": "Unauthorized()",
          "0x08c379a0": "Error(string)"
        };

        if (errors[errorSig]) {
          console.log("  Decoded:", errors[errorSig]);
        }
      } catch (e) {
        // ignore
      }
    }
    console.log();
  }

  // Check VRF status
  console.log("VRF STATE:");
  try {
    // Try to get pendingRngId from game storage
    const storageSlot = await ethers.provider.getStorage(deployment.contracts.GAME, 0);
    console.log("  Storage slot 0:", storageSlot);
  } catch (e) {
    console.log("  Could not read storage");
  }
}

main().catch(console.error);
