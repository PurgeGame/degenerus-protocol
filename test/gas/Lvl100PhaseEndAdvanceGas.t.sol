// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";

/// @title Lvl100PhaseEndAdvanceGas — the per-tx gas ceiling of the x00 level boundary.
/// @notice A level boundary is a CHAIN of advance txs, not one tx. Two of them are measured here:
///
///           STAGE_JACKPOT_PHASE_ENDED (9) — payDailyJackpotCoinAndTickets + _endPhase, at its
///             winner caps (100 main-board ticket, 50 near-coin, 10 far-coin), followed by
///           STAGE_JACKPOT_CARRYOVER_TICKETS (13) — the carryover leg (100 more ticket winners)
///             the phase-end stage priced, paid as the first stage of the very next advance so
///             the two ticket legs never share one tx.
///           STAGE_TRANSITION_DONE (3)     — the tx that reopens the purchase phase and hosts
///             `coinflip.armCenturySeed`. Reached only once the far-future batch reports no work,
///             so the century arm can never stack on a chunked stage.
///
///         Both drive the REAL production advanceGame() bytecode: the overlay below writes the
///         pre-state, then the real code is etched back before the measured call.
/// @dev TEST-INFRA ONLY. No contracts/*.sol is mutated. Seeding happens in setUp() — a SEPARATE
///      transaction from the measured body — so the measured call starts on a cold EIP-2929 access
///      list, as a real keeper tx would. Seeding inline understates the phase-end tx by ~565k.
contract PhaseEndSeeder is DegenerusGame, BucketSeed {
    /// @notice The level-100 jackpot-phase-END pre-state, at every winner cap the leg can reach.
    /// @param lvl         the x00 level whose jackpot phase is closing
    /// @param word        the day's recorded VRF word (non-zero -> rngGate returns it immediately)
    /// @param mainTraits  the 4 traits the main ticket board draws, mirrored from the live roll
    /// @param bonusTraits the 4 traits the carryover board and the coin legs draw
    /// @param base        disjoint address-space base for synthetic holders
    function seedPhaseEnd(
        uint24 lvl,
        uint256 word,
        uint8[4] calldata mainTraits,
        uint8[4] calldata bonusTraits,
        uint160 base
    ) external {
        uint24 day = _simulatedDayIndex();

        _seedJackpotDay(lvl, day);
        jackpotCounter = 4; // + counterStep 1 == JACKPOT_LEVEL_CAP -> _endPhase fires
        phaseTransitionActive = false;
        subsFullyProcessed = true;
        _afkingResetDay = day;
        rngWordCurrent = word;
        rngWordByDay[day] = word;
        vrfRequestId = 1;
        dailyJackpotCoinTicketsPending = true;
        // _packDailyTicketBudgets(counterStep=1, dailyEntries=4000, carryoverEntries=4000, offset=0).
        // 4000 entries = 1000 whole tickets, so both ticket legs saturate the 100-winner cap.
        dailyTicketBudgetsPacked =
            uint256(1) |
            (uint256(4000) << 8) |
            (uint256(4000) << 72);

        // Ticket-board buckets: both legs draw from lvlTraitEntry[lvl] (carryover offset 0).
        for (uint8 q; q < 4; ++q) {
            _fill(lvl, mainTraits[q], 130, base + uint160(q) * 0x40000);
            _fill(
                lvl,
                bonusTraits[q],
                130,
                base + 0x800000 + uint160(q) * 0x40000
            );
        }

        // Near-future coin pulls sample lvl+1 .. lvl+4 on the bonus traits.
        for (uint24 L = lvl + 1; L <= lvl + 4; ++L) {
            for (uint8 q; q < 4; ++q) {
                _fill(
                    L,
                    bonusTraits[q],
                    60,
                    base +
                        0x4000000 +
                        uint160(L - lvl) *
                        0x100000 +
                        uint160(q) *
                        0x20000
                );
            }
        }

        // Far-future coin samples: 10 draws over [lvl+5, lvl+99].
        for (uint24 L = lvl + 5; L <= lvl + 99; ++L) {
            ticketQueue[_tqFarFutureKey(L)].push(
                address(base + 0x20000000 + uint160(L))
            );
        }
    }

    /// @notice The transition-close pre-state: _endPhase already ran, the far-future queue is empty,
    ///         so one advance runs the housekeeping and completes the transition in the same tx.
    function seedTransitionDone(uint24 lvl, uint256 word) external {
        uint24 day = _simulatedDayIndex();

        _seedJackpotDay(lvl, day);
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
        compressedJackpotFlag = 0;
        ticketsFullyProcessed = true;
        prizePoolFrozen = true;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);

        levelPrizePool[lvl] = 1000 ether; // _endPhase record-pool fund (non-zero)
        levelPrizePool[lvl - 1] = 1000 ether; // coin budget -> 50 near + 10 far winners
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
    bytes32 internal constant FLIP_WIN_SIG =
        keccak256("JackpotFlipWin(address,uint24,uint8,uint256,uint256)");
    bytes32 internal constant FAR_WIN_SIG =
        keccak256("FarFutureFlipJackpotWinner(address,uint24,uint24,uint256)");
    bytes32 internal constant SEED_ARMED_SIG =
        keccak256("SeedWindowArmed(uint24,uint24,uint24,uint256)");
    bytes32 internal constant ADVANCE_SIG = keccak256("Advance(uint8,uint24)");

    uint8 internal constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 internal constant STAGE_JACKPOT_CARRYOVER_TICKETS = 13;
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
        wwxrpBefore = wwxrp.vaultAllowance();
    }

    function _measure()
        internal
        returns (
            uint256 used,
            uint256 ticketWins,
            uint256 flipWins,
            uint256 farWins,
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
            else if (t0 == FLIP_WIN_SIG) ++flipWins;
            else if (t0 == FAR_WIN_SIG) ++farWins;
            else if (t0 == SEED_ARMED_SIG) seedArmed = true;
            else if (t0 == ADVANCE_SIG) (lastStage, ) = abi.decode(logs[i].data, (uint8, uint24));
        }
        emit log_named_uint("headroom_to_16p7M", EIP7825_TX_GAS_CAP - used);
    }
}

/// @notice STAGE_JACKPOT_PHASE_ENDED then STAGE_JACKPOT_CARRYOVER_TICKETS — the two halves of the
///         x00 phase-end daily, each at every winner cap it can reach.
contract Lvl100PhaseEndAdvanceGas is BoundaryGasFixture {
    function setUp() public {
        _deployProtocol();

        uint256 word = uint256(keccak256("lvl100-phase-end")) | 1;
        uint8[4] memory mainT = JackpotBucketLib.getRandomTraits(word);
        uint8[4] memory bonusT = JackpotBucketLib.getRandomTraits(
            EntropyLib.hash2(word, uint256(keccak256("BONUS_TRAITS")))
        );

        bytes memory realCode = address(game).code;
        PhaseEndSeeder seeder = _etchSeedRestore();
        seeder.seedPhaseEnd(LVL, word, mainT, bonusT, uint160(0x1000000000));
        _restore(realCode);
    }

    function test_Lvl100PhaseEndAdvance_MaxGas() public {
        (
            uint256 used,
            uint256 ticketWins,
            uint256 flipWins,
            uint256 farWins,
            bool seedArmed
        ) = _measure();

        emit log_named_uint("LVL100_PHASE_END_ADVANCE_GAS", used);

        // Non-vacuity: the composition MUST have run at its winner caps, or the ceiling is not one.
        assertEq(lastStage, STAGE_JACKPOT_PHASE_ENDED, "the phase-end stage ran");
        assertEq(ticketWins, 100, "the main-board ticket leg paid the full 100-winner cap");
        assertEq(flipWins, 50, "the near coin leg paid the full 50-winner cap");
        assertEq(farWins, 10, "the far-future coin leg paid all 10 samples");
        // The century arm rides the transition close, not this tx — it must not fuse back onto the
        // binding stage.
        assertFalse(seedArmed, "the century arm does NOT ride the binding phase-end tx");
        assertLt(used, EIP7825_TX_GAS_CAP, "the phase-end advance tx clears EIP-7825");

        // The carryover leg is the whole of the next advance: 100 more ticket winners, nothing else.
        (used, ticketWins, flipWins, farWins, seedArmed) = _measure();
        emit log_named_uint("LVL100_CARRYOVER_LEG_ADVANCE_GAS", used);
        assertEq(lastStage, STAGE_JACKPOT_CARRYOVER_TICKETS, "the carryover leg ran as the next stage");
        assertEq(ticketWins, 100, "the carryover ticket leg paid the full 100-winner cap");
        assertEq(flipWins + farWins, 0, "no coin leg rides the carryover stage");
        assertFalse(seedArmed, "the century arm does NOT ride the carryover stage");
        assertLt(used, EIP7825_TX_GAS_CAP, "the carryover advance tx clears EIP-7825");
        (, bool jackpotPhase_, , , ) = game.purchaseInfo();
        assertTrue(jackpotPhase_, "the transition is still ahead: the leg ran before it");
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
        (uint256 used, , , , bool seedArmed) = _measure();

        emit log_named_uint("LVL100_TRANSITION_DONE_ADVANCE_GAS", used);
        emit log_named_uint(
            "wwxrp_vault_allowance_delta",
            wwxrp.vaultAllowance() - wwxrpBefore
        );

        // Non-vacuity: the purchase phase reopened AND the century window armed, in this one tx.
        (, bool jackpotPhase_, , , ) = game.purchaseInfo();
        assertFalse(jackpotPhase_, "the transition completed and the purchase phase reopened");
        assertTrue(seedArmed, "the century seed window armed on the transition close");
        assertGt(
            wwxrp.vaultAllowance(),
            wwxrpBefore,
            "the century arm raised the vault's uncirculated WWXRP reserve"
        );

        assertLt(used, EIP7825_TX_GAS_CAP, "the transition-close tx clears EIP-7825");
    }
}
