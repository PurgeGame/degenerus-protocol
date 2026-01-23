import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const walletsData = JSON.parse(fs.readFileSync("wallets.json", "utf8"));

async function main() {
  const linkToken = await ethers.getContractAt(
    ["function balanceOf(address account) external view returns (uint256)"],
    deployment.contracts.LINK_TOKEN
  );

  const deployer = walletsData.ownerAddress;
  const otherAddress = "0x03A395f94487025A0e9D18a9C88df73e800bEFcB";

  console.log("LINK Balances:");
  console.log("==============");
  
  const deployerBalance = await linkToken.balanceOf(deployer);
  console.log(`Deployer (${deployer}):`, ethers.formatEther(deployerBalance), "LINK");
  
  const otherBalance = await linkToken.balanceOf(otherAddress);
  console.log(`Other    (${otherAddress}):`, ethers.formatEther(otherBalance), "LINK");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
