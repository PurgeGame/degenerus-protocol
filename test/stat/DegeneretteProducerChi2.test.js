import { expect } from 'chai';
import hre from 'hardhat';

describe('Degenerette uniform producer exhaustive color/symbol support', function () {
  let h;
  before(async function () { h = await (await hre.ethers.getContractFactory('DegeneretteMathHarness')).deploy(); });
  it('each of 64 color/symbol combinations has equal bit-slice support in every quadrant', async function () {
    const counts = Array.from({length:4},()=>Array(8).fill(0));
    for (let c=0;c<8;c++) for (let s=0;s<8;s++) {
      const lane = BigInt(c) | (BigInt(s)<<32n);
      const ticket = await h.traits(lane | (lane<<64n) | (lane<<128n) | (lane<<192n));
      for (let q=0;q<4;q++) {
        const value = Number((ticket>>BigInt(q*8))&255n);
        expect(value).to.equal((q<<6)|(c<<3)|s);
        counts[q][(value>>3)&7]++;
      }
    }
    for (const row of counts) expect(row).to.deep.equal(Array(8).fill(8));
  });
  it('choosing a hero fixes only its symbol, with zero a real pick and 32 internal random sentinel', async function () {
    for (let symbol=0;symbol<32;symbol++) {
      const t = await h.ticket(123456n,symbol);
      expect(Number((t>>BigInt((symbol>>3)*8))&7n)).to.equal(symbol&7);
      expect(await h.hero(123456n,symbol)).to.equal(symbol);
    }
    expect(await h.hero(123456n,32)).to.be.lessThan(32n);
    await expect(h.ticket(123456n,32)).to.be.revertedWithCustomError(h,'InvalidBet');
  });
});
