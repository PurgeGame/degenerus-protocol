import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  CHECKING DEPLOYED CONTRACT FUNCTIONS                         ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  // Load contracts
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const coin = await ethers.getContractAt('contracts/BurnieCoin.sol:BurnieCoin', deployment.contracts.COIN);

  console.log("\nChecking COIN contract functions...");
  console.log("Address:", deployment.contracts.COIN);

  const coinFunctions = [
    'processCoinflipPayouts',
    'creditLinkReward'
  ];

  for (const fn of coinFunctions) {
    try {
      const exists = typeof coin[fn] === 'function';
      console.log(`  ${fn}: ${exists ? '✓' : '✗'}`);
    } catch (e) {
      console.log(`  ${fn}: ✗ (error)`);
    }
  }

  console.log("\nChecking GAME contract functions...");
  console.log("Address:", deployment.contracts.GAME);

  const gameFunctions = [
    'advanceGame',
    'mintPrice',
    'level',
    'gameState',
    'dailyIdx',
    'isRngFulfilled'
  ];

  for (const fn of gameFunctions) {
    try {
      const exists = typeof game[fn] === 'function';
      console.log(`  ${fn}: ${exists ? '✓' : '✗'}`);
    } catch (e) {
      console.log(`  ${fn}: ✗ (error)`);
    }
  }

  // Try to call a function that we know should work
  console.log("\n━━━ Testing actual calls ━━━");

  try {
    const level = await game.level();
    console.log("✓ game.level():", level.toString());
  } catch (e) {
    console.log("✗ game.level():", e.message.substring(0, 80));
  }

  try {
    const mintPrice = await game.mintPrice();
    console.log("✓ game.mintPrice():", ethers.formatEther(mintPrice), "ETH");
  } catch (e) {
    console.log("✗ game.mintPrice():", e.message.substring(0, 80));
  }

  // Check if dailyIdx is accessible
  try {
    const dailyIdx = await game.dailyIdx();
    console.log("✓ game.dailyIdx():", dailyIdx.toString());
  } catch (e) {
    console.log("✗ game.dailyIdx(): Function doesn't exist or isn't public");
  }
}

main().catch(console.error);
