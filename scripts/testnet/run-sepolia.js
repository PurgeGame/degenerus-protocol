#!/usr/bin/env node
/**
 * Sepolia testnet runner: connects to existing Sepolia deployment,
 * bootstraps the game, then runs the orchestrator with actors.
 *
 * Uses MockVRFCoordinator for instant VRF fulfillment.
 * Uses advanceDay() (CREATOR-only) instead of evm_increaseTime.
 *
 * Prerequisites:
 *   1. Deploy via: TESTNET_BUILD=1 npx hardhat run scripts/deploy-sepolia-testnet.js --network sepolia
 *   2. Fund deployer wallet with Sepolia ETH + LINK (https://faucets.chain.link/sepolia)
 *      (VRF subscription is auto-funded from deployer's LINK during bootstrap)
 *   3. Fund player wallets with Sepolia ETH
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

// Target LINK balance for VRF subscription
const VRF_TARGET_LINK = ethers.parseEther('50');

/**
 * Check VRF subscription LINK balance and top up to VRF_TARGET_LINK if needed.
 * Scans deployer + all player wallets for LINK, funds from whichever has enough.
 * Fails fast with clear instructions if no wallet has LINK.
 */
async function ensureVrfFunded(wallet, cfg, log) {
  // Skip LINK funding when using MockVRFCoordinator (mock doesn't need LINK)
  if (cfg.mocks?.VRF_COORDINATOR) {
    log('Mock VRF detected — skipping LINK funding');
    return;
  }

  const provider = wallet.provider;
  const adminAddr = cfg.contracts.ADMIN;
  const vrfCoordAddr = cfg.external.VRF_COORDINATOR;
  const linkAddr = cfg.external.LINK_TOKEN;

  const admin = new ethers.Contract(adminAddr, [
    'function subscriptionId() view returns (uint256)',
  ], provider);

  const vrfCoord = new ethers.Contract(vrfCoordAddr, [
    'function getSubscription(uint256 subId) view returns (uint96 balance, uint96 nativeBalance, uint64 reqCount, address subOwner, address[] consumers)',
  ], provider);

  const linkReadOnly = new ethers.Contract(linkAddr, [
    'function balanceOf(address) view returns (uint256)',
    'function transferAndCall(address to, uint256 value, bytes data) returns (bool)',
  ], provider);

  // Read subscription ID from Admin
  const subId = await admin.subscriptionId();
  if (subId === 0n) {
    throw new Error('Admin.subscriptionId() is 0 — VRF not wired. Redeploy or check Admin constructor.');
  }
  log(`VRF subscription ID: ${subId}`);

  // Check subscription LINK balance
  const sub = await vrfCoord.getSubscription(subId);
  const subLinkBalance = BigInt(sub[0]);
  log(`VRF subscription LINK balance: ${ethers.formatEther(subLinkBalance)} LINK`);

  if (subLinkBalance >= VRF_TARGET_LINK) {
    log('VRF subscription is funded — proceeding');
    return;
  }

  const needed = VRF_TARGET_LINK - subLinkBalance;
  log(`VRF subscription needs ${ethers.formatEther(needed)} more LINK to reach ${ethers.formatEther(VRF_TARGET_LINK)} target`);

  // Scan all available wallets for LINK: deployer first, then players
  const allKeys = [cfg.ownerKey, ...(cfg.playerKeys || [])].filter(Boolean);
  const walletBalances = await Promise.all(
    allKeys.map(async (key) => {
      const w = new ethers.Wallet(key, provider);
      const bal = await linkReadOnly.balanceOf(w.address);
      return { key, address: w.address, balance: bal };
    })
  );

  log('LINK balances across wallets:');
  for (const wb of walletBalances) {
    if (wb.balance > 0n) {
      log(`  ${wb.address.slice(0, 10)}... ${ethers.formatEther(wb.balance)} LINK`);
    }
  }

  // Fund from wallets until we've sent enough, preferring wallets with the most LINK
  walletBalances.sort((a, b) => (b.balance > a.balance ? 1 : b.balance < a.balance ? -1 : 0));

  let remaining = needed;
  for (const wb of walletBalances) {
    if (remaining <= 0n) break;
    if (wb.balance === 0n) continue;

    const sendAmount = wb.balance >= remaining ? remaining : wb.balance;
    const signer = new ethers.Wallet(wb.key, provider);
    const linkSigned = linkReadOnly.connect(signer);

    log(`Funding ${ethers.formatEther(sendAmount)} LINK from ${wb.address.slice(0, 10)}...`);
    const tx = await linkSigned.transferAndCall(adminAddr, sendAmount, '0x');
    const receipt = await tx.wait();
    log(`  OK (tx: ${receipt.hash.slice(0, 14)}... gas: ${receipt.gasUsed})`);

    remaining -= sendAmount;
  }

  if (remaining > 0n) {
    const funded = needed - remaining;
    console.warn('\n' + '='.repeat(70));
    console.warn(`  WARNING: VRF subscription underfunded — sent ${ethers.formatEther(funded)} of ${ethers.formatEther(needed)} LINK needed.`);
    console.warn(`  The run will proceed but may stall when LINK runs out.`);
    console.warn('');
    console.warn('  To add more LINK while the run is active:');
    console.warn(`    LINK.transferAndCall(${adminAddr}, amount, "0x")`);
    console.warn('  Or get LINK from https://faucets.chain.link/sepolia');
    console.warn('='.repeat(70) + '\n');
  }

  // Verify
  const subAfter = await vrfCoord.getSubscription(subId);
  log(`VRF subscription LINK balance after funding: ${ethers.formatEther(subAfter[0])} LINK`);
}

/**
 * Bootstrap circular affiliate codes for adversarial attack actors.
 * Registers affiliate codes and cross-refers the two attack wallets.
 * Gracefully skips if profiles don't include attack-affiliate-* actors.
 */
async function bootstrapAdversarialAffiliates(wallet, cfg, log) {
  const profilesPath = path.join(PROJECT_ROOT, 'profiles.json');
  if (!fs.existsSync(profilesPath)) return;

  const profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
  const loopIdx = profiles.findIndex(p => p.name === 'attack-affiliate-loop');
  const partnerIdx = profiles.findIndex(p => p.name === 'attack-affiliate-partner');
  if (loopIdx === -1 || partnerIdx === -1) return;

  const playerKeys = cfg.playerKeys || [];
  if (loopIdx >= playerKeys.length || partnerIdx >= playerKeys.length) {
    log('Skipping affiliate bootstrap: not enough player wallets for attack actors');
    return;
  }

  log('Bootstrapping adversarial affiliate codes...');
  const provider = wallet.provider;
  const affiliateAddr = cfg.contracts.AFFILIATE;
  const affiliateAbi = [
    'function createAffiliateCode(bytes32 code_, uint8 rakebackPct) external',
    'function referPlayer(bytes32 code_) external',
  ];

  const loopWallet = new ethers.Wallet(playerKeys[loopIdx], provider);
  const partnerWallet = new ethers.Wallet(playerKeys[partnerIdx], provider);
  const loopAffiliate = new ethers.Contract(affiliateAddr, affiliateAbi, loopWallet);
  const partnerAffiliate = new ethers.Contract(affiliateAddr, affiliateAbi, partnerWallet);

  const loopCode = ethers.encodeBytes32String('LOOP');
  const partnerCode = ethers.encodeBytes32String('PARTNER');

  // Register affiliate codes (25% max rakeback for maximum reward extraction)
  try {
    const tx1 = await loopAffiliate.createAffiliateCode(loopCode, 25);
    await tx1.wait();
    log(`  ${loopWallet.address.slice(0, 10)}... registered code LOOP`);
  } catch (e) {
    log(`  LOOP code: ${e.reason || e.shortMessage || 'already registered'}`);
  }

  try {
    const tx2 = await partnerAffiliate.createAffiliateCode(partnerCode, 25);
    await tx2.wait();
    log(`  ${partnerWallet.address.slice(0, 10)}... registered code PARTNER`);
  } catch (e) {
    log(`  PARTNER code: ${e.reason || e.shortMessage || 'already registered'}`);
  }

  // Cross-refer: loop refers under PARTNER, partner refers under LOOP
  try {
    const tx3 = await loopAffiliate.referPlayer(partnerCode);
    await tx3.wait();
    log(`  loop → referred under PARTNER`);
  } catch (e) {
    log(`  loop referral: ${e.reason || e.shortMessage || 'already referred'}`);
  }

  try {
    const tx4 = await partnerAffiliate.referPlayer(loopCode);
    await tx4.wait();
    log(`  partner → referred under LOOP`);
  } catch (e) {
    log(`  partner referral: ${e.reason || e.shortMessage || 'already referred'}`);
  }

  log('Affiliate bootstrap complete');
}

/**
 * Scan player wallet ETH balances and warn about underfunded wallets.
 */
async function scanPlayerBalances(cfg, log) {
  const profilesPath = path.join(PROJECT_ROOT, 'profiles.json');
  if (!fs.existsSync(profilesPath)) return;

  const profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
  const playerKeys = cfg.playerKeys || [];
  const count = Math.min(profiles.length, playerKeys.length);
  if (count === 0) return;

  log(`Scanning ${count} player wallet balances...`);
  const provider = new ethers.JsonRpcProvider(cfg.rpcUrl, undefined, { staticNetwork: true });

  const MIN_ETH = ethers.parseEther('0.001');
  let funded = 0;
  let dry = 0;

  // Batch balance checks (5 at a time to avoid rate limits)
  for (let i = 0; i < count; i += 5) {
    const batch = [];
    for (let j = i; j < Math.min(i + 5, count); j++) {
      const addr = new ethers.Wallet(playerKeys[j]).address;
      batch.push(provider.getBalance(addr).then(bal => ({ idx: j, addr, bal, name: profiles[j].name })));
    }
    const results = await Promise.all(batch);
    for (const { idx, addr, bal, name } of results) {
      if (bal < MIN_ETH) {
        log(`  WARNING: ${name} (${addr.slice(0, 10)}...) has ${ethers.formatEther(bal)} ETH — may fail`);
        dry++;
      } else {
        funded++;
      }
    }
  }

  log(`  ${funded} wallets funded, ${dry} wallets low/empty`);
  provider.destroy();
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
  const useMockVrf = !!cfg.mocks?.VRF_COORDINATOR;
  log(`Bootstrapping game state (${useMockVrf ? 'mock VRF — instant' : 'real VRF — this may take a minute'})...`);

  const ownerKey = cfg.ownerKey;
  if (!ownerKey) {
    throw new Error('No owner key. Set DEPLOYER_PRIVATE_KEY in .env or ownerPrivateKey in wallets.json');
  }

  const { provider, wallet, contracts } = createGameClient(cfg, ownerKey);

  // --- VRF subscription funding check ---
  await ensureVrfFunded(wallet, cfg, log);

  // --- Affiliate bootstrap for adversarial actors ---
  await bootstrapAdversarialAffiliates(wallet, cfg, log);

  // --- Player wallet ETH balance scan ---
  await scanPlayerBalances(cfg, log);

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

    // Fulfill VRF: mock or wait for Chainlink
    if (useMockVrf) {
      try {
        const vrfCoord = new ethers.Contract(cfg.mocks.VRF_COORDINATOR, [
          'function lastRequestId() view returns (uint256)',
          'function fulfillRandomWords(uint256 requestId, uint256 randomWord) external',
        ], wallet);
        const requestId = await vrfCoord.lastRequestId();
        if (requestId > 0n) {
          const randomWord = BigInt(ethers.hexlify(ethers.randomBytes(32)));
          const tx = await vrfCoord.fulfillRandomWords(requestId, randomWord, { gasLimit: 500_000 });
          await tx.wait();
          log(`  Mock VRF fulfilled #${requestId}`);
        }
      } catch (e) {
        log(`  Mock VRF fulfill: ${e.reason || e.shortMessage || e.message}`);
      }
    } else {
      log('  Waiting for Chainlink VRF fulfillment...');
      await new Promise(r => setTimeout(r, 12_000));
    }
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
    super({ ...opts, config: sepoliaCfg });
  }

  getActorConfigs() {
    // Try loading profiles.json for profile-driven actors (same as base Orchestrator)
    const profilesPath = path.join(this.config.projectRoot, 'profiles.json');
    if (fs.existsSync(profilesPath)) {
      const profiles = JSON.parse(fs.readFileSync(profilesPath, 'utf8'));
      log(`Loaded ${profiles.length} profiles from profiles.json`);

      // Testnet D-scaling: contract divides all ETH values by 1M.
      // Scale down profile budgets and pass divisor so strategy can scale hardcoded prices.
      const D = 1_000_000;
      for (const p of profiles) {
        p._testnetDivisor = D;
        if (p.budget) {
          if (p.budget.ethPerDay) p.budget.ethPerDay = p.budget.ethPerDay / D;
          if (p.budget.maxEthPerLevel) p.budget.maxEthPerLevel = p.budget.maxEthPerLevel / D;
        }
      }
      log(`Applied testnet D-scaling (1/${D}) to all profile budgets`);

      // Advancer-sepolia as the game clock (uses deployer wallet)
      const actors = [
        { name: 'advancer-sepolia', strategy: 'advancer-sepolia', walletSource: 'deployer', interval: 6_000 },
      ];

      // Map each profile to a player wallet
      const maxPlayers = this.config.playerKeys.length;
      for (let i = 0; i < profiles.length; i++) {
        if (i >= maxPlayers) {
          log(`Profile ${profiles[i].name} skipped: only ${maxPlayers} player wallets available`);
          break;
        }
        actors.push({
          name: profiles[i].name,
          strategy: 'profile',
          walletSource: `player:${i}`,
          interval: profiles[i].timing?.intervalMs || [8_000, 15_000],
          profile: profiles[i],
        });
      }

      // Trim playerKeys to only those used (avoid polling unused wallets on rate-limited RPC)
      const usedPlayerCount = Math.min(profiles.length, maxPlayers);
      this.config.playerKeys = this.config.playerKeys.slice(0, usedPlayerCount);

      if (actorFilter) {
        return actors.filter(a =>
          actorFilter.includes(a.name) || actorFilter.includes(a.strategy)
        );
      }
      return actors;
    }

    // Fallback: hardcoded actor layout
    log('No profiles.json found — using default Sepolia actors');
    // Limit player keys to those used by default actors
    const maxPlayerIdx = Math.max(...SEPOLIA_DEFAULT_ACTORS
      .filter(a => a.walletSource.startsWith('player:'))
      .map(a => parseInt(a.walletSource.split(':')[1], 10)));
    this.config.playerKeys = this.config.playerKeys.slice(0, maxPlayerIdx + 1);

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
