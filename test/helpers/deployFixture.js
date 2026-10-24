import { seedLogicalDay, setPackedField } from "./logicalDayFixture.js";
import hre from "hardhat";
import {
  predictAddresses,
  reserveDeploymentNonces,
  computeDeployDayBoundary,
  DEPLOY_ORDER,
  expandAliases,
  KEY_TO_CONTRACT,
} from "../../scripts/lib/predictAddresses.js";
import { patchContractAddresses } from "../../scripts/lib/patchContractAddresses.js";

// Module-level state: patch + compile happens only once per test run
let _patched = false;
let _patchedAddresses = null;
let _patchedExternal = null;
let _patchedDayBoundary = null;
let _patchedVrfKeyHash = null;
// loadFixture restores chain snapshots without restoring JavaScript module globals. Retain
// each Game's registrar so helpers never use a different fixture's most recent deployment.
const _registrarByGame = new Map();
const _governanceByTarget = new Map();
// Legacy fixtures deploy on day index 9 (GameTimeLib.MAIN_LAUNCH_DAY): 8 days past day index 1.
const LEGACY_DEPLOY_OFFSET = 8 * 86400;

/**
 * Deploy the full Degenerus protocol with mock external dependencies.
 * Designed for use with Hardhat's loadFixture().
 *
 * Options:
 *   affiliateBootstrap  DegenerusAffiliate constructor arrays.
 *   degenesis           false (default): the chain advances 8 days after DEPLOY_DAY_BOUNDARY is
 *                       taken, so every contract deploys on day index 9 (MAIN_LAUNCH_DAY) and
 *                       normal level-0 play starts on the deploy day. true: deploy on day index 1,
 *                       with the Degenesis sale (day indices 2..8) ahead.
 *
 * Flow:
 *   1. Take DEPLOY_DAY_BOUNDARY from the latest block (day index 1), then advance 8 days unless
 *      `degenesis` is set
 *   2. Deploy mock contracts (VRF, stETH, LINK)
 *   3. Predict addresses for every protocol contract
 *   4. Patch ContractAddresses.sol + recompile (once per test run)
 *   5. Deploy every protocol contract in order
 *   6. Verify deployed addresses match predictions
 */
export async function deployFullProtocol({
  affiliateBootstrap = [[], [], [], [], []],
  degenesis = false,
  finalizeIcons = false,
} = {}) {
  const signers = await hre.ethers.getSigners();
  const [deployer, alice, bob, carol, dan, eve, ...others] = signers;

  const block = await hre.ethers.provider.getBlock("latest");
  const deployDayBoundary = computeDeployDayBoundary(block.timestamp);
  if (!degenesis) {
    await hre.network.provider.send("evm_increaseTime", [LEGACY_DEPLOY_OFFSET]);
    await hre.network.provider.send("evm_mine");
  }

  // --- Phase 1: Deploy mocks ---
  const mockVRF = await deploy("MockVRFCoordinator");
  const mockStETH = await deploy("MockStETH");
  const mockLINK = await deploy("MockLinkToken");
  const mockFeed = await deploy("MockLinkEthFeed", [
    hre.ethers.parseEther("0.004"), // ~0.004 ETH per LINK
  ]);

  // --- Phase 2: Predict protocol addresses ---
  const startingNonce = await deployer.getNonce();
  const predicted = predictAddresses(deployer.address, startingNonce);

  const vrfKeyHash =
    "0xabababababababababababababababababababababababababababababababab";
  const external = {
    STETH_TOKEN: await mockStETH.getAddress(),
    LINK_TOKEN: await mockLINK.getAddress(),
    VRF_COORDINATOR: await mockVRF.getAddress(),
    // Pinned to zero on purpose: this fixture is the one that exercises the
    // feed-swap governance path, which needs the feed to start unhealthy. The
    // Foundry fixture pins mockFeed instead, so the constructor-install path is
    // covered there (test/fuzz/LinkFeedGenesis.t.sol). mockFeed below is still
    // deployed — the governance tests install it by vote.
    LINK_ETH_FEED: "0x0000000000000000000000000000000000000000",
    CREATOR: deployer.address,
  };

  // --- Phase 3: Patch + compile (once) ---
  // We need to re-patch if addresses changed (fresh fixture = different mock addresses)
  const needsPatch =
    !_patched ||
    _patchedExternal?.VRF_COORDINATOR !== external.VRF_COORDINATOR ||
    _patchedDayBoundary !== deployDayBoundary;

  if (needsPatch) {
    patchContractAddresses(predicted, external, deployDayBoundary, vrfKeyHash);
    // Hardhat checks the patched source content against its compiler input cache.
    // Changed pins still recompile; identical pins can reuse that exact build.
    await hre.run("compile", { quiet: true });
    _patched = true;
    _patchedAddresses = predicted;
    _patchedExternal = external;
    _patchedDayBoundary = deployDayBoundary;
    _patchedVrfKeyHash = vrfKeyHash;
  }

  // --- Phase 4: Deploy every protocol contract ---
  const contracts = {};
  const deployedAddrs = new Map();

  for (const key of DEPLOY_ORDER) {
      await reserveDeploymentNonces(deployer,key,startingNonce);
    const contractName = KEY_TO_CONTRACT[key];
    const args = getConstructorArgs(key, predicted, affiliateBootstrap, finalizeIcons);
    const contract = await deploy(contractName, args);
    const addr = await contract.getAddress();
    contracts[key] = contract;
    deployedAddrs.set(key, addr);
  }

  for (const [alias, contract] of expandAliases(new Map(Object.entries(contracts)))) contracts[alias] = contract;
  for (const [alias, addr] of expandAliases(deployedAddrs)) deployedAddrs.set(alias, addr);

  // --- Phase 5: Verify ---
  for (const [key, expectedAddr] of predicted) {
    const actualAddr = deployedAddrs.get(key);
    if (actualAddr.toLowerCase() !== expectedAddr.toLowerCase()) {
      throw new Error(
        `Address mismatch for ${key}: expected ${expectedAddr}, got ${actualAddr}`
      );
    }
  }

  // A post-Degenesis unit fixture explicitly seeds logical headers; wall time creates no rounds.
  if (!degenesis) {
    await seedLogicalDay(contracts.GAME, 9n, contracts.COINFLIP);
    await setPackedField(contracts.CRAPS, "_minerSlot", 9n * 8n, "CrapsBattle");
  }

  // Both protocol passes and their packed ticket queues initialize in one transaction.
  const genesisReceipt = await (await contracts.GAME.initProtocolDeity({ gasLimit: 16_777_216 })).wait();
  _registrarByGame.set(deployedAddrs.get("GAME").toLowerCase(), deployedAddrs.get("COINFLIP"));
  for (const addr of deployedAddrs.values()) {
    _governanceByTarget.set(addr.toLowerCase(), deployedAddrs.get("OWNER_GOVERNANCE"));
  }

  return {
    genesisReceipt,
    // Signers
    deployer,
    alice,
    bob,
    carol,
    dan,
    eve,
    others,

    // Mock external contracts
    mockVRF,
    mockStETH,
    mockLINK,
    mockFeed,

    // Protocol contracts (by ContractAddresses key)
    icons32: contracts.ICONS_32,
    coin: contracts.COIN,
    coinflip: contracts.COINFLIP,
    game: contracts.GAME,
    wwxrp: contracts.WWXRP,
    affiliate: contracts.AFFILIATE,
    jackpots: contracts.JACKPOTS,
    quests: contracts.QUESTS,
    deityPass: contracts.DEITY_PASS,
    vault: contracts.VAULT,
    ownerGovernance: contracts.OWNER_GOVERNANCE,
    sdgnrs: contracts.SDGNRS,
    dgnrs: contracts.DGNRS,
    admin: contracts.ADMIN,
    gnrus: contracts.GNRUS,
    jackpotBattle: contracts.JACKPOT_BATTLE,

    // Game modules
    mintModule: contracts.GAME_MINT_MODULE,
    ticketModule: contracts.GAME_TICKET_MODULE,
    minerModule: contracts.GAME_MINER_MODULE,
    rngModule: contracts.GAME_RNG_MODULE,
    jackpotDrawModule: contracts.GAME_JACKPOT_DRAW_MODULE,
    advanceModule: contracts.GAME_ADVANCE_MODULE,
    whaleModule: contracts.GAME_WHALE_MODULE,
    jackpotModule: contracts.GAME_JACKPOT_MODULE,
    decimatorModule: contracts.GAME_DECIMATOR_MODULE,
    gameOverModule: contracts.GAME_GAMEOVER_MODULE,
    lootboxModule: contracts.GAME_LOOTBOX_MODULE,
    boonModule: contracts.GAME_BOON_MODULE,
    degeneretteModule: contracts.GAME_DEGENERETTE_MODULE,
    degenesisModule: contracts.GAME_DEGENESIS_MODULE,

    // Metadata
    predicted,
    deployedAddrs,
    deployDayBoundary,
    startingNonce,
  };
}

/**
 * Reset the fixture patch state after tests complete. ContractAddresses.sol is
 * generated on demand and re-patched per run, so it is intentionally left
 * as-patched here; we only reset the flag so the next fixture re-patches with
 * fresh predicted addresses. Call this in an after() hook in your top-level test file.
 */
export function restoreAddresses() {
  _patched = false;
}

/** Real approval lifecycle for owner-action integration tests. Target errors bubble unchanged. */
export async function ownerExecutor(target) {
  const address = _governanceByTarget.get((await target.getAddress()).toLowerCase());
  if (!address) throw new Error("Unknown governance fixture target");
  return address;
}

export async function ownerAction(target, method, args = [], options = {}) {
  const signer = options.owner ?? target.runner;
  const owner = await signer.getAddress();
  const targetAddress = await target.getAddress();
  const govAddress = _governanceByTarget.get(targetAddress.toLowerCase());
  if (!govAddress) throw new Error("Unknown governance fixture target");
  const gov = await hre.ethers.getContractAt("DegenerusOwnerGovernance", govAddress, signer);
  const token = await hre.ethers.getContractAt("DegenerusVaultShare", await gov.dgve(), signer);
  const amount = await token.balanceOf(owner);
  await token.approve(govAddress, amount);
  const proposalId = await gov.proposalCount() + 1n;
  await gov.propose(owner, targetAddress, options.value ?? 0n, target.interface.encodeFunctionData(method, args), amount);
  try {
    const tx = await gov.execute(proposalId, target.interface.encodeFunctionData(method, args), {value: options.value ?? 0n});
    await tx.wait();
    return tx;
  } finally {
    await gov.withdraw();
  }
}

// --- Internal helpers ---

async function deploy(contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

function getConstructorArgs(key, predicted, affiliateBootstrap, finalizeIcons) {
  if (key === "ICONS_32") return [finalizeIcons];
  if (key === "COINFLIP") {
    return affiliateBootstrap;
  }
  if (key === "AF_KING") {
    // AfKing has a 3-arg constructor (subCostEthTarget, bountyEthTarget,
    // lootboxMin), all non-zero (each reverts on 0). Mirrors the foundry helper
    // test/fuzz/helpers/DeployProtocol.sol:126. The args set immutables only and
    // make no cross-contract calls, so they do not affect the predicted address.
    return [5_000_000_000n, 885_000_000n, 10_000_000_000n];
  }
  return [];
}

/**
 * Register `addr` in the Game's wallet table through the Coinflip contract (an allow-listed
 * `registerWallet_g9539` caller) and return its ID; an existing ID is returned unchanged.
 */
export async function giveWalletId(game, addr) {
  const existing = await game.walletIdOf_g3120(addr);
  if (existing !== 0n) return existing;
  const registrar = _registrarByGame.get((await game.getAddress()).toLowerCase());
  if (!registrar) throw new Error("Unknown Game fixture: cannot resolve its wallet registrar");
  await hre.network.provider.send("hardhat_setBalance", [registrar, "0x1000000000000000000"]);
  await hre.network.provider.send("hardhat_impersonateAccount", [registrar]);
  const signer = await hre.ethers.getSigner(registrar);
  await game.connect(signer).registerWallet_g9539(addr, true);
  await hre.network.provider.send("hardhat_stopImpersonatingAccount", [registrar]);
  return game.walletIdOf_g3120(addr);
}
