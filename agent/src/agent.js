// Agent orchestrator — the connect-and-play campaign loop (AGT-01..06).
//
// Wires Connection + WalletPool + ActionSurface + InvariantOracle + Ledger +
// Gate + Recorder into one loop: pick an actor, run a probe, then ASSERT the
// MAN-01 oracle from chain state, mark-to-market the actor, and — on a counted
// sample — run the profit gate. A conservation break records immediately; a
// "win more than you should" signal is adjudicated against the by-design
// allowlist before it records. Every step is a structured, replayable tx record.

import { readFileSync } from "node:fs";
import { Connection } from "./connection.js";
import { Ledger } from "./ledger.js";
import { Pricing } from "./pricing.js";
import { InvariantOracle } from "./oracle.js";
import { Gate } from "./gate.js";
import { Recorder } from "./records.js";
import { WalletPool } from "./wallets.js";
import { ActionSurface } from "./actions.js";
import { Strategy } from "./strategy.js";
import { AGENT_ROOT } from "./config.js";
import { resolve } from "node:path";

export class Agent {
  constructor(cfg) {
    this.cfg = cfg;
    this.conn = new Connection(cfg);
    this.manifest = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/invariants.json"), "utf8"));
    this.allowlist = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/allowlist.json"), "utf8"));
    this.ledger = new Ledger(cfg.ledger.dbPath);
    this.pricing = new Pricing(this.conn);
    this.oracle = new InvariantOracle(this.conn, this.manifest);
    this.gate = new Gate(this.allowlist, cfg.gate);
    this.recorder = new Recorder(cfg.records.dir);
    this.pool = new WalletPool(this.conn, cfg);
    this.surface = new ActionSurface({ conn: this.conn, ledger: this.ledger, pricing: this.pricing, oracle: this.oracle, gas: cfg.gas });
    this.strategy = new Strategy();
    this.recentTxs = [];
    this.step = 0;
    this.stats = { actions: 0, reverts: 0, stateViolations: 0, windowTransients: 0, profitAlarms: 0, degFindings: 0, findings: 0, revertReasons: {} };
  }

  async init() {
    // Fail fast on a stale/missing deployment manifest (no code at GAME address)
    // rather than a cryptic BAD_DATA later — common when the node was redeployed.
    const code = await this.conn.provider.getCode(this.conn.address("GAME"));
    if (!code || code === "0x") {
      throw new Error(`no contract code at GAME ${this.conn.address("GAME")} — stale ${this.cfg.deploymentsPath}? Re-run deploy:local / point at the live manifest.`);
    }
    await this.pool.init();
    // Baseline snapshot for every actor + checkpoint reconcile.
    const block = await this.conn.provider.getBlockNumber();
    for (const w of this.pool.wallets) {
      await this._snapshotActor(w.address, block);
    }
    const last = this.ledger.getMeta("lastBlock");
    this.ledger.setMeta("bootBlock", block);
    return { block, resumedFrom: last ? Number(last) : null, actors: this.pool.addresses() };
  }

  async _snapshotActor(address, block) {
    const { readLegs } = await import("./legs.js");
    const legs = await readLegs(this.conn, address);
    this.ledger.snapshot(address, block, 0, legs.ethEquivWei, legs);
    return legs;
  }

  // One campaign step.
  async tick() {
    this.step += 1;
    const actor = this.pool.get(this.step);
    const probe = this.strategy.next();

    const ctx = { surface: this.surface, actor, conn: this.conn, pricing: this.pricing };
    let rec;
    try {
      rec = await probe.run(ctx);
    } catch (e) {
      rec = { ok: false, action: probe.name, revert: e.shortMessage || e.message, from: actor.address };
    }
    rec.probe = probe.name;
    this.stats.actions++;
    if (rec.ok === false) {
      this.stats.reverts++;
      const reason = normalizeRevert(rec.revert);
      this.stats.revertReasons[reason] = (this.stats.revertReasons[reason] || 0) + 1;
    }
    this._remember(rec);

    // RNG-freeze window probe: if locked, snapshot -> in-window action -> verify.
    let windowFinding = null;
    try {
      const snap = await this.oracle.snapshotFrozen();
      if (snap.locked) {
        await this.surface.openBoxes(actor, 5); // an in-window player action
        windowFinding = await this.oracle.verifyFrozen(snap);
      }
    } catch { /* window probe best-effort */ }

    // Per-action MAN-01 STATE assertion.
    const block = rec.block ?? (await this.conn.provider.getBlockNumber());
    const check = await this.oracle.checkState();
    for (const v of check.violations) {
      const cls = this.gate.classifyStateViolation(v);
      this._recordFinding({ kind: "invariant", ...cls, block, actor: actor.address });
      this.stats.stateViolations++;
    }
    // In-window at-rest-invariant transients: counted as INFO, not findings (they
    // heal at seal; a persistent breach surfaces as a real violation at rest).
    this.stats.windowTransients += check.transients.length;
    if (windowFinding) {
      if (windowFinding.transient) {
        // rng-window lifecycle transition straddled the probe — INFO, not a finding.
        this.stats.windowTransients++;
      } else {
        this._recordFinding({ kind: "invariant", ...windowFinding, block, actor: actor.address });
        this.stats.stateViolations++;
      }
    }
    for (const v of this.oracle.drainPerSpin()) {
      this._recordFinding({ kind: "invariant", ...v, block, actor: actor.address, disposition: "REVIEW" });
    }

    // Mark-to-market the actor.
    await this._snapshotActor(actor.address, block);

    // Counted-sample profit gate (every 25 steps to amortize cost).
    if (this.step % 25 === 0) await this._runProfitGate(block);

    // Degenerette EV ceiling (statistical).
    for (const f of this.oracle.evCeilingFindings(this.cfg.gate.minSample)) {
      this._recordFinding({ kind: "profit", ...f, block, disposition: "REVIEW" });
      this.stats.degFindings++;
    }

    this.ledger.setMeta("lastBlock", block);
    return { step: this.step, probe: probe.name, ok: rec.ok !== false, revert: rec.revert, violations: check.violations.length };
  }

  async _runProfitGate(block) {
    for (const w of this.pool.wallets) {
      const verdict = this.gate.evaluateProfit(this.ledger, w.address);
      if (verdict.alarm) {
        // Adjudicate against the by-design allowlist using the actor's flags.
        const flags = await this._actorFlags(w.address);
        const allow = this.gate.matchAllowlist({ action: "profit-aggregate", actorFlags: flags });
        const gas = this.gate.gasViability(BigInt(verdict.totalResidualWei), BigInt(verdict.gasWei));
        this._recordFinding({
          kind: "profit", id: "WIN-MORE-THAN-EV", severity: "high",
          identity: "per-actor realized profit must not exceed modeled EV beyond kσ",
          observed: verdict.reason, expected: `within ${this.cfg.gate.kSigma}σ`,
          actor: w.address, block, allowlist: allow, gas,
          disposition: allow ? "DOCUMENT" : "REVIEW", extra: verdict,
        });
        if (!allow) this.stats.profitAlarms++;
      }
    }
  }

  async _actorFlags(address) {
    const flags = { deity: false, owner: false, protocolSeed: false, boon: false };
    try { flags.owner = (await this.conn.game.owner?.().catch(() => null))?.toLowerCase?.() === address.toLowerCase(); } catch { /* */ }
    // deity / protocol-seed detection can be refined via on-chain reads as needed.
    return flags;
  }

  _remember(rec) {
    this.recentTxs.push({
      action: rec.action, contract: rec.contract, to: rec.to, from: rec.from,
      selector: rec.selector, args: rec.args, valueWei: rec.valueWei, txHash: rec.txHash,
      block: rec.block, status: rec.status, gasWei: rec.gasWei, ok: rec.ok, revert: rec.revert,
    });
    if (this.recentTxs.length > 32) this.recentTxs.shift();
  }

  _recordFinding(f) {
    const pre = f.actor ? this.ledger.pnl(f.actor) : null;
    const path = this.recorder.record({
      ...f, rpc: this.cfg.rpcUrl,
      txSequence: this.recentTxs.slice(-8),
      preLedger: pre, postLedger: pre,
    });
    this.stats.findings++;
    return path;
  }

  async runCampaign({ maxSteps = 0, onProgress } = {}) {
    let i = 0;
    while (maxSteps === 0 || i < maxSteps) {
      const r = await this.tick();
      onProgress?.(r, this.stats);
      i++;
    }
    return this.stats;
  }

  close() { this.ledger.close(); }
}

// Collapse a revert message to a short bucket so the tally stays readable.
function normalizeRevert(r) {
  if (!r) return "unknown";
  const s = String(r);
  const m = s.match(/[A-Za-z_][A-Za-z0-9_]*\(\)/); // a named custom error like E()
  if (m) return m[0];
  if (/rngLocked/i.test(s)) return "rngLocked (guard)";
  if (/insufficient|exact|value/i.test(s)) return "value/amount guard";
  if (/nonce/i.test(s)) return "nonce";
  return s.slice(0, 48);
}
