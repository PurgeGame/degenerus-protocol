import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const subId = await admin.subscriptionId();

  const currentBlock = await hre.ethers.provider.getBlockNumber();
  const lookbackBlocks = 5000; // Last ~5000 blocks
  const startBlock = currentBlock - lookbackBlocks;

  console.log("Checking blocks", startBlock, "to", currentBlock, "(last", lookbackBlocks, "blocks)\n");

  // Check for VRF requests in recent blocks
  const vrfCoordABI = [
    "event RandomWordsRequested(bytes32 indexed keyHash, uint256 requestId, uint256 preSeed, uint256 indexed subId, uint16 minimumRequestConfirmations, uint32 callbackGasLimit, uint32 numWords, bytes extraArgs, address indexed sender)"
  ];
  const vrfCoord = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, vrfCoordABI, hre.ethers.provider);

  console.log("📡 Recent VRF Requests:");
  try {
    const requestFilter = vrfCoord.filters.RandomWordsRequested(null, null, null, subId);
    const requestEvents = await vrfCoord.queryFilter(requestFilter, startBlock, currentBlock);

    console.log("  Found", requestEvents.length, "request(s) in last", lookbackBlocks, "blocks\n");

    for (const event of requestEvents) {
      const block = await hre.ethers.provider.getBlock(event.blockNumber);
      const age = Math.floor((Date.now() / 1000) - block.timestamp);
      console.log("  Request ID:", event.args.requestId.toString());
      console.log("    Block:", event.blockNumber);
      console.log("    Age:", age, "seconds (", Math.floor(age/60), "minutes)");
      console.log("    Sender:", event.args.sender);
      console.log("    Callback Gas:", event.args.callbackGasLimit);
      console.log("    Min Confirmations:", event.args.minimumRequestConfirmations, "\n");
    }
  } catch (e) {
    console.log("  Error:", e.message, "\n");
  }

  // Check for VRF fulfillments in recent blocks
  const fulfillABI = [
    "event RandomWordsFulfilled(uint256 indexed requestId, uint256 randomWord, uint256 payment, bytes extraArgs, bool success)"
  ];
  const vrfCoordFulfill = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, fulfillABI, hre.ethers.provider);

  console.log("✅ Recent VRF Fulfillments:");
  try {
    const fulfillFilter = vrfCoordFulfill.filters.RandomWordsFulfilled();
    const fulfillEvents = await vrfCoordFulfill.queryFilter(fulfillFilter, startBlock, currentBlock);

    console.log("  Found", fulfillEvents.length, "fulfillment(s) in last", lookbackBlocks, "blocks\n");

    for (const event of fulfillEvents) {
      const block = await hre.ethers.provider.getBlock(event.blockNumber);
      const age = Math.floor((Date.now() / 1000) - block.timestamp);
      console.log("  Request ID:", event.args.requestId.toString());
      console.log("    Block:", event.blockNumber);
      console.log("    Age:", age, "seconds (", Math.floor(age/60), "minutes)");
      console.log("    Success:", event.args.success);
      console.log("    Payment:", hre.ethers.formatEther(event.args.payment), "LINK\n");
    }
  } catch (e) {
    console.log("  Error:", e.message, "\n");
  }
}

main().catch(console.error);
