// Fresh production artifacts, including actual ABI-encoded constructor arguments.
// --arguments accepts a JSON object keyed by deployment key (for nonempty bootstrap/options).
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { Interface, keccak256 } from 'ethers';
import { DEPLOYMENTS } from './lib/deploymentManifest.js';
const argv = process.argv.slice(2);
function option(flag, fallback) {
  const i = argv.indexOf(flag);
  if (i < 0) return fallback;
  if (!argv[i + 1] || argv[i + 1].startsWith('--')) throw new Error(`Missing ${flag} value`);
  return argv.splice(i, 2)[1];
}
const schedule = option('--schedule', 'eip170');
const file = option('--arguments', null);
const limits = { eip170: [24576, 49152], osaka: [24576, 49152], glamsterdam: [65536, 131072] }[schedule];
if (!limits) throw new Error(`Unknown schedule: ${schedule}`);
if (argv.length > 1 || argv.some(s => s.startsWith('--'))) throw new Error('Unexpected arguments');
const out = argv[0] || process.env.FOUNDRY_OUT || 'forge-out';
const overrides = file ? JSON.parse(fs.readFileSync(file)) : {};
const entries = [...DEPLOYMENTS.map(row => ({ ...row, args: row.key === 'ICONS_32' ? [false] : row.bootstrap ? [[], [], [], [], []] : [] })),
  { key: 'DGVF', contract: 'DegenerusVaultShare', source: 'DegenerusVault', args: ['Degenerus Vault Flip', 'DGVF', 'dgvf.degenerus.eth'] },
  { key: 'DGVE', contract: 'DegenerusVaultShare', source: 'DegenerusVault', args: ['Degenerus Vault Eth', 'DGVE', 'dgve.degenerus.eth'] },
  { key: 'GAME_LENS', contract: 'DegenerusGameLens', args: [] },
  { key: 'CRAPS_LENS', contract: 'CrapsLens', args: [] }];
for (const key of Object.keys(overrides)) if (!entries.some(e => e.key === key)) throw new Error(`Unknown constructor key: ${key}`);
const sourceHashes = new Map(), rows = [];
for (const entry of entries) {
  const name = entry.contract;
  const artifact = JSON.parse(fs.readFileSync(path.join(out, `${entry.source || name}.sol`, `${name}.json`)));
  const metadata = typeof artifact.metadata === 'string' ? JSON.parse(artifact.metadata) : artifact.metadata;
  if (!metadata?.sources) throw new Error(`${name}: source metadata missing`);
  for (const [file, expected] of Object.entries(metadata.sources)) {
    if (!sourceHashes.has(file)) {
      const sourcePath = fs.existsSync(file) ? file : path.join('node_modules', file);
      sourceHashes.set(file, keccak256(fs.readFileSync(sourcePath)));
    }
    if (sourceHashes.get(file) !== expected.keccak256) throw new Error(`${name}: stale source ${file}`);
  }
  function bytes(value) {
    const hex = value?.replace(/^0x/, '');
    if (!hex || !/^(?:[0-9a-fA-F]{2})+$/.test(hex)) throw new Error(`${name}: missing/unlinked bytecode`);
    return hex.length / 2;
  }
  const args = overrides[entry.key] ?? entry.args;
  const encoded = new Interface(artifact.abi).encodeDeploy(args);
  const runtime = bytes(artifact.deployedBytecode.object);
  const initcode = bytes(artifact.bytecode.object) + (encoded.length - 2) / 2;
  rows.push({ key: entry.key, contract: name, runtime_bytes: runtime, initcode_bytes: initcode,
    constructor_arguments: args, runtime_remaining: limits[0] - runtime, initcode_remaining: limits[1] - initcode });
}
const guard = spawnSync('python3', [fileURLToPath(new URL('./check-memory-guard.py', import.meta.url)), out, '--json'], { encoding: 'utf8' });
if (guard.error) throw guard.error;
if (guard.signal || !guard.stdout) throw new Error(`Memory guard failed: ${guard.stderr || guard.signal}`);
const memoryGuard = JSON.parse(guard.stdout);
console.log(JSON.stringify({ schedule, limits: { runtime: limits[0], initcode: limits[1] }, rows, memory_guard: memoryGuard }, null, 2));
if (guard.status !== 0) process.exitCode = 1;
if (rows.some(row => row.runtime_remaining < 0 || row.initcode_remaining < 0)) process.exitCode = 1;
