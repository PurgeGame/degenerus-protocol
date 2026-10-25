import fs from "node:fs";
import {expect} from "chai";
import hre from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import {deployFullProtocol, restoreAddresses, ownerAction} from "../helpers/deployFixture.js";
import {wireIcons32} from "../../scripts/lib/deployHelpers.js";

const data = JSON.parse(fs.readFileSync(new URL('../../scripts/data/icons32Data.symbolOrder.json', import.meta.url)));
async function finalizedFixture() { return deployFullProtocol({finalizeIcons: true}); }

describe("Icons32Data bootstrap and governance", function () {
  after(restoreAddresses);
  it("starts with empty data and an open setup window", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    expect(await icons32.initializedMask()).to.equal(0n);
    expect(await icons32.bootstrapClosed()).to.equal(false);
    expect(await icons32.finalized()).to.equal(false);
    for (let i=0;i<33;i++) expect(await icons32.data(i)).to.equal("");
    for (let q=0;q<4;q++) for (let i=0;i<8;i++) expect(await icons32.symbol(q,i)).to.equal("");
  });
  it("lets the creator initialize with no DGVE", async function () {
    const {icons32, vault, alice} = await loadFixture(deployFullProtocol);
    const dgve = await hre.ethers.getContractAt("DegenerusVaultShare", await vault.dgve());
    await dgve.transfer(alice.address, await dgve.totalSupply());
    await icons32.setPaths(0, ["initial"]);
    expect(await icons32.data(0)).to.equal("initial");
    await expect(icons32.connect(alice).setPaths(1,["unauthorized"])).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
  });
  it("rejects duplicates, empty entries and bad bounds atomically", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await icons32.setPaths(1,["existing"]);
    await expect(icons32.setPaths(0,["new", "replacement"])).to.be.revertedWithCustomError(icons32,"AlreadyInitialized");
    expect(await icons32.data(0)).to.equal("");
    expect(await icons32.initializedMask()).to.equal(2n);
    await expect(icons32.setPaths(0,[])).to.be.revertedWithCustomError(icons32,"InvalidInitialData");
    await expect(icons32.setPaths(0,[""])).to.be.revertedWithCustomError(icons32,"InvalidInitialData");
    await expect(icons32.setPaths(0,Array(11).fill("x"))).to.be.revertedWithCustomError(icons32,"MaxBatch");
    await expect(icons32.setPaths(32,["a","b"])).to.be.revertedWithCustomError(icons32,"IndexOutOfBounds");
    await expect(icons32.setSymbols(3,Array(8).fill("x"))).to.be.revertedWithCustomError(icons32,"InvalidQuadrant");
    await expect(icons32.setSymbols(0,["",...Array(7).fill("x")])).to.be.revertedWithCustomError(icons32,"InvalidInitialData");
    await icons32.setSymbols(0,data.symQ1);
    await expect(icons32.setSymbols(0,data.symQ1)).to.be.revertedWithCustomError(icons32,"AlreadyInitialized");
  });
  it("loads the canonical dataset in seven ordinary transactions and permanently closes setup", async function () {
    const {icons32, deployer} = await loadFixture(deployFullProtocol);
    const nonce = await deployer.getNonce();
    const firstBlock = await hre.ethers.provider.getBlockNumber();
    await wireIcons32(icons32,data);
    expect(await deployer.getNonce()-nonce).to.equal(7);
    const lastBlock = await hre.ethers.provider.getBlockNumber();
    for (let n=firstBlock+1;n<=lastBlock;n++) {
      const block = await hre.ethers.provider.getBlock(n);
      for (const hash of block.transactions) expect((await hre.ethers.provider.getTransactionReceipt(hash)).gasUsed).to.be.lt(16_777_216n);
    }
    expect(await icons32.bootstrapClosed()).to.equal(true);
    expect(await icons32.finalized()).to.equal(false);
    expect(await icons32.initializedMask()).to.equal((1n<<36n)-1n);
    await expect(icons32.setPaths(0,["later"])).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    await expect(icons32.finalize()).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    await ownerAction(icons32,"setPaths",[0,["governed"]]);
    expect(await icons32.data(0)).to.equal("governed");
    await ownerAction(icons32,"finalize");
    expect(await icons32.finalized()).to.equal(true);
  });
  it("resumes partial unordered uploads and treats completion as idempotent", async function () {
    const {icons32, deployer} = await loadFixture(deployFullProtocol);
    await icons32.setSymbols(2,data.symQ3);
    await icons32.setPaths(5,data.paths.slice(5,8));
    await wireIcons32(icons32,data);
    const nonce = await deployer.getNonce();
    await wireIcons32(icons32,data);
    expect(await deployer.getNonce()).to.equal(nonce);
    expect(await icons32.symbol(2,0)).to.equal("Club");
  });
  it("stops resumption on a mismatch without submitting more data", async function () {
    const {icons32, deployer} = await loadFixture(deployFullProtocol);
    await icons32.setPaths(0,["incorrect"]);
    const nonce = await deployer.getNonce();
    await expect(wireIcons32(icons32,data)).to.be.rejectedWith("differs from dataset");
    expect(await deployer.getNonce()).to.equal(nonce);
  });
  it("governance may take over incomplete setup, which cannot reopen", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await icons32.setPaths(0,["initial"]);
    await ownerAction(icons32,"setPaths",[0,[""]]);
    expect(await icons32.bootstrapClosed()).to.equal(true);
    await expect(icons32.setPaths(0,["retry"])).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    await expect(wireIcons32(icons32,data)).to.be.rejected;
    await ownerAction(icons32,"setPaths",[0,["governed"]]);
  });
  it("opt-in finalization happens on the final upload and prevents all later writes", async function () {
    this.timeout(300_000); // deploys a finalizing fixture and uploads every icon set: ~100s unloaded
    const {icons32} = await loadFixture(finalizedFixture);
    await icons32.setSymbols(0,data.symQ1);
    expect(await icons32.finalized()).to.equal(false);
    await wireIcons32(icons32,data,{finalize:true});
    expect(await icons32.finalized()).to.equal(true);
    await expect(ownerAction(icons32,"setPaths",[0,["changed"]])).to.be.revertedWithCustomError(icons32,"AlreadyFinalized");
  });
  it("rejects a deployment finalization flag inconsistent with the constructor", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await expect(wireIcons32(icons32,data,{finalize:true})).to.be.rejectedWith("immutable option");
  });
  it("reads back the canonical dataset by index and quadrant", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await wireIcons32(icons32,data);
    for (let i=0;i<33;i++) expect(await icons32.data(i)).to.equal(data.paths[i]);
    const quadrants = [data.symQ1,data.symQ2,data.symQ3];
    for (let q=0;q<3;q++) for (let i=0;i<8;i++) expect(await icons32.symbol(q,i)).to.equal(quadrants[q][i]);
    for (const q of [3,4,2n**256n-1n]) for (const i of [0,7,255]) expect(await icons32.symbol(q,i)).to.equal("");
  });
  it("enforces batch and index bounds on writes and reads", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await icons32.setPaths(0,data.paths.slice(0,10));
    expect(await icons32.initializedMask()).to.equal((1n<<10n)-1n);
    await icons32.setPaths(32,[data.paths[32]]);
    await expect(icons32.setPaths(33,["x"])).to.be.revertedWithCustomError(icons32,"IndexOutOfBounds");
    await expect(icons32.setPaths(hre.ethers.MaxUint256,["x"])).to.be.revertedWithPanic(0x11);
    await expect(icons32.setSymbols(4,Array(8).fill("x"))).to.be.revertedWithCustomError(icons32,"InvalidQuadrant");
    await expect(icons32.data(33)).to.be.revertedWithPanic(0x32);
    for (let q=0;q<3;q++) await expect(icons32.symbol(q,8)).to.be.revertedWithPanic(0x32);
  });
  it("lets no one but governance finalize, before or after setup", async function () {
    const {icons32, alice} = await loadFixture(deployFullProtocol);
    await expect(icons32.finalize()).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    await expect(icons32.connect(alice).finalize()).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    await expect(icons32.connect(alice).setSymbols(0,data.symQ1)).to.be.revertedWithCustomError(icons32,"NotVaultOwner");
    expect(await icons32.bootstrapClosed()).to.equal(false);
    expect(await icons32.finalized()).to.equal(false);
  });
  it("after finalization rejects every write and a second finalize, preserving data", async function () {
    const {icons32} = await loadFixture(deployFullProtocol);
    await wireIcons32(icons32,data);
    await ownerAction(icons32,"finalize");
    await expect(ownerAction(icons32,"setSymbols",[0,data.symQ1])).to.be.revertedWithCustomError(icons32,"AlreadyFinalized");
    await expect(ownerAction(icons32,"finalize")).to.be.revertedWithCustomError(icons32,"AlreadyFinalized");
    await expect(icons32.setPaths(0,["x"])).to.be.revertedWithCustomError(icons32,"AlreadyFinalized");
    expect(await icons32.data(32)).to.equal(data.paths[32]);
    expect(await icons32.symbol(2,7)).to.equal(data.symQ3[7]);
  });
});
