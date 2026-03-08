import hre from "hardhat";
import { writeFileSync, mkdirSync, existsSync, readFileSync } from "node:fs";
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
const ZERO_BYTES32 =
  "0x0000000000000000000000000000000000000000000000000000000000000000";

async function main() {
  const [deployer, alice, bob] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("=".repeat(70));
  console.log("  Degenerus Protocol — Local Deployment");
  console.log("=".repeat(70));
  console.log(`  Deployer: ${deployer.address}`);
  console.log(`  Network:  ${network}`);
  console.log("");

  // =========================================================================
  // Phase 1: Deploy mock external contracts
  // =========================================================================
  console.log("Phase 1: Deploying mock contracts...");

  const mockVRF = await deploy("MockVRFCoordinator");
  const mockStETH = await deploy("MockStETH");
  const mockLINK = await deploy("MockLinkToken");
  const mockWXRP = await deploy("MockWXRP");
  const mockFeed = await deploy("MockLinkEthFeed", [
    hre.ethers.parseEther("0.004"), // ~0.004 ETH per LINK
  ]);

  const mocks = {
    VRF_COORDINATOR: await mockVRF.getAddress(),
    STETH_TOKEN: await mockStETH.getAddress(),
    LINK_TOKEN: await mockLINK.getAddress(),
    WXRP: await mockWXRP.getAddress(),
    LINK_ETH_FEED: await mockFeed.getAddress(),
  };

  console.log(`  MockVRFCoordinator: ${mocks.VRF_COORDINATOR}`);
  console.log(`  MockStETH:          ${mocks.STETH_TOKEN}`);
  console.log(`  MockLINK:           ${mocks.LINK_TOKEN}`);
  console.log(`  MockWXRP:           ${mocks.WXRP}`);
  console.log(`  MockLinkEthFeed:    ${mocks.LINK_ETH_FEED}`);
  console.log("");

  // =========================================================================
  // Phase 2: Predict protocol addresses
  // =========================================================================
  console.log("Phase 2: Predicting protocol addresses...");

  const startingNonce = await deployer.getNonce();
  const block = await hre.ethers.provider.getBlock("latest");
  const deployDayBoundary = computeDeployDayBoundary(block.timestamp);
  const predicted = predictAddresses(deployer.address, startingNonce);

  const vrfKeyHash =
    "0xabababababababababababababababababababababababababababababababab";
  const external = {
    STETH_TOKEN: mocks.STETH_TOKEN,
    LINK_TOKEN: mocks.LINK_TOKEN,
    VRF_COORDINATOR: mocks.VRF_COORDINATOR,
    WXRP: mocks.WXRP,
    CREATOR: deployer.address,
  };

  console.log(`  Starting nonce: ${startingNonce}`);
  console.log(`  Deploy day boundary: ${deployDayBoundary}`);
  console.log("");

  // =========================================================================
  // Phase 3: Patch ContractAddresses.sol + recompile
  // =========================================================================
  console.log("Phase 3: Patching ContractAddresses.sol + recompiling...");

  patchContractAddresses(predicted, external, deployDayBoundary, vrfKeyHash);

  try {
    await hre.run("compile", { force: true, quiet: true });
    console.log("  Compilation successful.");
    console.log("");

    // =========================================================================
    // Phase 4: Deploy all 22 protocol contracts
    // =========================================================================
    console.log(`Phase 4: Deploying ${DEPLOY_ORDER.length} protocol contracts...`);

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
    // Phase 5: Seed initial game state
    // =========================================================================
    console.log("Phase 5: Seeding initial game state...");

    const game = contracts.GAME;

    // Purchase tickets for deployer (0.01 ETH = 1 full ticket at level 0)
    const price = await game.mintPrice();
    console.log(`  Mint price: ${hre.ethers.formatEther(price)} ETH`);

    await game.connect(deployer).purchase(
      deployer.address,
      400, // 4 full tickets (ticketQuantity at TICKET_SCALE=100)
      0,
      ZERO_BYTES32,
      0, // MintPaymentKind.DirectEth
      { value: price }
    );
    console.log("  Deployer purchased 4 tickets.");

    // Purchase tickets for alice and bob so there are multiple players
    if (alice) {
      await game.connect(alice).purchase(
        alice.address,
        200,
        0,
        ZERO_BYTES32,
        0,
        { value: price }
      );
      console.log(`  Alice (${alice.address}) purchased 2 tickets.`);
    }

    if (bob) {
      await game.connect(bob).purchase(
        bob.address,
        100,
        0,
        ZERO_BYTES32,
        0,
        { value: price }
      );
      console.log(`  Bob (${bob.address}) purchased 1 ticket.`);
    }

    // Advance the game — trigger VRF request
    await game.connect(deployer).advanceGame();
    console.log("  VRF request issued (advanceGame).");

    // Fulfill VRF with mock
    const requestId = await mockVRF.lastRequestId();
    await mockVRF.fulfillRandomWords(requestId, 98765432101234567890n);
    console.log(`  VRF fulfilled (requestId=${requestId}).`);

    // Drain tickets until RNG unlocks
    let drainCount = 0;
    for (let i = 0; i < 30; i++) {
      if (!(await game.rngLocked())) break;
      await game.connect(deployer).advanceGame();
      drainCount++;
    }
    console.log(`  Ticket processing drained (${drainCount} advance calls).`);

    const currentLevel = await game.level();
    console.log(`  Current game level: ${currentLevel}`);
    console.log("");

    // =========================================================================
    // Phase 6: Export addresses + ABIs
    // =========================================================================
    console.log("Phase 6: Writing deployment manifest + ABIs...");

    const deploymentsDir = resolve(__dirname, "../deployments");
    if (!existsSync(deploymentsDir)) {
      mkdirSync(deploymentsDir, { recursive: true });
    }

    // Write addresses manifest
    const manifest = {
      network: "localhost",
      chainId: 31337,
      deployer: deployer.address,
      timestamp: block.timestamp,
      deployDayBoundary,
      signers: {
        deployer: deployer.address,
        alice: alice?.address,
        bob: bob?.address,
      },
      contracts: Object.fromEntries(deployedAddrs),
      mocks,
    };

    const manifestPath = resolve(deploymentsDir, "localhost.json");
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`  Manifest: ${manifestPath}`);

    // Write ABI files
    const abisDir = resolve(deploymentsDir, "localhost-abis");
    if (!existsSync(abisDir)) {
      mkdirSync(abisDir, { recursive: true });
    }

    // Protocol contract ABIs
    const allContracts = new Set();
    for (const name of Object.values(KEY_TO_CONTRACT)) {
      allContracts.add(name);
    }
    // Mock contract ABIs
    for (const name of [
      "MockVRFCoordinator",
      "MockStETH",
      "MockLinkToken",
      "MockWXRP",
      "MockLinkEthFeed",
    ]) {
      allContracts.add(name);
    }

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
    console.log(`    MockVRF:  ${mocks.VRF_COORDINATOR}`);
    console.log("");
    console.log("  Frontend: point at http://127.0.0.1:8545 (chainId 31337)");
    console.log(`  Addresses: ${manifestPath}`);
    console.log(`  ABIs:      ${abisDir}/`);
    console.log("=".repeat(70));
  } finally {
    // Always restore ContractAddresses.sol
    console.log("\nRestoring ContractAddresses.sol...");
    restoreContractAddresses();
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
    restoreContractAddresses();
  } catch {}
  process.exit(1);
});
