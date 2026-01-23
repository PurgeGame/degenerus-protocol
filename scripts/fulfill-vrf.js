import fs from "node:fs";
import hre from "hardhat";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║  FULFILLING PENDING VRF REQUESTS                               ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  // Connect to VRF coordinator (Mock)
  const vrfCoordinator = await ethers.getContractAt(
    'contracts/test/VRFCoordinatorV2_5Mock.sol:VRFCoordinatorV2_5Mock',
    deployment.contracts.VRF_COORDINATOR
  );

  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);

  console.log('VRF Coordinator:', deployment.contracts.VRF_COORDINATOR);
  console.log('Game:', deployment.contracts.GAME);

  // Check if there are pending requests
  try {
    // Get subscription ID (should be 1 based on deployment)
    const subId = 1;

    console.log('\nAttempting to fulfill pending VRF requests...\n');

    // The mock VRF might have a function to get pending requests
    // For now, let's try to fulfill with a random request ID
    // Usually the first request ID is 1

    for (let requestId = 1; requestId <= 10; requestId++) {
      try {
        console.log(`Attempting to fulfill request ID ${requestId}...`);

        // Generate random words (1 word for most requests)
        const randomBytes = ethers.randomBytes(32);
        const randomWord = ethers.toBigInt(randomBytes);
        const randomWords = [randomWord];

        const tx = await vrfCoordinator.connect(deployer).fulfillRandomWords(
          requestId,
          deployment.contracts.GAME,
          randomWords,
          {
            gasLimit: 3000000
          }
        );

        await tx.wait();
        console.log(`  ✅ Fulfilled request ${requestId}`);
        console.log(`  Random word: ${randomWord.toString()}`);
        console.log(`  TX: ${tx.hash}\n`);
        break; // Stop after first successful fulfillment
      } catch (error) {
        if (error.message.includes('nonexistent request') || error.message.includes('not found') ||
            error.message.includes('AlreadyFulfilled')) {
          // Silent skip for expected errors
        } else {
          console.log(`  ❌ Failed: ${error.message.substring(0, 100)}\n`);
        }
      }
    }

    // Check game RNG status after fulfillment
    console.log('\n=== CHECKING GAME RNG STATUS ===');
    try {
      const rngLocked = await game.rngLocked();
      console.log('rngLocked:', rngLocked);

      const lastRngWord = await game.lastRngWord();
      console.log('lastRngWord:', lastRngWord.toString());

      if (!rngLocked && lastRngWord !== 0n) {
        console.log('\n✅ RNG fulfilled! Game should be able to advance now.');
      } else if (rngLocked) {
        console.log('\n⚠️  RNG still locked. May need to wait for fulfillment or retry.');
      }
    } catch (e) {
      console.log('Error checking RNG status:', e.message);
    }

  } catch (error) {
    console.error('Error fulfilling VRF:', error.message);
  }
}

main().catch(console.error);
