import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const SUB_ID = "67458435605790242145092699974487137187740349124980291188138707277520232677082";
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  
  console.log("Funding VRF V2.5 subscription with 40 LINK...\n");
  console.log("Subscription ID:", SUB_ID);
  
  const linkAbi = [
    "function balanceOf(address) view returns (uint256)",
    "function transferAndCall(address to, uint256 value, bytes calldata data) returns (bool)"
  ];
  
  const link = new ethers.Contract(LINK_TOKEN, linkAbi, deployer);
  
  const balance = await link.balanceOf(deployer.address);
  console.log("Deployer LINK balance:", ethers.formatEther(balance), "LINK\n");
  
  const amount = ethers.parseEther("40");
  const data = ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [SUB_ID]);
  
  try {
    const tx = await link.transferAndCall(VRF_COORDINATOR, amount, data, {
      gasLimit: 500000,
      gasPrice: 1000000000
    });
    await tx.wait();
    console.log("✅ Funded with 40 LINK!");
    
    // Verify
    await new Promise(r => setTimeout(r, 2000));
    const coordinatorAbi = [
      "function getSubscription(uint256 subId) view returns (uint96, uint96, uint64, address, address[])"
    ];
    const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, ethers.provider);
    const [newBalance] = await coordinator.getSubscription(SUB_ID);
    console.log("New subscription balance:", ethers.formatEther(newBalance), "LINK");
  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 200));
  }
}

main().catch(console.error);
