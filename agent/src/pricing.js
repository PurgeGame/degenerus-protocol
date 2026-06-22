// EV / pricing model.
//
// PRICES are read LIVE from chain (mintPrice/purchaseInfo/preview views) so the
// model is automatically correct at the /1e6 testnet scale — nothing hardcoded.
//
// PAYOUT tables are NOT externally viewable: the Degenerette/foil engines keep
// their base-payout tables and ROI/RTP curves as PRIVATE constants. For the
// per-actor P&L residual we model each gamble's EXPECTED value from the ROI/RTP
// curves (honest lane 90%→99.9%, WWXRP lane 70%→120% floor 70%). These are the
// load-bearing EV BOUNDS the gate compares realized profit against. The exact
// per-(N,score) base tables (DegenerusGameDegeneretteModule) only sharpen the
// variance, not the mean bound, and the oracle's DEG statistical ceiling checks
// realized payout/wager directly against the ≤100-centi-x honest bound.

const BPS = 10_000n;

// activityScore consumers cap the score before the curve: degenerette 305.
const DEG_SCORE_CAP = 305;

export class Pricing {
  constructor(conn) {
    this.conn = conn;
  }

  async purchaseInfo() {
    const [lvl, jackpotPhase, lastPurchaseDay, rngLocked, priceWei] = await this.conn.game.purchaseInfo();
    return { level: Number(lvl), jackpotPhase, lastPurchaseDay, rngLocked, priceWei };
  }

  async mintPrice() {
    return this.conn.game.mintPrice();
  }

  // DirectEth ticket cost for a 2-decimal-scaled quantity (qty=400 == 1 price).
  async ticketCost(qty) {
    const price = await this.mintPrice();
    return (price * BigInt(qty)) / 400n;
  }

  async activityScore(address) {
    try { return Number(await this.conn.game.playerActivityScore(address)); }
    catch { return 0; }
  }

  // Honest Degenerette ROI in bps: 9000 (score 0) → 9990 (score cap). Strictly
  // <100% at every score (house edge ≥ 0). Linear interpolation of the pinned
  // endpoints (ROI_MIN 9000 → 9990); exact intermediate steps live in-contract.
  honestRoiBps(score) {
    const s = Math.max(0, Math.min(DEG_SCORE_CAP, score));
    return 9000n + (990n * BigInt(s)) / BigInt(DEG_SCORE_CAP); // 9000..9990
  }

  // WWXRP RTP in bps: floor 7000, rising to 12000 at high activity (70→120%).
  wwxrpRoiBps(score) {
    const s = Math.max(0, Math.min(DEG_SCORE_CAP, score));
    const v = 7000n + (5000n * BigInt(s)) / BigInt(DEG_SCORE_CAP); // 7000..12000
    return v < 7000n ? 7000n : v; // explicit floor
  }

  // Modeled net EV of a Degenerette bet (wei). currency: 0 ETH, 1 FLIP, 3 WWXRP.
  // For numeraire P&L only ETH-currency bets move the ETH ledger; FLIP/WWXRP are
  // tracked in their own units (returned for the betting-EV oracle).
  modelDegeneretteEv(stakeWei, currency, score) {
    const rtp = currency === 3 ? this.wwxrpRoiBps(score) : this.honestRoiBps(score);
    const expectedReturn = (stakeWei * rtp) / BPS;
    const evNet = expectedReturn - stakeWei; // ≤ 0 for honest lanes
    return { rtpBps: rtp, expectedReturnWei: expectedReturn, evNetWei: evNet };
  }

  // Coinflip: pays rewardPercent (bps-like) on a win. Without the contract's win
  // probability exposed, model EV neutrally (stake-conserving) unless the day is
  // resolved, then use the realized outcome. Returns a conservative EV bound.
  async modelCoinflipEv(stakeFlip, day) {
    try {
      const [rewardPercent, win] = await this.conn.coinflip.getCoinflipDayResult(day);
      const mult = BigInt(rewardPercent);
      const realized = win ? (stakeFlip * mult) / 100n : 0n;
      return { resolved: true, win, rewardPercent: Number(rewardPercent), realizedFlip: realized };
    } catch {
      return { resolved: false, evNetFlip: 0n }; // unresolved → neutral
    }
  }

  // Redemption / salvage exits are value-CONSERVING exchanges: realized value is
  // quoted live by a preview view, so the modeled EV equals the quote (residual
  // ≈ 0). Returned for the action driver to set value_in/value_out from chain.
  async previewSdgnrsBurn(amount) {
    const [ethOut, stethOut, flipOut] = await this.conn.sdgnrs.previewBurn(amount);
    return { ethEquivWei: ethOut + stethOut, flipOut };
  }
}
