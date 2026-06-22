// Pure-logic unit tests (no chain) — runnable in CI via `node --test`.
// Covers the ledger P&L math, the statistical gate, the EV model, and the
// shape of the shared MAN-01 manifest + by-design allowlist.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, rmSync } from "node:fs";
import { resolve } from "node:path";
import { Ledger } from "../src/ledger.js";
import { Gate } from "../src/gate.js";
import { Pricing } from "../src/pricing.js";
import { AGENT_ROOT } from "../src/config.js";

const tmpDb = resolve(AGENT_ROOT, ".state/unit-test.db");

test("ledger: protocolPnl = position - baseline - injections + gas; residual vs EV", () => {
  rmSync(tmpDb, { force: true }); rmSync(tmpDb + "-wal", { force: true }); rmSync(tmpDb + "-shm", { force: true });
  const l = new Ledger(tmpDb);
  l.ensureActor("0xA", "alice");
  l.snapshot("0xA", 1, 0, 1000n);           // baseline = 1000
  l.recordInjection("0xA", 100n);           // faucet 100 (not winnings)
  // a gamble: staked 50, paid 70, modeled EV net = -5 (house edge)
  l.recordAction({ address: "0xA", action: "bet", block: 2, valueInWei: 50n, valueOutWei: 70n, evModeledWei: -5n, gasWei: 3n, sample: true });
  l.snapshot("0xA", 3, 0, 1070n);           // position now 1070
  const p = l.pnl("0xA");
  // protocolPnl = 1070 - 1000 - 100 + 3 = -27
  assert.equal(p.protocolPnl, -27n);
  assert.equal(p.evModeled, -5n);
  assert.equal(p.residual, -22n);           // -27 - (-5)
  // sample residual = (70 - 50) - (-5) = 25
  assert.deepEqual(l.sampleResiduals("0xA"), [25n]);
  l.close();
});

test("gate: no alarm when realized ≈ EV; alarm when profit > kσ", () => {
  rmSync(tmpDb, { force: true }); rmSync(tmpDb + "-wal", { force: true }); rmSync(tmpDb + "-shm", { force: true });
  const l = new Ledger(tmpDb);
  const allow = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/allowlist.json"), "utf8"));
  const gate = new Gate(allow, { kSigma: 4, minSample: 50, dustWei: 1000 });
  l.ensureActor("0xB");
  l.snapshot("0xB", 1, 0, 0n);
  // 200 fair-ish gambles: realized ≈ EV (residual mean ~0, small noise)
  for (let i = 0; i < 200; i++) {
    const out = i % 2 === 0 ? 11n : 9n; // alternates around 10
    l.recordAction({ address: "0xB", action: "bet", block: i, valueInWei: 10n, valueOutWei: out, evModeledWei: 0n, gasWei: 0n, sample: true });
  }
  l.snapshot("0xB", 999, 0, 0n);
  const fair = gate.evaluateProfit(l, "0xB");
  assert.equal(fair.alarm, false, fair.reason);

  // a cheater: every gamble pays far above EV
  l.ensureActor("0xC");
  l.snapshot("0xC", 1, 0, 0n);
  for (let i = 0; i < 200; i++) {
    l.recordAction({ address: "0xC", action: "bet", block: i, valueInWei: 10n, valueOutWei: 1_000_000_000_000n, evModeledWei: 0n, gasWei: 0n, sample: true });
  }
  l.snapshot("0xC", 999, 0, 200n * 1_000_000_000_000n);
  const cheat = gate.evaluateProfit(l, "0xC");
  assert.equal(cheat.alarm, true, "a persistent above-EV winner must alarm");
  l.close();
});

test("gate: state (conservation) violations are never allowlisted", () => {
  const allow = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/allowlist.json"), "utf8"));
  const gate = new Gate(allow, {});
  const cls = gate.classifyStateViolation({ id: "SOLV-01-ETH-SOLVENCY", severity: "critical" });
  assert.equal(cls.real, true);
  assert.equal(cls.allowlisted, false);
});

test("gate: allowlist matches by-design channels", () => {
  const allow = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/allowlist.json"), "utf8"));
  const gate = new Gate(allow, {});
  assert.ok(gate.matchAllowlist({ action: "sellFarFutureTickets" }), "salvage swap is allowlisted");
  assert.ok(gate.matchAllowlist({ action: "burn" }), "redemption burn is allowlisted");
  assert.ok(gate.matchAllowlist({ action: "purchase", foil: true }), "foil subsidy is allowlisted");
  assert.equal(gate.matchAllowlist({ action: "purchase", foil: false, actorFlags: {} }), null, "a plain purchase is not by-design profit");
});

test("gate: gas-viability is annotated separately from extraction", () => {
  const gate = new Gate({ entries: [] }, {});
  const tiny = gate.gasViability(5n, 100n); // extraction smaller than gas
  assert.equal(tiny.mainnetGasViable, false);
  const real = gate.gasViability(1_000_000n, 100n);
  assert.equal(real.mainnetGasViable, true);
});

test("pricing: honest ROI strictly <100%, WWXRP RTP floor 70%, rises with activity", () => {
  const p = new Pricing(null);
  assert.equal(p.honestRoiBps(0), 9000n);
  assert.ok(p.honestRoiBps(305) <= 9990n && p.honestRoiBps(305) >= 9000n);
  assert.ok(p.honestRoiBps(1000) <= 9990n, "ROI clamps below 100%");
  assert.ok(p.wwxrpRoiBps(0) >= 7000n, "WWXRP floor 70%");
  assert.ok(p.wwxrpRoiBps(305) > p.wwxrpRoiBps(0), "WWXRP RTP rises with activity");
  const ev = p.modelDegeneretteEv(1000n, 0, 0);
  assert.ok(ev.evNetWei <= 0n, "honest Degenerette EV is non-positive (house edge ≥ 0)");
});

test("manifest: MAN-01 has the full 28-invariant oracle set, each well-formed", () => {
  const man = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/invariants.json"), "utf8"));
  assert.equal(man.manifestId, "MAN-01");
  assert.equal(man.invariants.length, 28);
  for (const i of man.invariants) {
    for (const k of ["id", "category", "identity", "onchainRead", "comparator", "source"]) {
      assert.ok(i[k] && String(i[k]).length > 0, `${i.id} missing ${k}`);
    }
  }
  // the load-bearing solvency + rig invariants are present
  const ids = man.invariants.map((i) => i.id);
  for (const must of ["SOLV-01-ETH-SOLVENCY", "SOLV-05-CLAIMABLE-BACKED", "REDEEM-01-ETH-SEGREGATION",
    "FSM-03-NO-BRICK-LIVENESS", "DEG-03-WWXRP-RIG-NEVER-S9"]) {
    assert.ok(ids.includes(must), `manifest must include ${must}`);
  }
});

test("allowlist: 13 by-design entries, each with a reason", () => {
  const allow = JSON.parse(readFileSync(resolve(AGENT_ROOT, "manifest/allowlist.json"), "utf8"));
  assert.equal(allow.entries.length, 13);
  for (const e of allow.entries) {
    assert.ok(e.id && e.name && e.whyByDesign, `allowlist entry ${e.id} malformed`);
  }
});
