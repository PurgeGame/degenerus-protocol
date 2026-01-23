import fs from "node:fs";
import hre from "hardhat";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║  CHECKING RNG STATUS                                           ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  // Check game state
  const level = await game.level();
  console.log('Level:', level.toString());

  const gameState = await game.gameState();
  console.log('Game State:', gameState.toString(), '(2=PURCHASE, 3=BURN, 1=SETUP)');

  // Get block timestamp and compute current day
  const block = await ethers.provider.getBlock('latest');
  const currentTimestamp = block.timestamp;
  console.log('Block timestamp:', currentTimestamp);

  // JACKPOT_RESET_TIME is 20:00 UTC = 72000 seconds
  const JACKPOT_RESET_TIME = 72000;
  const currentDay = Math.floor((currentTimestamp - JACKPOT_RESET_TIME) / 86400);
  console.log('Computed current day:', currentDay);

  // Try to staticCall advanceGame to get the exact error
  console.log('\n=== TESTING ADVANCE GAME ===');
  try {
    await game.advanceGame.staticCall(0);
    console.log('✅ advanceGame(0) would succeed');
  } catch (error) {
    console.log('❌ advanceGame(0) would revert:');
    if (error.data) {
      console.log('Error data:', error.data);

      // Try to decode common errors
      const iface = new ethers.Interface([
        "error NotTimeYet()",
        "error RngNotReady()",
        "error MustMintToday()",
        "error PurchasesDisabled()"
      ]);
      try {
        const decoded = iface.parseError(error.data);
        console.log('Decoded error:', decoded.name);
      } catch (e) {
        console.log('Error message:', error.message.substring(0, 150));
      }
    } else {
      console.log('Error message:', error.message.substring(0, 150));
    }
  }

  console.log('Check output above to see what\'s blocking advanceGame()');
}

main().catch(console.error);
