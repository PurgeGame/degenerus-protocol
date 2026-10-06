import { expect } from 'chai';
import hre from 'hardhat';
import { execFileSync } from 'node:child_process';

describe('Shared Degenerette payout and activity invariants', function () {
  let h;
  let m;
  before(async function () {
    h = await (await hre.ethers.getContractFactory('DegeneretteMathHarness')).deploy();
    m = JSON.parse(execFileSync('python3', ['-B', 'scripts/data/degenerette_single_symbol_math.py'], { encoding: 'utf8' }));
  });
  it('uses the agreed table and ETH additions in the deployed production math', async function () {
    const base = [0, 0, 0, 50, 300, 1000, 10000, 62500, 1817328, 23000000];
    const add = [0, 0, 0, 0, 0, 0, 240, 4600, 105000, 22408400];
    for (let s = 0; s < 10; s++) {
      expect(await h.base(s)).to.equal(base[s]);
      expect(await h.ethAdd(s)).to.equal(add[s]);
    }
  });
  it('retains all activity knees', async function () {
    for (const [score, bps] of [[0, 9000], [305, 9891], [500, 9970], [30000, 9990], [65535, 9990]]) expect(await h.roi(score)).to.equal(bps);
  });
  it('keeps WWXRP low-tier payouts flat and puts activity bonuses only on scores 6-9', async function () {
    for (let s = 0; s < 10; s++) for (let w = 0; w < 5; w++) {
      const low = await h.payout(s, w, 3, 10n ** 18n, 0);
      const high = await h.payout(s, w, 3, 10n ** 18n, 30000);
      if (s < 6) expect(high).to.equal(low);
      else expect(high).to.be.above(low);
    }
  });
  it('matches the exact rigged score/wild EV through the compiled payout path', async function () {
    const denominator = BigInt(m.wwxrp.probability_denominator);
    for (const row of m.activity_returns_percent) {
      let total = 0n;
      for (const [score, wilds, weight] of m.wwxrp.score_wild_weights) {
        total += BigInt(weight) * await h.payout(score, wilds, 3, 10n ** 18n, row.activity_score);
      }
      const percent = Number(total) * 100 / Number(denominator * 10n ** 18n);
      expect(percent).to.be.closeTo(row.WWXRP, 1e-10);
      expect(percent).to.be.closeTo(row.WWXRP_target, 0.00002);
    }
  });
  it('preserves ordinary and ETH return targets through the compiled payout path', async function () {
    const denominator = BigInt(m.ordinary.probability_denominator);
    for (const row of m.activity_returns_percent) {
      for (const [currency, target] of [[1, row.ordinary], [0, row.ETH]]) {
        let total = 0n;
        for (const [score, wilds, weight] of m.ordinary.score_wild_weights) {
          total += BigInt(weight) * await h.payout(score, wilds, currency, 10n ** 18n, row.activity_score);
        }
        const percent = Number(total) * 100 / Number(denominator * 10n ** 18n);
        expect(percent).to.be.closeTo(target, 1e-10);
      }
    }
  });
});
