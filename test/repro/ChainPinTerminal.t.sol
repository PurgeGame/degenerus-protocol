// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {OwnerTargetCall} from "../helpers/OwnerTargetCall.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameGameOverModule} from "../../contracts/modules/DegenerusGameGameOverModule.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

// Pin tests for the terminal / game-over couplings of the mineFlip chain (audit slice S4
// F1..F7, S2 F-T4). The router and handler halves are checked on a storage harness; the
// request, drain and tally halves run the production Game.

uint8 constant ACTION_IDLE = 0;
uint8 constant ACTION_TERMINAL = 1;
uint8 constant ACTION_WAIT = 2;

// ------------------------------------------------------------------------------------------------
// Storage harness: the real GameOver module and router predicates over hand-seeded state.
// ------------------------------------------------------------------------------------------------

contract ChainPinGoHarness is DegenerusGameGameOverModule {
    /// @dev Bits: 0 level 5 (else 0), 1 next pool above the level target, 2 deadman, 3 request
    ///      unanswered past the VRF timeout, 4 purchase phase past its deadline, 5 ending started,
    ///      6 last-purchase day.
    function seedCase(uint256 m) external {
        uint24 day = _simulatedDayIndex();
        level = m & 1 != 0 ? 5 : 0;
        purchaseStartDay = m & 16 != 0 ? 1 : day;
        dailyIdx = m & 4 != 0 ? day - 31 : day - 1;
        lastPurchaseDay = m & 64 != 0;
        _setLevelPrizePool(5, 10 ether);
        _setPrizePools(m & 2 != 0 ? 11 ether : 9 ether, 0);
        if (m & 8 != 0) {
            rngRequestTime = uint48(block.timestamp - 15 days);
            _setRngRequestActive(true);
            _setRngSessionPublished(false);
            rngWordCurrent = RNG_WORD_WAITING;
            vrfRequestId = 7;
        }
        if (m & 32 != 0) {
            _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
            _setRngTerminal();
        }
    }

    /// @dev The state after `_requestTerminalRng` was accepted: swap latched, request active,
    ///      session unpublished, word awaited, timer armed now.
    function armTerminalRequest() external {
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _setRngTerminal();
        _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        rngRequestDay = _simulatedDayIndex();
        rngRequestTime = uint48(block.timestamp);
        vrfRequestId = 9;
        _setRngSessionPublished(false);
        rngWordCurrent = RNG_WORD_WAITING;
        _setRngRequestActive(true);
        rngLockedFlag = true;
    }

    /// @dev rawFulfillRandomWords' acceptance rule for the current request.
    function deliver(uint256 word) external {
        if (_rngRequestActive() && rngWordCurrent == RNG_WORD_WAITING) rngWordCurrent = word;
    }

    function endLoanStage() external { _goWrite(GO_LOAN_STEP_SHIFT, GO_LOAN_STEP_MASK, 0); }

    function liveness() external view returns (bool) { return _livenessTriggered(); }
    function action() external view returns (uint8) { return uint8(_nextMinerAction(address(0))); }
    function vrfDeadView() external view returns (bool) { return _vrfDead(); }
    function today() external view returns (uint24) { return _simulatedDayIndex(); }
    function levelNow() external view returns (uint24) { return level; }
    function recorded(uint24 day) external view returns (uint256) { return _recordedDailyWord(day); }
    function waitingWord() external pure returns (uint256) { return RNG_WORD_WAITING; }
    function wordNow() external view returns (uint256) { return rngWordCurrent; }
    function endingState() external view returns (bool active, bool published, uint256 dead, uint256 swap) {
        return (_rngRequestActive(), _rngSessionPublished(),
            _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK), _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK));
    }
}

contract ChainPinRouterTest is Test {
    ChainPinGoHarness private h;
    uint256 private constant LATE = 0xA11CE0DD;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 400 days);
        h = new ChainPinGoHarness();
    }

    function _advance(uint256 allowance) private returns (bool ok, bytes memory ret) {
        (ok, ret) = address(h).call{gas: 8_000_000}(
            abi.encodeCall(h.runGameOverAdvance, (h.today(), h.levelNow(), allowance)));
    }

    // ---------------------------------------------------------------- S4 F1

    /// @dev For every liveness cause and combination: whenever the trigger reads true, the handler
    ///      returns shouldReturn=true (or revert RngNotReady in a state the router calls Wait), so
    ///      the Advance module's `!handled -> E()` is unreachable. A met pool target rescues only
    ///      the bare purchase deadline of a level above 0 before the ending started.
    function test_F1_RescueRuleIsTheExactComplementOfTheLivenessTrigger() public {
        uint256 snap = vm.snapshotState();
        uint256 live;
        uint256 rescued;
        uint256 deadmanMet;
        uint256 vrfDeadMet;
        uint256 startedMet;
        uint256 level0Deadline;
        for (uint256 m; m < 128; ++m) {
            bool lvl5 = m & 1 != 0;
            bool met = m & 2 != 0;
            bool deadman = m & 4 != 0;
            bool vdead = m & 8 != 0;
            bool deadline = m & 16 != 0;
            bool started = m & 32 != 0;
            bool lastP = m & 64 != 0;
            h.seedCase(m);
            bool isLive = h.liveness();
            assertEq(isLive, deadman || vdead || (!lastP && deadline && (started || !(lvl5 && met))),
                string.concat("trigger truth table, case ", vm.toString(m)));
            if (lvl5 && met && deadline && !deadman && !vdead && !started && !lastP) {
                assertFalse(isLive, "a met target rescues the bare deadline");
                ++rescued;
            }
            if (isLive) {
                ++live;
                if (lvl5 && met && deadman) ++deadmanMet;
                if (lvl5 && met && vdead) ++vrfDeadMet;
                if (lvl5 && met && started) ++startedMet;
                if (!lvl5 && deadline && !deadman && !vdead && !lastP) ++level0Deadline;
                uint8 act = h.action();
                assertTrue(act == ACTION_TERMINAL || act == ACTION_WAIT, "router selects Terminal or Wait");
                (bool ok, bytes memory ret) = _advance(300_000);
                if (ok) {
                    (bool shouldReturn,,,) = abi.decode(ret, (bool, uint8, bool, bool));
                    assertTrue(shouldReturn, string.concat("handler returned unhandled, case ", vm.toString(m)));
                } else {
                    assertEq(ret.length, 4, string.concat("revert data, case ", vm.toString(m)));
                    assertEq(bytes4(ret), bytes4(keccak256("RngNotReady()")),
                        string.concat("handler reverted with a foreign error, case ", vm.toString(m)));
                    assertEq(act, ACTION_WAIT, string.concat("RngNotReady outside a Wait state, case ", vm.toString(m)));
                }
            }
            assertTrue(vm.revertToState(snap));
        }
        assertEq(rescued, 1, "the rescue shape was exercised");
        assertGt(deadmanMet, 0, "deadman with a met target");
        assertGt(vrfDeadMet, 0, "dead VRF with a met target");
        assertGt(startedMet, 0, "started ending with a met target");
        assertGt(level0Deadline, 0, "level 0 deadline");
        assertGt(live, 40, "enough live cases");
    }

    // ---------------------------------------------------------------- S2 F-T4 / dead clock

    function _assertTerminalOrWait(string memory label) private view {
        assertTrue(h.liveness(), string.concat("liveness persists, ", label));
        uint8 a = h.action();
        assertTrue(a == ACTION_TERMINAL || a == ACTION_WAIT, string.concat("action set, ", label));
    }

    function _sweepTime(bool mustBeTerminal, string memory label) private {
        uint256 base = block.timestamp;
        uint256 snap = vm.snapshotState();
        uint256[9] memory offsets = [uint256(0), 1 hours, 1 days, 13 days, 14 days, 14 days + 1, 29 days, 45 days, 400 days];
        for (uint256 i; i < offsets.length; ++i) {
            vm.warp(base + offsets[i]);
            _assertTerminalOrWait(label);
            if (mustBeTerminal) assertEq(h.action(), ACTION_TERMINAL, string.concat("never waits, ", label));
            assertTrue(vm.revertToState(snap));
        }
    }

    function test_FT4_DeadlineRouteStaysTerminalOrWaitAtEveryLaterTime() public {
        h.seedCase(1 | 16);
        (bool ok,) = _advance(300_000);
        assertTrue(ok, "latch call");
        _assertTerminalOrWait("latched, loans owed");
        _sweepTime(false, "latched, loans owed");
        h.endLoanStage();
        _sweepTime(false, "latched, loans done");
        h.armTerminalRequest();
        _sweepTime(false, "request in flight");
    }

    function test_FT4_DeadmanRouteStaysTerminalOrWaitAtEveryLaterTime() public {
        h.seedCase(1 | 4 | 64);
        (bool ok,) = _advance(300_000);
        assertTrue(ok, "latch call");
        _sweepTime(false, "deadman latched");
        h.endLoanStage();
        _sweepTime(false, "deadman, loans done");
        h.armTerminalRequest();
        _sweepTime(false, "deadman, request in flight");
    }

    function test_FT4_DeadVrfRouteIsTerminalAtEveryLaterTimeAndIgnoresLateWords() public {
        h.seedCase(1 | 8 | 64);
        (bool ok,) = _advance(300_000);
        assertTrue(ok, "dead ending latched");
        (bool active, bool published, uint256 dead,) = h.endingState();
        assertFalse(active);
        assertFalse(published);
        assertEq(dead, 1);
        h.deliver(LATE);
        assertEq(h.wordNow(), h.waitingWord(), "no callback authority after the latch");
        _sweepTime(true, "dead route");
    }

    /// @dev e48a39cfe: a request not in use 14 days after its send is dead even when its word was
    ///      delivered; the delivered word is discarded and the ending is the deterministic one.
    function test_FT4_WordDeliveredAfterTheWindowIsDiscarded() public {
        h.seedCase(1 | 16);
        h.armTerminalRequest();
        uint256 sent = block.timestamp;
        uint24 day = h.today();

        assertEq(h.action(), ACTION_WAIT, "waiting inside the window");
        vm.warp(sent + 14 days - 1);
        assertFalse(h.vrfDeadView());
        assertEq(h.action(), ACTION_WAIT);
        vm.warp(sent + 14 days);
        assertTrue(h.vrfDeadView(), "the window ends 14 days after the send");
        assertEq(h.action(), ACTION_TERMINAL);

        h.deliver(LATE);
        assertEq(h.wordNow(), LATE, "the callback still accepted the late word");
        assertTrue(h.vrfDeadView(), "a delivered word does not revive the request");
        assertEq(h.action(), ACTION_TERMINAL, "the ending takes the dead path");

        (bool ok,) = _advance(300_000);
        assertTrue(ok, "dead path call");
        (bool active, bool published, uint256 dead,) = h.endingState();
        assertFalse(active, "request dropped");
        assertFalse(published);
        assertEq(dead, 1, "dead ending latched");
        assertEq(h.wordNow(), h.waitingWord(), "late word discarded");
        assertEq(h.recorded(day), 0, "late word never recorded as a day word");
        assertEq(h.recorded(day + 1), 0);
        _sweepTime(true, "after the discard");
    }

    /// @dev The dead clock starts with the send: a word delivered inside the window keeps the request alive.
    function test_FT4_WordDeliveredInsideTheWindowKeepsTheRequestAlive() public {
        h.seedCase(1 | 16);
        h.armTerminalRequest();
        vm.warp(block.timestamp + 14 days - 1);
        h.deliver(LATE);
        assertFalse(h.vrfDeadView());
        assertEq(h.action(), ACTION_TERMINAL, "a delivered word is work, not a wait");
    }
}

// ------------------------------------------------------------------------------------------------
// S4 F2: how the terminal drain classifies a ticket-worker failure.
// ------------------------------------------------------------------------------------------------

error ChainPinForeignDrainError();

/// @dev Stands in for the ticket module; its behaviour is chosen through a harness storage slot.
contract ChainPinDrainStub {
    bytes32 internal constant MODE_SLOT = keccak256("chainpin.drain.mode");

    fallback() external {
        bytes32 slot = MODE_SLOT;
        uint256 mode;
        assembly ("memory-safe") { mode := sload(slot) }
        if (mode == 1) { assembly ("memory-safe") { revert(0, 0) } }
        if (mode == 2) revert MineFlipGas.EmptyRevert();
        if (mode == 3) revert MineFlipGas.InsufficientExecutionGas();
        if (mode == 4) revert MineFlipGas.WorkGasBound();
        if (mode == 5) revert ChainPinForeignDrainError();
        if (mode == 6) revert("foreign string");
        bytes memory out = abi.encode(MineFlipGas.Result(true, false, 0));
        assembly ("memory-safe") { return(add(out, 32), mload(out)) }
    }
}

contract ChainPinDrainHarness is DegenerusGameGameOverModule, BucketSeed {
    function seed(bool postSwap) external {
        uint24 day = _simulatedDayIndex();
        level = 10;
        dailyIdx = day - 1;
        purchaseStartDay = 1;
        _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, 1);
        _setRngTerminal();
        _setRngSessionPublished(true);
        rngWordCurrent = 0xB0B5;
        _seedQueued(_tqReadKey(10), 10, address(0xBEEF01), uint80(5) << 8);
        if (postSwap) {
            _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
            rngRequestDay = day;
            rngRequestTime = uint48(block.timestamp);
            vrfRequestId = 9;
            _setRngRequestActive(true);
            rngLockedFlag = true;
        }
    }

    function today() external view returns (uint24) { return _simulatedDayIndex(); }
    function swapLatched() external view returns (uint256) { return _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK); }
}

contract ChainPinDrainClassTest is Test {
    bytes32 private constant MODE_SLOT = keccak256("chainpin.drain.mode");
    ChainPinDrainHarness private h;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 100 days);
        h = new ChainPinDrainHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(ChainPinDrainStub).runtimeCode);
    }

    function _run(uint256 mode) private returns (bool ok, bytes memory ret) {
        vm.store(address(h), MODE_SLOT, bytes32(mode));
        (ok, ret) = address(h).call{gas: 12_000_000}(abi.encodeCall(h.runGameOverAdvance, (h.today(), 10, 10_000_000)));
    }

    /// @dev Empty data, InsufficientExecutionGas, WorkGasBound and EmptyRevert from the worker are
    ///      re-raised (the call reverts, nothing latches); an error of its own is swallowed so the
    ///      ending moves on. Both before and after the swap.
    function test_F2_DrainFallbackRethrowsExactlyTheGasClass() public {
        uint256 snap = vm.snapshotState();
        for (uint256 post; post < 2; ++post) {
            h.seed(post == 1);
            uint256 snap2 = vm.snapshotState();
            bytes4[5] memory expected = [
                bytes4(0), MineFlipGas.InsufficientExecutionGas.selector, MineFlipGas.EmptyRevert.selector,
                MineFlipGas.InsufficientExecutionGas.selector, MineFlipGas.WorkGasBound.selector
            ];
            for (uint256 mode = 1; mode <= 4; ++mode) {
                (bool ok, bytes memory ret) = _run(mode);
                assertFalse(ok, string.concat("gas-class failure must revert, mode ", vm.toString(mode)));
                assertEq(bytes4(ret), expected[mode], string.concat("rethrown selector, mode ", vm.toString(mode)));
                assertEq(h.swapLatched(), post, "nothing latched by a re-raised failure");
                assertTrue(vm.revertToState(snap2));
            }
            if (post == 0) {
                for (uint256 mode = 5; mode <= 6; ++mode) {
                    (bool ok,) = _run(mode);
                    assertTrue(ok, string.concat("an error of the worker's own is swallowed, mode ", vm.toString(mode)));
                    assertTrue(vm.revertToState(snap2));
                }
                (bool ok0,) = _run(0);
                assertTrue(ok0, "a progressing batch returns");
                assertEq(h.swapLatched(), 0, "and leaves the swap window open");
            }
            assertTrue(vm.revertToState(snap));
        }
    }
}

// ------------------------------------------------------------------------------------------------
// Production Game: terminal request, drain, tally.
// ------------------------------------------------------------------------------------------------

contract ChainPinSeeder is DeadVrfSeeder {
    function pinIdentity()
        external
        view
        returns (uint24 reqDay, uint48 reqTime, bool active, bool published, uint256 swap, uint256 dead, uint256 word)
    {
        return (rngRequestDay, rngRequestTime, _rngRequestActive(), _rngSessionPublished(),
            _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK), _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK), rngWordCurrent);
    }

    function pinPaid() external view returns (uint256) {
        return _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK);
    }

    function pinBuckets(uint24 lvl) external view returns (uint256 total) {
        for (uint256 t; t < 256; ++t) total += _bucketLength(lvl, t);
    }

    function pinApplied() external view returns (uint48) { return lastVrfProcessedTimestamp; }

    function pinDayWord(uint24 day) external view returns (uint256) { return _recordedDailyWord(day); }

    /// @dev A mid-day request unanswered for 15 days (no daily lock), so purchase writers are not
    ///      stopped by anything but the liveness trigger.
    function pinSeedDeadMidday(uint24 lvl) external {
        TQ.retireCompleted(address(this), lvl);
        uint24 day = _simulatedDayIndex();
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        level = lvl;
        jackpotPhaseFlag = false;
        lastPurchaseDay = false;
        phaseTransitionActive = false;
        rngLockedFlag = false;
        rngWordCurrent = RNG_WORD_WAITING;
        vrfRequestId = 777;
        _setRngRequestActive(true);
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp - 15 days);
        ticketsFullyProcessed = true;
        prizePoolFrozen = false;
    }

    /// @dev Everything `_tallyDeadVrf` counts: the three queues of `lvl`, the foil counts and the
    ///      created-ticket bucket lengths.
    function pinTallyInputs(uint24 lvl) external view returns (bytes32 d) {
        uint24[3] memory keys = [_tqReadKey(lvl), _tqWriteKey(lvl), _tqFarFutureKey(lvl)];
        for (uint256 k; k < 3; ++k) {
            uint256 len = _ticketQueueLength(keys[k]);
            d = keccak256(abi.encode(d, k, len));
            uint256[] storage q = ticketQueue[_ticketQueueStorageKey(keys[k])];
            for (uint256 p; p < len; ++p) {
                uint32 id = _tqPositionAt(q, p);
                d = keccak256(abi.encode(d, id, _entryPacked(keys[k], id)));
            }
        }
        d = keccak256(abi.encode(d, foilWriteCount, foilReadCount, foilCursor, _foilCount(0), _foilCount(1)));
        for (uint256 t; t < 256; ++t) d = keccak256(abi.encode(d, _bucketLength(lvl, t)));
    }
}

contract ChainPinTerminalFlowTest is DeployProtocol {
    uint24 private constant LVL = 5000; // purchase phase: the terminal ticket level is LVL + 1
    uint24 private constant TLVL = LVL + 1;
    uint256 private constant LATE = 0xA11CE0DD;
    bytes32 private constant PAYOUT_FIXED_SIG =
        keccak256("DeadVrfPayoutFixed(uint24,uint256,uint256,uint256,uint256)");
    bytes32 private constant JACKPOT_WIN_SIG = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    struct Id {
        uint24 reqDay;
        uint48 reqTime;
        bool active;
        bool published;
        uint256 swap;
        uint256 dead;
        uint256 word;
    }

    bytes private realCode;
    uint32[] private cohortPos;
    address private erin = makeAddr("chainpin-erin");

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 200 days);
        vm.deal(address(game), 100 ether);
        realCode = address(game).code;
    }

    // ---------------------------------------------------------------- helpers

    function _seeder() private returns (ChainPinSeeder s) {
        vm.etch(address(game), type(ChainPinSeeder).runtimeCode);
        s = ChainPinSeeder(payable(address(game)));
    }

    function _restore() private { vm.etch(address(game), realCode); }

    function _id() private returns (Id memory r) {
        ChainPinSeeder s = _seeder();
        (r.reqDay, r.reqTime, r.active, r.published, r.swap, r.dead, r.word) = s.pinIdentity();
        _restore();
    }

    function _dayWord(uint24 day) private returns (uint256 w) { w = _seeder().pinDayWord(day); _restore(); }

    function _paid() private returns (uint256 p) { p = _seeder().pinPaid(); _restore(); }

    function _queues() private returns (uint256 rl, uint256 wl, uint256 sw) {
        (rl, wl, sw) = _seeder().terminalQueues(TLVL);
        _restore();
    }

    function _owedTotal() private returns (uint256 owed) {
        ChainPinSeeder s = _seeder();
        for (uint256 i; i < cohortPos.length; ++i) owed += s.owedAt(TLVL, cohortPos[i]);
        _restore();
    }

    function _progressDigest() private returns (bytes32 d) {
        ChainPinSeeder s = _seeder();
        (uint256 rl, uint256 wl, uint256 sw) = s.terminalQueues(TLVL);
        uint256 owed;
        for (uint256 i; i < cohortPos.length; ++i) owed += s.owedAt(TLVL, cohortPos[i]);
        (uint24 reqDay, uint48 reqTime, bool active, bool published,, uint256 dead, uint256 word) = s.pinIdentity();
        d = keccak256(abi.encode(rl, wl, sw, owed, s.pinBuckets(TLVL), s.pinPaid(), game.gameOver(),
            reqDay, reqTime, active, published, dead, word));
        _restore();
    }

    function _seedCohort(uint256 owners, uint32 entries, bool writeSide) private {
        ChainPinSeeder s = _seeder();
        s.seedDeadlineWithLandedCohort(LVL, 0xB0B5);
        for (uint256 i; i < owners; ++i) {
            cohortPos.push(s.seedQueued(TLVL, writeSide, address(uint160(0xD00D0000 + i + 1)), entries, 0));
        }
        _restore();
        assertTrue(game.livenessTriggered(), "deadline passed, caught up, VRF alive");
    }

    /// @dev Decision call, then the (empty) loan stage.
    function _toBeforeSwap() private {
        game.mineFlip(0);
        game.mineFlip(0);
    }

    /// @dev Cohort on the write side; ends right after the one call that swaps, arms and sends.
    function _toRequestSent(uint256 owners, uint32 entries) private returns (uint256 req) {
        _seedCohort(owners, entries, true);
        uint256 req0 = mockVRF.lastRequestId();
        _toBeforeSwap();
        assertEq(mockVRF.lastRequestId(), req0, "no request before the swap call");
        game.mineFlip(0);
        req = mockVRF.lastRequestId();
        assertGt(req, req0, "the swap call armed and sent the terminal request");
    }

    function _assertGasClass(bytes memory err, string memory label) private pure {
        if (err.length == 0) return;
        require(err.length == 4 && (bytes4(err) == MineFlipGas.InsufficientExecutionGas.selector
            || bytes4(err) == MineFlipGas.EmptyRevert.selector || bytes4(err) == MineFlipGas.WorkGasBound.selector),
            label);
    }

    function _answer(MockVRFCoordinator vrf) private {
        uint256 id = vrf.lastRequestId();
        if (id == 0) return;
        (,, bool done) = vrf.pendingRequests(id);
        if (!done) vrf.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, "chainpin"))));
    }

    function _freshCoordinator() private returns (MockVRFCoordinator fresh) {
        fresh = new MockVRFCoordinator();
        uint256 sub = fresh.createSubscription();
        fresh.addConsumer(sub, address(game));
        fresh.fundSubscription(sub, 100e18);
        vm.prank(address(admin));
        game.updateVrfCoordinatorAndSub(address(fresh), sub, bytes32(uint256(1)));
    }

    function _sawLog(Vm.Log[] memory logs, bytes32 sig) private view returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == sig) return true;
        }
        return false;
    }

    function _finish(MockVRFCoordinator vrf, uint256 maxCalls) private {
        for (uint256 i; i < maxCalls; ++i) {
            if (game.gameOver() && _paid() != 0) return;
            _answer(vrf);
            game.mineFlip{gas: 12_000_000}(0);
        }
        fail("ending did not finish");
    }

    /// @dev Sampled over later timestamps without disturbing state.
    function _assertActionSet(string memory label) private {
        uint256 base = block.timestamp;
        uint256 snap = vm.snapshotState();
        uint256[7] memory offsets = [uint256(0), 1 hours, 1 days, 13 days, 14 days + 1, 45 days, 400 days];
        for (uint256 i; i < offsets.length; ++i) {
            vm.warp(base + offsets[i]);
            uint8 a = game.nextMinerAction();
            assertTrue(a == ACTION_TERMINAL || a == ACTION_WAIT || a == ACTION_IDLE, label);
            assertTrue(game.livenessTriggered() || game.gameOver(), label);
            assertTrue(vm.revertToState(snap));
        }
    }

    // ---------------------------------------------------------------- S2 F-T4 (production Game)

    function test_FT4_LateWordAfterFourteenDaysNeverAppliesAndTheEndingIsDeterministic() public {
        uint256 req = _toRequestSent(3, 40);
        Id memory a = _id();
        assertTrue(a.active && a.swap == 1 && a.reqDay != 0, "request armed and active");
        assertEq(a.reqTime, block.timestamp, "armed in the same call that sent it");
        _assertActionSet("request in flight");

        vm.warp(uint256(a.reqTime) + 14 days);
        assertTrue(game.livenessTriggered());
        mockVRF.fulfillRandomWords(req, LATE);
        assertGt(_id().word, 1, "the late word reached the Game");
        assertEq(game.nextMinerAction(), ACTION_TERMINAL, "a late word is not a wait");

        vm.recordLogs();
        for (uint256 i; i < 60 && !game.gameOver(); ++i) {
            assertEq(game.nextMinerAction(), ACTION_TERMINAL, "terminal every step");
            game.mineFlip(0);
            assertEq(mockVRF.lastRequestId(), req, "no further VRF request on the dead path");
        }
        assertTrue(game.gameOver(), "ended");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_sawLog(logs, PAYOUT_FIXED_SIG), "deterministic payout");
        assertFalse(_sawLog(logs, JACKPOT_WIN_SIG), "no drawn jackpot");
        assertEq(_dayWord(a.reqDay), 0, "the late word was never recorded");
        assertTrue(_id().dead == 1, "dead ending latched");
        uint8 after_ = game.nextMinerAction();
        assertTrue(after_ == ACTION_IDLE || after_ == ACTION_TERMINAL, "post-ending action");
    }

    function test_FT4_WordDeliveredInsideTheWindowGivesTheNormalEnding() public {
        uint256 req = _toRequestSent(3, 40);
        Id memory a = _id();
        vm.warp(uint256(a.reqTime) + 13 days);
        mockVRF.fulfillRandomWords(req, LATE);
        vm.recordLogs();
        _finish(mockVRF, 120);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertFalse(_sawLog(logs, PAYOUT_FIXED_SIG), "normal VRF ending");
        assertTrue(_dayWord(a.reqDay) != 0, "the delivered word was applied");
    }

    // ---------------------------------------------------------------- S4 F3

    /// @dev A swap latched without arming is repaired by the next call: it arms (day and a fresh
    ///      timer) and sends the request, so the ending is never left without its request.
    function test_F3_UnarmedSwapLatchIsRepairedByTheNextCall() public {
        _seedCohort(2, 40, true);
        _toBeforeSwap();
        uint256 base = vm.snapshotState();
        uint256[4] memory gases = [uint256(300_000), 1_000_000, 2_000_000, 2_600_000];
        for (uint256 i; i < gases.length; ++i) {
            assertTrue(vm.revertToState(base));
            uint256 req0 = mockVRF.lastRequestId();
            (bool ok,) = address(game).call{gas: gases[i]}(abi.encodeCall(game.mineFlip, (uint32(0))));
            if (!ok) continue;
            Id memory r = _id();
            if (r.swap == 0 || r.active) continue;
            vm.warp(block.timestamp + 1 hours);
            game.mineFlip(0);
            Id memory after_ = _id();
            assertGt(mockVRF.lastRequestId(), req0, "the next call sent the request");
            assertTrue(after_.active && after_.reqDay != 0 && after_.reqTime == block.timestamp, "and armed it afresh");
        }
    }

    // ---------------------------------------------------------------- S4 F7

    function test_F7_RequestActiveStaysSetFromTheRequestUntilThePayoutCompletes() public {
        _toRequestSent(3, 40);
        Id memory a = _id();
        assertTrue(a.active, "request active");

        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);
        assertTrue(_id().active, "a waiting call leaves the request set");

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip(0);
        assertTrue(_id().active, "a day later");

        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        OwnerTargetCall.call(address(admin), abi.encodeCall(admin.retryGameRng, ()), 0);
        assertTrue(_id().active, "the owner retry is closed during the ending");

        // A coordinator swap re-sends the request and keeps it active and unpublished.
        MockVRFCoordinator fresh = _freshCoordinator();
        assertEq(fresh.lastRequestId(), 1, "the swap re-sent the terminal request");
        Id memory b = _id();
        assertTrue(b.active && !b.published, "still active after the swap");
        assertEq(b.reqTime, a.reqTime, "the dead clock keeps its origin");

        // The new coordinator answers the re-sent request.
        fresh.fulfillRandomWords(1, uint256(keccak256("fresh")));
        assertTrue(_id().active, "delivery does not clear the request");

        game.mineFlip(0); // applies the word
        Id memory c = _id();
        assertTrue(c.active && c.published && c.swap == 1 && c.reqDay != 0, "word applied, request still set");
        assertTrue(_dayWord(c.reqDay) != 0, "day word recorded");
        ChainPinSeeder s0 = _seeder();
        uint48 appliedAt = s0.pinApplied();
        _restore();

        for (uint256 i; i < 120; ++i) {
            if (game.gameOver() && _paid() != 0) break;
            game.mineFlip{gas: 12_000_000}(0);
            if (_paid() == 0) {
                Id memory d = _id();
                assertTrue(d.active && d.published, "request stays set through the drain");
            }
            ChainPinSeeder s1 = _seeder();
            assertEq(s1.pinApplied(), appliedAt, "the word is applied once");
            _restore();
        }
        assertTrue(game.gameOver(), "ended");
    }

    // ---------------------------------------------------------------- S4 F2

    function _queuesRead() private returns (uint256 rl) { (rl,,) = _queues(); }

    /// @dev Before the swap, a landed read cohort drains one batch per call. A starved call must
    ///      leave the swap window open (the write cohort still swaps in later) and may only fail
    ///      with a gas-class error; every successful call progresses.
    function test_F2_StarvedPreSwapBatchNeverClosesTheSwapWindowOrRaisesAForeignError() public {
        ChainPinSeeder s = _seeder();
        s.seedDeadlineWithLandedCohort(LVL, 0xB0B5);
        for (uint160 i = 1; i <= 24; ++i) cohortPos.push(s.seedQueued(TLVL, false, address(0xD00D0000 + i), 1000, 0));
        uint32 erinAt = s.seedQueued(TLVL, true, erin, 2, 0);
        _restore();
        assertTrue(game.livenessTriggered());
        _toBeforeSwap();
        uint256 base = vm.snapshotState();

        uint256 g0 = gasleft();
        game.mineFlip{gas: 10_000_000}(0);
        uint256 batchGas = g0 - gasleft();
        Id memory ref = _id();
        assertEq(ref.swap, 0, "a batch call leaves the swap window open");
        assertGt(_queuesRead(), 0, "one batch does not drain the read side");
        assertTrue(vm.revertToState(base));

        uint256 oks;
        uint256 gasFails;
        uint256 leaks;
        uint256 witness;
        uint256 step = batchGas / 120 > 2_000 ? batchGas / 120 : 2_000;
        for (uint256 g = 30_000; g <= batchGas + 150_000; g += step) {
            assertTrue(vm.revertToState(base));
            try game.mineFlip{gas: g}(0) {
                ++oks;
            } catch (bytes memory err) {
                _assertGasClass(err, "a starved batch raised a foreign error");
                ++gasFails;
                if (witness == 0) witness = g;
            }
            if (_id().swap != 0) ++leaks;
        }
        emit log_named_uint("batchGas", batchGas);
        emit log_named_uint("firstGasFailure", witness);
        assertEq(leaks, 0, "a starved call closed the swap window with the read cohort undrained");
        assertGt(gasFails, 0, "the sweep starved real batches");
        assertGt(oks, 0, "and let real batches through");

        // A starved call first, then full gas: the read side drains, the write cohort swaps in and is drawn.
        assertTrue(vm.revertToState(base));
        try game.mineFlip{gas: witness}(0) {} catch {}
        _finish(mockVRF, 200);
        (uint256 rl, uint256 wl,) = _queues();
        assertEq(rl + wl, 0, "no terminal cohort stranded");
        ChainPinSeeder s2 = _seeder();
        assertEq(s2.owedAt(TLVL, erinAt), 0, "the write cohort was drawn");
        _restore();
        assertEq(_owedTotal(), 0, "the read cohort was drained");
    }

    /// @dev After the word applies, a single maximal entry drains over several calls. At every gas
    ///      level a call progresses or fails with a gas-class error, no call lets the payout or
    ///      gameOver run ahead of an unpaid cohort, and the cohort is fully materialized afterwards.
    function test_F2_StarvedPostSwapBatchProgressesOrFailsWithAGasErrorOnly() public {
        _seedCohort(1, 6_000, true);
        _toBeforeSwap();
        game.mineFlip(0); // swap, arm, send
        uint256 req = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(req, uint256(keccak256("chainpin-word")));
        game.mineFlip(0); // applies the word
        assertTrue(_dayWord(_id().reqDay) != 0, "terminal word recorded");
        (uint256 rl,,) = _queues();
        assertGt(rl, 0, "cohort queued behind the word");
        uint256 base = vm.snapshotState();

        uint256 g0 = gasleft();
        game.mineFlip{gas: 10_000_000}(0);
        uint256 batchGas = g0 - gasleft();
        assertTrue(vm.revertToState(base));
        bytes32 before_ = _progressDigest();

        uint256 oks;
        uint256 gasFails;
        uint256 step = batchGas / 12 > 100_000 ? batchGas / 12 : 100_000;
        for (uint256 g = 40_000; g <= batchGas + 300_000; g += step) {
            assertTrue(vm.revertToState(base));
            try game.mineFlip{gas: g}(0) {
                ++oks;
                assertTrue(_progressDigest() != before_, "a successful call made progress");
            } catch (bytes memory err) {
                _assertGasClass(err, "a starved drain raised a foreign error");
                ++gasFails;
            }
            if (_owedTotal() != 0 || _queuesRead() != 0) {
                assertFalse(game.gameOver(), "payout ahead of an unpaid cohort");
                assertEq(_paid(), 0, "payout completed ahead of an unpaid cohort");
            }
            // Finish from the starved state: the whole cohort is materialized.
            for (uint256 i; i < 300 && _paid() == 0; ++i) game.mineFlip{gas: 12_000_000}(0);
            assertEq(_owedTotal(), 0, "entire cohort materialized");
            (uint256 rl2,,) = _queues();
            assertEq(rl2, 0, "read queue released");
        }
        emit log_named_uint("batchGas", batchGas);
        assertGt(gasFails, 0, "the sweep starved real batches");
        assertGt(oks, 0, "and let real batches through");
    }

    // ---------------------------------------------------------------- coordinator item 3b

    /// @dev _vrfDead() reads an active request's `published` flag as "its word is present": the state
    ///      (active, published, word still waiting) would make the router wait forever.
    function _chk(string memory label) private {
        Id memory r = _id();
        assertFalse(r.active && r.published && r.word == 1, label);
    }

    function test_F3b_TerminalRefusalRetryAndApplicationNeverPublishAnEmptyWord() public {
        _seedCohort(2, 40, true);
        _toBeforeSwap();
        _chk("before the swap");
        vm.mockCallRevert(
            address(mockVRF), abi.encodeWithSelector(MockVRFCoordinator.requestRandomWords.selector),
            abi.encodeWithSignature("Error(string)", "coordinator refuses request")
        );
        try game.mineFlip(0) {} catch {}
        _chk("armed and refused");
        Id memory a = _id();
        assertTrue(a.reqDay != 0 && !a.active, "armed without a request");
        try game.mineFlip(0) {} catch {}
        _chk("refused again");
        vm.clearMockedCalls();
        uint256 req0 = mockVRF.lastRequestId();
        game.mineFlip(0);
        assertGt(mockVRF.lastRequestId(), req0, "the retry sent the request");
        _chk("sent");
        _answer(mockVRF);
        _chk("delivered");
        for (uint256 i; i < 200 && !(game.gameOver() && _paid() != 0); ++i) {
            game.mineFlip{gas: 12_000_000}(0);
            _chk("terminal step");
            _answer(mockVRF);
            _chk("terminal step, answered");
        }
        assertTrue(game.gameOver(), "ended");
    }

    function test_F3b_DeadLatchAfterALateWordNeverPublishesAnEmptyWord() public {
        uint256 req = _toRequestSent(3, 40);
        _chk("sent");
        Id memory a = _id();
        vm.warp(uint256(a.reqTime) + 14 days);
        mockVRF.fulfillRandomWords(req, LATE);
        _chk("late word delivered");
        for (uint256 i; i < 60 && !game.gameOver(); ++i) {
            game.mineFlip(0);
            _chk("dead step");
        }
        assertTrue(game.gameOver(), "ended");
    }

    // ---------------------------------------------------------------- S4 F6

    function _tallyInputs() private returns (bytes32 d) {
        d = _seeder().pinTallyInputs(TLVL);
        _restore();
    }

    function _writer(uint256 w, address who, uint256 seat) private {
        vm.startPrank(who);
        if (w == 0) {
            try game.purchase{value: 1 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        } else if (w == 1) {
            try game.purchase{value: 5 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, true) {} catch {}
        } else if (w == 2) {
            try game.purchaseWhalePass{value: 10 ether}(0, 1, bytes32(0)) {} catch {}
        } else if (w == 3) {
            try game.purchaseLazyPass{value: 1 ether}(0, bytes32(0)) {} catch {}
        } else if (w == 4) {
            try game.purchaseDeityPass{value: 200 ether}(0, 9, bytes32(0)) {} catch {}
        } else if (w == 5) {
            try game.placeDegeneretteBet{value: 0.01 ether}(0, 0, 0.01 ether, 1, 0) {} catch {}
        } else if (w == 6) {
            try game.claimWhalePass(0) {} catch {}
        } else if (w == 7) {
            try game.subscribe{value: 2 ether}(0, true, 1, seat) {} catch {}
        } else {
            uint256[] memory refs = new uint256[](1);
            refs[0] = (uint256(1) << 248) | (uint256(TLVL) << 32) | 1;
            try game.claimDeadVrf(0, refs) {} catch {}
        }
        vm.stopPrank();
    }

    /// @dev Between tally transactions (including before the first and with a partial tally), no
    ///      ticket, foil or trait-bucket writer changes anything the tally counts.
    function test_F6_NoWriterMovesTheTallyInputsBetweenTallyCalls() public {
        address alice = makeAddr("cp-alice");
        address bob = makeAddr("cp-bob");
        address dave = makeAddr("cp-dave");
        address frank = makeAddr("cp-frank");
        ChainPinSeeder s = _seeder();
        s.pinSeedDeadMidday(LVL);
        s.seedCreated(TLVL, 3, alice, 3);
        s.seedCreated(TLVL, 3, bob, 1);
        s.seedCreated(TLVL, 200, alice, 2);
        cohortPos.push(s.seedQueued(TLVL, false, dave, 4, 50));
        cohortPos.push(s.seedQueued(TLVL, true, erin, 2, 0));
        for (uint160 i = 1; i <= 12; ++i) cohortPos.push(s.seedQueued(TLVL, false, address(0xCAFE0000 + i), 300, 0));
        s.seedFoil(TLVL, uint24(block.timestamp / 1 days), frank);
        _restore();

        address buyer = makeAddr("cp-buyer");
        vm.deal(buyer, 5_000 ether);
        _giveWalletId(buyer);
        uint256 seat = _grantSeat(buyer);
        assertTrue(game.livenessTriggered(), "liveness fired");
        bytes32 d0 = _tallyInputs();

        for (uint256 i; i < 40 && !game.gameOver(); ++i) {
            uint256 moved;
            for (uint256 w; w < 9; ++w) {
                uint256 sn = vm.snapshotState();
                _writer(w, buyer, seat);
                if (_tallyInputs() != d0) moved |= uint256(1) << w;
                assertTrue(vm.revertToState(sn));
            }
            assertEq(moved, 0, string.concat("writers that moved the tally inputs (bitmask): ", vm.toString(moved)));
            try game.mineFlip{gas: i < 6 ? 400_000 : 12_000_000}(0) {} catch {}
            assertEq(_tallyInputs(), d0, "a tally call moved the tally inputs");
        }
        assertTrue(game.gameOver(), "dead ending completed");
    }
}

/// @notice Coordinator item 3b over the live request kinds: daily, mid-day and the Admin retry.
contract ChainPinRequestKindsTest is DeployProtocol {
    bytes private realCode;
    uint256 private dailySteps;
    uint256 private middaySteps;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 100 ether);
        realCode = address(game).code;
    }

    function _chk(string memory label) private {
        vm.etch(address(game), type(ChainPinSeeder).runtimeCode);
        (uint24 reqDay,, bool active, bool published,,, uint256 word) = ChainPinSeeder(payable(address(game))).pinIdentity();
        vm.etch(address(game), realCode);
        assertFalse(active && published && word == 1, label);
        if (active && !published) {
            if (reqDay == 0) ++middaySteps;
            else ++dailySteps;
        }
    }

    function test_F3b_DailyMiddayAndAdminRetryNeverPublishAnEmptyWord() public {
        address buyer = makeAddr("pin-kinds-buyer");
        vm.deal(buyer, 1_000 ether);
        _giveWalletId(buyer);
        bool retried;
        bool retryOk;
        for (uint256 day; day < 6; ++day) {
            vm.warp(block.timestamp + 1 days + 1);
            vm.prank(buyer);
            try game.purchase{value: 1 ether}(
                0, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false
            ) {} catch {}
            for (uint256 j; j < 150; ++j) {
                uint256 id = mockVRF.lastRequestId();
                if (id != 0) {
                    (,, bool done) = mockVRF.pendingRequests(id);
                    if (!done) {
                        if (day == 2 && !retried) {
                            retried = true;
                            vm.warp(block.timestamp + 21 hours);
                            _chk("before the retry");
                            vm.prank(ContractAddresses.OWNER_GOVERNANCE);
                            (retryOk,) = address(admin).call(abi.encodeCall(admin.retryGameRng, ()));
                            _chk("after the retry");
                            id = mockVRF.lastRequestId();
                            (,, done) = mockVRF.pendingRequests(id);
                        }
                        if (!done) {
                            mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(id, "pin-kinds"))) | 2);
                            _chk("fulfilled");
                        }
                    }
                }
                vm.prank(buyer);
                try game.mineFlip(0) {} catch {}
                _chk("after a mineFlip");
            }
        }
        emit log_named_uint("dailyRequestSteps", dailySteps);
        emit log_named_uint("middayRequestSteps", middaySteps);
        emit log_named_uint("retryAccepted", retryOk ? 1 : 0);
        assertGt(dailySteps, 0, "daily requests were driven");
    }
}
