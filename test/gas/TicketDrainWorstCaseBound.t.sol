// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Exposes the drain's pricing constants.
contract DrainPrices is DegenerusGameStorage {
    function unit() external pure returns (uint256) { return UNIT_GAS_BOUND; }
    function budget() external pure returns (uint256) { return WRITES_BUDGET_SAFE; }
    function roundUnits() external pure returns (uint256) { return ROUND_UNITS; }
    function splitUnits() external pure returns (uint256) { return ROUND_SPLIT_UNITS; }
    function joinUnits() external pure returns (uint256) { return SEAT_JOIN_UNITS; }
    function seats() external pure returns (uint256) { return ROUND_SEATS; }
}

/// @title TicketDrainWorstCaseBound — a drain call's gas is bounded by its write budget
/// @notice Reserve the worst, charge the actual. A step starts only if its worst case fits the
///         remaining budget; once done it charges every write it made at a price at or above
///         the opcode cost. So a call never spends more than WRITES_BUDGET_SAFE units, and its
///         gas is at most budget x UNIT_GAS_BOUND plus fixed overhead. This suite derives the
///         per-write prices and the reserves from EVM costs (every write fresh, every read cold)
///         and pins the ceiling. Lowering a price or raising the budget past the ceiling fails here.
contract TicketDrainWorstCaseBound is Test {
    uint256 internal constant COLD_SLOAD = 2_100;
    uint256 internal constant FRESH_SSTORE = 20_000 + 2_100; // zero -> nonzero, cold slot
    uint256 internal constant DIRTY_SSTORE = 2_900 + 2_100; // nonzero -> nonzero, cold slot
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;
    uint256 internal constant CEILING = 11_000_000;
    /// @dev Everything outside charged steps: entry reads, cursor/marker writes, a queue
    ///      release, the nested delegatecall, the foil deferral writes, the return path
    ///      (~120k) and the crank's own pre-drain logic in the same transaction, with headroom.
    uint256 internal constant FIXED_OVERHEAD = 1_000_000;

    DrainPrices internal p;

    function setUp() public {
        p = new DrainPrices();
    }

    function _singleAppend() internal pure returns (uint256) {
        return 2 * COLD_SLOAD + 2 * FRESH_SSTORE; // read+write length, read+write tail
    }

    function _wordAppend() internal pure returns (uint256) {
        return 2 * COLD_SLOAD + 3 * FRESH_SSTORE; // ... plus the next word
    }

    // ---- per-write prices (what a step charges once done) --------------------------------

    function test_FreshWritePrice_ThreeUnits() public view {
        assertGe(3 * p.unit(), FRESH_SSTORE + COLD_SLOAD, "a fresh write plus its read exceeds three units");
    }

    function test_DirtyWritePrice_OneUnit() public view {
        assertGe(1 * p.unit(), DIRTY_SSTORE + COLD_SLOAD, "a dirty write plus its read exceeds one unit");
    }

    function test_FixedCharges() public view {
        assertGe(1 * p.unit(), COLD_SLOAD + DIRTY_SSTORE, "a seat exit exceeds one unit");
        assertGe(1 * p.unit(), 2 * COLD_SLOAD + DIRTY_SSTORE, "a dust skip exceeds one unit");
        assertGe(p.joinUnits() * p.unit(), 2 * COLD_SLOAD + 2 * DIRTY_SSTORE, "a seat join exceeds its units");
        assertGe(4 * p.unit(), FRESH_SSTORE + DIRTY_SSTORE, "a drain-time registration exceeds four units");
        assertGe(3 * p.unit(), 375 + 375 + 8 * 352 + 20_000, "a round's event and loops exceed three units");
        assertGe(1 * p.unit(), 16 * 400, "sixteen occurrences of LCG and scratch work exceed one unit");
        assertGe(3 * p.unit(), 30_000, "a foil pack's record and cursor bookkeeping exceeds three units");
    }

    // ---- reserves (what must fit before a step starts) -----------------------------------

    function test_RoundReserve_CoversFullySplitRound() public {
        uint256 worst = 4 * (p.seats() * _singleAppend()) + p.seats() * (COLD_SLOAD + DIRTY_SSTORE) + 25_000;
        emit log_named_uint("fully_split_round_worst", worst);
        assertGe((p.roundUnits() + 4 * p.splitUnits()) * p.unit(), worst, "round reserve below a fully split round");
        assertGe(p.roundUnits() * p.unit(), 4 * _wordAppend() + p.seats() * (COLD_SLOAD + DIRTY_SSTORE) + 25_000, "unsplit round below its units");
    }

    function test_EntryReserve_CoversTake() public view {
        // Reserved at 6 units per occurrence for the first 256, 1 beyond.
        assertGe(6 * p.unit(), _singleAppend() + 400, "six units below a fresh-bucket occurrence");
        assertGe(1 * p.unit(), FRESH_SSTORE / 8 + 400, "one unit below an amortised occurrence");
    }

    function test_FoilReserve_CoversPack() public view {
        assertGe(83 * p.unit(), 16 * _singleAppend() + 30_000, "83 units below a foil pack");
    }

    // ---- the ceiling ---------------------------------------------------------------------

    function test_Budget_UnderCeilingAtUnitBound() public {
        uint256 bound = p.budget() * p.unit() + FIXED_OVERHEAD;
        emit log_named_uint("drain_call_gas_bound", bound);
        assertLe(bound, CEILING, "budget x unit plus fixed overhead exceeds the 11M ceiling");
        assertLt(bound, EIP7825_TX_GAS_CAP - 2_000_000, "and must leave 2M under the cap");
    }
}
