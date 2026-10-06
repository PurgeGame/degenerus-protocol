import { expect } from 'chai';
import { execFileSync } from 'node:child_process';

describe('Result-wild, ETH addition and side-reward budgets', function () {
  const m = JSON.parse(execFileSync('python3', ['-B', 'scripts/data/degenerette_single_symbol_math.py'], { encoding: 'utf8' }));
  it('adds the literal ETH additions at every activity tier', function () {
    expect(m.eth_extra_pp).to.be.closeTo(4.999995757825673, 1e-12);
    for (const r of m.activity_returns_percent) expect(r.ETH - r.ordinary).to.be.closeTo(m.eth_extra_pp, 1e-9);
  });
  it('lets the fully boosted paid jackpot exceed 1,000,000x with no ceiling', function () {
    expect(m.paid_maxima_x.FLIP_after_survival).to.equal(1029369.6);
    expect(m.paid_maxima_x.ETH_gross).to.equal(1016632.96);
  });
  it('calibrates the WWXRP rig and wilds to 70-130%, negative EV through activity 169', function () {
    expect(m.wwxrp.base_ev_percent).to.be.closeTo(70, 0.00002);
    expect(m.wwxrp.max_ev_percent).to.be.closeTo(130, 0.00002);
    expect(m.wwxrp.first_nonnegative_activity).to.equal(170);
    for (const r of m.activity_returns_percent) {
      expect(r.WWXRP).to.be.closeTo(r.WWXRP_target, 0.00002);
      if (r.activity_score < 170) expect(r.WWXRP).to.be.below(100);
    }
  });
  it('spends the max-activity WWXRP surplus on scores 6-9 in the 10/30/30/30 split', function () {
    const bonuses = m.wwxrp.activity_bonus_ev_by_winning_score_pp;
    for (const s of [6, 7, 8, 9]) expect(bonuses[s]).to.be.closeTo(s === 6 ? 6 : 18, 0.00001);
  });
  it('keeps the sDGNRS and affiliate side rewards at the previous expected value', function () {
    expect(m.side_rewards.dgnrs_bps).to.deep.equal({ 7: 204, 8: 466, 9: 1010 });
    expect(m.side_rewards.dgnrs_new_over_old).to.be.closeTo(1, 0.002);
    expect(m.side_rewards.affiliate_bps).to.equal(426);
    for (const r of m.side_rewards.affiliate_by_activity) expect(r.new_over_old).to.be.closeTo(1, 0.01);
  });
});
