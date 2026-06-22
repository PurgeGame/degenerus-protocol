// External action-surface driver (AGT-02).
//
// Drives the full external surface of the FROZEN protocol with valid sequencing,
// mirroring the patterns in test/fuzz/handlers/. Every priced input is read LIVE
// from chain so the /1e6 testnet scaling is automatic. Each call emits a
// structured, replayable tx record (to/from/selector/args/value/hash/block/gas)
// and books the value legs + modeled EV into the ledger. An expected guard
// revert (e.g. purchase while rngLocked) is NOT a violation — it is returned as
// {ok:false, revert} for the strategy to interpret.
//
// The agent calls only the public GAME facade + token handles. It NEVER touches
// evm_* / VRF / stETH (that is the environment's job — the dev-driver locally,
// the sim repo + real Chainlink on live).

import { ethers } from "ethers";

const ZERO32 = ethers.ZeroHash;

// Live-network tx timeouts. The single-threaded loop awaits each tx, so an
// unbounded broadcast (hung estimateGas/send) or confirmation (a tx left unmined
// by congestion / underpricing) would wedge the whole soak. Bounding both keeps
// the loop progressing; a timeout is surfaced as a soft {ok:false}, not a finding.
const SEND_TIMEOUT_MS = 30_000;
const CONFIRM_TIMEOUT_MS = 45_000;

function withTimeout(promise, ms, label) {
  let t;
  const timeout = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${label} timeout`)), ms); });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(t));
}

export class ActionSurface {
  constructor({ conn, ledger, pricing, oracle }) {
    this.conn = conn;
    this.ledger = ledger;
    this.pricing = pricing;
    this.oracle = oracle;
    this.openBets = new Map(); // actor -> [{betId, stakeWei, currency, score}]
    this._ftrTopic = null;
  }

  // -- generic send ----------------------------------------------------------
  // Sends `fn(...args)` on `key`'s handle from `actor`, books flows, returns a
  // structured record. meta carries the value-leg + EV bookkeeping.
  async call(actor, key, fn, args, meta = {}) {
    const value = meta.value ?? 0n;
    const handle = this.conn.write(key, actor.signer);
    const to = this.conn.address(key);
    const rec = {
      action: meta.action || fn, contract: key, to, from: actor.address,
      selector: fn, args: args.map(stringifyArg), valueWei: value.toString(),
    };
    try {
      const txArgs = value > 0n ? [...args, { value }] : [...args];
      // Bound the broadcast and the confirmation independently (see top-of-file).
      const tx = await withTimeout(handle[fn](...txArgs), SEND_TIMEOUT_MS, "send");
      const receipt = await tx.wait(1, CONFIRM_TIMEOUT_MS);
      if (!receipt) throw new Error("confirm timeout (no receipt)");
      const gasWei = receipt.gasUsed * (receipt.gasPrice ?? 0n);
      rec.txHash = receipt.hash; rec.block = receipt.blockNumber;
      rec.status = receipt.status; rec.gasWei = gasWei.toString(); rec.ok = true;
      rec.logs = receipt.logs;
      this.ledger.recordAction({
        address: actor.address, action: rec.action, block: receipt.blockNumber,
        ts: 0, valueInWei: meta.valueInWei ?? value, valueOutWei: meta.valueOutWei ?? 0n,
        evModeledWei: meta.evModeledWei ?? 0n, gasWei, sample: !!meta.sample,
        txHash: receipt.hash, note: meta.note || "",
      });
      return rec;
    } catch (e) {
      rec.ok = false;
      rec.revert = e.revert?.name || e.shortMessage || e.reason || e.message;
      // A send/confirm timeout may leave the actor's NonceManager holding a stale
      // (possibly already-broadcast) nonce; reset so it re-syncs from chain on the
      // next pick rather than wedging that wallet behind a phantom nonce.
      if (/timeout/i.test(rec.revert || "")) { try { actor.signer.reset(); } catch { /* */ } }
      return rec;
    }
  }

  // -- core day-loop actions -------------------------------------------------

  async purchase(actor, { qty = 400, lootBoxAmount = 0n, affiliate = ZERO32, payKind = 0, foil = false } = {}) {
    const info = await this.pricing.purchaseInfo();
    if (info.rngLocked) return { ok: false, revert: "rngLocked (guard, expected)", action: "purchase", from: actor.address };
    const cost = (info.priceWei * BigInt(qty)) / 400n + BigInt(lootBoxAmount) + (foil ? info.priceWei * 10n : 0n);
    return this.call(actor, "GAME", "purchase",
      [actor.address, qty, lootBoxAmount, affiliate, payKind, foil],
      { action: "purchase", value: payKind === 0 ? cost : 0n, valueInWei: payKind === 0 ? cost : 0n, note: foil ? "foil" : "" });
  }

  async advanceGame(actor) {
    return this.call(actor, "GAME", "advanceGame", [], { action: "advanceGame" });
  }

  async requestLootboxRng(actor) {
    return this.call(actor, "GAME", "requestLootboxRng", [], { action: "requestLootboxRng" });
  }

  // Degenerette: place a bet (stake leaves wallet) — tracked, scored at resolve.
  async placeDegeneretteBet(actor, { currency = 0, amountPerTicket, ticketCount = 1, customTicket = 0, heroQuadrant = 0xff } = {}) {
    const amt = BigInt(amountPerTicket ?? (await this.pricing.mintPrice()) / 10n);
    const stake = amt * BigInt(ticketCount);
    const score = await this.pricing.activityScore(actor.address);
    const rec = await this.call(actor, "GAME", "placeDegeneretteBet",
      [actor.address, currency, amt, ticketCount, customTicket, heroQuadrant],
      { action: "placeDegeneretteBet", value: currency === 0 ? stake : 0n, valueInWei: 0n, note: `cur${currency}` });
    if (rec.ok) {
      const list = this.openBets.get(actor.address) || [];
      // betId is the player's sequential nonce; track count to derive ids at resolve.
      list.push({ stakeWei: stake, currency, score, perTicket: amt, ticketCount });
      this.openBets.set(actor.address, list);
    }
    return rec;
  }

  // Resolve: books ONE complete sample per resolved bet (stake vs payout vs EV)
  // and feeds the oracle's Degenerette EV stream from FullTicketResult logs.
  async resolveDegeneretteBets(actor, betIds) {
    const claimableBefore = await this.conn.game.claimableWinningsOf(actor.address).catch(() => 0n);
    const rec = await this.call(actor, "GAME", "resolveDegeneretteBets", [actor.address, betIds],
      { action: "resolveDegeneretteBets" });
    if (!rec.ok) return rec;
    const claimableAfter = await this.conn.game.claimableWinningsOf(actor.address).catch(() => 0n);
    const ethPayout = claimableAfter > claimableBefore ? claimableAfter - claimableBefore : 0n;

    // Feed the Degenerette EV oracle from FullTicketResult events.
    const spins = this._decodeFullTicketResults(rec.logs || []);
    for (const s of spins) this.oracle.ingestSpin(s);

    // Book the resolved bets as samples (aggregate ETH payout across this call).
    const list = this.openBets.get(actor.address) || [];
    const resolved = list.splice(0, betIds.length);
    this.openBets.set(actor.address, list);
    const totalStake = resolved.reduce((a, b) => a + (b.currency === 0 ? b.stakeWei : 0n), 0n);
    let evNet = 0n;
    for (const b of resolved) {
      if (b.currency === 0) evNet += this.pricing.modelDegeneretteEv(b.stakeWei, 0, b.score).evNetWei;
    }
    if (totalStake > 0n) {
      this.ledger.recordAction({
        address: actor.address, action: "degenerette-settled", block: rec.block, ts: 0,
        valueInWei: totalStake, valueOutWei: ethPayout, evModeledWei: evNet, gasWei: 0n,
        sample: true, txHash: rec.txHash, note: "ETH Degenerette settlement",
      });
    }
    rec.ethPayoutWei = ethPayout.toString();
    rec.spins = spins.length;
    return rec;
  }

  async openBoxes(actor, maxCount = 10) {
    return this.call(actor, "GAME", "openBoxes", [maxCount], { action: "openBoxes" });
  }

  async claimWinnings(actor, target = null) {
    const who = target || actor.address;
    const before = await this.conn.provider.getBalance(actor.address);
    const rec = await this.call(actor, "GAME", "claimWinnings", [who], { action: "claimWinnings" });
    return rec;
  }

  async depositAfkingFunding(actor, target, amountWei) {
    return this.call(actor, "GAME", "depositAfkingFunding", [target || actor.address],
      { action: "depositAfkingFunding", value: BigInt(amountWei), valueInWei: BigInt(amountWei) });
  }

  // Passes -------------------------------------------------------------------
  async purchaseWhaleBundle(actor, quantity = 1) {
    // bundlePrice: 2.4 ETH lvl0-3, 4 ETH higher — read level, fall back on revert.
    const info = await this.pricing.purchaseInfo();
    const unit = info.level <= 3 ? ethers.parseEther("2.4") : ethers.parseEther("4");
    const cost = unit * BigInt(quantity);
    return this.call(actor, "GAME", "purchaseWhaleBundle", [actor.address, quantity],
      { action: "purchaseWhaleBundle", value: cost, valueInWei: cost });
  }

  async purchaseLazyPass(actor) {
    const info = await this.pricing.purchaseInfo();
    const cost = info.level <= 2 ? ethers.parseEther("0.24") : info.priceWei * 10n; // window approx
    return this.call(actor, "GAME", "purchaseLazyPass", [actor.address],
      { action: "purchaseLazyPass", value: cost, valueInWei: cost });
  }

  // sDGNRS redemption burn (value-conserving exchange; quoted live) ----------
  async sdgnrsBurn(actor, amountWei) {
    const handle = this.conn.write("SDGNRS", actor.signer);
    const quote = await this.conn.sdgnrs.previewBurn(amountWei).catch(() => null);
    const valueOut = quote ? quote[0] + quote[1] : 0n;
    return this.call(actor, "SDGNRS", "burn", [amountWei],
      { action: "sdgnrs.burn", valueInWei: 0n, valueOutWei: valueOut, note: "redemption" });
  }

  // Generic claim-for-others surfaces (credit the named player, not the caller).
  async claimFoilMatchMany(actor, players, days, ticketIndexes, drawKinds) {
    return this.call(actor, "GAME", "claimFoilMatchMany", [players, days, ticketIndexes, drawKinds],
      { action: "claimFoilMatchMany" });
  }
  async claimAfkingFlip(actor, subs) {
    return this.call(actor, "GAME", "claimAfkingFlip", [subs], { action: "claimAfkingFlip" });
  }
  async mintFlip(actor) {
    return this.call(actor, "GAME", "mintFlip", [], { action: "mintFlip" });
  }
  async setOperatorApproval(actor, operator, approved = true) {
    return this.call(actor, "GAME", "setOperatorApproval", [operator, approved], { action: "setOperatorApproval" });
  }

  // -- event decoding --------------------------------------------------------
  _decodeFullTicketResults(logs) {
    const iface = new ethers.Interface(this.conn.abi("GAME"));
    if (!this._ftrTopic) {
      try { this._ftrTopic = iface.getEvent("FullTicketResult").topicHash; } catch { this._ftrTopic = null; }
    }
    const out = [];
    for (const log of logs) {
      try {
        const parsed = iface.parseLog(log);
        if (!parsed || parsed.name !== "FullTicketResult") continue;
        const a = parsed.args;
        out.push({
          player: a.player, betId: Number(a.betId ?? 0), ticketIndex: Number(a.ticketIndex ?? 0),
          playerTicket: Number(a.playerTicket ?? 0), matches: Number(a.matches ?? 0),
          payout: a.payout ?? 0n, goldCount: countGold(Number(a.playerTicket ?? 0)),
          currency: a.currency != null ? Number(a.currency) : undefined,
          wager: a.wager ?? a.payout ?? 0n,
        });
      } catch { /* non-FTR log */ }
    }
    return out;
  }
}

function stringifyArg(a) {
  if (typeof a === "bigint") return a.toString();
  if (Array.isArray(a)) return a.map(stringifyArg);
  return a;
}

// Count gold quadrants in a packed Degenerette ticket (per quadrant: color in
// bits[5:3], symbol bits[2:0]; "gold" is color id 0 by the trait convention).
function countGold(packed) {
  let n = 0;
  for (let q = 0; q < 4; q++) {
    const color = (packed >> (q * 6 + 3)) & 0x7;
    if (color === 0) n++;
  }
  return n;
}
