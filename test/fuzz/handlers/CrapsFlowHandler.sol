// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {CrapsViews} from "../../craps/CrapsViews.sol";
import {MockFlip, MockCoinflip, MockGame} from "../../craps/CrapsPins.sol";
import {Craps} from "../../../contracts/Craps.sol";
import {CrapsBattle} from "../../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @title CrapsFlowHandler — the action surface CrapsConservation.inv drives.
///
/// @notice One handler, every money door the table sells, walked in random order by the invariant
///         campaign: window entries, day tickets, amendments, future-day purchases, banked-pass
///         redemptions, high-roller upgrades, custom battles, donations, closes, settles and the
///         keeper — across real protocol days the handler itself advances. Every door runs
///         through the SHIPPED contract; the mocks record what crossed the boundary.
///
/// @dev THE GHOST LEDGER. The invariants read figures the handler accumulates beside the mocks'
///      own: `ghost_subsidies` (every wei of protocol money the campaign made spendable — each
///      opened day's main + high budgets, which bound the ladder, the progressive bank and every
///      denied-boost rollover together, counted at the OPEN so nothing depends on how the dice
///      ran), the opened-day list (for the day-book split checks), the touched slots and battle
///      keys (for the per-field resolution bounds), and the action counters the non-vacuity gate
///      reads.
///
///      ARGUMENT VETTING over revert-tolerance: every action bounds its own inputs and checks the
///      door's preconditions first, so a fuzz step is almost always a real state transition. The
///      few residual reverts (a race the vetting cannot see) are absorbed by
///      `fail_on_revert = false` without polluting the run.
contract CrapsFlowHandler {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    CrapsViews public immutable craps;
    MockFlip internal immutable flip;
    MockCoinflip internal immutable coinflip;
    MockGame internal immutable game;

    /// @dev The game-side storage slots the words live in — the same numbers `CrapsPins` pins.
    uint256 internal constant WORD_SLOT = 34;
    uint256 internal constant DAY_WORD_SLOT = 10;

    uint256 internal constant PERIODS = 7;

    // ── Actors ──────────────────────────────────────────────────────────────
    address[] public actors;
    address public immutable creator;

    // ── Ghost ledger ────────────────────────────────────────────────────────
    /// @dev Protocol money made spendable by this campaign: Σ over opened days of
    ///      (mainBudget + highBudget). The ladder, the progressive contributions and every
    ///      denied-boost rollover all draw from inside this figure, never beyond it.
    uint256 public ghost_subsidies;

    uint24[] public ghost_openedDays;
    uint64[] public ghost_slots;
    mapping(uint64 => bool) internal slotSeen;
    uint256[] public ghost_betIds;

    uint256 public ghost_entries;
    uint256 public ghost_dayTickets;
    uint256 public ghost_highSeats;
    uint256 public ghost_settledFields;
    uint256 public ghost_scheduledSettles;
    uint256 public ghost_customBattles;
    uint256 public ghost_donations;
    uint256 public ghost_repeatSettleCreditDelta;
    uint256 public ghost_keeps;

    constructor(CrapsViews craps_) {
        craps = craps_;
        flip = MockFlip(ContractAddresses.COIN);
        coinflip = MockCoinflip(ContractAddresses.COINFLIP);
        game = MockGame(ContractAddresses.GAME);
        creator = address(0xC0FFEE);
        for (uint256 i = 0; i < 5; ++i) {
            address a = address(uint160(0xA110 + i));
            actors.push(a);
            game.setScore(a, 400 + i * 900);
        }
        game.setScore(creator, 5_000);
    }

    // ── Internals ───────────────────────────────────────────────────────────

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }

    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == PERIODS) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    function _boundOf(uint24 day, uint256 period) internal pure returns (uint64) {
        return uint64(uint256(day) * 8 + period + 1);
    }

    function _board(uint256 seed) internal pure returns (Craps.Bets memory b) {
        uint256 k = seed % 5;
        if (k == 1) {
            b.place4 = 4;
            b.place10 = 3;
        } else if (k == 2) {
            b.passLine = 4;
            b.place4 = 3;
        } else if (k == 3) {
            b.dontPass = 4;
            b.place4 = 3;
        } else if (k == 4) {
            b.place4 = 2;
            b.place5 = 2;
            b.place9 = 2;
            b.place10 = 1;
        }
        // k == 0 is the blank ticket: all ten chips to the dice.
    }

    function _setWord(uint48 index, uint256 word) internal {
        game.set(keccak256(abi.encode(uint256(index), WORD_SLOT)), bytes32(word));
    }

    function _setDailyWord(uint24 day, uint256 word) internal {
        game.set(keccak256(abi.encode(uint256(day), DAY_WORD_SLOT)), bytes32(word));
    }

    function _trackSlot(uint64 slot) internal {
        if (!slotSeen[slot]) {
            slotSeen[slot] = true;
            ghost_slots.push(slot);
        }
    }

    /// @dev Open the protocol day the clock currently sits in, if it has not opened yet: land the
    ///      daily word, bank the ghost subsidy AT THE OPEN, and let the shipped door do the rest.
    function _openToday(uint256 wordSeed) internal {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) != 0) return;
        _setDailyWord(d, uint256(keccak256(abi.encode("day", wordSeed, d))) | 1);
        (uint256 mainBudget, uint256 highBudget) = craps.drawBudgetsFor(d);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        ghost_subsidies += mainBudget + highBudget;
        ghost_openedDays.push(d);
    }

    // ── Actions ─────────────────────────────────────────────────────────────

    /// @dev Move to the NEXT protocol day and open it. The campaign's clock only moves forward.
    function advanceDay(uint256 wordSeed) external {
        _sweepToday(wordSeed);
        vm.warp(_dayStart() + 1 days);
        _openToday(wordSeed);
    }

    /// @dev The production keeper's daily duty, restated: before the campaign leaves a day, every
    ///      window of it is shut, worded and settled, so no field is stranded behind the clock.
    function _sweepToday(uint256 wordSeed) internal {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) == 0) return;
        vm.warp(_dayStart() + 1 days - craps.EVENT_LEAD());
        for (uint256 p = 0; p < PERIODS; ++p) {
            uint64 bound = _boundOf(d, p);
            if (craps.slotIndexOf(bound) == 0) {
                try craps.armBonusWindow(bound) returns (uint48 index) {
                    _setWord(index, uint256(keccak256(abi.encode("sweep", wordSeed, bound))) | 1);
                    _trackSlot(bound);
                } catch {}
            }
        }
        _landWords(wordSeed);
        for (uint256 p = 0; p < PERIODS; ++p) {
            uint64 bound = _boundOf(d, p);
            uint48 idx = craps.slotIndexOf(bound);
            if (idx == 0 || craps.wordAt(idx - 1) == 0) continue;
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(bound));
            if (b.entrants == 0 || b.resolved == b.entrants) continue;
            _settleBound(bound);
        }
    }

    /// @dev Enter one still-joinable window of the open day through the real door.
    function enterWindow(uint256 actorSeed, uint256 boardSeed, uint256 periodSeed, bool high) external {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) == 0) return;
        uint256 elapsed = block.timestamp - _dayStart();
        // A window takes bets until its close; pick among the ones still open and unarmed.
        uint256 p = periodSeed % PERIODS;
        bool found;
        for (uint256 i = 0; i < PERIODS; ++i) {
            uint256 cand = (p + i) % PERIODS;
            if (elapsed < _closeOf(cand) && craps.slotIndexOf(_boundOf(d, cand)) == 0) {
                p = cand;
                found = true;
                break;
            }
        }
        if (!found) return;
        address who = _actor(actorSeed);
        if (craps.daySeatNumberOf(d, who) != 0) return; // a day ticket already covers every window
        uint16 mult = 1;
        if (high) {
            uint256 h = craps.highMultForDay(d);
            if (h < 2) return;
            mult = uint16(h);
        }
        vm.prank(who);
        try craps.enterBonusBattle(p, _board(boardSeed), mult) returns (uint256 betId) {
            ghost_betIds.push(betId);
            _trackSlot(uint64(betId >> 64));
            ++ghost_entries;
            if (high) ++ghost_highSeats;
        } catch {}
    }

    /// @dev Take the whole day through the day lane, while its first window still sells it.
    function enterDay(uint256 actorSeed, uint256 boardSeed, bool high) external {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) == 0) return;
        (, uint256 period,) = craps.currentBonusSlot();
        if (period != 0) return;
        address who = _actor(actorSeed);
        if (craps.daySeatNumberOf(d, who) != 0) return;
        uint16 mult = 1;
        if (high) {
            uint256 h = craps.highMultForDay(d);
            if (h < 2) return;
            mult = uint16(h);
        }
        vm.prank(who);
        try craps.enterBonusDay(_board(boardSeed), mult) returns (uint256) {
            ++ghost_entries;
            ++ghost_dayTickets;
            if (high) ++ghost_highSeats;
        } catch {}
    }

    /// @dev Re-spread (or blank) a tracked slip through the real amendment door.
    function amend(uint256 pickSeed, uint256 boardSeed) external {
        if (ghost_betIds.length == 0) return;
        uint256 betId = ghost_betIds[pickSeed % ghost_betIds.length];
        CrapsBattle.Bet memory b = craps.betOf(betId);
        if (b.player == address(0)) return;
        vm.prank(b.player);
        try craps.amendSlip(betId, _board(boardSeed)) {} catch {}
    }

    /// @dev Buy future days outright; the burn is the mock's to record.
    function buyFuture(uint256 actorSeed, uint256 countSeed, bool high) external {
        uint24 d = craps.currentDayIndex();
        uint8 count = uint8(1 + (countSeed % 3));
        address who = _actor(actorSeed);
        vm.prank(who);
        try craps.buyFutureCrapsDays(d + 1, count, high) {} catch {}
    }

    /// @dev Spend banked pass credits on a future day.
    function applyPasses(uint256 actorSeed, bool high) external {
        address who = _actor(actorSeed);
        (uint256 normal, uint256 hi) = craps.passCreditsOf(who);
        if ((high ? hi : normal) == 0) return;
        vm.prank(who);
        try craps.applyCrapsPasses(craps.currentDayIndex() + 1, 1, high) {} catch {}
    }

    /// @dev Convert banked normal credits into high credits at the fixed 19:1. The rate is
    ///      re-measured against the balances after every success; a conversion that moved either
    ///      lane off-rate marks the ghost the invariant reads.
    function convert(uint256 actorSeed, uint256 countSeed) external {
        address who = _actor(actorSeed);
        (uint256 nB, uint256 hB) = craps.passCreditsOf(who);
        if (nB < 19) return;
        uint32 want = uint32(1 + (countSeed % (nB / 19)));
        vm.prank(who);
        try craps.convertNormalToHigh(want) {
            (uint256 nA, uint256 hA) = craps.passCreditsOf(who);
            if (nB - nA != 19 * uint256(want) || hA - hB != uint256(want)) ++ghost_conversionRateBreaks;
            ++ghost_conversions;
        } catch {}
    }

    uint256 public ghost_conversions;
    uint256 public ghost_conversionRateBreaks;

    /// @dev Upgrade a day ticket's still-unarmed windows to the high lane.
    function upgrade(uint256 actorSeed, uint8 mask) external {
        uint24 d = craps.currentDayIndex();
        address who = _actor(actorSeed);
        if (craps.daySeatNumberOf(d, who) == 0) return;
        if (mask == 0) mask = 1;
        vm.prank(who);
        try craps.upgradeDayWindows(d, mask & 0x7F) {} catch {}
    }

    /// @dev Open a custom battle as the authorized creator, seat one entrant, close it onto the
    ///      next index and land the word — the whole custom lifecycle in one action.
    function customBattle(uint256 actorSeed, uint256 boardSeed, uint256 termSeed) external {
        uint32 played = uint32(300 + (termSeed % 5) * 300);
        uint8 bankMult = uint8(1 + (termSeed % 25));
        uint16 goalMult = uint16(5 + (termSeed % 20));
        vm.prank(creator);
        try craps.createBattle(
            played, bankMult, goalMult, 2, 0, uint40(block.timestamp + 2 hours), false, 0
        ) returns (uint64 slot) {
            ++ghost_customBattles;
            address who = _actor(actorSeed);
            vm.prank(who);
            try craps.enterBattle(slot, _board(boardSeed), 1) returns (uint256 betId) {
                ghost_betIds.push(betId);
                _trackSlot(slot);
                ++ghost_entries;
            } catch {}
            vm.warp(block.timestamp + 2 hours + 1);
            try craps.closeBattle(slot) returns (uint48 index) {
                _setWord(index, uint256(keccak256(abi.encode("cword", termSeed))) | 1);
            } catch {}
        } catch {}
    }

    /// @dev Burn a third-party donation onto a joinable window's pot.
    function donate(uint256 actorSeed, uint256 periodSeed, uint24 granules) external {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) == 0) return;
        uint256 p = periodSeed % PERIODS;
        if (craps.slotIndexOf(_boundOf(d, p)) != 0) return;
        if (block.timestamp - _dayStart() >= _closeOf(p)) return;
        address who = _actor(actorSeed);
        vm.prank(who);
        try craps.donate(false, p, uint24(1 + (granules % 5))) {
            ++ghost_donations;
        } catch {}
    }

    /// @dev Land a word on every armed-but-wordless window of the open day. The KEEPER arms
    ///      windows on its own crank, and an armed field waits on its word — in production the
    ///      lootbox lane's, here the handler's. Without this, a keeper-armed window is stranded
    ///      and the scheduled surface silently stops settling.
    function _landWords(uint256 wordSeed) internal {
        uint24 d = craps.currentDayIndex();
        for (uint256 p = 0; p < PERIODS; ++p) {
            uint64 bound = _boundOf(d, p);
            uint48 idx = craps.slotIndexOf(bound);
            if (idx == 0) continue;
            if (craps.wordAt(idx - 1) == 0) {
                _setWord(idx - 1, uint256(keccak256(abi.encode("kword", wordSeed, bound))) | 1);
            }
            _trackSlot(bound);
        }
    }

    /// @dev Shut the next window past its close and land the word that settles it.
    function closeNextWindow(uint256 wordSeed) external {
        uint24 d = craps.currentDayIndex();
        if (craps.dailyWordAt(d) == 0) return;
        _landWords(wordSeed);
        for (uint256 p = 0; p < PERIODS; ++p) {
            uint64 bound = _boundOf(d, p);
            if (craps.slotIndexOf(bound) != 0) continue;
            uint256 close = _closeOf(p);
            if (block.timestamp - _dayStart() < close) vm.warp(_dayStart() + close);
            try craps.armBonusWindow(bound) returns (uint48 index) {
                _setWord(index, uint256(keccak256(abi.encode("word", wordSeed, bound))) | 1);
                _trackSlot(bound);
            } catch {}
            return;
        }
    }

    /// @dev Settle every seat a closed-and-worded slot still owes, and prove a repeat settle
    ///      credits nothing: any delta a second walk adds is accumulated for the invariant.
    function settleSlot(uint256 pickSeed) external {
        uint64 slot = _settleTarget(pickSeed);
        if (slot == 0) return;
        _settleBound(slot);
    }

    /// @dev The settle core: walk the whole field, book the ghosts, and prove the repeat walk
    ///      credits nothing.
    function _settleBound(uint64 slot) internal {
        try craps.resolveSlot(slot, type(uint64).max) {} catch {
            return;
        }
        ++ghost_settledFields;
        if (slot < 1 << 40) ++ghost_scheduledSettles;
        uint256 before = coinflip.totalCredited();
        try craps.resolveSlot(slot, type(uint64).max) {} catch {}
        ghost_repeatSettleCreditDelta += coinflip.totalCredited() - before;
    }

    /// @dev One keeper crank at a random budget.
    function keep(uint64 budget) external {
        try craps.keepScheduled(budget % 64) {
            ++ghost_keeps;
        } catch {}
        _landWords(budget);
    }

    // ── Shared helpers ──────────────────────────────────────────────────────

    /// @dev A closed slot whose word has landed and whose field still owes seats.
    function _settleTarget(uint256 pickSeed) internal view returns (uint64) {
        uint256 n = ghost_slots.length;
        for (uint256 i = 0; i < n; ++i) {
            uint64 slot = ghost_slots[(pickSeed + i) % n];
            uint48 idx = craps.slotIndexOf(slot);
            if (idx == 0) continue;
            if (craps.wordAt(idx - 1) == 0) continue;
            CrapsBattle.Battle memory b = craps.battleOf(craps.keyOfSlot(slot));
            if (b.entrants == 0 || b.resolved == b.entrants) continue;
            return slot;
        }
        return 0;
    }

    // ── Read surface for the invariants ─────────────────────────────────────

    function openedDayCount() external view returns (uint256) {
        return ghost_openedDays.length;
    }

    function slotCount() external view returns (uint256) {
        return ghost_slots.length;
    }

    function openedDayAt(uint256 i) external view returns (uint24) {
        return ghost_openedDays[i];
    }

    function slotAt(uint256 i) external view returns (uint64) {
        return ghost_slots[i];
    }
}
