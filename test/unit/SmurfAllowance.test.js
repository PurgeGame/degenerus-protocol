import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import { deployFullProtocol, restoreAddresses } from "../helpers/deployFixture.js";
import { eth, ZERO_BYTES32 } from "../helpers/testUtils.js";

describe("Smurf allowance vault-owner control", function () {
  after(() => restoreAddresses());
  describe("Smurf base allowance", function () {
    it("grants a uint16 base by main ID and follows transferred vault ownership", async function () {
      const { game, vault, deployer, alice, bob } = await loadFixture(deployFullProtocol);
      await game.connect(bob).purchase(0, 400, 0, ZERO_BYTES32, 0, false, { value: eth("0.01") });
      const main = await game.walletIdOf(bob.address);
      await expect(game.connect(alice).raiseSmurfBaseAllowance(main, 300))
        .to.be.revertedWithCustomError(game, "OnlyVault");
      await expect(game.connect(deployer).raiseSmurfBaseAllowance(main, 300))
        .to.emit(game, "SmurfBaseAllowanceRaised").withArgs(main, 0, 300);
      await expect(game.connect(deployer).raiseSmurfBaseAllowance(main, 300))
        .to.be.revertedWithCustomError(game, "InvalidSmurfBaseIncrease");

      const dgve = await hre.ethers.getContractAt("DegenerusVaultShare", hre.ethers.getCreateAddress({
        from: await vault.getAddress(), nonce: 2,
      }));
      await dgve.connect(deployer).transfer(alice.address, await dgve.balanceOf(deployer.address));
      await expect(game.connect(deployer).raiseSmurfBaseAllowance(main, 65535))
        .to.be.revertedWithCustomError(game, "OnlyVault");
      await expect(game.connect(alice).raiseSmurfBaseAllowance(main, 65535))
        .to.emit(game, "SmurfBaseAllowanceRaised").withArgs(main, 300, 65535);
      expect((await game.mintPackedFor(bob.address)) >> 240n).to.equal(65535n);
    });
  });

});
