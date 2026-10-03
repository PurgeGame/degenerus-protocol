// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusTraitUtils} from "../../contracts/DegenerusTraitUtils.sol";
import {GoldSixLib} from "../../contracts/libraries/GoldSixLib.sol";
import {Test} from "forge-std/Test.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";
import {IDegenerusGameDegeneretteModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";

contract FoilHeroSpinStub {
    event FoilHeroSpin(bytes4 selector, uint8 symbol);
    fallback() external {
        (,,,, uint8 symbol) = abi.decode(msg.data[4:], (address, uint256, uint16, uint256, uint8));
        require(symbol < 24, "foil award selected Dice");
        emit FoilHeroSpin(msg.sig, symbol);
        assembly ("memory-safe") { mstore(0, 0) return(0, 32) }
    }
}

contract FoilCohortCreditStub {
    mapping(address => uint256) public credited;
    function creditFlip(address player, uint256 amount) external { credited[player] += amount; }
}

/// @dev Seed commitment state only; generation, storage and gold claims are production code.
contract FoilCohortHarness is DegenerusGameFoilPackModule {
    function seedTaken(address who) external {
        _setTicketBufferLevel(1);
        uint256 owner = uint256(_registerEntryOwner(who, 1) >> OWNER_IDX_SHIFT) - 1;
        _bucketAppendRun(_traitBufferBase(1), 253, owner, 1, 1);
    }
    function retire() external { _setTicketBufferLevel(3); }
    function goldWord(address who) external pure returns (uint256 word) {
        uint256[7] memory cut = DegenerusTraitUtils.foilCuts(20_000);
        for (word = 2; ; ++word) {
            uint256 seed = uint256(keccak256(abi.encode(word, who, uint24(1), FOIL_SEED_TAG, uint256(0))));
            if (DegenerusTraitUtils.foilTrait(uint64(seed >> 192), cut) == 61) return word;
        }
    }
    function live() external {
        dailyIdx = _simulatedDayIndex();
        purchaseStartDay = dailyIdx;
    }
    function enqueue(address player) external {
        uint24 lvl = 1;
        require(_foilRecordWord(player, lvl) == 0);
        foilRecord[lvl & 3][player] = (uint256(20_000) << _FOIL_MULT_SHIFT) | (uint256(lvl) << _FOIL_LEVEL_SHIFT);
        uint256 pos = uint256(_registerEntryOwner(player, lvl) >> OWNER_IDX_SHIFT) - 1;
        foilQueue[_foilWriteKey()].push(((pos + 1) << 192) | (uint256(lvl) << 160) | uint160(player));
    }
    function commit(uint256 word) external {
        require(!_foilDrainPending());
        ticketWriteSlot = !ticketWriteSlot;
        foilWriteSlot = !foilWriteSlot;
        foilCursor = 0;
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        rngWordCurrent = word;
        _setRngSessionPublished(true);
    }
    function record(address player) external view returns (uint256) { return _foilRecordWord(player, 1); }
    function lines(address player) external view returns (uint32[4] memory) { return _foilStoredLines(player, 1); }
    function pending() external view returns (bool) { return _foilDrainPending(); }
    function length(bool read) external view returns (uint256) {
        return foilQueue[read ? _foilReadKey() : _foilWriteKey()].length;
    }
    function entries(uint8 trait) external view returns (uint256) { return _bucketLength(1, trait); }
    function seedWord(uint24 day, uint256 word) external { _recordDailyRng(day, word); }
    function retained(uint24 day) external view returns (uint256) { return _retainedDailyWord(day); }
    function seedGold(address player, uint24 day) external {
        // Three gold quadrants qualify for the first ladder rung, no all-gold ticket.
        foilRecord[1][player] = uint256(day) | (uint256(20_000) << _FOIL_MULT_SHIFT)
            | (uint256(0x0038_3838) << _FOIL_LINES_SHIFT)
            | (uint256(day) << _FOIL_GENERATED_DAY_SHIFT) | (uint256(1) << _FOIL_LEVEL_SHIFT) | _FOIL_READY;
    }
    function claimableDraw(uint24 day) external view returns (bool) { return _foilGoldClaimOpen(day); }
    function seedMatch(address player, uint256 word) external returns (uint24 day) {
        day = _simulatedDayIndex();
        uint32 line = 0xC5824100; // Crypto 0, Zodiac 1, Cards 2, Dice 6.
        dailyFoilDraw[day & 1] = _packFoilDraw(line, 1, day, word);
        foilRecord[1][player] = uint256(day) | (uint256(line) << _FOIL_LINES_SHIFT)
            | (uint256(1) << _FOIL_LEVEL_SHIFT) | _FOIL_READY;
    }
}

contract FoilGenerationCohortTest is Test {
    FoilCohortHarness private h;
    address private constant A = address(0xA11CE);
    address private constant B = address(0xB0B);
    uint256 private constant READY = uint256(1) << 255;

    function setUp() public {
        vm.warp(86400);
        vm.etch(ContractAddresses.GAME, type(FoilCohortHarness).runtimeCode);
        vm.etch(ContractAddresses.COINFLIP, type(FoilCohortCreditStub).runtimeCode);
        h = FoilCohortHarness(ContractAddresses.GAME);
        h.live();
    }

    function testFoilGoldSixUsesSharedCapAndStoresRedirectedClaims() public {
        uint256 word = h.goldWord(A);
        uint256 snapshot = vm.snapshotState();
        h.enqueue(A);
        h.commit(word);
        h.processFoilDrain(900);
        uint32[4] memory natural = h.lines(A);
        assertEq(uint8(natural[0] >> 24), 253);
        assertEq(h.entries(253), 1);
        assertTrue(vm.revertToStateAndDelete(snapshot));
        h.seedTaken(B);
        h.enqueue(A);
        h.commit(word);
        h.processFoilDrain(900);
        uint32[4] memory redirected = h.lines(A);
        uint256[256] memory counts;
        counts[253] = 1;
        for (uint256 i; i < 4; ++i) {
            assertEq(redirected[i] & 0x00ffffff, natural[i] & 0x00ffffff);
            uint8 dice = uint8(redirected[i] >> 24);
            if (uint8(natural[i] >> 24) == 253) {
                assertGe(dice, 248);
                assertTrue(dice != 253);
            } else assertEq(dice, uint8(natural[i] >> 24));
            for (uint256 q; q < 4; ++q) ++counts[uint8(redirected[i] >> (8 * q))];
        }
        for (uint256 t; t < 256; ++t) assertEq(h.entries(uint8(t)), counts[t], "stored claims and buckets agree");
    }

    function testRetiredFoilCannotCreateAnotherGoldSix() public {
        uint256 word = h.goldWord(A);
        h.enqueue(A);
        h.commit(word);
        h.retire();
        h.processFoilDrain(900);
        uint32[4] memory lines = h.lines(A);
        for (uint256 i; i < 4; ++i) assertTrue(uint8(lines[i] >> 24) != 253);
        assertGe(uint8(lines[0] >> 24), 248);
    }

    function testFoilMatchAwardsChooseOnlyNonDiceHeroesInEveryCurrency() public {
        vm.etch(ContractAddresses.GAME_DEGENERETTE_MODULE, type(FoilHeroSpinStub).runtimeCode);
        uint256 currencies;
        uint256 heroes;
        for (uint256 word; word < 64; ++word) {
            address player = address(uint160(0x1000 + word));
            uint24 day = h.seedMatch(player, word);
            vm.recordLogs();
            h.claimFoilMatch(player, day, 0);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool found;
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].topics[0] != keccak256("FoilHeroSpin(bytes4,uint8)")) continue;
                (bytes4 selector, uint8 symbol) = abi.decode(logs[i].data, (bytes4, uint8));
                assertTrue(symbol == 0 || symbol == 9 || symbol == 18, "hero comes from a non-Dice foil lane");
                heroes |= uint256(1) << (symbol >> 3);
                if (selector == IDegenerusGameDegeneretteModule.resolveEthSpinFromBox.selector) currencies |= 1;
                else if (selector == IDegenerusGameDegeneretteModule.resolveFlipSpinsFromBox.selector) currencies |= 2;
                else if (selector == IDegenerusGameDegeneretteModule.resolveWwxrpSpinFromBox.selector) currencies |= 4;
                else fail("unexpected spin selector");
                found = true;
            }
            assertTrue(found, "claim reached an award spin");
        }
        assertEq(currencies, 7, "all award currencies exercised");
        assertEq(heroes, 7, "all eligible quadrants exercised");
    }

    function test_NewBuyAfterCommitWaitsForFreshCohort() public {
        h.enqueue(A);
        assertEq(uint24(h.record(A)), 0, "purchase carries no day");
        h.commit(0xA11CE);
        h.enqueue(B);
        (bool done, bool worked) = h.processFoilDrain(900);
        assertTrue(done && worked);
        assertTrue(h.record(A) & READY != 0);
        assertEq(h.record(B) & READY, 0, "later buy cannot use public word");
        assertEq(h.length(true), 0);
        assertEq(h.length(false), 1);
        h.commit(0xBEEF);
        h.processFoilDrain(900);
        assertTrue(h.record(B) & READY != 0);
    }

    function test_MaterializedLinesEqualAllSixteenEntryTraits() public {
        h.enqueue(A);
        h.commit(0xA11CE);
        h.processFoilDrain(900);
        uint32[4] memory lines = h.lines(A);
        uint256[256] memory counts;
        for (uint256 i; i < 4; ++i) {
            for (uint256 q; q < 4; ++q) ++counts[uint8(lines[i] >> (q * 8))];
        }
        uint256 total;
        for (uint256 t; t < 256; ++t) {
            uint256 n = h.entries(uint8(t));
            assertEq(n, counts[t]);
            total += n;
        }
        assertEq(total, 16);
        h.seedWord(GameTimeLib.currentDayIndex(), 9);
        vm.warp(vm.getBlockTimestamp() + 250 days);
        h.seedWord(GameTimeLib.currentDayIndex(), 10);
        uint32[4] memory afterLines = h.lines(A);
        for (uint256 i; i < 4; ++i) assertEq(afterLines[i], lines[i]);
    }

    function test_PartialDrainAcrossMidnightKeepsCohortStampAndLines() public {
        h.enqueue(A);
        h.enqueue(B);
        h.commit(0xA11CE);
        uint24 day = GameTimeLib.currentDayIndex();
        MineFlipGas.Result memory first = h.runFoilWork(1_600_000);
        assertFalse(first.done);
        assertTrue(first.progressed);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        h.live();
        h.processFoilDrain(900);
        assertEq(uint24(h.record(A) >> 184), day);
        assertEq(uint24(h.record(B) >> 184), day + 1, "each pack gets its actual materialization day");
        assertFalse(h.pending());
    }

    function test_GoldClaimsTodayAndTomorrowWithoutRevealWord() public {
        uint24 day = GameTimeLib.currentDayIndex();
        h.seedGold(A, day);
        h.seedGold(B, day);
        h.claimGoldenTicket(A, 1);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        h.live();
        h.claimGoldenTicket(B, 1);
        assertGt(FoilCohortCreditStub(ContractAddresses.COINFLIP).credited(A), 0);
        assertGt(FoilCohortCreditStub(ContractAddresses.COINFLIP).credited(B), 0);
        vm.expectRevert();
        h.claimGoldenTicket(A, 1);
    }

    function test_GoldExpiresOnSecondDayEvenWithoutOverwrite() public {
        uint24 day = GameTimeLib.currentDayIndex();
        h.seedGold(A, day);
        h.seedWord(day, 99);
        vm.warp(vm.getBlockTimestamp() + 2 days);
        h.live();
        assertFalse(h.claimableDraw(day));
        assertEq(h.retained(day), 0);
        vm.expectRevert();
        h.claimGoldenTicket(A, 1);
    }

    function test_RngTagsRejectOldAndFutureParityAliases() public {
        uint24 day = GameTimeLib.currentDayIndex();
        h.seedWord(day, 11);
        assertEq(h.retained(day), 11);
        assertEq(h.retained(day + 2), 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        h.seedWord(day + 1, 12);
        assertEq(h.retained(day), 11);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        h.seedWord(day + 2, 13);
        assertEq(h.retained(day), 0);
        assertEq(h.retained(day + 1), 12);
        assertEq(h.retained(day + 2), 13);
    }
}
