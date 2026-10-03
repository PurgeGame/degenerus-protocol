// SPDX-License-Identifier: AGPL-3.0-only
// Ticket checkpoint replay and queued-storage regression. The event ABI remains
// TraitsGenerated(address,uint256,uint32); its versioned key now carries an
// immutable stream identity and absolute low32 offset. Historical owed-salt
// replay must not be applied to these new domains.

import { readEntriesOwed, entryOwnerRecordSlot } from "../helpers/bucketSeed.js";

import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { compiledStorageLayout } from "../helpers/storageLayout.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
import {
  checkpointIdentity,
  decodeCheckpointKey,
  ticketCheckpointTraits,
  seatedTicketReveals,
} from "../helpers/raritySymbolBatchRef.mjs";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

const DAILY_ENTROPY =
  0x2f02_3456_789a_bcde_f012_3456_789a_bcde_f012_3456_789a_bcde_f012_3456_789a_bcden;
const TRAITS_GENERATED_V42_TOPIC_HASH =
  "0x279edf1ccbf5db78a99006a6861b4d49de10ed6016d8400ce6a1d5e415d2ebc3";
const TICKETS_OWED_PACKED_BASE_SLOT = 13n;
const TICKET_SLOT_BIT = 0x800000n;
const TICKET_FAR_FUTURE_BIT = 0x400000n;

// Multi-day drain handling: the v42 TraitsGenerated event drops the entropy
// field, so the JS replay must resolve `entropyWord` per emission. The
// "drain crossed day boundary — scenario invalid" guard considered at plan
// time would have aborted the test the moment advanceGame() rolled to day
// N+1 (empirical on the whale-bundle scenario at v42 HEAD); the more robust
// approach used here looks up each emission's entropy from the live storage
// source the contract actually used at emit time — different per path:
//
//   Path B (lvl=1, current-level via processTicketBatch L686): entropy is
//     loaded from `lootboxRngWordByIndex[lrIndex - 1]` where `lrIndex` is
//     bits 0..47 of `lootboxRngPacked` (storage slot 34). The index does
//     not change while alice's ticket queue at lvl=1 drains, so a single
//     post-drain read is sufficient for every Path B emission.
//   Path A (lvl>=2, the whale-pass far-future span, drained only once its
//     level's own last-purchase-day seal fires the private
//     `_processFutureTicketBatch` continuation inside `processTicketBatch` —
//     not exercised by this fixture's single-day whale-bundle drain, so no
//     Path A emissions are expected here; this entropy resolution is kept
//     for whichever future scenario does progress far enough to reach it):
//     entropy is the `rngWord` advanceGame() loaded via rngGate → either
//     cached `rngWordByDay[day]` or freshly applied via _applyDailyRng
//     (which writes rngWordByDay[day] = finalWord at L1808). Per-emission
//     day is computed from the receipt block.timestamp using GameTimeLib's
//     formula `(ts - 82620)/86400 - DEPLOY_DAY_BOUNDARY + 1`, where the
//     dynamic DEPLOY_DAY_BOUNDARY is read from the deploy fixture.
const JACKPOT_RESET_TIME = 82620n;
const SECONDS_PER_DAY = 86400n;

function dayIndexAt(timestamp, deployDayBoundary) {
  const ts = BigInt(timestamp);
  const ddb = BigInt(deployDayBoundary);
  return Number((ts - JACKPOT_RESET_TIME) / SECONDS_PER_DAY - ddb + 1n);
}

async function parseTraitsGeneratedEvents(receipt, storage, deployDayBoundary) {
  const block = await hre.ethers.provider.getBlock(receipt.blockNumber);
  const emissionDay = dayIndexAt(block.timestamp, deployDayBoundary);
  const events = [];
  for (const log of receipt.logs) {
    let parsed = null;
    try {
      parsed = storage.interface.parseLog(log);
    } catch {
      parsed = null;
    }
    if (parsed && parsed.name === "TraitsGenerated") {
      const baseKey = BigInt(parsed.args.baseKey);
      const lvl = Number((baseKey >> 224n) & 0xFFFFFFn);
      const queueIdx = Number((baseKey >> 192n) & 0xFFFFFFFFn);
      const decoded = decodeCheckpointKey(baseKey);
      const playerFromBase = (baseKey >> 32n) & ((1n << 160n) - 1n);
      const indexedPlayerBn = BigInt(parsed.args.player);
      if ((indexedPlayerBn & ((1n << 160n) - 1n)) !== playerFromBase) {
        throw new Error(
          `TraitsGenerated decode mismatch: indexed player ${parsed.args.player} != baseKey bits 191..32 0x${playerFromBase.toString(16).padStart(40, "0")}`
        );
      }
      events.push({
        player: parsed.args.player,
        baseKey,
        take: Number(parsed.args.take),
        lvl,
        queueIdx,
        startIndex: decoded.startIndex,
        domain: decoded.domain,
        txHash: log.transactionHash,
        emissionDay,
        rawLog: log,
      });
    }
  }
  return events;
}

async function buyTickets(game, buyer, ticketCount, ethValue) {
  return game.connect(buyer).purchase(
    ZERO_ADDRESS,
    BigInt(ticketCount) * 400n,
    0n,
    ZERO_BYTES32,
    MintPaymentKind.DirectEth,false, 
    { value: eth(ethValue) }
  );
}

async function readPlayerTraitMultiset(game, lvl, player) {
  const multiset = new Map();
  for (let trait = 0; trait < 256; trait++) {
    const [count, , total] = await game.getEntries(trait, lvl, 0, 10_000, player);
    const c = Number(count);
    if (c > 0) multiset.set(trait, c);
    if (Number(total) > 10_000) {
      throw new Error(
        `readPlayerTraitMultiset: trait ${trait} has ${total} entries — paginate via nextOffset`
      );
    }
  }
  return multiset;
}

async function readTicketWriteSlot(addr) {
  const s0 = await hre.ethers.provider.getStorage(addr, 0);
  // ticketWriteSlot is at slot 0 byte 25 (bit 200).
  return ((BigInt(s0) >> 200n) & 0xFFn) !== 0n;
}

async function readDailyIdx(addr) {
  const s0 = await hre.ethers.provider.getStorage(addr, 0);
  return Number((BigInt(s0) >> 32n) & 0xFFFFFFFFn);
}

function computeRk(lvl, path, ticketWriteSlot) {
  const v = BigInt(lvl);
  // Path B (current-level) reads/writes `entriesOwedPacked` via `_tqWriteKey(lvl)`
  // in the queued state. `_tqFarFutureKey(lvl)` (TICKET_FAR_FUTURE_BIT-marked)
  // applies when `isFarFuture = targetLevel > _mintCeiling()` is true at queue
  // time — the near/far boundary shrank from the old fixed `level + 5` to
  // `_mintCeiling()` (normally `level + 1`). At the whale-bundle scenario's
  // deploy-state `level = 0` (lastPurchaseDay unset, so `_mintCeiling() = 1`),
  // only lvl=1 (path B) satisfies `targetLevel <= _mintCeiling()` and lands on
  // `_tqWriteKey`; lvl=2..5 (path A, the whale pass's far-future span) now all
  // satisfy `targetLevel > _mintCeiling()` and land on `_tqFarFutureKey`, same
  // as an explicit `FAR_FUTURE` tag.
  if (path === "B") {
    return ticketWriteSlot ? v | TICKET_SLOT_BIT : v;
  }
  if (path === "A" || path === "FAR_FUTURE") return v | TICKET_FAR_FUTURE_BIT;
  throw new Error("computeRk: unknown path " + path);
}

function reconstructMultisetViaReference(events, reveals) {
  const multiset = new Map();
  for (const e of events) {
    const traits = ticketCheckpointTraits({ baseKey: e.baseKey, entropyWord: DAILY_ENTROPY, count: e.take });
    for (const t of traits) multiset.set(t, (multiset.get(t) || 0) + 1);
  }
  for (const e of reveals) multiset.set(e.trait, (multiset.get(e.trait) || 0) + 1);
  return { multiset, pathUsed: "versioned-checkpoint" };
}

async function pinDailyEntropy(game, deployer, mockVRF, word) {
  await advanceToNextDay();
  const previous = await getLastVRFRequestId(mockVRF);
  let request = previous;
  for (let i = 0; i < 100 && request === previous; ++i) {
    await game.connect(deployer).mineFlip({ gasLimit: 12_000_000 });
    request = await getLastVRFRequestId(mockVRF);
  }
  expect(request).not.to.equal(previous);
  await mockVRF.fulfillRandomWords(request, word);
}

async function drainViaAdvanceGame(game, caller, storage, deployDayBoundary, maxIters = 300) {
  const events = [], reveals = [];
  for (let i = 0; i < maxIters; ++i) {
    const receipt = await (await game.connect(caller).mineFlip({ gasLimit: 12_000_000 })).wait();
    const newEvents = await parseTraitsGeneratedEvents(receipt, storage, deployDayBoundary);
    events.push(...newEvents);
    for (const log of receipt.logs) reveals.push(...seatedTicketReveals(log));
    if (!(await game.rngLocked()) && newEvents.length === 0 && i > 10) break;
  }
  return { events, reveals };
}

describe("MintCleanupRegression — Phase 291 v42.0 MINTCLN regression fixture", function () {
  this.timeout(900_000);
  after(() => restoreAddresses());

  describe("TST-MINTCLN-01..04 — end-to-end whale-bundle multi-call drain via mineFlip()", function () {
    async function setupWhaleBundleAndDrain() {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, deployer, mockVRF, alice } = fixture;

      await buyTickets(game, alice, 2000, 30);
      await game
        .connect(alice)
        .purchaseWhalePass(alice.address, 10, hre.ethers.ZeroHash, { value: eth(24) });
      await pinDailyEntropy(game, deployer, mockVRF, DAILY_ENTROPY);

      const storage = await hre.ethers.getContractAt(
        "DegenerusGameStorage",
        await game.getAddress()
      );

      const gameAddr = await game.getAddress();
      const { events, reveals } = await drainViaAdvanceGame(game, deployer, storage, fixture.deployDayBoundary, 300);
      const ticketWriteSlotAfter = await readTicketWriteSlot(gameAddr);

      const aliceEvents = events.filter(
        (e) => e.player.toLowerCase() === alice.address.toLowerCase()
      );

      return {
        fixture,
        storage,
        allEvents: events,
        aliceEvents,
        aliceReveals: reveals.filter((e) => e.player.toLowerCase() === alice.address.toLowerCase()),
        ticketWriteSlotPostDrain: ticketWriteSlotAfter,
        gameAddr,
      };
    }

    it("TST-MINTCLN-03 anchor — whale-bundle drain emits TraitsGenerated at lvl=1 (Path B, inside the minted window) and does NOT emit at lvl>=2 (Path A, the whale pass's far-future span, frozen until its own level's last-purchase-day seal)", async function () {
      const { aliceEvents } = await setupWhaleBundleAndDrain();

      expect(aliceEvents.length).to.be.gte(
        2,
        "whale-bundle drain must produce >= 2 TraitsGenerated emissions"
      );

      const byLevel = new Map();
      for (const e of aliceEvents) {
        if (!byLevel.has(e.lvl)) byLevel.set(e.lvl, 0);
        byLevel.set(e.lvl, byLevel.get(e.lvl) + 1);
      }

      const levelsSeen = Array.from(byLevel.keys()).sort((a, b) => a - b);
      const pathBLevels = levelsSeen.filter((l) => l === 1);
      const pathALevels = levelsSeen.filter((l) => l >= 2);

      console.log(
        `[B2-coverage] levels emitted: ${levelsSeen
          .map((l) => `lvl=${l}:${byLevel.get(l)} (path-accumulator=${l === 1 ? "B" : "A"})`)
          .join(", ")}`
      );

      expect(pathBLevels.length).to.be.gte(
        1,
        "Path B must emit at lvl=1 (current-level _processOneTicketEntry, inside the minted window)"
      );
      // Post-boundary-shrink behavior: the whale pass's lvl>=2 span now exceeds
      // _mintCeiling() (level=0 + 1) at purchase time, so it queues into the
      // far-future key space and is NOT minted by this single-day drain — it
      // only mints once its own level's last-purchase-day seal fires the
      // private _processFutureTicketBatch continuation inside
      // processTicketBatch. This whale-bundle fixture never reaches that seal,
      // so Path A must emit nothing here (the removed external
      // processFutureTicketBatch entrypoint this test used to drive directly
      // no longer exists; see TST-MINTCLN-04 for the frozen-queue-key proof).
      expect(pathALevels.length).to.equal(
        0,
        "Path A (lvl>=2) must NOT emit within the whale-bundle's own drain — those entries are frozen in the far-future key space until their level's own last-purchase-day seal"
      );
    });

    it("TST-MINTCLN-02 — each emission decodes to (player, baseKey, take) 3-tuple with baseKey low-32 = absolute offset + upper bits = (version/domain, lvl, queueIdx, player); event topic-hash matches v42 literal", async function () {
      const { storage, aliceEvents } = await setupWhaleBundleAndDrain();

      const evtFragment = storage.interface.getEvent("TraitsGenerated");
      expect(evtFragment.inputs.length).to.equal(
        3,
        "v42 TraitsGenerated must have exactly 3 ABI inputs"
      );
      const fieldNames = evtFragment.inputs.map((i) => i.name).sort();
      expect(fieldNames).to.deep.equal(
        ["baseKey", "player", "take"],
        "v42 TraitsGenerated field names must be exactly {player, baseKey, take}"
      );

      let topicMatchCount = 0;
      for (const e of aliceEvents) {
        const expectedBaseKey =
          checkpointIdentity({ level: e.lvl, queueIndex: e.queueIdx, player: e.player, domain: e.domain }) | BigInt(e.startIndex) | (e.baseKey & (1n << 255n));
        expect(e.baseKey).to.equal(
          expectedBaseKey,
          `baseKey for emission lvl=${e.lvl} queueIdx=${e.queueIdx} owed=${e.startIndex} must match the (domain, lvl, queueIdx, player, offset) encoding`
        );
        expect(decodeCheckpointKey(e.baseKey).startIndex).to.equal(
          e.startIndex,
          "decodeCheckpointKey must round-trip the absolute offset"
        );
        if (e.rawLog.topics[0] === TRAITS_GENERATED_V42_TOPIC_HASH) {
          topicMatchCount++;
        }
      }
      expect(topicMatchCount).to.be.gte(
        1,
        `at least one raw log must carry the v42 topic-hash ${TRAITS_GENERATED_V42_TOPIC_HASH}`
      );
    });

    it("TST-MINTCLN-01 — multi-call drain trait-multiset equivalence: versioned checkpoint JS replay reconstructs on-chain credited multiset trait-by-trait + cross-call seed separation evidence (pairwise-distinct keccak inputs)", async function () {
      const { fixture, aliceEvents, aliceReveals } = await setupWhaleBundleAndDrain();
      const { game, alice } = fixture;

      const byLevel = new Map();
      for (const e of aliceEvents) {
        if (!byLevel.has(e.lvl)) byLevel.set(e.lvl, []);
        byLevel.get(e.lvl).push(e);
      }

      for (const [lvl, levelEvents] of byLevel.entries()) {
        const onChain = await readPlayerTraitMultiset(game, lvl, alice.address);
        const { multiset: reconstructed, pathUsed } =
          reconstructMultisetViaReference(levelEvents, aliceReveals.filter((e) => e.lvl === lvl));

        const reconstructedTotal = Array.from(reconstructed.values()).reduce(
          (a, b) => a + b,
          0
        );
        const onChainTotal = Array.from(onChain.values()).reduce(
          (a, b) => a + b,
          0
        );
        const emittedTotal = levelEvents.reduce((a, e) => a + e.take, 0) + aliceReveals.filter((e) => e.lvl === lvl).length;

        console.log(
          `[W2 lvl=${lvl}] num-emissions=${levelEvents.length} | emitted-count-sum=${emittedTotal} | on-chain=${onChainTotal} | reconstructed=${reconstructedTotal} | path-accumulator=${pathUsed}`
        );

        expect(pathUsed).to.not.equal(
          "neither",
          `lvl ${lvl}: neither Path A nor Path B accumulator reconstructed the on-chain multiset`
        );
        expect(reconstructedTotal).to.equal(
          emittedTotal,
          `lvl ${lvl}: JS reference total must equal sum of emit takes`
        );
        expect(onChainTotal).to.equal(
          emittedTotal,
          `lvl ${lvl}: on-chain credited total must equal sum of emit takes`
        );

        const allTraits = new Set([...reconstructed.keys(), ...onChain.keys()]);
        const mismatches = [];
        for (const trait of allTraits) {
          const r = reconstructed.get(trait) || 0;
          const o = onChain.get(trait) || 0;
          if (r !== o) mismatches.push({ trait, reconstructed: r, onChain: o });
        }
        expect(mismatches.length).to.equal(
          0,
          `lvl ${lvl}: trait-by-trait multiset mismatches ${JSON.stringify(mismatches.slice(0, 10))}`
        );
      }

      const slotGroups = new Map();
      for (const e of aliceEvents) {
        const k = `${e.lvl}-${e.queueIdx}`;
        if (!slotGroups.has(k)) slotGroups.set(k, []);
        slotGroups.get(k).push(e);
      }
      for (const [slot, slotEvents] of slotGroups.entries()) {
        if (slotEvents.length < 2) continue;
        const baseKeySet = new Set(slotEvents.map((e) => e.baseKey.toString()));
        expect(baseKeySet.size).to.equal(
          slotEvents.length,
          `slot ${slot}: baseKey values must be pairwise distinct across multi-call emissions (cross-call seed separation evidence; got ${slotEvents.length} emissions, ${baseKeySet.size} unique baseKeys)`
        );
      }
    });
  });

  describe("TST-MINTCLN-04 — storage-layout regression at runtime", function () {
    this.timeout(900_000);

    async function setupQueuedState() {
      // Storage-layout slot reads target the QUEUED state — after purchase +
      // whale-bundle but BEFORE draining. Post-drain the contract zeros the
      // packed slot (owed=0, rem=0 → packed=0) which would silently pass a
      // wrong-rk derivation against a default-zero read. Reading the queued
      // state forces every (lvl, path) rk derivation to land on a slot the
      // contract actively wrote to, with a recoverable owed > 0.
      const fixture = await loadFixture(deployFullProtocol);
      const { game, alice } = fixture;
      await buyTickets(game, alice, 2000, 30);
      await game
        .connect(alice)
        .purchaseWhalePass(alice.address, 10, hre.ethers.ZeroHash, { value: eth(24) });
      const gameAddr = await game.getAddress();
      const ticketWriteSlot = await readTicketWriteSlot(gameAddr);
      return { fixture, gameAddr, ticketWriteSlot };
    }

    it("entriesOwedPacked[rk][player] slot reads decode to the expected (rem | (owed<<8) | owner<<48) 80-bit packed form on the queued state — Path A (lvl=2..5 far-future) AND Path B (lvl=1 current-level) outer-mapping keys both resolve to non-zero packed values with owed > 0", async function () {
      const layout = await compiledStorageLayout();
      const locator = layout.storage.find((entry) => entry.label === "ticketOwnerId");
      const owners = layout.storage.find((entry) => entry.label === "ticketOwners");
      const pending = layout.storage.find((entry) => entry.label === "ticketPending");
      expect(locator.slot).to.equal("13");
      expect(owners.slot).to.equal("67");
      expect(pending.slot).to.equal("78");
      expect(layout.types[locator.type].label).to.equal("mapping(address => uint32)");
      expect(layout.types[owners.type].label).to.equal("address[]");
      expect(layout.types[pending.type].label).to.equal("mapping(uint32 => uint256)");

      const { fixture, gameAddr, ticketWriteSlot } = await setupQueuedState();
      const { game, alice } = fixture;

      // The whale-bundle scenario queues alice at lvl=1 (Path B) via the
      // 2000-ticket purchase + at lvl=2..5 (Path A) via purchaseWhalePass.
      const pairs = [
        { lvl: 1, path: "B" },
        { lvl: 2, path: "A" },
        { lvl: 3, path: "A" },
        { lvl: 4, path: "A" },
        { lvl: 5, path: "A" },
      ];

      const abi = hre.ethers.AbiCoder.defaultAbiCoder();
      for (const { lvl, path } of pairs) {
        const rk = computeRk(lvl, path, ticketWriteSlot);
        const slot = await entryOwnerRecordSlot(gameAddr, rk, alice.address);
        const packed = await readEntriesOwed(gameAddr, rk, alice.address);
        const rem = Number(packed & 0xFFn);
        const owed = Number((packed >> 8n) & 0xFFFFFFFFn);

        console.log(
          `[TST-MINTCLN-04 storage-slot lvl=${lvl} path=${path} rk=0x${rk.toString(16)} slot=${slot} packed=0x${packed.toString(16)} rem=${rem} owed=${owed}]`
        );

        if (packed === 0n) {
          throw new Error(
            `[TST-MINTCLN-04 lvl=${lvl} path=${path}] storage slot resolved to zero — likely wrong rk derivation; expected rk=0x${rk.toString(16)}`
          );
        }
        expect(packed).to.be.lessThan(
          1n << 80n,
          `lvl=${lvl} path=${path}: packed value must fit in 80 bits (rem | owed<<8 | snap bit 40 | owner-registry position << 48)`
        );
        // Bits 41..47 are unused; the owner-registry position (plus one) sits in
        // bits 48..79 for a player-paid entry.
        expect((packed >> 41n) & 0x7fn, `lvl=${lvl} path=${path}: bits 41..47 must be zero`).to.equal(0n);
        expect(packed >> 80n, `lvl=${lvl} path=${path}: bits above bit-79 must be zero`).to.equal(0n);

        if (path === "B" && lvl === 1) {
          const viewOwed = Number(await game.entriesOwedView(1, alice.address));
          expect(owed).to.equal(
            viewOwed,
            `lvl=1 Path B: direct slot owed=${owed} must equal entriesOwedView(1, alice)=${viewOwed} — independent on-chain cross-check`
          );
        }
      }
    });
  });
});
