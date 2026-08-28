// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {Craps} from "../../contracts/Craps.sol";

/// @title The reader surface production no longer ships
/// @notice `CrapsBattle` keeps its whole reader surface internal: nothing on chain calls a craps
///         view, and the indexer rebuilds every one of them from the events, so shipping them
///         cost EIP-170 headroom for nobody. The suite still wants them, and it wants them under
///         the names it has always used — so they are restated here, once, over the same internals
///         production kept. Every signature below is byte-for-byte the one that used to be on the
///         contract, which is what lets the assertions that grade them stay untouched.
/// @dev Test-only. It is never deployed to a live chain, so its size is nobody's constraint.
contract CrapsViews is CrapsBattle {
    // ── Constants ───────────────────────────────────────────────────────────
    uint256 public constant MIN_BANKROLL_FLIP = _MIN_BANKROLL_FLIP;
    uint256 public constant MAX_BANKROLL_MULT = _MAX_BANKROLL_MULT;
    uint256 public constant MIN_BATTLE_GOAL_MULT = _MIN_BATTLE_GOAL_MULT;
    uint256 public constant MAX_GOAL_MULT = _MAX_GOAL_MULT;
    uint256 public constant BONUS_PERIOD = _BONUS_PERIOD;
    uint256 public constant BONUS_PERIODS_PER_DAY = _BONUS_PERIODS_PER_DAY;
    uint256 public constant BONUS_SLOTS_PER_DAY = _BONUS_SLOTS_PER_DAY;
    uint256 public constant BONUS_EVENT_CLOSE = _BONUS_EVENT_CLOSE;
    uint256 public constant BONUS_SMALL_BANKROLL = _BONUS_SMALL_BANKROLL;
    uint256 public constant BONUS_MED_BANKROLL = _BONUS_MED_BANKROLL;
    uint256 public constant BONUS_LARGE_BANKROLL = _BONUS_LARGE_BANKROLL;
    uint256 public constant BONUS_CHIPS = _BONUS_CHIPS;
    uint256 public constant BOOST_ACTION_BPS = _BOOST_ACTION_BPS;
    uint256 public constant BPS_DENOMINATOR = _BPS_DENOMINATOR;
    uint256 public constant BOOST_ACTION_WINDOW_DAYS = _BOOST_ACTION_WINDOW_DAYS;
    uint256 public constant BASE_MAIN_BUDGET = _BASE_MAIN_BUDGET;
    uint256 public constant HIGH_MAIN_NUM = _HIGH_MAIN_NUM;
    uint256 public constant HIGH_MAIN_DEN = _HIGH_MAIN_DEN;
    uint256 public constant BOOST_BLANK_CHANCE = _BOOST_BLANK_CHANCE;
    uint256 public constant BOOST_PICKED_CHANCE = _BOOST_PICKED_CHANCE;
    uint256 public constant BOOST_MAX_MULT = _BOOST_MAX_MULT;
    uint256 public constant MAX_MIN_SCORE = _MAX_MIN_SCORE;
    uint256 public constant MAX_SLIP_HANDS = _MAX_SLIP_HANDS;
    uint256 public constant BATTLE_STAKE_UNIT = _BATTLE_STAKE_UNIT;
    uint256 public constant SYBIL_SCORE_FLOOR = _SYBIL_SCORE_FLOOR;
    uint256 public constant MAX_ROLLS = _MAX_ROLLS;
    uint256 public constant SLIP_ROLL_BUDGET = _SLIP_ROLL_BUDGET;
    uint256 public constant ESC_HANDS = _ESC_HANDS;
    bytes32 public constant CRAPS_SEED_DOMAIN = _CRAPS_SEED_DOMAIN;
    uint256 public constant HIGH_MULT = _HIGH_MULT;
    uint256 public constant HIGH_MULT_TAIL = _HIGH_MULT_TAIL;
    uint256 public constant MAX_HIGH_MULT = _MAX_HIGH_MULT;

    /// @dev Three the production table stopped exposing. `stakeFor` alone cost 276 bytes of
    ///      EIP-170 as an external — its wrapper ABI-decodes a ten-field struct — and nothing on
    ///      chain called any of them: the indexer rebuilds `battleCreator` from
    ///      `BattleCreatorSet`, and `GAME` is a compile-time constant anyone can read off the
    ///      source. The suite still wants them under the names it has always used.
    function GAME() external pure returns (address) {
        return _GAME;
    }

    function battleCreator(address account) external view returns (bool) {
        return _battleCreator[account];
    }

    function stakeFor(Craps.Bets memory b) external pure returns (uint256) {
        return _stakeFor(b);
    }

    /// @dev THE STRUCT-SHAPED DOORS the shipped table stopped taking. Chips now go in packed —
    ///      three bits a leg, board order, don't pass at bit 27 — the same word `setVaultBoard`
    ///      has always taken, the same word a bet is STORED as, and the same word
    ///      `CrapsSlipPlaced` has always emitted. Decoding a ten-field struct at four separate
    ///      doors cost 1,931 bytes of EIP-170 to arrive at that word anyway.
    ///
    ///      These are OVERLOADS, not replacements: different parameter types, so the packed doors
    ///      are still right there on the same contract and every assertion below still reads the
    ///      board the way it always has.
    function _pack(Craps.Bets calldata c) private pure returns (uint32) {
        return uint32(
            uint256(c.passLine) | (uint256(c.place4) << 3) | (uint256(c.place5) << 6) | (uint256(c.place6) << 9)
                | (uint256(c.place8) << 12) | (uint256(c.place9) << 15) | (uint256(c.place10) << 18)
                | (uint256(c.hard4) << 21) | (uint256(c.hard8) << 24) | (uint256(c.dontPass) << 27)
        );
    }

    function enterBattle(uint64 slot, Craps.Bets calldata chips, uint16 multiple) external returns (uint256) {
        return enterBattle(slot, _pack(chips), multiple);
    }

    function enterBonusBattle(uint256 period, Craps.Bets calldata chips, uint16 multiple)
        external
        returns (uint256)
    {
        return enterBonusBattle(period, _pack(chips), multiple);
    }

    function enterBonusDay(Craps.Bets calldata chips, uint16 multiple) external returns (uint256) {
        return enterBonusDay(_pack(chips), multiple);
    }

    function amendSlip(uint256 betId, Craps.Bets calldata chips) external {
        amendSlip(betId, _pack(chips));
    }

    /// @dev The three-argument applicators the suite has always called — blank-board overloads of
    ///      the packed-board doors, the same shape as the entry overloads above.
    function applyCrapsPasses(uint24 startDay, uint8 count, bool high) external {
        applyCrapsPasses(startDay, count, high, 0);
    }

    function buyFutureCrapsDays(uint24 startDay, uint8 count, bool high) external {
        buyFutureCrapsDays(startDay, count, high, 0);
    }

    // ── Table / RNG ─────────────────────────────────────────────────────────
    function currentIndex() external view returns (uint48) {
        return _currentIndex();
    }

    function currentDayIndex() external view returns (uint24) {
        return _currentDayIndex();
    }

    function wordAt(uint48 index) external view returns (uint256) {
        return _wordAt(index);
    }

    function dailyWordAt(uint24 day) external view returns (uint256) {
        return _dailyWordAt(day);
    }

    function seedFor(uint48 index) external view returns (bytes32) {
        return _seedFor(index);
    }

    // ── Bets and battles ────────────────────────────────────────────────────
    function betOf(uint256 betId) external view returns (Bet memory) {
        return _betOf(betId);
    }

    function battleKeyOf(uint256 betId) external view returns (bytes32) {
        return _battleKeyOf(betId);
    }

    function battleOf(bytes32 key) external view returns (Battle memory) {
        return _battleOf(key);
    }

    function customBattleCount() external view returns (uint64) {
        return _customBattleCount;
    }

    function customBattleOf(uint64 slot)
        external
        view
        returns (bytes32 battleKey, uint48 index, uint256 terms)
    {
        return _customBattleOf(slot);
    }

    // ── Bonus schedule ──────────────────────────────────────────────────────
    function currentBonusSlot() external view returns (uint24 day, uint256 period, uint256 slot) {
        return _currentBonusSlot();
    }

    function bonusDayOf() external view returns (uint24 openedDay, bool openableNow) {
        return _bonusDayOf();
    }

    /// @dev The table a slot shut onto, plus one — zero for a window still taking bets. The raw
    ///      field, so a fixture can tell "armed" from "not armed" without inferring it.
    function slotIndexOf(uint64 slot) external view returns (uint48) {
        return _slotIndex[slot];
    }

    function bonusWindowOf(uint256 period)
        external
        view
        returns (bytes32 battleKey, uint48 index, uint256 seed, bool joinable)
    {
        return _bonusWindowOf(period);
    }

    function bonusTermsFor(uint24 day, uint256 period)
        external
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
        return _bonusTermsFor(day, period);
    }

    function bonusBoostBand(uint24 day, uint256 period)
        external
        view
        returns (uint256 low, uint256 mid, uint256 high)
    {
        return _bonusBoostBand(day, period);
    }

    // ── The high-roller lane ────────────────────────────────────────────────
    /// @dev What size a day's high lane runs at, from that day's own committed word. Zero while
    ///      the word has not landed.
    function highMultForDay(uint24 day) external view returns (uint256) {
        return _highMultOf(_dailyWordAt(day));
    }

    /// @dev A player's uncommitted pass credits, both lanes. Storage-internal on the contract —
    ///      the whole reader surface is — so a suite reads them back through here.
    function passCreditsOf(address player) external view returns (uint256 normal, uint256 high) {
        uint256 w = _passCredits[player];
        return (w & _PASS_MAX, (w >> _PASS_HIGH_SHIFT) & _PASS_MAX);
    }

    /// @dev A day's ticket counts in the SHAPE the suite has always read them: the total in the
    ///      low 32 bits, a high-roller count above. The stored word now carries one high count
    ///      per period; the shape is reconstructed from period zero's, which equals the old
    ///      whole-day figure everywhere the old assertions look — a whole-day high ticket bumps
    ///      all seven counters alike, and only an upgrade can make them differ.
    function dayTicketsOf(uint24 day) external view returns (uint64) {
        uint256 t = _dayTickets[uint256(day) * BONUS_SLOTS_PER_DAY];
        return uint64(uint32(t)) | (uint64(uint32(t >> _DT_HIGH_SHIFT)) << 32);
    }

    /// @dev The stored ticket word, raw: total low, seven per-period high counts above.
    function dayTicketsWordOf(uint24 day) external view returns (uint256) {
        return _dayTickets[uint256(day) * BONUS_SLOTS_PER_DAY];
    }

    /// @dev One period's high-ticket count.
    function dayHighTicketsOf(uint24 day, uint256 period) external view returns (uint256) {
        return (_dayTickets[uint256(day) * BONUS_SLOTS_PER_DAY] >> (_DT_HIGH_SHIFT * (period + 1)))
            & _MASK32;
    }

    /// @dev The day state as the suite has always graded it: `DAY_SEATED()` for any claim, zero
    ///      for none. The stored value is the SEAT NUMBER now; `daySeatNumberOf` reads it raw.
    function dayStateOf(uint24 day, address player) external view returns (uint256) {
        // `_daySlotOf` is private on the contract; the derivation is one multiply, so the view
        // restates it rather than asking for a visibility change on production code.
        return _daySeated[uint256(day) * BONUS_SLOTS_PER_DAY][player] == 0 ? 0 : 1;
    }

    /// @dev The holder's day-ticket seat number, or zero — the raw stored value.
    function daySeatNumberOf(uint24 day, address player) external view returns (uint256) {
        return _daySeated[uint256(day) * BONUS_SLOTS_PER_DAY][player];
    }

    function VAULT_BOARD_OFF() external pure returns (uint32) {
        return _VAULT_BOARD_OFF;
    }

    function DAY_SEATED() external pure returns (uint256) {
        return 1;
    }

    /// @dev Whether the day-lane seat `player` holds on `day` is a HIGH one. The lane lives on the
    ///      ticket itself rather than in the day state, so it is read off the bet the day holds.
    ///      Bit 217 is period zero's flag, which every whole-day high ticket sets.
    function daySeatIsHigh(uint24 day, address player) external view returns (bool) {
        uint256 daySlot = uint256(day) * BONUS_SLOTS_PER_DAY;
        uint64 n = uint32(_dayTickets[daySlot]);
        for (uint64 i = 1; i <= n; ++i) {
            uint256 w = _bets[(daySlot << 64) | i];
            if (address(uint160(w)) == player) return w & _BET_HIGH_BIT != 0;
        }
        return false;
    }

    /// @dev The seven per-period high flags of `player`'s day ticket, bit `p` for period `p`.
    function daySeatHighMaskOf(uint24 day, address player) external view returns (uint256) {
        uint256 daySlot = uint256(day) * BONUS_SLOTS_PER_DAY;
        uint256 seat = _daySeated[daySlot][player];
        if (seat == 0) return 0;
        return (_bets[(daySlot << 64) | seat] >> _BET_HIGH_SHIFT)
            & (_BET_DAYHIGH_MASK >> _BET_HIGH_SHIFT);
    }

    function NORMAL_FUTURE_DAY_PRICE() external pure returns (uint256) {
        return _NORMAL_FUTURE_DAY_PRICE;
    }

    function HIGH_FUTURE_DAY_PRICE() external pure returns (uint256) {
        return _HIGH_FUTURE_DAY_PRICE;
    }

    /// @dev The offset that puts every routine close on a round clock time.
    function BONUS_CLOCK_ALIGN() external pure returns (uint256) {
        return _BONUS_CLOCK_ALIGN;
    }

    /// @dev How far ahead of the day's turnover the event window shuts.
    function EVENT_LEAD() external pure returns (uint256) {
        return _EVENT_LEAD;
    }

    function highMultOfWord(uint256 word) external pure returns (uint256) {
        return _highMultOf(word);
    }

    /// @dev The whole sideboard, decoded. `bankrollRider` is true for the one-seat lane that
    ///      settled on its own run; `done` covers both that and a claimed competitive lane.
    function highFieldOf(bytes32 key)
        external
        view
        returns (uint32 entrants, uint256 best, uint64 winnerSeat, bool bankrollRider, bool done)
    {
        uint256 f = _highField[key];
        entrants = uint32(f);
        best = (f >> _HF_SCORE_SHIFT) & _SC_BEST_MASK;
        winnerSeat = uint64((f >> _HF_WINNER_SHIFT) & _MASK32);
        bankrollRider = entrants == 1;
        done = f & _HF_DONE_BIT != 0;
    }

    function highStakedOf(uint24 day) external view returns (uint256) {
        return _highStaked[day];
    }

    function highActionRateOf(uint24 day) external view returns (uint256) {
        return (_highStaked[day] * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
    }

    function highBudgetOf(uint24 day) external view returns (uint256) {
        return _highBudget[day];
    }

    function drawBudgetsFor(uint24 day) external view returns (uint256 mainBudget, uint256 highBudget) {
        return _drawBudgets(day);
    }

    /// @dev THE SPLIT, restated. `_drawBudgets` returns the RAW main allocation; this is the one
    ///      helper that turns it into the ladder half the windows share and the half banked in the
    ///      progressive, and the suite grades both through it rather than re-deriving `/ 2`.
    function splitMainBudget(uint256 rawMain) external pure returns (uint256 ladder, uint256 progressive) {
        return _splitMainBudget(rawMain);
    }

    /// @dev The ladder half a day would open on, before it opens — what `boostBudgetOf` will hold.
    function ladderBudgetFor(uint24 day) external view returns (uint256 ladder) {
        (uint256 m,) = _drawBudgets(day);
        (ladder,) = _splitMainBudget(m);
    }

    /// @dev What a day would bank in the progressive when it opens.
    function progressiveContributionFor(uint24 day) external view returns (uint256 contribution) {
        (uint256 m,) = _drawBudgets(day);
        (, contribution) = _splitMainBudget(m);
    }

    /// @dev The nine formats' roll cutoffs, indexed the way `_payProgressive` indexes them.
    function progressiveThresholds(uint256 depth, uint256 goalMult)
        external
        pure
        returns (uint256 common, uint256 rare)
    {
        uint256 i = 16 * (3 * (depth == 2 ? 0 : (depth == 5 ? 1 : 2)) + (goalMult == 5 ? 0 : (goalMult == 10 ? 1 : 2)));
        return ((_PROG_COMMON >> i) & 0xFFFF, (_PROG_RARE >> i) & 0xFFFF);
    }

    function PROG_COMMON_DIV() external pure returns (uint256) {
        return _PROG_COMMON_DIV;
    }

    function PROG_RARE_DIV() external pure returns (uint256) {
        return _PROG_RARE_DIV;
    }

    /// @dev The composite's money component, clamp included.
    function wonComponentOf(uint256 won) external pure returns (uint256) {
        return _wonComponent(won);
    }

    /// @dev How far a slot's field has settled. Production dropped this reader when the crank
    ///      moved to `keepScheduled`'s own progress report; the suites still grade batches by it.
    function bonusCursorOf(uint64 slot) external view returns (uint64) {
        return _bonusCursor[slot];
    }

    /// @dev The scheduled cursor, raw. Zero until the first day opens.
    function keeperSlot() external view returns (uint64) {
        return _keeperSlot;
    }

    /// @dev Write straight into the pool, so a fixture can put a known balance on the table
    ///      without opening thirty days to accumulate one.
    function seedProgressive(uint256 amount) external {
        _progressive = amount;
    }

    /// @dev EXACTLY `n` SEATS, whatever they cost. `resolveSlot` takes a GAS ALLOWANCE now, so a
    ///      fixture that wants a chunk of a known size can no longer name one — but the meter is
    ///      read after a seat rather than before, so the smallest nonzero budget always completes
    ///      one and stops. One call per seat is therefore the exact count the old lane gave, and
    ///      it is a statement about the budget rule rather than a way around it.
    function resolveSeats(uint64 slot, uint64 n) external {
        for (uint64 i = 0; i < n; ++i) {
            resolveSlot(slot, 1);
        }
    }

    /// @dev The day's 4:2:1 routine denominator, and one window's slice of a given budget.
    function routineWeightOf(uint256 word) external pure returns (uint256) {
        return _routineWeight(word);
    }

    function tierPickAt(uint256 word, uint256 period) external pure returns (uint256) {
        return _tierPick(word, period);
    }

    function boostWeightOf(uint24 day) external view returns (uint256) {
        return _boostBudget[day] >> _BUDGET_W_SHIFT;
    }

    function highBoostUnitsOf(uint64 slot, uint256 word) external view returns (uint256) {
        return _highBoostUnits(_slotWindow(slot), word);
    }

    function boostBaseOf(uint64 slot) external view returns (uint256) {
        return _boostBase(_slotWindow(slot));
    }

    function boostShareOf(uint256 units, uint256 held) external pure returns (uint256) {
        return _boostShare(units, held);
    }

    function highBaseOf(uint64 slot) external view returns (uint256) {
        return _highBase(_slotWindow(slot));
    }

    function highMultOfSlot(uint64 slot) external view returns (uint256) {
        return _slotWindow(slot).highMult;
    }

    /// @dev A slot's match key without owning a seat in it. `battleKeyOf` needs a bet, and a
    ///      fixture that only wants the scoreboard has no reason to place one.
    function keyOfSlot(uint64 slot) external view returns (bytes32) {
        return _slotWindow(slot).key;
    }

    /// @dev The ten-chip ROUND a window plays. `bonusTermsFor` quotes the SEVEN chips an entrant
    ///      POSTS, which is a different number — and the depth every format rule reads is the
    ///      bankroll against the whole round.
    function roundOf(uint64 slot) external view returns (uint256) {
        return _slotWindow(slot).played;
    }

    // ── Day action and budget ───────────────────────────────────────────────
    function dayStaked(uint24 day) external view returns (uint256) {
        return _dayStaked[day];
    }

    function dayActionRate(uint24 day) external view returns (uint256) {
        return _dayActionRate(day);
    }

    /// @dev The engine's own shooter-boost primitives, restated so the suite can grade the
    ///      schedule and the eligibility draw without a second implementation of either.
    function shooterBoostTerms(bool blank, uint256 goalMult) external pure returns (uint256) {
        return _shooterBoostTerms(blank, goalMult);
    }

    function boostedShooter(bytes32 seed, uint256 n, address player, uint256 chance)
        external
        pure
        returns (bool)
    {
        return _boostedShooter(seed, n, player, chance);
    }

    function survived(bytes32 seed, uint256 n, address player) external pure returns (bool) {
        return _survived(seed, n, player);
    }

    function boostBudgetOf(uint24 day) external view returns (uint256) {
        return _boostBudget[day] & _BUDGET_MASK;
    }
}
