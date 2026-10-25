// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DegenerusGameLootboxModule} from "../../contracts/modules/DegenerusGameLootboxModule.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {QueueHost} from "../helpers/BoxQueueHost.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {EvTaperRef} from "../helpers/EvTaperRef.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

contract EvOpenHost is QueueHost {
    function seed(address player, uint24 key, uint256 used) external returns (uint32 id) {
        (id,) = _registerWallet(player, 1 ether);
        mintPacked_[id] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
        _setLootboxEvUsedFor(id, key, used);
    }

    function capSlot(uint32 id) external pure returns (bytes32 slot) {
        uint256 base;
        assembly ("memory-safe") { base := lootboxEvCapPacked.slot }
        return keccak256(abi.encode(id, base));
    }

    function multiplier(uint16 score) external pure returns (uint256) { return _lootboxEvMultiplierFromScore(score); }

    function next() external {
        uint48 b = _rngReadBuffer();
        uint256 p = boxCursor;
        require(p < boxReadCount, "end");
        boxCursor = uint48(p + 1);
        _call(abi.encodeWithSignature("resolveHumanBoxOrder(uint48,uint256,uint256,uint256,uint24)",
            b, p, _boxEntryAt(b, p), _lootboxWord(b), level + 1));
    }

    function scoredSingle(uint32 id, uint256 amount, uint16 score, uint256 word, bool afk) external {
        _call(afk
            ? abi.encodeWithSignature("resolveAfkingBox(uint32,uint256,uint24,uint256,uint16)", id, amount, uint24(1), word, score)
            : abi.encodeWithSignature("resolveLootboxDirect(uint32,uint256,uint256,uint16)", id, amount, word, score));
    }

    function _call(bytes memory input) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(input);
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}

/// @dev Preserve the folded production parent while observing the child seam.
/// The child stops here, just as the original external resolver probe did, so
/// its own recirculated box cannot consume a second independent EV allowance.
contract EvNestedProbe is DegenerusGameLootboxModule, DegenerusGameBoonModule {
    uint256 private immutable EXPECTED;
    event CapSeen(uint256 used);
    constructor(uint256 expected) { EXPECTED = expected; }
    function _boxResolveEthSpinFromBox(uint32 id, uint256, uint16, uint256, uint8) internal override {
        uint256 used = _lootboxEvUsedFor(id, level + 1);
        require(used == EXPECTED, "parent must draw before child");
        emit CapSeen(used);
    }
    function _boxResolveFlipSpinsFromBox(uint32, uint256, uint16, uint256, uint8) internal pure override returns (uint256) { return 0; }
    function _boxResolveWwxrpSpinFromBox(uint32, uint256, uint16, uint256, uint8) internal pure override returns (uint256) { return 0; }
}

contract EvBoonFailure {
    fallback() external payable { revert("boon failed"); }
}

contract LootboxEvAtOpenTest is DeployProtocol {
    EvOpenHost private host;
    address private constant PLAYER = address(0xE7CA9);
    uint32 private id;
    uint24 private key;
    bytes32 private constant OPENED = keccak256("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");

    function setUp() public {
        _deployProtocol();
        vm.setNonce(address(this), 1024);
        vm.etch(address(game), type(EvOpenHost).runtimeCode);
        host = EvOpenHost(payable(address(game)));
        key = host.currentLvl() + 1;
        id = host.seed(PLAYER, key, 0);
        vm.deal(PLAYER, 1000 ether);
        vm.deal(address(game), 100_000 ether);
    }

    function _buy(uint256 order) private {
        (, uint256 cost) = host.decode(order, host.activeLevel());
        vm.prank(PLAYER);
        host.purchaseOrderFor{value: cost}(0, 0, order, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    function _word(uint48 b, uint256 p, bool nested) private view returns (uint256 w) {
        for (w = 2; ; ++w) {
            uint256 root = EntropyLib.hash3(20, w, p);
            uint256 seed = EntropyLib.hash3(19, root, 1);
            uint256 roll = uint16(seed >> 40) % 20;
            if (nested ? roll == 19 : roll < 8) return w;
        }
    }

    function _openedAmount(Vm.Log[] memory logs) private pure returns (uint256) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == OPENED) return abi.decode(logs[i].data, (uint256));
        }
        revert("no box event");
    }

    function _capWrites(VmSafe.AccountAccess[] memory accesses) private view returns (uint256 n) {
        bytes32 slot = host.capSlot(id);
        for (uint256 i; i < accesses.length; ++i) {
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory s = accesses[i].storageAccesses[j];
                if (s.account == address(host) && s.slot == slot && s.isWrite && !s.reverted) ++n;
            }
        }
    }

    function test_BuyAfterPublicationCannotTakePendingAllowance() public {
        _buy(BoxOrderLib.boCustom(1 ether));
        uint48 b = host.writeBuffer();
        assertEq(BoxOrderLib.boHighBits(host.entryAt(b, 0)), 0, "no EV field in the entry");
        assertEq(host.evUsed(id, key), 0);
        host.sealAndPublish(_word(b, 0, false));
        vm.startStateDiffRecording();
        _buy(BoxOrderLib.boCustom(40 ether));
        assertEq(_capWrites(vm.stopAndReturnStateDiff()), 0, "no cap write on purchase");
        assertEq(host.evUsed(id, key), 0);
        host.next();
        assertEq(host.evUsed(id, key), 1 ether, "only sealed order consumed allowance");
    }

    function test_StoredPriceButOpeningLevelAllowance() public {
        _buy(BoxOrderLib.boSmalls(1));
        uint48 b = host.writeBuffer();
        uint256 entry = host.entryAt(b, 0);
        uint256 nominal = BoxOrderLib.boNominal(entry);
        host.seed(PLAYER, key, 40 ether);
        host.setLevel(99);
        host.sealAndPublish(_word(b, 0, false));
        vm.recordLogs();
        host.next();
        uint256 amount = _openedAmount(vm.getRecordedLogs());
        assertEq(host.evUsed(id, key), 40 ether);
        assertEq(host.evUsed(id, 100), nominal);
        assertEq(amount, nominal * host.multiplier(uint16(BoxOrderLib.boScore(entry))) / 10_000);
    }

    function testFuzz_TaperAtOpen(uint96 rawUsed, uint64 rawSpend) public {
        uint256 used = bound(rawUsed, 0, 40 ether);
        // Grants are whole 0.001 ETH per box, at most 2,000 ETH (the producers' bound).
        uint256 spend = bound(rawSpend, 1, 2_000_000) * 0.001 ether;
        host.seed(PLAYER, key, used);
        host.grant(PLAYER, spend, 30_000, false, 0);
        uint48 b = host.writeBuffer();
        host.sealAndPublish(_word(b, 0, false));
        vm.recordLogs();
        host.next();
        uint256 amount = _openedAmount(vm.getRecordedLogs());
        (uint256 eligible, uint256 usedAfter) = EvTaperRef.eligible(used, spend);
        uint256 fraction = eligible * 10_000 / spend;
        uint256 adjusted = spend * fraction / 10_000;
        uint256 expected = spend + adjusted * 4500 / 10_000;
        assertEq(host.evUsed(id, key), usedAfter);
        assertLe(amount, expected);
        // Independent integral floors once; production floors each segment (at most 2 wei).
        uint256 lower = eligible > 2 ? eligible - 2 : 0;
        adjusted = spend * (lower * 10_000 / spend) / 10_000;
        assertGe(amount, spend + adjusted * 4500 / 10_000);
    }

    function test_GrantDustCanMoveOneBasisPoint() public {
        host.seed(PLAYER, key, 9 ether);
        host.grant(PLAYER, 1 ether + 1, 30_000, false, 0);
        host.sealAndPublish(_word(host.writeBuffer(), 0, false));
        vm.recordLogs();
        host.next();
        uint256 amount = _openedAmount(vm.getRecordedLogs());
        assertEq(host.evUsed(id, key), 10 ether);
        assertEq(amount, 1.45 ether, "represented 1 ETH is wholly eligible");
        uint256 oldFraction = uint256(1 ether) * 10_000 / (1 ether + 1);
        assertEq(oldFraction, 9999);
        assertEq(amount - (1 ether + (1 ether * oldFraction / 10_000) * 4500 / 10_000), 0.000045 ether);
    }

    function test_NeutralPenaltyAndExhaustedSkipWrites() public {
        uint16 neutral;
        while (host.multiplier(neutral) < 10_000) ++neutral;
        assertEq(host.multiplier(neutral), 10_000);
        host.grant(PLAYER, 1 ether, 0, false, 0);
        host.grant(PLAYER, 1 ether, neutral, false, 0);
        host.grant(PLAYER, 1 ether, 30_000, false, 0);
        host.seed(PLAYER, key, 40 ether);
        host.sealAndPublish(13);
        vm.startStateDiffRecording();
        assertTrue(host.work(25_000_000).done);
        assertEq(_capWrites(vm.stopAndReturnStateDiff()), 0);
    }

    function test_MultiAndHundredBoxOrderDrawOnceBeforeNestedReward() public {
        uint256[2] memory orders = [BoxOrderLib.boCustoms(4, 1 ether), BoxOrderLib.boSmalls(100)];
        for (uint256 i; i < orders.length; ++i) {
            uint256 snap = vm.snapshotState();
            _buy(orders[i]);
            uint48 b = host.writeBuffer();
            uint256 entry = host.entryAt(b, 0);
            uint256 nominal = BoxOrderLib.boNominal(entry);
            vm.etch(ContractAddresses.GAME_LOOTBOX_MODULE, address(new EvNestedProbe(nominal)).code);
            host.sealAndPublish(_word(b, 0, true));
            vm.recordLogs();
            vm.startStateDiffRecording();
            host.next();
            assertEq(_capWrites(vm.stopAndReturnStateDiff()), 1, "one parent draw");
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool seen;
            for (uint256 j; j < logs.length; ++j) if (logs[j].topics[0] == keccak256("CapSeen(uint256)")) seen = true;
            assertTrue(seen, "nested probe executed");
            assertEq(host.evUsed(id, key), nominal);
            assertTrue(vm.revertToState(snap));
        }
    }

    function test_RevertRollsBackAndRetryDrawsOnce() public {
        host.grant(PLAYER, 1 ether, 30_000, false, 0);
        host.sealAndPublish(_word(host.writeBuffer(), 0, false));
        bytes memory boonCode = ContractAddresses.GAME_BOON_MODULE.code;
        vm.etch(ContractAddresses.GAME_BOON_MODULE, type(EvBoonFailure).runtimeCode);
        vm.expectRevert(bytes("boon failed"));
        host.work(25_000_000);
        assertEq(host.evUsed(id, key), 0);
        (, uint256 cursor,) = host.readState();
        assertEq(cursor, 0);
        vm.etch(ContractAddresses.GAME_BOON_MODULE, boonCode);
        assertTrue(host.work(25_000_000).done);
        assertEq(host.evUsed(id, key), 1 ether);
        host.work(25_000_000);
        assertEq(host.evUsed(id, key), 1 ether);
    }

    function test_ManualAndDirectShareOpeningBucketAcrossChunksAfkExempt() public {
        host.grant(PLAYER, 6 ether, 30_000, false, 0);
        host.grant(PLAYER, 6 ether, 30_000, false, 0);
        host.sealAndPublish(17);
        // A daily AFKing box opens outside the allowance.
        host.scoredSingle(id, 2 ether, 30_000, 23, true);
        assertEq(host.evUsed(id, key), 0);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        host.work(25_000_000);
        bytes32 wholeLogs = keccak256(abi.encode(vm.getRecordedLogs()));
        uint256 wholeUsed = host.evUsed(id, key);
        assertTrue(vm.revertToState(snap));
        vm.recordLogs();
        host.next();
        host.next();
        assertEq(keccak256(abi.encode(vm.getRecordedLogs())), wholeLogs);
        assertEq(host.evUsed(id, key), wholeUsed);
        // Existing immediate recirculation (including foil over-cap rewards) still shares it.
        host.scoredSingle(id, 1 ether, 30_000, 29, false);
        assertEq(host.evUsed(id, key), wholeUsed + 1 ether);
    }

    function test_ImmediateRecirculationBetweenEntriesStillDrawsAllowance() public {
        host.seed(PLAYER, key, 9 ether);
        host.grant(PLAYER, 6 ether, 30_000, false, 0);
        host.grant(PLAYER, 6 ether, 30_000, false, 0);
        uint48 b = host.writeBuffer();
        uint256 word = _word(b, 1, false);
        host.sealAndPublish(word);
        host.next();
        uint256 before = host.evUsed(id, key);
        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        host.next();
        uint256 uninterrupted = _openedAmount(vm.getRecordedLogs());
        assertTrue(vm.revertToState(snap));
        // The direct resolver is also the existing foil over-cap recirculation route.
        host.scoredSingle(id, 1 ether, 30_000, 29, false);
        assertEq(host.evUsed(id, key), before + 1 ether);
        vm.recordLogs();
        host.next();
        assertLt(_openedAmount(vm.getRecordedLogs()), uninterrupted);
    }

    function test_RedemptionDrawsOnceAndProtocolAfkStaysExempt() public {
        uint256 word = 2;
        while (uint16(EntropyLib.hash3(19, word, 1) >> 40) % 20 >= 8) ++word;
        GameFunding.reserve(1 ether);
        vm.startStateDiffRecording();
        vm.prank(address(sdgnrs));
        host.resolveRedemptionLootbox(id, 1 ether, word, 30_000, 1);
        assertEq(_capWrites(vm.stopAndReturnStateDiff()), 1, "redemption is not charged twice");
        assertEq(host.evUsed(id, key), 1 ether);
        uint32 protocolId = host.walletIdOf_g3120(address(sdgnrs));
        uint256 before = host.evUsed(protocolId, key);
        word = 2;
        while (uint16(EntropyLib.hash3(13, word, protocolId) >> 40) % 20 >= 8) ++word;
        vm.recordLogs();
        host.scoredSingle(protocolId, 1 ether, 30_000, word, true);
        assertEq(_openedAmount(vm.getRecordedLogs()), 1.45 ether);
        assertEq(host.evUsed(protocolId, key), before);
    }
}
