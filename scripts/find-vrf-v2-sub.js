import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));

async function main() {
  const VRF_V2_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625";
  const VRF_V2_KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c";
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  const game = deployment.contracts.GAME;
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

  console.log("Deployer:", deployer.address);
  console.log();

  // Get recent SubscriptionCreated events (all)
  const coordinatorAbi = [
    "event SubscriptionCreated(uint64 indexed subId, address owner)",
    "function getSubscription(uint64 subId) external view returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers)",
    "function addConsumer(uint64 subId, address consumer) external"
  ];

  const coordinator = new ethers.Contract(VRF_V2_COORDINATOR, coordinatorAbi, deployer);

  const latestBlock = await ethers.provider.getBlockNumber();
  const fromBlock = latestBlock - 100;

  console.log(`Checking recent SubscriptionCreated events...`);

  const filter = coordinator.filters.SubscriptionCreated();
  const events = await coordinator.queryFilter(filter, fromBlock, latestBlock);

  let ourSubId = null;

  for (const event of events) {
    const subId = event.args.subId;
    try {
      const [balance, reqCount, owner, consumers] = await coordinator.getSubscription(subId);
      
      if (owner.toLowerCase() === deployer.address.toLowerCase()) {
        console.log("\n✓ Found subscription owned by deployer:");
        console.log("  Subscription ID:", subId.toString());
        console.log("  Balance:", ethers.formatEther(balance), "LINK");
        console.log("  Consumers:", consumers.length);
        
        if (consumers.length > 0) {
          consumers.forEach(c => console.log("    -", c));
        }
        
        ourSubId = subId;
      }
    } catch (e) {
      // Skip
    }
  }

  if (!ourSubId) {
    console.log("\n❌ No subscription found for deployer");
    console.log("   The subscription may have been created earlier");
    console.log("   Try checking manually at: https://vrf.chain.link/sepolia");
    return;
  }

  // Add Game as consumer if not already added
  console.log("\n━━━ Adding Game as consumer ━━━");
  try {
    const [balance, reqCount, owner, consumers] = await coordinator.getSubscription(ourSubId);
    const gameIsConsumer = consumers.some(c => c.toLowerCase() === game.toLowerCase());

    if (gameIsConsumer) {
      console.log("✓ Game is already a consumer");
    } else {
      console.log("Adding Game contract as consumer...");
      const tx = await coordinator.addConsumer(ourSubId, game, {
        gasLimit: 500000,
        gasPrice: 1000000000
      });
      await tx.wait();
      console.log("✓ Game added as consumer");
    }
  } catch (e) {
    console.log("❌ Failed to add consumer:", e.message.substring(0, 100));
  }

  // Wire VRF to Game contract
  console.log("\n━━━ Wiring VRF to Game contract ━━━");
  try {
    const tx = await admin.connect(deployer).wireVrf(
      VRF_V2_COORDINATOR,
      ourSubId,
      VRF_V2_KEY_HASH,
      {
        gasLimit: 500000,
        gasPrice: 1000000000
      }
    );
    await tx.wait();
    console.log("✓ VRF wired to Game contract");
  } catch (e) {
    console.log("❌ Failed:", e.message.substring(0, 150));
  }

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  VRF V2 CONFIGURATION COMPLETE                                 ║");
  console.log("╚════════════════════════════════════════════════════════════════╝");
  console.log("Subscription ID:", ourSubId.toString());
  console.log("Coordinator:", VRF_V2_COORDINATOR);
  console.log("Key Hash:", VRF_V2_KEY_HASH);
  console.log("\nNow try advanceGame again!");
}

main().catch(console.error);
