// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

// =============================================================================
// MintModuleDivergenceAcrossSplit.t.sol -- TST-03 (D-TST03-01..03)
// -----------------------------------------------------------------------------
// Caller gas may select WHICH checkpoint a ticket drain stops at, never an
// OUTCOME. The ticket module materializes an owner's owed entries in solo runs
// that stop only on 16-aligned offsets (`_solo`, capped at
// TICKET_SOLO_MAX_ENTRIES per run) and seeds every aligned group of sixteen from
// an immutable (stream, group) identity, so the traits written to
// `lvlTraitEntry[lvl][0..255]` must be byte-identical however the work is split.
//
// Cross-path oracle (D-TST03-02): from ONE seeded pre-state (snapshot), Path A
// drains the cohort contiguously in a single ample-gas worker call; after
// reverting to the snapshot, Path B drives the same worker with bounded gas so
// every call admits only a short aligned prefix and resumes from the persisted
// `ticketSoloOffset` checkpoint. Path B asserts it really split (several calls,
// each stopping on an advancing 16-aligned offset with owed conserved). The
// per-player trait-id occurrence digest, read from storage via vm.load, must
// match across the two paths.
//
// Host: the ticket worker `runTicketWork` (the one mineFlip's Tickets stage
// delegatecalls) is called directly on the deployed TicketModule, so its own
// storage (identical DegenerusGameStorage layout) hosts the queue, owed lanes and
// trait buffers; the Game's storage is not perturbed. No contracts/*.sol is mutated.
// =============================================================================

import {TicketQueueStorage} from "./helpers/TicketQueueStorage.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDegenerusGameTicketModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract MintModuleDivergenceAcrossSplitTest is DeployProtocol {
    // -------------------------------------------------------------------------
    // Storage-slot constants (DegenerusGameStorage; identical layout in all
    // modules; re-derived from scripts/layout/golden/DegenerusGame.json)
    // -------------------------------------------------------------------------

    /// @dev lvlTraitEntry — slot 8; the parity buffer base is keccak256(lvl & 1 . 8).
    uint256 private constant SLOT_TRAIT_BURN_TICKET = 8;

    /// @dev packed slot 14: ticketCursor (uint32) offset 0; ticketLevel (uint24) offset 4;
    ///      ticketSoloOffset (uint32) offset 16.
    uint256 private constant SLOT_TICKET_CURSOR_LEVEL = 14;
    uint256 private constant SOLO_OFFSET_SHIFT = 128;

    /// @dev Permanent ticketOwners array — slot 67; bucket lanes hold zero-based global IDs.
    uint256 private constant SLOT_TICKET_OWNERS = 67;

    /// @dev TICKET_SLOT_BIT mirror. With ticketWriteSlot=false (default),
    ///      _tqReadKey(lvl) returns lvl | TICKET_SLOT_BIT.
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev Live 3-arg TraitsGenerated signature: one event per solo run, carrying the run's
    ///      start offset in the low 32 bits of baseKey. Used only to read the checkpoint
    ///      trajectory; the equality oracle itself is storage-diff.
    bytes32 internal constant TOPIC_TRAITS_GENERATED =
        keccak256("TraitsGenerated(address,uint256,uint32)");

    // -------------------------------------------------------------------------
    // Scenario constants
    // -------------------------------------------------------------------------

    /// @dev Deterministic anchor owed value (D-TST03-03): two contiguous solo runs
    ///      (160 + 140) against many short bounded-gas runs.
    uint32 private constant ANCHOR_OWED = 300;

    /// @dev Boundary-fuzz range (D-TST03-01). [293, 492] spans contiguous trajectories of
    ///      two (<= 320), three (<= 480) and four 160-entry solo runs, so the contiguous
    ///      path itself crosses every run-boundary shape the split path is compared with.
    uint32 private constant BOUNDARY_OWED_FLOOR = 293;
    uint32 private constant BOUNDARY_OWED_CEIL = 492;

    /// @dev Target level (1 keeps slot computation cheap).
    uint24 private constant ANCHOR_LVL = 1;

    /// @dev Bounded per-call gas for the split path. The base admits one 16-entry aligned
    ///      run (TICKET_SOLO_BASE + 16 * TICKET_ENTRY_MAX + TICKET_TAIL ~= 0.68M plus the
    ///      call overhead); larger steps admit longer first runs, and the shrinking
    ///      remainder of each call admits shorter aligned runs after it.
    uint256 private constant SPLIT_GAS_BASE = 1_600_000;
    uint256 private constant SPLIT_GAS_STEP = 500_000;
    uint256 private constant SPLIT_MAX_CALLS = 200;

    /// @dev Entropy word seeded as the published read-buffer word.
    uint256 private constant DETERMINISTIC_ENTROPY =
        uint256(keccak256("336-05-tst-03-deterministic-anchor-entropy"));

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
    }

    // =========================================================================
    // Storage-direct seeding + digest helpers (test-side; no contract mutation)
    // =========================================================================

    /// @dev Storage slot of the array length of `lvlTraitEntry[lvl][traitId]`'s header.
    function _slotTraitBurnLen(uint24 lvl, uint8 traitId) private pure returns (bytes32) {
        bytes32 base = keccak256(abi.encode(uint256(lvl & 1), SLOT_TRAIT_BURN_TICKET));
        return bytes32(uint256(base) + uint256(traitId));
    }

    /// @dev Data root slot for the packed lane words at `lvlTraitEntry[lvl][traitId]`.
    function _slotTraitBurnData(uint24 lvl, uint8 traitId) private pure returns (bytes32) {
        return keccak256(abi.encode(_slotTraitBurnLen(lvl, traitId)));
    }

    /// @dev Decode a header-tail bucket lane and resolve its permanent wallet identity.
    function _laneOwner(address host, uint24 lvl, uint8 traitId, uint256 i) private view returns (address) {
        uint256 header = uint256(vm.load(host, _slotTraitBurnLen(lvl, traitId)));
        uint256 len = uint24(header);
        uint256 word = i / 8 == len / 8 ? header >> 32
            : uint256(vm.load(host, bytes32(uint256(_slotTraitBurnData(lvl, traitId)) + i / 8)));
        uint256 lane = (word >> (32 * (i & 7))) & 0xffffffff;
        bytes32 ownersData = keccak256(abi.encode(SLOT_TICKET_OWNERS));
        return address(uint160(uint256(vm.load(host, bytes32(uint256(ownersData) + lane)))));
    }

    /// @dev Single-player queue owing `owed` entries at level `lvl` on the read key.
    function _seedSinglePlayerQueue(
        address host,
        uint24 lvl,
        address player,
        uint32 owed
    ) private {
        uint24 rk = lvl | TICKET_SLOT_BIT; // _tqReadKey with ticketWriteSlot=false (default)
        TicketQueueStorage.seed(host, rk, lvl, player, uint80(owed) << 8);
        // No drain in flight: cursor, level marker, seats and solo offset all zero.
        vm.store(host, bytes32(SLOT_TICKET_CURSOR_LEVEL), bytes32(0));
    }

    /// @dev Publish `entropy` as the current read-buffer word the drain consumes.
    function _seedEntropy(address host, uint256 entropy) private {
        RecyclingState.seedWord(host, uint48(0), bytes32(entropy));
    }

    function _soloOffset(address host) private view returns (uint32) {
        return uint32(uint256(vm.load(host, bytes32(SLOT_TICKET_CURSOR_LEVEL))) >> SOLO_OFFSET_SHIFT);
    }

    /// @dev One `runTicketWork` call on the host, its allowance the gas it is sent;
    ///      `gasLimit == 0` forwards all gas.
    function _callBatch(address host, uint24 lvl, uint256 gasLimit)
        private returns (bool finished, bool didWork)
    {
        bytes memory callData = abi.encodeWithSelector(
            IDegenerusGameTicketModule.runTicketWork.selector, lvl, gasLimit == 0 ? gasleft() : gasLimit
        );
        (bool ok, bytes memory data) = gasLimit == 0 ? host.call(callData) : host.call{gas: gasLimit}(callData);
        require(ok, "TST-03: runTicketWork reverted");
        MineFlipGas.Result memory r = abi.decode(data, (MineFlipGas.Result));
        (finished, didWork) = (r.done, r.progressed);
    }

    /// @dev keccak digest of the player's per-traitId occurrence counts across all 256 trait
    ///      buckets at `lvlTraitEntry[lvl][0..255]`, plus the player's total occurrences.
    ///      Insertion-order invariant within a bucket; equal digests mean the same traits.
    function _digestTraitBurnTicketForPlayer(
        address host,
        uint24 lvl,
        address player
    ) private view returns (bytes32 digest, uint256 total) {
        uint32[256] memory counts;
        for (uint16 traitId = 0; traitId < 256; ++traitId) {
            uint256 len = uint24(uint256(vm.load(host, _slotTraitBurnLen(lvl, uint8(traitId)))));
            if (len == 0) continue;
            uint32 c;
            for (uint256 i = 0; i < len; ++i) {
                if (_laneOwner(host, lvl, uint8(traitId), i) == player) {
                    unchecked { ++c; }
                }
            }
            counts[traitId] = c;
            total += c;
        }
        digest = keccak256(abi.encode(counts));
    }

    // =========================================================================
    // Path-A and Path-B drivers (cross-path equality per D-TST03-02)
    // =========================================================================

    /// @dev Path A: one worker call with ample gas runs every admitted solo run to completion.
    function _runPathA_Contiguous(address host, uint24 lvl, address player)
        private returns (bytes32 digest, uint256 totalTraits)
    {
        (bool finished,) = _callBatch(host, lvl, 0);
        assertTrue(finished, "TST-03: one ample-gas call drains the whole cohort");
        (digest, totalTraits) = _digestTraitBurnTicketForPlayer(host, lvl, player);
    }

    /// @dev Path B: the same pre-state driven with bounded gas. Every unfinished call must stop
    ///      on an advancing 16-aligned solo checkpoint that conserves the owed balance.
    function _runPathB_BoundedSplit(address host, uint24 lvl, address player, uint32 owed, uint256 schedule)
        private returns (bytes32 digest, uint256 totalTraits, uint256 calls)
    {
        uint24 rk = lvl | TICKET_SLOT_BIT;
        uint32 lastOffset;
        bool finished;
        while (!finished) {
            uint256 gasLimit = SPLIT_GAS_BASE + ((schedule + calls) % 4) * SPLIT_GAS_STEP;
            bool didWork;
            (finished, didWork) = _callBatch(host, lvl, gasLimit);
            ++calls;
            require(calls <= SPLIT_MAX_CALLS, "TST-03: split drive did not finish");
            assertTrue(finished || didWork, "TST-03: every bounded call advances a checkpoint");
            if (!finished) {
                uint32 offset = _soloOffset(host);
                assertEq(offset % 16, 0, "TST-03: split stops on a 16-aligned checkpoint");
                assertGt(offset, lastOffset, "TST-03: split checkpoint advances");
                uint32 left = uint32(TicketQueueStorage.owed(host, rk, player) >> 8);
                assertEq(uint256(left) + offset, owed, "TST-03: checkpoint conserves the owed balance");
                lastOffset = offset;
            }
        }
        assertEq(_soloOffset(host), 0, "TST-03: completed drain clears the solo checkpoint");
        assertEq(TicketQueueStorage.owed(host, rk, player), 0, "TST-03: completed drain clears owed");
        (digest, totalTraits) = _digestTraitBurnTicketForPlayer(host, lvl, player);
    }

    /// @dev The recorded solo runs must form one contiguous cover of [0, owed), each run
    ///      starting on a 16-aligned checkpoint exactly where the previous one stopped.
    function _checkRuns(Vm.Log[] memory logs, uint32 owed) private returns (uint256 runs) {
        uint256 next;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0 || logs[i].topics[0] != TOPIC_TRAITS_GENERATED) continue;
            (uint256 baseKey, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
            uint32 start = uint32(baseKey);
            assertEq(start, next, "TST-03: each run resumes at the persisted checkpoint");
            assertEq(start % 16, 0, "TST-03: each run starts on a 16-aligned checkpoint");
            next += take;
            ++runs;
        }
        assertEq(next, owed, "TST-03: runs cover the owed balance exactly once");
    }

    /// @dev Seed once, snapshot, run both paths from the identical pre-state.
    function _crossPath(address player, uint32 owed, uint256 entropy, uint256 schedule)
        private
        returns (bytes32 digestA, uint256 totalA, bytes32 digestB, uint256 totalB, uint256 callsB)
    {
        address host = address(ticketModule);
        _seedEntropy(host, entropy);
        _seedSinglePlayerQueue(host, ANCHOR_LVL, player, owed);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        (digestA, totalA) = _runPathA_Contiguous(host, ANCHOR_LVL, player);
        uint256 runsA = _checkRuns(vm.getRecordedLogs(), owed);
        vm.revertToState(snap);
        vm.recordLogs();
        (digestB, totalB, callsB) = _runPathB_BoundedSplit(host, ANCHOR_LVL, player, owed, schedule);
        uint256 runsB = _checkRuns(vm.getRecordedLogs(), owed);
        emit log_named_uint("tst03_contiguous_runs", runsA);
        emit log_named_uint("tst03_split_runs", runsB);
        emit log_named_uint("tst03_split_calls", callsB);
        // Contiguous reference: full TICKET_SOLO_MAX_ENTRIES (160) runs plus one tail run.
        assertEq(runsA, (uint256(owed) + 159) / 160, "TST-03: contiguous path uses full 160-entry runs");
        // A real split: more checkpoints than the contiguous path, across several calls.
        assertGt(runsB, runsA, "TST-03: bounded gas must split the cohort at more checkpoints");
        assertGt(callsB, 1, "TST-03: the split spans several worker calls");
    }

    // =========================================================================
    // Deterministic anchor (D-TST03-03)
    // =========================================================================

    /// @notice Cross-path equality for the anchor scenario: owed=300 at level 1, drained
    ///         contiguously (160 + 140) versus in bounded-gas aligned runs.
    function testMintDivCrossPathEquality_OwedSplitsAcrossSlices() public {
        address player = makeAddr("mintdiv-300-player");
        (bytes32 digestA, uint256 totalA, bytes32 digestB, uint256 totalB,) =
            _crossPath(player, ANCHOR_OWED, DETERMINISTIC_ENTROPY, 0);

        // Non-vacuity guard (threat T-336-05-02): both paths credit the full owed allotment.
        assertEq(totalA, uint256(ANCHOR_OWED), "TST-03 anchor: Path A must credit owed=300 traits in total (non-vacuity)");
        assertEq(totalB, uint256(ANCHOR_OWED), "TST-03 anchor: Path B must credit owed=300 traits in total (non-vacuity)");

        assertEq(
            digestA,
            digestB,
            "TST-03 D-TST03-02: byte-identical trait derivation across gas-selected checkpoint splits"
        );
    }

    // =========================================================================
    // Boundary fuzz overlay (D-TST03-01 — owed in [293, 492])
    // =========================================================================

    /// @notice D-TST03-01 boundary fuzz overlay over owed in [293, 492]; the bounded-gas
    ///         schedule phase is derived from owed so run lengths vary across seeds.
    function testFuzz_MintDiv_BoundaryOwedCrossPath(uint32 owed) public {
        vm.assume(owed >= BOUNDARY_OWED_FLOOR && owed <= BOUNDARY_OWED_CEIL);

        address player = makeAddr("mintdiv-boundary-fuzz-player");
        uint256 entropy = uint256(keccak256(abi.encode("336-05-boundary-fuzz-entropy", owed)));

        (bytes32 digestA, uint256 totalA, bytes32 digestB, uint256 totalB,) =
            _crossPath(player, owed, entropy, owed);

        assertEq(totalA, uint256(owed), "TST-03 boundary fuzz: Path A must credit the fuzzed owed in total (non-vacuity)");
        assertEq(totalB, uint256(owed), "TST-03 boundary fuzz: Path B must credit the fuzzed owed in total (non-vacuity)");

        assertEq(
            digestA,
            digestB,
            "TST-03 D-TST03-01: byte-identical trait derivation across budget-slice splits (boundary fuzz)"
        );
    }
}
