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

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const startingNonce = await deployer.getNonce();
  const network = hre.network.name;

  console.log(`Deployer: ${deployer.address}`);
  console.log(`Network:  ${network}`);
  console.log(`Nonce:    ${startingNonce}`);
  console.log(`Deploying ${DEPLOY_ORDER.length} contracts (including DGNRS liquid wrapper)...\n`);

  // 1. Predict all addresses
  const predicted = predictAddresses(deployer.address, startingNonce);

  // 2. Compute deploy day boundary
  const block = await hre.ethers.provider.getBlock("latest");
  const deployDayBoundary = computeDeployDayBoundary(block.timestamp);

  // 3. External addresses from environment
  const vrfKeyHash = process.env.VRF_KEY_HASH;
  if (!vrfKeyHash) throw new Error("VRF_KEY_HASH not set in .env");

  const external = {
    STETH_TOKEN: process.env.STETH_TOKEN,
    LINK_TOKEN: process.env.LINK_TOKEN,
    VRF_COORDINATOR: process.env.VRF_COORDINATOR,
    CREATOR: deployer.address,
  };

  // Validate all external addresses are set
  for (const [key, val] of Object.entries(external)) {
    if (!val) throw new Error(`${key} not set in .env`);
  }

  // 4. Patch ContractAddresses.sol
  console.log("Patching ContractAddresses.sol...");
  patchContractAddresses(predicted, external, deployDayBoundary, vrfKeyHash);

  // 5. Recompile
  console.log("Recompiling...");
  await hre.run("compile", { force: true, quiet: true });

  // 6. Deploy in order
  const deployed = new Map();
  const affiliateBootstrap = parseAffiliateBootstrap();
  const affiliatePreReferrals = parseAffiliatePreReferrals();
  if (affiliateBootstrap.owners.length != 0) {
    console.log(
      `Bootstrapping ${affiliateBootstrap.owners.length} affiliate code(s) from AFFILIATE_BOOTSTRAP_JSON...`
    );
  }
  if (affiliatePreReferrals.players.length != 0) {
    console.log(
      `Pre-seeding ${affiliatePreReferrals.players.length} referral(s) from AFFILIATE_PREFERRALS_JSON...`
    );
  }
  try {
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
      deployed.set(key, addr);
      console.log(` ${addr}`);
    }

    // 7. Verify addresses
    console.log("\nVerifying address predictions...");
    verifyAddresses(predicted, deployed);
    console.log("All addresses match predictions.\n");

    // 8. Save deployment manifest
    const manifest = {
      network,
      deployer: deployer.address,
      startingNonce,
      deployDayBoundary,
      timestamp: block.timestamp,
      contracts: Object.fromEntries(deployed),
    };

    const deploymentsDir = resolve(__dirname, "../deployments");
    if (!existsSync(deploymentsDir)) {
      mkdirSync(deploymentsDir, { recursive: true });
    }
    const manifestPath = resolve(
      deploymentsDir,
      `${network}-${Date.now()}.json`
    );
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`Manifest saved: ${manifestPath}`);
  } finally {
    // 9. Restore ContractAddresses.sol
    console.log("Restoring ContractAddresses.sol...");
    restoreContractAddresses();
  }
}

/**
 * Return constructor arguments for contracts that need them.
 * DegenerusAffiliate takes constructor args.
 */
function getConstructorArgs(
  key,
  predicted,
  affiliateBootstrap,
  affiliatePreReferrals
) {
  if (key === "AFFILIATE") {
    return [
      affiliateBootstrap.owners,
      affiliateBootstrap.codes,
      affiliateBootstrap.kickbacks,
      affiliatePreReferrals.players,
      affiliatePreReferrals.codes,
    ];
  }
  return [];
}

/**
 * Parse optional affiliate bootstrap config from env:
 * AFFILIATE_BOOTSTRAP_JSON='[{"owner":"0x...","code":"ALICE","kickbackPct":10}]'
 * `code` may be either a 0x-prefixed bytes32 hex or a short ASCII label.
 */
function parseAffiliateBootstrap() {
  const raw = process.env.AFFILIATE_BOOTSTRAP_JSON;
  if (!raw || raw.trim() === "") {
    return { owners: [], codes: [], kickbacks: [] };
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
  const kickbacks = [];

  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if (!entry || typeof entry !== "object") {
      throw new Error(`Affiliate bootstrap entry ${i} must be an object`);
    }

    const owner = entry.owner;
    if (!hre.ethers.isAddress(owner)) {
      throw new Error(`Affiliate bootstrap entry ${i} has invalid owner`);
    }

    const kickbackRaw = entry.kickbackPct ?? 0;
    if (
      !Number.isInteger(kickbackRaw) ||
      kickbackRaw < 0 ||
      kickbackRaw > 25
    ) {
      throw new Error(
        `Affiliate bootstrap entry ${i} has invalid kickbackPct (0-25)`
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
    kickbacks.push(kickbackRaw);
  }

  return { owners, codes, kickbacks };
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
  // Always try to restore on error
  try {
    restoreContractAddresses();
  } catch {}
  process.exit(1);
});
