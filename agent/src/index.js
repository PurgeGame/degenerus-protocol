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

  let i = 0;
  while (!stop && (steps === 0 || i < steps)) {
    const r = await agent.tick();
    if (envDriver && i % driveEvery === driveEvery - 1) {
      const d = await envDriver.driveDay();
      if ((i + 1) % (driveEvery * 4) === 0) console.log(`[env] day driven: level=${d.level} advanced=${d.advanced} vrf=${d.vrf.fulfilled}`);
    }
    if ((i + 1) % 25 === 0) {
      const s = agent.stats;
      console.log(`[agent] step ${i + 1}: actions=${s.actions} reverts=${s.reverts} ` +
        `stateViol=${s.stateViolations} profitAlarms=${s.profitAlarms} findings=${s.findings}`);
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
