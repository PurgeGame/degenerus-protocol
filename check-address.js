import { ethers } from "hardhat";
import fs from "node:fs";

const walletsData = JSON.parse(fs.readFileSync("wallets.json", "utf8"));

console.log("Deployer from wallets.json:", walletsData.ownerAddress);
console.log("Target address:", "0x03A395f94487025A0e9D18a9C88df73e800bEFcB");
console.log();

// Check if it matches the private key from .env
if (process.env.PRIVATE_KEY) {
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY);
  console.log("Address from .env PRIVATE_KEY:", wallet.address);
}

// Check all players
for (let i = 0; i < walletsData.players.length; i++) {
  const player = walletsData.players[i];
  const wallet = new ethers.Wallet(player.privateKey);
  if (wallet.address.toLowerCase() === "0x03A395f94487025A0e9D18a9C88df73e800bEFcB".toLowerCase()) {
    console.log(`Found match: ${player.name} (${wallet.address})`);
  }
}
