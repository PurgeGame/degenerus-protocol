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

  describe("Mint-boost callsite at MintModule:1142 still calls `_queuePurchaseEntries` (D-40N-MINTBOOST-OUT-01)", function () {


    it("[01b] mint-boost callsite uses the boost-derived `adjustedQty` argument (boostBps drives the scaled fractional quantity)", function () {
      const mint = fs.readFileSync(MINT_MODULE_PATH, "utf8");
      // The pre-Phase-275 callsite at L1142 is:
      //   _queuePurchaseEntries(buyerId, targetLevel, adjustedQty);
      // Match by argument shape (boost-derived fractional adjustedQty).
      const callPattern = /_queuePurchaseEntries\(buyerId,\s*targetLevel,\s*adjustedQty\)/;
      expect(
        mint.match(callPattern),
        "MintModule mint-boost callsite `_queuePurchaseEntries(buyerId, targetLevel, adjustedQty)` missing"
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

  describe("TicketEntropy remainder identity is shared by solo and seated drains", function () {


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


  });

});
