#!/usr/bin/env node
// CLI entry for the connect-and-play adversarial agent.
//
//   node agent/src/index.js [--mode local|live] [--steps N] [--drive-every K]
//
// mode=local : interleaves the DEV env-driver (warp + honest VRF + honest actors)
//              with the agent campaign — the BUILD/validation path.
// mode=live  : connects to the running 15-min-day testnet, starts the mempool
//              watcher, and soaks. NEVER runs the dev-driver (external attacker).

import { loadConfig } from "./config.js";
import { Agent } from "./agent.js";
import { MempoolWatcher } from "./mempool.js";

function parseArgs(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--mode") o.mode = argv[++i];
    else if (a === "--steps") o.steps = Number(argv[++i]);
    else if (a === "--drive-every") o.driveEvery = Number(argv[++i]);
    else if (a === "--k-sigma") o.kSigma = Number(argv[++i]);
  }
  return o;
}

async function main() {
  // Soak resilience: a 24/7 run against a hosted RPC WILL hit transient errors
  // (timeouts, 429 rate limits, expiring filters). Node terminates on an
  // unhandled rejection by default; log-and-continue keeps the soak alive. Real
  // findings are still recorded to disk per tick, so survivability never masks a
  // genuine invariant break.
  process.on("unhandledRejection", (reason) => {
    console.error("[agent] unhandledRejection (continuing):", reason?.shortMessage || reason?.message || reason);
  });
  process.on("uncaughtException", (err) => {
    console.error("[agent] uncaughtException (continuing):", err?.shortMessage || err?.message || err);
  });

  const opts = parseArgs(process.argv.slice(2));
  const overrides = {};
  if (opts.mode) overrides.mode = opts.mode;
  if (opts.steps != null) overrides.campaign = { maxTicks: opts.steps };
  if (opts.kSigma != null) overrides.gate = { kSigma: opts.kSigma };
  const cfg = loadConfig(overrides);
  const steps = cfg.campaign.maxTicks || 0;
  const driveEvery = opts.driveEvery ?? 5;

  console.log(`[agent] mode=${cfg.mode} rpc=${cfg.rpcUrl} steps=${steps || "∞"} kσ=${cfg.gate.kSigma}`);
  const agent = new Agent(cfg);
  const boot = await agent.init();
  console.log(`[agent] connected @ block ${boot.block}; actors=${boot.actors.length}` +
    (boot.resumedFrom ? `; resumed from block ${boot.resumedFrom}` : ""));

  let envDriver = null;
  let mempool = null;
  if (cfg.mode === "local" && cfg.devDriver.enabled) {
    const { EnvDriver } = await import("../dev/env-driver.js");
    envDriver = new EnvDriver(agent.conn, cfg, agent.pool);
    console.log("[agent] DEV env-driver active (local stand-in for the sim repo)");
  } else {
    mempool = new MempoolWatcher(agent.conn);
    const sub = await mempool.start((t) => { /* targets used by live MEV probes */ });
    console.log(`[agent] mempool watcher ${sub ? "subscribed" : "unavailable on this RPC"}`);
  }

  let stop = false;
  const shutdown = () => { stop = true; };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Hard per-tick watchdog: bound a whole tick so any hang the per-tx/per-request
  // timeouts miss (a stuck oracle read, window probe, mempool contention) can't
  // wedge the single-threaded soak forever. A tick does <=2 txs, so its worst
  // case under the action timeouts is well under this ceiling.
  const TICK_TIMEOUT_MS = 200_000;
  const withTimeout = (p, ms, label) => {
    let t; const to = new Promise((_, rej) => { t = setTimeout(() => rej(new Error(`${label} timeout`)), ms); });
    return Promise.race([p, to]).finally(() => clearTimeout(t));
  };

  let i = 0;
  let consecErrors = 0;
  while (!stop && (steps === 0 || i < steps)) {
    try {
      await withTimeout(agent.tick(), TICK_TIMEOUT_MS, "tick");
      consecErrors = 0;
      if (envDriver && i % driveEvery === driveEvery - 1) {
        const d = await envDriver.driveDay();
        if ((i + 1) % (driveEvery * 4) === 0) console.log(`[env] day driven: level=${d.level} advanced=${d.advanced} vrf=${d.vrf.fulfilled}`);
      }
    } catch (e) {
      consecErrors++;
      console.error(`[agent] tick ${i + 1} error (continuing, streak=${consecErrors}):`, e?.shortMessage || e?.message || e);
      // A hung/abandoned tick may have left NonceManagers mid-flight — re-sync.
      try { agent.pool.resetNonces(); } catch { /* */ }
      // Linear backoff capped at 30s so an RPC outage doesn't hot-loop.
      await new Promise((res) => setTimeout(res, Math.min(30000, 1000 * consecErrors)));
    }
    if ((i + 1) % 25 === 0) {
      const s = agent.stats;
      console.log(`[agent] step ${i + 1}: actions=${s.actions} reverts=${s.reverts} ` +
        `stateViol=${s.stateViolations} windowTransients=${s.windowTransients} profitAlarms=${s.profitAlarms} findings=${s.findings}`);
    }
    i++;
  }

  mempool?.stop();
  const finalCheck = await agent.oracle.checkState();
  console.log("\n=== campaign summary ===");
  console.log(JSON.stringify(agent.stats, null, 2));
  console.log(`final on-chain MAN-01 STATE violations: ${finalCheck.violations.length}`);
  if (finalCheck.violations.length) console.log(JSON.stringify(finalCheck.violations, null, 2));
  console.log(`findings recorded under: ${cfg.records.dir}`);
  agent.close();
  process.exit(0);
}

main().catch((e) => { console.error("[agent] fatal:", e); process.exit(1); });
