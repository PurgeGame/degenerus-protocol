import hre from "hardhat";
const { ethers } = hre;
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));
const wallets = JSON.parse(fs.readFileSync('wallets.json', 'utf8'));

async function main() {
  const LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const ADMIN_ADDRESS = deployment.contracts.ADMIN;
  const SUB_ID = "17001401905709230887426249162986633867013327252126643187628313616020032091031";

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  FUNDING VRF SUBSCRIPTION WITH 35 MORE LINK                    ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const deployer = new ethers.Wallet(wallets.ownerPrivateKey, ethers.provider);
  
  const linkAbi = [
    "function balanceOf(address) view returns (uint256)",
    "function transferAndCall(address to, uint256 value, bytes calldata data) returns (bool)"
  ];

  const link = new ethers.Contract(LINK_TOKEN, linkAbi, deployer);

  // Check deployer's LINK balance
  const balance = await link.balanceOf(deployer.address);
  console.log("Deployer LINK balance:", ethers.formatEther(balance), "LINK");

  const amountToSend = ethers.parseEther("35");
  console.log("Amount to send:", ethers.formatEther(amountToSend), "LINK");
  console.log();

  if (balance < amountToSend) {
    console.log("❌ Insufficient LINK balance!");
    console.log("   Need:", ethers.formatEther(amountToSend), "LINK");
    console.log("   Have:", ethers.formatEther(balance), "LINK");
    console.log("\n   Get testnet LINK at: https://faucets.chain.link/sepolia");
    return;
  }

  console.log("Sending LINK to Admin contract (will auto-fund subscription)...");
  
  try {
    // transferAndCall to Admin contract - it will handle funding the subscription
    const tx = await link.transferAndCall(
      ADMIN_ADDRESS,
      amountToSend,
      "0x", // empty data
      {
        gasLimit: 500000,
        gasPrice: 1000000000
      }
    );
    
    console.log("TX sent:", tx.hash);
    const receipt = await tx.wait();
    console.log("✅ Transaction confirmed!");
    console.log("Gas used:", receipt.gasUsed.toString());

    // Check new subscription balance
    await new Promise(r => setTimeout(r, 2000)); // Wait a bit for state to update

    const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
    const coordinatorAbi = [
      "function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, address[] memory consumers)"
    ];
    const coordinator = new ethers.Contract(VRF_COORDINATOR, coordinatorAbi, ethers.provider);
    const [newBalance] = await coordinator.getSubscription(SUB_ID);

    console.log("\n📊 NEW SUBSCRIPTION BALANCE:", ethers.formatEther(newBalance), "LINK");

  } catch (error) {
    console.log("❌ Failed:", error.message.substring(0, 150));
  }
}

main().catch(console.error);
