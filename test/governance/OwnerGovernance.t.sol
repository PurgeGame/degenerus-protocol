// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {DegenerusOwnerGovernance as Gov} from "../../contracts/DegenerusOwnerGovernance.sol";
import {ContractAddresses as Pins} from "../../contracts/ContractAddresses.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

contract OwnerCollateral is ERC20 {
    constructor() ERC20("DGVE test collateral", "DGVE") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function burn(uint256 amount) external { _burn(msg.sender, amount); }
}

contract OwnerVaultStub {
    address public immutable dgve;
    constructor(address token) { dgve = token; }
    function spendDegenesis(bool, uint256, uint256, uint256 maxCost) external pure returns (uint256) {
        return maxCost;
    }
    function playerAction(address to, bytes calldata data, uint256 ethValue) external payable returns (bytes memory result) {
        if (to != Pins.GAME || bytes4(data) != DegenerusGame.depositAfkingFunding.selector) {
            revert DegenerusVault.UnsupportedPlayerAction();
        }
        bool ok;
        (ok, result) = to.call{value: msg.value + ethValue}(data);
        if (!ok) { assembly ("memory-safe") { revert(add(result, 32), mload(result)) } }
    }
}

contract OwnerTargetStub {
    uint256 public lastValue;
    uint256 public received;
    bool public shouldFail;
    address public callbackTarget;
    bytes public callbackData;
    bytes4 public callbackError;
    bool public callbackSucceeded;
    bool public failAfterCallback;
    function setFailAfterCallback(bool fail_) external { failAfterCallback = fail_; }
    function configure(bool fail_, address target, bytes calldata data) external {
        shouldFail = fail_; callbackTarget = target; callbackData = data;
    }
    function setLootboxRngThreshold(uint256 value) external payable {
        _action(value);
    }
    function depositAfkingFunding(uint32 id) external payable returns (uint256) {
        _action(id);
        return uint256(id) + 1;
    }
    function _action(uint256 value) private {
        require(!shouldFail, "target failed");
        lastValue = value; received += msg.value;
        if (callbackTarget != address(0)) {
            (bool ok, bytes memory result) = callbackTarget.call(callbackData);
            callbackSucceeded = ok;
            callbackError = bytes4(result);
        }
        require(!failAfterCallback, "failed after callback");
    }
}

contract OwnerCallbackBatch {
    bool[] public successes;
    bytes4[] public errors;
    function run(address target, bytes[] calldata calls) external {
        for (uint256 i; i < calls.length; ++i) {
            (bool ok, bytes memory result) = target.call(calls[i]);
            successes.push(ok);
            errors.push(bytes4(result));
        }
    }
}

abstract contract OwnerGovernanceFixture is Test {
    Gov internal gov;
    OwnerCollateral internal token;
    OwnerTargetStub internal target;
    address internal constant A = address(0xA);
    address internal constant B = address(0xB);
    address internal constant C = address(0xC);
    address internal constant D = address(0xD);

    function setUp() public virtual {
        token = new OwnerCollateral();
        vm.etch(Pins.VAULT, address(new OwnerVaultStub(address(token))).code);
        vm.etch(Pins.GAME, address(new OwnerTargetStub()).code);
        target = OwnerTargetStub(Pins.GAME);
        gov = new Gov();
        token.mint(A, 600); token.mint(B, 300); token.mint(C, 100);
        vm.prank(A); token.approve(address(gov), type(uint256).max);
        vm.prank(B); token.approve(address(gov), type(uint256).max);
        vm.prank(C); token.approve(address(gov), type(uint256).max);
    }
    function _data(uint256 value) internal pure returns (bytes memory) {
        return abi.encodeCall(DegenerusGame.setLootboxRngThreshold, (value));
    }
    function _propose(address who, uint256 amount) internal returns (uint256 id) {
        vm.prank(who); id = gov.propose(who, Pins.GAME, 0, _data(7), amount);
    }
    function _nextBlock() internal { vm.roll(block.number + 1); }
    function _positionAmount(address who) internal view returns (uint256 amount) {
        (amount,,,,) = gov.positions(who);
    }
    function _playerData() internal pure returns (bytes memory) {
        return abi.encodeCall(DegenerusGame.depositAfkingFunding, (uint32(1)));
    }
    function _owners(address first, address second) internal pure returns (address[] memory owners) {
        owners = new address[](second == address(0) ? 1 : 2);
        owners[0] = first;
        if (owners.length == 2) owners[1] = second;
    }

}

contract OwnerGovernanceTest is OwnerGovernanceFixture {
    function testDirectPlayerActionNeedsSettledControlledMajorityAndWritesNoStorage() public {
        vm.prank(A); gov.deposit(300, D);
        vm.prank(B); gov.deposit(300, D);
        address[] memory owners = _owners(A, B);
        vm.prank(D); vm.expectRevert(Gov.NoMajority.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), owners);
        _nextBlock();
        vm.prank(D); uint256 p = gov.propose(A, Pins.GAME, 0, _data(7), 0);
        // Current-block assignment does not erase the earlier deposit block for gameplay.
        vm.record();
        vm.prank(D); bytes memory result = gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), owners);
        (,bytes32[] memory writes) = vm.accesses(address(gov));
        assertEq(writes.length, 0);
        assertEq(abi.decode(abi.decode(result, (bytes)), (uint256)), 2);
        assertEq(gov.proposalCount(), p);
        assertEq(gov.proposal(p).lockedWeight, 300);
        assertEq(gov.settledWeight(p), 0);
        assertEq(gov.totalEscrowed(), 600);
        assertEq(token.balanceOf(D), 0);
    }

    function testDirectRejectsEveryAdminVaultSelectorAndRawNonVaultCalls() public {
        vm.prank(A); gov.deposit(600, address(0));
        _nextBlock();
        bytes4[12] memory forbidden = [
            DegenerusVault.setLiquidationBuyFallback.selector, DegenerusVault.crapsComp.selector,
            DegenerusVault.crapsCompDonate.selector, DegenerusVault.setCrapsCompAllowance.selector,
            DegenerusVault.wwxrpMint.selector, DegenerusVault.afkingSeatMint.selector,
            DegenerusVault.dgnrsUnwrapTo.selector, DegenerusVault.sweepToken.selector,
            DegenerusVault.sweepNft.selector, DegenerusGame.setLootboxRngThreshold.selector,
            DegenerusGame.depositAfkingFunding.selector, ERC20.transfer.selector
        ];
        for (uint256 i; i < forbidden.length; ++i) {
            vm.prank(A); vm.expectRevert(Gov.ActionNotAllowed.selector);
            gov.directAction(abi.encodePacked(forbidden[i]), _owners(A, address(0)));
        }
        vm.prank(A); vm.expectRevert(Gov.NoPosition.selector);
        gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(D, address(0)));
    }

    function testDirectPlayerActionRejectsDuplicatesUnsortedUncontrolledAndAdminCalls() public {
        vm.prank(A); gov.deposit(300, D);
        vm.prank(B); gov.deposit(300, D);
        _nextBlock();
        vm.startPrank(D);
        vm.expectRevert(Gov.InvalidOwnerOrder.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, A));
        vm.expectRevert(Gov.InvalidOwnerOrder.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(B, A));
        vm.expectRevert(Gov.NoMajority.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0)));
        vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _data(7), 0)), _owners(A, B));
        vm.expectRevert(DegenerusVault.UnsupportedPlayerAction.selector);
        gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.VAULT, abi.encodeCall(DegenerusVault.spendDegenesis, (false, 400, 0, 1 ether)), 0)), _owners(A, B));
        vm.expectRevert(Gov.ActionNotAllowed.selector);
        gov.directAction(abi.encodeCall(DegenerusVault.setLiquidationBuyFallback, (true, 0)), _owners(A, B));
        vm.expectRevert(Gov.ActionNotAllowed.selector); gov.directAction(hex"12", _owners(A, B));
        vm.stopPrank();
        vm.prank(A); vm.expectRevert(Gov.NotVotingController.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, B));
        vm.prank(B); gov.setVotingDelegate(address(0));
        vm.prank(D); vm.expectRevert(Gov.NotVotingController.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, B));
    }

    function testDirectPlayerActionStrictBoundaryLiveSupplyAndRedeposit() public {
        vm.prank(A); gov.deposit(501, address(0));
        _nextBlock();
        vm.prank(A); vm.expectRevert(Gov.NoMajority.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0)));
        vm.prank(B); token.burn(1);
        vm.prank(A); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0)));
        vm.prank(A); gov.withdraw();
        vm.prank(A); gov.deposit(501, address(0));
        vm.prank(A); vm.expectRevert(Gov.NoMajority.selector); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0)));
        _nextBlock();
        vm.prank(A); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0)));
    }

    function testDirectPlayerActionForwardsOnlySuppliedEthAndBubblesFailure() public {
        vm.prank(A); gov.deposit(600, address(0));
        _nextBlock();
        vm.deal(A, 2 ether); vm.deal(Pins.VAULT, 1 ether); vm.deal(address(gov), 10 ether);
        target.configure(true, address(0), "");
        vm.prank(A); vm.expectRevert("target failed");
        gov.directAction{value: 0.5 ether}(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 1 ether)), _owners(A, address(0)));
        assertEq(A.balance, 2 ether);
        target.configure(false, address(0), "");
        vm.expectEmit(true, false, false, true, address(gov));
        emit Gov.DirectAction(A, DegenerusVault.playerAction.selector, 0.5 ether);
        vm.prank(A); gov.directAction{value: 0.5 ether}(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 1 ether)), _owners(A, address(0)));
        assertEq(target.received(), 1.5 ether);
        assertEq(address(gov).balance, 10 ether);
        assertEq(gov.totalEscrowed(), 600);
    }

    function testDirectCallbackWithdrawalCannotReuseRemovedPosition() public {
        OwnerCallbackBatch actor = new OwnerCallbackBatch();
        vm.prank(A); token.transfer(address(actor), 600);
        vm.prank(address(actor)); token.approve(address(gov), 600);
        vm.prank(address(actor)); gov.deposit(600, address(0));
        _nextBlock();
        address[] memory owners = _owners(address(actor), address(0));
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(gov.withdraw, ());
        calls[1] = abi.encodeCall(gov.directAction, (abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), owners));
        target.configure(false, address(actor), abi.encodeCall(actor.run, (address(gov), calls)));
        vm.prank(address(actor)); gov.directAction(abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), owners);
        assertTrue(actor.successes(0)); assertFalse(actor.successes(1));
        assertEq(actor.errors(1), Gov.NoPosition.selector);
        assertEq(token.balanceOf(address(actor)), 600);
        assertEq(gov.totalEscrowed(), 0);
    }

    function testCalldataHashAndReadableProposalEvent() public {
        bytes memory data = _data(7);
        uint256 expiresAt = block.timestamp + gov.PROPOSAL_LIFETIME();
        bytes32 actionHash = keccak256(abi.encode(block.chainid, address(gov), uint256(1), Pins.GAME, uint256(0), data, expiresAt));
        vm.expectEmit(true, true, true, true, address(gov));
        emit Gov.ProposalCreated(1, A, A, Pins.GAME, 0, data, actionHash, expiresAt);
        uint256 p = _propose(A, 600);
        assertEq(gov.proposal(p).dataHash, keccak256(data));
        _nextBlock();
        vm.expectRevert(Gov.DataHashMismatch.selector); gov.execute(p, _data(8));
        vm.expectRevert(Gov.DataHashMismatch.selector); gov.execute(p, "");
        vm.expectRevert(Gov.DataHashMismatch.selector); gov.execute(p, bytes.concat(data, hex"00"));
        assertFalse(gov.proposal(p).executed);
        assertEq(gov.proposal(p).lockedWeight, 600);
        assertEq(target.lastValue(), 0);
        vm.expectEmit(true, true, false, true, address(gov));
        emit Gov.Executed(p, address(this));
        gov.execute(p, data);
        assertEq(target.lastValue(), 7);
    }

    function testValuePackingBoundRejectsBeforeCustodyChanges() public {
        vm.prank(A); vm.expectRevert(Gov.IncorrectValue.selector);
        gov.propose(A, Pins.GAME, uint256(type(uint96).max) + 1, _data(7), 600);
        assertEq(gov.proposalCount(), 0);
        assertEq(gov.totalEscrowed(), 0);
        assertEq(token.balanceOf(A), 600);
        vm.prank(A); uint256 p = gov.propose(A, Pins.GAME, type(uint96).max, _data(7), 600);
        assertEq(gov.proposal(p).value, type(uint96).max);
    }

    function testOversizedDepositCannotTruncateCustody() public {
        vm.prank(A); vm.expectRevert(); gov.deposit(uint256(type(uint128).max) + 1, D);
        assertEq(gov.totalEscrowed(), 0);
        assertEq(_positionAmount(A), 0);
        assertEq(token.balanceOf(A), 600);
        vm.prank(A); vm.expectRevert(); gov.propose(A, Pins.GAME, 0, _data(7), uint256(type(uint128).max) + 600);
        assertEq(gov.proposalCount(), 0);
        assertEq(gov.totalEscrowed(), 0);
        assertEq(_positionAmount(A), 0);
    }

    function testStrictThresholdAndSingleUse() public {
        vm.prank(A); token.transfer(B, 99);
        uint256 id = _propose(A, 501);
        _nextBlock();
        assertFalse(gov.canExecute(id));
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(id, _data(7));
        vm.prank(B); gov.support(B, id, 1);
        _nextBlock();
        gov.execute(id, _data(7));
        assertEq(target.lastValue(), 7);
        vm.prank(A); gov.withdraw();
        vm.prank(B); gov.withdraw();
        vm.expectRevert(Gov.InactiveProposal.selector); gov.execute(id, _data(7));
        assertEq(gov.totalEscrowed(), 0);
    }

    function testPooledCustodyIsNotApproval() public {
        uint256 p = _propose(A, 300);
        uint256 q = _propose(B, 300);
        _nextBlock();
        assertEq(token.balanceOf(address(gov)), 600);
        assertFalse(gov.canExecute(p)); assertFalse(gov.canExecute(q));
    }

    function testUnifiedCallerAndAmountRules() public {
        vm.prank(D); vm.expectRevert(Gov.OwnerOnly.selector); gov.propose(A, Pins.GAME, 0, _data(1), 600);
        vm.prank(D); vm.expectRevert(Gov.NoPosition.selector); gov.propose(A, Pins.GAME, 0, _data(1), 0);
        vm.prank(A); gov.deposit(400, D);
        vm.prank(D); vm.expectRevert(Gov.OwnerOnly.selector); gov.propose(A, Pins.GAME, 0, _data(1), 1);
        vm.prank(A); vm.expectRevert(Gov.PositionExists.selector); gov.propose(A, Pins.GAME, 0, _data(1), 1);
        vm.prank(C); vm.expectRevert(Gov.NotVotingController.selector); gov.propose(A, Pins.GAME, 0, _data(1), 0);
        vm.prank(D); uint256 p = gov.propose(A, Pins.GAME, 0, _data(1), 0);
        vm.prank(D); vm.expectRevert(Gov.OwnerOnly.selector); gov.support(A, p, 1);
        vm.prank(A); vm.expectRevert(Gov.PositionExists.selector); gov.support(A, p, 1);
        vm.prank(C); vm.expectRevert(Gov.NoPosition.selector); gov.support(C, p, 0);
        vm.prank(A); vm.expectRevert(Gov.AlreadyAssigned.selector); gov.support(A, p, 0);
        vm.prank(D); gov.clearVote(A);
        vm.prank(C); vm.expectRevert(Gov.NotVotingController.selector); gov.support(A, p, 0);
        vm.prank(D); gov.support(A, p, 0);
        assertEq(token.balanceOf(A), 200); // standing allowance was never used by D
        assertEq(gov.proposalCount(), 1); // rejected creation leaves no proposal
    }

    function testRevocationClearsSettledVoteAndAllowsOwnerOnlyReturn() public {
        vm.prank(A); gov.deposit(600, D);
        vm.prank(D); uint256 p = gov.propose(A, Pins.GAME, 0, _data(9), 0);
        _nextBlock(); assertTrue(gov.canExecute(p));
        vm.prank(D); vm.expectRevert(Gov.NoPosition.selector); gov.withdraw();
        vm.prank(D); vm.expectRevert(Gov.NoPosition.selector); gov.setVotingDelegate(C);
        vm.prank(A); gov.setVotingDelegate(address(0));
        assertEq(gov.settledWeight(p), 0);
        assertEq(gov.proposal(p).lockedWeight, 0);
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(p, _data(9));
        vm.prank(D); vm.expectRevert(Gov.NotVotingController.selector); gov.support(A, p, 0);
        vm.prank(A); gov.withdraw();
        assertEq(token.balanceOf(A), 600); assertEq(token.balanceOf(D), 0);
        vm.prank(D); vm.expectRevert(Gov.OwnerOnly.selector); gov.support(A, p, 600);
    }

    function testOneDelegateMultipleOwnersAndFreshBlockOnReuse() public {
        vm.prank(A); gov.deposit(300, D);
        vm.prank(B); gov.deposit(300, D);
        vm.warp(block.timestamp + 365 days);
        vm.prank(D); uint256 p = gov.propose(A, Pins.GAME, 0, _data(1), 0);
        vm.prank(D); gov.support(B, p, 0);
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(p, _data(1));
        _nextBlock(); gov.execute(p, _data(1));
        vm.prank(D); gov.clearVote(A);
        vm.prank(D); uint256 q = gov.propose(A, Pins.GAME, 0, _data(2), 0);
        vm.prank(D); gov.clearVote(B);
        vm.prank(D); gov.support(B, q, 0);
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(q, _data(2));
        _nextBlock(); gov.execute(q, _data(2));
        assertEq(target.lastValue(), 2);
        assertEq(token.balanceOf(D), 0);
    }

    function testDelegateReplacementResetsAgeAndOldDelegateCannotClear() public {
        uint256 p = _propose(A, 600);
        _nextBlock();
        vm.prank(A); gov.setVotingDelegate(D);
        vm.prank(D); gov.support(A, p, 0);
        vm.prank(A); gov.setVotingDelegate(C);
        vm.prank(D); vm.expectRevert(Gov.NotVotingController.selector); gov.clearVote(A);
        vm.prank(C); gov.support(A, p, 0);
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(p, _data(7));
    }

    function testWithdrawInAssignmentBlockAfterExpiryAndAfterTargetFailure() public {
        uint256 p = _propose(A, 600);
        vm.prank(A); gov.withdraw();
        vm.prank(A); gov.support(A, p, 600);
        _nextBlock();
        target.configure(true, address(0), "");
        vm.expectRevert("target failed"); gov.execute(p, _data(7));
        assertFalse(gov.proposal(p).executed);
        vm.prank(A); gov.withdraw();
        vm.prank(A); gov.support(A, p, 600);
        vm.warp(gov.proposal(p).expiresAt);
        vm.expectRevert(Gov.InactiveProposal.selector); gov.execute(p, _data(7));
        vm.prank(A); gov.withdraw();
        assertEq(token.balanceOf(A), 600);
    }

    function testLargeRevertingActionCannotBlockWithdrawal() public {
        bytes memory data = bytes.concat(_data(7), new bytes(4096));
        vm.prank(A); uint256 p = gov.propose(A, Pins.GAME, 0, data, 600);
        _nextBlock();
        target.configure(true, address(0), "");
        vm.expectRevert("target failed"); gov.execute(p, data);
        vm.prank(A); gov.withdraw{gas: 120_000}();
        assertEq(token.balanceOf(A), 600);
        assertEq(gov.totalEscrowed(), 0);
        assertEq(gov.proposal(p).lockedWeight, 0);
    }

    function testSupplyChangesAndUnsolicitedTokensNeverVote() public {
        uint256 p = _propose(A, 400);
        vm.prank(B); token.transfer(address(gov), 300);
        _nextBlock(); assertFalse(gov.canExecute(p));
        vm.prank(A); gov.withdraw();
        assertEq(gov.totalEscrowed(), 0); assertEq(token.balanceOf(address(gov)), 300);
        p = _propose(A, 400);
        vm.prank(A); token.burn(200);
        vm.prank(C); token.burn(100);
        _nextBlock(); gov.execute(p, _data(7));
    }

    function testExactEthAndRollback() public {
        vm.prank(A); uint256 p = gov.propose(A, Pins.GAME, 1 ether, _data(4), 600);
        _nextBlock();
        vm.deal(address(this), 3 ether); vm.deal(address(gov), 10 ether);
        vm.expectRevert(Gov.IncorrectValue.selector); gov.execute(p, _data(4));
        target.configure(true, address(0), "");
        vm.expectRevert("target failed"); gov.execute{value: 1 ether}(p, _data(4));
        assertFalse(gov.proposal(p).executed);
        target.configure(false, address(0), "");
        gov.execute{value: 1 ether}(p, _data(4));
        assertEq(target.received(), 1 ether); assertEq(address(gov).balance, 10 ether);
    }

    function testForbiddenTargetsAndSelectors() public {
        vm.prank(A); vm.expectRevert(Gov.ActionNotAllowed.selector);
        gov.propose(A, address(token), 0, abi.encodeCall(token.transfer, (D, 600)), 600);
        vm.prank(A); vm.expectRevert(Gov.ActionNotAllowed.selector);
        gov.propose(A, Pins.VAULT, 0, abi.encodeCall(DegenerusVault.burnEth, (600)), 600);
        vm.prank(A); vm.expectRevert(Gov.ActionNotAllowed.selector);
        gov.propose(A, address(gov), 0, abi.encodeCall(gov.withdraw, ()), 600);
        vm.prank(A); vm.expectRevert(Gov.ActionNotAllowed.selector);
        gov.propose(A, Pins.GAME, 0, hex"12", 600);
        assertEq(gov.proposalCount(), 0); assertEq(token.balanceOf(A), 600);
    }

    function testUnauthorizedCallbacksCannotChangeCustodyOrReplay() public {
        bytes[] memory attacks = new bytes[](8);
        attacks[0] = abi.encodeCall(gov.deposit, (1, address(0)));
        attacks[1] = abi.encodeCall(gov.propose, (A, Pins.GAME, 0, _data(1), 0));
        attacks[2] = abi.encodeCall(gov.support, (A, 1, 0));
        attacks[3] = abi.encodeCall(gov.clearVote, (A));
        attacks[4] = abi.encodeCall(gov.setVotingDelegate, (D));
        attacks[5] = abi.encodeCall(gov.withdraw, ());
        attacks[6] = abi.encodeCall(gov.execute, (1, _data(7)));
        attacks[7] = abi.encodeCall(gov.directAction, (abi.encodeCall(DegenerusVault.playerAction, (Pins.GAME, _playerData(), 0)), _owners(A, address(0))));
        for (uint256 i; i < attacks.length; ++i) {
            uint256 p = _propose(A, 600);
            _nextBlock(); target.configure(false, address(gov), attacks[i]); gov.execute(p, _data(7));
            assertFalse(target.callbackSucceeded());
            assertTrue(gov.proposal(p).executed);
            assertEq(gov.totalEscrowed(), 600);
            assertEq(_positionAmount(A), 600);
            vm.prank(A); gov.withdraw();
        }
    }

    function testAuthorizedCallbackCannotReuseSettledWeightOrReplay() public {
        OwnerCallbackBatch actor = new OwnerCallbackBatch();
        vm.prank(A); gov.deposit(600, address(actor));
        vm.prank(address(actor)); uint256 p = gov.propose(A, Pins.GAME, 0, _data(7), 0);
        uint256 q = _propose(B, 300);
        _nextBlock();
        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeCall(gov.clearVote, (A));
        calls[1] = abi.encodeCall(gov.support, (A, q, 0));
        calls[2] = abi.encodeCall(gov.execute, (q, _data(7)));
        calls[3] = abi.encodeCall(gov.support, (A, q, 1));
        calls[4] = abi.encodeCall(gov.execute, (p, _data(7)));
        target.configure(false, address(actor), abi.encodeCall(actor.run, (address(gov), calls)));
        gov.execute(p, _data(7));
        assertTrue(actor.successes(0)); assertTrue(actor.successes(1));
        assertFalse(actor.successes(2)); assertEq(actor.errors(2), Gov.NoMajority.selector);
        assertFalse(actor.successes(3)); assertEq(actor.errors(3), Gov.OwnerOnly.selector);
        assertFalse(actor.successes(4)); assertEq(actor.errors(4), Gov.InactiveProposal.selector);
        assertEq(gov.settledWeight(p), 0);
        assertEq(gov.proposal(q).lockedWeight, 900);
        assertEq(gov.settledWeight(q), 300);
        assertEq(gov.totalEscrowed(), 900);
    }

    function testOwnerCallbackCanWithdrawOnceAndFailedActionRollsEverythingBack() public {
        // The action target itself is a token owner; its callback uses only its own custody rights.
        vm.prank(A); token.transfer(address(target), 600);
        vm.prank(address(target)); token.approve(address(gov), 600);
        uint256 p = _propose(address(target), 600);
        _nextBlock();
        target.configure(false, address(gov), abi.encodeCall(gov.withdraw, ()));
        target.setFailAfterCallback(true);
        vm.expectRevert("failed after callback"); gov.execute(p, _data(7));
        assertFalse(gov.proposal(p).executed);
        assertEq(_positionAmount(address(target)), 600);
        assertEq(gov.totalEscrowed(), 600);
        assertEq(token.balanceOf(address(target)), 0);
        target.setFailAfterCallback(false);
        gov.execute(p, _data(7));
        assertTrue(target.callbackSucceeded());
        assertEq(gov.totalEscrowed(), 0);
        assertEq(gov.settledWeight(p), 0);
        assertEq(token.balanceOf(address(target)), 600);
        vm.prank(address(target)); vm.expectRevert(Gov.NoPosition.selector); gov.withdraw();
        vm.expectRevert(Gov.InactiveProposal.selector); gov.execute(p, _data(7));
    }

    function testThresholdAtMaximumDgveSupplyDoesNotOverflow() public {
        token.mint(A, 1e30 - 1000);
        uint256 threshold = (1e30 / 1000) * 501;
        uint256 p = _propose(A, threshold);
        _nextBlock(); assertFalse(gov.canExecute(p));
        vm.prank(B); gov.support(B, p, 1);
        _nextBlock(); assertTrue(gov.canExecute(p)); gov.execute(p, _data(7));
    }

    function testRecentBucketAcrossAssignmentRemovalAndBlockChanges() public {
        uint256 p = _propose(A, 300);
        vm.prank(B); gov.support(B, p, 300);
        assertEq(gov.settledWeight(p), 0);
        // Passing time without another block does not make atomic support count.
        vm.warp(block.timestamp + 1 hours);
        vm.expectRevert(Gov.NoMajority.selector); gov.execute(p, _data(7));
        _nextBlock(); assertEq(gov.settledWeight(p), 600);
        vm.prank(C); gov.support(C, p, 100);
        assertEq(gov.proposal(p).recentWeight, 100);
        assertEq(gov.settledWeight(p), 600);
        vm.prank(A); gov.clearVote(A); // old position cannot consume the current block's bucket
        assertEq(gov.proposal(p).recentWeight, 100);
        assertEq(gov.settledWeight(p), 300);
        vm.prank(A); gov.support(A, p, 0); // reusing the same action still starts a new assignment
        assertEq(gov.proposal(p).recentWeight, 400);
        assertEq(gov.settledWeight(p), 300);
        vm.prank(C); gov.withdraw(); // current-block removal subtracts both counters
        assertEq(gov.proposal(p).recentWeight, 300);
        assertEq(gov.proposal(p).lockedWeight, 600);
        _nextBlock(); assertEq(gov.settledWeight(p), 600);
        vm.prank(A); gov.clearVote(A); // also clears the stored bucket after it has settled
        assertEq(gov.proposal(p).recentWeight, 0);
        vm.prank(A); gov.clearVote(A); // clearing an already idle position cannot subtract twice
        assertEq(gov.proposal(p).recentWeight, 0);
        assertEq(gov.settledWeight(p), 300);
        vm.prank(B); gov.withdraw();
        assertEq(gov.proposal(p).lockedWeight, 0);
    }

    function testFuzzThreshold(uint256 amount, uint256 burned) public {
        amount = bound(amount, 1, 600); burned = bound(burned, 0, 300);
        uint256 p = _propose(A, amount);
        vm.prank(B); token.burn(burned);
        _nextBlock();
        bool expected = amount * 1000 > (1000 - burned) * 501;
        assertEq(gov.canExecute(p), expected);
        if (expected) gov.execute(p, _data(7));
        else { vm.expectRevert(Gov.NoMajority.selector); gov.execute(p, _data(7)); }
    }
    function testWithdrawalRetainsInactivePositionAndRedepositReplacesDelegate() public {
        vm.roll(10);
        vm.prank(A); gov.deposit(100, B);
        vm.prank(A); gov.withdraw();
        (uint128 amount, uint32 proposalId, uint40 assigned, uint40 deposited, address delegate) = gov.positions(A);
        assertEq(amount, 0); assertEq(proposalId, 0); assertEq(assigned, 0);
        assertEq(deposited, 10); assertEq(delegate, B);
        vm.prank(B); vm.expectRevert(Gov.NoPosition.selector); gov.clearVote(A);
        vm.roll(11);
        vm.prank(A); gov.deposit(50, C);
        (amount, proposalId, assigned, deposited, delegate) = gov.positions(A);
        assertEq(amount, 50); assertEq(proposalId, 0); assertEq(assigned, 0);
        assertEq(deposited, 11); assertEq(delegate, C);
    }

}
