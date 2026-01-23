import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
const subId = await admin.subscriptionId();

console.log("\n💰 Funding VRF Subscription via Admin");
console.log("  Subscription ID:", subId.toString());

// Check deployer LINK balance using standard ERC20 interface
const linkAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)"
];
const link = new ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, deployer);
const linkBalance = await link.balanceOf(deployer.address);

console.log("  Deployer LINK balance:", ethers.formatEther(linkBalance), "LINK\n");

if (linkBalance > 0n) {
  const fundAmount = linkBalance; // Fund with all available LINK
  console.log("Funding with", ethers.formatEther(fundAmount), "LINK...");
  
  const tx = await admin.connect(deployer).fundVrfSubscription(fundAmount, {
    gasLimit: 500000
  });
  
  await tx.wait();
  
  console.log("✅ VRF subscription funded!");
  console.log("TX:", tx.hash);
} else {
  console.log("⚠️  No LINK available to fund subscription");
}
