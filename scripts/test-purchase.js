import fs from "node:fs";
import hre from "hardhat";
import { formatEther, parseEther } from "ethers";

async function main() {
  const { ethers } = hre;

  const deployment = JSON.parse(fs.readFileSync('deployment-sepolia.json', 'utf8'));
  const game = await ethers.getContractAt('contracts/DegenerusGame.sol:DegenerusGame', deployment.contracts.GAME);

  const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
  const player = new ethers.Wallet(wallets.players[0].privateKey, ethers.provider);

  console.log('=== TESTING PURCHASE ===\n');
  console.log('Player:', player.address);

  const balance = await ethers.provider.getBalance(player.address);
  console.log('Balance:', formatEther(balance), 'ETH');

  const mintPrice = await game.mintPrice();
  console.log('Mint Price:', formatEther(mintPrice), 'ETH');

  // Try to purchase
  const purchaseAmount = parseEther("0.025");
  console.log('Attempting purchase with', formatEther(purchaseAmount), 'ETH...\n');

  try {
    const purchaseParams = {
      quantity: 1,
      kind: 0, // Player
      payKind: 0, // DirectEth
      claimableAmount: 0,
      affiliateCode: "0x0000000000000000000000000000000000000000000000000000000000000000"
    };

    // Static call first to see if it would work
    await game.connect(player).purchase.staticCall(purchaseParams, { value: purchaseAmount });
    console.log('✅ Purchase would succeed');

    // Actually do it
    const tx = await game.connect(player).purchase(purchaseParams, { value: purchaseAmount });
    console.log('Transaction sent:', tx.hash);
    await tx.wait();
    console.log('✅ Purchase completed!');

  } catch (error) {
    console.log('❌ Purchase failed:', error.message);
    if (error.data) {
      console.log('Error data:', error.data);
    }
  }
}

main().catch(console.error);
