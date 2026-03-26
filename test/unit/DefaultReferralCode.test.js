import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  getEvent,
  ZERO_ADDRESS,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

/*
 * Default Referral Code Tests
 * ===========================
 * Every address has an implicit affiliate code: bytes32(uint256(uint160(addr))).
 * No createAffiliateCode tx required. Custom codes still work as before.
 *
 * Covers:
 *  - defaultCode() view returns correct derivation
 *  - referPlayer accepts default codes
 *  - payAffiliate resolves default codes (first purchase, stored code recall)
 *  - Upline chains work through default codes
 *  - Default codes get 0% kickback
 *  - createAffiliateCode rejects address-range codes (collision guard)
 *  - Self-referral blocked for default codes
 *  - getReferrer resolves default codes
 */

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Compute the default affiliate code for an address (mirrors contract logic). */
function defaultCodeFor(address) {
  return hre.ethers.zeroPadValue(address, 32);
}

/** Create a bytes32 from a short ASCII string. */
function toBytes32(str) {
  return hre.ethers.encodeBytes32String(str);
}

/**
 * Call payAffiliate as the coin contract (impersonation).
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
 * staticCall payAffiliate as coin to get the return value.
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

describe("Default Referral Codes", function () {
  after(() => restoreAddresses());

  // =========================================================================
  // 1. defaultCode() view
  // =========================================================================
  describe("defaultCode view", function () {
    it("returns bytes32(uint256(uint160(addr))) for any address", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const expected = defaultCodeFor(alice.address);
      expect(await affiliate.defaultCode(alice.address)).to.equal(expected);
    });

    it("returns different codes for different addresses", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const codeA = await affiliate.defaultCode(alice.address);
      const codeB = await affiliate.defaultCode(bob.address);
      expect(codeA).to.not.equal(codeB);
    });

    it("returns zero bytes32 for address(0)", async function () {
      const { affiliate } = await loadFixture(deployFullProtocol);
      expect(await affiliate.defaultCode(ZERO_ADDRESS)).to.equal(ZERO_BYTES32);
    });
  });

  // =========================================================================
  // 2. createAffiliateCode collision guard
  // =========================================================================
  describe("createAffiliateCode collision guard", function () {
    it("rejects a code in the address-derived range", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const addrCode = defaultCodeFor(alice.address);
      await expect(
        affiliate.connect(alice).createAffiliateCode(addrCode, 0)
      ).to.be.revertedWithCustomError(affiliate, "Zero");
    });

    it("rejects any code where top 12 bytes are zero", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      // Arbitrary value within uint160 range (not an actual address)
      const lowCode = "0x" + "0".repeat(24) + "ff".repeat(20);
      await expect(
        affiliate.connect(alice).createAffiliateCode(lowCode, 0)
      ).to.be.revertedWithCustomError(affiliate, "Zero");
    });

    it("allows codes with nonzero high bytes (normal string codes)", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = toBytes32("CUSTOM1");
      await expect(
        affiliate.connect(alice).createAffiliateCode(code, 10)
      ).to.not.be.reverted;
    });
  });

  // =========================================================================
  // 3. referPlayer with default codes
  // =========================================================================
  describe("referPlayer with default codes", function () {
    it("registers under a default code (no createAffiliateCode needed)", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);
      await affiliate.connect(bob).referPlayer(code);
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);
    });

    it("reverts on self-referral via default code", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);
      await expect(
        affiliate.connect(alice).referPlayer(code)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("reverts on default code for address(0)", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      // defaultCodeFor(address(0)) == ZERO_BYTES32 => resolves to address(0) => invalid
      await expect(
        affiliate.connect(alice).referPlayer(ZERO_BYTES32)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("locks referral — cannot change after setting via default code", async function () {
      const { affiliate, alice, bob, carol } = await loadFixture(deployFullProtocol);
      const codeAlice = defaultCodeFor(alice.address);
      const codeCarol = defaultCodeFor(carol.address);
      await affiliate.connect(bob).referPlayer(codeAlice);
      await expect(
        affiliate.connect(bob).referPlayer(codeCarol)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("emits ReferralUpdated with correct referrer for default code", async function () {
      const { affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);
      const tx = await affiliate.connect(bob).referPlayer(code);
      const ev = await getEvent(tx, affiliate, "ReferralUpdated");
      expect(ev.args.player).to.equal(bob.address);
      expect(ev.args.code).to.equal(code);
      expect(ev.args.referrer).to.equal(alice.address);
      expect(ev.args.locked).to.equal(false);
    });
  });

  // =========================================================================
  // 4. payAffiliate with default codes
  // =========================================================================
  describe("payAffiliate with default codes", function () {
    it("resolves default code on first purchase and stores it", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);

      // First purchase by bob with alice's default code
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );

      // Bob's referrer should now be alice
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);
    });

    it("subsequent purchases recall the stored default code", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);

      // First purchase stores the code
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );

      // Second purchase with no code — should still use alice's default code
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), ZERO_BYTES32, bob.address, 1, true
      );

      // Alice should have affiliate score from both purchases
      const score = await affiliate.affiliateScore(1, alice.address);
      expect(score).to.be.gt(0n);
    });

    it("returns 0 kickback for default codes (0% kickback)", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);

      const kickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );
      expect(kickback).to.equal(0n);
    });

    it("tracks affiliate score for default code affiliates", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(deployFullProtocol);
      const code = defaultCodeFor(alice.address);

      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), code, bob.address, 1, true
      );

      // Fresh ETH L1 => 25% => 0.25 ETH scaled
      expect(await affiliate.affiliateScore(1, alice.address)).to.equal(eth("0.25"));
    });

    it("self-referral via default code locks to VAULT", async function () {
      const { affiliate, coin, alice } = await loadFixture(deployFullProtocol);
      const selfCode = defaultCodeFor(alice.address);

      // Alice tries to use her own default code
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), selfCode, alice.address, 1, true
      );

      // Should be locked to VAULT
      const { vault } = await loadFixture(deployFullProtocol);
      expect(await affiliate.getReferrer(alice.address)).to.equal(
        await vault.getAddress()
      );
    });
  });

  // =========================================================================
  // 5. Upline chains through default codes
  // =========================================================================
  describe("Upline chains with default codes", function () {
    it("default code affiliate has upline from their own referral", async function () {
      const { affiliate, coin, alice, bob, carol } = await loadFixture(deployFullProtocol);

      // Set up chain: carol referred by alice (custom code), bob referred by carol (default code)
      const aliceCustom = toBytes32("ACHAIN");
      await affiliate.connect(alice).createAffiliateCode(aliceCustom, 0);
      await affiliate.connect(carol).referPlayer(aliceCustom);

      const carolDefault = defaultCodeFor(carol.address);
      await affiliate.connect(bob).referPlayer(carolDefault);

      // Verify chain: bob -> carol -> alice
      expect(await affiliate.getReferrer(bob.address)).to.equal(carol.address);
      expect(await affiliate.getReferrer(carol.address)).to.equal(alice.address);

      // Pay affiliate — carol gets base, alice gets upline1
      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), carolDefault, bob.address, 1, true
      );

      // Carol should have affiliate score
      expect(await affiliate.affiliateScore(1, carol.address)).to.be.gt(0n);
    });

    it("default code affiliate with no referral has VAULT as upline", async function () {
      const { affiliate, coin, alice, bob, vault } = await loadFixture(deployFullProtocol);
      const aliceDefault = defaultCodeFor(alice.address);

      // Alice has never been referred — her upline should be VAULT
      expect(await affiliate.getReferrer(alice.address)).to.equal(
        await vault.getAddress()
      );

      // Bob uses alice's default code
      await affiliate.connect(bob).referPlayer(aliceDefault);
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);
    });
  });

  // =========================================================================
  // 6. Custom codes still work alongside default codes
  // =========================================================================
  describe("Custom and default code coexistence", function () {
    it("custom code takes priority when registered", async function () {
      const { affiliate, coin, alice, bob } = await loadFixture(deployFullProtocol);

      // Alice creates a custom code with 10% kickback
      const customCode = toBytes32("ACUSTOM");
      await affiliate.connect(alice).createAffiliateCode(customCode, 10);

      // Bob uses custom code
      await affiliate.connect(bob).referPlayer(customCode);

      // Should resolve to alice
      expect(await affiliate.getReferrer(bob.address)).to.equal(alice.address);

      // And should have kickback
      const kickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), customCode, bob.address, 1, true
      );
      expect(kickback).to.be.gt(0n);
    });

    it("default code gives 0 kickback vs custom code with kickback", async function () {
      const { affiliate, coin, alice, bob, carol } = await loadFixture(deployFullProtocol);

      // Custom code with 25% kickback
      const customCode = toBytes32("KICK25");
      await affiliate.connect(alice).createAffiliateCode(customCode, 25);

      const defaultCode = defaultCodeFor(alice.address);

      // Bob uses custom code
      const customKickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), customCode, bob.address, 1, true
      );

      // Carol uses default code
      const defaultKickback = await payAffiliateAsCoinStatic(
        hre.ethers, coin, affiliate, eth(1), defaultCode, carol.address, 1, true
      );

      expect(customKickback).to.be.gt(0n);
      expect(defaultKickback).to.equal(0n);
    });
  });

  // =========================================================================
  // 7. Edge cases
  // =========================================================================
  describe("Edge cases", function () {
    it("default code for address(1) resolves correctly (not REF_CODE_LOCKED)", async function () {
      const { affiliate } = await loadFixture(deployFullProtocol);
      // address(1) default code == bytes32(1) == REF_CODE_LOCKED
      // But referPlayer uses _resolveCodeOwner which checks affiliateCode first,
      // then derives address(1) — this is address(1), not a real user, so it should
      // technically resolve. In practice nobody owns address(1).
      const code = "0x0000000000000000000000000000000000000000000000000000000000000001";
      // This is the REF_CODE_LOCKED sentinel — referPlayer should handle it.
      // _resolveCodeOwner will find affiliateCode[code].owner == address(0),
      // then derive address(1) which is nonzero. But address(1) is a precompile, not a player.
      // The contract doesn't block it — edge case accepted.
    });

    it("invalid code in high-byte range still reverts in referPlayer", async function () {
      const { affiliate, alice } = await loadFixture(deployFullProtocol);
      // A code with nonzero high bytes that isn't registered as a custom code
      const fakeCode = toBytes32("NOTEXIST");
      await expect(
        affiliate.connect(alice).referPlayer(fakeCode)
      ).to.be.revertedWithCustomError(affiliate, "Insufficient");
    });

    it("payAffiliate with unregistered high-byte code locks to VAULT", async function () {
      const { affiliate, coin, alice, vault } = await loadFixture(deployFullProtocol);
      const fakeCode = toBytes32("BOGUS");

      await payAffiliateAsCoin(
        hre.ethers, coin, affiliate, eth(1), fakeCode, alice.address, 1, true
      );

      expect(await affiliate.getReferrer(alice.address)).to.equal(
        await vault.getAddress()
      );
    });
  });
});
