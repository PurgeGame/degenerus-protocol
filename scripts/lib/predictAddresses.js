import { ethers } from "ethers";

// 22:57 UTC in seconds — matches GameTimeLib.JACKPOT_RESET_TIME
const JACKPOT_RESET_TIME = 82620n;

import { DEPLOYMENTS, expandAliases } from "./deploymentManifest.js";
export { DEPLOYMENTS, expandAliases } from "./deploymentManifest.js";
export const DEPLOY_ORDER = DEPLOYMENTS.map(row => row.key);
export const KEY_TO_CONTRACT = Object.fromEntries(DEPLOYMENTS.flatMap(row =>
  row.aliases.map(alias => [alias, row.contract])));

/**
 * Predict CREATE addresses for the full deployment sequence.
 * @param {string} deployerAddress - Deployer EOA address
 * @param {number} startingNonce - Deployer's current nonce
 * @returns {Map<string, string>} Map from constant name to predicted address
 */
export function predictAddresses(deployerAddress, startingNonce) {
  const addresses = new Map();
  for (let i = 0; i < DEPLOY_ORDER.length; i++) {
    const addr = ethers.getCreateAddress({
      from: deployerAddress,
      nonce: startingNonce + (DEPLOYMENTS[i].nonceOffset ?? i),
    });
    addresses.set(DEPLOY_ORDER[i], addr);
  }
  return expandAliases(addresses);
}

/**
 * Compute DEPLOY_DAY_BOUNDARY from a deployment timestamp.
 * Matches GameTimeLib: day = (timestamp - JACKPOT_RESET_TIME) / 86400
 * @param {number} deployTimestamp - Unix timestamp in seconds
 * @returns {number} Day boundary as uint48
 */
export function computeDeployDayBoundary(deployTimestamp) {
  const ts = BigInt(deployTimestamp);
  return Number((ts - JACKPOT_RESET_TIME) / 86400n);
}

/** Check the next CREATE nonce; a fresh deployment has no retired nonce reservations. */
export async function reserveDeploymentNonces(signer, key, startingNonce) {
  const offset = DEPLOYMENTS.findIndex(row => row.key === key);
  if (offset < 0) throw new Error(`Unknown deployment ${key}`);
  const address = await signer.getAddress();
  const nonce = Number(BigInt(await signer.provider.send('eth_getTransactionCount', [address, 'pending'])));
  if (nonce !== startingNonce + offset) throw new Error(`Unexpected deployment nonce before ${key}: ${nonce}`);
}
