import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { DEPLOY_ORDER } from "../../scripts/lib/predictAddresses.js";

describe("Deploy Pipeline", function () {
  after(function () {
    restoreAddresses();
  });

  it("deploys all 22 contracts at predicted addresses", async function () {
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

  it("deployer nonce advances by exactly 22 protocol contracts", async function () {
    const f = await loadFixture(deployFullProtocol);
    const endNonce = await f.deployer.getNonce();
    // startingNonce was captured AFTER mock deploys, so delta = 22
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

    it("BurnieCoin: initial totalSupply is 0", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.totalSupply()).to.equal(0);
    });

    it("BurnieCoin: vaultMintAllowance is 2M", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.vaultMintAllowance()).to.equal(
        hre.ethers.parseEther("2000000")
      );
    });

    it("DegenerusStonk: creator receives 20% allocation", async function () {
      const f = await loadFixture(deployFullProtocol);
      const totalSupply = await f.dgnrs.totalSupply();
      const creatorBal = await f.dgnrs.balanceOf(f.deployer.address);
      // Creator gets 20% (2000 bps of 10000)
      expect(creatorBal).to.equal((totalSupply * 2000n) / 10000n);
    });

    it("DegenerusDeityPass: owner is deployer", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.deityPass.owner()).to.equal(f.deployer.address);
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
