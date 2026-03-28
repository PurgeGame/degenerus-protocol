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
  getEvent,
  getLastVRFRequestId,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, Earlybird: 4 };
const INITIAL_SUPPLY = 1_000_000_000_000n * eth("1");
const CREATOR_BPS = 2000n;
const BPS_DENOM = 10_000n;
const CREATOR_TOTAL = 200_000_000_000n * eth("1");
const CREATOR_INITIAL = 50_000_000_000n * eth("1");
const VEST_PER_LEVEL = 5_000_000_000n * eth("1");

// 912-day level-0 idle timeout triggers the game-over liveness path
const SECONDS_912_DAYS = 912 * 86400;

/**
 * Drive the two-step game-over flow:
 *   1. advance time past the 912-day level-0 timeout
 *   2. advanceGame → liveness guard fires, VRF request issued
 *   3. fulfill VRF
 *   4. advanceGame → processes word → handleGameOverDrain → gameOver = true
 */
async function triggerGameOver(game, caller, mockVRF) {
  await advanceTime(SECONDS_912_DAYS + 1);
  await game.connect(caller).advanceGame();
  const requestId = await getLastVRFRequestId(mockVRF);
  if (requestId > 0n) {
    await mockVRF.fulfillRandomWords(requestId, 42n);
  }
  await game.connect(caller).advanceGame();
}

/**
 * Fixture: full protocol deployed with gameOver already set to true.
 * Used by any test that calls dgnrs.burn(), which requires gameOver.
 */
async function deployWithGameOver() {
  const ctx = await deployFullProtocol();
  await triggerGameOver(ctx.game, ctx.deployer, ctx.mockVRF);
  return ctx;
}

// Helper: impersonate game contract and transfer sDGNRS from pool to recipient
async function giveSDGNRS(sdgnrs, game, recipient, amount) {
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
  await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  await sdgnrs.connect(gameSigner).transferFromPool(Pool.Reward, recipient, amount);
  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
}

// Helper: set game level via storage slot 0 (level is at offset 18, 3 bytes)
async function setGameLevel(game, level) {
  const gameAddr = await game.getAddress();
  const slot0 = await hre.ethers.provider.getStorage(gameAddr, 0);
  const slot0Bn = BigInt(slot0);
  // Clear bytes [18..20] (level field) and write new value
  const mask = ~(0xFFFFFFn << 144n); // 18 bytes * 8 = 144 bits
  const newSlot0 = (slot0Bn & mask) | (BigInt(level) << 144n);
  await hre.ethers.provider.send("hardhat_setStorageAt", [
    gameAddr,
    "0x0",
    "0x" + newSlot0.toString(16).padStart(64, "0"),
  ]);
}

// Helper: deposit ETH into sDGNRS via game impersonation
async function depositETH(sdgnrs, game, amount) {
  const gameAddr = await game.getAddress();
  const sdgnrsAddr = await sdgnrs.getAddress();
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
  // Set balance high enough to cover deposit + gas
  await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0x3635C9ADC5DEA00000"]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  await gameSigner.sendTransaction({ to: sdgnrsAddr, value: amount });
  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
}

describe("DegenerusStonk (DGNRS Liquid Token)", function () {
  after(() => restoreAddresses());

  // ===========================================================================
  // 1. Constructor / Initial State
  // ===========================================================================
  describe("Constructor", function () {
    it("name is 'Degenerus Stonk'", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.name()).to.equal("Degenerus Stonk");
    });

    it("symbol is 'DGNRS'", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.symbol()).to.equal("DGNRS");
    });

    it("decimals is 18", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.decimals()).to.equal(18n);
    });

    it("totalSupply equals 20% of sDGNRS supply", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const expected = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
      expect(await dgnrs.totalSupply()).to.equal(expected);
    });

    it("creator receives 25% of DGNRS at deployment (vesting)", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_INITIAL);
    });

    it("sDGNRS contract holds matching sDGNRS balance", async function () {
      const { dgnrs, sdgnrs } = await loadFixture(deployFullProtocol);
      const dgnrsAddr = await dgnrs.getAddress();
      const dgnrsSupply = await dgnrs.totalSupply();
      expect(await sdgnrs.balanceOf(dgnrsAddr)).to.equal(dgnrsSupply);
    });
  });

  // ===========================================================================
  // 2. ERC20 Functions
  // ===========================================================================
  describe("ERC20", function () {
    it("transfer moves tokens", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      expect(await dgnrs.balanceOf(alice.address)).to.equal(amount);
    });

    it("transfer emits Transfer event", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      const tx = await dgnrs.connect(deployer).transfer(alice.address, amount);
      const ev = await getEvent(tx, dgnrs, "Transfer");
      expect(ev.args.from).to.equal(deployer.address);
      expect(ev.args.to).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("transfer reverts to zero address", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(deployer).transfer(ZERO_ADDRESS, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "ZeroAddress");
    });

    it("transfer reverts on insufficient balance", async function () {
      const { dgnrs, alice, bob } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).transfer(bob.address, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("anyone can transfer DGNRS (not soulbound)", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(deployFullProtocol);
      await dgnrs.connect(deployer).transfer(alice.address, eth("1000"));
      // Alice can freely transfer to Bob
      await dgnrs.connect(alice).transfer(bob.address, eth("500"));
      expect(await dgnrs.balanceOf(bob.address)).to.equal(eth("500"));
    });

    it("approve + transferFrom works", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await dgnrs.connect(deployer).approve(alice.address, amount);
      expect(await dgnrs.allowance(deployer.address, alice.address)).to.equal(amount);

      await dgnrs.connect(alice).transferFrom(deployer.address, bob.address, amount);
      expect(await dgnrs.balanceOf(bob.address)).to.equal(amount);
      expect(await dgnrs.allowance(deployer.address, alice.address)).to.equal(0n);
    });

    it("transferFrom with max approval does not decrease allowance", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(deployFullProtocol);
      const MAX = hre.ethers.MaxUint256;
      await dgnrs.connect(deployer).approve(alice.address, MAX);

      await dgnrs.connect(alice).transferFrom(deployer.address, bob.address, eth("100"));
      expect(await dgnrs.allowance(deployer.address, alice.address)).to.equal(MAX);
    });

    it("transferFrom reverts when exceeding allowance", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(deployFullProtocol);
      await dgnrs.connect(deployer).approve(alice.address, eth("100"));
      await expect(
        dgnrs.connect(alice).transferFrom(deployer.address, bob.address, eth("200"))
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("Approval event emitted", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const tx = await dgnrs.connect(deployer).approve(alice.address, eth("500"));
      const ev = await getEvent(tx, dgnrs, "Approval");
      expect(ev.args.owner).to.equal(deployer.address);
      expect(ev.args.spender).to.equal(alice.address);
      expect(ev.args.amount).to.equal(eth("500"));
    });

    // Coverage gap: DELTA-L-01 — transfer to self
    it("transfer to self does not change balance (DELTA-L-01)", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      const balBefore = await dgnrs.balanceOf(deployer.address);
      const amount = eth("1000");

      const tx = await dgnrs.connect(deployer).transfer(deployer.address, amount);
      // Balance unchanged — tokens debited then credited to same address
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(balBefore);
      // Transfer event still emitted
      const ev = await getEvent(tx, dgnrs, "Transfer");
      expect(ev.args.from).to.equal(deployer.address);
      expect(ev.args.to).to.equal(deployer.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("transferFrom to self does not change balance", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const balBefore = await dgnrs.balanceOf(deployer.address);
      const amount = eth("500");
      await dgnrs.connect(deployer).approve(alice.address, amount);

      await dgnrs.connect(alice).transferFrom(deployer.address, deployer.address, amount);
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(balBefore);
    });
  });

  // ===========================================================================
  // 3. unwrapTo (Vault Owner Only)
  // ===========================================================================
  describe("unwrapTo", function () {
    it("vault owner can unwrap DGNRS to soulbound sDGNRS for a recipient", async function () {
      const { dgnrs, sdgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");

      const ownerBefore = await dgnrs.balanceOf(deployer.address);
      const supplyBefore = await dgnrs.totalSupply();
      await dgnrs.connect(deployer).unwrapTo(alice.address, amount);

      // Vault owner's DGNRS decreased
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(ownerBefore - amount);
      // DGNRS totalSupply decreased (burned)
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore - amount);
      // Alice received soulbound sDGNRS
      expect(await sdgnrs.balanceOf(alice.address)).to.equal(amount);
    });

    it("emits UnwrapTo event", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      const tx = await dgnrs.connect(deployer).unwrapTo(alice.address, amount);
      const ev = await getEvent(tx, dgnrs, "UnwrapTo");
      expect(ev.args.recipient).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("reverts when called by non-vault-owner", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      // Give alice some DGNRS first
      await dgnrs.connect(deployer).transfer(alice.address, eth("1000"));
      await expect(
        dgnrs.connect(alice).unwrapTo(alice.address, eth("100"))
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("reverts on zero address recipient", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(deployer).unwrapTo(ZERO_ADDRESS, eth("100"))
      ).to.be.revertedWithCustomError(dgnrs, "ZeroAddress");
    });

    it("reverts when amount exceeds balance", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      const bal = await dgnrs.balanceOf(deployer.address);
      await expect(
        dgnrs.connect(deployer).unwrapTo(deployer.address, bal + 1n)
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("reverts on zero amount", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(deployer).unwrapTo(alice.address, 0n)
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });
  });

  // ===========================================================================
  // 4. Burn (through to sDGNRS)
  // ===========================================================================
  describe("burn", function () {
    it("reverts on zero amount", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(deployer).burn(0n)
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("reverts when amount exceeds balance", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).burn(eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("burns DGNRS and forwards ETH from sDGNRS backing", async function () {
      const { dgnrs, sdgnrs, game, deployer, alice } = await loadFixture(deployWithGameOver);

      // Give alice some DGNRS
      const amount = eth("100000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      // Add ETH backing to sDGNRS
      await depositETH(sdgnrs, game, eth("10"));

      // Burn
      const balBefore = await hre.ethers.provider.getBalance(alice.address);
      const tx = await dgnrs.connect(alice).burn(amount);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balAfter = await hre.ethers.provider.getBalance(alice.address);

      // Should have received ETH
      const ev = await getEvent(tx, dgnrs, "BurnThrough");
      expect(ev.args.from).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
      expect(ev.args.ethOut).to.be.gt(0n);
      expect(balAfter + gasUsed - balBefore).to.equal(ev.args.ethOut);
    });

    it("DGNRS totalSupply decreases after burn", async function () {
      const { dgnrs, deployer } = await loadFixture(deployWithGameOver);
      const supplyBefore = await dgnrs.totalSupply();
      const amount = eth("1000");
      await dgnrs.connect(deployer).burn(amount);
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore - amount);
    });

    it("sDGNRS totalSupply also decreases (underlying burned)", async function () {
      const { dgnrs, sdgnrs, deployer } = await loadFixture(deployWithGameOver);
      const sSupplyBefore = await sdgnrs.totalSupply();
      const amount = eth("1000");
      await dgnrs.connect(deployer).burn(amount);
      expect(await sdgnrs.totalSupply()).to.equal(sSupplyBefore - amount);
    });

    it("emits BurnThrough event", async function () {
      const { dgnrs, deployer } = await loadFixture(deployWithGameOver);
      const tx = await dgnrs.connect(deployer).burn(eth("1000"));
      const ev = await getEvent(tx, dgnrs, "BurnThrough");
      expect(ev.args.from).to.equal(deployer.address);
      expect(ev.args.amount).to.equal(eth("1000"));
    });

    it("burn with stETH backing forwards stETH proportionally", async function () {
      const { dgnrs, sdgnrs, game, mockStETH, deployer, alice } = await loadFixture(deployWithGameOver);
      const amount = eth("100000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      // Deposit stETH into sDGNRS via game
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();
      await mockStETH.connect(deployer).mint(gameAddr, eth("10"));
      await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
      await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await mockStETH.connect(gameSigner).approve(sdgnrsAddr, eth("10"));
      await sdgnrs.connect(gameSigner).depositSteth(eth("10"));
      await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });

      // Preview should show stETH output
      const [, stethPreview] = await dgnrs.previewBurn(amount);
      expect(stethPreview).to.be.gt(0n);

      // Burn and verify stETH forwarded
      const stethBefore = await mockStETH.balanceOf(alice.address);
      const tx = await dgnrs.connect(alice).burn(amount);
      const ev = await getEvent(tx, dgnrs, "BurnThrough");
      expect(ev.args.stethOut).to.be.gt(0n);
      const stethAfter = await mockStETH.balanceOf(alice.address);
      expect(stethAfter - stethBefore).to.equal(ev.args.stethOut);
    });

    // BURNIE burn path not testable without fixture modification — fixture deploys
    // BURNIE (COIN contract) but no BURNIE is deposited/transferred to sDGNRS.
    // BURNIE backing arrives via manual transfers or coinflip claimables which
    // require game state that the unit test fixture does not set up.
  });

  // ===========================================================================
  // 5. previewBurn
  // ===========================================================================
  describe("previewBurn", function () {
    it("delegates to sDGNRS previewBurn", async function () {
      const { dgnrs, sdgnrs, game } = await loadFixture(deployFullProtocol);
      await depositETH(sdgnrs, game, eth("100"));

      const amount = eth("1000");
      const [ethD, stethD, burnieD] = await dgnrs.previewBurn(amount);
      const [ethS, stethS, burnieS] = await sdgnrs.previewBurn(amount);

      expect(ethD).to.equal(ethS);
      expect(stethD).to.equal(stethS);
      expect(burnieD).to.equal(burnieS);
    });
  });

  // ===========================================================================
  // 6. sDGNRS soulbound enforcement
  // ===========================================================================
  describe("sDGNRS soulbound enforcement", function () {
    it("sDGNRS has no transfer function", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      // StakedDegenerusStonk should not have a transfer function
      expect(sdgnrs.transfer).to.be.undefined;
    });

    it("sDGNRS burn(uint256) burns from msg.sender only", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await giveSDGNRS(sdgnrs, game, alice.address, amount);

      const supplyBefore = await sdgnrs.totalSupply();
      await sdgnrs.connect(alice).burn(amount);
      expect(await sdgnrs.balanceOf(alice.address)).to.equal(0n);
      expect(await sdgnrs.totalSupply()).to.equal(supplyBefore - amount);
    });

    it("wrapperTransferTo reverts when called by non-DGNRS contract", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs.connect(alice).wrapperTransferTo(alice.address, eth("1"))
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });
  });

  // ===========================================================================
  // 7. sDGNRS new features
  // ===========================================================================
  describe("sDGNRS new features", function () {
    it("burnAtGameOver: reverts for non-game caller", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs.connect(alice).burnAtGameOver()
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("burnAtGameOver: game can burn all pool tokens", async function () {
      const { sdgnrs, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();

      await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
      await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const poolBal = await sdgnrs.balanceOf(sdgnrsAddr);
      expect(poolBal).to.be.gt(0n);
      const supplyBefore = await sdgnrs.totalSupply();

      await sdgnrs.connect(gameSigner).burnAtGameOver();
      expect(await sdgnrs.balanceOf(sdgnrsAddr)).to.equal(0n);
      expect(await sdgnrs.totalSupply()).to.equal(supplyBefore - poolBal);

      await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
    });

    it("gameAdvance is permissionless", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      // Alice has no sDGNRS — should still work
      await expect(sdgnrs.connect(alice).gameAdvance()).to.not.be.reverted;
    });

    it("gameClaimWhalePass is permissionless", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(sdgnrs.connect(alice).gameClaimWhalePass()).to.not.be.reverted;
    });

    // resolveCoinflips removed — sDGNRS flips now resolve daily in processCoinflipPayouts
  });

  // ===========================================================================
  // 8. Supply accounting
  // ===========================================================================
  describe("Supply accounting", function () {
    it("DGNRS supply + sDGNRS wrapper balance stay in sync", async function () {
      const { dgnrs, sdgnrs, deployer, alice } = await loadFixture(deployWithGameOver);
      const dgnrsAddr = await dgnrs.getAddress();

      // Initial state
      const dgnrsSupply0 = await dgnrs.totalSupply();
      const wrapperBal0 = await sdgnrs.balanceOf(dgnrsAddr);
      expect(dgnrsSupply0).to.equal(wrapperBal0);

      // After unwrapTo — both decrease by same amount
      const unwrapAmt = eth("5000");
      await dgnrs.connect(deployer).unwrapTo(alice.address, unwrapAmt);
      const dgnrsSupply1 = await dgnrs.totalSupply();
      const wrapperBal1 = await sdgnrs.balanceOf(dgnrsAddr);
      expect(dgnrsSupply1).to.equal(wrapperBal1);
      expect(dgnrsSupply1).to.equal(dgnrsSupply0 - unwrapAmt);

      // After burn — both decrease by same amount
      const burnAmt = eth("1000");
      await dgnrs.connect(deployer).burn(burnAmt);
      const dgnrsSupply2 = await dgnrs.totalSupply();
      const wrapperBal2 = await sdgnrs.balanceOf(dgnrsAddr);
      expect(dgnrsSupply2).to.equal(wrapperBal2);
      expect(dgnrsSupply2).to.equal(dgnrsSupply1 - burnAmt);
    });

    it("sDGNRS totalSupply reflects all holders correctly", async function () {
      const { dgnrs, sdgnrs, game, deployer, alice } = await loadFixture(deployFullProtocol);

      // Get initial supply
      const supply0 = await sdgnrs.totalSupply();
      expect(supply0).to.equal(INITIAL_SUPPLY);

      // Give alice sDGNRS from pool, then burn — supply decreases
      await giveSDGNRS(sdgnrs, game, alice.address, eth("1000"));
      await sdgnrs.connect(alice).burn(eth("500"));
      expect(await sdgnrs.totalSupply()).to.equal(supply0 - eth("500"));
    });
  });

  // ===========================================================================
  // 7. Vesting
  // ===========================================================================
  describe("Vesting", function () {
    it("constructor gives creator 25% (50B), contract holds 75% (150B)", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      const dgnrsAddr = await dgnrs.getAddress();
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_INITIAL);
      expect(await dgnrs.balanceOf(dgnrsAddr)).to.equal(CREATOR_TOTAL - CREATOR_INITIAL);
      expect(await dgnrs.totalSupply()).to.equal(CREATOR_TOTAL);
    });

    it("claimVested reverts at level 0 (nothing new to vest)", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      await expect(dgnrs.connect(deployer).claimVested()).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("claimVested reverts for non-vault-owner", async function () {
      const { dgnrs, game, alice } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 5);
      await expect(dgnrs.connect(alice).claimVested()).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("claimVested releases 5B at level 1", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 1);
      await dgnrs.connect(deployer).claimVested();
      // Creator still has initial 50B, vault owner (deployer) gets 5B vested
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_INITIAL + VEST_PER_LEVEL);
    });

    it("claimVested releases 25B at level 5", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 5);
      await dgnrs.connect(deployer).claimVested();
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_INITIAL + VEST_PER_LEVEL * 5n);
    });

    it("claimVested caps at 200B total at level 30", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 30);
      await dgnrs.connect(deployer).claimVested();
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_TOTAL);
      const dgnrsAddr = await dgnrs.getAddress();
      expect(await dgnrs.balanceOf(dgnrsAddr)).to.equal(0n);
    });

    it("claimVested caps at 200B even past level 30", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 100);
      await dgnrs.connect(deployer).claimVested();
      expect(await dgnrs.balanceOf(deployer.address)).to.equal(CREATOR_TOTAL);
    });

    it("claimVested is incremental — claim at level 3 then level 7", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 3);
      await dgnrs.connect(deployer).claimVested();
      const after3 = await dgnrs.balanceOf(deployer.address);
      expect(after3).to.equal(CREATOR_INITIAL + VEST_PER_LEVEL * 3n);

      await setGameLevel(game, 7);
      await dgnrs.connect(deployer).claimVested();
      const after7 = await dgnrs.balanceOf(deployer.address);
      expect(after7).to.equal(CREATOR_INITIAL + VEST_PER_LEVEL * 7n);
    });

    it("claimVested reverts on double-claim at same level", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      await setGameLevel(game, 5);
      await dgnrs.connect(deployer).claimVested();
      await expect(dgnrs.connect(deployer).claimVested()).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("claimVested emits Transfer from contract to caller", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      const dgnrsAddr = await dgnrs.getAddress();
      await setGameLevel(game, 2);
      const tx = await dgnrs.connect(deployer).claimVested();
      const ev = await getEvent(tx, dgnrs, "Transfer");
      expect(ev.args.from).to.equal(dgnrsAddr);
      expect(ev.args.to).to.equal(deployer.address);
      expect(ev.args.amount).to.equal(VEST_PER_LEVEL * 2n);
    });

    it("totalSupply unchanged by vesting claims", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      const supplyBefore = await dgnrs.totalSupply();
      await setGameLevel(game, 10);
      await dgnrs.connect(deployer).claimVested();
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore);
    });
  });
});
