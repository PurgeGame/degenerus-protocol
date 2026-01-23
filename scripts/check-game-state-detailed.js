import hre from "hardhat";
import fs from "fs";
import wallets from "../wallets.json" with { type: "json" };

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);
  const player0 = new hre.ethers.Wallet(wallets.players[0].privateKey, provider);

  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);
  console.log("\n=== GAME STATE ===");
  const level = await game.level();
  const dailyIdx = await game.dailyIdx();
  const state = await game.gameState();

  console.log(`Level: ${level}`);
  console.log(`DailyIdx: ${dailyIdx}`);
  console.log(`State: ${state}`);

  console.log("\n=== PLAYER 0 STATE ===");
  const player0Mints = await game.ethMintLevelCount(player0.address);
  console.log(`Player 0 ETH Mint Count: ${player0Mints}`);

  console.log("\n=== VRF STATE ===");
  const vrfCoord = await game.vrfCoordinator();
  const vrfSubId = await game.vrfSubscriptionId();
  const vrfKeyHash = await game.vrfKeyHash();
  console.log(`VRF Coordinator: ${vrfCoord}`);
  console.log(`VRF Subscription: ${vrfSubId}`);
  console.log(`VRF Key Hash: ${vrfKeyHash}`);

  console.log("\n=== TESTING ADVANCE CALLS ===");

  // Try calling advanceGame with player0 and cap=0
  console.log("\nTrying advanceGame(0) as player0...");
  try {
    await game.connect(player0).advanceGame.staticCall(0);
    console.log("✅ advanceGame(0) would succeed");
  } catch (e) {
    console.log(`❌ advanceGame(0) would fail: ${e.message.substring(0, 200)}`);

    // Try with deployer
    console.log("\nTrying advanceGame(0) as deployer...");
    try {
      await game.connect(deployer).advanceGame.staticCall(0);
      console.log("✅ advanceGame(0) as deployer would succeed");
    } catch (e2) {
      console.log(`❌ advanceGame(0) as deployer would fail: ${e2.message.substring(0, 200)}`);
    }
  }

  // Try advancing day
  console.log("\nTrying advanceDailyIdx() as deployer...");
  try {
    await game.connect(deployer).advanceDailyIdx.staticCall();
    console.log("✅ advanceDailyIdx would succeed");
  } catch (e) {
    console.log(`❌ advanceDailyIdx would fail: ${e.message.substring(0, 200)}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
