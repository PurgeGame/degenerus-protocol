// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ChainCallJudge, ChainProgress, ChainStallProbe} from "./helpers/ChainCallJudge.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {FSMHandler} from "./handlers/FSMHandler.sol";
import {Vm} from "forge-std/Vm.sol";
import {MineFlipAdmission} from "./helpers/MineFlipAdmission.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";

/// @dev Stand-in engine that always has work and commits state on every call, but never finishes:
///      each mineRun bumps a counter while the selection stays on maintenance.
contract EndlessWorkGame {
    uint256 public bumps;

    function mineRun(uint32) external {
        ++bumps;
    }

    function minerAction() external pure returns (uint256) {
        return MineFlipAdmission.MAINTENANCE;
    }

    function advanceDue() external pure returns (bool) {
        return true;
    }
}

/// @dev Exposes the judge's call path to the self-test.
contract ChainCallJudgeProbe is ChainCallJudge {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function mine(address game, uint256 gasLimit, uint8 allowed, uint16 site) external returns (bool ok, bytes4 sel) {
        return _mine(game, gasLimit, allowed, site);
    }

    /// @dev A handler-style call: a one-shot prank, then the judged mine.
    function minePranked(address game, address who) external returns (bool ok, bytes4 sel) {
        VM.prank(who);
        return _mine(game, 0, 3, 1);
    }

    /// @dev The same with the gas capped by the handler (the call is the prank's first use).
    function minePrankedCapped(address game, address who, uint256 gasLimit) external returns (bool ok, bytes4 sel) {
        VM.prank(who);
        return _mine(game, gasLimit, 7, 1);
    }
}

/// @dev Stand-in Game: every call runs the production code in the Game's own storage, but `mineRun`
///      first logs its caller and the gas it received, and reverts with no data unless it received
///      at least `need` (work that only fits with that much gas).
contract SpyGame {
    event MineSeen(address caller, uint256 gasIn);

    address internal immutable production;
    uint256 internal immutable need;

    constructor(address production_, uint256 need_) {
        production = production_;
        need = need_;
    }

    fallback() external payable {
        if (msg.sig == bytes4(keccak256("mineRun(uint32)"))) {
            uint256 left = gasleft();
            emit MineSeen(msg.sender, left);
            if (left < need) revert();
        }
        (bool ok, bytes memory ret) = production.delegatecall(msg.data);
        assembly ("memory-safe") {
            if iszero(ok) { revert(add(ret, 32), mload(ret)) }
            return(add(ret, 32), mload(ret))
        }
    }
}

contract MappingWriter {
    mapping(uint256 => uint256) public m;

    function set(uint256 k) external {
        m[k] = 1;
    }
}

/// @dev External wrapper so a stall-probe failure can be caught with expectRevert.
contract ChainStallProbeHarness {
    function check(address game, MockVRFCoordinator vrf) external {
        ChainStallProbe.check("selftest", game, vrf);
    }
}

/// @title ChainCallJudgeTest -- the chain-call judge flags an unexpected mineRun revert (falsifiability)
/// @notice Every swallowed `game.mineRun` in the stateful-fuzz handlers goes through ChainCallJudge, and each
///         suite asserts `judgeCheck`. These tests prove the judge is not vacuous: a mocked chain brick with an
///         unexpected selector is recorded and `judgeCheck` reverts, through a real handler and directly; engine
///         refusals that are legitimate for a call site stay allowed, and are not allowed where they would hide
///         a no-progress state.
contract ChainCallJudgeTest is DeployProtocol {
    uint8 internal constant IDLE_WAIT = 3;
    uint8 internal constant ALL = 7;
    FSMHandler internal handler;
    ChainCallJudgeProbe internal probe;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        handler = new FSMHandler(game, mockVRF, 10);
        probe = new ChainCallJudgeProbe();
    }

    function _mockMineRun(bytes memory reason) internal {
        vm.mockCallRevert(address(game), abi.encodeWithSelector(game.mineRun.selector), reason);
    }

    function test_unexpectedCustomErrorIsFlaggedThroughAHandler() public {
        _mockMineRun(abi.encodeWithSignature("Boom(uint256)", 7));
        handler.mineFlip(1);
        assertEq(handler.judgeCalls(), 1);
        assertEq(handler.judgeUnexpected(), 1);
        assertEq(handler.judgeFirstSel(), bytes4(keccak256("Boom(uint256)")));
        assertEq(handler.judgeFirstSite(), 2, "FSMHandler.mineFlip is site 2");
        vm.expectRevert();
        handler.judgeCheck("selftest");
    }

    function test_panicAndErrorStringAreFlagged() public {
        _mockMineRun(abi.encodeWithSignature("Panic(uint256)", 0x11));
        handler.mineFlip(1);
        assertEq(handler.judgeUnexpected(), 1);
        assertEq(handler.judgeFirstSel(), bytes4(0x4e487b71));
        _mockMineRun(abi.encodeWithSignature("Error(string)", "nope"));
        handler.mineFlip(2);
        assertEq(handler.judgeUnexpected(), 2);
    }

    function _mockSelection(uint8 action) internal {
        vm.mockCall(address(game), abi.encodeWithSignature("minerAction()"), abi.encode(uint256(action)));
    }

    function test_idleAndWaitAreAllowedAtADefaultGasSite() public {
        _mockSelection(MineFlipAdmission.IDLE);
        _mockMineRun(abi.encodeWithSignature("NoWork()"));
        handler.mineFlip(1);
        _mockSelection(MineFlipAdmission.WAIT);
        _mockMineRun(abi.encodeWithSignature("RngNotReady()"));
        handler.mineFlip(1);
        assertEq(handler.judgeCalls(), 2);
        assertEq(handler.judgeUnexpected(), 0);
        handler.judgeCheck("selftest");
        assertEq(handler.judgeSeenCount(), 2);
    }

    function test_gasRefusalIsABrickWhereGasIsAmple() public {
        _mockMineRun(abi.encodeWithSignature("InsufficientExecutionGas()"));
        handler.mineFlip(1);
        assertEq(handler.judgeUnexpected(), 1, "no-progress at ample gas is not a legitimate refusal");
        _mockMineRun(bytes(""));
        handler.mineFlip(1);
        assertEq(handler.judgeUnexpected(), 2, "an empty revert at ample gas is not legitimate");
    }

    function test_gasRefusalIsAllowedWhereGasIsDeliberatelyCapped() public {
        _mockMineRun(abi.encodeWithSignature("InsufficientExecutionGas()"));
        probe.mine(address(game), 700_000, ALL, 9);
        _mockMineRun(abi.encodeWithSignature("WorkGasBound()"));
        probe.mine(address(game), 700_000, ALL, 9);
        _mockMineRun(bytes(""));
        probe.mine(address(game), 700_000, ALL, 9);
        assertEq(probe.judgeUnexpected(), 0);
        // The same refusals still fail a site that allows only idle and wait.
        probe.mine(address(game), 700_000, IDLE_WAIT, 10);
        assertEq(probe.judgeUnexpected(), 1);
        assertEq(probe.judgeFirstSite(), 10);
        assertEq(probe.judgeFirstGas(), 700_000);
    }

    bytes4 internal constant NO_PROGRESS = bytes4(keccak256("JudgeNoProgress()"));

    /// @dev A success that commits nothing is a crank that would repeat forever: flagged with work
    ///      selected, with a request selected but nothing refused, and at a capped site (judged by the
    ///      selection read after the call). No ample call repeats it.
    function test_successWithoutProgressIsFlagged() public {
        _mockSelection(MineFlipAdmission.TICKETS);
        vm.mockCall(address(game), abi.encodeWithSelector(game.mineRun.selector), bytes(""));
        (bool ok, bytes4 sel) = probe.mine(address(game), 0, IDLE_WAIT, 1);
        assertTrue(ok);
        assertEq(sel, NO_PROGRESS);
        assertEq(probe.judgeUnexpected(), 1);
        assertEq(probe.judgeFirstSel(), NO_PROGRESS);
        assertEq(probe.judgeFirstAction(), MineFlipAdmission.TICKETS);
        assertEq(probe.judgeSucceeded(), 1, "no ample call repeats a call that committed nothing");
        _mockSelection(MineFlipAdmission.REQUEST_DAILY);
        probe.mine(address(game), 0, IDLE_WAIT, 2);
        assertEq(probe.judgeUnexpected(), 2, "a request that refused nothing is not a refusal");
        probe.mine(address(game), 700_000, ALL, 3);
        assertEq(probe.judgeUnexpected(), 3, "a capped site's success must commit work too");
        assertEq(probe.judgeProgressed(), 0);
        vm.expectRevert();
        probe.judgeCheck("selftest");
    }

    /// @dev The real engine's work is counted as progress, and a refused daily request (the
    ///      coordinator rejects it, so the engine waits on its dependency) is the one success
    ///      that may commit nothing.
    function test_realWorkProgressesAndARefusedRequestIsAllowed() public {
        probe.mine(address(game), 0, IDLE_WAIT, 1);
        assertGt(probe.judgeProgressed(), 0, "real work commits state");
        assertEq(probe.judgeUnexpected(), 0);
        _driveToIdle();
        vm.warp(block.timestamp + 1 days);
        _refuseRequests();
        for (uint256 i; i < 100 && probe.judgeRefusals() == 0; ++i) probe.mine(address(game), 0, IDLE_WAIT, 4);
        assertGt(probe.judgeRefusals(), 0, "the refusal was recognised");
        assertEq(probe.judgeUnexpected(), 0);
        assertFalse(game.rngLocked(), "the refused request committed nothing");
        assertEq(game.nextMinerAction(), MineFlipAdmission.REQUEST_DAILY, "the request stays selected");
    }

    // ----- admission: the selected action's first-unit gas, inside the Osaka transaction cap -----

    function test_drawStaysBetweenTheMinimumAndTheCap(uint256 minimum, uint256 seed) public view {
        minimum = bound(minimum, 0, 40_000_000);
        uint256 g = probe.drawAdmissionGas(minimum, seed);
        if (minimum >= probe.TX_GAS_CAP()) {
            assertEq(g, probe.TX_GAS_CAP(), "a minimum above the cap is drawn at the cap");
        } else {
            assertGe(g, minimum);
            assertLe(g, probe.TX_GAS_CAP());
        }
    }

    function test_capIsOsakaLessIntrinsicAndHumanBoxesSitsAboveIt() public view {
        assertEq(probe.TX_GAS_CAP(), 16_756_216);
        assertGt(MineFlipAdmission.minGas(MineFlipAdmission.HUMAN_BOXES, false), probe.TX_GAS_CAP());
    }

    function test_successWhileSelectionIsIdleIsFlagged() public {
        _mockSelection(MineFlipAdmission.IDLE);
        vm.mockCall(address(game), abi.encodeWithSelector(game.mineRun.selector), bytes(""));
        probe.mine(address(game), 0, IDLE_WAIT, 4);
        assertEq(probe.judgeUnexpected(), 1, "work done while discovery reported none");
        assertEq(probe.judgeFirstAction(), MineFlipAdmission.IDLE);
    }

    function test_refusalOfSelectedWorkIsFlaggedEvenWhereTheSiteAllowsIt() public {
        _mockSelection(MineFlipAdmission.REQUEST_DAILY);
        _mockMineRun(abi.encodeWithSignature("NoWork()"));
        probe.mine(address(game), 0, ALL, 5);
        _mockSelection(MineFlipAdmission.IDLE);
        _mockMineRun(abi.encodeWithSignature("RngNotReady()"));
        probe.mine(address(game), 0, ALL, 6);
        _mockSelection(MineFlipAdmission.TICKETS);
        _mockMineRun(abi.encodeWithSignature("InsufficientExecutionGas()"));
        probe.mine(address(game), 0, ALL, 7);
        assertEq(probe.judgeUnexpected(), 3);
        assertEq(probe.judgeFirstSite(), 5);
        assertGe(probe.judgeFirstGas(), MineFlipAdmission.minGas(MineFlipAdmission.REQUEST_DAILY, true));
        assertLe(probe.judgeFirstGas(), probe.TX_GAS_CAP());
    }

    /// @dev Real engine behind a stand-in that needs more than the cap: every judged call fails and is
    ///      flagged, though an unlimited-gas call would have passed.
    function test_workThatOnlyFitsAboveTheCapIsFlagged() public {
        _spy(17_000_000);
        _openDailyWindowUnjudged();
        vm.recordLogs();
        probe.mine(address(game), 0, IDLE_WAIT, 8);
        assertEq(probe.judgeUnexpected(), 1, "above-cap work flagged");
        assertEq(probe.judgeFirstSel(), bytes4(0));
        assertLe(probe.judgeFirstGas(), probe.TX_GAS_CAP());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "one judged call, no ample follow-up after a failure");
        (, uint256 gasIn) = abi.decode(logs[0].data, (address, uint256));
        assertLe(gasIn, probe.TX_GAS_CAP());
    }

    /// @dev A one-shot prank set by the handler reaches every call the judge makes.
    function test_prankedCallerReachesEveryJudgedCall() public {
        _spy(0);
        address who = address(0xA11CE);
        vm.recordLogs();
        (bool ok,) = probe.minePranked(address(game), who);
        assertTrue(ok, "the fresh engine has work");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("MineSeen(address,uint256)") || logs[i].emitter != address(game)) continue;
            (address caller,) = abi.decode(logs[i].data, (address, uint256));
            assertEq(caller, who);
            ++seen;
        }
        assertGe(seen, 1);
        assertEq(probe.judgeDrawnCalls(), 1);
        assertEq(probe.judgeUnexpected(), 0);
    }

    function test_prankedCallerReachesACappedCall() public {
        _spy(0);
        address who = address(0xB0B);
        vm.recordLogs();
        probe.minePrankedCapped(address(game), who, 16_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("MineSeen(address,uint256)") || logs[i].emitter != address(game)) continue;
            (address caller,) = abi.decode(logs[i].data, (address, uint256));
            assertEq(caller, who);
            ++seen;
        }
        assertEq(seen, 1, "one capped call, from the pranked caller");
        assertEq(probe.judgeUnexpected(), 0);
    }

    /// @dev A recorded call leaves no mapping-slot recording running, so a drain of many recorded
    ///      calls holds one call's hashes at a time.
    function test_recordedCallEndsMappingRecording() public {
        MappingWriter w = new MappingWriter();
        ChainProgress.start();
        w.set(7);
        ChainProgress.stop();
        w.set(8);
        assertEq(vm.getMappingLength(address(w), bytes32(0)), 0, "no mapping slot is recorded after stop");
        w.set(9);
        ChainProgress.discard();
        w.set(10);
        assertEq(vm.getMappingLength(address(w), bytes32(0)), 0, "no mapping slot is recorded after discard");
        Vm.StorageAccess[] memory acc = vm.getStorageAccesses();
        bytes32 dropped = keccak256(abi.encode(uint256(9), uint256(0)));
        bytes32 kept = keccak256(abi.encode(uint256(10), uint256(0)));
        bool sawKept;
        for (uint256 i; i < acc.length; ++i) {
            assertTrue(acc[i].slot != dropped, "discard dropped the write before it");
            if (acc[i].slot == kept) sawKept = true;
        }
        assertTrue(sawKept, "accesses after discard are still recorded");
    }

    /// @dev The ample follow-up call carries more than a transaction's gas but at most AMPLE_GAS.
    function test_ampleCallIsBounded() public {
        _spy(0);
        vm.recordLogs();
        (bool ok,) = probe.mine(address(game), 0, ALL, 1);
        assertTrue(ok, "the fresh engine has work");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ample;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("MineSeen(address,uint256)") || logs[i].emitter != address(game)) continue;
            (, uint256 gasIn) = abi.decode(logs[i].data, (address, uint256));
            assertLe(gasIn, probe.AMPLE_GAS());
            if (gasIn > probe.TX_GAS_CAP()) ++ample;
        }
        assertEq(ample, 1, "one ample call followed the judged call");
    }

    function _spy(uint256 need) internal {
        address production = address(0xC0DE0001);
        vm.etch(production, address(game).code);
        SpyGame spy = new SpyGame(production, need);
        vm.etch(address(game), address(spy).code);
    }

    /// @dev Advance to a state with work, without the judge (the spy may refuse every judged call).
    function _openDailyWindowUnjudged() internal {
        vm.warp(block.timestamp + 1 days);
        assertTrue(game.nextMinerAction() > 2, "work is selected");
    }

    /// @dev The real engine from a fresh deployment: cranking with VRF answered reaches NoWork
    ///      with nothing flagged.
    function test_realEngineDrainsToIdleWithNothingFlagged() public {
        bool idle;
        for (uint256 i; i < 200; ++i) {
            uint256 req = mockVRF.lastRequestId();
            if (req != 0) {
                (,, bool done) = mockVRF.pendingRequests(req);
                if (!done) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("judge", i))) | 2);
            }
            (bool ok, bytes4 sel) = probe.mine(address(game), 0, IDLE_WAIT, 1);
            if (!ok && sel == bytes4(keccak256("NoWork()"))) {
                idle = true;
                break;
            }
        }
        assertTrue(idle, "the fresh engine reaches NoWork");
        assertEq(probe.judgeUnexpected(), 0);
        assertGt(probe.judgeDrawnCalls(), 1, "every call went through admission");
        assertEq(probe.judgeUnread(), 0);
        probe.judgeCheck("selftest");
    }

    // ----- end-of-run stall probe -----

    function test_stallProbePassesOnTheRealEngineAndRestoresState() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        uint256 reqBefore = mockVRF.lastRequestId();
        bool lockedBefore = game.rngLocked();
        h.check(address(game), mockVRF);
        assertEq(mockVRF.lastRequestId(), reqBefore, "probe state restored");
        assertEq(game.rngLocked(), lockedBefore, "probe state restored");
    }

    function test_stallProbeFlagsWaitAfterDeliveryNoWorkWhileDueAndOtherReverts() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        _openDailyWindow();
        // A live, unanswered request: the probe delivers a valid word, so a wait that persists is a stall.
        _mockMineRun(abi.encodeWithSignature("RngNotReady()"));
        vm.expectRevert(bytes("selftest: stalled: mineRun answers RngNotReady after the outstanding VRF word was delivered"));
        h.check(address(game), mockVRF);

        _mockMineRun(abi.encodeWithSignature("NoWork()"));
        vm.mockCall(address(game), abi.encodeWithSignature("advanceDue()"), abi.encode(true));
        vm.expectRevert(bytes("selftest: stalled: mineRun answers NoWork while advanceDue() is true"));
        h.check(address(game), mockVRF);
        vm.mockCall(address(game), abi.encodeWithSignature("advanceDue()"), abi.encode(false));
        h.check(address(game), mockVRF); // idle and nothing owed is a healthy end state

        _mockMineRun(abi.encodeWithSignature("InsufficientExecutionGas()"));
        vm.expectRevert(bytes("selftest: stalled: mineRun reverts with a full transaction's gas, selector 0x331bb5b8"));
        h.check(address(game), mockVRF);
    }

    function _openDailyWindow() internal {
        for (uint256 i; i < 40 && !game.rngLocked(); ++i) {
            vm.warp(block.timestamp + 1 days);
            probe.mine(address(game), 0, IDLE_WAIT, 1);
        }
        assertTrue(game.rngLocked(), "a daily window opened");
        (,, bool done) = mockVRF.pendingRequests(mockVRF.lastRequestId());
        assertFalse(done, "the request is unanswered");
    }

    /// @dev A mineRun that returns without committing anything is a stall, not a healthy end state.
    function test_stallProbeFlagsSuccessWithoutProgress() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        _mockSelection(MineFlipAdmission.TICKETS);
        vm.mockCall(address(game), abi.encodeWithSelector(game.mineRun.selector), bytes(""));
        vm.expectRevert(bytes("selftest: stalled: mineRun succeeded without committing work, action 4, after 0 calls"));
        h.check(address(game), mockVRF);
    }

    /// @dev Work that commits state on every call but never finishes spends the unranked budget.
    function test_stallProbeFlagsWorkThatNeverFinishes() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        EndlessWorkGame endless = new EndlessWorkGame();
        vm.expectRevert(bytes("selftest: stalled: no quiescence within 1000 unranked calls (1001 in all)"));
        h.check(address(endless), mockVRF);
    }

    /// @dev From a live day the probe drains the engine to idle; a refused request ends the drain
    ///      healthy (the engine waits on its dependency), and the state is restored either way.
    function test_stallProbeDrainsALiveDayAndAcceptsARefusedRequest() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        _openDailyWindow();
        uint256 req = mockVRF.lastRequestId();
        h.check(address(game), mockVRF);
        assertTrue(game.rngLocked(), "state restored");
        assertEq(mockVRF.lastRequestId(), req, "state restored");
        _driveToIdle();
        vm.warp(block.timestamp + 1 days);
        _refuseRequests();
        h.check(address(game), mockVRF);
    }

    /// @dev Deliver words and mine until the engine reports nothing to do.
    function _driveToIdle() internal {
        for (uint256 i; i < 600; ++i) {
            if (game.nextMinerAction() == MineFlipAdmission.IDLE) return;
            uint256 req = mockVRF.lastRequestId();
            bool done = true;
            if (req != 0) (,, done) = mockVRF.pendingRequests(req);
            if (!done) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("drive", i))) | 2);
            else probe.mine(address(game), 0, IDLE_WAIT, 1);
        }
        revert("idle not reached");
    }

    /// @dev The coordinator rejects every request with a reason (an empty revert reads as a gas failure).
    function _refuseRequests() internal {
        vm.mockCallRevert(address(mockVRF), abi.encodeWithSelector(IVRFCoordinator.requestRandomWords.selector),
            abi.encodeWithSignature("Refused()"));
    }

    /// @dev Raw words 0/1 leave a request pending (admin retry or the dead-VRF path): the wait is by design
    ///      and the probe must not flag it; the probe must also restore the state.
    function test_stallProbeAcceptsAReservedWordWait() public {
        ChainStallProbeHarness h = new ChainStallProbeHarness();
        _openDailyWindow();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 1);
        assertEq(game.nextMinerAction(), 2, "the reserved word leaves the engine waiting");
        h.check(address(game), mockVRF);
        assertEq(game.nextMinerAction(), 2, "state restored");
    }
}

/// @title ChainCallJudgeCommitTest -- a judged call keeps every protocol account through a commit
/// @notice setUp is its own committed transaction, as is every invariant handler call. The judge cools
///         the protocol's accounts before its drawn call; an account the call does not reach again must
///         still hold its code and storage once that transaction commits.
contract ChainCallJudgeCommitTest is DeployProtocol {
    ChainCallJudgeProbe internal probe;
    bytes32 internal constant MARK_SLOT = keccak256("judge commit mark");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        probe = new ChainCallJudgeProbe();
        vm.store(ContractAddresses.ICONS_32, MARK_SLOT, bytes32(uint256(7)));
        probe.mine(address(game), 0, 3, 1);
    }

    function test_judgedCallInACommittedTransactionKeepsEveryProtocolAccount() public view {
        assertGt(probe.judgeDrawnCalls(), 0, "setUp's call went through admission and cooling");
        address[8] memory untouched = [
            ContractAddresses.ICONS_32, ContractAddresses.DEITY_PASS, ContractAddresses.GNRUS,
            ContractAddresses.ADMIN, ContractAddresses.WWXRP, ContractAddresses.VAULT,
            ContractAddresses.OWNER_GOVERNANCE, ContractAddresses.GAME_FOILPACK_MODULE
        ];
        for (uint256 i; i < untouched.length; ++i) {
            assertGt(untouched[i].code.length, 0, "a cooled account keeps its code through the commit");
        }
        assertGt(address(game).code.length, 0, "game keeps its code");
        assertEq(
            vm.load(ContractAddresses.ICONS_32, MARK_SLOT),
            bytes32(uint256(7)),
            "a cooled account keeps storage written earlier in the transaction"
        );
    }
}
