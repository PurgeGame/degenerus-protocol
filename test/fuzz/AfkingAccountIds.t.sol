// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract AfkingIdSetHarness is GameAfkingModule {
    function add(address owner) external returns (uint32 id) {
        (id,) = _registerWallet(owner, 0);
        _addToSet(_subOf[id], id);
    }
    function remove(uint256 position) external {
        delete _subOf[_subscriberAt(position - 1)];
        _removeFromSet(position);
    }
    function at(uint256 index) external view returns (uint32) { return _subscriberAt(index); }
    function position(uint32 id) external view returns (uint32) { return _subOf[id].setPosition; }
    function root() external pure returns (uint256 r) { assembly { r := _subscribers.slot } }
    function smurf(uint32 ownerId) external returns (uint32 id) {
        id = uint32(wallets.length);
        wallets.push(uint256(ownerId) << 160);
    }
    function allowed(uint32 subId, uint32 fundId) external view returns (bool) {
        return _afkingFundingAllowed(subId, fundId);
    }
}

contract AfkingIdPackingTest is Test {
    function testFuzz_EightIdsPerWordAndSwapPopPreservesNeighbors(uint8 positionSeed) public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        uint256 expected;
        for (uint32 i = 1; i <= 9; ++i) {
            assertEq(h.add(address(uint160(i))), i);
            if (i <= 8) expected |= uint256(i) << ((i - 1) * 32);
        }
        uint256 base = uint256(keccak256(abi.encode(h.root())));
        assertEq(uint256(vm.load(address(h), bytes32(base))), expected);
        assertEq(uint256(vm.load(address(h), bytes32(base + 1))), 9);
        uint32 position = uint32(positionSeed % 8) + 1;
        h.remove(position);
        expected = (expected & ~(uint256(type(uint32).max) << ((position - 1) * 32)))
            | (uint256(9) << ((position - 1) * 32));
        assertEq(uint256(vm.load(address(h), bytes32(base))), expected);
        assertEq(uint256(vm.load(address(h), bytes32(base + 1))), 0, "tail lane cleared");
        assertEq(h.position(9), position);
        assertEq(h.position(position), 0);
        for (uint32 i; i < 8; ++i) assertEq(h.position(h.at(i)), i + 1);
        h.add(address(9));
        assertEq(uint256(vm.load(address(h), bytes32(h.root()))), 8, "idempotent set insertion");
    }

    function test_SameOwnerFundingUsesAccountIds() public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        uint32 a = h.add(address(11));
        uint32 b = h.add(address(12));
        uint32 s1 = h.smurf(a);
        uint32 s2 = h.smurf(a);
        assertTrue(h.allowed(s1, a));
        assertTrue(h.allowed(a, s1));
        assertTrue(h.allowed(s1, s2));
        assertFalse(h.allowed(s1, b));
        assertFalse(h.allowed(b, s2));
    }
}

contract AfkingFundingConsentIdsTest is DeployProtocol {
    address private constant FUNDER = address(0xF00D);
    address private constant SUB = address(0xA11CE);
    address private constant OP = address(0xB0B);
    uint32 private fundId;
    uint32 private subId;

    function setUp() public {
        _deployProtocol();
        fundId = _giveWalletId(FUNDER);
        subId = _giveWalletId(SUB);
    }

    function test_FundingConsentIsSeparateFromOperatorRightsAndRevocable() public {
        vm.startPrank(FUNDER);
        game.setOperatorApproval(fundId, SUB, true);
        assertFalse(game.afkingFundingApproved(fundId, subId));
        game.setAfkingFundingApproval(0, subId, true);
        assertTrue(game.afkingFundingApproved(fundId, subId));
        game.setAfkingFundingApproval(fundId, subId, false);
        assertFalse(game.afkingFundingApproved(fundId, subId));
        vm.stopPrank();
    }

    function test_OperatorCannotGrantFundingConsent() public {
        vm.prank(FUNDER);
        game.setOperatorApproval(fundId, OP, true);
        vm.prank(OP);
        vm.expectRevert(DegenerusGameStorage.NotApproved.selector);
        game.setAfkingFundingApproval(fundId, subId, true);
    }

    function test_ConsentRejectsUnallocatedSubscriber() public {
        vm.prank(FUNDER);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.setAfkingFundingApproval(fundId, type(uint32).max, true);
    }
}
