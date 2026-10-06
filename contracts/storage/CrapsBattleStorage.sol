// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {Craps} from "../Craps.sol";
import {CrapsPriceLib} from "../libraries/CrapsPriceLib.sol";
import {LootboxCraps} from "../LootboxCraps.sol";
import {CrapsCustomTerms} from "../CrapsCustomTerms.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";

interface IGameCrapsWorkStage {
    function rngConsumerStage() external view returns (uint8);
}

/// @dev Shared layout for the table and its pinned jackpot lifecycle delegate. Append-only.
abstract contract CrapsBattleStorage is LootboxCraps, CrapsCustomTerms {
    /// @notice A craps price reached the burn lane with a dirty low byte, where the action flags
    ///         ride. Unreachable by construction — every price is a whole-FLIP multiple — and a
    ///         hard stop rather than a silent mis-tag if that ever stops being true.
    error BadBurnTag();

    /// @notice A custom battle was opened on terms it may not have. ONE error for the whole
    ///         definition — round, bankroll depth, goal band, bounty ceiling and granule field,
    ///         close time and high-roller multiple — rather than one per field.
    ///         `createBattle` is creator-gated and rare, so per-field granularity bought a caller
    ///         very little and cost the table bytecode it does not have; the terms are documented
    ///         on the function and every bound is a public constant.
    error BadBattleTerms();
    /// @notice No such bet.
    error NoSuchBet();
    /// @notice Only the bet's owner may amend it.
    error NotYourBet();
    /// @notice The bet's slot has closed: its table is bound, its word is in flight.
    error BetLocked();
    /// @notice The entry multiple is neither one copy of the run nor the field's high-roller
    ///         multiple. Nothing between the two is a legal entry.
    error BadEntryMultiple();

    /// @notice The requested slot is not open for the attempted action.
    error BonusPeriodSpent();

    /// @notice The open window's period has not run out yet, so there is nothing to shut.
    error BonusStillRunning();
    /// @notice One seat per player in a seeded window — the entry is already taken.
    error AlreadyInBonus();
    /// @notice A donation would not fit the seed field, or there is nothing to donate to. Only a
    ///         donation is ever refused for this: a seed that overflows would run straight through
    ///         the real-entrant bit and the tier above it, and the day's opener forfeits the
    ///         excess instead of reverting.
    error SeedAboveMax();


    /// @notice A board's packed word sets bits outside the ten three-bit legs, or names more
    ///         than seven chips.
    error BadRandomCount();

    /// @notice A board stacks more than three player-selected chips on a single leg.
    error TooManyChipsOnALeg();
    /// @notice A ticket named chips on the pass line AND on don't pass. Pick a side: a board that
    ///         backs the shooter and fades them at once is two wagers cancelling into two house
    ///         edges, and it is refused at the door rather than sold.
    error BoardPlaysBothSides();
    /// @notice Opening a custom battle takes the vault owner's grant. Joining one does not.
    error NotBattleCreator();

    /// @notice Only the vault's majority holder may move the battle-creator roll.
    error NotVaultOwner();

    /// @notice Only the pinned game may open the bonus day. It rides the daily advance, which is
    ///         the crank that applies the very word the day's terms are drawn from.
    error OnlyGame();

    /// @notice The slot does not identify a custom battle or a valid bonus window.
    error NoSuchBattle();

    /// @notice A reservation run asked for no days at all.
    error BadPassCount();

    /// @notice A conversion would carry the high-roller credit lane past its ceiling.
    error PassLaneFull();

    /// @notice A day in the run is already spoken for, has already drawn its word, or is not in
    ///         the future. A commitment has to be blind to be worth anything, so a day whose terms
    ///         are knowable is not one anybody may reserve.
    error DayNotReservable();

    /// @notice The upgrade mask names nothing still buyable: every bit it set is already high, or
    ///         it named no period at all.
    error NothingToUpgrade();

    /// @notice A board save that pays nothing needs the caller's existing Game wallet ID.
    error NoWalletId();

    /// @notice Six windows per day: five ordinary battles, then the daily jackpot battle (period 5).
    uint256 internal constant _BONUS_PERIODS_PER_DAY = 6;
    /// @notice Width of one day in the bonus slot namespace. Remainder zero holds the day tickets;
    ///         the six windows use remainders one through six. Remainder seven takes no entries
    ///         and holds only a warm-up or skipped day's detached jackpot battle.
    uint256 internal constant _BONUS_SLOTS_PER_DAY = 8;

    /// @notice THE SCHEDULED FORMAT, and the whole of it. Every protocol-scheduled Dice Run runs
    ///         a bankroll FIVE rounds deep and chases FIVE times that bankroll. A high-water run
    ///         ranks on how far it got rather than how fast it arrived, so drawing another target
    ///         only creates another set of downstream rules without changing the product. A
    ///         CUSTOM battle still names its own depth and target — these are the schedule's,
    ///         never a test of eligibility.
    uint256 internal constant _SCHED_BANK_MULT = 5;
    uint256 internal constant _SCHED_GOAL = 5;

    /// @notice THE DICE RUN RECORD FLOOR, in score basis points: a 100x high point against the
    ///         run's own starting bankroll. Below it a scheduled winner never reads the shared
    ///         BIGGEST mark at all.
    /// @dev The one figure in this format the product discussion described rather than named. It
    ///      is a single constant and a single test vector on purpose, so moving it is cheap.
    uint256 internal constant _DICE_RUN_RECORD_FLOOR = 1_000_000;

    /// @notice THE LINEAR RATE A DAY'S BUDGET IS DRAWN AT, in basis points of ACTION.
    ///
    ///         Twelve percent of the bankroll the table's seats put up, and NOTHING is halved
    ///         downstream: what the two lanes offer between them is exactly this rate on exactly
    ///         the action they booked. It is a RATE ON THE HANDLE and not an estimate of burn —
    ///         the table does not measure what it kept, and this figure has never claimed to.
    ///
    ///         WHY TWELVE. Measured post-boost on the shipped resolver at five million runs a
    ///         cell, the weakest scheduled cell still leaves the table 13.72% of the bankroll it
    ///         was bought with — a run that goes broke has its remainder deleted, and that
    ///         deletion is what pays for the subsidy. Twelve sits under the worst cell, so the
    ///         linear term cannot outrun the engine's own take anywhere on the schedule.
    ///
    ///         A WHOLE-RUN FIGURE, NOT A PER-BET EDGE — the two are nothing alike here. A slip
    ///         re-bets its whole bankroll hand after hand chasing five times it out of five
    ///         rounds of depth, so what decides the loss is almost never the edge on any leg; it
    ///         is that the run busts first.
    uint256 internal constant _BOOST_ACTION_BPS = 1200;
    uint256 internal constant _BPS_DENOMINATOR = 10_000;

    /// @notice THE ABSOLUTE SEAT CEILING for one `resolveRngSlot` call, independent of whatever
    ///         budget the caller supplies. It bounds the two credit arrays and the loop counter,
    ///         so one call can never be made to allocate or iterate without limit — and it is the
    ///         only bound that does not depend on gas being measured correctly.
    ///
    ///         A field deeper than it settles over as many calls as it needs, carried by the
    ///         slot's cursor. It also bounds the credit flush that follows the last admitted
    ///         seat: SEAT + SETTLE_TAIL + 96 x CREDIT stays below 10M.
    uint64 internal constant _RESOLVE_MAX_SEATS = 96;

    // Safety bounds admit indivisible work; actual consumed gas, never these bounds, is charged.
    // Seat includes the engine's 1,111-roll ceiling, sole-high award and full field finalization.
    uint256 internal constant _SEAT_GAS_MAX = GasBounds.CRAPS_SEAT_GAS_MAX;
    uint256 internal constant _CREDIT_GAS_MAX = GasBounds.CRAPS_CREDIT_GAS_MAX;
    uint256 internal constant _SETTLE_TAIL_GAS = GasBounds.CRAPS_SETTLE_TAIL_GAS;
    uint256 internal constant _WORK_TAIL_GAS = GasBounds.CRAPS_WORK_TAIL_GAS;
    uint256 internal constant _MAINTENANCE_GAS_MAX = GasBounds.CRAPS_MAINTENANCE_GAS_MAX;
    uint256 internal constant _REFUND_GAS_MAX = GasBounds.CRAPS_REFUND_GAS_MAX;
    uint256 internal constant _SWEEP_TAIL_GAS = GasBounds.CRAPS_SWEEP_TAIL_GAS;

    /// @dev Carve the EIP-150 forwarding reserve and ABI/return tail from the fixed ledger.
    /// The atomic admission check separately reserves enough available gas for a safe checkpoint.
    function _resolverAllowance(uint256 remaining) internal pure returns (uint256) {
        uint256 available = remaining - _WORK_TAIL_GAS - 30_000;
        return available - available / 64 - 1;
    }

    function _readCrapsStage() internal view returns (uint8) {
        return IGameCrapsWorkStage(_GAME).rngConsumerStage();
    }

    /// @notice How many days of action a budget is drawn from.
    uint256 internal constant _BOOST_ACTION_WINDOW_DAYS = 7;

    /// @notice The most cheap cursor hops one maintenance or read-cohort batch may take —
    ///         finalized windows, empty armed fields and day separators crossed without doing
    ///         real work. Two days' worth of slots, so a backlog of windows the read-cohort stage
    ///         already settled clears at a bounded and predictable per-call cost.
    uint256 internal constant _KEEP_MAX_HOPS = 16;

    /// @notice THE DAILY BASE SUBSIDY, ADDED and never a floor. Every opened day puts this up on
    ///         top of the linear rate, so a table nobody has played still has something to offer
    ///         and a busy one is not paid the base INSTEAD of its action.
    ///
    ///         It is deliberately emissionary at low turnout and pays for itself at high: at the
    ///         conservative 16% the engine takes and the ~15,600 FLIP of action an ordinary daily
    ///         ticket puts through, each ticket leaves about 624 FLIP behind, so the day nets to
    ///         zero somewhere around eighty tickets and prints below that. That is an EXPECTATION,
    ///         not a cap — the ladder pays a window up to a hundred times its share, and the
    ///         window it is drawn from lags a week.
    ///
    ///         HALF OF IT NEVER REACHES A WINDOW. What a day raises — this base and its rate on
    ///         the week's action together — is split down the middle by `_splitMainBudget`: one
    ///         half is the ladder the day's seven windows share, the other is banked in the
    ///         progressive. So the figure here is the day's WHOLE main allocation, not what the
    ///         ladder gets.
    uint256 internal constant _BASE_MAIN_BUDGET = 50_000;

    /// @notice The top of the boost ladder. EVERY window is the same lottery: it advertises
    ///         `up to` this many times its share of the day, and the rung is drawn from the word
    ///         that SETTLES the table — which does not exist while anyone can still enter.
    uint256 internal constant _BOOST_MAX_MULT = 100;

    /// @notice THE PROGRESSIVE'S RUNGS, in BASIS POINTS of the LIVE pool at the moment a
    ///         scheduled field finalizes. Every scheduled window, the jackpot slot included,
    ///         pays on the same two rungs:
    ///
    ///           common (high point >= 25x)     5%
    ///           rare   (high point >= 120x)   10%
    ///
    ///         The rare rung is tested first and OVERRIDES, so a field never pays both.
    uint256 internal constant _PROG_ROUTINE_COMMON_BPS = 500;

    /// @dev The rare rung as DOUBLINGS of the common share, which is how the award applies it:
    ///      `_PROG_ROUTINE_COMMON_BPS << _PROG_RARE_DOUBLINGS` is the rare rung above.
    uint256 internal constant _PROG_RARE_DOUBLINGS = 1;

    /// @dev THE HIGH-POINT CUTOFFS, in SCORE BASIS POINTS — the
    ///      winner's high point over its own starting bankroll, 10,000 being 1x. INCLUSIVE:
    ///
    ///        common          rare
    ///        250,000 (25x)   1,200,000 (120x)
    ///
    ///      A MULTIPLE, not a roll count. A high-water run is not trying to be quick, so how
    ///      long it took says nothing about it; how far it got does. The high point adds no
    ///      draw of its own — it is a figure the settlement already computed.
    ///
    ///      TESTED IN BASIS POINTS, not in FLIP, and the two are the same test: the score is
    ///      `floor(peak * 10_000 / start)`, and for integers `floor(a/b) >= c` is exactly
    ///      `a >= c * b`. So comparing the floored score to a bps cutoff is comparing the whole
    ///      high point to a multiple of the bankroll, without the multiplication.
    uint256 internal constant _PROG_COMMON = 250_000;
    uint256 internal constant _PROG_RARE = 1_200_000;

    /// @notice House money lands on a ROUND figure. It is already counted in 100-FLIP granules,
    ///         so anything up to forty of them is round already; past that it goes to the nearest
    ///         THOUSAND. A four-figure subsidy quoted to the hundred reads like a rounding error
    ///         someone forgot to tidy, and the granule stops meaning anything at that size.
    ///
    ///         Nearest, not floored: the budget is an expected allocation and never a hard cap —
    ///         the ladder pays a window up to a hundred times its share — so half a granule of
    ///         drift either way is noise against a figure that already varies by two orders of
    ///         magnitude. Below the threshold nothing moves at all.
    uint256 internal constant _BOOST_ROUND_ABOVE = 40;
    uint256 internal constant _BOOST_ROUND_STEP = 10;

    /// @dev Custom battles take slots ABOVE the day-derived space. A window's slot is
    ///      `day * _BONUS_SLOTS_PER_DAY + period + 1` against a uint24 day, so the day lane can
    ///      never reach 2^27; starting custom slots at 2^40 leaves both room inside the 47 bits
    ///      inside a uint48 slot and no way for the two to collide.
    uint256 internal constant _CUSTOM_SLOT_BASE = 1 << 40;

    // A custom battle's whole definition, in ONE word. Money is held in WHOLE FLIP rather than
    // wei — every board leg already is — which is what makes it fit: in wei the bankroll and
    // target alone want 194 bits. Layout, low bits first:
    //   bits   0.. 27  played     the round a slip puts down, in whole FLIP
    //   bits  28.. 32  bankMult   how many rounds deep the bankroll runs, 1.._MAX_BANKROLL_MULT
    //   bits  33.. 42  goalMult   the target, _MIN_BATTLE_GOAL_MULT.._MAX_GOAL_MULT x the bankroll
    //   bits  43.. 60  stakeUnits the bounty, in _BATTLE_STAKE_UNIT granules
    //   bits  61..100  closeTime  when entry shuts and the table may be taken
    //   bit   101      multi      one address may take as many seats as it pays for
    //   bits 102..109  highMult   the high-roller multiple, 0 (no high lane) or 2.._MAX_HIGH_MULT
    // The chips left to the dice are not a term: every ticket places zero through seven and
    // scatters the complement, but all play the slot's same ten-chip round.
    uint256 internal constant _CB_PLAYED_MASK = 0xFFFFFFF;

    uint256 internal constant _CB_BANK_MASK = 0x1F;

    uint256 internal constant _CB_GOAL_MASK = 0x3FF;

    uint256 internal constant _CB_CLOSE_MASK = 0xFFFFFFFFFF;

    /// @notice What part of the HIGH lane's own component goes to the main boost rather than
    ///         staying with the lane that earned it. Two parts in five — so twelve percent of high
    ///         action reads 4.8 points to the main lane and 7.2 to the high one.
    uint256 internal constant _HIGH_MAIN_NUM = 2;
    uint256 internal constant _HIGH_MAIN_DEN = 5;

    uint256 internal constant SCHEDULE_TAG = 0x43726170735363686564756c65; // "CrapsSchedule"
    uint256 internal constant TIE_TAG = 0x4372617073546965; // "CrapsTie"
    /// @dev Domain tag for a battle's match key.
    uint256 internal constant BATTLE_TAG = 0x4372617073426174746c65; // "CrapsBattle"
    /// @dev Domain tag for the boost multiplier roll, so it cannot collide with any other draw off
    ///      the same word.
    uint256 internal constant BOOST_TAG = 0x426f6f7374; // "Boost"
    /// @dev Domain tag for the daily high-roller draw, so the one word a day commits can carry
    ///      this and the board scatter and the boost rung without any two seeing the same bits.
    uint256 internal constant HIGH_TAG = 0x48696768526f6c6c6572; // "HighRoller"

    // One stored bet word:
    //   bits   0..159  player
    //   bits 160..189  ten three-bit chip counts; all ten zero means draw all ten
    //   bits 190..205  scheduled day tag, low 16 bits (unused for custom bets)
    //   bits 206..208  the craps boon riding this slip, one-hot (see _BET_BOON_SHIFT)
    //   bits 209..216  scheduled day tag, high 8 bits (unused for custom bets)
    //   bits 217..223  high-roller flags: bit 217 alone on a window-local slip, bit 217 + p per
    //                  period on a day ticket
    //   bits 224..255  jackpot award units
    // Logical IDs are `(slot << 64) | seat`. Scheduled storage uses day modulo 64;
    // _loadBet authenticates the real day and removes the tag before decoding game fields.
    // Custom storage uses the full ID. Slot terms and resolution cursors keep logical keys.
    /// @dev The ten legs, three bits each, as chip counts, in the CANONICAL order — the identical
    ///      thirty-bit word `CrapsSlipPlaced` carries in its low bits, so storage and the log
    ///      agree without a translation anywhere. All ten zero leaves the whole round to the draw;
    ///      the submitted counts may sum to at most seven, and settlement scatters the complement.
    ///      Three bits is the right width because the per-leg cap fits and no submitted total may
    ///      exceed seven.
    uint256 internal constant _BET_CHIPS_SHIFT = 160;
    uint256 internal constant _BET_CHIPS_MASK = 0x3FFFFFFF;
    /// @dev The entry multiple MINUS ONE, carried on `CrapsSlipPlaced` alone and never stored: a
    ///      seat's scale is derived from its high flag at settlement, not read back from the word.
    ///      The byte rides above the bet id on the event rather than in the two-bit gap under it —
    ///      the id ends at 159 and a byte does not fit in two bits.
    uint256 internal constant _EV_MULT_SHIFT = 160;

    /// @dev Bits 206..208: the craps boon riding this slip, ONE-HOT — 1 = 5%, 2 = 10%, 4 = 15%,
    ///      0 = none. Carried at the SAME shift in storage and on `CrapsSlipPlaced`, so the log
    ///      and the word cannot drift.
    ///
    ///      A one-hot tier rather than a two-bit index because an invalid word must fail CLOSED:
    ///      3, 5, 6 and 7 are unreachable through the trusted writer and pay nothing if a value
    ///      ever reached storage another way, where a two-bit field would silently mean something.
    ///
    ///      Bits 209..216 are unused. A day-wide entry is ONE slip — the whole day or a single
    ///      window — so no slip carries a set to be locked as one, and nothing stamps a span.
    uint256 internal constant _BET_BOON_SHIFT = 206;
    uint256 internal constant _BET_BOON_MASK = 7;

    /// @dev A seat took the high-roller lane. Stored as a FLAG rather than inferred from the
    ///      multiple: a custom battle may legally set `H` to a figure an ordinary seat could once
    ///      have named, so eligibility has to be a thing the entry recorded, not a thing a later
    ///      reader re-derives from an argument.
    ///
    ///      A WINDOW-LOCAL slip stores exactly this one bit. A DAY ticket stores SEVEN — bit
    ///      `217 + p` for period `p` — so one ticket can be high in the windows it chose and
    ///      ordinary in the rest. A whole-day high entry sets all seven, which is what keeps it
    ///      byte-for-byte the seat it always was; `_highOn` is the one reader of either shape.
    uint256 internal constant _BET_HIGH_BIT = 1 << 217;
    uint256 internal constant _BET_HIGH_SHIFT = 217;
    uint256 internal constant _BET_DAYHIGH_MASK = 0x3F << 217;

    /// @dev Bit 0 of every one of the ten three-bit legs. Shifting each leg's `4` bit onto this
    ///      mask makes the three-chip ceiling one board-wide test.
    uint256 internal constant _CHIP_LO_MASK = 0x9249249;

    uint256 internal constant _CB_HIGH_MASK = 0xFF;

    /// @dev Where the multiple sits in `Window.terms`, directly above the 18-bit bounty, so the
    ///      match key commits to the whole of a field's economics and a lane read one way at entry
    ///      and another at settlement keys a different battle instead of mispaying this one.
    uint256 internal constant _TERM_HIGH_SHIFT = 18;

    /// @dev Shared sideboard, ONE word per battle:
    ///        bits   0.. 31  how many high seats the field holds
    ///        bits  32..136  the best composite among them, the SAME 105-bit score the main
    ///                       scoreboard ranks on, so neither lane can rank on money it scaled
    ///        bits 137..168  the seat holding that lead
    ///        bit  169       done: the sole rider settled, or the competitive award was paid
    ///        bits 170..188  longest shared hand, including its ordinal (Craps.SlipResult)
    ///      Main finalization proves every high score and hand record has been folded,
    ///      the head count is known from entry, and the principal follows from `H`, the bounty
    ///      and that count.
    uint256 internal constant _HF_SCORE_SHIFT = 32;
    uint256 internal constant _HF_WINNER_SHIFT = 137;
    uint256 internal constant _HF_DONE_BIT = 1 << 169;
    uint256 internal constant _HF_HOTTEST_SHIFT = 170;
    uint256 internal constant _HF_HOTTEST_MASK = (1 << 19) - 1;

    /// @dev A day's ticket word holds EIGHT counts in ONE slot: the total in the low 32 bits and
    ///      one high-roller count PER PERIOD above it, 32 bits each — period `p`'s at bits
    ///      `32(p + 1)`. Per period because an upgrade buys the lane one window at a time; still
    ///      one slot, so selling a day ticket writes one word and arming still folds the total
    ///      and its own period's high count into a window in one read.
    uint256 internal constant _DT_HIGH_SHIFT = 32;
    /// @dev One high ticket in EVERY period's counter — what a whole-day high entry adds.
    uint256 internal constant _DT_ALL_HIGH = 0x0000000000000001000000010000000100000001000000010000000100000000;

    /// @dev A day's action book is one word: total bankroll in the low 128 bits and the high-lane
    ///      part in the high 128. Even a maximally populated field at the protocol's term ceilings
    ///      is comfortably below either half; packing makes a seven-day budget draw seven cold
    ///      reads instead of fourteen.
    uint256 internal constant _DAY_HIGH_SHIFT = 128;

    /// @dev A day's budget word carries the day's total ROUTINE WEIGHT in its top byte. The
    ///      weight is a pure function of the day's word, but recomputing it means six keccaks,
    ///      and every settle reads a window's share — so it is summed once, when the day opens,
    ///      and rides home beside the figure it divides.
    uint256 internal constant _BUDGET_MASK = (1 << 248) - 1;
    uint256 internal constant _BUDGET_W_SHIFT = 248;

    /// @dev Where the bet id sits in `CrapsSlipPlaced`, clear of the chips' 30 bits.
    uint256 internal constant _EV_BET_SHIFT = 32;

    /// @dev A ticket may place at most seven of the round's ten chips. The dice scatter the rest.
    uint256 internal constant _MAX_PICKED_CHIPS = 7;

    // Battle scoreboard packing — one battle's entire shared state in one word.
    //   bits   0.. 31  entrants        bits  32.. 63  resolved
    //   bits  64..168  the leading COMPOSITE score
    //   bits 169..200  the SEAT holding it
    //   bits 201..218  battle stake granules (echo, for views)
    //   bits 219..249  seed granules
    //   bits 250..251  scheduled tier; bit 252 high tail; bit 255 terms frozen
    //
    // No roll slice: nothing ranks or qualifies on rolls — the progressive reads the winner's
    // HIGH POINT, which the composite already carries — and the composite needs the width: a
    // high-water verdict is a goal flag, a high point and an ending bankroll, and
    // no two of those may share a field.
    uint256 internal constant _BG_RESOLVED_SHIFT = 32;
    uint256 internal constant _BG_BEST_SHIFT = 64;
    uint256 internal constant _BG_WINNER_SHIFT = 169;
    uint256 internal constant _BG_STAKE_SHIFT = 201;
    uint256 internal constant _BG_TERM_TIER_SHIFT = 250;
    uint256 internal constant _BG_TERM_HIGH_TAIL = 4; // within the six-bit terms lane
    uint256 internal constant _BG_TERMS_FROZEN = 32;
    uint256 internal constant _MASK32 = 0xFFFFFFFF;

    /// @dev The scoreboard's composite is `Craps._rankOf` (the layout and every field are
    ///      documented there) with sixteen reserved low bits; this is the
    ///      mask of the whole 105-bit verdict.
    uint256 internal constant _SC_BEST_MASK = (1 << 105) - 1;
    // The bonus seed lives in the battle's OWN word, not in a global "currently armed" pointer:
    // a seeded battle can still be settling long after the next arm, and its pot must not depend
    // on what is armed by then. In `_BATTLE_STAKE_UNIT` granules — DONATIONS ONLY: a window's
    // own seed is a function of the day's word and is never stored here.
    uint256 internal constant _BG_SEED_SHIFT = 219;
    uint256 internal constant _BG_SEED_MASK = 0x7FFFFFFF;

    /// @dev Resolved seat payment and action totals, returned as one memory pointer to keep the
    ///      batch resolver within the compiler's stack limit. This adds no persistent storage.
    struct Window {
        bytes32 key;
        uint128 bankroll;
        uint128 goal;
        /// @dev The ten-chip round this window plays — what the match key is built on.
        uint256 played;
        /// @dev The maximum seven chips an entrant may place; the dice scatter the complement.
        uint256 postedStake;
        uint256 stakeUnits;
        uint256 terms;
        uint256 tier;
        /// @dev The multiple THIS field's high-roller lane runs at, or zero where it has none. A
        ///      scheduled window takes its own day's draw; a custom battle takes what its creator
        ///      fixed at creation.
        uint256 highMult;
        bool multiEntry;
        uint48 bound;
        /// @dev The field's frozen entrant count — the low word of its scoreboard — and the dense
        ///      combined ordinal of the seat being settled. Memory only: the rotation is a pure
        ///      function of these, the slot and the word, and nothing stores it.
        uint32 entrants;
        uint64 seat;
        uint32 drawn;
        uint32 extraUnits;
        uint256 extraPot;
        /// @dev Jackpot only: fee-funded EXTRA bankroll per high seat, also its extra bounty.
        uint256 highExtra;
    }

    struct SeatResult {
        address player;
        uint256 paid;
        uint256 staked;
        uint256 high;
    }

    /// @dev One settlement's whole account, carried between the engine and the paying/preview
    ///      paths as a single memory pointer — the resolver is sensitive to stack pressure.
    ///      Its layout deliberately matches `Craps.SlipResult`: `paid` reuses the dead
    ///      `bankrollIn` word, `won` aliases `bankrollOut`, and `unitsPlayed` keeps the otherwise
    ///      fifth word as the merit `rank`. `_settlementOf` can therefore reuse the engine result
    ///      directly instead of allocating and copying a second struct for every seat.
    struct Settlement {
        /// @dev What is actually credited. A bust pays ZERO: whatever it was still holding is
        ///      deleted, not returned to the player and not moved into anyone else's pot.
        uint256 paid;
        /// @dev The RAW bankroll the table returned, unscaled and unrounded, a busted run's
        ///      remainder included. It is what the scoreboard ranks on and what `CrapsBetSettled`
        ///      reports; it is deliberately NOT what a bust is paid.
        uint256 won;
        /// @dev THE HIGH POINT, raw and unscaled: the largest bankroll this run held at a
        ///      completed-shooter boundary. A scheduled goal RANKS on it and the records read it;
        ///      it is never what the run is paid. A bust's peak breaks ties among busts with
        ///      the same hand count and survival state, but never qualifies it for records.
        uint256 peak;
        uint256 handsPlayed;
        /// @dev THE MERIT COMPOSITE (`Craps._rankOf`): the fifth word, where
        ///      `SlipResult` carries escalated units, which the table never reads.
        ///      `CrapsEngine.settleRanked` returns the composite here instead.
        uint256 rank;
        /// @dev Dice rolls across the run. It ranks NOTHING and qualifies nothing — the
        ///      progressive reads the high point now — and survives only as telemetry.
        uint256 totalRolls;
        Craps.SlipStop stop;
        uint256 hottestHand;
    }

    /// @dev One word per bet: owner, board, flags, award units and a scheduled day tag.
    ///      Logical IDs are `(slot << 64) | n`, with dense indices 1..entrants. Only the
    ///      scheduled day component of the physical key is recycled; counts stay logical.
    mapping(uint256 => uint256) internal _bets;

    /// @dev Scheduled entries share 64 physical day banks. Thirty days ahead plus thirty
    ///      days of settlement fit without aliasing. Custom battle IDs are not recycled.
    uint256 internal constant _RESERVATION_DAYS = 30;
    uint256 internal constant _SETTLEMENT_DAYS = 30;
    uint256 private constant _BET_DAY_MASK = (uint256(0xffff) << 190) | (uint256(0xff) << 209);
    uint256 private constant _DAY_SEAT_VALUE_MASK = (uint256(1) << 39) - 1;

    function _scheduledExpired(uint256 slot) internal view returns (bool) {
        return slot < _CUSTOM_SLOT_BASE && slot / _BONUS_SLOTS_PER_DAY + _SETTLEMENT_DAYS < _currentDayIndex();
    }

    function _reservableDay(uint24 day) internal view returns (bool) {
        uint256 today = _currentDayIndex();
        return day > today && day <= today + _RESERVATION_DAYS && _dailyWordAt(day) == 0;
    }

    function _betStorageKey(uint256 id) internal pure returns (uint256) {
        return id >> 64 < _CUSTOM_SLOT_BASE ? id & ((uint256(1) << 73) - 1) : id;
    }

    /// @dev The two unused bit ranges carry the exact uint24 day. Never truncate the
    ///      requested day when checking it: oversized forged IDs must not alias a live bet.
    function _loadBet(uint256 id) internal view returns (uint256 word) {
        word = _bets[_betStorageKey(id)];
        if (id >> 64 < _CUSTOM_SLOT_BASE) {
            uint256 day = ((word >> 190) & 0xffff) | (((word >> 209) & 0xff) << 16);
            if (day != id >> 67) return 0;
            word &= ~_BET_DAY_MASK;
        }
    }

    function _storeBet(uint256 id, uint256 word) internal {
        if (id >> 64 < _CUSTOM_SLOT_BASE) {
            uint256 day = id >> 67;
            uint256 today = _currentDayIndex();
            if (day > today + _RESERVATION_DAYS || day + _SETTLEMENT_DAYS < today) revert DayNotReservable();
            word = (word & ~_BET_DAY_MASK) | ((day & 0xffff) << 190) | ((day >> 16) << 209);
        }
        _bets[_betStorageKey(id)] = word;
    }

    function _loadDaySeat(uint256 daySlot, address player) internal view returns (uint256 word) {
        word = _daySeated[daySlot & 511][player];
        if (word >> 40 != daySlot >> 3) return 0;
        return word & _DAY_SEAT_VALUE_MASK;
    }

    function _storeDaySeat(uint256 daySlot, address player, uint256 word) internal {
        _daySeated[daySlot & 511][player] = (word & _DAY_SEAT_VALUE_MASK) | ((daySlot >> 3) << 40);
    }

    /// @notice Custom battles opened so far. The next takes slot `_CUSTOM_SLOT_BASE + this + 1`.
    uint64 internal _customBattleCount;

    /// @dev Battle scoreboards, by match key (see `_battleKey`).
    mapping(bytes32 => uint256) internal _battles;

    /// @dev Who has already taken their one seat in a seeded custom field. Unseeded custom
    ///      battles permit separately funded repeat entries.
    mapping(bytes32 => mapping(address => bool)) internal _bonusSeated;

    /// @dev Opened bonus day plus one; zero means no day has been opened yet.
    uint256 internal _bonus;

    /// @dev Bits 0..47: table index + 1 (zero = open); bits 48..111: settlement cursor.
    ///      A closed field reuses its binding word as seats settle. No day identifier is recycled.
    mapping(uint256 => uint256) internal _slotState;

    function _slotIndexOf(uint256 slot) internal view returns (uint48) {
        return uint48(_slotState[slot]);
    }

    function _bonusCursorOf(uint256 slot) internal view returns (uint64) {
        return uint64(_slotState[slot] >> 48);
    }

    function _setSlotIndex(uint256 slot, uint48 index) internal {
        _slotState[slot] = (_slotState[slot] & ~uint256(type(uint48).max)) | index;
    }

    function _setBonusCursor(uint256 slot, uint64 cursor) internal {
        _slotState[slot] = (_slotState[slot] & ~(uint256(type(uint64).max) << 48))
            | (uint256(cursor) << 48);
    }

    /// @dev Scheduled window slots have remainders 1..6 within their eight-slot day.
    ///      Bits 33..38 in the day-seat word track them; low 32 bits remain the day seat.
    ///      Custom battles keep their independent membership mapping and multi-entry rules.
    function _claimScheduledSeat(uint256 slot, address player) internal {
        uint256 daySlot = slot & ~uint256(7);
        uint256 bit = uint256(1) << (32 + (slot & 7));
        uint256 word = _loadDaySeat(daySlot, player);
        if (word & (bit | _MASK32) != 0) revert AlreadyInBonus();
        _storeDaySeat(daySlot, player, word | bit);
    }

    /// @dev How many DAY TICKETS a protocol day sold, with the per-period high counts above the
    ///      total — see `_DT_HIGH_SHIFT`. A day ticket is one bet that plays every window of its
    ///      day, and it is only sold while the day's FIRST window is still taking bets — so the
    ///      TOTAL is frozen before any window can shut, and every window of the day therefore
    ///      plays the same day field. That is what removes the need for a per-window high-water
    ///      mark. A period's HIGH count stays open a little longer — an upgrade may move it until
    ///      that period's own entry close — which is still strictly before the arm that folds it.
    mapping(uint256 => uint256) internal _dayTickets;

    /// @dev The holder's day-ticket seat in bits 0..31, scheduled window membership in
    ///      bits 33..38, and the exact day at bits 40..63. Keys use daySlot modulo 512;
    ///      _loadDaySeat authenticates and strips the day before checking membership.
    ///      Day-ticket gates ask NONZERO — one ticket per address per day, and a bar on any single window of that
    ///      day, since the ticket already sits in all of them — but storing the seat is what lets
    ///      an upgrade name the caller's own ticket as `(daySlot << 64) | seat` without a walk.
    ///      Nothing here records how the seat was PAID for: a bought, pass-funded and prepaid
    ///      seat are indistinguishable, which is the point.
    mapping(uint256 => mapping(address => uint256)) internal _daySeated;

    /// @notice Who may OPEN a custom battle. Joining one an authorized creator opened is free to
    ///         anyone who clears its terms, and the bonus windows are the protocol's own door.
    mapping(address => bool) internal _battleCreator;

    /// @dev Per protocol day, the total BANKROLL in bits 0..127 and its high-roller part in bits
    ///      128..255. The total sizes later bonuses without depending on how the dice ran; the
    ///      high part is split out because the lanes recycle at different rates. Bounties and
    ///      boost never enter. One packed write per settle batch, never one per seat.
    mapping(uint24 => uint256) internal _dayStaked;

    /// @dev A day's bonus budget in whole FLIP, fixed when the day opens and shared by its seven
    ///      windows. Stored rather than recomputed so a window armed days later still pays what
    ///      its own day advertised.
    mapping(uint24 => uint256) internal _boostBudget;

    /// @dev A battle's high-roller sideboard — see the layout above. Written only by a field that
    ///      actually takes a high seat, so an ordinary battle never touches this mapping at all,
    ///      on entry or on settlement.
    mapping(bytes32 => uint256) internal _highField;

    /// @dev A day's high-roller boost budget, fixed when the day opens beside the main one. It has
    ///      no floor: the high lane pays out of what high rollers actually burned and out of
    ///      nothing else, so a day that saw none simply has none to give.
    mapping(uint24 => uint256) internal _highBudget;

    /// @dev A custom battle's whole definition, one word per slot — see the layout above. The
    ///      terms are fixed for the FIELD at creation rather than restated by each entrant, which
    ///      is what lets a custom battle behave exactly like a bonus window.
    mapping(uint256 => uint256) internal _customBattle;

    /// @dev A player's UNCOMMITTED day-pass credits, both denominations in one word: the normal
    ///      count in the low 32 bits, the high-roller count above `_PASS_HIGH_SHIFT`. Awarded by
    ///      the lootbox and by the pass half of a protocol payout, spent by committing one to a
    ///      future day, and movable one way — normals into highs — at the credits' value ratio.
    ///
    ///      HELD HERE RATHER THAN IN THE GAME, and that placement is forced. A credit is spent by
    ///      `applyCrapsPasses`, which writes the reserved days — Craps state — so holding the
    ///      balance in the Game would mean a cross-contract write on every application, and the
    ///      Game has no room for the entry point that would take it. Here the debit and the
    ///      reservation are one contract's storage and atomic by construction.
    ///
    ///      Credits never expire and are not transferable. They are AWARDED only by the pinned
    ///      game and spent only by their owner. Bits 64..83 hold the preferred board (two bits
    ///      per leg); bit 84 is set on its first save and never cleared. Bits 85..116 cache the
    ///      holder's Game wallet ID, filled once from the Game by the first save and never
    ///      changed. Balance updates preserve these fields. CrapsPreferenceLib pins this
    ///      mapping's slot for the Game's jackpot battle batch read.
    mapping(address => uint256) internal _passCredits;

    /// @dev The same word keyed by Game wallet ID, with the same lanes: normal passes in bits
    ///      0..31, high passes in bits 32..63, the board in bits 64..83 and its initialized bit
    ///      84. Only the board lanes are written, and only when a save changes the board; the
    ///      pass lanes stay zero for the ID-keyed balances, and board writes preserve them.
    mapping(uint32 => uint256) internal _passCreditsById;

    /// @dev THE PROGRESSIVE. One balance, shared by every scheduled window of every day.
    ///      Funded once when a protocol day opens — half of what that day's main allocation
    ///      raised. Future qualifying wins draw from this balance without any activity-score
    ///      reduction. It is a virtual emission liability, counted the
    ///      moment it lands here; a payout later RELEASES it and is not a second issuance.
    ///
    ///      Player money never enters. Bounties, principal, run losses, deleted bust remainders,
    ///      ladder under-realisation and rounding dust all stay exactly where they are.
    uint256 internal _progressive;

    /// @dev THE SCHEDULED CURSOR: the oldest scheduled slot the protocol may still owe work on.
    ///      Every scheduled slot strictly below it is completely finalized, an armed field with
    ///      no seats, a LAPSED day whose reservations were credited back, or the remainder-zero
    ///      separator — nothing of value is ever left behind it. Born in the constructor at
    ///      genesis + 1's separator: the deployment day is a warm-up day with no windows, so
    ///      tomorrow is the first day that can owe anything.
    ///
    ///      It only ever moves FORWARD, and only past a slot proven spent. A day the advance
    ///      never opened — a protocol stall — is not replayed: nobody could have entered it (the
    ///      doors check the live clock and the word), so all it can hold is prepaid reservations,
    ///      and the cursor hands each of those its pass credit back before crossing. Late work is
    ///      finished; dead days are refunded in kind; nothing is stranded either way.
    uint64 internal _keeperSlot;

    /// @dev What a future day costs bought outright, per day. FIXED constants, deliberately not
    ///      derived from the pass denominations or from each other: the pass is a lootbox award
    ///      priced at the expectation, while retail prices include the chosen premium or
    ///      discount. Tying the two together would move one every time the other was retuned.
    ///
    ///      Retail prices are 25,000 normal and 500,000 high: about 0.70% above the scheduled
    ///      mean normal entry cost and 4.09% below its 21x high equivalent. These margins are
    ///      consequences of the schedule, not fields; neither is booked as bankroll action.
    ///      Passes commit before opening RNG, so this is a comparison to the expected cost,
    ///      not a guaranteed discount or premium against every realized day's terms.
    /// @dev Paid-craps burn encoding: the low byte holds flags and bits 8..255 hold
    ///      the whole-FLIP amount. `_tag` validates both before shifting the amount.
    uint256 internal constant _CRAPS_FLAG_JOIN = 0x1;
    uint256 internal constant _CRAPS_FLAG_PASS = 0x2;
    uint256 internal constant _CRAPS_FLAG_NORMAL = 0x4;
    uint256 internal constant _CRAPS_FLAG_HIGH = 0x8;
    /// @dev The comp bit: FLIP charges the craps comp lane instead of the player, consumes no boon
    ///      and reports no quest. Set ONLY by `vaultComp` or a VAULT donation; player-funded
    ///      doors never set it.
    uint256 internal constant _CRAPS_FLAG_COMP = 0x10;

    /// @dev The five things the vault can comp, as the kind byte of a `vaultComp` code, and
    ///      where the code's other fields sit above the recipient's address.
    uint256 internal constant _COMP_WINDOW = 0;
    uint256 internal constant _COMP_DAY = 1;
    uint256 internal constant _COMP_FUTURE_DAYS = 2;
    uint256 internal constant _COMP_UPGRADE = 3;
    uint256 internal constant _COMP_PASSES = 4;
    uint256 internal constant _COMP_WINDOW_AHEAD = 5;
    uint256 internal constant _COMP_KIND_SHIFT = 160;
    uint256 internal constant _COMP_HIGH_BIT = 1 << 168;
    uint256 internal constant _COMP_ARG_SHIFT = 176;
    uint256 internal constant _COMP_COUNT_SHIFT = 200;
    uint256 internal constant _COMP_PERIOD_SHIFT = 208;

    /// @dev Normal day passes banked to sDGNRS and the Vault at deployment, each. Enough to cover
    ///      the opening stretch on its own while the lootbox lanes that feed these two start
    ///      paying, and small enough that the field it banks into is nowhere near its ceiling.
    uint256 internal constant _SEED_PASSES = 20;

    uint256 internal constant _NORMAL_FUTURE_DAY_PRICE = CrapsPriceLib.NORMAL_RETAIL;
    uint256 internal constant _HIGH_FUTURE_DAY_PRICE = CrapsPriceLib.HIGH_RETAIL;

    /// @dev Where the high-roller count sits in a pass-credit word.
    uint256 internal constant _PASS_HIGH_SHIFT = 32;

    /// @dev The ceiling on either lane. A lootbox sweep is permissionless and must never revert on
    ///      a full lane, so an award saturates here and reports what it dropped.
    uint256 internal constant _PASS_MAX = 0xFFFFFFFF;

    /// @dev Future-window comps pay the class expectation: bookends draw tiers 20/30/50,
    ///      routines 55/25/20, and the jackpot fee averages 8,000. The high draw averages 21x.
    uint256 internal constant _EV_WINDOW_OPENER = CrapsPriceLib.BOOKEND_EV;
    uint256 internal constant _EV_WINDOW_ROUTINE = CrapsPriceLib.ROUTINE_EV;
    uint256 internal constant _EV_WINDOW_TAIL = CrapsPriceLib.JACKPOT_FEE;
    uint256 internal constant _EV_HIGH_MULT = CrapsPriceLib.HIGH_EV;

    /// @dev What one banked pass is WORTH when a protocol award pays in passes — the lootbox's own
    ///      expected-cost figures, restated so an award and a box price the same credit
    ///      identically. The denomination switch mirrors the lootbox rule: a pass budget
    ///      strictly above twenty-two normal units pays high. The thirty-high cap is the award's own.
    uint256 internal constant _NORMAL_PASS_VALUE = CrapsPriceLib.NORMAL_VALUE;
    uint256 internal constant _HIGH_PASS_VALUE = CrapsPriceLib.HIGH_VALUE;
    uint256 internal constant _PASS_HIGH_SWITCH = CrapsPriceLib.HIGH_SWITCH;
    uint256 internal constant _MAX_HIGH_PASSES_PER_AWARD = 30;

    /// @dev Normal credits one high credit costs in `convertNormalToHigh` — the passes' own 21:1
    ///      value ratio, so conversion moves value exactly and subsidizes nothing. Deliberately
    ///      independent of the retail future-day price ratio, whose premium and discount
    ///      do not change the credit denominations.
    uint256 internal constant _PASSES_PER_HIGH = CrapsPriceLib.HIGH_EV;

    /// @dev `CrapsProtocolAwardSplit.source` values, frozen — carried to `_splitAward` in the
    ///      TOP BYTE of the award argument. An award is whole FLIP and nowhere near 2^248, so the
    ///      byte is always free, and packing the tag keeps the argument opaque enough that the
    ///      optimizer shares ONE copy of the split instead of specializing four.
    uint256 internal constant _SPLIT_SRC_MAIN = uint256(1) << 248;
    uint256 internal constant _SPLIT_SRC_HIGH_CONTESTED = uint256(2) << 248;
    uint256 internal constant _SPLIT_SRC_HIGH_SOLE = uint256(3) << 248;
    uint256 internal constant _SPLIT_SRC_PROGRESSIVE = uint256(4) << 248;
    uint256 internal constant _SPLIT_SRC_HOTTEST = uint256(5) << 248;
    uint256 internal constant _SPLIT_GROSS_MASK = (uint256(1) << 248) - 1;

    /// @notice A bet slip took a seat at a slot.
    /// @param bet The whole slip in one word:
    ///
    ///            - bits 0..29   the TEN leg counts, three bits each, low bits first: passLine,
    ///              place4, place5, place6, place8, place9, place10, hard4, hard8, dontPass. Bits
    ///              30..31 are unused. Zero is a blank ticket, so the draw places all ten chips.
    ///              Bit for bit the same word the bet stores at 160..189, so an indexer and the
    ///              contract never disagree about where a chip went.
    ///            - bits 32..159 the bet id, itself `(slot << 64) | seat`.
    ///            - bits 160..167 the entry multiple MINUS ONE, so 0 reads as one copy of the run.
    ///            - bits 190..205 are unused.
    ///            - bit 217 the high flag on a window seat; bits 217..223 a day ticket's per-period
    ///              high mask, bit `217 + p` for period `p` — the same bits the bet stores, so a
    ///              banked high pass seated at one copy of the run still reads as high.
    ///
    ///            The slot is the only term the slip carries: everything it PLAYS by — bankroll,
    ///            target, bounty, bar, the round — belongs to that slot, so an indexer reads those
    ///            once per battle rather than once per slip. The number also says which kind it
    ///            is: below `_CUSTOM_SLOT_BASE` a bonus window, `day * _BONUS_SLOTS_PER_DAY + period
    ///            + 1`; at or above it, a custom battle.
    /// @dev Every seat comes through here, the house's and the vault's included, so this one event
    ///      is a window's whole field. Carrying the id rather than deriving it from arrival order
    ///      costs nothing — the chips need 30 bits of a word that has 256 — and it means a dropped
    ///      or reordered log cannot renumber every seat behind it.
    event CrapsSlipPlaced(address indexed player, uint256 bet);

    /// @notice An open slip's chips were re-spread by its owner. `chips` is the same thirty-bit
    ///         word `CrapsSlipPlaced` carries in its low bits — ten counts, the dark side at
    ///         27..29, and ZERO for a blank ticket that has handed its board back to the dice.
    ///         Every other term of the slip belongs to its slot and cannot move.
    event CrapsSlipAmended(uint256 indexed betId, uint256 chips);

    /// @notice A wallet's automatic-entry default, in the canonical three-bit-per-leg encoding.
    event CrapsPreferredBoardSet(address indexed player, uint32 chips);

    /// @notice A wager settled.
    /// @dev Deliberately thin. The whole run — every roll, every leg, the stop — is a pure
    ///      function of the table's word, the slot, the chips and the owner, all of which an
    ///      indexer already has from `CrapsSlipPlaced` and `CrapsBonusArmed`. Only the two
    ///      figures a client would otherwise have to run the engine for are carried, and the
    ///      dice are not: shipping a roll log cost the allocation, a byte write per roll and the
    ///      log data, for information anyone can replay for nothing.
    /// @param won  What the table returned to this bet, before the award rounding.
    /// @param paid Coinflip stake actually credited, after the rounding.
    event CrapsBetSettled(uint256 indexed betId, address indexed player, uint256 won, uint256 paid);

    /// @notice Every entrant of the battle resolved: the scoreboard is the verdict.
    ///         Emitted by whichever settlement happened to be the last one.
    /// @param winnerId The winning seat within this battle's slot, not the full packed bet id.
    /// @param winningPeak The winner's HIGH POINT in whole FLIP: the largest bankroll it held at
    ///        a completed-shooter boundary. What a scheduled field ranks on.
    /// @dev THE SHOOTER COUNT IS NOT RESTATED HERE. A bust's primary leads with its shooter
    ///      count, and `Battle.winningHands` decodes it from the composite the scoreboard holds; a Goal's
    ///      primary is its high point in every product, custom included, so a Goal's hand count
    ///      is not recoverable and reads zero. The log carries the figures the two stops differ
    ///      on and leaves the derivable one in the word it came from.
    /// @param winningEnd The winner's raw ENDING bankroll in whole FLIP — what it was paid on. A
    ///        goal that gave ground after latching ends BELOW its peak and above its target.
    /// @param winningScoreBps The high point over the run's own starting bankroll, in basis
    ///        points: 10,000 is 1x. Carried for every field, custom ones included; zero when the
    ///        winner busted, since a bust's peak reaches no reader. Only a scheduled field's
    ///        score goes on to qualify anything.
    event CrapsBattleFinalized(
        bytes32 indexed battleKey,
        Craps.SlipStop winningStop,
        uint64 winnerId,
        uint256 winningPeak,
        uint256 winningEnd,
        uint256 winningScoreBps,
        uint256 pot
    );

    /// @notice The vault owner moved the battle-creator roll.
    event BattleCreatorSet(address indexed account, bool allowed);

    /// @notice A custom battle was opened. `terms` is the packed definition — everything an
    ///         entrant needs, and everything an indexer needs to reconstruct the match key.
    event CrapsBattleCreated(uint64 indexed slot, address indexed creator, uint256 terms);

    /// @notice A bonus window shut and took the table it will settle on. Arming is the CLOSE of
    ///         entry, not the start: everything before it was open to join, and the index is
    ///         chosen now precisely so nobody could know it while joining.
    event CrapsBonusArmed(bytes32 indexed battleKey, uint48 indexed slot, uint48 indexed index);

    /// @notice Somebody added `amount` FLIP to an open battle's seed, taking it to `seed`.
    event CrapsBonusDonated(bytes32 indexed battleKey, address indexed donor, uint256 amount, uint256 seed);

    /// @notice A protocol day opened its high-roller lane.
    /// @dev The one thing about the lane a reader cannot derive: both budgets are functions of
    ///      SEVEN prior days of split action, so reconstructing them means replaying a week of
    ///      settlement exactly. They are fixed here and never move again, so they are stated once.
    ///      `mainBoostBudget` is the LADDER half the day's seven windows share; its other half is
    ///      in `CrapsProgressiveFunded`, and the two sum to the raw allocation.
    ///      `multiplier` is derivable from the day's word and is carried for the same reason a
    ///      slip carries its own id — so a reader never has to re-run a draw to label a log.
    event CrapsHighRollerDayOpened(
        uint24 indexed day, uint16 multiplier, uint256 mainBoostBudget, uint256 highRollerBoostBudget
    );

    /// @notice A high-roller allocation went home. `amount` is the LIQUID coinflip credit, after
    ///         any slice of the lane's protocol boost banked as pass credit under
    ///         `CrapsProtocolAwardSplit`.
    /// @param bankrollRider True where the field held exactly ONE high seat, so the allocation
    ///        rode that seat's own run instead of being contested — in which case `amount` is what
    ///        the run returned on it, and zero is a real and expected outcome.
    event CrapsHighRollerPaid(
        uint256 indexed betId, bytes32 indexed battleKey, address indexed player, uint256 amount, bool bankrollRider
    );

    /// @notice A bonus window opened for entry at `slot`, carrying `seed` FLIP of house money on
    ///         top of whatever its entrants stake.
    ///
    ///         That figure is a CEILING, not a promise: every window is a lottery whose rung is
    ///         drawn from the word that SETTLES it, so it cannot be read while the field is still
    ///         forming. The drawn figure lands with the table's word — which is after entry shuts
    ///         and before any hand is settled — and none of it is stored. Entry is open from here
    ///         until the window is armed.
    /// @param bankroll The bankroll every entrant burns; the remaining numeric terms follow it.
    event CrapsBonusOpened(
        bytes32 indexed battleKey,
        uint48 indexed slot,
        uint256 seed,
        uint128 bankroll,
        uint128 goal,
        uint256 boardStake,
        uint256 battleStake
    );

    /// @notice A day-pass was committed to a future day for `player`. The day's terms and its
    ///         high-roller multiple are both unknown at this point — that is the whole point of
    ///         the commitment — so the log carries only which kind was placed and where.
    event CrapsDayReserved(address indexed player, uint24 indexed day, bool highRoller);

    /// @notice Chosen windows of a whole-day ticket were upgraded to the day's high-roller lane.
    /// @param upgradedMask Only the bits NEWLY set by this call, bit `p` for period `p` — a bit
    ///        already high was neither charged nor counted again and is not restated here.
    /// @param burned The exact delta charged for them: `(bankroll + bounty) * (H - 1)`, summed
    ///        over the newly upgraded windows. ZERO with the full mask is `upgradeReservedDay`:
    ///        a future reservation swapped to the high lane for a banked high credit.
    event CrapsDayWindowsUpgraded(address indexed player, uint24 indexed day, uint8 upgradedMask, uint256 burned);

    /// @notice Uncommitted day-pass credits were banked for `player`.
    event CrapsPassesCredited(address indexed player, bool highRoller, uint256 count);

    /// @notice Half of a protocol-funded award was targeted at day-pass credits; everything that
    ///         did not convert to whole passes stayed liquid. `grossProtocol` is the award the
    ///         source admitted and `liquidFlip` what went to Coinflip, so their difference is the
    ///         exact FLIP value of the passes banked. The `CrapsPassesCredited` log emitted
    ///         immediately before this one carries their denomination and count — correlate the
    ///         two by position; nothing is restated. Emitted only where at least one pass banked.
    /// @param source 1 main ladder, 2 contested high lane, 3 sole high rider, 4 progressive.
    event CrapsProtocolAwardSplit(
        bytes32 indexed battleKey,
        address indexed player,
        uint8 indexed source,
        uint256 grossProtocol,
        uint256 liquidFlip
    );

    /// @notice `normalSpent` uncommitted normal pass credits became `highReceived` high-roller
    ///         credits, at the credits' own 21:1 value ratio. The ONLY log a conversion emits —
    ///         both lane deltas live here, and no `CrapsPassesCredited` rides along to
    ///         double-count the high addition.
    event CrapsNormalPassesConverted(address indexed player, uint256 normalSpent, uint256 highReceived);

    /// @notice A battle's pot went to its winner, as coinflip credit. A progressive award riding
    ///         the same finalization is a SEPARATE credit and a separate log — this figure is the
    ///         pot and only the pot: the LIQUID figure, after any slice of a scheduled boost
    ///         banked as pass credit under `CrapsProtocolAwardSplit`.
    event CrapsBattlePaid(uint256 indexed betId, bytes32 indexed battleKey, address indexed player, uint256 amount);

    /// @notice The longest shared hand won 10% of the scheduled main pot. High-lane funds
    ///         are excluded. `amount` is liquid FLIP; protocol pass credit is logged separately.
    event CrapsHottestShooterPaid(
        uint256 indexed betId, bytes32 indexed battleKey, address indexed player, uint16 rolls, uint256 amount
    );

    /// @notice A protocol day banked its half of the main allocation in the progressive.
    /// @dev ONCE PER DAY, inside the same guarded block that fixes the ladder half — so repeated
    ///      arms, opens and advances cannot fund it twice, and the absence of this log is how a
    ///      day that never opened is seen.
    /// @param contribution What this day added, in whole FLIP. The ladder half is
    ///        `CrapsHighRollerDayOpened.mainBoostBudget`, and the two conserve the raw allocation
    ///        exactly — the odd wei lands here.
    /// @param balance The pool AFTER the contribution.
    event CrapsProgressiveFunded(uint24 indexed day, uint256 contribution, uint256 balance);

    /// @notice A finalized scheduled battle cleared a high-point cutoff and drew on the
    ///         progressive.
    /// @dev NO SEPARATE DRAW DECIDES THIS. The winner is the one the ordinary comparator already
    ///      named, and the qualification is that winner's HIGH POINT against its window's target.
    ///      A Bust never qualifies however far it ran, and a custom battle never reaches here.
    /// @param rare True for the rare rung, false for the common one. Never both.
    /// @param poolBps The rung applied, in basis points of the live pool: 500 common, 1,000 rare.
    /// @param peak The winner's high point in whole FLIP, the figure that was tested.
    /// @param scoreBps That high point over the run's own starting bankroll, in basis points:
    ///        10,000 is 1x, and the cutoffs are 250,000 / 1,200,000.
    /// @param candidate The rung's whole figure; identical to paid.
    /// @param paid The full gross award removed from the pool, including any pass-credit slice.
    /// @param balance The pool AFTER the debit.
    event CrapsProgressivePaid(
        uint256 indexed betId,
        bytes32 indexed battleKey,
        address indexed player,
        bool rare,
        uint16 poolBps,
        uint256 peak,
        uint256 scoreBps,
        uint256 candidate,
        uint256 paid,
        uint256 balance
    );

    /// @notice A day the advance never opened was crossed by the scheduled cursor: every seat
    ///         reserved on it was refunded. Nobody else could have entered — a dead day's doors
    ///         were shut by the clock and the missing word the whole time. `seats` counts the day
    ///         tickets, each handed its pass credit back (its own `CrapsPassesCredited` precedes
    ///         this); every window-ahead seat in the day's windows was refunded too, its comp's
    ///         price back to the comp lane.
    event CrapsDayLapsed(uint24 indexed day, uint64 seats);

    /// @notice A scheduled field or expired maintenance prefix was retired without further awards.
    /// @dev Scheduled wagers and lapsed refunds remain eligible through day D+30. For maintenance,
    ///      slot is the first skipped position; all days older than today minus 30 are skipped.
    event CrapsScheduledExpired(uint64 indexed slot);

    struct JackpotRound {
        uint256 word;
        uint256 added;
        uint256 totalPool;
        uint256 potRemainder;
        uint128 bankroll;
        uint64 paidUnits;
        uint32 bountyUnits;
        uint32 multiplierBps;
        uint32 paidCount;
        uint32 drawnCount;
        uint32 drawnUnits;
        uint24 level;
        uint24 requestDay;
        uint32 awardTarget;
        // Fill slot 5's spare bytes; drawWord/drawCursor retain slots 6/7.
        uint32 entryPrice;
        uint32 subsidyMultiplierBps;
        uint256 drawWord;
        uint256 drawCursor;
    }
    mapping(uint256 => JackpotRound) internal _jackpotRounds;
    uint64 internal _activeJackpotSlot;
    /// @dev One packed word per event. The nominee is sampled over the immutable paid high
    ///      field as settlement advances; cursor counts paid seats examined, including normals.
    struct HighRollerDraw {
        address nominee;
        uint32 eligible;
        uint32 cursor;
        bool resolved;
        bool won;
    }
    // Append-only: both delegate contracts inherit these exact slots.
    uint256 internal _highRollerReserve;
    mapping(uint64 => HighRollerDraw) internal _highRollerDraws;
    uint256 internal constant _HIGH_RESERVE_DIVISOR = 20; // 5% of unrolled gross Added
    uint256 internal constant _HIGH_RESERVE_CHANCE = 10; // one field-wide chance in ten
    uint256 internal constant HIGH_RESERVE_DRAW_TAG = uint256(keccak256("CrapsHighReserveDraw"));
    uint256 internal constant HIGH_RESERVE_WINNER_TAG = uint256(keccak256("CrapsHighReserveWinner"));
    uint256 internal constant _JACKPOT_BANKROLL_UNIT = 300;
    uint256 internal constant _JACKPOT_PRICE = CrapsPriceLib.JACKPOT_FEE;
    uint256 internal constant _AWARD_UNITS_SHIFT = 224;
    uint256 internal constant JACKPOT_MULT_TAG = 0x436f696e447261774d756c7469706c696572;
    uint256 internal constant JACKPOT_SUBSIDY_TAG = uint256(keccak256("CrapsJackpotSubsidy"));

    event JackpotBattleLocked(uint64 indexed slot, uint24 requestDay, uint256 added, uint256 paidEntries);
    event JackpotBattleStarted(uint64 indexed slot, uint24 level, uint256 drawnEntries, uint256 drawnUnits, uint256 word);
    /// @notice The hidden subsidy result, frozen once after entry locks. Reserve funding is excluded.
    event JackpotSubsidyRolled(uint64 indexed slot, uint32 multiplierBps, uint256 mainSubsidy);
    event HighRollerReserveFunded(uint64 indexed slot, uint256 contribution, uint256 balance);
    /// @notice A finalized event's single reserve draw. No eligible entries means no attempt.
    /// @param winner Zero on a miss or an empty eligible field.
    /// @param amount Existing reserve value released as Coinflip credit, never fresh funding.
    event HighRollerReserveDrawn(
        uint64 indexed slot, uint32 eligible, address indexed winner, uint256 amount, uint256 balance
    );
    /// @notice Fee-only high exposure and its expected-loss comp allocation, before the fair pool roll.
    /// @dev 80% of the conservative loss budget funds comps; the rest remains unissued. This is
    ///      theoretical loss, not the result of a particular run or the pool multiplier.
    event JackpotHighCompsAccrued(
        uint64 indexed slot, uint256 fees, uint256 atRisk, uint256 lossBudget, uint256 comps
    );
    uint64[4] internal _fundedCustomSlots;
    mapping(uint48 => uint64[]) internal _rngSlots;
    uint64[2] internal _rngSlotCursor;
    uint64[2] internal _rngPending;

    function _highMultOf(uint256 word) internal pure returns (uint256) {
        if (word == 0) return 0;
        return CrapsPriceLib.highMultiple(_hash2(word, HIGH_TAG));
    }

}
