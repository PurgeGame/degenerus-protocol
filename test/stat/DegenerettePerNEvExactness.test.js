import { expect } from 'chai';
import { execFileSync } from 'node:child_process';

export function model() {
  return JSON.parse(execFileSync('python3', ['-B', 'scripts/data/degenerette_single_symbol_math.py'], { encoding: 'utf8' }));
}

describe('Single-symbol exact EV (production constants)', function () {
  const m = model();
  it('joint score/gold enumeration agrees with independent binomial math and contract constants', function () {
    expect(m.checks).to.include('PASS: contract constants');
    expect(m.base_ev_percent).to.be.at.most(100).and.above(99.99999);
  });
  it('preserves the complete nine-point jackpot probability', function () {
    expect(m.score_table[9].one_in).to.equal(16777216);
    expect(m.score_table[9].rig5_probability_percent).to.equal(m.score_table[9].probability_percent);
  });
  it('has the same paying-score probability under the rig, but improves high tiers', function () {
    expect(m.paying_score_percent).to.be.closeTo(31.2782168388, 1e-8);
    expect(m.rig_rates[1].score_at_least_6_percent).to.be.above(m.rig_rates[0].score_at_least_6_percent);
    expect(m.rig_rates[1].base_ev_percent).to.be.closeTo(119.8649020060897, 1e-8);
  });
});
