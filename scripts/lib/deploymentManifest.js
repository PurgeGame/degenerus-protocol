import { PROFILE, PROFILES } from "./deploymentProfiles.js";
export { PROFILE, PROFILES };
export const DEPLOYMENTS = PROFILES[PROFILE];
export function usesAffiliateBootstrap(key) { return DEPLOYMENTS.find(row => row.key === key)?.bootstrap === true; }

export function aliasOwners(rows = DEPLOYMENTS) {
  const owners = new Map();
  for (const row of rows) {
    if (!row.aliases.includes(row.key)) throw new Error(`Missing canonical alias: ${row.key}`);
    for (const alias of row.aliases) {
      if (owners.has(alias)) throw new Error(`Duplicate alias: ${alias}`);
      owners.set(alias, row.key);
    }
  }
  return owners;
}
export function expandAliases(values, rows = DEPLOYMENTS) {
  const result = new Map();
  for (const [alias, owner] of aliasOwners(rows)) {
    if (!values.has(owner)) throw new Error(`Missing deployment: ${owner}`);
    result.set(alias, values.get(owner));
  }
  return result;
}
