// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @dev Actual purchases, callbacks and keeper calls; no queue/completion/storage seeding.
///      Also runs against the baseline with RECYCLED_STORAGE=false for payer comparison.
///      Owner gas rule (2026-10-03): the engine admits checkpoints while the supplied allowance
///      covers the next declared bound, so a call given unbounded gas measures its own allowance
///      (a whole-lifecycle call reached ~140M). Every keeper call here therefore gets a realistic
///      10M allowance and must either progress or stop on NoWork: a required checkpoint that a
///      10M call cannot admit fails the run. Whole-call figures are logged, never bounded.
contract KeeperGasProfileTest is DeployProtocol {
    /// @dev A realistic mineFlip allowance.
    uint256 internal constant KEEPER_CALL_GAS = 10_000_000;
    DegenerusGameLens lens;
    address[4] buyers;
    uint24[4] boughtFoilAt;
    uint256[32] queued;
    uint256[256] boxBuys;
    uint256[256] bets;
    uint256[32] generated;
    uint256[32] maxOccurrences;
    uint256[32] maxWords;
    bool recycled;
    bool rotateBuyers;
    uint256 purchaseGas;
    uint256 callbackGas;
    uint256 keeperGas;
    uint256 maxKeeperGas;
    uint256 keeperCalls;
    uint256 purchaseRefund;
    uint256 callbackRefund;
    uint256 keeperRefund;
    uint24[2] lastStamp;
    uint256 retirements;

    function setUp() public {
        _deployProtocol();
        lens = new DegenerusGameLens();
        recycled = vm.envOr("RECYCLED_STORAGE", true);
        rotateBuyers = vm.envOr("LIFECYCLE_ROTATE_BUYERS", false);
        mockVRF.fundSubscription(1, 1_000e18);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 4; ++i) {
            buyers[i] = address(uint160(0xCAFE00 + i));
            vm.deal(buyers[i], 10_000 ether);
        }
    }

    /// @dev Refund metadata is diagnostic only. Under FOUNDRY_ISOLATE=true this
    ///      Foundry build already includes intrinsic gas and applies refunds in
    ///      snapshotGasLastCall; never subtract this proxy from the snapshot.
    function _refundLastCall() private view returns (uint256) {
        Vm.Gas memory meter = vm.lastCallGas();
        if (meter.gasRefunded <= 0) return 0;
        uint256 refund = uint256(uint64(meter.gasRefunded));
        uint256 cap = meter.gasTotalUsed / 5;
        return refund < cap ? refund : cap;
    }

    function _purchaseDay(uint256 day) private {
        if (rotateBuyers) for (uint256 i; i < 4; ++i) {
            buyers[i] = address(uint160(0xCAFE00 + day * 4 + i));
            boughtFoilAt[i] = 0;
            vm.deal(buyers[i], 10_000 ether);
        }
        for (uint256 i; i < 4; ++i) {
            (, , , , uint256 price) = game.purchaseInfo();
            uint24 active = lens.activeTicketLevelOf(address(game));
            bool foil = boughtFoilAt[i] != active;
            uint256 quantity = (20 ether / price) * 400;
            uint256 value = price * quantity / 400 + 1 ether + (foil ? price * 10 : 0);
            vm.prank(buyers[i]);
            game.purchase{value: value}(buyers[i], quantity, BoxOrderLib.boCustomFloor(1 ether), bytes32(0), MintPaymentKind.DirectEth, foil);
            purchaseRefund += _refundLastCall();
            purchaseGas += vm.snapshotGasLastCall("lifecycle-purchase");
            if (foil) boughtFoilAt[i] = active;
            vm.prank(buyers[i]);
            game.placeDegeneretteBet{value: 0.01 ether}(address(0), 0, 0.01 ether, 1, 0);
            purchaseRefund += _refundLastCall();
            purchaseGas += vm.snapshotGasLastCall("lifecycle-bet");
        }
    }

    function _drive(uint256 daySeed) private {
        for (uint256 i; i < 512; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(request);
                if (!fulfilled) {
                    mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode(daySeed, request))) | 1);
                    callbackRefund += _refundLastCall();
                    callbackGas += vm.snapshotGasLastCall("lifecycle-callback");
                }
            }
            vm.prank(buyers[0]);
            vm.recordLogs();
            bool sample = false; ++callNo;
            if (sample) vm.resumeTracing();
            try game.mineFlip{gas: KEEPER_CALL_GAS}() {
                keeperRefund += _refundLastCall();
                uint256 used = vm.snapshotGasLastCall("lifecycle-keeper");
                keeperGas += used;
                ++keeperCalls;
                if (used > maxKeeperGas) maxKeeperGas = used;
                _attribute(used);
                if (sample) { vm.pauseTracing(); emit log_named_uint("traced call gas", used); }
            } catch (bytes memory reason) {
                assertEq(bytes4(reason), bytes4(keccak256("NoWork()")), "real lifecycle stopped on unfinished required work");
                assertFalse(game.rngLocked(), "NoWork cannot leave a locked daily stage");
                return;
            }
        }
        fail("real lifecycle exhausted bounded keeper calls");
    }

    uint256 sFreshW; uint256 sDirtyW; uint256 sSameW; uint256 sColdR; uint256 sWarmR; uint256 sClearW; uint256 sCalls; uint256 sGas;

    /// @dev Unique slots per call: first-write class and cold reads (approximate EIP-2929/2200).
    function _storageMix(uint256 used) private {
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        if (used < 1_000_000) return;
        emit log_named_uint("sample call gas", used);
        ++sCalls; sGas += used;
        for (uint256 i; i < acc.length; ++i) {
            Vm.StorageAccess[] memory st = acc[i].storageAccesses;
            for (uint256 j; j < st.length; ++j) {
                bytes32 key = keccak256(abi.encode(st[j].account, st[j].slot));
                if (readEpoch[key] != sCalls) { readEpoch[key] = sCalls; ++sColdR; } else if (!st[j].isWrite) ++sWarmR;
                if (st[j].isWrite && writeEpoch[key] != sCalls) {
                    writeEpoch[key] = sCalls;
                    if (st[j].previousValue == bytes32(0)) ++sFreshW;
                    else if (st[j].newValue == bytes32(0)) ++sClearW;
                    else if (st[j].newValue == st[j].previousValue) ++sSameW;
                    else ++sDirtyW;
                }
            }
        }
    }
    uint256 callNo;
    mapping(bytes32 => uint256) readEpoch;
    mapping(bytes32 => uint256) writeEpoch;

    uint256[64] catGas;
    uint256[64] catCalls;
    uint256[64] catMax;
    bytes32 constant ADV = keccak256("Advance(uint8,uint24)");
    bytes32 constant MB = keccak256("MinerBounty(uint8,address,uint256)");

    /// @dev cat = 32 + stage for advance calls; kind for bounty-only calls; 0 unpaid/skip.
    function _attribute(uint256 used) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 cat;
        uint256 kind;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == ADV) { (uint8 st,) = abi.decode(logs[i].data, (uint8, uint24)); cat = 32 + st; }
            else if (logs[i].topics[0] == MB) { (uint8 k,) = abi.decode(logs[i].data, (uint8, uint256)); kind = k; }
        }
        if (cat == 0) cat = kind;
        catGas[cat] += used; ++catCalls[cat]; if (used > catMax[cat]) catMax[cat] = used;
    }

    /// @dev Canonical live logical buckets; physical encodings intentionally differ.
    function _bucketDigest() private view returns (bytes32 d) {
        bool tails = vm.envOr("HEADER_TAIL", true);
        uint256 bitmapSlot = vm.envOr("TAIL_BITMAP_SLOT", uint256(75));
        uint256 stamps = uint256(game.extsload(bytes32(uint256(5))));
        for (uint256 parity; parity < 2; ++parity) {
            uint24 lvl = uint24(stamps >> (80 + parity * 24));
            uint256 bits = tails ? uint256(game.extsload(bytes32(bitmapSlot + parity))) : 0;
            d = keccak256(abi.encode(d, lvl));
            uint256 base = uint256(keccak256(abi.encode(parity, uint256(8))));
            for (uint256 trait; trait < 256; ++trait) {
                uint256 header = uint256(game.extsload(bytes32(base + trait)));
                uint256 count = tails ? ((bits >> trait) & 1 != 0 ? uint32(header) : 0)
                    : (lvl != 0 && uint24(header >> 232) == lvl ? (header << 24) >> 24 : 0);
                d = keccak256(abi.encode(d, count));
                uint256 data = uint256(keccak256(abi.encode(base + trait)));
                for (uint256 w; w < (count + 7) / 8; ++w) {
                    uint256 word = tails && w == count / 8 ? header >> 32
                        : uint256(game.extsload(bytes32(data + w)));
                    d = keccak256(abi.encode(d, word));
                }
            }
        }
    }

    function _snapshotInventory(uint24 lvl) private {
        if (lvl >= 32) return;
        if (recycled) {
            uint256 packed = uint256(game.extsload(bytes32(uint256(5))));
            if (uint24(packed >> (80 + (lvl & 1) * 24)) != lvl) return;
        }
        uint256 base = uint256(keccak256(abi.encode(uint256(recycled ? lvl & 1 : lvl), uint256(8))));
        uint256 occurrences; uint256 words;
        for (uint256 trait; trait < 256; ++trait) {
            uint256 header = uint256(game.extsload(bytes32(base + trait)));
            uint256 bits = vm.envOr("HEADER_TAIL", true)
                ? uint256(game.extsload(bytes32(vm.envOr("TAIL_BITMAP_SLOT", uint256(75)) + (lvl & 1)))) : 0;
            uint256 count = vm.envOr("HEADER_TAIL", true) ? (((bits >> trait) & 1) != 0 ? uint32(header) : 0)
                : (recycled ? (uint24(header >> 232) == lvl ? (header << 24) >> 24 : 0) : header);
            occurrences += count;
            words += (count + 7) / 8;
        }
        if (occurrences > maxOccurrences[lvl]) maxOccurrences[lvl] = occurrences;
        if (words > maxWords[lvl]) maxWords[lvl] = words;
    }

    function test_KeeperGasProfile() public {
        vm.pauseTracing();
        for (uint256 day; day < 16; ++day) {
            _purchaseDay(day);
            vm.warp(vm.getBlockTimestamp() + 1 days);
            _drive(day);
            if (recycled) {
                uint48 stamps = uint48(uint256(game.extsload(bytes32(uint256(5)))) >> 80);
                for (uint256 slot; slot < 2; ++slot) {
                    uint24 stamp = uint24(stamps >> (slot * 24));
                    if (lastStamp[slot] != 0 && stamp > lastStamp[slot]) ++retirements;
                    lastStamp[slot] = stamp;
                }
            }
            emit log_named_bytes32("day bucket digest", _bucketDigest());
            uint24 lvl = game.level();
            if (lvl > 0) _snapshotInventory(lvl - 1);
            _snapshotInventory(lvl);
            _snapshotInventory(lvl + 1);
            _snapshotInventory(lvl + 2);
        }
        assertGe(game.level(), 3, "must exercise completed levels beyond genesis");
        if (recycled) assertGe(retirements, 3, "must observe actual parity buffer takeovers");
        emit log_named_uint("final completed level", game.level());
        emit log_named_uint("observed parity retirements", retirements);
        for (uint256 i = 1; i < 4; ++i) emit log_named_uint("non-keeper claimable", game.claimableWinningsOf(buyers[i]));
        emit log_named_uint("purchase plus bet gas", purchaseGas);
        emit log_named_uint("purchase/bet capped call refunds", purchaseRefund);
        emit log_named_uint("callback gas", callbackGas);
        emit log_named_uint("callback capped call refunds", callbackRefund);
        emit log_named_uint("keeper gas", keeperGas);
        emit log_named_uint("keeper capped call refunds", keeperRefund);
        emit log_named_uint("max individual keeper gas", maxKeeperGas);
        emit log_named_uint("keeper calls (each at a 10M allowance)", keeperCalls);
        emit log_named_uint("heavy calls (>1M)", sCalls);
        emit log_named_uint("heavy gas", sGas);
        emit log_named_uint("unique slots touched (cold)", sColdR);
        emit log_named_uint("first write zero->nonzero", sFreshW);
        emit log_named_uint("first write nonzero->nonzero", sDirtyW);
        emit log_named_uint("first write unchanged", sSameW);
        emit log_named_uint("first write cleared", sClearW);
        emit log_named_uint("warm reads", sWarmR);
        for (uint256 c; c < 64; ++c) if (catCalls[c] != 0) {
            emit log_named_uint("== category (0 unpaid, 1 miner bounty, 32+stage advance)", c);
            emit log_named_uint("calls", catCalls[c]);
            emit log_named_uint("gas", catGas[c]);
            emit log_named_uint("max", catMax[c]);
        }
    }
}
