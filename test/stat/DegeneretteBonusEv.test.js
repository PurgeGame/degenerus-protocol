import { expect } from 'chai';
import { execFileSync } from 'node:child_process';

describe('Matched-gold and ETH bonus budgets', function () {
  const m = JSON.parse(execFileSync('python3', ['-B', 'scripts/data/degenerette_single_symbol_math.py'], { encoding: 'utf8' }));
  it('funds matched gold in the base EV using its joint distribution with score', function () {
    expect(m.gold_extra_base_ev_pp).to.be.closeTo(4.785943120718002, 1e-9);
    expect(m.any_gold_match_percent).to.be.closeTo(6.10503554344, 1e-9);
  });
  it('adds five ETH return percentage points at every activity tier', function () {
    expect(m.eth_bonus_ev_pp).to.be.closeTo(5, 0.000001);
    for (const r of m.activity_returns_percent) expect(r.ETH_with_5pp-r.ordinary).to.be.closeTo(5, 0.000001);
  });
  it('calibrates the rig and gold to 70-130%, negative EV through activity 169', function () {
    expect(m.wwxrp.base_ev_percent).to.be.closeTo(70, 0.000001);
    expect(m.wwxrp.max_ev_percent).to.be.closeTo(130, 0.00002);
    expect(m.wwxrp.first_nonnegative_activity).to.equal(170);
    for (const r of m.activity_returns_percent) {
      expect(r.WWXRP).to.be.closeTo(r.WWXRP_target, 0.00002);
      if (r.activity_score < 170) expect(r.WWXRP).to.be.below(100);
    }
  });
  it('spends the max-activity surplus on scores 6-9 in the existing 10/30/30/30 split', function () {
    const bonuses = m.wwxrp.activity_bonus_ev_by_winning_score_pp;
    for (const s of [6,7,8,9]) expect(bonuses[s]).to.be.closeTo(s===6 ? 6 : 18, 0.00001);
  });
});
