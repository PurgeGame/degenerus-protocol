import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);
  const [deployer] = await hre.ethers.getSigners();

  const subId = await admin.subscriptionId();
  console.log("Subscription ID:", subId.toString());

  const linkAbi = [
    "function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool success)",
    "function balanceOf(address) view returns (uint256)"
  ];
  const link = new hre.ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, deployer);
  
  const balance = await link.balanceOf(deployer.address);
  console.log("Current LINK balance:", hre.ethers.formatEther(balance), "LINK\n");

  console.log("Funding subscription with all LINK...");
  const data = hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [subId]);
  
  const txFund = await link.transferAndCall(
    deployment.contracts.VRF_COORDINATOR,
    balance,
    data,
    { gasLimit: 500000, gasPrice: 52014000 }
  );
  console.log("Tx:", txFund.hash);
  await txFund.wait();
  console.log("✅ Funded subscription\n");

  const newBalance = await link.balanceOf(deployer.address);
  console.log("Remaining LINK:", hre.ethers.formatEther(newBalance));
}

main().catch(console.error);
