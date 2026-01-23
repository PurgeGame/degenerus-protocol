import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const SUB_ID = "17001401905709230887426249162986633867013327252126643187628313616020032091031";
  const KEY_HASH = "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";

  console.log("Testing VRF requestRandomWords parameters...\n");

  const coordinatorAbi = [
    "function getSubscription(uint256 subId) view returns (uint96, uint96, uint64, address, address[])",
    "function pendingRequestExists(uint256 subId) view returns (bool)",
    "function requestRandomWords((bytes32,uint256,uint16,uint32,uint32)) external returns (uint256)"
  ];

  const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, ethers.provider);

  // Check if pending request exists
  try {
    const pending = await coordinator.pendingRequestExists(SUB_ID);
    console.log("Pending request exists:", pending);
    if (pending) {
      console.log("❌ There is already a pending VRF request!");
      console.log("   Must wait for Chainlink to fulfill it before making another");
    }
  } catch (e) {
    console.log("Could not check pending requests:", e.message.substring(0, 60));
  }

  console.log("\nSubscription verification:");
  const [balance, , reqCount, owner, consumers] = await coordinator.getSubscription(SUB_ID);
  console.log("  Balance:", ethers.formatEther(balance), "LINK");
  console.log("  Requests made:", reqCount.toString());
  console.log("  Consumers:", consumers.map(c => c === deployment.contracts.GAME ? "Game ✓" : c));
}

main().catch(console.error);
