import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const gamepieces = await ethers.getContractAt('contracts/DegenerusGamepieces.sol:DegenerusGamepieces', deployment.contracts.GAMEPIECES);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("Deployer:", deployer.address);
  console.log();

  // Check game state
  const mintPrice = await game.mintPrice();
  console.log("Mint Price:", ethers.formatEther(mintPrice), "ETH");

  // Make a purchase as deployer
  console.log("\nMaking purchase as deployer...");
  try {
    const purchaseParams = {
      quantity: 1,
      kind: 0,
      payKind: 0,
      payInCoin: false,
      affiliateCode: ethers.ZeroHash
    };

    const tx = await gamepieces.connect(deployer).purchase(purchaseParams, {
      value: mintPrice,
      gasLimit: 1000000,
      gasPrice: 1000000000
    });
    await tx.wait();
    console.log("✅ Purchase succeeded\n");
  } catch (error) {
    console.log("❌ Purchase failed:", error.message.substring(0, 100));
    console.log("Continuing anyway...\n");
  }

  // Now try advanceGame with cap=0
  console.log("Attempting advanceGame with cap=0...");
  try {
    const tx = await game.connect(deployer).advanceGame(0, {
      gasLimit: 5000000,
      gasPrice: 1000000000
    });
    await tx.wait();
    console.log("✅ advanceGame succeeded!");
  } catch (error) {
    console.log("❌ advanceGame failed:", error.message.substring(0, 200));

    // Try with cap=100
    console.log("\nTrying advanceGame with cap=100...");
    try {
      const tx2 = await game.connect(deployer).advanceGame(100, {
        gasLimit: 5000000,
        gasPrice: 1000000000
      });
      await tx2.wait();
      console.log("✅ advanceGame with cap=100 succeeded!");
    } catch (error2) {
      console.log("❌ advanceGame with cap=100 also failed:", error2.message.substring(0, 200));
    }
  }
}

main().catch(console.error);
