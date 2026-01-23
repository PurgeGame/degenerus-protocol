import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const game = await hre.ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);

  const subId = await admin.subscriptionId();
  console.log("VRF Subscription ID:", subId.toString());

  console.log("\nChecking subscription balance via VRFCoordinatorV2_5...");
  const vrfCoordABI = [
    "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
  ];
  const vrfCoord = new hre.ethers.Contract(deployment.contracts.VRF_COORDINATOR, vrfCoordABI, hre.ethers.provider);

  try {
    const [balance, nativeBalance, reqCount, owner, consumers] = await vrfCoord.getSubscription(subId);
    console.log("  LINK Balance:", hre.ethers.formatEther(balance), "LINK");
    console.log("  Native Balance:", hre.ethers.formatEther(nativeBalance), "ETH");
    console.log("  Request Count:", reqCount.toString());
    console.log("  Owner:", owner);
    console.log("  Consumers:", consumers);
  } catch (e) {
    console.log("  Error:", e.message.substring(0, 100));
  }

  console.log("\nChecking Game rngRequestTime...");
  // Try to read rngRequestTime if it's public
  try {
    const rngRequestTime = await game.rngRequestTime();
    console.log("  rngRequestTime:", rngRequestTime.toString());
    const blockTime = (await hre.ethers.provider.getBlock('latest')).timestamp;
    console.log("  Current block time:", blockTime);
    console.log("  Time waiting:", blockTime - Number(rngRequestTime), "seconds");
  } catch (e) {
    console.log("  rngRequestTime not accessible");
  }
}

main().catch(console.error);
