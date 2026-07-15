import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceTime,
  getLastVRFRequestId,
} from "../helpers/testUtils.js";
import {
  giveSDGNRS,
  runLevelTransitionViaGame,
} from "../helpers/charityFixture.js";

/**
 * Post-gameover GNRUS recovery integration tests.
 *
 * Covers three functions added to contracts/GNRUS.sol:
 *   1. onFinalSweep()          — onlyGame; stamps sweptAt = block.timestamp.
 *                                Called by the game from handleFinalSweep once
 *                                GO_SWEPT latches (30 days after gameover).
 *   2. vaultRedeemFor(holder)  — vault-owner-only, post-sweep; burns holder's
 *                                ENTIRE GNRUS and pays the holder its full
 *                                proportional ETH+stETH share.
 *   3. sweepResidualToVault()  — vault-owner-only, post-sweep + 3-year delay;
 *                                moves ALL GNRUS ETH+stETH to ContractAddresses.VAULT.
 *
 * The final sweep is reached through advanceGame: once gameOver is latched and
 * 30 days have elapsed, advanceGame's post-gameover path delegatecalls
 * handleFinalSweep, which sets GO_SWEPT and calls gnrus.onFinalSweep().
 */
describe("GnrusRecovery", function () {
  after(function () {
    restoreAddresses();
  });

  const SECONDS_912_DAYS = 912 * 86400;
  const SWEEP_DELAY = 30 * 86400; // handleFinalSweep gate: goTime + 30 days
  const RESIDUAL_RECOVERY_DELAY = 3 * 365 * 86400; // GNRUS RESIDUAL_RECOVERY_DELAY
  const provider = hre.ethers.provider;

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  /**
   * Trigger game over at level 0 via the 912-day inactivity timeout.
   * Mirrors CharityGameHooks.triggerGameOver: advance past 912 days, then loop
   * advanceGame (fulfilling any VRF request) until gameOver() latches.
   */
  async function triggerGameOver(game, deployer, mockVRF) {
    await advanceTime(SECONDS_912_DAYS + 86400);
    for (let i = 0; i < 12; i++) {
      const reqBefore = await getLastVRFRequestId(mockVRF);
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        /* multi-tx drain may revert mid-sequence; keep driving */
      }
      const reqAfter = await getLastVRFRequestId(mockVRF);
      if (reqAfter > reqBefore) {
        try {
          await mockVRF.fulfillRandomWords(reqAfter, 42n);
        } catch {}
      }
      if (await game.gameOver()) return;
    }
  }

  /**
   * Drive the final sweep: after gameOver has latched, advance 30 days past the
   * gameover timestamp, then call advanceGame until GO_SWEPT flips and
   * gnrus.onFinalSweep() stamps sweptAt. The post-gameover advanceGame path
   * requests no VRF, but we fulfill any stray request defensively.
   */
  async function triggerFinalSweep(game, gnrus, deployer, mockVRF) {
    await advanceTime(SWEEP_DELAY + 3600);
    for (let i = 0; i < 12; i++) {
      if ((await gnrus.sweptAt()) !== 0n) return;
      const reqBefore = await getLastVRFRequestId(mockVRF);
      try {
        await game.connect(deployer).advanceGame();
      } catch {}
      const reqAfter = await getLastVRFRequestId(mockVRF);
      if (reqAfter > reqBefore) {
        try {
          await mockVRF.fulfillRandomWords(reqAfter, 42n);
        } catch {}
      }
    }
  }

  /**
   * Manufacture a real external GNRUS holder before gameover.
   *
   * GNRUS is only ever distributed out of the contract via the pickCharity()
   * paid branch (2% of unallocated to the winning slot's recipient). We fill a
   * non-locked slot with `holder`, fund `voter` with sDGNRS so the slot wins the
   * winner phase, then resolve level 0 by impersonating the game. `holder` ends
   * up with 2% of the initial supply; the game's own timeout-gameover never
   * transitions a level, so it never re-calls pickCharity (no currentLevel
   * desync), and burnAtGameOver only burns the contract's own unallocated
   * balance — leaving `holder`'s balance intact as the sole external holder.
   *
   * @returns the holder's GNRUS balance after distribution.
   */
  async function manufactureHolder(gnrus, sdgnrs, deployer, voter, holder, gameAddress) {
    const slot = 5; // non-locked (>= LOCKED_SLOTS)
    await gnrus.connect(deployer).setCharity(slot, holder.address);
    await giveSDGNRS(sdgnrs, gameAddress, voter.address, eth("100"));
    await gnrus.connect(voter).vote(slot);
    await runLevelTransitionViaGame(gnrus, gameAddress, 0); // pickCharity(0) via game impersonation
    return gnrus.balanceOf(holder.address);
  }

  // =====================================================================
  //  onFinalSweep
  // =====================================================================

  describe("onFinalSweep", function () {
    it("sweptAt is 0 before gameover, still 0 after gameover, and nonzero after the final sweep", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, gnrus, deployer, mockVRF } = fixture;

      expect(await gnrus.sweptAt()).to.equal(0n);
      expect(await game.gameOver()).to.equal(false);

      await triggerGameOver(game, deployer, mockVRF);
      expect(await game.gameOver()).to.equal(true);
      // Sweep is a distinct step 30 days later — not yet run.
      expect(await gnrus.sweptAt()).to.equal(0n);

      await triggerFinalSweep(game, gnrus, deployer, mockVRF);
      expect(await gnrus.sweptAt()).to.not.equal(0n,
        "sweptAt must be stamped once handleFinalSweep runs onFinalSweep()");
    });

    it("a direct onFinalSweep() from a non-game signer reverts Unauthorized", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { gnrus, alice } = fixture;

      await expect(
        gnrus.connect(alice).onFinalSweep()
      ).to.be.revertedWithCustomError(gnrus, "Unauthorized");
    });
  });

  // =====================================================================
  //  vaultRedeemFor
  // =====================================================================

  describe("vaultRedeemFor", function () {
    it("reverts NotSwept when called (by the vault owner) before the final sweep", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { gnrus, vault, deployer, dan } = fixture;

      expect(await vault.isVaultOwner(deployer.address)).to.equal(true);
      expect(await gnrus.sweptAt()).to.equal(0n);

      await expect(
        gnrus.connect(deployer).vaultRedeemFor(dan.address)
      ).to.be.revertedWithCustomError(gnrus, "NotSwept");
    });

    it("reverts Unauthorized when called by a non-vault-owner", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { gnrus, vault, alice, dan } = fixture;

      expect(await vault.isVaultOwner(alice.address)).to.equal(false);

      await expect(
        gnrus.connect(alice).vaultRedeemFor(dan.address)
      ).to.be.revertedWithCustomError(gnrus, "Unauthorized");
    });

    it("reverts InsufficientBurn for a zero-balance holder after the sweep", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, gnrus, deployer, mockVRF, others } = fixture;

      await triggerGameOver(game, deployer, mockVRF);
      await triggerFinalSweep(game, gnrus, deployer, mockVRF);
      expect(await gnrus.sweptAt()).to.not.equal(0n);

      const zeroHolder = others[3]; // never received any GNRUS
      expect(await gnrus.balanceOf(zeroHolder.address)).to.equal(0n);

      await expect(
        gnrus.connect(deployer).vaultRedeemFor(zeroHolder.address)
      ).to.be.revertedWithCustomError(gnrus, "InsufficientBurn");
    });

    it("vault owner redeems a real holder: holder's GNRUS zeroed, holder paid ETH+stETH, totalSupply drops by the holder's balance", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, gnrus, sdgnrs, deployer, alice, dan, mockVRF } = fixture;
      const gameAddress = await game.getAddress();
      const gnrusAddr = await gnrus.getAddress();

      // Real holder (dan) minted via the charity pickCharity paid branch.
      const holderBal = await manufactureHolder(gnrus, sdgnrs, deployer, alice, dan, gameAddress);
      expect(holderBal).to.be.gt(0n, "manufactured holder must own GNRUS");

      await triggerGameOver(game, deployer, mockVRF);
      await triggerFinalSweep(game, gnrus, deployer, mockVRF);
      expect(await gnrus.sweptAt()).to.not.equal(0n);

      // Back the redemption: fund GNRUS with ETH (receive()) and stETH so the
      // holder is paid real value. dan is the sole external holder post-burn, so
      // the proportional share equals the full GNRUS ETH+stETH balance.
      await deployer.sendTransaction({ to: gnrusAddr, value: eth("5") });
      await fixture.mockStETH.mint(gnrusAddr, eth("3"));

      const gnrusEthBefore = await provider.getBalance(gnrusAddr);
      const gnrusStethBefore = await fixture.mockStETH.balanceOf(gnrusAddr);
      const danEthBefore = await provider.getBalance(dan.address);
      const danStethBefore = await fixture.mockStETH.balanceOf(dan.address);
      const supplyBefore = await gnrus.totalSupply();
      const danGnrusBefore = await gnrus.balanceOf(dan.address);

      expect(gnrusEthBefore).to.be.gt(0n);
      expect(gnrusStethBefore).to.be.gt(0n);

      // dan does NOT send the tx (deployer does), so dan pays no gas — its ETH
      // balance moves only by the redemption payout.
      await gnrus.connect(deployer).vaultRedeemFor(dan.address);

      // Holder fully burned.
      expect(await gnrus.balanceOf(dan.address)).to.equal(0n);
      // totalSupply drops by exactly the holder's burned balance.
      expect(await gnrus.totalSupply()).to.equal(supplyBefore - danGnrusBefore);
      // Holder paid ETH (exact — sole holder drains GNRUS's ETH) and stETH.
      const danEthAfter = await provider.getBalance(dan.address);
      const danStethAfter = await fixture.mockStETH.balanceOf(dan.address);
      expect(danEthAfter - danEthBefore).to.equal(gnrusEthBefore);
      expect(danStethAfter).to.be.gt(danStethBefore);
    });
  });

  // =====================================================================
  //  sweepResidualToVault
  // =====================================================================

  describe("sweepResidualToVault", function () {
    it("reverts NotSwept when called (by the vault owner) before the final sweep", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { gnrus, vault, deployer } = fixture;

      expect(await vault.isVaultOwner(deployer.address)).to.equal(true);
      expect(await gnrus.sweptAt()).to.equal(0n);

      await expect(
        gnrus.connect(deployer).sweepResidualToVault()
      ).to.be.revertedWithCustomError(gnrus, "NotSwept");
    });

    it("reverts Unauthorized when called by a non-vault-owner", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { gnrus, vault, alice } = fixture;

      expect(await vault.isVaultOwner(alice.address)).to.equal(false);

      await expect(
        gnrus.connect(alice).sweepResidualToVault()
      ).to.be.revertedWithCustomError(gnrus, "Unauthorized");
    });

    it("reverts TooEarly after the sweep but before the 3-year residual delay", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, gnrus, deployer, mockVRF } = fixture;

      await triggerGameOver(game, deployer, mockVRF);
      await triggerFinalSweep(game, gnrus, deployer, mockVRF);
      expect(await gnrus.sweptAt()).to.not.equal(0n);

      // Immediately post-sweep: block.timestamp == sweptAt << sweptAt + 3 years.
      await expect(
        gnrus.connect(deployer).sweepResidualToVault()
      ).to.be.revertedWithCustomError(gnrus, "TooEarly");
    });

    it("after sweep + 3 years, vault owner sweeps ALL GNRUS ETH+stETH to the VAULT", async function () {
      const fixture = await loadFixture(deployFullProtocol);
      const { game, gnrus, vault, deployer, mockVRF } = fixture;
      const gnrusAddr = await gnrus.getAddress();
      const vaultAddr = await vault.getAddress();

      await triggerGameOver(game, deployer, mockVRF);
      await triggerFinalSweep(game, gnrus, deployer, mockVRF);
      expect(await gnrus.sweptAt()).to.not.equal(0n);

      // Seed a residual: ETH (receive()) + stETH held by GNRUS.
      await deployer.sendTransaction({ to: gnrusAddr, value: eth("5") });
      await fixture.mockStETH.mint(gnrusAddr, eth("3"));

      const gnrusEthBefore = await provider.getBalance(gnrusAddr);
      const gnrusStethBefore = await fixture.mockStETH.balanceOf(gnrusAddr);
      const vaultEthBefore = await provider.getBalance(vaultAddr);
      const vaultStethBefore = await fixture.mockStETH.balanceOf(vaultAddr);
      expect(gnrusEthBefore).to.be.gt(0n);
      expect(gnrusStethBefore).to.be.gt(0n);

      // Pass the 3-year residual-recovery delay.
      await advanceTime(RESIDUAL_RECOVERY_DELAY + 3600);

      await gnrus.connect(deployer).sweepResidualToVault();

      // GNRUS drained.
      expect(await provider.getBalance(gnrusAddr)).to.equal(0n);
      expect(await fixture.mockStETH.balanceOf(gnrusAddr)).to.equal(0n);
      // VAULT received the residual (ETH exact; stETH increased).
      expect(await provider.getBalance(vaultAddr)).to.equal(vaultEthBefore + gnrusEthBefore);
      expect(await fixture.mockStETH.balanceOf(vaultAddr)).to.be.gt(vaultStethBefore);
    });
  });
});
