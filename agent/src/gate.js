// By-design allowlist + k·σ statistical gate (AGT-05).
//
// Two responsibilities:
//  1) matchAllowlist(ctx) — recognize when a value-positive outcome flows through
//     a by-design channel (deity refund/boon, redemption/salvage exchange, foil
//     subsidy, owner knob, a documented WONTFIX). Such outcomes are EXPLAINED,
//     not exploits, and must not raise the "win more than you should" alarm.
//  2) evaluateProfit(ledger, actor) — the statistical core. The alarm fires only
//     when an actor's REALIZED protocol-value profit exceeds the MODELED EV by
//     kσ over a COUNTED sample of EV-bearing actions (never per-spin). Variance
//     is estimated from the per-action residual series.
//
// Conservation breaks (SOLVENCY / BACKING / SUPPLY, surfaced by the oracle STATE
// check) are NEVER routed through the statistical gate or the allowlist — they
// are scale-invariant and alarm immediately (classifyStateViolation).
//
// Mainnet-gas-viability is a SEPARATE annotation: a tiny extraction that mainnet
// gas would eat is still logged, tagged not-gas-viable — free testnet gas must
// never mask a finding.

const GWEI = 1e9;

export class Gate {
  constructor(allowlist, params = {}) {
    this.allow = allowlist;
    this.kSigma = params.kSigma ?? 4;
    this.minSample = params.minSample ?? 200;
    // Absolute floor (wei) below which a "profit" is treated as dust/rounding,
    // not a finding — but still annotated. Scale-free: tuned tiny for /1e6 testnet.
    this.dustWei = BigInt(params.dustWei ?? 1_000_000); // 1e6 wei
  }

  // ctx: { action, currency, foil, actorFlags:{deity,owner,protocolSeed}, vrfStallDays, livenessTriggered }
  matchAllowlist(ctx) {
    for (const e of this.allow.entries) {
      const m = e.match || {};
      if (m.actions && !m.actions.includes(ctx.action) &&
          !(m.functions && m.functions.includes(ctx.action))) continue;
      if (m.functions && !m.functions.includes(ctx.action) &&
          !(m.actions && m.actions.includes(ctx.action))) continue;
      const conds = m.conditions || [];
      if (conds.includes("actorHoldsDeityPass") && !ctx.actorFlags?.deity) continue;
      if (conds.includes("activeBoonSlot") && !ctx.actorFlags?.boon) continue;
      if (conds.includes("callerIsOwnerOrAdmin") && !ctx.actorFlags?.owner) continue;
      if (conds.includes("actorIsProtocolOwnedSeedAddress") && !ctx.actorFlags?.protocolSeed) continue;
      if (conds.includes("currency==3") && ctx.currency !== 3) continue;
      if (conds.includes("foil==true") && !ctx.foil) continue;
      if (conds.includes("vrfStallDays>120") && !(ctx.vrfStallDays > 120)) continue;
      if (conds.includes("gameOverBeforeLevel10") && !ctx.gameOverBeforeLevel10) continue;
      if (conds.includes("livenessTriggeredUnderSustainedStall") && !ctx.livenessTriggered) continue;
      return { id: e.id, name: e.name, class: e.class, whyByDesign: e.whyByDesign };
    }
    return null;
  }

  // A conservation/state violation is always real and never allowlisted.
  classifyStateViolation(v) {
    return { ...v, real: true, allowlisted: false, byDesign: null };
  }

  // The statistical "win more than you should" test over an actor's sample.
  evaluateProfit(ledger, address) {
    const summary = ledger.pnl(address);
    if (!summary) return { address, alarm: false, reason: "unknown actor" };
    const residuals = ledger.sampleResiduals(address).map((x) => Number(x) / GWEI); // gwei
    const n = residuals.length;
    const totalWei = summary.residual; // protocolPnl - evModeled, BigInt wei
    const base = {
      address, alarm: false, n, totalResidualWei: totalWei.toString(),
      protocolPnlWei: summary.protocolPnl.toString(), evModeledWei: summary.evModeled.toString(),
      gasWei: summary.gas.toString(),
    };

    if (n < this.minSample) {
      return { ...base, reason: `insufficient sample (${n}<${this.minSample})` };
    }
    if (totalWei <= this.dustWei) {
      return { ...base, reason: "no positive profit beyond EV (≤ dust)" };
    }

    const mean = residuals.reduce((a, b) => a + b, 0) / n;
    const variance = residuals.reduce((a, b) => a + (b - mean) ** 2, 0) / Math.max(1, n - 1);
    const sd = Math.sqrt(variance);
    const totalGwei = Number(totalWei) / GWEI;

    if (sd < 1e-9) {
      // Deterministic positive residual beyond EV — a non-statistical edge.
      return { ...base, alarm: totalGwei > 0, sigmaGwei: 0, z: Infinity,
        reason: totalGwei > 0 ? "deterministic profit beyond modeled EV" : "no edge" };
    }

    const sigmaTotalGwei = sd * Math.sqrt(n); // std of the SUM of n samples
    const z = totalGwei / sigmaTotalGwei;
    const alarm = z > this.kSigma;
    return {
      ...base, alarm, sigmaGwei: Number(sigmaTotalGwei.toFixed(6)), z: Number(z.toFixed(3)),
      kSigma: this.kSigma,
      reason: alarm
        ? `realized profit ${totalGwei.toFixed(3)} gwei exceeds EV by ${z.toFixed(2)}σ (> kσ=${this.kSigma})`
        : `within ${this.kSigma}σ (z=${z.toFixed(2)})`,
    };
  }

  // Separate mainnet-gas annotation for a flagged extraction.
  gasViability(extractedWei, gasWei, mainnetGweiHint = 5n) {
    // On testnet gas is free; estimate whether the same extraction survives a
    // realistic mainnet gas cost. We can only flag relative magnitude here.
    const eaten = gasWei >= extractedWei;
    return {
      extractedWei: extractedWei.toString(), testnetGasWei: gasWei.toString(),
      gasViableOnTestnet: extractedWei > 0n,
      mainnetGasViable: !eaten,
      note: eaten
        ? "extraction smaller than its own (testnet) gas — NOT gas-viable on mainnet"
        : "extraction exceeds gas cost — gas-viability plausible (confirm at mainnet gas price)",
    };
  }
}
