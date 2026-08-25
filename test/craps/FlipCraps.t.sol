// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsOracle} from "./CrapsOracle.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {FlipCraps, IFlipCoin, ICoinflipStake} from "../../contracts/FlipCraps.sol";
import {FlipRoundLib} from "../../contracts/libraries/FlipRoundLib.sol";

/// @dev Points the three pins (game slots, FLIP) at doubles. Overrides nothing else, so every rule
///      under test is the shipped one.
contract FlipCrapsHarness is FlipCraps {

    /// @dev The suite's oracle. `resolveSlipAt` / `resolveHandsAt` and the scripted-dice replay
    ///      were cut from production — they cost this contract its EIP-170 headroom and settlement
    ///      never called one. They are rebuilt here over the SHIPPED `seedFor`, so the assertions
    ///      below still compare production's lean settlement against an independent engine off the
    ///      identical seed. That comparison is the point: it is what makes these tests statements
    ///      about `FlipCraps` rather than about a fixture.
    CrapsOracle internal immutable oracle;

    constructor() {
        oracle = new CrapsOracle();
    }

    function resolveSlipAt(
        Craps.Bets calldata b,
        uint48 index,
        uint256 bankroll,
        uint256 goal,
        uint256 cap
    ) external view returns (CrapsOracle.SlipResult memory) {
        return oracle.resolveSlip(b, seedFor(index), bankroll, goal, cap);
    }

    function resolveHandsAt(Craps.Bets calldata b, uint48 index, uint256 hands)
        external
        view
        returns (CrapsOracle.Session memory)
    {
        return oracle.resolveHands(b, seedFor(index), hands);
    }

    function resolveHandWithScriptedDice(
        Craps.Bets calldata b,
        uint8[] calldata dice,
        bytes32 seed
    ) external view returns (CrapsOracle.Outcome memory) {
        return oracle.resolveHandWithScriptedDice(b, dice, seed);
    }







    /// @dev `bankrollGoalFor` went internal — external users get the real answer from
    ///      `previewSettlement`, and the conversion is one shift. The suite still pins the
    ///      rounding rule, so the SHIPPED function is re-exposed here.
    function bankrollGoalForX(uint256 payoutGoal) external pure returns (uint256) {
        return bankrollGoalFor(payoutGoal);
    }

    /// @dev `survivedAt` was cut from production: `previewSettlement` returns `survived` and
    ///      `CrapsBetSettled` emits it, so nothing on the paying path needed a standalone view.
    ///      The suite still interrogates the coin for (index, handsPlayed) pairs no bet holds —
    ///      that is how the exit-round salt is proven — so it reaches the SHIPPED `_survived`
    ///      through the harness rather than keeping an unused external on the table.
    function survivedAt(uint48 index, uint256 handsPlayed) external view returns (bool) {
        return _survived(seedFor(index), handsPlayed);
    }

    /// @dev Test tap into the slip engine with a caller-chosen roll budget — organically
    ///      unreachable through the production constant, so the stop logic is proven here. Drives
    ///      the shipped settlement engine, which takes the budget as a parameter of its own.
    function slipWithBudget(Craps.Bets calldata b, uint48 index, uint256 bankroll, uint256 budget)
        external
        view
        returns (Craps.SlipResult memory)
    {
        return _settleSlip(b, seedFor(index), bankroll, 0, 256, budget);
    }
}

/// @title FlipCraps suite
/// @notice The resolver and the RNG binding are covered elsewhere. This is about the money: that a
///         stake is burned exactly once and bounds the loss, that the survival flip is one
///         table-level coin no batch composition can move, and that the award lands where
///         Degenerette's two-band rounding policy puts it.
contract FlipCrapsTest is CrapsPins {
    FlipCrapsHarness internal craps;

    /// @dev Three of these make exactly the 600-FLIP table minimum, so `_bets()` is the smallest
    ///      legal three-leg board; `L` is the minimum carried on a single leg.
    uint24 internal constant U = 200;
    uint128 internal constant UW = 200e18;
    uint24 internal constant L = 600;
    uint128 internal constant LW = 600e18;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal settler = makeAddr("settler");


    function setUp() public {
        _installPins();
        craps = new FlipCrapsHarness();
        _setIndex(4);
    }


    function _bets() internal pure returns (Craps.Bets memory b) {
        b.passLine = U;
        b.place6 = U;
        b.hard8 = U;
    }

    function _ids(uint64 a) internal pure returns (uint64[] memory out) {
        out = new uint64[](1);
        out[0] = a;
    }

    /// @dev The table's survival coin, recomputed independently of the engine — an indexer or a
    ///      client replay hardcodes this tag ("Survival") and the seed. The engine rides the same
    ///      coin both mid-run (as a second chance) and at the end. Mirrors `Craps._survived`.
    uint256 internal constant _SURVIVAL_TAG = 0x537572766976616c; // "Survival"

    function _survivalCoin(bytes32 seed, uint256 n) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(_SURVIVAL_TAG, seed, n))) & 1 == 1;
    }

    /// @dev Reconstruct a slip's final bankroll from scratch: walk the base-board ledger, applying
    ///      the escalator multiple AND the deterministic second-chance coin exactly where the engine
    ///      would, so this is a real check on the money path rather than a copy of the engine's own
    ///      scalar. A played hand below the round's stake proves its second-chance coin survived; the
    ///      stop round splits a hard bust (remainder kept) from a second-chance bust (bankroll zeroed).
    function _replaySlipBankroll(Craps.Bets memory b, uint48 idx, CrapsOracle.SlipResult memory r)
        internal
        view
        returns (uint256 bank, uint256 units)
    {
        uint256 stake = craps.stakeFor(b);
        bytes32 seed = craps.seedFor(idx);
        bank = r.bankrollIn;
        for (uint256 h = 0; h < r.ledger.length; ++h) {
            uint256 q = 1 << (h / craps.ESC_HANDS());
            if (q > 0xFFFF) q = 0xFFFF;
            uint256 need = q * stake;
            if (bank < need) {
                assertGe(bank * 2, need, "played a hand below the second-chance floor");
                assertTrue(_survivalCoin(seed, h), "played on a losing second-chance coin");
                bank += bank;
            }
            units += q;
            bank = bank - need + q * uint256(int256(stake) + r.ledger[h].net);
        }
        if (r.stop == CrapsOracle.SlipStop.Bust) {
            uint256 q = 1 << (r.ledger.length / craps.ESC_HANDS());
            if (q > 0xFFFF) q = 0xFFFF;
            if (bank * 2 >= q * stake) {
                // Not a hard bust — the run was in the second-chance band and the coin lost.
                assertTrue(!_survivalCoin(seed, r.ledger.length), "busted on a surviving coin");
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
        Craps.Bets memory b = _bets();

        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW * 5, 0);

        assertEq(flip.burned(alice), uint256(LW) * 5, "burned the bankroll");
        assertEq(betId, 1, "first bet id");

        FlipCraps.Bet memory bet = craps.betOf(betId);
        assertEq(bet.player, alice, "owner");
        assertEq(bet.index, 4, "bound to the live table");
        assertEq(bet.staked, uint256(LW) * 5, "staked");
        assertFalse(bet.settled, "settled");
    }

    /// @dev The protocol advances the index in the same call that requests its word, so the live
    ///      index should be empty. Placement checks that invariant itself before taking funds.
    function test_placementBindsToTheLiveIndex() public {
        Craps.Bets memory b = _bets();
        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW, 0);

        assertEq(craps.betOf(betId).index, craps.currentIndex(), "bound off the live index");
        assertEq(craps.wordAt(craps.currentIndex()), 0, "the live index carried a word");
    }


    function test_rejectsBoardsUnderTheTableMinimum() public {
        Craps.Bets memory nothing;
        vm.expectRevert(FlipCraps.BelowTableMinimum.selector);
        craps.placeSlip(nothing, LW, 0);

        Craps.Bets memory under;
        under.passLine = 599; // one FLIP short of the table minimum
        vm.expectRevert(FlipCraps.BelowTableMinimum.selector);
        craps.placeSlip(under, LW, 0);

        Craps.Bets memory exact;
        exact.passLine = 600;
        vm.prank(alice);
        craps.placeSlip(exact, LW, 0);
    }

    /// @dev The indexer's contract with this game: `CrapsSlipPlaced` must carry everything needed
    ///      to rebuild a slip with no follow-up call, so an event-derived indexer never has to
    ///      reach for `betOf`. Decode the packed config exactly as an off-chain consumer would and
    ///      demand every field back — a decoder that shifts by the wrong amount would otherwise
    ///      fail silently and mis-price every historical bet.
    function test_placementEventCarriesTheWholeBoardAndRate() public {
        // Distinct values per leg, so a transposed or mis-shifted field cannot coincidentally pass.
        Craps.Bets memory b;
        b.passLine = 100;
        b.place4 = 110;
        b.place5 = 120;
        b.place6 = 130;
        b.place8 = 140;
        b.place9 = 150;
        b.place10 = 160;
        b.hard4 = 170;
        b.hard8 = 180;
        b.passOddsMult = 7;
        game.setScore(alice, 400); // 50% — a non-zero rate, so the high bits are pinned too

        // Hoisted: an inline `craps.stakeFor(b)` would be the call the prank lands on, and the
        // placement would run as the test contract with a zero score.
        uint128 bankroll = uint128(craps.stakeFor(b) * 3);

        vm.recordLogs();
        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, bankroll, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 sig = keccak256("CrapsSlipPlaced(uint64,address,uint48,uint256,uint256,uint256)");
        uint256 config;
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (,, config) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            found = true;
        }
        assertTrue(found, "no placement event");

        assertEq(uint24(config), b.passLine, "passLine");
        assertEq(uint24(config >> 24), b.place4, "place4");
        assertEq(uint24(config >> 48), b.place5, "place5");
        assertEq(uint24(config >> 72), b.place6, "place6");
        assertEq(uint24(config >> 96), b.place8, "place8");
        assertEq(uint24(config >> 120), b.place9, "place9");
        assertEq(uint24(config >> 144), b.place10, "place10");
        assertEq(uint24(config >> 168), b.hard4, "hard4");
        assertEq(uint24(config >> 192), b.hard8, "hard8");
        assertEq(uint16(config >> 216), b.passOddsMult, "passOddsMult");
        assertEq(uint16(config >> 232), craps.betOf(betId).rakeBps, "rakeBps != the locked rate");
        assertEq(config >> 248, 0, "the spare byte is dirty");
    }

    // ---------------------------------------------------------------------------------------
    // Settling
    // ---------------------------------------------------------------------------------------

    function test_cannotSettleBeforeTheTableRolls() public {
        vm.prank(alice);
        uint64 betId = craps.placeSlip(_bets(), LW * 3, 0);

        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        craps.resolveBets(_ids(betId));
    }

    function test_settlesOnceAndOnlyOnce() public {
        vm.prank(alice);
        uint64 betId = craps.placeSlip(_bets(), LW * 3, 0);
        _setWord(4, uint256(keccak256("vrf")));

        craps.resolveBets(_ids(betId));
        assertTrue(craps.betOf(betId).settled, "settled");

        vm.expectRevert(FlipCraps.AlreadySettled.selector);
        craps.resolveBets(_ids(betId));
    }

    /// @dev Settlement is permissionless because it can only ever pay the bet's owner. A stranger
    ///      settling someone else's bet must move the money to that someone else.
    function test_anyoneMaySettleButOnlyTheOwnerIsPaid() public {
        // Search for a table that actually pays, so the assertion is about who gets the money
        // rather than about a bet that happened to lose its survival flip.
        for (uint256 i = 0; i < 40; ++i) {
            _setIndex(uint48(4000 + i));
            vm.prank(alice);
            uint64 betId = craps.placeSlip(_bets(), LW * 4, 0);
            _setWord(uint48(4000 + i), uint256(keccak256(abi.encode("pay", i))));

            (,, uint256 expected) = craps.previewSettlement(betId);
            if (expected == 0) continue;

            vm.prank(settler);
            craps.resolveBets(_ids(betId));

            assertEq(flip.minted(alice), expected, "owner paid");
            assertEq(flip.minted(settler), 0, "settler paid nothing");
            return;
        }
        revert("no paying table found");
    }

    /// @dev The preview and the payer share one computation, so they cannot disagree about what a
    ///      bet is worth. This is the assertion that keeps them shared.
    function test_previewIsExactlyWhatSettlementPays() public {
        for (uint256 i = 0; i < 12; ++i) {
            _setIndex(uint48(100 + i));
            vm.prank(alice);
            uint64 betId = craps.placeSlip(_bets(), LW * 3, 0);
            _setWord(uint48(100 + i), uint256(keccak256(abi.encode("w", i))));

            (uint256 won,, uint256 expected) = craps.previewSettlement(betId);
            uint256 before = flip.minted(alice);
            craps.resolveBets(_ids(betId));
            assertEq(flip.minted(alice) - before, expected, "preview != paid");
            // The paying path runs lean (no per-leg books); the public view runs full. Pin them.
            assertEq(
                won,
                craps.resolveSlipAt(
                    _bets(), uint48(100 + i), LW * 3, 0, craps.MAX_SLIP_HANDS()).bankrollOut,
                "lean settlement != full-fidelity view"
            );
        }
    }

    function test_sideOnlySettlementMatchesFullResolver() public {
        Craps.Bets memory b;
        b.place6 = L;
        b.hard8 = L;
        uint256 stake = craps.stakeFor(b);

        for (uint256 i = 0; i < 12; ++i) {
            uint48 idx = uint48(500 + i);
            _setIndex(idx);
            vm.prank(alice);
            uint64 betId = craps.placeSlip(b, uint128(stake * 5), 0);
            _setWord(idx, uint256(keccak256(abi.encode("side", i))));

            (uint256 won,,) = craps.previewSettlement(betId);
            assertEq(
                won,
                craps.resolveSlipAt(b, idx, stake * 5, 0, craps.MAX_SLIP_HANDS()).bankrollOut,
                "side-only lean settlement != full resolver"
            );
        }
    }

    function test_maxOddsSettlementMatchesFullResolver() public {
        game.setScore(alice, 2000);
        Craps.Bets memory b;
        b.passLine = L;
        b.passOddsMult = 1000;
        uint256 stake = craps.stakeFor(b);

        for (uint256 i = 0; i < 8; ++i) {
            uint48 idx = uint48(700 + i);
            _setIndex(idx);
            vm.prank(alice);
            uint64 betId = craps.placeSlip(b, uint128(stake * 2), 0);
            _setWord(idx, uint256(keccak256(abi.encode("max-odds", i))));

            (uint256 won,,) = craps.previewSettlement(betId);
            assertEq(
                won,
                craps.resolveSlipAt(b, idx, stake * 2, 0, craps.MAX_SLIP_HANDS()).bankrollOut,
                "max-odds lean settlement != full resolver"
            );
        }
    }

    // ---------------------------------------------------------------------------------------
    // The bet slip
    // ---------------------------------------------------------------------------------------

    function test_slipValidatesAndBurnsTheBankroll() public {
        Craps.Bets memory b;
        b.passLine = L;

        vm.expectRevert(FlipCraps.BankrollBelowStake.selector);
        craps.placeSlip(b, LW - 1, 0);

        vm.expectRevert(FlipCraps.BankrollAboveMax.selector);
        craps.placeSlip(b, LW * 10 + 1, 0); // one wei past ten rounds of the board

        vm.expectRevert(FlipCraps.BadGoal.selector);
        craps.placeSlip(b, LW * 4, LW * 8); // surviving now already reaches this payout goal

        vm.expectRevert(FlipCraps.BadGoal.selector);
        craps.placeSlip(b, LW * 4, LW * 4 * 1000 + 1); // beyond the goal-multiplier cap

        assertEq(craps.bankrollGoalForX(0), 0, "zero means no goal");
        assertEq(craps.bankrollGoalForX(11), 6, "half-goal rounds up");

        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW * 4, LW * 40);
        assertEq(flip.burned(alice), uint256(LW) * 4, "burned the bankroll");

        FlipCraps.Bet memory bet = craps.betOf(betId);
        assertEq(bet.staked, uint256(LW) * 4, "bankroll");
        assertEq(bet.goal, uint256(LW) * 40, "goal");
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

            CrapsOracle.SlipResult memory r =
                craps.resolveSlipAt(b, idx, UW * 3, UW * 6, craps.MAX_SLIP_HANDS());

            assertEq(r.ledger.length, r.handsPlayed, "ledger trimmed to hands played");
            (uint256 bank, uint256 units) = _replaySlipBankroll(b, idx, r);
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

            CrapsOracle.SlipResult memory r =
                craps.resolveSlipAt(b, idx, UW * 2, 0, craps.MAX_SLIP_HANDS());
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
                    assertTrue(_survivalCoin(seed, h), "played on a lost coin");
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
                    assertTrue(!_survivalCoin(seed, r.ledger.length), "busted on a surviving coin");
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

    /// @dev A slip that can neither bust nor reach a goal runs to the cap — and its hands are the
    ///      table's own shooters: the same ledger any fixed session at the index shows.
    function test_slipSharesTheTablesShooters() public {
        Craps.Bets memory b;
        b.passLine = U;

        _setWord(4, uint256(keccak256("capslip")));

        CrapsOracle.SlipResult memory r = craps.resolveSlipAt(b, 4, uint256(UW) * 1000, 0, 10);
        assertTrue(r.stop == CrapsOracle.SlipStop.Cap, "should have hit the cap");
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
        b.passLine = U;
        b.place6 = U;
        b.place8 = U;

        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW * 10, LW * 40);
        _setWord(4, uint256(keccak256("slipvrf")));

        (uint256 won,, uint256 expected) = craps.previewSettlement(betId);
        assertEq(
            won,
            craps.resolveSlipAt(
                b,
                4,
                LW * 10,
                craps.bankrollGoalForX(LW * 40),
                craps.MAX_SLIP_HANDS()).bankrollOut,
            "lean slip settlement != full view"
        );

        vm.recordLogs();
        craps.resolveBets(_ids(betId));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(flip.minted(alice), expected, "paid what it previewed");

        bytes32 sig = keccak256("CrapsBetSettled(uint64,address,uint256,uint256,bool,uint256,bytes)");
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (,,,, bytes memory rolls) = abi.decode(logs[i].data, (uint256, uint256, bool, uint256, bytes));
            uint256 terminators;
            for (uint256 k = 0; k < rolls.length; ++k) {
                if (uint8(rolls[k]) == 0) ++terminators;
            }
            assertEq(
                terminators,
                craps.resolveSlipAt(b, 4, LW * 10, LW * 20, craps.MAX_SLIP_HANDS()).handsPlayed,
                "receipt hands != played hands"
            );
            return;
        }
        revert("no settlement event");
    }

    // ---------------------------------------------------------------------------------------
    // Rakeback
    // ---------------------------------------------------------------------------------------

    /// @dev Theo is the closed-form expected loss of the board, and the comp is a fixed slice of
    ///      it. Pin the closed forms exactly.
    function test_theoMatchesTheClosedForms() public view {
        Craps.Bets memory b;
        b.passLine = U;
        b.place4 = U;
        b.place5 = U;
        b.place6 = U;
        b.place8 = U;
        b.place9 = U;
        b.place10 = U;
        b.hard4 = U;
        b.hard8 = U;
        b.passOddsMult = 1000; // odds are zero-edge: they must contribute NOTHING to theo

        uint256 expected = (uint256(UW) * 7) / 251
            + uint256(UW) / 10 + uint256(UW) / 15 + uint256(UW) / 36 + uint256(UW) / 36
            + uint256(UW) / 15 + uint256(UW) / 10 + uint256(UW) / 8 + uint256(UW) / 10;
        assertEq(craps.theoFor(b), expected, "theo");
    }

    /// @dev The rate ladder: nothing at score zero, 25% at 100, 50% at 400, 75% at 1,000, flat
    ///      above, continuous at every knee.
    function test_rakebackRateScalesWithScore() public {
        assertEq(craps.rakeBpsFor(alice), 0, "no play, no comp");
        game.setScore(alice, 50);
        assertEq(craps.rakeBpsFor(alice), 1250, "halfway to the first knee");
        game.setScore(alice, 100);
        assertEq(craps.rakeBpsFor(alice), 2500, "25% knee");
        game.setScore(alice, 250);
        assertEq(craps.rakeBpsFor(alice), 3750, "between 25% and 50%");
        game.setScore(alice, 400);
        assertEq(craps.rakeBpsFor(alice), 5000, "50% knee");
        game.setScore(alice, 700);
        assertEq(craps.rakeBpsFor(alice), 6250, "between 50% and 75%");
        game.setScore(alice, 1000);
        assertEq(craps.rakeBpsFor(alice), 7500, "75% ceiling");
        game.setScore(alice, 65_534);
        assertEq(craps.rakeBpsFor(alice), 7500, "flat above the ceiling");
    }

    /// @dev Every settlement comps immediately and in full through the no-minimum crediting lane:
    ///      no accrual, no threshold, no FLIP minted to anyone.
    function test_rakebackCreditsEverySettlementInFull() public {
        game.setScore(alice, 100); // 25% of theo
        Craps.Bets memory b;
        b.passLine = 1000;

        uint256 theo = craps.theoFor(b);

        vm.prank(alice);
        uint64 first = craps.placeSlip(b, uint128(1000e18) * 10, 0);
        _setWord(4, uint256(keccak256("rake1")));
        uint256 units1 = craps.resolveSlipAt(
            b, 4, uint256(1000e18) * 10, 0, craps.MAX_SLIP_HANDS()).unitsPlayed;
        craps.resolveBets(_ids(first));

        // Floors exactly as the contract does: bps of the whole settlement's theo.
        uint256 rake1 = (theo * units1 * 2500) / 10_000;
        assertEq(coinflip.staked(alice), rake1, "first settlement comped in full");
        assertEq(coinflip.credits(), 1, "one credit per settlement");

        _setIndex(5);
        vm.prank(alice);
        uint64 second = craps.placeSlip(b, uint128(1000e18) * 10, 0);
        _setWord(5, uint256(keccak256("rake2")));
        uint256 units2 = craps.resolveSlipAt(
            b, 5, uint256(1000e18) * 10, 0, craps.MAX_SLIP_HANDS()).unitsPlayed;
        craps.resolveBets(_ids(second));

        uint256 rake2 = (theo * units2 * 2500) / 10_000;
        assertEq(coinflip.staked(alice), rake1 + rake2, "second settlement comped in full");
        assertEq(flip.minted(address(craps)), 0, "the comp mints nothing to the table");

        // A zero-score player gets nothing, and no credit call is wasted on them.
        _setIndex(6);
        vm.prank(bob);
        uint64 third = craps.placeSlip(b, uint128(1000e18) * 10, 0);
        _setWord(6, uint256(keccak256("rake3")));
        craps.resolveBets(_ids(third));
        assertEq(coinflip.staked(bob), 0, "no play, no comp");
        assertEq(coinflip.credits(), 2, "zero rake makes no credit call");
    }

    /// @dev The rate is LOCKED at placement: pumping (or losing) score afterwards moves nothing.
    function test_rakebackRateIsLockedAtPlacement() public {
        game.setScore(alice, 100); // 25%
        Craps.Bets memory b;
        b.passLine = 1000;

        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, uint128(1000e18) * 10, 0);
        assertEq(craps.betOf(betId).rakeBps, 2500, "locked rate");

        game.setScore(alice, 65_534); // now worth 75% — but not for the bet already down
        _setWord(4, uint256(keccak256("lockrake")));
        uint256 units = craps.resolveSlipAt(
            b, 4, uint256(1000e18) * 10, 0, craps.MAX_SLIP_HANDS()).unitsPlayed;
        craps.resolveBets(_ids(betId));

        assertEq(
            coinflip.staked(alice),
            (craps.theoFor(b) * units * 2500) / 10_000,
            "comp used a rate other than the placement lock"
        );
    }

    /// @dev The roll budget is what turns the slip's gas bound from a probability into a
    ///      guarantee: judged between shooters, so every hand still settles whole, and the run
    ///      stops as Cap with the bankroll intact.
    function test_slipRollBudgetStopsBetweenShooters() public {
        Craps.Bets memory b;
        b.passLine = U;
        _setWord(4, uint256(keccak256("budget")));

        Craps.SlipResult memory r = craps.slipWithBudget(b, 4, uint256(UW) * 1000, 20);
        assertTrue(r.stop == Craps.SlipStop.Cap, "budget stop reports as Cap");
        assertGe(r.totalRolls, 20, "stopped before the budget was consumed");
        assertLt(r.totalRolls, 20 + craps.MAX_ROLLS(), "a hand was cut mid-roll");
        assertLt(r.handsPlayed, 256, "the shooter cap should not have been the binding stop");
    }

    /// @dev The comp follows theo, not results — and for a slip, theo counts the units the
    ///      bankroll actually wagered (the escalator included), not a hand count nobody played.
    function test_slipRakebackCountsUnitsActuallyWagered() public {
        game.setScore(alice, 100); // 25% of theo
        Craps.Bets memory b;
        b.passLine = L;

        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW * 3, LW * 12);
        _setWord(4, uint256(keccak256("sliprake")));

        uint256 units =
            craps.resolveSlipAt(
                b,
                4,
                LW * 3,
                craps.bankrollGoalForX(LW * 12),
                craps.MAX_SLIP_HANDS()).unitsPlayed;
        craps.resolveBets(_ids(betId));

        assertEq(
            coinflip.staked(alice),
            (craps.theoFor(b) * units * 2500) / 10_000,
            "slip theo != units actually wagered"
        );
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

            (uint256 bank, uint256 units) = _replaySlipBankroll(b, idx, r);
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
    function test_settlementEmitsTheShooterRun() public {
        Craps.Bets memory b = _bets();
        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, LW * 3, 0);
        _setWord(4, uint256(keccak256("logvrf")));

        vm.recordLogs();
        craps.resolveBets(_ids(betId));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 sig = keccak256("CrapsBetSettled(uint64,address,uint256,uint256,bool,uint256,bytes)");
        bytes memory rolls;
        uint256 won;
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;
            (, won,,, rolls) = abi.decode(logs[i].data, (uint256, uint256, bool, uint256, bytes));
            found = true;
        }
        assertTrue(found, "no settlement event");

        CrapsOracle.SlipResult memory r =
            craps.resolveSlipAt(b, 4, LW * 3, 0, craps.MAX_SLIP_HANDS());

        // Structure: exactly one 0x00 per hand, and every roll byte is a pair of real dice.
        uint256 terminators;
        uint256 rollCount;
        for (uint256 i = 0; i < rolls.length; ++i) {
            uint8 v = uint8(rolls[i]);
            if (v == 0) {
                ++terminators;
                continue;
            }
            assertGe(v >> 4, 1, "die 1 low");
            assertLe(v >> 4, 6, "die 1 high");
            assertGe(v & 0x0f, 1, "die 2 low");
            assertLe(v & 0x0f, 6, "die 2 high");
            ++rollCount;
        }
        assertEq(terminators, r.handsPlayed, "hand terminators");
        assertEq(rollCount, r.totalRolls, "emitted rolls != rolled rolls");
        assertEq(won, r.bankrollOut, "emitted won != final bankroll");

        // Round trip hand one.
        uint256 end;
        while (uint8(rolls[end]) != 0) {
            ++end;
        }
        uint8[] memory dice = new uint8[](end * 2);
        for (uint256 i = 0; i < end; ++i) {
            dice[2 * i] = uint8(rolls[i]) >> 4;
            dice[2 * i + 1] = uint8(rolls[i]) & 0x0f;
        }
        CrapsOracle.Outcome memory replay = craps.resolveHandWithScriptedDice(b, dice, bytes32(0));
        assertEq(replay.rolls, end, "replayed hand length");
        assertEq(replay.net, r.ledger[0].net, "replayed money != settled money");
    }

    // ---------------------------------------------------------------------------------------
    // The survival flip
    // ---------------------------------------------------------------------------------------

    /// @dev Settlement is permissionless and the batch is caller-composed, so if the flip were
    ///      keyed to a batch total a settler could enumerate partitions against an already-public
    ///      word and take the best split. Keyed to the table alone — nothing in the key is
    ///      caller-composed — every partition pays identically by construction.
    function test_batchingCannotChangeWhatABetPays() public {
        uint64[] memory ids = new uint64[](6);
        for (uint256 i = 0; i < 6; ++i) {
            vm.prank(alice);
            ids[i] = craps.placeSlip(_bets(), LW * 2, 0);
        }
        _setWord(4, uint256(keccak256("vrf")));

        uint256[] memory expected = new uint256[](6);
        uint256 total;
        for (uint256 i = 0; i < 6; ++i) {
            (,, expected[i]) = craps.previewSettlement(ids[i]);
            total += expected[i];
        }

        // Settle them in three arbitrary partitions: one whole batch would have been the settler's
        // choice too, and none of the choices may matter.
        uint64[] memory first = new uint64[](1);
        first[0] = ids[0];
        uint64[] memory middle = new uint64[](3);
        middle[0] = ids[3];
        middle[1] = ids[1];
        middle[2] = ids[4];
        uint64[] memory rest = new uint64[](2);
        rest[0] = ids[5];
        rest[1] = ids[2];

        craps.resolveBets(first);
        craps.resolveBets(middle);
        craps.resolveBets(rest);

        assertEq(flip.minted(alice), total, "a partition changed the payout");
    }

    /// @dev Double-or-nothing at even money is EV-neutral, which is the point: it moves variance
    ///      and leaves the game's edge alone. A run that came home with something flips once, and
    ///      roughly half of those survive and are paid double; a busted run never flips.
    function test_survivalFlipIsEvNeutral() public {
        uint256 n = 400;
        uint256 survivors;
        uint256 payers;
        uint256 wonTotal;
        uint256 paidTotal;

        for (uint256 i = 0; i < n; ++i) {
            _setIndex(uint48(1000 + i));
            vm.prank(alice);
            uint64 betId = craps.placeSlip(_bets(), LW, 0);
            _setWord(uint48(1000 + i), uint256(keccak256(abi.encode("seed", i))));

            (uint256 won, bool survived, uint256 paid) = craps.previewSettlement(betId);
            // A busted run does not flip — won == 0 is definitionally not survived — so the fair
            // coin lives on the runs that came home with something.
            if (won != 0) {
                ++payers;
                if (survived) ++survivors;
            }
            wonTotal += won;
            paidTotal += paid;
        }

        // One flip per paying table, a fair coin: survivors sit on half of them.
        assertApproxEqAbs(survivors * 2, payers, payers / 4 + 20, "survival rate is not a fair coin");

        // Survivors pay double, so the paid total tracks the won total. Rounding only ever
        // truncates, so paid must not exceed 2x won.
        assertLe(paidTotal, wonTotal * 2, "paid more than double the wins");
        assertApproxEqRel(paidTotal, wonTotal, 0.25e18, "paid total drifted from the wins");
    }

    /// @dev The survived flag is a fact about the table AND the round the run ended on: for a run
    ///      that came home with something it must agree with `survivedAt(index, handsPlayed)`; a run
    ///      that returned nothing busted, so it is "not survived" and pays nothing — it never flips,
    ///      which is what keeps a busted run from re-using the second-chance coin that busted it.
    function test_survivedFlagIsTheTableAndExitRoundFlip() public {
        Craps.Bets memory b;
        b.passLine = L;

        bool sawZero;
        bool sawPaid;
        for (uint256 i = 0; i < 40; ++i) {
            uint48 idx = uint48(2000 + i);
            _setIndex(idx);
            vm.prank(alice);
            uint64 betId = craps.placeSlip(b, LW, 0);
            _setWord(idx, uint256(keccak256(abi.encode("z", i))));

            uint256 hands =
                craps.resolveSlipAt(b, idx, LW, 0, craps.MAX_SLIP_HANDS()).handsPlayed;
            (uint256 won, bool survived, uint256 paid) = craps.previewSettlement(betId);
            // A paying run's flag is the coin at its exit round; a busted run never flips.
            assertEq(survived, won != 0 && craps.survivedAt(idx, hands), "flag disagrees with the coin");
            if (won == 0) {
                assertFalse(survived, "a busted run must not survive");
                assertEq(paid, 0, "paid on a zero return");
                sawZero = true;
            } else if (survived) {
                sawPaid = true;
            }
        }
        assertTrue(sawZero, "no losing table found");
        assertTrue(sawPaid, "no surviving paid table found");
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
            _setIndex(uint48(3000 + i));
            vm.prank(alice);
            uint64 betId = craps.placeSlip(_bets(), LW * 4, 0);
            _setWord(uint48(3000 + i), uint256(keccak256(abi.encode("r", i))));

            (,, uint256 paid) = craps.previewSettlement(betId);
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

    /// @dev Two linear segments: 3x for anyone to 100x at 400 points, then on to 1000x at 2,000,
    ///      flat above. Continuous at both knees.
    function test_oddsAllowanceLadder() public {
        assertEq(craps.maxOddsFor(alice), 3, "base");

        game.setScore(alice, 200);
        assertEq(craps.maxOddsFor(alice), 51, "halfway to the first knee");
        game.setScore(alice, 399);
        assertEq(craps.maxOddsFor(alice), 99, "continuous into the first knee");
        game.setScore(alice, 400);
        assertEq(craps.maxOddsFor(alice), 100, "the 100x table");
        game.setScore(alice, 1200);
        assertEq(craps.maxOddsFor(alice), 550, "halfway up the second segment");
        game.setScore(alice, 1999);
        assertEq(craps.maxOddsFor(alice), 999, "continuous into the cap");
        game.setScore(alice, 2000);
        assertEq(craps.maxOddsFor(alice), 1000, "the 1000x ceiling");
        game.setScore(alice, 65_534); // the game's global score cap
        assertEq(craps.maxOddsFor(alice), 1000, "flat above the ceiling");
    }

    function test_oddsAboveTheAllowanceAreRefused() public {
        Craps.Bets memory b;
        b.passLine = L;
        b.passOddsMult = 4; // score 0 -> allowance 3

        // Hoisted: `stakeFor` is itself an external call, and an inline one would consume the
        // expectRevert latch.
        uint128 roll4 = uint128(craps.stakeFor(b));
        vm.prank(alice);
        vm.expectRevert(FlipCraps.OddsAboveAllowance.selector);
        craps.placeSlip(b, roll4, 0);

        // A maxed degen takes the full 1000x — and not a point more.
        game.setScore(alice, 2000);
        b.passOddsMult = 1000;
        uint128 roll1000 = uint128(craps.stakeFor(b));
        vm.prank(alice);
        craps.placeSlip(b, roll1000, 0);

        b.passOddsMult = 1001;
        uint128 roll1001 = uint128(craps.stakeFor(b));
        vm.prank(alice);
        vm.expectRevert(FlipCraps.OddsAboveAllowance.selector);
        craps.placeSlip(b, roll1001, 0);

        // The allowance is per player: bob's score is still 0.
        b.passOddsMult = 1000;
        vm.prank(bob);
        vm.expectRevert(FlipCraps.OddsAboveAllowance.selector);
        craps.placeSlip(b, roll1000, 0);
    }

    // ---------------------------------------------------------------------------------------
    // Shared table
    // ---------------------------------------------------------------------------------------

    /// @dev Friends seated at one index play one shooter, so identical wagers settle identically no
    ///      matter who placed them.
    function test_friendsAtOneTableSettleIdentically() public {
        vm.prank(alice);
        uint64 a = craps.placeSlip(_bets(), LW * 3, 0);
        vm.prank(bob);
        uint64 c = craps.placeSlip(_bets(), LW * 3, 0);

        _setWord(4, uint256(keccak256("vrf")));

        (uint256 wonA, bool survivedA, uint256 paidA) = craps.previewSettlement(a);
        (uint256 wonB, bool survivedB, uint256 paidB) = craps.previewSettlement(c);
        assertEq(wonA, wonB, "same table dealt different hands");
        assertEq(craps.betOf(a).staked, craps.betOf(c).staked, "same wager, same cost");
        // Identical bets run identically, so they exit on the same round and share a coin.
        assertEq(survivedA, survivedB, "identical runs produced two flips");
        assertEq(paidA, paidB, "identical wagers at one table paid differently");
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

            uint256 shortHands =
                craps.resolveSlipAt(b, idx, LW, 0, craps.MAX_SLIP_HANDS()).handsPlayed;
            uint256 longHands =
                craps.resolveSlipAt(b, idx, LW * 10, 0, craps.MAX_SLIP_HANDS()).handsPlayed;
            if (shortHands == longHands) continue; // same length, same coin by design
            ++differingLengths;

            if (craps.survivedAt(idx, shortHands) == craps.survivedAt(idx, longHands)) {
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
    function testFuzz_theBankrollIsTheWholeExposure(uint256 seed, uint16 rawStake, uint8 rawRounds) public {
        // The board must clear the 600-FLIP table minimum: nine legs of at least 67 each do.
        uint24 unit = uint24(bound(uint256(rawStake), 67, 16_777_215));
        uint256 rounds = bound(uint256(rawRounds), 1, 10);

        Craps.Bets memory b;
        b.passLine = unit;
        b.passOddsMult = 2;
        b.place4 = unit;
        b.place5 = unit;
        b.place6 = unit;
        b.place8 = unit;
        b.place9 = unit;
        b.place10 = unit;
        b.hard4 = unit;
        b.hard8 = unit;

        uint48 idx = uint48(bound(seed, 1, type(uint32).max));
        _setIndex(idx);

        uint256 bankroll = craps.stakeFor(b) * rounds;
        vm.prank(alice);
        uint64 betId = craps.placeSlip(b, uint128(bankroll), 0);
        assertEq(flip.burned(alice), bankroll, "burned exactly the bankroll");

        _setWord(idx, uint256(keccak256(abi.encode(seed))));
        craps.resolveBets(_ids(betId));

        // Settlement mints; it never burns again. The placement burn is the entire cost.
        assertEq(flip.burned(alice), bankroll, "settlement reached back into the wallet");
    }
}
