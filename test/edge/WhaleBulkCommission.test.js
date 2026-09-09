import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";

describe("Whale bulk commission", function () {
  this.timeout(300_000);
  after(() => restoreAddresses());

  for (const level of [0, 2, 3, 4]) {
    for (const quantity of [4, 5, 10]) {
      it(`uses the correct fresh rate at level ${level} for ${quantity} passes`, async function () {
        const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
        const address = await game.getAddress();
        const slot = BigInt(await hre.ethers.provider.getStorage(address, 0));
        const mask = 0xffffffn << 96n;
        await hre.network.provider.send("hardhat_setStorageAt", [
          address, "0x0", hre.ethers.toBeHex((slot & ~mask) | (BigInt(level) << 96n), 32),
        ]);
        const code = hre.ethers.encodeBytes32String("bulk-referral");
        await affiliate.connect(alice).createAffiliateCode(code, 25);
        const price = hre.ethers.parseEther(level <= 3 ? "2.4" : "4") * BigInt(quantity);
        await game.connect(bob).purchaseWhalePass(bob.address, quantity, code, { value: price });
        const ticketPrice = hre.ethers.parseEther(level < 4 ? "0.01" : "0.02");
        const rateBps = level < 3 ? 2500n : 2000n;
        const bulkDivisor = quantity >= 5 ? 2n : 1n;
        const expected = price * hre.ethers.parseEther("1000") / ticketPrice * rateBps / 10_000n / bulkDivisor;
        expect(await affiliate.totalAffiliateScore(level + 1)).to.equal(expected);
      });
    }
  }

  for (const freshPercent of [0n, 50n]) {
    it(`keeps recycled bulk funding at 5% with ${freshPercent}% fresh ETH`, async function () {
      const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = hre.ethers.encodeBytes32String("mixed-bulk");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      const price = hre.ethers.parseEther("12");
      const fresh = price * freshPercent / 100n;
      await game.connect(bob).depositAfkingFunding(bob.address, { value: price - fresh });
      await game.connect(bob).purchaseWhalePass(bob.address, 5, code, { value: fresh });
      const conversion = 100_000n;
      expect(await affiliate.totalAffiliateScore(1)).to.equal(
        fresh * conversion / 8n + (price - fresh) * conversion / 20n,
      );
    });
  }
});
