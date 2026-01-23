import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const SUB_ID = "17001401905709230887426249162986633867013327252126643187628313616020032091031";
  const KEY_HASH = "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";
  const game = deployment.contracts.GAME;

  console.log("Testing VRF request from Game contract perspective...\n");

  // Try to simulate what the game contract does
  const gameContract = await ethers.getContractAt('DegenerusGame', game);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("Game contract:", game);
  console.log("VRF Coordinator:", VRF_COORDINATOR);
  console.log("Subscription ID:", SUB_ID);
  console.log();

  // Try staticCall on advanceGame to see where it fails
  console.log("Testing advanceGame staticCall...");
  try {
    await gameContract.connect(deployer).advanceGame.staticCall(100);
    console.log("✓ Would succeed");
  } catch (error) {
    console.log("❌ Would fail");
    
    // Try to get more details
    const msg = error.message || String(error);
    console.log("\nError details:");
    console.log(msg.substring(0, 300));
    
    if (error.data) {
      console.log("\nError data:", error.data);
      
      // Check for specific error signatures
      if (typeof error.data === 'string' && error.data.length >= 10) {
        const sig = error.data.substring(0, 10);
        const errors = {
          '0x3f73cf47': 'RngNotReady()',
          '0xb7b2409c': 'NotTimeYet()',
          '0x82b42900': 'Unauthorized()',
          '0x902621a8': 'E()',
          '0x7138356f': 'MustMintToday()'
        };
        if (errors[sig]) {
          console.log("Decoded:", errors[sig]);
        }
      }
    }
  }
}

main().catch(console.error);
