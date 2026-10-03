// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Precomputed cold-path admission bounds for the mining engine.
/// @dev Constants include the named operation only; callers additionally reserve their
///      complete checkpoint/return tail. Every operation plus its tail stays at or below
///      10M gas. These bounds are part of the gas calibration contract and must be
///      revalidated when an operation or compiler setting changes.
///      Numbers are conservative candidates until their cold-path evidence is recorded.
library MineFlipGasBounds {
    uint256 internal constant ENGINE_BOUNDARY = 100_000;
    uint256 internal constant ENGINE_RETURN = 200_000;
    uint256 internal constant DAILY_GAP = 1_500_000;
    uint256 internal constant DAILY_APPLY = 3_600_000;
    uint256 internal constant RNG_REQUEST = 2_500_000;
    // Century close: 32 deity renewals, stETH stake, unlock, recycle and seed arming.
    uint256 internal constant TRANSITION_CLOSE = 3_000_000;
    uint256 internal constant LEVEL_ONE_DRAW = 2_500_000;
    uint256 internal constant POOL_CONSOLIDATION = 8_100_000;
    uint256 internal constant DAILY_PHASE_TAIL = 150_000;
    uint256 internal constant FOIL_PACK = 1_400_000;

    uint256 internal constant JACKPOT_BATTLE_DRAW = 8_200_000;
    uint256 internal constant TERMINAL_SETUP = 1_600_000;
    uint256 internal constant TERMINAL_TAIL = 250_000;
    uint256 internal constant TERMINAL_TALLY_RECORD = 25_000;
    uint256 internal constant TERMINAL_TALLY_FINAL = 900_000;
    uint256 internal constant TERMINAL_TALLY_TAIL = 100_000;
    uint256 internal constant TERMINAL_FINAL_SWEEP = 700_000;
    uint256 internal constant TERMINAL_SWEEP_TAIL = 80_000;

    // TICKET
    uint256 internal constant TICKET_TAIL = 180_000;
    uint256 internal constant TICKET_SELECT_MAX = 110_000;
    uint256 internal constant TICKET_SEAT_MAX = 75_000;
    uint256 internal constant TICKET_RELOAD_MAX = 350_000;
    uint256 internal constant TICKET_ROUND_MAX = 1_850_000;
    uint256 internal constant TICKET_SOLO_BASE = 95_000;
    uint256 internal constant TICKET_ENTRY_MAX = 60_000;
    // One solo trait run: SOLO_BASE + 160 x ENTRY_MAX + TAIL stays below 10M.
    uint256 internal constant TICKET_SOLO_MAX_ENTRIES = 160;
    uint256 internal constant TICKET_FOIL_CALL_MAX = 1_550_000;
    uint256 internal constant TICKET_CALL_OVERHEAD = 35_000;

    // AFK
    // Includes a failed full-stipend stETH attempt followed by normal eviction,
    // or a successful pull followed by the most expensive subscriber delivery.
    uint256 internal constant SUBSCRIBER_ITEM_GAS = 400_000;
    uint256 internal constant AFKING_STETH_PULL_GAS = 160_000;
    uint256 internal constant SUBSCRIBER_WHALE_GAS = 3_400_000;
    uint256 internal constant SUBSCRIBER_TAIL_GAS = 150_000;
    uint256 internal constant AFKING_OPEN_GAS = 500_000;
    uint256 internal constant AFKING_SKIP_GAS = 20_000;
    uint256 internal constant AFKING_TAIL_GAS = 100_000;

    // BOX
    uint256 internal constant HUMAN_ENTRY_GAS = 550_000;
    uint256 internal constant HUMAN_BOX_GAS = 70_000;
    uint256 internal constant HUMAN_PRESALE_GAS = 500_000;
    uint256 internal constant HUMAN_SKIP_GAS = 20_000;
    uint256 internal constant HUMAN_TAIL_GAS = 250_000;

    // BET
    uint256 internal constant DEGENERETTE_ETH_BASE_GAS = 500_000;
    uint256 internal constant DEGENERETTE_ETH_SPIN_GAS = 80_000;
    uint256 internal constant DEGENERETTE_FLIP_BASE_GAS = 80_000;
    uint256 internal constant DEGENERETTE_FLIP_SPIN_GAS = 20_000;
    uint256 internal constant DEGENERETTE_RECORD_GAS = 100_000;
    uint256 internal constant DEGENERETTE_SKIP_GAS = 20_000;
    uint256 internal constant DEGENERETTE_TAIL_GAS = 120_000;

    // DEC
    uint256 internal constant DECIMATOR_RUN_GAS_MAX = 700_000;
    uint256 internal constant DECIMATOR_TAILS_GAS_MAX = 20_000;
    uint256 internal constant DECIMATOR_RANK_GAS_MAX = 500_000;
    uint256 internal constant DECIMATOR_PAYMENT_GAS_MAX = 120_000;
    uint256 internal constant DECIMATOR_WORK_TAIL_GAS = 80_000;

    // JACKPOT
    uint256 internal constant JACKPOT_SETUP_GAS = 500_000;
    uint256 internal constant JACKPOT_PLAN_GAS = 120_000;
    uint256 internal constant JACKPOT_FINAL_GAS = 150_000;
    uint256 internal constant JACKPOT_TAIL_GAS = 180_000;
    // Cold winner with a fresh claimable balance: 30.6k measured.
    uint256 internal constant JACKPOT_ETH_WINNER_GAS_MAX = 37_000;
    // One sampler group, as for tickets: a quadrant's first group adds 160k for its pass
    // conversion, gold arm and accounting; continuation groups are 8 x WINNER.
    uint256 internal constant JACKPOT_ETH_AWARD_CHUNK = 8;
    // One ticket-leg pass recipient: bucket draw, cold claim write and event.
    uint256 internal constant JACKPOT_PASS_AWARD_GAS = 100_000;
    // Cold draw: 3.4k per winner. Award with a fresh pending word: 37.6k measured.
    uint256 internal constant JACKPOT_TICKET_DRAW_GAS_MAX = 4_200;
    uint256 internal constant JACKPOT_TICKET_AWARD_GAS_MAX = 45_000;
    // One sampler group: eight draws share one packed bucket word. Checkpoints must start a
    // group, so this stays a multiple of eight. 8 x (DRAW + AWARD) + TAIL = 0.57M.
    uint256 internal constant JACKPOT_TICKET_AWARD_CHUNK = 8;

    // CRAPS
    uint256 internal constant CRAPS_SEAT_GAS_MAX = 1_650_000;
    uint256 internal constant CRAPS_CREDIT_GAS_MAX = 65_000;
    uint256 internal constant CRAPS_SETTLE_TAIL_GAS = 200_000;
    uint256 internal constant CRAPS_WORK_TAIL_GAS = 60_000;
    uint256 internal constant CRAPS_MAINTENANCE_GAS_MAX = 240_000;
    uint256 internal constant CRAPS_REFUND_GAS_MAX = 65_000;
    uint256 internal constant CRAPS_SWEEP_TAIL_GAS = 130_000;

    // REDEEM
    uint256 internal constant REDEMPTION_BASE_GAS = 350_000;
    uint256 internal constant REDEMPTION_CHUNK_GAS = 250_000;
    uint256 internal constant REDEMPTION_TAIL_GAS = 80_000;
}
