// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {BucketSeed} from "../helpers/BucketSeed.sol";
import {JackpotBucketLib} from "../../contracts/libraries/JackpotBucketLib.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract EarlyBirdWhaleHarness is DegenerusGameJackpotModule, BucketSeed {
    function price(uint24 target, uint256 budget, uint256 word, bool turbo) external {
        level = target - 1;
        dailyIdx = 100;
        jackpotPhaseFlag = true;
        jackpotCounter = 0;
        jackpotFlags = turbo ? JACKPOT_TURBO : 0;
        rngLockedFlag = true;
        goldenTicket = 0;
        _setCurrentPrizePool(10 ether);
        _setPrizePools(20 ether, uint128((budget * 100 + 2) / 3));
        this.payDailyJackpot(true, level, word);
    }

    function seed(uint24 target, uint8 trait, address who, uint256 n) external {
        _seedBucket(target, trait, who, n);
    }
    function seedDistinct(uint24 target, uint8 trait, uint256 n, uint160 base) external {
        _seedBucketDistinct(target, trait, n, base);
    }
    function deity(uint8 trait, address who) external { deityBySymbol[(trait >> 6) * 8 + (trait & 7)] = who; }
    function latch(uint256 entries, uint256 halves) external {
        dailyTicketBudgetsPacked = (dailyTicketBudgetsPacked & ((uint256(1) << 144) - 1)) | (entries << 144);
        earlyBirdWhalePasses = halves;
    }
    function pending() external view returns (uint256) { return earlyBirdWhalePasses; }
    function packed() external view returns (uint256) { return dailyTicketBudgetsPacked; }
    function pools() external view returns (uint128, uint128) { return _getPrizePools(); }
    function liability() external view returns (uint256) { return claimablePool; }
    function passes(address who) external view returns (uint256) { return whalePassClaims[who]; }
    function unlock() external { rngLockedFlag = false; }
    function creditPasses(address who, uint256 halves) external { whalePassClaims[who] += halves; }
    function owed(uint24 target, address who) external view returns (uint256) {
        uint24 key = target > _mintCeiling() ? _tqFarFutureKey(target) : _tqWriteKey(target);
        return uint32(_entriesOwed(key, who) >> 8);
    }
    function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        return _pickSoloQuadrant(traits, entropy);
    }
}

contract EarlyBirdWhalePassTest is Test {
    bytes32 private constant PASS = keccak256("JackpotWhalePassWin(address,uint256,uint8)");
    bytes32 private constant TICKET = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    EarlyBirdWhaleHarness private h;
    uint24 private constant TARGET = 10;
    uint256 private constant FULL_PASS = 4.5 ether;

    struct Awards {
        address winner;
        uint256 halves;
        uint256 passEvents;
        uint256 slots;
        uint256 entries;
        bytes32 fingerprint;
    }

    function setUp() public {
        vm.warp(101 days);
        h = new EarlyBirdWhaleHarness();
        vm.etch(ContractAddresses.GAME_WHALE_MODULE, address(new DegenerusGameWhaleModule()).code);
    }

    function _traits(uint256 word) private pure returns (uint8[4] memory) {
        return JackpotBucketLib.getRandomTraits(word);
    }

    function _seed(uint256 word, uint8 active, bool oneWallet) private {
        uint8[4] memory traits = _traits(word);
        for (uint8 q; q < 4; ++q) {
            if (active & (1 << q) != 0) h.seed(TARGET, traits[q], address(uint160(oneWallet ? 0xA000 : 0xA000 + q)), 8);
        }
    }

    function _draw(uint256 word, uint256 entriesEach) private returns (Awards memory a) {
        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == PASS) {
                a.winner = address(uint160(uint256(logs[i].topics[1])));
                uint8 source;
                (a.halves, source) = abi.decode(logs[i].data, (uint256, uint8));
                assertEq(source, 4, "early-bird event source");
                ++a.passEvents;
            } else if (logs[i].topics[0] == TICKET) {
                (uint32 entries, uint24 source, uint256 index,) = abi.decode(logs[i].data, (uint32, uint24, uint256, bool));
                assertEq(entries, entriesEach, "equal whole-ticket prize per slot");
                a.entries += entries;
                ++a.slots;
                a.fingerprint = keccak256(abi.encode(a.fingerprint, logs[i].topics, source, index));
            }
        }
    }

    function _checkPrice(uint24 target, uint256 budget) private {
        h.price(target, budget, 12345, false);
        uint256 p = PriceLookupLib.priceForLevel(target);
        uint256 tickets = budget / p;
        uint256 n = tickets < 128 ? tickets : 128;
        if (n >= 8) n = n / 8 * 8;
        uint256 passes;
        if (n != 0 && tickets / n > 45) passes = (budget - n * 45 * p) / FULL_PASS;
        uint256 entries = passes == 0 ? budget * 4 / p : n * 180;
        assertEq(uint64(h.packed() >> 144), entries, "pricing latch");
        assertEq(h.pending(), passes * 2, "full passes only");
        (uint128 next, uint128 future) = h.pools();
        uint256 initialFuture = (budget * 100 + 2) / 3;
        assertEq(future, initialFuture - budget, "full 3% debit stays in next");
        uint256 dailyEntries = uint64(h.packed() >> 8);
        uint256 dailyBudget = uint256(next) - 20 ether - budget;
        assertGe(dailyBudget, dailyEntries * (p / 4));
        assertLt(dailyBudget, (dailyEntries + 1) * (p / 4));
        assertEq(h.liability(), 0, "no cash liability from conversion");
    }

    function test_thresholdsAtEveryPriceTier() public {
        uint24[7] memory targets = [uint24(2), 5, 10, 30, 60, 90, 100];
        for (uint256 i; i < targets.length; ++i) {
            uint256 p = PriceLookupLib.priceForLevel(targets[i]);
            uint256 threshold = 46 * 128 * p;
            uint256 passFloor = 45 * 128 * p + FULL_PASS;
            if (passFloor > threshold) threshold = passFloor;
            _checkPrice(targets[i], threshold - 1);
            assertEq(h.pending(), 0);
            _checkPrice(targets[i], threshold);
            assertGt(h.pending(), 0);
            _checkPrice(targets[i], threshold + 1);
            _checkPrice(targets[i], 45 * 128 * p);
            assertEq(h.pending(), 0, "gate resets after a smaller draw");
        }
    }

    function testFuzz_exactBudgetAndPoolConservation(uint8 tier, uint96 amount) public {
        uint24[7] memory targets = [uint24(2), 5, 10, 30, 60, 90, 100];
        _checkPrice(targets[tier % 7], bound(uint256(amount), 0, 1_000_000 ether));
    }

    function test_surplusUsesExactWeiIncludingOriginalDust() public {
        // Target 2 (live `level` = 1, the smallest level that ever reaches its own jackpot
        // phase) still sits in the 0.01 ETH intro tier. At that price, 62.10 ETH buys one
        // pass after reserving 45 per slot; the old equal-slot awards used only 61.44 ETH
        // (48 tickets each).
        _checkPrice(2, 62.10 ether);
        assertEq(h.pending(), 2);
        _checkPrice(2, 62.10 ether - 1);
        assertEq(h.pending(), 0, "retain 48 tickets until a whole pass fits");
        _checkPrice(TARGET, 234.90 ether);
        assertEq(h.pending(), 0, "rounding dust alone cannot trigger at 45 each");
    }

    function test_convertedDrawPreservesRecipientsPoolsAndOtherLatches() public {
        uint256 word = 1337;
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, false);
        uint256 packed = h.packed();
        (uint128 next, uint128 future) = h.pools();
        uint256 liability = h.liability();
        uint256 snap = vm.snapshotState();
        Awards memory capped = _draw(word, 180);
        assertEq(capped.slots, 128);
        assertEq(capped.passEvents, 1);
        assertEq(capped.halves, 10);
        assertEq(h.passes(capped.winner), 10);
        assertEq(h.pending(), 0);
        assertEq(h.packed(), packed & ((uint256(1) << 144) - 1));
        (uint128 nextAfter, uint128 futureAfter) = h.pools();
        assertEq(nextAfter, next);
        assertEq(futureAfter, future);
        assertEq(h.liability(), liability);
        Awards memory replay = _draw(word, 0);
        assertEq(replay.slots + replay.passEvents, 0, "no duplicate settlement");
        assertTrue(vm.revertToState(snap));
        h.latch(256 ether * 4 / 0.04 ether, 0);
        Awards memory ordinary = _draw(word, 200);
        assertEq(ordinary.fingerprint, capped.fingerprint, "same ticket recipients and source indices");
    }

    function test_duplicateWalletKeepsEveryTicketSlot() public {
        uint256 word = 1337;
        _seed(word, 15, true);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        assertEq(a.slots, 128);
        assertEq(h.owed(TARGET, address(0xA000)), 128 * 180);
        assertEq(a.winner, address(0xA000));
        assertEq(h.passes(a.winner), 10);
    }

    function testFuzz_goldPreferenceAndEmptyFallback(uint256 word, uint8 mask) public {
        mask &= 15;
        uint8[4] memory traits = _traits(word);
        uint8 solo = _soloQuadrant(word);
        _seed(word, mask, false);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        if (mask == 0) {
            assertEq(a.slots + a.passEvents, 0);
            assertEq(h.pending(), 0, "empty draw consumes the latch");
            return;
        }
        assertEq(a.slots, 128);
        assertEq(a.passEvents, 1);
        assertEq(a.halves, 10);
        uint256 chosen = uint160(a.winner) - 0xA000;
        assertLt(chosen, 4);
        assertTrue(mask & (1 << chosen) != 0, "selected bucket is active");
        // The solo quadrant is skipped by the draw entirely, gold or not, unless it is the
        // only active bucket (the mask has no other bit set).
        uint8 nonSoloMask = mask & ~uint8(1 << solo);
        if (nonSoloMask == 0) {
            assertEq(chosen, solo, "the solo quadrant is the only active bucket, so it still wins");
            return;
        }
        assertTrue(chosen != solo, "the solo quadrant never wins while another bucket is active");
        uint8 activeGold;
        for (uint8 q; q < 4; ++q) if (nonSoloMask & (1 << q) != 0 && ((traits[q] >> 3) & 7) == 7) activeGold |= uint8(1 << q);
        if (activeGold != 0) assertTrue(activeGold & (1 << chosen) != 0, "eligible gold always wins");
        uint8 candidates = activeGold != 0 ? activeGold : nonSoloMask;
        uint8[] memory quadrants = new uint8[](4);
        uint256 count;
        for (uint8 q; q < 4; ++q) if (candidates & (1 << q) != 0) quadrants[count++] = q;
        uint256 root = uint256(keccak256(abi.encode(word, keccak256("early-bird-whale"), uint256(100), uint256(TARGET))));
        assertEq(chosen, quadrants[root % count], "equal choice among eligible preferred buckets");
    }

    function test_deityOnlyGoldIsEligible() public {
        uint256 word;
        uint8[4] memory traits;
        uint8 goldQ;
        // _pickSoloQuadrant always prefers a gold quadrant when one exists, so a board with
        // exactly ONE gold quadrant always has that quadrant AS the solo pick (covered
        // separately by test_surplusWhalePassSkipsSoloEvenWhenItIsTheOnlyGoldQuadrant): a
        // deity-only-gold fixture needs a SECOND gold quadrant, so the non-solo one is still
        // an eligible (and the only eligible) gold candidate.
        while (true) {
            traits = _traits(word);
            uint8 goldCount;
            uint8[4] memory golds;
            for (uint8 q; q < 4; ++q) {
                if (((traits[q] >> 3) & 7) == 7) { golds[goldCount] = q; ++goldCount; }
            }
            if (goldCount == 2) {
                // Gold is always preferred, so the solo pick is one of these two.
                uint8 solo = _soloQuadrant(word);
                goldQ = golds[0] == solo ? golds[1] : golds[0];
                break;
            }
            ++word;
        }
        _seed(word, uint8(15 ^ (1 << goldQ)), false);
        address goldDeity = address(0xD00D);
        h.deity(traits[goldQ], goldDeity);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        assertEq(a.winner, goldDeity);
        assertEq(a.halves, 10);
    }

    function testFuzz_passWinnerIndependentOfAwardAmount(uint256 word) public {
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, false);
        Awards memory first = _draw(word, 180);
        h.price(TARGET, 512 ether, word, false);
        Awards memory second = _draw(word, 180);
        assertEq(first.winner, second.winner);
        assertEq(first.halves, 10);
        assertEq(second.halves, 124);
        assertEq(first.fingerprint, second.fingerprint);
    }

    function testFuzz_freshEntryDrawRetainsRealAndDeityWeights(uint256 word) public {
        uint8 trait = _traits(word)[0];
        h.seedDistinct(TARGET, trait, 64, 0x100000);
        address deity = address(0xD00D);
        h.deity(trait, deity);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        uint256 root = uint256(keccak256(abi.encode(word, keccak256("early-bird-whale"), uint256(100), uint256(TARGET))));
        uint256 virtuals = ((trait >> 3) & 7) >= 5 ? 1 : 2;
        uint256 index = uint256(keccak256(abi.encode(root, uint256(1)))) % (64 + virtuals);
        address expected = index < 64 ? address(uint160(0x100001 + index)) : deity;
        assertEq(a.winner, expected, "fresh entry-weighted sample including virtual deity entries");
        assertEq(a.passEvents, 1);
        assertEq(a.halves, 10);
    }

    // -- solo-quadrant exclusion (main board) ----------------------------------

    /// @dev The ETH leg's own solo-quadrant pick, off the day's main board and the storage
    ///      level (not lvl + 1): the same value payEarlyBirdTickets feeds both the ticket
    ///      draw's exclusion and the surplus whale pass.
    function _soloQuadrant(uint256 word) private view returns (uint8) {
        return h.pickSoloQuadrant(_traits(word), EntropyLib.hash2(word, uint256(TARGET - 1)));
    }

    function test_earlyBirdTicketsNeverLandInTheSoloQuadrantUnlessItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, false);
        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != TICKET) continue;
            uint256 q = uint256(logs[i].topics[3]) >> 6;
            assertTrue(q != solo, "early-bird tickets exclude the day's solo ETH quadrant");
            ++n;
        }
        assertGt(n, 0, "tickets were actually drawn");
    }

    function test_earlyBirdTicketsUseTheSoloQuadrantWhenItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, uint8(1 << solo), false);
        h.price(TARGET, 256 ether, word, false);
        vm.recordLogs();
        h.payEarlyBirdTickets(word);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 n;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != TICKET) continue;
            uint256 q = uint256(logs[i].topics[3]) >> 6;
            assertEq(q, solo, "the only active bucket is the solo quadrant, so it still wins");
            ++n;
        }
        assertGt(n, 0, "tickets were actually drawn from the fallback bucket");
    }

    function test_surplusWhalePassNeverLandsInSoloQuadrantUnlessItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        assertEq(a.passEvents, 1, "surplus pass still awarded");
        uint256 chosen = uint160(a.winner) - 0xA000;
        assertLt(chosen, 4, "winner drawn from a seeded quadrant wallet");
        assertTrue(chosen != solo, "the pass winner is never the solo quadrant when others are active");
    }

    function test_surplusWhalePassFallsBackToSoloQuadrantWhenItIsTheOnlyActiveBucket() public {
        uint256 word = 1337;
        uint8 solo = _soloQuadrant(word);
        _seed(word, uint8(1 << solo), false);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        assertEq(a.passEvents, 1, "the pass still pays when the solo bucket is the only one active");
        assertEq(a.winner, address(uint160(0xA000 + solo)), "falls back to the solo quadrant");
    }

    /// @dev Gold preference must not pull the winner into the solo quadrant even when the solo
    ///      quadrant is the board's ONLY gold one: the solo skip in _drawWhalePassWinner runs
    ///      before the gold-preference reset, so the other three (non-gold) quadrants remain
    ///      the candidate pool.
    function test_surplusWhalePassSkipsSoloEvenWhenItIsTheOnlyGoldQuadrant() public {
        uint256 word;
        uint8[4] memory traits;
        uint8 solo;
        uint8 goldQ;
        while (true) {
            traits = _traits(word);
            uint8 goldCount;
            for (uint8 q; q < 4; ++q) if (((traits[q] >> 3) & 7) == 7) { ++goldCount; goldQ = q; }
            solo = _soloQuadrant(word);
            if (goldCount == 1 && goldQ == solo) break;
            ++word;
        }
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, false);
        Awards memory a = _draw(word, 180);
        uint256 chosen = uint160(a.winner) - 0xA000;
        assertTrue(chosen != solo, "gold preference does not pull the winner into the solo quadrant");
    }

    function test_turboAndDeferredClaimAggregatesExistingPasses() public {
        uint256 word = 1337;
        _seed(word, 15, false);
        h.price(TARGET, 256 ether, word, true);
        Awards memory a = _draw(word, 180);
        h.creditPasses(a.winner, 2);
        bytes memory original = address(h).code;
        bytes memory whaleCode = address(new DegenerusGameWhaleModule()).code;
        vm.etch(address(h), whaleCode);
        vm.expectRevert(bytes4(keccak256("RngLocked()")));
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.etch(address(h), original);
        assertEq(h.passes(a.winner), 12, "blocked claim retains all awards");
        h.unlock();
        vm.etch(address(h), whaleCode);
        vm.warp(132 days);
        vm.expectRevert(bytes4(keccak256("GameOver()")));
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.warp(101 days);
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.expectRevert();
        DegenerusGameWhaleModule(payable(address(h))).claimWhalePass(a.winner);
        vm.etch(address(h), original);
        assertEq(h.passes(a.winner), 0);
        // 12 half-pass units grant 12 entries at each of 100 levels. Existing
        // immediate tickets at TARGET are separate; inspect the later 99 levels.
        for (uint24 l = TARGET + 1; l < TARGET + 100; ++l) assertEq(h.owed(l, a.winner), 12);
    }
}
