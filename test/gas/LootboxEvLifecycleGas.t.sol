// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {VmSafe} from "forge-std/Vm.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {QueueHost} from "../helpers/BoxQueueHost.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

contract EvLifecycleGasHost is QueueHost {
    function seedAccount(address player, uint256 used, bool bonus) external {
        (uint32 id,) = _registerWallet(player, 1 ether);
        if (bonus) mintPacked_[id] |= uint256(1) << BitPackingLib.HAS_DEITY_PASS_SHIFT;
        if (used != 0) _setLootboxEvUsedFor(id, level + 1, used);
    }

    function workWithAfk(address player, uint256 word) external returns (MineFlipGas.Result memory result) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(
            abi.encodeWithSignature("resolveAfkingBox(uint32,uint256,uint24,uint256,uint16)",
                _walletIdOf(player), uint256(1 ether), uint24(1), word, uint16(400)));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        (ok, data) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSignature("runHumanBoxWork_g315(uint256)", uint256(25_000_000)));
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        result = abi.decode(data, (MineFlipGas.Result));
    }
}

/// @notice Full purchase + opening costs, with each call a separate transaction. Run with
///         FOUNDRY_ISOLATE=true. Replay accesses only AFTER measuring the uninstrumented call:
///         recording warms storage and must never supply the measured Osaka gas.
contract LootboxEvLifecycleGasTest is DeployProtocol {
    EvLifecycleGasHost private host;
    address private constant PLAYER = address(0xE7CA9);
    uint256 private constant WORD = 0x5eedc0ffee;
    uint256 private openWord = WORD;
    bool private withAfk;

    function setUp() public {
        _deployProtocol();
        vm.etch(address(game), type(EvLifecycleGasHost).runtimeCode);
        host = EvLifecycleGasHost(payable(address(game)));
        vm.deal(address(game), 100_000 ether);
    }

    function _buy(address player, uint256 order, bool grant) private {
        if (grant) host.grant(player, order == 0 ? 1 ether : order * 1 ether, 400, false, uint8(order));
        else {
            (, uint256 cost) = host.decode(order, host.activeLevel());
            vm.prank(player);
            host.purchaseOrderFor{value: cost}(0, 0, order, bytes32(0), MintPaymentKind.DirectEth, false);
        }
    }

    function _open() private {
        MineFlipGas.Result memory result = withAfk ? host.workWithAfk(PLAYER, openWord) : host.work(25_000_000);
        assertTrue(result.done);
    }

    function _cycle(string memory label, uint256 order, uint256 orders, bool distinct, uint256 used,
        bool bonus, bool grant) private
    {
        require(vm.envOr("FOUNDRY_ISOLATE", false), "gas measurement requires isolated transactions");
        for (uint256 i; i < (distinct ? orders : 1); ++i) {
            address player = address(uint160(PLAYER) + uint160(i));
            vm.deal(player, 100_000 ether);
            host.seedAccount(player, used, bonus);
        }
        // Every buy and the open run unrecorded first, so each figure is cold; the recorded
        // replays then run from each call's pre-state, latest first.
        uint256[] memory pre = new uint256[](orders);
        uint256[] memory measured = new uint256[](orders);
        uint256 buyGas;
        for (uint256 i; i < orders; ++i) {
            address player = address(uint160(PLAYER) + uint160(distinct ? i : 0));
            pre[i] = vm.snapshotState();
            _buy(player, order, grant);
            measured[i] = vm.lastCallGas().gasTotalUsed;
            buyGas += measured[i];
        }
        host.sealAndPublish(openWord);
        uint256 snap = vm.snapshotState();
        _open();
        uint256 openGas = vm.lastCallGas().gasTotalUsed;
        {
            (, uint256 cursor, bool complete) = host.readState();
            assertEq(cursor, orders);
            assertTrue(complete);
        }
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        _open();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory opened = GlamsterdamReprice.reprice(openGas, accesses, address(host));
        uint256 buyRepriced;
        uint256 buySlots;
        for (uint256 i = orders; i != 0; --i) {
            address player = address(uint160(PLAYER) + uint160(distinct ? i - 1 : 0));
            assertTrue(vm.revertToState(pre[i - 1]));
            vm.startStateDiffRecording();
            _buy(player, order, grant);
            VmSafe.AccountAccess[] memory buyAccesses = vm.stopAndReturnStateDiff();
            GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(measured[i - 1], buyAccesses, address(host));
            buyRepriced += r.glamsterdamExec + r.stateGas;
            buySlots += r.newSlots;
        }
        emit log_named_string("case", label);
        emit log_named_uint("buy_osaka", buyGas);
        emit log_named_uint("open_osaka", openGas);
        emit log_named_uint("total_osaka", buyGas + openGas);
        emit log_named_uint("buy_repriced_including_state", buyRepriced);
        emit log_named_uint("open_repriced_including_state", opened.glamsterdamExec + opened.stateGas);
        emit log_named_uint("total_repriced_including_state", buyRepriced + opened.glamsterdamExec + opened.stateGas);
        emit log_named_uint("total_new_slots", buySlots + opened.newSlots);
        (uint256 oldGas, uint256 oldRepriced, uint256 oldSlots) = _baseline(keccak256(bytes(label)));
        uint256 total = buyGas + openGas;
        uint256 repriced = buyRepriced + opened.glamsterdamExec + opened.stateGas;
        assertLe(total, oldGas + 1000 * orders, "lifecycle Osaka regression >1000/order");
        assertLe(repriced, oldRepriced + 1000 * orders, "repriced lifecycle regression >1000/order");
        assertLe(total * 100, oldGas * 101, "workload Osaka regression >1%");
        assertLe(repriced * 100, oldRepriced * 101, "repriced workload regression >1%");
        assertEq(buySlots + opened.newSlots, oldSlots, "no additional lifecycle storage slots");
    }

    /// @dev Cold figures per case (eip170 profile, solc 0.8.38, via IR, 1,000 runs, Osaka, isolated
    ///      transactions): every buy and open is measured before the first recorded replay of its
    ///      test. Columns: Osaka total, Glamsterdam total including state gas, new slots. The limits
    ///      are 1% of the workload and 1,000 gas per order.
    function _baseline(bytes32 label) private pure returns (uint256, uint256, uint256) {
        if (label == keccak256("cover")) return (212574, 514634, 3);
        if (label == keccak256("distinct_wallets")) return (1481118, 4532258, 32);
        if (label == keccak256("exhausted")) return (446524, 1373724, 10);
        if (label == keccak256("existing_bonus")) return (450454, 1384854, 10);
        if (label == keccak256("fresh_bonus")) return (467611, 1482831, 11);
        if (label == keccak256("low_score")) return (452428, 1460348, 11);
        if (label == keccak256("manual_with_afk")) return (516573, 1634213, 12);
        if (label == keccak256("100_boxes")) return (1662707, 3651507, 20);
        if (label == keccak256("nested_eth_spin")) return (552460, 1758520, 13);
        if (label == keccak256("pass_grant")) return (353926, 1022866, 7);
        if (label == keccak256("same_wallet")) return (1043863, 2612763, 15);
        if (label == keccak256("taper")) return (450650, 1385050, 10);
        revert("missing lifecycle baseline");
    }

    function test_Gas_FreshBonus() public { _cycle("fresh_bonus", BoxOrderLib.boCustom(1 ether), 1, false, 0, true, false); }
    function test_Gas_ExistingBonus() public { _cycle("existing_bonus", BoxOrderLib.boCustom(1 ether), 1, false, 5 ether, true, false); }
    function test_Gas_Taper() public { _cycle("taper", BoxOrderLib.boCustom(1 ether), 1, false, 15 ether, true, false); }
    function test_Gas_Exhausted() public { _cycle("exhausted", BoxOrderLib.boCustom(1 ether), 1, false, 40 ether, true, false); }
    function test_Gas_LowScore() public { _cycle("low_score", BoxOrderLib.boCustom(1 ether), 1, false, 0, false, false); }
    function test_Gas_MaxOrder() public { _cycle("100_boxes", BoxOrderLib.boSmalls(100), 1, false, 0, true, false); }
    function test_Gas_SameWallet() public { _cycle("same_wallet", BoxOrderLib.boCustom(1 ether), 4, false, 0, true, false); }
    function test_Gas_DistinctWallets() public { _cycle("distinct_wallets", BoxOrderLib.boCustom(1 ether), 4, true, 0, true, false); }
    function test_Gas_Cover() public { _cycle("cover", 0, 1, false, 0, true, true); }
    function test_Gas_PassGrant() public { _cycle("pass_grant", 3, 1, false, 0, true, true); }
    function test_Gas_ManualWithAfk() public {
        withAfk = true;
        _cycle("manual_with_afk", BoxOrderLib.boCustom(1 ether), 1, false, 0, true, false);
    }
    function test_Gas_NestedEthSpin() public {
        host.seedAccount(PLAYER, 0, true);
        uint32 id = host.walletIdOf_g3120(PLAYER);
        uint48 buffer = host.writeBuffer();
        for (uint256 w = 2; ; ++w) {
            uint256 root = uint256(keccak256(abi.encode(uint256(20), w, uint256(0))));
            uint256 seed = uint256(keccak256(abi.encode(uint256(19), root, uint256(1))));
            if (uint16(seed >> 40) % 20 == 19) { openWord = w; break; }
        }
        _cycle("nested_eth_spin", BoxOrderLib.boCustom(1 ether), 1, false, 0, true, false);
    }
}
