import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const subIdArg = process.argv[2];

  if (!subIdArg) {
    console.log("Usage: npx hardhat run scripts/check-subscription-balance.js --network sepolia <subscriptionId>");
    console.log("\nTo check current deployment subscription, run:");
    console.log("  npx hardhat run scripts/check-vrf-status.js --network sepolia");
    process.exit(1);
  }

  const VRF_COORDINATOR = deployment.contracts.VRF_COORDINATOR;
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  const coordinatorAbi = [
    "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
  ];

  const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, ethers.provider);

  try {
    const [balance, nativeBalance, reqCount, owner, consumers] = await coordinator.getSubscription(subIdArg);

    console.log("╔════════════════════════════════════════════════════════════════╗");
    console.log("║  VRF SUBSCRIPTION DETAILS                                      ║");
    console.log("╚════════════════════════════════════════════════════════════════╝\n");

    console.log("Subscription ID:", subIdArg);
    console.log("LINK Balance:", ethers.formatEther(balance), "LINK");
    console.log("Native Balance:", ethers.formatEther(nativeBalance), "ETH");
    console.log("Request Count:", reqCount.toString());
    console.log("Owner:", owner);
    console.log("Number of Consumers:", consumers.length);
    console.log();

    if (consumers.length > 0) {
      console.log("Consumers:");
      for (const consumer of consumers) {
        console.log("  -", consumer);
      }
      console.log();
    }

    const isOwner = owner.toLowerCase() === deployer.address.toLowerCase();
    const hasBalance = balance > 0n || nativeBalance > 0n;

    if (isOwner && hasBalance) {
      console.log("✅ You own this subscription and it has balance");
      console.log("\nTo reclaim LINK, run:");
      console.log(`  npx hardhat run scripts/reclaim-link-from-subscription.js --network sepolia ${subIdArg}`);
    } else if (!isOwner) {
      console.log("⚠️  You do not own this subscription");
      console.log("   Owner:", owner);
      console.log("   Your address:", deployer.address);
    } else {
      console.log("ℹ️  Subscription has no balance to reclaim");
    }

  } catch (error) {
    console.log("❌ Error: Subscription does not exist or cannot be accessed");
    console.log("   Subscription ID:", subIdArg);
  }
}

main().catch(console.error);
