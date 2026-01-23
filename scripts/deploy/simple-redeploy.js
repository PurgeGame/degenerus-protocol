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
  "DegenerusGameStorage",
  "BurnieCoin",
  "DegenerusVault",
  "DegenerusAffiliate",
  "DegenerusJackpots",
  "DegenerusQuests",
  "IconColorRegistry",
  "RendererRegular",
  "RendererTrophySvg",
  "RendererTrophy",
  "GamepieceRendererRouter",
  "TrophyRendererRouter",
  "DegenerusTrophies",
  "DegenerusGamepieces",
  "DegenerusGame",
  "DegenerusAdmin"
];

async function main() {
  const provider = hre.ethers.provider;
  const deployer = new hre.ethers.Wallet(wallets.ownerPrivateKey, provider);

  console.log("\n╔════════════════════════════════════════════════════════════════╗");
  console.log("║  SIMPLE REDEPLOY - NO PRECOMPUTED ADDRESSES                   ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");
  console.log(`Deployer: ${deployer.address}`);

  const currentNonce = await provider.getTransactionCount(deployer.address);
  console.log(`Current nonce: ${currentNonce}\n`);

  // First, precompute all addresses
  console.log("=== PRECOMPUTING ADDRESSES ===\n");
  const addresses = {};
  for (let i = 0; i < DEPLOY_ORDER.length; i++) {
    const addr = getCreateAddress({
      from: deployer.address,
      nonce: currentNonce + i
    });
    addresses[DEPLOY_ORDER[i]] = addr;
    console.log(`${DEPLOY_ORDER[i]}: ${addr}`);
  }

  // Update ContractAddresses.sol
  console.log("\n=== UPDATING CONTRACT ADDRESSES ===\n");

  const contractAddressesContent = `// SPDX-License-Identifier: MIT
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
    address internal constant RENDERER_REGULAR = ${addresses.RendererRegular};
    address internal constant RENDERER_TROPHY_SVG = ${addresses.RendererTrophySvg};
    address internal constant RENDERER_TROPHY = ${addresses.RendererTrophy};
    address internal constant GAMEPIECE_RENDERER_ROUTER = ${addresses.GamepieceRendererRouter};
    address internal constant TROPHY_RENDERER_ROUTER = ${addresses.TrophyRendererRouter};
    address internal constant TROPHIES = ${addresses.DegenerusTrophies};
    address internal constant GAMEPIECES = ${addresses.DegenerusGamepieces};
    address internal constant GAME = ${addresses.DegenerusGame};
    address internal constant ADMIN = ${addresses.DegenerusAdmin};
}
`;

  fs.writeFileSync("contracts/ContractAddresses.sol", contractAddressesContent);
  console.log("✅ Updated ContractAddresses.sol\n");

  // Compile
  console.log("=== COMPILING CONTRACTS ===\n");
  await hre.run("compile");
  console.log("✅ Compiled\n");

  // Recheck nonce after compile (in case it changed)
  const finalNonce = await provider.getTransactionCount(deployer.address);
  if (finalNonce !== currentNonce) {
    console.log(`⚠️  Nonce changed during compile: ${currentNonce} -> ${finalNonce}`);
    console.log(`   Recomputing addresses...\n`);

    // Recompute addresses with new nonce
    for (let i = 0; i < DEPLOY_ORDER.length; i++) {
      const addr = getCreateAddress({
        from: deployer.address,
        nonce: finalNonce + i
      });
      addresses[DEPLOY_ORDER[i]] = addr;
    }

    // Update ContractAddresses.sol again
    const contractAddressesContent = `// SPDX-License-Identifier: MIT
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
    address internal constant RENDERER_REGULAR = ${addresses.RendererRegular};
    address internal constant RENDERER_TROPHY_SVG = ${addresses.RendererTrophySvg};
    address internal constant RENDERER_TROPHY = ${addresses.RendererTrophy};
    address internal constant GAMEPIECE_RENDERER_ROUTER = ${addresses.GamepieceRendererRouter};
    address internal constant TROPHY_RENDERER_ROUTER = ${addresses.TrophyRendererRouter};
    address internal constant TROPHIES = ${addresses.DegenerusTrophies};
    address internal constant GAMEPIECES = ${addresses.DegenerusGamepieces};
    address internal constant GAME = ${addresses.DegenerusGame};
    address internal constant ADMIN = ${addresses.DegenerusAdmin};
}
`;

    fs.writeFileSync("contracts/ContractAddresses.sol", contractAddressesContent);

    // Recompile with correct addresses
    await hre.run("compile");
    console.log("✅ Recompiled with correct addresses\n");
  }

  // Wait for nonce to stabilize before deployment
  console.log("=== WAITING FOR NONCE TO STABILIZE ===\n");
  let stableNonce;
  let attempts = 0;
  const maxAttempts = 10;

  while (attempts < maxAttempts) {
    // Use "pending" block tag to get most accurate nonce
    const nonce1 = await provider.getTransactionCount(deployer.address, "pending");
    await new Promise(resolve => setTimeout(resolve, 2000)); // Wait 2 seconds
    const nonce2 = await provider.getTransactionCount(deployer.address, "pending");

    if (nonce1 === nonce2) {
      stableNonce = nonce1;
      console.log(`✅ Nonce stabilized at: ${stableNonce}\n`);
      break;
    }

    console.log(`⏳ Nonce still changing (${nonce1} -> ${nonce2}), waiting...`);
    attempts++;
  }

  if (!stableNonce) {
    throw new Error("Nonce never stabilized after 10 attempts");
  }

  // If stable nonce is different from what we used, recompute one last time
  if (stableNonce !== (finalNonce || currentNonce)) {
    console.log(`⚠️  Stable nonce ${stableNonce} differs from expected ${finalNonce || currentNonce}`);
    console.log(`   Recomputing addresses for final deployment...\n`);

    // Recompute addresses with stable nonce
    for (let i = 0; i < DEPLOY_ORDER.length; i++) {
      const addr = getCreateAddress({
        from: deployer.address,
        nonce: stableNonce + i
      });
      addresses[DEPLOY_ORDER[i]] = addr;
    }

    // Update ContractAddresses.sol again
    const contractAddressesContent = `// SPDX-License-Identifier: MIT
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
    address internal constant RENDERER_REGULAR = ${addresses.RendererRegular};
    address internal constant RENDERER_TROPHY_SVG = ${addresses.RendererTrophySvg};
    address internal constant RENDERER_TROPHY = ${addresses.RendererTrophy};
    address internal constant GAMEPIECE_RENDERER_ROUTER = ${addresses.GamepieceRendererRouter};
    address internal constant TROPHY_RENDERER_ROUTER = ${addresses.TrophyRendererRouter};
    address internal constant TROPHIES = ${addresses.DegenerusTrophies};
    address internal constant GAMEPIECES = ${addresses.DegenerusGamepieces};
    address internal constant GAME = ${addresses.DegenerusGame};
    address internal constant ADMIN = ${addresses.DegenerusAdmin};
}
`;

    fs.writeFileSync("contracts/ContractAddresses.sol", contractAddressesContent);

    // Recompile one last time
    await hre.run("compile");
    console.log("✅ Final recompile complete\n");

    // Wait again for nonce to stabilize after recompile
    await new Promise(resolve => setTimeout(resolve, 3000));
    const postCompileNonce = await provider.getTransactionCount(deployer.address, "pending");
    if (postCompileNonce !== stableNonce) {
      throw new Error(`Nonce changed again after final recompile: ${stableNonce} -> ${postCompileNonce}`);
    }
  }

  // Deploy in order
  console.log("=== DEPLOYING CONTRACTS ===\n");
  const deployed = {};

  for (const contractName of DEPLOY_ORDER) {
    process.stdout.write(`Deploying ${contractName}... `);

    const Factory = await hre.ethers.getContractFactory(contractName);
    const contract = await Factory.connect(deployer).deploy({
      gasLimit: CONFIG.GAS_LIMIT,
      gasPrice: CONFIG.GAS_PRICE
    });
    await contract.waitForDeployment();

    const deployedAddress = await contract.getAddress();
    deployed[contractName] = deployedAddress;

    if (deployedAddress.toLowerCase() !== addresses[contractName].toLowerCase()) {
      console.log(`\n❌ ADDRESS MISMATCH!`);
      console.log(`   Expected: ${addresses[contractName]}`);
      console.log(`   Got:      ${deployedAddress}`);
      throw new Error(`Address mismatch for ${contractName}`);
    }

    console.log(`✅ ${deployedAddress}`);
  }

  // Get VRF subscription ID from admin
  console.log("\n=== CONFIGURING VRF ===\n");
  const admin = await hre.ethers.getContractAt("DegenerusAdmin", deployed.DegenerusAdmin);
  const vrfSubId = await admin.vrfSubscriptionId();
  console.log(`VRF Subscription: ${vrfSubId}\n`);

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
    const VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
    const data = hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256"], [vrfSubId]);
    const txFund = await link.transferAndCall(
      VRF_COORDINATOR,
      linkBalance,
      data,
      { gasLimit: 500000, gasPrice: CONFIG.GAS_PRICE }
    );
    await txFund.wait();
    console.log(`✅ Funded with ${hre.ethers.formatEther(linkBalance)} LINK\n`);
  }

  // Save deployment
  const deployment = {
    contracts: {
      GAME: deployed.DegenerusGame,
      ADMIN: deployed.DegenerusAdmin,
      GAMEPIECES: deployed.DegenerusGamepieces,
      COIN: deployed.BurnieCoin
    },
    vrfSubscriptionId: vrfSubId.toString()
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
