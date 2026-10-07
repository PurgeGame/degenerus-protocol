// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract DrainPrices is DegenerusGameTicketModule {
    function roundMax() external pure returns (uint256) { return ROUND_MAX; }
    function entryMax() external pure returns (uint256) { return ENTRY_MAX; }
    function seatMax() external pure returns (uint256) { return SEAT_MAX; }
    function reloadMax() external pure returns (uint256) { return RELOAD_MAX; }
    function tail() external pure returns (uint256) { return TAIL; }
}

/// @notice Analytic cold-write floors for each indivisible checkpoint operation.
/// @dev These assertions support admission bounds; production execution suites
///      separately exercise complete calls and measured gas. Each indivisible
///      operation and its complete checkpoint tail must fit the caller's remaining
///      gas, and the 10M target below is the per-chunk ceiling for every admitted step.
contract TicketDrainWorstCaseBound is Test {
    uint256 private constant COLD_SLOAD = 2_100;
    // Stores on a slot already read in the same call (warm).
    uint256 private constant ZERO_TO_NONZERO = 20_000;
    uint256 private constant WARM_RESET = 2_900;
    uint256 private constant STEP_GAS_TARGET = 10_000_000;
    DrainPrices private p;
    function setUp() public { p = new DrainPrices(); }
    /// @dev The heaviest single-occurrence append: a seven-lane header completes a fresh
    ///      word (cold header and word reads, fresh word store, header rewrite).
    function flushAppend() private pure returns (uint256) { return 2 * COLD_SLOAD + ZERO_TO_NONZERO + WARM_RESET; }

    function test_RoundReserveCoversAllRareSplitsAndDebtWrites() public view {
        // 32 split appends with their loop work, eight seat exits, seed, reveals and compaction.
        uint256 bound = 32 * (flushAppend() + 1_000) + 8 * (WARM_RESET + 500) + 60_000;
        assertGe(p.roundMax(), bound);
    }
    function test_EntryReserveCoversColdBucketAndGenerator() public view {
        assertGe(p.entryMax(), flushAppend() + 2_000);
    }
    function test_SeatAndReloadReservesCoverColdRegistryAndRemainder() public view {
        // Queue word, registry element and length, pending word; a skip or win writes it.
        uint256 seat = 4 * COLD_SLOAD + WARM_RESET + 5_000;
        assertGe(p.seatMax(), seat);
        // Reloaded seats owe entries, so they read but never write.
        assertGe(p.reloadMax(), 8 * (3 * COLD_SLOAD + 3_000) + 2 * COLD_SLOAD + 10_000);
    }
    function test_FlushTailCoversEightDebtsAndAllControlWrites() public view {
        // Eight changed seat words, a fresh seat word, the control slot, queue release, return.
        uint256 flush = 8 * (WARM_RESET + 500) + ZERO_TO_NONZERO + 2 * WARM_RESET + COLD_SLOAD + 10_000;
        assertGe(p.tail(), flush);
    }
    function test_CanonicalTicketStepsFitSizingTargetIncludingCheckpoint() public pure {
        uint256 tail = GasBounds.TICKET_TAIL + MineFlipGas.CHECK_RESERVE;
        assertLe(GasBounds.TICKET_SELECT_MAX + tail, STEP_GAS_TARGET);
        assertLe(GasBounds.TICKET_SEAT_MAX + tail, STEP_GAS_TARGET);
        assertLe(GasBounds.TICKET_RELOAD_MAX + tail, STEP_GAS_TARGET);
        assertLe(GasBounds.TICKET_ROUND_MAX + tail, STEP_GAS_TARGET);
        assertLe(GasBounds.TICKET_FOIL_CALL_MAX + tail, STEP_GAS_TARGET);
        // One aligned group and its possible final fractional entry must remain
        // admissible, and the largest solo run any budget can admit stays within 10M.
        assertLe(GasBounds.TICKET_SOLO_BASE + 17 * GasBounds.TICKET_ENTRY_MAX + tail,
            STEP_GAS_TARGET);
        uint256 maxEntries = GasBounds.TICKET_SOLO_MAX_ENTRIES;
        assertEq(maxEntries % 16, 0, "solo cap preserves aligned group seeds");
        assertGe(maxEntries, 17);
        assertLe(GasBounds.TICKET_SOLO_BASE + maxEntries * GasBounds.TICKET_ENTRY_MAX + tail,
            STEP_GAS_TARGET);
    }



}
