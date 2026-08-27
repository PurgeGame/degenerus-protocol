// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsBattle} from "../../contracts/CrapsBattle.sol";

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
    uint256 public constant BOOST_ACTION_DIVISOR = _BOOST_ACTION_DIVISOR;
    uint256 public constant BOOST_BURN_SHARE_DIVISOR = _BOOST_BURN_SHARE_DIVISOR;
    uint256 public constant BOOST_BURN_WINDOW_DAYS = _BOOST_BURN_WINDOW_DAYS;
    uint256 public constant MIN_BOOST_BUDGET = _MIN_BOOST_BUDGET;
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

    /// @dev A day's ticket counts, packed: the total in the low 32 bits, the high-roller subset
    ///      above. One word, because a window folds both in when it shuts.
    function dayTicketsOf(uint24 day) external view returns (uint64) {
        return _dayTickets[uint256(day) * BONUS_SLOTS_PER_DAY];
    }

    /// @dev The packed day-state byte for one player on one day: seated, reserved, or nothing.
    function dayStateOf(uint24 day, address player) external view returns (uint256) {
        // `_daySlotOf` is private on the contract; the derivation is one multiply, so the view
        // restates it rather than asking for a visibility change on production code.
        return _daySeated[uint256(day) * BONUS_SLOTS_PER_DAY][player];
    }

    function VAULT_BOARD_OFF() external pure returns (uint32) {
        return _VAULT_BOARD_OFF;
    }

    function DAY_SEATED() external pure returns (uint256) {
        return _DAY_SEATED;
    }

    /// @dev Whether the day-lane seat `player` holds on `day` is a HIGH one. The lane lives on the
    ///      ticket itself rather than in the day state, so it is read off the bet the day holds.
    function daySeatIsHigh(uint24 day, address player) external view returns (bool) {
        uint256 daySlot = uint256(day) * BONUS_SLOTS_PER_DAY;
        uint64 n = uint32(_dayTickets[daySlot]);
        for (uint64 i = 1; i <= n; ++i) {
            uint256 w = _bets[(daySlot << 64) | i];
            if (address(uint160(w)) == player) return w & _BET_HIGH_BIT != 0;
        }
        return false;
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

    function highBurnOf(uint24 day) external view returns (uint256) {
        return _highStaked[day] / _BOOST_ACTION_DIVISOR;
    }

    function highBudgetOf(uint24 day) external view returns (uint256) {
        return _highBudget[day];
    }

    function drawBudgetsFor(uint24 day) external view returns (uint256 mainBudget, uint256 highBudget) {
        return _drawBudgets(day);
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

    // ── Day action and budget ───────────────────────────────────────────────
    function dayStaked(uint24 day) external view returns (uint256) {
        return _dayStaked[day];
    }

    function dayBurn(uint24 day) external view returns (uint256) {
        return _dayBurn(day);
    }

    function boostBudgetOf(uint24 day) external view returns (uint256) {
        return _boostBudget[day] & _BUDGET_MASK;
    }
}
