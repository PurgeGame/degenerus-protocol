// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusVaultShare, DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {Icons32Data} from "../../contracts/Icons32Data.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {ContractAddresses as Pins} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

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
        _ownerAction(address(game), abi.encodeCall(DegenerusGame.setLootboxRngThreshold, (1 ether)), 0);
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
        ownerGovernance.directAction{value: 0.5 ether}(abi.encodeCall(DegenerusVault.playerAction, (address(game), abi.encodeCall(DegenerusGame.depositAfkingFunding, (uint32(1))), 0.5 ether)), owners);
        assertEq(game.afkingFundingOf(address(vault)), funding + 1 ether);
        assertEq(address(vault).balance, 0.5 ether);
        assertEq(address(ownerGovernance).balance, 0);
        assertEq(ownerGovernance.proposalCount(), 0);
        vm.prank(representative); vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector);
        ownerGovernance.directAction(abi.encodeCall(DegenerusVault.playerAction, (address(game), abi.encodeCall(DegenerusGame.setLootboxRngThreshold, (1 ether)), 0)), owners);
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
        bytes memory result = _ownerAction(address(admin), abi.encodeCall(DegenerusAdmin.propose, (address(next), bytes32(uint256(123)))), 0);
        uint256 id = abi.decode(result, (uint256));
        assertEq(admin.activeProposalId(address(ownerGovernance)), id);
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
}
