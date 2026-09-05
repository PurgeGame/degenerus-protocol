// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CompGameDouble {
    function subscribe(address, bool, bool, uint8, address) external payable {}
    function initPerpetualTickets() external {}
}

/// @dev Records what the vault asked of the table's comp door, in order, and can refuse.
contract CompCrapsDouble {
    struct Ask {
        uint8 kind;
        address to;
        bool high;
        uint24 arg;
        uint8 count;
    }

    Ask[] public asks;
    bool public refuse;

    error Refused();

    function setRefuse(bool r) external {
        refuse = r;
    }

    function vaultComp(uint256 code) external returns (uint256 charged) {
        if (refuse) revert Refused();
        uint8 kind = uint8(code >> 160);
        uint8 count = uint8(code >> 200);
        asks.push(Ask(kind, address(uint160(code)), code & (1 << 168) != 0, uint24(code >> 176), count));
        charged = uint256(count) * 1 ether + kind;
    }

    function calls() external view returns (uint256) {
        return asks.length;
    }
}

/// @dev The vault's side of a comp: owner-only, every field forwarded untouched, every item
///      logged with what the table charged, and any refusal taking the whole batch down.
contract VaultCrapsCompsTest is Test {
    DegenerusVault internal vault;
    CompCrapsDouble internal craps;

    address internal owner = ContractAddresses.CREATOR;
    address internal stranger = makeAddr("stranger");
    address internal streamer = makeAddr("streamer");

    event CrapsCompGranted(address indexed operator, address indexed to, uint8 kind, uint256 charged);
    event CrapsCompAllowanceSet(address indexed operator, address indexed who, uint256 amount);

    function setUp() public {
        vm.etch(ContractAddresses.GAME, address(new CompGameDouble()).code);
        vm.etch(ContractAddresses.CRAPS, address(new CompCrapsDouble()).code);
        craps = CompCrapsDouble(ContractAddresses.CRAPS);
        vault = new DegenerusVault();
    }

    function _code(uint8 kind, address to, bool high, uint24 arg, uint8 count) internal pure returns (uint256) {
        return uint256(uint160(to)) | (uint256(kind) << 160) | (high ? (1 << 168) : 0) | (uint256(arg) << 176)
            | (uint256(count) << 200);
    }

    function _one(uint8 kind, address to, bool high, uint24 arg, uint8 count) internal pure returns (uint256[] memory r) {
        r = new uint256[](1);
        r[0] = _code(kind, to, high, arg, count);
    }

    function test_everyFieldReachesTheTableUntouched() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit CrapsCompGranted(owner, streamer, 3, 5 ether + 3);
        vault.crapsComp(_one(3, streamer, true, 123_456, 5));
        assertEq(craps.calls(), 1, "the table was not called once");
        (uint8 kind, address to, bool high, uint24 arg, uint8 count) = craps.asks(0);
        assertEq(kind, 3, "kind");
        assertEq(to, streamer, "to");
        assertTrue(high, "high");
        assertEq(arg, 123_456, "arg");
        assertEq(count, 5, "count");
    }

    function test_aBatchIsForwardedInOrder() public {
        uint256[] memory r = new uint256[](4);
        for (uint256 i; i < 4; ++i) {
            r[i] = _code(uint8(i), address(uint160(0xC0FFEE + i)), false, uint24(i), uint8(i + 1));
        }
        vm.prank(owner);
        vault.crapsComp(r);
        assertEq(craps.calls(), 4, "one call per item is the contract");
        for (uint256 i; i < 4; ++i) {
            (uint8 kind, address to,,,) = craps.asks(i);
            assertEq(kind, uint8(i), "an item was reordered");
            assertEq(to, address(uint160(0xC0FFEE + i)), "a recipient was reordered or dropped");
        }
    }

    function test_anEmptyBatchIsRefused() public {
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsComp(new uint256[](0));
    }

    function test_onlyTheVaultOwnerMayComp() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsComp(_one(4, streamer, false, 0, 1));
        assertEq(craps.calls(), 0, "a refused caller reached the table");
    }

    // ── Allowances ──────────────────────────────────────────────────────────

    address internal host = makeAddr("host");

    function test_onlyTheOwnerSetsAnAllowance() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.setCrapsCompAllowance(host, 10 ether);
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.ZeroAddress.selector);
        vault.setCrapsCompAllowance(address(0), 10 ether);
        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(vault));
        emit CrapsCompAllowanceSet(owner, host, 10 ether);
        vault.setCrapsCompAllowance(host, 10 ether);
        assertEq(vault.crapsCompAllowanceOf(host), 10 ether, "the allowance did not land");
    }

    function test_aDelegateSpendsItsAllowanceAtTheTablesPrice() public {
        vm.prank(owner);
        vault.setCrapsCompAllowance(host, 10 ether);
        // The double charges count x 1 ether + kind: 3 + 0 and 2 + 0 = 5 ether.
        uint256[] memory r = new uint256[](2);
        r[0] = _code(0, streamer, false, 1, 3);
        r[1] = _code(0, stranger, false, 2, 2);
        vm.prank(host);
        vault.crapsComp(r);
        assertEq(craps.calls(), 2, "the delegate's batch did not reach the table");
        assertEq(vault.crapsCompAllowanceOf(host), 5 ether, "the allowance was not charged what the table charged");
        // Over the remainder: refused whole, nothing reaches the table, nothing is spent.
        vm.prank(host);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsComp(_one(0, streamer, false, 1, 6));
        assertEq(craps.calls(), 2, "a refused batch reached the table");
        assertEq(vault.crapsCompAllowanceOf(host), 5 ether, "a refused batch spent the allowance");
        // Exactly the remainder is fine, and then the delegate is nobody again.
        vm.prank(host);
        vault.crapsComp(_one(0, streamer, false, 1, 5));
        assertEq(vault.crapsCompAllowanceOf(host), 0, "the allowance did not empty");
        vm.prank(host);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsComp(_one(0, streamer, false, 1, 1));
    }

    function test_theOwnerSpendsNoAllowance() public {
        vm.prank(owner);
        vault.setCrapsCompAllowance(owner, 1 ether);
        vm.prank(owner);
        vault.crapsComp(_one(0, streamer, false, 1, 50));
        assertEq(vault.crapsCompAllowanceOf(owner), 1 ether, "the owner's grant drew on an allowance");
    }

    function test_revokingAnAllowanceStopsTheDelegate() public {
        vm.prank(owner);
        vault.setCrapsCompAllowance(host, 10 ether);
        vm.prank(owner);
        vault.setCrapsCompAllowance(host, 0);
        vm.prank(host);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsComp(_one(0, streamer, false, 1, 1));
    }

    function test_aRefusedItemTakesTheWholeBatchDown() public {
        uint256[] memory r = new uint256[](2);
        r[0] = _code(4, streamer, false, 0, 1);
        r[1] = _code(4, stranger, false, 0, 1);
        craps.setRefuse(true);
        vm.prank(owner);
        vm.expectRevert(CompCrapsDouble.Refused.selector);
        vault.crapsComp(r);
        assertEq(craps.calls(), 0, "a failed batch left a grant behind");
    }

    function test_aZeroRecipientTakesTheWholeBatchDown() public {
        uint256[] memory r = new uint256[](2);
        r[0] = _code(4, streamer, false, 0, 1);
        r[1] = _code(4, address(0), false, 0, 1);
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.ZeroAddress.selector);
        vault.crapsComp(r);
        assertEq(craps.calls(), 0, "the recipient ahead of the zero address kept its grant");
    }
}
