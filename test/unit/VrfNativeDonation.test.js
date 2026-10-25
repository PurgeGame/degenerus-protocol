import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import hre from "hardhat";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";

describe("Native VRF donations", function () {
  after(() => restoreAddresses());
  it("forwards all ETH and banks the quarter in wei", async function () {
    const {admin, game, mockVRF, alice} = await loadFixture(deployFullProtocol);
    const amount = 1_000_000_000_000_000_003n;
    const subId = await admin.subscriptionId();
    const before = (await mockVRF.getSubscription(subId))[1];
    await admin.connect(alice).donateVrf({value: amount});
    expect((await mockVRF.getSubscription(subId))[1] - before).to.equal(amount);
    expect(await game.middayRngCredits(alice.address)).to.equal(amount / 4n);
    expect(await hre.ethers.provider.getBalance(await admin.getAddress())).to.equal(0n);
  });
  it("plain ETH reaches the Vault without credit", async function () {
    const {admin, game, vault, alice} = await loadFixture(deployFullProtocol);
    const before = await hre.ethers.provider.getBalance(await vault.getAddress());
    await alice.sendTransaction({to: await admin.getAddress(), value: 1000n});
    expect(await hre.ethers.provider.getBalance(await vault.getAddress())).to.equal(before + 1000n);
    expect(await game.middayRngCredits(alice.address)).to.equal(0n);
  });
  it("rejects zero donations", async function () {
    const {admin} = await loadFixture(deployFullProtocol);
    await expect(admin.donateVrf()).to.be.revertedWithCustomError(admin, "InvalidAmount");
  });
});
