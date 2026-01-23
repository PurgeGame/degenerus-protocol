import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B"; // V2.5 Plus
  const KEY_HASH = "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae"; // 100 gwei
  const GAME = deployment.contracts.GAME;
  const ADMIN = deployment.contracts.ADMIN;
  
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  
  console.log("Setting up VRF V2.5 Plus...\n");
  console.log("Game:", GAME);
  console.log("Admin:", ADMIN);
  console.log("Coordinator:", VRF_COORDINATOR);
  console.log();

  const coordinatorAbi = [
    "function createSubscription() external returns (uint256 subId)",
    "function addConsumer(uint256 subId, address consumer) external",
    "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)",
    "event SubscriptionCreated(uint256 indexed subId, address owner)"
  ];

  const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, deployer);

  // Step 1: Create subscription
  console.log("Creating VRF V2.5 subscription...");
  let subId;
  try {
    const tx = await coordinator.createSubscription({
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    const receipt = await tx.wait();
    
    // Find SubscriptionCreated event
    for (const log of receipt.logs) {
      try {
        const parsed = coordinator.interface.parseLog(log);
        if (parsed && parsed.name === 'SubscriptionCreated') {
          subId = parsed.args.subId;
          break;
        }
      } catch (e) {}
    }
    
    console.log("✓ Subscription created:", subId.toString());
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
    return;
  }

  // Step 2: Add Game as consumer
  console.log("\nAdding Game as consumer...");
  try {
    const tx2 = await coordinator.addConsumer(subId, GAME, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx2.wait();
    console.log("✓ Game added as consumer");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }

  // Step 3: Fund with LINK
  console.log("\nFunding with 40 LINK...");
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const linkAbi = [
    "function transferAndCall(address to, uint256 value, bytes calldata data) returns (bool)"
  ];
  const link = new ethers.Contract(LINK_TOKEN, linkAbi, deployer);
  
  try {
    const amount = ethers.parseEther("40");
    const data = ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [subId]);
    
    const tx3 = await link.transferAndCall(VRF_COORDINATOR, amount, data, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx3.wait();
    console.log("✓ Funded with 40 LINK");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }

  // Step 4: Wire to Game
  console.log("\nWiring VRF to Game contract...");
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', ADMIN);
  
  try {
    const tx4 = await admin.connect(deployer).wireVrf(VRF_COORDINATOR, subId, KEY_HASH, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx4.wait();
    console.log("✓ VRF wired to Game");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }

  console.log("\n✅ SETUP COMPLETE!");
  console.log("Subscription ID:", subId.toString());
  console.log("View at: https://vrf.chain.link/sepolia/" + subId.toString());
}

main().catch(console.error);
