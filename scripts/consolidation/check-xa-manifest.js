import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { getCreateAddress, keccak256, AbiCoder, toUtf8Bytes } from 'ethers';
import fs from 'node:fs';
import { DEPLOYMENTS, expandAliases } from '../lib/deploymentManifest.js';
import { predictAddresses } from '../lib/predictAddresses.js';

const base = process.argv[2] || 'db2004c99eaaaca8c4be1b8a1a1c0f6439a0b9b6';
const source = execFileSync('git', ['show', `${base}:scripts/lib/deploymentManifest.js`], { encoding: 'utf8' });
const prior = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
const deployer = '0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496';
const nonce = 5;
const old = prior.expandAliases(new Map(prior.DEPLOYMENTS.map((row, i) => [row.key,
  getCreateAddress({ from: deployer, nonce: nonce + (row.nonceOffset ?? i) })])));
const candidate = predictAddresses(deployer, nonce);
const changed = [...candidate].filter(([key, value]) => old.get(key) !== value).map(([key]) => key).sort();
assert.deepEqual(changed, ['COINFLIP', 'QUESTS']);
assert.equal(candidate.get('QUESTS'), candidate.get('COINFLIP'));
assert.equal(candidate.get('AFFILIATE'), candidate.get('COINFLIP'));
assert.equal(DEPLOYMENTS.length, prior.DEPLOYMENTS.length - 2);
const physical = new Map(DEPLOYMENTS.map(row => [row.key, candidate.get(row.key)]));
assert.equal(new Set(physical.values()).size, DEPLOYMENTS.length);
assert.deepEqual(expandAliases(physical), candidate);
const occupied = new Set(DEPLOYMENTS.map((row, i) => row.nonceOffset ?? i));
const reserved = Array.from({ length: Math.max(...occupied) + 1 }, (_, i) => i).filter(i => !occupied.has(i));
assert.deepEqual(reserved, [6, 10]);
const namespaces = JSON.parse(fs.readFileSync('scripts/consolidation/xa-namespaces.json'));
for (const [key, value] of Object.entries(namespaces)) {
  const id = `degenerus.storage.${key}.v1`;
  const root = BigInt(keccak256(AbiCoder.defaultAbiCoder().encode(['uint256'], [BigInt(keccak256(toUtf8Bytes(id))) - 1n]))) & ~255n;
  assert.equal(root, BigInt(value.root), `${key} namespace derivation`);
}
console.log(JSON.stringify({ base, physicalDeployments: DEPLOYMENTS.length, reservedNonces: reserved,
  changedAliases: changed, unchangedAddresses: [...candidate.keys()].filter(key => !changed.includes(key)),
  namespaceDerivations: 'PASS', manifestAliases: 'PASS' }, null, 2));
