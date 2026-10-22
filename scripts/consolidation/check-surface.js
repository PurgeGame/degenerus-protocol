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
assert.deepEqual(b, a, 'Game selectors, payability or return encodings changed');
