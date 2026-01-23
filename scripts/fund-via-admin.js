import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const ADMIN = deployment.contracts.ADMIN;
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  
  console.log("Funding VRF subscription via Admin contract...\n");
  console.log("Admin:", ADMIN);
  
  const linkAbi = [
    "function balanceOf(address) view returns (uint256)",
    "function transferAndCall(address to, uint256 value, bytes calldata data) returns (bool)"
  ];
  
  const link = new ethers.Contract(LINK_TOKEN, linkAbi, deployer);
  
  const balance = await link.balanceOf(deployer.address);
  console.log("Deployer LINK balance:", ethers.formatEther(balance), "LINK\n");
  
  const amount = ethers.parseEther("20"); // Send 20 LINK to Admin
  
  try {
    // Admin has onTokenTransfer that auto-funds the subscription
    const tx = await link.transferAndCall(ADMIN, amount, "0x", {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx.wait();
    console.log("✅ Sent 20 LINK to Admin contract!");
    console.log("   Admin will auto-fund the subscription");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 200));
  }
}

main().catch(console.error);
