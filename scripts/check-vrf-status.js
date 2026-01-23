import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  VRF STATUS CHECK                                              ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const adminSubId = await admin.subscriptionId();
  const adminCoordinator = await admin.coordinator();
  const adminKeyHash = await admin.vrfKeyHash();

  console.log("Contracts:");
  console.log("  Game:", deployment.contracts.GAME);
  console.log("  Admin:", deployment.contracts.ADMIN);
  console.log();

  console.log("VRF Configuration:");
  console.log("  Subscription ID:", adminSubId.toString());
  console.log("  Coordinator:", adminCoordinator);
  console.log("  Key Hash:", adminKeyHash);
  console.log();

  if (adminSubId === 0n || adminCoordinator === ethers.ZeroAddress) {
    console.log("❌ VRF NOT WIRED - Subscription ID is 0 or coordinator not set");
    console.log("\nTo wire VRF:");
    console.log("  1. Create subscription at: https://vrf.chain.link/sepolia");
    console.log("  2. Add Game as consumer:", deployment.contracts.GAME);
    console.log("  3. Fund with 2-5 LINK");
    console.log("  4. Run: VRF_SUB_ID=<id> npx hardhat run scripts/wire-vrf.js --network sepolia");
  } else {
    console.log("✅ VRF IS WIRED");
    console.log(`   View subscription at: https://vrf.chain.link/sepolia/${adminSubId}\n`);

    // Check subscription details from coordinator
    try {
      const coordinatorAbi = [
        "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
      ];
      const coordinator = new ethers.Contract(adminCoordinator, coordinatorAbi, ethers.provider);
      const [balance, nativeBalance, reqCount, owner, consumers] = await coordinator.getSubscription(adminSubId);

      console.log("Subscription Details:");
      console.log("  LINK Balance:", ethers.formatEther(balance), "LINK");
      console.log("  Request Count:", reqCount.toString());
      console.log("  Owner:", owner);
      console.log("  Consumers:", consumers.length);

      const gameIsConsumer = consumers.some(c => c.toLowerCase() === deployment.contracts.GAME.toLowerCase());

      if (!gameIsConsumer) {
        console.log("\n❌ GAME CONTRACT NOT REGISTERED AS CONSUMER!");
        console.log("   Expected:", deployment.contracts.GAME);
        console.log("   Need to add Game contract to subscription");
      } else {
        console.log("\n✅ Game contract is registered as consumer");
      }

      if (balance === 0n) {
        console.log("\n❌ SUBSCRIPTION HAS NO LINK!");
        console.log("   Fund at: https://vrf.chain.link/sepolia/${adminSubId}");
      }
    } catch (e) {
      console.log("\n⚠️  Could not fetch subscription details:", e.message.substring(0, 80));
    }
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
