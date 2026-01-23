import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));
const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

console.log("Checking player wallet balances...\n");

const REQUIRED_BALANCE = ethers.parseEther("0.01"); // 0.01 ETH per player
const FUND_AMOUNT = ethers.parseEther("0.02"); // Fund with 0.02 ETH

for (let i = 0; i < 10; i++) {
  const playerData = wallets.players[i];
  const playerWallet = new ethers.Wallet(playerData.privateKey, ethers.provider);
  const balance = await ethers.provider.getBalance(playerWallet.address);

  console.log(`Player ${i}: ${playerWallet.address}`);
  console.log(`  Balance: ${ethers.formatEther(balance)} ETH`);

  if (balance < REQUIRED_BALANCE) {
    console.log(`  Funding with ${ethers.formatEther(FUND_AMOUNT)} ETH...`);

    try {
      const tx = await deployer.sendTransaction({
        to: playerWallet.address,
        value: FUND_AMOUNT,
        gasLimit: 21000,
        gasPrice: 100000000 // 0.1 gwei
      });
      await tx.wait();
      console.log(`  ✓ Funded`);
    } catch (e) {
      console.log(`  ❌ Failed: ${e.message.substring(0, 40)}`);
    }
  } else {
    console.log(`  ✓ Already funded`);
  }

  console.log();
}

console.log("Player funding check complete");
