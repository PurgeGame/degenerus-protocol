import hre from "hardhat";
import fs from "fs";
import wallets from "../wallets.json" with { type: "json" };

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);
  const player0 = new hre.ethers.Wallet(wallets.players[0].privateKey, provider);

  const game = await hre.ethers.getContractAt("DegenerusGame", deployment.contracts.GAME);
  const admin = await hre.ethers.getContractAt("DegenerusAdmin", deployment.contracts.ADMIN);

  console.log("\n=== BASIC STATE ===");
  const [level, gameState, , rngLocked] = await game.purchaseInfo();
  const mintPrice = await game.mintPrice();
  console.log(`Level: ${level}`);
  console.log(`Game State: ${gameState}`);
  console.log(`RNG Locked: ${rngLocked}`);
  console.log(`Mint Price: ${hre.ethers.formatEther(mintPrice)} ETH`);

  // Check player 0 mint status
  console.log("\n=== PLAYER 0 INFO ===");
  const ethMintCount = await game.ethMintLevelCount(player0.address);
  console.log(`Player 0 ETH Mint Count: ${ethMintCount}`);

  console.log("\n=== TESTING ADVANCE WITH cap=0 ===");

  // Try calling advanceGame with player0 and cap=0
  console.log("\nTrying advanceGame(0) as player0...");
  try {
    const result = await game.connect(player0).advanceGame.staticCall(0);
    console.log(`✅ advanceGame(0) would succeed, result: ${result}`);
  } catch (e) {
    console.log(`❌ advanceGame(0) failed`);
    console.log(`Full error: ${e.toString()}`);
  }

  console.log("\n=== TESTING ADVANCE WITH cap=1 ===");

  // Try calling advanceGame with deployer and cap=1
  console.log("\nTrying advanceGame(1) as deployer (should bypass mustMintToday)...");
  try {
    const result = await game.connect(deployer).advanceGame.staticCall(1);
    console.log(`✅ advanceGame(1) would succeed, result: ${result}`);
  } catch (e) {
    console.log(`❌ advanceGame(1) failed`);
    console.log(`Full error: ${e.toString()}`);
  }

  console.log("\n=== TESTING ADVANCE DAY ===");

  // Try advancing day
  console.log("\nTrying admin.advanceDailyIdx(1) as deployer...");
  try {
    await admin.connect(deployer).advanceDailyIdx.staticCall(1);
    console.log("✅ advanceDailyIdx would succeed");
  } catch (e) {
    console.log(`❌ advanceDailyIdx failed`);
    console.log(`Full error: ${e.toString()}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
