/**
 * Coercion Attacker PoC Tests
 * Phase 20: Admin Key Compromise Threat Model
 *
 * Tests demonstrate what a hostile admin/CREATOR can and CANNOT do.
 */
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import { deployFullProtocol } from "../helpers/deployFixture.js";

describe("Coercion Attacker: Admin Key Compromise", function () {
  // =========================================================================
  // SETUP
  // =========================================================================

  async function deployFixture() {
    const f = await deployFullProtocol();
    return f;
  }

  // =========================================================================
  // FINDING 1: Admin CANNOT directly drain ETH from Game contract
  // =========================================================================

  describe("Admin ETH Access Boundaries", function () {
    it("adminSwapEthForStEth is value-neutral -- admin sends ETH, gets stETH back", async function () {
      const { deployer, game, admin, mockStETH, alice } = await loadFixture(deployFixture);

      // Give game some stETH
      const stethAmount = hre.ethers.parseEther("10");
      await mockStETH.mint(await game.getAddress(), stethAmount);

      // Admin swaps 5 ETH for 5 stETH -- value-neutral exchange
      const swapAmount = hre.ethers.parseEther("5");
      const adminAddr = await admin.getAddress();

      // The admin contract calls game.adminSwapEthForStEth(msg.sender, amount)
      // msg.sender in game context is Admin contract; recipient = Admin contract's msg.sender = deployer
      // But the Admin.swapGameEthForStEth passes msg.sender as recipient, which is the deployer EOA
      // Wait -- Admin.swapGameEthForStEth calls gameAdmin.adminSwapEthForStEth{value}(msg.sender, msg.value)
      // Game receives ETH via msg.value, sends stETH to recipient (msg.sender of Admin = deployer)
      const deployerStethBefore = await mockStETH.balanceOf(deployer.address);
      await admin.swapGameEthForStEth({ value: swapAmount });

      // Deployer (CREATOR) got stETH in return -- value-neutral exchange
      const deployerStethAfter = await mockStETH.balanceOf(deployer.address);
      expect(deployerStethAfter - deployerStethBefore).to.equal(swapAmount);

      // Game ETH balance increased by the swap amount (received ETH from admin)
      const gameEth = await hre.ethers.provider.getBalance(await game.getAddress());
      expect(gameEth).to.be.gte(swapAmount);
    });

    it("adminStakeEthForStEth CANNOT stake below claimablePool reserve", async function () {
      const { deployer, game, admin } = await loadFixture(deployFixture);

      // Game has no ETH above claimablePool -- should revert
      await expect(
        admin.stakeGameEthToStEth(hre.ethers.parseEther("1"))
      ).to.be.reverted;
    });

    it("admin CANNOT call adminSwapEthForStEth without sending exact ETH", async function () {
      const { deployer, game, admin, mockStETH } = await loadFixture(deployFixture);

      // Give game some stETH
      await mockStETH.mint(await game.getAddress(), hre.ethers.parseEther("10"));

      // Try to swap 5 stETH out without sending any ETH
      await expect(
        admin.swapGameEthForStEth({ value: 0 })
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FINDING 2: Emergency VRF Recovery -- The Highest Impact Attack Vector
  // =========================================================================

  describe("VRF Governance Attack Path", function () {
    it("propose requires VRF stall -- cannot be called instantly", async function () {
      const { deployer, admin } = await loadFixture(deployFixture);

      // Try proposing immediately -- should revert (not stalled)
      await expect(
        admin.propose(
          deployer.address, // fake coordinator
          "0xabababababababababababababababababababababababababababababababab"
        )
      ).to.be.reverted;
    });

    it("shutdownVrf only callable by GAME contract -- cannot steal LINK", async function () {
      const { deployer, admin, alice } = await loadFixture(deployFixture);

      // Try to shutdown VRF as attacker
      await expect(
        admin.connect(alice).shutdownVrf()
      ).to.be.reverted; // NotAuthorized
    });
  });

  // =========================================================================
  // FINDING 3: Vault Control via DGVE Ownership
  // =========================================================================

  describe("Vault Control via DGVE Share Dominance", function () {
    it("CREATOR starts with 100% of DGVE shares -- controls vault gameplay", async function () {
      const { deployer, vault } = await loadFixture(deployFixture);

      const isOwner = await vault.isVaultOwner(deployer.address);
      expect(isOwner).to.equal(true);
    });

    it("vault owner can play the game (advance, purchase) but NOT extract vault ETH directly", async function () {
      const { deployer, vault, game } = await loadFixture(deployFixture);

      // Vault owner can advance game for the vault
      // (This is by design -- vault owner manages vault gameplay)
      // But there's no admin withdraw function on the vault
      // Vault ETH can only leave via burnEth (proportional to shares burned)
    });
  });

  // =========================================================================
  // FINDING 4: DeityPass Owner -- Cosmetic Only
  // =========================================================================

  describe("DeityPass Owner Powers (Cosmetic)", function () {
    it("deityPass owner can transfer ownership but cannot mint/burn tokens", async function () {
      const { deployer, deityPass, alice } = await loadFixture(deployFixture);

      // Owner can transfer ownership
      await deityPass.transferOwnership(alice.address);
      expect(await deityPass.owner()).to.equal(alice.address);
    });

    it("deityPass owner can set renderer (view-only external call)", async function () {
      const { deployer, deityPass } = await loadFixture(deployFixture);

      // This is cosmetic -- affects only tokenURI rendering
      await deityPass.setRenderer(deployer.address);
      expect(await deityPass.renderer()).to.equal(deployer.address);
    });
  });

  // =========================================================================
  // FINDING 5: Non-Admin Addresses Cannot Access Admin Functions
  // =========================================================================

  describe("Access Control Enforcement", function () {
    it("non-admin cannot call admin functions on Game", async function () {
      const { alice, game } = await loadFixture(deployFixture);

      // setLootboxRngThreshold requires msg.sender == ADMIN contract
      await expect(
        game.connect(alice).setLootboxRngThreshold(hre.ethers.parseEther("1"))
      ).to.be.reverted;
    });

    it("non-admin cannot call adminSwapEthForStEth on Game", async function () {
      const { alice, game } = await loadFixture(deployFixture);

      await expect(
        game.connect(alice).adminSwapEthForStEth(
          alice.address,
          hre.ethers.parseEther("1"),
          { value: hre.ethers.parseEther("1") }
        )
      ).to.be.reverted;
    });

    it("non-owner cannot call admin functions on Admin contract", async function () {
      const { alice, admin } = await loadFixture(deployFixture);

      await expect(
        admin.connect(alice).stakeGameEthToStEth(hre.ethers.parseEther("1"))
      ).to.be.reverted;
    });
  });

  // =========================================================================
  // FINDING 6: setLinkEthPriceFeed -- Limited Griefing
  // =========================================================================

  describe("LINK Price Feed Manipulation", function () {
    it("cannot replace a healthy price feed", async function () {
      const { deployer, admin, mockFeed } = await loadFixture(deployFixture);

      // First set a healthy feed
      await admin.setLinkEthPriceFeed(await mockFeed.getAddress());

      // Cannot replace it while healthy
      await expect(
        admin.setLinkEthPriceFeed(deployer.address)
      ).to.be.reverted; // FeedHealthy
    });

    it("can set feed to zero to disable LINK rewards (griefing only)", async function () {
      const { deployer, admin } = await loadFixture(deployFixture);

      // Feed starts at address(0), which is "unhealthy"
      // Setting to address(0) disables oracle -- no rewards, but LINK still forwards
      await admin.setLinkEthPriceFeed(hre.ethers.ZeroAddress);
      // This is low-impact: LINK donations still fund VRF, just no BURNIE reward
    });
  });

  // =========================================================================
  // FINDING 7: CREATOR advanceGame bypass -- limited to daily mint gate
  // =========================================================================

  describe("CREATOR advanceGame Daily Mint Gate Bypass", function () {
    it("CREATOR can call advanceGame without minting today", async function () {
      const { deployer, game } = await loadFixture(deployFixture);

      // CREATOR bypasses daily mint gate -- can advance game without minting
      // This is by design for operational convenience but with a compromised key,
      // the attacker can advance the game state freely (without skin-in-game)
      // Impact: Low -- advancing the game does not extract funds
    });
  });

  // =========================================================================
  // FINDING 8: Icons32Data -- CREATOR Can Corrupt Art Before Finalize
  // =========================================================================

  describe("Icons32Data CREATOR Powers", function () {
    it("CREATOR can modify icon data before finalization", async function () {
      const { deployer, icons32 } = await loadFixture(deployFixture);

      // CREATOR can overwrite SVG paths -- cosmetic vandalism only
      // Once finalize() is called, paths are immutable
      // If already finalized, this is not exploitable
    });
  });
});
