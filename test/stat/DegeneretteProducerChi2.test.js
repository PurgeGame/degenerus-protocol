import { expect } from 'chai';
import hre from 'hardhat';

describe('Degenerette producers: exhaustive lane support', function () {
  let h;
  before(async function () { h = await (await hre.ethers.getContractFactory('DegeneretteMathHarness')).deploy(); });
  const word = (lane) => lane | (lane << 64n) | (lane << 128n) | (lane << 192n);
  it('ordinary lanes: each of 64 color/symbol combinations, untagged, in every quadrant', async function () {
    const counts = Array.from({ length: 4 }, () => Array(8).fill(0));
    for (let c = 0; c < 8; c++) for (let s = 0; s < 8; s++) {
      const t = await h.ordinaryTraits(word(BigInt(c) | (BigInt(s) << 32n)));
      for (let q = 0; q < 4; q++) {
        const value = Number((t >> BigInt(q * 8)) & 255n);
        expect(value).to.equal((c << 3) | s);
        counts[q][(value >> 3) & 7]++;
      }
    }
    for (const row of counts) expect(row).to.deep.equal(Array(8).fill(8));
  });
  it('house lanes: wild iff the 4-bit wild nibble is zero (1/16), with color bits cleared', async function () {
    for (let n = 0; n < 16; n++) for (const [c, s] of [[0, 0], [5, 3], [7, 7]]) {
      const t = await h.traits(word(BigInt(c) | (BigInt(n) << 3n) | (BigInt(s) << 32n)));
      for (let q = 0; q < 4; q++) {
        const value = Number((t >> BigInt(q * 8)) & 255n);
        expect(value).to.equal(n === 0 ? 0x40 | s : (c << 3) | s);
      }
    }
  });
  it('the player ticket has exactly one wild, at the hero lane, with the hero symbol', async function () {
    for (let symbol = 0; symbol < 24; symbol++) for (const seed of [1n, 123456n, 2n ** 255n + 7n]) {
      const t = await h.ticket(seed, symbol);
      for (let q = 0; q < 4; q++) {
        const value = Number((t >> BigInt(q * 8)) & 255n);
        expect(value & 0x80).to.equal(0);
        if (q === symbol >> 3) expect(value).to.equal(0x40 | (symbol & 7));
        else expect(value & 0x40).to.equal(0);
      }
      expect(await h.hero(seed, symbol)).to.equal(symbol);
    }
    expect(await h.hero(123456n, 32)).to.be.lessThan(24n);
    for (let symbol = 24; symbol < 32; symbol++) {
      await expect(h.hero(123456n, symbol)).to.be.revertedWithCustomError(h, 'InvalidBet');
      await expect(h.ticket(123456n, symbol)).to.be.revertedWithCustomError(h, 'InvalidBet');
    }
    await expect(h.ticket(123456n, 32)).to.be.revertedWithCustomError(h, 'InvalidBet');
  });
});
