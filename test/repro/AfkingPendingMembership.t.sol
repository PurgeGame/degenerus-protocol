// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract AfkingMembershipHarness is GameAfkingModule, WalletSeed {
    function seed(address pending, address clean, uint8 quantity) external returns (uint24 processDay) {
        dailyIdx = _simulatedDayIndex();
        processDay = dailyIdx + 1;
        _afkingResetDay = processDay;
        _setRngComplete(true);
        _setRngSessionPublished(true);
        rngWordCurrent = 0xAFAF;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        uint32 pendingId = _seedWallet(pending);
        _subscribers.push(pendingId);
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
            _subscribers.push(cleanId);
            _subOf[cleanId].setPosition = 2;
        }
    }
    function idOf(address player) external view returns (uint32) { return _walletIdOf(player); }
    function deliver() external { ++dailyIdx; _setRngComplete(false); }
    function corruptEmptySet() external { delete _subscribers; }
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

    function test_CancellationAndTombstoneReclaimRetainPendingStamp() public {
        uint24 day = h.seed(PLAYER, address(0xBB22), 1);
        uint32 playerId = h.idOf(PLAYER);
        vm.prank(PLAYER);
        h.subscribe(playerId, false, false, 0, 0, 0);
        MineFlipGas.Result memory staged = h.runSubscriberWork(day, 9_000_000);
        assertTrue(staged.done);
        (uint256 pending, uint256 members, uint256 index, uint24 stamp, uint24 opened, uint8 qty) = h.state(PLAYER);
        assertEq(pending, 1);
        assertEq(members, 1, "only the clean tombstone was removed");
        assertEq(index, 1);
        assertEq(stamp, day);
        assertLt(opened, stamp);
        assertEq(qty, 0, "cancelled stamp remains reachable");
        h.deliver();
        MineFlipGas.Result memory result = h.runAfkingWork(9_000_000);
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        (pending, members, index, stamp, opened,) = h.state(PLAYER);
        assertEq(pending, 0);
        assertEq(opened, stamp);
        assertEq(members, 1);
    }

    function test_UnderfundedPendingSubscriberCannotBeEvicted() public {
        uint24 day = h.seed(PLAYER, address(0), 1);
        h.runSubscriberWork(day, 9_000_000);
        (uint256 pending, uint256 members, uint256 index, uint24 stamp, uint24 opened,) = h.state(PLAYER);
        assertEq(pending, 1);
        assertEq(members, 1);
        assertEq(index, 1);
        assertLt(opened, stamp);
    }

    /// @dev A count no ring member can satisfy is forfeited: the stage completes and the
    ///      session certifies instead of reselecting this stage; the stamp itself is untouched.
    function test_EmptySetForfeitsUnresolvedCountAndCertifiesCompletion() public {
        h.seed(PLAYER, address(0), 1);
        h.deliver();
        h.corruptEmptySet();
        MineFlipGas.Result memory result = h.runAfkingWork(9_000_000);
        assertTrue(result.done);
        assertTrue(result.progressed);
        assertEq(result.rewardBasis, 0, "no box opened");
        (uint256 pending,,, uint24 stamp, uint24 opened,) = h.state(PLAYER);
        assertEq(pending, 0, "phantom count cleared");
        assertLt(opened, stamp, "the orphaned stamp is not written");
        assertTrue(h.complete(), "the read cohort certified");
    }
}
