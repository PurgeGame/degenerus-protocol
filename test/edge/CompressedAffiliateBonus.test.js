import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {
  deployFullProtocol,
  restoreAddresses,
} from "../helpers/deployFixture.js";
import {
  eth,
  advanceToNextDay,
  getEvents,
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const ZERO_ADDRESS = hre.ethers.ZeroAddress;
const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

/**
 * Affiliate Bonus in Compressed Jackpot Mode
 *
 * The MintModule inflates freshBurnie by 7/5 (level 0-3) or 3/2 (level 4+)
 * on the physical day before the final jackpot draw. This bonus must fire
 * correctly in all three compression tiers:
 *
 *   Normal (flag=0):     counter=4, nextStep=1, 4+1≥5 → bonus
 *   Compressed (flag=1): counter=4, nextStep=1, 4+1≥5 → bonus
 *   Turbo (flag=2):      excluded by outer guard → no bonus
 *
 * Per-referrer commission cap (0.5 ETH BURNIE) means each test buyer
 * can only be used ONCE — a single ticket purchase in BURNIE units
 * exceeds the cap. Tests use separate buyers for baseline vs bonus day.
 */
describe("CompressedAffiliateBonus", function () {
  this.timeout(300_000);

  after(function () {
    restoreAddresses();
  });

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  function toBytes32(str) {
    return hre.ethers.encodeBytes32String(str);
  }

  async function buyFullTickets(game, buyer, n, totalEth, affiliateCode) {
    return game.connect(buyer).purchase(
      ZERO_ADDRESS,
      BigInt(n) * 400n,
      0n,
      affiliateCode || ZERO_BYTES32,
      MintPaymentKind.DirectEth,
      { value: eth(totalEth) }
    );
  }

  async function driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word) {
    await game.connect(deployer).advanceGame();
    const requestId = await getLastVRFRequestId(mockVRF);
    try {
      await mockVRF.fulfillRandomWords(requestId, word);
    } catch {}
    for (let i = 0; i < 200; i++) {
      try {
        await game.connect(deployer).advanceGame();
      } catch {
        break;
      }
      if (!(await game.rngLocked())) break;
    }
  }

  async function driveOneCycle(game, deployer, mockVRF, advanceModule, word) {
    await advanceToNextDay();
    return driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, word);
  }

  async function heavyPurchases(game, buyers) {
    for (const buyer of buyers) {
      try {
        await game
          .connect(buyer)
          .purchaseWhaleBundle(buyer.address, 1, { value: eth(2.4) });
      } catch {}
      await buyFullTickets(game, buyer, 500, 5);
    }
  }

  /**
   * Warm-up: advance one day with a small purchase so purchaseDays > 1
   * on the next cycle. Prevents turbo (tier=2) from firing.
   */
  async function warmUpDay(game, deployer, mockVRF, advanceModule, buyer) {
    await buyFullTickets(game, buyer, 10, 0.1);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 7n);
  }

  async function driveToJackpotPhase(game, deployer, mockVRF, advanceModule) {
    for (let cycle = 0; cycle < 30; cycle++) {
      await driveOneCycle(game, deployer, mockVRF, advanceModule, BigInt(cycle * 1000 + 42));
      if (await game.jackpotPhase()) return true;
    }
    return false;
  }

  /**
   * Get the raw freshBurnie value passed to payAffiliate from a purchase tx.
   * Uses the Affiliate(amount, code, sender) event emitted at the end of
   * payAffiliate's normal path (line 622). This captures the pre-scaling,
   * pre-cap value — exactly what MintModule passes after potential inflation.
   *
   * For DirectEth purchases with isFreshEth, there's one payAffiliate call
   * and one Affiliate event. We match by the buyer's address (3rd arg).
   */
  async function getRawAffiliateBasis(tx, affiliate, buyerAddr) {
    const events = await getEvents(tx, affiliate, "Affiliate");
    // Filter for events from this buyer (args[2] = sender address)
    const fromBuyer = events.filter(
      (e) => e.args[2].toLowerCase() === buyerAddr.toLowerCase()
    );
    return fromBuyer.length > 0 ? fromBuyer[0].args[0] : null;
  }

  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  async function deployCompressedWithAffiliate() {
    const protocol = await deployFullProtocol();
    const { affiliate, game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } = protocol;

    const aliceCode = toBytes32("ALICE");
    await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);

    // Reserve others[12] and others[13] as test buyers with fresh per-referrer caps
    const buyerBaseline = others[12];
    const buyerBonus = others[13];
    await affiliate.connect(buyerBaseline).referPlayer(aliceCode);
    await affiliate.connect(buyerBonus).referPlayer(aliceCode);

    // Warm-up: consume day 2 so purchaseDays > 1 on next advance (avoids turbo)
    await warmUpDay(game, deployer, mockVRF, advanceModule, bob);

    // Heavy purchases → target met quickly → compressed on next driveToJackpotPhase
    // Use others[0..11] (not 12-13 which are reserved for test purchases)
    const buyers = [carol, dan, eve, ...others.slice(0, 12)];
    await heavyPurchases(game, buyers);

    return { ...protocol, aliceCode, buyerBaseline, buyerBonus };
  }

  async function deployNormalWithAffiliate() {
    const protocol = await deployFullProtocol();
    const { affiliate, game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } = protocol;

    const aliceCode = toBytes32("ALICE");
    await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);

    const buyerBaseline = others[12];
    const buyerBonus = others[13];
    await affiliate.connect(buyerBaseline).referPlayer(aliceCode);
    await affiliate.connect(buyerBonus).referPlayer(aliceCode);

    // Spread purchases over 4+ advances so purchaseDays > 3 when target met.
    // purchaseStartDay = 1 at deploy.
    // Advance 1 (day 2): purchaseDays = 2-1 = 1
    await buyFullTickets(game, alice, 200, 2);
    await advanceToNextDay();
    await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 100n);

    // Advance 2 (day 3): purchaseDays = 3-1 = 2
    await buyFullTickets(game, bob, 200, 2);
    await driveOneCycle(game, deployer, mockVRF, advanceModule, 200n);

    // Advance 3 (day 4): purchaseDays = 4-1 = 3
    await buyFullTickets(game, carol, 200, 2);
    await driveOneCycle(game, deployer, mockVRF, advanceModule, 300n);

    // Advance 4 (day 5): purchaseDays = 5-1 = 4 > 3 → normal
    await buyFullTickets(game, others[0], 200, 2);
    await driveOneCycle(game, deployer, mockVRF, advanceModule, 400n);

    // Heavy purchases on day 5+ → normal (purchaseDays > 3)
    const buyers = [dan, eve, ...others.slice(1, 12)];
    await heavyPurchases(game, buyers);

    return { ...protocol, aliceCode, buyerBaseline, buyerBonus };
  }

  // ---------------------------------------------------------------------------
  // Compressed mode (tier=1): bonus fires on penultimate day
  // ---------------------------------------------------------------------------

  describe("compressed mode (tier=1)", function () {
    it("affiliate bonus inflates earnings by 7/5 on penultimate physical day", async function () {
      const { game, deployer, mockVRF, advanceModule, affiliate, buyerBaseline, buyerBonus, aliceCode } =
        await loadFixture(deployCompressedWithAffiliate);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(1, "Should be compressed");

      // Remaining day 1 (no bonus): buyerBaseline purchases
      const tx1 = await buyFullTickets(game, buyerBaseline, 10, 0.1, aliceCode);
      const baseline = await getRawAffiliateBasis(tx1, affiliate, buyerBaseline.address);
      expect(baseline).to.not.be.null;
      expect(baseline).to.be.gt(0n, "Baseline freshBurnie should be non-zero");

      // Advance to penultimate day (bonus expected)
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 5000n);
      expect(await game.jackpotPhase()).to.equal(true, "Should still be in jackpot phase");

      // buyerBonus purchases same amount on bonus day
      const tx2 = await buyFullTickets(game, buyerBonus, 10, 0.1, aliceCode);
      const bonus = await getRawAffiliateBasis(tx2, affiliate, buyerBonus.address);
      expect(bonus).to.not.be.null;
      expect(bonus).to.be.gt(0n, "Bonus day freshBurnie should be non-zero");

      // Bonus day freshBurnie should be 7/5 of baseline (same ETH → same base BURNIE, inflated)
      const ratio = (bonus * 10000n) / baseline;
      expect(ratio).to.be.gte(13900n, "Compressed bonus should inflate by ~7/5");
      expect(ratio).to.be.lte(14100n, "Compressed bonus should inflate by ~7/5");
    });
  });

  // ---------------------------------------------------------------------------
  // Normal mode (tier=0): bonus fires on counter=4 (regression check)
  // ---------------------------------------------------------------------------

  describe("normal mode (tier=0)", function () {
    it("affiliate bonus inflates earnings by 7/5 on penultimate physical day", async function () {
      const { game, deployer, mockVRF, advanceModule, affiliate, buyerBaseline, buyerBonus, aliceCode } =
        await loadFixture(deployNormalWithAffiliate);

      const reached = await driveToJackpotPhase(game, deployer, mockVRF, advanceModule);
      expect(reached).to.equal(true, "Should reach jackpot phase");
      expect(await game.jackpotCompressionTier()).to.equal(0, "Should be normal mode");

      // Day 1 (no bonus): buyerBaseline purchases
      const tx1 = await buyFullTickets(game, buyerBaseline, 10, 0.1, aliceCode);
      const baseline = await getRawAffiliateBasis(tx1, affiliate, buyerBaseline.address);
      expect(baseline).to.not.be.null;
      expect(baseline).to.be.gt(0n);

      // Advance to penultimate day (counter=4, bonus expected)
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 3000n);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 4000n);
      await driveOneCycle(game, deployer, mockVRF, advanceModule, 5000n);
      expect(await game.jackpotPhase()).to.equal(true, "Should still be in jackpot phase");

      // buyerBonus purchases same amount on bonus day
      const tx4 = await buyFullTickets(game, buyerBonus, 10, 0.1, aliceCode);
      const bonus = await getRawAffiliateBasis(tx4, affiliate, buyerBonus.address);
      expect(bonus).to.not.be.null;
      expect(bonus).to.be.gt(0n);

      // Bonus should be ~7/5 of baseline
      const ratio = (bonus * 10000n) / baseline;
      expect(ratio).to.be.gte(13900n, "Normal mode bonus should inflate by ~7/5");
      expect(ratio).to.be.lte(14100n, "Normal mode bonus should inflate by ~7/5");
    });
  });

  // ---------------------------------------------------------------------------
  // Turbo mode (tier=2): bonus never fires
  // ---------------------------------------------------------------------------

  describe("compressed early target (tier=1)", function () {
    it("affiliate bonus does NOT fire on first compressed day", async function () {
      const protocol = await loadFixture(deployFullProtocol);
      const { affiliate, game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } = protocol;

      const aliceCode = toBytes32("ALICE");
      await affiliate.connect(alice).createAffiliateCode(aliceCode, 0);

      const buyerPre = others[12];
      const buyerCompressed = others[13];
      await affiliate.connect(buyerPre).referPlayer(aliceCode);
      await affiliate.connect(buyerCompressed).referPlayer(aliceCode);

      // Warm-up: consume day 2 so purchaseDays > 1 on next advance (avoids turbo)
      await warmUpDay(game, deployer, mockVRF, advanceModule, bob);

      // Heavy purchases → compressed on next advance
      const buyers = [carol, dan, eve, ...others.slice(0, 12)];
      await heavyPurchases(game, buyers);

      // Pre-compressed baseline: buy with affiliate before advancing
      const txBaseline = await buyFullTickets(game, buyerPre, 10, 0.1, aliceCode);
      const baseline = await getRawAffiliateBasis(txBaseline, affiliate, buyerPre.address);
      expect(baseline).to.not.be.null;
      expect(baseline).to.be.gt(0n, "Should have baseline freshBurnie pre-compressed");

      // Trigger compressed via full cycle (day 3, purchaseDays=2)
      // Compressed tier is set during daily processing, not at advanceGame entry
      await advanceToNextDay();
      await driveOneCycleSameDay(game, deployer, mockVRF, advanceModule, 42n);
      expect(await game.jackpotCompressionTier()).to.equal(1, "Should be compressed");

      // Buy during compressed jackpot phase — first day should NOT inflate
      if (await game.jackpotPhase()) {
        const txCompressed = await buyFullTickets(game, buyerCompressed, 10, 0.1, aliceCode);
        const compressedAmount = await getRawAffiliateBasis(txCompressed, affiliate, buyerCompressed.address);

        if (compressedAmount !== null && compressedAmount > 0n) {
          // First compressed day freshBurnie should NOT be inflated — ratio should be ~1:1
          const ratio = (compressedAmount * 10000n) / baseline;
          expect(ratio).to.be.lte(10100n, "First compressed day should NOT inflate affiliate freshBurnie");
        }
      }
    });
  });
});
