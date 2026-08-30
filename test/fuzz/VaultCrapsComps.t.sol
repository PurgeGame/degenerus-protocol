// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev The two game doors the vault self-subscribes through at construction. No-ops here: the
///      subscription is not what this suite is about, and standing it up would drag the whole
///      afking surface in behind it.
contract CompGameDouble {
    function subscribe(address, bool, bool, uint8, address) external payable {}
    function initPerpetualTickets() external {}
}

/// @dev Records every delivery the vault sends the table, and can refuse one on demand — the
///      refusal is how the suite proves a late failure unwinds the debit that preceded it.
contract CompCrapsDouble {
    address[] public toWhom;
    uint32[] public howMany;
    bool public refuse;

    error Refused();

    function setRefuse(bool r) external {
        refuse = r;
    }

    function deliverPasses(address player, uint32 normal, uint32) external returns (uint24) {
        if (refuse) revert Refused();
        toWhom.push(player);
        howMany.push(normal);
        return 0;
    }

    function calls() external view returns (uint256) {
        return toWhom.length;
    }

    function delivered() external view returns (uint256 total) {
        for (uint256 i; i < howMany.length; ++i) {
            total += howMany[i];
        }
    }
}

/// @title The vault's craps comp allowance
/// @notice Two hundred day passes, once, for whoever the vault's owner likes. The allowance is a
///         COUNT and nothing else: no vault asset moves, no FLIP is burned or minted, and the
///         table it spends against keeps no ledger of its own. So every rule worth having is an
///         accounting rule here — the figure only ever falls, it falls by exactly what was handed
///         out, and a batch that fails anywhere hands out nothing and spends nothing.
contract VaultCrapsCompsTest is Test {
    DegenerusVault internal vault;
    CompCrapsDouble internal craps;

    address internal owner = ContractAddresses.CREATOR;
    address internal stranger = makeAddr("stranger");
    address internal streamer = makeAddr("streamer");

    uint16 internal constant ALLOWANCE = 200;

    function setUp() public {
        vm.etch(ContractAddresses.GAME, address(new CompGameDouble()).code);
        vm.etch(ContractAddresses.CRAPS, address(new CompCrapsDouble()).code);
        craps = CompCrapsDouble(ContractAddresses.CRAPS);
        vault = new DegenerusVault();
    }

    function _list(address a) internal pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }

    function _many(uint256 n) internal pure returns (address[] memory r) {
        r = new address[](n);
        for (uint256 i; i < n; ++i) {
            r[i] = address(uint160(0xC0FFEE + i));
        }
    }

    // ── The allowance ───────────────────────────────────────────────────────

    /// @dev A fresh deployment holds the whole lifetime figure, and it sits in the salvage fields'
    ///      slot rather than taking one of its own.
    function test_aFreshDeploymentHoldsTheWholeAllowance() public view {
        assertEq(vault.crapsCompsRemaining(), ALLOWANCE, "the vault did not start on its allowance");
    }

    /// @dev The debit is exactly what crossed the boundary — recipients times the count each.
    function test_aGrantSpendsExactlyWhatItHandsOut() public {
        vm.prank(owner);
        uint16 left = vault.crapsGrantComps(_list(streamer), 3);

        assertEq(left, ALLOWANCE - 3, "the returned figure is not the remainder");
        assertEq(vault.crapsCompsRemaining(), ALLOWANCE - 3, "the stored figure is not the remainder");
        assertEq(craps.calls(), 1, "the table was not called once per recipient");
        assertEq(craps.toWhom(0), streamer, "the passes went to the wrong address");
        assertEq(craps.howMany(0), 3, "the recipient was not handed the requested count");
    }

    /// @dev Many recipients in one batch, each handed their own passes, one call apiece.
    function test_aBatchHandsEveryRecipientTheirOwn() public {
        address[] memory who = _many(5);
        vm.prank(owner);
        vault.crapsGrantComps(who, 2);

        assertEq(vault.crapsCompsRemaining(), ALLOWANCE - 10, "the batch debited the wrong total");
        assertEq(craps.calls(), 5, "one call per recipient is the contract");
        assertEq(craps.delivered(), 10, "the table did not receive the whole batch");
        for (uint256 i; i < 5; ++i) {
            assertEq(craps.toWhom(i), who[i], "a recipient was reordered or dropped");
        }
    }

    /// @dev THE ONLY CAP. Spend the allowance down to nothing and the next pass has nowhere to come
    ///      from — there is no setter, refill or renewal anywhere on the contract.
    function test_theAllowanceIsSpentOnceAndNeverRefills() public {
        vm.prank(owner);
        vault.crapsGrantComps(_list(streamer), uint16(ALLOWANCE));
        assertEq(vault.crapsCompsRemaining(), 0, "the allowance did not empty");

        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsGrantComps(_list(streamer), 1);
    }

    /// @dev A batch asking for more than is left takes nothing, rather than handing out the part
    ///      that would have fit.
    function test_anOversizedBatchIsRefusedWhole() public {
        vm.prank(owner);
        vault.crapsGrantComps(_list(streamer), 190);

        address[] memory who = _many(4);
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsGrantComps(who, 4); // 16 wanted, 10 left

        assertEq(vault.crapsCompsRemaining(), 10, "a refused batch moved the allowance");
        assertEq(craps.calls(), 1, "a refused batch reached the table");
    }

    /// @dev An empty batch and a zero count are both refused: neither spends anything, and both
    ///      would otherwise emit a grant that granted nothing.
    function test_anEmptyGrantIsRefused() public {
        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsGrantComps(new address[](0), 1);

        vm.prank(owner);
        vm.expectRevert(DegenerusVault.Insufficient.selector);
        vault.crapsGrantComps(_list(streamer), 0);
    }

    // ── Who may spend it ────────────────────────────────────────────────────

    /// @dev The DGVE majority and nobody else. The allowance is the vault's to give, and a comp is
    ///      a free entry into the protocol's own windows.
    function test_onlyTheVaultOwnerMayComp() public {
        vm.prank(stranger);
        vm.expectRevert(DegenerusVault.NotVaultOwner.selector);
        vault.crapsGrantComps(_list(streamer), 1);

        assertEq(vault.crapsCompsRemaining(), ALLOWANCE, "a refused caller moved the allowance");
    }

    // ── Failure is atomic ───────────────────────────────────────────────────

    /// @dev The debit lands BEFORE the table is called, so a recipient the table refuses has to
    ///      take the debit down with it. Anything else would let a reverting delivery burn the
    ///      allowance without seating anybody.
    function test_aRefusedDeliveryUnwindsTheDebit() public {
        craps.setRefuse(true);

        vm.prank(owner);
        vm.expectRevert(CompCrapsDouble.Refused.selector);
        vault.crapsGrantComps(_list(streamer), 5);

        assertEq(vault.crapsCompsRemaining(), ALLOWANCE, "a failed grant spent the allowance");
        assertEq(craps.calls(), 0, "a failed grant left a delivery behind");
    }

    /// @dev The zero address is refused, and refused ATOMICALLY — the recipients ahead of it in the
    ///      batch do not keep their passes.
    function test_aZeroRecipientTakesTheWholeBatchDown() public {
        address[] memory who = new address[](3);
        who[0] = streamer;
        who[1] = address(0);
        who[2] = stranger;

        vm.prank(owner);
        vm.expectRevert(DegenerusVault.ZeroAddress.selector);
        vault.crapsGrantComps(who, 1);

        assertEq(vault.crapsCompsRemaining(), ALLOWANCE, "a failed batch spent the allowance");
        assertEq(craps.calls(), 0, "the recipient ahead of the zero address kept its passes");
    }

    // ── The announcement ────────────────────────────────────────────────────

    /// @dev One event for the batch. Calldata carries who got what; what the log has to add is the
    ///      figure nobody can reconstruct without replaying every grant ever made.
    function test_aGrantAnnouncesWhatIsLeft() public {
        vm.recordLogs();
        vm.prank(owner);
        vault.crapsGrantComps(_many(3), 4);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 topic = keccak256("CrapsCompsGranted(address,uint256,uint16)");
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != topic) continue;
            ++seen;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), owner, "the wrong operator was named");
            (uint256 granted, uint16 left) = abi.decode(logs[i].data, (uint256, uint16));
            assertEq(granted, 12, "the log did not carry the batch total");
            assertEq(left, ALLOWANCE - 12, "the log did not carry the remainder");
        }
        assertEq(seen, 1, "a batch should announce exactly once");
    }

    // ── The figure only ever falls ──────────────────────────────────────────

    /// @dev No sequence of grants can raise the allowance or spend past it. The invariant is the
    ///      whole design: there is no refill path to test around.
    function testFuzz_theAllowanceOnlyEverFalls(uint8[8] calldata counts) public {
        uint256 spent;
        for (uint256 i; i < counts.length; ++i) {
            uint16 before = vault.crapsCompsRemaining();
            if (counts[i] == 0 || counts[i] > before) continue;

            vm.prank(owner);
            uint16 left = vault.crapsGrantComps(_list(streamer), counts[i]);

            assertEq(left, before - counts[i], "a grant moved the allowance by the wrong amount");
            assertLe(left, before, "the allowance rose");
            spent += counts[i];
        }
        assertEq(vault.crapsCompsRemaining(), ALLOWANCE - spent, "the allowance and the spend disagree");
        assertEq(craps.delivered(), spent, "the table received a different total than was debited");
    }
}
