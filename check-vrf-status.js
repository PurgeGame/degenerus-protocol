import { ethers } from "hardhat";
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

const [signer] = await ethers.getSigners();

const game = await ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);
const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

console.log("Game VRF Subscription ID:", (await game.vrfSubscriptionId()).toString());
console.log("Admin VRF Subscription ID:", (await admin.subscriptionId()).toString());
console.log("Admin VRF Coordinator:", await admin.coordinator());
console.log("Admin VRF Key Hash:", await admin.vrfKeyHash());
