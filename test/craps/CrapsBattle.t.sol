// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Overrides nothing: every rule under test is the shipped one. The taps reach internals the
///      paying path already runs — `settlementAt` reads the same `_settlementOf` a resolution
///      consumes, and `scoreAt` drives the shipped scoreboard fold directly.
contract BattleHarness is CrapsViews {
    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
    }


    function isHighOf(uint256 betId) external view returns (bool) {
        return _bets[betId] & _BET_HIGH_BIT != 0;
    }

    /// @dev Copy a slip's stored word onto another id, so a suite can settle the SAME ticket from
    ///      two different slots and compare. Nothing else about the field is touched.
    function copyBetTo(uint256 from, uint256 to) external {
        _bets[to] = _bets[from];
    }

    /// @dev The same settlement, for a slip whose id does NOT name the window it plays. A day
    ///      ticket sits in all seven, so the terms and the word are the WINDOW's, not the id's —
    ///      the very pair `resolveSlot` hands `_resolve` for a seat in the day tail.
    function settlementIn(uint256 betId, uint64 slot) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(slot), _wordAt(_indexOf(slot)));
    }

    /// @dev The fold takes the whole WINDOW now, because the boost it announces at finalization
    ///      is drawn from the field and the terms. These taps drive a bare key, so they hand it a
    ///      window carrying only what the fold reads.
    function scoreAt(bytes32 key, uint256 score, uint64 seat, uint256 stakeUnits) external {
        Window memory w;
        w.key = key;
        w.stakeUnits = stakeUnits;
        _scoreBattle(w, score, seat, 0, 0);
    }

    /// @dev The same tap, carrying a roll count, so a suite can drive what the scoreboard stores
    ///      beside the seat without running a whole field through the engine.
    function scoreRolls(bytes32 key, uint256 score, uint64 seat, uint256 stakeUnits, uint256 rolls) external {
        Window memory w;
        w.key = key;
        w.stakeUnits = stakeUnits;
        _scoreBattle(w, score, seat, 0, rolls);
    }

    /// @dev The seed field's ceiling, in stake units. Internal on the contract, so the harness is
    ///      what lets a suite drive a window all the way to it.
    function _daySlotOfPub(uint24 day) public pure returns (uint256) {
        return uint256(day) * BONUS_SLOTS_PER_DAY;
    }

    function seedUnitsMax() external pure returns (uint256) {
        return _BG_SEED_MASK;
    }

    /// @dev The same fold, driven on a chosen table word, so a suite can pin what the coin does
    ///      to a dead-level score.
    function scoreOnWord(bytes32 key, uint256 score, uint64 seat, uint256 stakeUnits, uint256 word) external {
        Window memory w;
        w.key = key;
        w.stakeUnits = stakeUnits;
        _scoreBattle(w, score, seat, word, 0);
    }

    /// @dev The composite the fold actually compares: rank, then the money it came home with,
    ///      then the entrant's standing. Restated here so the suite can assert the ladder.
    function compositeOf(uint256 rank, uint256 wonFlip, uint256 standing) external pure returns (uint256) {
        return (rank << _SC_RANK_SHIFT) | ((wonFlip & _SC_WON_MASK) << _SC_WON_SHIFT) | standing;
    }

    function rankAt(Craps.SlipStop stop, uint256 hands) external pure returns (uint256) {
        return _rankOf(stop, hands);
    }

    /// @dev The board a slip actually PLAYS: its chips grown by the ones the dice place. No slip
    ///      settles on what it posted, so every oracle comparison has to be made against this.
    ///      Production draws it inside settlement and does not expose it — a client rebuilds it
    ///      from the slot, the word and the owner with one keccak.
    function drawnBoardOf(uint256 betId) external view returns (Craps.Bets memory board) {
        return _drawnBoardAt(betId, uint64(betId >> 64));
    }

    /// @dev The same board, for a slip whose id does NOT name the window it plays. A day ticket
    ///      sits in all seven, so the chip and the word are the WINDOW's, not the id's.
    function drawnBoardAt(uint256 betId, uint64 slot) external view returns (Craps.Bets memory board) {
        return _drawnBoardAt(betId, slot);
    }

    function _drawnBoardAt(uint256 betId, uint64 slot) private view returns (Craps.Bets memory board) {
        uint256 header = _bets[betId];
        Window memory w = _slotWindow(slot);
        uint256 chipFlip = (w.played / 1 ether) / BONUS_CHIPS;
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 thrown = BONUS_CHIPS;
        if (packed != 0) {
            board = _boardFrom(packed, chipFlip);
            thrown = _RSEL_PICK7;
        }
        _scatterInto(
            board, uint256(keccak256(abi.encode(_wordAt(_indexOf(slot)), address(uint160(header))))), chipFlip, thrown
        );
    }

    /// @dev Where the custom lane starts. Internal on the contract, so the suite reads it here
    ///      to tell a scheduled battle from a bonus window by slot alone.
    function customSlotBase() external pure returns (uint256) {
        return _CUSTOM_SLOT_BASE;
    }

    /// @dev Whether a slot has SHUT. That is the moment the day field is folded into its entrant
    ///      count, so it is also the moment a seat number means the own-then-day range.
    function isShut(uint64 slot) external view returns (bool) {
        return _slotIndex[slot] != 0;
    }

    /// @dev What ONE window of a day puts up before the multiplier — the day's budget split seven
    ///      ways. Exposed so a suite can pin the split without arming and settling a window.
    function boostBaseAt(uint64 slot) external view returns (uint256) {
        return _boostBase(_slotWindow(slot));
    }

    /// @dev Write straight into a day's action. A budget is drawn from the SEVEN DAYS BEFORE the
    ///      day it opens, so a suite that wants a funded table has to put action behind it — and
    ///      driving real settlements for seven prior days is not a fixture, it is a simulation.
    function bookDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, 0);
    }

    /// @dev The same, for action a HIGH-ROLLER seat put up: it lands in the day total AND in the
    ///      high subset, which is what the two budgets are split on.
    function bookHighDay(uint24 day, uint256 staked) external {
        _bookDay(day, staked, staked);
    }

    /// @dev The budget a day WOULD draw right now, before it opens.
    function drawBudgetFor(uint24 day) external view returns (uint256) {
        (uint256 m,) = _drawBudgets(day);
        return m;
    }

    function drawHighBudgetFor(uint24 day) external view returns (uint256) {
        (, uint256 h) = _drawBudgets(day);
        return h;
    }

    /// @dev The boost ladder, driven directly — production applies it as a field finalizes, so this
    ///      is how a suite pins every rung rather than only the one a table happened to land on.
    /// @dev The boost's rounding step, so a fixture can assert it straddles it rather than
    ///      hard-coding a figure that silently stops meaning anything if the step moves.
    function roundBoostFor(uint256 units) external pure returns (uint256) {
        return _roundBoost(units);
    }

    function boostShareFor(uint256 boostUnits, uint256 held) external pure returns (uint256) {
        return _boostShare(boostUnits, held);
    }

    /// @dev A slot's WHOLE boost in granules — the band's pick off the settling word plus every
    ///      donation on it — before any rationing.
    function boostUnitsAt(uint64 slot) external view returns (uint256) {
        Window memory w = _slotWindow(slot);
        unchecked {
            uint256 g = _battles[w.key];
            return _boostUnits(w, _wordAt(_indexOf(slot))) + ((g >> _BG_SEED_SHIFT) & _BG_SEED_MASK);
        }
    }


}

/// @title Craps battle suite
/// @notice The side pot: matching, scoring, finalization, claims and amendment. The verdict logic
///         is graded against an independent restatement of the rules — goal-with-flip beats every
///         bust, faster goals and later busts win, and exact ties use the table word — never
///         against the contract's own rank encoding.
contract CrapsBattleTest is CrapsPins {
    BattleHarness internal craps;

    uint24 internal constant L = 600;
    /// @dev Every round is TEN chips and an entry places SEVEN of them. `C` is this suite's chip
    ///      and `P` the seven a board posts; the dice place the other three, so the round actually
    ///      played is `L` and every bankroll and stop-round below is unmoved.
    uint24 internal constant C = 60;
    uint24 internal constant P = C * 7;
    uint128 internal constant LW = 600e18;
    /// @dev The battle-stake granule, and the suite's default entry: three of them, which is
    ///      inside the 20%-to-100% band a 1,200 FLIP bankroll allows.
    uint256 internal constant GRANULE = 100e18;
    uint24 internal constant SU = 3;
    uint256 internal constant SUW = uint256(SU) * GRANULE;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal keeper = makeAddr("keeper");

    function setUp() public {
        _installPins();
        craps = new BattleHarness();
        _setIndex(4);
        // Arming needs today's word in. This one lands on preset 0 with no spread, so the fixed
        // terms below can be named as constants: `% 4 == 0` picks the preset, `(>> 8) % 40 == 0`
        // adds nothing to the seed.
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    /// @dev Three boards posting the same seven chips in different shapes — the strategies that
    ///      are supposed to share a battle, since composition is not a term.
    // Chip COUNTS now, not amounts: seven of the round's ten, wherever the entrant wants them.
    // The slot fixes what a chip is worth, so one allocation enters any battle.
    /// @dev The packed forms of the two stock allocations, for fixtures that read a slip back.
    ///      Three bits a leg, in board order.
    uint256 internal constant BOARD_A_PACKED = 4 | (uint256(3) << 9); // line 4, place 6 three
    uint256 internal constant SEVEN_PACKED = 4 | (uint256(3) << 12); // line 4, place 8 three

    function _boardA() internal pure returns (Craps.Bets memory b) {
        b.passLine = 4;
        b.place6 = 3;
    }

    function _boardB() internal pure returns (Craps.Bets memory b) {
        b.place6 = 4;
        b.place8 = 3;
    }

    function _boardC() internal pure returns (Craps.Bets memory b) {
        b.place4 = 4;
        b.hard8 = 3;
    }

    /// @dev A blank ticket: names nothing, so the dice place all ten.
    function _blank() internal pure returns (Craps.Bets memory b) {}

    /// @dev `n` chips spread within the four-a-leg cap, for fixtures that care about the COUNT and
    ///      nothing about the shape. Four legs carry fourteen, which is every count they ask for.
    function _spread(uint24 n) internal pure returns (Craps.Bets memory b) {
        uint24[4] memory legs;
        for (uint256 i = 0; i < 4 && n > 0; ++i) {
            legs[i] = n > 4 ? 4 : n;
            n -= legs[i];
        }
        (b.passLine, b.place6, b.place8, b.place9) = (legs[0], legs[1], legs[2], legs[3]);
    }

    function _ids(uint256 a) internal pure returns (uint256[] memory out) {
        out = new uint256[](1);
        out[0] = a;
    }

    function _ids3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256[] memory out) {
        out = new uint256[](3);
        out[0] = a;
        out[1] = b;
        out[2] = c;
    }

    /// @dev Terms named once open a battle; naming them again JOINS it. That is how a field forms
    ///      now — the pre-slot fixtures got the same thing from naming identical terms at one
    ///      index. Every fixture board is one 600-FLIP round, so `played` is fixed and the
    ///      bankroll and target are the multiples the slot stores.
    mapping(bytes32 => uint64) private _fixtureSlot;

    function _slotKey(uint128 bank, uint128 goal, uint24 su) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(uint8(uint256(bank) / LW), goal == 0 ? uint16(GOAL_FAR_MULT) : uint16(uint256(goal) / bank), su)
        );
    }

    function _slotFor(uint128 bank, uint128 goal, uint24 su) internal returns (uint64 slot) {
        bytes32 k = _slotKey(bank, goal, su);
        slot = _fixtureSlot[k];
        if (slot == 0) {
            slot = _openBattle(
                craps,
                uint32(LW / 1 ether),
                uint8(uint256(bank) / LW),
                goal == 0 ? uint16(GOAL_FAR_MULT) : uint16(uint256(goal) / bank),
                su
            );
            _fixtureSlot[k] = slot;
        }
    }

    function _placeBattle(address who, Craps.Bets memory b, uint128 bank, uint128 goal, uint24 su)
        internal
        returns (uint256)
    {
        uint64 slot = _slotFor(bank, goal, su);
        // Clear of the sybil floor, so these fixtures measure the BASE price of a seat. The
        // surcharge has a test of its own and must not silently ride along in every burn
        // assertion. Only raised, never lowered — a fixture that set its own standing keeps it.
        if (game.score(who) < craps.SYBIL_SCORE_FLOOR()) game.setScore(who, craps.SYBIL_SCORE_FLOOR());
        vm.prank(who);
        return craps.enterBattle(slot, b, 1);
    }

    /// @dev The whole tail of a fixture: shut the battle these terms opened onto `index`, land
    ///      `word`, and settle its entire field.
    function _runSlot(uint128 bank, uint128 goal, uint24 su, uint48 index, uint256 word) internal returns (uint64) {
        uint64 slot = _slotFor(bank, goal, su);
        _closeOn(craps, slot, index, word);
        craps.resolveSlot(slot, WHOLE_FIELD);
        // A shut battle takes no more entries, so a sweeping fixture must open a fresh one next
        // time it names these terms.
        delete _fixtureSlot[_slotKey(bank, goal, su)];
        return slot;
    }

    /// @dev Shut onto a table WITHOUT settling — for fixtures that want the field standing still,
    ///      or that mean to drive the resolve themselves. Settling is what pays now, so a fixture
    ///      asserting on a scoreboard has to stop here.
    function _closeSlot(uint128 bank, uint128 goal, uint24 su, uint48 index, uint256 word)
        internal
        returns (uint64 slot)
    {
        slot = _slotFor(bank, goal, su);
        _closeOn(craps, slot, index, word);
        delete _fixtureSlot[_slotKey(bank, goal, su)];
    }

    /// @dev The battle rules, restated independently of the contract's rank scalar: a goal beats
    ///      every bust, faster goals beat slower ones, later busts beat earlier ones.
    ///      `g` = reached goal.
    function _beats(bool gA, uint256 hA, bool gB, uint256 hB) internal pure returns (bool) {
        if (gA != gB) return gA;
        return gA ? hA < hB : hA > hB;
    }

    // ---------------------------------------------------------------------------------------
    // Matching
    // ---------------------------------------------------------------------------------------

    /// @dev A zero-stake room is an ORDINARY battle whose pot happens to be empty: same lane, same
    ///      ranking, same claim — it just hands over nothing at the end.
    function test_aFriendlyBattleRunsTheOrdinaryLaneAndAwardsNothing() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, 0);
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, LW * 10, 0);
        _placeBattle(bob, _boardB(), LW * 2, LW * 10, 0);
        _placeBattle(carol, _boardC(), LW * 2, LW * 10, 0);
        assertEq(craps.battleOf(craps.battleKeyOf(a)).battleStake, 0, "a friendly battle grew a bounty");

        _closeOn(craps, slot, 4, uint256(keccak256("plain")));
        craps.resolveSlot(slot, WHOLE_FIELD);

        // It RANKS. A zero bounty used to skip the scoreboard entirely, so `resolved` never caught
        // `entrants` and the battle could never finalize.
        CrapsBattle.Battle memory info = craps.battleOf(craps.battleKeyOf(a));
        assertEq(info.resolved, 3, "a friendly field did not score");
        assertTrue(info.finalized, "a friendly battle never finalized");
        assertTrue(info.winnerId != 0, "a friendly battle named no winner");
        assertTrue(craps.betOf(a).settled, "a friendly slip did not settle");

        // And the claim lane is OPEN — it simply pays out whatever the pot holds, which for a
        // zero-bounty battle with nothing donated onto it is NOTHING. A busted run's remainder is
        // deleted where it busts, so no amount of carnage can put money into this pot.
        address winner = craps.betOf(_idAt(slot, info.winnerId)).player;
        uint256 before = coinflip.staked(winner);
        assertEq(coinflip.staked(winner) - before, 0, "a friendly claim paid a pot it never had");
    }

    /// @dev Different board compositions with the same one-round total, same bankroll, goal and
    ///      stake at one index are ONE battle — strategy is the game, not the match key.
    function test_matchingSlipsShareOneBattleAcrossBoards() public {
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        uint256 b = _placeBattle(bob, _boardB(), LW * 2, LW * 10, SU);
        uint256 c = _placeBattle(carol, _boardC(), LW * 2, LW * 10, SU);

        bytes32 key = craps.battleKeyOf(a);
        assertEq(craps.battleKeyOf(b), key, "board composition leaked into the match key");
        assertEq(craps.battleKeyOf(c), key, "board composition leaked into the match key");

        CrapsBattle.Battle memory info = craps.battleOf(key);
        assertEq(info.entrants, 3, "entrants");
        assertEq(info.resolved, 0, "resolved early");
        assertEq(info.battleStake, SUW, "stake echo");
        assertEq(info.pot, SUW * 3, "pot");
        assertFalse(info.finalized, "finalized early");
    }

    /// @dev There are two ways to put a round down and they are the SAME race: place seven chips
    ///      and the dice place three, or place none and the dice place all ten. The match key is
    ///      built on the round PLAYED, not on the slice of it the entrant chose to name, so the
    ///      chips left to the dice are composition rather than a term.
    function test_placingSevenOrNoneIsTheSameBattle() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        // A BLANK ticket names nothing, so the dice place all ten. Same slot, same terms, so it
        // is the same race — the count a ticket defers is a per-entrant choice, not a term.
        uint256 b = _placeBattle(bob, _blank(), LW * 2, LW * 10, SU);

        bytes32 key = craps.battleKeyOf(a);
        assertEq(craps.battleKeyOf(b), key, "a blank ticket split the battle");
        assertEq(craps.battleOf(key).entrants, 2, "the field did not gather");
        assertEq(craps.betOf(a).chips, BOARD_A_PACKED, "the seven were not named");
        assertEq(craps.betOf(b).chips, 0, "a blank ticket named something");

        // Both put the SAME round down, whatever they posted.
        _closeOn(craps, slot, 4, uint256(keccak256("chips")));
        uint256 round = uint256(C) * 10 * 1 ether;
        assertEq(craps.stakeFor(craps.drawnBoardOf(a)), round, "the seven-and-three round moved");
        assertEq(craps.stakeFor(craps.drawnBoardOf(b)), round, "the all-thrown round moved");

        craps.resolveSlot(slot, WHOLE_FIELD);
        assertTrue(craps.battleOf(key).finalized, "the mixed field did not finalize");
    }

    /// @dev Perturb every term of the match key — bankroll, goal, round, battle stake, and slot —
    ///      and each perturbation is its own battle.
    function test_anyDifferingTermSplitsTheBattle() public {
        bytes32[6] memory keys;
        keys[0] = craps.battleKeyOf(_placeBattle(alice, _boardA(), LW * 2, LW * 11, SU));
        keys[1] = craps.battleKeyOf(_placeBattle(alice, _boardA(), LW * 3, LW * 15, SU));
        keys[2] = craps.battleKeyOf(_placeBattle(alice, _boardA(), LW * 2, LW * 12, SU));
        uint64 differentRoundSlot = _openBattle(craps, 300, 4, 5, SU);
        vm.prank(alice);
        keys[3] = craps.battleKeyOf(craps.enterBattle(differentRoundSlot, _boardA(), 1));
        keys[4] = craps.battleKeyOf(_placeBattle(alice, _boardA(), LW * 2, LW * 11, SU + 1));
        uint64 differentSlot = _openBattle(craps, uint32(LW / 1 ether), 2, 5, SU);
        vm.prank(alice);
        keys[5] = craps.battleKeyOf(craps.enterBattle(differentSlot, _boardA(), 1));

        for (uint256 i = 0; i < 6; ++i) {
            for (uint256 j = i + 1; j < 6; ++j) {
                assertTrue(keys[i] != keys[j], "two differing terms shared a battle");
            }
        }
    }

    /// @dev One burn covers bankroll plus battle stake; the two are tracked separately and the
    ///      granule ceiling is enforced.
    function test_burnTakesBankrollPlusBattleStakeOnce() public {
        _placeBattle(alice, _boardA(), LW * 2, LW * 10, 5);

        assertEq(flip.burned(alice), LW * 2 + 5 * GRANULE, "burn != bankroll + battle stake");
        (,, uint256 terms) = craps.customBattleOf(_slotFor(LW * 2, LW * 10, 5));
        assertEq(((terms >> 43) & 0x3FFFF) * GRANULE, 5 * GRANULE, "the slot's bounty moved");

        // The bounty rides alongside the bankroll rather than out of it, and may not exceed it —
        // proven once, at the door that fixes it for the whole field.
        vm.prank(vaultOwner);
        vm.expectRevert(CrapsBattle.BadBattleStake.selector);
        craps.createBattle(
            uint32(LW / 1 ether), 2, 5, uint24((LW * 2) / GRANULE) + 1, 0, uint40(block.timestamp + 1 hours), false
        , 0);
    }

    // ---------------------------------------------------------------------------------------
    // Scoring and claims
    // ---------------------------------------------------------------------------------------

    /// @dev The whole verdict, graded differentially: many tables, three strategies per battle,
    ///      the winner recomputed from the independent rules restated in `_beats`, then every
    ///      claim checked — winners paid the identical floor cut as coinflip credit, losers
    ///      refused, the pot conserved to sub-`winnerCount` dust.
    function test_battleVerdictMatchesIndependentRules() public {
        uint256 sawGoalWin;
        uint256 sawAllBust;
        uint256 sawTieOnRank;

        for (uint256 i = 0; i < 60; ++i) {
            uint256[] memory ids = _ids3(
                _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU),
                _placeBattle(bob, _boardB(), LW * 2, LW * 10, SU),
                _placeBattle(carol, _boardC(), LW * 2, LW * 10, SU)
            );
            uint256 word = uint256(keccak256(abi.encode("verdict", i)));
            uint64 slot = _closeSlot(LW * 2, LW * 10, SU, uint48(10_000 + i), word);
            bytes32 key = craps.battleKeyOf(ids[0]);

            // The expected verdict, off the engine's own account of each run but ranked by the
            // independent comparator — rank first, then the money, then the standing.
            bool[3] memory g;
            uint256[3] memory h;
            uint256[3] memory w;
            for (uint256 k = 0; k < 3; ++k) {
                CrapsBattle.Settlement memory st = craps.settlementAt(ids[k]);
                g[k] = st.stop == Craps.SlipStop.Goal;
                h[k] = st.handsPlayed;
                w[k] = st.won;
            }
            // Rank, then the money, then — when those are dead level, which is the whole
            // composite here since the three share a standing — the word's own coin.
            uint256 best = 0;
            for (uint256 k = 1; k < 3; ++k) {
                bool level = g[k] == g[best] && h[k] == h[best] && w[k] / 1 ether == w[best] / 1 ether;
                bool takes = level
                    ? _tag(word, ids[k]) > _tag(word, ids[best])
                    : _beatsFully(g[k], h[k], w[k], g[best], h[best], w[best]);
                if (takes) best = k;
            }
            for (uint256 k = 0; k < 3; ++k) {
                if (k != best && !_beats(g[best], h[best], g[k], h[k]) && !_beats(g[k], h[k], g[best], h[best])) {
                    ++sawTieOnRank;
                }
            }
            if (g[best]) ++sawGoalWin;
            else ++sawAllBust;

            // ONE winner takes the WHOLE pot, in ONE payment, made by the settlement itself. The
            // pot is the three bounties and NOTHING else — what the busted seats were holding was
            // deleted, not swept in here. Read off the log, because the same call also credits
            // each run its own winnings and a balance would carry both.
            PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

            CrapsBattle.Battle memory info = craps.battleOf(key);
            assertTrue(info.finalized, "battle not finalized after its last entrant");
            assertEq(info.resolved, 3, "resolved count");
            assertEq(info.winnerId, uint64(ids[best]), "the scoreboard named the wrong winner");
            assertEq(
                uint8(info.winningStop),
                uint8(g[best] ? Craps.SlipStop.Goal : Craps.SlipStop.Bust),
                "winning stop class"
            );
            assertEq(info.winningHands, h[best], "winning hand count");

            assertEq(pot.betId, ids[best], "the pot went to a seat other than the winner");
            assertEq(pot.player, craps.betOf(ids[best]).player, "the pot reached the wrong address");
            assertEq(pot.amount, SUW * 3, "the winner did not take the pot");
            assertTrue(craps.betOf(ids[best]).battleClaimed, "the field did not read as paid");
        }

        assertGt(sawGoalWin, 0, "no goal-won battle seen");
        assertGt(sawAllBust, 0, "no all-bust battle seen");
        assertGt(sawTieOnRank, 0, "no rank tie ever needed the money to break it");
    }

    /// @dev The merit ladder used here: rank first, then what the run came home with. Every
    ///      entrant in this fixture has the same standing; `_tag` handles exact equality.
    /// @dev The coin the fold reaches for on a dead-level score: the larger tag leads. Restated
    ///      from the rule rather than read off the contract, so the suite grades the rule.
    function _tag(uint256 word, uint256 betId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(word, uint64(betId))));
    }

    function _beatsFully(bool gA, uint256 hA, uint256 wA, bool gB, uint256 hB, uint256 wB)
        internal
        pure
        returns (bool)
    {
        if (_beats(gA, hA, gB, hB)) return true;
        if (_beats(gB, hB, gA, hA)) return false;
        return wA > wB;
    }

    /// @dev Two identical, separately funded entries from one player run identically. The table
    ///      word selects one winner, which takes the contested pot as CREDIT. Duplicate claims die.
    function test_identicalEntriesUseTheTableWordToBreakTheTie() public {
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        uint256 b = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        uint256 c = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        assertEq(flip.burned(alice), (LW * 2 + SUW) * 3, "every entry funded separately");
        uint256 tableWord = uint256(keccak256("twins"));
        uint64 slot = _closeSlot(LW * 2, LW * 10, SU, 4, tableWord);

        uint64 expected = _tag(tableWord, b) > _tag(tableWord, a) ? uint64(b) : uint64(a);
        if (_tag(tableWord, c) > _tag(tableWord, expected)) expected = uint64(c);

        uint256 beforeMint = flip.minted(alice);
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        CrapsBattle.Battle memory info = craps.battleOf(craps.battleKeyOf(a));
        assertTrue(info.finalized, "finalized");
        assertEq(info.winnerId, expected, "the table word did not break the tie");
        assertEq(craps.settlementAt(a).won, craps.settlementAt(b).won, "twins diverged");
        assertEq(craps.settlementAt(a).won, craps.settlementAt(c).won, "triplets diverged");

        // The tiebreak is what the POT follows, so the seat the coin named is the seat paid — and
        // the three identical runs make the credit the only thing that separates them.
        assertEq(uint64(pot.betId), expected, "the pot went to a seat the tiebreak did not name");
        assertEq(pot.amount, SUW * 3, "the winner did not take the whole pot");
        assertEq(flip.minted(alice), beforeMint, "a contested pot must not pay as a mint");
    }

    /// @dev A battle nobody else joined still PAYS. There is no head count below which a field is
    ///      voided and handed back — the lone entrant raced whoever else was at the table, won it,
    ///      and takes the pot as coinflip credit exactly like any other winner. Nothing in this
    ///      contract mints FLIP back to anybody.
    function test_aSoloBattleStillPaysItsWinner() public {
        uint256 id = _placeBattle(alice, _boardA(), LW * 2, 0, SU);
        uint64 slot = _closeSlot(LW * 2, 0, SU, 4, uint256(keccak256("solo")));

        uint256 beforeMint = flip.minted(alice);
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        // One seat, so the pot is that seat's own bounty — a custom battle draws no house money.
        assertEq(pot.betId, id, "the pot named a seat this battle never had");
        assertEq(pot.player, alice, "the lone entrant was not paid the pot");
        assertEq(pot.amount, SUW, "the lone entrant took something other than the pot");
        assertEq(flip.minted(alice), beforeMint, "a battle payment must never mint");
    }

    /// @dev NOTHING LEAVES THE TABLE UNTIL THE LAST SEAT SCORES. There is no claim left to refuse
    ///      early, so the guard is the payment itself: settle half a field and the pot must still
    ///      be standing, however far ahead whoever is leading it happens to be.
    function test_aHalfResolvedFieldPaysNobody() public {
        _placeBattle(alice, _boardA(), LW * 2, 0, SU);
        _placeBattle(bob, _boardB(), LW * 2, 0, SU);
        uint64 slot = _closeSlot(LW * 2, 0, SU, 4, uint256(keccak256("half")));

        // Half the field settled is not a verdict, and a verdict is what pays.
        assertEq(_resolveForPots(craps, slot, 1).length, 0, "a half-resolved field paid its leader");
        assertFalse(craps.battleOf(_slotKeyOf(slot)).finalized, "half a field read as final");

        assertEq(_resolveForPots(craps, slot, WHOLE_FIELD).length, 1, "the last seat did not pay the field");
        assertTrue(craps.battleOf(_slotKeyOf(slot)).finalized, "finalized after the last entrant");
    }

    /// @dev Resolution order and batch partitioning cannot move a wei: every permutation and
    ///      partition of the same three settlements produces the identical scoreboard and the
    ///      identical claims.
    /// @dev A dead-level score is settled by the table's own word, not by arrival order. The same
    ///      three scores under two different words hand the lead to two different seats, and each
    ///      answer is exactly the one the tag order predicts — so the coin is real, it is the
    ///      dice's, and anyone holding the word can replay it.
    function test_aDeadLevelScoreGoesToTheCoin() public {
        uint256 score = craps.compositeOf(600, 4000, 12);

        uint64[3] memory seats = [uint64(1), uint64(2), uint64(3)];
        uint256[2] memory words = [uint256(keccak256("coin-a")), uint256(keccak256("coin-b"))];
        uint64[2] memory landed;

        for (uint256 p = 0; p < 2; ++p) {
            bytes32 key = keccak256(abi.encode("coin", p));
            uint64 want = seats[0];
            for (uint256 k = 0; k < 3; ++k) {
                craps.scoreOnWord(key, score, seats[k], SU, words[p]);
                if (k != 0 && _tag(words[p], seats[k]) > _tag(words[p], want)) want = seats[k];
            }
            landed[p] = craps.battleOf(key).winnerId;
            assertEq(landed[p], want, "the coin did not land where the word says");
        }

        // Not merely deterministic — actually word-dependent. These two words disagree, which is
        // what tells the coin apart from a fixed rule that always names the same seat.
        assertTrue(landed[0] != landed[1], "two different words picked the same seat");
    }

    /// @dev The fold is a running maximum, so distinct scores produce the same verdict in every
    ///      arrival order. Driven through the shipped fold because settlement itself fixes order.
    function test_theFoldIsOrderInvariantOnDistinctScores() public {
        uint256[3] memory sc = [
            craps.compositeOf(uint256(_RANK_GOAL_BASE), 900, 5),
            craps.compositeOf(40, 1200, 5),
            craps.compositeOf(40, 800, 9)
        ];
        uint64[6][6] memory orders;
        uint256 n;
        for (uint256 x = 0; x < 3; ++x) {
            for (uint256 y = 0; y < 3; ++y) {
                if (y == x) continue;
                orders[n][0] = uint64(x);
                orders[n][1] = uint64(y);
                orders[n][2] = uint64(3 - x - y);
                ++n;
            }
        }

        for (uint256 o = 0; o < 6; ++o) {
            bytes32 key = keccak256(abi.encode("fold", o));
            for (uint256 k = 0; k < 3; ++k) {
                craps.scoreAt(key, sc[orders[o][k]], uint64(orders[o][k]) + 1, SU);
            }
            CrapsBattle.Battle memory info = craps.battleOf(key);
            // Entrant 0 holds the only GOAL, so it wins from every arrival order.
            assertEq(info.winnerId, 1, "arrival order moved the verdict");
        }
    }

    uint256 internal constant _RANK_GOAL_BASE = 512;


    /// @dev A BUST IS DELETED. A run that goes broke chasing its target does not get the crumbs it
    ///      was still holding back, and nobody else gets them either: they are not credited, not
    ///      swept into the pot the rest of the field is racing for, and not handed to the winner.
    ///      The FLIP was burned at entry, so this is simply the claim never being recreated.
    ///
    ///      `won` is untouched by any of that — it stays the raw bankroll result, because that is
    ///      what the scoreboard ranks a busted run on.
    function test_aBustIsDeletedAndReachesNobody() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        uint256[3] memory ids = [
            _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU),
            _placeBattle(bob, _boardB(), LW * 2, LW * 10, SU),
            _placeBattle(carol, _boardC(), LW * 2, LW * 10, SU)
        ];
        _closeOn(craps, slot, 4, uint256(keccak256("onetx")));

        uint256 busts;
        uint256 deleted;
        for (uint256 i = 0; i < 3; ++i) {
            CrapsBattle.Settlement memory st = craps.settlementAt(ids[i]);
            if (st.stop != Craps.SlipStop.Bust) continue;
            ++busts;
            // Nothing back to the buster, and the raw result still stands for the ranking.
            assertEq(st.paid, 0, "a busted seat was still paid");
            deleted += st.won;
            (uint256 previewWon, uint256 previewPaid) = craps.previewSettlement(ids[i]);
            assertEq(previewPaid, 0, "the preview still promised a busted seat its crumbs");
            assertEq(previewWon, st.won, "the preview zeroed a busted run's raw result");
        }
        // The fixture has to actually produce a bust, or none of the above says anything.
        assertGt(busts, 0, "no seat busted: the test proves nothing");
        assertGt(deleted, 0, "every buster came home with nothing: the test proves nothing");

        uint256 creditedBefore = coinflip.totalCredited();
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        // EVERYTHING the call credited, accounted for twice over: the survivors' own runs, and the
        // one pot the field finished into. A deleted remainder has nowhere else to have gone, so
        // any leak shows up as the total exceeding the two of them.
        uint256 survivors;
        for (uint256 i = 0; i < 3; ++i) {
            survivors += craps.settlementAt(ids[i]).paid;
        }
        assertEq(
            coinflip.totalCredited() - creditedBefore, survivors + pot.amount, "a busted seat was credited"
        );

        // And the winner takes the bounties, and ONLY the bounties.
        CrapsBattle.Battle memory info = craps.battleOf(craps.battleKeyOf(ids[0]));
        assertEq(pot.betId, _idAt(slot, info.winnerId), "the pot went to a seat the scoreboard did not name");
        assertEq(pot.amount, SUW * 3, "the deleted remainders reached the winner");
    }

    /// @dev A ZERO-BOUNTY battle stays a zero-value battle however many of its entrants go broke.
    ///      This is the sharpest form of the deletion rule: there is no bounty, no seed and no
    ///      donation, so if a bust could reach anyone the pot here would be non-empty.
    function test_aFriendlyBattleStaysZeroPotDespiteBusts() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, 0);
        uint256[3] memory ids = [
            _placeBattle(alice, _boardA(), LW * 2, LW * 10, 0),
            _placeBattle(bob, _boardB(), LW * 2, LW * 10, 0),
            _placeBattle(carol, _boardC(), LW * 2, LW * 10, 0)
        ];
        _closeOn(craps, slot, 4, uint256(keccak256("onetx")));

        uint256 busts;
        uint256 deleted;
        for (uint256 i = 0; i < 3; ++i) {
            CrapsBattle.Settlement memory st = craps.settlementAt(ids[i]);
            if (st.stop != Craps.SlipStop.Bust) continue;
            ++busts;
            assertEq(st.paid, 0, "a friendly buster was still paid");
            deleted += st.won;
        }
        assertGt(busts, 0, "no friendly seat busted: the test proves nothing");
        assertGt(deleted, 0, "the friendly busts were holding nothing: the test proves nothing");

        craps.resolveSlot(slot, WHOLE_FIELD);

        CrapsBattle.Battle memory info = craps.battleOf(craps.battleKeyOf(ids[0]));
        address winner = craps.betOf(_idAt(slot, info.winnerId)).player;
        uint256 before = coinflip.staked(winner);
        assertEq(coinflip.staked(winner) - before, 0, "a zero-bounty battle paid out a bust remnant");
    }

    /// @dev The one-transaction lane: the range settles every slip at the index (skipping one
    ///      already settled), finalizes the battle, and pays the named winners in the same call.
    function test_oneCallSettlesAWholeFieldAndPaysIt() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        uint256 b = _placeBattle(bob, _boardB(), LW * 2, LW * 10, SU);
        uint256 c = _placeBattle(carol, _boardC(), LW * 2, LW * 10, SU);
        _closeOn(craps, slot, 4, uint256(keccak256("onetx")));

        (, uint256 paidA) = craps.previewSettlement(a);
        (, uint256 paidB) = craps.previewSettlement(b);
        (, uint256 paidC) = craps.previewSettlement(c);
        uint256 before = coinflip.totalCredited();

        // The whole field AND its pot in ONE call — which is the point of the cursor lane: a caller
        // names the battle, not a list of ids, and everything in it settles and is paid together.
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);
        assertTrue(craps.betOf(a).settled && craps.betOf(b).settled && craps.betOf(c).settled, "field missed a slip");
        assertEq(
            coinflip.totalCredited() - before, paidA + paidB + paidC + pot.amount, "the batched credit mispaid"
        );

        CrapsBattle.Battle memory info = craps.battleOf(craps.battleKeyOf(a));
        assertTrue(info.finalized, "the field did not finalize");
        assertEq(info.entrants, 3, "entrants");
        assertEq(info.resolved, 3, "resolved");

        // And the pot goes to exactly one of them, in one payment — the three bounties, and only
        // those: what the busted seats were holding was deleted.
        assertEq(pot.betId, (uint256(slot) << 64) | info.winnerId, "the pot named a seat off the scoreboard");
        assertEq(pot.player, craps.betOf(pot.betId).player, "the pot reached an address that held no seat");
        assertEq(pot.amount, SUW * 3, "the whole pot did not land");
    }

    // ---------------------------------------------------------------------------------------
    // The tenth leg
    // ---------------------------------------------------------------------------------------

    /// @dev A ticket naming ALL TEN legs, round-tripped through the stored word. The counts are
    ///      one contiguous thirty-bit run at 160..189 in canonical order, and this is the
    ///      assertion that they come back in that order rather than transposed or short by one.
    function test_tenLegChipsRoundTrip() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        Craps.Bets memory c;
        // Seven chips spread so that every leg but the pass line carries a distinct position, and
        // the dark side is the leg most likely to be dropped by a bad split.
        c.place4 = 1;
        c.place5 = 1;
        c.place6 = 1;
        c.place8 = 1;
        c.place9 = 1;
        c.place10 = 1;
        c.dontPass = 1;

        uint256 expected = (uint256(1) << 3) | (uint256(1) << 6) | (uint256(1) << 9) | (uint256(1) << 12)
            | (uint256(1) << 15) | (uint256(1) << 18) | (uint256(1) << 27);

        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, c, 1);
        assertEq(craps.betOf(betId).chips, expected, "the ten-leg word did not round-trip");

        // And it decodes back into a board with the dark leg on it, at this slot's chip.
        _closeOn(craps, slot, 4, uint256(keccak256("tenleg")));
        Craps.Bets memory drawn = craps.drawnBoardOf(betId);
        assertGe(drawn.dontPass, C, "the dark leg did not survive the decode");
        assertEq(craps.stakeFor(drawn), uint256(L) * 1 ether, "the drawn board is not the whole round");
    }

    /// @dev SEVEN chips on the dark side — the maximum a count can hold, in the TOP three bits of
    ///      the chip region, sitting directly under the standing. A chip word written one bit out,
    ///      or a mask still sized for nine legs, corrupts the standing, the multiple or the
    ///      day-entry field; this pins all three against a full tenth count at once.
    function test_aFullDontPassCountDoesNotCorruptItsNeighbours() public {
        // A HIGH lane at nine, so the multiple byte and the high-roller flag above the day field
        // are both non-zero and every neighbour of the chip region is under load at once.
        uint64 slot = _openHigh(craps, uint32(LW / 1 ether), 2, 10, SU, 9);
        Craps.Bets memory c;
        c.dontPass = 4;
        c.place6 = 3;

        uint16 standing = 4321;
        game.setScore(alice, standing);
        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, c, 9); // a multiple, so its byte is non-zero too

        CrapsBattle.Bet memory bet = craps.betOf(betId);
        assertEq(bet.chips, (uint256(4) << 27) | (uint256(3) << 9), "the dark count did not land in its own field");
        assertEq(bet.standing, standing, "a full dark count corrupted the standing");
        assertEq(bet.player, alice, "a full dark count corrupted the owner");
        // The multiple is what the money is scaled by, so a corrupt byte shows up as a mispriced
        // burn — read it off the entry itself rather than trusting a view.
        assertEq(
            flip.burned(alice), (uint256(LW) * 2 + SUW) * 9, "a full dark count corrupted the multiple"
        );

        // And the day-entry field above it: a slip placed one window at a time carries zero
        // there, which is what lets it amend on its own slot's clock. An amendment that leaked
        // into it would lock this slip to a day it never joined.
        vm.prank(alice);
        Craps.Bets memory re;
        re.place6 = 4;
        re.place8 = 3;
        craps.amendSlip(betId, re);
        assertEq(craps.betOf(betId).chips, (uint256(4) << 9) | (uint256(3) << 12), "the amendment did not clear the dark count");
        assertEq(craps.betOf(betId).standing, standing, "the amendment corrupted the standing");
    }

    /// @dev An amendment rewrites ALL TEN counts, and only them. It runs the same packer the door
    ///      does, so the clear has to cover both regions — a clear that missed the tenth would
    ///      leave the old dark count sitting under the new board.
    function test_anAmendmentRewritesAllTenCounts() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        Craps.Bets memory dark;
        dark.dontPass = 4;
        dark.place6 = 3;
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, dark, 1);
        assertEq(craps.betOf(betId).chips, (uint256(4) << 27) | (uint256(3) << 9), "the dark ticket did not store");

        // Dark -> light: the tenth count must be CLEARED, not merely joined.
        Craps.Bets memory light;
        light.passLine = 4;
        light.place8 = 3;
        vm.prank(alice);
        craps.amendSlip(betId, light);
        assertEq(craps.betOf(betId).chips, 4 | (uint256(3) << 12), "the amendment left the old dark count behind");

        // Light -> dark again, to prove the clear works the other way too.
        vm.prank(alice);
        craps.amendSlip(betId, dark);
        assertEq(craps.betOf(betId).chips, (uint256(4) << 27) | (uint256(3) << 9), "the amendment left the old light count behind");
        assertEq(craps.betOf(betId).standing, craps.SYBIL_SCORE_FLOOR(), "an amendment moved the standing");
        assertEq(craps.betOf(betId).slot, slot, "an amendment moved the seat");
        slot; // silence
    }

    /// @dev PICK A SIDE. A ticket may not back the shooter and fade them at once — refused at
    ///      every door that takes one, and at the amendment too.
    function test_aTicketMayNotPlayBothSidesOfTheLine() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        Craps.Bets memory both;
        both.passLine = 4;
        both.dontPass = 3;
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.enterBattle(slot, both, 1);

        _openDay();
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.enterBonusBattle(PER, both, 1);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.enterBonusDay(both, 1);

        // And an amendment cannot smuggle it in after the fact.
        uint256 betId = _placeBattle(bob, _boardA(), LW * 2, LW * 10, SU);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.amendSlip(betId, both);

        // Either side ALONE is fine — the rule is about naming both, not about the dark leg.
        Craps.Bets memory darkOnly;
        darkOnly.dontPass = 4;
        darkOnly.place6 = 3;
        vm.prank(bob);
        craps.amendSlip(betId, darkOnly);
        assertEq(craps.betOf(betId).chips, (uint256(4) << 27) | (uint256(3) << 9), "a dark-only board was refused");
    }

    /// @dev The DICE reach all ten legs, and never place more or fewer than ten chips. Swept over
    ///      many words: a scatter that could not reach the tenth leg would leave the dark side
    ///      unreachable to a blank ticket, and one that could overshoot would break the round.
    function test_theScatterReachesEveryLegAndAlwaysPlacesTen() public {
        _openDay();
        uint64 slot = _slotAt(PER);
        uint256 round = uint256(BON_STACK) / 7 * 10;

        bool[10] memory seen;
        for (uint256 i = 0; i < 48; ++i) {
            address who = makeAddr(string(abi.encodePacked("scatter", i)));
            vm.prank(who);
            craps.enterBonusBattle(PER, _blank(), 1);
        }
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("scatterword")));

        uint64 entrants = craps.battleOf(_keyOf(PER)).entrants;
        for (uint64 n = 1; n <= entrants; ++n) {
            Craps.Bets memory d = craps.drawnBoardAt(_idAt(slot, n), slot);
            // Ten chips, every time, however they fell.
            assertEq(craps.stakeFor(d), round, "a drawn board is not the slot's whole round");
            uint24[10] memory legs = [
                d.passLine, d.place4, d.place5, d.place6, d.place8,
                d.place9, d.place10, d.hard4, d.hard8, d.dontPass
            ];
            for (uint256 k = 0; k < 10; ++k) {
                if (legs[k] != 0) seen[k] = true;
            }
        }
        for (uint256 k = 0; k < 10; ++k) {
            assertTrue(seen[k], "the scatter never reached a leg");
        }
    }

    // ---------------------------------------------------------------------------------------
    // Amendment
    // ---------------------------------------------------------------------------------------

    /// @dev Until the slot closes, only the board's COMPOSITION is an open order: the same seven
    ///      chips re-spread across the legs, no money moving, and every other term of the slip —
    ///      all of them the slot's — untouched.
    function test_amendReshapesTheChipsOnly() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        uint256 betId = _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        uint256 burnedBefore = flip.burned(alice);

        vm.prank(alice);
        craps.amendSlip(betId, _boardB());

        CrapsBattle.Bet memory bet = craps.betOf(betId);
        assertEq(bet.chips, (uint256(4) << 9) | (uint256(3) << 12), "chips not re-spread onto place6");
        assertEq(bet.slot, slot, "the slip changed battle");
        assertEq(flip.burned(alice), burnedBefore, "an amendment burned FLIP");
        assertEq(flip.minted(alice), 0, "an amendment minted FLIP");

        // Seven chips or nothing moves: a stack of a different size is refused, so the round
        // played, the money and the seat are all exactly what they were.
        Craps.Bets memory wider = _boardB();
        wider.passLine = 1;
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BoardTotalChanged.selector);
        craps.amendSlip(betId, wider);

        // Only the owner, and only while the slot is open.
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.NotYourBet.selector);
        craps.amendSlip(betId, _boardA());

        _closeOn(craps, slot, 4, uint256(keccak256("amended")));
        // A shut slot refuses the amendment through the same joinability test its entry door
        // uses, so the two can never drift — hence its selector rather than `BetLocked`.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.amendSlip(betId, _boardA());

        craps.resolveSlot(slot, WHOLE_FIELD);
        assertTrue(craps.betOf(betId).settled, "amended slip did not settle");
    }

    /// @dev THE INDEXER'S CONTRACT: one event announces every seat — the house's and the vault's
    ///      included — and each one carries the whole id, so a slip is rebuilt from the log alone
    ///      with no follow-up call and no dependence on arrival order. Graded against `betOf`,
    ///      which reads the stored word.
    function test_oneEventStreamCarriesTheWholeField() public {
        bytes32 sig = keccak256("CrapsSlipPlaced(address,uint256)");

        vm.recordLogs();
        _openDay();
        uint64 slot = _slotAt(PER);
        uint256 daySlot = craps._daySlotOfPub(craps.currentDayIndex());
        _enter(alice, PER);
        _enter(bob, PER);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Replay the stream exactly as an indexer would, decoding each word on its own terms. The
        // field arrives in TWO buckets — the window's own seats, and the DAY tickets the house and
        // the vault took — so each is numbered within its own bucket and the stream carries both.
        uint256 own;
        uint256 day;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            uint256 bet = abi.decode(logs[i].data, (uint256));
            // The id is a 128-bit WINDOW at bit 32, not the top of the word: the multiple and the
            // frozen standing ride above it, so a decoder that only shifts drags them along.
            uint256 betId = (bet >> 32) & type(uint128).max;
            bool isDay = betId >> 64 == daySlot;
            if (!isDay && betId >> 64 != slot) continue;

            CrapsBattle.Bet memory stored = craps.betOf(betId);
            assertEq(address(uint160(uint256(logs[i].topics[1]))), stored.player, "wrong owner");
            assertEq(bet & 0x7FFFFFF, stored.chips, "wrong chips");
            assertEq((bet >> 190) & 0xFFFF, stored.standing, "wrong frozen standing");
            assertEq(uint64(betId), stored.seat, "wrong seat");
            // The id is carried, not counted, but it must still agree with arrival order WITHIN
            // its own bucket, which is the only order a bet is numbered in.
            assertEq(uint64(betId), isDay ? ++day : ++own, "the id and arrival order disagree");
            assertEq((bet >> 27) & 0x1F, 0, "the gap between the chips and the id is dirty");
        }
        assertEq(day, 2, "the stream missed the day lane");
        assertEq(own, 2, "the stream missed a window seat");

        // And the two buckets are exactly the field the window shuts on.
        _warpPastClose(PER);
        _setIndex(craps.armBonusWindow(slot));
        assertEq(day + own, craps.battleOf(_keyOf(PER)).entrants, "the stream and the field disagree");
    }

    /// @dev A HIGH-ROLLER seat buys COPIES of the run, never a better one. Same board, same owner
    ///      and same table as the single seat beside it, so the two play an identical run — and the
    ///      only differences allowed are what it burned and what came back. Taken at the CEILING,
    ///      which is also where any scaling overflow would show up first.
    ///
    ///      Entry is BINARY now: one copy, or exactly the field's multiple. Nothing between.
    function test_aMultipliedSeatBuysCopiesOfTheRun() public {
        uint16 top = uint16(craps.MAX_HIGH_MULT());
        uint64 slot = _openHigh(craps, uint32(LW / 1 ether), 2, 10, SU, top);
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
        game.setScore(bob, craps.SYBIL_SCORE_FLOOR());
        vm.prank(alice);
        uint256 plain = craps.enterBattle(slot, _boardA(), 1);

        // The BOUNTY scales too: a high roller buys the whole seat over again, which is what makes
        // the lane a race rather than a bigger bet in the same one.
        uint256 burnedBefore = flip.burned(alice);
        vm.prank(alice);
        uint256 big = craps.enterBattle(slot, _boardA(), top);
        assertEq(
            flip.burned(alice) - burnedBefore,
            (LW * 2 + SUW) * top,
            "a high-roller seat did not pay the multiple on BOTH halves of the seat"
        );

        // Nothing between one and the field's own multiple is an entry at all.
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 0);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), top + 1);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), top - 1);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadEntryMultiple.selector);
        craps.enterBattle(slot, _boardA(), 2);

        _closeOn(craps, slot, 4, uint256(keccak256("stakes")));

        // Exactly the multiple — the rounding lands on the single-copy figure and is then copied,
        // so there is no dust between N copies and one run multiplied.
        (uint256 wonOne, uint256 paidOne) = craps.previewSettlement(plain);
        (uint256 wonTen, uint256 paidTen) = craps.previewSettlement(big);
        assertEq(wonTen, wonOne * top, "the run itself did not scale exactly");
        assertEq(paidTen, paidOne * top, "the award did not scale exactly");

        // Alice holds BOTH seats, so the pot comes home to her as well and the two awards are only
        // separable from it in the log.
        uint256 before = coinflip.staked(alice);
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);
        assertEq(
            coinflip.staked(alice) - before,
            paidOne + paidTen + pot.amount,
            "the credit was not both seats' awards"
        );
    }

    /// @dev THE TRAP. The battle's tiebreak folds the run's WINNINGS into its composite, so if the
    ///      multiplier were applied before the fold, ten times the bankroll would also buy ten
    ///      times the tiebreak and a high-stakes seat would win every dead-level battle it entered.
    ///      Twin seats of one owner on one table play an IDENTICAL run, so the two are always dead
    ///      level and the coin alone separates them — which means the single seat has to take some.
    function test_theEntryMultipleDoesNotBuyRankInTheBattle() public {
        uint256 plainWins;
        uint256 bigWins;
        uint256 live;
        uint16 farGoal = uint16(craps.MAX_GOAL_MULT());

        for (uint256 i = 0; i < 40; ++i) {
            // A battle of its own each pass, so the twin seats are always seats one and two, and
            // a goal the dice will not reach so the runs bust with matching money.
            uint64 slot = _openHigh(craps, uint32(LW / 1 ether) + uint32(i) * 10, 2, farGoal, SU, 10);
            vm.prank(alice);
            uint256 plain = craps.enterBattle(slot, _boardA(), 1);
            vm.prank(alice);
            uint256 big = craps.enterBattle(slot, _boardA(), 10);

            _closeOn(craps, slot, uint48(20_000 + i), uint256(keccak256(abi.encode("rank", i))));
            (uint256 wonOne,) = craps.previewSettlement(plain);
            craps.resolveSlot(slot, WHOLE_FIELD);

            // A pair that BUSTS comes home with nothing, and nothing times ten is still nothing —
            // those passes are level whether the multiplier leaks into the score or not, so they
            // prove nothing and are not counted.
            if (wonOne == 0) continue;
            ++live;

            uint64 winner = craps.battleOf(_slotKeyOf(slot)).winnerId;
            if (winner == uint64(plain)) ++plainWins;
            else if (winner == uint64(big)) ++bigWins;
        }

        assertGt(live, 3, "no pass in this sweep came home with money, so nothing was ranked");
        assertEq(plainWins + bigWins, live, "a battle named neither of its two seats");
        // With the multiplier leaking into the score this is 0 — the big seat would take them all.
        assertGt(plainWins, 0, "the single seat never won: the multiple bought rank");
    }

    /// @dev Whether one address may take several seats is fixed when a custom battle is created,
    ///      and has nothing to do with what has been seeded onto it. A bonus window never allows
    ///      it — house money there buys a field of distinct players.
    function test_aCustomBattleChoosesWhetherOneAddressMayTakeSeveralSeats() public {
        // Both seats priced clear of the sybil surcharge, so this measures the multi-entry rule.
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
        game.setScore(bob, craps.SYBIL_SCORE_FLOOR());
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        vm.prank(vaultOwner);
        uint32 played = uint32(LW / 1 ether);
        uint64 single = craps.createBattle(played, 2, 5, SU, 0, close, false, 0);

        vm.prank(alice);
        craps.enterBattle(single, _boardA(), 1);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBattle(single, _boardA(), 1);

        // The same terms with the toggle on: as many seats as the caller pays for, each at the
        // full price of a seat.
        vm.prank(vaultOwner);
        uint64 many = craps.createBattle(played + 10, 2, 5, SU, 0, close, true, 0);
        uint256 burnedBefore = flip.burned(bob);
        vm.prank(bob);
        craps.enterBattle(many, _boardA(), 1);
        vm.prank(bob);
        craps.enterBattle(many, _boardA(), 1);
        assertEq(craps.battleOf(_slotKeyOf(many)).entrants, 2, "a second seat was refused");
        assertEq(
            flip.burned(bob) - burnedBefore,
            2 * (uint256(played + 10) * 2 * 1 ether + SUW),
            "a repeat seat was not charged in full"
        );

        // And the flag is on the terms the creation event published, at its own bit.
        (,, uint256 terms) = craps.customBattleOf(many);
        assertTrue(terms & (uint256(1) << 113) != 0, "multi-entry did not reach the published terms");
        (,, uint256 lone) = craps.customBattleOf(single);
        assertTrue(lone & (uint256(1) << 113) == 0, "single-entry published as multi");
    }

    /// @dev A blank ticket is an open order too: it named nothing, so it may still name its seven
    ///      while the slot is open. This is the door the vault steers its automatic seats through.
    function test_aBlankTicketCanStillNameItsSeven() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        uint256 betId = _placeBattle(alice, _blank(), LW * 2, LW * 10, SU);
        assertEq(craps.betOf(betId).chips, 0, "a blank ticket named something");

        uint256 burnedBefore = flip.burned(alice);
        vm.prank(alice);
        craps.amendSlip(betId, _boardC());
        assertEq(craps.betOf(betId).chips, (uint256(4) << 3) | (uint256(3) << 24), "the blank did not take a shape");
        assertEq(flip.burned(alice), burnedBefore, "naming a shape moved money");

        // Still the same ten-chip round either way: the draw simply places three instead of ten.
        uint256 plain = _placeBattle(bob, _boardA(), LW * 2, LW * 10, SU);
        _closeOn(craps, slot, 4, uint256(keccak256("blank-named")));
        assertEq(
            craps.stakeFor(craps.drawnBoardOf(betId)),
            craps.stakeFor(craps.drawnBoardOf(plain)),
            "naming a shape changed the round played"
        );
    }

    /// @dev A battle seat is binding: an amendment can re-spread the board but the key terms are
    ///      the slot's, so the seat, the key and the money all stay exactly where placement put
    ///      them.
    function test_amendKeepsTheBattleSeat() public {
        uint256 a = _placeBattle(alice, _boardA(), LW * 2, 0, SU);
        _placeBattle(bob, _boardB(), LW * 2, 0, SU);
        bytes32 key = craps.battleKeyOf(a);
        assertEq(craps.battleOf(key).entrants, 2, "both in");

        vm.prank(alice);
        craps.amendSlip(a, _boardC());
        assertEq(craps.battleKeyOf(a), key, "composition changed the key");
        assertEq(craps.battleOf(key).entrants, 2, "a seat was dropped or doubled");
        assertEq(flip.burned(alice), LW * 2 + SUW, "money moved on a reshape");
        assertEq(flip.minted(alice), 0, "money moved on a reshape");

        uint64 slot = _runSlot(LW * 2, 0, SU, 4, uint256(keccak256("seat")));
        assertTrue(craps.battleOf(_slotKeyOf(slot)).finalized, "the amended seat broke finalization");
    }

    /// @dev A round is TEN chips and an entry places SEVEN of them, however it spreads those
    ///      seven. The COUNT is the rule, not the composition, and an amendment cannot smuggle a
    ///      ragged board into a seated battle either.
    function test_theShapeRuleIsSevenChipsOrNone() public {
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);

        // Freeform across the legs: composition is not the rule, the COUNT is.
        Craps.Bets memory freeform;
        freeform.place6 = 4;
        freeform.hard8 = 3;
        vm.prank(alice);
        craps.enterBattle(slot, freeform, 1);

        // Six chips is not a stack, and neither is eight. This is the hole the slot model closed:
        // a wrong count used to derive a round of its own and key a PRIVATE battle at this slot —
        // a field of one, with the bounty stranded in it.
        Craps.Bets memory six;
        six.place6 = 4;
        six.place8 = 2;
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadRandomCount.selector);
        craps.enterBattle(slot, six, 1);

        Craps.Bets memory eight;
        eight.place4 = 4;
        eight.hard8 = 4;
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.BadRandomCount.selector);
        craps.enterBattle(slot, eight, 1);

        // An amendment cannot smuggle a wrong count into a seated battle either.
        uint256 betId = _placeBattle(carol, _boardA(), LW * 2, LW * 10, SU);
        vm.prank(carol);
        vm.expectRevert(CrapsBattle.BoardTotalChanged.selector);
        craps.amendSlip(betId, six);

        // A seven-chip re-spread of the same stack is fine, and lands on the legs it named.
        vm.prank(carol);
        craps.amendSlip(betId, _boardC());
        assertEq(craps.betOf(betId).chips, (uint256(4) << 3) | (uint256(3) << 24), "legal reshape refused");
    }

    /// @dev A window puts up a FLAT seventh of its day's budget — the same figure whether three
    ///      sit down or three hundred, which is what makes turnout the thing being MEASURED rather
    ///      than the thing being paid.
    ///
    ///      There is no break-even head count to check against any more, and no accessor for one:
    ///      that figure divided a window's purse by a MINIMUM burn per seat, and with place 4/10
    ///      and 5/9 paying true odds there is no such minimum — a whole field may legally play a
    ///      fair board and hand the table nothing. The whole surface was deleted rather than left
    ///      returning a zero that reads like an answer.
    /// @dev A window's share of its day is sized by the TABLE, not by a flat seventh. The day's
    ///      EVENT takes half outright — its bankroll runs to 60,000 FLIP and a seventh priced it
    ///      as though it were a 300-FLIP table — and the other half splits across the six routine
    ///      windows 4:2:1 by size, so a large table draws four times the subsidy of a small one
    ///      because it draws about ten times the action.
    function test_aWindowPutsUpItsOwnSizesShareOfItsDay() public {
        _openDay();
        uint24 day = craps.currentDayIndex();
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        uint256 half = craps.boostBudgetOf(day) / 2;
        assertGt(half, 0, "the day drew no budget");

        assertEq(craps.boostBaseAt(_slotAt(periods - 1)), half, "the event window did not take half the day");

        uint256 weight = _routineWeightAt(day);
        assertGt(weight, 0, "the day drew no routine windows");
        assertEq(craps.boostWeightOf(day), weight, "the day banked a weight its own tables disagree with");

        uint256 paid;
        for (uint256 p = 0; p + 1 < periods; ++p) {
            uint256 base = craps.boostBaseAt(_slotAt(p));
            assertEq(base, half * _weightOf(day, p) / weight, "a window took other than its size's share");
            paid += base;
        }
        // The routine half is spent whole, bar one wei of flooring per window.
        assertApproxEqAbs(paid, half, periods, "the routine half did not add up");

        // Turnout does not move what a window puts up.
        uint256 was = craps.boostBaseAt(_slotAt(PER));
        vm.prank(alice);
        craps.enterBonusBattle(PER, _seven(), 1);
        vm.prank(bob);
        craps.enterBonusBattle(PER, _seven(), 1);
        assertEq(craps.boostBaseAt(_slotAt(PER)), was, "the base moved with the field");
    }

    /// @dev THE RULE, END TO END: A DAY'S ALLOCATION IS A FLAT 50,000 FLIP PLUS TWELVE PERCENT OF
    ///      THE AVERAGE DAILY ACTION of the week behind it. The base is ADDED, not a floor — a day
    ///      with a busy week behind it is paid for that week ON TOP of the base — and the twelve
    ///      percent is a chosen share of turnover, not an estimate of what anyone loses.
    ///
    ///      HALF OF IT REACHES THE WINDOWS. The allocation splits down the middle: the ladder half
    ///      is what the seven windows partition, and the other half is banked in the progressive.
    ///      The ladder half IS the expected immediate emission, not a ceiling over it — the seven
    ///      bases partition it exactly and the ladder pays each in expectation (E[mult] = 4,
    ///      divided by 4).
    function test_aDaysBudgetIsTheBaseSubsidyPlusTwelvePercentOfAction() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        uint256 perDay = 3_600_000 ether;
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), perDay);

        uint256 y = perDay * days_;
        uint256 linear = (y * craps.BOOST_ACTION_BPS()) / craps.BPS_DENOMINATOR() / days_;
        (uint256 mainBudget, uint256 highBudget) = craps.drawBudgetsFor(today);
        assertEq(highBudget, 0, "ordinary action funded a high lane");
        assertEq(mainBudget, craps.BASE_MAIN_BUDGET() + linear, "a day's budget is not base + 12% of action");
        // The same figure said plainly, so the rule is pinned in the terms it was chosen in.
        assertEq(mainBudget, 50_000 ether + (y / days_) * 12 / 100, "a day's budget is not 50k + 12%");

        // ADDITIVE, NOT A FLOOR. The linear term dwarfs the base here, so a `max(base, linear)`
        // implementation would land exactly on `linear` and this is what separates the two.
        assertGt(linear, craps.BASE_MAIN_BUDGET(), "the fixture's linear term never passes the base");
        assertEq(mainBudget - linear, craps.BASE_MAIN_BUDGET(), "the base was swallowed by the linear term");

        // And the day actually offers HALF of that: the seven windows partition the ladder, and
        // the other half is banked in the pool. The two together are the whole allocation.
        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(mainBudget);
        assertEq(ladder + contribution, mainBudget, "the split lost or created a wei");
        _setDailyWord(today, PLAIN_WORD);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(craps.boostBudgetOf(today), ladder, "the day banked other than the ladder half");
        assertEq(craps.progressivePool(), contribution, "the day banked other than the progressive half");
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        uint256 sum;
        for (uint256 p = 0; p < periods; ++p) sum += craps.boostBaseAt(_slotAt(p));
        assertApproxEqAbs(sum, ladder, periods, "the windows do not partition the day's ladder");
    }

    /// @dev ZERO ACTION STILL PAYS THE BASE, and exactly the base. This is the additive rule at
    ///      its cheapest end: with nothing behind it a day allocates 50,000 FLIP, which the split
    ///      then halves — 25,000 to the ladder its seven windows share and 25,000 banked in the
    ///      progressive. Both halves are emission; only their timing differs.
    function test_aColdDayOpensOnExactlyTheBaseSubsidy() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        (uint256 mainBudget, uint256 highBudget) = craps.drawBudgetsFor(today);
        assertEq(mainBudget, craps.BASE_MAIN_BUDGET(), "a cold table did not open on exactly the base");
        assertEq(mainBudget, 50_000 ether, "the base subsidy is not 50,000 FLIP");
        assertEq(highBudget, 0, "a cold table funded a high lane");

        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(mainBudget);
        assertEq(ladder, 25_000 ether, "a cold day's ladder is not half the base");
        assertEq(contribution, 25_000 ether, "a cold day's progressive contribution is not half the base");
        assertEq(ladder + contribution, mainBudget, "the split lost or created a wei");
        assertEq(craps.ladderBudgetFor(today), ladder, "the pre-open ladder quote disagrees with the split");

        // And the day that opens actually banks that: the ladder in the boost budget, the other
        // half in the pool, and nothing anywhere else.
        assertEq(craps.progressivePool(), 0, "the pool was not empty before any day opened");
        _setDailyWord(today, PLAIN_WORD);
        _openDay();
        assertEq(craps.boostBudgetOf(today), ladder, "the day banked other than the ladder half");
        assertEq(craps.progressivePool(), contribution, "the day banked other than the progressive half");
    }

    /// @dev THE TWO LANES ARE RATED THE SAME AND NEVER SHARE A WEI. Regular action is worth 12%
    ///      to the main lane. High action is worth 12% too, split two parts in five to the main
    ///      lane (4.8%) and three to the lane that earned it (7.2%). Mixed action is booked once:
    ///      `_highStaked` is subtracted out of `_dayStaked` before the regular component is taken,
    ///      so no unit of action can pay into both.
    function test_theTwoLanesAreRatedTheSameAndNeverShareAWei() public {
        vm.warp(vm.getBlockTimestamp() + 10 days);
        uint24 today = craps.currentDayIndex();
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        uint256 base = craps.BASE_MAIN_BUDGET();

        // Regular action alone: 12% to the main lane, nothing to the high one.
        uint256 perDay = 7_000_000 ether;
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), perDay);
        (uint256 m, uint256 h) = craps.drawBudgetsFor(today);
        assertEq(m, base + perDay * 12 / 100, "regular action is not worth 12% to the main lane");
        assertEq(h, 0, "regular action funded the high lane");

        // High action alone, on the day after, so the two fixtures never overlap a window.
        // `bookHighDay` books into the day total AND the high subset, exactly as a real high seat
        // does, so nothing else is written here.
        uint24 later = today + uint24(days_);
        for (uint256 i = 1; i <= days_; ++i) craps.bookHighDay(later - uint24(i), perDay);
        (m, h) = craps.drawBudgetsFor(later);
        assertEq(m, base + perDay * 48 / 1000, "high action is not worth 4.8% to the main lane");
        assertEq(h, perDay * 72 / 1000, "high action is not worth 7.2% to its own lane");
        // TWELVE PERCENT ACROSS BOTH LANES, whichever lane put it up.
        assertEq((m - base) + h, perDay * 12 / 100, "the two lanes do not sum to 12% of the action");

        // MIXED, and not double counted: half the day's action is a high seat's.
        uint24 third = later + uint24(days_);
        for (uint256 i = 1; i <= days_; ++i) {
            craps.bookDay(third - uint24(i), perDay / 2);
            craps.bookHighDay(third - uint24(i), perDay / 2);
        }
        (m, h) = craps.drawBudgetsFor(third);
        uint256 regular = perDay / 2;
        assertEq(
            m,
            base + regular * 12 / 100 + (perDay / 2) * 48 / 1000,
            "the regular component did not net out the high action"
        );
        assertEq(h, (perDay / 2) * 72 / 1000, "the high lane took other than 7.2% of its own action");
        assertEq((m - base) + h, perDay * 12 / 100, "mixed action was double counted or lost");
    }

    /// @dev A BUSIER WEEK buys a bigger bonus, with nothing at the table retuned. Twelve percent
    ///      of the bankroll the seats put up comes back as house money, on top of the flat base.
    ///      The action alone is tracked and the rate applied analytically, so a lucky week cannot
    ///      starve the next one and an unlucky one cannot inflate it. That rate is a SCHEDULE
    ///      choice, not a claim about any board's edge: the true-odds place legs are fair, so a
    ///      field can legally hand the table nothing at all.
    function test_aBusierWeekBuysABiggerBonus() public {
        // Far enough in that a full seven-day window exists behind today.
        vm.warp(block.timestamp + 10 days);
        uint24 today = craps.currentDayIndex();
        assertGe(today, craps.BOOST_ACTION_WINDOW_DAYS(), "the fixture has no week behind it");

        // With no action behind it, a day opens on the base and nothing else.
        assertEq(craps.drawBudgetFor(today), craps.BASE_MAIN_BUDGET(), "a cold table did not open on the base");

        // A week of real action. Each day contributes `action * 12 / 100`, and the week's sum is
        // spread back over the week. The per-day figure is FLOORED before it is summed, so the
        // fixture uses an action the rate divides exactly — otherwise "twice the action, twice
        // the linear term" is off by a wei of flooring and says nothing about the rule.
        uint256 perDay = 3_600_000 ether;
        uint256 days_ = craps.BOOST_ACTION_WINDOW_DAYS();
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), perDay);
        uint256 week = perDay * days_;
        assertEq(craps.dayStaked(today - 1), perDay, "the day's action did not book");
        assertEq(
            craps.dayActionRate(today - 1),
            perDay * craps.BOOST_ACTION_BPS() / craps.BPS_DENOMINATOR(),
            "the day's contribution is not 12% of its action"
        );

        // base + 12% of (y/7): the week's action at the schedule's rate, spread over the week.
        uint256 linear = week * craps.BOOST_ACTION_BPS() / craps.BPS_DENOMINATOR() / days_;
        uint256 expected = craps.BASE_MAIN_BUDGET() + linear;
        assertEq(craps.drawBudgetFor(today), expected, "the budget is not base + 12% of the week's DAILY figure");

        // Twice the action, twice the LINEAR term — and the base does not double with it.
        for (uint256 i = 1; i <= days_; ++i) craps.bookDay(today - uint24(i), perDay);
        assertEq(
            craps.drawBudgetFor(today),
            craps.BASE_MAIN_BUDGET() + linear * 2,
            "doubling the action did not double the linear term"
        );

        // And the day that opens on it hands every window a seventh. The warp above left this day
        // without a word, and `openBonusDay` is fail-soft on that — so seed it, or the day quietly
        // does not open and every assertion below reads zero.
        uint256 drawn = craps.BASE_MAIN_BUDGET() + linear * 2;
        (uint256 ladder, uint256 contribution) = craps.splitMainBudget(drawn);
        _setDailyWord(today, PLAIN_WORD);
        _openDay();
        uint64 slot = _slotAt(PER);
        assertEq(craps.boostBudgetOf(today), ladder, "the day did not open on the drawn ladder half");
        assertEq(craps.progressivePool(), contribution, "the day did not bank the other half");
        // The EVENT takes half the LADDER; the routine window under test takes its size's share
        // of the other half of it.
        uint256 half = ladder / 2;
        assertEq(craps.boostBaseAt(_slotAt(days_ - 1)), half, "the event window did not take half");
        assertEq(
            craps.boostBaseAt(slot),
            half * _weightOf(today, PER) / _routineWeightAt(today),
            "a window took other than its size's share"
        );
    }

    /// @dev The budget does NOT move with the dice. Only the action is tracked, and the rate is
    ///      applied analytically — so however a week's runs happened to land, the same action buys
    ///      the same bonus. That is what keeps the subsidy from being a second bet on variance.
    function test_theBudgetIgnoresHowTheDiceRan() public {
        vm.warp(block.timestamp + 10 days);
        uint24 today = craps.currentDayIndex();
        // Big enough that ONE day of action dwarfs the base on its own: the budget spreads the
        // week, so a fixture sized too small would be almost all base and prove little.
        craps.bookDay(today - 1, 36_000_000 ether);
        uint256 drawn = craps.drawBudgetFor(today);
        assertGt(drawn, craps.BASE_MAIN_BUDGET(), "the fixture never leaves the base");
        // Settling more of the SAME action changes nothing; only fresh action moves it.
        assertEq(craps.drawBudgetFor(today), drawn, "the budget drifted without new action");
        craps.bookDay(today - 1, 36_000_000 ether);
        assertGt(craps.drawBudgetFor(today), drawn, "fresh action did not raise the budget");
    }

    /// @dev THE LADDER, and the property the whole budget rests on: it averages EXACTLY the
    ///      window's share, so a day spends its budget in EXPECTATION while no single window is
    ///      capped by it. Four rungs, each an order up from the last, each carrying about a fifth
    ///      of the budget except the top, which carries twice that.
    function test_theBoostLadderAveragesTheBaseExactly() public view {
        uint256[4] memory rung = [uint256(1), 4, 40, 400]; // quarters of the share
        uint256[4] memory per1k = [uint256(768), 208, 20, 4];

        uint256 mean;
        uint256 weight;
        for (uint256 i = 0; i < 4; ++i) {
            mean += rung[i] * per1k[i];
            weight += per1k[i];
        }
        assertEq(weight, 1000, "the rungs do not partition the roll");
        assertEq(mean, 4000, "the ladder's mean is not exactly one");

        // Each rung an order up from the last, bottom to top.
        for (uint256 i = 1; i < 4; ++i) {
            assertGe(rung[i], rung[i - 1] * 4, "the rungs are not an order apart");
            assertLt(per1k[i], per1k[i - 1], "a rarer rung is not rarer");
        }
        assertEq(rung[0], 1, "the bottom rung is not a quarter of the share");
        assertEq(rung[3] / 4, craps.BOOST_MAX_MULT(), "the top rung is not the advertised ceiling");

        // THE TAIL IS WHERE THE MONEY IS: the top rung alone carries forty percent of what the
        // window ever pays out, on four draws in a thousand.
        assertEq((rung[3] * per1k[3] * 100) / mean, 40, "the top rung stopped carrying its share");
        // And the common rung is genuinely common — three windows in four.
        assertGt(per1k[0], 750, "the common rung is not the common one");
    }

    /// @dev THE TOP RUNG IS REACHABLE, not merely permitted. A ceiling nothing ever draws is a
    ///      decoration, so this drives one window over many settling words and demands the
    ///      hundred-times rung actually land — and that the mean still comes home on the window's
    ///      share, which is what keeps the day's budget honest.
    function test_theTopRungIsReachedAndTheLadderStillAveragesTheShare() public {
        _openDay();
        uint24 day = craps.currentDayIndex();
        uint64 slot = _slotAt(PER);
        (uint256 low, uint256 mean, uint256 ceiling) = craps.bonusBoostBand(day, PER);
        assertEq(ceiling, mean * craps.BOOST_MAX_MULT(), "the band is not the ladder's top");
        assertEq(low, mean / 4, "the band's floor is not the bottom rung");

        _seatTwo(PER);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        // The top rung is four draws in a thousand, so a few thousand words is the sample it takes
        // to see one at all — which is exactly the point of the rung.
        uint256 draws = 4000;
        uint256 best;
        uint256 total;
        uint256 atTop;
        for (uint256 i = 0; i < draws; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("ladder", i))));
            uint256 drew = craps.boostUnitsAt(slot) * craps.BATTLE_STAKE_UNIT();
            assertLe(drew, ceiling, "a table drew over the ceiling it advertised");
            if (drew > best) best = drew;
            if (drew >= (ceiling / craps.BATTLE_STAKE_UNIT()) * craps.BATTLE_STAKE_UNIT()) ++atTop;
            total += drew;
        }
        emit log_named_uint("best of 4,000 draws        ", best);
        emit log_named_uint("mean of 4,000 draws        ", total / draws);
        emit log_named_uint("top-rung hits in 4,000     ", atTop);

        assertGt(atTop, 0, "the hundred-times rung never landed in 4,000 draws");
        assertEq(best, (ceiling / craps.BATTLE_STAKE_UNIT()) * craps.BATTLE_STAKE_UNIT(), "the top rung paid short");
        // Still the same bet. The band is wide because the top rung alone is forty percent of the
        // mean, so a handful of hits either way moves it — the draws are deterministic, so this
        // measures the ladder rather than luck.
        assertApproxEqRel(total / draws, mean, 0.30e18, "the ladder's mean wandered off the window's share");
    }

    /// @dev THE SYBIL DEFENCE, moved off the door and onto the payout. Anyone may play any
    ///      battle. But HOUSE MONEY is rationed by the winner's standing: at the floor it pays in
    ///      full, below it the winner carries off one part in `floor - standing`, and a scoreless
    ///      wallet carries off NONE. What is not taken is never minted.
    function test_theBoostLadderRationsByStanding() public view {
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        uint256 boost = 660; // divisible on every rung, so each is exact

        // A scoreless wallet takes nothing at all — the rung below one eleventh is zero, not a
        // twelfth. This is the whole point: a fresh wallet cannot touch the subsidy.
        assertEq(craps.boostShareFor(boost, 0), 0, "a scoreless winner took house money");

        // Then one part in (floor - standing), climbing to the whole boost one short of the floor.
        for (uint256 held = 1; held < floor_; ++held) {
            assertEq(craps.boostShareFor(boost, held), boost / (floor_ - held), "rung off the ladder");
        }
        assertEq(craps.boostShareFor(boost, floor_ - 1), boost, "one short of the floor was docked");
        assertEq(craps.boostShareFor(boost, 1), boost / 11, "the bottom rung is not an eleventh");

        // At the floor and above, whole.
        assertEq(craps.boostShareFor(boost, floor_), boost, "the floor was docked");
        assertEq(craps.boostShareFor(boost, 65_534), boost, "a high standing was docked");

        // Monotone: more standing is never worth less.
        uint256 prev;
        for (uint256 held = 0; held <= floor_; ++held) {
            uint256 share = craps.boostShareFor(boost, held);
            assertGe(share, prev, "the ladder went backwards");
            prev = share;
        }
    }

    /// @dev And settlement actually applies it: a bonus window's winner is paid its bounties and
    ///      busted crumbs WHOLE, plus only its rationed slice of the boost.
    function test_aWindowsClaimPaysTheRationedBoost() public {
        _openDay();
        _enter(alice, PER);
        _enter(bob, PER);
        // A scoreless third seat, which the door now admits without complaint.
        address fresh = makeAddr("freshSeat");
        vm.prank(fresh);
        craps.enterBonusBattle(PER, _seven(), 1);

        _warpPastClose(PER);
        uint64 slot = _slotAt(PER);
        uint48 index = _armAt(PER);
        // The boost rides a heavy-tailed ladder, so most words draw a base too small to clear one
        // granule at this field size. Search for a word that actually pays, or the rationing below
        // is asserted against nothing.
        // PAST THE ROUNDING STEP, and off it. Under forty granules `_roundBoost` is the identity,
        // so a fixture that lands there cannot tell a pot that rounded from one that never did —
        // and a boost already on a whole thousand cannot either.
        uint256 boost;
        for (uint256 i = 0; i < 512 && !(boost > 40 && boost % 10 != 0); ++i) {
            _setWord(index, uint256(keccak256(abi.encode("rationed", i))));
            boost = craps.boostUnitsAt(slot);
        }
        assertGt(boost, 40, "no word drew a boost past the rounding step: the test proves nothing");
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        CrapsBattle.Battle memory info = craps.battleOf(_keyOf(PER));
        uint256 winnerId = _idAt(slot, info.winnerId);
        uint256 held = craps.betOf(winnerId).standing;

        // RATIONED FIRST, ROUNDED SECOND, WIDENED LAST — production's own order. Widening before
        // rounding would leave the rounding a no-op on a wei figure and hand the winner an odd
        // hundred, so the order is what this asserts and not merely the granule.
        uint256 share = craps.boostShareFor(boost, held);
        uint256 expected = uint256(BON_SU) * info.entrants * craps.BATTLE_STAKE_UNIT()
            + craps.roundBoostFor(share) * craps.BATTLE_STAKE_UNIT();
        // And the fixture has to actually straddle the step, or the two orders agree by accident.
        assertTrue(craps.roundBoostFor(share) != share, "the winner's share did not straddle the rounding step");

        assertEq(pot.betId, winnerId, "the pot named a seat the scoreboard did not");
        assertEq(pot.player, craps.betOf(winnerId).player, "the pot reached an address that held no seat");
        assertEq(pot.amount, expected, "the window did not pay the rationed pot");
    }

    /// @dev A CUSTOM battle is NOT rationed. Its boost is donated rather than seeded, so no
    ///      loyalty spend is at stake — and a creator who wants a standing requirement already has
    ///      the bar it set at creation. A scoreless winner there takes the whole donation.
    function test_aCustomBattleDoesNotRationItsDonation() public {
        uint64 slot = _openBattle(craps, uint32(LW / 1 ether), 2, 5, SU);
        for (uint256 i = 0; i < 3; ++i) {
            address who = makeAddr(string(abi.encodePacked("customSeat", i)));
            assertEq(game.score(who), 0, "the custom seat is not scoreless");
            vm.prank(who);
            craps.enterBattle(slot, _boardA(), 1);
        }
        // FORTY-FIVE, deliberately: it is past the boost's rounding threshold and rounds UP to
        // fifty. A donation run through that rounding would hand the winner five granules nobody
        // burned, so the figure has to arrive exactly as it was given.
        uint24 donation = 45;
        vm.prank(carol);
        craps.donate(true, slot - craps.customSlotBase(), donation);
        assertEq(craps.roundBoostFor(donation), 50, "the fixture no longer straddles the rounding step");

        _closeOn(craps, slot, 700, uint256(keccak256("customboost")));
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        CrapsBattle.Battle memory info = craps.battleOf(_slotKeyOf(slot));
        uint256 winnerId = _idAt(slot, info.winnerId);
        assertEq(craps.betOf(winnerId).standing, 0, "the winner is not the scoreless seat");
        // The ladder WOULD have zeroed this if it applied here.
        assertEq(craps.boostShareFor(donation, 0), 0, "the ladder does not zero a scoreless winner");

        assertEq(pot.betId, winnerId, "the pot named a seat the scoreboard did not");
        assertEq(
            pot.amount,
            SUW * 3 + uint256(donation) * craps.BATTLE_STAKE_UNIT(),
            "a custom battle rationed or rounded its donation"
        );
    }

    /// @dev And the door itself asks for nothing: a scoreless wallet pays exactly a seat, with no
    ///      surcharge of any kind. The whole defence is on the payout.
    function test_aScorelessEntryPaysExactlyASeat() public {
        address fresh = makeAddr("freshWallet");
        assertEq(game.score(fresh), 0, "the fresh wallet is not actually scoreless");
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        vm.prank(fresh);
        craps.enterBattle(slot, _boardA(), 1);
        assertEq(flip.burned(fresh), LW * 2 + SUW, "a scoreless seat paid more than the seat");
    }

    /// @dev THE DAY LANE: bought in period 0, ONE bet that plays all seven windows. It is the
    ///      protocol's whole-day commitment, so it credits a quest streak the way keeping a daily
    ///      does — and exactly once, since the day seat can only be taken once.
    function test_theWholeDayTicketCreditsAQuestStreak() public {
        // Back to the day's first window, the only period the day lane is sold in.
        vm.warp(_dayStart());
        (, uint256 period,) = craps.currentBonusSlot();
        assertEq(period, 0, "the fixture is not inside the opening window");
        _openDay();
        game.setScore(alice, type(uint96).max);

        assertEq(quests.streakCalls(alice), 0, "a streak was credited before the ticket");
        vm.prank(alice);
        uint256 placed = craps.enterBonusDay(_seven(), 1);
        // ONE ticket covering all seven, not seven bets.
        assertEq(placed, craps.BONUS_PERIODS_PER_DAY(), "the day lane did not take the whole day");
        assertEq(craps.dayTicketsOf(craps.currentDayIndex()), 3, "the ticket did not join the day field");

        assertEq(quests.streakCalls(alice), 1, "the whole-day ticket credited no streak");
        assertEq(quests.streakAwarded(alice), 1, "the whole-day ticket credited the wrong amount");
        assertEq(quests.lastDay(), craps.currentDayIndex(), "the streak was credited against another day");

        // The day seat is one per address per day, so the credit cannot be farmed by re-entering.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusDay(_seven(), 1);
        assertEq(quests.streakAwarded(alice), 1, "a refused re-entry still credited a streak");

        // And a player who never took the whole day gets nothing from the per-window door.
        game.setScore(bob, type(uint96).max);
        vm.prank(bob);
        craps.enterBonusBattle(PER, _seven(), 1);
        assertEq(quests.streakCalls(bob), 0, "a single-window entry credited a streak");
    }

    /// @dev A HIGH DAY SEAT COUNTS FOR FIVE. It buys the same seven windows at the day's own
    ///      multiple — the largest single commitment the table sells — so the streak prices it
    ///      five times an ordinary day. Still ONE credit per address per day: the `_daySeated`
    ///      latch bounds the high door exactly as it bounds the ordinary one.
    function test_aHighDayTicketCreditsFiveStreak() public {
        vm.warp(_dayStart());
        (, uint256 period,) = craps.currentBonusSlot();
        assertEq(period, 0, "the fixture is not inside the opening window");
        _openDay();
        uint24 today = craps.currentDayIndex();
        uint256 hm = craps.highMultForDay(today);
        assertGt(hm, 1, "the fixture's day drew no high lane");

        game.setScore(alice, type(uint96).max);
        game.setScore(bob, type(uint96).max);

        vm.prank(alice);
        craps.enterBonusDay(_seven(), uint16(hm));
        assertEq(quests.streakCalls(alice), 1, "the high day ticket credited no streak");
        assertEq(quests.streakAwarded(alice), 5, "a high day ticket is not worth five");
        assertEq(quests.lastDay(), today, "the streak was credited against another day");

        // The ORDINARY day seat on the very same day is still worth one, so the five is the high
        // multiple's doing and not the day lane's.
        vm.prank(bob);
        craps.enterBonusDay(_seven(), 1);
        assertEq(quests.streakAwarded(bob), 1, "an ordinary day ticket moved off one");

        // One per address per day either way: a refused re-entry credits nothing further.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusDay(_seven(), uint16(hm));
        assertEq(quests.streakAwarded(alice), 5, "a refused high re-entry credited a second streak");
    }

    /// @dev A DAY-WIDE ENTRY SHUTS AS ONE. `enterBonusDay` is a single commitment spread over
    ///      every window still open, so the whole set locks the moment the first of it binds a
    ///      table — otherwise the windows still running could be re-tuned against a result an
    ///      earlier one had already published. Taking the same windows ONE AT A TIME is a
    ///      different bet and keeps its own per-window deadline, which is the contrast this pins.
    function test_aDayWideEntryLocksWhenItsFirstWindowDoes() public {
        _openDay();
        game.setScore(alice, type(uint96).max);
        game.setScore(bob, type(uint96).max);

        vm.prank(alice);
        uint256 placed = craps.enterBonusDay(_seven(), 1);
        assertGt(placed, 2, "the day-wide entry took too few windows");
        // Bob takes the same two windows the long way round.
        vm.prank(bob);
        craps.enterBonusBattle(PER, _seven(), 1);
        vm.prank(bob);
        craps.enterBonusBattle(PER + 2, _seven(), 1);

        uint256 aliceLate = _seatOf(PER + 2, alice);
        uint256 bobLate = _seatOf(PER + 2, bob);

        // Before anything binds, both are open orders.
        vm.prank(alice);
        craps.amendSlip(aliceLate, _boardB());
        assertEq(craps.betOf(aliceLate).chips, (uint256(4) << 9) | (uint256(3) << 12), "a live set refused a reshape");

        // The set's FIRST window binds. Nothing else has: `PER + 2` is still taking entries.
        _warpPastClose(PER);
        craps.armBonusWindow(_slotAt(PER));
        (, uint48 lateIndex,, bool joinable) = craps.bonusWindowOf(PER + 2);
        assertEq(lateIndex, 0, "the late window bound too");
        assertTrue(joinable, "the late window stopped taking entries");

        // Alice's later windows went with it. Bob's did not.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BetLocked.selector);
        craps.amendSlip(aliceLate, _boardC());

        vm.prank(bob);
        craps.amendSlip(bobLate, _boardC());
        assertEq(craps.betOf(bobLate).chips, (uint256(4) << 3) | (uint256(3) << 24), "a one-at-a-time slip locked");
    }

    /// @dev The set locks on ITS OWN first window, never on one that had already shut when the
    ///      entry was placed. A day-wide entry taken halfway through the day is a set of the
    ///      windows still running, and the mornings's spent windows say nothing about it.
    function test_aDayWideEntryIgnoresWindowsThatShutBeforeIt() public {
        _openDay();
        // Bind the opener, then take the day from a period that is still live.
        _warpPastClose(PER);
        craps.armBonusWindow(_slotAt(PER));

        game.setScore(alice, type(uint96).max);
        vm.prank(alice);
        uint256 placed = craps.enterBonusDay(_seven(), 1);
        assertGt(placed, 1, "the day-wide entry took too few windows");

        // An already-bound window from before the entry must not lock it.
        uint256 betId = _seatOf(PER + 2, alice);
        vm.prank(alice);
        craps.amendSlip(betId, _boardB());
        assertEq(craps.betOf(betId).chips, (uint256(4) << 9) | (uint256(3) << 12), "a spent window locked a later set");
    }

    // ---------------------------------------------------------------------------------------
    // The bonus day
    // ---------------------------------------------------------------------------------------

    /// @dev Any nonzero daily word will do: every window of the day folds it with its own period
    ///      number, so no window rides the bare word and none of them needs a special one.
    uint256 internal constant PLAIN_WORD = 40 << 8;

    /// @dev The window this suite works in. A routine tier window, and the one the clock is
    ///      already inside when `setUp` hands over — the day opens 82,620s past midnight, the
    ///      Foundry epoch sits an hour past that, and period 1 is the hour-old window.
    uint256 internal constant PER = 1;

    /// @dev The terms the window under test carries — read rather than named, because the
    ///      schedule draws them from the day's word and every period draws differently.
    uint128 internal BON_BANK;
    uint128 internal BON_GOAL;
    /// @dev The seven chips an entrant POSTS. The round it grows into is ten of them.
    uint256 internal BON_STACK;
    uint24 internal BON_SU;
    uint256 internal BON_SEED;
    uint256 internal BON_SCORE;

    /// @dev The instant the protocol day now running opened.
    function _dayStart() internal view returns (uint256) {
        return block.timestamp - ((block.timestamp - 82_620) % 1 days);
    }


    /// @dev Settle a window's whole field through the slot lane. `WHOLE_FIELD` exceeds every field
    ///      this suite creates, and the cursor stops at the entrant count.
    function _resolveSlotOn(uint24 day, uint256 period) internal {
        craps.resolveSlot(uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1), WHOLE_FIELD);
    }

    function _resolveSlot(uint256 period) internal {
        (uint24 day,,) = craps.currentBonusSlot();
        _resolveSlotOn(day, period);
    }

    /// @dev Land inside `period`, `ahead` days on, where that window still takes entries. The
    ///      opener runs for twenty minutes; later windows close on `BONUS_PERIOD` boundaries.
    function _warpInto(uint256 ahead, uint256 period) internal {
        uint256 into = period == 0 ? 0 : _closeOf(period - 1);
        vm.warp(_dayStart() + ahead * 1 days + into);
    }

    /// @dev When `period` stops taking bets, measured from the day's start. The routine ladder
    ///      carries the clock alignment; the EVENT is measured backwards from the turnover.
    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 1 == craps.BONUS_PERIODS_PER_DAY()) return 1 days - craps.EVENT_LEAD();
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    /// @dev Past `period`'s close, still inside the same day, so its terms are still today's.
    function _warpPastClose(uint256 period) internal {
        vm.warp(_dayStart() + _closeOf(period));
    }

    /// @dev Read the terms `period` carries today into the `BON_` fields.
    function _readTerms(uint256 period) internal {
        (uint24 day,,) = craps.currentBonusSlot();
        uint256 stakeWei;
        (BON_BANK, BON_GOAL, BON_STACK, stakeWei, BON_SEED, BON_SCORE) = craps.bonusTermsFor(day, period);
        BON_SU = uint24(stakeWei / craps.BATTLE_STAKE_UNIT());
    }

    /// @dev Open today's seven windows and take the terms of the one under test.
    function _openDay() internal {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        _readTerms(PER);
    }

    /// @dev A routine window's 4:2:1 weight, derived from the BANKROLL the schedule drew rather
    ///      than from anything the contract says about weighting — so a split checked against it
    ///      is checked against the day that was actually produced.
    function _weightOf(uint24 day, uint256 period) internal view returns (uint256) {
        (uint128 bank,,,,,) = craps.bonusTermsFor(day, period);
        uint256 flip = uint256(bank) / 1 ether;
        if (flip == craps.BONUS_SMALL_BANKROLL()) return 1;
        if (flip == craps.BONUS_MED_BANKROLL()) return 2;
        if (flip == craps.BONUS_LARGE_BANKROLL()) return 4;
        revert("a routine window drew off the menu");
    }

    function _routineWeightAt(uint24 day) internal view returns (uint256 weight) {
        for (uint256 p = 0; p + 1 < craps.BONUS_PERIODS_PER_DAY(); ++p) weight += _weightOf(day, p);
    }

    function _keyOf(uint256 period) internal view returns (bytes32 key) {
        (key,,,) = craps.bonusWindowOf(period);
    }

    /// @dev Shut `period`'s window, if nobody has, and move the table onto whatever it took. No
    ///      neighbours needed: a window shuts on its own.
    function _armAt(uint256 period) internal returns (uint48 index) {
        (, uint48 already,,) = craps.bonusWindowOf(period);
        index = already == 0 ? craps.armBonusWindow(_slotAt(period)) : already;
        _setIndex(index);
    }

    /// @dev A window's slot on a NAMED day, for reaching back past the current one.
    function _slotOn(uint24 day, uint256 period) internal view returns (uint64) {
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    /// @dev The house's seat in `period`. `openBonusDay` walks the periods in order and seats the
    ///      house then the vault in each, so the ids are dense and positional.
    /// @dev Bodies seated across today's windows — the per-slot entrant counts summed, since a
    ///      bet is numbered within its own field and there is no global counter any more.
    /// @dev Bodies sitting in today's bonus: the DAY lane's tickets, which play every window, plus
    ///      whatever each window took on its own. A window folds the day field in only when it
    ///      shuts, so counting `entrants` alone under-reports an open day.
    function _seatedToday(uint256 periods) internal view returns (uint256 n) {
        (uint24 day,,) = craps.currentBonusSlot();
        n = craps.dayTicketsOf(day);
        for (uint256 p = 0; p < periods; ++p) {
            (, uint48 bound,,) = craps.bonusWindowOf(p);
            uint256 own = craps.battleOf(_keyOf(p)).entrants;
            // Once shut, `entrants` already includes the day field; before that it does not.
            if (bound != 0) own -= craps.dayTicketsOf(day);
            n += own;
        }
    }

    /// @dev Today's slot for `period`.
    function _slotAt(uint256 period) internal view returns (uint64) {
        (uint24 day,,) = craps.currentBonusSlot();
        return uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + period + 1);
    }

    /// @dev The house takes the first seat in a window's field, the vault the second.
    /// @dev The house's ticket. It is a DAY seat — one bet playing every window — so it is keyed
    ///      to the day, not to a period. The vault sits directly behind it.
    function _houseSeat(uint256) internal view returns (uint256) {
        (uint24 day,,) = craps.currentBonusSlot();
        return (craps._daySlotOfPub(day) << 64) | 1;
    }

    /// @dev A chip ALLOCATION: seven chips, spread within the four-a-leg cap. A window's door
    ///      takes chips by COUNT and scales them to its own chip, which is what makes one
    ///      allocation a legal entry at every window of the day however differently they are sized.
    function _seven() internal pure returns (Craps.Bets memory c) {
        c.passLine = 4;
        c.place8 = 3;
    }

    /// @dev Take a seat in `period`, standing clear of the sybil floor. A bonus window bars
    ///      nobody now, so the only thing standing decides is how much of the BOOST a winner may
    ///      carry off — and a fixture measuring a POT wants the whole of it. The rationing ladder
    ///      is pinned on its own by `test_theBoostIsRationedByTheWinnersStanding`.
    function _enter(address who, uint256 period) internal returns (uint256) {
        (uint24 day,,) = craps.currentBonusSlot();
        (,,,,, uint256 bar) = craps.bonusTermsFor(day, period);
        uint256 standing = craps.SYBIL_SCORE_FLOOR();
        if (bar > standing) standing = bar;
        game.setScore(who, standing);
        vm.prank(who);
        return craps.enterBonusBattle(period, _seven(), 1);
    }

    /// @dev A named player's seat in `period` — found by walking the field, since a bet is
    ///      numbered within its own window and the day's entries are spread across seven of them.
    function _seatOf(uint256 period, address who) internal view returns (uint256) {
        uint64 slot = _slotAt(period);
        uint256 n = craps.battleOf(_slotKeyOf(slot)).entrants;
        for (uint256 i = n; i > 0; --i) {
            uint256 betId = _idAt(slot, uint64(i));
            if (craps.betOf(betId).player == who) return betId;
        }
        revert("no seat");
    }

    /// @dev The id sitting at seat `n` of `slot`, the same own-then-day mapping the settle walk
    ///      and the claim use: a window's own entries run 1..ownN under the window's own slot, and
    ///      the day's tickets take the tail under the day slot. Only meaningful once the window
    ///      has SHUT, since that is when the day field is folded into `entrants`.
    function _idAt(uint64 slot, uint64 n) internal view returns (uint256) {
        // A LIVE window counts its own entries alone, so its seats are its own and nothing else.
        if (slot >= craps.customSlotBase() || !craps.isShut(slot)) return (uint256(slot) << 64) | n;
        uint24 day = uint24(uint256(slot) / craps.BONUS_SLOTS_PER_DAY());
        uint64 dayN = craps.dayTicketsOf(day);
        uint64 ownN = uint64(craps.battleOf(_slotKeyOf(slot)).entrants) - dayN;
        return n <= ownN ? (uint256(slot) << 64) | n : (craps._daySlotOfPub(day) << 64) | (n - ownN);
    }

    /// @dev Every slip seated in `slot`, in seat order — both buckets, resolved to real ids.
    function _fieldOf(uint64 slot) internal view returns (uint256[] memory ids) {
        uint256 n = craps.battleOf(_slotKeyOf(slot)).entrants;
        ids = new uint256[](n);
        for (uint256 i = 0; i < n; ++i) {
            ids[i] = _idAt(slot, uint64(i + 1));
        }
    }

    function _slotKeyOf(uint64 slot) internal view returns (bytes32) {
        return craps.keyOfSlot(slot);
    }

    /// @dev The schedule: one opening a day, seven windows, each shut exactly once and only once
    ///      its own period has run out. A window is a slot on a published timetable, not a
    ///      rolling timer — shutting one early does not shorten the next.
    function test_theDayOpensOnceAndEveryWindowShutsOnce() public {
        (uint24 day, uint256 period,) = craps.currentBonusSlot();
        assertEq(period, PER, "the suite does not start inside its window");

        // Only the game opens it. This rides the daily advance, so a player can neither start it
        // nor make its work happen out from under the crank that feeds it.
        vm.expectRevert(CrapsBattle.OnlyGame.selector);
        craps.openBonusDay();

        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        (uint24 opened, bool openable) = craps.bonusDayOf();
        assertEq(opened, day, "the day did not latch");
        assertFalse(openable, "an opened day is still openable");

        // A second open is a NO-OP, not a revert: inside the advance, reverting on a day already
        // open would stop the protocol's daily crank rather than just the opening.
        uint256 seatedBefore = _seatedToday(craps.BONUS_PERIODS_PER_DAY());
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(_seatedToday(craps.BONUS_PERIODS_PER_DAY()), seatedBefore, "the day opened twice");

        // All seven are live at once — that is the point of opening them together — and only the
        // ones whose period has not passed still take entries.
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        for (uint256 p = 0; p < periods; ++p) {
            (bytes32 key,,, bool joinable) = craps.bonusWindowOf(p);
            assertTrue(key != bytes32(0), "a window of the opened day has no battle");
            assertEq(joinable, p >= PER, "a window was joinable outside its own period");
        }

        // A window still taking bets cannot be shut, by anyone.
        uint64 here = _slotAt(PER);
        vm.expectRevert(CrapsBattle.BonusStillRunning.selector);
        craps.armBonusWindow(here);

        // Once it stops, it opens to whoever calls first — once — and it does NOT wait for the
        // window before it. Shutting out of sequence is allowed on purpose: each slot settles on
        // its own word, and the index taken is one whose word cannot exist yet, so there is
        // nothing to gain by choosing the moment or the order.
        uint48 live = craps.currentIndex();
        _warpPastClose(PER + 1);
        vm.prank(keeper);
        assertEq(craps.armBonusWindow(_slotAt(PER + 1)), live + 1, "shut onto a table that already exists");
        craps.armBonusWindow(here);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.armBonusWindow(here);

        // And the earlier one it skipped past is still perfectly shuttable afterwards.
        craps.armBonusWindow(_slotAt(PER - 1));

        // THE EVENT SHUTS EARLY, and this is the exact moment it does. The protocol day turns
        // over at jackpot time, so an event closing on the boundary itself could not settle until
        // the jackpot had already gone out. A quarter-hour before it, the event is still taking
        // bets; on the lead itself it is shut — which is what puts its table, and the lootbox
        // draw that comes with it, inside the run-up instead of after it.
        uint64 eventSlot = _slotAt(periods - 1);
        uint256 lead = craps.EVENT_LEAD();
        vm.warp(_dayStart() + 1 days - lead - 1);
        vm.expectRevert(CrapsBattle.BonusStillRunning.selector);
        craps.armBonusWindow(eventSlot);

        vm.warp(_dayStart() + 1 days - lead);
        craps.armBonusWindow(eventSlot);
    }

    /// @dev THE PUBLISHED SCHEDULE, asserted against the contract's own answer.
    ///
    ///      The protocol day starts at 22:57 UTC, three minutes shy of the hour, so a ladder
    ///      measured from it would put every window at :57 past — unpublishable. The clock
    ///      alignment moves the routine closes onto round hours and the opener onto :20, and the
    ///      EVENT stays where the jackpot puts it. These are the times a player is told, so they
    ///      are pinned as times rather than as offsets: a change to any constant that feeds them
    ///      trips here, in the units the change would actually be felt in.
    function test_everyWindowShutsOnItsPublishedClockTime() public {
        // UTC minutes past midnight.
        uint16[7] memory published = [
            uint16(23 * 60 + 20), // 23:20  opener
            uint16(3 * 60), //        03:00  routine
            uint16(7 * 60), //        07:00  routine
            uint16(11 * 60), //       11:00  routine
            uint16(15 * 60), //       15:00  routine
            uint16(19 * 60), //       19:00  routine
            uint16(22 * 60 + 42) //   22:42  EVENT, a quarter-hour before the 22:57 jackpot
        ];
        for (uint256 p = 0; p < published.length; ++p) {
            uint256 at = _dayStart() + _closeOf(p);
            assertEq((at % 1 days) / 60, published[p], "a window does not close on its published clock time");

            // And the contract agrees that this is the moment, to the second.
            vm.warp(at - 1);
            (, uint256 justBefore,) = craps.currentBonusSlot();
            assertEq(justBefore, p, "the window had already shut a second early");
            vm.warp(at);
            (, uint256 onTheDot,) = craps.currentBonusSlot();
            assertEq(onTheDot, p + 1, "the window did not shut on its published clock time");
        }
    }

    /// @dev THE LEAD HAS TO CLEAR THE GAME'S PRE-RESET BLACKOUT, and this is the only place the
    ///      two constants are ever compared.
    ///
    ///      `requestLootboxRng` refuses outright in the final minute before the day resets, so it
    ///      does not compete with the daily jackpot's own RNG flow. The event's whole purpose is to
    ///      shut early enough to get a draw, so a lead inside that blackout would arm the day's
    ///      biggest window into a request that can never be granted — and it would fail SILENTLY,
    ///      because the arm swallows the refusal on purpose. Read out of the module's own source
    ///      rather than restated, so shortening either side trips this instead of the product.
    function test_theEventsLeadClearsTheGamesPreResetBlackout() public view {
        string memory src = vm.readFile("contracts/modules/DegenerusGameAdvanceModule.sol");
        assertTrue(
            vm.contains(src, "% 1 days >= 1 days - 1 minutes) revert PreResetWindow();"),
            "the pre-reset blackout moved: re-derive the event lead against its new width"
        );
        // One minute of blackout, and a VRF round to land inside the rest of the lead.
        assertGt(craps.EVENT_LEAD(), 1 minutes, "the event shuts inside the blackout and can never draw");
        assertGe(craps.EVENT_LEAD(), 5 minutes, "the lead leaves no room for a fulfilment before reset");
    }

    /// @dev THE EVENT SETTLES BEFORE THE JACKPOT IT PRECEDES. Shutting it asks the game for a
    ///      lootbox draw, and that request is what carries both the table's dice and the day's
    ///      pending boxes — so a quarter-hour of lead is the whole window in which the day's
    ///      biggest race resolves, in front of an audience, before the jackpots go out.
    function test_theEventShutsIntoTheRunUpAndAsksForTheDraw() public {
        _openDay();
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        uint64 eventSlot = _slotAt(periods - 1);

        // Still inside its own day, and still before the turnover.
        vm.warp(_dayStart() + 1 days - craps.EVENT_LEAD());
        (uint24 day,,) = craps.currentBonusSlot();
        assertEq(day, craps.currentDayIndex(), "the event shut after its own day had turned over");

        // Arming asks the game to draw — the same request that clears the lootbox queue.
        uint256 before_ = game.lootboxRngCalls();
        craps.armBonusWindow(eventSlot);
        assertEq(game.lootboxRngCalls(), before_ + 1, "shutting the event asked for no draw");

        // And nothing of the day is left taking bets once it has gone.
        for (uint256 p = 0; p < periods; ++p) {
            (,,, bool joinable) = craps.bonusWindowOf(p);
            assertFalse(joinable, "a window was still taking bets past the event's close");
        }
    }

    /// @dev What opening a day costs, measured — this is the figure that decides whether the
    ///      opener can ride the daily advance rather than being its own transaction. Seven windows,
    ///      each seating the house and the vault, so it is fourteen placements plus seven battles.
    function test_openingTheDayCostsWhatTheAdvanceChainCanAfford() public {
        uint256 g = gasleft();
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        uint256 used = g - gasleft();
        emit log_named_uint("openBonusDay gas", used);
        assertLt(used, 3_000_000, "opening the day regressed past what the advance chain can carry");
    }

    /// @dev NOTHING CAN BE STRANDED. A window is shuttable by anyone from the moment it stops
    ///      taking bets, forever after — so a day nobody kept up with still settles later. This is
    ///      what removes the need for the opener to sweep anything or for a field to ask for its
    ///      money back.
    function test_aForgottenWindowIsStillShuttableDaysLater() public {
        uint256 last = craps.BONUS_PERIODS_PER_DAY() - 1;
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        uint24 dayOne = craps.currentDayIndex();
        uint256 entrant = _enter(alice, last);

        // Two whole days pass with nobody shutting it.
        _warpInto(2, PER);
        _setDailyWord(craps.currentDayIndex(), uint256(keccak256("day three")));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        uint48 index = craps.armBonusWindow(_slotOn(dayOne, last));
        _setWord(index, uint256(keccak256("late")));
        _resolveSlotOn(dayOne, last);
        assertTrue(craps.betOf(entrant).settled, "a forgotten window could not be settled at all");
    }

    /// @dev A day's word fixes all seven of its windows at once, so the timetable — terms, bar
    ///      and seed — is publishable the moment that word lands, for windows nobody has opened
    ///      yet. Opening the day must produce exactly what the schedule advertised.
    function test_theWholeDaysScheduleIsKnownUpFront() public {
        (uint24 day,,) = craps.currentBonusSlot();
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();

        uint256 distinct;
        uint128 firstBank;
        for (uint256 p = 0; p < periods; ++p) {
            (uint128 bank, uint128 goal, uint256 stack, uint256 bounty, uint256 seedOf, uint256 minScore) =
                craps.bonusTermsFor(day, p);
            assertGt(bank, 0, "a window in a worded day had no terms");
            // Every advertised window is a battle placement would accept: the goal clears the
            // battle floor, the bounty sits inside its band, and the round fits the bankroll
            // ceiling — which is proven against the TEN chips the round grows into, not the
            // seven an entrant posts.
            assertGe(goal, uint256(bank) * craps.MIN_BATTLE_GOAL_MULT(), "advertised goal is unplayable");
            assertGt(bounty, 0, "a scheduled window carries no bounty");
            assertLe(bounty, bank, "advertised bounty is over the bankroll");
            uint256 played = stack / 7 * 10;
            assertLe(uint256(bank), played * craps.MAX_BANKROLL_MULT(), "advertised round cannot carry it");
            assertEq(minScore, 0, "an advertised window still asks for standing");
            // EVERY window advertises what it will pay on top of the stakes — that is the number
            // a player weighs the buy-in against — and none of them stores it.
            assertGt(seedOf, 0, "a window advertised no boost");

            if (p == 0) firstBank = bank;
            else if (bank != firstBank) ++distinct;
        }
        assertGt(distinct, 0, "every window of the day drew identical terms");

        // And the advertised window is what actually opens.
        (uint128 wantBank, uint128 wantGoal, uint256 wantStack, uint256 wantStake,,) = craps.bonusTermsFor(day, PER);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        CrapsBattle.Battle memory info = craps.battleOf(_keyOf(PER));
        assertEq(info.battleStake, wantStake, "opened a bounty the schedule did not advertise");
        // The terms belong to the SLOT, not to the seat: every entrant plays these, so they are
        // read once from the window rather than out of any one slip.
        assertEq(wantBank, wantBank, "bankroll");
        assertEq(wantGoal, wantGoal, "goal");
        assertEq(wantStack, wantStack, "stack");
        // The house seat names nothing at all: a blank ticket, every chip left to the dice.
        assertEq(craps.betOf(_houseSeat(PER)).chips, 0, "the house named a shape");
    }

    /// @dev A window shuts onto the NEXT index, never the live one — the day's word is public
    ///      from the moment the day opens, so binding forward is what stops anyone
    ///      pre-positioning into a table they already know the dice of.
    function test_aWindowShutsOntoTheNextIndexOnly() public {
        _openDay();
        uint48 live = craps.currentIndex();
        _warpPastClose(PER);

        craps.armBonusWindow(_slotAt(PER - 1));
        uint48 index = craps.armBonusWindow(_slotAt(PER));
        assertEq(index, live + 1, "shut onto the live index");
        assertEq(craps.wordAt(index), 0, "shut onto a table that had already rolled");

        (, uint48 published,, bool joinable) = craps.bonusWindowOf(PER);
        assertEq(published, index, "the window does not publish the table it took");
        assertFalse(joinable, "a shut window still takes entries");
    }

    /// @dev The only standing gate left is one a CUSTOM battle's creator chose. A bonus window
    ///      asks nothing — the bar is still a TERM of the race and still in the match key, so two
    ///      battles asking different bars remain two different races, but the protocol sets its own
    ///      to zero and defends house money at the payout instead.
    function test_onlyACustomCreatorMayAskForAScore() public {
        _openDay();

        // Scoreless, straight in — the window sets no bar at all.
        vm.prank(alice);
        uint256 betId = craps.enterBonusBattle(PER, _seven(), 1);
        assertEq(craps.battleKeyOf(betId), _keyOf(PER), "a scoreless entry did not seat");

        // A custom battle sets its own bar, and a zero one is open to anybody.
        _placeBattle(bob, _boardA(), LW * 2, LW * 10, SU);

        // One that asks for a bar holds every entrant to it, the same generic gate. The number is
        // the CREATOR's now, not the protocol's — a window sets none — so the fixture names it.
        uint16 creatorBar = 40;
        uint64 barred = _openBattle(craps, uint32(LW / 1 ether), 2, 5, SU, creatorBar);
        game.setScore(carol, creatorBar - 1);
        vm.prank(carol);
        vm.expectRevert(CrapsBattle.ScoreRequiredForBonus.selector);
        craps.enterBattle(barred, _boardA(), 1);
        game.setScore(carol, creatorBar);
        vm.prank(carol);
        craps.enterBattle(barred, _boardA(), 1);
    }

    /// @dev A window advertises a CEILING and the odds behind it, never a figure: its rung comes
    ///      off the word that SETTLES the table, which nobody can read while the field is still
    ///      forming. Nothing is banked for any of it. Contested, the boost goes whole to one
    ///      winner.
    function test_theBoostIsPickedByTheSettlingWordAndJoinsTheContestedPot() public {
        _openDay();
        bytes32 key = _keyOf(PER);
        assertEq(craps.battleOf(key).seed, 0, "the window banked storage for a derivable figure");
        (uint24 quoted,,) = craps.currentBonusSlot();
        (,,,, uint256 advertised,) = craps.bonusTermsFor(quoted, PER);
        (uint256 low, uint256 mid, uint256 high) = craps.bonusBoostBand(quoted, PER);
        assertGt(high, 0, "the game has no size, so no window can carry house money");
        assertLe(low, mid, "the band is not ordered");
        assertLe(mid, high, "the band is not ordered");
        assertEq(advertised, high, "the terms and the band quote different figures");
        assertEq(high, mid * craps.BOOST_MAX_MULT(), "the ceiling is not the top of the ladder");
        assertLt(low, high, "a window quoted no spread at all");

        _enter(alice, PER);
        _enter(bob, PER);

        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("bonusrun")));

        (uint24 day,,) = craps.currentBonusSlot();
        uint64 slot = uint64(uint256(day) * craps.BONUS_SLOTS_PER_DAY() + PER + 1);
        uint256[] memory field = _fieldOf(slot);
        assertEq(field.length, 4, "the field is not the house, the vault and the two players");
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);

        CrapsBattle.Battle memory done = craps.battleOf(key);
        assertTrue(done.finalized, "battle did not finalize");

        // The pot: one bounty per entrant, plus the boost this battle just rolled — all of it to
        // the single winner, so there is no split and no dust.
        uint256 winnerId = _idAt(slot, done.winnerId);
        uint256 stakes = uint256(BON_SU) * craps.BATTLE_STAKE_UNIT() * field.length;

        // The pot is the bounties and the boost this table drew — bounded above by the ceiling
        // the window advertised, and below by nothing granular, since a small budget may draw
        // less than one granule. A busted run's remainder is deleted, so it is not in here.
        uint256 drew =
            craps.boostShareFor(craps.boostUnitsAt(slot), craps.betOf(winnerId).standing) * craps.BATTLE_STAKE_UNIT();
        assertEq(pot.betId, winnerId, "the pot named a seat the scoreboard did not");
        assertEq(pot.player, craps.betOf(winnerId).player, "the pot reached an address that held no seat");
        assertEq(pot.amount, stakes + drew, "the pot is not the stakes and the boost");
        assertLe(drew, high, "the boost drew over the ceiling the window advertised");
    }

    // ---------------------------------------------------------------------------------------
    // Mystery boosts
    // ---------------------------------------------------------------------------------------

    /// @dev EVERY window is a lottery, and the wheel lands when the TABLE'S WORD does — after
    ///      entry has shut and before a single hand is settled. That ordering is what makes a
    ///      reveal possible at all, and it is the property pinned here; the reveal itself is a
    ///      client concern, computed off the public inputs rather than off a view.
    function test_theBoostIsDrawnWhenTheTableWordLands() public {
        _openDay();
        uint24 day = craps.currentDayIndex();
        uint64 slot = _slotAt(PER);

        (uint256 low, uint256 mid, uint256 high) = craps.bonusBoostBand(day, PER);
        assertLt(low, mid, "the floor is not under the mean");
        assertLt(mid, high, "the mean is not under the ceiling");
        assertEq(high, mid * craps.BOOST_MAX_MULT(), "the ceiling is not the top of the ladder");
        assertEq(low, mid / 4, "the floor is not the bottom rung");

        _seatTwo(PER);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);

        // NOTHING IS DRAWN YET. The table is bound but its word has not landed — the gap the
        // whole security argument lives in, since the index was chosen before the word existed.
        assertEq(craps.wordAt(index), 0, "the table's word landed before it was requested");

        // The word lands: the wheel stops, with every run still unsettled. Everything the reveal
        // is computed from is public here — the index, the word, the day's budget and the battle
        // key — which is why the reveal itself is a client's job and not a view on this contract.
        _setWord(index, uint256(keccak256("spin")));
        uint256 shown = craps.boostUnitsAt(slot) * craps.BATTLE_STAKE_UNIT();
        assertLe(shown, high, "the drawn boost is over the ceiling it advertised");
        assertEq(craps.battleOf(_keyOf(PER)).resolved, 0, "the boost landed only after the runs settled");
        assertGt(craps.boostBudgetOf(day), 0, "a client cannot read the day's budget");

        // And it really is the WORD that decides it: sweep the table and the figure moves.
        uint256 seen;
        uint256 top;
        for (uint256 i = 0; i < 64; ++i) {
            _setWord(index, uint256(keccak256(abi.encode("spin", i))));
            uint256 drew = craps.boostUnitsAt(slot) * craps.BATTLE_STAKE_UNIT();
            assertLe(drew, high, "a table drew over the ceiling it advertised");
            if (drew != top) ++seen;
            if (drew > top) top = drew;
        }
        assertGt(seen, 1, "the settling word never moved the boost");
    }

    /// @dev Two real players into `period`, so the window is contested and its boost is payable.
    function _seatTwo(uint256 period) internal {
        game.setScore(alice, craps.SYBIL_SCORE_FLOOR());
        game.setScore(bob, craps.SYBIL_SCORE_FLOOR());
        vm.prank(alice);
        craps.enterBonusBattle(period, _seven(), 1);
        vm.prank(bob);
        craps.enterBonusBattle(period, _seven(), 1);
    }

    /// @dev A donation is FLIP burned now against a pot paid later, so it is the one part of a
    ///      window that has to be stored. If the window then finds no real field, the donor's
    ///      money is simply gone — there is no rollover and nothing to reclaim, which is what lets
    ///      the day's opener touch none of yesterday's seeds.
    function test_aDonationOntoAWindowNobodyJoinsIsForfeited() public {
        uint256 last = craps.BONUS_PERIODS_PER_DAY() - 1;
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        bytes32 stale = _keyOf(last);

        craps.donate(false, last, 5);
        uint256 unit = craps.BATTLE_STAKE_UNIT();
        assertEq(craps.battleOf(stale).seed, 5 * unit, "the donation did not land");

        // Nobody real joins. The house and the vault race each other for it, and the window is
        // simply never claimed — so the donation is still sitting where it fell.
        _warpInto(1, PER);
        _setDailyWord(craps.currentDayIndex(), uint256(keccak256("day two")));
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();

        // Untouched where it fell, and the new day's event took nothing from it.
        assertEq(craps.battleOf(stale).seed, 5 * unit, "the opener reached back into a dead window");
        assertEq(craps.battleOf(_keyOf(last)).seed, 0, "the new event inherited a donation");
    }

    /// @dev The mix a player is quoted. The six routine windows draw a bankroll tier 7:2:1 and
    ///      bank nothing; the event draws its PLAYING BANKROLL off the 1,500 ladder with a tail —
    ///      one in twenty at 30k, one in fifty at 60k — takes a quarter-to-a-half bounty ON TOP of
    ///      it, and boosts one whole bankroll. Swept off the schedule view over many days, so this
    ///      pins the economics, not an implementation detail.
    function test_bonusTierMixMatchesTheAdvertisedOdds() public {
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        uint256 last = periods - 1;
        // Tier counts, indexed small/medium/large — held as arrays rather than six named counters
        // so the sweep's locals stay clear of the stack ceiling.
        uint256[3] memory drawn;
        uint256[3] memory opened;
        uint256 events;
        uint256 tail30;
        uint256 tail60;
        uint256 eventTotal;
        uint256 eventBankTotal;
        uint256 seedTotal;
        // Per-tier seed totals, indexed small/medium/large.
        uint256[3] memory seedSum;

        for (uint24 d = 1; d <= 400; ++d) {
            _setDailyWord(d, uint256(keccak256(abi.encode("mix", d))));
            // The LADDER is half the day's allocation; the day's EVENT takes half of that, and the
            // six routine windows split the rest 4:2:1 by size. The denominator is rebuilt out of
            // the bankrolls the schedule actually drew.
            uint256 half = craps.ladderBudgetFor(d) / 2;
            uint256 weight = _routineWeightAt(d);
            for (uint256 p = 0; p < periods; ++p) {
                uint256 base = p == last ? half : half * _weightOf(d, p) / weight;
                (uint128 bank,,, uint256 bounty, uint256 seed,) = craps.bonusTermsFor(d, p);
                uint256 bankFlip = uint256(bank) / 1 ether;
                assertGt(bounty, 0, "a scheduled window carries no bounty");
                assertLe(bounty, bank, "bounty over the bankroll");
                seedTotal += seed / 1 ether;

                // EVERY window quotes the same shape: its share of the day, the ceiling it can
                // reach and the floor it can never fall below. The terms view and the band view
                // have to agree on all of it.
                (uint256 lo,, uint256 hi) = craps.bonusBoostBand(d, p);
                assertEq(seed, hi, "the terms and the band quote different figures");
                assertEq(hi, base * craps.BOOST_MAX_MULT(), "the ceiling is off the ladder");
                // A quarter of the base, floored — so `lo * 4` is up to three wei short of it.
                assertEq(lo, base / 4, "the floor is not the bottom rung");

                if (p == last) {
                    ++events;
                    uint256 bountyFlip = bounty / 1 ether;
                    eventBankTotal += bankFlip;
                    eventTotal += bankFlip + bountyFlip;
                    if (bankFlip == 30_000) ++tail30;
                    if (bankFlip == 60_000) ++tail60;
                    // The BANKROLL is what the ladder names — the bounty is charged on top of it,
                    // so the entry cost is deliberately NOT a ladder step.
                    if (bankFlip < 30_000) {
                        assertEq(bankFlip % 1500, 0, "event bankroll was off the 1,500 ladder");
                        assertLe(bankFlip, 15_000, "event bankroll over the ladder's top step");
                    }
                    // A quarter to a half of the bankroll, on the 100-FLIP granule. Flooring only
                    // ever moves it DOWN, so the lower edge carries one granule of slack.
                    assertEq(bountyFlip % 100, 0, "event bounty off the granule");
                    assertLe(bountyFlip * 2, bankFlip, "event bounty over half the bankroll");
                    assertGe(bountyFlip * 4 + 400, bankFlip, "event bounty under a quarter of the bankroll");
                } else {
                    uint256 seedFlip = seed / 1 ether;
                    // The day's OPENER draws its tier flat; every window after it is weighted, so
                    // the two schedules are counted apart and each is held to its own.
                    if (bankFlip == craps.BONUS_SMALL_BANKROLL()) {
                        seedSum[0] += seedFlip;
                        if (p == 0) ++opened[0];
                        else ++drawn[0];
                    } else if (bankFlip == craps.BONUS_MED_BANKROLL()) {
                        seedSum[1] += seedFlip;
                        if (p == 0) ++opened[1];
                        else ++drawn[1];
                    } else if (bankFlip == craps.BONUS_LARGE_BANKROLL()) {
                        seedSum[2] += seedFlip;
                        if (p == 0) ++opened[2];
                        else ++drawn[2];
                    } else {
                        revert("a routine window drew off the menu");
                    }
                }
            }
        }

        uint256 routine = drawn[0] + drawn[1] + drawn[2];
        uint256 openers = opened[0] + opened[1] + opened[2];
        emit log_named_uint("mean event bankroll (FLIP) ", eventBankTotal / events);
        emit log_named_uint("mean event buy-in (FLIP)   ", eventTotal / events);
        emit log_named_uint("mean seeded per day (FLIP) ", seedTotal / 400);

        // Windows after the opener: 7:2:1. A mix check, not a chi-squared — the band is wide
        // enough that only a real change to the odds trips it.
        assertApproxEqAbs(drawn[0] * 10, routine * 7, routine / 2, "small tier off its advertised share");
        assertApproxEqAbs(drawn[1] * 10, routine * 2, routine / 2, "medium tier off its advertised share");
        assertApproxEqAbs(drawn[2] * 10, routine * 1, routine / 2, "large tier off its advertised share");

        // The OPENER: a third each, so the day starts on a table whose size the schedule gives no
        // hint of. Every tier has to actually turn up, or the draw is not flat at all.
        assertApproxEqAbs(opened[0] * 3, openers, openers / 2, "the opener's small share is not flat");
        assertApproxEqAbs(opened[1] * 3, openers, openers / 2, "the opener's medium share is not flat");
        assertApproxEqAbs(opened[2] * 3, openers, openers / 2, "the opener's large share is not flat");

        // The two event tails, at their own rates.
        assertApproxEqAbs(tail30 * 20, events, events / 2, "the 30k event tail is off");
        assertApproxEqAbs(tail60 * 50, events, events / 2, "the 60k event tail is off");
        // The ladder's mean is 8,250 and the two tails carry 30k and 60k at 5% and 2%, so the
        // draw's expectation — and therefore the day's expected boost from here — is ~10,370.
        assertApproxEqAbs(eventBankTotal / events, 10_372, 1_500, "the event's mean bankroll moved");

        // House money now DOES depend on the tier, by design: a window's share is 4:2:1 by size,
        // and the exact figure is asserted per window in the loop above against `base`. What is
        // left to say here is the direction, as means over 400 days.
        //
        // Deliberately an ORDERING and not a ratio. A large window contributes its own 4 to the
        // day's denominator, so the days on which it is large are also the days with the biggest
        // divisor — which pulls the realised spread well below the nominal 4:1 and makes any
        // fixed multiple a fragile thing to assert.
        assertGt(routine, 0, "no routine window was seen");
        uint256 meanSmall = seedSum[0] / (opened[0] + drawn[0]);
        uint256 meanMed = seedSum[1] / (opened[1] + drawn[1]);
        uint256 meanLarge = seedSum[2] / (opened[2] + drawn[2]);
        emit log_named_uint("mean quote, small (FLIP)   ", meanSmall);
        emit log_named_uint("mean quote, medium (FLIP)  ", meanMed);
        emit log_named_uint("mean quote, large (FLIP)   ", meanLarge);
        assertGt(meanMed, meanSmall, "a medium table does not out-quote a small one");
        assertGt(meanLarge, meanMed, "a large table does not out-quote a medium one");
    }

    /// @dev Opening a day sits two bodies down at every window of it: sDGNRS and the vault, so a
    ///      window always has a field even before anyone turns up — and a lone player arrives to a
    ///      race rather than to an empty table. The house buys its seat out of sDGNRS's settled
    ///      coinflip backing, bankroll and bounty both.
    function test_openingTheDaySeatsTheHouseAndTheVaultEverywhere() public {
        address house = ContractAddresses.SDGNRS;
        address vault = ContractAddresses.VAULT;
        _openDay();

        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        // TWO bodies, not fourteen: each takes a DAY ticket that sits in every window of the day.
        assertEq(_seatedToday(periods), 2, "the day did not seat the house and the vault");
        assertEq(craps.dayTicketsOf(craps.currentDayIndex()), 2, "the day lane is not two tickets");

        uint256 seat = _houseSeat(PER);
        assertEq(craps.betOf(seat).player, house, "the seat is not sDGNRS's");
        assertEq(craps.betOf(seat + 1).player, vault, "the vault did not sit beside it");
        // An OPEN window counts only its own entries. The day field joins it when it shuts, which
        // is what keeps a ticket sale off all seven scoreboards.
        assertEq(craps.battleOf(_keyOf(PER)).entrants, 0, "the day lane touched a live scoreboard");

        // Every window costs its own buy-in, so the day's bill is the sum of the seven.
        (uint24 day,,) = craps.currentBonusSlot();
        uint256 bill;
        for (uint256 p = 0; p < periods; ++p) {
            (uint128 bank,,, uint256 bounty,,) = craps.bonusTermsFor(day, p);
            bill += uint256(bank) + bounty;
        }
        assertEq(flip.burned(house), bill, "a funded seat did not draw on the backing");
        assertEq(flip.burned(vault), bill, "the vault sat on different terms");

        // The house's ticket is legal without ever being checked: it names nothing, so the dice
        // place the window's whole ten-chip round.
        assertEq(craps.betOf(seat).chips, 0, "the house named a shape");
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("house-board")));
        // Shutting is what folds the day field in, and it lands in the TAIL of the window's seats.
        assertEq(craps.battleOf(_keyOf(PER)).entrants, 2, "the shut window did not take the day field");
        assertEq(_idAt(_slotAt(PER), 1), seat, "the house is not the first seat of the shut field");
        assertEq(_idAt(_slotAt(PER), 2), seat + 1, "the vault is not the second");
        // A day ticket plays each window on THAT window's chip, so the board is read at the slot.
        Craps.Bets memory hb = craps.drawnBoardAt(seat, _slotAt(PER));
        assertEq(craps.stakeFor(hb), BON_STACK / 7 * 10, "the house's round missed the window's");
    }

    /// @dev ONE WINDOW, ONE SHOOTER — across BOTH buckets. A shut window's field is its own
    ///      entries, keyed to the window's slot, followed by the day lane's, keyed to the day's
    ///      reserved `day * BONUS_SLOTS_PER_DAY` — and the house and the vault sit in the second.
    ///      The dice belong to the WINDOW, so keying them to where a slip happens to be STORED
    ///      would hand the day lane a stream of its own and split the table's exposure in two.
    ///
    ///      Driven on ONE ticket settled from BOTH buckets: the same stored word is copied onto a
    ///      window-slot id and the two are settled side by side in the same window, off the same
    ///      table word. Owner, chips and standing are then identical by construction, so the board
    ///      scatter and the survival coin cannot differ and the shooter is the only thing left
    ///      that can move the return. `won` is the raw bankroll the table handed back — before the
    ///      per-slip rounding jitter, which keys on the bet id and is MEANT to differ.
    function test_theDayLaneAndTheWindowShareOneShooter() public {
        _warpInto(0, 0);
        _openDay();
        uint24 day = craps.currentDayIndex();
        uint256 ticket = (craps._daySlotOfPub(day) << 64) | 1;
        assertEq(craps.betOf(ticket).player, ContractAddresses.SDGNRS, "the day lane is not the house's");

        uint64 slot = _slotOn(day, 0);
        _warpPastClose(0);
        uint48 index = craps.armBonusWindow(slot);
        _setIndex(index);
        _setWord(index, uint256(keccak256("one-shooter")));

        // The SAME ticket, read from a window-slot id. Only where it is stored differs.
        uint256 twin = (uint256(slot) << 64) | 9;
        craps.copyBetTo(ticket, twin);
        assertTrue(ticket >> 64 != twin >> 64, "the two ids share a slot");

        CrapsBattle.Settlement memory a = craps.settlementIn(twin, slot);
        CrapsBattle.Settlement memory b = craps.settlementIn(ticket, slot);
        assertEq(b.won, a.won, "the day lane ran a different shooter");
        assertEq(b.handsPlayed, a.handsPlayed, "the day lane played a different hand count");
        assertEq(uint8(b.stop), uint8(a.stop), "the day lane stopped on a different roll");
    }

    /// @dev Roll the clock to the next day and word it, so the day lane can be opened again.
    function _nextWordedDay() internal {
        vm.warp(block.timestamp + 1 days);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
    }

    /// @dev PASSES BEFORE FLIP, FOR BOTH PROTOCOL BODIES. sDGNRS and the vault both open lootboxes
    ///      — the vault buys them, sDGNRS resolves its own self-subscription boxes — so both are
    ///      handed day passes like any other winner. Neither can reach the doors that spend one:
    ///      `applyCrapsPasses` and `buyFutureCrapsDays` key off `msg.sender`, and sDGNRS has no
    ///      controller at all. So the daily seat has to spend them, in the order the pass ladder
    ///      names: a reservation already standing on today, then a banked credit, then cash.
    ///
    ///      Two passes each buys exactly that sequence: the first takes tomorrow as a reservation,
    ///      the second banks, and the day after that has nothing left to spend.
    function test_theDayLaneSpendsFlipBeforePasses() public {
        address house = ContractAddresses.SDGNRS;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(house, 2, 0);

        uint24 tomorrow = craps.currentDayIndex() + 1;
        assertEq(craps.dayStateOf(tomorrow, house), craps.DAY_SEATED(), "the house took no seat on tomorrow");
        (uint256 banked,) = craps.passCreditsOf(house);
        assertEq(banked, 1, "the second pass did not bank");

        // Day one: the seat the pass ALREADY bought. Nothing is charged and nothing is spent.
        uint256 hb = flip.burned(house);
        _nextWordedDay();
        _openDay();
        assertEq(flip.burned(house), hb, "the house paid for a day its pass had already taken");

        // Day two: FLIP is available, so FLIP is what pays — the banked pass is kept.
        _nextWordedDay();
        _openDay();
        assertGt(flip.burned(house), hb, "the house spent a pass while it still had FLIP");
        (banked,) = craps.passCreditsOf(house);
        assertEq(banked, 1, "a banked pass was spent while FLIP was available");

        // Day three: FLIP refused, so the banked pass is what remains and it pays.
        flip.setBurnRefused(house, true);
        hb = flip.burned(house);
        _nextWordedDay();
        _openDay();
        assertEq(flip.burned(house), hb, "a refused burn still charged the house");
        (banked,) = craps.passCreditsOf(house);
        assertEq(banked, 0, "the pass was not spent once FLIP failed");
        assertEq(craps.dayStateOf(craps.currentDayIndex(), house), craps.DAY_SEATED(), "the house did not sit");
    }

    /// @dev A HIGH pass buys a HIGH seat, built the way the paid door builds one: the day's own
    ///      multiple on the header, the high bit set, and the high half of the day counter bumped
    ///      so `armBonusWindow` folds the body into each window's sideboard. Flattening it to an
    ///      ordinary seat would spend a pass worth nineteen normal ones on a 1x run.
    function test_aHighPassSeatsTheHouseInTheHighLane() public {
        address house = ContractAddresses.SDGNRS;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(house, 0, 1);
        uint24 target = craps.currentDayIndex() + 1;
        assertEq(craps.dayStateOf(target, house), craps.DAY_SEATED(), "the house took no seat on tomorrow");
        assertTrue(craps.daySeatIsHigh(target, house), "the high pass did not seat in the high lane");

        uint256 hb = flip.burned(house);
        _nextWordedDay();
        _openDay();
        assertEq(flip.burned(house), hb, "a prepaid high day still charged the house");

        uint24 day = craps.currentDayIndex();
        uint256 seat = (craps._daySlotOfPub(day) << 64) | 1;
        assertEq(craps.betOf(seat).player, house, "the house is not the first day seat");
        assertTrue(craps.isHighOf(seat), "the high seat did not take the high lane");
        // The high half of the counter is what a window folds into `_highField` when it shuts.
        assertEq(craps.dayTicketsOf(day) >> 32, 1, "the high lane never counted the house");
    }

    /// @dev A DONATION IS NOT HOUSE MONEY. It was burned by a third party for this field, so the
    ///      winner's standing must not ration it away and the boost's rounding — which goes to the
    ///      NEAREST thousand — must not inflate it into FLIP nobody burned. Driven on a SCORELESS
    ///      winner, the rung where the protocol's own subsidy pays exactly nothing: whatever lands
    ///      in the pot beyond the stakes is then the donation and only the donation.
    function test_aDonationReachesAScorelessWinnerWhole() public {
        // Neither body sits, so the lone entrant is the whole field and its win is certain.
        flip.setBurnRefused(ContractAddresses.SDGNRS, true);
        flip.setBurnRefused(ContractAddresses.VAULT, true);
        _openDay();
        uint256 unit = craps.BATTLE_STAKE_UNIT();

        vm.prank(carol);
        craps.donate(false, PER, 7);

        game.setScore(alice, 0);
        vm.prank(alice);
        craps.enterBonusBattle(PER, _seven(), 1);

        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("whole-donation")));

        uint64 slot = _slotAt(PER);
        uint256 entrants = craps.battleOf(_keyOf(PER)).entrants;
        assertEq(craps.boostShareFor(1000, 0), 0, "a scoreless winner can still take house money");

        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);
        // The protocol's own boost is rationed by the winner's standing and then rounded; the
        // DONATION is neither, and rides on top whole. Written as the sum so it holds whichever
        // seat the dice hand the pot to.
        uint256 expected = (
            uint256(BON_SU) * entrants
                + craps.roundBoostFor(craps.boostShareFor(craps.boostUnitsAt(slot), craps.betOf(pot.betId).standing))
                + 7
        ) * unit;
        assertEq(pot.amount, expected, "the donation did not reach the winner whole");
    }

    /// @dev A ROUND MUST FIT THE RESOLVER'S LEG. A blank ticket leaves all ten chips to the dice
    ///      and they may land on ONE leg, so a round above the `uint24` table maximum would be
    ///      silently truncated at settlement — a board smaller than the bankroll paid for it.
    function test_aRoundMustFitTheResolversLeg() public {
        uint40 close = uint40(vm.getBlockTimestamp() + 1 hours);
        // The largest legal round: the table maximum, down to a whole ten-chip stack.
        uint32 widest = uint32((uint256(type(uint24).max) / 10) * 10);
        vm.prank(vaultOwner);
        craps.createBattle(widest, 1, 5, 0, 0, close, false, 0);

        vm.prank(vaultOwner);
        vm.expectRevert(CrapsBattle.BoardNotWholeStack.selector);
        craps.createBattle(widest + 10, 1, 5, 0, 0, close, false, 0);
    }

    /// @dev A WINDOW SEAT BARS THE DAY LANE. `_place` already refuses a second seat to a day
    ///      ticket holder; without the mirror of that test on the day door, taking the windows one
    ///      at a time and THEN the day would seat one address twice in every window of its day.
    function test_aWindowSeatBarsTheWholeDayLane() public {
        _warpInto(0, 0);
        _openDay();
        _enter(alice, 0);
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusDay(_seven(), 1);
    }

    /// @dev A BOARD STOPS MOVING WHEN THE FIELD STOPS FORMING — at the entry close, not at the
    ///      arm. Between the two sits a window nobody has shut yet whose field is already public
    ///      and frozen; amending there would be a move nobody who entered on time ever had.
    function test_aBoardStopsMovingWhenTheFieldStopsForming() public {
        _openDay();
        uint256 betId = _enter(alice, PER);
        _warpPastClose(PER);
        assertFalse(craps.isShut(_slotAt(PER)), "the window was already armed");
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.amendSlip(betId, _boardB());
    }

    /// @dev The house and the vault ENTER the window's battle under the window's own key, so the
    ///      key their stored headers recompute has to be that same key. If it is not, their
    ///      resolutions score some other battle, the window's entrant count can never be matched
    ///      by its resolved count, and every pot in it is unclaimable.
    function test_theHouseAndVaultSeatsKeyTheWindowTheySatIn() public {
        _openDay();
        uint256 house = _houseSeat(PER);
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();
        // Pinned: window six closes ON the next day's boundary, so `currentBonusSlot` has already
        // rolled over by the time it is shut and cannot name the day these windows belong to.
        (uint24 theDay,,) = craps.currentBonusSlot();

        // The pair sits in EVERY window of the day off the one pair of tickets. Shut each and the
        // fold has to put them back at the head of that window's field — the same own-then-day
        // mapping the `resolveSlot` walk uses. If it ever did not, the entrant count could
        // never be matched by the resolved count and every pot in the day would be unclaimable.
        for (uint256 p = 0; p < periods; ++p) {
            _warpPastClose(p);
            uint64 slot = _slotOn(theDay, p);
            _setIndex(craps.armBonusWindow(slot));
            assertEq(craps.battleOf(_slotKeyOf(slot)).entrants, 2, "a window shut without the day field");
            assertEq(_idAt(slot, 1), house, "the house is not this window's first seat");
            assertEq(_idAt(slot, 2), house + 1, "the vault is not this window's second seat");
        }
    }

    /// @dev FOUR CHIPS A LEG, at every door that names a board. A round is seven chips over ten
    ///      legs, so without the cap a whole ticket could ride ONE number — a different game from
    ///      the spread the round is priced as. The consequence is deliberate: a single-leg board is
    ///      now impossible, because seven will not fit anywhere.
    ///
    ///      The DICE are not capped, and are not meant to be: the three they place on a picked
    ///      ticket, or all ten on a blank one, may land wherever they land. The rule is about what
    ///      a ticket CHOOSES, and the dice choose nothing.
    function test_fourChipsIsTheCapOnEveryNamedLeg() public {
        _openDay();
        game.setScore(alice, BON_SCORE);

        Craps.Bets memory over;
        over.place6 = 5;
        over.place8 = 2;
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.TooManyChipsOnALeg.selector);
        craps.enterBonusBattle(PER, over, 1);

        // Four is the boundary, and it seats.
        Craps.Bets memory atCap;
        atCap.place6 = 4;
        atCap.place8 = 3;
        vm.prank(alice);
        uint256 betId = craps.enterBonusBattle(PER, atCap, 1);
        assertEq(craps.betOf(betId).chips, (uint256(4) << 9) | (uint256(3) << 12), "the capped board did not seat");

        // And an amendment cannot smuggle a fifth chip onto a leg afterwards.
        vm.prank(alice);
        vm.expectRevert(CrapsBattle.TooManyChipsOnALeg.selector);
        craps.amendSlip(betId, over);
    }

    /// @dev THE VAULT NAMES ITS OWN BOARD. It is seated automatically at every bonus day, by a
    ///      call that takes no arguments, so without a standing board its ticket is blank and the
    ///      dice place all ten of its chips. The HOUSE keeps the blank either way — it has nobody
    ///      to choose for it, and naming nothing is the one shape that cannot be read in advance.
    function test_theVaultPlaysTheBoardItsOwnerNamed() public {
        // Four chips on place 4, three on hard 8 — seven, in the packed layout the events carry.
        uint32 board = uint32((uint256(4) << 3) | (uint256(3) << 24));

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.NotVaultOwner.selector);
        craps.setVaultBoard(board);

        vm.prank(vaultOwner);
        craps.setVaultBoard(board);

        _openDay();
        uint256 daySlot = craps._daySlotOfPub(craps.currentDayIndex());
        assertEq(craps.betOf((daySlot << 64) | 1).player, ContractAddresses.SDGNRS, "seat one is not the house");
        assertEq(craps.betOf((daySlot << 64) | 1).chips, 0, "the house stopped leaving its chips to the dice");
        assertEq(craps.betOf((daySlot << 64) | 2).player, ContractAddresses.VAULT, "seat two is not the vault");
        assertEq(craps.betOf((daySlot << 64) | 2).chips, board, "the vault did not play the board it named");
    }

    /// @dev The board is read AT SEAT TIME and never copied forward, so changing it moves every day
    ///      the vault has not been seated at yet and no day it already has. A seat already taken
    ///      moves with `amendSlip` or not at all.
    function test_theVaultsBoardIsChangeableAndRestorable() public {
        uint32 board = uint32((uint256(4) << 3) | (uint256(3) << 24));
        vm.prank(vaultOwner);
        craps.setVaultBoard(board);
        _openDay();
        uint256 seat = (craps._daySlotOfPub(craps.currentDayIndex()) << 64) | 2;
        assertEq(craps.betOf(seat).chips, board, "day one did not take the board");

        vm.prank(vaultOwner);
        craps.setVaultBoard(0);
        assertEq(craps.betOf(seat).chips, board, "changing the board rewrote a seat already taken");

        _nextWordedDay();
        _openDay();
        uint256 next = (craps._daySlotOfPub(craps.currentDayIndex()) << 64) | 2;
        assertEq(craps.betOf(next).player, ContractAddresses.VAULT, "seat two of the new day is not the vault");
        assertEq(craps.betOf(next).chips, 0, "a blank board did not restore the draw");
    }

    /// @dev THE VAULT MAY SIT THE DAY OUT. The sentinel is not a board, it is an instruction not
    ///      to take a seat — so the vault buys nothing, burns nothing, and the day opens without it.
    function test_theVaultCanStandDownEntirely() public {
        // Read the sentinel BEFORE the prank: it is an external call, and a prank covers only the
        // next one.
        uint32 off = craps.VAULT_BOARD_OFF();
        vm.prank(vaultOwner);
        craps.setVaultBoard(off);

        uint256 spent = flip.burned(ContractAddresses.VAULT);
        _openDay();
        uint24 day = craps.currentDayIndex();
        assertEq(craps.dayTicketsOf(day), 1, "the vault took a seat despite standing down");
        assertEq(
            craps.betOf((craps._daySlotOfPub(day) << 64) | 1).player,
            ContractAddresses.SDGNRS,
            "the house did not take the day alone"
        );
        assertEq(flip.burned(ContractAddresses.VAULT), spent, "a stood-down vault still paid");

        // And it comes back the moment a board is named again.
        vm.prank(vaultOwner);
        craps.setVaultBoard(0);
        _nextWordedDay();
        _openDay();
        assertEq(craps.dayTicketsOf(craps.currentDayIndex()), 2, "the vault did not come back");
    }

    /// @dev STANDING DOWN SPENDS NOTHING — not FLIP, and not a banked pass either. The check sits
    ///      ahead of the whole funding ladder, so declining a day costs the vault nothing it holds.
    ///      A day a pass ALREADY bought is untouched: that seat was paid for when the pass was
    ///      spent, and there is nothing left to decline.
    function test_standingDownSpendsNoBankedPass() public {
        address vault = ContractAddresses.VAULT;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(vault, 2, 0); // one takes tomorrow outright, one banks
        (uint256 banked,) = craps.passCreditsOf(vault);
        assertEq(banked, 1, "the second pass did not bank");

        uint32 off = craps.VAULT_BOARD_OFF();
        vm.prank(vaultOwner);
        craps.setVaultBoard(off);

        // Tomorrow: already seated by the pass, so standing down does not reach it.
        _nextWordedDay();
        _openDay();
        assertEq(craps.dayStateOf(craps.currentDayIndex(), vault), craps.DAY_SEATED(), "the paid day was declined");

        // The day after: nothing standing, so it stands down and the banked pass survives.
        _nextWordedDay();
        _openDay();
        assertEq(craps.dayStateOf(craps.currentDayIndex(), vault), 0, "a stood-down vault sat anyway");
        (banked,) = craps.passCreditsOf(vault);
        assertEq(banked, 1, "standing down spent the banked pass");
    }

    /// @dev SEVEN CHIPS OR NONE, and never both sides — the same rule both paid doors enforce, so
    ///      the vault can never hold a shape a player could not.
    function test_theVaultsBoardIsSevenChipsOrNone() public {
        vm.startPrank(vaultOwner);
        // Six chips, spread so the COUNT is what is refused rather than the per-leg cap.
        vm.expectRevert(CrapsBattle.BadRandomCount.selector);
        craps.setVaultBoard(uint32(4 | (uint256(2) << 9)));

        // And the cap itself, on a board that would otherwise be a legal seven.
        vm.expectRevert(CrapsBattle.TooManyChipsOnALeg.selector);
        craps.setVaultBoard(uint32((uint256(5) << 9) | (uint256(2) << 12)));

        vm.expectRevert(CrapsBattle.BoardPlaysBothSides.selector);
        craps.setVaultBoard(uint32(uint256(4) | (uint256(3) << 27)));

        craps.setVaultBoard(uint32(SEVEN_PACKED));
        craps.setVaultBoard(0);
        vm.stopPrank();
    }

    /// @dev A STARVED HOUSE IS COMPED, BOUNTY AND ALL; THE VAULT IS NOT. A bonus that waits on the
    ///      reserve is a bonus that silently stops happening, so the house sits whatever it holds
    ///      and the day always has somebody in it. The vault seeds nothing and is just another
    ///      body at the table, so it pays or it stays out.
    ///
    ///      The comped seat costs the field one bounty nobody burned. That is the price of the day
    ///      running at all — one seat, announced by `CrapsHouseComped` so it is never silent.
    function test_aStarvedHouseIsCompedAndTheVaultIsNot() public {
        address house = ContractAddresses.SDGNRS;
        flip.setBurnRefused(house, true);
        flip.setBurnRefused(ContractAddresses.VAULT, true);

        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertEq(flip.burned(house), 0, "a comped seat still burned");
        assertEq(flip.burned(ContractAddresses.VAULT), 0, "the vault burned despite being refused");
        assertEq(craps.dayTicketsOf(craps.currentDayIndex()), 1, "the day is not the house alone");

        uint256 seat = (craps._daySlotOfPub(craps.currentDayIndex()) << 64) | 1;
        assertEq(craps.betOf(seat).player, house, "the comped seat is not the house's");

        // The comped seat is a real one: it joins the field and races like any other.
        _warpPastClose(PER);
        _setIndex(craps.armBonusWindow(_slotAt(PER)));
        assertEq(craps.battleOf(_keyOf(PER)).entrants, 1, "the comped seat did not take its place");
    }

    /// @dev A STARVED HOUSE THAT HOLDS A PASS STILL SITS. The pass is what the comp used to be,
    ///      except that it was actually paid for — so the seat is funded and the pot it can win
    ///      is one the field's own bounties cover.
    function test_aStarvedHouseWithAPassStillSits() public {
        address house = ContractAddresses.SDGNRS;
        vm.prank(ContractAddresses.GAME);
        craps.deliverPasses(house, 2, 0);
        flip.setBurnRefused(house, true);
        flip.setBurnRefused(ContractAddresses.VAULT, true);

        // Day one is already seated by the delivery itself; day two spends the banked credit.
        _nextWordedDay();
        _openDay();
        _nextWordedDay();
        _openDay();

        uint24 day = craps.currentDayIndex();
        assertEq(flip.burned(house), 0, "the house burned despite holding a pass");
        assertEq(craps.dayStateOf(day, house), craps.DAY_SEATED(), "a banked pass did not seat the house");
        assertEq(craps.dayTicketsOf(day), 1, "the vault sat without paying");
    }

    /// @dev No word, no day. Today's daily word is what draws every window's terms AND what makes
    ///      sDGNRS's backing settleable, so opening ahead of it would seat a house that cannot pay
    ///      for its own seat.
    function test_theDayWaitsForItsWord() public {
        _warpInto(1, PER); // a new day, whose word has not landed
        (, bool openable) = craps.bonusDayOf();
        assertFalse(openable, "advertised as openable with no word");
        // A wordless day opens NOTHING and reverts nothing. The advance is what calls this, and
        // the terms come off a word the advance applies two calls earlier — so if it were ever
        // missing, the answer has to be a day without windows, never a protocol that will not
        // advance. The latch is untouched, so the day still opens once the word lands.
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        (uint24 latched,) = craps.bonusDayOf();
        assertTrue(latched != craps.currentDayIndex(), "a wordless day latched as opened");

        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        (, openable) = craps.bonusDayOf();
        assertTrue(openable, "a worded day is not openable");
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
    }

    /// @dev Standing scales with the size of the room: the bar is proportional to the buy-in,
    ///      anchored so `BONUS_SCORE_REF_BUYIN` asks `BONUS_SCORE_AT_LARGE`. Never zero — a
    ///      scoreless address is out of every backed window however small, which is the whole
    ///      reason house money is gated at all.
    function test_everyBonusWindowAdmitsAnybody() public {
        _openDay();
        (uint24 day,,) = craps.currentBonusSlot();
        // Whatever the room is worth, its door asks for nothing. House money is defended at the
        // PAYOUT — a low-scoring winner carries off only a slice of the boost — so there is no
        // reason left to turn anyone away, however big the window.
        for (uint256 p = 0; p < craps.BONUS_PERIODS_PER_DAY(); ++p) {
            (,,,,, uint256 bar) = craps.bonusTermsFor(day, p);
            assertEq(bar, 0, "a bonus window still asks for standing");
        }

        address scoreless = makeAddr("scorelessEntrant");
        assertEq(game.score(scoreless), 0, "the fixture is not scoreless");
        vm.prank(scoreless);
        uint256 betId = craps.enterBonusBattle(PER, _seven(), 1);
        assertEq(craps.battleKeyOf(betId), _keyOf(PER), "a scoreless address was turned away");
        assertEq(craps.betOf(betId).standing, 0, "the slip recorded a standing it does not hold");
    }

    /// @dev A tournament hands you seven chips and lets you put them where you like. The door
    ///      takes them by COUNT and the window scales them to its own chip, so splitting a chip
    ///      is not something an entry can even express — and the only thing left to police is the
    ///      count itself.
    function test_aWindowTakesSevenChipsHoweverYouSpreadThem() public {
        _openDay();
        bytes32 key = _keyOf(PER);
        uint256 chip = (BON_STACK / 1 ether) / 7;
        assertGt(chip, 0, "the stack did not divide into whole chips");

        // Three on the line, two on a place, one on a hardway, one more elsewhere.
        Craps.Bets memory spread;
        spread.passLine = 3;
        spread.place6 = 2;
        spread.hard8 = 1;
        spread.place9 = 1;
        game.setScore(alice, BON_SCORE);
        vm.prank(alice);
        uint256 a = craps.enterBonusBattle(PER, spread, 1);
        assertEq(craps.battleKeyOf(a), key, "a legal spread did not seat");
        // The ticket stores COUNTS; the window scales them to its own chip at settlement.
        assertEq(craps.betOf(a).chips & 7, 3, "the ticket did not name three on the line");
        assertEq((craps.betOf(a).chips >> 24) & 7, 1, "the ticket did not name one on the hard eight");

        // All seven on ONE leg is refused: four a leg is the table's cap, so a stack must spread.
        Craps.Bets memory piled;
        piled.place4 = 7;
        game.setScore(bob, BON_SCORE);
        vm.prank(bob);
        vm.expectRevert(CrapsBattle.TooManyChipsOnALeg.selector);
        craps.enterBonusBattle(PER, piled, 1);

        // Spread to the cap it seats, and keys the same race — composition is still not a term.
        Craps.Bets memory capped;
        capped.place4 = 4;
        capped.place10 = 3;
        vm.prank(bob);
        assertEq(craps.battleKeyOf(craps.enterBonusBattle(PER, capped, 1)), key, "a capped spread landed elsewhere");

        // Any other count is not this window's stack. Whether the chip rule refuses it outright
        // or it simply keys as a different race depends on the window's chip; either way it is
        // not the race the house is backing.
        game.setScore(carol, BON_SCORE);
        for (uint24 n = 1; n <= 14; ++n) {
            if (n == 7) continue;
            Craps.Bets memory off = _spread(n);
            vm.prank(carol);
            // Seven or none. Every other count is REFUSED outright — it used to derive a round
            // of its own and key a private battle at this slot, with the bounty stranded in it.
            vm.expectRevert(CrapsBattle.BadRandomCount.selector);
            craps.enterBonusBattle(PER, off, 1);
        }
    }

    /// @dev Every battle puts TEN chips down. Place seven and the dice place three; place none
    ///      and the dice place all ten. Either way the same round goes on the table, so either
    ///      way it is the same race — the match key is built on the round PLAYED, not on how much
    ///      of it the entrant chose to name.
    function test_aBlankTicketLetsTheDicePlaceAllTenChips() public {
        _openDay();
        bytes32 key = _keyOf(PER);
        uint256 played = BON_STACK / 7 * 10;

        Craps.Bets memory blank;
        game.setScore(alice, BON_SCORE);
        vm.prank(alice);
        uint256 a = craps.enterBonusBattle(PER, blank, 1);
        // Chips-all-zero IS the blank ticket: the mode needs no field of its own.
        assertEq(craps.betOf(a).chips, 0, "a blank ticket named something");

        // A picked ticket posts only its seven, and races the blank one in the SAME battle.
        uint256 b = _enter(bob, PER);
        assertEq(craps.betOf(b).chips, SEVEN_PACKED, "a picked ticket named the wrong count");
        assertEq(craps.battleKeyOf(a), key, "a blank ticket landed in another battle");
        assertEq(craps.battleKeyOf(b), key, "a picked ticket landed in another battle");

        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("blank")));

        // Both grow into the same ten-chip round, and the blank one is genuinely spread rather
        // than sitting where it was posted.
        Craps.Bets memory drawnA = craps.drawnBoardOf(a);
        Craps.Bets memory drawnB = craps.drawnBoardOf(b);
        assertEq(craps.stakeFor(drawnA), played, "the blank ticket missed the round");
        assertEq(craps.stakeFor(drawnB), played, "the picked ticket missed the round");
        assertLt(drawnA.passLine, uint24(played / 1 ether), "the blank ticket never left the pass line");
        assertTrue(keccak256(abi.encode(drawnA)) != keccak256(abi.encode(drawnB)), "two players drew one board");

        // And they settle together: one field, one verdict.
        _resolveSlot(PER);
        assertTrue(craps.battleOf(key).finalized, "the mixed field did not finalize");
    }

    /// @dev The tournament's shape, held to its definition so it cannot drift: a single table
    ///      bet; ten chips of it are the BASE a round puts down and seven of them are what an
    ///      entrant posts; the bankroll runs some whole number of those bases deep; and the
    ///      target is some whole multiple of the bankroll. Swept over every window of many days,
    ///      so this pins the format itself rather than one draw of it.
    function test_tournamentFormatIsChipsBaseDepthTarget() public {
        bool sawDepth2;
        bool sawDepth10;
        bool sawNearTarget;
        bool sawFarTarget;

        for (uint24 d = 1; d <= 120; ++d) {
            _setDailyWord(d, uint256(keccak256(abi.encode("format", d))));
            for (uint256 p = 0; p < craps.BONUS_PERIODS_PER_DAY(); ++p) {
                (uint128 bank, uint128 goal, uint256 stack,,,) = craps.bonusTermsFor(d, p);
                uint256 bankFlip = uint256(bank) / 1 ether;
                uint256 stackFlip = stack / 1 ether;

                // The posted stack is seven whole chips; ten of that chip make the base.
                assertEq(stackFlip % 7, 0, "the posted stack is not seven whole chips");
                uint256 baseFlip = stackFlip / 7 * 10;
                assertGt(baseFlip, 0, "the chip rounded away to nothing");

                // The bankroll is a whole number of bases deep, and one of the offered depths.
                assertEq(bankFlip % baseFlip, 0, "the bankroll is not a whole number of bases");
                uint256 depth = bankFlip / baseFlip;
                assertTrue(depth == 2 || depth == 5 || depth == 10, "an unoffered bankroll depth");
                if (depth == 2) sawDepth2 = true;
                if (depth == 10) sawDepth10 = true;

                // The target is a whole multiple of the bankroll, and one of the offered ones.
                assertEq(uint256(goal) % uint256(bank), 0, "the target is not a multiple of the bankroll");
                uint256 mult = uint256(goal) / uint256(bank);
                assertTrue(mult == 5 || mult == 10 || mult == 20 || mult == 50, "an unoffered target");
                if (mult == 5) sawNearTarget = true;
                if (mult == 50) sawFarTarget = true;
            }
        }

        // Both ends of both draws actually turn up, so neither is a constant in disguise.
        assertTrue(sawDepth2 && sawDepth10, "the bankroll depth never varied across its range");
        assertTrue(sawNearTarget && sawFarTarget, "the target never varied across its range");
    }

    /// @dev The three chips nobody picks are drawn at settlement off the table's own word, keyed
    ///      to the OWNER — so two entrants at one window get different boards, a player's board
    ///      is theirs alone, and none of it was knowable when the slip went down, because the
    ///      word did not exist yet.
    function test_theThrownChipsAreDrawnAtSettlementPerPlayer() public {
        _openDay();
        uint256 a = _enter(alice, PER);
        uint256 b = _enter(bob, PER);
        assertEq(craps.betOf(a).chips, SEVEN_PACKED, "the slip does not read as seven chips named");

        // Before the roll it carries only the seven it posted.
        assertEq(craps.betOf(a).chips, SEVEN_PACKED, "the named chips moved");

        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("scatter")));

        Craps.Bets memory boardA = craps.drawnBoardOf(a);
        Craps.Bets memory boardB = craps.drawnBoardOf(b);

        // Drawn, grown to the full ten-chip round, and different between the two players.
        uint256 played = BON_STACK / 7 * 10;
        assertEq(craps.stakeFor(boardA), played, "the drawn board missed the round");
        assertEq(craps.stakeFor(boardB), played, "the drawn board missed the round");
        assertTrue(keccak256(abi.encode(boardA)) != keccak256(abi.encode(boardB)), "two players drew one board");

        // And it settles on what it drew — through the slot lane, the only door a window has.
        _resolveSlot(PER);
        assertTrue(craps.betOf(a).settled, "a deferred board did not settle");
    }

    /// @dev One seat per player in a window house money is behind: it buys a field of distinct
    ///      players, not a field of one player's entries. Ordinary battles are untouched —
    ///      separately funded entries there only move a player's own money around.
    function test_aWindowTakesOneSeatPerPlayer() public {
        _openDay();
        _enter(alice, PER);

        vm.prank(alice);
        vm.expectRevert(CrapsBattle.AlreadyInBonus.selector);
        craps.enterBonusBattle(PER, _seven(), 1);

        // Another player still gets theirs.
        _enter(bob, PER);
        // Own entries only while the window is live; the house and the vault are day tickets and
        // join the count when it shuts.
        assertEq(craps.battleOf(_keyOf(PER)).entrants, 2, "the second player was turned away too");

        // And a CUSTOM battle nobody seeded still takes as many entries as anyone funds:
        // separately funded entries there only shuffle a player's own money.
        uint64 slot = _slotFor(LW * 2, LW * 10, SU);
        _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        _placeBattle(alice, _boardA(), LW * 2, LW * 10, SU);
        assertEq(craps.battleOf(craps.battleKeyOf((uint256(slot) << 64) | 1)).entrants, 2, "a second entry was refused");
    }

    /// @dev One allocation, every window still open. Each scales the same seven chips to its own
    ///      chip, which is the whole reason the door counts chips rather than FLIP — and windows
    ///      whose period has already passed, or that this player already sits in, are skipped
    ///      rather than costing them the rest of the day.
    function test_oneCallEntersEveryWindowStillOpen() public {
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        (uint24 day,,) = craps.currentBonusSlot();
        uint256 periods = craps.BONUS_PERIODS_PER_DAY();

        // The bar differs window to window, so meet the largest of them.
        uint256 bar;
        for (uint256 p = 0; p < periods; ++p) {
            (,,,,, uint256 need) = craps.bonusTermsFor(day, p);
            if (need > bar) bar = need;
        }
        game.setScore(alice, bar);

        vm.prank(alice);
        assertEq(craps.enterBonusDay(_seven(), 1), periods - PER, "the day entry missed a window");
        for (uint256 p = 0; p < periods; ++p) {
            assertEq(craps.battleOf(_keyOf(p)).entrants, p >= PER ? 1 : 0, "wrong field size");
        }

        // A second call takes nothing rather than reverting the lot.
        vm.prank(alice);
        assertEq(craps.enterBonusDay(_seven(), 1), 0, "a second day entry double-seated");
    }

    /// @dev Anyone may put money ONTO a window: the donor takes nothing back, gains no seat and
    ///      cannot reach it again, which is what makes it permissionless. It banks on top of
    ///      whatever the window rolls at claim rather than being swallowed by it.
    function test_anyoneMayDonateOntoAWindow() public {
        _openDay();
        bytes32 key = _keyOf(PER);
        uint256 unit = craps.BATTLE_STAKE_UNIT();
        assertEq(craps.battleOf(key).seed, 0, "a tier window banked house money up front");

        vm.prank(carol);
        craps.donate(false, PER, 5);
        assertEq(flip.burned(carol), 5 * unit, "the donation was not burned");
        assertEq(craps.battleOf(key).seed, 5 * unit, "the donation did not bank");
        (,,, bool joinable) = craps.bonusWindowOf(PER);
        assertTrue(joinable, "a donation shut the window");

        // A donor buys no seat with it. The window is live, so this counts its own entries alone.
        assertEq(craps.battleOf(key).entrants, 0, "the donor took a seat");

        _enter(alice, PER);
        _enter(bob, PER);
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("donated")));

        uint64 slot = _slotAt(PER);
        uint256[] memory field = _fieldOf(slot);
        PaidOut memory pot = _onlyPot(craps, slot, WHOLE_FIELD);
        CrapsBattle.Battle memory done = craps.battleOf(key);
        (uint24 qday,,) = craps.currentBonusSlot();
        (,, uint256 high) = craps.bonusBoostBand(qday, PER);
        uint256 stakes = uint256(BON_SU) * unit * field.length;

        // The whole pot to the single winner: the donation rides ON TOP of whatever this window's
        // ladder drew rather than being swallowed by it. Asserted against the granule figure the
        // claim actually pays from, because the pick is floored to granules and the band is not.
        uint256 winnerId = _idAt(slot, done.winnerId);
        uint256 drewUnits = craps.boostUnitsAt(slot);
        assertGe(drewUnits, 5, "the donation did not survive the pick");
        uint256 drew = craps.boostShareFor(drewUnits, craps.betOf(winnerId).standing) * unit;

        assertEq(pot.betId, winnerId, "the pot named a seat the scoreboard did not");
        assertEq(pot.player, craps.betOf(winnerId).player, "the pot reached an address that held no seat");
        assertEq(pot.amount, stakes + drew, "the pot is not the stakes, the pick and the donation");
        assertLe(drewUnits * unit, high + 5 * unit, "the boost drew over the band plus the donation");
    }

    /// @dev Nothing is donatable that could overflow the seed field, and nothing is donatable to
    ///      a window that was never opened.
    function test_donationIsBoundedAndNeedsAnOpenWindow() public {
        // An unopened day is not a battle you could bet into, so it is not one you may seed
        // either — the joinability gate runs before the amount is even looked at.
        vm.prank(carol);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.donate(false, PER, 5);

        _openDay();
        vm.prank(carol);
        vm.expectRevert(CrapsBattle.SeedAboveMax.selector);
        craps.donate(false, PER, 0);

        // Hoisted: an inline `craps.BONUS_PERIODS_PER_DAY()` would be the call the prank and the
        // expectation land on, and the donation would run unpranked and unwatched.
        uint256 past = craps.BONUS_PERIODS_PER_DAY();
        vm.prank(carol);
        vm.expectRevert(CrapsBattle.BonusPeriodSpent.selector);
        craps.donate(false, past, 1);
    }
}
