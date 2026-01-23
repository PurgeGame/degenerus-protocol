import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

// VRF Coordinator V2.5 Plus on Sepolia
const coordinatorAddress = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";

const coordinatorABI = [
  "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
];

const coordinator = new ethers.Contract(coordinatorAddress, coordinatorABI, ethers.provider);

console.log("\n🔗 VRF Subscription Status\n");
console.log("Subscription ID:", deployment.vrfSubscriptionId);

try {
  const [balance, nativeBalance, reqCount, owner, consumers] = await coordinator.getSubscription(deployment.vrfSubscriptionId);

  console.log("\nSubscription Details:");
  console.log("  LINK Balance:", ethers.formatEther(balance), "LINK");
  console.log("  Native Balance:", ethers.formatEther(nativeBalance), "ETH");
  console.log("  Request Count:", reqCount.toString());
  console.log("  Owner:", owner);
  console.log("  Consumers:", consumers.length);
  console.log("");

  consumers.forEach((consumer, idx) => {
    console.log(`  Consumer ${idx}:`, consumer);
  });

  console.log("");
} catch (error) {
  console.error("Error fetching subscription:", error.message);
}
