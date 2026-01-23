import hre from "hardhat";
const { ethers } = hre;

async function main() {
  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  CHECKING VRF COORDINATOR V2.5 INTERFACE                       ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log("Address:", VRF_COORDINATOR);
  console.log();

  // Check contract exists
  const code = await ethers.provider.getCode(VRF_COORDINATOR);
  if (code === "0x") {
    console.log("❌ No contract at this address!");
    return;
  }
  console.log("✓ Contract exists\n");

  // Chainlink VRF V2.5 uses VRFV2PlusClient.RandomWordsRequest struct
  // The struct has an extraArgs field for native payment

  console.log("Testing VRF V2.5 Plus interface...");

  // This is the correct V2.5 signature with extraArgs
  const v25Abi = [
    "function requestRandomWords((bytes32 keyHash,uint256 subId,uint16 requestConfirmations,uint32 callbackGasLimit,uint32 numWords,bytes extraArgs)) external returns (uint256)"
  ];

  try {
    const coordinator = new ethers.Contract(VRF_COORDINATOR, v25Abi, ethers.provider);
    console.log("✓ VRF V2.5 Plus format detected");
    console.log("  Function: requestRandomWords(VRFV2PlusClient.RandomWordsRequest)");
    console.log("  Note: Requires 'extraArgs' field (6th parameter)\n");
  } catch (e) {
    console.log("✗ Could not instantiate with V2.5 format\n");
  }

  console.log("━━━ DIAGNOSIS ━━━");
  console.log("VRF V2.5 Plus requires an 'extraArgs' parameter that our contract doesn't provide!");
  console.log("\nOur game contract calls:");
  console.log("  requestRandomWords(VRFRandomWordsRequest{keyHash, subId, confirmations, gasLimit, numWords})");
  console.log("\nBut V2.5 Plus expects:");
  console.log("  requestRandomWords(VRFV2PlusClient.RandomWordsRequest{...same fields..., extraArgs})");
  console.log("\nThe extraArgs field is for native token payment configuration.");
  console.log("For LINK payment, it should be empty bytes: 0x");
  console.log("\n📋 SOLUTION:");
  console.log("The Game contract needs to be updated to add the extraArgs field");
  console.log("OR we need to use VRF V2 (not V2.5) coordinator");

  console.log("\n🔗 View contract on Etherscan:");
  console.log("https://sepolia.etherscan.io/address/" + VRF_COORDINATOR + "#code");
}

main().catch(console.error);
