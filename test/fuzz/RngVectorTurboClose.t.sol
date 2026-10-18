// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title RngVectorTurboClose -- the turbo level-1 jackpot at the close of Degenesis is fixed at
///        its request
/// @notice With the next pool past the 50 ETH target, the day-9 request latches the one-day turbo
///         and the level becomes 1. Whatever players buy while that word is out (tickets at the
///         level-1 price, lootboxes, Degenesis boxes, which the closed sale refuses), the level-1
///         jackpot pays the same winners the same amounts, event for event, as the undisturbed run:
///         window buys sit in the write buffers and the pending pools until the next request.
contract RngVectorTurboClose is DegenesisFixture {
    bytes32 internal constant SIG_ETH_WIN = keccak256("JackpotEthWin(uint32,uint24,uint16,uint256,uint256)");
    bytes32 internal constant SIG_TICKET_WIN = keccak256("JackpotTicketWin(uint32,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 internal constant SIG_TICKET_BATCH =
        keccak256("JackpotTicketBatchWin(uint24,uint24,uint16,uint16,uint8,uint32,uint256[4],uint256[4])");
    bytes32 internal constant SIG_BATCH_TRAITS = keccak256("JackpotTicketBatchTraits(uint24,uint8,uint256[4],uint256[4])");
    bytes32 internal constant SIG_FLIP_WIN = keccak256("JackpotFlipWin(uint32,uint24,uint8,uint256,uint256)");
    bytes32 internal constant SIG_TRAITS = keccak256("DailyWinningTraits(uint24,uint32)");
    uint8 internal constant JACKPOT_TURBO = 1;

    address internal alice;
    address internal bob;

    function setUp() public override {
        super.setUp();
        alice = _player("tc-alice", 0);
        bob = _player("tc-bob", 0);
    }

    function _isJackpot(Vm.Log memory l) internal view returns (bool) {
        if (l.emitter != address(game) || l.topics.length == 0) return false;
        bytes32 t = l.topics[0];
        return t == SIG_ETH_WIN || t == SIG_TICKET_WIN || t == SIG_TICKET_BATCH || t == SIG_BATCH_TRAITS
            || t == SIG_FLIP_WIN || t == SIG_TRAITS;
    }

    function _jackpotEvents(Vm.Log[] memory logs) internal view returns (bytes32[] memory out) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) if (_isJackpot(logs[i])) ++n;
        out = new bytes32[](n);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (_isJackpot(logs[i])) out[n++] = keccak256(abi.encode(logs[i].topics, logs[i].data));
        }
    }

    function test_TurboJackpotIgnoresWindowPurchases() public {
        vm.deal(alice, 70 ether);
        _buyTickets(alice, 6700);
        assertGt(_nextPool(), 50 ether, "fixture: next pool past the level-1 target");
        _drain();
        _driveThrough(8);
        assertEq(_level(), 0, "level 0 through the sale");

        _warpDay(GameTimeLib.MAIN_LAUNCH_DAY, 1 hours);
        _drain(false, 400);
        assertTrue(game.rngLocked(), "the day-9 request is out");
        assertEq(_level(), 1, "level 1 at the request");
        assertEq(_jackpotFlags() & JACKPOT_TURBO, JACKPOT_TURBO, "turbo latched");

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _drain();
        bytes32[] memory plain = _jackpotEvents(vm.getRecordedLogs());
        vm.revertToStateAndDelete(snap);

        // Inside the window: tickets at the level-1 price, lootboxes, and a refused Degenesis box.
        vm.deal(bob, 100 ether);
        _buyTickets(bob, 300);
        _buyTickets(alice, 200);
        vm.prank(bob);
        game.purchase{value: 2 ether}(0, 0, BoxOrderLib.boCustom(2 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.deal(alice, alice.balance + 1 ether);
        vm.prank(alice);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        vm.recordLogs();
        _drain();
        bytes32[] memory mixed = _jackpotEvents(vm.getRecordedLogs());

        assertGt(plain.length, 5, "the turbo jackpot paid");
        assertEq(mixed.length, plain.length, "same jackpot event count");
        for (uint256 i; i < plain.length; ++i) assertEq(mixed[i], plain[i], "same jackpot event, in order");
        assertEq(_level(), 1, "level 1");
        assertFalse(_jackpotPhase(), "the one-day jackpot phase completed");
    }
}
