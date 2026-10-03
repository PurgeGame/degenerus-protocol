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
//     `entriesOwedPacked` — the `uint32(entriesEach)` leg and the BAF
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

import { readEntriesOwed, entryOwnerRecordSlot } from "../helpers/bucketSeed.js";

import { expect } from "chai";
import hre from "hardhat";
import fs from "node:fs";
import path from "node:path";
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
import { readyDailyFixture } from "../helpers/readyDailyFixture.js";
import { boCustom } from "../helpers/boxOrder.js";

const MINT_MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameMintModule.sol"
);

// ---------------------------------------------------------------------------
// Slot 13 maps wallets to stable IDs; slot 67 is the global immutable address array.
// Slot 78 holds three pending lanes per logical level and ID. The helper decodes
// the selected queue lane; the public accessor independently attests owed totals.
async function readTicketsOwedSlot(gameAddress, wk, buyer) {
  const slot = await entryOwnerRecordSlot(gameAddress, wk, buyer);
  const word = await readEntriesOwed(gameAddress, wk, buyer);
  // The value is uint80, but owed (bits [8..39]) and rem (bits [0..7]) both sit
  // in the low 40 bits; masking there isolates them below the bit-40 snap-done
  // marker, mirroring the contract's `uint32(packed >> 8)` owed read.
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
// args, respecting nested parens so `uint32(entriesEach)` stays one arg.
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
        // entries count queued (`uint32(entriesEach)` / `wholeTicketsToEntries(whole)`)
        // — never a `* QTY_SCALE` scaled value.
        expect(
          /QTY_SCALE/.test(args[3]),
          `JackpotTicketWin 4th arg \`${args[3]}\` must not reference QTY_SCALE — emit the queued entries count`
        ).to.equal(false);
      }
    });

    it("[03b] the 2 emit sites emit, in source order, the entries counts `uint32(entriesEach)`, `wholeTicketsToEntries(whole)`", function () {
      const src = fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8");
      const emitMatches = [...src.matchAll(/emit JackpotTicketWin\(/g)];
      const fourthArgs = emitMatches.map((m) => {
        const argList = extractCallArgs(
          src.slice(m.index),
          "emit JackpotTicketWin("
        );
        return splitTopLevelArgs(argList)[3];
      });
      // Site 1 (the ticket-jackpot leg): `uint32(entriesEach)`, a whole-ticket
      // multiple identical for every winner in the draw —
      // `_budgetToEntries` already returns entries. Site 2 (the BAF
      // `_jackpotTicketRoll`): the post-Bernoulli whole count routed through the
      // canonical `wholeTicketsToEntries`. Each matches the entries value passed
      // to the adjacent `_queueEntries` call.
      expect(fourthArgs).to.deep.equal([
        "uint32(entriesEach)",
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
    async function reachOpenableLootbox(fixture) {
      const { game, deployer, mockVRF, alice } = fixture;
      const layout = JSON.parse(fs.readFileSync("scripts/layout/golden/DegenerusGame.json", "utf8"));
      const root = layout.find((entry) => entry.label === "rngFlagsAndNudges");
      expect(root, "current RNG buffer storage root").to.not.be.undefined;
      const flags = BigInt(await hre.ethers.provider.getStorage(await game.getAddress(), root.slot)) >> (BigInt(root.offset) * 8n);
      const index = (flags >> 12n) & 1n;
      await game.connect(alice).purchase(alice.address, 0n, boCustom(eth(1)), ZERO_BYTES32, 0, false, { value: eth(1) });
      await game.connect(deployer).requestLootboxRng();
      const request = await getLastVRFRequestId(mockVRF);
      const artifact = await hre.artifacts.readArtifact("DegenerusGameLootboxModule");
      const iface = new hre.ethers.Interface(artifact.abi);
      // Choose a ticket-paying outcome, reverting each trial. The regression must
      // exercise a nonzero award, not pass because this box rolled another reward.
      for (let word = 2n; word <= 64n; word++) {
        const snapshot = await hre.ethers.provider.send("evm_snapshot", []);
        await mockVRF.fulfillRandomWords(request, word);
        // Publication is a keeper step; the callback only stores the final word.
        await game.connect(deployer).mineFlip();
        const receipt = await (await game.openBoxes(hre.ethers.MaxUint256)).wait();
        const ticketAward = receipt.logs.some((log) => {
          try {
            const ev = iface.parseLog(log);
            return ev?.name === "LootBoxOpened" && ev.args.player === alice.address && ev.args.futureTickets > 0n;
          } catch { return false; }
        });
        await hre.ethers.provider.send("evm_revert", [snapshot]);
        if (ticketAward) {
          await mockVRF.fulfillRandomWords(request, word);
          await game.connect(deployer).mineFlip();
          return index;
        }
      }
      throw new Error("fixture did not find a nonzero ordinary-box ticket award");
    }

    // Resolve the live `entriesOwedPacked` slot for `player` at `lvl` by
    // probing the three candidate write-keys (`lvl`, `lvl | TICKET_SLOT_BIT`
    // — the double-buffer toggle — and the far-future key `lvl | 1<<22`) and
    // selecting the key whose slot read's `owed` matches the public
    // `entriesOwedView(lvl, player)` accessor. This makes the slot math
    // self-validating without needing the internal `ticketWriteSlot` bool.
    async function resolveLiveTicketsOwed(game, gameAddress, lvl, player) {
      const TICKET_SLOT_BIT = 1n << 23n;
      const FAR_FUTURE_BIT = 1n << 22n;
      const viewWhole = BigInt(
        await game.entriesOwedView(lvl, player.address)
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
        "entriesOwedView must agree the player has 0 whole tickets at baseline"
      ).to.equal(0n);
    });

    it("[CROSS-01b] live-state: driving the REAL `openBox` entry point full-stack leaves the shared `entriesOwedPacked` `rem` byte at 0 (whole-ticket path never writes rem)", async function () {
      const fixture = await loadFixture(readyDailyFixture);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();
      const index = await reachOpenableLootbox(fixture);

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

      // Drive the REAL lootbox-open path full-stack. The removed per-(player,index)
      // `openBox` entry point is gone; `openBoxes(MaxUint256)` is its permissionless
      // sweep replacement — alice is the fixture's sole queued entry, so draining
      // everything ready opens exactly her box and then finds nothing else to do.
      await game.connect(alice).openBoxes(hre.ethers.MaxUint256);

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
      expect(sawWholeTicketAward, "ordinary box must award nonzero tickets").to.be.true;
    });

    it("[CROSS-01c] slot-math self-validation: the derived `entriesOwedPacked` slot's `owed` field round-trips against the public `entriesOwedView` accessor", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();
      const currentLevel = BigInt(await game.level()) + 1n;

      // At baseline both the raw-slot `owed` and `entriesOwedView` are 0 — a
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
          "entriesOwedView (keccak nesting: keccak256(abi.encode(buyer, " +
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

      // (1) `_queueEntries` body packs `(packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem)`
      //     with `rem` carried UNCHANGED from the pre-existing slot value — it never
      //     computes a fraction. The owner-registry bits ride along untouched.
      const queueBody = extractBody(storage, "function _queueEntries(");
      expect(queueBody, "_queueEntries body not found").to.not.equal(null);
      expect(
        /_setEntryOwed\(wk,\s*uint32\(packed\s*>>\s*OWNER_IDX_SHIFT\),\s*\(packed\s*&\s*OWNER_IDX_MASK\)\s*\|\s*\(uint80\(owed\)\s*<<\s*8\)\s*\|\s*uint80\(rem\)/.test(
          queueBody
        ),
        "_queueEntries must pack `(packed & OWNER_IDX_MASK) | (uint80(owed) << 8) | uint80(rem)` with rem carried from the existing slot"
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

      // (3) Manual + auto-resolve lootbox surfaces: both settle through the
      //     shared per-entry `_flushBoxAcc` (box-order rework: one box = one
      //     roll, rewards settle once per entry), which routes each tier's
      //     ticket award through `_queueEntries` at `currentLevel + uint24(offset)`,
      //     converting the post-Bernoulli whole count to entries via the
      //     canonical `wholeTicketsToEntries`, and contains ZERO
      //     `_queueEntriesScaled` invocations.
      expect(
        lootboxSrc.includes(
          "_queueEntries(player, currentLevel + uint24(offset), wholeTicketsToEntries(whole), false)"
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
      const fixture = await loadFixture(readyDailyFixture);
      const { game, alice } = fixture;
      const gameAddress = await game.getAddress();
      const index = await reachOpenableLootbox(fixture);

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

      // Drive the REAL lootbox-open path full-stack and capture LootBoxOpened. The
      // removed per-(player,index) `openBox` entry point is gone; `openBoxes(MaxUint256)`
      // is its permissionless sweep replacement — alice is the fixture's sole queued
      // entry, so draining everything ready opens exactly her box.
      const tx = await game.connect(alice).openBoxes(hre.ethers.MaxUint256);
      const receipt = await tx.wait();

      const lbArtifact = await hre.artifacts.readArtifact(
        "DegenerusGameLootboxModule"
      );
      const lbIface = new hre.ethers.Interface(lbArtifact.abi);
      let opened = null;
      for (const log of receipt.logs) {
        try {
          const parsed = lbIface.parseLog(log);
          if (parsed && parsed.name === "LootBoxOpened" && parsed.args.player === alice.address) {
            opened = parsed;
            break;
          }
        } catch (_) {
          // not a LootBoxOpened log — skip
        }
      }
      expect(opened, "ticket-paying fixture must emit LootBoxOpened").to.not.equal(null);
      expect(opened.args.futureTickets, "ticket award must be nonzero").to.be.gt(0n);

      const rollLevel = BigInt(opened.args.futureLevel);
      const scaledTickets = BigInt(opened.args.futureTickets);
      const roundedUp = Boolean(opened.args.roundedUp);

      // Owed-entries delta at the roll level == the queued entries. before == 0 on a
      // fresh fixture (asserted across the band above), so the post-open owed IS the
      // delta. resolveLiveTicketsOwed cross-validates the slot against entriesOwedView.
      const after = await resolveLiveTicketsOwed(
        game,
        gameAddress,
        rollLevel,
        alice
      );
      expect(
        after.matched,
        "the derived owed slot must resolve against entriesOwedView at the roll level"
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


    });
  });
});
