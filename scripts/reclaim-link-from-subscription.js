import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

// OLD Admin address from PREVIOUS deployment
const oldAdminAddress = "0x90f5F37E78eb7dC80822a702f5001b8E5F74b56F";

console.log("\n🔄 Reclaiming LINK from old VRF subscription\n");

const oldAdmin = await ethers.getContractAt(
  'contracts/DegenerusAdmin.sol:DegenerusAdmin',
  oldAdminAddress
);

const oldSubId = await oldAdmin.subscriptionId();
console.log("Old Admin:", oldAdminAddress);
console.log("Old subscription ID:", oldSubId.toString());
console.log("");

try {
  console.log("Canceling old subscription...");
  
  const tx = await oldAdmin.connect(deployer).TEST_cancelVrfSubscription({
    gasLimit: 500000
  });
  
  console.log("TX hash:", tx.hash);
  await tx.wait();
  
  console.log("✅ LINK reclaimed from old subscription!");
  console.log("");
  
  // Check deployer's new LINK balance
  const linkAbi = ["function balanceOf(address) view returns (uint256)"];
  const link = new ethers.Contract("0x779877A7B0D9E8603169DdbD7836e478b4624789", linkAbi, ethers.provider);
  const balance = await link.balanceOf(deployer.address);
  
  console.log("Deployer LINK balance:", ethers.formatEther(balance), "LINK");
  
} catch (error) {
  console.error("❌ Error:", error.message);
}
