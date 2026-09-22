// Run from degenerus-audit: node scripts/check-entry-reveal-decoder.mjs
// Exercises the website's actual shipped browser bundle, not a substitute decoder.
import assert from 'node:assert/strict';
import { Interface, toBeHex, zeroPadValue, version } from '../../website/app/vendor/ethers-app.mjs';

const fragment = {
  type: 'event', name: 'EntryTraitsRevealed', anonymous: true,
  inputs: [
    ...[0, 1, 2, 3].map(i => ({ name: `player${i}`, type: 'uint256', indexed: true })),
    { name: 'entries', type: 'uint144', indexed: false },
  ],
};
const iface = new Interface([fragment]);
const key = (level, player) => (BigInt(level) << 160n) | BigInt(player);
for (let count = 1; count <= 4; count++) {
  const players = [0, 1, 2, 3].map(i => i < count ? key(73, 0x1234 + i) : 0n);
  // Include valid trait zero and a partial player: presence, not trait value,
  // determines whether a byte contributes an entry.
  const packed = (BigInt((1 << (count * 4)) - 1) << 128n) | 0xc0804000n;
  const encoded = iface.encodeEventLog('EntryTraitsRevealed', [...players, packed]);
  assert.equal(encoded.topics.length, 4);
  assert.equal((encoded.data.length - 2) / 2, 32);
  assert.equal(iface.parseLog(encoded), null, 'automatic topic0 discovery must not be used');
  const decoded = iface.decodeEventLog('EntryTraitsRevealed', encoded.data, encoded.topics);
  assert.deepEqual(Array.from(decoded), [...players, packed]);
  for (let position = 0; position < count; position++) {
    const args = Array.from({ length: 4 }, (_, i) => i === position ? players[i] : null);
    const topics = iface.encodeFilterTopics('EntryTraitsRevealed', args);
    assert.equal(topics[position], zeroPadValue(toBeHex(players[position]), 32));
    assert.equal(encoded.topics[position], topics[position]);
  }
}
console.log(`PASS: browser ethers ${version}; anonymous JSON ABI; explicit decode; all four filter positions; zero trailing topics.`);
