import hre from "hardhat";
import wallets from "../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 100000000,
  GAS_LIMIT: 1000000
};

// Admin addresses to try (from various deployments)
const ADMIN_ADDRESSES = [
  "0x59a8E28eb43aEd6D4a7535b60cAeC76D19Fe046D",  // Had 194 LINK
  "0x9461eA4B327aEe48b111142b262E5921EF785Ff0",  // Has 40 LINK
  "0x20Cb78eD09C22D318bF488887B84F31f19823F50"   // Current (0 LINK)
];

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  SCANNING ALL KNOWN ADMIN CONTRACTS FOR LINK                   ║");
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

  let totalFound = 0n;
  let totalReclaimed = 0n;

  for (const adminAddr of ADMIN_ADDRESSES) {
    console.log(`\n${"=".repeat(70)}`);
    console.log(`Checking Admin: ${adminAddr}`);
    console.log(`${"=".repeat(70)}\n`);

    try {
      const admin = await hre.ethers.getContractAt("DegenerusAdmin", adminAddr);

      let subId;
      try {
        subId = await admin.subscriptionId();
      } catch (e) {
        console.log(`✗ Cannot read subscriptionId: ${e.message.substring(0, 60)}\n`);
        continue;
      }

      if (subId === 0n) {
        console.log(`✗ No active subscription\n`);
        continue;
      }

      console.log(`✓ Subscription ID: ${subId}`);

      let balance, consumers;
      try {
        [balance, , , , consumers] = await vrfCoordinator.getSubscription(subId);
        console.log(`✓ Balance: ${hre.ethers.formatEther(balance)} LINK`);
        console.log(`✓ Consumers: ${consumers.length}`);
        for (let i = 0; i < consumers.length; i++) {
          console.log(`    ${i + 1}. ${consumers[i]}`);
        }
      } catch (e) {
        console.log(`✗ Cannot get subscription: ${e.message.substring(0, 60)}\n`);
        continue;
      }

      if (balance === 0n) {
        console.log(`✗ Empty balance\n`);
        continue;
      }

      totalFound += balance;

      // Try to remove consumers
      if (consumers.length > 0) {
        console.log(`\n🔧 Removing ${consumers.length} consumer(s)...`);
        for (const consumer of consumers) {
          try {
            const txRemove = await admin.connect(deployer).TEST_removeVrfConsumer(consumer, {
              gasLimit: CONFIG.GAS_LIMIT,
              gasPrice: CONFIG.GAS_PRICE
            });
            await txRemove.wait();
            console.log(`  ✓ Removed ${consumer}`);
          } catch (e) {
            console.log(`  ✗ Failed to remove ${consumer}`);
            console.log(`     ${e.message.substring(0, 80)}`);
          }
        }
      }

      // Try to cancel
      console.log(`\n💰 Attempting to cancel subscription...`);
      try {
        const tx = await admin.connect(deployer).TEST_cancelVrfSubscription({
          gasLimit: CONFIG.GAS_LIMIT,
          gasPrice: CONFIG.GAS_PRICE
        });
        const receipt = await tx.wait();

        totalReclaimed += balance;
        console.log(`✅ SUCCESS! Reclaimed ${hre.ethers.formatEther(balance)} LINK`);
        console.log(`   Tx: ${receipt.hash}`);
      } catch (e) {
        console.log(`✗ Cancellation failed`);
        console.log(`   ${e.message.substring(0, 100)}`);
      }
    } catch (e) {
      console.log(`✗ Error: ${e.message.substring(0, 100)}\n`);
    }
  }

  console.log(`\n${"=".repeat(70)}`);
  console.log(`SUMMARY`);
  console.log(`${"=".repeat(70)}\n`);
  console.log(`Found: ${hre.ethers.formatEther(totalFound)} LINK across all subscriptions`);
  console.log(`Reclaimed: ${hre.ethers.formatEther(totalReclaimed)} LINK`);

  // Show current LINK balance
  const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const link = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    LINK_ADDRESS
  );
  const currentBalance = await link.balanceOf(deployer.address);
  console.log(`\n💰 Wallet LINK balance: ${hre.ethers.formatEther(currentBalance)} LINK\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
