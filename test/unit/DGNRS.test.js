import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  deployFullProtocol,
  restoreAddresses,
  giveWalletId,
} from "../helpers/deployFixture.js";
import {
  eth,
  seedDailyWord,
  advanceToNextDay,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";

// Pool enum mapping (from DGNRS.sol)
// v47: the 4-ordinal pool was renamed Earlybird -> PresaleBox (the earlybird
// subsystem was removed; the pool itself survives, renamed, still seeded at deploy).
const dgnrsUnits = (value) => hre.ethers.parseUnits(value, 12);

const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, PresaleBox: 4 };

// Distribution constants from contract
const INITIAL_SUPPLY = 1_000_000_000_000n * dgnrsUnits("1"); // 1 trillion
const CREATOR_BPS = 2000n; // 20%
const WHALE_POOL_BPS = 1000n;
const AFFILIATE_POOL_BPS = 3000n;
const LOOTBOX_POOL_BPS = 2000n;
const REWARD_POOL_BPS = 1000n;
const PRESALE_BOX_POOL_BPS = 1000n; // v47: was EARLYBIRD_POOL_BPS; pool renamed, BPS unchanged
const BPS_DENOM = 10_000n;

// Helper: give a player sDGNRS from the Reward pool via game impersonation
async function giveSDGNRS(sdgnrs, game, recipient, amount) {
  // Redemptions are keyed by wallet ID, so a burning holder must be registered.
  await giveWalletId(game, recipient);
  const gameAddr = await game.getAddress();
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [gameAddr] });
  await hre.ethers.provider.send("hardhat_setBalance", [gameAddr, "0xDE0B6B3A7640000"]);
  const gameSigner = await hre.ethers.getSigner(gameAddr);
  await sdgnrs.connect(gameSigner).transferFromPool(Pool.Reward, recipient, amount);
  await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [gameAddr] });
  // Admit a gambling burn using the authenticated current-day parity word.
  await seedDailyWord(game, await game.currentDayView(), BigInt("0x" + "de".repeat(32)));
}

// Fund Game claimable through its real credit hook, including matching ETH custody.
async function fundGameClaimableForSdgnrs(gameAddr, sdgnrsAddr, amount) {
  const balance = await hre.ethers.provider.getBalance(sdgnrsAddr);
  await hre.ethers.provider.send("hardhat_setBalance", [sdgnrsAddr, hre.ethers.toBeHex(balance + amount)]);
  await hre.network.provider.request({ method: "hardhat_impersonateAccount", params: [sdgnrsAddr] });
  try {
    const signer = await hre.ethers.getSigner(sdgnrsAddr);
    const game = await hre.ethers.getContractAt("DegenerusGame", gameAddr);
    await hre.network.provider.send("hardhat_setNextBlockBaseFeePerGas", ["0x0"]);
    await game.connect(signer).creditRedemptionDirect(2, amount, { value: amount, gasPrice: 0 });
  } finally {
    await hre.network.provider.request({ method: "hardhat_stopImpersonatingAccount", params: [sdgnrsAddr] });
  }
}

async function assertBurnAdmitted(sdgnrs, amount) {
  const [value] = await sdgnrs.previewBurnValue(amount);
  expect(value, "fixture must clear the production redemption minimum").to.be.gte(eth("0.01"));
}

describe("DGNRS", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("token name is 'Degenerus Protocol Revenue and Governance Token'", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      expect(await sdgnrs.name()).to.equal("Degenerus Protocol Revenue and Governance Token");
    });

    it("token symbol is 'sDGNRS'", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      expect(await sdgnrs.symbol()).to.equal("sDGNRS");
    });

    it("token decimals is 12", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      expect(await sdgnrs.decimals()).to.equal(12n);
    });

    it("total supply equals INITIAL_SUPPLY", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      expect(await sdgnrs.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("DGNRS contract holds creator's 20% of sDGNRS supply", async function () {
      const { sdgnrs, dgnrs } = await loadFixture(deployFullProtocol);
      const expectedCreator = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
      const dgnrsAddr = await dgnrs.getAddress();
      expect(await sdgnrs.balanceOf(dgnrsAddr)).to.be.closeTo(
        expectedCreator,
        dgnrsUnits("1")
      );
    });

    it("creator holds initial vesting (50B) as DGNRS tokens", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      const CREATOR_INITIAL = 50_000_000_000n * dgnrsUnits("1");
      expect(await dgnrs.balanceOf(deployer.address)).to.be.closeTo(
        CREATOR_INITIAL,
        dgnrsUnits("1")
      );
    });

    it("contract holds the pool allocations (80% total)", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const sdgnrsAddr = await sdgnrs.getAddress();
      const contractBal = await sdgnrs.balanceOf(sdgnrsAddr);
      const expectedPool =
        INITIAL_SUPPLY - (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
      expect(contractBal).to.be.closeTo(expectedPool, dgnrsUnits("1"));
    });

    it("Whale pool balance is correct (~11.43% of total)", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const whalePool = await sdgnrs.poolBalance(Pool.Whale);
      const expected = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
      expect(whalePool).to.be.closeTo(expected, dgnrsUnits("100"));
    });

    it("Affiliate pool balance is correct (30% of total)", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const affiliatePool = await sdgnrs.poolBalance(Pool.Affiliate);
      const expected = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
      expect(affiliatePool).to.be.closeTo(expected, dgnrsUnits("100"));
    });

    it("Lootbox pool balance is correct (~11.43%)", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const lootboxPool = await sdgnrs.poolBalance(Pool.Lootbox);
      const expected = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
      expect(lootboxPool).to.be.closeTo(expected, dgnrsUnits("100"));
    });

    it("Reward pool balance is correct (10% of total)", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const rewardPool = await sdgnrs.poolBalance(Pool.Reward);
      const expected = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
      expect(rewardPool).to.be.closeTo(expected, dgnrsUnits("100"));
    });

    it("PresaleBox pool balance is correct (seeded at deploy)", async function () {
      // v47: the 4-ordinal pool (was Earlybird, now PresaleBox) is still seeded at
      // deploy from PRESALE_BOX_POOL_BPS. The earlybird ACCRUAL mechanics
      // (_awardEarlybirdDgnrs / _finalizeEarlybird) were removed in v47, but the
      // pool seeding survives unchanged.
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const presaleBoxPool = await sdgnrs.poolBalance(Pool.PresaleBox);
      const expected = (INITIAL_SUPPLY * PRESALE_BOX_POOL_BPS) / BPS_DENOM;
      expect(presaleBoxPool).to.be.closeTo(expected, dgnrsUnits("100"));
    });

  });

  // ---------------------------------------------------------------------------
  // 2. transferFromPool (game-only)
  // ---------------------------------------------------------------------------
  describe("transferFromPool", function () {
    it("reverts when called by non-game address", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs
          .connect(alice)
          .transferFromPool(Pool.Reward, alice.address, dgnrsUnits("100"))
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("game contract can transfer from pool to recipient", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const poolBefore = await sdgnrs.poolBalance(Pool.Reward);
      const amount = dgnrsUnits("100");
      const tx = await sdgnrs
        .connect(gameSigner)
        .transferFromPool(Pool.Reward, alice.address, amount);

      const ev = await getEvent(tx, sdgnrs, "PoolTransfer");
      expect(ev.args.pool).to.equal(BigInt(Pool.Reward));
      expect(ev.args.to).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);

      const poolAfter = await sdgnrs.poolBalance(Pool.Reward);
      expect(poolAfter).to.equal(poolBefore - amount);
      expect(await sdgnrs.balanceOf(alice.address)).to.equal(amount);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("transfers only available amount when requested exceeds pool", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const poolBal = await sdgnrs.poolBalance(Pool.Reward);
      // Request more than available
      const tx = await sdgnrs
        .connect(gameSigner)
        .transferFromPool(Pool.Reward, alice.address, poolBal * 2n);
      const ev = await getEvent(tx, sdgnrs, "PoolTransfer");
      // Should transfer only the available amount
      expect(ev.args.amount).to.equal(poolBal);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("returns 0 when amount is 0", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const transferred = await sdgnrs
        .connect(gameSigner)
        .transferFromPool.staticCall(Pool.Reward, alice.address, 0n);
      expect(transferred).to.equal(0n);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("reverts when recipient is zero address", async function () {
      const { sdgnrs, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      await expect(
        sdgnrs
          .connect(gameSigner)
          .transferFromPool(Pool.Whale, ZERO_ADDRESS, dgnrsUnits("100"))
      ).to.be.revertedWithCustomError(sdgnrs, "ZeroAddress");

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 7. burnAtGameOver (game-only, game over)
  // ---------------------------------------------------------------------------

  describe("burnAtGameOver", function () {
    it("reverts when called by non-game address", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs.connect(alice).burnAtGameOver()
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("game can burn remaining pool tokens", async function () {
      const { sdgnrs, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const sdgnrsAddr = await sdgnrs.getAddress();
      const poolBal = await sdgnrs.balanceOf(sdgnrsAddr);
      expect(poolBal).to.be.gt(0n);
      const supplyBefore = await sdgnrs.totalSupply();

      await sdgnrs.connect(gameSigner).burnAtGameOver();
      expect(await sdgnrs.balanceOf(sdgnrsAddr)).to.equal(0n);
      expect(await sdgnrs.totalSupply()).to.equal(supplyBefore - poolBal);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 8. depositSteth (game-only)
  // ---------------------------------------------------------------------------
  describe("depositSteth", function () {
    it("reverts when called by non-game address", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs.connect(alice).depositSteth(eth("1"))
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("game can deposit stETH", async function () {
      const { sdgnrs, game, mockStETH, deployer } = await loadFixture(
        deployFullProtocol
      );
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();

      // Mint stETH to game
      await mockStETH.connect(deployer).mint(gameAddr, eth("5"));

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      // Approve sdgnrs to pull stETH
      await mockStETH.connect(gameSigner).approve(sdgnrsAddr, eth("5"));

      const tx = await sdgnrs.connect(gameSigner).depositSteth(eth("5"));
      const ev = await getEvent(tx, sdgnrs, "Deposit");
      expect(ev.args.stethAmount).to.equal(eth("5"));

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("depositSteth with zero amount succeeds as no-op", async function () {
      const { sdgnrs, game, mockStETH, deployer } = await loadFixture(
        deployFullProtocol
      );
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      // Approve 0 stETH (mockStETH.transferFrom(game, sdgnrs, 0) should succeed)
      await mockStETH.connect(gameSigner).approve(sdgnrsAddr, 0n);

      const tx = await sdgnrs.connect(gameSigner).depositSteth(0n);
      const ev = await getEvent(tx, sdgnrs, "Deposit");
      // Zero amount emitted — no-op deposit
      expect(ev.args.stethAmount).to.equal(0n);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 9. ETH receive (game-only)
  // ---------------------------------------------------------------------------
  describe("receive (ETH deposit)", function () {
    it("reverts when ETH sent by non-game address", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      const sdgnrsAddr = await sdgnrs.getAddress();
      await expect(
        alice.sendTransaction({ to: sdgnrsAddr, value: eth("1") })
      ).to.be.revertedWithCustomError(sdgnrs, "Unauthorized");
    });

    it("game can send ETH to sdgnrs contract", async function () {
      const { sdgnrs, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x56BC75E2D63100000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);

      const tx = await gameSigner.sendTransaction({
        to: sdgnrsAddr,
        value: eth("1"),
      });
      const ev = await getEvent(tx, sdgnrs, "Deposit");
      expect(ev.args.ethAmount).to.equal(eth("1"));

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 10. burn (proportional claim)
  // ---------------------------------------------------------------------------
  describe("burn", function () {
    it("reverts when amount is zero", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        sdgnrs.connect(alice).burn(0n)
      ).to.be.revertedWithCustomError(sdgnrs, "Insufficient");
    });

    it("reverts when amount exceeds balance", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      // Alice has no tokens
      await expect(
        sdgnrs.connect(alice).burn(dgnrsUnits("1"))
      ).to.be.revertedWithCustomError(sdgnrs, "Insufficient");
    });

    it("burn is player-only — no third-party burn", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const amount = INITIAL_SUPPLY / 100n;
      await giveSDGNRS(sdgnrs, game, alice.address, amount);
      await fundGameClaimableForSdgnrs(await game.getAddress(), await sdgnrs.getAddress(), eth("10"));
      await assertBurnAdmitted(sdgnrs, amount);

      // Alice burns her own sDGNRS — during active game this enters the gambling path
      // and emits RedemptionSubmitted, not Burn (Burn is only emitted post-gameOver)
      const tx = await sdgnrs.connect(alice).burn(amount);
      const ev = await getEvent(tx, sdgnrs, "RedemptionSubmitted");
      expect(ev.args.player).to.equal(await game.walletIdOf(alice.address));
      expect(ev.args.sdgnrsAmount).to.equal(amount);
    });

    it("burn with ETH backing records unpriced batch tokens", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const sdgnrsAmount = INITIAL_SUPPLY / 100n;
      await giveSDGNRS(sdgnrs, game, alice.address, sdgnrsAmount);

      // Add ETH to DGNRS contract via game impersonation
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x56BC75E2D63100000", // 100 ETH
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await gameSigner.sendTransaction({ to: sdgnrsAddr, value: eth("10") });
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });

      // Include Game claimable in the estimated backing; burning does not pull it.
      await fundGameClaimableForSdgnrs(gameAddr, sdgnrsAddr, eth("100"));

      // Preview before burn
      const [ethOut, flipOut] = await sdgnrs.previewBurnValue(sdgnrsAmount);

      // Burn — during active game this enters the gambling path (RedemptionSubmitted).
      // Tokens burn immediately; the next request fixes their proportional payout base.
      await assertBurnAdmitted(sdgnrs, sdgnrsAmount);
      const tx = await sdgnrs.connect(alice).burn(sdgnrsAmount);

      const ev = await getEvent(tx, sdgnrs, "RedemptionSubmitted");
      expect(ev.args.player).to.equal(await game.walletIdOf(alice.address));
      expect(ev.args.sdgnrsAmount).to.equal(sdgnrsAmount);
      // Pricing and reservation happen when the next live request closes this batch.
      expect(ev.args.batchId).to.equal((await sdgnrs.redemptionBatchState()).openBatch);
      const pending = await sdgnrs.pendingRedemptions(await game.walletIdOf(alice.address), ev.args.batchId);
      expect(pending.tokens).to.equal(sdgnrsAmount);
      expect(await sdgnrs.pendingRedemptionEthValue()).to.equal(0n);
    });

    it("RedemptionSubmitted event emitted with correct fields during active game", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const amount = INITIAL_SUPPLY / 100n;
      await giveSDGNRS(sdgnrs, game, alice.address, amount);
      await fundGameClaimableForSdgnrs(await game.getAddress(), await sdgnrs.getAddress(), eth("10"));
      await assertBurnAdmitted(sdgnrs, amount);

      // During active game, burn() routes to the gambling path and emits RedemptionSubmitted.
      // The Burn event is only emitted on the deterministic post-gameOver path.
      const tx = await sdgnrs.connect(alice).burn(amount);
      const ev = await getEvent(tx, sdgnrs, "RedemptionSubmitted");
      expect(ev.args.player).to.equal(await game.walletIdOf(alice.address));
      expect(ev.args.sdgnrsAmount).to.equal(amount);
    });

    it("total supply decreases after burn", async function () {
      const { sdgnrs, game, alice } = await loadFixture(deployFullProtocol);
      const amount = INITIAL_SUPPLY / 100n;
      await giveSDGNRS(sdgnrs, game, alice.address, amount);
      await fundGameClaimableForSdgnrs(await game.getAddress(), await sdgnrs.getAddress(), eth("10"));
      await assertBurnAdmitted(sdgnrs, amount);
      const supplyBefore = await sdgnrs.totalSupply();

      await sdgnrs.connect(alice).burn(amount);
      expect(await sdgnrs.totalSupply()).to.equal(supplyBefore - amount);
    });

    it("burn with stETH backing records unpriced batch tokens", async function () {
      const { sdgnrs, game, mockStETH, deployer, alice } = await loadFixture(deployFullProtocol);
      const sdgnrsAmount = INITIAL_SUPPLY / 100n;
      await giveSDGNRS(sdgnrs, game, alice.address, sdgnrsAmount);

      // Deposit stETH into sDGNRS via game
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();
      await mockStETH.connect(deployer).mint(gameAddr, eth("10"));
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0xDE0B6B3A7640000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await mockStETH.connect(gameSigner).approve(sdgnrsAddr, eth("10"));
      await sdgnrs.connect(gameSigner).depositSteth(eth("10"));
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });

      // previewBurnValue reports one wei figure paid as ETH and/or stETH; the deposited
      // stETH is part of the base, so the preview must be positive here with claimableEth
      // still unfunded.
      const [valuePreview] = await sdgnrs.previewBurnValue(sdgnrsAmount);
      expect(valuePreview).to.be.gt(0n);

      await fundGameClaimableForSdgnrs(gameAddr, sdgnrsAddr, eth("100"));

      // A live burn records raw tokens; stETH stays in custody until settlement.
      const stethBefore = await mockStETH.balanceOf(alice.address);
      await assertBurnAdmitted(sdgnrs, sdgnrsAmount);
      const tx = await sdgnrs.connect(alice).burn(sdgnrsAmount);
      const ev = await getEvent(tx, sdgnrs, "RedemptionSubmitted");
      expect(ev.args.player).to.equal(await game.walletIdOf(alice.address));
      expect(ev.args.sdgnrsAmount).to.equal(sdgnrsAmount);
      // The burn retains its holder share until request close.
      expect(ev.args.batchId).to.equal((await sdgnrs.redemptionBatchState()).openBatch);
      const pending = await sdgnrs.pendingRedemptions(await game.walletIdOf(alice.address), ev.args.batchId);
      expect(pending.tokens).to.equal(sdgnrsAmount);
      expect(await sdgnrs.pendingRedemptionEthValue()).to.equal(0n);
      // No immediate stETH transfer on the gambling path
      const stethAfter = await mockStETH.balanceOf(alice.address);
      expect(stethAfter).to.equal(stethBefore);
    });

    // FLIP burn path not testable without fixture modification — fixture does not
    // deposit FLIP into sDGNRS. FLIP backing arrives via manual transfers or
    // coinflip claimables which require game state the unit test fixture does not set up.
  });

  // ---------------------------------------------------------------------------
  // 11. previewBurnValue
  // ---------------------------------------------------------------------------
  describe("previewBurnValue", function () {
    it("returns zeros when amount is 0", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const [ethOut, flipOut] = await sdgnrs.previewBurnValue(0n);
      expect(ethOut).to.equal(0n);
      expect(flipOut).to.equal(0n);
    });

    it("returns zeros when amount exceeds total supply", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const [ethOut, flipOut] = await sdgnrs.previewBurnValue(
        INITIAL_SUPPLY * 2n
      );
      expect(ethOut).to.equal(0n);
      expect(flipOut).to.equal(0n);
    });

    it("proportional preview when ETH exists", async function () {
      const { sdgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const sdgnrsAddr = await sdgnrs.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      // Set 1000 ETH balance to cover 100 ETH transfer + gas
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x3635C9ADC5DEA00000",
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await gameSigner.sendTransaction({ to: sdgnrsAddr, value: eth("100") });
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });

      // Preview for 1% of supply
      const onePercent = INITIAL_SUPPLY / 100n;
      const [ethOut, flipOut] = await sdgnrs.previewBurnValue(onePercent);
      // 1% of 100 ETH = 1 ETH
      expect(ethOut).to.be.closeTo(eth("1"), eth("0.01"));
    });
  });

  // ---------------------------------------------------------------------------
  // 12. flipReserve
  // ---------------------------------------------------------------------------
  describe("flipReserve", function () {
    it("returns 0 initially when no FLIP deposited", async function () {
      const { sdgnrs } = await loadFixture(deployFullProtocol);
      const reserve = await sdgnrs.flipReserve();
      expect(reserve).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 11. gameAdvance (holder-only)
  // ---------------------------------------------------------------------------
  describe("gameAdvance", function () {
    it("anyone can call gameAdvance", async function () {
      const { sdgnrs, alice } = await loadFixture(deployFullProtocol);
      await advanceToNextDay();
      await expect(sdgnrs.connect(alice).gameAdvance(0)).to.not.be.reverted;
    });
  });

});
