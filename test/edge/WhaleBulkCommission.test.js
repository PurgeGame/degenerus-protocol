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
        const code = hre.ethers.encodeBytes32String("BULKREFERRAL");
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

  // Prepaid AFKing is the buyer's own principal: it earns the fresh rate (halved for bulk) on
  // the whole price, alone or mixed with msg.value.
  for (const freshPercent of [0n, 50n]) {
    it(`pays AFKing-funded bulk passes at the halved fresh rate with ${freshPercent}% msg.value`, async function () {
      const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = hre.ethers.encodeBytes32String("MIXEDBULK");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      const price = hre.ethers.parseEther("12");
      const fresh = price * freshPercent / 100n;
      await game.connect(bob).depositAfkingFunding(await giveWalletId(game, bob.address), { value: price - fresh });
      await game.connect(bob).purchaseWhalePass(0, 5, code, { value: fresh });
      expect(await affiliate.totalAffiliateScore(1)).to.equal(price * 100_000n / 8n / ONE_ETH);
    });
  }

  it("keeps claimable-funded bulk passes at the unhalved recycled 5%", async function () {
    const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
    const code = hre.ethers.encodeBytes32String("CLAIMBULK");
    await affiliate.connect(alice).createAffiliateCode(code, 0);
    const price = hre.ethers.parseEther("12");
    await fundClaimable(game, await giveWalletId(game, bob.address), price);
    await game.connect(bob).purchaseWhalePass(0, 5, code);
    expect(await affiliate.totalAffiliateScore(1)).to.equal(price * 100_000n / 20n / ONE_ETH);
  });

  for (const [label, freshWei, afkingWei] of [
    ["AFKing", 0n, hre.ethers.parseEther("2.4")],
    ["mixed msg.value + AFKing", hre.ethers.parseEther("1.2"), hre.ethers.parseEther("1.2")],
  ]) {
    it(`pays a ${label}-funded whale pass at the fresh 25%`, async function () {
      const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
      const code = hre.ethers.encodeBytes32String("AFKWHALE");
      await affiliate.connect(alice).createAffiliateCode(code, 0);
      await game.connect(bob).depositAfkingFunding(await giveWalletId(game, bob.address), { value: afkingWei });
      await game.connect(bob).purchaseWhalePass(0, 1, code, { value: freshWei });
      // 2.4 ETH at 0.01 ETH = 240,000 FLIP basis; 25% = 60,000.
      expect(await affiliate.totalAffiliateScore(1)).to.equal(60_000n);
    });
  }

  it("keeps a claimable-funded whale pass at the recycled 5%", async function () {
    const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
    const code = hre.ethers.encodeBytes32String("CLAIMWHALE");
    await affiliate.connect(alice).createAffiliateCode(code, 0);
    await fundClaimable(game, await giveWalletId(game, bob.address), hre.ethers.parseEther("2.4"));
    await game.connect(bob).purchaseWhalePass(0, 1, code);
    expect(await affiliate.totalAffiliateScore(1)).to.equal(12_000n);
  });

  it("pays an AFKing-funded lazy pass at the fresh 25%", async function () {
    const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
    const code = hre.ethers.encodeBytes32String("AFKLAZY");
    await affiliate.connect(alice).createAffiliateCode(code, 0);
    await game.connect(bob).depositAfkingFunding(await giveWalletId(game, bob.address), {
      value: hre.ethers.parseEther("0.24"),
    });
    await game.connect(bob).purchaseLazyPass(0, code);
    // 0.24 ETH at 0.01 ETH = 24,000 FLIP basis; 25% = 6,000.
    expect(await affiliate.totalAffiliateScore(1)).to.equal(6_000n);
  });

  it("keeps a claimable-funded lazy pass at the recycled 5%", async function () {
    const { game, affiliate, alice, bob } = await loadFixture(deployFullProtocol);
    const code = hre.ethers.encodeBytes32String("CLAIMLAZY");
    await affiliate.connect(alice).createAffiliateCode(code, 0);
    await fundClaimable(game, await giveWalletId(game, bob.address), hre.ethers.parseEther("0.24"));
    await game.connect(bob).purchaseLazyPass(0, code);
    expect(await affiliate.totalAffiliateScore(1)).to.equal(1_200n);
  });
});

const ONE_ETH = 10n ** 18n;
const BALANCES_PACKED_SLOT = 6n;
const CLAIMABLE_POOL_SLOT = 1n;

// Credit `amount` of claimable (plus the 1-wei sentinel's worth) to wallet `id`, moving
// claimablePool and the Game's ETH in tandem.
async function fundClaimable(game, id, amount) {
  const gameAddr = await game.getAddress();
  const word = (v) => hre.ethers.toBeHex(v, 32);
  const credit = amount + 1n;
  const balanceSlot = hre.ethers.keccak256(
    hre.ethers.AbiCoder.defaultAbiCoder().encode(["uint256", "uint256"], [BigInt(id), BALANCES_PACKED_SLOT]),
  );
  const packed = BigInt(await hre.ethers.provider.getStorage(gameAddr, balanceSlot));
  await hre.network.provider.send("hardhat_setStorageAt", [gameAddr, balanceSlot, word(packed + credit)]);
  const poolSlot = word(CLAIMABLE_POOL_SLOT);
  const poolWord = BigInt(await hre.ethers.provider.getStorage(gameAddr, poolSlot));
  await hre.network.provider.send("hardhat_setStorageAt", [gameAddr, poolSlot, word(poolWord + (credit << 128n))]);
  const balance = await hre.ethers.provider.getBalance(gameAddr);
  await hre.network.provider.send("hardhat_setBalance", [gameAddr, hre.ethers.toBeHex(balance + credit)]);
}
