// SPDX-License-Identifier: AGPL-3.0-only
// Verify jackpot event entries match their queue values, and exercise the human
// box path through VRF settlement with nonzero ticket awards and unchanged remainder.
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
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
import { readyDailyFixture, mineAll, requestMiddayRng } from "../helpers/readyDailyFixture.js";
import { boCustom } from "../helpers/boxOrder.js";

// ---------------------------------------------------------------------------
// A wallet's stable ID is the position of its element in the `wallets` table.
// Near owed balances share one `ticketPending[id]` word (read/write lanes per level
// parity, each parity tagged with its level); far-future balances are 32-bit lanes of
// `farFutureOwed[id]`. The helper decodes the selected queue lane from the layout oracle;
// the public accessor independently attests owed totals.
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

const JACKPOT_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotModule.sol"
);
const JACKPOT_DRAW_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameJackpotDrawModule.sol"
);
const TICKET_MODULE_SOURCE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameTicketModule.sol"
);
// The same two award surfaces now live in separate pinned modules. 95d88f68b moved the
// queued main-daily ticket leg (`_resumeQueuedJackpotTickets`) verbatim from the jackpot
// module into the ticket module, so the scan covers all three, ticket leg first.
function jackpotAwardSource() {
  return fs.readFileSync(TICKET_MODULE_SOURCE_PATH, "utf8") + "\n" +
    fs.readFileSync(JACKPOT_SOURCE_PATH, "utf8") + "\n" +
    fs.readFileSync(JACKPOT_DRAW_SOURCE_PATH, "utf8");
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

describe("Cross-surface ticket events and remainder preservation", function () {
  this.timeout(600_000);

  after(function () {
    restoreAddresses();
  });

  describe("TST-CLEAN-03 — `JackpotTicketWin` entries-basis emit regression", function () {
    it("[03a] there are exactly 2 `emit JackpotTicketWin` sites and none multiply the 4th (ticketCount) arg by QTY_SCALE", function () {
      const src = jackpotAwardSource();
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

    it("[03b] the 2 emit sites emit the resumed-plan and whole-ticket entries counts", function () {
      const src = jackpotAwardSource();
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
        "uint32(plan.entriesEach)",
        "wholeTicketsToEntries(whole)",
      ]);
    });

    it("[03c] each emit site's 4th arg matches the entries value passed to its adjacent `_queueEntries` call (emit value == storage-write value)", function () {
      const src = jackpotAwardSource();
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


  });

  describe("TST-CROSS-01 — cross-surface `rem`-byte regression (live-state `entriesOwedPacked` read, D-278-TST-CROSS-DEPTH-01)", function () {
    // -----------------------------------------------------------------------
    // PRIMARY ASSERTION (D-278-TST-CROSS-DEPTH-01): a live-state raw
    // `provider.getStorage` read of the genuinely-shared
    // `entriesOwedPacked[wk][buyer]` slot, driven full-stack through mineFlip, the
    // only box-opening door (purchase -> mid-day request stage -> VRF fulfill ->
    // human-box stage). The lootbox ticket path routes through
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
      await game.connect(alice).purchase(0, 0n, boCustom(eth(1)), ZERO_BYTES32, 0, false, { value: eth(1) });
      // 1 ETH of pending box value meets the mid-day threshold: an ordinary mineFlip requests.
      const request = await requestMiddayRng(game, deployer, mockVRF);
      const aliceId = await game.walletIdOf(alice.address);
      const artifact = await hre.artifacts.readArtifact("DegenerusGameLootboxModule");
      const iface = new hre.ethers.Interface(artifact.abi);
      // Choose a ticket-paying outcome, reverting each trial. The regression must
      // exercise a nonzero award, not pass because this box rolled another reward.
      for (let word = 2n; word <= 64n; word++) {
        const snapshot = await hre.ethers.provider.send("evm_snapshot", []);
        await mockVRF.fulfillRandomWords(request, word);
        // Publication is a keeper step; the callback only stores the final word.
        await game.connect(deployer).mineFlip(0, { gasLimit: 1_000_000 });
        expect(await game.rngConsumerStage(), "publication checkpoint leaves human boxes ready").to.equal(3n);
        const receipts = await mineAll(game, deployer);
        const ticketAward = receipts.flatMap((receipt) => receipt.logs).some((log) => {
          try {
            const ev = iface.parseLog(log);
            return ev?.name === "LootBoxOpened" && ev.args.id === aliceId && ev.args.futureTickets > 0n;
          } catch { return false; }
        });
        await hre.ethers.provider.send("evm_revert", [snapshot]);
        if (ticketAward) {
          await mockVRF.fulfillRandomWords(request, word);
          await game.connect(deployer).mineFlip(0, { gasLimit: 1_000_000 });
          expect(await game.rngConsumerStage(), "selected trial remains unopened").to.equal(3n);
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

    it("[CROSS-01b] live-state: opening the box full-stack through mineFlip leaves the shared `entriesOwedPacked` `rem` byte at 0 (whole-ticket path never writes rem)", async function () {
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

      // Drive the lootbox-open path full-stack: mineFlip's human-box stage opens the
      // ready entries. Alice is the fixture's sole queued entry, so running the engine
      // to rest opens exactly her box.
      const opened = await mineAll(game, alice);
      expect(opened.length, "mineFlip opened the ready box").to.be.gt(0);

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
            `— the human lootbox open routes through _queueEntries (whole), which ` +
            `never writes the rem byte`
        ).to.equal(0);
        if (after.owed > 0n) sawWholeTicketAward = true;
      }
      expect(sawWholeTicketAward, "ordinary box must award nonzero tickets").to.be.true;
    });





    it("[CROSS-01e] live-state: opening the box full-stack through mineFlip delivers owed-entries == the entries basis (~4x the pre-fix whole count) at the roll level", async function () {
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

      // Drive the lootbox-open path full-stack and capture LootBoxOpened: mineFlip's
      // human-box stage opens the ready entries, and alice is the fixture's sole queued
      // entry, so running the engine to rest opens exactly her box.
      const receipts = await mineAll(game, alice);

      const lbArtifact = await hre.artifacts.readArtifact(
        "DegenerusGameLootboxModule"
      );
      const lbIface = new hre.ethers.Interface(lbArtifact.abi);
      let opened = null;
      const aliceId = await game.walletIdOf(alice.address);
      for (const log of receipts.flatMap((receipt) => receipt.logs)) {
        try {
          const parsed = lbIface.parseLog(log);
          if (parsed && parsed.name === "LootBoxOpened" && parsed.args.id === aliceId) {
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
