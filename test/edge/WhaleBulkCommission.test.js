import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { giveWalletId,
  deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { seedTicketQueue, entryOwnerRecordSlot } from "../helpers/bucketSeed.js";

describe("Whale bulk commission", function () {
  this.timeout(300_000);
  after(() => restoreAddresses());

  for (const level of [0, 2, 3, 4]) {
    for (const quantity of [4, 5, 10]) {
      it(`uses the correct fresh rate at level ${level} for ${quantity} passes`, async function () {
        const { game, affiliate, alice, bob, vault, sdgnrs } = await loadFixture(deployFullProtocol);
        const address = await game.getAddress();
        // This isolates commission arithmetic at a chosen completed level;
        // it does not simulate playing the skipped levels. Genesis owns paid
        // future queues for levels 1..100. Project only the skipped, completed
        // levels to drained records before their level+100 roots can be reused.
        // Leaving those live while only poking `level` is an impossible fixture.
        for (let completed = 1; completed <= level; ++completed) {
          for (const domain of [0n, 1n << 22n, 1n << 23n]) {
            await seedTicketQueue(address, BigInt(completed) | domain, []);
          }
          for (const owner of [await vault.getAddress(), await sdgnrs.getAddress()]) {
            const record = await entryOwnerRecordSlot(address, completed, owner);
            if (record !== null) {
              await hre.network.provider.send("hardhat_setStorageAt", [address, record, hre.ethers.ZeroHash]);
            }
          }
        }
        const slot = BigInt(await hre.ethers.provider.getStorage(address, 0));
        const mask = 0xffffffn << 96n;
        await hre.network.provider.send("hardhat_setStorageAt", [
          address, "0x0", hre.ethers.toBeHex((slot & ~mask) | (BigInt(level) << 96n), 32),
        ]);
        const code = hre.ethers.encodeBytes32String("bulk-referral");
        await affiliate.connect(alice).createAffiliateCode(code, 25);
        const price = hre.ethers.parseEther(level <= 3 ? "2.4" : "4") * BigInt(quantity);
        await game.connect(bob).purchaseWhalePass(0, quantity, code, { value: price });
        const ticketPrice = hre.ethers.parseEther(level < 4 ? "0.01" : "0.02");
        const rateBps = level < 3 ? 2500n : 2000n;
        const bulkDivisor = quantity >= 5 ? 2n : 1n;
        const expected = price * 1000n / ticketPrice * rateBps / 10_000n / bulkDivisor;
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
      await game.connect(bob).depositAfkingFunding(await giveWalletId(game, bob.address), { value: price - fresh });
      await game.connect(bob).purchaseWhalePass(0, 5, code, { value: fresh });
      const conversion = 100_000n;
      expect(await affiliate.totalAffiliateScore(1)).to.equal(
        (fresh * conversion / 8n + (price - fresh) * conversion / 20n) / hre.ethers.parseEther("1"),
      );
    });
  }
});
