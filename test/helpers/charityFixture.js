import hre from "hardhat";
import { deployFullProtocol } from "./deployFixture.js";
import { eth } from "./testUtils.js";

// sDGNRS pool index used by transferFromPool to fund test voters.
export const POOL_REWARD = 3;

/**
 * Impersonate an address with a 100-ETH balance and return its signer.
 * Used to call onlyGame / onlyVault-owner gated functions in unit tests.
 */
export async function impersonate(address) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x56BC75E2D63100000", // 100 ETH
  ]);
  return hre.ethers.getSigner(address);
}

/**
 * Stop impersonating an address previously set up via {@link impersonate}.
 */
export async function stopImpersonating(address) {
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [address],
  });
}

/**
 * Fund `recipient` with `amount` sDGNRS by impersonating the game contract
 * and routing the transfer through the reward pool.
 */
export async function giveSDGNRS(sdgnrs, gameAddress, recipient, amount) {
  const gameSigner = await impersonate(gameAddress);
  await sdgnrs.connect(gameSigner).transferFromPool(POOL_REWARD, recipient, amount);
  await stopImpersonating(gameAddress);
}

/**
 * Deploy the full protocol and fund the v33 charity test signers.
 *
 * Returns the GNRUS contract (as `charity`), supporting protocol contracts,
 * and named voter / recipient signers + their addresses for tests that
 * impersonate contract addresses.
 */
export async function deployGNRUSFixture() {
  const protocol = await deployFullProtocol();
  const {
    deployer, alice, bob, carol,
    dan: recipient1, eve: recipient2, others,
    mockStETH: mockSteth,
    game, sdgnrs, vault, gnrus: charity,
  } = protocol;

  const voter1 = alice;
  const voter2 = bob;
  const voter3 = carol;
  const recipient3 = others[0];

  const gameAddress = await game.getAddress();
  const sdgnrsAddress = await sdgnrs.getAddress();
  const vaultAddress = await vault.getAddress();
  const stethAddress = await mockSteth.getAddress();
  const charityAddress = await charity.getAddress();

  // v33: vote weight = floor(sdgnrs.balanceOf(voter) / 1e18); no minimum, no bonus.
  // Sized for tie-break (voter1 == voter2 == 100 sDGNRS), multi-slot (per-voter
  // independence), and tie-breaker (voter3 == 200 sDGNRS to force a clear winner
  // when paired against the equal-weight pair).
  const voter1Amount = eth("100");   // 100 sDGNRS → vote weight = 100
  const voter2Amount = eth("100");   // 100 sDGNRS → vote weight = 100 (tie partner)
  const voter3Amount = eth("200");   // 200 sDGNRS → vote weight = 200 (tie breaker)

  await giveSDGNRS(sdgnrs, gameAddress, voter1.address, voter1Amount);
  await giveSDGNRS(sdgnrs, gameAddress, voter2.address, voter2Amount);
  await giveSDGNRS(sdgnrs, gameAddress, voter3.address, voter3Amount);

  // Sub-1e18 voters (weight = 0 → REJECT_ZERO_WEIGHT) are funded inline by
  // the it-blocks that exercise that branch — keeping them off the default
  // fixture avoids polluting tie-break tests with extra voting weight.

  // Collect extra signers
  const allSigners = await hre.ethers.getSigners();
  const extraOthers = allSigners.slice(7);

  return {
    charity,
    charityAddress,
    sdgnrs,
    game,
    vault,
    mockSteth,
    deployer,
    voter1,
    voter2,
    voter3,
    recipient1,
    recipient2,
    recipient3,
    others: [recipient3, ...extraOthers],
    // expose addresses for tests that impersonate contract addresses
    gameAddress,
    sdgnrsAddress,
    vaultAddress,
    stethAddress,
  };
}

/**
 * Drive a level transition by impersonating the game contract and calling
 * `pickCharity(level)` on the GNRUS contract. Returns the transaction.
 */
export async function runLevelTransitionViaGame(charity, gameAddress, level) {
  const gameSigner = await impersonate(gameAddress);
  const tx = await charity.connect(gameSigner).pickCharity(level);
  await stopImpersonating(gameAddress);
  return tx;
}
