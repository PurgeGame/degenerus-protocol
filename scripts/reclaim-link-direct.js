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
  console.log("║  DIRECT VRF COORDINATOR LINK RECLAIM                           ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}\n`);

  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const vrfCoordinator = await hre.ethers.getContractAt(
    [
      "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] memory consumers)",
      "function removeConsumer(uint256 subId, address consumer) external",
      "function cancelSubscription(uint256 subId, address to) external"
    ],
    VRF_COORDINATOR
  );

  // Target the old admin with 40 LINK
  const OLD_ADMIN = "0x9461eA4B327aEe48b111142b262E5921EF785Ff0";
  const SUB_ID = "17001401905709230887426249162986633867013327252126643187628313616020032091031";

  console.log(`Target Admin: ${OLD_ADMIN}`);
  console.log(`Subscription ID: ${SUB_ID}\n`);

  // Get subscription details
  const [balance, , , subOwner, consumers] = await vrfCoordinator.getSubscription(SUB_ID);
  console.log(`Balance: ${hre.ethers.formatEther(balance)} LINK`);
  console.log(`Owner: ${subOwner}`);
  console.log(`Consumers: ${consumers.length}`);
  for (let i = 0; i < consumers.length; i++) {
    console.log(`  ${i + 1}. ${consumers[i]}`);
  }
  console.log();

  // Get the admin contract
  const admin = await hre.ethers.getContractAt("DegenerusAdmin", OLD_ADMIN);

  // Check who can call functions on this admin
  try {
    const owner = await admin.owner();
    console.log(`Admin owner: ${owner}`);
    console.log(`Deployer matches owner: ${owner.toLowerCase() === deployer.address.toLowerCase()}\n`);
  } catch (e) {
    console.log(`Could not get owner: ${e.message}\n`);
  }

  // Strategy 1: Try to remove consumers using the Admin contract
  if (consumers.length > 0) {
    console.log(`Strategy 1: Remove consumers via Admin.TEST_removeVrfConsumer()\n`);
    for (const consumer of consumers) {
      try {
        console.log(`  Checking if TEST_removeVrfConsumer exists...`);
        // Try to call it
        const tx = await admin.connect(deployer).TEST_removeVrfConsumer(consumer, {
          gasLimit: CONFIG.GAS_LIMIT,
          gasPrice: CONFIG.GAS_PRICE
        });
        const receipt = await tx.wait();
        console.log(`  ✓ Removed ${consumer}`);
        console.log(`    Gas: ${receipt.gasUsed}, Tx: ${receipt.hash}\n`);
      } catch (e) {
        console.log(`  ✗ Failed: ${e.message.substring(0, 100)}\n`);
        console.log(`  This old Admin likely doesn't have TEST_removeVrfConsumer function\n`);
      }
    }
  }

  // Strategy 2: Try calling VRF coordinator directly (will only work if deployer is subscription owner)
  console.log(`Strategy 2: Try direct VRF coordinator calls\n`);

  if (consumers.length > 0) {
    for (const consumer of consumers) {
      try {
        console.log(`  Removing ${consumer} directly...`);
        const tx = await vrfCoordinator.connect(deployer).removeConsumer(SUB_ID, consumer, {
          gasLimit: CONFIG.GAS_LIMIT,
          gasPrice: CONFIG.GAS_PRICE
        });
        const receipt = await tx.wait();
        console.log(`  ✓ Removed (gas: ${receipt.gasUsed})\n`);
      } catch (e) {
        console.log(`  ✗ Failed: ${e.message.substring(0, 100)}`);
        console.log(`  (Expected - subscription owner is Admin contract, not deployer)\n`);
      }
    }
  }

  // Strategy 3: Try to cancel via Admin.TEST_cancelVrfSubscription()
  console.log(`Strategy 3: Cancel via Admin.TEST_cancelVrfSubscription()\n`);
  try {
    const tx = await admin.connect(deployer).TEST_cancelVrfSubscription({
      gasLimit: CONFIG.GAS_LIMIT,
      gasPrice: CONFIG.GAS_PRICE
    });
    const receipt = await tx.wait();
    console.log(`✅ SUCCESS! Reclaimed ${hre.ethers.formatEther(balance)} LINK`);
    console.log(`   Gas: ${receipt.gasUsed}, Tx: ${receipt.hash}\n`);
  } catch (e) {
    console.log(`✗ Failed: ${e.message}\n`);
    console.log(`VRF Coordinator won't allow cancellation with consumers present\n`);
  }

  // Show current LINK balance
  const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const link = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)"],
    LINK_ADDRESS
  );
  const currentBalance = await link.balanceOf(deployer.address);
  console.log(`\n💰 Final LINK balance: ${hre.ethers.formatEther(currentBalance)} LINK\n`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
