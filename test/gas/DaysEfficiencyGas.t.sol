// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {LogicalDaysGasTest} from "./LogicalDaysGas.t.sol";
import {CrapsScheduledCursorTest} from "../craps/CrapsScheduledCursor.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Same fixture on both revisions. Only the BAF calldata schema varies by environment.
contract DaysEfficiencyProtocolGasTest is LogicalDaysGasTest {
    function test_DaysEffBafBegin() public {
        uint24 day = game.currentDayView();
        bytes memory data = vm.envOr("DAYSEFF_NEW_ABI", false)
            ? abi.encodeWithSignature("beginBaf(uint24)", day) : abi.encodeWithSignature("beginBaf()");
        emit log_named_uint("dayseff_baf_begin", this.measure(address(jackpots), address(game), data));
        assertEq(jackpots.getLastBafResolvedDay(), day);
    }

    function test_DaysEffBafBeginThroughGame() public {
        emit log_named_uint("dayseff_baf_begin_game", this.measure(address(game), address(game),
            abi.encodeWithSignature("runBafJackpot(uint256,uint24,uint256)", 10 ether, uint24(10), uint256(777))));
        assertEq(jackpots.getLastBafResolvedDay(), game.currentDayView());
    }

    function test_DaysEffBafSkip() public {
        uint24 day = game.currentDayView();
        bytes memory data = vm.envOr("DAYSEFF_NEW_ABI", false)
            ? abi.encodeWithSignature("markBafSkipped(uint24,uint24)", uint24(10), day)
            : abi.encodeWithSignature("markBafSkipped(uint24)", uint24(10));
        emit log_named_uint("dayseff_baf_skip", this.measure(address(jackpots), address(game), data));
        assertEq(jackpots.getLastBafResolvedDay(), day);
    }

    function test_DaysEffRecord() public {
        address player = address(0xEFFE);
        uint32 id = _giveWalletId(player);
        bytes memory data = abi.encodeCall(coinflip.armRecord, (uint8(1), id, uint256(1 ether)));
        emit log_named_uint("dayseff_record_first", this.measure(address(coinflip), address(game), data));
        (address holder,,uint24 since,) = recordBounty.recordInfo(1);
        assertEq(holder, player);
        assertEq(since, game.currentDayView());
        emit log_named_uint("dayseff_record_same_holder", this.measure(address(coinflip), address(game),
            abi.encodeCall(coinflip.armRecord, (uint8(1), id, uint256(2 ether)))));
        (,,uint24 afterDay,) = recordBounty.recordInfo(1);
        assertEq(afterDay, since);
    }

    function test_DaysEffCoinflipHeaderReads() public {
        if (!vm.envOr("DAYSEFF_TRACE", false)) return;
        address player = address(0xEFFE);
        uint32 id = _giveWalletId(player);
        vm.prank(address(game)); coin.mintForGame(player, 10_000);
        vm.startStateDiffRecording();
        vm.prank(player); coinflip.depositCoinflip(id, 1_000);
        Vm.AccountAccess[] memory calls = vm.stopAndReturnStateDiff();
        uint256 reads;
        for (uint256 i; i < calls.length; ++i) {
            for (uint256 j; j < calls[i].storageAccesses.length; ++j) {
                Vm.StorageAccess memory access = calls[i].storageAccesses[j];
                if (access.account == address(coinflip) && access.slot == bytes32(uint256(4)) && !access.isWrite) ++reads;
            }
        }
        emit log_named_uint("dayseff_deposit_slot4_reads", reads);
    }

    function test_DaysEffDiceRecord() public {
        uint32 id = _giveWalletId(address(0xEFFE));
        emit log_named_uint("dayseff_record_dice", this.measure(address(coinflip), ContractAddresses.CRAPS,
            abi.encodeCall(coinflip.armDiceRunRecord, (id, uint256(1_000_000)))));
        (address holder,,uint24 since,) = recordBounty.recordInfo(4);
        assertEq(holder, address(0xEFFE));
        assertEq(since, game.currentDayView());
    }
}

contract DaysEfficiencyCrapsGasTest is CrapsScheduledCursorTest {
    function probe(address caller, bytes calldata data, string calldata label) external returns (bytes memory result) {
        require(msg.sender == address(this));
        bool trace = vm.envOr("DAYSEFF_TRACE", false);
        if (trace) vm.startStateDiffRecording();
        vm.prank(caller);
        bool ok;
        (ok, result) = address(craps).call(data);
        uint256 used = vm.lastCallGas().gasTotalUsed;
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        if (trace) {
            Vm.AccountAccess[] memory calls = vm.stopAndReturnStateDiff();
            bytes32 inputHash = keccak256(abi.encodeWithSignature("extsload_g8132(bytes32)", bytes32(0)));
            uint256 headers;
            for (uint256 i; i < calls.length; ++i) {
                if (calls[i].kind == VmSafe.AccountAccessKind.StaticCall && calls[i].account == ContractAddresses.GAME
                    && keccak256(calls[i].data) == inputHash) ++headers;
            }
            emit log_named_uint(string.concat(label, " headers"), headers);
        } else emit log_named_uint(label, used);
    }

    function test_DaysEffOpenDay() public {
        this.probe(ContractAddresses.GAME, abi.encodeWithSignature("openBonusDay()"), "dayseff_open_day");
    }

    function test_DaysEffScheduledEntry() public {
        _openDay();
        this.probe(alice, abi.encodeWithSignature("enterBonusBattle(uint32,uint256,uint32,uint16)", 0, PER, SEVEN, 1), "dayseff_scheduled_entry");
    }

    function test_DaysEffMaintenance() public {
        vm.warp(_dayStart() + 1);
        _openDay();
        vm.warp(_dayStart() + 1 hours);
        bytes memory result = this.probe(ContractAddresses.GAME,
            abi.encodeWithSignature("runCrapsMaintenance_g10712(uint256)", 10_000_000), "dayseff_maintenance");
        assertTrue(abi.decode(result, (MineFlipGas.Result)).progressed);
    }

    function test_DaysEffReadWork() public {
        _openDay();
        _seat(alice, PER);
        _warpPastClose(PER);
        uint64 slot = _slotAt(PER);
        _driveCursorTo(slot);
        uint48 index = craps.slotIndexOf(slot) - 1;
        _setWord(index, uint256(keccak256("dayseff")));
        bytes memory result = this.probe(ContractAddresses.GAME,
            abi.encodeWithSignature("runCrapsReadWork(uint48,uint256)", index, 10_000_000), "dayseff_read_work");
        assertTrue(abi.decode(result, (MineFlipGas.Result)).progressed);
        assertTrue(craps.battleOf(craps.keyOfSlot(slot)).finalized);
    }

    function test_DaysEffDonation() public {
        _openDay();
        this.probe(alice, abi.encodeWithSignature("donate(bool,uint256,uint24)", false, PER, uint24(1)), "dayseff_donation");
    }

    function test_DaysEffUpgrade() public {
        vm.warp(_dayStart() + 1);
        _openDay();
        vm.prank(alice);
        craps.enterBonusDay(0, SEVEN, 1);
        uint24 day = craps.currentDayIndex();
        this.probe(alice, abi.encodeWithSignature("upgradeDayWindows(uint32,uint24,uint8)", 0, day, uint8(31)), "dayseff_upgrade");
    }

    function _prepareMeasuredJackpot() private returns (uint256[] memory field) {
        _warpToAwardGenesis();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _setDailyWord(craps.currentDayIndex(), PLAIN_WORD);
        _openDay();
        uint24 requestDay = craps.currentDayIndex() + 1;
        this.probe(ContractAddresses.GAME,
            abi.encodeWithSignature("lockJackpotBattle(uint24,uint256,uint24)", requestDay, 1_000 ether, 2), "dayseff_jackpot_lock");
        vm.prank(ContractAddresses.GAME);
        (,, uint256 remaining) = JackpotBattle(address(craps)).prepareJackpotBattle(7, 123);
        uint256 n = remaining < 50 ? remaining : 50;
        assertGt(n, 0);
        field = new uint256[](n);
        for (uint256 i; i < n; ++i) field[i] = uint256(_idFor(address(uint160(0xEF000 + i)))) | (uint256(1) << 181);
    }

    function test_DaysEffJackpotAppend() public {
        uint256[] memory field = _prepareMeasuredJackpot();
        emit log_named_uint("dayseff_jackpot_field_size", field.length);
        this.probe(ContractAddresses.GAME,
            abi.encodeWithSignature("appendJackpotBattle(uint256[],uint256,bool)", field, field.length, true), "dayseff_jackpot_append");
        (,,bool started,) = JackpotBattle(address(craps)).jackpotProgress();
        assertTrue(started);
    }

    function test_DaysEffJackpotWork() public {
        uint256[] memory field = _prepareMeasuredJackpot();
        vm.prank(ContractAddresses.GAME);
        JackpotBattle(address(craps)).appendJackpotBattle(field, field.length, true);
        bytes memory result = this.probe(ContractAddresses.GAME,
            abi.encodeWithSignature("runDailyBattleWork(uint256)", 10_000_000), "dayseff_jackpot_work");
        assertTrue(abi.decode(result, (MineFlipGas.Result)).progressed);
    }

    function test_DaysEffCustomEntry() public {
        uint64 slot = _openBattle(craps, 200, 2, 5, 1, 0);
        this.probe(alice, abi.encodeWithSignature("enterBattle(uint32,uint64,uint32,uint16)", 0, slot, SEVEN, 1), "dayseff_custom_entry");
    }
}
