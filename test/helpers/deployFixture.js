import hre from "hardhat";
import {
  predictAddresses,
  computeDeployDayBoundary,
  DEPLOY_ORDER,
  KEY_TO_CONTRACT,
} from "../../scripts/lib/predictAddresses.js";
import {
  patchContractAddresses,
  restoreContractAddresses,
} from "../../scripts/lib/patchContractAddresses.js";

// Module-level state: patch + compile happens only once per test run
let _patched = false;
let _patchedAddresses = null;
let _patchedExternal = null;
let _patchedDayBoundary = null;
let _patchedVrfKeyHash = null;

/**
 * Deploy the full Degenerus protocol with mock external dependencies.
 * Designed for use with Hardhat's loadFixture().
 *
 * Flow:
 *   1. Deploy mock contracts (VRF, stETH, LINK, wXRP)
 *   2. Predict addresses for the 23 protocol contracts
 *   3. Patch ContractAddresses.sol + recompile (once per test run)
 *   4. Deploy all 23 protocol contracts in order
 *   5. Verify deployed addresses match predictions
 */
export async function deployFullProtocol() {
  const signers = await hre.ethers.getSigners();
  const [deployer, alice, bob, carol, dan, eve, ...others] = signers;

  // --- Phase 1: Deploy mocks ---
  const mockVRF = await deploy("MockVRFCoordinator");
  const mockStETH = await deploy("MockStETH");
  const mockLINK = await deploy("MockLinkToken");
  const mockWXRP = await deploy("MockWXRP");
  const mockFeed = await deploy("MockLinkEthFeed", [
    hre.ethers.parseEther("0.004"), // ~0.004 ETH per LINK
  ]);

  // --- Phase 2: Predict protocol addresses ---
  const startingNonce = await deployer.getNonce();
  const block = await hre.ethers.provider.getBlock("latest");
  const deployDayBoundary = computeDeployDayBoundary(block.timestamp);
  const predicted = predictAddresses(deployer.address, startingNonce);

  const vrfKeyHash =
    "0xabababababababababababababababababababababababababababababababab";
  const external = {
    STETH_TOKEN: await mockStETH.getAddress(),
    LINK_TOKEN: await mockLINK.getAddress(),
    VRF_COORDINATOR: await mockVRF.getAddress(),
    WXRP: await mockWXRP.getAddress(),
    CREATOR: deployer.address,
  };

  // --- Phase 3: Patch + compile (once) ---
  // We need to re-patch if addresses changed (fresh fixture = different mock addresses)
  const needsPatch =
    !_patched ||
    _patchedExternal?.VRF_COORDINATOR !== external.VRF_COORDINATOR;

  if (needsPatch) {
    patchContractAddresses(predicted, external, deployDayBoundary, vrfKeyHash);
    await hre.run("compile", { force: true, quiet: true });
    _patched = true;
    _patchedAddresses = predicted;
    _patchedExternal = external;
    _patchedDayBoundary = deployDayBoundary;
    _patchedVrfKeyHash = vrfKeyHash;
  }

  // --- Phase 4: Deploy all 23 protocol contracts ---
  const contracts = {};
  const deployedAddrs = new Map();

  for (const key of DEPLOY_ORDER) {
    const contractName = KEY_TO_CONTRACT[key];
    const args = getConstructorArgs(key, predicted);
    const contract = await deploy(contractName, args);
    const addr = await contract.getAddress();
    contracts[key] = contract;
    deployedAddrs.set(key, addr);
  }

  // --- Phase 5: Verify ---
  for (const [key, expectedAddr] of predicted) {
    const actualAddr = deployedAddrs.get(key);
    if (actualAddr.toLowerCase() !== expectedAddr.toLowerCase()) {
      throw new Error(
        `Address mismatch for ${key}: expected ${expectedAddr}, got ${actualAddr}`
      );
    }
  }

  return {
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
    mockWXRP,
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
    sdgnrs: contracts.SDGNRS,
    dgnrs: contracts.DGNRS,
    admin: contracts.ADMIN,
    gnrus: contracts.GNRUS,

    // Game modules
    mintModule: contracts.GAME_MINT_MODULE,
    advanceModule: contracts.GAME_ADVANCE_MODULE,
    whaleModule: contracts.GAME_WHALE_MODULE,
    jackpotModule: contracts.GAME_JACKPOT_MODULE,
    decimatorModule: contracts.GAME_DECIMATOR_MODULE,
    gameOverModule: contracts.GAME_GAMEOVER_MODULE,
    lootboxModule: contracts.GAME_LOOTBOX_MODULE,
    boonModule: contracts.GAME_BOON_MODULE,
    degeneretteModule: contracts.GAME_DEGENERETTE_MODULE,

    // Metadata
    predicted,
    deployedAddrs,
    deployDayBoundary,
    startingNonce,
  };
}

/**
 * Restore ContractAddresses.sol after all tests complete.
 * Call this in an after() hook in your top-level test file.
 */
export function restoreAddresses() {
  restoreContractAddresses();
  _patched = false;
}

// --- Internal helpers ---

async function deploy(contractName, args = []) {
  const factory = await hre.ethers.getContractFactory(contractName);
  const contract = await factory.deploy(...args);
  await contract.waitForDeployment();
  return contract;
}

function getConstructorArgs(key, predicted) {
  if (key === "AFFILIATE") {
    return [[], [], [], [], []];
  }
  return [];
}
