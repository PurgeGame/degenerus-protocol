import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const [deployer] = await hre.ethers.getSigners();

  const linkAbi = ["function balanceOf(address) view returns (uint256)"];
  const link = new hre.ethers.Contract(deployment.contracts.LINK_TOKEN, linkAbi, hre.ethers.provider);
  
  const balance = await link.balanceOf(deployer.address);
  console.log("Deployer LINK balance:", hre.ethers.formatEther(balance), "LINK");
}

main().catch(console.error);
