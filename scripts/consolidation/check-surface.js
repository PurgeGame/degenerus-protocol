import fs from 'node:fs';
import assert from 'node:assert/strict';
import { Interface } from 'ethers';
const [before, after] = process.argv.slice(2);
if (!before || !after) throw new Error('usage: check-surface.js BASELINE_ARTIFACT CANDIDATE_ARTIFACT');
const read = path => JSON.parse(fs.readFileSync(path));
function surface(artifact) {
  return new Interface(artifact.abi).fragments.filter(f => f.type === 'function')
    .map(f => [f.selector, f.format('sighash'), f.stateMutability, f.outputs.map(o => o.format('sighash'))])
    .sort((a, b) => a[0].localeCompare(b[0]));
}
const a = surface(read(before)), b = surface(read(after));
console.log(JSON.stringify({ before: a, after: b, added: b.filter(x => !a.some(y => y[0] === x[0])), removed: a.filter(x => !b.some(y => y[0] === x[0])) }, null, 2));
if (process.argv.includes('--degenesis-gift')) {
  const oldSignature = 'spendDegenesis(bool,uint256,uint256,uint256)';
  const newSignature = 'spendDegenesis(uint32,bool,uint256,uint256,uint256)';
  const removed = a.filter(x => !b.some(y => y[0] === x[0]));
  const added = b.filter(x => !a.some(y => y[0] === x[0]));
  assert.deepEqual(removed.map(x => x[1]), [oldSignature]);
  assert.deepEqual(added.map(x => x[1]), [newSignature]);
  assert.deepEqual(added[0].slice(2), removed[0].slice(2));
  assert.deepEqual(b.filter(x => x[1] !== newSignature), a.filter(x => x[1] !== oldSignature));
} else assert.deepEqual(b, a, 'Game selectors, payability or return encodings changed');
