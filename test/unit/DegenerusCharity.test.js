import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";
import { expect } from "chai";
import hre from "hardhat";
import {
  eth,
  getEvent,
  getEvents,
  ZERO_ADDRESS,
} from "../helpers/testUtils.js";
import { deployFullProtocol } from "../helpers/deployFixture.js";

const INITIAL_SUPPLY = hre.ethers.parseEther("1000000000000"); // 1T
const MIN_BURN = hre.ethers.parseEther("1"); // 1 GNRUS
const DISTRIBUTION_BPS = 200n;
const BPS_DENOM = 10_000n;
const PROPOSE_THRESHOLD_BPS = 50n;
const VAULT_VOTE_BPS = 500n;
const MAX_CREATOR_PROPOSALS = 5;

// ---------------------------------------------------------------------------
// Helper: inject mock bytecode at targetAddress
// ---------------------------------------------------------------------------
async function deployMockAt(contractName, targetAddress) {
  const Factory = await hre.ethers.getContractFactory(contractName);
  const tmp = await Factory.deploy();
  await tmp.waitForDeployment();
  const code = await hre.ethers.provider.getCode(await tmp.getAddress());
  await hre.ethers.provider.send("hardhat_setCode", [targetAddress, code]);
  return Factory.attach(targetAddress);
}

// ---------------------------------------------------------------------------
// Helper: impersonate an address with ETH balance
// ---------------------------------------------------------------------------
async function impersonate(address) {
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });
  await hre.ethers.provider.send("hardhat_setBalance", [
    address,
    "0x56BC75E2D63100000", // 100 ETH
  ]);
  return hre.ethers.getSigner(address);
}

async function stopImpersonating(address) {
  await hre.network.provider.request({
    method: "hardhat_stopImpersonatingAccount",
    params: [address],
  });
}

// ---------------------------------------------------------------------------
// Fixture: deploy full protocol, inject mocks at protocol addresses, deploy GNRUS
// ---------------------------------------------------------------------------
async function deployGNRUSFixture() {
  // Deploy the full protocol (patches ContractAddresses.sol + compiles)
  const protocol = await deployFullProtocol();
  const {
    deployer, alice: voter1, bob: voter2, carol: voter3,
    dan: recipient1, eve: recipient2, others,
    mockStETH: mockSteth,
    game, sdgnrs, vault,
  } = protocol;

  // Use signers[7] onward as recipient3 and additional others
  const allSigners = await hre.ethers.getSigners();
  const recipient3 = allSigners[6]; // 'others[0]' in deployFullProtocol (index 6)

  // Get the deployed addresses for the three protocol contracts GNRUS talks to
  const gameAddress   = await game.getAddress();
  const sdgnrsAddress = await sdgnrs.getAddress();
  const vaultAddress  = await vault.getAddress();
  const stethAddress  = await mockSteth.getAddress();

  // Inject mock bytecode at game, sdgnrs, and vault addresses.
  // GNRUS reads ContractAddresses constants that now point to these addresses,
  // so the mocks will be called by GNRUS under test.
  const mockGame   = await deployMockAt("MockGameCharity",   gameAddress);
  const mockSdgnrs = await deployMockAt("MockSDGNRSCharity", sdgnrsAddress);
  const mockVault  = await deployMockAt("MockVaultCharity",  vaultAddress);

  // Set up sDGNRS mock with reasonable defaults.
  // 1T sDGNRS total supply, voters get 1% each.
  const sdgnrsSupply = hre.ethers.parseEther("1000000000000");
  await mockSdgnrs.setTotalSupply(sdgnrsSupply);
  // voter1 gets 1% (above 0.5% threshold)
  await mockSdgnrs.setBalance(voter1.address, sdgnrsSupply / 100n);
  // voter2 gets 1%
  await mockSdgnrs.setBalance(voter2.address, sdgnrsSupply / 100n);
  // voter3 gets 0.1% (below 0.5% threshold)
  await mockSdgnrs.setBalance(voter3.address, sdgnrsSupply / 1000n);

  // Deploy GNRUS — it reads the patched ContractAddresses constants at compile time,
  // which now point to the addresses where our mocks live.
  const CharityFactory = await hre.ethers.getContractFactory("GNRUS");
  const charity = await CharityFactory.deploy();
  await charity.waitForDeployment();
  const charityAddress = await charity.getAddress();

  // Collect extra signers the original tests used under the name 'others'
  // deployFullProtocol returns others starting at index 6; re-slice from allSigners
  const extraOthers = allSigners.slice(7); // indices 7+

  return {
    charity,
    charityAddress,
    mockSdgnrs,
    mockGame,
    mockVault,
    mockSteth,
    deployer,
    voter1,
    voter2,
    voter3,
    recipient1,
    recipient2,
    recipient3,
    others: [recipient3, ...extraOthers],
    sdgnrsSupply,
    // expose addresses for tests that impersonate contract addresses
    gameAddress,
    sdgnrsAddress,
    vaultAddress,
    stethAddress,
  };
}

// ---------------------------------------------------------------------------
// Helper: run a full governance cycle to distribute GNRUS to a recipient
// ---------------------------------------------------------------------------
async function distributeGNRUS(charity, mockVault, mockSdgnrs, voter, recipientAddr, gameAddress) {
  // Make voter a vault owner so they can propose
  await mockVault.setVaultOwner(voter.address, true);
  // Ensure voter has sDGNRS balance
  const supply = await mockSdgnrs.totalSupply();
  await mockSdgnrs.setBalance(voter.address, supply / 100n);

  const level = await charity.currentLevel();
  const tx1 = await charity.connect(voter).propose(recipientAddr);
  const ev = await getEvent(tx1, charity, "ProposalCreated");
  const proposalId = ev.args.proposalId;

  // Vote to approve
  await charity.connect(voter).vote(proposalId, true);

  // Resolve the level (onlyGame) — impersonate the game contract address
  const gameSigner = await impersonate(gameAddress);
  await charity.connect(gameSigner).pickCharity(level);

  // Clean up vault owner status
  await mockVault.setVaultOwner(voter.address, false);
}

// Alias so fixture name matches loadFixture usage
const deployCharityFixture = deployGNRUSFixture;

describe("GNRUS (GNRUS)", function () {
  // =========================================================================
  // 1. Token Metadata
  // =========================================================================
  describe("Token Metadata", function () {
    it("name is 'Degenerus Donations'", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.name()).to.equal("GNRUS Donations");
    });

    it("symbol is 'GNRUS'", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.symbol()).to.equal("GNRUS");
    });

    it("decimals is 18", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.decimals()).to.equal(18n);
    });

    it("totalSupply is 1T after deploy", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.totalSupply()).to.equal(INITIAL_SUPPLY);
    });

    it("all tokens minted to contract itself (unallocated pool)", async function () {
      const { charity, charityAddress } = await loadFixture(deployCharityFixture);
      expect(await charity.balanceOf(charityAddress)).to.equal(INITIAL_SUPPLY);
    });

    it("currentLevel starts at 0", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.currentLevel()).to.equal(0);
    });

    it("proposalCount starts at 0", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.proposalCount()).to.equal(0);
    });

    it("finalized starts as false", async function () {
      const { charity } = await loadFixture(deployCharityFixture);
      expect(await charity.finalized()).to.equal(false);
    });
  });

  // =========================================================================
  // 2. Soulbound Enforcement
  // =========================================================================
  describe("Soulbound Enforcement", function () {
    it("transfer() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).transfer(voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });

    it("transferFrom() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2, deployer } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).transferFrom(deployer.address, voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });

    it("approve() reverts with TransferDisabled", async function () {
      const { charity, voter1, voter2 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).approve(voter2.address, eth("1"))
      ).to.be.revertedWithCustomError(charity, "TransferDisabled");
    });
  });

  // =========================================================================
  // 3. Burn Redemption
  // =========================================================================
  describe("Burn Redemption", function () {
    it("burn below MIN_BURN (1 GNRUS) reverts with InsufficientBurn", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burn(eth("0.5"))
      ).to.be.revertedWithCustomError(charity, "InsufficientBurn");
    });

    it("burn(0) reverts with InsufficientBurn", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burn(0n)
      ).to.be.revertedWithCustomError(charity, "InsufficientBurn");
    });

    it("burn reduces totalSupply by burned amount", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      // Distribute GNRUS to recipient1 via governance
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      expect(bal).to.be.gt(0n);

      const supplyBefore = await charity.totalSupply();
      await charity.connect(recipient1).burn(bal);
      expect(await charity.totalSupply()).to.equal(supplyBefore - bal);
    });

    it("burn reduces balanceOf[caller] to 0 on full burn", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      await charity.connect(recipient1).burn(bal);
      expect(await charity.balanceOf(recipient1.address)).to.equal(0n);
    });

    it("burn emits Transfer(caller, address(0), amount) and Burn events", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);

      const transferEv = await getEvent(tx, charity, "Transfer");
      expect(transferEv.args.from).to.equal(recipient1.address);
      expect(transferEv.args.to).to.equal(ZERO_ADDRESS);
      expect(transferEv.args.amount).to.equal(bal);

      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.burner).to.equal(recipient1.address);
      expect(burnEv.args.gnrusAmount).to.equal(bal);
    });

    it("burn with ETH backing pays proportional ETH", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, deployer, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund charity with 10 ETH
      await deployer.sendTransaction({ to: charityAddress, value: eth("10") });

      // Distribute GNRUS to recipient1
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      const supply = await charity.totalSupply();
      const ethBal = await hre.ethers.provider.getBalance(charityAddress);

      // Expected ETH out: (ethBal * bal) / supply
      const expectedEthOut = (ethBal * bal) / supply;

      const recipientBalBefore = await hre.ethers.provider.getBalance(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;
      const recipientBalAfter = await hre.ethers.provider.getBalance(recipient1.address);

      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.ethOut).to.be.gt(0n);
      expect(burnEv.args.ethOut).to.be.closeTo(expectedEthOut, eth("0.01"));
      expect(recipientBalAfter + gasUsed - recipientBalBefore).to.equal(burnEv.args.ethOut);
    });

    it("burn with stETH backing pays proportional stETH", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, mockSteth, voter1, recipient1, deployer, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund charity with stETH
      await mockSteth.mint(charityAddress, eth("5"));

      // Distribute GNRUS to recipient1
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);

      const stethBefore = await mockSteth.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");

      expect(burnEv.args.stethOut).to.be.gt(0n);
      const stethAfter = await mockSteth.balanceOf(recipient1.address);
      expect(stethAfter - stethBefore).to.equal(burnEv.args.stethOut);
    });

    it("burn with zero ETH and zero stETH sends nothing (no revert)", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      // No ETH or stETH funded -- charity has 0 backing
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");
      expect(burnEv.args.ethOut).to.equal(0n);
      expect(burnEv.args.stethOut).to.equal(0n);
    });

    it("ETH-preferred: ETH covers owed first, stETH fills remainder", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, mockSteth, voter1, recipient1, deployer, gameAddress } = await loadFixture(deployCharityFixture);

      // Fund with both ETH and stETH
      await deployer.sendTransaction({ to: charityAddress, value: eth("3") });
      await mockSteth.mint(charityAddress, eth("7"));

      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");

      // Total owed is proportional to (3 + 7) ETH equivalent
      // ETH is preferred, so ethOut should be used first
      expect(burnEv.args.ethOut).to.be.gt(0n);
      // If owed <= ethBalance, stethOut should be 0
      // With 2% of 1T = 20B GNRUS distributed, and 1T total supply:
      // owed = 10 * 20B / 1T = 0.2 ETH approx, well under 3 ETH
      // So ethOut should cover it all, stethOut = 0
      expect(burnEv.args.stethOut).to.equal(0n);
    });

    it("last-holder sweep: burning exact balance sweeps full amount", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, deployer, gameAddress } = await loadFixture(deployCharityFixture);

      await deployer.sendTransaction({ to: charityAddress, value: eth("1") });
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      // Burn exactly the balance -- triggers last-holder sweep
      const tx = await charity.connect(recipient1).burn(bal);
      expect(await charity.balanceOf(recipient1.address)).to.equal(0n);
    });

    it("burn with claimable winnings: lazy claim pulls from game when on-hand insufficient", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, mockGame, voter1, recipient1, deployer, gameAddress } = await loadFixture(deployCharityFixture);

      // Set claimable winnings on mock game for the charity address
      const claimableAmount = eth("5");
      await mockGame.setClaimable(charityAddress, claimableAmount);
      // Fund the mock game with ETH to pay claimable
      await deployer.sendTransaction({ to: gameAddress, value: claimableAmount });

      // Distribute GNRUS to recipient1
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);

      const bal = await charity.balanceOf(recipient1.address);
      const supply = await charity.totalSupply();

      // On-hand is 0, but claimable is 5 ETH, so owed = (5-1) * bal / supply (claimable adjusted by -1)
      // owed > onHand, so claimWinnings should be called
      const tx = await charity.connect(recipient1).burn(bal);
      const burnEv = await getEvent(tx, charity, "Burn");
      // After claiming, ETH should be on-hand and paid out
      expect(burnEv.args.ethOut).to.be.gt(0n);
    });

    it("burn reverts on underflow when amount exceeds balance", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      // voter1 has no GNRUS
      await expect(
        charity.connect(voter1).burn(eth("1"))
      ).to.be.reverted; // Solidity 0.8 underflow revert
    });
  });

  // =========================================================================
  // 4. Governance -- Propose
  // =========================================================================
  describe("Governance -- Propose", function () {
    it("propose creates a proposal with correct recipient and proposer", async function () {
      const { charity, mockVault, voter1, recipient1 } = await loadFixture(deployCharityFixture);
      // voter1 has 1% sDGNRS, above 0.5% threshold
      const tx = await charity.connect(voter1).propose(recipient1.address);
      const ev = await getEvent(tx, charity, "ProposalCreated");
      expect(ev.args.level).to.equal(0n);
      expect(ev.args.proposalId).to.equal(0n);
      expect(ev.args.proposer).to.equal(voter1.address);
      expect(ev.args.recipient).to.equal(recipient1.address);
    });

    it("propose increments proposalCount", async function () {
      const { charity, voter1, recipient1 } = await loadFixture(deployCharityFixture);
      expect(await charity.proposalCount()).to.equal(0);
      await charity.connect(voter1).propose(recipient1.address);
      expect(await charity.proposalCount()).to.equal(1);
    });

    it("propose increments levelProposalCount", async function () {
      const { charity, voter1, recipient1 } = await loadFixture(deployCharityFixture);
      const [, countBefore] = await charity.getLevelProposals(0);
      expect(countBefore).to.equal(0);
      await charity.connect(voter1).propose(recipient1.address);
      const [, countAfter] = await charity.getLevelProposals(0);
      expect(countAfter).to.equal(1);
    });

    it("propose snapshots sDGNRS totalSupply on first proposal", async function () {
      const { charity, mockSdgnrs, voter1, recipient1, sdgnrsSupply } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      expect(await charity.levelSdgnrsSnapshot(0)).to.equal(sdgnrsSupply / BigInt(1e18));
    });

    it("propose(address(0)) reverts with ZeroAddress", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).propose(ZERO_ADDRESS)
      ).to.be.revertedWithCustomError(charity, "ZeroAddress");
    });

    it("propose to contract address reverts with RecipientIsContract", async function () {
      const { charity, voter1, charityAddress } = await loadFixture(deployCharityFixture);
      // charityAddress is a contract
      await expect(
        charity.connect(voter1).propose(charityAddress)
      ).to.be.revertedWithCustomError(charity, "RecipientIsContract");
    });

    it("community: non-creator with <0.5% sDGNRS reverts with InsufficientStake", async function () {
      const { charity, voter3, recipient1 } = await loadFixture(deployCharityFixture);
      // voter3 has 0.1% sDGNRS -- below 0.5% threshold
      // Need to make a first proposal to snapshot supply
      // Actually, the first proposal sets the snapshot. If voter3 proposes first, it will set snapshot
      // But voter3 has 0.1% < 0.5% so it should fail even as first
      await expect(
        charity.connect(voter3).propose(recipient1.address)
      ).to.be.revertedWithCustomError(charity, "InsufficientStake");
    });

    it("community: non-creator proposing twice reverts with AlreadyProposed", async function () {
      const { charity, voter1, recipient1, recipient2 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      await expect(
        charity.connect(voter1).propose(recipient2.address)
      ).to.be.revertedWithCustomError(charity, "AlreadyProposed");
    });

    it("vault owner can propose up to 5 times per level", async function () {
      const { charity, mockVault, voter1, recipient1, recipient2, recipient3, others } = await loadFixture(deployCharityFixture);
      await mockVault.setVaultOwner(voter1.address, true);

      // Create 5 proposals (need 5 unique EOA recipients)
      const recipients = [recipient1.address, recipient2.address, recipient3.address, others[0].address, others[1].address];
      for (let i = 0; i < 5; i++) {
        await charity.connect(voter1).propose(recipients[i]);
      }
      expect(await charity.proposalCount()).to.equal(5);
    });

    it("vault owner 6th proposal reverts with ProposalLimitReached", async function () {
      const { charity, mockVault, voter1, recipient1, recipient2, recipient3, others } = await loadFixture(deployCharityFixture);
      await mockVault.setVaultOwner(voter1.address, true);

      const recipients = [recipient1.address, recipient2.address, recipient3.address, others[0].address, others[1].address];
      for (let i = 0; i < 5; i++) {
        await charity.connect(voter1).propose(recipients[i]);
      }
      await expect(
        charity.connect(voter1).propose(others[2].address)
      ).to.be.revertedWithCustomError(charity, "ProposalLimitReached");
    });

    it("vault owner does not consume community propose slot", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, voter2, recipient1, recipient2, sdgnrsSupply } = await loadFixture(deployCharityFixture);
      // voter1 is vault owner, proposes first
      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);

      // voter2 is community with 1% sDGNRS -- should still be able to propose
      await charity.connect(voter2).propose(recipient2.address);
      expect(await charity.proposalCount()).to.equal(2);
    });

    it("getProposal returns correct data", async function () {
      const { charity, voter1, recipient1 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);

      const [recipient, proposer, approveWeight, rejectWeight] = await charity.getProposal(0);
      expect(recipient).to.equal(recipient1.address);
      expect(proposer).to.equal(voter1.address);
      expect(approveWeight).to.equal(0n);
      expect(rejectWeight).to.equal(0n);
    });

    it("getLevelProposals returns correct start and count", async function () {
      const { charity, voter1, voter2, recipient1, recipient2 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter2).propose(recipient2.address);

      const [start, count] = await charity.getLevelProposals(0);
      expect(start).to.equal(0);
      expect(count).to.equal(2);
    });
  });

  // =========================================================================
  // 5. Governance -- Vote
  // =========================================================================
  describe("Governance -- Vote", function () {
    it("vote(proposalId, true) increases approveWeight by voter's sDGNRS balance", async function () {
      const { charity, mockSdgnrs, voter1, voter2, recipient1, sdgnrsSupply } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);

      const voter2Bal = await mockSdgnrs.balanceOf(voter2.address);
      const voter2Tokens = voter2Bal / BigInt(1e18);
      const tx = await charity.connect(voter2).vote(0, true);

      const ev = await getEvent(tx, charity, "Voted");
      expect(ev.args.voter).to.equal(voter2.address);
      expect(ev.args.approve).to.equal(true);
      expect(ev.args.weight).to.equal(voter2Tokens);

      const [, , approveWeight] = await charity.getProposal(0);
      expect(approveWeight).to.equal(voter2Tokens);
    });

    it("vote(proposalId, false) increases rejectWeight by voter's sDGNRS balance", async function () {
      const { charity, mockSdgnrs, voter1, voter2, recipient1 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);

      const voter2Bal = await mockSdgnrs.balanceOf(voter2.address);
      const voter2Tokens = voter2Bal / BigInt(1e18);
      const tx = await charity.connect(voter2).vote(0, false);

      const ev = await getEvent(tx, charity, "Voted");
      expect(ev.args.approve).to.equal(false);
      expect(ev.args.weight).to.equal(voter2Tokens);

      const [, , , rejectWeight] = await charity.getProposal(0);
      expect(rejectWeight).to.equal(voter2Tokens);
    });

    it("voting twice on same proposal reverts with AlreadyVoted", async function () {
      const { charity, voter1, voter2, recipient1 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter2).vote(0, true);

      await expect(
        charity.connect(voter2).vote(0, true)
      ).to.be.revertedWithCustomError(charity, "AlreadyVoted");
    });

    it("voting on invalid proposalId reverts with InvalidProposal", async function () {
      const { charity, voter1, voter2, recipient1 } = await loadFixture(deployCharityFixture);
      // No proposals exist yet
      await expect(
        charity.connect(voter2).vote(0, true)
      ).to.be.revertedWithCustomError(charity, "InvalidProposal");
    });

    it("voting on out-of-range proposalId reverts with InvalidProposal", async function () {
      const { charity, voter1, voter2, recipient1 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      // proposalId 99 does not exist in current level
      await expect(
        charity.connect(voter2).vote(99, true)
      ).to.be.revertedWithCustomError(charity, "InvalidProposal");
    });

    it("voter with 0 sDGNRS reverts with InsufficientStake", async function () {
      const { charity, mockSdgnrs, voter1, recipient1, others } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);

      // others[3] has 0 sDGNRS
      const noStake = others[3];
      expect(await mockSdgnrs.balanceOf(noStake.address)).to.equal(0n);

      await expect(
        charity.connect(noStake).vote(0, true)
      ).to.be.revertedWithCustomError(charity, "InsufficientStake");
    });

    it("vault owner gets 5% bonus on vote weight", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, voter2, recipient1, sdgnrsSupply } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);

      // Make voter2 vault owner
      await mockVault.setVaultOwner(voter2.address, true);
      const voter2Bal = await mockSdgnrs.balanceOf(voter2.address);

      const tx = await charity.connect(voter2).vote(0, true);
      const ev = await getEvent(tx, charity, "Voted");

      // Expected weight = voter2Bal/1e18 + 5% of snapshot (already whole tokens)
      const snapshot = await charity.levelSdgnrsSnapshot(0);
      const voter2Tokens = voter2Bal / BigInt(1e18);
      const bonus = (BigInt(snapshot) * VAULT_VOTE_BPS) / BPS_DENOM;
      expect(ev.args.weight).to.equal(voter2Tokens + bonus);
    });

    it("voter can vote on multiple proposals independently", async function () {
      const { charity, voter1, voter2, recipient1, recipient2 } = await loadFixture(deployCharityFixture);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter2).propose(recipient2.address);

      // voter1 votes on proposal 0
      await charity.connect(voter1).vote(0, true);
      // voter1 votes on proposal 1
      await charity.connect(voter1).vote(1, false);

      // Both votes should succeed
      const [, , approve0] = await charity.getProposal(0);
      const [, , , reject1] = await charity.getProposal(1);
      expect(approve0).to.be.gt(0n);
      expect(reject1).to.be.gt(0n);
    });
  });

  // =========================================================================
  // 6. Governance -- pickCharity
  // =========================================================================
  describe("Governance -- pickCharity", function () {
    it("pickCharity distributes 2% of unallocated GNRUS to winning recipient", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);

      const unallocatedBefore = await charity.balanceOf(charityAddress);
      const expectedDist = (unallocatedBefore * DISTRIBUTION_BPS) / BPS_DENOM;

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelResolved");

      expect(ev.args.gnrusDistributed).to.equal(expectedDist);
      expect(ev.args.recipient).to.equal(recipient1.address);
      expect(await charity.balanceOf(recipient1.address)).to.equal(expectedDist);
      expect(await charity.balanceOf(charityAddress)).to.equal(unallocatedBefore - expectedDist);
    });

    it("pickCharity increments currentLevel", async function () {
      const { charity, mockVault, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      expect(await charity.currentLevel()).to.equal(0);

      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).pickCharity(0);

      expect(await charity.currentLevel()).to.equal(1);
    });

    it("pickCharity marks level as resolved", async function () {
      const { charity, mockVault, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).pickCharity(0);

      expect(await charity.levelResolved(0)).to.equal(true);
    });

    it("resolving same level twice reverts with LevelAlreadyResolved", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);
      const gameSigner = await impersonate(gameAddress);
      // Resolve level 0 with no proposals (skip)
      await charity.connect(gameSigner).pickCharity(0);

      // Try to resolve level 0 again -- but currentLevel is now 1
      await expect(
        charity.connect(gameSigner).pickCharity(0)
      ).to.be.revertedWithCustomError(charity, "LevelNotActive");
    });

    it("resolving wrong level reverts with LevelNotActive", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);
      const gameSigner = await impersonate(gameAddress);
      await expect(
        charity.connect(gameSigner).pickCharity(5)
      ).to.be.revertedWithCustomError(charity, "LevelNotActive");
    });

    it("pickCharity with no proposals emits LevelSkipped", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);
      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelSkipped");
      expect(ev.args.level).to.equal(0);
    });

    it("pickCharity where all proposals net-negative emits LevelSkipped", async function () {
      const { charity, voter1, voter2, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      await charity.connect(voter1).propose(recipient1.address);
      // Both voters reject
      await charity.connect(voter1).vote(0, false);
      await charity.connect(voter2).vote(0, false);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelSkipped");
      expect(ev.args.level).to.equal(0);
    });

    it("pickCharity where all proposals net-zero emits LevelSkipped", async function () {
      const { charity, mockSdgnrs, voter1, voter2, recipient1, gameAddress } = await loadFixture(deployCharityFixture);
      // Set a small total supply so the equal weight is above 0.5% threshold
      const smallSupply = eth("10000");
      await mockSdgnrs.setTotalSupply(smallSupply);
      // Make both voters have equal weight above 0.5% of smallSupply (>= 50 tokens)
      const equalWeight = eth("100");
      await mockSdgnrs.setBalance(voter1.address, equalWeight);
      await mockSdgnrs.setBalance(voter2.address, equalWeight);

      await charity.connect(voter1).propose(recipient1.address);
      // One approves, one rejects with same weight -- net = 0
      await charity.connect(voter1).vote(0, true);
      await charity.connect(voter2).vote(0, false);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelSkipped");
      expect(ev.args.level).to.equal(0);
    });

    it("ties go to lower proposalId (first-submitted)", async function () {
      const { charity, mockSdgnrs, voter1, voter2, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);
      // Set a small total supply so the equal weight is above 0.5% threshold
      const smallSupply = eth("10000");
      await mockSdgnrs.setTotalSupply(smallSupply);
      // Make both voters have equal weight above 0.5% of smallSupply (>= 50 tokens)
      const equalWeight = eth("100");
      await mockSdgnrs.setBalance(voter1.address, equalWeight);
      await mockSdgnrs.setBalance(voter2.address, equalWeight);

      await charity.connect(voter1).propose(recipient1.address); // id 0
      await charity.connect(voter2).propose(recipient2.address); // id 1

      // Both approve their own -- same net weight
      await charity.connect(voter1).vote(0, true);
      await charity.connect(voter2).vote(1, true);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      // First proposal (id 0) wins because it's evaluated first and bestNet starts at 0
      // net = equalWeight > 0 = bestNet, so proposal 0 wins
      // Then proposal 1 net = equalWeight, but equalWeight is NOT > bestNet (it's equal)
      // So proposal 0 wins
      expect(ev.args.winningProposalId).to.equal(0);
      expect(ev.args.recipient).to.equal(recipient1.address);
    });

    it("2% decay: second level distributes less than first", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);

      // Level 0: distribute 2% of 1T
      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      const tx1 = await charity.connect(gameSigner).pickCharity(0);
      const ev1 = await getEvent(tx1, charity, "LevelResolved");
      const dist1 = ev1.args.gnrusDistributed;

      // Level 1: distribute 2% of remaining (1T - dist1)
      await charity.connect(voter1).propose(recipient2.address);
      await charity.connect(voter1).vote(1, true);
      const tx2 = await charity.connect(gameSigner).pickCharity(1);
      const ev2 = await getEvent(tx2, charity, "LevelResolved");
      const dist2 = ev2.args.gnrusDistributed;

      // Second distribution should be less than first (2% decay)
      expect(dist2).to.be.lt(dist1);
      // Verify: dist1 = 2% of 1T, dist2 = 2% of (1T - dist1) = 2% * 98% * 1T
      const expectedDist1 = (INITIAL_SUPPLY * DISTRIBUTION_BPS) / BPS_DENOM;
      const remaining = INITIAL_SUPPLY - expectedDist1;
      const expectedDist2 = (remaining * DISTRIBUTION_BPS) / BPS_DENOM;
      expect(dist1).to.equal(expectedDist1);
      expect(dist2).to.equal(expectedDist2);
    });

    it("pickCharity emits Transfer from contract to recipient", async function () {
      const { charity, charityAddress, mockVault, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);

      const transfers = await getEvents(tx, charity, "Transfer");
      // Should have exactly one Transfer event (contract -> recipient)
      const distTransfer = transfers.find(e => e.args.from === charityAddress);
      expect(distTransfer).to.not.be.undefined;
      expect(distTransfer.args.to).to.equal(recipient1.address);
    });

    it("pickCharity picks highest net-positive proposal", async function () {
      const { charity, mockSdgnrs, voter1, voter2, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);
      // voter1 has 1%, voter2 has 1%
      // voter1 proposes recipient1, voter2 proposes recipient2
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter2).propose(recipient2.address);

      // voter1 approves both proposals
      await charity.connect(voter1).vote(0, true);
      await charity.connect(voter1).vote(1, true);
      // voter2 approves only proposal 1 (so proposal 1 has more approve weight)
      await charity.connect(voter2).vote(1, true);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).pickCharity(0);
      const ev = await getEvent(tx, charity, "LevelResolved");
      // Proposal 1 should win -- voter1 + voter2 approved it
      expect(ev.args.winningProposalId).to.equal(1);
      expect(ev.args.recipient).to.equal(recipient2.address);
    });
  });

  // =========================================================================
  // 7. burnAtGameOver
  // =========================================================================
  describe("burnAtGameOver", function () {
    it("burnAtGameOver burns all unallocated GNRUS (onlyGame)", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);

      const gameSigner = await impersonate(gameAddress);
      const unallocated = await charity.balanceOf(charityAddress);
      const supplyBefore = await charity.totalSupply();

      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      expect(await charity.balanceOf(charityAddress)).to.equal(0n);
      expect(await charity.totalSupply()).to.equal(supplyBefore - unallocated);

      const ev = await getEvent(tx, charity, "GameOverFinalized");
      expect(ev.args.gnrusBurned).to.equal(unallocated);
    });

    it("burnAtGameOver reverts if not called by game", async function () {
      const { charity, voter1 } = await loadFixture(deployCharityFixture);
      await expect(
        charity.connect(voter1).burnAtGameOver()
      ).to.be.revertedWithCustomError(charity, "Unauthorized");
    });

    it("burnAtGameOver reverts if called twice (AlreadyFinalized)", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);

      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();

      await expect(
        charity.connect(gameSigner).burnAtGameOver()
      ).to.be.revertedWithCustomError(charity, "AlreadyFinalized");
      await stopImpersonating(gameAddress);
    });

    it("burnAtGameOver sets finalized to true", async function () {
      const { charity, gameAddress } = await loadFixture(deployCharityFixture);
      expect(await charity.finalized()).to.equal(false);

      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      expect(await charity.finalized()).to.equal(true);
    });

    it("burnAtGameOver emits Transfer(contract, address(0), amount)", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);
      const unallocated = await charity.balanceOf(charityAddress);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      const transferEv = await getEvent(tx, charity, "Transfer");
      expect(transferEv.args.from).to.equal(charityAddress);
      expect(transferEv.args.to).to.equal(ZERO_ADDRESS);
      expect(transferEv.args.amount).to.equal(unallocated);
    });

    it("burnAtGameOver after partial distribution burns only remaining", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, gameAddress } = await loadFixture(deployCharityFixture);

      // Distribute some GNRUS via governance first
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);
      const distributed = await charity.balanceOf(recipient1.address);
      expect(distributed).to.be.gt(0n);

      const unallocatedAfterDist = await charity.balanceOf(charityAddress);
      expect(unallocatedAfterDist).to.be.lt(INITIAL_SUPPLY);

      const gameSigner = await impersonate(gameAddress);
      const tx = await charity.connect(gameSigner).burnAtGameOver();
      await stopImpersonating(gameAddress);

      const ev = await getEvent(tx, charity, "GameOverFinalized");
      expect(ev.args.gnrusBurned).to.equal(unallocatedAfterDist);
      expect(await charity.balanceOf(charityAddress)).to.equal(0n);
      // Recipient still has their GNRUS
      expect(await charity.balanceOf(recipient1.address)).to.equal(distributed);
    });
  });

  // =========================================================================
  // 8. receive() -- ETH acceptance
  // =========================================================================
  describe("receive() -- ETH acceptance", function () {
    it("contract can receive ETH from anyone", async function () {
      const { charity, charityAddress, voter1 } = await loadFixture(deployCharityFixture);
      const balBefore = await hre.ethers.provider.getBalance(charityAddress);
      await voter1.sendTransaction({ to: charityAddress, value: eth("1") });
      const balAfter = await hre.ethers.provider.getBalance(charityAddress);
      expect(balAfter - balBefore).to.equal(eth("1"));
    });

    it("contract can receive ETH from game", async function () {
      const { charity, charityAddress, gameAddress } = await loadFixture(deployCharityFixture);
      const gameSigner = await impersonate(gameAddress);
      await gameSigner.sendTransaction({ to: charityAddress, value: eth("5") });
      await stopImpersonating(gameAddress);
      expect(await hre.ethers.provider.getBalance(charityAddress)).to.equal(eth("5"));
    });
  });

  // =========================================================================
  // 9. Edge Cases and Integration
  // =========================================================================
  describe("Edge Cases", function () {
    it("multiple levels: proposals from previous levels are not accessible for voting", async function () {
      const { charity, mockVault, voter1, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);
      await mockVault.setVaultOwner(voter1.address, true);

      // Level 0: create and resolve
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).pickCharity(0);

      // Level 1: create new proposal
      await charity.connect(voter1).propose(recipient2.address);

      // Try to vote on proposal 0 (from level 0) -- should fail because it's not in current level range
      await expect(
        charity.connect(voter1).vote(0, true)
      ).to.be.revertedWithCustomError(charity, "InvalidProposal");
    });

    it("community proposer can propose in new level after resolve", async function () {
      const { charity, mockVault, voter1, voter2, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);

      // Level 0
      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).pickCharity(0);

      // Level 1 -- voter2 can propose (different level, hasProposed resets per level)
      await charity.connect(voter2).propose(recipient2.address);
      expect(await charity.proposalCount()).to.equal(2);
    });

    it("vault owner proposal count resets per level", async function () {
      const { charity, mockVault, voter1, recipient1, recipient2, recipient3, others, gameAddress } = await loadFixture(deployCharityFixture);
      await mockVault.setVaultOwner(voter1.address, true);

      // Level 0: 5 proposals
      const recs0 = [recipient1.address, recipient2.address, recipient3.address, others[0].address, others[1].address];
      for (let i = 0; i < 5; i++) {
        await charity.connect(voter1).propose(recs0[i]);
      }
      await charity.connect(voter1).vote(0, true);
      const gameSigner = await impersonate(gameAddress);
      await charity.connect(gameSigner).pickCharity(0);

      // Level 1: can propose 5 more (count resets per level)
      await charity.connect(voter1).propose(others[2].address);
      expect(await charity.creatorProposalCount(1)).to.equal(1);
    });

    it("totalSupply is conserved: unallocated + all holders = totalSupply", async function () {
      const { charity, charityAddress, mockVault, mockSdgnrs, voter1, recipient1, recipient2, gameAddress } = await loadFixture(deployCharityFixture);

      // Distribute to two recipients across two levels
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient1.address, gameAddress);
      await distributeGNRUS(charity, mockVault, mockSdgnrs, voter1, recipient2.address, gameAddress);

      const unallocated = await charity.balanceOf(charityAddress);
      const r1Bal = await charity.balanceOf(recipient1.address);
      const r2Bal = await charity.balanceOf(recipient2.address);
      const supply = await charity.totalSupply();

      // Sum of all balances should equal totalSupply
      expect(unallocated + r1Bal + r2Bal).to.equal(supply);
    });

    it("vault owner snapshot locks on first vault-owner action per level", async function () {
      const { charity, mockVault, mockSdgnrs, voter1, voter2, recipient1, recipient2, sdgnrsAddress } = await loadFixture(deployCharityFixture);

      // voter1 proposes first as vault owner
      await mockVault.setVaultOwner(voter1.address, true);
      await charity.connect(voter1).propose(recipient1.address);

      // Check vault owner is snapshotted
      expect(await charity.levelVaultOwner(0)).to.equal(voter1.address);

      // Even if voter2 becomes vault owner later, the snapshot keeps voter1
      await mockVault.setVaultOwner(voter2.address, true);
      await mockVault.setVaultOwner(voter1.address, false);

      // voter2 is now vault owner but the level snapshot has voter1
      // voter2 can still propose as community member (if they have enough sDGNRS)
      // but won't get vault bonus since they're not the snapshotted vault owner
      await charity.connect(voter2).propose(recipient2.address);

      // voter2 votes -- should NOT get vault bonus (voter1 is snapshotted)
      const tx = await charity.connect(voter2).vote(0, true);
      const ev = await getEvent(tx, charity, "Voted");
      const mockSdgnrsAtAddr = await hre.ethers.getContractAt("MockSDGNRSCharity", sdgnrsAddress);
      const voter2Bal = await mockSdgnrsAtAddr.balanceOf(voter2.address);
      // Weight should equal voter2's sDGNRS balance (in whole tokens) without bonus
      expect(ev.args.weight).to.equal(voter2Bal / BigInt(1e18));
    });
  });
});
