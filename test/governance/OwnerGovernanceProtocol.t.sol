// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {GameFacade} from "../../contracts/modules/GameFacade.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusVaultShare, DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {Icons32Data} from "../../contracts/Icons32Data.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {ContractAddresses as Pins} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract OwnerGovernanceProtocolTest is DeployProtocol {
    DegenerusVaultShare internal dgve;
    function setUp() public { _deployProtocol(); dgve = DegenerusVaultShare(vault.dgve()); }
    function _ownerAction(address target, bytes memory data, uint256 value) internal returns (bytes memory result) {
        uint256 amount = dgve.balanceOf(address(this));
        dgve.approve(address(ownerGovernance), amount);
        uint256 p = ownerGovernance.propose(address(this), target, value, data, amount);
        vm.roll(block.number + 1);
        result = ownerGovernance.execute{value: value}(p, data); ownerGovernance.withdraw();
    }
    function testFullOwnerRouteAndNoDirectMajorityShortcut() public {
        assertEq(address(ownerGovernance), Pins.OWNER_GOVERNANCE);
        assertEq(address(ownerGovernance.dgve()), address(dgve));
        assertFalse(vault.isVaultOwner(address(this))); assertTrue(vault.isVaultOwner(address(ownerGovernance)));
        vm.expectRevert(); game.setLootboxRngThreshold(1 ether);
        _ownerAction(address(game), abi.encodeCall(GameFacade.setLootboxRngThreshold, (1 ether)), 0);
        _ownerAction(address(vault), abi.encodeCall(DegenerusVault.setCrapsCompAllowance, (address(77), 12)), 0);
        _ownerAction(address(wwxrp), abi.encodeCall(WWXRP.setGameMintScale, (3)), 0);
        assertEq(wwxrp.gameMintScale(), 3);
        assertEq(ownerGovernance.totalEscrowed(), 0);
    }
    function testHeirsUseOneRepresentativeWithSeparatePositions() public {
        address heir = address(101); address representative = address(102);
        uint256 half = dgve.totalSupply() / 2;
        dgve.transfer(heir, half);
        dgve.approve(address(ownerGovernance), half);
        ownerGovernance.deposit(half, representative);
        vm.startPrank(heir); dgve.approve(address(ownerGovernance), half); ownerGovernance.deposit(half, representative); vm.stopPrank();
        vm.startPrank(representative);
        uint256 p = ownerGovernance.propose(address(this), address(wwxrp), 0, abi.encodeCall(WWXRP.setGameMintScale, (4)), 0);
        ownerGovernance.support(heir, p, 0); vm.stopPrank();
        vm.roll(block.number + 1);
        ownerGovernance.execute(p, abi.encodeCall(WWXRP.setGameMintScale, (4))); assertEq(wwxrp.gameMintScale(), 4);
        ownerGovernance.withdraw(); vm.prank(heir); ownerGovernance.withdraw();
        assertEq(dgve.balanceOf(representative), 0);
    }
    function testDirectVaultGameplayWithTwoDelegatedThirdsAndNoAdminBypass() public {
        address heir = address(101); address representative = address(102);
        uint256 third = dgve.totalSupply() / 3;
        dgve.transfer(heir, third);
        dgve.approve(address(ownerGovernance), third);
        ownerGovernance.deposit(third, representative);
        vm.startPrank(heir);
        dgve.approve(address(ownerGovernance), third); ownerGovernance.deposit(third, representative);
        vm.stopPrank();
        address[] memory owners = new address[](2);
        owners[0] = heir < address(this) ? heir : address(this);
        owners[1] = heir < address(this) ? address(this) : heir;
        vm.roll(block.number + 1);
        vm.deal(address(vault), 1 ether); vm.deal(representative, 1 ether);
        uint256 funding = game.afkingFundingOf(address(vault));
        vm.prank(representative);
        ownerGovernance.directAction{value: 0.5 ether}(abi.encodeCall(DegenerusVault.playerAction, (address(game), abi.encodeCall(GameFacade.depositAfkingFunding, (uint32(1))), 0.5 ether)), owners);
        assertEq(game.afkingFundingOf(address(vault)), funding + 1 ether);
        assertEq(address(vault).balance, 0.5 ether);
        assertEq(address(ownerGovernance).balance, 0);
        assertEq(ownerGovernance.proposalCount(), 0);
        vm.prank(representative); vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector);
        ownerGovernance.directAction(abi.encodeCall(DegenerusVault.playerAction, (address(game), abi.encodeCall(GameFacade.setLootboxRngThreshold, (1 ether)), 0)), owners);
        vm.prank(representative); vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector);
        ownerGovernance.directAction(abi.encodeCall(DegenerusVault.playerAction, (address(vault), abi.encodeCall(DegenerusVault.spendDegenesis, (0, false, 400, 0, 1 ether)), 0)), owners);
    }
    function testIconBootstrapTakeoverAndLaterChangesRequireGovernance() public {
        string[] memory paths = new string[](1); paths[0] = "initial";
        icons32.setPaths(0, paths);
        vm.expectRevert(Icons32Data.AlreadyInitialized.selector); icons32.setPaths(0, paths);
        paths[0] = "governance correction";
        _ownerAction(address(icons32), abi.encodeCall(Icons32Data.setPaths, (0, paths)), 0);
        assertTrue(icons32.bootstrapClosed());
        vm.expectRevert(Icons32Data.NotVaultOwner.selector); icons32.setPaths(1, paths);
        _ownerAction(address(icons32), abi.encodeCall(Icons32Data.finalize, ()), 0);
        assertTrue(icons32.finalized());
    }
    function testRecoveryOwnerNeedsNoGameRegistration() public {
        vm.warp(block.timestamp + 45 hours);
        // A closed registry must not block owner recovery, even with no gameplay identity.
        vm.mockCallRevert(address(game), abi.encodeWithSignature("registerWalletIdentity(address)", address(ownerGovernance)), "registry closed");
        MockVRFCoordinator next = new MockVRFCoordinator();
        bytes memory result = _ownerAction(address(admin), abi.encodeCall(DegenerusAdmin.propose, (address(next), bytes32(uint256(123)), 300_000)), 0);
        uint256 id = abi.decode(result, (uint256));
        assertEq(admin.activeProposalId(address(ownerGovernance)), id);
        // The owner path files under key 1, which is also the Vault's wallet identity. The Vault
        // cannot propose, so its own address reads no active proposal.
        assertEq(game.walletIdentityOf_g8516(address(vault)), 1, "fixture: the Vault's identity is 1");
        assertEq(admin.activeProposalId(address(vault)), 0, "the Vault has no proposal slot of its own");
        assertEq(admin.activeProposalId(address(0xBEEF)), 0, "an unregistered address has none");
    }
    /// @dev `lootboxRngPacked` bits 88..119: the mid-day request threshold in 0.001 ETH units.
    function _lootboxRngThreshold() internal view returns (uint256) {
        return ((uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> 88) & 0xFFFFFFFF) * 1e15;
    }
    function testLootboxRngThresholdStoresWhatItReports() public {
        assertEq(_lootboxRngThreshold(), 1 ether, "fixture: default threshold");
        vm.startPrank(Pins.OWNER_GOVERNANCE);
        // Below one stored unit and above the field: refused, nothing stored.
        vm.expectRevert(bytes4(keccak256("ZeroValue()")));
        game.setLootboxRngThreshold(1e15 - 1);
        vm.expectRevert(GameFacade.OutOfBounds.selector);
        game.setLootboxRngThreshold((uint256(1) << 32) * 1e15);
        assertEq(_lootboxRngThreshold(), 1 ether, "a refused value changed the threshold");
        // The event reports the stored value, rounded down to 0.001 ETH.
        vm.expectEmit(address(game));
        emit GameFacade.LootboxRngThresholdUpdated(1 ether, 2 ether);
        game.setLootboxRngThreshold(2.0005 ether);
        assertEq(_lootboxRngThreshold(), 2 ether, "stored value is the input rounded down");
        vm.expectEmit(address(game));
        emit GameFacade.LootboxRngThresholdUpdated(2 ether, 2 ether);
        game.setLootboxRngThreshold(2 ether + 1);
        // The largest storable value, with sub-unit dust on the input.
        uint256 top = uint256(type(uint32).max) * 1e15;
        vm.expectEmit(address(game));
        emit GameFacade.LootboxRngThresholdUpdated(2 ether, top);
        game.setLootboxRngThreshold(top + 1e15 - 1);
        assertEq(_lootboxRngThreshold(), top, "largest storable threshold");
        vm.stopPrank();
    }
    function testFullSupplyRefillCannotReviveWithdrawnSupport() public {
        uint256 supply = dgve.totalSupply(); dgve.approve(address(ownerGovernance), supply);
        uint256 p = ownerGovernance.propose(address(this), address(wwxrp), 0, abi.encodeCall(WWXRP.setGameMintScale, (7)), supply);
        ownerGovernance.withdraw(); vault.burnEth(supply);
        assertGt(dgve.totalSupply(), 0); assertFalse(ownerGovernance.canExecute(p));
        assertEq(ownerGovernance.proposal(p).lockedWeight, 0);
    }

    function testApprovedPayableSwapPaysExplicitRecipient() public {
        address recipient = address(0xBEEF);
        mockStETH.mint(address(game), 2 ether);
        uint256 gameEth = address(game).balance;
        _ownerAction(address(admin), abi.encodeCall(DegenerusAdmin.swapGameEthForStEth, (recipient)), 1 ether);
        assertEq(mockStETH.balanceOf(recipient), 1 ether);
        assertEq(mockStETH.balanceOf(address(ownerGovernance)), 0);
        assertEq(address(game).balance, gameEth + 1 ether);
        assertEq(address(ownerGovernance).balance, 0);
    }

    /// @dev A proposal created in the block where a daily word is later processed is dead: the
    ///      word's timestamp equals `createdAt`, so the proposal cannot resume on a later re-stall
    ///      at its decayed threshold even though its recorded approval would clear that threshold.
    function test_ProposalCreatedInTheRecoveryBlockIsDead() public {
        address voter = address(0xA11CE); address other = address(0xB0B);
        vm.startPrank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, voter, 4000e12);
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, other, 4500e12);
        vm.stopPrank();

        vm.warp(block.timestamp + 45 hours);
        MockVRFCoordinator next = new MockVRFCoordinator();
        bytes memory result = _ownerAction(address(admin), abi.encodeCall(DegenerusAdmin.propose, (address(next), bytes32(uint256(123)), 300_000)), 0);
        uint256 id = abi.decode(result, (uint256));
        (, uint40 createdAt, uint40 snapshot,, DegenerusAdmin.ProposalState state,,,,,) = admin.proposals(id);
        assertEq(createdAt, block.timestamp);

        // Approval below the initial 50% threshold: the proposal stays active.
        vm.prank(voter); admin.vote(id, true);
        uint40 approveWeight; uint40 rejectWeight;
        (,,,, state,,, approveWeight, rejectWeight,) = admin.proposals(id);
        assertEq(uint8(state), uint8(DegenerusAdmin.ProposalState.Active));
        assertGt(approveWeight, 0);
        assertLt(uint256(approveWeight) * 10_000, uint256(admin.threshold(id)) * snapshot);

        // A daily word is requested, delivered and applied in the proposal's own block.
        for (uint256 i; i < 1000 && game.lastVrfProcessed() != block.timestamp; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("recovery-block", request))));
            }
            game.mineRun(0);
        }
        assertEq(game.lastVrfProcessed(), createdAt);
        assertEq(block.timestamp, createdAt);

        // Re-stall past the admin threshold and past a decay step with no word processed.
        vm.warp(block.timestamp + 73 hours);
        assertGe(block.timestamp - game.lastVrfProcessed(), 44 hours);
        assertEq(admin.threshold(id), 3000);

        // The recorded approval clears the decayed threshold, so only the recovery rule stops it.
        assertGe(uint256(approveWeight) * 10_000, uint256(admin.threshold(id)) * snapshot);
        assertGt(approveWeight, rejectWeight);
        assertFalse(admin.canExecute(id));

        vm.expectEmit(true, false, false, false, address(admin));
        emit DegenerusAdmin.ProposalKilled(id);
        vm.prank(voter); admin.vote(id, true);
        (,,,, state,,,,,) = admin.proposals(id);
        assertEq(uint8(state), uint8(DegenerusAdmin.ProposalState.Killed));
    }

    /// @dev sDGNRS delivered after a proposal exists enters the denominator its votes resolve
    ///      against: a weight that meets 50% of the creation snapshot but not 50% of the larger
    ///      live voting supply does not execute, while approvals reaching 50% of the live supply do.
    function test_WeightDeliveredAfterCreationCountsInTheDenominator() public {
        address late = address(0xCAFE); address holder = address(0xA11CE); address other = address(0xB0B);
        vm.startPrank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, holder, 6000e12);
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, other, 4000e12);
        vm.stopPrank();

        vm.warp(block.timestamp + 45 hours);
        MockVRFCoordinator next = new MockVRFCoordinator();
        bytes memory result = _ownerAction(address(admin), abi.encodeCall(DegenerusAdmin.propose, (address(next), bytes32(uint256(123)), 300_000)), 0);
        uint256 id = abi.decode(result, (uint256));
        (, uint40 createdAt, uint40 snapshot,, DegenerusAdmin.ProposalState state,,,,,) = admin.proposals(id);
        assertEq(createdAt, block.timestamp);
        assertEq(uint256(snapshot), sdgnrs.votingSupply() / 1e12);
        assertGe(uint256(snapshot), 10_000);
        assertEq(admin.threshold(id), 5000);

        // New sDGNRS reaches a fresh voter after creation: 60% of the snapshot.
        uint256 lateWeight = (uint256(snapshot) * 6) / 10;
        vm.prank(address(game));
        sdgnrs.transferFromPool_g106128(sDGNRS.Pool.Reward, late, lateWeight * 1e12);
        uint256 liveSupply = sdgnrs.votingSupply() / 1e12;
        assertEq(liveSupply, uint256(snapshot) + lateWeight);

        // Non-vacuity: the weight clears the stale snapshot and misses the live supply.
        assertGe(lateWeight * 10_000, uint256(admin.threshold(id)) * snapshot);
        assertLt(lateWeight * 10_000, uint256(admin.threshold(id)) * liveSupply);

        vm.prank(late); admin.vote(id, true);
        uint40 approveWeight;
        (,,,, state,,, approveWeight,,) = admin.proposals(id);
        assertEq(uint256(approveWeight), lateWeight);
        assertEq(uint8(state), uint8(DegenerusAdmin.ProposalState.Active));
        assertFalse(admin.canExecute(id));
        assertTrue(admin.coordinator() != address(next));

        // Approvals from pre-existing holders bring the total to 50% of the live supply.
        vm.prank(other); admin.vote(id, true);
        (,,,, state,,, approveWeight,,) = admin.proposals(id);
        assertGe(uint256(approveWeight) * 10_000, uint256(admin.threshold(id)) * liveSupply);
        assertEq(uint8(state), uint8(DegenerusAdmin.ProposalState.Executed));
        assertEq(admin.coordinator(), address(next));
    }
}
