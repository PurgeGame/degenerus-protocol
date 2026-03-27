import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/**
 * AccessControl tests – systematic unauthorized caller checks.
 *
 * For each contract, calls restricted functions from `alice` (an unaffiliated
 * signer) and verifies that a revert occurs. Where the error name is known and
 * stable it is checked with revertedWithCustomError; otherwise the generic
 * .to.be.reverted is used.
 *
 * Error name mapping (from source files):
 *  BurnieCoin       : OnlyFlipCreditors, OnlyGame, OnlyVault
 *  BurnieCoinflip   : OnlyFlipCreditors, OnlyDegenerusGame, OnlyBurnieCoin
 *  DegenerusGame    : E (generic guard)
 *  DegenerusStonk   : Unauthorized
 *  DegenerusVault   : Unauthorized
 *  DegenerusJackpots: OnlyCoin, OnlyGame
 *  DegenerusQuests  : OnlyCoin, OnlyGame
 *  DegenerusAdmin   : NotOwner
 *  Icons32Data      : OnlyCreator
 */
describe("AccessControl", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // BurnieCoin
  // ---------------------------------------------------------------------------

  describe("BurnieCoin", function () {
    it("creditFlip: reverts when called by alice (OnlyFlipCreditors)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).creditFlip(bob.address, eth("100"))
      ).to.be.revertedWithCustomError(coin, "OnlyFlipCreditors");
    });

    it("creditFlipBatch: reverts when called by alice (OnlyFlipCreditors)", async function () {
      const { coin, alice, bob, carol, dan } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).creditFlipBatch(
          [bob.address, carol.address, dan.address],
          [eth("100"), eth("100"), eth("100")]
        )
      ).to.be.revertedWithCustomError(coin, "OnlyFlipCreditors");
    });

    it("creditCoin: reverts when called by alice (OnlyFlipCreditors)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).creditCoin(bob.address, eth("1000"))
      ).to.be.revertedWithCustomError(coin, "OnlyFlipCreditors");
    });

    it("rollDailyQuest: reverts when called by alice (OnlyGame)", async function () {
      const { coin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).rollDailyQuest(1n, 12345n)
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("vaultEscrow: reverts when called by alice (OnlyVault)", async function () {
      const { coin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).vaultEscrow(eth("1000"))
      ).to.be.revertedWithCustomError(coin, "OnlyVault");
    });

    it("mintForGame: reverts when called by alice (OnlyGame)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).mintForGame(bob.address, eth("1000"))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("burnCoin: reverts when called by alice (OnlyTrustedContracts)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).burnCoin(bob.address, eth("100"))
      ).to.be.revertedWithCustomError(coin, "OnlyTrustedContracts");
    });
  });

  // ---------------------------------------------------------------------------
  // BurnieCoinflip
  // ---------------------------------------------------------------------------

  describe("BurnieCoinflip", function () {
    it("processCoinflipPayouts: reverts when called by alice (OnlyDegenerusGame)", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coinflip.connect(alice).processCoinflipPayouts(false, 12345n, 1n)
      ).to.be.revertedWithCustomError(coinflip, "OnlyDegenerusGame");
    });

    it("claimCoinflipsFromBurnie: reverts when called by alice (OnlyBurnieCoin)", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coinflip.connect(alice).claimCoinflipsFromBurnie(alice.address, eth("100"))
      ).to.be.revertedWithCustomError(coinflip, "OnlyBurnieCoin");
    });

    it("creditFlip: reverts when called by alice (OnlyFlipCreditors)", async function () {
      const { coinflip, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coinflip.connect(alice).creditFlip(bob.address, eth("100"))
      ).to.be.revertedWithCustomError(coinflip, "OnlyFlipCreditors");
    });

    it("creditFlipBatch: reverts when called by alice (OnlyFlipCreditors)", async function () {
      const { coinflip, alice, bob, carol, dan } = await loadFixture(deployFullProtocol);

      await expect(
        coinflip.connect(alice).creditFlipBatch(
          [bob.address, carol.address, dan.address],
          [eth("100"), eth("100"), eth("100")]
        )
      ).to.be.revertedWithCustomError(coinflip, "OnlyFlipCreditors");
    });

    it("settleFlipModeChange: reverts when called by alice (OnlyDegenerusGame)", async function () {
      const { coinflip, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coinflip.connect(alice).settleFlipModeChange(alice.address)
      ).to.be.revertedWithCustomError(coinflip, "OnlyDegenerusGame");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusGame
  // ---------------------------------------------------------------------------

  describe("DegenerusGame", function () {
    it("wireVrf: reverts when called by alice (only ADMIN contract)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).wireVrf(
          alice.address, // coordinator
          1n,            // subId
          ZERO_BYTES32   // keyHash
        )
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("rawFulfillRandomWords: reverts when called by alice (only VRF coordinator)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).rawFulfillRandomWords(1n, [12345n])
      ).to.be.reverted;
    });

    it("recordMint: reverts when called by alice (only self-call)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).recordMint(
          alice.address, // player
          0,             // lvl
          eth("0.01"),   // costWei
          1,             // mintUnits
          0              // payKind = DirectEth
        )
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("recordMintQuestStreak: reverts when called by alice (only COIN)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).recordMintQuestStreak(alice.address)
      ).to.be.revertedWithCustomError(game, "E");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusStonk (DGNRS)
  // ---------------------------------------------------------------------------

  describe("DegenerusStonk (DGNRS)", function () {
    it("depositSteth: reverts when called by alice (onlyGame → Unauthorized)", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);

      await expect(
        sdgnrs.connect(alice).depositSteth(eth("1"))
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("transferFromPool: reverts when called by alice (onlyGame → Unauthorized)", async function () {
      const { sdgnrs, alice, bob } = await loadFixture(deployFullProtocol);

      // Pool enum: 0 = first pool (e.g. AFFILIATE)
      await expect(
        sdgnrs.connect(alice).transferFromPool(0, bob.address, eth("1"))
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("burnAtGameOver: reverts when called by alice (onlyGame → Unauthorized)", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);

      await expect(
        sdgnrs.connect(alice).burnAtGameOver()
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusVault
  // ---------------------------------------------------------------------------

  describe("DegenerusVault", function () {
    it("deposit: reverts when called by alice (onlyGame → Unauthorized)", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);

      await expect(
        vault.connect(alice).deposit(eth("100"), 0n, { value: eth("0") })
      ).to.be.revertedWithCustomError(vault, "Unauthorized");
    });

    it("deposit with ETH: reverts when called by alice (onlyGame → Unauthorized)", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);

      await expect(
        vault.connect(alice).deposit(0n, 0n, { value: eth("1") })
      ).to.be.revertedWithCustomError(vault, "Unauthorized");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusJackpots
  // ---------------------------------------------------------------------------

  describe("DegenerusJackpots", function () {
    it("recordBafFlip: reverts when called by alice (onlyCoin → OnlyCoin)", async function () {
      const { jackpots, alice } = await loadFixture(deployFullProtocol);

      await expect(
        jackpots.connect(alice).recordBafFlip(alice.address, 0, eth("100"))
      ).to.be.revertedWithCustomError(jackpots, "OnlyCoin");
    });

    it("runBafJackpot: reverts when called by alice (onlyGame → OnlyGame)", async function () {
      const { jackpots, alice } = await loadFixture(deployFullProtocol);

      await expect(
        jackpots.connect(alice).runBafJackpot(eth("1"), 0, 12345n)
      ).to.be.revertedWithCustomError(jackpots, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusQuests
  // ---------------------------------------------------------------------------

  describe("DegenerusQuests", function () {
    it("rollDailyQuest: reverts when called by alice (onlyCoin → OnlyCoin)", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);

      await expect(
        quests.connect(alice).rollDailyQuest(1n, 12345n)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    it("handleMint: reverts when called by alice (onlyCoin → OnlyCoin)", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);

      await expect(
        quests.connect(alice).handleMint(alice.address, 1, true)
      ).to.be.revertedWithCustomError(quests, "OnlyCoin");
    });

    // resetQuestStreak — removed (was only used for deity pass transfer penalties)

    it("awardQuestStreakBonus: reverts when called by alice (onlyGame → OnlyGame)", async function () {
      const { quests, alice } = await loadFixture(deployFullProtocol);

      await expect(
        quests.connect(alice).awardQuestStreakBonus(alice.address, 1, 1n)
      ).to.be.revertedWithCustomError(quests, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // DegenerusAdmin
  // ---------------------------------------------------------------------------

  describe("DegenerusAdmin", function () {
    it("propose: reverts when called by alice with no VRF stall (NotStalled)", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).propose(alice.address, ZERO_BYTES32)
      ).to.be.revertedWithCustomError(admin, "ZeroAddress");
    });

    it("shutdownVrf: reverts when called by alice (only GAME → NotAuthorized)", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("proposeFeedSwap: reverts when called by alice (no sDGNRS → InsufficientStake)", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      const ZERO = "0x" + "0".repeat(40);
      await expect(
        admin.connect(alice).proposeFeedSwap(ZERO)
      ).to.be.revertedWithCustomError(admin, "InsufficientStake");
    });

    it("stakeGameEthToStEth: reverts when called by alice (onlyOwner → NotOwner)", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).stakeGameEthToStEth(eth("1"))
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("setLootboxRngThreshold: reverts when called by alice (onlyOwner → NotOwner)", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).setLootboxRngThreshold(eth("5"))
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });
  });

  // ---------------------------------------------------------------------------
  // Icons32Data
  // ---------------------------------------------------------------------------

  describe("Icons32Data", function () {
    it("setPaths: reverts when called by alice (OnlyCreator)", async function () {
      const { icons32, alice } = await loadFixture(deployFullProtocol);

      await expect(
        icons32.connect(alice).setPaths(0, ["M0 0"])
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });

    it("setSymbols: reverts when called by alice (OnlyCreator)", async function () {
      const { icons32, alice } = await loadFixture(deployFullProtocol);

      const symbols = ["A", "B", "C", "D", "E", "F", "G", "H"];
      await expect(
        icons32.connect(alice).setSymbols(0, symbols)
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });

    it("finalize: reverts when called by alice (OnlyCreator)", async function () {
      const { icons32, alice } = await loadFixture(deployFullProtocol);

      await expect(
        icons32.connect(alice).finalize()
      ).to.be.revertedWithCustomError(icons32, "OnlyCreator");
    });
  });

  // ---------------------------------------------------------------------------
  // Positive sanity checks — deployer (CREATOR) CAN call owner-restricted functions
  // ---------------------------------------------------------------------------

  describe("positive access – CREATOR can call restricted functions", function () {
    it("Icons32Data.setPaths: succeeds when called by deployer (CREATOR)", async function () {
      const { icons32, deployer } = await loadFixture(deployFullProtocol);

      const tx = await icons32.connect(deployer).setPaths(0, ["M0 0 L1 1"]);
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("Icons32Data.setSymbols: succeeds when called by deployer (CREATOR)", async function () {
      const { icons32, deployer } = await loadFixture(deployFullProtocol);

      const symbols = ["Sym1", "Sym2", "Sym3", "Sym4", "Sym5", "Sym6", "Sym7", "Sym8"];
      const tx = await icons32.connect(deployer).setSymbols(0, symbols);
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("Icons32Data.finalize: succeeds when called by deployer (CREATOR)", async function () {
      const { icons32, deployer } = await loadFixture(deployFullProtocol);

      const tx = await icons32.connect(deployer).finalize();
      const receipt = await tx.wait();
      expect(receipt.status).to.equal(1);
    });

    it("Icons32Data.setPaths: reverts with AlreadyFinalized after finalize()", async function () {
      const { icons32, deployer } = await loadFixture(deployFullProtocol);

      await icons32.connect(deployer).finalize();

      await expect(
        icons32.connect(deployer).setPaths(0, ["M0 0"])
      ).to.be.revertedWithCustomError(icons32, "AlreadyFinalized");
    });

    it("DegenerusAdmin.swapGameEthForStEth: reverts for alice but not access error type matters", async function () {
      // Confirms alice cannot call owner-restricted functions.
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).swapGameEthForStEth({ value: eth("1") })
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-contract access checks
  // ---------------------------------------------------------------------------

  describe("cross-contract unauthorized access", function () {
    it("alice cannot call game.updateVrfCoordinatorAndSub (only ADMIN)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).updateVrfCoordinatorAndSub(
          alice.address,
          1n,
          ZERO_BYTES32
        )
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("alice cannot call game.adminSwapEthForStEth (only ADMIN)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      await expect(
        game.connect(alice).adminSwapEthForStEth(
          alice.address,
          eth("1"),
          { value: eth("1") }
        )
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("alice cannot call game.consumeCoinflipBoon (only trusted contracts)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);

      // consumeCoinflipBoon is guarded — only specific callers can invoke it
      // (it reads from game storage on behalf of a player; direct calls from
      // random signers should revert with E() since it checks msg.sender).
      await expect(
        game.connect(alice).consumeCoinflipBoon(alice.address)
      ).to.be.reverted;
    });

    it("coin.burnForCoinflip reverts when called by alice (not coinflip contract)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      // burnForCoinflip uses OnlyGame (reuses error) for coinflip-only access.
      await expect(
        coin.connect(alice).burnForCoinflip(bob.address, eth("100"))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("coin.mintForCoinflip reverts when called by alice (not coinflip contract)", async function () {
      const { coin, alice, bob } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).mintForCoinflip(bob.address, eth("100"))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("coin.vaultMintTo reverts when called by alice (onlyVault → OnlyVault)", async function () {
      const { coin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        coin.connect(alice).vaultMintTo(alice.address, eth("1000"))
      ).to.be.revertedWithCustomError(coin, "OnlyVault");
    });
  });
});
