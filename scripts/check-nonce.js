import hre from "hardhat";
import wallets from "../wallets.json" with { type: "json" };

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);
  const nonce = await provider.getTransactionCount(deployer.address);
  console.log(`Current nonce: ${nonce}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
