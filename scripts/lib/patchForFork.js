import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  predictAddresses,
  computeDeployDayBoundary,
} from "./predictAddresses.js";
import { patchContractAddresses } from "./patchContractAddresses.js";
import {
  FOUNDRY_TEST_CONTRACT,
  PROTOCOL_START_NONCE,
} from "./patchForFoundry.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PINS_FILE = resolve(__dirname, "../../test/fork/ForkPins.sol");

/**
 * Read the fork pins from test/fork/ForkPins.sol, the single source of truth shared with the
 * Solidity fixture (which re-checks every value against the compiled ContractAddresses).
 * @returns {{FORK_BLOCK:number, FORK_TIMESTAMP:number, STETH:string, LINK:string,
 */
export function readForkPins(file = PINS_FILE) {
  const src = readFileSync(file, "utf8");
  const pick = (name, pattern) => {
    const re = new RegExp(`constant ${name} = (${pattern});`);
    const matches = src.match(new RegExp(re.source, "g"));
    if (!matches || matches.length !== 1) {
      throw new Error(`patchForFork: expected exactly one '${name}' pin in ${file}`);
    }
    return src.match(re)[1];
  };
  return {
    FORK_BLOCK: Number(pick("FORK_BLOCK", "\\d+")),
    FORK_TIMESTAMP: Number(pick("FORK_TIMESTAMP", "\\d+")),
    STETH: pick("STETH", "0x[0-9a-fA-F]{40}"),
    VRF_COORDINATOR: pick("VRF_COORDINATOR", "0x[0-9a-fA-F]{40}"),
    VRF_KEY_HASH: pick("VRF_KEY_HASH", "0x[0-9a-fA-F]{64}"),
  };
}

/**
 * Patch ContractAddresses.sol for the mainnet-fork suite (test/fork). Every protocol address is
 * predicted EXACTLY as patchForFoundry does (same test-contract deployer, the four mocks still
 * occupy nonces 1-4, protocol from nonce 5), so the fork deployment lands on the same addresses.
 * Only the external dependencies differ: STETH_TOKEN, LINK_TOKEN, VRF_COORDINATOR and
 * LINK_ETH_FEED point at the real mainnet contracts, VRF_KEY_HASH is a lane the real coordinator
 * has registered, and DEPLOY_DAY_BOUNDARY is derived from the pinned block's timestamp — the
 * fork keeps mainnet time (the fixture does not warp to 86400, which would put the real LINK/ETH
 * round in the future).
 */
export function patchForFork() {
  const pins = readForkPins();
  const predicted = predictAddresses(FOUNDRY_TEST_CONTRACT, PROTOCOL_START_NONCE);
  const external = {
    STETH_TOKEN: pins.STETH,
    VRF_COORDINATOR: pins.VRF_COORDINATOR,
    CREATOR: FOUNDRY_TEST_CONTRACT,
  };
  const dayBoundary = computeDeployDayBoundary(pins.FORK_TIMESTAMP);
  patchContractAddresses(predicted, external, dayBoundary, pins.VRF_KEY_HASH);
  return { pins, predicted, external, dayBoundary };
}

const scriptPath = process.argv[1];
if (scriptPath && scriptPath.endsWith("patchForFork.js")) {
  const { pins, predicted, external, dayBoundary } = patchForFork();
  console.log("Fork ContractAddresses patched:");
  console.log(`  Fork block:     ${pins.FORK_BLOCK} (timestamp ${pins.FORK_TIMESTAMP})`);
  console.log(`  Day boundary:   ${dayBoundary}`);
  console.log(`  stETH:          ${external.STETH_TOKEN}`);
  console.log(`  VRF v2.5:       ${external.VRF_COORDINATOR}`);
  console.log(`  VRF key hash:   ${pins.VRF_KEY_HASH}`);
  console.log(`  GAME:           ${predicted.get("GAME")}`);
}
