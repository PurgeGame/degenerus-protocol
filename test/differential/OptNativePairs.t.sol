// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {StorageCensusLongRunTest} from "../census/StorageCensusLongRun.t.sol";
import {Vm} from "forge-std/Vm.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";
import {console} from "forge-std/console.sol";

/// @dev Optional native fixtures. Each sample records the UNION of accesses by two
/// runtime variants at exactly the same prestate, including zero-valued slots.
/// This avoids treating a newly selected random recipient's omitted state as zero.
contract OptNativePairsTest is StorageCensusLongRunTest {
    string private directory;
    address[] private priorTargets;
    bytes[] private priorCode;
    mapping(bytes32 => uint256) private sampled;
    string[] private categories;
    bool[] private protocolPayers;
    uint256 private sequence;

    function setUp() public override {
        super.setUp();
        directory = vm.envOr("OPT_NATIVE_EXPORT", string(""));
        if (bytes(directory).length == 0) return;
        string memory variants = vm.readFile(vm.envString("OPT_NATIVE_BEFORE"));
        uint256 count = vm.parseJsonUint(variants, ".count");
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".contracts[", vm.toString(i), "]");
            priorTargets.push(vm.parseJsonAddress(variants, string.concat(key, ".target")));
            priorCode.push(vm.parseJsonBytes(variants, string.concat(key, ".runtime")));
        }
        vm.fee(0);
    }

    function _ctx(string memory label, bool protocolPaid, address from, address to, uint256 value, bytes memory data)
        internal override returns (bool ok, bytes memory ret)
    {
        if (bytes(directory).length != 0) {
            string memory category = label;
            if (to == address(game) && data.length >= 4 && bytes4(data) == game.mineRun.selector) {
                vm.prank(from, from);
                category = string.concat(label, ":", vm.toString(game.nextMinerAction()));
                uint24 lvl = game.currentLvl();
                if (lvl == 0 && block.timestamp >= GameTimeLib.DEGENESIS_END_TS) category = string.concat(category, ":level-one");
                if (lvl >= 10 && lvl % 10 == 0) category = string.concat(category, ":baf");
            }
            uint256 occurrence = sampled[keccak256(bytes(category))]++;
            if (occurrence == 0) {
                categories.push(category);
                protocolPayers.push(protocolPaid);
            }
            if (occurrence < 4) {
                this.exportPair(++sequence, category, protocolPaid, from, to, value, data);
            }
        }
        return super._ctx(label, protocolPaid, from, to, value, data);
    }

    function _censusEnd() internal override {
        super._censusEnd();
        for (uint256 i; i < categories.length; ++i) {
            console.log(string.concat("NATIVECOUNT|", categories[i], "|",
                protocolPayers[i] ? "protocol" : "player", "|",
                vm.toString(sampled[keccak256(bytes(categories[i]))])));
        }
    }

    function _capture(address from, address to, uint256 value, bytes memory data)
        private returns (Vm.AccountAccess[] memory accesses)
    {
        uint256 snapshot = vm.snapshotState();
        Vm.AccountAccess[] memory ordinary = _captureAtGas(from, to, value, data, 16_000_000);
        require(vm.revertToState(snapshot));
        // Reservoir execution can continue beyond the Osaka 16M checkpoint. Record
        // that continuation too, then read every union slot from the restored state.
        Vm.AccountAccess[] memory reservoir = _captureAtGas(from, to, value, data, 500_000_000);
        require(vm.revertToState(snapshot));
        vm.deleteStateSnapshot(snapshot);
        accesses = new Vm.AccountAccess[](ordinary.length + reservoir.length);
        for (uint256 i; i < ordinary.length; ++i) accesses[i] = ordinary[i];
        for (uint256 i; i < reservoir.length; ++i) accesses[ordinary.length + i] = reservoir[i];
    }

    function _captureAtGas(address from, address to, uint256 value, bytes memory data, uint256 supplied)
        private returns (Vm.AccountAccess[] memory accesses)
    {
        vm.startStateDiffRecording();
        vm.prank(from, from);
        vm.resumeGasMetering();
        (bool ok,) = to.call{value: value, gas: supplied}(data);
        vm.pauseGasMetering();
        // Reverted paths are useful fixtures too; their prestate is still complete.
        ok;
        accesses = vm.stopAndReturnStateDiff();
    }

    function exportPair(uint256 seq, string calldata label, bool protocolPaid,
        address from, address to, uint256 value, bytes calldata data) external
    {
        require(msg.sender == address(this));
        uint256 snapshot = vm.snapshotState();
        Vm.AccountAccess[] memory current = _capture(from, to, value, data);
        require(vm.revertToState(snapshot));
        for (uint256 i; i < priorTargets.length; ++i) vm.etch(priorTargets[i], priorCode[i]);
        Vm.AccountAccess[] memory previous = _capture(from, to, value, data);
        require(vm.revertToState(snapshot));
        vm.deleteStateSnapshot(snapshot);

        address[] memory accounts = new address[](current.length + previous.length + 2);
        accounts[0] = from; accounts[1] = to;
        for (uint256 i; i < current.length; ++i) accounts[i + 2] = current[i].account;
        for (uint256 i; i < previous.length; ++i) accounts[i + current.length + 2] = previous[i].account;
        string memory state = "{";
        for (uint256 i; i < accounts.length; ++i) {
            address account = accounts[i];
            bool seen;
            for (uint256 j; j < i; ++j) if (accounts[j] == account) { seen = true; break; }
            if (seen) continue;
            string memory key = string.concat("pair-storage-", vm.toString(account));
            vm.serializeJson(key, "{}");
            this.serializeSlots(key, account, current); this.serializeSlots(key, account, previous);
            if (account == address(game)) {
                // Amsterdam can cross the miner compensation gas threshold or finish
                // at a different boundary and reach caller-credit eligibility. Export
                // this registry value from the restored state even if Osaka stopped
                // before that read. No unobserved slot is assumed to contain zero.
                bytes32 walletKey = keccak256(abi.encode(from, GameSlots.WALLET_IDS));
                vm.serializeBytes32(key, vm.toString(walletKey), vm.load(account, walletKey));
            }
            string memory slots = vm.serializeBytes32(key, vm.toString(bytes32(0)), vm.load(account, 0));
            if (bytes(state).length > 1) state = string.concat(state, ",");
            state = string.concat(state, '"', vm.toString(account), '":{"code":"', vm.toString(account.code),
                '","balance":"', vm.toString(bytes32(account.balance)), '","nonce":"',
                vm.toString(bytes32(uint256(vm.getNonce(account)))), '","state":', slots, '}');
        }
        string memory name = string.concat(directory, "/", vm.toString(seq));
        vm.writeJson(string.concat(state, "}"), string.concat(name, ".state.json"));
        string memory key = "pair-call";
        vm.serializeJson(key, "{}");
        vm.serializeUint(key, "seq", seq);
        vm.serializeString(key, "label", label);
        vm.serializeString(key, "payer", protocolPaid ? "protocol" : "player");
        vm.serializeAddress(key, "from_", from); vm.serializeAddress(key, "to", to);
        vm.serializeBytes32(key, "value", bytes32(value)); vm.serializeBytes(key, "data", data);
        vm.serializeUint(key, "number", block.number);
        vm.writeJson(vm.serializeUint(key, "timestamp", block.timestamp), string.concat(name, ".call.json"));
    }

    function serializeSlots(string memory key, address account, Vm.AccountAccess[] memory accesses) external {
        require(msg.sender == address(this));
        for (uint256 i; i < accesses.length; ++i) {
            Vm.StorageAccess[] memory slots = accesses[i].storageAccesses;
            for (uint256 j; j < slots.length; ++j) if (slots[j].account == account) {
                // serializeBytes32 returns the ENTIRE growing JSON object. Discard that
                // returndata here; decoding it at every access exhausts test memory.
                bytes memory input = abi.encodeWithSignature("serializeBytes32(string,string,bytes32)",
                    key, vm.toString(slots[j].slot), vm.load(account, slots[j].slot));
                address cheatcode = address(vm);
                bool ok;
                assembly ("memory-safe") {
                    ok := call(gas(), cheatcode, 0, add(input, 32), mload(input), 0, 0)
                }
                require(ok, "fixture slot serialization");
            }
        }
    }
}
