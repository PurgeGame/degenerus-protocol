// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {CrapsProgressiveActions} from "./modules/CrapsProgressiveActions.sol";
import {CrapsLifecycleViews} from "./modules/CrapsLifecycleViews.sol";

import {EntropyLib} from "./libraries/EntropyLib.sol";
import {RngTags} from "./libraries/RngTags.sol";

import {MineFlipGas} from "./libraries/MineFlipGas.sol";
import {Craps} from "./Craps.sol";
import {ICoinflipStake, ICrapsEngine, IFlipCoin, IGameCraps} from "./CrapsInterfaces.sol";
import {CrapsBattleStorage} from "./storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {CrapsPriceLib} from "./libraries/CrapsPriceLib.sol";
import {CrapsPreferenceLib} from "./libraries/CrapsPreferenceLib.sol";
import {PriceLookupLib} from "./libraries/PriceLookupLib.sol";
import {IReadCohortLifecycle, IVaultOwnership} from "./CrapsInterfaces.sol";
import {JackpotBattleFieldLib} from "./libraries/JackpotBattleFieldLib.sol";
import {GameTimeLib} from "./libraries/GameTimeLib.sol";

interface IGameCrapsPending {

    function setCrapsRngPending_g1406(uint48 index, bool pending) external;
}

interface IFlipCrapsComps {
    function creditCrapsComps_g37225(uint256 amount) external;
}

/// @notice Lifecycle component inherited by CrapsBattle in the table storage context.
contract JackpotBattle is CrapsLifecycleViews, CrapsProgressiveActions {
    error BadJackpotField();
    error OnlyTableSelf();
    error CustomSlotsFull();
    error NothingToSeed();
    error ZeroDonation();
    /// @dev The Game's FLIP-per-price unit: `price / _PRICE_COIN_UNIT` FLIP buys one ticket.
    uint256 private constant _PRICE_COIN_UNIT = 1000;
    /// @dev Conservative whole-run loss budget, using the same 12% calibration as the ordinary
    ///      action subsidy. Separate constants keep future boost tuning from changing high comps.
    uint256 private constant _HIGH_LOSS_BPS = 1200;
    uint256 private constant _HIGH_COMP_SHARE_BPS = 8000;
    event JackpotBattleEntry(uint64 indexed slot, uint256 indexed betId, uint32 indexed playerId, uint256 units, uint32 chips);

    /// @notice Open a custom battle with validated immutable terms.
    /// @dev The creator roll is checked FIRST so a granted creator never pays for the
    ///      cross-contract call; the DGVE governance executor always qualifies, so the authority
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
        uint256 terms = _crapsCustomDefinition(
            played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult
        );
        unchecked { slot = uint64(_CUSTOM_SLOT_BASE + ++_customBattleCount); }
        _customBattle[slot] = terms;
        emit CrapsBattleCreated(slot, msg.sender, terms);
    }

    function closeBattle(uint64 slot) external returns (uint48 index) {
        uint256 c = _customBattle[slot];
        if (c == 0) revert NoSuchBattle();
        if (block.timestamp < ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusStillRunning();
        if (_slotIndexOf(slot) != 0) revert BonusPeriodSpent();
        bytes32 key = _rngBattleKey(slot);
        if (_loadBattle(key) == 0) revert BonusPeriodSpent();
        index = _writeBuffer();
        _setSlotIndex(slot, index + 1);
        IReadCohortLifecycle(address(this)).registerRngSlot_g709(index, slot, key);
        emit CrapsBonusArmed(key, uint48(slot), index);
    }

    function donate(bool custom, uint256 index, uint24 granules) external returns (uint256 amount) {
        uint256 slot;
        uint24 today;
        unchecked {
            if (custom) slot = _CUSTOM_SLOT_BASE + index;
            else {
                if (index >= _BONUS_PERIODS_PER_DAY) revert BonusPeriodSpent();
                today = _currentDayIndex();
                slot = _jackpotSlotOf(today, index);
            }
        }
        if (slot >= _CUSTOM_SLOT_BASE) {
            uint256 c = _customBattle[slot];
            if (c == 0) revert NoSuchBattle();
            if (block.timestamp >= ((c >> _CB_CLOSE_SHIFT) & _CB_CLOSE_MASK)) revert BonusPeriodSpent();
        } else if (!_scheduledAdmissionsOpen()) {
            revert BonusPeriodSpent();
        } else if (_jackpotIsJackpotSlot(slot)) {
            if (slot != _jackpotSlotOf(_bonus - 1, _BONUS_PERIODS_PER_DAY - 1)
                || IGameCraps(_GAME).rngLocked()) revert BonusPeriodSpent();
        } else {
            (,, uint256 live) = _jackpotCurrentBonusSlot(today);
            if (slot < live) revert BonusPeriodSpent();
        }
        if (_slotIndexOf(slot) != 0) revert BonusPeriodSpent();
        bytes32 key = _rngBattleKey(uint64(slot));
        uint256 g = _loadBattle(key);
        if (slot < _CUSTOM_SLOT_BASE && !_jackpotIsJackpotSlot(slot)
            && g >> 255 == 0 && _dailyWordAt(today) == 0) revert RngNotReady();
        if (slot < _CUSTOM_SLOT_BASE && g == 0) revert BonusPeriodSpent();
        if (granules == 0) revert ZeroDonation();
        if (g == 0) revert NothingToSeed();
        uint256 seed;
        unchecked {
            seed = ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK) + granules;
            amount = uint256(granules) * _BATTLE_STAKE_UNIT;
        }
        if (seed > _BG_SEED_MASK) revert SeedAboveMax();
        if (msg.sender == ContractAddresses.VAULT) {
            IFlipCoin(ContractAddresses.COIN).burnCoinForCraps_g292454(
                ContractAddresses.VAULT, _VAULT_ID, (amount << 8) | _CRAPS_FLAG_COMP
            );
        } else IFlipCoin(ContractAddresses.COIN).burnCoin_g27673(msg.sender, amount);
        _storeBattle(key, (g & ~(_BG_SEED_MASK << _BG_SEED_SHIFT)) | (seed << _BG_SEED_SHIFT));
        emit CrapsBonusDonated(key, msg.sender, amount, seed * _BATTLE_STAKE_UNIT);
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
            uint256 heat = (_loadHighField(key) >> _HF_HOTTEST_SHIFT) & _HF_HOTTEST_MASK;
            if (heat != 0 && pot != 0) {
                uint256 seed = uint256(EntropyLib.hash3(RngTags.CRAPS_DICE, word, uint256(slot)));
                uint256 n = uint32(_loadBattle(key));
                uint256 start = uint256(EntropyLib.hash2(RngTags.CRAPS_SHOOTER, seed)) % n;
                uint256 seat = 1 + (start + 511 - (heat & 511)) % n;
                uint256 daySlot = uint256(slot) / _BONUS_SLOTS_PER_DAY * _BONUS_SLOTS_PER_DAY;
                uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0 : uint32(_loadDayTickets(daySlot));
                uint256 ownN = n - dayN - (_roundExists(slot) ? _jackpotRounds[slot & 511].drawnCount : 0);
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


    /// @notice Drain the committed read FIFO within `allowance`.
    function runCrapsReadWork(uint48 index, uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        return _keepRngCohort(index, allowance);
    }

    function _keepRngCohort(uint48 index, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (index > 1) revert BadJackpotField();
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint64[] storage slots = _rngSlots[index];
        uint64 pos = _rngCursor(index);
        if (pos == slots.length) { result.done = true; return result; }
        if (_readCrapsStage() != 6) return result;
        uint256 gameState = _gameState();
        if (_wordAt(index, gameState) == 0) return result;
        for (uint256 steps; pos < slots.length && steps < _KEEP_MAX_HOPS; ++steps) {
            if (!MineFlipGas.canRun(meter, _MAINTENANCE_GAS_MAX, _WORK_TAIL_GAS)) break;
            uint64 slot = slots[pos];
            if (_scheduledExpired(slot, _currentDayIndex(gameState))) {
                _completeRngSlot(slot, index);
                ++pos;
                result.progressed = true;
                MineFlipGas.markProgress(meter);
                emit CrapsScheduledExpired(slot);
                continue;
            }
            if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX + _WORK_TAIL_GAS)) break;
            uint256 childAllowance = MineFlipGas.child(meter, _WORK_TAIL_GAS + 30_000);
            MineFlipGas.Result memory child = IReadCohortLifecycle(address(this)).resolveRngSlot_g1079(slot, childAllowance);
            result.progressed = result.progressed || child.progressed;
            if (child.progressed) MineFlipGas.markProgress(meter);
            result.rewardBasis += child.rewardBasis;
            if (child.done) ++pos;
            // One field per batch preserves the established finalization boundary.
            break;
        }
        // Final-seat settlement and expiry advance the stored head atomically.
        result.done = pos == slots.length;
        MineFlipGas.finish(meter);
    }

    function admitCustom(uint64 slot) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        for (uint256 i; i < 4; ++i) {
            if (_fundedCustomSlots[i] == 1) { _fundedCustomSlots[i] = slot; return; }
        }
        revert CustomSlotsFull();
    }

    function registerRngSlot_g709(uint48 index, uint64 slot, bytes32 key) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        if (uint32(_loadBattle(key)) == 0) return;
        if (index > 1) revert BadJackpotField();
        uint64[] storage slots = _rngSlots[index];
        bool empty = _rngCursor(index) == slots.length;
        if (empty) {
            assembly ("memory-safe") { sstore(slots.slot, 0) }
            _rngSlotCursor[index] = 1;
        }
        slots.push(slot);
        if (empty) {
            IGameCrapsPending(ContractAddresses.GAME).setCrapsRngPending_g1406(index, true);
        }
    }

    function _completeRngSlot(uint64 slot, uint48 index) private {
        // Only the read FIFO's head can finish: either its final seat calls us
        // through finalizeBattle, or the read worker retires an expired field.
        // Commit before notifying Game so the callback observes a drained FIFO.
        uint64 next = _rngCursor(index) + 1;
        _rngSlotCursor[index] = next + 1;
        if (next == _rngSlots[index].length) {
            IGameCrapsPending(ContractAddresses.GAME).setCrapsRngPending_g1406(index, false);
        }
        if (slot >= _CUSTOM_SLOT_BASE) {
            for (uint256 i; i < 4; ++i) {
                if (_fundedCustomSlots[i] == slot) { _fundedCustomSlots[i] = 1; return; }
            }
        }
    }

    /// @param pool The recorded prize pool the Added allocation is drawn from, in wei.
    /// @param level The Game's level at the request: it prices the pool in FLIP and picks the floor.
    /// @return locked True when a round is active for the daily phase: this one, a retry's or an
    ///         unfinished prior one. False for a window day before the first window day.
    function lockJackpotBattle(uint24 requestDay, uint256 pool, uint24 level) external returns (bool locked) {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        locked = true;
        uint24 today = _currentDayIndex();
        if (_activeJackpotSlot != 0 && !_scheduledExpired(_activeJackpotSlot, today)) {
            JackpotRound storage prior = _jackpotRounds[_activeJackpotSlot & 511];
            // A retry never changes the field, allocation or request identity.
            uint256 priorBoard = _loadBattle(bytes32(uint256(_activeJackpotSlot)));
            if (prior.requestDay == requestDay || !prior.started
                || uint32(priorBoard >> _BG_RESOLVED_SHIFT) != uint32(priorBoard)) return locked;
        }
        uint256 day = _bonus == 0 ? 0 : _bonus - 1;
        uint64 slot = uint64(day * _BONUS_SLOTS_PER_DAY + _BONUS_PERIODS_PER_DAY);
        // Warm-up/skipped days have no paid field. Their free-only draw uses the unused
        // remainder-seven namespace, so lapsed reservations remain available to their refund walk.
        bool detached = _scheduledExpired(slot, today) || _loadBudget(uint24(day)) == 0 || _slotIndexOf(slot) != 0;
        uint256 windowDay = detached ? uint256(requestDay) - 1 : day;
        // No round, award or reserve funding exists before the first window day.
        if (windowDay < _firstWindowDay) return false;
        if (detached) slot = uint64(windowDay * _BONUS_SLOTS_PER_DAY + 7);
        JackpotRound storage r = _jackpotRounds[slot & 511];
        if (_roundExists(slot)) return locked;
        bytes32 key = bytes32(uint256(slot));
        uint256 g = _loadBattle(key);
        if (!detached) {
            uint256 tickets = _loadDayTickets(day * _BONUS_SLOTS_PER_DAY);
            g += uint32(tickets);
            uint256 high = (tickets >> (_DT_HIGH_SHIFT * _BONUS_PERIODS_PER_DAY)) & _MASK32;
            if (high != 0) _storeHighField(key, _loadHighField(key) + (high));
        }
        // An opened battle already holds its advertised fee. Only detached award-only
        // rounds need neutral terms; OR-ing the old constant into a drawn fee corrupts it.
        uint256 entryPrice = detached ? _JACKPOT_PRICE : ((g >> _BG_STAKE_SHIFT) & _BSTAKE_MAX) * _BATTLE_STAKE_UNIT;
        if (detached) g |= (entryPrice / _BATTLE_STAKE_UNIT) << _BG_STAKE_SHIFT;
        _storeBattle(key, g);
        _setSlotIndex(slot, type(uint48).max);
        // Floor the baseline first. Awards depend on that baseline alone, and are frozen
        // in the same packed word as the fee/counts before any settlement word exists.
        uint256 added = CrapsPriceLib.jackpotAdded(pool * _PRICE_COIN_UNIT / (PriceLookupLib.priceForLevel(level) * 200), level);
        uint256 target = added / CrapsPriceLib.JACKPOT_AWARD_VALUE;
        // Degenesis battles run with their paid field only.
        uint256 awardTarget = windowDay < GameTimeLib.MAIN_LAUNCH_DAY ? 0 : (target > 500 ? 500 : target);
        added = added * entryPrice / _JACKPOT_PRICE;
        uint256 paidCount = uint32(g);
        uint256 highMult = detached ? 1 : (g >> _BG_TERM_TIER_SHIFT & _BG_TERM_HIGH_TAIL != 0
            ? CrapsPriceLib.HIGH_TAIL : CrapsPriceLib.HIGH_BASE);
        uint256 paidUnits = paidCount + uint32(_loadHighField(key)) * (highMult - 1);
        // Replace every packed word, including padding. Old entropy is hidden until preparation.
        // The pre-start bankroll sentinel retains word 2 even when no paid seat exists.
        assembly ("memory-safe") {
            sstore(add(r.slot, 1), added)
            sstore(add(r.slot, 2), or(shl(128, paidUnits), shl(192, 1)))
            sstore(add(r.slot, 3), shl(232, requestDay))
            sstore(add(r.slot, 4), or(or(shl(32, paidCount), shl(128, awardTarget)),
                or(shl(160, entryPrice), shl(232, shr(3, slot)))))
        }
        _activeJackpotSlot = slot;
        uint256 contribution = added / _HIGH_RESERVE_DIVISOR;
        _highRollerReserve += contribution;
        emit HighRollerReserveFunded(slot, contribution, _highRollerReserve - 1);
        emit JackpotBattleLocked(slot, requestDay, added, paidCount);
    }

    /// @notice Initialize a resumable draw, returning its frozen word, cursor and units still wanted.
    /// @dev The target was frozen from the unscaled baseline at lock; paid volume adds no free units.
    function prepareJackpotBattle(uint24 level, uint256 word)
        external returns (uint256 drawWord, uint256 cursor, uint256 remaining)
    {
        if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
        if (_scheduledExpired(_activeJackpotSlot)) return (word, 0, 0);
        JackpotRound storage r = _prepare(level, word);
        return (r.drawWord, r.drawCursor & ~_ROUND_PREPARED, r.awardTarget - r.drawnUnits);
    }

    function _prepare(uint24 level, uint256 word) private returns (JackpotRound storage r) {
        r = _jackpotRounds[_activeJackpotSlot & 511];
        if (r.requestDay == 0 || word == 0) revert BadJackpotField();
        // A resumed draw keeps the word and level frozen when it began.
        if (r.drawCursor & _ROUND_PREPARED != 0) return r;
        uint256 roll = EntropyLib.hash2(RngTags.CRAPS_JACKPOT_MULT, word) % 1_000;
        uint256 multiplier = roll < 900 ? 5_000 : roll < 990 ? 30_000 : roll < 999 ? 200_000 : 1_000_000;
        // The reserve and award target were committed at lock. This independently tagged
        // draw changes only the main subsidy, with 60/30/9/1 odds and an exact 1x mean.
        uint256 subsidyBps = _subsidyMultiplier(EntropyLib.hash2(RngTags.CRAPS_SUBSIDY, word));
        uint256 mainAdded = r.added - r.added / _HIGH_RESERVE_DIVISOR;
        mainAdded = mainAdded * subsidyBps / 10_000;
        uint256 pool = (uint256(r.paidUnits) * r.entryPrice + mainAdded) * multiplier / 10_000;
        // At the 6,000 fee and both minimum rolls, awarded capital is still >=890
        // per seat before the bankroll split: every nonempty field retains >=300.
        r.totalPool = uint128(pool);
        r.multiplierBps = uint32(multiplier);
        r.subsidyMultiplierBps = uint32(subsidyBps);
        r.level = level;
        r.drawWord = word;
        r.drawCursor = _ROUND_PREPARED;
        emit JackpotSubsidyRolled(_activeJackpotSlot, uint32(subsidyBps), mainAdded);
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
        JackpotRound storage r = _jackpotRounds[slot & 511];
        if (r.drawCursor & _ROUND_PREPARED == 0 || r.started || field.length > JackpotBattleFieldLib.MAX_CHUNK) {
            revert BadJackpotField();
        }
        // No external calls occur while appending: commit the cursor before the loop
        // so the packed write does not keep another live stack value across every entry.
        r.drawCursor = uint208(cursor) | _ROUND_PREPARED;
        uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0
            : uint32(_loadDayTickets((uint256(slot) / _BONUS_SLOTS_PER_DAY) * _BONUS_SLOTS_PER_DAY));
        uint256 ownN = r.paidCount - dayN;
        uint256 units = r.drawnUnits;
        uint256 drawn = r.drawnCount;
        // lockJackpotBattle derives this scheduled slot from the opened or requested day.
        // It cannot be future-dated; the expiry check above rejects a recycled day bank.
        // Every appended ID has this same day, so no per-seat Game callback is needed.
        for (uint256 i; i < field.length && units < r.awardTarget; ++i) {
            uint256 entry = field[i];
            uint32 playerId = uint32(entry);
            // A malformed or empty entry forfeits its award rather than halting the advance.
            if (entry >> JackpotBattleFieldLib.UNITS_SHIFT != 1 || playerId == 0) continue;
            uint256 id = (uint256(slot) << 64) | (ownN + ++drawn);
            ++units;
            (uint32 chips,) = CrapsPreferenceLib.decode(
                entry >> (JackpotBattleFieldLib.BOARD_SHIFT - CrapsPreferenceLib.SHIFT));
            _appendScheduledBet(id, uint256(playerId) | (uint256(chips) << _BET_CHIPS_SHIFT));
            emit JackpotBattleEntry(slot, id, playerId, 1, chips);
        }
        r.drawnCount = uint32(drawn);
        r.drawnUnits = uint32(units);
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
            // The largest bankroll unit multiple whose scheduled round fits one uint24 leg.
            uint256 maxBank = (uint256(type(uint24).max) * 5 / 2 / _JACKPOT_BANKROLL_UNIT) * _JACKPOT_BANKROLL_UNIT;
            if (bankroll > maxBank) bankroll = maxBank;
            bounty = (perUnit - bankroll) / _BATTLE_STAKE_UNIT;
            if (bounty > bankroll / _BATTLE_STAKE_UNIT) bounty = bankroll / _BATTLE_STAKE_UNIT;
            if (bounty > _BSTAKE_MAX) bounty = _BSTAKE_MAX;
        }
        r.bankroll = uint32(bankroll);
        r.bountyUnits = uint32(bounty);
        r.potRemainder = uint128(mainPool - totalUnits * (bankroll + bounty * _BATTLE_STAKE_UNIT));
        bytes32 key = bytes32(uint256(slot));
        _storeBattle(key, ((_loadBattle(key) + drawn) & ~(_BSTAKE_MAX << _BG_STAKE_SHIFT))
            | (bounty << _BG_STAKE_SHIFT));
        r.started = true;
        emit JackpotBattleStarted(slot, r.level, drawn, units, r.drawWord);
        _bookFees(slot, r, totalUnits * bankroll, mainPool, uint32(_loadHighField(key)));
        // An empty field has no seat that could finish it through the normal resolver.
        if (totalUnits == 0) _settleHighRollerReserve(slot);
    }

    /// @notice The table's post-batch hook, reached through its self-call.
    /// @dev No caller-supplied candidate, count, randomness or cursor is trusted.
    function settleHighRollerReserve(uint64 slot) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _settleHighRollerReserve(slot);
    }

    struct ReserveDrawWork {
        HighRollerDraw draw;
        uint256 settled;
        uint256 end;
        uint256 daySlot;
        uint256 ownN;
    }

    function _settleHighRollerReserve(uint64 slot) private {
        if (_scheduledExpired(slot)) return;
        JackpotRound storage r = _jackpotRounds[slot & 511];
        if (!r.started) revert BadJackpotField();
        ReserveDrawWork memory c;
        c.draw = _loadHighDraw(slot);
        if (c.draw.resolved) return;
        c.settled = _bonusCursorOf(slot);
        c.end = c.settled < r.paidCount ? c.settled : r.paidCount;
        {
        c.daySlot = uint256(slot) / _BONUS_SLOTS_PER_DAY * _BONUS_SLOTS_PER_DAY;
        uint256 dayN = slot % _BONUS_SLOTS_PER_DAY == 7 ? 0 : uint32(_loadDayTickets(c.daySlot));
        c.ownN = r.paidCount - dayN;
        // Reservoir sampling: contender n replaces the nominee with probability 1/n. Counts
        // and the nominee survive chunk boundaries, and the canonical seat order never changes.
        // Every high seat has one ticket, regardless of its multiple, dice or activity history.
        for (uint256 seat = uint256(c.draw.cursor) + 1; seat <= c.end; ++seat) {
            bool daySeat = seat > c.ownN;
            uint256 id = daySeat ? (c.daySlot << 64) | (seat - c.ownN) : (uint256(slot) << 64) | seat;
            uint256 header = _loadBet(id);
            uint256 highBit = daySeat ? _BET_HIGH_BIT << (_BONUS_PERIODS_PER_DAY - 1) : _BET_HIGH_BIT;
            uint32 playerId = uint32(header);
            if (header & highBit == 0 || playerId == _SDGNRS_ID) continue;
            ++c.draw.eligible;
            if (EntropyLib.hash3(RngTags.CRAPS_RESERVE_WINNER, r.drawWord, (uint256(slot) << 32) | c.draw.eligible) % c.draw.eligible == 0) {
                c.draw.nominee = playerId;
            }
        }
        }
        c.draw.cursor = uint32(c.end);
        uint256 amount;
        if (c.settled == uint256(r.paidCount) + r.drawnCount) {
            c.draw.resolved = true;
            if (c.draw.eligible != 0 && EntropyLib.hash3(RngTags.CRAPS_RESERVE_DRAW, r.drawWord, slot) % _HIGH_RESERVE_CHANCE == 0) {
                c.draw.won = true;
                amount = _highRollerReserve - 1;
                _highRollerReserve = 1;
            }
            emit HighRollerReserveDrawn(slot, c.draw.eligible, c.draw.won ? c.draw.nominee : 0, amount, _highRollerReserve - 1);
        }
        // Effects precede the existing Coinflip credit call. Awards never feed action or comps,
        // never receive a pool multiplier, and never convert to additional pass grants.
        _storeHighDraw(slot, c.draw);
        if (amount != 0) _creditFlip(c.draw.nominee, amount);
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
            _storeDayStaked(uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY), _loadDayStaked(uint24(uint256(slot) / _BONUS_SLOTS_PER_DAY)) + (staked + (high << _DAY_HIGH_SHIFT)));
        }
        uint256 highFees = (uint256(r.paidUnits) - paidCount) * r.entryPrice;
        uint256 atRisk = highSeats == 1 ? highFees : highFees / 2;
        uint256 lossBudget = atRisk * _HIGH_LOSS_BPS / _BPS_DENOMINATOR;
        uint256 highComps = lossBudget * _HIGH_COMP_SHARE_BPS / _BPS_DENOMINATOR;
        uint256 earned = staked / 50;
        earned += highComps;
        if (earned != 0) IFlipCrapsComps(ContractAddresses.COIN).creditCrapsComps_g37225(earned);
        if (highFees != 0) emit JackpotHighCompsAccrued(slot, highFees, atRisk, lossBudget, highComps);
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
        uint256 normals = word & _PASS_MAX;
        if (normals < cost) revert InsufficientPassCredits();
        unchecked { normals -= cost; }
        _passCreditsById[id] =
            (word & ~(_PASS_MAX | (_PASS_MAX << _PASS_HIGH_SHIFT))) | (highs << _PASS_HIGH_SHIFT) | normals;
        emit CrapsNormalPassesConverted(id, cost, highCount);
    }

    function upgradeReservedDay(uint32 id, uint24 day) external {
        if (!_reservableDay(day)) revert DayNotReservable();
        id = _accountId(id);
        uint256 daySlot = _jackpotDaySlotOf(day);
        uint256 seat = _loadDaySeat(daySlot, id) & _MASK32;
        if (seat == 0) revert NoSuchBet();
        uint256 betId = (daySlot << 64) | seat;
        uint256 header = _loadBet(betId);
        if (header & _BET_DAYHIGH_MASK != 0) revert NothingToUpgrade();
        _takeCredits(id, true, 1);
        _credit(id, false, 1);
        _storeBet(betId, header | _BET_DAYHIGH_MASK);
        unchecked {
            _storeDayTickets(daySlot, _loadDayTickets(daySlot) + (_DT_ALL_HIGH));
        }
        emit CrapsDayWindowsUpgraded(id, day, uint8(_BET_DAYHIGH_MASK >> _BET_HIGH_SHIFT), 0);
    }

    /// @dev The pass doors' account: `id == 0` is the caller, by its existing wallet ID; any other
    ///      `id` must be allocated (the Game's resolution reverts otherwise) and the caller
    ///      authorized for it. These doors move only ID-keyed credits and seats, so neither the
    ///      key nor the payee is needed.
    function _accountId(uint32 id) private returns (uint32) {
        if (id == 0) return uint32(_walletWord(msg.sender, false) >> CrapsPreferenceLib.ID_SHIFT);
        (,, bool authorized) = IGameCraps(_GAME).resolveAccount_g7029(id, msg.sender);
        if (!authorized) revert NotApproved();
        return id;
    }



    /// @dev Self-only finalization executes atomically inside the last seat.
    function finalizeBattle_g3665(Window calldata w, uint256 board, uint256 word) external {
        if (msg.sender != address(this)) revert OnlyTableSelf();
        _payout(w, board, word);
        // Preserve payout-before-completion ordering in the same self-call.
        // Dedicated daily jackpot fields do not belong to the normal read cohort.
        if (!_jackpotIsJackpotSlot(w.bound)) {
            uint48 index;
            unchecked { index = _slotIndexOf(w.bound) - 1; }
            _completeRngSlot(w.bound, index);
        }
    }









    function _creditComps(uint256 amount) private {
        IFlipCoin(ContractAddresses.COIN).creditCrapsComps_g37225(amount);
    }

    function _creditFlip(uint32 id, uint256 amount) private {
        ICoinflipStake(ContractAddresses.COINFLIP).creditFlip_g317(id, amount);
    }



















    function _payout(Window memory w, uint256 g, uint256 word) private {
        unchecked {
            uint256 slot = w.bound;
            uint256 entrants = g & _MASK32;
            // The main boost is shared by the finalization log and the payout. Its derivation
            // reads the day's budget and hashes the settling word, so compute it once here.
            uint256 boost = _jackpotRoundBoost(_jackpotBoostUnits(w, word));
            bool scheduled = slot < _CUSTOM_SLOT_BASE;
            uint256 best = (g >> _BG_BEST_SHIFT) & _SC_BEST_MASK;
            (Craps.SlipStop stop,, uint256 peakFlip, uint256 endFlip) = _jackpotDecodeBest(best);
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
            uint256 f = _loadHighField(w.key);
            // The jackpot battle's comp share is paid on its fees alone when its field seals.
            if (!_jackpotIsJackpotSlot(slot)) {
                uint256 highSeats = uint32(f);
                uint256 eligible = uint256(w.bankroll) * (entrants + w.extraUnits);
                if (highSeats != 0) eligible += uint256(w.bankroll) * highSeats * (w.highMult - 1);
                uint256 earned = eligible / 50;
                if (earned != 0) _creditComps(earned);
            }
            // The winning seat is an index into the same own-then-day range the settle walk used,
            // so naming it takes the same mapping back.
            (uint256 dayBase, uint64 dayN) = _jackpotDayField(slot);
            uint64 ownN = uint64(entrants) - dayN - w.drawn;

            uint64 seat = uint64(uint32(g >> _BG_WINNER_SHIFT));
            uint256 winnerId = _jackpotSeatId(slot, seat, ownN, dayBase, dayN);
            uint256 winnerWord = _loadBet(winnerId);
            // The boost: this table's own pick from the band the window advertised, plus anything
            // donated on top of it. Nothing about either was stored.
            // Donations pay in full and bypass protocol-bonus rounding.
            uint256 donated = (g >> _BG_SEED_SHIFT) & _BG_SEED_MASK;
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
                uint256 hId = _jackpotSeatId(slot, seat, ownN, dayBase, dayN);
                uint256 hWord = _loadBet(hId);
                _storeHighField(w.key, f | _HF_DONE_BIT);
                uint256 lane = _jackpotLaneBoost(w, word);
                // The extra bounties are the seats' own posted money and pay out whole; only the
                // lane boost is protocol money, so only it can pay in passes.
                uint32 hWinner = uint32(hWord);
                uint256 lanePot = heads * _jackpotHighBounty(w) + lane
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
                _jackpotPayProgressive(w, peakFlip, score, winnerId, winnerWord);
                _recordDiceRun(uint32(winnerWord), score);
            }
        }
    }



    function _recordDiceRun(uint32 winner, uint256 score) private {
        if (score >= _DICE_RUN_RECORD_FLOOR) {
            ICoinflipStake(ContractAddresses.COINFLIP).armDiceRunRecord(winner, score);
        }
    }









    function _jackpotArmSlot(uint64 slot, Window memory w, uint48 index) internal {
        unchecked {
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
                uint256 tickets = _loadDayTickets(_jackpotDaySlotOf(uint256(slot) / _BONUS_SLOTS_PER_DAY));
                if (uint32(tickets) != 0) _storeBattle(w.key, _loadBattle(w.key) + (uint32(tickets)));
                uint256 dayHigh = (tickets >> (_DT_HIGH_SHIFT * (uint256(slot) % _BONUS_SLOTS_PER_DAY))) & _MASK32;
                if (dayHigh != 0) _storeHighField(w.key, _loadHighField(w.key) + (dayHigh));
            }
        }
        // The shut window joins the write buffer's RNG round like any other consumer: the next
        // request, daily or mid-day, settles it. Its pending bit counts as work for that request.
        IReadCohortLifecycle(address(this)).registerRngSlot_g709(index, slot, w.key);
        emit CrapsBonusArmed(w.key, uint48(slot), index);
    }









    function _keepScheduled(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint8 stage = _readCrapsStage();
        uint256 gameState = _gameState();
        uint48 read = _writeBuffer(gameState) ^ 1;
        // Before the first session, maintenance creates the commitments that request seals.
        // A live read cohort, locked day or earlier consumer always blocks admission work.
        if (stage != 7 && !(stage == 0 && uint8(gameState >> 152) == 0
            && _rngCursor(read) == _rngSlots[read].length && _wordAt(read, gameState) == 0)) return result;
        uint64 cur = _minerSlot;
        uint24 today = _currentDayIndex(gameState);
        if (_scheduledExpired(cur, today)) {
            // Bounded catch-up after a long outage. No expired seat is read or refunded.
            emit CrapsScheduledExpired(cur);
            cur = uint64((uint256(today) - _SETTLEMENT_DAYS) * _BONUS_SLOTS_PER_DAY);
        }
        (,, uint256 open) = _jackpotCurrentBonusSlot(today);
        for (uint256 hops; hops < _KEEP_MAX_HOPS; ++hops) {
            if (!MineFlipGas.canRun(meter, _MAINTENANCE_GAS_MAX, _WORK_TAIL_GAS)) break;
            uint24 day = uint24(uint256(cur) / _BONUS_SLOTS_PER_DAY);
            if (cur % _BONUS_SLOTS_PER_DAY == 0) {
                if (_loadBudget(day) != 0) { ++cur; continue; }
                if (day >= today) { result.done = true; break; }
                (bool doneAll, bool moved) = _sweepLapsedDay(cur, day, meter);
                result.progressed = moved;
                if (doneAll) cur += uint64(_BONUS_SLOTS_PER_DAY);
                break;
            }
            if (cur % _BONUS_SLOTS_PER_DAY > _BONUS_PERIODS_PER_DAY) { ++cur; continue; }
            if (_slotIndexOf(cur) == 0) {
                if (cur >= open || _jackpotIsJackpotSlot(cur)) { result.done = true; break; }
                if ((_loadBattle(bytes32(uint256(cur))) >> _BG_TERM_TIER_SHIFT) & _BG_TERMS_SKIPPED != 0) {
                    (bool refunded, bool moved) = _refundSkippedWindow(cur, meter);
                    result.progressed = result.progressed || moved;
                    if (!refunded) break;
                    ++cur;
                    continue;
                }
                Window memory w = _jackpotWindowTerms(day, (uint256(cur) % _BONUS_SLOTS_PER_DAY) - 1);
                _jackpotArmSlot(cur, w, read ^ 1);
                result.progressed = true;
                MineFlipGas.markProgress(meter);
                // Re-examine the armed slot: a field ends maintenance (done) so the same miner
                // call can request its word; an empty one steps on to the next head.
                continue;
            }
            uint256 g = _loadBattle(bytes32(uint256(cur)));
            uint256 entrants = uint32(g);
            if (entrants == 0 || uint32(g >> _BG_RESOLVED_SHIFT) == entrants) { ++cur; continue; }
            // Committed settlement is exclusively the read FIFO; daily battles have their own tx.
            result.done = true;
            break;
        }
        if (cur != _minerSlot) { _minerSlot = cur; result.progressed = true; MineFlipGas.markProgress(meter); }
        result.rewardBasis = result.progressed ? 1 : 0;
        MineFlipGas.finish(meter);
    }

    /// @dev A late daily opening never runs expired periods. Refund their prepaid window
    ///      reservations under the same comp policy as an entirely unopened day.
    function _refundSkippedWindow(uint64 slot, MineFlipGas.Meter memory meter)
        private returns (bool doneAll, bool moved)
    {
        uint64 n = uint32(_loadBattle(bytes32(uint256(slot))));
        uint64 done = _bonusCursorOf(slot);
        uint256 comps;
        while (done < n && MineFlipGas.canRun(meter, _REFUND_GAS_MAX, _SWEEP_TAIL_GAS)) {
            uint256 header = _loadBet((uint256(slot) << 64) | ++done);
            comps += _jackpotWindowAheadPrice(slot % _BONUS_SLOTS_PER_DAY - 1, header & _BET_HIGH_BIT != 0);
            moved = true;
            MineFlipGas.markProgress(meter);
        }
        if (moved) _setBonusCursor(slot, done);
        if (comps != 0) _creditComps(comps);
        return (done == n, moved);
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
            uint64 n = slot == daySlot_ ? uint32(_loadDayTickets(slot)) : uint32(_loadBattle(bytes32(slot)));
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
                else comps += _jackpotWindowAheadPrice(slot - daySlot_ - 1, high);
                moved = true;
                MineFlipGas.markProgress(meter);
            }
            if (done != _bonusCursorOf(slot)) _setBonusCursor(slot, done);
        }
        if (comps != 0) _creditComps(comps);
        emit CrapsDayLapsed(day, uint32(_loadDayTickets(daySlot_)));
        return (true, moved);
    }







    function runCrapsMaintenance_g10712(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != _GAME) revert OnlyGame();
        return _keepScheduled(allowance);
    }
    /// @notice Dedicated daily battle work, metered against the enclosing phase's remainder.
    function runDailyBattleWork(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        if (msg.sender != _GAME) revert OnlyGame();
        return _runDailyBattleWork(allowance);
    }

    function _runDailyBattleWork(uint256 allowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint64 slot = _activeJackpotSlot;
        if (_scheduledExpired(slot)) { result.done = true; return result; }
        uint256 board = _loadBattle(bytes32(uint256(slot)));
        if (uint32(board) == uint32(board >> _BG_RESOLVED_SHIFT)) {
            result.done = true;
            return result;
        }
        if (!MineFlipGas.canRun(meter, _SEAT_GAS_MAX, _SETTLE_TAIL_GAS + _CREDIT_GAS_MAX + _WORK_TAIL_GAS)) return result;
        uint256 childAllowance = MineFlipGas.child(meter, _WORK_TAIL_GAS + 30_000);
        result = IReadCohortLifecycle(address(this)).resolveRngSlot_g1079(slot, childAllowance);
        MineFlipGas.finish(meter);
    }
    function _crapsCustomDefinition(uint32 played, uint8 bankMult, uint16 goalMult, uint24 stakeUnits,
        uint40 closeTime, bool multiEntry, uint16 highRollerMult) internal view virtual returns (uint256)
    {
        return ICrapsEngine(ContractAddresses.CRAPS_ENGINE).customDefinition(
            played, bankMult, goalMult, stakeUnits, closeTime, multiEntry, highRollerMult);
    }
}
