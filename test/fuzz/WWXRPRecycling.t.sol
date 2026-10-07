// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Only the draw's external dependencies are mocked. The token, bucket hash,
///      entry book, claim gates and payment dispatch are the production code.
contract WwxrpRecyclingGameMock {
    mapping(uint24 => uint256) public rngWordForDay;
    mapping(address => uint256) public playerActivityScore;
    uint24 public level;
    function setWord(uint24 day, uint256 word) external { rngWordForDay[day] = word; }
    function setActivity(address player, uint256 score) external { playerActivityScore[player] = score; }
    mapping(address => uint32) public walletIdOf;
    function setId(address player, uint32 id) external { walletIdOf[player] = id; }
    function playerActivityScoreCached(address player) external view returns (uint256, uint32) {
        return (playerActivityScore[player], walletIdOf[player]);
    }
    function setLevel(uint24 value) external { level = value; }
    function extsload(bytes32) external pure returns (bytes32) { return bytes32(0); }
}

contract WwxrpRecyclingCoinflipMock {
    mapping(uint32 => uint256) public credited;
    uint256 public totalCredited;
    function creditFlip(uint32 id, uint256 amount) external {
        credited[id] += amount;
        totalCredited += amount;
    }
}

contract WWXRPRecyclingTest is Test {
    WWXRP private token;
    WwxrpRecyclingGameMock private game;
    WwxrpRecyclingCoinflipMock private coinflip;

    function setUp() public {
        vm.etch(ContractAddresses.GAME, type(WwxrpRecyclingGameMock).runtimeCode);
        vm.etch(ContractAddresses.COINFLIP, type(WwxrpRecyclingCoinflipMock).runtimeCode);
        game = WwxrpRecyclingGameMock(ContractAddresses.GAME);
        coinflip = WwxrpRecyclingCoinflipMock(ContractAddresses.COINFLIP);
        token = new WWXRP();
        _day(2);
    }

    function _day(uint24 day) private {
        vm.warp((uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + day - 1) * 1 days + 82620);
    }

    function _actor(uint24 day, uint8 bucket, uint256 salt) private returns (address player) {
        for (uint256 i = salt + 1; ; ++i) {
            uint32 id = uint32(i);
            if (token.bucketOf(day, id) != bucket) continue;
            player = address(uint160(uint256(keccak256(abi.encode(day, bucket, id)))));
            game.setId(player, id);
            return player;
        }
    }

    function _id(address player) private view returns (uint32) {
        return game.walletIdOf(player);
    }

    function _mint(address player, uint256 amount) private {
        vm.prank(ContractAddresses.GAME);
        token.mintPrize(player, amount);
    }

    function _enter(address player, uint256 amount) private {
        _mint(player, amount);
        vm.prank(player);
        token.enter(0, amount);
    }

    function _hash(bytes32 domain, uint24 day, uint256 word) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(domain, address(token), day, word)));
    }

    function _winningWord(uint24 day, uint8 bucket) private view returns (uint256 word) {
        for (word = 1; ; ++word) {
            if (_hash("WWXRP_DRAW_BIG", day, word) % 365 != 0
                && _hash("WWXRP_DRAW_SMALL", day, word) % 30 == 0
                && _hash("WWXRP_DRAW_WIN_BUCKET", day, word) % 10 == bucket) return word;
        }
    }

    function _assertEmpty(uint24 day, uint8 bucket, uint32 index) private view {
        (uint256 raw, uint256 total, uint32 count) = token.bucketInfo(day, bucket);
        assertEq(raw, 0);
        assertEq(total, 0);
        assertEq(count, 0);
        (uint32 player, uint256 endpoint) = token.entryAt(day, bucket, index);
        assertEq(player, 0);
        assertEq(endpoint, 0);
    }

    function test_ClaimsStayOpenThroughSecondDayAndCloseAtReuse() public {
        address player = _actor(2, 0, 0);
        _enter(player, 50);
        game.setWord(3, _winningWord(2, 0));
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        token.claim(2, 0);
        _day(3);
        (bool available, bool prize,,,,,) = token.previewOutcome(2);
        assertTrue(available && prize);
        uint256 snapshot = vm.snapshotState();
        token.claim(2, 0);
        assertEq(coinflip.credited(_id(player)), 10_000);
        vm.expectRevert(WWXRP.AlreadyClaimed.selector);
        token.claim(2, 0);
        assertTrue(vm.revertToState(snapshot));
        _day(4);
        // Both newer banks may be populated without affecting day 2's last claim day.
        _enter(_actor(4, 0, 0), 75);
        token.claim(2, 0);
        assertEq(coinflip.credited(_id(player)), 10_000);
        _day(5);
        _enter(_actor(5, 0, 0), 100);
        _assertEmpty(2, 0, 0);
        assertTrue(token.dayClaimed(2), "claimed history survives reuse");
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        token.claim(2, 0);
        assertEq(coinflip.totalCredited(), 10_000);
    }

    function test_VrfStallCannotPayExpiredDrawOrNewDrawWithOldWord() public {
        _enter(_actor(2, 0, 0), 50);
        _day(5);
        address next = _actor(5, 0, 0);
        _enter(next, 75);
        _day(6);
        game.setWord(3, _winningWord(2, 0));
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        token.claim(2, 0);
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        token.claim(5, 0);
        assertEq(coinflip.totalCredited(), 0);
        game.setWord(6, _winningWord(5, 0));
        token.claim(5, 0);
        assertEq(coinflip.credited(_id(next)), 10_000);
        assertFalse(token.dayClaimed(2));
    }

    function test_ShorterReplacementHidesTailAndRejectsItsClaims() public {
        address previous = _actor(2, 0, 0);
        for (uint256 i; i < 4; ++i) _enter(previous, 100);
        _day(5);
        address next = _actor(5, 0, 0);
        _enter(next, 25);
        (uint32 tail, uint256 endpoint) = token.entryAt(5, 0, 1);
        assertEq(tail, 0);
        assertEq(endpoint, 0);
        _assertEmpty(2, 0, 3);
        _day(6);
        game.setWord(6, _winningWord(5, 0));
        vm.expectRevert(WWXRP.EntryMissing.selector);
        token.claim(5, 1);
        (bool found, uint32 index, uint32 winner) = token.findWinningEntry(5);
        assertTrue(found);
        assertEq(index, 0);
        assertEq(winner, _id(next));
        token.claim(5, index);
        assertEq(coinflip.credited(_id(previous)), 0);
        assertEq(coinflip.credited(_id(next)), 10_000);
    }

    function test_AllReadersRejectWrongDayTagWithinClaimWindow() public {
        _enter(_actor(2, 0, 0), 50);
        _day(6); // day 5 is open, but the physical bank still belongs to day 2.
        game.setWord(6, _winningWord(5, 0));
        _assertEmpty(5, 0, 0);
        (bool available, bool prize,,,, uint256 total,) = token.previewOutcome(5);
        assertTrue(available);
        assertFalse(prize);
        assertEq(total, 0);
        (bool found,, uint32 winner) = token.findWinningEntry(5);
        assertFalse(found);
        assertEq(winner, 0);
        vm.expectRevert(WWXRP.EmptyWinningBucket.selector);
        token.claim(5, 0);
        assertEq(coinflip.totalCredited(), 0);
    }

    function test_BanksAndBucketsDoNotAliasAndDayZeroIsEmpty() public {
        for (uint24 day = 1; day <= 3; ++day) {
            _day(day);
            for (uint8 bucket; bucket < 10; ++bucket) _enter(_actor(day, bucket, 0), 25 + day);
        }
        _assertEmpty(0, 0, 0);
        _day(4);
        _enter(_actor(4, 4, 0), 100);
        for (uint24 day = 1; day <= 3; ++day) {
            for (uint8 bucket; bucket < 10; ++bucket) {
                if (day == 1 && bucket == 4) _assertEmpty(day, bucket, 0);
                else {
                    (uint256 raw,, uint32 count) = token.bucketInfo(day, bucket);
                    assertEq(raw, 25 + day);
                    assertEq(count, 1);
                }
            }
        }
    }

    function test_MaximumDayTagAndCountAreIndependent() public {
        uint24 day = type(uint24).max;
        _day(day);
        address player = _actor(day, 0, 0);
        _enter(player, 25);
        _enter(player, 25);
        (uint256 raw, uint256 total, uint32 count) = token.bucketInfo(day, 0);
        assertEq(raw, 50);
        assertEq(total, 50);
        assertEq(count, 2);
        _assertEmpty(0, 0, 0);
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        token.claim(day, 0);
    }

    function test_SaturationAndCountOverflowSurviveRecycling() public {
        address previous = _actor(2, 0, 0);
        _enter(previous, type(uint256).max);
        _enter(previous, 25);
        (uint256 raw, uint256 total, uint32 count) = token.bucketInfo(2, 0);
        assertEq(raw, type(uint96).max);
        assertEq(total, type(uint96).max);
        assertEq(count, 2);
        _day(3);
        game.setWord(3, _winningWord(2, 0));
        vm.expectRevert(WWXRP.NotWinningEntry.selector);
        token.claim(2, 1);
        _day(5);
        address next = _actor(5, 0, 0);
        _enter(next, 25);
        (raw, total, count) = token.bucketInfo(5, 0);
        assertEq(raw, 25);
        assertEq(total, 25);
        assertEq(count, 1);
        bytes32 headerSlot = keccak256(abi.encode(uint256(2) << 8, uint256(3)));
        uint256 header = uint256(vm.load(address(token), headerSlot));
        vm.store(address(token), headerSlot, bytes32(header | (uint256(type(uint32).max) << 192)));
        _mint(next, 25);
        vm.expectRevert(WWXRP.ScoreOverflow.selector);
        vm.prank(next);
        token.enter(0, 25);
        assertEq(token.balanceOf(next), 25, "overflow must not burn");
    }

    function test_IncineratorBookDoesNotRecycleWithDailyBook() public {
        game.setLevel(99);
        _enter(_actor(2, 0, 0), 100);
        _day(5);
        _enter(_actor(5, 0, 0), 200);
        (uint256 total, uint32 count) = token.incineratorInfo(100);
        assertEq(total, 300);
        assertEq(count, 2);
        (, uint256 first) = token.incineratorEntryAt(100, 0);
        assertEq(first, 100);
    }

    function testFuzz_ReusedBankStartsFreshAndHidesAllRetiredEntries(
        uint24 daySeed, uint8 gapSeed, uint8 oldCountSeed, uint8 newCountSeed, uint8 bucketSeed
    ) public {
        uint24 day = uint24(bound(daySeed, 1, type(uint24).max - 768));
        uint24 nextDay = day + 3 * (uint24(gapSeed) + 1);
        uint8 bucket = bucketSeed % 10;
        uint32 oldCount = uint32(oldCountSeed % 8) + 1;
        uint32 newCount = uint32(newCountSeed % 8) + 1;
        _day(day);
        address previous = _actor(day, bucket, 0);
        for (uint32 i; i < oldCount; ++i) _enter(previous, 100);
        _day(nextDay);
        address next = _actor(nextDay, bucket, 0);
        for (uint32 i; i < newCount; ++i) _enter(next, 25);
        (uint256 raw, uint256 total, uint32 count) = token.bucketInfo(nextDay, bucket);
        assertEq(raw, 25 * uint256(newCount));
        assertEq(total, raw);
        assertEq(count, newCount);
        for (uint32 i; i < oldCount; ++i) _assertEmpty(day, bucket, i);
        for (uint32 i; i < 9; ++i) {
            (uint32 player, uint256 endpoint) = token.entryAt(nextDay, bucket, i);
            assertEq(player, i < newCount ? _id(next) : 0);
            assertEq(endpoint, i < newCount ? (uint256(i) + 1) * 25 : 0);
        }
    }
}
