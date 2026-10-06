// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {AdvanceStageStream} from "../helpers/AdvanceStageStream.sol";
import {TicketQueueStorage as TQ} from "../fuzz/helpers/TicketQueueStorage.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title Lvl100PhaseEndAdvanceGas — the x00 level boundary's two daily stages.
/// @notice A level boundary is a CHAIN of checkpoints. Two of them are exercised here:
///
///           STAGE_JACKPOT_PHASE_ENDED (9) — the coin+tickets leg + _endPhase, at its ticket-board
///             winner cap (96 doubled to 192 at 40 ETH of value, 5b25fded0) and no battle work of
///             its own, then
///           STAGE_TRANSITION_DONE (3)     — the checkpoint that reopens the purchase phase and
///             hosts `coinflip.armCenturySeed`, a separately admitted stage after the phase end.
///         The engine composes admitted checkpoints into a call, so the stages are read from the
///         ordered log stream; every call takes a realistic allowance and must succeed. No
///         whole-call ceiling is asserted (owner rule): the largest call is logged.
///
///         The day's jackpot battle runs from its own stage before the phase-ending day's legs;
///         JackpotMergeAdvance pins its transactions. Both measured txs drive the REAL production
///         mineFlip() bytecode: the overlay below writes the pre-state (its word recorded
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
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
        _recordDailyRng(day, word);
        // The completed ETH leg records this exact board before the ticket stage.
        dailyFoilDraw[day & 1] = _packFoilDraw(JackpotBucketLib.packWinningTraits(mainTraits), lvl, day, word);
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
                _tqAppend(_tqFarFutureKey(c), _seedWallet(address(b + uint160(i + 1))));
            }
        }
    }

    /// @notice The transition-close pre-state: _endPhase already ran, the far-future queue is empty,
    ///         so one advance runs the housekeeping and completes the transition in the same tx.
    function seedTransitionDone(uint24 lvl, uint256 word) external {
        uint24 day = _simulatedDayIndex();

        _seedJackpotDay(lvl, day);
        for (uint256 i = _deityCount(); i < 32; ++i) {
            _seedDeity(address(uint160(0xDE170000 + i)));
        }
        jackpotCounter = 0; // _endPhase zeroed it on the previous advance
        phaseTransitionActive = true;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = word < 2 ? RNG_WORD_WAITING : word;
        _recordDailyRng(day, word);
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
///      restore, then drive the live mineFlip and classify the winner events it emitted.
/// @dev The seeded day is the daily phase of a delivered, published request: the engine selects
///      DailyPhase only for an active, published, not-yet-complete session.
contract BoundarySessionSeeder is DegenerusGame {
    function openDailyPhase() external {
        rngRequestDay = _simulatedDayIndex();
        _setRngRequestActive(true);
        _setRngSessionPublished(true);
        _setRngComplete(false);
    }
}

abstract contract BoundaryGasFixture is AdvanceStageStream {
    /// @dev EIP-7825 per-transaction gas cap. A single mineFlip tx above this is a permanent DoS.
    uint256 internal constant EIP7825_TX_GAS_CAP = 16_777_216;

    bytes32 internal constant TICKET_WIN_SIG =
        keccak256(
            "JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)"
        );
    bytes32 internal constant TICKET_BATCH_SIG =
        keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    bytes32 internal constant BATTLE_ENTRY_SIG =
        keccak256("JackpotBattleEntry(uint64,uint256,address,uint256,uint32)");
    bytes32 internal constant SEED_ARMED_SIG =
        keccak256("SeedWindowArmed(uint24,uint24,uint24,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 internal constant STAGE_TRANSITION_DONE = 3;
    // 1000 whole tickets worth 40 ETH at 0.04: the 96-winner cap doubles (5b25fded0).
    uint256 internal constant TICKET_LEG_WINNERS = 192;
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

    /// @dev Open the seeded day's session; the caller restores the production runtime after.
    function _openSession() internal {
        vm.etch(address(game), type(BoundarySessionSeeder).runtimeCode);
        BoundarySessionSeeder(payable(address(game))).openDailyPhase();
    }

    /// @dev Registry owner of zero-based index `idx` (ticketOwners, slot 67).
    function _ownerAt(uint256 idx) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(game), bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + idx)))));
    }

    /// @dev The next stage from the stream. A coin+tickets leg's partial calls mark stage 8 and its
    ///      completing call on a final day marks 9: one leg. `ticketWins` counts queued
    ///      (JackpotTicketWin) and directly materialized (JackpotTicketBatchWin) winners. `used` is
    ///      the largest call that carried the stage.
    function _measure()
        internal
        returns (
            uint256 used,
            uint256 ticketWins,
            uint256 battleEntries,
            bool seedArmed
        )
    {
        (uint8 stage, uint256 from, uint256 to, uint256 maxGas) = _nextStageRun(200);
        if (stage == STAGE_JACKPOT_COIN_TICKETS && game.rngLocked()) {
            uint256 g;
            (stage,, to, g) = _nextStageRun(200);
            if (g > maxGas) maxGas = g;
        }
        used = maxGas;
        lastStage = stage;
        for (uint256 i = from; i <= to; ++i) {
            Vm.Log storage l = streamLogs[i];
            if (l.topics.length == 0) continue;
            bytes32 t0 = l.topics[0];
            if (t0 == TICKET_WIN_SIG) ++ticketWins;
            else if (t0 == TICKET_BATCH_SIG) {
                (, uint8 count,,,) = abi.decode(l.data, (uint16, uint8, uint32, uint256[4], uint256[4]));
                ticketWins += count;
            } else if (t0 == BATTLE_ENTRY_SIG) ++battleEntries;
            else if (t0 == SEED_ARMED_SIG) seedArmed = true;
        }
        emit log_named_uint("largest_call_gas_incl_intrinsic", used);
    }
}

/// @notice STAGE_JACKPOT_PHASE_ENDED — the x00 phase-end daily's ticket leg at its winner cap,
///         with no battle work of its own.
contract Lvl100PhaseEndAdvanceGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();

        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);
        mainT[3] = GoldSixLib.daily(mainT[3], word);

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        // The level-100 phase end has drained every queue through level 100; the recycled
        // far-future roots for levels 102..200 are free to bind (seedPhaseEnd fills them).
        TQ.retireCompleted(address(game), LVL);
        seeder.seedPhaseEnd(LVL, word, mainT, uint160(0x1000000000));
        _openSession();
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

        // Non-vacuity: the leg MUST have run at its winner cap.
        assertEq(lastStage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(ticketWins, TICKET_LEG_WINNERS, "the main-board ticket leg paid the full 192-winner cap");
        assertEq(battleEntries, 0, "the phase-end coin+tickets stage runs no battle work");
        // The century arm rides the transition close, not the phase-end stage.
        assertFalse(seedArmed, "the century arm does NOT ride the phase-end stage");
        // The transition close is its own later stage (it may share a call with the phase end
        // when the allowance admits both checkpoints).
        (uint256 closeUsed,,, bool closeArmed) = _measure();
        emit log_named_uint("LVL100_TRANSITION_CLOSE_STAGE_GAS", closeUsed);
        assertEq(lastStage, STAGE_TRANSITION_DONE, "the close runs from its own stage after the phase end");
        assertTrue(closeArmed, "the century arm rides the transition close");
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
        _openSession();
        _restore(realCode);
        // The level-100 close has drained every queue through level 100: the recycled roots for
        // the level-200 perpetual grants are free to bind.
        TQ.retireCompleted(address(game), LVL);
    }

    function test_TransitionDoneAdvance_WithCenturyArm() public {
        // One call at a realistic 10M allowance must close the transition: the close is one
        // admitted checkpoint (TRANSITION_CLOSE).
        vm.recordLogs();
        game.mineFlip{gas: 10_000_000}();
        uint256 used = vm.lastCallGas().gasTotalUsed + 21_064;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool seedArmed;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 0 && logs[i].topics[0] == SEED_ARMED_SIG) seedArmed = true;
        }

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
    }
}
