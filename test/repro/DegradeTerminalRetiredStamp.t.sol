// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev Etch overlay: seeds a caught-up past-deadline ending at level 10 whose terminal cohort
///      (level 11) holds every trait, then re-stamps that cohort's parity buffer with a higher
///      level the way a later materialization would, so the terminal level reads as retired.
contract RetiredStampSeeder is DegenerusGame, BucketSeed {
    function seedEnding(address holder) external {
        uint24 day = _simulatedDayIndex();
        level = 10;
        purchaseStartDay = day - 31; // the deadline passed yesterday
        dailyIdx = day - 1; // caught up: the deadline starts the ending today
        levelPrizePool[10] = 1000 ether;
        ticketsFullyProcessed = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        for (uint256 t; t < 256; ++t) _seedBucket(11, uint8(t), holder, t == 253 ? 1 : 4); // one gold six
    }

    function retireBuffer(uint24 lvl) external {
        _setTicketBufferLevel(lvl + 2);
    }

    function endingState() external view returns (uint256 dead, uint256 paid, uint256 swept, uint256 liability) {
        return (
            _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK),
            _goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK),
            _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK),
            claimablePool
        );
    }
}

/// @notice A terminal level whose parity buffer carries a higher stamp holds no cohort. The
///         ending must still complete: the normal payout settles every quadrant unpaid (the
///         share waits for the final sweep, exactly like an empty bucket with no deity) and the
///         deterministic tally counts no created tickets. Live jackpot paths keep the guard.
contract DegradeTerminalRetiredStampTest is DeployProtocol {
    uint256 private constant WORD = 0x987654321;
    address private constant HOLDER = address(0x715E7);
    bytes32 private constant ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");

    bytes private realCode;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 500 days);
        realCode = address(game).code;
    }

    function _fixture(bytes memory data) private {
        vm.etch(address(game), type(RetiredStampSeeder).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        vm.etch(address(game), realCode);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
    }

    function _endingState() private returns (uint256 dead, uint256 paid, uint256 swept, uint256 liability) {
        vm.etch(address(game), type(RetiredStampSeeder).runtimeCode);
        (dead, paid, swept, liability) = RetiredStampSeeder(payable(address(game))).endingState();
        vm.etch(address(game), realCode);
    }

    /// @dev Latch, request, fulfil and apply the terminal word; the payout runs on a later call.
    function _reachPayout() private {
        _fixture(abi.encodeCall(RetiredStampSeeder.seedEnding, (HOLDER)));
        vm.deal(address(game), 100 ether);
        assertTrue(game.livenessTriggered(), "caught up past the deadline");
        game.mineFlip(0); // latches the cohort level and requests the terminal word
        uint256 requestId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(requestId, WORD);
        game.mineFlip(0); // applies the word in its own transaction
        assertFalse(game.gameOver(), "applying the word does not pay out");
    }

    function _finishTerminal() private {
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.mineFlip(0);
        assertTrue(game.gameOver(), "terminal payout completed");
    }

    function _ethWins(Vm.Log[] memory logs) private pure returns (uint256 wins) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == ETH_WIN) ++wins;
        }
    }

    function test_ControlPayoutReachesTheSeededCohort() public {
        _reachPayout();
        vm.recordLogs();
        _finishTerminal();
        assertGt(_ethWins(vm.getRecordedLogs()), 0, "a readable cohort draws winners");
        assertGt(game.claimableWinningsOf(HOLDER), 0, "the cohort's holder is paid");
    }

    function test_RetiredTerminalBufferPaysNobodyAndTheSweepTakesTheShare() public {
        _reachPayout();
        _fixture(abi.encodeCall(RetiredStampSeeder.retireBuffer, (11)));
        vm.expectCall(
            address(game), abi.encodeWithSelector(game.runTerminalJackpotWork.selector, 100 ether, uint24(11), WORD)
        );
        vm.recordLogs();
        _finishTerminal();
        assertEq(_ethWins(vm.getRecordedLogs()), 0, "no quadrant pays from a retired buffer");
        (uint256 dead, uint256 paid,, uint256 liability) = _endingState();
        assertEq(dead, 0, "the normal ending stays normal");
        assertEq(paid, 1, "payout marked complete");
        assertEq(game.claimableWinningsOf(HOLDER), 0, "retired cohort receives nothing");
        assertEq(liability, 0, "no cohort was credited");
        assertEq(address(game).balance, 100 ether, "nothing left the game at the payout");
        vm.expectRevert();
        game.mineFlip(0); // idle until the sweep opens: nothing pays twice

        vm.warp(block.timestamp + 30 days);
        game.mineFlip(0);
        (,, uint256 swept,) = _endingState();
        assertEq(swept, 1, "final sweep ran");
        assertEq(address(game).balance, 0, "the unpaid quadrant shares left with the sweep");
    }

    function test_RetiredTerminalBufferDeadTallyCountsNoCreatedTickets() public {
        uint24 lvl = 5000; // purchase phase: the terminal ticket level is lvl + 1
        uint24 tlvl = lvl + 1;
        address alice = makeAddr("alice");
        address dave = makeAddr("dave");
        vm.deal(address(game), 100 ether);

        vm.etch(address(game), type(DeadVrfSeeder).runtimeCode);
        DeadVrfSeeder s = DeadVrfSeeder(payable(address(game)));
        s.seedDeadStall(lvl);
        s.seedCreated(tlvl, 3, alice, 3);
        uint32 davePos = s.seedQueued(tlvl, false, dave, 4, 50);
        vm.etch(address(game), realCode);
        _fixture(abi.encodeCall(RetiredStampSeeder.retireBuffer, (tlvl)));

        assertTrue(game.livenessTriggered(), "request unanswered 15 days");
        for (uint256 i; i < 20 && !game.gameOver(); ++i) game.mineFlip(0);
        assertTrue(game.gameOver(), "dead ending reached game over");

        vm.etch(address(game), type(DeadVrfSeeder).runtimeCode);
        (uint256 pot, uint256 total, uint256 created, uint256 uncreated, uint256 traits,) = s.deadState();
        vm.etch(address(game), realCode);
        assertEq(pot, 100 ether, "the whole balance is the pot");
        assertEq(created, 0, "a retired buffer holds no created tickets");
        assertEq(traits, 0);
        assertEq(uncreated, 450, "4.5 queued entries");
        assertEq(total, 450, "the pot divides over the queued weight alone");

        uint256[] memory refs = new uint256[](1);
        refs[0] = (uint256(1) << 248) | (uint256(tlvl | (uint24(1) << 23)) << 32) | davePos;
        game.claimDeadVrf(game.walletIdOf(dave), refs);
        assertEq(game.claimableWinningsOf(dave), pot, "the queued holder claims the tallied weight");

        refs[0] = uint256(3) << 64; // alice's created ticket: the bucket is unreadable
        vm.expectRevert(DegenerusGameStorage.E.selector);
        game.claimDeadVrf(_fixtureId(alice), refs);
        assertEq(game.claimableWinningsOf(alice), 0);
    }
}
