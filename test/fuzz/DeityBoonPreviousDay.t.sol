// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DeityBoonViewer} from "../../contracts/DeityBoonViewer.sol";
import {DeityBoonViewerTreeHarness} from "./BoonRollTreeParity.t.sol";

contract PreviousDayBoonSeeder is DegenerusGameStorage {
    function seed(uint24 day, uint256 word, address deity, bool locked) external {
        rngWordByDay[day] = word;
        mintPacked_[deity] |= uint256(1) << 184;
        rngLockedFlag = locked;
    }
}

contract DeityBoonPreviousDayTest is DeployProtocol {
    address private constant DEITY = address(0xDE17);
    address private constant RECIPIENT = address(0xB001);
    uint24 private constant TODAY = 41;
    uint256 private constant YESTERDAY_WORD = 0xCAFE;
    uint256 private constant TODAY_WORD = 0xBEEF;
    bytes32 private constant ISSUED = keccak256("DeityBoonIssued(address,address,uint24,uint8,uint8)");
    DeityBoonViewerTreeHarness private viewer;

    function setUp() public {
        _deployProtocol();
        viewer = new DeityBoonViewerTreeHarness();
        _warp(TODAY);
        _seed(TODAY - 1, YESTERDAY_WORD, false);
        _seed(TODAY, TODAY_WORD, false);
    }

    function _warp(uint24 day) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620 + 3 hours);
    }

    function _seed(uint24 day, uint256 word, bool locked) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(PreviousDayBoonSeeder).runtimeCode);
        PreviousDayBoonSeeder(address(game)).seed(day, word, DEITY, locked);
        vm.etch(address(game), code);
    }

    function _expected(uint256 word, uint24 day, uint8 slot) private view returns (uint8) {
        uint256 roll = uint256(keccak256(abi.encode(word, DEITY, day, slot))) % 2766;
        if (roll >= 982) roll += 50;
        if (roll >= 1072) roll += 40;
        return viewer.tree(roll);
    }

    function _issue(address recipient, uint8 slot, uint24 day, uint8 expectedType) private {
        vm.recordLogs();
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, recipient, slot);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 issued;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != ISSUED) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), DEITY);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), recipient);
            assertEq(uint256(logs[i].topics[3]), day, "stamp the issuance day, not the seed day");
            (uint8 actualSlot, uint8 actualType) = abi.decode(logs[i].data, (uint8, uint8));
            assertEq(actualSlot, slot);
            assertEq(actualType, expectedType);
            ++issued;
        }
        assertEq(issued, 1);
    }

    function test_TodayUsesYesterdayAndTomorrowUsesToday() public view {
        (uint256 word, uint24 day, uint8 mask,,) = game.deityBoonData(DEITY);
        assertEq(word, YESTERDAY_WORD);
        assertEq(day, TODAY);
        assertEq(mask, 0);
        (uint8[3] memory today,,) = viewer.deityBoonSlots(address(game), DEITY);
        (uint8[3] memory tomorrow, uint24 tomorrowDay) = viewer.deityBoonSlotsTomorrow(address(game), DEITY);
        assertEq(tomorrowDay, TODAY + 1);
        for (uint8 i; i < 3; ++i) {
            assertEq(today[i], _expected(YESTERDAY_WORD, TODAY, i));
            assertEq(tomorrow[i], _expected(TODAY_WORD, TODAY + 1, i));
        }
    }

    function testFuzz_PreviewMatchesNextDayIssuanceBeforeItsRng(uint256 word) public {
        word |= 1;
        _seed(TODAY, word, false);
        (uint8[3] memory preview, uint24 issueDay) = viewer.deityBoonSlotsTomorrow(address(game), DEITY);
        _warp(issueDay);
        assertEq(game.rngWordForDay(issueDay), 0, "no issuance-day RNG yet");
        (uint8[3] memory current, uint8 mask, uint24 day) = viewer.deityBoonSlots(address(game), DEITY);
        assertEq(mask, 0);
        assertEq(day, issueDay);
        for (uint8 i; i < 3; ++i) {
            assertEq(preview[i], _expected(word, issueDay, i));
            assertEq(current[i], preview[i]);
            _issue(address(uint160(0xB001 + i)), i, issueDay, preview[i]);
        }
        (, mask,) = viewer.deityBoonSlots(address(game), DEITY);
        assertEq(mask, 7);
    }

    function test_IssuanceDayRngCannotChangeTheMenu() public {
        _warp(TODAY + 1);
        (uint8[3] memory beforeMenu,,) = viewer.deityBoonSlots(address(game), DEITY);
        _seed(TODAY + 1, 0x123456789, false);
        (uint8[3] memory afterMenu,,) = viewer.deityBoonSlots(address(game), DEITY);
        for (uint8 i; i < 3; ++i) assertEq(afterMenu[i], beforeMenu[i]);
        _issue(RECIPIENT, 0, TODAY + 1, beforeMenu[0]);
    }

    function test_CanIssueWhileCurrentDayRngIsPending() public {
        _seed(TODAY, 0, true);
        assertTrue(game.rngLocked());
        _issue(RECIPIENT, 0, TODAY, _expected(YESTERDAY_WORD, TODAY, 0));
    }

    function test_PreviewDoesNotSpendTomorrowSlotsOrChangeTodaysMenu() public {
        _issue(RECIPIENT, 0, TODAY, _expected(YESTERDAY_WORD, TODAY, 0));
        (uint8[3] memory preview, uint24 tomorrow) = viewer.deityBoonSlotsTomorrow(address(game), DEITY);
        (uint8[3] memory current, uint8 mask, uint24 today) = viewer.deityBoonSlots(address(game), DEITY);
        assertEq(mask, 1);
        assertEq(today, TODAY);
        assertEq(tomorrow, TODAY + 1);
        assertEq(current[0], _expected(YESTERDAY_WORD, TODAY, 0));
        assertEq(preview[0], _expected(TODAY_WORD, tomorrow, 0));
        _warp(tomorrow);
        (, mask,) = viewer.deityBoonSlots(address(game), DEITY);
        assertEq(mask, 0);
        _issue(RECIPIENT, 0, tomorrow, preview[0]);
    }

    function test_TomorrowHasNoPlaceholderBeforeTodaysWord() public {
        _seed(TODAY, 0, false);
        (uint8[3] memory preview, uint24 day) = viewer.deityBoonSlotsTomorrow(address(game), DEITY);
        assertEq(day, TODAY + 1);
        for (uint8 i; i < 3; ++i) assertEq(preview[i], 0);
        _issue(RECIPIENT, 0, TODAY, _expected(YESTERDAY_WORD, TODAY, 0));
    }

    function test_MissingPreviousDayNeverFallsBackToTodaysWord() public {
        _seed(TODAY - 1, 0, false);
        (uint8[3] memory slots,,) = viewer.deityBoonSlots(address(game), DEITY);
        for (uint8 i; i < 3; ++i) assertEq(slots[i], 0);
        vm.expectRevert(DegenerusGameBoonModule.RngNotReady.selector);
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, RECIPIENT, 0);
    }

    function test_FirstDayHasNoPreviousSeed() public {
        _warp(1);
        _seed(1, TODAY_WORD, false);
        (uint256 word, uint24 day,,,) = game.deityBoonData(DEITY);
        assertEq(word, 0);
        assertEq(day, 1);
        vm.expectRevert(DegenerusGameBoonModule.RngNotReady.selector);
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, RECIPIENT, 0);
        (uint8[3] memory tomorrow, uint24 tomorrowDay) = viewer.deityBoonSlotsTomorrow(address(game), DEITY);
        assertEq(tomorrowDay, 2);
        for (uint8 i; i < 3; ++i) assertEq(tomorrow[i], _expected(TODAY_WORD, 2, i));
    }

    function test_SlotAndRecipientDailyLimitsStillApply() public {
        _issue(RECIPIENT, 0, TODAY, _expected(YESTERDAY_WORD, TODAY, 0));
        vm.expectRevert(DegenerusGameBoonModule.SlotAlreadyUsed.selector);
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, address(0xB002), 0);
        vm.expectRevert(DegenerusGameBoonModule.RecipientAlreadyBoonedToday.selector);
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, RECIPIENT, 1);
    }

    function test_LifetimeLimitStillAppliesAcrossSeedDays() public {
        for (uint24 i; i < 10; ++i) {
            uint24 day = TODAY + i;
            _warp(day);
            _seed(day - 1, YESTERDAY_WORD + i, false);
            _issue(RECIPIENT, 0, day, _expected(YESTERDAY_WORD + i, day, 0));
        }
        _warp(TODAY + 10);
        _seed(TODAY + 9, TODAY_WORD, false);
        vm.expectRevert(DegenerusGameBoonModule.RecipientBoonCapReached.selector);
        vm.prank(DEITY);
        game.issueDeityBoon(DEITY, RECIPIENT, 0);
    }
}
