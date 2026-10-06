import { expect } from 'chai';
import { execFileSync } from 'node:child_process';

export function model() {
  return JSON.parse(execFileSync('python3', ['-B', 'scripts/data/degenerette_single_symbol_math.py'], { encoding: 'utf8' }));
}

describe('Wild-color exact EV (production constants)', function () {
  const m = model();
  it('joint score/wild enumeration agrees with the independent convolution and contract constants', function () {
    expect(m.checks).to.include('PASS: contract constants');
    expect(m.base_ev_percent).to.be.at.most(100).and.above(99.99999);
  });
  it('never scores zero, and the rig cannot create a jackpot', function () {
    expect(m.score_table[0].probability_percent).to.equal(0);
    expect(m.score_table[9].one_in).to.be.closeTo(11296042.8595, 1e-3);
    expect(m.score_table[9].rig5_probability_percent).to.equal(m.score_table[9].probability_percent);
  });
  it('pays from S3 up and the rig only lifts already-paying scores', function () {
    expect(m.paying_score_percent).to.be.closeTo(30.37435679070768, 1e-10);
    const rigPaying = m.score_table.slice(3).reduce((a, r) => a + r.rig5_probability_percent, 0);
    expect(rigPaying).to.be.closeTo(m.paying_score_percent, 1e-9);
    expect(m.score_table[8].rig5_probability_percent).to.be.above(m.score_table[8].probability_percent);
  });
});
