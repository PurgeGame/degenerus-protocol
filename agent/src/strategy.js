// Adversarial strategy — the probe set the agent cycles through (AGT-06).
//
// Each probe is a named attempt to either (a) extract more protocol value than
// the rules allow, or (b) brick / corrupt state. Probes read live state and
// sequence validly; an expected guard revert is a NEGATIVE result (the guard
// held), not a finding. The selector rotates probes deterministically so a flag
// is reproducible from the recorded sequence.
//
// MEV / interaction probes that only exist with honest 24/7 traffic
// (front-run / sandwich / shared-window race) live in mempool.js and are mixed
// in only in live/soak mode.

export const PROBES = [
  // --- participation baseline (also fills pools so other probes have surface) ---
  { name: "buy-ticket", weight: 3, async run({ surface, actor }) {
      return surface.purchase(actor, { qty: 400 });
  } },
  { name: "buy-foil", weight: 1, async run({ surface, actor }) {
      return surface.purchase(actor, { qty: 400, foil: true });
  } },

  // --- value-extraction: bet to win beyond EV; settle and measure ---
  { name: "degenerette-eth-bet", weight: 3, async run({ surface, actor, pricing }) {
      const amt = (await pricing.mintPrice()) / 10n;
      return surface.placeDegeneretteBet(actor, { currency: 0, amountPerTicket: amt, ticketCount: 3, heroQuadrant: 0 });
  } },
  { name: "degenerette-wwxrp-bet", weight: 2, async run({ surface, actor, pricing }) {
      // currency 3 = WWXRP (rig lane). Needs WWXRP balance; reverts benignly if 0.
      const amt = (await pricing.mintPrice()) / 10n;
      return surface.placeDegeneretteBet(actor, { currency: 3, amountPerTicket: amt, ticketCount: 2, heroQuadrant: 1 });
  } },
  { name: "open-boxes", weight: 2, async run({ surface, actor }) {
      return surface.openBoxes(actor, 20);
  } },

  // --- harvest: claim winnings; the oracle checks solvency holds after ---
  { name: "claim-winnings", weight: 2, async run({ surface, actor }) {
      return surface.claimWinnings(actor);
  } },
  { name: "mint-flip-bounty", weight: 1, async run({ surface, actor }) {
      return surface.mintFlip(actor);
  } },

  // --- brick probes: well-formed-but-edge calls that must fail on a GUARD only ---
  { name: "purchase-during-window", weight: 1, async run({ surface, actor }) {
      // If rngLocked, purchase MUST revert on the guard (not brick). The probe
      // returns the revert; FSM-03/liveness oracle confirms no permanent wedge.
      return surface.purchase(actor, { qty: 100 });
  } },
  { name: "whale-bundle", weight: 1, async run({ surface, actor }) {
      return surface.purchaseWhaleBundle(actor, 1);
  } },

  // --- redemption exit (value-conserving; oracle checks segregation/backing) ---
  { name: "afk-deposit", weight: 1, async run({ surface, actor, pricing }) {
      const amt = (await pricing.mintPrice()) / 2n;
      return surface.depositAfkingFunding(actor, actor.address, amt);
  } },
];

export class Strategy {
  constructor(probes = PROBES) {
    // Expand by weight into a flat rotation for deterministic, replayable picks.
    this.rotation = [];
    for (const p of probes) for (let i = 0; i < (p.weight || 1); i++) this.rotation.push(p);
    this.cursor = 0;
  }
  next() {
    const p = this.rotation[this.cursor % this.rotation.length];
    this.cursor++;
    return p;
  }
}
