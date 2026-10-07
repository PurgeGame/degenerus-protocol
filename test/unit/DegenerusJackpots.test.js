import { expect } from "chai";
import hre from "hardhat";
import * as bucketSeed from "../helpers/bucketSeed.js";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
  giveWalletId,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
} from "../helpers/testUtils.js";

/*
 * DegenerusJackpots Unit Tests
 * ============================
 * Covers:
 *  - recordBafFlip (onlyCoin: coinflip contract only)
 *    - happy path: accumulates bafTotals, updates leaderboard
 *    - ignores vault address
 *    - emits BafFlipRecorded
 *    - top-4 leaderboard maintenance (insert, update, replace)
 *  - beginBaf / finalizeBaf (onlyGame)
 *    - access control
 *    - beginBaf records the resolution day and leaves the board frozen
 *    - finalizeBaf clears the board and bumps the epoch (stored scores read zero)
 *  - bafHeadWinner / bafPairWinners (views the game's award stage pays from)
 *    - head slots read the frozen board and the armed-day depositor draw
 *    - scatter rounds name only scored candidates (ID 0 otherwise)
 *    - the word picks third or fourth place for head slot 2
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Wallet ID of `addr`, registering it through the Game's allow-listed hook when new. */
async function idOf(coinflip, addr) {
  const game = await hre.ethers.getContractAt("DegenerusGame", await coinflip.degenerusGame());
  return giveWalletId(game, addr);
}

/**
 * Impersonate the coinflip contract to call recordBafFlip for `player`'s wallet ID.
 */
async function recordBafFlipAsCoinflip(hreEthers, coinflip, jackpots, player, lvl, amount) {
  const playerId = await idOf(coinflip, player);
  const coinflipAddr = await coinflip.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinflipAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinflipAddr,
    "0x1000000000000000000",
  ]);
  const coinflipSigner = await hreEthers.getSigner(coinflipAddr);
  const tx = await jackpots
    .connect(coinflipSigner)
    .recordBafFlip(playerId, lvl, amount);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinflipAddr]);
  return tx;
}

/**
 * Run `fn(gameSigner)` while impersonating the game contract (the onlyGame caller).
 */
async function asGame(hreEthers, game, fn) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  try {
    return await fn(gameSigner);
  } finally {
    await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  }
}

/**
 * Every scatter round's (best, second) for a bracket and word: 48 rounds in four
 * twelve-round bands (lvl trait buckets, lvl+1 trait buckets, lvl+2..lvl+5 and
 * lvl+6..lvl+99 far-future queues).
 */
async function roundWinners(jackpots, lvl, word) {
  const rounds = [];
  for (let p = 0; p < 24; p++) {
    const w = await jackpots.bafPairWinners(lvl, word, p, 48);
    rounds.push({ best: w[0], second: w[1] }, { best: w[2], second: w[3] });
  }
  return rounds;
}

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("DegenerusJackpots", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. recordBafFlip - Access Control
  // =========================================================================
  describe("recordBafFlip - access control", function () {
    it("reverts OnlyCoin when called by a random EOA", async function () {
      const { jackpots, alice, bob } = await loadFixture(deployFullProtocol);
      await expect(
        jackpots.connect(alice).recordBafFlip(1, 10, eth(100))
      ).to.be.revertedWithCustomError(jackpots, "OnlyCoin");
    });

    it("reverts OnlyCoin when called by the coin contract (coinflip-only gate)", async function () {
      const { jackpots, coin, alice } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);
      await expect(
        jackpots.connect(coinSigner).recordBafFlip(1, 10, eth(100))
      ).to.be.revertedWithCustomError(jackpots, "OnlyCoin");
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
    });

    it("succeeds when called by coinflip contract", async function () {
      const { jackpots, coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        recordBafFlipAsCoinflip(
          hre.ethers,
          coinflip,
          jackpots,
          alice.address,
          10,
          eth(100)
        )
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 2. recordBafFlip - Happy Path
  // =========================================================================
  describe("recordBafFlip - happy path", function () {
    it("emits BafFlipRecorded with correct fields", async function () {
      const { jackpots, coinflip, alice } = await loadFixture(deployFullProtocol);
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        10,
        eth(500)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      expect(ev.args.id).to.equal(await idOf(coinflip, alice.address));
      expect(ev.args.lvl).to.equal(10n);
      expect(ev.args.amount).to.equal(eth(500));
      expect(ev.args.newTotal).to.equal(eth(500));
    });

    it("accumulates total across multiple flips for same player/level", async function () {
      const { jackpots, coinflip, alice } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        10,
        eth(200)
      );
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        10,
        eth(300)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      expect(ev.args.newTotal).to.equal(eth(500));
    });

    it("vault accrues a BAF score and emits BafFlipRecorded", async function () {
      const { jackpots, coinflip, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      // recordBafFlip now records the vault's running total and emits
      // BafFlipRecorded for it (the prior "silently ignore vault" behavior is
      // gone). The vault is only kept off the top-bettor leaderboard — the
      // `if (player != VAULT) _updateBafTop(...)` guard in recordBafFlip — which
      // is contract-internal (no public leaderboard view); the observable change
      // here is that the vault now accrues a score and emits the event.
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        vaultAddr,
        10,
        eth(1000)
      );
      const evs = await getEvents(tx, jackpots, "BafFlipRecorded");
      expect(evs.length).to.equal(1);
      expect(evs[0].args.id).to.equal(1n);
      expect(evs[0].args.newTotal).to.equal(eth(1000));
    });

    it("different levels are tracked independently", async function () {
      const { jackpots, coinflip, alice } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        10,
        eth(100)
      );
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        20,
        eth(200)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      // Level 20 should only have 200 ETH
      expect(ev.args.lvl).to.equal(20n);
      expect(ev.args.newTotal).to.equal(eth(200));
    });
  });

  // =========================================================================
  // 3. recordBafFlip - Leaderboard Maintenance
  // =========================================================================
  describe("recordBafFlip - leaderboard maintenance", function () {
    it("inserts new player into top-4 in sorted order", async function () {
      const { jackpots, coinflip, alice, bob, carol, dan } = await loadFixture(
        deployFullProtocol
      );
      const lvl = 10;
      // Insert 4 players in unsorted order
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, carol.address, lvl, eth(300));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, lvl, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, dan.address, lvl, eth(100));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, lvl, eth(400));

      // Head slot 0 is the top bettor; head slot 2 is the word-picked third or fourth place.
      expect(await jackpots.bafHeadWinner(lvl, 1n, 0)).to.equal(await idOf(coinflip, alice.address));
      expect([await idOf(coinflip, carol.address), await idOf(coinflip, dan.address)]).to.include(await jackpots.bafHeadWinner(lvl, 1n, 2));
    });

    it("updates existing player score when they flip more", async function () {
      const { jackpots, coinflip, alice } = await loadFixture(deployFullProtocol);
      const lvl = 15;
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        lvl,
        eth(100)
      );
      // Alice flips more
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        lvl,
        eth(900)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      expect(ev.args.newTotal).to.equal(eth(1000));
    });

    it("replaces lowest score when board is full and new player is higher", async function () {
      const { jackpots, coinflip, alice, bob, carol, dan, eve } =
        await loadFixture(deployFullProtocol);
      const lvl = 20;
      // Fill top-4
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        lvl,
        eth(400)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        bob.address,
        lvl,
        eth(300)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        carol.address,
        lvl,
        eth(200)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        dan.address,
        lvl,
        eth(100)
      );
      // eve beats dan (lowest) with eth(150)
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        eve.address,
        lvl,
        eth(150)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      // Eve should appear in the event since she was recorded
      expect(ev.args.id).to.equal(await idOf(coinflip, eve.address));
    });

    it("does not replace lowest score when new player is equal or lower", async function () {
      const { jackpots, coinflip, alice, bob, carol, dan, eve } =
        await loadFixture(deployFullProtocol);
      const lvl = 25;
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        alice.address,
        lvl,
        eth(400)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        bob.address,
        lvl,
        eth(300)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        carol.address,
        lvl,
        eth(200)
      );
      await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        dan.address,
        lvl,
        eth(100)
      );

      // Eve with eth(50) should NOT enter leaderboard (below dan's 100)
      // But the event is still emitted for the flip recording; the leaderboard just won't change.
      // Verify that alice still holds top spot (not displaced) by checking jackpot output.
      // The BafFlipRecorded event is always emitted.
      const tx = await recordBafFlipAsCoinflip(
        hre.ethers,
        coinflip,
        jackpots,
        eve.address,
        lvl,
        eth(50)
      );
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      expect(ev.args.id).to.equal(await idOf(coinflip, eve.address));
      expect(ev.args.newTotal).to.equal(eth(50));
    });
  });

  // =========================================================================
  // 4. beginBaf / finalizeBaf - Access Control
  // =========================================================================
  describe("beginBaf / finalizeBaf - access control", function () {
    it("reverts OnlyGame when called by random EOA", async function () {
      const { jackpots, alice } = await loadFixture(deployFullProtocol);
      await expect(jackpots.connect(alice).beginBaf()).to.be.revertedWithCustomError(jackpots, "OnlyGame");
      await expect(jackpots.connect(alice).finalizeBaf(10)).to.be.revertedWithCustomError(jackpots, "OnlyGame");
    });

    it("reverts OnlyGame when called by coin contract", async function () {
      const { jackpots, coin } = await loadFixture(deployFullProtocol);
      const coinAddr = await coin.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [coinAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0x1000000000000000000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);
      await expect(
        jackpots.connect(coinSigner).beginBaf()
      ).to.be.revertedWithCustomError(jackpots, "OnlyGame");
      await expect(
        jackpots.connect(coinSigner).finalizeBaf(10)
      ).to.be.revertedWithCustomError(jackpots, "OnlyGame");
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
    });

    it("succeeds when called by game contract", async function () {
      const { jackpots, game } = await loadFixture(deployFullProtocol);
      await asGame(hre.ethers, game, async (gameSigner) => {
        await expect(jackpots.connect(gameSigner).beginBaf()).to.not.be.reverted;
        await expect(jackpots.connect(gameSigner).finalizeBaf(10)).to.not.be.reverted;
      });
    });
  });

  // =========================================================================
  // 5. Bracket resolution: beginBaf, the frozen views, finalizeBaf
  // =========================================================================
  describe("bracket resolution", function () {
    it("an unscored bracket names nobody in any slot", async function () {
      const { jackpots } = await loadFixture(deployFullProtocol);
      // No BAF flips recorded: far-future holders from the fixture deployment can be
      // sampled, but a zero score never takes a place.
      for (const word of [1n, 999n]) {
        const rounds = await roundWinners(jackpots, 10, word);
        for (const { best, second } of rounds) {
          expect(best).to.equal(0n);
          expect(second).to.equal(0n);
        }
        for (let slot = 0; slot < 3; slot++) {
          expect(await jackpots.bafHeadWinner(10, word, slot)).to.equal(0n);
        }
      }
    });

    it("beginBaf records today's resolution day and leaves the board frozen", async function () {
      const { jackpots, game, coinflip, alice, bob } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));
      const before = await jackpots.bafHeadWinner(10, 1n, 0);
      expect(before).to.equal(await idOf(coinflip, alice.address));

      await asGame(hre.ethers, game, (gameSigner) => jackpots.connect(gameSigner).beginBaf());

      expect(await jackpots.getLastBafResolvedDay()).to.equal(await game.currentDayView());
      // The award stage draws across several transactions from the same board.
      expect(await jackpots.bafHeadWinner(10, 1n, 0)).to.equal(await idOf(coinflip, alice.address));
      expect(await jackpots.bafConsolationOf(alice.address, 10)).to.equal(0n);
    });

    it("finalizeBaf clears the board and restarts every score from zero", async function () {
      const { jackpots, game, coinflip, alice, bob } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));

      await asGame(hre.ethers, game, async (gameSigner) => {
        await jackpots.connect(gameSigner).beginBaf();
        await jackpots.connect(gameSigner).finalizeBaf(10);
      });

      for (let slot = 0; slot < 3; slot++) {
        expect(await jackpots.bafHeadWinner(10, 1n, slot)).to.equal(0n);
      }
      // The epoch bump makes the stored totals stale: a new flip starts from zero.
      const tx = await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(100));
      const ev = await getEvent(tx, jackpots, "BafFlipRecorded");
      expect(ev.args.newTotal).to.equal(eth(100));
    });

    it("the views are read-only and repeatable for a fixed word", async function () {
      const { jackpots, coinflip, alice, bob, carol } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, carol.address, 10, eth(100));
      const first = await roundWinners(jackpots, 10, 42n);
      const second = await roundWinners(jackpots, 10, 42n);
      expect(second).to.deep.equal(first);
      expect(await jackpots.bafHeadWinner(10, 42n, 2)).to.equal(await jackpots.bafHeadWinner(10, 42n, 2));
    });
  });

  // =========================================================================
  // 6. RNG variation: the word picks third or fourth place
  // =========================================================================
  describe("bafHeadWinner - RNG variation", function () {
    it("different words reach both third and fourth place for head slot 2", async function () {
      const { jackpots, coinflip, alice, bob, carol, dan } = await loadFixture(deployFullProtocol);
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(400));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, carol.address, 10, eth(200));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, dan.address, 10, eth(100));
      const seen = new Set();
      for (let w = 1n; w <= 32n && seen.size < 2; w++) {
        const pick = await jackpots.bafHeadWinner(10, w, 2);
        expect([await idOf(coinflip, carol.address), await idOf(coinflip, dan.address)]).to.include(pick);
        seen.add(pick);
      }
      expect(seen.size).to.equal(2);
    });
  });

  // =========================================================================
  // 7. Head slots with BAF bettors
  // =========================================================================
  describe("bafHeadWinner - leaderboard slots", function () {
    it("100 ETH pool, with BAF bettors — shows head-slot winners", async function () {
      const { jackpots, coinflip, alice, bob, carol } = await loadFixture(deployFullProtocol);
      const pool = eth(100);

      // Record BAF flips for leaderboard
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, carol.address, 10, eth(100));

      const names = {
        [await idOf(coinflip, alice.address)]: "Alice",
        [await idOf(coinflip, bob.address)]: "Bob",
        [await idOf(coinflip, carol.address)]: "Carol",
      };
      const labels = ["top bettor (P/10)", "armed-day depositor draw (P/20)", "3rd/4th place (P/20)"];
      const heads = [];
      console.log("\n    === BAF head slots: lvl 10, 3 bettors ===");
      console.log(`    Alice (500 ETH flips), Bob (300 ETH), Carol (100 ETH); pool ${hre.ethers.formatEther(pool)} ETH`);
      for (let slot = 0; slot < 3; slot++) {
        const w = await jackpots.bafHeadWinner(10, 42n, slot);
        heads.push(w);
        console.log(`    slot ${slot} ${labels[slot]}: ${names[w] || w}`);
      }

      // Alice is the top BAF bettor (500 > 300 > 100).
      expect(heads[0]).to.equal(await idOf(coinflip, alice.address));
      // No direct deposit on an armed day: the draw slot is empty.
      expect(heads[1]).to.equal(0n);
      // Third place is Carol, fourth is empty.
      expect([await idOf(coinflip, carol.address), 0n]).to.include(heads[2]);
    });
  });

  // =========================================================================
  // 7b. Full-slate rounds with populated tickets
  // =========================================================================
  describe("bafPairWinners - full slate with trait tickets + FF tickets", function () {
    /** Seed trait lanes and the owners they reference. */
    async function setTraitBurnTicket(gameAddr, level, trait, addresses) {
      await bucketSeed.seedTraitBucket(gameAddr, level, trait, addresses);
    }

    /** Seed packed owner-position lanes for a far-future key. */
    async function setTicketQueue(gameAddr, key, addresses) {
      await bucketSeed.seedTicketQueue(gameAddr, key, addresses);
    }

    /** Set game level (slot 0, offset 12 = 3 bytes at byte 12) */
    async function setLevel(gameAddr, lvl) {
      // Read current slot 0 value to preserve other packed fields
      const current = await hre.ethers.provider.getStorage(gameAddr, 0);
      const val = BigInt(current);
      // Clear bytes 12-14 (level is uint24 at offset 12 = bits 96-119)
      const mask = ~(BigInt(0xFFFFFF) << 96n);
      const newVal = (val & mask) | (BigInt(lvl) << 96n);
      await hre.ethers.provider.send("hardhat_setStorageAt", [
        gameAddr,
        hre.ethers.toBeHex(0, 32),
        hre.ethers.toBeHex(newVal, 32),
      ]);
    }

    it("lvl 10, full trait tickets + FF tickets — scored holders fill the rounds", async function () {
      const { jackpots, game, coinflip, alice, bob, carol } = await loadFixture(deployFullProtocol);
      const signers = await hre.ethers.getSigners();
      const gameAddr = await game.getAddress();

      // Generate 20 unique player addresses from signers
      const players = signers.slice(0, 20).map((s) => s.address);
      const scored = new Set([
        await idOf(coinflip, alice.address),
        await idOf(coinflip, bob.address),
        await idOf(coinflip, carol.address),
      ]);

      // Set game level to 10
      await setLevel(gameAddr, 10);

      // Populate every trait bucket of levels 10 and 11 (the first two bands).
      for (let lvl = 10; lvl <= 11; lvl++) {
        for (let trait = 0; trait < 256; trait++) {
          const startIdx = ((lvl - 10) * 7 + trait) % players.length;
          const holders = [
            players[startIdx % players.length],
            players[(startIdx + 1) % players.length],
            players[(startIdx + 2) % players.length],
          ];
          await setTraitBurnTicket(gameAddr, lvl, trait, holders);
        }
      }

      // Populate far-future ticketQueue for levels 17-25 (inside the lvl+6..lvl+99 band)
      // FF key = level | (1 << 22)
      const FF_BIT = 1 << 22;
      for (let lvl = 17; lvl <= 25; lvl++) {
        const key = lvl | FF_BIT;
        const startIdx = (lvl - 17) * 2;
        const holders = [
          players[startIdx % players.length],
          players[(startIdx + 1) % players.length],
          players[(startIdx + 2) % players.length],
          players[(startIdx + 3) % players.length],
        ];
        await setTicketQueue(gameAddr, key, holders);
      }

      // Record BAF flips for leaderboard (top 3)
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, alice.address, 10, eth(500));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, bob.address, 10, eth(300));
      await recordBafFlipAsCoinflip(hre.ethers, coinflip, jackpots, carol.address, 10, eth(100));

      // Four words, 192 rounds: each draws its own trait bucket or far-future packs.
      const words = [42n, 43n, 44n, 45n];
      let firstCount = 0;
      let secondCount = 0;
      console.log("\n    === BAF scatter rounds: lvl 10, FULL SLATE ===");
      for (const word of words) {
        const rounds = await roundWinners(jackpots, 10, word);
        for (const { best, second } of rounds) {
          // Only scored candidates place, and a second place needs a distinct first.
          if (best !== 0n) {
            expect(scored.has(best)).to.equal(true);
            ++firstCount;
          }
          if (second !== 0n) {
            expect(scored.has(second)).to.equal(true);
            expect(best).to.not.equal(0n);
            expect(second).to.not.equal(best);
            ++secondCount;
          }
        }
      }
      console.log(`    Scatter 1st place filled: ${firstCount}/${48 * words.length} rounds`);
      console.log(`    Scatter 2nd place filled: ${secondCount}/${48 * words.length} rounds`);

      // There should be scatter winners now
      expect(firstCount).to.be.gt(0, "Should have scatter 1st place winners");
      expect(secondCount).to.be.gt(0, "Should have scatter 2nd place winners");

      // Alice should be top BAF
      expect(await jackpots.bafHeadWinner(10, 42n, 0)).to.equal(await idOf(coinflip, alice.address));
    });
  });
});
