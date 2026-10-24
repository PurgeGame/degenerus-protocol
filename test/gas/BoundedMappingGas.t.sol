// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {BoundedDeployProtocol} from "../helpers/BoundedDeployProtocol.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract BoundedGameSeeder is DegenerusGameStorage, WalletSeed {
    function seed(address player) external {
        level = 24;
        dailyIdx = _wallDay();
        purchaseStartDay = dailyIdx;
        rngRequestTime = uint48(block.timestamp);
        lastPurchaseDay = false;
        jackpotPhaseFlag = false;
        degenesisClosed = 7;
        _setPrizePools(10 ether, 10 ether);
        balancesPacked[_seedWallet(player)] = uint256(10 ether) | (uint256(10 ether) << 128);
        claimablePool = 20 ether;
        seedDay();
    }

    function seedDay() public {
        uint24 day = _wallDay();
        dailyIdx = day;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = day;
        _recordDailyRng(day - 1, 0xCAFE);
        _recordDailyRng(day, 0xBEEF);
    }

    function reuseHero() external {
        seedDay();
        uint24 day = _gameDay();
        _sealHeroWagers(day - 1);
        _sealHeroWagers(day);
        dailyIdx = day;
    }
}

/// @dev Run through the bounded runner with FOUNDRY_ISOLATE=true. The external
///      measurement wrapper gives each cold case a fresh transaction, while gas is
///      captured in its nested production frame. Warm cases use explicit access lists.
contract BoundedMappingGasTest is BoundedDeployProtocol {
    address private constant PLAYER = address(0xA11CE);
    address private constant DEITY = address(0xDE17);
    uint32 private deityId;
    uint32 private playerId;

    function setUp() public {
        _deployBounded(true);
        vm.deal(DEITY, 1_000 ether);
        vm.prank(DEITY);
        game.purchaseDeityPass{value: 24 ether}(0, 1, bytes32(0));
        deityId = game.walletIdOf_g3120(DEITY);
        vm.warp(block.timestamp + 20 days);
        _seed(abi.encodeCall(BoundedGameSeeder.seed, (PLAYER)));
        playerId = game.walletIdOf_g3120(PLAYER);
        vm.deal(PLAYER, 1_000 ether);
        vm.deal(address(game), 1_000 ether);
    }

    function _seed(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), vm.getDeployedCode("BoundedMappingGas.t.sol:BoundedGameSeeder"));
        (bool ok, bytes memory reason) = address(game).call(data);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        vm.etch(address(game), original);
        _syncCoinflipFixtureDay(game.currentDayView());
    }

    function measured(address sender, uint256 value, bytes calldata data, bool cold,
        VmSafe.AccountAccess[] calldata accesses) external returns (uint256 gasUsed, int64 refund)
    {
        require(msg.sender == address(this), "measurement self-call");
        for (uint256 i; i < accesses.length; ++i) {
            if (cold && accesses[i].account != sender) vm.cool(accesses[i].account);
            for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = accesses[i].storageAccesses[j];
                if (cold) vm.coolSlot(a.account, a.slot);
                else vm.warmSlot(a.account, a.slot);
            }
        }
        vm.prank(sender);
        (bool ok, bytes memory reason) = address(game).call{value: value}(data);
        VmSafe.Gas memory gas = vm.lastCallGas();
        gasUsed = gas.gasTotalUsed;
        refund = gas.gasRefunded;
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }

    function _measure(string memory label, address sender, uint256 value, bytes memory data, bool warm) private {
        // Measure cold first: this Forge version retains recorder state across
        // isolated transactions after a recorded replay. The fully warm replay is
        // valid and independently cross-checks this initial uninstrumented call.
        uint256 snapshot = vm.snapshotState();
        (uint256 coldGas, int64 coldRefund) = this.measured(sender, value, data, true,
            new VmSafe.AccountAccess[](0));
        assertTrue(vm.revertToState(snapshot));
        snapshot = vm.snapshotState();
        vm.startStateDiffRecording();
        this.measured(sender, value, data, false, new VmSafe.AccountAccess[](0));
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        assertTrue(vm.revertToState(snapshot));
        {
            uint256 n = accesses.length;
            for (uint256 i; i < accesses.length; ++i) n += accesses[i].storageAccesses.length;
            VmSafe.AccessListItem[] memory list = new VmSafe.AccessListItem[](n);
            uint256 next;
            for (uint256 i; i < accesses.length; ++i) {
                list[next++] = VmSafe.AccessListItem(accesses[i].account, new bytes32[](0));
                for (uint256 j; j < accesses[i].storageAccesses.length; ++j) {
                    VmSafe.StorageAccess memory a = accesses[i].storageAccesses[j];
                    bytes32[] memory keys = new bytes32[](1);
                    keys[0] = a.slot;
                    list[next++] = VmSafe.AccessListItem(a.account, keys);
                }
            }
            vm.accessList(list);
        }
        (uint256 warmGas, int64 warmRefund) = this.measured(sender, value, data, false, accesses);
        vm.noAccessList();
        VmSafe.AccountAccess[] memory acc = accesses;
        uint256 count;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account == address(this) || acc[i].account == address(vm)) continue;
            acc[count++] = acc[i];
        }
        assembly ("memory-safe") { mstore(acc, count) }
        (uint256 surcharge, uint256 firstWrites) = _surcharge(acc, sender);
        emit log_named_uint("cold_frame_crosscheck", coldGas);
        emit log_named_uint("warm_frame_crosscheck", warmGas);
        emit log_named_uint("cold_surcharge", surcharge);
        assertEq(coldGas, warmGas + surcharge, "benchmark cold/warm cross-check");
        uint256 used = warm ? warmGas : coldGas;
        int64 refund = warm ? warmRefund : coldRefund;
        GlamsterdamReprice.Result memory g = GlamsterdamReprice.reprice(used, acc, address(game));
        // All benchmarked mutation paths keep their external-call structure. Storage
        // repricing gives exact before/after deltas; common opcode costs cancel.
        uint256 projected = g.glamsterdamExec + g.stateGas;
        if (warm) projected -= g.coldAccounts * 400;
        else projected -= firstWrites * 100;
        emit log_named_string("bounded_case", label);
        emit log_named_uint("osaka_frame_gross", used);
        emit log_named_int("refund_counter", refund);
        emit log_named_uint("projected_storage_account_total", projected);
        emit log_named_uint("first_write_cold_slots", firstWrites);
        emit log_named_uint("new_slots", g.newSlots);
        emit log_named_uint("sstores", g.sstores);
    }

    function _surcharge(VmSafe.AccountAccess[] memory acc, address sender) private view returns (uint256 charge, uint256 firstWrites) {
        address[] memory accounts = new address[](acc.length);
        address[] memory slotAccounts = new address[](4096);
        bytes32[] memory slots = new bytes32[](4096);
        uint256 na;
        uint256 ns;
        for (uint256 i; i < acc.length; ++i) {
            address account = acc[i].account;
            if (acc[i].kind != VmSafe.AccountAccessKind.Resume && account != sender
                && account != address(game) && uint160(account) > 0x100) {
                bool seen;
                for (uint256 j; j < na; ++j) if (accounts[j] == account) seen = true;
                if (!seen) { accounts[na++] = account; charge += 2500; }
            }
            for (uint256 j; j < acc[i].storageAccesses.length; ++j) {
                VmSafe.StorageAccess memory a = acc[i].storageAccesses[j];
                bool seen;
                for (uint256 k; k < ns; ++k) if (slotAccounts[k] == a.account && slots[k] == a.slot) seen = true;
                if (seen) continue;
                require(ns < 4096, "surcharge capacity");
                slotAccounts[ns] = a.account; slots[ns++] = a.slot;
                charge += a.isWrite ? 2100 : 2000;
                if (a.isWrite) ++firstWrites;
            }
        }
    }

    function _boonData() private view returns (bytes memory) {
        return abi.encodeCall(game.issueDeityBoon, (deityId, playerId, uint8(0)));
    }

    function test_D1_FirstReceiptCold() public { _measure("D1_first_cold", DEITY, 0, _boonData(), false); }
    function test_D1_FirstReceiptWarm() public { _measure("D1_first_warm", DEITY, 0, _boonData(), true); }

    function _priorBoon() private {
        vm.prank(DEITY);
        game.issueDeityBoon(deityId, playerId, 0);
        vm.warp(block.timestamp + 1 days);
        _seed(abi.encodeCall(BoundedGameSeeder.seedDay, ()));
    }

    function test_D1_ExistingRecipientCold() public {
        _priorBoon(); _measure("D1_existing_cold", DEITY, 0, _boonData(), false);
    }
    function test_D1_ExistingRecipientWarm() public {
        _priorBoon(); _measure("D1_existing_warm", DEITY, 0, _boonData(), true);
    }

    function _betData(uint8 symbol) private view returns (bytes memory) {
        return abi.encodeCall(game.placeDegeneretteBet, (uint32(0), uint8(0), uint128(0.01 ether), uint8(1), symbol));
    }
    function _bet(uint8 symbol) private {
        vm.prank(PLAYER);
        game.placeDegeneretteBet{value: 0.01 ether}(0, 0, uint128(0.01 ether), 1, symbol);
    }
    function test_G6_FirstBetCold() public { _measure("G6_first_cold", PLAYER, 0.01 ether, _betData(3), false); }
    function test_G6_FirstBetWarm() public { _measure("G6_first_warm", PLAYER, 0.01 ether, _betData(3), true); }
    function test_G6_RepeatBetCold() public {
        _bet(3); _measure("G6_repeat_cold", PLAYER, 0.01 ether, _betData(3), false);
    }
    function test_G6_RepeatBetWarm() public {
        _bet(3); _measure("G6_repeat_warm", PLAYER, 0.01 ether, _betData(3), true);
    }
    function test_G6_RecycledWordCold() public {
        _bet(3); _bet(3);
        vm.warp(block.timestamp + 2 days);
        _seed(abi.encodeCall(BoundedGameSeeder.reuseHero, ()));
        _measure("G6_recycled_cold", PLAYER, 0.01 ether, _betData(3), false);
    }
    function test_G6_StalledWordCold() public {
        _bet(3);
        vm.warp(block.timestamp + 3 days);
        _measure("G6_stalled_cold", PLAYER, 0.01 ether, _betData(3), false);
    }
    function test_G8_G9_ProtocolSymbolZero() public {
        _measure("G8_G9_symbol0_cold", PLAYER, 0.01 ether, _betData(0), false);
    }
    function test_G8_G9_ProtocolSymbolSix() public {
        _measure("G8_G9_symbol6_cold", PLAYER, 0.01 ether, _betData(6), false);
    }
}
