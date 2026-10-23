// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {ChainPinBase, ModuleSpy} from "./ChainPinAdvanceDriven.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {IDegenerusGameTicketModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Reports the ticket worker's drain cursors and the marker queue's total owed around each call.
contract TicketDrainProbe is ModuleSpy {
    event TWPre(uint24 marker, uint256 cursor, uint256 seats, uint256 qlen, uint256 solo, uint256 owed, uint256 gasLeft);
    event TWPost(
        uint24 marker, uint256 cursor, uint256 seats, uint256 solo, uint256 owed, uint256 gasLeft, bool progressed,
        bool done
    );

    function _real() internal pure override returns (address) {
        return address(uint160(uint256(keccak256("chainpin.ticket.real"))));
    }

    function _owedSum() private view returns (uint256 sum) {
        uint24 key = ticketLevel;
        if (key == 0) return 0;
        uint256 n = _ticketQueueLength(key);
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        for (uint256 i; i < n; ++i) sum += uint32(_entryPacked(key, _tqPositionAt(q, i)) >> 8);
    }

    function _enter() internal override {
        if (msg.sig != IDegenerusGameTicketModule.runTicketWork_g1150.selector) return;
        emit TWPre(ticketLevel, ticketCursor, ticketSeats, _ticketQueueLength(ticketLevel), ticketSoloOffset, _owedSum(), gasleft());
    }

    function _leave(bytes memory ret) internal override {
        if (msg.sig != IDegenerusGameTicketModule.runTicketWork_g1150.selector) return;
        (bool progressed, bool done,) = abi.decode(ret, (bool, bool, uint256));
        emit TWPost(ticketLevel, ticketCursor, ticketSeats, ticketSoloOffset, _owedSum(), gasleft(), progressed, done);
    }
}

/// @notice Ticket-stage drain after paid deity passes past the price-doubling anchor (each confers a lootbox of 5%
///         of its price): per-call cursor movement, entries per call and the extrapolated drain length.
contract ChainPinTicketDrain is ChainPinBase {
    bytes32 private constant PRE = TicketDrainProbe.TWPre.selector;
    bytes32 private constant POST = TicketDrainProbe.TWPost.selector;
    bytes32 private constant TRAITS = keccak256("TraitsGenerated(uint32,uint256,uint32)");

    uint256 private deepCalls;
    uint256 private deepEntries;
    uint256 private deepGas;
    uint256 private stalledCalls;
    uint256 private firstOwed;
    uint256 private lastOwed;
    uint256 private maxEntriesPerCall;
    uint256 private ticketCallsTotal;
    uint256 private rungSum;
    uint256 private lastLogCount;
    uint256 private doneCalls;
    uint256 private maxDayCalls2;

    // pre/post of the current call
    uint256 private cCursor; uint256 private cSeats; uint256 private cSolo; uint256 private cOwed; uint256 private cGas; uint24 private cMarker; uint256 private cQlen;

    function setUp() public {
        _setUpWorld(false);
        address real = address(uint160(uint256(keccak256("chainpin.ticket.real"))));
        vm.etch(real, ContractAddresses.GAME_TICKET_MODULE.code);
        vm.etch(ContractAddresses.GAME_TICKET_MODULE, type(TicketDrainProbe).runtimeCode);
    }

    function _buyPaidDeities() private {
        uint256 sold;
        for (uint8 sym = 1; sym < 32 && sold < 30; ++sym) {
            if (sym == 6) continue;
            address who = address(uint160(0xDE170000 + sym));
            uint256 price = sold <= 23 ? 24 ether + (sold * (sold + 1) * 1 ether) / 2 : (300 ether << (sold - 23));
            vm.deal(who, price);
            vm.prank(who);
            game.purchaseDeityPass{value: price}(0, sym, bytes32(0));
            ++sold;
        }
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOLS_PACKED), bytes32((uint256(100 ether) << 128) | 1 ether));
    }

    /// @dev One engine call; `fixedGas == 0` uses the smallest-admitting ladder. Returns the rung that succeeded.
    function _callOnce(uint256 fixedGas) private returns (bool ok, uint256 rung) {
        uint256[6] memory ladder = [uint256(1_500_000), 2_500_000, 3_500_000, 5_000_000, 9_000_000, 16_777_216];
        if (fixedGas != 0) {
            (bool o, bytes4 sel) = this.mineOnce(fixedGas);
            if (!o && sel != NO_WORK_SEL && sel != RNG_NOT_READY_SEL && sel != MineFlipGas.InsufficientExecutionGas.selector) {
                revert(string.concat("mineFlip reverted ", vm.toString(sel)));
            }
            return (o, fixedGas);
        }
        for (uint256 r; r < 6; ++r) {
            (bool o, bytes4 sel) = this.mineOnce(ladder[r]);
            if (o) return (true, ladder[r]);
            if (sel == MineFlipGas.InsufficientExecutionGas.selector) continue;
            if (sel == NO_WORK_SEL || sel == RNG_NOT_READY_SEL) return (false, 0);
            revert(string.concat("mineFlip reverted ", vm.toString(sel)));
        }
        return (false, 0);
    }

    bytes4 private constant NO_WORK_SEL = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY_SEL = bytes4(keccak256("RngNotReady()"));

    function _observe(Vm.Log[] memory logs, uint256 rung) private {
        uint256 entries;
        bool pre; bool post;
        bool progressed; bool done;
        uint256 pMarker; uint256 pCursor; uint256 pSeats; uint256 pSolo; uint256 pOwed; uint256 pGas;
        uint256 qlen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            bytes32 t = logs[i].topics[0];
            if (t == PRE && !pre) {
                pre = true;
                uint256 m; uint256 c; uint256 s; uint256 ql; uint256 so; uint256 ow; uint256 g;
                (m, c, s, ql, so, ow, g) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256, uint256, uint256));
                cMarker = uint24(m); cCursor = c; cSeats = s; cQlen = ql; cSolo = so; cOwed = ow; cGas = g;
            } else if (t == POST) {
                post = true;
                lastLogCount++;
                (pMarker, pCursor, pSeats, pSolo, pOwed, pGas, progressed, done) =
                    abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256, uint256, bool, bool));
            }
        }
        if (!pre || !post) return;
        entries = pMarker == cMarker && cOwed >= pOwed ? cOwed - pOwed : 0;
        ++ticketCallsTotal;
        if (done) ++doneCalls;
        bool deep = cSeats != 0 && cCursor == cQlen && cQlen != 0;
        if (!deep) return;
        ++deepCalls;
        rungSum += rung;
        deepEntries += entries;
        deepGas += cGas - pGas;
        if (entries > maxEntriesPerCall) maxEntriesPerCall = entries;
        if (firstOwed == 0) firstOwed = cOwed;
        lastOwed = pOwed;
        bool advanced = pOwed < cOwed || pSolo != cSolo || pCursor != cCursor || pSeats != cSeats || pMarker != cMarker;
        if (!advanced) ++stalledCalls;
        if (deepCalls <= 8) {
            emit log_named_uint("deep call", deepCalls);
            emit log_named_uint("  rung gas", rung);
            emit log_named_uint("  marker", cMarker);
            emit log_named_uint("  cursor/qlen", cCursor * 1000 + cQlen);
            emit log_named_uint("  seats pre", cSeats);
            emit log_named_uint("  seats post", pSeats);
            emit log_named_uint("  soloOffset pre", cSolo);
            emit log_named_uint("  soloOffset post", pSolo);
            emit log_named_uint("  queue owed pre", cOwed);
            emit log_named_uint("  queue owed post", pOwed);
            emit log_named_uint("  entries materialized", entries);
            emit log_named_uint("  worker gas used", cGas - pGas);
            emit log_named_uint("  progressed", progressed ? 1 : 0);
            emit log_named_uint("  done", done ? 1 : 0);
        }
    }

    function _run(uint256 fixedGas, uint256 stopAfterDeep) private {
        _buyPaidDeities();
        _settleToday();
        vm.resumeGasMetering();
        for (uint256 d; d < 12; ++d) {
            if (!game.jackpotPhase()) {
                _seedNextPrizePool(_levelPrizePool(game.level()) + 25 ether);
                _buyTickets();
            }
            simTime += 1 days + 1;
            vm.warp(simTime);
            for (uint256 i; i < 40_000; ++i) {
                if (i > maxDayCalls2) maxDayCalls2 = i;
                _fulfillPending();
                vm.getRecordedLogs();
                (bool ok, uint256 rung) = _callOnce(fixedGas);
                if (!ok) break;
                _observe(vm.getRecordedLogs(), rung);
                if (deepCalls >= stopAfterDeep) return;
            }
            vm.getRecordedLogs();
        }
    }

    function _report() private {
        emit log_named_uint("ticket-stage calls observed", ticketCallsTotal);
        emit log_named_uint("deep (seat-tail) calls", deepCalls);
        emit log_named_uint("calls that moved no cursor/count", stalledCalls);
        emit log_named_uint("entries materialized, total over deep calls", deepEntries);
        emit log_named_uint("max entries in one call", maxEntriesPerCall);
        emit log_named_uint("worker gas per deep call (avg)", deepCalls == 0 ? 0 : deepGas / deepCalls);
        emit log_named_uint("avg rung gas", deepCalls == 0 ? 0 : rungSum / deepCalls);
        emit log_named_uint("queue owed at first deep call", firstOwed);
        emit log_named_uint("queue owed after last observed call", lastOwed);
        uint256 per = deepCalls == 0 ? 0 : deepEntries / deepCalls;
        emit log_named_uint("entries per deep call (avg)", per);
        emit log_named_uint("extrapolated calls to drain the first queue", per == 0 ? 0 : firstOwed / per);
        emit log_named_uint("worker invocations that reported done", doneCalls);
        emit log_named_uint("most mining calls in one day", maxDayCalls2);
    }

    function test_drain_ladderGas() public {
        _run(0, 300);
        _report();
        assertGt(deepCalls, 0, "reached the seat-tail drain");
        assertEq(stalledCalls, 0, "every successful ticket call moves a cursor or count");
    }

    function test_drain_16M() public {
        _run(16_777_216, type(uint256).max);
        _report();
        assertGt(deepCalls, 0, "reached the seat-tail drain");
        assertGt(deepEntries / deepCalls, 1000, "at 16.7M a call materializes thousands of entries");
        assertLt(maxDayCalls2, 400, "a day drains in a few hundred 16.7M calls");
        assertEq(stalledCalls, 0, "every successful ticket call moves a cursor or count");
    }
}
