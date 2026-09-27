// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title Lvl100PhaseEndAdvanceGas — the per-tx gas ceiling of the x00 level boundary.
/// @notice A level boundary is a CHAIN of advance txs, not one tx. Two of them are measured here:
///
///           STAGE_JACKPOT_PHASE_ENDED (9) — payDailyJackpotCoinAndTickets + _endPhase, at its
///             ticket-board winner cap (96 main-board tickets) and no battle work of its own, then
///           STAGE_TRANSITION_DONE (3)     — the tx that reopens the purchase phase and hosts
///             `coinflip.armCenturySeed`. Reached only once the far-future batch reports no work,
///             so the century arm can never stack on a chunked stage.
///
///         The day's jackpot battle runs from its own stage before the phase-ending day's legs;
///         JackpotMergeAdvance pins its transactions. Both measured txs drive the REAL production
///         advanceGame() bytecode: the overlay below writes the pre-state (its word recorded
///         directly, so no battle is locked), then the real code is etched back before the call.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding happens in setUp() — a SEPARATE
///      transaction from the measured body — so the measured call starts on a cold EIP-2929 access
///      list, as a real keeper tx would. Seeding inline understates the phase-end tx by ~565k.
contract PhaseEndSeeder is DegenerusGame, BucketSeed {
    /// @notice The level-100 jackpot-phase-END pre-state, at every winner cap the leg can reach.
    /// @param lvl         the x00 level whose jackpot phase is closing
    /// @param word        the day's recorded VRF word (non-zero -> rngGate returns it immediately)
    /// @param mainTraits  the 4 traits the ticket board draws, mirrored from the live roll
    /// @param base        disjoint address-space base for synthetic holders
    function seedPhaseEnd(
        uint24 lvl,
        uint256 word,
        uint8[4] calldata mainTraits,
        uint160 base
    ) external {
        uint24 day = _simulatedDayIndex();

        _seedJackpotDay(lvl, day);
        jackpotCounter = 2; // the third draw ends the standard phase
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = word;
        rngWordByDay[day] = word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = true;
        // dailyEntries = 4000 (bits 8..71): 1000 whole tickets, so the ticket leg saturates the
        // 96-winner cap. The battle-pending bit (72) is clear: the day's battle has completed, so
        // the coin+tickets stage runs the ticket leg alone.
        dailyTicketBudgetsPacked = uint256(4000) << 8;

        // Ticket-board buckets at lvl.
        for (uint8 q; q < 4; ++q) {
            _fill(lvl, mainTraits[q], 130, base + uint160(q) * 0x40000);
        }

        // Populated far-future queues, levels lvl+2..lvl+100, distinct fresh wallets only. The
        // coin+tickets stage does not read them.
        for (uint24 c = lvl + 2; c <= lvl + 100; ++c) {
            uint160 b = base + 0x4000000 + uint160(c - lvl - 2) * 0x1000;
            for (uint256 i; i < 8; ++i) {
                _tqAppend(_tqFarFutureKey(c), uint32(_registerEntryOwner(address(b + uint160(i + 1)), c) >> OWNER_IDX_SHIFT));
            }
        }
    }

    /// @notice The transition-close pre-state: _endPhase already ran, the far-future queue is empty,
    ///         so one advance runs the housekeeping and completes the transition in the same tx.
    function seedTransitionDone(uint24 lvl, uint256 word) external {
        uint24 day = _simulatedDayIndex();

        _seedJackpotDay(lvl, day);
        for (uint256 i = deityPassOwners.length; i < 32; ++i) {
            deityPassOwners.push(address(uint160(0xDE170000 + i)));
        }
        jackpotCounter = 0; // _endPhase zeroed it on the previous advance
        phaseTransitionActive = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = word;
        rngWordByDay[day] = word;
        vrfRequestId = 1;
        ticketLevel = 0; // not resuming FF -> _processPhaseTransition runs this tx
        ticketCursor = 0;
        claimablePool = uint128(10 ether); // < balance -> _autoStakeExcessEth actually stakes
    }

    /// @dev The shared jackpot-phase day shape: day == dailyIdx + 1 (no RNGREUSE clamp, no mid-day
    ///      branch), the day's request still locked (so the subscriber STAGE is skipped, as it is on
    ///      every advance between a request and its _unlockRng), and pools deep enough that the coin
    ///      legs reach their caps.
    function _seedJackpotDay(uint24 lvl, uint24 day) private {
        level = lvl;
        purchaseStartDay = day - 10;
        dailyIdx = day - 1;
        jackpotPhaseFlag = true;
        lastPurchaseDay = false;
        jackpotFlags = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);

        levelPrizePool[lvl] = 1000 ether; // _endPhase record-pool fund (non-zero)
        levelPrizePool[lvl - 1] = 100_000 ether;
        _setPrizePools(uint128(50 ether), uint128(300 ether));
        currentPrizePool = uint128(200 ether);
    }

    function _fill(uint24 lvl_, uint8 trait, uint256 n, uint160 b) private {
        _seedBucketDistinct(lvl_, trait, n, b);
    }
}

/// @dev Shared measurement seam: warp to a day whose century-seed lanes are all virgin, etch-seed-
///      restore, then drive the live advanceGame and classify the winner events it emitted.
abstract contract BoundaryGasFixture is DeployProtocol {
    /// @dev EIP-7825 per-transaction gas cap. A single advanceGame tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    bytes32 internal constant TICKET_WIN_SIG =
        keccak256(
            "JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)"
        );
    bytes32 internal constant BATTLE_ENTRY_SIG =
        keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
    bytes32 internal constant SEED_ARMED_SIG =
        keccak256("SeedWindowArmed(uint24,uint24,uint24,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal lastStage;

    uint24 internal constant LVL = 100;
    uint256 internal wwxrpBefore;

    /// @dev Day 400 puts the seed window's 20 target lanes far past the deploy program, so every
    ///      slot the century arm writes is virgin — the cold, worst-case shape.
    function _warpToDay(uint24 targetDay, uint256 intoDay) internal {
        vm.warp(
            (uint256(targetDay - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620 +
                intoDay
        );
    }

    function _etchSeedRestore() internal returns (PhaseEndSeeder seeder) {
        _warpToDay(400, 3 hours);
        seeder = PhaseEndSeeder(payable(address(game)));
        vm.etch(address(game), type(PhaseEndSeeder).runtimeCode);
    }

    function _restore(bytes memory realCode) internal {
        vm.etch(address(game), realCode);
        vm.deal(address(game), 1000 ether);
        wwxrpBefore = wwxrp.totalSupply();
    }

    function _measure()
        internal
        returns (
            uint256 used,
            uint256 ticketWins,
            uint256 battleEntries,
            bool seedArmed
        )
    {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame();
        used = g0 - gasleft();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t0 = logs[i].topics[0];
            if (t0 == TICKET_WIN_SIG) ++ticketWins;
            else if (t0 == BATTLE_ENTRY_SIG) ++battleEntries;
            else if (t0 == SEED_ARMED_SIG) seedArmed = true;
            else if (t0 == ADVANCE_SIG) (lastStage, ) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("headroom_to_16p7M", EIP7825_TX_GAS_CAP - used);
    }
}

/// @notice STAGE_JACKPOT_PHASE_ENDED — the x00 phase-end daily's ticket leg at its winner cap,
///         with no battle work of its own.
contract Lvl100PhaseEndAdvanceGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();

        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedPhaseEnd(LVL, word, mainT, uint160(0x1000000000));
        _restore(realCode);
    }

    function test_Lvl100PhaseEndAdvance_MaxGas() public {
        (
            uint256 used,
            uint256 ticketWins,
            uint256 battleEntries,
            bool seedArmed
        ) = _measure();

        emit log_named_uint("LVL100_PHASE_END_ADVANCE_GAS", used);

        // Non-vacuity: the composition MUST have run at its winner cap, or the ceiling is not one.
        assertEq(lastStage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(ticketWins, 96, "the main-board ticket leg paid the full 96-winner cap");
        assertEq(battleEntries, 0, "the phase-end coin+tickets stage runs no battle work");
        // The century arm rides the transition close, not this tx — it must not fuse back onto the
        // binding stage.
        assertFalse(seedArmed, "the century arm does NOT ride the binding phase-end tx");
        assertLt(used, EIP7825_TX_GAS_CAP, "the phase-end advance tx clears EIP-7825");
        (, bool jackpotPhase_, , , ) = game.purchaseInfo();
        assertTrue(jackpotPhase_, "the transition is still ahead: the close runs from its own stage");
    }
}

/// @notice STAGE_TRANSITION_DONE — the tx that reopens the purchase phase and arms the century seed.
contract Lvl100TransitionDoneGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedTransitionDone(
            LVL,
            uint256(keccak256("lvl100-transition")) | 1
        );
        _restore(realCode);
    }

    function test_TransitionDoneAdvance_WithCenturyArm() public {
        (uint256 used, , , bool seedArmed) = _measure();

        emit log_named_uint("LVL100_TRANSITION_DONE_ADVANCE_GAS", used);
        emit log_named_uint(
            "wwxrp_supply_delta",
            wwxrp.totalSupply() - wwxrpBefore
        );

        // Non-vacuity: the purchase phase reopened AND the century window armed, in this one tx.
        (, bool jackpotPhase_, , , ) = game.purchaseInfo();
        assertFalse(jackpotPhase_, "the transition completed and the purchase phase reopened");
        assertTrue(seedArmed, "the century seed window armed on the transition close");
        assertEq(wwxrp.totalSupply(), wwxrpBefore, "century arming no longer mints WWXRP");

        assertLt(used, EIP7825_TX_GAS_CAP, "the transition-close tx clears EIP-7825");
    }
}
