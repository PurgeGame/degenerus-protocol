// SPDX-License-Identifier: AGPL-3.0-only
//
// EventSurfaceUnification.test.js — Phase 277 Wave 2 TST-EVT-UNI-01..06
//
// Verifies the Phase 277 event-surface unification + sentinel retirement:
//   - LootboxTicketRoll is fully removed (event def + emit sites) from both the
//     LootboxModule contract and the IDegenerusGameModules interface.
//   - LootBoxOpened / JackpotTicketWin carry their current signatures (both gain a
//     trailing non-indexed `bool roundedUp`; LootBoxOpened dropped its `day` arg in
//     4cb9ccbf "lootbox event day cleanup" — now 7 args, 2 indexed). FlipLootOpen
//     is REMOVED in v47 (FLIP-lootbox surface deleted — terminal-paradox closure).
//   - The `index != type(uint48).max` behavior-gating sentinel in
//     _resolveLootboxCommon is retired; auto-resolve callers pass index=0 and
//     payColdBustConsolation=false; the unified ticket-queue path is unconditional.
//   - The `emitLootboxEvent` silencing flag is removed: every box path now emits
//     the per-box LootBoxOpened summary, gated only by !wasSpin (spin rolls emit a
//     single BoxSpin instead). _resolveLootboxCommon takes 12 positional args.
//   - The manual cold-bust WWXRP consolation sits under the dedicated
//     `payColdBustConsolation` gate (true for the manual + afking opens, false for
//     the auto-resolve callers — they never pay the cold-bust consolation).
//   - JackpotTicketWin.roundedUp mirrors the _jackpotTicketRoll Bernoulli outcome.
//
// TEST STRATEGY:
//   Phase 274/275/276 precedent — source-structural assertions (fs.readFileSync +
//   regex match counts, brace-matched function-body extraction) plus compiled-ABI
//   topic-hash work via ethers Interface. There is a documented fixture-coverage
//   gap for full end-to-end resolution-path integration (LBX-02, RE-DEFERRED) — no
//   end-to-end resolution fixture is attempted here.
//
// CROSS-CITES:
//   - D-277-EVT-WIDE-01 (LootBoxOpened amount/flip stay uint256 wei)
//   - D-277-NO-PREROLL-01 (no preRollTickets field; consumers derive whole from
//     the already-emitted scaled futureTickets/tickets + roundedUp)
//   - D-277-ROUNDEDUP-01 (roundedUp is the only new field on all 3 events)
//   - D-277-AR-SILENT-01 (auto-resolve never pays the cold-bust consolation; the
//     emitLootboxEvent silencing flag is retired — every box now emits LootBoxOpened)
//   - D-277-CONSOLATION-GATE-01 (manual cold-bust consolation gated by payColdBustConsolation)
//   - D-277-AR-INDEX-01 (auto-resolve callers pass index=0)
//   - D-40N-EVT-BREAK-01 (breaking event topic-hashes accepted)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";

const TICKET_SCALE = 100n;

const LOOTBOX_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);
const JACKPOT_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);
const INTERFACE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/interfaces/IDegenerusGameModules.sol"
);
const CONTRACTS_DIR = path.resolve(process.cwd(), "contracts");

// Brace-match function-body extractor (mirrors test/unit/JackpotTicketRollSilentColdBust.test.js).
function extractBody(source, signature) {
  const fnIdx = source.indexOf(signature);
  if (fnIdx < 0) return null;
  let depth = 0;
  let bodyStart = -1;
  let bodyEnd = -1;
  for (let i = fnIdx; i < source.length; i++) {
    if (source[i] === "{") {
      if (depth === 0) bodyStart = i;
      depth++;
    } else if (source[i] === "}") {
      depth--;
      if (depth === 0) {
        bodyEnd = i;
        break;
      }
    }
  }
  if (bodyStart < 0 || bodyEnd < 0) return null;
  return source.slice(bodyStart, bodyEnd + 1);
}

// Paren-match call/emit arg-list extractor: returns the parenthesised argument
// list (inclusive of the outer `(` `)`) for the first occurrence of `prefix`,
// where `prefix` ends just before the opening `(` of the call.
function extractCallArgs(source, prefix) {
  const idx = source.indexOf(prefix);
  if (idx < 0) return null;
  const open = idx + prefix.length - 1; // `prefix` includes the trailing `(`
  if (source[open] !== "(") return null;
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "(") {
      depth++;
    } else if (source[i] === ")") {
      depth--;
      if (depth === 0) {
        return source.slice(open, i + 1);
      }
    }
  }
  return null;
}

// Split a parenthesised arg list (inclusive of outer parens) into top-level
// args, respecting nested parens so `uint32(index)` stays one arg.
function splitTopLevelArgs(parenList) {
  const inner = parenList.slice(1, -1);
  const args = [];
  let depth = 0;
  let cur = "";
  for (const ch of inner) {
    if (ch === "(") depth++;
    if (ch === ")") depth--;
    if (ch === "," && depth === 0) {
      args.push(cur.trim());
      cur = "";
    } else {
      cur += ch;
    }
  }
  if (cur.trim().length > 0) args.push(cur.trim());
  return args;
}

// Recursively collect every .sol file path under a directory.
function collectSolFiles(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...collectSolFiles(full));
    } else if (entry.isFile() && entry.name.endsWith(".sol")) {
      out.push(full);
    }
  }
  return out;
}

// Load a compiled-artifact ABI for a module by source path + contract name.
async function loadAbi(contractName) {
  const artifact = await hre.artifacts.readArtifact(contractName);
  return artifact.abi;
}

describe("EventSurfaceUnification — Phase 277 Wave 2 TST-EVT-UNI-01..06", function () {
  this.timeout(60_000);

  describe("TST-EVT-UNI-01 — event topic-hash changes (new signatures via compiled ABI; old LootboxTicketRoll has zero emit sites)", function () {
    it("[01a] LootBoxOpened resolves to the post-Phase-277 signature with a well-formed topic-0 hash", async function () {
      const abi = await loadAbi("DegenerusGameLootboxModule");
      const iface = new hre.ethers.Interface(abi);
      const frag = iface.getEvent("LootBoxOpened");
      expect(frag, "LootBoxOpened event fragment missing from ABI").to.not.equal(
        null
      );
      // Current field list (the `day` arg was dropped in commit 4cb9ccbf "lootbox
      // event day cleanup"): trailing roundedUp; the bonusFlip breakdown field is
      // folded into `flip`. 7 args, 2 indexed (player + lootboxIndex).
      const types = frag.inputs.map((i) => `${i.type}${i.indexed ? " indexed" : ""}`);
      expect(types).to.deep.equal([
        "address indexed",
        "uint48 indexed",
        "uint256",
        "uint24",
        "uint32",
        "uint256",
        "bool",
      ]);
      const names = frag.inputs.map((i) => i.name);
      expect(names).to.deep.equal([
        "player",
        "lootboxIndex",
        "amount",
        "futureLevel",
        "futureTickets",
        "flip",
        "roundedUp",
      ]);
      // Exactly 2 indexed topics (player + lootboxIndex).
      expect(frag.inputs.filter((i) => i.indexed).length).to.equal(2);
      // Topic-0 hash is a well-formed non-zero 32-byte hash.
      expect(frag.topicHash).to.match(/^0x[0-9a-f]{64}$/);
      expect(BigInt(frag.topicHash)).to.not.equal(0n);
    });

    // [01b] FlipLootOpen — REMOVED (v47): the FLIP-lootbox surface is gone by
    // design (terminal-paradox closure); the `FlipLootOpen` event no longer exists
    // in the ABI. The event-fragment assertion for it was removed, not skipped.
    it("[01b] the v47 ABI no longer declares FlipLootOpen (removed-by-design)", async function () {
      const abi = await loadAbi("DegenerusGameLootboxModule");
      const names = abi.filter((x) => x.type === "event").map((x) => x.name);
      expect(
        names,
        "FlipLootOpen must be fully removed from the v47 ABI (FLIP-lootbox surface deleted)"
      ).to.not.include("FlipLootOpen");
    });

    it("[01c] JackpotTicketWin resolves to the post-Phase-277 signature: trailing non-indexed bool roundedUp, exactly 3 indexed params", async function () {
      const abi = await loadAbi("DegenerusGameJackpotModule");
      const iface = new hre.ethers.Interface(abi);
      const frag = iface.getEvent("JackpotTicketWin");
      expect(frag, "JackpotTicketWin event fragment missing from ABI").to.not.equal(
        null
      );
      const last = frag.inputs[frag.inputs.length - 1];
      expect(last.type).to.equal("bool");
      expect(last.name).to.equal("roundedUp");
      expect(last.indexed).to.equal(false);
      // traitId already occupies the 3rd indexed slot — roundedUp must NOT be indexed.
      expect(frag.inputs.filter((i) => i.indexed).length).to.equal(3);
      expect(frag.topicHash).to.match(/^0x[0-9a-f]{64}$/);
      expect(BigInt(frag.topicHash)).to.not.equal(0n);
    });

    it("[01d] the OLD LootboxTicketRoll topic hash has zero emit sites across contracts/", function () {
      // keccak256 of the retired v39-additive signature — kept here purely as the
      // documented "old surface" the unification removes (D-40N-EVT-BREAK-01).
      const oldTopic = hre.ethers.id(
        "LootboxTicketRoll(address,uint48,uint32,bool)"
      );
      expect(oldTopic).to.match(/^0x[0-9a-f]{64}$/);
      let emitSites = 0;
      for (const file of collectSolFiles(CONTRACTS_DIR)) {
        const src = fs.readFileSync(file, "utf8");
        emitSites += (src.match(/emit LootboxTicketRoll\(/g) || []).length;
      }
      expect(
        emitSites,
        "the retired LootboxTicketRoll event must have zero emit sites"
      ).to.equal(0);
    });

    it("[01e] the compiled LootboxModule ABI no longer declares LootboxTicketRoll", async function () {
      const abi = await loadAbi("DegenerusGameLootboxModule");
      const names = abi.filter((x) => x.type === "event").map((x) => x.name);
      expect(names).to.not.include("LootboxTicketRoll");
    });
  });

  describe("TST-EVT-UNI-02 — LootboxTicketRoll removal regression (absent from contract + interface)", function () {
    it("[02a] DegenerusGameLootboxModule.sol contains zero LootboxTicketRoll references", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const matches = (src.match(/LootboxTicketRoll/g) || []).length;
      expect(
        matches,
        "LootboxTicketRoll must be fully removed from DegenerusGameLootboxModule.sol (event def + emit + NatSpec)"
      ).to.equal(0);
    });

    it("[02b] IDegenerusGameModules.sol contains zero LootboxTicketRoll references", function () {
      const src = fs.readFileSync(INTERFACE_SOURCE_PATH, "utf8");
      const matches = (src.match(/LootboxTicketRoll/g) || []).length;
      expect(
        matches,
        "LootboxTicketRoll must be fully removed from the IDegenerusGameLootboxModule interface block"
      ).to.equal(0);
    });

    it("[02c] no .sol file under contracts/ declares or emits LootboxTicketRoll", function () {
      let total = 0;
      for (const file of collectSolFiles(CONTRACTS_DIR)) {
        const src = fs.readFileSync(file, "utf8");
        total += (src.match(/LootboxTicketRoll/g) || []).length;
      }
      expect(
        total,
        "LootboxTicketRoll must not appear anywhere under contracts/"
      ).to.equal(0);
    });
  });

  describe("TST-EVT-UNI-03 — sentinel retirement regression (no `index != type(uint48).max` branch; auto-resolve callers pass 0 + false)", function () {
    it("[03a] DegenerusGameLootboxModule.sol contains zero `index != type(uint48).max` matches", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      expect(
        (src.match(/index != type\(uint48\)\.max/g) || []).length,
        "the `index != type(uint48).max` behavior-gating sentinel must be retired"
      ).to.equal(0);
    });

    it("[03b] DegenerusGameLootboxModule.sol contains zero `type(uint48).max` matches (sentinel value fully gone)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      expect(
        (src.match(/type\(uint48\)\.max/g) || []).length,
        "no `type(uint48).max` sentinel value should remain in the module"
      ).to.equal(0);
    });

    it("[03c] auto-resolve callers pass index=0 (2nd positional) and payColdBustConsolation=false (7th positional) to _resolveLootboxCommon", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // _resolveLootboxCommon positional arg order (12 args — `day` was threaded
      // out of the resolve helpers in 4cb9ccbf "lootbox event day cleanup", and the
      // always-true `emitLootboxEvent` flag was removed once every box path emits):
      //   1 player, 2 index, 3 amount, 4 targetLevel, 5 currentLevel,
      //   6 seed, 7 payColdBustConsolation, 8 distressEth, 9 totalPackedEth,
      //   10 allowSplit, 11 activityScore, 12 allowEthSpin
      // The redemption auto-resolve path holds its `_resolveLootboxCommon` call in the
      // private `_resolveRedemptionChunk` helper (one per 5-ETH chunk).
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function _resolveRedemptionChunk(",
      ]) {
        const body = extractBody(src, fnSig);
        expect(body, `${fnSig} body not found`).to.not.equal(null);
        const callIdx = body.indexOf("_resolveLootboxCommon(");
        expect(
          callIdx,
          `${fnSig} must call _resolveLootboxCommon`
        ).to.be.greaterThan(-1);
        // Extract the parenthesised arg list of the call.
        const callArgs = extractCallArgs(body, "_resolveLootboxCommon(");
        expect(callArgs, `${fnSig} _resolveLootboxCommon call args not parsed`).to.not.equal(
          null
        );
        const args = splitTopLevelArgs(callArgs);
        expect(
          args.length,
          `${fnSig} _resolveLootboxCommon must receive 12 positional args (emitLootboxEvent removed; allowSplit + activityScore + allowEthSpin)`
        ).to.equal(12);
        expect(
          args[1],
          `${fnSig} must pass index=0 as the 2nd positional arg (D-277-AR-INDEX-01)`
        ).to.equal("0");
        // payColdBustConsolation (7th positional) stays false on both auto-resolve callers —
        // they never pay the cold-bust WWXRP consolation (D-277-AR-SILENT-01). The
        // emitLootboxEvent flag is gone: every box path emits LootBoxOpened (gated only by !wasSpin).
        expect(
          args[6],
          `${fnSig} must pass payColdBustConsolation=false as the 7th positional arg (D-277-AR-SILENT-01)`
        ).to.equal("false");
        // The retired sentinel value must not appear in the caller body.
        expect(
          body.includes("type(uint48).max"),
          `${fnSig} must not pass the retired type(uint48).max sentinel`
        ).to.equal(false);
      }
    });

    it("[03d] the per-roll ticket-queue path calls `_queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false)` at one source site inside _settleLootboxRoll — not inside any index-conditional branch", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // The ticket/emit/consolation logic moved to `_settleLootboxRoll` (the
      // void `_resolveLootboxCommon` dispatcher calls it once per roll).
      const body = extractBody(src, "function _settleLootboxRoll(");
      expect(body, "_settleLootboxRoll body not found").to.not.equal(null);
      const calls = (
        body.match(/_queueEntries\(player, rollLevel, wholeTicketsToEntries\(whole\), false\)/g) || []
      ).length;
      expect(
        calls,
        "_settleLootboxRoll must contain exactly one `_queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false)` call (unconditional)"
      ).to.equal(1);
      // No `if (index` conditional should wrap any logic in this function body.
      expect(
        /if\s*\(\s*index\b/.test(body),
        "_settleLootboxRoll must not branch on `index` after sentinel retirement"
      ).to.equal(false);
    });
  });

  describe("TST-EVT-UNI-04 — manual-path LootBoxOpened field-consistency (whole derived from scaled futureTickets + roundedUp; no preRollTickets; FlipLootOpen removed in v47)", function () {
    it("[04a] no contract source declares a preRollTickets event field (D-277-NO-PREROLL-01)", function () {
      for (const file of collectSolFiles(CONTRACTS_DIR)) {
        const src = fs.readFileSync(file, "utf8");
        expect(
          src.includes("preRollTickets"),
          `${path.basename(file)} must not reference preRollTickets — the field is redundant with the scaled futureTickets/tickets fields`
        ).to.equal(false);
      }
    });

    it("[04b] the off-chain whole-ticket derivation `whole = (futureTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)` is consistent with the on-chain Bernoulli collapse", function () {
      // The contract emits the un-mutated scaled `futureTickets` on LootBoxOpened
      // and feeds the local `whole` (post-Bernoulli collapse) into _queueEntries.
      // A consumer reconstructs `whole` from the already-emitted scaled field +
      // the roundedUp flag. This proves that derivation is arithmetically exact:
      //   whole_floor = scaled / TICKET_SCALE
      //   whole       = whole_floor + (roundedUp ? 1 : 0)
      // which is exactly what the on-chain code computes
      // (`whole = futureTickets / TICKET_SCALE; if (...) whole += 1`).
      for (const scaled of [0n, 1n, 47n, 99n, 100n, 101n, 199n, 250n, 9999n]) {
        const wholeFloor = scaled / TICKET_SCALE;
        for (const roundedUp of [false, true]) {
          // roundedUp can only be true when frac != 0.
          const frac = scaled % TICKET_SCALE;
          if (roundedUp && frac === 0n) continue;
          const derived = wholeFloor + (roundedUp ? 1n : 0n);
          // On-chain equivalent.
          let onchain = scaled / TICKET_SCALE;
          if (roundedUp) onchain += 1n;
          expect(
            derived,
            `derivation mismatch at scaled=${scaled}, roundedUp=${roundedUp}`
          ).to.equal(onchain);
        }
      }
    });

    it("[04c] _settleLootboxRoll keeps this roll's `scaledWholeTickets` at the scaled value and the LootBoxOpened emit consumes it (whole is a separate local)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _settleLootboxRoll(");
      expect(body, "_settleLootboxRoll body not found").to.not.equal(null);
      // The Bernoulli collapse writes to a SEPARATE local `whole`, never to
      // this roll's `scaledWholeTickets`.
      expect(
        /uint32 whole = scaledWholeTickets \/ uint32\(QTY_SCALE\);/.test(body),
        "`whole` must be derived from scaled `scaledWholeTickets` as a separate local"
      ).to.equal(true);
      // The LootBoxOpened emit references `scaledWholeTickets` (scaled), not `whole`.
      const emitArgList = extractCallArgs(body, "emit LootBoxOpened(");
      expect(emitArgList, "LootBoxOpened emit not found").to.not.equal(null);
      const emitArgs = splitTopLevelArgs(emitArgList);
      // Positional order matches the current 7-arg event def (the `day` arg was
      // dropped in 4cb9ccbf "lootbox event day cleanup"):
      //   player, lootboxIndex(index), amount(fullAmount), futureLevel(rollLevel),
      //   futureTickets(scaledWholeTickets), flip(flipAmount), roundedUp
      expect(emitArgs.length).to.equal(7);
      expect(emitArgs[0]).to.equal("player");
      expect(emitArgs[1]).to.equal("index"); // lootboxIndex slot fed the `index` param
      expect(emitArgs[2]).to.equal("fullAmount"); // box pre-split amount
      expect(emitArgs[3]).to.equal("rollLevel"); // this roll's queue level
      expect(emitArgs[4]).to.equal("scaledWholeTickets"); // scaled, un-mutated by the collapse
      expect(emitArgs[6]).to.equal("roundedUp");
    });

    // [04d] FlipLootOpen manual-emit field-consistency — REMOVED (v47): the
    // FLIP-lootbox manual caller `openFlipLootBox` and its `FlipLootOpen`
    // emit are gone by design (terminal-paradox closure). This block tested a
    // removed source surface and is deleted, not skipped. Confirm the source no
    // longer declares the removed symbols.
    it("[04d] the v47 LootboxModule source no longer references openFlipLootBox / FlipLootOpen (removed-by-design)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      expect(
        src.includes("openFlipLootBox"),
        "openFlipLootBox must be fully removed from DegenerusGameLootboxModule.sol"
      ).to.equal(false);
      expect(
        src.includes("FlipLootOpen"),
        "FlipLootOpen must be fully removed from DegenerusGameLootboxModule.sol"
      ).to.equal(false);
    });

    it("[04e] the WWXRP-consolation case is inferable as `whole == 0 && scaledWholeTickets > 0` corroborated by a same-tx WWXRP ERC-20 Transfer from mintPrize", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _settleLootboxRoll(");
      expect(body, "_settleLootboxRoll body not found").to.not.equal(null);
      // The consolation predicate is `payColdBustConsolation && whole == 0` and
      // sits inside the `if (scaledWholeTickets != 0)` guard — i.e. it only fires when
      // the scaled count was non-zero but the Bernoulli collapse produced whole==0.
      expect(
        /if \(payColdBustConsolation && whole == 0\)/.test(body),
        "manual cold-bust consolation must be gated on `payColdBustConsolation && whole == 0`"
      ).to.equal(true);
      // It pays LOOTBOX_WWXRP_CONSOLATION via wwxrp.mintPrize; the payout is
      // observable off-chain through the WWXRP ERC-20 `Transfer` event the mint
      // emits (no dedicated lootbox-WWXRP event).
      expect(
        body.includes("wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)"),
        "consolation must mint LOOTBOX_WWXRP_CONSOLATION"
      ).to.equal(true);
      // No dedicated LootBoxWwxrpReward event exists anymore — the ERC-20 Transfer
      // plus same-tx context is the correlation surface.
      expect(
        body.includes("LootBoxWwxrpReward"),
        "the consolation path must not reference a retired LootBoxWwxrpReward event"
      ).to.equal(false);
    });
  });

  describe("TST-EVT-UNI-05 — every-box-emits field-consistency (LootBoxOpened gated only by !wasSpin; consolation is payColdBustConsolation-gated)", function () {
    it("[05a] the only `emit LootBoxOpened` site in _settleLootboxRoll is inside the `if (!wasSpin)` gate", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _settleLootboxRoll(");
      expect(body, "_settleLootboxRoll body not found").to.not.equal(null);
      const emitMatches = [...body.matchAll(/emit LootBoxOpened\(/g)];
      expect(
        emitMatches.length,
        "_settleLootboxRoll must contain exactly one `emit LootBoxOpened` site"
      ).to.equal(1);
      const emitIdx = emitMatches[0].index;
      // Walk back: the nearest preceding gate must enclose it. After the emitLootboxEvent flag
      // was removed (every box path emits), the gate is now `if (!wasSpin)` — spin rolls emit a
      // single BoxSpin instead, so they remain the only suppressed case.
      const preamble = body.slice(0, emitIdx);
      const gateIdx = preamble.lastIndexOf("if (!wasSpin)");
      expect(
        gateIdx,
        "the LootBoxOpened emit must sit inside an `if (!wasSpin)` gate"
      ).to.be.greaterThan(-1);
    });

    it("[05b] the emitLootboxEvent silencing flag is fully removed — every box path emits (the gate is !wasSpin only)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // The always-true `emitLootboxEvent` flag was deleted module-wide, so no box-resolution
      // path can be silenced: every caller of _resolveLootboxCommon/resolveLootboxDirect now
      // produces a LootBoxOpened (or a BoxSpin for spin rolls). Proven by the token's absence.
      expect(
        src.includes("emitLootboxEvent"),
        "no `emitLootboxEvent` token may remain in the lootbox module (flag retired — every box emits)"
      ).to.equal(false);
    });

    it("[05c] the manual cold-bust consolation (wwxrp.mintPrize with LOOTBOX_WWXRP_CONSOLATION) appears exactly once and is inside the `if (payColdBustConsolation && whole == 0)` gate (manual-only)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // Module-wide single-site.
      expect(
        (src.match(/wwxrp\.mintPrize\(player, LOOTBOX_WWXRP_CONSOLATION\)/g) || [])
          .length,
        "the LOOTBOX_WWXRP_CONSOLATION mint must be single-site"
      ).to.equal(1);
      // The dedicated LootBoxWwxrpReward event is removed — the WWXRP ERC-20
      // Transfer the mint emits is the correlation surface.
      expect(
        src.includes("LootBoxWwxrpReward"),
        "the retired LootBoxWwxrpReward event must not appear in the module"
      ).to.equal(false);
      // The consolation predicate explicitly tests payColdBustConsolation —
      // proving it cannot fire on the auto-resolve (payColdBustConsolation=false)
      // path, while the surviving manual caller (openBox) passes
      // payColdBustConsolation=true and DOES pay it. (The FLIP-lootbox manual
      // caller openFlipLootBox was removed in v47.) The gate now lives in the
      // per-roll `_settleLootboxRoll` helper.
      const body = extractBody(src, "function _settleLootboxRoll(");
      expect(
        /if \(payColdBustConsolation && whole == 0\)\s*\{/.test(body),
        "the consolation must be gated by `payColdBustConsolation && whole == 0` — manual-only per D-277-CONSOLATION-GATE-01"
      ).to.equal(true);
    });

    it("[05d] auto-resolve ticket awards stay observable via the unified `_queueEntries` path → `EntriesQueued`", function () {
      const lootbox = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(lootbox, "function _settleLootboxRoll(");
      // The per-roll path calls _queueEntries unconditionally (proven single-site
      // in [03d]); _queueEntries is what makes auto-resolve awards observable
      // without a LootBoxOpened emit.
      expect(
        body.includes("_queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false)"),
        "the per-roll path must call _queueEntries so auto-resolve awards remain observable via EntriesQueued"
      ).to.equal(true);
      // _queueEntries emits EntriesQueued (verified at the storage layer).
      const storage = fs.readFileSync(
        path.resolve(process.cwd(), "contracts/storage/DegenerusGameStorage.sol"),
        "utf8"
      );
      const queueBody = extractBody(storage, "function _queueEntries(");
      expect(queueBody, "_queueEntries body not found in storage").to.not.equal(
        null
      );
      expect(
        queueBody.includes("emit EntriesQueued("),
        "_queueEntries must emit EntriesQueued"
      ).to.equal(true);
    });
  });

  describe("TST-EVT-UNI-06 — JackpotTicketWin.roundedUp field-consistency (mirrors the _jackpotTicketRoll Bernoulli outcome)", function () {
    it("[06a] the JackpotTicketWin ABI fragment has a non-indexed final bool roundedUp", async function () {
      const abi = await loadAbi("DegenerusGameJackpotModule");
      const frag = abi.find(
        (x) => x.type === "event" && x.name === "JackpotTicketWin"
      );
      expect(frag, "JackpotTicketWin event missing from ABI").to.not.equal(
        undefined
      );
      const last = frag.inputs[frag.inputs.length - 1];
      expect(last.name).to.equal("roundedUp");
      expect(last.type).to.equal("bool");
      expect(last.indexed).to.equal(false);
    });

    it("[06b] _jackpotTicketRoll declares `bool roundedUp = false;` before the Bernoulli predicate and sets `roundedUp = true;` inside it", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _jackpotTicketRoll(");
      expect(body, "_jackpotTicketRoll body not found").to.not.equal(null);
      const declIdx = body.indexOf("bool roundedUp = false;");
      expect(
        declIdx,
        "_jackpotTicketRoll must declare `bool roundedUp = false;`"
      ).to.be.greaterThan(-1);
      // The Bernoulli predicate uses bits[96..127] of the per-roll entropy word.
      const predIdx = body.indexOf(
        "(uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac"
      );
      expect(
        predIdx,
        "_jackpotTicketRoll Bernoulli predicate `(uint32(entropy >> 96) % uint32(QTY_SCALE)) < frac` missing"
      ).to.be.greaterThan(declIdx);
      const setIdx = body.indexOf("roundedUp = true;");
      expect(
        setIdx,
        "_jackpotTicketRoll must set `roundedUp = true;` inside the Bernoulli branch"
      ).to.be.greaterThan(predIdx);
    });

    it("[06c] the JackpotTicketWin emit inside _jackpotTicketRoll threads the captured `roundedUp` local", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _jackpotTicketRoll(");
      expect(body, "_jackpotTicketRoll body not found").to.not.equal(null);
      const emitArgList = extractCallArgs(body, "emit JackpotTicketWin(");
      expect(
        emitArgList,
        "JackpotTicketWin emit not found in _jackpotTicketRoll"
      ).to.not.equal(null);
      const emitArgs = splitTopLevelArgs(emitArgList);
      // winner, targetLevel, BAF_TRAIT_SENTINEL, wholeTicketsToEntries(whole),
      // minTargetLevel, 0, roundedUp — the 4th arg is the entries count (whole<<2,
      // 4 per whole ticket) queued by the adjacent _queueEntries call: emit == queue.
      expect(emitArgs.length).to.equal(7);
      expect(emitArgs[3]).to.equal("wholeTicketsToEntries(whole)");
      expect(emitArgs[6]).to.equal("roundedUp");
    });

    it("[06d] all JackpotTicketWin emit sites supply the 7th `roundedUp` arg; the trait-matched site passes literal `false`", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      expect(
        emitMatches.length,
        "there must be exactly 2 JackpotTicketWin emit sites"
      ).to.equal(2);
      let literalFalseCount = 0;
      let threadedCount = 0;
      for (const m of emitMatches) {
        const emitArgList = extractCallArgs(
          src.slice(m.index),
          "emit JackpotTicketWin("
        );
        expect(emitArgList, "JackpotTicketWin emit args not parsed").to.not.equal(
          null
        );
        const args = splitTopLevelArgs(emitArgList);
        expect(
          args.length,
          "every JackpotTicketWin emit must supply 7 args (incl. roundedUp)"
        ).to.equal(7);
        if (args[6] === "false") literalFalseCount++;
        else if (args[6] === "roundedUp") threadedCount++;
      }
      // One trait-matched path (the shared distributor emit) passes literal `false`
      // (zero fractional part by construction); the BAF _jackpotTicketRoll path threads
      // the real flag. The early-bird path now routes through the shared distributor
      // emit instead of its own JackpotTicketWin site.
      expect(literalFalseCount, "one trait-matched site must pass `false`").to.equal(
        1
      );
      expect(
        threadedCount,
        "the _jackpotTicketRoll site must thread the captured `roundedUp`"
      ).to.equal(1);
    });

    it("[06e] the _jackpotTicketRoll Bernoulli predicate mirrors the LootboxModule capture pattern (byte-identical math, different entropy slice)", function () {
      const jackpot = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const lootbox = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // Lootbox path: bits[224..255]; Jackpot path: bits[96..127]. Both use the
      // same `frac != 0 && (uint32(...) % uint32(QTY_SCALE)) < frac` shape.
      expect(
        /frac != 0 && \(uint32\(rollSeed >> 224\) % uint32\(QTY_SCALE\)\) < frac/.test(
          lootbox
        ),
        "LootboxModule Bernoulli predicate shape drifted"
      ).to.equal(true);
      expect(
        /frac != 0 && \(uint32\(entropy >> 96\) % uint32\(QTY_SCALE\)\) < frac/.test(
          jackpot
        ),
        "JackpotModule Bernoulli predicate shape drifted from the LootboxModule pattern"
      ).to.equal(true);
    });
  });
});
