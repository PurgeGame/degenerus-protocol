// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {Test} from "forge-std/Test.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract AfkingMembershipHarness is GameAfkingModule, WalletSeed {
    function seed(address pending, address clean, uint8 quantity) external returns (uint24 processDay) {
        _seedProtocolWallets();
        dailyIdx = _simulatedDayIndex();
        processDay = dailyIdx + 1;
        _afkingResetDay = processDay;
        _setRngComplete(true);
        _setRngSessionPublished(true);
        rngWordCurrent = 0xAFAF;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        uint32 pendingId = _seedWallet(pending);
        _addToSet(_subOf[pendingId], pendingId);
        Sub storage sub = _subOf[pendingId];
        sub.setPosition = 1;
        sub.dailyQuantity = quantity;
        sub.lastAutoBoughtDay = processDay;
        sub.lastOpenedDay = dailyIdx;
        sub.afkCoveredThroughDay = processDay;
        sub.afkingStartDay = processDay;
        sub.amount = 10;
        _pendingBoxCount = 1;
        if (clean != address(0)) {
            uint32 cleanId = _seedWallet(clean);
            _addToSet(_subOf[cleanId], cleanId);
            _subOf[cleanId].setPosition = 2;
        }
    }
    function idOf(address player) external view returns (uint32) { return _walletIdOf(player); }
    function deliver() external { ++dailyIdx; _setRngComplete(false); }
    function nextProcessDay() external returns (uint24 day) {
        day = dailyIdx + 1;
        _afkingResetDay = day;
        _subCursor = 0;
        subsFullyProcessed = false;
        _setRngComplete(true);
    }
    function corruptEmptySet() external { _setSubscriberAt(0, 0); _setSubscriberCount(0); _subBoxCount = 0; }
    function complete() external view returns (bool) { return _rngComplete(); }
    function state(address player) external view returns (uint256 count, uint256 members, uint256 index, uint24 stamp, uint24 opened, uint8 quantity) {
        Sub storage sub = _subOf[_walletIdOf(player)];
        return (_pendingBoxCount, _subscribers.length, sub.setPosition, sub.lastAutoBoughtDay, sub.lastOpenedDay, sub.dailyQuantity);
    }
}

contract AfkingPendingMembershipTest is Test {
    AfkingMembershipHarness private h;
    address private constant PLAYER = address(0xAA11);

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        h = new AfkingMembershipHarness();
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.QUESTS, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.AFFILIATE, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.GAME_LOOTBOX_MODULE, bytes(""), bytes(""));
    }

    function test_CancellationWaitsForPendingStampToOpen() public {
        uint24 day = h.seed(PLAYER, address(0), 1);
        uint32 playerId = h.idOf(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(playerId, false, false, 0, 0, 0);
        h.deliver();
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(playerId, false, false, 0, 0, 0);
        MineFlipGas.Result memory result = h.runAfkingWork(9_000_000);
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        vm.prank(PLAYER);
        h.subscribe(playerId, false, false, 0, 0, 0);
        (uint256 pending, uint256 members, uint256 index, uint24 stamp, uint24 opened, uint8 qty) = h.state(PLAYER);
        assertEq(pending, 0);
        assertEq(members, 1, "cancel keeps same-day history until reclaim");
        assertEq(index, 1);
        assertEq(stamp, day);
        assertEq(opened, stamp);
        assertEq(qty, 0);
        day = h.nextProcessDay();
        assertTrue(h.runSubscriberWork(day, 9_000_000).done);
        (, members, index,,,) = h.state(PLAYER);
        assertEq(members, 0);
        assertEq(index, 0);
    }

    function test_PendingModeChangeIsRejectedWithoutLosingPaidBox() public {
        h.seed(PLAYER, address(0), 1);
        h.deliver();
        uint32 id = h.idOf(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(id, false, true, 1, 0, 0);
        (uint256 pending,, uint256 index, uint24 stamp, uint24 opened,) = h.state(PLAYER);
        assertEq(pending, 1);
        assertEq(index, 1);
        assertLt(opened, stamp);
        assertEq(h.runAfkingWork(9_000_000).rewardBasis, 1);
    }

    function test_PausedVaultKeepsItsEntryAfterOpeningAndLaterReclaimPasses() public {
        address vault = ContractAddresses.VAULT;
        uint24 day = h.seed(vault, address(0xBB22), 1);
        uint32 vaultId = h.idOf(vault);
        vm.prank(vault);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(vaultId, false, false, 0, 0, 0);
        h.deliver();
        MineFlipGas.Result memory opened = h.runAfkingWork(9_000_000);
        assertTrue(opened.done);
        assertEq(opened.rewardBasis, 1, "the already-paid box still opens");
        assertEq(h.runAfkingWork(9_000_000).rewardBasis, 0, "no repeated open");

        vm.prank(vault);
        h.subscribe(vaultId, false, false, 0, 0, 0);
        for (uint256 i; i < 3; ++i) {
            day = h.nextProcessDay();
            MineFlipGas.Result memory staged = h.runSubscriberWork(day, 9_000_000);
            assertTrue(staged.done, "a paused Vault cannot stall purchasing");
            (uint256 pending, uint256 members, uint256 index, uint24 stamp, uint24 lastOpened, uint8 qty) = h.state(vault);
            assertEq(pending, 0);
            assertEq(members, 1, "Vault retains the counted entry");
            assertEq(index, 1, "Vault retains its set position");
            assertEq(qty, 0, "Vault stays paused");
            assertEq(lastOpened, stamp, "no new box purchased");
            h.deliver();
        }
    }

    function test_EmptySectionNeverForfeitsUnresolvedCount() public {
        h.seed(PLAYER, address(0), 1);
        h.deliver();
        h.corruptEmptySet();
        vm.expectRevert(bytes4(keccak256("E()")));
        h.runAfkingWork(9_000_000);
        (uint256 pending,,, uint24 stamp, uint24 opened,) = h.state(PLAYER);
        assertEq(pending, 1);
        assertLt(opened, stamp);
        assertFalse(h.complete());
    }
}
