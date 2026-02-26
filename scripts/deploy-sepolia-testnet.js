import hre from "hardhat";
import { writeFileSync, mkdirSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  predictAddresses,
  computeDeployDayBoundary,
  DEPLOY_ORDER,
  KEY_TO_CONTRACT,
} from "./lib/predictAddresses.js";
import {
  patchContractAddresses,
  restoreContractAddresses,
} from "./lib/patchContractAddresses.js";
import { deployContract, verifyAddresses } from "./lib/deployHelpers.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Sepolia external addresses — real Chainlink VRF V2.5
const SEPOLIA_LINK_TOKEN = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
const SEPOLIA_VRF_COORDINATOR = "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B";
const VRF_KEY_HASH =
  "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae";

// Testnet ContractAddresses.sol path
const TESTNET_CONTRACT_ADDRESSES = resolve(
  __dirname,
  "../contracts-testnet/ContractAddresses.sol"
);

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  if (network !== "sepolia") {
    throw new Error(`Expected network "sepolia", got "${network}"`);
  }

  const balance = await hre.ethers.provider.getBalance(deployer.address);

  console.log("=".repeat(70));
  console.log("  Degenerus Protocol — Sepolia Testnet Deployment");
  console.log("=".repeat(70));
  console.log(`  Deployer: ${deployer.address}`);
  console.log(`  Balance:  ${hre.ethers.formatEther(balance)} ETH`);
  console.log(`  Network:  ${network}`);
  console.log("");

  if (balance < hre.ethers.parseEther("0.5")) {
    console.warn("  WARNING: Low balance — deployment may fail partway through.");
  }

  // =========================================================================
  // Phase 1: Deploy mock external contracts (stETH, WXRP only — real VRF)
  // =========================================================================
  console.log("Phase 1: Deploying mock contracts (stETH, WXRP)...");
  console.log("  VRF: Using real Chainlink VRF V2.5 on Sepolia");

  const mockStETH = await deploy("MockStETH");
  const mockWXRP = await deploy("MockWXRP");

  const mocks = {
    STETH_TOKEN: await mockStETH.getAddress(),
    WXRP: await mockWXRP.getAddress(),
  };

  console.log(`  MockStETH:        ${mocks.STETH_TOKEN}`);
  console.log(`  MockWXRP:         ${mocks.WXRP}`);
  console.log(`  VRF Coordinator:  ${SEPOLIA_VRF_COORDINATOR} (real Chainlink)`);
  console.log(`  LINK Token:       ${SEPOLIA_LINK_TOKEN} (real Sepolia)`);
  console.log(`  VRF Key Hash:     ${VRF_KEY_HASH}`);
  console.log("");

  // =========================================================================
  // Phase 2: Predict protocol addresses
  // =========================================================================
  console.log("Phase 2: Predicting protocol addresses...");

  const startingNonce = await deployer.getNonce();
  const block = await hre.ethers.provider.getBlock("latest");
  const deployDayBoundary = computeDeployDayBoundary(block.timestamp);
  const predicted = predictAddresses(deployer.address, startingNonce);

  const external = {
    STETH_TOKEN: mocks.STETH_TOKEN,
    LINK_TOKEN: SEPOLIA_LINK_TOKEN,
    VRF_COORDINATOR: SEPOLIA_VRF_COORDINATOR,
    WXRP: mocks.WXRP,
    CREATOR: deployer.address,
  };

  console.log(`  Starting nonce: ${startingNonce}`);
  console.log(`  Deploy day boundary: ${deployDayBoundary}`);
  console.log(`  Predicted GAME: ${predicted.get("GAME")}`);
  console.log(`  Predicted ADMIN: ${predicted.get("ADMIN")}`);
  console.log("");

  // =========================================================================
  // Phase 3: Patch contracts-testnet/ContractAddresses.sol + recompile
  // =========================================================================
  console.log("Phase 3: Patching ContractAddresses.sol + recompiling...");

  patchContractAddresses(
    predicted,
    external,
    deployDayBoundary,
    VRF_KEY_HASH,
    TESTNET_CONTRACT_ADDRESSES
  );

  try {
    await hre.run("compile", { force: true, quiet: true });
    console.log("  Compilation successful.");
    console.log("");

    // =========================================================================
    // Phase 4: Deploy all 22 protocol contracts
    // =========================================================================
    console.log(
      `Phase 4: Deploying ${DEPLOY_ORDER.length} protocol contracts...`
    );

    const contracts = {};
    const deployedAddrs = new Map();
    const affiliateBootstrap = parseAffiliateBootstrap();
    const affiliatePreReferrals = parseAffiliatePreReferrals();
    if (affiliateBootstrap.owners.length != 0) {
      console.log(
        `  Bootstrapping ${affiliateBootstrap.owners.length} affiliate code(s) from AFFILIATE_BOOTSTRAP_JSON...`
      );
    }
    if (affiliatePreReferrals.players.length != 0) {
      console.log(
        `  Pre-seeding ${affiliatePreReferrals.players.length} referral(s) from AFFILIATE_PREFERRALS_JSON...`
      );
    }

    for (const key of DEPLOY_ORDER) {
      const contractName = KEY_TO_CONTRACT[key];
      const args = getConstructorArgs(
        key,
        predicted,
        affiliateBootstrap,
        affiliatePreReferrals
      );
      process.stdout.write(`  [${key}] ${contractName}...`);
      const contract = await deployContract(hre, contractName, args);
      const addr = await contract.getAddress();
      contracts[key] = contract;
      deployedAddrs.set(key, addr);
      console.log(` ${addr}`);
    }

    // Verify addresses match predictions
    verifyAddresses(predicted, deployedAddrs);
    console.log("  All addresses verified.");
    console.log("");

    // =========================================================================
    // Phase 5: Export addresses + ABIs
    // =========================================================================
    console.log("Phase 5: Writing deployment manifest + ABIs...");

    const deploymentsDir = resolve(__dirname, "../deployments");
    if (!existsSync(deploymentsDir)) {
      mkdirSync(deploymentsDir, { recursive: true });
    }

    const manifest = {
      network: "sepolia",
      chainId: 11155111,
      deployer: deployer.address,
      timestamp: block.timestamp,
      deployBlock: (await hre.ethers.provider.getBlockNumber()),
      deployDayBoundary,
      contracts: Object.fromEntries(deployedAddrs),
      mocks,
      external: {
        LINK_TOKEN: SEPOLIA_LINK_TOKEN,
        VRF_COORDINATOR: SEPOLIA_VRF_COORDINATOR,
        VRF_KEY_HASH: VRF_KEY_HASH,
      },
    };

    const manifestPath = resolve(deploymentsDir, "sepolia-testnet.json");
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`  Manifest: ${manifestPath}`);

    // Write ABI files
    const abisDir = resolve(deploymentsDir, "sepolia-testnet-abis");
    if (!existsSync(abisDir)) {
      mkdirSync(abisDir, { recursive: true });
    }

    const allContracts = new Set();
    for (const name of Object.values(KEY_TO_CONTRACT)) {
      allContracts.add(name);
    }
    allContracts.add("MockStETH");
    allContracts.add("MockWXRP");

    for (const name of allContracts) {
      const artifact = await hre.artifacts.readArtifact(name);
      const abiPath = resolve(abisDir, `${name}.json`);
      writeFileSync(abiPath, JSON.stringify(artifact.abi, null, 2));
    }
    console.log(`  ABIs: ${abisDir}/ (${allContracts.size} files)`);
    console.log("");

    // =========================================================================
    // Done
    // =========================================================================
    console.log("=".repeat(70));
    console.log("  Deployment complete!");
    console.log("");
    console.log("  Key addresses:");
    console.log(`    Game:     ${deployedAddrs.get("GAME")}`);
    console.log(`    Coin:     ${deployedAddrs.get("COIN")}`);
    console.log(`    Coinflip: ${deployedAddrs.get("COINFLIP")}`);
    console.log(`    Vault:    ${deployedAddrs.get("VAULT")}`);
    console.log(`    DGNRS:    ${deployedAddrs.get("DGNRS")}`);
    console.log(`    Admin:    ${deployedAddrs.get("ADMIN")}`);
    console.log("");
    console.log("  VRF: Real Chainlink VRF V2.5 (auto-fulfillment)");
    console.log("  NEXT STEPS:");
    console.log("    1. Fund VRF subscription with LINK via Admin.onTokenTransfer()");
    console.log("       (send LINK to Admin address using transferAndCall)");
    console.log("    2. Run: node scripts/testnet/run-sepolia.js");
    console.log("    3. Or manually: advanceDay() + advanceGame() to progress");
    console.log("");
    console.log(`  Manifest: ${manifestPath}`);
    console.log("=".repeat(70));
  } finally {
    console.log("\nRestoring ContractAddresses.sol...");
    restoreContractAddresses(TESTNET_CONTRACT_ADDRESSES);
  }
}

// --- Helpers ---

async function deploy(contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

function getConstructorArgs(
  key,
  predicted,
  affiliateBootstrap,
  affiliatePreReferrals
) {
  if (key === "COINFLIP") {
    return [
      predicted.get("COIN"),
      predicted.get("GAME"),
      predicted.get("JACKPOTS"),
      predicted.get("WWXRP"),
    ];
  }
  if (key === "AFFILIATE") {
    return [
      affiliateBootstrap.owners,
      affiliateBootstrap.codes,
      affiliateBootstrap.rakebacks,
      affiliatePreReferrals.players,
      affiliatePreReferrals.codes,
    ];
  }
  return [];
}

/**
 * Parse optional affiliate bootstrap config from env:
 * AFFILIATE_BOOTSTRAP_JSON='[{"owner":"0x...","code":"ALICE","rakebackPct":10}]'
 * `code` may be either a 0x-prefixed bytes32 hex or a short ASCII label.
 */
function parseAffiliateBootstrap() {
  const raw = process.env.AFFILIATE_BOOTSTRAP_JSON;
  if (!raw || raw.trim() === "") {
    return { owners: [], codes: [], rakebacks: [] };
  }

  let entries;
  try {
    entries = JSON.parse(raw);
  } catch {
    throw new Error("AFFILIATE_BOOTSTRAP_JSON must be valid JSON");
  }
  if (!Array.isArray(entries)) {
    throw new Error("AFFILIATE_BOOTSTRAP_JSON must be a JSON array");
  }

  const owners = [];
  const codes = [];
  const rakebacks = [];

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (!entry || typeof entry !== "object") {
      throw new Error(`Affiliate bootstrap entry ${i} must be an object`);
    }

    const owner = entry.owner;
    if (!hre.ethers.isAddress(owner)) {
      throw new Error(`Affiliate bootstrap entry ${i} has invalid owner`);
    }

    const rakebackRaw = entry.rakebackPct ?? 0;
    if (
      !Number.isInteger(rakebackRaw) ||
      rakebackRaw < 0 ||
      rakebackRaw > 25
    ) {
      throw new Error(
        `Affiliate bootstrap entry ${i} has invalid rakebackPct (0-25)`
      );
    }

    const codeInput = entry.code;
    if (typeof codeInput !== "string" || codeInput.length === 0) {
      throw new Error(`Affiliate bootstrap entry ${i} has invalid code`);
    }

    let code;
    if (/^0x[0-9a-fA-F]{64}$/.test(codeInput)) {
      code = codeInput;
    } else {
      try {
        code = hre.ethers.encodeBytes32String(codeInput);
      } catch {
        throw new Error(
          `Affiliate bootstrap entry ${i} code must fit bytes32 (<=31 chars)`
        );
      }
    }

    owners.push(owner);
    codes.push(code);
    rakebacks.push(rakebackRaw);
  }

  return { owners, codes, rakebacks };
}

/**
 * Parse optional pre-referral config from env:
 * AFFILIATE_PREFERRALS_JSON='[{"player":"0x...","code":"ALICE"}]'
 * `code` may be either a 0x-prefixed bytes32 hex or a short ASCII label.
 */
function parseAffiliatePreReferrals() {
  const raw = process.env.AFFILIATE_PREFERRALS_JSON;
  if (!raw || raw.trim() === "") {
    return { players: [], codes: [] };
  }

  let entries;
  try {
    entries = JSON.parse(raw);
  } catch {
    throw new Error("AFFILIATE_PREFERRALS_JSON must be valid JSON");
  }
  if (!Array.isArray(entries)) {
    throw new Error("AFFILIATE_PREFERRALS_JSON must be a JSON array");
  }

  const players = [];
  const codes = [];

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (!entry || typeof entry !== "object") {
      throw new Error(`Affiliate pre-referral entry ${i} must be an object`);
    }

    const player = entry.player;
    if (!hre.ethers.isAddress(player)) {
      throw new Error(`Affiliate pre-referral entry ${i} has invalid player`);
    }

    const codeInput = entry.code;
    if (typeof codeInput !== "string" || codeInput.length === 0) {
      throw new Error(`Affiliate pre-referral entry ${i} has invalid code`);
    }

    let code;
    if (/^0x[0-9a-fA-F]{64}$/.test(codeInput)) {
      code = codeInput;
    } else {
      try {
        code = hre.ethers.encodeBytes32String(codeInput);
      } catch {
        throw new Error(
          `Affiliate pre-referral entry ${i} code must fit bytes32 (<=31 chars)`
        );
      }
    }

    players.push(player);
    codes.push(code);
  }

  return { players, codes };
}

main().catch((err) => {
  console.error(err);
  try {
    restoreContractAddresses(TESTNET_CONTRACT_ADDRESSES);
  } catch {}
  process.exit(1);
});
