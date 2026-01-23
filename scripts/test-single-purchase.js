import fs from "node:fs";
import hre from "hardhat";
import { formatEther, parseEther } from "ethers";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const gamepieces = await ethers.getContractAt('contracts/DegenerusGamepieces.sol:DegenerusGamepieces', deployment.contracts.GAMEPIECES);

  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const player = new ethers.Wallet(wallets.players[0].privateKey, ethers.provider);

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║  TESTING SINGLE PURCHASE                                       ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  console.log('Player:', player.address);
  const balance = await ethers.provider.getBalance(player.address);
  console.log('Balance:', formatEther(balance), 'ETH\n');

  // Check game state
  const level = await game.level();
  const gameState = await game.gameState();
  const mintPrice = await game.mintPrice();
  console.log('Game Level:', level.toString());
  console.log('Game State:', gameState.toString(), '(2=PURCHASE, 3=BURN, 1=SETUP)');
  console.log('Mint Price:', formatEther(mintPrice), 'ETH\n');

  // Try to purchase
  console.log('\n=== ATTEMPTING PURCHASE ===');

  const purchaseParams = {
    quantity: 1,
    kind: 0, // Player
    payKind: 0, // DirectEth
    payInCoin: false,
    affiliateCode: ethers.ZeroHash
  };

  console.log('Purchase params:', purchaseParams);
  console.log('Value:', formatEther(mintPrice), 'ETH\n');

  try {
    // First try staticCall to see what error we get
    console.log('Testing with staticCall first...');
    await gamepieces.connect(player).purchase.staticCall(purchaseParams, {
      value: mintPrice
    });
    console.log('✅ staticCall succeeded, purchase should work\n');
  } catch (error) {
    console.log('❌ staticCall failed:');
    console.log('Error:', error.message);

    // Try to extract revert reason
    if (error.data) {
      console.log('Error data:', error.data);
    }

    // Try with more details
    console.log('\nAttempting to get detailed revert reason...');
    try {
      const tx = await gamepieces.connect(player).purchase.populateTransaction(purchaseParams, {
        value: mintPrice
      });
      const result = await ethers.provider.call(tx);
      console.log('Call result:', result);
    } catch (callError) {
      console.log('Call error:', callError);

      // Parse error
      if (callError.data) {
        try {
          const iface = new ethers.Interface([
            "error InsufficientBalance()",
            "error SaleClosed()",
            "error InvalidQuantity()",
            "error InvalidPayment()"
          ]);
          const decoded = iface.parseError(callError.data);
          console.log('Decoded error:', decoded);
        } catch (parseError) {
          console.log('Could not decode error:', parseError.message);
        }
      }
    }
    console.log();
  }

  // Try actual transaction
  console.log('Attempting actual transaction...');
  try {
    const tx = await gamepieces.connect(player).purchase(purchaseParams, {
      value: mintPrice,
      gasLimit: 1000000
    });
    console.log('TX:', tx.hash);
    const receipt = await tx.wait();
    console.log('✅ Purchase succeeded!');
    console.log('Gas used:', receipt.gasUsed.toString());
  } catch (error) {
    console.log('❌ Purchase failed:', error.message.substring(0, 200));
  }
}

main().catch(console.error);
