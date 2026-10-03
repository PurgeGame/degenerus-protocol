// SPDX-License-Identifier: AGPL-3.0-only
// Structural guards for the current mint-boost queue and remainder paths.
// Runtime behavior is covered by the mint/lootbox Foundry suites. Historical
// comparisons with HEAD are retired: they cannot detect a committed regression.

import { expect } from "chai";
import fs from "node:fs";
import path from "node:path";

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

  describe("`_rollRemainder` defined in the shared storage base + consumed by MintModule (mint-boost activation still resolves rem byte)", function () {
    it("[02a] `_rollRemainder` is defined in DegenerusGameStorage.sol (the shared owed-balance engine both drains use)", function () {
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      expect(
        storage.includes("function _rollRemainder("),
        "_rollRemainder must be defined in the storage base"
      ).to.equal(true);
    });

    it("[02b] solo and seated ticket drains resolve the same frozen remainder identity", function () {
      const ticket = fs.readFileSync("contracts/modules/DegenerusGameTicketModule.sol", "utf8");
      const entropy = fs.readFileSync("contracts/libraries/TicketEntropy.sol", "utf8");
      // The checkpoint engine replaced both MintModule drain wrappers. Retain
      // coverage of final solo tails, zero-owed seats and exhausted seated entries.
      function body(name) {
        const start = ticket.indexOf(`function ${name}(`);
        expect(start, `${name} must exist`).to.be.gte(0);
        const next = ticket.indexOf("\n    function ", start + 1);
        return ticket.slice(start, next < 0 ? ticket.length : next);
      }
      for (const name of ["_solo", "_seatEntry", "_runRound"]) {
        expect(body(name)).to.include("TicketEntropy.remainder(");
        expect(body(name)).to.include("TicketEntropy.identity(");
      }
      expect(body("_solo")).to.include("finalTail && rem != 0 && TicketEntropy.remainder(stream, entropy, rem)");
      expect(body("_runTicketWork")).to.include("_drainQueue(");
      expect(body("_drainQueue")).to.include("_solo(");
      expect(body("_drainQueue")).to.include("_roundPhase(");
      expect(entropy).to.include("DEGENERUS_TICKET_REMAINDER_V2");
      expect(entropy).to.include("abi.encode(REMAINDER_DOMAIN, stream, entropy)");
      expect(entropy).to.include("% 100 < fraction");
    });

    it("[02c] cross-module negation: `_rollRemainder` is NOT defined in MintModule or DegenerusGameLootboxModule.sol — it's the storage base's", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      const lootbox = fs.readFileSync(LOOTBOX_MODULE_PATH, "utf8");
      expect(mint.includes("function _rollRemainder(")).to.equal(false);
      expect(lootbox.includes("function _rollRemainder(")).to.equal(false);

      // LootboxModule must not even reference _rollRemainder (no auto-resolve
      // dependency on the helper post-Phase-275).
      expect(lootbox.includes("_rollRemainder(")).to.equal(false);
    });
  });

  describe("Scaled queue ownership across mint and lootbox modules", function () {
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
