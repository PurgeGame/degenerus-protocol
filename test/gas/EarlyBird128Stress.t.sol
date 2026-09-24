// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DayOneFixture, DayOneSeeder} from "./JackpotDayOneWorstCase.t.sol";

contract HeroStressSeeder is DayOneSeeder {
    function setEarlyBirdFuture(uint128 amount) external {
        (uint128 next,) = _getPrizePools();
        _setPrizePools(next, amount);
    }
    function seedTailBuckets() external {
        uint8[4] memory traits = [uint8(61), 66, 161, 222];
        uint256[4] memory lengths = [uint256(513), 761, 1761, 561];
        for (uint8 q; q < 4; ++q) {
            _seedBucketDistinct(level + 1, traits[q], lengths[q], uint160(0x1000000000 + 0x800000 + uint256(q) * 0x100000));
            deityBySymbol[q * 8 + (traits[q] & 7)] = address(0);
        }
    }

    function seedHeroStress(uint256 prefix) external {
        // Preserve an older resolved-ticket marker. A fresh arm in stage 10 then exercises
        // both age checks without banning a hero quadrant on this draw.
        goldenTicket = (uint256(1) << 190) | (uint256(dailyIdx - 1) << 193);
        for (uint8 q; q < 4; ++q) {
            uint256 packed;
            for (uint8 s; s < 8; ++s) {
                uint8 idx = q * 8 + s;
                packed |= uint256(idx + 1) << (uint256(s) * 32);
                deityBySymbol[idx] = address(uint160(0xD0000000 + uint256(idx)));
            }
            dailyHeroWagers[dailyIdx][q] = packed;
        }
        for (uint256 i; i < prefix; ++i) {
            _queueEntries(address(uint160(0xE0000000 + i)), level + 1, 4, true);
        }
    }
}

abstract contract EarlyBird128StressFixture is DayOneFixture {
    // Searched deterministically using the exact production hashing and weighted-roll rules:
    // main hero index 31 and bonus hero index 30 force long weighted scans. Four
    // one-entry tails force 28 padding redraws, and all 128 recipients are distinct.
    uint256 internal constant WORD = 1790035;

    function prefix() internal pure virtual returns (uint256) { return 0; }
    function late() internal pure virtual returns (bool) { return false; }
    function futurePool() internal pure virtual returns (uint128) { return 1000 ether; }

    function setUp() public {
        _deployProtocol();
        _warpToDay(400, 3 hours);
        bytes memory realCode = address(game).code;
        vm.etch(address(game), type(HeroStressSeeder).runtimeCode);
        uint8[4] memory mainTraits = [uint8(59), 121, 189, 255];
        uint8[4] memory bonusTraits = [uint8(61), 66, 161, 222];
        HeroStressSeeder(payable(address(game))).seedDayOne(
            LVL, WORD, mainTraits, bonusTraits, BASE, ETH_HOLDERS, 0, false
        );
        HeroStressSeeder(payable(address(game))).seedHeroStress(prefix());
        HeroStressSeeder(payable(address(game))).seedTailBuckets();
        HeroStressSeeder(payable(address(game))).setEarlyBirdFuture(futurePool());
        vm.etch(address(game), realCode);
        vm.deal(address(game), uint256(futurePool()) + 10_000 ether);
        game.advanceGame();
        if (late()) _warpToDay(401, 3 hours);
    }

    function test_EarlyBird128ColdHeroAndPartialSourceWords() public {
        vm.recordLogs();
        uint256 g0 = gasleft();
        game.advanceGame();
        uint256 used = g0 - gasleft();
        emit log_named_uint("EARLY_BIRD_128_HERO_TAIL_COLD_WORDS", used);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[128] memory sourceWords;
        address[128] memory recipients;
        uint256 count;
        uint256 uniqueSourceWords;
        uint256[4] memory quadrantCounts;
        uint256 advanceEvents;
        uint256 passEvents;
        address passWinner;
        uint256 halfPasses;
        for (uint256 i; i < logs.length; ++i) {
            bytes32 sig = logs[i].topics[0];
            assertTrue(sig != ETH_WIN_SIG && sig != GOLDEN_WIN_SIG && sig != GOLDEN_ARMED_SIG);
            if (sig == ADVANCE_SIG) {
                (uint8 stage,) = abi.decode(logs[i].data, (uint8, uint24));
                assertEq(stage, STAGE_JACKPOT_EARLY_BIRD_TICKETS);
                ++advanceEvents;
            }
            if (sig == WHALE_PASS_SIG) {
                uint8 source;
                (halfPasses, source) = abi.decode(logs[i].data, (uint256, uint8));
                assertEq(source, 4);
                passWinner = address(uint160(uint256(logs[i].topics[1])));
                ++passEvents;
            }
            if (logs[i].topics[0] != TICKET_WIN_SIG) continue;
            uint256 trait = uint256(logs[i].topics[3]);
            address recipient = address(uint160(uint256(logs[i].topics[1])));
            (uint32 entries, uint24 sourceLevel, uint256 index,) =
                abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
            assertEq(entries, futurePool() == 1000 ether ? 20 : 180);
            assertEq(sourceLevel, LVL + 1);
            assertTrue(index != type(uint256).max, "every draw must read a real owner's source slot");
            uint256 key = (trait << 32) | (index >> 3);
            for (uint256 j; j < count; ++j) {
                assertTrue(recipients[j] != recipient, "all recipients must be distinct and cold");
            }
            recipients[count] = recipient;
            bool seenWord;
            for (uint256 j; j < count; ++j) if (sourceWords[j] == key) seenWord = true;
            if (!seenWord) ++uniqueSourceWords;
            sourceWords[count++] = key;
            ++quadrantCounts[trait >> 6];
        }
        assertEq(count, 128);
        assertEq(uniqueSourceWords, 44, "four one-entry tails force 28 padding redraws plus 16 group words");
        assertEq(advanceEvents, 1);
        if (futurePool() != 1000 ether) {
            assertEq(passEvents, 1, "one aggregate pass award");
            uint256 budget = uint256(futurePool()) * 3 / 100;
            assertEq(halfPasses, ((budget - 128 * 45 * 0.04 ether) / 4.5 ether) * 2);
            assertEq(game.whalePassClaimAmount(passWinner), halfPasses);
            assertGt(uint160(passWinner), BASE + 0x800000);
            assertLe(uint160(passWinner), BASE + 0x800000 + 513, "gold trait wins");
            for (uint256 i; i < count; ++i) assertTrue(recipients[i] != passWinner, "fresh recipient outside ticket winners");
        } else assertEq(passEvents, 0);
        for (uint256 q; q < 4; ++q) assertEq(quadrantCounts[q], 32);
        assertLt(used, GAS_TARGET);
    }
}

contract EarlyBird128StressEmptyQueue is EarlyBird128StressFixture {}
contract EarlyBird128StressPartialQueue is EarlyBird128StressFixture {
    function prefix() internal pure override returns (uint256) { return 1; }
}
contract EarlyBird128StressEmptyQueueLate is EarlyBird128StressFixture {
    function late() internal pure override returns (bool) { return true; }
}
contract EarlyBird128StressPartialQueueLate is EarlyBird128StressFixture {
    function prefix() internal pure override returns (uint256) { return 1; }
    function late() internal pure override returns (bool) { return true; }
}

contract EarlyBird128StressWhale is EarlyBird128StressFixture {
    function futurePool() internal pure override returns (uint128) { return 10_000 ether; }
}
contract EarlyBird128StressWhaleLate is EarlyBird128StressFixture {
    function futurePool() internal pure override returns (uint128) { return 10_000 ether; }
    function prefix() internal pure override returns (uint256) { return 1; }
    function late() internal pure override returns (bool) { return true; }
}
contract EarlyBird128StressWhaleLarge is EarlyBird128StressFixture {
    function futurePool() internal pure override returns (uint128) { return 1_000_000 ether; }
}
