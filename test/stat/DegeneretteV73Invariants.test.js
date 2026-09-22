import { expect } from 'chai';
import hre from 'hardhat';
import { execFileSync } from 'node:child_process';

describe('Shared Degenerette payout and activity invariants', function () {
  let h;
  before(async function () { h = await (await hre.ethers.getContractFactory('DegeneretteMathHarness')).deploy(); });
  it('uses the agreed table in the deployed production math', async function () {
    const values = [0, 0, 50, 300, 1000, 2500, 12500, 62500, 2347036, 10000000];
    for (let s=0;s<10;s++) expect(await h.base(s)).to.equal(values[s]);
  });
  it('retains all activity knees', async function () {
    for (const [score,bps] of [[0,9000],[305,9891],[500,9970],[30000,9990],[65535,9990]]) expect(await h.roi(score)).to.equal(bps);
  });
  it('keeps WWXRP low-tier payouts flat and puts activity bonuses only on scores 6-9', async function () {
    for (let s=0;s<10;s++) for (let g=0;g<5;g++) {
      const low = await h.payout(s,g,3,10n**18n,0);
      const high = await h.payout(s,g,3,10n**18n,30000);
      if (s<6) expect(high).to.equal(low);
      else expect(high).to.be.above(low);
    }
  });
  it('matches the exact rigged score/gold EV through the compiled payout path', async function () {
    const m = JSON.parse(execFileSync('python3',['-B','scripts/data/degenerette_single_symbol_math.py'],{encoding:'utf8'}));
    const denominator = BigInt(m.wwxrp.probability_denominator);
    for (const row of m.activity_returns_percent) {
      let total = 0n;
      for (const [score,gold,weight] of m.wwxrp.score_gold_weights) {
        total += BigInt(weight)*await h.payout(score,gold,3,10n**18n,row.activity_score);
      }
      const percent = Number(total)*100/Number(denominator*10n**18n);
      expect(percent).to.be.closeTo(row.WWXRP, 1e-10);
      expect(percent).to.be.closeTo(row.WWXRP_target, 0.00002);
    }
  });
});
