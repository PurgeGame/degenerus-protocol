#!/usr/bin/env node
/**
 * PARI ABI surface gate.
 *
 * The parimutuel is a growth-only market: the ticket-volume book was excised, and its
 * seven methods and three events must never come back — not as a shim, not as a view, not
 * as a tombstone. This gate pins BOTH directions against the compiled artifact:
 *
 *   PARI-01  a retained growth method/event is missing or its selector/topic changed
 *   PARI-02  a removed volume method/event is present again
 *   PARI-03  a method/event exists that is in neither list (unreviewed surface growth)
 *
 * Comparison is over exact key/value sets from `forge inspect --json`, never substring
 * presence. Read-only: touches no artifact and no deployment ABI.
 *
 * Usage:
 *   node scripts/check-parimutuel-abi.js
 *   node scripts/check-parimutuel-abi.js --handoff docs/VOLUME-BET-REMOVAL-HANDOFF.md
 *
 * The --handoff mode additionally asserts the named Markdown file documents every
 * retained AND removed signature with its selector/topic, so the consumer handoff cannot
 * drift from the live surface it describes.
 */

import { spawnSync } from "node:child_process";
import fs from "node:fs";

const CONTRACT = "DegenerusParimutuel";

// The exact retained growth surface.
const KEEP_METHODS = {
  "QUEST_BASE()": "9e4a23f2",
  "STAKE()": "125fdbbc",
  "claim(address,uint24[])": "fbdc1e8a",
  "claimRound(uint24,address[])": "30c194e5",
  "marketState(address,uint24)": "c1ca0ce7",
  "placeBet(address,bool)": "d7604ca3",
  "recordGrowth(uint24,bool)": "a126a091",
};

const KEEP_EVENTS = {
  "BetClaimed(address,uint24,uint8,uint256)":
    "0xfe51f04082426a2a3607b3158e84cf13b31ef5e3d39a6700d249479a916bfdd4",
  "BetPlaced(address,uint24,bool,uint256)":
    "0x8e0aa1e952464967d9730a4e1121dc8ac73d06d1ac109c983c8da3a77598170b",
  "GrowthRoundSealed(uint24,bool)":
    "0xca3ee902860d838642f9002bad6dfde77682e901e6c518ef99504d6d98b9f9a3",
};

// The excised volume surface. Present again = the removal regressed.
const GONE_METHODS = {
  "VOLUME_BET_CREDIT()": "a7f2de31",
  "placeVolumeBet(address,bool)": "65e372dd",
  "volumeBetCredit()": "9d59bf27",
  "claimVolume(address,uint24[])": "6ac5a3b5",
  "claimVolumeRound(uint24,address[])": "2e6b6f33",
  "volumeMarketState(address,uint24)": "520739bb",
  "recordVolume(uint24,uint48)": "6461c74a",
};

const GONE_EVENTS = {
  "VolumeBetClaimed(address,uint24,uint8,uint256)":
    "0xd2d6f656c40e54ce22fa3351150754d677fa61a78b6b066e1105b5b9f4810aae",
  "VolumeBetPlaced(address,uint24,bool,uint256)":
    "0xb256da398c4ed44de896917570681f2d47e0286f38253b3558d43de77105cf3c",
  "VolumeRoundSealed(uint24,uint48,uint48)":
    "0x0655c621883298d79dfd9499016ff1f0e8215d2efc7661206c7f43e38269cde4",
};

const failures = [];
const fail = (code, msg) => failures.push(`${code} ${msg}`);

function inspect(field) {
  const r = spawnSync(
    "forge",
    ["inspect", CONTRACT, field, "--json"],
    { encoding: "utf8", env: { ...process.env, FOUNDRY_DISABLE_NIGHTLY_WARNING: "1" } }
  );
  if (r.error) {
    console.error(`FAIL forge inspect ${field} could not run: ${r.error.message}`);
    process.exit(1);
  }
  if (r.status !== 0) {
    console.error(`FAIL forge inspect ${CONTRACT} ${field} exited ${r.status}`);
    if (r.stderr) console.error(r.stderr.trim());
    process.exit(1);
  }
  let parsed;
  try {
    parsed = JSON.parse(r.stdout);
  } catch (e) {
    console.error(`FAIL forge inspect ${field} returned malformed JSON: ${e.message}`);
    process.exit(1);
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    console.error(`FAIL forge inspect ${field} returned an unexpected shape`);
    process.exit(1);
  }
  return parsed;
}

/** Exact set comparison in both directions, plus the removed-surface assertion. */
function compare(kind, live, keep, gone) {
  for (const [sig, expected] of Object.entries(keep)) {
    if (!(sig in live)) {
      fail("PARI-01", `${kind} missing: ${sig}`);
    } else if (String(live[sig]).toLowerCase() !== expected.toLowerCase()) {
      fail(
        "PARI-01",
        `${kind} changed: ${sig} is ${live[sig]}, expected ${expected}`
      );
    }
  }
  for (const sig of Object.keys(gone)) {
    if (sig in live) fail("PARI-02", `removed ${kind} is present again: ${sig}`);
  }
  for (const sig of Object.keys(live)) {
    if (!(sig in keep) && !(sig in gone)) {
      fail("PARI-03", `unexpected ${kind} (not in the reviewed surface): ${sig}`);
    }
  }
}

const methods = inspect("methods");
const events = inspect("events");
compare("method", methods, KEEP_METHODS, GONE_METHODS);
compare("event", events, KEEP_EVENTS, GONE_EVENTS);

// --handoff: the consumer document must carry the same canonical arrays.
const handoffIdx = process.argv.indexOf("--handoff");
let handoffPath = null;
if (handoffIdx !== -1) {
  handoffPath = process.argv[handoffIdx + 1];
  if (!handoffPath) {
    console.error("FAIL --handoff requires a file path");
    process.exit(1);
  }
  if (!fs.existsSync(handoffPath)) {
    console.error(`FAIL --handoff file not found: ${handoffPath}`);
    process.exit(1);
  }
  const doc = fs.readFileSync(handoffPath, "utf8");
  const need = (label, table) => {
    for (const [sig, id] of Object.entries(table)) {
      if (!doc.includes(sig)) fail("PARI-04", `${label} signature absent from handoff: ${sig}`);
      const bare = id.startsWith("0x") ? id.slice(2) : id;
      if (!doc.toLowerCase().includes(bare.toLowerCase())) {
        fail("PARI-04", `${label} selector/topic absent from handoff: ${sig} -> ${id}`);
      }
    }
  };
  need("retained method", KEEP_METHODS);
  need("retained event", KEEP_EVENTS);
  need("removed method", GONE_METHODS);
  need("removed event", GONE_EVENTS);
}

console.log("Parimutuel ABI surface gate");
console.log("===========================");
if (failures.length) {
  for (const f of failures) console.error(`FAIL ${f}`);
  console.error(
    `\nFAIL ${failures.length} surface mismatch(es) — the growth-only ABI contract is broken`
  );
  process.exit(1);
}
console.log(
  `PASS ${Object.keys(KEEP_METHODS).length} methods / ${Object.keys(KEEP_EVENTS).length} events exactly, ` +
    `${Object.keys(GONE_METHODS).length} methods / ${Object.keys(GONE_EVENTS).length} events confirmed absent` +
    (handoffPath ? `, handoff ${handoffPath} in sync` : "")
);
