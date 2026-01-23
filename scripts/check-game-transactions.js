import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

  console.log("Game Contract:", deployment.contracts.GAME);
  console.log("VRF Coordinator:", deployment.contracts.VRF_COORDINATOR);
  console.log("\nChecking Etherscan:");
  console.log("https://sepolia.etherscan.io/address/" + deployment.contracts.GAME);
  console.log("\nVRF Coordinator on Etherscan:");
  console.log("https://sepolia.etherscan.io/address/" + deployment.contracts.VRF_COORDINATOR);

  // Try to get the current pending request ID from the Game contract
  console.log("\n📊 Checking Game contract state...");
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);

  // Check if we can access currentWord (indicates if RNG has been consumed)
  try {
    const currentWord = await game.currentWord();
    console.log("  currentWord:", currentWord.toString());
  } catch (e) {
    console.log("  currentWord: not accessible");
  }

  // Check rngLockedFlag
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
  console.log("  rngLockedFlag:", rngLocked);
  console.log("  level:", level.toString());
  console.log("  gameState:", gameState.toString());

  // Check the subscription
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const subId = await admin.subscriptionId();

  const subscriptionABI = [
    "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)",
    "function pendingRequestExists(uint256 subId) external view returns (bool)"
  ];
  const vrfSub = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, subscriptionABI, hre.ethers.provider);

  const [balance, nativeBalance, reqCount, owner, consumers] = await vrfSub.getSubscription(subId);
  console.log("\n💰 Subscription Info:");
  console.log("  Total requests made:", reqCount.toString());
  console.log("  LINK balance:", hre.ethers.formatEther(balance), "LINK");

  // Check if there's a pendingRequestExists function
  try {
    const pending = await vrfSub.pendingRequestExists(subId);
    console.log("  Pending requests:", pending);
  } catch (e) {
    console.log("  pendingRequestExists: not available on this coordinator");
  }

  console.log("\n🔍 Manual Investigation:");
  console.log("1. Visit the Game contract on Etherscan and check:");
  console.log("   - Recent 'rawFulfillRandomWords' calls (these are VRF callbacks)");
  console.log("   - 'advanceGame' transaction history");
  console.log("\n2. Visit the VRF Coordinator on Etherscan and check:");
  console.log("   - Events for your subscription ID:", subId.toString());
  console.log("   - Look for RandomWordsRequested and RandomWordsFulfilled events");
}

main().catch(console.error);
