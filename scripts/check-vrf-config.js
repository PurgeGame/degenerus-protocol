import hre from "hardhat";
import fs from "fs";

async function main() {
  const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
  const admin = await hre.ethers.getContractAt('contracts/DegenerusAdmin.sol:DegenerusAdmin', deployment.contracts.ADMIN);

  console.log("VRF Configuration in Admin contract:\n");

  try {
    const callbackGasLimit = await admin.callbackGasLimit();
    console.log("  Callback Gas Limit:", callbackGasLimit.toString());
  } catch (e) {
    console.log("  callbackGasLimit: not accessible");
  }

  try {
    const requestConfirmations = await admin.requestConfirmations();
    console.log("  Request Confirmations:", requestConfirmations.toString());
  } catch (e) {
    console.log("  requestConfirmations: not accessible");
  }

  try {
    const numWords = await admin.numWords();
    console.log("  Num Words:", numWords.toString());
  } catch (e) {
    console.log("  numWords: not accessible");
  }

  const subId = await admin.subscriptionId();
  console.log("  Subscription ID:", subId.toString());

  console.log("\n📊 Checking if VRF callback might be failing:");
  console.log("  - If callback gas limit is too low, rawFulfillRandomWords will fail");
  console.log("  - Recommended callback gas limit: 500,000 - 2,500,000");
  console.log("  - Check Etherscan for failed rawFulfillRandomWords transactions");
}

main().catch(console.error);
