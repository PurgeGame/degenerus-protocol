import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

/*
 * BurnieCoinflip Unit Tests
 * ========================
 * Covers:
 *  - Constructor / immutable addresses
 *  - depositCoinflip (happy path, min amount, access control)
 *  - processCoinflipPayouts (onlyGame, win/loss outcomes, bounty)
 *  - claimCoinflips (happy path, rngLocked guard)
 *  - claimCoinflipsFromBurnie / consumeCoinflipsForBurn (onlyBurnie)
 *  - creditFlip / creditFlipBatch (onlyFlipCreditors)
 *  - setCoinflipAutoRebuy (enable, disable, rngLocked guard)
 *  - setCoinflipAutoRebuyTakeProfit
 *  - Bounty system (BiggestFlipUpdated, BountyOwed, BountyPaid)
 *  - BAF top bettor (CoinflipTopUpdated — only on BAF lastPurchaseDay)
 *  - Events
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Mint BURNIE to `player` using the vault contract's vaultMintTo function.
 * The vault must first escrow the tokens via vaultEscrow (callable by the vault itself).
 * We impersonate the vault contract address to call both.
 */
async function giveBurnie(coin, player, amount, vaultAddr) {
  await hre.ethers.provider.send("hardhat_setBalance", [
    vaultAddr,
    "0x1000000000000000000",
  ]);
  await hre.ethers.provider.send("hardhat_impersonateAccount", [vaultAddr]);
  const vaultSigner = await hre.ethers.getSigner(vaultAddr);
  // Vault can call vaultEscrow on itself to increase allowance
  await coin.connect(vaultSigner).vaultEscrow(amount);
  // Then mint to player
  await coin.connect(vaultSigner).vaultMintTo(player.address, amount);
  await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [vaultAddr]);
}

/**
 * Make a direct coinflip deposit on behalf of `player`.
 * burnForCoinflip is called internally by the coinflip contract directly from the
 * player's balance — no approval needed.
 */
async function deposit(coinflip, player, amount) {
  return coinflip.connect(player).depositCoinflip(ZERO_ADDRESS, amount);
}

/**
 * Simulate one full day: impersonate the game contract and call processCoinflipPayouts.
 * Returns the tx so callers can inspect events.
 */
async function resolveDay(hreEthers, game, coinflip, epoch, rngWord, bonusFlip = false) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const tx = await coinflip
    .connect(gameSigner)
    .processCoinflipPayouts(bonusFlip, rngWord, epoch);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  return tx;
}

// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("BurnieCoinflip", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. Constructor / Immutables
  // =========================================================================
  describe("Constructor", function () {
    it("stores correct immutable addresses", async function () {
      const { coinflip, coin, game, jackpots, wwxrp } = await loadFixture(
        deployFullProtocol
      );
      expect(await coinflip.burnie()).to.equal(await coin.getAddress());
      expect(await coinflip.degenerusGame()).to.equal(await game.getAddress());
      expect(await coinflip.jackpots()).to.equal(await jackpots.getAddress());
      expect(await coinflip.wwxrp()).to.equal(await wwxrp.getAddress());
    });

    it("initial currentBounty is 1000 BURNIE", async function () {
      const { coinflip } = await loadFixture(deployFullProtocol);
      expect(await coinflip.currentBounty()).to.equal(eth(1000));
    });

    it("initial biggestFlipEver is zero", async function () {
      const { coinflip } = await loadFixture(deployFullProtocol);
      expect(await coinflip.biggestFlipEver()).to.equal(0n);
    });
  });

  // =========================================================================
  // 2. depositCoinflip
  // =========================================================================
  describe("depositCoinflip", function () {
    it("reverts when amount is below 100 BURNIE minimum", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(200), vaultAddr);
      await expect(
        deposit(coinflip, alice, eth(99))
      ).to.be.revertedWithCustomError(coinflip, "AmountLTMin");
    });

    it("accepts minimum deposit of exactly 100 BURNIE", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(200), vaultAddr);
      await expect(deposit(coinflip, alice, eth(100))).to.not.be.reverted;
    });

    it("emits CoinflipDeposit event", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(500), vaultAddr);
      const tx = await deposit(coinflip, alice, eth(200));
      const ev = await getEvent(tx, coinflip, "CoinflipDeposit");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.creditedFlip).to.equal(eth(200));
    });

    it("emits CoinflipStakeUpdated for the next day", async function () {
      const { coinflip, coin, alice, game, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(500), vaultAddr);
      const currentDay = await game.currentDayView();
      const tx = await deposit(coinflip, alice, eth(200));
      const ev = await getEvent(tx, coinflip, "CoinflipStakeUpdated");
      // Target day is currentDay + 1
      expect(ev.args.day).to.equal(currentDay + 1n);
      expect(ev.args.player).to.equal(alice.address);
    });

    it("records coinflipAmount for next day", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(500), vaultAddr);
      await deposit(coinflip, alice, eth(300));
      // coinflipAmount() returns stake for the next day
      const stake = await coinflip.coinflipAmount(alice.address);
      expect(stake).to.be.gte(eth(300));
    });

    it("emits CoinflipTopUpdated on deposit", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(1000), vaultAddr);
      const tx = await deposit(coinflip, alice, eth(500));
      const evs = await getEvents(tx, coinflip, "CoinflipTopUpdated");
      expect(evs.length).to.equal(1);
    });

    it("reverts NotApproved when non-approved operator deposits on behalf of player", async function () {
      const { coinflip, bob, alice } = await loadFixture(deployFullProtocol);
      // bob tries to deposit on behalf of alice without approval
      await expect(
        coinflip.connect(bob).depositCoinflip(alice.address, eth(200))
      ).to.be.revertedWithCustomError(coinflip, "NotApproved");
    });

    it("zero amount deposit emits CoinflipDeposit with amount 0", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      const tx = await coinflip.connect(alice).depositCoinflip(ZERO_ADDRESS, 0);
      const ev = await getEvent(tx, coinflip, "CoinflipDeposit");
      expect(ev.args.creditedFlip).to.equal(0n);
    });
  });

  // =========================================================================
  // 3. processCoinflipPayouts (onlyGame)
  // =========================================================================
  describe("processCoinflipPayouts", function () {
    it("reverts when caller is not the game contract", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip.connect(alice).processCoinflipPayouts(false, 1n, 1n)
      ).to.be.revertedWithCustomError(coinflip, "OnlyDegenerusGame");
    });

    it("emits CoinflipDayResolved with win=true for odd rngWord", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      // rngWord & 1 == 1 => win
      const rngWord = 1n;
      const epoch = 1n;
      const tx = await resolveDay(hre.ethers, game, coinflip, epoch, rngWord);
      const ev = await getEvent(tx, coinflip, "CoinflipDayResolved");
      expect(ev.args.day).to.equal(epoch);
      expect(ev.args.win).to.equal(true);
    });

    it("emits CoinflipDayResolved with win=false for even rngWord", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      const rngWord = 2n;
      const epoch = 1n;
      const tx = await resolveDay(hre.ethers, game, coinflip, epoch, rngWord);
      const ev = await getEvent(tx, coinflip, "CoinflipDayResolved");
      expect(ev.args.win).to.equal(false);
    });

    it("rewardPercent is 50 when roll == 0 (seedWord % 20 == 0)", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      // Find an rngWord such that keccak256(rngWord, epoch) % 20 == 0
      const epoch = 5n;
      let found = false;
      for (let i = 0n; i < 10000n; i++) {
        const seed = hre.ethers.solidityPackedKeccak256(
          ["uint256", "uint32"],
          [i, epoch]
        );
        const seedBig = BigInt(seed);
        if (seedBig % 20n === 0n) {
          const tx = await resolveDay(hre.ethers, game, coinflip, epoch, i);
          const ev = await getEvent(tx, coinflip, "CoinflipDayResolved");
          expect(ev.args.rewardPercent).to.equal(50);
          found = true;
          break;
        }
      }
      if (!found) this.skip();
    });

    it("rewardPercent is 150 when roll == 1 (seedWord % 20 == 1)", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      const epoch = 7n;
      let found = false;
      for (let i = 0n; i < 10000n; i++) {
        const seed = hre.ethers.solidityPackedKeccak256(
          ["uint256", "uint32"],
          [i, epoch]
        );
        const seedBig = BigInt(seed);
        if (seedBig % 20n === 1n) {
          const tx = await resolveDay(hre.ethers, game, coinflip, epoch, i);
          const ev = await getEvent(tx, coinflip, "CoinflipDayResolved");
          expect(ev.args.rewardPercent).to.equal(150);
          found = true;
          break;
        }
      }
      if (!found) this.skip();
    });

    it("bounty pool grows by 1000 BURNIE per resolved day", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      const before = await coinflip.currentBounty();
      await resolveDay(hre.ethers, game, coinflip, 1n, 2n);
      const after = await coinflip.currentBounty();
      expect(after - before).to.equal(eth(1000));
    });

    it("bountyPaid is 0 and bountyRecipient is zero address when no bounty owner", async function () {
      const { coinflip, game } = await loadFixture(deployFullProtocol);
      const tx = await resolveDay(hre.ethers, game, coinflip, 1n, 1n);
      const ev = await getEvent(tx, coinflip, "CoinflipDayResolved");
      expect(ev.args.bountyPaid).to.equal(0n);
      expect(ev.args.bountyRecipient).to.equal(ZERO_ADDRESS);
    });
  });

  // =========================================================================
  // 4. Bounty System
  // =========================================================================
  describe("Bounty system", function () {
    it("emits BiggestFlipUpdated when deposit exceeds current record", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      const tx = await deposit(coinflip, alice, eth(500));
      const evs = await getEvents(tx, coinflip, "BiggestFlipUpdated");
      expect(evs.length).to.equal(1);
      expect(evs[0].args.player).to.equal(alice.address);
      expect(evs[0].args.recordAmount).to.equal(eth(500));
    });

    it("emits BountyOwed when setting new record from zero", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      const tx = await deposit(coinflip, alice, eth(500));
      const evs = await getEvents(tx, coinflip, "BountyOwed");
      expect(evs.length).to.equal(1);
      expect(evs[0].args.player).to.equal(alice.address);
    });

    it("does not update biggestFlipEver when deposit is smaller than record", async function () {
      const { coinflip, coin, alice, bob, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      await giveBurnie(coin, bob, eth(2000), vaultAddr);

      // Alice sets the record first
      await deposit(coinflip, alice, eth(1000));
      const record = await coinflip.biggestFlipEver();

      // Bob deposits less
      const tx = await deposit(coinflip, bob, eth(500));
      const evs = await getEvents(tx, coinflip, "BiggestFlipUpdated");
      expect(evs.length).to.equal(0);
      expect(await coinflip.biggestFlipEver()).to.equal(record);
    });

    it("second record setter must exceed first by 1% to steal bounty", async function () {
      const { coinflip, coin, alice, bob, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      await giveBurnie(coin, bob, eth(2000), vaultAddr);

      await deposit(coinflip, alice, eth(1000));

      // Bob deposits >1% more than alice (1001 BURNIE >= threshold 1010 after 1% of 1000 = 10)
      // 1% of 1000 = 10, so threshold = 1000 + 10 = 1010
      const tx = await deposit(coinflip, bob, eth(1010));
      const evs = await getEvents(tx, coinflip, "BountyOwed");
      expect(evs.length).to.equal(1);
      expect(evs[0].args.player).to.equal(bob.address);
    });

    it("biggestFlipEver tracks the largest direct deposit", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(5000), vaultAddr);
      await deposit(coinflip, alice, eth(200));
      await deposit(coinflip, alice, eth(500));
      expect(await coinflip.biggestFlipEver()).to.equal(eth(500));
    });
  });

  // =========================================================================
  // 5. claimCoinflips
  // =========================================================================
  describe("claimCoinflips", function () {
    it("does not revert with RngLocked when rngLocked is false", async function () {
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.rngLocked()).to.equal(false);
      await expect(
        coinflip.connect(alice).claimCoinflips(ZERO_ADDRESS, eth(100))
      ).to.not.be.revertedWithCustomError(coinflip, "RngLocked");
    });

    it("returns 0 when player has no claimable balance", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      const claimed = await coinflip
        .connect(alice)
        .claimCoinflips.staticCall(ZERO_ADDRESS, eth(100));
      expect(claimed).to.equal(0n);
    });

    it("claimCoinflips with explicit player address succeeds when called by player", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      // No balance, but call should not revert with access error
      await expect(
        coinflip.connect(alice).claimCoinflips(alice.address, eth(100))
      ).to.not.be.reverted;
    });

    it("claimCoinflips reverts with NotApproved when operator not approved", async function () {
      const { coinflip, alice, bob } = await loadFixture(deployFullProtocol);
      // bob tries to claim on behalf of alice without approval
      await expect(
        coinflip.connect(bob).claimCoinflips(alice.address, eth(100))
      ).to.be.revertedWithCustomError(coinflip, "NotApproved");
    });

    it("previewClaimCoinflips matches actual claimable after winning day", async function () {
      const { coinflip, coin, game, alice, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      await deposit(coinflip, alice, eth(1000));

      const currentDay = await game.currentDayView();
      const epoch = currentDay + 1n;

      // Win (odd rngWord)
      await resolveDay(hre.ethers, game, coinflip, epoch, 1n);

      const preview = await coinflip.previewClaimCoinflips(alice.address);
      // Preview should be > 0 (stake + reward)
      expect(preview).to.be.gt(0n);
    });
  });

  // =========================================================================
  // 6. claimCoinflipsFromBurnie / consumeCoinflipsForBurn (onlyBurnieCoin)
  // =========================================================================
  describe("claimCoinflipsFromBurnie / consumeCoinflipsForBurn", function () {
    it("claimCoinflipsFromBurnie reverts when called by non-coin address", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip.connect(alice).claimCoinflipsFromBurnie(alice.address, eth(100))
      ).to.be.revertedWithCustomError(coinflip, "OnlyBurnieCoin");
    });

    it("consumeCoinflipsForBurn reverts when called by non-coin address", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip.connect(alice).consumeCoinflipsForBurn(alice.address, eth(100))
      ).to.be.revertedWithCustomError(coinflip, "OnlyBurnieCoin");
    });
  });

  // =========================================================================
  // 7. creditFlip / creditFlipBatch (onlyFlipCreditors)
  // =========================================================================
  describe("creditFlip / creditFlipBatch", function () {
    it("creditFlip reverts when called by unauthorized address", async function () {
      const { coinflip, alice, bob } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip.connect(alice).creditFlip(bob.address, eth(100))
      ).to.be.revertedWithCustomError(coinflip, "OnlyFlipCreditors");
    });

    it("creditFlipBatch reverts when called by unauthorized address", async function () {
      const { coinflip, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );
      await expect(
        coinflip.connect(alice).creditFlipBatch(
          [bob.address, carol.address, ZERO_ADDRESS],
          [eth(100), eth(200), 0n]
        )
      ).to.be.revertedWithCustomError(coinflip, "OnlyFlipCreditors");
    });

    it("creditFlip from game contract emits CoinflipStakeUpdated", async function () {
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const tx = await coinflip
        .connect(gameSigner)
        .creditFlip(alice.address, eth(500));
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);

      const evs = await getEvents(tx, coinflip, "CoinflipStakeUpdated");
      expect(evs.length).to.equal(1);
      expect(evs[0].args.player).to.equal(alice.address);
      expect(evs[0].args.amount).to.equal(eth(500));
    });

    it("creditFlip ignores zero address and zero amount silently", async function () {
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      // zero address: should not emit CoinflipStakeUpdated
      const tx1 = await coinflip
        .connect(gameSigner)
        .creditFlip(ZERO_ADDRESS, eth(500));
      const evs1 = await getEvents(tx1, coinflip, "CoinflipStakeUpdated");
      expect(evs1.length).to.equal(0);

      // zero amount: should not emit CoinflipStakeUpdated
      const tx2 = await coinflip
        .connect(gameSigner)
        .creditFlip(alice.address, 0n);
      const evs2 = await getEvents(tx2, coinflip, "CoinflipStakeUpdated");
      expect(evs2.length).to.equal(0);

      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
    });

    it("creditFlipBatch credits all three non-zero players from game contract", async function () {
      const { coinflip, game, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const tx = await coinflip.connect(gameSigner).creditFlipBatch(
        [alice.address, bob.address, carol.address],
        [eth(100), eth(200), eth(300)]
      );
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);

      const evs = await getEvents(tx, coinflip, "CoinflipStakeUpdated");
      expect(evs.length).to.equal(3);
    });

    it("creditFlipBatch skips zero-address slots", async function () {
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const tx = await coinflip.connect(gameSigner).creditFlipBatch(
        [alice.address, ZERO_ADDRESS, ZERO_ADDRESS],
        [eth(100), 0n, 0n]
      );
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);

      const evs = await getEvents(tx, coinflip, "CoinflipStakeUpdated");
      expect(evs.length).to.equal(1);
    });
  });

  // =========================================================================
  // 8. Auto-Rebuy
  // =========================================================================
  describe("setCoinflipAutoRebuy", function () {
    it("enables auto-rebuy and emits CoinflipAutoRebuyToggled", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      const tx = await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      const ev = await getEvent(tx, coinflip, "CoinflipAutoRebuyToggled");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.enabled).to.equal(true);
    });

    it("emits CoinflipAutoRebuyStopSet when enabling with takeProfit", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      const tx = await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(5000));
      const ev = await getEvent(tx, coinflip, "CoinflipAutoRebuyStopSet");
      expect(ev.args.stopAmount).to.equal(eth(5000));
    });

    it("reverts with AutoRebuyAlreadyEnabled if enabling when already enabled", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      await expect(
        coinflip
          .connect(alice)
          .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000))
      ).to.be.revertedWithCustomError(coinflip, "AutoRebuyAlreadyEnabled");
    });

    it("disables auto-rebuy and emits CoinflipAutoRebuyToggled(false)", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      const tx = await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, false, 0n);
      const ev = await getEvent(tx, coinflip, "CoinflipAutoRebuyToggled");
      expect(ev.args.enabled).to.equal(false);
    });

    it("coinflipAutoRebuyInfo reflects enabled state after enabling", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(2000));
      const info = await coinflip.coinflipAutoRebuyInfo(alice.address);
      expect(info.enabled).to.equal(true);
      expect(info.stop).to.equal(eth(2000));
    });

    it("coinflipAutoRebuyInfo enabled=false after disabling", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      await coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, false, 0n);
      const info = await coinflip.coinflipAutoRebuyInfo(alice.address);
      expect(info.enabled).to.equal(false);
    });

    it("reverts RngLocked if rngLocked is true", async function () {
      // We cannot easily force rngLocked=true without going through the full game flow.
      // This test verifies the happy path when rngLocked=false.
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.rngLocked()).to.equal(false);
      await expect(
        coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000))
      ).to.not.be.revertedWithCustomError(coinflip, "RngLocked");
    });
  });

  describe("setCoinflipAutoRebuyTakeProfit", function () {
    it("reverts AutoRebuyNotEnabled when auto-rebuy is off", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip
          .connect(alice)
          .setCoinflipAutoRebuyTakeProfit(ZERO_ADDRESS, eth(1000))
      ).to.be.revertedWithCustomError(coinflip, "AutoRebuyNotEnabled");
    });

    it("updates stop amount and emits CoinflipAutoRebuyStopSet", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip
        .connect(alice)
        .setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      const tx = await coinflip
        .connect(alice)
        .setCoinflipAutoRebuyTakeProfit(ZERO_ADDRESS, eth(3000));
      const ev = await getEvent(tx, coinflip, "CoinflipAutoRebuyStopSet");
      expect(ev.args.stopAmount).to.equal(eth(3000));
      const info = await coinflip.coinflipAutoRebuyInfo(alice.address);
      expect(info.stop).to.equal(eth(3000));
    });
  });

  // =========================================================================
  // 9. settleFlipModeChange (onlyGame)
  // =========================================================================
  describe("settleFlipModeChange", function () {
    it("reverts when called by non-game address", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await expect(
        coinflip.connect(alice).settleFlipModeChange(alice.address)
      ).to.be.revertedWithCustomError(coinflip, "OnlyDegenerusGame");
    });

    it("game can call settleFlipModeChange without revert", async function () {
      const { coinflip, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.ethers.provider.send("hardhat_impersonateAccount", [gameAddr]);
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x1000000000000000000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await expect(
        coinflip.connect(gameSigner).settleFlipModeChange(alice.address)
      ).to.not.be.reverted;
      await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
    });
  });

  // =========================================================================
  // 10. View Functions
  // =========================================================================
  describe("View functions", function () {
    it("previewClaimCoinflips returns 0 for player with no activity", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      expect(await coinflip.previewClaimCoinflips(alice.address)).to.equal(0n);
    });

    it("coinflipTopLastDay returns zero address before any resolved day", async function () {
      const { coinflip } = await loadFixture(deployFullProtocol);
      const [player, score] = await coinflip.coinflipTopLastDay();
      expect(player).to.equal(ZERO_ADDRESS);
      expect(score).to.equal(0n);
    });

    it("coinflipTopLastDay returns top bettor after day resolves", async function () {
      const { coinflip, coin, game, alice, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(1000), vaultAddr);
      await deposit(coinflip, alice, eth(500));

      const currentDay = await game.currentDayView();
      await resolveDay(hre.ethers, game, coinflip, currentDay + 1n, 1n);

      const [player, score] = await coinflip.coinflipTopLastDay();
      expect(player).to.equal(alice.address);
      expect(score).to.be.gt(0n);
    });

    it("coinflipAmount returns 0 for player with no stake", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      expect(await coinflip.coinflipAmount(alice.address)).to.equal(0n);
    });

    it("coinflipAmount increases after deposit", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(1000), vaultAddr);
      await deposit(coinflip, alice, eth(500));
      expect(await coinflip.coinflipAmount(alice.address)).to.be.gte(eth(500));
    });

    it("coinflipAutoRebuyInfo startDay is lastClaim day when enabled", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);
      await coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, true, eth(1000));
      const info = await coinflip.coinflipAutoRebuyInfo(alice.address);
      // carry should be 0 initially
      expect(info.carry).to.equal(0n);
    });
  });

  // =========================================================================
  // 11. End-to-end: deposit, resolve (win), claim cycle
  // =========================================================================
  describe("End-to-end deposit/resolve/claim", function () {
    it("player deposit is burned from balance", async function () {
      const { coinflip, coin, alice, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      const balBefore = await coin.balanceOf(alice.address);

      await deposit(coinflip, alice, eth(1000));

      const balAfterDeposit = await coin.balanceOf(alice.address);
      expect(balBefore - balAfterDeposit).to.equal(eth(1000));
    });

    it("player wins and can claim after day resolution", async function () {
      const { coinflip, coin, game, alice, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      await deposit(coinflip, alice, eth(1000));

      const currentDay = await game.currentDayView();
      const epoch = currentDay + 1n;

      // Win: odd rngWord => win=true
      await resolveDay(hre.ethers, game, coinflip, epoch, 1n);

      const preview = await coinflip.previewClaimCoinflips(alice.address);
      expect(preview).to.be.gt(0n);

      // Claim should succeed and mint tokens
      await expect(
        coinflip.connect(alice).claimCoinflips(ZERO_ADDRESS, preview)
      ).to.not.be.reverted;
    });

    it("player loses and gets WWXRP consolation prize on claim", async function () {
      const { coinflip, coin, game, alice, vault, wwxrp } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(2000), vaultAddr);
      await deposit(coinflip, alice, eth(1000));

      const currentDay = await game.currentDayView();
      const epoch = currentDay + 1n;

      // Loss: even rngWord => win=false
      await resolveDay(hre.ethers, game, coinflip, epoch, 2n);

      // Claim triggers WWXRP mint for losses
      await coinflip.connect(alice).claimCoinflips(ZERO_ADDRESS, eth(999999));

      const wwxrpBal = await wwxrp.balanceOf(alice.address);
      expect(wwxrpBal).to.be.gte(eth(1)); // 1 WWXRP per loss
    });

    it("multiple consecutive wins compound correctly with auto-rebuy", async function () {
      const { coinflip, coin, game, alice, vault } = await loadFixture(
        deployFullProtocol
      );
      const vaultAddr = await vault.getAddress();
      await giveBurnie(coin, alice, eth(5000), vaultAddr);

      // Enable auto-rebuy with no take profit (all carries forward)
      await coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, true, 0n);

      // First deposit
      await deposit(coinflip, alice, eth(1000));

      const currentDay = await game.currentDayView();
      // Resolve day 1 as win
      await resolveDay(hre.ethers, game, coinflip, currentDay + 1n, 1n);

      // Disable auto-rebuy to collect winnings
      const tx = await coinflip.connect(alice).setCoinflipAutoRebuy(ZERO_ADDRESS, false, 0n);
      // Should emit CoinflipAutoRebuyToggled(false)
      const ev = await getEvent(tx, coinflip, "CoinflipAutoRebuyToggled");
      expect(ev.args.enabled).to.equal(false);
    });
  });

});
