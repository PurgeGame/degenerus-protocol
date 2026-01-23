import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

const admin = await ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
const subId = await admin.subscriptionId();

console.log("\n💰 Funding VRF Subscription");
console.log("  Subscription ID:", subId.toString());

// LINK token interface
const linkAbi = [
  "function balanceOf(address) view returns (uint256)",
  "function transferAndCall(address to, uint256 amount, bytes data) returns (bool)"
];

const link = new ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, deployer);
const linkBalance = await link.balanceOf(deployer.address);

console.log("  Deployer LINK balance:", ethers.formatEther(linkBalance), "LINK\n");

if (linkBalance > 0n) {
  const fundAmount = linkBalance;
  console.log("Funding with", ethers.formatEther(fundAmount), "LINK...");
  
  // Encode subscription ID for transferAndCall
  const data = ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [subId]);
  
  const tx = await link.transferAndCall(
    deployment.contracts.VRF_COORDINATOR,
    fundAmount,
    data,
    {
      gasLimit: 500000
    }
  );
  
  await tx.wait();
  
  console.log("✅ VRF subscription funded!");
  console.log("TX:", tx.hash);
  console.log("");
} else {
  console.log("⚠️  No LINK available");
}
