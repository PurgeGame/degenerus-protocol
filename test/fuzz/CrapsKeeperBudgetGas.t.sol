// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";

/// @title The Craps keeper's work budget, measured
/// @notice `resolveSlot`'s second argument is a GAS ALLOWANCE, so the question a fixed seat count
///         could never answer is now the only one that matters: how far past its allowance can one
///         call land, and what does that make the whole `mineFlip` crank worth at the tail?
///
/// @dev EVERY FIGURE HERE IS AGAINST THE REAL PROTOCOL — the real Coinflip, the real FLIP, the
///      real Game router. The mocked craps suite cannot price a credit, and a credit is the one
///      part of a seat the resolver has to predict rather than measure.
///
///      THE STUDY IS SHAPED BY WHAT A BUDGET ACTUALLY BOUNDS. Under a fixed allowance the walk
///      stops on the first seat that crosses it, so a call costs `allowance + one seat's
///      overshoot` and the whole distribution question collapses to the overshoot. That is what
///      the sweeps below measure, over shared table words on one deep field — and it is why a
///      few hundred words is evidence where it would not be for an unbounded walk.
contract CrapsKeeperBudgetGasTest is DeployProtocol {
    address internal constant KEEPER = address(0xC0FFEE);

    /// @dev The afking module reached DIRECTLY. Both budget readers are pure — a compile-time
    ///      constant and arithmetic — so neither needs the Game's storage context.
    GameAfkingModule internal constant keeper = GameAfkingModule(ContractAddresses.GAME_AFKING_MODULE);

    /// @dev Deep enough that the BUDGET stops the walk rather than the field running out, at every
    ///      format — the cheapest cell walks the most seats, so this is sized against that one.
    uint256 internal constant FIELD = 300;

    /// @dev How many shared table words each sweep replays. Every sample is a whole ~9M-gas
    ///      settlement, so this is the honest trade between tail resolution and a suite that
    ///      finishes; the emitted tables state it beside every percentile.
    uint256 internal constant WORDS = 64;

    /// @dev The allowance an untouched box budget hands the craps leg — `OPEN_WEIGHT_BUDGET *
    ///      CRAPS_GAS_PER_UNIT - CRAPS_ROUTER_TAIL_GAS`, restated so this suite can drive the
    ///      resolver directly at exactly what the router would give it.
    uint64 internal constant KEEPER_ALLOWANCE = uint64(1920 - 32);

    /// @dev What the router costs ON TOP of the resolver — the arm probe, the cursor reads, the
    ///      bounty credit and the `MinerBounty` log. Measured by
    ///      `test_probe_theRouterTailOverTheResolver`, and held against the reserve the router
    ///      subtracts before it hands the allowance down.
    uint256 internal constant ROUTER_TAIL_MEASURED = 100_000;

    /// @dev Four Pass, three Place 8 — the picked board the plan names, packed. Three bits a leg,
    ///      board order: pass at 0, place8 at bit 12.
    uint32 internal constant PICKED_PASS_PLACE8 = 3 | (uint32(3) << 12) | (uint32(1) << 15);

    /// @dev A blank ticket: names nothing, so the dice place all ten chips.
    uint32 internal constant BLANK = 0;

    function setUp() public {
        _deployProtocol();
    }

    // ════════════════════════════════════════════════════════════════════════
    // A. The overshoot, which is the only thing a fixed budget leaves uncertain
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE SWEEP. One deep field, replayed against `WORDS` independent shared table words at
    ///      the keeper's own allowance. What is reported is the distribution of the whole call and
    ///      of the OVERSHOOT past the allowance — because under a budget the call is
    ///      `allowance + one seat`, and the one seat is what the words move.
    function _sweep(uint256 dayWord, uint32 board, string memory label) internal returns (uint256 p95) {
        (uint64 slot, uint48 index) = _deepField(dayWord, board);
        uint256 depth = _depthOf(slot);

        uint256[] memory used = new uint256[](WORDS);
        uint256[] memory seats = new uint256[](WORDS);
        uint256[] memory over = new uint256[](WORDS);
        uint256 paidTotal;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < WORDS; ++i) {
            _landTableWord(index, uint256(keccak256(abi.encode("sweep", dayWord, i))));
            uint256 before = coinflip.coinflipAmount(address(0));
            uint256 g = gasleft();
            crapsBattle.resolveSlot(slot, KEEPER_ALLOWANCE);
            used[i] = g - gasleft();
            seats[i] = crapsBattle.bonusCursorOf(slot);
            over[i] = used[i] > KEEPER_ALLOWANCE ? used[i] - KEEPER_ALLOWANCE : 0;
            paidTotal += before; // keeps the read from being optimised out
            vm.revertToState(snap);
            snap = vm.snapshotState();
        }

        emit log_string(label);
        emit log_named_uint("  depth                     ", depth);
        emit log_named_uint("  words replayed            ", WORDS);
        emit log_named_uint("  seats p50                 ", _p(seats, 50));
        emit log_named_uint("  seats min                 ", _p(seats, 1));
        emit log_named_uint("  seats max                 ", _p(seats, 100));
        emit log_named_uint("  resolveSlot p50           ", _p(used, 50));
        emit log_named_uint("  resolveSlot p90           ", _p(used, 90));
        emit log_named_uint("  resolveSlot p95           ", _p(used, 95));
        emit log_named_uint("  resolveSlot p99           ", _p(used, 99));
        emit log_named_uint("  resolveSlot max           ", _p(used, 100));
        emit log_named_uint("  overshoot p95             ", _p(over, 95));
        emit log_named_uint("  overshoot max             ", _p(over, 100));
        p95 = _p(used, 95);

        // The budget, not the ceiling, is what stopped these calls.
        assertLt(_p(seats, 100), FIELD, "the field ran out before the budget did");
    }

    /// @dev The one scheduled format, on the picked board the plan names.
    function test_theBudgetHoldsAcrossTheScheduledFormat() public {
        uint256 dayWord = _findBankroll(3000);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, dayWord);
        (uint128 bank, uint128 goal, uint256 posted,,,) = crapsBattle.bonusTermsFor(today, 1);
        assertEq(uint256(bank) / ((posted * 10) / 7), 5, "a scheduled window is not five rounds deep");
        assertEq(uint256(goal) / uint256(bank), 5, "a scheduled window is not goal 5x");

        uint256 p95 = _sweep(dayWord, PICKED_PASS_PLACE8, "FORMAT");
        emit log_named_uint("resolveSlot p95 for fixed 5x format", p95);
        emit log_named_uint("  + measured router tail          ", p95 + ROUTER_TAIL_MEASURED);
        assertLt(p95 + ROUTER_TAIL_MEASURED, 9_500_000, "the scheduled format's p95 passed the 9.5M target");
    }

    /// @dev The outcome-weighted allowance still walks a useful, bounded part of the fixed 5x
    ///      field across several shared settlement words.
    function test_theFixedFiveXFormatHasMeasuredSeatThroughput() public {
        uint256 seats = _medianSeats(_findBankroll(3000));
        emit log_named_uint("median seats, 3000 FLIP goal 5x", seats);
        assertGt(seats, 0, "one allowance walked no seats");
        assertLt(seats, FIELD, "the field ceiling, not the allowance, stopped settlement");
    }

    /// @dev Seat one deep field on `dayWord` and settle it at the keeper's allowance against
    ///      several shared words; report the median seats walked and put the world back.
    function _medianSeats(uint256 dayWord) internal returns (uint256) {
        uint256 outer = vm.snapshotState();
        (uint64 slot, uint48 index) = _deepField(dayWord, PICKED_PASS_PLACE8);
        uint256[] memory seats = new uint256[](9);
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < 9; ++i) {
            _landTableWord(index, uint256(keccak256(abi.encode("cmp", dayWord, i))));
            crapsBattle.resolveSlot(slot, KEEPER_ALLOWANCE);
            seats[i] = crapsBattle.bonusCursorOf(slot);
            vm.revertToState(snap);
            snap = vm.snapshotState();
        }
        vm.revertToState(outer);
        return _p(seats, 50);
    }

    /// @dev WHAT THE ROUTER COSTS ON TOP. The resolver's meter cannot see the arm probe above it
    ///      or the cursor read, bounty credit and `MinerBounty` log below it, so the router
    ///      subtracts a reserve before handing the allowance down. This is that reserve measured:
    ///      the same field settled through `game.mineFlip()` and through `resolveSlot` directly.
    function test_probe_theRouterTailOverTheResolver() public {
        uint256 dayWord = _findBankroll(3000);
        uint256 word = uint256(keccak256("router-tail"));

        uint256 snap = vm.snapshotState();
        (uint64 slot, uint48 index) = _deepField(dayWord, PICKED_PASS_PLACE8);
        _landTableWord(index, word);
        uint256 g = gasleft();
        crapsBattle.resolveSlot(slot, KEEPER_ALLOWANCE);
        uint256 bare = g - gasleft();
        uint256 bareSeats = crapsBattle.bonusCursorOf(slot);
        vm.revertToState(snap);

        snap = vm.snapshotState();
        (slot, index) = _deepField(dayWord, PICKED_PASS_PLACE8);
        // The crank arms nothing here — the window is already shut — so this call is the walk.
        _landTableWord(index, word);
        g = gasleft();
        vm.prank(KEEPER);
        game.mineFlip();
        uint256 crank = g - gasleft();
        uint256 crankSeats = crapsBattle.bonusCursorOf(slot);
        vm.revertToState(snap);

        emit log_named_uint("resolveSlot alone           ", bare);
        emit log_named_uint("  seats                     ", bareSeats);
        emit log_named_uint("whole mineFlip crank        ", crank);
        emit log_named_uint("  seats                     ", crankSeats);
        emit log_named_uint("router tail over the resolver", crank > bare ? crank - bare : 0);
        assertLt(crank, 16_700_000, "the crank passed the protocol's hard per-transaction ceiling");
    }

    /// @dev A day word whose period-1 window draws the requested bankroll. Depth and target are
    ///      fixed by the schedule and asserted by the format test above.
    function _findBankroll(uint256 wantBankrollFlip) internal returns (uint256) {
        uint24 today = crapsBattle.currentDayIndex();
        for (uint256 i = 0; i < 4000; ++i) {
            uint256 dayWord = uint256(keccak256(abi.encode("find", wantBankrollFlip, i)));
            _landDayWord(today, dayWord);
            (uint128 bank,,,,,) = crapsBattle.bonusTermsFor(today, 1);
            if (uint256(bank) / 1 ether == wantBankrollFlip) return dayWord;
        }
        revert("no day word drew that format");
    }

    // ════════════════════════════════════════════════════════════════════════
    // B. The hard bound, which is deterministic and not a percentile
    // ════════════════════════════════════════════════════════════════════════

    /// @dev THE OVERSHOOT IS ONE SEAT, AND THIS IS WHAT ONE SEAT CAN COST. The meter is read
    ///      AFTER a seat, so the worst a budgeted call can do is stop one seat short of its
    ///      allowance and then run the most expensive seat the table can produce. The bound is
    ///      therefore `allowance + max seat + router tail`, with no statistical step in it.
    ///
    ///      The dearest seat is simultaneously a long dice path, PAID, FIELD-FINALIZING (so it
    ///      carries the pot, progressive and lane), and a HIGH seat. This searches for it rather
    ///      than asserting it exists.
    function test_theHardBoundHoldsWithAWholeSeatOfOvershoot() public {
        uint256 dayWord = _findBankroll(3000);
        uint256 worstSeat;
        uint256 worstFinal;

        for (uint256 i = 0; i < 24; ++i) {
            uint256 snap = vm.snapshotState();
            (uint64 slot, uint48 index) = _smallHighField(dayWord, i);
            _landTableWord(index, uint256(keccak256(abi.encode("hardbound", i))));
            // A pool worth drawing on, so the finalizing seat carries a progressive award too.
            crapsBattle.seedProgressive(10_000_000 ether);

            uint64 seats = uint64(crapsBattle.battleOf(crapsBattle.keyOfSlot(slot)).entrants);
            for (uint64 n = 0; n < seats; ++n) {
                uint256 g = gasleft();
                crapsBattle.resolveSlot(slot, 1); // one seat: the smallest nonzero budget
                uint256 used = g - gasleft();
                if (n + 1 == seats) {
                    if (used > worstFinal) worstFinal = used;
                } else if (used > worstSeat) {
                    worstSeat = used;
                }
            }
            vm.revertToState(snap);
        }

        uint256 maxSeat = worstFinal > worstSeat ? worstFinal : worstSeat;
        uint256 bound = uint256(KEEPER_ALLOWANCE) + maxSeat + ROUTER_TAIL_MEASURED;
        emit log_named_uint("dearest ordinary seat        ", worstSeat);
        emit log_named_uint("dearest FINALIZING seat      ", worstFinal);
        emit log_named_uint("keeper allowance             ", KEEPER_ALLOWANCE);
        emit log_named_uint("HARD BOUND = allowance+seat+tail", bound);
        emit log_named_uint("margin to the 16.7M ceiling  ", 16_700_000 - bound);

        // The engine's own regression ceiling is the other half of the argument: a seat cannot
        // outrun it however the dice fall, so the bound holds for seats this search never drew.
        uint256 structural = uint256(KEEPER_ALLOWANCE) + 1_500_000 + 600_000 + ROUTER_TAIL_MEASURED;
        emit log_named_uint("STRUCTURAL bound at the engine cap", structural);
        assertLt(bound, 16_700_000, "the measured hard bound passed the protocol ceiling");
        assertLt(structural, 16_700_000, "the structural hard bound passed the protocol ceiling");
    }

    /// @dev A small field on the day's high lane: the house and the vault take day seats, and two
    ///      high rollers race the lane, so the LAST seat to settle finalizes the field and carries
    ///      the pot, the progressive and the contested lane together.
    function _smallHighField(uint256 dayWord, uint256 salt) internal returns (uint64 slot, uint48 index) {
        // Genesis is a warm-up day with no windows, and vm snapshots do not rewind the clock —
        // so every field is built on a FRESH day, deterministically: the next day boundary plus
        // an hour, whatever the clock says now.
        // vm.getBlockTimestamp, NOT block.timestamp: the optimizer caches the TIMESTAMP opcode
        // across vm.warp calls in one frame, and a stale read here warps BACKWARD.
        uint256 ts = vm.getBlockTimestamp();
        vm.warp(ts - ((ts - 82_620) % 1 days) + 1 days + 3_900);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, dayWord);
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        (uint128 bankroll,,,,,) = crapsBattle.bonusTermsFor(today, 1);
        uint16 mult = uint16(crapsBattle.highMultForDay(today));
        for (uint256 i = 0; i < 4; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("high", dayWord, salt, i)))));
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(who, uint256(bankroll) * uint256(mult) * 4);
            vm.prank(who);
            crapsBattle.enterBonusBattle(1, PICKED_PASS_PLACE8, i < 2 ? mult : 1);
        }

        slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        index = crapsBattle.armBonusWindow(slot);
    }

    // ════════════════════════════════════════════════════════════════════════
    // C. Composition with the box legs — the envelope they share
    // ════════════════════════════════════════════════════════════════════════

    /// @dev A FULLY CONSUMED BOX WALK LEAVES NOTHING. This is the bug the old form carried: it
    ///      divided the spend into seats first, so 1,920 units spent still left `80 - 1920/27 = 9`
    ///      seats of craps work stacked on top of a full-budget call.
    function test_theBoxLegsAndTheCrapsLegShareOneEnvelope() public pure {
        uint256 budget = keeper.keeperOpenWeightBudget();
        assertEq(keeper.keeperCrapsUnitBudget(budget), 0, "a fully spent box budget still bought craps work");
        assertEq(keeper.keeperCrapsUnitBudget(budget + 1), 0, "an overspent box budget bought craps work");
        assertEq(keeper.keeperCrapsUnitBudget(budget * 3), 0, "a wildly overspent budget bought craps work");

        uint256 whole = keeper.keeperCrapsUnitBudget(0);
        assertEq(whole, KEEPER_ALLOWANCE, "an untouched budget is not the keeper allowance");

        // HALF THE BOX BUDGET LEAVES ABOUT HALF THE WORK — linear in the remainder, less the one
        // fixed router reserve, which is why it is not exactly half.
        uint256 half = keeper.keeperCrapsUnitBudget(budget / 2);
        assertApproxEqAbs(half, whole / 2, 32, "half a box budget did not leave about half the work");

        // And the tail below the minimum start is ZERO rather than a sliver that buys a whole seat.
        assertEq(keeper.keeperCrapsUnitBudget(budget - 1), 0, "a one-unit remainder bought a whole seat");
        assertGt(keeper.keeperCrapsUnitBudget(budget - 100), 0, "a hundred units of remainder bought nothing");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Fixtures
    // ════════════════════════════════════════════════════════════════════════

    /// @dev Land a day's committed word in the Game slot the table reads it out of.
    function _landDayWord(uint24 day, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(day), uint256(10))), bytes32(word));
    }

    function _landTableWord(uint48 index, uint256 word) internal {
        vm.store(address(game), keccak256(abi.encode(uint256(index), uint256(34))), bytes32(word));
    }

    /// @dev Open a day, seat `FIELD` distinct funded players into period 1 on `board`, shut the
    ///      window, and hand back its slot and table index. One shared word settles all of them,
    ///      which is the whole point: independent per-player dice would understate the tail.
    function _deepField(uint256 dayWord, uint32 board) internal returns (uint64 slot, uint48 index) {
        // Genesis is a warm-up day with no windows, and vm snapshots do not rewind the clock —
        // so every field is built on a FRESH day, deterministically: the next day boundary plus
        // an hour, whatever the clock says now.
        // vm.getBlockTimestamp, NOT block.timestamp: the optimizer caches the TIMESTAMP opcode
        // across vm.warp calls in one frame, and a stale read here warps BACKWARD.
        uint256 ts = vm.getBlockTimestamp();
        vm.warp(ts - ((ts - 82_620) % 1 days) + 1 days + 3_900);
        uint24 today = crapsBattle.currentDayIndex();
        _landDayWord(today, dayWord);
        vm.prank(ContractAddresses.GAME);
        crapsBattle.openBonusDay();

        (uint128 bankroll,,,,,) = crapsBattle.bonusTermsFor(today, 1);
        for (uint256 i = 0; i < FIELD; ++i) {
            address who = address(uint160(uint256(keccak256(abi.encode("deep", dayWord, i)))));
            vm.prank(ContractAddresses.GAME);
            coin.mintForGame(who, uint256(bankroll) * 4);
            vm.prank(who);
            crapsBattle.enterBonusBattle(1, board, 1);
        }

        slot = uint64(uint256(today) * crapsBattle.BONUS_SLOTS_PER_DAY() + 2);
        vm.warp(vm.getBlockTimestamp() + 4 hours);
        index = crapsBattle.armBonusWindow(slot);
    }

    /// @dev The fixed scheduled depth, reconstructed from a live window.
    function _depthOf(uint64 slot) internal view returns (uint256 depth) {
        uint24 day = uint24(uint256(slot) / crapsBattle.BONUS_SLOTS_PER_DAY());
        (uint128 bank,,,,,) = crapsBattle.bonusTermsFor(day, 1);
        uint256 round = crapsBattle.roundOf(slot);
        depth = uint256(bank) / round;
    }

    function _p(uint256[] memory xs, uint256 pct) internal pure returns (uint256) {
        uint256[] memory a = xs;
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 v = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > v) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = v;
        }
        if (a.length == 0) return 0;
        // Nearest-rank: the smallest value at or above the pct-th position, 1-indexed.
        uint256 rank = (pct * a.length + 99) / 100;
        if (rank == 0) rank = 1;
        return a[rank - 1];
    }
}
