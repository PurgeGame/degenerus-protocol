import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const [deployer] = await hre.ethers.getSigners();

  console.log("Funding VRF via Admin contract...\n");

  // Transfer LINK to Admin
  console.log("Transferring 75 LINK to Admin contract...");
  const linkAbi = [
    "function transfer(address to, uint256 value) external returns (bool)",
    "function balanceOf(address) view returns (uint256)"
  ];
  const link = new hre.ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, deployer);
  
  const fundAmount = hre.ethers.parseEther("75");
  
  const txTransfer = await link.transfer(
    deployment.contracts.ADMIN,
    fundAmount,
    { gasLimit: 100000, gasPrice: 52014000 }
  );
  console.log("Tx:", txTransfer.hash);
  await txTransfer.wait();
  console.log("✅ Transferred 75 LINK to Admin\n");

  // Call fundVrf on Admin
  console.log("Calling admin.TEST_fundVrf(75 ether)...");
  const tx = await admin.connect(deployer).TEST_fundVrf(fundAmount, {
    gasLimit: 500000,
    gasPrice: 52014000
  });
  console.log("Tx:", tx.hash);
  await tx.wait();
  console.log("✅ VRF funded via Admin!\n");

  // Check subscription
  const subId = await admin.subscriptionId();
  console.log("Subscription ID:", subId.toString());
}

main().catch(console.error);
