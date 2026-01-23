import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const [deployer] = await hre.ethers.getSigners();

  // Get subscription ID
  const subId = await admin.subscriptionId();
  console.log("Subscription ID:", subId.toString());

  // Fund with LINK
  console.log("\nFunding subscription with 75 LINK...");
  const linkAbi = [
    "function transferAndCall(address to, uint256 value, bytes memory data) external returns (bool)",
    "function balanceOf(address) view returns (uint256)"
  ];
  const link = new hre.ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, deployer);
  
  const fundAmount = hre.ethers.parseEther("75");
  const data = hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [subId]);
  
  const txFund = await link.transferAndCall(
    deployment.contracts.VRF_COORDINATOR,
    fundAmount,
    data,
    { gasLimit: 500000, gasPrice: 52014000 }
  );
  console.log("Tx:", txFund.hash);
  await txFund.wait();
  console.log("✅ Funded with 75 LINK\n");

  const balance = await link.balanceOf(deployer.address);
  console.log("Remaining LINK:", hre.ethers.formatEther(balance));
}

main().catch(console.error);
