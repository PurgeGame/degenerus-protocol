// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {TicketQueueStorage as RingStorage} from "../fuzz/helpers/TicketQueueStorage.sol";

import {Test} from "forge-std/Test.sol";
import {BoundaryGasFixture, PhaseEndSeeder} from "./Lvl100PhaseEndAdvanceGas.t.sol";
import {ChunkHarness} from "./RoundDrainChunkGas.t.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {DegenerusGameTicketModule} from "../../contracts/modules/DegenerusGameTicketModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract DeityTransitionQueueSeeder is DegenerusGameStorage, WalletSeed {
    function seedSurvivors(uint24 target) external {
        uint24 key = _tqFarFutureKey(target);
        for (uint160 i; i < 8; ++i) {
            address who = address(0xF0100000 + i);
            uint80 packed = (uint80(_seedWallet(who)) << OWNER_IDX_SHIFT);
            uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
            _tqAppend(key, pos);
            _setEntryOwed(key, pos, packed | (uint80(1_000_000) << 8));
        }
    }

    /// @dev The seeded close is the daily phase of a delivered, published request: the engine
    ///      selects DailyPhase only for an active, published, not-yet-complete session.
    function openDailyPhase() external {
        rngRequestDay = _simulatedDayIndex();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
    }
}

/// @dev The transition close used to carry the 32 cold deity perpetual grants AND the first chunk
///      of the far-future level crossing into the +5 mint window, resuming the drain on later
///      advances. That drain is gone: the transition closes in one advance and mints nothing; a
///      level's unminted queue mints once, as the frozen pool, in runTicketWork's continuation
///      after the previous level's last purchase day. The two halves of the old worst case are now
///      separate transactions and are measured separately: the grants here, the drain chunk (same
///      eight deep survivors) in DeityFrozenPoolDrainGasTest below.
contract DeityTransitionDrainGasTest is BoundaryGasFixture {
    uint160 private constant SURVIVOR_BASE = 0xF0100000;

    function setUp() public {
        _deployProtocol();
        TQ.retireCompleted(address(game), LVL);
        bytes memory original = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(LVL, uint256(keccak256("deity-transition-full-drain")) | 1);
        vm.etch(address(game), type(DeityTransitionQueueSeeder).runtimeCode);
        // The nearest unminted level at this close (purchase level LVL + 1 is the mint ceiling).
        DeityTransitionQueueSeeder(address(game)).seedSurvivors(LVL + 2);
        DeityTransitionQueueSeeder(address(game)).openDailyPhase();
        _restore(original);
    }

    function testColdThirtyTwoPerpetualGrantsFitAndCloseWithoutDrainingUnmintedQueue() public {
        uint24 ffKey = (uint24(1) << 22) | (LVL + 2);
        bytes32 ffLenSlot = keccak256(abi.encode(uint256(RingStorage.queueKey(uint24(ffKey))), uint256(12)));

        // A realistic 10M allowance succeeds and closes the transition. The call is reported, not
        // bounded (the engine admits chunks while the allowance lasts); the close checkpoint itself
        // (same 32 cold grants) is bounded in isolation by SdgnrsCenturyRecycleGas'
        // testColdCloseChunk* tests.
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: 10_000_000}();
        uint256 used = beforeGas - gasleft() + 21_064;
        emit log_named_uint("cold 32-deity renewal transition close including intrinsic", used);
        _checkOwners();
        assertFalse(game.rngLocked(), "transition closes in this advance");
        // Nothing crosses a far-future boundary at the close: the survivors stay unminted.
        assertEq(uint32(uint256(vm.load(address(game), ffLenSlot))), 8, "transition must not drain an unminted queue");
        for (uint160 i; i < 8; ++i) {
            assertEq(uint32(TQ.owed(address(game), ffKey, address(SURVIVOR_BASE + i)) >> 8), 1_000_000);
        }
        // The close cannot re-run, so no owner gets a second perpetual ticket: the rest of the same
        // day (the day-400 fixture's Craps maintenance catch-up) ends idle (NoWork; was NotTimeYet).
        bool idle;
        for (uint256 i; i < 1000 && !idle; ++i) {
            try game.mineFlip{gas: 10_000_000}() {} catch (bytes memory err) {
                assertEq(bytes4(err), bytes4(keccak256("NoWork()")), "same day ends idle");
                idle = true;
            }
        }
        assertTrue(idle, "the same day runs out of work");
        _checkOwners();
    }

    function _checkOwners() private {
        DegenerusGameLens lens = new DegenerusGameLens();
        for (uint256 i; i < 32; ++i) {
            address owner = lens.deityOwnerAt(address(game), i);
            uint24 key = (uint24(1) << 22) | (LVL + 100);
            assertEq(uint32(TQ.owed(address(game), key, owner) >> 8), 4);
        }
    }
}

/// @dev The drain half of the old test on the path that now exists: the same eight survivors
///      owing 1,000,000 entries each, minted as a frozen pool through runTicketWork's
///      continuation. setUp is a separate transaction, so the first chunk is cold; the chunk
///      resumes on the next call without re-minting what the first one consumed.
contract DeityFrozenPoolDrainGasTest is Test {
    uint24 private constant POOL_LVL = 102;
    uint160 private constant BASE = 0xF0100000;
    ChunkHarness internal h;

    function setUp() public {
        h = new ChunkHarness();
        vm.etch(ContractAddresses.GAME_FOILPACK_MODULE, address(new DegenerusGameFoilPackModule()).code);
        // The harness delegates runTicketWork to the ticket module at its pinned address.
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, address(new DegenerusGameTicketModule()).code);
        // 1,000,000 entries each = 100,000,000 scaled. Cold start: no marker, cursor 0.
        h.seedFrozenPool(POOL_LVL, 8, 100_000_000, BASE, false);
    }

    function _owedSum() private view returns (uint256 sum) {
        for (uint160 i = 1; i <= 8; ++i) sum += uint32(h.ffOwedOf(POOL_LVL, address(BASE + i)) >> 8);
    }

    function testColdFrozenPoolChunkOfDeepSurvivorsFitsAndResumes() public {
        uint256 owed0 = _owedSum();
        assertEq(owed0, 8_000_000, "fixture: eight deep survivors");

        // runTicketWork spends the allowance it is given, so each chunk is driven with a realistic
        // bounded allowance and checked for progress, not bounded.
        uint256 g0 = gasleft();
        MineFlipGas.Result memory r = h.runTicketWork{gas: 10_000_000}(POOL_LVL - 1, 10_000_000);
        (bool finished1, bool worked1) = (r.done, r.progressed);
        uint256 cold = g0 - gasleft();
        uint256 owed1 = _owedSum();
        emit log_named_uint("cold frozen-pool call at a 10M allowance (excl. intrinsic)", cold);
        assertTrue(worked1, "cold chunk mints");
        assertFalse(finished1, "a deep pool is not finished in one chunk");
        assertLt(owed1, owed0, "cold chunk consumes owed entries");

        g0 = gasleft();
        r = h.runTicketWork{gas: 10_000_000}(POOL_LVL - 1, 10_000_000);
        (bool finished2, bool worked2) = (r.done, r.progressed);
        uint256 warm = g0 - gasleft();
        uint256 owed2 = _owedSum();
        emit log_named_uint("resumed frozen-pool call at a 10M allowance (excl. intrinsic)", warm);
        assertTrue(worked2, "resume mints");
        assertFalse(finished2);
        assertLt(owed2, owed1, "resume continues from where the cold chunk stopped");
    }
}
