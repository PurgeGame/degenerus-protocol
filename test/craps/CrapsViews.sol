// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {Craps} from "../../contracts/Craps.sol";
import {IJackpotBattleViews} from "./JackpotBattleViews.sol";
import {CrapsSeedViews} from "./CrapsSeedViews.sol";
import {CrapsPriceLib} from "../../contracts/libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {WalletTableLib} from "../../contracts/libraries/WalletTableLib.sol";

interface ICrapsWalletIdView {
    function walletIdOf(address player) external view returns (uint32);
}

/// @title The reader surface production no longer ships
/// @notice `CrapsBattle` keeps its whole reader surface internal: nothing on chain calls a craps
///         view, and the indexer rebuilds every one of them from the events, so shipping them
///         cost EIP-170 headroom for nobody. The suite still wants them, and it wants them under
///         the names it has always used — so they are restated here, once, over the same internals
///         production kept. Every signature below is byte-for-byte the one that used to be on the
///         contract, which is what lets the assertions that grade them stay untouched.
/// @dev Test-only. It is never deployed to a live chain, so its size is nobody's constraint.
contract CrapsViews is CrapsSeedViews, CrapsBattle {
    /// @dev Legacy score helper for harnesses. Production receives this score from the engine
    ///      in Settlement.rank and has no reason to compute it again.
    function _compositeOf(Settlement memory s) internal pure returns (uint256) {
        SlipResult memory r;
        r.bankrollOut = s.won * FLIP;
        r.peakBankroll = s.peak * FLIP;
        r.handsPlayed = s.handsPlayed;
        r.stop = s.stop;
        return _rankOf(r);
    }

    // Legacy field positions used only to inject ignored score bits in regression tests.
    uint256 internal constant _BET_SCORE_SHIFT = 190;
    uint256 internal constant _BET_SCORE_MASK = 0xFFFF;
    uint256 internal constant _AWARD_STANDING = 100;
    uint256 internal constant _SYBIL_SCORE_FLOOR = 12;
    uint256 internal constant _MAX_MIN_SCORE = 0xFFF;
    function entryPrice(address player, uint256 base) external view returns (uint256) { return _newcomer(_idOf(player)) ? base + base / 20 : base; }

    /// @dev Canonical Game wallet ID, or zero before registration.
    function _idOf(address player) internal view returns (uint32 id) {
        id = ICrapsWalletIdView(_GAME).walletIdOf(player);
    }

    /// @dev The account key of a stored bet owner ID (the Game's wallet table).
    function _ownerOfId(uint32 id) internal view returns (address) {
        return id == 0 ? address(0) : WalletTableLib.ownerOf(id);
    }

    /// @dev The RNG salt the table uses for `player`'s paid entries: the wallet ID when the Game
    ///      has one, else the address (engine probes on arbitrary players).
    function _saltOf(address player) internal view returns (uint256) {
        uint32 id = _idOf(player);
        return id != 0 ? id : uint256(uint160(player));
    }

    function walletIdOfPlayer(address player) external view returns (uint32) {
        return _idOf(player);
    }

    // ── Constants ───────────────────────────────────────────────────────────
    uint256 public constant MIN_BANKROLL_FLIP = _MIN_BANKROLL_FLIP;
    uint256 public constant MAX_BANKROLL_MULT = _MAX_BANKROLL_MULT;
    uint256 public constant MIN_BATTLE_GOAL_MULT = _MIN_BATTLE_GOAL_MULT;
    uint256 public constant MAX_GOAL_MULT = _MAX_GOAL_MULT;
    /// @dev The schedule's close offsets, as `CrapsBattle._currentBonusSlot` writes them: routine
    ///      closes every six hours plus the clock alignment, the opener 20 minutes in, and the last
    ///      window 20 minutes before the turnover.
    uint256 public constant BONUS_PERIOD = 6 hours;
    uint256 public constant BONUS_PERIODS_PER_DAY = _BONUS_PERIODS_PER_DAY;
    uint256 public constant BONUS_SLOTS_PER_DAY = _BONUS_SLOTS_PER_DAY;
    uint256 public constant CUSTOM_SLOT_BASE = _CUSTOM_SLOT_BASE;
    uint256 public constant BONUS_EVENT_CLOSE = 20 minutes;
    /// @dev The routine tiers' total buy-ins, as packed into `_bonusPreset`.
    uint256 public constant BONUS_SMALL_BANKROLL = 600;
    uint256 public constant BONUS_MED_BANKROLL = 1800;
    uint256 public constant BONUS_LARGE_BANKROLL = 4500;
    uint256 public constant BONUS_CHIPS = _BONUS_CHIPS;
    uint256 public constant BOOST_ACTION_BPS = _BOOST_ACTION_BPS;
    uint256 public constant BPS_DENOMINATOR = _BPS_DENOMINATOR;
    uint256 public constant BOOST_ACTION_WINDOW_DAYS = _BOOST_ACTION_WINDOW_DAYS;
    uint256 public constant BASE_MAIN_BUDGET = _BASE_MAIN_BUDGET;
    uint256 public constant HIGH_MAIN_NUM = _HIGH_MAIN_NUM;
    uint256 public constant HIGH_MAIN_DEN = _HIGH_MAIN_DEN;
    uint256 public constant BOOST_MAX_MULT = _BOOST_MAX_MULT;
    uint256 public constant MAX_MIN_SCORE = _MAX_MIN_SCORE;
    uint256 public constant MAX_SLIP_HANDS = _MAX_SLIP_HANDS;
    uint256 public constant BATTLE_STAKE_UNIT = _BATTLE_STAKE_UNIT;
    uint256 public constant SYBIL_SCORE_FLOOR = _SYBIL_SCORE_FLOOR;
    uint256 public constant MAX_ROLLS = _MAX_ROLLS;
    uint256 public constant SLIP_ROLL_BUDGET = _SLIP_ROLL_BUDGET;
    uint256 public constant SLIP_ROLL_CEILING = _SLIP_ROLL_BUDGET - 1 + _MAX_ROLLS;
    uint256 public constant ESC_HANDS = _ESC_HANDS;
    uint256 public constant ESC_FAST_FROM = _ESC_FAST_FROM;
    uint256 public constant ESC_CAP = _ESC_CAP;
    uint256 public constant SCHED_BANK_MULT = _SCHED_BANK_MULT;
    uint256 public constant SCHED_GOAL = _SCHED_GOAL;
    uint256 public constant DICE_RUN_RECORD_FLOOR = _DICE_RUN_RECORD_FLOOR;
    bytes32 public constant CRAPS_SEED_DOMAIN = _CRAPS_SEED_DOMAIN;
    uint256 public constant HIGH_MULT = CrapsPriceLib.HIGH_BASE;
    uint256 public constant HIGH_MULT_TAIL = CrapsPriceLib.HIGH_TAIL;
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
    ///      three bits a leg, board order, don't pass at bit 27 — the same word `setPreferredBoard`
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
        return enterBattle(0, slot, _pack(chips), multiple);
    }

    function enterBonusBattle(uint256 period, Craps.Bets calldata chips, uint16 multiple)
        external
        returns (uint256)
    {
        return enterBonusBattle(0, period, _pack(chips), multiple);
    }

    function enterBonusDay(Craps.Bets calldata chips, uint16 multiple) external returns (uint256) {
        return enterBonusDay(0, _pack(chips), multiple);
    }

    function amendSlip(uint256 betId, Craps.Bets calldata chips) external {
        amendSlip(0, betId, _pack(chips));
    }

    /// @dev Self-path overloads (account 0 = the caller) with the packed-board arity the suite has
    ///      always called; the account-taking doors are the production ABI.
    function enterBattle(uint64 slot, uint32 chips, uint16 multiple) external returns (uint256) {
        return enterBattle(0, slot, chips, multiple);
    }

    function enterBonusBattle(uint256 period, uint32 chips, uint16 multiple) external returns (uint256) {
        return enterBonusBattle(0, period, chips, multiple);
    }

    function enterBonusDay(uint32 chips, uint16 multiple) external returns (uint256) {
        return enterBonusDay(0, chips, multiple);
    }

    function amendSlip(uint256 betId, uint32 chips) external {
        amendSlip(0, betId, chips);
    }

    function applyCrapsPasses(uint24 startDay, uint8 count, bool high, uint32 chips) external {
        applyCrapsPasses(0, startDay, count, high, chips);
    }

    function buyFutureCrapsDays(uint24 startDay, uint8 count, bool high, uint32 chips) external {
        buyFutureCrapsDays(0, startDay, count, high, chips);
    }

    /// @dev The three-argument applicators the suite has always called — blank-board overloads of
    ///      the packed-board doors, the same shape as the entry overloads above.
    function applyCrapsPasses(uint24 startDay, uint8 count, bool high) external {
        applyCrapsPasses(0, startDay, count, high, 0);
    }

    function buyFutureCrapsDays(uint24 startDay, uint8 count, bool high) external {
        buyFutureCrapsDays(0, startDay, count, high, 0);
    }

    function rngCohortComplete(uint48 index) external view returns (bool) {
        return index < 2 && _rngSlotCursor[index] == _rngSlots[index].length;
    }

    // ── Table / RNG ─────────────────────────────────────────────────────────
    function currentIndex() external view returns (uint48) {
        return _writeBuffer();
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

    /// @dev Compact 72-bit slip plus the derived awarded bit at 72, for codec assertions.
    function betWordOf(uint256 betId) external view returns (uint256) {
        return _loadBet(betId);
    }

    /// @dev Overwrite a stored bet word. Test-only, and the ONLY way to grade a settlement with
    ///      and without a boon on the SAME run: seats are seeded individually, so two slips are
    ///      two different runs and could never be compared.
    function setBetWord(uint256 betId, uint256 word) external {
        _storeBet(betId, word);
    }

    /// @dev The craps boon riding a slip, one-hot as stored.
    function boonMaskOf(uint256 betId) external view returns (uint256) {
        return (_loadBet(betId) >> BET_BOON_SHIFT()) & BET_BOON_MASK();
    }

    function BET_CHIPS_SHIFT() external pure returns (uint256) {
        return _BET_CHIPS_SHIFT;
    }

    function BET_CHIPS_MASK() external pure returns (uint256) {
        return _BET_CHIPS_MASK;
    }

    function BET_BOON_SHIFT() public pure returns (uint256) {
        return _BET_BOON_SHIFT;
    }

    function BET_BOON_MASK() public pure returns (uint256) {
        return _BET_BOON_MASK;
    }

    function BOON_PAYOUT_BASE_CAP() external pure returns (uint256) {
        return _BOON_PAYOUT_BASE_CAP;
    }

    /// @dev The settlement bonus itself, so the cap and the three tiers can be graded exactly
    ///      rather than inferred from a random run's payout.
    function boonBonusOf(uint256 mask, uint256 basePaid) external pure returns (uint256) {
        return _boonBonus(mask, basePaid);
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
        return _slotIndexOf(slot);
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
            uint256 reserved
        )
    {
        (bankroll, goal, boardStake, battleStake, boostQuote) = _bonusTermsFor(day, period);
        reserved = 0; // Preserve the test fixtures' tuple shape; no score gate exists.
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
        uint256 w = _passCreditsById[_idOf(player)];
        return (w & _PASS_MAX, (w >> _PASS_HIGH_SHIFT) & _PASS_MAX);
    }

    /// @dev Overwrite a body's pass bank. Test-only. The constructor banks `_SEED_PASSES` normal
    ///      passes to sDGNRS and the Vault, which is production state every suite inherits — so a
    ///      test whose claim is about the FLIP leg of the funding ladder says here that the bank
    ///      is empty, rather than leaving the reader to wonder which leg actually paid.
    /// @dev Root of the ID-keyed pass word (passes, board, initialized bit).
    function passCreditsByIdSlot() external pure returns (uint256 slot) {
        assembly ("memory-safe") { slot := _passCreditsById.slot }
    }

    function setPassCredits(address player, uint32 normal, uint32 high) external {
        uint32 id = _idOf(player);
        require(id != 0, "setPassCredits: no wallet ID");
        _passCreditsById[id] = (_passCreditsById[id] & ~uint256(type(uint64).max))
            | uint256(normal) | (uint256(high) << _PASS_HIGH_SHIFT);
    }

    /// @dev The deployment seed, so a suite can state the figure rather than repeat the literal.
    function SEED_PASSES() external pure returns (uint256) {
        return _SEED_PASSES;
    }

    /// @dev THE SHIPPED AWARD SPLIT, driven directly, so the deterministic formula is gradable on
    ///      each of its boundaries without staging a field whose boost lands exactly there. The
    ///      tap packs the tag the way every payout site does.
    function splitAward(bytes32 key, address player, uint8 source, uint256 gross)
        external
        returns (uint256 banked)
    {
        return _splitAward(key, _idOf(player), (uint256(source) << 248) | gross);
    }

    /// @dev The award split's denominations and cap, stated once for the suites.
    function NORMAL_PASS_VALUE() external pure returns (uint256) {
        return _NORMAL_PASS_VALUE;
    }

    function HIGH_PASS_VALUE() external pure returns (uint256) {
        return _HIGH_PASS_VALUE;
    }

    function MAX_HIGH_PASSES_PER_AWARD() external pure returns (uint256) {
        return _MAX_HIGH_PASSES_PER_AWARD;
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
        return _loadDaySeat(uint256(day) * BONUS_SLOTS_PER_DAY, _idOf(player)) == 0 ? 0 : 1;
    }

    /// @dev The holder's day-ticket seat number, or zero — the raw stored value.
    function daySeatNumberOf(uint24 day, address player) external view returns (uint256) {
        return _loadDaySeat(uint256(day) * BONUS_SLOTS_PER_DAY, _idOf(player)) & _MASK32;
    }

    function daySeatNumberOfId(uint24 day, uint32 playerId) external view returns (uint256) {
        return _loadDaySeat(uint256(day) * BONUS_SLOTS_PER_DAY, playerId) & _MASK32;
    }

    function seatedIn(uint64 slot, address player) external view returns (bool) {
        uint32 id = _idOf(player);
        if (slot >= _CUSTOM_SLOT_BASE) return _bonusSeated[_slotWindow(slot).key][id];
        return _loadDaySeat(uint256(slot) & ~uint256(7), id) & (uint256(1) << (32 + (slot & 7))) != 0;
    }

    function seatedInId(uint64 slot, uint32 id) external view returns (bool) {
        if (slot >= _CUSTOM_SLOT_BASE) return _bonusSeated[_slotWindow(slot).key][id];
        return _loadDaySeat(uint256(slot) & ~uint256(7), id) & (uint256(1) << (32 + (slot & 7))) != 0;
    }

    function windowReservedOf(uint64 slot) external view returns (uint256 count, uint256 high) {
        bytes32 key = bytes32(uint256(slot));
        return (_battles[key] & _MASK32, uint32(_highField[key]));
    }

    function DAY_SEATED() external pure returns (uint256) {
        return 1;
    }

    /// @dev Whether the day-lane seat `player` holds on `day` is a HIGH one. The lane lives on the
    ///      ticket itself rather than in the day state, so it is read off the bet the day holds.
    ///      Bit 65 is period zero's flag, which every whole-day high ticket sets.
    function daySeatIsHigh(uint24 day, address player) external view returns (bool) {
        uint256 daySlot = uint256(day) * BONUS_SLOTS_PER_DAY;
        uint64 n = uint32(_dayTickets[daySlot]);
        uint32 id = _idOf(player);
        for (uint64 i = 1; i <= n; ++i) {
            uint256 w = _loadBet((daySlot << 64) | i);
            if (id != 0 && uint32(w) == id) return w & _BET_HIGH_BIT != 0;
        }
        return false;
    }

    /// @dev The seven per-period high flags of `player`'s day ticket, bit `p` for period `p`.
    function daySeatHighMaskOf(uint24 day, address player) external view returns (uint256) {
        uint256 daySlot = uint256(day) * BONUS_SLOTS_PER_DAY;
        uint256 seat = _loadDaySeat(daySlot, _idOf(player));
        if (seat == 0) return 0;
        return (_loadBet((daySlot << 64) | seat) >> _BET_HIGH_SHIFT)
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
        return 3 minutes;
    }

    /// @dev How far ahead of the day's turnover the last window shuts.
    function EVENT_LEAD() external pure returns (uint256) {
        return 20 minutes;
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
        return _dayStaked[day] >> _DAY_HIGH_SHIFT;
    }

    function highActionRateOf(uint24 day) external view returns (uint256) {
        return ((_dayStaked[day] >> _DAY_HIGH_SHIFT) * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
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

    /// @dev The scheduled format's HIGH-POINT cutoffs, as inclusive multiples of the run's own
    ///      starting bankroll — exactly the pair `_payProgressive` applies.
    function progressiveThresholds() external pure returns (uint256 common, uint256 rare) {
        return (_PROG_COMMON, _PROG_RARE);
    }

    /// @dev The comparator, restated: everything but the entrant's standing.
    function compositeOf(Settlement memory s) external pure returns (uint256) {
        return _compositeOf(s);
    }

    /// @dev A composite back into what it says, as `_payout` reads it.
    function decodeBest(uint256 best)
        external
        pure
        returns (Craps.SlipStop stop, uint256 hands, uint256 peakFlip, uint256 endFlip)
    {
        return _decodeBest(best);
    }

    /// @dev The escalator itself, so its boundaries and its ceiling are pinned on the shipped
    ///      function rather than on a run that happens to reach them.
    function escOf(uint256 hand) external pure returns (uint256) {
        return _escOf(hand);
    }

    /// @dev The whole settlement of a bet, high point included — what the paying path computes.
    function settlementOf(uint256 betId) external view returns (Settlement memory) {
        uint256 header = _loadBet(betId);
        uint256 slot = betId >> 64;
        return _settlementOf(betId, header, _slotWindow(slot), _wordAt(_indexOf(slot)));
    }

    /// @dev The table index a slip settles on, whichever way it was bound. Test-side: the
    ///      production contract has no reader for it since the preview moved here.
    function _indexOf(uint256 slot) internal view returns (uint48 index) {
        index = _slotIndexOf(slot);
        if (index == 0) revert RngNotReady();
        unchecked {
            index -= 1;
        }
    }

    /// @notice What `betId` would settle to, if its table has rolled.
    /// @dev Test helper mirroring `_resolve`'s arithmetic: the production contract ships no such
    ///      view. It returns the GROSS figure: for a sole high roller that is the value before
    ///      settlement banks day passes out of the lane's protocol share (`_splitAward`), so the
    ///      suite compares it against the pre-conversion total, not against what lands liquid.
    function previewSettlement(uint256 betId) external view returns (uint256 won, uint256 paid) {
        uint256 header = _loadBet(betId);
        if (uint32(header) == 0) revert NoSuchBet();
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
                uint256 lane = _laneBoost(w, word);
                paid += _ride(s.paid, (scale - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT + lane, w.bankroll);
            }
        }
    }



    function PROG_ROUTINE_COMMON_BPS() external pure returns (uint256) {
        return _PROG_ROUTINE_COMMON_BPS;
    }

    function PROG_ROUTINE_RARE_BPS() external pure returns (uint256) {
        return _PROG_ROUTINE_COMMON_BPS << _PROG_RARE_DOUBLINGS;
    }

    function PROG_RARE_DOUBLINGS() external pure returns (uint256) {
        return _PROG_RARE_DOUBLINGS;
    }

    /// @dev The exact share the contract takes of a pool at a rung, so a suite states the rung it
    ///      expects rather than restating the floor arithmetic beside it.
    function poolShareOf(uint256 pool, uint256 bps) external pure returns (uint256) {
        return _poolShare(pool, bps);
    }

    /// @dev The progressive award `_payout` makes to a finalized scheduled winner, driven
    ///      directly for a winner at the Game-funded award standing (a jackpot-slot seat).
    function payProgressiveAt(bytes32 key, address winner, uint256 peakFlip, uint256 score) external {
        Window memory w;
        w.key = key;
        _payProgressive(w, peakFlip, score, 0, uint256(_idOf(winner)) | (_AWARD_STANDING << _BET_SCORE_SHIFT));
    }


    /// @dev The composite's money component, clamp included.
    function wonComponentOf(uint256 won) external pure returns (uint256) {
        return _wonComponent(won);
    }

    /// @dev How far a slot's field has settled. Production has no such reader (mineFlip's craps stages
    ///      report their own progress); the suites grade batches by it.
    function bonusCursorOf(uint64 slot) external view returns (uint64) {
        return _bonusCursorOf(slot);
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

    /// @dev EXACTLY `n` SEATS, whatever they cost. Settlement takes a GAS ALLOWANCE, so a fixture
    ///      that wants a chunk of a known size cannot name one — but the meter is read after a seat
    ///      rather than before, so the smallest nonzero budget always completes one and stops. One
    ///      call per seat is therefore an exact count, and a statement about the budget rule rather
    ///      than a way around it.
    function resolveSeats(uint64 slot, uint64 n) external {
        for (uint64 i = 0; i < n; ++i) {
            _resolveSlotRange(slot, MineFlipGas.available(), 1);
        }
    }

    /// @dev Test-only settle door. Production settles every armed slot only through mineFlip's
    ///      craps read stage, which walks the read cohort in order and hands each field to
    ///      `resolveRngSlot` under the same admission rule as below. Fixtures that need one
    ///      specific field settled without walking the cohort call this instead.
    function settleGas(uint64 slot, uint256 allowance) external returns (MineFlipGas.Result memory) {
        return _settleField(slot, allowance);
    }

    function settleSlot(uint64 slot, uint64) external {
        _settleField(slot, MineFlipGas.available());
    }

    function _settleField(uint64 slot, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (allowance == 0) return result;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX + _WORK_TAIL_GAS)) return result;
        result = this.resolveRngSlot(slot, _resolverAllowance(MineFlipGas.remaining(meter)));
        MineFlipGas.finish(meter);
    }

    /// @dev Test-only arm door, so the suite can shut and bind one chosen window directly.
    ///      Production arms scheduled windows only in order, through the maintenance cursor
    ///      mineFlip drives.
    function armWindow(uint64 slot) external returns (uint48 index) {
        if (_isJackpotSlot(slot)) revert BonusStillRunning();
        (,, uint256 open) = _currentBonusSlot();
        if (slot >= open) revert BonusStillRunning();
        if (_slotIndexOf(slot) != 0) revert BonusPeriodSpent();
        Window memory w = _slotWindow(slot);
        if (_battles[w.key] == 0) revert BonusPeriodSpent();
        if (_boostBudget[uint24(slot / _BONUS_SLOTS_PER_DAY)] == 0) revert BonusPeriodSpent();
        index = _armSlot(slot, w);
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

    function highBaseOf(uint64 slot) external view returns (uint256) {
        return _highBase(_slotWindow(slot));
    }

    function highMultOfSlot(uint64 slot) external view returns (uint256) {
        return _slotWindow(slot).highMult;
    }

    /// @dev A slot's match key without owning a seat in it. `battleKeyOf` needs a bet, and a
    ///      fixture that only wants the scoreboard has no reason to place one.
    /// @dev The table index a slot shut onto — what a fixture needs to move the word under a
    ///      field it has already armed.
    function indexOfSlot(uint64 slot) external view returns (uint48) {
        return _indexOf(slot);
    }

    /// @dev The FLIP a seat's run pays when `slot`'s field settles, from the settlement engine
    ///      itself: the scaled run, its boon, and — for a lane's SOLE high rider — the ride on its
    ///      extra bounties and admitted lane boost. Unlike `previewSettlement` this prices a DAY
    ///      ticket too: a day ticket's own slot never shuts onto a table, so it is quoted on the
    ///      window that settles it. The harness bound is built on this figure.
    function settlementOn(uint256 betId, uint64 slot) external view returns (uint256 paid) {
        uint256 header = _loadBet(betId);
        if (uint32(header) == 0) return 0;
        uint256 word = _wordAt(_indexOf(slot));
        if (word == 0) revert RngNotReady();
        Window memory w = _slotWindow(slot);
        // A day ticket sits after the window's own seats: own count plus its day-local seat.
        if ((betId >> 64) != slot) {
            unchecked {
                uint256 dayN = uint32(_dayTickets[(slot / _BONUS_SLOTS_PER_DAY) * _BONUS_SLOTS_PER_DAY]);
                w.seat = uint64(w.entrants - dayN) + uint64(betId);
            }
        }
        Settlement memory s = _settlementOf(betId, header, w, word);
        // A day ticket stores seven high flags and the window's period picks its own.
        uint256 bit = _BET_HIGH_BIT;
        unchecked {
            if ((betId >> 64) != slot) bit <<= (slot % _BONUS_SLOTS_PER_DAY) - 1;
        }
        bool hi = header & bit != 0;
        unchecked {
            uint256 scale = hi ? w.highMult : 1;
            paid = s.paid * scale;
            paid += _boonBonus((header >> _BET_BOON_SHIFT) & _BET_BOON_MASK, paid);
            if (hi && uint32(_highField[w.key]) == 1) {
                uint256 lane = _roundBoost(_highBoostUnits(w, word)) * _BATTLE_STAKE_UNIT;
                paid += _ride(s.paid, (scale - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT + lane, w.bankroll);
            }
        }
    }

    /// @dev Where a slot's day tickets live — the day slot's bet-id base — and how many there
    ///      are. The resolve walk settles a window's own seats `1..ownN` at the slot and then the
    ///      day tickets `1..n` under this base. A custom battle carries no day field.
    function dayFieldOf(uint64 slot) external view returns (uint256 base, uint64 n) {
        if (slot >= _CUSTOM_SLOT_BASE) return (0, 0);
        unchecked {
            uint256 d = (uint256(slot) / _BONUS_SLOTS_PER_DAY) * _BONUS_SLOTS_PER_DAY;
            return (d << 64, uint32(_dayTickets[d]));
        }
    }

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
        return uint128(_dayStaked[day]);
    }

    /// @dev The live progressive pool, for the conservation invariants.
    function progressiveOf() external view returns (uint256) {
        return _progressive;
    }

    function dayActionRate(uint24 day) external view returns (uint256) {
        return _dayActionRate(day);
    }

    /// @dev The engine's own shooter-boost primitives, restated so the suite can grade the
    ///      schedule without duplicating the production table.
    function shooterBoostTerms(uint256 placed) external pure returns (uint256) {
        return _shooterBoostTerms(placed);
    }

    function survived(bytes32 seed, uint256 n, address player) external pure returns (bool) {
        return _survived(seed, n, uint256(uint160(player)));
    }

    function boostBudgetOf(uint24 day) external view returns (uint256) {
        return _boostBudget[day] & _BUDGET_MASK;
    }

    // ── Readers production no longer carries ────────────────────────────────
    /// @notice A placed bet slip, decoded — what `_betOf` returns. Its logical ID is
    ///         `(slot << 64) | seat`; scheduled records become unavailable after bank reuse.
    /// @param player        Who staked it: the account key of the stored owner wallet ID.
    /// @param playerId      The owner's wallet ID as the bet word stores it (bits 0-31).
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
    /// @dev The header is created at placement. Its chip slice may change through `amendSlip`
    ///      before close; settlement never writes the bet, and the slot's cursor carries its
    ///      settled mark.
    struct Bet {
        address player;
        uint32 playerId;
        uint64 slot;
        uint64 seat;
        bool settled;
        bool battleClaimed;
        uint256 chips;
    }

    /// @notice One battle's scoreboard, decoded — what `_battleOf` returns.
    /// @param entrants     Slips entered (and still in) the battle.
    /// @param resolved     Entrants whose runs have settled.
    /// @param winnerId     The winning seat within this slot; combine it with the slot for the bet id.
    /// @param finalized    Every entrant resolved: the scoreboard is the verdict.
    /// @param winningStop  The winning outcome class, meaningful once finalized.
    /// @param winningHands The winning hand count — meaningful once finalized, and only where the
    ///                     composite encodes it: a BUST, whose primary leads with its shooter
    ///                     count. A goal ranks on its high point alone and reports zero here.
    /// @param winningPeak  The winner's HIGH POINT in whole FLIP, once finalized.
    /// @param winningEnd   The winner's raw ENDING bankroll in whole FLIP, once finalized — what
    ///                     it was actually paid on, which a goal's peak may sit well above.
    /// @dev The high point AS A MULTIPLE is not restated here: a battle key is a hash, so this
    ///      reader cannot recover the starting bankroll to divide by. `CrapsBattleFinalized`
    ///      carries `winningScoreBps` for exactly that reason, and a caller holding the window's
    ///      terms divides `winningPeak` by them.
    /// @param battleStake  One entrant's stake (wei).
    /// @param seed         FLIP donated onto this battle by third parties (wei), via `donate`;
    ///                     zero if nobody has. Never the protocol's own boost — a window's boost
    ///                     is drawn from the word that settles it and read through `boostOf`.
    ///                     Every field that forms pays it out — there is no head count below
    ///                     which it falls back out of the pot.
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

    /// @dev Whether a bet has settled. No slip carries a settled bit — its slot's cursor marks the
    ///      whole field at once, and an id's low half is its place in that field.
    function _settledOf(uint256 betId) internal view returns (bool) {
        uint256 slot = betId >> 64;
        uint256 ordinal = uint64(betId);
        if (_loadBet(betId) >> _AWARD_UNITS_SHIFT != 0) {
            (, uint64 dayN) = _dayField(slot);
            ordinal += dayN;
        }
        return ordinal <= _bonusCursorOf(slot);
    }

    /// @notice The custom battle at `slot`: its match key, the table it shut onto (zero until it
    ///         does), and its packed definition. `terms` is handed back whole rather than spread
    ///         into eight returns — the layout is fixed by `CrapsBattleCreated` and a client
    ///         decodes it for nothing, where eight returns cost real code on a table with none
    ///         to spare.
    function _customBattleOf(uint64 slot) internal view returns (bytes32 battleKey, uint48 index, uint256 terms) {
        (Window memory w, uint256 c) = _customTerms(slot);
        uint48 stored = _slotIndexOf(slot);
        unchecked {
            if (stored != 0) index = stored - 1;
        }
        return (w.key, index, c);
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
        uint48 stored = _slotIndexOf(target);
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
    /// @dev `mid` is the ladder's mean and therefore this window's share of the day's budget
    ///      exactly — half for the event, the other half split across the six routine windows
    ///      by tier (`_windowShare`) — which is what makes a day's budget an EXPECTATION rather
    ///      than a cap: the realised total can land far above it or far below.
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

    /// @dev A stored composite back into what it says. `hands` is recoverable for a BUST, whose
    ///      primary leads with its shooter count, and reads zero for a goal, whose primary is its
    ///      high point alone. A bust's high point ranks it against other busts but DECODES AS
    ///      ZERO: the progressive, the record and the finalization log read a high point only
    ///      for a goal, whatever a bust once held.
    function _decodeBest(uint256 best)
        internal
        pure
        returns (Craps.SlipStop stop, uint256 hands, uint256 peakFlip, uint256 endFlip)
    {
        unchecked {
            uint256 primary = (best >> _SC_PRIMARY_SHIFT) & _SC_PRIMARY_MASK;
            endFlip = (best >> _SC_WON_SHIFT) & _SC_WON_MASK;
            if (best & _SC_GOAL_BIT == 0) {
                return (Craps.SlipStop.Bust, primary >> _SC_BUST_HANDS_SHIFT, 0, endFlip);
            }
            return (Craps.SlipStop.Goal, 0, primary, endFlip);
        }
    }

    function _boostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            // Multiplied in WEI and only then cut to granules. Flooring the base first would
            // round a small window's whole boost away — a thin day funds well under one granule
            // per window, and it is the top rungs that make such a window pay at all.
            return (_boostBase(w) * _boostMult(word, w.bound)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    /// @notice What a day's action contributes to a later budget: `dayStaked * _BOOST_ACTION_BPS / _BPS_DENOMINATOR`.
    ///         Drawn from the HANDLE rather than from the realised result, so it does not move
    ///         with the dice and a lucky week cannot starve the next one. It measures no burn and
    ///         never has — it is a linear rate on what the seats put up.
    function _dayActionRate(uint24 day) internal view returns (uint256) {
        unchecked {
            return (uint256(uint128(_dayStaked[day])) * _BOOST_ACTION_BPS) / _BPS_DENOMINATOR;
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
    ///      the amount is a fixed share of the live pool, chosen by the rung. Every scheduled
    ///      window, the jackpot slot included, pays on the same two rungs: 5% of the pool at a
    ///      25x high point, 10% at 120x. Nothing is re-run and no runner-up is ever considered.
    ///
    ///      A BUST NEVER QUALIFIES, however high it got: its `peakFlip` decodes as zero, which is
    ///      below every cutoff. A custom battle neither draws on the pool nor funds it and is excluded
    ///      by the caller before this helper is reached.
    /// @param w The window the finalized winner played.
    /// @param peakFlip The finalized winner's HIGH POINT in whole FLIP, straight off the
    ///        scoreboard the field just closed. Nothing is re-run to obtain it.
    /// @param score That high point over the run's own starting bankroll, in basis points — the
    ///        same figure the finalization log carries, computed once by the caller.
    /// @param winnerId The winner's bet id, logged with the payout.
    /// @param winnerWord The winner's settled bet header, carrying its owner wallet ID (bits 0-31),
    ///        which the payout is credited to.
    ///      Reached by self-call through the table's delegate fallback, so the suite installs
    ///      `JackpotBattleViews` at `JACKPOT_BATTLE` before calling it.
    function _payProgressive(Window memory w, uint256 peakFlip, uint256 score, uint256 winnerId, uint256 winnerWord) internal {
        IJackpotBattleViews(address(this)).payProgressive(w, peakFlip, score, winnerId, winnerWord);
    }

    function _betOf(uint256 betId) internal view returns (Bet memory bet) {
        uint256 header = _loadBet(betId);
        bet.playerId = uint32(header);
        bet.player = _ownerOfId(bet.playerId);
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
    }

    /// @notice The battle a bet is entered in — its slot's, since that is the only battle a slip
    ///         at that slot can be in.
    function _battleKeyOf(uint256 betId) internal view returns (bytes32) {
        if (uint32(_loadBet(betId)) == 0) revert NoSuchBet();
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
            uint256 boostQuote
        )
    {
        if (_dailyWordAt(day) == 0 || period >= _BONUS_PERIODS_PER_DAY) {
            return (0, 0, 0, 0, 0);
        }
        Window memory w = _windowTerms(day, period);
        (bankroll, goal, boardStake) = (w.bankroll, w.goal, w.postedStake);
        battleStake = w.stakeUnits * _BATTLE_STAKE_UNIT;
        // The MOST this window can put up on top of the stakes, before any donation adds to it.
        // Every window is a lottery, so a ceiling is the honest single number; `_bonusBoostBand`
        // gives the spread and `boostOf` the figure once the table's word lands.
        boostQuote = _boostBase(w) * _BOOST_MAX_MULT;
    }
}
