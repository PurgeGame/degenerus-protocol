// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MultiLevelHandler} from "./handlers/MultiLevelHandler.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";

/// @title BoxOpeningNeverReverts -- opening queued box orders never reverts on their inputs
/// @notice Owner rule: nothing in mining may revert on immutable inputs. A queued box order's
///         immutable inputs are its 85-bit entry (wallet ID, per-box units, frozen score code,
///         boost, quantity, distress bit), the session word that answers its request, and the
///         open level. Each fuzz run buys one to three real orders through `purchaseOrderFor`
///         (kind, quantity and custom size fuzzed over the whole input domain the purchase
///         accepts), then overwrites each entry's score code (0 to the code of the 30,000-point
///         cap), boost (0 to 2,500 bps, the writer's bound) and distress bit with fuzzed values
///         inside the domain the writers produce, answers the day's request with a fuzzed word,
///         and drives the engine with ordinary 16,777,216-gas mineRun calls until it is idle.
///         Every call must succeed or refuse with NoWork / RngNotReady (answered, then retried),
///         every queued entry must be settled, and every bought box must be rolled (one LootBoxOpened,
///         or one BoxSpin for a spin roll, per box). Run at the
///         level-0 launch fixture and at a mature level reached by the real scripted opening.
abstract contract BoxOpeningNeverRevertsBase is DeployProtocol {
    uint256 private constant CALL_GAS = 16_777_216;
    uint256 private constant MAX_CALLS = 2_000;
    uint256 private constant SCORE_CODE_MAX = 4039; // BoxOrderLib.scoreCode(30_000)
    uint256 private constant BOOST_MAX = 2500;
    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes32 private constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
    /// @dev A spin roll records its own BoxSpin event in place of LootBoxOpened.
    bytes32 private constant SPUN = keccak256("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
    address private constant MINER = address(0x3141);

    struct Order {
        uint8 kind;
        uint8 qty;
        uint32 units;
        uint16 scoreCode;
        uint16 boostBps;
        bool distress;
    }

    address[3] internal buyers = [address(0xB1), address(0xB2), address(0xB3)];
    uint256 private answerSeed;

    function _boxInput(Order memory o) private pure returns (uint256) {
        uint256 qty = bound(o.qty, 1, 100);
        uint256 kind = o.kind % 4;
        uint256 units = kind == 3 ? bound(o.units, 10, 2_000_000) : 0;
        return BoxOrderLib.boInput(kind, qty, units);
    }

    function _fulfill() private returns (bool) {
        uint256 id = mockVRF.lastRequestId();
        if (id == 0) return false;
        (,, bool done) = mockVRF.pendingRequests(id);
        if (done) return false;
        mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode(answerSeed, id))));
        return true;
    }

    function _buy(uint256 i, Order memory o) private returns (uint256 boxes) {
        uint256 input = _boxInput(o);
        uint48 buffer = RecyclingState.writeBuffer(address(game));
        uint256 position = RecyclingState.boxCount(address(game), buffer);
        vm.deal(buyers[i], 10_000_000 ether);
        vm.prank(buyers[i]);
        // Overpay is credited to the buyer's AFKing funding, so a generous value is exact.
        game.purchaseOrderFor{value: 300_000 ether}(0, 0, input, bytes32(0), MintPaymentKind.DirectEth, false);
        assertEq(RecyclingState.boxCount(address(game), buffer), position + 1, "the purchase queued one entry");
        uint256 entry = RecyclingState.boxEntry(address(game), buffer, position);
        boxes = BoxOrderLib.boCount(entry);
        entry = BoxOrderLib.boEntry(BoxOrderLib.boId(entry), BoxOrderLib.boUnits(entry),
            bound(o.scoreCode, 0, SCORE_CODE_MAX), bound(o.boostBps, 0, BOOST_MAX), boxes, o.distress);
        RecyclingState.storeBoxEntry(address(game), buffer, position, entry);
    }

    /// @dev One engine call, as an external self-call so its recorded logs are freed on return.
    ///      status: 1 = the call succeeded, 2 = it waited on a word that is now answered, 0 = idle.
    function mineStep() external returns (uint8 status, uint256 opened) {
        require(msg.sender == address(this), "self only");
        vm.recordLogs();
        _fulfill();
        vm.prank(MINER);
        (bool ok, bytes memory err) =
            address(game).call{gas: CALL_GAS}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        if (ok) {
            for (uint256 i; i < logs.length; ++i) {
                if (logs[i].emitter == address(game) && (logs[i].topics[0] == OPENED || logs[i].topics[0] == SPUN)) {
                    ++opened;
                }
            }
            return (1, opened);
        }
        bytes4 sel = bytes4(err);
        if (err.length != 4 || (sel != NO_WORK && sel != RNG_NOT_READY)) {
            emit log_named_bytes("mineRun reverted", err);
            revert("box opening reverted on its inputs");
        }
        if (sel == RNG_NOT_READY) {
            require(_fulfill(), "engine waits on a word that never comes");
            return (2, 0);
        }
        return (0, 0);
    }

    function _drive() private returns (uint256 opened, uint256 calls) {
        for (uint256 i; i < MAX_CALLS; ++i) {
            (uint8 status, uint256 n) = this.mineStep();
            if (status == 0) return (opened, calls);
            if (status == 1) ++calls;
            opened += n;
        }
        fail("engine did not go idle");
    }

    function _run(Order[3] memory orders, uint8 count, uint256 word) internal {
        answerSeed = word;
        uint256 n = bound(count, 1, 3);
        uint256 boxes;
        uint48 buffer = RecyclingState.writeBuffer(address(game));
        uint256 before = RecyclingState.boxCount(address(game), buffer);
        for (uint256 i; i < n; ++i) boxes += _buy(i, orders[i]);
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        (uint256 opened, uint256 calls) = _drive();
        assertEq(game.nextMinerAction(), 0, "the engine is idle after the drive");
        assertGt(calls, 0, "the drive made progress");
        assertGe(opened, boxes, "every bought box was opened");
        // The sealed buffer's entries all settled: the human-box cursor reached the read count.
        assertTrue(game.rngComplete(), "the read cohort completed, so every entry settled");
        emit log_named_uint("entries before", before);
        emit log_named_uint("boxes bought", boxes);
        emit log_named_uint("boxes opened", opened);
    }
}

contract BoxOpeningNeverRevertsLaunchTest is BoxOpeningNeverRevertsBase {
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    /// forge-config: default.fuzz.runs = 64
    /// forge-config: deep.fuzz.runs = 512
    function testFuzz_BoxOrdersOpenWithoutRevertAtLaunch(Order[3] memory orders, uint8 count, uint256 word) public {
        _run(orders, count, word);
    }
}

contract BoxOpeningNeverRevertsMatureTest is BoxOpeningNeverRevertsBase {
    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        MultiLevelHandler opening = new MultiLevelHandler(game, mockVRF, 1);
        opening.scriptedOpening();
        assertGe(game.currentLvl(), 10, "fixture: real mature opening");
        for (uint256 i; i < 2_000 && game.nextMinerAction() != 0; ++i) {
            uint256 id = mockVRF.lastRequestId();
            (,, bool done) = mockVRF.pendingRequests(id);
            if (id != 0 && !done) mockVRF.fulfillRandomWords(id, uint256(keccak256(abi.encode("mature", id))));
            game.mineRun{gas: 30_000_000}(0);
        }
    }

    /// forge-config: default.fuzz.runs = 24
    /// forge-config: deep.fuzz.runs = 256
    function testFuzz_BoxOrdersOpenWithoutRevertAtAMatureLevel(Order[3] memory orders, uint8 count, uint256 word) public {
        _run(orders, count, word);
    }
}
