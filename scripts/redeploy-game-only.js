import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  
  console.log("Deploying updated Game contract with VRF V2.5 support...\n");
  console.log("Deployer:", deployer.address);
  
  const GameFactory = await ethers.getContractFactory("DegenerusGame", deployer);
  
  console.log("Deploying...");
  const game = await GameFactory.deploy({
    gasLimit: 10000000,
    gasPrice: 1000000000
  });
  
  await game.waitForDeployment();
  const gameAddress = await game.getAddress();
  
  console.log("✅ Game deployed at:", gameAddress);
  
  // Update deployment file
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  deployment.contracts.GAME = gameAddress;
  deployment.timestamp = new Date().toISOString();
  fs.writeFileSync("deployment-sepolia.json", JSON.stringify(deployment, null, 2));
  
  console.log("\n📋 Saved to deployment-sepolia.json");
  console.log("\n⚠️  IMPORTANT: You need to:");
  console.log("1. Wire VRF to new Game contract via Admin");
  console.log("2. Update ContractAddresses.sol and recompile other contracts that reference GAME");
  console.log("\nGame address:", gameAddress);
}

main().catch(console.error);
