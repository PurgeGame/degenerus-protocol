import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { getEvent, ZERO_ADDRESS } from "../helpers/testUtils.js";

/*
 * Icons32Data Unit Tests
 *
 * Contract: contracts/Icons32Data.sol
 *
 * Architecture summary:
 *  - On-chain storage for 33 SVG icon paths (indices 0-32)
 *  - Symbol names for quadrants 0/1/2 (Q3=Dice is dynamic)
 *  - Mutable until finalize() is called by CREATOR
 *  - After finalization, no setter functions can be called
 *
 * Access control: only ContractAddresses.CREATOR (== deployer in tests)
 */

describe("Icons32Data", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function getFixture() {
    return loadFixture(deployFullProtocol);
  }

  // Build an array of `count` unique SVG path strings
  function makePaths(count, prefix = "M0 0 L") {
    return Array.from({ length: count }, (_, i) => `${prefix}${i} ${i}`);
  }

  // Build an array of exactly 8 symbol name strings
  function makeSymbols(prefix = "Symbol") {
    return Array.from({ length: 8 }, (_, i) => `${prefix}${i}`);
  }

  // ---------------------------------------------------------------------------
  // Initial state
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("is deployed at the predicted address", async function () {
      const { icons32, predicted } = await getFixture();
      const addr = await icons32.getAddress();
      expect(addr.toLowerCase()).to.equal(
        predicted.get("ICONS_32").toLowerCase()
      );
    });

    it("all 33 paths are empty strings by default", async function () {
      const { icons32 } = await getFixture();
      for (let i = 0; i < 33; i++) {
        expect(await icons32.data(i)).to.equal("");
      }
    });

    it("all symbol names (q0-q2) are empty strings by default", async function () {
      const { icons32 } = await getFixture();
      for (let q = 0; q < 3; q++) {
        for (let idx = 0; idx < 8; idx++) {
          expect(await icons32.symbol(q, idx)).to.equal("");
        }
      }
    });

    it("symbol() for quadrant 3 (Dice) always returns empty string", async function () {
      const { icons32 } = await getFixture();
      for (let idx = 0; idx < 8; idx++) {
        expect(await icons32.symbol(3, idx)).to.equal("");
      }
    });

    it("is NOT finalized on deploy (setPaths does not revert)", async function () {
      const { icons32 } = await getFixture();
      // If finalized, this would revert with AlreadyFinalized
      await expect(
        icons32.setPaths(0, ["M 0 0"])
      ).to.not.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // setPaths — happy path
  // ---------------------------------------------------------------------------

  describe("setPaths()", function () {
    it("sets a single path at index 0", async function () {
      const { icons32 } = await getFixture();
      const path = "M10 20 L30 40";
      await icons32.setPaths(0, [path]);
      expect(await icons32.data(0)).to.equal(path);
    });

    it("sets a full batch of 10 paths starting at index 0", async function () {
      const { icons32 } = await getFixture();
      const paths = makePaths(10);
      await icons32.setPaths(0, paths);
      for (let i = 0; i < 10; i++) {
        expect(await icons32.data(i)).to.equal(paths[i]);
      }
    });

    it("sets the last valid batch that fills up to index 32", async function () {
      const { icons32 } = await getFixture();
      // indices 30, 31, 32
      const paths = ["path30", "path31", "path32"];
      await icons32.setPaths(30, paths);
      expect(await icons32.data(30)).to.equal("path30");
      expect(await icons32.data(31)).to.equal("path31");
      expect(await icons32.data(32)).to.equal("path32");
    });

    it("sets the affiliate badge path at index 32", async function () {
      const { icons32 } = await getFixture();
      const affiliatePath = "M0 0 affiliate path data";
      await icons32.setPaths(32, [affiliatePath]);
      expect(await icons32.data(32)).to.equal(affiliatePath);
    });

    it("overwrites previously set paths", async function () {
      const { icons32 } = await getFixture();
      await icons32.setPaths(5, ["original"]);
      expect(await icons32.data(5)).to.equal("original");
      await icons32.setPaths(5, ["updated"]);
      expect(await icons32.data(5)).to.equal("updated");
    });

    it("sets paths at various non-zero start indices", async function () {
      const { icons32 } = await getFixture();
      await icons32.setPaths(8, ["q1_idx0", "q1_idx1"]);
      expect(await icons32.data(8)).to.equal("q1_idx0");
      expect(await icons32.data(9)).to.equal("q1_idx1");
    });

    it("leaves untouched slots unchanged", async function () {
      const { icons32 } = await getFixture();
      await icons32.setPaths(1, ["path1"]);
      // index 0 should still be empty
      expect(await icons32.data(0)).to.equal("");
      // index 2 should still be empty
      expect(await icons32.data(2)).to.equal("");
    });
  });

  // ---------------------------------------------------------------------------
  // setPaths — access control
  // ---------------------------------------------------------------------------

  describe("setPaths() access control", function () {
    it("reverts with OnlyCreator when called by a non-CREATOR address", async function () {
      const { icons32, alice } = await getFixture();
      await expect(
        icons32.connect(alice).setPaths(0, ["malicious"])
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });

    it("reverts with OnlyCreator for any signer that is not CREATOR", async function () {
      const { icons32, bob, carol } = await getFixture();
      for (const signer of [bob, carol]) {
        await expect(
          icons32.connect(signer).setPaths(0, ["x"])
        ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
      }
    });
  });

  // ---------------------------------------------------------------------------
  // setPaths — edge cases / bounds
  // ---------------------------------------------------------------------------

  describe("setPaths() edge cases", function () {
    it("reverts with MaxBatch when paths.length > 10", async function () {
      const { icons32 } = await getFixture();
      const paths = makePaths(11);
      await expect(
        icons32.setPaths(0, paths)
      ).to.be.revertedWithCustomError(icons32, "MaxBatch");
    });

    it("accepts exactly 10 paths (boundary — no revert)", async function () {
      const { icons32 } = await getFixture();
      const paths = makePaths(10);
      await expect(icons32.setPaths(0, paths)).to.not.be.reverted;
    });

    it("reverts with IndexOutOfBounds when startIndex + length > 33", async function () {
      const { icons32 } = await getFixture();
      // 32 + 2 = 34 > 33
      await expect(
        icons32.setPaths(32, ["a", "b"])
      ).to.be.revertedWithCustomError(icons32, "IndexOutOfBounds");
    });

    it("reverts with IndexOutOfBounds when startIndex alone is 33", async function () {
      const { icons32 } = await getFixture();
      await expect(
        icons32.setPaths(33, ["a"])
      ).to.be.revertedWithCustomError(icons32, "IndexOutOfBounds");
    });

    it("reverts with IndexOutOfBounds on overflow attempt (startIndex = max uint)", async function () {
      const { icons32 } = await getFixture();
      // startIndex = 2^256-1 + 1 path => 2^256 > 33
      await expect(
        icons32.setPaths(
          "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          ["x"]
        )
      ).to.be.reverted; // arithmetic overflow before custom error
    });

    it("accepts an empty paths array without reverting", async function () {
      const { icons32 } = await getFixture();
      // 0 paths, no-op is valid
      await expect(icons32.setPaths(0, [])).to.not.be.reverted;
    });

    it("data() reverts with out-of-bounds access for index 33", async function () {
      const { icons32 } = await getFixture();
      await expect(icons32.data(33)).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // setSymbols — happy path
  // ---------------------------------------------------------------------------

  describe("setSymbols()", function () {
    it("sets quadrant 0 (Crypto) symbols", async function () {
      const { icons32 } = await getFixture();
      const symbols = makeSymbols("Crypto");
      await icons32.setSymbols(0, symbols);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(0, i)).to.equal(symbols[i]);
      }
    });

    it("sets quadrant 1 (Zodiac) symbols", async function () {
      const { icons32 } = await getFixture();
      const symbols = makeSymbols("Zodiac");
      await icons32.setSymbols(1, symbols);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(1, i)).to.equal(symbols[i]);
      }
    });

    it("sets quadrant 2 (Cards) symbols", async function () {
      const { icons32 } = await getFixture();
      const symbols = makeSymbols("Cards");
      await icons32.setSymbols(2, symbols);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(2, i)).to.equal(symbols[i]);
      }
    });

    it("overwrites previously set symbols", async function () {
      const { icons32 } = await getFixture();
      await icons32.setSymbols(0, makeSymbols("First"));
      await icons32.setSymbols(0, makeSymbols("Second"));
      expect(await icons32.symbol(0, 0)).to.equal("Second0");
    });

    it("sets canonical symbol names matching expected layout", async function () {
      const { icons32 } = await getFixture();
      const cryptoNames = [
        "Bitcoin",
        "Ethereum",
        "Litecoin",
        "Dogecoin",
        "Solana",
        "Cardano",
        "Polkadot",
        "Avalanche",
      ];
      await icons32.setSymbols(0, cryptoNames);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(0, i)).to.equal(cryptoNames[i]);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // setSymbols — access control
  // ---------------------------------------------------------------------------

  describe("setSymbols() access control", function () {
    it("reverts with OnlyCreator when called by a non-CREATOR address", async function () {
      const { icons32, alice } = await getFixture();
      await expect(
        icons32.connect(alice).setSymbols(0, makeSymbols())
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });
  });

  // ---------------------------------------------------------------------------
  // setSymbols — edge cases
  // ---------------------------------------------------------------------------

  describe("setSymbols() edge cases", function () {
    it("reverts with InvalidQuadrant for quadrant 3", async function () {
      const { icons32 } = await getFixture();
      await expect(
        icons32.setSymbols(3, makeSymbols())
      ).to.be.revertedWithCustomError(icons32, "InvalidQuadrant");
    });

    it("reverts with InvalidQuadrant for quadrant 4", async function () {
      const { icons32 } = await getFixture();
      await expect(
        icons32.setSymbols(4, makeSymbols())
      ).to.be.revertedWithCustomError(icons32, "InvalidQuadrant");
    });

    it("reverts with InvalidQuadrant for large quadrant values", async function () {
      const { icons32 } = await getFixture();
      await expect(
        icons32.setSymbols(255, makeSymbols())
      ).to.be.revertedWithCustomError(icons32, "InvalidQuadrant");
    });

    it("symbol() returns empty string for any quadrant >= 3", async function () {
      const { icons32 } = await getFixture();
      // Quadrant 3 is always dice (dynamic rendering)
      expect(await icons32.symbol(3, 0)).to.equal("");
      expect(await icons32.symbol(3, 7)).to.equal("");
    });

    it("symbol() returns empty for quadrant 4+ (fallthrough)", async function () {
      const { icons32 } = await getFixture();
      // quadrant 4 hits the last fallthrough return ""
      expect(await icons32.symbol(4, 0)).to.equal("");
      expect(await icons32.symbol(100, 0)).to.equal("");
    });
  });

  // ---------------------------------------------------------------------------
  // finalize() — happy path
  // ---------------------------------------------------------------------------

  describe("finalize()", function () {
    it("allows CREATOR to call finalize without reverting", async function () {
      const { icons32 } = await getFixture();
      await expect(icons32.finalize()).to.not.be.reverted;
    });

    it("blocks setPaths after finalization with AlreadyFinalized", async function () {
      const { icons32 } = await getFixture();
      await icons32.finalize();
      await expect(
        icons32.setPaths(0, ["blocked"])
      ).to.be.revertedWithCustomError(icons32, "AlreadyFinalized");
    });

    it("blocks setSymbols after finalization with AlreadyFinalized", async function () {
      const { icons32 } = await getFixture();
      await icons32.finalize();
      await expect(
        icons32.setSymbols(0, makeSymbols())
      ).to.be.revertedWithCustomError(icons32, "AlreadyFinalized");
    });

    it("preserves previously set data after finalization", async function () {
      const { icons32 } = await getFixture();
      await icons32.setPaths(0, ["preserved_path"]);
      await icons32.setSymbols(0, makeSymbols("Kept"));
      await icons32.finalize();

      expect(await icons32.data(0)).to.equal("preserved_path");
      expect(await icons32.symbol(0, 0)).to.equal("Kept0");
    });

    it("reverts with AlreadyFinalized if called a second time", async function () {
      const { icons32 } = await getFixture();
      await icons32.finalize();
      await expect(icons32.finalize()).to.be.revertedWithCustomError(
        icons32,
        "AlreadyFinalized"
      );
    });
  });

  // ---------------------------------------------------------------------------
  // finalize() — access control
  // ---------------------------------------------------------------------------

  describe("finalize() access control", function () {
    it("reverts with OnlyCreator when called by non-CREATOR", async function () {
      const { icons32, alice } = await getFixture();
      await expect(
        icons32.connect(alice).finalize()
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });

    it("does not finalize the contract when a non-CREATOR attempts it", async function () {
      const { icons32, alice } = await getFixture();
      // Attempt by alice (should fail)
      await expect(icons32.connect(alice).finalize()).to.be.reverted;
      // CREATOR can still set paths (contract not finalized)
      await expect(icons32.setPaths(0, ["still_ok"])).to.not.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // data() view function
  // ---------------------------------------------------------------------------

  describe("data()", function () {
    it("returns the correct path for each index after a full populate", async function () {
      const { icons32 } = await getFixture();
      // Populate all 33 paths in batches of 10
      const allPaths = Array.from({ length: 33 }, (_, i) => `path_${i}`);
      await icons32.setPaths(0, allPaths.slice(0, 10));
      await icons32.setPaths(10, allPaths.slice(10, 20));
      await icons32.setPaths(20, allPaths.slice(20, 30));
      await icons32.setPaths(30, allPaths.slice(30, 33));

      for (let i = 0; i < 33; i++) {
        expect(await icons32.data(i)).to.equal(allPaths[i]);
      }
    });

    it("returns empty string for unset indices", async function () {
      const { icons32 } = await getFixture();
      expect(await icons32.data(0)).to.equal("");
      expect(await icons32.data(16)).to.equal("");
      expect(await icons32.data(32)).to.equal("");
    });
  });

  // ---------------------------------------------------------------------------
  // symbol() view function — quadrant mapping
  // ---------------------------------------------------------------------------

  describe("symbol() quadrant mapping", function () {
    it("quadrant param 0 reads from _symQ1 (Crypto names)", async function () {
      const { icons32 } = await getFixture();
      const cryptoNames = [
        "Bitcoin",
        "Ethereum",
        "Litecoin",
        "Dogecoin",
        "Solana",
        "Cardano",
        "Polkadot",
        "Avalanche",
      ];
      await icons32.setSymbols(0, cryptoNames);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(0, i)).to.equal(cryptoNames[i]);
      }
    });

    it("quadrant param 1 reads from _symQ2 (Zodiac names)", async function () {
      const { icons32 } = await getFixture();
      const zodiacNames = [
        "Aries",
        "Taurus",
        "Gemini",
        "Cancer",
        "Leo",
        "Virgo",
        "Libra",
        "Scorpio",
      ];
      await icons32.setSymbols(1, zodiacNames);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(1, i)).to.equal(zodiacNames[i]);
      }
    });

    it("quadrant param 2 reads from _symQ3 (Cards names)", async function () {
      const { icons32 } = await getFixture();
      const cardNames = [
        "Horseshoe",
        "King",
        "Cashsack",
        "Club",
        "Diamond",
        "Heart",
        "Spade",
        "Ace",
      ];
      await icons32.setSymbols(2, cardNames);
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(2, i)).to.equal(cardNames[i]);
      }
    });

    it("quadrant 3+ always returns empty string regardless of idx", async function () {
      const { icons32 } = await getFixture();
      // Even after setting q0/q1/q2, quadrant 3 in symbol() stays empty
      await icons32.setSymbols(0, makeSymbols("A"));
      await icons32.setSymbols(1, makeSymbols("B"));
      await icons32.setSymbols(2, makeSymbols("C"));

      for (let idx = 0; idx < 8; idx++) {
        expect(await icons32.symbol(3, idx)).to.equal("");
      }
    });
  });

  // ---------------------------------------------------------------------------
  // Full lifecycle integration
  // ---------------------------------------------------------------------------

  describe("full lifecycle", function () {
    it("populates all data then finalizes — all reads correct after finalization", async function () {
      const { icons32 } = await getFixture();

      const allPaths = Array.from({ length: 33 }, (_, i) => `final_path_${i}`);
      await icons32.setPaths(0, allPaths.slice(0, 10));
      await icons32.setPaths(10, allPaths.slice(10, 20));
      await icons32.setPaths(20, allPaths.slice(20, 30));
      await icons32.setPaths(30, allPaths.slice(30, 33));

      const cryptoNames = [
        "Bitcoin",
        "Ethereum",
        "Litecoin",
        "Dogecoin",
        "Solana",
        "Cardano",
        "Polkadot",
        "Avalanche",
      ];
      const zodiacNames = [
        "Aries",
        "Taurus",
        "Gemini",
        "Cancer",
        "Leo",
        "Virgo",
        "Libra",
        "Scorpio",
      ];
      const cardNames = [
        "Horseshoe",
        "King",
        "Cashsack",
        "Club",
        "Diamond",
        "Heart",
        "Spade",
        "Ace",
      ];

      await icons32.setSymbols(0, cryptoNames);
      await icons32.setSymbols(1, zodiacNames);
      await icons32.setSymbols(2, cardNames);

      await icons32.finalize();

      // Verify paths
      for (let i = 0; i < 33; i++) {
        expect(await icons32.data(i)).to.equal(allPaths[i]);
      }

      // Verify symbols
      for (let i = 0; i < 8; i++) {
        expect(await icons32.symbol(0, i)).to.equal(cryptoNames[i]);
        expect(await icons32.symbol(1, i)).to.equal(zodiacNames[i]);
        expect(await icons32.symbol(2, i)).to.equal(cardNames[i]);
      }

      // Verify finalization blocks further writes
      await expect(icons32.setPaths(0, ["blocked"])).to.be.revertedWithCustomError(
        icons32,
        "AlreadyFinalized"
      );
    });

    it("non-CREATOR cannot disrupt lifecycle at any stage", async function () {
      const { icons32, alice, bob } = await getFixture();

      // Alice tries to set paths
      await expect(
        icons32.connect(alice).setPaths(0, ["hack"])
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");

      // CREATOR sets a path normally
      await icons32.setPaths(0, ["legit"]);
      expect(await icons32.data(0)).to.equal("legit");

      // Bob tries to finalize early
      await expect(
        icons32.connect(bob).finalize()
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");

      // CREATOR can still write after failed finalize attempts
      await icons32.setPaths(1, ["also_legit"]);
      expect(await icons32.data(1)).to.equal("also_legit");

      // CREATOR finalizes
      await icons32.finalize();

      // Nobody can write anymore
      await expect(
        icons32.setPaths(0, ["post-final"])
      ).to.be.revertedWithCustomError(icons32, "AlreadyFinalized");
      await expect(
        icons32.connect(alice).setPaths(0, ["post-final"])
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });
  });
});
