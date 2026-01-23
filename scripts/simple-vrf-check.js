import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

console.log("\nDeployment VRF Config:");
console.log("  VRF Subscription ID:", deployment.vrfSubscriptionId);
console.log("  Use Real VRF:", deployment.useRealVRF);
console.log("  Use Mocks:", deployment.useMocks);
console.log("");
