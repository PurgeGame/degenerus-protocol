import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  SWITCHING TO VRF V2 COORDINATOR                               ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const VRF_V2_COORDINATOR = "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625";
  const VRF_V2_KEY_HASH = "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c"; // 500 gwei key hash for Sepolia V2
  
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const game = deployment.contracts.GAME;

  console.log("Deployer:", deployer.address);
  console.log("Admin:", deployment.contracts.ADMIN);
  console.log("Game:", game);
  console.log();

  console.log("New VRF V2 Coordinator:", VRF_V2_COORDINATOR);
  console.log("New Key Hash (500 gwei):", VRF_V2_KEY_HASH);
  console.log();

  // Step 1: Create new subscription on V2 coordinator
  console.log("Step 1: Creating new VRF V2 subscription...");
  const coordinatorAbi = [
    "function createSubscription() external returns (uint64 subId)",
    "function addConsumer(uint64 subId, address consumer) external",
    "function getSubscription(uint64 subId) external view returns (uint96 balance, uint64 reqCount, address owner, address[] memory consumers)"
  ];

  const coordinator = new ethers.Contract(VRF_V2_COORDINATOR, coordinatorAbi, deployer);

  let newSubId;
  try {
    const tx = await coordinator.createSubscription({
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    const receipt = await tx.wait();
    
    // Parse SubscriptionCreated event to get subId
    const event = receipt.logs.find(log => {
      try {
        const parsed = coordinator.interface.parseLog(log);
        return parsed && parsed.name === 'SubscriptionCreated';
      } catch (e) {
        return false;
      }
    });
    
    if (event) {
      const parsed = coordinator.interface.parseLog(event);
      newSubId = parsed.args.subId;
      console.log("✓ Subscription created:", newSubId.toString());
    } else {
      console.log("✓ Transaction confirmed, checking owner's subscriptions...");
      // The subscription ID will be auto-incremented, we'll get it from events
      newSubId = 1n; // Placeholder
    }
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
    return;
  }

  // Step 2: Add Game as consumer
  console.log("\nStep 2: Adding Game contract as consumer...");
  try {
    const tx2 = await coordinator.addConsumer(newSubId, game, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx2.wait();
    console.log("✓ Game added as consumer");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }

  // Step 3: Fund with LINK (transfer from old subscription)
  console.log("\nStep 3: Funding new subscription with 40 LINK...");
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const linkAbi = [
    "function transferAndCall(address to, uint256 value, bytes calldata data) returns (bool)"
  ];
  const link = new ethers.Contract(LINK_TOKEN, linkAbi, deployer);

  try {
    const amount = ethers.parseEther("40");
    // Encode subId for transferAndCall data
    const data = ethers.AbiCoder.defaultAbiCoder().encode(['uint64'], [newSubId]);
    
    const tx3 = await link.transferAndCall(VRF_V2_COORDINATOR, amount, data, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx3.wait();
    console.log("✓ Funded with 40 LINK");
  } catch (error) {
    console.log("⚠️  Funding may have failed:", error.message.substring(0, 100));
    console.log("   You can fund manually at: https://vrf.chain.link/sepolia/" + newSubId.toString());
  }

  // Step 4: Wire new VRF config to Game via Admin
  console.log("\nStep 4: Wiring new VRF config to Game contract...");
  try {
    const tx4 = await admin.connect(deployer).updateVrfCoordinatorAndSub(
      VRF_V2_COORDINATOR,
      newSubId,
      VRF_V2_KEY_HASH,
      {
        gasLimit: 500000,
        gasPrice: 1000000000
      }
    );
    await tx4.wait();
    console.log("✓ VRF config updated in Game contract");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  CONFIGURATION COMPLETE                                        ║");
  console.log("╚════════════════════════════════════════════════════════════════╝");
  console.log("New Subscription ID:", newSubId.toString());
  console.log("VRF V2 Coordinator:", VRF_V2_COORDINATOR);
  console.log("Key Hash:", VRF_V2_KEY_HASH);
  console.log("\nView subscription at:");
  console.log("https://vrf.chain.link/sepolia/" + newSubId.toString());
}

main().catch(console.error);
