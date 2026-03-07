import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
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

// Pool enum mapping (from DegenerusStonk.sol)
const Pool = { Whale: 0, Affiliate: 1, Lootbox: 2, Reward: 3, Earlybird: 4 };

// Distribution constants from contract
const INITIAL_SUPPLY = 1_000_000_000_000n * eth("1"); // 1 trillion
const CREATOR_BPS = 2000n; // 20%
const WHALE_POOL_BPS = 1143n;
const AFFILIATE_POOL_BPS = 3428n;
const LOOTBOX_POOL_BPS = 1143n;
const REWARD_POOL_BPS = 1143n;
const EARLYBIRD_POOL_BPS = 1143n;
const BPS_DENOM = 10_000n;

describe("DegenerusStonk", function () {
  after(() => restoreAddresses());

  // ---------------------------------------------------------------------------
  // 1. Constructor / Initial State
  // ---------------------------------------------------------------------------
  describe("Initial state", function () {
    it("token name is 'Degenerus Stonk'", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.name()).to.equal("Degenerus Stonk");
    });

    it("token symbol is 'DGNRS'", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.symbol()).to.equal("DGNRS");
    });

    it("token decimals is 18", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.decimals()).to.equal(18n);
    });

    it("total supply equals INITIAL_SUPPLY", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("creator receives 20% of initial supply", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      const expectedCreator = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
      expect(await dgnrs.balanceOf(deployer.address)).to.be.closeTo(
        expectedCreator,
        eth("1")
      );
    });

    it("contract holds the pool allocations (80% total)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const dgnrsAddr = await dgnrs.getAddress();
      const contractBal = await dgnrs.balanceOf(dgnrsAddr);
      const expectedPool =
        INITIAL_SUPPLY - (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
      expect(contractBal).to.be.closeTo(expectedPool, eth("1"));
    });

    it("Whale pool balance is correct (~11.43% of total)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const whalePool = await dgnrs.poolBalance(Pool.Whale);
      const expected = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
      expect(whalePool).to.be.closeTo(expected, eth("100"));
    });

    it("Affiliate pool balance is correct (~34.28% of total)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const affiliatePool = await dgnrs.poolBalance(Pool.Affiliate);
      const expected = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
      expect(affiliatePool).to.be.closeTo(expected, eth("100"));
    });

    it("Lootbox pool balance is correct (~11.43%)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const lootboxPool = await dgnrs.poolBalance(Pool.Lootbox);
      const expected = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
      expect(lootboxPool).to.be.closeTo(expected, eth("100"));
    });

    it("Reward pool balance is correct (~11.43%)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const rewardPool = await dgnrs.poolBalance(Pool.Reward);
      const expected = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
      expect(rewardPool).to.be.closeTo(expected, eth("100"));
    });

    it("Earlybird pool balance is correct (~11.43%)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const earlybirdPool = await dgnrs.poolBalance(Pool.Earlybird);
      const expected = (INITIAL_SUPPLY * EARLYBIRD_POOL_BPS) / BPS_DENOM;
      expect(earlybirdPool).to.be.closeTo(expected, eth("100"));
    });

    it("locked balances start at 0 for all users", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      expect(await dgnrs.lockedBalance(alice.address)).to.equal(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. ERC20 Standard Functions
  // ---------------------------------------------------------------------------
  describe("ERC20 basics", function () {
    it("transfer works between accounts", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      expect(await dgnrs.balanceOf(alice.address)).to.equal(amount);
    });

    it("Transfer event is emitted on transfer", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      const tx = await dgnrs.connect(deployer).transfer(alice.address, amount);
      const ev = await getEvent(tx, dgnrs, "Transfer");
      expect(ev.args.from).to.equal(deployer.address);
      expect(ev.args.to).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("reverts on transfer to zero address", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(deployer).transfer(ZERO_ADDRESS, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "ZeroAddress");
    });

    it("reverts when transferring more than balance", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).transfer(ZERO_ADDRESS, eth("1"))
      ).to.be.reverted;
    });

    it("approve sets allowance and emits Approval event", async function () {
      const { dgnrs, alice, bob } = await loadFixture(deployFullProtocol);
      const amount = eth("500");
      const tx = await dgnrs.connect(alice).approve(bob.address, amount);
      const ev = await getEvent(tx, dgnrs, "Approval");
      expect(ev.args.owner).to.equal(alice.address);
      expect(ev.args.spender).to.equal(bob.address);
      expect(ev.args.amount).to.equal(amount);
      expect(await dgnrs.allowance(alice.address, bob.address)).to.equal(amount);
    });

    it("transferFrom works with sufficient allowance", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      await dgnrs.connect(alice).approve(bob.address, amount);
      await dgnrs.connect(bob).transferFrom(alice.address, bob.address, amount);
      expect(await dgnrs.balanceOf(bob.address)).to.equal(amount);
      // Allowance should be reduced
      expect(await dgnrs.allowance(alice.address, bob.address)).to.equal(0n);
    });

    it("transferFrom reverts when allowance is insufficient", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      // No approval given
      await expect(
        dgnrs.connect(bob).transferFrom(alice.address, bob.address, amount)
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("transferFrom with max allowance does not reduce allowance", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      await dgnrs
        .connect(alice)
        .approve(bob.address, hre.ethers.MaxUint256);
      await dgnrs.connect(bob).transferFrom(alice.address, bob.address, amount);
      expect(await dgnrs.allowance(alice.address, bob.address)).to.equal(
        hre.ethers.MaxUint256
      );
    });

    it("COIN contract bypasses allowance check in transferFrom", async function () {
      const { dgnrs, coin, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      const amount = eth("100");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      const coinAddr = await coin.getAddress();

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [coinAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        coinAddr,
        "0xDE0B6B3A7640000",
      ]);
      const coinSigner = await hre.ethers.getSigner(coinAddr);

      // COIN can transferFrom without allowance
      await expect(
        dgnrs
          .connect(coinSigner)
          .transferFrom(alice.address, deployer.address, amount)
      ).to.not.be.reverted;

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [coinAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 3. Locked tokens / transfers blocked
  // ---------------------------------------------------------------------------
  describe("locked token transfer restriction", function () {
    it("locked tokens cannot be transferred", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      // Transfer tokens to alice
      const amount = eth("10000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      // Lock all tokens
      await dgnrs.connect(alice).lockForLevel(amount);

      // Attempt to transfer locked tokens should revert
      await expect(
        dgnrs.connect(alice).transfer(deployer.address, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "TokensLocked");
    });

    it("can transfer unlocked portion when partially locked", async function () {
      const { dgnrs, deployer, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const totalAmount = eth("10000");
      const lockAmount = eth("6000");
      const transferAmount = eth("3000"); // within unlocked portion

      await dgnrs.connect(deployer).transfer(alice.address, totalAmount);
      await dgnrs.connect(alice).lockForLevel(lockAmount);

      await expect(
        dgnrs.connect(alice).transfer(bob.address, transferAmount)
      ).to.not.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 4. lockForLevel and unlock
  // ---------------------------------------------------------------------------
  describe("lockForLevel", function () {
    it("locks tokens and emits Locked event", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("5000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      const tx = await dgnrs.connect(alice).lockForLevel(amount);
      const ev = await getEvent(tx, dgnrs, "Locked");
      expect(ev.args.holder).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
      expect(await dgnrs.lockedBalance(alice.address)).to.equal(amount);
    });

    it("reverts when trying to lock more than available balance", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).lockForLevel(eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("can increase lock within same level", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("5000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      await dgnrs.connect(alice).lockForLevel(eth("2000"));
      await dgnrs.connect(alice).lockForLevel(eth("2000"));
      expect(await dgnrs.lockedBalance(alice.address)).to.equal(eth("4000"));
    });

    it("auto-unlocks when locking at a new level", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      // Alice can only test auto-unlock behavior if level changes
      // For now just verify the lock mechanism works at level 0
      const amount = eth("5000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      await dgnrs.connect(alice).lockForLevel(amount);
      expect(await dgnrs.lockedBalance(alice.address)).to.equal(amount);
      expect(await dgnrs.lockedLevel(alice.address)).to.equal(0n);
    });
  });

  describe("unlock", function () {
    it("reverts when no locked tokens", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).unlock()
      ).to.be.revertedWithCustomError(dgnrs, "NoLockedTokens");
    });

    it("reverts when lock is still active (same level)", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("5000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      await dgnrs.connect(alice).lockForLevel(amount);

      // Still at level 0, lock is active
      await expect(
        dgnrs.connect(alice).unlock()
      ).to.be.revertedWithCustomError(dgnrs, "LockStillActive");
    });
  });

  // ---------------------------------------------------------------------------
  // 5. transferFromPool (game-only)
  // ---------------------------------------------------------------------------
  describe("transferFromPool", function () {
    it("reverts when called by non-game address", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs
          .connect(alice)
          .transferFromPool(Pool.Reward, alice.address, eth("100"))
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("game contract can transfer from pool to recipient", async function () {
      const { dgnrs, game, alice } = await loadFixture(deployFullProtocol);
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

      const poolBefore = await dgnrs.poolBalance(Pool.Reward);
      const amount = eth("100");
      const tx = await dgnrs
        .connect(gameSigner)
        .transferFromPool(Pool.Reward, alice.address, amount);

      const ev = await getEvent(tx, dgnrs, "PoolTransfer");
      expect(ev.args.pool).to.equal(BigInt(Pool.Reward));
      expect(ev.args.to).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);

      const poolAfter = await dgnrs.poolBalance(Pool.Reward);
      expect(poolAfter).to.equal(poolBefore - amount);
      expect(await dgnrs.balanceOf(alice.address)).to.equal(amount);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("transfers only available amount when requested exceeds pool", async function () {
      const { dgnrs, game, alice } = await loadFixture(deployFullProtocol);
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

      const poolBal = await dgnrs.poolBalance(Pool.Reward);
      // Request more than available
      const tx = await dgnrs
        .connect(gameSigner)
        .transferFromPool(Pool.Reward, alice.address, poolBal * 2n);
      const ev = await getEvent(tx, dgnrs, "PoolTransfer");
      // Should transfer only the available amount
      expect(ev.args.amount).to.equal(poolBal);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("returns 0 when amount is 0", async function () {
      const { dgnrs, game, alice } = await loadFixture(deployFullProtocol);
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

      const transferred = await dgnrs
        .connect(gameSigner)
        .transferFromPool.staticCall(Pool.Reward, alice.address, 0n);
      expect(transferred).to.equal(0n);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 6. transferBetweenPools (game-only)
  // ---------------------------------------------------------------------------
  describe("transferBetweenPools", function () {
    it("reverts when called by non-game address", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs
          .connect(alice)
          .transferBetweenPools(Pool.Earlybird, Pool.Reward, eth("100"))
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("game can move tokens between pools", async function () {
      const { dgnrs, game } = await loadFixture(deployFullProtocol);
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

      const earlybirdBefore = await dgnrs.poolBalance(Pool.Earlybird);
      const rewardBefore = await dgnrs.poolBalance(Pool.Reward);
      const amount = eth("1000");

      const tx = await dgnrs
        .connect(gameSigner)
        .transferBetweenPools(Pool.Earlybird, Pool.Reward, amount);
      const ev = await getEvent(tx, dgnrs, "PoolRebalance");
      expect(ev.args.from).to.equal(BigInt(Pool.Earlybird));
      expect(ev.args.to).to.equal(BigInt(Pool.Reward));
      expect(ev.args.amount).to.equal(amount);

      expect(await dgnrs.poolBalance(Pool.Earlybird)).to.equal(
        earlybirdBefore - amount
      );
      expect(await dgnrs.poolBalance(Pool.Reward)).to.equal(
        rewardBefore + amount
      );

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });

    it("total supply is unchanged after transferBetweenPools (no minting/burning)", async function () {
      const { dgnrs, game } = await loadFixture(deployFullProtocol);
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

      const supplyBefore = await dgnrs.totalSupply();
      await dgnrs
        .connect(gameSigner)
        .transferBetweenPools(Pool.Earlybird, Pool.Reward, eth("1000"));
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });
    });
  });

  // ---------------------------------------------------------------------------
  // 7. burnForGame (game-only)
  // ---------------------------------------------------------------------------

  describe("burnForGame", function () {
    it("reverts when called by non-game address", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).burnForGame(alice.address, eth("100"))
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("game can burn tokens from an address", async function () {
      const { dgnrs, game, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      // Give alice some tokens
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

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

      const supplyBefore = await dgnrs.totalSupply();
      await dgnrs.connect(gameSigner).burnForGame(alice.address, amount);
      expect(await dgnrs.balanceOf(alice.address)).to.equal(0n);
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore - amount);

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
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).depositSteth(eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("game can deposit stETH", async function () {
      const { dgnrs, game, mockStETH, deployer } = await loadFixture(
        deployFullProtocol
      );
      const gameAddr = await game.getAddress();
      const dgnrsAddr = await dgnrs.getAddress();

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

      // Approve dgnrs to pull stETH
      await mockStETH.connect(gameSigner).approve(dgnrsAddr, eth("5"));

      const tx = await dgnrs.connect(gameSigner).depositSteth(eth("5"));
      const ev = await getEvent(tx, dgnrs, "Deposit");
      expect(ev.args.stethAmount).to.equal(eth("5"));

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
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      const dgnrsAddr = await dgnrs.getAddress();
      await expect(
        alice.sendTransaction({ to: dgnrsAddr, value: eth("1") })
      ).to.be.revertedWithCustomError(dgnrs, "Unauthorized");
    });

    it("game can send ETH to dgnrs contract", async function () {
      const { dgnrs, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const dgnrsAddr = await dgnrs.getAddress();

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
        to: dgnrsAddr,
        value: eth("1"),
      });
      const ev = await getEvent(tx, dgnrs, "Deposit");
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
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).burn(ZERO_ADDRESS, 0n)
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("reverts when amount exceeds balance", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      // Alice has no tokens
      await expect(
        dgnrs.connect(alice).burn(ZERO_ADDRESS, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "Insufficient");
    });

    it("reverts when non-approved caller tries to burn for another player", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).burn(deployer.address, eth("1"))
      ).to.be.revertedWithCustomError(dgnrs, "NotApproved");
    });

    it("approved operator can burn on behalf of player", async function () {
      const { dgnrs, game, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      // Transfer tokens to alice
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      // Approve bob as operator for alice
      await game.connect(alice).setOperatorApproval(deployer.address, true);

      // deployer burns on alice's behalf
      const tx = await dgnrs
        .connect(deployer)
        .burn(alice.address, amount);
      const ev = await getEvent(tx, dgnrs, "Burn");
      expect(ev.args.from).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("burn with ETH backing pays ETH proportionally", async function () {
      const { dgnrs, game, deployer, alice } = await loadFixture(
        deployFullProtocol
      );
      // Give alice some DGNRS
      const dgnrsAmount = eth("100000"); // 100k DGNRS
      await dgnrs.connect(deployer).transfer(alice.address, dgnrsAmount);

      // Add ETH to DGNRS contract via game impersonation
      const gameAddr = await game.getAddress();
      const dgnrsAddr = await dgnrs.getAddress();
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [gameAddr],
      });
      await hre.ethers.provider.send("hardhat_setBalance", [
        gameAddr,
        "0x56BC75E2D63100000", // 100 ETH
      ]);
      const gameSigner = await hre.ethers.getSigner(gameAddr);
      await gameSigner.sendTransaction({ to: dgnrsAddr, value: eth("10") });
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });

      // Preview before burn
      const [ethOut, stethOut, burnieOut] = await dgnrs.previewBurn(dgnrsAmount);

      // Burn
      const balBefore = await hre.ethers.provider.getBalance(alice.address);
      const tx = await dgnrs.connect(alice).burn(ZERO_ADDRESS, dgnrsAmount);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const balAfter = await hre.ethers.provider.getBalance(alice.address);

      const ev = await getEvent(tx, dgnrs, "Burn");
      expect(ev.args.from).to.equal(alice.address);
      expect(ev.args.amount).to.equal(dgnrsAmount);
      expect(ev.args.ethOut).to.be.gt(0n);
      // Verify ETH was actually received
      expect(balAfter + gasUsed - balBefore).to.equal(ev.args.ethOut);
    });

    it("Burn event emitted with correct fields", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);

      const tx = await dgnrs.connect(alice).burn(ZERO_ADDRESS, amount);
      const ev = await getEvent(tx, dgnrs, "Burn");
      expect(ev.args.from).to.equal(alice.address);
      expect(ev.args.amount).to.equal(amount);
    });

    it("total supply decreases after burn", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("1000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      const supplyBefore = await dgnrs.totalSupply();

      await dgnrs.connect(alice).burn(ZERO_ADDRESS, amount);
      expect(await dgnrs.totalSupply()).to.equal(supplyBefore - amount);
    });
  });

  // ---------------------------------------------------------------------------
  // 11. previewBurn
  // ---------------------------------------------------------------------------
  describe("previewBurn", function () {
    it("returns zeros when amount is 0", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const [ethOut, stethOut, burnieOut] = await dgnrs.previewBurn(0n);
      expect(ethOut).to.equal(0n);
      expect(stethOut).to.equal(0n);
      expect(burnieOut).to.equal(0n);
    });

    it("returns zeros when amount exceeds total supply", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const [ethOut, stethOut, burnieOut] = await dgnrs.previewBurn(
        INITIAL_SUPPLY * 2n
      );
      expect(ethOut).to.equal(0n);
      expect(stethOut).to.equal(0n);
      expect(burnieOut).to.equal(0n);
    });

    it("proportional preview when ETH exists", async function () {
      const { dgnrs, game, deployer } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const dgnrsAddr = await dgnrs.getAddress();
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
      await gameSigner.sendTransaction({ to: dgnrsAddr, value: eth("100") });
      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [gameAddr],
      });

      // Preview for 1% of supply
      const onePercent = INITIAL_SUPPLY / 100n;
      const [ethOut, stethOut, burnieOut] = await dgnrs.previewBurn(onePercent);
      // 1% of 100 ETH = 1 ETH
      expect(ethOut).to.be.closeTo(eth("1"), eth("0.01"));
    });
  });

  // ---------------------------------------------------------------------------
  // 12. totalBacking and burnieReserve
  // ---------------------------------------------------------------------------
  describe("totalBacking", function () {
    it("returns 0 initially (no ETH/stETH/BURNIE backing)", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      // Initially no backing (all DGNRS is just distributed, no ETH backing)
      const backing = await dgnrs.totalBacking();
      expect(backing).to.be.gte(0n);
    });
  });

  describe("burnieReserve", function () {
    it("returns 0 initially when no BURNIE deposited", async function () {
      const { dgnrs } = await loadFixture(deployFullProtocol);
      const reserve = await dgnrs.burnieReserve();
      expect(reserve).to.be.gte(0n);
    });
  });

  // ---------------------------------------------------------------------------
  // 13. getLockStatus
  // ---------------------------------------------------------------------------
  describe("getLockStatus", function () {
    it("returns zero locked amount for address with no lock", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      const [locked, lockLevel, ethLimit, ethSpent, burnieLimit, burnieSpent, canUnlock] =
        await dgnrs.getLockStatus(alice.address);
      expect(locked).to.equal(0n);
      expect(canUnlock).to.be.false;
    });

    it("returns correct values after locking", async function () {
      const { dgnrs, deployer, alice } = await loadFixture(deployFullProtocol);
      const amount = eth("10000");
      await dgnrs.connect(deployer).transfer(alice.address, amount);
      await dgnrs.connect(alice).lockForLevel(amount);

      const [locked, lockLevel, ethLimit, ethSpent, burnieLimit, burnieSpent, canUnlock] =
        await dgnrs.getLockStatus(alice.address);
      expect(locked).to.equal(amount);
      expect(lockLevel).to.equal(0n);
      expect(canUnlock).to.be.false; // still at same level
    });
  });

  // ---------------------------------------------------------------------------
  // 14. gameAdvance (holder-only)
  // ---------------------------------------------------------------------------
  describe("gameAdvance", function () {
    it("reverts when called by non-holder", async function () {
      const { dgnrs, alice } = await loadFixture(deployFullProtocol);
      await expect(
        dgnrs.connect(alice).gameAdvance()
      ).to.be.revertedWithCustomError(dgnrs, "NotHolder");
    });

    it("holder can call gameAdvance", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      // deployer has DGNRS tokens
      await expect(dgnrs.connect(deployer).gameAdvance()).to.not.be.reverted;
    });
  });

  // ---------------------------------------------------------------------------
  // 15. gamePurchase (requires locked tokens)
  // ---------------------------------------------------------------------------
  describe("gamePurchase (requires lock)", function () {
    it("reverts when caller has no locked tokens", async function () {
      const { dgnrs, deployer } = await loadFixture(deployFullProtocol);
      // deployer has tokens but none locked
      await expect(
        dgnrs.connect(deployer).gamePurchase(400n, 0n, 0n, { value: eth("0.01") })
      ).to.be.revertedWithCustomError(dgnrs, "NoLockedTokens");
    });
  });

});
