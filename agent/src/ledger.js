// Per-actor P&L ledger — the AGT-03 numeraire accounting.
//
// Tracks, per wallet, every value flow normalized to ETH wei and a mark-to-
// market position (from legs.js), so the agent can compute REALIZED net P&L vs
// MODELED EV. Persisted in better-sqlite3 so a soak can checkpoint/resume
// (SOAK-03): the ledger + last-processed block survive a restart.
//
// Accounting identity (all ETH-equiv wei):
//   protocolPnl(actor) = (positionNow - baseline) - externalInjections + gasSpent
//     - positionNow  : latest mark-to-market ETH-equiv of all realizable legs
//     - baseline     : ETH-equiv at the actor's first snapshot
//     - injections   : faucet/drip ETH we put in from outside the game (live mode)
//     - gasSpent     : added back — gas is a SEPARATE mainnet-viability annotation,
//                      not a protocol loss (free testnet gas must not mask a finding)
//   evModeled(actor) = Σ modeled EV of every EV-bearing action
//   residual         = protocolPnl - evModeled   (≈0 mean; the gate flags > k·σ)

import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

const S = (v) => (typeof v === "bigint" ? v.toString() : String(v ?? "0"));
const B = (v) => BigInt(v ?? "0");

export class Ledger {
  constructor(dbPath) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath);
    this.db.pragma("journal_mode = WAL");
    this._migrate();
  }

  _migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
      CREATE TABLE IF NOT EXISTS actors (
        address TEXT PRIMARY KEY, label TEXT,
        first_block INTEGER, baseline_wei TEXT, injections_wei TEXT DEFAULT '0'
      );
      CREATE TABLE IF NOT EXISTS flows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT, block INTEGER, ts INTEGER, action TEXT,
        value_in_wei TEXT, value_out_wei TEXT, ev_modeled_wei TEXT,
        gas_wei TEXT, sample INTEGER DEFAULT 0, tx_hash TEXT, note TEXT
      );
      CREATE TABLE IF NOT EXISTS snapshots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        address TEXT, block INTEGER, ts INTEGER, eth_equiv_wei TEXT, raw_json TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_flows_addr ON flows(address);
      CREATE INDEX IF NOT EXISTS idx_snap_addr ON snapshots(address, id);
    `);
  }

  setMeta(k, v) {
    this.db.prepare("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=?")
      .run(k, String(v), String(v));
  }
  getMeta(k) {
    return this.db.prepare("SELECT value FROM meta WHERE key=?").get(k)?.value;
  }

  ensureActor(address, label = "") {
    const row = this.db.prepare("SELECT address FROM actors WHERE address=?").get(address);
    if (!row) {
      this.db.prepare("INSERT INTO actors(address,label,first_block,baseline_wei) VALUES(?,?,?,?)")
        .run(address, label, null, null);
    }
  }

  recordInjection(address, wei) {
    this.ensureActor(address);
    const cur = B(this.db.prepare("SELECT injections_wei FROM actors WHERE address=?").get(address)?.injections_wei);
    this.db.prepare("UPDATE actors SET injections_wei=? WHERE address=?").run(S(cur + B(wei)), address);
  }

  // Record one EV-bearing or value-moving action.
  recordAction(f) {
    this.ensureActor(f.address, f.label);
    this.db.prepare(`INSERT INTO flows
      (address,block,ts,action,value_in_wei,value_out_wei,ev_modeled_wei,gas_wei,sample,tx_hash,note)
      VALUES (@address,@block,@ts,@action,@vin,@vout,@ev,@gas,@sample,@tx,@note)`)
      .run({
        address: f.address, block: f.block ?? 0, ts: f.ts ?? 0, action: f.action,
        vin: S(f.valueInWei), vout: S(f.valueOutWei), ev: S(f.evModeledWei),
        gas: S(f.gasWei), sample: f.sample ? 1 : 0, tx: f.txHash ?? "", note: f.note ?? "",
      });
  }

  // Store a mark-to-market position; the FIRST snapshot fixes the actor baseline.
  snapshot(address, block, ts, ethEquivWei, raw = {}) {
    this.ensureActor(address);
    this.db.prepare("INSERT INTO snapshots(address,block,ts,eth_equiv_wei,raw_json) VALUES(?,?,?,?,?)")
      .run(address, block, ts, S(ethEquivWei), JSON.stringify(raw, (_, v) => (typeof v === "bigint" ? v.toString() : v)));
    const a = this.db.prepare("SELECT baseline_wei FROM actors WHERE address=?").get(address);
    if (a && (a.baseline_wei === null || a.baseline_wei === undefined)) {
      this.db.prepare("UPDATE actors SET baseline_wei=?, first_block=? WHERE address=?")
        .run(S(ethEquivWei), block, address);
    }
  }

  latestPosition(address) {
    const r = this.db.prepare("SELECT eth_equiv_wei FROM snapshots WHERE address=? ORDER BY id DESC LIMIT 1").get(address);
    return r ? B(r.eth_equiv_wei) : 0n;
  }

  // Per-actor P&L summary in ETH-equiv wei.
  pnl(address) {
    const a = this.db.prepare("SELECT baseline_wei,injections_wei FROM actors WHERE address=?").get(address);
    if (!a) return null;
    const baseline = B(a.baseline_wei);
    const injections = B(a.injections_wei);
    const positionNow = this.latestPosition(address);
    const agg = this.db.prepare(`SELECT
        COALESCE(SUM(CAST(gas_wei AS INTEGER)),0) AS gas,
        COUNT(CASE WHEN sample=1 THEN 1 END) AS samples
      FROM flows WHERE address=?`).get(address);
    // gas summed via JS BigInt for precision (SQLite SUM over TEXT casts to float).
    const gasRows = this.db.prepare("SELECT gas_wei, ev_modeled_wei FROM flows WHERE address=?").all(address);
    let gas = 0n, evModeled = 0n;
    for (const r of gasRows) { gas += B(r.gas_wei); evModeled += B(r.ev_modeled_wei); }
    const protocolPnl = positionNow - baseline - injections + gas;
    const residual = protocolPnl - evModeled;
    return {
      address, baseline, positionNow, injections, gas, protocolPnl,
      evModeled, residual, sampleCount: agg.samples,
    };
  }

  // The per-action residual series for an actor (realized leg vs its modeled EV),
  // used by the statistical gate. Returns array of BigInt residuals per sampled action.
  sampleResiduals(address) {
    const rows = this.db.prepare(
      "SELECT value_in_wei,value_out_wei,ev_modeled_wei FROM flows WHERE address=? AND sample=1 ORDER BY id"
    ).all(address);
    // realized leg of a gamble = value_out - value_in; residual = realized - ev.
    return rows.map((r) => (B(r.value_out_wei) - B(r.value_in_wei)) - B(r.ev_modeled_wei));
  }

  actors() {
    return this.db.prepare("SELECT address,label FROM actors").all();
  }

  close() { this.db.close(); }
}
