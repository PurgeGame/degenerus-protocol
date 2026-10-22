// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {MineFlipGasBounds as GasBounds} from "../../../contracts/libraries/MineFlipGasBounds.sol";

/// @title MineFlipAdmission -- the gas a mineFlip caller must supply for an action's first unit
/// @notice The engine runs the first unit of the selected action without consulting estimates,
///         so a caller that supplies the action's declared first-unit bound must see progress.
///         `minGas` is that bound (MineFlipGasBounds, with the Degenesis additions while fewer
///         than seven cohorts are closed) plus ENGINE_BOUNDARY and ENGINE_RETURN, grossed up for
///         the facade -> miner and miner -> worker 63/64 forwarding hops, plus FACADE_ALLOWANCE
///         for the facade dispatch and the miner's action selection outside the meter.
library MineFlipAdmission {
    uint8 internal constant IDLE = 0;
    uint8 internal constant TERMINAL = 1;
    uint8 internal constant WAIT = 2;
    uint8 internal constant PUBLISH = 3;
    uint8 internal constant TICKETS = 4;
    uint8 internal constant DAILY_GAP = 5;
    uint8 internal constant DAILY_APPLY = 6;
    uint8 internal constant DAILY_PHASE = 7;
    uint8 internal constant REDEMPTION = 8;
    uint8 internal constant AFKING = 9;
    uint8 internal constant HUMAN_BOXES = 10;
    uint8 internal constant DEGENERETTE = 11;
    uint8 internal constant DECIMATOR = 12;
    uint8 internal constant CRAPS = 13;
    uint8 internal constant CERTIFY = 14;
    uint8 internal constant PREPARE_SUBS = 15;
    uint8 internal constant MAINTENANCE = 16;
    uint8 internal constant REQUEST_DAILY = 17;
    uint8 internal constant REQUEST_MIDDAY = 18;
    uint8 internal constant GROWTH = 19;
    uint8 internal constant SEIZE_LOANS = 20;
    uint8 internal constant DEGENESIS_SETTLE = 21;

    uint256 internal constant FACADE_ALLOWANCE = 150_000;

    /// @dev The worst single Degenesis order with its own flush, the cohort close and the burn.
    function degenesisSettleFirstUnit() internal pure returns (uint256) {
        uint256 branch = GasBounds.DEGENESIS_DGNRS_GAS;
        if (GasBounds.DEGENESIS_FLIP_PASS_GAS > branch) branch = GasBounds.DEGENESIS_FLIP_PASS_GAS;
        if (GasBounds.DEGENESIS_WWXRP_GAS > branch) branch = GasBounds.DEGENESIS_WWXRP_GAS;
        return branch + GasBounds.DEGENESIS_TAIL_GAS + GasBounds.DEGENESIS_FLUSH_PER_CREDIT;
    }

    /// @dev Game over's loan checkpoint: the terminal phase pre-check, one worst-family loan, one
    ///      due-level step and the loan tail.
    function terminalLoanFirstUnit() internal pure returns (uint256) {
        return 100_000 + 150_000 + GasBounds.LOAN_SEIZE_BASE + 6 * GasBounds.LOAN_SEIZE_SUB
            + GasBounds.LOAN_SEIZE_DEITY + GasBounds.LOAN_TERMINAL_LEVEL + GasBounds.LOAN_SEIZE_TAIL;
    }

    /// @notice The declared first-unit bound of `action`, before the engine boundary and return.
    function firstUnit(uint8 action, bool sale) internal pure returns (uint256 b) {
        if (action == IDLE || action == WAIT || action == CERTIFY) return 0;
        if (action == DEGENESIS_SETTLE) return degenesisSettleFirstUnit();
        if (action == REQUEST_DAILY) {
            return GasBounds.RNG_DAILY_REQUEST + GasBounds.RNG_REDEMPTION_CLOSE
                + (sale ? GasBounds.DEGENESIS_REQUEST_GAS : 0);
        }
        if (action == REQUEST_MIDDAY) return GasBounds.RNG_MIDDAY_REQUEST;
        if (action == DAILY_GAP) return GasBounds.DAILY_GAP + (sale ? GasBounds.DEGENESIS_WORD_COPY_GAS : 0);
        if (action == DAILY_APPLY) return GasBounds.DAILY_APPLY + (sale ? GasBounds.DEGENESIS_WORD_COPY_GAS : 0);
        if (action == PREPARE_SUBS) return GasBounds.SUBSCRIBER_WHALE_GAS + GasBounds.SUBSCRIBER_TAIL_GAS;
        if (action == AFKING) return GasBounds.AFKING_OPEN_GAS + GasBounds.AFKING_TAIL_GAS;
        if (action == HUMAN_BOXES) {
            return GasBounds.HUMAN_ENTRY_GAS + 100 * GasBounds.HUMAN_BOX_GAS + GasBounds.HUMAN_TAIL_GAS;
        }
        if (action == TICKETS) {
            b = GasBounds.TICKET_SOLO_BASE + GasBounds.TICKET_SOLO_MAX_ENTRIES * GasBounds.TICKET_ENTRY_MAX
                + GasBounds.TICKET_TAIL + GasBounds.TICKET_CALL_OVERHEAD;
            uint256 round = GasBounds.TICKET_ROUND_MAX + GasBounds.TICKET_TAIL + GasBounds.TICKET_CALL_OVERHEAD;
            return round > b ? round : b;
        }
        // The heaviest daily stage, the stage's own pre-check and its tail.
        if (action == DAILY_PHASE) return GasBounds.LEVEL_ONE_DRAW + 100_000 + 150_000 + GasBounds.DAILY_PHASE_TAIL;
        if (action == TERMINAL) {
            // The heaviest terminal checkpoint (the terminal word's gap and apply), the phase
            // pre-check, the terminal tail and the phase tail.
            b = GasBounds.DAILY_GAP + GasBounds.DAILY_APPLY;
            uint256 setup = GasBounds.TERMINAL_SETUP + GasBounds.DEGENESIS_TERMINAL_GAS;
            if (setup > b) b = setup;
            return b + 250_000 + GasBounds.TERMINAL_TAIL + GasBounds.DAILY_PHASE_TAIL;
        }
        if (action == SEIZE_LOANS) {
            return GasBounds.LOAN_SEIZE_BASE + 6 * GasBounds.LOAN_SEIZE_SUB + GasBounds.LOAN_SEIZE_DEITY
                + GasBounds.LOAN_SEIZE_TAIL;
        }
        if (action == REDEMPTION) {
            return GasBounds.REDEMPTION_BASE_GAS + GasBounds.REDEMPTION_TAIL_GAS + GasBounds.REDEMPTION_RESOLVE_GAS;
        }
        if (action == DEGENERETTE) {
            return GasBounds.DEGENERETTE_ETH_BASE_GAS + 100 * GasBounds.DEGENERETTE_ETH_SPIN_GAS
                + GasBounds.DEGENERETTE_RECORD_GAS + GasBounds.DEGENERETTE_TAIL_GAS;
        }
        if (action == DECIMATOR) return GasBounds.DECIMATOR_GENERATED_GAS_MAX + GasBounds.DECIMATOR_WORK_TAIL_GAS;
        if (action == CRAPS) {
            return GasBounds.CRAPS_SEAT_GAS_MAX + GasBounds.CRAPS_SETTLE_TAIL_GAS + GasBounds.CRAPS_CREDIT_GAS_MAX
                + GasBounds.CRAPS_WORK_TAIL_GAS;
        }
        if (action == MAINTENANCE) return GasBounds.CRAPS_MAINTENANCE_GAS_MAX + GasBounds.CRAPS_WORK_TAIL_GAS;
        // Publish and growth settlement: small fixed work.
        return 1_000_000;
    }

    /// @notice Caller gas that funds `firstUnit` through the engine.
    function gross(uint256 unit) internal pure returns (uint256) {
        return (unit + GasBounds.ENGINE_BOUNDARY + GasBounds.ENGINE_RETURN) * 4096 / 3969 + FACADE_ALLOWANCE;
    }

    function minGas(uint8 action, bool sale) internal pure returns (uint256) {
        return gross(firstUnit(action, sale));
    }
}
