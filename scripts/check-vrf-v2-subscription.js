import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const VRF_V2_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625";
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("Checking VRF V2 subscriptions for deployer:", deployer.address);
  console.log();

  // Get recent SubscriptionCreated events
  const coordinatorAbi = [
    "event SubscriptionCreated(uint64 indexed subId, address owner)",
    "function getSubscription(uint64 subId) external view returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers)"
  ];

  const coordinator = new ethers.Contract(VRF_V2_COORDINATOR, coordinatorAbi, ethers.provider);

  // Check recent blocks for SubscriptionCreated events
  const latestBlock = await ethers.provider.getBlockNumber();
  const fromBlock = latestBlock - 100; // Last 100 blocks

  console.log(`Checking blocks ${fromBlock} to ${latestBlock} for SubscriptionCreated events...`);

  const filter = coordinator.filters.SubscriptionCreated(null, deployer.address);
  const events = await coordinator.queryFilter(filter, fromBlock, latestBlock);

  if (events.length === 0) {
    console.log("No subscriptions found for this address in recent blocks");
    return;
  }

  console.log(`\nFound ${events.length} subscription(s):\n`);

  for (const event of events) {
    const subId = event.args.subId;
    console.log("Subscription ID:", subId.toString());

    try {
      const [balance, reqCount, owner, consumers] = await coordinator.getSubscription(subId);
      console.log("  Balance:", ethers.formatEther(balance), "LINK");
      console.log("  Request Count:", reqCount.toString());
      console.log("  Owner:", owner);
      console.log("  Consumers:", consumers.length > 0 ? consumers : "None");
      console.log();
    } catch (e) {
      console.log("  Could not fetch details:", e.message.substring(0, 60));
      console.log();
    }
  }
}

main().catch(console.error);
