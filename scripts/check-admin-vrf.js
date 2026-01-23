import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

const subId = await admin.subscriptionId();
console.log("\n📋 Admin VRF Subscription:");
console.log("  Subscription ID:", subId.toString());
console.log("");
