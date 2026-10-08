// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {BafStageHost, BafBracketFixture} from "../helpers/BafStageHost.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

/// @title BafStagedGameOver — the terminal latch with BAF awards still in flight.
/// @notice A real bracket's kind-7 record is paid one group, then the deadman fires. The terminal
///         path must proceed; the latch releases exactly the uncredited reservation
///         (`jackpotWork.paid`) from claimablePool and deletes the record; credited winners keep
///         their balances and whale halves; the ending distributes the released ETH; no award
///         group runs after the latch.
contract BafStagedGameOverTest is BafBracketFixture {
    uint24 private constant LVL = 20;
    uint256 private constant WORD = uint256(keccak256("baf-staged-game-over")) | 1;
    uint256 private constant POOL = 150 ether;
    uint256 private constant ONE_GROUP =
        GasBounds.BAF_AWARD_GROUP + GasBounds.BAF_AWARD_TAIL + GasBounds.DAILY_PHASE_TAIL + 150_000;
    bytes32 private constant DRAINED_SIG = keccak256("GameOverDrained(uint24,uint256,uint256)");

    uint256 private reserve;

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 1_000 ether);
        vm.warp(block.timestamp + 40 days);
        _hostAt(LVL, WORD, true);
        host.seedPools(10 ether, 200 ether, 50 ether, LVL - 1, 40 ether);
        host.seedFrozen(true, 0, 2 ether);
        _seedBracket(LVL);
        _armDepositDraw();
        reserve = _bafReserve(POOL);
        _armBaf(LVL, POOL, 0);
        vm.deal(address(game), address(game).balance + 260 ether + reserve);
    }

    function test_LatchReleasesTheUncreditedReservationAndTheEndingDistributesIt() public {
        uint256 word = host.dailyWord();
        // Group 0 is two trait-bucket pairs: the views at the stage start name its winners.
        address[] memory first = _groupWinners(LVL, word, 0, POOL);
        vm.recordLogs();
        host.daily{gas: 30_000_000}(ONE_GROUP);
        Vm.Log[] memory groupLogs = vm.getRecordedLogs();
        BafStageHost.WorkView memory w = host.workView();
        assertEq(w.kind, 7, "record mid-way");
        assertEq(w.winner, BAF_GROUP, "one group paid");
        uint256 inFlight = w.paid;
        uint256 groupCredit = _creditedIn(groupLogs);
        assertEq(inFlight + groupCredit, reserve, "paid is the reservation less the group's credits");
        assertGt(inFlight, 0, "uncredited reservation remains");
        uint256 poolBefore = host.liabilities();
        uint256[] memory credits = new uint256[](first.length);
        uint256[] memory halves = new uint256[](first.length);
        uint256 creditedSum;
        for (uint256 k; k < first.length; ++k) {
            assertTrue(first[k] != address(0), "the first group's slots are filled");
            credits[k] = host.claimableOf(first[k]);
            halves[k] = host.whalePassesOf(first[k]);
            bool seen;
            for (uint256 j; j < k; ++j) if (first[j] == first[k]) seen = true;
            if (!seen) creditedSum += credits[k];
        }
        assertEq(creditedSum, groupCredit, "the paid winners hold the group's credits");

        // Deadman: the daily phase stops at its liveness guard before any award group.
        vm.warp(block.timestamp + 31 days);
        assertTrue(host.livenessView(), "deadman fired");
        vm.expectRevert(bytes4(keccak256("E()")));
        host.daily(9_000_000);

        // The latch: one terminal step releases exactly the uncredited reservation.
        vm.recordLogs();
        host.terminal(9_000_000);
        _assertNoBafAward(vm.getRecordedLogs());
        BafStageHost.WorkView memory cleared = host.workView();
        assertEq(cleared.kind, 0, "record deleted at the latch");
        assertEq(cleared.paid, 0);
        assertEq(cleared.traits, 0);
        assertEq(cleared.winner, 0);
        assertEq(host.liabilities(), poolBefore - inFlight, "claimablePool releases exactly work.paid");
        vm.expectRevert(bytes4(keccak256("E()")));
        host.daily(9_000_000);

        // Run the ending out on the production engine.
        bool drained;
        uint256 available;
        uint256 reservedAtDrain;
        uint256 fundsAtDrain;
        for (uint256 i; i < 120 && !game.gameOver(); ++i) {
            _answer();
            vm.recordLogs();
            try game.mineFlip(0) {} catch {}
            Vm.Log[] memory logs = vm.getRecordedLogs();
            _assertNoBafAward(logs);
            for (uint256 j; j < logs.length; ++j) {
                if (logs[j].emitter != address(game) || logs[j].topics.length == 0 || logs[j].topics[0] != DRAINED_SIG) continue;
                (, available, reservedAtDrain) = abi.decode(logs[j].data, (uint24, uint256, uint256));
                fundsAtDrain = address(game).balance + mockStETH.balanceOf(address(game));
                drained = true;
            }
        }
        assertTrue(game.gameOver(), "the terminal path ends the game");
        assertTrue(drained, "the ending distributed a pot");
        assertEq(reservedAtDrain, poolBefore - inFlight, "the ending reserves only credited liabilities");
        assertEq(available + reservedAtDrain, fundsAtDrain, "the released ETH is part of the distributable total");

        // Paid winners keep every credit and whale half (terminal payouts can only add).
        for (uint256 k; k < first.length; ++k) {
            assertGe(host.claimableOf(first[k]), credits[k], "credited winners keep their balance");
            assertGe(host.whalePassesOf(first[k]), halves[k], "queued whale halves stay");
        }
    }

    function _answer() private {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (!done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("terminal", id))));
    }

    /// @dev No award-stage marker and no BAF award event (the BAF sentinel trait or a BAF
    ///      whale-pass source) after the latch.
    function _assertNoBafAward(Vm.Log[] memory logs) private view {
        for (uint256 j; j < logs.length; ++j) {
            if (logs[j].emitter != address(game) || logs[j].topics.length == 0) continue;
            bytes32 sig = logs[j].topics[0];
            if (sig == ADVANCE_SIG) {
                (uint8 stage,) = abi.decode(logs[j].data, (uint8, uint24));
                assertTrue(stage != STAGE_BAF, "no BAF award group after the latch");
            } else if (sig == ETH_SIG || sig == TICKET_SIG) {
                assertTrue(uint256(logs[j].topics[3]) != BAF_TRAIT_SENTINEL, "no BAF award after the latch");
            } else if (sig == WHALE_SIG) {
                (, uint8 source) = abi.decode(logs[j].data, (uint256, uint8));
                assertTrue(source != WHALE_SRC_BAF_DIRECT && source != WHALE_SRC_AWARD_TICKETS,
                    "no BAF whale award after the latch");
            }
        }
    }
}
