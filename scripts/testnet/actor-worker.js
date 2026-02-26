import { workerData, parentPort } from 'node:worker_threads';
import { ethers } from 'ethers';
import { loadContractAbis } from './lib/abi-loader.js';
import { createProvider } from './lib/game-client.js';
import { AdvancerStrategy } from './strategies/advancer.js';
import { AdvancerSepoliaStrategy } from './strategies/advancer-sepolia.js';
import { BuyerStrategy } from './strategies/buyer.js';
import { BurnerStrategy } from './strategies/burner.js';
import { FlipperStrategy, ClaimerStrategy } from './strategies/flipper.js';
import { WhaleBuyerStrategy } from './strategies/whale-buyer.js';
import { DeityBuyerStrategy } from './strategies/deity-buyer.js';
import { TargetBuyerStrategy } from './strategies/target-buyer.js';
import { ProfileStrategy } from './strategies/profile-strategy.js';

const STRATEGY_MAP = {
  advancer: AdvancerStrategy,
  'advancer-sepolia': AdvancerSepoliaStrategy,
  buyer: BuyerStrategy,
  burner: BurnerStrategy,
  flipper: FlipperStrategy,
  claimer: ClaimerStrategy,
  'whale-buyer': WhaleBuyerStrategy,
  'deity-buyer': DeityBuyerStrategy,
  'target-buyer': TargetBuyerStrategy,
  profile: ProfileStrategy,
};

function log(...args) {
  const msg = args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a)).join(' ');
  parentPort.postMessage({ type: 'LOG', msg });
}

async function run() {
  const { strategyName, walletKey, allWalletKeys, rpcUrl, projectRoot,
    contracts: deployedContracts, mocks: mockContracts,
    gameAddress, intervalMs, artifactsBase } = workerData;

  // Create isolated provider + wallet
  const provider = createProvider(rpcUrl);
  const wallet = new ethers.Wallet(walletKey, provider);
  const abiOpts = artifactsBase ? { artifactsBase } : {};
  const abis = loadContractAbis(projectRoot, deployedContracts, mockContracts, abiOpts);

  // Create contracts with this worker's wallet as default signer
  const contractInstances = {};
  for (const [name, { address, abi }] of abis) {
    contractInstances[name.toLowerCase()] = new ethers.Contract(address, abi, wallet);
  }

  // Build allWallets for claimer
  let allWallets = [];
  if (allWalletKeys) {
    allWallets = allWalletKeys.map(k => new ethers.Wallet(k, provider));
  }

  const StrategyClass = STRATEGY_MAP[strategyName];
  if (!StrategyClass) {
    log(`Unknown strategy: ${strategyName}`);
    process.exit(1);
  }

  const strategy = new StrategyClass({
    wallet,
    contracts: contractInstances,
    provider,
    config: {},
    log,
    gameAddress,
    stethAddress: workerData.stethAddress || null,
    allWallets,
    profile: workerData.profile || null,
    name: workerData.profile?.name || `${strategyName}-${wallet.address.slice(2, 6)}`,
  });

  log(`Worker started: ${strategyName} wallet=${wallet.address}`);

  // Listen for state updates from orchestrator
  let state = null;
  parentPort.on('message', (msg) => {
    if (msg.type === 'STATE_UPDATE') {
      state = msg.state;
      strategy.updateState(state);
    } else if (msg.type === 'SHUTDOWN') {
      log('Shutdown received');
      provider.destroy();
      process.exit(0);
    }
  });

  // Tick loop
  const [minInterval, maxInterval] = Array.isArray(intervalMs)
    ? intervalMs : [intervalMs, intervalMs];

  while (true) {
    try {
      if (state) {
        await strategy.tick();
        parentPort.postMessage({
          type: 'TICK',
          strategyName,
          wallet: wallet.address,
        });
      }
    } catch (err) {
      log(`Tick error: ${err.message}`);
    }

    const delay = minInterval + Math.random() * (maxInterval - minInterval);
    await new Promise(r => setTimeout(r, delay));
  }
}

run().catch(err => {
  log(`Fatal: ${err.message}`);
  process.exit(1);
});
