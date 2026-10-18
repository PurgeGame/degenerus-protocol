// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Cold-path admission bounds for Osaka and Glamsterdam, including new-state gas.
/// @dev No state reservoir is assumed. Bounds include the named operation; callers reserve
///      checkpoint/return tails separately. Measured witnesses or conservative component
///      sums carry about 20% margin; fixed reserves are identified beside their constants.
///      Continuations use caller calibration; first mandatory progress bypasses estimates.
///      Revalidate after operation, compiler or gas-schedule changes.
library MineFlipGasBounds {
    // Dispatch reads/arithmetic; the enclosing worker reserves its own checkpoint tail.
    uint256 internal constant ENGINE_BOUNDARY = 100_000;
    // Return and one fresh caller credit; native single-credit call: 130.7k.
    uint256 internal constant ENGINE_RETURN = 200_000;
    // Cold 29-day gap: 683.6k including state gas.
    uint256 internal constant DAILY_GAP = 850_000;
    // Cold century day with 730-day vault history: 5.954M including 25 fresh slots.
    uint256 internal constant DAILY_APPLY = 7_200_000;
    // Cold midday: 530.7k plus 97.9k coordinator execution-floor padding, then margin.
    uint256 internal constant RNG_MIDDAY_REQUEST = 800_000;
    // Cold daily request: 2.632M plus 97.9k coordinator execution-floor padding.
    // Redemption close is additional; post-fulfillment work has separate checkpoints.
    uint256 internal constant RNG_DAILY_REQUEST = 3_400_000;
    // Nonempty close plus mixed ETH/stETH pull: 443.5k, including proxy and
    // 10k balance / 40k transfer execution padding. No historical coinflip walk here.
    uint256 internal constant RNG_REDEMPTION_CLOSE = 550_000;
    // Conservative external-request envelope; terminal requests never close redemption.
    uint256 internal constant RNG_TERMINAL_REQUEST = 2_500_000;
    // Cold century close, 32 deity renewals, stake, unlock, recycle and seed: 4.762M.
    uint256 internal constant TRANSITION_CLOSE = 5_800_000;
    // Cold level-one draw with 51 fresh slots: 6.240M.
    uint256 internal constant LEVEL_ONE_DRAW = 7_500_000;
    // Cold losing x00 flip, incinerator search, seals and yield/keep roll: 1.368M.
    uint256 internal constant POOL_CONSOLIDATION = 1_650_000;
    // Phase cursor, caller frame and return reserve.
    uint256 internal constant DAILY_PHASE_TAIL = 150_000;
    // Full 730-day vault claim window with auto-rebuy and loss mint: 2.868M.
    uint256 internal constant BAF_VAULT_SETTLE = 3_500_000;
    // Forced all-gold grand prize with distinct traits and fresh buffer: 2.263M.
    uint256 internal constant FOIL_PACK = 3_000_000;
    // One full 50-entry field checkpoint, cold initialization or final seal: 3.870M.
    uint256 internal constant JACKPOT_BATTLE_DRAW = 4_700_000;
    // Cold terminal setup: 1.282M including new-slot state gas.
    uint256 internal constant TERMINAL_SETUP = 1_600_000;
    // Terminal checkpoint and return reserve.
    uint256 internal constant TERMINAL_TAIL = 250_000;
    // Record body; the fresh tally cursor is covered by TALLY_TAIL.
    uint256 internal constant TERMINAL_TALLY_RECORD = 25_000;
    // Full 256-record scan plus immediate 30-refund setup: 1.878M.
    uint256 internal constant TERMINAL_TALLY_FINAL = 2_300_000;
    // Fresh cursor (110.1k) plus 80k frame, with margin.
    uint256 internal constant TERMINAL_TALLY_TAIL = 250_000;
    // Cold final sweep: 547.3k.
    uint256 internal constant TERMINAL_FINAL_SWEEP = 700_000;
    // Sweep return reserve.
    uint256 internal constant TERMINAL_SWEEP_TAIL = 80_000;
    // Eight changed seats, a fresh seat word, cursor/release writes and return: <=209.8k.
    uint256 internal constant TICKET_TAIL = 260_000;
    // Cold selection reads and arithmetic; no materialization writes.
    uint256 internal constant TICKET_SELECT_MAX = 110_000;
    // Cold marginal skip 15.1k plus two distinct cold reads (4.2k), with margin.
    uint256 internal constant TICKET_SEAT_MAX = 25_000;
    // Eight persisted seats re-read on resume: 45k; read-only allowance.
    uint256 internal constant TICKET_RELOAD_MAX = 100_000;
    // Four rare quadrants, fresh split appends: full cold worker 4.175M.
    uint256 internal constant TICKET_ROUND_MAX = 5_100_000;
    // Fresh live-bitmap initialization differential: 204.9k.
    uint256 internal constant TICKET_SOLO_BASE = 250_000;
    // Distinct trait completing a fresh word: cold marginal 124.1k including state gas.
    uint256 internal constant TICKET_ENTRY_MAX = 150_000;
    // One solo run: 250k + 32 x 150k + 260k tail = 5.31M reserved.
    uint256 internal constant TICKET_SOLO_MAX_ENTRIES = 32;
    // One foil pack plus its checkpoint, worker preamble and call overhead.
    uint256 internal constant TICKET_FOIL_CALL_MAX = FOIL_PACK + 200_000;
    // Delegatecall and worker dispatch reserve.
    uint256 internal constant TICKET_CALL_OVERHEAD = 35_000;
    // Cold stETH-funded subscriber delivery: 472.3k. Dependency failure reverts.
    uint256 internal constant SUBSCRIBER_ITEM_GAS = 600_000;
    // Cold sDGNRS 1,000-pass purchase 2.378M plus the AFKing top-up 20.2k.
    uint256 internal constant SUBSCRIBER_WHALE_GAS = 2_800_000;
    // Subscriber cursor, flush and return reserve, including fresh state.
    uint256 internal constant SUBSCRIBER_TAIL_GAS = 250_000;
    // Cold AFKing opening: 776.2k including EV allowance accounting.
    uint256 internal constant AFKING_OPEN_GAS = 950_000;
    // Empty-run reads and cursor arithmetic.
    uint256 internal constant AFKING_SKIP_GAS = 20_000;
    // AFKing checkpoint and return reserve.
    uint256 internal constant AFKING_TAIL_GAS = 100_000;
    // One atomic human order, including a cold fresh EV allowance read-modify-write.
    // Forced 100-box ETH-spin/recirculation component envelope: 12.878M plus
    // a fresh allowance RMW (110.1k) and frame. ENTRY + 100 x BOX reserves 15.7M.
    // This rare 100-box operation is an accepted exception to the 10M checkpoint target.
    uint256 internal constant HUMAN_ENTRY_GAS = 3_200_000;
    // Per-box term; ENTRY covers concave first-touch costs and the EV allowance.
    uint256 internal constant HUMAN_BOX_GAS = 125_000;
    // Human order cursor and return reserve.
    uint256 internal constant HUMAN_TAIL_GAS = 80_000;
    // Cold first order with a fresh WWXRP consolation: <=134.1k including state gas.
    uint256 internal constant DEGENESIS_WWXRP_GAS = 165_000;
    // Coin-credit order with the next order's cold decode and frame: <=37.7k.
    uint256 internal constant DEGENESIS_FLIP_CREDIT_GAS = 46_000;
    // Cold capped pass order, fresh CrapsBattle credit, rest's flush apart: <=144.2k.
    uint256 internal constant DEGENESIS_FLIP_PASS_GAS = 175_000;
    // Cold first sDGNRS award to a fresh two-link payee: <=165.8k; fallback 147.3k.
    uint256 internal constant DEGENESIS_DGNRS_GAS = 200_000;
    // Fresh distinct creditFlipBatch recipient: cold marginal <=113.4k including state gas.
    uint256 internal constant DEGENESIS_FLUSH_PER_CREDIT = 140_000;
    // Flush frame, seventh close with the burn, one decode and return: <=100.9k.
    uint256 internal constant DEGENESIS_TAIL_GAS = 125_000;
    // Degenesis day-close branch with a fresh seat-draw credit: <=177.2k including state gas.
    uint256 internal constant DEGENESIS_DAY_CLOSE = 215_000;
    // Seven cold splits, fresh budget, pool and pricing slots: 472.2k; seven closes and burn 98.3k.
    uint256 internal constant DEGENESIS_REQUEST_GAS = 570_000;
    // Seven-cohort split, release and active clear: 367.8k peak with the transient budget slot.
    uint256 internal constant DEGENESIS_TERMINAL_GAS = 450_000;
    // Bound day's word into a fresh degenesisWord slot, with the gate reads: 120.4k.
    uint256 internal constant DEGENESIS_WORD_COPY_GAS = 145_000;
    // Forced cold winning/recirculating one-spin bet: 991.7k.
    uint256 internal constant DEGENERETTE_ETH_BASE_GAS = 1_200_000;
    // A capped winning spin adds at most 14k; base covers first-touch writes.
    uint256 internal constant DEGENERETTE_ETH_SPIN_GAS = 14_000;
    // Cold base 113.1k plus two fresh FLIP slots (195.9k), with margin.
    uint256 internal constant DEGENERETTE_FLIP_BASE_GAS = 400_000;
    // About 4k per additional FLIP spin.
    uint256 internal constant DEGENERETTE_FLIP_SPIN_GAS = 5_000;
    // Fresh cold FLIP mint 238.6k plus 40k record frame, with margin.
    uint256 internal constant DEGENERETTE_RECORD_GAS = 350_000;
    // Bet cursor, checkpoint and return reserve.
    uint256 internal constant DEGENERETTE_TAIL_GAS = 150_000;
    // Conservative sum: 286.2k heap/frame plus the full 511-roll engine (344.1k).
    uint256 internal constant DECIMATOR_RUN_GAS_MAX = 800_000;
    // Cold full rank checkpoint: 448.9k.
    uint256 internal constant DECIMATOR_RANK_GAS_MAX = 550_000;
    // Cold payment including worker frame: 82.6k.
    uint256 internal constant DECIMATOR_PAYMENT_GAS_MAX = 100_000;
    // Cold isolated finalization worker: 74.7k, with margin.
    uint256 internal constant DECIMATOR_FINAL_GAS_MAX = 90_000;
    // Decimator checkpoint and return reserve.
    uint256 internal constant DECIMATOR_WORK_TAIL_GAS = 80_000;
    // Saved-board/heap item 388.4k plus full 511-roll engine 344.1k, with margin.
    uint256 internal constant DECIMATOR_GENERATED_GAS_MAX = 900_000;
    // Opposite-phase stratum: cold marginal 12.2k.
    uint256 internal constant DECIMATOR_SAMPLE_SKIP_GAS_MAX = 15_000;
    // Cold four-cohort initialization including worker frame: 102.0k.
    uint256 internal constant DECIMATOR_PLAN_GAS_MAX = 125_000;
    // Conservative setup, gold grand prize, arming and fresh budget sum: 596.0k.
    uint256 internal constant JACKPOT_SETUP_GAS = 750_000;
    // Read-only winner planning and worker frame.
    uint256 internal constant JACKPOT_PLAN_GAS = 120_000;
    // Final jackpot accounting and return reserve.
    uint256 internal constant JACKPOT_FINAL_GAS = 150_000;
    // Jackpot checkpoint, worker frame and return reserve.
    uint256 internal constant JACKPOT_TAIL_GAS = 180_000;
    // Registered claimable slot is nonzero: 17.3k padded draw + 7.1k repricing.
    uint256 internal constant JACKPOT_ETH_WINNER_GAS_MAX = 30_000;
    // First-group pass award, fresh gold arm and accounting: 234.2k, with margin.
    uint256 internal constant JACKPOT_ETH_FIRST_GROUP_GAS = 300_000;
    // Canonical eight-position sampler group; its first group reserves another 300k.
    uint256 internal constant JACKPOT_ETH_AWARD_CHUNK = 8;
    // One ticket-leg pass recipient: bucket draw, cold claim write and event.
    uint256 internal constant JACKPOT_PASS_AWARD_GAS = 100_000;
    // Cold draw: 3.4k per winner; one group shares a packed bucket word.
    uint256 internal constant JACKPOT_TICKET_DRAW_GAS_MAX = 4_200;
    // Fresh recipient may create three slots. A full single-award call is 414.1k;
    // AWARD + DRAW + TAIL = 534.2k covers it with margin.
    uint256 internal constant JACKPOT_TICKET_AWARD_GAS_MAX = 350_000;
    // Canonical eight-position sampler group: total reserve with tail 3.014M.
    uint256 internal constant JACKPOT_TICKET_AWARD_CHUNK = 8;
    // Cold eight-award far-future pair group: 1.980M, independent of round count.
    uint256 internal constant BAF_AWARD_GROUP = 2_400_000;
    // 60k cursor/frame plus five changed-slot repricing deltas (35.5k), with margin.
    uint256 internal constant BAF_AWARD_TAIL = 120_000;
    // Conservative seat frame 369.7k plus full dice engine 823.0k, with margin.
    uint256 internal constant CRAPS_SEAT_GAS_MAX = 1_650_000;
    // Fresh distinct creditFlipBatch recipient: cold marginal 113.7k, state included.
    uint256 internal constant CRAPS_CREDIT_GAS_MAX = 140_000;
    // Craps settlement checkpoint, flush frame and return reserve.
    uint256 internal constant CRAPS_SETTLE_TAIL_GAS = 200_000;
    // Craps work checkpoint and return reserve.
    uint256 internal constant CRAPS_WORK_TAIL_GAS = 60_000;
    // Cold maintenance: 515.9k.
    uint256 internal constant CRAPS_MAINTENANCE_GAS_MAX = 650_000;
    // Cold refund: 179.6k.
    uint256 internal constant CRAPS_REFUND_GAS_MAX = 220_000;
    // Two fresh cursor words (220.1k) plus 25k frame, with margin.
    uint256 internal constant CRAPS_SWEEP_TAIL_GAS = 300_000;
    // Growth round advance reads and cursor arithmetic; persistence uses GROWTH_TAIL_GAS.
    uint256 internal constant GROWTH_ROUND_ADVANCE_GAS = 10_000;
    // Read and calculate one winner's payout; its FLIP credit is reserved separately.
    uint256 internal constant GROWTH_WINNER_GAS = 10_000;
    // Growth cursor, credit-call frame and return reserve, excluding per-recipient credits.
    uint256 internal constant GROWTH_TAIL_GAS = 30_000;
    // Bound the fresh-state cost of a single growth credit flush.
    uint256 internal constant GROWTH_CREDIT_BATCH_SIZE = 32;
    // Cold beneficiary without a lootbox leg: 496.3k including fresh state.
    uint256 internal constant REDEMPTION_BASE_GAS = 600_000;
    // Redemption cursor and return reserve.
    uint256 internal constant REDEMPTION_TAIL_GAS = 100_000;
    // Cold batch resolution before its first claim: 69.2k, with margin.
    uint256 internal constant REDEMPTION_RESOLVE_GAS = 85_000;
    // Zero-token entry: packed queue read and existing cursor update, with margin.
    uint256 internal constant REDEMPTION_SKIP_GAS = 20_000;
    // A lootbox leg is ONE order of min(ceil(leg / UNIT), BOXES_MAX) custom boxes,
    // priced by HUMAN_ENTRY_GAS + boxes x HUMAN_BOX_GAS, including EV accounting.
    uint256 internal constant REDEMPTION_BOX_UNIT = 1 ether;
    // Maximum boxes per redemption order.
    uint256 internal constant REDEMPTION_BOXES_MAX = 20;
    // Loan/list reads, ownership and main-ID writes, sDGNRS burn, deletion and event.
    // Cold full six-account deity family: 471.7k vs BASE + 6 x SUB + DEITY = 600k.
    uint256 internal constant LOAN_SEIZE_BASE = 160_000;
    // Per family account: active-run finalization with Quests call and walk reads.
    uint256 internal constant LOAN_SEIZE_SUB = 50_000;
    // One deity per family: full 32-symbol scan and cold DeityPass.seize.
    uint256 internal constant LOAN_SEIZE_DEITY = 140_000;
    // Cursor and pending-flag writes, game over's loan cursor, event and return.
    uint256 internal constant LOAN_SEIZE_TAIL = 60_000;
    // Game over's loan scan: one due level's cold count read and step.
    uint256 internal constant LOAN_TERMINAL_LEVEL = 10_000;
}
