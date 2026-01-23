import hre from "hardhat";
import { formatEther } from "ethers";
import deployment from "../deployment-sepolia.json" with { type: "json" };

async function main() {

  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);

  // Get purchase info
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();

  console.log("Current State:");
  console.log(`  Level: ${level}`);
  console.log(`  Game State: ${gameState}`);
  console.log(`  Last Purchase Day: ${lastPurchaseDay}`);
  console.log(`  RNG Locked: ${rngLocked}`);
  console.log(`  Mint Price: ${formatEther(priceWei)} ETH`);

  // Get prize pool info
  const lastPrizepool = await game.prizePoolTargetView();
  const nextPrizepool = await game.nextPrizePoolView();

  console.log(`\nPrize Pool Info:`);
  console.log(`  Last Prize Pool: ${formatEther(lastPrizepool)} ETH`);
  console.log(`  Next Prize Pool: ${formatEther(nextPrizepool)} ETH`);
  console.log(`  5% of Last Pool: ${formatEther((lastPrizepool * 5n) / 100n)} ETH`);

  // Calculate what purchase would be
  const purchaseAmount = (lastPrizepool * 5n) / 100n;
  console.log(`\nCalculated purchase amount: ${purchaseAmount.toString()} wei (${formatEther(purchaseAmount)} ETH)`);

  if (purchaseAmount > 0n) {
    const quantity = purchaseAmount / priceWei;
    console.log(`  Would purchase quantity: ${quantity.toString()} MAPs`);
  } else {
    console.log(`  ⚠️  Purchase amount is 0!`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
