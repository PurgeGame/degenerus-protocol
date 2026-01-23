import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  TESTING DIRECT VRF REQUEST FROM GAME CONTRACT                 ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const SUB_ID = "17001401905709230887426249162986633867013327252126643187628313616020032091031";
  const KEY_HASH = "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";
  const GAME = deployment.contracts.GAME;

  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);

  // Create coordinator contract instance
  const coordinatorAbi = [
    "function requestRandomWords((bytes32,uint256,uint16,uint32,uint32)) external returns (uint256)"
  ];
  
  const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, deployer);

  console.log("VRF Coordinator:", VRF_COORDINATOR);
  console.log("Subscription ID:", SUB_ID);
  console.log("Key Hash:", KEY_HASH);
  console.log("Caller (deployer):", deployer.address);
  console.log("Game (consumer):", GAME);
  console.log();

  // Try to request from deployer address (will fail - not a consumer)
  console.log("Attempt 1: Request from deployer (should fail - not registered consumer)");
  try {
    await coordinator.requestRandomWords.staticCall([
      KEY_HASH,
      SUB_ID,
      10, // requestConfirmations
      200000, // callbackGasLimit
      1 // numWords
    ]);
    console.log("  ✓ Would succeed (unexpected!)");
  } catch (error) {
    const msg = error.message || String(error);
    if (msg.includes('InvalidConsumer')) {
      console.log("  ✓ Correctly rejected: InvalidConsumer");
    } else {
      console.log("  ✗ Error:", msg.substring(0, 100));
    }
  }

  // Now try staticCall from Game contract perspective
  console.log("\nAttempt 2: Check if Game contract can request");
  
  const game = await ethers.getContractAt('DegenerusGame', GAME);
  
  // Try to see what happens when game tries to request
  console.log("Testing game.advanceGame staticCall with detailed trace...");
  
  try {
    // Use eth_call with from address as Game contract
    const gameIface = game.interface;
    const data = gameIface.encodeFunctionData('advanceGame', [100]);
    
    const result = await ethers.provider.call({
      to: GAME,
      from: deployer.address,
      data: data,
      gasLimit: 5000000
    });
    
    console.log("  ✓ Would succeed");
  } catch (error) {
    console.log("  ✗ Would fail");
    
    // Try to extract revert reason
    if (error.data) {
      console.log("\n  Error data:", error.data);
      
      // Try to decode
      try {
        if (error.data.startsWith('0x08c379a0')) {
          // Error(string)
          const reason = ethers.AbiCoder.defaultAbiCoder().decode(['string'], '0x' + error.data.slice(10));
          console.log("  Revert reason:", reason[0]);
        }
      } catch (e) {
        // Can't decode
      }
    }
    
    console.log("  Error message:", (error.message || String(error)).substring(0, 150));
  }
}

main().catch(console.error);
