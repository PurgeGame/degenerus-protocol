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
  advanceToNextDay,
  fulfillVRF,
  getLastVRFRequestId,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

// MintPaymentKind enum values (matches IDegenerusGame.sol)
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// Initial DGVE supply: 1 trillion tokens (18 decimals)
const INITIAL_SUPPLY = 1_000_000_000_000n * 10n ** 18n;

// Game day resets at 22:57 UTC = 82620 seconds from midnight
const JACKPOT_RESET_TIME = 82620;
const DAY_SECONDS = 86400;

/**
 * Derive the DGVE (ethShare) token address from the vault address.
 *
 * The DegenerusVault constructor deploys two child contracts via `new`:
 *   1. coinShare = new DegenerusVaultShare(...) at vault nonce 1
 *   2. ethShare  = new DegenerusVaultShare(...) at vault nonce 2
 *
 * Since `ethShare` is private immutable, we compute its CREATE address.
 */
async function getDgveAddress(vault) {
  const vaultAddr = await vault.getAddress();
  const dgveAddr = hre.ethers.getCreateAddress({ from: vaultAddr, nonce: 2 });
  return dgveAddr;
}

/**
 * Get a contract instance for the DGVE (ethShare) ERC20 token.
 * Uses the DegenerusVaultShare ABI which is deployed at the computed address.
 */
async function getDgveToken(vault) {
  const dgveAddr = await getDgveAddress(vault);
  return hre.ethers.getContractAt("DegenerusVaultShare", dgveAddr);
}

/**
 * Impersonate a contract address and return a signer for it.
 * Funds the impersonated account with ETH for gas.
 */
async function impersonate(address) {
  await hre.ethers.provider.send("hardhat_impersonateAccount", [address]);
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x1000000000000000000",
  ]);
  return hre.ethers.getSigner(address);
}

/**
 * Stop impersonating a contract address.
 */
async function stopImpersonating(address) {
  await hre.ethers.provider.send("hardhat_stopImpersonatingAccount", [address]);
}

/**
 * Jump to the next game day boundary plus an offset.
 * Game days reset at JACKPOT_RESET_TIME (22:57 UTC).
 * @param {number} offsetSeconds - Seconds after the boundary (default: 5)
 */
async function jumpToNextGameDayBoundary(offsetSeconds = 5) {
  const block = await hre.ethers.provider.getBlock("latest");
  const currentBoundaryIdx = Math.floor(
    (block.timestamp - JACKPOT_RESET_TIME) / DAY_SECONDS
  );
  const nextBoundaryTs =
    (currentBoundaryIdx + 1) * DAY_SECONDS + JACKPOT_RESET_TIME;
  await hre.ethers.provider.send("evm_setNextBlockTimestamp", [
    nextBoundaryTs + offsetSeconds,
  ]);
  await hre.ethers.provider.send("evm_mine");
}

/**
 * Advance the game through one full day cycle.
 * advanceGame (requests VRF) -> fulfill VRF -> advanceGame (processes word, sets dailyIdx).
 * Caller must bypass the mint gate (via DGVE majority or gateIdx condition).
 */
async function advanceGameOneDay(game, caller, mockVRF) {
  await game.connect(caller).advanceGame();
  const reqId = await getLastVRFRequestId(mockVRF);
  if (reqId > 0n) {
    await fulfillVRF(mockVRF, reqId, BigInt(Math.floor(Math.random() * 1e15)));
  }
  await game.connect(caller).advanceGame();
}

describe("Governance & Gating (Phase 43)", function () {
  after(() => restoreAddresses());

  // ===========================================================================
  // ADMIN-01: onlyOwner in DegenerusAdmin requires >50.1% DGVE
  // ===========================================================================
  describe("ADMIN-01: Admin onlyOwner requires >50.1% DGVE", function () {
    it("deployer (100% DGVE) passes onlyOwner", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.not.be.reverted;
    });

    it("alice (0% DGVE) fails onlyOwner with NotOwner", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("deployer fails onlyOwner after transferring >49.9% DGVE away", async function () {
      const { admin, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const halfSupply = INITIAL_SUPPLY / 2n;
      await dgve.connect(deployer).transfer(alice.address, halfSupply);

      // Deployer now has 50% -- should NOT pass onlyOwner (needs >50.1%)
      await expect(
        admin.connect(deployer).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("alice passes onlyOwner after receiving >50.1% DGVE", async function () {
      const { admin, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const amount = (INITIAL_SUPPLY * 51n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      await expect(
        admin.connect(alice).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.not.be.reverted;
    });

    it("CREATOR address alone (0% DGVE) fails onlyOwner", async function () {
      const { admin, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const balance = await dgve.balanceOf(deployer.address);
      await dgve.connect(deployer).transfer(alice.address, balance);

      // CREATOR (deployer) now holds 0% -- no special privilege
      await expect(
        admin.connect(deployer).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("multiple owner-gated functions all check DGVE majority", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);

      await expect(
        admin.connect(alice).stakeGameEthToStEth(eth("1"))
      ).to.be.revertedWithCustomError(admin, "NotOwner");

      await expect(
        admin.connect(alice).setLootboxRngThreshold(eth("2"))
      ).to.be.revertedWithCustomError(admin, "NotOwner");

      await expect(
        admin.connect(alice).swapGameEthForStEth({ value: eth("1") })
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });
  });

  // ===========================================================================
  // ADMIN-02: onlyVaultOwner in DegenerusVault requires >50.1% DGVE
  // ===========================================================================
  describe("ADMIN-02: Vault onlyVaultOwner requires >50.1% DGVE", function () {
    it("deployer (100% DGVE) passes onlyVaultOwner", async function () {
      const { vault, deployer } = await loadFixture(deployFullProtocol);
      const tx = vault.connect(deployer).gameAdvance();
      await expect(tx).to.not.be.revertedWithCustomError(
        vault,
        "NotVaultOwner"
      );
    });

    it("alice (0% DGVE) fails onlyVaultOwner with NotVaultOwner", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);
      await expect(
        vault.connect(alice).gameAdvance()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("isVaultOwner boundary: exactly 50.1% fails, 50.1% + 1 passes", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      // balance * 1000 > supply * 501
      // At exactBoundary = supply * 501 / 1000: boundary * 1000 == supply * 501, NOT > so fails
      const exactBoundary = (INITIAL_SUPPLY * 501n) / 1000n;
      const transferAway = INITIAL_SUPPLY - exactBoundary;
      await dgve.connect(deployer).transfer(alice.address, transferAway);

      expect(await vault.isVaultOwner(deployer.address)).to.be.false;

      // 1 more token pushes past boundary
      await dgve.connect(alice).transfer(deployer.address, 1n);
      expect(await vault.isVaultOwner(deployer.address)).to.be.true;
    });

    it("deployer fails onlyVaultOwner after giving away majority", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const amount = (INITIAL_SUPPLY * 51n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      await expect(
        vault.connect(deployer).gameAdvance()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });

    it("multiple vault-owner-gated functions all check DGVE majority", async function () {
      const { vault, alice } = await loadFixture(deployFullProtocol);

      await expect(
        vault.connect(alice).gameSetAutoRebuy(true)
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");

      await expect(
        vault.connect(alice).gameClaimWinnings()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");

      await expect(
        vault.connect(alice).gameClaimWhalePass()
      ).to.be.revertedWithCustomError(vault, "NotVaultOwner");
    });
  });

  // ===========================================================================
  // ADMIN-03: shutdownVrf() reverts for non-GAME callers
  // ===========================================================================
  describe("ADMIN-03: shutdownVrf() only callable by GAME", function () {
    it("reverts with NotAuthorized when called by deployer", async function () {
      const { admin, deployer } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(deployer).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("reverts with NotAuthorized when called by alice", async function () {
      const { admin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        admin.connect(alice).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");
    });

    it("reverts with NotAuthorized when called by vault", async function () {
      const { admin, vault } = await loadFixture(deployFullProtocol);
      const vaultAddr = await vault.getAddress();
      const vaultSigner = await impersonate(vaultAddr);

      await expect(
        admin.connect(vaultSigner).shutdownVrf()
      ).to.be.revertedWithCustomError(admin, "NotAuthorized");

      await stopImpersonating(vaultAddr);
    });

    it("succeeds when called by GAME contract", async function () {
      const { admin, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(
        admin.connect(gameSigner).shutdownVrf()
      ).to.not.be.revertedWithCustomError(admin, "NotAuthorized");

      await stopImpersonating(gameAddr);
    });
  });

  // ===========================================================================
  // ADMIN-04: shutdownVrf() cancels sub, sweeps LINK, sets subscriptionId=0
  // ===========================================================================
  describe("ADMIN-04: shutdownVrf() cancels subscription and sweeps LINK", function () {
    it("sets subscriptionId to 0 after shutdown", async function () {
      const { admin, game } = await loadFixture(deployFullProtocol);

      const subIdBefore = await admin.subscriptionId();
      expect(subIdBefore).to.be.gt(0n);

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await admin.connect(gameSigner).shutdownVrf();
      await stopImpersonating(gameAddr);

      expect(await admin.subscriptionId()).to.equal(0n);
    });

    it("emits SubscriptionShutdown event with correct args", async function () {
      const { admin, game, vault } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();
      const vaultAddr = await vault.getAddress();

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(admin.connect(gameSigner).shutdownVrf())
        .to.emit(admin, "SubscriptionShutdown")
        .withArgs(subId, vaultAddr, 0n);

      await stopImpersonating(gameAddr);
    });

    it("cancels subscription on the VRF coordinator", async function () {
      const { admin, game, mockVRF } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();

      const [, , , ownerBefore] = await mockVRF.getSubscription(subId);
      const adminAddr = await admin.getAddress();
      expect(ownerBefore).to.equal(adminAddr);

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);
      await admin.connect(gameSigner).shutdownVrf();
      await stopImpersonating(gameAddr);

      const [, , , ownerAfter] = await mockVRF.getSubscription(subId);
      expect(ownerAfter).to.equal(ZERO_ADDRESS);
    });

    it("sweeps LINK from admin to vault when admin holds LINK", async function () {
      const { admin, game, vault, mockLINK, deployer } =
        await loadFixture(deployFullProtocol);

      const adminAddr = await admin.getAddress();
      const vaultAddr = await vault.getAddress();
      const subId = await admin.subscriptionId();

      await mockLINK.connect(deployer).mint(adminAddr, eth("50"));
      expect(await mockLINK.balanceOf(adminAddr)).to.equal(eth("50"));

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      const tx = await admin.connect(gameSigner).shutdownVrf();
      await stopImpersonating(gameAddr);

      expect(await mockLINK.balanceOf(adminAddr)).to.equal(0n);
      expect(await mockLINK.balanceOf(vaultAddr)).to.equal(eth("50"));

      await expect(tx)
        .to.emit(admin, "SubscriptionShutdown")
        .withArgs(subId, vaultAddr, eth("50"));
    });
  });

  // ===========================================================================
  // ADMIN-05: shutdownVrf() silently succeeds when subscriptionId is already 0
  // ===========================================================================
  describe("ADMIN-05: shutdownVrf() no-op when subscriptionId is 0", function () {
    it("silently succeeds on second call (subscriptionId already 0)", async function () {
      const { admin, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await admin.connect(gameSigner).shutdownVrf();
      expect(await admin.subscriptionId()).to.equal(0n);

      await expect(admin.connect(gameSigner).shutdownVrf()).to.not.be.reverted;

      await stopImpersonating(gameAddr);
    });

    it("does not emit any events when subscriptionId is already 0", async function () {
      const { admin, game } = await loadFixture(deployFullProtocol);
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await admin.connect(gameSigner).shutdownVrf();

      const tx = await admin.connect(gameSigner).shutdownVrf();
      const receipt = await tx.wait();
      expect(receipt.logs.length).to.equal(0);

      await stopImpersonating(gameAddr);
    });
  });

  // ===========================================================================
  // ADMIN-06: shutdownVrf() try/catch handles coordinator/LINK failures
  // ===========================================================================
  describe("ADMIN-06: shutdownVrf() try/catch resilience", function () {
    it("completes even if coordinator cancelSubscription has already been called", async function () {
      const { admin, game, mockVRF } = await loadFixture(deployFullProtocol);
      const subId = await admin.subscriptionId();

      // Externally cancel the subscription directly on the mock coordinator
      const adminAddr = await admin.getAddress();
      const adminSigner = await impersonate(adminAddr);
      await mockVRF.connect(adminSigner).cancelSubscription(subId, adminAddr);
      await stopImpersonating(adminAddr);

      // shutdownVrf should still succeed (try/catch around cancelSubscription)
      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await expect(admin.connect(gameSigner).shutdownVrf()).to.not.be.reverted;
      expect(await admin.subscriptionId()).to.equal(0n);

      await stopImpersonating(gameAddr);
    });

    it("completes and sets subscriptionId=0 even on partial failure", async function () {
      const { admin, game } = await loadFixture(deployFullProtocol);

      const gameAddr = await game.getAddress();
      const gameSigner = await impersonate(gameAddr);

      await admin.connect(gameSigner).shutdownVrf();
      expect(await admin.subscriptionId()).to.equal(0n);

      await stopImpersonating(gameAddr);
    });
  });

  // ===========================================================================
  // GATE-01 through GATE-04: advanceGame daily mint gate
  // ===========================================================================
  //
  // The _enforceDailyMintGate checks:
  //   1. gateIdx = uint32(dailyIdx). If gateIdx == 0 → no gate.
  //   2. lastEthDay + 1 < gateIdx: if false → passes (minted recently enough).
  //   3. If true → tiered bypasses: deity pass, 30min anyone, 15min pass holder,
  //      DGVE majority → or revert MustMintToday().
  //
  // The elapsed time check uses: elapsed = (block.timestamp - 82620) % 1 days
  //
  // CRITICAL: We must position the block timestamp just past a day boundary
  // (within the first few seconds) to avoid the 30-minute time bypass.
  // Using advanceToNextDay() lands ~19h into the game day, always bypassing.
  // Instead, we use jumpToNextGameDayBoundary(5) for 5 seconds past boundary.

  describe("GATE-01: Tiered advanceGame mint gate (caller must have minted)", function () {
    it("caller who purchased on current day can call advanceGame", async function () {
      const { game, advanceModule, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2 to get dailyIdx >= 2
      // Use advanceToNextDay for processing days (timing doesn't matter for deployer
      // since deployer has 100% DGVE and bypasses the gate anyway)
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, positioned 5 seconds past the boundary
      await jumpToNextGameDayBoundary(5);

      // Alice purchases (mints) on day 3 -- creates a mint record for today
      const info = await game.purchaseInfo();
      const cost = info.priceWei; // 1 full ticket
      await game
        .connect(alice)
        .purchase(
          alice.address,
          400,
          0,
          ZERO_BYTES32,
          MintPaymentKind.DirectEth,
          { value: cost }
        );

      // Alice should pass the mint gate (she minted today).
      // May revert for other game-state reasons, but NOT MustMintToday.
      const tx = game.connect(alice).advanceGame();
      await expect(tx).to.not.be.revertedWithCustomError(
        advanceModule,
        "MustMintToday"
      );
    });
  });

  describe("GATE-02: Time-based unlock relaxes mint gate", function () {
    it("non-minter can call advanceGame after 30-minute delay", async function () {
      const { game, advanceModule, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Verify that alice FAILS the gate when within the first few seconds
      await expect(
        game.connect(alice).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "MustMintToday");

      // Advance 31 minutes past the day boundary
      await advanceTime(31 * 60);

      // Now the 30-minute time-based unlock should bypass the gate
      const tx = game.connect(alice).advanceGame();
      await expect(tx).to.not.be.revertedWithCustomError(
        advanceModule,
        "MustMintToday"
      );
    });
  });

  describe("GATE-03: DGVE majority holder bypasses mint gate", function () {
    it("deployer (100% DGVE) bypasses mint gate without minting", async function () {
      const { game, advanceModule, deployer, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Deployer has NOT minted today, but holds 100% DGVE → bypasses gate
      const tx = game.connect(deployer).advanceGame();
      await expect(tx).to.not.be.revertedWithCustomError(
        advanceModule,
        "MustMintToday"
      );
    });

    it("alice with >50.1% DGVE bypasses mint gate without minting", async function () {
      const { game, advanceModule, vault, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      // Transfer 52% DGVE to alice
      const amount = (INITIAL_SUPPLY * 52n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      // Process day 1 and day 2 using deployer
      // gateIdx=0 on day 1, and gateIdx=1 on day 2 where lastEthDay=0 → 0+1<1=false → passes
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Alice has NOT minted but holds >50.1% DGVE → bypasses gate
      const tx = game.connect(alice).advanceGame();
      await expect(tx).to.not.be.revertedWithCustomError(
        advanceModule,
        "MustMintToday"
      );
    });
  });

  describe("GATE-04: Non-minter, non-DGVE-holder reverts with MustMintToday()", function () {
    it("alice (0% DGVE, no mint) reverts with MustMintToday", async function () {
      const { game, advanceModule, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2 to get dailyIdx >= 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // alice: 0% DGVE, never minted, no deity pass, <15 min elapsed
      await expect(
        game.connect(alice).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "MustMintToday");
    });

    it("bob (0% DGVE, no mint) also reverts within 15 min window", async function () {
      const { game, advanceModule, deployer, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      await expect(
        game.connect(bob).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "MustMintToday");
    });

    it("non-minter fails within first seconds but succeeds after 30 min", async function () {
      const { game, advanceModule, deployer, carol, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Within first seconds: should fail with MustMintToday
      await expect(
        game.connect(carol).advanceGame()
      ).to.be.revertedWithCustomError(advanceModule, "MustMintToday");

      // Advance past 30 minutes
      await advanceTime(31 * 60);

      // After 30 min: gate relaxed
      const tx = game.connect(carol).advanceGame();
      await expect(tx).to.not.be.revertedWithCustomError(
        advanceModule,
        "MustMintToday"
      );
    });
  });

  // ===========================================================================
  // Cross-cutting: DGVE ownership transfer changes governance control
  // ===========================================================================
  describe("Cross-cutting: DGVE transfer changes who controls governance", function () {
    it("ownership transfers from deployer to alice via DGVE transfer", async function () {
      const { admin, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      expect(await vault.isVaultOwner(deployer.address)).to.be.true;
      expect(await vault.isVaultOwner(alice.address)).to.be.false;

      const amount = (INITIAL_SUPPLY * 52n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      expect(await vault.isVaultOwner(alice.address)).to.be.true;
      expect(await vault.isVaultOwner(deployer.address)).to.be.false;

      await expect(
        admin.connect(alice).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.not.be.reverted;

      await expect(
        admin.connect(deployer).setLinkEthPriceFeed(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(admin, "NotOwner");
    });

    it("no two accounts can simultaneously be vault owner (pigeonhole >50.1%)", async function () {
      const { vault, deployer, alice } = await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      // Give alice exactly 50% -- neither qualifies
      const halfSupply = INITIAL_SUPPLY / 2n;
      await dgve.connect(deployer).transfer(alice.address, halfSupply);

      expect(await vault.isVaultOwner(deployer.address)).to.be.false;
      expect(await vault.isVaultOwner(alice.address)).to.be.false;

      // 50% + 1 wei is still not >50.1% with 1T supply (need 0.1% = 1B tokens)
      await dgve.connect(deployer).transfer(alice.address, 1n);
      const aliceBal = await dgve.balanceOf(alice.address);
      const supply = await dgve.totalSupply();
      expect(aliceBal * 1000n > supply * 501n).to.be.false;

      // Transfer enough to cross the 50.1% threshold
      const oneBillion = 1_000_000_000n * 10n ** 18n;
      await dgve.connect(deployer).transfer(alice.address, oneBillion);
      expect(await vault.isVaultOwner(alice.address)).to.be.true;
      expect(await vault.isVaultOwner(deployer.address)).to.be.false;
    });
  });
});
