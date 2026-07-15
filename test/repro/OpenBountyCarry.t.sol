// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title OpenBountyCarry — forced-split chunks pay ONE aggregate bounty; real batches pay each
/// @notice The weighted open walk can split what a single unweighted call used to drain (a skip
///         run eats budget). The `_openBountyCarry` netting must make the split chunks'
///         aggregate bounty equal the unsplit call's — WITHOUT under-paying genuinely separate
///         batches. Two discriminating cases:
///         (1) 80 pending boxes behind a 22-skip prefix (one old-call batch, forced to split):
///             chunk 1 pays the full knee bounty, chunk 2 (the spill-over open) pays ZERO.
///         (2) ~100 organically-stamped boxes (two old-call batches): chunk 2 crosses the
///             OPEN_BATCH boundary, so its beyond-boundary opens open a FRESH knee — both
///             chunks pay a full bounty, matching the two old calls.
contract OpenBountyCarry is DeployProtocol {
    uint256 private constant SUBOF_SLOT = 53;
    uint256 private constant SUBSCRIBERS_SLOT = 55;
    uint256 private constant CURSOR_SLOT = 57;
    uint256 private constant PENDING_SHIFT = 224;
    uint256 private constant CARRY_SHIFT = 240;
    uint256 private constant MINTPACKED_SLOT = 9;
    uint256 private constant DEITY_SHIFT = 184;
    uint256 private constant OFF_LASTBOUGHT = 10;
    uint256 private constant OFF_LASTOPENED = 13;
    uint256 private _lastFulfilledReqId;

    bytes32 private constant STAKE_UPDATED_SIG =
        keccak256("CoinflipStakeUpdated(address,uint24,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }

    /// @notice Case 1: one logical batch (80 boxes) forced to split by a skip prefix —
    ///         aggregate bounty == one full unit (chunk 2 pays zero).
    function testForcedSplitPaysSingleAggregateBounty() public {
        address[] memory subs = _setupFundedSubs(100, "bc1_", 20 ether);
        _runStageNewDay(uint256(keccak256("bc1_w")) | 1);
        _settleClean(uint256(keccak256("bc1_c")) | 1);
        vm.prank(makeAddr("bc1_drain"));
        game.openBoxes(2000);
        require(_pendingCount() == 0, "fixture: drained");

        // Re-arm EXACTLY 80 pending boxes on ring indices [22..101] (0/1 are deploy subs,
        // 2..21 stay clean = the skip prefix), counter = 80, cursor = 0. One old-style call
        // (skips free) would open all 80 → ONE bounty.
        for (uint256 i = 20; i < 100; ++i) {
            _rearmPending(subs[i]);
        }
        _pokeCursorPendingCarry(0, 80, 0);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: open leg live");

        uint256 credit1 = _mintFlipKeeperCredit(makeAddr("bc1_k1"));
        emit log_named_uint("after_chunk1_pending", _pendingCount());
        emit log_named_uint("after_chunk1_carry", _carry());
        emit log_named_uint("chunk1_credit", credit1);
        uint256 credit2 = _mintFlipKeeperCredit(makeAddr("bc1_k2"));
        emit log_named_uint("after_chunk2_pending", _pendingCount());
        emit log_named_uint("chunk2_credit", credit2);

        assertGt(credit1, 0, "chunk 1 pays the full batch bounty");
        assertEq(credit2, 0, "chunk 2 (forced-split spill-over) pays ZERO - the batch was already paid");
        assertEq(_pendingCount(), 0, "both chunks together drained the batch");
        assertEq(_carry(), 0, "carry cleared once the batch drained");
    }

    /// @notice Case 2: two logical batches (~100 organically stamped boxes) — chunk 2's
    ///         beyond-boundary opens start a fresh knee, so BOTH chunks pay a full unit,
    ///         matching the two old-style calls.
    function testTwoRealBatchesEachPayFullBounty() public {
        _setupFundedSubs(100, "bc2_", 20 ether);
        _runStageNewDay(uint256(keccak256("bc2_w")) | 1);
        _settleClean(uint256(keccak256("bc2_c")) | 1);
        uint256 pending = _pendingCount();
        require(pending > 80, "fixture: more than one OPEN_BATCH of organic pending boxes");
        require(!game.advanceDue() && !game.rngLocked(), "fixture: open leg live");

        uint256 credit1 = _mintFlipKeeperCredit(makeAddr("bc2_k1"));
        uint256 credit2 = _mintFlipKeeperCredit(makeAddr("bc2_k2"));

        assertGt(credit1, 0, "chunk 1 pays a full unit (first OPEN_BATCH-worth of opens)");
        assertEq(credit2, credit1, "chunk 2 crosses the batch boundary - its fresh-batch opens pay a full unit too");
        assertEq(_pendingCount(), 0, "two chunks drained the ~100-box backlog");
    }

    // ---- helpers ----

    function _mintFlipKeeperCredit(address keeper) internal returns (uint256 total) {
        vm.recordLogs();
        vm.prank(keeper);
        game.mintFlip();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length > 1 &&
                logs[i].topics[0] == STAKE_UPDATED_SIG &&
                address(uint160(uint256(logs[i].topics[1]))) == keeper
            ) {
                (uint256 amount, ) = abi.decode(logs[i].data, (uint256, uint256));
                total += amount;
            }
        }
    }

    /// @dev Re-arm a drained sub as pending on its already-worded stamp day.
    function _rearmPending(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(SUBOF_SLOT)));
        uint256 w = uint256(vm.load(address(game), slot));
        uint256 bought = (w >> (OFF_LASTBOUGHT * 8)) & 0xFFFFFF;
        require(bought > 0, "rearm: sub was stamped");
        uint256 shift = OFF_LASTOPENED * 8;
        w = (w & ~(uint256(0xFFFFFF) << shift)) | ((bought - 1) << shift);
        vm.store(address(game), slot, bytes32(w));
    }

    function _pokeCursorPendingCarry(uint16 cursor, uint16 pendingCount, uint16 carry) internal {
        uint256 w = uint256(vm.load(address(game), bytes32(CURSOR_SLOT)));
        w = (w & ~(uint256(0xFFFF) << 16)) | (uint256(cursor) << 16);
        w = (w & ~(uint256(0xFFFF) << PENDING_SHIFT)) | (uint256(pendingCount) << PENDING_SHIFT);
        w = (w & ~(uint256(0xFFFF) << CARRY_SHIFT)) | (uint256(carry) << CARRY_SHIFT);
        vm.store(address(game), bytes32(CURSOR_SLOT), bytes32(w));
    }

    function _pendingCount() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(CURSOR_SLOT))) >> PENDING_SHIFT) & 0xFFFF;
    }

    function _carry() internal view returns (uint256) {
        return (uint256(vm.load(address(game), bytes32(CURSOR_SLOT))) >> CARRY_SHIFT) & 0xFFFF;
    }

    function _setupFundedSubs(uint256 n, string memory prefix, uint256 poolEach)
        internal
        returns (address[] memory subs)
    {
        subs = new address[](n);
        for (uint256 i; i < n; ++i) {
            address who = makeAddr(string(abi.encodePacked(prefix, _u(i))));
            subs[i] = who;
            bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
            vm.store(address(game), slot, bytes32(uint256(vm.load(address(game), slot)) | (uint256(1) << DEITY_SHIFT)));
            vm.deal(address(this), poolEach);
            game.depositAfkingFunding{value: poolEach}(who);
            vm.prank(who);
            game.subscribe(address(0), false, false, 1, address(0));
        }
    }

    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        vm.warp(block.timestamp + 1 days);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < 60; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        bytes memory b;
        while (v > 0) {
            b = abi.encodePacked(uint8(48 + (v % 10)), b);
            v /= 10;
        }
        return string(b);
    }
}
