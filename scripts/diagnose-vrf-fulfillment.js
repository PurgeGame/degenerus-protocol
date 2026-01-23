import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  VRF FULFILLMENT DIAGNOSIS                                     ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  // Get current state
  const [level, gameState, lastPurchaseDay, rngLocked, priceWei] = await game.purchaseInfo();
  console.log("Current Game State:");
  console.log("  Level:", level.toString());
  console.log("  State:", gameState.toString());
  console.log("  RNG Locked:", rngLocked);

  // Get VRF config
  const subId = await admin.subscriptionId();
  console.log("\nVRF Configuration:");
  console.log("  Subscription ID:", subId.toString());
  console.log("  VRF Coordinator:", deployment.contracts.VRF_COORDINATOR);

  // Check for VRF request events from the Game contract
  console.log("\n📡 Checking for VRF Request events...");
  const gameDeployBlock = 7529000; // Approximate - adjust if known
  const latestBlock = await hre.ethers.provider.getBlockNumber();

  // Look for RandomWordsRequested events from VRF Coordinator
  const vrfCoordABI = [
    "event RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed, uint256 indexed subId, uint16 minimumRequestConfirmations, uint32 callbackGasLimit, uint32 numWords, bytes extraArgs, address indexed sender)"
  ];
  const vrfCoord = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, vrfCoordABI, hre.ethers.provider);

  try {
    const requestFilter = vrfCoord.filters.RandomWordsRequested(null, null, null, subId);
    const requestEvents = await vrfCoord.queryFilter(requestFilter, gameDeployBlock, latestBlock);

    console.log(`  Found ${requestEvents.length} VRF request(s)`);

    for (let i = 0; i < Math.min(requestEvents.length, 10); i++) {
      const event = requestEvents[i];
      const block = await hre.ethers.provider.getBlock(event.blockNumber);
      console.log(`\n  Request ${i + 1}:`);
      console.log(`    Request ID: ${event.args.requestId.toString()}`);
      console.log(`    Block: ${event.blockNumber}`);
      console.log(`    Time: ${new Date(block.timestamp * 1000).toISOString()}`);
      console.log(`    Sender: ${event.args.sender}`);
      console.log(`    Callback Gas: ${event.args.callbackGasLimit}`);
      console.log(`    Min Confirmations: ${event.args.minimumRequestConfirmations}`);
    }
  } catch (e) {
    console.log("  Error fetching request events:", e.message.substring(0, 100));
  }

  // Check for fulfillment events
  console.log("\n✅ Checking for VRF Fulfillment events...");
  const fulfillABI = [
    "event RandomWordsFulfilled(uint256 indexed requestId, uint256 randomWord, uint256 payment, bytes extraArgs, bool success)"
  ];
  const vrfCoordFulfill = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, fulfillABI, hre.ethers.provider);

  try {
    const fulfillFilter = vrfCoordFulfill.filters.RandomWordsFulfilled();
    const fulfillEvents = await vrfCoordFulfill.queryFilter(fulfillFilter, gameDeployBlock, latestBlock);

    console.log(`  Found ${fulfillEvents.length} VRF fulfillment(s)`);

    for (let i = 0; i < Math.min(fulfillEvents.length, 10); i++) {
      const event = fulfillEvents[i];
      const block = await hre.ethers.provider.getBlock(event.blockNumber);
      console.log(`\n  Fulfillment ${i + 1}:`);
      console.log(`    Request ID: ${event.args.requestId.toString()}`);
      console.log(`    Block: ${event.blockNumber}`);
      console.log(`    Time: ${new Date(block.timestamp * 1000).toISOString()}`);
      console.log(`    Success: ${event.args.success}`);
      console.log(`    Payment: ${hre.ethers.formatEther(event.args.payment)} LINK`);
    }
  } catch (e) {
    console.log("  Error fetching fulfillment events:", e.message.substring(0, 100));
  }

  // Check subscription balance
  console.log("\n💰 Subscription Balance:");
  const subscriptionABI = [
    "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
  ];
  const vrfSub = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, subscriptionABI, hre.ethers.provider);

  try {
    const [balance, nativeBalance, reqCount, owner, consumers] = await vrfSub.getSubscription(subId);
    console.log("  LINK Balance:", hre.ethers.formatEther(balance), "LINK");
    console.log("  Native Balance:", hre.ethers.formatEther(nativeBalance), "ETH");
    console.log("  Total Requests Made:", reqCount.toString());
    console.log("  Owner:", owner);
    console.log("  Consumers:", consumers);
  } catch (e) {
    console.log("  Error:", e.message);
  }

  // Try to check pending requests
  console.log("\n⏳ Checking for pending VRF requests...");
  console.log("  (This requires checking if requestId exists but wasn't fulfilled)");

  const currentBlock = await hre.ethers.provider.getBlockNumber();
  console.log(`  Current block: ${currentBlock}`);
  console.log(`  Latest block timestamp: ${(await hre.ethers.provider.getBlock('latest')).timestamp}`);
}

main().catch(console.error);
