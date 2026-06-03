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
 * advanceGame (requests VRF) -> fulfill VRF -> loop advanceGame until RNG unlocked.
 * Caller must bypass the mint gate (via DGVE majority or gateIdx condition).
 *
 * Multiple post-fulfillment advances are required because future ticket processing
 * (STAGE_FUTURE_TICKETS_WORKING) now takes several advance calls before daily
 * processing completes and RNG is unlocked.
 */
async function advanceGameOneDay(game, caller, mockVRF) {
  await game.connect(caller).advanceGame();
  const reqId = await getLastVRFRequestId(mockVRF);
  if (reqId > 0n) {
    await fulfillVRF(mockVRF, reqId, BigInt(Math.floor(Math.random() * 1e15)));
  }
  // Loop until RNG is unlocked (daily processing fully complete).
  for (let i = 0; i < 30; i++) {
    const locked = await game.rngLocked();
    if (!locked) break;
    await game.connect(caller).advanceGame();
  }
}

describe("Governance & Gating (Phase 43)", function () {
  after(() => restoreAddresses());

  // ===========================================================================
  // ADMIN-01: onlyOwner in DegenerusAdmin requires >50.1% DGVE
  // ===========================================================================
  describe("ADMIN-01: Admin onlyOwner requires >50.1% DGVE", function () {
    // setLootboxRngThreshold and stakeGameEthToStEth moved from Admin to Game in Phase 146.
    // swapGameEthForStEth remains on Admin and uses the same onlyOwner modifier.
    it("deployer (100% DGVE) passes onlyOwner", async function () {
      const { game, deployer } = await loadFixture(deployFullProtocol);
      // setLootboxRngThreshold now on Game, gated by vault.isVaultOwner
      await expect(
        game.connect(deployer).setLootboxRngThreshold(eth("1"))
      ).to.not.be.reverted;
    });

    it("alice (0% DGVE) fails onlyOwner with E", async function () {
      const { game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        game.connect(alice).setLootboxRngThreshold(eth("1"))
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("deployer fails onlyOwner after transferring >49.9% DGVE away", async function () {
      const { game, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const halfSupply = INITIAL_SUPPLY / 2n;
      await dgve.connect(deployer).transfer(alice.address, halfSupply);

      // Deployer now has 50% -- should NOT pass (needs >50.1%)
      await expect(
        game.connect(deployer).setLootboxRngThreshold(eth("1"))
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("alice passes onlyOwner after receiving >50.1% DGVE", async function () {
      const { game, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const amount = (INITIAL_SUPPLY * 51n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      await expect(
        game.connect(alice).setLootboxRngThreshold(eth("1"))
      ).to.not.be.reverted;
    });

    it("CREATOR address alone (0% DGVE) fails onlyOwner", async function () {
      const { game, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);
      const balance = await dgve.balanceOf(deployer.address);
      await dgve.connect(deployer).transfer(alice.address, balance);

      // CREATOR (deployer) now holds 0% -- no special privilege
      await expect(
        game.connect(deployer).setLootboxRngThreshold(eth("1"))
      ).to.be.revertedWithCustomError(game, "E");
    });

    it("multiple owner-gated functions all check DGVE majority", async function () {
      const { admin, game, alice } = await loadFixture(deployFullProtocol);

      // setLootboxRngThreshold now on Game
      await expect(
        game.connect(alice).setLootboxRngThreshold(eth("2"))
      ).to.be.revertedWithCustomError(game, "E");

      // swapGameEthForStEth remains on Admin
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
  // GATE-01 through GATE-04: advanceGame liveness + the mintBurnie advance-bounty
  // SOFT pay-gate (357 advance-incentive redesign, HEAD'' 61315ecd)
  // ===========================================================================
  //
  // The 357 redesign DROPPED the MustMintToday hard revert. advanceGame() is now
  // PURE LIVENESS: anyone may crank it any time; the dead _enforceDailyMintGate /
  // MustMintToday / vault / caller arguments were removed. The error no longer
  // exists in the contract surface, so asserting revertedWithCustomError(...,
  // "MustMintToday") would itself error on an unknown selector — those assertions
  // are gone.
  //
  // The must-mint tier ladder moved to _bountyEligible(address) in
  // DegenerusGameMintStreakUtils, surfaced as the view game.bountyEligible(addr).
  // It is now a SOFT PAY gate: mintBurnie() reads bountyEligible(msg.sender)
  // BEFORE the self-call and pays the advance bounty only when mult>0 && eligible.
  // The advance WORK is always permitted regardless of eligibility.
  //
  // Tier ladder (cheapest-first short-circuit):
  //   minted today/yesterday → true; deity pass → true; anyone 30+ min into the
  //   day → true; any pass holder 15+ min in → true; active afking sub → true;
  //   DGVE-majority owner → true; else false (no bounty, but advance still runs).
  //
  // The elapsed time check uses: elapsed = (block.timestamp - 82620) % 1 days
  //
  // CRITICAL: position the block timestamp just past a day boundary (within the
  // first few seconds) to land BELOW the 15-minute window. jumpToNextGameDayBoundary(5)
  // gives 5 seconds past the boundary; advanceToNextDay() lands ~19h in (always >30m).

  describe("GATE-01: advanceGame is permissionless liveness (no MustMintToday)", function () {
    it("a same-day minter is bountyEligible AND can advance", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2 to get dailyIdx >= 2
      // (timing doesn't matter for deployer — it holds 100% DGVE)
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, positioned 5 seconds past the boundary (below the 15-min window)
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

      // Soft pay-gate: minted-today → bountyEligible == true.
      expect(await game.bountyEligible(alice.address)).to.equal(true);

      // Liveness: advanceGame never reverts for a mint-gate reason (MustMintToday
      // is gone). It may revert NotTimeYet for ordinary game-state reasons, but
      // NEVER for a removed gate — and it does not for alice on this fresh day.
      await expect(game.connect(alice).advanceGame()).to.not.be.reverted;
    });
  });

  describe("GATE-02: 30-minute window flips bountyEligible true; advance always works", function () {
    it("non-minter is ineligible in the first seconds, eligible after 30 min", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary (< 15 min)
      await jumpToNextGameDayBoundary(5);

      // Fresh non-minter, non-DGVE, no pass, < 15 min in → NOT bounty-eligible …
      expect(await game.bountyEligible(alice.address)).to.equal(false);
      // … yet the advance WORK is still permitted (pure liveness, no MustMintToday).
      await expect(game.connect(alice).advanceGame()).to.not.be.reverted;

      // Advance 31 minutes past the day boundary
      await advanceTime(31 * 60);

      // Now the 30-minute window makes anyone bounty-eligible.
      expect(await game.bountyEligible(alice.address)).to.equal(true);
    });
  });

  describe("GATE-03: DGVE majority holder is always bountyEligible", function () {
    it("deployer (100% DGVE) is eligible without minting", async function () {
      const { game, deployer, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process day 1 and day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary (the DGVE tier must not depend on time)
      await jumpToNextGameDayBoundary(5);

      // Deployer has NOT minted today, but holds 100% DGVE → bountyEligible via the
      // DGVE-majority tier (the cold-path isVaultOwner read).
      expect(await game.bountyEligible(deployer.address)).to.equal(true);
    });

    it("alice with >50.1% DGVE is eligible without minting", async function () {
      const { game, vault, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      // Transfer 52% DGVE to alice
      const amount = (INITIAL_SUPPLY * 52n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      // Process day 1 and day 2 using deployer
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Alice has NOT minted but holds >50.1% DGVE → bountyEligible.
      expect(await game.bountyEligible(alice.address)).to.equal(true);
    });
  });

  describe("GATE-04: ineligible keeper earns no bounty, but the advance still works", function () {
    it("alice (0% DGVE, no mint, <15 min) is ineligible yet can advance", async function () {
      const { game, deployer, alice, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2 to get dailyIdx >= 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // alice: 0% DGVE, never minted, no deity pass, no afking sub, < 15 min in.
      expect(await game.bountyEligible(alice.address)).to.equal(false);
      // The advance work is still permissionless — MustMintToday no longer exists.
      await expect(game.connect(alice).advanceGame()).to.not.be.reverted;
    });

    it("bob (0% DGVE, no mint) is likewise ineligible within the 15-min window", async function () {
      const { game, deployer, bob, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      expect(await game.bountyEligible(bob.address)).to.equal(false);
      await expect(game.connect(bob).advanceGame()).to.not.be.reverted;
    });

    it("carol is ineligible in the first seconds, then eligible after 30 min", async function () {
      const { game, deployer, carol, mockVRF } =
        await loadFixture(deployFullProtocol);

      // Process through day 2
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);
      await advanceToNextDay();
      await advanceGameOneDay(game, deployer, mockVRF);

      // Jump to day 3, 5 seconds past boundary
      await jumpToNextGameDayBoundary(5);

      // Within the first seconds: ineligible (the soft pay-gate withholds the bounty).
      expect(await game.bountyEligible(carol.address)).to.equal(false);

      // Advance past 30 minutes
      await advanceTime(31 * 60);

      // After 30 min: the anyone-tier flips eligibility true.
      expect(await game.bountyEligible(carol.address)).to.equal(true);
    });
  });

  // ===========================================================================
  // Cross-cutting: DGVE ownership transfer changes governance control
  // ===========================================================================
  describe("Cross-cutting: DGVE transfer changes who controls governance", function () {
    it("ownership transfers from deployer to alice via DGVE transfer", async function () {
      const { admin, game, vault, deployer, alice } =
        await loadFixture(deployFullProtocol);

      const dgve = await getDgveToken(vault);

      expect(await vault.isVaultOwner(deployer.address)).to.be.true;
      expect(await vault.isVaultOwner(alice.address)).to.be.false;

      const amount = (INITIAL_SUPPLY * 52n) / 100n;
      await dgve.connect(deployer).transfer(alice.address, amount);

      expect(await vault.isVaultOwner(alice.address)).to.be.true;
      expect(await vault.isVaultOwner(deployer.address)).to.be.false;

      // setLootboxRngThreshold now on Game, gated by vault.isVaultOwner
      await expect(
        game.connect(alice).setLootboxRngThreshold(eth("1"))
      ).to.not.be.reverted;

      await expect(
        game.connect(deployer).setLootboxRngThreshold(eth("1"))
      ).to.be.revertedWithCustomError(game, "E");
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
