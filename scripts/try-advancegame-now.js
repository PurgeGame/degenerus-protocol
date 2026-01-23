import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Trying to call advanceGame(0)...\n");

  try {
    // First try static call to see if it would revert
    try {
      await game.connect(deployer).advanceGame.staticCall(0);
      console.log("✅ Static call succeeded - transaction should work\n");
    } catch (staticError) {
      console.log("⚠️  Static call failed:", staticError.message.substring(0, 150), "\n");
    }

    const tx = await game.connect(deployer).advanceGame(0, {
      gasLimit: 5000000,
      gasPrice: 52014000
    });
    console.log("Tx:", tx.hash);
    const receipt = await tx.wait();
    console.log("✅ Success! Gas used:", receipt.gasUsed.toString());

    const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
    console.log("\nNew state:");
    console.log("  Level:", level.toString());
    console.log("  State:", gameState.toString());
    console.log("  RNG Locked:", rngLocked);
  } catch (e) {
    console.log("❌ Failed!");
    console.log("Error message:", e.message);
    console.log("\nFull error:");
    console.log(e);
  }
}

main().catch(console.error);
