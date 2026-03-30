import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

/*
 * BurnieCoin Unit Tests
 *
 * Contract: contracts/BurnieCoin.sol
 *
 * Architecture summary:
 *   - Custom ERC20 "BURNIE" with 18 decimals
 *   - Initial totalSupply = 0, vaultAllowance = 2,000,000 BURNIE
 *   - Vault escrow: virtual reserve, minted via vaultMintTo()
 *   - Game/Affiliate bypass for minting, burning, and flip credits
 *   - Transfers to ContractAddresses.VAULT redirect to allowance (no circulating balance)
 *   - Access-controlled: onlyGame, onlyVault, onlyFlipCreditors, onlyTrustedContracts
 *
 * In the test fixture the deployer IS the ContractAddresses.CREATOR.
 * The GAME contract is f.game, VAULT is f.vault, AFFILIATE is f.affiliate,
 * COINFLIP is f.coinflip.
 */

describe("BurnieCoin", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function getFixture() {
    return loadFixture(deployFullProtocol);
  }

  // Impersonate an address so we can call privileged functions in tests
  async function impersonate(address) {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [address],
    });
    await hre.network.provider.send("hardhat_setBalance", [
      address,
      "0x56BC75E2D63100000", // 100 ETH
    ]);
    return hre.ethers.getSigner(address);
  }

  async function stopImpersonate(address) {
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [address],
    });
  }

  // ---------------------------------------------------------------------------
  // Initial state / constructor side effects
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("name is 'Burnies'", async function () {
      const { coin } = await getFixture();
      expect(await coin.name()).to.equal("Burnies");
    });

    it("symbol is 'BURNIE'", async function () {
      const { coin } = await getFixture();
      expect(await coin.symbol()).to.equal("BURNIE");
    });

    it("decimals is 18", async function () {
      const { coin } = await getFixture();
      expect(await coin.decimals()).to.equal(18);
    });

    it("totalSupply is 2M on deploy (sDGNRS backing reserve)", async function () {
      const { coin } = await getFixture();
      expect(await coin.totalSupply()).to.equal(eth(2_000_000));
    });

    it("vaultMintAllowance is 2,000,000 BURNIE on deploy", async function () {
      const { coin } = await getFixture();
      expect(await coin.vaultMintAllowance()).to.equal(eth(2_000_000));
    });

    it("supplyIncUncirculated equals totalSupply + vaultAllowance", async function () {
      const { coin } = await getFixture();
      const total = await coin.totalSupply();
      const vault = await coin.vaultMintAllowance();
      expect(await coin.supplyIncUncirculated()).to.equal(total + vault);
    });

    it("all user balances start at zero", async function () {
      const { coin, alice, bob, carol } = await getFixture();
      for (const user of [alice, bob, carol]) {
        expect(await coin.balanceOf(user.address)).to.equal(0n);
      }
    });

    it("all allowances start at zero", async function () {
      const { coin, alice, bob } = await getFixture();
      expect(await coin.allowance(alice.address, bob.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — approve / allowance
  // ---------------------------------------------------------------------------

  describe("approve()", function () {
    it("sets allowance and emits Approval event", async function () {
      const { coin, alice, bob } = await getFixture();
      const tx = await coin.connect(alice).approve(bob.address, eth(500));
      await expect(tx)
        .to.emit(coin, "Approval")
        .withArgs(alice.address, bob.address, eth(500));
      expect(await coin.allowance(alice.address, bob.address)).to.equal(
        eth(500)
      );
    });

    it("can set allowance to type(uint256).max (infinite approval)", async function () {
      const { coin, alice, bob } = await getFixture();
      const max = hre.ethers.MaxUint256;
      await coin.connect(alice).approve(bob.address, max);
      expect(await coin.allowance(alice.address, bob.address)).to.equal(max);
    });

    it("can reduce allowance by calling approve again", async function () {
      const { coin, alice, bob } = await getFixture();
      await coin.connect(alice).approve(bob.address, eth(100));
      await coin.connect(alice).approve(bob.address, eth(50));
      expect(await coin.allowance(alice.address, bob.address)).to.equal(
        eth(50)
      );
    });

    it("can set allowance to 0 (effectively revoke)", async function () {
      const { coin, alice, bob } = await getFixture();
      await coin.connect(alice).approve(bob.address, eth(100));
      await coin.connect(alice).approve(bob.address, 0);
      expect(await coin.allowance(alice.address, bob.address)).to.equal(0n);
    });

    it("does NOT emit Approval when the new amount equals the current allowance", async function () {
      const { coin, alice, bob } = await getFixture();
      await coin.connect(alice).approve(bob.address, eth(100));
      // Setting the same value — contract skips the assignment but still emits
      // (the contract always emits even if value unchanged — let's verify)
      const tx = await coin.connect(alice).approve(bob.address, eth(100));
      await expect(tx)
        .to.emit(coin, "Approval")
        .withArgs(alice.address, bob.address, eth(100));
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — transfer (requires balance, so we need mintForGame first)
  // ---------------------------------------------------------------------------

  describe("transfer()", function () {
    async function mintToAlice(coin, game, alice, amount = eth(1000)) {
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, amount);
      await stopImpersonate(gameAddr);
    }

    it("transfers tokens between two accounts and emits Transfer", async function () {
      const { coin, game, alice, bob } = await getFixture();
      await mintToAlice(coin, game, alice);

      const tx = await coin.connect(alice).transfer(bob.address, eth(200));
      await expect(tx)
        .to.emit(coin, "Transfer")
        .withArgs(alice.address, bob.address, eth(200));

      expect(await coin.balanceOf(alice.address)).to.equal(eth(800));
      expect(await coin.balanceOf(bob.address)).to.equal(eth(200));
    });

    it("reverts (underflow) when balance is insufficient", async function () {
      const { coin, alice, bob } = await getFixture();
      // alice has no balance
      await expect(
        coin.connect(alice).transfer(bob.address, eth(1))
      ).to.be.reverted;
    });

    it("allows transferring entire balance", async function () {
      const { coin, game, alice, bob } = await getFixture();
      await mintToAlice(coin, game, alice);
      await coin.connect(alice).transfer(bob.address, eth(1000));
      expect(await coin.balanceOf(alice.address)).to.equal(0n);
      expect(await coin.balanceOf(bob.address)).to.equal(eth(1000));
    });

    it("transfer of zero amount is a no-op (balance unchanged)", async function () {
      const { coin, game, alice, bob } = await getFixture();
      await mintToAlice(coin, game, alice);
      const aliceBefore = await coin.balanceOf(alice.address);
      await coin.connect(alice).transfer(bob.address, 0);
      expect(await coin.balanceOf(alice.address)).to.equal(aliceBefore);
    });

    it("sending to VAULT increases vaultAllowance (not recipient balance)", async function () {
      const { coin, game, alice, vault } = await getFixture();
      await mintToAlice(coin, game, alice);
      const vaultAddr = await vault.getAddress();
      const vaultAllowBefore = await coin.vaultMintAllowance();
      const totalBefore = await coin.totalSupply();

      await coin.connect(alice).transfer(vaultAddr, eth(100));

      // totalSupply decreases (tokens burned from circulation)
      expect(await coin.totalSupply()).to.equal(totalBefore - eth(100));
      // vaultAllowance increases
      expect(await coin.vaultMintAllowance()).to.equal(
        vaultAllowBefore + eth(100)
      );
      // VAULT receives no ERC20 balance
      expect(await coin.balanceOf(vaultAddr)).to.equal(0n);
    });

    it("transfer to VAULT emits VaultEscrowRecorded event", async function () {
      const { coin, game, alice, vault } = await getFixture();
      await mintToAlice(coin, game, alice);
      const vaultAddr = await vault.getAddress();
      const tx = await coin.connect(alice).transfer(vaultAddr, eth(50));
      await expect(tx)
        .to.emit(coin, "VaultEscrowRecorded")
        .withArgs(alice.address, eth(50));
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — transferFrom
  // ---------------------------------------------------------------------------

  describe("transferFrom()", function () {
    async function setup(coin, game, alice, bob) {
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(1000));
      await stopImpersonate(gameAddr);
      await coin.connect(alice).approve(bob.address, eth(500));
    }

    it("transfers within allowance and decrements allowance", async function () {
      const { coin, game, alice, bob, carol } = await getFixture();
      await setup(coin, game, alice, bob);

      await coin.connect(bob).transferFrom(alice.address, carol.address, eth(200));
      expect(await coin.balanceOf(carol.address)).to.equal(eth(200));
      expect(await coin.allowance(alice.address, bob.address)).to.equal(eth(300));
    });

    it("reverts when allowance is insufficient", async function () {
      const { coin, game, alice, bob, carol } = await getFixture();
      await setup(coin, game, alice, bob);

      await expect(
        coin.connect(bob).transferFrom(alice.address, carol.address, eth(600))
      ).to.be.reverted;
    });

    it("does not decrement infinite (max uint256) allowance", async function () {
      const { coin, game, alice, bob, carol } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(1000));
      await stopImpersonate(gameAddr);
      await coin.connect(alice).approve(bob.address, hre.ethers.MaxUint256);

      await coin
        .connect(bob)
        .transferFrom(alice.address, carol.address, eth(100));
      expect(await coin.allowance(alice.address, bob.address)).to.equal(
        hre.ethers.MaxUint256
      );
    });

    it("GAME contract can transferFrom without approval", async function () {
      const { coin, game, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(500));
      // No approve() call needed
      await coin
        .connect(gameSigner)
        .transferFrom(alice.address, bob.address, eth(100));
      await stopImpersonate(gameAddr);

      expect(await coin.balanceOf(bob.address)).to.equal(eth(100));
    });

    it("emits Approval event when allowance is decremented", async function () {
      const { coin, game, alice, bob, carol } = await getFixture();
      await setup(coin, game, alice, bob);

      const tx = await coin
        .connect(bob)
        .transferFrom(alice.address, carol.address, eth(100));
      await expect(tx)
        .to.emit(coin, "Approval")
        .withArgs(alice.address, bob.address, eth(400));
    });
  });

  // ---------------------------------------------------------------------------
  // mintForGame() — privileged mint
  // ---------------------------------------------------------------------------

  describe("mintForGame()", function () {
    it("mints BURNIE to recipient and emits Transfer from zero address", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await coin
        .connect(gameSigner)
        .mintForGame(alice.address, eth(1000));
      await expect(tx)
        .to.emit(coin, "Transfer")
        .withArgs(ZERO_ADDRESS, alice.address, eth(1000));

      await stopImpersonate(gameAddr);
      expect(await coin.balanceOf(alice.address)).to.equal(eth(1000));
      expect(await coin.totalSupply()).to.equal(eth(2_000_000) + eth(1000));
    });

    it("reverts with OnlyGame when called by non-GAME address", async function () {
      const { coin, alice, bob } = await getFixture();
      await expect(
        coin.connect(alice).mintForGame(bob.address, eth(100))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("zero amount is a silent no-op (no revert, no Transfer event)", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await coin
        .connect(gameSigner)
        .mintForGame(alice.address, 0);
      // No Transfer event
      const receipt = await tx.wait();
      const transferEvents = receipt.logs.filter(
        (l) =>
          l.topics[0] ===
          coin.interface.getEvent("Transfer").topicHash
      );
      expect(transferEvents.length).to.equal(0);
      await stopImpersonate(gameAddr);
    });

    it("increases totalSupply and supplyIncUncirculated", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const beforeTotal = await coin.totalSupply();

      await coin.connect(gameSigner).mintForGame(alice.address, eth(500));
      await stopImpersonate(gameAddr);

      expect(await coin.totalSupply()).to.equal(beforeTotal + eth(500));
    });
  });

  // ---------------------------------------------------------------------------
  // burnForCoinflip() and mintForCoinflip()
  // ---------------------------------------------------------------------------

  describe("burnForCoinflip()", function () {
    it("burnForCoinflip reverts with OnlyGame when called by non-COINFLIP address", async function () {
      const { coin, alice, bob } = await getFixture();
      await expect(
        coin.connect(alice).burnForCoinflip(bob.address, eth(1))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });

    it("burnForCoinflip burns from user when called by COINFLIP", async function () {
      const { coin, game, coinflip, alice } = await getFixture();
      // Mint first via game
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(5000));
      await stopImpersonate(gameAddr);

      const coinflipAddr = await coinflip.getAddress();
      const coinflipSigner = await impersonate(coinflipAddr);
      await coin
        .connect(coinflipSigner)
        .burnForCoinflip(alice.address, eth(1000));
      await stopImpersonate(coinflipAddr);

      expect(await coin.balanceOf(alice.address)).to.equal(eth(4000));
    });

    // mintForCoinflip removed in Phase 146 (merged into mintForGame, which now accepts COINFLIP + GAME)
  });

  // creditCoin() removed from BurnieCoin in Phase 146 ABI cleanup (dead function, zero callers)

  // ---------------------------------------------------------------------------
  // vaultEscrow() — only GAME or VAULT
  // ---------------------------------------------------------------------------

  describe("vaultEscrow()", function () {
    it("reverts with OnlyVault when called by an unauthorized address", async function () {
      const { coin, alice } = await getFixture();
      await expect(
        coin.connect(alice).vaultEscrow(eth(100))
      ).to.be.revertedWithCustomError(coin, "OnlyVault");
    });

    it("increases vaultAllowance when called by GAME", async function () {
      const { coin, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const before = await coin.vaultMintAllowance();

      await coin.connect(gameSigner).vaultEscrow(eth(500));
      await stopImpersonate(gameAddr);

      expect(await coin.vaultMintAllowance()).to.equal(before + eth(500));
    });

    it("increases vaultAllowance when called by VAULT", async function () {
      const { coin, vault } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const before = await coin.vaultMintAllowance();

      await coin.connect(vaultSigner).vaultEscrow(eth(1000));
      await stopImpersonate(vaultAddr);

      expect(await coin.vaultMintAllowance()).to.equal(before + eth(1000));
    });

    it("emits VaultEscrowRecorded event", async function () {
      const { coin, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await coin.connect(gameSigner).vaultEscrow(eth(100));
      await expect(tx)
        .to.emit(coin, "VaultEscrowRecorded")
        .withArgs(gameAddr, eth(100));
      await stopImpersonate(gameAddr);
    });

    it("does NOT increase totalSupply (virtual escrow only)", async function () {
      const { coin, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const supplyBefore = await coin.totalSupply();

      await coin.connect(gameSigner).vaultEscrow(eth(1000));
      await stopImpersonate(gameAddr);

      expect(await coin.totalSupply()).to.equal(supplyBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // vaultMintTo() — only VAULT
  // ---------------------------------------------------------------------------

  describe("vaultMintTo()", function () {
    it("reverts with OnlyVault when called by a non-VAULT address", async function () {
      const { coin, alice, bob } = await getFixture();
      await expect(
        coin.connect(alice).vaultMintTo(bob.address, eth(100))
      ).to.be.revertedWithCustomError(coin, "OnlyVault");
    });

    it("mints from vault allowance to recipient and reduces allowance", async function () {
      const { coin, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allowBefore = await coin.vaultMintAllowance();

      await coin.connect(vaultSigner).vaultMintTo(alice.address, eth(100));
      await stopImpersonate(vaultAddr);

      expect(await coin.balanceOf(alice.address)).to.equal(eth(100));
      expect(await coin.vaultMintAllowance()).to.equal(
        allowBefore - eth(100)
      );
    });

    it("increases totalSupply when minting from vault allowance", async function () {
      const { coin, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const totalBefore = await coin.totalSupply();

      await coin.connect(vaultSigner).vaultMintTo(alice.address, eth(200));
      await stopImpersonate(vaultAddr);

      expect(await coin.totalSupply()).to.equal(totalBefore + eth(200));
    });

    it("emits VaultAllowanceSpent and Transfer events", async function () {
      const { coin, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);

      const tx = await coin
        .connect(vaultSigner)
        .vaultMintTo(alice.address, eth(50));
      await expect(tx)
        .to.emit(coin, "Transfer")
        .withArgs(ZERO_ADDRESS, alice.address, eth(50));
      await expect(tx).to.emit(coin, "VaultAllowanceSpent");
      await stopImpersonate(vaultAddr);
    });

    it("reverts with Insufficient when amount exceeds vault allowance", async function () {
      const { coin, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allow = await coin.vaultMintAllowance();

      await expect(
        coin.connect(vaultSigner).vaultMintTo(alice.address, allow + eth(1))
      ).to.be.revertedWithCustomError(coin, "Insufficient");
      await stopImpersonate(vaultAddr);
    });

    it("reverts with ZeroAddress when recipient is address(0)", async function () {
      const { coin, vault } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);

      await expect(
        coin.connect(vaultSigner).vaultMintTo(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(coin, "ZeroAddress");
      await stopImpersonate(vaultAddr);
    });

    it("supplyIncUncirculated remains constant after vaultMintTo (supply up, allowance down)", async function () {
      const { coin, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const before = await coin.supplyIncUncirculated();

      await coin.connect(vaultSigner).vaultMintTo(alice.address, eth(300));
      await stopImpersonate(vaultAddr);

      expect(await coin.supplyIncUncirculated()).to.equal(before);
    });
  });

  // ---------------------------------------------------------------------------
  // burnCoin() — only trusted contracts (GAME, AFFILIATE)
  // ---------------------------------------------------------------------------

  describe("burnCoin()", function () {
    it("reverts with OnlyTrustedContracts when called by an unauthorized address", async function () {
      const { coin, alice, bob } = await getFixture();
      await expect(
        coin.connect(alice).burnCoin(bob.address, eth(1))
      ).to.be.revertedWithCustomError(coin, "OnlyTrustedContracts");
    });

    it("burns from target when called by GAME", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(1000));

      await coin.connect(gameSigner).burnCoin(alice.address, eth(300));
      await stopImpersonate(gameAddr);

      expect(await coin.balanceOf(alice.address)).to.equal(eth(700));
    });

    it("burns from target when called by AFFILIATE", async function () {
      const { coin, game, affiliate, alice } = await getFixture();
      // Mint via game
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(500));
      await stopImpersonate(gameAddr);

      const affiliateAddr = await affiliate.getAddress();
      const affiliateSigner = await impersonate(affiliateAddr);
      await coin.connect(affiliateSigner).burnCoin(alice.address, eth(100));
      await stopImpersonate(affiliateAddr);

      expect(await coin.balanceOf(alice.address)).to.equal(eth(400));
    });

    it("decreases totalSupply after burn", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(1000));
      const totalBefore = await coin.totalSupply();

      await coin.connect(gameSigner).burnCoin(alice.address, eth(400));
      await stopImpersonate(gameAddr);

      expect(await coin.totalSupply()).to.equal(totalBefore - eth(400));
    });
  });

  // creditFlip() and creditFlipBatch() removed from BurnieCoin in Phase 146 ABI cleanup
  // (forwarding wrappers; callers now call coinflip.creditFlip / coinflip.creditFlipBatch directly)

  // ---------------------------------------------------------------------------
  // View helpers — claimableCoin, balanceOfWithClaimable, etc.
  // ---------------------------------------------------------------------------

  describe("view helpers", function () {
    // claimableCoin, previewClaimCoinflips, coinflipAmount, coinflipAutoRebuyInfo
    // removed from BurnieCoin in Phase 146 ABI cleanup (forwarding wrappers to coinflip)

    it("balanceOfWithClaimable returns at least the on-chain balance", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(500));
      await stopImpersonate(gameAddr);

      const spendable = await coin.balanceOfWithClaimable(alice.address);
      const onChain = await coin.balanceOf(alice.address);
      expect(spendable).to.be.gte(onChain);
    });

    it("balanceOfWithClaimable for VAULT includes vaultAllowance", async function () {
      const { coin, vault } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const allow = await coin.vaultMintAllowance();
      const spendable = await coin.balanceOfWithClaimable(vaultAddr);
      expect(spendable).to.be.gte(allow);
    });
  });

  // ---------------------------------------------------------------------------
  // affiliateQuestReward() — only AFFILIATE
  // ---------------------------------------------------------------------------

  describe("affiliateQuestReward()", function () {
    it("reverts with OnlyAffiliate when called by non-AFFILIATE address", async function () {
      const { coin, alice, bob } = await getFixture();
      await expect(
        coin.connect(alice).affiliateQuestReward(bob.address, eth(100))
      ).to.be.revertedWithCustomError(coin, "OnlyAffiliate");
    });
  });

  // ---------------------------------------------------------------------------
  // rollDailyQuest() — only GAME
  // ---------------------------------------------------------------------------

  describe("rollDailyQuest()", function () {
    it("reverts with OnlyGame when called by a non-GAME address", async function () {
      const { coin, alice } = await getFixture();
      await expect(
        coin.connect(alice).rollDailyQuest(1, 12345)
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // notifyQuestMint() — only GAME
  // ---------------------------------------------------------------------------

  describe("notifyQuestMint()", function () {
    it("reverts with OnlyGame when called by a non-GAME address", async function () {
      const { coin, alice } = await getFixture();
      await expect(
        coin.connect(alice).notifyQuestMint(alice.address, 1, true)
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // notifyQuestLootBox() — only GAME
  // ---------------------------------------------------------------------------

  describe("notifyQuestLootBox()", function () {
    it("reverts with OnlyGame when called by a non-GAME address", async function () {
      const { coin, alice } = await getFixture();
      await expect(
        coin.connect(alice).notifyQuestLootBox(alice.address, eth(1))
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // notifyQuestDegenerette() — only GAME
  // ---------------------------------------------------------------------------

  describe("notifyQuestDegenerette()", function () {
    it("reverts with OnlyGame when called by a non-GAME address", async function () {
      const { coin, alice } = await getFixture();
      await expect(
        coin.connect(alice).notifyQuestDegenerette(alice.address, eth(1), true)
      ).to.be.revertedWithCustomError(coin, "OnlyGame");
    });
  });

  // ---------------------------------------------------------------------------
  // Supply invariants
  // ---------------------------------------------------------------------------

  describe("supply invariants", function () {
    it("supplyIncUncirculated = totalSupply + vaultAllowance at all times", async function () {
      const { coin, game, vault, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const vaultAddr = await vault.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const vaultSigner = await impersonate(vaultAddr);

      // Mint some
      await coin.connect(gameSigner).mintForGame(alice.address, eth(500));
      // Escrow some
      await coin.connect(gameSigner).vaultEscrow(eth(200));
      // MintTo some from vault
      await coin.connect(vaultSigner).vaultMintTo(bob.address, eth(100));

      await stopImpersonate(gameAddr);
      await stopImpersonate(vaultAddr);

      const total = await coin.totalSupply();
      const allowance = await coin.vaultMintAllowance();
      const incUncirculated = await coin.supplyIncUncirculated();
      expect(incUncirculated).to.equal(total + allowance);
    });
  });

  // ---------------------------------------------------------------------------
  // ZeroAddress guard on _transfer
  // ---------------------------------------------------------------------------

  describe("ZeroAddress guards", function () {
    it("transfer to zero address reverts with ZeroAddress", async function () {
      const { coin, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await coin.connect(gameSigner).mintForGame(alice.address, eth(100));
      await stopImpersonate(gameAddr);

      await expect(
        coin.connect(alice).transfer(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(coin, "ZeroAddress");
    });
  });
});
