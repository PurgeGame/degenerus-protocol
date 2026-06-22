// Configuration loader for the connect-and-play adversarial agent.
//
// The agent is a real EXTERNAL attacker: it connects to an already-running
// testnet (deployed + clocked + VRF-fed by a SEPARATE sim repo) and plays
// adversarially. It never deploys, never warps the clock, never fulfils VRF.
// `mode: "local"` points it at a local stand-in node (deploy-local.js + the
// dev-only env-driver) for BUILD/validation; `mode: "live"` points the SAME
// client at the real 15-min-day testnet — the only difference is config.
//
// Resolution order (last wins): packaged default.json -> the file named by
// AGENT_CONFIG (or agent/config/<mode>.json) -> AGENT_* env overrides.

import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
export const AGENT_ROOT = resolve(__dirname, "..");
export const REPO_ROOT = resolve(AGENT_ROOT, "..");

function readJson(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function deepMerge(base, over) {
  if (over === undefined) return base;
  if (Array.isArray(base) || typeof base !== "object" || base === null) return over;
  const out = { ...base };
  for (const k of Object.keys(over)) out[k] = deepMerge(base[k], over[k]);
  return out;
}

// AGENT_RPC_URL, AGENT_MODE, AGENT_DEPLOYMENTS, AGENT_DB, AGENT_K_SIGMA, ...
function envOverrides() {
  const e = process.env;
  const o = {};
  if (e.AGENT_MODE) o.mode = e.AGENT_MODE;
  if (e.AGENT_RPC_URL) o.rpcUrl = e.AGENT_RPC_URL;
  if (e.AGENT_DEPLOYMENTS) o.deploymentsPath = e.AGENT_DEPLOYMENTS;
  if (e.AGENT_ABIS_DIR) o.abisDir = e.AGENT_ABIS_DIR;
  if (e.AGENT_DB) o.ledger = { dbPath: e.AGENT_DB };
  if (e.AGENT_K_SIGMA) o.gate = { kSigma: Number(e.AGENT_K_SIGMA) };
  if (e.AGENT_MAX_TICKS) o.campaign = { maxTicks: Number(e.AGENT_MAX_TICKS) };
  if (e.AGENT_WALLET_COUNT) o.wallets = { count: Number(e.AGENT_WALLET_COUNT) };
  if (e.AGENT_MAX_FEE_GWEI) o.gas = { ...(o.gas || {}), maxFeeGwei: Number(e.AGENT_MAX_FEE_GWEI) };
  if (e.AGENT_MAX_PRIORITY_GWEI) o.gas = { ...(o.gas || {}), maxPriorityGwei: Number(e.AGENT_MAX_PRIORITY_GWEI) };
  return o;
}

// EIP-1559 fee overrides from the (gwei) gas config. null fields fall back to
// the network's own fee estimate; a set maxFeeGwei is a HARD per-tx ceiling so a
// tx only mines while basefee+tip stays under it (cheap-but-bounded on testnet).
export function buildGasOverrides(gas) {
  const o = {};
  const gwei = (x) => BigInt(Math.round(Number(x) * 1e9));
  if (gas?.maxFeeGwei != null) o.maxFeePerGas = gwei(gas.maxFeeGwei);
  if (gas?.maxPriorityGwei != null) o.maxPriorityFeePerGas = gwei(gas.maxPriorityGwei);
  // Never let the tip exceed the ceiling (ethers rejects priority > maxFee).
  if (o.maxFeePerGas != null && o.maxPriorityFeePerGas != null && o.maxPriorityFeePerGas > o.maxFeePerGas) {
    o.maxPriorityFeePerGas = o.maxFeePerGas;
  }
  return o;
}

export const DEFAULTS = {
  // "local" = stand-in node for build/validation; "live" = real 15-min-day testnet.
  mode: "local",
  rpcUrl: "http://127.0.0.1:8545",
  // Deployment artifacts emitted by scripts/deploy-local.js Phase 6.
  deploymentsPath: "deployments/localhost.json",
  abisDir: "deployments/localhost-abis",
  wallets: {
    // Adversary wallet count. In local mode these are funded from the deployer
    // unlocked account; in live mode supply privateKeys + a funderPrivateKey.
    count: 3,
    fundingEth: "0.01", // /1e6 testnet: a ticket is ~1e-8 ETH, so this is plenty.
    lowWaterEth: "0.0005", // drip-refill an actor wallet below this (live mode).
    privateKeys: [], // live mode: explicit attacker keys (else derived from mnemonic).
    funderPrivateKey: null, // live mode: key that drips refills; null in local.
    mnemonic: null, // optional: derive `count` wallets from this mnemonic.
  },
  gate: {
    // The "win more than you should" alarm fires only when realized per-actor
    // protocol-value profit exceeds the modeled EV bound by kSigma over a
    // counted sample (never per-spin). mainnet-gas-viability flagged separately.
    kSigma: 4,
    minSample: 200,
    // A single unbacked-payout / solvency break is scale-invariant and alarms
    // immediately regardless of sample (it is a conservation break, not variance).
    solvencyImmediate: true,
  },
  // EIP-1559 fee caps (gwei). null = use the network estimate. On the testnet a
  // tight cap keeps the soak from wasting gas; a tx that can't fit under the cap
  // simply hits the confirm-timeout soft-revert and is retried next tick.
  gas: { maxFeeGwei: null, maxPriorityGwei: null },
  ledger: { dbPath: "agent/.state/ledger.db" },
  records: { dir: "agent/.state/findings" },
  campaign: {
    tickMs: 1500, // poll/act cadence; live testnet day is ~15 min so this is fine.
    maxTicks: 0, // 0 = run until stopped (soak); >0 bounds a validation run.
    checkpointEverySec: 30,
  },
  // Dev-only environment driver — stands in for the sim repo on a LOCAL node.
  // The attacker client NEVER reads this block; only agent/dev/env-driver.js does.
  devDriver: {
    enabled: false, // run-local.js turns this on; never true against a live RPC.
    dayWarpSeconds: 86400, // one on-chain game-day is hard-coded to 86400s.
    honestActors: 2,
    maxAdvancePerTick: 4,
  },
};

export function loadConfig(overrides = {}) {
  let cfg = structuredClone(DEFAULTS);

  const named = process.env.AGENT_CONFIG
    ? resolveRepo(process.env.AGENT_CONFIG)
    : resolve(AGENT_ROOT, "config", `${cfg.mode}.json`);
  if (existsSync(named)) cfg = deepMerge(cfg, readJson(named));

  cfg = deepMerge(cfg, envOverrides());
  cfg = deepMerge(cfg, overrides);

  // A live RPC must never run the dev driver — that would be driving the
  // environment, which an external attacker categorically cannot do.
  if (cfg.mode === "live") cfg.devDriver.enabled = false;

  cfg.deploymentsPath = resolveRepo(cfg.deploymentsPath);
  cfg.abisDir = resolveRepo(cfg.abisDir);
  cfg.ledger.dbPath = resolveRepo(cfg.ledger.dbPath);
  cfg.records.dir = resolveRepo(cfg.records.dir);
  return cfg;
}

export function resolveRepo(p) {
  return isAbsolute(p) ? p : resolve(REPO_ROOT, p);
}
