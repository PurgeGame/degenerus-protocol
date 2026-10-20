// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";

/// @dev Etched over the Game to seed a live level-1 purchase phase, move its deadline, and fund
///      or reshape balances. Every measured call runs the production Game runtime.
contract TerminalLoanSeeder is DegenerusGame {
    /// @dev A level-1 purchase phase `age` days old, sealed yesterday (DeadVrfEnding's DeadlineSeeder).
    function livePurchase(uint24 age) external {
        TQ.retireCompleted(address(this), 2);
        uint24 day = _simulatedDayIndex();
        level = 1;
        purchaseStartDay = day - age;
        dailyIdx = day - 1;
        _setLevelPrizePool(1, 10 ether);
        _setPrizePools(9 ether, 0);
        currentPrizePool = 0;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
    }

    /// @dev Push the purchase phase's start back past its 30-day deadline with the level still
    ///      unfunded: the ending fires today. Fixture purchases (smurfs, a deity pass) would
    ///      otherwise have filled the next pool past its target and rescued the level.
    function pastDeadline() external {
        purchaseStartDay = _simulatedDayIndex() - 31;
        _setPrizePools(9 ether, uint128(_getFuturePrizePool()));
    }

    function fund(uint32 id, uint128 amount) external {
        balancesPacked[id] += amount;
        claimablePool += amount;
    }

    function setBalances(uint32 id, uint128 claimable, uint128 afking) external {
        uint256 old = balancesPacked[id];
        uint128 oldBacked = uint128(old) > 1 ? uint128(old) - 1 : 0;
        uint128 newBacked = claimable > 1 ? claimable - 1 : 0;
        claimablePool = claimablePool - oldBacked - uint128(old >> 128) + newBacked + afking;
        balancesPacked[id] = (uint256(afking) << 128) | claimable;
    }

    function seedLevel(uint32 id, uint24 lvl, uint32 entries) external {
        _queueEntries(id, lvl, entries, false);
    }
}

/// @notice Shared fixture: borrowers, the expected settlement of each loan, and a driver that runs
///         the real engine through the ending while checking that no terminal request, payout or
///         gameOver happens while any loan is still open.
abstract contract TerminalLoanBase is DeployProtocol {
    bytes32 internal constant LOAN_SEIZED_SIG = keccak256("LoanSeized(uint32,uint32)");
    bytes32 internal constant LOAN_REPAID_SIG = keccak256("LoanRepaid(uint32,address,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");
    uint8 internal constant ACTION_TERMINAL = 1;
    uint8 internal constant STAGE_TERMINAL_LOANS = 20;
    uint32 internal constant SDGNRS_ID = 2;
    uint256 internal constant GO_LOAN_STEP_SHIFT = 64;
    uint256 internal constant GO_LOAN_INDEX_SHIFT = 72;

    bytes internal gameRuntime;
    DegenerusGameLens internal lens;

    uint32[] internal tracked;
    uint256 internal requestAtDecision;

    function _seeder() internal returns (TerminalLoanSeeder s) {
        vm.etch(address(game), type(TerminalLoanSeeder).runtimeCode);
        s = TerminalLoanSeeder(payable(address(game)));
    }

    function _restore() internal {
        vm.etch(address(game), gameRuntime);
    }

    function _fund(uint32 id, uint128 amount) internal { _seeder().fund(id, amount); _restore(); }

    function _setBalances(uint32 id, uint256 claimable, uint256 afking) internal {
        _seeder().setBalances(id, uint128(claimable), uint128(afking));
        _restore();
    }

    function _seedLevel(uint32 id, uint24 lvl, uint32 entries) internal {
        _seeder().seedLevel(id, lvl, entries);
        _restore();
    }

    function _payee(uint32 id) internal view returns (address payee) {
        (, payee, ) = game.resolveAccount(id, address(0));
    }

    function _open(uint32 id) internal view returns (bool) {
        return lens.loanOf(address(game), id).principal != 0;
    }

    function _anyOpen() internal view returns (bool) {
        for (uint256 i; i < tracked.length; ++i) if (_open(tracked[i])) return true;
        return false;
    }

    function _borrow(address who, uint32 id, uint24 due) internal returns (uint256 principal) {
        DegenerusGameLens.LoanQuote memory q = lens.previewBorrow(address(game), id, due, type(uint256).max);
        assertTrue(q.eligible, "borrow eligible");
        principal = q.principal;
        vm.prank(who);
        game.borrow(id, due, type(uint256).max, principal - q.ticketWei);
        tracked.push(id);
    }

    /// @dev What repaying costs at the current level, computed independently from the loan's
    ///      record: 5% per level used (at least one) plus 1% per unused level. Game-over
    ///      settlement charges exactly this; at the due level it is the full term.
    function _owedNow(uint32 id) internal view returns (uint256) {
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
        uint256 lvl = game.level();
        uint256 used = lvl > info.startLevel ? lvl - info.startLevel : 1;
        return info.principal * (10_000 + used * 500 + (uint256(info.dueLevel) - info.startLevel - used) * 100)
            / 10_000;
    }

    function _fullTerm(uint32 id) internal view returns (uint256) {
        DegenerusGameLens.LoanInfo memory info = lens.loanOf(address(game), id);
        return info.principal * (10_000 + (uint256(info.dueLevel) - info.startLevel) * 500) / 10_000;
    }

    /// @dev The amount the account's `LoanRepaid` event recorded (zero if none).
    function _repaidOwed(Vm.Log[] memory logs, uint32 id) internal view returns (uint256 owed) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (logs[i].topics[0] == LOAN_REPAID_SIG && uint32(uint256(logs[i].topics[1])) == id) {
                owed = abi.decode(logs[i].data, (uint256));
            }
        }
    }

    function _goWord() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(GameSlots.GAME_OVER_STATE_PACKED))));
    }

    function _loanStep() internal view returns (uint256) { return uint8(_goWord() >> GO_LOAN_STEP_SHIFT); }
    function _loanIndex() internal view returns (uint256) { return uint32(_goWord() >> GO_LOAN_INDEX_SHIFT); }
    function _jackpotPaid() internal view returns (bool) { return uint8(_goWord() >> 48) != 0; }
    function _swept() internal view returns (bool) { return uint8(_goWord() >> 56) != 0; }

    function _fulfillLatest() internal {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(id);
        if (!fulfilled) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("terminal-loan", id))));
    }

    /// @dev One engine call at `gasCap`. Waiting on a word is not a failure; anything else is.
    function _mine(uint256 gasCap) internal returns (bool ran) {
        (bool ok, bytes memory reason) =
            address(game).call{gas: gasCap}(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
        if (ok) return true;
        if (reason.length == 4 && (bytes4(reason) == bytes4(keccak256("RngNotReady()"))
            || bytes4(reason) == bytes4(keccak256("NoWork()")))) return false;
        assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    /// @dev While any tracked loan is open: no terminal request after the decision, no gameOver.
    function _assertNothingAheadOfLoans() internal view {
        if (!_anyOpen()) return;
        assertEq(mockVRF.lastRequestId(), requestAtDecision, "no terminal request while a loan is open");
        assertFalse(game.gameOver(), "no gameOver while a loan is open");
        assertFalse(_jackpotPaid(), "no payout while a loan is open");
    }

    /// @dev Drive the ending to the paid terminal jackpot. `answer` fulfils requests as they appear.
    function _driveEnding(uint256 gasCap, bool answer, uint256 maxCalls) internal returns (uint256 calls) {
        for (; calls < maxCalls; ++calls) {
            if (game.gameOver() && _jackpotPaid()) return calls;
            if (answer && !_anyOpen()) _fulfillLatest();
            _mine(gasCap);
            _assertNothingAheadOfLoans();
        }
        fail("ending did not finish");
    }

    /// @dev Settlement events, in log order, must all precede the first terminal Advance after the
    ///      loan stage (any stage other than 20 once stage 20 has completed).
    function _countSettlements(Vm.Log[] memory logs, uint32 id)
        internal
        view
        returns (uint256 seized, uint256 repaid)
    {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2) continue;
            if (uint32(uint256(logs[i].topics[1])) != id) continue;
            if (logs[i].topics[0] == LOAN_SEIZED_SIG) ++seized;
            else if (logs[i].topics[0] == LOAN_REPAID_SIG) ++repaid;
        }
    }

    function _assertSeized(Vm.Log[] memory logs, uint32 id, string memory label) internal view {
        (uint256 seized, uint256 repaid) = _countSettlements(logs, id);
        assertEq(seized, 1, label);
        assertEq(repaid, 0, label);
        assertEq(_payee(id), address(sdgnrs), label);
        assertEq(game.acquiredBuyer(id), SDGNRS_ID, label);
        assertFalse(_open(id), label);
    }

    function _assertRepaid(Vm.Log[] memory logs, uint32 id, address borrower, uint256 owed, string memory label)
        internal
        view
    {
        (uint256 seized, uint256 repaid) = _countSettlements(logs, id);
        assertEq(seized, 0, label);
        assertEq(repaid, 1, label);
        assertEq(_repaidOwed(logs, id), owed, label);
        assertEq(_payee(id), borrower, label);
        assertEq(game.acquiredBuyer(id), 0, label);
        assertFalse(_open(id), label);
    }
}

/// @notice An insufficient-pool (purchase-deadline) ending decided with VRF alive settles every
///         outstanding loan before the terminal request, repaying at what a manual repayment would
///         cost then or else seizing; a VRF already dead at the decision leaves every loan as it
///         stands.
///         Pins for the advance-call manifest on the game-over path: IsDGNRS.burnForLiquidation
///         (a main's seizure burns its wallet's native sDGNRS) and IDeityPassSeize.seize (the pass
///         follows its account).
contract TerminalLoanSettlementTest is TerminalLoanBase {
    address private alice = makeAddr("terminal-loan-alice");
    address private bob = makeAddr("terminal-loan-bob");
    address private carol = makeAddr("terminal-loan-carol");
    address private dave = makeAddr("terminal-loan-dave");
    address private erin = makeAddr("terminal-loan-erin");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 500 days);
        vm.deal(address(game), 100_000 ether);
        gameRuntime = address(game).code;
        lens = new DegenerusGameLens();
        _seeder().livePurchase(5);
        _restore();
        _fund(SDGNRS_ID, 5_000 ether);
    }

    function _account(address who) private returns (uint32 id) {
        vm.deal(who, 1_000 ether);
        id = _giveWalletId(who);
        _seedLevel(id, 60, 4_000);
        _seedLevel(id, 102, 4_000);
    }

    function _child(address owner) private returns (uint32 id) {
        uint256 price = game.mintPrice();
        vm.prank(owner);
        id = game.createSmurf{value: price}(0, MintPaymentKind.DirectEth);
        _seedLevel(id, 60, 4_000);
    }

    function _decide() private {
        _seeder().pastDeadline();
        _restore();
        assertTrue(game.livenessTriggered(), "the deadline ending fires");
        assertEq(game.nextMinerAction(), ACTION_TERMINAL);
        requestAtDecision = mockVRF.lastRequestId();
    }

    // ---------------------------------------------------------------- full book

    function test_DeadlineEndingSettlesEveryLoanBeforeTheTerminalRequest() public {
        // alice: due 10, covered by claimable plus AFKing at the current repayment price, which
        // is below her full term: game over charges what repaying would cost now.
        uint32 a = _account(alice);
        _borrow(alice, a, 10);
        uint256 owedA = _owedNow(a);
        assertEq(owedA, lens.loanOf(address(game), a).owed, "the price is the manual repayment quote");
        assertLt(owedA, _fullTerm(a), "and below the full term");
        _setBalances(a, owedA / 3 + 1, owedA - owedA / 3);
        // bob: one wei short of the current price at due 3 (holding sDGNRS); defaults intact.
        uint32 b = _account(bob);
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, bob, 1e15);
        _borrow(bob, b, 3);
        uint256 owedB = _owedNow(b);
        _setBalances(b, owedB, 0);
        // carol: a main with five smurfs, one holding a deity pass, defaults at due 30.
        uint32 c = _account(carol);
        _grantSmurfBase(carol, 8);
        uint32[] memory kids = new uint32[](5);
        for (uint256 i; i < 5; ++i) kids[i] = _child(carol);
        vm.prank(carol);
        game.purchaseDeityPass{value: 200 ether}(kids[4], 31, bytes32(0));
        _borrow(carol, c, 30);
        _setBalances(c, 0, 0);
        // dave: a main due 4 whose smurf carries its own loan due 50; the main goes first.
        uint32 d = _account(dave);
        _grantSmurfBase(dave, 8);
        uint32 dKid = _child(dave);
        _borrow(dave, dKid, 50);
        _setBalances(dKid, 1, 1_000 ether); // ample, but an acquired borrower always defaults
        _borrow(dave, d, 4);
        _setBalances(d, 0, 0);
        // erin: the last level a loan can be due (level + 99).
        uint32 e = _account(erin);
        _borrow(erin, e, 100);
        _setBalances(e, 0, 0);

        (uint128 lenderBefore, ) = lens.accountBalances(address(game), SDGNRS_ID);
        uint256 poolBefore = game.claimablePoolView();
        assertEq(sdgnrs.balanceOf(bob), 1e15, "bob holds native sDGNRS going in");
        _decide();

        vm.recordLogs();
        // The first call only latches the ending and its loan policy.
        assertTrue(_mine(30_000_000));
        assertEq(_loanStep(), 1, "VRF alive: settlement owed");
        assertTrue(_anyOpen(), "the deciding call settles nothing");
        assertEq(game.nextMinerAction(), ACTION_TERMINAL, "the loan stage comes next");
        // One call then settles the whole book.
        assertTrue(_mine(30_000_000));
        assertFalse(_anyOpen(), "every loan settled");
        assertEq(_loanStep(), 0, "settlement complete");
        assertEq(mockVRF.lastRequestId(), requestAtDecision, "the request waits for its own call");
        assertEq(game.claimablePoolView(), poolBefore, "settlement moves claimable between accounts only");
        (uint128 claimA, uint128 afkA) = lens.accountBalances(address(game), a);
        assertEq(claimA, 1, "alice's claimable leg spent down to its sentinel");
        assertEq(afkA, 0, "then her AFKing leg");
        (uint128 lenderAfter, ) = lens.accountBalances(address(game), SDGNRS_ID);
        assertEq(lenderAfter - lenderBefore, owedA, "exactly alice's current price reached the lender");
        (uint128 claimB, ) = lens.accountBalances(address(game), b);
        assertEq(claimB, owedB, "bob defaults with his balance intact");

        _driveEnding(30_000_000, true, 200);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertRequestFollowsSettlement(logs);

        _assertRepaid(logs, a, alice, owedA, "alice repays at the current price");
        _assertSeized(logs, b, "bob defaults one wei short");
        assertEq(sdgnrs.balanceOf(bob), 0, "bob's native sDGNRS burned");
        assertEq(game.walletIdOf(bob), 0, "bob's default gameplay ID cleared");
        _assertSeized(logs, c, "carol's main defaults");
        for (uint256 i; i < 5; ++i) assertEq(_payee(kids[i]), address(sdgnrs), "carol's family moves with her");
        assertEq(deityPass.ownerOf(31), address(sdgnrs), "the deity pass follows its account");
        _assertSeized(logs, d, "dave's main defaults");
        _assertSeized(logs, dKid, "dave's smurf defaults to its own lender at its own due level");
        _assertSeized(logs, e, "the horizon loan settles");

        // The 30-day final sweep remains reachable after settlement.
        vm.warp(block.timestamp + 31 days);
        _mineAll(5);
        assertTrue(_swept(), "final sweep ran");
    }

    /// @dev Every settlement event precedes the first terminal Advance after the loan stage.
    function _assertRequestFollowsSettlement(Vm.Log[] memory logs) private pure {
        uint256 lastSettlement;
        uint256 firstLaterStage = type(uint256).max;
        bool loanStageSeen;
        for (uint256 i; i < logs.length; ++i) {
            if (_isSettlement(logs[i])) lastSettlement = i;
            uint256 stage = _stageOf(logs[i]);
            if (stage == STAGE_TERMINAL_LOANS) loanStageSeen = true;
            else if (stage != type(uint256).max && loanStageSeen && i < firstLaterStage) firstLaterStage = i;
        }
        assertTrue(loanStageSeen, "the loan stage ran");
        assertLt(lastSettlement, firstLaterStage, "settlement finished before the ending moved on");
    }

    function _isSettlement(Vm.Log memory log) private pure returns (bool) {
        return log.topics.length != 0 && (log.topics[0] == LOAN_SEIZED_SIG || log.topics[0] == LOAN_REPAID_SIG);
    }

    /// @dev The Advance stage of `log`, or max for any other event.
    function _stageOf(Vm.Log memory log) private pure returns (uint256) {
        if (log.topics.length == 0 || log.topics[0] != ADVANCE_SIG) return type(uint256).max;
        (uint8 stage, ) = abi.decode(log.data, (uint8, uint24));
        return stage;
    }

    // ---------------------------------------------------------------- chunks and manual repayment

    function test_ChunkedSettlementResumesAroundManualRepayment() public {
        uint256 n = 24;
        address[] memory owners = new address[](n);
        uint32[] memory ids = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            owners[i] = makeAddr(string(abi.encode("chunk-borrower", i)));
            ids[i] = _account(owners[i]);
            _borrow(owners[i], ids[i], i < 16 ? 5 : 7);
            _setBalances(ids[i], 0, 0);
        }
        _decide();
        vm.recordLogs();
        assertTrue(_mine(30_000_000)); // decision only

        // 800k calls admit only a few loans after the engine's reserves; the rest resume
        // from the stored index. The first call may only walk the empty levels ahead of 5.
        assertTrue(_mine(800_000));
        for (uint256 k; k < 4 && _loanIndex() == 0; ++k) assertTrue(_mine(800_000));
        uint256 step = _loanStep();
        uint256 index = _loanIndex();
        assertEq(step, 4, "still on level 5");
        assertGt(index, 0, "some of level 5 settled");
        assertLt(index, 16, "not all of it");
        // A borrower beyond the cursor repays manually at the early price: the last entry moves
        // into its lane, still at or after the cursor.
        uint32 mid = ids[index + 1];
        uint256 early = lens.loanOf(address(game), mid).owed;
        assertEq(early, _owedNow(mid), "manual repayment costs what settlement would charge");
        vm.deal(owners[index + 1], early);
        vm.prank(owners[index + 1]);
        game.repay{value: early}(mid);
        // And the last entry of level 7 repays too.
        uint32 last = ids[n - 1];
        uint256 lastOwed = lens.loanOf(address(game), last).owed;
        vm.deal(owners[n - 1], lastOwed);
        vm.prank(owners[n - 1]);
        game.repay{value: lastOwed}(last);

        for (uint256 calls; calls < 100 && _anyOpen(); ++calls) {
            _mine(800_000);
            _assertNothingAheadOfLoans();
        }
        assertFalse(_anyOpen(), "every loan settled");
        _driveEnding(30_000_000, true, 200);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < n; ++i) {
            if (ids[i] == mid || ids[i] == last) {
                _assertRepaid(logs, ids[i], owners[i], ids[i] == mid ? early : lastOwed,
                    "manual repayment closes the loan once");
            } else {
                _assertSeized(logs, ids[i], "each remaining loan seized exactly once");
            }
        }
    }

    // ---------------------------------------------------------------- dead VRF at the decision

    function test_DeadVrfAtTheDecisionLeavesLoansUntouched() public {
        uint32 a = _account(alice);
        uint256 principal = _borrow(alice, a, 3);
        _setBalances(a, 0, 0);
        // A daily request goes out and is never answered.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) _mine(30_000_000);
        assertTrue(game.rngLocked(), "the day's request is out");
        vm.warp(block.timestamp + 15 days);
        assertTrue(game.livenessTriggered(), "VRF dead");
        vm.recordLogs();
        for (uint256 i; i < 200 && !(game.gameOver() && _jackpotPaid()); ++i) _mine(30_000_000);
        assertTrue(game.gameOver(), "the deterministic ending finished");
        assertEq(_loanStep(), 0, "no settlement owed");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 seized, uint256 repaid) = _countSettlements(logs, a);
        assertEq(seized + repaid, 0, "loans stand");
        assertEq(_payee(a), alice, "the borrower keeps the account");
        assertEq(lens.loanOf(address(game), a).principal, principal, "the loan record stands");
    }

    // ---------------------------------------------------------------- VRF failing after the decision

    function test_OlderRequestDyingDuringSettlementNeitherSkipsNorReversesIt() public {
        uint256 n = 12;
        uint32[] memory ids = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            address owner = makeAddr(string(abi.encode("late-death", i)));
            ids[i] = _account(owner);
            _borrow(owner, ids[i], 6);
            _setBalances(ids[i], 0, 0);
        }
        // The day's request is in flight and young when the deadline ending is decided.
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) _mine(30_000_000);
        assertTrue(game.rngLocked(), "the day's request is out");
        _decide();
        vm.recordLogs();
        assertTrue(_mine(30_000_000)); // decision: VRF alive, settlement owed
        assertEq(_loanStep(), 1);
        assertTrue(_mine(800_000)); // part of the book
        assertTrue(_anyOpen(), "the book is still part-settled");
        assertEq(game.nextMinerAction(), ACTION_TERMINAL, "settlement outranks the wait for the old word");

        // The older request now times out. Settlement still finishes every remaining loan.
        vm.warp(block.timestamp + 15 days);
        for (uint256 calls; calls < 100 && _anyOpen(); ++calls) {
            _mine(800_000);
            _assertNothingAheadOfLoans();
        }
        assertFalse(_anyOpen(), "no loan skipped after the timeout");
        for (uint256 i; i < 200 && !(game.gameOver() && _jackpotPaid()); ++i) _mine(30_000_000);
        assertTrue(game.gameOver() && _jackpotPaid(), "the deterministic fallback finished");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < n; ++i) _assertSeized(logs, ids[i], "settled once; ownership stands after the fallback");
    }

    function test_OlderWordLandingDuringSettlementChangesNothing() public {
        uint32 a = _account(alice);
        _borrow(alice, a, 2);
        _setBalances(a, 0, 0);
        uint32 b = _account(bob);
        _borrow(bob, b, 9);
        _setBalances(b, 0, 0);
        for (uint256 i; i < 256 && !game.rngLocked(); ++i) _mine(30_000_000);
        assertTrue(game.rngLocked(), "the day's request is out");
        _decide();
        assertTrue(_mine(30_000_000)); // decision
        _fulfillLatest(); // the older request's word lands mid-settlement
        assertEq(game.nextMinerAction(), ACTION_TERMINAL);
        _driveEnding(30_000_000, true, 200);
        assertEq(_payee(a), address(sdgnrs));
        assertEq(_payee(b), address(sdgnrs));
    }

    // ---------------------------------------------------------------- empty book

    function test_EmptyBookScansInOneCallThenTheEndingProceeds() public {
        _decide();
        assertTrue(_mine(30_000_000)); // decision
        assertEq(_loanStep(), 1);
        vm.recordLogs();
        assertTrue(_mine(30_000_000));
        assertEq(_loanStep(), 0, "the empty scan completes in one call");
        assertEq(mockVRF.lastRequestId(), requestAtDecision, "the request has its own call");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 stages;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == ADVANCE_SIG) ++stages;
        }
        assertEq(stages, 1, "one loan-stage checkpoint");
        _driveEnding(30_000_000, true, 200);
    }

    // ---------------------------------------------------------------- independent ledger

    /// forge-config: default.fuzz.runs = 24
    function testFuzz_RandomBookSettlesOnceAtTheRepaymentPrice(uint256 seed) public {
        uint256 n = 6;
        uint32[] memory ids = new uint32[](n);
        address[] memory owners = new address[](n);
        bool[] memory covers = new bool[](n);
        uint256[] memory owedAt = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            owners[i] = makeAddr(string(abi.encode("fuzz-borrower", i)));
            ids[i] = _account(owners[i]);
            uint24 due = uint24(2 + r % 99); // 2..100: collateral at 102 serves every due level
            _borrow(owners[i], ids[i], due);
            uint256 owed = _owedNow(ids[i]);
            owedAt[i] = owed;
            covers[i] = (r >> 32) & 1 == 1;
            // Covered: exactly enough across both legs; otherwise one wei short.
            uint256 split = (r >> 40) % (owed + 1);
            uint256 total = covers[i] ? owed : owed - 1;
            if (split > total) split = total;
            _setBalances(ids[i], split + 1, total - split);
        }
        _decide();
        vm.recordLogs();
        uint256 gasCap = 800_000 + (seed % 2_000_000);
        for (uint256 calls; calls < 200 && _anyOpen(); ++calls) {
            _mine(calls == 0 ? 30_000_000 : gasCap);
            _assertNothingAheadOfLoans();
        }
        assertFalse(_anyOpen(), "every loan settled");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < n; ++i) {
            if (covers[i]) _assertRepaid(logs, ids[i], owners[i], owedAt[i], "covered: repaid at the current price");
            else _assertSeized(logs, ids[i], "one wei short: seizure");
        }
        _driveEnding(30_000_000, true, 200);
    }
}

/// @notice A deadman ending can land while the level just entered still has loans pending: the
///         ending finishes that batch from its cursor, then every later due level.
contract TerminalLoanPendingBatchTest is TerminalLoanBase {
    uint256 private constant POOL_HALF_MASK = (uint256(1) << 128) - 1;
    address private buyer;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        buyer = makeAddr("pending-ticket-buyer");
        vm.deal(buyer, 50_000 ether);
        vm.deal(address(game), 100_000 ether);
        gameRuntime = address(game).code;
        lens = new DegenerusGameLens();
        _fund(SDGNRS_ID, 5_000 ether);
    }

    function _seedNextPrizePool(uint256 targetNext) private {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(GameSlots.PRIZE_POOLS_PACKED))));
        if ((packed & POOL_HALF_MASK) >= targetNext) return;
        vm.store(address(game), bytes32(uint256(GameSlots.PRIZE_POOLS_PACKED)),
            bytes32((packed & ~POOL_HALF_MASK) | targetNext));
    }

    function _buyTickets(uint256 qty) private {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        vm.prank(buyer);
        try game.purchase{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    /// @dev Drive the real engine until the request that enters `target` has run; the word stays out.
    function _driveToTransition(uint24 target) private {
        uint256 simTime = block.timestamp;
        for (uint256 day; day < 60; ++day) {
            simTime += 1 days + 1;
            vm.warp(simTime);
            _seedNextPrizePool(500 ether);
            _buyTickets(4000);
            for (uint256 j; j < 80; ++j) {
                if (game.level() >= target) return;
                _fulfillLatest();
                if (game.level() >= target) return;
                (bool ok,) = address(game).call(abi.encodeWithSignature("mineFlip(uint32)", uint32(0)));
                if (game.level() >= target) return;
                if (!ok) break;
            }
        }
        fail("transition not reached");
    }

    function test_DeadmanFinishesThePendingBatchFromItsCursorThenLaterLevels() public {
        uint256 n = 30;
        uint32[] memory ids = new uint32[](n);
        for (uint256 i; i < n; ++i) {
            address owner = makeAddr(string(abi.encode("pending-borrower", i)));
            vm.deal(owner, 10 ether);
            ids[i] = _giveWalletId(owner);
            _seedLevel(ids[i], 8, 400);
            _seedLevel(ids[i], 60, 400);
            _borrow(owner, ids[i], i < 20 ? 1 : (i < 25 ? 2 : 40));
        }
        _driveToTransition(1);
        _fulfillLatest(); // the transition's word lands: VRF is alive
        vm.recordLogs();
        game.mineFlip{gas: 800_000}(0); // the ordinary stage settles part of level 1's batch
        uint256 cursorAfterOrdinary = uint32(uint256(vm.load(address(game), bytes32(uint256(GameSlots.LOAN_SEIZE_CURSOR))))
            >> (GameSlots.LOAN_SEIZE_CURSOR_OFFSET * 8));
        assertGt(cursorAfterOrdinary, 0, "part of the batch settled");
        assertLt(cursorAfterOrdinary, 20, "and part is still pending");

        // Nobody mines for the deadman's 30 days; the delivered word means VRF is alive.
        vm.warp(block.timestamp + 31 days);
        assertTrue(game.livenessTriggered(), "deadman");
        assertEq(game.nextMinerAction(), ACTION_TERMINAL);
        requestAtDecision = mockVRF.lastRequestId();
        assertTrue(_mine(30_000_000)); // decision
        assertEq(_loanStep(), 1, "settlement owed");
        uint256 settleCalls;
        for (; settleCalls < 100 && _anyOpen(); ++settleCalls) {
            _mine(800_000);
            _assertNothingAheadOfLoans();
        }
        assertGt(settleCalls, 1, "the book spans several checkpoints");
        assertFalse(_anyOpen(), "pending batch and later levels all settled");
        _driveEnding(30_000_000, true, 300);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < n; ++i) {
            (uint256 seized, uint256 repaid) = _countSettlements(logs, ids[i]);
            assertEq(seized + repaid, 1, "each loan settled exactly once across both stages");
            assertEq(_payee(ids[i]), address(sdgnrs));
        }
    }
}
