// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusAdmin} from "../../contracts/DegenerusAdmin.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";

contract IdVoteAdminHarness is DegenerusAdmin {
    function seedProposal() external {
        proposalCount = 1;
        proposals[1] = Proposal({proposer: 1, createdAt: uint40(block.timestamp), votingSnapshot: 1_000_000,
            path: ProposalPath.Community, state: ProposalState.Active, coordinator: address(0xBEEF),
            approveWeight: 0, rejectWeight: 0, keyHash: bytes32(uint256(1))});
    }
}

contract AccountIdOnlyTest is DeployProtocol {
    address private owner;
    uint32 private ownerId;
    uint32 private a;
    uint32 private b;

    function setUp() public {
        _deployProtocol();
        owner = makeAddr("id-only-owner");
        ownerId = _giveWalletId(owner);
        vm.deal(owner, 100 ether);
        uint256 price = game.mintPrice();
        vm.startPrank(owner);
        a = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        b = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        vm.stopPrank();
    }

    function test_SubaccountsResolveTheirOwnerAndKeepHistorySeparate() public view {
        uint256 base = uint256(keccak256(abi.encode(uint256(13))));
        for (uint32 id = a; id <= b; ++id) {
            uint256 element = uint256(vm.load(address(game), bytes32(base + id)));
            assertEq(uint160(element), 0);
            assertEq(uint32(element >> 160), ownerId);
            (address key, address payee, bool authorized) = game.resolveAccount(id, owner);
            assertEq(key, address(0));
            assertEq(payee, owner);
            assertTrue(authorized);
            assertEq(game.mintPackedOfId(id) >> 224, 0);
        }
        assertEq(game.walletIdOf(owner), ownerId);
        assertEq(game.mintPackedOfId(ownerId), 0, "creating subaccounts does not mint on the owner");
    }

    function test_PurchasesAuthorizeAndKeepSiblingHistorySeparate() public {
        uint256 beforeA = game.mintPackedOfId(a);
        uint256 beforeB = game.mintPackedOfId(b);
        uint256 price = game.mintPrice();
        address operator = makeAddr("id-only-operator");
        vm.deal(operator, price * 2);
        vm.prank(operator);
        vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.purchase{value: price}(a, 400, 0, 0, MintPaymentKind.DirectEth, false);
        vm.prank(owner);
        game.setOperatorApproval(a, operator, true);
        vm.prank(operator);
        game.purchase{value: price}(a, 400, 0, 0, MintPaymentKind.DirectEth, false);
        assertNotEq(game.mintPackedOfId(a), beforeA);
        assertEq(game.mintPackedOfId(b), beforeB);
        assertEq(game.mintPackedOfId(ownerId), 0);
        vm.prank(owner);
        game.setOperatorApproval(a, operator, false);
        vm.prank(operator);
        vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.purchase{value: price}(a, 400, 0, 0, MintPaymentKind.DirectEth, false);
    }

    function test_CoinflipAndWwxrpStayOnSelectedIdAndTokensReachOwner() public {
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(owner, 10_000);
        uint256 beforeB = coinflip.coinflipAmountById(b);
        uint256 beforeA = coinflip.coinflipAmountById(a);
        vm.prank(owner);
        coinflip.depositCoinflip(a, 2_000);
        assertGt(coinflip.coinflipAmountById(a), beforeA);
        assertEq(coinflip.coinflipAmountById(b), beforeB);
        vm.prank(ContractAddresses.GAME);
        wwxrp.creditPrize(a, 100 ether);
        vm.prank(owner);
        wwxrp.enter(a, 25 ether);
        assertEq(wwxrp.claimable(a), 75 ether);
        assertEq(wwxrp.claimable(b), 0);
        assertEq(wwxrp.balanceOf(owner), 0);
        vm.prank(owner);
        wwxrp.withdraw(a, 0);
        assertEq(wwxrp.claimable(a), 0);
        assertEq(wwxrp.balanceOf(owner), 75 ether);
    }

    function _voter(uint256 i) private returns (address voter, uint32 id) {
        voter = address(uint160(0xA000 + i));
        id = _giveWalletId(voter);
        vm.prank(ContractAddresses.GAME);
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, voter, (i + 1) * 1e12);
    }

    function test_GnrusFiveVoterLanesPreserveNeighborsAndRejectReplay() public {
        // Public slate starts empty; install a fixed recipient to isolate voting from slate administration.
        vm.store(address(gnrus), bytes32(uint256(7)), bytes32(uint256(uint160(address(0xBEEF)))));
        uint24 level = gnrus.currentLevel();
        address[5] memory voters;
        uint32[5] memory ids;
        // Align the first voter to a packed-word boundary.
        while (uint256(vm.load(address(game), bytes32(uint256(13)))) % 5 != 0) _giveWalletId(address(uint160(0xF000 + uint256(vm.load(address(game), bytes32(uint256(13)))))));
        for (uint256 i; i < 5; ++i) {
            (voters[i], ids[i]) = _voter(i);
            vm.prank(voters[i]);
            gnrus.vote(3);
        }
        uint256 word = uint256(vm.load(address(gnrus), keccak256(abi.encode(ids[0] / 5, uint256(3)))));
        for (uint256 i; i < 5; ++i) {
            assertEq(uint48(word >> (i * 48)), (uint256(level) << 20) | 8);
            assertTrue(gnrus.hasVoted(level, voters[i], 3));
            vm.prank(voters[i]);
            vm.expectRevert();
            gnrus.vote(3);
        }
    }

    function test_AdminFiveVoteLanesAndChangedDirectionPreserveNeighbors() public {
        vm.etch(address(admin), type(IdVoteAdminHarness).runtimeCode);
        vm.warp(block.timestamp + 22 days);
        IdVoteAdminHarness(payable(address(admin))).seedProposal();
        address[5] memory voters;
        uint32[5] memory ids;
        while (uint256(vm.load(address(game), bytes32(uint256(13)))) % 5 != 0) _giveWalletId(address(uint160(0xF000 + uint256(vm.load(address(game), bytes32(uint256(13)))))));
        for (uint256 i; i < 5; ++i) {
            (voters[i], ids[i]) = _voter(i);
            vm.prank(voters[i]);
            admin.vote(1, true);
        }
        vm.prank(voters[2]);
        admin.vote(1, false);
        bytes32 root = keccak256(abi.encode(uint256(1), uint256(5)));
        uint256 word = uint256(vm.load(address(admin), keccak256(abi.encode(ids[0] / 5, root))));
        for (uint256 i; i < 5; ++i) {
            uint256 direction = i == 2 ? 2 : 1;
            assertEq(uint48(word >> (i * 48)), ((i + 1) << 8) | direction);
            assertEq(uint256(admin.votes(1, voters[i])), direction);
            assertEq(admin.voteWeight(1, voters[i]), i + 1);
        }
    }
}
