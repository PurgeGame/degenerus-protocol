import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '..', '..', '..');

function loadDotEnv(filePath) {
  try {
    if (!fs.existsSync(filePath)) return;
    const raw = fs.readFileSync(filePath, 'utf8');
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const eq = trimmed.indexOf('=');
      if (eq === -1) continue;
      const key = trimmed.slice(0, eq).trim();
      let value = trimmed.slice(eq + 1).trim();
      if (!key) continue;
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      if (process.env[key] === undefined) process.env[key] = value;
    }
  } catch { /* best-effort */ }
}

export function loadSepoliaConfig() {
  loadDotEnv(path.join(PROJECT_ROOT, '.env'));

  const deployPath = path.join(PROJECT_ROOT, 'deployments', 'sepolia-testnet.json');
  if (!fs.existsSync(deployPath)) {
    throw new Error(`deployments/sepolia-testnet.json not found. Run deploy-sepolia-testnet.js first.`);
  }
  const deployment = JSON.parse(fs.readFileSync(deployPath, 'utf8'));

  const walletsPath = path.join(PROJECT_ROOT, 'wallets.json');
  let wallets = null;
  if (fs.existsSync(walletsPath)) {
    wallets = JSON.parse(fs.readFileSync(walletsPath, 'utf8'));
  }

  const rpcUrl = process.env.PURGE_RPC_URL || process.env.SEPOLIA_RPC_URL || process.env.RPC_URL;
  if (!rpcUrl) {
    throw new Error('No RPC URL set. Set PURGE_RPC_URL, SEPOLIA_RPC_URL, or RPC_URL in .env');
  }

  const startBlock = deployment.deployBlock || 0;

  return {
    projectRoot: PROJECT_ROOT,
    rpcUrl,
    deployment,
    contracts: deployment.contracts,
    mocks: deployment.mocks,
    external: deployment.external,
    deployDayBoundary: deployment.deployDayBoundary,
    isLocal: false, // Real network — no evm_increaseTime
    artifactsBase: path.join('artifacts-testnet', 'contracts-testnet'),
    startBlock,
    deployerKey: process.env.PURGE_DEPLOYER_KEY || process.env.DEPLOYER_PRIVATE_KEY || null,
    ownerKey: wallets?.ownerPrivateKey || process.env.PURGE_DEPLOYER_KEY || process.env.DEPLOYER_PRIVATE_KEY || null,
    playerKeys: wallets?.players?.map(p => p.privateKey) || [],
    playerNames: wallets?.players?.map(p => p.name) || [],
    signers: deployment.signers || {},
    dbPath: process.env.PURGE_DB_PATH || path.join(PROJECT_ROOT, 'testnet-events.db'),
    // Sepolia via Alchemy free tier: ~5 block getLogs limit, 12s blocks
    eventBatchSize: 5,
    eventPollInterval: 15_000,
    // Actor intervals — fast for testnet throughput
    intervals: {
      advancer: 6_000,
      buyer: [8_000, 15_000],
      burner: [15_000, 30_000],
      flipper: [15_000, 30_000],
      claimer: 30_000,
      statePoll: 12_000,
      stateDeepPoll: 30_000,
      eventHealth: 20_000,
    },
  };
}
