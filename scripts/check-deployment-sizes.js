// Check exactly the production deploy set against fresh Foundry artifacts.
// Usage: forge build --skip test; node scripts/check-deployment-sizes.js [out]
import fs from "node:fs";
import path from "node:path";
import { keccak256 } from "ethers";
import { DEPLOY_ORDER, KEY_TO_CONTRACT } from "./lib/predictAddresses.js";

const out = process.argv[2] || process.env.FOUNDRY_OUT || "forge-out";
const names = [...new Set([...DEPLOY_ORDER.map(k => KEY_TO_CONTRACT[k]), "DegenerusVaultShare"])];
const sourceHashes = new Map();
const rows = [];
for (const name of names) {
  const source = name === "DegenerusVaultShare" ? "DegenerusVault" : name;
  const artifact = JSON.parse(fs.readFileSync(path.join(out, `${source}.sol`, `${name}.json`)));
  const metadata = typeof artifact.metadata === "string" ? JSON.parse(artifact.metadata) : artifact.metadata;
  if (!metadata?.sources) throw new Error(`${name}: source metadata missing`);
  for (const [file, expected] of Object.entries(metadata.sources)) {
    if (!sourceHashes.has(file)) sourceHashes.set(file, keccak256(fs.readFileSync(file)));
    if (sourceHashes.get(file) !== expected.keccak256) throw new Error(`${name}: stale source ${file}`);
  }
  const hex = artifact.deployedBytecode.object.replace(/^0x/, "");
  if (!hex || !/^(?:[0-9a-fA-F]{2})+$/.test(hex)) throw new Error(`${name}: missing/unlinked runtime`);
  const size = hex.length / 2;
  rows.push({ contract: name, runtime_bytes: size, remaining_bytes: 24576 - size });
}
console.log(JSON.stringify(rows.sort((a, b) => b.runtime_bytes - a.runtime_bytes), null, 2));
if (rows.some(row => row.remaining_bytes < 0)) process.exitCode = 1;
