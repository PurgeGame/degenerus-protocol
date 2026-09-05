// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Craps} from "./Craps.sol";
import {LootboxCraps} from "./LootboxCraps.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";

/// @dev The one FLIP sink this game uses, authorized to `ContractAddresses.CRAPS` in the
///      protocol's FLIP.sol. Craps only ever BURNS: a stake goes in and nothing here hands liquid
///      FLIP back, because nothing here is ever given back. Every payment — a run's winnings, a
///      pot, a lane — ships as coinflip credit.
interface IFlipCoin {
    function burnCoin(address target, uint256 amount) external;
    /// @dev The paid-craps twin. Takes the price with action flags in its low byte and hands back
    ///      the one-hot craps-boon tier consumed by this burn (0 on every burn that consumed none).
    function burnCoinForCraps(address target, uint256 grossAndFlags) external returns (uint8 boonMask);
}

/// @dev The vault's ownership test — a majority DGVE holder. The only authority this contract
///      recognises, and it grants exactly one thing: the right to OPEN a custom battle.
interface IVaultOwnership {
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev Requests the lootbox word that will fill a newly selected table index.
interface IGameLootboxRng {
    function requestLootboxRng() external;
}

/// @dev Supplies the entry-time standing used for a battle's minimum-score gate and last
///      merit component. An exact score tie is resolved from the table word.
interface IGameActivityScore {
    function playerActivityScore(address player) external view returns (uint256 scorePoints);
}

/// @dev Run winnings and competitive battle pots pay as next-day coinflip stake. The batch lane
///      lets a slot settle many entrants with one external call.
interface ICoinflipStake {
    function creditFlip(address player, uint256 amount) external;
    function creditFlipBatch(address[] calldata players, uint256[] calldata amounts) external;
    /// @notice Arm THE BIGGEST DICE RUN — the fifth category of the shared BIGGEST record.
    /// @dev CRAPS only, and this kind only: the generic `armRecord` door is the GAME's and
    ///      carries the four existing kinds' 20%-improvement claim rule, which is not this one's.
    ///      Coinflip credits the claim itself, so a finalization makes ONE call and the player
    ///      takes ONE credit.
    /// @param candidate The winner's high point over its starting bankroll, in basis points.
    /// @dev DECLARED WITHOUT ITS RETURN, deliberately. `Coinflip` returns the FLIP it claimed and
    ///      logs it in `BigRecordUpdated`; nothing on this side of the call needs the figure, so
    ///      the table does not pay to decode one. The selector is the same either way.
    function armDiceRunRecord(address player, uint256 candidate) external;
}

/// @title CrapsBattle
/// @notice Slot-based FLIP craps battles. A slot fixes one bankroll, goal, ten-chip round,
///         battle stake and standing bar for every entrant. A player places zero through seven
///         chips and leaves the rest of the ten to the draw.
///
/// @dev Entry burns the bankroll plus any battle stake. Closing a slot binds it to
///      `_currentIndex()`, the table whose word cannot exist yet, and asks for that word. `resolveSlot`
///      walks the slot's dense, 1-based seats and credits each run's rounded return as coinflip
///      stake. A non-zero battle stake also records a single running leader, and the seat that
///      completes the field hands that leader the pot in the same call — there is no claim.
///
///      Bet ids encode membership as `(slot << 64) | seat`. The stored bet word therefore needs
///      only the owner, selected chip counts and entry-time standing. A per-slot cursor carries
///      the settled high-water mark without one write per bet. Until its slot closes, an
///      owner may name or re-spread those chip counts with `amendSlip`, a blank ticket included —
///      the terms and the seat are the slot's, so nothing an amendment touches can move value or
///      change the field.
///
///      Bonus slots are derived from the protocol day and opened from a committed daily word.
///      Custom slots are opened by approved creators with explicit terms and a future close time.
///      In both cases entrants know the terms but not the settlement word before entry closes.
///
///      This contract depends on the pinned FLIP, Coinflip, Vault and Game addresses. FLIP and
///      Coinflip must in turn authorize `ContractAddresses.CRAPS` for burns and credits.
contract CrapsBattle is LootboxCraps {
    /// @notice A craps price reached the burn lane with a dirty low byte, where the action flags
    ///         ride. Unreachable by construction — every price is a whole-FLIP multiple — and a
    ///         hard stop rather than a silent mis-tag if that ever stops being true.
    error BadBurnTag();

    /// @notice A custom battle was opened on terms it may not have. ONE error for the whole
    ///         definition — round, bankroll depth, goal band, bounty ceiling and granule field,
    ///         standing bar, close time and high-roller multiple — rather than one per field.
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

    /// @notice The battle asks for more standing than the caller held at entry.
    error ScoreRequiredForBonus();

    /// @notice An entrant supplied neither zero nor seven selected chips, or a custom battle's
    ///         standing bar exceeds `_MAX_MIN_SCORE`.
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

    /// @notice Minimum bankroll for a custom battle, in whole FLIP.
    uint256 internal constant _MIN_BANKROLL_FLIP = 300;

    /// @notice Maximum custom-battle bankroll depth, in rounds.
    uint256 internal constant _MAX_BANKROLL_MULT = 25;

    /// @notice Minimum goal, as a multiple of the battle bankroll.
    uint256 internal constant _MIN_BATTLE_GOAL_MULT = 5;

    /// @notice Maximum goal, as a multiple of the battle bankroll.
    uint256 internal constant _MAX_GOAL_MULT = 1000;

    /// @notice Interval between the six routine bonus-window close times.
    uint256 internal constant _BONUS_PERIOD = 4 hours;
    /// @notice Seven windows per day: the short opener, five routine windows, then the event.
    uint256 internal constant _BONUS_PERIODS_PER_DAY = 7;
    /// @notice Width of one day in the bonus slot namespace. Remainder zero is reserved; the
    ///         seven live windows use remainders one through seven.
    uint256 internal constant _BONUS_SLOTS_PER_DAY = 8;
    /// @notice Delay after day start before the period-zero opener may be shut.
    uint256 internal constant _BONUS_EVENT_CLOSE = 20 minutes;
    /// @notice Shifts every ROUTINE close onto a round wall-clock time.
    ///
    ///         The protocol day starts at 22:57 UTC — three minutes shy of the hour — so a ladder
    ///         measured from the day's own start lands every window at :57 past. Three minutes of
    ///         offset puts the five routine closes on 03:00, 07:00, 11:00, 15:00 and 19:00 and the
    ///         opener on 23:20, which is what lets a schedule be published as clock times rather
    ///         than as offsets nobody can hold in their head.
    ///
    ///         The EVENT is deliberately outside this: its close is measured backwards from the
    ///         day's turnover, not forwards from its start, because what it has to stay clear of
    ///         is the jackpot.
    uint256 internal constant _BONUS_CLOCK_ALIGN = 3 minutes;
    /// @notice How far AHEAD of the day's turnover the event window shuts.
    ///
    ///         The protocol day turns at jackpot time, so a window closing on the boundary itself
    ///         could not be settled until the next day had already begun — its table, and every
    ///         lootbox waiting on the same draw, would land after the jackpot they were meant to
    ///         precede. Shutting the event a quarter-hour early puts its arm, its RNG request and
    ///         its settlement all inside the run-up instead: the day's biggest table resolves in
    ///         front of an audience that has somewhere to be, and the same draw clears the
    ///         lootbox queue before the jackpots go out.
    uint256 internal constant _EVENT_LEAD = 15 minutes;

    /// @notice The routine windows' tiers, as whole FLIP: total buy-in (bankroll PLUS bounty),
    ///         the bounty inside it, and the house seed that rides on top. Drawn 7:2:1.
    uint256 internal constant _BONUS_SMALL_BANKROLL = 300;
    uint256 internal constant _BONUS_MED_BANKROLL = 1200;
    uint256 internal constant _BONUS_LARGE_BANKROLL = 3000;

    /// @notice Chips in every round. An entrant places zero through seven; the draw scatters the rest.
    uint256 internal constant _BONUS_CHIPS = 10;

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
    ///         WHY TWELVE. Measured post-boost on the shipped resolver across the nine scheduled
    ///         depth/target formats at five million runs a cell, the weakest still leaves the
    ///         table 13.72% of the bankroll it was bought with — a run that goes broke has its
    ///         remainder deleted, and that deletion is what pays for the subsidy. Twelve sits
    ///         under the worst cell, so the linear term cannot outrun the engine's own take at
    ///         any format on the schedule.
    ///
    ///         A WHOLE-RUN FIGURE, NOT A PER-BET EDGE — the two are nothing alike here. A slip
    ///         re-bets its whole bankroll hand after hand chasing five to fifty times it out of
    ///         two to ten rounds of depth, so what decides the loss is almost never the edge on
    ///         any leg; it is that the run busts first.
    uint256 internal constant _BOOST_ACTION_BPS = 1200;
    uint256 internal constant _BPS_DENOMINATOR = 10_000;

    /// @notice The largest round a battle may post. A BLANK ticket leaves all ten chips to the
    ///         dice and they may land on ONE leg, so the whole round has to fit the resolver's
    ///         `uint24` leg — the table maximum `Craps` documents. `_CB_PLAYED_MASK` is only how
    ///         wide the stored field is, and a round between the two would silently truncate the
    ///         board it was paid for.
    uint256 internal constant _MAX_ROUND_FLIP = type(uint24).max;

    /// @notice THE ABSOLUTE SEAT CEILING for one `resolveSlot` call, independent of whatever
    ///         budget the caller supplies. It bounds the two credit arrays and the loop counter,
    ///         so one call can never be made to allocate or iterate without limit — and it is the
    ///         only bound that does not depend on gas being measured correctly.
    ///
    ///         It is NOT the throughput knob. A production crank stops on its BUDGET long before
    ///         this; a field deeper than it settles over as many calls as it needs, carried by the
    ///         slot's cursor. At the cheapest seat the table can produce this is still a very
    ///         large call, which is why the budget and not the ceiling is what sizes a crank.
    uint64 internal constant _RESOLVE_MAX_SEATS = 256;

    /// @notice A SEAT'S WORK, IN THE PROTOCOL'S OWN WALK UNITS (~4.7k gas each, the same unit
    ///         every box leg budgets in) — deterministic, derived from the seat's OUTCOME after it
    ///         settles rather than from a gas meter:
    ///
    ///             cost = _SEAT_UNITS + rolls / _ROLLS_PER_UNIT + (paid ? _CREDIT_UNITS : 0)
    ///
    ///         The engine already reports the roll count, and rolls are what a seat's cost
    ///         actually varies by — two orders of magnitude between a three-roll bust and a
    ///         four-hundred-roll run — so the unit charge keeps the outcome sensitivity a flat
    ///         per-seat weight never had, while staying replayable: the same chain state stops
    ///         the same batch at the same seat, on every node, under every gas schedule.
    ///
    ///         Each weight rounds its measured cost UP so the charge is conservative everywhere:
    ///         seat plumbing ~28k → 7 units (32.9k); dice 578-699 gas a roll → a unit per 6
    ///         rolls (783 budgeted); a distinct cold coinflip credit 25,910 → 6 units (28.2k).
    uint256 internal constant _SEAT_UNITS = 7;
    uint256 internal constant _ROLLS_PER_UNIT = 6;
    uint256 internal constant _CREDIT_UNITS = 6;

    /// @notice What one lapsed-day reservation refund charges: a pass-credit write, two logs and
    ///         the resumable sweep cursor — ~33k measured cold, rounded up.
    uint256 internal constant _SWEEP_SEAT_UNITS = 8;

    /// @notice How many days of action a budget is drawn from.
    uint256 internal constant _BOOST_ACTION_WINDOW_DAYS = 7;

    /// @notice The most cheap cursor hops one `keepScheduled` call may take — finalized windows,
    ///         empty armed fields and day separators crossed without doing real work. Two days'
    ///         worth of slots, so a backlog of externally-settled days still clears at a bounded
    ///         and predictable per-call cost.
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
    uint256 internal constant _BASE_MAIN_BUDGET = 50_000 ether;

    /// @notice The top of the boost ladder. EVERY window is the same lottery: it advertises
    ///         `up to` this many times its share of the day, and the rung is drawn from the word
    ///         that SETTLES the table — which does not exist while anyone can still enter.
    uint256 internal constant _BOOST_MAX_MULT = 100;

    /// @notice THE PROGRESSIVE'S RUNGS, in BASIS POINTS of the LIVE pool at the moment a field
    ///         finalizes. Two rungs, and two window classes — because the day's EVENT is its
    ///         headline and is paid for being one:
    ///
    ///           window                     common   rare
    ///           routine (periods 0..5)        5%     10%
    ///           event   (period 6)           20%     40%
    ///           event, after a repeat        40%     80%
    ///
    ///         THE REPEAT DOUBLE IS THE EVENT'S ALONE. A routine window never doubles, whatever
    ///         its winner did earlier in the day: the double is what makes the headline worth
    ///         chasing from the day's FIRST window, and a routine rung that could double would be
    ///         paying for that chase twice over.
    ///
    ///         The rare rung is tested first and OVERRIDES, so a field never pays both. Note that
    ///         a doubled common event rung and an undoubled rare one are the same 40% — the
    ///         `rare` flag on the award log is what separates them.
    uint256 internal constant _PROG_ROUTINE_COMMON_BPS = 500;
    uint256 internal constant _PROG_ROUTINE_RARE_BPS = 1000;
    uint256 internal constant _PROG_EVENT_COMMON_BPS = 2000;
    uint256 internal constant _PROG_EVENT_RARE_BPS = 4000;

    /// @dev The same four rungs as DOUBLINGS of the routine common share, which is how the award
    ///      applies them: rare is worth one, the event two more, and a repeat victory one further.
    ///      `_PROG_ROUTINE_COMMON_BPS << shift` reproduces the table above exactly, and
    ///      `CrapsProgressive.t.sol` holds the two statements of it together.
    uint256 internal constant _PROG_RARE_DOUBLINGS = 1;
    uint256 internal constant _PROG_EVENT_DOUBLINGS = 2;

    /// @dev THE HIGH-POINT CUTOFFS, in SCORE BASIS POINTS — the
    ///      winner's high point over its own starting bankroll, 10,000 being 1x. INCLUSIVE:
    ///
    ///        common          rare
    ///        250,000 (25x)   1,200,000 (120x)
    ///
    ///      A MULTIPLE, not a roll count. The old cutoffs read the winner's cumulative roll
    ///      prefix, which measured how LONG a run took rather than how far it got; a high-water
    ///      run is not trying to be quick, so the roll prefix stopped saying anything about it.
    ///      The high point adds no draw of its own either — it is a figure the settlement already
    ///      computed — and it rewards exactly the thing the format is now about.
    ///
    ///      TESTED IN BASIS POINTS, not in FLIP, and the two are the same test: the score is
    ///      `floor(peak * 10_000 / start)`, and for integers `floor(a/b) >= c` is exactly
    ///      `a >= c * b`. So comparing the floored score to a bps cutoff is comparing the whole
    ///      high point to a multiple of the bankroll, without the multiplication.
    uint256 internal constant _PROG_COMMON = 250_000;
    uint256 internal constant _PROG_RARE = 1_200_000;

    /// @dev Where a `CrapsProgressiveRolled` came from: the main ladder, a contested high lane,
    ///      or the boost capital a sole high rider's standing would not admit. Carried to
    ///      `_rollIn` in the TOP BYTE of the amount — an amount is FLIP wei and nowhere near
    ///      2^248, and the packing keeps every call's arguments opaque enough that the optimizer
    ///      shares one copy of the bank instead of specializing three.
    uint256 internal constant _ROLL_SRC_MAIN = uint256(1) << 248;
    uint256 internal constant _ROLL_SRC_HIGH_CONTESTED = uint256(2) << 248;
    uint256 internal constant _ROLL_SRC_HIGH_SOLE = uint256(3) << 248;

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

    /// @notice Ceiling on a battle's 12-bit standing requirement.
    uint256 internal constant _MAX_MIN_SCORE = 0xFFF;

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
    //   bits  61.. 72  minScore   the standing bar
    //   bits  73..112  closeTime  when entry shuts and the table may be taken
    // The chips left to the dice are not a term: every ticket places zero through seven and
    // scatters the complement, but all play the slot's same ten-chip round.
    uint256 private constant _CB_PLAYED_MASK = 0xFFFFFFF;
    uint256 private constant _CB_BANK_SHIFT = 28;
    uint256 private constant _CB_BANK_MASK = 0x1F;
    uint256 private constant _CB_GOAL_SHIFT = 33;
    uint256 private constant _CB_GOAL_MASK = 0x3FF;
    uint256 private constant _CB_STAKE_SHIFT = 43;
    uint256 private constant _CB_SCORE_SHIFT = 61;
    uint256 private constant _CB_CLOSE_SHIFT = 73;
    uint256 private constant _CB_CLOSE_MASK = 0xFFFFFFFFFF;

    /// @notice Granularity of battle stakes, seeds and tier boosts.
    uint256 internal constant _BATTLE_STAKE_UNIT = 100 ether;

    /// @notice The activity score at which house money pays in full. ANYONE may play any battle —
    ///         nothing gates the door — but a winner below this collects only `1 / (floor - score)`
    ///         of the BOOST, and the rest is burned. Score 11 takes all of it, 6 takes a sixth, 1
    ///         takes an eleventh, and a scoreless wallet takes NONE.
    ///
    ///         It bites exactly where a sybil profits and nowhere else. Splitting a bankroll over
    ///         fresh wallets buys more seats in a field that allows one, but the only free money
    ///         in the pot is the house's — every bounty was posted by the seat that holds it. So
    ///         the entrants' stakes and the busted crumbs always pay out whole, and only the
    ///         subsidy is rationed. A single account that plays clears this within days.
    uint256 internal constant _SYBIL_SCORE_FLOOR = 12;

    /// @notice The two sizes a protocol day's high-roller lane can take, and how often. One roll
    ///         off the day's own committed word decides which, nine days in ten the smaller: a
    ///         high roller buys `_HIGH_MULT` copies of the run AND posts that many bounties, so
    ///         the tail day is a hundred times the ordinary seat rather than ten.
    uint256 internal constant _HIGH_MULT = 10;
    uint256 internal constant _HIGH_MULT_TAIL = 100;

    /// @notice The ceiling on a CUSTOM battle's high-roller multiple. A creator names any figure
    ///         from two to here, or zero to run the battle without a high lane at all.
    uint256 internal constant _MAX_HIGH_MULT = 256;

    /// @notice What part of the HIGH lane's own component goes to the main boost rather than
    ///         staying with the lane that earned it. Two parts in five — so twelve percent of high
    ///         action reads 4.8 points to the main lane and 7.2 to the high one.
    uint256 internal constant _HIGH_MAIN_NUM = 2;
    uint256 internal constant _HIGH_MAIN_DEN = 5;

    /// @dev Ceiling imposed by the scoreboard's 18-bit stake field.
    uint256 internal constant _BSTAKE_MAX = 0x3FFFF;

    /// @dev Separates the per-bet rounding roll from everything else on the same committed word.
    uint256 internal constant FLIP_ROUND_TAG = 0x466c6970526f756e64; // "FlipRound"
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
    //   bits 190..205  entry-time standing
    //   bits 206..208  the craps boon riding this slip, one-hot (see _BET_BOON_SHIFT)
    //   bits 209..216  unused (the entry multiple is carried on the event, never stored)
    //   bits 217..223  high-roller flags: bit 217 alone on a window-local slip, bit 217 + p per
    //                  period on a day ticket
    //   bits 224..255  unused
    // The mapping key is `(slot << 64) | seat`; slot terms live once per field, and the resolve
    // cursor carries the one lifecycle mark a slip needs.
    /// @dev The ten legs, three bits each, as chip counts, in the CANONICAL order — the identical
    ///      thirty-bit word `CrapsSlipPlaced` carries in its low bits, so storage and the log
    ///      agree without a translation anywhere. All ten zero leaves the whole round to the draw;
    ///      the submitted counts may sum to at most seven, and settlement scatters the complement.
    ///      Three bits is the right width because the per-leg cap fits and no submitted total may
    ///      exceed seven.
    uint256 internal constant _BET_CHIPS_SHIFT = 160;
    uint256 internal constant _BET_CHIPS_MASK = 0x3FFFFFFF;
    /// @dev The entrant's standing, frozen at entry. Chip composition may be amended before the
    ///      slot closes, but this score component never changes: standing earned after joining
    ///      must not decide a race already entered.
    uint256 internal constant _BET_SCORE_SHIFT = 190;
    uint256 internal constant _BET_SCORE_MASK = 0xFFFF;

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
    uint256 internal constant _BET_DAYHIGH_MASK = 0x7F << 217;

    /// @dev Where the DON'T PASS count sits inside the chip word — the tenth and last leg. The
    ///      same position in storage and in every event, since the two carry the identical word.
    /// @notice The one `setVaultBoard` value that is NOT a board: an instruction to sit out. Above
    ///         every legal packed board — those occupy thirty bits and this sets thirty-two — so it
    ///         can never collide with a shape anyone could name.
    uint32 internal constant _VAULT_BOARD_OFF = type(uint32).max;

    /// @dev Bit 0 of every one of the ten three-bit legs. Shifting each leg's `4` bit onto this
    ///      mask makes the three-chip ceiling one board-wide test.
    uint256 internal constant _CHIP_LO_MASK = 0x9249249;

    uint256 internal constant _CHIP_DONT_SHIFT = 27;
    uint256 internal constant _CHIP_DONT_MASK = 7;

    /// @dev Bit 113 of a custom battle's terms: one address may take as many seats as it pays for.
    uint256 internal constant _CB_MULTI_BIT = 1 << 113;

    /// @dev A custom battle's high-roller multiple, bits 114..122: literal 0..256, where 0 is a
    ///      battle with no high lane and 1 is not a multiple at all.
    uint256 internal constant _CB_HIGH_SHIFT = 114;
    uint256 internal constant _CB_HIGH_MASK = 0x1FF;

    /// @dev Where the multiple sits in `Window.terms`, above the bounty and the bar, so the match
    ///      key commits to the whole of a field's economics and a lane read one way at entry and
    ///      another at settlement keys a different battle instead of mispaying this one.
    uint256 internal constant _TERM_HIGH_SHIFT = 44;

    /// @dev The high-roller sideboard, ONE word per battle that actually takes a high seat:
    ///        bits   0.. 31  how many high seats the field holds
    ///        bits  32..136  the best composite among them, the SAME 105-bit score the main
    ///                       scoreboard ranks on, so neither lane can rank on money it scaled
    ///        bits 137..168  the seat holding that lead
    ///        bit  169       done: the sole rider settled, or the competitive award was paid
    ///      Nothing else is needed. Main finalization proves every high score has been folded,
    ///      the head count is known from entry, and the principal follows from `H`, the bounty
    ///      and that count.
    uint256 internal constant _HF_SCORE_SHIFT = 32;
    uint256 internal constant _HF_WINNER_SHIFT = 137;
    uint256 internal constant _HF_DONE_BIT = 1 << 169;

    /// @dev A day's ticket word holds EIGHT counts in ONE slot: the total in the low 32 bits and
    ///      one high-roller count PER PERIOD above it, 32 bits each — period `p`'s at bits
    ///      `32(p + 1)`. Per period because an upgrade buys the lane one window at a time; still
    ///      one slot, so selling a day ticket writes one word and arming still folds the total
    ///      and its own period's high count into a window in one read.
    uint256 internal constant _DT_HIGH_SHIFT = 32;
    /// @dev One high ticket in EVERY period's counter — what a whole-day high entry adds.
    uint256 internal constant _DT_ALL_HIGH = 0x0000000100000001000000010000000100000001000000010000000100000000;

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

    /// @dev The standing a battle asks of its entrants. A battle TERM, so it is in the match key:
    ///      a field is only a fair race if everyone in it cleared the same bar.
    uint256 internal constant _BET_MINSCORE_MASK = 0xFFF;

    /// @dev The two non-money terms, packed for the key: bounty granules in 0..23, standing bar
    ///      in 32..43. They live on the SLOT, never in a header. The chips a ticket leaves to the
    ///      dice are NOT a term — that is a per-ENTRANT choice, and every split between placed and
    ///      scattered chips puts the same round down, so all eight shapes race in ONE field.
    uint256 internal constant _TERM_SCORE_SHIFT = 32;

    /// @dev A ticket may place at most seven of the round's ten chips. The dice scatter the rest.
    uint256 internal constant _MAX_PICKED_CHIPS = 7;

    // Battle scoreboard packing — one battle's entire shared state in one word.
    //   bits   0.. 31  entrants        bits  32.. 63  resolved
    //   bits  64..168  the leading COMPOSITE score
    //   bits 169..200  the SEAT holding it
    //   bits 201..218  battle stake granules (echo, for views)
    //   bits 219..249  seed granules
    //   bits 250..255  free
    //
    // THE ROLL SLICE IS GONE. It held thirteen bits, which a scheduled run's 8,703-roll ceiling no
    // longer fits, and nothing ranks or qualifies on rolls any more — the progressive reads the
    // winner's HIGH POINT, which the composite already carries. Its bits went to the composite,
    // which needs them: a high-water verdict is a goal flag, a high point, an ending bankroll and
    // a standing, and no two of those may share a field.
    uint256 internal constant _BG_RESOLVED_SHIFT = 32;
    uint256 internal constant _BG_BEST_SHIFT = 64;
    uint256 internal constant _BG_WINNER_SHIFT = 169;
    uint256 internal constant _BG_STAKE_SHIFT = 201;
    uint256 internal constant _MASK32 = 0xFFFFFFFF;

    /// @dev THE MERIT VERDICT as one lexicographic scalar, so the common fold is one comparison.
    ///      One hundred and five bits, most significant first:
    ///
    ///        bit  104     GOAL. Every goal beats every bust.
    ///        bits 60..103 THE PRIMARY, read one way for each stop:
    ///                       * a goal ranks on its HIGH POINT, in whole FLIP;
    ///                       * a bust ranks on shooters completed.
    ///        bits 16..59  THE MONEY: the raw ENDING bankroll in whole FLIP — a goal's payout
    ///                     figure, a bust's surviving remainder — never the high point.
    ///        bits  0..15  the entrant's STANDING, frozen at entry.
    ///
    ///      Exact equality is resolved separately by the table word's deterministic ordering of
    ///      bet ids, so settlement order cannot choose the winner.
    ///
    ///      BOTH MONEY FIELDS SATURATE rather than mask. A mask would wrap a seventeen-trillion-
    ///      FLIP figure to a small one and rank it WORSE; saturating can only ever fail to
    ///      separate two runs that are already past the horizon, and the comparison then falls
    ///      through to the next field. The largest bankroll the schedule can hand out is 60,000
    ///      FLIP, so reaching the field's ceiling means a 2.9e8x run — the same order of
    ///      unreachable as the engine's own 512-roll hand bound.
    uint256 internal constant _SC_GOAL_BIT = 1 << 104;
    uint256 internal constant _SC_PRIMARY_SHIFT = 60;
    uint256 internal constant _SC_PRIMARY_MASK = 0xFFFFFFFFFFF;
    uint256 internal constant _SC_WON_SHIFT = 16;
    uint256 internal constant _SC_WON_MASK = 0xFFFFFFFFFFF;
    uint256 internal constant _SC_BEST_MASK = (1 << 105) - 1;
    // The bonus seed lives in the battle's OWN word, not in a global "currently armed" pointer:
    // a seeded battle can still be settling long after the next arm, and its pot must not depend
    // on what is armed by then. In `_BATTLE_STAKE_UNIT` granules — DONATIONS ONLY: a window's
    // own seed is a function of the day's word and is never stored here.
    uint256 internal constant _BG_SEED_SHIFT = 219;
    uint256 internal constant _BG_SEED_MASK = 0x7FFFFFFF;

    /// @notice A placed bet slip, decoded — what `_betOf` returns. Storage keeps one packed word,
    ///         under the key `(slot << 64) | seat`.
    /// @param player        Who staked it, and the only address any payment can ever reach.
    /// @param slot          The battle this slip sits in. Its terms — bankroll, target, bounty,
    ///                      bar — are the SLOT's; read them with `_customBattleOf` or
    ///                      `_bonusTermsFor`.
    /// @param seat          This entrant's place in its field, 1-based — the low half of its id.
    /// @param settled       Whether it has been resolved, read off the slot's resolve cursor.
    /// @param battleClaimed Whether this slip's battle has paid. A battle pays the instant its
    ///                      last seat scores, so this is simply whether the field finished.
    /// @param chips         The ten leg counts as one thirty-bit word, three bits each — the nine
    ///                      light legs at bits 0..26 and the dark side at 27..29. Zero is a blank
    ///                      ticket; the draw places all ten chips.
    /// @param standing      The entrant's activity score, frozen at entry — the last merit
    ///                      component before a word-derived exact-tie break.
    /// @dev The header is created at placement. Its chip slice may change through `amendSlip`
    ///      before close; settlement never writes the bet, and the slot's cursor carries its
    ///      settled mark.
    struct Bet {
        address player;
        uint64 slot;
        uint64 seat;
        bool settled;
        bool battleClaimed;
        uint256 chips;
        uint256 standing;
    }

    /// @notice One battle's scoreboard, decoded — what `_battleOf` returns.
    /// @param entrants     Slips entered (and still in) the battle.
    /// @param resolved     Entrants whose runs have settled.
    /// @param winnerId     The winning seat within this slot; combine it with the slot for the bet id.
    /// @param finalized    Every entrant resolved: the scoreboard is the verdict.
    /// @param winningStop  The winning outcome class, meaningful once finalized.
    /// @param winningHands The winning hand count — meaningful once finalized, and only where the
    ///                     composite encodes it: a BUST, whose primary is its shooter count. A
    ///                     goal ranks on its high point instead and reports zero here.
    /// @param winningPeak  The winner's HIGH POINT in whole FLIP, once finalized.
    /// @param winningEnd   The winner's raw ENDING bankroll in whole FLIP, once finalized — what
    ///                     it was actually paid on, which a goal's peak may sit well above.
    /// @dev The high point AS A MULTIPLE is not restated here: a battle key is a hash, so this
    ///      reader cannot recover the starting bankroll to divide by. `CrapsBattleFinalized`
    ///      carries `winningScoreBps` for exactly that reason, and a caller holding the window's
    ///      terms divides `winningPeak` by them.
    /// @param battleStake  One entrant's stake (wei).
    /// @param seed         House money banked on this battle (wei); zero for an unseeded custom one.
    ///                     Every field that forms pays it out — there is no head count below which
    ///                     it falls back out of the pot.
    /// @param pot          `battleStake x entrants`, plus banked seed (wei). A tier boost is drawn
    ///                     from the word that settles the field and is therefore not included here.
    struct Battle {
        uint64 entrants;
        uint64 resolved;
        uint64 winnerId;
        bool finalized;
        Craps.SlipStop winningStop;
        uint16 winningHands;
        uint256 winningPeak;
        uint256 winningEnd;
        uint256 battleStake;
        uint256 seed;
        uint256 pot;
    }

    /// @dev One settlement's whole account, carried between the engine and the paying/preview
    ///      paths as a single memory pointer — the resolver is sensitive to stack pressure.
    ///      Its layout deliberately matches `Craps.SlipResult`: `paid` reuses the dead
    ///      `bankrollIn` word, `won` aliases `bankrollOut`, and `unitsPlayed` keeps the otherwise
    ///      unused fifth word in place. `_settlementOf` can therefore reuse the engine result
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
        ///      it is never what the run is paid, and a bust's peak reaches neither — the
        ///      comparator drops it the moment the goal bit is clear.
        uint256 peak;
        uint256 handsPlayed;
        /// @dev Retained to preserve `SlipResult`'s memory layout. The resolver does not rank or
        ///      charge on escalated units, but keeping the word avoids a five-word copy per seat.
        uint256 unitsPlayed;
        /// @dev Dice rolls across the run. It ranks NOTHING and qualifies nothing — the
        ///      progressive reads the high point now — and survives only as the settle walk's
        ///      work-unit charge and as telemetry.
        uint256 totalRolls;
        Craps.SlipStop stop;
    }

    /// @dev A bet is ONE word — `player | chips | standing`, and nothing else. It does not carry
    ///      which battle it is in, because that is the KEY it is stored under: an id is
    ///      `(slot << 64) | n`, where `n` is the entrant's index within its own field. Membership
    ///      is therefore structural — `n` runs 1..entrants with no gaps — so a settler walks a
    ///      field without reading a single id that is not in it.
    mapping(uint256 => uint256) internal _bets;

    /// @notice Custom battles opened so far. The next takes slot `_CUSTOM_SLOT_BASE + this + 1`.
    uint64 internal _customBattleCount;

    /// @dev Battle scoreboards, by match key (see `_battleKey`).
    mapping(bytes32 => uint256) internal _battles;

    /// @dev Who has already taken their one seat in a house-backed field. Unseeded custom
    ///      battles permit separately funded repeat entries.
    mapping(bytes32 => mapping(address => bool)) internal _bonusSeated;

    /// @dev Opened bonus day plus one; zero means no day has been opened yet.
    uint256 internal _bonus;

    /// @dev Slot to the table index it closed on, stored as index + 1 so an open slot reads zero.
    mapping(uint256 => uint48) internal _slotIndex;

    /// @dev A slot's settlement high-water mark: every seat at or below it is settled. One word
    ///      replaces one bit per entrant; see `_settledOf` for why `seat <= cursor` is sound.
    mapping(uint256 => uint64) internal _bonusCursor;

    /// @dev How many DAY TICKETS a protocol day sold, with the per-period high counts above the
    ///      total — see `_DT_HIGH_SHIFT`. A day ticket is one bet that plays every window of its
    ///      day, and it is only sold while the day's FIRST window is still taking bets — so the
    ///      TOTAL is frozen before any window can shut, and every window of the day therefore
    ///      plays the same day field. That is what removes the need for a per-window high-water
    ///      mark. A period's HIGH count stays open a little longer — an upgrade may move it until
    ///      that period's own entry close — which is still strictly before the arm that folds it.
    mapping(uint256 => uint256) internal _dayTickets;

    /// @dev The holder's day-ticket SEAT NUMBER, or zero for no claim. Every gate here only ever
    ///      asks NONZERO — one ticket per address per day, and a bar on any single window of that
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

    /// @dev A day's bonus budget in FLIP wei, fixed when the day opens and shared by its seven
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
    ///      game and spent only by their owner.
    mapping(address => uint256) internal _passCredits;

    /// @dev The board the VAULT's automatic day seats play, as packed chip COUNTS. Zero is a blank
    ///      ticket and leaves all ten chips to the dice, which is where this starts.
    ///
    ///      COUNTS, not amounts, which is what lets ONE board serve every window: a chip is worth
    ///      whatever its own window says it is, and the seat plays all seven of them.
    uint256 internal _vaultBoard;

    /// @dev THE PROGRESSIVE. One balance, shared by all nine scheduled formats and by every day.
    ///      Funded once when a protocol day opens — half of what that day's main allocation
    ///      raised — and topped up by every wei of the protocol's own subsidy that a winner's
    ///      activity standing would not admit. It is a virtual emission liability, counted the
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

    /// @dev THE DAY'S ROUTINE GOAL VICTORS: the protocol day on which this address last took a
    ///      ROUTINE field's main bounty with its run finishing as GOAL, stored PLUS ONE so that a
    ///      never-seen address and day zero cannot be confused.
    ///
    ///      Read once a day, by that day's EVENT, to decide whether its progressive rung doubles.
    ///
    ///      KEYED BY ADDRESS ALONE, not by (day, address), because only the LATEST day can ever
    ///      be asked about: the event reads its OWN day and nothing else, so a later day's win
    ///      simply overwrites a spent one and the map never needs clearing. A stale entry from
    ///      any earlier day fails the equality and is indistinguishable from never having won.
    ///
    ///      WRITTEN ON THE VICTORY, NOT ON THE AWARD. A routine winner qualifies its day whether
    ///      or not its own run cleared a progressive cutoff, so the write lives where the field
    ///      is finalized rather than inside the award, which returns early on a short score.
    ///
    ///      DECLARED LAST, so it takes a fresh slot and moves none of the ones above it.
    mapping(address => uint256) internal _routineGoalDay;

    /// @dev What a future day costs bought outright, per day. FIXED constants, deliberately not
    ///      derived from the pass denominations or from each other: the pass is a lootbox award
    ///      priced at the expectation, while these are a retail price with the protocol's margin
    ///      in them, and tying the two together would move one every time the other was retuned.
    ///
    ///      Against the current expected costs — 22,802.12 and 433,240.22 FLIP — these carry
    ///      premiums of about 9.64% and 3.87%. Those are consequences of the numbers, not fields:
    ///      nothing here stores or books a premium, and none of it ever reaches action.
    /// @dev Action flags for the paid-craps burn, riding the LOW BYTE of the amount. Every craps
    ///      price is an integer multiple of 1 ether — the three cost expressions below contain no
    ///      division, and their only wei atoms are `1 ether` and `_BATTLE_STAKE_UNIT` — and 256
    ///      divides 1e18, so the byte is always free. `_tag` proves it rather than trusting it.
    uint256 internal constant _CRAPS_FLAG_JOIN = 0x1;
    uint256 internal constant _CRAPS_FLAG_PASS = 0x2;
    uint256 internal constant _CRAPS_FLAG_NORMAL = 0x4;
    uint256 internal constant _CRAPS_FLAG_HIGH = 0x8;

    /// @dev Normal day passes banked to sDGNRS and the Vault at deployment, each. Enough to cover
    ///      the opening stretch on its own while the lootbox lanes that feed these two start
    ///      paying, and small enough that the field it banks into is nowhere near its ceiling.
    uint256 internal constant _SEED_PASSES = 20;

    uint256 internal constant _NORMAL_FUTURE_DAY_PRICE = 25_000 ether;
    uint256 internal constant _HIGH_FUTURE_DAY_PRICE = 450_000 ether;

    /// @dev Where the high-roller count sits in a pass-credit word.
    uint256 internal constant _PASS_HIGH_SHIFT = 32;

    /// @dev The ceiling on either lane. A lootbox sweep is permissionless and must never revert on
    ///      a full lane, so an award saturates here and reports what it dropped.
    uint256 internal constant _PASS_MAX = 0xFFFFFFFF;

    /// @dev What one banked pass is WORTH when a protocol award pays in passes — the lootbox's own
    ///      expected-cost figures, restated so an award and a box price the same credit
    ///      identically. The denomination switch mirrors the lootbox rule: a pass budget
    ///      strictly above twenty normal units pays high. The thirty-high cap is the award's own.
    uint256 internal constant _NORMAL_PASS_VALUE = 22_800 ether;
    uint256 internal constant _HIGH_PASS_VALUE = 19 * _NORMAL_PASS_VALUE;
    uint256 internal constant _PASS_HIGH_SWITCH = 20 * _NORMAL_PASS_VALUE;
    uint256 internal constant _MAX_HIGH_PASSES_PER_AWARD = 30;

    /// @dev Normal credits one high credit costs in `convertNormalToHigh` — the passes' own 19:1
    ///      value ratio, so conversion moves value exactly and subsidizes nothing. Deliberately
    ///      NOT the 18:1 the retail future-day prices imply; those carry margins the credits
    ///      never did.
    uint256 internal constant _PASSES_PER_HIGH = 19;

    /// @dev `CrapsProtocolAwardSplit.source` values, frozen — carried to `_splitAward` in the
    ///      TOP BYTE of the award argument. An award is FLIP wei and nowhere near 2^248, so the
    ///      byte is always free, and packing the tag keeps the argument opaque enough that the
    ///      optimizer shares ONE copy of the split instead of specializing four.
    uint256 internal constant _SPLIT_SRC_MAIN = uint256(1) << 248;
    uint256 internal constant _SPLIT_SRC_HIGH_CONTESTED = uint256(2) << 248;
    uint256 internal constant _SPLIT_SRC_HIGH_SOLE = uint256(3) << 248;
    uint256 internal constant _SPLIT_SRC_PROGRESSIVE = uint256(4) << 248;
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
    ///            - bits 190..205 the standing the seat froze at entry, at the same shift the bet
    ///              stores it, which is what lets one constant decode both. Nothing the owner does
    ///              afterwards moves it: it breaks a dead-level scoreboard and it rations the
    ///              boost a winner carries off, so a reader that cannot see it can order a field
    ///              only down to a tie and can quote a subsidy only after the fact.
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
    ///         Every other term of the slip is the slot's and cannot move.
    event CrapsSlipAmended(uint256 indexed betId, uint256 chips);

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
    /// @dev THE SHOOTER COUNT IS NOT RESTATED HERE. It is still in the composite the scoreboard
    ///      holds — a bust's primary is its shooter count and a CUSTOM goal's is its speed rank —
    ///      and `Battle.winningHands` decodes it; the log carries the figures the two products
    ///      actually differ on and leaves the derivable one in the word it came from.
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
    ///         forming. `_bonusBoostBand` gives the spread it will be drawn from, `boostOf` gives
    ///         the drawn figure the moment the table's word lands — which is after entry shuts and
    ///         before any hand is settled — and none of it is stored. Entry is open from here
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
    ///        over the newly upgraded windows.
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
    ///         credits, at the credits' own 19:1 value ratio. The ONLY log a conversion emits —
    ///         both lane deltas live here, and no `CrapsPassesCredited` rides along to
    ///         double-count the high addition.
    event CrapsNormalPassesConverted(address indexed player, uint256 normalSpent, uint256 highReceived);

    /// @notice A battle's pot went to its winner, as coinflip credit. A progressive award riding
    ///         the same finalization is a SEPARATE credit and a separate log — this figure is the
    ///         pot and only the pot: the LIQUID figure, after any slice of a scheduled boost
    ///         banked as pass credit under `CrapsProtocolAwardSplit`.
    event CrapsBattlePaid(uint256 indexed betId, bytes32 indexed battleKey, address indexed player, uint256 amount);

    /// @notice A protocol day banked its half of the main allocation in the progressive.
    /// @dev ONCE PER DAY, inside the same guarded block that fixes the ladder half — so repeated
    ///      arms, opens and advances cannot fund it twice, and the absence of this log is how a
    ///      day that never opened is seen.
    /// @param contribution What this day added, in FLIP wei. The ladder half is
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
    /// @param poolBps The rung ACTUALLY APPLIED, in basis points of the live pool: 500/1,000 on a
    ///        routine window, 2,000/4,000 on the day's event, and 4,000/8,000 where the event
    ///        doubled on a repeat victory. Read with `rare` this is the whole decision — a 4,000
    ///        that is not `rare` is a doubled common event rung, and one that is `rare` is an
    ///        undoubled rare one.
    /// @param peak The winner's high point in whole FLIP, the figure that was tested.
    /// @param scoreBps That high point over the run's own starting bankroll, in basis points:
    ///        10,000 is 1x, and the cutoffs are 250,000 / 1,200,000.
    /// @param candidate The rung's whole figure, before the winner's standing is applied.
    /// @param paid What actually LEFT the pool — `candidate` at full standing, less below it —
    ///        so `poolBefore - poolAfter` reconstructs from this figure alone. A slice of it can
    ///        bank as pass credit rather than Coinflip money; the `CrapsProtocolAwardSplit` log
    ///        riding the same finalization carries that liquid/pass breakdown. What the standing
    ///        DENIED is `candidate - paid`; it was never removed from the pool, so it needs no
    ///        funding log and no field of its own.
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
    ///         reserved on it was handed its pass credit back. Nobody else could have entered — a
    ///         dead day's doors were shut by the clock and the missing word the whole time — so
    ///         `seats` is the whole of what the day held, and each seat's own
    ///         `CrapsPassesCredited` precedes this.
    event CrapsDayLapsed(uint24 indexed day, uint64 seats);

    /// @notice Protocol money a winner's activity standing would not admit, banked in the
    ///         progressive rather than left unminted.
    /// @dev PROTOCOL MONEY ONLY. Bounties, principal, run losses, deleted bust remainders, the
    ///      ladder's own variance and rounding dust are none of them a standing forfeiture and
    ///      none of them arrive here.
    /// @param source `_ROLL_SRC_MAIN`, `_ROLL_SRC_HIGH_CONTESTED` or `_ROLL_SRC_HIGH_SOLE`.
    event CrapsProgressiveRolled(bytes32 indexed battleKey, uint8 indexed source, uint256 amount, uint256 balance);

    // ---------------------------------------------------------------------------------------
    // Deployment
    // ---------------------------------------------------------------------------------------

    /// @dev Register this contract's ENS reverse name (best-effort; skipped when the registrar is
    ///      unset — local/test/testnet builds). The `setName(string)` selector is shared by the L1
    ///      ReverseRegistrar and Base's L2ReverseRegistrar. Constructor code is init code, so this
    ///      costs nothing against the deployed contract's EIP-170 ceiling.
    constructor() {
        // THE DEPLOYMENT DAY IS A WARM-UP DAY WITH NO WINDOWS. Genesis is marked consumed and the
        // scheduled cursor born pointing at TOMORROW'S separator, so the first Craps windows open
        // on genesis + 1 and nothing can ever fall behind initialization: a pass awarded on
        // genesis reserves genesis + 1 normally, and the cursor is already standing there.
        // Derived from the clock rather than hard-coded, so deployment timing cannot move the
        // rule — and written from INIT code, which costs the runtime nothing.
        uint24 genesis = _currentDayIndex();
        unchecked {
            _bonus = uint256(genesis) + 1;
            _keeperSlot = uint64(_daySlotOf(uint256(genesis) + 1));
        }

        // TWENTY SEED DAYS EACH, banked to the two protocol bodies. The day lane seats both of
        // them every day and spends a banked pass before it burns anything, so this is twenty days
        // of protocol seats bought at deployment rather than out of the reserve — which is what
        // the opening days need, because the lootboxes that normally feed these two lanes have not
        // paid a pass yet. Banked rather than reserved: credit never expires, so it is spent one
        // day at a time by whichever days actually open. Written from INIT code, so the runtime
        // carries none of it.
        _credit(ContractAddresses.SDGNRS, false, _SEED_PASSES);
        _credit(ContractAddresses.VAULT, false, _SEED_PASSES);

        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok,) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "craps.degenerus.eth")
            );
            ok;
        }
    }

    // ---------------------------------------------------------------------------------------
    // Placing
    // ---------------------------------------------------------------------------------------

    /// @dev The one placement there is: a seat at a slot, on terms the slot already fixed.
    ///      Nothing here is caller-chosen but the chips, so nothing has to be vetted against a
    ///      caller's arithmetic — the terms were proven once, for the whole field, when the slot
    ///      was made. The whole bet is ONE word.
    /// @dev A battle entry is BINARY: one copy of the run, or exactly the field's high-roller
    ///      multiple. Nothing between is legal, and that is what makes a variable daily multiple
    ///      safe to quote — a transaction submitted naming ten cannot be silently filled at a
    ///      hundred, because a hundred-day rejects ten outright rather than reinterpreting it.
    ///      Zero and one-as-a-high-multiple both fall to the same floor.
    function _vetMultiple(uint256 highMult, uint256 multiple) internal pure returns (bool) {
        if (multiple == 1) return false;
        if (multiple < 2 || multiple != highMult) revert BadEntryMultiple();
        return true;
    }

    function _place(Window memory w, uint256 chips, uint256 multiple, uint256 standing)
        private
        returns (uint256 betId)
    {
        uint8 boonMask;
        bool high = _vetMultiple(w.highMult, multiple);
        // The bar this battle set, against the standing the caller actually holds. It is a term,
        // so it is in the key: two battles asking different bars are two races.
        // A CUSTOM battle's creator may still gate its own field; a bonus window asks nothing, so
        // its bar is zero and this never fires there. The protocol's own defence is on the PAYOUT
        // now, not the door — see `_SYBIL_SCORE_FLOOR`.
        if (standing < ((w.terms >> _TERM_SCORE_SHIFT) & _BET_MINSCORE_MASK)) revert ScoreRequiredForBonus();
        // One seat per address unless the battle was opened saying otherwise. A bonus window
        // never says otherwise: house money there buys a field of distinct players, not a field of
        // one player's entries.
        if (!w.multiEntry) {
            if (_bonusSeated[w.key][msg.sender]) revert AlreadyInBonus();
            // A day ticket is already sitting in every window of its day, so it bars a second seat
            // at any one of them — and so does a RESERVATION, which is a day ticket already paid
            // for. Any nonzero state is a claim on the whole day.
            if (
                w.bound < _CUSTOM_SLOT_BASE
                    && _daySeated[_daySlotOf(uint256(w.bound) / _BONUS_SLOTS_PER_DAY)][msg.sender] != 0
            ) revert AlreadyInBonus();
            _bonusSeated[w.key][msg.sender] = true;
        }
        unchecked {
            // A high roller buys the WHOLE seat over again — the bankroll it runs and the bounty
            // it posts — which is what makes the lane a race rather than a bigger bet in the same
            // one. Exactly one of those bounties stays in the main pot; the other `H - 1` are what
            // the high lane plays for. Bounded far below 2^256: a uint128 bankroll by 256 is 136
            // bits.
            boonMask = _burnForCraps(
                _tag((uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple, _CRAPS_FLAG_JOIN)
            );
            // The id IS the seat: this battle's slot, and this entrant's place in its field.
            betId = (uint256(w.bound) << 64) | _enterBattle(w.key, w.stakeUnits);
            // The sideboard is touched ONLY by a field that actually takes a high seat, so an
            // ordinary battle never pays for a lane it does not run.
            if (high) ++_highField[w.key];
        }
        // Settlement never writes this word. Before the slot closes, `amendSlip` may replace only
        // its chip slice; the owner, the frozen standing and the stakes flag remain fixed.
        _writeSlip(betId, msg.sender, chips, standing, high ? _BET_HIGH_BIT : 0, multiple - 1, boonMask);
    }

    /// @dev The one assembler of a stored bet word and its `CrapsSlipPlaced` echo — the window
    ///      door and the day lane both land here, so storage and the log cannot drift apart.
    function _writeSlip(
        uint256 betId,
        address player,
        uint256 chips,
        uint256 standing,
        uint256 highBits,
        uint256 evMult,
        uint256 boonMask
    ) private {
        uint256 boon = boonMask << _BET_BOON_SHIFT;
        _bets[betId] = uint256(uint160(player)) | (chips << _BET_CHIPS_SHIFT) | (standing << _BET_SCORE_SHIFT)
            | boon | highBits;
        emit CrapsSlipPlaced(
            player,
            chips | (betId << _EV_BET_SHIFT) | (evMult << _EV_MULT_SHIFT) | (standing << _BET_SCORE_SHIFT) | boon
        );
    }

    /// @dev The terms of any slot, window or custom alike — the one place a settler or a preview
    ///      reads what a field is playing. Read ONCE for a whole field rather than copied into
    ///      every header, which is what makes a bet a single word.
    function _slotWindow(uint256 slot) internal view returns (Window memory w) {
        if (slot >= _CUSTOM_SLOT_BASE) {
            (w,) = _customTerms(slot);
        } else {
            unchecked {
                // `_slotOf(day, period)` is `day * _BONUS_SLOTS_PER_DAY + period + 1`, so the
                // remainder names the period and zero is the reserved gap between days.
                uint256 p = slot % _BONUS_SLOTS_PER_DAY;
                if (p == 0) revert NoSuchBattle();
                w = _windowTerms(uint24(slot / _BONUS_SLOTS_PER_DAY), p - 1);
                w.entrants = uint32(_battles[w.key]);
            }
        }
    }

    /// @dev A ticket's ten leg counts, packed into the thirty-bit chip word, with their sum.
    ///      Each leg is a COUNT of chips, not an amount — the slot fixes what a chip is worth, so
    ///      an entrant chooses only where up to seven go. The sum is the board-wide ceiling; the
    ///      separate per-leg check keeps each count within the priced spread.
    ///
    ///      The one composition rule on top of that: PICK A SIDE. A ticket may not name both the
    ///      pass line and don't pass. Checked here rather than at each door, so every way in — a
    ///      window, a day ticket, a custom battle, an amendment — is held to it identically.
    ///      The DICE are not: a scatter chip may still land on the side a ticket did not pick,
    ///      which is the draw's doing and not a wager the player chose.
    function _packChips(uint32 c) internal pure returns (uint256 packed, uint256 count) {
        packed = c;
        // Bits 30-31 are outside the ten three-bit legs. Letting either through would overlap the
        // frozen standing field when `chips` is shifted into the stored bet word.
        if (packed > _BET_CHIPS_MASK) revert BadRandomCount();
        if (packed & 7 != 0 && (packed >> _CHIP_DONT_SHIFT) & _CHIP_DONT_MASK != 0) {
            revert BoardPlaysBothSides();
        }
        // Three is the ceiling, so bit 2 being set in any three-bit leg is the whole cap test.
        if ((packed >> 2) & _CHIP_LO_MASK != 0) revert TooManyChipsOnALeg();
        unchecked {
            for (uint256 i = 0; i <= _CHIP_DONT_SHIFT; i += 3) {
                count += (packed >> i) & 7;
            }
        }
    }

    /// @dev Packed counts back into the board they stand for, at this slot's chip.
    function _boardFrom(uint256 packed, uint256 chipFlip) internal pure returns (Craps.Bets memory b) {
        unchecked {
            b.passLine = uint24((packed & 7) * chipFlip);
            b.place4 = uint24(((packed >> 3) & 7) * chipFlip);
            b.place5 = uint24(((packed >> 6) & 7) * chipFlip);
            b.place6 = uint24(((packed >> 9) & 7) * chipFlip);
            b.place8 = uint24(((packed >> 12) & 7) * chipFlip);
            b.place9 = uint24(((packed >> 15) & 7) * chipFlip);
            b.place10 = uint24(((packed >> 18) & 7) * chipFlip);
            b.hard4 = uint24(((packed >> 21) & 7) * chipFlip);
            b.hard8 = uint24(((packed >> 24) & 7) * chipFlip);
            b.dontPass = uint24(((packed >> _CHIP_DONT_SHIFT) & _CHIP_DONT_MASK) * chipFlip);
        }
    }

    /// @notice Name or re-spread zero through seven chips on an open slip. Only the COMPOSITION moves: the
    ///         bankroll, target, bounty and seat are all the SLOT's, so no value moves and no
    ///         field changes. A blank ticket may name a pick this way, which is how the vault
    ///         steers the seats it takes automatically. Allowed until the slot closes, which is
    ///         the moment its table is bound — for a slip that came in through `enterBonusDay`,
    ///         only until the first window of that entry closes, and for a DAY ticket, its own
    ///         day's period zero: a reservation on a future day re-spreads freely until then.
    /// @param betId The slip: `(slot << 64) | seat`.
    /// @param chips Where up to seven chips go; the draw places the remainder of ten.
    /// @custom:reverts NotYourBet If the caller does not own the slip.
    /// @custom:reverts BetLocked If the slot has closed, or a day-wide entry's first window has.
    /// @custom:reverts BadRandomCount If the new board names more than seven chips.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    function amendSlip(uint256 betId, uint32 chips) public {
        uint256 header = _bets[betId];
        if (address(uint160(header)) != msg.sender) revert NotYourBet();
        uint256 slot = betId >> 64;
        // A slip re-spreads until its slot closes, which is the moment its table is chosen and so
        // the moment its word first becomes possible. A DAY ticket has no slot of its own to shut,
        // so it freezes when ITS day's first window stops taking bets — the same instant its own
        // door closes, and before any table it plays can be picked. Until then it is the
        // holder's to move: a FUTURE reservation amends freely, since nothing about a future day
        // is frozen yet — no word, no armed window, not even the field's head count — so there is
        // nothing an early re-spread could be tuned against.
        if (slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY == 0) {
            (uint24 nowDay, uint256 nowPeriod,) = _currentBonusSlot();
            uint256 liveDaySlot = _daySlotOf(nowDay);
            if (slot < liveDaySlot || (slot == liveDaySlot && nowPeriod != 0)) revert BetLocked();
        } else {
            // THE ENTRY CLOSE, not the arm — and through the very test every door that takes
            // money already uses, so the two can never drift apart. Closing on the arm instead
            // left a window between the moment a field stopped forming and the moment somebody
            // got round to shutting it, in which the last amender could re-tune a board against a
            // field that was already public and frozen. Nobody who entered on time had that move.
            _joinableSlot(slot);
        }
        // ZERO THROUGH SEVEN CHIPS, the same range every entry door takes. The stored count fixes
        // both how many of the ten the dice scatter and, on scheduled windows alone, which
        // shooter-profit row the slip receives. There is no separate mode bit to update.
        uint256 packed = _upToSeven(chips);

        // THE STANDING MOVES WITH THE BOARD. A seat may now be written days before its day opens,
        // so the standing frozen at that moment is the holder's oldest rather than their current
        // one — and an amendment is the one door open to them in between. Re-read here, so a slip
        // carries what its owner held the last time they touched it.
        uint256 standing = _standingOf(msg.sender);
        _bets[betId] = (header & ~((_BET_CHIPS_MASK << _BET_CHIPS_SHIFT) | (_BET_SCORE_MASK << _BET_SCORE_SHIFT)))
            | (packed << _BET_CHIPS_SHIFT) | (standing << _BET_SCORE_SHIFT);

        emit CrapsSlipAmended(betId, packed);
    }

    /// @dev One ticket, every window of the day. Nothing per-window is written here: the field
    ///      each window plays is folded in when that window shuts, which is safe precisely because
    ///      this door closes before any window can.
    ///
    ///      SHARED BY BOTH DOORS. `reserved` is zero for an ordinary paid entry and the holder's
    ///      reservation bit when a commitment is being redeemed, and the two differ in exactly
    ///      three places: which day state is required, where the multiple comes from, and whether
    ///      anything is burned. Everything else — the board, the seven-window open check, the bar,
    ///      the frozen standing, the ticket counts, the slip event and the quest streak — is the
    ///      same code, so a redeemed seat cannot drift from a bought one.
    function _enterDayLane(uint24 today, uint256 word, uint32 chips, uint256 multiple) private returns (uint256) {
        // ONE lane for the whole day, so one multiple: the draw is the day's, and every window
        // the ticket sits in runs it.
        bool high = _vetMultiple(_highMultOf(word), multiple);
        uint256 daySlot = _daySlotOf(today);
        // A day already claimed — seated here, or seated in advance by a pass — is not for sale
        // twice. A prepaid day needs no door of its own: the seat was written when the pass was
        // spent, so there is nothing left to redeem.
        if (_daySeated[daySlot][msg.sender] != 0) revert AlreadyInBonus();
        uint256 packed = _upToSeven(chips);

        uint256 cost;
        uint256 bar;
        unchecked {
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                Window memory w = _windowTermsOn(today, p, word);
                // The day has to be OPEN: its windows are what the ticket plays.
                if (_battles[w.key] == 0) revert BonusPeriodSpent();
                // And the buyer must not already hold a seat in any of them. `_place` bars a day
                // ticket from taking a second seat at a window; without the mirror of that test
                // here, taking the windows one at a time and THEN the day would seat one address
                // twice in every window of its own day.
                if (_bonusSeated[w.key][msg.sender]) revert AlreadyInBonus();
                cost += (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * multiple;
                uint256 b = (w.terms >> _TERM_SCORE_SHIFT) & _BET_MINSCORE_MASK;
                if (b > bar) bar = b;
            }
        }
        // Held to the HIGHEST bar of the seven, since the ticket sits in all of them.
        uint256 standing = IGameActivityScore(_GAME).playerActivityScore(msg.sender);
        if (standing < bar) revert ScoreRequiredForBonus();
        if (standing > _BET_SCORE_MASK) standing = _BET_SCORE_MASK;

        // ONE tagged burn buys the whole day: the join, the day pass and the day-kept streak all
        // ride the same report, so the table no longer calls the quest ledger itself.
        uint8 boonMask = _burnForCraps(
            _tag(cost, _CRAPS_FLAG_JOIN | _CRAPS_FLAG_PASS | (high ? _CRAPS_FLAG_HIGH : _CRAPS_FLAG_NORMAL))
        );
        _writeDaySeat(daySlot, msg.sender, packed, standing, high, multiple - 1, boonMask);
        return _BONUS_PERIODS_PER_DAY;
    }

    /// @dev THE ONE WRITER of a day-lane seat — the paid door, a reservation and a protocol body
    ///      all land here, so a seat cannot drift by how it was funded. It writes the three
    ///      things a day ticket is: its slice of the ticket counters (a HIGH ticket bumps every
    ///      period's high count — the whole day is high), the bet word (a high ticket carries all
    ///      seven period flags), and the holder's SEAT NUMBER in `_daySeated`, which is what lets
    ///      a later per-window upgrade name the ticket without a walk.
    function _writeDaySeat(
        uint256 daySlot,
        address player,
        uint256 chips,
        uint256 standing,
        bool high,
        uint256 evMult,
        uint256 boonMask
    ) private {
        unchecked {
            uint256 t = _dayTickets[daySlot] + 1 + (high ? _DT_ALL_HIGH : 0);
            _dayTickets[daySlot] = t;
            uint256 seat = t & _MASK32;
            _daySeated[daySlot][player] = seat;
            _writeSlip(
                (daySlot << 64) | seat, player, chips, standing, high ? _BET_DAYHIGH_MASK : 0, evMult, boonMask
            );
        }
    }

    /// @dev Count an entrant into its battle. The first one carries the stake echo in with it;
    ///      after that the word is a bare increment.
    /// @return n This entrant's index within its own field, 1-based — the low half of its bet id.
    function _enterBattle(bytes32 key, uint256 stakeUnits) private returns (uint256 n) {
        uint256 g = _battles[key];
        unchecked {
            g = g == 0 ? 1 | (stakeUnits << _BG_STAKE_SHIFT) : g + 1;
            n = g & _MASK32;
        }
        _battles[key] = g;
    }

    // ---------------------------------------------------------------------------------------
    // Settling
    // ---------------------------------------------------------------------------------------

    /// @notice Settle a slot's entrants — bonus window or custom battle alike — in id order,
    ///         from wherever its cursor stands.
    /// @dev THE settle lane, and the only one there is. A slot's readiness is uniform — every
    ///      member shut onto the same table — so the arm and the word are proven ONCE here and
    ///      every member the walk then examines settles. The cursor advances to the last id
    ///      actually RESOLVED, and `id <= cursor` is sound because the walk starts AT the cursor,
    ///      so the settled set is contiguous by construction. A lane that could start anywhere
    ///      would break that.
    ///
    ///      ⚠ THE SECOND ARGUMENT IS A WORK BUDGET IN WALK UNITS, NOT A SEAT COUNT. That is a
    ///      deliberate public change with an unchanged selector: both arguments are still
    ///      `uint64`, so an integration that keeps passing a head count will settle far fewer
    ///      seats than it intended rather than reverting. The reason is that a seat's cost is not
    ///      a constant — a three-roll bust and a four-hundred-roll one differ by two orders of
    ///      magnitude, and whether a run PAYS decides whether it adds a deferred credit — so each
    ///      settled seat charges its own OUTCOME (`_SEAT_UNITS`) and a bust-heavy table walks
    ///      many more seats per call than a correlated hot one, which is exactly the behaviour a
    ///      fixed count cannot express. The charge is deterministic, so the same chain state
    ///      stops the same batch at the same seat on every node.
    ///
    ///      Zero settles nothing. Any nonzero budget completes at least one seat, because the
    ///      charge is levied AFTER a seat rather than before: a run cannot be stopped halfway
    ///      without storing a resumable engine state that costs more than the overshoot it would
    ///      save. A caller repeats the call to walk a deeper field.
    /// @param slot A window's `day * _BONUS_SLOTS_PER_DAY + period + 1`, or a custom battle's.
    /// @param budgetUnits HOW MUCH WORK to do, in the protocol's walk units — not how many seats.
    ///        Each settled seat charges its own outcome (see `_SEAT_UNITS`), and the walk stops
    ///        after the first seat whose charge meets or crosses the budget. Zero settles
    ///        nothing; any nonzero budget completes at least one seat.
    /// @custom:reverts RngNotReady If the slot has not shut, or its table has no word yet.
    function resolveSlot(uint64 slot, uint64 budgetUnits) public {
        if (budgetUnits == 0) return;
        // Unarmed reads as zero: the slot has not shut, so no table has been chosen yet.
        uint48 index = _slotIndex[slot];
        if (index == 0) revert RngNotReady();
        unchecked {
            index -= 1;
        }
        uint256 word = _wordAt(index);
        if (word == 0) revert RngNotReady();
        // The whole field plays these. Read once here rather than out of every header — which is
        // what lets a bet be a single word.
        Window memory w = _slotWindow(slot);

        unchecked {
            // The field IS 1..entrants. There is no id space to scan and nothing to skip: every
            // read below is a member of this battle.
            uint64 end0 = uint64((_battles[w.key] & _MASK32) + 1);
            uint64 end = end0;
            uint64 from = _bonusCursor[slot] + 1;
            // THE ABSOLUTE CEILING, and it is not the budget's job. It bounds the two credit
            // arrays and the loop counter whatever the caller asked for, so one call can never be
            // made to allocate unboundedly; the BUDGET is what stops a production crank.
            if (from + _RESOLVE_MAX_SEATS < end) end = from + _RESOLVE_MAX_SEATS;
            if (end <= from) return;
            // The field is the window's OWN seats followed by the day's, as one dense 1..entrants
            // range — so a single cursor still covers both and nothing here has to skip or scan.
            // Only where a seat's word LIVES differs.
            (uint256 dayBase, uint64 dayN) = _dayField(slot);
            (uint256 put, uint256 hi) = _settleBatch(slot, from, end, (end0 - 1) - dayN, dayBase, w, word, budgetUnits);
            // Booked to the day the field PLAYED, not the day someone got round to settling it.
            // Settlement is permissionless and unbounded in time, so keying the books to `now`
            // would let a holder of unsettled slots choose which day's boost budget their action
            // inflates.
            //
            // A CUSTOM BATTLE IS NOT BOOKED AT ALL — not to its close day, not to its settlement
            // day, not to a day of its own. Its bankroll is its creator's terms and its entrants'
            // burn, and the day books are what SIZE the protocol's own subsidy: letting a table
            // anyone can open at any depth feed that denominator would let custom volume mint
            // scheduled emission. So the two products share the engine and share nothing else.
            //
            // `done` is the last seat ACTUALLY resolved, never the end the batch was offered:
            // the cursor, the action and the credit arrays all key off the same figure, so a
            // budget that stops early can never book work it did not do or skip work it did.
            if (slot < _CUSTOM_SLOT_BASE) _bookDay(uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY), put, hi);
        }
    }

    /// @dev The walk itself, on a frame of its own. Split out of `resolveSlot` for STACK, not for
    ///      structure: the loop carries the two credit arrays, their cursor, the batch bounds, the
    ///      two id bases and the running action, and via-IR runs out of slots with the readiness
    ///      checks and the decoded window still live above it. The same split the session loops in
    ///      `Craps` use, for the same reason.
    /// @return staked The bankroll this batch's seats put up — the action a later day's bonus
    ///         budget is drawn against.
    /// @return high The high-lane part of that action.
    /// @dev The walk writes the slot's cursor ITSELF, to the last seat actually resolved — the
    ///      budget makes that necessary: the offered `end` is a ceiling rather than a plan, and
    ///      booking the offer instead of the outcome would strand every seat the charge stopped
    ///      short of.
    function _settleBatch(
        uint64 slot,
        uint64 from,
        uint64 end,
        uint64 ownN,
        uint256 dayBase,
        Window memory w,
        uint256 word,
        uint256 budgetUnits
    ) private returns (uint256 staked, uint256 high) {
        unchecked {
            // One batched credit for the whole walk. `creditFlipBatch` skips nothing we have to
            // pre-filter, but a busted run pays zero and a zero word still costs calldata, so the
            // arrays are packed and then trimmed to what actually pays.
            address[] memory players = new address[](end - from);
            uint256[] memory amounts = new uint256[](end - from);
            uint256 k;
            uint256 freePtr;
            assembly ("memory-safe") {
                freePtr := mload(0x40)
            }
            for (uint64 n = from; n < end; ++n) {
                // Every allocation made while resolving the previous seat is dead now. Reuse that
                // memory instead of expanding it once per entrant; the credit arrays and `w` were
                // allocated below this saved pointer and remain intact.
                assembly ("memory-safe") {
                    mstore(0x40, freePtr)
                }
                uint256 id = n <= ownN ? (uint256(slot) << 64) | n : dayBase | (n - ownN);
                (address player, uint256 paid, uint256 put, uint256 hi, uint256 cost) =
                    _resolve(id, n, _bets[id], w, word);
                staked += put;
                high += hi;
                if (paid != 0) {
                    players[k] = player;
                    amounts[k] = paid;
                    ++k;
                }
                _bonusCursor[slot] = n;
                // THE CHARGE IS THE SEAT'S OWN OUTCOME — its rolls and whether it pays — so a
                // bust-heavy field walks many more seats than a paying one on the same budget,
                // and the stopping point is a pure function of chain state: no gas meter, no
                // schedule dependence, the same batch boundary on every node.
                //
                // CHECKED AFTER THE SEAT, because a run cannot be half-settled without storing a
                // resumable engine state, and that state costs more than the overshoot. So one
                // complete seat may cross the budget; the hard bound is what covers it.
                if (cost >= budgetUnits) break;
                budgetUnits -= cost;
            }

            if (k != 0) {
                assembly ("memory-safe") {
                    mstore(players, k)
                    mstore(amounts, k)
                }
                ICoinflipStake(ContractAddresses.COINFLIP).creditFlipBatch(players, amounts);
            }
        }
    }

    /// @notice One step of the scheduled keeper: find the oldest scheduled slot still owing work
    ///         and do the next piece of it, whatever that piece is — cross a spent slot, sweep a
    ///         lapsed day's reservations back to credits, shut a window whose close has passed,
    ///         or settle a batch of an armed field within `budgetUnits`.
    /// @dev PERMISSIONLESS, and the ONE source of scheduled liveness. The old keeper looked only
    ///      at the most recently closed window, so a field that outlasted one budget — or whose
    ///      word came late, the daily event above all — fell behind the rewarded crank forever.
    ///      This cursor cannot pass a slot that still owes anything, so nothing scheduled is ever
    ///      forgotten; external help (a direct arm, a direct settle) is detected as done work and
    ///      crossed, never wedged on.
    ///
    ///      WHAT IT WILL NOT DO is wait for the impossible. It stops — reporting no progress and
    ///      earning no bounty — on a window still taking bets, an armed field whose word has not
    ///      landed, a day the advance has not opened yet, and a settle it lacks budget for. All
    ///      four resolve themselves; polling them pays nobody.
    /// @param budgetUnits The work allowance in walk units, exactly as `resolveSlot` takes it.
    ///        Zero still does the cheap lifecycle work — crossing spent slots and shutting a
    ///        closed window — since the arm is the time-critical piece and costs no settlement.
    /// @return progressed Whether ANY state moved: the cursor, a sweep, an arm, or settled seats.
    ///         The keeper's bounty gate, so a poll can never be farmed.
    /// @return slot Where the cursor stands after the call.
    function keepScheduled(uint64 budgetUnits) external returns (bool progressed, uint64 slot) {
        // Never zero: the constructor births the cursor at genesis + 1's separator.
        uint64 cur = _keeperSlot;
        uint24 today = _currentDayIndex();
        (,, uint256 open) = _currentBonusSlot();
        uint24 cachedDay = type(uint24).max;
        uint256 cachedWord;
        unchecked {
            for (uint256 hops = 0; hops < _KEEP_MAX_HOPS; ++hops) {
                uint24 day = uint24(uint256(cur) / _BONUS_SLOTS_PER_DAY);
                if (cur % _BONUS_SLOTS_PER_DAY == 0) {
                    // THE SEPARATOR. An opened day is crossed into its windows; today and the
                    // future wait for the advance to open them; a day the advance never opened is
                    // LAPSED — nobody could have entered it, so all it holds is reservations, and
                    // they are swept back to pass credits before the WHOLE day is stepped over.
                    if (_boostBudget[day] != 0) {
                        ++cur;
                        continue;
                    }
                    if (day >= today) break;
                    // The sweep is this call's ONE expensive action, complete or not. A PARTIAL
                    // one must still report its refunds as progress — the rewarded crank reverts
                    // a no-progress call as NoWork, and a revert would undo the very credits the
                    // sweep just committed. The day's own sweep cursor moving is that report;
                    // crossing the finished day moves the keeper cursor and reports itself.
                    (bool doneAll, bool moved) = _sweepLapsedDay(cur, day, budgetUnits);
                    if (doneAll) cur += uint64(_BONUS_SLOTS_PER_DAY);
                    else if (moved) progressed = true;
                    break;
                }
                // Cheap hops commonly cross several spent windows from one day. They all derive
                // from the same daily word, so fetch it once until the cursor reaches another day.
                if (cachedDay != day) {
                    cachedDay = day;
                    cachedWord = _dailyWordAt(day);
                }
                if (cachedWord == 0) revert RngNotReady();
                Window memory w =
                    _windowTermsOn(day, (uint256(cur) % _BONUS_SLOTS_PER_DAY) - 1, cachedWord);
                uint256 g = _battles[w.key];
                uint48 idx = _slotIndex[cur];
                if (idx == 0) {
                    if (cur >= open) break;
                    // The battle exists by construction: the cursor only enters a day's windows
                    // through a separator that proved the day opened, and an opened day writes
                    // all seven.
                    _armSlot(cur, w);
                    progressed = true;
                    break;
                }
                uint256 entrants = g & _MASK32;
                // Finalized — or armed with nobody in it, which is a race with no runners and
                // nothing owed. Either way the slot is spent.
                if (entrants == 0 || ((g >> _BG_RESOLVED_SHIFT) & _MASK32) == entrants) {
                    ++cur;
                    continue;
                }
                if (_wordAt(idx - 1) == 0) break;
                if (budgetUnits == 0) break;
                resolveSlot(cur, budgetUnits);
                progressed = true;
                g = _battles[w.key];
                if (((g >> _BG_RESOLVED_SHIFT) & _MASK32) == (g & _MASK32)) ++cur;
                break;
            }
            if (cur != _keeperSlot) {
                _keeperSlot = cur;
                progressed = true;
            }
        }
        slot = cur;
    }

    /// @dev Hand every seat reserved on a lapsed day its pass credit back, metered against the
    ///      caller's budget and resumable mid-walk: the day's OWN `_bonusCursor` entry is the
    ///      refund cursor, free because a remainder-zero slot is never a battle and never settles.
    ///      Restitution is IN KIND — a reservation was a claim on one future day seat, and a pass
    ///      credit is exactly that claim again.
    /// @return doneAll The whole day refunded — the separator, and its seven never-opened
    ///         windows with it, are now crossable.
    /// @return moved Whether this call refunded anybody — real, one-time progress even when the
    ///         day is not yet done.
    function _sweepLapsedDay(uint64 daySlot_, uint24 day, uint64 budgetUnits)
        private
        returns (bool doneAll, bool moved)
    {
        unchecked {
            uint64 n = uint32(_dayTickets[daySlot_]);
            uint64 done = _bonusCursor[daySlot_];
            uint256 base = uint256(daySlot_) << 64;
            while (done < n) {
                if (budgetUnits < _SWEEP_SEAT_UNITS) return (false, moved);
                budgetUnits -= uint64(_SWEEP_SEAT_UNITS);
                ++done;
                moved = true;
                uint256 header = _bets[base | done];
                _credit(address(uint160(header)), header & _BET_HIGH_BIT != 0, 1);
                _bonusCursor[daySlot_] = done;
            }
            emit CrapsDayLapsed(day, n);
            doneAll = true;
        }
    }

    /// @notice GAME-only: bank a rolled pass award as credits and nothing else — no reservation
    ///         attempt, no external call, no way to revert past the saturation the credit lane
    ///         already announces. The lootbox module's LAST resort when the full delivery lane
    ///         fails: a pass the table has banked is a pass nobody can lose.
    /// @dev REVERT-FREE for the authorized caller, and that is load-bearing: the jackpot's comp
    ///      lane calls this bare from inside the daily advance, so a new revert path here is an
    ///      advance-liveness regression, not a local style choice.
    /// @return normalCredited What the normal lane actually banked after saturation — a caller
    ///         pricing value off it never charges for a credit the ceiling refused. Only the
    ///         normal lane reports: the one pricing caller sends normals alone, and the high
    ///         lane's `CrapsPassesCredited` log already carries its actual count.
    function creditPasses(address player, uint32 normal, uint32 high)
        external
        returns (uint32 normalCredited)
    {
        if (msg.sender != _GAME) revert OnlyGame();
        // `_credit` returns at most `_PASS_MAX`, so the cast is exact.
        if (normal != 0) normalCredited = uint32(_credit(player, false, normal));
        if (high != 0) _credit(player, true, high);
    }

    /// @notice The Craps progressive's live balance, in FLIP wei — one pool, shared by all nine
    ///         scheduled formats.
    /// @dev The SECOND reader production keeps, and for the same kind of reason as the first: it
    ///      is the one figure of the whole system that is not a pure function of published inputs.
    ///      Reconstructing it means replaying every day's funding and every finalized field's
    ///      standing rollover and award from genesis, so a client that only wants to show what is
    ///      on the table would otherwise have to index the entire history to do it.
    function progressivePool() external view returns (uint256) {
        return _progressive;
    }

    /// @dev Whether a bet has settled. No slip carries a settled bit — its slot's cursor marks the
    ///      whole field at once, and an id's low half is its place in that field.
    function _settledOf(uint256 betId) internal view returns (bool) {
        return uint64(betId) <= _bonusCursor[betId >> 64];
    }

    /// @dev Who may open a battle. The roll is checked FIRST so a granted creator never pays for
    ///      the cross-contract call; the vault's majority holder always qualifies, so the
    ///      authority behind the grant can never be locked out of its own table.
    function _mayOpenBattle() private view returns (bool) {
        return _battleCreator[msg.sender] || IVaultOwnership(ContractAddresses.VAULT).isVaultOwner(msg.sender);
    }

    /// @notice Open a custom battle: a race on terms of your own, on its own slot, settling on a
    ///         table nobody can know until it shuts. The whole definition is vetted ONCE, here,
    ///         for the whole field — an entrant restates nothing and so can key nothing else.
    /// @param played    The round a slip puts down, in whole FLIP. A whole ten chips.
    /// @param bankMult  How many of those rounds deep the bankroll runs.
    /// @param goalMult  The target, as a multiple of that bankroll.
    /// @param stakeUnits The bounty each entrant posts, in `_BATTLE_STAKE_UNIT` granules.
    /// @param minScore  The standing bar this battle asks of its entrants.
    /// @param closeTime When entry shuts. From then, anyone may `closeBattle` it.
    /// @return slot The battle's slot — what an entrant joins and a settler resolves.
    function createBattle(
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint16 minScore,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) external returns (uint64 slot) {
        if (!_mayOpenBattle()) revert NotBattleCreator();
        // THE WHOLE DEFINITION, vetted in one pass. A round is ten whole chips or it is not a
        // round; the bankroll runs a bounded number of them; the goal sits in its band; the bounty
        // fits the scoreboard's granule field; the standing bar and close time are sane; and a high
        // lane is either absent or a real multiple — zero runs no lane, while one is the ordinary
        // seat under another name and would make the two entry modes indistinguishable.
        if (
            played == 0 || played % _BONUS_CHIPS != 0 || played > _MAX_ROUND_FLIP
                || bankMult == 0 || bankMult > _MAX_BANKROLL_MULT
                || goalMult < _MIN_BATTLE_GOAL_MULT || goalMult > _MAX_GOAL_MULT
                || stakeUnits > _BSTAKE_MAX
                || minScore > _MAX_MIN_SCORE
                || closeTime <= block.timestamp
                || highRollerMult == 1 || highRollerMult > _MAX_HIGH_MULT
        ) revert BadBattleTerms();
        unchecked {
            uint256 bankroll = uint256(played) * bankMult;
            // The table's entry floor, and the bounty ceiling: a bounty rides alongside the
            // bankroll and may never exceed it. Zero is legal and leaves an empty pot to race for.
            if (
                bankroll < _MIN_BANKROLL_FLIP
                    || uint256(stakeUnits) * (_BATTLE_STAKE_UNIT / 1 ether) > bankroll
            ) revert BadBattleTerms();
            slot = uint64(_CUSTOM_SLOT_BASE + ++_customBattleCount);
            uint256 terms = uint256(played) | (uint256(bankMult) << _CB_BANK_SHIFT)
                | (uint256(goalMult) << _CB_GOAL_SHIFT) | (uint256(stakeUnits) << _CB_STAKE_SHIFT)
                | (uint256(minScore) << _CB_SCORE_SHIFT) | (uint256(closeTime) << _CB_CLOSE_SHIFT)
                | (multiEntry ? _CB_MULTI_BIT : 0) | (uint256(highRollerMult) << _CB_HIGH_SHIFT);
            _customBattle[slot] = terms;
            emit CrapsBattleCreated(slot, msg.sender, terms);
        }
    }

    /// @notice Join a custom battle, placing zero through seven chips and leaving the rest of the
    ///         ten-chip round to the dice. Custom tickets receive no shooter-profit boost.
    /// @custom:reverts BoardPlaysBothSides If the ticket names both the pass line and don't pass.
    function enterBattle(uint64 slot, uint32 chips, uint16 multiple) public returns (uint256 betId) {
        return _enterWindow(_joinableSlot(slot), chips, multiple);
    }

    /// @notice Shut a custom battle and take the table it will settle on. Permissionless once its
    ///         close time has passed.
    /// @dev The same shape as a window's arm, for the same reason: the index is chosen NOW, so
    ///      nobody could know it while joining. Custom slots carry no in-order rule — a window
    ///      lane needs slot order to BE table order so a settler can walk a day in sequence, but
    ///      a custom battle is resolved through its own slot alone.
    function closeBattle(uint64 slot) external returns (uint48 index) {
        (Window memory w, uint256 c) = _customTerms(slot);
        unchecked {
            if (block.timestamp < ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusStillRunning();
        }
        if (_slotIndex[slot] != 0) revert BonusPeriodSpent();
        // A battle nobody joined is not shut, it never happened — and binding it would strand a
        // table index on nothing.
        if (_battles[w.key] == 0) revert BonusPeriodSpent();
        index = _armSlot(slot, w);
    }

    /// @dev Decode a custom battle into the same `Window` representation used by bonus slots, so
    ///      entry, settlement and payment share one path.
    function _customTerms(uint256 slot) private view returns (Window memory w, uint256 c) {
        c = _customBattle[slot];
        if (c == 0) revert NoSuchBattle();
        unchecked {
            w.played = (c & _CB_PLAYED_MASK) * 1 ether;
            w.bankroll = uint128(w.played * ((c >> _CB_BANK_SHIFT) & _CB_BANK_MASK));
            w.goal = uint128(uint256(w.bankroll) * ((c >> _CB_GOAL_SHIFT) & _CB_GOAL_MASK));
            // The maximum a player may place directly: seven of the ten chips.
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.stakeUnits = (c >> _CB_STAKE_SHIFT) & _BSTAKE_MAX;
            // Fixed at creation, and no day's draw can move it: a custom battle's high lane is a
            // term its creator named, not a thing the protocol rolls.
            w.highMult = (c >> _CB_HIGH_SHIFT) & _CB_HIGH_MASK;
            w.terms = w.stakeUnits | (((c >> _CB_SCORE_SHIFT) & _BET_MINSCORE_MASK) << _TERM_SCORE_SHIFT)
                | (w.highMult << _TERM_HIGH_SHIFT);
            // Fixed at creation and never revisited: how much has been seeded onto a battle has
            // nothing to do with how many seats one address may take.
            w.multiEntry = c & _CB_MULTI_BIT != 0;
            w.bound = uint48(slot);
        }
        w.key = _battleKey(w.bound, w.bankroll, w.goal, w.played, w.terms);
    }

    /// @notice The custom battle at `slot`: its match key, the table it shut onto (zero until it
    ///         does), and its packed definition. `terms` is handed back whole rather than spread
    ///         into eight returns — the layout is fixed by `CrapsBattleCreated` and a client
    ///         decodes it for nothing, where eight returns cost real code on a table with none
    ///         to spare.
    function _customBattleOf(uint64 slot) internal view returns (bytes32 battleKey, uint48 index, uint256 terms) {
        (Window memory w, uint256 c) = _customTerms(slot);
        uint48 stored = _slotIndex[slot];
        unchecked {
            if (stored != 0) index = stored - 1;
        }
        return (w.key, index, c);
    }

    /// @notice Grant or revoke the right to open a custom battle. The vault's majority holder is
    ///         the only caller — and always holds the right itself — and this roll is the only
    ///         thing it confers: a creator has no say over settlement, arming or anyone else's
    ///         money, and every battle they open is joinable by anyone clearing its terms.
    /// @dev Held as a mapping rather than resolved through the vault on each placement so a
    ///      granted creator pays one warm SLOAD instead of a cross-contract call.
    /// @notice Name the board the vault's automatic day seats play from here on.
    /// @dev The vault is seated at every bonus day by `openBonusDay` — a call nobody makes on its
    ///      behalf and which takes no arguments — so without this its ticket is always blank and
    ///      the dice place all ten of its chips. This is the vault's only say in what it plays,
    ///      short of amending each seat by hand after the fact.
    ///
    ///      ZERO THROUGH SEVEN CHIPS, the same rule every paid door enforces, so the vault can
    ///      never hold a shape a player could not. A zero board restores the full draw.
    ///
    ///      Read at seat time, never copied forward: changing it moves every day the vault has not
    ///      yet been seated at, and no day it already has. A seat already taken is moved with
    ///      `amendSlip` instead, which is open until its slot stops taking bets.
    ///      Taken PACKED rather than as a `Craps.Bets`: the ten-field struct costs several hundred
    ///      bytes to decode at a new entry point, and this contract has none to spare. It is the
    ///      same thirty-bit layout `CrapsSlipPlaced` already carries, which every client decodes
    ///      already — three bits a leg, in board order, don't pass last.
    ///
    ///      `_VAULT_BOARD_OFF` is the one value that is not a board at all: it takes the vault OUT
    ///      of the automatic day lane, so it buys no seat, burns no FLIP and spends no banked pass
    ///      until its owner names a board again. It does NOT reach a seat a pass already bought —
    ///      that day was paid for when the pass was spent, and there is nothing left to decline.
    /// @param packed Up to seven chips in the packed layout, zero to go back to the draw, or
    ///        `VAULT_BOARD_OFF` to stop taking day seats at all.
    /// @custom:reverts NotVaultOwner If the caller does not hold the vault's DGVE majority.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    /// @custom:reverts BadRandomCount If it names more than seven chips.
    function setVaultBoard(uint32 packed) external {
        if (!IVaultOwnership(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        if (packed != 0 && packed != _VAULT_BOARD_OFF) {
            (, uint256 count) = _packChips(packed);
            if (count > _MAX_PICKED_CHIPS) revert BadRandomCount();
        }
        // No echo of its own: the board is read back at each seat, and every seat it steers
        // still announces the chips it actually plays through `CrapsSlipPlaced`.
        _vaultBoard = packed;
    }

    function setBattleCreator(address account, bool allowed) external {
        if (!IVaultOwnership(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        _battleCreator[account] = allowed;
        emit BattleCreatorSet(account, allowed);
    }

    /// @dev Whether `header` takes the high lane in the window at `windowSlot`. A window-local or
    ///      custom slip stores ONE flag at bit 217. A DAY ticket — the one case where the bet's
    ///      own slot differs from the window settling it — stores seven, and the window's period
    ///      picks its own: bit `217 + p`, where `p + 1` is the slot's remainder.
    function _highOn(uint256 header, uint256 betId, uint256 windowSlot) private pure returns (bool) {
        uint256 bit = _BET_HIGH_BIT;
        unchecked {
            if ((betId >> 64) != windowSlot) bit <<= (windowSlot % _BONUS_SLOTS_PER_DAY) - 1;
        }
        return header & bit != 0;
    }

    /// @dev Settle one loaded bet. The slot's terms and word are supplied by `resolveSlot`, which
    ///      reads each once for the whole batch.
    /// @dev The last return is the seat's WORK CHARGE in walk units — plumbing, dice and the
    ///      deferred credit a paying run adds — computed here, where the roll count is in hand.
    function _resolve(uint256 betId, uint64 seat, uint256 header, Window memory w, uint256 word)
        private
        returns (address player, uint256 paid, uint256 staked, uint256 high, uint256 cost)
    {
        // The combined ordinal is the rotation's seat: a day ticket's own id names its day-local
        // seat, not where it sits in this window's field.
        w.seat = seat;
        Settlement memory s = _settlementOf(betId, header, w, word);
        // High for THIS window: a day ticket may be high in some of its seven and ordinary in the
        // rest, and the window being settled names which flag applies.
        bool hi = _highOn(header, betId, uint256(w.bound));

        // NOTHING is written back to the bet. The verdict folds into the battle's own word as a
        // single composite score, and the scoreboard remembers which bet is holding the lead — so
        // a settlement touches one shared word rather than one word per entrant, and the slot's
        // cursor is the only mark a slip needs.
        //
        // EVERY field ranks, bounty or none. A friendly battle is an ordinary battle whose pot
        // happens to be empty: it gathers, ranks, finalizes and names a winner exactly the same
        // way, and the only thing that falls out at the end is the payment.
        uint256 sc;
        unchecked {
            sc = _compositeOf(s) | ((header >> _BET_SCORE_SHIFT) & _BET_SCORE_MASK);
        }
        // THE LANE FOLDS FIRST, and the ordering is load-bearing: scoring the main board is what
        // finalizes the field, and finalization is what PAYS — so the last high seat has to be in
        // the sideboard before the main board can go looking for a lane winner.
        uint256 ride;
        if (hi) {
            uint256 extra;
            (ride, extra) = _foldHigh(w, sc, seat, word, header, s.paid);
            unchecked {
                staked = uint256(w.bankroll) * w.highMult + extra;
                high = staked;
            }
        }
        _scoreBattle(w, sc, seat, word);

        // ONLY NOW does the multiple apply. The composite above folded the UNSCALED return on
        // purpose: a seat buys copies of a run, never a better one, so 256 times the bankroll must
        // not also buy 256 times the tiebreak in the bounty battle. Rounding has already landed on
        // the single-copy figure, so N copies pay exactly N times one copy.
        // ENTRY IS BINARY, so the scale is the high flag and nothing else: `_vetMultiple` admits
        // only one copy of the run or exactly the day's `highMult`. Reading it off the flag rather
        // than out of the header is what lets a seat be written before its day has drawn a word.
        uint256 scale = hi ? w.highMult : 1;

        // The award is handed BACK rather than paid here: a field settles into one batched
        // credit at the end of the walk, not one cross-contract call per entrant.
        player = address(uint160(header));
        unchecked {
            // A sole rider's return rides home with the run. What this seat PUT UP is the bankroll
            // it ran; the bounty is deliberately not action, since it is posted by a seat and
            // handed to a winner and so nets to zero across the field.
            // The boon lands HERE and only here: after `_foldHigh` has already run on the
            // unscaled figure and after `_scoreBattle` has closed the field, so it cannot reach
            // the rider, the lane, the ranking, the pots or `staked` — and `won` below stays the
            // unboosted scaled result. It moves `paid`, and nothing else.
            uint256 basePaid = s.paid * scale;
            // THE BOON RIDES EVERY WINDOW THE TICKET PLAYS. It was bought with the burn, and a
            // DAY ticket's burn paid for all seven — so a boon spent on a day purchase lifts all
            // seven bankroll payments rather than one of them. Settlement order cannot reach it:
            // the lift is a function of the run and the mask, so every window's answer is fixed
            // before any of them is cranked.
            paid = basePaid + ride + _boonBonus((header >> _BET_BOON_SHIFT) & _BET_BOON_MASK, basePaid);
            if (staked == 0) staked = uint256(w.bankroll) * scale;

            // A contested lane pays one winner when the field closes; its individual high seats
            // have no rider payment to announce. A one-seat lane really does ride this run, and
            // still emits zero when the run busts because that zero is its final disposition.
            if (hi && uint32(_highField[w.key]) == 1) {
                emit CrapsHighRollerPaid(betId, w.key, player, ride, true);
            }
            cost = _SEAT_UNITS + s.totalRolls / _ROLLS_PER_UNIT + (paid != 0 ? _CREDIT_UNITS : 0);
        }
        emit CrapsBetSettled(betId, player, s.won * scale, paid);
    }

    /// @dev THE SCHEDULED SHOOTER-PROFIT TERMS, indexed by how many of the ten chips the ticket
    ///      placed itself. The low byte is the eligible-shooter percentage and the byte above is
    ///      the percent added to an eligible shooter's PROFIT:
    ///
    ///        placed       0       1       2       3       4       5       6       7
    ///        chance      15%     14%     12%     11%      9%      8%      6%      5%
    ///        uplift     +32%    +29%    +29%    +29%    +29%    +24%    +23%    +18%
    ///
    ///      The uplifts sit one to two points under what a field with no rotation would carry:
    ///      the difference funds the rotating shooter's +5% at forty seats.
    ///
    ///      Packed into one constant so the continuum costs one indexed shift instead of eight
    ///      branches. Only a SCHEDULED window is handed the result: custom battles always pass
    ///      zero and play the bare engine, while still accepting every placed-chip count.
    function _shooterBoostTerms(uint256 placed) internal pure returns (uint256) {
        return (0x1205170618081D091D0B1D0C1D0E200F >> (placed << 4)) & 0xFFFF;
    }

    /// @dev The entire settlement of `betId`, decided the moment its table's word landed. Shared
    ///      by the paying path and the preview so the two can never disagree about what a bet is
    ///      worth. Pure in the committed inputs — the caller supplies the word.
    function _settlementOf(uint256 betId, uint256 header, Window memory w, uint256 word)
        internal
        pure
        returns (Settlement memory s)
    {
        uint256 chipFlip;
        unchecked {
            chipFlip = (w.played / 1 ether) / _BONUS_CHIPS;
        }
        // The board a slip actually PLAYS: the chips it named, grown to ten by the dice.
        // The throw comes off the table's own word keyed to the OWNER, so two players at one
        // table get different boards; both inputs were fixed before this could be read — the word
        // did not exist when the slip was placed, and the owner is who placed it. The stored sum
        // says exactly how many of the ten remain for the dice.
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 placed;
        (, placed) = _packChips(uint32(packed));
        Craps.Bets memory board = _boardFrom(packed, chipFlip);
        _scatterInto(board, _hash2(word, uint160(header)), chipFlip, _BONUS_CHIPS - placed);

        // Lean mode: settlement pays from the scalars alone, so the per-leg books stay off. The
        // owner rides in for the survival coin alone — the dice stay the TABLE's, so the field
        // still shares a shooter, but no two slips take the same second chance.
        //
        // The shooter is keyed to `w.bound`, the WINDOW's own slot, and never to where the slip
        // happens to be stored. A whole-day ticket — the house's and the vault's seats included —
        // lives at the day's reserved `day * _BONUS_SLOTS_PER_DAY`, so keying off the bet id would
        // hand the day lane a second stream and split the field's exposure in two. Keying off the
        // window instead is also what keeps two windows that shut onto the SAME table index apart:
        // the word alone would give them identical dice.
        //
        // The SHOOTER PROFIT BOOST rides the same call, and only for a window the protocol
        // scheduled itself: a custom battle is handed zero, so its every byte of settlement is
        // what it always was. The ticket is classified from the word it was STORED with — before
        // the scatter, which is what the dice did to it — so the boost row cannot be changed by
        // where the scattered chips happen to land.
        //
        // ONE ENGINE, ONE SET OF RULES. Both products latch the goal, hold it as a protected
        // reserve, escalate every three shooters to `uint32.max`, and run to the same bounds — a
        // custom table plays the same GAME, and the boundary between the two is entirely about
        // MONEY. The one thing the slot decides here is the SHOOTER BOOST, which is house money
        // and therefore the protocol's own windows' alone. Nothing reads the goal, the depth or
        // the schedule to decide which is which: a custom battle may legally copy every number a
        // scheduled one draws, and a future scheduled format could legally carry a zero boost.
        bytes32 seed = _crapsSeed(word, w.bound);
        uint256 boost;
        if (w.bound < _CUSTOM_SLOT_BASE) {
            boost = _shooterBoostTerms(placed);
            // THE ROTATING SHOOTER. One start for the whole field, drawn off the slot-keyed seed
            // under its own tag once the word exists, then passed seat by seat in dense order
            // and wrapping at the field's frozen count. This seat's turn is the hand whose
            // ordinal is its distance from the start; a run that stops first forfeits it, and a
            // turn past the hand bound is unreachable and encodes as none. A window's own seats
            // are the field's first segment, so a slip settled without a combined ordinal —
            // a preview — is at its own bet ordinal.
            uint256 n = w.entrants;
            if (n != 0) {
                uint256 seat = w.seat != 0 ? w.seat : uint64(betId);
                uint256 offset;
                unchecked {
                    offset = (seat + n - 1 - (_hash2(ROTATING_SHOOTER_TAG, uint256(seed)) % n)) % n;
                }
                if (offset < _MAX_SLIP_HANDS) boost |= (offset + 1) << _BOOST_TURN_SHIFT;
            }
        }
        SlipResult memory sr = _settleSlip(
            board, seed, w.bankroll, w.goal, _MAX_SLIP_HANDS, _SLIP_ROLL_BUDGET, address(uint160(header)), boost
        );
        // `Settlement` is the same seven-word memory shape as `SlipResult`. The first word —
        // bankrollIn — is dead after the engine returns and becomes `paid` below; every other
        // field is already at the offset its settlement reader expects.
        assembly ("memory-safe") {
            s := sr
        }

        // Paid exactly what the table returned. The only coin in the game is the MID-RUN second
        // chance inside `_settleSlip`, and it is the owner's alone; a run that lost one came home
        // with nothing and a run that won one played on, so by here `won` is already the whole
        // account.
        uint256 paid = s.won;

        // Land the award on a round figure, the same two-band policy the protocol uses: the
        // 100-FLIP granule only once it is a small slice of the award, the whole-FLIP floor below.
        if (paid != 0) {
            paid = paid > FlipRoundLib.FLIP_ROUND_THRESHOLD
                ? FlipRoundLib.roundFlipToHundreds(paid, _hash2(word, uint256(betId) ^ FLIP_ROUND_TAG))
                : FlipRoundLib.floorWholeFlip(paid);
        }
        // A BUST PAYS NOTHING, and what it was still holding is DELETED. The FLIP was burned at
        // entry, so deleting it is nothing more than declining to recreate it: no value
        // moves, no second burn is needed, and no other party — the winner, the field or the
        // protocol — receives it. Decided HERE, in the shared settlement, so the preview can never
        // disagree with the pay. `s.won` keeps the raw figure regardless, because that is what the
        // scoreboard ranks on: a busted run still competes on how long it lasted and what it had.
        if (s.stop == Craps.SlipStop.Bust) paid = 0;
        s.paid = paid;
    }

    // ---------------------------------------------------------------------------------------
    // The battle
    // ---------------------------------------------------------------------------------------

    /// @dev One bonus window, resolved from the day's word. Every field is a pure function of
    ///      (day, period), so a front end and this contract always agree without a call.
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
    }

    /// @dev The slot a day's shared field lives at — remainder ZERO, the one `_slotWindow`
    ///      refuses and no window ever takes.
    function _daySlotOf(uint256 day) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY;
        }
    }

    /// @dev Where a slot's day tickets live and how many of them there are. Custom battles are not
    ///      on the day clock and never carry any.
    function _dayField(uint256 slot) private view returns (uint256 base, uint64 n) {
        if (slot >= _CUSTOM_SLOT_BASE) return (0, 0);
        unchecked {
            uint256 d = _daySlotOf(slot / _BONUS_SLOTS_PER_DAY);
            return (d << 64, uint32(_dayTickets[d]));
        }
    }

    /// @dev A window's slot in the bonus lane. Period zero starts at remainder one; remainder
    ///      zero is reserved and identifies no field.
    function _slotOf(uint256 day, uint256 period) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY + period + 1;
        }
    }

    /// @dev Everything about the window at (day, period). Reverts if that day has no word yet,
    ///      since the word is what draws the terms.
    function _windowTerms(uint24 day, uint256 period) private view returns (Window memory w) {
        uint256 word = _dailyWordAt(day);
        if (word == 0) revert RngNotReady();
        return _windowTermsOn(day, period, word);
    }

    /// @dev The same terms off a word the caller already holds. Anything that builds SEVERAL of a
    ///      day's windows reads that word once and hands it down rather than fetching the same
    ///      value seven times — and a caller holding it can decide for itself what a missing word
    ///      means, instead of being reverted at.
    function _windowTermsOn(uint24 day, uint256 period, uint256 word) private pure returns (Window memory w) {
        (w.bankroll, w.goal, w.played, w.stakeUnits, w.tier) = _bonusPreset(_bonusRoll(word, period), period);
        unchecked {
            // The maximum a player may place directly: seven of the window's ten chips. The key
            // is built on the full round, so every placed/scattered split is the same race.
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.bound = uint48(_slotOf(day, period));
            // Every window of a day runs the SAME high lane, because the draw is the day's and
            // the slot names the day. A window armed or settled days later still reads its own.
            w.highMult = _highMultOf(word);
            // A bonus window bars NOBODY: its standing term is zero, and the score only decides
            // how much of the BOOST a winner may carry off. The term stays in the key so a window
            // and a custom battle on identical numbers still key the same way.
            w.terms = w.stakeUnits | (w.highMult << _TERM_HIGH_SHIFT);
        }
        w.key = _battleKey(w.bound, w.bankroll, w.goal, w.played, w.terms);
    }

    /// @notice GAME or VAULT: deliver a day-pass award. Reserves ONE pass on tomorrow where
    ///         tomorrow is free, and banks everything else as credit. The vault comps a seat
    ///         through the same door a lootbox award takes, so a comped ticket and a rolled one
    ///         are the same object and nothing downstream can tell them apart.
    /// @dev ONE CALL PER BATCH, and it is also the eligibility test. Whether tomorrow is already
    ///      taken and whether its word has landed are both facts about state held here, so the
    ///      Game does not pre-screen either — asking twice would either duplicate the rule in two
    ///      contracts that can drift apart, or cost a second call to learn what the first returns.
    ///
    ///      NOTHING HERE REVERTS on an ineligible day. It runs inside lootbox settlement, where a
    ///      revert would cost the player their whole box rather than one day's reservation, so an
    ///      unavailable tomorrow silently becomes credit instead. Credit never expires, so nothing
    ///      is lost by that.
    ///
    ///      The HIGH pass takes the slot when a batch holds both. It is the more valuable of the
    ///      two, and only one can be seated.
    /// @param player The award's owner.
    /// @param normal Normal passes the batch rolled.
    /// @param high High-roller passes the batch rolled.
    /// @return day The day a pass was reserved on, or zero if none was.
    /// @custom:reverts OnlyGame If the caller is neither the pinned game nor the pinned vault.
    function deliverPasses(address player, uint32 normal, uint32 high) external returns (uint24 day) {
        if (msg.sender != _GAME && msg.sender != ContractAddresses.VAULT) revert OnlyGame();
        unchecked {
            uint256 tomorrow = uint256(_currentDayIndex()) + 1;
            // A day index that will not fit is not a day anyone can reserve; the award simply
            // banks. The protocol runs out of uint24 days long before this matters.
            if (tomorrow <= type(uint24).max && (normal | high) != 0) {
                bool takeHigh = high != 0;
                // Blank: an award names no board, and naming one is what `amendSlip` is for.
                if (_reserveDay(player, uint24(tomorrow), takeHigh, _standingOf(player), 0, 0)) {
                    day = uint24(tomorrow);
                    if (takeHigh) --high;
                    else --normal;
                }
            }
            if (normal != 0) _credit(player, false, normal);
            if (high != 0) _credit(player, true, high);
        }
    }

    /// @dev Take one future day, or report that it could not be taken. A day is takeable only
    ///      while it is STRICTLY FUTURE and its word has not landed: the second condition is what
    ///      makes the commitment blind, and it fails closed if a future word is ever filled in
    ///      early.
    ///
    ///      A PASS BUYS THE SEAT, NOT A CLAIM ON ONE. The whole ticket is written here — the day's
    ///      dense seat number, the board the reservation named (or a blank one) and the standing
    ///      the holder carries right now — so there is nothing to come back and redeem, no window
    ///      to be present for, and no way for a day to strand a holder who was already paid up.
    ///      Nothing is given up by committing this early: `amendSlip` re-spreads the chips AND
    ///      refreshes the standing at any time until the day's first window closes.
    ///
    ///      The MULTIPLE is deliberately not stored. Entry is binary, so a high seat runs at
    ///      exactly its day's `highMult` — a number drawn from a word that cannot exist yet — and
    ///      settlement reads it off the window instead.
    function _reserveDay(
        address player,
        uint24 day,
        bool high,
        uint256 standing,
        uint256 packed,
        uint256 boonMask
    ) private returns (bool) {
        if (day <= _currentDayIndex()) return false;
        if (_dailyWordAt(day) != 0) return false;
        uint256 daySlot = _daySlotOf(day);
        if (_daySeated[daySlot][player] != 0) return false;
        // The whole seat, exactly as the paid door writes one, on the board the reservation
        // named — chip COUNTS, so one shape is legal at every window whatever its chip is worth.
        // Writing it days early only strengthens the freeze the arm relies on: the total still
        // cannot move once the day's first window stops taking bets.
        _writeDaySeat(daySlot, player, packed, standing, high, 0, boonMask);
        emit CrapsDayReserved(player, day, high);
        return true;
    }

    /// @dev ONE encoder for every coinflip credit the table pays. Shared so three payment sites
    ///      do not each carry their own copy of the call plumbing.
    function _creditFlip(address player, uint256 amount) private {
        ICoinflipStake(ContractAddresses.COINFLIP).creditFlip(player, amount);
    }

    /// @dev ONE encoder for every tagged craps burn, always on the caller — the three paid doors
    ///      share this plumbing the same way the payment sites share `_creditFlip`.
    function _burnForCraps(uint256 grossAndFlags) private returns (uint8) {
        return IFlipCoin(ContractAddresses.COIN).burnCoinForCraps(msg.sender, grossAndFlags);
    }

    /// @dev ONE encoder for the plain self-burns. The lapse sweep's guarded burn stays direct —
    ///      a `try` needs the external call in its own hands.
    function _burnCoin(uint256 amount) private {
        IFlipCoin(ContractAddresses.COIN).burnCoin(msg.sender, amount);
    }

    /// @dev The caller's standing, clamped to the field the bet word carries.
    function _standingOf(address player) private view returns (uint256 standing) {
        standing = IGameActivityScore(_GAME).playerActivityScore(player);
        if (standing > _BET_SCORE_MASK) standing = _BET_SCORE_MASK;
    }

    /// @dev Bank credits, SATURATING at the lane's ceiling. A lootbox sweep is permissionless and
    ///      must never revert on a full lane, so the excess is dropped and announced rather than
    ///      thrown — and the ceiling is four billion passes, which no box can approach.
    /// @return got What actually banked, which is `add` everywhere short of the ceiling. The
    ///         award split prices its pass slice off this figure, so a saturated lane leaves the
    ///         refused units' value liquid rather than deleting it.
    function _credit(address player, bool high, uint256 add) private returns (uint256 got) {
        unchecked {
            uint256 word = _passCredits[player];
            uint256 shift = high ? _PASS_HIGH_SHIFT : 0;
            uint256 held = (word >> shift) & _PASS_MAX;
            uint256 sum = held + add;
            // SATURATES silently. The cap is four billion passes a lane — unreachable by any real
            // award — and the clamp exists only so an impossible overflow could not spill into
            // the lane packed above this one. `CrapsPassesCredited` reports what actually banked.
            if (sum > _PASS_MAX) sum = _PASS_MAX;
            _passCredits[player] = (word & ~(_PASS_MAX << shift)) | (sum << shift);
            got = sum - held;
            emit CrapsPassesCredited(player, high, got);
        }
    }

    /// @dev Split one protocol-funded award between pass credit and liquid FLIP: HALF of it is
    ///      the pass target, floored to whole passes, and every wei the flooring, the high cap or
    ///      a saturated lane refuses simply stays liquid — the caller subtracts only `banked`, so
    ///      `liquid + banked == gross` exactly, by construction, and nothing here can delete
    ///      value. The denomination is the lootbox's own switch: a budget strictly above twenty
    ///      normal units pays HIGH, at most thirty of them, and one award never mixes lanes.
    ///      DETERMINISTIC on purpose — the winner is receiving FLIP in this same transaction, so
    ///      fractional dust rides home as change and no coin is tossed.
    /// @param taggedGross The award in FLIP wei, with its `_SPLIT_SRC_*` tag in the top byte.
    /// @return banked The exact FLIP value of the passes actually credited — what the caller
    ///         removes from the liquid payment. Zero banks nothing and emits nothing.
    function _splitAward(bytes32 key, address player, uint256 taggedGross) internal returns (uint256 banked) {
        unchecked {
            uint256 gross = taggedGross & _SPLIT_GROSS_MASK;
            uint256 budget = gross / 2;
            bool high = budget > _PASS_HIGH_SWITCH;
            uint256 unit = high ? _HIGH_PASS_VALUE : _NORMAL_PASS_VALUE;
            uint256 wanted = budget / unit;
            if (wanted == 0) return 0;
            if (high && wanted > _MAX_HIGH_PASSES_PER_AWARD) wanted = _MAX_HIGH_PASSES_PER_AWARD;
            banked = _credit(player, high, wanted) * unit;
            if (banked != 0) {
                emit CrapsProtocolAwardSplit(key, player, uint8(taggedGross >> 248), gross, gross - banked);
            }
        }
    }

    /// @notice Commit `count` of your own day-pass credits to `count` consecutive future days.
    /// @dev ALL OR NOTHING. The whole range is checked before a single credit is spent, and any
    ///      day in it that is already taken, already worded or not yet future takes the entire
    ///      call down. There is no skipping, no partial application and no partial debit — a
    ///      caller who wanted the days either side of an occupied one asks for them separately.
    ///
    ///      A run this walks is bounded by `count`'s own byte, so the caller pays for exactly what
    ///      they asked for and nothing here can be made to walk further.
    /// @param startDay The first day to reserve. Must be strictly after today.
    /// @param count    How many consecutive days, 1..255.
    /// @param high     Which credit lane to spend.
    /// @param chips    The packed board every reserved day starts on — zero through seven named
    ///                 chips in the same packed shape every live door takes. Each day may still
    ///                 be re-spread on its own through
    ///                 `amendSlip` once that day opens.
    /// @custom:reverts BadPassCount If `count` is zero.
    /// @custom:reverts DayNotReservable If any day in the range is taken, worded or not future.
    /// @custom:reverts BadRandomCount If `chips` names more than seven chips.
    /// @custom:reverts TooManyChipsOnALeg If any leg stacks more than three chips.
    /// @custom:reverts BoardPlaysBothSides If it names both the pass line and don't pass.
    function applyCrapsPasses(uint24 startDay, uint8 count, bool high, uint32 chips) public {
        _takeCredits(msg.sender, high, count);
        _reserveRun(startDay, count, high, chips, 0);
    }

    /// @notice Buy `count` consecutive future days outright, at the fixed price.
    /// @dev The PRICE IS FIXED AND PAID NOW, before the target days draw their terms or their
    ///      high-roller multiple. That is what is being bought: a day whose cost is not yet known,
    ///      at a number that cannot move. Redemption never tops up and never refunds, whichever
    ///      way the day lands, and an unredeemed day is simply gone.
    ///
    ///      The burn happens AFTER the whole range has been vetted, so a range that cannot be
    ///      taken costs nothing.
    /// @param startDay The first day to reserve. Must be strictly after today.
    /// @param count    How many consecutive days, 1..255.
    /// @param high     Whether these are high-roller days.
    /// @param chips    The packed board every reserved day starts on — zero through seven named
    ///                 chips, exactly as `applyCrapsPasses` takes it.
    /// @custom:reverts BadPassCount If `count` is zero.
    /// @custom:reverts DayNotReservable If any day in the range is taken, worded or not future.
    function buyFutureCrapsDays(uint24 startDay, uint8 count, bool high, uint32 chips) public {
        if (count == 0) revert BadPassCount();
        uint8 boonMask;
        unchecked {
            boonMask = _burnForCraps(
                _tag(
                    uint256(count) * (high ? _HIGH_FUTURE_DAY_PRICE : _NORMAL_FUTURE_DAY_PRICE),
                    _CRAPS_FLAG_PASS
                )
            );
        }
        // The burn goes FIRST and the run is vetted as it is written. A day the run cannot take
        // reverts the whole call, and the burn unwinds with it — so a rejected range still costs
        // nothing, and the rule lives in one place instead of being restated in a pre-walk that
        // could drift from the writer.
        _reserveRun(startDay, count, high, chips, boonMask);
    }

    /// @notice Convert your own uncommitted normal pass credits into high-roller credits, at
    ///         nineteen normals per high — the credits' own value ratio, exactly.
    /// @dev ONE PACKED WRITE moves both lanes, so the debit and the credit are all-or-nothing by
    ///      construction and no failure can leave either lane half-moved. Only BANKED credits are
    ///      reachable: a reservation already committed to a day lives in that day's seat word,
    ///      not here. ONE-WAY — a high credit never breaks back into normals.
    /// @param highCount How many high-roller credits to buy. Costs `19 * highCount` normals.
    /// @custom:reverts BadPassCount If `highCount` is zero.
    /// @custom:reverts PassLaneFull If the high lane cannot hold the result.
    /// @custom:reverts Panic(0x11) If the caller holds fewer than `19 * highCount` normals.
    function convertNormalToHigh(uint32 highCount) external {
        if (highCount == 0) revert BadPassCount();
        uint256 word = _passCredits[msg.sender];
        uint256 cost;
        uint256 highs;
        unchecked {
            cost = uint256(highCount) * _PASSES_PER_HIGH;
            highs = ((word >> _PASS_HIGH_SHIFT) & _PASS_MAX) + highCount;
        }
        if (highs > _PASS_MAX) revert PassLaneFull();
        // Deliberately CHECKED, exactly as `_takeCredits`: the underflow IS the balance test.
        uint256 normals = (word & _PASS_MAX) - cost;
        _passCredits[msg.sender] =
            (word & ~(_PASS_MAX | (_PASS_MAX << _PASS_HIGH_SHIFT))) | (highs << _PASS_HIGH_SHIFT) | normals;
        emit CrapsNormalPassesConverted(msg.sender, cost, highCount);
    }

    /// @dev Spend `count` credits from one lane. CHECKED: an insufficient balance underflows and
    ///      takes the call down, so the check and the debit are one write rather than two.
    function _takeCredits(address who, bool high, uint256 count) private {
        if (count == 0) revert BadPassCount();
        uint256 word = _passCredits[who];
        uint256 shift = high ? _PASS_HIGH_SHIFT : 0;
        uint256 held = (word >> shift) & _PASS_MAX;
        // Deliberately CHECKED — this is the one subtraction here that can be driven negative by a
        // caller, and it is the whole balance validation.
        held -= count;
        _passCredits[who] = (word & ~(_PASS_MAX << shift)) | (held << shift);
    }

    /// @dev Write the run, vetting each day as it goes. ALL OR NOTHING: the first day that
    ///      cannot be taken takes the whole call down, and everything already written — the
    ///      earlier days, the credit debit, the burn — unwinds with it. There is no skipping and
    ///      no partial run.
    ///
    ///      The day index is widened before the add so a run that would walk off the end of the
    ///      `uint24` day space fails on the day itself rather than wrapping into the past.
    function _reserveRun(uint24 startDay, uint8 count, bool high, uint32 chips, uint256 boonMask) private {
        // The board is vetted ONCE for the whole run, by the same test every live door uses:
        // zero through seven chips within the per-leg cap and off the both-sides trap. One
        // slip serves every day of the run; `amendSlip` still re-spreads any single day once that
        // day opens.
        uint256 packed = _upToSeven(chips);
        // Read ONCE for the whole run: a standing is a property of the caller, not of the day, and
        // a 255-day run must not make 255 trips into the game to ask the same question.
        uint256 standing = _standingOf(msg.sender);
        unchecked {
            for (uint256 i = 0; i < count; ++i) {
                uint256 d = uint256(startDay) + i;
                // ONE boon, ONE ticket: a multi-day purchase marks only its first reserved day,
                // and the boon rides that day's seat exactly as a day ticket's does — every
                // window the seat plays. Marking more days would multiply one boon over a run of
                // independent tickets.
                if (
                    d > type(uint24).max
                        || !_reserveDay(msg.sender, uint24(d), high, standing, packed, i == 0 ? boonMask : 0)
                ) {
                    revert DayNotReservable();
                }
            }
        }
    }

    /// @notice Upgrade chosen windows of YOUR OWN whole-day ticket to the day's high-roller
    ///         lane, paying each window's missing `H - 1` seat copies. The ticket already
    ///         supplies one, so after the delta burns the selected windows settle exactly as a
    ///         native high seat: `H` copies of the ONE run, one main-scoreboard entry, one bounty
    ///         in the main pot and `H - 1` in the lane — same board, same dice, same rounding.
    /// @dev ALL OR NOTHING over the NEW bits: every window still being bought is vetted through
    ///      the same joinability test the paid doors use before anything burns, so a mask naming
    ///      one shut, armed or nonexistent window buys nothing anywhere. Bits already high are
    ///      ignored rather than charged twice — but a mask naming ONLY those has nothing to buy
    ///      and reverts. There is no downgrade, no transfer and no refund, and no quest credit
    ///      moves here: the streak was paid when the day was taken, and this is the same day.
    ///
    ///      A banked pass or an unworded future reservation cannot come through this door at
    ///      calculated terms: a day that is not OPEN fails the joinability test on every period,
    ///      so in practice `day` is today, upgraded window by window while each still takes bets.
    /// @param day        The ticket's day.
    /// @param periodMask Which periods to upgrade, bit `p` for period `p`. Bits 0..6 only.
    /// @return burned The exact FLIP delta charged: the sum over the newly upgraded windows of
    ///         `(bankroll + bounty) * (H - 1)`.
    /// @custom:reverts BonusPeriodSpent If the mask names a period past the seventh, or any newly
    ///         selected window is closed by the clock, already armed, or not yet opened.
    /// @custom:reverts RngNotReady If a newly selected window is on a day whose word has not landed
    ///         — a banked pass or an unworded future reservation cannot be upgraded at calculated
    ///         terms, so its every period fails this before anything burns.
    /// @custom:reverts NoSuchBet If the caller holds no day ticket on `day`.
    /// @custom:reverts NothingToUpgrade If no selected period is newly upgradable.
    function upgradeDayWindows(uint24 day, uint8 periodMask) external returns (uint256 burned) {
        // Bits above the seven periods name windows that do not exist.
        if (periodMask > 0x7F) revert BonusPeriodSpent();
        uint256 daySlot = _daySlotOf(day);
        // The caller's own ticket or nothing: the seat lookup is keyed to the caller, so nobody
        // can reach — or be charged for — anyone else's.
        uint256 seat = _daySeated[daySlot][msg.sender];
        if (seat == 0) revert NoSuchBet();
        uint256 betId = (daySlot << 64) | seat;
        uint256 header = _bets[betId];
        uint256 newMask = periodMask & ~(header >> _BET_HIGH_SHIFT);
        if (newMask == 0) revert NothingToUpgrade();
        uint256 counters;
        unchecked {
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                if (newMask & (1 << p) == 0) continue;
                // The very test every paid door uses: opened, unarmed, and its period still to
                // come. A window shut by the CLOCK fails it whether or not anyone has armed it
                // yet — the same instant its own entry door closed.
                Window memory w = _joinableSlot(_slotOf(day, p));
                // The missing copies of the WHOLE seat — the bankroll each runs and the bounty
                // each posts, exactly as the high door prices them. The ticket itself is the one
                // copy already paid for.
                burned += (uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT) * (w.highMult - 1);
                counters += 1 << (_DT_HIGH_SHIFT * (p + 1));
            }
        }
        _burnCoin(burned);
        _bets[betId] = header | (newMask << _BET_HIGH_SHIFT);
        unchecked {
            _dayTickets[daySlot] += counters;
        }
        emit CrapsDayWindowsUpgraded(msg.sender, day, uint8(newMask), burned);
    }

    /// @notice Open all seven of today's bonus windows at once, once a day. Each is joinable from
    ///         here, in any order and for as long as its own period has not passed, so a player
    ///         picks the windows they want rather than waiting at each. The terms were public the
    ///         moment the day's word landed.
    /// @dev Called by the GAME, on the daily advance that applies that word — never by a player,
    ///      which is what keeps the opening on the same crank as the word it depends on.
    ///
    ///      NOTHING HERE REVERTS. It runs inside the advance, so a revert would not skip the
    ///      opening, it would take the whole protocol's daily crank down with it. A day already
    ///      open and a day whose word has not landed both simply do nothing, and the absence of
    ///      `CrapsBonusOpened` is how either is seen. The seat burns are already fail-soft for the
    ///      same reason.
    /// @custom:reverts OnlyGame If the caller is not the pinned game.
    /// @dev Opening walks nothing but today. A window that this day leaves unshut is not stranded
    ///      and does not need sweeping up: `armBonusWindow` takes any window that has stopped
    ///      taking bets, on any day, in any order, from anyone.
    function openBonusDay() external {
        if (msg.sender != _GAME) revert OnlyGame();
        uint24 today = _currentDayIndex();
        unchecked {
            if (_bonus >= uint256(today) + 1) return;
            // The word is what draws every window's terms, and it is what makes the house's seat
            // payable: sDGNRS holds its FLIP entirely as coinflip backing, which only settles once
            // the day it belongs to has resolved. The advance applies it two calls before this
            // one, so it is here; if it ever is not, the day goes unopened rather than unadvanced.
            // Read ONCE for the whole day and hand it to all seven. Having it here is also what
            // lets a missing word be a day that does not open rather than a revert: this runs
            // inside the advance, where reverting stops the protocol's crank and not just the
            // opening.
            uint256 word = _dailyWordAt(today);
            if (word == 0) return;
            _bonus = uint256(today) + 1;
            // The day's bonus budgets, drawn ONCE off the table's own recent books and fixed
            // here. Every window of the day shares them, so what a window offers is settled
            // before anyone can sit down at it. The routine weighting rides home in the same word
            // it divides: it is a pure function of `word`, but every later read of a window's
            // share would otherwise have to re-roll all six routine windows to recover it.
            (uint256 rawMain, uint256 highBudget) = _drawBudgets(today);
            // HALF THE MAIN ALLOCATION NEVER REACHES A WINDOW. The ladder gets one half; the other
            // is banked in the progressive, here and exactly once — this whole block is behind the
            // `_bonus` guard set above, so however many times the day is arbed, opened or
            // advanced, it funds once.
            (uint256 mainBudget, uint256 contribution) = _splitMainBudget(rawMain);
            _boostBudget[today] = mainBudget | (_routineWeight(word) << _BUDGET_W_SHIFT);
            // A day that banked no high action has no high budget, and writing a zero would cost
            // a slot to say so.
            if (highBudget != 0) _highBudget[today] = highBudget;
            uint256 pool = _progressive + contribution;
            _progressive = pool;
            emit CrapsProgressiveFunded(today, contribution, pool);
            emit CrapsHighRollerDayOpened(today, uint16(_highMultOf(word)), mainBudget, highBudget);
            uint256 cost;
            for (uint256 p = 0; p < _BONUS_PERIODS_PER_DAY; ++p) {
                cost += _openWindow(today, p, word);
            }
            // The house and the vault take DAY seats — one ticket each for the whole day, rather
            // than one per window. Two bet writes instead of fourteen, for the same field in every
            // window and the same price paid for it.
            _seatDayLane(_daySlotOf(today), cost);
        }
    }

    /// @dev Open one window, seat the house and the vault in it, and announce it.
    function _openWindow(uint24 day, uint256 period, uint256 word) private returns (uint256 cost) {
        Window memory w = _windowTermsOn(day, period, word);
        // Only the stake echo is banked. The seed is a pure function of the day's word, so it is
        // recomputed wherever it is needed and never stored — which is also why an uncontested
        // window creates nothing to reclaim, and why the seed field below belongs entirely to
        // donations.
        _battles[w.key] = w.stakeUnits << _BG_STAKE_SHIFT;

        unchecked {
            cost = uint256(w.bankroll) + w.stakeUnits * _BATTLE_STAKE_UNIT;
        }

        emit CrapsBonusOpened(
            w.key,
            w.bound,
            _boostBase(w) * _BOOST_MAX_MULT,
            w.bankroll,
            w.goal,
            w.postedStake,
            w.stakeUnits * _BATTLE_STAKE_UNIT
        );
    }

    /// @notice Shut a bonus window and take the table it settles on. Permissionless, open from the
    ///         moment that window stops taking bets, and good for ANY window on any day in any
    ///         order — which is what makes a window impossible to strand, whoever forgot it and
    ///         however long ago. The index is `_currentIndex()`, the table whose word cannot exist
    ///         yet — every path that fills an index advances the cursor past it in the same
    ///         transaction — so the dice were unknowable to every entrant however late it is shut.
    ///         The request fired below is the one that fills it.
    /// @param slot The window: `day * _BONUS_SLOTS_PER_DAY + period + 1`.
    function armBonusWindow(uint64 slot) external returns (uint48 index) {
        (,, uint256 open) = _currentBonusSlot();
        // Anything below the window currently taking bets has stopped taking them — on this day or
        // any before it, since a slot is `day * _BONUS_SLOTS_PER_DAY + period + 1` and so runs in
        // time order. No schedule order is imposed on top of that: two windows binding out of
        // sequence still settle on their own words, and choosing the moment gains nothing when the
        // index bound is one that has no word yet.
        if (slot >= open) revert BonusStillRunning();
        if (_slotIndex[slot] != 0) revert BonusPeriodSpent();
        Window memory w = _slotWindow(slot);
        if (_battles[w.key] == 0) revert BonusPeriodSpent();
        index = _armSlot(slot, w);
    }

    /// @dev The arm itself, past the door's checks — shared by the permissionless door above and
    ///      the scheduled cursor, which has already proven the same preconditions on its own walk.
    function _armSlot(uint64 slot, Window memory w) private returns (uint48 index) {
        unchecked {
            index = _currentIndex();
            _slotIndex[slot] = index + 1;
            // The day field joins the window HERE rather than at the ticket sale, so selling a day
            // ticket never touches seven scoreboards. Both counts are already frozen — tickets
            // stop when the day's first window stops taking bets, and THIS period's high count
            // stops moving at this window's own entry close, before anything can be shut.
            // One read carries all the counts; the window folds in the total and the high count
            // that belongs to its own period — counter `p + 1` of the word, which is
            // `slot % _BONUS_SLOTS_PER_DAY` exactly. A custom battle is not on the day clock and
            // carries no day field at all.
            if (slot < _CUSTOM_SLOT_BASE) {
                uint256 tickets = _dayTickets[_daySlotOf(uint256(slot) / _BONUS_SLOTS_PER_DAY)];
                if (uint32(tickets) != 0) _battles[w.key] += uint32(tickets);
                uint256 dayHigh = (tickets >> (_DT_HIGH_SHIFT * (uint256(slot) % _BONUS_SLOTS_PER_DAY))) & _MASK32;
                if (dayHigh != 0) _highField[w.key] += dayHigh;
            }
        }
        // Shutting a window also asks the protocol for the word that settles it: the request
        // fulfils into the cursor it was sent at, which is the index bound above, and advances the
        // cursor past it. The lootbox queue's pending-value gates do not apply to this caller — the
        // word settles a table, not a queue — but the temporary ones do. Fail-open: if the lootbox
        // lane cannot request right now — LINK, gas ceiling, the daily lock, a request already in
        // flight — the cursor stays put and the next request on that lane, whoever sends it, fills
        // this same index. Closing on the clock must not be hostage to it.
        try IGameLootboxRng(_GAME).requestLootboxRng() {} catch {}
        emit CrapsBonusArmed(w.key, uint48(slot), index);
    }

    /// @dev The window a player may still join: one of today's, opened, not yet shut, and not in
    ///      a period that has already run out.
    /// @dev THE joinability test: a battle you can still bet into. Every door that takes money on
    ///      a battle's behalf — an entry, a donation — goes through this one function, so a
    ///      donation can never reach a field an entrant could not also have reached.
    function _joinableSlot(uint256 slot) internal view returns (Window memory w) {
        if (slot >= _CUSTOM_SLOT_BASE) {
            uint256 c;
            (w, c) = _customTerms(slot);
            unchecked {
                if (block.timestamp >= ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusPeriodSpent();
            }
        } else {
            // A window whose period has already come round is shut whether or not anyone armed it.
            (,, uint256 live) = _currentBonusSlot();
            if (slot < live) revert BonusPeriodSpent();
            w = _slotWindow(slot);
            // A window nobody opened is not a battle yet.
            if (_battles[w.key] == 0) revert BonusPeriodSpent();
        }
        // Shut is shut: a battle whose table has been taken takes no more of anything, whatever
        // some clock says.
        if (_slotIndex[slot] != 0) revert BonusPeriodSpent();
    }

    function _joinableWindow(uint256 period) private view returns (Window memory w) {
        if (period >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
        uint24 today = _currentDayIndex();
        return _joinableSlot(_slotOf(today, period));
    }

    /// @dev The one placement path every bonus door funnels through. Kept single on purpose:
    ///      `_place` is private and the optimizer inlines a full copy at each call site, so a
    ///      door of its own per entry mode costs more than the mode is worth.
    function _enterWindow(Window memory w, uint32 chips, uint256 multiple) private returns (uint256) {
        return _place(w, _upToSeven(chips), multiple, _standingOf(msg.sender));
    }

    /// @dev A door's board: zero through seven named chips. Every count grows to the same ten-chip
    ///      round at settlement, so none of them changes the field key or creates a private race.
    function _upToSeven(uint32 chips) private pure returns (uint256 packed) {
        uint256 count;
        (packed, count) = _packChips(chips);
        if (count > _MAX_PICKED_CHIPS) revert BadRandomCount();
    }

    /// @notice Join one of today's bonus windows, placing up to seven chips. `chips` names them by
    ///         COUNT — how many of the stack go on each leg — rather than by FLIP,
    ///         so ONE allocation enters any window whatever its chip is worth. The window dictates
    ///         bankroll, target and bounty, so there is nothing else to supply.
    ///
    ///         The dice scatter the rest of the ten: an all-zero `chips` leaves the whole board
    ///         to the draw.
    function enterBonusBattle(uint256 period, uint32 chips, uint16 multiple) public returns (uint256 betId) {
        Window memory w = _joinableWindow(period);
        return _enterWindow(w, chips, multiple);
    }

    /// @notice Enter EVERY one of today's windows with the same chip allocation, in one call.
    ///         Each window scales the allocation to its own chip, so a single board is a legal
    ///         entry at all of them however differently they are sized — which is the whole
    ///         reason the allocation is counted in chips rather than in FLIP. An all-zero
    ///         allocation takes the whole day blind, every chip of every window left to the dice.
    ///
    ///         Sold only while the first window is still taking bets: a whole-day ticket is a
    ///         commitment made before any of the day is spent. Past that, take what is left one
    ///         window at a time through `enterBonusBattle`.
    /// @return placed How many windows took the entry.
    /// @custom:reverts BonusPeriodSpent If the day's first window has already closed.
    function enterBonusDay(uint32 chips, uint16 multiple) public returns (uint256 placed) {
        (uint24 today, uint256 period,) = _currentBonusSlot();
        uint256 word = _dailyWordAt(today);
        if (word == 0) revert RngNotReady();
        // THE DAY LANE OR NOTHING. A whole-day ticket is a commitment made before any of the day
        // is spent, so it is sold only while the first window is still taking bets. Past that the
        // day is part-spent and what is left is taken one window at a time through
        // `enterBonusBattle` — the same seats at the same prices, without a SET of slips that has
        // to be stamped with where it began, locked as one and amended as one.
        if (period != 0) revert BonusPeriodSpent();
        return _enterDayLane(today, word, chips, multiple);
    }

    /// @notice Add FLIP to a battle's seed, so its winner takes more than the entrants put in.
    /// @dev Permissionless, but accepted only while the battle remains joinable. The explicit
    ///      ceiling protects the scoreboard's 31-bit seed field.
    /// @param custom   True for a custom battle, false for one of today's bonus windows.
    /// @param index    The custom battle's number, or the window's period.
    /// @param granules What to add, in `_BATTLE_STAKE_UNIT` granules.
    function donate(bool custom, uint256 index, uint24 granules) external {
        uint256 slot;
        unchecked {
            if (custom) {
                slot = _CUSTOM_SLOT_BASE + index;
            } else {
                if (index >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
                uint24 today = _currentDayIndex();
                slot = _slotOf(today, index);
            }
        }
        Window memory w = _joinableSlot(slot);
        uint256 g = _battles[w.key];
        if (granules == 0 || g == 0) revert SeedAboveMax();
        uint256 seed;
        uint256 amount;
        unchecked {
            seed = ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK) + granules;
            amount = uint256(granules) * _BATTLE_STAKE_UNIT;
        }
        if (seed > _BG_SEED_MASK) revert SeedAboveMax();
        _burnCoin(amount);
        _battles[w.key] = (g & ~(_BG_SEED_MASK << _BG_SEED_SHIFT)) | (seed << _BG_SEED_SHIFT);
        emit CrapsBonusDonated(w.key, msg.sender, amount, seed * _BATTLE_STAKE_UNIT);
    }

    /// @notice One of today's windows as it stands: its battle, the table it settled on (zero
    ///         until it shuts), its seed, and whether it is still taking entries.
    function _bonusWindowOf(uint256 period)
        internal
        view
        returns (bytes32 battleKey, uint48 index, uint256 seed, bool joinable)
    {
        (uint24 today,, uint256 slot) = _currentBonusSlot();
        if (period >= _BONUS_PERIODS_PER_DAY) return (bytes32(0), 0, 0, false);
        Window memory w = _windowTerms(today, period);
        battleKey = w.key;
        uint256 target = w.bound;
        uint48 stored = _slotIndex[target];
        if (stored != 0) index = stored - 1;
        uint256 g = _battles[w.key];
        // The MOST this window can pay on top of the stakes, plus whatever has been donated onto
        // it. The rung itself is the settling table's, so `boostOf` is where the drawn figure
        // shows up and `_bonusBoostBand` is the spread it was drawn from.
        seed = _boostBase(w) * _BOOST_MAX_MULT + ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK) * _BATTLE_STAKE_UNIT;
        joinable = g != 0 && stored == 0 && target >= slot;
    }

    /// @notice What a bonus window's boost can be, in wei: its worst rung, its MEAN, and its
    ///         ceiling. Every window is a lottery — the rung comes off the word that SETTLES the
    ///         table, which does not exist while the field is forming — so this is the whole of
    ///         what is knowable at entry, and `boostOf` is where the drawn figure appears once
    ///         that word lands.
    /// @dev `mid` is the ladder's mean and therefore the day's budgeted seventh exactly, which is
    ///      what makes a day's budget an EXPECTATION rather than a cap: the realised total can
    ///      land far above it or far below.
    function _bonusBoostBand(uint24 day, uint256 period)
        internal
        view
        returns (uint256 low, uint256 mid, uint256 high)
    {
        if (_dailyWordAt(day) == 0 || period >= _BONUS_PERIODS_PER_DAY) return (0, 0, 0);
        Window memory w = _windowTerms(day, period);
        unchecked {
            uint256 base = _boostBase(w);
            // The bottom rung is a quarter of the base, so an unlucky window is never nothing —
            // it is simply the smallest thing the schedule pays.
            low = base / 4;
            mid = base;
            high = base * _BOOST_MAX_MULT;
        }
    }

    /// @notice Whether today's windows have been opened yet, and when the next day's can be.
    function _bonusDayOf() internal view returns (uint24 openedDay, bool openableNow) {
        uint256 latch = _bonus;
        uint24 today = _currentDayIndex();
        unchecked {
            if (latch != 0) openedDay = uint24(latch - 1);
        }
        openableNow = latch < uint256(today) + 1 && _dailyWordAt(today) != 0;
    }

    /// @dev Seat the house and the vault on the DAY lane: one ticket each, playing every window
    ///      of the day, at the sum of what those windows cost. They take whatever seats are next:
    ///      a day whose passes were spent in advance already has a field, and these two join it
    ///      rather than heading it. A window therefore always has a field: a lone entrant arrives
    ///      to a race rather than an empty table, and a window nobody turns up to is still one the
    ///      two of them settle between themselves.
    ///
    ///      Both burns are fail-soft, and NEITHER body is comped. A seat that was never funded
    ///      still counts in `entrants`, so the pot would pay out one more bounty than the field
    ///      burned — house money conjured out of a failed payment. Both bodies now accrue day
    ///      passes from their own lootboxes, so a house that cannot pay is a house that had
    ///      neither FLIP nor a pass, and a window it misses still opens and still pays whoever
    ///      turns up.
    function _seatDayLane(uint256 daySlot, uint256 cost) private {
        _seatBody(daySlot, ContractAddresses.SDGNRS, cost);
        _seatBody(daySlot, ContractAddresses.VAULT, cost);
    }

    /// @dev Seat ONE protocol body, cheapest funding first: a day it already holds a reservation
    ///      on, then a banked pass credit, then FLIP.
    ///
    ///      THIS IS THE ONLY PLACE EITHER BODY CAN SPEND A PASS. Both open lootboxes — the vault
    ///      buys them outright, sDGNRS resolves its own self-subscription boxes — so both are
    ///      handed passes by `deliverPasses` like any other winner, and the house banks its level
    ///      cut as high passes at every level close besides. Neither can reach the doors
    ///      that spend them: `applyCrapsPasses` and `buyFutureCrapsDays` key off `msg.sender`,
    ///      the vault would need a door of its own, and sDGNRS has no controller at all. So the
    ///      daily seat spends them, and a body that arrives already paid for is not charged twice.
    ///
    ///      A HIGH pass is honoured as a high seat, exactly as the paid door builds one: the
    ///      day's own multiple, the high bit, and the high half of the ticket counter — which is
    ///      what `armBonusWindow` folds into each window's sideboard. The FLIP fallback is always
    ///      an ordinary 1x seat, so `cost` is only ever the plain seven-window bill.
    function _seatBody(uint256 daySlot, address body, uint256 cost) private {
        // Already sitting: a pass spent on this day wrote the seat the moment it was spent, so
        // there is nothing here to buy.
        if (_daySeated[daySlot][body] != 0) return;
        // The vault plays a board its owner may name, and may name the sentinel instead and sit
        // the day out. Read BEFORE anything is spent, so standing down costs it neither FLIP nor a
        // banked pass. The house has no board and no say: it has nobody to choose for it, and
        // naming nothing is the one shape that cannot be read off in advance.
        uint256 chips;
        if (body == ContractAddresses.VAULT) {
            chips = _vaultBoard;
            if (chips == _VAULT_BOARD_OFF) return;
        }
        // THE BANK FIRST, FLIP SECOND. A pass is a claim on a day that is already bought and
        // cannot be spent on anything else, so it is what the seat reaches for; FLIP is liquid and
        // is only burned for a day the bank cannot cover. The burn pays the whole day — every
        // window's bankroll AND its bounty.
        bool high;
        bool funded;
        uint256 credits = _passCredits[body];
        if (credits >> _PASS_HIGH_SHIFT != 0) {
            (high, funded) = (true, true);
        } else if (credits & _PASS_MAX != 0) {
            funded = true;
        }
        if (funded) {
            _takeCredits(body, high, 1);
        } else {
            try IFlipCoin(ContractAddresses.COIN).burnCoin(body, cost) {
                funded = true;
            } catch {}
        }
        if (!funded) {
            // THE HOUSE SITS ANYWAY, bounty included. A bonus that waits on the reserve is a bonus
            // that silently stops happening, and the day still has to have somebody in it. The
            // seat costs the field one bounty it never burned, which is the price of the day
            // running at all — bounded to a single seat, and visible without a log of its own:
            // the seat's `CrapsSlipPlaced` lands with no matching burn beside it.
            //
            // The VAULT gets no such comp: it seeds nothing and is just another body at the table.
            if (body != ContractAddresses.SDGNRS) return;
        }
        // The house usually names no board, so the dice place all ten in every window it sits
        // in — naming nothing is also the one shape that cannot be read off in advance.
        //
        // Seated AT the floor. The boost ladder exists to keep house money away from wallets
        // with no history, and these two are the protocol itself — so they collect a window
        // they win in full rather than burning a subsidy one of them just paid for.
        _writeDaySeat(daySlot, body, chips, _SYBIL_SCORE_FLOOR, high, 0, 0);
    }

    /// @dev Throwing `n` chips onto `b`: one at a time, at a leg drawn off `word`. Every leg
    ///      stays a whole number of chips by construction — the tournament's own rule, met
    ///      without a check.
    ///
    ///      Written through the memory struct because `_settlementOf` immediately passes that
    ///      same board to the engine; rebinding a memory parameter would not update the caller's
    ///      reference.
    ///
    ///      Random rather than optimised on purpose: the dice are the field's pace-setter, not
    ///      its sharpest opponent, and finding a better board than a random one is the game.
    function _scatterInto(Craps.Bets memory b, uint256 word, uint256 chipFlip, uint256 n) internal pure {
        unchecked {
            for (uint256 i = 0; i < n; ++i) {
                // Memory structs are one word per field, so leg `n` is at offset 32n — and the
                // ten bettable legs are exactly fields 0..9, the dark side last. The draw hashes
                // the same two words `abi.encode(word, i)` would, out of scratch space so the loop
                // allocates none.
                assembly ("memory-safe") {
                    mstore(0x00, word)
                    mstore(0x20, i)
                    let p := add(b, mul(mod(keccak256(0x00, 0x40), 10), 0x20))
                    mstore(p, add(mload(p), chipFlip))
                }
            }
        }
    }

    /// @notice Where the seven-window daily schedule stands: protocol day, next closable window,
    ///         and its monotonic slot.
    function _currentBonusSlot() internal view returns (uint24 day, uint256 period, uint256 slot) {
        day = _currentDayIndex();
        unchecked {
            // `period` counts the windows whose closing time has arrived, not the part of the day
            // it is: the opener may be shut twenty minutes in, and one more every `_BONUS_PERIOD`
            // after the day's start.
            uint256 elapsed = (block.timestamp - 82_620) % 1 days;
            // THE EVENT SHUTS EARLY, and this is the whole of that rule. Past the lead the day has
            // no window still taking bets, so `period` runs one past the last of them — which
            // reads as `_BONUS_PERIODS_PER_DAY` to the joinability checks and puts `slot` one
            // above every window of the day for the arming ones. Both are thresholds, so no
            // caller has to learn about the early close to respect it.
            period = elapsed >= 1 days - _EVENT_LEAD
                ? _BONUS_PERIODS_PER_DAY
                : (elapsed < _BONUS_EVENT_CLOSE + _BONUS_CLOCK_ALIGN
                        ? 0
                        : 1 + (elapsed - _BONUS_CLOCK_ALIGN) / _BONUS_PERIOD);
            slot = _slotOf(day, period);
        }
    }

    /// @dev A window's draw: the day's committed word folded with window number 1..7, so no
    ///      window rides the bare word. Pure in two published inputs.
    function _bonusRoll(uint256 word, uint256 period) private pure returns (uint256) {
        unchecked {
            return _hash2(word, period + 1);
        }
    }

    /// @dev The shape a window takes, drawn from its own roll — a tournament format, not a
    ///      derivation of the entry fee. Six of the day's seven are routine and pick a tier
    ///      7:2:1 — small, medium, large; the LAST is the event, with a buy-in drawn in round
    ///      thousands and a seed of one whole buy-in. The event shuts `_EVENT_LEAD` BEFORE the
    ///      day turns over, so it settles in the run-up to the jackpot rather than after it. Every window is a table bet, ten of
    ///      which are the base a round puts down; it draws how deep the bankroll runs on that
    ///      base (two, five or ten rounds) and how far the target sits from it (five, ten,
    ///      twenty or fifty times), so the same buy-in can be a sprint or a long grind.
    ///
    ///      Everything returned satisfies the table's own bands by construction — bankroll floor,
    ///      the bankroll ceiling over the board, the battle goal floor, and a bounty inside its
    ///      band — so an armed window is always one a player can actually join, and the schedule
    ///      never advertises a battle placement would refuse. The board is named by TOTAL only:
    ///      any legal composition summing to it is in, which is the point of the match key.
    /// @dev Which of the three sizes a ROUTINE window drew, as 0, 1 or 2. Lifted out of
    ///      `_bonusPreset` because the day's weighting needs the size of all six and nothing else
    ///      about them: running the whole preset six times to read one field would cost the
    ///      bankroll, the goal, the bounty and the board for windows nobody asked about.
    ///      MUST stay bit-for-bit the draw `_bonusPreset` takes, or a window's weight and its tier
    ///      would disagree.
    function _tierPick(uint256 word, uint256 period) internal pure returns (uint256) {
        unchecked {
            uint256 roll = _bonusRoll(word, period);
            // The opener draws its size flat, a third each; every window after it is weighted
            // seven in ten to the small tier.
            if (period == 0) return (roll >> 40) % 3;
            uint256 draw = roll % 10;
            return draw < 7 ? 0 : (draw < 9 ? 1 : 2);
        }
    }

    /// @dev The day's six routine windows, weighted 4:2:1 by size and summed. This is the
    ///      DENOMINATOR the routine half is split on, so a day of six small tables and a day
    ///      carrying two large ones both spend the same half — the large tables simply take more
    ///      of it, which is the point: a 3,000 bankroll draws ten times the action of a 300 one
    ///      and an even seventh paid it the same subsidy.
    function _routineWeight(uint256 word) internal pure returns (uint256 total) {
        unchecked {
            for (uint256 p = 0; p + 1 < _BONUS_PERIODS_PER_DAY; ++p) {
                total += 1 << _tierPick(word, p);
            }
        }
    }

    /// @dev What ONE window takes of a day's budget. The day's EVENT — its last window, and the
    ///      one whose bankroll runs from 1,500 FLIP to 60,000 — takes HALF outright, because it
    ///      is the day's headline and an even seventh priced it as though it were a 300-FLIP
    ///      table. The other half is split across the six routine windows by size.
    function _windowShare(uint256 budget, uint256 weight, uint256 period, uint256 tier) private pure returns (uint256) {
        unchecked {
            uint256 half = budget / 2;
            if (period + 1 == _BONUS_PERIODS_PER_DAY) return half;
            // A day whose word never landed has no weights to divide by and no windows to pay.
            if (weight == 0) return 0;
            return (half * (1 << (tier - 1))) / weight;
        }
    }

    function _bonusPreset(uint256 roll, uint256 period)
        private
        pure
        returns (uint128 bankroll, uint128 goal, uint256 boardStake, uint256 stakeUnits, uint256 tier)
    {
        unchecked {
            uint256 boardFlip;
            uint256 bountyFlip;
            uint256 bankrollFlip;
            // FIXED AT FIVE. The depth used to be a three-way draw, back when a run stopped the
            // moment it reached its target and the depth was what decided how long that took. A
            // scheduled run does not stop there any more — it latches the win and plays on — so
            // the depth stopped separating the formats and the schedule stopped drawing it.
            uint256 bankMult = _SCHED_BANK_MULT;

            if (period == _BONUS_PERIODS_PER_DAY - 1) {
                // The day's EVENT, and its last window. The draw names the PLAYING BANKROLL
                // outright — a ladder of 1,500 FLIP to 15,000 in 1,500 steps, with a tail one in
                // twenty at 30k and one in fifty at 60k — and the bounty is stepped by five points
                // from a quarter to a half of it and charged ON TOP. So the headline figure is the
                // run the player actually gets, not a number the bounty is then carved out of.
                //
                // It boosts one whole BANKROLL, not the entry cost: the bounty roll already sets
                // what the field puts up, and paying the protocol's share off that same roll would
                // reward it twice. The draw's mean of ~10,400 is therefore the day's expected
                // boost from here; the two tails carry a quarter of it between them, which is why
                // they are this rare. Closing on the day's own boundary, this is the one window
                // the NEXT day's word settles, which is what gives it a full day to gather a
                // field.
                uint256 tail = roll % 100;
                bankrollFlip = tail < 5 ? 30_000 : (tail < 7 ? 60_000 : 1500 * (1 + ((roll >> 8) % 10)));
                // Floored to the bounty granule: a quarter of an odd thousand lands on half a
                // unit otherwise. Flooring only ever moves the bounty DOWN its band, never out.
                bountyFlip = ((bankrollFlip * (25 + 5 * ((roll >> 16) % 6))) / 100 / 100) * 100;
                boardFlip = (bankrollFlip / bankMult / _BONUS_CHIPS) * _BONUS_CHIPS;
                if (boardFlip < _BONUS_CHIPS) boardFlip = _BONUS_CHIPS;
            } else {
                // A routine window names its BANKROLL — 300, 1200 or 3000, every one a multiple
                // of 300 — and takes a bounty from that tier's three. The bounty is deliberately
                // a LARGE share of the bankroll, from about a third of it up to the whole of it:
                // the bounty is what the field is racing for, and a subsidy on a rounding error
                // is not worth showing up to.
                //
                // The day's OPENER draws its tier flat, a third each, so the day starts on a
                // table whose size the schedule gives no hint of. Every window after it is
                // weighted hard toward the small tier — seven in ten — which is what keeps a
                // routine window routine and the day's seed on its schedule.
                uint256 b = (roll >> 8) % 3;
                uint256 pick3;
                if (period == 0) {
                    pick3 = (roll >> 40) % 3;
                } else {
                    uint256 draw = roll % 10;
                    pick3 = draw < 7 ? 0 : (draw < 9 ? 1 : 2);
                }
                // The TIER is drawn here — it fixes the bankroll and the bounty band. It no longer
                // carries a seed: house money is sized by the GAME (a share of the level's pool
                // target) against what the field itself funded, not by which tier the word picked.
                if (pick3 == 0) {
                    tier = 1;
                    bankrollFlip = _BONUS_SMALL_BANKROLL;
                    bountyFlip = b == 0 ? 100 : (b == 1 ? 200 : 300);
                } else if (pick3 == 1) {
                    tier = 2;
                    bankrollFlip = _BONUS_MED_BANKROLL;
                    bountyFlip = b == 0 ? 300 : (b == 1 ? 800 : 1200);
                } else {
                    tier = 3;
                    bankrollFlip = _BONUS_LARGE_BANKROLL;
                    bountyFlip = b == 0 ? 1000 : (b == 1 ? 1500 : 3000);
                }
                boardFlip = (bankrollFlip / bankMult / _BONUS_CHIPS) * _BONUS_CHIPS;
                if (boardFlip < _BONUS_CHIPS) boardFlip = _BONUS_CHIPS;
            }

            bankroll = uint128(bankrollFlip * 1 ether);
            boardStake = boardFlip * 1 ether;
            stakeUnits = (bountyFlip * 1 ether) / _BATTLE_STAKE_UNIT;

            // The target: five times the bankroll, in every scheduled window. Custom battles
            // continue to carry the creator's chosen target through their separate terms path.
            goal = uint128(bankrollFlip * _SCHED_GOAL * 1 ether);
        }
    }

    /// @dev The match key: one slot and the exact numeric terms every entrant shares. The round
    ///      played is included; chip composition is not, because every zero-through-seven choice
    ///      deliberately races in the same field.
    function _battleKey(uint48 bound, uint256 staked, uint256 goal, uint256 played, uint256 terms)
        private
        pure
        returns (bytes32 key)
    {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, BATTLE_TAG)
            mstore(add(ptr, 0x20), bound)
            mstore(add(ptr, 0x40), staked)
            mstore(add(ptr, 0x60), goal)
            mstore(add(ptr, 0x80), played)
            mstore(add(ptr, 0xA0), terms)
            key := keccak256(ptr, 0xC0)
        }
    }

    /// @dev The craps boon's payout-base ceiling. The percentage runs on the bankroll payment up
    ///      to this much, so the three tiers top out at 3,000 / 6,000 / 9,000 FLIP PER WINDOW — a
    ///      whole-day ticket plays seven, and its boon lifts every one of them, which is what its
    ///      seven-window burn paid for. The TOP TIER is 15%, not the 25% a one-window anchor
    ///      could afford: seven windows at a quarter would have let one boon add 105,000 FLIP,
    ///      and 15% holds the whole-ticket ceiling near where the anchored quarter sat.
    ///
    ///      A SHARED base ceiling rather than three separate caps: capping each tier at 9,000
    ///      would flatten all three to the same number on a big enough return and delete the
    ///      tier spread.
    uint256 internal constant _BOON_PAYOUT_BASE_CAP = 60_000 ether;

    /// @dev What a stored boon mask adds to an already-rounded, already-scaled bankroll payment.
    ///      Fails CLOSED: mask 0 and the unreachable 3/5/6/7 pay nothing, and a busted run pays
    ///      nothing because its payment is zero — which is also why a boon can never turn a bust
    ///      into a credit and move a settlement's `_CREDIT_UNITS` accounting.
    function _boonBonus(uint256 mask, uint256 basePaid) internal pure returns (uint256) {
        if (basePaid == 0) return 0;
        uint256 bps;
        if (mask == 1) bps = 500;
        else if (mask == 2) bps = 1000;
        else if (mask == 4) bps = 1500;
        else return 0;
        unchecked {
            uint256 base = basePaid > _BOON_PAYOUT_BASE_CAP ? _BOON_PAYOUT_BASE_CAP : basePaid;
            return (base * bps) / _BPS_DENOMINATOR;
        }
    }

    /// @dev Tag a craps price with its action flags. The low byte of every eligible price is zero
    ///      by construction; this asserts it instead of assuming it, because a dirty bit would OR
    ///      into the FLAGS — turning a window entry's JOIN into JOIN|PASS and paying out a level
    ///      quest — long before the lost wei mattered.
    function _tag(uint256 cost, uint256 flags) private pure returns (uint256) {
        if (cost & 0xFF != 0) revert BadBurnTag();
        return cost | flags;
    }

    /// @dev THE COMPARATOR, as one lexicographic scalar (see `_SC_GOAL_BIT`) — everything but the
    ///      entrant's standing, which the caller folds into the low bits.
    ///
    ///      A GOAL BEATS EVERY BUST, and there is ONE comparator for both products:
    ///
    ///        * GOALS race on the HIGH POINT, then on the ending bankroll. A run does not stop
    ///          when it wins any more, so how fast it got there stopped being a merit; how far it
    ///          got is.
    ///        * BUSTS race on shooters completed, then on the remainder still held. A bust's high
    ///          point reaches neither field: the goal bit is clear, so the primary is its hand
    ///          count and nothing about a temporary peak can enter an all-Bust race.
    function _compositeOf(Settlement memory s) internal pure returns (uint256) {
        unchecked {
            uint256 primary;
            uint256 goalBit;
            if (s.stop == Craps.SlipStop.Goal) {
                goalBit = _SC_GOAL_BIT;
                primary = _wonComponent(s.peak);
            } else {
                primary = s.handsPlayed;
            }
            return goalBit | (primary << _SC_PRIMARY_SHIFT) | (_wonComponent(s.won) << _SC_WON_SHIFT);
        }
    }

    /// @dev The money component of a composite score: whole FLIP, SATURATED at the field rather
    ///      than masked into it. The mask would wrap a seventeen-trillion-FLIP return to a small
    ///      one and rank it WORSE; no constructible battle reaches a fortieth of that, but a
    ///      comparator's job is to be right past the horizon too.
    function _wonComponent(uint256 won) internal pure returns (uint256 f) {
        unchecked {
            f = won / 1 ether;
            if (f > _SC_WON_MASK) f = _SC_WON_MASK;
        }
    }

    /// @dev A stored composite back into what it says. `hands` is recoverable for a BUST, whose
    ///      primary is its shooter count, and reads zero for a goal, whose primary is its high
    ///      point instead.
    function _decodeBest(uint256 best)
        internal
        pure
        returns (Craps.SlipStop stop, uint256 hands, uint256 peakFlip, uint256 endFlip)
    {
        unchecked {
            uint256 primary = (best >> _SC_PRIMARY_SHIFT) & _SC_PRIMARY_MASK;
            endFlip = (best >> _SC_WON_SHIFT) & _SC_WON_MASK;
            if (best & _SC_GOAL_BIT == 0) return (Craps.SlipStop.Bust, primary, 0, endFlip);
            return (Craps.SlipStop.Goal, 0, primary, endFlip);
        }
    }

    /// @dev Fold one settlement into its battle's scoreboard: a running (best score, the bet
    ///      holding it) pair, which is order-invariant — whatever settles last completes it, and
    ///      that IS the finalization. Nothing here ever loops, and nothing is written back to the
    ///      bet: the leader lives in this one shared word.
    /// @dev Breaks a dead-level score on the table's own word: the entrant whose tag is larger
    ///      takes the lead. A random total order rather than a running coin, so a field of any
    ///      size picks uniformly among its tied runs instead of favouring the last one to settle,
    ///      and arrival order carries no advantage at all. Replayable off-chain from the word.
    function _tieBreak(uint256 word, uint64 challenger, uint64 leader) private pure returns (bool) {
        return _hash2(word, challenger) > _hash2(word, leader);
    }

    function _scoreBattle(Window memory w, uint256 score, uint64 betId, uint256 word) internal {
        bytes32 key = w.key;
        uint256 g = _battles[key];
        unchecked {
            g += 1 << _BG_RESOLVED_SHIFT;
            // Greater displaces outright. Dead level — same rank, same ending bankroll, same
            // standing — goes to the coin, so the last tiebreak is the dice rather than arrival
            // order. `leader == 0` is the first entrant to score, who leads unopposed.
            uint64 leader = uint64(uint32(g >> _BG_WINNER_SHIFT));
            uint256 standing = (g >> _BG_BEST_SHIFT) & _SC_BEST_MASK;
            if (score > standing || leader == 0 || (score == standing && _tieBreak(word, betId, leader))) {
                // ONE CLEAR-AND-REPLACE over the composite and the seat holding it. Everything a
                // finalization reports about the winner — its stop, its high point, its ending
                // bankroll — is inside the composite, so a displaced leader leaves nothing behind
                // for the seat that beat it.
                g = (g & ~((_SC_BEST_MASK << _BG_BEST_SHIFT) | (uint256(_MASK32) << _BG_WINNER_SHIFT)))
                    | (score << _BG_BEST_SHIFT) | (uint256(betId) << _BG_WINNER_SHIFT);
            }
            uint256 entrants = g & _MASK32;
            // BANKED BEFORE ANYTHING LEAVES THE CONTRACT. `_payout` takes `g` by value and reads
            // no scoreboard, so committing the word here costs the same single write it always
            // did — and it means a finished field is already marked finished by the time the
            // first external credit is made, rather than while one is in flight.
            _battles[key] = g;
            if (((g >> _BG_RESOLVED_SHIFT) & _MASK32) == entrants) {
                // AND IT PAYS, here, in the same transaction that finished it. Everything a
                // payment needs was just computed to finalize the field — the winner, the boost,
                // the table's word — so a separate claim would only re-derive all of it and cost
                // the player a second transaction to collect what is already decided.
                _payout(w, g, word);
            }
        }
    }

    /// @dev What a window pays its winner on top of the stakes, in stake units — the day's
    ///      budgeted seventh times whichever rung the table drew.
    ///
    ///      EVERY WINDOW IS A LOTTERY, and the rung always comes off the word that SETTLES the
    ///      table. That word does not exist while entry is open, so a field forms knowing the
    ///      ceiling and the odds and nothing else; it lands the moment the table's VRF word does,
    ///      which is BEFORE a single hand is settled. The ladder averages exactly one, so a day
    ///      spends its budget in EXPECTATION and any single window can pay forty times its share.
    /// @dev A FRACTIONAL COPY of a run's result: `floor(p * y / r)`, where `r` is the bankroll
    ///      the run actually played and `y` is capital riding alongside it. A bust has `p == 0`
    ///      and so returns nothing; a run that doubled its bankroll doubles `y` too.
    ///
    ///      Done WITHOUT a 512-bit product. `p` splits into whole copies of the bankroll and a
    ///      remainder below one, and `floor(p*y/r)` is exactly `(p/r)*y + floor((p%r)*y/r)` — so
    ///      the only multiplication left has a factor smaller than the bankroll. CHECKED on
    ///      purpose: these are the one pair of operands here that are not obviously small, and a
    ///      revert is a better answer than a payout that wrapped.
    function _ride(uint256 p, uint256 y, uint256 r) internal pure returns (uint256) {
        if (p == 0 || y == 0) return 0;
        return (p / r) * y + ((p % r) * y) / r;
    }

    /// @dev The high lane's boost for this window, in granules. The SAME rung as the main lane —
    ///      one draw off the settling word, keyed to the battle — so the high lane adds no second
    ///      source of randomness and cannot be timed apart from the main one.
    function _highBoostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            return (_highBase(w) * _boostMult(word, w.key)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    /// @dev What the lane's boost is worth to the seat holding `header`, in WEI, and what that
    ///      seat's standing would not let it have. Rationed and rounded in GRANULES and only then
    ///      widened — the same order the main lane uses, which is what keeps every figure the
    ///      table pays a whole number of granules, and what makes the two parts add back to the
    ///      full-standing figure exactly.
    /// @return paid What the seat may carry — the whole thing at standing `_SYBIL_SCORE_FLOOR`.
    /// @return denied The rest. Protocol money, so it is banked in the progressive rather than
    ///         left unminted; zero at full standing, always.
    function _laneBoostSplit(Window memory w, uint256 word, uint256 header)
        private
        view
        returns (uint256 paid, uint256 denied)
    {
        unchecked {
            uint256 full = _highBoostUnits(w, word);
            uint256 got = _roundBoost(_boostShare(full, (header >> _BET_SCORE_SHIFT) & _BET_SCORE_MASK));
            paid = got * _BATTLE_STAKE_UNIT;
            denied = (_roundBoost(full) - got) * _BATTLE_STAKE_UNIT;
        }
    }

    /// @dev Fold one high seat's verdict into the sideboard, and — where it turns out to be the
    ///      lane's ONLY seat — settle the whole lane here, on that seat's own run.
    ///
    ///      A field of one is not a race. Refunding its extra bounties would hand back money the
    ///      seat chose to put at risk, and paying them out whole would pay a contest it never had
    ///      to win. So they ride the run it did make: the same dice, the same bankroll, pro rata.
    ///      The lane's boost rides with them, rationed by the same standing that rations the main
    ///      one — placed at RISK rather than paid, which is what stops a sole high roller from
    ///      being a way to draw house money down for free.
    /// @return ride What the run returned on that capital; zero on a bust, and zero is expected.
    /// @return extra The bounty part of it, which is player money and therefore real action. The
    ///         boost part is protocol money and is deliberately NOT booked — recycling emitted
    ///         boost into the burn that sizes the next boost would compound on itself.
    function _foldHigh(Window memory w, uint256 sc, uint64 seat, uint256 word, uint256 header, uint256 p)
        private
        returns (uint256 ride, uint256 extra)
    {
        uint256 f = _highField[w.key];
        unchecked {
            uint256 best = (f >> _HF_SCORE_SHIFT) & _SC_BEST_MASK;
            uint64 lead = uint64((f >> _HF_WINNER_SHIFT) & _MASK32);
            // The SAME comparator the main scoreboard runs, on the SAME unscaled composite: a
            // high roller buys copies of a run, never a better one, so the money it staked must
            // not reach either ranking.
            if (sc > best || lead == 0 || (sc == best && _tieBreak(word, seat, lead))) {
                f = (f & ~((_SC_BEST_MASK << _HF_SCORE_SHIFT) | (uint256(_MASK32) << _HF_WINNER_SHIFT)))
                    | (sc << _HF_SCORE_SHIFT) | (uint256(seat) << _HF_WINNER_SHIFT);
            }
            if (uint32(f) == 1) {
                extra = (w.highMult - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT;
                // THE CAPITAL IS COMPARED, NOT A RETURN. What the standing denies never gets on
                // the table, so nothing here manufactures a hypothetical winning run: only the
                // admitted boost rides, and the rest is banked before the dice are consulted.
                (uint256 lane, uint256 denied) = _laneBoostSplit(w, word, header);
                _rollIn(w.key, _ROLL_SRC_HIGH_SOLE | denied);
                ride = _ride(p, extra + lane, w.bankroll);
                // The pass slice comes off the PROTOCOL's part of the ride alone, measured as its
                // own pro-rata copy — never by flooring the bounty and boost rides separately,
                // whose floors could sum away from the combined figure the seat is owed. The
                // bounty part is player money and stays liquid whole, and a Bust rides nothing
                // and so awards nothing: its protocol ride is zero and zero banks zero.
                ride -= _splitAward(
                    w.key, address(uint160(header)), _SPLIT_SRC_HIGH_SOLE | _ride(p, lane, w.bankroll)
                );
                // The lane's final disposition, recorded in the same write the fold makes; the
                // resolve cursor is what keeps a later call from re-walking the seat.
                f |= _HF_DONE_BIT;
            }
            _highField[w.key] = f;
        }
    }

    function _boostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            // Multiplied in WEI and only then cut to granules. Flooring the base first would
            // round a small window's whole boost away — a thin day funds well under one granule
            // per window, and it is the top rungs that make such a window pay at all.
            return (_boostBase(w) * _boostMult(word, w.key)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    /// @dev The base a window's boost is drawn around, in FLIP wei. FLAT — the same figure
    ///      whether three sit down or three hundred, because that is what makes a window's size
    ///      the thing turnout is measured AGAINST.
    ///
    ///      A window puts up a share of its own day's budget, and that budget is a flat base plus
    ///      a rate on the ACTION the week before it put through the table. So the lever is
    ///      turnover: a busier week buys a bigger bonus, and a quiet one shrinks back toward the
    ///      base the day is opened with regardless.
    ///
    ///      NOT a break-even argument. There is no deterministic minimum a seat burns — place
    ///      4/10 and 5/9 pay true odds, so a whole field may legally play a fair board — and the
    ///      schedule does not pretend otherwise. What actually pays for the subsidy is the
    ///      remainder deleted out of every busted run, which no term here measures.
    function _boostBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, false);
    }

    /// @dev What the HIGH lane offers this window, drawn off the day's high budget with the same
    ///      split the main one uses. No floor and no fallback quote: the high budget is funded by
    ///      what high rollers actually burned, so a day that banked none has none, and there is
    ///      nothing to advertise on a day that never opened.
    function _highBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, true);
    }

    /// @dev One window's slice of its OWN day's budget. A day that has not opened yet has nothing
    ///      banked, so the schedule quotes what it WOULD draw — a pure function of days already
    ///      settled, so a day about to open quotes exactly what it will get.
    ///
    ///      A CUSTOM battle puts up no house money at all. Its pot is the bounties its entrants
    ///      posted plus whatever anyone donated onto it — the protocol's purse backs the windows
    ///      it schedules itself, not a table someone else opened.
    function _shareOf(Window memory w, bool high) private view returns (uint256) {
        if (w.bound >= _CUSTOM_SLOT_BASE) return 0;
        unchecked {
            uint256 slot = uint256(w.bound);
            uint24 day = uint24(slot / _BONUS_SLOTS_PER_DAY);
            uint256 packed = _boostBudget[day];
            uint256 budget;
            uint256 weight;
            if (packed != 0) {
                weight = packed >> _BUDGET_W_SHIFT;
                budget = high ? _highBudget[day] : packed & _BUDGET_MASK;
            } else {
                uint256 word = _dailyWordAt(day);
                if (word == 0) return 0;
                weight = _routineWeight(word);
                (uint256 m, uint256 h) = _drawBudgets(day);
                // The HIGH budget is whole and unsplit. The main one is quoted at the ladder half
                // it will be stored as, through the same helper the opening uses.
                if (high) budget = h;
                else (budget,) = _splitMainBudget(m);
            }
            // `slot % _BONUS_SLOTS_PER_DAY` names the period plus one — zero is the gap between
            // days — so the period this window shares on is one below it.
            return _windowShare(budget, weight, (slot % _BONUS_SLOTS_PER_DAY) - 1, w.tier);
        }
    }

    /// @dev Fold one settle batch's staked bankroll into its day. Unchecked: the figure only ever
    ///      sizes a later bonus, and no real table can approach a uint256.
    function _bookDay(uint24 day, uint256 staked, uint256 high) internal {
        unchecked {
            _dayStaked[day] += staked + (high << _DAY_HIGH_SHIFT);
        }
    }

    /// @notice What a day's action contributes to a later budget: `dayStaked * _BOOST_ACTION_BPS`.
    ///         Drawn from the HANDLE rather than from the realised result, so it does not move
    ///         with the dice and a lucky week cannot starve the next one. It measures no burn and
    ///         never has — it is a linear rate on what the seats put up.
    function _dayActionRate(uint24 day) internal view returns (uint256) {
        unchecked {
            return (uint256(uint128(_dayStaked[day])) * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
        }
    }

    /// @dev THE DAY'S RAW ALLOCATION: `_BASE_MAIN_BUDGET` plus `_BOOST_ACTION_BPS` of the average
    ///      daily action of the seven days before `day`. The base is ADDED, never a floor — a day
    ///      that banked real action is paid for it ON TOP of the base, not instead of it. Drawn
    ///      ONCE, when the day opens, so every window of it offers the same figure and a window
    ///      armed days later still pays what its own day advertised.
    ///
    ///      `mainBudget` here is the RAW main figure, BEFORE the progressive split. Nothing may
    ///      read it as a ladder without passing it through `_splitMainBudget` first. The high
    ///      budget is final as returned: only its standing forfeitures ever leave the lane.
    function _drawBudgets(uint24 day) internal view returns (uint256 mainBudget, uint256 highBudget) {
        unchecked {
            uint256 er;
            uint256 eh;
            for (uint256 i = 1; i <= _BOOST_ACTION_WINDOW_DAYS; ++i) {
                if (day < i) break;
                uint24 d = day - uint24(i);
                uint256 action = _dayStaked[d];
                uint256 high = action >> _DAY_HIGH_SHIFT;
                // The two lanes are rated the same and NEVER share an amount: what a high seat put
                // up is in the high half and taken back out of the total, so no wei of action can
                // feed both components.
                er += ((uint256(uint128(action)) - high) * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
                eh += (high * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
            }
            // AVERAGED OVER THE WINDOW, NEVER SUMMED. A budget is drawn EVERY day, off a window
            // that overlaps the six before it — so handing one day the whole week's figure would
            // let every unit of action fund seven budgets and put emission at seven times what
            // the rule intends. The divisor is the window itself, so widening the window changes
            // how smooth the figure is and nothing about its level.
            er /= _BOOST_ACTION_WINDOW_DAYS;
            eh /= _BOOST_ACTION_WINDOW_DAYS;

            // THE HIGH LANE'S COMPONENT SPLITS TWO WAYS: two parts in five to the main boost and
            // the other three to the lane that earned them. Floored on the main side, which puts
            // the one-wei split remainder with the high lane.
            uint256 fromHigh = (eh * _HIGH_MAIN_NUM) / _HIGH_MAIN_DEN;
            highBudget = eh - fromHigh;
            // The base rides the MAIN lane alone. Subsidising a high lane nobody played would
            // print house money against action that was never put through it.
            //
            // RAW, and the only place the raw figure exists. Both callers split it through
            // `_splitMainBudget` before anything reads it as a ladder.
            mainBudget = _BASE_MAIN_BUDGET + er + fromHigh;
        }
    }

    /// @dev THE SPLIT, and the one statement of it. Half the day's raw main allocation is the
    ///      ladder its seven windows share; the other half is banked in the progressive. Floored
    ///      on the ladder side, so the odd wei goes to the pool and the two ALWAYS sum back to the
    ///      raw figure.
    ///
    ///      Both callers go through here — the day that opens and stores the ladder, and the quote
    ///      a window gives before its day has opened — which is what stops a pre-open quote from
    ///      advertising twice what the ladder will actually hold.
    function _splitMainBudget(uint256 rawMain) internal pure returns (uint256 ladder, uint256 progressive) {
        unchecked {
            ladder = rawMain / 2;
            progressive = rawMain - ladder;
        }
    }

    /// @dev THE LADDER. In QUARTERS, drawn in THOUSANDTHS because the top rung is too rare to
    ///      name in hundredths, and to a mean of EXACTLY one:
    ///
    ///        76.8%   a quarter of the share      1 quarter    carries 19.2% of the budget
    ///        20.8%   the share itself            4            carries 20.8%
    ///         2.0%   TEN times it               40            carries 20.0%
    ///         0.4%   A HUNDRED times it        400            carries 40.0%
    ///
    ///      `768(1) + 208(4) + 20(40) + 4(400) = 4000` quarters over 1,000 draws.
    ///
    ///      Four rungs, each an order up from the last, and each carrying about a fifth of the
    ///      budget except the top, which carries twice that. Three windows in four pay a quarter
    ///      of their share; the hundred-times rung lands about once in every 250 windows, which
    ///      across a seven-window day is roughly once a month. The mean being exactly one is what
    ///      keeps a day's budget the thing actually spent IN EXPECTATION while no single window is
    ///      capped by it. Drawn off the word that SETTLES the table and keyed to the battle, so it
    ///      cannot be read while anyone can still enter.
    ///
    ///      THE REVEAL IS A CLIENT CONCERN, and needs nothing from here. The rung lands the
    ///      instant the table's VRF word does — after entry shuts, before any run is settled — and
    ///      everything it is drawn from is already public: `CrapsBonusArmed` carries the battle
    ///      key and the table index, `_wordAt` the word, `boostBudgetOf` the day's budget and
    ///      `_battleOf` the donations. So a front end spins its own wheel off the chain's own
    ///      inputs rather than paying for a view that restates them.
    /// @dev WHAT SIZE THE DAY'S HIGH LANE RUNS AT, off the day's own committed word and nothing
    ///      else. Nine days in ten it is ten times the ordinary seat; one in ten it is a hundred.
    ///
    ///      The hash is an EXTRACTOR, not a source: the entropy is the protocol's daily VRF word,
    ///      and the tag only keeps this draw from colliding with the others taken off the same
    ///      word. Nothing else may enter — not the timestamp, not the day number, not the caller,
    ///      not the head count — because the figure has to be knowable, and identical, from the
    ///      moment the word lands until the last of the day's seven windows has settled.
    ///
    ///      An undrawn word means the day HAS no lane. There is no fallback: a day that cannot
    ///      draw simply does not offer one, which is the same thing that happens to the windows.
    ///
    ///      Independent per day, so ten consecutive days carry no promise of a tail among them.
    function _highMultOf(uint256 word) internal pure returns (uint256) {
        if (word == 0) return 0;
        unchecked {
            return _hash2(word, HIGH_TAG) % 10 == 0 ? _HIGH_MULT_TAIL : _HIGH_MULT;
        }
    }

    function _boostMult(uint256 word, bytes32 key) internal pure returns (uint256) {
        unchecked {
            uint256 roll = _hash3(word, uint256(key), BOOST_TAG) % 1000;
            if (roll < 768) return 1;
            if (roll < 976) return 4;
            if (roll < 996) return 40;
            return 400;
        }
    }

    /// @dev How much of a window's boost a winner holding `held` standing may carry off. The
    ///      standing is the FROZEN one its slip recorded when it sat down, so nothing the winner
    ///      does after the dice can move it. At the floor the boost pays whole; below it the
    ///      winner takes one part in `floor - held`; a scoreless wallet takes none at all. What is
    ///      not taken is simply never minted.
    /// @dev Collapse a boost, in granules, onto the figure it is actually paid at.
    function _roundBoost(uint256 units) internal pure returns (uint256) {
        if (units <= _BOOST_ROUND_ABOVE) return units;
        unchecked {
            return ((units + _BOOST_ROUND_STEP / 2) / _BOOST_ROUND_STEP) * _BOOST_ROUND_STEP;
        }
    }

    function _boostShare(uint256 boostUnits, uint256 held) internal pure returns (uint256) {
        if (held >= _SYBIL_SCORE_FLOOR) return boostUnits;
        unchecked {
            return held == 0 ? 0 : boostUnits / (_SYBIL_SCORE_FLOOR - held);
        }
    }

    /// @dev The table index a slip settles on, whichever way it was bound.
    function _indexOf(uint256 slot) internal view returns (uint48 index) {
        index = _slotIndex[slot];
        if (index == 0) revert RngNotReady();
        unchecked {
            index -= 1;
        }
    }

    /// @dev Pay a battle the instant it finishes: the pot to the main winner, and a contested
    ///      lane's principal and boost to the best high roller. Reached from exactly one place —
    ///      the branch in `_scoreBattle` where the last seat scores — so it runs once by
    ///      construction and needs no latch of its own.
    ///
    ///      A pot of zero pays nobody: a friendly battle still ranks and still names its winner,
    ///      and a zero credit is a cross-contract call for no reason.
    function _payout(Window memory w, uint256 g, uint256 word) private {
        unchecked {
            uint256 slot = w.bound;
            uint256 entrants = g & _MASK32;
            // The main boost is shared by the finalization log and the payout. Its derivation
            // reads the day's budget and hashes the settling word, so compute it once here.
            uint256 boost = _boostUnits(w, word);
            bool scheduled = slot < _CUSTOM_SLOT_BASE;
            uint256 best = (g >> _BG_BEST_SHIFT) & _SC_BEST_MASK;
            (Craps.SlipStop stop,, uint256 peakFlip, uint256 endFlip) = _decodeBest(best);
            // THE SCORE, drawn once here and reused by everything downstream that reads a high
            // point: the finalization log, the progressive's rung and the record's candidate.
            // BOTH SIDES IN WHOLE FLIP — every scheduled bankroll is a whole-FLIP multiple of 300
            // and the scoreboard floors the peak the same way, so every cutoff on the schedule
            // lands on an exact figure and the flooring can only discard sub-FLIP dust.
            uint256 score = (peakFlip * _BPS_DENOMINATOR) / (uint256(w.bankroll) / 1 ether);
            // DONATED GRANULES AND THE WINNING SEAT, read once each: both the finalization log and
            // the payment below want them, and a battle word is one warm slot either way.
            // The pot this field pays out, seed and boost included. Every finished field carries
            // the whole pot: a window nobody else wanted is still a race, and what is on it is what
            // its winner takes.
            emit CrapsBattleFinalized(
                w.key,
                stop,
                uint64(uint32(g >> _BG_WINNER_SHIFT)),
                peakFlip,
                endFlip,
                score,
                (entrants * w.stakeUnits + boost + ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK)) * _BATTLE_STAKE_UNIT
            );
            // The winning seat is an index into the same own-then-day range the settle walk used,
            // so naming it takes the same mapping back.
            (uint256 dayBase, uint64 dayN) = _dayField(slot);
            uint64 ownN = uint64(entrants) - dayN;

            uint64 seat = uint64(uint32(g >> _BG_WINNER_SHIFT));
            uint256 winnerId = seat <= ownN ? (slot << 64) | seat : dayBase | (seat - ownN);
            uint256 winnerWord = _bets[winnerId];
            // The boost: this table's own pick from the band the window advertised, plus anything
            // donated on top of it. Nothing about either was stored.
            // DONATED GRANULES ARE NOT HOUSE MONEY. They were burned by a third party for this
            // field, so they are neither rationed by the winner's standing — which would delete
            // someone else's burn — nor run through the boost's rounding, which rounds to NEAREST
            // and would hand out FLIP nobody burned. Only the protocol's own subsidy does either.
            uint256 donated = (g >> _BG_SEED_SHIFT) & _BG_SEED_MASK;
            // HOUSE MONEY IS RATIONED BY STANDING, on the protocol's own windows only. A custom
            // battle's boost is donated, not seeded — nobody's loyalty spend is at stake — and a
            // creator who wants a standing requirement already set one at creation.
            //
            // WHAT THE STANDING DENIES IS NOT UNMINTED. It is the protocol's own subsidy, already
            // allocated to this window, so it is banked in the progressive — in GRANULES, at the
            // same rounding stage the payment lands on, which is what makes `paid + rolled` equal
            // the full-standing award to the wei.
            if (scheduled) {
                uint256 got = _roundBoost(_boostShare(boost, (winnerWord >> _BET_SCORE_SHIFT) & _BET_SCORE_MASK));
                _rollIn(w.key, _ROLL_SRC_MAIN | ((_roundBoost(boost) - got) * _BATTLE_STAKE_UNIT));
                boost = got;
            } else {
                boost = _roundBoost(boost);
            }
            // The bounties and the house money, and NOTHING else. What the field busted away is
            // deleted where it busted.
            uint256 pot = (w.stakeUnits * entrants + boost + donated) * _BATTLE_STAKE_UNIT;
            address winner = address(uint160(winnerWord));
            // ONLY the protocol's own admitted boost can pay in passes — split AFTER the standing
            // ration, so a pass can never carry what the ration denied. The bounties and donated
            // granules are player money and stay liquid whole, custom battles hold no house money
            // at all, and what banks as passes comes off the liquid pot to the wei.
            if (scheduled) {
                pot -= _splitAward(w.key, winner, _SPLIT_SRC_MAIN | (boost * _BATTLE_STAKE_UNIT));
            }
            if (pot != 0) {
                _creditFlip(winner, pot);
                emit CrapsBattlePaid(winnerId, w.key, winner, pot);
            }
            // THE LANE. Only a contested one pays here — a field of one settled its lane on that
            // seat's own run, and a field of none never had one.
            uint256 f = _highField[w.key];
            uint256 heads = uint32(f);
            if (heads >= 2) {
                seat = uint64((f >> _HF_WINNER_SHIFT) & _MASK32);
                uint256 hId = seat <= ownN ? (slot << 64) | seat : dayBase | (seat - ownN);
                uint256 hWord = _bets[hId];
                _highField[w.key] = f | _HF_DONE_BIT;
                // Entry is BINARY, so every seat in the lane posted the same `H - 1` bounties
                // beyond the one the main pot holds. Only the BOOST is rationed; player-funded
                // principal always pays out whole, and the rationed part is banked exactly as the
                // main lane's is.
                (uint256 lane, uint256 denied) = _laneBoostSplit(w, word, hWord);
                _rollIn(w.key, _ROLL_SRC_HIGH_CONTESTED | denied);
                // The extra bounties are the seats' own posted money and pay out whole; only the
                // admitted lane boost is protocol money, so only it can pay in passes.
                uint256 lanePot = heads * (w.highMult - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT + lane
                    - _splitAward(w.key, address(uint160(hWord)), _SPLIT_SRC_HIGH_CONTESTED | lane);
                if (lanePot != 0) {
                    address hWinner = address(uint160(hWord));
                    _creditFlip(hWinner, lanePot);
                    emit CrapsHighRollerPaid(hId, w.key, hWinner, lanePot, false);
                }
            }

            // THE PROGRESSIVE, LAST, and decided by the scoreboard that just closed and by nothing
            // else. Every rollover this field can produce — the ladder's and both lane shapes' —
            // is already in the pool by here, so the rung is measured against the balance the
            // whole field left rather than against a partial one.
            //
            // THEN THE RECORD, on the same finalized figures and once for the whole field. Never
            // per entrant: the candidate is the winner the comparator named, and the field is
            // closed by the time either of these can read it.
            //
            // BOTH ARE THE PROTOCOL'S OWN MONEY, so both are SCHEDULED-ONLY. A custom battle
            // plays the same game and races on the same comparator; what it does not do is fund
            // or draw on anything the protocol allocates. The single scheduled branch below
            // carries that guard for the progressive, repeat-victory stamp and record alike.
            // `peakFlip` is zero for a bust in either product, so the goal gate needs no restating.
            //
            // THE BIGGEST DICE RUN is the FIFTH category of the record `Coinflip` already owns,
            // not a pool of its own: nothing here funds a record pool, adds craps action, or
            // touches the four existing kinds. A 100x high point has necessarily crossed the
            // scheduled target, so the floor does the whole eligibility test. Below it NOTHING is
            // called — a field that never got near a record does not pay for a cross-contract
            // read to be told so — and `Coinflip` logs the claim it makes.
            //
            // A ROUTINE GOAL VICTORY IS REMEMBERED FOR THIS DAY'S EVENT. Only the main bounty
            // winner reaches here, which is the whole of "won the field" — reaching Goal behind
            // somebody else qualifies nobody.
            if (scheduled) {
                _noteRoutineVictory(slot, stop, winner);
                _payProgressive(w, peakFlip, score, winnerId, winnerWord, winner);
                if (score >= _DICE_RUN_RECORD_FLOOR) {
                    ICoinflipStake(ContractAddresses.COINFLIP).armDiceRunRecord(winner, score);
                }
            }
        }
    }

    /// @dev Bank protocol money a winner's standing would not admit. Zero is the common case and
    ///      costs nothing but the branch — a full-standing field never reaches the write.
    function _rollIn(bytes32 key, uint256 taggedAmount) internal {
        uint256 amount = taggedAmount & _SPLIT_GROSS_MASK;
        if (amount == 0) return;
        unchecked {
            uint256 pool = _progressive + amount;
            _progressive = pool;
            emit CrapsProgressiveRolled(key, uint8(taggedAmount >> 248), amount, pool);
        }
    }

    /// @dev Remember a ROUTINE field's GOAL victory against the day it happened on, so that day's
    ///      EVENT can double its progressive rung. Called from `_payout` for every finalized
    ///      SCHEDULED field with that field's own winner.
    ///
    ///      WRITTEN ON THE VICTORY, NOT ON THE AWARD: an earlier win qualifies the day whether or
    ///      not its own run cleared a progressive cutoff, and the award returns early on a short
    ///      score. Only ROUTINE windows write, which is what stops the event qualifying itself,
    ///      and only a Goal counts — a bust that ran high is still a bust.
    function _noteRoutineVictory(uint256 slot, Craps.SlipStop stop, address winner) internal {
        if (stop != Craps.SlipStop.Goal || _isEventSlot(slot)) return;
        unchecked {
            _routineGoalDay[winner] = slot / _BONUS_SLOTS_PER_DAY + 1;
        }
    }

    /// @dev Whether a SCHEDULED slot is its day's EVENT — the seventh and last window, and the
    ///      only one whose progressive rung can double. Slots run `day * 8 + period + 1`, so the
    ///      event's remainder is 7 and a routine window's is 1..6. Callers have already excluded
    ///      custom slots and the reserved day slot, whose remainder is 0.
    function _isEventSlot(uint256 slot) private pure returns (bool) {
        unchecked {
            return slot % _BONUS_SLOTS_PER_DAY == _BONUS_PERIODS_PER_DAY;
        }
    }

    /// @dev `floor(pool * bps / 10_000)` that CANNOT overflow, whatever the pool comes to hold.
    ///      Dividing at the denominator FIRST bounds the multiplication by the result — which is
    ///      at most the pool itself — where a bare `pool * bps` would wrap silently inside an
    ///      unchecked block at the 80% rung.
    ///
    ///      EXACT, not an approximation: write `pool = 10_000q + r`. Then
    ///      `floor(pool * bps / 10_000)` is `q * bps + floor(r * bps / 10_000)`, which is
    ///      term-for-term what this returns. Floor semantics are preserved at every rung.
    function _poolShare(uint256 pool, uint256 bps) internal pure returns (uint256) {
        unchecked {
            return (pool / _BPS_DENOMINATOR) * bps + ((pool % _BPS_DENOMINATOR) * bps) / _BPS_DENOMINATOR;
        }
    }

    /// @dev THE PROGRESSIVE AWARD, and the whole of it. Reached once per finalized SCHEDULED
    ///      field, from `_payout`'s single scheduled branch, so it cannot pay twice however the
    ///      settlement batches were cut and a custom field can never reach the pool.
    ///
    ///      IT ADDS NO RANDOMNESS. The recipient is the winner the ordinary comparator already
    ///      named; the qualification is that winner's HIGH POINT against its window's target; and
    ///      the amount is a fixed share of the live pool, chosen by the rung and by whether this
    ///      is the day's event. Nothing is re-run and no runner-up is ever considered.
    ///
    ///      A BUST NEVER QUALIFIES, however high it got: its `peakFlip` is zero, which is below
    ///      every cutoff. A custom battle neither draws on the pool nor funds it and is excluded
    ///      by the caller before this helper is reached.
    /// @param peakFlip The finalized winner's HIGH POINT in whole FLIP, straight off the
    ///        scoreboard the field just closed. Nothing is re-run to obtain it.
    /// @param score That high point over the run's own starting bankroll, in basis points — the
    ///        same figure the finalization log carries, computed once by the caller.
    function _payProgressive(
        Window memory w,
        uint256 peakFlip,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord,
        address winner
    ) internal {
        unchecked {
            // RARE FIRST, and it OVERRIDES. The rare cutoff is above the common cutoff, so a run
            // that clears it has cleared both — and takes the rare rung alone,
            // never both. Both cutoffs are INCLUSIVE.
            uint256 pool = _progressive;
            bool rare = score >= _PROG_RARE;
            // THE RUNG, COUNTED IN DOUBLINGS of the routine common share, because that is what
            // the schedule actually is: RARE is worth one doubling, the day's EVENT two more, and
            // a repeat victory at the event one further. So `500 << shift` is the whole table —
            // 500/1,000 routine, 2,000/4,000 event, 4,000/8,000 event doubled — and the four
            // named rungs below it are the same four figures written out.
            uint256 shift;
            if (rare) shift = _PROG_RARE_DOUBLINGS;
            else if (score < _PROG_COMMON) return;
            if (_isEventSlot(w.bound)) {
                shift += _PROG_EVENT_DOUBLINGS;
                // THE REPEAT DOUBLE, on the EVENT alone. Its state is read at RESOLUTION time: a
                // routine field that has not been finalized yet has qualified nobody, so an event
                // cranked ahead of the routine victory does not double. One earlier victory is
                // enough and a second cannot stack — this is a doubling, not a count — and the
                // event cannot qualify itself because only routine windows ever write the map.
                if (_routineGoalDay[winner] == uint256(w.bound) / _BONUS_SLOTS_PER_DAY + 1) ++shift;
            }
            uint256 bps = _PROG_ROUTINE_COMMON_BPS << shift;
            uint256 candidate = _poolShare(pool, bps);
            if (candidate == 0) return;
            // THE CANDIDATE IS ALREADY IN THE POOL, so the standing curve applies to it directly
            // and only the credit is deducted. What the standing denies is not added back — it
            // never left.
            uint256 paid = _boostShare(candidate, (winnerWord >> _BET_SCORE_SHIFT) & _BET_SCORE_MASK);
            // The WHOLE gross award leaves the pool, pass slice included — a pass is this award
            // paying in a different shape, and leaving its value behind would count it twice.
            pool -= paid;
            _progressive = pool;
            emit CrapsProgressivePaid(
                winnerId, w.key, winner, rare, uint16(bps), peakFlip, score, candidate, paid, pool
            );
            // State first, credit second. A scoreless winner takes nothing, and a call for nothing
            // is a call not worth making.
            paid -= _splitAward(w.key, winner, _SPLIT_SRC_PROGRESSIVE | paid);
            if (paid != 0) _creditFlip(winner, paid);
        }
    }

    function _betOf(uint256 betId) internal view returns (Bet memory bet) {
        uint256 header = _bets[betId];
        bet.player = address(uint160(header));
        bet.slot = uint64(betId >> 64);
        bet.seat = uint64(betId);
        bet.settled = _settledOf(betId);
        uint256 slot = betId >> 64;
        // A DAY TICKET holds no battle of its own — it plays all seven of its day's, and the
        // reserved slot it lives at names no window — so there is no single field whose finish
        // this could report and it stays false. Read those seven through their own slots.
        if (slot >= _CUSTOM_SLOT_BASE || slot % _BONUS_SLOTS_PER_DAY != 0) {
            uint256 board = _battles[_slotWindow(slot).key];
            uint256 field = board & _MASK32;
            bet.battleClaimed = field != 0 && ((board >> _BG_RESOLVED_SHIFT) & _MASK32) == field;
        }
        bet.chips = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        bet.standing = (header >> _BET_SCORE_SHIFT) & _BET_SCORE_MASK;
    }

    /// @notice The battle a bet is entered in — its slot's, since that is the only battle a slip
    ///         at that slot can be in.
    function _battleKeyOf(uint256 betId) internal view returns (bytes32) {
        if (address(uint160(_bets[betId])) == address(0)) revert NoSuchBet();
        return _slotWindow(betId >> 64).key;
    }

    /// @notice One battle's scoreboard, decoded. The winning stop and hand count mean something
    ///         once `finalized`.
    function _battleOf(bytes32 key) internal view returns (Battle memory info) {
        uint256 g = _battles[key];
        info.entrants = uint32(g);
        info.resolved = uint32(g >> _BG_RESOLVED_SHIFT);
        info.winnerId = uint64(uint32(g >> _BG_WINNER_SHIFT));
        info.finalized = info.entrants != 0 && info.resolved == info.entrants;
        info.battleStake = ((g >> _BG_STAKE_SHIFT) & _BSTAKE_MAX) * _BATTLE_STAKE_UNIT;
        // DONATIONS ONLY. A window's own seed is a function of the day's word, and a key is a
        // hash — there is no day to recover here — so read the full figure from `bonusOpenState`
        // or `_bonusTermsFor`, both of which take the day and period.
        info.seed = ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK) * _BATTLE_STAKE_UNIT;
        info.pot = info.battleStake * info.entrants + info.seed;
        if (info.finalized) {
            (Craps.SlipStop stop, uint256 hands, uint256 peakFlip, uint256 endFlip) =
                _decodeBest((g >> _BG_BEST_SHIFT) & _SC_BEST_MASK);
            info.winningStop = stop;
            info.winningHands = uint16(hands);
            info.winningPeak = peakFlip;
            info.winningEnd = endFlip;
        }
    }

    /// @notice The terms a bonus battle armed in `period` of `day` carries — derivable from the
    ///         day's word alone, so a front end can publish the whole day's timetable the moment
    ///         that word lands, including windows nobody has armed yet. Zero bankroll means that
    ///         day has no word and nothing is scheduled.
    function _bonusTermsFor(uint24 day, uint256 period)
        internal
        view
        returns (
            uint128 bankroll,
            uint128 goal,
            uint256 boardStake,
            uint256 battleStake,
            uint256 boostQuote,
            uint256 minScore
        )
    {
        if (_dailyWordAt(day) == 0 || period >= _BONUS_PERIODS_PER_DAY) {
            return (0, 0, 0, 0, 0, 0);
        }
        Window memory w = _windowTerms(day, period);
        (bankroll, goal, boardStake) = (w.bankroll, w.goal, w.postedStake);
        battleStake = w.stakeUnits * _BATTLE_STAKE_UNIT;
        // The MOST this window can put up on top of the stakes, before any donation adds to it.
        // Every window is a lottery, so a ceiling is the honest single number; `_bonusBoostBand`
        // gives the spread and `boostOf` the figure once the table's word lands.
        boostQuote = _boostBase(w) * _BOOST_MAX_MULT;
        // Always zero: a bonus window admits anybody. Kept in the tuple because a client reads
        // the same shape for a custom battle, which may still set one.
        minScore = (w.terms >> _TERM_SCORE_SHIFT) & _BET_MINSCORE_MASK;
    }

    /// @notice What `betId` would settle to, if its table has rolled.
    /// @dev Exactly what a settlement will pay — same computation, not a second copy of it.
    function previewSettlement(uint256 betId) external view returns (uint256 won, uint256 paid) {
        uint256 header = _bets[betId];
        if (address(uint160(header)) == address(0)) revert NoSuchBet();
        // Through `_indexOf`, so a slip previews on the table its slot actually shut onto.
        uint256 word = _wordAt(_indexOf(betId >> 64));
        if (word == 0) revert RngNotReady();
        Window memory w = _slotWindow(betId >> 64);
        Settlement memory s = _settlementOf(betId, header, w, word);
        // The same scaling a settlement applies, and in the same place: after the rounding.
        unchecked {
            uint256 scale = header & _BET_HIGH_BIT != 0 ? w.highMult : 1;
            won = s.won * scale;
            paid = s.paid * scale;
            // `paid` is still the bare scaled payment here, so it doubles as the boon base.
            paid += _boonBonus((header >> _BET_BOON_SHIFT) & _BET_BOON_MASK, paid);
            // A SOLE high roller's extra bounties and its lane's boost ride this same run, so a
            // preview that left them out would under-quote the one seat they belong to. A
            // CONTESTED lane is paid to one of its seats when the field finishes, not returned by
            // a run, so it is no part of what this quotes.
            if (header & _BET_HIGH_BIT != 0 && uint32(_highField[w.key]) == 1) {
                (uint256 lane,) = _laneBoostSplit(w, word, header);
                paid += _ride(s.paid, (scale - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT + lane, w.bankroll);
            }
        }
    }
}
