import hre from "hardhat";
import fs from "fs";
import wallets from "../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 100000000,
  GAS_LIMIT: 1000000
};

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  RECLAIM LINK FROM OLD DEPLOYMENTS                             ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}\n`);

  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const vrfCoordinator = await hre.ethers.getContractAt(
    [
      "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] memory consumers)",
      "function removeConsumer(uint256 subId, address consumer) external"
    ],
    VRF_COORDINATOR
  );

  // Collect unique Admin contract addresses from deployment files
  const adminAddresses = new Set();

  const deploymentFiles = [
    "deployment-sepolia.json",
    "deployment-sepolia.json.bak"
  ];

  for (const file of deploymentFiles) {
    if (fs.existsSync(file)) {
      try {
        const deployment = JSON.parse(fs.readFileSync(file, "utf8"));
        if (deployment.contracts?.ADMIN) {
          adminAddresses.add(deployment.contracts.ADMIN.toLowerCase());
          console.log(`Found Admin in ${file}: ${deployment.contracts.ADMIN}`);
        }
      } catch (e) {
        // Skip invalid files
      }
    }
  }

  if (adminAddresses.size === 0) {
    console.log(`No previous deployments found\n`);
    return;
  }

  console.log(`\nChecking ${adminAddresses.size} Admin contract(s)...\n`);

  let totalReclaimed = 0n;
  let reclaimedCount = 0;

  // Try to reclaim from each Admin
  for (const adminAddr of adminAddresses) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`Admin: ${adminAddr}`);
    console.log(`${"=".repeat(70)}\n`);

    try {
      // Try to instantiate as DegenerusAdmin
      const admin = await hre.ethers.getContractAt("DegenerusAdmin", adminAddr);

      // Check if it has a subscription
      let subId;
      try {
        subId = await admin.subscriptionId();
        console.log(`✓ Found subscription ID: ${subId}`);
      } catch (e) {
        console.log(`✗ Not a valid Admin contract: ${e.message.substring(0, 80)}\n`);
        continue;
      }

      if (subId === 0n) {
        console.log(`✗ No active subscription\n`);
        continue;
      }

      // Get subscription details
      let balance, subOwner, consumers;
      try {
        [balance, , , subOwner, consumers] = await vrfCoordinator.getSubscription(subId);
        console.log(`✓ Subscription balance: ${hre.ethers.formatEther(balance)} LINK`);
        console.log(`✓ Subscription owner: ${subOwner}`);
        console.log(`✓ Consumers registered: ${consumers.length}`);
        for (let i = 0; i < consumers.length; i++) {
          console.log(`    ${i + 1}. ${consumers[i]}`);
        }
      } catch (e) {
        console.log(`✗ Failed to get subscription details: ${e.message.substring(0, 80)}\n`);
        continue;
      }

      if (balance === 0n) {
        console.log(`✗ Empty balance\n`);
        continue;
      }

      // Try to remove consumers first
      if (consumers.length > 0) {
        console.log(`\n🔧 Attempting to remove ${consumers.length} consumer(s)...`);
        let removedCount = 0;
        for (const consumer of consumers) {
          try {
            console.log(`  Removing ${consumer}...`);
            const txRemove = await admin.connect(deployer).TEST_removeVrfConsumer(consumer, {
              gasLimit: CONFIG.GAS_LIMIT,
              gasPrice: CONFIG.GAS_PRICE
            });
            const receipt = await txRemove.wait();
            console.log(`  ✓ Removed (gas: ${receipt.gasUsed})`);
            removedCount++;
          } catch (e) {
            console.log(`  ✗ Failed: ${e.message.substring(0, 100)}`);
          }
        }
        console.log(`\nRemoved ${removedCount}/${consumers.length} consumers\n`);
      }

      // Try to cancel subscription
      console.log(`💰 Attempting to cancel subscription...`);
      try {
        const tx = await admin.connect(deployer).TEST_cancelVrfSubscription({
          gasLimit: CONFIG.GAS_LIMIT,
          gasPrice: CONFIG.GAS_PRICE
        });
        const receipt = await tx.wait();

        totalReclaimed += balance;
        reclaimedCount++;
        console.log(`✅ SUCCESS! Reclaimed ${hre.ethers.formatEther(balance)} LINK`);
        console.log(`   Gas used: ${receipt.gasUsed}`);
        console.log(`   Tx: ${receipt.hash}\n`);
      } catch (e) {
        console.log(`✗ Cancellation failed: ${e.message}\n`);
        if (e.data) {
          console.log(`   Error data: ${e.data}\n`);
        }
      }
    } catch (e) {
      console.log(`✗ Unexpected error: ${e.message}\n`);
    }
  }

  console.log(`\n${"=".repeat(70)}`);
  console.log(`SUMMARY`);
  console.log(`${"=".repeat(70)}\n`);

  if (reclaimedCount > 0) {
    console.log(`✅ Total reclaimed: ${hre.ethers.formatEther(totalReclaimed)} LINK from ${reclaimedCount} deployment(s)`);
  } else {
    console.log(`⚠️  No LINK reclaimed`);
  }

  // Show current LINK balance
  const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const link = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    LINK_ADDRESS
  );
  const currentBalance = await link.balanceOf(deployer.address);
  console.log(`\n💰 Current LINK balance: ${hre.ethers.formatEther(currentBalance)} LINK\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
