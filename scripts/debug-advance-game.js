import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const game = await ethers.getContractAt('DegenerusGame', deployment.contracts.GAME);
  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  console.log("Debugging advanceGame revert...\n");

  // Try staticCall with detailed error handling
  try {
    const tx = await game.connect(deployer).advanceGame.populateTransaction(100);
    console.log("Populated transaction:", tx);

    console.log("\nCalling transaction...");
    const result = await ethers.provider.call(tx);
    console.log("Success:", result);
  } catch (error) {
    console.log("❌ Call failed");
    console.log("\nFull error:", error);
    console.log("\nError message:", error.message);

    if (error.data) {
      console.log("\nError data:", error.data);

      // Try to decode the error
      const errorData = error.data;

      // Common custom error selectors
      const errorSelectors = {
        "0x3f73cf47": "RngNotReady()",
        "0xb7b2409c": "NotTimeYet()",
        "0x82b42900": "Unauthorized()",
        "0x902621a8": "E()",
        "0x3ee5aeb5": "SafeTransferFailed()",
        "0x08c379a0": "Error(string)",
        "0x4e487b71": "Panic(uint256)"
      };

      if (typeof errorData === 'string') {
        const selector = errorData.slice(0, 10);
        console.log("\nError selector:", selector);

        if (errorSelectors[selector]) {
          console.log("Decoded error:", errorSelectors[selector]);
        } else {
          console.log("Unknown error selector");

          // If it's Error(string), decode the message
          if (selector === '0x08c379a0') {
            try {
              const reason = ethers.AbiCoder.defaultAbiCoder().decode(['string'], '0x' + errorData.slice(10));
              console.log("Error message:", reason[0]);
            } catch (e) {
              console.log("Could not decode error message");
            }
          }
        }
      }
    }

    // Try to get more info from the error object
    if (error.error) {
      console.log("\nNested error:", error.error);
    }

    if (error.code) {
      console.log("\nError code:", error.code);
    }

    if (error.action) {
      console.log("Error action:", error.action);
    }
  }
}

main().catch(console.error);
