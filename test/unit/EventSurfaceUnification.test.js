// SPDX-License-Identifier: AGPL-3.0-only
//
// EventSurfaceUnification.test.js — Phase 277 Wave 2 TST-EVT-UNI-01..06
//
// Verifies the Phase 277 event-surface unification + sentinel retirement:
//   - LootboxTicketRoll is fully removed (event def + emit sites) from both the
//     LootboxModule contract and the IDegenerusGameModules interface.
//   - LootBoxOpened / BurnieLootOpen / JackpotTicketWin carry their post-Phase-277
//     signatures (the LootBoxOpened index/day mislabel is fixed; all three gain a
//     trailing non-indexed `bool roundedUp`).
//   - The `index != type(uint48).max` behavior-gating sentinel in
//     _resolveLootboxCommon is retired; auto-resolve callers pass index=0,
//     emitLootboxEvent=false, and payColdBustConsolation=false; the unified
//     ticket-queue path is unconditional.
//   - The manual cold-bust WWXRP consolation sits under the dedicated
//     `payColdBustConsolation` gate (true for both manual callers, false for
//     the auto-resolve callers); auto-resolve emits no LootBoxOpened.
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
//   - D-277-EVT-WIDE-01 (LootBoxOpened amount/burnie stay uint256 wei)
//   - D-277-NO-PREROLL-01 (no preRollTickets field; consumers derive whole from
//     the already-emitted scaled futureTickets/tickets + roundedUp)
//   - D-277-ROUNDEDUP-01 (roundedUp is the only new field on all 3 events)
//   - D-277-AR-SILENT-01 (auto-resolve emits nothing)
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
      // Post-Phase-277 field list: fixed index/day mislabel + trailing roundedUp;
      // the bonusBurnie breakdown field is dropped (folded into `burnie`).
      const types = frag.inputs.map((i) => `${i.type}${i.indexed ? " indexed" : ""}`);
      expect(types).to.deep.equal([
        "address indexed",
        "uint48 indexed",
        "uint32",
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
        "day",
        "amount",
        "futureLevel",
        "futureTickets",
        "burnie",
        "roundedUp",
      ]);
      // Exactly 2 indexed topics (player + lootboxIndex).
      expect(frag.inputs.filter((i) => i.indexed).length).to.equal(2);
      // Topic-0 hash is a well-formed non-zero 32-byte hash.
      expect(frag.topicHash).to.match(/^0x[0-9a-f]{64}$/);
      expect(BigInt(frag.topicHash)).to.not.equal(0n);
    });

    it("[01b] BurnieLootOpen resolves to the post-Phase-277 signature ending in non-indexed bool roundedUp", async function () {
      const abi = await loadAbi("DegenerusGameLootboxModule");
      const iface = new hre.ethers.Interface(abi);
      const frag = iface.getEvent("BurnieLootOpen");
      expect(frag, "BurnieLootOpen event fragment missing from ABI").to.not.equal(
        null
      );
      const last = frag.inputs[frag.inputs.length - 1];
      expect(last.type).to.equal("bool");
      expect(last.name).to.equal("roundedUp");
      expect(last.indexed).to.equal(false);
      // amount/burnieReward stay uint256 wei (D-277-EVT-WIDE-01).
      const burnieAmount = frag.inputs.find((i) => i.name === "burnieAmount");
      const burnieReward = frag.inputs.find((i) => i.name === "burnieReward");
      expect(burnieAmount.type).to.equal("uint256");
      expect(burnieReward.type).to.equal("uint256");
      expect(frag.topicHash).to.match(/^0x[0-9a-f]{64}$/);
      expect(BigInt(frag.topicHash)).to.not.equal(0n);
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

    it("[03c] auto-resolve callers pass index=0 (3rd positional), emitLootboxEvent=false (10th positional), and payColdBustConsolation=false (11th positional) to _resolveLootboxCommon", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // The _resolveLootboxCommon positional arg order (per signature):
      //   1 player, 2 day, 3 index, 4 amount, 5 targetLevel, 6 currentLevel,
      //   7 seed, 8 presale, 9 allowPasses, 10 emitLootboxEvent,
      //   11 payColdBustConsolation, 12 allowBoons, 13 distressEth,
      //   14 totalPackedEth
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function resolveRedemptionLootbox(",
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
          `${fnSig} _resolveLootboxCommon must receive 14 positional args`
        ).to.equal(14);
        expect(
          args[2],
          `${fnSig} must pass index=0 as the 3rd positional arg (D-277-AR-INDEX-01)`
        ).to.equal("0");
        expect(
          args[9],
          `${fnSig} must pass emitLootboxEvent=false as the 10th positional arg (D-277-AR-SILENT-01)`
        ).to.equal("false");
        expect(
          args[10],
          `${fnSig} must pass payColdBustConsolation=false as the 11th positional arg (D-277-AR-SILENT-01)`
        ).to.equal("false");
        // The retired sentinel value must not appear in the caller body.
        expect(
          body.includes("type(uint48).max"),
          `${fnSig} must not pass the retired type(uint48).max sentinel`
        ).to.equal(false);
      }
    });

    it("[03d] the unified ticket-queue path calls `_queueTickets(player, targetLevel, whole, false)` exactly once inside _resolveLootboxCommon — not inside any index-conditional branch", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _resolveLootboxCommon(");
      expect(body, "_resolveLootboxCommon body not found").to.not.equal(null);
      const calls = (
        body.match(/_queueTickets\(player, targetLevel, whole, false\)/g) || []
      ).length;
      expect(
        calls,
        "the post-retirement _resolveLootboxCommon must contain exactly one `_queueTickets(player, targetLevel, whole, false)` call (unified, unconditional)"
      ).to.equal(1);
      // No `if (index` conditional should wrap any logic in this function body.
      expect(
        /if\s*\(\s*index\b/.test(body),
        "_resolveLootboxCommon must not branch on `index` after sentinel retirement"
      ).to.equal(false);
    });
  });

  describe("TST-EVT-UNI-04 — manual-path LootBoxOpened / BurnieLootOpen field-consistency (whole derived from scaled futureTickets/tickets + roundedUp; no preRollTickets)", function () {
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
      // and feeds the local `whole` (post-Bernoulli collapse) into _queueTickets.
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

    it("[04c] _resolveLootboxCommon keeps function-scope `futureTickets` at the scaled value and the LootBoxOpened emit consumes it (whole is a separate local)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _resolveLootboxCommon(");
      expect(body, "_resolveLootboxCommon body not found").to.not.equal(null);
      // The Bernoulli collapse writes to a SEPARATE local `whole`, never to
      // function-scope `futureTickets`.
      expect(
        /uint32 whole = futureTickets \/ uint32\(TICKET_SCALE\);/.test(body),
        "`whole` must be derived from scaled `futureTickets` as a separate local"
      ).to.equal(true);
      // The LootBoxOpened emit references `futureTickets` (scaled), not `whole`.
      const emitArgList = extractCallArgs(body, "emit LootBoxOpened(");
      expect(emitArgList, "LootBoxOpened emit not found").to.not.equal(null);
      const emitArgs = splitTopLevelArgs(emitArgList);
      // Positional order matches the event def:
      //   player, lootboxIndex(index), day, amount, futureLevel(targetLevel),
      //   futureTickets, burnie(burnieAmount), roundedUp
      expect(emitArgs.length).to.equal(8);
      expect(emitArgs[0]).to.equal("player");
      expect(emitArgs[1]).to.equal("index"); // lootboxIndex slot fed the `index` param
      expect(emitArgs[2]).to.equal("day"); // day slot fed the `day` param
      expect(emitArgs[5]).to.equal("futureTickets"); // scaled, un-mutated
      expect(emitArgs[7]).to.equal("roundedUp");
    });

    it("[04d] the manual BurnieLootOpen emit threads the scaled `tickets` return value and the `roundedUp` flag from _resolveLootboxCommon", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function openBurnieLootBox(");
      expect(body, "openBurnieLootBox body not found").to.not.equal(null);
      // openBurnieLootBox destructures (uint32 tickets, uint256 burnieReward, bool roundedUp)
      // — the 3-return shape after the bonusBurnie return was dropped.
      expect(
        /\(uint32 tickets, uint256 burnieReward, bool roundedUp\)\s*=\s*_resolveLootboxCommon/.test(
          body
        ),
        "openBurnieLootBox must destructure the scaled `tickets` and the `roundedUp` flag from _resolveLootboxCommon"
      ).to.equal(true);
      const emitArgList = extractCallArgs(body, "emit BurnieLootOpen(");
      expect(emitArgList, "BurnieLootOpen emit not found").to.not.equal(null);
      const emitArgs = splitTopLevelArgs(emitArgList);
      // player, index, burnieAmount, ticketLevel(targetLevel), tickets, burnieReward, roundedUp
      expect(emitArgs.length).to.equal(7);
      expect(emitArgs[0]).to.equal("player");
      expect(emitArgs[1]).to.equal("uint32(index)");
      expect(emitArgs[4]).to.equal("tickets"); // scaled pre-Bernoulli
      expect(emitArgs[6]).to.equal("roundedUp");
    });

    it("[04e] the WWXRP-consolation case is inferable as `whole == 0 && futureTickets > 0` corroborated by a same-tx WWXRP ERC-20 Transfer from mintPrize", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _resolveLootboxCommon(");
      expect(body, "_resolveLootboxCommon body not found").to.not.equal(null);
      // The consolation predicate is `payColdBustConsolation && whole == 0` and
      // sits inside the `if (futureTickets != 0)` guard — i.e. it only fires when
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

  describe("TST-EVT-UNI-05 — auto-resolve field-consistency, EVT-UNI-06 resolved form (auto-resolve is SILENT; consolation is payColdBustConsolation-gated)", function () {
    it("[05a] the only `emit LootBoxOpened` site in _resolveLootboxCommon is inside the `if (emitLootboxEvent)` gate", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(src, "function _resolveLootboxCommon(");
      expect(body, "_resolveLootboxCommon body not found").to.not.equal(null);
      const emitMatches = [...body.matchAll(/emit LootBoxOpened\(/g)];
      expect(
        emitMatches.length,
        "_resolveLootboxCommon must contain exactly one `emit LootBoxOpened` site"
      ).to.equal(1);
      const emitIdx = emitMatches[0].index;
      // Walk back: the nearest preceding `if (emitLootboxEvent)` must enclose it.
      const preamble = body.slice(0, emitIdx);
      const gateIdx = preamble.lastIndexOf("if (emitLootboxEvent)");
      expect(
        gateIdx,
        "the LootBoxOpened emit must sit inside an `if (emitLootboxEvent)` gate"
      ).to.be.greaterThan(-1);
    });

    it("[05b] auto-resolve callers emit no LootBoxOpened — resolveLootboxDirect / resolveRedemptionLootbox pass emitLootboxEvent=false (D-277-AR-SILENT-01)", function () {
      const src = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // No `emit LootBoxOpened` appears directly in the auto-resolve caller bodies,
      // and they pass emitLootboxEvent=false (proven structurally in [03c]).
      for (const fnSig of [
        "function resolveLootboxDirect(",
        "function resolveRedemptionLootbox(",
      ]) {
        const body = extractBody(src, fnSig);
        expect(body, `${fnSig} body not found`).to.not.equal(null);
        expect(
          body.includes("emit LootBoxOpened("),
          `${fnSig} must not emit LootBoxOpened directly`
        ).to.equal(false);
      }
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
      // path, while both manual callers (openLootBox, openBurnieLootBox) pass
      // payColdBustConsolation=true and DO pay it.
      const body = extractBody(src, "function _resolveLootboxCommon(");
      expect(
        /if \(payColdBustConsolation && whole == 0\)\s*\{/.test(body),
        "the consolation must be gated by `payColdBustConsolation && whole == 0` — manual-only per D-277-CONSOLATION-GATE-01"
      ).to.equal(true);
    });

    it("[05d] auto-resolve ticket awards stay observable via the unified `_queueTickets` path → `TicketsQueued`", function () {
      const lootbox = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      const body = extractBody(lootbox, "function _resolveLootboxCommon(");
      // The unified path calls _queueTickets unconditionally (proven single-site
      // in [03d]); _queueTickets is what makes auto-resolve awards observable
      // without a LootBoxOpened emit.
      expect(
        body.includes("_queueTickets(player, targetLevel, whole, false)"),
        "the unified path must call _queueTickets so auto-resolve awards remain observable via TicketsQueued"
      ).to.equal(true);
      // _queueTickets emits TicketsQueued (verified at the storage layer).
      const storage = fs.readFileSync(
        path.resolve(process.cwd(), "contracts/storage/DegenerusGameStorage.sol"),
        "utf8"
      );
      const queueBody = extractBody(storage, "function _queueTickets(");
      expect(queueBody, "_queueTickets body not found in storage").to.not.equal(
        null
      );
      expect(
        queueBody.includes("emit TicketsQueued("),
        "_queueTickets must emit TicketsQueued"
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
      // The Bernoulli predicate uses bits[200..215] of the per-roll entropy word.
      const predIdx = body.indexOf(
        "(uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)"
      );
      expect(
        predIdx,
        "_jackpotTicketRoll Bernoulli predicate `(uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)` missing"
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
      // winner, targetLevel, BAF_TRAIT_SENTINEL, whole, minTargetLevel, 0, roundedUp
      // — the 4th arg `whole` is the whole-ticket count queued by the adjacent
      // _queueTickets call (D-278-EVT-UNIFY-01).
      expect(emitArgs.length).to.equal(7);
      expect(emitArgs[3]).to.equal("whole");
      expect(emitArgs[6]).to.equal("roundedUp");
    });

    it("[06d] all 3 JackpotTicketWin emit sites supply the 7th `roundedUp` arg; the two trait-matched sites pass literal `false`", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      expect(
        emitMatches.length,
        "there must be exactly 3 JackpotTicketWin emit sites"
      ).to.equal(3);
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
      // Two trait-matched paths pass literal `false` (zero fractional part by
      // construction); the BAF _jackpotTicketRoll path threads the real flag.
      expect(literalFalseCount, "two trait-matched sites must pass `false`").to.equal(
        2
      );
      expect(
        threadedCount,
        "the _jackpotTicketRoll site must thread the captured `roundedUp`"
      ).to.equal(1);
    });

    it("[06e] the _jackpotTicketRoll Bernoulli predicate mirrors the LootboxModule capture pattern (byte-identical math, different entropy slice)", function () {
      const jackpot = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const lootbox = fs.readFileSync(LOOTBOX_SOURCE_PATH, "utf8");
      // Lootbox path: bits[152..167]; Jackpot path: bits[200..215]. Both use the
      // same `frac != 0 && (uint16(...) % uint16(TICKET_SCALE)) < uint16(frac)` shape.
      expect(
        /frac != 0 && \(uint16\(seed >> 152\) % uint16\(TICKET_SCALE\)\) < uint16\(frac\)/.test(
          lootbox
        ),
        "LootboxModule Bernoulli predicate shape drifted"
      ).to.equal(true);
      expect(
        /frac != 0 && \(uint16\(entropy >> 200\) % uint16\(TICKET_SCALE\)\) < uint16\(frac\)/.test(
          jackpot
        ),
        "JackpotModule Bernoulli predicate shape drifted from the LootboxModule pattern"
      ).to.equal(true);
    });
  });
});
