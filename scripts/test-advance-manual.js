import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf-8"));
  const [deployer] = await hre.ethers.getSigners();

  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);

  const [level, state, , rngLocked] = await game.purchaseInfo();
  const isFulfilled = await game.isRngFulfilled();

  console.log("\n=== BEFORE ADVANCE ===");
  console.log(`Level: ${level}, State: ${state}`);
  console.log(`RNG Locked: ${rngLocked}, Fulfilled: ${isFulfilled}`);

  console.log("\n=== ATTEMPTING ADVANCE GAME ===");
  try {
    const tx = await game.connect(deployer).advanceGame(0, {
      gasLimit: 16000000,
    });
    console.log("Transaction sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("✅ Success! Gas used:", receipt.gasUsed.toString());
  } catch (error) {
    console.log("\n❌ FAILED:");
    console.log(error.message);

    // Try to get more details
    if (error.data) {
      console.log("\nError data:", error.data);
    }
  }
}

main().catch(console.error);
