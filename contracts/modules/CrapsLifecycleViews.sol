// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {Craps} from "../Craps.sol";
import {CrapsPriceLib} from "../libraries/CrapsPriceLib.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {RngTags} from "../libraries/RngTags.sol";

import {CrapsBattleStorage} from "../storage/CrapsBattleStorage.sol";

abstract contract CrapsLifecycleViews is CrapsBattleStorage {
    function jackpotProgress() external view returns (uint64 slot, uint256 added, bool started, bool complete) {
        slot = _activeJackpotSlot;
        JackpotRound storage r = _jackpotRounds[slot & 511];
        added = r.added;
        if (slot != 0 && _scheduledExpired(slot)) return (slot, added, true, true);
        started = r.started;
        // The only writer assigns a scheduled day slot: day * 8 + 6, or + 7 for a detached round.
        uint256 g = _loadBattle(bytes32(uint256(slot)));
        complete = started && uint32(g >> _BG_RESOLVED_SHIFT) == uint32(g);
    }
    function _rngBattleKey(uint64 slot) internal view returns (bytes32) {
        if (slot < _CUSTOM_SLOT_BASE) return bytes32(uint256(slot));
        uint256 c = _customBattle[slot];
        uint256 played = (c & _CB_PLAYED_MASK);
        uint256 bank = uint128(played * ((c >> _CB_BANK_SHIFT) & _CB_BANK_MASK));
        uint256 goal = uint128(bank * ((c >> _CB_GOAL_SHIFT) & _CB_GOAL_MASK));
        uint256 terms = ((c >> _CB_STAKE_SHIFT) & _BSTAKE_MAX)
            | (((c >> _CB_HIGH_SHIFT) & _CB_HIGH_MASK) << _TERM_HIGH_SHIFT);
        return keccak256(abi.encode(BATTLE_TAG, uint48(slot), bank, goal, played, terms));
    }

    /// @dev The jackpot's hidden main-subsidy multiplier in bps: 60/30/9/1 odds, mean exactly 1x.
    function _subsidyMultiplier(uint256 entropy) internal pure returns (uint256) {
        uint256 roll = entropy % 100;
        return roll < 60 ? 2_500 : roll < 90 ? 10_000 : roll < 99 ? 50_000 : 100_000;
    }

    function _jackpotDaySlotOf(uint256 day) internal pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY;
        }
    }

    function _jackpotBonusRoll(uint256 word, uint256 period) internal pure returns (uint256) {
        unchecked {
            return EntropyLib.hash3(RngTags.CRAPS_SCHEDULE, word, period == _BONUS_PERIODS_PER_DAY - 2 ? 0 : period);
        }
    }

    function _jackpotBoostBase(Window memory w) internal view returns (uint256) {
        return _jackpotShareOf(w, false);
    }

    function _jackpotBoostMult(uint256 word, uint48 bound) internal pure returns (uint256) {
        unchecked {
            uint256 roll = EntropyLib.hash3(RngTags.CRAPS_BOOST, word, bound) % 1000;
            if (roll < 768) return 1;
            if (roll < 976) return 4;
            if (roll < 996) return 40;
            return 400;
        }
    }

    function _jackpotBoostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            // Multiplied in WEI and only then cut to granules. Flooring the base first would
            // round a small window's whole boost away — a thin day funds well under one granule
            // per window, and it is the top rungs that make such a window pay at all.
            return (_jackpotBoostBase(w) * _jackpotBoostMult(word, w.bound)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    function _jackpotDayField(uint256 slot) internal view returns (uint256 base, uint64 n) {
        if (slot >= _CUSTOM_SLOT_BASE || slot % _BONUS_SLOTS_PER_DAY == 7) return (0, 0);
        unchecked {
            uint256 d = _jackpotDaySlotOf(slot / _BONUS_SLOTS_PER_DAY);
            return (d << 64, uint32(_loadDayTickets(d)));
        }
    }

    function _jackpotDecodeBest(uint256 best)
        internal
        pure
        returns (Craps.SlipStop stop, uint256 peakFlip, uint256 endFlip)
    {
        unchecked {
            uint256 primary = (best >> _SC_PRIMARY_SHIFT) & _SC_PRIMARY_MASK;
            endFlip = (best >> _SC_WON_SHIFT) & _SC_WON_MASK;
            if (best & _SC_GOAL_BIT == 0) return (Craps.SlipStop.Bust, 0, endFlip);
            return (Craps.SlipStop.Goal, primary, endFlip);
        }
    }

    function _jackpotHighBase(Window memory w) internal view returns (uint256) {
        return _jackpotShareOf(w, true);
    }

    function _jackpotHighBoostUnits(Window memory w, uint256 word) internal view returns (uint256) {
        unchecked {
            return (_jackpotHighBase(w) * _jackpotBoostMult(word, w.bound)) / (4 * _BATTLE_STAKE_UNIT);
        }
    }

    function _jackpotHighBounty(Window memory w) internal pure returns (uint256) {
        unchecked { return w.highExtra != 0 ? w.highExtra : (w.highMult - 1) * w.stakeUnits * _BATTLE_STAKE_UNIT; }
    }

    function _jackpotIsJackpotSlot(uint256 slot) internal pure returns (bool) {
        return slot < _CUSTOM_SLOT_BASE && slot % _BONUS_SLOTS_PER_DAY >= _BONUS_PERIODS_PER_DAY;
    }

    function _jackpotLaneBoost(Window memory w, uint256 word) internal view returns (uint256) {
        return _jackpotRoundBoost(_jackpotHighBoostUnits(w, word)) * _BATTLE_STAKE_UNIT;
    }

    function _jackpotRoundBoost(uint256 units) internal pure returns (uint256) {
        if (units <= _BOOST_ROUND_ABOVE) return units;
        unchecked {
            return ((units + _BOOST_ROUND_STEP / 2) / _BOOST_ROUND_STEP) * _BOOST_ROUND_STEP;
        }
    }

    function _jackpotSeatId(uint256 slot, uint64 seat, uint64 ownN, uint256 dayBase, uint64 dayN)
        internal pure returns (uint256)
    {
        // Both counts come from uint32 fields. The sum fits uint64, and each
        // subtraction is guarded by the preceding ordinal comparisons.
        unchecked {
            if (seat <= ownN) return (slot << 64) | seat;
            if (seat <= ownN + dayN) return dayBase | (seat - ownN);
            return (slot << 64) | (seat - dayN);
        }
    }

    function _jackpotShareOf(Window memory w, bool high) internal view returns (uint256) {
        if (w.bound >= _CUSTOM_SLOT_BASE || _jackpotIsJackpotSlot(w.bound)) return 0;
        unchecked {
            uint256 slot = uint256(w.bound);
            uint24 day = uint24(slot / _BONUS_SLOTS_PER_DAY);
            uint256 packed = _loadBudget(day);
            uint256 budget = (high ? packed >> 112 : packed) & _BUDGET_MASK;
            return _jackpotWindowShare(budget, packed >> _BUDGET_W_SHIFT, w.tier);
        }
    }

    function _jackpotWindowShare(uint256 budget, uint256 weight, uint256 tier) internal pure returns (uint256) {
        if (weight == 0) return 0;
        unchecked { return budget * (1 << (tier - 1)) / weight; }
    }

    function _jackpotBonusPreset(uint256 roll, uint256 period) internal pure
        returns (uint128 bankroll, uint128 goal, uint256 boardStake, uint256 stakeUnits, uint256 tier)
    {
        // The jackpot fee is known now. Its bankroll/pot are derived only after its field locks.
        if (period == _BONUS_PERIODS_PER_DAY - 1) return (0, 0, 0, CrapsPriceLib.jackpotPrice(roll) / _BATTLE_STAKE_UNIT, 0);
        uint256 pick = CrapsPriceLib.tier(roll, period == 0 || period == _BONUS_PERIODS_PER_DAY - 2);
        uint256 bank = (uint256(0x119407080258) >> (pick * 16)) & 0xffff;
        uint256 bounty = (uint256(0xdac09c405dc057803e802580190012c00c8) >> ((pick * 3 + ((roll >> 8) % 3)) * 16)) & 0xffff;
        return (uint128(bank), uint128(bank * _SCHED_GOAL),
            _schedRound(bank), bounty / 100, pick + 1);
    }

    function _jackpotCurrentBonusSlot(uint24 day) internal view returns (uint24, uint256 period, uint256 slot) {
        uint256 elapsed = (block.timestamp - 82_620) % 1 days;
        if (_scheduleResetPassed()) period = _BONUS_PERIODS_PER_DAY;
        else if (elapsed >= 1 days - 20 minutes) period = 5;
        else if (elapsed >= 20 minutes) {
            unchecked { period = 1 + (elapsed - 3 minutes) / 6 hours; }
        }
        slot = _jackpotSlotOf(day, period);
        return (day, period, slot);
    }

    function _jackpotFinishWindowTerms(uint24 day, uint256 period, Window memory w, uint256 highMult)
        internal pure returns (Window memory)
    {
        unchecked {
            w.postedStake = (w.played / _BONUS_CHIPS) * _MAX_PICKED_CHIPS;
            w.bound = uint48(_jackpotSlotOf(day, period));
            w.highMult = highMult;
            w.terms = w.stakeUnits | (highMult << _TERM_HIGH_SHIFT);
        }
        w.key = bytes32(uint256(w.bound));
        return w;
    }

    function _jackpotSlotOf(uint256 day, uint256 period) internal pure returns (uint256) {
        unchecked {
            return day * _BONUS_SLOTS_PER_DAY + period + 1;
        }
    }

    function _jackpotWindowAheadPrice(uint256 period, bool high) internal pure returns (uint256 price) {
        unchecked {
            price = period == 0 || period == _BONUS_PERIODS_PER_DAY - 2
                ? _EV_WINDOW_OPENER
                : (period == _BONUS_PERIODS_PER_DAY - 1 ? _EV_WINDOW_TAIL : _EV_WINDOW_ROUTINE);
            if (high) price *= _EV_HIGH_MULT;
        }
    }

    function _jackpotWindowTerms(uint24 day, uint256 period) internal view returns (Window memory w) {
        uint256 slot = _jackpotSlotOf(day, period);
        uint256 state = _loadBattle(bytes32(slot));
        uint256 frozen = state >> _BG_TERM_TIER_SHIFT;
        if (frozen & _BG_TERMS_FROZEN == 0) {
            uint256 word = _dailyWordAt(day);
            if (word == 0 && period != _BONUS_PERIODS_PER_DAY - 1) revert RngNotReady();
            return _jackpotWindowTermsOn(day, period, word);
        }
        // Opened terms survive word retirement in the scoreboard. Settlement entropy still
        // comes from the committed normal RNG cohort (or jackpot round).
        w.tier = frozen & 3;
        w.stakeUnits = (state >> _BG_STAKE_SHIFT) & _BSTAKE_MAX;
        if (w.tier != 0) {
            unchecked {
                uint256 bank = (uint256(0x119407080258) >> ((w.tier - 1) * 16)) & 0xffff;
                w.bankroll = uint128(bank);
                w.goal = uint128(bank * _SCHED_GOAL);
                w.played = _schedRound(bank);
            }
        }
        return _jackpotFinishWindowTerms(day, period, w,
            frozen & _BG_TERM_HIGH_TAIL != 0 ? CrapsPriceLib.HIGH_TAIL : CrapsPriceLib.HIGH_BASE);
    }

    function _jackpotWindowTermsOn(uint24 day, uint256 period, uint256 word) internal view returns (Window memory w) {
        (w.bankroll, w.goal, w.played, w.stakeUnits, w.tier) = _jackpotBonusPreset(_jackpotBonusRoll(word, period), period);
        return _jackpotFinishWindowTerms(day, period, w, _highMultOf(word));
    }
}
