// Post-deploy ENS forward-record + reverse-name verifier.
//
// The contracts set their OWN reverse record in-constructor (setName), which is
// only DISPLAYED by wallets once a matching forward record (name -> address)
// exists — "forward-confirmed" reverse resolution. This script writes those
// forward records under the parent name and then verifies each contract's
// primary name resolves back correctly.
//
// It touches only the ENS registry/resolver — never the protocol contracts —
// and is a mainnet/L1 operation (the `<label>.degenerus.eth` subdomains live on
// L1 Ethereum regardless of where the protocol is deployed).
//
// Required env:
//   ENS_PARENT_NAME     e.g. "degenerus.eth" (you must own it; deployer = its controller)
//   ENS_PUBLIC_RESOLVER  the PublicResolver the subdomains should point at
// Optional env:
//   ENS_REGISTRY        defaults to the canonical ENS registry (same on mainnet + sepolia)
//   ENS_MANIFEST        path to a deployment manifest; defaults to newest deployments/<network>-*.json
//
// Usage: npx hardhat run scripts/ens-register.js --network mainnet

import hre from "hardhat";
import { readdirSync, readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { forwardConfirmedName } from "./lib/ensForwardConfirmed.js";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Canonical ENS registry — identical address on Ethereum mainnet and Sepolia.
const DEFAULT_ENS_REGISTRY = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";

// manifest key (ContractAddresses / DEPLOY_ORDER name) -> subdomain label.
// Mirrors the setName("<label>.degenerus.eth") string baked into each constructor.
const LABELS = {
  GAME: "game",
  COIN: "flip",
  COINFLIP: "coinflip",
  SDGNRS: "sdgnrs",
  DGNRS: "dgnrs",
  VAULT: "vault",
  AFFILIATE: "affiliate",
  JACKPOTS: "jackpots",
  QUESTS: "quests",
  DEITY_PASS: "deity",
  GNRUS: "gnrus",
  WWXRP: "wwxrp",
  AFKING_SUB_TOKEN: "afking",
  ADMIN: "admin",
  PARIMUTUEL: "parimutuel",
  VAULT_FLIP_SHARE: "dgvf",
  VAULT_ETH_SHARE: "dgve",
};

// Every contract whose constructor calls setName MUST appear in LABELS, or its
// forward record is never written and its reverse name displays nowhere.
// Guard against the list drifting out of sync with the contracts again.
// Note: DegenerusVaultShare has ONE parameterized setName site covering TWO
// deployed instances (dgvf + dgve), so labels = setName grep hits + 1.
const EXPECTED_LABEL_COUNT = 17;

const REGISTRY_ABI = [
  "function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external",
  "function owner(bytes32 node) external view returns (address)",
];
const RESOLVER_ABI = [
  "function setAddr(bytes32 node, address addr) external",
  "function addr(bytes32 node) external view returns (address)",
];

function newestManifest(network) {
  const dir = resolve(__dirname, "../deployments");
  const files = readdirSync(dir)
    .filter((f) => f.startsWith(`${network}-`) && f.endsWith(".json"))
    .sort();
  if (files.length === 0) {
    throw new Error(`No deployment manifest found for network "${network}" in ${dir}`);
  }
  return resolve(dir, files[files.length - 1]);
}

async function main() {
  const { ethers } = hre;
  const network = hre.network.name;

  const parentName = process.env.ENS_PARENT_NAME;
  const resolverAddr = process.env.ENS_PUBLIC_RESOLVER;
  const registryAddr = process.env.ENS_REGISTRY || DEFAULT_ENS_REGISTRY;
  if (!parentName) throw new Error("ENS_PARENT_NAME not set (e.g. degenerus.eth)");
  if (!resolverAddr) throw new Error("ENS_PUBLIC_RESOLVER not set");

  const labelCount = Object.keys(LABELS).length;
  if (labelCount !== EXPECTED_LABEL_COUNT) {
    throw new Error(
      `LABELS has ${labelCount} entries, expected ${EXPECTED_LABEL_COUNT}. Every ` +
        `contract with an in-constructor setName needs one. Verify against: ` +
        `grep -rn 'setName(string)", "' contracts/`
    );
  }

  const manifestPath = process.env.ENS_MANIFEST || newestManifest(network);
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const contracts = manifest.contracts || {};

  const [signer] = await ethers.getSigners();
  const parentNode = ethers.namehash(parentName);

  const registry = new ethers.Contract(registryAddr, REGISTRY_ABI, signer);
  const parentOwner = await registry.owner(parentNode);
  if (parentOwner.toLowerCase() !== signer.address.toLowerCase()) {
    throw new Error(
      `Signer ${signer.address} does not own ${parentName} on ${network} ` +
        `(registry owner is ${parentOwner}). Cannot create subdomains.`
    );
  }
  const resolver = new ethers.Contract(resolverAddr, RESOLVER_ABI, signer);

  console.log(`Network:   ${network}`);
  console.log(`Parent:    ${parentName} (${parentNode})`);
  console.log(`Registry:  ${registryAddr}`);
  console.log(`Resolver:  ${resolverAddr}`);
  console.log(`Manifest:  ${manifestPath}\n`);

  // 1. Forward records: create each subnode and point its addr at the contract.
  for (const [key, label] of Object.entries(LABELS)) {
    const addr = contracts[key];
    if (!addr) {
      console.log(`SKIP  ${label}.${parentName} — "${key}" absent from manifest`);
      continue;
    }
    const labelHash = ethers.keccak256(ethers.toUtf8Bytes(label));
    const node = ethers.namehash(`${label}.${parentName}`);

    const cur = await resolver.addr(node).catch(() => ethers.ZeroAddress);
    if (cur.toLowerCase() === addr.toLowerCase()) {
      console.log(`OK    ${label}.${parentName} already -> ${addr}`);
      continue;
    }
    const t1 = await registry.setSubnodeRecord(parentNode, labelHash, signer.address, resolverAddr, 0);
    await t1.wait();
    const t2 = await resolver.setAddr(node, addr);
    await t2.wait();
    console.log(`SET   ${label}.${parentName} -> ${addr}`);
  }

  // 2. Verify reverse (primary) names resolve forward-confirmed. The constructors
  //    set the reverse record on deploy; this confirms wallets will display it.
  console.log(`\nVerifying reverse (primary) names via forward-confirmed lookup:`);
  let missing = 0;
  for (const [key, label] of Object.entries(LABELS)) {
    const addr = contracts[key];
    if (!addr) continue;
    const expected = `${label}.${parentName}`;
    // Deliberately NOT provider.lookupAddress(): that needs an ENS plugin in
    // ethers' network config (mainnet/sepolia/holesky only) and throws
    // "network does not support ENS" anywhere else, reporting a false MISS for
    // every contract. This applies the same forward-confirmation rule against
    // the registry actually in use.
    const { name: got, reason } = await forwardConfirmedName(
      ethers.provider,
      registryAddr,
      addr
    );
    if (got === expected) {
      console.log(`PASS  ${addr} -> ${got}`);
    } else {
      missing++;
      console.log(`MISS  ${addr} expected ${expected} — ${reason}`);
    }
  }
  if (missing > 0) {
    console.log(
      `\n${missing} contract(s) have no forward-confirmed primary name. For non-Ownable ` +
        `contracts the in-constructor setName is one-shot, so a MISS there means the reverse ` +
        `record did not land at deploy (check ENS_REVERSE_REGISTRAR was patched correctly). ` +
        `Ownable contracts (DEITY_PASS/ADMIN/AFKING_SUB_TOKEN) can be re-set via setNameForAddr.`
    );
  } else {
    console.log(`\nAll primary names resolve forward-confirmed.`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
