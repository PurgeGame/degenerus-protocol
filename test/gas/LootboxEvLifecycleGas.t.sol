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
        uint256 buyGas;
        uint256 buyRepriced;
        uint256 buySlots;
        for (uint256 i; i < orders; ++i) {
            address player = address(uint160(PLAYER) + uint160(distinct ? i : 0));
            uint256 snap = vm.snapshotState();
            _buy(player, order, grant);
            uint256 measured = vm.lastCallGas().gasTotalUsed;
            assertTrue(vm.revertToState(snap));
            vm.startStateDiffRecording();
            _buy(player, order, grant);
            VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
            GlamsterdamReprice.Result memory r = GlamsterdamReprice.reprice(measured, accesses, address(host));
            buyGas += measured;
            buyRepriced += r.glamsterdamExec + r.stateGas;
            buySlots += r.newSlots;
        }
        host.sealAndPublish(openWord);
        uint256 snap = vm.snapshotState();
        _open();
        uint256 openGas = vm.lastCallGas().gasTotalUsed;
        assertTrue(vm.revertToState(snap));
        vm.startStateDiffRecording();
        _open();
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        GlamsterdamReprice.Result memory opened = GlamsterdamReprice.reprice(openGas, accesses, address(host));
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
        (, uint256 cursor, bool complete) = host.readState();
        assertEq(cursor, orders);
        assertTrue(complete);
    }

    /// @dev Recalibrated on the stack with the VRF request-ID port (eip170 profile, solc 0.8.38/via-IR/1000/
    ///      Osaka, isolated transactions). Against the P7B calibration (e.g. exhausted 395,695) every case
    ///      is higher, bisected: logical game days add about 4.0k per path (75a1765b3), the Glamsterdam
    ///      shape gains about 1.3k more through the profile and native-VRF commits (exhausted 401,048 there),
    ///      and the EIP-170 split adds about 14.6k of cold module hops (exhausted 415,662 here; 419,214
    ///      before the split call-overhead cuts). pass_grant realizes a cheaper branch (7 new slots, was
    ///      10) after the RNG derivation changes. The limits stay at the original 1% / 1000-per-order.
    ///      Earlier calibration: frozen P7B 824d757cf. P6b changed RNG domains and therefore the realized
    ///      award branches and new-slot counts. The 0.8.34 b80dab839 measurements remain
    ///      historical evidence in docs/VERIFICATION.md.
    function _baseline(bytes32 label) private pure returns (uint256, uint256, uint256) {
        if (label == keccak256("cover")) return (179460, 481520, 3);
        if (label == keccak256("distinct_wallets")) return (1307320, 4357560, 32);
        if (label == keccak256("exhausted")) return (415662, 1342662, 10);
        if (label == keccak256("existing_bonus")) return (419592, 1353792, 10);
        if (label == keccak256("fresh_bonus")) return (436749, 1451769, 11);
        if (label == keccak256("low_score")) return (424789, 1432609, 11);
        if (label == keccak256("manual_with_afk")) return (477939, 1595379, 12);
        if (label == keccak256("100_boxes")) return (1562271, 3550671, 20);
        if (label == keccak256("nested_eth_spin")) return (515868, 1721728, 13);
        if (label == keccak256("pass_grant")) return (309384, 978324, 7);
        if (label == keccak256("same_wallet")) return (894353, 2462653, 15);
        if (label == keccak256("taper")) return (419788, 1353988, 10);
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
