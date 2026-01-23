import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

console.log("\n🔍 VRF Configuration Check\n");

const adminSubId = await admin.subscriptionId();
const gameSubId = await game.vrfSubscriptionId();

console.log("Admin subscription ID:", adminSubId.toString());
console.log("Game subscription ID: ", gameSubId.toString());
console.log("");

if (adminSubId === gameSubId) {
  console.log("✅ VRF is properly wired!");
} else {
  console.log("❌ VRF mismatch! Game is not using Admin's subscription.");
}
