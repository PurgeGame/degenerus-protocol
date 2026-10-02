// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract DrainPrices is DegenerusGameTicketModule {
    function recordAtQueueIndex(uint24 lvl, uint256 index) external view returns (uint256) {
        return _entryRecord(lvl, _tqPositionAt(ticketQueue[_ticketQueueStorageKey(lvl)], index));
    }
    function roundMax() external pure returns (uint256) { return ROUND_MAX; }
    function entryMax() external pure returns (uint256) { return ENTRY_MAX; }
    function seatMax() external pure returns (uint256) { return SEAT_MAX; }
    function reloadMax() external pure returns (uint256) { return RELOAD_MAX; }
    function tail() external pure returns (uint256) { return TAIL; }
}

/// @notice Analytic cold-write floors for each indivisible checkpoint operation.
/// @dev These assertions support admission bounds; production execution suites
///      separately exercise complete calls and measured gas. There is no weighted
///      write budget or fixed chunk cap: each indivisible operation and its
///      complete checkpoint tail must fit the caller's remaining gas. The 10M
///      sizing target below is a benchmark guideline, not a runtime limit.
contract TicketDrainWorstCaseBound is Test {
    uint256 private constant COLD_SLOAD = 2_100;
    uint256 private constant FRESH_SSTORE = 22_100;
    uint256 private constant DIRTY_SSTORE = 5_000;
    uint256 private constant STEP_GAS_TARGET = 10_000_000;
    DrainPrices private p;
    function setUp() public { p = new DrainPrices(); }
    function singleton() private pure returns (uint256) { return 2 * COLD_SLOAD + 2 * FRESH_SSTORE; }

    function test_RoundReserveCoversAllRareSplitsAndDebtWrites() public view {
        uint256 bound = 32 * singleton() + 8 * (COLD_SLOAD + DIRTY_SSTORE) + 40_000;
        assertGe(p.roundMax(), bound);
    }
    function test_EntryReserveCoversColdBucketAndGenerator() public view {
        assertGe(p.entryMax(), singleton() + 1_000);
    }
    function test_SeatAndReloadReservesCoverColdRegistryAndRemainder() public view {
        uint256 seat = 4 * COLD_SLOAD + FRESH_SSTORE + 12_000;
        assertGe(p.seatMax(), seat);
        assertGe(p.reloadMax(), 8 * (4 * COLD_SLOAD + DIRTY_SSTORE + 12_000));
    }
    function test_FlushTailCoversEightDebtsAndAllControlWrites() public view {
        uint256 flush = 8 * DIRTY_SSTORE + 3 * FRESH_SSTORE + 2 * DIRTY_SSTORE + 25_000;
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
        // admissible at the sizing target. Larger budgets can size larger chunks.
        assertLe(GasBounds.TICKET_SOLO_BASE + 17 * GasBounds.TICKET_ENTRY_MAX + tail,
            STEP_GAS_TARGET);
        uint256 maxEntries = (STEP_GAS_TARGET - tail - GasBounds.TICKET_SOLO_BASE)
            / GasBounds.TICKET_ENTRY_MAX;
        assertGe(maxEntries, 17);
        assertLe(GasBounds.TICKET_SOLO_BASE + maxEntries * GasBounds.TICKET_ENTRY_MAX + tail,
            STEP_GAS_TARGET);
    }

    function test_PositionLookupUsesGlobalIdentityAndPendingWithoutWalletMap() public {
        uint24 lvl = 7;
        uint256 queueBase = uint256(keccak256(abi.encode(keccak256(abi.encode(uint256(lvl), uint256(12))))));
        uint256 ownerBase = uint256(keccak256(abi.encode(uint256(67))));
        uint32 id = 0x01000002;
        bytes32 queueSlot = bytes32(queueBase + 1);
        bytes32 ownerSlot = bytes32(ownerBase + id - 1);
        bytes32 pendingSlot = keccak256(abi.encode(uint256(id), keccak256(abi.encode(uint256(lvl), uint256(79)))));
        vm.store(address(p), bytes32(uint256(67)), bytes32(uint256(id)));
        vm.store(address(p), queueSlot, bytes32(uint256(id) << 32));
        vm.store(address(p), ownerSlot, bytes32(uint256(uint160(address(0xBEEF)))));
        vm.store(address(p), pendingSlot, bytes32((uint256(1) << 255) | (uint256(lvl) << 126)
            | (uint256(1) << 41) | (uint256(4) << 8)));
        uint256 record = uint160(address(0xBEEF)) | (uint256((uint80(id) << 48) | (uint80(4) << 8)) << 160);
        vm.record();
        assertEq(p.recordAtQueueIndex(lvl, 9), record);
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(p));
        assertEq(reads.length, 4, "queue lane, shared count, identity and owed; no wallet-map lookup");
        for (uint256 i; i < reads.length; ++i) {
            assertTrue(reads[i] == queueSlot || reads[i] == bytes32(uint256(67))
                || reads[i] == ownerSlot || reads[i] == pendingSlot);
        }
        assertEq(writes.length, 0);
    }

}
