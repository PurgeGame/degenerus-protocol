// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Test} from "forge-std/Test.sol";
import {OwnerGovernanceFixture, OwnerCollateral, OwnerTargetStub} from "./OwnerGovernance.t.sol";
import {DegenerusOwnerGovernance as Gov} from "../../contracts/DegenerusOwnerGovernance.sol";
import {ContractAddresses as Pins} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

contract OwnerVoteHandler is Test {
    Gov public gov;
    OwnerCollateral public token;
    address[3] public owners = [address(0xA), address(0xB), address(0xC)];
    uint256 public executions;
    uint256 public directActions;
    uint256 public invalidDirectActions;
    uint256 public rejectedDirectActions;
    constructor(Gov g, OwnerCollateral t) { gov = g; token = t; }
    function _data() internal pure returns (bytes memory) {
        return abi.encodeCall(DegenerusGame.setLootboxRngThreshold, (123));
    }
    function propose(uint256 who) external {
        gov.propose(owners[who % 3], Pins.GAME, 0, _data(), 0);
    }
    function support(uint256 who, uint256 proposal) external {
        gov.support(owners[who % 3], bound(proposal, 1, gov.proposalCount()), 0);
    }
    function clear(uint256 who) external { gov.clearVote(owners[who % 3]); }
    function nextBlock(uint256 count) external { vm.roll(block.number + bound(count, 1, 100)); }
    function advance(uint256 elapsed) external { vm.warp(block.timestamp + bound(elapsed, 0, 8 days)); }
    function revoke(uint256 who) external {
        vm.prank(owners[who % 3]); gov.setVotingDelegate(address(0));
    }
    function withdrawAndAllocate(uint256 who) external {
        address owner = owners[who % 3];
        vm.prank(owner); gov.withdraw();
        uint256 amount = token.balanceOf(owner);
        vm.prank(owner); gov.deposit(amount, address(this));
    }
    function withdraw(uint256 who) external {
        vm.prank(owners[who % 3]); gov.withdraw();
    }
    function deposit(uint256 who, uint256 amount, bool delegated) external {
        address owner = owners[who % 3];
        amount = bound(amount, 1, token.balanceOf(owner));
        vm.prank(owner); gov.deposit(amount, delegated ? address(this) : address(0));
    }
    function changeDelegate(uint256 who, uint256 delegate) external {
        vm.prank(owners[who % 3]);
        gov.setVotingDelegate(delegate % 3 == 0 ? address(this) : delegate % 3 == 1 ? Pins.GAME : owners[(who % 3 + 1) % 3]);
    }
    function transfer(uint256 who, uint256 to, uint256 amount) external {
        address owner = owners[who % 3];
        amount = bound(amount, 0, token.balanceOf(owner));
        vm.prank(owner); token.transfer(owners[to % 3], amount);
    }
    function burn(uint256 who, uint256 amount) external {
        address owner = owners[who % 3];
        uint256 surplus = token.balanceOf(address(gov)) - gov.totalEscrowed();
        // Retain an attainable majority for the successful-execution postcondition.
        uint256 maximum = token.totalSupply() - (surplus * 10 + 1);
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, maximum < balance ? maximum : balance);
        vm.prank(owner); token.burn(amount);
    }
    function donate(uint256 who, uint256 amount) external {
        address owner = owners[who % 3];
        uint256 surplus = token.balanceOf(address(gov)) - gov.totalEscrowed();
        uint256 maximum = (token.totalSupply() - 1) / 10 - surplus;
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, maximum < balance ? maximum : balance);
        vm.prank(owner); token.transfer(address(gov), amount);
    }
    function ownerPropose(uint256 who, uint256 amount) external {
        address owner = owners[who % 3];
        amount = bound(amount, 0, token.balanceOf(owner));
        vm.prank(owner); gov.propose(owner, Pins.GAME, 0, _data(), amount);
    }
    function ownerSupport(uint256 who, uint256 proposal, uint256 amount) external {
        address owner = owners[who % 3];
        amount = bound(amount, 0, token.balanceOf(owner));
        proposal = bound(proposal, 1, gov.proposalCount());
        vm.prank(owner); gov.support(owner, proposal, amount);
    }
    function unauthorized(uint256 who, uint256 proposal, uint256 amount) external {
        // Existing standing allowances must never let a delegate pull fresh wallet funds.
        gov.support(owners[who % 3], bound(proposal, 1, gov.proposalCount()), bound(amount, 1, 1000));
    }
    function failingExecution(uint256 proposal) external {
        OwnerTargetStub target = OwnerTargetStub(Pins.GAME);
        target.configure(true, address(0), "");
        gov.execute(bound(proposal, 1, gov.proposalCount()), _data());
        revert("failing action unexpectedly executed");
    }
    function configureCallback(uint256 who) external {
        OwnerTargetStub(Pins.GAME).configure(false, address(gov), abi.encodeCall(gov.clearVote, (owners[who % 3])));
    }
    function directAction(uint256 mask, uint256 actor, uint256 action, uint256 ordering) public {
        address caller = actor % 5 == 0 ? address(this) : actor % 5 == 4 ? address(0xBAD) : owners[actor % 5 - 1];
        address[] memory selected = new address[](4);
        uint256 count;
        for (uint256 i; i < 3; ++i) {
            if (mask & (1 << i) != 0) selected[count++] = owners[i];
        }
        if (count > 0 && ordering % 3 == 1) selected[count++] = selected[0];
        if (count > 1 && ordering % 3 == 2) (selected[0], selected[count - 1]) = (selected[count - 1], selected[0]);
        assembly ("memory-safe") { mstore(selected, count) }
        bytes memory data;
        if (action % 4 == 0) data = abi.encodeCall(DegenerusVault.playerAction,
            (Pins.GAME, abi.encodeCall(DegenerusGame.depositAfkingFunding, (uint32(1))), 0));
        else if (action % 4 == 1) data = abi.encodeCall(DegenerusVault.spendDegenesis, (0, false, 400, 0, 1));
        else if (action % 4 == 2) data = abi.encodeCall(DegenerusVault.setLiquidationBuyFallback, (true, 0));
        else data = _data(); // A raw Game call cannot choose a non-Vault target.

        // Independent authorization recount immediately before CALL, including positions
        // that are absent, freshly deposited, revoked, or delegated to somebody else.
        uint256 weight;
        bool allowed = action % 4 < 2;
        address previous;
        for (uint256 i; i < count; ++i) {
            (uint256 amount,,, uint40 deposited, address delegate) = gov.positions(selected[i]);
            if (selected[i] <= previous || amount == 0 || (caller != selected[i] && caller != delegate)) allowed = false;
            previous = selected[i];
            if (deposited < block.number) weight += amount;
        }
        allowed = allowed && weight * 1000 > token.totalSupply() * 501;
        vm.prank(caller);
        try gov.directAction(data, selected) {
            ++directActions;
            if (!allowed) ++invalidDirectActions;
        } catch { ++rejectedDirectActions; }
    }
    function execute(uint256 proposal) external {
        gov.execute(bound(proposal, 1, gov.proposalCount()), _data()); ++executions;
    }
    /// @dev Deliberately reaches successful delegated execution amid adversarial random operations.
    function executeCoalition() public {
        uint256 p;
        for (uint256 i; i < 3; ++i) {
            address owner = owners[i];
            (uint256 amount,,,,) = gov.positions(owner);
            if (amount != 0) { vm.prank(owner); gov.withdraw(); }
            amount = token.balanceOf(owner);
            if (amount == 0) continue;
            vm.prank(owner); gov.deposit(amount, address(this));
            if (p == 0) p = gov.propose(owner, Pins.GAME, 0, _data(), 0);
            else gov.support(owner, p, 0);
        }
        vm.roll(block.number + 1);
        assertGt(gov.settledWeight(p) * 1000, token.totalSupply() * 501);
        gov.execute(p, _data()); ++executions;
    }
}

contract OwnerGovernanceInvariantTest is OwnerGovernanceFixture {
    OwnerVoteHandler internal handler;
    function setUp() public override {
        super.setUp(); handler = new OwnerVoteHandler(gov, token);
        vm.prank(A); gov.deposit(600, address(handler));
        vm.prank(B); gov.deposit(300, address(handler));
        vm.prank(C); gov.deposit(100, address(handler));
        bytes4[] memory selectors = new bytes4[](21);
        selectors[0] = handler.propose.selector; selectors[1] = handler.support.selector;
        selectors[2] = handler.clear.selector; selectors[3] = handler.nextBlock.selector;
        selectors[4] = handler.advance.selector; selectors[5] = handler.revoke.selector;
        selectors[6] = handler.withdrawAndAllocate.selector; selectors[7] = handler.execute.selector;
        selectors[8] = handler.executeCoalition.selector;
        selectors[9] = handler.withdraw.selector; selectors[10] = handler.deposit.selector;
        selectors[11] = handler.changeDelegate.selector; selectors[12] = handler.transfer.selector;
        selectors[13] = handler.burn.selector; selectors[14] = handler.donate.selector;
        selectors[15] = handler.ownerPropose.selector; selectors[16] = handler.ownerSupport.selector;
        selectors[17] = handler.unauthorized.selector; selectors[18] = handler.failingExecution.selector;
        selectors[19] = handler.configureCallback.selector;
        selectors[20] = handler.directAction.selector;
        targetSelector(FuzzSelector(address(handler), selectors)); targetContract(address(handler));
    }
    function invariantCustodyAndExactProposalWeights() public view {
        uint256 count = gov.proposalCount();
        uint256[] memory locked = new uint256[](count + 1);
        uint256[] memory settled = new uint256[](count + 1);
        uint256[] memory recent = new uint256[](count + 1);
        uint256 liability;
        for (uint256 i; i < 3; ++i) {
            (uint256 amount, uint256 p, uint40 assignedBlock, uint40 depositBlock,) = gov.positions(handler.owners(i));
            liability += amount;
            // A withdrawal zeroes only the amount (depositBlock and the delegate stay as dead
            // fields); amount == 0 is the closed state, and a closed position holds no vote.
            assertLe(depositBlock, block.number);
            if (amount == 0) assertEq(p, 0, "a closed position is assigned to no proposal");
            if (p == 0) { assertEq(assignedBlock, 0); }
            else {
                locked[p] += amount;
                if (assignedBlock < block.number) settled[p] += amount;
                if (assignedBlock == gov.proposal(p).recentBlock) recent[p] += amount;
            }
        }
        assertEq(gov.totalEscrowed(), liability);
        assertGe(token.balanceOf(address(gov)), liability);
        for (uint256 p = 1; p <= count; ++p) {
            Gov.Proposal memory proposal = gov.proposal(p);
            assertEq(proposal.lockedWeight, locked[p]); assertEq(gov.settledWeight(p), settled[p]);
            assertEq(proposal.recentWeight, recent[p]);
            assertLe(proposal.recentWeight, proposal.lockedWeight);
        }
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(handler.invalidDirectActions(), 0, "successful direct call lacked prior-block controlled majority or player selector");
    }
    function afterInvariant() public {
        handler.executeCoalition();
        assertGt(handler.executions(), 0);
        uint256 mask;
        for (uint256 i; i < 3; ++i) {
            (uint256 amount,,,,) = gov.positions(handler.owners(i));
            if (amount != 0) mask |= 1 << i;
        }
        handler.directAction(mask, 0, 0, 0);
        handler.directAction(mask, 0, 1, 0);
        handler.directAction(7, 4, 2, 0);
        assertGt(handler.directActions(), 0);
        assertGt(handler.rejectedDirectActions(), 0);
        invariantCustodyAndExactProposalWeights();
    }
}
