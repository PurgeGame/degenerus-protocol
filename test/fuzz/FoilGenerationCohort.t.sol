// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameFoilPackModule} from "../../contracts/modules/DegenerusGameFoilPackModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

contract FoilCohortCreditStub {
    mapping(address => uint256) public credited;
    function creditFlip(address player, uint256 amount) external { credited[player] += amount; }
}

/// @dev Seed commitment state only; generation, storage and gold claims are production code.
contract FoilCohortHarness is DegenerusGameFoilPackModule {
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
        (bool done, bool worked) = h.processFoilDrain(84);
        assertFalse(done);
        assertTrue(worked);
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
