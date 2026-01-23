/**
 * Verify all deployed contracts on Etherscan
 *
 * Usage:
 *   npx hardhat run scripts/verify-all-contracts.js --network sepolia
 */

import hre from "hardhat";
import fs from "node:fs";

const deployment = JSON.parse(fs.readFileSync("deployment-sepolia.json", "utf8"));

async function main() {
  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  VERIFYING ALL CONTRACTS ON ETHERSCAN                          ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  const contractsToVerify = [
    // Core contracts
    { name: "Icons32Data", address: deployment.contracts.ICONS_32 },
    { name: "TrophySvgAssets", address: deployment.contracts.TROPHY_SVG_ASSETS },
    { name: "DegenerusGame", address: deployment.contracts.GAME },
    { name: "DegenerusGamepieces", address: deployment.contracts.GAMEPIECES, contract: "contracts/DegenerusGamepieces.sol:DegenerusGamepieces" },
    { name: "DegenerusTrophies", address: deployment.contracts.TROPHIES, contract: "contracts/DegenerusTrophies.sol:DegenerusTrophies" },
    { name: "DegenerusAdmin", address: deployment.contracts.ADMIN, contract: "contracts/DegenerusAdmin.sol:DegenerusAdmin" },

    // Tokens
    { name: "BurnieCoin", address: deployment.contracts.COIN, contract: "contracts/BurnieCoin.sol:BurnieCoin" },

    // Game modules
    { name: "GameMintModule", address: deployment.contracts.GAME_MINT_MODULE },
    { name: "GameJackpotModule", address: deployment.contracts.GAME_JACKPOT_MODULE },
    { name: "GameEndgameModule", address: deployment.contracts.GAME_ENDGAME_MODULE },

    // Supporting contracts
    { name: "DegenerusVault", address: deployment.contracts.VAULT },
    { name: "DegenerusAffiliate", address: deployment.contracts.AFFILIATE },
    { name: "DegenerusJackpots", address: deployment.contracts.JACKPOTS },
    { name: "DegenerusQuests", address: deployment.contracts.QUESTS },
    { name: "IconColorRegistry", address: deployment.contracts.ICON_COLOR_REGISTRY },

    // Renderers
    { name: "GamepieceRendererRegular", address: deployment.contracts.RENDERER_REGULAR },
    { name: "TrophyRendererSvg", address: deployment.contracts.RENDERER_TROPHY_SVG },
    { name: "TrophyRenderer", address: deployment.contracts.RENDERER_TROPHY },
    { name: "GamepieceRendererRouter", address: deployment.contracts.GAMEPIECE_RENDERER_ROUTER },
    { name: "TrophyRendererRouter", address: deployment.contracts.TROPHY_RENDERER_ROUTER }
  ];

  let verified = 0;
  let alreadyVerified = 0;
  let failed = 0;

  for (const { name, address, contract } of contractsToVerify) {
    try {
      console.log(`Verifying ${name} at ${address}...`);
      await hre.run("verify:verify", {
        address: address,
        contract: contract,
        constructorArguments: []
      });
      console.log(`✅ ${name} verified\n`);
      verified++;
    } catch (error) {
      if (error.message.includes("already verified") || error.message.includes("Already Verified")) {
        console.log(`✅ ${name} already verified\n`);
        alreadyVerified++;
      } else {
        console.log(`⚠️  ${name} verification failed: ${error.message.substring(0, 150)}\n`);
        failed++;
      }
    }

    // Small delay to avoid rate limiting
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  console.log("╔════════════════════════════════════════════════════════════════╗");
  console.log("║  VERIFICATION SUMMARY                                          ║");
  console.log("╚════════════════════════════════════════════════════════════════╝\n");

  console.log(`Total Contracts: ${contractsToVerify.length}`);
  console.log(`✅ Newly Verified: ${verified}`);
  console.log(`✅ Already Verified: ${alreadyVerified}`);
  console.log(`⚠️  Failed: ${failed}`);
  console.log();

  if (failed > 0) {
    console.log("Note: Some verifications may require manual verification through Etherscan");
    console.log("or may need specific constructor arguments.");
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
