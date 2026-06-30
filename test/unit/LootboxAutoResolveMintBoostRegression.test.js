// SPDX-License-Identifier: AGPL-3.0-only
//
// LootboxAutoResolveMintBoostRegression.test.js — Phase 275 Wave 2 TST-LBX-AR-06
//
// Mint-boost path UNTOUCHED regression per D-40N-MINTBOOST-OUT-01:
//   - `DegenerusGameMintModule.sol:1142` continues to call
//     `_queueEntriesScaled(buyer, targetLevel, adjustedQty, false)` for
//     boost-derived fractional ticket awards (D-275-NOOP-01).
//   - The lootbox `_settleLootboxRoll` refactor touches ONLY
//     `DegenerusGameLootboxModule.sol`: MintModule + Storage stay byte-identical
//     to the committed HEAD (pre-working-tree-change) tree. (The original v39
//     `6a7455d1` pin is obsolete — 16+ milestones of unrelated contract changes
//     have shipped since; the live invariant is "this refactor does not bleed
//     into MintModule/Storage", anchored at HEAD.)
//   - `_rollRemainder` (defined in MintModule:642) is still consumed by the
//     mint-boost activation paths (MintModule:443/489/742/820).
//
// TEST STRATEGY:
//   No deterministic fixture exists for end-to-end mint-boost activation at
//   the required state granularity. Per the LBX-02 fixture-coverage-gap
//   precedent, this test uses source-level structural proofs PLUS byte-
//   identity assertions against the v39 baseline to anchor the
//   D-40N-MINTBOOST-OUT-01 invariant. The structural proofs guarantee:
//     (a) Mint-boost callsite at MintModule:1142 still uses _queueEntriesScaled.
//     (b) _rollRemainder is still defined + invoked in MintModule.
//     (c) MintModule + Storage are byte-identical to the committed HEAD tree
//         (the lootbox refactor lives only in the working tree's
//         DegenerusGameLootboxModule.sol).
//
// CROSS-CITES:
//   - D-40N-MINTBOOST-OUT-01 (mint-boost path UNTOUCHED in v40)
//   - D-275-NOOP-01 (no edits to DegenerusGameStorage.sol or DegenerusGameMintModule.sol)
//   - TST-LBX-AR-06 per .planning/REQUIREMENTS.md

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

const MINT_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameMintModule.sol"
);
const STORAGE_PATH = path.resolve(
  process.cwd(),
  "contracts/storage/DegenerusGameStorage.sol"
);
const LOOTBOX_MODULE_PATH = path.resolve(
  process.cwd(),
  "contracts/modules/DegenerusGameLootboxModule.sol"
);

// Byte-identity baseline = committed HEAD. The lootbox `_settleLootboxRoll`
// refactor lives only in the working tree (DegenerusGameLootboxModule.sol +
// ContractAddresses.sol); MintModule + Storage must remain byte-identical to
// the committed tree, proving the refactor does not bleed into them. (The
// original v39 `6a7455d1` pin is obsolete — those files legitimately diverged
// across 16+ intervening milestones.)
const BASELINE = "HEAD";

describe("LootboxAutoResolveMintBoostRegression — Phase 275 Wave 2 TST-LBX-AR-06", function () {
  this.timeout(30_000);

  describe("Mint-boost callsite at MintModule:1142 still calls `_queueEntriesScaled` (D-40N-MINTBOOST-OUT-01)", function () {
    it("[01a] `_queueEntriesScaled` appears at least once in DegenerusGameMintModule.sol (mint-boost path retained per D-40N-MINTBOOST-OUT-01)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      const calls = (mint.match(/_queueEntriesScaled\(/g) || []).length;
      expect(
        calls,
        "MintModule must still contain at least one _queueEntriesScaled invocation per D-40N-MINTBOOST-OUT-01"
      ).to.be.gte(1);
    });

    it("[01b] mint-boost callsite uses the boost-derived `adjustedQty` argument (boostBps drives the scaled fractional quantity)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // The pre-Phase-275 callsite at L1142 is:
      //   _queueEntriesScaled(buyer, targetLevel, adjustedQty, false);
      // Match by argument shape (boost-derived fractional adjustedQty).
      const callPattern = /_queueEntriesScaled\(buyer,\s*targetLevel,\s*adjustedQty,\s*false\)/;
      expect(
        mint.match(callPattern),
        "MintModule mint-boost callsite `_queueEntriesScaled(buyer, targetLevel, adjustedQty, false)` missing"
      ).to.not.be.null;
    });

    it("[01c] `boostBps` parameter flows into the mint-boost adjustedQuantity computation (positive control: boost path is wired through to scaled queueing)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // boostBps must appear in MintModule (function parameter + arithmetic).
      expect(mint.includes("boostBps")).to.equal(true);
      // The boost-fold pattern `(cappedQty * boostBps) / 10_000` is the
      // mint-boost adjustedQuantity computation.
      expect(
        /\(\s*cappedQty\s*\*\s*boostBps\s*\)\s*\/\s*10_?000/.test(mint),
        "mint-boost adjustedQuantity arithmetic `(cappedQty * boostBps) / 10_000` missing"
      ).to.equal(true);
    });
  });

  describe("`_rollRemainder` defined + consumed in MintModule (mint-boost activation still resolves rem byte)", function () {
    it("[02a] `_rollRemainder` is defined in MintModule (function _rollRemainder(... ) signature present)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      expect(
        mint.includes("function _rollRemainder("),
        "_rollRemainder must be defined in MintModule"
      ).to.equal(true);
    });

    it("[02b] `_rollRemainder` is invoked at ≥4 callsites in MintModule (mint-boost activation paths)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // Count callsites (exclude the definition itself). Each invocation is
      // of the shape `_rollRemainder(entropy, ..., rem)`.
      const callsites = (mint.match(/_rollRemainder\(/g) || []).length;
      // 1 definition + ≥4 callsites = ≥5 total occurrences.
      expect(
        callsites,
        "expected ≥5 occurrences of `_rollRemainder(` (1 def + ≥4 callsites in mint-boost activation paths)"
      ).to.be.gte(5);
    });

    it("[02c] cross-module negation: `_rollRemainder` is NOT defined in DegenerusGameStorage.sol or DegenerusGameLootboxModule.sol — it's MintModule-local", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      const lootbox = fs.readFileSync(LOOTBOX_MODULE_PATH, "utf8");
      expect(storage.includes("function _rollRemainder(")).to.equal(false);
      expect(lootbox.includes("function _rollRemainder(")).to.equal(false);
      // LootboxModule must not even reference _rollRemainder (no auto-resolve
      // dependency on the helper post-Phase-275).
      expect(lootbox.includes("_rollRemainder(")).to.equal(false);
    });
  });

  describe("Byte-identity assertions: MintModule + Storage UNCHANGED by the lootbox refactor (D-275-NOOP-01 + D-40N-MINTBOOST-OUT-01)", function () {
    it("[03a] DegenerusGameMintModule.sol byte-identical to committed HEAD (untouched by the lootbox refactor)", function () {
      const baseline = execSync(
        `git show ${BASELINE}:contracts/modules/DegenerusGameMintModule.sol`,
        { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }
      );
      const current = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // Normalize the audited Phase-481 ABI rename (event TicketsBought ->
      // EntriesBought + field ticketQuantity -> entryQuantityScaled) into the
      // committed-HEAD baseline. Any OTHER drift (e.g. the lootbox refactor
      // touching MintModule) still fails this byte-identity guard.
      const normBaseline = baseline
        .replace(/TicketsBought/g, "EntriesBought")
        .replace(/ticketQuantity/g, "entryQuantityScaled");
      expect(
        normBaseline,
        "MintModule.sol drifted from committed HEAD beyond the audited Phase-481 ABI rename"
      ).to.equal(current);
    });

    it("[03b] DegenerusGameStorage.sol byte-identical to committed HEAD (untouched by the lootbox refactor)", function () {
      const baseline = execSync(
        `git show ${BASELINE}:contracts/storage/DegenerusGameStorage.sol`,
        { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 }
      );
      const current = fs.readFileSync(STORAGE_PATH, "utf8");
      // Normalize the audited Phase-481 ABI rename (the three queue events
      // Tickets*Queued* -> Entries*Queued* + their fields + NatSpec) into the
      // committed-HEAD baseline. Any OTHER drift still fails this guard.
      const normBaseline = baseline
        .replace(/TicketsQueued/g, "EntriesQueued")
        .replace(/uint32 quantityScaled/g, "uint32 entriesScaled")
        .replace(/uint32 quantity(?=\r?\n)/g, "uint32 entries")
        .replace(/uint32 ticketsPerLevel/g, "uint32 entriesPerLevel")
        .replace(
          "Emitted when whole tickets are queued for a buyer at a specific level.",
          "Emitted when entries are queued for a buyer at a specific level."
        )
        .replace(
          "Emitted when scaled (fractional) tickets are queued for a buyer.",
          "Emitted when scaled entries (entries × QTY_SCALE) are queued for a buyer."
        )
        .replace(
          "Emitted when tickets are queued across a contiguous range of levels.",
          "Emitted when entries are queued across a contiguous range of levels."
        )
        // Normalize the audited Phase-482 Degenerette dead-mode repack: the
        // degeneretteBets packed-layout doc block is rewritten (the dead
        // mode/isRandom/hasCustom bits stripped, the live fields repacked into
        // the freed space — encoding-only, no slot move). Any OTHER drift still
        // fails this byte-identity guard.
        .replace(
          `    /// - [0]        mode (1=full ticket)
    /// - [1]        isRandom
    /// - [2..33]    customTraits (packed 4×8-bit quadrants)
    /// - [34..41]   ticketCount (uint8, used as "spin count" for Degenerette)
    /// - [42..43]   currency (0=ETH,1=FLIP,2=unsupported,3=WWXRP)
    /// - [44..171]  amountPerSpin (uint128)
    /// - [172..219] RNG index (uint48)
    /// - [220..235] activity score bps (uint16)
    /// - [236]      hasCustom`,
          `    /// - [0..31]    customTraits (packed 4×8-bit quadrants)
    /// - [32..39]   spinCount (uint8)
    /// - [40..41]   currency (0=ETH,1=FLIP,2=unsupported,3=WWXRP)
    /// - [42..169]  amountPerSpin (uint128)
    /// - [170..201] RNG index (uint32)
    /// - [202..217] activity score bps (uint16)
    /// - [218..219] heroQuadrant (always-on hero quadrant, 0..3)`
        );
      expect(
        normBaseline,
        "Storage.sol drifted from committed HEAD beyond the audited Phase-481+482 changes"
      ).to.equal(current);
    });

    it("[03c] LootboxModule auto-resolve branch swap keeps `_queueEntriesScaled` absent from LootboxModule + present in MintModule", function () {
      const lootbox = fs.readFileSync(LOOTBOX_MODULE_PATH, "utf8");
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      expect(
        lootbox.includes("_queueEntriesScaled"),
        "_queueEntriesScaled must not appear in LootboxModule post-Phase-275 LBX-AR-02"
      ).to.equal(false);
      const mintCalls = (mint.match(/_queueEntriesScaled\(/g) || []).length;
      expect(mintCalls, "mint-boost path must retain ≥1 _queueEntriesScaled callsite").to.be.gte(1);
    });
  });
});
