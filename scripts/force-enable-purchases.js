import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Enabling gamepiece purchases...\n");

  try {
    const tx = await admin.connect(deployer).TEST_enableGamepiecePurchases({
      gasLimit: 500000,
      gasPrice: 52014000
    });
    console.log("Tx:", tx.hash);
    await tx.wait();
    console.log("✅ Purchases enabled!\n");
  } catch (e) {
    console.log("❌ Failed:", e.message);
  }
}

main().catch(console.error);
