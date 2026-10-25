// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract AfkingMembershipHarness is DegenerusGameBoxModule, WalletSeed {
    /// @dev A completed pass with `pending`'s box paid and unopened; `clean` is an unpaid-for
    ///      member of the same cohort. The pass endpoint is the process day.
    function seed(address pending, address clean, uint8 quantity) external returns (uint24 processDay) {
        _seedProtocolWallets();
        dailyIdx = _wallDay();
        dailyComplete = true; lastDailyRequestWallDay = _wallDay();
        lastDailyCompletedAt = uint48(block.timestamp);
        processDay = dailyIdx + 1;
        _afkingResetDay = processDay;
        _afkingEndpointDay = processDay;
        _setRngComplete(true);
        _setRngSessionPublished(true);
        rngWordCurrent = 0xAFAF;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        uint32 pendingId = _seedWallet(pending);
        _seedMember(pendingId, quantity, processDay);
        if (pendingId == VAULT_WALLET_ID) _afkingProtocolFlags |= AFK_VAULT_BOUGHT;
        _afkingCohortPriceMilli = 10;
        _pendingBoxCount = 1;
        if (clean != address(0)) _seedMember(_seedWallet(clean), 1, processDay - 1);
    }
    function _seedMember(uint32 id, uint8 quantity, uint24 checkpointDay) private {
        _seedSubscriber(id, false);
        uint256 position = _subPosition1(id) - 1;
        _setSubLaneAt(position, _withSubCheckpoint(
            _subLaneAt(position) | ((uint256(quantity) - 1) << SUB_QTY_SHIFT), checkpointDay, 0));
    }
    /// @dev Mark `player`'s run as seized, as the loan seizure does.
    function markSeized(address player) external {
        (uint256 lane, uint256 position1) = _subLaneOf(_walletIdOf(player));
        _setSubLaneAt(position1 - 1, lane | SUB_REMOVAL_BIT);
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
    function complete() external view returns (bool) { return _rngComplete(); }
    function protocolFlags() external view returns (uint8) { return _afkingProtocolFlags; }
    function state(address player) external view returns (uint256 count, uint256 members, uint256 position1, bool boxPending, uint256 quantity) {
        uint256 lane;
        (lane, position1) = _subLaneOf(_walletIdOf(player));
        // The lane has no open marker: the box is pending while the opener has not passed it.
        boxPending = position1 != 0 && _pendingBoxCount != 0
            && position1 <= _subBoxCount && position1 - 1 >= _subOpenCursor;
        return (_pendingBoxCount, _subscribers.length, position1, boxPending, position1 == 0 ? 0 : _subQuantity(lane));
    }
}

contract AfkingPendingMembershipTest is Test {
    AfkingMembershipHarness private h;
    address private constant PLAYER = address(0xAA11);

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        h = new AfkingMembershipHarness();
        vm.etch(ContractAddresses.GAME, address(h).code);
        vm.copyStorage(address(h), ContractAddresses.GAME);
        h = AfkingMembershipHarness(ContractAddresses.GAME);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending_g153837()"), abi.encode(false));
        vm.mockCall(ContractAddresses.QUESTS, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.AFFILIATE, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.WWXRP, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.COINFLIP, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.GAME_LOOTBOX_MODULE, bytes(""), bytes(""));
    }

    function test_CancellationWaitsForPendingBoxToOpen() public {
        h.seed(PLAYER, address(0), 1);
        uint32 playerId = h.idOf(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(playerId, false, 0, 0);
        h.deliver();
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(playerId, false, 0, 0);
        MineFlipGas.Result memory result = h.runAfkingWork_g8553(9_000_000);
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        vm.prank(PLAYER);
        h.subscribe(playerId, false, 0, 0);
        (uint256 pending, uint256 members, uint256 position1, bool boxPending, uint256 qty) = h.state(PLAYER);
        assertEq(pending, 0);
        assertEq(members, 0, "a cancel removes the member at once");
        assertEq(position1, 0);
        assertFalse(boxPending);
        assertEq(qty, 0);
    }

    function test_PendingModeChangeIsRejectedWithoutLosingPaidBox() public {
        h.seed(PLAYER, address(0), 1);
        h.deliver();
        uint32 id = h.idOf(PLAYER);
        vm.prank(PLAYER);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(id, true, 1, 0);
        (uint256 pending,, uint256 position1, bool boxPending,) = h.state(PLAYER);
        assertEq(pending, 1);
        assertEq(position1, 1);
        assertTrue(boxPending);
        assertEq(h.runAfkingWork_g8553(9_000_000).rewardBasis, 1);
    }

    function test_PausedVaultKeepsItsEntryAfterOpeningAndLaterPassesSkipIt() public {
        address vault = ContractAddresses.VAULT;
        uint24 day = h.seed(vault, address(0xBB22), 1);
        uint32 vaultId = h.idOf(vault);
        vm.prank(vault);
        vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
        h.subscribe(vaultId, false, 0, 0);
        h.deliver();
        MineFlipGas.Result memory opened = h.runAfkingWork_g8553(9_000_000);
        assertTrue(opened.done);
        assertEq(opened.rewardBasis, 1, "the already-paid box still opens");
        assertEq(h.runAfkingWork_g8553(9_000_000).rewardBasis, 0, "no repeated open");

        vm.prank(vault);
        h.subscribe(vaultId, false, 0, 0);
        assertEq(h.protocolFlags() & 4, 4, "the owner's pause is set");
        for (uint256 i; i < 3; ++i) {
            day = h.nextProcessDay();
            MineFlipGas.Result memory staged = h.runSubscriberWork_g6352(day, 9_000_000);
            assertTrue(staged.done, "a paused Vault cannot stall purchasing");
            (uint256 pending, uint256 members, uint256 position1, bool boxPending, uint256 qty) = h.state(vault);
            assertEq(pending, 0, "no new box purchased");
            assertEq(members, 1, "the unfunded member left, the Vault stays");
            assertEq(position1, 1, "Vault retains its set position");
            assertFalse(boxPending);
            assertEq(qty, 1, "the lane keeps its quantity");
            h.deliver();
        }
    }

    function test_SeizedRunIsRemovedByTheNextPassBeforeItBuys() public {
        h.seed(PLAYER, address(0xBB22), 1);
        h.deliver();
        assertTrue(h.runAfkingWork_g8553(9_000_000).done);
        h.markSeized(PLAYER);
        // Until the next pass the closed run keeps its place.
        (, uint256 members, uint256 position1,,) = h.state(PLAYER);
        assertEq(members, 2);
        assertEq(position1, 1);

        uint24 day = h.nextProcessDay();
        vm.recordLogs();
        h.runSubscriberWork_g6352(day, 9_000_000);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool expired;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("SubscriptionExpired(uint32,uint8)")
                && uint32(uint256(logs[i].topics[1])) == h.idOf(PLAYER)) {
                expired = true;
                assertEq(abi.decode(logs[i].data, (uint8)), 2, "reason 2: seized");
            }
        }
        assertTrue(expired, "SubscriptionExpired emitted");
        (uint256 pending,, uint256 afterPosition,,) = h.state(PLAYER);
        assertEq(afterPosition, 0, "the seized run is gone");
        assertEq(pending, 0, "it bought nothing");
    }
}
