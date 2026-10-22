// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {VRFRandomWordsRequest} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MockVRFCoordinator} from "../../contracts/mocks/MockVRFCoordinator.sol";

/// @title RngVectorVrfConfirmations -- every VRF request carries the confirmations its kind owns
/// @notice Daily and terminal requests ask for 6 confirmations, mid-day requests for 4, and the
///         two re-issue paths (the admin retry and the coordinator rotation) keep the kind of the
///         request they replace. Checked with exact-calldata expectCall on the coordinator,
///         including the key hash, subscription, callback gas and word count, so a request with
///         any other confirmation count fails the count-zero expectation.
contract RngVectorVrfConfirmations is DegenesisHarness {
    bytes4 internal constant REQ_SEL = bytes4(keccak256("requestRandomWords((bytes32,uint256,uint16,uint32,uint32,bytes))"));

    address internal buyer;

    function setUp() public override {
        super.setUp();
        _drive(0);
        buyer = _player("conf-buyer");
        _earnCredit(buyer, 1 ether);
        _driveDay(2, 0);
        mockVRF.fundSubscription(1, 100e18);
    }

    function _reqData(uint16 confirmations) internal view returns (bytes memory) {
        bytes32 keyHash = vm.load(address(game), bytes32(GameSlots.VRF_KEY_HASH));
        uint256 subId = uint256(vm.load(address(game), bytes32(GameSlots.VRF_SUBSCRIPTION_ID)));
        return abi.encodeWithSelector(
            REQ_SEL,
            VRFRandomWordsRequest({
                keyHash: keyHash,
                subId: subId,
                requestConfirmations: confirmations,
                callbackGasLimit: 300_000,
                numWords: 1,
                extraArgs: ""
            })
        );
    }

    /// @dev Make the day's daily request and leave it unanswered.
    function _dailyRequest(uint24 d) internal returns (uint256 req) {
        _warpTo(d, 1 hours);
        _stepToRequest();
        game.mineFlip(0);
        req = mockVRF.lastRequestId();
        lastFulfilledReq = req;
        assertTrue(game.rngLocked(), "daily request out");
    }

    /// @dev Queue boxes past the mid-day threshold and mine until the mid-day request goes out.
    function _middayRequest() internal returns (uint256 req) {
        _earnCredit(buyer, 1 ether);
        uint256 req0 = mockVRF.lastRequestId();
        for (uint256 i; i < 40 && mockVRF.lastRequestId() == req0; ++i) {
            try game.mineFlip(0) {} catch { break; }
        }
        req = mockVRF.lastRequestId();
        assertEq(req, req0 + 1, "mid-day request out");
        assertFalse(game.rngLocked(), "mid-day: no daily lock");
        lastFulfilledReq = req;
    }

    /// @notice A daily request asks for 6 confirmations; the admin retry of it asks for 6 again.
    function test_DailyAndItsRetryUseSix() public {
        vm.expectCall(address(mockVRF), _reqData(6), 2);
        vm.expectCall(address(mockVRF), _reqData(4), 0);
        uint256 req = _dailyRequest(3);
        vm.warp(block.timestamp + 20 hours + 1);
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        assertEq(mockVRF.lastRequestId(), req + 1, "retry re-issued");
    }

    /// @notice A mid-day request asks for 4 confirmations; the admin retry of it asks for 4 again.
    function test_MiddayAndItsRetryUseFour() public {
        vm.expectCall(address(mockVRF), _reqData(4), 2);
        vm.expectCall(address(mockVRF), _reqData(6), 0);
        uint256 req = _middayRequest();
        vm.warp(block.timestamp + 20 hours + 1);
        assertEq(game.currentDayView(), 2, "still the same day");
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        assertEq(mockVRF.lastRequestId(), req + 1, "retry re-issued");
    }

    /// @notice A coordinator rotation re-issues an unanswered daily request on the new
    ///         coordinator with 6 confirmations.
    function test_RotationReissuesDailyWithSix() public {
        _dailyRequest(3);
        MockVRFCoordinator next = new MockVRFCoordinator();
        uint256 sub = next.createSubscription();
        bytes32 key = keccak256("rotated-key");
        bytes memory six = abi.encodeWithSelector(
            REQ_SEL, VRFRandomWordsRequest(key, sub, 6, 300_000, 1, "")
        );
        bytes memory four = abi.encodeWithSelector(
            REQ_SEL, VRFRandomWordsRequest(key, sub, 4, 300_000, 1, "")
        );
        vm.expectCall(address(next), six, 1);
        vm.expectCall(address(next), four, 0);
        vm.prank(ContractAddresses.ADMIN);
        game.updateVrfCoordinatorAndSub(address(next), sub, key);
        assertEq(next.lastRequestId(), 1, "re-issued on the new coordinator");
    }

    /// @notice A coordinator rotation re-issues an unanswered mid-day request on the new
    ///         coordinator with 4 confirmations.
    function test_RotationReissuesMiddayWithFour() public {
        _middayRequest();
        MockVRFCoordinator next = new MockVRFCoordinator();
        uint256 sub = next.createSubscription();
        bytes32 key = keccak256("rotated-key-midday");
        vm.expectCall(address(next), abi.encodeWithSelector(REQ_SEL, VRFRandomWordsRequest(key, sub, 4, 300_000, 1, "")), 1);
        vm.expectCall(address(next), abi.encodeWithSelector(REQ_SEL, VRFRandomWordsRequest(key, sub, 6, 300_000, 1, "")), 0);
        vm.prank(ContractAddresses.ADMIN);
        game.updateVrfCoordinatorAndSub(address(next), sub, key);
        assertEq(next.lastRequestId(), 1, "re-issued on the new coordinator");
    }

    /// @notice A game over decided with VRF alive requests its terminal word with 6
    ///         confirmations.
    function test_TerminalRequestUsesSix() public {
        _warpTo(60, 1 hours);
        assertTrue(game.livenessTriggered(), "fixture: the ending fires");
        uint256 req0 = mockVRF.lastRequestId();
        vm.expectCall(address(mockVRF), _reqData(6), 1);
        vm.expectCall(address(mockVRF), _reqData(4), 0);
        for (uint256 i; i < 60 && mockVRF.lastRequestId() == req0; ++i) {
            try game.mineFlip(0) {} catch { break; }
        }
        assertEq(mockVRF.lastRequestId(), req0 + 1, "terminal request out");
    }
}

/// @title RngVectorCompactBoxFreeze -- compact lootbox orders resolve from the word their buffer
///        was sealed for, whatever players do afterwards
/// @notice Three 85-bit entries share a storage word; each entry's seed root is
///         hash4(domain, word, buffer, position), so two entries in one word never share a root
///         and an entry's outcome is fixed once its buffer is sealed. For both window shapes (the
///         mid-day request, and the daily request that also binds a Degenesis cohort) the sealed
///         buffer's words are byte-identical through the window, and every box-outcome event
///         emitted while the sealed buffer drains (LootBoxOpened, BoxSpin, rewards, passes, DGNRS,
///         whale-pass jackpot) is identical, in order, to an undisturbed run, while new buys from
///         the same wallets go to the other buffer. The daily shape also compares cohort 1.
contract RngVectorCompactBoxFreeze is DegenesisHarness {
    bytes32 internal constant SIG_OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant SIG_SPIN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    bytes32 internal constant SIG_REWARD = keccak256("LootBoxReward(uint32,uint8,uint256,uint256)");
    bytes32 internal constant SIG_PASSES = keccak256("LootBoxCrapsPasses(uint32,uint32,uint32,uint24)");
    bytes32 internal constant SIG_WHALE = keccak256("LootBoxWhalePassJackpot(uint32,uint256,uint24,uint24,uint24,uint24)");
    bytes32 internal constant SIG_DGNRS = keccak256("LootBoxDgnrsBatch(uint32,uint256,uint256)");

    address[6] internal buyers;

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 6; ++i) {
            buyers[i] = _player(string.concat("cb-", vm.toString(i)));
            _earnCredit(buyers[i], 2 ether);
        }
        _driveDay(2, 0);
        mockVRF.fundSubscription(1, 100e18);
    }

    function _boxBuy(address p, uint256 amount) internal {
        vm.prank(p);
        game.purchase{value: amount}(0, 0, BoxOrderLib.boCustom(amount), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _readBuffer() internal view returns (uint48) {
        uint256 flags = uint16(uint256(vm.load(address(game), bytes32(uint256(0)))) >> (GameSlots.RNG_FLAGS_AND_NUDGES_OFFSET * 8));
        return uint48(((flags >> 12) & 1) ^ 1);
    }

    function _readCount() internal view returns (uint256) {
        return uint32(uint256(vm.load(address(game), bytes32(GameSlots.BOX_READ_COUNT))) >> (GameSlots.BOX_READ_COUNT_OFFSET * 8));
    }

    function _boxCursor() internal view returns (uint256) {
        return uint48(uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR))) >> (GameSlots.BOX_CURSOR_OFFSET * 8));
    }

    function _queueWord(uint48 buf, uint256 i) internal view returns (uint256) {
        bytes32 base = keccak256(abi.encode(bytes32(GameSlots.BOX_QUEUE + uint256(buf))));
        return uint256(vm.load(address(game), bytes32(uint256(base) + i)));
    }

    function _bufferDigest(uint48 buf, uint256 count) internal view returns (bytes32 h) {
        for (uint256 i; i < (count + 2) / 3; ++i) h = keccak256(abi.encode(h, _queueWord(buf, i)));
    }

    function _isOutcome(Vm.Log memory l) internal view returns (bool) {
        if (l.emitter != address(game) || l.topics.length == 0) return false;
        bytes32 t = l.topics[0];
        return t == SIG_OPENED || t == SIG_SPIN || t == SIG_REWARD || t == SIG_PASSES || t == SIG_WHALE || t == SIG_DGNRS;
    }

    /// @dev Hashes of every box-outcome log, in order.
    function _outcomes(Vm.Log[] memory logs) internal view returns (bytes32[] memory out) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) if (_isOutcome(logs[i])) ++n;
        out = new bytes32[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (_isOutcome(logs[i])) out[n++] = keccak256(abi.encode(logs[i].topics, logs[i].data));
        }
    }

    /// @dev Settlement events (LootBoxOpened or BoxSpin) of wallet `id`, hashed, in order.
    function _settlementsOf(Vm.Log[] memory logs, uint32 id) internal view returns (bytes32[] memory out) {
        uint256 n;
        for (uint256 pass; pass < 2; ++pass) {
            uint256 k;
            for (uint256 i; i < logs.length; ++i) {
                Vm.Log memory l = logs[i];
                if (l.emitter != address(game) || l.topics.length < 2 || uint32(uint256(l.topics[1])) != id) continue;
                if (l.topics[0] != SIG_OPENED && l.topics[0] != SIG_SPIN) continue;
                if (pass == 1) out[k] = keccak256(l.data);
                ++k;
            }
            if (pass == 0) {
                n = k;
                out = new bytes32[](n);
            }
        }
    }

    /// @dev New boxes from the sealed entries' own wallets and others, and Degenesis buys.
    function _disturb(uint256 salt) internal {
        for (uint256 i; i < 6; ++i) {
            vm.warp(block.timestamp + 3 minutes);
            _boxBuy(buyers[i], 0.013 ether + ((i + salt) % 50) * 0.001 ether);
            if (game.currentDayView() <= 8) _buy(buyers[(i + 1) % 6], 0.0101 ether + i * 0.0001 ether);
        }
    }

    /// @dev Answer with `word`, then mine on small budgets until the sealed buffer has drained,
    ///      optionally disturbing between steps; no other request is answered meanwhile. A new
    ///      seal (a request made once the drain completes) ends the span too. Returns its logs.
    function _drainSealed(uint256 word, uint48 buf, uint256 count, bool disturb) internal returns (Vm.Log[] memory) {
        vm.recordLogs();
        lastFulfilledReq = 0;
        assertTrue(_fulfillPending(word), "answer");
        for (uint256 i; i < 600 && _readBuffer() == buf && _readCount() == count && _boxCursor() < count; ++i) {
            if (disturb && i % 3 == 0) _disturb(i + 2);
            vm.prank(makeAddr(string.concat("cb-miner-", vm.toString(i))));
            try game.mineFlip{gas: 2_500_000}(0) {} catch {
                try game.mineFlip{gas: 10_000_000}(0) {} catch {
                    try game.mineFlip(0) {} catch { break; }
                }
            }
        }
        assertTrue(_readCount() != count || _readBuffer() != buf || _boxCursor() == count, "sealed buffer drained");
        return vm.getRecordedLogs();
    }

    function _concat(Res[] memory a, Res[] memory b) internal pure returns (Res[] memory out) {
        out = new Res[](a.length + b.length);
        for (uint256 i; i < a.length; ++i) out[i] = a[i];
        for (uint256 i; i < b.length; ++i) out[a.length + i] = b[i];
    }

    function _windowDifferential(bool midday) internal {
        // Seven one-box orders: positions share storage words three to a word.
        uint256[7] memory amounts = [uint256(0.5 ether), 0.5 ether, 0.5 ether, 0.25 ether, 0.75 ether, 0.5 ether, 1 ether];
        for (uint256 i; i < 7; ++i) _boxBuy(buyers[i % 6], amounts[i]);
        if (!midday) {
            _buy(buyers[0], 0.05 ether);
            _buy(buyers[1], 0.07 ether);
        }

        uint256 req0 = mockVRF.lastRequestId();
        if (midday) {
            for (uint256 i; i < 40 && mockVRF.lastRequestId() == req0; ++i) {
                try game.mineFlip(0) {} catch { break; }
            }
            assertFalse(game.rngLocked(), "mid-day window");
        } else {
            _warpTo(3, 1 hours);
            _stepToRequest();
            game.mineFlip(0);
            assertTrue(game.rngLocked(), "daily window");
            assertEq(_activeDay(), 3, "the daily request also bound cohort 1");
        }
        assertEq(mockVRF.lastRequestId(), req0 + 1, "request out");
        lastFulfilledReq = mockVRF.lastRequestId();
        uint48 buf = _readBuffer();
        uint256 count = _readCount();
        assertGe(count, 7, "the seven orders are sealed");
        bytes32 digest = _bufferDigest(buf, count);
        uint256 word = uint256(keccak256(abi.encode("cb-word", midday)));

        uint256 snap = vm.snapshotState();
        Vm.Log[] memory drained = _drainSealed(word, buf, count, false);
        bytes32[] memory plain = _outcomes(drained);
        vm.recordLogs();
        _drive(word);
        Res[] memory plainDeg = _concat(_resolved(drained), _resolved(vm.getRecordedLogs()));
        vm.revertToStateAndDelete(snap);

        _disturb(1);
        assertEq(_readBuffer(), buf, "read buffer unchanged");
        assertEq(_readCount(), count, "read count unchanged");
        assertEq(_bufferDigest(buf, count), digest, "sealed entries byte-identical through the window");
        drained = _drainSealed(word, buf, count, true);
        bytes32[] memory mixed = _outcomes(drained);
        vm.recordLogs();
        _drive(word);
        Res[] memory mixedDeg = _concat(_resolved(drained), _resolved(vm.getRecordedLogs()));

        assertGe(plain.length, 7, "every sealed order settled");
        assertEq(plain.length, mixed.length, "same outcome-event count");
        for (uint256 i; i < plain.length; ++i) assertEq(plain[i], mixed[i], "same box outcome, in order");
        if (!midday) {
            assertEq(plainDeg.length, 2, "cohort 1 resolved");
            assertEq(mixedDeg.length, plainDeg.length, "cohort 1 resolved once");
            for (uint256 i; i < plainDeg.length; ++i) _assertRes(mixedDeg[i], plainDeg[i], "cohort 1");
        }
    }

    /// @notice Mid-day window: boxes sealed by the mid-day request open identically whatever
    ///         is bought (by the same wallets or others) while it is out and while they open.
    function test_MiddayWindowSealedBoxesUnchanged() public {
        _windowDifferential(true);
    }

    /// @notice Daily window on Degenesis day 2: the day-3 request seals day 2's boxes and binds
    ///         cohort 1 to the same word; later buys change no sealed box and no cohort-1 order.
    function test_DailyWindowSealedBoxesUnchanged() public {
        _windowDifferential(false);
    }

    /// @notice Three equal one-box orders from one wallet, in one storage word, settle on three
    ///         distinct seeds: the root mixes each entry's position.
    function test_EqualNeighboursInOneWordDiffer() public {
        for (uint256 i; i < 3; ++i) _boxBuy(buyers[0], 0.5 ether);
        uint256 req0 = mockVRF.lastRequestId();
        for (uint256 i; i < 40 && mockVRF.lastRequestId() == req0; ++i) {
            try game.mineFlip(0) {} catch { break; }
        }
        assertEq(mockVRF.lastRequestId(), req0 + 1, "request out");
        vm.recordLogs();
        _drive(uint256(keccak256("cb-neighbours")));
        bytes32[] memory got = _settlementsOf(vm.getRecordedLogs(), game.walletIdOf(buyers[0]));
        assertEq(got.length, 3, "three neighbours settled, one event each");
        assertTrue(got[0] != got[1] || got[1] != got[2], "neighbours draw distinct seeds");
    }
}
