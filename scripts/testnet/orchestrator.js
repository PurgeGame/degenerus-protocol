import { Worker } from 'node:worker_threads';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { ethers } from 'ethers';
import { loadConfig } from './lib/config.js';
import { loadContractAbis } from './lib/abi-loader.js';
import { openDatabase, logActorAction } from './lib/db.js';
import { createProvider, createWallet } from './lib/game-client.js';
import { startEventLogger } from './event-logger.js';
import { StateMirror } from './state-mirror.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Default actor configuration.
 * Each actor specifies: strategy, wallet source, interval.
 */
const DEFAULT_ACTORS = [
  { name: 'advancer',      strategy: 'advancer',      walletSource: 'owner',    interval: 5_000 },
  { name: 'whale-buyer',   strategy: 'whale-buyer',   walletSource: 'player:0', interval: [10_000, 20_000] },
  { name: 'deity-buyer',   strategy: 'deity-buyer',   walletSource: 'player:1', interval: [10_000, 20_000] },
  { name: 'target-buyer',  strategy: 'target-buyer',  walletSource: 'player:2', interval: [10_000, 20_000] },
  { name: 'buyer-1',       strategy: 'buyer',         walletSource: 'player:3', interval: [10_000, 20_000] },
  { name: 'buyer-2',       strategy: 'buyer',         walletSource: 'player:4', interval: [10_000, 20_000] },
  { name: 'buyer-3',       strategy: 'buyer',         walletSource: 'player:5', interval: [10_000, 20_000] },
  { name: 'buyer-4',       strategy: 'buyer',         walletSource: 'player:6', interval: [10_000, 20_000] },
  { name: 'buyer-5',       strategy: 'buyer',         walletSource: 'player:7', interval: [10_000, 20_000] },
  { name: 'buyer-6',       strategy: 'buyer',         walletSource: 'player:8', interval: [10_000, 20_000] },
];

export class Orchestrator {
  constructor(opts = {}) {
    this.config = opts.config || loadConfig();
    this.actorFilter = opts.actors || null; // null = all, or array of names
    this.loggerOnly = opts.loggerOnly || false;
    this.workers = new Map();
    this.db = null;
    this.eventLogger = null;
    this.stateMirror = null;
    this.provider = null;
  }

  resolveWalletKey(walletSource) {
    if (walletSource === 'deployer') return this.config.deployerKey || this.config.ownerKey;
    if (walletSource === 'owner') return this.config.ownerKey;
    if (walletSource.startsWith('player:')) {
      const idx = parseInt(walletSource.split(':')[1], 10);
      return this.config.playerKeys[idx];
    }
    throw new Error(`Unknown wallet source: ${walletSource}`);
  }

  async start() {
    const cfg = this.config;
    console.log('=== Degenerus Local Orchestrator ===');
    console.log(`RPC: ${cfg.rpcUrl}`);
    console.log(`Contracts: ${Object.keys(cfg.contracts).length}`);
    console.log(`Mocks: ${Object.keys(cfg.mocks || {}).length}`);

    // Open database
    this.db = openDatabase(cfg.dbPath);
    console.log(`DB: ${cfg.dbPath}`);

    // Create provider
    this.provider = createProvider(cfg.rpcUrl);
    const blockNumber = await this.provider.getBlockNumber();
    console.log(`Chain head: ${blockNumber}`);

    // Load ABIs (protocol + mock contracts)
    const abiOpts = cfg.artifactsBase ? { artifactsBase: cfg.artifactsBase } : {};
    const abis = loadContractAbis(cfg.projectRoot, cfg.contracts, cfg.mocks, abiOpts);

    // Start event logger with ticket tracking callback
    this.eventLogger = await startEventLogger({
      provider: this.provider,
      db: this.db,
      contractAbis: abis,
      startBlock: cfg.startBlock,
      log: console.log,
      batchSize: cfg.eventBatchSize,
      pollInterval: cfg.eventPollInterval,
      onNewEvents: (events) => {
        if (this.stateMirror) {
          const count = this.stateMirror.processTicketEvents(events);
          if (count > 0) {
            console.log(`[ticket-tracker] +${count} ticket entries from ${events.length} events`);
          }
        }
      },
    });

    if (this.loggerOnly) {
      console.log('\n[orchestrator] Logger-only mode. Press Ctrl+C to stop.');
      return;
    }

    // Build player addresses for state mirror
    const playerAddresses = cfg.playerKeys.map(k =>
      new ethers.Wallet(k).address
    );
    // Add owner
    const ownerAddress = new ethers.Wallet(cfg.ownerKey).address;
    const allAddresses = [ownerAddress, ...playerAddresses];

    // Create contract instances for state mirror
    const contracts = {};
    for (const [name, { address, abi }] of abis) {
      contracts[name.toLowerCase()] = new ethers.Contract(address, abi, this.provider);
    }

    // Start state mirror
    this.stateMirror = new StateMirror({
      contracts,
      provider: this.provider,
      db: this.db,
      playerAddresses: allAddresses,
      log: console.log,
      dgnrsAddress: cfg.contracts.DGNRS,
      vaultAddress: cfg.contracts.VAULT,
    });

    this.stateMirror.onStateUpdate = (state) => {
      // Push state to all workers
      for (const worker of this.workers.values()) {
        worker.postMessage({ type: 'STATE_UPDATE', state });
      }
    };

    this.stateMirror.start(
      cfg.intervals.statePoll,
      cfg.intervals.stateDeepPoll
    );

    // Wait for initial state
    await new Promise(r => setTimeout(r, 3000));

    // Spawn actor workers
    const actorConfigs = this.getActorConfigs();
    console.log(`\nSpawning ${actorConfigs.length} actors...`);

    for (const actor of actorConfigs) {
      this.spawnWorker(actor, cfg, abis);
    }

    console.log('\n[orchestrator] All actors running. Press Ctrl+C to stop.');
  }

  getActorConfigs() {
    // Try loading profiles.json for profile-driven actors
    const profilesPath = path.join(this.config.projectRoot, 'profiles.json');
    if (fs.existsSync(profilesPath)) {
      const profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
      console.log(`[orchestrator] Loaded ${profiles.length} profiles from profiles.json`);

      // Always include advancer as first actor
      const actors = [
        { name: 'advancer', strategy: 'advancer', walletSource: 'deployer', interval: 5_000 },
      ];

      // Map each profile to an actor config
      for (let i = 0; i < profiles.length; i++) {
        const p = profiles[i];
        if (i >= this.config.playerKeys.length) {
          console.warn(`[orchestrator] Profile ${p.name} skipped: only ${this.config.playerKeys.length} wallets available`);
          break;
        }
        actors.push({
          name: p.name,
          strategy: 'profile',
          walletSource: `player:${i}`,
          interval: p.timing?.intervalMs || [10_000, 20_000],
          profile: p,
        });
      }

      if (this.actorFilter) {
        return actors.filter(a =>
          this.actorFilter.includes(a.name) || this.actorFilter.includes(a.strategy) ||
          this.actorFilter.includes(a.name.split('-').slice(0, -1).join('-'))
        );
      }
      return actors;
    }

    // Fallback: default actors
    let actors = DEFAULT_ACTORS;
    if (this.actorFilter) {
      actors = actors.filter(a =>
        this.actorFilter.includes(a.name) || this.actorFilter.includes(a.strategy)
      );
    }
    return actors;
  }

  resolveInterval(actor, cfg) {
    // Use config intervals when available (local mode has faster intervals)
    const strategyKey = (actor.strategy === 'advancer' || actor.strategy === 'advancer-sepolia') ? 'advancer'
      : actor.strategy === 'burner' ? 'burner'
      : actor.strategy === 'flipper' ? 'flipper'
      : actor.strategy === 'claimer' ? 'claimer'
      : 'buyer'; // all buyer variants use 'buyer' interval
    return cfg.intervals[strategyKey] || actor.interval;
  }

  spawnWorker(actor, cfg, abis) {
    const walletKey = this.resolveWalletKey(actor.walletSource);
    const workerPath = path.join(__dirname, 'actor-worker.js');

    const workerData = {
      strategyName: actor.strategy,
      walletKey,
      rpcUrl: cfg.rpcUrl,
      projectRoot: cfg.projectRoot,
      contracts: cfg.contracts,
      mocks: cfg.mocks || {},
      gameAddress: cfg.contracts.GAME,
      intervalMs: this.resolveInterval(actor, cfg),
      artifactsBase: cfg.artifactsBase || null,
    };

    // Advancer-sepolia needs mock stETH address for rebase
    if (actor.strategy === 'advancer-sepolia') {
      workerData.stethAddress = cfg.mocks?.STETH_TOKEN || null;
    }

    // Claimer needs all wallet keys
    if (actor.strategy === 'claimer') {
      workerData.allWalletKeys = [cfg.ownerKey, ...cfg.playerKeys];
    }

    // Profile strategy needs profile data
    if (actor.profile) {
      workerData.profile = actor.profile;
    }

    const worker = new Worker(workerPath, { workerData });

    worker.on('message', (msg) => {
      if (msg.type === 'LOG') {
        console.log(`  ${msg.msg}`);
      } else if (msg.type === 'ACTION_RESULT') {
        logActorAction(this.db, {
          actorName: actor.name,
          action: msg.action,
          txHash: msg.txHash,
          success: msg.success,
          gasUsed: msg.gasUsed,
          errorMsg: msg.error || null,
        });
      }
    });

    worker.on('error', (err) => {
      console.error(`[${actor.name}] Worker error: ${err.message}`);
    });

    worker.on('exit', (code) => {
      console.log(`[${actor.name}] Worker exited with code ${code}`);
      this.workers.delete(actor.name);
    });

    this.workers.set(actor.name, worker);
    const addr = new ethers.Wallet(walletKey).address;
    console.log(`  ${actor.name} (${actor.strategy}) → ${addr.slice(0, 10)}...`);
  }

  async stop() {
    console.log('\n[orchestrator] Shutting down...');

    // Stop workers
    for (const [name, worker] of this.workers) {
      worker.postMessage({ type: 'SHUTDOWN' });
    }
    // Give workers a moment to clean up
    await new Promise(r => setTimeout(r, 1000));
    for (const worker of this.workers.values()) {
      worker.terminate();
    }
    this.workers.clear();

    // Stop state mirror
    if (this.stateMirror) this.stateMirror.stop();

    // Stop event logger
    if (this.eventLogger) this.eventLogger.stop();

    // Close DB
    if (this.db) this.db.close();

    // Destroy provider
    if (this.provider) this.provider.destroy();

    console.log('[orchestrator] Stopped.');
  }
}
