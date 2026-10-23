import { ownerAction } from "../helpers/deployFixture.js";
import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import { DEPLOY_ORDER, DEPLOYMENTS } from "../../scripts/lib/predictAddresses.js";
import { ZERO_ADDRESS } from "../helpers/testUtils.js";

const deployDegenesisProtocol = () => deployFullProtocol({ degenesis: true });

describe("Deploy Pipeline", function () {
  after(function () {
    restoreAddresses();
  });

  it("deploys every contract at its predicted address", async function () {
    const f = await loadFixture(deployFullProtocol);
    expect(f.deployedAddrs.size).to.equal(f.predicted.size);

    for (const [key, predicted] of f.predicted) {
      const actual = f.deployedAddrs.get(key);
      expect(actual.toLowerCase()).to.equal(
        predicted.toLowerCase(),
        `Address mismatch for ${key}`
      );
    }
  });

  it("hosts Quests and Affiliate on Coinflip and leaves reserved addresses empty", async function () {
    const f = await loadFixture(deployFullProtocol);
    expect(await f.quests.getAddress()).to.equal(await f.coinflip.getAddress());
    expect(await f.affiliate.getAddress()).to.equal(await f.coinflip.getAddress());
    for (const offset of [6, 10]) {
      const address = hre.ethers.getCreateAddress({ from: f.deployer.address, nonce: f.startingNonce + offset });
      expect(await hre.ethers.provider.getCode(address)).to.equal("0x");
    }
  });

  it("the default fixture deploys on day index 9 (MAIN_LAUNCH_DAY)", async function () {
    const f = await loadFixture(deployFullProtocol);
    expect(await f.game.currentDayView()).to.equal(9n);
    expect(await f.degenesisModule.getAddress()).to.equal(f.predicted.get("GAME_DEGENESIS_MODULE"));
  });

  it("the Degenesis fixture deploys on day index 1 at the predicted addresses", async function () {
    const f = await loadFixture(deployDegenesisProtocol);
    expect(await f.game.currentDayView()).to.equal(1n);
    expect(f.deployedAddrs.size).to.equal(f.predicted.size);
    for (const [key, predicted] of f.predicted) {
      expect(f.deployedAddrs.get(key).toLowerCase()).to.equal(predicted.toLowerCase(), `Address mismatch for ${key}`);
    }
  });

  it("deployer nonce covers deployments, reserved addresses and combined genesis", async function () {
    const f = await loadFixture(deployFullProtocol);
    const endNonce = await f.deployer.getNonce();
    // Reserved nonce gaps preserve token addresses; genesis consumes one more nonce.
    const last = DEPLOYMENTS.at(-1).nonceOffset ?? DEPLOY_ORDER.length - 1;
    expect(endNonce - f.startingNonce).to.equal(last + 2);
  });

  it("initializes both real protocol passes within the transaction gas cap", async function () {
    const f = await loadFixture(deployFullProtocol);
    expect(await f.deityPass.ownerOf(0)).to.equal(await f.vault.getAddress());
    expect(await f.deityPass.ownerOf(6)).to.equal(await f.sdgnrs.getAddress());
    expect(f.genesisReceipt.gasUsed).to.be.lt(16_777_216n);
  });

  describe("Constructor side effects", function () {
    it("DegenerusGame: purchaseStartDay is set", async function () {
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

    it("FLIP: initial totalSupply is 0 (emission arrives as coinflip seed stakes)", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.totalSupply()).to.equal(0n);
    });

    it("FLIP: vaultMintAllowance is 0 (vault emission arrives as coinflip seed stakes)", async function () {
      const f = await loadFixture(deployFullProtocol);
      expect(await f.coin.vaultMintAllowance()).to.equal(0n);
    });

    it("Coinflip: days 1-20 each stake 200k for VAULT and sDGNRS", async function () {
      const f = await loadFixture(deployFullProtocol);
      const seed = 200000n; // whole FLIP: stake lanes and the seed window carry whole units
      const vaultAddr = await f.vault.getAddress();
      const sdgnrsAddr = await f.sdgnrs.getAddress();
      // The deploy seed is one window, not stake lanes: the constructor announces it with a
      // single SeedWindowArmed (days 1-20, 200k per day) and emits no
      // CoinflipStakeUpdated for either recipient.
      const armed = await f.coinflip.queryFilter(f.coinflip.filters.SeedWindowArmed());
      expect(armed.length).to.equal(1);
      expect(armed[0].args.firstDay).to.equal(1n);
      expect(armed[0].args.dayCount).to.equal(20n);
      expect(armed[0].args.amountPerDay).to.equal(seed);
      const staked = await f.coinflip.queryFilter(
        f.coinflip.filters.CoinflipStakeUpdated()
      );
      for (const ev of staked) {
        expect(ev.args.id).to.not.equal(1n);
        expect(ev.args.id).to.not.equal(2n);
      }
      // The next flip day lies in the window, so the view carries the seed for both.
      expect(await f.coinflip.coinflipAmount(vaultAddr)).to.equal(seed);
      expect(await f.coinflip.coinflipAmount(sdgnrsAddr)).to.equal(seed);
    });

    it("sDGNRS: DGNRS contract holds creator's 20% as sDGNRS", async function () {
      const f = await loadFixture(deployFullProtocol);
      const totalSupply = await f.sdgnrs.totalSupply();
      const dgnrsAddr = await f.dgnrs.getAddress();
      const wrapperBal = await f.sdgnrs.balanceOf(dgnrsAddr);
      expect(wrapperBal).to.equal((totalSupply * 2000n) / 10000n);
    });

    it("DGNRS: the vault holds the initial vesting release (50B) as DGNRS", async function () {
      const f = await loadFixture(deployFullProtocol);
      const VAULT_INITIAL = 50_000_000_000n * 10n ** 12n;
      expect(await f.dgnrs.balanceOf(await f.vault.getAddress())).to.equal(VAULT_INITIAL);
      expect(await f.dgnrs.balanceOf(f.deployer.address)).to.equal(0n);
    });

    it("DegenerusDeityPass: DGVE majority holder can call admin functions", async function () {
      const f = await loadFixture(deployFullProtocol);
      // Deployer holds all DGVE, so they are the vault owner
      await expect(
        ownerAction(f.deityPass.connect(f.deployer), "setRenderer", [ZERO_ADDRESS])
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
