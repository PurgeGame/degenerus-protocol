// Portable forward-confirmed reverse ENS resolution.
//
// ethers' provider.lookupAddress() only works on chains ethers ships an ENS
// plugin for (mainnet, sepolia, holesky). It throws "network does not support
// ENS" everywhere else, so it cannot verify a deploy on any other chain.
//
// This does the same job against an explicitly supplied registry, which is the
// only requirement: reverse records are unverified claims (any address may
// claim any name), so a name is only trustworthy once resolving it FORWARD
// returns the address you started from. Wallets apply exactly this rule, which
// is why a reverse record with no matching forward record displays nowhere.

import { Contract, ZeroAddress, namehash } from "ethers";

const RESOLVER_LOOKUP_ABI = ["function resolver(bytes32) view returns (address)"];
const NAME_ABI = ["function name(bytes32) view returns (string)"];
const ADDR_ABI = ["function addr(bytes32) view returns (address)"];

/**
 * Resolve an address to its forward-confirmed primary ENS name.
 *
 * @param {import("ethers").Provider} provider
 * @param {string} registryAddress - ENS (or ENS-compatible) registry
 * @param {string} address - address to reverse-resolve
 * @returns {Promise<{name: string|null, reason: string}>} name is null unless
 *   the round trip confirms; reason names the step that failed, for diagnostics.
 */
export async function forwardConfirmedName(provider, registryAddress, address) {
  const registry = new Contract(registryAddress, RESOLVER_LOOKUP_ABI, provider);
  const reverseNode = namehash(`${address.slice(2).toLowerCase()}.addr.reverse`);

  const reverseResolver = await registry.resolver(reverseNode).catch(() => ZeroAddress);
  if (reverseResolver === ZeroAddress) {
    return { name: null, reason: "no reverse resolver (setName never landed)" };
  }

  const claimed = await new Contract(reverseResolver, NAME_ABI, provider)
    .name(reverseNode)
    .catch(() => "");
  if (!claimed) {
    return { name: null, reason: "reverse resolver holds no name" };
  }

  const forwardNode = namehash(claimed);
  const forwardResolver = await registry.resolver(forwardNode).catch(() => ZeroAddress);
  if (forwardResolver === ZeroAddress) {
    return { name: null, reason: `no forward resolver for "${claimed}"` };
  }

  const forwardAddr = await new Contract(forwardResolver, ADDR_ABI, provider)
    .addr(forwardNode)
    .catch(() => ZeroAddress);
  if (forwardAddr.toLowerCase() !== address.toLowerCase()) {
    return {
      name: null,
      reason: `"${claimed}" forward-resolves to ${forwardAddr}, not ${address}`,
    };
  }

  return { name: claimed, reason: "confirmed" };
}
