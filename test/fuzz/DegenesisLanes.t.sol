// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";

/// @title DegenesisLanes -- packed order lanes, unit grid and the per-order bound (spec §1, check 2)
/// @notice Three 85-bit lanes per word (id 32 | units 38 | seconds 15), keyed day << 32 | i / 3.
///         Amounts are whole 0.0001 ETH units from 0.01 ETH up to 2^38 - 1 units (~27.5M ETH);
///         anything else reverts and leaves credit untouched. The lane settlement decodes is
///         the one the buy wrote: DegenesisOrderResolved carries the same id, index and amount.
contract DegenesisLanes is DegenesisHarness {
    address[7] internal who;

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 7; ++i) {
            who[i] = _player(string.concat("ln-", vm.toString(i)));
            _earnCredit(who[i], 3 ether);
        }
        _driveDay(2, 0);
    }

    struct Buy {
        uint32 id;
        uint8 day;
        uint32 index;
        uint256 amount;
        uint256 secs;
    }

    function _buys(Vm.Log[] memory logs) internal view returns (Buy[] memory out) {
        out = new Buy[](_countSig(logs, SIG_BUY));
        uint256 k;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0 || logs[i].topics[0] != SIG_BUY) continue;
            Buy memory b = out[k++];
            b.id = uint32(uint256(logs[i].topics[1]));
            (b.day, b.index, b.amount, b.secs) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256));
        }
    }

    /// @notice Lanes at index % 3 = 0, 1, 2 across three words: each decodes to its own buyer,
    ///         units and capped seconds; later OR-merges never disturb earlier lanes; bit 255 is
    ///         unused; settlement resolves each order with the decoded id and amount.
    function test_LanePackingAllPositions() public {
        uint256[7] memory secs = [uint256(3601), 3700, 21_599, 21_600, 21_601, 40_000, 86_000];
        uint256[7] memory amt = [uint256(0.01 ether), 1.2345 ether, 0.0101 ether, 2 ether, 0.5555 ether, 0.01 ether, 2.9999 ether];
        vm.recordLogs();
        for (uint256 i; i < 7; ++i) {
            vm.warp(_dayStart(2) + secs[i]);
            _buy(who[i], amt[i]);
            uint256 word0 = _orderSlot(1, 0);
            if (i >= 1 && i <= 2) assertEq(word0 & ((uint256(1) << 85) - 1), _lane(1, 0), "lane 0 undisturbed");
        }
        Buy[] memory buys = _buys(vm.getRecordedLogs());
        assertEq(buys.length, 7, "seven buys");
        for (uint256 i; i < 7; ++i) {
            uint256 lane = _lane(1, i);
            uint32 id = game.walletIdOf_g3120(who[i]);
            uint256 capped = secs[i] > BONUS_WINDOW ? BONUS_WINDOW : secs[i];
            assertEq(uint32(lane), id, "lane id");
            assertEq((lane >> 32) & MAX_UNITS, amt[i] / UNIT, "lane units");
            assertEq(lane >> 70, capped, "lane seconds (capped)");
            assertEq(buys[i].id, id, "event buyer");
            assertEq(buys[i].day, 1, "event cohort");
            assertEq(buys[i].index, i, "event index");
            assertEq(buys[i].amount, amt[i], "event amount");
            assertEq(buys[i].secs, capped, "event seconds");
        }
        for (uint256 w; w < 3; ++w) assertEq(_orderSlot(1, w * 3) >> 255, 0, "bit 255 unused");
        assertEq(_orderSlot(1, 6) >> 85, 0, "third word holds one lane");
        assertEq(_count(1), 7, "count");
        uint256 v;
        for (uint256 i; i < 7; ++i) v += amt[i];
        assertEq(_volumeUnits(1) * UNIT, v, "V in units");

        uint256 word = uint256(keccak256("lanes"));
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        Res[] memory want = _refCohort(1, word, q);
        assertEq(got.length, 7, "seven resolved");
        for (uint256 i; i < 7; ++i) {
            assertEq(got[i].id, buys[i].id, "resolved id = bought id");
            assertEq(got[i].index, buys[i].index, "resolved index = bought index");
            assertEq(got[i].amount, buys[i].amount, "resolved amount = bought amount");
            _assertRes(got[i], want[i], "lane order vs reference");
        }
    }

    function _expectBuyRevert(address p, uint256 amount) internal {
        uint256 credit = game.degenesisCreditOf(p);
        uint256 count = _count(1);
        vm.prank(p);
        vm.expectRevert();
        game.purchaseDegenesisBox{value: amount}(0, amount);
        assertEq(game.degenesisCreditOf(p), credit, "credit untouched on revert");
        assertEq(_count(1), count, "no order on revert");
    }

    /// @notice Unit grid and minimum: 0.01 ETH and any whole 0.0001 ETH above it are accepted;
    ///         below the minimum, or off the grid by any wei, reverts.
    function test_UnitGranularityAndMinimum() public {
        _warpTo(2, 2 hours);
        address p = who[0];
        _buy(p, 0.01 ether);
        _buy(p, 0.0101 ether);
        _buy(p, 0.0123 ether);
        _buy(p, 1 ether + 0.0001 ether);
        assertEq(_count(1), 4, "on-grid buys accepted");
        _expectBuyRevert(p, 0.0099 ether);
        _expectBuyRevert(p, 0.01 ether - 1);
        _expectBuyRevert(p, 0.01 ether + 1);
        _expectBuyRevert(p, 0.01 ether + 0.00005 ether);
        _expectBuyRevert(p, 0.0123 ether + 1 gwei);
        _expectBuyRevert(p, 0);
        // Credit is consumed 1:1 by the applied amount.
        assertEq(game.degenesisCreditOf(p), 3 ether - (0.01 ether + 0.0101 ether + 0.0123 ether + 1.0001 ether), "credit consumed 1:1");
        // A buy above the remaining credit reverts.
        _expectBuyRevert(p, game.degenesisCreditOf(p) + UNIT);
    }

    /// @notice The per-order bound: 2^38 - 1 units (~27.5M ETH) is accepted and settles with its
    ///         full amount; 2^38 units reverts. Credit for these sizes is written via vm.store
    ///         (a real 110M ETH qualifying spend is impractical).
    function test_PerOrderBound() public {
        _warpTo(2, 2 hours);
        address p = who[1];
        uint256 maxAmt = MAX_UNITS * UNIT;
        assertEq(maxAmt, 27_487_790.6943 ether, "documented ~27.5M ETH bound");
        _seedCredit(p, (MAX_UNITS + 2) * UNIT * 2);
        vm.deal(p, maxAmt * 3);
        _expectBuyRevert(p, (MAX_UNITS + 1) * UNIT);
        uint256 claimable0 = game.claimablePoolView();
        _buy(p, maxAmt);
        assertEq(game.claimablePoolView() - claimable0, maxAmt, "whole amount held in claimablePool");
        assertEq((_lane(1, 0) >> 32) & MAX_UNITS, MAX_UNITS, "units saturate the field exactly");
        assertEq(_volumeUnits(1), MAX_UNITS, "header V");
        _buy(who[2], 0.01 ether); // lane 1 after a full lane 0
        assertEq((_lane(1, 0) >> 32) & MAX_UNITS, MAX_UNITS, "lane 0 intact after merge");
        assertEq(uint32(_lane(1, 1)), game.walletIdOf_g3120(who[2]), "lane 1 id");

        uint256 word = uint256(keccak256("lanes-max"));
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(word);
        Res[] memory got = _resolved(vm.getRecordedLogs());
        Res[] memory want = _refCohort(1, word, q);
        assertEq(got.length, 2, "two resolved");
        assertEq(got[0].amount, maxAmt, "max order settles with its full amount");
        _assertRes(got[0], want[0], "max order vs reference");
        _assertRes(got[1], want[1], "small order vs reference");
        assertEq(_vaultBudget(), (maxAmt + 0.01 ether) / 4, "split exact at the bound");
    }

    /// @notice Fuzz: any on-grid amount in [0.01 ETH, credit] is accepted and its lane decodes to
    ///         the amount; any off-grid amount reverts.
    function testFuzz_GridAcceptsExactlyUnitMultiples(uint256 raw) public {
        _warpTo(2, 2 hours);
        address p = who[3];
        uint256 amount = bound(raw, 0, 3 ether);
        bool ok = amount >= MIN_ORDER && amount % UNIT == 0;
        if (!ok) {
            _expectBuyRevert(p, amount);
            return;
        }
        _buy(p, amount);
        assertEq((_lane(1, _count(1) - 1) >> 32) & MAX_UNITS, amount / UNIT, "lane units");
    }
}
