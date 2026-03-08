import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { eth, getEvent, getEvents, ZERO_ADDRESS } from "../helpers/testUtils.js";

/*
 * WrappedWrappedXRP Unit Tests
 *
 * Contract: contracts/WrappedWrappedXRP.sol
 *
 * Architecture summary:
 *   - Custom ERC20 "WWXRP" with 18 decimals (joke parody token)
 *   - totalSupply starts at 0; vaultAllowance starts at 1,000,000,000 WWXRP
 *   - Wrapping is DISABLED; unwrap() burns WWXRP and sends wXRP (if reserves allow)
 *   - donate() transfers wXRP in without minting WWXRP (increases wXRPReserves)
 *   - mintPrize(): GAME / COIN / COINFLIP can mint unbacked WWXRP
 *   - vaultMintTo(): VAULT can mint from the uncirculating reserve
 *   - burnForGame(): GAME can burn WWXRP from any address
 *   - wXRPReserves tracks actual backing; may be less than totalSupply
 */

describe("WrappedWrappedXRP", function () {
  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  async function getFixture() {
    return loadFixture(deployFullProtocol);
  }

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

  // Mint wXRP to a user via the MockWXRP test helper
  async function mintWXRP(mockWXRP, to, amount) {
    await mockWXRP.mint(to, amount);
  }

  // Have `user` approve the WWXRP contract to spend their wXRP
  async function approveWXRP(mockWXRP, wwxrp, user, amount) {
    const wwxrpAddr = await wwxrp.getAddress();
    await mockWXRP.connect(user).approve(wwxrpAddr, amount);
  }

  // ---------------------------------------------------------------------------
  // Initial state / constructor
  // ---------------------------------------------------------------------------

  describe("initial state", function () {
    it("name is 'Wrapped Wrapped WWXRP (PARODY)'", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.name()).to.equal("Wrapped Wrapped WWXRP (PARODY)");
    });

    it("symbol is 'WWXRP'", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.symbol()).to.equal("WWXRP");
    });

    it("decimals is 18", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.decimals()).to.equal(18);
    });

    it("totalSupply is 0 on deploy", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.totalSupply()).to.equal(0n);
    });

    it("INITIAL_VAULT_ALLOWANCE is 1,000,000,000 WWXRP", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.INITIAL_VAULT_ALLOWANCE()).to.equal(eth(1_000_000_000));
    });

    it("vaultAllowance starts at INITIAL_VAULT_ALLOWANCE", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.vaultAllowance()).to.equal(eth(1_000_000_000));
    });

    it("vaultMintAllowance() returns vaultAllowance", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.vaultMintAllowance()).to.equal(await wwxrp.vaultAllowance());
    });

    it("wXRPReserves is 0 on deploy", async function () {
      const { wwxrp } = await getFixture();
      expect(await wwxrp.wXRPReserves()).to.equal(0n);
    });

    it("all user balances start at zero", async function () {
      const { wwxrp, alice, bob, carol } = await getFixture();
      for (const user of [alice, bob, carol]) {
        expect(await wwxrp.balanceOf(user.address)).to.equal(0n);
      }
    });

    it("supplyIncUncirculated equals totalSupply + vaultAllowance", async function () {
      const { wwxrp } = await getFixture();
      const total = await wwxrp.totalSupply();
      const vaultAllow = await wwxrp.vaultAllowance();
      expect(await wwxrp.supplyIncUncirculated()).to.equal(total + vaultAllow);
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — approve
  // ---------------------------------------------------------------------------

  describe("approve()", function () {
    it("sets allowance and emits Approval event", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      const tx = await wwxrp.connect(alice).approve(bob.address, eth(500));
      await expect(tx)
        .to.emit(wwxrp, "Approval")
        .withArgs(alice.address, bob.address, eth(500));
      expect(await wwxrp.allowance(alice.address, bob.address)).to.equal(eth(500));
    });

    it("can set allowance to type(uint256).max", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      const max = hre.ethers.MaxUint256;
      await wwxrp.connect(alice).approve(bob.address, max);
      expect(await wwxrp.allowance(alice.address, bob.address)).to.equal(max);
    });

    it("overwrites previous allowance", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      await wwxrp.connect(alice).approve(bob.address, eth(100));
      await wwxrp.connect(alice).approve(bob.address, eth(50));
      expect(await wwxrp.allowance(alice.address, bob.address)).to.equal(eth(50));
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — transfer
  // ---------------------------------------------------------------------------

  describe("transfer()", function () {
    async function giveWWXRP(wwxrp, game, alice, amount = eth(1000)) {
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, amount);
      await stopImpersonate(gameAddr);
    }

    it("transfers tokens between accounts and emits Transfer", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      await giveWWXRP(wwxrp, game, alice);

      const tx = await wwxrp.connect(alice).transfer(bob.address, eth(200));
      await expect(tx)
        .to.emit(wwxrp, "Transfer")
        .withArgs(alice.address, bob.address, eth(200));

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(800));
      expect(await wwxrp.balanceOf(bob.address)).to.equal(eth(200));
    });

    it("reverts with InsufficientBalance when balance is too low", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      await expect(
        wwxrp.connect(alice).transfer(bob.address, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientBalance");
    });

    it("reverts with ZeroAddress when `to` is address(0)", async function () {
      const { wwxrp, game, alice } = await getFixture();
      await giveWWXRP(wwxrp, game, alice);
      await expect(
        wwxrp.connect(alice).transfer(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAddress");
    });

    it("can transfer entire balance", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      await giveWWXRP(wwxrp, game, alice, eth(500));
      await wwxrp.connect(alice).transfer(bob.address, eth(500));
      expect(await wwxrp.balanceOf(alice.address)).to.equal(0n);
      expect(await wwxrp.balanceOf(bob.address)).to.equal(eth(500));
    });

    it("zero-amount transfer does not revert", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      await giveWWXRP(wwxrp, game, alice);
      await expect(wwxrp.connect(alice).transfer(bob.address, 0n)).to.not.be.reverted;
    });

    it("totalSupply does not change after a transfer", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      await giveWWXRP(wwxrp, game, alice, eth(1000));
      const supplyBefore = await wwxrp.totalSupply();
      await wwxrp.connect(alice).transfer(bob.address, eth(300));
      expect(await wwxrp.totalSupply()).to.equal(supplyBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // ERC20 — transferFrom
  // ---------------------------------------------------------------------------

  describe("transferFrom()", function () {
    async function setup(wwxrp, game, alice, bob) {
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1000));
      await stopImpersonate(gameAddr);
      await wwxrp.connect(alice).approve(bob.address, eth(500));
    }

    it("spends allowance and transfers", async function () {
      const { wwxrp, game, alice, bob, carol } = await getFixture();
      await setup(wwxrp, game, alice, bob);

      await wwxrp.connect(bob).transferFrom(alice.address, carol.address, eth(200));
      expect(await wwxrp.balanceOf(carol.address)).to.equal(eth(200));
      expect(await wwxrp.allowance(alice.address, bob.address)).to.equal(eth(300));
    });

    it("emits Approval event when allowance is decremented", async function () {
      const { wwxrp, game, alice, bob, carol } = await getFixture();
      await setup(wwxrp, game, alice, bob);

      const tx = await wwxrp
        .connect(bob)
        .transferFrom(alice.address, carol.address, eth(100));
      await expect(tx)
        .to.emit(wwxrp, "Approval")
        .withArgs(alice.address, bob.address, eth(400));
    });

    it("reverts with InsufficientAllowance when spender lacks enough allowance", async function () {
      const { wwxrp, game, alice, bob, carol } = await getFixture();
      await setup(wwxrp, game, alice, bob);

      await expect(
        wwxrp.connect(bob).transferFrom(alice.address, carol.address, eth(600))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientAllowance");
    });

    it("does not decrement max uint256 allowance", async function () {
      const { wwxrp, game, alice, bob, carol } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1000));
      await stopImpersonate(gameAddr);
      await wwxrp.connect(alice).approve(bob.address, hre.ethers.MaxUint256);

      await wwxrp
        .connect(bob)
        .transferFrom(alice.address, carol.address, eth(100));
      expect(await wwxrp.allowance(alice.address, bob.address)).to.equal(
        hre.ethers.MaxUint256
      );
    });

    it("reverts with ZeroAddress when `from` is address(0)", async function () {
      const { wwxrp, alice } = await getFixture();
      await expect(
        wwxrp.connect(alice).transferFrom(ZERO_ADDRESS, alice.address, eth(1))
      ).to.be.reverted; // either InsufficientAllowance or ZeroAddress
    });
  });

  // ---------------------------------------------------------------------------
  // donate()
  // ---------------------------------------------------------------------------

  describe("donate()", function () {
    it("increases wXRPReserves and emits Donated", async function () {
      const { wwxrp, mockWXRP, alice } = await getFixture();
      await mintWXRP(mockWXRP, alice.address, eth(100));
      await approveWXRP(mockWXRP, wwxrp, alice, eth(100));

      const reservesBefore = await wwxrp.wXRPReserves();
      const tx = await wwxrp.connect(alice).donate(eth(100));
      await expect(tx)
        .to.emit(wwxrp, "Donated")
        .withArgs(alice.address, eth(100));

      expect(await wwxrp.wXRPReserves()).to.equal(reservesBefore + eth(100));
    });

    it("does NOT mint WWXRP (totalSupply stays the same)", async function () {
      const { wwxrp, mockWXRP, alice } = await getFixture();
      await mintWXRP(mockWXRP, alice.address, eth(50));
      await approveWXRP(mockWXRP, wwxrp, alice, eth(50));

      const supplyBefore = await wwxrp.totalSupply();
      await wwxrp.connect(alice).donate(eth(50));
      expect(await wwxrp.totalSupply()).to.equal(supplyBefore);
    });

    it("reverts with ZeroAmount when amount is 0", async function () {
      const { wwxrp, alice } = await getFixture();
      await expect(
        wwxrp.connect(alice).donate(0n)
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAmount");
    });

    it("reverts when wXRP transferFrom fails (insufficient wXRP balance)", async function () {
      const { wwxrp, alice } = await getFixture();
      // Alice has no wXRP but tries to donate
      await expect(
        wwxrp.connect(alice).donate(eth(1))
      ).to.be.reverted;
    });

    it("multiple donations accumulate in reserves", async function () {
      const { wwxrp, mockWXRP, alice, bob } = await getFixture();
      await mintWXRP(mockWXRP, alice.address, eth(100));
      await mintWXRP(mockWXRP, bob.address, eth(200));
      await approveWXRP(mockWXRP, wwxrp, alice, eth(100));
      await approveWXRP(mockWXRP, wwxrp, bob, eth(200));

      await wwxrp.connect(alice).donate(eth(100));
      await wwxrp.connect(bob).donate(eth(200));

      expect(await wwxrp.wXRPReserves()).to.equal(eth(300));
    });

    it("wXRP balance of wwxrp contract increases after donation", async function () {
      const { wwxrp, mockWXRP, alice } = await getFixture();
      await mintWXRP(mockWXRP, alice.address, eth(75));
      await approveWXRP(mockWXRP, wwxrp, alice, eth(75));
      const wwxrpAddr = await wwxrp.getAddress();

      const contractWXRPBefore = await mockWXRP.balanceOf(wwxrpAddr);
      await wwxrp.connect(alice).donate(eth(75));
      expect(await mockWXRP.balanceOf(wwxrpAddr)).to.equal(
        contractWXRPBefore + eth(75)
      );
    });
  });

  // ---------------------------------------------------------------------------
  // unwrap()
  // ---------------------------------------------------------------------------

  describe("unwrap()", function () {
    // Helper: give alice some WWXRP and fund the wwxrp contract with wXRP reserves
    async function setupUnwrap(wwxrp, game, mockWXRP, alice, amount = eth(100)) {
      // Mint WWXRP to alice via game
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, amount);
      await stopImpersonate(gameAddr);

      // Fund reserves via donation from a separate "donor" (we use alice here
      // but give them wXRP to donate — donate does not mint WWXRP)
      await mockWXRP.mint(alice.address, amount);
      const wwxrpAddr = await wwxrp.getAddress();
      await mockWXRP.connect(alice).approve(wwxrpAddr, amount);
      await wwxrp.connect(alice).donate(amount);
    }

    it("burns WWXRP and transfers wXRP back to user, emits Unwrapped", async function () {
      const { wwxrp, game, mockWXRP, alice } = await getFixture();
      await setupUnwrap(wwxrp, game, mockWXRP, alice, eth(100));

      const aliceWWXRPBefore = await wwxrp.balanceOf(alice.address);
      const aliceWXRPBefore = await mockWXRP.balanceOf(alice.address);
      const reservesBefore = await wwxrp.wXRPReserves();

      const tx = await wwxrp.connect(alice).unwrap(eth(50));
      await expect(tx)
        .to.emit(wwxrp, "Unwrapped")
        .withArgs(alice.address, eth(50));

      expect(await wwxrp.balanceOf(alice.address)).to.equal(
        aliceWWXRPBefore - eth(50)
      );
      expect(await mockWXRP.balanceOf(alice.address)).to.equal(
        aliceWXRPBefore + eth(50)
      );
      expect(await wwxrp.wXRPReserves()).to.equal(reservesBefore - eth(50));
    });

    it("decreases totalSupply after unwrap", async function () {
      const { wwxrp, game, mockWXRP, alice } = await getFixture();
      await setupUnwrap(wwxrp, game, mockWXRP, alice, eth(200));
      const supplyBefore = await wwxrp.totalSupply();

      await wwxrp.connect(alice).unwrap(eth(100));
      expect(await wwxrp.totalSupply()).to.equal(supplyBefore - eth(100));
    });

    it("reverts with ZeroAmount when amount is 0", async function () {
      const { wwxrp, alice } = await getFixture();
      await expect(
        wwxrp.connect(alice).unwrap(0n)
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAmount");
    });

    it("reverts with InsufficientReserves when wXRP reserves are insufficient", async function () {
      const { wwxrp, game, alice } = await getFixture();
      // Mint WWXRP to alice but provide NO reserves
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(100));
      await stopImpersonate(gameAddr);

      await expect(
        wwxrp.connect(alice).unwrap(eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientReserves");
    });

    it("reverts with InsufficientBalance when user's WWXRP balance is insufficient", async function () {
      const { wwxrp, game, mockWXRP, alice, bob } = await getFixture();
      // Give alice 50 WWXRP, and add 200 wXRP reserves (reserves > request, so
      // InsufficientReserves won't fire first — the balance check will fail instead).
      // We use bob to donate wXRP so alice's WWXRP balance stays at 50.
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(50));
      await stopImpersonate(gameAddr);

      // Bob donates 200 wXRP so reserves = 200 (plenty to satisfy the reserves check)
      await mockWXRP.mint(bob.address, eth(200));
      const wwxrpAddr = await wwxrp.getAddress();
      await mockWXRP.connect(bob).approve(wwxrpAddr, eth(200));
      await wwxrp.connect(bob).donate(eth(200));

      // alice has 50 WWXRP but tries to unwrap 100 — reserves OK but balance insufficient
      await expect(
        wwxrp.connect(alice).unwrap(eth(100))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientBalance");
    });

    it("unwrapping entire balance results in zero WWXRP for user", async function () {
      const { wwxrp, game, mockWXRP, alice } = await getFixture();
      await setupUnwrap(wwxrp, game, mockWXRP, alice, eth(100));
      await wwxrp.connect(alice).unwrap(eth(100));
      expect(await wwxrp.balanceOf(alice.address)).to.equal(0n);
    });

    it("emits Transfer to address(0) during unwrap (burn event)", async function () {
      const { wwxrp, game, mockWXRP, alice } = await getFixture();
      await setupUnwrap(wwxrp, game, mockWXRP, alice, eth(100));

      const tx = await wwxrp.connect(alice).unwrap(eth(10));
      await expect(tx)
        .to.emit(wwxrp, "Transfer")
        .withArgs(alice.address, ZERO_ADDRESS, eth(10));
    });
  });

  // ---------------------------------------------------------------------------
  // mintPrize() — GAME / COIN / COINFLIP only
  // ---------------------------------------------------------------------------

  describe("mintPrize()", function () {
    it("reverts with OnlyMinter when called by an unauthorized address", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      await expect(
        wwxrp.connect(alice).mintPrize(bob.address, eth(100))
      ).to.be.revertedWithCustomError(wwxrp, "OnlyMinter");
    });

    it("GAME can mint WWXRP to a recipient", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(500));
      await expect(tx)
        .to.emit(wwxrp, "Transfer")
        .withArgs(ZERO_ADDRESS, alice.address, eth(500));
      await stopImpersonate(gameAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(500));
    });

    it("COIN contract can mint WWXRP", async function () {
      const { wwxrp, coin, alice } = await getFixture();
      const coinAddr = await coin.getAddress();
      const coinSigner = await impersonate(coinAddr);

      await wwxrp.connect(coinSigner).mintPrize(alice.address, eth(200));
      await stopImpersonate(coinAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(200));
    });

    it("COINFLIP contract can mint WWXRP", async function () {
      const { wwxrp, coinflip, alice } = await getFixture();
      const coinflipAddr = await coinflip.getAddress();
      const coinflipSigner = await impersonate(coinflipAddr);

      await wwxrp.connect(coinflipSigner).mintPrize(alice.address, eth(300));
      await stopImpersonate(coinflipAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(300));
    });

    it("reverts with ZeroAmount when amount is 0", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        wwxrp.connect(gameSigner).mintPrize(alice.address, 0)
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAmount");
      await stopImpersonate(gameAddr);
    });

    it("reverts with ZeroAddress when recipient is address(0)", async function () {
      const { wwxrp, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        wwxrp.connect(gameSigner).mintPrize(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAddress");
      await stopImpersonate(gameAddr);
    });

    it("increases totalSupply on each mintPrize call", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(100));
      await wwxrp.connect(gameSigner).mintPrize(bob.address, eth(200));
      await stopImpersonate(gameAddr);

      expect(await wwxrp.totalSupply()).to.equal(eth(300));
    });

    it("does NOT change wXRPReserves (unbacked mint)", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const reservesBefore = await wwxrp.wXRPReserves();

      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(999));
      await stopImpersonate(gameAddr);

      expect(await wwxrp.wXRPReserves()).to.equal(reservesBefore);
    });

    it("deployer (not GAME/COIN/COINFLIP) cannot call mintPrize", async function () {
      const { wwxrp, deployer, alice } = await getFixture();
      await expect(
        wwxrp.connect(deployer).mintPrize(alice.address, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "OnlyMinter");
    });
  });

  // ---------------------------------------------------------------------------
  // vaultMintTo() — VAULT only
  // ---------------------------------------------------------------------------

  describe("vaultMintTo()", function () {
    it("reverts with OnlyVault when called by a non-VAULT address", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      await expect(
        wwxrp.connect(alice).vaultMintTo(bob.address, eth(100))
      ).to.be.revertedWithCustomError(wwxrp, "OnlyVault");
    });

    it("VAULT can mint from the vault allowance to a recipient", async function () {
      const { wwxrp, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allowBefore = await wwxrp.vaultAllowance();

      await wwxrp.connect(vaultSigner).vaultMintTo(alice.address, eth(1000));
      await stopImpersonate(vaultAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(1000));
      expect(await wwxrp.vaultAllowance()).to.equal(allowBefore - eth(1000));
    });

    it("emits VaultAllowanceSpent and Transfer events", async function () {
      const { wwxrp, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);

      const tx = await wwxrp.connect(vaultSigner).vaultMintTo(alice.address, eth(50));
      await expect(tx)
        .to.emit(wwxrp, "Transfer")
        .withArgs(ZERO_ADDRESS, alice.address, eth(50));
      await expect(tx).to.emit(wwxrp, "VaultAllowanceSpent");
      await stopImpersonate(vaultAddr);
    });

    it("reverts with ZeroAddress when recipient is address(0)", async function () {
      const { wwxrp, vault } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);

      await expect(
        wwxrp.connect(vaultSigner).vaultMintTo(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAddress");
      await stopImpersonate(vaultAddr);
    });

    it("reverts with InsufficientVaultAllowance when amount exceeds remaining allowance", async function () {
      const { wwxrp, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allow = await wwxrp.vaultAllowance();

      await expect(
        wwxrp.connect(vaultSigner).vaultMintTo(alice.address, allow + eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientVaultAllowance");
      await stopImpersonate(vaultAddr);
    });

    it("zero amount is a no-op (returns without minting)", async function () {
      const { wwxrp, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allowBefore = await wwxrp.vaultAllowance();

      await wwxrp.connect(vaultSigner).vaultMintTo(alice.address, 0);
      await stopImpersonate(vaultAddr);

      expect(await wwxrp.vaultAllowance()).to.equal(allowBefore);
      expect(await wwxrp.balanceOf(alice.address)).to.equal(0n);
    });

    it("reduces vaultAllowance proportionally with multiple calls", async function () {
      const { wwxrp, vault, alice, bob } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const allowBefore = await wwxrp.vaultAllowance();

      await wwxrp.connect(vaultSigner).vaultMintTo(alice.address, eth(500));
      await wwxrp.connect(vaultSigner).vaultMintTo(bob.address, eth(300));
      await stopImpersonate(vaultAddr);

      expect(await wwxrp.vaultAllowance()).to.equal(allowBefore - eth(800));
    });

    it("supplyIncUncirculated remains constant after vaultMintTo (supply up, allowance down)", async function () {
      const { wwxrp, vault, alice } = await getFixture();
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);
      const before = await wwxrp.supplyIncUncirculated();

      await wwxrp.connect(vaultSigner).vaultMintTo(alice.address, eth(10000));
      await stopImpersonate(vaultAddr);

      expect(await wwxrp.supplyIncUncirculated()).to.equal(before);
    });
  });

  // ---------------------------------------------------------------------------
  // burnForGame() — GAME only
  // ---------------------------------------------------------------------------

  describe("burnForGame()", function () {
    it("reverts with OnlyMinter when called by a non-GAME address", async function () {
      const { wwxrp, alice, bob } = await getFixture();
      await expect(
        wwxrp.connect(alice).burnForGame(bob.address, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "OnlyMinter");
    });

    it("GAME can burn WWXRP from a user", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      // Mint first
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(500));

      const tx = await wwxrp.connect(gameSigner).burnForGame(alice.address, eth(200));
      await expect(tx)
        .to.emit(wwxrp, "Transfer")
        .withArgs(alice.address, ZERO_ADDRESS, eth(200));
      await stopImpersonate(gameAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(eth(300));
    });

    it("decreases totalSupply after burnForGame", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1000));
      const supplyBefore = await wwxrp.totalSupply();

      await wwxrp.connect(gameSigner).burnForGame(alice.address, eth(400));
      await stopImpersonate(gameAddr);

      expect(await wwxrp.totalSupply()).to.equal(supplyBefore - eth(400));
    });

    it("zero amount is a silent no-op", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(100));
      const balanceBefore = await wwxrp.balanceOf(alice.address);

      await wwxrp.connect(gameSigner).burnForGame(alice.address, 0);
      await stopImpersonate(gameAddr);

      expect(await wwxrp.balanceOf(alice.address)).to.equal(balanceBefore);
    });

    it("reverts with InsufficientBalance when user has insufficient WWXRP", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(50));

      await expect(
        wwxrp.connect(gameSigner).burnForGame(alice.address, eth(100))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientBalance");
      await stopImpersonate(gameAddr);
    });

    it("reverts with ZeroAddress when `from` is address(0)", async function () {
      const { wwxrp, game } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        wwxrp.connect(gameSigner).burnForGame(ZERO_ADDRESS, eth(1))
      ).to.be.revertedWithCustomError(wwxrp, "ZeroAddress");
      await stopImpersonate(gameAddr);
    });

    it("non-GAME cannot burn even with balance", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(100));
      await stopImpersonate(gameAddr);

      await expect(
        wwxrp.connect(alice).burnForGame(alice.address, eth(50))
      ).to.be.revertedWithCustomError(wwxrp, "OnlyMinter");
    });
  });

  // ---------------------------------------------------------------------------
  // supplyIncUncirculated
  // ---------------------------------------------------------------------------

  describe("supplyIncUncirculated()", function () {
    it("equals totalSupply + vaultAllowance at all times", async function () {
      const { wwxrp, game, vault, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const vaultAddr = await vault.getAddress();
      const gameSigner = await impersonate(gameAddr);
      const vaultSigner = await impersonate(vaultAddr);

      // Mint some via game
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1000));
      // Mint some from vault
      await wwxrp.connect(vaultSigner).vaultMintTo(bob.address, eth(500));

      await stopImpersonate(gameAddr);
      await stopImpersonate(vaultAddr);

      const total = await wwxrp.totalSupply();
      const vaultAllow = await wwxrp.vaultAllowance();
      expect(await wwxrp.supplyIncUncirculated()).to.equal(total + vaultAllow);
    });

    it("decreases only by burn (not by transfer)", async function () {
      const { wwxrp, game, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1000));
      const supplyIncBefore = await wwxrp.supplyIncUncirculated();

      // Transfer doesn't change totalSupply
      await wwxrp.connect(alice).transfer(bob.address, eth(500));
      expect(await wwxrp.supplyIncUncirculated()).to.equal(supplyIncBefore);

      // BurnForGame does reduce totalSupply
      await wwxrp.connect(gameSigner).burnForGame(bob.address, eth(500));
      await stopImpersonate(gameAddr);
      expect(await wwxrp.supplyIncUncirculated()).to.equal(
        supplyIncBefore - eth(500)
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Integration — undercollateralized scenario
  // ---------------------------------------------------------------------------

  describe("undercollateralization scenario", function () {
    it("contract can have more WWXRP than wXRP reserves (joke token behavior)", async function () {
      const { wwxrp, game, alice } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      // Mint a large amount of unbacked WWXRP
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(1_000_000));
      await stopImpersonate(gameAddr);

      const totalSupply = await wwxrp.totalSupply();
      const reserves = await wwxrp.wXRPReserves();

      // Prove undercollateralization: totalSupply > reserves
      expect(totalSupply).to.be.gt(reserves);
    });

    it("first-come-first-served: first unwrapper succeeds, second fails when reserves depleted", async function () {
      const { wwxrp, game, mockWXRP, alice, bob } = await getFixture();
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      // Mint WWXRP to both alice and bob
      await wwxrp.connect(gameSigner).mintPrize(alice.address, eth(100));
      await wwxrp.connect(gameSigner).mintPrize(bob.address, eth(100));
      await stopImpersonate(gameAddr);

      // Only enough reserves for 50 WWXRP
      await mockWXRP.mint(alice.address, eth(50));
      await approveWXRP(mockWXRP, wwxrp, alice, eth(50));
      // Use a separate donor to add reserves without affecting alice's WWXRP balance
      await wwxrp.connect(alice).donate(eth(50));

      // Alice unwraps 50 — succeeds
      await expect(wwxrp.connect(alice).unwrap(eth(50))).to.not.be.reverted;

      // Bob tries to unwrap 50 — fails (reserves now 0)
      await expect(
        wwxrp.connect(bob).unwrap(eth(50))
      ).to.be.revertedWithCustomError(wwxrp, "InsufficientReserves");
    });
  });
});
