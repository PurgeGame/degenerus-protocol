import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Testing if we can call advanceGame to consume RNG...\n");

  for (let i = 0; i < 5; i++) {
    const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
    console.log(`\nIteration ${i + 1}:`);
    console.log("  Level:", level.toString());
    console.log("  State:", gameState.toString());
    console.log("  RNG Locked:", rngLocked);

    if (!rngLocked) {
      console.log("  ✅ RNG is unlocked! No need to continue.");
      break;
    }

    console.log("  Calling advanceGame(0)...");
    try {
      const tx = await game.connect(deployer).advanceGame(0, {
        gasLimit: 5000000,
        gasPrice: 52014000
      });
      console.log("  Tx:", tx.hash);
      const receipt = await tx.wait();
      console.log("  ✅ Success! Gas used:", receipt.gasUsed.toString());
    } catch (e) {
      console.log("  ❌ Failed:", e.message.substring(0, 150));

      if (e.message.includes("RngNotReady")) {
        console.log("\n  VRF has NOT been fulfilled yet - need to wait for Chainlink");
        break;
      }
    }

    // Wait a bit between calls
    await new Promise(r => setTimeout(r, 2000));
  }

  console.log("\n✅ Final state:");
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
  console.log("  Level:", level.toString());
  console.log("  State:", gameState.toString());
  console.log("  RNG Locked:", rngLocked);
}

main().catch(console.error);
