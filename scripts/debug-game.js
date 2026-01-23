import fs from "node:fs";
import hre from "hardhat";
import { formatEther } from "ethers";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

  console.log('=== GAME STATE DEBUG ===\n');

  const mintPrice = await game.mintPrice();
  console.log('Mint Price:', formatEther(mintPrice), 'ETH');

  const level = await game.level();
  console.log('Level:', level.toString());

  const state = await game.gameState();
  console.log('Game State:', state.toString(), '(2=PURCHASE, 3=BURN, 1=SETUP)');

  const prizePool = await game.nextPrizePoolView();
  console.log('Prize Pool:', formatEther(prizePool), 'ETH');

  // Try to call advanceGame and see error
  console.log('\n=== TESTING ADVANCE GAME ===');
  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  try {
    await game.connect(deployer).advanceGame.staticCall(0);
    console.log('✅ advanceGame(0) would succeed');
  } catch (error) {
    console.log('❌ advanceGame(0) would revert:', error.message);

    // Try with different values
    try {
      await game.connect(deployer).advanceGame.staticCall(100);
      console.log('✅ advanceGame(100) would succeed');
    } catch (e) {
      console.log('❌ advanceGame(100) would also revert:', e.message);
    }
  }
}

main().catch(console.error);
