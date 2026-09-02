// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @dev Exposes the storage contract's queue-key derivation so the test reads the
///      exact keys the production strided walks write.
contract WBBKeyComputer is DegenerusGameStorage {
    function writeKey(uint24 lvl, bool ws) external pure returns (uint24) {
        return ws ? lvl | TICKET_SLOT_BIT : lvl;
    }

    function farFutureKey(uint24 lvl) external pure returns (uint24) {
        return _tqFarFutureKey(lvl);
    }
}

/// @title Whale pass bulk-buy bonus
/// @notice Every 5 passes in one `purchaseWhalePass` call award one more pass's entries,
///         shaped exactly like a paid pass (20 entries/level over the intro window, then one
///         whole ticket every 2nd level). The bonus is entries only: price, freeze, lootbox
///         and Craps credit follow the paid quantity. Qualification is per call: 3 passes
///         then 2 passes earn nothing.
///
///         Read back through the production path (full deployment, real keys): per-level
///         owed entries at every level of the span equal the paid shape for
///         quantity + floor(quantity / 5), the level past the span stays empty, and the
///         extra entries equal one paid pass's entries per bonus pass.
contract WhaleBulkBuyBonusTest is DeployProtocol {
    event LootBoxBuy(address indexed buyer, uint48 indexed index, uint256 amount);

    uint256 private constant SLOT_0 = 0;
    uint256 private constant TICKET_QUEUE_SLOT = 12;
    uint256 private constant ENTRIES_OWED_SLOT = 13;
    uint256 private constant LEVEL_SHIFT = 96;
    uint256 private constant WRITE_SLOT_SHIFT = 200;

    uint256 private constant WHALE_EARLY_PRICE = 2.4 ether;
    uint256 private constant WHALE_STANDARD_PRICE = 4 ether;

    WBBKeyComputer private keys;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        keys = new WBBKeyComputer();
    }

    // ── storage readers ──────────────────────────────────────────────────────

    function _setLevel(uint24 lvl) private {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT_0)));
        uint256 mask = uint256(0xFFFFFF) << LEVEL_SHIFT;
        vm.store(address(game), bytes32(SLOT_0), bytes32((s0 & ~mask) | (uint256(lvl) << LEVEL_SHIFT)));
    }

    function _keyFor(uint24 lvl) private view returns (uint24) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(SLOT_0)));
        uint24 cur = uint24(s0 >> LEVEL_SHIFT);
        bool ws = ((s0 >> WRITE_SLOT_SHIFT) & 1) != 0;
        return lvl > cur + 5 ? keys.farFutureKey(lvl) : keys.writeKey(lvl, ws);
    }

    function _owedAt(uint24 lvl, address who) private view returns (uint32) {
        bytes32 first = keccak256(abi.encode(uint256(_keyFor(lvl)), ENTRIES_OWED_SLOT));
        bytes32 second = keccak256(abi.encode(uint256(uint160(who)), uint256(first)));
        return uint32(uint256(vm.load(address(game), second)) >> 8);
    }

    function _queueLenAt(uint24 lvl) private view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(_keyFor(lvl)), TICKET_QUEUE_SLOT));
        return uint256(vm.load(address(game), slot));
    }

    // ── expected shapes ──────────────────────────────────────────────────────

    /// @dev Paid awards for `q` passes bought at `passLevel`: 20q entries/level over the
    ///      intro window (passLevel..9), then 2q half-passes over the rest as whole tickets
    ///      (base 4·floor(q/2) per level, plus one ticket every 2nd level when q is odd).
    function _paid(uint24 passLevel, uint24 lvl, uint256 q) private pure returns (uint256) {
        if (lvl < passLevel || lvl > passLevel + 99) return 0;
        if (lvl <= 9) return 20 * q;
        uint24 stdStart = passLevel > 9 ? passLevel : 10;
        uint256 owed = 4 * (q / 2);
        if (q % 2 == 1 && (lvl - stdStart) % 2 == 0) owed += 4;
        return owed;
    }

    /// @dev Bonus entries at `lvl`: the paid shape for q + floor(q/5) less the paid shape for q.
    function _bonus(uint24 passLevel, uint24 lvl, uint256 q) private pure returns (uint256) {
        return _paid(passLevel, lvl, q + q / 5) - _paid(passLevel, lvl, q);
    }

    /// @dev Entries `q` passes queue over the whole span (paid shape).
    function _spanTotal(uint24 passLevel, uint256 q) private pure returns (uint256 sum) {
        for (uint24 lvl = passLevel; lvl <= passLevel + 99; ++lvl) sum += _paid(passLevel, lvl, q);
    }

    function _buy(address who, uint256 q) private returns (uint24 passLevel) {
        passLevel = game.level() + 1;
        uint256 unit = passLevel <= 4 ? WHALE_EARLY_PRICE : WHALE_STANDARD_PRICE;
        vm.deal(who, unit * q);
        vm.prank(who);
        game.purchaseWhalePass{value: unit * q}(who, q, bytes32(0));
    }

    /// @dev Walk passLevel..passLevel+100, assert each level's owed against paid + bulk and
    ///      exactly-once queue membership for the buyer's own levels; return the bulk sum.
    function _checkSpan(address who, uint24 passLevel, uint256 q) private view returns (uint256 bulkSum) {
        for (uint24 lvl = passLevel; lvl <= passLevel + 100; ++lvl) {
            uint256 paid = _paid(passLevel, lvl, q + q / 5);
            assertEq(_owedAt(lvl, who), paid, string.concat("owed at level ", vm.toString(lvl)));
            bulkSum += _bonus(passLevel, lvl, q);
        }
    }

    // ── bonus shape ──────────────────────────────────────────────────────────

    function testBelowFiveEarnsNoBonus() public {
        for (uint256 q = 1; q <= 4; ++q) {
            address who = makeAddr(string.concat("small", vm.toString(q)));
            uint24 passLevel = _buy(who, q);
            assertEq(_checkSpan(who, passLevel, q), 0, "no bonus below five");
        }
    }

    /// @notice 5..9 passes queue the entries of 6..10: one extra pass. Even award counts
    ///         (6, 8, 10) queue a dense ticket per pair on every standard level, odd ones
    ///         keep the every-2nd-level ticket, so the extra is the difference of shapes.
    function testFiveThroughNineOneBonusPass() public {
        for (uint256 q = 5; q <= 9; ++q) {
            address who = makeAddr(string.concat("one", vm.toString(q)));
            uint24 passLevel = _buy(who, q);
            uint256 extra = _checkSpan(who, passLevel, q);
            assertTrue(extra != 0, "one bonus pass adds entries");
            assertEq(extra, _spanTotal(passLevel, q + 1) - _spanTotal(passLevel, q), "extra = one pass' shape");
        }
    }

    function testTenThroughFourteenTwoBonusPasses() public {
        for (uint256 q = 10; q <= 14; ++q) {
            address who = makeAddr(string.concat("two", vm.toString(q)));
            uint24 passLevel = _buy(who, q);
            assertEq(_checkSpan(who, passLevel, q), _spanTotal(passLevel, q + 2) - _spanTotal(passLevel, q));
        }
    }

    /// @notice 100 passes queue as 120: level 1..9 carry 2,400 entries each, the standard
    ///         levels 60 whole tickets each (even award count, no strided leg).
    function testHundredPassesTwentyBonusPasses() public {
        address who = makeAddr("hundred");
        uint24 passLevel = _buy(who, 100);
        uint256 extra = _checkSpan(who, passLevel, 100);
        assertEq(_owedAt(1, who), 2_400, "intro level: 20 entries x 120 passes");
        assertEq(_owedAt(50, who), 240, "standard level: 60 whole tickets");
        assertEq(extra, _spanTotal(passLevel, 120) - _spanTotal(passLevel, 100), "twenty bonus passes queued densely");
    }

    /// @notice Span edges at level 0 (passLevel 1) for q = 5 (awarded as 6): the intro
    ///         window carries 120/level, standard levels 12 (three dense tickets), level 101
    ///         past the span stays empty.
    function testSpanEdgesAtLevelZero() public {
        address who = makeAddr("edges0");
        uint24 passLevel = _buy(who, 5);
        assertEq(passLevel, 1);
        assertEq(_owedAt(1, who), 120, "intro level: 20 x 6");
        assertEq(_owedAt(9, who), 120, "last intro level");
        assertEq(_owedAt(10, who), 12, "first standard level: 3 dense tickets");
        assertEq(_owedAt(11, who), 12, "no strided gap with an even award count");
        assertEq(_owedAt(100, who), 12, "last level of the span");
        assertEq(_owedAt(101, who), 0, "past the span");
    }

    /// @notice Past the intro window (level 51, passLevel 52) with q = 7 (awarded as 8):
    ///         four dense tickets on 52..151, nothing at 152.
    function testSpanEdgesPastIntroWindow() public {
        _setLevel(51);
        address who = makeAddr("edges51");
        uint24 passLevel = _buy(who, 7);
        assertEq(passLevel, 52);
        _checkSpan(who, passLevel, 7);
        assertEq(_owedAt(52, who), 16, "passLevel: 4 dense tickets");
        assertEq(_owedAt(151, who), 16, "passLevel+99: 4 dense tickets");
        assertEq(_owedAt(152, who), 0, "past the span");
        assertEq(_queueLenAt(151), 1, "buyer enqueued once on a far-future level");
    }

    /// @notice Two separate calls of 3 and 2 passes never qualify: the bonus is per call.
    function testSeparateCallsDoNotAccumulate() public {
        address who = makeAddr("split");
        uint24 passLevel = _buy(who, 3);
        _buy(who, 2);
        for (uint24 lvl = passLevel; lvl <= passLevel + 100; ++lvl) {
            assertEq(
                _owedAt(lvl, who),
                _paid(passLevel, lvl, 3) + _paid(passLevel, lvl, 2),
                "split buys carry only paid awards"
            );
        }
    }

    function testFuzzBonusEntriesTotal(uint256 q) public {
        q = bound(q, 1, 100);
        address who = makeAddr("fuzz");
        uint24 passLevel = _buy(who, q);
        uint256 extra = _checkSpan(who, passLevel, q);
        assertEq(extra, _spanTotal(passLevel, q + q / 5) - _spanTotal(passLevel, q), "extra = bonus passes' shape");
        if (q < 5) assertEq(extra, 0, "below five: nothing");
        else assertGe(extra, (q / 5) * 180, "each bonus pass adds at least its half-pass floor");
    }

    // ── nothing else scales with the stream ──────────────────────────────────

    function testBonusLeavesPriceFreezeLootboxAndCreditsOnPaidQuantity() public {
        address who = makeAddr("paidonly");
        uint256 price = WHALE_EARLY_PRICE * 5;
        vm.deal(who, price);
        vm.expectEmit(true, false, false, true, address(game));
        emit LootBoxBuy(who, 0, price / 10);
        vm.prank(who);
        game.purchaseWhalePass{value: price}(who, 5, bytes32(0));

        assertEq(game.afkingFundingOf(who), 0, "exact paid price, no excess");
        uint256 packed = game.mintPackedFor(who);
        uint24 frozen = uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
        assertEq(frozen, 100, "freeze covers the paid 100-level span only");
        uint24 levelCount = uint24((packed >> BitPackingLib.LEVEL_COUNT_SHIFT) & BitPackingLib.MASK_24);
        assertEq(levelCount, 100, "level count follows the paid span");
        (uint256 normal, uint256 high) = crapsBattle.passCreditsOf(who);
        assertEq(normal, 5, "one Craps credit per paid pass");
        assertEq(high, 0, "no high lane credit");
    }
}
