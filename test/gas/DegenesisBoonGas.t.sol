// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenesisGasBase, DegenesisGasHost} from "./DegenesisGas.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {NativeMeasuredGasExport} from "../helpers/NativeMeasuredGasExport.sol";
import {DegenesisBoonReference as Ref} from "../fuzz/helpers/DegenesisBoonReference.sol";
import {GameSlots, GameSlotKeys} from "../helpers/GameSlots.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

/// @notice Full production settlement calls: dispatch, expiry, all deliveries, event, primary,
///         flush and close. Paired native runs remove only the additional boon path.
contract DegenesisBoonGasTest is DegenesisGasBase, NativeMeasuredGasExport {
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
        // Full dumps include every selected module and optional continuation slot.
        // The cheatcode writes directly; export does not build a growing JSON string
        // containing every runtime in the EVM test frame.
        string memory label = "degenesis-chunk-three-boons-seventh";
        string memory dir = vm.envOr("STORAGE_REUSE_EXPORT", string(""));
        if (bytes(dir).length != 0) {
            // Isolated dumpState omits untouched cached deployment accounts.
            // Materialize actual runtimes/headers, preserving every value.
            for (uint256 i; i <= GameSlots.DEGENERETTE_QUEUE + 1; ++i) {
                bytes32 slot = bytes32(i);
                vm.store(address(host), slot, vm.load(address(host), slot));
            }
            address[32] memory accounts = [
                ContractAddresses.GAME,
                ContractAddresses.GAME_ACTIONS_MODULE,
                ContractAddresses.GAME_PURCHASE_MODULE,
                ContractAddresses.GAME_MINT_MODULE,
                ContractAddresses.GAME_DEGENESIS_MODULE,
                ContractAddresses.GAME_ADVANCE_MODULE,
                ContractAddresses.GAME_RNG_MODULE,
                ContractAddresses.GAME_JACKPOT_MODULE,
                ContractAddresses.GAME_JACKPOT_DRAW_MODULE,
                ContractAddresses.GAME_WHALE_MODULE,
                ContractAddresses.GAME_TICKET_MODULE,
                ContractAddresses.GAME_LOOTBOX_MODULE,
                ContractAddresses.GAME_BOON_MODULE,
                ContractAddresses.GAME_DEGENERETTE_MODULE,
                ContractAddresses.GAME_AFKING_MODULE,
                ContractAddresses.GAME_GAMEOVER_MODULE,
                ContractAddresses.GAME_DECIMATOR_MODULE,
                ContractAddresses.GAME_MINER_MODULE,
                ContractAddresses.COIN,
                ContractAddresses.COINFLIP,
                ContractAddresses.QUESTS,
                ContractAddresses.AFFILIATE,
                ContractAddresses.SDGNRS,
                ContractAddresses.DGNRS,
                ContractAddresses.WWXRP,
                ContractAddresses.VAULT,
                ContractAddresses.GNRUS,
                ContractAddresses.DEITY_PASS,
                ContractAddresses.RECORD_BOUNTY,
                ContractAddresses.CRAPS,
                ContractAddresses.CRAPS_ENGINE,
                ContractAddresses.CRAPS_LIFECYCLE_MODULE
            ];
            for (uint256 a; a < accounts.length; ++a) {
                vm.etch(accounts[a], accounts[a].code);
                for (uint256 i; i < 32; ++i) {
                    bytes32 slot = bytes32(i);
                    vm.store(accounts[a], slot, vm.load(accounts[a], slot));
                }
            }
            bytes32[2] memory roots = [
                bytes32(0x04343aaa474371a66bb47cad27e6432f6ed56b02c7b23c6e11e4d1818f7af200),
                bytes32(0x93b2738aa52d403a1d6cd7cad14e72a7cda308b6a92d312ff0746cbfb7eec800)
            ];
            for (uint256 a; a < 2; ++a) {
                address owner = a == 0 ? ContractAddresses.QUESTS : ContractAddresses.AFFILIATE;
                for (uint256 i; i < 8; ++i) {
                    bytes32 slot = bytes32(uint256(roots[a]) + i);
                    vm.store(owner, slot, vm.load(owner, slot));
                }
            }
            // Deployment cache also holds the pool inventory and the Game's
            // sDGNRS claimable sentinel. Materialize those constructor mappings.
            bytes32 poolBalanceSlot = keccak256(abi.encode(address(sdgnrs), uint256(1))); // sDGNRS.balanceOf
            vm.store(address(sdgnrs), poolBalanceSlot, vm.load(address(sdgnrs), poolBalanceSlot));
            bytes32 claimableSlot = keccak256(abi.encode(uint32(2), GameSlots.BALANCES_PACKED));
            vm.store(address(host), claimableSlot, vm.load(address(host), claimableSlot));
            vm.dumpState(string.concat(dir, "/", label, ".state.json"));
        }
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
            vm.dumpState(string.concat(dir, "/", label, ".post.json"));
            this.writeDumpFixture(label, address(this), address(host), input, output, logs);
        }
    }
}
