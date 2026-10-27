import {expect} from "chai";
import hre from "hardhat";
import {loadFixture, time} from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {deployFullProtocol, restoreAddresses} from "../helpers/deployFixture.js";
import {readOwnerProposalAction} from "../../scripts/lib/ownerProposal.js";
import {controlledOwnerPositions} from "../../scripts/lib/ownerDirect.js";

describe("Owner governance block boundary", function () {
  this.timeout(300_000);
  after(restoreAddresses);

  it("builds a sorted direct owner list from current control, excluding revoked and withdrawn positions", async function () {
    const {ownerGovernance: gov, vault, deployer} = await loadFixture(deployFullProtocol);
    const [, second, third, delegate] = await hre.ethers.getSigners();
    const token = await hre.ethers.getContractAt("DegenerusVaultShare", await vault.dgve());
    const thirdAmount = (await token.totalSupply()) / 3n;
    await token.transfer(second.address, thirdAmount);
    await token.transfer(third.address, thirdAmount);
    await token.approve(await gov.getAddress(), thirdAmount);
    const deposited = await (await gov.deposit(thirdAmount, delegate.address)).wait();
    await token.connect(second).approve(await gov.getAddress(), thirdAmount);
    await gov.connect(second).deposit(thirdAmount, hre.ethers.ZeroAddress);
    await gov.connect(second).setVotingDelegate(delegate.address);
    await token.connect(third).approve(await gov.getAddress(), thirdAmount);
    await gov.connect(third).deposit(thirdAmount, delegate.address);
    await gov.connect(third).withdraw();
    const options = {fromBlock: deposited.blockNumber};
    const selection = await controlledOwnerPositions(gov, delegate.address, options);
    const expected = [deployer.address, second.address].sort((a, b) => BigInt(a) < BigInt(b) ? -1 : 1);
    expect(selection.owners).to.deep.equal(expected);
    expect(selection.settledWeight).to.equal(thirdAmount * 2n);
    const explicit = await controlledOwnerPositions(gov, delegate.address, {owners: expected.toReversed()});
    expect(explicit.owners).to.deep.equal(expected);
    await expect(controlledOwnerPositions(gov, delegate.address, {owners: [second.address, second.address]}))
      .to.be.rejectedWith("duplicate");
    await gov.connect(second).setVotingDelegate(hre.ethers.ZeroAddress);
    expect((await controlledOwnerPositions(gov, delegate.address, options)).owners).to.deep.equal([deployer.address]);
    await expect(controlledOwnerPositions(gov, delegate.address, {owners: expected}))
      .to.be.rejectedWith("does not control");
    expect((await controlledOwnerPositions(gov, second.address, options)).owners).to.deep.equal([second.address]);
  });

  it("recovers and verifies execution calldata from ProposalCreated logs", async function () {
    const {ownerGovernance: gov, vault, wwxrp, deployer} = await loadFixture(deployFullProtocol);
    const token = await hre.ethers.getContractAt("DegenerusVaultShare", await vault.dgve());
    const amount = await token.balanceOf(deployer.address);
    const data = wwxrp.interface.encodeFunctionData("setGameMintScale", [8]);
    await token.approve(await gov.getAddress(), amount);
    const receipt = await (await gov.propose(deployer.address, await wwxrp.getAddress(), 0, data, amount)).wait();
    const p = await gov.proposal(1);
    const action = await readOwnerProposalAction(gov, 1n, p);
    expect(action.data).to.equal(data);
    expect(action.creationBlock).to.equal(receipt.blockNumber);
    expect(hre.ethers.keccak256(action.data)).to.equal(p.dataHash);
    expect(action.createdAt).to.equal(BigInt((await hre.ethers.provider.getBlock(receipt.blockNumber)).timestamp));
    // Corrupted log data must be rejected before it reaches a signing operation.
    const badLogs = new Proxy(gov, {get(target, property) {
      if (property === "queryFilter") return async (...args) => (await target.queryFilter(...args)).map(log => ({
        ...log, args: {...log.args.toObject(), data: wwxrp.interface.encodeFunctionData("setGameMintScale", [9])},
      }));
      return Reflect.get(target, property);
    }});
    await expect(readOwnerProposalAction(badLogs, 1n, p)).to.be.rejectedWith("does not match its stored action");
    await gov.execute(1, action.data, {gasLimit: 300_000});
    expect(await wwxrp.gameMintScale()).to.equal(8n);
  });

  it("excludes long-idle support on an old proposal in a later transaction of the same block", async function () {
    const {ownerGovernance: gov, vault, wwxrp, deployer} = await loadFixture(deployFullProtocol);
    const token = await hre.ethers.getContractAt("DegenerusVaultShare", await vault.dgve());
    const amount = await token.balanceOf(deployer.address);
    await token.approve(await gov.getAddress(), hre.ethers.MaxUint256);
    await gov.propose(deployer.address, await wwxrp.getAddress(), 0,
      wwxrp.interface.encodeFunctionData("setGameMintScale", [7]), amount);
    await gov.withdraw();
    await gov.deposit(amount, hre.ethers.ZeroAddress);
    await time.increase(3600);

    const nonce = await deployer.getNonce("pending");
    await hre.network.provider.send("evm_setAutomine", [false]);
    try {
      const support = await gov.support(deployer.address, 1, 0, {nonce, gasLimit: 300_000});
      const execute = await gov.execute(1, wwxrp.interface.encodeFunctionData("setGameMintScale", [7]), {nonce: nonce + 1, gasLimit: 300_000});
      await hre.network.provider.send("evm_mine");
      const supported = await hre.ethers.provider.getTransactionReceipt(support.hash);
      const attempted = await hre.ethers.provider.getTransactionReceipt(execute.hash);
      expect(supported.status).to.equal(1);
      expect(attempted.status).to.equal(0);
      expect(attempted.blockNumber).to.equal(supported.blockNumber);
      expect(await gov.settledWeight(1)).to.equal(0n);
      expect(await gov.canExecute(1)).to.equal(false);
      expect((await gov.proposal(1)).executed).to.equal(false);
    } finally {
      await hre.network.provider.send("evm_setAutomine", [true]);
    }
    // An explicit gas limit submits the transaction for the next block; an estimate
    // against the current block would correctly still report insufficient settled approval.
    await gov.execute(1, wwxrp.interface.encodeFunctionData("setGameMintScale", [7]), {gasLimit: 300_000});
    expect(await wwxrp.gameMintScale()).to.equal(7n);
    await gov.withdraw();
    expect(await token.balanceOf(deployer.address)).to.equal(amount);
  });

  it("excludes a fresh deposit from direct gameplay in a later transaction of the same block", async function () {
    const {ownerGovernance: gov, vault, game, deployer} = await loadFixture(deployFullProtocol);
    const token = await hre.ethers.getContractAt("DegenerusVaultShare", await vault.dgve());
    const amount = await token.balanceOf(deployer.address);
    await token.approve(await gov.getAddress(), amount);
    const data = game.interface.encodeFunctionData("depositAfkingFunding", [1]);
    const value = hre.ethers.parseEther("0.01");
    const funding = await game.afkingFundingOf(await vault.getAddress());
    const nonce = await deployer.getNonce("pending");
    await hre.network.provider.send("evm_setAutomine", [false]);
    try {
      const deposit = await gov.deposit(amount, hre.ethers.ZeroAddress, {nonce, gasLimit: 300_000});
      const play = await gov.directAction(vault.interface.encodeFunctionData("playerAction", [await game.getAddress(), data, 0]), [deployer.address], {value, nonce: nonce + 1, gasLimit: 300_000});
      await hre.network.provider.send("evm_mine");
      const deposited = await hre.ethers.provider.getTransactionReceipt(deposit.hash);
      const attempted = await hre.ethers.provider.getTransactionReceipt(play.hash);
      expect(deposited.status).to.equal(1);
      expect(attempted.status).to.equal(0);
      expect(attempted.blockNumber).to.equal(deposited.blockNumber);
    } finally {
      await hre.network.provider.send("evm_setAutomine", [true]);
    }
    await gov.directAction(vault.interface.encodeFunctionData("playerAction", [await game.getAddress(), data, 0]), [deployer.address], {value, gasLimit: 300_000});
    expect(await game.afkingFundingOf(await vault.getAddress())).to.equal(funding + value);
    expect(await gov.proposalCount()).to.equal(0n);
  });
});
