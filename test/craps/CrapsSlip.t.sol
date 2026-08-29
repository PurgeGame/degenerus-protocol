// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {CrapsViews} from "./CrapsViews.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {CrapsBattle, IFlipCoin, ICoinflipStake, IGameActivityScore} from "../../contracts/CrapsBattle.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @dev Points the three pins (game slots, FLIP) at doubles. Overrides nothing else, so every rule
///      under test is the shipped one.
contract CrapsSlipHarness is CrapsViews {
    /// @dev The suite's oracle. `resolveSlipAt` / `resolveHandsAt` and the scripted-dice replay
    ///      were cut from production — they cost this contract its EIP-170 headroom and settlement
    ///      never called one. They are rebuilt here over the SHIPPED `seedFor`, so the assertions
    ///      below still compare production's lean settlement against an independent engine off the
    ///      identical seed. That comparison is the point: it is what makes these tests statements
    ///      about `CrapsBattle` rather than about a fixture.
    CrapsOracle internal immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    /// @dev The whole settlement of a bet, stop included — production decides a FORFEIT off the
    ///      stop, so a suite grading the money path has to be able to see it.
    function settlementAt(uint256 betId) external view returns (Settlement memory) {
        return _settlementOf(betId, _bets[betId], _slotWindow(betId >> 64), _wordAt(_indexOf(betId >> 64)));
    }

    /// @dev Engine-only: a run off a bare table seed, for comparisons that hold no bet.
    function resolveSlipAt(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 goal, uint256 cap)
        external
        view
        returns (CrapsOracle.SlipResult memory)
    {
        return oracle.resolveSlip(b, _seedFor(index), bankroll, goal, cap);
    }

    /// @dev Engine-only, for a NAMED owner: same table seed, different survival coin. This is
    ///      what lets the suite hold the table fixed and move only the owner.
    function resolveSlipAtFor(
        Craps.Bets calldata b,
        uint48 index,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player
    ) external view returns (CrapsOracle.SlipResult memory) {
        return oracle.resolveSlipFor(b, _seedFor(index), bankroll, goal, cap, player);
    }

    /// @dev Seeded the way PRODUCTION seeds a BET: `_crapsSeed(word, slot)`. A settlement keys its
    ///      run on the battle's slot, not on the table index it shut onto — two slots that took
    ///      the same table still get their own dice — so an oracle keyed on the index could never
    ///      agree with it. The OWNER rides in beside it because the survival coin is salted by the
    ///      slip's owner: an oracle that left it out would diverge the moment a coin fired.
    function resolveSlipForBet(
        Craps.Bets calldata b,
        uint64 slot,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player
    ) external view returns (CrapsOracle.SlipResult memory) {
        return oracle.resolveSlipFor(
            b, _crapsSeed(_wordAt(_indexOf(slot)), uint48(slot)), bankroll, goal, cap, player
        );
    }

    function resolveHandsAt(Craps.Bets calldata b, uint48 index, uint256 hands)
        external
        view
        returns (CrapsOracle.Session memory)
    {
        return oracle.resolveHands(b, _seedFor(index), hands);
    }

    function resolveHandWithScriptedDice(Craps.Bets calldata b, uint8[] calldata dice, bytes32 seed)
        external
        view
        returns (CrapsOracle.Outcome memory)
    {
        return oracle.resolveHandWithScriptedDice(b, dice, seed);
    }

    /// @dev The board a slip actually PLAYS: its chips grown by the ones the dice place. No slip
    ///      settles on what it posted, so every oracle comparison has to be made against this.
    ///      Production draws it inside settlement and does not expose it — a client rebuilds it
    ///      from the slot, the word and the owner with one keccak.
    function drawnBoardOf(uint256 betId) external view returns (Craps.Bets memory board) {
        uint256 header = _bets[betId];
        Window memory w = _slotWindow(betId >> 64);
        uint256 chipFlip = (w.played / 1 ether) / BONUS_CHIPS;
        uint256 packed = (header >> _BET_CHIPS_SHIFT) & _BET_CHIPS_MASK;
        uint256 thrown = BONUS_CHIPS;
        if (packed != 0) {
            board = _boardFrom(packed, chipFlip);
            thrown = _RSEL_PICK7;
        }
        _scatterInto(
            board,
            uint256(keccak256(abi.encode(_wordAt(_indexOf(betId >> 64)), address(uint160(header))))),
            chipFlip,
            thrown
        );
    }

    /// @dev The MID-RUN second chance, reachable for (index, round) pairs no bet holds — which is
    ///      how the round salt is proven. Production consults `_survived` only inside the engine's
    ///      own loop, so there is no external on the table; the suite reaches the SHIPPED function
    ///      through this harness rather than adding one.
    function survivedAt(uint48 index, uint256 handsPlayed, address player) external view returns (bool) {
        return _survived(_seedFor(index), handsPlayed, player);
    }

    /// @dev Test tap into the slip engine with a caller-chosen roll budget — organically
    ///      unreachable through the production constant, so the stop logic is proven here. Drives
    ///      the shipped settlement engine, which takes the budget as a parameter of its own.
    function slipWithBudget(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 budget, address player)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, _seedFor(index), bankroll, 0, MAX_SLIP_HANDS, budget, player, 0);
    }

    /// @dev The same engine under a SCHEDULE. `boost` is the packed pair `_settleSlip` reads —
    ///      eligible-shooter percent in the low byte, profit percent above it — so a fixture can
    ///      pin an exact schedule on an exact seed rather than going through a window's draw.
    function slipWithBoost(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        return _settleSlip(b, seed, bankroll, goal, cap, SLIP_ROLL_BUDGET, player, boost);
    }

    /// @dev The engine under caller-chosen bounds, so a fixture can drive the shooter cap and the
    ///      roll budget directly.
    function slipUnder(
        Craps.Bets calldata b,
        bytes32 seed,
        uint256 bankroll,
        uint256 goal,
        uint256 cap,
        uint256 rollBudget,
        address player,
        uint256 boost
    ) external pure returns (Craps.SlipResult memory) {
        return _settleSlip(b, seed, bankroll, goal, cap, rollBudget, player, boost);
    }
}

/// @title CrapsBattle suite
/// @notice The resolver and the RNG binding are covered elsewhere. This is about the money: that a
///         stake is burned exactly once and bounds the loss, that the survival flip is one
///         table-level coin no batch composition can move, and that the award lands where
///         Degenerette's two-band rounding policy puts it.
contract CrapsSlipTest is CrapsPins {
    CrapsSlipHarness internal craps;

    /// @dev The legacy leg size the oracle fixtures still measure in — those drive the engine
    ///      directly and never pass the table's chip rule. `L` is one round on the pass line.
    uint24 internal constant U = 180;
    uint128 internal constant UW = 180e18;
    /// @dev The chip. A round is ten of them and an entry places SEVEN, so `C * 7` is what a
    ///      board posts, `C * 10` is the round it grows into, and the fixtures below are cut in
    ///      multiples of it.
    uint24 internal constant C = 60;
    uint24 internal constant L = 600;
    uint128 internal constant LW = 600e18;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal settler = makeAddr("settler");

    function setUp() public {
        _installPins();
        craps = new CrapsSlipHarness();
        // Genesis is a Craps warm-up day; every fixture plays from genesis + 1.
        vm.warp(block.timestamp + 1 days);
        _setIndex(4);
        // Clear of the sybil floor. This suite prices a SEAT — what a placement burns and what a
        // settlement pays back — so the low-score surcharge must not ride silently inside every
        // burn assertion; it has a test of its own.
        uint256 floor_ = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floor_);
        game.setScore(bob, floor_);
        game.setScore(settler, floor_);
    }

    /// @dev Chip COUNTS: three on the line, two on the six, two on the hard eight — seven of the
    ///      round's ten, with the dice placing the rest.
    function _bets() internal pure returns (Craps.Bets memory b) {
        b.passLine = 3;
        b.place6 = 2;
        b.hard8 = 2;
    }

    /// @dev The round these fixtures play, in whole FLIP: ten chips of `C`.
    uint32 internal constant PLAYED = uint32(C) * 10;

    /// @dev One table, one battle: open it, seat `who`, shut it onto `idx` and land `word`.
    function _run(address who, Craps.Bets memory chips, uint8 bankMult, uint16 goalMult, uint48 idx, uint256 word)
        internal
        returns (uint256 betId, uint64 slot)
    {
        slot = _openBattle(craps, PLAYED, bankMult, goalMult, 0);
        vm.prank(who);
        betId = craps.enterBattle(slot, chips, 1);
        _closeOn(craps, slot, idx, word);
    }

    /// @dev Open and seat, without shutting — for fixtures that assert on an OPEN battle.
    function _seat(address who, Craps.Bets memory chips, uint8 bankMult, uint16 goalMult)
        internal
        returns (uint256 betId, uint64 slot)
    {
        slot = _openBattle(craps, PLAYED, bankMult, goalMult, 0);
        vm.prank(who);
        betId = craps.enterBattle(slot, chips, 1);
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    /// @dev A slip's survival coin, recomputed independently of the engine — an indexer or a
    ///      client replay hardcodes this tag ("Survival"), the seed, the round and the OWNER. The
    ///      dice are the table's, so every slip at one table watches the same shooter; the coin is
    ///      the owner's, so no two of them take the same second chance. Mirrors `Craps._survived`.
    uint256 internal constant _SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    function _survivalCoin(bytes32 seed, uint256 n, address player) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(_SURVIVAL_TAG, seed, n, player))) & 1 == 1;
    }

    /// @dev Reconstruct a slip's final bankroll from scratch: walk the base-board ledger, applying
    ///      the escalator multiple AND the deterministic second-chance coin exactly where the engine
    ///      would, so this is a real check on the money path rather than a copy of the engine's own
    ///      scalar. A played hand below the round's stake proves its second-chance coin survived; the
    ///      stop round splits a hard bust (remainder kept) from a second-chance bust (bankroll zeroed).
    function _replaySlipBankroll(
        Craps.Bets memory b,
        uint48 idx,
        CrapsOracle.SlipResult memory r,
        address player,
        uint256 cap
    ) internal view returns (uint256 bank, uint256 units) {
        uint256 stake = craps.stakeFor(b);
        bytes32 seed = craps.seedFor(idx);
        bank = r.bankrollIn;
        for (uint256 h = 0; h < r.ledger.length; ++h) {
            uint256 q = 1 << (h / craps.ESC_HANDS());
            if (q > 0xFFFF) q = 0xFFFF;
            uint256 need = q * stake;
            if (bank < need) {
                assertGe(bank * 2, need, "played a hand below the second-chance floor");
                assertTrue(_survivalCoin(seed, h, player), "played on a losing second-chance coin");
                bank += bank;
            }
            units += q;
            bank = bank - need + q * uint256(int256(stake) + r.ledger[h].net);
        }
        if (
            r.stop == CrapsOracle.SlipStop.Bust && r.handsPlayed < cap
                && r.totalRolls < craps.SLIP_ROLL_BUDGET()
        ) {
            uint256 q = 1 << (r.ledger.length / craps.ESC_HANDS());
            if (q > 0xFFFF) q = 0xFFFF;
            if (bank * 2 >= q * stake) {
                // Not a hard bust — the run was in the second-chance band and the coin lost.
                assertTrue(!_survivalCoin(seed, r.ledger.length, player), "busted on a surviving coin");
                bank = 0;
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // Placing
    // ---------------------------------------------------------------------------------------

    /// @dev The bankroll is burned up front and is the player's entire exposure — there is no
    ///      second call on their wallet, whatever the dice do.
    function test_placeBurnsExactlyTheBankroll() public {
        (uint256 betId, uint64 slot) = _seat(alice, _bets(), 5, uint16(GOAL_FAR_MULT));

        assertEq(flip.burned(alice), uint256(PLAYED) * 5 * 1 ether, "burned the bankroll");
        assertEq(betId, (uint256(slot) << 64) | 1, "the id is the slot and the seat");

        CrapsBattle.Bet memory bet = craps.betOf(betId);
        assertEq(bet.player, alice, "owner");
        assertEq(bet.slot, slot, "bound to its battle");
        assertEq(bet.seat, 1, "first seat in the field");
        assertEq(bet.chips, uint256(3) | (uint256(2) << 9) | (uint256(2) << 24), "the chips it named");
        assertFalse(bet.settled, "settled");
    }

    /// @dev The protocol advances the index in the same call that requests its word, so the live
    ///      index should be empty. Placement checks that invariant itself before taking funds.
    function test_aSlipLearnsItsTableOnlyWhenItsBattleShuts() public {
        (uint256 betId, uint64 slot) = _seat(alice, _bets(), 3, uint16(GOAL_FAR_MULT));

        // Bound to the BATTLE, not to a table: no index exists for it yet, so nothing about the
        // dice could have been known when it was placed.
        assertEq(craps.betOf(betId).slot, slot, "not bound to its battle");
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.previewSettlement(betId);

        // Shutting picks the index, and the word for it cannot exist until after that.
        _setIndex(9);
        vm.warp(block.timestamp + 2 hours);
        uint48 index = craps.closeBattle(slot);
        assertEq(index, 10, "the close took the next table");
        assertEq(craps.wordAt(index), 0, "the table it took already carried a word");
    }

    /// @dev The table's entry floor is the BANKROLL, not the board: a bankroll under
    ///      `MIN_BANKROLL_FLIP` is refused whatever it is betting, and an empty board is refused
    ///      because no bankroll may exceed `MAX_BANKROLL_MULT` rounds of nothing.
    function test_rejectsBattlesUnderTheTableFloor() public {
        // The bankroll floor is proven ONCE, at the door that fixes it for the whole field.
        // Hoisted: an inline `craps.CONST()` inside a call's ARGUMENTS is the call that
        // `vm.expectRevert` lands on, not the one under test.
        uint8 maxMult = uint8(craps.MAX_BANKROLL_MULT());
        uint40 close = uint40(block.timestamp + 1 hours);
        vm.startPrank(vaultOwner);
        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(20, 14, 5, 0, 0, close, false, 0); // 280 FLIP, under the floor

        // A round that is not ten whole chips is not a round.
        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(25, 20, 5, 0, 0, close, false, 0);

        // A bankroll deeper than the cap, and one no rounds deep at all.
        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, maxMult + 1, 5, 0, 0, close, false, 0);
        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, 0, 5, 0, 0, close, false, 0);

        // Exactly at the floor, on the smallest round that can carry it: ten chips of two is a
        // 20-FLIP round, and fifteen of those is 300 FLIP.
        craps.createBattle(20, 15, 5, 0, 0, close, false, 0);
        vm.stopPrank();
    }

    /// @dev The indexer's contract with this game: `CrapsSlipPlaced` must carry everything needed
    ///      to rebuild a slip with no follow-up call, so an event-derived indexer never has to
    ///      reach for `betOf`. An entry places SEVEN whole chips, so nine legs cannot each carry a
    ///      distinct figure — instead the DOUBLE chip walks the board one leg at a time over the
    ///      five singles that fit beside it, which pins every field's shift on its own: a decoder
    ///      off by one boundary reads the double on the wrong leg and fails here rather than
    ///      silently mis-pricing every historical bet.
    function test_placementEventCarriesTheChips() public {
        bytes32 sig = keccak256("CrapsSlipPlaced(address,uint256)");
        uint64 slot = _openBattle(craps, PLAYED, 3, uint16(GOAL_FAR_MULT), 0);

        for (uint256 leg = 0; leg < 9; ++leg) {
            // One leg carrying three chips, the next four spread one each — a different shape
            // every pass, so every field of the packing is exercised at its own shift.
            uint24[9] memory legs;
            legs[leg] = 3;
            uint256 singles;
            for (uint256 k = 0; k < 9 && singles < 4; ++k) {
                if (k == leg) continue;
                legs[k] = 1;
                ++singles;
            }
            Craps.Bets memory b;
            (b.passLine, b.place4, b.place5, b.place6) = (legs[0], legs[1], legs[2], legs[3]);
            (b.place8, b.place9, b.place10, b.hard4, b.hard8) = (legs[4], legs[5], legs[6], legs[7], legs[8]);

            vm.recordLogs();
            vm.prank(alice);
            craps.enterBattle(slot, b, 1);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            uint256 chips;
            bool found;
            for (uint256 i = 0; i < logs.length; ++i) {
                if (logs[i].topics[0] != sig) continue;
                uint256 bet = abi.decode(logs[i].data, (uint256));
                // The id rides above the chips with a clear gap between them. It is a WINDOW in
                // the word, not its top — the standing sits above it — so the slot is masked out
                // of the id rather than shifted off the end.
                assertEq((bet >> 27) & 0x1F, 0, "the gap between the chips and the id is dirty");
                assertEq((bet >> 96) & type(uint64).max, slot, "the event named the wrong slot");
                assertEq((bet >> 190) & 0xFFFF, craps.SYBIL_SCORE_FLOOR(), "the event lost the frozen standing");
                chips = bet & 0x7FFFFFF;
                found = true;
            }
            assertTrue(found, "no placement event");
            for (uint256 k = 0; k < 9; ++k) {
                assertEq((chips >> (3 * k)) & 7, legs[k], "a leg decoded off its own shift");
            }
            assertEq(chips >> 27, 0, "a leg overflowed its three bits");
        }
    }

    // ---------------------------------------------------------------------------------------
    // Settling
    // ---------------------------------------------------------------------------------------

    /// @dev A table that has not rolled is passed OVER, never stopped on — that is what makes
    ///      "resolve everything from here" a call anyone can make without knowing which ids are
    ///      ready. What must not happen is a payout.
    function test_cannotSettleBeforeTheTableRolls() public {
        (uint256 betId, uint64 slot) = _seat(alice, _bets(), 3, uint16(GOAL_FAR_MULT));

        // Unshut: no table has been chosen, so there is nothing to settle against.
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.resolveSlot(slot, WHOLE_FIELD);

        // Shut, but the word has not landed.
        _setIndex(4);
        vm.warp(block.timestamp + 2 hours);
        craps.closeBattle(slot);
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.resolveSlot(slot, WHOLE_FIELD);

        assertFalse(craps.betOf(betId).settled, "settled before its table rolled");
        assertEq(coinflip.staked(alice), 0, "paid before its table rolled");
    }

    function test_settlesOnceAndOnlyOnce() public {
        (uint256 betId, uint64 slot) = _run(alice, _bets(), 3, uint16(GOAL_FAR_MULT), 4, uint256(keccak256("vrf")));

        craps.resolveSlot(slot, WHOLE_FIELD);
        assertTrue(craps.betOf(betId).settled, "settled");
        uint256 paidOnce = coinflip.staked(alice);

        // A second sweep is not an error, it is a no-op: the cursor has already passed the whole
        // field, so there is nothing left in the range to walk.
        craps.resolveSlot(slot, WHOLE_FIELD);
        assertEq(coinflip.staked(alice), paidOnce, "a second sweep paid the field again");
    }

    /// @dev Settlement is permissionless because it can only ever pay the bet's owner. A stranger
    ///      settling someone else's bet must move the money to that someone else.
    function test_anyoneMaySettleButOnlyTheOwnerIsPaid() public {
        // Search for a table that actually pays, so the assertion is about who gets the money
        // rather than about a run that happened to bust.
        for (uint256 i = 0; i < 40; ++i) {
            (uint256 betId, uint64 slot) =
                _run(alice, _bets(), 4, 5, uint48(4000 + i), uint256(keccak256(abi.encode("pay", i))));

            (, uint256 expected) = craps.previewSettlement(betId);
            if (expected == 0) continue;

            uint256 before = coinflip.staked(alice);
            vm.prank(settler);
            craps.resolveSlot(slot, WHOLE_FIELD);

            assertEq(coinflip.staked(alice) - before, expected, "owner paid");
            assertEq(coinflip.staked(settler), 0, "settler paid nothing");
            return;
        }
        revert("no paying table found");
    }

    /// @dev The preview and the payer share one computation, so they cannot disagree about what a
    ///      bet is worth. This is the assertion that keeps them shared.
    /// @dev The oracle is handed the SAME GOAL production ran with, never zero. A far goal looks
    ///      unreachable and almost always is — but the mid-run survival coin DOUBLES a bankroll,
    ///      and a long enough chain of survivals reaches even a thousand-times target. A run that
    ///      reaches it stops there in production while an oracle told `goal = 0` plays on, usually
    ///      to nothing. That is a rare false failure, not a real divergence, and this is where it
    ///      is closed.
    function test_previewIsExactlyWhatSettlementPays() public {
        uint256 bankroll = uint256(PLAYED) * 3 * 1 ether;
        for (uint256 i = 0; i < 12; ++i) {
            uint48 idx = uint48(100 + i);
            (uint256 betId, uint64 slot) =
                _run(alice, _bets(), 3, uint16(GOAL_FAR_MULT), idx, uint256(keccak256(abi.encode("w", i))));

            (uint256 won, uint256 expected) = craps.previewSettlement(betId);
            uint256 before = coinflip.staked(alice);
            craps.resolveSlot(slot, WHOLE_FIELD);
            assertEq(coinflip.staked(alice) - before, expected, "preview != paid");
            // The paying path runs lean (no per-leg books); the public view runs full. Pin them.
            assertEq(
                won,
                craps.resolveSlipForBet(craps.drawnBoardOf(betId), slot, bankroll, uint256(bankroll) * GOAL_FAR_MULT, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player).bankrollOut,
                "lean settlement != full-fidelity view"
            );
        }
    }

    function test_sideOnlySettlementMatchesFullResolver() public {
        // No pass line: the engine's place/hardway specialization resolves this one.
        Craps.Bets memory b;
        b.place6 = 4;
        b.hard8 = 3;
        uint256 bankroll = uint256(PLAYED) * 5 * 1 ether;

        for (uint256 i = 0; i < 12; ++i) {
            uint48 idx = uint48(500 + i);
            (uint256 betId, uint64 slot) =
                _run(alice, b, 5, uint16(GOAL_FAR_MULT), idx, uint256(keccak256(abi.encode("side", i))));

            (uint256 won,) = craps.previewSettlement(betId);
            assertEq(
                won,
                craps.resolveSlipForBet(craps.drawnBoardOf(betId), slot, bankroll, uint256(bankroll) * GOAL_FAR_MULT, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player).bankrollOut,
                "side-only lean settlement != full resolver"
            );
        }
    }


    /// @dev THE DIFFERENTIAL, over boards carrying the DARK LEG. The oracle is an independent
    ///      restatement of the rules — its own state machine, its own payout table — so agreement
    ///      here is the assertion that production implements Don't Pass rather than merely
    ///      implementing it consistently with itself.
    ///
    ///      Fuzzed on the word, so it is not one lucky shooter: a whole run is many hands, and a
    ///      run long enough to escalate visits every dark decision there is.
    function testFuzz_darkBoardsMatchTheIndependentOracle(uint256 rawWord, uint8 rawSplit) public {
        // Hashed rather than used raw: a table's word is a landed VRF word, and ZERO is how the
        // lane says "not landed yet". Feeding it in would test the readiness guard, not the rules.
        uint256 word = uint256(keccak256(abi.encode(rawWord)));
        // Seven chips split between the dark side and a light leg that is not the pass line —
        // naming both sides is refused at the door, and rightly so.
        // Bounded by the FOUR-A-LEG cap, and the light remainder spread over two legs for the
        // same reason: a seven-chip board can no longer sit on one number.
        uint256 dark = bound(uint256(rawSplit), 1, 4);
        Craps.Bets memory b;
        b.dontPass = uint24(dark);
        uint256 rest = 7 - dark;
        b.place6 = uint24(rest > 4 ? 4 : rest);
        if (rest > 4) b.place8 = uint24(rest - 4);

        uint256 bankroll = uint256(PLAYED) * 4 * 1 ether;
        (uint256 betId, uint64 slot) = _run(alice, b, 4, uint16(GOAL_FAR_MULT), 900, word);

        (uint256 won,) = craps.previewSettlement(betId);
        assertEq(
            won,
            craps.resolveSlipForBet(
                craps.drawnBoardOf(betId), slot, bankroll, uint256(bankroll) * GOAL_FAR_MULT, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player
            ).bankrollOut,
            "the dark lane diverged from the independent oracle"
        );
    }

    /// @dev The same differential on a NO-LINE board carrying the dark side at its cap, which is
    ///      what reaches the engine's no-line specialization with a dark wager on it. Both machines
    ///      carry their own copy of the rule, so this is the only fixture that grades the second.
    ///
    ///      Not dark-ONLY any more: four chips a leg is the table's cap, so seven cannot sit on
    ///      `dontPass` alone. The specialization keys on the absence of a PASS LINE, which a
    ///      place-6 remainder leaves untouched.
    function test_aDarkOnlyBoardMatchesTheIndependentOracle() public {
        Craps.Bets memory b;
        b.dontPass = 4;
        b.place6 = 3;
        uint256 bankroll = uint256(PLAYED) * 5 * 1 ether;

        for (uint256 i = 0; i < 12; ++i) {
            uint48 idx = uint48(1500 + i);
            (uint256 betId, uint64 slot) =
                _run(alice, b, 5, uint16(GOAL_FAR_MULT), idx, uint256(keccak256(abi.encode("dark", i))));

            (uint256 won,) = craps.previewSettlement(betId);
            assertEq(
                won,
                craps.resolveSlipForBet(
                    craps.drawnBoardOf(betId), slot, bankroll, uint256(bankroll) * GOAL_FAR_MULT, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player
                ).bankrollOut,
                "the dark-only lean settlement != full resolver"
            );
        }
    }

    // ---------------------------------------------------------------------------------------
    // The bet slip
    // ---------------------------------------------------------------------------------------

    function test_battleTermsAreVettedAtTheDoorThatFixesThem() public {
        uint40 close = uint40(block.timestamp + 1 hours);
        // Hoisted for the same reason as above.
        uint16 minGoal = uint16(craps.MIN_BATTLE_GOAL_MULT());
        uint16 maxGoal = uint16(craps.MAX_GOAL_MULT());
        uint16 maxScore = uint16(craps.MAX_MIN_SCORE());
        vm.startPrank(vaultOwner);

        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, 4, minGoal - 1, 0, 0, close, false, 0);

        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, 4, maxGoal + 1, 0, 0, close, false, 0);

        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, 4, 5, 0, maxScore + 1, close, false, 0);

        // A close time already past is not a window anyone can join.
        vm.expectRevert(CrapsBattle.BadBattleTerms.selector);
        craps.createBattle(PLAYED, 4, 5, 0, 0, uint40(block.timestamp), false, 0);

        uint64 slot = craps.createBattle(PLAYED, 4, 40, 0, 0, close, false, 0);
        vm.stopPrank();

        vm.prank(alice);
        uint256 betId = craps.enterBattle(slot, _bets(), 1);
        assertEq(flip.burned(alice), uint256(PLAYED) * 4 * 1 ether, "burned the bankroll");

        // Bankroll and target are the SLOT's, held as multiples of the round it plays.
        (,, uint256 terms) = craps.customBattleOf(slot);
        assertEq(terms & 0xFFFFFFF, PLAYED, "the round moved");
        assertEq((terms >> 28) & 0x1F, 4, "the bankroll depth moved");
        assertEq((terms >> 33) & 0x3FF, 40, "the target moved");
        assertEq(craps.betOf(betId).slot, slot, "the slip did not seat at the battle");
    }

    /// @dev Sweep tables and hold every run to its arithmetic: the final bankroll is exactly what an
    ///      independent replay of the base-board ledger — escalator multiple and second-chance coin
    ///      included — produces, and each stop reason means what it says.
    function test_slipStopsHonestlyAndConservesTheBankroll() public {
        Craps.Bets memory b;
        b.passLine = U;

        bool sawBust;
        bool sawGoal;
        for (uint256 i = 0; i < 30; ++i) {
            uint48 idx = uint48(6000 + i);
            _setIndex(idx);
            _setWord(idx, uint256(keccak256(abi.encode("slip", i))));

            CrapsOracle.SlipResult memory r = craps.resolveSlipAt(b, idx, UW * 3, UW * 6, craps.MAX_SLIP_HANDS());

            assertEq(r.ledger.length, r.handsPlayed, "ledger trimmed to hands played");
            (uint256 bank, uint256 units) =
                _replaySlipBankroll(b, idx, r, address(0), craps.MAX_SLIP_HANDS());
            assertEq(r.bankrollOut, bank, "bankroll does not match the second-chance replay");
            assertEq(r.unitsPlayed, units, "units != sum of mandatory multipliers");

            if (r.stop == CrapsOracle.SlipStop.Bust) {
                uint256 due = uint256(UW) * (uint256(1) << (r.handsPlayed / craps.ESC_HANDS()));
                assertLt(r.bankrollOut, due, "bust with the mandatory round still affordable");
                sawBust = true;
            } else if (r.stop == CrapsOracle.SlipStop.Goal) {
                assertGe(r.bankrollOut, uint256(UW) * 6, "goal reported below the goal");
                sawGoal = true;
            }
        }
        assertTrue(sawBust, "no busted run seen");
        assertTrue(sawGoal, "no goal run seen");
    }

    /// @dev The mid-run second chance. A run that cannot cover a full round but still holds at least
    ///      half of it takes one committed double-or-nothing: surviving doubles the bankroll and
    ///      plays on, losing zeroes it. A run short of even half a round gets no coin. Over many
    ///      tables the coin is fair, and a lost coin always leaves nothing behind.
    function test_secondChanceIsAFairDoubleOrBust() public {
        Craps.Bets memory b;
        b.passLine = U; // cheap one-unit rounds, so a small bankroll dips into the band often
        uint256 stake = craps.stakeFor(b);

        uint256 survives;
        uint256 busts;
        for (uint256 i = 0; i < 400; ++i) {
            uint48 idx = uint48(40_000 + i);
            _setIndex(idx);
            _setWord(idx, uint256(keccak256(abi.encode("2ndchance", i))));

            CrapsOracle.SlipResult memory r = craps.resolveSlipAt(b, idx, UW * 2, 0, craps.MAX_SLIP_HANDS());
            bytes32 seed = craps.seedFor(idx);

            // Every played hand that opened below its round stake proves a survived coin — and the
            // engine may never play one that opened below half the round.
            uint256 bank = r.bankrollIn;
            for (uint256 h = 0; h < r.ledger.length; ++h) {
                uint256 q = 1 << (h / craps.ESC_HANDS());
                if (q > 0xFFFF) q = 0xFFFF;
                uint256 need = q * stake;
                if (bank < need) {
                    assertGe(bank * 2, need, "a coin fired below half a round");
                    assertTrue(_survivalCoin(seed, h, address(0)), "played on a lost coin");
                    ++survives;
                    bank += bank;
                }
                bank = bank - need + q * uint256(int256(stake) + r.ledger[h].net);
            }
            // A second-chance bust is the stop round in the band with a lost coin — and it zeroes.
            if (r.stop == CrapsOracle.SlipStop.Bust) {
                uint256 q = 1 << (r.ledger.length / craps.ESC_HANDS());
                if (q > 0xFFFF) q = 0xFFFF;
                if (bank * 2 >= q * stake) {
                    assertTrue(!_survivalCoin(seed, r.ledger.length, address(0)), "busted on a surviving coin");
                    assertEq(r.bankrollOut, 0, "a second-chance bust kept money");
                    ++busts;
                }
            }
        }

        emit log_named_uint("second-chance survives", survives);
        emit log_named_uint("second-chance busts   ", busts);
        assertGt(survives + busts, 40, "the second-chance band was never exercised");
        assertGt(busts, 0, "no run ever lost the coin");
        // Fair: each flip is an independent keccak-LSB coin, so survives and busts split evenly. A
        // generous band — this counts incidental flips, not a dedicated 10k-trial fairness rig.
        uint256 survivePct = (survives * 1000) / (survives + busts);
        assertApproxEqAbs(survivePct, 500, 200, "the second-chance coin looks shaded");
    }

    /// @dev A slip that reaches its hard hand bound is an ordinary bust, and its hands are the
    ///      table's own shooters: the same ledger any fixed session at the index shows.
    function test_slipSharesTheTablesShooters() public {
        Craps.Bets memory b;
        b.passLine = U;

        _setWord(4, uint256(keccak256("capslip")));

        CrapsOracle.SlipResult memory r = craps.resolveSlipAt(b, 4, uint256(UW) * 1000, 0, 10);
        assertTrue(r.stop == CrapsOracle.SlipStop.Bust, "hard bound should bust");
        assertEq(r.handsPlayed, 10, "hands at cap");

        CrapsOracle.Session memory sess = craps.resolveHandsAt(b, 4, 10);
        assertEq(r.totalRolls, sess.totalRolls, "different dice");
        for (uint256 h = 0; h < 10; ++h) {
            assertEq(r.ledger[h].net, sess.ledger[h].net, "slip hand diverged from the table");
        }
    }

    /// @dev The slip settles through the same lean path, one flip, same rounding — and pays what
    ///      the preview says, with the run's dice on the receipt.
    function test_slipSettlesLikeItPreviews() public {
        Craps.Bets memory b;
        b.passLine = 3;
        b.place6 = 2;
        b.place8 = 2;
        uint256 bankroll = uint256(PLAYED) * 10 * 1 ether;

        (uint256 betId, uint64 slot) = _run(alice, b, 10, 50, 4, uint256(keccak256("slipvrf")));

        (uint256 won, uint256 expected) = craps.previewSettlement(betId);
        assertEq(
            won,
            craps.resolveSlipForBet(craps.drawnBoardOf(betId), slot, bankroll, bankroll * 50, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player)
                .bankrollOut,
            "lean slip settlement != full view"
        );

        vm.recordLogs();
        craps.resolveSlot(slot, WHOLE_FIELD);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(coinflip.staked(alice), expected, "paid what it previewed");

        // The receipt carries the two figures a client would otherwise run the engine for, and
        // nothing else — the dice are replayable from the word, so they are not shipped.
        bytes32 sig = keccak256("CrapsBetSettled(uint256,address,uint256,uint256)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (uint256 eWon, uint256 ePaid) = abi.decode(logs[i].data, (uint256, uint256));
            assertEq(eWon, won, "receipt won != settled won");
            assertEq(ePaid, expected, "receipt paid != settled paid");
            return;
        }
        revert("no settlement event");
    }

    // ---------------------------------------------------------------------------------------
    // Rakeback
    // ---------------------------------------------------------------------------------------

    /// @dev Theo is the closed-form expected loss of the board, and the comp is a fixed slice of

    /// @dev The roll budget is what turns the slip's gas bound from a probability into a
    ///      guarantee: judged between shooters, so every hand still settles whole, and exhausting
    ///      it is an ordinary bust.
    function test_slipRollBudgetStopsBetweenShooters() public {
        Craps.Bets memory b;
        b.passLine = U;
        _setWord(4, uint256(keccak256("budget")));

        Craps.SlipResult memory r = craps.slipWithBudget(b, 4, uint256(UW) * 1000, 20, address(0));
        assertTrue(r.stop == Craps.SlipStop.Bust, "budget stop should bust");
        assertGe(r.totalRolls, 20, "stopped before the budget was consumed");
        assertLt(r.totalRolls, 20 + craps.MAX_ROLLS(), "a hand was cut mid-roll");
        assertLt(r.handsPlayed, 256, "the shooter cap should not have been the binding stop");
    }

    // ---------------------------------------------------------------------------------------
    // The escalator
    // ---------------------------------------------------------------------------------------

    /// @dev Every round wagers the mandatory multiple for its ordinal, and because payouts are
    ///      linear in stakes, round money is exactly q x the base hand. Reconstruct the whole money
    ///      path off the base ledger — q depends only on the hand index — and demand the engine's
    ///      bankroll match it to the wei.
    function test_escalatorCompoundsExactlyByTheLinearityRule() public {
        Craps.Bets memory b;
        b.passLine = L;

        bool sawDoubling;
        for (uint256 i = 0; i < 20; ++i) {
            uint48 idx = uint48(9000 + i);
            _setIndex(idx);
            _setWord(idx, uint256(keccak256(abi.encode("esc", i))));

            CrapsOracle.SlipResult memory r = craps.resolveSlipAt(b, idx, LW * 10, 0, 25);

            (uint256 bank, uint256 units) = _replaySlipBankroll(b, idx, r, address(0), 25);
            if (units > r.ledger.length) sawDoubling = true;
            assertEq(r.bankrollOut, bank, "bankroll != linearity replay");
            assertEq(r.unitsPlayed, units, "units != sum of mandatory multipliers");
        }
        assertTrue(sawDoubling, "no run ever reached the first doubling");
    }

    // ---------------------------------------------------------------------------------------
    // The settlement receipt
    // ---------------------------------------------------------------------------------------

    /// @dev The settlement event carries the whole shooter run — a byte per roll, 0x00 closing
    ///      each hand — recorded by the same loop that moved the money. The strongest check is a
    ///      round trip: decode hand one from the emitted bytes alone, replay it through the
    ///      scripted-dice entry point, and demand the same settlement the ledger shows.
    function test_theRunIsReplayableFromTheWordAlone() public {
        // The receipt ships no dice, so this is the property that has to hold instead: everything
        // about a run is derivable from its table's word, its slot and its owner — which is what
        // makes the lean event sufficient for an indexer.
        (uint256 betId, uint64 slot) = _run(alice, _bets(), 3, uint16(GOAL_FAR_MULT), 4, uint256(keccak256("logvrf")));
        uint256 bankroll = uint256(PLAYED) * 3 * 1 ether;

        (uint256 won,) = craps.previewSettlement(betId);

        // An independent engine, handed only the drawn board and the table seed, reproduces the
        // run exactly — hand for hand and roll for roll.
        CrapsOracle.SlipResult memory r =
            craps.resolveSlipForBet(craps.drawnBoardOf(betId), slot, bankroll, uint256(bankroll) * GOAL_FAR_MULT, craps.MAX_SLIP_HANDS(), craps.betOf(betId).player);
        assertEq(won, r.bankrollOut, "replay != settled won");
        assertGt(r.totalRolls, 0, "the replay rolled nothing");
        assertGt(r.handsPlayed, 0, "the replay played no hands");

        craps.resolveSlot(slot, WHOLE_FIELD);
        assertTrue(craps.betOf(betId).settled, "the slip did not settle");
    }

    // ---------------------------------------------------------------------------------------
    // The survival flip
    // ---------------------------------------------------------------------------------------

    /// @dev Settlement is permissionless and the batch is caller-composed, so if the flip were
    ///      keyed to a batch total a settler could enumerate partitions against an already-public
    ///      word and take the best split. Keyed to the table alone — nothing in the key is
    ///      caller-composed — every partition pays identically by construction.
    function test_howAFieldIsSplitCannotChangeWhatItPays() public {
        uint64 slot = _openBattle(craps, PLAYED, 2, uint16(GOAL_FAR_MULT), 0);
        uint256[] memory ids = new uint256[](6);
        for (uint256 i = 0; i < 6; ++i) {
            vm.prank(alice);
            ids[i] = craps.enterBattle(slot, _bets(), 1);
        }
        _closeOn(craps, slot, 4, uint256(keccak256("vrf")));

        uint256 total;
        for (uint256 i = 0; i < 6; ++i) {
            (, uint256 e) = craps.previewSettlement(ids[i]);
            total += e;
        }

        // Walk the field in three arbitrary batches. A settler chooses only how far to go, never
        // which entrants — the cursor fixes the order — but what freedom is left must move nothing.
        craps.resolveSeats(slot, 1);
        craps.resolveSeats(slot, 3);
        craps.resolveSeats(slot, 2);

        assertEq(coinflip.staked(alice), total, "a split field changed the payout");
        for (uint256 i = 0; i < 6; ++i) {
            assertTrue(craps.betOf(ids[i]).settled, "the walk missed a seat");
        }
    }

    /// @dev A goal is paid what its table returned, to the award-rounding granule; a bust is paid
    ///      zero and its remainder is deleted.
    function test_aGoalIsPaidAndABustIsDeleted() public {
        uint256 goal = uint256(PLAYED) * 4 * 5 * 1 ether;
        uint256 goalWonTotal;
        uint256 paidTotal;
        uint256 sawGoal;
        uint256 sawBust;

        for (uint256 i = 0; i < 200; ++i) {
            (uint256 betId,) =
                _run(alice, _bets(), 4, 5, uint48(1000 + i), uint256(keccak256(abi.encode("seed", i))));

            (uint256 won, uint256 paid) = craps.previewSettlement(betId);
            if (won >= goal) {
                // Award rounding moves a goal by at most one 100-FLIP granule in either direction.
                assertLe(paid, won + 100 ether, "paid more than the table returned");
                assertGe(paid + 100 ether, won, "goal paid below its rounding band");
                goalWonTotal += won;
                ++sawGoal;
            } else {
                assertEq(paid, 0, "a bust was paid its remainder");
                ++sawBust;
            }
            paidTotal += paid;
        }

        // Both ends of the run distribution have to turn up, or the band above proves nothing.
        assertGt(sawGoal, 0, "no run reached its goal");
        assertGt(sawBust, 0, "no run busted");
        // Across goals the rounding is even-handed; busted remainders are deleted, not paid, so
        // they are excluded from the comparison rather than being a shading of it.
        assertApproxEqRel(paidTotal, goalWonTotal, 0.02e18, "rounding is shaded, not neutral");
    }

    // ---------------------------------------------------------------------------------------
    // Rounding
    // ---------------------------------------------------------------------------------------

    /// @dev Degenerette's two-band policy, reproduced: the 100-FLIP granule only once it is a small
    ///      slice of the award, the whole-FLIP floor below it. Either way a player is never paid a
    ///      wei-scale residue.
    function test_awardsLandOnRoundFigures() public {
        uint256 checked;
        for (uint256 i = 0; i < 30; ++i) {
            (uint256 betId,) =
                _run(alice, _bets(), 4, 5, uint48(3000 + i), uint256(keccak256(abi.encode("r", i))));

            (, uint256 paid) = craps.previewSettlement(betId);
            if (paid == 0) continue;
            ++checked;

            if (paid > FlipRoundLib.FLIP_ROUND_THRESHOLD) {
                assertEq(paid % FlipRoundLib.FLIP_ROUND_UNIT, 0, "not a whole 100 FLIP");
            } else {
                assertEq(paid % 1 ether, 0, "not a whole FLIP");
            }
        }
        assertGt(checked, 0, "no paying tables to check");
    }

    // ---------------------------------------------------------------------------------------
    // Odds allowance
    // ---------------------------------------------------------------------------------------

    // ---------------------------------------------------------------------------------------
    // Shared table
    // ---------------------------------------------------------------------------------------

    /// @dev One index is one shooter, but not one board. Two slips from the SAME player with the
    ///      same stack are the same run down to the wei — the three chips the dice place are drawn
    ///      from the table's word and the OWNER, so nothing else can separate them. Two different
    ///      players at that table share the shooter and get their own three chips, which is the
    ///      whole point of keying the throw to the owner.
    function test_oneTableIsOneShooterButEveryPlayerTheirOwnBoard() public {
        uint64 slot = _openBattle(craps, PLAYED, 3, uint16(GOAL_FAR_MULT), 0);
        vm.startPrank(alice);
        uint256 a = craps.enterBattle(slot, _bets(), 1);
        uint256 twin = craps.enterBattle(slot, _bets(), 1);
        vm.stopPrank();
        vm.prank(bob);
        uint256 c = craps.enterBattle(slot, _bets(), 1);

        _closeOn(craps, slot, 4, uint256(keccak256("vrf")));

        (uint256 wonA, uint256 paidA) = craps.previewSettlement(a);
        (uint256 wonTwin, uint256 paidTwin) = craps.previewSettlement(twin);
        assertEq(wonA, wonTwin, "one player's identical slips diverged");
        assertEq(paidA, paidTwin, "identical wagers paid differently");
        assertEq(craps.betOf(a).chips, craps.betOf(c).chips, "same ticket, different chips");

        // The throw is keyed to the OWNER, so two players at one table draw different boards.
        assertTrue(
            keccak256(abi.encode(craps.drawnBoardOf(a))) != keccak256(abi.encode(craps.drawnBoardOf(c))),
            "two players at one table drew the same board"
        );
    }

    /// @dev And the reason it is ALSO salted by the owner. Two slips at one table share a shooter
    ///      by design — that is what makes it a craps table — but they must not share a BUST. On one
    ///      shared coin every seat that reached the same round lived or died together, so a table
    ///      either carried its whole field through the second-chance band or wiped it. Here the same
    ///      round on the same table is asked for two different owners across many tables, and the
    ///      answers must come up independent.
    function test_theOwnerSaltDecorrelatesTheFieldsSecondChances() public {
        uint256 agreed;
        uint256 trials = 120;

        for (uint256 i = 0; i < trials; ++i) {
            uint48 idx = uint48(6000 + i);
            _setWord(idx, uint256(keccak256(abi.encode("owner-salt", i))));
            // Same table, same round — the owner is the ONLY thing that moves.
            if (craps.survivedAt(idx, 7, alice) == craps.survivedAt(idx, 7, bob)) ++agreed;
        }

        // Independent coins agree about half the time. A table-wide coin agrees ALWAYS.
        assertLt(agreed, trials, "two owners never disagreed: the coin is not salted by owner");
        assertGt(agreed, 0, "suspiciously anti-correlated");
        assertGt(agreed, trials / 4, "agreement far below a fair coin");
        assertLt(agreed, (trials * 3) / 4, "agreement far above a fair coin");
    }

    /// @dev The other half of that: the salt moves the COIN and nothing else. A run that never
    ///      dips into the second-chance band is a pure function of the table, so two owners must
    ///      get the identical run — same dice, same length, same money. If the owner leaked into
    ///      the shooter, the field would stop watching one table.
    function test_theOwnerSaltLeavesTheSharedShooterAlone() public {
        Craps.Bets memory b;
        b.passLine = L;
        uint48 idx = 6500;
        _setIndex(idx);
        _setWord(idx, uint256(keccak256("shared-shooter")));

        // A bankroll deep enough that the escalator never puts a round inside the coin's band.
        // TWENTY-FOUR SHOOTERS, not sixty-four: the escalator doubles every THREE, so shooter 63
        // would want 2,097,152x the board and no bankroll this side of the field's ceiling covers
        // it. At 24 the deepest round is 128x against a 4,096x bankroll, and the worst case the
        // whole run can lose — 3 x (1 + 2 + ... + 128) = 765x — still leaves six times the last
        // round standing, so no shooter ever lands in the coin's band.
        uint256 deep = uint256(craps.stakeFor(b)) * 4096;
        CrapsOracle.SlipResult memory ra = craps.resolveSlipAtFor(b, idx, deep, 0, 24, alice);
        CrapsOracle.SlipResult memory rb = craps.resolveSlipAtFor(b, idx, deep, 0, 24, bob);

        assertEq(ra.handsPlayed, 24, "the fixture dipped into the coin's band");
        assertEq(ra.handsPlayed, rb.handsPlayed, "the two owners played different lengths");
        assertEq(ra.bankrollOut, rb.bankrollOut, "the two owners came home with different money");
        assertEq(keccak256(ra.rollLog), keccak256(rb.rollLog), "the shooter differed by owner");
    }

    /// @dev The reason the coin is salted by the exit round. A table's word is public the instant it
    ///      lands, so one shared coin let whoever settled first publish the answer for everyone
    ///      still holding a longer run. Here two bankrolls at ONE table run to different rounds, and
    ///      across many tables their coins must come up independent — a settled short run tells you
    ///      nothing about a long one. (Agreement on any single table is expected half the time; what
    ///      would indict the salt is agreement EVERY time, which is what one shared coin looked
    ///      like.)
    function test_theExitRoundSaltStopsAShortRunSpoilingALongOne() public {
        Craps.Bets memory b;
        b.passLine = L;

        uint256 differingLengths;
        uint256 coinsAgreed;

        for (uint256 i = 0; i < 60; ++i) {
            uint48 idx = uint48(5000 + i);
            _setIndex(idx);
            _setWord(idx, uint256(keccak256(abi.encode("salt", i))));

            uint256 shortHands = craps.resolveSlipAt(b, idx, LW, 0, craps.MAX_SLIP_HANDS()).handsPlayed;
            uint256 longHands = craps.resolveSlipAt(b, idx, LW * 10, 0, craps.MAX_SLIP_HANDS()).handsPlayed;
            if (shortHands == longHands) continue; // same length, same coin by design
            ++differingLengths;

            if (craps.survivedAt(idx, shortHands, alice) == craps.survivedAt(idx, longHands, alice)) {
                ++coinsAgreed;
            }
        }

        assertGt(differingLengths, 20, "not enough tables where the two runs differed in length");
        // Independent coins land together about half the time. A shared coin lands together ALWAYS.
        assertLt(coinsAgreed, differingLengths, "the two lengths never disagreed: coin not salted");
        assertGt(coinsAgreed, 0, "suspiciously anti-correlated");
    }

    /// @dev Loss is bounded by the burn and nothing else: whatever the dice do, FLIP only ever
    ///      leaves a player's balance once, at placement.
    function testFuzz_theBankrollIsTheWholeExposure(uint256 seed, uint32 rawPlayed, uint8 rawRounds) public {
        // The round is ten whole chips, and the bankroll a whole number of rounds of it. Both
        // bands are the slot's, proven once at creation for the whole field.
        // At least a 300-FLIP round, so the bankroll clears the floor at any depth.
        uint32 played = uint32(bound(uint256(rawPlayed), 30, 1_500_000) * 10);
        uint8 rounds = uint8(bound(uint256(rawRounds), 1, craps.MAX_BANKROLL_MULT()));
        uint256 bankroll = uint256(played) * rounds * 1 ether;

        uint48 idx = uint48(bound(seed, 1, type(uint32).max));
        uint64 slot = _openBattle(craps, played, rounds, uint16(GOAL_FAR_MULT), 0);
        vm.prank(alice);
        craps.enterBattle(slot, _bets(), 1);
        assertEq(flip.burned(alice), bankroll, "burned exactly the bankroll");

        _closeOn(craps, slot, idx, uint256(keccak256(abi.encode(seed))));
        craps.resolveSlot(slot, WHOLE_FIELD);

        // Settlement credits; it never burns again. The placement burn is the entire cost.
        assertEq(flip.burned(alice), bankroll, "settlement reached back into the wallet");
    }
}
