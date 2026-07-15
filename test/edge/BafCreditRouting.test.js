import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/**
 * BafCreditRouting — verifies the BAF credit-routing changes in Coinflip.sol:
 *   - :525  cursor >= bafResolvedDay  (was strict >, orphaned the resolution day)
 *   - :585  RngLocked guard now keys off storage `level` (was `purchaseLevel_ = level + 1`,
 *           which never matched at x10 boundaries because level is pre-bumped in
 *           _finalizeRngRequest atomically with rngLockedFlag = true)
 *   - :594  jackpot-phase post-BAF override routes credit to cachedLevel + 1 on x10 eras
 *           (otherwise day-D wins claimed during the jackpot phase land in the bracket
 *           that just resolved)
 *   - :1041 same predicate fix for _coinflipLockedDuringTransition (deposit-side lock)
 *
 * STRATEGY:
 *   The lock predicate is the security-critical change — it's what stops players from
 *   writing into bafTotals[N] between _requestRng and runBafJackpot. We verify it
 *   directly: drive the game one day cycle organically so alice has a winning claimable
 *   flip + claimableStored, then overwrite the `level` byte in slot 0 of the game's
 *   packed state and assert the lock fires (level=10) or doesn't (level=5).
 *
 *   We do NOT drive organically to level 10 because that costs hundreds of advanceGame
 *   iterations per test; the Foundry fuzz BafRebuyReconciliation.t.sol uses the same
 *   pattern (`vm.store`) for the same reason.
 *
 *   The cursor>=bafResolvedDay filter and the bafLevel override at jackpot phase are
 *   covered by separate `describe` blocks that seed lastBafResolvedDay directly.
 *
 * STORAGE LAYOUT REMINDERS (per DegenerusGameStorage.sol header):
 *   Slot 0 packing (bytes, LSB-first; authoritative forge inspect storageLayout):
 *     [0:3]   purchaseStartDay   uint24
 *     [3:6]   dailyIdx           uint24
 *     [6:12]  rngRequestTime     uint48
 *     [12:15] level              uint24   <-- we overwrite this
 *     [15]    jackpotPhaseFlag   bool
 *     [16]    jackpotCounter     uint8
 *     [17]    lastPurchaseDay    bool
 *     [18]    decWindowOpen      bool
 *     [19]    rngLockedFlag      bool
 *     ...
 *
 *   DegenerusJackpots layout (authoritative forge inspect storageLayout):
 *     slot 0: bafPlayer mapping
 *     slot 1: bafTop mapping
 *     slot 2: bafLevel mapping
 *     slot 3: lastBafResolvedDay (uint24, offset 0)
 */
describe("BafCreditRouting", function () {
  this.timeout(180_000);

  after(function () {
    restoreAddresses();
  });

  const SLOT0 = "0x" + "0".repeat(64);
  const LAST_BAF_RESOLVED_DAY_SLOT =
    "0x" + (3).toString(16).padStart(64, "0");

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /** Read packed slot 0 of the game and return it as a BigInt. */
  async function readSlot0(gameAddr) {
    const raw = await hre.ethers.provider.getStorage(gameAddr, SLOT0);
    return BigInt(raw);
  }

  /** Pack the level uint24 into bytes [12:15] of slot 0 and write it back. */
  async function setLevel(gameAddr, newLevel) {
    const current = await readSlot0(gameAddr);
    const LEVEL_MASK = ((1n << 24n) - 1n) << 96n;
    const cleared = current & ~LEVEL_MASK;
    const updated = cleared | ((BigInt(newLevel) & ((1n << 24n) - 1n)) << 96n);
    await hre.network.provider.send("hardhat_setStorageAt", [
      gameAddr,
      SLOT0,
      "0x" + updated.toString(16).padStart(64, "0"),
    ]);
  }

  /** Toggle a single-byte boolean in slot 0 at the given byte offset. */
  async function setSlot0Bool(gameAddr, byteOffset, value) {
    const current = await readSlot0(gameAddr);
    const BIT_OFFSET = BigInt(byteOffset * 8);
    const BYTE_MASK = 0xffn << BIT_OFFSET;
    const cleared = current & ~BYTE_MASK;
    const updated = cleared | (value ? 1n << BIT_OFFSET : 0n);
    await hre.network.provider.send("hardhat_setStorageAt", [
      gameAddr,
      SLOT0,
      "0x" + updated.toString(16).padStart(64, "0"),
    ]);
  }

  /** Set lastBafResolvedDay (uint32 at slot 5 of DegenerusJackpots). */
  async function setLastBafResolvedDay(jackpotsAddr, day) {
    const value = "0x" + BigInt(day).toString(16).padStart(64, "0");
    await hre.network.provider.send("hardhat_setStorageAt", [
      jackpotsAddr,
      LAST_BAF_RESOLVED_DAY_SLOT,
      value,
    ]);
  }

  async function mintFlipToAlice(coin, vault, alice, amount = eth(10000)) {
    const vaultAddr = await vault.getAddress();
    await hre.ethers.provider.send("hardhat_setBalance", [
      vaultAddr,
      "0x1000000000000000000",
    ]);
    await hre.ethers.provider.send("hardhat_impersonateAccount", [vaultAddr]);
    const vaultSigner = await hre.ethers.getSigner(vaultAddr);
    await coin.connect(vaultSigner).vaultEscrow(amount);
    await coin.connect(vaultSigner).vaultMintTo(alice.address, amount);
    await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [
      vaultAddr,
    ]);
  }

  /** Drive one full daily VRF cycle with a winning daily-flip word (bit 0 = 1). */
  async function driveDailyCycleWinningFlip(game, deployer, mockVRF, word) {
    if ((word & 1n) === 0n) {
      throw new Error("word must be odd for a winning daily flip");
    }
    await advanceToNextDay();
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, word);
    } catch {
      /* may already be fulfilled */
    }
    for (let i = 0; i < 30; i++) {
      if (!(await game.rngLocked())) break;
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        break;
      }
    }
  }

  /**
   * Set up alice with a winning claimable flip:
   *   - mint FLIP to alice
   *   - alice deposits coinflip stake during day N
   *   - advanceGame + fulfill VRF with odd word → day N+1 resolves as a win
   *   - drive cycle to completion (RNG unlocked)
   * Returns the day index of the winning flip.
   */
  async function setupAliceWinningFlip(fixture) {
    const { game, coin, coinflip, deployer, mockVRF, alice, vault } = fixture;

    await mintFlipToAlice(coin, vault, alice);

    // alice places a coinflip stake (deposit). This routes the FLIP into the
    // coinflipBalance[nextDay][alice] mapping.
    await coinflip
      .connect(alice)
      .depositCoinflip(alice.address, eth(100));

    // Drive day cycle with winning flip word (bit 0 = 1).
    await driveDailyCycleWinningFlip(game, deployer, mockVRF, 0xdeadbeefn);

    expect(await game.rngLocked()).to.equal(false);

    // Scan resolved days for the winning flip — coinflipDayResult only has win=true
    // for days where the daily VRF word's bit 0 was 1.
    const currentDay = Number(await game.currentDayView());
    for (let d = currentDay; d >= 1; d--) {
      const res = await coinflip.getCoinflipDayResult(d);
      if (res.win) return d;
    }
    throw new Error("No winning coinflip day found in setup");
  }

  // =========================================================================
  // BAF-ROUTE-03a/b — Lock predicate (the security-critical fix)
  // =========================================================================
  describe("BAF-ROUTE-03 lock predicate", function () {
    it("[03a] claim REVERTS RngLocked when level=10 + rngLocked + lastPurchaseDay (BAF window)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      // Simulate the era-10 RNG-wait window: level was bumped to 10 in
      // _finalizeRngRequest atomically with rngLockedFlag and lastPurchaseDay.
      // jackpotPhaseFlag stays false during this window.
      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 17, true); // lastPurchaseDay
      await setSlot0Bool(gameAddr, 19, true); // rngLockedFlag
      await setSlot0Bool(gameAddr, 15, false); // jackpotPhaseFlag = false

      // Confirm the external view returns the window state. With the OLD predicate
      // (purchaseLevel_ % 10 == 0) this would mis-fire: purchaseLevel_ = level + 1 = 11.
      // With the FIXED predicate (cachedLevel % 10 == 0) the lock fires correctly.
      const info = await game.purchaseInfo();
      expect(info.inJackpotPhase).to.equal(false);
      expect(info.lastPurchaseDay_).to.equal(true);
      expect(info.rngLocked_).to.equal(true);
      expect(info.lvl).to.equal(10n); // purchaseInfo.lvl now returns the actual game level (not level+1)
      expect(await game.level()).to.equal(10n);

      await expect(
        coinflip.connect(alice).claimCoinflips(alice.address, eth(10000))
      ).to.be.revertedWithCustomError(coinflip, "RngLocked");
    });

    it("[03b] deposit REVERTS CoinflipLocked under the same state", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, coin, alice, vault } = fixture;

      await mintFlipToAlice(coin, vault, alice);
      const gameAddr = await game.getAddress();

      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 17, true);
      await setSlot0Bool(gameAddr, 19, true);
      await setSlot0Bool(gameAddr, 15, false);

      await expect(
        coinflip
          .connect(alice)
          .depositCoinflip(alice.address, eth(100))
      ).to.be.revertedWithCustomError(coinflip, "CoinflipLocked");
    });

    it("[03c] claim does NOT revert when level is bumped but lastPurchaseDay is false", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      // Set level to 10 but DO NOT flip lastPurchaseDay. The lock requires all
      // four conditions to be true together — this proves the predicate is a
      // conjunction, not just a level check.
      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 17, false); // lastPurchaseDay
      await setSlot0Bool(gameAddr, 19, false); // rngLockedFlag
      await setSlot0Bool(gameAddr, 15, false); // jackpotPhaseFlag

      await expect(
        coinflip.connect(alice).claimCoinflips(alice.address, eth(10000))
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // BAF-ROUTE-04 — Non-x10 RNG-wait window does NOT lock
  // =========================================================================
  describe("BAF-ROUTE-04 non-x10 wait window", function () {
    it("[04a] claim succeeds when level=5 + rngLocked + lastPurchaseDay (era 5 has no BAF)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      await setLevel(gameAddr, 5);
      await setSlot0Bool(gameAddr, 17, true);
      await setSlot0Bool(gameAddr, 19, true);
      await setSlot0Bool(gameAddr, 15, false);

      // The predicate (level % 10 == 0) is false at level 5 — claim proceeds.
      await expect(
        coinflip.connect(alice).claimCoinflips(alice.address, eth(10000))
      ).to.not.be.reverted;
    });

    it("[04b] deposit succeeds when level=5 + rngLocked + lastPurchaseDay", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, coin, alice, vault } = fixture;

      await mintFlipToAlice(coin, vault, alice);
      const gameAddr = await game.getAddress();

      await setLevel(gameAddr, 5);
      await setSlot0Bool(gameAddr, 17, true);
      await setSlot0Bool(gameAddr, 19, true);
      await setSlot0Bool(gameAddr, 15, false);

      await expect(
        coinflip
          .connect(alice)
          .depositCoinflip(alice.address, eth(100))
      ).to.not.be.revertedWithCustomError(coinflip, "CoinflipLocked");
    });

    it("[04c] claim at level=10 with rngLocked=false does NOT revert (lock requires rngLocked)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 17, true);
      await setSlot0Bool(gameAddr, 19, false); // rngLocked = false → lock skipped
      await setSlot0Bool(gameAddr, 15, false);

      await expect(
        coinflip.connect(alice).claimCoinflips(alice.address, eth(10000))
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // BAF-ROUTE-01 — Normal sub-x10 claim emits BafFlipRecorded for the right bracket
  // =========================================================================
  describe("BAF-ROUTE-01 routing in normal purchase phase", function () {
    it("[01] level=0 purchase claim credits bracket 10 (_bafBracketLevel(1)=10)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      await setupAliceWinningFlip(fixture);

      // Default state from setupAliceWinningFlip: level=0, purchaseLevel_=1, !jackpotPhase.
      // bafLevel = purchaseLevel_ = 1 → _bafBracketLevel(1) = 10.
      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");

      // Expect at least one BafFlipRecorded for alice into bracket 10.
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      expect(aliceEvents[0].args.lvl).to.equal(10n);
      expect(aliceEvents[0].args.amount).to.be.gt(0n);
    });
  });

  // =========================================================================
  // BAF-ROUTE-05 — Post-BAF jackpot-phase override (level=10 + jackpotPhase → bracket 20)
  // =========================================================================
  describe("BAF-ROUTE-05 post-BAF jackpot-phase override", function () {
    it("[05a] claim at level=10 + jackpotPhase routes credit to bracket 20 (override fires)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      const winningDay = await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();
      const jackpotsAddr = await jackpots.getAddress();

      // Simulate: BAF for bracket 10 just resolved on day D = winningDay - 1
      // (so winningDay is the day AFTER resolution — the win still passes the
      // cursor >= bafResolvedDay filter).
      const bafResolvedDay = Number(winningDay) - 1;
      await setLastBafResolvedDay(jackpotsAddr, bafResolvedDay >= 0 ? bafResolvedDay : 0);
      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 15, true); // jackpotPhaseFlag = true
      await setSlot0Bool(gameAddr, 17, false); // lastPurchaseDay reset by phase transition
      await setSlot0Bool(gameAddr, 19, false); // rngLocked reset

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");

      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      // The override forces bafLevel = cachedLevel + 1 = 11 → _bafBracketLevel(11) = 20.
      expect(aliceEvents[0].args.lvl).to.equal(20n);
    });

    it("[05b] claim at level=15 + jackpotPhase (non-x10 era) does NOT override — credit stays in bracket 20", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      // Override only fires at cachedLevel % 10 == 0. At level 15 inside a (synthetic)
      // jackpot phase, bafLevel = cachedLevel = 15, bafLvl = _bafBracketLevel(15) = 20.
      await setLevel(gameAddr, 15);
      await setSlot0Bool(gameAddr, 15, true);
      await setSlot0Bool(gameAddr, 17, false);
      await setSlot0Bool(gameAddr, 19, false);

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      expect(aliceEvents[0].args.lvl).to.equal(20n);
    });
  });

  // =========================================================================
  // BAF-ROUTE-02 — cursor >= bafResolvedDay filter
  // =========================================================================
  describe("BAF-ROUTE-02 cursor >= bafResolvedDay (day-of-resolution NOT orphaned)", function () {
    it("[02a] cursor == lastBafResolvedDay is INCLUDED (was excluded under strict >)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      const winningDay = await setupAliceWinningFlip(fixture);
      const jackpotsAddr = await jackpots.getAddress();

      // Pin lastBafResolvedDay = winningDay. cursor == winningDay.
      // Pre-fix: cursor > lastBafResolvedDay was false → excluded. Orphan.
      // Post-fix: cursor >= lastBafResolvedDay is true → included.
      await setLastBafResolvedDay(jackpotsAddr, Number(winningDay));

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(
        aliceEvents.length,
        "day-of-resolution wins must be credited under the >= filter"
      ).to.be.gte(1);
    });

    it("[02b] cursor < lastBafResolvedDay is EXCLUDED (pre-resolution wins stay dropped)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      const winningDay = await setupAliceWinningFlip(fixture);
      const jackpotsAddr = await jackpots.getAddress();

      // Pin lastBafResolvedDay = winningDay + 1 (further in the future).
      // cursor = winningDay < lastBafResolvedDay → excluded. No BafFlipRecorded.
      await setLastBafResolvedDay(jackpotsAddr, Number(winningDay) + 1);

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(
        aliceEvents.length,
        "wins older than the latest BAF resolution must NOT be credited (no forward leak)"
      ).to.equal(0);
    });
  });

  // =========================================================================
  // BAF-ROUTE-06 — Post-jackpot era-(N+1) purchase claim routes via purchaseLevel_
  // =========================================================================
  describe("BAF-ROUTE-06 post-jackpot purchase phase routing", function () {
    it("[06] claim at level=10 + !jackpotPhase + !lastPurchaseDay routes via purchaseLevel_=11 → bracket 20", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      // Simulate era-11 purchase phase after the era-10 BAF resolved + jackpot phase closed:
      // level storage still = 10 (it bumps next at era-11's RNG request);
      // jackpotPhaseFlag = false; lastPurchaseDay = false. purchaseLevel_ = level + 1 = 11.
      // bafLevel = purchaseLevel_ = 11 → _bafBracketLevel(11) = 20.
      // This proves the !inJackpotPhase branch routes the same day-D credit to bracket 20
      // as the jackpot-phase override does in BAF-ROUTE-05a — the two paths converge.
      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 15, false); // jackpotPhaseFlag
      await setSlot0Bool(gameAddr, 17, false); // lastPurchaseDay
      await setSlot0Bool(gameAddr, 19, false); // rngLockedFlag

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      expect(aliceEvents[0].args.lvl).to.equal(20n);
    });
  });

  // =========================================================================
  // BAF-ROUTE-07 — Mid-bracket jackpot phase, override does NOT fire
  // =========================================================================
  describe("BAF-ROUTE-07 non-x10 jackpot-phase routing", function () {
    it("[07] claim at level=7 + jackpotPhase credits bracket 10 (no override fires)", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();

      // Era-7 jackpot phase (no BAF resolves at era 7 — only x10 eras have BAF).
      // cachedLevel = 7, cachedLevel % 10 != 0 → override does NOT fire.
      // bafLevel = cachedLevel = 7 → _bafBracketLevel(7) = 10 (the still-open bracket).
      await setLevel(gameAddr, 7);
      await setSlot0Bool(gameAddr, 15, true);
      await setSlot0Bool(gameAddr, 17, false);
      await setSlot0Bool(gameAddr, 19, false);

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      expect(aliceEvents[0].args.lvl).to.equal(10n);
    });
  });

  // =========================================================================
  // BAF-ROUTE-08 — markBafSkipped path routes identically to runBafJackpot
  // =========================================================================
  describe("BAF-ROUTE-08 markBafSkipped routing equivalence", function () {
    it("[08] markBafSkipped bumps lastBafResolvedDay; day-D claim routes to bracket 20 like the runBafJackpot path", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, coinflip, jackpots, alice } = fixture;

      const winningDay = await setupAliceWinningFlip(fixture);
      const gameAddr = await game.getAddress();
      const jackpotsAddr = await jackpots.getAddress();

      // Impersonate the game contract to call markBafSkipped (onlyGame modifier).
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const dayBefore = await jackpots.getLastBafResolvedDay();
      const skipTx = await jackpots.connect(gameSigner).markBafSkipped(10);
      const skipReceipt = await skipTx.wait();

      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [
        gameAddr,
      ]);

      // BafSkipped event should have fired for bracket 10.
      const skipEvents = await getEvents(skipTx, jackpots, "BafSkipped");
      expect(skipEvents.length).to.equal(1);
      expect(skipEvents[0].args.lvl).to.equal(10n);

      // lastBafResolvedDay must have advanced to "today" (currentDayView).
      const dayAfter = await jackpots.getLastBafResolvedDay();
      expect(dayAfter).to.be.gte(dayBefore);
      const currentDay = await game.currentDayView();
      expect(dayAfter).to.equal(currentDay);

      // Now drive a routing scenario equivalent to BAF-ROUTE-05a: day-D claim
      // during era-10 jackpot phase post-skip. Set lastBafResolvedDay back to
      // winningDay (the day of alice's win) so cursor == lastBafResolvedDay
      // passes the >= filter.
      await setLastBafResolvedDay(jackpotsAddr, Number(winningDay));
      await setLevel(gameAddr, 10);
      await setSlot0Bool(gameAddr, 15, true); // jackpotPhaseFlag = true (post-skip phase)
      await setSlot0Bool(gameAddr, 17, false);
      await setSlot0Bool(gameAddr, 19, false);

      const tx = await coinflip
        .connect(alice)
        .claimCoinflips(alice.address, eth(10000));
      const events = await getEvents(tx, jackpots, "BafFlipRecorded");
      const aliceEvents = events.filter(
        (e) => e.args.player.toLowerCase() === alice.address.toLowerCase()
      );
      expect(aliceEvents.length).to.be.gte(1);
      // Override fires (level=10, jackpot phase) → credit lands in bracket 20
      // — identical routing to the runBafJackpot path in BAF-ROUTE-05a.
      expect(aliceEvents[0].args.lvl).to.equal(20n);
    });
  });
});
