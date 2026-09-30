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

    it("[02b] every MintModule drain path still reaches `_rollRemainder` (via the shared per-entry engine)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      const storage = fs.readFileSync(STORAGE_PATH, "utf8");
      // The zero-owed roll lives in the storage base's _resolveZeroOwedRemainder; the
      // end-of-take roll lives in MintModule's _processOneTicketEntry. Assert both roll sites
      // AND that both drain entrypoints route through that engine.
      expect(
        (mint.match(/_rollRemainder\(/g) || []).length,
        "expected the end-of-take `_rollRemainder(` site in MintModule"
      ).to.be.gte(1);
      const zeroOwed = storage.slice(storage.indexOf("function _resolveZeroOwedRemainder("));
      expect(
        zeroOwed.slice(0, zeroOwed.indexOf("\n    function ")).includes("_rollRemainder("),
        "_resolveZeroOwedRemainder must roll the remainder"
      ).to.equal(true);
      for (const entrypoint of ["processTicketBatch", "_processFutureTicketBatch"]) {
        const body = mint.slice(mint.indexOf(`function ${entrypoint}(`));
        expect(
          body.slice(0, body.indexOf("\n    function ")).includes("_processOneTicketEntry("),
          `${entrypoint} must drain through _processOneTicketEntry (the only remainder-roll path)`
        ).to.equal(true);
      }
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
