import fs from "node:fs";
import { ethers } from "ethers";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey);

console.log("Deployer address:", deployer.address);
console.log("\nCheck recent transactions and reverts at:");
console.log(`https://sepolia.etherscan.io/address/${deployer.address}`);
