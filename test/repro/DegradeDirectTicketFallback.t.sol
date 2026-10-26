// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test, Vm} from "forge-std/Test.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {DegenerusGamePassModule} from "../../contracts/modules/DegenerusGamePassModule.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Jackpot-phase harness at level 41 with a live level-42 target buffer, so the coin+tickets
///      stage latches the direct lane; the drift setters then break one of its preconditions.
contract DegradeDirectFallbackHarness is DegenerusGameJackpotModule, BucketSeed {
    function seed(uint256 word, uint256 tickets) external {
        level = 41;
        jackpotPhaseFlag = true;
        rngLockedFlag = true;
        _seedWallet(address(1));
        uint8[4] memory traits = JackpotBucketLib.getRandomTraits(word);
        traits[3] = GoldSixLib.daily(traits[3], word);
        dailyIdx = 101;
        rngRequestDay = 101;
        dailyFoilDraw[rngRequestDay & 1] = _packFoilDraw(
            JackpotBucketLib.packWinningTraits(traits), level, rngRequestDay, word);
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(41, traits[q], 64, uint160(0x10000 + uint256(q) * 0x10000));
        }
        _setTicketBufferLevel(42);
        dailyJackpotCoinTicketsPending = true;
        dailyTicketBudgetsPacked = 1 | ((tickets * 4) << 8);
    }

    /// @dev Thanos scaling declared for the target level after the latch.
    function driftSnap() external { snapShift = 1; }

    function state() external view returns (uint8 quadrant, uint16 winner, uint32 round, bool direct, uint8 counter, bool pending) {
        return (jackpotWork.quadrant, jackpotWork.winner, jackpotWork.directTicketRound,
            jackpotWork.directTickets, jackpotCounter, dailyJackpotCoinTicketsPending);
    }

    function queued() external view returns (uint256) { return _ticketQueueLength(_tqWriteKey(42)); }
}

/// @notice Daily-spine degrade (DAILY-4c): when a direct-lane precondition fails after the lane was
///         latched, the coin+tickets stage falls back to the queued path from the same cursor
///         instead of reverting `E()` on every call. Groups the direct lane completed are not drawn
///         again: direct batch winners plus queued winners equal the draw's winner count exactly.
/// @dev Tickets equal the 96-winner floor, so each winner takes one ticket and a direct group is a
///      single round; the partial-group skip therefore never arms here and is a code-read item.
///      Run: forge test --match-path test/repro/DegradeDirectTicketFallback.t.sol -vv
contract DegradeDirectTicketFallbackTest is Test {
    bytes32 private constant WIN = keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 private constant BATCH =
        keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    uint256 private constant WORD = 0xAC4DE45EDBEEF;
    uint256 private constant TICKETS = 96;
    // Independent assertion of the protocol limits: the direct round bound plus 65k per eight-winner
    // sampler group, the ticket tail and the 2k engine margin.
    uint256 private constant EXPECTED_DIRECT_ROUND = 4_500_000;
    uint256 private constant EXPECTED_DIRECT_GROUP = 65_000;
    uint256 private constant EXPECTED_TICKET_TAIL = 260_000;
    uint256 private constant ENGINE_MARGIN = 2_000;
    // The call's own setup (750k) and plan (120k) spend comes off the allowance before a round is admitted.
    uint256 private constant SETUP_HEADROOM = 1_000_000;
    // Admits any 32-winner direct round (four sampler groups) from a fresh call, so every step makes progress.
    uint256 private constant ANY_ROUND_ALLOWANCE =
        EXPECTED_DIRECT_ROUND + 4 * EXPECTED_DIRECT_GROUP + EXPECTED_TICKET_TAIL + ENGINE_MARGIN + SETUP_HEADROOM;
    DegradeDirectFallbackHarness private h;

    function setUp() public {
        vm.setNonce(address(this), vm.getNonce(address(this)) + 1024);
        vm.warp(30 days);
        h = new DegradeDirectFallbackHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGamePassModule()).code);
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGamePassModule()).code);
    }

    function _count(Vm.Log[] memory logs) private pure returns (uint256 direct, uint256 queued) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == WIN) {
                ++queued;
            } else if (logs[i].topics[0] == BATCH) {
                (, uint8 n,,,) = abi.decode(logs[i].data, (uint16, uint8, uint32, uint256[4], uint256[4]));
                direct += n;
            }
        }
    }

    function _step(uint256 allowance) private returns (MineFlipGas.Result memory r, uint256 direct, uint256 queued) {
        vm.recordLogs();
        r = h.runDailyJackpotTickets{gas: allowance + 400_000}(WORD, allowance);
        (direct, queued) = _count(vm.getRecordedLogs());
    }

    function _finish() private returns (uint256 direct, uint256 queued, uint256 calls) {
        bool done;
        while (!done && calls < 100) {
            (MineFlipGas.Result memory r, uint256 d, uint256 q) = _step(ANY_ROUND_ALLOWANCE);
            direct += d;
            queued += q;
            done = r.done;
            ++calls;
        }
        assertTrue(done, "the stage completes");
    }

    /// @dev One direct group is materialized, then Thanos scaling for the target level appears:
    ///      the rest of the draw is delivered by the queued path from the same cursor.
    function test_SnapDriftFallsBackAfterDirectGroups() public {
        h.seed(WORD, TICKETS);
        // Admits one direct group (4.5M round bound + sampler groups + tail), not a second: the
        // first group's actual spend leaves less than another round bound.
        (MineFlipGas.Result memory first, uint256 direct, uint256 queued) = _step(ANY_ROUND_ALLOWANCE);
        assertFalse(first.done, "harness: the first call must leave work for the fallback");
        assertEq(queued, 0, "harness: the first call ran the direct lane only");
        (uint8 quadrant, uint16 winner, uint32 round, bool wasDirect,,) = h.state();
        assertTrue(wasDirect, "harness: the direct lane is latched");
        assertEq(round, 0, "single-round groups leave no partial group");
        emit log_named_uint("direct winners paid by the first call", direct);
        emit log_named_uint("cursor quadrant", quadrant);
        emit log_named_uint("cursor winner", winner);
        assertGt(direct, 0, "harness: the first call materialized a direct group");
        assertTrue(direct != 0 || (quadrant == 0 && winner == 0), "cursor and batch events agree");

        h.driftSnap();
        (uint256 directRest, uint256 queuedRest,) = _finish();
        assertEq(directRest, 0, "no further direct batches after the fallback");
        assertEq(direct + queuedRest, TICKETS, "every winner position paid exactly once");
        assertGt(h.queued(), 0, "queued winners entered the target queue");
        assertLe(h.queued(), queuedRest, "a queue member per distinct queued winner at most");
        (,,, bool direct2, uint8 counter, bool pending) = h.state();
        assertFalse(direct2, "direct flag cleared by the fallback");
        assertEq(counter, 1, "the day completes as a counted jackpot day");
        assertFalse(pending, "coin+tickets latch cleared");
    }

    /// @dev Reachable shape: nothing drifts and the whole draw stays on the direct lane.
    function test_ReachableDirectDrawUnchanged() public {
        h.seed(WORD, TICKETS);
        (uint256 direct, uint256 queued,) = _finish();
        assertEq(queued, 0, "no queued winners on the direct lane");
        assertEq(direct, TICKETS, "direct lane pays every winner position");
        assertEq(h.queued(), 0, "nothing enters the queue");
    }
}
