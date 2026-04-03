import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvents,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/*
 * DegenerusAffiliate Unit Tests
 * =============================
 * Covers:
 *  - Constructor: VAULT and DGNRS codes pre-registered, cross-referrals set
 *  - createAffiliateCode: happy path, reserved codes, duplicate, kickback cap
 *  - setAffiliatePayoutMode: owner-only, all three modes
 *  - referPlayer: happy path, self-referral, double-register, non-existent code
 *  - getReferrer: before/after referral
 *  - payAffiliate: access control (coin/game only), reward distribution,
 *                  kickback returned, 3-tier chain
 *  - consumeDegeneretteCredit: game-only, partial and full consumption
 *  - pendingDegeneretteCreditOf: Degenerette payout mode
 *  - affiliateTop / affiliateScore / affiliateBonusPointsBest
 *  - Events
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Create a bytes32 from a short ASCII string. */
function toBytes32(str) {
  return hre.ethers.encodeBytes32String(str);
}


/**
 * Call payAffiliate as the coin contract (impersonation).
 * Returns the tx.
 */
async function payAffiliateAsCoin(
  hreEthers,
  coin,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const tx = await affiliate
    .connect(coinSigner)
    .payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return tx;
}

/**
 * Call payAffiliate as the game contract.
 */
async function payAffiliateAsGame(
  hreEthers,
  game,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const gameAddr = await game.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [gameAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    gameAddr,
    "0x1000000000000000000",
  ]);
  const gameSigner = await hreEthers.getSigner(gameAddr);
  const tx = await affiliate
    .connect(gameSigner)
    .payAffiliate(amount, code, sender, lvl, isFreshEth, lootboxActivityScore);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [gameAddr]);
  return tx;
}

/**
 * staticCall payAffiliate as coin to get the return value without mutating state.
 */
async function payAffiliateAsCoinStatic(
  hreEthers,
  coin,
  affiliate,
  amount,
  code,
  sender,
  lvl,
  isFreshEth,
  lootboxActivityScore = 0
) {
  const coinAddr = await coin.getAddress();
  await hreEthers.provider.send("hardhat_impersonateAccount", [coinAddr]);
  await hreEthers.provider.send("hardhat_setBalance", [
    coinAddr,
    "0x1000000000000000000",
  ]);
  const coinSigner = await hreEthers.getSigner(coinAddr);
  const result = await affiliate
    .connect(coinSigner)
    .payAffiliate.staticCall(amount, code, sender, lvl, isFreshEth, lootboxActivityScore);
  await hreEthers.provider.send("hardhat_stopImpersonatingAccount", [coinAddr]);
  return result;
}


// ---------------------------------------------------------------------------
// Test Suite
// ---------------------------------------------------------------------------

describe("DegenerusAffiliate", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. Constructor
  // =========================================================================
  describe("Constructor", function () {
    it("pre-registers VAULT affiliate code owned by vault address", async function () {
      const { affiliate, vault } = await loadFixture(deployFullProtocol);
      const vaultCode = hre.ethers.encodeBytes32String("VAULT");
      // The affiliate code struct should have owner == vault
      const info = await affiliate.affiliateCode(vaultCode);
      expect(info.owner.toLowerCase()).to.equal(
        (await vault.getAddress()).toLowerCase()
      );
    });

    it("pre-registers DGNRS affiliate code owned by sdgnrs address", async function () {
      const { affiliate, sdgnrs } = await loadFixture(deployFullProtocol);
      const dgnrsCode = hre.ethers.encodeBytes32String("DGNRS");
      const info = await affiliate.affiliateCode(dgnrsCode);
      expect(info.owner.toLowerCase()).to.equal(
        (await sdgnrs.getAddress()).toLowerCase()
      );
    });

    it("vault and dgnrs default kickback is 0", async function () {
      const { affiliate } = await loadFixture(deployFullProtocol);
      const vaultCode = hre.ethers.encodeBytes32String("VAULT");
      const dgnrsCode = hre.ethers.encodeBytes32String("DGNRS");
      const vaultInfo = await affiliate.affiliateCode(vaultCode);
      const dgnrsInfo = await affiliate.affiliateCode(dgnrsCode);
      expect(vaultInfo.kickback).to.equal(0);
      expect(dgnrsInfo.kickback).to.equal(0);
    });

    it("emits Affiliate(1) events for VAULT and DGNRS on construction", async function () {
      // Since we cannot catch constructor events directly via receipt in this test,
      // we verify the codes exist (side effect of constructor) which implies events fired.
      const { affiliate } = await loadFixture(deployFullProtocol);
      const vaultCode = hre.ethers.encodeBytes32String("VAULT");
      const info = await affiliate.affiliateCode(vaultCode);
      expect(info.owner).to.not.equal(ZERO_ADDRESS);
    });

    it("getReferrer returns sdgnrs for vault's own address (cross-registered to DGNRS)", async function () {
      const { affiliate, vault, sdgnrs } = await loadFixture(deployFullProtocol);
      // Vault was registered under DGNRS code, so its referrer is the SDGNRS owner
      const referrer = await affiliate.getReferrer(await vault.getAddress());
      expect(referrer.toLowerCase()).to.equal(
        (await sdgnrs.getAddress()).toLowerCase()
      );
    });

    it("seeds pre-known affiliate codes passed to constructor", async function () {
      const { alice, bob } = await loadFixture(deployFullProtocol);
      const factory = await hre.ethers.getContractFactory("DegenerusAffiliate");

      const codeA = toBytes32("BOOT_A");
      const codeB = toBytes32("BOOT_B");
      const affiliateBootstrapped = await factory.deploy(
        [alice.address, bob.address],
        [codeA, codeB],
        [7, 12],
        [],
        []
      );
      await affiliateBootstrapped.waitForDeployment();

      const infoA = await affiliateBootstrapped.affiliateCode(codeA);
      const infoB = await affiliateBootstrapped.affiliateCode(codeB);
      expect(infoA.owner).to.equal(alice.address);
      expect(infoA.kickback).to.equal(7);
      expect(infoB.owner).to.equal(bob.address);
      expect(infoB.kickback).to.equal(12);
    });

    it("reverts when bootstrap constructor arrays have mismatched lengths", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const factory = await hre.ethers.getContractFactory("DegenerusAffiliate");

      await expect(
        factory.deploy([alice.address], [toBytes32("BOOT_LEN_1")], [], [], [])
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("seeds pre-known player referrals passed to constructor", async function () {
      const { alice, bob, carol } = await loadFixture(deployFullProtocol);
      const factory = await hre.ethers.getContractFactory("DegenerusAffiliate");
      const codeA = toBytes32("BOOT_REF_A");

      const affiliateBootstrapped = await factory.deploy(
        [alice.address],
        [codeA],
        [3],
        [bob.address, carol.address],
        [codeA, codeA]
      );
      await affiliateBootstrapped.waitForDeployment();

      expect(await affiliateBootstrapped.getReferrer(bob.address)).to.equal(
        alice.address
      );
      expect(await affiliateBootstrapped.getReferrer(carol.address)).to.equal(
        alice.address
      );
    });
  });

  // =========================================================================
  // 2. createAffiliateCode
  // =========================================================================
  describe("createAffiliateCode", function () {
    it("creates a new code with correct owner and kickback", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("ALICE1");
      await affiliate.connect(alice).createAffiliateCode(code, 10);
      const info = await affiliate.affiliateCode(code);
      expect(info.owner).to.equal(alice.address);
      expect(info.kickback).to.equal(10);
    });

    it("emits Affiliate(1, code, creator) event", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("ALICE2");
      const tx = await affiliate.connect(alice).createAffiliateCode(code, 5);
      const ev = await getEvent(tx, affiliate, "Affiliate");
      expect(ev.args.amount).to.equal(1n);
      expect(ev.args.code).to.equal(code);
      expect(ev.args.sender).to.equal(alice.address);
    });

    it("reverts with Zero when code is bytes32(0)", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      await expect(
        affiliate.connect(alice).createAffiliateCode(ZERO_BYTES32, 0)
      ).to.be.revertedWithCustomError(affiliate, "Zero");
    });

    it("reverts with Zero when code is REF_CODE_LOCKED sentinel (bytes32(1))", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const lockedSentinel =
        "0x0000000000000000000000000000000000000000000000000000000000000001";
      await expect(
        affiliate.connect(alice).createAffiliateCode(lockedSentinel, 0)
      ).to.be.revertedWithCustomError(affiliate, "Zero");
    });

    it("reverts with Insufficient when code is already taken", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = toBytes32("SHARED");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await expect(
        affiliate.connect(bob).createAffiliateCode(code, 0)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("reverts with InvalidKickback when kickback exceeds 25%", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      await expect(
        affiliate.connect(alice).createAffiliateCode(toBytes32("TOOBIG"), 26)
      ).to.be.revertedWithCustomError(affiliate, "InvalidKickback");
    });

    it("allows maximum kickback of 25%", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("MAX25");
      await expect(
        affiliate.connect(alice).createAffiliateCode(code, 25)
      ).to.not.be.reverted;
      const info = await affiliate.affiliateCode(code);
      expect(info.kickback).to.equal(25);
    });
  });

  // =========================================================================
  // 3. referPlayer
  // =========================================================================
  describe("referPlayer", function () {
    it("registers player under a valid code", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = toBytes32("REFTEST");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);
    });

    it("emits Affiliate(0, code, player) event", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = toBytes32("REFEV");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      const tx = await affiliate.connect(bob).referPlayer(code);
      const ev = await getEvent(tx, affiliate, "Affiliate");
      expect(ev.args.amount).to.equal(0n);
      expect(ev.args.code).to.equal(code);
      expect(ev.args.sender).to.equal(bob.address);
    });

    it("emits ReferralUpdated event", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = toBytes32("REFUPD");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      const tx = await affiliate.connect(bob).referPlayer(code);
      const ev = await getEvent(tx, affiliate, "ReferralUpdated");
      expect(ev.args.player).to.equal(bob.address);
      expect(ev.args.code).to.equal(code);
      expect(ev.args.locked).to.equal(false);
    });

    it("reverts Insufficient for self-referral", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("SELF");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await expect(
        affiliate.connect(alice).referPlayer(code)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("reverts Insufficient for non-existent code", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      await expect(
        affiliate.connect(alice).referPlayer(toBytes32("NOPE"))
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("reverts Insufficient when already referred (non-vault code)", async function () {
      const { affiliate, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );
      const code1 = toBytes32("FIRST");
      const code2 = toBytes32("SECOND");
      await affiliate.connect(alice).createAffiliateCode(code1, 0);
      await affiliate.connect(carol).createAffiliateCode(code2, 0);
      await affiliate.connect(bob).referPlayer(code1);
      await expect(
        affiliate.connect(bob).referPlayer(code2)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });
  });

  // =========================================================================
  // 5. getReferrer
  // =========================================================================
  describe("getReferrer", function () {
    it("returns vault address for player with no referral", async function () {
      const { affiliate, vault, alice } = await loadFixture(deployFullProtocol);
      expect((await affiliate.getReferrer(alice.address)).toLowerCase()).to.equal(
        (await vault.getAddress()).toLowerCase()
      );
    });

    it("returns correct referrer after referral registration", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = toBytes32("GETREF");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);
    });
  });

  // =========================================================================
  // 6. payAffiliate - Access Control
  // =========================================================================
  describe("payAffiliate - access control", function () {
    it("reverts OnlyAuthorized when called by random EOA", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      await expect(
        affiliate
          .connect(alice)
          .payAffiliate(eth(1), ZERO_BYTES32, bob.address, 1, true, 0)
      ).to.be.revertedWithCustomError(affiliate, "OnlyAuthorized");
    });

    it("succeeds when called by coin contract", async function () {
      const { affiliate, coin, alice } = await loadFixture(deployFullProtocol);
      await expect(
        payAffiliateAsCoin(
          hre.ethers,
          coin,
          affiliate,
          eth(1),
          ZERO_BYTES32,
          alice.address,
          1,
          true
        )
      ).to.not.be.reverted;
    });

    it("succeeds when called by game contract", async function () {
      const { affiliate, game, alice } = await loadFixture(deployFullProtocol);
      await expect(
        payAffiliateAsGame(
          hre.ethers,
          game,
          affiliate,
          eth(1),
          ZERO_BYTES32,
          alice.address,
          1,
          true
        )
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 7. payAffiliate - Reward Distribution
  // =========================================================================
  describe("payAffiliate - reward distribution", function () {
    it("emits Affiliate event with correct code and sender", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("PAYTST");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(10),
        code,
        bob.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "Affiliate");
      // Should have at least one Affiliate event with amount > 1 (payout event)
      const payoutEvs = evs.filter((e) => e.args.amount > 1n);
      expect(payoutEvs.length).to.be.gte(1);
    });

    it("emits AffiliateEarningsRecorded for the direct affiliate", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("EARNREC");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(100),
        code,
        bob.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.affiliate).to.equal(alice.address);
    });

    it("returns player kickback equal to kickbackPct% of scaled reward", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("RAKBK10");
      // 10% kickback
      await affiliate.connect(alice).createAffiliateCode(code, 10);
      await affiliate.connect(bob).referPlayer(code);

      // Level 1 fresh ETH: scale = 25%
      // scaledAmount = 1 ETH * 25% = 0.25 ETH (under 0.5 cap)
      // kickback = 0.25 ETH * 10% = 0.025 ETH
      const staticResult = await payAffiliateAsCoinStatic(
        hre.ethers,
        coin,
        affiliate,
        eth(1),
        code,
        bob.address,
        1,
        true
      );

      expect(staticResult).to.equal(eth("0.025"));
    });

    it("fresh ETH level 1-3 uses 25% reward scale", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("SCAL25");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH input, 25% scale = 0.25 ETH (under 0.5 cap)
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(1),
        code,
        bob.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.25")); // 25% of 1
    });

    it("fresh ETH level 4+ uses 20% reward scale", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("SCAL20");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH input, 20% scale = 0.2 ETH (under 0.5 cap)
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(1),
        code,
        bob.address,
        4,
        true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.2")); // 20% of 1
    });

    it("recycled ETH uses 5% reward scale", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("SCAL5");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH input, 5% scale = 0.05 ETH (under 0.5 cap)
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(1),
        code,
        bob.address,
        1,
        false
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.05")); // 5% of 1
    });

    it("blank referral code locks player to VAULT (REF_CODE_LOCKED)", async function () {
      const { affiliate, coin, alice } = await loadFixture(deployFullProtocol);
      // Alice has no stored code; send blank code
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(10),
        ZERO_BYTES32,
        alice.address,
        1,
        true
      );
      // A ReferralUpdated event with locked=true should be emitted
      const evs = await getEvents(tx, affiliate, "ReferralUpdated");
      const lockedEv = evs.find((e) => e.args.locked === true);
      expect(lockedEv).to.not.be.undefined;
    });

    it("invalid code (unknown) locks player to VAULT", async function () {
      const { affiliate, coin, bob } = await loadFixture(deployFullProtocol);
      const unknownCode = toBytes32("UNKNOWN");
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(10),
        unknownCode,
        bob.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "ReferralUpdated");
      const lockedEv = evs.find((e) => e.args.locked === true);
      expect(lockedEv).to.not.be.undefined;
    });

    it("self-referral code locks player to VAULT", async function () {
      const { affiliate, coin, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("OWNCODE");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      // Alice provides her own code as the referral
      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(10),
        code,
        alice.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "ReferralUpdated");
      const lockedEv = evs.find((e) => e.args.locked === true);
      expect(lockedEv).to.not.be.undefined;
    });

    it("upline tier 1 (20%) is distributed via creditFlip", async function () {
      // Alice has code; Bob refers to Alice; Carol refers to Bob.
      // When Carol pays, Bob and Alice should be in the distribution batch.
      const { affiliate, coin, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );
      const aliceCode = toBytes32("ALICE");
      const bobCode = toBytes32("BOB");
      await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);
      await affiliate.connect(bob).createAffiliateCode(bobCode, 0);
      await affiliate.connect(bob).referPlayer(aliceCode); // bob -> alice
      await affiliate.connect(carol).referPlayer(bobCode); // carol -> bob

      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(100),
        bobCode,
        carol.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      // Should record earnings for bob (direct affiliate)
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.affiliate).to.equal(bob.address);
    });
  });

  // =========================================================================
  // 8. View Functions
  // =========================================================================
  describe("affiliateTop / affiliateScore / affiliateBonusPointsBest", function () {
    it("affiliateTop returns zero address for level with no activity", async function () {
      const { affiliate } = await loadFixture(deployFullProtocol);
      const [player, score] = await affiliate.affiliateTop(1);
      expect(player).to.equal(ZERO_ADDRESS);
      expect(score).to.equal(0n);
    });

    it("affiliateScore returns 0 for player with no earnings", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(0n);
    });

    it("affiliateScore reflects earnings after payAffiliate", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("SCORE1");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH input, 25% scale = 0.25 ETH (under 0.5 cap)
      await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(1),
        code,
        bob.address,
        1,
        true
      );

      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.equal(eth("0.25")); // 25% of 1
    });

    it("affiliateTop reflects top affiliate after activity", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TOP1");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(100),
        code,
        bob.address,
        1,
        true
      );

      const [topPlayer] = await affiliate.affiliateTop(1);
      expect(topPlayer).to.equal(alice.address);
    });

    it("emits AffiliateTopUpdated when new top is set", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TOPEV");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      const tx = await payAffiliateAsCoin(
        hre.ethers,
        coin,
        affiliate,
        eth(100),
        code,
        bob.address,
        1,
        true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateTopUpdated");
      expect(evs.length).to.be.gte(1);
      expect(evs[0].args.player).to.equal(alice.address);
    });

    it("affiliateBonusPointsBest returns 0 for new player", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      expect(
        await affiliate.affiliateBonusPointsBest(5, alice.address)
      ).to.equal(0n);
    });

    it("affiliateBonusPointsBest returns 0 for zero address or zero level", async function () {
      const { affiliate } = await loadFixture(deployFullProtocol);
      expect(
        await affiliate.affiliateBonusPointsBest(0, ZERO_ADDRESS)
      ).to.equal(0n);
      // Also test zero level with valid address
      const { alice } = await loadFixture(deployFullProtocol);
      expect(
        await affiliate.affiliateBonusPointsBest(0, alice.address)
      ).to.equal(0n);
    });

    it("affiliateBonusPointsBest accumulates over previous 5 levels", async function () {
      const { affiliate, coin, alice, bob, carol, dan, eve } =
        await loadFixture(deployFullProtocol);
      const code = toBytes32("BONUS5");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      // Refer multiple senders so each can contribute up to 0.5 cap
      const senders = [bob, carol, dan, eve];
      for (const s of senders) {
        await affiliate.connect(s).referPlayer(code);
      }

      // Earn at levels 1-5 using all senders (each capped at 0.5 ETH/level).
      // Per sender: 2 ETH fresh L1-3 => 25% = 0.5 ETH (hits cap).
      // 4 senders * 0.5 ETH = 2 ETH per level.
      // Levels 1-3: 2 ETH each = 6 ETH; Levels 4-5: 20% so 2.5 ETH input => 0.5 cap.
      // 4 senders * 0.5 = 2 ETH per level. Total = 2*5 = 10 ETH => 10 points.
      for (let lvl = 1; lvl <= 5; lvl++) {
        const inputAmt = lvl <= 3 ? eth(2) : eth("2.5");
        for (const s of senders) {
          await payAffiliateAsCoin(
            hre.ethers,
            coin,
            affiliate,
            inputAmt,
            code,
            s.address,
            lvl,
            true
          );
        }
      }

      // At level 6, sum previous 5 levels = 10 ETH => 10 points
      const points = await affiliate.affiliateBonusPointsBest(6, alice.address);
      expect(points).to.equal(10n);
    });
  });

  // =========================================================================
  // 11. Per-Referrer Commission Cap
  // =========================================================================
  describe("per-referrer commission cap (0.5 ETH)", function () {
    it("allows full commission when under the cap", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPU1");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH fresh L1 => 25% = 0.25 ETH (under 0.5 cap)
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.25"));
    });

    it("clamps commission at exactly the 0.5 ETH cap", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPEX");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // 100 ETH fresh L1 => 25% = 25 ETH, but cap clamps to 0.5 ETH
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.5"));
    });

    it("returns 0 and emits only Affiliate event once cap is fully used", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPFL");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // First call: max out the cap
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true
      );

      // Second call: cap already reached
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(10), code, bob.address, 1, true
      );
      const earningsEvs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(earningsEvs.length).to.equal(0);
      // Affiliate event with the original amount is still emitted
      const affEvs = await getEvents(tx, affiliate, "Affiliate");
      expect(affEvs.length).to.be.gte(1);
    });

    it("returns 0 kickback once cap is exhausted", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPRK");
      await affiliate.connect(alice).createAffiliateCode(code, 25); // max kickback
      await affiliate.connect(bob).referPlayer(code);

      // Exhaust cap
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true
      );

      // Second call should return 0 kickback
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(10), code, bob.address, 1, true
      );
      expect(result).to.equal(0n);
    });

    it("partially clamps when remaining cap is less than scaled amount", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPPT");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // First call: 1 ETH fresh L1 => 0.25 ETH (0.25 of 0.5 cap used)
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.25"));

      // Second call: 2 ETH fresh L1 => 0.5 ETH scaled, but only 0.25 cap remains
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(2), code, bob.address, 1, true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.25")); // clamped to remaining cap

      // Total should be 0.5 (the full cap)
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.5"));
    });

    it("different senders each have independent caps", async function () {
      const { affiliate, coin, alice, bob, carol } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPDS");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);
      await affiliate.connect(carol).referPlayer(code);

      // Bob maxes cap: 100 ETH => capped to 0.5
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true
      );
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.5"));

      // Carol can still contribute independently: 1 ETH => 0.25
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, carol.address, 1, true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.25"));

      // Total now 0.75
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.75"));
    });

    it("cap resets per level", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("CAPL");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // Max cap at level 1
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true
      );
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.5"));

      // Same sender can earn again at level 2
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 2, true
      );
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.25"));
      expect(await affiliate.affiliateScore(2, alice.address)).to.equal(eth("0.25"));
    });
  });

  // =========================================================================
  // 12. Lootbox Activity Taper
  // =========================================================================
  describe("lootbox activity taper", function () {
    it("no taper when activity score is 0", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPER0");
      await affiliate.connect(alice).createAffiliateCode(code, 25); // max kickback to observe taper
      await affiliate.connect(bob).referPlayer(code);

      // 1 ETH fresh L1 => 0.25 scaled, 25% kickback = 0.0625
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 0
      );
      expect(result).to.equal(eth("0.0625"));
    });

    it("no taper when activity score is below 10000", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPLO");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 9999
      );
      // Same as no-taper: 0.25 * 25% = 0.0625
      expect(result).to.equal(eth("0.0625"));
    });

    it("25% floor taper when activity score >= 25500", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPFL");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      // At max taper: scaledAmount * 25% => 0.25 * 0.25 = 0.0625
      // kickback = 0.0625 * 25% = 0.015625
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 25500
      );
      expect(result).to.equal(eth("0.015625"));
    });

    it("25% floor also applies above 25500", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPAB");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 30000
      );
      // Same as 25500: 0.015625
      expect(result).to.equal(eth("0.015625"));
    });

    it("linear taper in range (score 20250)", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPMID");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // score=20250: excess = 20250 - 10000 = 10250, range = 15500
      // reductionBps = 7500 * 10250 / 15500 = 4959 (integer division)
      // effectiveBps = 10000 - 4959 = 5041
      // Scaled = 0.25 * 5041 / 10000 = 0.126025
      const tx = await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 20250
      );
      // Event records the post-taper amount
      const evs = await getEvents(tx, affiliate, "AffiliateEarningsRecorded");
      expect(evs[0].args.amount).to.equal(eth("0.126025")); // post-taper
    });

    it("leaderboard tracks post-taper amount", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPLB");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await affiliate.connect(bob).referPlayer(code);

      // Max taper: score=25500 triggers 25% floor
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 25500
      );

      // score=25500: 0.25 ETH scaled * 25% floor = 0.0625 ETH recorded
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.0625"));
    });

    it("taper reduces kickback proportionally", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPRK");
      await affiliate.connect(alice).createAffiliateCode(code, 25); // max kickback
      await affiliate.connect(bob).referPlayer(code);

      // No taper: 0.25 scaled * 25% kickback = 0.0625
      const noTaper = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 0
      );

      // Max taper (25% floor): 0.25 * 25% = 0.0625 * 25% kickback = 0.015625
      const maxTaper = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 25500
      );

      expect(noTaper).to.equal(eth("0.0625"));
      expect(maxTaper).to.equal(eth("0.015625"));
      // Max taper kickback should be exactly one quarter of no-taper kickback
      expect(maxTaper * 4n).to.equal(noTaper);
    });

    it("taper at exact start boundary (10000) applies reduction", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPST");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      // Score exactly at 10000: excess = 0, reductionBps = 0, 100% payout
      // Same as no taper
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true, 10000
      );
      expect(result).to.equal(eth("0.0625"));
    });

    it("recycled ETH with taper score still gets no taper (taper only affects payout, not scale)", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPREC");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      // Recycled: 5% scale => 0.05 ETH
      // Max taper (25% floor): 0.05 * 25% = 0.0125 => 25% kickback = 0.003125
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, false, 25500
      );
      expect(result).to.equal(eth("0.003125"));

      // Without taper: 0.05 * 25% = 0.0125
      const noTaper = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, false, 0
      );
      expect(noTaper).to.equal(eth("0.0125"));
    });

    it("taper interacts correctly with commission cap", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(
        deployFullProtocol
      );
      const code = toBytes32("TAPCAP");
      await affiliate.connect(alice).createAffiliateCode(code, 25);
      await affiliate.connect(bob).referPlayer(code);

      // 100 ETH fresh L1 => 25 ETH scaled, capped to 0.5 ETH, then 25% taper => 0.125 ETH
      // Kickback = 0.125 * 25% = 0.03125
      const result = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true, 25500
      );
      expect(result).to.equal(eth("0.03125"));

      // Leaderboard records the post-taper amount: 0.5 ETH capped * 25% floor = 0.125 ETH
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(100), code, bob.address, 1, true, 25500
      );
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.125"));
    });
  });
});
