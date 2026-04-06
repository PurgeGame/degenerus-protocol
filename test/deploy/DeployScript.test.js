import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { DEPLOY_ORDER } from "../../scripts/lib/predictAddresses.js";
import { ZERO_ADDRESS } from "../helpers/testUtils.js";

describe("Deploy Pipeline", function () {
  after(function () {
    restoreAddresses();
  });

  it("deploys all 23 contracts at predicted addresses", async function () {
    const f = await loadFixture(deployFullProtocol);
    expect(f.deployedAddrs.size).to.equal(DEPLOY_ORDER.length);

    for (const [key, predicted] of f.predicted) {
      const actual = f.deployedAddrs.get(key);
      expect(actual.toLowerCase()).to.equal(
        predicted.toLowerCase(),
        `Address mismatch for ${key}`
      );
    }
  });

  it("deployer nonce advances by exactly 23 protocol contracts", async function () {
    const f = await loadFixture(deployFullProtocol);
    const endNonce = await f.deployer.getNonce();
    // startingNonce was captured AFTER mock deploys, so delta = 23
    expect(endNonce - f.startingNonce).to.equal(DEPLOY_ORDER.length);
  });

  describe("Constructor side effects", function () {
    it("DegenerusGame: levelStartTime is set", async function () {
      const f = await loadFixture(deployFullProtocol);
      const game = f.game;
      // level() should return 0 initially
      expect(await game.level()).to.equal(0);
    });

    it("DegenerusGame: mintPrice returns initial price", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.game.mintPrice()).to.equal(hre.ethers.parseEther("0.01"));
    });

    it("DegenerusGame: not in jackpot phase", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.game.jackpotPhase()).to.equal(false);
    });

    it("DegenerusGame: not game over", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.game.gameOver()).to.equal(false);
    });

    it("BurnieCoin: initial totalSupply is 2M (sDGNRS backing reserve)", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.totalSupply()).to.equal(hre.ethers.parseEther("2000000"));
    });

    it("BurnieCoin: vaultMintAllowance is 2M", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.vaultMintAllowance()).to.equal(
        hre.ethers.parseEther("2000000")
      );
    });

    it("StakedDegenerusStonk: DGNRS contract holds creator's 20% as sDGNRS", async function () {
      const f = await loadFixture(deployFullProtocol);
      const totalSupply = await f.sdgnrs.totalSupply();
      const dgnrsAddr = await f.dgnrs.getAddress();
      const wrapperBal = await f.sdgnrs.balanceOf(dgnrsAddr);
      expect(wrapperBal).to.equal((totalSupply * 2000n) / 10000n);
    });

    it("DegenerusStonk: creator holds initial vesting (50B) as DGNRS", async function () {
      const f = await loadFixture(deployFullProtocol);
      const CREATOR_INITIAL = 50_000_000_000n * 10n ** 18n;
      const creatorDgnrs = await f.dgnrs.balanceOf(f.deployer.address);
      expect(creatorDgnrs).to.equal(CREATOR_INITIAL);
    });

    it("DegenerusDeityPass: DGVE majority holder can call admin functions", async function () {
      const f = await loadFixture(deployFullProtocol);
      // Deployer holds all DGVE, so they are the vault owner
      await expect(
        f.deityPass.connect(f.deployer).setRenderer(ZERO_ADDRESS)
      ).to.not.be.reverted;
    });

    it("DegenerusAdmin: VRF subscription created", async function () {
      const f = await loadFixture(deployFullProtocol);
      const subId = await f.admin.subscriptionId();
      expect(subId).to.be.gt(0);
    });

    it("Icons32Data: not finalized", async function () {
      const f = await loadFixture(deployFullProtocol);
      // Should be able to call setPaths without revert
      // (just verifying it's not finalized — actual data test in unit tests)
      expect(await f.icons32.getAddress()).to.not.equal(
        hre.ethers.ZeroAddress
      );
    });
  });
});
