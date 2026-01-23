import fs from "node:fs";
import hre from "hardhat";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  const vrfCoordinator = await ethers.getContractAt(
    'contracts/test/VRFCoordinatorV2_5Mock.sol:VRFCoordinatorV2_5Mock',
    deployment.contracts.VRF_COORDINATOR
  );
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║  FULFILL VRF AND ADVANCE GAME                                  ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  // Fulfill the next VRF request (try 3-5)
  let fulfilled = false;
  for (let requestId = 3; requestId <= 10; requestId++) {
    try {
      console.log(`Fulfilling request ID ${requestId}...`);
      const randomBytes = ethers.randomBytes(32);
      const randomWord = ethers.toBigInt(randomBytes);
      const randomWords = [randomWord];

      const tx = await vrfCoordinator.connect(deployer).fulfillRandomWords(
        requestId,
        deployment.contracts.GAME,
        randomWords,
        { gasLimit: 3000000 }
      );
      await tx.wait();
      console.log(`✅ Fulfilled request ${requestId}`);
      console.log(`Random word: ${randomWord.toString()}\n`);
      fulfilled = true;
      break;
    } catch (error) {
      // Silent skip
    }
  }

  if (!fulfilled) {
    console.log('❌ No pending VRF requests to fulfill\n');
    return;
  }

  // Wait a bit for state to settle
  console.log('Waiting 5 seconds for fulfillment to process...');
  await new Promise(resolve => setTimeout(resolve, 5000));

  // Now try to advance the game
  console.log('\n=== ADVANCING GAME ===');
  try {
    const tx = await game.connect(deployer).advanceGame(100, {
      gasLimit: 5000000,
      gasPrice: 1000000000
    });
    console.log('TX:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ advanceGame succeeded!');
    console.log('Gas used:', receipt.gasUsed.toString());

    // Check new state
    const level = await game.level();
    const gameState = await game.gameState();
    console.log('\n=== NEW GAME STATE ===');
    console.log('Level:', level.toString());
    console.log('Game State:', gameState.toString());
  } catch (error) {
    console.log('❌ advanceGame failed:', error.message.substring(0, 200));
  }
}

main().catch(console.error);
