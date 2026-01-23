import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  CHECKING GAME CONTRACT VRF CONFIGURATION                      ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const GAME = deployment.contracts.GAME;
  
  // Read storage slots where VRF config should be
  // Based on DegenerusGameStorage.sol, these should be in specific slots
  console.log("Reading Game contract storage...\n");

  // Slot 100 (0x64): vrfCoordinator
  const coordinatorSlot = await ethers.provider.getStorage(GAME, 100);
  const coordinatorAddr = "0x" + coordinatorSlot.slice(-40);
  console.log("VRF Coordinator (slot 100):", coordinatorAddr);

  // Slot 101 (0x65): vrfKeyHash
  const keyHashSlot = await ethers.provider.getStorage(GAME, 101);
  console.log("VRF Key Hash (slot 101):", keyHashSlot);

  // Slot 102 (0x66): vrfSubscriptionId
  const subIdSlot = await ethers.provider.getStorage(GAME, 102);
  console.log("VRF Subscription ID (slot 102):", subIdSlot);
  const subIdBigInt = BigInt(subIdSlot);
  console.log("  (as decimal):", subIdBigInt.toString());

  console.log("\n━━━ EXPECTED VALUES ━━━");
  console.log("Coordinator:", "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B");
  console.log("Key Hash:", "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae");
  console.log("Subscription ID:", "17001401905709230887426249162986633867013327252126643187628313616020032091031");

  console.log("\n━━━ DIAGNOSIS ━━━");
  
  if (coordinatorAddr.toLowerCase() !== "0x9ddfaca8183c41ad55329bdeed9f6a8d53168b1b") {
    console.log("❌ Coordinator address MISMATCH!");
  } else {
    console.log("✓ Coordinator address correct");
  }

  if (keyHashSlot !== "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae") {
    console.log("❌ Key hash MISMATCH!");
  } else {
    console.log("✓ Key hash correct");
  }

  const expectedSubId = "17001401905709230887426249162986633867013327252126643187628313616020032091031";
  if (subIdBigInt.toString() !== expectedSubId) {
    console.log("❌ Subscription ID MISMATCH!");
    console.log("   This might be the issue!");
  } else {
    console.log("✓ Subscription ID correct");
  }
}

main().catch(console.error);
