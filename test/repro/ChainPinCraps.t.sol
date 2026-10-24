// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CrapsPins} from "../craps/CrapsPins.sol";
import {CrapsViews} from "../craps/CrapsViews.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {CrapsRngSealHandler} from "../fuzz/handlers/CrapsRngSealHandler.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {LootboxCraps} from "../../contracts/LootboxCraps.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

// ════════════════════════════════════════════════════════════════════════════════════════════
// Chain pins for the Craps stages of the mineFlip chain (Craps, JackpotBattle, LootboxCraps).
// Each test names the coupling it pins (audit IDs F2..F12, C3, S2 F-C3) and fails if it breaks.
// ════════════════════════════════════════════════════════════════════════════════════════════

/// @dev Game storage with the Game's own flag setters. Etched at the GAME pin so LootboxCraps reads it.
contract ChainPinGameFlags is DegenerusGameStorage {
    function extsload_g8132(bytes32 s) external view returns (bytes32 v) {
        assembly { v := sload(s) }
    }
    function setPublished(bool on) external { _setRngSessionPublished(on); }
    function setTerminal() external { _setRngTerminal(); }
    function swapBuffers() external { _swapRngBuffers(); }
    function setWord(uint256 w) external { rngWordCurrent = w; }
    function writeBuffer() external view returns (uint48) { return _rngWriteBuffer(); }
    function readBuffer() external view returns (uint48) { return _rngReadBuffer(); }
}

/// @dev LootboxCraps' raw Game reads, exposed.
contract ChainPinLootboxProbe is LootboxCraps {
    function wordAt(uint48 i) external view returns (uint256) { return _wordAt(i); }
    function writeBuffer() external view returns (uint48) { return _writeBuffer(); }
}

/// @dev Craps storage constants and key functions, exposed.
contract ChainPinTableProbe is JackpotBattle {
    function ringConsts() external pure returns (uint256 reservation, uint256 settlement, uint256 slotsPerDay) {
        return (_RESERVATION_DAYS, _SETTLEMENT_DAYS, _BONUS_SLOTS_PER_DAY);
    }
    function betKey(uint256 id) external pure returns (uint256) { return _betStorageKey(id); }
    function reservedIds() external pure returns (uint32, uint32) { return (_VAULT_ID, _SDGNRS_ID); }
}

/// @dev The full table plus a cursor setter, for states the clock alone reaches slowly.
contract ChainPinTable is CrapsViews {
    function setCursor(uint64 s) external { _minerSlot = s; }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
// F2: LootboxCraps' hard-coded Game flag bits mean what the Game's own setters say they mean.
// ────────────────────────────────────────────────────────────────────────────────────────────
contract ChainPinLootboxFlagsTest is Test {
    ChainPinGameFlags internal game;
    ChainPinLootboxProbe internal probe;

    function setUp() public {
        vm.etch(ContractAddresses.GAME, address(new ChainPinGameFlags{salt: keccak256("chainpin-flags")}()).code);
        game = ChainPinGameFlags(ContractAddresses.GAME);
        probe = new ChainPinLootboxProbe{salt: keccak256("chainpin-lootbox-probe")}();
    }

    /// @dev Bit 253 is the Game's terminal flag: a terminal session never serves a word.
    function test_F2_terminalBitIsTheGamesTerminalFlag() public {
        game.setPublished(true);
        game.setWord(0xABCD);
        uint48 read = game.readBuffer();
        assertEq(probe.wordAt(read), 0xABCD, "control: published word is served");
        game.setTerminal();
        assertEq(probe.wordAt(read), 0, "terminal session still served a word");
        assertEq(probe.wordAt(read ^ 1), 0, "terminal write buffer");
    }

    /// @dev Bit 255 is the Game's published flag: an unpublished session serves nothing.
    function test_F2_publishedBitIsTheGamesPublishedFlag() public {
        game.setWord(0xABCD);
        uint48 read = game.readBuffer();
        game.setPublished(false);
        assertEq(probe.wordAt(read), 0, "unpublished session served a word");
        game.setPublished(true);
        assertEq(probe.wordAt(read), 0xABCD, "published word not served");
    }

    /// @dev Bit 252 is the Game's write-buffer selector, through its own buffer swap.
    function test_F2_selectorBitIsTheGamesWriteBuffer() public {
        for (uint256 i; i < 4; ++i) {
            assertEq(probe.writeBuffer(), game.writeBuffer(), "write selector");
            game.swapBuffers();
        }
    }

    function testFuzz_F2_wordAtFollowsTheGamesOwnFlags(bool published, bool terminal, uint8 swaps, uint256 word)
        public
    {
        for (uint256 i; i < swaps % 4; ++i) game.swapBuffers();
        game.setPublished(published);
        if (terminal) game.setTerminal();
        game.setWord(word);
        uint48 read = game.readBuffer();
        assertEq(probe.writeBuffer(), game.writeBuffer(), "write selector");
        uint256 expected = published && !terminal && word > 1 ? word : 0;
        assertEq(probe.wordAt(read), expected, "read buffer word");
        assertEq(probe.wordAt(read ^ 1), 0, "the write buffer never serves a word");
    }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
// C3, F10: constants read from the real contracts.
// ────────────────────────────────────────────────────────────────────────────────────────────
contract ChainPinStructureTest is Test {
    ChainPinTableProbe internal probe;

    function setUp() public {
        probe = new ChainPinTableProbe{salt: keccak256("chainpin-structure-probe")}();
    }

    /// @dev C3: BAF pair resumption restarts the pair draw at `i & 3 == 0`; a chunk that is not a
    ///      multiple of four would resume mid-pair on a zero winner.
    function test_C3_bafAwardChunkIsPairAligned() public pure {
        assertEq(GasBounds.JACKPOT_ETH_AWARD_CHUNK % 4, 0, "JACKPOT_ETH_AWARD_CHUNK is not a multiple of four");
    }

    /// @dev F10: 30 reservation days + today + 30 settlement days must fit the 64 day banks
    ///      (`slot & 511` over eight slots a day).
    function test_F10_liveSpanFitsTheSixtyFourBankRings() public view {
        (uint256 reservation, uint256 settlement, uint256 perDay) = probe.ringConsts();
        assertLe(reservation + settlement + 1, 64, "live day span exceeds the 64 day banks");
        assertEq(perDay * 64, 512, "slot mask and day banks disagree");
    }

    function testFuzz_F10_noTwoLiveDaysShareABetBank(uint24 start, uint256 aSeed, uint256 bSeed) public view {
        (uint256 reservation, uint256 settlement,) = probe.ringConsts();
        uint256 span = reservation + settlement + 1;
        start = uint24(bound(start, 1, type(uint24).max - 200));
        uint256 a = bound(aSeed, 0, span - 1);
        uint256 b = bound(bSeed, 0, span - 1);
        if (a == b) return;
        uint256 slotA = (uint256(start) + a) * 8 + 1;
        uint256 slotB = (uint256(start) + b) * 8 + 1;
        assertTrue(probe.betKey((slotA << 64) | 1) != probe.betKey((slotB << 64) | 1), "two live days alias");
    }

    /// @dev Negative control: days 64 apart do share a bank, so the test above can fail.
    function test_F10_daysSixtyFourApartShareABank() public view {
        uint256 slotA = uint256(100) * 8 + 1;
        uint256 slotB = uint256(164) * 8 + 1;
        assertEq(probe.betKey((slotA << 64) | 1), probe.betKey((slotB << 64) | 1));
    }

    /// @dev F12 (layout half): the compact board bits copied into a field word sit above the id
    ///      and below the unit bit, so neither can corrupt the other.
    function test_F12_fieldBoardBitsFitBetweenIdAndUnit() public pure {
        assertGe(JackpotBattleFieldLib.BOARD_SHIFT, 32, "board overlaps the wallet id");
        assertLe(JackpotBattleFieldLib.BOARD_SHIFT + 20, JackpotBattleFieldLib.UNITS_SHIFT, "board overlaps the unit");
    }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
// Mock-Game table pins: F4, F5a, F12, S2 F-C3.
// ────────────────────────────────────────────────────────────────────────────────────────────
contract ChainPinCrapsMockTest is CrapsPins {
    ChainPinTable internal craps;

    uint256 internal constant PLAIN_WORD = 40 << 8;
    uint32 internal constant SEVEN = 3 | (uint32(3) << 9) | (uint32(1) << 12);
    bytes32 internal constant ARMED_SIG = keccak256("CrapsBonusArmed(bytes32,uint48,uint48)");

    address internal alice = makeAddr("chainpin-alice");
    address internal bob = makeAddr("chainpin-bob");

    function setUp() public {
        _installPins();
        game.registerWallet_g9539(alice, true);
        game.registerWallet_g9539(bob, true);
        _warpToTableGenesis();
        craps = new ChainPinTable();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setIndex(0);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        vm.prank(vaultOwner);
        craps.setBattleCreator(address(this), true);
    }

    // ── F4: the custom-battle key is derived twice and must agree ───────────────────────────

    /// @dev CrapsBattle derives the key a seat is written under; JackpotBattle derives the key
    ///      `closeBattle` registers. A mismatch leaves a registered head that never settles.
    ///      `closeBattle` reverts unless both keys name the same nonzero board, and the emitted
    ///      key must equal the table's own.
    /// forge-config: default.fuzz.runs = 200
    function testFuzz_F4_customKeyAgreesBetweenCrapsBattleAndJackpotBattle(
        uint256 playedRaw,
        uint256 bankRaw,
        uint256 goalRaw,
        uint256 stakeRaw,
        uint256 highRaw,
        uint256 closeRaw,
        bool multi
    ) public {
        uint32 played = uint32(bound(playedRaw, 30, 1_000_000) * 10);
        uint8 bankMult = uint8(bound(bankRaw, 1, 25));
        uint16 goalMult = uint16(bound(goalRaw, 5, 1000));
        uint256 stakeCap = (uint256(played) * bankMult) / 100;
        if (stakeCap > 0x3FFFF) stakeCap = 0x3FFFF;
        uint24 stake = uint24(bound(stakeRaw, 0, stakeCap));
        uint16 high = uint16(bound(highRaw, 0, 255));
        if (high == 1) high = 0;
        uint40 close = uint40(vm.getBlockTimestamp() + bound(closeRaw, 1, 7 days));

        uint64 slot = craps.createBattle(played, bankMult, goalMult, stake, close, multi, high);
        vm.prank(alice);
        craps.enterBattle(slot, uint32(0), 1);
        vm.warp(uint256(close));

        (bytes32 expected,,) = craps.customBattleOf(slot);
        vm.recordLogs();
        craps.closeBattle(slot);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(craps) || logs[i].topics[0] != ARMED_SIG) continue;
            found = true;
            assertEq(logs[i].topics[1], expected, "JackpotBattle and CrapsBattle disagree on the custom key");
        }
        assertTrue(found, "closeBattle did not arm the field");
    }

    // ── F5a: minerMaintenancePending vs the worker, row by row ──────────────────────────────

    function _dayStart() internal view returns (uint256) {
        return vm.getBlockTimestamp() - ((vm.getBlockTimestamp() - 82_620) % 1 days);
    }

    function _closeOf(uint256 period) internal view returns (uint256) {
        if (period + 2 == craps.BONUS_PERIODS_PER_DAY()) return 1 days - craps.EVENT_LEAD();
        if (period + 1 == craps.BONUS_PERIODS_PER_DAY()) return 1 days;
        uint256 base = period == 0 ? craps.BONUS_EVENT_CLOSE() : period * craps.BONUS_PERIOD();
        return base + craps.BONUS_CLOCK_ALIGN();
    }

    /// @dev The predicate the selector reads and the worker the stage runs, from the same state:
    ///      the worker progresses exactly when the predicate says maintenance is owed.
    function _agree(string memory row) internal returns (bool pred) {
        assertEq(uint256(game.rngConsumerStage_g379()), 7, row);
        pred = craps.minerMaintenancePending_g11976();
        bool progressed = _maintain(craps).progressed;
        assertEq(progressed, pred, row);
    }

    function test_F5a_predicateAndWorkerAgreeOnEveryRow() public {
        assertFalse(_agree("A: separator, no budget, not lapsed"));

        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        assertTrue(_agree("B: separator with a budget"));

        vm.warp(_dayStart() + _closeOf(3));
        assertTrue(_agree("B2: first live scheduled window closed"));
        assertGt(craps.slotIndexOf(craps.minerSlot()), 0, "fixture: the first live window was armed");
        assertFalse(_agree("C: armed, unresolved"));

        uint64 head = craps.minerSlot();
        _setWord(craps.slotIndexOf(head) - 1, 0xC105ED);
        for (uint256 i; i < 8 && game.rngConsumerStage_g379() == 6; ++i) _readWork(craps, craps.currentIndex() ^ 1);
        assertEq(uint256(game.rngConsumerStage_g379()), 7, "fixture: the read cohort did not drain");
        assertTrue(_agree("D: armed, fully resolved"));

        assertFalse(_agree("E: unarmed, still taking bets"));
        // The unbounded D call may skip every empty closed window. Seed this
        // independent truth-table row at a known unarmed routine window.
        uint64 unarmed = uint64(uint256(craps.currentDayIndex()) * 8 + 4);
        assertEq(craps.slotIndexOf(unarmed), 0, "F fixture: unarmed routine field");
        craps.setCursor(unarmed);
        vm.warp(_dayStart() + _closeOf(3));
        assertTrue(_agree("F: unarmed, closed"), "F: closed unarmed routine field");

        vm.warp(vm.getBlockTimestamp() + 40 days);
        uint256 today = craps.currentDayIndex();
        craps.setCursor(uint64((today - 3) * 8));
        assertTrue(_agree("G: separator, no budget, lapsed day"));
        craps.setCursor(uint64((today - 2) * 8 + 7));
        assertTrue(_agree("H: remainder seven"));
        craps.setCursor(uint64((today - 2) * 8 + 6));
        assertFalse(_agree("I: unarmed jackpot window"));
        craps.setCursor(uint64((today - 31) * 8 + 3));
        assertTrue(_agree("J: expired cursor"));
    }

    /// forge-config: default.fuzz.runs = 120
    function testFuzz_F5a_randomHistoriesAgree(uint256 seed) public {
        uint256 floorScore = craps.SYBIL_SCORE_FLOOR();
        for (uint256 i; i < 24; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            uint256 op = r % 8;
            if (op == 0) {
                vm.warp(vm.getBlockTimestamp() + 1 minutes + (r >> 8) % 3 hours);
            } else if (op == 1) {
                vm.warp(vm.getBlockTimestamp() + (r >> 8) % 2 days);
            } else if (op == 2) {
                if ((r >> 8) % 8 == 0) vm.warp(vm.getBlockTimestamp() + 25 days + (r >> 16) % 15 days);
            } else if (op == 3) {
                _setDailyWord(craps.currentDayIndex(), (r >> 8) | 2);
                vm.prank(ContractAddresses.GAME);
                craps.openBonusDay();
            } else if (op == 4) {
                address who = (r >> 8) % 2 == 0 ? alice : bob;
                game.setScore(who, floorScore);
                vm.prank(who);
                try craps.enterBonusBattle((r >> 16) % 6, SEVEN, 1) {} catch {}
            } else if (op == 5) {
                uint48 b = craps.currentIndex();
                if (!craps.rngCohortComplete(b) && craps.rngCohortComplete(b ^ 1)) _setWord(b, (r >> 8) | 2);
            }
            uint8 stage = game.rngConsumerStage_g379();
            if (stage == 6) _readWork(craps, craps.currentIndex() ^ 1);
            else if (stage == 7) _agree("random history");
        }
    }

    // ── F12 / S2 F-C3: saved boards never exceed seven named chips ──────────────────────────

    function _boardKey(address who) internal view returns (bytes32) {
        return keccak256(abi.encode(uint256(game.walletIdOf_g3120(who)), CrapsPreferenceLib.PASS_SLOT));
    }

    function _word(address who) internal view returns (uint256) {
        return uint256(craps.extsload_g8132(_boardKey(who)));
    }

    /// @dev A board of up to twelve chips, at most three a leg, starting at a random leg. Leg 0 is the
    ///      pass line and leg 9 the don't pass; a board names only one of them.
    function _board(uint256 r) internal pure returns (uint32 chips, uint256 count) {
        uint256 leg = (r >> 8) % 10;
        uint256 left = r % 13;
        while (left != 0) {
            uint256 put = left > 3 ? 3 : left;
            chips |= uint32(put << (leg * 3));
            left -= put;
            leg = (leg + 1) % 10;
        }
        if (chips & 7 != 0 && (chips >> 27) & 7 != 0) chips &= ~uint32(7 << 27);
        for (uint256 i; i < 10; ++i) count += (chips >> (i * 3)) & 7;
    }

    /// @dev Every door that can save a board: whatever is offered, the stored compact board names
    ///      at most seven chips, because the engine's `10 - placed` and the Decimator decode
    ///      panic past that on every drawn seat.
    /// forge-config: default.fuzz.runs = 250
    function testFuzz_F12_noDoorSavesAnInvalidBoard(uint256 r, uint8 door, uint256 garbage) public {
        (uint32 chips, uint256 count) = _board(r);
        bool wild = garbage % 8 == 0;
        if (wild) chips = uint32(garbage >> 8);
        vm.prank(ContractAddresses.GAME);
        craps.openBonusDay();
        uint256 floorScore = craps.SYBIL_SCORE_FLOOR();
        game.setScore(alice, floorScore);
        uint24 nextDay = craps.currentDayIndex() + 1;
        uint256 d = door % 4;
        if (d == 0) {
            vm.prank(alice);
            try craps.setPreferredBoard(0, chips) {} catch {}
        } else if (d == 1) {
            vm.prank(alice);
            try craps.enterBonusBattle(1, chips, 1) {} catch {}
        } else if (d == 2) {
            uint64 slot = craps.createBattle(300, 2, 5, 0, uint40(vm.getBlockTimestamp() + 1 hours), true, 0);
            vm.prank(alice);
            try craps.enterBattle(slot, chips, 1) {} catch {}
        } else {
            vm.prank(alice);
            try craps.buyFutureCrapsDays(nextDay, 1, false, chips) {} catch {}
        }
        (, uint256 placed) = CrapsPreferenceLib.decode(_word(alice));
        assertLe(placed, 7, "a saved board names more than seven chips");
        if (d == 0 && !wild && count <= 7) {
            assertEq(craps.preferredBoardOf(game.walletIdOf_g3120(alice)), chips, "a valid board was not saved");
        }
    }

    /// @dev Every writer of the shared id-keyed word other than the board saver — credits, spends,
    ///      conversions, deliveries — leaves the saved board bits untouched.
    /// forge-config: default.fuzz.runs = 250
    function testFuzz_FC3_passWritersLeaveTheSavedBoardAlone(uint256 r, uint256 ops) public {
        (uint32 chips, uint256 count) = _board(r);
        vm.assume(count <= 7);
        vm.prank(alice);
        craps.setPreferredBoard(0, chips);
        uint256 saved = (_word(alice) >> CrapsPreferenceLib.SHIFT) & 0x1FFFFF;
        uint32 aliceId = game.walletIdOf_g3120(alice);
        uint24 today = craps.currentDayIndex();
        for (uint256 i; i < 8; ++i) {
            uint256 o = uint256(keccak256(abi.encode(ops, i)));
            uint256 k = o % 4;
            uint32 n = uint32(o >> 8);
            uint32 h = uint32(o >> 40);
            if (k == 0) {
                vm.prank(ContractAddresses.GAME);
                craps.creditPasses(aliceId, n, h);
            } else if (k == 1) {
                vm.prank(ContractAddresses.GAME);
                craps.creditPasses(aliceId, n % 64, 0);
                vm.prank(alice);
                try craps.convertNormalToHigh(0, 1 + n % 2) {} catch {}
            } else if (k == 2) {
                vm.prank(alice);
                try craps.applyCrapsPasses(today + 1 + uint24(o % 20), 1, h % 2 == 0, chips) {} catch {}
            } else {
                vm.prank(ContractAddresses.GAME);
                try craps.deliverPasses(aliceId, n % 4, h % 3) {} catch {}
            }
            assertEq(
                (_word(alice) >> CrapsPreferenceLib.SHIFT) & 0x1FFFFF, saved, "a pass writer touched the board bits"
            );
        }
    }

    /// @dev The Game-side field word and the battle-side decode agree on the board.
    function testFuzz_F12_compactBoardRoundTripsThroughTheFieldWord(uint256 r) public pure {
        (uint32 chips, uint256 count) = _board(r);
        vm.assume(count <= 7);
        uint256 word = (CrapsPreferenceLib.compress(chips) << CrapsPreferenceLib.SHIFT) | CrapsPreferenceLib.INITIALIZED;
        (uint32 back, uint256 placed) = CrapsPreferenceLib.decode(word);
        assertEq(back, chips);
        assertEq(placed, count);
        uint256 entry = ((word & CrapsPreferenceLib.MASK) >> CrapsPreferenceLib.SHIFT) << JackpotBattleFieldLib.BOARD_SHIFT;
        (uint32 back2, uint256 placed2) = CrapsPreferenceLib.decode(
            entry >> (JackpotBattleFieldLib.BOARD_SHIFT - CrapsPreferenceLib.SHIFT)
        );
        assertEq(back2, chips);
        assertEq(placed2, count);
    }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
// Real-protocol pins: F3, F5a/F5b on the live RNG machine.
// ────────────────────────────────────────────────────────────────────────────────────────────
contract ChainPinCrapsFsmTest is DeployProtocol {
    CrapsRngSealHandler internal handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);
        handler = new CrapsRngSealHandler(game, mockVRF, coin, crapsBattle, 5);
    }

    function _bit(uint48 i) internal view returns (bool) {
        return (uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) >> (250 + i)) & 1 == 1;
    }

    function _low() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(GameSlots.LOOTBOX_RNG_PACKED))) & ((uint256(1) << 250) - 1);
    }

    /// @dev F3 (Game bit 250+i mirrors "craps FIFO i non-empty"), F5b (RNG complete means consumer
    ///      stage 7, no lock, no live request, no terminal flag; Maintenance only when complete) and
    ///      F5a (the predicate and the worker agree) in the live machine.
    function _couplings() internal {
        for (uint48 b; b < 2; ++b) {
            assertEq(_bit(b), !crapsBattle.rngCohortComplete(b), "F3: Game pending bit and craps FIFO disagree");
        }
        if (game.nextMinerAction() == 15) assertTrue(game.rngComplete(), "F5b: Maintenance selected while incomplete");
        if (!game.rngComplete() || game.gameOver()) return;
        assertEq(uint256(game.rngConsumerStage_g379()), 7, "F5b: RNG complete but the consumer stage is not 7");
        assertFalse(game.rngLocked(), "F5b: complete while locked");
        uint256 flags = uint256(vm.load(address(game), bytes32(0)));
        assertEq((flags >> 254) & 1, 0, "F5b: complete with a live request");
        assertEq((flags >> 253) & 1, 0, "F5b: complete with the terminal flag");
        bool pred = crapsBattle.minerMaintenancePending_g11976();
        uint256 snap = vm.snapshotState();
        vm.prank(address(game));
        MineFlipGas.Result memory res = crapsBattle.runCrapsMaintenance_g10712(gasleft());
        vm.revertToState(snap);
        assertEq(res.progressed, pred, "F5a: maintenance predicate and worker disagree");
    }

    function _degenerette(uint256 a) internal {
        address who = address(uint160(uint256(keccak256(abi.encode("pin-bettor", a % 4)))));
        vm.deal(who, 10 ether);
        vm.prank(who);
        try game.placeDegeneretteBet{value: 0.01 ether}(0, 0, 0.01 ether, 1, uint8(a % 24)) {} catch {}
    }

    function _box(uint256 a) internal {
        address who = address(uint160(uint256(keccak256(abi.encode("pin-buyer", a % 4)))));
        uint256 amt = 0.01 ether + (a % 5) * 0.01 ether;
        vm.deal(who, 10 ether);
        vm.prank(who);
        try game.purchase{value: amt + 1 ether}(
            0, 400, BoxOrderLib.boCustomFloor(amt), bytes32(0), MintPaymentKind.DirectEth, false
        ) {} catch {}
    }

    function _step(uint256 r) internal {
        uint256 op = r % 12;
        uint256 a = r >> 8;
        if (op == 0) {
            try handler.advanceDay(a) {} catch {}
        } else if (op == 1) {
            try handler.enterWindow(a, a >> 16, a >> 32, (a >> 48) & 1 == 1) {} catch {}
        } else if (op == 2) {
            try handler.createCustom(a, a >> 16) {} catch {}
        } else if (op == 3) {
            try handler.arm(a) {} catch {}
        } else if (op == 4) {
            try handler.sealRequest(a) {} catch {}
        } else if (op == 5) {
            try handler.fulfil(a) {} catch {}
        } else if (op == 6) {
            try handler.keep(uint64(a)) {} catch {}
        } else if (op == 7) {
            try handler.settle(a) {} catch {}
        } else if (op == 8) {
            _degenerette(a);
        } else if (op == 9) {
            _box(a);
        } else if (op == 10) {
            vm.prank(address(uint160(a)));
            try game.mineFlip(0) {} catch {}
        } else {
            vm.warp(vm.getBlockTimestamp() + a % 6 hours);
        }
    }

    /// @dev Shared prologue: one armed read FIFO.
    function _armedFifo() internal returns (uint48 i0) {
        _couplings();
        handler.advanceDay(1);
        handler.enterWindow(0, 5, 0, false);
        handler.enterWindow(1, 6, 1, false);
        _couplings();
        handler.arm(0);
        i0 = handler.armedIndexOf(handler.armedSlots(0));
        assertTrue(_bit(i0), "register did not set the Game bit");
        assertFalse(crapsBattle.rngCohortComplete(i0), "FIFO empty after register");
        _couplings();
    }

    /// @dev Every other lootboxRngPacked writer (bets, boxes) leaves the craps bits alone while a FIFO
    ///      is registered, and a second push onto a non-empty FIFO keeps the bit set.
    function test_F3_lowerFieldWritersLeaveTheBitsAlone() public {
        uint48 i0 = _armedFifo();
        try handler.arm(4) {} catch {}
        assertTrue(_bit(i0), "second push cleared the bit");
        _couplings();

        uint256 low0 = _low();
        _degenerette(1);
        assertTrue(_low() != low0, "fixture: the bet wrote no lower field");
        assertTrue(_bit(i0), "a bet cleared the craps pending bit");
        _couplings();
        low0 = _low();
        _box(2);
        assertTrue(_low() != low0, "fixture: the box purchase wrote no lower field");
        assertTrue(_bit(i0), "a box purchase cleared the craps pending bit");
        _couplings();
    }

    /// @dev Sealing keeps the bit while the FIFO is non-empty; the bit clears when the head reaches the
    ///      length, and not before.
    function test_F3_completeClearsTheBitOnlyWhenTheFifoDrains() public {
        uint48 i0 = _armedFifo();
        handler.sealRequest(0);
        assertTrue(_bit(i0), "the seal cleared the bit with the FIFO still pending");
        assertFalse(crapsBattle.rngCohortComplete(i0), "fixture: the FIFO drained at the seal");
        _couplings();
        handler.fulfil(11);
        _couplings();
        for (uint256 i; i < 96 && !crapsBattle.rngCohortComplete(i0); ++i) {
            try game.mineFlip(0) {} catch {}
            _couplings();
        }
        assertTrue(crapsBattle.rngCohortComplete(i0), "fixture: the FIFO never drained");
        assertFalse(_bit(i0), "complete did not clear the Game bit");
        _couplings();
    }

    /// forge-config: default.fuzz.runs = 12
    function testFuzz_F3_F5_couplingsHoldAlongRandomHistories(uint256 seed) public {
        _couplings();
        for (uint256 i; i < 14; ++i) {
            _step(uint256(keccak256(abi.encode(seed, i))));
            _couplings();
        }
    }
}

// ────────────────────────────────────────────────────────────────────────────────────────────
// Real-protocol pins: F6 (payees and reserved ids) and S1 F7 (idle gap).
// ────────────────────────────────────────────────────────────────────────────────────────────
contract ChainPinCrapsMiscTest is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.deal(address(game), 5_000_000 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    /// @dev F6: Craps' reserved protocol ids are the Game's (and Coinflip's literal 1/2).
    function test_F6_craps_reservedIdsAreTheGamesProtocolIds() public {
        ChainPinTableProbe probe = new ChainPinTableProbe{salt: keccak256("chainpin-misc-probe")}();
        (uint32 vaultId, uint32 sdgnrsId) = probe.reservedIds();
        assertEq(vaultId, game.walletIdOf_g3120(ContractAddresses.VAULT), "vault id");
        assertEq(sdgnrsId, game.walletIdOf_g3120(ContractAddresses.SDGNRS), "sDGNRS id");
        assertEq(vaultId, 1);
        assertEq(sdgnrsId, 2);
    }

    /// @dev F6 / A-F8: every allocated winner id (protocol, main, smurf) has a nonzero payee, and
    ///      the dice-run record path (`armDiceRunRecord` -> `payRecordSdgnrs` -> `recordSet`) takes
    ///      it. A zero id reverts, which is why the producer must never pass one.
    function test_F6_everyAllocatedWinnerTakesTheDiceRunRecord() public {
        address m1 = makeAddr("pin-main-1");
        address m2 = makeAddr("pin-main-2");
        address m3 = makeAddr("pin-main-3");
        _giveWalletId(m1);
        _giveWalletId(m2);
        _giveWalletId(m3);
        _grantSmurfBase(m1, 2);
        vm.deal(m1, 10 ether);
        (,,,, uint256 price) = game.purchaseInfo();
        vm.prank(m1);
        game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);

        uint32 n;
        for (uint32 id = 1;; ++id) {
            try game.resolveAccount_g502(id, address(0)) returns (address, address payee, bool) {
                assertTrue(payee != address(0), "an allocated id resolves to a zero payee");
                n = id;
            } catch {
                break;
            }
        }
        assertGe(uint256(n), 7, "fixture: too few ids");

        vm.prank(ContractAddresses.GAME);
        coinflip.fundRecordPool(1e30);
        for (uint32 id = 1; id <= n; ++id) {
            uint256 score = 1_000_000 * (uint256(id) + 1);
            vm.prank(ContractAddresses.CRAPS);
            coinflip.armDiceRunRecord(id, score);
            (, address payee,) = game.resolveAccount_g502(id, address(0));
            (address holder, uint128 mark,,) = recordBounty.recordInfo(4);
            assertEq(holder, payee, "record holder is not the winner's payee");
            assertEq(uint256(mark), score);
        }

        vm.prank(ContractAddresses.CRAPS);
        vm.expectRevert();
        coinflip.armDiceRunRecord(0, 1_000_000 * (uint256(n) + 2));
    }

    function _fulfilPending() internal {
        uint256 req = mockVRF.lastRequestId();
        if (req == 0) return;
        (,, bool done) = mockVRF.pendingRequests(req);
        if (!done) mockVRF.fulfillRandomWords(req, uint256(keccak256(abi.encode("pin-f7", req))) | 2);
    }

    /// @dev A calendar gap below the hard deadline creates no logical backlog.
    ///      Servicing the next actual reset advances exactly one round and its table cursor.
    /// forge-config: default.fuzz.runs = 6
    function testFuzz_F7_idleGapViewsReturnAndMineFlipProceeds(uint256 gapRaw) public {
        uint256 gap = bound(gapRaw, 2, 12);
        uint24 beforeDay = game.currentDayView();
        uint64 beforeCursor = crapsBattle.minerSlot();
        vm.warp(vm.getBlockTimestamp() + gap * 1 days);
        assertEq(crapsBattle.currentDayIndex(), beforeDay, "calendar gap creates no table days");
        assertEq(crapsBattle.minerSlot(), beforeCursor, "calendar gap creates no cursor debt");
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertTrue(game.nextMinerAction() != 1, "gap is inside the completion deadline");
        for (uint256 i; i < 300; ++i) {
            _fulfilPending();
            if (game.currentDayView() == beforeDay + 1) {
                (bool complete,,) = game.dailySessionState();
                if (complete && !crapsBattle.minerMaintenancePending_g11976()) return;
            }
            game.mineFlip{gas: 16_700_000}(0);
            assertLe(game.currentDayView(), beforeDay + 1, "one round per actual reset");
        }
        fail("one delayed round did not complete");
    }

    /// @dev Past the deadman the selector goes terminal, but the same views must still return for any
    ///      cursor lag, expired or not.
    /// forge-config: default.fuzz.runs = 12
    function testFuzz_F7_viewsReturnForAnyGap(uint256 gapRaw) public {
        uint256 gap = bound(gapRaw, 1, 400);
        vm.warp(vm.getBlockTimestamp() + gap * 1 days);
        bool pending = crapsBattle.minerMaintenancePending_g11976();
        uint24 today = crapsBattle.currentDayIndex();
        if (uint256(crapsBattle.minerSlot()) / 8 + 30 < today) assertTrue(pending, "an expired cursor is owed maintenance");
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertLe(uint256(game.nextMinerAction()), 20);
        assertLe(uint256(game.minerAction()), 21);
    }
}
