// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotTableHarness} from "./JackpotBattle.t.sol";
import {CrapsPins} from "./CrapsPins.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract JackpotVariableHarness is JackpotTableHarness {
    function presetFee(uint256 roll) external pure returns (uint256) {
        (,,, uint256 units,) = _bonusPreset(roll, 5);
        return units * 100;
    }

    function roundBase(uint64 slot) external pure returns (bytes32) {
        uint256 root;
        assembly ("memory-safe") { root := _jackpotRounds.slot }
        return keccak256(abi.encode(uint256(slot), root));
    }
}

contract JackpotVariableDecoder is JackpotBattle {
    function subsidy(uint256 bucket) external pure returns (uint256) { return _subsidyMultiplier(bucket); }
    function presetFee(uint256 roll) external pure returns (uint256) {
        (,,, uint256 units,) = _bonusPreset(roll, 5);
        return units * 100;
    }
}

contract JackpotVariablePricingTest is CrapsPins {
    JackpotVariableHarness private table;
    JackpotBattle private cold;
    uint24 private day;
    uint64 private slot;
    uint256 private start;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    uint256 private constant SUBSIDY_TAG = uint256(keccak256("CrapsJackpotSubsidy"));
    uint256 private constant MULT_TAG = 0x436f696e447261774d756c7469706c696572;

    function setUp() public {
        _installPins();
        table = JackpotVariableHarness(deployCode("JackpotVariablePricing.t.sol:JackpotVariableHarness"));
        cold = JackpotBattle(address(table));
        start = vm.getBlockTimestamp() + 1 days - (vm.getBlockTimestamp() - 82_620) % 1 days;
        vm.warp(start);
        day = table.currentDayIndex();
        slot = uint64(uint256(day) * 8 + 6);
        _setIndex(1);
        game.setScore(ALICE, 100);
        game.setScore(BOB, 100);
    }

    function _price(uint256 word) private pure returns (uint256) {
        uint256 b = uint256(keccak256(abi.encode(word, uint256(0x43726170735363686564756c65), uint256(5)))) & 3;
        return b == 0 ? 6000 : b == 3 ? 10000 : 8000;
    }

    function _open(uint256 price, uint16 high) private {
        uint256 word = 1;
        while (_price(word) != price || table.highMultOfWord(word) != high) ++word;
        _setDailyWord(day, word);
        vm.prank(ContractAddresses.GAME);
        table.openBonusDay();
        table.clearDayBodies(day);
        assertEq(cold.jackpotEntryPrice(), price);
    }

    function _lock(uint256 baseline) private {
        vm.warp(start + 1 days);
        game.setRngLocked(true);
        vm.prank(ContractAddresses.GAME);
        cold.lockJackpotBattle(day + 1, baseline * 1 ether / 500, 2);
    }

    function _round() private view returns (CrapsBattleStorage.JackpotRound memory r) {
        (r,,) = cold.jackpotBattleOf(slot);
    }

    function _start(uint256 word, uint32 chips) private {
        uint256[] memory field = new uint256[](5);
        for (uint256 i; i < 5; ++i) field[i] = uint160(ALICE) | (uint256(chips) << 160) | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        cold.prepareJackpotBattle(2, word);
        cold.appendJackpotBattle(field, 5, true);
        vm.stopPrank();
    }

    // Collect deterministic witnesses for all 16 independent hidden outcome pairs in one walk.
    function _words() private view returns (uint256[16] memory words) {
        uint256 found;
        for (uint256 word = 1; found != 0xffff; ++word) {
            uint256 s = uint256(keccak256(abi.encode(word, uint256(slot), SUBSIDY_TAG))) % 100;
            uint256 m = uint256(keccak256(abi.encode(word, MULT_TAG))) % 1000;
            uint256 i = (s < 60 ? 0 : s < 90 ? 1 : s < 99 ? 2 : 3) * 4
                + (m < 900 ? 0 : m < 990 ? 1 : m < 999 ? 2 : 3);
            if (words[i] == 0) { words[i] = word; found |= uint256(1) << i; }
        }
    }

    function test_ExactDecoderOddsMeanAndBothPresetCopies() public {
        JackpotVariableDecoder decoder = JackpotVariableDecoder(deployCode("JackpotVariablePricing.t.sol:JackpotVariableDecoder"));
        uint256 priceSum;
        for (uint256 i; i < 4; ++i) {
            uint256 expected = i == 0 ? 6000 : i == 3 ? 10000 : 8000;
            assertEq(table.presetFee(i), expected);
            assertEq(decoder.presetFee(i), expected);
            priceSum += expected;
        }
        assertEq(priceSum, 4 * 8000);
        uint256 subsidySum;
        for (uint256 i; i < 100; ++i) {
            uint256 expected = i < 60 ? 2500 : i < 90 ? 10000 : i < 99 ? 50000 : 100000;
            assertEq(decoder.subsidy(i), expected);
            subsidySum += expected;
        }
        assertEq(subsidySum, 100 * 10000);
    }

    function test_All48OutcomesConserveCapitalAndKeepHighFeesSeparate() public {
        uint256[16] memory words = _words();
        uint256[3] memory prices = [uint256(6000), 8000, 10000];
        uint256[3] memory priceWeights = [uint256(25), 50, 25];
        uint256[4] memory subsidies = [uint256(2500), 10000, 50000, 100000];
        uint256[4] memory subsidyWeights = [uint256(60), 30, 9, 1];
        uint256[4] memory multiples = [uint256(5000), 30000, 200000, 1000000];
        uint256[4] memory multipleWeights = [uint256(900), 90, 9, 1];
        uint256 root = vm.snapshotState();
        uint256 weightedMain;
        for (uint256 p; p < 3; ++p) {
            if (p != 0) { assertTrue(vm.revertToState(root)); root = vm.snapshotState(); }
            uint256 price = prices[p];
            _open(price, 100);
            vm.prank(ALICE); table.enterBonusBattle(5, 0, 1);
            uint256 dayCost;
            for (uint256 period; period < 6; ++period) {
                (uint128 bank,,,uint256 bounty,,) = table.bonusTermsFor(day, period);
                dayCost += bank + bounty;
            }
            vm.prank(BOB); table.enterBonusDay(0, 100);
            assertEq(flip.burned(ALICE), price);
            assertEq(flip.burned(BOB), dayCost * 100);
            _lock(50_000);
            CrapsBattleStorage.JackpotRound memory r = _round();
            assertEq(r.entryPrice, price);
            assertEq(r.awardTarget, 5, "target must be fixed at lock");
            assertEq(r.paidCount, 2);
            assertEq(r.paidUnits, 101);
            assertEq(r.subsidyMultiplierBps, 0, "hidden draw must not exist at lock");
            assertEq(r.drawWord, 0);
            uint256 added = 50_000 * price / 8000;
            assertEq(r.added, added);
            assertEq(cold.highRollerReserve(), added / 20);
            uint256 snap = vm.snapshotState();
            for (uint256 i; i < 16; ++i) {
                if (i != 0) { assertTrue(vm.revertToState(snap)); snap = vm.snapshotState(); }
                _start(words[i], 0);
                r = _round();
                uint256 subsidy = (added - added / 20) * subsidies[i / 4] / 10000;
                uint256 main = (2 * price + subsidy) * multiples[i % 4] / 10000;
                uint256 high = 99 * price * multiples[i % 4] / 10000;
                assertEq(r.subsidyMultiplierBps, subsidies[i / 4]);
                assertEq(r.multiplierBps, multiples[i % 4]);
                assertEq(r.totalPool, main + high);
                assertEq(7 * (uint256(r.bankroll) + uint256(r.bountyUnits) * 100) + r.potRemainder, main);
                assertEq(2 * table.jackpotTerms(slot).highExtra, high);
                assertEq(r.awardTarget, 5);
                assertEq(r.drawnCount, 5);
                assertEq(cold.highRollerReserve(), added / 20);
                assertEq(cold.jackpotEntryPriceOf(slot), price, "bounty must not replace fee quote");
                weightedMain += main * priceWeights[p] * subsidyWeights[i / 4] * multipleWeights[i % 4];
            }
        }
        // Exact accounting expectation over 10,000,000 bucket combinations, including floors.
        assertEq(weightedMain, (2 * 8000 + 47500) * 10_000_000 - 4_402_500);
    }

    function test_MinimumBankrollRunsEveryLegalPickedCount() public {
        uint256[16] memory words = _words();
        _open(6000, 10);
        _lock(50_000);
        uint256 snap = vm.snapshotState();
        for (uint256 count; count <= 7; ++count) {
            if (count != 0) { assertTrue(vm.revertToState(snap)); snap = vm.snapshotState(); }
            uint32 chips = uint32(count > 3 ? 3 : count);
            if (count > 3) chips |= uint32(count > 6 ? 3 : count - 3) << 3;
            if (count > 6) chips |= uint32(count - 6) << 6;
            _start(words[0], chips);
            assertEq(_round().bankroll, 300);
            for (uint256 calls; calls < 10; ++calls) {
                (,,, bool done) = cold.jackpotProgress();
                if (done) break;
                vm.prank(ContractAddresses.GAME); cold.runDailyBattleWork(12_000_000);
            }
            (,,, bool complete) = cold.jackpotProgress();
            assertTrue(complete, "minimum bankroll must settle through the real engine");
            assertEq(table.battleOf(bytes32(uint256(slot))).resolved, 5);
        }
    }

    function test_AllPricesChargeLiveCompsAndNewcomersButKeepBlindReservationsAtMean() public {
        uint256 root = vm.snapshotState();
        address compPlayer = address(0xCA401);
        for (uint256 price = 6000; price <= 10000; price += 2000) {
            if (price != 6000) { assertTrue(vm.revertToState(root)); root = vm.snapshotState(); }
            flip.setCompLane(1_000_000);
            vm.warp(start - 1 days);
            uint256 reservation = uint160(BOB) | (uint256(5) << 160) | (uint256(day) << 176)
                | (uint256(1) << 200) | (uint256(5) << 208);
            vm.prank(ContractAddresses.VAULT);
            assertEq(table.vaultComp(reservation), 8000, "unworded reservation uses the mean");
            vm.warp(start);
            _open(price, 10);
            game.setMintHistory(ALICE, 0);
            vm.prank(ALICE); table.enterBonusBattle(5, 0, 1);
            assertEq(flip.burned(ALICE), price * 105 / 100);
            vm.prank(ContractAddresses.VAULT);
            assertEq(table.vaultComp(uint160(compPlayer) | (uint256(5) << 176)), price);
            assertEq(flip.compLane(), 1_000_000 - 8000 - price);
            assertEq(flip.burned(BOB), 0);
            assertEq(flip.burned(compPlayer), 0);
            vm.prank(ContractAddresses.VAULT);
            vm.expectRevert(); table.vaultComp(reservation);
            _lock(50_000);
            assertEq(_round().paidCount, 3);
            assertEq(_round().paidUnits, 3);
            assertEq(_round().entryPrice, price);
        }
    }

    function test_MegaTailPreservesCapsAndRemainderAtMaximumAwards() public {
        uint256[16] memory words = _words();
        _open(10000, 100);
        vm.prank(BOB); table.enterBonusBattle(5, 0, 100);
        _lock(1_000_000_000);
        assertEq(_round().awardTarget, 500);
        uint256[] memory field = new uint256[](50);
        for (uint256 i; i < 50; ++i) field[i] = uint160(ALICE) | (uint256(1) << 180);
        vm.startPrank(ContractAddresses.GAME);
        cold.prepareJackpotBattle(2, words[15]);
        for (uint256 i; i < 10; ++i) cold.appendJackpotBattle(field, (i + 1) * 50, i == 9);
        vm.stopPrank();
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.subsidyMultiplierBps, 100000);
        assertEq(r.multiplierBps, 1000000);
        assertEq(r.drawnUnits, 500);
        uint256 maxBank = (uint256(type(uint24).max) / 60) * 300;
        assertEq(r.bankroll, maxBank, "existing engine cap remains in force");
        uint256 main = r.totalPool - 99 * 10000 * 100;
        assertEq(main, 501 * (uint256(r.bankroll) + uint256(r.bountyUnits) * 100) + r.potRemainder);
        assertGt(r.potRemainder, main / 2, "capped capital remains in the pot");
        for (uint256 calls; calls < 100; ++calls) {
            (,,, bool done) = cold.jackpotProgress();
            if (done) break;
            vm.prank(ContractAddresses.GAME); cold.runDailyBattleWork(12_000_000);
        }
        (,,, bool complete) = cold.jackpotProgress();
        assertTrue(complete, "maximum field and concentrated awards must finish");
    }

    function test_RetiredWordAndRetriesPreservePackedFieldsAndBothResults() public {
        _open(10000, 100);
        vm.prank(ALICE); table.enterBonusBattle(5, 0, 100);
        _setDailyWord(day, 0);
        assertEq(cold.jackpotEntryPriceOf(slot), 10000);
        _lock(150_000);
        CrapsBattleStorage.JackpotRound memory r = _round();
        assertEq(r.paidUnits, 100, "retired word must not erase frozen high multiple");
        assertEq(r.added, 187500);
        assertEq(r.awardTarget, 15);
        bytes32 base = table.roundBase(slot);
        uint256 packed = uint256(vm.load(address(table), bytes32(uint256(base) + 5)));
        assertEq(uint32(packed >> 144), 15);
        assertEq(uint32(packed >> 176), 10000);
        assertEq(uint32(packed >> 208), 0);
        _start(123, 0);
        r = _round();
        assertEq(uint256(vm.load(address(table), bytes32(uint256(base) + 6))), 123);
        assertEq(uint256(vm.load(address(table), bytes32(uint256(base) + 7))), 5);
        assertEq(uint32(uint256(vm.load(address(table), bytes32(uint256(base) + 5))) >> 208), r.subsidyMultiplierBps);
        bytes32 frozen = keccak256(abi.encode(r));
        vm.startPrank(ContractAddresses.GAME);
        cold.prepareJackpotBattle(99, 456);
        cold.lockJackpotBattle(day + 1, 999 ether, 99);
        vm.stopPrank();
        assertEq(keccak256(abi.encode(_round())), frozen);
        assertEq(cold.jackpotEntryPriceOf(slot), 10000);
    }

    function testFuzz_TargetIsFixedAtLockFromUnscaledBaseline(uint96 raw, uint8 pick) public {
        uint256 baseline = bound(raw, 50_000, 10_000_000);
        uint256 price = 6000 + uint256(pick % 3) * 2000;
        _open(price, 10);
        _lock(baseline);
        uint256 target = baseline / 10000;
        if (target > 500) target = 500;
        assertEq(_round().awardTarget, target);
        assertEq(_round().added, baseline * price / 8000);
        assertEq(_round().entryPrice, price);
        assertEq(_round().subsidyMultiplierBps, 0);
    }

    function test_DetachedRoundUsesNeutralPriceAndNoPaidReservations() public {
        _open(10000, 100);
        table.clearBoostBudget(day);
        _lock(50_000);
        slot = uint64(uint256(day) * 8 + 7);
        assertEq(_round().entryPrice, 8000);
        assertEq(_round().added, 50000);
        assertEq(_round().awardTarget, 5);
        assertEq(cold.highRollerReserve(), 2500);
        assertEq(cold.jackpotEntryPriceOf(slot), 8000);
    }

    function test_UnopenedPriceIsNotAnActualEightThousandQuote() public {
        vm.expectRevert(bytes4(keccak256("RngNotReady()"))); cold.jackpotEntryPrice();
        vm.expectRevert(bytes4(keccak256("RngNotReady()"))); cold.jackpotEntryPriceOf(slot);
        vm.expectRevert(JackpotBattle.BadJackpotField.selector); cold.jackpotEntryPriceOf(slot - 1);
    }

    function test_LockClosesAllControlsBeforeEitherHiddenResult() public {
        _open(6000, 10);
        vm.prank(ALICE); uint256 bet = table.enterBonusBattle(5, 0, 1);
        _lock(50_000);
        assertEq(_round().subsidyMultiplierBps, 0);
        vm.expectRevert(); table.enterBonusBattle(5, 0, 1);
        vm.prank(ALICE); vm.expectRevert(); table.amendSlip(bet, 1);
        vm.expectRevert(); table.donate(false, 5, 1);
        vm.prank(ContractAddresses.GAME);
        vm.expectRevert(JackpotBattle.BadJackpotField.selector); cold.prepareJackpotBattle(2, 0);
    }
}
