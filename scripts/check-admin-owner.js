import hre from "hardhat";
import fs from "fs";
import wallets from "../wallets.json" with { type: "json" };

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  const admin = await hre.ethers.getContractAt("DegenerusAdmin", deployment.contracts.ADMIN);

  console.log("\n=== ADMIN CONTRACT INFO ===");
  const owner = await admin.owner();
  console.log(`Admin Owner: ${owner}`);
  console.log(`Deployer:    ${deployer.address}`);
  console.log(`Match: ${owner.toLowerCase() === deployer.address.toLowerCase()}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
