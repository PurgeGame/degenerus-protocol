// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenesisGasBase, DegenesisGasHost} from "./DegenesisGas.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisBoonReference as Ref} from "../fuzz/helpers/DegenesisBoonReference.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Full production settlement calls: dispatch, expiry, all deliveries, event, primary,
///         flush and close. Paired native runs remove only the additional boon path.
contract DegenesisBoonGasTest is DegenesisGasBase {
    uint32 private id;
    uint256 private q;

    function setUp() public {
        _deployProtocol();
        _etchHost();
        id = host.hostWallet(address(0xB008));
        q = sdgnrs.poolBalance(sDGNRS.Pool.Degenesis) / 3;
    }

    function _export(string memory label, uint256 word) private {
        host.hostCohort(1, 50_000, 1, true);
        host.hostActive(q, 3, 0);
        host.hostWord(word);
        host.hostOrder(1, 0, id, 50_000, 0);
        this.exportNativeFixture(
            label, address(this), address(host), abi.encodeCall(DegenesisGasHost.hostRun, (type(uint128).max))
        );
    }

    function testNativeColdMixedFamilies() public {
        _export("degenesis-boon-cold-mixed", 1905);
    }

    function testNativeColdActivityAndBothBoonSlots() public {
        _export("degenesis-boon-cold-activity-two-slots", 275);
    }

    function testNativeColdRepeatedTier() public {
        _export("degenesis-boon-cold-repeated", 3103);
    }

    function testNativeColdThreeActivity() public {
        _export("degenesis-boon-cold-activity", 15_071);
    }

    function testNativeColdThreeShields() public {
        _export("degenesis-boon-cold-shields", 3237);
    }

    function testNativeColdWhaleAndActivity() public {
        _export("degenesis-boon-cold-whale", 154);
    }

    function testNativeDeityDiscard() public {
        vm.store(
            address(game),
            keccak256(abi.encode(id, GameSlots.MINT_PACKED)),
            bytes32(uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT)
        );
        _export("degenesis-boon-discard", 3);
    }

    function testNativePopulatedMixedFamilies() public {
        host.hostSeedBoons(id, 5 ether, 426);
        _export("degenesis-boon-populated-mixed", 1905);
    }

    function testNativeExpiryBothPackedSlots() public {
        host.hostSeedBoons(id, 5 ether, 426);
        vm.warp(block.timestamp + 30 days);
        _export("degenesis-boon-expired-mixed", 1905);
    }

    function testNativeLargeActivityAndWhaleBalance() public {
        vm.store(
            address(game),
            keccak256(abi.encode(id, GameSlots.MINT_PACKED)),
            bytes32(uint256(type(uint24).max) << BitPackingLib.LEVEL_COUNT_SHIFT)
        );
        bytes32 slot = bytes32(uint256(keccak256(abi.encode(GameSlots.WALLETS))) + id);
        uint256 element = uint256(vm.load(address(game), slot));
        vm.store(
            address(game),
            slot,
            bytes32((element & ((uint256(1) << 192) - 1)) | ((uint256(type(uint64).max) - 6) << 192))
        );
        uint24 day = game.currentDayView();
        vm.prank(address(game));
        quests.awardQuestStreakBonus(id, type(uint16).max, day);
        vm.prank(address(game));
        quests.awardQuestStreakShield(id, type(uint16).max);
        _export("degenesis-boon-large-whale-activity", 154);
    }

    function testNativeAfkingActivityCallback() public {
        // A real subscription creates the Game and Quests records used by the callback.
        address player = address(0xB008);
        vm.deal(player, 100 ether);
        // Seeding through the production subscription entry is covered by the regular AFKing
        // suites; the host helper mirrors its valid set membership for this isolated call.
        host.hostAfkingBoonMember(id);
        uint24 day = game.currentDayView();
        vm.prank(address(game));
        quests.beginAfking(id, day);
        _export("degenesis-boon-afking-activity", 15_071);
    }

    function testNativeFullThreeDrawChunkAndSeventhClose() public {
        uint256 n = 128;
        for (uint256 i; i < n; ++i) {
            uint32 recipient = host.hostWallet(address(uint160(0xC00800 + i)));
            host.hostOrder(7, i, recipient, 50_000, 0);
        }
        host.hostClosed(6);
        host.hostCohort(7, n * 50_000, n, true);
        host.hostActive(q, 9, 0);
        host.hostWord(275);
        // The storage-access recorder avoids a large nested state-diff transcript.
        string memory label = "degenesis-chunk-three-boons-seventh";
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        uint256 snapshot = vm.snapshotState();
        vm.record();
        bytes memory input = abi.encodeCall(DegenesisGasHost.hostRun, (type(uint128).max));
        _cool();
        vm.recordLogs();
        (bool ok, bytes memory output) = address(host).call(input);
        if (!ok) assembly ("memory-safe") { revert(add(output, 32), mload(output)) }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bool progressed, bool done, uint256 basis) = abi.decode(output, (bool, bool, uint256));
        assertTrue(progressed && done, "full cohort completes");
        assertEq(basis, n, "one reward per order");
        uint256 companions;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != keccak256("DegenesisBoonsRolled(uint32,uint8,uint32,uint24)")) continue;
            (uint8 day, uint32 index, uint24 types_) = abi.decode(logs[i].data, (uint8, uint32, uint24));
            assertEq(day, 7);
            assertEq(index, companions);
            assertEq(types_, Ref.selected(5 ether, Ref.root(275, 7, index)));
            assertEq(Ref.packedCount(types_), 3);
            ++companions;
        }
        assertEq(companions, n);
        assertEq(sdgnrs.poolBalance(sDGNRS.Pool.Degenesis), 0, "seventh close burns inventory");
        if (bytes(dir).length != 0) {
            ChunkAccess[] memory accesses = _chunkAccesses();
            string memory post = "{";
            for (uint256 i; i < accesses.length; ++i) {
                ChunkAccess memory a = accesses[i];
                string memory key = string.concat(label, "-post-", vm.toString(a.account));
                string memory slots = this.chunkStorage(key, a.account, a.reads, a.writes);
                post = string.concat(post, i == 0 ? "" : ",", '"', vm.toString(a.account), '":', slots);
            }
            post = string.concat(post, "}");
            assertTrue(vm.revertToStateAndDelete(snapshot));
            _writeChunk(label, dir, accesses, input, output, logs, post);
        } else {
            vm.deleteStateSnapshot(snapshot);
        }
    }

    struct ChunkAccess {
        address account;
        bytes32[] reads;
        bytes32[] writes;
    }

    /// @dev Every possible callee of this settlement, including shared-host aliases.
    /// Native replay separately rejects any accessed code or slot absent from the export.
    function _chunkAccesses() private returns (ChunkAccess[] memory result) {
        address[14] memory accounts = [
            address(this),
            address(host),
            ContractAddresses.GAME_DEGENESIS_MODULE,
            ContractAddresses.GAME_BOON_MODULE,
            ContractAddresses.GAME_ADVANCE_MODULE,
            ContractAddresses.GAME_WHALE_MODULE,
            address(sdgnrs),
            address(wwxrp),
            address(crapsBattle),
            address(coinflip),
            address(coin),
            address(mockStETH),
            address(mockVRF),
            address(gnrus)
        ];
        result = new ChunkAccess[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
            (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(accounts[i]);
            result[i] = ChunkAccess(accounts[i], reads, writes);
        }
    }

    function chunkStorage(string calldata key, address account, bytes32[] calldata reads, bytes32[] calldata writes)
        external
        returns (string memory)
    {
        require(msg.sender == address(this), "chunk serializer self-call");
        vm.serializeJson(key, "{}");
        for (uint256 i; i < reads.length; ++i) {
            this.nativeSerializeSlot(key, account, reads[i]);
        }
        for (uint256 i; i < writes.length; ++i) {
            this.nativeSerializeSlot(key, account, writes[i]);
        }
        return vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(account, 0));
    }

    function _writeChunk(
        string memory label,
        string memory dir,
        ChunkAccess[] memory accesses,
        bytes memory input,
        bytes memory output,
        Vm.Log[] memory logs,
        string memory post
    ) private {
        string memory state = "{";
        for (uint256 i; i < accesses.length; ++i) {
            ChunkAccess memory a = accesses[i];
            string memory key = string.concat(label, "-pre-", vm.toString(a.account));
            string memory slots = this.chunkStorage(key, a.account, a.reads, a.writes);
            state = string.concat(
                state,
                i == 0 ? "" : ",",
                '"',
                vm.toString(a.account),
                '":{"code":"',
                vm.toString(a.account.code),
                '","balance":"',
                vm.toString(bytes32(a.account.balance)),
                '","nonce":',
                vm.toString(vm.getNonce(a.account)),
                ',"storage":',
                slots,
                "}"
            );
        }
        vm.writeJson(string.concat(state, "}"), string.concat(dir, "/", label, ".state.json"));
        vm.serializeJson(label, "{}");
        vm.serializeAddress(label, "from", address(this));
        vm.serializeAddress(label, "to", address(host));
        vm.serializeBytes(label, "input", input);
        vm.serializeBytes(label, "expectedReturn", output);
        vm.serializeString(label, "expectedStorage", post);
        vm.serializeUint(label, "baseFee", block.basefee);
        vm.serializeUint(label, "number", block.number);
        vm.serializeUint(label, "timestamp", block.timestamp);
        string memory entries = "[";
        for (uint256 i; i < logs.length; ++i) {
            string memory key = string.concat(label, "-log-", vm.toString(i));
            vm.serializeAddress(key, "address", logs[i].emitter);
            vm.serializeBytes(key, "data", logs[i].data);
            string memory entry = vm.serializeBytes32(key, "topics", logs[i].topics);
            entries = string.concat(entries, i == 0 ? "" : ",", entry);
        }
        string memory json = vm.serializeString(label, "expectedLogs", string.concat(entries, "]"));
        vm.writeJson(json, string.concat(dir, "/", label, ".call.json"));
    }
}
