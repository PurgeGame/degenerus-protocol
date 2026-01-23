import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

const subId = await admin.subscriptionId();

console.log("\n🔍 VRF Subscription Details\n");
console.log("Subscription ID:", subId.toString());

const coordinatorAbi = [
  "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
];

const coordinator = new ethers.Contract(deployment.contracts.VRF_COORDINATOR, coordinatorAbi, ethers.provider);

try {
  const [balance, nativeBalance, reqCount, owner, consumers] = await coordinator.getSubscription(subId);

  console.log("\nSubscription Info:");
  console.log("  LINK Balance:", ethers.formatEther(balance), "LINK");
  console.log("  Request Count:", reqCount.toString());
  console.log("  Owner:", owner);
  console.log("  Consumers:", consumers.length);
  
  console.log("\nConsumer List:");
  for (let i = 0; i < consumers.length; i++) {
    const consumer = consumers[i];
    const isGame = consumer.toLowerCase() === deployment.contracts.GAME.toLowerCase();
    console.log("  " + (i + 1) + ". " + consumer + (isGame ? ' (GAME)' : ''));
  }

  const gameIsConsumer = consumers.some(c => c.toLowerCase() === deployment.contracts.GAME.toLowerCase());
  
  if (!gameIsConsumer) {
    console.log("\n❌ Game is NOT a consumer of this subscription!");
  } else {
    console.log("\n✅ Game is properly registered as consumer");
  }
  
} catch (error) {
  console.error("Error:", error.message);
}
