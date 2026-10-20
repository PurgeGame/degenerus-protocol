// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";
import {DegenerusOwnerGovernance} from "../../contracts/DegenerusOwnerGovernance.sol";

/// @title DegenesisVaultSpend -- the Vault's restricted Degenesis budget (check 9)
/// @notice The budget is built by real Degenesis volume and its real split. The Vault owner spends
///         it through DegenerusVault.spendDegenesis, which reaches the Degenesis module by the
///         facade's delegatecall with msg.sender == VAULT; exactly the purchase's cost leaves the
///         budget and nothing stays withdrawable. Only the no-sentinel case writes storage (the
///         Vault's claimable word cleared to 0), to exercise the module's documented branch.
contract DegenesisVaultSpend is DegenesisFixture {
    bytes32 internal constant SPENT_SIG = keccak256("DegenesisVaultSpent(uint256)");
    address internal owner = ContractAddresses.CREATOR;
    uint256 internal budget;

    function setUp() public override {
        super.setUp();
        address alice = _player("alice", 100 ether);
        vm.prank(alice);
        game.purchaseWhalePass{value: 81.6 ether}(0, 34, bytes32(0));
        _drain();
        _driveDay(2);
        _buyDegenesis(alice, 20 ether);
        _driveDay(3);
        budget = _vaultBudget();
        assertEq(budget, 5 ether, "fixture: a quarter of the 20 ETH cohort");
    }

    struct Snap {
        uint256 budget;
        uint256 vaultWord;
        uint256 claimablePool;
        uint256 pools;
        uint256 balance;
    }

    function _snap() internal view returns (Snap memory s) {
        s.budget = _vaultBudget();
        s.vaultWord = _packed(VAULT_ID);
        s.claimablePool = _claimablePool();
        s.pools = _nextTotal() + _futureTotal();
        s.balance = _gameBalance();
    }

    function _spend(bool whale, uint256 quantity, uint256 boxOrder, uint256 maxCost) internal returns (uint256 cost) {
        vm.recordLogs();
        vm.prank(owner);
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (whale, quantity, boxOrder, maxCost)), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == SPENT_SIG) {
                cost = abi.decode(logs[i].data, (uint256));
                ++n;
            }
        }
        assertEq(n, 1, "one DegenesisVaultSpent");
    }

    /// @dev The purchase's effect: budget down by `cost`, Vault word untouched, the obligation
    ///      released from claimablePool into the pools, no ETH moved.
    function _assertExactSpend(Snap memory a, uint256 cost) internal view {
        Snap memory b = _snap();
        assertEq(a.budget - b.budget, cost, "budget -= cost exactly");
        assertEq(b.vaultWord, a.vaultWord, "no cashout balance left (claimable and AFKing unchanged)");
        assertEq(a.claimablePool - b.claimablePool, cost, "the reservation funds the purchase");
        assertEq(b.pools - a.pools, cost, "the cost lands in the prize pools");
        assertEq(b.balance, a.balance, "no ETH leaves the Game");
        assertGe(_gameBalance(), _claimablePool(), "solvent");
    }

    // ------------------------------------------------------------------ paths

    function test_DirectGovernanceSpendUsesOnlyVaultBudgetWithoutProposal() public {
        DegenerusVaultShare token = ownerGovernance.dgve();
        uint256 amount = token.balanceOf(owner);
        vm.startPrank(owner);
        token.approve(address(ownerGovernance), amount);
        ownerGovernance.deposit(amount, address(0));
        uint256 cost = 10 * game.mintPrice();
        uint32 owed = game.entriesOwedView(1, ContractAddresses.VAULT);
        Snap memory before = _snap();
        address[] memory owners = new address[](1); owners[0] = owner;
        vm.expectRevert(DegenerusOwnerGovernance.NoMajority.selector);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost)), owners);
        vm.roll(vm.getBlockNumber() + 1);
        ownerGovernance.withdraw();
        token.approve(address(ownerGovernance), amount);
        ownerGovernance.deposit(amount, address(0));
        vm.expectRevert(DegenerusOwnerGovernance.NoMajority.selector);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost)), owners);
        // Read through the cheatcode: the optimizer may cache block.number within this test transaction.
        vm.roll(vm.getBlockNumber() + 1);
        ownerGovernance.directAction(abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost)), owners);
        vm.stopPrank();
        _assertExactSpend(before, cost);
        assertEq(game.entriesOwedView(1, ContractAddresses.VAULT) - owed, 40);
        assertEq(ownerGovernance.proposalCount(), 0);
        assertEq(ownerGovernance.totalEscrowed(), amount);
        assertEq(address(ownerGovernance).balance, 0);
    }

    function test_SpendTickets_ExactCost_SentinelMaxCostEqualsCost() public {
        assertEq(_claimableOf(VAULT_ID), 1, "fixture: the Vault holds its 1-wei sentinel");
        uint256 cost = 10 * game.mintPrice();
        uint32 owed = game.entriesOwedView(1, ContractAddresses.VAULT);
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, cost), cost, "spent the quote");
        _assertExactSpend(a, cost);
        assertEq(game.entriesOwedView(1, ContractAddresses.VAULT) - owed, 40, "ten tickets queued for the Vault");
    }

    function test_SpendLootbox_ExactCost() public {
        uint256 cost = 0.05 ether;
        Snap memory a = _snap();
        assertEq(_spend(false, 0, BoxOrderLib.boCustom(cost), cost), cost, "box cost");
        _assertExactSpend(a, cost);
    }

    function test_SpendTicketsAndLootbox_ExactCost() public {
        uint256 cost = 20 * game.mintPrice() + 0.03 ether;
        Snap memory a = _snap();
        assertEq(_spend(false, 8000, BoxOrderLib.boCustom(0.03 ether), cost), cost, "tickets + box");
        _assertExactSpend(a, cost);
    }

    function test_SpendWhalePass_ExactCost() public {
        uint256 cost = 2.4 ether;
        Snap memory a = _snap();
        assertEq(_spend(true, 1, 0, cost), cost, "one whale pass");
        _assertExactSpend(a, cost);
    }

    /// @notice Any maxCost from the cost up to the budget moves exactly the cost.
    /// forge-config: default.fuzz.runs = 32
    function testFuzz_SpendLeavesNoCashout(uint256 extra) public {
        uint256 cost = 10 * game.mintPrice();
        uint256 maxCost = cost + bound(extra, 0, budget - cost);
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, maxCost), cost, "spent the cost, not maxCost");
        _assertExactSpend(a, cost);
    }

    /// @notice The Vault's genuine claimable winnings are not touched: the budget pays.
    function test_VaultWinningsUntouched() public {
        _seedClaimable(VAULT_ID, 1 ether);
        uint256 cost = 10 * game.mintPrice();
        Snap memory a = _snap();
        _spend(false, 4000, 0, cost);
        _assertExactSpend(a, cost);
        assertEq(_claimableOf(VAULT_ID), 1 ether + 1, "winnings intact");
    }

    // ------------------------------------------------------------------ sentinel

    /// @notice Without the sentinel (the Vault's claimable word cleared in storage), the purchase
    ///         can spend only maxCost - 1, so maxCost == cost + 1 works and the 1 wei returns.
    function test_NoSentinel_MaxCostPlusOne_ReturnsOneWei() public {
        _clearVaultClaimable();
        uint256 cost = 10 * game.mintPrice();
        Snap memory a = _snap();
        assertEq(_spend(false, 4000, 0, cost + 1), cost, "cost moved");
        _assertExactSpend(a, cost);
        assertEq(_claimableOf(VAULT_ID), 0, "the extra wei went back to the budget");
    }

    function test_NoSentinel_MaxCostEqualsCost_Reverts() public {
        _clearVaultClaimable();
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost)), 0);
    }

    function _clearVaultClaimable() internal {
        bytes32 key = keccak256(abi.encode(uint256(VAULT_ID), GameSlots.BALANCES_PACKED));
        uint256 word = uint256(vm.load(address(game), key));
        assertEq(uint128(word), 1, "fixture: only the unbacked sentinel");
        vm.store(address(game), key, bytes32(word - 1));
    }

    // ------------------------------------------------------------------ refusals

    function test_NonVaultCaller_DirectGame_Reverts() public {
        address stranger = _player("stranger", 0);
        vm.prank(stranger);
        vm.expectRevert();
        game.spendDegenesis(false, 4000, 0, 0.1 ether);
        vm.prank(owner);
        vm.expectRevert();
        game.spendDegenesis(false, 4000, 0, 0.1 ether);
        assertEq(_vaultBudget(), budget, "budget intact");
    }

    function test_NonVaultCaller_DirectModule_Reverts() public {
        vm.prank(ContractAddresses.VAULT);
        vm.expectRevert();
        degenesisModule.spendDegenesis(false, 4000, 0, 0.1 ether);
        assertEq(_vaultBudget(), budget, "budget intact");
    }

    function test_NonOwner_VaultEntry_Reverts() public {
        address stranger = _player("stranger2", 0);
        vm.prank(stranger);
        vm.expectRevert();
        vault.spendDegenesis(false, 4000, 0, 0.1 ether);
    }

    function test_MaxCostBelowCost_Reverts() public {
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost - 1)), 0);
    }

    /// @notice The Vault's own winnings cannot top up a short maxCost.
    function test_MaxCostBelowCost_RevertsEvenWithVaultWinnings() public {
        _seedClaimable(VAULT_ID, 1 ether);
        uint256 cost = 10 * game.mintPrice();
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, cost - 1)), 0);
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, 0)), 0);
    }

    function test_MaxCostAboveBudget_Reverts() public {
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (false, 4000, 0, budget + 1)), 0);
        vm.prank(owner);
        vm.expectRevert();
        OwnerTargetCall.call(address(vault), abi.encodeCall(vault.spendDegenesis, (true, 3, 0, budget + 1)), 0); // three whale passes cost 7.2 ETH > 5 ETH
    }
}
