import hre from "hardhat";
import fs from "fs";
import wallets from "../../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 100000000, // 0.1 gwei for faster confirmation
  GAS_LIMIT: 10000000
};

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  FULL SEPOLIA REDEPLOY                                         ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}\n`);

  // Step 1: Deploy Game
  console.log("📦 [1/4] Deploying DegenerusGame...");
  const GameFactory = await hre.ethers.getContractFactory("DegenerusGame");
  const game = await GameFactory.connect(deployer).deploy({
    gasLimit: CONFIG.GAS_LIMIT,
    gasPrice: CONFIG.GAS_PRICE
  });
  await game.waitForDeployment();
  const gameAddress = await game.getAddress();
  console.log(`✅ Game deployed: ${gameAddress}\n`);

  // Step 2: Deploy Admin
  console.log("📦 [2/4] Deploying DegenerusAdmin...");
  const AdminFactory = await hre.ethers.getContractFactory("DegenerusAdmin");
  const admin = await AdminFactory.connect(deployer).deploy({
    gasLimit: CONFIG.GAS_LIMIT,
    gasPrice: CONFIG.GAS_PRICE
  });
  await admin.waitForDeployment();
  const adminAddress = await admin.getAddress();
  console.log(`✅ Admin deployed: ${adminAddress}\n`);

  // Get VRF subscription ID from admin
  console.log("🔍 Getting VRF subscription ID...");
  const vrfSubId = await admin.vrfSubscriptionId();
  console.log(`VRF Subscription: ${vrfSubId}\n`);

  // Step 3: Deploy Gamepieces
  console.log("📦 [3/4] Deploying DegenerusGamepieces...");
  const GamepiecesFactory = await hre.ethers.getContractFactory("DegenerusGamepieces");
  const gamepieces = await GamepiecesFactory.connect(deployer).deploy({
    gasLimit: CONFIG.GAS_LIMIT,
    gasPrice: CONFIG.GAS_PRICE
  });
  await gamepieces.waitForDeployment();
  const gamepiecesAddress = await gamepieces.getAddress();
  console.log(`✅ Gamepieces deployed: ${gamepiecesAddress}\n`);

  // Step 4: Get BurnieCoin address
  console.log("📦 [4/4] Getting BurnieCoin address...");
  const coinAddress = await gamepieces.coin();
  console.log(`✅ BurnieCoin: ${coinAddress}\n`);

  // Save deployment
  const deployment = {
    contracts: {
      GAME: gameAddress,
      ADMIN: adminAddress,
      GAMEPIECES: gamepiecesAddress,
      COIN: coinAddress
    },
    vrfSubscriptionId: vrfSubId.toString()
  };

  fs.writeFileSync("deployment-sepolia.json", JSON.stringify(deployment, null, 2));
  console.log("💾 Saved deployment-sepolia.json\n");

  // Step 6: Setup VRF on Game
  console.log("🔧 Setting up VRF configuration...");
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B"; // Sepolia VRF V2.5
  const VRF_KEY_HASH = "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae"; // 100 gwei

  const txVrf = await game.connect(deployer).wireVrfConfig(
    VRF_COORDINATOR,
    VRF_KEY_HASH,
    vrfSubId,
    {
      gasLimit: 500000,
      gasPrice: CONFIG.GAS_PRICE
    }
  );
  await txVrf.wait();
  console.log(`✅ VRF configured\n`);

  // Step 7: Add Game as VRF consumer
  console.log("🔧 Adding Game as VRF consumer...");
  const txConsumer = await admin.connect(deployer).addVrfConsumer(gameAddress, {
    gasLimit: 500000,
    gasPrice: CONFIG.GAS_PRICE
  });
  await txConsumer.wait();
  console.log(`✅ Game added as VRF consumer\n`);

  // Step 8: Fund VRF subscription
  console.log("💰 Funding VRF subscription with LINK...");
  const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789"; // Sepolia LINK
  const link = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)", "function transferAndCall(address,uint256,bytes) returns (bool)"],
    LINK_ADDRESS
  );

  const linkBalance = await link.balanceOf(deployer.address);
  console.log(`Deployer LINK balance: ${hre.ethers.formatEther(linkBalance)} LINK`);

  if (linkBalance > 0n) {
    const data = hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [vrfSubId]);
    const txFund = await link.transferAndCall(
      VRF_COORDINATOR,
      linkBalance,
      data,
      { gasLimit: 500000, gasPrice: CONFIG.GAS_PRICE }
    );
    await txFund.wait();
    console.log(`✅ Funded VRF with ${hre.ethers.formatEther(linkBalance)} LINK\n`);
  } else {
    console.log(`⚠️  No LINK to fund VRF\n`);
  }

  // Summary
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  DEPLOYMENT COMPLETE                                           ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Game:       ${gameAddress}`);
  console.log(`Admin:      ${adminAddress}`);
  console.log(`Gamepieces: ${gamepiecesAddress}`);
  console.log(`Coin:       ${coinAddress}`);
  console.log(`VRF Sub:    ${vrfSubId}`);
  console.log(`\n✅ Ready for simulation!`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
