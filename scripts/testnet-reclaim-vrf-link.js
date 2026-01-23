import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Reclaiming LINK from VRF subscription...\n");

  const subId = await admin.subscriptionId();
  console.log("Subscription ID:", subId.toString());

  try {
    const tx = await admin.connect(deployer).TEST_cancelVrfSubscription({
      gasLimit: 500000,
      gasPrice: 52014000
    });
    console.log("Tx:", tx.hash);
    await tx.wait();
    console.log("✅ LINK reclaimed from subscription!\n");

    // Check deployer LINK balance
    const linkAbi = ["function balanceOf(address) view returns (uint256)"];
    const link = new hre.ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, hre.ethers.provider);
    const balance = await link.balanceOf(deployer.address);
    console.log("Deployer LINK balance:", hre.ethers.formatEther(balance), "LINK");
  } catch (e) {
    console.log("❌ Failed:", e.message);
  }
}

main().catch(console.error);
