import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  COMPREHENSIVE STATE DIAGNOSTIC                                ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  // === GAME STATE ===
  console.log("🎮 GAME STATE:");
  const level = await game.level();
  const gameState = await game.gameState();
  const mintPrice = await game.mintPrice();
  console.log("  Level:", level.toString());
  console.log("  Game State:", gameState.toString(), "(1=SETUP, 2=PURCHASE, 3=BURN, 86=GAMEOVER)");
  console.log("  Mint Price:", ethers.formatEther(mintPrice), "ETH");

  // === DAILY INDEX STATE ===
  console.log("\n📅 DAILY INDEX STATE:");
  try {
    const dailyIdx = await game.dailyIdx();
    console.log("  Stored dailyIdx:", dailyIdx.toString());

    // Calculate what the current day SHOULD be from block.timestamp
    const JACKPOT_RESET_TIME = 3600; // 1 hour after midnight
    const currentBlock = await ethers.provider.getBlock('latest');
    const blockTimestamp = currentBlock.timestamp;
    const calculatedDay = Math.floor((blockTimestamp - JACKPOT_RESET_TIME) / 86400);
    console.log("  Calculated day (from block.timestamp):", calculatedDay);
    console.log("  Match:", dailyIdx.toString() === calculatedDay.toString() ? "EQUAL (will revert NotTimeYet)" : "DIFFERENT (OK)");
  } catch (e) {
    console.log("  Daily Index: (error)");
  }

  // === RNG STATE ===
  console.log("\n🎲 RNG STATE:");
  try {
    const rngFulfilled = await game.isRngFulfilled();
    console.log("  RNG Fulfilled:", rngFulfilled);
  } catch (e) {
    console.log("  RNG Fulfilled: (error)");
  }

  // === CALLER MINT STATUS ===
  console.log("\n👤 DEPLOYER MINT STATUS:");
  console.log("  Address:", deployer.address);
  try {
    const mintData = await game.mintPacked(deployer.address);
    console.log("  mintPacked:", mintData.toString());

    // Decode lastEthDay (bits 32-63)
    const lastEthDay = Number((mintData >> 32n) & ((1n << 32n) - 1n));
    console.log("  Last ETH Mint Day:", lastEthDay);

    const dailyIdx = await game.dailyIdx();
    console.log("  Current dailyIdx:", dailyIdx.toString());
    console.log("  Needs to mint today:", lastEthDay < dailyIdx ? "YES (will fail daily gate)" : "NO");
  } catch (e) {
    console.log("  Error reading mint data:", e.message.substring(0, 80));
  }

  // === CONTRACT ETH BALANCES ===
  console.log("\n💰 CONTRACT BALANCES:");
  const gameBalance = await ethers.provider.getBalance(deployment.contracts.GAME);
  const vaultBalance = await ethers.provider.getBalance(deployment.contracts.VAULT);
  console.log("  Game Contract:", ethers.formatEther(gameBalance), "ETH");
  console.log("  Vault Contract:", ethers.formatEther(vaultBalance), "ETH");

  // === DIAGNOSIS ===
  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  DIAGNOSIS                                                     ║");
  console.log("╚════════════════════════════════════════════════════════════════╝");

  if (gameState === 1n) {
    console.log("✓ Game is in SETUP");
  } else if (gameState === 2n) {
    console.log("✓ Game is in PURCHASE");
  } else if (gameState === 3n) {
    console.log("✓ Game is in BURN");
  } else if (gameState === 86n) {
    console.log("⚠ Game is in GAMEOVER");
  } else {
    console.log("⚠ Unknown game state");
  }

  console.log("\n📋 RECOMMENDED ACTIONS:");
  console.log("1. Try advanceGame with cap=100 to bypass daily gate");
  console.log("2. If still failing, check transaction on Etherscan for revert reason");
}

main().catch(console.error);
