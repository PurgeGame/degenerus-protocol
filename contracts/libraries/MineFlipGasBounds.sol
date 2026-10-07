// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Precomputed cold-path admission bounds for the mining engine.
/// @dev Constants include the named operation only; callers additionally reserve their
///      complete checkpoint/return tail. Every operation plus its tail stays at or below
///      10M gas. These bounds are part of the gas calibration contract and must be
///      revalidated when an operation or compiler setting changes.
///      Each bound is its cold measured cost plus a modest margin; the measurement is noted
///      beside it.
library MineFlipGasBounds {
    uint256 internal constant ENGINE_BOUNDARY = 100_000;
    uint256 internal constant ENGINE_RETURN = 200_000;
    // Cold widest live gap (29 days): 0.47M measured.
    uint256 internal constant DAILY_GAP = 600_000;
    // Cold century day with a 365-day vault coinflip history: 3.23M measured.
    uint256 internal constant DAILY_APPLY = 3_900_000;
    uint256 internal constant RNG_REQUEST = 2_500_000;
    // Century close: 32 deity renewals, stETH stake, unlock, recycle and seed arming.
    // Cold: 3.20M measured, empty sDGNRS pools.
    uint256 internal constant TRANSITION_CLOSE = 3_850_000;
    uint256 internal constant LEVEL_ONE_DRAW = 2_500_000;
    // Cold consolidation. Worst: x00 losing flip, skip mark plus the incinerator's 20-probe
    // book search and fresh FLIP credit, Decimator seal, growth seal, yield dump, keep roll:
    // 0.51M measured including intrinsic gas. The x00 winning flip (BAF reservation) measures 0.45M.
    uint256 internal constant POOL_CONSOLIDATION = 580_000;
    uint256 internal constant DAILY_PHASE_TAIL = 150_000;
    // Vault flip settlement at an x0 seal over the full 365-day claim window, auto-rebuy
    // carry and loss mint included. Cold: 1.28M measured.
    uint256 internal constant BAF_VAULT_SETTLE = 1_550_000;
    uint256 internal constant FOIL_PACK = 1_400_000;

    // One 50-entry field checkpoint, including cold initialization or final sealing.
    uint256 internal constant JACKPOT_BATTLE_DRAW = 3_300_000;
    uint256 internal constant TERMINAL_SETUP = 1_600_000;
    uint256 internal constant TERMINAL_TAIL = 250_000;
    uint256 internal constant TERMINAL_TALLY_RECORD = 25_000;
    uint256 internal constant TERMINAL_TALLY_FINAL = 900_000;
    uint256 internal constant TERMINAL_TALLY_TAIL = 100_000;
    uint256 internal constant TERMINAL_FINAL_SWEEP = 700_000;
    uint256 internal constant TERMINAL_SWEEP_TAIL = 80_000;

    // TICKET
    // Eight changed seat writes, a fresh seat word, cursor and release writes, return: 65k.
    uint256 internal constant TICKET_TAIL = 75_000;
    uint256 internal constant TICKET_SELECT_MAX = 110_000;
    // Skip with an owed write and a cold queue word: 11.7k measured.
    uint256 internal constant TICKET_SEAT_MAX = 17_000;
    // Eight persisted seats re-read on a resumed call: 45k measured (one shared queue word).
    uint256 internal constant TICKET_RELOAD_MAX = 100_000;
    // Four rare quadrants, 32 split appends each completing a fresh word: 0.95M measured.
    uint256 internal constant TICKET_ROUND_MAX = 1_150_000;
    // Fixed run cost including first live-bitmap initialization: 37k measured.
    uint256 internal constant TICKET_SOLO_BASE = 45_000;
    // A distinct trait completing a fresh word: 28.7k measured per entry.
    uint256 internal constant TICKET_ENTRY_MAX = 35_000;
    // One solo trait run: SOLO_BASE + 160 x ENTRY_MAX + TAIL = 5.72M.
    uint256 internal constant TICKET_SOLO_MAX_ENTRIES = 160;
    // One foil pack, the foil worker's 100k tail, its preamble and the call overhead.
    uint256 internal constant TICKET_FOIL_CALL_MAX = FOIL_PACK + 150_000;
    uint256 internal constant TICKET_CALL_OVERHEAD = 35_000;

    // AFK
    // Includes a failed full-stipend stETH attempt followed by normal eviction,
    // or a successful pull followed by the most expensive subscriber delivery.
    uint256 internal constant SUBSCRIBER_ITEM_GAS = 400_000;
    uint256 internal constant AFKING_STETH_PULL_GAS = 160_000;
    // Cold sDGNRS 100-pass purchase: 1.07M measured.
    uint256 internal constant SUBSCRIBER_WHALE_GAS = 1_300_000;
    uint256 internal constant SUBSCRIBER_TAIL_GAS = 150_000;
    uint256 internal constant AFKING_OPEN_GAS = 500_000;
    uint256 internal constant AFKING_SKIP_GAS = 20_000;
    uint256 internal constant AFKING_TAIL_GAS = 100_000;

    // BOX
    // Cold entry peaks: 1 box 0.33M, 10 boxes 1.00M, 50 boxes 2.19M, 100 boxes 3.15M. Entry cost
    // is concave in its box count (first-touch writes stop repeating), so the entry term carries
    // them: ENTRY + 100 x BOX = 4.05M.
    uint256 internal constant HUMAN_ENTRY_GAS = 1_300_000;
    uint256 internal constant HUMAN_BOX_GAS = 27_500;
    // Cold presale resolution: 0.09M measured; the closing entry's remainder transfer rides
    // inside its entry bound.
    uint256 internal constant HUMAN_PRESALE_GAS = 110_000;
    uint256 internal constant HUMAN_TAIL_GAS = 80_000;

    // BET
    // Cold: 197k measured for a 1-spin bet, 311k for 25 spins (11 capped wins, one sDGNRS award).
    uint256 internal constant DEGENERETTE_ETH_BASE_GAS = 240_000;
    // A capped winning spin adds about 14k; the per-spin term covers every spin winning.
    uint256 internal constant DEGENERETTE_ETH_SPIN_GAS = 14_000;
    uint256 internal constant DEGENERETTE_FLIP_BASE_GAS = 80_000;
    // About 4k measured per FLIP spin.
    uint256 internal constant DEGENERETTE_FLIP_SPIN_GAS = 5_000;
    // Record claim spin chain with a cold FLIP mint: 31.9k measured.
    uint256 internal constant DEGENERETTE_RECORD_GAS = 40_000;
    uint256 internal constant DEGENERETTE_SKIP_GAS = 20_000;
    uint256 internal constant DEGENERETTE_TAIL_GAS = 120_000;

    // DEC
    // Cold: 456k conservative sum of a 511-roll engine and the worst 200-place heap/frame.
    uint256 internal constant DECIMATOR_RUN_GAS_MAX = 550_000;
    // Up to 200 entries: 464k cold rank call, including any admitted payment tail.
    uint256 internal constant DECIMATOR_RANK_GAS_MAX = 500_000;
    // Cold: 80k measured for one payment, including the worker frame.
    uint256 internal constant DECIMATOR_PAYMENT_GAS_MAX = 100_000;
    uint256 internal constant DECIMATOR_WORK_TAIL_GAS = 80_000;
    // Scale witness: cold saved-board/heap item plus 511-roll engine totals 456,226.
    // Keep the established generated admission; checkpoint/return tail is separate.
    uint256 internal constant DECIMATOR_GENERATED_GAS_MAX = 469_000;
    // Opposite-phase stratum: 4,973 incremental cold gas, rounded to the next 1k.
    uint256 internal constant DECIMATOR_SAMPLE_SKIP_GAS_MAX = 5_000;
    // Cold four-cohort initialization including the worker frame: 59,983 gas.
    uint256 internal constant DECIMATOR_PLAN_GAS_MAX = 60_000;

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
    // One eight-award BAF group. Worst: a far-future pair group with four cold claimable
    // credits and eight rolls on eight levels, 0.90M measured; whale-pass legs cost less and the
    // cost does not grow with the round count.
    uint256 internal constant BAF_AWARD_GROUP = 1_080_000;
    // Cursor write and the meter's close after the last admitted group: 60k measured.
    uint256 internal constant BAF_AWARD_TAIL = 72_000;

    // CRAPS
    uint256 internal constant CRAPS_SEAT_GAS_MAX = 1_650_000;
    // One cold distinct creditFlipBatch recipient: 25.9k measured.
    uint256 internal constant CRAPS_CREDIT_GAS_MAX = 32_000;
    uint256 internal constant CRAPS_SETTLE_TAIL_GAS = 200_000;
    uint256 internal constant CRAPS_WORK_TAIL_GAS = 60_000;
    uint256 internal constant CRAPS_MAINTENANCE_GAS_MAX = 240_000;
    uint256 internal constant CRAPS_REFUND_GAS_MAX = 65_000;
    uint256 internal constant CRAPS_SWEEP_TAIL_GAS = 130_000;

    // GROWTH
    // Winners paid per Parimutuel settlement call, credited through one creditFlipBatch.
    uint256 internal constant GROWTH_SETTLE_WINNERS = 100;
    // Cold chunk of GROWTH_SETTLE_WINNERS distinct winners on fresh Coinflip lanes (the call, packed
    // ID reads, cursor write, events and batch credit): 2.65M measured inside mineFlip.
    uint256 internal constant GROWTH_SETTLE_GAS = 3_200_000;

    // REDEEM
    // Cold beneficiary without a lootbox leg: 0.23M measured (pre-batch; re-measure).
    uint256 internal constant REDEMPTION_BASE_GAS = 500_000;
    uint256 internal constant REDEMPTION_TAIL_GAS = 80_000;
    // A claim's lootbox leg resolves as ONE box order of min(ceil(leg / UNIT), BOXES_MAX)
    // equal custom boxes, admitted like a human entry: HUMAN_ENTRY_GAS + boxes * HUMAN_BOX_GAS.
    uint256 internal constant REDEMPTION_BOX_UNIT = 1 ether;
    uint256 internal constant REDEMPTION_BOXES_MAX = 20;
}
