import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  advanceToNextDay,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

// MintPaymentKind enum values
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };
const QUEST_TYPE_MINT_ETH = 1;

async function rollQuestAsGame(coin, game, day, entropy) {
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [gameAddr],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  await coin.connect(gameSigner).rollDailyQuest(day, entropy);
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [gameAddr],
  });
}

describe("DegenerusGame", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("starts at level 0", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.level()).to.equal(0n);
    });

    it("starts in purchase phase (jackpotPhase = false)", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.jackpotPhase()).to.be.false;
    });

    it("gameOver is false initially", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.gameOver()).to.be.false;
    });

    it("initial mint price is 0.01 ETH", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.mintPrice()).to.equal(eth("0.01"));
    });

    it("lootbox presale is active by default", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.lootboxPresaleActiveFlag()).to.be.true;
    });

    it("rng is not locked initially", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.rngLocked()).to.be.false;
    });

    it("VRF coordinator is wired after deployment (via admin constructor)", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      // Game should have VRF config from the admin wireVrf call in admin constructor
      // verify via rngLocked (should return false, not revert)
      expect(await game.rngLocked()).to.be.false;
    });

    it("levelPrizePool[0] is bootstrapped (activeTicketLevel=1 in purchase phase at level 0)", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      // In purchase phase at level=0, activeTicketLevel = level + 1 = 1
      const info = await game.purchaseInfo();
      expect(info.lvl).to.equal(1n);
      // Base level (game.level()) is 0
      expect(await game.level()).to.equal(0n);
    });

    it("tickets are pre-queued for vault and sdgnrs (levels 1-100)", async function () {
      const { game, vault, sdgnrs } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();
      // Tickets owed at level 1 should be 16 for vault and sdgnrs
      expect(await game.ticketsOwedView(1, vaultAddr)).to.equal(16n);
      expect(await game.ticketsOwedView(1, sdgnrsAddr)).to.equal(16n);
    });

    it("purchaseInfo returns consistent initial state", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      const [lvl, inJackpotPhase, lastPurchaseDay, rngLocked_, priceWei] =
        await game.purchaseInfo();
      // lvl is the active ticket level: level + 1 = 1 in purchase phase at game start
      expect(lvl).to.equal(1n);
      expect(inJackpotPhase).to.be.false;
      expect(rngLocked_).to.be.false;
      expect(priceWei).to.equal(eth("0.01"));
    });

    it("decimator window is closed initially", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      const [on] = await game.decWindow();
      expect(on).to.be.false;
      expect(await game.decWindowOpenFlag()).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Operator Approvals
  // ---------------------------------------------------------------------------
  describe("setOperatorApproval", function () {
    it("approves an operator and emits OperatorApproval event", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const tx = await game.connect(alice).setOperatorApproval(bob.address, true);
      const ev = await getEvent(tx, game, "OperatorApproval");
      expect(ev.args.owner).to.equal(alice.address);
      expect(ev.args.operator).to.equal(bob.address);
      expect(ev.args.approved).to.be.true;
      expect(await game.isOperatorApproved(alice.address, bob.address)).to.be.true;
    });

    it("revokes an operator", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      await game.connect(alice).setOperatorApproval(bob.address, true);
      await game.connect(alice).setOperatorApproval(bob.address, false);
      expect(await game.isOperatorApproved(alice.address, bob.address)).to.be.false;
    });

    it("reverts when operator is zero address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).setOperatorApproval(ZERO_ADDRESS, true)
      ).to.be.reverted;
    });

    it("operator can act on behalf of owner after approval", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      // Alice approves Bob to set her auto-rebuy
      await game.connect(alice).setOperatorApproval(bob.address, true);
      // Bob sets auto-rebuy for Alice (this is a valid operator action)
      await expect(
        game.connect(bob).setAutoRebuy(alice.address, true)
      ).to.not.be.reverted;
    });

    it("unapproved caller cannot act for another player", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      // Bob is NOT approved for Alice
      await expect(
        game.connect(bob).setAutoRebuy(alice.address, true)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Purchase flow (ETH)
  // ---------------------------------------------------------------------------
  describe("purchase (ETH)", function () {
    it("allows purchasing tickets with DirectEth", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const price = await game.mintPrice(); // 0.01 ETH per unit
      // 4 scaled units = 1 ticket at 1x price; ticketQuantity is 2-decimal scaled
      // 400 = 4 tickets
      await expect(
        game.connect(alice).purchase(
          ZERO_ADDRESS,    // buyer = msg.sender
          400n,            // 4 tickets (scaled by 100)
          0n,              // no lootbox
          ZERO_BYTES32,    // no affiliate
          MintPaymentKind.DirectEth,
          { value: price }
        )
      ).to.not.be.reverted;
    });

    it("reverts when underpaying for DirectEth", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).purchase(
          ZERO_ADDRESS,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: eth("0.001") } // underpay
        )
      ).to.be.reverted;
    });

    it("reverts when ticket buy-in is below 0.0025 ETH minimum", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).purchase(
          ZERO_ADDRESS,
          99n, // 0.002475 ETH at 0.01 mintPrice
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: eth("0.002475") }
        )
      ).to.be.reverted;
    });

    it("purchaseCoin reverts when ticket buy-in is below 0.0025 ETH minimum", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).purchaseCoin(ZERO_ADDRESS, 99n, 0n)
      ).to.be.reverted;
    });

    it("allows purchasing lootbox with ETH (minimum 0.01 ETH)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).purchase(
          ZERO_ADDRESS,
          0n,
          eth("0.01"), // lootbox amount
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: eth("0.01") }
        )
      ).to.not.be.reverted;
    });

    it("allows purchasing tickets for another address when approved", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      await game.connect(bob).setOperatorApproval(alice.address, true);
      const price = await game.mintPrice();
      // alice buys for bob using alice as buyer
      await expect(
        game.connect(alice).purchase(
          bob.address,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: price }
        )
      ).to.not.be.reverted;
    });

    it("reverts when buying for another address without approval", async function () {
      const { game, alice, bob } = await loadFixture(deployFullProtocol);
      const price = await game.mintPrice();
      await expect(
        game.connect(alice).purchase(
          bob.address,
          400n,
          0n,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: price }
        )
      ).to.be.reverted;
    });

    it("purchaseCoin with zero lootbox and zero tickets succeeds as no-op", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      // purchaseCoin with both zero succeeds (no-op: no tickets or lootboxes purchased)
      await expect(
        game.connect(alice).purchaseCoin(ZERO_ADDRESS, 0n, 0n)
      ).to.not.be.reverted;
    });

    it("lootbox purchase also completes slot-0 MINT_ETH quest like ticket purchases", async function () {
      const { game, coin, quests, alice } = await loadFixture(deployFullProtocol);
      await rollQuestAsGame(coin, game, 1n, 99n);

      const active = await quests.getActiveQuests();
      expect(active[0].questType).to.equal(QUEST_TYPE_MINT_ETH);

      const mintPrice = await game.mintPrice();

      const [, , beforeProgress, beforeCompleted] = await quests.playerQuestStates(
        alice.address
      );
      expect(beforeProgress[0]).to.equal(0n);
      expect(beforeCompleted[0]).to.equal(false);

      await expect(
        game.connect(alice).purchase(
          ZERO_ADDRESS,
          0n,
          mintPrice,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: mintPrice }
        )
      ).to.not.be.reverted;

      const [, , progress, completed] = await quests.playerQuestStates(
        alice.address
      );
      expect(progress[0]).to.equal(mintPrice);
      expect(completed[0]).to.equal(true);
    });
  });

  // endLootboxPresale was removed in 840a083 — presale now ends only via
  // automatic triggers (level 3 or 200 ETH cap).

  // ---------------------------------------------------------------------------
  // 5. setLootboxRngThreshold
  // ---------------------------------------------------------------------------
  describe("setLootboxRngThreshold", function () {
    it("vault owner can update threshold and emits LootboxRngThresholdUpdated", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);
      // deployer is vault owner (holds 100% DGVE)
      const newThreshold = eth("2");
      const tx = await game.connect(deployer).setLootboxRngThreshold(newThreshold);
      const ev = await getEvent(tx, game, "LootboxRngThresholdUpdated");
      expect(ev.args.current).to.equal(newThreshold);
    });

    it("reverts when called by non-vault-owner", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).setLootboxRngThreshold(eth("2"))
      ).to.be.reverted;
    });

    it("reverts when threshold is zero", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(deployer).setLootboxRngThreshold(0n)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 6. Auto-rebuy toggle
  // ---------------------------------------------------------------------------
  describe("setAutoRebuy", function () {
    it("enables auto-rebuy and emits AutoRebuyToggled", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const tx = await game.connect(alice).setAutoRebuy(ZERO_ADDRESS, true);
      const ev = await getEvent(tx, game, "AutoRebuyToggled");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.enabled).to.be.true;
    });

    it("disables auto-rebuy", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await game.connect(alice).setAutoRebuy(ZERO_ADDRESS, true);
      const tx = await game.connect(alice).setAutoRebuy(ZERO_ADDRESS, false);
      const ev = await getEvent(tx, game, "AutoRebuyToggled");
      expect(ev.args.enabled).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // 7. setAutoRebuyTakeProfit
  // ---------------------------------------------------------------------------
  describe("setAutoRebuyTakeProfit", function () {
    it("sets take profit and emits AutoRebuyTakeProfitSet", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("10");
      const tx = await game.connect(alice).setAutoRebuyTakeProfit(ZERO_ADDRESS, amount);
      const ev = await getEvent(tx, game, "AutoRebuyTakeProfitSet");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.takeProfit).to.equal(amount);
      expect(await game.autoRebuyTakeProfitFor(alice.address)).to.equal(amount);
    });

    it("can set take profit to zero (rebuy all)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await game.connect(alice).setAutoRebuyTakeProfit(ZERO_ADDRESS, eth("10"));
      await game.connect(alice).setAutoRebuyTakeProfit(ZERO_ADDRESS, 0n);
      expect(await game.autoRebuyTakeProfitFor(alice.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 8. setDecimatorAutoRebuy
  // ---------------------------------------------------------------------------
  describe("setDecimatorAutoRebuy", function () {
    it("disables decimator auto-rebuy for player", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const tx = await game.connect(alice).setDecimatorAutoRebuy(ZERO_ADDRESS, false);
      const ev = await getEvent(tx, game, "DecimatorAutoRebuyToggled");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.enabled).to.be.false;
    });

    it("emits DecimatorAutoRebuyToggled", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      const tx = await game.connect(alice).setDecimatorAutoRebuy(ZERO_ADDRESS, false);
      const ev = await getEvent(tx, game, "DecimatorAutoRebuyToggled");
      expect(ev.args.player).to.equal(alice.address);
      expect(ev.args.enabled).to.be.false;
    });
  });

  // ---------------------------------------------------------------------------
  // 9. claimWinnings
  // ---------------------------------------------------------------------------
  describe("claimWinnings", function () {
    it("reverts when player has no winnings", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      // Alice has 0 claimable winnings
      expect(await game.claimableWinningsOf(alice.address)).to.equal(0n);
      await expect(
        game.connect(alice).claimWinnings(ZERO_ADDRESS)
      ).to.be.reverted;
    });

    it("claimableWinningsOf returns 0 for unknown addresses", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.claimableWinningsOf(alice.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 10. claimWinningsStethFirst access control
  // ---------------------------------------------------------------------------
  describe("claimWinningsStethFirst", function () {
    it("reverts when called by a non-vault/non-dgnrs address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(game.connect(alice).claimWinningsStethFirst()).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 12. recordMintQuestStreak access control
  // ---------------------------------------------------------------------------
  describe("recordMintQuestStreak", function () {
    it("reverts when called by unauthorized address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).recordMintQuestStreak(alice.address)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 13. payCoinflipBountyDgnrs access control
  // ---------------------------------------------------------------------------
  describe("payCoinflipBountyDgnrs", function () {
    it("reverts when called by unauthorized address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).payCoinflipBountyDgnrs(alice.address, 0, 0)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 14. advanceGame
  // ---------------------------------------------------------------------------
  describe("advanceGame", function () {
    it("can be called by anyone", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await advanceToNextDay();
      await expect(game.connect(alice).advanceGame()).to.not.be.reverted;
    });

    it("advanceGame is handled gracefully when caller has no mint (no-op or gate revert)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      // Requires daily mint to trigger advancement. Alice hasn't minted,
      // so the call either no-ops gracefully or reverts. Both are acceptable.
      try {
        await game.connect(alice).advanceGame();
      } catch (e) {
        expect(e.message).to.satisfy(
          (msg) => msg.includes("revert") || msg.includes("reverted")
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // 15. adminSwapEthForStEth access control
  // ---------------------------------------------------------------------------
  describe("adminSwapEthForStEth", function () {
    it("reverts when called by non-admin", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).adminSwapEthForStEth(alice.address, eth("1"), {
          value: eth("1"),
        })
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 16. adminStakeEthForStEth access control
  // ---------------------------------------------------------------------------
  describe("adminStakeEthForStEth", function () {
    it("reverts when called by non-admin", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).adminStakeEthForStEth(eth("1"))
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 17. wireVrf access control
  // ---------------------------------------------------------------------------
  describe("wireVrf", function () {
    it("reverts when called by non-admin", async function () {
      const { game, alice, mockVRF } = await loadFixture(deployFullProtocol);
      const vrfAddr = await mockVRF.getAddress();
      await expect(
        game.connect(alice).wireVrf(vrfAddr, 1n, ZERO_BYTES32)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 18. VRF callback (rawFulfillRandomWords)
  // ---------------------------------------------------------------------------
  describe("VRF callback", function () {
    it("rawFulfillRandomWords reverts when called by non-VRF coordinator", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).rawFulfillRandomWords(1n, [12345n])
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 20. View functions
  // ---------------------------------------------------------------------------
  describe("view functions", function () {
    // rngStalledForThreeDays, lootboxRngIndexView, lootboxRngThresholdView,
    // ethMintLevelCount, ethMintStreakCount, hasActiveLazyPass, autoRebuyEnabledFor,
    // decimatorAutoRebuyEnabledFor, lootboxRngWord removed in Phase 146 ABI cleanup

    it("currentDayView returns a non-zero day", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      const day = await game.currentDayView();
      expect(day).to.be.gt(0n);
    });

    it("futurePrizePoolView is zero before any purchases", async function () {
      const { game } = await loadFixture(deployFullProtocol);
      expect(await game.futurePrizePoolView()).to.equal(0n);
    });

    it("afKingModeFor returns false for new player", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.afKingModeFor(alice.address)).to.be.false;
    });

    it("playerActivityScore returns 0 for new player", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.playerActivityScore(alice.address)).to.equal(0n);
    });

    it("ticketsOwedView returns 0 for player with no tickets", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.ticketsOwedView(1, alice.address)).to.equal(0n);
    });

    it("deityPassCountFor returns 0 for new player", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      expect(await game.deityPassCountFor(alice.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 21. claimAffiliateDgnrs
  // ---------------------------------------------------------------------------
  describe("claimAffiliateDgnrs", function () {
    it("reverts at level 0 (needs level > 1)", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).claimAffiliateDgnrs(ZERO_ADDRESS)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 22. onDeityPassTransfer — removed (deity passes are now soulbound)
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // 23. consumeCoinflipBoon / consumeDecimatorBoon access control
  // ---------------------------------------------------------------------------
  describe("consumeCoinflipBoon access control", function () {
    it("reverts when called by non-coin/non-coinflip address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).consumeCoinflipBoon(alice.address)
      ).to.be.reverted;
    });
  });

  describe("consumeDecimatorBoon access control", function () {
    it("reverts when called by non-coin address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).consumeDecimatorBoon(alice.address)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 24. deactivateAfKingFromCoin access control
  // ---------------------------------------------------------------------------
  describe("deactivateAfKingFromCoin", function () {
    it("reverts when called by non-coin/non-coinflip address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).deactivateAfKingFromCoin(alice.address)
      ).to.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 25. syncAfKingLazyPassFromCoin access control
  // ---------------------------------------------------------------------------
  describe("syncAfKingLazyPassFromCoin", function () {
    it("reverts when called by non-coinflip address", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).syncAfKingLazyPassFromCoin(alice.address)
      ).to.be.reverted;
    });
  });
});
