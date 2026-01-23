import hre from "hardhat";
import deployment from "../deployment-sepolia.json" with { type: "json" };

async function main() {
  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);
  const gamepieces = await hre.ethers.getContractAt("DegenerusGamepieces", deployment.contracts.GAMEPIECES);

  // Check purchase enabled
  try {
    const purchaseEnabled = await gamepieces.purchasesEnabled();
    console.log(`Purchases Enabled: ${purchaseEnabled}`);
  } catch (e) {
    console.log(`Error checking purchasesEnabled: ${e.message}`);
  }

  // Get game state details
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
  console.log(`\nGame State:`);
  console.log(`  Level: ${level}`);
  console.log(`  State: ${gameState} (2=PURCHASE, 4=BURN, 5=DECIMATOR)`);
  console.log(`  RNG Locked: ${rngLocked}`);

  // Try to see if there's a require that's failing
  console.log(`\nChecking if we can simulate a purchase call...`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
