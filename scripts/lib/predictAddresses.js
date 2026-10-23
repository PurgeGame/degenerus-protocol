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

/** Consume only explicitly reserved retired-deployment nonces, preserving token addresses. */
export async function reserveDeploymentNonces(signer, key, startingNonce) {
  const i = DEPLOYMENTS.findIndex(row => row.key === key);
  if (i < 0) throw new Error(`Unknown deployment ${key}`);
  const offset = DEPLOYMENTS[i].nonceOffset ?? i;
  const previous = i === 0 ? -1 : (DEPLOYMENTS[i-1].nonceOffset ?? i-1);
  const gap = offset - previous - 1;
  const address = await signer.getAddress();
  const nonce = Number(BigInt(await signer.provider.send('eth_getTransactionCount',[address,'pending'])));
  if (nonce !== startingNonce + offset - gap) throw new Error(`Unexpected deployment nonce before ${key}: ${nonce}`);
  for (let n=0; n<gap; ++n) await (await signer.sendTransaction({to:address,value:0,nonce:nonce+n})).wait();
}
