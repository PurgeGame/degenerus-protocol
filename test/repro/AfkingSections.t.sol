// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameBoxModule} from "../../contracts/modules/DegenerusGameBoxModule.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract AfkingSectionsHarness is DegenerusGameBoxModule, WalletSeed {
    constructor() {
        _seedProtocolWallets(); dailyIdx = _wallDay();
        dailyComplete = true; lastDailyRequestWallDay = _wallDay();
        lastDailyCompletedAt = uint48(block.timestamp);
    }

    function put(address owner, bool tickets) external returns (uint32 id) {
        id = _seedWallet(owner);
        _insertMember(id, uint256(id) | (tickets ? SUB_TICKETS_BIT : 0), _wallDay());
    }
    function remove(uint32 id) external {
        _removeFromSet(_subPosition1(id));
        _setSubMetaLane(id, 0);
    }
    function book() external view returns (uint256, uint256) { return (_subscribers.length, _subBoxCount); }
    function at(uint256 p) external view returns (uint32) { return uint32(_subLaneAt(p)); }
    function position(uint32 id) external view returns (uint256) { return _subPosition1(id); }
    function owner(uint32 id) external view returns (address) { return _walletKey(id); }
    function setGate(uint8 mode) external {
        uint24 day = _wallDay();
        dailyIdx = mode == 1 ? day - 1 : day;
        lastDailyRequestWallDay = mode == 1 ? day - 1 : day;
        _afkingResetDay = mode == 2 ? day + 1 : day;
        rngLockedFlag = mode == 3;
        _pendingBoxCount = mode == 4 ? 1 : 0;
    }
    function seedOpen(uint24 day) external {
        dailyIdx = day;
        _afkingResetDay = day;
        rngWordCurrent = 991;
        ticketsFullyProcessed = true;
        humanReadComplete = false;
        _setRngComplete(false);
        _setRngSessionPublished(true);
        _afkingCohortPriceMilli = 10;
        ++_pendingBoxCount;
    }
    function cursor() external view returns (uint256) { return _subOpenCursor; }
    function pending() external view returns (uint256) { return _pendingBoxCount; }
    /// @dev Storage slot of the word holding the first ticket position (2000).
    function ticketWordSlot() external pure returns (bytes32 slot) {
        assembly ("memory-safe") { mstore(0, _subscribers.slot) slot := add(keccak256(0, 32), 666) }
    }
}

contract AfkingSectionsTest is Test {
    AfkingSectionsHarness private h;

    function setUp() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 1 days);
        h = new AfkingSectionsHarness();
        vm.etch(ContractAddresses.GAME, address(h).code);
        vm.copyStorage(address(h), ContractAddresses.GAME);
        h = AfkingSectionsHarness(ContractAddresses.GAME);
        vm.mockCall(ContractAddresses.QUESTS, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.AFFILIATE, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.WWXRP, bytes(""), bytes(""));
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending_g153837()"), abi.encode(false));
        vm.mockCall(ContractAddresses.GAME_LOOTBOX_MODULE, bytes(""), bytes(""));
    }

    function _verify(uint32[] memory boxes, uint256 b, uint32[] memory tickets, uint256 t) private view {
        (uint256 n, uint256 actualB) = h.book();
        assertEq(n, b + t);
        assertEq(actualB, b);
        for (uint256 i; i < b; ++i) {
            assertEq(h.at(i), boxes[i]);
            assertEq(h.position(boxes[i]), i + 1);
        }
        for (uint256 i; i < t; ++i) {
            assertEq(h.at(2000 - i), tickets[i]);
            assertEq(h.position(tickets[i]), 2001 - i);
        }
        assertEq(h.at(b), 0, "box sentinel");
        assertEq(h.at(2000 - t), 0, "ticket sentinel");
    }

    function testFuzz_SectionsMatchReferenceUnderSwitchAndRemoval(uint256 seed) public {
        uint32[] memory boxes = new uint32[](80);
        uint32[] memory tickets = new uint32[](80);
        uint256 b;
        uint256 t;
        for (uint256 step; step < 80; ++step) {
            seed = uint256(keccak256(abi.encode(seed, step)));
            bool ticket = seed & 1 != 0;
            uint256 n = ticket ? t : b;
            if (n == 0 || seed % 3 == 0) {
                uint32 id = h.put(address(uint160(0x10000 + step)), ticket);
                if (ticket) tickets[t++] = id;
                else boxes[b++] = id;
            } else {
                uint256 index = (seed >> 32) % n;
                uint32 id = ticket ? tickets[index] : boxes[index];
                bool move = seed & 2 != 0;
                // WalletSeed registers new owners monotonically; IDs identify the owner
                // through the harness wallet table, read via walletElement's public test seam.
                if (move) {
                    // Physical membership move uses exactly the production subscribe path.
                    address owner = h.owner(id);
                    vm.prank(owner);
                    h.subscribe(id, !ticket, 1, 0);
                } else h.remove(id);
                if (ticket) {
                    tickets[index] = tickets[--t];
                    if (move) boxes[b++] = id;
                } else {
                    boxes[index] = boxes[--b];
                    if (move) tickets[t++] = id;
                }
                if (!move) assertEq(h.position(id), 0);
            }
            _verify(boxes, b, tickets, t);
        }
    }

    function test_FullCapacityKeepsSentinelAndMovesAcrossPackedGap() public {
        uint32[] memory boxes = new uint32[](2000);
        uint32[] memory tickets = new uint32[](2000);
        for (uint256 i; i < 2000; ++i) {
            uint32 id = h.put(address(uint160(0x10000 + i)), i >= 1000);
            if (i < 1000) boxes[i] = id;
            else tickets[i - 1000] = id;
        }
        _verify(boxes, 1000, tickets, 1000);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.put(address(0xFFFFF), false);
        vm.prank(address(0x10000));
        h.subscribe(boxes[0], true, 1, 0);
        tickets[1000] = boxes[0];
        boxes[0] = boxes[999];
        _verify(boxes, 999, tickets, 1001);
    }

    function test_AllSubscriptionMutationsWaitAcrossEveryTimingWindow() public {
        address owner = address(0xAA11);
        uint32 id = h.put(owner, false);
        for (uint8 mode = 1; mode <= 4; ++mode) {
            h.setGate(mode);
            for (uint8 quantity; quantity < 2; ++quantity) {
                vm.prank(owner);
                vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
                h.subscribe(id, true, quantity, 0);
            }
            vm.prank(address(0xBB22));
            vm.expectRevert(DegenerusGameStorage.RngLocked.selector);
            h.subscribe(0, false, 1, 0);
            assertEq(h.position(id), 1);
        }
        h.setGate(0);
        vm.prank(owner);
        h.subscribe(id, true, 1, 0);
        assertEq(h.position(id), 2001, "unlocked switch is immediate");
    }

    function test_OpenerNeverReadsTicketsAndProtocolSkipIsMandatoryProgress() public {
        h.put(ContractAddresses.VAULT, false);
        h.put(address(0xAA11), false);
        h.put(address(0xBB22), true);
        uint24 day = uint24((block.timestamp - 82_620) / 1 days);
        h.seedOpen(day);
        uint256 budget = MineFlipGas.budget(16_000_000, type(uint32).max, true);
        bytes32 ticketSlot = h.ticketWordSlot();
        vm.record();
        MineFlipGas.Result memory result = h.runAfkingWork_g8553(budget);
        (bytes32[] memory reads,) = vm.accesses(address(h));
        for (uint256 i; i < reads.length; ++i) assertTrue(reads[i] != ticketSlot);
        assertTrue(result.progressed);
        assertFalse(result.done);
        assertEq(result.rewardBasis, 0);
        assertEq(h.cursor(), 1);
        result = h.runAfkingWork_g8553(budget);
        assertTrue(result.done);
        assertEq(result.rewardBasis, 1);
        assertEq(h.pending(), 0);
        assertEq(h.cursor(), 2);
    }
}
