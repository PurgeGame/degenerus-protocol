// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {C1Viewer} from "../repro/C1BoxAutoOpen.t.sol";

/// @title LootboxTicketLanesFlush -- every box's announced future level receives exactly its entries
/// @notice A box open announces each box's target level and whole-ticket roll in `LootBoxOpened`
///         and accumulates the tickets per level offset; the entry's flush then walks the
///         populated offsets with a six-step lowest-set-bit search and queues each level once.
///         Mutation v78 broke one step of that walk (`scan & 0xF` to `scan * 0xF`) and survived:
///         nothing had checked that the queued levels are the announced ones. Twenty boxes spread
///         over the target band pin the walk lane by lane.
contract LootboxTicketLanesFlush is DeployProtocol {
    address internal actor;

    bytes32 internal constant OPENED =
        keccak256("LootBoxOpened(address,uint48,uint256,uint24,uint32,uint256,bool)");
    bytes32 internal constant QUEUED = keccak256("EntriesQueued(address,uint24,uint32)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("tierActor");
        vm.deal(actor, 100 ether);
    }

    function _idx() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _word(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(C1Viewer).runtimeCode);
        v = C1Viewer(payable(address(game))).rngWordFor(index);
        vm.etch(address(game), real);
    }

    /// @dev Point the permissionless open walk at `index` (cursor 0), as the auto-open repro does.
    function _parkBoxFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(56));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));
        packed &= ~(m << (13 * 8));
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 10 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
            if (game.rngLocked()) break;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        for (uint256 i; i < 10 && game.rngLocked(); i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("dailyword", i))) | 1) {} catch {}
                }
            }
            vm.prank(actor);
            try game.advanceGame() {} catch {}
        }
    }

    /// @dev Tally one open's announcements and queue writes per level offset from `base`.
    function _tally(Vm.Log[] memory logs, uint48 N, uint256 base)
        internal
        returns (uint256[64] memory announced, uint256[64] memory queued, uint256 boxes)
    {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == OPENED && address(uint160(uint256(logs[i].topics[1]))) == actor
                && uint48(uint256(logs[i].topics[2])) == N) {
                (, uint24 lvl, uint32 scaled,, bool up) = abi.decode(logs[i].data, (uint256, uint24, uint32, uint256, bool));
                uint256 whole = scaled / 100 + (up ? 1 : 0);
                assertGe(lvl, base, "a box targets the live level or later");
                assertLt(lvl - base, 64, "and within the band");
                announced[lvl - base] += whole * 4;
                boxes++;
            } else if (logs[i].topics[0] == QUEUED && address(uint160(uint256(logs[i].topics[1]))) == actor) {
                (uint24 lvl, uint32 entries) = abi.decode(logs[i].data, (uint24, uint32));
                assertGe(lvl, base, "queued at the live level or later");
                assertLt(lvl - base, 64, "and within the band");
                assertEq(queued[lvl - base], 0, "each level is queued exactly once per entry");
                queued[lvl - base] += entries;
            }
        }
    }

    /// @dev The lane shape the six-step walk is most easily wrong about: a populated offset in
    ///      the high nibble of a byte whose low nibble is empty (the `& 0xF` step must fire).
    function _hasIsolatedHighNibbleLane(uint256[64] memory announced) internal pure returns (bool) {
        for (uint256 k = 4; k < 64; k++) {
            if (announced[k] == 0 || (k & 7) < 4) continue;
            uint256 b = k & ~uint256(7);
            if (announced[b] == 0 && announced[b + 1] == 0 && announced[b + 2] == 0 && announced[b + 3] == 0) return true;
        }
        return false;
    }

    function test_flushQueuesEachAnnouncedLevelExactlyOnce() public {
        _driveDailyCycleOnce();
        assertFalse(game.rngLocked(), "stage: mid-day path reachable");
        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint48 N = _idx();
        // Thirty smalls spread over the target band, plus a one-ETH custom so the pending ETH
        // clears the mid-day request threshold.
        vm.prank(actor);
        game.purchase{value: 30 * priceWei + 2 ether}(actor, 400, BoxOrderLib.boOrder(30, 0, 0, 1, 1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(actor);
        game.requestLootboxRng();
        uint256 reqId = mockVRF.lastRequestId();
        uint256 base = game.level();

        // Search the word for a draw whose lanes include an isolated high-nibble offset, so every
        // step of the walk is exercised; the word only moves the boxes' targets.
        uint256[64] memory announced;
        uint256[64] memory queued;
        uint256 boxes;
        bool found;
        for (uint256 w = 1; w <= 96 && !found; w++) {
            uint256 snap = vm.snapshotState();
            mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("lane_word", w))) | 1);
            assertGt(_word(N), 0, "the word landed at the order's index");
            _parkBoxFrontier(N);
            vm.recordLogs();
            vm.prank(actor);
            assertGt(game.openBoxes(100), 0, "the walk opened the order");
            (announced, queued, boxes) = _tally(vm.getRecordedLogs(), N, base);
            if (_hasIsolatedHighNibbleLane(announced)) found = true;
            else vm.revertToState(snap);
        }
        assertTrue(found, "some word populates an isolated high-nibble lane");
        assertGe(boxes, 15, "most of the boxes opened plainly");

        // A box that drew a spin announces nothing here but may still queue tickets, so a level
        // may hold MORE than its plain boxes announced; it can never hold less, and a mis-walked
        // lane would leave an announced level short.
        uint256 lanes;
        for (uint256 k; k < 64; k++) {
            assertGe(queued[k], announced[k], "a level receives at least the entries its boxes announced");
            if (announced[k] != 0) {
                lanes++;
                emit log_named_uint("populated lane offset", k);
            }
        }
        assertGe(lanes, 3, "the boxes spread over several lanes");
    }
}
