// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {CrapsPriceLib} from "./libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";
import {JackpotBattleFieldLib} from "./libraries/JackpotBattleFieldLib.sol";

interface IFlipCrapsComps {
    function creditCrapsComps(uint256 amount) external;
}

/// @notice Cold lifecycle and views for the daily jackpot battle, delegated by CrapsBattle.
/// @dev Deployed at `JACKPOT_BATTLE` and reached only by CrapsBattle's fallback delegatecall, so it
///      runs in the table's storage; the shared base appends to the table's layout and moves no
///      existing slot. The table itself runs all paid/day/awarded seats through its normal
///      budgeted resolver.
contract JackpotBattle is CrapsBattleStorage {
    error BadJackpotField();
    /// @dev The Game's FLIP-per-price unit: `price / _PRICE_COIN_UNIT` FLIP buys one ticket.
    uint256 private constant _PRICE_COIN_UNIT = 1000 ether;
    event JackpotBattleEntry(uint64 indexed slot, uint256 indexed betId, address indexed player, uint256 units, uint32 chips);

    /// @param pool The recorded prize pool the Added allocation is drawn from, in wei.
    /// @param level The Game's level at the request: it prices the pool in FLIP and picks the floor.
    function lockJackpotBattle(uint24 requestDay, uint256 pool, uint24 level) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (_activeJackpotSlot != 0) {
            JackpotRound storage prior = _jackpotRounds[_activeJackpotSlot];
            // A retry never changes the field, allocation or request identity.
            uint256 priorBoard = _battles[bytes32(uint256(_activeJackpotSlot))];
            if (prior.requestDay == requestDay || prior.word == 0
                || uint32(priorBoard >> _BG_RESOLVED_SHIFT) != uint32(priorBoard)) return;
        }
        uint256 day = _bonus == 0 ? 0 : _bonus - 1;
        uint64 slot = uint64(day * _BONUS_SLOTS_PER_DAY + _BONUS_PERIODS_PER_DAY);
        // Warm-up/skipped days have no paid field. Their free-only draw uses the unused
        // remainder-seven namespace, so lapsed reservations remain available to their refund walk.
        bool detached = _boostBudget[uint24(day)] == 0 || _slotIndex[slot] != 0;
        if (detached) slot = uint64((uint256(requestDay) - 1) * _BONUS_SLOTS_PER_DAY + 7);
        JackpotRound storage r = _jackpotRounds[slot];
        if (r.requestDay != 0) return;
        bytes32 key = bytes32(uint256(slot));
        uint256 g = _battles[key];
        if (!detached) {
            uint256 tickets = _dayTickets[day * _BONUS_SLOTS_PER_DAY];
            g += uint32(tickets);
            uint256 high = (tickets >> (_DT_HIGH_SHIFT * _BONUS_PERIODS_PER_DAY)) & _MASK32;
            if (high != 0) _highField[key] += high;
        }
        g |= (_JACKPOT_PRICE / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT;
        _battles[key] = g;
        _slotIndex[slot] = type(uint48).max;
        // Added is 0.5% of the pool at the level's ticket price, raised to its floor.
        r.added = CrapsPriceLib.jackpotAdded(pool * _PRICE_COIN_UNIT / (PriceLookupLib.priceForLevel(level) * 200), level);
        r.paidCount = uint32(g);
        uint256 highMult = _dailyWordAt(uint24(day));
        highMult = highMult == 0 ? 1 : _highMultOf(highMult);
        r.paidUnits = uint64(uint256(r.paidCount) + uint32(_highField[key]) * (highMult - 1));
        r.requestDay = requestDay;
        _activeJackpotSlot = slot;
        emit JackpotBattleLocked(slot, requestDay, r.added, r.paidCount);
    }

    /// @notice Initialize a resumable draw, returning its frozen word, cursor and units still wanted.
    /// @dev The total target grows with unrolled Added; paid volume does not create extra free units.
    function prepareJackpotBattle(uint24 level, uint256 word)
        external returns (uint256 drawWord, uint256 cursor, uint256 remaining)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        JackpotRound storage r = _prepare(level, word);
        return (r.drawWord, r.drawCursor, r.awardTarget - r.drawnUnits);
    }

    function _prepare(uint24 level, uint256 word) private returns (JackpotRound storage r) {
        r = _jackpotRounds[_activeJackpotSlot];
        if (r.requestDay == 0 || word == 0) revert BadJackpotField();
        // A resumed draw keeps the word and level frozen when it began.
        if (r.drawWord != 0) return r;
        uint256 roll = _hash2(word, JACKPOT_MULT_TAG) % 1_000;
        uint256 multiplier = roll < 900 ? 5_000 : roll < 990 ? 30_000 : roll < 999 ? 200_000 : 1_000_000;
        uint256 pool = (uint256(r.paidUnits) * _JACKPOT_PRICE + r.added) * multiplier / 10_000;
        // Awards come from unrolled Added alone; paid fees do not create them. At least 10,000 of
        // Added per award and 8,000 per paid unit leave the 0.5x roll 4,000 FLIP per unit, so
        // every bankroll rounds to at least 1,800.
        uint256 target = r.added / CrapsPriceLib.JACKPOT_AWARD_VALUE;
        if (target > 500) target = 500;
        r.awardTarget = uint32(target);
        r.totalPool = pool;
        r.multiplierBps = uint32(multiplier);
        r.level = level;
        r.drawWord = word;
    }

    /// @notice Collect at most `JackpotBattleFieldLib.MAX_CHUNK` units; the final chunk freezes terms
    ///         and enables paid settlement.
    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool last) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _append(field, cursor, last);
    }

    function _append(uint256[] calldata field, uint256 cursor, bool last) private {
        uint64 slot = _activeJackpotSlot;
        JackpotRound storage r = _jackpotRounds[slot];
        if (r.drawWord == 0 || r.word != 0 || field.length > JackpotBattleFieldLib.MAX_CHUNK) {
            revert BadJackpotField();
        }
        uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0
            : uint32(_dayTickets[(uint256(slot) / _BONUS_SLOTS_PER_DAY) * _BONUS_SLOTS_PER_DAY]);
        uint256 ownN = r.paidCount - dayN;
        uint256 units = r.drawnUnits;
        uint256 drawn = r.drawnCount;
        for (uint256 i; i < field.length && units < r.awardTarget; ++i) {
            uint256 entry = field[i];
            address player = address(uint160(entry));
            // A malformed or empty entry forfeits its award rather than halting the advance.
            if (entry >> JackpotBattleFieldLib.UNITS_SHIFT != 1 || player == address(0)) continue;
            (uint32 chips,) = CrapsPreferenceLib.decode(
                entry >> (JackpotBattleFieldLib.BOARD_SHIFT - CrapsPreferenceLib.SHIFT));
            uint256 id = (uint256(slot) << 64) | (ownN + ++drawn);
            _bets[id] = uint160(player) | (uint256(chips) << _BET_CHIPS_SHIFT)
                | (_AWARD_STANDING << _BET_SCORE_SHIFT) | (uint256(1) << _AWARD_UNITS_SHIFT);
            ++units;
            emit JackpotBattleEntry(slot, id, player, 1, chips);
        }
        r.drawnCount = uint32(drawn);
        r.drawnUnits = uint32(units);
        r.drawCursor = cursor;
        if (!last) return;

        uint256 totalUnits = uint256(r.paidUnits) + units;
        uint256 bankroll;
        uint256 bounty;
        if (totalUnits != 0) {
            uint256 perUnit = r.totalPool / totalUnits;
            bankroll = perUnit / 2 / _JACKPOT_BANKROLL_UNIT * _JACKPOT_BANKROLL_UNIT;
            uint256 maxBank = (uint256(type(uint24).max) / 10 / 6) * 6 * 50 ether;
            if (bankroll > maxBank) bankroll = maxBank;
            bounty = (perUnit - bankroll) / _BATTLE_STAKE_UNIT;
            if (bounty > bankroll / _BATTLE_STAKE_UNIT) bounty = bankroll / _BATTLE_STAKE_UNIT;
            if (bounty > _BSTAKE_MAX) bounty = _BSTAKE_MAX;
        }
        r.bankroll = uint128(bankroll);
        r.bountyUnits = uint32(bounty);
        r.potRemainder = r.totalPool - totalUnits * (bankroll + bounty * _BATTLE_STAKE_UNIT);
        bytes32 key = bytes32(uint256(slot));
        _battles[key] = ((_battles[key] + drawn) & ~(_BSTAKE_MAX << _BG_STAKE_SHIFT))
            | (bounty << _BG_STAKE_SHIFT);
        r.word = r.drawWord;
        emit JackpotBattleStarted(slot, r.level, drawn, units, r.word);
        _bookFees(slot, r, totalUnits * bankroll, uint32(_highField[key]));
    }

    /// @dev The paid fees are the battle's only craps action: the bankroll share of the fee money
    ///      the pool roll kept. Added and any roll gain never reach the day books or the comp lane.
    ///      Booked once, at seal, to the day the field played; the table books nothing for this slot.
    function _bookFees(uint64 slot, JackpotRound storage r, uint256 ranBankroll, uint256 highSeats) private {
        uint256 paidUnits = r.paidUnits;
        if (paidUnits == 0 || ranBankroll == 0) return;
        uint256 bps = r.multiplierBps < 10_000 ? r.multiplierBps : 10_000;
        uint256 staked = paidUnits * _JACKPOT_PRICE * bps / 10_000 * ranBankroll / r.totalPool;
        // High seats hold H units each: every paid unit beyond the seat count, plus the seats.
        uint256 high = staked * (paidUnits - r.paidCount + highSeats) / paidUnits;
        unchecked {
            _dayStaked[uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY)] += staked + (high << _DAY_HIGH_SHIFT);
        }
        uint256 earned = staked / 50;
        if (earned != 0) IFlipCrapsComps(ContractAddresses.COIN).creditCrapsComps(earned);
    }

    function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete) {
        slot = _activeJackpotSlot;
        JackpotRound storage r = _jackpotRounds[slot];
        added = r.added;
        started = r.word != 0;
        uint256 g = _battles[bytes32(uint256(slot))];
        complete = started && uint32(g >> _BG_RESOLVED_SHIFT) == uint32(g);
    }

    /// @notice UI/replay view. Added is the whole protocol allocation, including awarded bankrolls.
    function jackpotBattleOf(uint64 slot) external view returns (JackpotRound memory round, uint256 board, uint64 cursor) {
        return (_jackpotRounds[slot], _battles[bytes32(uint256(slot))], _bonusCursor[slot]);
    }

    /// @notice The fee is fixed; bankroll and pot are sized from the locked field after its pool roll.
    function jackpotEntryPrice() external pure returns (uint256) {
        return _JACKPOT_PRICE;
    }

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

    function upgradeReservedDay(uint24 day) external {
        if (day <= _currentDayIndex() || _dailyWordAt(day) != 0) revert DayNotReservable();
        uint256 daySlot = _daySlotOf(day);
        uint256 seat = _daySeated[daySlot][msg.sender] & _MASK32;
        if (seat == 0) revert NoSuchBet();
        uint256 betId = (daySlot << 64) | seat;
        uint256 header = _bets[betId];
        if (header & _BET_DAYHIGH_MASK != 0) revert NothingToUpgrade();
        _takeCredits(msg.sender, true, 1);
        _credit(msg.sender, false, 1);
        _bets[betId] = header | _BET_DAYHIGH_MASK;
        unchecked {
            _dayTickets[daySlot] += _DT_ALL_HIGH;
        }
        emit CrapsDayWindowsUpgraded(msg.sender, day, uint8(_BET_DAYHIGH_MASK >> _BET_HIGH_SHIFT), 0);
    }

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

    function _daySlotOf(uint256 day) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY;
        }
    }
}
