import hre from "hardhat";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  copyFileSync,
  readdirSync,
} from "node:fs";
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
  cleanupBackup,
} from "./lib/patchContractAddresses.js";
import {
  deployContract,
  verifyAddresses,
  wireIcons32,
} from "./lib/deployHelpers.js";

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

  // Optional: ENS reverse registrar for contract self-naming. If unset, the
  // constant stays address(0) and every constructor's setName call is skipped.
  if (process.env.ENS_REVERSE_REGISTRAR) {
    external.ENS_REVERSE_REGISTRAR = process.env.ENS_REVERSE_REGISTRAR;
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

      // Fail at the FIRST divergence, not after all 28. Every address is baked
      // into ContractAddresses.sol as a compile-time constant, so once one lands
      // off-prediction the whole deployment is unusable — there is nothing to
      // salvage by continuing, and each further deploy is wasted gas.
      const want = predicted.get(key);
      if (addr.toLowerCase() !== want.toLowerCase()) {
        throw new Error(
          `Address divergence at [${key}] (${deployed.size}/${DEPLOY_ORDER.length}):\n` +
            `  expected ${want}\n  got      ${addr}\n` +
            `The deployer nonce moved unexpectedly — something else spent a nonce ` +
            `from ${deployer.address} mid-deploy. STOP: every already-deployed ` +
            `contract is unusable. Re-run from a clean nonce on a quiet key.`
        );
      }
    }

    // 7. Verify addresses
    console.log("\nVerifying address predictions...");
    verifyAddresses(predicted, deployed);
    console.log("All addresses match predictions.\n");

    // 7b. Record the vault's constructor-deployed share tokens (DGVF/DGVE) so
    // downstream tooling (ens-register.js forward records) can reach them.
    const vault = await hre.ethers.getContractAt(
      "DegenerusVault",
      deployed.get("VAULT"),
      deployer
    );
    deployed.set("VAULT_FLIP_SHARE", await vault.flipShare());
    deployed.set("VAULT_ETH_SHARE", await vault.ethShare());
    console.log(`  [VAULT_FLIP_SHARE] DGVF ${deployed.get("VAULT_FLIP_SHARE")}`);
    console.log(`  [VAULT_ETH_SHARE]  DGVE ${deployed.get("VAULT_ETH_SHARE")}\n`);

    // 8. Wire Icons32Data (33 paths + 3 name quadrants). MUST use the
    //    symbol-ordered dataset — the legacy icons32Data.json is badge-FILE
    //    ordered and mismaps the whole cards quadrant. finalize() is an
    //    IRREVERSIBLE lock, so it stays opt-in: verify the wired data on-chain,
    //    then run with ICONS32_FINALIZE=1 as a deliberate second step.
    const finalizeIcons = process.env.ICONS32_FINALIZE === "1";
    console.log(
      `Wiring Icons32Data (33 paths, 3 name quadrants, finalize=${finalizeIcons})...`
    );
    const iconsData = JSON.parse(
      readFileSync(resolve(__dirname, "data/icons32Data.symbolOrder.json"), "utf8")
    );
    const icons32 = await hre.ethers.getContractAt(
      "Icons32Data",
      deployed.get("ICONS_32"),
      deployer
    );
    await wireIcons32(icons32, iconsData, { finalize: finalizeIcons });
    console.log(
      finalizeIcons
        ? "Icons32Data wired and FINALIZED (permanently immutable).\n"
        : "Icons32Data wired (NOT finalized — verify, then ICONS32_FINALIZE=1).\n"
    );

    // 9. Save deployment manifest
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
    const stamp = Date.now();
    const manifestPath = resolve(deploymentsDir, `${network}-${stamp}.json`);
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`Manifest saved: ${manifestPath}`);

    // 10. Archive everything Etherscan verification needs, RIGHT NOW.
    //
    //     ContractAddresses.sol is generated: this run patched it with the real
    //     predicted addresses, and it is the only source that compiles to the
    //     deployed bytecode. It is also destroyed by the next `make test-foundry`
    //     (that target ends with `git checkout -- contracts/ContractAddresses.sol`)
    //     and re-patched by any hardhat run. Copy it, plus the solc build-info
    //     (full standard-json input + output), before anything can touch them.
    const archiveDir = resolve(deploymentsDir, `${network}-${stamp}`);
    mkdirSync(archiveDir, { recursive: true });
    writeFileSync(
      resolve(archiveDir, "manifest.json"),
      JSON.stringify(manifest, null, 2)
    );
    copyFileSync(
      resolve(__dirname, "../contracts/ContractAddresses.sol"),
      resolve(archiveDir, "ContractAddresses.sol")
    );

    const buildInfoDir = resolve(__dirname, "../artifacts/build-info");
    let buildInfoCount = 0;
    if (existsSync(buildInfoDir)) {
      for (const f of readdirSync(buildInfoDir).filter((n) => n.endsWith(".json"))) {
        copyFileSync(resolve(buildInfoDir, f), resolve(archiveDir, f));
        buildInfoCount++;
      }
    }

    // ABIs for the indexer / frontend (deploy-local.js exports these; production
    // did not, so every mainnet consumer was left to dig them out of artifacts/).
    const abisDir = resolve(archiveDir, "abis");
    mkdirSync(abisDir, { recursive: true });
    const abiNames = new Set([
      ...Object.values(KEY_TO_CONTRACT),
      "DegenerusVaultShare", // DGVF/DGVE, deployed from the vault constructor
      "DegenerusGameLens", // deployment-decoupled periphery, deployed separately
      "DeityBoonViewer",
    ]);
    let abiCount = 0;
    for (const name of abiNames) {
      try {
        const artifact = await hre.artifacts.readArtifact(name);
        writeFileSync(
          resolve(abisDir, `${name}.json`),
          JSON.stringify(artifact.abi, null, 2)
        );
        abiCount++;
      } catch {
        console.log(`  WARN: no artifact for ${name}, ABI skipped`);
      }
    }

    console.log(`Archive saved: ${archiveDir}`);
    console.log(
      `  ContractAddresses.sol + ${buildInfoCount} build-info + ${abiCount} ABIs`
    );
    if (buildInfoCount === 0) {
      console.log(
        "  WARN: no build-info found — Etherscan verification will need a rebuild " +
          "from the archived ContractAddresses.sol."
      );
    }
  } finally {
    // ContractAddresses.sol is generated on demand — leave it as-patched and
    // just purge any stale backup so it can't resurrect a removed constant.
    cleanupBackup();
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
  try {
    cleanupBackup();
  } catch {}
  process.exit(1);
});
