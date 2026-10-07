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
  getLastVRFRequestId,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";

const MintPaymentKind = { DirectEth: 0, Claimable: 1, Combined: 2 };

// Active random-sequence and turbo regression checks. Current delayed-VRF,
// gap-credit and cross-midnight assertions are in BackfillIdempotency.test.js.

async function buyFullTickets(game, buyer, n, totalEth) {
  return game.connect(buyer).purchase(
    0,
    BigInt(n) * 400n,
    0n,
    ZERO_BYTES32,
    MintPaymentKind.DirectEth,false, 
    { value: eth(totalEth) }
  );
}

async function heavyPurchases(game, buyers) {
  for (const buyer of buyers) {
    try {
      await game
        .connect(buyer)
        .purchaseWhalePass(0, 1, hre.ethers.ZeroHash, { value: eth(2.4) });
    } catch {}
    await buyFullTickets(game, buyer, 500, 5);
  }
}

describe("LastPurchaseDayRace (turbo + gap-day backfill)", function () {
  this.timeout(900_000);

  after(() => restoreAddresses());

  describe("stress (no panic ever)", function () {
    it("survives 30 randomised advance/mint/skip cycles without panic", async function () {
      const { game, deployer, mockVRF, advanceModule, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const allBuyers = [alice, bob, carol, dan, eve, ...others.slice(0, 14)];
      let panicked = false;
      let panicLog = "";

      // Pre-seed pool with some mints so we exercise both pre- and
      // post-target paths during the stress loop.
      for (const b of allBuyers.slice(0, 5)) {
        await buyFullTickets(game, b, 50, 0.5);
      }

      // Use a deterministic PRNG so failures are reproducible.
      let seed = 0xdeadbeef;
      const rand = () => {
        seed = (seed * 1664525 + 1013904223) >>> 0;
        return seed;
      };

      for (let cycle = 0; cycle < 30; cycle++) {
        const action = rand() % 4;
        try {
          if (action === 0) {
            // Mint by a random buyer.
            const buyer = allBuyers[rand() % allBuyers.length];
            const ethAmt = 0.1 + (rand() % 50) / 10;
            await buyFullTickets(game, buyer, 50, ethAmt);
          } else if (action === 1) {
            // Skip 1-5 days (gap accumulation).
            const days = 1 + (rand() % 5);
            for (let d = 0; d < days; d++) await advanceToNextDay();
          } else if (action === 2) {
            // mineFlip (fulfil VRF first if pending).
            const reqId = await getLastVRFRequestId(mockVRF);
            if (reqId > 0n) {
              try {
                await mockVRF.fulfillRandomWords(reqId, BigInt(rand()) || 1n);
              } catch {}
            }
            const caller = allBuyers[rand() % allBuyers.length];
            try {
              await game.connect(caller).mineFlip();
            } catch (e) {
              const msg = (e && (e.shortMessage || e.message)) || "";
              if (msg.includes("0x11") || msg.toLowerCase().includes("panic")) {
                panicked = true;
                panicLog = `cycle=${cycle} action=advance ${msg.slice(0, 80)}`;
                break;
              }
              // RngNotReady, NotTimeYet, mint gate etc are fine.
            }
          } else {
            // Heavy purchase burst.
            const subset = allBuyers.slice(0, 3 + (rand() % 5));
            for (const b of subset) {
              try {
                await buyFullTickets(game, b, 200, 2);
              } catch {}
            }
          }
        } catch (e) {
          const msg = (e && (e.shortMessage || e.message)) || "";
          if (msg.includes("0x11") || msg.toLowerCase().includes("panic")) {
            panicked = true;
            panicLog = `cycle=${cycle} setup ${msg.slice(0, 80)}`;
            break;
          }
        }
      }

      expect(panicked).to.equal(false, `Stress test panicked: ${panicLog}`);
    });
  });

  // ===========================================================================
  // Sanity: normal turbo path still works (regression check).
  // ===========================================================================
  describe("regression: normal turbo path still works", function () {
    it("turbo (tier=2) fires when target met before any advance and no VRF in flight", async function () {
      const { game, deployer, alice, bob, carol, dan, eve, others } =
        await loadFixture(deployFullProtocol);

      const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 14)];
      await heavyPurchases(game, buyers);

      await advanceToNextDay();
      await game.connect(alice).mineFlip();

      expect(await game.jackpotDuration()).to.equal(
        1n,
        "Normal turbo (tier 2) must still activate when no VRF is in flight"
      );
      expect(await game.level()).to.equal(
        1n,
        "Turbo must pre-increment level via _finalizeRngRequest"
      );
      expect(await game.rngLocked()).to.equal(true);
    });
  });
});
