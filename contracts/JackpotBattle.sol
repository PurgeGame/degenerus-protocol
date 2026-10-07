// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGas} from "./libraries/MineFlipGas.sol";
import {Craps} from "./Craps.sol";
import {ICoinflipStake, ICrapsEngine, IFlipCoin, IGameCraps} from "./CrapsBattle.sol";
import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {CrapsPriceLib} from "./libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";
import {IReadCohortLifecycle, IVaultOwnership} from "./CrapsBattle.sol";
import {JackpotBattleFieldLib} from "./libraries/JackpotBattleFieldLib.sol";

interface IGameCrapsPending {
    function setCrapsRngPending(uint48 index, bool pending) external;
}

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
    error OnlyTableSelf();
    /// @dev The Game's FLIP-per-price unit: `price / _PRICE_COIN_UNIT` FLIP buys one ticket.
    uint256 private constant _PRICE_COIN_UNIT = 1000;
    /// @dev Conservative whole-run loss budget, using the same 12% calibration as the ordinary
    ///      action subsidy. Separate constants keep future boost tuning from changing high comps.
    uint256 private constant _HIGH_LOSS_BPS = 1200;
    uint256 private constant _HIGH_COMP_SHARE_BPS = 8000;
    event JackpotBattleEntry(uint64 indexed slot, uint256 indexed betId, uint32 indexed playerId, uint256 units, uint32 chips);

    /// @notice Open a custom battle; the table's `createBattle` forwards here. See CrapsBattle.
    /// @dev The creator roll is checked FIRST so a granted creator never pays for the
    ///      cross-contract call; the vault's majority holder always qualifies, so the authority
    ///      behind the grant can never be locked out of its own table.
    function createBattle(
        uint32 played,
        uint8 bankMult,
        uint16 goalMult,
        uint24 stakeUnits,
        uint40 closeTime,
        bool multiEntry,
        uint16 highRollerMult
    ) external returns (uint64 slot) {
        if (!_battleCreator[msg.sender] && !IVaultOwnership(ContractAddresses.VAULT).isVaultOwner(msg.sender)) {
            revert NotBattleCreator();
        }
        uint256 terms = ICrapsEngine(ContractAddresses.CRAPS_ENGINE).customDefinition(
            played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult
        );
        unchecked { slot = uint64(_CUSTOM_SLOT_BASE + ++_customBattleCount); }
        _customBattle[slot] = terms;
        emit CrapsBattleCreated(slot, msg.sender, terms);
    }

    function setBattleCreator(address account, bool allowed) external {
        if (!IVaultOwnership(ContractAddresses.VAULT).isVaultOwner(msg.sender)) revert NotVaultOwner();
        _battleCreator[account] = allowed;
        emit BattleCreatorSet(account, allowed);
    }

    /// @notice Self-only finalization: split the scheduled main pot 90/10 between the
    ///         battle winner and the longest shared hand's named shooter. Their own run
    ///         may have stopped; the table's shared dice decide the hand length.
    function payBattlePot(uint64 slot, bytes32 key, uint256 winnerId, uint256 pot, uint256 boost, uint256 word)
        public
    {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        uint32 winner = uint32(_loadBet(winnerId));
        if (slot < _CUSTOM_SLOT_BASE) {
            uint256 heat = (_highField[key] >> _HF_HOTTEST_SHIFT) & _HF_HOTTEST_MASK;
            if (heat != 0 && pot != 0) {
                uint256 seed = uint256(keccak256(abi.encode(_CRAPS_SEED_DOMAIN, word, uint256(slot))));
                uint256 n = uint32(_battles[key]);
                uint256 start = uint256(keccak256(abi.encode(uint256(0x526f746174696e6753686f6f746572), seed))) % n;
                uint256 seat = 1 + (start + 511 - (heat & 511)) % n;
                uint256 daySlot = uint256(slot) / _BONUS_SLOTS_PER_DAY * _BONUS_SLOTS_PER_DAY;
                uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0 : uint32(_dayTickets[daySlot]);
                uint256 ownN = n - dayN - _jackpotRounds[slot].drawnCount;
                uint256 hotId = seat <= ownN ? (uint256(slot) << 64) | seat
                    : seat <= ownN + dayN ? (daySlot << 64) | (seat - ownN)
                    : (uint256(slot) << 64) | (seat - dayN);
                uint32 shooter = uint32(_loadBet(hotId));
                uint256 share = pot / 10;
                pot -= share;
                uint256 protocolShare = boost / 10;
                boost -= protocolShare;
                share -= _splitAward(key, shooter, _SPLIT_SRC_HOTTEST | protocolShare);
                if (share != 0) _creditFlip(shooter, share);
                emit CrapsHottestShooterPaid(hotId, key, shooter, uint16(heat >> 9), share);
            }
            pot -= _splitAward(key, winner, _SPLIT_SRC_MAIN | boost);
        }
        if (pot != 0) {
            _creditFlip(winner, pot);
            emit CrapsBattlePaid(winnerId, key, winner, pot);
        }
    }

    /// @dev Scheduled fields use the slot itself; custom fields commit to their exact terms.
    function _rngBattleKey(uint64 slot) private view returns (bytes32) {
        if (slot < _CUSTOM_SLOT_BASE) return bytes32(uint256(slot));
        uint256 c = _customBattle[slot];
        uint256 played = (c & _CB_PLAYED_MASK);
        uint256 bank = uint128(played * ((c >> _CB_BANK_SHIFT) & _CB_BANK_MASK));
        uint256 goal = uint128(bank * ((c >> _CB_GOAL_SHIFT) & _CB_GOAL_MASK));
        uint256 terms = ((c >> _CB_STAKE_SHIFT) & _BSTAKE_MAX)
            | (((c >> _CB_HIGH_SHIFT) & _CB_HIGH_MASK) << _TERM_HIGH_SHIFT);
        return keccak256(abi.encode(BATTLE_TAG, uint48(slot), bank, goal, played, terms));
    }

    /// @notice Drain the committed read FIFO within `allowance`.
    function runCrapsReadWork(uint48 index, uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        return _keepRngCohort(index, allowance);
    }

    function _keepRngCohort(uint48 index, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (index > 1) revert BadJackpotField();
        if (allowance == 0) return result;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (_rngPending[index] == 0) { result.done = true; return result; }
        if (_readCrapsStage() != 6 || _wordAt(index) == 0) return result;
        uint64[] storage slots = _rngSlots[index];
        uint64 pos = _rngSlotCursor[index];
        for (uint256 steps; pos < slots.length && steps < _KEEP_MAX_HOPS; ++steps) {
            if (!MineFlipGas.canRun(meter, _MAINTENANCE_GAS_MAX, _WORK_TAIL_GAS)) break;
            uint64 slot = slots[pos];
            // Boards retain their logical keys. A completed slot may still be in
            // the FIFO, but its pending count was already released at settlement.
            uint256 board = _battles[_rngBattleKey(slot)];
            if (uint32(board >> _BG_RESOLVED_SHIFT) == uint32(board)) {
                ++pos;
                result.progressed = true;
                continue;
            }
            if (_scheduledExpired(slot)) {
                _completeRngSlot(slot, index);
                ++pos;
                result.progressed = true;
                emit CrapsScheduledExpired(slot);
                continue;
            }
            if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX + _WORK_TAIL_GAS)) break;
            if (_rngSlotCursor[index] != pos) _rngSlotCursor[index] = pos;
            uint256 childAllowance = _resolverAllowance(MineFlipGas.remaining(meter));
            MineFlipGas.Result memory child = IReadCohortLifecycle(address(this)).resolveRngSlot(slot, childAllowance);
            result.progressed = result.progressed || child.progressed;
            result.rewardBasis += child.rewardBasis;
            if (child.done) ++pos;
            // One field per batch preserves the established finalization boundary.
            break;
        }
        if (_rngSlotCursor[index] != pos) _rngSlotCursor[index] = pos;
        result.done = _rngPending[index] == 0;
        MineFlipGas.finish(meter);
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

    function _completeRngSlot(uint64 slot, uint48 index) private {
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
        if (_activeJackpotSlot != 0 && !_scheduledExpired(_activeJackpotSlot)) {
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
        bool detached = _scheduledExpired(slot) || _boostBudget[uint24(day)] == 0 || _slotIndexOf(slot) != 0;
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
        // An opened battle already holds its advertised fee. Only detached award-only
        // rounds need neutral terms; OR-ing the old constant into a drawn fee corrupts it.
        uint256 entryPrice = detached ? _JACKPOT_PRICE : ((g >> _BG_STAKE_SHIFT) & _BSTAKE_MAX) * _BATTLE_STAKE_UNIT;
        if (detached) g |= (entryPrice / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT;
        _battles[key] = g;
        _setSlotIndex(slot, type(uint48).max);
        // Floor the baseline first. Awards depend on that baseline alone, and are frozen
        // in the same packed word as the fee/counts before any settlement word exists.
        uint256 added = CrapsPriceLib.jackpotAdded(pool * _PRICE_COIN_UNIT / (PriceLookupLib.priceForLevel(level) * 200), level);
        uint256 target = added / CrapsPriceLib.JACKPOT_AWARD_VALUE;
        r.awardTarget = uint32(target > 500 ? 500 : target);
        r.entryPrice = uint32(entryPrice);
        r.added = added * entryPrice / _JACKPOT_PRICE;
        r.paidCount = uint32(g);
        // Frozen terms survive retirement of the opening word.
        uint256 highMult = detached ? 1 : (g >> _BG_TERM_TIER_SHIFT & _BG_TERM_HIGH_TAIL != 0
            ? CrapsPriceLib.HIGH_TAIL : CrapsPriceLib.HIGH_BASE);
        r.paidUnits = uint64(uint256(r.paidCount) + uint32(_highField[key]) * (highMult - 1));
        r.requestDay = requestDay;
        _activeJackpotSlot = slot;
        uint256 contribution = r.added / _HIGH_RESERVE_DIVISOR;
        _highRollerReserve += contribution;
        emit HighRollerReserveFunded(slot, contribution, _highRollerReserve);
        emit JackpotBattleLocked(slot, requestDay, r.added, r.paidCount);
    }

    /// @notice Initialize a resumable draw, returning its frozen word, cursor and units still wanted.
    /// @dev The target was frozen from the unscaled baseline at lock; paid volume adds no free units.
    function prepareJackpotBattle(uint24 level, uint256 word)
        external returns (uint256 drawWord, uint256 cursor, uint256 remaining)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (_scheduledExpired(_activeJackpotSlot)) return (word, 0, 0);
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
        // The reserve and award target were committed at lock. This independently tagged
        // draw changes only the main subsidy, with 60/30/9/1 odds and an exact 1x mean.
        uint256 subsidyBps = _subsidyMultiplier(_hash3(word, _activeJackpotSlot, JACKPOT_SUBSIDY_TAG));
        uint256 mainAdded = r.added - r.added / _HIGH_RESERVE_DIVISOR;
        mainAdded = mainAdded * subsidyBps / 10_000;
        uint256 pool = (uint256(r.paidUnits) * r.entryPrice + mainAdded) * multiplier / 10_000;
        // At the 6,000 fee and both minimum rolls, awarded capital is still >=890
        // per seat before the bankroll split: every nonempty field retains >=300.
        r.totalPool = pool;
        r.multiplierBps = uint32(multiplier);
        r.subsidyMultiplierBps = uint32(subsidyBps);
        r.level = level;
        r.drawWord = word;
        emit JackpotSubsidyRolled(_activeJackpotSlot, uint32(subsidyBps), mainAdded);
    }

    function _subsidyMultiplier(uint256 entropy) internal pure returns (uint256) {
        uint256 roll = entropy % 100;
        return roll < 60 ? 2_500 : roll < 90 ? 10_000 : roll < 99 ? 50_000 : 100_000;
    }

    /// @notice Collect at most `JackpotBattleFieldLib.MAX_CHUNK` units; the final chunk freezes terms
    ///         and enables paid settlement.
    function appendJackpotBattle(uint256[] calldata field, uint256 cursor, bool last) external {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        _append(field, cursor, last);
    }

    function _append(uint256[] calldata field, uint256 cursor, bool last) private {
        uint64 slot = _activeJackpotSlot;
        if (_scheduledExpired(slot)) return;
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
            uint32 playerId = uint32(entry);
            // A malformed or empty entry forfeits its award rather than halting the advance.
            if (entry >> JackpotBattleFieldLib.UNITS_SHIFT != 1 || playerId == 0) continue;
            (uint32 chips,) = CrapsPreferenceLib.decode(
                entry >> (JackpotBattleFieldLib.BOARD_SHIFT - CrapsPreferenceLib.SHIFT));
            uint256 id = (uint256(slot) << 64) | (ownN + ++drawn);
            _storeBet(id, uint256(playerId) | (uint256(chips) << _BET_CHIPS_SHIFT)
                | (uint256(1) << _AWARD_UNITS_SHIFT));
            ++units;
            emit JackpotBattleEntry(slot, id, playerId, 1, chips);
        }
        r.drawnCount = uint32(drawn);
        r.drawnUnits = uint32(units);
        r.drawCursor = cursor;
        if (!last) return;

        // Every paid seat buys ONE place in the Added-funded main battle. Its extra high
        // units form their own fee-only bankroll/bounty allocation under the same fair roll.
        uint256 totalUnits = uint256(r.paidCount) + units;
        uint256 highPool = (uint256(r.paidUnits) - r.paidCount) * r.entryPrice * r.multiplierBps / 10_000;
        uint256 mainPool = r.totalPool - highPool;
        uint256 bankroll;
        uint256 bounty;
        if (totalUnits != 0) {
            uint256 perUnit = mainPool / totalUnits;
            bankroll = perUnit / 2 / _JACKPOT_BANKROLL_UNIT * _JACKPOT_BANKROLL_UNIT;
            uint256 maxBank = (uint256(type(uint24).max) / 10 / 6) * 6 * 50;
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
        if (_scheduledExpired(slot)) return;
        JackpotRound storage r = _jackpotRounds[slot];
        if (r.word == 0) revert BadJackpotField();
        HighRollerDraw memory draw = _highRollerDraws[slot];
        if (draw.resolved) return;
        uint256 settled = _bonusCursorOf(slot);
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
            uint256 header = _loadBet(id);
            uint256 highBit = daySeat ? _BET_HIGH_BIT << (_BONUS_PERIODS_PER_DAY - 1) : _BET_HIGH_BIT;
            uint32 playerId = uint32(header);
            if (header & highBit == 0 || playerId == _SDGNRS_ID) continue;
            ++draw.eligible;
            if (_hash3(r.word, HIGH_RESERVE_WINNER_TAG, (uint256(slot) << 32) | draw.eligible) % draw.eligible == 0) {
                draw.nominee = playerId;
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
            emit HighRollerReserveDrawn(slot, draw.eligible, draw.won ? draw.nominee : 0, amount, _highRollerReserve);
        }
        // Effects precede the existing Coinflip credit call. Awards never feed action or comps,
        // never receive a pool multiplier, and never convert to additional pass grants.
        _highRollerDraws[slot] = draw;
        if (amount != 0) _creditFlip(draw.nominee, amount);
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
        uint256 staked = paidCount * r.entryPrice * bps / 10_000 * ranBankroll / mainPool;
        uint256 high = staked * highSeats / paidCount;
        unchecked {
            _dayStaked[uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY)] += staked + (high << _DAY_HIGH_SHIFT);
        }
        uint256 highFees = (uint256(r.paidUnits) - paidCount) * r.entryPrice;
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
        if (slot != 0 && _scheduledExpired(slot)) return (slot, added, true, true);
        started = r.word != 0;
        uint256 g = _battles[_rngBattleKey(slot)];
        complete = started && uint32(g >> _BG_RESOLVED_SHIFT) == uint32(g);
    }

    /// @notice UI/replay view. Added is the whole protocol allocation, including awarded bankrolls.
    function jackpotBattleOf(uint64 slot) external view returns (JackpotRound memory round, uint256 board, uint64 cursor) {
        return (_jackpotRounds[slot], _battles[_rngBattleKey(slot)], _bonusCursorOf(slot));
    }

    /// @notice The advertised jackpot's base fee, including after it locks. No opening means no quote.
    function jackpotEntryPrice() external view returns (uint256) {
        if (_bonus == 0) revert RngNotReady();
        return jackpotEntryPriceOf(uint64((_bonus - 1) * _BONUS_SLOTS_PER_DAY + _BONUS_PERIODS_PER_DAY));
    }

    /// @notice An opened/locked event's fee survives word retirement and the bounty overwrite.
    function jackpotEntryPriceOf(uint64 slot) public view returns (uint256) {
        if (!_isJackpotSlot(slot)) revert BadJackpotField();
        uint256 price = _jackpotRounds[slot].entryPrice;
        if (price != 0) return price;
        uint256 board = _battles[bytes32(uint256(slot))];
        if ((board >> _BG_TERM_TIER_SHIFT) & _BG_TERMS_FROZEN == 0) revert RngNotReady();
        return ((board >> _BG_STAKE_SHIFT) & _BSTAKE_MAX) * _BATTLE_STAKE_UNIT;
    }

    function convertNormalToHigh(uint32 id, uint32 highCount) external {
        if (highCount == 0) revert BadPassCount();
        id = _accountId(id);
        uint256 word = _passCreditsById[id];
        uint256 cost;
        uint256 highs;
        unchecked {
            cost = uint256(highCount) * _PASSES_PER_HIGH;
            highs = ((word >> _PASS_HIGH_SHIFT) & _PASS_MAX) + highCount;
        }
        if (highs > _PASS_MAX) revert PassLaneFull();
        // Deliberately CHECKED, exactly as `_takeCredits`: the underflow IS the balance test.
        uint256 normals = (word & _PASS_MAX) - cost;
        _passCreditsById[id] =
            (word & ~(_PASS_MAX | (_PASS_MAX << _PASS_HIGH_SHIFT))) | (highs << _PASS_HIGH_SHIFT) | normals;
        emit CrapsNormalPassesConverted(id, cost, highCount);
    }

    function upgradeReservedDay(uint32 id, uint24 day) external {
        if (!_reservableDay(day)) revert DayNotReservable();
        id = _accountId(id);
        uint256 daySlot = _daySlotOf(day);
        uint256 seat = _loadDaySeat(daySlot, id) & _MASK32;
        if (seat == 0) revert NoSuchBet();
        uint256 betId = (daySlot << 64) | seat;
        uint256 header = _loadBet(betId);
        if (header & _BET_DAYHIGH_MASK != 0) revert NothingToUpgrade();
        _takeCredits(id, true, 1);
        _credit(id, false, 1);
        _storeBet(betId, header | _BET_DAYHIGH_MASK);
        unchecked {
            _dayTickets[daySlot] += _DT_ALL_HIGH;
        }
        emit CrapsDayWindowsUpgraded(id, day, uint8(_BET_DAYHIGH_MASK >> _BET_HIGH_SHIFT), 0);
    }

    /// @dev The pass doors' account: `id == 0` is the caller, by its existing wallet ID; any other
    ///      `id` must be allocated (the Game's resolution reverts otherwise) and the caller
    ///      authorized for it. These doors move only ID-keyed credits and seats, so neither the
    ///      key nor the payee is needed.
    function _accountId(uint32 id) private returns (uint32) {
        if (id == 0) return uint32(_walletWord(msg.sender, false) >> CrapsPreferenceLib.ID_SHIFT);
        (,, bool authorized) = IGameCraps(_GAME).resolveAccount(id, msg.sender);
        if (!authorized) revert NotApproved();
        return id;
    }

    function _daySlotOf(uint256 day) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY;
        }
    }

    /// @dev Self-only finalization executes atomically inside the last seat.
    function finalizeBattle(Window calldata w, uint256 board, uint256 word) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _payout(w, board, word);
        // Preserve payout-before-completion ordering in the same cold-module call.
        // Dedicated daily jackpot fields do not belong to the normal read cohort.
        if (!_isJackpotSlot(w.bound)) {
            uint48 index;
            unchecked { index = _slotIndexOf(w.bound) - 1; }
            _completeRngSlot(w.bound, index);
        }
    }

    function _bonusRoll(uint256 word, uint256 period) private pure returns (uint256) {
        unchecked {
            return _hash3(word, SCHEDULE_TAG, period == _BONUS_PERIODS_PER_DAY - 2 ? 0 : period);
        }
    }

    function _boostBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, false);
    }

    function _boostMult(uint256 word, uint48 bound) internal pure returns (uint256) {
        unchecked {
            uint256 roll = _hash3(word, bound, BOOST_TAG) % 1000;
            if (roll < 768) return 1;
            if (roll < 976) return 4;
            if (roll < 996) return 40;
            return 400;
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

    function _creditComps(uint256 amount) private {
        IFlipCoin(ContractAddresses.COIN).creditCrapsComps(amount);
    }

    function _creditFlip(uint32 id, uint256 amount) private {
        ICoinflipStake(ContractAddresses.COINFLIP).creditFlip(id, amount);
    }

    function _dayField(uint256 slot) private view returns (uint256 base, uint64 n) {
        if (slot >= _CUSTOM_SLOT_BASE || slot % _BONUS_SLOTS_PER_DAY == 7) return (0, 0);
        unchecked {
            uint256 d = _daySlotOf(slot / _BONUS_SLOTS_PER_DAY);
            return (d << 64, uint32(_dayTickets[d]));
        }
    }

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

    function _highBase(Window memory w) internal view returns (uint256) {
        return _shareOf(w, true);
    }

    function _highBoostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            return (_highBase(w) * _boostMult(word, w.bound)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    function _highBounty(Window memory w) internal pure returns (uint256) {
        return w.highExtra != 0 ? w.highExtra : (w.highMult - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT;
    }

    function _isJackpotSlot(uint256 slot) internal pure returns (bool) {
        return slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY >= _BONUS_PERIODS_PER_DAY;
    }

    function _laneBoost(Window memory w, uint256 word) internal view returns (uint256) {
        return _roundBoost(_highBoostUnits(w, word)) * _BATTLE_STAKE_UNIT;
    }

    function _payProgressive(
        Window memory w,
        uint256 peakFlip,
        uint256 score,
        uint256 winnerId,
        uint256 winnerWord
    ) internal {
        unchecked {
            // RARE FIRST, and it OVERRIDES. The rare cutoff is above the common cutoff, so a run
            // that clears it has cleared both — and takes the rare rung alone,
            // never both. Both cutoffs are INCLUSIVE.
            bool rare = score >= _PROG_RARE;
            // THE RUNG, COUNTED IN DOUBLINGS of the common share: RARE is one doubling, so
            // `500 << shift` is the whole table, 500 common and 1,000 rare.
            uint256 shift;
            if (rare) shift = _PROG_RARE_DOUBLINGS;
            else if (score < _PROG_COMMON) return;

            uint256 bps = _PROG_ROUTINE_COMMON_BPS << shift;
            _payProgressiveShare(w.key, winnerId, winnerWord, peakFlip, score, bps);
        }
    }

    function _payProgressiveShare(bytes32 key, uint256 winnerId, uint256 winnerWord, uint256 peakFlip, uint256 score, uint256 bps) private {
        unchecked {
            uint32 winner = uint32(winnerWord);
            uint256 pool = _progressive;
            uint256 candidate = _poolShare(pool, bps);
            if (candidate == 0) return;
            uint256 paid = candidate;
            // The WHOLE gross award leaves the pool, pass slice included — a pass is this award
            // paying in a different shape, and leaving its value behind would count it twice.
            pool -= paid;
            _progressive = pool;
            emit CrapsProgressivePaid(
                winnerId, key, winner, score >= _PROG_RARE, uint16(bps), peakFlip, score, candidate, paid, pool
            );
            // State first, credit second; every qualifying dice result receives the full award.
            paid -= _splitAward(key, winner, _SPLIT_SRC_PROGRESSIVE | paid);
            if (paid != 0) _creditFlip(winner, paid);
        }
    }

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
            uint256 score = (peakFlip * _BPS_DENOMINATOR) / (uint256(w.bankroll));
            // DONATED GRANULES AND THE WINNING SEAT, read once each: both the finalization log and
            // the payment below want them, and a battle word is one warm slot either way.
            // The pot this field pays out, seed and boost included. Every finished field carries
            // the whole pot: a window nobody else wanted is still a race, and what is on it is what
            // its main-pool prize recipients share.
            emit CrapsBattleFinalized(
                w.key,
                stop,
                uint64(uint32(g >> _BG_WINNER_SHIFT)),
                peakFlip,
                endFlip,
                score,
                ((entrants + w.extraUnits) * w.stakeUnits + boost + ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK)) * _BATTLE_STAKE_UNIT + w.extraPot
            );
            // THE COMP LANE'S SHARE: two percent of the bankroll this field actually ran, seat by
            // seat — a high seat runs `highMult` copies — and nothing else. Bounties, donations,
            // boosts and returns are not bankroll, and the sole rider's extra capital is bounty.
            // Every term here was fixed before a die was thrown, so the credit is the same
            // whichever way the field settles and however its settlement was chunked, and it is
            // paid exactly once: finalization runs once. A custom battle earns it too — this sits
            // above the scheduled-only branch, and a custom window with no high lane has zero
            // high seats, so its zero multiple never enters the sum.
            // The sideboard is read ONCE for the whole finalization — here for the count, and
            // below for the lane's winner — so an ordinary field still asks it one question.
            uint256 f = _highField[w.key];
            // The jackpot battle's comp share is paid on its fees alone when its field seals.
            if (!_isJackpotSlot(slot)) {
                uint256 highSeats = uint32(f);
                uint256 eligible = uint256(w.bankroll) * (entrants + w.extraUnits);
                if (highSeats != 0) eligible += uint256(w.bankroll) * highSeats * (w.highMult - 1);
                uint256 earned = eligible / 50;
                if (earned != 0) _creditComps(earned);
            }
            // The winning seat is an index into the same own-then-day range the settle walk used,
            // so naming it takes the same mapping back.
            (uint256 dayBase, uint64 dayN) = _dayField(slot);
            uint64 ownN = uint64(entrants) - dayN - w.drawn;

            uint64 seat = uint64(uint32(g >> _BG_WINNER_SHIFT));
            uint256 winnerId = _seatId(slot, seat, ownN, dayBase, dayN);
            uint256 winnerWord = _loadBet(winnerId);
            // The boost: this table's own pick from the band the window advertised, plus anything
            // donated on top of it. Nothing about either was stored.
            // Donations pay in full and bypass protocol-bonus rounding.
            uint256 donated = (g >> _BG_SEED_SHIFT) & _BG_SEED_MASK;
            boost = _roundBoost(boost);
            // The bounties and the house money, and NOTHING else. What the field busted away is
            // deleted where it busted.
            uint256 pot = (w.stakeUnits * (entrants + w.extraUnits) + boost + donated) * _BATTLE_STAKE_UNIT + w.extraPot;
            payBattlePot(
                uint64(slot), w.key, winnerId, pot, boost * _BATTLE_STAKE_UNIT, word
            );
            // THE LANE. Only a contested one pays here — a field of one settled its lane on that
            // seat's own run, and a field of none never had one.
            uint256 heads = uint32(f);
            if (heads >= 2) {
                seat = uint64((f >> _HF_WINNER_SHIFT) & _MASK32);
                uint256 hId = _seatId(slot, seat, ownN, dayBase, dayN);
                uint256 hWord = _loadBet(hId);
                _highField[w.key] = f | _HF_DONE_BIT;
                uint256 lane = _laneBoost(w, word);
                // The extra bounties are the seats' own posted money and pay out whole; only the
                // lane boost is protocol money, so only it can pay in passes.
                uint32 hWinner = uint32(hWord);
                uint256 lanePot = heads * _highBounty(w) + lane
                    - _splitAward(w.key, hWinner, _SPLIT_SRC_HIGH_CONTESTED | lane);
                if (lanePot != 0) {
                    _creditFlip(hWinner, lanePot);
                    emit CrapsHighRollerPaid(hId, w.key, hWinner, lanePot, false);
                }
            }

            // THE PROGRESSIVE, LAST, and decided by the scoreboard that just closed and by nothing
            // else. Entry pricing and activity history do not reduce the winner's pool share.
            //
            // THEN THE RECORD, on the same finalized figures and once for the whole field. Never
            // per entrant: the candidate is the winner the comparator named, and the field is
            // closed by the time either of these can read it.
            //
            // BOTH ARE THE PROTOCOL'S OWN MONEY, so both are SCHEDULED-ONLY. A custom battle
            // plays the same game and races on the same comparator; what it does not do is fund
            // or draw on anything the protocol allocates. The single scheduled branch below
            // carries that guard for the progressive and the record alike.
            // `peakFlip` decodes as zero for a bust in either product, so the goal gate needs no
            // restating.
            //
            // THE BIGGEST DICE RUN is the FIFTH category of the record `Coinflip` already owns,
            // not a pool of its own: nothing here funds a record pool, adds craps action, or
            // touches the four existing kinds. A 100x high point has necessarily crossed the
            // scheduled target, so the floor does the whole eligibility test. Below it NOTHING is
            // called — a field that never got near a record does not pay for a cross-contract
            // read to be told so — and `Coinflip` logs the claim it makes.
            if (scheduled) {
                _payProgressive(w, peakFlip, score, winnerId, winnerWord);
                _recordDiceRun(uint32(winnerWord), score);
            }
        }
    }

    function _poolShare(uint256 pool, uint256 bps) internal pure returns (uint256) {
        unchecked {
            return (pool / _BPS_DENOMINATOR) * bps + ((pool % _BPS_DENOMINATOR) * bps) / _BPS_DENOMINATOR;
        }
    }

    function _recordDiceRun(uint32 winner, uint256 score) private {
        if (score >= _DICE_RUN_RECORD_FLOOR) {
            ICoinflipStake(ContractAddresses.COINFLIP).armDiceRunRecord(winner, score);
        }
    }

    function _roundBoost(uint256 units) internal pure returns (uint256) {
        if (units <= _BOOST_ROUND_ABOVE) return units;
        unchecked {
            return ((units + _BOOST_ROUND_STEP / 2) / _BOOST_ROUND_STEP) * _BOOST_ROUND_STEP;
        }
    }

    function _routineWeight(uint256 word) internal pure returns (uint256 total) {
        unchecked {
            for (uint256 p = 0; p + 1 < _BONUS_PERIODS_PER_DAY; ++p) {
                total += 1 << _tierPick(word, p);
            }
        }
    }

    function _seatId(uint256 slot, uint64 seat, uint64 ownN, uint256 dayBase, uint64 dayN)
        private pure returns (uint256)
    {
        // Both counts come from uint32 fields. The sum fits uint64, and each
        // subtraction is guarded by the preceding ordinal comparisons.
        unchecked {
            if (seat <= ownN) return (slot << 64) | seat;
            if (seat <= ownN + dayN) return dayBase | (seat - ownN);
            return (slot << 64) | (seat - dayN);
        }
    }

    function _shareOf(Window memory w, bool high) private view returns (uint256) {
        if (w.bound >= _CUSTOM_SLOT_BASE || _isJackpotSlot(w.bound)) return 0;
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

    function _splitMainBudget(uint256 rawMain) internal pure returns (uint256 ladder, uint256 progressive) {
        unchecked {
            ladder = rawMain / 2;
            progressive = rawMain - ladder;
        }
    }

    function _tierPick(uint256 word, uint256 period) internal pure returns (uint256) {
        return CrapsPriceLib.tier(_bonusRoll(word, period), period == 0 || period == _BONUS_PERIODS_PER_DAY - 2);
    }

    function _windowShare(uint256 budget, uint256 weight, uint256 period, uint256 tier) private pure returns (uint256) {
        if (period == _BONUS_PERIODS_PER_DAY - 1 || weight == 0) return 0;
        return budget * (1 << (tier - 1)) / weight;
    }

    function _armSlot(uint64 slot, Window memory w) internal returns (uint48 index) {
        unchecked {
            index = _writeBuffer();
            _setSlotIndex(slot, index + 1);
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
        // The shut window joins the write buffer's RNG round like any other consumer: the next
        // request, daily or mid-day, settles it. Its pending bit counts as work for that request.
        IReadCohortLifecycle(address(this)).registerRngSlot(index, slot, w.key);
        emit CrapsBonusArmed(w.key, uint48(slot), index);
    }

    function _bonusPreset(uint256 roll, uint256 period) internal pure
        returns (uint128 bankroll, uint128 goal, uint256 boardStake, uint256 stakeUnits, uint256 tier)
    {
        // The jackpot fee is known now. Its bankroll/pot are derived only after its field locks.
        if (period == _BONUS_PERIODS_PER_DAY - 1) return (0, 0, 0, CrapsPriceLib.jackpotPrice(roll) / _BATTLE_STAKE_UNIT, 0);
        uint256 pick = CrapsPriceLib.tier(roll, period == 0 || period == _BONUS_PERIODS_PER_DAY - 2);
        uint256 bank = (uint256(0x119407080258) >> (pick * 16)) & 0xffff;
        uint256 bounty = (uint256(0xdac09c405dc057803e802580190012c00c8) >> ((pick * 3 + ((roll >> 8) % 3)) * 16)) & 0xffff;
        return (uint128(bank), uint128(bank * _SCHED_GOAL),
            bank / _SCHED_BANK_MULT, bounty / 100, pick + 1);
    }

    function _currentBonusSlot() internal view returns (uint24 day, uint256 period, uint256 slot) {
        day = _currentDayIndex();
        uint256 elapsed = (block.timestamp - 82_620) % 1 days;
        if (elapsed < 20 minutes) period = 0;
        else if (elapsed < 6 hours + 3 minutes) period = 1;
        else if (elapsed < 12 hours + 3 minutes) period = 2;
        else if (elapsed < 18 hours + 3 minutes) period = 3;
        else if (elapsed < 1 days - 20 minutes) period = 4;
        else period = 5;
        slot = _slotOf(day, period);
    }

    function _finishWindowTerms(uint24 day, uint256 period, Window memory w, uint256 highMult)
        private pure returns (Window memory)
    {
        unchecked {
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.bound = uint48(_slotOf(day, period));
            w.highMult = highMult;
            w.terms = w.stakeUnits | (highMult << _TERM_HIGH_SHIFT);
        }
        w.key = bytes32(uint256(w.bound));
        return w;
    }

    function _keepScheduled(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (allowance == 0) return result;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint8 stage = _readCrapsStage();
        uint48 read = _writeBuffer() ^ 1;
        // Before the first session, maintenance creates the commitments that request seals.
        // A live read cohort, locked day or earlier consumer always blocks admission work.
        if (stage != 7 && !(stage == 0 && !IGameCraps(_GAME).rngLocked()
            && _rngPending[read] == 0 && _wordAt(read) == 0)) return result;
        uint64 cur = _keeperSlot;
        uint24 today = _currentDayIndex();
        if (_scheduledExpired(cur)) {
            // Bounded catch-up after a long outage. No expired seat is read or refunded.
            emit CrapsScheduledExpired(cur);
            cur = uint64((uint256(today) - _SETTLEMENT_DAYS) * _BONUS_SLOTS_PER_DAY);
        }
        (,, uint256 open) = _currentBonusSlot();
        for (uint256 hops; hops < _KEEP_MAX_HOPS; ++hops) {
            if (!MineFlipGas.canRun(meter, _MAINTENANCE_GAS_MAX, _WORK_TAIL_GAS)) break;
            uint24 day = uint24(uint256(cur) / _BONUS_SLOTS_PER_DAY);
            if (cur % _BONUS_SLOTS_PER_DAY == 0) {
                if (_boostBudget[day] != 0) { ++cur; continue; }
                if (day >= today) { result.done = true; break; }
                (bool doneAll, bool moved) = _sweepLapsedDay(cur, day, meter);
                result.progressed = moved;
                if (doneAll) cur += uint64(_BONUS_SLOTS_PER_DAY);
                break;
            }
            if (cur % _BONUS_SLOTS_PER_DAY > _BONUS_PERIODS_PER_DAY) { ++cur; continue; }
            if (_slotIndexOf(cur) == 0) {
                if (cur >= open || _isJackpotSlot(cur)) { result.done = true; break; }
                Window memory w = _windowTerms(day, (uint256(cur) % _BONUS_SLOTS_PER_DAY) - 1);
                _armSlot(cur, w);
                result.progressed = true;
                // Re-examine the armed slot: a field ends maintenance (done) so the same miner
                // call can request its word; an empty one steps on to the next head.
                continue;
            }
            uint256 g = _battles[bytes32(uint256(cur))];
            uint256 entrants = uint32(g);
            if (entrants == 0 || uint32(g >> _BG_RESOLVED_SHIFT) == entrants) { ++cur; continue; }
            // Committed settlement is exclusively the read FIFO; daily battles have their own tx.
            result.done = true;
            break;
        }
        if (cur != _keeperSlot) { _keeperSlot = cur; result.progressed = true; }
        result.rewardBasis = result.progressed ? 1 : 0;
        MineFlipGas.finish(meter);
    }

    function _slotOf(uint256 day, uint256 period) private pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY + period + 1;
        }
    }

    function _sweepLapsedDay(uint64 daySlot_, uint24 day, MineFlipGas.Meter memory meter)
        private returns (bool doneAll, bool moved)
    {
        uint256 comps;
        for (uint256 slot = daySlot_; slot <= uint256(daySlot_) + _BONUS_PERIODS_PER_DAY; ++slot) {
            if (!MineFlipGas.canRun(meter, _REFUND_GAS_MAX, _SWEEP_TAIL_GAS)) {
                if (comps != 0) _creditComps(comps);
                return (false, moved);
            }
            uint64 n = slot == daySlot_ ? uint32(_dayTickets[slot]) : uint32(_battles[bytes32(slot)]);
            uint64 done = _bonusCursorOf(slot);
            while (done < n) {
                if (!MineFlipGas.canRun(meter, _REFUND_GAS_MAX, _SWEEP_TAIL_GAS)) {
                    _setBonusCursor(slot, done);
                    if (comps != 0) _creditComps(comps);
                    return (false, moved);
                }
                uint256 header = _loadBet((slot << 64) | ++done);
                bool high = header & _BET_HIGH_BIT != 0;
                if (slot == daySlot_) _credit(uint32(header), high, 1);
                else comps += _windowAheadPrice(slot - daySlot_ - 1, high);
                moved = true;
            }
            if (done != _bonusCursorOf(slot)) _setBonusCursor(slot, done);
        }
        if (comps != 0) _creditComps(comps);
        emit CrapsDayLapsed(day, uint32(_dayTickets[daySlot_]));
        return (true, moved);
    }

    function _windowAheadPrice(uint256 period, bool high) private pure returns (uint256 price) {
        unchecked {
            price = period == 0 || period == _BONUS_PERIODS_PER_DAY - 2
                ? _EV_WINDOW_OPENER
                : (period == _BONUS_PERIODS_PER_DAY - 1 ? _EV_WINDOW_TAIL : _EV_WINDOW_ROUTINE);
            if (high) price *= _EV_HIGH_MULT;
        }
    }

    function _windowTerms(uint24 day, uint256 period) private view returns (Window memory w) {
        uint256 slot = _slotOf(day, period);
        uint256 state = _battles[bytes32(slot)];
        uint256 frozen = state >> _BG_TERM_TIER_SHIFT;
        if (frozen & _BG_TERMS_FROZEN == 0) {
            uint256 word = _dailyWordAt(day);
            if (word == 0 && period != _BONUS_PERIODS_PER_DAY - 1) revert RngNotReady();
            return _windowTermsOn(day, period, word);
        }
        // Opened terms survive word retirement in the existing scoreboard. Settlement
        // entropy still comes from the committed normal RNG cohort (or jackpot round).
        w.tier = frozen & 3;
        w.stakeUnits = (state >> _BG_STAKE_SHIFT) & _BSTAKE_MAX;
        if (w.tier != 0) {
            unchecked {
                uint256 bank = (uint256(0x119407080258) >> ((w.tier - 1) * 16)) & 0xffff;
                w.bankroll = uint128(bank);
                w.goal = uint128(bank * _SCHED_GOAL);
                w.played = bank / _SCHED_BANK_MULT;
            }
        }
        return _finishWindowTerms(day, period, w,
            frozen & _BG_TERM_HIGH_TAIL != 0 ? CrapsPriceLib.HIGH_TAIL : CrapsPriceLib.HIGH_BASE);
    }

    function _windowTermsOn(uint24 day, uint256 period, uint256 word) internal view returns (Window memory w) {
        (w.bankroll, w.goal, w.played, w.stakeUnits, w.tier) = _bonusPreset(_bonusRoll(word, period), period);
        return _finishWindowTerms(day, period, w, _highMultOf(word));
    }

    function runCrapsMaintenance(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != _GAME) revert OnlyGame();
        return _keepScheduled(allowance);
    }
    /// @notice Dedicated daily battle work, metered against the enclosing phase's remainder.
    function runDailyBattleWork(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != _GAME) revert OnlyGame();
        return _runDailyBattleWork(allowance);
    }

    function _runDailyBattleWork(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (allowance == 0) return result;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint64 slot = _activeJackpotSlot;
        if (_scheduledExpired(slot)) { result.done = true; return result; }
        uint256 board = _battles[bytes32(uint256(slot))];
        if (uint32(board) == uint32(board >> _BG_RESOLVED_SHIFT)) {
            result.done = true;
            return result;
        }
        if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX + _WORK_TAIL_GAS)) return result;
        uint256 childAllowance = _resolverAllowance(MineFlipGas.remaining(meter));
        result = IReadCohortLifecycle(address(this)).resolveRngSlot(slot, childAllowance);
        MineFlipGas.finish(meter);
    }

}
