// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

contract CohortRecyclingHarness is DegenerusGameStorage {
    function seal() external {
        if (!_lootboxReadComplete()) revert E();
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
        rngWordCurrent = RNG_WORD_WAITING;
    }
    function ready(uint256 value) external { rngWordCurrent = value; _setRngSessionPublished(true); _tryCompleteRng(); }
    function word(uint48 buffer) external view returns(uint256) { return _lootboxWord(buffer); }
    function readBuffer() external view returns(uint48) { return _rngReadBuffer(); }
    function writeBuffer() external view returns(uint48) { return _rngWriteBuffer(); }
    function craps(uint48 buffer, bool pending) external {
        if (buffer > 1) revert E();
        uint256 mask = uint256(1) << (LR_CRAPS_PENDING_SHIFT + buffer);
        lootboxRngPacked = pending ? lootboxRngPacked | mask : lootboxRngPacked & ~mask;
        if (pending && buffer == _rngReadBuffer()) _setRngComplete(false);
        else _tryCompleteRng();
    }
    function queueBox(address player, uint256 order_) external {
        lootboxOrder[_rngWriteBuffer()][player] = order_;
        boxPlayers[_rngWriteBuffer()].push(player);
    }
    function queueBet(uint256 bet) external { degeneretteQueue[_rngWriteBuffer()].push(bet); }
    function processed(address player) external { lootboxOrder[_rngReadBuffer()][player] |= BOX_PROCESSED; }
    function order(uint48 buffer, address player) external view returns(uint256) { return _boxOrder(buffer, player); }
    function counts(uint48 buffer) external view returns(uint256, uint256) { return(boxPlayers[buffer].length, degeneretteQueue[buffer].length); }
    function frontier(bool done) external { humanReadComplete = done; if (!done) _setRngComplete(false); _tryCompleteRng(); }
    function settleBets() external { degeneretteCursor = uint32(degeneretteQueue[_rngReadBuffer()].length); _tryCompleteRng(); }
    function tickets(bool done) external { ticketsFullyProcessed = done; if (!done) _setRngComplete(false); _tryCompleteRng(); }
    function mid(uint8 flag) external { _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, flag); if (flag != 0) _setRngComplete(false); _tryCompleteRng(); }
    function locked(bool on) external { rngLockedFlag = on; if (on) _setRngComplete(false); _tryCompleteRng(); }
    function complete() external view returns(bool) { return _lootboxReadComplete(); }
    function window(bool on) external { _setDecWindowOpen(on); }
    function opening(bool on) external { _setDecDayOneActive(on); }
    function decimator() external view returns(bool, bool) { return (_decWindowOpen(), _decDayOneActive()); }
}

contract NoPendingCohortRedemptions {
    function redemptionSettlementPending() external pure returns (bool) { return false; }
}

contract RngCohortRecyclingTest is Test {
    CohortRecyclingHarness h;
    function setUp() public {
        h = new CohortRecyclingHarness();
        vm.etch(ContractAddresses.SDGNRS, address(new NoPendingCohortRedemptions()).code);
    }
    function _finish() private { h.ready(42); h.tickets(true); h.frontier(true); h.settleBets(); }
    function test_CompleteAtDeploymentAndClearOnReservation() public {
        assertTrue(h.complete()); assertEq(h.writeBuffer(), 0);
        h.seal(); assertFalse(h.complete()); assertEq(h.readBuffer(), 0); assertEq(h.writeBuffer(), 1);
    }
    function test_DailyLockMustReleaseBeforeCompletion() public {
        h.seal(); h.locked(true); _finish(); assertFalse(h.complete());
        h.locked(false); assertTrue(h.complete());
    }
    function test_WriteSideOrdersAndCrapsDoNotReopenCompletedRead() public {
        h.seal(); _finish(); assertTrue(h.complete());
        h.queueBox(address(20), 123); h.queueBet(77); h.craps(h.writeBuffer(), true);
        assertTrue(h.complete()); h.seal(); assertFalse(h.complete());
        _finish(); assertFalse(h.complete(), "write commitments became the new read");
        h.craps(h.readBuffer(), false); assertTrue(h.complete());
    }
    function testFuzz_LastConsumerSetsCompletion(uint256 seed) public {
        h.seal(); h.mid(2); h.craps(h.readBuffer(), true); h.ready(11);
        uint8[4] memory order = [uint8(0), 1, 2, 3];
        for (uint256 i = 4; i > 1; --i) {
            uint256 j = seed % i; (order[i - 1], order[j]) = (order[j], order[i - 1]);
            seed = uint256(keccak256(abi.encode(seed)));
        }
        for (uint256 i; i < 4; ++i) {
            if (order[i] == 0) h.tickets(true);
            else if (order[i] == 1) h.mid(0);
            else if (order[i] == 2) h.frontier(true);
            else h.craps(h.readBuffer(), false);
            assertEq(h.complete(), i == 3, "every consumer is required in every completion order");
        }
    }
    function test_DecimatorFlagsRemainIndependent() public {
        h.window(true); h.opening(true); h.seal();
        (bool windowOpen, bool dayOne) = h.decimator(); assertTrue(windowOpen && dayOne);
        h.opening(false); _finish(); (windowOpen, dayOne) = h.decimator();
        assertTrue(windowOpen); assertFalse(dayOne); assertTrue(h.complete());
    }
    function test_RepeatedReuseResetsOnlyHeadersAndMasksProcessedOrders() public {
        for (uint256 i; i < 8; ++i) {
            uint48 write = h.writeBuffer();
            (uint256 boxes, uint256 bets) = h.counts(write); assertEq(boxes, 0); assertEq(bets, 0);
            address player = address(uint160(10 + (i & 1)));
            assertEq(h.order(write, player), 0);
            h.queueBox(player, i + 100); h.queueBet(i + 200);
            h.seal(); assertEq(h.readBuffer(), write); assertEq(h.word(write), 0);
            vm.expectRevert(DegenerusGameStorage.E.selector); h.seal();
            h.ready(i + 42); assertEq(h.word(write), i + 42); assertEq(h.word(write ^ 1), 0);
            h.processed(player); assertEq(h.order(write, player), 0);
            h.tickets(true); h.frontier(true);
            assertFalse(h.complete(), "human completion does not skip committed Degenerette bets");
            h.settleBets(); assertTrue(h.complete());
        }
    }
    function test_InvalidPhysicalTagsNeverAliasARealBuffer() public {
        h.seal(); _finish();
        assertEq(h.word(2), 0); assertEq(h.order(2, address(10)), 0);
        vm.expectRevert(DegenerusGameStorage.E.selector); h.craps(2, true);
    }
}

contract GameCrapsPendingMirrorTest is DeployProtocol {
    function setUp() public { _deployProtocol(); }
    function test_KeeperHintIncludesEmptyFrontierAndCrapsOnlyReadWork() public {
        RecyclingState.seedWord(address(game), 0, bytes32(uint256(11)));
        uint256 state = uint256(game.extsload(bytes32(0))) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(state));
        assertTrue(game.boxesPending(), "empty read frontier must be traversed");
        game.openBoxes(10);
        assertFalse(game.boxesPending());
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(0, true);
        assertTrue(game.boxesPending(), "Craps-only work is discoverable");
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(0, false);
        assertFalse(game.boxesPending());
        RecyclingState.seedWord(address(game), 0, bytes32(uint256(1)));
        assertFalse(game.boxesPending(), "missing word cannot be opened");
    }
    function test_OnlyPinnedCrapsCanMutateIndependentPendingBits() public {
        uint256 before = uint256(game.extsload(bytes32(uint256(33))));
        vm.expectRevert(DegenerusGameStorage.E.selector); game.setCrapsRngPending(0, true);
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(0, true);
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(1, true);
        assertEq(uint256(game.extsload(bytes32(uint256(33)))), before | (uint256(3) << 250));
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(1, false);
        assertEq(uint256(game.extsload(bytes32(uint256(33)))), before | (uint256(1) << 250));
        vm.prank(ContractAddresses.CRAPS); game.setCrapsRngPending(0, false);
        assertEq(uint256(game.extsload(bytes32(uint256(33)))), before);
        vm.prank(ContractAddresses.CRAPS); vm.expectRevert(DegenerusGameStorage.E.selector);
        game.setCrapsRngPending(2, true);
    }
}
