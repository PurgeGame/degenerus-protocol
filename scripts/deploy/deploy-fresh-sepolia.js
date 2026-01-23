import hre from "hardhat";
import fs from "fs";
import wallets from "../../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 100000000,
  GAS_LIMIT: 10000000
};

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  FRESH SEPOLIA DEPLOYMENT                                      ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}\n`);
  console.log(`⚠️  This requires updating ContractAddresses.sol between deployments`);
  console.log(`    Deploy Game first, then update addresses, then deploy others.\n`);

  // Step 1: Deploy just Game first
  console.log("📦 [1/1] Deploying DegenerusGame...");
  const GameFactory = await hre.ethers.getContractFactory("DegenerusGame");
  const game = await GameFactory.connect(deployer).deploy({
    gasLimit: CONFIG.GAS_LIMIT,
    gasPrice: CONFIG.GAS_PRICE
  });
  await game.waitForDeployment();
  const gameAddress = await game.getAddress();
  console.log(`✅ Game deployed: ${gameAddress}\n`);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  NEXT STEPS                                                    ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`1. Update contracts/ContractAddresses.sol:`);
  console.log(`   address internal constant GAME = ${gameAddress};\n`);
  console.log(`2. Run: npx hardhat compile --force\n`);
  console.log(`3. Run: npx hardhat run scripts/deploy/deploy-rest-sepolia.js --network sepolia\n`);

  // Save partial deployment
  const deployment = {
    contracts: {
      GAME: gameAddress
    }
  };

  fs.writeFileSync("deployment-sepolia-partial.json", JSON.stringify(deployment, null, 2));
  console.log("💾 Saved deployment-sepolia-partial.json");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
