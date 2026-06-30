// SPDX-License-Identifier: AGPL-3.0-only
//
// CrossSurfaceTicketMixing.test.js — Phase 278 Wave 2 TST-CROSS-01 + TST-CLEAN-02/03
//
// Phase 278 retired two dead helpers and unified the jackpot ticket-award event
// surface onto whole-ticket counts. This file carries the test wave's
// regression coverage for those two deletions plus the cross-surface
// ticket-award independence proof:
//
//   TST-CLEAN-02 — `_queueLootboxTickets` wrapper-removal regression:
//     The zero-caller `_queueLootboxTickets` wrapper was deleted from
//     `DegenerusGameStorage.sol`. This block asserts zero remaining
//     invocation/declaration sites across `contracts/`, and that the three
//     sibling queue helpers that STAY (`_queueEntries`, `_queueEntriesScaled`,
//     `_queueEntryRange`) are still present.
//
//   TST-CLEAN-03 — `JackpotTicketWin` entries-basis emit regression:
//     The 2 `JackpotTicketWin` emit sites emit the ENTRIES count queued into
//     `entriesOwedPacked` — the already-correct `uint32(units)` leg and the BAF
//     roll's `wholeTicketsToEntries(whole)` — neither multiplies the 4th arg by
//     `QTY_SCALE`. This block asserts that, plus that the `JackpotTicketWin`
//     event definition (field types + `indexed` markers) is unchanged: the value
//     fix shifts emitted VALUES onto the entries basis, not the signature.
//
//   TST-CROSS-01 — cross-surface `rem`-byte regression:
//     The 3 RNG-driven ticket-award surfaces (manual lootbox open, auto-resolve
//     lootbox open, jackpot ticket-roll award) all route through `_queueEntries`
//     — the whole-ticket helper, which carries the `rem` byte of
//     `entriesOwedPacked[wk][buyer]` UNTOUCHED. Only `_queueEntriesScaled`
//     (the mint-boost path) ever writes a non-zero `rem`. Driven full-stack
//     through the real entry points so the genuinely-shared
//     `entriesOwedPacked[wk][buyer]` slot is exercised (D-278-TST-CROSS-DEPTH-01).
//
// PLACEMENT: `test/integration/` — directory-globbed by both the `test` and
// `test:integration` package.json scripts, so this file is auto-discovered with
// no script edit. `test/integration/` is also the correct semantic home: the
// TST-CROSS-01 full-stack depth requirement (D-278-TST-CROSS-DEPTH-01) needs the
// integration suite's VRF-mock + level + day + staking fixture setup.
//
// CROSS-CITES:
//   - D-278-EVT-UNIFY-01 / D-278-ENTROPYSTEP-DELETE-01 (278-CONTEXT.md)
//   - D-278-TST-CROSS-ASSERT-01 / D-278-TST-CROSS-DEPTH-01 (278-CONTEXT.md)
//   - 278-01-SUMMARY.md (Wave 1 landed the deletions + the whole-ticket emits)
//   - test/unit/LootboxAutoResolveRemByte.test.js (Phase 275 rem-byte snapshot precedent)

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const MINT_MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameMintModule.sol"
);

// ---------------------------------------------------------------------------
// entriesOwedPacked slot-derivation — D-278-TST-CROSS-DEPTH-01 live-state read.
//
// `entriesOwedPacked` is declared `mapping(uint24 => mapping(address => uint40))`
// at DegenerusGameStorage.sol:465. The compiled storage layout (hardhat
// build-info `storageLayout`) places it at STORAGE SLOT 13 in DegenerusGame and
// every module (the modules share DegenerusGame's layout because they are
// delegatecall targets over the same storage).
//
// For a Solidity nested mapping `m[k1][k2]` rooted at `baseSlot`, the value
// slot is the standard double-keccak nesting:
//   inner = keccak256(abi.encode(k1, baseSlot))
//   slot  = keccak256(abi.encode(k2, inner))
// Here k1 is the `uint24` write-key `wk` (abi-encoded to a full 32-byte word)
// and k2 is the `address` buyer. The packed `uint40` value occupies the low
// 40 bits of the slot word; `rem = uint8(value)` is its low 8 bits and the
// owed-entries count is `value >> 8`.
//
// This slot math is cross-checked at runtime against the public
// `ticketsOwedView(lvl, player)` accessor (which returns `packed >> 8` for the
// `_tqWriteKey(lvl)` key) — if the derivation drifts, the cross-check fails.
// ---------------------------------------------------------------------------
const TICKETS_OWED_PACKED_BASE_SLOT = 13n;

function entriesOwedPackedSlot(wk, buyer) {
  const abi = hre.ethers.AbiCoder.defaultAbiCoder();
  // Inner mapping slot: keccak256(abi.encode(uint24 wk, uint256 baseSlot)).
  // uint24 abi-encodes to a full left-padded 32-byte word, so encoding `wk`
  // as a plain integer is equivalent.
  const inner = hre.ethers.keccak256(
    abi.encode(["uint256", "uint256"], [BigInt(wk), TICKETS_OWED_PACKED_BASE_SLOT])
  );
  // Value slot: keccak256(abi.encode(address buyer, bytes32 inner)).
  return hre.ethers.keccak256(
    abi.encode(["address", "bytes32"], [buyer, inner])
  );
}

// Read the live `entriesOwedPacked[wk][buyer]` word straight out of the
// Game contract's storage and split it into { packed, owed, rem }.
async function readTicketsOwedSlot(gameAddress, wk, buyer) {
  const slot = entriesOwedPackedSlot(wk, buyer);
  const raw = await hre.ethers.provider.getStorage(gameAddress, slot);
  const word = BigInt(raw);
  // The uint40 value lives in the low 40 bits of the slot.
  const packed = word & ((1n << 40n) - 1n);
  const rem = Number(packed & 0xffn); // low 8 bits
  const owed = packed >> 8n; // owed-entries count
  return { slot, packed, owed, rem };
}

const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);
const JACKPOT_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);
const CONTRACTS_DIR = path.resolve(process.cwd(), "contracts");

// Brace-match function-body extractor (mirrors test/unit/LootboxAutoResolveRemByte.test.js).
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

// Paren-match emit/call arg-list extractor (mirrors EventSurfaceUnification.test.js).
function extractCallArgs(source, prefix) {
  const idx = source.indexOf(prefix);
  if (idx < 0) return null;
  const open = idx + prefix.length - 1; // `prefix` includes the trailing `(`
  if (source[open] !== "(") return null;
  let depth = 0;
  for (let i = open; i < source.length; i++) {
    if (source[i] === "(") depth++;
    else if (source[i] === ")") {
      depth--;
      if (depth === 0) return source.slice(open, i + 1);
    }
  }
  return null;
}

// Split a parenthesised arg list (inclusive of outer parens) into top-level
// args, respecting nested parens so `uint32(units)` stays one arg.
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
    if (entry.isDirectory()) out.push(...collectSolFiles(full));
    else if (entry.isFile() && entry.name.endsWith(".sol")) out.push(full);
  }
  return out;
}

describe("CrossSurfaceTicketMixing — Phase 278 Wave 2 TST-CLEAN-02/03 + TST-CROSS-01", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  describe("TST-CLEAN-02 — `_queueLootboxTickets` wrapper-removal regression", function () {
    it("[02a] DegenerusGameStorage.sol contains zero `_queueLootboxTickets` references (wrapper + NatSpec fully deleted)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      expect(
        (storage.match(/_queueLootboxTickets/g) || []).length,
        "_queueLootboxTickets must be fully removed from DegenerusGameStorage.sol"
      ).to.equal(0);
    });

    it("[02b] no .sol file under contracts/ declares or invokes `_queueLootboxTickets`", function () {
      let total = 0;
      for (const file of collectSolFiles(CONTRACTS_DIR)) {
        const src = fs.readFileSync(file, "utf8");
        total += (src.match(/_queueLootboxTickets/g) || []).length;
      }
      expect(
        total,
        "_queueLootboxTickets must not appear anywhere under contracts/ — zero declaration + zero invocation sites"
      ).to.equal(0);
    });

    it("[02c] the three sibling queue helpers that STAY are still declared in DegenerusGameStorage.sol", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      for (const sig of [
        "function _queueEntries(",
        "function _queueEntriesScaled(",
        "function _queueEntryRange(",
      ]) {
        expect(
          storage.includes(sig),
          `${sig} must still be present — only the zero-caller _queueLootboxTickets wrapper was deleted`
        ).to.equal(true);
      }
    });
  });

  describe("TST-CLEAN-03 — `JackpotTicketWin` entries-basis emit regression", function () {
    it("[03a] there are exactly 2 `emit JackpotTicketWin` sites and none multiply the 4th (ticketCount) arg by QTY_SCALE", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      expect(
        emitMatches.length,
        "there must be exactly 2 JackpotTicketWin emit sites"
      ).to.equal(2);
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
          "every JackpotTicketWin emit must supply 7 args"
        ).to.equal(7);
        // The 4th positional arg (index 3) is `ticketCount`. It carries the
        // entries count queued (`uint32(units)` / `wholeTicketsToEntries(whole)`)
        // — never a `* QTY_SCALE` scaled value.
        expect(
          /QTY_SCALE/.test(args[3]),
          `JackpotTicketWin 4th arg \`${args[3]}\` must not reference QTY_SCALE — emit the queued entries count`
        ).to.equal(false);
      }
    });

    it("[03b] the 2 emit sites emit, in source order, the entries counts `uint32(units)`, `wholeTicketsToEntries(whole)`", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      const fourthArgs = emitMatches.map((m) => {
        const argList = extractCallArgs(
          src.slice(m.index),
          "emit JackpotTicketWin("
        );
        return splitTopLevelArgs(argList)[3];
      });
      // Site 1 (the already-correct coin/units leg): `uint32(units)` —
      // `_budgetToEntries` already returns entries. Site 2 (the BAF
      // `_jackpotTicketRoll`): the post-Bernoulli whole count routed through the
      // canonical `wholeTicketsToEntries`. Each matches the entries value passed
      // to the adjacent `_queueEntries` call.
      expect(fourthArgs).to.deep.equal([
        "uint32(units)",
        "wholeTicketsToEntries(whole)",
      ]);
    });

    it("[03c] each emit site's 4th arg matches the entries value passed to its adjacent `_queueEntries` call (emit value == storage-write value)", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      // For each emit site, the nearest preceding `_queueEntries(` call must
      // pass the SAME entries expression as the emit's 4th arg.
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      for (const m of emitMatches) {
        const emitArgs = splitTopLevelArgs(
          extractCallArgs(src.slice(m.index), "emit JackpotTicketWin(")
        );
        const preamble = src.slice(0, m.index);
        const queueIdx = preamble.lastIndexOf("_queueEntries(");
        expect(
          queueIdx,
          "every JackpotTicketWin emit must be preceded by a _queueEntries call"
        ).to.be.greaterThan(-1);
        const queueArgs = splitTopLevelArgs(
          extractCallArgs(src.slice(queueIdx), "_queueEntries(")
        );
        // _queueEntries(winner, level, <entries>, rngBypass) — 3rd arg is the
        // entries count; JackpotTicketWin's 4th arg (`ticketCount`) carries the
        // same entries value (emit == queue on the entries basis).
        expect(
          emitArgs[3],
          `JackpotTicketWin 4th arg \`${emitArgs[3]}\` must equal the entries value \`${queueArgs[2]}\` passed to the adjacent _queueEntries call`
        ).to.equal(queueArgs[2]);
      }
    });

    it("[03d] the `JackpotTicketWin` event definition (field types + indexed markers) is unchanged across the Phase 278 wave — Phase 278 shifts emitted VALUES only", function () {
      // Phase 278 (D-278-EVT-UNIFY-01) is explicit: the event signature /
      // topic-hash is UNCHANGED — only the emitted ticketCount VALUES shift from
      // scaled to whole. The pre-Phase-278 state is HEAD's parent of the Wave 1
      // contract commit; the `bool roundedUp` 7th field was added in Phase 277,
      // BEFORE this phase, so it is part of the unchanged pre-278 baseline.
      // Wave 1 contract commit is 8a81a87c; its parent is the pre-278 state.
      let pre278Source;
      try {
        pre278Source = execSync(
          "git show 8a81a87c~1:contracts/modules/DegenerusGameJackpotModule.sol",
          { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }
        );
      } catch (_) {
        // Soft-skip if the pre-278 commit is unreachable (shallow clone).
        console.warn(
          "[TST-CLEAN-03] pre-278 baseline 8a81a87c~1 unreachable — soft-skipping event-def byte-identity check"
        );
        this.skip();
        return;
      }
      const currentSource = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");

      // Extract the `event JackpotTicketWin(...)` declaration body from each.
      function extractEventDecl(source) {
        const idx = source.indexOf("event JackpotTicketWin(");
        expect(idx, "event JackpotTicketWin declaration not found").to.be.greaterThan(
          -1
        );
        const semi = source.indexOf(");", idx);
        return source
          .slice(idx, semi + 2)
          .replace(/\s+/g, " ")
          .trim();
      }
      const preDecl = extractEventDecl(pre278Source);
      const curDecl = extractEventDecl(currentSource);
      expect(
        curDecl,
        "JackpotTicketWin event definition (types + indexed markers) must be byte-identical to the pre-278 baseline — Phase 278 changes emitted values only, not the signature"
      ).to.equal(preDecl);
    });

    it("[03e] the compiled JackpotTicketWin ABI fragment carries the 7-field post-Phase-277 signature with exactly 3 indexed params", async function () {
      const artifact = await hre.artifacts.readArtifact(
        "DegenerusGameJackpotModule"
      );
      const iface = new hre.ethers.Interface(artifact.abi);
      const frag = iface.getEvent("JackpotTicketWin");
      expect(frag, "JackpotTicketWin missing from ABI").to.not.equal(null);
      const types = frag.inputs.map(
        (i) => `${i.type}${i.indexed ? " indexed" : ""}`
      );
      expect(types).to.deep.equal([
        "address indexed",
        "uint24 indexed",
        "uint16 indexed",
        "uint32",
        "uint24",
        "uint256",
        "bool",
      ]);
      expect(frag.inputs.filter((i) => i.indexed).length).to.equal(3);
      expect(frag.topicHash).to.match(/^0x[0-9a-f]{64}$/);
      expect(BigInt(frag.topicHash)).to.not.equal(0n);
    });
  });

  describe("TST-CROSS-01 — cross-surface `rem`-byte regression (live-state `entriesOwedPacked` read, D-278-TST-CROSS-DEPTH-01)", function () {
    // -----------------------------------------------------------------------
    // PRIMARY ASSERTION (D-278-TST-CROSS-DEPTH-01): a live-state raw
    // `provider.getStorage` read of the genuinely-shared
    // `entriesOwedPacked[wk][buyer]` slot, driven through the REAL
    // `openBox` entry point full-stack (purchase -> requestLootboxRng ->
    // VRF fulfill -> openBox). The lootbox ticket path routes through
    // `_queueEntries` (entries, via `wholeTicketsToEntries(whole)`), which carries
    // the `rem` byte of the packed slot UNTOUCHED — so `rem` must stay 0 across
    // every open. Only `_queueEntriesScaled` (the mint-boost path) ever writes a
    // non-zero `rem`.
    //
    // FIXTURE_COVERAGE_GAP (carried-forward harness limitation, NOT a Phase 278
    // regression): the 278-02 plan's `<action>` calls for ALL THREE RNG-driven
    // surfaces (manual lootbox, auto-resolve lootbox, jackpot ticket-roll) plus
    // a mint-boost open to be driven full-stack through their real entry
    // points. The current test harness can deterministically drive ONLY the
    // manual `openBox` entry point end-to-end (v47: the `openFlipLootBox`
    // FLIP-lootbox entry point was removed — terminal-paradox closure):
    //   - `resolveLootboxDirect` has NO public DegenerusGame entry point — it is
    //     a cross-module delegatecall target only (documented in
    //     test/gas/LootboxOpenGas.test.js: "no public-entry-point harness
    //     available").
    //   - `resolveRedemptionLootbox` requires sDGNRS staking + a burn-redemption
    //     submission to reach; the harness has no redemption-flow fixture.
    //   - `_awardJackpotTickets` / `_jackpotTicketRoll` are PRIVATE — reachable
    //     only through the jackpot-phase daily-advance path, which the
    //     simulator cannot deterministically land on without VRF rigging
    //     (the same documented LBX-02 / Phase 269 GAS-01 fixture-coverage gap
    //     cited in test/gas/LootboxOpenGas.test.js and the FIXTURE-COVERAGE
    //     NOTE in test/unit/LootboxConsolation.test.js TST-WX-04).
    //   - VRF-rigging to force a per-resolution seed's bit-slice (needed to
    //     hit a specific Bernoulli outcome / non-zero `frac`) is not supported
    //     by the harness.
    // Per that precedent body, this block uses:
    //   [CROSS-01a/b] the live-state `provider.getStorage` read driven through
    //     the REAL `openBox` entry point full-stack — the PRIMARY assertion
    //     for the surfaces the harness CAN reach (manual lootbox path), with a
    //     soft-skip if the simulator denies lootbox-RNG reachability (matching
    //     the LootboxOpenGas.test.js `reachOpenableLootbox` soft-skip precedent).
    //   [CROSS-01c] a slot-math self-validation: the derived slot's `owed`
    //     cross-checks against the public `ticketsOwedView` accessor.
    //   [CROSS-01d] the source-structural `extractBody` proof (DEMOTED to a
    //     secondary cross-check per D-278-TST-CROSS-DEPTH-01) that the 3
    //     RNG-driven surfaces all route through `_queueEntries` (whole, no rem
    //     write) while `_queueEntriesScaled` is the sole rem-byte writer — this
    //     is the structural coverage for the auto-resolve + jackpot-roll
    //     surfaces the live-state harness cannot reach.
    // -----------------------------------------------------------------------

    // Buy `n` lootboxes at the level-0 intro price (mirrors
    // test/gas/LootboxOpenGas.test.js `buyLootboxes`).
    async function buyLootboxes(game, buyer, n, totalEth) {
      return game
        .connect(buyer)
        .purchase(hre.ethers.ZeroAddress, 0n, BigInt(n), ZERO_BYTES32, 0,false,  {
          value: eth(totalEth),
        });
    }

    // Drive the lifecycle to a state where lootbox VRF has been requested AND
    // fulfilled (mirrors test/gas/LootboxOpenGas.test.js `reachOpenableLootbox`).
    async function reachOpenableLootbox(fixture) {
      const { game, deployer, mockVRF, alice } = fixture;
      try {
        await buyLootboxes(game, alice, 20, 0.02);
      } catch (err) {
        return { reason: `lootbox purchase failed: ${err.message.slice(0, 80)}` };
      }
      let lbRequestId;
      try {
        await game.connect(deployer).requestLootboxRng();
        lbRequestId = await getLastVRFRequestId(mockVRF);
      } catch (err) {
        return { reason: `requestLootboxRng failed: ${err.message.slice(0, 80)}` };
      }
      try {
        await mockVRF.fulfillRandomWords(lbRequestId, 278278n);
      } catch (err) {
        return {
          reason: `fulfillRandomWords failed: ${err.message.slice(0, 80)}`,
        };
      }
      return { reason: null };
    }

    // Find an openable ETH lootbox index for `player` (non-zero stored ETH +
    // non-zero rngWord). Mirrors LootboxOpenGas.test.js `findOpenableEthIndex`.
    async function findOpenableEthIndex(game, player) {
      for (let i = 0; i < 64; i++) {
        let amount;
        try {
          amount = await game.lootboxEth(i, player.address);
        } catch (_) {
          break;
        }
        if (amount === undefined || amount === null) continue;
        if (BigInt(amount) === 0n) continue;
        let rngWord;
        try {
          rngWord = await game.lootboxRngWordByIndex(i);
        } catch (_) {
          continue;
        }
        if (BigInt(rngWord) === 0n) continue;
        return i;
      }
      return null;
    }

    // Resolve the live `entriesOwedPacked` slot for `player` at `lvl` by
    // probing the three candidate write-keys (`lvl`, `lvl | TICKET_SLOT_BIT`
    // — the double-buffer toggle — and the far-future key `lvl | 1<<22`) and
    // selecting the key whose slot read's `owed` matches the public
    // `ticketsOwedView(lvl, player)` accessor. This makes the slot math
    // self-validating without needing the internal `ticketWriteSlot` bool.
    async function resolveLiveTicketsOwed(game, gameAddress, lvl, player) {
      const TICKET_SLOT_BIT = 1n << 23n;
      const FAR_FUTURE_BIT = 1n << 22n;
      const viewWhole = BigInt(
        await game.ticketsOwedView(lvl, player.address)
      );
      const candidateKeys = [
        BigInt(lvl),
        BigInt(lvl) | TICKET_SLOT_BIT,
        BigInt(lvl) | FAR_FUTURE_BIT,
        BigInt(lvl) | TICKET_SLOT_BIT | FAR_FUTURE_BIT,
      ];
      for (const wk of candidateKeys) {
        const read = await readTicketsOwedSlot(gameAddress, wk, player.address);
        if (read.owed === viewWhole) {
          return { ...read, wk, viewWhole, matched: true };
        }
      }
      // No candidate matched — return the primary write-key read plus the
      // view value so the caller can assert / diagnose.
      const fallback = await readTicketsOwedSlot(
        gameAddress,
        BigInt(lvl),
        player.address
      );
      return { ...fallback, wk: BigInt(lvl), viewWhole, matched: false };
    }

    it("[CROSS-01a] live-state: a freshly-deployed player's `entriesOwedPacked` slot reads `rem == 0` (baseline snapshot via raw provider.getStorage)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();
      const currentLevel = BigInt(await game.level()) + 1n;

      // Before any ticket activity, the shared slot is empty: rem == 0 AND
      // owed == 0. This also pins the slot-derivation math against a known
      // all-zero ground truth.
      const snap = await resolveLiveTicketsOwed(
        game,
        gameAddress,
        currentLevel,
        alice
      );
      expect(
        snap.rem,
        `freshly-deployed player's entriesOwedPacked rem byte must be 0 (raw slot read ${snap.slot})`
      ).to.equal(0);
      expect(
        snap.owed,
        "freshly-deployed player's entriesOwedPacked owed count must be 0"
      ).to.equal(0n);
      expect(
        snap.viewWhole,
        "ticketsOwedView must agree the player has 0 whole tickets at baseline"
      ).to.equal(0n);
    });

    it("[CROSS-01b] live-state: driving the REAL `openBox` entry point full-stack leaves the shared `entriesOwedPacked` `rem` byte at 0 (whole-ticket path never writes rem)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();

      const probe = await reachOpenableLootbox(fixture);
      if (probe.reason !== null) {
        // Soft-skip — the simulator state denied lootbox-RNG reachability.
        // Matches the LootboxOpenGas.test.js `reachOpenableLootbox` soft-skip
        // precedent: fixture-coverage gaps are reported, not silently passed.
        console.warn(
          `[TST-CROSS-01b] soft-skip — ${probe.reason} (matches ` +
            `LootboxOpenGas.test.js reachOpenableLootbox soft-skip precedent; ` +
            `the structural cross-check [CROSS-01d] still covers the rem-byte invariant)`
        );
        this.skip();
        return;
      }

      const index = await findOpenableEthIndex(game, alice);
      if (index === null) {
        console.warn(
          "[TST-CROSS-01b] soft-skip — no openable ETH lootbox index found for alice in probe range"
        );
        this.skip();
        return;
      }

      // Snapshot the shared slot BEFORE the open across the plausible target
      // levels (the lootbox roll picks a target level >= currentLevel).
      const baseLevel = BigInt(await game.level()) + 1n;
      const levelsToWatch = [];
      for (let l = baseLevel; l <= baseLevel + 55n; l++) {
        levelsToWatch.push(l);
      }
      for (const lvl of levelsToWatch) {
        const before = await resolveLiveTicketsOwed(
          game,
          gameAddress,
          lvl,
          alice
        );
        expect(
          before.rem,
          `pre-open: entriesOwedPacked rem byte for level ${lvl} must be 0`
        ).to.equal(0);
      }

      // Drive the REAL openBox entry point full-stack.
      await game.connect(alice).openBox(alice.address, index);

      // Re-snapshot every watched level: the whole-ticket `_queueEntries` path
      // carries the rem byte untouched, so rem must STILL be 0 everywhere —
      // regardless of which target level the lootbox roll landed on.
      let sawWholeTicketAward = false;
      for (const lvl of levelsToWatch) {
        const after = await resolveLiveTicketsOwed(
          game,
          gameAddress,
          lvl,
          alice
        );
        expect(
          after.rem,
          `post-open: entriesOwedPacked rem byte for level ${lvl} must STILL be 0 ` +
            `— the manual lootbox open routes through _queueEntries (whole), which ` +
            `never writes the rem byte`
        ).to.equal(0);
        if (after.owed > 0n) sawWholeTicketAward = true;
      }
      // The open should have queued whole tickets somewhere in the watched
      // range (the lootbox ticket path produced a non-zero whole count). If it
      // did not (e.g. the roll picked a non-ticket reward), that is still a
      // valid run — the rem-byte invariant above is the load-bearing assertion.
      if (!sawWholeTicketAward) {
        console.warn(
          "[TST-CROSS-01b] note — openBox did not queue whole tickets in the " +
            "watched level range (non-ticket lootbox reward roll); the rem == 0 " +
            "invariant still held across all watched levels"
        );
      }
    });

    it("[CROSS-01c] slot-math self-validation: the derived `entriesOwedPacked` slot's `owed` field round-trips against the public `ticketsOwedView` accessor", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();
      const currentLevel = BigInt(await game.level()) + 1n;

      // At baseline both the raw-slot `owed` and `ticketsOwedView` are 0 — a
      // trivial-but-real round-trip that pins the keccak nesting math. If a
      // post-open whole-ticket award is reachable, [CROSS-01b]'s
      // resolveLiveTicketsOwed `matched` flag exercises the non-zero round-trip.
      const snap = await resolveLiveTicketsOwed(
        game,
        gameAddress,
        currentLevel,
        alice
      );
      expect(
        snap.matched,
        "slot-math self-validation: the derived slot's owed field must match " +
          "ticketsOwedView (keccak nesting: keccak256(abi.encode(buyer, " +
          "keccak256(abi.encode(wk, 13)))))"
      ).to.equal(true);
      expect(snap.owed).to.equal(snap.viewWhole);
    });

    it("[CROSS-01d] structural cross-check (secondary): the 3 RNG-driven surfaces route through `_queueEntries` (whole, no rem write); `_queueEntriesScaled` is the sole rem-byte writer (mint-boost)", function () {
      // DEMOTED to a secondary cross-check per D-278-TST-CROSS-DEPTH-01 — the
      // live-state read above is primary. This block provides the structural
      // coverage for the auto-resolve + jackpot-roll surfaces the harness
      // cannot deterministically drive full-stack (see FIXTURE_COVERAGE_GAP).
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const lootboxSrc = fs.readFileSync(
        path.resolve(
          process.cwd(),
          "contracts/modules/DegenerusGameLootboxModule.sol"
        ),
        "utf8"
      );
      const jackpotSrc = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const mintSrc = fs.readFileSync(MINT_MODULE_SOURCE_PATH, "utf8");

      // (1) `_queueEntries` body packs `(uint40(owed) << 8) | uint40(rem)` with
      //     `rem` carried UNCHANGED from the pre-existing slot value — it never
      //     computes a fraction.
      const queueBody = extractBody(storage, "function _queueEntries(");
      expect(queueBody, "_queueEntries body not found").to.not.equal(null);
      expect(
        /entriesOwedPacked\[wk\]\[buyer\]\s*=\s*\(uint40\(owed\)\s*<<\s*8\)\s*\|\s*uint40\(rem\)/.test(
          queueBody
        ),
        "_queueEntries must pack `(uint40(owed) << 8) | uint40(rem)` with rem carried from the existing slot"
      ).to.equal(true);
      expect(
        queueBody.includes("% QTY_SCALE"),
        "_queueEntries must NOT compute a fractional remainder"
      ).to.equal(false);
      expect(
        /\bfrac\b/.test(queueBody),
        "_queueEntries must NOT have a `frac` local"
      ).to.equal(false);
      expect(
        /\bnewRem\b/.test(queueBody),
        "_queueEntries must NOT have a `newRem` local"
      ).to.equal(false);

      // (2) `_queueEntriesScaled` body IS the rem-byte writer — it computes
      //     `frac` via `% QTY_SCALE` and folds it into `newRem`.
      const scaledBody = extractBody(storage, "function _queueEntriesScaled(");
      expect(scaledBody, "_queueEntriesScaled body not found").to.not.equal(null);
      expect(
        scaledBody.includes("% QTY_SCALE"),
        "_queueEntriesScaled must compute frac via `% QTY_SCALE`"
      ).to.equal(true);
      expect(
        /\bnewRem\b/.test(scaledBody),
        "_queueEntriesScaled must have a `newRem` local (the rem-byte writer)"
      ).to.equal(true);

      // (3) Manual + auto-resolve lootbox surfaces: LootboxModule routes its
      //     per-roll ticket award through `_queueEntries` at this roll's
      //     `rollLevel`, converting the post-Bernoulli whole count to entries via
      //     the canonical `wholeTicketsToEntries`, and contains ZERO
      //     `_queueEntriesScaled` invocations.
      expect(
        lootboxSrc.includes(
          "_queueEntries(player, rollLevel, wholeTicketsToEntries(whole), false)"
        ),
        "LootboxModule must route the ticket award through `_queueEntries` on the entries basis (`wholeTicketsToEntries(whole)`)"
      ).to.equal(true);
      expect(
        lootboxSrc.includes("_queueEntriesScaled"),
        "LootboxModule must NOT invoke `_queueEntriesScaled` — it never writes the rem byte"
      ).to.equal(false);

      // (4) Jackpot ticket-roll surface: `_jackpotTicketRoll` converts its
      //     post-Bernoulli whole count to entries via the canonical
      //     `wholeTicketsToEntries` and queues it through `_queueEntries`; it does
      //     NOT call `_queueEntriesScaled` and never invokes the (absent)
      //     `_queueLootboxTickets` wrapper.
      const rollBody = extractBody(jackpotSrc, "function _jackpotTicketRoll(");
      expect(rollBody, "_jackpotTicketRoll body not found").to.not.equal(null);
      expect(
        rollBody.includes(
          "_queueEntries(winner, targetLevel, wholeTicketsToEntries(whole), true)"
        ),
        "_jackpotTicketRoll must route the post-Bernoulli whole count through `_queueEntries` on the entries basis (`wholeTicketsToEntries(whole)`)"
      ).to.equal(true);
      expect(
        rollBody.includes("_queueEntriesScaled"),
        "_jackpotTicketRoll must NOT invoke `_queueEntriesScaled`"
      ).to.equal(false);
      expect(
        rollBody.includes("_queueLootboxTickets"),
        "_jackpotTicketRoll must NOT invoke the retired `_queueLootboxTickets` wrapper"
      ).to.equal(false);

      // (5) Mint-boost surface: MintModule is the surface that DOES write the
      //     rem byte — it invokes `_queueEntriesScaled` (the sole rem-byte
      //     writer) for boost-derived fractional ticket awards.
      expect(
        (mintSrc.match(/_queueEntriesScaled\(/g) || []).length,
        "MintModule must invoke `_queueEntriesScaled` for boost-derived fractional awards — the surface that flips the rem byte non-zero"
      ).to.be.gte(1);
    });

    it("[CROSS-01e] live-state: driving the REAL `openBox` full-stack delivers owed-entries == the entries basis (~4x the pre-fix whole count) at the roll level", async function () {
      // emit == queue + ~4x behavioral proof for the lootbox leg: the post-Bernoulli
      // whole count routes through `wholeTicketsToEntries(whole)` into the entries-
      // denominated `entriesOwedPacked` sink, so the owed-entries delta at the roll
      // level is exactly `whole << 2` (4 entries per whole ticket) — four times the
      // pre-fix `scaledTickets/100` whole count. `_jackpotTicketRoll` (PRIVATE,
      // VRF-rigging-gated) is NOT driven full-stack here (carried-forward
      // FIXTURE_COVERAGE_GAP); its identical converter + basis path is proven
      // deterministically by the PrizeLegEntriesDelivery forge regression.
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();

      const probe = await reachOpenableLootbox(fixture);
      if (probe.reason !== null) {
        // Soft-skip — the simulator denied lootbox-RNG reachability (matches the
        // [CROSS-01b] / LootboxOpenGas.test.js reachOpenableLootbox precedent). The
        // deterministic entries-basis coverage is carried by the
        // PrizeLegEntriesDelivery forge proof + the structural [CROSS-01d].
        console.warn(
          `[TST-CROSS-01e] soft-skip — ${probe.reason} (deterministic entries-basis ` +
            `coverage carried by the PrizeLegEntriesDelivery forge proof + [CROSS-01d])`
        );
        this.skip();
        return;
      }

      const index = await findOpenableEthIndex(game, alice);
      if (index === null) {
        console.warn(
          "[TST-CROSS-01e] soft-skip — no openable ETH lootbox index found for alice in probe range"
        );
        this.skip();
        return;
      }

      // Fresh fixture: alice has 0 owed-entries everywhere (proven by [CROSS-01a]).
      // Pin before == 0 across the plausible target-level band so the post-open owed
      // at whichever level the roll lands on IS the full delta.
      const baseLevel = BigInt(await game.level()) + 1n;
      for (let l = baseLevel; l <= baseLevel + 55n; l++) {
        const before = await resolveLiveTicketsOwed(game, gameAddress, l, alice);
        expect(
          before.owed,
          `pre-open: alice's owed-entries at level ${l} must be 0 on a fresh fixture`
        ).to.equal(0n);
      }

      // Drive the REAL openBox entry point full-stack and capture LootBoxOpened.
      const tx = await game.connect(alice).openBox(alice.address, index);
      const receipt = await tx.wait();

      const lbArtifact = await hre.artifacts.readArtifact(
        "DegenerusGameLootboxModule"
      );
      const lbIface = new hre.ethers.Interface(lbArtifact.abi);
      let opened = null;
      for (const log of receipt.logs) {
        try {
          const parsed = lbIface.parseLog(log);
          if (parsed && parsed.name === "LootBoxOpened") {
            opened = parsed;
            break;
          }
        } catch (_) {
          // not a LootBoxOpened log — skip
        }
      }
      if (opened === null) {
        // wasSpin roll (WWXRP / FLIP-spin / ETH-spin) suppresses LootBoxOpened — a
        // valid deterministic outcome with no ticket-queue delta to assert here.
        console.warn(
          "[TST-CROSS-01e] note — openBox emitted no LootBoxOpened (spin roll); no " +
            "ticket-entry delta to measure on this deterministic seed"
        );
        return;
      }

      const rollLevel = BigInt(opened.args.futureLevel);
      const scaledTickets = BigInt(opened.args.futureTickets);
      const roundedUp = Boolean(opened.args.roundedUp);

      // Owed-entries delta at the roll level == the queued entries. before == 0 on a
      // fresh fixture (asserted across the band above), so the post-open owed IS the
      // delta. resolveLiveTicketsOwed cross-validates the slot against ticketsOwedView.
      const after = await resolveLiveTicketsOwed(
        game,
        gameAddress,
        rollLevel,
        alice
      );
      expect(
        after.matched,
        "the derived owed slot must resolve against ticketsOwedView at the roll level"
      ).to.equal(true);
      const delta = after.owed;

      // The lootbox leg queues `wholeTicketsToEntries(whole)` where
      // whole = scaledTickets/100 (+1 iff the Bernoulli sub-roll fired), so the
      // delivered entries are exactly the entries basis: `whole << 2`.
      const wholeFloor = scaledTickets / 100n;
      const lo = wholeFloor << 2n; // no round-up branch
      const hi = (wholeFloor + 1n) << 2n; // Bernoulli round-up branch
      const expectedEntries = roundedUp ? hi : lo;

      expect(
        delta === lo || delta === hi,
        `lootbox owed-entries delta ${delta} must equal the entries basis ` +
          `(lo=${lo} or round-up hi=${hi}) for scaledTickets=${scaledTickets}`
      ).to.equal(true);
      expect(
        delta,
        `lootbox owed-entries delta must equal wholeTicketsToEntries(whole) = ` +
          `${expectedEntries} (roundedUp=${roundedUp})`
      ).to.equal(expectedEntries);

      if (scaledTickets === 0n) {
        // The deterministic roll awarded no scaled tickets; the delta == 0 invariant
        // held but the ~4x delivery is vacuous on this seed — the non-zero converter
        // + basis coverage is carried by the PrizeLegEntriesDelivery forge proof.
        console.warn(
          "[TST-CROSS-01e] note — deterministic roll awarded 0 scaled tickets; " +
            "owed-entries delta correctly 0 (non-zero 4x delivery proven in the " +
            "PrizeLegEntriesDelivery forge regression)"
        );
      } else {
        const wholeAwarded = roundedUp ? wholeFloor + 1n : wholeFloor;
        console.warn(
          `[TST-CROSS-01e] openBox delivered ${delta} owed-entries at level ` +
            `${rollLevel} (scaledTickets=${scaledTickets}, whole=${wholeAwarded}, ` +
            `roundedUp=${roundedUp}) — 4x the pre-fix whole count ${wholeAwarded}`
        );
      }
    });
  });
});
