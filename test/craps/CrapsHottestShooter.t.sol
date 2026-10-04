// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {CrapsPins} from "./CrapsPins.sol";
import {CrapsViews} from "./CrapsViews.sol";
import {Craps} from "../../contracts/Craps.sol";
import {CrapsBattle, IReadCohortLifecycle} from "../../contracts/CrapsBattle.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {Vm} from "forge-std/Vm.sol";

contract HottestHarness is CrapsViews {
    function prime(uint64 slot, uint32 own, uint32 day, uint32 drawn, uint256 heat, uint256 lane) external {
        bytes32 key = bytes32(uint256(slot));
        uint256 total = uint256(own) + day + drawn;
        _battles[key] = total | (total << _BG_RESOLVED_SHIFT);
        _dayTickets[uint256(slot) / 8 * 8] = day;
        _jackpotRounds[slot].drawnCount = drawn;
        _highField[key] = lane | (heat << _HF_HOTTEST_SHIFT);
    }
    function pay(uint64 slot, uint256 winnerId, uint256 pot, uint256 boost, uint256 word) external {
        IReadCohortLifecycle(address(this)).payBattlePot(slot, bytes32(uint256(slot)), winnerId, pot, boost, word);
    }
    function heat(uint64 slot) external view returns (uint256) {
        return (_highField[bytes32(uint256(slot))] >> _HF_HOTTEST_SHIFT) & _HF_HOTTEST_MASK;
    }
    function sideboard(uint64 slot) external view returns (uint256) { return _highField[bytes32(uint256(slot))]; }
}

contract CrapsHottestShooterTest is CrapsPins {
    HottestHarness table;
    address alice = makeAddr("hot-alice");
    address bob = makeAddr("hot-bob");
    uint64 constant SLOT = 82;
    uint256 constant WORD = 923;
    bytes32 constant HOT_EVENT = keccak256("CrapsHottestShooterPaid(uint256,bytes32,address,uint16,uint256)");

    function setUp() public { _installPins(); table = new HottestHarness(); }

    function _heatForSeat(uint256 seat, uint256 n, uint256 rolls) private pure returns (uint256) {
        bytes32 seed = keccak256(abi.encode(keccak256("degenerus.lootbox.craps.v1"), WORD, uint256(SLOT)));
        uint256 start = uint256(keccak256(abi.encode(uint256(0x526f746174696e6753686f6f746572), seed))) % n;
        uint256 hand = (seat + n - 1 - start) % n;
        return (rolls << 9) | (511 - hand);
    }

    function _bet(uint256 slot, uint256 seat, address player, bool high) private returns (uint256 id) {
        id = (slot << 64) | seat;
        table.setBetWord(id, uint160(player) | (high ? 1 << 217 : 0));
    }

    // payBattlePot must creditFlip exactly the two conserved liquid shares.
    function test_tenPercentGoesToHottestAndHighLaneIsUntouched() public {
        uint256 winner = _bet(SLOT, 1, alice, false);
        _bet(SLOT, 2, bob, true);
        uint256 lane = 2 | (uint256(123) << 32) | (uint256(2) << 137) | (1 << 169);
        table.prime(SLOT, 2, 0, 0, _heatForSeat(2, 2, 38), lane);
        uint256 before = table.sideboard(SLOT);
        uint256 pot = 1001 + 7;
        table.pay(SLOT, winner, pot, 0, WORD);
        assertEq(coinflip.staked(bob), pot / 10, "high roller is eligible for the regular prize");
        assertEq(coinflip.staked(alice), pot - pot / 10);
        assertEq(coinflip.totalCredited(), pot, "pot conservation including dust");
        assertEq(table.sideboard(SLOT), before, "high-lane accounting changed");
    }

    function test_battleWinnerCanAlsoBeHottest() public {
        uint256 winner = _bet(SLOT, 1, alice, false);
        table.prime(SLOT, 1, 0, 0, _heatForSeat(1, 1, 9), 0);
        table.pay(SLOT, winner, 1234, 0, WORD);
        assertEq(coinflip.staked(alice), 1234);
    }

    function test_dayAndAwardedSeatsUseDenseRotationOrdinals() public {
        uint256 winner = _bet(SLOT, 1, alice, false);
        uint256 dayId = _bet(80, 1, bob, false);
        uint256 awardId = _bet(SLOT, 2, bob, false);
        for (uint256 seat = 2; seat <= 3; ++seat) {
            table.prime(SLOT, 1, 1, 1, _heatForSeat(seat, 3, 20), 0);
            vm.recordLogs();
            table.pay(SLOT, winner, 1000, 0, WORD);
            Vm.Log[] memory logs = vm.getRecordedLogs();
            bool found;
            for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == HOT_EVENT) {
                found = true;
                assertEq(uint256(logs[i].topics[1]), seat == 2 ? dayId : awardId);
                (uint16 rolls, uint256 paid) = abi.decode(logs[i].data, (uint16, uint256));
                assertEq(rolls, 20); assertEq(paid, 100);
            }
            assertTrue(found);
        }
    }

    function test_protocolPassSplitsConserveBothRecipientsShares() public {
        uint256 winner = _bet(SLOT, 1, alice, false);
        _bet(SLOT, 2, bob, false);
        table.prime(SLOT, 2, 0, 0, _heatForSeat(2, 2, 27), 0);
        uint256 pot = 1_000_000;
        uint256 boost = 900_000;
        table.pay(SLOT, winner, pot, boost, WORD);
        (uint256 an, uint256 ah) = table.passCreditsOf(alice);
        (uint256 bn, uint256 bh) = table.passCreditsOf(bob);
        uint256 av = an * table.NORMAL_PASS_VALUE() + ah * table.HIGH_PASS_VALUE();
        uint256 bv = bn * table.NORMAL_PASS_VALUE() + bh * table.HIGH_PASS_VALUE();
        assertEq(coinflip.staked(alice) + av, pot - pot / 10);
        assertEq(coinflip.staked(bob) + bv, pot / 10);
        assertGt(av, 0); assertGt(bv, 0);
    }

    function test_customBattleKeepsItsWholePot() public {
        uint64 slot = (1 << 40) + 1;
        uint256 winner = _bet(slot, 1, alice, false);
        table.pay(slot, winner, 1000, 0, WORD);
        assertEq(coinflip.staked(alice), 1000);
        assertEq(coinflip.credits(), 1);
    }

    function test_externalCallerCannotInvokePayout() public {
        vm.expectRevert(JackpotBattle.OnlyTableSelf.selector);
        IReadCohortLifecycle(address(table)).payBattlePot(SLOT, bytes32(uint256(SLOT)), 1, 1000, 0, WORD);
    }

    function test_zeroPotDoesNotCreateCredit() public {
        uint256 winner = _bet(SLOT, 1, alice, false);
        table.prime(SLOT, 1, 0, 0, _heatForSeat(1, 1, 30), 0);
        table.pay(SLOT, winner, 0, 0, WORD);
        assertEq(coinflip.credits(), 0);
    }
}
