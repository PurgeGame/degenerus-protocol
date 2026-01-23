/**
 * Wire VRF subscription to DegenerusGame contract
 *
 * Usage:
 *   VRF_SUB_ID=123 npx hardhat run scripts/wire-vrf.js --network sepolia
 *
 * Prerequisites:
 *   1. Create VRF subscription at https://vrf.chain.link/sepolia
 *   2. Add Game contract as consumer in the subscription
 *   3. Fund subscription with at least 2-5 LINK
 *   4. Note the subscription ID
 */

import { ethers } from "hardhat";
import fs from "node:fs";
import path from "node:path";

async function main() {
  const subIdEnv = process.env.VRF_SUB_ID;
  if (!subIdEnv) {
    console.error("❌ Error: VRF_SUB_ID environment variable not set");
    console.log("\nUsage:");
    console.log("  VRF_SUB_ID=<your_subscription_id> npx hardhat run scripts/wire-vrf.js --network sepolia");
    console.log("\nSteps to get subscription ID:");
    console.log("  1. Visit https://vrf.chain.link/sepolia");
    console.log("  2. Click 'Create Subscription'");
    console.log("  3. Note the subscription ID (e.g., 123)");
    console.log("  4. Add Game contract as consumer");
    console.log("  5. Fund with at least 2 LINK");
    process.exit(1);
  }

  const subId = BigInt(subIdEnv);

  // Load deployment info
  const deployInfoPath = path.resolve("deployment-sepolia.json");
  if (!fs.existsSync(deployInfoPath)) {
    console.error("❌ deployment-sepolia.json not found. Deploy contracts first.");
    process.exit(1);
  }

  const deployment = JSON.parse(fs.readFileSync(deployInfoPath, "utf8"));

  // Load deployer from wallets.json
  const walletsPath = path.resolve("wallets.json");
  if (!fs.existsSync(walletsPath)) {
    console.error("❌ wallets.json not found");
    process.exit(1);
  }

  const walletsData = JSON.parse(fs.readFileSync(walletsPath, "utf8"));
  const deployerWallet = new ethers.Wallet(walletsData.ownerPrivateKey, ethers.provider);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  WIRING VRF SUBSCRIPTION TO GAME CONTRACT                      ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  console.log("Deployer:", deployerWallet.address);
  console.log("VRF Subscription ID:", subId.toString());
  console.log("VRF Coordinator:", deployment.contracts.VRF_COORDINATOR);
  console.log("VRF Key Hash:", deployment.contracts.VRF_KEY_HASH);
  console.log("Game Contract:", deployment.contracts.GAME);
  console.log("Admin Contract:", deployment.contracts.ADMIN);
  console.log();

  // Get contracts
  const admin = await ethers.getContractAt(
    'contracts/DegenerusAdmin.sol:DegenerusAdmin',
    deployment.contracts.ADMIN
  );

  const game = await ethers.getContractAt(
    'contracts/DegenerusGame.sol:DegenerusGame',
    deployment.contracts.GAME
  );

  // Check if already wired
  const currentSubId = await game.vrfSubscriptionId();
  if (currentSubId !== 0n) {
    console.log(`⚠️  VRF already wired with subscription ID: ${currentSubId}`);
    if (currentSubId === subId) {
      console.log("✅ Subscription ID matches - no action needed");
      return;
    } else {
      console.log(`❌ Different subscription ID detected. Current: ${currentSubId}, Requested: ${subId}`);
      console.log("   Use updateVrfCoordinatorAndSub() to change it.");
      process.exit(1);
    }
  }

  // Verify subscription exists and has Game as consumer
  const vrfCoordinator = await ethers.getContractAt(
    [
      "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
    ],
    deployment.contracts.VRF_COORDINATOR
  );

  try {
    const [balance, nativeBalance, reqCount, owner, consumers] = await vrfCoordinator.getSubscription(subId);
    console.log("Subscription Details:");
    console.log("  LINK Balance:", ethers.formatEther(balance), "LINK");
    console.log("  Native Balance:", ethers.formatEther(nativeBalance), "ETH");
    console.log("  Owner:", owner);
    console.log("  Consumers:", consumers);
    console.log();

    if (balance === 0n) {
      console.log("⚠️  WARNING: Subscription has 0 LINK balance!");
      console.log("   Fund your subscription at: https://vrf.chain.link/sepolia/" + subId);
      console.log("   Minimum recommended: 2 LINK");
      console.log();
    }

    const hasGameAsConsumer = consumers.some(c => c.toLowerCase() === deployment.contracts.GAME.toLowerCase());
    if (!hasGameAsConsumer) {
      console.log("⚠️  WARNING: Game contract is not listed as a consumer!");
      console.log("   Add it in your subscription at: https://vrf.chain.link/sepolia/" + subId);
      console.log();
    }

  } catch (error) {
    console.error("❌ Failed to fetch subscription details:", error.message);
    console.log("   Make sure the subscription ID is correct and exists.");
    process.exit(1);
  }

  // Wire VRF
  console.log("Wiring VRF to Game contract...");
  const tx = await admin.connect(deployerWallet).wireVrf(
    deployment.contracts.VRF_COORDINATOR,
    subId,
    deployment.contracts.VRF_KEY_HASH,
    {
      gasLimit: 500000
    }
  );

  console.log("Transaction hash:", tx.hash);
  console.log("Waiting for confirmation...");
  await tx.wait();

  console.log();
  console.log("✅ VRF SUCCESSFULLY WIRED!");
  console.log();

  // Verify
  const newSubId = await game.vrfSubscriptionId();
  console.log("Verified subscription ID in Game contract:", newSubId.toString());

  // Update deployment file with correct subId
  deployment.vrfSubscriptionId = subId.toString();
  fs.writeFileSync(deployInfoPath, JSON.stringify(deployment, null, 2), "utf8");
  console.log("Updated deployment-sepolia.json with subscription ID");
  console.log();
  console.log("🎉 Ready for testing! You can now run:");
  console.log("   npx hardhat run scripts/test/production-simulation.js --network sepolia");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
