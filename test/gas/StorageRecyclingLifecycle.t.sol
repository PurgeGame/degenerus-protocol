// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";

/// @dev Actual purchases, callbacks and keeper calls; no queue/completion/storage seeding.
///      Also runs against the baseline with RECYCLED_STORAGE=false for payer comparison.
contract StorageRecyclingLifecycleTest is DeployProtocol {
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
            try game.mineFlip() {
                keeperRefund += _refundLastCall();
                uint256 used = vm.snapshotGasLastCall("lifecycle-keeper");
                keeperGas += used;
                if (used > maxKeeperGas) maxKeeperGas = used;
            } catch (bytes memory reason) {
                assertEq(bytes4(reason), bytes4(keccak256("NoWork()")), "real lifecycle stopped on unfinished required work");
                assertFalse(game.rngLocked(), "NoWork cannot leave a locked daily stage");
                return;
            }
        }
        fail("real lifecycle exhausted bounded keeper calls");
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
            uint256 bits = uint256(game.extsload(bytes32(uint256(75) + (lvl & 1))));
            uint256 count = recycled ? ((bits >> trait) & 1 != 0 ? uint32(header) : 0) : header;
            occurrences += count;
            words += (count + 7) / 8;
        }
        if (occurrences > maxOccurrences[lvl]) maxOccurrences[lvl] = occurrences;
        if (words > maxWords[lvl]) maxWords[lvl] = words;
    }

    function test_CurrentSourceVolumeAndPayerCostsThroughRepeatedRetirement() public {
        vm.recordLogs();
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
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 legacyTraits = keccak256("TraitsGenerated(address,uint256,uint32)");
        bytes32 entries = keccak256("EntriesQueued(address,uint24,uint32)");
        bytes32 scaled = keccak256("EntriesQueuedScaled(address,uint24,uint32)");
        bytes32 range = keccak256("EntriesQueuedRange(address,uint24,uint24,uint24,uint32)");
        bytes32 boxes = keccak256("LootBoxBuy(address,uint48,uint256)");
        bytes32 bet = keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory row = logs[i];
            if (row.emitter != address(game) || row.topics.length == 0) continue;
            if (row.topics.length == 4 && uint256(row.topics[0]) < (uint256(1) << 184)
                && row.data.length == 32) {
                uint256 mask = abi.decode(row.data, (uint256)) >> 128;
                for (uint256 seat; seat < 4; ++seat) {
                    uint256 lvl = uint256(row.topics[seat]) >> 160;
                    if (lvl >= 32) continue;
                    for (uint256 lane; lane < 4; ++lane) generated[lvl] += (mask >> (seat * 4 + lane)) & 1;
                }
            } else if (row.topics[0] == legacyTraits) {
                (uint256 baseKey, uint32 take) = abi.decode(row.data, (uint256, uint32));
                uint256 lvl = baseKey >> 224;
                if (lvl < 32) generated[lvl] += take;
            } else if (row.topics[0] == entries || row.topics[0] == scaled) {
                (uint24 lvl, uint32 n) = abi.decode(row.data, (uint24, uint32));
                if (lvl < 32) queued[lvl] += row.topics[0] == scaled ? n / 100 : n;
            } else if (row.topics[0] == range) {
                (uint24 start, uint24 length, uint24 stride, uint32 n) = abi.decode(row.data, (uint24, uint24, uint24, uint32));
                for (uint256 j; j < length && start + j * stride < 32; ++j) queued[start + j * stride] += n;
            } else if (row.topics[0] == boxes && uint256(row.topics[2]) < 256) ++boxBuys[uint256(row.topics[2])];
            else if (row.topics[0] == bet && uint256(row.topics[2]) < 256) ++bets[uint256(row.topics[2])];
        }
        emit log_named_uint("purchase plus bet gas", purchaseGas);
        emit log_named_uint("purchase/bet capped call refunds", purchaseRefund);
        emit log_named_uint("callback gas", callbackGas);
        emit log_named_uint("callback capped call refunds", callbackRefund);
        emit log_named_uint("keeper gas", keeperGas);
        emit log_named_uint("keeper capped call refunds", keeperRefund);
        emit log_named_uint("max individual keeper gas", maxKeeperGas);
        for (uint256 lvl; lvl < 32; ++lvl) if (queued[lvl] != 0 || maxOccurrences[lvl] != 0) {
            emit log_named_uint("level", lvl);
            emit log_named_uint("queued entries at level", queued[lvl]);
            emit log_named_uint("generated trait occurrences from events", generated[lvl]);
            emit log_named_uint("observed generated trait occurrences", maxOccurrences[lvl]);
            emit log_named_uint("observed occupied trait words", maxWords[lvl]);
        }
        for (uint256 index; index < 256; ++index) if (boxBuys[index] != 0 || bets[index] != 0) {
            emit log_named_uint("cohort", index);
            emit log_named_uint("box purchase events", boxBuys[index]);
            emit log_named_uint("bet events", bets[index]);
        }
    }
}
