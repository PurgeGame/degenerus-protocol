// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

/// @notice Cold-path admission bounds for Osaka and Glamsterdam, including new-state gas.
/// @dev No state reservoir is assumed unless a constant says otherwise. Bounds include the named
///      operation unless the constant's comment names a larger case or counts the bound together
///      with its tail; callers reserve checkpoint/return tails separately. Measured witnesses or
///      conservative component sums carry margin, about 20% for most and down to about 10%; fixed
///      reserves are identified beside their constants.
///      Continuations use caller calibration; first mandatory progress bypasses estimates.
library MineFlipGasBounds {
    // Fixed 32-winner direct round. Osaka cold worst 2.320M. Glamsterdam: at most 1.989M execution
    // plus 97,920 per new slot. Past a buffer's high-water mark a round writes at most 24 new
    // words: at most 4.34M, measured worst 3.58M. A common round over a never-used buffer writes
    // 32 new headers and words, measured 3.627M. Rounds with more new slots (at most 80, 9.823M)
    // need a reservoir, a multiplier or a smaller call.
    uint256 internal constant TICKET_DIRECT_ROUND_GAS_MAX = 4_500_000;
    // Eight packed winner draws, padding redraws, deity cache and batch event.
    uint256 internal constant TICKET_DIRECT_GROUP_GAS = 65_000;
    // Dispatch, decoding and checkpoint normalization; selection is admitted separately.
    uint256 internal constant ENGINE_BOUNDARY = 200_000;
    // Selection plus native-balance admission: 50k minimum + 200k read reserve + 10k frame,
    // caller-credit lookup and cold selection reads, with margin.
    uint256 internal constant ENGINE_SELECTION = 450_000;
    // Return and one caller credit; native fresh/spill credit transactions: 138.2k/153.6k
    // Glamsterdam, 49.8k/57.9k Osaka.
    uint256 internal constant ENGINE_RETURN = 200_000;
    // Cold century word apply: 3.345M Glamsterdam with 23 new slots; 1.231M Osaka.
    uint256 internal constant DAILY_APPLY = 7_200_000;
    // Cold request/credit witness: 609.0k Glamsterdam. Selection reads the subscription balance
    // (a pending craps window waives it), so on every mineRun path the request reads nothing and
    // admits at its own 1M floor and reserve; retain forwarding and frame headroom.
    uint256 internal constant RNG_MIDDAY_REQUEST = 2_200_000;
    // Native daily witnesses: 1.55M normal, 1.60M refill (EIP-170 profile, Amsterdam; Osaka
    // 0.55M/0.59M). Refill admission: VRF_DAILY_REFILL_TAIL + 250k funding minimum + 45k value
    // frame, 3.35M. Coordinator calls and the stETH read forward all gas above the tails; both
    // reads admit at a 50k minimum.
    // Redemption close is additional; post-fulfillment work has separate checkpoints.
    // GNRUS's purchase-phase-end step (one flip settlement walk and an ordinary FLIP ticket
    // purchase burning wallet FLIP, then claimable, then carry) rides only a request that can end
    // the purchase phase; the miner admission and the refill tail add it for exactly those requests.
    // Worst measured (x99 with WWXRP entry, 35 days): 0.502M Osaka, 1.626M Glamsterdam total.
    uint256 internal constant GNRUS_TICKET_PURCHASE = 2_125_000;
    uint256 internal constant RNG_DAILY_REQUEST = 4_400_000;
    // Rest of a fresh daily request after its refill. Measured 1.546M (refill day, funding call
    // and request included); plus the Degenesis-pricing and redemption-close extras admitted on top.
    uint256 internal constant VRF_DAILY_REFILL_TAIL = 1_800_000 + DEGENESIS_REQUEST_GAS + RNG_REDEMPTION_CLOSE;
    // Nonempty redemption close: 129.9k Glamsterdam. The close moves no ETH or stETH. No
    // historical coinflip walk here.
    uint256 internal constant RNG_REDEMPTION_CLOSE = 550_000;
    // Terminal request: cold cohort setup and the VRF request with its 500k request reserve, with
    // margin; excludes redemption close.
    uint256 internal constant RNG_TERMINAL_REQUEST = 3_100_000;
    // Cold century close including the stake and balance reads and rollback frame: reachable
    // worst 1.725M Glamsterdam; a fixture that over-counts the work, 4.859M.
    uint256 internal constant TRANSITION_CLOSE = 6_200_000;
    // Cold level-one draw: 6.361M Glamsterdam with 52 fresh slots, the most a draw creates; the
    // unit is 1.753M Osaka.
    uint256 internal constant LEVEL_ONE_DRAW = 7_700_000;
    // Cold x00 consolidation (flip, incinerator search, seals and yield/keep roll): at most
    // 1.215M Glamsterdam (x00 win with VRF funding, 8 new slots), 0.45M Osaka. Funding admission
    // at the call (work spent + VRF_LEVEL_FUND_TAIL + 250k minimum + 45k frame): at most 1.781M,
    // within this plus DAILY_PHASE_TAIL.
    uint256 internal constant POOL_CONSOLIDATION = 1_650_000;
    // Level entry after its VRF top-up: the yield split, the rest of the consolidation and the
    // phase tail. At most 751.6k Glamsterdam (x00 win), with margin.
    uint256 internal constant VRF_LEVEL_FUND_TAIL = 1_000_000;
    // 150k phase tail + bounded balance 60,794 and allocation/frame margin.
    uint256 internal constant DAILY_PHASE_TAIL = 250_000;
    // Conservative full-walk envelope (up to 90 resolved days) for the 45-day Vault
    // checkpoint and x0 seal, including the Game stamp.
    uint256 internal constant BAF_VAULT_SETTLE = 3_500_000;
    // Forced all-gold grand prize with distinct traits and fresh buffer: 2.263M.
    uint256 internal constant FOIL_PACK = 3_000_000;
    // One full 50-entry field checkpoint, cold initialization or final seal: 3.870M.
    uint256 internal constant JACKPOT_BATTLE_DRAW = 4_700_000;
    // Cold terminal setup 1.282M + bounded balance 60,794, including new-slot state gas.
    uint256 internal constant TERMINAL_SETUP = 1_700_000;
    // Terminal checkpoint and return reserve.
    uint256 internal constant TERMINAL_TAIL = 250_000;
    // Record body; the fresh tally cursor is covered by TERMINAL_TALLY_TAIL.
    uint256 internal constant TERMINAL_TALLY_RECORD = 25_000;
    // Full 256-record scan plus immediate 30-refund setup: 1.878M.
    uint256 internal constant TERMINAL_TALLY_FINAL = 2_300_000;
    // Fresh cursor (110.1k) plus 80k frame, with margin.
    uint256 internal constant TERMINAL_TALLY_TAIL = 250_000;
    // Cold sweep with GNRUS's cash-outs: at most 510.5k Glamsterdam, 291.6k Osaka. Plus the
    // shutdown call (1M + 250k tail kept out of Admin's allowance + 15,873 EIP-150 + 10k frame;
    // as part of the first unit its admission checks only 1,025,873), with margin. Admin's
    // cancellation admission (450k + 50k tail + 10k) fits in 1M.
    // The sweep is always its transaction's mandatory first unit (Terminal runs only first, 30 days
    // after the payout), so it runs with all gas, GNRUS's sDGNRS/DGNRS cash-out included.
    uint256 internal constant TERMINAL_FINAL_SWEEP = 2_200_000;
    // Sweep return reserve.
    uint256 internal constant TERMINAL_SWEEP_TAIL = 80_000;
    // After the sweep's stETH read: the three payout legs (403.2k Glamsterdam when every stETH leg
    // writes a fresh balance) and the VRF shutdown call (1M floor + 250k allowance tail + 15,873
    // EIP-150 + 10k frame; its first-unit admission checks only 1,025,873): 1.679M Glamsterdam
    // together. The shutdown terms are fixed, so the margin is on the measured legs, about 30%.
    // GNRUS's cash-outs after the legs are outside this
    // reserve: each admits GNRUS_CASHOUT_BURN before its call, and the first-unit sweep carries
    // all the transaction's gas.
    uint256 internal constant TERMINAL_SWEEP_AFTER_READ = 1_800_000;
    // One GNRUS cash-out burn (sDGNRS or wrapped DGNRS) after the sinks are paid, admitted before
    // its call so a refused burn is never a gas shortage. Worst cold burn: an empty Game, so the
    // stETH leg writes GNRUS's balance fresh, 198,449 at Glamsterdam with the mock token. The real
    // Lido leg into an empty balance alone is 159,469 (mainnet fork). Their sum with 20% margin.
    uint256 internal constant GNRUS_CASHOUT_BURN = 450_000;
    // Eight changed seats, a fresh seat word, cursor/release writes and return: <=209.8k.
    uint256 internal constant TICKET_TAIL = 260_000;
    // Cold selection reads and arithmetic; no materialization writes. Amsterdam, no reservoir: 150,198.
    uint256 internal constant TICKET_SELECT_MAX = 165_000;
    // Cold marginal skip 15.1k plus two distinct cold reads (4.2k), with margin.
    uint256 internal constant TICKET_SEAT_MAX = 25_000;
    // Eight persisted seats re-read on resume: 45k; read-only allowance.
    uint256 internal constant TICKET_RELOAD_MAX = 100_000;
    // Four rare quadrants, fresh split appends: full cold round 4.291M Glamsterdam, 1.073M
    // Osaka.
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
    // Cold delivery + atomic 1M pull + 15,873 EIP-150 + 10k frame, with margin.
    uint256 internal constant SUBSCRIBER_ITEM_GAS = 1_700_000;
    // Cold sDGNRS 1,000-pass purchase plus the AFKing top-up (20.4k): 2.398M Glamsterdam, no
    // reservoir.
    uint256 internal constant SUBSCRIBER_WHALE_GAS = 2_800_000;
    // Subscriber cursor, flush and return reserve, including fresh state.
    uint256 internal constant SUBSCRIBER_TAIL_GAS = 250_000;
    // Cold AFKing opening, forced ETH spin with a recirculated box and its EV allowance
    // accounting.
    uint256 internal constant AFKING_OPEN_GAS = 950_000;
    // Empty-run reads and cursor arithmetic.
    uint256 internal constant AFKING_SKIP_GAS = 20_000;
    // AFKing checkpoint and return reserve.
    uint256 internal constant AFKING_TAIL_GAS = 100_000;
    // One atomic human order, including a cold fresh EV allowance read-modify-write. Forced
    // worst 100-box order: every box a winning ETH spin, the recirculated boxes queueing tickets
    // on all 51 levels; 9.86M Osaka for the whole transaction. At Glamsterdam each of the 51
    // queue appends can open a new queue word and a new wallet's owed words are new, 97,920
    // each. ENTRY + 100 x BOX reserves 15.7M. This rare 100-box operation is an accepted
    // Glamsterdam state-gas exception to the 10M checkpoint target.
    uint256 internal constant HUMAN_ENTRY_GAS = 3_200_000;
    // Per-box term; ENTRY covers concave first-touch costs and the EV allowance.
    uint256 internal constant HUMAN_BOX_GAS = 125_000;
    // Human order cursor and return reserve.
    uint256 internal constant HUMAN_TAIL_GAS = 80_000;
    /// @dev Degenesis dispatch, expiry, three boon deliveries, return and companion event.
    ///      Native full-order addition: <=470,886 no-reservoir / 90,562 reservoir execution.
    ///      A 20% margin rounds up to 600k; primary, coin-flush and tail terms stay separate.
    uint256 internal constant DEGENESIS_BOON_GAS = 600_000;
    // Cold first order with a fresh WWXRP consolation: <=134.1k including state gas.
    uint256 internal constant DEGENESIS_WWXRP_GAS = 165_000;
    // Coin-credit order with the next order's cold decode and frame: <=37.7k.
    uint256 internal constant DEGENESIS_FLIP_CREDIT_GAS = 46_000;
    // Cold capped pass order, fresh CrapsBattle credit, rest's flush apart: <=144.2k.
    uint256 internal constant DEGENESIS_FLIP_PASS_GAS = 175_000;
    // Cold first sDGNRS award to a fresh two-link payee: <=165.8k; fallback 147.3k.
    uint256 internal constant DEGENESIS_DGNRS_GAS = 200_000;
    // Live-collision recipient: native cold marginal 129,647, state gas included.
    // 160k retains >23% margin; the ordinary fresh recipient is cheaper.
    uint256 internal constant DEGENESIS_FLUSH_PER_CREDIT = 160_000;
    // Flush frame, seventh close with AFKing excess/events and burn, decode/return: <=118.1k.
    uint256 internal constant DEGENESIS_TAIL_GAS = 142_000;
    // Degenesis day-close branch with a fresh seat-draw credit: <=177.2k including state gas.
    uint256 internal constant DEGENESIS_DAY_CLOSE = 215_000;
    // Fixture with six cold four-way splits (a request splits at most one), one empty close and
    // pricing: 484.9k Glamsterdam with three new slots; 148.0k Osaka. A request closes every
    // sealed empty cohort ahead of the next one it prices; the seventh close also burns the
    // leftover inventory.
    uint256 internal constant DEGENESIS_REQUEST_GAS = 700_000;
    // Fixture with seven cold four-way splits (terminal setup splits at most the current day's
    // cohort), release and active clear: 282.8k Glamsterdam with one new slot; 107.9k Osaka.
    uint256 internal constant DEGENESIS_TERMINAL_GAS = 580_000;
    // Bound day's word into a fresh degenesisWord slot, with the gate reads: 120.4k.
    uint256 internal constant DEGENESIS_WORD_COPY_GAS = 145_000;
    // Forced cold winning/recirculating one-spin bet.
    uint256 internal constant DEGENERETTE_ETH_BASE_GAS = 1_200_000;
    // Each further capped winning spin, with the sDGNRS pool read and transfer of a spin scoring
    // 7 or more; base covers first-touch writes.
    uint256 internal constant DEGENERETTE_ETH_SPIN_GAS = 14_000;
    // Cold base plus two fresh FLIP slots, with margin.
    uint256 internal constant DEGENERETTE_FLIP_BASE_GAS = 400_000;
    // Each additional FLIP spin.
    uint256 internal constant DEGENERETTE_FLIP_SPIN_GAS = 5_000;
    // Fresh cold FLIP mint plus 40k record frame, with margin.
    uint256 internal constant DEGENERETTE_RECORD_GAS = 350_000;
    // After the last admitted bet: the last owner's FLIP mint and claimable credit, the pool
    // write-back, the bet cursor, the RNG completion check and return.
    uint256 internal constant DEGENERETTE_TAIL_GAS = 150_000;
    // Heap/frame work plus the full 511-roll engine (351.7k Glamsterdam, 351.3k Osaka).
    uint256 internal constant DECIMATOR_RUN_GAS_MAX = 800_000;
    // Cold full rank checkpoint.
    uint256 internal constant DECIMATOR_RANK_GAS_MAX = 550_000;
    // Cold payment including worker frame.
    uint256 internal constant DECIMATOR_PAYMENT_GAS_MAX = 100_000;
    // Cold isolated finalization worker, with margin.
    uint256 internal constant DECIMATOR_FINAL_GAS_MAX = 90_000;
    // Decimator checkpoint and return reserve. A round's first cursor checkpoint creates its second
    // slot: 110.0k Glamsterdam with the skipped stratum before it.
    uint256 internal constant DECIMATOR_WORK_TAIL_GAS = 125_000;
    // Saved-board/heap item plus the full 511-roll engine: largest cold item with worker frame
    // 725.6k Glamsterdam, 483.1k Osaka.
    uint256 internal constant DECIMATOR_GENERATED_GAS_MAX = 900_000;
    // Opposite-phase stratum: cold marginal 12.3k Glamsterdam, 5.1k Osaka.
    uint256 internal constant DECIMATOR_SAMPLE_SKIP_GAS_MAX = 15_000;
    // Cold four-cohort initialization including worker frame: 89.0k Glamsterdam, 59.8k Osaka.
    uint256 internal constant DECIMATOR_PLAN_GAS_MAX = 125_000;
    // Conservative sum of setup, gold grand prize, fresh budget and the golden-ticket arm, which
    // itself runs in the first ETH group: 596.0k.
    uint256 internal constant JACKPOT_SETUP_GAS = 750_000;
    // Read-only winner planning and worker frame.
    uint256 internal constant JACKPOT_PLAN_GAS = 120_000;
    // Final jackpot accounting and return reserve.
    uint256 internal constant JACKPOT_FINAL_GAS = 150_000;
    // Jackpot checkpoint, worker frame and return reserve.
    uint256 internal constant JACKPOT_TAIL_GAS = 180_000;
    // Registered claimable slot is nonzero: 17.3k padded draw + 7.1k repricing.
    uint256 internal constant JACKPOT_ETH_WINNER_GAS_MAX = 30_000;
    // First-group pass award, fresh gold arm and accounting, with margin.
    uint256 internal constant JACKPOT_ETH_FIRST_GROUP_GAS = 300_000;
    // Canonical eight-position sampler group; its first group reserves another 300k.
    uint256 internal constant JACKPOT_ETH_AWARD_CHUNK = 8;
    // One ticket-leg pass recipient: bucket draw, cold claim write and event.
    uint256 internal constant JACKPOT_PASS_AWARD_GAS = 100_000;
    // Cold draw: 3.4k per winner; one group shares a packed bucket word.
    uint256 internal constant JACKPOT_TICKET_DRAW_GAS_MAX = 4_200;
    // A fresh recipient on a never-used queue creates three slots: the award 348.3k Glamsterdam,
    // 364.4k with a deep draw. AWARD + DRAW + TAIL = 609.2k for a single-award call.
    uint256 internal constant JACKPOT_TICKET_AWARD_GAS_MAX = 425_000;
    // Canonical eight-position sampler group: total reserve with tail 3.614M.
    uint256 internal constant JACKPOT_TICKET_AWARD_CHUNK = 8;
    // Cold eight-award far-future group (4 ETH, 8 ticket rolls), independent of round count:
    // 708.3k Osaka, 2.183M Glamsterdam with 16 new slots. Each roll that lands on a never-used
    // level queue creates one more slot (97,920); all eight give 2.967M.
    uint256 internal constant BAF_AWARD_GROUP = 3_600_000;
    // 60k cursor/frame plus five changed-slot repricing deltas (35.5k), with margin. Closing a
    // bracket whose board never took an entry creates its level word (one new slot, 97,920 state
    // gas); the close follows only the three-award head group, whose unused BAF_AWARD_GROUP covers it.
    uint256 internal constant BAF_AWARD_TAIL = 120_000;
    // Cold final-seat body, 1,111-roll engine and real award/record callees:
    // native no-reservoir component envelope 2.298M, with >20% margin.
    uint256 internal constant CRAPS_SEAT_GAS_MAX = 2_800_000;
    // Live-collision recipient: native cold marginal 129,647, state gas included.
    // Shared by Craps, jackpot-battle and growth flush admission; >23% margin.
    uint256 internal constant CRAPS_CREDIT_GAS_MAX = 160_000;
    // Craps settlement checkpoint, flush frame and return reserve, the post-batch day booking (a new
    // day-ring word on its index's first use) and, on a jackpot field, the high-roller reserve walk
    // over the batch's seats. A won reserve's FLIP credit falls only in the batch that settles the
    // field's final seat, and that seat's unused CRAPS_SEAT_GAS_MAX covers it.
    uint256 internal constant CRAPS_SETTLE_TAIL_GAS = 200_000;
    // Craps work checkpoint and return reserve.
    uint256 internal constant CRAPS_WORK_TAIL_GAS = 60_000;
    // Cold maintenance: 515.9k.
    uint256 internal constant CRAPS_MAINTENANCE_GAS_MAX = 650_000;
    // Cold refund.
    uint256 internal constant CRAPS_REFUND_GAS_MAX = 220_000;
    // At most one cursor write follows an admission; sized at two fresh cursor words (220.1k) plus
    // 25k frame, with margin.
    uint256 internal constant CRAPS_SWEEP_TAIL_GAS = 300_000;
    // Growth round advance reads and cursor arithmetic; persistence uses GROWTH_TAIL_GAS.
    uint256 internal constant GROWTH_ROUND_ADVANCE_GAS = 10_000;
    // Read and calculate one winner's payout; its FLIP credit is reserved separately.
    uint256 internal constant GROWTH_WINNER_GAS = 10_000;
    // Growth cursor, credit-call frame and return reserve, excluding per-recipient credits.
    uint256 internal constant GROWTH_TAIL_GAS = 30_000;
    // Bound the fresh-state cost of a single growth credit flush.
    uint256 internal constant GROWTH_CREDIT_BATCH_SIZE = 32;
    // Cold beneficiary without a lootbox leg: whole worker 118.7k Osaka.
    uint256 internal constant REDEMPTION_BASE_GAS = 600_000;
    // Redemption cursor and return reserve.
    uint256 internal constant REDEMPTION_TAIL_GAS = 100_000;
    // Cold batch resolution before its first claim: 71.9k Glamsterdam, with margin.
    uint256 internal constant REDEMPTION_RESOLVE_GAS = 90_000;
    // Zero-token entry: packed queue read and existing cursor update, with margin.
    uint256 internal constant REDEMPTION_SKIP_GAS = 20_000;
    // A lootbox leg is ONE order of min(ceil(leg / UNIT), BOXES_MAX) custom boxes,
    // priced by HUMAN_ENTRY_GAS + boxes x HUMAN_BOX_GAS, including EV accounting.
    uint256 internal constant REDEMPTION_BOX_UNIT = 1 ether;
    // Maximum boxes per redemption order.
    uint256 internal constant REDEMPTION_BOXES_MAX = 20;
    // One loan settlement: list and loan reads, the auto-repay check, ownership and default-ID
    // writes, native sDGNRS burn, AFKing-run finalization with its Quests call, the 32-symbol
    // deity scan with a cold DeityPass.seize, loan deletion and event.
    // Cold account with a run, a symbol-31 deity and sDGNRS: 194.1k Osaka, 283.3k Glamsterdam
    // vs LOAN_SEIZE + TAIL = 340k.
    uint256 internal constant LOAN_SEIZE = 280_000;
    // Cursor and pending-flag writes, game over's loan cursor, event and return.
    uint256 internal constant LOAN_SEIZE_TAIL = 60_000;
    // Game over's loan scan: one due level's cold count read and step.
    uint256 internal constant LOAN_TERMINAL_LEVEL = 10_000;
}
