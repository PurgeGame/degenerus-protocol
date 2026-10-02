// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {CrapsPriceLib} from "./libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";
import {IReadCohortLifecycle} from "./CrapsBattle.sol";
import {JackpotBattleFieldLib} from "./libraries/JackpotBattleFieldLib.sol";

interface IGameCrapsPending {
    function setCrapsRngPending(uint48 index, bool pending) external;
}

interface IFlipCrapsComps {
    function creditCrapsComps(uint256 amount) external;
}

interface IHighReserveCredit {
    function creditFlip(address player, uint256 amount) external;
}

/// @notice Cold lifecycle and views for the daily jackpot battle, delegated by CrapsBattle.
/// @dev Deployed at `JACKPOT_BATTLE` and reached only by CrapsBattle's fallback delegatecall, so it
///      runs in the table's storage; the shared base appends to the table's layout and moves no
///      existing slot. The table itself runs all paid/day/awarded seats through its normal
///      budgeted resolver.
contract JackpotBattle is CrapsBattleStorage {
    error BadJackpotField();
    error OnlyTableSelf();
    /// @dev The Game's FLIP-per-price unit: `price / _PRICE_COIN_UNIT` FLIP buys one ticket.
    uint256 private constant _PRICE_COIN_UNIT = 1000 ether;
    /// @dev Conservative whole-run loss budget, using the same 12% calibration as the ordinary
    ///      action subsidy. Separate constants keep future boost tuning from changing high comps.
    uint256 private constant _HIGH_LOSS_BPS = 1200;
    uint256 private constant _HIGH_COMP_SHARE_BPS = 8000;
    event JackpotBattleEntry(uint64 indexed slot, uint256 indexed betId, address indexed player, uint256 units, uint32 chips);

    /// @dev Scheduled fields use the slot itself; custom fields commit to their exact terms.
    function _rngBattleKey(uint64 slot) private view returns (bytes32) {
        if (slot < _CUSTOM_SLOT_BASE) return bytes32(uint256(slot));
        uint256 c = _customBattle[slot];
        uint256 played = (c & _CB_PLAYED_MASK) * 1 ether;
        uint256 bank = uint128(played * ((c >> _CB_BANK_SHIFT) & _CB_BANK_MASK));
        uint256 goal = uint128(bank * ((c >> _CB_GOAL_SHIFT) & _CB_GOAL_MASK));
        uint256 terms = ((c >> _CB_STAKE_SHIFT) & _BSTAKE_MAX)
            | (((c >> _CB_HIGH_SHIFT) & _CB_HIGH_MASK) << _TERM_HIGH_SHIFT);
        return keccak256(abi.encode(BATTLE_TAG, uint48(slot), bank, goal, played, terms));
    }

    /// @notice Bounded keeper settlement of every armed field committed to a word.
    function keepRngCohort(uint48 index, uint64 budget) external returns (bool moved, bool settled) {
        (moved, settled,) = _keepRngCohort(index, budget);
    }

    /// @notice Settle the read cohort in commitment order using MineFlip work units.
    function keepRngCohortBudgeted(uint48 index, uint64 budget)
        external returns (bool moved, bool settled, uint64 charged)
    {
        return _keepRngCohort(index, budget);
    }

    function _keepRngCohort(uint48 index, uint64 budget)
        private returns (bool moved, bool settled, uint64 charged)
    {
        if (index > 1) revert BadJackpotField();
        budget = _readWorkAllowance(budget);
        uint48 physical = index;
        if (_rngPending[physical] == 0 || budget < _KEEP_HOP_UNITS || _readCrapsStage() != 5
            || _wordAt(index) == 0) return (false, false, 0);
        uint64[] storage slots = _rngSlots[physical];
        uint64 pos = _rngSlotCursor[physical];
        // One field per call; direct settlements may leave a bounded skip-only frontier.
        uint256 steps;
        while (pos < slots.length && steps++ < 16) {
            if (budget - charged < _KEEP_HOP_UNITS) break;
            charged += uint64(_KEEP_HOP_UNITS);
            uint64 slot = slots[pos];
            uint256 board = _battles[_rngBattleKey(slot)];
            if (uint32(board >> _BG_RESOLVED_SHIFT) == uint32(board)) { ++pos; moved = true; continue; }
            _rngSlotCursor[physical] = pos;
            uint64 beforeCursor = _bonusCursor[slot];
            charged += IReadCohortLifecycle(address(this)).resolveRngSlot(slot, budget - charged);
            uint256 afterBoard = _battles[_rngBattleKey(slot)];
            settled = _bonusCursor[slot] != beforeCursor || afterBoard != board;
            moved = moved || settled;
            board = afterBoard;
            if (uint32(board >> _BG_RESOLVED_SHIFT) == uint32(board)) ++pos;
            break;
        }
        _rngSlotCursor[physical] = pos;
    }

    function admitCustom(uint64 slot) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        for (uint256 i; i < 4; ++i) {
            if (_fundedCustomSlots[i] == 0) { _fundedCustomSlots[i] = slot; return; }
        }
        revert BadJackpotField();
    }

    function registerRngSlot(uint48 index, uint64 slot, bytes32 key) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        if (uint32(_battles[key]) == 0) return;
        if (index > 1) revert BadJackpotField();
        uint48 physical = index;
        if (_rngPending[physical] == 0) {
            uint64[] storage slots = _rngSlots[physical];
            assembly ("memory-safe") { sstore(slots.slot, 0) }
            _rngSlotCursor[physical] = 0;
        }
        _rngSlots[physical].push(slot);
        if (_rngPending[physical]++ == 0) {
            IGameCrapsPending(ContractAddresses.GAME).setCrapsRngPending(index, true);
        }
    }

    function completeRngSlot(uint64 slot, uint48 index) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        if (index > 1) revert BadJackpotField();
        uint64 pos = _rngSlotCursor[index];
        if (pos < _rngSlots[index].length && _rngSlots[index][pos] == slot) _rngSlotCursor[index] = pos + 1;
        if (--_rngPending[index] == 0) {
            IGameCrapsPending(ContractAddresses.GAME).setCrapsRngPending(index, false);
        }
        if (slot >= _CUSTOM_SLOT_BASE) {
            for (uint256 i; i < 4; ++i) {
                if (_fundedCustomSlots[i] == slot) { _fundedCustomSlots[i] = 0; return; }
            }
        }
    }

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
        uint256 contribution = r.added / _HIGH_RESERVE_DIVISOR;
        _highRollerReserve += contribution;
        emit HighRollerReserveFunded(slot, contribution, _highRollerReserve);
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
        // The reserve is funded before the lottery and receives none of its multiplier.
        // Award counts still use GROSS Added; high extras remain entirely fee-funded.
        uint256 mainAdded = r.added - r.added / _HIGH_RESERVE_DIVISOR;
        uint256 pool = (uint256(r.paidUnits) * _JACKPOT_PRICE + mainAdded) * multiplier / 10_000;
        // Awards come from unrolled Added alone; paid fees do not create them. At least 9,500 of
        // main-pool Added per award (after the 5% reserve) and 8,000 per paid unit leave the 0.5x
        // roll at least 4,000 FLIP per unit, so every bankroll rounds to at least 1,800.
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
                | (uint256(1) << _AWARD_UNITS_SHIFT);
            ++units;
            emit JackpotBattleEntry(slot, id, player, 1, chips);
        }
        r.drawnCount = uint32(drawn);
        r.drawnUnits = uint32(units);
        r.drawCursor = cursor;
        if (!last) return;

        // Every paid seat buys ONE place in the Added-funded main battle. Its extra high
        // units form their own fee-only bankroll/bounty allocation under the same fair roll.
        uint256 totalUnits = uint256(r.paidCount) + units;
        uint256 highPool = (uint256(r.paidUnits) - r.paidCount) * _JACKPOT_PRICE * r.multiplierBps / 10_000;
        uint256 mainPool = r.totalPool - highPool;
        uint256 bankroll;
        uint256 bounty;
        if (totalUnits != 0) {
            uint256 perUnit = mainPool / totalUnits;
            bankroll = perUnit / 2 / _JACKPOT_BANKROLL_UNIT * _JACKPOT_BANKROLL_UNIT;
            uint256 maxBank = (uint256(type(uint24).max) / 10 / 6) * 6 * 50 ether;
            if (bankroll > maxBank) bankroll = maxBank;
            bounty = (perUnit - bankroll) / _BATTLE_STAKE_UNIT;
            if (bounty > bankroll / _BATTLE_STAKE_UNIT) bounty = bankroll / _BATTLE_STAKE_UNIT;
            if (bounty > _BSTAKE_MAX) bounty = _BSTAKE_MAX;
        }
        r.bankroll = uint128(bankroll);
        r.bountyUnits = uint32(bounty);
        r.potRemainder = mainPool - totalUnits * (bankroll + bounty * _BATTLE_STAKE_UNIT);
        bytes32 key = bytes32(uint256(slot));
        _battles[key] = ((_battles[key] + drawn) & ~(_BSTAKE_MAX << _BG_STAKE_SHIFT))
            | (bounty << _BG_STAKE_SHIFT);
        r.word = r.drawWord;
        emit JackpotBattleStarted(slot, r.level, drawn, units, r.word);
        _bookFees(slot, r, totalUnits * bankroll, mainPool, uint32(_highField[key]));
        // An empty field has no seat that could finish it through the normal resolver.
        if (totalUnits == 0) _settleHighRollerReserve(slot);
    }

    /// @notice The table's post-batch hook, reached through its self-call and delegate fallback.
    /// @dev No caller-supplied candidate, count, randomness or cursor is trusted.
    function settleHighRollerReserve(uint64 slot) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _settleHighRollerReserve(slot);
    }

    function _settleHighRollerReserve(uint64 slot) private {
        JackpotRound storage r = _jackpotRounds[slot];
        if (r.word == 0) revert BadJackpotField();
        HighRollerDraw memory draw = _highRollerDraws[slot];
        if (draw.resolved) return;
        uint256 settled = _bonusCursor[slot];
        uint256 end = settled < r.paidCount ? settled : r.paidCount;
        uint256 daySlot = uint256(slot) / _BONUS_SLOTS_PER_DAY * _BONUS_SLOTS_PER_DAY;
        uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0 : uint32(_dayTickets[daySlot]);
        uint256 ownN = r.paidCount - dayN;
        // Reservoir sampling: contender n replaces the nominee with probability 1/n. Counts
        // and the nominee survive chunk boundaries, and the canonical seat order never changes.
        // Every high seat has one ticket, regardless of its multiple, dice or activity history.
        for (uint256 seat = uint256(draw.cursor) + 1; seat <= end; ++seat) {
            bool daySeat = seat > ownN;
            uint256 id = daySeat ? (daySlot << 64) | (seat - ownN) : (uint256(slot) << 64) | seat;
            uint256 header = _bets[id];
            uint256 highBit = daySeat ? _BET_HIGH_BIT << (_BONUS_PERIODS_PER_DAY - 1) : _BET_HIGH_BIT;
            address player = address(uint160(header));
            if (header & highBit == 0 || player == ContractAddresses.SDGNRS) continue;
            ++draw.eligible;
            if (_hash3(r.word, HIGH_RESERVE_WINNER_TAG, (uint256(slot) << 32) | draw.eligible) % draw.eligible == 0) {
                draw.nominee = player;
            }
        }
        draw.cursor = uint32(end);
        uint256 amount;
        if (settled == uint256(r.paidCount) + r.drawnCount) {
            draw.resolved = true;
            if (draw.eligible != 0 && _hash3(r.word, HIGH_RESERVE_DRAW_TAG, slot) % _HIGH_RESERVE_CHANCE == 0) {
                draw.won = true;
                amount = _highRollerReserve;
                _highRollerReserve = 0;
            }
            emit HighRollerReserveDrawn(slot, draw.eligible, draw.won ? draw.nominee : address(0), amount, _highRollerReserve);
        }
        // Effects precede the existing Coinflip credit call. Awards never feed action or comps,
        // never receive a pool multiplier, and never convert to additional pass grants.
        _highRollerDraws[slot] = draw;
        if (amount != 0) IHighReserveCredit(ContractAddresses.COINFLIP).creditFlip(draw.nominee, amount);
    }

    function highRollerReserve() external view returns (uint256) {
        return _highRollerReserve;
    }

    /// @notice Sampling progress; eligible is the final count only once all paid seats are read.
    /// @dev A nominee is a winner only if resolved AND won. Drawn free seats never enter this draw.
    function highRollerDrawOf(uint64 slot) external view returns (HighRollerDraw memory) {
        return _highRollerDraws[slot];
    }

    /// @dev Base-seat fees keep the ordinary action/2% comp treatment, excluding Added and roll
    ///      gains. Extra high capital instead funds comps from its conservative 12% expected loss:
    ///      80% to comps, 20% left unissued. The fair pool roll has mean one, so use PRE-ROLL fee
    ///      value. A contested bounty is redistribution; a sole high seat risks its bounty too.
    ///      These extras never enter the day books, which would spend their loss again on boosts.
    ///      Book once at seal; the table books nothing for this slot during settlement.
    function _bookFees(
        uint64 slot, JackpotRound storage r, uint256 ranBankroll, uint256 mainPool, uint256 highSeats
    ) private {
        uint256 paidCount = r.paidCount;
        if (paidCount == 0 || ranBankroll == 0) return;
        uint256 bps = r.multiplierBps < 10_000 ? r.multiplierBps : 10_000;
        uint256 staked = paidCount * _JACKPOT_PRICE * bps / 10_000 * ranBankroll / mainPool;
        uint256 high = staked * highSeats / paidCount;
        unchecked {
            _dayStaked[uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY)] += staked + (high << _DAY_HIGH_SHIFT);
        }
        uint256 highFees = (uint256(r.paidUnits) - paidCount) * _JACKPOT_PRICE;
        uint256 atRisk = highSeats == 1 ? highFees : highFees / 2;
        uint256 lossBudget = atRisk * _HIGH_LOSS_BPS / _BPS_DENOMINATOR;
        uint256 highComps = lossBudget * _HIGH_COMP_SHARE_BPS / _BPS_DENOMINATOR;
        uint256 earned = staked / 50;
        earned += highComps;
        if (earned != 0) IFlipCrapsComps(ContractAddresses.COIN).creditCrapsComps(earned);
        if (highFees != 0) emit JackpotHighCompsAccrued(slot, highFees, atRisk, lossBudget, highComps);
    }

    function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete) {
        slot = _activeJackpotSlot;
        JackpotRound storage r = _jackpotRounds[slot];
        added = r.added;
        started = r.word != 0;
        uint256 g = _battles[_rngBattleKey(slot)];
        complete = started && uint32(g >> _BG_RESOLVED_SHIFT) == uint32(g);
    }

    /// @notice UI/replay view. Added is the whole protocol allocation, including awarded bankrolls.
    function jackpotBattleOf(uint64 slot) external view returns (JackpotRound memory round, uint256 board, uint64 cursor) {
        return (_jackpotRounds[slot], _battles[_rngBattleKey(slot)], _bonusCursor[slot]);
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
