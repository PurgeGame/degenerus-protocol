// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {CrapsProgressiveTest, ProgHarness} from "../craps/CrapsProgressive.t.sol";
import {NativeGasExport} from "../helpers/NativeGasExport.sol";

Vm constant G7VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

/// @dev Gross gas of the last call, before refunds (limit - remaining). Under --isolate this
///      includes the intrinsic cost; refunds never reduce it, matching gasleft()-based metering.
function g7Gross() view returns (uint256) {
    // Under --isolate gasTotalUsed is net of the transaction refund; add the refund counter
    // back so the figure is the gross execution a gasleft()-based meter sees (conservative).
    Vm.Gas memory g = G7VM.lastCallGas();
    return uint256(g.gasTotalUsed) + (g.gasRefunded > 0 ? uint256(int256(g.gasRefunded)) : 0);
}

function g7Refund() view returns (int256) {
    return int256(G7VM.lastCallGas().gasRefunded);
}


/// @dev ProgHarness plus raw writers for the forced final-seat state.
contract G7ProgHarness is ProgHarness {
    /// @dev Replace the scoreboard's best composite and the seat holding it, as `_scoreBattle` does.
    function g7SeedBest(bytes32 key, uint256 best, uint64 seat) external {
        uint256 g = _loadBattle(key);
        g = (g & ~((_SC_BEST_MASK << _BG_BEST_SHIFT) | (uint256(_MASK32) << _BG_WINNER_SHIFT)))
            | (best << _BG_BEST_SHIFT) | (uint256(seat) << _BG_WINNER_SHIFT);
        _storeBattle(key, g);
    }
    function g7Battle(bytes32 key) external view returns (uint256) { return _loadBattle(key); }
    function g7HighField(bytes32 key) external view returns (uint256) { return _loadHighField(key); }
}

/// @notice G7: the craps finalizing seat paying every award at once (original bound 1.65M).
///         A routine scheduled window with a contested high lane: the LAST seat (a high seat) runs
///         its engine, folds the lane, closes the scoreboard and finalizes in the same seat: comp
///         credit, hottest-shooter tenth (+pass split), main pot (+pass split), contested lane
///         (+pass split), rare progressive (+pass split), dice-run record arm, RNG-slot completion.
///         Forced inputs: the scoreboard's best composite (a goal with a high point far past the
///         rare progressive cutoff and the record floor) and the progressive pool balance.
///         Callees COIN/COINFLIP/GAME are the suite's mocks; their real cold costs are measured
///         separately (G7CrapsCalleeGas) and added in the report.
contract CrapsFinalSeatNativeGasTest is CrapsProgressiveTest, NativeGasExport {
    bytes32 private constant HOT_SIG = keccak256("CrapsHottestShooterPaid(uint256,bytes32,uint32,uint16,uint256)");
    bytes32 private constant POT_SIG = keccak256("CrapsBattlePaid(uint256,bytes32,uint32,uint256)");
    bytes32 private constant LANE_SIG = keccak256("CrapsHighRollerPaid(uint256,bytes32,uint32,uint256,bool)");
    bytes32 private constant PROG_SIG = keccak256(
        "CrapsProgressivePaid(uint256,bytes32,uint32,bool,uint16,uint256,uint256,uint256,uint256,uint256)"
    );

    function _stubCallees() private {
        address originalGame = address(uint160(uint256(keccak256("native-craps-game-original"))));
        vm.etch(originalGame, ContractAddresses.GAME.code);
        vm.etch(ContractAddresses.GAME, address(new CrapsNativeGameStub(originalGame)).code);
        vm.etch(ContractAddresses.COINFLIP, type(CrapsNativeCreditStub).runtimeCode);
        vm.etch(ContractAddresses.COIN, type(CrapsNativeCreditStub).runtimeCode);
    }

    function g7Intrinsic(bytes memory data) private pure returns (uint256 g) {
        g = 21_000;
        for (uint256 i; i < data.length; ++i) g += data[i] == 0 ? 4 : 16;
    }

    function g7FundedDay() private {
        vm.warp(_dayStart() + 10 days + _closeOf(PER - 1));
        uint24 today = craps.currentDayIndex();
        for (uint256 i = 1; i <= craps.BOOST_ACTION_WINDOW_DAYS(); ++i) {
            craps.bookDay(today - uint24(i), 400_000_000);
            craps.bookHighDay(today - uint24(i), 400_000_000);
        }
        _setDailyWord(today, PLAIN_WORD);
        _openDay();
    }

    function test_G7_CrapsFinalSeatEveryAward() public {
        vm.etch(address(craps), address(new G7ProgHarness()).code);
        G7ProgHarness h = G7ProgHarness(address(craps));
        g7FundedDay();
        uint16 floor_ = uint16(craps.SYBIL_SCORE_FLOOR());
        // Eight seats, the first and last (and two between) high: a contested lane whose last
        // high seat is the field's final seat.
        uint256 lastBet;
        for (uint160 i; i < 8; ++i) {
            address who = address(0x7700 + i);
            game.registerWallet_g9539(who, true);
            lastBet = (i % 3 == 0 || i == 7) ? _seatHigh(who, PER, floor_) : _seat(who, PER, floor_);
        }
        _warpPastClose(PER);
        uint48 index = _armAt(PER);
        _setWord(index, uint256(keccak256("G7 final seat")));
        uint64 slot = _slotAt(PER);
        bytes32 key = _keyOf(PER);
        craps.resolveSeats(slot, 7);
        assertEq(craps.bonusCursorOf(slot), 7, "all but the final seat settled");
        craps.seedProgressive(50_000_000);
        // Goal composite: high point 10^9 FLIP (score >> rare cutoff and >> record floor).
        h.g7SeedBest(key, craps.goalScore(1_000_000_000, 1_000_000_000, 0), 1);

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        vm.expectCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("armDiceRunRecord(uint32,uint256)"));
        vm.expectCall(ContractAddresses.COIN, abi.encodeWithSignature("creditCrapsComps_g37225(uint256)"));
        bytes memory data = abi.encodeWithSignature("settleGas(uint64,uint256)", slot, uint256(30_000_000));
        (bool ok,) = address(craps).call{gas: 40_000_000}(data);
        assertTrue(ok, "final seat settles");
        uint256 used = g7Gross();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 hot; uint256 pot; uint256 lane; uint256 prog; uint256 splits;
        bytes32 splitSig = keccak256("CrapsProtocolAwardSplit(bytes32,uint32,uint8,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            bytes32 t = logs[i].topics[0];
            if (t == HOT_SIG) ++hot;
            else if (t == POT_SIG) ++pot;
            else if (t == LANE_SIG) ++lane;
            else if (t == PROG_SIG) ++prog;
            else if (t == splitSig) ++splits;
        }
        assertTrue(craps.battleOf(key).finalized, "field finalized in the final seat");
        emit log_named_uint("G7 CRAPS final seat: hottest-shooter payments", hot);
        emit log_named_uint("G7 CRAPS final seat: main pot payments", pot);
        emit log_named_uint("G7 CRAPS final seat: lane payments (incl. sole-rider logs)", lane);
        emit log_named_uint("G7 CRAPS final seat: progressive payments", prog);
        emit log_named_uint("G7 CRAPS final seat: protocol pass splits", splits);
        emit log_named_uint("G7 CRAPS final seat call gas (tx total; mocked callees)", used);
        emit log_named_uint("G7 CRAPS final seat call gas minus intrinsic", used - g7Intrinsic(data));
        assertEq(hot, 1, "hottest shooter paid");
        assertEq(pot, 1, "main pot paid");
        assertGe(lane, 1, "contested lane paid");
        assertEq(prog, 1, "progressive paid");
        assertTrue(vm.revertToState(snap));

        // The same final seat with every external callee stubbed (near-zero cost), so the real
        // cold callee costs measured in G7CrapsCalleeGas can be added without double counting.
        _stubCallees();
        (ok,) = address(craps).call{gas: 40_000_000}(data);
        assertTrue(ok, "stubbed final seat settles");
        emit log_named_uint("G7 CRAPS final seat, callees stubbed, minus intrinsic", g7Gross() - g7Intrinsic(data));
        assertTrue(craps.battleOf(key).finalized, "stubbed field finalized");
        assertTrue(vm.revertToState(snap));

        // The final seat's own engine run, alone (a view over the same committed inputs).
        bytes memory view_ = abi.encodeWithSignature("settlementOf(uint256)", lastBet);
        (ok,) = address(craps).call{gas: 40_000_000}(view_);
        assertTrue(ok);
        emit log_named_uint("G7 CRAPS final seat engine-only view gas minus intrinsic", g7Gross() - g7Intrinsic(view_));
        emit log_named_uint("G7 CRAPS seat admission CRAPS_SEAT_GAS_MAX", GasBounds.CRAPS_SEAT_GAS_MAX);
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            assertTrue(vm.revertToState(snap));
            this.exportNativeFixture("craps-final-seat-all-awards", address(this), address(craps), data);
            assertTrue(vm.revertToState(snap));
            _stubCallees();
            this.exportNativeFixture("craps-final-seat-stubbed-callees", address(this), address(craps), data);
        }
        vm.deleteStateSnapshot(snap);
    }
}


/// @dev Native equivalents of the original calibration's external no-op mocks.
contract CrapsNativeCreditStub {
    function creditFlip_g317(uint32, uint256) external pure {}
    function creditFlipBatch(uint32[] calldata, uint256[] calldata) external pure {}
    function armDiceRunRecord(uint32, uint256) external pure returns (uint256) { return 0; }
    function creditCrapsComps_g37225(uint256) external pure {}
}
contract CrapsNativeGameStub {
    address private immutable ORIGINAL;
    constructor(address original) { ORIGINAL = original; }
    function setCrapsRngPending_g1406(uint48, bool) external pure {}
    fallback() external {
        address target = ORIGINAL;
        assembly ("memory-safe") {
            let p := mload(0x40)
            calldatacopy(p, 0, calldatasize())
            let ok := delegatecall(gas(), target, p, calldatasize(), 0, 0)
            returndatacopy(p, 0, returndatasize())
            switch ok case 0 { revert(p, returndatasize()) } default { return(p, returndatasize()) }
        }
    }
}

contract CrapsCalleeNativeGasTest is DeployProtocol, NativeGasExport {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    uint256 private nativeCase;
    function g7Intrinsic(bytes memory data) private pure returns (uint256 gas_) {
        gas_ = 21_000;
        for (uint256 i; i < data.length; ++i) gas_ += data[i] == 0 ? 4 : 16;
    }
    function g7AsCraps(address target, bytes memory data) private returns (uint256) {
        uint256 snapshot = vm.snapshotState();
        vm.prank(address(crapsBattle));
        (bool ok,) = target.call{gas: 30_000_000}(data);
        assertTrue(ok, "callee call succeeds");
        uint256 used = g7Gross() - g7Intrinsic(data) + 2_600;
        if (bytes(vm.envOr("STORAGE_REUSE_EXPORT", string(""))).length != 0) {
            uint256 post = vm.snapshotState();
            assertTrue(vm.revertToState(snapshot));
            this.exportNativeFixture(string.concat("craps-real-callee-", vm.toString(nativeCase)), address(crapsBattle), target, data);
            assertTrue(vm.revertToState(post));
            vm.deleteStateSnapshot(post);
        }
        ++nativeCase;
        vm.deleteStateSnapshot(snapshot);
        return used;
    }

    function test_G7_CrapsCalleeColdCosts() public {
        uint32[4] memory ids;
        for (uint256 i; i < 4; ++i) ids[i] = _giveWalletId(address(uint160(0xC7A000 + i)));
        uint256 worstFresh;
        for (uint256 i; i < 4; ++i) {
            uint256 g = g7AsCraps(address(coinflip), abi.encodeWithSignature("creditFlip_g317(uint32,uint256)", ids[i], uint256(5_000_000)));
            if (g > worstFresh) worstFresh = g;
        }
        uint256 repeat = g7AsCraps(address(coinflip), abi.encodeWithSignature("creditFlip_g317(uint32,uint256)", ids[0], uint256(5_000_000)));
        vm.prank(address(game));
        coinflip.fundRecordPool(1_000_000);
        uint32 recordId = _giveWalletId(address(0xC7A100));
        uint256 record = g7AsCraps(address(coinflip), abi.encodeWithSignature("armDiceRunRecord(uint32,uint256)", recordId, uint256(1e15)));
        uint256 comps = g7AsCraps(address(coin), abi.encodeWithSignature("creditCrapsComps_g37225(uint256)", uint256(123_456)));
        // A pending bit to clear, then the clear (Game._tryCompleteRng runs on false).
        vm.prank(address(crapsBattle));
        game.setCrapsRngPending_g1406(0, true);
        uint256 pending = g7AsCraps(address(game), abi.encodeWithSignature("setCrapsRngPending_g1406(uint48,bool)", uint48(0), false));
        // The batched credit flush: per-recipient cost against CRAPS_CREDIT_GAS_MAX.
        uint32[] memory batchIds = new uint32[](96);
        uint256[] memory amounts = new uint256[](96);
        for (uint256 i; i < 96; ++i) {
            batchIds[i] = _giveWalletId(address(uint160(0xC7B000 + i)));
            amounts[i] = 1_000;
        }
        uint256 batch = g7AsCraps(address(coinflip), abi.encodeWithSignature("creditFlipBatch(uint32[],uint256[])", batchIds, amounts));
        emit log_named_uint("G7 CALLEE creditFlip fresh recipient (worst of 4)", worstFresh);
        emit log_named_uint("G7 CALLEE creditFlip repeat recipient", repeat);
        emit log_named_uint("G7 CALLEE armDiceRunRecord new record", record);
        emit log_named_uint("G7 CALLEE FLIP.creditCrapsComps_g37225", comps);
        emit log_named_uint("G7 CALLEE Game.setCrapsRngPending(false)", pending);
        emit log_named_uint("G7 CALLEE creditFlipBatch 96 fresh recipients", batch);
        emit log_named_uint("G7 CALLEE creditFlipBatch per recipient", batch / 96);
        emit log_named_uint("G7 CALLEE CRAPS_CREDIT_GAS_MAX", GasBounds.CRAPS_CREDIT_GAS_MAX);
    }
}
