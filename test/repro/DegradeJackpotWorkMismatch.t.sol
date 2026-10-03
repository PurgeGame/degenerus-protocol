// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Module harness: seeds a jackpotWork of one kind/level and reads the accounting back.
contract DegradeWorkMismatchHarness is DegenerusGameJackpotModule {
    function seedWork(uint8 kind, uint24 lvl, uint8 quadrant, uint16 winner) external {
        level = 6;
        jackpotWork.kind = kind;
        jackpotWork.lvl = lvl;
        jackpotWork.quadrant = quadrant;
        jackpotWork.winner = winner;
        jackpotWork.budget = 3 ether;
        jackpotWork.paid = 1 ether;
    }

    function seedTicketFields(uint64 earlyBird, uint64 daily, bool pending) external {
        dailyTicketBudgetsPacked = (uint256(earlyBird) << 144) | (uint256(daily) << 8);
        dailyJackpotCoinTicketsPending = pending;
    }

    function work() external view returns (JackpotWork memory) { return jackpotWork; }

    function accounting()
        external view returns (uint256 current, uint256 next, uint256 future, uint256 claimable)
    {
        (uint128 n, uint128 f) = _getPrizePools();
        return (_getCurrentPrizePool(), n, f, claimablePool);
    }

    function fields() external view returns (uint64 earlyBird, uint64 daily, bool pending, uint8 counter) {
        return (uint64(dailyTicketBudgetsPacked >> 144), uint64(dailyTicketBudgetsPacked >> 8),
            dailyJackpotCoinTicketsPending, jackpotCounter);
    }
}

/// @notice Daily-spine degrade (DAILY-4a/b): a jackpotWork of another kind or level is retired and
///         the requested draw is priced fresh instead of reverting `JackpotWorkMismatch` on every
///         call. The seeded work is unreachable (each kind is created only inside the stage that
///         re-selects it), so it is written straight into the harness's storage.
/// @dev Pools are empty, so the restarted draws price to zero and complete in one call; the
///      assertions are about control flow, retired fields and untouched accounting.
///      Run: forge test --match-path test/repro/DegradeJackpotWorkMismatch.t.sol -vv
contract DegradeJackpotWorkMismatchTest is Test {
    uint256 private constant WORD = 0xD15EA5E;
    uint256 private constant ALLOWANCE = 30_000_000;
    DegradeWorkMismatchHarness private h;

    function setUp() public {
        vm.warp(30 days);
        h = new DegradeWorkMismatchHarness();
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
    }

    function _assertNoAccounting() private {
        (uint256 current, uint256 next, uint256 future, uint256 claimable) = h.accounting();
        assertEq(current, 0, "current pool untouched");
        assertEq(next, 0, "next pool untouched");
        assertEq(future, 0, "future pool untouched");
        assertEq(claimable, 0, "no liability created");
    }

    /// @dev Stale jackpot-phase ETH work meets a purchase-phase request at another level.
    function test_EthWorkOfAnotherKindAndLevelIsRestarted() public {
        h.seedWork(2, 5, 2, 7);
        MineFlipGas.Result memory r = h.runDailyJackpot(false, 7, WORD, ALLOWANCE);
        assertTrue(r.progressed, "fresh pricing counts as progress");
        assertTrue(r.done, "an empty-pool draw completes in one call");
        assertEq(h.work().kind, 0, "stale work retired, fresh work completed");
        _assertNoAccounting();
        (,, bool pending,) = h.fields();
        assertFalse(pending, "a purchase-phase draw sets no coin+tickets latch");
    }

    /// @dev Stale purchase-phase ETH work meets a jackpot-phase request.
    function test_EthWorkOfAnotherKindIsRestartedInJackpotPhase() public {
        h.seedWork(1, 7, 1, 3);
        MineFlipGas.Result memory r = h.runDailyJackpot(true, 6, WORD, ALLOWANCE);
        assertTrue(r.done);
        assertEq(h.work().kind, 0);
        _assertNoAccounting();
        (,, bool pending,) = h.fields();
        assertTrue(pending, "the fresh jackpot-phase draw sets its own coin+tickets latch");
    }

    /// @dev Same kind and level: the in-flight cursor is resumed, never re-priced.
    function test_MatchingWorkResumesFromCursor() public {
        h.seedWork(1, 7, 4, 0);
        MineFlipGas.Result memory r = h.runDailyJackpot(false, 7, WORD, ALLOWANCE);
        assertTrue(r.done, "cursor already at the end: completes without pricing");
        assertFalse(r.progressed, "nothing was drawn or priced");
        assertEq(h.work().kind, 0);
        _assertNoAccounting();
    }

    /// @dev Stale early-bird ticket work meets the coin+tickets stage: the early-bird field is
    ///      retired with the work, the coin+tickets draw runs and completes.
    function test_StaleEarlyBirdWorkRetiredByCoinTicketsStage() public {
        h.seedWork(5, 7, 1, 3);
        h.seedTicketFields(40, 80, true);
        MineFlipGas.Result memory r = h.runDailyJackpotTickets(WORD, ALLOWANCE);
        assertTrue(r.done, "coin+tickets completes on empty buckets");
        (uint64 earlyBird, uint64 daily, bool pending, uint8 counter) = h.fields();
        assertEq(earlyBird, 0, "stale early-bird field retired so that draw never restarts");
        assertEq(daily, 0, "coin+tickets consumed its own field");
        assertFalse(pending, "coin+tickets latch cleared by its own completion");
        assertEq(counter, 1, "the completed coin+tickets day is counted");
        assertEq(h.work().kind, 0);
        _assertNoAccounting();
    }

    /// @dev Stale coin+tickets work meets the early-bird stage: its latch and field are retired
    ///      without counting a jackpot day; the early-bird draw runs and completes.
    function test_StaleCoinTicketsWorkRetiredByEarlyBirdStage() public {
        h.seedWork(6, 6, 2, 9);
        h.seedTicketFields(40, 80, true);
        MineFlipGas.Result memory r = h.runEarlyBirdTickets(WORD, ALLOWANCE);
        assertTrue(r.done, "early bird completes on empty buckets");
        (uint64 earlyBird, uint64 daily, bool pending, uint8 counter) = h.fields();
        assertEq(earlyBird, 0, "early bird consumed its own field");
        assertEq(daily, 0, "stale coin+tickets field retired");
        assertFalse(pending, "stale coin+tickets latch retired");
        assertEq(counter, 0, "a retired coin+tickets day is not counted");
        assertEq(h.work().kind, 0);
        _assertNoAccounting();
    }
}
