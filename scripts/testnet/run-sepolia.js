#!/usr/bin/env node
/**
 * Sepolia testnet runner: connects to existing Sepolia deployment,
 * bootstraps the game, then runs the orchestrator with actors.
 *
 * Uses real Chainlink VRF V2.5 — no mock fulfillment.
 * Uses advanceDay() (CREATOR-only) instead of evm_increaseTime.
 *
 * Prerequisites:
 *   1. Deploy via: TESTNET_BUILD=1 npx hardhat run scripts/deploy-sepolia-testnet.js --network sepolia
 *   2. Fund VRF subscription with LINK (send to Admin via transferAndCall)
 *   3. Fund deployer + player wallets with Sepolia ETH
 *   4. Set PURGE_RPC_URL or SEPOLIA_RPC_URL in .env
 *
 * Usage:
 *   node scripts/testnet/run-sepolia.js [--skip-bootstrap] [--actors advancer-sepolia,buyer-1,...]
 */

// Crash resilience: log unhandled errors instead of silently dying
process.on('unhandledRejection', (reason, promise) => {
  console.error(`[FATAL] Unhandled rejection:`, reason);
});
process.on('uncaughtException', (err) => {
  console.error(`[FATAL] Uncaught exception:`, err);
});

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';
import { ethers } from 'ethers';
import { loadSepoliaConfig } from './lib/config-sepolia.js';
import { createGameClient, readGameState } from './lib/game-client.js';
import { Orchestrator } from './orchestrator.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PROJECT_ROOT = path.resolve(__dirname, '..', '..');

// Parse CLI args
const args = process.argv.slice(2);
const skipBootstrap = args.includes('--skip-bootstrap');
const actorsIdx = args.indexOf('--actors');
const actorsArg = actorsIdx !== -1 ? args[actorsIdx + 1] : null;

function log(msg) {
  console.log(`[run-sepolia] ${msg}`);
}

// Create timestamped run directory
const runTs = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const runsDir = path.join(PROJECT_ROOT, 'runs', 'sepolia');
const runDir = path.join(runsDir, runTs);
fs.mkdirSync(runDir, { recursive: true });
const dbPath = path.join(runDir, 'events.db');
log(`Run directory: ${runDir}`);

// Load Sepolia config
const cfg = loadSepoliaConfig();
log(`RPC: ${cfg.rpcUrl}`);
log(`Game: ${cfg.contracts.GAME}`);
log(`Admin: ${cfg.contracts.ADMIN}`);
log(`VRF Coordinator: ${cfg.external.VRF_COORDINATOR}`);

// Override DB path for this run
process.env.PURGE_DB_PATH = dbPath;

// Bootstrap: drive initial advanceGame + VRF cycle
if (!skipBootstrap) {
  log('Bootstrapping game state (real VRF — this may take a minute)...');

  const ownerKey = cfg.ownerKey;
  if (!ownerKey) {
    throw new Error('No owner key. Set DEPLOYER_PRIVATE_KEY in .env or ownerPrivateKey in wallets.json');
  }

  const { provider, wallet, contracts } = createGameClient(cfg, ownerKey);
  const MAX_CYCLES = 100;
  let cycle = 0;

  while (cycle < MAX_CYCLES) {
    const state = await readGameState(contracts);
    log(`  [${cycle}] L${state.level} ${state.jackpotPhase ? 'JACKPOT' : 'BUY'} ` +
      `rng=${state.rngLocked ? 'LOCKED' : 'ok'} fulfilled=${state.rngFulfilled}`);

    if (!state.rngLocked) {
      log('  Game is ready for player interaction!');

      // Set up Vault
      if (contracts.vault) {
        try {
          const tx1 = await contracts.vault.gameClaimWhalePass();
          await tx1.wait();
          log('  Vault: whale pass claimed');
        } catch (e) {
          log(`  Vault whale pass: ${e.reason || e.shortMessage || 'already claimed'}`);
        }
        try {
          const tx2 = await contracts.vault.gameSetAfKingMode(true, 0, 0);
          await tx2.wait();
          log('  Vault: afKing enabled');
        } catch (e) {
          log(`  Vault afKing: ${e.reason || e.shortMessage || e.message}`);
        }
      }
      break;
    }

    // If VRF is fulfilled, consume it
    if (state.rngFulfilled) {
      try {
        const tx = await contracts.game.advanceGame({ gasLimit: 15_000_000 });
        const r = await tx.wait();
        log(`  advanceGame (consume VRF) OK (gas: ${r.gasUsed})`);
      } catch (e) {
        log(`  advanceGame: ${e.reason || e.shortMessage || e.message}`);
      }
      cycle++;
      continue;
    }

    // RNG locked but not fulfilled — wait for Chainlink
    // First check if we need to advance a day and request VRF
    const rngLocked = await contracts.game.rngLocked();
    if (!rngLocked) {
      // Advance the day
      try {
        const tx = await contracts.game.advanceDay({ gasLimit: 100_000 });
        await tx.wait();
        log('  Day advanced via advanceDay()');
      } catch (e) {
        log(`  advanceDay: ${e.reason || e.shortMessage || e.message}`);
      }

      // Request VRF
      try {
        const tx = await contracts.game.advanceGame({ gasLimit: 15_000_000 });
        await tx.wait();
        log('  advanceGame (request VRF) OK');
      } catch (e) {
        log(`  advanceGame: ${e.reason || e.shortMessage || e.message}`);
      }
      cycle++;
      continue;
    }

    // Waiting for Chainlink VRF fulfillment
    log('  Waiting for Chainlink VRF fulfillment...');
    await new Promise(r => setTimeout(r, 12_000));
    cycle++;
  }

  if (cycle >= MAX_CYCLES) {
    log(`Reached ${MAX_CYCLES} bootstrap cycles. Check VRF subscription LINK balance.`);
  }

  provider.destroy();
  log('Bootstrap complete');
}

// Copy deployment manifest to run directory
try {
  const deployPath = path.join(PROJECT_ROOT, 'deployments', 'sepolia-testnet.json');
  fs.copyFileSync(deployPath, path.join(runDir, 'deployment.json'));
  log(`Deployment manifest saved to ${runDir}`);
} catch (err) {
  log(`Warning: could not copy deployment manifest: ${err.message}`);
}

// Start orchestrator with Sepolia config
log('Starting orchestrator...');

// Default Sepolia actor layout: advancer-sepolia + 8 buyers (fast intervals for testnet)
const SEPOLIA_DEFAULT_ACTORS = [
  { name: 'advancer-sepolia', strategy: 'advancer-sepolia', walletSource: 'deployer', interval: 6_000 },
  { name: 'whale-buyer',     strategy: 'whale-buyer',      walletSource: 'player:0', interval: [8_000, 15_000] },
  { name: 'deity-buyer',     strategy: 'deity-buyer',      walletSource: 'player:1', interval: [8_000, 15_000] },
  { name: 'target-buyer',    strategy: 'target-buyer',     walletSource: 'player:2', interval: [8_000, 15_000] },
  { name: 'buyer-1',         strategy: 'buyer',            walletSource: 'player:3', interval: [8_000, 15_000] },
  { name: 'buyer-2',         strategy: 'buyer',            walletSource: 'player:4', interval: [8_000, 15_000] },
  { name: 'buyer-3',         strategy: 'buyer',            walletSource: 'player:5', interval: [8_000, 15_000] },
  { name: 'buyer-4',         strategy: 'buyer',            walletSource: 'player:6', interval: [8_000, 15_000] },
  { name: 'buyer-5',         strategy: 'buyer',            walletSource: 'player:7', interval: [8_000, 15_000] },
];

// Parse requested actor filter
const actorFilter = actorsArg
  ? actorsArg.split(',').map(s => s.trim())
  : null;

class SepoliaOrchestrator extends Orchestrator {
  constructor(opts) {
    const sepoliaCfg = loadSepoliaConfig();
    sepoliaCfg.dbPath = dbPath;
    // Limit player keys to only those used by actors (avoid polling 100 players on Alchemy free tier)
    const maxPlayerIdx = Math.max(...SEPOLIA_DEFAULT_ACTORS
      .filter(a => a.walletSource.startsWith('player:'))
      .map(a => parseInt(a.walletSource.split(':')[1], 10)));
    sepoliaCfg.playerKeys = sepoliaCfg.playerKeys.slice(0, maxPlayerIdx + 1);
    super({ ...opts, config: sepoliaCfg });
  }

  getActorConfigs() {
    let actors = SEPOLIA_DEFAULT_ACTORS;
    if (actorFilter) {
      actors = actors.filter(a =>
        actorFilter.includes(a.name) || actorFilter.includes(a.strategy)
      );
    }
    return actors;
  }
}

const orchestrator = new SepoliaOrchestrator({});

// Graceful shutdown
process.on('SIGINT', async () => {
  log(`Data preserved in: ${runDir}`);
  await orchestrator.stop();
  process.exit(0);
});
process.on('SIGTERM', async () => {
  log(`Data preserved in: ${runDir}`);
  await orchestrator.stop();
  process.exit(0);
});

orchestrator.start().catch(err => {
  log(`Fatal: ${err.message}`);
  log(`Data preserved in: ${runDir}`);
  process.exit(1);
});

log(`All systems running on Sepolia. DB: ${dbPath}`);
log('Press Ctrl+C to stop.');
