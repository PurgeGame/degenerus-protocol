import hre from "hardhat";
import fs from "fs";
import { getCreateAddress } from "ethers";
import wallets from "../../wallets.json" with { type: "json" };

const CONFIG = {
  GAS_PRICE: 100000000,
  GAS_LIMIT: 10000000
};

const DEPLOY_ORDER = [
  "Icons32Data",
  "TrophySvgAssets",
  "DegenerusGameMintModule",
  "DegenerusGameJackpotModule",
  "DegenerusGameEndgameModule",
  "BurnieCoin",
  "DegenerusVault",
  "DegenerusAffiliate",
  "DegenerusJackpots",
  "DegenerusQuests",
  "IconColorRegistry",
  "IconRendererRegular32",
  "IconRendererTrophy32Svg",
  "IconRendererTrophy32",
  "GamepieceRendererRouter",
  "TrophyRendererRouter",
  "DegenerusTrophies",
  "DegenerusGamepieces",
  "DegenerusGame",
  "DegenerusAdmin"
];

function generateContractAddresses(addresses) {
  return `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ContractAddresses {
    // Network Constants
    address internal constant CREATOR = 0xceE410a785AA2D4a78130FB9bF519408c115C21b;
    address internal constant STETH_TOKEN = 0x3e3FE7dBc6B4C189E7128855dD526361c49b40Af; // Sepolia stETH
    address internal constant LINK_TOKEN = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // Sepolia LINK
    address internal constant VRF_COORDINATOR = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; // Sepolia VRF V2.5
    bytes32 internal constant VRF_KEY_HASH = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; // 100 gwei

    // Cost divisor for testnet (divide all ETH amounts by 1,000,000)
    uint256 internal constant COST_DIVISOR = 1_000_000;

    // Contract Addresses (Precomputed)
    address internal constant ICONS_32 = ${addresses.Icons32Data};
    address internal constant TROPHY_SVG_ASSETS = ${addresses.TrophySvgAssets};
    address internal constant GAME_MINT_MODULE = ${addresses.DegenerusGameMintModule};
    address internal constant GAME_JACKPOT_MODULE = ${addresses.DegenerusGameJackpotModule};
    address internal constant GAME_ENDGAME_MODULE = ${addresses.DegenerusGameEndgameModule};
    address internal constant COIN = ${addresses.BurnieCoin};
    address internal constant VAULT = ${addresses.DegenerusVault};
    address internal constant AFFILIATE = ${addresses.DegenerusAffiliate};
    address internal constant JACKPOTS = ${addresses.DegenerusJackpots};
    address internal constant QUESTS = ${addresses.DegenerusQuests};
    address internal constant ICON_COLOR_REGISTRY = ${addresses.IconColorRegistry};
    address internal constant RENDERER_REGULAR = ${addresses.IconRendererRegular32};
    address internal constant RENDERER_TROPHY_SVG = ${addresses.IconRendererTrophy32Svg};
    address internal constant RENDERER_TROPHY = ${addresses.IconRendererTrophy32};
    address internal constant GAMEPIECE_RENDERER_ROUTER = ${addresses.GamepieceRendererRouter};
    address internal constant TROPHY_RENDERER_ROUTER = ${addresses.TrophyRendererRouter};
    address internal constant TROPHIES = ${addresses.DegenerusTrophies};
    address internal constant GAMEPIECES = ${addresses.DegenerusGamepieces};
    address internal constant GAME = ${addresses.DegenerusGame};
    address internal constant ADMIN = ${addresses.DegenerusAdmin};
}
`;
}

async function reclaimLinkFromOldDeployments(deployer) {
  console.log("=== RECLAIMING LINK FROM OLD DEPLOYMENTS ===\n");

  const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
  const vrfCoordinator = await hre.ethers.getContractAt(
    ["function getSubscription(uint256 subId) external view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] memory consumers)"],
    VRF_COORDINATOR
  );

  try {
    // Collect unique Admin contract addresses from deployment files
    const adminAddresses = new Set();

    // Check deployment files
    const deploymentFiles = [
      "deployment-sepolia.json",
      "deployment-sepolia.json.bak"
    ];

    for (const file of deploymentFiles) {
      if (fs.existsSync(file)) {
        try {
          const deployment = JSON.parse(fs.readFileSync(file, "utf8"));
          if (deployment.contracts?.ADMIN) {
            adminAddresses.add(deployment.contracts.ADMIN.toLowerCase());
            console.log(`Found Admin in ${file}: ${deployment.contracts.ADMIN}`);
          }
        } catch (e) {
          // Skip invalid files
        }
      }
    }

    if (adminAddresses.size === 0) {
      console.log(`No previous deployments found\n`);
      return;
    }

    console.log(`Checking ${adminAddresses.size} Admin contract(s)...\n`);

    let totalReclaimed = 0n;
    let reclaimedCount = 0;

    // Try to reclaim from each Admin
    for (const adminAddr of adminAddresses) {
      try {
        console.log(`Admin: ${adminAddr}`);

        // Try to instantiate as DegenerusAdmin
        const admin = await hre.ethers.getContractAt("DegenerusAdmin", adminAddr);

        // Check if it has a subscription
        let subId;
        try {
          subId = await admin.subscriptionId();
        } catch (e) {
          console.log(`  ⏭️  Not a valid Admin contract\n`);
          continue;
        }

        if (subId === 0n) {
          console.log(`  ⏭️  No active subscription\n`);
          continue;
        }

        console.log(`  Subscription ID: ${subId}`);

        // Get subscription balance
        const [balance] = await vrfCoordinator.getSubscription(subId);
        console.log(`  Balance: ${hre.ethers.formatEther(balance)} LINK`);

        if (balance === 0n) {
          console.log(`  ⏭️  Empty balance\n`);
          continue;
        }

        // Try to cancel it
        console.log(`  💰 Cancelling subscription...`);
        const tx = await admin.connect(deployer).TEST_cancelVrfSubscription({
          gasLimit: 500000,
          gasPrice: CONFIG.GAS_PRICE
        });
        await tx.wait();

        totalReclaimed += balance;
        reclaimedCount++;
        console.log(`  ✅ Reclaimed ${hre.ethers.formatEther(balance)} LINK!\n`);
      } catch (e) {
        console.log(`  ⚠️  Failed: ${e.message.substring(0, 80)}\n`);
      }
    }

    if (reclaimedCount > 0) {
      console.log(`✅ Total reclaimed: ${hre.ethers.formatEther(totalReclaimed)} LINK from ${reclaimedCount} deployment(s)\n`);
    } else {
      console.log(`No LINK to reclaim\n`);
    }
  } catch (e) {
    console.log(`⚠️  Error during LINK reclamation: ${e.message.substring(0, 100)}`);
    console.log(`Continuing with deployment...\n`);
  }
}

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  ADAPTIVE REDEPLOY - RETRY UNTIL SUCCESS                       ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}\n`);

  // Reclaim LINK from all old deployments before deploying
  await reclaimLinkFromOldDeployments(deployer);

  const deployed = {};
  let deployedCount = 0;

  while (deployedCount < DEPLOY_ORDER.length) {
    // Get current nonce (pending to include mempool txs)
    const currentNonce = await provider.getTransactionCount(deployer.address, "pending");
    console.log(`Current nonce: ${currentNonce} (deploying ${DEPLOY_ORDER[deployedCount]})`);

    // Precompute remaining addresses
    const addresses = {};
    for (let i = 0; i < DEPLOY_ORDER.length; i++) {
      const addr = getCreateAddress({
        from: deployer.address,
        nonce: currentNonce + (i - deployedCount)
      });
      addresses[DEPLOY_ORDER[i]] = addr;
    }

    // Update ContractAddresses.sol
    fs.writeFileSync("contracts/ContractAddresses.sol", generateContractAddresses(addresses));

    // Compile (suppress output after first time)
    if (deployedCount === 0) {
      console.log("\n=== COMPILING ===\n");
      await hre.run("compile");
      console.log("✅ Compiled\n");
    } else {
      await hre.run("compile");
    }

    // Try to deploy the next contract
    const contractName = DEPLOY_ORDER[deployedCount];
    process.stdout.write(`Deploying ${contractName}... `);

    try {
      const Factory = await hre.ethers.getContractFactory(contractName);
      const contract = await Factory.connect(deployer).deploy({
        gasLimit: CONFIG.GAS_LIMIT,
        gasPrice: CONFIG.GAS_PRICE
      });
      await contract.waitForDeployment();

      const deployedAddress = await contract.getAddress();

      // Check if it matches expected address
      if (deployedAddress.toLowerCase() !== addresses[contractName].toLowerCase()) {
        console.log(`\n⚠️  Address mismatch (expected ${addresses[contractName]}, got ${deployedAddress})`);
        console.log(`   Nonce must have changed, retrying...\n`);
        continue; // Retry the loop
      }

      // Success!
      deployed[contractName] = deployedAddress;
      console.log(`✅ ${deployedAddress}`);
      deployedCount++;
    } catch (e) {
      console.log(`\n❌ Deployment failed: ${e.message.substring(0, 100)}`);
      console.log(`   Retrying...\n`);
      // Continue to retry
    }
  }

  console.log("\n=== ALL CONTRACTS DEPLOYED ===\n");

  // Get VRF subscription ID from admin (created in constructor)
  console.log("=== READING VRF CONFIG ===\n");
  const admin = await hre.ethers.getContractAt("DegenerusAdmin", deployed.DegenerusAdmin);
  const vrfSubId = await admin.subscriptionId();
  console.log(`VRF Subscription (auto-created by Admin): ${vrfSubId}\n`);

  // Fund VRF with LINK
  console.log("=== FUNDING VRF ===\n");
  const LINK_ADDRESS = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const link = await hre.ethers.getContractAt(
    ["function balanceOf(address) view returns (uint256)", "function transferAndCall(address,uint256,bytes) returns (bool)"],
    LINK_ADDRESS
  );

  const linkBalance = await link.balanceOf(deployer.address);
  console.log(`LINK balance: ${hre.ethers.formatEther(linkBalance)} LINK`);

  if (linkBalance > 0n) {
    // Cap at 50 LINK max
    const MAX_FUNDING = hre.ethers.parseEther("50");
    const fundAmount = linkBalance > MAX_FUNDING ? MAX_FUNDING : linkBalance;

    const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
    const data = hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [vrfSubId]);
    const txFund = await link.transferAndCall(
      VRF_COORDINATOR,
      fundAmount,
      data,
      { gasLimit: 500000, gasPrice: CONFIG.GAS_PRICE }
    );
    await txFund.wait();
    console.log(`✅ Funded with ${hre.ethers.formatEther(fundAmount)} LINK (capped at 50)\n`);
  }

  // Save deployment
  const deployment = {
    contracts: {
      GAME: deployed.DegenerusGame,
      ADMIN: deployed.DegenerusAdmin,
      GAMEPIECES: deployed.DegenerusGamepieces,
      COIN: deployed.BurnieCoin,
      VAULT: deployed.DegenerusVault,
      AFFILIATE: deployed.DegenerusAffiliate,
      JACKPOTS: deployed.DegenerusJackpots
    },
    vrfSubscriptionId: vrfSubId.toString(),
    useRealVRF: true
  };

  fs.writeFileSync("deployment-sepolia.json", JSON.stringify(deployment, null, 2));
  console.log("💾 Saved deployment-sepolia.json");

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  DEPLOYMENT COMPLETE                                           ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Game:       ${deployed.DegenerusGame}`);
  console.log(`Admin:      ${deployed.DegenerusAdmin}`);
  console.log(`Gamepieces: ${deployed.DegenerusGamepieces}`);
  console.log(`Coin:       ${deployed.BurnieCoin}`);
  console.log(`VRF Sub:    ${vrfSubId}`);
  console.log(`\n✅ Ready for simulation with "allow previous day mint" fix!`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
